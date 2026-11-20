-- ForeverPilot / Logic/PriceProvider.lua
--
-- One answer to "what does this item cost?", with the honest caveat attached.
--
-- Source order, best first:
--   1. Auctionator's stable API (GetAuctionPriceByItemID / ByItemLink). Only
--      those two plus MultiSearch are documented as stable, so only those are
--      called without a guard.
--   2. Observed market prices sitting in another addon's SavedVariables.
--   3. A vendor price we recorded ourselves at a merchant, or one the optional
--      unstable Auctionator call gives us.
--   4. The item's own sell price scaled up - a weak estimate, labelled as one.
--   5. Nothing. The card then says "цена неизвестна" rather than guessing.
--
-- With Auctionator switched off entirely the addon keeps working: prices simply
-- degrade to UNKNOWN or ESTIMATE and the ranking stops using them as evidence.
local ADDON, ns = ...

local U = ns.Util
local Api = ns.Api
local CONF = ns.CONF

local Price = {}
ns.PriceProvider = Price

-- Vendors buy at a fraction of what they sell for; the usual markup is 4x the
-- item's own sell price. This is a heuristic, which is why it returns ESTIMATE.
Price.VENDOR_MARKUP = 4

Price.session = {}       -- itemID -> { copper, conf, age, src } for this recompute
-- Sell prices are memoised the same way the buy side already was. Without it
-- the history check below ran once per Margin call, and the profit branch calls
-- Margin for every learned recipe - two hundred of them on this character.
Price.sellSession = {}
-- Вендорный потолок - тоже один раз за пересчёт на предмет. Его спрашивают из
-- пяти денежных веток, и без памяти каждая стоила бы отдельного обращения к
-- кешу цен торговцев Auctionator (см. Price:Ceiling).
Price.ceilingSession = {}
-- И сам вопрос «сколько просит торговец» - тоже один раз: ветка перепродажи
-- задаёт его напрямую (Price:VendorCeiling), минуя решение выше, и без этой
-- памяти один предмет стоил двух обращений к кешу Auctionator за пересчёт.
Price.vendorAskSession = {}

local function blankStats()
    return { auctionator = 0, own = 0, foreign = 0, vendor = 0, estimate = 0, unknown = 0 }
end
Price.stats = blankStats()

function Price:BeginPass()
    self.session = {}
    self.sellSession = {}
    self.ceilingSession = {}
    self.vendorAskSession = {}
    self.stats = blankStats()
end

function Price:AuctionatorEnabled()
    return Api:AuctionatorPresent()
end

-- A number is a price only when it is strictly positive. Zero is what every
-- one of these sources returns for "I have nothing for this item", and treating
-- it as a price turns a missing listing into free materials.
local function copperOrNil(value)
    local n = tonumber(value)
    if n and n > 0 and n == n and n ~= math.huge then return n end
    return nil
end

-- Which sources are evidence that the item can actually be bought.
--   auctionator / own / foreign - someone listed it on the auction house
--   vendor                      - a merchant we stood in front of asks this
--   ledger                      - НАША СОБСТВЕННАЯ КНИГА ЗАКУПОК: игрок сам
--                                 заплатил эти деньги за этот предмет. Более
--                                 прямого доказательства «это можно купить»
--                                 не бывает вовсе.
-- "markup" is our own arithmetic on the item's sell price, and "vendorForeign"
-- is another addon's vendor number whose polarity (asking price or the vendor's
-- offer) we have not been able to verify. Neither proves anything is for sale.
Price.PROVEN_SOURCES = {
    auctionator = true, own = true, foreign = true, vendor = true,
    ledger = true,
}

-- ЧУЖИЕ ИСТОЧНИКИ. Числа из SavedVariables другого аддона: схема
-- недокументированная, обновляется он без нас, и лицензия не разрешает брать
-- данные (ns.FOREIGN_BOOK в Core/Const.lua). Нужны, пока своя книга пуста;
-- помечены, чтобы это было видно и в коде, и на экране.
Price.FOREIGN_SOURCES = { foreign = true, vendorForeign = true }

-- Какие маршруты ПОКУПКИ - это чьё-то объявление на аукционе, а не прилавок.
-- На стороне продажи те же два источника называются иначе (auction / foreign,
-- см. Price.MARKET_SELL_SOURCES), и смешивать перечни нельзя.
Price.BUY_MARKET_SOURCES = { auctionator = true, foreign = true }

function Price:IsForeignSource(src)
    return Price.FOREIGN_SOURCES[Price:BaseSource(src)] and true or false
end

-- НАСКОЛЬКО ИСТОЧНИК НАШ. Меньше - наш. Решает только при РАВНЫХ числах;
-- какая цена дешевле, этот порядок не меняет.
Price.SOURCE_RANK = {
    ledger = 1,        -- своя книга: игрок сам платил
    own = 2,           -- своё наблюдение у торговца
    vendor = 3,        -- торговец, перед которым мы стояли
    auctionator = 4,   -- чужой аддон, но схема у него документированная
    auction = 4,
    foreign = 5,       -- чужая книга закупок
    vendorForeign = 6,
    markup = 7,        -- наша же арифметика по цене продажи
}

function Price:SourceRank(src)
    return Price.SOURCE_RANK[Price:BaseSource(src)] or 9
end

