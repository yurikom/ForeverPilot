-- ForeverPilot / Logic/VendorArbitrage.lua
--
-- КУПИТЬ У ТОРГОВЦА, ПРОДАТЬ НА АУКЦИОНЕ.
--
-- Самый простой способ заработать, который вообще есть в игре, и единственный,
-- где одна сторона сделки заведомо известна: торговец просит фиксированную цену
-- и не торгуется. Персонажу с пятью золотыми это подходит лучше крафта - вложить
-- надо мало, а товар не надо делать.
--
-- ЧТО ОБЯЗАНО БЫТЬ В СОВЕТЕ, И ПОЧЕМУ ИМЕННО ЭТО:
--   * русское название из клиента - потому что английское имя из внешней базы
--     игрок в игре не увидит и не найдёт;
--   * itemID - потому что «Красная краска» бывает не одна;
--   * имя NPC, зона и координаты - иначе совет «купи у торговца» бесполезен;
--   * валюта и цена - и если цена не в золоте, об этом надо сказать, а не
--     считать её нулём;
--   * ограничения продажи - вещь, которую нельзя выставить, продать нельзя;
--   * прибыль ПОСЛЕ сбора аукциона, а не до.
--
-- ЧЕГО ВНЕШНИЕ БАЗЫ НЕ ЗНАЮТ, И ЭТО ПРИХОДИТСЯ ГОВОРИТЬ ВСЛУХ. В пакете
-- Polestar_Codex поле `limited` («осталось N штук») не заполнено НИ У ОДНОЙ из
-- 7219 записей о торговцах, а у 210 записей нет самой цены. Значит, из Codex
-- нельзя узнать, постоянный это товар или штучный. Выдать штучный за постоянный
-- источник - это отправить игрока в другую зону за товаром, которого там уже
-- нет, поэтому:
--   * если мы стояли у этого торговца сами, то запись о цене у нас есть только
--     для товара с НЕОГРАНИЧЕННЫМ запасом (Price:RecordMerchant отбрасывает
--     ограниченный) - такой товар можно называть постоянным;
--   * если не стояли, совет честно говорит, что наличие не проверялось.
--
-- Никакой автоматизации: аддон ничего не покупает и не выставляет.
local ADDON, ns = ...

local U = ns.Util
local Api = ns.Api
local CONF = ns.CONF

local VA = {}
ns.VendorArbitrage = VA

-- Ниже этой прибыли за штуку советовать не стоит: беготня дороже.
VA.MIN_PROFIT_PER_UNIT = 500      -- 5 серебра
-- И ниже этой доли от цены покупки - тоже: 10% маржи на товаре за 50 золотых
-- выглядит заманчиво, но это 5 золотых риска ради 5 золотых прибыли.
VA.MIN_MARGIN_SHARE = 0.25
-- Сколько предметов осматривать за пересчёт. Ограничитель, а не оптимизация:
-- обойти 10 621 предмет внешней базы на каждом пересчёте нельзя.
VA.MAX_CANDIDATES = 400

-- ПОТОЛОК ПРАВДОПОДОБИЯ НАЦЕНКИ ------------------------------------------
--
-- Живой прогон выдал шесть карточек с наценкой 419%..2433%, все к одному NPC,
-- и все они были ошибкой данных, а не кладом. Нужен тот же механизм, что уже
-- стоит у выручки против цены торговца (Risk.VENDOR_RATIO_NOTE = 100,
-- VENDOR_RATIO_LIMIT = 1000): «упомянуть» - не то же самое, что «не поверить».
--
-- ОТКУДА ЧИСЛА. Два независимых обоснования, и они сходятся.
--
--   1. ИЗ САМОЙ ИГРЫ. Торговец продаёт примерно вчетверо дороже, чем выкупает
--      (Price.VENDOR_MARKUP = 4). Это и есть масштаб разрыва, который игра
--      создаёт своими же ценами. Разрыв между прилавком и аукционом шире
--      этого масштаба никто не оставит: товар с фиксированной ценой выкупают
--      и перевыставляют, пока разница не закроется.
--
--   2. ИЗ ДАННЫХ ИГРОКА. В его файлах есть 44 предмета, у которых известны ОБА
--      числа - цена, которую торговец просил (кеш цен торговцев Auctionator,
--      500 записей) и цена аукциона (своя история цен, 447 предметов).
--      Распределение отношения «аукцион / торговец» по этим 44 парам:
--         x1..x2   - 27 пар      x4..x8   - 1 пара (максимум x4.6)
--         x2..x4   - 2 пары      выше x8  - НИ ОДНОЙ
--      То есть на настоящем рынке этого сервера рынок ни разу не платил больше
--      пяти цен торговца.
--
-- Отсюда:
--   MARKUP_NOTE  = 2 наценки игры = 8  - выше всего, что когда-либо
--      наблюдалось (максимум 4.6), но ещё не невозможно: упоминаем и снимаем
--      ступень достоверности.
--   MARKUP_LIMIT = 5 наценок игры = 20 - вчетверо шире самого широкого
--      наблюдённого разрыва. Такому числу мы не верим: это дефект данных.
--
-- Наценка здесь - это ВЫРУЧКА, ДЕЛЁННАЯ НА ЦЕНУ ПОКУПКИ (revenue / ask), а не
-- маржа: маржа 2270% и наценка x23.7 - одно и то же число, сказанное дважды.
VA.MARKUP_NOTE = 8
VA.MARKUP_LIMIT = 20

