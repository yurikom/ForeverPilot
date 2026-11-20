-- ForeverPilot / Tests/test_regress.lua
--
-- Regression tests. Every assertion in this file corresponds to a bug that was
-- actually reproduced against the real code: each one failed before its fix and
-- passes after. Nothing here is speculative - a case that could not be proven
-- outside the game is written up in the report instead of guessed at here.
--
-- Run with:  lua Tests/run.lua
local H = ...

return function()

local function fresh(opts)
    local env = H.load(opts)
    return env, env.ns
end

-- 1. Buy price: the cheapest route the player can actually use ------------
-- A merchant we have stood in front of asks 100 for an item the auction house
-- lists at 10000. Buying from the merchant is both possible and ten times
-- cheaper, so that is the number the advice has to use.

H.suite("Регресс: цена покупки — выбирается дешёвый доступный источник")
do
    local env, ns = fresh()
    env.items[1] = { name = "Ткань", sellPrice = 10 }
    env.prices[1] = 10000
    ns.Config:RememberVendorPrice(1, 100)
    ns.PriceProvider:BeginPass()
    local copper, conf, src = ns.PriceProvider:Buy(1)
    H.eq(copper, 100, "взята цена торговца 100, а не аукциона 10000")
    H.eq(src, "vendor", "источник помечен как торговец")
    H.ok(conf ~= nil and ns.CONF_LABEL[conf] ~= nil, "достоверность заполнена: " .. tostring(conf))

    -- And the other way round: when the auction is cheaper, it wins.
    local env2, ns2 = fresh()
    env2.items[1] = { name = "Ткань" }
    env2.prices[1] = 80
    ns2.Config:RememberVendorPrice(1, 500)
    ns2.PriceProvider:BeginPass()
    local c2, _, s2 = ns2.PriceProvider:Buy(1)
    H.eq(c2, 80, "аукцион 80 дешевле торговца 500 — берётся аукцион")
    H.eq(s2, "auctionator", "источник помечен как аукцион")
end

-- 1b. A non-positive price is not a price -------------------------------
H.suite("Регресс: цена 0 или меньше не считается ценой")
do
    local env, ns = fresh()
    env.items[2] = { name = "Нулевой", sellPrice = 0 }
    -- Every source returns a zero or negative number.
    function env.Api:AuctionPrice() return 0, ns.CONF.CACHED, 0 end
    function env.Api:MastercraftObservedPrice() return 0, ns.CONF.CACHED, 0 end
    function env.Api:MastercraftVendorPrice() return -5, ns.CONF.CACHED end
    function env.Api:VendorPrice() return 0, ns.CONF.CACHED end
    ns.PriceProvider:BeginPass()
    local copper, conf, src = ns.PriceProvider:Buy(2)
    H.eq(copper, nil, "нулевая цена не выдаётся за цену")
    H.eq(conf, ns.CONF.UNKNOWN, "достоверность — неизвестно")
    H.eq(src, "none", "источник — никакой")
    H.eq(ns.PriceProvider:Buyable(2), false, "предмет не считается покупаемым")
end

-- 1c. Our own observation is counted in the source summary --------------
H.suite("Регресс: источник «мои данные» попадает в сводку по ценам")
do
    local env, ns = fresh()
    env.items[3] = { name = "Своя цена" }
    env.prices = {}
    ns.Config:RememberPrice(3, 1234, "own", ns.Api:ServerTime())
    ns.PriceProvider:BeginPass()
    local copper = ns.PriceProvider:Buy(3)
    H.eq(copper, 1234, "цена из своего кеша прочитана")
    local sum = ns.PriceProvider:SourceSummary()
    H.eq(sum.total, 1, "запрос учтён в сводке (было 0 — диагностика врала)")
    H.eq(sum.own, 1, "и отнесён к источнику «мои данные»")
end

-- 1d. Limited merchant stock is not a standing buy price ----------------
H.suite("Регресс: ограниченный ассортимент торговца не запоминается как цена")
do
    local env, ns = fresh()
    env.items[4] = { name = "Редкий чертёж" }
    env.items[5] = { name = "Обычная ткань" }
    env.npcUnit = { id = 777, name = "Торговец" }
    env.playerMap = { mapID = 1, x = 0.5, y = 0.5, zone = "Дуротар" }
    env.merchantItems = {
        { itemID = 4, name = "Редкий чертёж", price = 5000, stack = 1, numAvailable = 1 },
        { itemID = 5, name = "Обычная ткань", price = 500, stack = 5, numAvailable = -1 },
    }
    ns.Places:RecordMerchant()
    H.eq(ns.Config:VendorPrice(4), nil, "позиция с лимитом 1 шт. не записана как цена")
    H.eq(ns.Config:VendorPrice(5), 100, "неограниченная позиция записана по цене за штуку")
end

