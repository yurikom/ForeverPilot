-- ForeverPilot / Tests/test_risk.lua
--
-- РИСК РЯДОМ С ВЫГОДОЙ, И ПРАВДОПОДОБИЕ ПЕРЕД ОБОИМИ.
--
-- Этот набор держит два контракта, и оба появились из настоящих убытков:
--
--   1. У игрока около пяти золотых. Совет, который требует больше, обязан
--      сказать это словами на самой карточке - вместе с тем, сколько можно
--      потерять, если покупателя не найдётся. Выгода без риска - это половина
--      правды, и именно эту половину игрок уже один раз прочитал.
--
--   2. Карточка «На продажу: Тренировочный жезл новобранца» показывала выручку
--      2з 66с при цене торговца 5м - расхождение в 5320 раз. Самопроверка это
--      ловила и писала в файл, а карточка всё равно уходила игроку, наверху
--      денежной части и без единого слова о том, что числа друг с другом не
--      согласуются. Числа ниже - настоящие, из ForeverPilot.lua игрока
--      (itemID 247789, revenue 26600, vendor 5).
local H = ...

return function()

local ns0 = nil

-- =====================================================================
-- Модуль риска сам по себе
-- =====================================================================

H.suite("Риск: модуль на месте и считает четыре величины")
do
    local env = H.load()
    local ns = env.ns
    H.ok(ns.Risk ~= nil, "модуль риска есть")
    if not ns.Risk then return end

    local r = ns.Risk:Assess({
        kind = ns.KIND.CRAFT_PROFIT,
        cost = 10000,          -- вложить 1з
        revenue = 30000,       -- получить 3з
        benefitValue = 20000,
        revOrigin = { src = "auction", market = true, observed = true },
        itemID = 700,
    }, { money = 58000 })

    H.ok(r ~= nil, "оценка построена")
    if r then
        H.eq(r.capital, 10000, "требуемый капитал = то, что надо выложить")
        H.ok(r.maxLoss ~= nil, "максимальный убыток назван: "
            .. tostring(r.maxLoss))
        H.ok(r.buyerRisk ~= nil, "риск отсутствия покупателей назван: "
            .. tostring(r.buyerRisk))
        H.ok(r.priceRisk ~= nil, "риск изменения цены назван: "
            .. tostring(r.priceRisk))
        H.ok(type(r.text) == "string" and r.text ~= "",
            "и всё это одной фразой: " .. tostring(r.text))
    end
end

H.suite("Риск: рыночная цена рискованнее гарантированной")
do
    local env = H.load()
    local ns = env.ns
    local snap = { money = 100000 }

    local market = ns.Risk:Assess({
        kind = ns.KIND.CRAFT_PROFIT, cost = 1000, revenue = 5000,
        revOrigin = { src = "auction", market = true, observed = true },
    }, snap)
    local vendor = ns.Risk:Assess({
        kind = ns.KIND.CRAFT_PROFIT, cost = 1000, revenue = 5000,
        revOrigin = { src = "vendor", market = false, observed = true },
    }, snap)
    local nobody = ns.Risk:Assess({
        kind = ns.KIND.CRAFT_PROFIT, cost = 1000, revenue = 5000,
        revOrigin = { src = "none", market = false, observed = false },
    }, snap)

    H.eq(vendor.buyerRisk, ns.Risk.LEVEL.NONE,
        "торговец заберёт всегда — покупателя искать не надо")
    H.ok(ns.Risk:Worse(market.buyerRisk, vendor.buyerRisk) == market.buyerRisk,
        "аукцион рискованнее торговца: " .. tostring(market.buyerRisk)
        .. " > " .. tostring(vendor.buyerRisk))
    H.eq(nobody.buyerRisk, ns.Risk.LEVEL.HIGH,
        "цену никто не подтверждал — риск высокий")
end

