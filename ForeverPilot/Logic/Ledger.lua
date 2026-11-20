-- ForeverPilot / Logic/Ledger.lua
--
-- СВОЯ КНИГА ЗАКУПОК: что игрок реально заплатил за предмет и когда.
--
-- ЗАЧЕМ ОНА ПОЯВИЛАСЬ. Себестоимость материалов до этого считалась по
-- MastercraftDB.costs - книге закупок другого аддона. Схема там
-- недокументированная (её разобрали по файлу игрока), аддон обновляется раз в
-- пару дней, и его лицензия не разрешает брать данные. Сменят формат - у нас
-- молча отвалятся все цены, и узнаем мы об этом от игрока. Подробнее -
-- ns.FOREIGN_BOOK в Core/Const.lua.
--
-- ОТКУДА БЕРУТСЯ ЗАПИСИ. Игра не присылает события «игрок купил предмет за
-- столько». Прислать она может только две вещи по отдельности: деньги
-- изменились (PLAYER_MONEY) и сумки изменились (BAG_UPDATE_DELAYED). Поэтому
-- книга работает сверкой: берётся снимок «деньги + сумки» до, снимок после, и
-- если деньги убыли ровно настолько, насколько прибыл ОДИН предмет, - это
-- покупка, и цена за штуку известна точно.
--
-- И ГЛАВНОЕ ПРАВИЛО: ЕСЛИ СВЕРКА НЕОДНОЗНАЧНА - НИЧЕГО НЕ ЗАПИСЫВАЕТСЯ.
-- Выдуманная цена в книге закупок хуже пустой книги: пустая говорит «не знаю»,
-- а выдуманная врёт про себестоимость, и врёт потом во всех советах про
-- заработок. Каждый отказ назван словами (Ledger.SKIP) и посчитан, так что
-- «книга ничего не видит» отличимо от «книге нечего было видеть».
--
-- Сверка привязана к КОНТЕКСТУ: записывается только то, что случилось при
-- открытом окне торговца или аукциона. Без этого добыча, награда за задание и
-- почта попадали бы в книгу как покупки по неизвестной цене.
--
-- ЧЕГО КНИГА НЕ ВИДИТ - перечислено в Ledger.GAPS и показывается человеку.
-- Ничего не автоматизируется: события только читаются.
local ADDON, ns = ...

local U = ns.Util
local Api = ns.Api
local CONF = ns.CONF

local Ledger = {}
ns.Ledger = Ledger

Ledger.KIND = { BUY = "buy", SELL = "sell" }
Ledger.WHERE = { VENDOR = "vendor", AUCTION = "auction" }

-- ПОЧЕМУ СВЕРКА ОТКАЗАЛАСЬ. Фразами, а не кодами: эти же строки идут в отчёт
-- для человека, и «MANY_ITEMS» ему ничего не говорит.
Ledger.SKIP = {
    NO_CONTEXT = "окно торговца или аукциона не было открыто — за такое я не ручаюсь",
    NO_MONEY   = "деньги не изменились, значит платежа не было",
    NO_ITEMS   = "деньги изменились, а содержимое сумок нет — за что платили, не знаю",
    MANY_ITEMS = "за один раз изменилось несколько предметов — чей это был платёж, я не знаю",
    MISMATCH   = "деньги и предметы поехали в одну сторону — это не покупка и не продажа",
    NO_CLOCK   = "часы сервера не ответили, а запись без времени бесполезна",
}

-- ЧЕГО КНИГА НЕ ВИДИТ, И ЭТО НАДО ГОВОРИТЬ ВСЛУХ.
Ledger.GAPS = {
    "лот с аукциона, который приходит почтой, а не сразу в сумки: деньги ушли,"
        .. " а предмет появится позже — такую покупку я записать не могу",
    "две разные покупки подряд, слившиеся в одно изменение: тогда я не знаю,"
        .. " за который предмет сколько отдано, и не записываю ни одну",
    "покупку у другого игрока из рук в руки: окно обмена — не торговец и не"
        .. " аукцион, цену там никто не называет",
}

