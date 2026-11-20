-- ForeverPilot / Tests/test_ceiling.lua
--
-- ВЕНДОРНЫЙ ПОТОЛОК: материал стоит min(цена аукциона, цена торговца с
-- НЕОГРАНИЧЕННЫМ запасом).
--
-- Зачем набор. Игрок один раз уже заплатил аукционную цену за то, что торговец
-- продавал дешевле и в неограниченном количестве. В его собственном кеше
-- Auctionator таких предметов 561, и у 27 реагентов его рецептов аукцион стоит
-- ВЫШЕ прилавка - у Mild Spices (2678) вдвое, у Heavy Silken Thread (8343) на
-- 80 медяков за штуку при девяти штуках в списке покупок.
--
-- Что проверяется, и почему именно это:
--
--   1. ПОТОЛОК ОДИН НА ВЕСЬ АДДОН. Источников ровно два, и оба доказывают
--      неограниченный запас: своя запись у торговца и кеш цен торговцев
--      Auctionator. Чужой кеш с непроверенной полярностью, Codex и
--      Data/Horizon.lua потолком НЕ считаются, и это проверяется отдельно:
--      цены торговца, у которого игрок не стоял, нельзя называть фактом.
--   2. ПРАВИЛО ПРИМЕНЯЕТСЯ В ОДНОМ МЕСТЕ. Ответ Price:Buy не может превысить
--      цену на полке, сколько бы маршрутов туда ни добавили.
--   3. СЛАБЫЙ МИНИМУМ АУКЦИОНА. Нижняя цена лота - не пол рынка: продавцы
--      перебивают собственные лоты. Минимум, за которым стоит одно наблюдение
--      и который обходит полку на копейки, достоверным не считается.
--   4. СЛОВА. Во всех денежных ветках сказано, где купить и сколько это даёт.
--   5. ОБРАТНАЯ СТОРОНА. Выручка выше потолка помечается существующим
--      механизмом сомнения (doubt), а не новым.
--   6. ЧЕСТНОСТЬ ПРО НЕИЗВЕСТНОЕ. Потолка нет - так и сказано, и это отдельный
--      вид заказа данных, а не «цены нет».
--
-- Run with:  FP_SUITE=test_ceiling texluajit Tests/one.lua
local H = ...
local S = assert(loadfile((H.ROOT or ".") .. "/Tests/uistub.lua"))()

return function()

local function cardOf(cards, kind)
    for _, c in ipairs(cards) do
        if c.kind == kind then return c end
    end
    return nil
end

local function cardByKey(cards, key)
    for _, c in ipairs(cards) do
        if c.key == key then return c end
    end
    return nil
end

local function hasDoubt(card, code)
    for _, d in ipairs((card and card.doubts) or {}) do
        if d.code == code then return d end
    end
    return nil
end

-- Мир с одним реагентом и одним рецептом на него. Числа взяты из кеша игрока:
-- 8343 Heavy Silken Thread, торговец 18с, аукцион 18с 80м.
local function world(opts)
    opts = opts or {}
    local env = H.load({ moneyFloor = "off" })
    local ns = env.ns
    env.money = opts.money or 95056
    env.auctionator = true

    H.item(env, 8343, { name = "Крепкая шелковая нить", sellPrice = 450,
                        stackCount = 20 })
    H.item(env, 9343, { name = "Куртка-смокинг", equipLoc = "INVTYPE_CHEST",
                        reqLevel = 30, classID = 4, subclassID = 1, quality = 2,
                        itemLevel = 40, sellPrice = 4000 })
    if opts.auction ~= nil then env.prices[8343] = opts.auction end
    if opts.vendorCache ~= nil then env.vendorPrices[8343] = opts.vendorCache end
    if opts.outputPrice ~= nil then env.prices[9343] = opts.outputPrice end
    if opts.outputVendor ~= nil then env.vendorPrices[9343] = opts.outputVendor end
    if opts.own ~= nil then ns.Config:RememberVendorPrice(8343, opts.own) end

    H.profession(env, "Портняжное дело", 225, 225, {
        H.recipe { id = 9000, name = "Куртка-смокинг", output = 9343,
                   outputQty = 1, category = "Одеяния и жилеты", diff = "optimal",
                   reagents = { { itemID = 8343, qty = opts.qty or 9 } } },
    })
    if opts.history then
        local cfg = ns.Config:Get()
        cfg.priceHistory[8343] = opts.history
        cfg.priceHistoryMeta.days = 0
        for _ in pairs(opts.history) do
            cfg.priceHistoryMeta.days = cfg.priceHistoryMeta.days + 1
        end
    end
    H.itemsChanged(env)
    H.rescan(env)
    return env
