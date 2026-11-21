-- ForeverPilot / Tests/test_handy.lua
--
-- КНОПКИ НА СОВЕТАХ: «ПОКАЗАТЬ В ПРОФЕССИИ» И «ИСКАТЬ НА АУКЦИОНЕ».
--
-- Жалоба игрока (маг 32 ур., 2026-11-21, три совета «Скрафтить: …» на экране):
-- «Почему у меня нету „Показать в профессии“ кнопочки? Я просто на это смотрю и
-- должен ручками вбивать название в профессии. Или искать на аукционе
-- кнопочку вставить».
--
-- Открыть окно профессии аддон не может: игра этот вызов блокирует и обвиняет
-- аддон (Core/Api.lua). Что здесь закреплено:
--   1. окно профессии аддон не открывает НИКОГДА - запрещённый вызов не
--      делается ни в одном из состояний;
--   2. в окне, которое игрок открыл сам, остаётся один рецепт - поиском по
--      имени; если окно закрыто, нажатие запоминается и срабатывает, когда
--      игрок окно откроет;
--   3. второе нажатие и закрытие окна возвращают весь список, а поиск, который
--      игрок набрал сам, аддон не трогает;
--   4. игра заблокировала или вызов упал - кнопки больше нет, насовсем;
--   5. у аукциона кнопка совета ищет то, что этому совету нужно, - и только
--      то, что есть смысл искать на аукционе;
--   6. подпись кнопки и то, что она делает, решает одна функция.
local H = ...
local S = assert(loadfile((H.ROOT or ".") .. "/Tests/uistub.lua"))()

return function()

local RECIPE = 1
local HOOD, OLD_HOOD, CLOTH = 101, 100, 200

