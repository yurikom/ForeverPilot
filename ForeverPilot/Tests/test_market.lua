-- ForeverPilot / Tests/test_market.lua
--
-- РАСПЫЛЕНИЕ, ПЕРЕКУПКА И ИСТОРИЯ ЦЕН: ТРИ ВЕЩИ, КОТОРЫЕ ЛЕГКО СОВРАТЬ.
--
--   РАСПЫЛЕНИЕ. Результат рандомный: у зелёной вещи 75/20/5 на
--   пыль/эссенцию/осколок. Значит число - это ожидание, и на одном распыле оно
--   не сбудется почти никогда. Плюс три отдельные причины не верить: вероятности
--   из Classic, а не из Forever; Arcane Salvager даёт неизвестный бонус;
--   GetDisenchantPriceByItemID на этом клиенте всегда nil.
--
--   ПЕРЕКУПКА. Самый опасный совет в аддоне, и задание называет ловушку прямо:
--   «НЕ рекомендовать предмет только потому, что он дешевле соседнего лота».
--
--   ИСТОРИЯ ЦЕН. На два-три дня наблюдений нельзя опираться как на неделю, и
--   это должно быть сказано.
local H = ...

return function()

local function cardOf(cards, kind)
    for _, c in ipairs(cards) do
        if c.kind == kind then return c end
    end
    return nil
end

-- =====================================================================
-- 2.3 Распыление
-- =====================================================================

-- Зелёная вещь 25 уровня предмета: по таблице это Strange Dust 75% x4-6,
-- Lesser Astral Essence 15% x1-2, Small Glimmering Shard 10% x1.
local function deEnv(opts)
    opts = opts or {}
    local env = H.load()
    local ns = env.ns
    env.money = 58052
    env.auctionator = true

    H.item(env, 6001, { name = "Зелёный плащик", equipLoc = "INVTYPE_CLOAK",
        reqLevel = 20, classID = 4, subclassID = 1, quality = 2,
        itemLevel = 25, sellPrice = 500 })
    -- Продукты распыла с ценами.
    H.item(env, 10940, { name = "Странная пыль", sellPrice = 100 })
    H.item(env, 10998, { name = "Малая астральная эссенция", sellPrice = 300 })
    H.item(env, 10978, { name = "Мерцающий осколок", sellPrice = 2000 })
    env.prices[10940] = opts.dust or 2000
    env.prices[10998] = 4000
    env.prices[10978] = 30000
    env.prices[6001] = opts.itemPrice or 3000
    env.vendorPrices[6001] = opts.vendorAsk or 3000

    -- Зачарователь: без него совет бессмысленен.
    H.profession(env, "Наложение чар", 225, 225, {
        H.recipe { id = 6101, name = "Чары для плаща: малое сопротивление",
                   category = "Плащ", diff = "trivial",
                   reagents = { { itemID = 10940, qty = 1 } } },
    })
    -- И портняжка, которая этот плащ умеет сделать. Это ровно ситуация
    -- настоящего персонажа - портной И зачарователь - и именно она делает
    -- совет осмысленным: вещь, которую он умеет получить, в распыл может
    -- стоить дороже, чем в продажу.
    H.profession(env, "Портняжное дело", 225, 225, {
        H.recipe { id = 6102, name = "Зелёный плащик", output = 6001,
                   category = "Плащи", diff = "trivial",
                   reagents = { { itemID = 10940, qty = 1 } } },
    })
    H.itemsChanged(env)
    return env
end

