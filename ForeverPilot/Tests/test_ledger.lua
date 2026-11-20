-- ForeverPilot / Tests/test_ledger.lua
--
-- СВОЯ КНИГА ЗАКУПОК: что игрок реально заплатил и когда.
--
-- До неё себестоимость материалов бралась из MastercraftDB.costs - книги
-- закупок ЧУЖОГО аддона, по недокументированной схеме, который обновляется раз
-- в пару дней. Сломают формат - у нас отвалятся цены, и мы узнаем об этом от
-- игрока. Поэтому книга теперь своя, в своих SavedVariables, и пишется она из
-- событий игры, которые нам и так приходят: деньги и сумки.
--
-- ЧТО ЗДЕСЬ ГЛАВНОЕ. Не «записалось», а «НЕ записалось наугад»: единственный
-- способ узнать цену покупки из событий - сверить деньги с сумками, а значит
-- каждый случай, когда сверка неоднозначна, обязан кончаться отказом с
-- названной причиной. Выдуманная цена в книге закупок хуже пустой книги:
-- пустая говорит «не знаю», а выдуманная врёт про себестоимость.
--
-- Run with:  FP_SUITE=test_ledger texluajit Tests/one.lua

local H = ...

return function()

local CONF

local function fresh()
    local env = H.load()
    CONF = env.ns.CONF
    return env, env.ns
end

-- Короткая запись «снимок мира»: деньги и сумки.
local function snap(money, items)
    return { money = money, items = items or {} }
end

H.suite("Книга закупок: модуль есть и книга начинается пустой")
do
    local env, ns = fresh()
    H.ok(type(ns.Ledger) == "table", "ns.Ledger загружен")
    H.ok(type(ns.Ledger.Observe) == "function", "у него есть сверка Observe")

    local meta = ns.Config:LedgerMeta()
    H.ok(type(meta) == "table", "книга в SavedVariables есть")
    H.eq(meta.entries or 0, 0, "и она пуста: ни одной записи")
    H.eq(ns.Ledger:Paid(1), nil, "про цену предмета ничего не известно")
    H.ok(ns.Ledger:Count() == 0, "записей ноль")
end

H.suite("Книга закупок: покупка у торговца записана с ценой за штуку")
do
    local env, ns = fresh()
    -- Игрок стоял у торговца, отдал 500 медяков и получил 5 штук.
    local entry, why = ns.Ledger:Observe(
        snap(10000, { [7] = 0 }),
        snap(9500, { [7] = 5 }),
        ns.Ledger.WHERE.VENDOR, H.serverTime)
    H.ok(entry ~= nil, "запись сделана" .. (entry and "" or (": " .. tostring(why))))
    if entry then
        H.eq(entry.kind, ns.Ledger.KIND.BUY, "это покупка")
        H.eq(entry.itemID, 7, "предмет опознан")
        H.eq(entry.qty, 5, "количество")
        H.eq(entry.copper, 500, "сколько ушло всего")
        H.eq(entry.unit, 100, "и цена за штуку")
        H.eq(entry.where, ns.Ledger.WHERE.VENDOR, "где это было")
        H.eq(entry.t, H.serverTime, "и когда")
    end
end

H.suite("Книга закупок: продажа — это не покупка, и считается отдельно")
do
    local env, ns = fresh()
    local entry = ns.Ledger:Observe(
        snap(9500, { [7] = 5 }),
        snap(10000, { [7] = 0 }),
        ns.Ledger.WHERE.VENDOR, H.serverTime)
    H.ok(entry ~= nil, "запись сделана")
    if entry then
        H.eq(entry.kind, ns.Ledger.KIND.SELL, "это продажа")
        H.eq(entry.unit, 100, "цена за штуку")
    end

    ns.Ledger:Note(entry)
    -- Продажа НЕ становится себестоимостью: заплатил - это только покупка.
    H.eq(ns.Ledger:Paid(7), nil, "проданное не превращается в «я за это заплатил»")
    local got = ns.Ledger:Received(7)
    H.eq(got, 100, "зато «за столько продал» известно: " .. tostring(got))