end

-- =====================================================================
-- 1. Источники потолка
-- =====================================================================

H.suite("Потолок: источников ровно два, и оба доказывают неограниченный запас")
do
    local env = world({ auction = 1880, vendorCache = 1800 })
    local ns = env.ns
    local Price = ns.PriceProvider
    H.ok(type(Price.VendorCeiling) == "function",
        "вопрос «сколько просит торговец» задаётся одной функцией")
    H.ok(Price.CEILING_SOURCES.own and Price.CEILING_SOURCES.cache,
        "в перечне источников потолка есть своя запись и кеш Auctionator")
    H.ok(not Price.CEILING_SOURCES.vendorForeign,
        "а чужого кеша с непроверенной полярностью в нём нет")
    H.ok(not Price.CEILING_SOURCES.markup and not Price.CEILING_SOURCES.codex,
        "и ни арифметики по цене выкупа, ни Codex")

    Price:BeginPass()
    local copper, src = Price:VendorCeiling(8343)
    H.eq(copper, 1800, "кеш Auctionator отдаёт потолок 18с")
    H.eq(src, "cache", "и источник назван его именем")
end

H.suite("Потолок: дешевле из двух источников, при равенстве — своя запись")
do
    local env = world({ auction = 1880, vendorCache = 1800, own = 1700 })
    local Price = env.ns.PriceProvider
    Price:BeginPass()
    local copper, src = Price:VendorCeiling(8343)
    H.eq(copper, 1700, "своя запись дешевле — она и потолок")
    H.eq(src, "own", "источник: своя запись")

    local env2 = world({ auction = 1880, vendorCache = 1600, own = 1700 })
    local P2 = env2.ns.PriceProvider
    P2:BeginPass()
    local c2, s2 = P2:VendorCeiling(8343)
    H.eq(c2, 1600, "кеш дешевле — потолок берётся по нему")
    H.eq(s2, "cache", "источник: кеш Auctionator")

    local env3 = world({ auction = 1880, vendorCache = 1800, own = 1800 })
    local P3 = env3.ns.PriceProvider
    P3:BeginPass()
    local c3, s3 = P3:VendorCeiling(8343)
    H.eq(c3, 1800, "при равных числах потолок тот же")
    H.eq(s3, "own", "а источник — свой: его мы видели сами")
end

H.suite("Потолок: чужой кеш торговцев потолком не становится")
do
    -- Mastercraft.vendorPrices: полярность не проверена, число там может
    -- означать «сколько торговец ДАЁТ». Такое в потолок не идёт вовсе.
    local env = world({ auction = 1880 })
    env.foreignVendorPrices = { [8343] = 100 }
    local Price = env.ns.PriceProvider
    Price:BeginPass()
    H.eq(Price:VendorCeiling(8343), nil,
        "чужая вендорная цена потолком не считается")
    H.eq(Price:Ceiling(8343), nil, "и решения по потолку из неё не выходит")
    local copper = Price:Buy(8343)
    H.eq(copper, 1880, "цена покупки остаётся аукционной")
end

