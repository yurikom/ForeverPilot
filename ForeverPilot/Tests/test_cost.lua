-- ForeverPilot / Tests/test_cost.lua
-- Costing, margins, price-source precedence and graceful degradation.
local H = ...

return function()

local function base()
    local env = H.load()
    H.item(env, 1, { name = "Сырьё", sellPrice = 10 })
    H.item(env, 2, { name = "Полуфабрикат", sellPrice = 25 })
    H.item(env, 3, { name = "Товар", sellPrice = 200 })
    return env
end

H.suite("Себестоимость: базовый расчёт")
do
    local env = base()
    local ns = env.ns
    env.prices[1] = 100
    env.prices[2] = 900     -- dearer than 3x100, so craft
    env.prices[3] = 5000
    H.profession(env, "Tailoring", 225, 225, {
        H.recipe { id = 1, output = 2, outputQty = 1, reagents = { { itemID = 1, qty = 3 } } },
        H.recipe { id = 2, output = 3, outputQty = 1, reagents = { { itemID = 2, qty = 2 } } },
    })
    H.rescan(env)
    ns.PriceProvider:BeginPass()
    ns.CraftingPlanner:Bind(ns.RecipeBook, ns.PriceProvider):BeginPass()

    -- unit cost of 2 = 3 * 100 = 300 (craft beats buying at 900)
    local u2, c2, m2 = ns.CraftingPlanner:UnitCost(2, 0, {})
    H.eq(u2, 300, "себестоимость полуфабриката 300")
    H.eq(m2, "craft", "полуфабрикат делаем")
    -- unit cost of 3 = 2 * 300 = 600
    local u3, _, m3 = ns.CraftingPlanner:UnitCost(3, 0, {})
    H.eq(u3, 600, "себестоимость товара 600")
    H.eq(m3, "craft", "товар делаем")
end

H.suite("Себестоимость: выход 2 за крафт делит пополам")
do
    local env = base()
    local ns = env.ns
    env.prices[1] = 100
    env.prices[2] = 9000
    H.profession(env, "Tailoring", 225, 225, {
        H.recipe { id = 1, output = 2, outputQty = 2, reagents = { { itemID = 1, qty = 3 } } },
    })
    H.rescan(env)
    ns.PriceProvider:BeginPass()
    ns.CraftingPlanner:Bind(ns.RecipeBook, ns.PriceProvider):BeginPass()
    -- 3 * 100 = 300 for two units -> 150 each
    H.eq(ns.CraftingPlanner:UnitCost(2, 0, {}), 150, "300 за 2 шт = 150 за штуку")
end

H.suite("Маржа")
do
    local env = base()
    local ns = env.ns
    env.prices[1] = 100
    env.prices[3] = 5000
    H.profession(env, "Tailoring", 225, 225, {
        H.recipe { id = 9, output = 3, outputQty = 1, reagents = { { itemID = 1, qty = 10 } } },
    })
    H.rescan(env)
    ns.PriceProvider:BeginPass()
    ns.CraftingPlanner:Bind(ns.RecipeBook, ns.PriceProvider):BeginPass()

    local margin, conf, revenue, cost = ns.CraftingPlanner:Margin(ns.RecipeBook:Get(9))
    H.eq(cost, 1000, "себестоимость 1000")
    -- Revenue is the auction price minus the 5% house cut.
    H.near(revenue, 5000 * 0.95, 0.01, "выручка за вычетом сбора")
    H.near(margin, 4750 - 1000, 0.01, "прибыль 3750")
    H.ok(margin > 0, "прибыль положительная")
end