H.suite("Риск: пять золотых в кошельке — совет дороже обязан это сказать")
do
    local env = H.load()
    local ns = env.ns
    -- Настоящий кошелёк игрока на 17 ноября.
    local snap = { money = 58052 }

    local cheap = ns.Risk:Assess({ kind = ns.KIND.BUY, cost = 2000 }, snap)
    H.eq(cheap.overWallet, false, "2з при 5з 80с — по карману")

    local dear = ns.Risk:Assess({ kind = ns.KIND.BUY, cost = 246300 }, snap)
    H.eq(dear.overWallet, true, "24з 63с при 5з 80с — не по карману")
    H.ok(dear.capitalShare and dear.capitalShare > 4,
        "и во сколько раз, тоже посчитано: " .. tostring(dear.capitalShare))
    H.ok(ns.Util.contains(dear.text, "5з 80с"),
        "в тексте названо, сколько у игрока есть: " .. tostring(dear.text))
    H.ok(ns.Util.contains(dear.text, "хват") or ns.Util.contains(dear.text, "больше"),
        "и что этого не хватает")
end

H.suite("Риск: максимальный убыток не выдумывается из воздуха")
do
    local env = H.load()
    local ns = env.ns
    H.item(env, 701, { name = "Товар", sellPrice = 400 })
    H.itemsChanged(env)

    -- Вложить 1з, рынок обещает 3з, торговец даст 4с за штуку. Если рынок
    -- не заберёт, торговец заберёт - значит терять можно только разницу.
    local r = ns.Risk:Assess({
        kind = ns.KIND.CRAFT_PROFIT, cost = 10000, revenue = 30000,
        itemID = 701, outputQty = 1,
        revOrigin = { src = "auction", market = true, observed = true },
    }, { money = 58052 })
    H.eq(r.vendorFloor, 400, "пол по цене торговца найден")
    H.eq(r.maxLoss, 9600, "максимальный убыток = вложено минус пол (1з - 4с)")

    -- Та же покупка, но продать потом некому вообще: теряется всё.
    local r2 = ns.Risk:Assess({
        kind = ns.KIND.CRAFT_PROFIT, cost = 10000, revenue = 30000,
        itemID = 999999,
        revOrigin = { src = "auction", market = true, observed = true },
    }, { money = 58052 })
    H.eq(r2.vendorFloor, nil, "пола нет — цены торговца по предмету не знаем")
    H.eq(r2.maxLoss, 10000, "и тогда максимальный убыток — всё вложенное")
end

-- =====================================================================
-- Правдоподобие: жезл за 5 медных и выручка 2з 66с
-- =====================================================================

-- Настоящий случай целиком: рецепт делает предмет 247789, аукцион просит за
-- него 2з 80с, а сам предмет по данным клиента стоит у торговца 5 медных.
local WAND = 247789
local function wandEnv(opts)
    opts = opts or {}
    local env = H.load()
    local ns = env.ns

    H.item(env, WAND, { name = "Тренировочный жезл новобранца",
        equipLoc = "INVTYPE_RANGED", reqLevel = 5,
        classID = 2, subclassID = 19, sellPrice = opts.vendorSell or 5 })
    H.item(env, 4470, { name = "Простая древесина", sellPrice = 1 })
    env.vendorPrices[4470] = 40
    env.money = 58052
    env.prices[WAND] = opts.auction or 28000

    local cfg = ns.Config:Get()
    for day, copper in pairs(opts.history or {}) do
        cfg.priceHistory[WAND] = cfg.priceHistory[WAND] or {}
        cfg.priceHistory[WAND][day] = copper
    end

    H.profession(env, "Наложение чар", 225, 225, {
        H.recipe { id = 1245321, output = WAND, outputQty = 1,
                   reagents = { { itemID = 4470, qty = 1 } },
                   name = "Тренировочный жезл новобранца",
                   diff = "trivial", category = "Жезлы" },
    })
    return env
end

local function cardByKind(cards, kind)
    for _, c in ipairs(cards) do
        if c.kind == kind then return c end
    end
    return nil
end

H.suite("Жезл за 5 медных: расхождение в 5320 раз распознаётся")
do
    local env = wandEnv {}
    local ns = env.ns
    ns0 = ns

    local p = ns.Risk:Plausibility({
        kind = ns.KIND.CRAFT_PROFIT, itemID = WAND, revenue = 26600,
        title = "На продажу: Тренировочный жезл новобранца",
    })
    H.ok(p ~= nil, "неправдоподобие найдено")
    if p then
        H.eq(p.code, "revenue-far-above-vendor", "и названо своим кодом")
        H.eq(ns.Util.round(p.ratio), 5320, "отношение посчитано: 5320")
        H.ok(ns.Util.contains(p.text, "торговц"),
            "в тексте названа цена торговца: " .. tostring(p.text))
    end

    -- Порог упоминания — один на весь аддон: самопроверка берёт его оттуда же.
    H.eq(ns.SanityChecks.VENDOR_RATIO_LIMIT, ns.Risk.VENDOR_RATIO_NOTE,
        "порог упоминания у самопроверки и у модуля риска один и тот же")
    H.ok(ns.Risk.VENDOR_RATIO_LIMIT > ns.Risk.VENDOR_RATIO_NOTE,
        "а порог недоверия выше порога упоминания: "
        .. ns.Risk.VENDOR_RATIO_LIMIT .. " > " .. ns.Risk.VENDOR_RATIO_NOTE)