H.suite("Потолок: торговец, у которого игрок не был, в данные как факт не вписан")
do
    -- Mister Graphed (263384, Powderfuse Port) - по данным сообщества торгует
    -- высокоуровневыми реагентами с неограниченным запасом. В кеше игрока его
    -- НЕТ: он там не стоял. Цены сообщества лежат в Data/Horizon.lua с
    -- провенансом и достоверностью, и потолком не становятся.
    local env = world({ auction = 1880 })
    local ns = env.ns
    local HZ = ns.Horizon
    H.ok(HZ ~= nil, "справочник горизонта на месте")
    local watch = HZ and HZ.PRICE_WATCH and HZ.PRICE_WATCH[249427]
    H.ok(watch ~= nil and watch.vendor == 263384,
        "цена этого торговца в справочнике есть — с провенансом, как данные")
    H.ok(HZ.PROVENANCE and HZ.PROVENANCE.vendorBuy ~= nil,
        "и у неё назван источник, а не «факт»")
    ns.PriceProvider:BeginPass()
    H.eq(ns.PriceProvider:VendorCeiling(249427), nil,
        "но потолком она не становится: игрок у этого торговца не стоял")
    H.eq(ns.PriceProvider:Ceiling(249427), nil, "и решения по ней нет")
end

-- =====================================================================
-- 2. Правило применяется в одном месте
-- =====================================================================

H.suite("Покупка: цена материала — min(аукцион, прилавок)")
do
    local env = world({ auction = 1880, vendorCache = 1800 })
    local Price = env.ns.PriceProvider
    Price:BeginPass()
    local copper, conf, src, age = Price:Buy(8343)
    H.eq(copper, 1800, "взята цена с полки, а не с аукциона")
    H.eq(src, "vendor", "и источник назван торговцем")
    H.eq(age, false, "а возраст у фиксированной цены — «не стареет», а не «не знаю»")
    H.ok(env.ns.Util.contains(Price:Label(copper, conf, src, age), "не стареет"),
        "это же видно и в подписи цены: " .. Price:Label(copper, conf, src, age))
end

H.suite("Покупка: аукцион ниже потолка — потолок ничего не портит")
do
    -- Thick Logs (272941) в кеше игрока: торговец 20з, аукцион 15з 99с.
    local env = world({ auction = 159900, vendorCache = 200000 })
    local Price = env.ns.PriceProvider
    Price:BeginPass()
    local copper, _, src = Price:Buy(8343)
    H.eq(copper, 159900, "цена аукционная: она и дешевле")
    H.eq(src, "auctionator", "и источник — аукцион")
    H.eq(Price:CeilingText(8343), nil,
        "говорить тут нечего: потолок не сработал")
end

H.suite("Покупка: потолок — правило, а не порядок сравнения маршрутов")
do
    -- Сейчас прилавок стоит среди маршрутов, и выбор дешёвого сам не даёт
    -- превысить потолок. Но это свойство ПОРЯДКА, а не правило: маршрут с
    -- другим признаком подтверждённости снял бы его молча. Здесь прилавок
    -- нарочно объявлен неподтверждённым - то есть из выбора он выпадает
    -- целиком, - и ответ всё равно обязан остаться на уровне полки.
    local env = world({ auction = 1880, vendorCache = 1800 })
    local Price = env.ns.PriceProvider
    local saved = Price.PROVEN_SOURCES.vendor
    Price.PROVEN_SOURCES.vendor = nil
    Price:BeginPass()
    local copper, _, src = Price:Buy(8343)
    Price.PROVEN_SOURCES.vendor = saved
    H.eq(copper, 1800, "выше полки ответ не поднялся")
    H.eq(src, "vendor", "и источником назван тот, кто этот потолок держит")
end

-- =====================================================================
-- 3. Слабый минимум аукциона
-- =====================================================================