H.suite("Маржа: убыточный рецепт отрицателен")
do
    local env = base()
    local ns = env.ns
    env.prices[1] = 1000
    env.prices[3] = 2000
    H.profession(env, "Tailoring", 225, 225, {
        H.recipe { id = 9, output = 3, outputQty = 1, reagents = { { itemID = 1, qty = 10 } } },
    })
    H.rescan(env)
    ns.PriceProvider:BeginPass()
    ns.CraftingPlanner:Bind(ns.RecipeBook, ns.PriceProvider):BeginPass()
    local margin = ns.CraftingPlanner:Margin(ns.RecipeBook:Get(9))
    H.ok(margin < 0, "убыток распознан (" .. tostring(margin) .. ")")
end

-- Price-source precedence ---------------------------------------------

H.suite("Цены: приоритет источников")
do
    local env = base()
    local ns = env.ns
    env.prices[1] = 500                        -- auctionator
    env.observedPrices = { [1] = 700 }         -- foreign observation
    env.foreignVendorPrices = { [1] = 300 }    -- foreign vendor
    H.rescan(env)
    ns.PriceProvider:BeginPass()
    local p, conf, src = ns.PriceProvider:Buy(1)
    H.eq(p, 500, "аукцион важнее наблюдений и торговца")
    H.eq(src, "auctionator", "источник помечен верно")
end

H.suite("Цены: падение к наблюдениям")
do
    local env = base()
    local ns = env.ns
    env.auctionator = false
    env.observedPrices = { [1] = 700 }
    H.rescan(env)
    ns.PriceProvider:BeginPass()
    local p, conf, src = ns.PriceProvider:Buy(1)
    H.eq(p, 700, "взяли наблюдение")
    H.eq(src, "foreign", "источник - наблюдение")
    H.ok(conf ~= ns.CONF.EXACT, "достоверность не «точно»")
end

H.suite("Цены: падение к торговцу")
do
    local env = base()
    local ns = env.ns
    env.auctionator = false
    env.foreignVendorPrices = { [1] = 300 }
    H.rescan(env)
    ns.PriceProvider:BeginPass()
    local p, conf, src = ns.PriceProvider:Buy(1)
    H.eq(p, 300, "цена торговца")
    -- Another addon's "vendorPrices" table is used as a number, but we have not
    -- been able to establish whether it holds the merchant's asking price or
    -- what the merchant pays. So it is labelled separately and never counts as
    -- proof that the item is on sale somewhere.
    H.eq(src, "vendorForeign", "источник - чужой кеш торговца, помечен отдельно")
    H.eq(conf, ns.CONF.ESTIMATE, "и подан как оценка")
    H.eq(ns.PriceProvider:Buyable(1), false,
        "по непроверенному кешу предмет не объявляется покупаемым")

    -- Our OWN merchant observation is unambiguous and does count.
    local env2 = base()
    local ns2 = env2.ns
    env2.auctionator = false
    ns2.Config:RememberVendorPrice(1, 300)
    H.rescan(env2)
    ns2.PriceProvider:BeginPass()
    local p2, _, src2 = ns2.PriceProvider:Buy(1)
    H.eq(p2, 300, "своя записанная цена торговца")
    H.eq(src2, "vendor", "источник - торговец")
    H.eq(ns2.PriceProvider:Buyable(1), true, "и предмет действительно можно купить")
end

H.suite("Цены: последний рубеж - наценка на цену продажи")
do
    local env = base()
    local ns = env.ns
    env.auctionator = false
    H.rescan(env)
    ns.PriceProvider:BeginPass()
    local p, conf, src = ns.PriceProvider:Buy(1)
    H.eq(p, 10 * ns.PriceProvider.VENDOR_MARKUP, "цена продажи x4")
    H.eq(src, "markup", "источник - оценка")
    H.eq(conf, ns.CONF.ESTIMATE, "помечено как оценка")
    H.eq(ns.PriceProvider:Buyable(1), false,
        "грубая оценка не считается «можно купить»")
end

H.suite("Цены: совсем ничего")
do
    local env = H.load()
    local ns = env.ns
    H.item(env, 77, { name = "Квестовая штука", sellPrice = 0 })
    env.auctionator = false
    H.rescan(env)
    ns.PriceProvider:BeginPass()
    local p, conf, src = ns.PriceProvider:Buy(77)
    H.eq(p, nil, "цены нет")
    H.eq(conf, ns.CONF.UNKNOWN, "честно помечено «неизвестно»")
    H.eq(src, "none", "источника нет")
