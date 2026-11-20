-- ForeverPilot / Tests/test_planner.lua
-- Material maths: recursion, shared ingredients, output quantities, cycles.
local H = ...

return function()

-- Fixture ---------------------------------------------------------------
-- A tailoring chain modelled on the player's real one:
--   2589 Linen Cloth  ->  2996 Bolt of Linen (2 cloth -> 1 bolt)
--   2592 Wool Cloth   ->  2997 Bolt of Woolen (3 wool -> 1 bolt)
--   4306 Silk         ->  4305 Bolt of Silk (4 silk -> 1 bolt)
--   2996 + 2320 Coarse Thread -> 4308 Green Linen Bracers
local function fixture(opts)
    opts = opts or {}
    local env = H.load()
    local ns = env.ns

    H.item(env, 2589, { name = "Льняная ткань", sellPrice = 5 })
    H.item(env, 2592, { name = "Шерстяная ткань", sellPrice = 10 })
    H.item(env, 4306, { name = "Шелковая ткань", sellPrice = 40 })
    H.item(env, 2320, { name = "Грубая нить", sellPrice = 2 })
    H.item(env, 2996, { name = "Рулон льняной ткани", sellPrice = 12 })
    H.item(env, 2997, { name = "Рулон шерстяной ткани", sellPrice = 30 })
    H.item(env, 4305, { name = "Рулон шелка", sellPrice = 170 })
    H.item(env, 4308, { name = "Зеленые льняные наручи", sellPrice = 300,
        equipLoc = "INVTYPE_WRIST", reqLevel = 13, classID = 4, subclassID = 1 })
    H.item(env, 9999, { name = "Поножи", sellPrice = 500,
        equipLoc = "INVTYPE_LEGS", reqLevel = 40, classID = 4, subclassID = 1 })

    env.prices[2589] = 50      -- linen cloth, 50c each
    env.prices[2592] = 100
    env.prices[4306] = 400
    env.prices[2320] = 9
    env.prices[2996] = 130     -- a bolt costs more than 2 cloth (2x50=100)
    env.prices[2997] = 400     -- a woolen bolt is CHEAPER than 3 wool (3x100=300)? no: 400 > 300
    env.prices[4305] = 1500    -- cheaper than 4 silk (4x400=1600)
    env.prices[4308] = 2000
    env.prices[9999] = 9000

    local recipes = {
        H.recipe { id = 2963, name = "Рулон льняной ткани", output = 2996, outputQty = 1,
                   reagents = { { itemID = 2589, qty = 2 } }, diff = "trivial",
                   category = "Реагенты", categoryID = 100 },
        H.recipe { id = 2964, name = "Рулон шерстяной ткани", output = 2997, outputQty = 1,
                   reagents = { { itemID = 2592, qty = 3 } }, diff = "trivial",
                   category = "Реагенты", categoryID = 100 },
        H.recipe { id = 3839, name = "Рулон шелка", output = 4305, outputQty = 1,
                   reagents = { { itemID = 4306, qty = 4 } }, diff = "trivial",
                   category = "Реагенты", categoryID = 100 },
        H.recipe { id = 3841, name = "Зеленые льняные наручи", output = 4308, outputQty = 1,
                   reagents = { { itemID = 2996, qty = 3 }, { itemID = 2320, qty = 2 } },
                   diff = "optimal", category = "Наручи", categoryID = 101 },
        H.recipe { id = 12049, name = "Поножи", output = 9999, outputQty = 1,
                   reagents = { { itemID = 4305, qty = 2 }, { itemID = 2997, qty = 2 } },
                   diff = "medium", category = "Поножи", categoryID = 102 },
        -- Makes 2 at a time: tests the surplus path.
        H.recipe { id = 7000, name = "Парные бинты", output = 7001, outputQty = 2,
                   reagents = { { itemID = 2996, qty = 1 } }, diff = "trivial",
                   category = "Бинты", categoryID = 103 },
    }
    H.item(env, 7001, { name = "Бинт", sellPrice = 4 })
    -- Deliberately dearer than making one (a bolt is 100 to make, 2 bandages
    -- per bolt = 50 each), so the planner chooses to craft and we exercise the
    -- surplus path.
    env.prices[7001] = 500

    if opts.extraRecipes then
        for _, r in ipairs(opts.extraRecipes) do recipes[#recipes + 1] = r end
    end

    H.profession(env, "Tailoring", 225, 225, recipes)
    env.money = 25081
    H.rescan(env)
    ns.PriceProvider:BeginPass()
    ns.CraftingPlanner:Bind(ns.RecipeBook, ns.PriceProvider):BeginPass()
    return env
end

-- 1. Nothing in the bags: everything is raw and must be bought ----------

H.suite("Планировщик: пустые сумки")
do
    local env = fixture()
    local ns = env.ns
    local recipe = ns.RecipeBook:Get(3841)
    local plan = ns.CraftingPlanner:Plan(recipe, 1)

    H.ok(plan ~= nil, "план построен")
    -- A bolt costs 130 to buy, but 2 linen at 50 = 100 to make. So the planner
    -- should decide to craft the bolts and buy linen cloth instead.
    H.eq(plan.decisions[2996] and plan.decisions[2996].method, "craft",
        "рулон дешевле скрафтить, чем купить")
    H.eq(plan.needRaw[2589], 6, "6 льняной ткани на 3 рулона")
    H.eq(plan.needRaw[2320], 2, "2 нити")
    H.eq(plan.needRaw[2996], nil, "рулон не покупаем - делаем")
    H.eq(#plan.crafts, 2, "два шага крафта: рулон, потом наручи")
    H.eq(plan.crafts[1].recipeID, 2963, "сначала рулон")
    H.eq(plan.crafts[2].recipeID, 3841, "потом наручи")
    H.eq(plan.crafts[1].times, 3, "рулон делаем 3 раза")
    -- 6 * 50 + 2 * 9 = 318
    H.eq(plan.cost, 318, "стоимость закупки 318м")
    H.eq(plan.ready, false, "не готово - нужно докупить")
end

-- 2. Buying the intermediate wins when crafting it is dearer ------------

H.suite("Планировщик: купить промежуточный vs скрафтить")
do
    local env = fixture()
    local ns = env.ns
    -- A silk bolt is 1500 to buy but 4x400 = 1600 to make: buy it.
    local plan = ns.CraftingPlanner:Plan(ns.RecipeBook:Get(12049), 1)
    H.eq(plan.decisions[4305] and plan.decisions[4305].method, "buy",
        "рулон шелка выгоднее купить")
    H.eq(plan.needRaw[4305], 2, "покупаем 2 рулона шелка")
    H.eq(plan.needRaw[4306], nil, "шелковую ткань не покупаем")
    -- A woolen bolt is 400 to buy but 3x100 = 300 to make: craft it.
    H.eq(plan.decisions[2997] and plan.decisions[2997].method, "craft",
        "рулон шерсти выгоднее скрафтить")
    H.eq(plan.needRaw[2592], 6, "6 шерстяной ткани на 2 рулона")
    -- 2 * 1500 + 6 * 100 = 3600
    H.eq(plan.cost, 3600, "итого 3600м")
end

-- 3. Materials already in the bags are deducted -------------------------

H.suite("Планировщик: вычет из сумок")
do
    local env = fixture()
    local ns = env.ns
    env.bags[2589] = 4    -- enough for 2 bolts
    env.bags[2320] = 10
    H.rescan(env)
    ns.PriceProvider:BeginPass()
    ns.CraftingPlanner:BeginPass()

    local plan = ns.CraftingPlanner:Plan(ns.RecipeBook:Get(3841), 1)
    H.eq(plan.usedHere[2589], 4, "взяли 4 ткани из сумок")
    H.eq(plan.usedHere[2320], 2, "взяли 2 нити из сумок")
    H.eq(plan.needRaw[2589], 2, "докупить 2 ткани")
    H.eq(plan.needRaw[2320], nil, "нить докупать не нужно")
    H.eq(plan.cost, 100, "осталось купить на 100м")
    H.ok(plan.readiness > 0.5 and plan.readiness < 1, "готовность между 0 и 1")
end

-- 4. Everything on hand -------------------------------------------------

H.suite("Планировщик: всё есть")
do
    local env = fixture()
    local ns = env.ns
    env.bags[2589] = 6
    env.bags[2320] = 2
    H.rescan(env)
    ns.PriceProvider:BeginPass()
    ns.CraftingPlanner:BeginPass()

    local plan = ns.CraftingPlanner:Plan(ns.RecipeBook:Get(3841), 1)
    H.eq(plan.ready, true, "готово к крафту")
    H.eq(plan.cost, 0, "покупать нечего")
    H.eq(plan.readiness, 1, "готовность 100%")
    H.eq(#plan.shopping, 0, "список покупок пуст")
end

-- 5. THE shared-ingredient case ----------------------------------------
-- Two sub-recipes both want linen bolts. The pool is shared, so the bolts in
-- the bags must be counted once, not once per branch.

H.suite("Планировщик: общий ингредиент у нескольких рецептов")
do
    local env = H.load()
    local ns = env.ns
    H.item(env, 2589, { name = "Льняная ткань", sellPrice = 5 })
    H.item(env, 2996, { name = "Рулон льна", sellPrice = 12 })
    H.item(env, 500, { name = "Деталь A" })
    H.item(env, 501, { name = "Деталь B" })
    H.item(env, 502, { name = "Готовое изделие" })
    env.prices[2589] = 50
    env.prices[2996] = 500   -- expensive to buy, so crafting wins
    env.prices[500] = 9000
    env.prices[501] = 9000

    H.profession(env, "Tailoring", 225, 225, {
        H.recipe { id = 1, output = 2996, outputQty = 1,
                   reagents = { { itemID = 2589, qty = 2 } }, name = "Рулон льна" },
        H.recipe { id = 2, output = 500, outputQty = 1,
                   reagents = { { itemID = 2996, qty = 2 } }, name = "Деталь A" },
        H.recipe { id = 3, output = 501, outputQty = 1,
                   reagents = { { itemID = 2996, qty = 3 } }, name = "Деталь B" },
        H.recipe { id = 4, output = 502, outputQty = 1,
                   reagents = { { itemID = 500, qty = 1 }, { itemID = 501, qty = 1 } },
                   name = "Готовое изделие" },
    })
    -- 4 bolts in the bags. Branch A wants 2, branch B wants 3: total 5.
    env.bags[2996] = 4
    H.rescan(env)
    ns.PriceProvider:BeginPass()
    ns.CraftingPlanner:Bind(ns.RecipeBook, ns.PriceProvider):BeginPass()

    local plan = ns.CraftingPlanner:Plan(ns.RecipeBook:Get(4), 1)
    H.eq(plan.usedHere[2996], 4, "все 4 рулона из сумок израсходованы один раз")
    -- The 5th bolt has to be made: 2 linen cloth.
    H.eq(plan.needRaw[2589], 2, "на пятый рулон нужно 2 льняной ткани")
    H.eq(plan.needRaw[2996], nil, "рулон не покупаем")
    local boltCraft
    for _, step in ipairs(plan.crafts) do
        if step.recipeID == 1 then boltCraft = step end
    end
    H.eq(boltCraft and boltCraft.times, 1, "рулон делаем ровно 1 раз, а не 2")
    H.eq(plan.cost, 100, "докупка только 100м")
end

-- 6. Surplus from a recipe that makes more than one --------------------

H.suite("Планировщик: выход больше 1 за крафт")
do
    -- Recipe 7000 makes 2 bandages from 1 bolt. A kit needs 3 bandages, so the
    -- planner must run it twice (producing 4) and put the spare back in the pool.
    local env = fixture({ extraRecipes = {
        H.recipe { id = 7003, output = 7002, outputQty = 1,
                   reagents = { { itemID = 7001, qty = 3 } }, name = "Набор из 3 бинтов" },
    } })
    local ns = env.ns
    H.item(env, 7002, { name = "Набор", sellPrice = 100 })
    env.prices[7002] = 9000

    env.bags[2589] = 100
    H.rescan(env)
    ns.PriceProvider:BeginPass()
    ns.CraftingPlanner:BeginPass()

    local plan = ns.CraftingPlanner:Plan(ns.RecipeBook:Get(7003), 1)
    H.ok(plan ~= nil, "план построен")
    local bandageStep
    for _, step in ipairs(plan.crafts or {}) do
        if step.recipeID == 7000 then bandageStep = step end
    end
    H.eq(bandageStep and bandageStep.times, 2, "бинты делаем 2 раза (4 шт на 3 нужных)")
    H.eq(plan.needRaw[7001], nil, "бинты не покупаем")
    -- 2 runs need 2 bolts, which is 4 linen cloth; all of it is in the bags.
    H.eq(plan.usedHere[2589], 4, "израсходовано 4 льняной ткани из сумок")
    H.eq(plan.ready, true, "всё из своего")
end

H.suite("Книга рецептов: свежий скан того же ранга заменяет старый")
do
    local env = fixture()
    local ns = env.ns
    local before = #ns.RecipeBook:Bucket("Tailoring").list
    H.ok(before > 1, "в книге много рецептов")

    -- A new scan of the same profession is the whole truth, not an addition:
    -- the player may have unlearned something.
    ns.RecipeBook:Store("Tailoring", {
        H.recipe { id = 999, output = 4308, reagents = { { itemID = 2589, qty = 1 } } },
    }, "own", ns.CONF.EXACT, 1)
    H.eq(#ns.RecipeBook:Bucket("Tailoring").list, 1, "новый скан заменил старый целиком")
end

H.suite("Книга рецептов: слабый источник не перебивает сильный")
do
    local env = fixture()
    local ns = env.ns
    local before = #ns.RecipeBook:Bucket("Tailoring").list
    -- A foreign cache must not overwrite what we read ourselves.
    local added = ns.RecipeBook:Store("Tailoring", {
        H.recipe { id = 998, output = 4308, reagents = { { itemID = 2589, qty = 1 } } },
    }, "foreign", ns.CONF.CACHED, 1)
    H.eq(added, 0, "чужой кеш отклонён")
    H.eq(#ns.RecipeBook:Bucket("Tailoring").list, before, "список не изменился")
    H.eq(ns.RecipeBook:Bucket("Tailoring").source, "own", "источник остался «own»")
end

H.suite("Книга рецептов: реагенты одного предмета в двух слотах складываются")
do
    local env = fixture()
    local ns = env.ns
    -- Some recipes list the same item in two reagent slots. The planner must
    -- see one requirement of the summed quantity, not two separate ones.
    local recipe = H.recipe { id = 1234, output = 4308, reagents = {
        { itemID = 2589, qty = 2 }, { itemID = 2320, qty = 1 },
        { itemID = 2589, qty = 3 },
    } }
    local normalized = ns.RecipeBook:Normalize(recipe, "Tailoring")
    H.eq(#normalized.reagents, 3, "в сыром виде три слота")
    local merged = ns.RecipeBook:MergedReagents(normalized)
    H.eq(#merged, 2, "после слияния две позиции")
    local byID = {}
    for _, r in ipairs(merged) do byID[r.itemID] = r.qty end
    H.eq(byID[2589], 5, "2 + 3 = 5")
    H.eq(byID[2320], 1, "вторая позиция не тронута")
end

-- 7. Cycle protection -------------------------------------------------

H.suite("Планировщик: защита от циклов")
do
    local env = H.load()
    local ns = env.ns
    H.item(env, 10, { name = "Предмет X" })
    H.item(env, 11, { name = "Предмет Y" })
    H.item(env, 12, { name = "Финал" })
    env.prices[10] = 100
    env.prices[11] = 100
    env.prices[12] = 5000

    -- X is made from Y, Y is made from X. A naive planner loops forever here.
    H.profession(env, "Tailoring", 225, 225, {
        H.recipe { id = 20, output = 10, reagents = { { itemID = 11, qty = 1 } }, name = "X из Y" },
        H.recipe { id = 21, output = 11, reagents = { { itemID = 10, qty = 1 } }, name = "Y из X" },
        H.recipe { id = 22, output = 12, reagents = { { itemID = 10, qty = 2 } }, name = "Финал" },
    })
    H.rescan(env)
    ns.PriceProvider:BeginPass()
    ns.CraftingPlanner:Bind(ns.RecipeBook, ns.PriceProvider):BeginPass()

    local ok, plan = pcall(function()
        return ns.CraftingPlanner:Plan(ns.RecipeBook:Get(22), 1)
    end)
    H.ok(ok, "планировщик не упал и не зацикбился", tostring(plan))
    H.ok(ok and plan ~= nil, "план получен")
    if ok and plan then
        local total = 0
        for _, qty in pairs(plan.needRaw) do total = total + qty end
        H.ok(total > 0, "цикл разорван: что-то попало в покупки")
        H.ok(#plan.crafts <= 10, "количество шагов конечно (" .. #plan.crafts .. ")")
    end
end

-- A recipe whose reagent is its own output.
H.suite("Планировщик: рецепт из самого себя")
do
    local env = H.load()
    local ns = env.ns
    H.item(env, 30, { name = "Самоед" })
    H.item(env, 31, { name = "Сырьё" })
    env.prices[30] = 1000
    env.prices[31] = 10
    H.profession(env, "Tailoring", 225, 225, {
        H.recipe { id = 40, output = 30, outputQty = 2,
                   reagents = { { itemID = 30, qty = 1 }, { itemID = 31, qty = 1 } },
                   name = "Удвоитель" },
    })
    H.rescan(env)
    ns.PriceProvider:BeginPass()
    ns.CraftingPlanner:Bind(ns.RecipeBook, ns.PriceProvider):BeginPass()

    local ok, plan = pcall(function()
        return ns.CraftingPlanner:Plan(ns.RecipeBook:Get(40), 1)
    end)
    H.ok(ok and plan ~= nil, "не упал на самоподдерживающемся рецепте", tostring(plan))
    if ok and plan then
        H.eq(plan.needRaw[30], 1, "сам предмет уходит в покупку, а не в бесконечный крафт")
    end
end

-- 8. Quantity multiplies correctly -------------------------------------

H.suite("Планировщик: количество")
do
    local env = fixture()
    local ns = env.ns
    local plan = ns.CraftingPlanner:Plan(ns.RecipeBook:Get(3841), 5)
    H.eq(plan.needRaw[2589], 30, "5 наручей = 15 рулонов = 30 ткани")
    H.eq(plan.needRaw[2320], 10, "10 нити")
    H.eq(plan.cost, 30 * 50 + 10 * 9, "стоимость умножается")
end

-- 9. Bank stock counts but is flagged as a trip ------------------------

H.suite("Планировщик: материалы в банке")
do
    local env = fixture()
    local ns = env.ns
    env.bags[2320] = 2
    env.bank = { [2589] = 6 }
    H.rescan(env)
    ns.PriceProvider:BeginPass()
    ns.CraftingPlanner:BeginPass()

    local plan = ns.CraftingPlanner:Plan(ns.RecipeBook:Get(3841), 1)
    H.eq(plan.usedBank[2589], 6, "6 ткани взято из банка")
    H.eq(plan.ready, true, "формально всё есть")
    H.eq(plan.needsTrip, true, "но нужен поход в банк")
end

-- Bank switched off: the same materials must now be bought.
H.suite("Планировщик: банк отключён")
do
    local env = fixture()
    local ns = env.ns
    ns.Config:Get().show.includeBank = false
    env.bags[2320] = 2
    env.bank = { [2589] = 6 }
    H.rescan(env)
    ns.PriceProvider:BeginPass()
    ns.CraftingPlanner:BeginPass()

    local plan = ns.CraftingPlanner:Plan(ns.RecipeBook:Get(3841), 1, { useBank = false })
    H.eq(plan.usedBank[2589], nil, "банк не учитывается")
    H.eq(plan.needRaw[2589], 6, "всю ткань нужно купить")
end

-- 10. Unknown prices stay unknown --------------------------------------

H.suite("Планировщик: неизвестные цены")
do
    local env = fixture()
    local ns = env.ns
    env.prices = {}        -- no auction data at all
    env.auctionator = false
    H.rescan(env)
    ns.PriceProvider:BeginPass()
    ns.CraftingPlanner:BeginPass()

    local plan = ns.CraftingPlanner:Plan(ns.RecipeBook:Get(3841), 1)
    H.ok(plan ~= nil, "план строится и без цен")
    -- Items have a sellPrice, so the markup estimate kicks in; the key point is
    -- that the confidence is never claimed as exact.
    H.ok(plan.costConf ~= ns.CONF.EXACT, "достоверность цены не «точно»")
    H.ok(plan.needRaw[2589] ~= nil or plan.usedHere[2589] ~= nil,
        "материалы всё равно перечислены")
end

H.suite("Планировщик: MaxCraftableNow")
do
    local env = fixture()
    local ns = env.ns
    env.bags[2996] = 7
    env.bags[2320] = 5
    H.rescan(env)
    ns.PriceProvider:BeginPass()
    ns.CraftingPlanner:BeginPass()
    -- 3 bolts + 2 thread per craft: 7 bolts -> 2, 5 thread -> 2. Answer: 2.
    H.eq(ns.CraftingPlanner:MaxCraftableNow(ns.RecipeBook:Get(3841)), 2,
        "из 7 рулонов и 5 нитей выходит 2 наруча")
end

end
