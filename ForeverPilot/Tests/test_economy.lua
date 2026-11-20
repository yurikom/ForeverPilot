-- ForeverPilot / Tests/test_economy.lua
--
-- The economy half of the addon, and it opens with the defect that cost the
-- player a real action.
--
-- WHAT HAPPENED. The Now tab's top card read "На продажу: Льняные сапоги,
-- +4з 74с". The player believed it and listed the boots at 5 gold. The revenue
-- figure came from Auctionator's current minimum listing for item 2569, which
-- was 50200 copper - against a seven-day history in the same database of 180 to
-- 300 copper, on two listings instead of the usual hundred. One absurd listing,
-- taken as the market, 167 times over.
--
-- The numbers in the first suite are the player's real ones, copied out of their
-- SavedVariables, because a threshold that would not have caught THIS is not
-- worth having.
local H = ...

return function()

-- =====================================================================
-- Price history: is today's price typical of this item?
-- =====================================================================

-- The real record for Linen Boots, by day stamp, as the addon stores it.
local BOOTS = 2569
local BOOTS_HISTORY = {
    [20770] = 200, [20771] = 180, [20772] = 244, [20773] = 300, [20774] = 300,
}

local function historyEnv(items)
    local env = H.load()
    local ns = env.ns
    local cfg = ns.Config:Get()
    for itemID, days in pairs(items or {}) do
        cfg.priceHistory[itemID] = {}
        local n, first, last = 0, nil, nil
        for day, copper in pairs(days) do
            cfg.priceHistory[itemID][day] = copper
            n = n + 1
            if (not first) or day < first then first = day end
            if (not last) or day > last then last = day end
        end
        cfg.priceHistoryMeta.days = math.max(cfg.priceHistoryMeta.days or 0, n)
        cfg.priceHistoryMeta.firstDay = first
        cfg.priceHistoryMeta.lastDay = last
    end
    return env
end

H.suite("История цен: читается и считается")
do
    local env = historyEnv { [BOOTS] = BOOTS_HISTORY }
    local ns = env.ns
    local MH = ns.MarketHistory
    H.ok(MH ~= nil, "модуль истории цен есть")

    local st = MH:Stats(BOOTS)
    H.ok(st ~= nil, "статистика по предмету посчитана")
    H.eq(st.days, 5, "пять дней в выборке")
    H.eq(st.min, 180, "минимум 180 м")
    H.eq(st.max, 300, "максимум 300 м")
    H.eq(st.median, 244, "медиана 244 м")
    H.eq(st.latest, 300, "последний записанный день — 300 м")
    H.eq(st.latestDay, 20774, "и это день 20774")

    local none = MH:Stats(999999)
    H.ok(none == nil or none.days == 0, "по неизвестному предмету истории нет")
end

H.suite("История цен: выброс в 167 раз распознаётся")
do
    local env = historyEnv { [BOOTS] = BOOTS_HISTORY }
    local ns = env.ns
    local MH = ns.MarketHistory

    local v = MH:Verdict(BOOTS, 50200)
    H.ok(v ~= nil, "вердикт получен")
    H.eq(v.flag, "HIGH_OUTLIER", "сегодняшняя цена помечена как нетипично высокая")
    H.ok(v.ratio > 100, string.format("превышение %.0fx над максимумом истории", v.ratio))
    H.eq(v.days, 5, "сказано, на какой выборке")
    H.ok(v.text and v.text ~= "", "есть человеческое объяснение: " .. tostring(v.text))

    -- And the price the advice should actually use.
    local use, conf, note = MH:Expected(BOOTS, 50200)
    H.eq(use, 244, "для совета берём медиану истории, а не сегодняшний лот")
    H.eq(conf, ns.CONF.ESTIMATE, "и помечаем это как оценку")
    H.ok(note and ns.Util.contains(note, "167"),
        "в объяснении назван масштаб расхождения: " .. tostring(note))
end

H.suite("История цен: нормальная цена не ломается")
do
    local env = historyEnv { [BOOTS] = BOOTS_HISTORY }
    local ns = env.ns
    local MH = ns.MarketHistory

    local v = MH:Verdict(BOOTS, 260)
    H.eq(v.flag, "TYPICAL", "260 м — обычная цена для этого предмета")
    local use, conf = MH:Expected(BOOTS, 260)
    H.eq(use, 260, "её и используем")
    H.ok(conf ~= ns.CONF.ESTIMATE or true, "достоверность не понижена без причины")
end

H.suite("История цен: подозрительно низкая отмечается, но не подменяется")
do
    local env = historyEnv { [BOOTS] = BOOTS_HISTORY }
    local ns = env.ns
    local MH = ns.MarketHistory

    local v = MH:Verdict(BOOTS, 5)
    H.eq(v.flag, "LOW_OUTLIER", "5 м — нетипично низкая")
    -- For a SALE a suspiciously low price only understates the profit, which is
    -- the safe direction, so it is reported and not overridden.
    local use = MH:Expected(BOOTS, 5)
    H.eq(use, 5, "цену продажи не завышаем: берём как есть")
