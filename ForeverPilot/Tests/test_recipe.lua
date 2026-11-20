-- ForeverPilot / Tests/test_recipe.lua
--
-- РЕЦЕПТ В ОКНЕ ПРОФЕССИЙ: АДДОН ЕГО НЕ ОТКРЫВАЕТ, А ГОВОРИТ, ГДЕ ИСКАТЬ.
--
-- Здесь была кнопка «Показать рецепт» / «Показать формулу». Она звала
-- C_TradeSkillUI.OpenRecipe, и игра показала игроку:
--
--   «Модификация "ForeverPilot" заблокирована при попытке выполнения
--    действия, доступного только интерфейсу Blizzard. Вы можете отключить
--    эту модификацию и перезагрузить интерфейс. [Отключить] [Пропустить]»
--
-- То есть на этом клиенте открытие рецепта - действие, доступное только самой
-- игре. Защита, которая тут стояла («окно профессий уже загружено игрой»),
-- защищала не от того: блокируют не первую загрузку окна, а сам вызов из кода
-- аддона, и всегда.
--
-- И ОТКАЗ БЫЛО НЕЧЕМ ЗАМЕТИТЬ, ЧТО ХУЖЕ САМОЙ БЛОКИРОВКИ. Заблокированный
-- вызов не бросает ошибку Lua: игра просто его не делает. Поэтому pcall
-- отвечал «получилось», адаптер отвечал «открыл», кнопка не исчезала, в чат не
-- писалось ничего, а в FOREVERPILOT_DIAG не появлялось ни ошибки, ни записи.
-- Снаружи это «нажимаю - ничего не происходит, и выскакивает окно про
-- блокировку», и так игрок это и описал.
--
-- ПОЭТОМУ ПРАВИЛО ТЕПЕРЬ ОДНО, И ОНО НЕ ЗАВИСИТ ОТ СОСТОЯНИЯ МИРА:
--   * функции клиента аддон не зовёт НИКОГДА и НИ ОДНИМ ПУТЁМ;
--   * кнопки показа рецепта нет НИ У ОДНОГО совета и ни на одной поверхности;
--   * вместо неё на экране стоит то, чего игроку и не хватало: какую профессию
--     открыть, что в ней найти и в каком разделе.
--
-- Ловушка стоит на самой функции клиента (Tests/harness.lua,
-- env.G.C_TradeSkillUI.OpenRecipe) и отвечает так же, как ответила игра:
-- ничем. Кто бы её ни позвал - адаптер, кнопка, щелчок, панель - обращение
-- попадёт в env.openRecipeCalls, и этот список обязан остаться пустым.
--
-- Имени функции в коде аддона нет и быть не должно вовсе: это отдельная
-- проверка, по закрытому перечню защищённых вызовов - Tests/test_ui.lua,
-- «Загрузка: ни одного защищённого вызова игры».
local H = ...
local S = assert(loadfile((H.ROOT or ".") .. "/Tests/uistub.lua"))()

return function()

-- Подписи, которых на экране быть не должно ни в одном состоянии мира.
local LABELS = { ["Показать рецепт"] = true, ["Показать формулу"] = true }

local function fresh(prepare)
    local env = S.load(H)
    if prepare then prepare(env) end
    S.populate(env, H)
    return env
end

local function showNow(env)
    local ns = env.ns
    ns.MainFrame:Build()
    ns.MainFrame:Select("NOW")
    ns.MainFrame:RenderActive()
end

