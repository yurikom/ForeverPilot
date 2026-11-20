-- ForeverPilot / Tests/test_handoff.lua
--
-- КНОПКА «ИСКАТЬ НА АУКЦИОНЕ»: список покупок одним нажатием уходит в поиск
-- Auctionator.
--
-- У этой кнопки особая история. Текст под списком покупок обещал её -
-- «Открой аукцион и нажми „Искать на аукционе“» - когда самой кнопки не было
-- нигде: логику передачи написали, а кнопку к ней нет. Обещание тогда убрали, а
-- теперь кнопка сделана по-настоящему.
--
-- В ИГРЕ ЕЁ ПРОВЕРИТЬ НЕЛЬЗЯ, поэтому всё, что можно проверить без игры,
-- проверяется здесь, и правило у кнопки одно: ОНА ЕСТЬ ТОЛЬКО ТОГДА, КОГДА
-- НАЖАТИЕ ЗАВЕДОМО ИМЕЕТ СМЫСЛ. Нет Auctionator, нет в нём поиска списком,
-- закрыт аукцион, нечего искать, прошлый вызов не удался - кнопки нет вовсе, а
-- не «кнопка, которая отвечает ошибкой». Кнопка, которая ничего не делает, -
-- тот же дефект, что текст про кнопку, которой нет.
--
-- Что именно зовётся в Auctionator, сверено с исходником установленной версии
-- (Source/API/v1/MultiSearch.lua, версия 347): поиск требует открытого окна
-- аукциона и вкладки покупок AuctionatorTabs_Shopping, а имена в поиске не
-- должны содержать «;», «^» и не должны быть целиком в кавычках.
local H = ...
local S = assert(loadfile((H.ROOT or ".") .. "/Tests/uistub.lua"))()

return function()

local LABEL = "Искать на аукционе"