end

H.suite("Разрыв в сотни раз: упомянуть — не то же самое, что не поверить")
do
    -- Настоящий случай из набора про потолок навыка: тканевый пояс идёт на
    -- аукционе за 9з при цене торговца 5с. Это 171 раз — много, но это рынок.
    local env = H.load()
    local ns = env.ns
    env.money = 5000000
    H.item(env, 2589, { name = "Лён", sellPrice = 10, stackCount = 20 })
    H.item(env, 2996, { name = "Тканевый пояс", sellPrice = 500,
        equipLoc = "INVTYPE_WAIST", quality = 1, classID = 4 })
    env.prices[2589] = 400
    env.prices[2996] = 90000
    env.bags[2589] = 60
    H.profession(env, "Портняжное дело", 225, 225, {
        H.recipe { id = 101, name = "Тканевый пояс", output = 2996,
                   diff = "optimal", reagents = { { itemID = 2589, qty = 3 } } },
    })
    local cards = H.build(env)
    local c = cardByKind(cards, ns.KIND.CRAFT_PROFIT)
    H.ok(c ~= nil, "карточка на продажу есть")
    if c then
        H.eq(c.suspect, nil, "171 раз — не повод не верить")
        H.ok(c.vendorRatioNote ~= nil, "но разрыв упомянут")
        H.ok(ns.Util.contains(c.why, "наценка большая"),
            "и упомянут в тексте карточки: " .. ns.Util.truncate(c.why, 160))
        H.ok(c.conf == ns.CONF.ESTIMATE or c.conf == ns.CONF.UNKNOWN,
            "достоверность снята на ступень: " .. tostring(c.conf))
    end
end

H.suite("Сомнительный совет: карточка покупки под него предупреждает")
do
    local env = wandEnv {}
    local ns = env.ns
    local cards = H.build(env)
    local buy
    for _, c in ipairs(cards) do
        if c.kind == ns.KIND.BUY and c.itemID == 4470 then buy = c end
    end
    H.ok(buy ~= nil, "карточка покупки материала построена (строка не выкинута молча)")
    if buy then
        H.eq(buy.suspectOnly, true, "и помечена как нужная только сомнительному совету")
        H.ok(ns.Util.contains(buy.need, "не верю"),
            "предупреждение написано словами: " .. ns.Util.truncate(buy.need, 180))
    end
end

H.suite("Жезл за 5 медных: карточка не уходит игроку без предупреждения")
do
    local env = wandEnv {}
    local ns = env.ns
    local cards = H.build(env)
    local c = cardByKind(cards, ns.KIND.CRAFT_PROFIT)

    H.ok(c ~= nil, "карточка построена (предмет и правда продаётся на аукционе)")
    if c then
        H.ok(c.suspect ~= nil, "карточка помечена как сомнительная")
        H.eq(c.conf, ns.CONF.UNKNOWN,
            "достоверность опущена до «неизвестно»: " .. tostring(c.conf))
        H.ok(ns.Util.contains(c.benefit, "сомнительно")
             or ns.Util.contains(c.benefit, "не верю"),
            "предупреждение стоит в самом заголовке выгоды: " .. tostring(c.benefit))
        H.ok(ns.Util.contains(c.why, "5320") or ns.Util.contains(c.why, "раз"),
            "и в тексте сказано, во сколько раз расхождение: "
            .. ns.Util.truncate(c.why, 140))
        H.ok(ns.Util.contains(c.why, "торговц"),
            "и с чем именно оно сравнивается")
    end
end