end

H.suite("Книга закупок: ни одной записи наугад")
do
    local env, ns = fresh()
    local L = ns.Ledger
    local cases = {
        { "без торговца и аукциона запись не делается",
          snap(10000, {}), snap(9500, { [7] = 5 }), nil, L.SKIP.NO_CONTEXT },
        { "деньги не изменились — это не платёж",
          snap(10000, { [7] = 0 }), snap(10000, { [7] = 5 }), L.WHERE.VENDOR, L.SKIP.NO_MONEY },
        { "сумки не изменились — непонятно, за что платили",
          snap(10000, { [7] = 5 }), snap(9500, { [7] = 5 }), L.WHERE.AUCTION, L.SKIP.NO_ITEMS },
        { "изменилось несколько предметов — чей это платёж, неизвестно",
          snap(10000, { [7] = 0, [8] = 0 }), snap(9500, { [7] = 5, [8] = 2 }),
          L.WHERE.VENDOR, L.SKIP.MANY_ITEMS },
        { "деньги убыли и предмет убыл — это не покупка и не продажа",
          snap(10000, { [7] = 5 }), snap(9500, { [7] = 1 }), L.WHERE.VENDOR, L.SKIP.MISMATCH },
        { "без часов сервера запись бесполезна",
          snap(10000, { [7] = 0 }), snap(9500, { [7] = 5 }), L.WHERE.VENDOR, L.SKIP.NO_CLOCK, 0 },
    }
    for _, c in ipairs(cases) do
        local entry, why = L:Observe(c[2], c[3], c[4], c[6] or H.serverTime)
        H.eq(entry, nil, c[1])
        H.eq(why, c[5], "   и причина названа: " .. tostring(why))
    end

    -- И каждая причина - человеческая фраза, а не код.
    for key, text in pairs(L.SKIP) do
        H.ok(type(text) == "string" and ns.Util.charLen(text) > 10,
            "причина «" .. key .. "» объяснена словами: " .. tostring(text))
    end
end

H.suite("Книга закупок: себестоимость — средняя по количеству, а не по записям")
do
    local env, ns = fresh()
    local L = ns.Ledger
    -- Купил 1 штуку за 1000 и 9 штук по 100. Средняя по записям была бы 550,
    -- а заплачено на самом деле 1900 за 10 штук, то есть 190 за штуку.
    L:Note(L:Observe(snap(10000, { [7] = 0 }), snap(9000, { [7] = 1 }),
        L.WHERE.AUCTION, H.serverTime - 100))
    L:Note(L:Observe(snap(9000, { [7] = 1 }), snap(8100, { [7] = 10 }),
        L.WHERE.VENDOR, H.serverTime))

    local paid, conf, info = L:Paid(7)
    H.eq(paid, 190, "средняя взвешена по количеству: " .. tostring(paid))
    H.eq(conf, CONF.EXACT, "это факт, а не оценка: игрок эти деньги отдал")
    if info then
        H.eq(info.qty, 10, "штук учтено")
        H.eq(info.copper, 1900, "денег учтено")
        H.eq(info.n, 2, "покупок учтено")
        H.eq(info.lastT, H.serverTime, "и когда была последняя")
    end
end