-- НА ЧЁМ КНИГА ДЕРЖИТСЯ. Все эти события аддон уже слушает, и каждое Events
-- проверяет на существование через C_EventUtils.IsEventValid - то есть ни одно
-- имя здесь не выдумано и ни одно не подписано вслепую.
Ledger.NEEDS_EVENTS = {
    "PLAYER_MONEY", "BAG_UPDATE_DELAYED",
    "MERCHANT_SHOW", "MERCHANT_UPDATE", "MERCHANT_CLOSED",
    "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED",
    "PLAYER_INTERACTION_MANAGER_FRAME_SHOW",
}

-- Насколько старую свою запись ещё можно считать ценой «сейчас». Сам факт
-- «я заплатил столько» не стареет никогда; стареет только вывод «значит и
-- сегодня столько же».
Ledger.PRICE_FRESH_SECONDS = 14 * 86400

Ledger.pending = nil        -- снимок мира до сверки
Ledger.atVendor = false
Ledger.atAuction = false
Ledger.bound = false

-- Снимок мира ------------------------------------------------------------

-- Деньги и сумки одной таблицей. Банк сюда НЕ входит: покупка у торговца
-- кладёт предмет в сумки, а банк в этот момент меняться не может, зато
-- читается он из кеша и мог бы дать ложное изменение.
function Ledger:World()
    if not (Api.Money and Api.BagCounts) then return nil end
    local money, moneyConf = Api:Money()
    local bags, bagConf = Api:BagCounts()
    if type(money) ~= "number" or type(bags) ~= "table" then return nil end
    -- СНИМОК БЕРЁТСЯ ТОЛЬКО КОГДА КЛИЕНТ ОТВЕТИЛ ТОЧНО, и это не формальность.
    --
    -- Api:BagCounts без функций чтения сумок отдаёт ПУСТУЮ таблицу с пометкой
    -- «неизвестно». Если принять её за снимок, то у игрока, у которого в
    -- сумках один вид предмета, «сумки опустели» плюс «денег прибыло» сложится
    -- в правдоподобную продажу - по неправильному количеству и навсегда.
    -- Пустой ответ и пустые сумки различимы только по этой пометке.
    if moneyConf ~= ns.CONF.EXACT or bagConf ~= ns.CONF.EXACT then return nil end
    local items = {}
    for id, qty in pairs(bags) do items[id] = qty end
    return { money = money, items = items }
end

-- Запомнить состояние мира. `why` идёт только в диагностику.
function Ledger:Remember(why)
    local world = self:World()
    if not world then
        if ns.Diag then
            ns.Diag:Call("книга закупок: снимок мира", false,
                "деньги или сумки клиент не отдал")
        end
        return false
    end
    world.why = why
    world.at = Api.Now and Api:Now() or 0
    self.pending = world
    return true
end

function Ledger:Reset()
    self.pending = nil
    self.atVendor = false
    self.atAuction = false
end

-- Что сейчас за контекст: у торговца, у аукциона, или нигде.
function Ledger:Context()
    if self.atVendor then return Ledger.WHERE.VENDOR end
    if self.atAuction then return Ledger.WHERE.AUCTION end
    -- Окно аукциона может отслеживать AuctionMoment - он подписан на тот же
    -- сигнал. Спрашиваем его, чтобы два места не расходились.
    if ns.AuctionMoment and ns.AuctionMoment.atAuction then
        return Ledger.WHERE.AUCTION
    end
    return nil
end

-- Сверка ------------------------------------------------------------------