-- ВЕНДОРНЫЙ ПОТОЛОК ------------------------------------------------------
--
-- ЦЕНА ТОРГОВЦА С НЕОГРАНИЧЕННЫМ ЗАПАСОМ - ЭТО ПОТОЛОК, А НЕ ЕЩЁ ОДИН ИСТОЧНИК.
--
-- Полка не кончается и не торгуется, поэтому заплатить за материал больше, чем
-- он на ней стоит, нельзя «по невезению» - только по незнанию. Значит ответ на
-- вопрос «сколько это стоит купить» ограничен сверху этой ценой, и ограничен
-- ЗДЕСЬ, в единственном месте, где этот вопрос вообще задаётся. Игрок уже один
-- раз заплатил за аукционную цену того, что торговец продавал дешевле.
--
-- ЧТО СЧИТАЕТСЯ ПОТОЛКОМ - ТОЛЬКО ДВА ИСТОЧНИКА, И ОБА ДОКАЗЫВАЮТ ЗАПАС:
--   "own"   - наша собственная запись. Price:RecordMerchant кладёт в неё
--             ТОЛЬКО товар с numAvailable == -1, то есть неограниченный.
--   "cache" - кеш цен торговцев Auctionator. Его собственный код пишет запись
--             тоже только при numAvailable == -1 и делит цену окна на размер
--             стопки. Это такие же честные потолки, просто увиденные его
--             глазами: в файле игрока их 561.
--
-- ЧТО ПОТОЛКОМ НЕ СЧИТАЕТСЯ, И ЭТО ВАЖНЕЕ ПЕРВОГО:
--   vendorForeign - чужой кеш, полярность не проверена: число там может
--             означать «сколько торговец ДАЁТ», и тогда это не потолок, а пол.
--   Codex и Data/Horizon.lua - цены из пакетов сообщества. Про запас они
--             молчат (поле limited не заполнено ни у одной из 7219 записей), а
--             штучный товар потолка не держит. Отдельный случай того же рода:
--             по данным сообщества в Forever есть торговец с неограниченным
--             запасом высокоуровневых реагентов (Mister Graphed, 263384,
--             Powderfuse Port), но игрок у него НЕ БЫЛ, и в его кеше этих цен
--             нет. Выдать их за потолок значило бы назвать фактом то, чего мы
--             не видели, - ровно та ошибка, от которой этот файл и защищает.
--   markup  - наша же арифметика по цене выкупа. Оценка, а не прилавок.
--
-- Нет ни одной из двух записей - потолка НЕТ, и это ответ («я не знаю, сколько
-- за это просит торговец»), а не ноль и не догадка.
Price.CEILING_SOURCES = { own = true, cache = true }

-- Словами для игрока: чьими глазами увиден потолок. Отдельно от SRC_LABEL,
-- потому что в маршрутах покупки оба источника называются одним словом
-- «торговец» - а вот доверие к ним разное, и на карточке это видно.
Price.CEILING_SRC_LABEL = {
    own   = "я сам стоял у этого торговца",
    cache = "кеш цен торговцев Auctionator",
}

-- НИЖНЯЯ ЦЕНА НА АУКЦИОНЕ - НЕ ПОЛ РЫНКА.
--
-- Auctionator отдаёт минимум последнего наблюдения. Продавцы перебивают
-- собственные лоты, и самый дешёвый лот может висеть непроданным неделю: то
-- есть «на аукционе дешевле» бывает утверждением об одном лоте, а не о рынке.
-- Против фиксированной цены на полке это слабое свидетельство, и лечится оно
-- дёшево - не доверять минимуму, за которым стоит одно наблюдение.
--
-- Наблюдения считаются по СВОЕЙ истории суточных слепков (Logic/MarketHistory):
-- ноль и один день - это одно наблюдение, то самое, на которое мы смотрим
-- сейчас. Числом цена при этом НЕ меняется: поднять игроку стоимость покупки
-- из-за своего сомнения значило бы менять сумму молча. Падает достоверность, и
-- об этом говорится словами.
Price.THIN_OBSERVATIONS = 1
Price.THIN_MARGIN_SHARE = 0.10

-- РАЗНИЦА МЕНЬШЕ МЕДЯКА - ЭТО НЕ РАЗНИЦА.
--
-- Цены в кеше Auctionator бывают ДРОБНЫМИ: он делит цену окна торговца на
-- размер стопки, и у стрел со стопкой в 200 штук выходит 0.045 медяка за штуку
-- (в файле игрока таких записей 10, из них 4 меньше медяка). Разница в такую
-- долю на экране печатается как «экономия 0м» - число, которое не значит
-- ничего, и его же ловит детектор бессмыслицы. Такой разрыв считается
-- отсутствующим, и это честно: заплатить меньше медяка нельзя.
Price.MIN_GAP = 1

-- Сколько СВОИХ наблюдений стоит за ценой этого предмета на аукционе.
function Price:MarketObservations(itemID)
    local st = ns.MarketHistory and ns.MarketHistory:Stats(itemID) or nil
    return (st and tonumber(st.days)) or 0
end

-- Потолок: copper, source ("own"/"cache"), confidence. Без потолка - nil.
--
-- Два источника сравниваются по ЦЕНЕ, а не по старшинству: полка дешевле - её
-- и можно взять. При равенстве впереди своя запись: мы её видели сами.
function Price:VendorCeiling(itemID)
    if not itemID then return nil, nil, CONF.UNKNOWN end
    local memo = self.vendorAskSession
    local hit = memo and memo[itemID]
    if hit then return hit[1], hit[2], hit[3] end
    local own = copperOrNil(ns.Config and ns.Config:VendorPrice(itemID))
    local cache, cacheConf = Api:VendorPrice(itemID)
    cache = copperOrNil(cache)
    local copper, src, conf
    if own and cache and cache < own then
        copper, src, conf = cache, "cache", cacheConf or CONF.CACHED
    elseif own then
        copper, src, conf = own, "own", CONF.CACHED
    elseif cache then
        copper, src, conf = cache, "cache", cacheConf or CONF.CACHED
    else
        conf = CONF.UNKNOWN
    end
    if memo then memo[itemID] = { copper, src, conf } end
    return copper, src, conf
end