H.suite("Книга закупок: своя книга важнее чужой")
do
    local env, ns = fresh()
    local L = ns.Ledger
    env.auctionator = false
    -- У чужой книги Mastercraft по этому предмету своё число.
    env.observedPrices = { [7] = 700 }
    H.rescan(env)

    ns.PriceProvider:BeginPass()
    local p, _, src = ns.PriceProvider:Buy(7)
    H.eq(src, "foreign", "пока своя книга пуста, чужая работает запасным источником")
    H.eq(p, 700, "и её число берётся")

    -- Теперь в своей книге есть ответ по этому предмету.
    L:Note(L:Observe(snap(10000, { [7] = 0 }), snap(9000, { [7] = 10 }),
        L.WHERE.VENDOR, H.serverTime))
    ns.PriceProvider:BeginPass()
    local p2, _, src2 = ns.PriceProvider:Buy(7)
    H.eq(src2, "ledger", "своя книга отвечает первой: " .. tostring(src2))
    H.eq(p2, 100, "и чужое число больше не участвует")

    -- Чужая книга помечена чужой - и в коде, и на экране.
    H.ok(ns.PriceProvider:IsForeignSource("foreign"),
        "«foreign» опознаётся как чужой источник")
    H.ok(not ns.PriceProvider:IsForeignSource("ledger"),
        "своя книга чужой не считается")
    H.ok(ns.Util.contains(ns.PriceProvider:Label(700, CONF.CACHED, "foreign", 60),
            "другого аддона"),
        "и на экране сказано, что это чужое наблюдение: "
        .. ns.PriceProvider:Label(700, CONF.CACHED, "foreign", 60))
end

H.suite("Книга закупок: фактическая себестоимость вместо оценки")
do
    local env, ns = fresh()
    local L = ns.Ledger
    env.auctionator = false
    H.item(env, 70, { name = "Ткань", sellPrice = 10 })
    H.item(env, 71, { name = "Жилет", sellPrice = 50 })
    -- Цены на аукционе нет, и без книги остаётся только оценка по цене продажи
    -- торговцу: 10 * 4 = 40 за ткань.
    H.profession(env, "Портняжное дело", 50, 75, {
        H.recipe({ id = 700, name = "Жилет", output = 71, outputQty = 1,
                   reagents = { { itemID = 70, qty = 5 } }, diff = "medium" }),
    })
    H.rescan(env)

    ns.PriceProvider:BeginPass()
    ns.CraftingPlanner:Bind(ns.RecipeBook, ns.PriceProvider):BeginPass()
    local guess, guessConf = ns.CraftingPlanner:RecipeUnitCost(ns.RecipeBook:Get(700))
    H.eq(guess, 200, "без книги себестоимость - оценка: " .. tostring(guess))
    H.eq(guessConf, CONF.ESTIMATE, "и помечена оценкой")

    local a0, c0, cov0 = L:ActualMaterialCost(ns.RecipeBook:Get(700))
    H.eq(a0, nil, "фактической себестоимости без книги нет вовсе")
    H.eq(c0, CONF.UNKNOWN, "и это «не знаю», а не ноль")
    H.ok(cov0 and cov0.known == 0 and cov0.total == 1,
        "и сказано, по скольким материалам книга молчит: 0 из 1")

    -- Игрок купил ткань по 7 медяков за штуку. Это уже не оценка.
    L:Note(L:Observe(snap(10000, { [70] = 0 }), snap(9930, { [70] = 10 }),
        L.WHERE.VENDOR, H.serverTime))
    ns.PriceProvider:BeginPass()
    ns.CraftingPlanner:Bind(ns.RecipeBook, ns.PriceProvider):BeginPass()

    local actual, aConf, cov = L:ActualMaterialCost(ns.RecipeBook:Get(700))
    H.eq(actual, 35, "фактическая себестоимость: 5 x 7 = " .. tostring(actual))
    H.eq(aConf, CONF.EXACT, "и она факт, а не оценка")
    H.ok(cov and cov.known == 1 and cov.total == 1, "книга закрыла все материалы")
    H.ok(actual < guess, "и она НЕ равна оценке — иначе проверять было бы нечего")
end