-- Строки списка, на которых сейчас лежит совет про рецепт.
local function recipeRows(env)
    local rows = {}
    for _, row in ipairs(env.ns.Card.pool) do
        local card = row.card
        if row.__shown and card and card.action and card.action.kind == "findRecipe" then
            rows[#rows + 1] = row
        end
    end
    return rows
end

local function recipeLabelsOnScreen(env, root)
    local labels = select(1, S.harvest(env.world, root or env.ns.MainFrame.frame))
    local n = 0
    for _, label in ipairs(labels) do
        if LABELS[S.plain(label)] then n = n + 1 end
    end
    return n
end

local function screenText(env, root)
    local _, texts = S.harvest(env.world, root or env.ns.MainFrame.frame)
    local plain = {}
    for i, t in ipairs(texts) do plain[i] = S.plain(t) end
    return table.concat(plain, "\n")
end

local function press(frame, ...)
    local handler = frame and frame.__scripts and frame.__scripts.OnClick
    if not handler then return false, "нет обработчика" end
    return pcall(handler, frame, ...)
end

local function calls(env) return #(env.openRecipeCalls or {}) end

local function saidAny(env, needle)
    for _, line in ipairs(env.said or {}) do
        if S.plain(line):find(needle, 1, true) then return line end
    end
    return nil
end

local function errorCount(env) return #(env.ns.Diag:Init().errors or {}) end

-- Поставить на панель совет с рецептом (листая «Дальше»), вернуть его.
local function panelOnRecipe(env)
    local ns = env.ns
    ns.Config:Get().panel.enabled = true
    ns.StepPanel:Build()
    ns.StepPanel:ApplyVisibility()
    ns.StepPanel:Render()
    for _ = 1, #(ns.ActionEngine.cards or {}) + 1 do
        local card = ns.StepPanel.current
        if card and card.action and card.action.kind == "findRecipe" then return card end
        if not ns.StepPanel:Advance() then break end
    end
    local card = ns.StepPanel.current
    if card and card.action and card.action.kind == "findRecipe" then return card end
    return nil
end

local function tipLines(env, frame)
    local tips = {}
    env.G.GameTooltip.AddLine = function(_, text) tips[#tips + 1] = S.plain(text) end
    env.G.GameTooltip.AddDoubleLine = function(_, a, b)
        tips[#tips + 1] = S.plain(a) .. " " .. S.plain(b)
    end
    local enter = frame and frame.__scripts and frame.__scripts.OnEnter
    if enter then pcall(enter, frame) end
    return table.concat(tips, "\n")
end

-- САМА ЛОВУШКА. Без этой проверки все «клиент не тронут» ниже проверяли бы
-- пустоту: сломайся подмена в стенде - и список обращений останется пустым
-- просто потому, что записывать его стало нечем.
H.suite("Рецепт: ловушка на функции клиента работает")
do
    local env = fresh()
    H.ok(type(env.G.C_TradeSkillUI) == "table", "C_TradeSkillUI в песочнице есть")
    H.ok(type(env.G.C_TradeSkillUI.OpenRecipe) == "function",
        "и функция открытия рецепта в нём подменена")
    H.eq(calls(env), 0, "до вызова список обращений пуст")
    env.G.C_TradeSkillUI.OpenRecipe(4242)
    H.eq(calls(env), 1, "прямой вызов ловушкой замечен")
    H.eq(env.openRecipeCalls[1], 4242, "и записан с тем самым номером рецепта")
    -- Ответ как у заблокированного вызова: ни значения, ни ошибки.
    local ok, answer = pcall(env.G.C_TradeSkillUI.OpenRecipe, 1)
    H.eq(ok, true, "заблокированный вызов не бросает ошибку — он просто ничего не делает")
    H.eq(answer, nil, "и ничего не возвращает")
    env.openRecipeCalls = {}
    H.eq(calls(env), 0, "список можно обнулить перед наблюдением")
end

-- АДАПТЕР: ФУНКЦИИ ПОКАЗА РЕЦЕПТА В НЁМ НЕТ ВОВСЕ -------------------------
--
-- Это главное изменение, и проверяется оно у настоящего адаптера, а не у
-- подмены: ни вызова, ни проверки наличия, ни «а можно ли сейчас». Пока такая
-- функция существует, её кто-нибудь позовёт.
H.suite("Адаптер: показа рецепта в нём больше нет ни в каком виде")
do
    local env = H.load()
    local Api = env.ns.Api
    for _, name in ipairs({ "ShowRecipe", "HasOpenRecipe", "ProfessionsUILoaded" }) do
        H.eq(Api[name], nil, "Api:" .. name .. " больше не существует")
    end
    -- И в таблице обнаружения функций клиента её тоже нет: даже проверка
    -- наличия - это повод кого-то потом её позвать.
    Api:Detect()
    H.eq(Api.has.openRecipe, nil, "адаптер не ищет функцию открытия рецепта")
    local detected = env.ns.Diag:Init().detect or {}
    H.eq(detected["C_TradeSkillUI.OpenRecipe"], nil,
        "и в диагностике её наличия нет: не искали — не записали")
    -- А соседние, читающие, на месте: убрали ровно одну функцию.
    --
    -- Разница между «искали и не нашли» и «не искали» здесь и проверяется:
    -- у искомого имени в Api.has есть ключ (true или false), у неискомого
    -- ключа нет вовсе. Если бы открытие рецепта просто перестало находиться
    -- на этом клиенте, ключ остался бы - со значением false.
    H.ok(Api.has.recipeInfo ~= nil, "чтение рецепта адаптер по-прежнему ищет")
    H.ok(Api.has.recipeSchematic ~= nil, "и состав рецепта тоже")
    H.ok(Api.has.openRecipe == nil, "а открытие рецепта не ищет вовсе")
    local missing = {}
    for _, key in ipairs(Api.missing or {}) do missing[key] = true end
    H.eq(missing.openRecipe, nil, "и в списке «чего нет» его тоже нет: не искали")
    H.eq(calls(env), 0, "клиент при обнаружении не тронут")
end

-- КНОПКИ НЕТ НИ В ОДНОМ СОСТОЯНИИ МИРА -------------------------------------

H.suite("Рецепт: кнопки показа нет ни у одного совета")
do
    local env = fresh()
    local ns = env.ns
    showNow(env)

    local rows = recipeRows(env)
    H.ok(#rows >= 2, "советов с рецептом на экране: " .. #rows)
    H.eq(ns.RecipeBook:ShowState().state, "none", "состояние одно: показывать нечем")
    H.eq(ns.RecipeBook:CanShow(), false, "показать рецепт нельзя")

    local drawn = 0
    for _, row in ipairs(rows) do
        if row.action.__shown then drawn = drawn + 1 end
    end
    H.eq(drawn, 0, "ни у одного такого совета кнопка не нарисована")
    H.eq(recipeLabelsOnScreen(env), 0,
        "подписей «Показать рецепт» и «Показать формулу» на экране нет")
    -- И ни у одного совета нет подписи действия: подпись есть - значит, где-то
    -- нарисуется кнопка.
    local labelled = {}
    for _, card in ipairs(ns.ActionEngine.cards or {}) do
        if card.action and card.action.kind == "findRecipe" and card.action.label then
            labelled[#labelled + 1] = tostring(card.title)
        end
    end
    H.eq(#labelled, 0, "у действия «найти рецепт» нет подписи кнопки"
        .. ((#labelled > 0) and ("  <- " .. table.concat(labelled, ", ")) or ""))
end

H.suite("Рецепт: клиент не зовётся ни одним путём")
do
    local env = fresh()
    local ns = env.ns
    showNow(env)
    local rows = recipeRows(env)
    H.ok(#rows >= 2, "советов с рецептом на экране: " .. #rows)
    env.said = {}

    -- 1. Щелчок по самой карточке.
    for _, row in ipairs(rows) do
        local ok, err = press(row, "LeftButton")
        H.ok(ok, "щелчок по карточке «" .. tostring(row.card.title) .. "» не падает",
            tostring(err))
    end
    H.eq(calls(env), 0, "щелчки по карточкам до клиента не дошли")

    -- 2. Нажатие «призрака»: кнопка скрыта, но обработчик у неё остался с
    --    прошлой отрисовки. Нажать его нельзя, а вызвать можно.
    for _, row in ipairs(rows) do
        local ok, err = press(row.action)
        H.ok(ok, "обработчик скрытой кнопки не падает", tostring(err))
    end
    H.eq(calls(env), 0, "обработчик скрытой кнопки до клиента не дошёл")

    -- 3. Прямой вызов действия совета.
    for _, card in ipairs(ns.ActionEngine.cards) do
        if card.action and card.action.kind == "findRecipe" then
            ns.Card.Activate(card)
        end
    end
    H.eq(calls(env), 0, "Card.Activate до клиента не дошёл")

    -- 4. Панель.
    local card = panelOnRecipe(env)
    H.ok(card ~= nil, "на панели совет с рецептом")
    local pf = ns.StepPanel.frame
    H.eq(S.plain(pf.action.text.__text or ""), "Открыть",
        "кнопка панели подписана «Открыть», а не показом рецепта")
    H.eq(recipeLabelsOnScreen(env, pf), 0, "на панели подписей показа рецепта нет")
    ns.MainFrame.frame:Hide()
    local ok, err = press(pf.action)
    H.ok(ok, "нажатие кнопки панели не падает", tostring(err))
    H.eq(calls(env), 0, "кнопка панели до клиента не дошла")
    H.eq(ns.MainFrame.frame:IsShown(), true, "и сделала то, что на ней написано: открыла окно")

    -- И игроку сказано словами, где рецепт искать.
    H.ok(saidAny(env, "айдите") ~= nil, "в чате сказано, что найти его надо самому")
    H.ok(saidAny(env, "ткройте") ~= nil, "и что для этого открыть")
    H.eq(errorCount(env), 0, "ошибок в диагностике нет")
end

H.suite("Рецепт: ни бой, ни чужое окно профессий ничего не меняют")
do
    -- Раньше от этих трёх условий зависело, можно ли звать клиент. Теперь
    -- нельзя никогда, и состояние на них не реагирует - проверяется, что ни
    -- одно из них не открывает лазейку.
    for _, case in ipairs({
        { name = "бой", prepare = function(e) e.inCombat = true end },
        { name = "окно профессий игрой загружено",
          prepare = function(e) e.G.ProfessionsFrame = {} end },
        { name = "клиент умеет открывать рецепт",
          prepare = function(e)
              e.G.C_AddOns = { IsAddOnLoaded = function() return true, true end }
          end },
    }) do
        local env = fresh(case.prepare)
        local ns = env.ns
        showNow(env)
        H.eq(ns.RecipeBook:ShowState().state, "none", case.name .. ": состояние то же")
        H.eq(ns.RecipeBook:CanShow(), false, case.name .. ": кнопки нет")
        H.eq(recipeLabelsOnScreen(env), 0, case.name .. ": подписей на экране нет")
        local rows = recipeRows(env)
        H.ok(#rows > 0, case.name .. ": советы с рецептом есть")
        for _, row in ipairs(rows) do press(row, "LeftButton"); press(row.action) end
        H.eq(calls(env), 0, case.name .. ": клиент не зовётся")
        H.eq(errorCount(env), 0, case.name .. ": ошибок в диагностике нет")
    end
end

-- ВМЕСТО КНОПКИ - СЛОВА, И ОНИ ПРО ЭТОТ РЕЦЕПТ ----------------------------

H.suite("Рецепт: сказано, какую профессию открыть и что в ней найти")
do
    local env = fresh()
    local ns = env.ns
    showNow(env)

    -- Строка строится по справочнику, а не по карточке: номер рецепта -> имя,
    -- профессия, раздел.
    local recipe
    for _, r in pairs(ns.RecipeBook.byID) do recipe = recipe or r end
    H.ok(recipe ~= nil, "в справочнике есть рецепт, про который можно сказать")
    local text = ns.RecipeBook:FindText(recipe.id)
    H.ok(type(text) == "string" and #text > 20, "строка есть: " .. tostring(text))
    H.ok(text:find(recipe.name, 1, true) ~= nil, "и в ней название рецепта")
    H.ok(text:find(ns.Util.profLabel(recipe.profession), 1, true) ~= nil,
        "и профессия, которую надо открыть")
    if recipe.categoryName then
        H.ok(text:find(recipe.categoryName, 1, true) ~= nil,
            "и раздел внутри профессии: " .. recipe.categoryName)
    else
        H.ok(true, "раздела у этого рецепта нет — и он не выдуман")
    end
    -- Про рецепт, которого в справочнике нет, не выдумывается ничего.
    H.eq(ns.RecipeBook:FindText(999999), nil, "про незнакомый рецепт — ничего")
    H.eq(ns.RecipeBook:FindText(nil), nil, "и без номера — тоже ничего")

    -- ЭТА СТРОКА СТОИТ ТАМ, ГДЕ НЕ ХВАТАЕТ КНОПКИ: в подсказке совета.
    local rows = recipeRows(env)
    local tip = tipLines(env, rows[1])
    local own = ns.RecipeBook:FindText(rows[1].card.action.recipeID)
    H.ok(own ~= nil, "у этого совета есть своя строка про его рецепт")
    H.ok(tip:find(S.plain(own), 1, true) ~= nil,
        "и она в подсказке именно этого совета: " .. tostring(own))
    H.ok(tip:find("Достоверность", 1, true) ~= nil,
        "и то, что про сам совет, в подсказке осталось")

    -- А длинного объяснения в подсказке нет: игрок прислал скриншот, где оно
    -- занимало пять строк поверх игровых данных о предмете.
    H.eq(tip:find(S.plain(ns.RecipeBook.NOTE), 1, true), nil,
        "длинного объяснения в подсказке совета нет")

    -- Щелчок по совету говорит то же самое, и ровно одной строкой.
    env.said = {}
    press(rows[1], "LeftButton")
    H.eq(#env.said, 1, "щелчок отвечает одной строкой")
    H.ok(S.plain(env.said[1] or ""):find(S.plain(own), 1, true) ~= nil,
        "и это та же строка, что в подсказке: " .. tostring(env.said[1]))
end

H.suite("Рецепт: своя строка у КАЖДОГО такого совета, а не только у первого")
do
    -- Раньше объяснение было одно на всех, и проверялось на первом совете.
    -- Строка теперь про конкретный рецепт, поэтому и проверяется у каждого:
    -- «у первого правильно» ничего не говорит об остальных.
    local env = fresh()
    local ns = env.ns
    showNow(env)
    local rows = recipeRows(env)
    H.ok(#rows >= 2, "советов с рецептом на экране: " .. #rows)
    for _, row in ipairs(rows) do
        local card = row.card
        local short = ns.Card.ActionNoteShort(card)
        local title = ns.Util.truncate(tostring(card.title), 26)
        H.ok(type(short) == "string" and #short > 20,
            "«" .. title .. "»: своя строка есть")
        H.eq(ns.Card.ActionReady(card), false,
            "«" .. title .. "»: кнопка не рисуется")
        H.eq(ns.StepPanel.HasOwnAction(card), false,
            "«" .. title .. "»: и на панели своей кнопки нет")
        H.ok(tipLines(env, row):find(S.plain(short), 1, true) ~= nil,
            "«" .. title .. "»: и строка стоит в подсказке этого совета")
    end
    H.eq(calls(env), 0, "и за весь обход клиент не тронут")
end

H.suite("Рецепт: объяснение не обещает кнопку и не висит над списком")
do
    local env = fresh()
    local ns = env.ns
    showNow(env)
    local note = ns.RecipeBook:ShowState().note
    H.ok(type(note) == "string" and #note > 20, "у состояния есть объяснение")
    H.ok(note:find("професси", 1, true) ~= nil, "объяснение называет окно профессий")
    -- КНОПКИ НЕ БУДЕТ НИКОГДА, И ОБЕЩАТЬ ЕЁ НЕЛЬЗЯ. Раньше текст говорил
    -- «откройте профессию один раз — и кнопка появится». Теперь это было бы
    -- обещание, которого аддон не выполнит ни при каком условии.
    H.eq(note:find("появ", 1, true), nil, "и не обещает, что кнопка появится")
    local short = ns.RecipeBook:ShowState().short
    H.ok(type(short) == "string" and #short > 20, "короткая форма есть: " .. tostring(short))
    H.eq(short:find("появ", 1, true), nil, "и она тоже ничего не обещает")
    H.ok(ns.Util.charLen(short) <= 90,
        "и она одной строкой (" .. ns.Util.charLen(short) .. " символов)")

    -- Над списком длинной инструкции нет - это перенос, а не потеря: игрок
    -- сказал про простыню над советами «кратко, понятно и без всяких хрени».
    H.eq(screenText(env):find(S.plain(note), 1, true), nil,
        "над списком длинной инструкции нет")
    -- А в подсказке панели она есть: там места хватает.
    local card = panelOnRecipe(env)
    H.ok(card ~= nil, "на панели совет с рецептом")
    H.ok(tipLines(env, ns.StepPanel.frame):find(S.plain(note), 1, true) ~= nil,
        "объяснение есть в подсказке панели")
end

-- ВИД ДЕЙСТВИЯ: ОДИН, И НИГДЕ НЕ ОСТАЛОСЬ ПРЕЖНЕГО ------------------------

H.suite("Рецепт: прежнего вида действия «открыть рецепт» в советах не осталось")
do
    local env = fresh()
    local ns = env.ns
    -- Все профили: ветки у них разные, и совет про рецепт строит не одна.
    local kinds, found = {}, 0
    for _, profile in ipairs(ns.PROFILE_ORDER or { "POWER" }) do
        ns.Config:SetProfile(profile)
        H.build(env)
        for _, card in ipairs(ns.ActionEngine.cards or {}) do
            local act = card.action
            if act and act.kind then
                kinds[act.kind] = (kinds[act.kind] or 0) + 1
                if act.kind == "findRecipe" then found = found + 1 end
            end
        end
    end
    H.eq(kinds.openRecipe, nil, "вида действия «openRecipe» больше нет ни у одного совета")
    H.ok(found > 0, "а советов с видом «findRecipe» построено: " .. found)
    H.eq(calls(env), 0, "и за весь перебор профилей клиент не тронут")
end

end