end

H.suite("Цены: Auctionator выключен целиком")
do
    local env = base()
    local ns = env.ns
    env.auctionator = false
    env.prices[1] = 500      -- present but unreachable without Auctionator
    H.rescan(env)
    ns.PriceProvider:BeginPass()
    H.eq(ns.PriceProvider:AuctionatorEnabled(), false, "Auctionator не найден")
    local p = ns.PriceProvider:Buy(1)
    H.ok(p ~= 500, "аукционная цена недоступна")
    local summary = ns.PriceProvider:SourceSummary()
    H.eq(summary.auctionatorAvailable, false, "сводка знает, что аукциона нет")
end

H.suite("Цены: продажа торговцу точная")
do
    local env = base()
    local ns = env.ns
    env.auctionator = false
    H.rescan(env)
    ns.PriceProvider:BeginPass()
    local p, conf = ns.PriceProvider:VendorSell(3)
    H.eq(p, 200, "цена продажи торговцу взята из клиента")
    H.eq(conf, ns.CONF.EXACT, "это точные данные, не оценка")
end

-- Confidence propagation ----------------------------------------------

H.suite("Достоверность: берётся по худшему входу")
do
    local env = base()
    local ns = env.ns
    local U = ns.Util
    H.eq(U.worstConf("EXACT", "EXACT"), "EXACT", "точно + точно = точно")
    H.eq(U.worstConf("EXACT", "CACHED"), "CACHED", "точно + кеш = кеш")
    H.eq(U.worstConf("CACHED", "ESTIMATE"), "ESTIMATE", "кеш + оценка = оценка")
    H.eq(U.worstConf("EXACT", "UNKNOWN"), "UNKNOWN", "любое + неизвестно = неизвестно")
    H.eq(U.worstConf("ESTIMATE"), "ESTIMATE", "один вход")
end

H.suite("Достоверность: неизвестная цена реагента ломает себестоимость")
do
    local env = base()
    local ns = env.ns
    H.item(env, 50, { name = "Недобываемое", sellPrice = 0 })
    env.prices[1] = 100
    H.profession(env, "Tailoring", 225, 225, {
        H.recipe { id = 1, output = 3, reagents = {
            { itemID = 1, qty = 2 }, { itemID = 50, qty = 1 } } },
    })
    H.rescan(env)
    ns.PriceProvider:BeginPass()
    ns.CraftingPlanner:Bind(ns.RecipeBook, ns.PriceProvider):BeginPass()
    local cost, conf = ns.CraftingPlanner:RecipeMaterialCost(ns.RecipeBook:Get(1), 0, {})
    H.eq(cost, nil, "себестоимость не считается, если цена реагента неизвестна")
    H.eq(conf, ns.CONF.UNKNOWN, "достоверность - неизвестно")
    local margin = ns.CraftingPlanner:Margin(ns.RecipeBook:Get(1))
    H.eq(margin, nil, "и маржа тоже не выдумывается")
end

-- Money formatting ----------------------------------------------------