-- Что изменилось в сумках между двумя снимками.
-- Возвращает два списка: что прибыло и что убыло, каждый как { itemID, qty }.
function Ledger:BagDiff(before, after)
    local up, down = {}, {}
    local seen = {}
    local function consider(id)
        if seen[id] then return end
        seen[id] = true
        local was = tonumber((before.items or {})[id]) or 0
        local now = tonumber((after.items or {})[id]) or 0
        local d = now - was
        if d > 0 then up[#up + 1] = { itemID = id, qty = d }
        elseif d < 0 then down[#down + 1] = { itemID = id, qty = -d } end
    end
    for id in pairs(before.items or {}) do consider(id) end
    for id in pairs(after.items or {}) do consider(id) end
    local function byID(a, b) return a.itemID < b.itemID end
    table.sort(up, byID)
    table.sort(down, byID)
    return up, down
end

-- ЕДИНСТВЕННОЕ МЕСТО, КОТОРОЕ РЕШАЕТ «ЭТО БЫЛА ПОКУПКА».
--
-- Чистая функция: два снимка, контекст, время. Ничего не читает у клиента и
-- ничего не пишет - поэтому её можно проверить на столе целиком, и именно она
-- проверена в Tests/test_ledger.lua.
--
-- Возвращает entry или nil + причину отказа (одна из Ledger.SKIP).
function Ledger:Observe(before, after, context, now)
    if type(before) ~= "table" or type(after) ~= "table" then
        return nil, Ledger.SKIP.NO_ITEMS
    end
    if context ~= Ledger.WHERE.VENDOR and context ~= Ledger.WHERE.AUCTION then
        return nil, Ledger.SKIP.NO_CONTEXT
    end
    now = tonumber(now)
    if not now or now <= 0 then return nil, Ledger.SKIP.NO_CLOCK end

    local moneyBefore = tonumber(before.money)
    local moneyAfter = tonumber(after.money)
    if not (moneyBefore and moneyAfter) then return nil, Ledger.SKIP.NO_MONEY end
    local dMoney = moneyAfter - moneyBefore
    if dMoney == 0 then return nil, Ledger.SKIP.NO_MONEY end

    local up, down = self:BagDiff(before, after)
    if #up == 0 and #down == 0 then return nil, Ledger.SKIP.NO_ITEMS end
    -- Несколько предметов за один раз - значит разложить платёж между ними
    -- нечем. Разложить «поровну» было бы выдумкой, а выдумка здесь дороже
    -- отказа: она ляжет в себестоимость и останется там навсегда.
    if #up > 1 or #down > 1 or (#up == 1 and #down == 1) then
        return nil, Ledger.SKIP.MANY_ITEMS
    end

    local kind, change
    if dMoney < 0 then
        -- Денег стало меньше. Покупка - это когда предмет при этом ПРИБЫЛ.
        if #up ~= 1 then return nil, Ledger.SKIP.MISMATCH end
        kind, change = Ledger.KIND.BUY, up[1]
    else
        -- Денег стало больше. Продажа - это когда предмет УБЫЛ.
        if #down ~= 1 then return nil, Ledger.SKIP.MISMATCH end
        kind, change = Ledger.KIND.SELL, down[1]
    end

    local copper = math.abs(dMoney)
    local qty = tonumber(change.qty) or 0
    if qty <= 0 or copper <= 0 then return nil, Ledger.SKIP.MISMATCH end
    local unit = copper / qty
    -- Цена за штуку меньше медяка - это не цена: клиент считает в медяках, и
    -- такое может прийти только из сложения двух разных событий.
    if unit < 1 then return nil, Ledger.SKIP.MANY_ITEMS end

    return {
        itemID = change.itemID,
        kind = kind,
        where = context,
        qty = qty,
        copper = copper,
        unit = U.round(unit),
        t = now,
    }
end

-- Записать сверенную сделку в SavedVariables.
function Ledger:Note(entry)
    if type(entry) ~= "table" then return false end
    local ok = ns.Config:LedgerAdd(entry)
    if ok and ns.Diag then
        ns.Diag:Count("ledger." .. tostring(entry.kind))
    end
    return ok
end

-- СВЕРИТЬ ЖИВОЙ МИР С ЗАПОМНЕННЫМ и, если вышло однозначно, записать.
--
-- Новое состояние запоминается ВСЕГДА, даже когда записать не удалось: иначе
-- одна неоднозначная перемена испортит все последующие сверки, сравнивая их с
-- давно устаревшим снимком.
function Ledger:Settle(context)
    local before = self.pending
    local after = self:World()
    if not after then return nil, Ledger.SKIP.NO_ITEMS end
    if not before then
        self.pending = after
        return nil, Ledger.SKIP.NO_ITEMS
    end
    context = context or self:Context()
    local now = Api.ServerTime and Api:ServerTime() or 0

    local entry, why = self:Observe(before, after, context, now)
    after.at = Api.Now and Api:Now() or 0
    self.pending = after

    if entry then
        self:Note(entry)
        local meta = ns.Config:LedgerMeta()
        meta.observed = (meta.observed or 0) + 1
        return entry
    end
    -- «Ничего не изменилось» - это не отказ, а обычное состояние мира: окно
    -- торговца присылает MERCHANT_UPDATE и просто при листании страниц.
    if why ~= Ledger.SKIP.NO_MONEY then ns.Config:LedgerSkip(why) end
    return nil, why
end

-- Что игрок заплатил ------------------------------------------------------

local function sideAverage(side)
    if type(side) ~= "table" then return nil end
    local qty, copper = tonumber(side.qty) or 0, tonumber(side.copper) or 0
    if qty <= 0 or copper <= 0 then return nil end
    -- СРЕДНЯЯ ВЗВЕШЕНА ПО КОЛИЧЕСТВУ, А НЕ ПО ЗАПИСЯМ. Одна штука за золотой и
    -- девять по медяку - это не «пополам»: заплачено столько, сколько
    -- заплачено, и делить надо на все десять штук.
    return copper / qty, qty, copper
end

-- СКОЛЬКО ИГРОК ОТДАЛ ЗА ШТУКУ. Это факт, а не оценка: деньги ушли из кошелька
-- и мы это видели. Поэтому достоверность - CONF.EXACT, независимо от возраста:
-- возраст важен для вопроса «а сегодня столько же?», и на него отвечает
-- Ledger:UnitCost, а не эта функция.
--
-- Возвращает copper, conf, info { n, qty, copper, firstT, lastT, age, minUnit, maxUnit }
function Ledger:Paid(itemID)
    local bucket = ns.Config:LedgerFor(itemID)
    if not bucket then return nil, CONF.UNKNOWN, nil end
    local avg, qty, copper = sideAverage(bucket.buy)
    if not avg then return nil, CONF.UNKNOWN, nil end
    local side = bucket.buy
    local now = Api.ServerTime and Api:ServerTime() or 0
    return U.round(avg), CONF.EXACT, {
        n = side.n, qty = qty, copper = copper,
        firstT = side.firstT, lastT = side.lastT,
        age = (now > 0 and side.lastT) and (now - side.lastT) or nil,
        minUnit = side.minUnit, maxUnit = side.maxUnit,
        where = side.where,
    }
end

-- И обратная сторона: за сколько игрок это ПРОДАВАЛ. Отдельно от покупок, и
-- смешивать их нельзя - иначе собственная продажа станет себестоимостью.
function Ledger:Received(itemID)
    local bucket = ns.Config:LedgerFor(itemID)
    if not bucket then return nil, CONF.UNKNOWN, nil end
    local avg, qty, copper = sideAverage(bucket.sell)
    if not avg then return nil, CONF.UNKNOWN, nil end
    local side = bucket.sell
    local now = Api.ServerTime and Api:ServerTime() or 0
    return U.round(avg), CONF.EXACT, {
        n = side.n, qty = qty, copper = copper,
        firstT = side.firstT, lastT = side.lastT,
        age = (now > 0 and side.lastT) and (now - side.lastT) or nil,
    }
end

-- ТА ЖЕ ЦЕНА, НО КАК ОТВЕТ НА «СКОЛЬКО ЭТО СТОИТ СЕЙЧАС». Здесь возраст уже
-- решает: своя запись двухнедельной давности - всё ещё лучшее, что у нас есть,
-- но выдавать её за сегодняшнюю цену нельзя.
--
-- Возвращает copper, conf, ageSeconds - ровно в той форме, которую ждёт
-- PriceProvider от любого своего источника.
function Ledger:UnitCost(itemID)
    local paid, _, info = self:Paid(itemID)
    if not paid then return nil, CONF.UNKNOWN end
    local age = info and info.age or nil
    local conf
    if age == nil then
        conf = CONF.ESTIMATE
    elseif age < (ns.PRICE_STALE_SECONDS or 172800) then
        conf = CONF.CACHED
    elseif age < Ledger.PRICE_FRESH_SECONDS then
        conf = CONF.ESTIMATE
    else
        conf = CONF.ESTIMATE
    end
    return paid, conf, age
end

function Ledger:Has(itemID)
    return (self:Paid(itemID) ~= nil)
end

function Ledger:Count()
    local meta = ns.Config:LedgerMeta()
    return tonumber(meta.entries) or 0
end

-- Себестоимость -----------------------------------------------------------

local function reagentsOf(recipe)
    if type(recipe) ~= "table" then return {} end
    local book = ns.RecipeBook
    if book and book.MergedReagents then return book:MergedReagents(recipe) end
    return recipe.reagents or {}
end

-- ФАКТИЧЕСКАЯ себестоимость одного крафта: только по своей книге, без единой
-- оценки. Нет своей цены хотя бы на один материал - ответа нет вовсе.
--
-- Это не придирчивость, а смысл слова «фактическая»: сумма, где половина
-- слагаемых угадана, фактом не является, и называть её так нельзя. Для
-- смешанного ответа есть Ledger:MaterialCost ниже, и он честно говорит долю.
--
-- Возвращает copper, conf, coverage { known, total, missing = { itemID, ... } }
function Ledger:ActualMaterialCost(recipe)
    local reagents = reagentsOf(recipe)
    local coverage = { known = 0, total = #reagents, missing = {} }
    if #reagents == 0 then return nil, CONF.UNKNOWN, coverage end
    local total = 0
    for _, r in ipairs(reagents) do
        local paid = self:Paid(r.itemID)
        if paid then
            coverage.known = coverage.known + 1
            total = total + paid * (tonumber(r.qty) or 0)
        else
            coverage.missing[#coverage.missing + 1] = r.itemID
        end
    end
    if coverage.known < coverage.total then return nil, CONF.UNKNOWN, coverage end
    return U.round(total), CONF.EXACT, coverage
end

-- СМЕШАННАЯ себестоимость: своя цена там, где она есть, цена покупки там, где
-- её нет. Достоверность - по худшему слагаемому, то есть при любой подмешанной
-- оценке весь ответ становится оценкой. Доля своих данных называется, чтобы на
-- экране было видно, насколько это наши числа.
function Ledger:MaterialCost(recipe, priceProvider)
    local reagents = reagentsOf(recipe)
    local coverage = { known = 0, total = #reagents, missing = {} }
    if #reagents == 0 then return nil, CONF.UNKNOWN, coverage end
    local price = priceProvider or ns.PriceProvider
    -- ТО, ЧЕГО НЕТ В КНИГЕ, СПРАШИВАЕТСЯ У ПЛАНИРОВЩИКА, А НЕ У ЦЕН НАПРЯМУЮ.
    --
    -- Иначе на одной карточке оказываются ДВЕ разные себестоимости: «материалы
    -- 59с 4м» от планировщика (он умеет «скрафтить промежуточное, если так
    -- дешевле») и «себестоимость 59с 84м» отсюда (прямая покупка всего).
    -- Расхождение было в 80 медяков - и это ровно та мелочь, из-за которой
    -- игрок перестаёт верить обоим числам.
    local planner = ns.CraftingPlanner
    local function fallback(itemID)
        if planner and planner.UnitCost and planner.book then
            return planner:UnitCost(itemID, 0, {})
        end
        return price:Buy(itemID)
    end
    local total, conf = 0, CONF.EXACT
    for _, r in ipairs(reagents) do
        local qty = tonumber(r.qty) or 0
        local paid = self:Paid(r.itemID)
        if paid then
            coverage.known = coverage.known + 1
            total = total + paid * qty
        else
            coverage.missing[#coverage.missing + 1] = r.itemID
            local buy, buyConf = fallback(r.itemID)
            if not buy then return nil, CONF.UNKNOWN, coverage end
            total = total + buy * qty
            conf = U.worstConf(conf, buyConf or CONF.UNKNOWN)
        end
    end
    -- Хоть одно чужое число - и это уже не факт, а оценка. Даже если
    -- подмешанная цена пришла с пометкой «точно»: точной она была для вопроса
    -- «сколько просят», а не для вопроса «сколько я отдал».
    if coverage.known < coverage.total then
        conf = U.worstConf(conf, CONF.ESTIMATE)
    end
    return U.round(total), conf, coverage
end

-- Безубыточность ----------------------------------------------------------

-- НИЖЕ ЭТОЙ ЦЕНЫ КРАФТ НА ПРОДАЖУ ИДЁТ В МИНУС.
--
-- Считается так: себестоимость одной штуки - это материалы на крафт, делённые
-- на выход рецепта. Аукцион забирает свой сбор с ПРОДАЖНОЙ цены, значит
-- выставлять надо выше себестоимости ровно настолько, чтобы после сбора
-- осталась себестоимость:
--
--     выставить >= себестоимость / (1 - сбор)
--
-- Делить, а не прибавлять сбор к себестоимости: сбор берётся с той цены,
-- которую выставили, а не с той, которую мы хотели получить. На пяти процентах
-- разница маленькая, но она всегда в минус игроку, и именно такие «маленькие
-- разницы» превращают «заработал» в «поработал бесплатно».
--
-- Возвращает nil, когда себестоимость назвать нечем, и ничего не выдумывает.
function Ledger:Breakeven(recipe, priceProvider)
    if type(recipe) == "number" and ns.RecipeBook then
        recipe = ns.RecipeBook:Get(recipe)
    end
    if type(recipe) ~= "table" then return nil end
    -- Чары не продаются: предмета нет, и продавать нечего. Это «так нельзя», а
    -- не «не знаю», и путать их здесь особенно дорого.
    if not recipe.output then return nil end

    local price = priceProvider or ns.PriceProvider
    local cost, conf, coverage = self:ActualMaterialCost(recipe)
    local source = "ledger"
    if not cost then
        cost, conf, coverage = self:MaterialCost(recipe, price)
        source = (coverage and coverage.known > 0) and "mixed" or "market"
    end
    if not cost then return nil end

    local qty = math.max(1, tonumber(recipe.outputQty) or 1)
    local unitCost = cost / qty
    local cut = price.AH_CUT or 0
    if cut >= 1 then cut = 0 end
    local listPrice = unitCost / (1 - cut)

    return {
        unitCost = U.round(unitCost),
        craftCost = U.round(cost),
        outputQty = qty,
        listPrice = U.round(listPrice),
        cut = cut,
        conf = conf,
        source = source,
        coverage = coverage,
        -- Торговец даёт за вещь столько всегда, и это пол, ниже которого
        -- продавать на аукционе просто незачем.
        vendorFloor = (function()
            local info = Api.ItemInfo and Api:ItemInfo(recipe.output) or nil
            local sell = info and tonumber(info.sellPrice) or nil
            return (sell and sell > 0) and sell or nil
        end)(),
    }
end

-- И ТО ЖЕ САМОЕ СЛОВАМИ, ПРЯМО.
--
-- «Безубыточность 2з 10с» игроку ничего не говорит. Сказать надо то, что он
-- должен сделать и чего не должен: ниже этой цены он продаёт в минус.
function Ledger:BreakevenText(recipe, priceProvider)
    local be = self:Breakeven(recipe, priceProvider)
    if not be then
        return "Цену безубыточности не назову: себестоимость материалов"
            .. " посчитать нечем."
    end
    local bits = {}
    bits[#bits + 1] = "Себестоимость штуки — " .. U.money(be.unitCost)
        .. (be.source == "ledger" and " (по вашим покупкам)"
            or (be.source == "mixed" and " (часть по вашим покупкам, часть — оценка)"
                or " (оценка: своих покупок по материалам нет)"))
        .. "."
    bits[#bits + 1] = "Выставлять дешевле " .. U.money(be.listPrice)
        .. " — продавать в минус: аукцион забирает " .. U.pct(be.cut)
        .. " с цены продажи."
    if be.vendorFloor and be.vendorFloor > 0 then
        bits[#bits + 1] = "Торговец за неё даёт " .. U.money(be.vendorFloor)
            .. " и это без сбора."
    end
    return table.concat(bits, " ")
end

-- Что я заплатил против того, что на рынке -------------------------------

Ledger.SAME_TOLERANCE = 0.05   -- ближе пяти процентов считаем «столько же»

-- Возвращает nil, когда своей цены по предмету нет: сравнивать нечего, и
-- выдумывать вторую половину сравнения нельзя.
--
-- verdict:
--   "dearer"    - сейчас на рынке дороже, чем игрок брал
--   "cheaper"   - сейчас дешевле
--   "same"      - примерно столько же
--   "no_market" - рыночной цены нет вовсе (это НЕ «цены равны»)
function Ledger:PaidVsMarket(itemID, priceProvider)
    local paid, _, info = self:Paid(itemID)
    if not paid then return nil end
    local price = priceProvider or ns.PriceProvider

    -- Спрашиваем рынок, а не свою же книгу: иначе сравнение сравнивает число
    -- с самим собой. Поэтому берётся аукционная цена напрямую.
    local market, marketConf, marketAge = Api:AuctionPrice(itemID)
    local marketSrc = market and "auctionator" or nil
    if not market then
        local fp, fc, fa = Api:MastercraftObservedPrice(itemID)
        if fp then market, marketConf, marketAge, marketSrc = fp, fc, fa, "foreign" end
    end

    local out = {
        itemID = itemID,
        paid = paid,
        paidAge = info and info.age or nil,
        paidQty = info and info.qty or nil,
        paidTimes = info and info.n or nil,
        market = market,
        marketConf = marketConf,
        marketAge = marketAge,
        marketSrc = marketSrc,
        foreignMarket = (marketSrc == "foreign") or false,
    }
    if not market then
        out.verdict = "no_market"
        out.text = "Вы платили " .. U.priceText(paid, CONF.EXACT, out.paidAge)
            .. ". Сравнить не с чем: " .. U.void(ns.VOID.NO_PRICE) .. "."
        return out
    end
    out.diff = U.round(market - paid)
    out.ratio = market / paid
    local drift = math.abs(market - paid) / paid
    if drift <= Ledger.SAME_TOLERANCE then
        out.verdict = "same"
    elseif market > paid then
        out.verdict = "dearer"
    else
        out.verdict = "cheaper"
    end

    local tail
    if out.verdict == "same" then
        tail = "сейчас примерно столько же"
    elseif out.verdict == "dearer" then
        tail = "сейчас дороже — " .. U.priceText(market, marketConf, marketAge)
            .. ", это " .. (U.times(out.ratio) or "дороже") .. " больше"
    else
        tail = "сейчас дешевле — " .. U.priceText(market, marketConf, marketAge)
    end
    out.text = "Вы платили " .. U.priceText(paid, CONF.EXACT, out.paidAge)
        .. ", " .. tail .. "."
    return out
end

-- Подписка ----------------------------------------------------------------

-- Книга слушает те же сигналы, что и всё остальное: отдельных подписок на
-- события она не делает, иначе отчёт Events:Report() перестал бы отвечать на
-- вопрос «на что аддон подписан».
function Ledger:Bind()
    if self.bound then return false end
    self.bound = true
    local Events = ns.Events
    if not Events then return false end

    Events:On("merchant", function(phase)
        if phase == "close" then
            -- Последняя сверка перед закрытием окна: игрок мог купить и сразу
            -- закрыть, и события денег и сумок придут уже после.
            Ledger:Settle(Ledger.WHERE.VENDOR)
            Ledger.atVendor = false
            return
        end
        if not Ledger.atVendor then
            Ledger.atVendor = true
            Ledger:Remember("окно торговца открылось")
            return
        end
        Ledger:Settle(Ledger.WHERE.VENDOR)
    end)

    Events:On("auction", function(what)
        if what == "close" then
            Ledger:Settle(Ledger.WHERE.AUCTION)
            Ledger.atAuction = false
            return
        end
        if what == "open" then
            Ledger.atAuction = true
            Ledger:Remember("аукцион открылся")
            return
        end
        Ledger:Settle(Ledger.WHERE.AUCTION)
    end)

    -- Деньги и сумки. Пересчёт идёт по тем же событиям, и подписываться на них
    -- второй раз незачем: если изменились деньги или сумки, причина уже здесь.
    Events:On("recompute", function(reasons)
        reasons = reasons or {}
        if not (reasons.money or reasons.bags) then return end
        local context = Ledger:Context()
        if not context then
            -- Вне торговца и аукциона запоминаем новое состояние, но не
            -- записываем ничего: добыча и награды - не покупки.
            Ledger:Remember("мир изменился вне торговца и аукциона")
            return
        end
        Ledger:Settle(context)
    end)
    return true
end

-- Отчёт -------------------------------------------------------------------

-- Какие из нужных событий клиент вообще знает и на какие мы подписаны.
-- nil в `exists` - «проверить было нечем», и это не то же самое, что false.
function Ledger:EventHealth()
    local state = (ns.Events and ns.Events.eventState) or {}
    local out, missing = {}, {}
    for _, name in ipairs(Ledger.NEEDS_EVENTS) do
        local st = state[name]
        out[#out + 1] = {
            event = name,
            exists = st and st.exists or nil,
            subscribed = (st and st.subscribed) and true or false,
        }
        if st and st.exists == false then missing[#missing + 1] = name end
    end
    return out, missing
end

function Ledger:Report()
    local meta = ns.Config:LedgerMeta()
    local L = ns.Config:Ledger() or {}
    local items = 0
    for _ in pairs(L.byItem or {}) do items = items + 1 end
    local _, missingEvents = self:EventHealth()

    local gaps = {}
    for _, g in ipairs(Ledger.GAPS) do gaps[#gaps + 1] = g end
    if #missingEvents > 0 then
        gaps[#gaps + 1] = "на этом клиенте нет событий " ..
            table.concat(missingEvents, ", ") .. " — часть покупок я не увижу"
    end

    local skips = {}
    for reason, n in pairs((meta.skips or {})) do
        skips[#skips + 1] = { reason = reason, times = n }
    end
    table.sort(skips, function(a, b)
        if a.times ~= b.times then return a.times > b.times end
        return a.reason < b.reason
    end)

    local rep = {
        entries = tonumber(meta.entries) or 0,
        items = items,
        observed = tonumber(meta.observed) or 0,
        skipped = tonumber(meta.skipped) or 0,
        skips = skips,
        firstT = meta.firstT,
        lastT = meta.lastT,
        gaps = gaps,
        missingEvents = missingEvents,
        foreign = ns.FOREIGN_BOOK,
    }
    if ns.Diag then
        ns.Diag:Module("ledger", {
            ["in"] = rep.observed + rep.skipped,
            out = rep.entries,
            items = rep.items,
            skipped = rep.skipped,
            skips = skips,
            reason = (rep.entries == 0)
                and "книга пуста — записей ещё не было" or nil,
            reasonCode = (rep.entries == 0) and "NO_DATA" or nil,
        })
    end
    return rep
end

-- Одна строка для человека: что в книге есть.
function Ledger:Headline()
    local rep = self:Report()
    if rep.entries == 0 then
        return "Своя книга закупок пока пуста. Я заполняю её, пока вы покупаете"
            .. " и продаёте: делать для этого ничего не надо."
    end
    local parts = { "В своей книге " .. rep.entries .. " "
        .. U.plural(rep.entries, "запись", "записи", "записей")
        .. " по " .. rep.items .. " "
        .. U.plural(rep.items, "предмету", "предметам", "предметам") }
    if rep.lastT then
        local now = Api.ServerTime and Api:ServerTime() or 0
        if now > 0 then
            parts[#parts + 1] = "последняя — " .. U.ageWord(now - rep.lastT)
        end
    end
    return table.concat(parts, ", ") .. "."
end

return Ledger