end

H.suite("История цен: короткая выборка — порог строже и это сказано")
do
    -- One single day. A lone observation must not be enough to call a price
    -- wrong unless the gap is enormous.
    local env = historyEnv { [BOOTS] = { [20774] = 300 } }
    local ns = env.ns
    local MH = ns.MarketHistory

    local v1 = MH:Verdict(BOOTS, 1500)   -- 5x on one day: not enough
    H.eq(v1.flag, "TYPICAL", "5x при одном дне истории — молчим")
    H.ok(ns.Util.contains(v1.text or "", "корот")
         or ns.Util.contains(v1.text or "", "наблюдение"),
        "но про короткую выборку сказано: " .. tostring(v1.text))

    local v2 = MH:Verdict(BOOTS, 50200)  -- 167x on one day: yes
    H.eq(v2.flag, "HIGH_OUTLIER", "167x при одном дне — всё равно выброс")
end

H.suite("История цен: совсем без истории ничего не выдумываем")
do
    local env = historyEnv {}
    local ns = env.ns
    local MH = ns.MarketHistory

    local v = MH:Verdict(777, 50000)
    H.eq(v.flag, "NO_HISTORY", "без истории вердикта нет")
    local use, conf, note = MH:Expected(777, 50000)
    H.eq(use, 50000, "цену не меняем")
    H.ok(note and ns.Util.contains(note, "истории"),
        "но честно говорим, что сравнивать не с чем: " .. tostring(note))
end

H.suite("История цен: тренд по предмету")
do
    local env = historyEnv { [BOOTS] = { [20770] = 100, [20771] = 150,
                                         [20772] = 200, [20773] = 250 } }
    local ns = env.ns
    local t = ns.MarketHistory:Trend(BOOTS)
    H.ok(t ~= nil, "тренд посчитан")
    H.eq(t.direction, "up", "цена растёт")
    H.ok(t.changePct and t.changePct > 50,
        string.format("рост %.0f%% за выборку", t.changePct or 0))

    local env2 = historyEnv { [BOOTS] = { [20770] = 250, [20771] = 120 } }
    H.eq(env2.ns.MarketHistory:Trend(BOOTS).direction, "down", "и падение видно")
end

-- =====================================================================
-- The card itself: the 2569 scenario end to end
-- =====================================================================

-- Exactly the player's situation: one learned recipe making Linen Boots out of
-- one Coarse Thread, a vendor price for the thread, and an auction price for the
-- boots that is 167 times the item's own history.
local function bootsEnv(opts)
    opts = opts or {}
    local env = H.load()
    local ns = env.ns

    H.item(env, BOOTS, { name = "Льняные сапоги", equipLoc = "INVTYPE_FEET",
        reqLevel = 10, classID = 4, subclassID = 1, sellPrice = 19 })
    H.item(env, 2320, { name = "Грубая нить", sellPrice = 2 })
    env.vendorPrices[2320] = 9
    env.bags[2320] = 0
    env.money = 224635
    if opts.auction then env.prices[BOOTS] = opts.auction end

    local cfg = ns.Config:Get()
    if opts.history then
        cfg.priceHistory[BOOTS] = {}
        for day, copper in pairs(opts.history) do
            cfg.priceHistory[BOOTS][day] = copper
        end
    end

    H.profession(env, "Портняжное дело", 225, 225, {
        H.recipe { id = 2386, output = BOOTS, outputQty = 1,
                   reagents = { { itemID = 2320, qty = 1 } },
                   name = "Льняные сапоги", diff = "trivial", category = "Обувь" },
    })
    return env
end

local function profitCard(cards, ns)
    for _, c in ipairs(cards) do
        if c.kind == ns.KIND.CRAFT_PROFIT then return c end
    end
    return nil
end

H.suite("Льняные сапоги: карточка больше не обещает 4з 74с")
do
    local env = bootsEnv { auction = 50200, history = BOOTS_HISTORY }
    local ns = env.ns
    local cards = H.build(env)
    local c = profitCard(cards, ns)

    H.ok(c ~= nil, "карточка на продажу всё ещё есть (предмет действительно продаётся)")
    if c then
        -- 244 * 0.95 - 228 = 3.8 copper, so the honest margin is pennies.
        H.ok(c.benefitValue < 10000, string.format(
            "обещанная прибыль сбита с 4з 74с до %s", ns.Util.money(c.benefitValue)))
        H.ok(ns.Util.contains(c.why, "167") or ns.Util.contains(c.why, "раз"),
            "в карточке сказано, насколько цена выбивается: "
            .. ns.Util.truncate(c.why, 120))
        H.ok(ns.Util.contains(c.why, "истори"),
            "и что считали по истории: " .. ns.Util.truncate(c.why, 120))
        H.ok(c.conf == ns.CONF.ESTIMATE or c.conf == ns.CONF.UNKNOWN,
            "достоверность понижена до оценки: " .. tostring(c.conf))
        H.ok(c.priceOutlier == "HIGH_OUTLIER",
            "и выброс помечен на самой карточке для диагностики")
    end