H.suite("Распыление: ожидание считается из вероятностей и цен")
do
    local env = deEnv()
    local ns = env.ns
    H.ok(ns.Disenchant ~= nil, "модуль распыления есть")
    H.rescan(env)
    ns.PriceProvider:BeginPass()

    local exp = ns.Disenchant:Expectation(6001)
    H.ok(exp ~= nil, "ожидание посчитано")
    if exp then
        -- 0.75*5*2000*0.95 + 0.15*1.5*4000*0.95 + 0.10*1*30000*0.95
        -- = 7125 + 855 + 2850 = 10830
        H.near(exp.expected, 10830, 5, "ожидание: " .. ns.Util.money(exp.expected))
        H.eq(#exp.products, 3, "три возможных результата")
        H.eq(exp.unpriced, 0, "все с ценами")
        H.ok(exp.conf == ns.CONF.ESTIMATE or exp.conf == ns.CONF.UNKNOWN,
            "достоверность не выше оценки: " .. tostring(exp.conf))
    end
end

H.suite("Распыление: три причины не верить названы все три")
do
    local env = deEnv()
    local ns = env.ns
    H.rescan(env)
    ns.PriceProvider:BeginPass()
    local exp = ns.Disenchant:Expectation(6001)
    H.ok(exp ~= nil, "ожидание есть")
    if exp then
        local text = ns.Disenchant:CaveatText(exp)
        H.ok(ns.Util.contains(text, "ОЖИДАНИЕ") or ns.Util.contains(text, "ожидание"),
            "сказано, что это ожидание: " .. ns.Util.truncate(text, 120))
        H.ok(ns.Util.contains(text, "classic") or ns.Util.contains(text, "Classic"),
            "сказано, что вероятности из Classic")
        H.ok(ns.Util.contains(text, "Salvager"),
            "и про Arcane Salvager с неизвестным бонусом")
    end
end

H.suite("Распыление: карточка говорит «ожидание» в заголовке")
do
    local env = deEnv()
    local ns = env.ns
    H.rescan(env)
    local cards = H.build(env)
    local c = cardOf(cards, ns.KIND.DISENCHANT)
    H.ok(c ~= nil, "карточка распыления есть")
    if c then
        H.ok(ns.Util.contains(c.benefit, "ожидание"),
            "и слово «ожидание» стоит В ЗАГОЛОВКЕ, а не в сноске: " .. c.benefit)
        H.eq(c.expectation, true, "карточка помечена как расчёт-ожидание")
        H.ok(ns.Util.contains(c.why, "75%") or ns.Util.contains(c.why, "%"),
            "в тексте названы вероятности: " .. ns.Util.truncate(c.why, 160))
        H.ok(ns.Util.contains(c.why, "Странная пыль"),
            "и что именно может выпасть, по-русски")
        H.ok(ns.Util.contains(c.need, "средний результат"),
            "и напоминание, что это средний, а не его результат: " .. c.need)
    end
end

H.suite("Распыление: нет данных по предмету — так и сказано")
do
    local env = deEnv()
    local ns = env.ns
    -- Серая вещь: распылять нельзя вообще.
    H.item(env, 6002, { name = "Серая тряпка", quality = 0, itemLevel = 5,
        equipLoc = "INVTYPE_CLOAK", classID = 4, sellPrice = 10 })
    H.itemsChanged(env)
    H.rescan(env)
    ns.PriceProvider:BeginPass()
    local exp, why = ns.Disenchant:Expectation(6002)
    H.eq(exp, nil, "ожидания нет")
    H.eq(why, "too-common", "и причина названа: серое не распыляется")

    -- Предмет без уровня предмета: данных не хватает, и это заказ.
    H.item(env, 6003, { name = "Загадка", quality = 2,
        equipLoc = "INVTYPE_CLOAK", classID = 4, sellPrice = 10 })
    H.itemsChanged(env)
    local e3, w3 = ns.Disenchant:Expectation(6003)
    H.eq(e3, nil, "ожидания нет")
    H.eq(w3, "no-itemlevel", "и причина — неизвестен уровень предмета")
end

H.suite("Распыление: неизвестная вероятность попадает в заказ данных")
do
    local env = deEnv()
    local ns = env.ns
    -- Зелёная вещь с уровнем предмета вне всех полос таблицы: вероятностей нет.
    H.item(env, 6004, { name = "Невозможная вещь", quality = 2, itemLevel = -5,
        equipLoc = "INVTYPE_CLOAK", classID = 4, sellPrice = 10 })
    H.itemsChanged(env)
    H.rescan(env)
    ns.PriceProvider:BeginPass()
    local exp, why = ns.Disenchant:Expectation(6004)
    if exp == nil and why == "no-probabilities" then
        local b = (ns.Diag:Init().wanted or {}).disenchantUnknown
        H.ok(b ~= nil and b.items["6004"] ~= nil,
            "предмет попал в заказ disenchantUnknown")
    else
        H.ok(true, "таблица покрыла и этот уровень предмета — заказ не нужен")
    end
end

H.suite("Распыление: без Наложения чар совета нет")
do
    local env = H.load()
    local ns = env.ns
    env.money = 58052
    env.auctionator = true
    H.item(env, 6001, { name = "Зелёный плащик", equipLoc = "INVTYPE_CLOAK",
        quality = 2, itemLevel = 25, classID = 4, sellPrice = 500 })
    H.profession(env, "Портняжное дело", 225, 225, {
        H.recipe { id = 1, name = "Что-то", output = 6001, category = "Плащи",
                   reagents = {} },
    })
    H.itemsChanged(env)
    H.rescan(env)
    local opps = ns.Disenchant:Opportunities(ns.CharacterScanner:Get())
    H.eq(#opps, 0, "возможностей нет")
    H.ok(ns.Util.contains(tostring(ns.Disenchant.lastReason), "Наложение чар"),
        "и причина названа: " .. tostring(ns.Disenchant.lastReason))
end

H.suite("Распыление: гадание на гадание не множится")
do
    -- Цена покупки, которой никто не подтверждал (оценка по цене продажи),
    -- не годится: умножать её на ожидание - это гадание в квадрате.
    local env = deEnv()
    local ns = env.ns
    env.vendorPrices[6001] = nil
    env.prices[6001] = nil
    H.itemsChanged(env)
    H.rescan(env)
    ns.PriceProvider:BeginPass()
    local opp, why = ns.Disenchant:Evaluate(6001)
    H.eq(opp, nil, "совета нет")
    H.ok(why == "unproven-cost" or why == "no-buy-price",
        "потому что цену покупки никто не подтверждал: " .. tostring(why))
end

-- =====================================================================
-- 2.4 Перекупка
-- =====================================================================

local function resaleEnv(opts)
    opts = opts or {}
    local env = H.load()
    local ns = env.ns
    env.money = 58052
    env.auctionator = true
    H.item(env, 2589, { name = "Льняная ткань", sellPrice = 50 })
    env.prices[2589] = opts.live or 8000
    local cfg = ns.Config:Get()
    cfg.priceHistory[2589] = opts.history or {
        [20770] = 20000, [20771] = 21000, [20772] = 19000,
        [20773] = 20500, [20774] = 20000,
    }
    cfg.priceHistoryMeta.days = 5
    cfg.priceHistoryMeta.firstDay = 20770
    cfg.priceHistoryMeta.lastDay = 20774
    return env
end

H.suite("Перекупка: лот вдвое ниже наблюдённого — возможность")
do
    local env = resaleEnv()
    local ns = env.ns
    H.ok(ns.Resale ~= nil, "модуль перекупки есть")
    H.rescan(env)
    ns.PriceProvider:BeginPass()
    local opp = ns.Resale:Evaluate(2589)
    H.ok(opp ~= nil, "возможность найдена")
    if opp then
        H.eq(opp.live, 8000, "цена лота")
        H.eq(opp.reference, 20000, "и медиана наблюдённого — не соседний лот")
        H.near(opp.discount, 0.6, 0.01, "скидка 60%")
        H.ok(opp.profit > 0, "прибыль положительная: " .. ns.Util.money(opp.profit))
        H.ok(opp.deposit ~= nil, "залог учтён: " .. tostring(opp.deposit))
        H.ok(opp.liquidity and opp.liquidity.liquid, "и ликвидность проверена")
    end
end

H.suite("Перекупка: БЕЗ СВОЕЙ ИСТОРИИ СОВЕТА НЕТ")
do
    -- Главная защита от «дешевле соседнего лота»: без истории «ниже рынка»
    -- просто не определено.
    local env = resaleEnv()
    local ns = env.ns
    ns.Config:Get().priceHistory[2589] = nil
    H.rescan(env)
    ns.PriceProvider:BeginPass()
    local opp, why = ns.Resale:Evaluate(2589)
    H.eq(opp, nil, "совета нет")
    H.eq(why, "no-history", "и причина — своей истории по предмету нет")
end

H.suite("Перекупка: один день истории — тоже не история")
do
    local env = resaleEnv { history = { [20774] = 20000 } }
    local ns = env.ns
    H.rescan(env)
    ns.PriceProvider:BeginPass()
    local opp, why = ns.Resale:Evaluate(2589)
    H.eq(opp, nil, "совета нет")
    H.eq(why, "history-too-short", "одного наблюдения недостаточно")
end

H.suite("Перекупка: неустойчивая цена — не возможность")
do
    -- Предмет, который гуляет в пять раз, «дешевле рынка» бывает каждый день.
    local env = resaleEnv {
        live = 8000,
        history = { [20770] = 10000, [20771] = 50000, [20772] = 12000,
                    [20773] = 45000, [20774] = 20000 },
    }
    local ns = env.ns
    H.rescan(env)
    ns.PriceProvider:BeginPass()
    local opp, why = ns.Resale:Evaluate(2589)
    H.eq(opp, nil, "совета нет")
    H.eq(why, "too-volatile", "потому что разброс слишком велик")
end

H.suite("Перекупка: неликвид — не возможность")
do
    -- Предмет появлялся два дня из десяти: быстро перепродать не выйдет.
    local env = resaleEnv {
        live = 8000,
        history = { [20765] = 20000, [20774] = 20000 },
    }
    local ns = env.ns
    H.rescan(env)
    ns.PriceProvider:BeginPass()
    local opp, why = ns.Resale:Evaluate(2589)
    H.eq(opp, nil, "совета нет")
    H.eq(why, "illiquid", "потому что предмет на аукционе почти не появлялся")

    local liq = ns.Resale:Liquidity(2589)
    H.eq(liq.liquid, false, "ликвидность названа низкой")
    H.ok(ns.Util.contains(liq.text, "редко"),
        "и это сказано словами: " .. liq.text)
end

H.suite("Перекупка: небольшая скидка — не возможность")
do
    local env = resaleEnv { live = 18000 }   -- 10% ниже медианы
    local ns = env.ns
    H.rescan(env)
    ns.PriceProvider:BeginPass()
    local opp, why = ns.Resale:Evaluate(2589)
    H.eq(opp, nil, "совета нет")
    H.eq(why, "not-cheap-enough", "10% ниже рынка — это шум, а не сделка")
end

H.suite("Перекупка: карточка называет всё, на чём стоит расчёт")
do
    local env = resaleEnv()
    local ns = env.ns
    -- ПРОФИЛЬ ЗАДАН ЯВНО. Перекупка - это вложить деньги и подождать, и
    -- профили «Сила» и «Экономия» её намеренно не показывают (см.
    -- ns.PROFILE_EXCLUDE): в одном это не цель, в другом прямо противоречит.
    -- Проверяем в том профиле, которому этот совет и адресован.
    ns.Config:SetProfile("EARN")
    H.rescan(env)
    local cards = H.build(env)
    local c = cardOf(cards, ns.KIND.RESELL)
    H.ok(c ~= nil, "карточка перекупки есть")
    if c then
        H.ok(ns.Util.contains(c.why, "наблюдени") or ns.Util.contains(c.why, "обычно"),
            "сказано, с чем сравнивали: " .. ns.Util.truncate(c.why, 170))
        H.ok(ns.Util.contains(c.why, "разброс") or ns.Util.contains(c.why, "наблюдения дали"),
            "назван разброс")
        H.ok(ns.Util.contains(c.why, "сбор"), "назван сбор аукциона")
        H.ok(ns.Util.contains(c.why, "залог"), "назван залог")
        H.ok(ns.Util.contains(c.need, "залог не вернётся"),
            "и что залог не вернётся, если лот не продастся: " .. c.need)
        H.ok(c.risk ~= nil, "риск приложен")
        if c.risk then
            H.ok(c.risk.maxLoss ~= nil,
                "с максимальным убытком: " .. tostring(c.risk.maxLoss))
        end
    end
end

-- =====================================================================
-- 2.5 История цен
-- =====================================================================

H.suite("История цен: отклонение показывается карточкой")
do
    local env = H.load()
    local ns = env.ns
    -- Справка про цены адресована денежным профилям: «Сила» и «Прокачка» её
    -- не показывают, и это намеренно (ns.PROFILE_EXCLUDE).
    ns.Config:SetProfile("EARN")
    env.money = 58052
    env.auctionator = true
    H.item(env, 7777, { name = "Шёлковый пояс", equipLoc = "INVTYPE_WAIST",
        reqLevel = 20, classID = 4, subclassID = 1, sellPrice = 600 })
    H.item(env, 7778, { name = "Шёлк", sellPrice = 100 })
    env.vendorPrices[7778] = 300
    env.bags[7778] = 20
    -- Сейчас втрое дороже, чем всю неделю.
    env.prices[7777] = 60000
    local cfg = ns.Config:Get()
    cfg.priceHistory[7777] = {
        [20770] = 20000, [20771] = 19000, [20772] = 20000,
        [20773] = 21000, [20774] = 20000,
    }
    cfg.priceHistoryMeta.days = 5
    cfg.priceHistoryMeta.firstDay = 20770
    cfg.priceHistoryMeta.lastDay = 20774
    H.profession(env, "Портняжное дело", 225, 225, {
        H.recipe { id = 7701, output = 7777, name = "Шёлковый пояс",
                   diff = "trivial", category = "Пояса",
                   reagents = { { itemID = 7778, qty = 3 } } },
    })
    H.itemsChanged(env)
    H.rescan(env)
    local cards = H.build(env)
    local c = cardOf(cards, ns.KIND.PRICE_INFO)
    H.ok(c ~= nil, "карточка про цену есть")
    if c then
        H.ok(ns.Util.contains(c.title, "дорого"),
            "и она говорит, что сейчас дорого: " .. c.title)
        H.ok(ns.Util.contains(c.why, "выше") or ns.Util.contains(c.why, "больше"),
            "с объяснением: " .. ns.Util.truncate(c.why, 150))
        H.eq(c.informational, true, "карточка справочная, а не совет к действию")
        H.ok(c.priceVerdict ~= nil, "вердикт истории приложен")
    end
end

H.suite("История цен: короткая выборка называется короткой")
do
    local env = H.load()
    local ns = env.ns
    ns.Config:SetProfile("EARN")
    env.money = 58052
    env.auctionator = true
    H.item(env, 7779, { name = "Пояс", equipLoc = "INVTYPE_WAIST",
        reqLevel = 20, classID = 4, subclassID = 1, sellPrice = 600 })
    H.item(env, 7780, { name = "Ткань", sellPrice = 100 })
    env.vendorPrices[7780] = 300
    env.bags[7780] = 20
    env.prices[7779] = 60000
    -- Ровно та картина, что у игрока: два дня наблюдений.
    local cfg = ns.Config:Get()
    cfg.priceHistory[7779] = { [20773] = 20000, [20774] = 20000 }
    cfg.priceHistoryMeta.days = 2
    cfg.priceHistoryMeta.firstDay = 20773
    cfg.priceHistoryMeta.lastDay = 20774
    H.profession(env, "Портняжное дело", 225, 225, {
        H.recipe { id = 7702, output = 7779, name = "Пояс",
                   diff = "trivial", category = "Пояса",
                   reagents = { { itemID = 7780, qty = 3 } } },
    })
    H.itemsChanged(env)
    H.rescan(env)
    local cards = H.build(env)
    local c = cardOf(cards, ns.KIND.PRICE_INFO)
    H.ok(c ~= nil, "карточка есть")
    if c then
        H.ok(ns.Util.contains(c.why, "короткая"),
            "и выборка названа короткой: " .. ns.Util.truncate(c.why, 180))
        H.ok(ns.Util.contains(c.why, "2 дня") or ns.Util.contains(c.why, "дня"),
            "с числом дней")
        H.ok(ns.Util.contains(c.why, "присмотреться") or ns.Util.contains(c.why, "не вывод"),
            "и сказано, что это повод присмотреться, а не вывод")
        H.eq(c.conf, ns.CONF.ESTIMATE, "достоверность — оценка")
    end
end

H.suite("История цен: тренд считается и называется направлением")
do
    local env = H.load()
    local ns = env.ns
    local cfg = ns.Config:Get()
    cfg.priceHistory[8888] = {
        [20770] = 10000, [20771] = 12000, [20772] = 15000,
        [20773] = 18000, [20774] = 25000,
    }
    local t = ns.MarketHistory:Trend(8888)
    H.ok(t ~= nil, "тренд посчитан")
    if t then
        H.eq(t.direction, "up", "направление — вверх")
        H.near(t.changePct, 150, 1, "и на сколько: " .. ns.Util.round(t.changePct) .. "%")
        H.eq(t.days, 5, "по пяти дням")
    end
end

H.suite("История цен: обычная цена карточки не рождает")
do
    local env = H.load()
    local ns = env.ns
    ns.Config:SetProfile("EARN")
    env.money = 58052
    env.auctionator = true
    H.item(env, 7781, { name = "Пояс", equipLoc = "INVTYPE_WAIST",
        reqLevel = 20, classID = 4, subclassID = 1, sellPrice = 600 })
    H.item(env, 7782, { name = "Ткань", sellPrice = 100 })
    env.vendorPrices[7782] = 300
    env.bags[7782] = 20
    env.prices[7781] = 20000
    local cfg = ns.Config:Get()
    cfg.priceHistory[7781] = {
        [20770] = 19000, [20771] = 20000, [20772] = 21000,
        [20773] = 20000, [20774] = 20500,
    }
    cfg.priceHistoryMeta.days = 5
    H.profession(env, "Портняжное дело", 225, 225, {
        H.recipe { id = 7703, output = 7781, name = "Пояс",
                   diff = "trivial", category = "Пояса",
                   reagents = { { itemID = 7782, qty = 3 } } },
    })
    H.itemsChanged(env)
    H.rescan(env)
    local cards = H.build(env)
    H.eq(cardOf(cards, ns.KIND.PRICE_INFO), nil,
        "цена обычная — говорить нечего")
    H.ok(ns.Util.contains(tostring(ns.ActionEngine.branchNote.priceinfo), "обычные"),
        "и ветка это сказала: " .. tostring(ns.ActionEngine.branchNote.priceinfo))
end

end