H.suite("Формат денег")
do
    local env = H.load()
    local U = env.ns.Util
    H.eq(U.money(0), "0м", "ноль")
    H.eq(U.money(81), "81м", "медь")
    H.eq(U.money(5081), "50с 81м", "серебро и медь")
    H.eq(U.money(25081), "2з 50с", "золото и серебро, медь отброшена")
    H.eq(U.money(25081, true), "2з 50с 81м", "полный формат")
    H.eq(U.money(10000), "1з", "ровно золотой")
    H.eq(U.moneyDelta(500), "+5с", "плюс")
    H.eq(U.moneyDelta(-500), "-5с", "минус")
    H.eq(U.moneyDelta(0), "0м", "ровный ноль остаётся нулём")
    -- БЕЗ ЧИСЛА - «не знаю», А НЕ ПРОЧЕРК. Раньше здесь стоял прочерк, и это
    -- была ровно та путаница, из-за которой заведён словарь пустоты (ns.VOID):
    -- прочерк означает «такого значения не бывает», а U.money про причину
    -- ничего не знает - ей просто не дали числа. Разбор всех четырёх состояний
    -- живёт в Tests/test_void.lua.
    H.eq(U.money(nil), env.ns.VOID_TEXT.UNKNOWN, "nil - это «не знаю»")
    H.eq(U.moneyDelta(nil), env.ns.VOID_TEXT.UNKNOWN,
        "разницы нет - «не знаю», а не «0м»")
    H.ok(U.money(nil) ~= env.ns.VOID_TEXT.IMPOSSIBLE,
        "и не «так нельзя»: эти два случая разные")
end

H.suite("Утилиты: округление вверх при делении")
do
    local env = H.load()
    local U = env.ns.Util
    H.eq(U.ceilDiv(5, 2), 3, "5/2 вверх = 3")
    H.eq(U.ceilDiv(4, 2), 2, "4/2 = 2")
    H.eq(U.ceilDiv(1, 3), 1, "1/3 вверх = 1")
    H.eq(U.ceilDiv(0, 3), 0, "0/3 = 0")
    H.eq(U.ceilDiv(5, 0), 0, "деление на ноль безопасно")
end

H.suite("Утилиты: пул материалов")
do
    local env = H.load()
    local U = env.ns.Util
    local pool = { [1] = 5 }
    H.eq(U.takeFrom(pool, 1, 3), 3, "взяли 3 из 5")
    H.eq(pool[1], 2, "осталось 2")
    H.eq(U.takeFrom(pool, 1, 10), 2, "взяли остаток")
    H.eq(pool[1], nil, "запись удалена, а не оставлена нулём")
    H.eq(U.takeFrom(pool, 99, 1), 0, "из пустого ничего не взять")
    U.addTo(pool, 1, 4)
    H.eq(pool[1], 4, "добавление работает")
end

H.suite("Утилиты: русские множественные числа")
do
    local env = H.load()
    local U = env.ns.Util
    H.eq(U.plural(1, "рецепт", "рецепта", "рецептов"), "рецепт", "1")
    H.eq(U.plural(2, "рецепт", "рецепта", "рецептов"), "рецепта", "2")
    H.eq(U.plural(5, "рецепт", "рецепта", "рецептов"), "рецептов", "5")
    H.eq(U.plural(11, "рецепт", "рецепта", "рецептов"), "рецептов", "11")
    H.eq(U.plural(21, "рецепт", "рецепта", "рецептов"), "рецепт", "21")
    H.eq(U.plural(112, "рецепт", "рецепта", "рецептов"), "рецептов", "112")
end

H.suite("Утилиты: разбор ссылок на предметы")
do
    local env = H.load()
    local U = env.ns.Util
    local plain = "|cnIQ3:|Hitem:253957::::::::26:1482::::::::Player-6946-00CCA8FC:|h[Жемчужный венец]|h|r"
    local enchanted = "|cnIQ2:|Hitem:12047:12748:::::::26:1482:::1:12748::::::|h[Призрачное ожерелье]|h|r"
    H.eq(U.itemIDFromLink(plain), 253957, "id из ссылки")
    H.eq(U.itemNameFromLink(plain), "Жемчужный венец", "имя из ссылки")
    H.eq(U.enchantIDFromLink(plain), nil, "незачарованная вещь - nil")
    H.eq(U.enchantIDFromLink(enchanted), 12748, "id чар прочитан")
    H.eq(U.itemIDFromLink(nil), nil, "nil не ломает разбор")
    H.eq(U.itemIDFromLink("мусор"), nil, "мусор не ломает разбор")
end

end