-- 2. Pinning a material must not double the need ------------------------
H.suite("Регресс: закрепление позиции не удваивает потребность")
do
    local env, ns = fresh()
    env.items[10] = { name = "Шерсть" }
    env.prices[10] = 100
    ns.PriceProvider:BeginPass()
    ns.ShoppingList:Reset()
    ns.ShoppingList:Add(10, 3, "plan:1", "План", { unit = 100, conf = ns.CONF.CACHED, buyable = true })
    ns.ShoppingList:Pin(10, 3)
    ns.ShoppingList:LoadPinned()
    local lines = ns.ShoppingList:Lines()
    H.eq(#lines, 1, "строка одна, а не две")
    H.eq(lines[1] and lines[1].qty, 3, "количество 3, а не 6")

    -- Pinning MORE than the plan needs raises the number to what was pinned.
    ns.ShoppingList:Pin(10, 7)
    ns.ShoppingList:Reset()
    ns.ShoppingList:Add(10, 3, "plan:1", "План", { unit = 100, conf = ns.CONF.CACHED, buyable = true })
    ns.ShoppingList:LoadPinned()
    H.eq(ns.ShoppingList:Lines()[1].qty, 7, "закрепили 7 при потребности 3 — показываем 7")
end

-- 3. Two cards needing the same material share one inventory ------------
-- Recipe A needs 10 cloth, recipe B needs 10, the bags hold 7. Each card on its
-- own is short 3. Doing both is short 13, not 6: the same 7 cannot be spent
-- twice.

H.suite("Регресс: общий список не вычитает одни и те же материалы дважды")
do
    local env, ns = fresh()
    env.items[20] = { name = "Ткань" }
    env.items[21] = { name = "Изделие A" }
    env.items[22] = { name = "Изделие B" }
    env.prices[20] = 50
    env.bags[20] = 7
    H.profession(env, "Tailoring", 225, 225, {
        H.recipe({ id = 1, name = "A", output = 21, reagents = { { itemID = 20, qty = 10 } } }),
        H.recipe({ id = 2, name = "B", output = 22, reagents = { { itemID = 20, qty = 10 } } }),
    })
    local snap = ns.CharacterScanner:Scan()
    ns.PriceProvider:BeginPass()
    ns.CraftingPlanner:Bind(ns.RecipeBook, ns.PriceProvider):BeginPass()
    local planA = ns.CraftingPlanner:Plan(ns.RecipeBook:Get(1), 1)
    local planB = ns.CraftingPlanner:Plan(ns.RecipeBook:Get(2), 1)
    H.eq(planA.needRaw[20], 3, "по отдельности совету A не хватает 3")
    H.eq(planB.needRaw[20], 3, "по отдельности совету B не хватает 3")

    ns.ShoppingList:Reset()
    ns.ShoppingList:SetInventory(snap)
    ns.ShoppingList:AddPlan(planA, "a", "A")
    ns.ShoppingList:AddPlan(planB, "b", "B")
    local lines = ns.ShoppingList:Lines()
    H.eq(#lines, 1, "в списке одна строка на ткань")
    H.eq(lines[1] and lines[1].qty, 13, "на оба совета нужно купить 13, а не 6")
    H.eq(select(1, ns.ShoppingList:Total()), 13 * 50, "сумма считается от 13 штук")
end

-- 4. The merged list says what it is -----------------------------------
H.suite("Регресс: общий список честно помечен как «если делать всё»")
do
    local env, ns = fresh()
    env.items[20] = { name = "Ткань" }
    env.prices[20] = 50
    env.bags[20] = 7
    local snap = ns.CharacterScanner:Scan()
    ns.PriceProvider:BeginPass()
    ns.ShoppingList:Reset()
    ns.ShoppingList:SetInventory(snap)
    ns.ShoppingList:Add(20, 10, "a", "A")
    ns.ShoppingList:Add(20, 10, "b", "B")
    local lines = ns.ShoppingList:Lines()
    H.eq(lines[1].qty, 13, "13 штук на два совета")
    H.eq(lines[1].gross, 20, "общая потребность 20 сохранена отдельно")
    H.eq(lines[1].have, 7, "и то, что уже есть, тоже")
    H.eq(#lines[1].uses, 2, "видно, для скольких советов это нужно")
end

-- 5. UnitCost must not depend on the order it was asked in --------------
-- X is craftable two ways: cheaply from raw W, or from Y. Y is craftable from
-- X. Asking for X first used to leave a memoised, inflated price for Y, because
-- Y was costed while the cycle guard had X temporarily forbidden.

H.suite("Регресс: UnitCost не зависит от порядка обхода")
do
    local function build()
        local env, ns = fresh()
        for _, id in ipairs({ 30, 31, 32 }) do env.items[id] = { name = "И" .. id } end
        env.prices[30] = 1000   -- X: dear to buy
        env.prices[31] = 900    -- Y: dear to buy
        env.prices[32] = 10     -- W: cheap raw
        H.profession(env, "Tailoring", 225, 225, {
            H.recipe({ id = 1, name = "X из сырья", output = 30, reagents = { { itemID = 32, qty = 1 } } }),
            H.recipe({ id = 2, name = "X из Y", output = 30, reagents = { { itemID = 31, qty = 1 } } }),
            H.recipe({ id = 3, name = "Y из X", output = 31, reagents = { { itemID = 30, qty = 1 } } }),
        })
        ns.PriceProvider:BeginPass()
        ns.CraftingPlanner:Bind(ns.RecipeBook, ns.PriceProvider):BeginPass()
        return ns
    end

    local a = build()
    a.CraftingPlanner:UnitCost(30)              -- ask X first
    local yAfterX = a.CraftingPlanner:UnitCost(31)

    local b = build()
    local yAlone = b.CraftingPlanner:UnitCost(31)   -- ask Y first

    H.eq(yAfterX, yAlone, "цена Y одинакова, в каком бы порядке ни спрашивали")
    H.eq(yAlone, 10, "и равна настоящей: Y делается из X, X — из сырья за 10")
end

-- 6. The plan has to be executable in the order it lists ---------------
-- A is made from raw, C from A, D from A and C. Any order that puts C before A
-- cannot be carried out.

H.suite("Регресс: последовательность крафта выполнима")
do
    local env, ns = fresh()
    for _, id in ipairs({ 40, 41, 42, 43 }) do env.items[id] = { name = "И" .. id } end
    env.prices[43] = 1          -- raw
    env.prices[40] = 100000     -- A: not worth buying
    env.prices[41] = 100000     -- C: not worth buying
    H.profession(env, "Tailoring", 225, 225, {
        H.recipe({ id = 1, name = "A", output = 40, reagents = { { itemID = 43, qty = 1 } } }),
        H.recipe({ id = 2, name = "C", output = 41, reagents = { { itemID = 40, qty = 1 } } }),
        H.recipe({ id = 3, name = "D", output = 42,
                   reagents = { { itemID = 40, qty = 1 }, { itemID = 41, qty = 1 } } }),
    })
    ns.PriceProvider:BeginPass()
    ns.CraftingPlanner:Bind(ns.RecipeBook, ns.PriceProvider):BeginPass()
    local plan = ns.CraftingPlanner:Plan(ns.RecipeBook:Get(3), 1, { pool = {}, bankPool = {} })

    -- Walk the list in order and check every reagent that is itself crafted
    -- here was already produced by an earlier step.
    local produced, problems = {}, {}
    for i, step in ipairs(plan.crafts) do
        for _, r in ipairs(ns.RecipeBook:MergedReagents(step.recipe)) do
            if ns.RecipeBook:CanCraft(r.itemID) and plan.decisions[r.itemID]
               and plan.decisions[r.itemID].method == "craft" then
                if not produced[r.itemID] then
                    problems[#problems + 1] = "шаг " .. i .. " («" .. step.recipe.name
                        .. "») требует " .. r.itemID .. ", который ещё не сделан"
                end
            end
        end
        produced[step.output or -1] = true
    end
    H.eq(#problems, 0, "зависимости идут раньше того, что из них делают",
        table.concat(problems, "; "))
end

-- 6b. Crafted surplus is not reported as something already in the bags --
H.suite("Регресс: излишек крафта не выдаётся за содержимое сумок")
do
    local env, ns = fresh()
    for _, id in ipairs({ 50, 51, 52, 53 }) do env.items[id] = { name = "И" .. id } end
    env.prices[53] = 5
    env.prices[51] = 100000
    env.prices[52] = 100000
    H.profession(env, "Tailoring", 225, 225, {
        H.recipe({ id = 1, name = "D", output = 50,
                   reagents = { { itemID = 51, qty = 1 }, { itemID = 52, qty = 1 } } }),
        H.recipe({ id = 2, name = "E x5", output = 51, outputQty = 5,
                   reagents = { { itemID = 53, qty = 1 } } }),
        H.recipe({ id = 3, name = "F", output = 52, reagents = { { itemID = 51, qty = 1 } } }),
    })
    ns.PriceProvider:BeginPass()
    ns.CraftingPlanner:Bind(ns.RecipeBook, ns.PriceProvider):BeginPass()
    local plan = ns.CraftingPlanner:Plan(ns.RecipeBook:Get(1), 1, { pool = {}, bankPool = {} })
    H.eq(plan.usedHere[51], nil, "ничего не списано из пустых сумок")
    H.eq(next(plan.usedHere), nil, "usedHere пуст, раз сумки были пусты")
    H.eq(plan.readiness, 0, "готовность 0: своего не было вообще")
end

-- 7. A two-hander replaces both hands ----------------------------------
H.suite("Регресс: двуручное оружие сравнивается с обеими руками")
do
    local env, ns = fresh()
    env.player.classFile = "MAGE"
    env.player.level = 60
    env.items[60] = { name = "Кинжал", equipLoc = "INVTYPE_WEAPONMAINHAND", classID = 2, subclassID = 15 }
    env.stats[60] = { ITEM_MOD_INTELLECT_SHORT = 4 }
    env.items[61] = { name = "Книга", equipLoc = "INVTYPE_HOLDABLE", classID = 4, subclassID = 0 }
    env.stats[61] = { ITEM_MOD_INTELLECT_SHORT = 10 }
    env.items[62] = { name = "Посох", equipLoc = "INVTYPE_2HWEAPON", classID = 2, subclassID = 10 }
    env.stats[62] = { ITEM_MOD_INTELLECT_SHORT = 6 }
    env.items[63] = { name = "Дерево" }
    env.prices[63] = 10
    env.equipped.MAINHAND = { itemID = 60 }
    env.equipped.OFFHAND = { itemID = 61 }
    H.profession(env, "Tailoring", 225, 225, {
        H.recipe({ id = 1, name = "Посох", output = 62, reagents = { { itemID = 63, qty = 1 } } }),
    })
    local snap = ns.CharacterScanner:Scan()
    ns.PriceProvider:BeginPass()
    ns.CraftingPlanner:Bind(ns.RecipeBook, ns.PriceProvider):BeginPass()
    ns.GearAdvisor:BeginPass()
    local ups = ns.GearAdvisor:Upgrades(snap, ns.CraftingPlanner)
    H.eq(#ups, 0, "посох на 6 не улучшение против связки 4+10=14")

    -- And when the two-hander really is better, it is still offered.
    env.stats[62] = { ITEM_MOD_INTELLECT_SHORT = 20 }
    H.itemsChanged(env)   -- the item's data changed; in game that is an event
    ns.GearAdvisor:BeginPass()
    local ups2 = ns.GearAdvisor:Upgrades(snap, ns.CraftingPlanner)
    H.eq(#ups2, 1, "посох на 20 — улучшение, он предложен")
    H.near(ups2[1] and ups2[1].gain, 6, 0.001, "прирост считается как 20 - 14 = 6")
end

-- 8/9. Enchants are matched to the item, not to a slot name -----------
H.suite("Регресс: чары двуручного находят посох в правой руке")
do
    local env, ns = fresh()
    env.player.classFile = "MAGE"
    env.categories = { [1] = { name = "Чары для двуручного оружия" } }
    env.items[70] = { name = "Пыль" }
    env.prices[70] = 100
    env.bags[70] = 5
    env.items[71] = { name = "Посох без чар", equipLoc = "INVTYPE_2HWEAPON" }
    env.equipped.MAINHAND = { itemID = 71 }
    H.profession(env, "Enchanting", 225, 225, {
        H.recipe({ id = 1, name = "Чары для двуручного оружия - интеллект",
                   output = nil, categoryID = 1, category = "Чары для двуручного оружия",
                   reagents = { { itemID = 70, qty = 1 } } }),
    })
    local snap = ns.CharacterScanner:Scan()
    ns.PriceProvider:BeginPass()
    ns.CraftingPlanner:Bind(ns.RecipeBook, ns.PriceProvider):BeginPass()
    local sugg = ns.EnchantAdvisor:Suggestions(snap, ns.CraftingPlanner)
    H.eq(#sugg, 1, "формула на двуручное предложена для посоха")
    H.eq(sugg[1] and sugg[1].slot, "MAINHAND", "предложение привязано к слоту правой руки")
    H.eq(#ns.EnchantAdvisor:BareWithoutFormula(snap), 0,
        "и карточки «формул на этот слот нет» больше не появляется")
end

H.suite("Регресс: чары щита не предлагаются на книгу в левой руке")
do
    local env, ns = fresh()
    env.player.classFile = "MAGE"
    env.categories = { [1] = { name = "Чары для щита" } }
    env.items[80] = { name = "Пыль" }
    env.prices[80] = 100
    env.bags[80] = 5
    env.items[81] = { name = "Книга", equipLoc = "INVTYPE_HOLDABLE" }
    env.equipped.OFFHAND = { itemID = 81 }
    H.profession(env, "Enchanting", 225, 225, {
        H.recipe({ id = 1, name = "Чары для щита - блок", output = nil, categoryID = 1,
                   category = "Чары для щита", reagents = { { itemID = 80, qty = 1 } } }),
    })
    local snap = ns.CharacterScanner:Scan()
    ns.PriceProvider:BeginPass()
    ns.CraftingPlanner:Bind(ns.RecipeBook, ns.PriceProvider):BeginPass()
    local sugg = ns.EnchantAdvisor:Suggestions(snap, ns.CraftingPlanner)
    H.eq(#sugg, 0, "на книгу чары щита не предлагаются")

    -- With a real shield in the slot the same formula does apply.
    env.items[82] = { name = "Щит", equipLoc = "INVTYPE_SHIELD" }
    env.equipped.OFFHAND = { itemID = 82 }
    local snap2 = ns.CharacterScanner:Scan()
    local sugg2 = ns.EnchantAdvisor:Suggestions(snap2, ns.CraftingPlanner)
    H.eq(#sugg2, 1, "на щит — предлагаются")
end

-- 9b. Spell power is not read as strength ------------------------------
H.suite("Регресс: «сила магии» в названии формулы — не «сила»")
do
    local _, ns = fresh()
    local w = ns.StatWeights:Set("CASTER_DPS")
    local sp = ns.StatWeights:TextUsefulness("Чары для оружия - малая сила магии", w)
    local str = ns.StatWeights:TextUsefulness("Чары для наручей - сила", w)
    -- Reading a stat out of a NAME and reading a number out of the client are
    -- two different jobs, and they used to share one table. "+N spell power"
    -- as a NUMBER is two stats (damage and healing); as a WORD on an enchant it
    -- means spell damage, which is what a caster gets from it.
    H.near(sp, w[ns.STAT.SPELLDMG], 0.001, "«сила магии» оценена как урон от магии (" .. tostring(sp) .. ")")
    H.near(str, w[ns.STAT.STR], 0.001, "«сила» по-прежнему оценена как сила")
    H.ok(sp > str, "и для мага сила магии ценнее силы")
    local stats = ns.StatWeights:StatsInText("Чары для оружия - малая сила магии")
    H.ok(stats and stats[ns.STAT.SPELLDMG], "сила магии распознана как урон от магии")
end

-- 10. Another character's recipe cache is not ours ---------------------
H.suite("Регресс: кеш чужого персонажа не выдаётся за свой")
do
    local env, ns = fresh()
    -- The production adapter, not the harness stand-in: this is exactly the
    -- real account's shape - two characters, one of them with recipes cached.
    local real = env.real.MastercraftRecipes
    local db = {
        recipes = {
            ["Player-ЧУЖОЙ"] = { Tailoring = { list = {
                H.recipe({ id = 1, name = "Чужой рецепт", output = 5 }) } } },
        },
        chars = { ["Player-ЧУЖОЙ"] = { name = "Альт" },
                  ["Player-МОЙ"] = { name = "Я" } },
    }
    function ns.Api:MastercraftDB() return db end
    local got, used, why = real(ns.Api, "Player-МОЙ")
    H.eq(got, nil, "рецепты чужого GUID не отданы")
    H.eq(used, nil, "и GUID не подменён")
    H.ok(type(why) == "string", "причина записана: " .. tostring(why))

    local mine, usedMine = real(ns.Api, "Player-ЧУЖОЙ")
    H.ok(mine ~= nil, "свой GUID по-прежнему читается")
    H.eq(usedMine, "Player-ЧУЖОЙ", "и возвращается как есть")

    local none, _, noneWhy = real(ns.Api, nil)
    H.eq(none, nil, "без GUID чужой кеш не читается вообще")
    H.ok(type(noneWhy) == "string", "и это тоже объяснено")
end

-- 11. Logging out closes the diagnostics session ------------------------
H.suite("Регресс: PLAYER_LOGOUT закрывает сессию диагностики")
do
    local env, ns = fresh()
    -- Events takes over the frame's OnEvent script. Before the fix that threw
    -- away PLAYER_LOGOUT, and the session was never stamped as finished.
    local seen, registered = {}, {}
    local fakeFrame = {
        RegisterEvent = function(_, event) registered[event] = true end,
        SetScript = function(_, which, fn) seen[which] = fn end,
    }
    local ownerSaw = {}
    ns.Events:Init(fakeFrame, function(event, arg1)
        ownerSaw[event] = arg1 or true
    end)
    H.ok(type(seen.OnEvent) == "function", "Events поставил обработчик OnEvent")
    H.eq(registered.PLAYER_LOGOUT, true, "и подписался на PLAYER_LOGOUT")
    H.eq(registered.ADDON_LOADED, true, "и на ADDON_LOADED")
    H.eq(registered.PLAYER_LOGIN, true, "и на PLAYER_LOGIN")

    seen.OnEvent(nil, "PLAYER_LOGOUT")
    H.ok(ownerSaw.PLAYER_LOGOUT ~= nil, "PLAYER_LOGOUT дошёл до обработчика загрузчика")
    seen.OnEvent(nil, "ADDON_LOADED", "ForeverPilot")
    H.eq(ownerSaw.ADDON_LOADED, "ForeverPilot", "ADDON_LOADED дошёл вместе с аргументом")

    -- And with nobody claiming the event the session is still closed, because
    -- logout is the one moment that does not come round again.
    local env2, ns2 = fresh()
    local seen2 = {}
    ns2.Events:Init({
        RegisterEvent = function() end,
        SetScript = function(_, which, fn) seen2[which] = fn end,
    })
    local finished = false
    local realFinish = ns2.Diag.Finish
    ns2.Diag.Finish = function(self) finished = true; return realFinish(self) end
    seen2.OnEvent(nil, "PLAYER_LOGOUT")
    ns2.Diag.Finish = realFinish
    H.eq(finished, true, "без владельца события сессия всё равно закрывается")

    -- Ordinary events still reach the scheduler.
    local env3, ns3 = fresh()
    local seen3 = {}
    ns3.Events:Init({
        RegisterEvent = function() end,
        SetScript = function(_, which, fn) seen3[which] = fn end,
    }, function() end)
    seen3.OnEvent(nil, "BAG_UPDATE_DELAYED")
    H.eq(ns3.Events:IsDirty("bags"), true, "обычные события по-прежнему идут планировщику")
end

-- 12. Per-item profit and per-craft profit are different numbers -------
H.suite("Регресс: прибыль за штуку и за крафт разведены")
do
    local env, ns = fresh()
    env.items[90] = { name = "Реагент" }
    env.items[91] = { name = "Изделие" }
    env.prices[90] = 25        -- 5 reagents x 25 = 125 per craft
    env.prices[91] = 100       -- sells for 100, minus the 5% cut = 95
    H.profession(env, "Tailoring", 225, 225, {
        H.recipe({ id = 1, name = "Пять за раз", output = 91, outputQty = 5,
                   reagents = { { itemID = 90, qty = 5 } } }),
    })
    ns.PriceProvider:BeginPass()
    ns.CraftingPlanner:Bind(ns.RecipeBook, ns.PriceProvider):BeginPass()
    local recipe = ns.RecipeBook:Get(1)
    local margin, conf, revenue, cost, craft = ns.CraftingPlanner:Margin(recipe)
    H.near(cost, 25, 0.001, "себестоимость одной штуки — 25 (125 / 5)")
    H.near(revenue, 95, 0.001, "выручка за штуку — 95")
    H.near(margin, 70, 0.001, "прибыль за штуку — 70")
    H.ok(type(craft) == "table", "вторая величина отдана отдельной таблицей")
    H.near(craft and craft.margin, 350, 0.001, "прибыль за один крафт — 350 (70 x 5)")
    H.near(craft and craft.cost, 125, 0.001, "материалы на крафт — 125")
    H.near(craft and craft.revenue, 475, 0.001, "выручка с крафта — 475")
    H.eq(craft and craft.outputQty, 5, "выход за крафт — 5 штук")
end

-- 13. BeginPass clears the truncation flag -----------------------------
H.suite("Регресс: BeginPass сбрасывает признак обрезанного дерева")
do
    local env, ns = fresh()
    env.items[100] = { name = "Изделие" }
    env.items[101] = { name = "Реагент" }
    env.prices[101] = 10
    H.profession(env, "Tailoring", 225, 225, {
        H.recipe({ id = 1, name = "Простое", output = 100, reagents = { { itemID = 101, qty = 1 } } }),
    })
    ns.PriceProvider:BeginPass()
    local P = ns.CraftingPlanner:Bind(ns.RecipeBook, ns.PriceProvider)
    P:BeginPass()
    P.truncated = true                   -- as if a huge plan had been cut
    P:BeginPass()
    H.ok(not P.truncated, "флаг снят новым проходом")
    local plan = P:Plan(ns.RecipeBook:Get(1), 1)
    H.eq(plan.truncated, false, "и следующий план не помечен обрезанным")
end

-- 14. A vendor's offer and a market estimate are not the same thing ----
H.suite("Регресс: цена продажи торговцу и рыночная оценка не смешиваются")
do
    local env, ns = fresh()
    env.auctionator = false
    env.items[110] = { name = "Ткань", sellPrice = 10 }
    env.observedPrices = { [110] = 1000 }
    ns.PriceProvider:BeginPass()
    local copper, conf, src = ns.PriceProvider:Sell(110)
    H.ok(copper and copper > 10, "рыночная оценка 1000 не подменяется десятком торговца ("
        .. tostring(copper) .. ")")
    H.eq(src, "foreign", "и помечена как наблюдение, а не как цена торговца")
    H.ok(conf ~= ns.CONF.EXACT, "неподтверждённая рыночная цена не выдаётся за точную")

    local guaranteed, gConf = ns.PriceProvider:VendorSell(110)
    H.eq(guaranteed, 10, "гарантированная цена торговца доступна отдельно")
    H.eq(gConf, ns.CONF.EXACT, "и она действительно точная")
end

-- 15. Unbuyable lines must not eat the card limit ----------------------
H.suite("Регресс: недоступные покупки не занимают лимит карточек")
do
    local env, ns = fresh()
    env.money = 10000000
    env.player.level = 26
    -- Four expensive drop-only items (price only as a markup guess -> not
    -- buyable) plus one cheap item with a real listing.
    for i = 1, 4 do
        env.items[120 + i] = { name = "Добыча " .. i, sellPrice = 100000 }
    end
    env.items[130] = { name = "Ткань с аукциона" }
    env.prices[130] = 500
    ns.PriceProvider:BeginPass()
    ns.ShoppingList:Reset()
    for i = 1, 4 do
        ns.ShoppingList:Add(120 + i, 1, "c" .. i, "Совет " .. i)
    end
    ns.ShoppingList:Add(130, 2, "c5", "Совет 5")
    ns.ActionEngine.cards = {}
    local added = ns.ActionEngine:AddBuyCards({ money = env.money },
        ns.ActionEngine:Scales({ money = env.money }))
    H.eq(added, 1, "одна карточка покупки построена, а не ноль")
    H.ok(ns.ActionEngine.cards[1] and ns.ActionEngine.cards[1].itemID == 130,
        "и это именно доступная позиция")
end

-- 16. A recipe on cooldown is not available right now ------------------
H.suite("Регресс: рецепт на перезарядке не считается доступным сейчас")
do
    local env, ns = fresh()
    env.items[140] = { name = "Реагент" }
    env.items[141] = { name = "Суточное изделие" }
    env.prices[140] = 10
    env.prices[141] = 100000
    env.bags[140] = 10
    H.profession(env, "Tailoring", 225, 225, {
        H.recipe({ id = 1, name = "Раз в сутки", output = 141, diff = "optimal",
                   reagents = { { itemID = 140, qty = 1 } } }),
    })
    local recipe = ns.RecipeBook:Get(1)
    recipe.cooldown = 3600      -- an hour left
    ns.CharacterScanner:Scan()
    ns.PriceProvider:BeginPass()
    ns.CraftingPlanner:Bind(ns.RecipeBook, ns.PriceProvider):BeginPass()
    H.eq(ns.CraftingPlanner:OnCooldown(recipe), true, "планировщик видит перезарядку")
    H.eq(ns.CraftingPlanner:MaxCraftableNow(recipe), 0,
        "«можно сделать сейчас» — ноль, пока идёт перезарядка")
    local plan = ns.CraftingPlanner:Plan(recipe, 1)
    H.eq(plan.cooldown, 3600, "план знает, сколько ждать")
    H.eq(plan.ready, false, "и не считается готовым к исполнению")
    recipe.cooldown = 0
    H.eq(ns.CraftingPlanner:OnCooldown(recipe), false, "без перезарядки всё как было")
    H.ok(ns.CraftingPlanner:MaxCraftableNow(recipe) > 0, "и сделать снова можно")
end

-- 17. The bank: no double counting, and silence is not zero ------------
H.suite("Регресс: банк не дублирует сумки и отличает «нет данных» от нуля")
do
    local env, ns = fresh()
    local realBank = env.real.BankCounts
    -- A client that hands back bank "tabs" numbered like the player's own bags.
    local reads = {}
    local slots = {
        [0] = 16, [1] = 16, [2] = 16, [3] = 16, [4] = 16,   -- the player's bags
        [-1] = 24, [5] = 12,                                 -- real bank space
    }
    local contents = {
        [0] = { { itemID = 999, stackCount = 5 } },
        [1] = { { itemID = 999, stackCount = 5 } },
        [-1] = { { itemID = 500, stackCount = 2 } },
        [5] = { { itemID = 501, stackCount = 3 } },
    }
    ns.Api.has.bagNumSlots, ns.Api.has.bagItemInfo, ns.Api.has.bankTabs = true, true, true
    ns.Api:InjectBankFakes({
        numSlots = function(bag) reads[bag] = (reads[bag] or 0) + 1; return slots[bag] end,
        itemInfo = function(bag, slot) return (contents[bag] or {})[slot] end,
        tabs = function() return { { ID = 1 }, { ID = 2 }, { ID = 5 } } end,
        playerBags = { [0] = true, [1] = true, [2] = true, [3] = true, [4] = true },
    })
    local counts, conf = realBank(ns.Api)
    H.ok(counts ~= nil, "банк прочитан")
    H.eq(counts and counts[999], nil, "содержимое сумок персонажа в банк не попало")
    H.eq(counts and counts[500], 2, "настоящий банковский контейнер прочитан")
    H.eq(counts and counts[501], 3, "банковская сумка прочитана")
    H.eq(conf, ns.CONF.EXACT, "данные помечены как точные")

    -- Nothing readable at all is UNKNOWN, not an empty bank.
    ns.Api:InjectBankFakes({
        numSlots = function() return 0 end,
        itemInfo = function() return nil end,
        tabs = function() return {} end,
        playerBags = {},
    })
    local none, noneConf = realBank(ns.Api)
    H.eq(none, nil, "банк, который не открывали, — не пустой банк, а неизвестность")
    H.eq(noneConf, ns.CONF.UNKNOWN, "и помечен как неизвестный")
    ns.Api:InjectBankFakes(nil)
end

-- 18. One profession's trainer is not every profession's trainer -------
H.suite("Регресс: тренер одной профессии не привязывается ко всем")
do
    local env, ns = fresh()
    env.npcUnit = { id = 555, name = "Портной-наставник" }
    env.playerMap = { mapID = 1, x = 0.4, y = 0.6, zone = "Оргриммар" }
    ns.Places:RecordTrainer({ "Tailoring", "Enchanting", "Cooking" })
    local tailoring = ns.Places:ForTrainer("Tailoring")
    local enchanting = ns.Places:ForTrainer("Enchanting")
    H.eq(tailoring, nil, "при трёх возможных профессиях тренер ни к одной не привязан")
    H.eq(enchanting, nil, "и ко второй тоже")
    local any = ns.Places:AnyTrainer()
    H.ok(any ~= nil, "но сам NPC записан как тренер без профессии")
    H.eq(any and any.professionKnown, false, "и помечен как «профессия не определена»")

    -- With a single crafting profession the attribution is safe.
    local env2, ns2 = fresh()
    env2.npcUnit = { id = 556, name = "Портной" }
    env2.playerMap = { mapID = 1, x = 0.4, y = 0.6, zone = "Оргриммар" }
    ns2.Places:RecordTrainer({ "Tailoring" })
    H.ok(ns2.Places:ForTrainer("Tailoring") ~= nil,
        "одна профессия — привязка однозначна и сохраняется")
end

-- 19. Truncation counts characters, not bytes --------------------------
H.suite("Регресс: обрезка строк считает символы, а не байты")
do
    local _, ns = fresh()
    local U = ns.Util
    H.eq(U.truncate("HelloWorld", 4), "Hell…", "латиница: 4 символа")
    H.eq(U.truncate("ПриветМир", 4), "Прив…", "кириллица: 4 символа, а не 2")
    H.eq(U.truncate("Привет", 6), "Привет", "строка ровно в лимит не трогается")
    H.eq(U.truncate("Привет", 10), "Привет", "короткая строка не трогается")
    H.eq(U.truncate("", 4), "", "пустая строка остаётся пустой")
    H.eq(U.truncate("абв🙂гд", 4), "абв🙂…", "четырёхбайтовый символ не разрезается")
    H.eq(U.charLen("ПриветМир"), 9, "длина в символах считается правильно")
end

-- 20. Incomplete reagent data is not presented as an exact cost --------
H.suite("Регресс: неполные сведения о реагентах не дают точной стоимости")
do
    local env, ns = fresh()
    env.openProfession = "Tailoring"
    env.openRecipeIDs = { 1 }
    env.readRecipe = function(id)
        return {
            id = id, name = "Рецепт с выбором реагента", learned = true,
            output = 150, outputQty = 1,
            -- One basic slot that accepts either of two items: we only read the
            -- first, so the cost we compute cannot be called exact.
            reagents = { { itemID = 151, qty = 2 } },
            reagentChoices = 2,
            conf = ns.CONF.EXACT,
        }
    end
    env.items[150] = { name = "Изделие" }
    env.items[151] = { name = "Реагент A" }
    env.prices[151] = 100
    ns.RecipeBook:Store("Tailoring", { env.readRecipe(1) }, "own", ns.CONF.EXACT, 0)
    ns.RecipeBook:Reindex()
    local recipe = ns.RecipeBook:Get(1)
    H.eq(recipe.reagentChoices, 2, "факт выбора реагентов сохранён")
    ns.PriceProvider:BeginPass()
    ns.CraftingPlanner:Bind(ns.RecipeBook, ns.PriceProvider):BeginPass()
    local cost, conf = ns.CraftingPlanner:RecipeMaterialCost(recipe, 0, {})
    H.eq(cost, 200, "стоимость всё равно считается")
    H.eq(conf, ns.CONF.ESTIMATE, "но помечена как оценка, а не как точное значение")
end

-- 21. The gear branch says where the data went -------------------------
H.suite("Регресс: ветка экипировки честно отчитывается, где потерялись данные")
do
    local env, ns = fresh()
    env.player.level = 26
    env.player.classFile = "MAGE"
    env.items[160] = { name = "Со статами", equipLoc = "INVTYPE_HEAD", reqLevel = 10,
                       classID = 4, subclassID = 1 }
    env.stats[160] = { ITEM_MOD_INTELLECT_SHORT = 10 }
    env.items[161] = { name = "Без статов", equipLoc = "INVTYPE_HEAD", reqLevel = 10,
                       classID = 4, subclassID = 1 }
    env.items[162] = { name = "Не по уровню", equipLoc = "INVTYPE_CHEST", reqLevel = 50,
                       classID = 4, subclassID = 1 }
    env.items[164] = { name = "Еда", equipLoc = "" }
    env.items[170] = { name = "Ткань" }
    env.prices[170] = 100
    local recs = {}
    for i, out in ipairs({ 160, 161, 162, 163, 164 }) do
        recs[i] = H.recipe({ id = 200 + i, name = "Рецепт " .. out, output = out,
                             reagents = { { itemID = 170, qty = 1 } } })
    end
    H.profession(env, "Tailoring", 225, 225, recs)
    local snap = ns.CharacterScanner:Scan()
    ns.GearAdvisor:BeginPass()
    local wearable, unwearable, stats = ns.GearAdvisor:Candidates(snap)
    H.eq(type(stats), "table", "Candidates отдаёт разбор, а не одно число")
    H.eq(stats.pending, 1, "один предмет ещё не в кеше клиента")
    H.eq(stats.notGear, 1, "один рецепт делает не экипировку")
    H.eq(#unwearable, 1, "один предмет не по уровню — он в ветке на продажу")
    H.eq(#wearable, 2, "два надеваемых кандидата")
    H.eq(stats.noStats, 1, "и у одного из них характеристик нет")
end

-- 21b. A readable candidate is not thrown away because the worn item is not
H.suite("Регресс: нечитаемая надетая вещь не убивает совет по экипировке")
do
    local env, ns = fresh()
    env.player.level = 26
    env.player.classFile = "MAGE"
    env.items[180] = { name = "Новая шапка", equipLoc = "INVTYPE_HEAD", reqLevel = 10,
                       classID = 4, subclassID = 1 }
    env.stats[180] = { ITEM_MOD_INTELLECT_SHORT = 12 }
    env.items[181] = { name = "Старая шапка", equipLoc = "INVTYPE_HEAD" }
    -- no env.stats[181]: the client will not tell us what the worn item does
    env.equipped.HEAD = { itemID = 181 }
    env.items[182] = { name = "Ткань" }
    env.prices[182] = 100
    H.profession(env, "Tailoring", 225, 225, {
        H.recipe({ id = 1, name = "Новая шапка", output = 180,
                   reagents = { { itemID = 182, qty = 1 } } }),
    })
    local snap = ns.CharacterScanner:Scan()
    ns.PriceProvider:BeginPass()
    ns.CraftingPlanner:Bind(ns.RecipeBook, ns.PriceProvider):BeginPass()
    ns.GearAdvisor:BeginPass()
    local ups = ns.GearAdvisor:Upgrades(snap, ns.CraftingPlanner)
    H.eq(#ups, 1, "совет не выброшен только потому, что надетое не читается")
    local up = ups[1]
    H.eq(up and up.compare, "unknown", "сравнение помечено как невозможное")
    H.eq(up and up.gain, nil, "никакого придуманного прироста не заявлено")
    H.near(up and up.newScore, 12, 0.001, "известна только ценность самой вещи")
    H.eq(up and up.conf, ns.CONF.UNKNOWN, "и достоверность — неизвестно")

    -- With no stats on either side there is still nothing to say.
    env.stats[180] = nil
    H.itemsChanged(env)   -- the item's data changed; in game that is an event
    ns.GearAdvisor:BeginPass()
    H.eq(#ns.GearAdvisor:Upgrades(snap, ns.CraftingPlanner), 0,
        "без характеристик вообще ничего не предлагается")
end

-- 22. No infinities leak out of the gear branch ------------------------
H.suite("Регресс: бесконечность не попадает в расчёт пользы на золото")
do
    local env, ns = fresh()
    env.player.level = 26
    env.player.classFile = "MAGE"
    env.items[190] = { name = "Шапка", equipLoc = "INVTYPE_HEAD", reqLevel = 1,
                       classID = 4, subclassID = 1 }
    env.stats[190] = { ITEM_MOD_INTELLECT_SHORT = 10 }
    env.items[191] = { name = "Ткань" }
    env.prices[191] = 100
    env.bags[191] = 10                       -- everything already in the bags
    H.profession(env, "Tailoring", 225, 225, {
        H.recipe({ id = 1, name = "Шапка", output = 190, reagents = { { itemID = 191, qty = 1 } } }),
    })
    local snap = ns.CharacterScanner:Scan()
    ns.PriceProvider:BeginPass()
    ns.CraftingPlanner:Bind(ns.RecipeBook, ns.PriceProvider):BeginPass()
    ns.GearAdvisor:BeginPass()
    local ups = ns.GearAdvisor:Upgrades(snap, ns.CraftingPlanner)
    H.eq(#ups, 1, "улучшение найдено")
    local g = ups[1].gainPerGold
    H.ok(g == nil or (g == g and g ~= math.huge and g ~= -math.huge),
        "польза на золото не бесконечна и не nan: " .. tostring(g))
    H.eq(ups[1].free, true, "вместо бесконечности стоит честный признак «бесплатно»")
end

-- 23. A price learned later is picked up -------------------------------
H.suite("Регресс: цена, узнанная позже, попадает в список покупок")
do
    local env, ns = fresh()
    env.items[200] = { name = "Пыль" }
    ns.PriceProvider:BeginPass()
    ns.ShoppingList:Reset()
    ns.ShoppingList:Add(200, 2, "c1", "Карточка 1",
        { unit = nil, conf = ns.CONF.UNKNOWN, buyable = false })
    ns.ShoppingList:Add(200, 3, "c2", "Карточка 2",
        { unit = 700, conf = ns.CONF.CACHED, src = "auctionator", buyable = true })
    local line = ns.ShoppingList:Lines()[1]
    H.eq(line.qty, 5, "количества сложились")
    H.eq(line.unit, 700, "цена подхвачена из второй карточки")
    H.eq(line.subtotal, 3500, "и сумма посчитана")
    H.eq(line.buyable, true, "позиция признана покупаемой")
    H.eq(select(3, ns.ShoppingList:Total()), 0, "строк без цены не осталось")
end

-- 24. Affordability does not claim "you can afford it" without prices --
H.suite("Регресс: без цен список не объявляется посильным")
do
    local env, ns = fresh()
    env.items[210] = { name = "Без цены" }
    ns.PriceProvider:BeginPass()
    ns.ShoppingList:Reset()
    ns.ShoppingList:Add(210, 40, "c", "Карточка",
        { unit = nil, conf = ns.CONF.UNKNOWN, buyable = false })
    local a = ns.ShoppingList:Affordability({ money = 100 })
    H.eq(a.unknownLines, 1, "строка без цены учтена")
    H.eq(a.affordable, nil, "вывод «хватает» не делается")
    H.eq(a.withinCap, nil, "и про лимит траты тоже")

    ns.ShoppingList:Reset()
    ns.ShoppingList:Add(210, 2, "c", "Карточка",
        { unit = 10, conf = ns.CONF.CACHED, buyable = true })
    local b = ns.ShoppingList:Affordability({ money = 100 })
    H.eq(b.affordable, true, "когда все цены известны — вывод делается как раньше")
end

-- 25. Advice that loses money does not outrank advice that does not ----
H.suite("Регресс: убыточный совет не поднимается наверх")
do
    local env, ns = fresh()
    env.money = 100
    env.player.level = 26
    env.player.classFile = "MAGE"
    env.items[220] = { name = "Дорогая пыль" }
    env.prices[220] = 300000
    env.items[221] = { name = "Дешёвый итог" }
    env.prices[221] = 100
    H.profession(env, "Tailoring", 100, 300, {
        H.recipe({ id = 1, name = "Убыточный крафт", output = 221, diff = "optimal",
                   reagents = { { itemID = 220, qty = 1 } } }),
    })
    ns.Config:SetProfile("THRIFT")
    local cards = H.build(env)
    H.ok(#cards > 0, #cards .. " карточек построено")
    H.ok((cards[1] and cards[1].score or 0) >= 0,
        "первая карточка не с отрицательной оценкой",
        "score = " .. tostring(cards[1] and cards[1].score))

    -- A negative card is allowed to exist - "buying this would cost 30 gold" is
    -- a fact worth knowing - but it must sit below everything non-negative, and
    -- it must be marked so the UI never dresses it up as a recommendation.
    local firstNegative, lastNonNegative
    for i, card in ipairs(cards) do
        if (card.score or 0) < 0 then
            if not firstNegative then firstNegative = i end
            H.ok(card.unaffordable or card.losesMoney,
                "убыточная карточка №" .. i .. " помечена как таковая")
        else
            lastNonNegative = i
        end
    end
    if firstNegative and lastNonNegative then
        H.ok(firstNegative > lastNonNegative,
            "все убыточные советы ниже всех остальных",
            "первый убыточный №" .. firstNegative
            .. ", последний нормальный №" .. lastNonNegative)
    else
        H.ok(true, "сравнивать нечего")
    end
end

-- 26. An information card does not outrank a real action ---------------
H.suite("Регресс: справочная карточка не вытесняет настоящий совет")
do
    local env, ns = fresh()
    env.money = 25000
    env.player.level = 26
    env.player.classFile = "MAGE"
    env.items[230] = { name = "Шёлк" }
    env.prices[230] = 100
    env.items[231] = { name = "Шёлковый пояс" }
    env.prices[231] = 50000
    env.bags[230] = 10
    -- A capped profession: the engine adds its "go and see a trainer" card.
    H.profession(env, "Tailoring", 225, 225, {
        H.recipe({ id = 1, name = "Шёлковый пояс", output = 231, diff = "optimal",
                   reagents = { { itemID = 230, qty = 3 } } }),
    })
    for _, profile in ipairs(ns.PROFILE_ORDER) do
        ns.Config:SetProfile(profile)
        local cards = H.build(env)
        local firstReal, firstInfo
        for i, card in ipairs(cards) do
            if card.benefitValue and card.benefitValue > 0 and not firstReal then firstReal = i end
            if card.informational and not firstInfo then firstInfo = i end
        end
        if firstInfo and firstReal then
            H.ok(firstReal < firstInfo,
                ns.PROFILE_LABEL[profile] .. ": настоящий совет выше справочного",
                "настоящий №" .. firstReal .. ", справочный №" .. firstInfo)
        else
            H.ok(firstReal ~= nil, ns.PROFILE_LABEL[profile] .. ": настоящий совет в списке есть")
        end
    end
end

-- 27. nan never reaches the sort --------------------------------------
H.suite("Регресс: nan в оценке не ломает сортировку")
do
    local _, ns = fresh()
    local list = {}
    for i = 1, 20 do
        list[i] = { s = (i % 2 == 0) and (0 / 0) or i }
    end
    local ok, out = pcall(ns.Util.stableSortBy, list, function(x) return x.s end, true)
    H.eq(ok, true, "сортировка не падает", tostring(out))
    H.eq(type(out) == "table" and #out, 20, "ни один элемент не потерян")
    local first = out and out[1]
    H.ok(first and first.s == first.s, "наверху не nan, а настоящее число")
end

-- 27b. Small helpers that the fixes lean on --------------------------
H.suite("Регресс: мелкие помощники не врут о достоверности")
do
    local _, ns = fresh()
    local U = ns.Util
    H.eq(U.worstConf(), ns.CONF.UNKNOWN, "без данных достоверность «неизвестно», а не «точно»")
    H.eq(U.worstConf(nil, nil), ns.CONF.UNKNOWN, "и с одними nil тоже")
    H.eq(U.worstConf(ns.CONF.EXACT, ns.CONF.ESTIMATE), ns.CONF.ESTIMATE,
        "худшее из нескольких по-прежнему выбирается")
    H.eq(U.worstConf(ns.CONF.CACHED), ns.CONF.CACHED, "одно значение проходит как есть")

    H.eq(U.capitalize("материалы"), "Материалы", "кириллица поднимается в верхний регистр")
    H.eq(U.capitalize("hello"), "Hello", "латиница тоже")
    H.eq(U.capitalize(""), "", "пустая строка не ломает")
    H.ok(U.durationText(3600) ~= nil, "длительность переводится в текст: "
        .. tostring(U.durationText(3600)))
    H.eq(U.durationText(0), nil, "нулевая длительность — ничего")
end

H.suite("Регресс: видно, из каких источников бралась цена")
do
    local env, ns = fresh()
    env.items[240] = { name = "Ткань" }
    env.prices[240] = 500
    ns.Config:RememberVendorPrice(240, 120)
    ns.PriceProvider:BeginPass()
    local copper, _, src = ns.PriceProvider:Buy(240)
    H.eq(copper, 120, "выбран дешёвый источник")
    H.eq(src, "vendor", "и это торговец")
    local routes = ns.PriceProvider:Routes(240)
    H.ok(#routes >= 2, #routes .. " источника сохранено для объяснения")
    H.eq(routes[1] and routes[1].copper, 120, "дешёвый первым")
    H.ok(routes[2] and routes[2].copper == 500, "дорогой тоже виден")
end

-- 28. The addon compartment entry point is declared --------------------
H.suite("Регресс: точка входа меню аддонов объявлена в .toc")
do
    local path = H.ROOT .. "/ForeverPilot.toc"
    local f = io.open(path, "r")
    H.ok(f ~= nil, "файл .toc читается")
    if f then
        local text = f:read("*a")
        f:close()
        H.ok(text:find("AddonCompartmentFunc", 1, true) ~= nil,
            "## AddonCompartmentFunc прописан")
        H.ok(text:find("ForeverPilot_OnAddonCompartmentClick", 1, true) ~= nil,
            "и указывает на существующую функцию")
    end
end

-- 29. Скрытые карточки не оставляют список пустым ----------------------
--
-- Это ровно ситуация игрока из FOREVERPILOT_DIAG: четыре профессии 225/225,
-- 265 выученных рецептов, 4з 91с в кошельке, Auctionator на месте,
-- характеристики предметов читаются. Ветки советов РАБОТАЛИ - диагностика
-- записала gear=4, enchant=0, profit=8, skill=1 - а generated вышел 0,
-- потому что все ключи этих карточек лежали в ForeverPilotDB.dismissed
-- (21 запись, поставлены правым щелчком и кнопкой «Понятно» сутками раньше).
-- Движок молча выбрасывал каждую карточку и сообщал «ни одна ветка советов
-- ничего не выдала», что неправда.
--
-- Инварианта: советующий аддон не может быть опустошён собственной кнопкой
-- «скрыть». Если скрыто всё, он обязан сказать об этом и дать способ вернуть.

-- Мир игрока, воспроизведённый по диагностике: 4 профессии на потолке,
-- 265 выученных рецептов, 4з 91с 35м, цены есть, статы читаются.
local function playerWorld(env, ns)
    env.player.name = "Гендольф"
    env.player.level = 26
    env.player.classFile = "MAGE"
    env.player.className = "Маг"
    env.money = 49135            -- 4з 91с 35м, как в статусной строке
    env.auctionator = true

    -- Реагенты с ценами аукциона.
    H.item(env, 4339, { name = "Магическая ткань", sellPrice = 300 })
    H.item(env, 14047, { name = "Рунная ткань", sellPrice = 500 })
    H.item(env, 11137, { name = "Магическая пыль", sellPrice = 120 })
    env.prices[4339] = 1200
    env.prices[14047] = 2155
    env.prices[11137] = 900
    env.bags[4339] = 40
    env.bags[14047] = 20
    env.bags[11137] = 6
    env.bank = {}

    -- Надетое и улучшение к нему: статы читаются, как в игре.
    H.item(env, 7054, { name = "Мерцающий посох", equipLoc = "INVTYPE_2HWEAPON",
        reqLevel = 24, classID = 2, subclassID = 10, sellPrice = 4000 })
    H.item(env, 9000, { name = "Старая мантия", equipLoc = "INVTYPE_CHEST",
        reqLevel = 20, classID = 4, subclassID = 1, sellPrice = 400 })
    H.item(env, 9001, { name = "Мантия из магической ткани", equipLoc = "INVTYPE_CHEST",
        reqLevel = 25, classID = 4, subclassID = 1, sellPrice = 2000 })
    env.stats[9000] = { ITEM_MOD_INTELLECT_SHORT = 6, ITEM_MOD_STAMINA_SHORT = 4 }
    env.stats[9001] = { ITEM_MOD_INTELLECT_SHORT = 18, ITEM_MOD_STAMINA_SHORT = 12 }
    env.prices[9001] = 30000
    env.equipped.CHEST = { itemID = 9000 }
    env.equipped.MAINHAND = { itemID = 7054 }

    -- Крафт на продажу: выгодный, цена выше материалов.
    for i = 1, 6 do
        local itemID = 9100 + i
        H.item(env, itemID, { name = "Сумка из магической ткани " .. i, sellPrice = 900 })
        env.prices[itemID] = 9000 + i * 500
    end

    -- 265 выученных рецептов, как в «265 рецептов известно».
    local tailoring = {}
    tailoring[1] = H.recipe { id = 9001, name = "Мантия из магической ткани",
        output = 9001, outputQty = 1, diff = nil,
        reagents = { { itemID = 4339, qty = 6 } },
        category = "Мантии", categoryID = 1 }
    for i = 1, 6 do
        tailoring[#tailoring + 1] = H.recipe { id = 9100 + i,
            name = "Сумка из магической ткани " .. i, output = 9100 + i,
            outputQty = 1, diff = "trivial",
            reagents = { { itemID = 4339, qty = 2 } },
            category = "Сумки", categoryID = 2 }
    end
    -- Остальное добивает счётчик до 265: обычные выученные рецепты без прибыли.
    local filler = 9200
    while (#tailoring + 3) < 265 do
        filler = filler + 1
        H.item(env, filler, { name = "Поделка " .. filler })
        tailoring[#tailoring + 1] = H.recipe { id = filler, name = "Поделка " .. filler,
            output = filler, outputQty = 1, diff = "trivial",
            reagents = { { itemID = 14047, qty = 3 } },
            category = "Прочее", categoryID = 3 }
    end
    H.profession(env, "Портняжное дело", 225, 225, tailoring)

    -- Чары: формула на пояс, слот под неё свободен.
    H.profession(env, "Наложение чар", 225, 225, {
        H.recipe { id = 9500, name = "Чары для наручей: интеллект",
            reagents = { { itemID = 11137, qty = 2 } }, diff = "medium",
            category = "Чары для наручей", categoryID = 10 },
    })
    H.profession(env, "Кулинария", 225, 225, {
        H.recipe { id = 9600, name = "Жареное мясо", output = 14047, outputQty = 1,
            reagents = { { itemID = 4339, qty = 1 } }, diff = "trivial",
            category = "Еда", categoryID = 4 },
    })
    H.profession(env, "Первая помощь", 225, 225, {
        H.recipe { id = 9700, name = "Плотная повязка", output = 14047, outputQty = 1,
            reagents = { { itemID = 4339, qty = 2 } }, diff = "trivial",
            category = "Бинты", categoryID = 5 },
    })
    return env
end

H.suite("Регресс: 265 рецептов, 4з 91с — советы есть, пока их не скрыли")
do
    local env, ns = fresh()
    playerWorld(env, ns)

    local cards, meta = H.build(env)
    H.ok(#cards > 0, #cards .. " карточек на мире игрока (до скрывашек)")
    H.eq(meta.learnedRecipes, 265, "265 выученных рецептов, как на экране")
    H.eq(env.money, 49135, "4з 91с 35м в кошельке")
    H.ok(ns.PriceProvider:AuctionatorEnabled(), "Auctionator доступен")
    H.ok(ns.Api:ItemStatsRaw(9001) ~= nil, "характеристики предметов читаются")

    -- Все четыре профессии на потолке: это ожидаемо и крафт на продажу
    -- с чарами от этого отключаться не должны.
    local capped = 0
    for _, prof in ipairs(ns.CharacterScanner:CraftingProfessions()) do
        if prof.skill and prof.max and prof.skill >= prof.max then capped = capped + 1 end
    end
    H.eq(capped, 4, "все четыре профессии 225/225")
    local counts = meta.counts or {}
    H.ok((counts.profit or 0) > 0,
        "крафт на продажу работает при навыке на потолке: " .. tostring(counts.profit))
    H.ok((counts.gear or 0) > 0,
        "ветка экипировки работает при навыке на потолке: " .. tostring(counts.gear))
end

H.suite("Регресс: скрыв всё, игрок не остаётся без советов")
do
    local env, ns = fresh()
    playerWorld(env, ns)

    local cards = H.build(env)
    local keys, n = {}, 0
    for _, card in ipairs(cards) do keys[#keys + 1] = card.key end
    H.ok(#keys > 0, #keys .. " карточек можно скрыть")

    -- Игрок прошёлся по списку правым щелчком - ровно то, что лежит
    -- в его ForeverPilotDB.dismissed.
    local now = ns.Api:ServerTime()
    for _, key in ipairs(keys) do
        ns.Config:Dismiss(key, now, 86400)
        n = n + 1
    end

    local after, meta = H.build(env)
    H.ok(#after > 0, "после скрытия всех " .. n .. " карточек список НЕ пуст",
        "получили " .. #after)
    H.eq(meta.hiddenByDismissal, n,
        "движок сосчитал скрытое ровно: " .. tostring(meta.hiddenByDismissal))

    -- Счётчик не накапливается между пересборками: hidden сбрасывается.
    local raw = #ns.ActionEngine.hidden
    H.ok(raw > 0, raw .. " записей в списке скрытого после первой сборки")
    local _, meta2 = H.build(env)
    H.eq(meta2.hiddenByDismissal, n, "и на втором пересчёте число то же, не двойное")
    -- Сам список тоже обнуляется, а не копится: счётчик этого не покажет,
    -- потому что HiddenSummary схлопывает повторы ключей, а память течёт.
    H.eq(#ns.ActionEngine.hidden, raw,
        "список скрытого не растёт от пересчёта к пересчёту")
    local _, meta3 = H.build(env)
    H.eq(meta3.hiddenByDismissal, n, "и на третьем")
    H.eq(#ns.ActionEngine.hidden, raw, "и на третьем список той же длины")

    -- И карточка, которая осталась, обязана объяснить происходящее.
    local restore
    for _, card in ipairs(after) do
        if card.action and card.action.kind == "undismiss" then restore = card end
    end
    H.ok(restore ~= nil, "есть карточка «вернуть скрытые»")
    if restore then
        H.ok(tostring(restore.why):find("скры") ~= nil,
            "в объяснении сказано про скрытые советы: " .. tostring(restore.why))
        H.ok(tostring(restore.title):find(tostring(n)) ~= nil
            or tostring(restore.benefit):find(tostring(n)) ~= nil,
            "названо число скрытых советов")
        H.eq(restore.pinTop, true, "карточка приколота наверх")
        H.eq(restore.blocking, true, "и сама не скрывается — иначе снова получим ноль")
    end

    -- Она должна проходить любой фильтр: игрок может сидеть на «Золото»,
    -- как на скриншоте, и обязан увидеть причину.
    for _, chip in ipairs(ns.CHIP_ORDER) do
        local filtered = ns.ActionEngine:Filtered(chip)
        H.ok(#filtered > 0, "фильтр «" .. (ns.CHIP_LABEL[chip] or chip)
            .. "» не пустой, пока есть скрытые")
    end

    -- Диагностика больше не врёт «ни одна ветка советов ничего не выдала».
    local mod = ns.Diag:Init().modules or {}
    local ae = mod.actionEngine or {}
    H.ok(ae.hiddenByDismissal ~= nil and ae.hiddenByDismissal >= n,
        "в диагностике записано число скрытых: " .. tostring(ae.hiddenByDismissal))
end

-- 30. Снять скрывашки можно, и это не стирает настройки ----------------
H.suite("Регресс: скрытые советы возвращаются одной командой")
do
    local env, ns = fresh()
    local now = ns.Api:ServerTime()
    ns.Config:Dismiss("profit:1", now, 86400)
    ns.Config:Dismiss("gear:2", now, 86400)
    ns.Config:SetProfile("EARN")
    H.eq(ns.Config:IsDismissed("profit:1", now), true, "карточка скрыта")

    local cleared = ns.Config:ClearDismissed()
    H.eq(cleared, 2, "снято две скрывашки")
    H.eq(ns.Config:IsDismissed("profit:1", now), false, "первая вернулась")
    H.eq(ns.Config:IsDismissed("gear:2", now), false, "вторая тоже")
    H.eq(ns.Config:Profile(), "EARN", "профиль при этом не тронут")
    H.eq(ns.Config:ClearDismissed(), 0, "повторный вызов снимать нечего")
end

-- 29b. Каждая молчащая ветка объясняет себя сама ------------------------
--
-- «Всё уже сделано» на пустом окне ничего не объясняет. Каждая ветка, выдавшая
-- ноль карточек, обязана записать причину — своими словами и из своих же
-- чисел, без новых вычислений.
H.suite("Регресс: ветка, выдавшая ноль, называет причину")
do
    local env, ns = fresh()
    env.money = 49135
    env.player.level = 26
    env.player.classFile = "MAGE"
    -- Профессия на потолке, рецепт убыточный, чар нет, хлама нет.
    H.item(env, 300, { name = "Дорогая ткань" })
    env.prices[300] = 50000
    H.item(env, 301, { name = "Дешёвая тряпка" })
    env.prices[301] = 10
    env.bags[300] = 2
    H.profession(env, "Портняжное дело", 225, 225, {
        H.recipe { id = 1, name = "Убыточная тряпка", output = 301, diff = "trivial",
                   reagents = { { itemID = 300, qty = 1 } } },
    })
    local cards, meta = H.build(env)
    H.ok(meta.branches ~= nil, "отчёт по веткам построен")
    -- Список ветвей, а не их число: когда появляется новая ветка (а «надеть
    -- своё» появилась именно так), число меняется законно, а вот пропажа или
    -- переименование ветки - нет.
    -- Ветки второго этапа (перепродажа у торговцев, распыление, перекупка
    -- лотов, «что говорят цены») дописаны в конец: порядок в списке - это
    -- порядок, в котором их считает движок, и новые встают после старых.
    -- «camp» (лагерь у костра) встал после «favor»: там же, где его считает
    -- движок - после покупок, потому что ему нужны цены.
    local EXPECTED = { "equip", "gear", "enchant", "profit", "skill", "buy", "junk",
                       "arbitrage", "favor", "camp", "paths", "disenchant",
                       "resale", "priceinfo", "cross" }
    local keys = {}
    for _, br in ipairs(meta.branches or {}) do keys[#keys + 1] = br.key end
    H.eq(table.concat(keys, ","), table.concat(EXPECTED, ","),
        "все ветви перечислены и в своём порядке")
    -- И ни одна из прежних не пропала: именно пропажа ветки - та поломка,
    -- из-за которой эта проверка существует, а не изменение их числа.
    local present = {}
    for _, k in ipairs(keys) do present[k] = true end
    for _, k in ipairs({ "equip", "gear", "enchant", "profit", "skill", "buy", "junk" }) do
        H.eq(present[k], true, "прежняя ветка «" .. k .. "» на месте")
    end

    local byKey = {}
    for _, br in ipairs(meta.branches or {}) do byKey[br.key] = br end
    for _, key in ipairs(EXPECTED) do
        H.ok(byKey[key] ~= nil, "ветка " .. key .. " в отчёте")
        if byKey[key] and byKey[key].count == 0 then
            H.ok(byKey[key].reason ~= nil and byKey[key].reason ~= "",
                "ветка " .. key .. " назвала причину: " .. tostring(byKey[key].reason))
        else
            H.ok(true, "ветка " .. key .. " выдала " .. tostring(byKey[key] and byKey[key].count))
        end
    end
    H.ok((byKey.enchant.reason or ""):find("формул") ~= nil,
        "чары: сказано про формулы — " .. tostring(byKey.enchant.reason))
    H.ok((byKey.junk.reason or ""):find("хлам") ~= nil,
        "хлам: сказано про хлам — " .. tostring(byKey.junk.reason))
    -- Навык на потолке - это не молчащая ветка: она выдаёт свою карточку,
    -- которая и объясняет потолок. Поэтому причины у неё нет, а объяснение
    -- есть, и оно на экране.
    H.eq(byKey.skill.reason, nil, "навык: ветка не молчит, причина не нужна")
    local capCard
    for _, card in ipairs(cards) do
        if card.cappedProfessions then capCard = card end
    end
    H.ok(capCard ~= nil, "и потолок объясняет отдельная карточка")
    H.ok(capCard and (capCard.why or ""):find("максимальн") ~= nil,
        "в ней сказано, что навык равен максимуму")

    -- Ветка, которая что-то выдала, причину не получает: иначе отчёт врёт.
    for _, br in ipairs(meta.branches or {}) do
        if (br.count or 0) > 0 then
            H.eq(br.reason, nil, "работающая ветка " .. br.key .. " без причины")
        end
    end

    -- Без Auctionator причина крафта на продажу меняется на «нет цен».
    local env2, ns2 = fresh()
    env2.auctionator = false
    env2.money = 100
    H.item(env2, 310, { name = "Ткань" })
    H.item(env2, 311, { name = "Итог" })
    H.profession(env2, "Портняжное дело", 100, 300, {
        H.recipe { id = 1, name = "Что-то", output = 311, diff = "optimal",
                   reagents = { { itemID = 310, qty = 1 } } },
    })
    local _, meta2 = H.build(env2)
    local profit2
    for _, br in ipairs(meta2.branches or {}) do
        if br.key == "profit" then profit2 = br end
    end
    H.ok(profit2 and (profit2.reason or ""):find("цен") ~= nil,
        "без цен так и сказано: " .. tostring(profit2 and profit2.reason))
end

-- 30b. Одна профессия — одна запись ------------------------------------
--
-- В живом файле игрока ключ карточки о потолке выглядел так:
--   cap:reached:Кулинария,Кулинария,Наложение чар,Наложение чар,
--               Первая помощь,Первая помощь,Портняжное дело,Портняжное дело
-- Каждая профессия дважды. Диагностика подтверждает: professions = 10,
-- craftingProfessions = 8 при четырёх реальных крафтовых профессиях.
-- Клиент отдаёт одну и ту же линию навыка под двумя разными ID
-- (C_SkillInfo.GetSkillLineInfoByID пробегает и список профессий, и окно
-- навыков), а Api:Professions честно возвращает обе. Склеивать их — работа
-- сканера: это он фильтрует и помечает профессии.
H.suite("Регресс: одна и та же профессия не считается дважды")
do
    local env, ns = fresh()
    -- Ровно то, что отдаёт клиент: одно имя, два ID линии навыка, причём
    -- у второй записи числа хуже (так и приходит из окна навыков).
    env.professions = {
        { name = "Портняжное дело", skill = 225, max = 225, skillLineID = 197,
          skillTrusted = true },
        { name = "Портняжное дело", skill = nil, max = nil, skillLineID = 3908,
          skillTrusted = false, fromSkillWindow = true },
        { name = "Кулинария", skill = 225, max = 225, skillLineID = 185,
          skillTrusted = true },
        { name = "Кулинария", skill = 225, max = 225, skillLineID = 2550,
          skillTrusted = true },
        { name = "Рыбная ловля", skill = 150, max = 225, skillLineID = 356,
          skillTrusted = true },
        { name = "Рыбная ловля", skill = 150, max = 225, skillLineID = 131474,
          skillTrusted = true },
    }
    local snap = H.rescan(env)
    H.eq(#snap.professions, 3, "шесть записей клиента склеились в три профессии")

    local crafting = ns.CharacterScanner:CraftingProfessions()
    H.eq(#crafting, 2, "крафтовых профессий две, а не четыре")

    local names = {}
    for _, prof in ipairs(snap.professions) do
        H.eq(names[prof.name], nil, "«" .. tostring(prof.name) .. "» встречается один раз")
        names[prof.name] = true
    end

    -- Склеивать надо в пользу записи с настоящими числами.
    for _, prof in ipairs(snap.professions) do
        if prof.name == "Портняжное дело" then
            H.eq(prof.skill, 225, "оставлены доверенные числа, а не пустые")
            H.eq(prof.skillTrusted, true, "и отметка доверия с ними")
        end
    end

    -- И карточка о потолке перечисляет каждую профессию по одному разу.
    ns.RecipeBook:Store("Портняжное дело", {
        H.recipe { id = 1, name = "Мантия", output = 50, diff = "trivial",
                   reagents = {} },
    }, "own", ns.CONF.EXACT, H.serverTime)
    ns.RecipeBook:Store("Кулинария", {
        H.recipe { id = 2, name = "Похлёбка", output = 51, diff = "trivial",
                   reagents = {} },
    }, "own", ns.CONF.EXACT, H.serverTime)
    ns.RecipeBook:Reindex()
    H.item(env, 50, { name = "Мантия" })
    H.item(env, 51, { name = "Похлёбка" })

    local cards = H.build(env)
    local capCard
    for _, card in ipairs(cards) do
        if card.cappedProfessions then capCard = card end
    end
    H.ok(capCard ~= nil, "карточка о потолке построена")
    if capCard then
        H.eq(#capCard.cappedProfessions, 2, "в ней две профессии, не четыре")
        local _, dupes = capCard.key:gsub("Кулинария", "")
        H.eq(dupes, 1, "и в ключе карточки имя не повторяется: " .. capCard.key)
    end
end

-- 29c. Сборка работает и без диагностики --------------------------------
--
-- Ветки вызываются через локальный timed(), и в его резервной ветке «если
-- диагностики нет» стояло fn(snap, scales) вместо fn(self, snap, scales):
-- snap приезжал на место self, и первое же обращение к self.branchNote
-- валило ветку. В игре ns.Diag есть всегда, поэтому защита, которая не
-- защищает, так и не выстрелила — но это ровно тот код, который должен
-- работать, когда всё остальное уже сломалось.
H.suite("Регресс: ветки советов вызываются с self в обеих ветвях timed()")
do
    local env, ns = fresh()
    env.money = 25000
    env.player.level = 26
    env.player.classFile = "MAGE"
    H.item(env, 400, { name = "Шёлк" })
    env.prices[400] = 100
    env.bags[400] = 10
    H.item(env, 401, { name = "Шёлковый пояс", equipLoc = "INVTYPE_WAIST",
        reqLevel = 20, classID = 4, subclassID = 1 })
    env.stats[401] = { ITEM_MOD_INTELLECT_SHORT = 8 }
    env.prices[401] = 50000
    H.profession(env, "Портняжное дело", 180, 300, {
        H.recipe { id = 1, name = "Шёлковый пояс", output = 401, diff = "optimal",
                   reagents = { { itemID = 400, qty = 3 } } },
    })
    local snap = H.rescan(env)

    -- Каждая ветка — метод, и self ей действительно нужен: без него она
    -- обязана падать, а не тихо делать что-то не то. Именно это и ловит
    -- опечатку fn(snap, scales) вместо fn(self, snap, scales).
    local E = ns.ActionEngine
    local scales = E:Scales(snap)
    for _, name in ipairs({ "AddGearCards", "AddEnchantCards", "AddProfitCards",
                            "AddSkillCards", "AddBuyCards", "AddJunkCards" }) do
        E.cards, E.hidden, E.branchNote = {}, {}, {}
        ns.PriceProvider:BeginPass()
        ns.CraftingPlanner:Bind(ns.RecipeBook, ns.PriceProvider):BeginPass()
        ns.GearAdvisor:BeginPass()
        ns.ShoppingList:Reset()
        ns.ShoppingList:SetInventory(snap)
        local okMethod = pcall(E[name], E, snap, scales)
        H.eq(okMethod, true, name .. " работает, когда self передан")
        local okNoSelf = pcall(E[name], snap, scales)
        H.eq(okNoSelf, false, name .. " без self падает — значит self обязателен")
    end

    -- И резервная ветка timed() передаёт его так же, как основная. Проверяется
    -- по исходнику: в тестах ns.Diag есть всегда, иначе фейки харнесса сами
    -- не работают, так что поведением эту ветку offline не достать.
    --
    -- ПРОВЕРЯЕТСЯ КОНТРАКТ, А НЕ НАПИСАНИЕ. Раньше здесь искалась одна
    -- конкретная строка целиком, и любая правка внутри timed() - даже та, что
    -- контракт не нарушает - ломала проверку, то есть проверка защищала
    -- форматирование вместо поведения. Теперь ищутся ВСЕ вызовы fn(...) внутри
    -- timed(), и каждый обязан начинаться с self. Это строже: добавь кто-нибудь
    -- третью ветку с fn(snap, scales) - поймается и она.
    local fh = io.open(H.ROOT .. "/Logic/ActionEngine.lua", "r")
    H.ok(fh ~= nil, "Logic/ActionEngine.lua читается")
    if fh then
        local src = fh:read("*a")
        fh:close()
        local body = src:match("local function timed%(name, fn%)(.-)\n    end")
        H.ok(body ~= nil, "тело timed() найдено в исходнике")
        if body then
            -- Комментарии выбрасываются: внутри timed() объяснена та самая
            -- опечатка fn(snap, scales), и считать её нарушением контракта
            -- значит запретить документировать ошибку, из-за которой проверка
            -- и появилась.
            local code = body:gsub("%-%-[^\n]*", "")
            local calls, bad = 0, 0
            for args in code:gmatch("fn%((.-)%)") do
                calls = calls + 1
                if not args:match("^%s*self%s*,") then bad = bad + 1 end
            end
            H.ok(calls >= 2, "в timed() " .. calls
                .. " вызовов ветки — есть и основная, и резервная")
            H.eq(bad, 0, "каждый вызов ветки в timed() передаёт self первым аргументом")
        end
        H.eq(src:find("return fn(snap, scales)", 1, true), nil,
            "и старого вызова без self в файле не осталось")
    end
    E.cards, E.hidden, E.branchNote = {}, {}, {}
end

-- 30a. Обязательную карточку скрывашка не трогает -----------------------
--
-- Карточку с blocking = true интерфейс скрыть отказывается, поэтому запись
-- о её скрытии в SavedVariables может быть только мусором от прежней версии
-- или совпадением ключа. Чинить такое молчаливым исчезновением нельзя: без
-- карточки «откройте окно профессии» список просто неверен.
H.suite("Регресс: скрывашка не действует на обязательную карточку")
do
    local env, ns = fresh()
    env.professions = {
        { name = "Портняжное дело", skill = 100, max = 300, skillTrusted = true },
    }
    -- Рецептов нет: движок обязан выдать карточку «откройте окно профессии».
    H.rescan(env)
    local cards = H.build(env)
    local setupKey
    for _, card in ipairs(cards) do
        if card.blocking then setupKey = card.key end
    end
    H.ok(setupKey ~= nil, "обязательная карточка построена: " .. tostring(setupKey))

    -- Прячем её ключ напрямую, минуя интерфейс.
    ns.Config:Dismiss(setupKey, ns.Api:ServerTime(), 86400)
    H.eq(ns.Config:IsDismissed(setupKey, ns.Api:ServerTime()), true,
        "запись в таблице есть")

    local after, meta = H.build(env)
    local stillThere = false
    for _, card in ipairs(after) do
        if card.key == setupKey then stillThere = true end
    end
    H.eq(stillThere, true, "обязательная карточка на месте, несмотря на запись")
    H.eq(meta.hiddenByDismissal, 0,
        "и в скрытые она не записана — её никто не скрывал")

    -- А необязательная карточка с тем же подходом исчезает как обычно.
    local optional
    for _, card in ipairs(after) do
        if not card.blocking then optional = card end
    end
    if optional then
        ns.Config:Dismiss(optional.key, ns.Api:ServerTime(), 86400)
        local after2, meta2 = H.build(env)
        local found = false
        for _, card in ipairs(after2) do
            if card.key == optional.key then found = true end
        end
        H.eq(found, false, "необязательная «" .. tostring(optional.title) .. "» скрылась")
        H.eq(meta2.hiddenByDismissal, 1, "и попала в счётчик скрытых")
    else
        H.ok(false, "не нашлось необязательной карточки для сравнения")
    end
end

-- 30c. Без времени скрывашка не вечная ---------------------------------
--
-- Тот же класс отказа, что и основная причина, только хуже: если
-- GetServerTime вернёт не число, то `(now or 0) > expiry` ложно для любой
-- записи, и КАЖДАЯ скрытая карточка скрыта навсегда, без срока годности.
-- Показать карточку, которую игрок прятал, — меньшее зло, чем навсегда
-- выключить все советы.
H.suite("Регресс: без времени сервера скрывашки не действуют")
do
    local env, ns = fresh()
    ns.Config:Dismiss("profit:1", 1794800000, 86400)
    H.eq(ns.Config:IsDismissed("profit:1", 1794800000), true, "в обычное время скрыта")
    H.eq(ns.Config:IsDismissed("profit:1", nil), false,
        "без времени — не скрыта, а не скрыта навсегда")
    H.eq(ns.Config:IsDismissed("profit:1", 0), false, "и при нулевом времени тоже")
    H.eq(ns.Config:IsDismissed("profit:1", 1794800000), true,
        "и запись при этом не потеряна")

    -- И записывать скрывашку без времени тоже нельзя: получится метка из
    -- 1970 года, которая истекла ещё до того, как игрок отпустил кнопку.
    -- Проверяем саму таблицу, а не IsDismissed: он такую метку всё равно
    -- вернёт как просроченную, и тест был бы зелёным при записанном мусоре.
    H.eq(ns.Config:Dismiss("gear:1", nil, 86400), false,
        "Dismiss сообщает, что не записал")
    H.eq(ns.Config:Get().dismissed["gear:1"], nil,
        "и в таблице ничего не появилось")
    H.eq(ns.Config:Dismiss("gear:2", 0, 86400), false, "нулевое время тоже отклонено")
    H.eq(ns.Config:Get().dismissed["gear:2"], nil, "и тоже ничего не записано")
    H.eq(ns.Config:Dismiss("gear:3", 1794800000, 86400), true,
        "а с настоящим временем записывает и подтверждает")
    H.eq(ns.Config:DismissedCount(1794800000), 2,
        "в таблице только датированные записи")

    -- DismissedCount считает живые, а не все: просроченные не в счёт.
    ns.Config:Get().dismissed["старая"] = 1794700000
    H.eq(ns.Config:DismissedCount(1794800000), 2,
        "просроченная запись в счёт не идёт")
    H.eq(ns.Config:DismissedCount(1794600000), 3,
        "а до её истечения — идёт")
end

-- 30d. HiddenSummary не считает один ключ дважды ------------------------
H.suite("Регресс: один скрытый ключ — одна единица в счётчике")
do
    local env, ns = fresh()
    local E = ns.ActionEngine
    E.hidden = {
        { key = "profit:1", kind = ns.KIND.CRAFT_PROFIT, title = "A", until_ = 300 },
        { key = "profit:1", kind = ns.KIND.CRAFT_PROFIT, title = "A", until_ = 500 },
        { key = "gear:2", kind = ns.KIND.CRAFT_GEAR, title = "B", until_ = 200 },
    }
    local count, soonest = E:HiddenSummary()
    H.eq(count, 2, "три записи с повтором дали два скрытых совета")
    H.eq(soonest, 200, "и ближайший срок — самый ранний")

    E.hidden = {}
    local zero, none = E:HiddenSummary()
    H.eq(zero, 0, "пусто — ноль")
    H.eq(none, nil, "и срока нет")
end

-- 31. Счётчик скрытого честен и когда советы остались -------------------
H.suite("Регресс: скрытое считается, даже когда список не пуст")
do
    local env, ns = fresh()
    playerWorld(env, ns)
    local cards = H.build(env)
    H.ok(#cards > 1, "карточек больше одной")

    ns.Config:Dismiss(cards[1].key, ns.Api:ServerTime(), 86400)
    local after, meta = H.build(env)
    H.eq(meta.hiddenByDismissal, 1, "одна скрытая учтена")
    H.ok(#after > 0, "список по-прежнему не пуст")
    local restore
    for _, card in ipairs(after) do
        if card.action and card.action.kind == "undismiss" then restore = card end
    end
    H.eq(restore, nil, "но карточку «вернуть» не навязываем, пока советы есть")
end

end