H.suite("Книга закупок: смешанная себестоимость честно называет долю")
do
    local env, ns = fresh()
    local L = ns.Ledger
    env.auctionator = false
    H.item(env, 70, { name = "Ткань", sellPrice = 10 })
    H.item(env, 72, { name = "Нить", sellPrice = 20 })
    H.item(env, 71, { name = "Жилет", sellPrice = 50 })
    H.profession(env, "Портняжное дело", 50, 75, {
        H.recipe({ id = 700, name = "Жилет", output = 71, outputQty = 1,
                   reagents = { { itemID = 70, qty = 5 }, { itemID = 72, qty = 1 } },
                   diff = "medium" }),
    })
    H.rescan(env)
    -- Книга знает только про ткань.
    L:Note(L:Observe(snap(10000, { [70] = 0 }), snap(9930, { [70] = 10 }),
        L.WHERE.VENDOR, H.serverTime))
    ns.PriceProvider:BeginPass()
    ns.CraftingPlanner:Bind(ns.RecipeBook, ns.PriceProvider):BeginPass()

    local total, conf, cov = L:ActualMaterialCost(ns.RecipeBook:Get(700))
    H.ok(cov and cov.known == 1 and cov.total == 2,
        "книга закрыла 1 материал из 2")
    H.eq(total, nil, "и целиком фактической себестоимости нет")
    H.eq(conf, CONF.UNKNOWN, "это «не знаю», а не частичная сумма, выданная за полную")

    local mixed, mConf, mCov = L:MaterialCost(ns.RecipeBook:Get(700))
    H.eq(mixed, 35 + 80, "смешанная сумма считается: своя цена плюс оценка")
    H.eq(mConf, CONF.ESTIMATE, "и помечена оценкой, потому что часть - оценка")
    H.ok(mCov and mCov.known == 1 and mCov.total == 2, "с названной долей своих данных")
end

H.suite("Книга закупок: цена безубыточности говорится прямо")
do
    local env, ns = fresh()
    local L = ns.Ledger
    env.auctionator = false
    H.item(env, 70, { name = "Ткань", sellPrice = 10 })
    H.item(env, 71, { name = "Жилет", sellPrice = 50 })
    H.profession(env, "Портняжное дело", 50, 75, {
        H.recipe({ id = 700, name = "Жилет", output = 71, outputQty = 2,
                   reagents = { { itemID = 70, qty = 5 } }, diff = "medium" }),
    })
    H.rescan(env)
    L:Note(L:Observe(snap(10000, { [70] = 0 }), snap(9900, { [70] = 10 }),
        L.WHERE.VENDOR, H.serverTime))
    ns.PriceProvider:BeginPass()
    ns.CraftingPlanner:Bind(ns.RecipeBook, ns.PriceProvider):BeginPass()

    local be = L:Breakeven(ns.RecipeBook:Get(700))
    H.ok(be ~= nil, "безубыточность посчитана")
    if be then
        -- 5 ткани по 10 = 50 за крафт, крафт даёт 2 штуки -> 25 за штуку.
        H.eq(be.unitCost, 25, "себестоимость за штуку: " .. tostring(be.unitCost))
        -- Аукцион забирает свой сбор, значит выставлять надо выше себестоимости.
        local cut = ns.PriceProvider.AH_CUT
        H.near(be.listPrice, 25 / (1 - cut), 1,
            "цена выставления, при которой выходим в ноль: " .. tostring(be.listPrice))
        H.ok(be.listPrice > be.unitCost,
            "и она ВЫШЕ себестоимости — сбор аукциона никто не отменял")
        H.eq(be.cut, cut, "сбор назван")
        H.eq(be.conf, CONF.EXACT, "достоверность - по своей книге")
        H.eq(be.source, "ledger", "и источник назван своим")

        -- И это сказано словами, прямо.
        local text = L:BreakevenText(ns.RecipeBook:Get(700))
        H.ok(type(text) == "string" and text ~= "", "фраза есть: " .. tostring(text))
        H.ok(ns.Util.contains(text, "минус"),
            "и в ней прямо сказано про минус: " .. tostring(text))
        H.ok(text:find(ns.Util.money(ns.Util.round(be.listPrice)), 1, true) ~= nil,
            "и названа сама цена: " .. tostring(text))
    end