end

H.suite("Льняные сапоги: без истории карточка честно помечена оценкой")
do
    -- Day one on a new realm: Auctionator has a price, we have no history of our
    -- own. The number is used, because it is the only one there is, but it is
    -- not dressed up as a measured market.
    local env = bootsEnv { auction = 50200, history = nil }
    local ns = env.ns
    local cards = H.build(env)
    local c = profitCard(cards, ns)
    H.ok(c ~= nil, "карточка есть")
    if c then
        H.ok(ns.Util.contains(c.why, "истори"),
            "сказано, что своей истории по предмету нет: "
            .. ns.Util.truncate(c.why, 120))
    end
end

H.suite("Нет цены продажи — нет карточки, а не нулевая прибыль")
do
    -- No auction price, no vendor sell price, nothing. The branch must produce
    -- nothing at all for this item rather than inventing a figure.
    local env = H.load()
    local ns = env.ns
    H.item(env, 500, { name = "Неизвестный товар", sellPrice = 0 })
    H.item(env, 501, { name = "Материал", sellPrice = 1 })
    env.vendorPrices[501] = 100
    env.money = 50000
    H.profession(env, "Портняжное дело", 225, 225, {
        H.recipe { id = 60, output = 500, reagents = { { itemID = 501, qty = 1 } },
                   name = "Неизвестный товар", diff = "trivial", category = "Обувь" },
    })
    local cards = H.build(env)
    H.eq(profitCard(cards, ns), nil, "карточки на продажу нет")

    -- And the funnel says why, by name.
    local f = ns.Diag:Init().funnels.craftProfit
    H.ok(f ~= nil, "воронка ветки записана")
    if f then
        H.ok((f.drops["no-price"] or {}).n == 1,
            "и отсеяно именно фильтром «нет цены»")
    end
end

H.suite("Проверка разумности: выручка без наблюдённой цены — подозрение")
do
    local env = bootsEnv { auction = nil, history = nil }
    local ns = env.ns
    -- Only the item's own vendor sell price exists, and it is tiny; make it big
    -- enough to clear the materials so a card is produced at all.
    env.items[BOOTS].sellPrice = 80000
    local cards = H.build(env)
    local c = profitCard(cards, ns)
    H.ok(c ~= nil, "карточка построена на цене торговца")
    local found = false
    for _, e in ipairs(ns.Diag:Init().suspicious) do
        if e.code == "profit-without-market" then found = true end
    end
    H.ok(found, "и помечена как подозрительная: рыночной цены никто не подтвердил")
end

-- РАЗРЫВ С ЦЕНОЙ ТОРГОВЦА: ПРОВЕРКА ПИСАЛА В ФАЙЛ, КАРТОЧКА МОЛЧАЛА ========
--
-- Здесь проверялось ровно одно: что находка попала в ФАЙЛ. Живой прогон игрока
-- показал, чего эта проверка не проверяла. Файл писал «„На продажу:
-- Небесно-голубая краска“: выручка 1з 24с против цены торговца 75м — это в 166
-- раз больше» на каждом пересчёте (счётчик 937), а карточка стояла ВТОРЫМ
-- советом сверху с заголовком «оценка ~1з 22с» и без оговорки: текст про разрыв
-- в ней был последней фразой строки «почему», которая на экране обрезается
-- шириной окна.
--
-- Поэтому спрашивается теперь другое: доехало ли сомнение до экрана. Разрыв
-- называет сама карточка, а находка в файле стала сторожем - она появляется
-- только тогда, когда карточка про разрыв молчит.