local function world(opts)
    opts = opts or {}
    local env = S.load(H)
    local ns = env.ns
    env.player.classFile = "MAGE"
    env.player.level = 30
    H.item(env, OLD_HOOD, { name = "Старый капюшон", equipLoc = "INVTYPE_HEAD",
        reqLevel = 20, classID = 4, subclassID = 1, sellPrice = 100 })
    env.stats[OLD_HOOD] = { ITEM_MOD_INTELLECT_SHORT = 4, ITEM_MOD_STAMINA_SHORT = 3 }
    env.equipped.HEAD = { itemID = OLD_HOOD }
    H.item(env, HOOD, { name = "Хороший капюшон", equipLoc = "INVTYPE_HEAD",
        reqLevel = 25, classID = 4, subclassID = 1, sellPrice = 400 })
    env.stats[HOOD] = { ITEM_MOD_INTELLECT_SHORT = 12, ITEM_MOD_STAMINA_SHORT = 9 }
    H.item(env, CLOTH, { name = "Ткань", sellPrice = 10 })
    env.prices[CLOTH] = 50
    env.prices[HOOD] = 3000
    env.money = 50000
    env.auctionator = true
    H.profession(env, "Портняжное дело", 225, 225, {
        H.recipe { id = RECIPE, output = HOOD, reagents = { { itemID = CLOTH, qty = 4 } },
                   name = "Хороший капюшон", diff = "optimal", category = "Капюшоны" },
    })

    -- Поиск по имени в окне профессии: то, что ставит и читает клиент.
    local filter = { text = "", calls = {} }
    if opts.filter ~= false then
        env.G.C_TradeSkillUI = env.G.C_TradeSkillUI or {}
        env.G.C_TradeSkillUI.SetRecipeItemNameFilter = function(text)
            if opts.filterError then error("клиент отказал") end
            filter.text = text or ""
            filter.calls[#filter.calls + 1] = filter.text
        end
        env.G.C_TradeSkillUI.GetRecipeItemNameFilter = function() return filter.text end
    end
    return env, ns, filter
end

local function cardOf(cards, ns, kind)
    for _, c in ipairs(cards) do
        if c.kind == kind then return c end
    end
    return nil
end

local function press(env, ns, card)
    env.said = {}
    ns.Card.Activate(card)
    return env.said[#env.said], #env.said
end

local function forbiddenCalls(env)
    return #(env.openRecipeCalls or {})
end

-- Аукцион открыт, и Auctionator умеет поиск списком.
local function openAuction(env)
    local searched = {}
    env.G.Auctionator = { API = { v1 = {
        MultiSearchAdvanced = function(caller, terms)
            if env.auctionatorError then error("Auctionator: неверный запрос") end
            searched[#searched + 1] = terms
        end,
    } } }
    local ah = env.world.newFrame("Frame", "AuctionHouseFrame")
    ah:Show()
    env.G.AuctionHouseFrame = ah
    env.G.AuctionatorTabs_Shopping = env.world.newFrame("Button", "AuctionatorTabs_Shopping")
    return searched, ah
end

-- 1. СТАРОЕ ПОВЕДЕНИЕ, КОГДА ИСКАТЬ НЕЧЕМ ---------------------------------

H.suite("Кнопки: клиент не умеет искать по имени — кнопки у рецепта нет, как раньше")
do
    local env, ns = world { filter = false }
    local cards = H.build(env)
    local gear = cardOf(cards, ns, ns.KIND.CRAFT_GEAR)
    H.ok(gear ~= nil, "совет «скрафтить» построен")
    if gear then
        H.eq(ns.RecipeBook:CanShow(RECIPE), false, "показать рецепт нечем")
        H.eq(ns.Card.LiveAction(gear), nil, "нажимать на совете нечего")
        H.eq(ns.Card.ActionReady(gear), false, "и кнопка не рисуется")
        local line = press(env, ns, gear)
        H.ok(ns.Util.contains(line or "", "Хороший капюшон"),
            "щелчок по совету говорит, что найти: " .. tostring(line))
        H.ok(ns.Util.contains(line or "", "Портняжное дело"), "и в какой профессии")
    end
    H.eq(ns.RecipeBook:CanShow(), false, "без номера рецепта ответ всегда «нет»")
    H.eq(forbiddenCalls(env), 0, "запрещённый вызов не сделан")
end

-- 2. ОКНО ЗАКРЫТО: ЗАПОМНИТЬ И ДОЖДАТЬСЯ -----------------------------------

H.suite("Кнопки: «Показать в профессии» при закрытом окне запоминает и ждёт")
do
    local env, ns, filter = world()
    local cards = H.build(env)
    local gear = cardOf(cards, ns, ns.KIND.CRAFT_GEAR)
    H.ok(gear ~= nil, "совет «скрафтить» построен")
    local live = gear and ns.Card.LiveAction(gear)
    H.ok(live ~= nil, "на совете есть что нажать")
    if live then
        H.eq(live.kind, "showRecipe", "это показ рецепта")
        H.eq(live.label, "Показать в профессии", "и подписан он так")
        H.eq(ns.Card.ActionLabel(gear), "Показать в профессии", "подпись кнопки та же")
        H.eq(ns.Card.ActionNote(gear), nil, "объяснять отсутствие кнопки незачем: она есть")
        local title, body = ns.Card.ActionTip(gear)
        H.ok(title ~= nil and type(body) == "table" and #body >= 2, "у кнопки есть подсказка")

        local line, count = press(env, ns, gear)
        H.eq(count, 1, "одна строка в ответ")
        H.ok(ns.Util.contains(line or "", "откройте «Портняжное дело»"),
            "сказано, что открыть: " .. tostring(line))
        H.ok(ns.Util.contains(line or "", "Хороший капюшон"), "и что будет найдено")
        H.eq(#filter.calls, 0, "окно закрыто - поиск не трогали")
        H.ok(ns.RecipeBook.pending ~= nil and ns.RecipeBook.pending.recipeID == RECIPE,
            "нажатие запомнено")

        -- Игрок открыл профессию сам.
        env.openProfession = "Портняжное дело"
        local message, changed = ns.RecipeBook:OnTradeSkill("show")
        H.eq(filter.text, "Хороший капюшон", "в открытом окне поставлен поиск по имени рецепта")
        H.eq(changed, true, "экран надо перерисовать")
        H.ok(ns.Util.contains(message or "", "только «Хороший капюшон»"),
            "и сказано, что сделано: " .. tostring(message))
        H.eq(ns.RecipeBook.pending, nil, "обещание выполнено и снято")
        H.eq(ns.Card.ActionLabel(gear), "Вернуть весь список", "кнопка теперь снимает поиск")

        -- Десять событий «список обновился» подряд ничего не меняют.
        local before = #filter.calls
        for i = 1, 10 do ns.RecipeBook:OnTradeSkill("update") end
        H.eq(#filter.calls, before, "на обновлениях списка поиск заново не ставится")

        -- Второе нажатие: вернуть весь список.
        local back = press(env, ns, gear)
        H.eq(filter.text, "", "поиск снят")
        H.ok(ns.Util.contains(back or "", "вернул весь список"), "и сказано: " .. tostring(back))
        H.eq(ns.Card.ActionLabel(gear), "Показать в профессии", "подпись вернулась")
    end
    H.eq(forbiddenCalls(env), 0, "окно профессии аддон не открывал ни разу")
end

-- 3. ОКНО УЖЕ ОТКРЫТО --------------------------------------------------------

H.suite("Кнопки: окно профессии открыто — рецепт находится сразу")
do
    local env, ns, filter = world()
    env.openProfession = "Портняжное дело"
    local gear = cardOf(H.build(env), ns, ns.KIND.CRAFT_GEAR)
    local line = press(env, ns, gear)
    H.eq(filter.text, "Хороший капюшон", "поиск поставлен сразу")
    H.ok(ns.Util.contains(line or "", "оставил в списке"), "сказано, что сделано: " .. tostring(line))
    H.eq(ns.RecipeBook.pending, nil, "ждать нечего")

    -- Игрок закрыл окно: свой поиск аддон за собой убирает.
    local _, changed = ns.RecipeBook:OnTradeSkill("close")
    H.eq(changed, true, "подпись кнопки изменится")
    H.eq(filter.text, "", "поиск снят при закрытии окна")
    H.eq(ns.RecipeBook.applied, nil, "и состояние забыто")
    H.eq(forbiddenCalls(env), 0, "запрещённый вызов не сделан")
end

H.suite("Кнопки: поиск, который игрок набрал сам, аддон не трогает")
do
    local env, ns, filter = world()
    env.openProfession = "Портняжное дело"
    local gear = cardOf(H.build(env), ns, ns.KIND.CRAFT_GEAR)
    press(env, ns, gear)
    H.eq(filter.text, "Хороший капюшон", "поиск поставлен")
    -- Окно, открываясь, само сбросило фильтры сразу после нашего вызова:
    -- поиск ставится заново, а не считается «игрок передумал».
    filter.text = ""
    ns.RecipeBook:OnTradeSkill("update")
    H.eq(filter.text, "Хороший капюшон", "сброс окном в первые секунды - ставим ещё раз")
    H.ok(ns.RecipeBook.applied ~= nil, "и по-прежнему считаем поиск своим")
    -- Прошло время: игрок стёр и набрал своё.
    H.clock = H.clock + ns.RecipeBook.SETTLE_SECONDS + 1
    filter.text = "плащ"
    local _, changed = ns.RecipeBook:OnTradeSkill("update")
    H.eq(changed, true, "кнопка возвращается к «Показать»")
    H.eq(ns.RecipeBook.applied, nil, "своим этот поиск аддон больше не считает")
    H.eq(filter.text, "плащ", "и чужой текст не тронут")
    ns.RecipeBook:OnTradeSkill("close")
    H.eq(filter.text, "плащ", "при закрытии - тоже")
end

H.suite("Кнопки: открыта другая профессия — ждём нужную")
do
    local env, ns, filter = world()
    env.openProfession = "Кулинария"
    local gear = cardOf(H.build(env), ns, ns.KIND.CRAFT_GEAR)
    local line = press(env, ns, gear)
    H.eq(#filter.calls, 0, "в чужом окне поиск не ставится")
    H.ok(ns.Util.contains(line or "", "другая профессия"), "сказано почему: " .. tostring(line))
    ns.RecipeBook:OnTradeSkill("update")
    H.eq(#filter.calls, 0, "и на обновлениях чужого окна тоже")
    env.openProfession = "Портняжное дело"
    ns.RecipeBook:OnTradeSkill("show")
    H.eq(filter.text, "Хороший капюшон", "открыли нужную - поиск поставлен")
end

H.suite("Кнопки: забытое нажатие через десять минут не срабатывает")
do
    local env, ns, filter = world()
    local gear = cardOf(H.build(env), ns, ns.KIND.CRAFT_GEAR)
    press(env, ns, gear)
    H.ok(ns.RecipeBook.pending ~= nil, "нажатие запомнено")
    H.clock = H.clock + ns.RecipeBook.PENDING_SECONDS + 5
    env.openProfession = "Портняжное дело"
    ns.RecipeBook:OnTradeSkill("show")
    H.eq(#filter.calls, 0, "через десять минут список не сужается сам собой")
    H.eq(ns.RecipeBook.pending, nil, "обещание снято")
end

-- 4. ИГРА ОТКАЗАЛА ---------------------------------------------------------

H.suite("Кнопки: игра заблокировала поиск — кнопки больше нет, и после перезагрузки тоже")
do
    local env, ns = world()
    local gear = cardOf(H.build(env), ns, ns.KIND.CRAFT_GEAR)
    H.ok(ns.Card.LiveAction(gear) ~= nil, "до отказа кнопка есть")
    ns.Events:Dispatch("ADDON_ACTION_FORBIDDEN", "ForeverPilot",
        "C_TradeSkillUI.SetRecipeItemNameFilter()")
    H.eq(ns.RecipeBook:CanShow(RECIPE), false, "после отказа показать нечем")
    H.eq(ns.Card.LiveAction(gear), nil, "и кнопки нет")
    H.eq(ns.Config:Get().recipeFilterBlocked, true, "отказ записан в настройки")
    -- «После перезагрузки»: память сеанса пуста, запись в настройках осталась.
    ns.RecipeBook.filterBroken = nil
    H.eq(ns.RecipeBook:CanShow(RECIPE), false, "и после перезагрузки кнопка не возвращается")
    ns.Config:Get().recipeFilterBlocked = nil
end

H.suite("Кнопки: вызов поиска упал — сказано словами, второй раз не зовём")
do
    local env, ns, filter = world { filterError = true }
    env.openProfession = "Портняжное дело"
    local gear = cardOf(H.build(env), ns, ns.KIND.CRAFT_GEAR)
    local line, count = press(env, ns, gear)
    H.eq(count, 1, "одна строка, а не ошибка Lua")
    H.ok(ns.Util.contains(line or "", "не приняла"), "сказано, что игра не приняла: " .. tostring(line))
    H.ok(ns.Util.contains(line or "", "Хороший капюшон"), "и что найти самому")
    H.eq(ns.RecipeBook:CanShow(RECIPE), false, "кнопки больше нет")
    H.eq(ns.Card.LiveAction(gear), nil, "совет снова без кнопки")
end

H.suite("Кнопки: в бою окно профессии не трогаем")
do
    local env, ns, filter = world()
    env.openProfession = "Портняжное дело"
    local gear = cardOf(H.build(env), ns, ns.KIND.CRAFT_GEAR)
    env.inCombat = true
    local line = press(env, ns, gear)
    H.eq(#filter.calls, 0, "в бою поиск не ставится")
    H.ok(ns.Util.contains(line or "", "в бою"), "и сказано почему: " .. tostring(line))
    env.inCombat = false
end

-- 5. АУКЦИОН ---------------------------------------------------------------

H.suite("Кнопки: у аукциона совет «Купить» ищет свой предмет")
do
    local env, ns = world()
    local cards = H.build(env)
    local buy = cardOf(cards, ns, ns.KIND.BUY)
    H.ok(buy ~= nil, "совет «купить» построен")
    if buy then
        H.eq(ns.Card.ActionLabel(buy), "В список покупок", "аукцион закрыт - кнопка прежняя")
        local searched = openAuction(env)
        local live = ns.Card.LiveAction(buy)
        H.eq(live and live.kind, "auction", "аукцион открыт - кнопка ищет")
        H.eq(ns.Card.ActionLabel(buy), "Искать на аукционе", "и подписана так")
        local line, count = press(env, ns, buy)
        H.eq(count, 1, "одна строка в ответ")
        H.ok(ns.Util.contains(line or "", "передал в поиск Auctionator"),
            "сказано, что передано: " .. tostring(line))
        H.eq(#searched, 1, "Auctionator позван один раз")
        local term = searched[1] and searched[1][1]
        H.eq(term and term.searchString, "Ткань", "ищется сам предмет")
        H.eq(term and term.quantity, 4, "в нужном количестве")
        H.eq(term and term.isExact, true, "по точному имени")
        H.eq(next(ns.Config:Shopping()), nil, "в список покупок при этом ничего не закреплено")
    end
end

H.suite("Кнопки: у аукциона совет «Скрафтить» ищет материалы, которых не хватает")
do
    local env, ns, filter = world()
    local gear = cardOf(H.build(env), ns, ns.KIND.CRAFT_GEAR)
    local searched, ah = openAuction(env)
    local live = ns.Card.LiveAction(gear)
    H.eq(live and live.kind, "auction", "у аукциона кнопка совета ищет материалы")
    H.eq(live and #live.items, 1, "одна позиция: ткань")
    local line = press(env, ns, gear)
    H.ok(ns.Util.contains(line or "", "передал в поиск"), "сказано: " .. tostring(line))
    H.eq(searched[1] and searched[1][1] and searched[1][1].searchString, "Ткань",
        "ищется недостающий материал, а не сама вещь")
    H.eq(#filter.calls, 0, "окно профессии при этом не трогали")

    -- Аукцион закрыли: кнопка снова про профессию.
    ah:Hide()
    H.eq(ns.Card.ActionLabel(gear), "Показать в профессии", "аукцион закрыт - показ рецепта")

    -- Материалы куплены: искать на аукционе нечего даже при открытом окне.
    ah:Show()
    env.bags[CLOTH] = 4
    local ready = cardOf(H.build(env), ns, ns.KIND.CRAFT_GEAR)
    H.ok(ready ~= nil, "совет на месте")
    if ready then
        H.eq(ns.Card.ActionLabel(ready), "Показать в профессии",
            "материалы есть - у аукциона кнопка всё равно про рецепт")
    end
end

H.suite("Кнопки: то, что дешевле у торговца, на аукционе не ищем")
do
    local env, ns = world()
    env.vendorPrices[CLOTH] = 10
    local cards = H.build(env)
    local buy = cardOf(cards, ns, ns.KIND.BUY)
    openAuction(env)
    if buy then
        H.eq(#ns.ShoppingList:CardAuctionItems(buy), 0, "у торговца дешевле - в поиск не идёт")
        H.eq(ns.Card.ActionLabel(buy), "В список покупок", "и кнопка остаётся прежней")
    else
        H.ok(true, "совета «купить» в этом мире нет - проверять нечего")
    end
end

H.suite("Кнопки: Auctionator не принял поиск — сказано, и больше не зовём")
do
    local env, ns = world()
    local buy = cardOf(H.build(env), ns, ns.KIND.BUY)
    local searched = openAuction(env)
    env.auctionatorError = true
    local line, count = press(env, ns, buy)
    H.eq(count, 1, "одна строка, а не ошибка Lua")
    H.ok(ns.Util.contains(line or "", "не принял"), "сказано: " .. tostring(line))
    H.eq(ns.Card.ActionLabel(buy), "В список покупок", "кнопка вернулась к своему действию")
    ns.ShoppingList.handoffBroken = nil
end

end