-- Доля, после которой советы ветки считаются «сошедшимися на одном источнике».
-- Больше половины - это уже не совпадение: у восьми карточек живого прогона
-- семь вели к одному торговцу.
VA.CONCENTRATION_SHARE = 0.5
-- Меньше этого числа советов концентрацию не считаем: «2 из 2» или «1 из 1»
-- у одного торговца - это нормально, а не подозрительно.
VA.CONCENTRATION_MIN = 3

-- Откуда берутся кандидаты ------------------------------------------------
--
-- НЕ ИЗ ОБХОДА ВСЕЙ БАЗЫ. Кандидат - это предмет, про который мы уже знаем
-- две вещи: сколько за него просит торговец и сколько дают на аукционе.
-- Таких источников три, и все они уже наполнены к моменту вызова:
--   1. наши собственные записи о торговцах (стояли и видели цену);
--   2. цены торговцев из чужого кеша (Auctionator их тоже собирает);
--   3. список торговцев из Data/ForeverSource.lua - материалы, которые
--      портняжник и зачарователь покупают за деньги.
function VA:Candidates()
    local seen, out = {}, {}
    local function add(itemID, where)
        itemID = tonumber(itemID)
        if not itemID or seen[itemID] then return end
        if #out >= VA.MAX_CANDIDATES then return end
        seen[itemID] = true
        out[#out + 1] = { itemID = itemID, from = where }
    end

    -- 1. Свои записи: самый надёжный источник, и единственный, который
    -- доказывает неограниченный запас.
    local cfg = ns.Config and ns.Config:Get() or nil
    for itemID in pairs((cfg and cfg.vendorPrices) or {}) do add(itemID, "own") end

    -- 2. Материалы с известными торговцами из нашего файла данных.
    local FS = ns.ForeverSource
    for itemID in pairs((FS and FS.MAT_VENDORS) or {}) do add(itemID, "foreverSource") end

    -- 3. Codex: предметы, которые кто-то продаёт. Только те, что уже попались
    -- аддону по другому поводу - в сумках, в рецептах, в истории цен; полный
    -- обход базы здесь не делается.
    for _, itemID in ipairs(VA:KnownItems()) do add(itemID, "known") end
    return out
end

-- Предметы, про которые аддон и так знает: реагенты рецептов, содержимое
-- сумок и всё, по чему есть история цен. Это и есть разумный круг поиска.
function VA:KnownItems()
    local set = {}
    local snap = ns.CharacterScanner and ns.CharacterScanner:Get() or nil
    for itemID in pairs((snap and snap.bags) or {}) do set[itemID] = true end
    for _, recipe in ipairs(ns.RecipeBook and ns.RecipeBook:Iterate(function() return true end) or {}) do
        for _, r in ipairs(recipe.reagents or {}) do set[r.itemID] = true end
    end
    local cfg = ns.Config and ns.Config:Get() or nil
    for itemID in pairs((cfg and cfg.priceHistory) or {}) do
        set[tonumber(itemID) or itemID] = true
    end
    local out = {}
    for itemID in pairs(set) do out[#out + 1] = tonumber(itemID) or itemID end
    table.sort(out, function(a, b) return tostring(a) < tostring(b) end)
    return out
end

-- Цена торговца: сколько он ПРОСИТ -----------------------------------------
--
-- Это не то же самое, что Price:Buy: там выбирается самый дешёвый источник из
-- всех, включая аукцион. Здесь нужна именно цена торговца, и нужно знать,
-- откуда она - от этого зависит, можно ли называть товар постоянным.
--   Возвращает copper, conf, source, proven, currencyNote
function VA:VendorAsk(itemID)
    -- 1. ВЕНДОРНЫЙ ПОТОЛОК - У ТОГО, КТО ЗА НЕГО ОТВЕЧАЕТ.
    --
    -- Это своя запись (Price:RecordMerchant кладёт в неё ТОЛЬКО товар с
    -- неограниченным запасом) И кеш цен торговцев Auctionator, который пишется
    -- по тому же правилу его собственным кодом. Второго здесь раньше не было
    -- вовсе: ветка спрашивала свою запись, потом Codex, потом чужой кеш с
    -- непроверенной полярностью - а 561 честная вендорная цена из файла игрока
    -- до неё не доходила ни одна. Перечень источников живёт в
    -- Logic/PriceProvider.lua (Price.CEILING_SOURCES), и второго перечня здесь
    -- нет сознательно: разойдись они - и «постоянный товар» значило бы в двух
    -- ветках разное.
    local Price = ns.PriceProvider
    if Price and Price.VendorCeiling then
        local ceiling, seenBy, conf = Price:VendorCeiling(itemID)
        if ceiling then
            -- Наличие в любом из двух источников доказывает неограниченный
            -- запас, то есть постоянство товара (proven = true). Чьими глазами
            -- оно увидено, говорит VA:StockText по Price:Ceiling.
            return ceiling, conf or CONF.CACHED,
                (seenBy == "own") and "own" or "vendor", true, nil
        end
    end

    -- 2. Codex: цена есть, но про запас он молчит, а у 210 записей нет и цены.
    local sources = Api.CodexItemSources and Api:CodexItemSources(itemID) or nil
    local best, bestNpc, bestFrom, noPrice = nil, nil, nil, false
    for _, src in ipairs(sources or {}) do
        if src.type == "vendor" then
            local cost = tonumber(src.cost)
            if cost and cost > 0 then
                if (not best) or cost < best then
                    best, bestNpc, bestFrom = cost, src.npc, src.from
                end
            else
                -- ЦЕНА НЕ В ЗОЛОТЕ ИЛИ НЕИЗВЕСТНА - И ЭТО НЕ НОЛЬ.
                -- Торговец, берущий спецвалюту (жетоны, репутация), в данных
                -- выглядит как «цена пустая». Считать это бесплатным значило
                -- бы советовать «купи даром и продай» про то, что даром не даётся.
                noPrice = true
                bestNpc = bestNpc or src.npc
            end
        end
    end
    if best then
        -- ПОЛЯРНОСТЬ ПРОВЕРЯЕТСЯ И ЗДЕСЬ, А НЕ ТОЛЬКО У ЧУЖОГО КЕША.
        --
        -- Поле Codex называется `cost` и означает цену продажи - так его
        -- объявляет сам декодер пакета (Polestar/Lookup/Codex.lua: v =
        -- { "vendor", { "npc", "cost", "limited" } }), и на одной записи это
        -- можно проверить снаружи: Gift of Galloping (271871) стоит в пакете
        -- 1 500 000 медяков, то есть 150 золотых, и ровно столько за него
        -- просят по двум отчётам сообщества. Значит единица - медяки, и
        -- полярность у поля правильная.
        --
        -- Но ПРАВИЛЬНОЕ ПОЛЕ - это ещё не правильное число, и проверить его
        -- есть чем, не поверив на слово: ТОРГОВЕЦ НИКОГДА НЕ ПРОДАЁТ ДЕШЕВЛЕ,
        -- ЧЕМ ВЫКУПАЕТ. Цена выкупа лежит в данных самого предмета, и если
        -- «цена продажи» из пакета ниже её, то это не цена продажи - что бы
        -- там ни было написано.
        local ok, why = VA:AskAboveSell(itemID, best)
        if not ok then
            if ns.Diag then ns.Diag:Count("arbitrage.codexPolarityRejected") end
            return nil, CONF.UNKNOWN, "codex", false, why, "vendor-polarity"
        end
        return best, CONF.ESTIMATE, "codex", false, nil, nil, bestNpc, bestFrom
    end
    if noPrice then
        return nil, CONF.UNKNOWN, "codex", false,
            "торговец есть, но цена в данных не указана — скорее всего это"
            .. " не золото, а особая валюта. Нулём я её не считаю"
    end

    -- 3. Чужой кеш цен торговцев - и ЗДЕСЬ ПОЛЯРНОСТЬ РЕШАЕТ ВСЁ.
    --
    -- Число из чужого кеша может означать две противоположные вещи: сколько
    -- торговец ПРОСИТ и сколько он ДАЁТ. Для схемы «купи дешевле - продай
    -- дороже» это разница между советом и убытком: если взять цену выкупа за
    -- цену продажи, аддон насоветует покупать по цене, которой не существует.
    --
    -- Проверяется это не верой, а арифметикой: торговец всегда просит БОЛЬШЕ,
    -- чем даёт, причём заметно (обычная наценка - вчетверо). Поэтому число,
    -- которое не превышает цену выкупа хотя бы вдвое, ценой продажи быть не
    -- может, и такой кандидат отбрасывается.
    local foreign = Api.MastercraftVendorPrice and Api:MastercraftVendorPrice(itemID) or nil
    if foreign and foreign > 0 then
        local ok, why = VA:AskPolarityOK(itemID, foreign)
        if ok then
            return foreign, CONF.ESTIMATE, "vendorForeign", false, nil
        end
        if ns.Diag then ns.Diag:Count("arbitrage.polarityRejected") end
        return nil, CONF.UNKNOWN, "vendorForeign", false, why, "vendor-polarity"
    end
    return nil, CONF.UNKNOWN, "none", false, nil
end

-- Похоже ли число на цену, которую торговец ПРОСИТ.
--
-- Возвращает ok, reason. Три пути, от сильного к слабому:
--   * есть своя запись по этому предмету и она близка - полярность
--     подтверждена нашими собственными глазами;
--   * число заметно больше цены выкупа - значит это не выкуп;
--   * иначе отказ.
--
-- ПОЧЕМУ МИНИМУМ ВДВОЕ. Торговец продаёт примерно вчетверо дороже, чем
-- выкупает (Price.VENDOR_MARKUP). Двойка - половина от этого, то есть запас на
-- скидки за репутацию: в данных игрока все цены ровно 90% от обычной, и такой
-- запас их пропускает, а цену выкупа - нет.
VA.MIN_ASK_OVER_SELL = 2.0

-- Может ли это число быть ценой ПРОДАЖИ: торговец не продаёт дешевле, чем
-- выкупает. Слабее VA:AskPolarityOK намеренно - там решается, цена это продажи
-- или выкупа, и запас нужен двойной; здесь поле уже названо ценой продажи, и
-- проверяется только то, что число не противоречит само себе.
--   Возвращает ok, причина словами.
function VA:AskAboveSell(itemID, price)
    local info = Api:ItemInfo(itemID)
    local sell = info and tonumber(info.sellPrice) or nil
    -- Цены выкупа нет - проверять нечем, и это не повод отказывать: у части
    -- предметов её в игре просто не бывает.
    if not sell or sell <= 0 then return true, nil end
    if price >= sell then return true, nil end
    return false, string.format(
        "цена торговца в данных (%s) ниже цены выкупа у этого же предмета (%s)."
        .. " Торговец не продаёт дешевле, чем выкупает, значит это число -"
        .. " не цена продажи, и перепродажу на нём я не считаю",
        U.money(price), U.money(sell))
end

function VA:AskPolarityOK(itemID, price)
    local own = ns.Config and ns.Config:VendorPrice(itemID) or nil
    if own and own > 0 then
        local ratio = price / own
        if ratio >= 0.8 and ratio <= 1.25 then
            if ns.Diag then ns.Diag:Count("arbitrage.polarityConfirmedByOwn") end
            return true, "совпадает с тем, что я видел сам"
        end
        return false, "чужой кеш расходится с тем, что я видел у торговца сам"
    end
    local info = Api:ItemInfo(itemID)
    local sell = info and tonumber(info.sellPrice) or nil
    if not sell or sell <= 0 then
        -- Цены выкупа не знаем - сравнивать не с чем. Для схемы «купи и
        -- продай» этого недостаточно: ошибка здесь стоит денег.
        return false, "полярность цены проверить нечем: цены выкупа у предмета нет"
    end
    if price >= sell * VA.MIN_ASK_OVER_SELL then
        return true, "больше цены выкупа — похоже на цену продажи"
    end
    return false, "это число не больше цены выкупа вдвое — скорее всего это"
        .. " сколько торговец даёт, а не сколько просит"
end

-- Ограничения продажи -----------------------------------------------------
--
-- Вещь, которую нельзя выставить на аукцион, продать нельзя - и это надо
-- проверить ДО того, как обещать прибыль. Привязка к персонажу читается из
-- данных клиента; «нельзя продавать» у торговых товаров не бывает, но
-- квестовые и привязанные предметы попадаются.
--   Возвращает sellable (bool), reason
VA.BIND_ON_PICKUP = 1
VA.BIND_QUEST = 4

function VA:Sellable(itemID)
    local info = Api:ItemInfo(itemID)
    if not info then return nil, "предмет ещё не в кеше клиента" end
    local bind = tonumber(info.bindType)
    if bind == VA.BIND_ON_PICKUP then
        return false, "привязывается при получении — на аукцион не выставить"
    end
    if bind == VA.BIND_QUEST then
        return false, "квестовый предмет — продать нельзя"
    end
    -- Нулевая цена продажи у торговца сама по себе не запрещает аукцион, но
    -- это признак предмета, который рынок не берёт.
    return true, nil
end

-- Правдоподобие наценки ----------------------------------------------------
--
-- Возвращает nil (наценка в пределах наблюдаемого) или вердикт
-- { code, markup, ask, revenue, text }. Карточку вердикт НЕ убирает: молча
-- съеденный совет - это то самое тихое поведение, от которого аддон отказался.
-- Он понижает достоверность и заставляет карточку сказать о себе правду.
function VA:MarkupVerdict(ask, revenue)
    ask, revenue = tonumber(ask), tonumber(revenue)
    if not (ask and revenue and ask > 0 and revenue > 0) then return nil end
    local markup = revenue / ask
    if markup < VA.MARKUP_NOTE then return nil end
    if markup < VA.MARKUP_LIMIT then
        return {
            code = "markup-note",
            markup = markup, ask = ask, revenue = revenue,
            text = string.format(
                "наценка такого размера (аукцион %s против прилавка %s, в %s)"
                .. " на этом сервере ни разу не наблюдалась: по 44 предметам, где"
                .. " известны обе цены, рынок платил максимум в 4.6 раза больше"
                .. " торговца. Так бывает, но проверьте цену на месте",
                U.money(revenue), U.money(ask), U.times(markup)),
        }
    end
    return {
        code = "markup-impossible",
        markup = markup, ask = ask, revenue = revenue,
        text = string.format(
            "аукцион %s против прилавка %s — это в %s. Торговец с"
            .. " фиксированной ценой такого разрыва не держит: его бы выкупили"
            .. " и перевыставили за час. Значит ошибка в одном из двух чисел, а"
            .. " не найденный клад — скорее всего цена торговца в данных не та",
            U.money(revenue), U.money(ask), U.times(markup)),
    }
end

-- Откуда взялась цена торговца, словами. Нужно затем, что у Codex провенанс
-- бывает разной силы, и «подтверждено одним чьим-то наблюдением» - это не то
-- же самое, что «сошлось у трёх независимых источников».
--
-- Из 16 259 записей о торговцах в поставляемом пакете провенанс «только
-- recordings» стоит у 476, то есть у 2.9%: пометка редкая, и шум она не создаёт.
function VA:AskSourceText(opp)
    if type(opp) ~= "table" then return nil end
    if opp.askSrc == "own" then return nil end
    local from = opp.askFrom
    if type(from) ~= "table" or #from == 0 then return nil end
    if #from > 1 then return nil end
    -- Имя источника («recordings») игроку не говорит ничего и остаётся в
    -- данных карточки (opp.askFrom); на экране - сам факт: источник один.
    return "Цену у торговца подтверждает только один источник данных, а не"
        .. " несколько — на такой цене весь расчёт держится целиком."
end

-- Одна возможность ---------------------------------------------------------

-- Возвращает таблицу возможности или nil с причиной отказа.
function VA:Evaluate(itemID)
    itemID = tonumber(itemID)
    if not itemID then return nil, "no-id" end

    local ask, askConf, askSrc, proven, note, noteCode, askNpc, askFrom =
        VA:VendorAsk(itemID)
    if not ask then
        -- Три разных отказа, и смешивать их нельзя: «цена не в золоте»,
        -- «полярность числа не та» и «цены нет вовсе» требуют разных действий -
        -- первое идёт в заказ данных, второе в воронку как дефект источника,
        -- третье просто означает «торговца не знаем».
        if noteCode == "vendor-polarity" then return nil, "vendor-polarity", note end
        if note then return nil, "vendor-currency", note end
        return nil, "no-vendor-price", nil
    end

    -- Сколько дают на аукционе. Через Price:Sell - то есть уже с вычтенным
    -- сбором и с проверкой по своей истории цен.
    local revenue, revConf, revSrc, revAge, revInfo = ns.PriceProvider:Sell(itemID)
    if not revenue then return nil, "no-market-price" end
    -- ТОЛЬКО РЫНОК. Если «выручка» - это цена торговца, то схема вырождается в
    -- «купи у торговца и продай торговцу», то есть в гарантированный убыток.
    if not ns.PriceProvider:IsMarketSource(revSrc) then
        return nil, "no-market-only-vendor"
    end

    local sellable, sellReason = VA:Sellable(itemID)
    if sellable == false then return nil, "not-sellable", sellReason end

    local profit = revenue - ask
    if profit < VA.MIN_PROFIT_PER_UNIT then return nil, "too-small" end
    if profit / ask < VA.MIN_MARGIN_SHARE then return nil, "thin-margin" end

    local info = Api:ItemInfo(itemID)
    local place = ns.Places and ns.Places:ForItem(itemID) or nil
    -- Торговца может не быть в наших записях, зато он есть в Codex: берём
    -- первого, у кого известны координаты.
    local npcID, npcName
    if not place then
        for _, src in ipairs(Api.CodexItemSources and Api:CodexItemSources(itemID) or {}) do
            if src.type == "vendor" and src.npc then
                local mapID, x, y, name = Api:CodexNpcSpawn(src.npc)
                if mapID and x and y then
                    npcID, npcName = src.npc, name
                    place = {
                        npcID = src.npc, name = name, mapID = mapID, x = x, y = y,
                        zone = Api:MapName(mapID), routable = true,
                        conf = CONF.ESTIMATE, source = "codex",
                    }
                    break
                end
                npcID = npcID or src.npc
            end
        end
    end

    -- НАЦЕНКА И ЕЁ ПРАВДОПОДОБИЕ. Считается ДО достоверности: вердикт на неё
    -- влияет, и порядок здесь не косметика.
    local markupVerdict = VA:MarkupVerdict(ask, revenue)
    -- ЦЕНУ ТОРГОВЦА В ЭТОЙ ИГРЕ НИКТО НЕ ВИДЕЛ, А НАЦЕНКА ВЫШЕ ВСЕГО, ЧТО
    -- НАБЛЮДАЛОСЬ. Тогда это не «стоит упомянуть», а «не верю».
    --
    -- Живая жалоба (маг 31 ур., 2026-11-21): «Купить и перепродать: Лотос
    -- смерти, +10з 80с за штуку» - у торговца «~60с (оценка)», на аукционе
    -- 12з, наценка x19. До потолка x20 не хватило одной единицы, и карточка
    -- стояла в списке с прибылью крупными цифрами и оговоркой в конце строки.
    -- Рядом такие же: Чародейный кристалл, Кристалл Скверны, Зачарованная
    -- кожа. Цена торговца у всех четырёх - из чужой базы (CONF.ESTIMATE), у
    -- прилавка её не видел ни игрок, ни Auctionator.
    --
    -- Порог «упомянуть» (x8) уже выше любой наценки, которую этот сервер
    -- показал на проверенных ценах. За ним непроверенной цене верить нечем:
    -- вердикт становится «не верю», а дальше работает то же, что и для x20 -
    -- достоверность снимается, карточка помечается сомнительной и уходит вниз.
    -- Цена, которую игрок видел сам (askConf выше оценки), сюда не попадает.
    if markupVerdict and markupVerdict.code == "markup-note"
        and askConf == CONF.ESTIMATE then
        markupVerdict = {
            code = "markup-impossible",
            unverifiedAsk = true,
            markup = markupVerdict.markup, ask = ask, revenue = revenue,
            text = string.format(
                "аукцион %s против прилавка %s — это в %s, а цену торговца я"
                .. " взял из чужой базы: в этой игре её у прилавка никто не"
                .. " видел. На проверенных ценах рынок платил максимум в 4.6"
                .. " раза больше торговца. Скорее всего цена торговца в данных"
                .. " не та — проверьте её на месте, прежде чем считать прибыль",
                U.money(revenue), U.money(ask), U.times(markupVerdict.markup)),
        }
    end
    local conf = U.worstConf(askConf, revConf)
    if markupVerdict then
        conf = (markupVerdict.code == "markup-impossible")
            and CONF.UNKNOWN or U.worstConf(conf, CONF.ESTIMATE)
    end
    -- Цена, за которой стоит один источник, тоже снимает ступень: весь расчёт
    -- висит на ней одной.
    local askLone = (askSrc ~= "own" and type(askFrom) == "table" and #askFrom == 1)
        or nil
    if askLone then conf = U.worstConf(conf, CONF.ESTIMATE) end

    return {
        itemID = itemID,
        -- РУССКОЕ НАЗВАНИЕ ИЗ КЛИЕНТА, а не английское из базы: игрок ищет в
        -- игре то, что видит в игре.
        name = (info and info.name) or U.itemFallbackName(itemID),
        link = info and info.link or nil,
        texture = info and info.texture or nil,
        ask = ask, askConf = askConf, askSrc = askSrc,
        askFrom = askFrom, askLone = askLone,
        provenStock = proven,
        -- Чьими глазами увиден потолок: своя запись или кеш Auctionator. Нужно
        -- тексту про запас, и только ему.
        askSeenBy = (ns.PriceProvider and ns.PriceProvider.Ceiling
            and (ns.PriceProvider:Ceiling(itemID) or {}).ceilingSrc) or nil,
        revenue = revenue, revConf = revConf, revSrc = revSrc, revAge = revAge,
        revInfo = revInfo,
        profit = profit,
        marginShare = profit / ask,
        markup = revenue / ask,
        markupVerdict = markupVerdict,
        place = place,
        npcID = place and place.npcID or npcID or askNpc,
        npcName = place and place.name or npcName,
        sellable = sellable,
        sellNote = sellReason,
        conf = conf,
    }
end

-- КОНЦЕНТРАЦИЯ: БОЛЬШИНСТВО СОВЕТОВ ВЕДЁТ К ОДНОМУ ИСТОЧНИКУ ---------------
--
-- Это подозрение само по себе, независимо от того, правдоподобна ли каждая
-- цена по отдельности. В живом прогоне семь из восьми карточек «Купить и
-- перепродать» вели к одному NPC, и все семь были построены на одних и тех же
-- неверных записях - то есть ошибка была не в семи местах, а в одном, и
-- увидеть это можно было только по тому, что советы сошлись.
--
-- Возвращает nil или { npcID, npcName, count, total, share }.
function VA:Concentration(opps)
    if type(opps) ~= "table" then return nil end
    local total = #opps
    if total < VA.CONCENTRATION_MIN then return nil end
    local tally, names = {}, {}
    local unknown = 0
    for _, opp in ipairs(opps) do
        local id = tonumber(opp.npcID)
        if id then
            tally[id] = (tally[id] or 0) + 1
            names[id] = names[id] or opp.npcName
        else
            unknown = unknown + 1
        end
    end
    local topID, topCount = nil, 0
    for id, n in pairs(tally) do
        if n > topCount or (n == topCount and topID and id < topID) then
            topID, topCount = id, n
        end
    end
    if not topID then return nil end
    local share = topCount / total
    if share < VA.CONCENTRATION_SHARE then return nil end
    return {
        npcID = topID,
        npcName = names[topID],
        count = topCount, total = total, share = share,
        unknownSource = unknown,
        text = string.format(
            "%d из %d таких советов ведут к одному торговцу (%s) —"
            .. " значит и ошибка в данных у них может быть одна на всех, а не"
            .. " %s",
            topCount, total, names[topID] and tostring(names[topID])
                or ("#" .. tostring(topID)), VA.IndependentFinds(topCount)),
    }
end

-- «3 независимые находки», «5 независимых находок», «21 независимая находка».
-- Прилагательное согласуется вместе с существительным: раньше оно стояло одной
-- формой при любом числе, и выходило «3 независимых находки».
function VA.IndependentFinds(n)
    n = tonumber(n) or 0
    return n .. " " .. U.plural(n, "независимая находка", "независимые находки",
        "независимых находок")
end

-- Все возможности, лучшие первыми ----------------------------------------

function VA:Opportunities()
    local out = {}
    local funnel = ns.Diag and ns.Diag:Funnel("vendorArbitrage") or nil
    local currencySkipped = 0
    for _, cand in ipairs(VA:Candidates()) do
        local item = { itemID = cand.itemID, name = tostring(cand.itemID) }
        if funnel then funnel:In(item) end
        local opp, why, detail = VA:Evaluate(cand.itemID)
        if opp then
            out[#out + 1] = opp
        elseif funnel then
            funnel:Drop(why or "unknown", item, detail)
        end
        if why == "vendor-currency" then
            currencySkipped = currencySkipped + 1
            if ns.Diag then
                ns.Diag:Want("itemsNoPrice", cand.itemID, "vendor-currency",
                    { note = "у торговца цена не в золоте или не указана" })
            end
        end
    end
    table.sort(out, function(a, b)
        if a.profit ~= b.profit then return a.profit > b.profit end
        return a.itemID < b.itemID
    end)
    if funnel then funnel:Finish(#out) end
    VA.lastCurrencySkipped = currencySkipped

    -- Концентрация считается по ВСЕМУ списку возможностей, а не по тем, что
    -- влезли на экран: ошибка в данных не становится меньше от того, что
    -- карточек показано пять, а не семь.
    local conc = VA:Concentration(out)
    VA.lastConcentration = conc
    if conc then
        for _, opp in ipairs(out) do
            if tonumber(opp.npcID) == conc.npcID then
                opp.concentration = conc
                opp.conf = U.worstConf(opp.conf, CONF.ESTIMATE)
            end
        end
        if ns.Diag then
            ns.Diag:Count("arbitrage.concentrated")
        end
    end
    return out
end

-- Текст для карточки ------------------------------------------------------

-- Где купить, словами. Отдельно, потому что это самая частая причина, по
-- которой совет оказывается бесполезным: «купи дешевле» без адреса.
function VA:WhereText(opp)
    if opp.place and opp.place.routable then
        local hint = ns.Places and ns.Places:CardHint(opp.place) or nil
        return "Торговец: " .. (hint or (tostring(opp.place.name or "?")
            .. (opp.place.zone and (", " .. opp.place.zone) or ""))) .. "."
    end
    if opp.npcName or opp.npcID then
        return "Торговец: " .. (opp.npcName or ("#" .. tostring(opp.npcID)))
            .. " — где он стоит, я не знаю: координат на него нет ни у меня,"
            .. " ни во внешних базах."
    end
    return "У кого именно это купить, я не знаю — цену помню, торговца нет."
end

-- Постоянный товар или штучный. Это та самая вещь, которую внешние базы не
-- знают, и поэтому она пишется словами, а не подразумевается.
function VA:StockText(opp)
    -- ЦЕНУ ЗАПИСАЛ AUCTIONATOR, А НЕ Я - И СКАЗАТЬ НАДО ИМЕННО ЭТО.
    --
    -- Запас в его кеше тоже доказан (он пишет только неограниченный), но имени
    -- торговца там нет: кеш хранит цену по предмету, а не по тому, у кого
    -- стояли. Обещать «я сам видел» за чужое наблюдение нельзя, и выдумывать
    -- торговца к нему - тоже.
    if opp.provenStock and opp.askSeenBy == "cache" then
        return "Эту цену записал Auctionator, когда вы открывали окно торговца,"
            .. " и только для неограниченного запаса — товар постоянный."
            .. " У какого именно торговца, он не запомнил."
    end
    if opp.provenStock then
        return "Я сам стоял у этого торговца и видел неограниченный запас —"
            .. " товар постоянный, можно брать сколько нужно."
    end
    return "Наличие я не проверял: у этого торговца я не стоял, а внешние базы"
        .. " про запас ничего не говорят. Может оказаться штучным товаром —"
        .. " посмотрите на месте."
end

return VA