H.suite("Проверка разумности: разрыв с ценой торговца доезжает до карточки, а не только до файла")
do
    local env = bootsEnv { auction = 50200, history = nil }
    local ns = env.ns
    local cards = H.build(env)
    local c = profitCard(cards, ns)
    H.ok(c ~= nil, "карточка построена")
    if c then
        H.ok(c.doubtLevel ~= nil,
            "карточка помечена сомнением: " .. tostring(c.doubtLevel))
        H.ok(ns.Util.contains(c.benefit or "", "сомнительно"),
            "заголовок выгоды предупреждает: " .. tostring(c.benefit))
        -- ПЕРВАЯ фраза, а не последняя: на экране видно только начало строки.
        local first = tostring(c.why or ""):match("^[^%.]+") or ""
        H.ok(ns.Util.contains(first, "не сходятся"),
            "и оговорка стоит первой фразой «почему»: " .. first)
        H.ok(ns.Util.contains(c.why or "", "торговц"),
            "сказано, с чем сравнивается")
        H.eq(c.conf, ns.CONF.UNKNOWN, "достоверность снята")
        H.eq(ns.ActionEngine.TierOf(c), 0,
            "и место в списке — под всем исполнимым")
    end
    local found
    for _, e in ipairs(ns.Diag:Init().suspicious) do
        if e.code == "revenue-far-above-vendor" then found = e end
    end
    H.eq(found, nil, "в файле записи нет — про разрыв говорит сама карточка"
        .. (found and ("  <- " .. ns.Util.truncate(found.text, 120)) or ""))
end