-- ПОЧЕМУ ПОТОЛКА НЕТ - ОДНОЙ ФРАЗОЙ, И ЭТО НЕ ОТГОВОРКА.
--
-- Вендорная цена известна ровно у тех торговцев, перед которыми игрок стоял
-- (своими глазами или глазами Auctionator). Во всём остальном честный ответ -
-- «не знаю», и он обязан звучать так, а не подставляться догадкой из пакета
-- сообщества.
Price.CEILING_UNKNOWN_WHY = "цену торговца я знаю только там, где вы у него"
    .. " стояли, — по этому предмету потолка у меня нет"

-- Решение по потолку для одного предмета. nil - потолка нет.
--
--   { ceiling, ceilingSrc, ceilingConf, auction, days,
--     cheaper = "vendor" | "auction" | "equal",
--     saving, share, thin, text }
--
-- `saving` - сколько даёт дешёвая сторона за ОДНУ штуку. `thin` - «дешевле на
-- аукционе, но за этим стоит одно наблюдение и разрыв меньше десятой части»:
-- см. Price.THIN_OBSERVATIONS выше.
-- `auctionKnown` - цена аукциона, если вызывающий её только что спросил. Это не
-- оптимизация ради красоты: Api:AuctionPrice помнит ответы по КЛЮЧУ (itemID или
-- ссылка), и спросить второй раз по другому ключу значит сходить к Auctionator
-- ещё раз за тем же числом. Цена работы в этом проекте мерится вызовами за
-- пересчёт, а не миллисекундами.
function Price:Ceiling(itemID, auctionKnown)
    if not itemID then return nil end
    local memo = self.ceilingSession
    if memo and memo[itemID] ~= nil then
        return (memo[itemID] ~= false) and memo[itemID] or nil
    end
    local ceiling, src, conf = Price:VendorCeiling(itemID)
    if not ceiling then
        if memo then memo[itemID] = false end
        return nil
    end
    local auction = copperOrNil(auctionKnown) or copperOrNil(Api:AuctionPrice(itemID))
    local v = {
        itemID = itemID, ceiling = ceiling, ceilingSrc = src, ceilingConf = conf,
        auction = auction, days = Price:MarketObservations(itemID),
        seenBy = Price.CEILING_SRC_LABEL[src],
    }
    if not auction then
        v.cheaper = "vendor"
        v.text = "у торговца " .. U.money(ceiling)
            .. ", и запас у него неограниченный; цены аукциона по этому"
            .. " предмету нет вовсе"
    elseif math.abs(auction - ceiling) < Price.MIN_GAP then
        v.cheaper = "equal"
        v.text = "у торговца столько же (" .. U.money(ceiling)
            .. "), но запас у него неограниченный, а лот один"
    elseif auction > ceiling then
        v.cheaper = "vendor"
        v.saving = auction - ceiling
        v.share = U.div(v.saving, auction, 0)
        v.text = "у торговца дешевле: " .. U.money(ceiling) .. " против "
            .. U.money(auction) .. " на аукционе, экономия " .. U.money(v.saving)
            .. " за штуку"
    else
        v.cheaper = "auction"
        v.saving = ceiling - auction
        v.share = U.div(v.saving, ceiling, 0)
        v.thin = (v.days <= Price.THIN_OBSERVATIONS)
            and (v.share < Price.THIN_MARGIN_SHARE) or false
        if v.thin then
            v.text = "на аукционе дешевле всего на " .. U.money(v.saving)
                .. ", и за этой ценой стоит одно наблюдение; у торговца та же"
                .. " вещь есть всегда за " .. U.money(ceiling)
        else
            v.text = "на аукционе дешевле: " .. U.money(auction) .. " против "
                .. U.money(ceiling) .. " у торговца, экономия "
                .. U.money(v.saving) .. " за штуку"
        end
    end
    if memo then memo[itemID] = v end
    return v
end

-- Одна короткая фраза для карточки - или nil, когда говорить нечего (потолок
-- есть, и на аукционе он честно ниже). Та же фраза во всех ветках: пока каждая
-- писала свою, одно состояние выглядело на экране по-разному.
function Price:CeilingText(itemID)
    local v = Price:Ceiling(itemID)
    if not v then return nil end
    if v.cheaper == "auction" and not v.thin then return nil end
    return v.text
end