H.suite("Слабый минимум: дешевле на копейки и одно наблюдение — это оценка")
do
    -- Fine Thread (2321) в кеше игрока: торговец 1с, аукцион 96м. Разрыв 4%,
    -- своей истории по нему нет.
    local env = world({ auction = 96, vendorCache = 100 })
    local ns = env.ns
    local Price = ns.PriceProvider
    Price:BeginPass()
    local v = Price:Ceiling(8343)
    H.ok(v ~= nil, "решение по потолку есть")
    H.eq(v.cheaper, "auction", "дешевле на аукционе")
    H.eq(v.days, 0, "наблюдений своих — ни одного")
    H.eq(v.thin, true, "и минимум назван слабым")
    local copper, conf, src = Price:Buy(8343)
    H.eq(copper, 96, "ЧИСЛО НЕ МЕНЯЕТСЯ: поднять игроку стоимость молча нельзя")
    H.eq(src, "auctionator", "источник остаётся аукционом")
    H.eq(conf, ns.CONF.ESTIMATE, "а достоверность падает до оценки")
    local text = Price:CeilingText(8343)
    H.ok(text and ns.Util.contains(text, "одно наблюдение"),
        "и сказано, на чём эта цена стоит: " .. tostring(text))
    H.ok(text and ns.Util.contains(text, "всегда"),
        "и что у торговца та же вещь есть всегда")
end

H.suite("Слабый минимум: наблюдений несколько — минимуму верим")
do
    local env = world({ auction = 96, vendorCache = 100,
                        history = { [20770] = 96, [20771] = 98, [20772] = 97 } })
    local ns = env.ns
    local Price = ns.PriceProvider
    Price:BeginPass()
    local v = Price:Ceiling(8343)
    H.eq(v.days, 3, "три наблюдения")
    H.eq(v.thin, false, "минимум слабым не считается")
    local copper, conf = Price:Buy(8343)
    H.eq(copper, 96, "цена аукционная")
    H.eq(conf, ns.CONF.CACHED, "и ступень достоверности не снята")
    H.eq(Price:CeilingText(8343), nil, "говорить про потолок нечего")
end

H.suite("Потолок: разница меньше медяка — не разница")
do
    -- Кеш Auctionator делит цену окна на размер стопки, и у стрел со стопкой в
    -- 200 штук выходит дробь: в файле игрока 10 таких записей, 4 из них меньше
    -- медяка. Разрыв в такую долю печатался бы как «экономия 0м» - число,
    -- которое не значит ничего, и его же ловит детектор бессмыслицы.
    local env = world({ auction = 1, vendorCache = 1.225 })
    local ns = env.ns
    local Price = ns.PriceProvider
    Price:BeginPass()
    local v = Price:Ceiling(8343)
    H.ok(v ~= nil, "решение есть")
    H.eq(v.cheaper, "equal", "разрыв 0.225 медяка разрывом не считается")
    H.eq(v.saving, nil, "и экономии в нём нет")
    local text = Price:CeilingText(8343)
    H.ok(text and not ns.Util.contains(text, "0м"),
        "и в тексте нет «0м»: " .. tostring(text))
    H.ok(text and ns.Util.contains(text, "столько же"),
        "сказано, что цены сошлись")
end

H.suite("Слабый минимум: разрыв широкий — одного наблюдения достаточно")
do
    local env = world({ auction = 50, vendorCache = 100 })
    local ns = env.ns
    local Price = ns.PriceProvider
    Price:BeginPass()
    local v = Price:Ceiling(8343)
    H.eq(v.thin, false, "вдвое дешевле — это не «на копейки»")
    local copper, conf = Price:Buy(8343)
    H.eq(copper, 50, "цена аукционная")
    H.eq(conf, ns.CONF.CACHED, "достоверность на месте")
end

-- =====================================================================
-- 4. Слова во всех денежных ветках
-- =====================================================================

H.suite("Слова: карточка покупки говорит, где купить и сколько это даёт")
do
    local env = world({ auction = 1880, vendorCache = 1800, outputPrice = 19800 })
    local ns, U = env.ns, env.ns.Util
    local cards = H.build(env)
    local buy = cardByKey(cards, "buy:8343")
    H.ok(buy ~= nil, "карточка покупки построена")
    if buy then
        H.ok(U.contains(buy.why, "У торговца дешевле"),
            "сказано, что у торговца дешевле")
        H.ok(U.contains(buy.why, "экономия 80м за штуку"),
            "названа экономия за штуку: " .. tostring(buy.why))
        H.ok(U.contains(buy.why, "экономия 7с 20м"),
            "и экономия на всё количество")
        H.ok(U.contains(buy.why, "18с (торговец"),
            "цена в карточке — вендорная")
        H.ok(U.contains(buy.need, "У какого торговца — не знаю"),
            "а торговец не выдуман: его имени в кеше нет, и так и сказано")
    end