H.suite("Жезл за 5 медных: сомнительная карточка не стоит выше исполнимых")
do
    local env = wandEnv {}
    local ns = env.ns
    -- Что-то заведомо нормальное в том же списке: хлам в сумках.
    H.item(env, 702, { name = "Серый мусор", quality = 0, sellPrice = 500 })
    env.bags[702] = 2
    H.itemsChanged(env)
    local cards = H.build(env)

    local suspectAt, junkAt
    for i, c in ipairs(cards) do
        if c.suspect and not suspectAt then suspectAt = i end
        if c.kind == ns.KIND.SELL_JUNK and not junkAt then junkAt = i end
    end
    H.ok(suspectAt ~= nil, "сомнительная карточка в списке есть")
    H.ok(junkAt ~= nil, "и нормальная тоже")
    if suspectAt and junkAt then
        H.ok(junkAt < suspectAt, string.format(
            "нормальная (№%d) выше сомнительной (№%d)", junkAt, suspectAt))
    end
end

H.suite("Жезл за 5 медных: самопроверка ловит карточку без предупреждения")
do
    local env = wandEnv {}
    local ns = env.ns
    H.build(env)

    local checked = ns.SanityChecks:HasCheck("suspect-card-unmarked")
    H.ok(checked, "проверка «сомнительная карточка без пометки» существует")

    -- Пока движок помечает карточку сам, подозрение молчит.
    local fired = false
    for _, e in ipairs(ns.Diag:Init().suspicious) do
        if e.code == "suspect-card-unmarked" then fired = true end
    end
    H.eq(fired, false, "и она молчит, потому что пометка на месте")

    -- А если пометку снять - ругается. Это и есть смысл проверки.
    local card = cardByKind(ns.ActionEngine.cards, ns.KIND.CRAFT_PROFIT)
    if card then
        card.benefit = "+2з 64с"
        card.why = "Материалы 1с 10м, выручка 2з 66с за штуку."
        card.conf = ns.CONF.CACHED
        ns.Diag:ClearSuspicions()
        ns.SanityChecks:Run({ cards = ns.ActionEngine.cards, snap = env.ns.CharacterScanner:Get(),
                              counts = {}, generated = #ns.ActionEngine.cards, hidden = 0 })
        local fired2 = false
        for _, e in ipairs(ns.Diag:Init().suspicious) do
            if e.code == "suspect-card-unmarked" then fired2 = true end
        end
        H.ok(fired2, "без пометки проверка срабатывает")
    end
end

H.suite("Правдоподобие: обычная наценка подозрений не вызывает")
do
    local env = wandEnv { vendorSell = 400 }
    local ns = env.ns
    -- 28000 * 0.95 / 400 = 66 раз. Много, но для крафта бывает.
    local p = ns.Risk:Plausibility({
        kind = ns.KIND.CRAFT_PROFIT, itemID = WAND, revenue = 26600,
    })
    H.eq(p, nil, "66-кратная наценка — не повод не верить")

    local cards = H.build(env)
    local c = cardByKind(cards, ns.KIND.CRAFT_PROFIT)
    H.ok(c ~= nil, "карточка есть")
    if c then
        H.eq(c.suspect, nil, "и она не помечена сомнительной")
    end
end

H.suite("Риск: на карточке покупки видно, что денег не хватает")
do
    -- Улучшение экипировки из дорогого материала, которого в сумках нет:
    -- ветка покупок обязана проговорить и капитал, и то, что его не хватает.
    local env = H.load()
    local ns = env.ns
    env.money = 58052
    H.item(env, 810, { name = "Жилет из ткани Грез", equipLoc = "INVTYPE_CHEST",
        reqLevel = 20, classID = 4, subclassID = 1, sellPrice = 400 })
    env.stats[810] = { ITEM_MOD_INTELLECT_SHORT = 20 }
    H.item(env, 811, { name = "Рулон магической ткани", sellPrice = 2000 })
    env.vendorPrices[811] = 40000
    env.prices[811] = 40000
    H.profession(env, "Портняжное дело", 225, 225, {
        H.recipe { id = 8101, output = 810, outputQty = 1,
                   reagents = { { itemID = 811, qty = 6 } },
                   name = "Жилет из ткани Грез", diff = "trivial",
                   category = "Одеяния и жилеты" },
    })
    H.itemsChanged(env)
    local cards = H.build(env)
    local buy = cardByKind(cards, ns.KIND.BUY)
    H.ok(buy ~= nil, "карточка покупки есть")
    if buy then
        H.ok(buy.risk ~= nil, "риск к ней приложен")
        if buy.risk then
            H.eq(buy.risk.overWallet, true, "и он говорит, что не по карману")
            H.ok(buy.risk.capital and buy.risk.capital > 0,
                "капитал назван: " .. ns.Util.money(buy.risk.capital))
            H.eq(buy.risk.buyerRisk, ns.Risk.LEVEL.NONE,
                "покупку никому перепродавать не надо — риска покупателя нет")
        end
    end
end

H.suite("Риск: «не по карману» говорится на ЛЮБОЙ карточке с ценой")
do
    -- У игрока около пяти золотых, и это прямое требование: совет дороже обязан
    -- сказать об этом явно. Раньше текст дописывала только ветка покупок, и на
    -- живых данных самопроверка ловила четыре молчащих карточки за пересчёт -
    -- крафт, развилку путей и две покупки. Теперь это делает модуль риска, один
    -- раз для всех, и новая ветка не может об этом забыть.
    local env = H.load()
    local ns = env.ns
    env.money = 58052          -- 5з 80с, как у игрока
    env.auctionator = true
    H.item(env, 820, { name = "Дорогой жилет", equipLoc = "INVTYPE_CHEST",
        reqLevel = 20, classID = 4, subclassID = 1, sellPrice = 400 })
    env.stats[820] = { ITEM_MOD_INTELLECT_SHORT = 20 }
    H.item(env, 821, { name = "Дорогая ткань", sellPrice = 2000 })
    env.vendorPrices[821] = 30000
    env.prices[821] = 30000
    H.profession(env, "Портняжное дело", 225, 225, {
        H.recipe { id = 8201, output = 820, outputQty = 1,
                   reagents = { { itemID = 821, qty = 5 } },
                   name = "Дорогой жилет", diff = "trivial",
                   category = "Одеяния и жилеты" },
    })
    H.itemsChanged(env)
    local cards = H.build(env)

    local checked = 0
    for _, c in ipairs(cards) do
        if c.cost and c.cost > env.money then
            checked = checked + 1
            local says = ns.Util.contains(c.need or "", "хватает")
                or tostring(c.need or ""):find("в %d+ раз[^ ]* больше, чем у вас есть") ~= nil
            H.ok(says, "«" .. ns.Util.truncate(tostring(c.title), 38)
                .. "» говорит, что денег не хватает")
        end
    end
    H.ok(checked > 0, "карточки дороже кошелька в списке есть: " .. checked)

    -- И самопроверка на этом молчит: это и есть доказательство.
    local fired = false
    for _, e in ipairs(ns.Diag:Init().suspicious) do
        if e.code == "unaffordable-unmarked" then fired = true end
    end
    H.eq(fired, false, "самопроверка «не по карману без пометки» молчит")
end

H.suite("Сомнительный совет: строка списка покупок помечена, а не выкинута")
do
    -- Молча убрать материал из списка - это ровно то «тихое действие», от
    -- которого игрок уже пострадал: сумма покупок поехала бы из-за суждения,
    -- которого он не видит. Строка остаётся, но с отметкой, от кого она.
    local env = wandEnv {}
    local ns = env.ns
    local cards = H.build(env)
    local c = cardByKind(cards, ns.KIND.CRAFT_PROFIT)
    H.ok(c ~= nil and c.suspect ~= nil, "сомнительная карточка на месте")

    local line
    for _, l in ipairs(ns.ShoppingList:Lines()) do
        if l.itemID == 4470 then line = l end
    end
    H.ok(line ~= nil, "материал в списке покупок остался")
    if line then
        H.eq(line.suspectOnly, true, "и строка помечена: нужна только сомнительному")
        H.ok(line.suspectWhy ~= nil, "с причиной: "
            .. ns.Util.truncate(tostring(line.suspectWhy), 90))
    end
end

-- =====================================================================
-- СОМНЕНИЕ ДОХОДИТ ДО КАРТОЧКИ
-- =====================================================================
--
-- Живая находка, на которой всё это и выросло. У игрока карточка «На продажу:
-- Небесно-голубая краска» стояла ВТОРЫМ советом сверху с заголовком «оценка
-- ~1з 22с». В том же пересчёте самопроверка писала в файл: «выручка 1з 24с
-- против цены торговца 75м — это в 166 раз больше», и писала на КАЖДОМ
-- пересчёте (счётчик 937). Текст про разрыв на карточке формально был - в
-- хвосте строки «почему», которая на экране обрезается шириной окна, - то есть
-- не был нигде.
--
-- Три требования, и ни одного из них по отдельности не хватает: видно в
-- заголовке, сказано ПЕРВОЙ фразой, и место в списке - не наверху.

H.suite("Сомнение: разрыв в сотни раз видно в заголовке и первой фразой")
do
    -- Тот же тканевый пояс: 171 раз. Не повод не верить, но повод сказать.
    local env = H.load()
    local ns = env.ns
    env.money = 5000000
    H.item(env, 2589, { name = "Лён", sellPrice = 10, stackCount = 20 })
    H.item(env, 2996, { name = "Тканевый пояс", sellPrice = 500,
        equipLoc = "INVTYPE_WAIST", quality = 1, classID = 4 })
    env.prices[2589] = 400
    env.prices[2996] = 90000
    env.bags[2589] = 60
    H.profession(env, "Портняжное дело", 225, 225, {
        H.recipe { id = 101, name = "Тканевый пояс", output = 2996,
                   diff = "optimal", reagents = { { itemID = 2589, qty = 3 } } },
    })
    local cards = H.build(env)
    local c = cardByKind(cards, ns.KIND.CRAFT_PROFIT)
    H.ok(c ~= nil, "карточка на продажу есть")
    if c then
        H.eq(c.doubtLevel, ns.Risk.DOUBT_SOFT,
            "сомнение названо своей ступенью: " .. tostring(c.doubtLevel))
        H.ok(ns.Util.contains(c.benefit or "", ns.Risk.DOUBT_MARK.doubt),
            "заголовок выгоды предупреждает: " .. tostring(c.benefit))
        local first = tostring(c.why or ""):match("^[^%.]+") or ""
        H.ok(ns.Util.contains(first, "сомнева"),
            "и оговорка стоит ПЕРВОЙ фразой, а не в хвосте строки: " .. first)
        H.ok(first:find("171", 1, true) ~= nil,
            "в ней названо, насколько: " .. first)
        H.eq(ns.ActionEngine.TierOf(c), 1,
            "место в списке — ниже всего исполнимого")
        -- И это действительно меняет порядок: выше неё стоит хотя бы один
        -- совет, которому аддон верит.
        local firmAbove, pos = 0, nil
        for i, other in ipairs(cards) do
            if other == c then pos = i end
            if pos == nil and ns.ActionEngine.TierOf(other) == 2 then
                firmAbove = firmAbove + 1
            end
        end
        H.ok(pos ~= nil and firmAbove > 0,
            "и сомнительный совет не стоит наверху: он " .. tostring(pos)
            .. "-й, выше него " .. firmAbove .. " твёрдых")
    end
end

H.suite("Сомнение: находка самопроверки печатается на карточке её же словами")
do
    local env = H.load()
    local ns = env.ns
    local card = { key = "k", kind = ns.KIND.CRAFT_PROFIT,
                   title = "На продажу: Небесно-голубая краска",
                   benefit = "оценка ~1з 22с", why = "Материалы 6с 6м.",
                   need = "y", conf = ns.CONF.ESTIMATE, score = 0.5 }
    local text = "«На продажу: Небесно-голубая краска»: выручка 1з 24с против"
        .. " цены торговца 75м — это в 166 раз больше"
    ns.Diag:BindCards({ card })
    ns.Diag:Suspect("revenue-far-above-vendor", text, { key = "k" })
    ns.Diag:UnbindCards()
    ns.Risk:RenderDoubts(card)

    H.eq(card.doubtLevel, ns.Risk.DOUBT_SOFT, "ступень — сомнение")
    H.ok(ns.Util.contains(card.why, "в 166 раз больше"),
        "на карточке сказано, что именно смущает и насколько: "
        .. ns.Util.truncate(card.why, 180))
    local first = tostring(card.why):match("^[^%.]+") or ""
    H.ok(ns.Util.contains(first, "сомнева"), "первой фразой: " .. first)
    H.eq(card.why:find("«На продажу: Небесно-голубая краска»", 1, true), nil,
        "а заголовок карточки в её же тексте не повторяется")
    H.ok(ns.Util.contains(card.benefit, ns.Risk.DOUBT_MARK.doubt),
        "заголовок выгоды: " .. tostring(card.benefit))
    H.eq(ns.ActionEngine.TierOf(card), 1, "и место — ниже исполнимого")

    -- Перерисовка идемпотентна: второй вызов не удваивает ни оговорку, ни
    -- пометку в заголовке.
    local why, benefit = card.why, card.benefit
    ns.Risk:RenderDoubts(card)
    ns.Risk:RenderDoubts(card)
    H.eq(card.why, why, "повторная перерисовка текст не удваивает")
    H.eq(card.benefit, benefit, "и заголовок тоже")
end

H.suite("Сомнение: находка самопроверки доезжает до карточки на целой сборке")
do
    -- ПРОХОД САМОПРОВЕРОК ШЁЛ ПОСЛЕ ЗАПИСИ КАРТОЧЕК И ПИСАЛ ТОЛЬКО В ФАЙЛ.
    -- Поэтому проверять маршрут вызовом Diag:Suspect руками недостаточно: он
    -- работал бы и тогда, когда до экрана всё равно ничего не доходит. Здесь -
    -- целая сборка: цена явно битая, самопроверка это находит, и её слова
    -- обязаны оказаться на самой карточке.
    local env = H.load()
    local ns = env.ns
    env.money = 5000000
    H.item(env, 2320, { name = "Грубая нить", sellPrice = 2 })
    H.item(env, 2569, { name = "Льняные сапоги", equipLoc = "INVTYPE_FEET",
        reqLevel = 10, classID = 4, subclassID = 1, sellPrice = 19 })
    env.vendorPrices[2320] = 9
    env.prices[2569] = 5000000
    H.profession(env, "Портняжное дело", 225, 225, {
        H.recipe { id = 2386, output = 2569, outputQty = 1,
                   reagents = { { itemID = 2320, qty = 1 } },
                   name = "Льняные сапоги", diff = "trivial", category = "Обувь" },
    })
    local cards = H.build(env)
    local c = cardByKind(cards, ns.KIND.CRAFT_PROFIT)
    H.ok(c ~= nil, "карточка построена")
    local found
    for _, e in ipairs(ns.Diag:Init().suspicious or {}) do
        if e.code == "implausible-profit" then found = e end
    end
    H.ok(found ~= nil, "самопроверка нашла неправдоподобную прибыль")
    if c and found then
        local onCard = false
        for _, d in ipairs(c.doubts or {}) do
            if d.code == "implausible-profit" then onCard = true end
        end
        H.ok(onCard, "и находка приложена к карточке")
        H.ok(ns.Util.contains(c.why, "скорее битая цена"),
            "и напечатана на ней: " .. ns.Util.truncate(c.why, 220))
        H.ok(c.doubtLevel ~= nil, "карточка помечена сомнением: "
            .. tostring(c.doubtLevel))
        -- И в файл записано, сколько находок доехало.
        local m = ns.Diag:Init().modules.sanityChecks
        H.ok(m and (m.onCards or 0) > 0,
            "в файле записано, сколько находок доехало: "
            .. tostring(m and m.onCards))
    end
end

H.suite("Сомнение: находка, написанная не для игрока, не уезжает на карточку дословно")
do
    local env = H.load()
    local ns = env.ns
    local card = { key = "k", kind = ns.KIND.CRAFT_PROFIT, title = "Совет",
                   benefit = "+5з", why = "Материалы 6с.", need = "y",
                   conf = ns.CONF.CACHED, score = 0.5 }
    ns.Diag:BindCards({ card })
    ns.Diag:Suspect("bad-score", "у совета №3 «Совет» приоритет = nan",
        { key = "k" })
    ns.Diag:UnbindCards()
    ns.Risk:RenderDoubts(card)

    H.eq(card.doubtLevel, ns.Risk.DOUBT_DISTRUST, "ступень — недоверие")
    H.eq(card.why:find("nan", 1, true), nil, "мусор на карточку не уехал")
    H.eq(card.why:find("№3", 1, true), nil, "и номер совета тоже")
    H.ok(ns.Util.contains(card.why, ns.Risk.DOUBT_DEFECT_SAY),
        "вместо них — одна честная фраза: " .. ns.Util.truncate(card.why, 160))
    H.eq(card.conf, ns.CONF.UNKNOWN, "достоверность снята совсем")
    H.eq(ns.ActionEngine.TierOf(card), 0, "и карточка ушла под всё исполнимое")
end

end