-- Мир с интерфейсом; всё, что аддон говорит в чат, записывается.
local function fresh()
    local env = S.load(H)
    env.said = {}
    local Api = env.ns.Api
    function Api:Print(msg) env.said[#env.said + 1] = tostring(msg) end
    S.populate(env, H)
    return env
end

-- Поддельный Auctionator ровно той формы, что у настоящего: таблица API.v1 с
-- функциями поиска, окно аукциона и вкладка покупок. Каждое обращение к нему
-- записывается - и вызовы, и попытки взять то, чего в нём нет.
--   opts.functions - какие функции поиска есть (по умолчанию все три)
--   opts.ahOpen    - открыт ли аукцион (по умолчанию да)
--   opts.legacy    - окно аукциона старого образца (AuctionFrame)
--   opts.tab       - есть ли вкладка покупок (по умолчанию да)
--   opts.throw     - текст ошибки, которой отвечает поиск
local function fakeAuctionator(env, opts)
    opts = opts or {}
    local seen = { calls = {}, touched = {} }
    local v1 = {}
    for _, name in ipairs(opts.functions
        or { "MultiSearchAdvanced", "MultiSearchExact", "MultiSearch" }) do
        v1[name] = function(caller, terms)
            seen.calls[#seen.calls + 1] = { fn = name, caller = caller, terms = terms }
            if opts.throw then error(opts.throw, 0) end
        end
    end
    setmetatable(v1, { __index = function(_, key)
        seen.touched[#seen.touched + 1] = tostring(key)
        return nil
    end })
    env.auctionator = true
    env.G.Auctionator = { API = { v1 = v1 } }

    local frameName = opts.legacy and "AuctionFrame" or "AuctionHouseFrame"
    local ah = env.world.newFrame("Frame", frameName)
    if opts.ahOpen == false then ah:Hide() else ah:Show() end
    env.G[frameName] = ah
    seen.ah = ah

    if opts.tab ~= false then
        env.G.AuctionatorTabs_Shopping = env.world.newFrame("Button", "AuctionatorTabs_Shopping")
    end
    return seen
end

local function showCraft(env)
    local ns = env.ns
    ns.MainFrame:Build()
    ns.MainFrame:Select("CRAFT")
    ns.MainFrame:RenderActive()
end

-- Кнопка на вкладке «Крафт», если она НА ЭКРАНЕ: показана сама и показано всё,
-- в чём она лежит. Скрытая кнопка из пула виджетов кнопкой на экране не
-- считается - нажать её нельзя.
local function handoffButton(env)
    local ns = env.ns
    local labels = select(1, S.harvest(env.world, ns.MainFrame.frame))
    local onScreen = false
    for _, label in ipairs(labels) do
        if S.plain(label) == LABEL then onScreen = true end
    end
    if not onScreen then return nil end
    for _, frame in ipairs(env.world.frames) do
        if frame.__type == "Button" and frame.__shown
            and S.descends(frame, ns.MainFrame.frame) then
            local fs = rawget(frame, "text")
            if type(fs) == "table" and S.plain(fs.__text or "") == LABEL then
                return frame
            end
        end
    end
    return nil
end

local function press(button)
    local handler = button and button.__scripts and button.__scripts.OnClick
    if not handler then return false, "у кнопки нет обработчика" end
    return pcall(handler, button)
end

-- Все тексты вкладки одной строкой - чтобы проверить, что именно сказано.
local function craftText(env)
    local _, texts = S.harvest(env.world, env.ns.MainFrame.frame)
    local plain = {}
    for i, t in ipairs(texts) do plain[i] = S.plain(t) end
    return table.concat(plain, "\n")
end

local function saidAny(env, needle)
    for _, line in ipairs(env.said or {}) do
        if S.plain(line):find(needle, 1, true) then return line end
    end
    return nil
end

local function errorCount(env)
    return #(env.ns.Diag:Init().errors or {})
end

-- ГЛАВНОЕ: БЕЗ AUCTIONATOR КНОПКИ НЕТ -----------------------------------

H.suite("Кнопка «Искать на аукционе»: без Auctionator её нет")
do
    local env = fresh()
    local ns = env.ns
    env.auctionator = false
    env.G.Auctionator = nil
    H.build(env)
    showCraft(env)

    H.eq(handoffButton(env), nil, "кнопки на вкладке «Крафт» нет")
    local state = ns.ShoppingList:HandoffState()
    H.eq(state, "none", "состояние передачи: Auctionator не загружен")
    local text = craftText(env)
    H.ok(text:find("Auctionator не загружен", 1, true) ~= nil,
        "и сказано почему: " .. (text:match("[^\n]*Auctionator[^\n]*") or "?"))
    H.ok(text:find("«" .. LABEL .. "»", 1, true) == nil,
        "текст не называет кнопку, которой нет")

    -- Даже с открытым аукционом и вкладкой покупок: без самого Auctionator
    -- передавать некуда.
    local ah = env.world.newFrame("Frame", "AuctionHouseFrame")
    ah:Show()
    env.G.AuctionHouseFrame = ah
    env.G.AuctionatorTabs_Shopping = env.world.newFrame("Button", "AuctionatorTabs_Shopping")
    showCraft(env)
    H.eq(handoffButton(env), nil, "и с открытым аукционом её тоже нет")

    -- И прямой вызов ничего не ломает: отказ словами, без ошибки.
    local before = errorCount(env)
    local ok, message = ns.ShoppingList:SendToAuctionator()
    H.eq(ok, false, "прямой вызов передачи отвечает отказом")
    H.ok(type(message) == "string" and message ~= "", "и объясняет: " .. tostring(message))
    H.eq(errorCount(env), before, "ошибок в диагностике не прибавилось")
end

-- КАЖДОЕ УСЛОВИЕ ПО ОТДЕЛЬНОСТИ -----------------------------------------

H.suite("Кнопка «Искать на аукционе»: нет ни одного условия — нет кнопки")
do
    -- Все условия, без которых нажатие бессмысленно. В каждой строке не хватает
    -- ровно одного; кнопки быть не должно ни в одной.
    local CASES = {
        { name = "в Auctionator нет поиска списком", state = "partial",
          opts = { functions = {} } },
        { name = "аукцион закрыт", state = "closed",
          opts = { ahOpen = false } },
        { name = "окна аукциона нет вовсе", state = "closed",
          opts = {}, after = function(env) env.G.AuctionHouseFrame = nil end },
        { name = "нет вкладки покупок Auctionator", state = "partial",
          opts = { tab = false } },
        { name = "в списке нечего искать на аукционе", state = "nothing",
          opts = {}, after = function(env)
              env.ns.ShoppingList.Lines = function() return {} end
          end },
    }
    for _, case in ipairs(CASES) do
        local env = fresh()
        local ns = env.ns
        local seen = fakeAuctionator(env, case.opts)
        if case.after then case.after(env) end
        showCraft(env)

        H.eq(handoffButton(env), nil, case.name .. ": кнопки нет")
        local state, note = ns.ShoppingList:HandoffState()
        H.eq(state, case.state, case.name .. ": состояние «" .. tostring(state) .. "»")
        H.ok(type(note) == "string" and note ~= "",
            case.name .. ": причина сказана — " .. tostring(note))
        H.ok(not tostring(note):find("«" .. LABEL .. "»", 1, true),
            case.name .. ": текст не называет кнопку, которой нет")
        H.eq(#seen.calls, 0, case.name .. ": Auctionator не тронут")

        -- И прямой вызов в таком состоянии - отказ, а не обращение к API.
        local before = errorCount(env)
        local ok = ns.ShoppingList:SendToAuctionator()
        H.eq(ok, false, case.name .. ": прямой вызов передачи отвечает отказом")
        H.eq(#seen.calls, 0, case.name .. ": и до Auctionator не доходит")
        H.eq(errorCount(env), before, case.name .. ": ошибок не прибавилось")
    end
end

H.suite("Кнопка «Искать на аукционе»: игра говорит «аукцион открыт», а окна нет")
do
    -- Чего нельзя проверить без игры: какое окно аукциона на этом клиенте.
    -- Auctionator ищет только в двух - нового и старого образца. Если событие
    -- «аукцион открыт» пришло, а ни одного из них нет, кнопка не появится
    -- никогда, и текст «когда откроете аукцион, появится кнопка» стал бы
    -- обещанием, которое нельзя выполнить.
    local env = fresh()
    local ns = env.ns
    local seen = fakeAuctionator(env, { ahOpen = false })
    env.G.AuctionHouseFrame = nil
    ns.AuctionMoment.atAuction = true
    showCraft(env)

    H.eq(handoffButton(env), nil, "кнопки нет")
    local state, note = ns.ShoppingList:HandoffState()
    H.eq(state, "partial", "состояние: передать некуда")
    H.ok(not tostring(note):find("появится кнопка", 1, true),
        "и кнопка не обещана: " .. tostring(note))
    H.eq(#seen.calls, 0, "Auctionator не тронут")

    -- Аукцион закрыли - снова обычное «когда откроете».
    ns.AuctionMoment.atAuction = false
    local state2, note2 = ns.ShoppingList:HandoffState()
    H.eq(state2, "closed", "аукцион закрыт — состояние «закрыт»")
    H.ok(tostring(note2):find("Когда откроете аукцион", 1, true) ~= nil,
        "и сказано, когда кнопка появится")
end

-- ВСЁ НА МЕСТЕ: КНОПКА ЕСТЬ И РАБОТАЕТ ----------------------------------

H.suite("Кнопка «Искать на аукционе»: всё на месте — кнопка есть и передаёт список")
do
    local env = fresh()
    local ns = env.ns
    local seen = fakeAuctionator(env)
    H.build(env)
    showCraft(env)

    local state = ns.ShoppingList:HandoffState()
    H.eq(state, "ready", "состояние передачи: готово")
    local button = handoffButton(env)
    H.ok(button ~= nil, "кнопка «" .. LABEL .. "» на вкладке «Крафт» есть")

    -- Что уйдёт в поиск: то, что аддон сам называет позициями для аукциона.
    local items = ns.ShoppingList:AuctionItems()
    H.ok(#items > 0, "позиций для аукциона: " .. #items)

    env.said = {}
    local before = errorCount(env)
    local ok, err = press(button)
    H.ok(ok, "нажатие не падает", tostring(err))
    H.eq(errorCount(env), before, "ошибок в диагностике не прибавилось")
    H.eq(#seen.calls, 1, "Auctionator вызван ровно один раз")

    local call = seen.calls[1]
    if call then
        H.eq(call.fn, "MultiSearchAdvanced", "выбран поиск с точным именем и количеством")
        H.eq(call.caller, "ForeverPilot", "аддон назвал себя своим именем")
        H.eq(type(call.terms), "table", "передан список")
        H.eq(#call.terms, #items, "позиций передано столько же, сколько в списке: " .. #items)
        for i, term in ipairs(call.terms) do
            local item = items[i]
            H.eq(type(term), "table", "позиция " .. i .. " — запись, а не строка")
            if type(term) == "table" and item then
                H.eq(term.searchString, item.name, "имя: " .. tostring(item.name))
                H.eq(term.isExact, true, "поиск точный")
                H.eq(term.quantity, item.qty, "количество: " .. tostring(item.qty))
                -- Auctionator отвергает запись с любым лишним видом значения.
                for key, value in pairs(term) do
                    local kind = type(value)
                    H.ok(type(key) == "string"
                        and (kind == "string" or kind == "number" or kind == "boolean"),
                        "поле «" .. tostring(key) .. "» допустимого вида")
                end
            end
        end
    end
    H.ok(saidAny(env, "Auctionator") ~= nil,
        "в чате сказано, что список передан: " .. tostring(env.said[1]))

    -- Ничего, кроме поиска: аддон не покупает, не выставляет и не создаёт
    -- списков втихую.
    H.eq(#seen.touched, 0, "никаких других функций Auctionator не тронуто"
        .. ((#seen.touched > 0) and (": " .. table.concat(seen.touched, ", ")) or ""))

    -- Кнопка остаётся: искать можно ещё раз.
    showCraft(env)
    H.ok(handoffButton(env) ~= nil, "после удачной передачи кнопка на месте")
end

H.suite("Кнопка «Искать на аукционе»: работает и с окном аукциона старого образца")
do
    local env = fresh()
    local seen = fakeAuctionator(env, { legacy = true })
    H.build(env)
    showCraft(env)
    local button = handoffButton(env)
    H.ok(button ~= nil, "кнопка есть")
    press(button)
    H.eq(#seen.calls, 1, "поиск вызван")
end

H.suite("Кнопка «Искать на аукционе»: берётся тот поиск, который в Auctionator есть")
do
    -- Версии Auctionator разные. Берётся лучшее из того, что на месте: поиск с
    -- количеством, затем точный, затем простой. Имена во всех случаях обычные.
    local ROUTES = {
        { functions = { "MultiSearchExact", "MultiSearch" }, want = "MultiSearchExact" },
        { functions = { "MultiSearch" }, want = "MultiSearch" },
    }
    for _, route in ipairs(ROUTES) do
        local env = fresh()
        local ns = env.ns
        local seen = fakeAuctionator(env, { functions = route.functions })
        H.build(env)
        showCraft(env)
        local button = handoffButton(env)
        H.ok(button ~= nil, route.want .. ": кнопка есть")
        press(button)
        H.eq(#seen.calls, 1, route.want .. ": вызван один раз")
        local call = seen.calls[1]
        if call then
            H.eq(call.fn, route.want, "выбрана функция " .. route.want)
            local items = ns.ShoppingList:AuctionItems()
            H.eq(#call.terms, #items, "позиций: " .. #items)
            for i, term in ipairs(call.terms) do
                H.eq(term, items[i] and items[i].name,
                    "позиция " .. i .. " — имя строкой: " .. tostring(term))
            end
        end
    end
end

-- ЧТО ПОПАДАЕТ В ПОИСК ---------------------------------------------------

H.suite("Передача в Auctionator: что уходит в поиск, а что нет")
do
    local env = fresh()
    local ns = env.ns
    fakeAuctionator(env)
    ns.ShoppingList.Lines = function()
        return {
            { itemID = 1, name = "Рунная ткань", qty = 12, src = "auctionator", buyable = true },
            { itemID = 2, name = "Тонкая нить", qty = 4, src = "vendor", buyable = true },
            { itemID = 3, name = ns.Util.itemFallbackName(3), qty = 1, src = "none" },
            { itemID = 4, name = "Странная; вещь", qty = 2, src = "auctionator" },
            { itemID = 5, name = "Пыль^2", qty = 2, src = "auctionator" },
            { itemID = 6, name = "\"В кавычках\"", qty = 2, src = "auctionator" },
            { itemID = 7, name = "Магическая пыль", qty = 0, src = "auctionator" },
            { itemID = 8, name = "Без цены", qty = 3, src = "none" },
            { itemID = 9, name = "", qty = 3, src = "auctionator" },
        }
    end
    local items, skipped = ns.ShoppingList:AuctionItems()
    local names = {}
    for i, item in ipairs(items) do names[i] = item.name .. " x" .. tostring(item.qty) end
    H.eq(table.concat(names, " | "), "Рунная ткань x12 | Без цены x3",
        "в поиск идут позиции с настоящим именем, которые не дешевле у торговца")
    H.eq(type(skipped), "table", "пропущенные посчитаны по причинам")
    if type(skipped) == "table" then
        H.eq(skipped.vendor, 1, "у торговца дешевле: 1 (её незачем искать на аукционе)")
        H.eq(skipped.unnamed, 2, "без настоящего имени: 2 (искать нечего)")
        H.eq(skipped.unsafe, 3, "с «;», «^» или в кавычках: 3 (Auctionator такие отвергает)")
        H.eq(skipped.zero, 1, "с нулевым количеством: 1")
    end
end

-- АУКЦИОН ЗАКРЫЛИ, А КНОПКА ЕЩЁ НА ЭКРАНЕ --------------------------------

H.suite("Кнопка «Искать на аукционе»: аукцион закрыли раньше, чем окно перерисовалось")
do
    -- Перерисовка идёт с задержкой, так что между закрытием аукциона и
    -- исчезновением кнопки есть миг, когда её ещё можно нажать. Нажатие в этот
    -- миг не должно ни звать Auctionator, ни считаться его отказом.
    local env = fresh()
    local ns = env.ns
    local seen = fakeAuctionator(env)
    H.build(env)
    showCraft(env)
    local button = handoffButton(env)
    H.ok(button ~= nil, "кнопка есть, пока аукцион открыт")

    seen.ah:Hide()
    env.said = {}
    local before = errorCount(env)
    local ok, err = press(button)
    H.ok(ok, "нажатие не падает", tostring(err))
    H.eq(#seen.calls, 0, "Auctionator не вызван")
    H.eq(errorCount(env), before, "ошибок не прибавилось")
    H.ok(#env.said > 0, "игроку сказано, что произошло: " .. tostring(env.said[1]))
    H.eq(handoffButton(env), nil, "и кнопка сразу убрана")

    -- Это не поломка: аукцион откроют снова - кнопка вернётся.
    seen.ah:Show()
    showCraft(env)
    H.ok(handoffButton(env) ~= nil, "аукцион открыли снова — кнопка вернулась")
end

-- AUCTIONATOR ОТВЕТИЛ ОШИБКОЙ -------------------------------------------

H.suite("Кнопка «Искать на аукционе»: Auctionator ответил ошибкой — кнопка убрана")
do
    local env = fresh()
    local ns = env.ns
    local seen = fakeAuctionator(env, {
        throw = "Contact the maintainer of ForeverPilot to resolve this problem."
            .. " Details: Usage Auctionator.API.v1.MultiSearchAdvanced",
    })
    H.build(env)
    showCraft(env)
    local button = handoffButton(env)
    H.ok(button ~= nil, "кнопка есть")

    env.said = {}
    local ok, err = press(button)
    H.ok(ok, "ошибка Auctionator не вышла наружу", tostring(err))
    H.eq(#seen.calls, 1, "вызов был один")
    H.ok(#env.said > 0, "игроку сказано словами: " .. tostring(env.said[1]))
    H.eq(saidAny(env, "attempt to"), nil, "без сырого текста ошибки Lua")
    H.eq(saidAny(env, "Contact the maintainer"), nil,
        "и без английской фразы из чужого аддона")

    -- Кнопки больше нет: второй раз в ту же ошибку игрок не упрётся.
    H.eq(handoffButton(env), nil, "кнопка убрана")
    local state, note = ns.ShoppingList:HandoffState()
    H.eq(state, "broken", "состояние: передача не удалась")
    H.ok(type(note) == "string" and note ~= "", "и под списком сказано почему: " .. tostring(note))
    showCraft(env)
    H.eq(handoffButton(env), nil, "и после перерисовки её нет")
    ns.ShoppingList:SendToAuctionator()
    H.eq(#seen.calls, 1, "повторный прямой вызов до Auctionator не доходит")

    -- Что именно ответил Auctionator, записано в диагностику - там, где это
    -- прочтёт тот, кто будет чинить, а не игрок.
    local found
    for _, e in ipairs(ns.Diag:Init().log or {}) do
        if tostring(e.text):find("Auctionator не принял список", 1, true) then found = e end
    end
    H.ok(found ~= nil, "в журнале диагностики запись про отказ")
    H.ok(found and type(found.detail) == "table"
        and tostring(found.detail.error):find("MultiSearchAdvanced", 1, true) ~= nil,
        "и в ней дословный ответ Auctionator")
end

-- ВКЛАДКА ОТКРЫТА, А АУКЦИОН ОТКРЫЛИ ПОТОМ --------------------------------

H.suite("Кнопка «Искать на аукционе»: появляется и пропадает вместе с аукционом, без переключения вкладок")
do
    -- Самый обычный порядок действий: окно аддона открыто на вкладке «Крафт»,
    -- игрок подходит к аукциону. Кнопка обязана появиться сама - пересчёт после
    -- открытия аукциона перерисовывает активную вкладку. У вкладки «Крафт»
    -- перерисовки по пересчёту не было вовсе: она обновлялась только когда на
    -- неё переключались, так что и кнопка, и суммы в списке покупок оставались
    -- бы прежними, пока игрок не уйдёт с вкладки и не вернётся.
    local env = fresh()
    local ns = env.ns
    local seen = fakeAuctionator(env, { ahOpen = false })
    H.build(env)
    showCraft(env)
    H.eq(handoffButton(env), nil, "аукцион закрыт — кнопки нет")

    -- Аукцион открыли. Дальше - только то, что делает сам аддон по событию:
    -- пересчёт и перерисовка активной вкладки. Никаких переключений.
    seen.ah:Show()
    ns.MainFrame:RebuildCards()
    H.ok(handoffButton(env) ~= nil, "аукцион открыли — кнопка появилась сама")

    seen.ah:Hide()
    ns.MainFrame:RebuildCards()
    H.eq(handoffButton(env), nil, "аукцион закрыли — кнопка сама пропала")

    -- И то же через простую перерисовку, без пересборки советов.
    seen.ah:Show()
    ns.MainFrame:Refresh()
    H.ok(handoffButton(env) ~= nil, "и по простой перерисовке окна — тоже")
end

H.suite("Вкладка «Крафт»: список покупок не остаётся вчерашним после пересчёта")
do
    -- Та же причина, другой симптом: без перерисовки по пересчёту строка
    -- «Итого» под списком покупок показывала бы суммы на момент, когда на
    -- вкладку зашли, сколько бы пересчётов с тех пор ни прошло.
    local env = fresh()
    local ns = env.ns
    showCraft(env)
    -- Только сама вкладка, без заголовка и строки состояния окна: те
    -- обновляются своим путём и изменились бы в любом случае.
    local function tabText()
        local _, texts = S.harvest(env.world, ns.TabCraft.frame)
        local plain = {}
        for i, t in ipairs(texts) do plain[i] = S.plain(t) end
        return table.concat(plain, "\n")
    end
    local before = tabText()
    H.ok(before:find("Общий список покупок", 1, true) ~= nil, "список покупок на вкладке есть")
    local totalBefore = before:match("Итого[^\n]*\n([^\n]*)") or before

    -- Цена материала изменилась (игрок был у аукциона), советы пересчитаны.
    env.prices[2589] = 5000
    if ns.Api.ClearAuctionCache then ns.Api:ClearAuctionCache("тест") end
    ns.MainFrame:RebuildCards()
    local after = tabText()
    H.ok(after ~= before, "после пересчёта содержимое вкладки изменилось вместе с ценами")
end

H.suite("Передача в Auctionator: в бою не делается")
do
    local env = fresh()
    local ns = env.ns
    local seen = fakeAuctionator(env)
    H.build(env)
    env.inCombat = true
    local ok, message = ns.ShoppingList:SendToAuctionator()
    H.eq(ok, false, "в бою передача отвечает отказом")
    H.eq(#seen.calls, 0, "Auctionator не вызван")
    H.ok(type(message) == "string" and message ~= "", "сказано почему: " .. tostring(message))
    -- И это не поломка: бой кончится - всё как было.
    env.inCombat = false
    H.eq(ns.ShoppingList:HandoffState(), "ready", "после боя передача снова готова")
end

end