end

H.suite("Слова: карточка «на продажу» называет экономию на материалах")
do
    local env = world({ auction = 1880, vendorCache = 1800, outputPrice = 19800 })
    local ns, U = env.ns, env.ns.Util
    local cards = H.build(env)
    local sell = cardOf(cards, ns.KIND.CRAFT_PROFIT)
    H.ok(sell ~= nil, "карточка «на продажу» построена")
    if sell then
        H.ok(U.contains(sell.why, "У торговца это дешевле"),
            "сказано про прилавок: " .. tostring(sell.why))
        H.ok(U.contains(sell.why, "на весь план"),
            "и экономия названа на весь план")
    end
end

H.suite("Слова: список покупок считает экономию и не ищет это на аукционе")
do
    local env = world({ auction = 1880, vendorCache = 1800, outputPrice = 19800 })
    local ns, U = env.ns, env.ns.Util
    H.build(env)
    local line
    for _, l in ipairs(ns.ShoppingList:Lines()) do
        if l.itemID == 8343 then line = l end
    end
    H.ok(line ~= nil, "строка списка покупок есть")
    if line then
        H.eq(line.vendorCheaper, true, "строка помечена «дешевле у торговца»")
        H.eq(line.vendorSaving, 720, "экономия на всё количество: 7с 20м")
        H.eq(line.src, "vendor", "и цена в строке вендорная")
    end
    local save = ns.ShoppingList:VendorSaving()
    H.ok(save ~= nil, "итог экономии по списку посчитан")
    if save then
        H.eq(save.lines, 1, "одна позиция дешевле у торговца")
        H.eq(save.saving, 720, "итого 7с 20м")
    end
    local items, skipped = ns.ShoppingList:AuctionItems()
    H.eq(skipped.vendor, 1, "в поиск по аукциону эта позиция не идёт")
    H.eq(#items, 0, "искать на аукционе нечего")

    -- А ЧТО СКАЗАНО ПОД СПИСКОМ. Передача требует открытого аукциона, поиска
    -- списком и вкладки покупок; всё это читают три функции адаптера, и здесь
    -- они отвечают «да» - проверяется сам текст, а не окно игры.
    local Api = ns.Api
    local savedRoute, savedOpen, savedTab =
        Api.AuctionatorSearchRoute, Api.AuctionHouseOpen, Api.AuctionatorShoppingTab
    function Api:AuctionatorSearchRoute() return "MultiSearchAdvanced", function() end end
    function Api:AuctionHouseOpen() return true end
    function Api:AuctionatorShoppingTab() return true end
    local info = ns.ShoppingList:Handoff()
    Api.AuctionatorSearchRoute, Api.AuctionHouseOpen, Api.AuctionatorShoppingTab =
        savedRoute, savedOpen, savedTab
    H.eq(info.state, "nothing", "передавать нечего: всё дешевле у торговца")
    H.ok(info.note and U.contains(info.note, "дешевле"),
        "и под списком сказано почему: " .. tostring(info.note))
    H.ok(info.note and U.contains(info.note, "7с 20м"),
        "с числом, а не только словом «дешевле»")
end

H.suite("Слова: окно крафта помечает строку списка и считает итог экономии")
do
    -- Проверяется ЭКРАН, а не только решение: сумма списка уже посчитана по
    -- потолку, и если про это не сказано там, где цена, игрок пойдёт на
    -- аукцион и заплатит разницу второй раз.
    local env = S.load(H)
    local ns, U = env.ns, env.ns.Util
    S.populate(env, H)
    H.item(env, 8343, { name = "Крепкая шелковая нить", sellPrice = 450 })
    H.item(env, 8344, { name = "Шелковый кушак", sellPrice = 400 })
    env.prices[8343] = 1880
    env.vendorPrices[8343] = 1800
    env.prices[8344] = 9000
    ns.RecipeBook:Store("Tailoring", {
        H.recipe { id = 3, name = "Шелковый кушак", output = 8344, outputQty = 1,
                   reagents = { { itemID = 8343, qty = 4 } }, diff = "optimal",
                   category = "Пояса", categoryID = 2 },
    }, "own", ns.CONF.EXACT, H.serverTime)
    ns.RecipeBook:Reindex()
    H.itemsChanged(env)
    H.rescan(env)
    H.build(env)

    ns.MainFrame:Build()
    ns.MainFrame:Select("CRAFT")
    ns.MainFrame:RenderActive()
    local _, texts = S.harvest(env.world, ns.MainFrame.frame)
    local screen = {}
    for i, t in ipairs(texts) do screen[i] = S.plain(t) end
    screen = table.concat(screen, "\n")
    H.ok(U.contains(screen, "у торговца, экономия"),
        "строка списка помечена: у торговца дешевле, и на сколько")
    H.ok(U.contains(screen, "дешевле взять у торговца"),
        "а под списком — итог по всем таким позициям")
    -- Нить просят два совета по 4 штуки, в сумках её нет: 80м x 8 = 6с 40м.
    H.ok(U.contains(screen, "6с 40м"),
        "и с числом, а не одним словом «дешевле»")
end

H.suite("Слова: перепродажа отказывается от лота дороже прилавка, назвав причину")
do
    local env = world({ auction = 1880, vendorCache = 1800 })
    local ns = env.ns
    local cfg = ns.Config:Get()
    -- История делает лот «ниже рынка» по всем остальным признакам.
    cfg.priceHistory[8343] = { [20770] = 4000, [20771] = 4000, [20772] = 4000 }
    cfg.priceHistoryMeta.days = 3
    ns.PriceProvider:BeginPass()
    local opp, why, detail = ns.Resale:Evaluate(8343, 1880)
    H.eq(opp, nil, "совета нет")
    H.eq(why, "vendor-cheaper", "и причина названа кодом, а не молчанием")
    H.ok(detail and ns.Util.contains(detail, "торговца"),
        "а словами — что дешевле на полке: " .. tostring(detail))
end

H.suite("Слова: перепродажа у торговца знает, чьими глазами увиден запас")
do
    local env = world({ auction = 1880, vendorCache = 1800 })
    local ns = env.ns
    ns.PriceProvider:BeginPass()
    local ask, conf, src, proven = ns.VendorArbitrage:VendorAsk(8343)
    H.eq(ask, 1800, "ветка перепродажи видит кеш цен торговцев Auctionator")
    H.eq(proven, true, "и считает запас доказанным: он пишется только для -1")
    H.eq(src, "vendor", "источник на карточке называется торговцем")
    -- Текст про запас проверяется по самому решению, а не через карточку: в
    -- этом мире перепродажа убыточна (аукцион 18с 80м против прилавка 18с), и
    -- карточки не будет - а текст обязан быть верным и тогда, когда карточка
    -- родится на других числах.
    local byCache = ns.VendorArbitrage:StockText({ provenStock = true,
                                                   askSeenBy = "cache" })
    H.ok(ns.Util.contains(byCache, "Auctionator"),
        "цену записал Auctionator, и так и сказано")
    H.ok(ns.Util.contains(byCache, "не запомнил"),
        "а торговец не выдуман: " .. byCache)
    local byOwn = ns.VendorArbitrage:StockText({ provenStock = true,
                                                 askSeenBy = "own" })
    H.ok(ns.Util.contains(byOwn, "Я сам стоял"),
        "своя запись говорит про себя иначе: " .. byOwn)
    H.ok(not ns.Util.contains(byOwn, "Auctionator"),
        "и чужого наблюдения себе не приписывает")
end

-- =====================================================================
-- 5. Обратная сторона: выручка выше потолка
-- =====================================================================

H.suite("Обратная сторона: выручка выше прилавка — сомнение на карточке")
do
    -- Куртку-смокинг продаёт торговец с неограниченным запасом за 1з, а
    -- карточка обещает выручить 2з. Покупателю незачем брать у игрока.
    local env = world({ auction = 1880, vendorCache = 1800,
                        outputPrice = 20000, outputVendor = 10000 })
    local ns, U = env.ns, env.ns.Util
    local cards = H.build(env)
    local sell = cardOf(cards, ns.KIND.CRAFT_PROFIT)
    H.ok(sell ~= nil, "карточка «на продажу» есть")
    if sell then
        local d = hasDoubt(sell, "revenue-above-vendor-ceiling")
        H.ok(d ~= nil, "сомнение приложено тем же механизмом, что и все прочие")
        H.eq(sell.doubtLevel, ns.Risk.DOUBT_SOFT,
            "ступень — «я бы это проверил», а не «числа не сходятся»")
        H.ok(U.contains(sell.benefit, ns.Risk.DOUBT_MARK.doubt),
            "в заголовке выгоды стоит пометка: " .. tostring(sell.benefit))
        H.ok(U.contains(sell.why, ns.Risk.DOUBT_LEAD.doubt),
            "и первой фразой «почему» — зачин сомнения")
        H.ok(U.contains(sell.why, "запас у него неограниченный"),
            "сказано, почему это вообще сомнительно")
        H.ok(sell.conf == ns.CONF.ESTIMATE or sell.conf == ns.CONF.UNKNOWN,
            "достоверность опущена: " .. tostring(sell.conf))
    end
end

H.suite("Обратная сторона: без потолка сомнения нет")
do
    local env = world({ auction = 1880, vendorCache = 1800, outputPrice = 20000 })
    local ns = env.ns
    local cards = H.build(env)
    local sell = cardOf(cards, ns.KIND.CRAFT_PROFIT)
    H.ok(sell ~= nil, "карточка есть")
    H.eq(hasDoubt(sell, "revenue-above-vendor-ceiling"), nil,
        "потолка по готовой вещи нет — и сомнения нет")
    H.eq(ns.Risk:CeilingDoubt(sell), nil, "решение тоже пустое")
end

H.suite("Обратная сторона: выручка НИЖЕ потолка сомнения не вызывает")
do
    local env = world({ auction = 1880, vendorCache = 1800,
                        outputPrice = 20000, outputVendor = 40000 })
    local ns = env.ns
    local cards = H.build(env)
    local sell = cardOf(cards, ns.KIND.CRAFT_PROFIT)
    H.ok(sell ~= nil, "карточка есть")
    H.eq(hasDoubt(sell, "revenue-above-vendor-ceiling"), nil,
        "на полке дороже — продавать можно, вопросов нет")
end

H.suite("Обратная сторона: перепродажа у торговца этим сомнением не метится")
do
    -- Там «аукцион дороже прилавка» - не побочный признак, а сама схема, и
    -- правдоподобие наценки считается собственными порогами ветки.
    local ns = world({ auction = 1880, vendorCache = 1800 }).ns
    H.eq(ns.Risk.CEILING_DOUBT_KINDS[ns.KIND.ARBITRAGE], nil,
        "вид «купить и перепродать» в перечне отсутствует — это записано")
    H.ok(ns.Risk.CEILING_DOUBT_KINDS[ns.KIND.CRAFT_PROFIT]
        and ns.Risk.CEILING_DOUBT_KINDS[ns.KIND.RESELL],
        "а крафт на продажу и перекупка — в нём")
    H.eq(ns.Risk:CeilingDoubt({ kind = ns.KIND.ARBITRAGE, itemID = 8343,
                                revenue = 999999 }), nil,
        "и решения по такой карточке не выходит")
end

H.suite("Самопроверка: сторож молчит, пока пометка доезжает до карточки")
do
    local env = world({ auction = 1880, vendorCache = 1800,
                        outputPrice = 20000, outputVendor = 10000 })
    local ns = env.ns
    H.ok(ns.SanityChecks:HasCheck("revenue-above-vendor-ceiling"),
        "проверка зарегистрирована")
    H.eq(ns.SanityChecks.SCOPE["revenue-above-vendor-ceiling"], "say",
        "и адресована словами игроку, а не в файл")
    H.build(env)
    local found = 0
    for _, e in ipairs(ns.Diag:Init().suspicious or {}) do
        if e.code == "revenue-above-vendor-ceiling" then found = found + 1 end
    end
    H.eq(found, 0, "находки нет: сомнение на карточке, и это её молчание")

    -- А теперь пометку с карточки снимаем - сторож обязан заговорить.
    local cards = ns.ActionEngine.cards
    local sell = cardOf(cards, ns.KIND.CRAFT_PROFIT)
    if sell then sell.doubts = nil end
    ns.Diag:ClearSuspicions()
    ns.SanityChecks:Run({ cards = cards, snap = ns.CharacterScanner:Get(),
                          counts = {}, generated = #cards })
    local after = 0
    for _, e in ipairs(ns.Diag:Init().suspicious or {}) do
        if e.code == "revenue-above-vendor-ceiling" then after = after + 1 end
    end
    H.eq(after, 1, "без пометки находка записана — сторож работает")
end

-- =====================================================================
-- 6. Честность про неизвестное
-- =====================================================================

H.suite("Незнание: потолка нет — это заказ данных, а не «цены нет»")
do
    local env = world({ auction = 1880, outputPrice = 19800 })
    local ns, U = env.ns, env.ns.Util
    H.ok(ns.PriceProvider.CEILING_UNKNOWN_WHY ~= nil,
        "почему потолка нет — написано словами")
    H.ok(U.contains(ns.PriceProvider.CEILING_UNKNOWN_WHY, "стояли"),
        "и причина настоящая: вендорную цену знаем только там, где игрок был")
    H.build(env)
    local b = (ns.Diag:Init().wanted or {}).vendorCeilingUnknown
    H.ok(b ~= nil and (b.total or 0) > 0,
        "заказ записан: " .. tostring(b and b.total))
    local t = ns.Diag:WantedTotals()
    H.ok((t.vendorCeilingTotal or 0) > 0, "и считается отдельной величиной")
    H.eq(t.pricesTotal, 0, "а к «цены нет» не приписывается: цена-то есть")
    local line = ns.Diag:WantedLine()
    H.ok(line and U.contains(line, "дешевле ли это у торговца"),
        "в сводке это сказано игроку: " .. tostring(line))
end

H.suite("Незнание: потолок известен — заказа по этому предмету нет")
do
    local env = world({ auction = 1880, vendorCache = 1800, outputPrice = 19800 })
    local ns = env.ns
    H.build(env)
    local b = (ns.Diag:Init().wanted or {}).vendorCeilingUnknown
    local asked = false
    for _, item in ipairs((b and b.items) or {}) do
        if item.id == 8343 then asked = true end
    end
    H.eq(asked, false, "по предмету с потолком данных не заказываем")
end

-- =====================================================================
-- 7. Цена работы: обращения за пересчёт
-- =====================================================================

H.suite("Цена работы: кеш цен торговцев спрашивается один раз на предмет")
do
    local env = world({ auction = 1880, vendorCache = 1800, outputPrice = 19800 })
    local ns = env.ns
    local Api = ns.Api
    local real = Api.VendorPrice
    local calls = {}
    function Api:VendorPrice(itemID)
        calls[itemID] = (calls[itemID] or 0) + 1
        return real(self, itemID)
    end
    H.build(env)
    Api.VendorPrice = real
    local worst, worstID = 0, nil
    local items = 0
    for itemID, n in pairs(calls) do
        items = items + 1
        if n > worst then worst, worstID = n, itemID end
    end
    H.ok(items > 0, "обращения были: " .. items .. " предметов")
    H.eq(worst, 1, "и ни по одному предмету не больше одного за пересчёт"
        .. ((worst > 1) and (" (предмет " .. tostring(worstID) .. ")") or ""))

    -- И повторный вопрос в том же пересчёте не стоит ничего.
    local again = 0
    function Api:VendorPrice(itemID)
        again = again + 1
        return real(self, itemID)
    end
    for _ = 1, 5 do ns.PriceProvider:Ceiling(8343) end
    Api.VendorPrice = real
    H.eq(again, 0, "пять повторных вопросов — ноль обращений")
end

end