end

H.suite("Книга закупок: без данных безубыточность не выдумывается")
do
    local env, ns = fresh()
    local L = ns.Ledger
    env.auctionator = false
    H.item(env, 71, { name = "Жилет" })
    H.profession(env, "Портняжное дело", 50, 75, {
        H.recipe({ id = 700, name = "Жилет", output = 71, outputQty = 1,
                   reagents = { { itemID = 70, qty = 5 } }, diff = "medium" }),
    })
    H.rescan(env)
    ns.PriceProvider:BeginPass()
    ns.CraftingPlanner:Bind(ns.RecipeBook, ns.PriceProvider):BeginPass()

    local be = L:Breakeven(ns.RecipeBook:Get(700))
    H.eq(be, nil, "цены материалов нет - безубыточности нет")
    local text = L:BreakevenText(ns.RecipeBook:Get(700))
    H.ok(text == nil or ns.Util.contains(text, "не"),
        "и фраза об этом не обещает числа: " .. tostring(text))
end

H.suite("Книга закупок: «что я заплатил» против «что сейчас на рынке»")
do
    local env, ns = fresh()
    local L = ns.Ledger
    H.item(env, 70, { name = "Ткань", sellPrice = 10 })
    env.auctionator = true
    env.prices = { [70] = 200 }
    H.rescan(env)
    L:Note(L:Observe(snap(10000, { [70] = 0 }), snap(9000, { [70] = 10 }),
        L.WHERE.AUCTION, H.serverTime - 3600))

    ns.PriceProvider:BeginPass()
    local cmp = L:PaidVsMarket(70)
    H.ok(cmp ~= nil, "сравнение считается")
    if cmp then
        H.eq(cmp.paid, 100, "заплачено за штуку")
        H.eq(cmp.market, 200, "на рынке сейчас")
        H.eq(cmp.diff, 100, "разница")
        H.near(cmp.ratio, 2, 0.001, "во сколько раз")
        H.eq(cmp.verdict, "dearer", "вердикт: сейчас дороже, чем я брал")
        H.ok(cmp.paidAge ~= nil, "и возраст своей цены известен")
        H.ok(ns.Util.contains(cmp.text, "Вы платили"),
            "фраза обращается к игроку: " .. tostring(cmp.text))
    end

    -- Рынок дешевле моей покупки. Память цен Auctionator переживает пересчёт
    -- (она сбрасывается по сроку и по визиту на аукцион), поэтому подмена
    -- цены в стенде - это ровно тот случай, когда её надо сбросить.
    env.prices = { [70] = 50 }
    ns.Api:ClearAuctionCache("тест подменил цену")
    ns.PriceProvider:BeginPass()
    local cheap = L:PaidVsMarket(70)
    H.eq(cheap and cheap.verdict, "cheaper", "вердикт меняется на «сейчас дешевле»")

    -- Рынка нет вовсе: сравнивать не с чем, и это НЕ «цены равны».
    env.auctionator = false
    env.prices = {}
    H.rescan(env)
    ns.Api:ClearAuctionCache("тест убрал Auctionator")
    ns.PriceProvider:BeginPass()
    local noMarket = L:PaidVsMarket(70)
    H.eq(noMarket and noMarket.verdict, "no_market", "без рынка вердикт свой")
    H.eq(noMarket and noMarket.market, nil, "и рыночного числа нет")

    -- Своей цены нет: тоже отдельный случай.
    H.eq(L:PaidVsMarket(999), nil, "про незнакомый предмет сравнения не выдумывается")
end