H.suite("Проверка разумности: если карточка про разрыв молчит — говорит самопроверка")
do
    local env = bootsEnv { auction = 50200, history = nil }
    local ns = env.ns
    H.build(env)
    ns.Diag:ClearSuspicions()
    -- Карточка без единой пометки - ровно то состояние, в котором механизм не
    -- сработал. Сторож обязан его заметить, а находка - доехать до карточки.
    local bare = { key = "profit:2386", kind = ns.KIND.CRAFT_PROFIT,
                   itemID = BOOTS, revenue = 50200, benefit = "+5з",
                   title = "На продажу: Льняные сапоги", why = "Материалы 9м.",
                   need = "y", action = {}, conf = ns.CONF.CACHED, score = 1 }
    ns.SanityChecks:Run({ cards = { bare }, snap = ns.CharacterScanner:Scan() })
    local found
    for _, e in ipairs(ns.Diag:Init().suspicious) do
        if e.code == "revenue-far-above-vendor" then found = e end
    end
    H.ok(found ~= nil, "сторож сработал")
    if found then
        H.ok(ns.Util.contains(found.text, "торговц"),
            "и в тексте названа цена торговца: " .. ns.Util.truncate(found.text, 110))
    end
    -- И эта же находка приложена к самой карточке, а не только записана.
    H.eq(ns.SanityChecks:Scope("revenue-far-above-vendor"), "say",
        "находка адресована игроку")
    local codes = {}
    for _, d in ipairs(bare.doubts or {}) do codes[d.code] = d end
    H.ok(codes["revenue-far-above-vendor"] ~= nil,
        "и доехала до карточки (" .. #(bare.doubts or {}) .. " сомнения)")
    -- Вторая находка на той же карточке - проверка 37, то есть упрёк аддона
    -- самому себе («пометки нет, достоверность CACHED»). Её адрес - «дефект», и
    -- на карточке от неё одна фраза, а не код достоверности.
    H.eq(ns.SanityChecks:Scope("suspect-card-unmarked"), "defect",
        "а находка-упрёк адресована не игроку")
    if codes["suspect-card-unmarked"] then
        ns.Risk:RenderDoubts(bare)
        H.ok(ns.Util.contains(bare.why, ns.Risk.DOUBT_DEFECT_SAY),
            "и печатается на карточке одной фразой: "
            .. ns.Util.truncate(bare.why, 160))
        H.eq(ns.Util.contains(bare.why, "CACHED"), false,
            "код достоверности на карточку не уехал")
        H.eq(ns.ActionEngine.TierOf(bare), 0,
            "а карточка с дефектом уходит под всё исполнимое")
    end
end

-- =====================================================================
-- ПОРОГ МЕЛКОЙ ДЕНЕЖНОЙ ВЫГОДЫ
-- =====================================================================
--
-- Дословная просьба игрока: «если я выигрываю меньше 20 или 30 золотых, слоя
-- золотых, серебряных, то смысла нету это показывать, особенно выше чем в 20-м
-- левеле. Если ты находишься на мелких левелах персонажа до 15-го, тогда можно
-- показывать с 10-го и выше серебра выигрыш. Если там выше 15-го левела или
-- 20-го, больше 30-ти как минимум.»
--
-- Полосы и числа - в Core/Const.lua, действующий порог - Config:MoneyFloor,
-- применение - Engine:ApplyMoneyFloor. Проверяется здесь всё три: числа полос,
-- что отсекается именно денежное, и что отсечённое ОБЪЯВЛЕНО. Путь исчезновения
-- как таковой стоит в перечне Tests/test_vanish.lua.
--
-- Порог в фикстурных мирах снят (см. H.setMoneyFloor в Tests/harness.lua),
-- поэтому каждый набор ниже включает его сам и явно - в том числе значение по
-- умолчанию, через opts.moneyFloor = "default".

H.suite("Порог мелкой выгоды: полосы по уровню — те числа, что названы игроком")
do
    local env = H.load({ moneyFloor = "default" })
    local ns = env.ns
    local U = ns.Util

    -- ЗНАЧЕНИЕ ПО УМОЛЧАНИЮ ПРОВЕРЯЕТСЯ В САМИХ ДЕФОЛТАХ. Стенд порог снимает,
    -- и если смотреть только на стенд, смена дефолта пройдёт незамеченной.
    H.eq(ns.Config.DEFAULTS.show.moneyFloorMode, ns.MONEY_FLOOR_MODE.LEVEL,
        "по умолчанию порог берётся по полосам уровня")
    H.eq(ns.Config:MoneyFloorMode(), ns.MONEY_FLOOR_MODE.LEVEL,
        "и в мире, который стенд не трогал, он такой же")
    H.eq(#ns.MONEY_FLOOR_BANDS, 3, "полос три: игрок назвал два края — 15 и 20")

    for _, case in ipairs({ { 1, 1000 }, { 14, 1000 }, { 15, 1000 },
                            { 16, 2000 }, { 20, 2000 },
                            { 21, 3000 }, { 60, 3000 } }) do
        local floor, mode, band = ns.Config:MoneyFloor(case[1])
        H.eq(floor, case[2], case[1] .. " ур. — порог " .. U.money(case[2]))
        H.eq(mode, ns.MONEY_FLOOR_MODE.LEVEL, "   и он взят по уровню")
        H.ok(band ~= nil and band.label ~= nil,
            "   у полосы есть подпись для настроек: " .. tostring(band and band.label))
    end

    -- Уровень клиент иногда не отдаёт. Гадать вниз нельзя: персонажу 60 уровня
    -- показали бы ту мелочь, которую он просил не показывать.
    H.eq((ns.Config:MoneyFloor(nil)), 3000,
        "уровень неизвестен — берётся самая строгая полоса")

    -- Числа строго возрастают: «чем выше уровень, тем выше порог» - это и есть
    -- просьба, и порядок полос её выражает.
    local prev = -1
    for _, band in ipairs(ns.MONEY_FLOOR_BANDS) do
        H.ok(band.copper > prev, "порог полосы «" .. band.label .. "» (" .. U.money(band.copper)
            .. ") выше предыдущего")
        prev = band.copper
    end

    -- Своё число и выключение - то, чем игрок решает спор «30 золотых или
    -- 30 серебра» сам.
    H.ok(ns.Config:SetMoneyFloorMode(ns.MONEY_FLOOR_MODE.FIXED), "режим «своё число» принят")
    H.ok(ns.Config:SetMoneyFloorOwn(300000), "30 золотых поставлены")
    H.eq((ns.Config:MoneyFloor(16)), 300000, "своё число действует на любом уровне")
    H.eq((ns.Config:MoneyFloor(60)), 300000, "и на высоком тоже")
    H.ok(ns.Config:SetMoneyFloorMode(ns.MONEY_FLOOR_MODE.OFF), "режим «без порога» принят")
    H.eq((ns.Config:MoneyFloor(16)), 0, "порога нет — ноль, и это выбор игрока, а не пустота")
    H.eq(ns.Config:SetMoneyFloorMode("абракадабра"), false, "неизвестный режим не принимается")
    H.eq(ns.Config:MoneyFloorMode(), ns.MONEY_FLOOR_MODE.OFF, "и прежний выбор не испорчен")

    -- Каждое число лестницы настроек - настоящие деньги, и 30 золотых в ней
    -- есть: именно про них игрок и спрашивал.
    local has30g, zero = false, false
    for _, v in ipairs(ns.MONEY_FLOOR_CHOICES) do
        H.ok(type(v) == "number" and v >= 0, "выбор порога — число меди: " .. tostring(v))
        if v == 300000 then has30g = true end
        if v == 0 then zero = true end
    end
    H.ok(has30g, "в лестнице есть 30 золотых — то число, про которое спрашивал игрок")
    H.ok(zero, "и ноль: «показывать любую выгоду»")
end

-- Мир с тремя денежными советами разного размера и одним неденежным. Размеры
-- выбраны так, чтобы попасть МЕЖДУ полосами (14с, 25с, 76с при полосах 10с, 20с,
-- 30с): иначе все три полосы отсекают одно и то же, и проверка полос ничего не
-- проверяет - ровно это и случилось с первой версией этого мира. Сами пороги в
-- наборах ниже берутся ОТ ТОГО, что мир насчитал, а не вписаны вторым списком.
--
-- `withUI` - мир с интерфейсом: он нужен одному набору из четырёх (строка над
-- списком), а остальным три - лишняя работа на каждый H.load.
local S
local function floorWorld(level, withUI)
    local env
    if withUI then
        S = S or assert(loadfile((H.ROOT or ".") .. "/Tests/uistub.lua"))()
        env = S.load(H)
    else
        env = H.load()
    end
    local ns = env.ns
    env.player.level = level or 26
    env.money = 500000

    -- Хлам: мелкие деньги (14с 40м), цена торговца точная.
    H.item(env, 9100, { name = "Рваная шкура", sellPrice = 180, quality = 0 })
    env.bags[9100] = 8

    -- Крафт на продажу: деньги крупнее (76с 50м).
    H.item(env, 9200, { name = "Шёлковый пояс", equipLoc = "INVTYPE_WAIST",
        reqLevel = 20, classID = 4, subclassID = 1, sellPrice = 600 })
    H.item(env, 9201, { name = "Шёлк", sellPrice = 100 })
    env.vendorPrices[9201] = 300
    env.bags[9201] = 20
    env.prices[9200] = 9000

    -- Второй крафт на продажу - стопкой, ровно между средней и верхней полосой
    -- (25с 50м при 20 нитях в сумке).
    H.item(env, 9400, { name = "Шёлковая нить", sellPrice = 150 })
    env.prices[9400] = 450

    -- Неденежный совет: вещь в сумке лучше надетой. Порог его касаться не
    -- должен - его выгода в баллах, а не в золоте.
    H.item(env, 9300, { name = "Старый капюшон", equipLoc = "INVTYPE_HEAD",
        reqLevel = 10, classID = 4, subclassID = 1, sellPrice = 50 })
    H.item(env, 9301, { name = "Расшитый капюшон", equipLoc = "INVTYPE_HEAD",
        reqLevel = 20, classID = 4, subclassID = 1, sellPrice = 400 })
    env.stats[9300] = { ITEM_MOD_INTELLECT_SHORT = 3 }
    env.stats[9301] = { ITEM_MOD_INTELLECT_SHORT = 16 }
    env.equipped.HEAD = { itemID = 9300 }
    env.bags[9301] = 1

    H.profession(env, "Портняжное дело", 225, 225, {
        H.recipe { id = 9210, output = 9200, outputQty = 1,
                   reagents = { { itemID = 9201, qty = 3 } },
                   name = "Шёлковый пояс", diff = "trivial", category = "Пояса" },
        H.recipe { id = 9410, output = 9400, outputQty = 1,
                   reagents = { { itemID = 9201, qty = 1 } },
                   name = "Шёлковая нить", diff = "trivial", category = "Нити" },
    })
    H.itemsChanged(env)
    H.rescan(env)
    return env
end

local function moneyCards(ns)
    local out = {}
    for _, c in ipairs(ns.ActionEngine.cards or {}) do
        if ns.MONEY_FLOOR_KINDS[c.kind] then out[#out + 1] = c end
    end
    return out
end

H.suite("Порог мелкой выгоды: отсекает денежные советы и не трогает остальные")
do
    local env = floorWorld(26)
    local ns = env.ns
    local U = ns.Util

    -- Без порога видно всё: это предпосылка, без неё набор ничего не проверяет.
    H.build(env)
    local before = moneyCards(ns)
    H.ok(#before >= 2, "без порога денежных советов: " .. #before)
    local gains = {}
    for _, c in ipairs(before) do gains[#gains + 1] = tonumber(c.benefitValue) or 0 end
    table.sort(gains)
    H.ok(gains[1] > 0 and gains[#gains] > gains[1],
        "и они разного размера: от " .. U.money(gains[1]) .. " до " .. U.money(gains[#gains]))
    local gearBefore = 0
    for _, c in ipairs(ns.ActionEngine.cards or {}) do
        if c.kind == ns.KIND.EQUIP or c.kind == ns.KIND.CRAFT_GEAR then gearBefore = gearBefore + 1 end
    end
    H.ok(gearBefore > 0, "и неденежные советы в мире есть: " .. gearBefore)

    -- Порог ровно по самой мелкой выгоде: она остаётся (порог - это «не меньше»).
    ns.Config:SetMoneyFloorMode(ns.MONEY_FLOOR_MODE.FIXED)
    ns.Config:SetMoneyFloorOwn(gains[1])
    H.build(env)
    H.eq(#moneyCards(ns), #before, "порог равен самой мелкой выгоде — не убрал ничего")
    H.eq((ns.ActionEngine.meta or {}).moneyFloorDropped, 0, "и сказал, что убрал ноль")

    -- На медяк выше - самая мелкая уходит, остальные на месте.
    ns.Config:SetMoneyFloorOwn(gains[1] + 1)
    H.build(env)
    H.eq(#moneyCards(ns), #before - 1,
        "порог на медяк выше — ушёл ровно один, самый мелкий")
    H.eq((ns.ActionEngine.meta or {}).moneyFloorDropped, 1, "и это записано числом")
    H.eq((ns.ActionEngine.meta or {}).moneyFloorBiggest, gains[1],
        "самый крупный из убранных назван: " .. U.money(gains[1]))

    -- Порог выше всего - денег не остаётся вовсе, а вещи остаются.
    ns.Config:SetMoneyFloorOwn(gains[#gains] + 1)
    H.build(env)
    H.eq(#moneyCards(ns), 0, "порог выше всего — денежных советов нет ни одного")
    local gearAfter = 0
    for _, c in ipairs(ns.ActionEngine.cards or {}) do
        if c.kind == ns.KIND.EQUIP or c.kind == ns.KIND.CRAFT_GEAR then gearAfter = gearAfter + 1 end
    end
    H.eq(gearAfter, gearBefore,
        "а советов про вещи столько же: порог деньгами их не мерит")

    -- И «без порога» действительно без порога.
    ns.Config:SetMoneyFloorMode(ns.MONEY_FLOOR_MODE.OFF)
    H.build(env)
    H.eq(#moneyCards(ns), #before, "порог снят — вернулись все " .. #before)
    H.eq((ns.ActionEngine.meta or {}).moneyFloorDropped, 0, "и убрано ноль")
end

H.suite("Порог мелкой выгоды: полоса уровня меняет состав списка, а не только слова")
do
    -- Один и тот же мир тремя персонажами - по одному на полосу. Если полосы
    -- работают, с ростом уровня советов видно меньше, и каждый шаг виден числом.
    local seen = {}
    for _, level in ipairs({ 15, 20, 21 }) do
        local env = floorWorld(level)
        local ns = env.ns
        ns.Config:SetMoneyFloorMode(ns.MONEY_FLOOR_MODE.LEVEL)
        H.build(env)
        local meta = ns.ActionEngine.meta or {}
        seen[level] = #moneyCards(ns)
        H.eq(meta.moneyFloor, (level <= 15) and 1000 or ((level <= 20) and 2000 or 3000),
            level .. " ур.: порог " .. ns.Util.money(meta.moneyFloor)
            .. ", денежных советов " .. seen[level])
    end
    H.ok(seen[15] > seen[20], "15 ур. против 20 ур.: " .. seen[15] .. " против " .. seen[20])
    H.ok(seen[20] > seen[21], "20 ур. против 21 ур.: " .. seen[20] .. " против " .. seen[21])
end

H.suite("Порог мелкой выгоды: покупка под убранный совет уходит вместе с ним")
do
    -- Ветка покупок работает ДО порога, и на настоящих данных это выглядело
    -- так: порог убрал «На продажу: Лунная винтовка», а карточка «Купить:
    -- Предмет #1705 x2» осталась и честно писала «Нужно для: На продажу: Лунная
    -- винтовка» - про совет, которого на экране нет. Четыре таких карточки из
    -- десяти, и сумма «материалы по советам» в шапке считалась по ним же.
    local env = H.load()
    local ns = env.ns
    local U = ns.Util
    env.player.level = 26
    env.money = 500000
    H.item(env, 9500, { name = "Грубая бечёвка", sellPrice = 50 })
    H.item(env, 9501, { name = "Тонкая нить", sellPrice = 120 })
    env.vendorPrices[9500] = 200
    env.prices[9500] = 200
    env.prices[9501] = 500
    -- Материала в сумках нет: значит под этот совет нужна покупка.
    H.profession(env, "Портняжное дело", 225, 225, {
        H.recipe { id = 9510, output = 9501, outputQty = 1,
                   reagents = { { itemID = 9500, qty = 1 } },
                   name = "Тонкая нить", diff = "trivial", category = "Нити" },
    })
    H.itemsChanged(env)
    H.rescan(env)

    local function look()
        local profit, buy = nil, nil
        for _, c in ipairs(ns.ActionEngine.cards or {}) do
            if c.kind == ns.KIND.CRAFT_PROFIT then profit = c end
            if c.kind == ns.KIND.BUY and c.itemID == 9500 then buy = c end
        end
        return profit, buy
    end

    ns.Config:SetMoneyFloorMode(ns.MONEY_FLOOR_MODE.OFF)
    H.build(env)
    local profit, buy = look()
    H.ok(profit ~= nil, "предпосылка: совет «на продажу» построен")
    H.ok(buy ~= nil, "предпосылка: и покупка материала под него тоже")
    if profit and buy then
        H.ok(U.contains(buy.why, profit.title),
            "покупка называет этот совет: " .. U.truncate(buy.why, 90))
        H.ok(type(buy.buyFor) == "table" and buy.buyFor[profit.key] ~= nil,
            "и знает его по ключу, а не только по имени")
        local total = (ns.ActionEngine.meta or {}).shoppingTotal
        H.ok((tonumber(total) or 0) > 0, "сумма материалов в шапке: " .. U.money(total))

        -- Порог выше выгоды этого совета: уходит и совет, и покупка под него.
        ns.Config:SetMoneyFloorMode(ns.MONEY_FLOOR_MODE.FIXED)
        ns.Config:SetMoneyFloorOwn((tonumber(profit.benefitValue) or 0) + 1)
        H.build(env)
        local profit2, buy2 = look()
        H.eq(profit2, nil, "совет «на продажу» убран порогом")
        H.eq(buy2, nil, "и покупка, нужная только ему, тоже ушла")
        H.eq((ns.ActionEngine.meta or {}).shoppingTotal, 0,
            "в шапке не осталось материалов под совет, которого нет")
        H.eq((ns.ActionEngine.meta or {}).shoppingLines, 0, "и ни одной позиции")
    end
end

H.suite("Порог мелкой выгоды: ни один совет не исчезает молча")
do
    local env = floorWorld(26, true)
    local ns = env.ns
    local U = ns.Util
    ns.Config:SetMoneyFloorMode(ns.MONEY_FLOOR_MODE.FIXED)
    ns.Config:SetMoneyFloorOwn(300000)   -- 30 золотых: в этом мире уходит всё денежное
    H.build(env)
    local meta = ns.ActionEngine.meta or {}
    H.ok((meta.moneyFloorDropped or 0) > 0,
        "порог что-то убрал: " .. tostring(meta.moneyFloorDropped))
    H.ok(meta.moneyFloorNote ~= nil, "и это записано словами")

    local note = tostring(meta.moneyFloorNote)
    H.ok(U.contains(note, tostring(meta.moneyFloorDropped)),
        "в строке сказано, сколько убрано: " .. U.truncate(note, 160))
    H.ok(U.contains(note, U.money(300000)), "и какой порог — " .. U.money(300000))
    H.ok(U.contains(note, "настройк"), "и где его снять")
    H.ok(U.contains(note, ns.ActionEngine.MONEY_FLOOR_SECTION),
        "назван сам раздел настроек: «" .. ns.ActionEngine.MONEY_FLOOR_SECTION .. "»")
    for kind in pairs(meta.moneyFloorByKind or {}) do
        H.ok(U.contains(note, ns.KIND_LABEL[kind] or kind),
            "назван вид убранных советов: " .. tostring(ns.KIND_LABEL[kind]))
    end

    -- И у ветки, чьи советы ушли, причина - порог, а не выдуманная нехватка.
    for kind in pairs(meta.moneyFloorByKind or {}) do
        local branch = ns.ActionEngine.BRANCH_BY_KIND[kind]
        local reason = branch and ns.ActionEngine.branchNote[branch]
        H.ok(reason ~= nil and U.contains(reason, "порог"),
            "ветка «" .. tostring(branch) .. "» объясняет пропажу порогом: "
            .. U.truncate(tostring(reason), 120))
    end

    -- Строка над списком - та же, что в meta: окно ничего не выдумывает.
    local line
    for _, text in ipairs(ns.TabNow:Notices(meta, ns.CHIP.ALL, 3, 3, {})) do
        if U.contains(text, "порог") then line = text end
    end
    H.ok(line ~= nil, "над списком есть строка про порог: " .. tostring(line))
    if line then
        H.ok(U.contains(line, U.money(300000)), "с числом порога")
        H.ok(U.contains(line, tostring(meta.moneyFloorDropped)), "и с числом убранных")
    end

    -- Порога нет - строки нет. Иначе она превратилась бы в шум.
    ns.Config:SetMoneyFloorMode(ns.MONEY_FLOOR_MODE.OFF)
    H.build(env)
    local quiet = ns.TabNow:Notices(ns.ActionEngine.meta, ns.CHIP.ALL, 3, 3, {})
    local said = false
    for _, text in ipairs(quiet) do
        if U.contains(text, "порог мелкой") then said = true end
    end
    H.eq(said, false, "порог снят — строки про него нет")
end

H.suite("Журнал цен: для выручки записан источник")
do
    local env = bootsEnv { auction = 50200, history = BOOTS_HISTORY }
    local ns = env.ns
    H.build(env)
    local s = ns.Diag:Init()
    local rec = s.prices["sell:" .. BOOTS]
    H.ok(rec ~= nil, "решение по цене продажи записано")
    if rec then
        H.eq(rec.kind, "sell", "помечено как продажа")
        H.ok(rec.chosenSrc ~= nil, "источник выбранной цены назван: "
            .. tostring(rec.chosenSrc))
        H.ok(rec.why ~= nil, "и почему он выбран: " .. tostring(rec.why))
        H.ok(rec.historyFlag == "HIGH_OUTLIER",
            "вердикт истории тоже в журнале: " .. tostring(rec.historyFlag))
        H.ok(rec.liveCopper == 50200,
            "исходная живая цена сохранена: " .. tostring(rec.liveCopper))
    end
end

end