-- Buy price: what the player would have to pay to get one of these.
--
-- Every route is asked, and the CHEAPEST one the player can actually use wins.
-- Taking the first answer meant a 1-silver reagent sitting on a vendor's shelf
-- was costed at the 1-gold the auction house wanted for it.
--
-- Returns copper (or nil), confidence, source, ageSeconds.
function Price:Buy(itemID, itemLink)
    if not itemID then return nil, CONF.UNKNOWN, "none" end
    local cached = self.session[itemID]
    if cached then return cached.copper, cached.conf, cached.src, cached.age end

    local routes = {}
    local function offer(src, copper, conf, age)
        copper = copperOrNil(copper)
        if not copper then return end
        routes[#routes + 1] = { src = src, copper = copper, conf = conf, age = age }
    end

    -- 0. СВОЯ КНИГА ЗАКУПОК - ПЕРВОЙ, И ЭТО НЕ ПОРЯДОК РАДИ ПОРЯДКА.
    --    Игрок сам отдал эти деньги за этот предмет: доказательства прямее
    --    «это можно купить за столько» не существует. См. Logic/Ledger.lua.
    local ourBook
    if ns.Ledger then
        local copper, conf, age = ns.Ledger:UnitCost(itemID)
        if copper then ourBook = true end
        offer("ledger", copper, conf, age)
    end

    -- 1. Auctionator, stable API only. Число запоминается: его же сравнивает с
    --    потолком Price:Ceiling ниже, и второй раз спрашивать незачем.
    local livePrice, liveConf, liveAge = Api:AuctionPrice(itemID, itemLink)
    offer("auctionator", livePrice, liveConf, liveAge)

    -- 2. Our own remembered observation, aged against the staleness window.
    local own, ownT = ns.Config:CachedPrice(itemID)
    if own then
        local ageOwn = Api:ServerTime() - (ownT or 0)
        offer("own", own, (ageOwn < ns.PRICE_STALE_SECONDS) and CONF.CACHED or CONF.ESTIMATE,
            ageOwn)
    end

    -- 3. ЧУЖАЯ КНИГА - ТОЛЬКО ПОКА СВОЯ ПО ЭТОМУ ПРЕДМЕТУ МОЛЧИТ.
    --    Это и есть «запасной источник на первое время»: как только игрок
    --    сам купил предмет, чужое число по нему больше не спрашивается вовсе.
    if not ourBook then
        offer("foreign", Api:MastercraftObservedPrice(itemID))
    elseif ns.Diag then
        ns.Diag:Count("ledger.foreignSkipped")
    end

    -- 4. A merchant's asking price - THE CEILING. Ours comes from the merchant
    --    window we read ourselves; Auctionator's cache is the same thing (its
    --    own code divides the window price by the stack size and only keeps
    --    unlimited stock). Спрашивается ОДНИМ вызовом (Price:Ceiling помнит
    --    ответ на пересчёт), и то же решение потом читают денежные ветки.
    --
    -- ВОЗРАСТ У ЭТОЙ ЦЕНЫ - `false`, И ЭТО НЕ «НЕ ЗНАЮ». Цена на полке
    -- фиксированная: вчера она была той же и завтра будет той же. Раньше
    -- маршрут торговца шёл без возраста вовсе, и на карточке стояло «18с
    -- (торговец, возраст неизвестен)» - про число, которое не стареет. Словарь
    -- возраста это различает ровно для такого случая (U.ageWord, ns.AGE_*).
    local ceilingVerdict = Price:Ceiling(itemID, livePrice)
    if ceilingVerdict then
        offer("vendor", ceilingVerdict.ceiling, ceilingVerdict.ceilingConf, false)
    end

    -- Pick the cheapest proven route.
    --
    -- ДЕШЕВИЗНА РЕШАЕТ ПЕРВОЙ, И МЕНЯТЬ ЭТО НЕЛЬЗЯ: вопрос здесь - «сколько я
    -- отдам, чтобы получить одну штуку сейчас», и реагент за серебро на полке
    -- торговца стоит серебро, даже если на аукционе за него просят золотой и
    -- даже если в прошлый раз игрок платил больше.
    --
    -- А вот РАВНЫЕ числа разбираются по происхождению: своя книга впереди
    -- своих наблюдений, свои - впереди чужих. Иначе при совпадении цены
    -- источник на экране зависел бы от порядка строк выше.
    local best
    for _, route in ipairs(routes) do
        if Price.PROVEN_SOURCES[route.src] then
            if (not best) or route.copper < best.copper
                or (route.copper == best.copper
                    and Price:SourceRank(route.src) < Price:SourceRank(best.src)) then
                best = route
            end
        end
    end

    -- ПОТОЛОК ПРИМЕНЯЕТСЯ ЗДЕСЬ, И ОДНОЙ СТРОКОЙ, А НЕ ПОРЯДКОМ МАРШРУТОВ.
    --
    -- Выбор дешёвого выше уже не поднимет цену выше прилавка - пока прилавок
    -- остаётся одним из маршрутов. Но это свойство ПОРЯДКА СРАВНЕНИЯ, а не
    -- правило: новый источник с другим признаком «подтверждённости» (или
    -- маршрут, добавленный после выбора) снял бы его молча. Правило живёт
    -- строкой ниже и звучит ровно так, как задумано: сколько бы маршрутов тут
    -- ни появилось, ответ не может превысить цену на неограниченной полке.
    local ceilingApplied
    if ceilingVerdict and best and best.copper > ceilingVerdict.ceiling then
        ceilingApplied = best.copper
        best = { src = "vendor", copper = ceilingVerdict.ceiling,
                 conf = ceilingVerdict.ceilingConf, age = false }
    end

    -- И СЛАБЫЙ МИНИМУМ АУКЦИОНА НЕ ВЫГЛЯДИТ ТВЁРДЫМ ЧИСЛОМ.
    --
    -- Цена остаётся аукционной (поднимать игроку стоимость покупки из-за своего
    -- сомнения - это менять сумму молча), но достоверность падает на ступень:
    -- «дешевле на четыре медяка, и за этим стоит один лот» - это оценка, а не
    -- измерение. См. Price.THIN_OBSERVATIONS.
    local thinMinimum
    if ceilingVerdict and ceilingVerdict.thin and best
        and Price.BUY_MARKET_SOURCES[best.src] then
        thinMinimum = true
        best = { src = best.src, copper = best.copper, age = best.age,
                 conf = U.worstConf(best.conf or CONF.CACHED, CONF.ESTIMATE) }
    end

    -- Nothing proven: fall back to the numbers that are only indications, and
    -- say so. These never make an item count as buyable.
    if not best then
        local fv, fc = Api:MastercraftVendorPrice(itemID)
        fv = copperOrNil(fv)
        if fv then
            best = { src = "vendorForeign", copper = fv, conf = CONF.ESTIMATE }
        end
    end
    if not best then
        local info = Api:ItemInfo(itemID)
        local sell = info and copperOrNil(info.sellPrice)
        if sell then
            best = { src = "markup", copper = sell * Price.VENDOR_MARKUP, conf = CONF.ESTIMATE }
        end
    end

    local entry
    local why
    if best then
        local bucket = (best.src == "vendorForeign" or best.src == "markup")
            and "estimate" or best.src
        self.stats[bucket] = (self.stats[bucket] or 0) + 1
        entry = {
            copper = best.copper, conf = best.conf or CONF.UNKNOWN,
            src = best.src, age = best.age, routes = routes,
            -- РЕШЕНИЕ ПО ПОТОЛКУ ЕДЕТ С ОТВЕТОМ. Ветки читают его отсюда и не
            -- считают заново: одно состояние - один текст.
            ceiling = ceilingVerdict,
            cappedFrom = ceilingApplied,
            thinMinimum = thinMinimum,
        }
        if ceilingApplied then
            why = "цена торговца с неограниченным запасом — это потолок:"
                .. " дешёвый маршрут просил " .. U.money(ceilingApplied)
        elseif thinMinimum then
            why = "самый дешёвый из подтверждённых источников, но за минимумом"
                .. " аукциона стоит одно наблюдение — это оценка"
        elseif Price.PROVEN_SOURCES[best.src] then
            why = "самый дешёвый из подтверждённых источников"
        else
            why = "подтверждённых источников не было, это только оценка"
        end
    else
        self.stats.unknown = self.stats.unknown + 1
        entry = { copper = nil, conf = CONF.UNKNOWN, src = "none", routes = routes,
                  ceiling = ceilingVerdict }
        why = (#routes == 0) and "ни один источник не ответил"
            or "источники ответили, но ни один не дал положительной цены"
    end

    -- Which sources were asked, what each said, which won and why. Written from
    -- the routes already collected above - no second lookup - and bounded by
    -- Diag.CAP.priceDecisions. This is what the file was missing when a buy
    -- card showed a price with "priceSource = nil" beside it.
    if ns.Diag then
        ns.Diag:PriceDecision(itemID, "buy", routes, best, why)
        -- СПИСОК ЗАКАЗА. Цены нет ни в одном источнике - это заказ на цену, и
        -- он нужен структурой: по какому предмету и в какой ветке.
        if not best then
            ns.Diag:Want("itemsNoPrice", itemID, Price.askedFor or "buy",
                { routes = #routes })
        elseif best.age and best.age >= (ns.PRICE_AGE_SAY_SECONDS or 86400) then
            ns.Diag:Want("pricesStale", itemID, Price.askedFor or "buy",
                { ageSeconds = U.round(best.age), src = best.src })
        end
        -- ПОТОЛКА НЕТ, А СОВЕТ БУДЕТ «КУПИ НА АУКЦИОНЕ» - ЭТО ЗАКАЗ НА ДАННЫЕ.
        --
        -- Заказ ставится не на каждый предмет без вендорной цены (у капюшона
        -- своего производства торговца и не бывает), а ровно там, где потолок
        -- изменил бы совет: цену мы собираемся взять с аукциона, и проверить её
        -- сверху нечем. Исполняется он одним действием игрока - постоять у
        -- торговца, который этим торгует.
        if best and not ceilingVerdict and Price.BUY_MARKET_SOURCES[best.src] then
            ns.Diag:Want("vendorCeilingUnknown", itemID, Price.askedFor or "buy",
                { auction = best.copper, src = best.src })
        end
    end

    self.session[itemID] = entry
    return entry.copper, entry.conf, entry.src, entry.age
end

-- Every route we found for an item, cheapest first. The craft tab shows this so
-- "where did that number come from" has an answer the player can read.
function Price:Routes(itemID)
    local entry = itemID and self.session[itemID]
    local out = {}
    for _, r in ipairs((entry and entry.routes) or {}) do out[#out + 1] = r end
    table.sort(out, function(a, b)
        if a.copper ~= b.copper then return a.copper < b.copper end
        return tostring(a.src) < tostring(b.src)
    end)
    return out
end

-- Sell price: what the player would get for one. Auction minus the house's cut
-- when we have an auction price; the vendor's offer otherwise.
Price.AH_CUT = 0.05

-- Which `src` values from Price:Sell mean "somebody listed this on the auction
-- house", i.e. the ones the house's cut was taken off. "vendor" is not one of
-- them, and a card describing a vendor figure must not mention a fee.
--
-- A source may carry a "+history" suffix when MarketHistory overruled the live
-- listing; it is still a market price (and still had the fee taken off), so the
-- base name is what decides.
Price.MARKET_SELL_SOURCES = { auction = true, foreign = true }

function Price:BaseSource(src)
    if type(src) ~= "string" then return src end
    return (src:gsub("%+.*$", ""))
end

function Price:IsMarketSource(src)
    return Price.MARKET_SELL_SOURCES[Price:BaseSource(src)] and true or false
end

-- Will SOMEBODY actually hand over this much? Three different answers, and the
-- advice needs all three kept apart:
--
--   market     - somebody listed it on the auction house. The fee applies, and
--                nobody has paid it yet, so it is an observation and not a
--                promise.
--   guaranteed - the vendor's offer out of the item's own data. Small, exact,
--                and certain. NOT a market price: check 27 treats a revenue
--                with no market behind it as suspicious precisely because
--                "a vendor would take it" is not the trade the card describes.
--   neither    - we made the number up from the item's sell price. Never
--                allowed to produce a profit card; Price:Sell does not return
--                one of these at all.
Price.GUARANTEED_SELL_SOURCES = { vendor = true }

function Price:IsGuaranteedSource(src)
    return Price.GUARANTEED_SELL_SOURCES[Price:BaseSource(src)] and true or false
end

-- "Somebody will pay this": a market listing or the vendor's standing offer.
function Price:IsObservedSource(src)
    return Price:IsMarketSource(src) or Price:IsGuaranteedSource(src)
end

-- Sell price: the best price we can defend for one of these.
--
-- Two quite different things live here and they must not be swapped:
--   * what a vendor will hand over - small, but guaranteed
--   * what the auction house is paying - larger, but a market observation
-- A market observation always beats the vendor's offer as the expected sale
-- price, and it is never labelled EXACT, because nobody has bought it yet.
function Price:Sell(itemID, itemLink)
    if not itemID then return nil, CONF.UNKNOWN, "none" end
    local cached = self.sellSession and self.sellSession[itemID]
    if cached then
        return cached.copper, cached.conf, cached.src, cached.age, cached.info
    end

    local market, marketConf, marketSrc, marketAge
    local liveCopper, historyNote, verdict
    local p, c, a = Api:AuctionPrice(itemID, itemLink)
    p = copperOrNil(p)
    if p then
        market, marketConf, marketSrc, marketAge = p, c, "auction", a
    else
        local fp, fc, fa = Api:MastercraftObservedPrice(itemID)
        fp = copperOrNil(fp)
        if fp then
            market, marketConf, marketSrc, marketAge = fp, fc, "foreign", fa
        end
    end

    -- THE 167x GUARD. A live listing is checked against the item's own recorded
    -- history before it becomes advice. On 17 November the cheapest Linen Boots
    -- listing was 50200 copper against a week at 180-300, on two listings; the
    -- addon believed it and the player listed boots at 5 gold on the strength
    -- of the card. MarketHistory replaces a price that far out of line with the
    -- median it actually observed, downgrades the confidence, and hands back a
    -- sentence saying so - which the card then prints rather than hiding.
    --
    -- The cut is applied AFTER this, so the fee is taken off whichever price we
    -- ended up trusting.
    if market and ns.MarketHistory then
        liveCopper = market
        local use, forcedConf, note, v = ns.MarketHistory:Expected(itemID, market)
        historyNote, verdict = note, v
        if use and use ~= market then
            market = use
            marketSrc = marketSrc .. "+history"
        end
        if forcedConf then marketConf = U.worstConf(marketConf or CONF.CACHED, forcedConf) end
    end
    if market then market = market * (1 - Price.AH_CUT) end

    local vendor, vendorConf = Price:VendorSell(itemID)

    -- The same journal as on the buy side, so a revenue figure can be traced
    -- back to the source that produced it. The old diagnostics recorded only a
    -- material price here and printed it next to the revenue, which is how a
    -- 167x outlier hid behind the label "vendor" for a whole session.
    local function journal(chosenSrc, chosenCopper, chosenConf, why)
        if not ns.Diag then return end
        local routes = {}
        if market then
            routes[#routes + 1] = { src = marketSrc, copper = market,
                                    conf = marketConf, age = marketAge }
        end
        if vendor then
            routes[#routes + 1] = { src = "vendor", copper = vendor, conf = vendorConf }
        end
        ns.Diag:PriceDecision(itemID, "sell", routes,
            chosenSrc and { src = chosenSrc, copper = chosenCopper, conf = chosenConf } or nil,
            why, {
                liveCopper = liveCopper,
                historyFlag = verdict and verdict.flag or nil,
                historyRatio = verdict and verdict.ratio or nil,
                historyDays = verdict and verdict.days or nil,
                historyMedian = verdict and verdict.median or nil,
                observed = Price:IsObservedSource(chosenSrc),
            })
    end

    -- One place to remember the answer and hand it back, so every return below
    -- goes through the same memo.
    local function remember(copper, conf, src, age, infoTable)
        if self.sellSession then
            self.sellSession[itemID] = {
                copper = copper, conf = conf, src = src, age = age, info = infoTable,
            }
        end
        return copper, conf, src, age, infoTable
    end

    -- ОБРАТНАЯ СТОРОНА ПОТОЛКА: ВЫРУЧКА ВЫШЕ ПРИЛАВКА.
    --
    -- Если тот же предмет лежит у торговца с неограниченным запасом дешевле,
    -- чем мы обещаем за него выручить, то покупателю незачем брать его у
    -- игрока: он возьмёт у торговца, сколько захочет и когда захочет. Числа
    -- здесь НЕ подменяются - выручка остаётся той, что показывает рынок, - но
    -- решение едет с ответом, и карточку по нему помечает Logic/Risk.lua.
    --
    -- Живая цена передаётся готовой: её уже спросили выше, и второе обращение к
    -- Auctionator за тем же числом здесь было бы платой ни за что.
    local ceilingVerdict = Price:Ceiling(itemID, liveCopper or p)

    -- `info` is the fifth return: everything a card needs to describe where the
    -- figure came from without re-deriving any of it.
    local function info(src)
        return {
            src = src,
            observed = Price:IsObservedSource(src),
            market = Price:IsMarketSource(src),
            cutApplied = Price:IsMarketSource(src),
            liveCopper = liveCopper,
            historyNote = historyNote,
            verdict = verdict,
            ceiling = ceilingVerdict,
            outlier = verdict and verdict.flag ~= ns.MarketHistory.FLAG.TYPICAL
                and verdict.flag ~= ns.MarketHistory.FLAG.NO_HISTORY
                and verdict.flag or nil,
        }
    end

    if market and vendor and vendor > market then
        -- The vendor pays more than the market: rare, but then the vendor is
        -- the honest answer and it is the guaranteed one.
        journal("vendor", vendor, vendorConf,
            "торговец платит больше, чем рынок — и это гарантированно")
        return remember(vendor, vendorConf, "vendor", nil, info("vendor"))
    end
    if market then
        -- A market price is never "exact": it is what listings said, not what
        -- anybody paid. The auction cut is already taken off above.
        if marketConf == CONF.EXACT then marketConf = CONF.CACHED end
        journal(marketSrc, market, marketConf,
            "рыночная цена минус сбор аукциона " .. U.pct(Price.AH_CUT)
            .. (historyNote and ("; " .. historyNote) or ""))
        return remember(market, marketConf or CONF.CACHED, marketSrc, marketAge,
            info(marketSrc))
    end
    if vendor then
        journal("vendor", vendor, vendorConf, "рыночной цены нет, остаётся торговец")
        return remember(vendor, vendorConf, "vendor", nil, info("vendor"))
    end

    journal(nil, nil, nil, "ни рынка, ни торговца — цену продажи назвать нечем")
    if ns.Diag then
        ns.Diag:Want("itemsNoPrice", itemID, "sell", { routes = 0 })
    end
    return remember(nil, CONF.UNKNOWN, "none", nil, info("none"))
end

-- В КАКОЙ ВЕТКЕ СПРАШИВАЛИ. Ветка - это та самая «где понадобилось», без
-- которой заказ на цену нельзя исполнить осмысленно: цена на реагент и цена на
-- готовую вещь добываются по-разному. Движок выставляет это перед веткой и
-- снимает после; снаружи поля нет - тогда пометка будет просто "buy".
function Price:AskingFor(branch)
    Price.askedFor = branch
end

-- Vendor sell price only: used for junk, where the player walks to a merchant.
-- This one really is exact - it is the item's own data, not an estimate.
function Price:VendorSell(itemID)
    local info = Api:ItemInfo(itemID)
    local sell = info and copperOrNil(info.sellPrice)
    if sell then return sell, CONF.EXACT end
    return nil, CONF.UNKNOWN
end

-- Whether buying is even possible: an item that only drops has no buy price we
-- can trust, and suggesting "buy 6 of these" would be useless advice.
function Price:Buyable(itemID)
    local copper, conf, src = self:Buy(itemID)
    if not copper then return false, conf end
    if not Price.PROVEN_SOURCES[src] then return false, conf end
    return true, conf
end

function Price:AgeText(itemID)
    local entry = self.session[itemID]
    if not entry or not entry.age then return nil end
    return U.ageText(entry.age)
end

-- A short, honest label for a price.
--
-- ОДИН СЛОВАРЬ НА ВСЕ СЛУЧАИ ПУСТОТЫ (см. ns.VOID в Core/Const.lua). Раньше
-- отсутствие цены печаталось здесь своей фразой, в карточке - другой, в окне
-- крафта - прочерком, и три разных причины молчания выглядели одинаково.
--
-- И ВОЗРАСТ ТЕПЕРЬ НАЗЫВАЕТСЯ ВСЕГДА. До этого `age and U.ageText(age)`
-- молчал, когда возраста нет, и «2з 50с (аукцион)» значило то «видел минуту
-- назад», то «видел неизвестно когда». Цена торговца из данных предмета не
-- стареет вовсе - для неё вызывающий передаёт age = false.
-- ОТКУДА ЦЕНА, СЛОВАМИ ДЛЯ ИГРОКА. ОДНА ТАБЛИЦА НА ВЕСЬ АДДОН.
--
-- Эти слова стояли внутри Label цепочкой if, и спросить их было нельзя.
-- Самопроверка из-за этого печатала КОД источника: на карточке живого прогона
-- оказалась фраза «Единственная цена здесь — vendor, то есть сколько даст
-- торговец» (Logic/SanityChecks.lua, проверка 27). Слово «vendor» игрок в игре
-- не видел нигде.
Price.SRC_LABEL = {
    auctionator   = "аукцион",
    auction       = "аукцион",
    vendor        = "торговец",
    foreign       = "наблюдение другого аддона",
    own           = "мои данные",
    ledger        = "вы столько заплатили",
    vendorForeign = "чужой кеш торговца, полярность не проверена",
    markup        = "по цене продажи торговцу",
}

-- Название источника словами, или nil, когда источник не назван. nil - это
-- ответ («не знаю, откуда»), и подменять его кодом нельзя.
function Price:SourceLabel(src)
    if type(src) ~= "string" then return nil end
    return Price.SRC_LABEL[src]
end

function Price:Label(copper, conf, src, age)
    if not copper then return U.void(ns.VOID.NO_PRICE) end
    local text = U.money(copper)
    local tag = Price:SourceLabel(src)
    local bits = {}
    if conf == CONF.ESTIMATE or conf == CONF.UNKNOWN then
        text = ns.ESTIMATE_MARK .. text
        bits[#bits + 1] = ns.ESTIMATE_WORD
    end
    if tag then bits[#bits + 1] = tag end
    bits[#bits + 1] = U.ageWord(age)
    return text .. " (" .. table.concat(bits, ", ") .. ")"
end

-- СВЕЖЕСТЬ ЦЕН, ОДНИМ ОТВЕТОМ -------------------------------------------
--
-- Auctionator знает ровно то, что игрок отсканировал сам. Это не недостаток
-- аддона и не починить - значит надо честно показывать. Возвращает:
--   { priced, stale, staleCount, oldestSeconds, oldestDays, text }
--
-- ПОЧЕМУ ЭТО ВООБЩЕ ПРИШЛОСЬ СЧИТАТЬ ОТДЕЛЬНО. Возраст цены приходит от
-- Auctionator в ДНЯХ (его GetPriceAge возвращает GetScanDay() - последний день
-- наблюдения), а адаптер считал это число секундами. Из-за этого цена
-- двухдневной давности печаталась как «2 минуты назад» и никогда не считалась
-- устаревшей: порог был 48 часов, а сравнивалось с двойкой. Перевод в секунды
-- теперь делается в Api:ReadAuctionPrice, здесь - сводка по всей сессии.
function Price:Freshness()
    local priced, stale, oldest = 0, 0, nil
    for _, entry in pairs(self.session or {}) do
        if entry.copper then
            priced = priced + 1
            local age = tonumber(entry.age)
            if age then
                if (not oldest) or age > oldest then oldest = age end
                if age >= (ns.PRICE_AGE_SAY_SECONDS or 86400) then stale = stale + 1 end
            end
        end
    end
    local days = oldest and math.floor(oldest / 86400) or nil
    local isStale = (stale > 0)
    local text
    if priced == 0 then
        text = "цен нет вообще: ничего денежного я сейчас не считаю."
    elseif not oldest then
        text = "сколько лет ценам, Auctionator не говорит — считаю их как есть."
    elseif isStale then
        text = "цены не сегодняшние: самая старая — " .. (U.ageText(oldest) or "давно")
            .. ", таких " .. stale .. " из " .. priced .. "."
    else
        text = "цены свежие: самой старой " .. (U.ageText(oldest) or "меньше суток") .. "."
    end
    return {
        priced = priced, staleCount = stale, stale = isStale,
        oldestSeconds = oldest, oldestDays = days,
        auctionator = self:AuctionatorEnabled(),
        text = text,
    }
end

function Price:SourceSummary()
    local s = self.stats
    local total = s.auctionator + (s.own or 0) + s.foreign + s.vendor + s.estimate + s.unknown
    return {
        total = total,
        auctionator = s.auctionator, own = s.own or 0, foreign = s.foreign,
        vendor = s.vendor, estimate = s.estimate, unknown = s.unknown,
        auctionatorAvailable = self:AuctionatorEnabled(),
    }
end

-- Record what a merchant is asking. Called from the merchant handler in Main;
-- reading the merchant window is not automation, we never buy anything.
--
-- `numAvailable` is the merchant's stock: -1 means unlimited, anything else is
-- a finite pile that will be gone tomorrow. Only an unlimited line is a price
-- we can keep, and that is exactly the rule Auctionator applies to its own
-- vendor cache. A limited line is recorded as an observation, not as a price
-- the player can go and rely on.
function Price:RecordMerchant(itemID, copper, stackCount, numAvailable)
    if not (itemID and copper and copper > 0) then return false end
    if numAvailable ~= nil and numAvailable ~= -1 then
        if ns.Diag then ns.Diag:Count("merchant.limitedStock") end
        return false
    end
    local unit = copper / math.max(1, tonumber(stackCount) or 1)
    ns.Config:RememberVendorPrice(itemID, U.round(unit))
    return true
end

-- Daily price snapshot ---------------------------------------------------
--
-- The realm opened on 4 November 2026. Nobody has a price history for it and
-- one cannot be built retroactively, so we start saving a daily number for
-- every item we care about from the first login onward. Deliberately dumb in
-- this version: one price per item per day, stored, no analysis.
--
-- Only runs once per calendar day, only for items we have a reason to track,
-- and it is spread over several frames so a login never stutters.

Price.snapshotQueue = nil
Price.snapshotWritten = 0

-- `itemIDs` is the set of items worth remembering: every reagent of every
-- learned recipe, everything those recipes produce, and whatever is in the bags.
function Price:QueueDailySnapshot(itemIDs)
    local now = ns.Api:ServerTime()
    if not ns.Config:SnapshotDue(now) then return false, "already-today" end
    if not Api:AuctionatorPresent() then return false, "no-auctionator" end

    local queue = {}
    for itemID in pairs(itemIDs or {}) do queue[#queue + 1] = itemID end
    table.sort(queue)
    if #queue == 0 then return false, "nothing-to-track" end

    self.snapshotQueue = queue
    self.snapshotIndex = 1
    self.snapshotWritten = 0
    self.snapshotDay = now
    return true, #queue
end

-- Process a slice of the queue. Returns true while there is more to do.
function Price:StepDailySnapshot(budget)
    local queue = self.snapshotQueue
    if not queue then return false end
    budget = budget or 150

    local stop = math.min(#queue, self.snapshotIndex + budget - 1)
    for i = self.snapshotIndex, stop do
        local itemID = queue[i]
        -- Stable API only: this is the documented call, nothing else.
        local copper = Api:AuctionPrice(itemID)
        if copper then
            if ns.Config:RecordPriceSnapshot(itemID, copper, self.snapshotDay,
                    self.snapshotOverwrite) then
                self.snapshotWritten = self.snapshotWritten + 1
            end
        end
    end
    self.snapshotIndex = stop + 1

    if self.snapshotIndex > #queue then
        ns.Config:FinishSnapshot(self.snapshotDay, self.snapshotWritten)
        self.snapshotQueue = nil
        self.snapshotOverwrite = nil
        return false
    end
    return true
end

-- ПЕРЕЗАПИСАТЬ СЕГОДНЯШНИЙ СЛЕПОК. Обычный QueueDailySnapshot отказывается
-- работать второй раз за сутки, и это правильно - при каждом входе в игру
-- переписывать историю незачем. Но есть один момент, когда переписать НАДО:
-- игрок стоит у аукциона, и вот сейчас цены точно свежее, чем те, что лежали в
-- базе при входе. Другого такого момента за сессию может не быть.
function Price:RequeueToday(itemIDs)
    if not Api:AuctionatorPresent() then return false, "no-auctionator" end
    local queue = {}
    for itemID in pairs(itemIDs or {}) do queue[#queue + 1] = itemID end
    table.sort(queue)
    if #queue == 0 then return false, "nothing-to-track" end
    self.snapshotQueue = queue
    self.snapshotIndex = 1
    self.snapshotWritten = 0
    self.snapshotDay = ns.Api:ServerTime()
    self.snapshotOverwrite = true
    return true, #queue
end

function Price:SnapshotProgress()
    if not self.snapshotQueue then return nil end
    return self.snapshotIndex - 1, #self.snapshotQueue, self.snapshotWritten
end

return Price