H.suite("Книга закупок: записей не бесконечно много")
do
    local env, ns = fresh()
    local L = ns.Ledger
    local cap = ns.Config.LEDGER_MAX_ENTRIES
    H.ok(type(cap) == "number" and cap > 0, "предел числа записей назван: " .. tostring(cap))
    local money = 10000000
    for i = 1, cap + 25 do
        L:Note(L:Observe(snap(money, { [7] = i - 1 }), snap(money - 100, { [7] = i }),
            L.WHERE.VENDOR, H.serverTime + i))
        money = money - 100
    end
    local entries = ns.Config:LedgerEntries()
    H.ok(#entries <= cap, "журнал обрезан по пределу: " .. #entries)
    H.ok(#entries >= cap - 1, "но и не выброшен целиком: " .. #entries)
    -- Обрезается СТАРОЕ, а итоги по предмету не теряются.
    H.eq(entries[#entries].t, H.serverTime + cap + 25, "последняя запись - самая свежая")
    local _, _, info = L:Paid(7)
    H.eq(info and info.qty, cap + 25, "а суммарно по предмету учтено всё")
end

H.suite("Книга закупок: книгу можно стереть, и она становится пустой")
do
    local env, ns = fresh()
    local L = ns.Ledger
    L:Note(L:Observe(snap(10000, { [7] = 0 }), snap(9500, { [7] = 5 }),
        L.WHERE.VENDOR, H.serverTime))
    H.ok(L:Count() > 0, "запись есть")
    local n = ns.Config:ClearLedger()
    H.eq(n, 1, "стёрто записей: " .. tostring(n))
    H.eq(L:Count(), 0, "книга пуста")
    H.eq(L:Paid(7), nil, "и себестоимости по ней больше нет")
end

H.suite("Книга закупок: про себя рассказывает честно")
do
    local env, ns = fresh()
    local L = ns.Ledger
    local rep = L:Report()
    H.ok(type(rep) == "table", "отчёт есть")
    H.eq(rep.entries, 0, "пустая книга так и сказана")
    H.ok(type(rep.gaps) == "table" and #rep.gaps > 0,
        "и названы случаи, которых книга НЕ видит")
    for _, gap in ipairs(rep.gaps or {}) do
        H.ok(type(gap) == "string" and ns.Util.charLen(gap) > 15,
            "пробел объяснён словами: " .. tostring(gap))
    end

    -- Источник в общей сводке «откуда что взято».
    local rows = ns.Provenance:Rows()
    local byKey = {}
    for _, r in ipairs(rows) do byKey[r.key] = r end
    H.ok(byKey.ledger ~= nil, "строка про свою книгу есть в сводке источников")
    if byKey.ledger then
        H.ok(byKey.ledger.conf ~= nil, "с достоверностью")
        H.ok(byKey.ledger.fresh and byKey.ledger.fresh ~= "", "и со свежестью")
        H.ok(byKey.ledger.conf ~= CONF.UNKNOWN,
            "пустая своя книга - это не «источник не отвечает»")
    end
end

H.suite("Книга закупок: чужая книга помечена чужой и у неё есть план отказа")
do
    local env, ns = fresh()
    H.ok(type(ns.FOREIGN_BOOK) == "table", "чужой источник описан в одном месте")
    if type(ns.FOREIGN_BOOK) == "table" then
        H.ok(ns.FOREIGN_BOOK.name and ns.FOREIGN_BOOK.name ~= "", "назван: "
            .. tostring(ns.FOREIGN_BOOK.name))
        H.ok(ns.Util.charLen(ns.FOREIGN_BOOK.why or "") > 20,
            "сказано, почему ему меньше веры: " .. tostring(ns.FOREIGN_BOOK.why))
        H.ok(ns.Util.charLen(ns.FOREIGN_BOOK.plan or "") > 20,
            "и что с ним будет дальше: " .. tostring(ns.FOREIGN_BOOK.plan))
    end
end

H.suite("Книга закупок: из событий игры, и ни одно не выдумано")
do
    local env, ns = fresh()
    local L = ns.Ledger
    -- Все события, на которые книга опирается, должны быть в карте событий или
    -- в сигналах - то есть на них аддон действительно подписывается, и Events
    -- проверяет их наличие на клиенте через C_EventUtils.IsEventValid.
    local known = {}
    for name in pairs(ns.Events.EVENT_MAP) do known[name] = true end
    for name in pairs(ns.Events.SIGNAL_ONLY) do known[name] = true end
    for name in pairs(ns.Events.PASSTHROUGH) do known[name] = true end

    H.ok(type(L.NEEDS_EVENTS) == "table" and #L.NEEDS_EVENTS > 0,
        "книга перечисляет, на чём держится: " .. #(L.NEEDS_EVENTS or {}))
    local orphans = {}
    for _, name in ipairs(L.NEEDS_EVENTS or {}) do
        if not known[name] then orphans[#orphans + 1] = name end
    end
    H.eq(#orphans, 0, "каждое нужное событие аддон действительно слушает"
        .. ((#orphans > 0) and ("  <- " .. table.concat(orphans, ", ")) or ""))

    -- И ни одной покупки аддон не делает: проверка на запрещённые вызовы живёт
    -- в test_ui/test_sense и идёт по всем файлам из .toc, включая этот модуль.
    H.ok(ns.Ledger.Buy == nil and ns.Ledger.Purchase == nil,
        "в книге нет ничего, что само покупает")
end

H.suite("Книга закупок: подписка работает целиком, от события до записи")
do
    -- ЭТО ЕДИНСТВЕННОЕ МЕСТО, ГДЕ ПРОВЕРЯЕТСЯ САМА ПОДПИСКА. Стенд её снимает
    -- (иначе каждый чужой набор начал бы писать в книгу), поэтому здесь она
    -- ставится обратно и события подаются так, как их подаёт игра.
    local env, ns = fresh()
    local L = ns.Ledger
    L.bound = false
    H.ok(L:Bind(), "подписка поставлена")
    H.ok(not L:Bind(), "и второй раз не ставится")

    env.money = 10000
    env.bags = { [7] = 0 }
    L:Reset()

    -- Игра: игрок открыл окно торговца.
    ns.Events:OnEvent("MERCHANT_SHOW")
    H.ok(L.atVendor, "книга знает, что игрок у торговца")
    H.ok(L.pending ~= nil, "и запомнила состояние до покупки")

    -- Игрок купил 5 штук за 500. Клиент присылает деньги и сумки по
    -- отдельности, а окно торговца - своё обновление.
    env.money = 9500
    env.bags = { [7] = 5 }
    ns.Events:OnEvent("MERCHANT_UPDATE")
    H.eq(L:Count(), 1, "покупка записана по событию окна торговца")
    H.eq(L:Paid(7), 100, "с правильной ценой за штуку")

    -- Окно закрылось: контекст снимается, иначе добыча в поле попадёт в книгу.
    ns.Events:OnEvent("MERCHANT_CLOSED")
    H.ok(not L.atVendor, "после закрытия окна игрок больше не «у торговца»")

    -- Добыча в поле: сумки и деньги меняются, записи быть НЕ должно.
    env.money = 9600
    env.bags = { [7] = 5, [8] = 3 }
    ns.Events:MarkDirty("bags", "money")
    ns.Events:Run(true)
    H.eq(L:Count(), 1, "вне торговца и аукциона запись не появилась")
    H.eq(L:Paid(8), nil, "и подобранное не стало покупкой")

    -- А у аукциона - должна.
    ns.Events:OnEvent("AUCTION_HOUSE_SHOW")
    env.money = 9000
    env.bags = { [7] = 5, [8] = 3, [9] = 2 }
    ns.Events:MarkDirty("money", "bags")
    ns.Events:Run(true)
    H.eq(L:Count(), 2, "покупка на аукционе записана")
    H.eq(L:Paid(9), 300, "с ценой за штуку: " .. tostring(L:Paid(9)))
    ns.Events:OnEvent("AUCTION_HOUSE_CLOSED")
    H.ok(not L.atAuction, "после закрытия аукциона контекст снят")
end

H.suite("Книга закупок: сохранения старше книги не ломаются")
do
    local env, ns = fresh()
    -- Файл игрока, записанный ДО появления книги: поля ledger в нём нет вовсе.
    local old = { profile = "POWER", vendorPrices = { [7] = 100 } }
    ns.Config:Bind(old, {})
    H.ok(type(ns.Config:Ledger()) == "table", "книга заводится на старом файле")
    H.eq(ns.Ledger:Count(), 0, "и она пуста")
    local e = ns.Ledger:Observe(snap(10000, { [7] = 0 }), snap(9500, { [7] = 5 }),
        ns.Ledger.WHERE.VENDOR, H.serverTime)
    H.ok(ns.Ledger:Note(e), "и запись в неё ложится")
    H.eq(ns.Ledger:Paid(7), 100, "себестоимость считается")

    -- И полуразрушенная книга: поля есть, таблиц нет.
    local half = { ledger = { meta = { entries = 3 } } }
    ns.Config:Bind(half, {})
    local e2 = ns.Ledger:Observe(snap(10000, { [8] = 0 }), snap(9800, { [8] = 2 }),
        ns.Ledger.WHERE.VENDOR, H.serverTime)
    H.ok(ns.Ledger:Note(e2), "запись ложится и в недостроенную книгу")
    H.eq(ns.Ledger:Paid(8), 100, "и читается обратно")
end

H.suite("Книга закупок: неточный ответ клиента снимком не считается")
do
    local env, ns = fresh()
    local L = ns.Ledger
    -- В сумках ОДИН вид предмета. Клиент перестал отдавать сумки и ответил
    -- пустой таблицей с пометкой «неизвестно» - ровно так Api:BagCounts ведёт
    -- себя без функций чтения сумок. Если принять это за снимок, «сумки
    -- опустели» плюс «денег прибыло» сложится в правдоподобную продажу.
    env.money = 10000
    env.bags = { [7] = 5 }
    L:Reset()
    H.ok(L:Remember("до"), "снимок на точных данных берётся")

    local realBagCounts = ns.Api.BagCounts
    ns.Api.BagCounts = function() return {}, ns.CONF.UNKNOWN, {} end
    env.money = 10500
    local entry, why = L:Settle(L.WHERE.VENDOR)
    ns.Api.BagCounts = realBagCounts

    H.eq(entry, nil, "по неточному ответу клиента запись НЕ делается")
    H.eq(L:Count(), 0, "книга осталась пустой")
    H.eq(L:Paid(7), nil, "и ложной продажи в ней нет")
end

H.suite("Книга закупок: сверка из живого мира, без ручных снимков")
do
    local env, ns = fresh()
    local L = ns.Ledger
    env.money = 10000
    env.bags = { [7] = 0 }
    L:Reset()
    L:Remember("окно торговца открылось")
    H.ok(L.pending ~= nil, "снимок до покупки сделан")

    -- Игрок купил. Мир изменился.
    env.money = 9500
    env.bags = { [7] = 5 }
    local entry, why = L:Settle(ns.Ledger.WHERE.VENDOR)
    H.ok(entry ~= nil, "сверка нашла покупку" .. (entry and "" or (": " .. tostring(why))))
    H.eq(entry and entry.unit, 100, "с ценой за штуку")
    H.eq(L:Count(), 1, "и записала её")
    H.ok(L.pending ~= nil, "и сразу запомнила новое состояние — для следующей покупки")

    -- Вторая покупка в том же окне торговца.
    env.money = 9400
    env.bags = { [7] = 6 }
    local e2 = L:Settle(ns.Ledger.WHERE.VENDOR)
    H.eq(e2 and e2.unit, 100, "вторая покупка в том же окне тоже записана")
    H.eq(L:Count(), 2, "записей две")
end

end
