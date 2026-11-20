-- ForeverPilot / Tests/test_vanish.lua
--
-- ВСЕ ПУТИ, КОТОРЫМИ СОВЕТ МОЖЕТ ПРОПАСТЬ С ГЛАЗ. Перечень и проверка на каждый.
--
-- Это сквозная беда одного дня. Игрок трижды оставался без советов и каждый
-- раз решал, что аддон сломан, и каждый раз находился ещё один путь:
--
--   1. правый щелчок по совету в списке прятал его с одного раза;
--   2. «Дальше» на панели откладывала совет на час;
--   3. левый щелчок по информационному совету прятал его - без кнопки и без
--      подписи;
--   4. правый щелчок по панели прятал совет с одного раза.
--
-- Латать их по одному можно бесконечно. Поэтому здесь не четыре проверки на
-- четыре найденных пути, а ПЕРЕЧЕНЬ: все места в коде, которые умеют спрятать
-- совет, и все обработчики, через которые игрок до них добирается. Перечень
-- закрытый: новый путь нельзя добавить, не вписав его сюда, - набор упадёт.
--
-- ЧТО ЗНАЧИТ «ПРОПАСТЬ». Причин три, и они разные:
--
--   А. СКРЫТ. Совет записан в список скрытых и не показывается, пока не выйдет
--      срок. Единственное действие, которое это делает, - ДВА правых щелчка
--      подряд по совету: в списке (на сутки) или на панели (на час). Первый
--      щелчок только спрашивает, любое другое действие вопрос снимает.
--   Б. НЕ ПОКАЗАН ПО ВЫБОРУ ИГРОКА. Фильтр над списком, профиль приоритетов и
--      порог мелкой денежной выгоды. Совет никуда не записан и вернётся тем же
--      щелчком, но на экране обязано быть сказано, сколько советов не показано
--      и почему, - иначе это выглядит так же, как пропажа.
--   В. НЕ ПОМЕСТИЛСЯ. Список ограничен по длине; если советов больше, об этом
--      тоже обязано быть сказано на экране.
--
-- Отдельно - Г: пропал не совет, а экран (панель убрана, окно закрыто). Советы
-- при этом целы; что экран можно вернуть, проверяет Tests/test_text.lua.
local H = ...
local S = assert(loadfile((H.ROOT or ".") .. "/Tests/uistub.lua"))()
local D = assert(loadfile((H.ROOT or ".") .. "/Tests/dialect.lua"))()

return function()

local ROOT = H.ROOT or "."

-- Мир с интерфейсом; всё, что аддон говорит в чат, записывается.
local function fresh()
    local env = S.load(H)
    env.said = {}
    local Api = env.ns.Api
    function Api:Print(msg) env.said[#env.said + 1] = tostring(msg) end
    S.populate(env, H)
    return env
end

local function hiddenCount(env)
    return env.ns.Config:DismissedCount(env.Api:ServerTime())
end

local function hiddenRecords(env)
    local n = 0
    for _ in pairs(env.ns.Config:Get().dismissed or {}) do n = n + 1 end
    return n
end

-- Докрутить отложенные вызовы: скрытие однажды уже пряталось за таймером.
local function drainTimers(env)
    for _ = 1, 4 do
        local timers = env.pendingTimers or {}
        env.pendingTimers = {}
        for _, fn in ipairs(timers) do pcall(fn) end
        for _, fn in ipairs(env.pendingTickers or {}) do pcall(fn) end
    end
end

-- Окно со всеми вкладками, панель, кнопка у миникарты и стрелка - всё, на что
-- игрок может нажать.
local function buildEverything(env)
    local ns = env.ns
    ns.Config:Get().panel.enabled = true
    ns.Config:Get().ui.minimapButton = true
    ns.Config:ClearDismissed()
    ns.MainFrame:Build()
    ns.MainFrame:ApplyMinimapButton()
    for _, def in ipairs(ns.MainFrame.TABS) do
        ns.MainFrame:Select(def.key)
        ns.MainFrame:RenderActive()
    end
    ns.MainFrame:Select("NOW")
    ns.MainFrame:RenderActive()
    ns.StepPanel:ApplyVisibility()
    H.build(env)
    ns.MainFrame:RenderActive()
    ns.StepPanel:Render()
    if ns.Arrow and ns.Arrow.Build then pcall(function() ns.Arrow:Build() end) end
end

-- А1. ПЕРЕЧЕНЬ МЕСТ В КОДЕ ----------------------------------------------
--
-- Цепочка от щелчка до записи в список скрытых. У каждого звена перечислено,
-- кто имеет право его звать. Появился новый вызывающий - значит, появился новый
-- путь спрятать совет, и набор об этом скажет раньше игрока.

-- Сколько раз образец встречается в коде каждого файла из .toc. Комментарии и
-- строки вырезаны: слово в пояснении - не вызов.
-- `accept` - необязательный отбор: получает то, что образец захватил, и решает,
-- считать ли находку.
local function occurrences(pattern, accept)
    local found = {}
    for _, rel in ipairs(assert(D.tocFiles(ROOT))) do
        local f = assert(io.open(ROOT .. "/" .. rel, "rb"))
        local code = D.stripped(f:read("*a"))
        f:close()
        local n = 0
        for capture in code:gmatch(pattern) do
            if (not accept) or accept(capture) then n = n + 1 end
        end
        if n > 0 then found[rel] = n end
    end
    return found
end

local function describe(found)
    local bits = {}
    for rel, n in pairs(found) do bits[#bits + 1] = rel .. " x" .. n end
    table.sort(bits)
    return (#bits > 0) and table.concat(bits, ", ") or "нигде"
end

local function sameSet(found, expected)
    for rel, n in pairs(expected) do
        if found[rel] ~= n then return false end
    end
    for rel in pairs(found) do
        if expected[rel] == nil then return false end
    end
    return true
end

H.suite("Перечень: кто в коде может спрятать совет")
do
    local CHAIN = {
        { what = "запись в список скрытых (присваивание срока)",
          -- `dismissed[ключ] = значение`. Присваивание nil - это возврат
          -- совета, а не скрытие, и в счёт не идёт.
          pattern = "dismissed%[[^%]]*%]%s*=%s*([%w_]+)",
          accept = function(value) return value ~= "nil" end,
          expected = { ["Core/Config.lua"] = 1 },
          why = "только Config:Dismiss" },
        { what = "вызов Config:Dismiss",
          pattern = "Config:Dismiss%(",
          -- одно объявление в Config.lua и один вызов в Dismissal.lua
          expected = { ["Core/Config.lua"] = 1, ["Logic/Dismissal.lua"] = 1 },
          why = "объявление и единственный вызов - из Dismissal:Hide" },
        { what = "вызов Dismissal:Hide (скрытие без вопроса)",
          pattern = "[%w_]+:Hide%(%s*card",
          expected = { ["Logic/Dismissal.lua"] = 2 },
          why = "объявление и второй шаг Dismissal:Request; интерфейс его не зовёт" },
        { what = "вызов Dismissal:Request (скрытие в два шага)",
          pattern = "[%w_]+:Request%(%s*card",
          expected = { ["Logic/Dismissal.lua"] = 1, ["UI/Card.lua"] = 1 },
          why = "объявление и вызов из Card.RequestDismiss" },
        { what = "вызов Card.RequestDismiss",
          pattern = "RequestDismiss%(",
          expected = { ["UI/Card.lua"] = 2, ["UI/StepPanel.lua"] = 1 },
          why = "объявление, правый щелчок по строке списка, правый щелчок по панели" },
        { what = "вызов Panel:Dismiss",
          pattern = "Panel:Dismiss%(",
          expected = { ["UI/StepPanel.lua"] = 2 },
          why = "объявление и правый щелчок по панели" },
    }
    for _, link in ipairs(CHAIN) do
        local found = occurrences(link.pattern, link.accept)
        H.ok(sameSet(found, link.expected), link.what .. ": " .. link.why
            .. " — найдено: " .. describe(found))
    end

    -- Скрытия одним движением в интерфейсе нет ни под каким именем.
    H.eq(describe(occurrences("Card%.Dismiss%f[^%w_]")), "нигде",
        "Card.Dismiss — скрытие в один шаг — из интерфейса убрано целиком")
    local env = fresh()
    H.eq(env.ns.Card.Dismiss, nil, "и в загруженном аддоне такой функции нет")

    -- ВЫКИДЫВАНИЕ ИЗ ГОТОВОГО СПИСКА - ТОЖЕ ПУТЬ ИСЧЕЗНОВЕНИЯ, И ОН СЧИТАННЫЙ.
    --
    -- Скрытие (выше) записывает совет в список скрытых; здесь другое - совет
    -- просто не доходит до экрана. Таких мест в движке ровно три, и каждое
    -- обязано говорить о себе строкой над списком:
    --   * профиль приоритетов (ns.PROFILE_EXCLUDE);
    --   * порог мелкой денежной выгоды (Engine:ApplyMoneyFloor);
    --   * обрезка списка по длине (ns.MAX_CARDS).
    -- Четвёртое появится - эта проверка упадёт раньше, чем игрок заметит, что
    -- советов стало меньше.
    for _, drop in ipairs({
        { what = "выкидывание карточек из готового списка",
          pattern = "self%.cards%s*=%s*kept",
          expected = { ["Logic/ActionEngine.lua"] = 2 },
          why = "ровно два: профиль приоритетов и порог мелкой денежной выгоды" },
        { what = "обрезка списка по длине",
          pattern = "self%.cards%s*=%s*trimmed",
          expected = { ["Logic/ActionEngine.lua"] = 1 },
          why = "одно: ns.MAX_CARDS" },
    }) do
        local found = occurrences(drop.pattern)
        H.ok(sameSet(found, drop.expected), drop.what .. ": " .. drop.why
            .. " — найдено: " .. describe(found))
    end

    -- Правый щелчок - единственная кнопка мыши, от которой идёт путь к
    -- скрытию: оба места, где зовётся скрытие, стоят под проверкой на неё.
    for _, rel in ipairs({ "UI/Card.lua", "UI/StepPanel.lua" }) do
        local f = assert(io.open(ROOT .. "/" .. rel, "rb"))
        local code = D.stripped(f:read("*a"))
        f:close()
        -- В вырезанном коде строки заменены пробелами, так что сравнение
        -- `button == "RightButton"` читается как `button ==   then`. Что это
        -- именно правая кнопка, проверяют наборы ниже - щелчками.
        local guarded, total = 0, 0
        for _ in code:gmatch("Dismiss%(") do total = total + 1 end
        for chunk in code:gmatch("if%s+button%s*==%s*then(.-)else") do
            for _ in chunk:gmatch("Dismiss%(") do guarded = guarded + 1 end
        end
        H.eq(guarded, 1, rel .. ": скрытие зовётся из обработчика щелчка в одном месте,"
            .. " под проверкой кнопки мыши")
    end
end

-- А2. ЩЁЛКАЕМ ПО ВСЕМУ --------------------------------------------------

-- Все обработчики, какие бывают у кадра, и с чем их зовёт клиент.
local SCRIPT_ARGS = {
    OnClick = { { "LeftButton" }, { "RightButton" }, { "MiddleButton" } },
    OnDoubleClick = { { "LeftButton" }, { "RightButton" } },
    OnMouseDown = { { "LeftButton" }, { "RightButton" } },
    OnMouseUp = { { "LeftButton" }, { "RightButton" } },
    OnMouseWheel = { { 1 }, { -1 } },
    OnDragStart = { {} },
    OnDragStop = { {} },
    OnKeyDown = { { "ESCAPE" }, { "ENTER" }, { "SPACE" } },
    OnValueChanged = { { 1.0 } },
    OnTextChanged = { {} },
    OnEnterPressed = { {} },
    OnEscapePressed = { {} },
    OnEditFocusGained = { {} },
    OnEditFocusLost = { {} },
    OnEnter = { {} },
    OnLeave = { {} },
    OnShow = { {} },
    OnHide = { {} },
    OnSizeChanged = { { 600, 400 } },
    OnUpdate = { { 0.1 } },
    OnEvent = {},   -- события проверяются отдельно, настоящими именами
}

local function labelOf(frame)
    for _, field in ipairs({ "text", "label" }) do
        local fs = rawget(frame, field)
        if type(fs) == "table" and fs.__text and fs.__text ~= "" then
            return S.plain(fs.__text)
        end
    end
    return frame.__name or frame.__type or "?"
end

H.suite("Щёлкаем по всему: ни один обработчик с одного раза ничего не прячет")
do
    local env = fresh()
    local ns = env.ns
    buildEverything(env)
    H.eq(hiddenCount(env), 0, "до начала скрытых нет")
    H.ok(#(ns.ActionEngine.cards or {}) >= 5,
        "советов в списке: " .. #(ns.ActionEngine.cards or {}))

    -- Все пары «кадр - обработчик» собираются ДО первого вызова: часть
    -- обработчиков перестраивает окно, а проверить надо всё, что было на экране.
    local work, unknown = {}, {}
    for _, frame in ipairs(env.world.frames) do
        for name, handler in pairs(frame.__scripts or {}) do
            if type(handler) == "function" then
                local argSets = SCRIPT_ARGS[name]
                if argSets == nil then
                    unknown[name] = true
                else
                    for _, args in ipairs(argSets) do
                        work[#work + 1] = { frame = frame, name = name,
                                            handler = handler, args = args }
                    end
                end
            end
        end
    end
    local unknownNames = {}
    for name in pairs(unknown) do unknownNames[#unknownNames + 1] = name end
    table.sort(unknownNames)
    H.eq(#unknownNames, 0, "все виды обработчиков известны этому набору"
        .. ((#unknownNames > 0) and ("  <- неизвестны: " .. table.concat(unknownNames, ", ")) or ""))
    H.ok(#work > 150, "обработчиков к проверке: " .. #work)

    local culprits, failed = {}, 0
    for _, item in ipairs(work) do
        -- Каждое нажатие - само по себе: вопрос «скрыть?» от прошлого снят.
        ns.Dismissal:Disarm()
        local ok = pcall(item.handler, item.frame, unpack(item.args))
        drainTimers(env)
        if not ok then failed = failed + 1 end
        if hiddenRecords(env) > 0 then
            culprits[#culprits + 1] = item.name .. "(" .. tostring(item.args[1] or "") .. ") на «"
                .. labelOf(item.frame) .. "»"
            ns.Config:ClearDismissed()
        end
    end
    H.eq(#culprits, 0, "ни одно одиночное действие не спрятало совет"
        .. ((#culprits > 0) and ("  <- прячут: " .. table.concat(culprits, "; ")) or ""))
    H.ok(failed < #work / 10, "обработчики в основном отработали без ошибок: упало "
        .. failed .. " из " .. #work)
end

H.suite("Два щелчка подряд: прячут только два ПРАВЫХ по совету — в списке и на панели")
do
    -- Положительная половина. Мир свежий: в строках списка настоящие советы.
    local env = fresh()
    local ns = env.ns
    buildEverything(env)

    -- 1. Каждая строка списка. Строки перебираются по номеру, а совет в строке
    --    читается заново перед каждым шагом: и вопрос «скрыть?», и само скрытие
    --    перерисовывают список, так что в строке каждый раз новая запись того же
    --    (или уже другого) совета.
    local function rowAt(index)
        local row = (ns.Card.pool or {})[index]
        if not (row and row:IsShown()) then return nil end
        return row, rawget(row, "card"), row.__scripts and row.__scripts.OnClick
    end
    local rows = 0
    for index = 1, #(ns.ActionEngine.cards or {}) do
        -- Исходное состояние перед каждой строкой: ничего не скрыто, список
        -- полный, вопросов нет.
        ns.Config:ClearDismissed()
        ns.Dismissal:Disarm()
        H.build(env)
        ns.MainFrame:RenderActive()

        local row, card, click = rowAt(index)
        if row and card and click and not card.blocking then
            rows = rows + 1
            local key, title = card.key, tostring(card.title):sub(1, 30)

            pcall(click, row, "LeftButton")
            pcall(click, row, "LeftButton")
            H.eq(hiddenRecords(env), 0, "список, «" .. title
                .. "»: два левых щелчка ничего не прячут")

            ns.Dismissal:Disarm()
            pcall(click, row, "RightButton")
            H.eq(hiddenRecords(env), 0, "…один правый — тоже")
            local _, again = rowAt(index)
            H.eq(again and again.key, key, "…и в строке после вопроса тот же совет")
            pcall(click, row, "RightButton")
            H.eq(ns.Config:IsDismissed(key, env.Api:ServerTime()), true,
                "…два правых подряд прячут именно этот совет")
            H.eq(hiddenRecords(env), 1, "…и только его")
            local expiry = ns.Config:Get().dismissed[key]
            H.eq(expiry and (expiry - env.Api:ServerTime()), ns.DISMISS_SECONDS,
                "…на сутки, как сказано в чате")
        end
    end
    ns.Config:ClearDismissed()
    ns.Dismissal:Disarm()
    H.ok(rows >= 3, "строк списка проверено: " .. rows)

    -- 2. Панель.
    H.build(env)
    ns.StepPanel.cursorKey, ns.StepPanel.cursorIndex = nil, 1
    ns.StepPanel:Render()
    local f = ns.StepPanel.frame
    local card = ns.StepPanel.current
    local click = f and f.__scripts and f.__scripts.OnClick
    H.ok(card ~= nil and not card.blocking and click ~= nil, "на панели обычный совет")
    if card and click then
        ns.Dismissal:Disarm()
        pcall(click, f, "RightButton")
        H.eq(hiddenRecords(env), 0, "панель: один правый щелчок ничего не прячет")
        ns.StepPanel.current = card
        pcall(click, f, "RightButton")
        H.eq(ns.Config:IsDismissed(card.key, env.Api:ServerTime()), true,
            "панель: два правых подряд прячут этот совет")
        local expiry = ns.Config:Get().dismissed[card.key]
        H.eq(expiry and (expiry - env.Api:ServerTime()), ns.SNOOZE_SECONDS,
            "…на час")
        ns.Config:ClearDismissed()
    end
end

H.suite("Два щелчка подряд по всему остальному ничего не прячут")
do
    -- Отрицательная половина: всё, кроме строк списка и самой панели. Двойной
    -- щелчок - самое частое случайное движение после одиночного.
    local env = fresh()
    local ns = env.ns
    buildEverything(env)

    local isRow = {}
    for _, row in ipairs(ns.Card.pool or {}) do isRow[row] = true end
    local panel = ns.StepPanel.frame

    local work = {}
    for _, frame in ipairs(env.world.frames) do
        local click = frame.__scripts and frame.__scripts.OnClick
        if type(click) == "function" and not isRow[frame] and frame ~= panel then
            work[#work + 1] = { frame = frame, click = click }
        end
    end
    H.ok(#work > 40, "элементов с обработчиком щелчка: " .. #work)

    local culprits = {}
    for _, item in ipairs(work) do
        for _, button in ipairs({ "LeftButton", "RightButton" }) do
            ns.Dismissal:Disarm()
            pcall(item.click, item.frame, button)
            pcall(item.click, item.frame, button)
            drainTimers(env)
            if hiddenRecords(env) > 0 then
                culprits[#culprits + 1] = button .. " x2 на «" .. labelOf(item.frame) .. "»"
                ns.Config:ClearDismissed()
            end
        end
    end
    H.eq(#culprits, 0, "двойной щелчок нигде, кроме совета, ничего не прячет"
        .. ((#culprits > 0) and ("  <- прячут: " .. table.concat(culprits, "; ")) or ""))
end

-- А3. БЕЗ ЕДИНОГО ЩЕЛЧКА -------------------------------------------------

H.suite("Без щелчков: события игры, таймеры и команды ничего не прячут")
do
    local env = fresh()
    local ns = env.ns
    local G = env.G
    G.SlashCmdList = {}
    G.GetMerchantNumItems = function() return 0 end
    local chunk = assert(loadfile(ROOT .. "/Main.lua"))
    setfenv(chunk, env.sandbox)
    chunk("ForeverPilot", ns)

    -- Настоящий вход в игру: аддон сам подписывается на события.
    local driver = G.ForeverPilotDriver
    local onEvent = driver and driver.__scripts and driver.__scripts.OnEvent
    H.ok(onEvent ~= nil, "обработчик событий есть")
    pcall(onEvent, driver, "ADDON_LOADED", "ForeverPilot")
    pcall(onEvent, driver, "PLAYER_LOGIN")
    H.eq(ns.Bootstrap.ready, true, "аддон запущен")
    S.populate(env, H)
    ns.Config:ClearDismissed()
    buildEverything(env)
    H.eq(hiddenRecords(env), 0, "после входа скрытых нет")

    -- 1. Все события, на которые аддон подписан, по три раза, с прогоном
    --    таймеров и планировщика пересчёта между ними.
    local events = {}
    for name in pairs(ns.Events.EVENT_MAP or {}) do events[#events + 1] = name end
    for name in pairs(ns.Events.SIGNAL_ONLY or {}) do events[#events + 1] = name end
    table.sort(events)
    H.ok(#events > 20, "событий к проверке: " .. #events)
    local culprits = {}
    for _, name in ipairs(events) do
        for _ = 1, 3 do
            pcall(onEvent, driver, name, 1, 2, 3)
            H.clock = (H.clock or 0) + 2
            if ns.Events.Tick then pcall(function() ns.Events:Tick() end) end
            drainTimers(env)
        end
        if hiddenRecords(env) > 0 then
            culprits[#culprits + 1] = name
            ns.Config:ClearDismissed()
        end
    end
    H.eq(#culprits, 0, "ни одно событие игры не спрятало совет"
        .. ((#culprits > 0) and ("  <- прячут: " .. table.concat(culprits, ", ")) or ""))

    -- 2. Бой, смена зоны, торговец, тренер, аукцион - сигналы самого аддона.
    for _, signal in ipairs({
        function() ns.MainFrame:OnCombat(true); ns.MainFrame:OnCombat(false) end,
        function() ns.MainFrame:OnZoneChanged() end,
        function() ns.Bootstrap:ReadMerchant() end,
        function() ns.Bootstrap:ReadTrainer() end,
        function() ns.AuctionMoment:OnAuction("open") end,
        function() ns.AuctionMoment:OnAuction("results") end,
        function() ns.AuctionMoment:OnAuction("close") end,
        function() ns.MainFrame:Rebuild(true) end,
        function() ns.MainFrame:RebuildCards() end,
        function() ns.MainFrame:Refresh() end,
        function() ns.Bootstrap:MaybeSnapshotPrices() end,
    }) do
        pcall(signal)
        drainTimers(env)
    end
    H.eq(hiddenRecords(env), 0, "бой, зона, торговец, тренер, аукцион, пересчёты — скрытых 0")

    -- 2а. Вход, который зовёт сам клиент, а не кадр аддона: пункт в меню
    --     аддонов у миникарты. Обработчиком кадра он не является, поэтому в
    --     наборе «щёлкаем по всему» его нет - проверяется отдельно.
    local compartment = G.ForeverPilot_OnAddonCompartmentClick
    H.ok(type(compartment) == "function", "пункт в меню аддонов есть")
    if type(compartment) == "function" then
        for _ = 1, 3 do
            pcall(compartment, "ForeverPilot", "LeftButton")
            pcall(compartment, "ForeverPilot", "RightButton")
            drainTimers(env)
        end
        H.eq(hiddenRecords(env), 0, "щелчки по пункту в меню аддонов — скрытых 0")
    end

    -- 3. Все команды. Среди них нет ни одной, которая прячет: есть только те,
    --    что возвращают.
    local slash = G.SlashCmdList.FOREVERPILOT
    H.ok(slash ~= nil, "команда зарегистрирована")
    local commands = { "", "now", "char", "craft", "config", "scan", "panel", "panel on",
        "panel off", "panel", "show", "undo", "hidden", "reset", "api", "diag",
        "diag full", "diag reset", "сила", "прокачка", "экономия", "заработок",
        "hide", "скрыть", "dismiss", "next", "дальше", "абракадабра" }
    culprits = {}
    for _, cmd in ipairs(commands) do
        pcall(slash, cmd)
        drainTimers(env)
        if hiddenRecords(env) > 0 then
            culprits[#culprits + 1] = "/fp " .. cmd
            ns.Config:ClearDismissed()
        end
    end
    H.eq(#culprits, 0, "ни одна команда не прячет совет (" .. #commands .. " проверено)"
        .. ((#culprits > 0) and ("  <- прячут: " .. table.concat(culprits, ", ")) or ""))

    -- И при уже скрытых советах команды их число не увеличивают.
    S.populate(env, H)
    ns.Config:ClearDismissed()
    local two = 0
    for _, card in ipairs(ns.ActionEngine.cards or {}) do
        if not card.blocking and two < 2 then
            ns.Config:Dismiss(card.key, env.Api:ServerTime(), 3600)
            two = two + 1
        end
    end
    local before = hiddenRecords(env)
    H.eq(before, 2, "заранее скрыто два совета")
    for _, cmd in ipairs({ "", "now", "scan", "hidden", "panel", "panel", "reset", "diag",
                           "сила", "заработок" }) do
        pcall(slash, cmd)
        H.ok(hiddenRecords(env) <= before, "/fp " .. ((cmd == "") and "(пусто)" or cmd)
            .. " не добавил скрытых: " .. hiddenRecords(env))
    end
end

-- Б. НЕ ПОКАЗАНО ПО ВЫБОРУ ИГРОКА ---------------------------------------
--
-- Фильтр и профиль не прячут совет - они его не показывают, и это другое. Но
-- для игрока разницы нет, если экран об этом молчит: фильтр «Чары», нажатый
-- вчера, сегодня выглядит как «у меня один совет вместо девяти». Выбор
-- сохраняется между сессиями, так что вспоминать о нём некому.

local function nowTabText(env)
    local ns = env.ns
    ns.MainFrame:Build()
    ns.MainFrame:Select("NOW")
    ns.MainFrame:RenderActive()
    local labels, texts = S.harvest(env.world, ns.MainFrame.frame)
    local plain = {}
    for i, t in ipairs(texts) do plain[i] = S.plain(t) end
    return table.concat(plain, "\n"), labels
end

-- ОБЪЯВЛЕНО - ЗНАЧИТ, ЕСТЬ СТРОКА И ЕСТЬ ПОДРОБНОСТИ. Два разных вопроса.
--
-- Над списком стояла простыня: четыре абзаца про порог, профиль, длину списка и
-- окно профессий - пять строк до первого совета. Игрок сказал про это «кратко и
-- без воды», и он прав. Но сократить - не значит замолчать, поэтому проверяется
-- и то и другое: НАД СПИСКОМ одна короткая строка с числом и с путём к
-- подробностям, ПОД КУРСОРОМ - сами подробности, с теми же числами и словами,
-- что были раньше в тексте над списком.
local function nowStrip(env)
    local ns = env.ns
    ns.MainFrame:Build()
    ns.MainFrame:Select("NOW")
    ns.MainFrame:RenderActive()
    local strip = ns.TabNow.strip
    if not (strip and strip.__shown) then return nil, "" end
    local line = S.plain(strip.text:GetText() or "")
    local details = {}
    for _, d in ipairs(strip.details or {}) do details[#details + 1] = S.plain(d) end
    return line, table.concat(details, "\n")
end

-- Строка над списком обязана быть одной, короткой и с путём к подробностям.
local function checkStripLine(env, line, where)
    local ns = env.ns
    H.ok(line ~= nil, where .. ": над списком есть строка — " .. tostring(line))
    if not line then return end
    H.eq(line:find("\n", 1, true), nil, where .. ": она ровно одна, без переносов")
    H.ok(ns.Util.charLen(line) <= 110,
        where .. ": и короткая (" .. ns.Util.charLen(line) .. " символов)")
    H.ok(line:find(ns.TabNow.DETAILS_HINT, 1, true) ~= nil,
        where .. ": путь к подробностям назван в ней самой")
end

H.suite("Фильтр над списком: на экране сказано, сколько советов он не показывает")
do
    local env = fresh()
    local ns = env.ns
    local total = #(ns.ActionEngine.cards or {})
    H.ok(total >= 5, "советов всего: " .. total)

    -- Без фильтра - никаких оговорок.
    ns.Config:SetChip(ns.CHIP.ALL)
    local line = nowStrip(env)
    H.eq(line, nil, "без фильтра строки над списком нет вовсе")

    -- Фильтр «Чары» оставляет часть списка.
    ns.Config:SetChip(ns.CHIP.ENCHANT)
    local shown = #ns.ActionEngine:Filtered(ns.CHIP.ENCHANT)
    H.ok(shown > 0 and shown < total, "фильтр «Чары» показывает " .. shown .. " из " .. total)
    local details
    line, details = nowStrip(env)
    checkStripLine(env, line, "фильтр")
    if line then
        H.ok(line:find("«" .. ns.CHIP_LABEL[ns.CHIP.ENCHANT] .. "»", 1, true) ~= nil,
            "в ней назван сам фильтр: " .. line)
        H.ok(line:find(tostring(total - shown), 1, true) ~= nil,
            "и число не показанных: " .. (total - shown))
    end
    local full = details:match("[^\n]*Фильтр «[^\n]*")
    H.ok(full ~= nil, "под курсором — подробная строка про фильтр: " .. tostring(full))
    if full then
        H.ok(full:find(shown .. " из " .. total, 1, true) ~= nil,
            "и числа: показано " .. shown .. " из " .. total)
        H.ok(full:find("«" .. ns.CHIP_LABEL[ns.CHIP.ALL] .. "»", 1, true) ~= nil,
            "и чем вернуть остальные")
    end

    -- Фильтр переживает перезагрузку - значит, и строка обязана.
    local saved = ns.Config:Get()
    local env2 = S.load(H)
    env2.ns.Config:Bind(saved, {})
    S.populate(env2, H)
    H.eq(env2.ns.Config:Chip(), ns.CHIP.ENCHANT, "после перезагрузки фильтр тот же")
    local line2, details2 = nowStrip(env2)
    checkStripLine(env2, line2, "фильтр после перезагрузки")
    H.ok(details2:find("Фильтр «", 1, true) ~= nil,
        "и подробности про него снова на месте — вспоминать о вчерашнем щелчке не надо")

    -- Щелчок по «Всё» возвращает весь список и убирает строку.
    ns.Config:SetChip(ns.CHIP.ALL)
    line = nowStrip(env)
    H.eq(line, nil, "после «Всё» строки нет")
    H.eq(#ns.ActionEngine:Filtered(ns.CHIP.ALL), total, "и показаны все " .. total)
end

H.suite("Профиль приоритетов: на экране сказано, что он убрал из списка")
do
    -- В коде давно написано, что профиль убирает советы «НЕ МОЛЧА» и что это
    -- «видно в окне». Не было видно: причина показывалась только у веток, не
    -- выдавших ни одного совета, а профиль убирает советы у веток, которые их
    -- как раз выдали. В диагностике игрока - 72 убранных за сессию и ни одной
    -- строки об этом на экране.
    local env = fresh()
    local ns = env.ns
    local profile = ns.Config:Profile()
    local label = ns.PROFILE_LABEL[profile]
    H.ok(label ~= nil, "текущий профиль: " .. tostring(label))

    -- Пусть этот профиль убирает покупки: такой совет в списке точно есть.
    local saved = ns.PROFILE_EXCLUDE[profile]
    ns.PROFILE_EXCLUDE[profile] = { BUY = true }
    H.build(env)
    local dropped = (ns.ActionEngine.meta or {}).profileDropped or 0
    H.ok(dropped > 0, "профиль убрал советов: " .. dropped)

    local line, details = nowStrip(env)
    checkStripLine(env, line, "профиль")
    if line then
        H.ok(line:find("«" .. label .. "»", 1, true) ~= nil,
            "в ней назван сам профиль: " .. line)
        H.ok(line:find(tostring(dropped), 1, true) ~= nil, "и сколько: " .. dropped)
    end
    local full = details:match("[^\n]*Профиль «[^\n]*")
    H.ok(full ~= nil, "под курсором — подробная строка про профиль: " .. tostring(full))
    if full then
        H.ok(full:find(ns.KIND_LABEL.BUY, 1, true) ~= nil, "названо, что именно убрано")
        H.ok(full:find(tostring(dropped), 1, true) ~= nil, "и сколько: " .. dropped)
        H.ok(full:find("другом профиле", 1, true) ~= nil, "и что это вернётся в другом профиле")
    end

    -- Профиль ничего не убрал - строки нет.
    ns.PROFILE_EXCLUDE[profile] = {}
    H.build(env)
    line, details = nowStrip(env)
    H.eq(line, nil, "профиль ничего не убрал — строки нет")
    ns.PROFILE_EXCLUDE[profile] = saved
end

-- Б2. ПОРОГ МЕЛКОЙ ДЕНЕЖНОЙ ВЫГОДЫ -------------------------------------
--
-- Правило самого игрока: мелкий денежный выигрыш не показывать, и чем выше
-- уровень, тем выше порог (Core/Const.lua, ns.MONEY_FLOOR_BANDS). Пропажа по
-- нему - такая же пропажа, как по фильтру, и объявляется так же.

H.suite("Порог мелкой выгоды: на экране сказано, сколько денежных советов он убрал")
do
    local env = fresh()
    local ns = env.ns

    -- ПЕРЕЧЕНЬ ВИДОВ, КОТОРЫХ ПОРОГ КАСАЕТСЯ, - ЗАКРЫТЫЙ, И СВЕРЯЕТСЯ С САМИМИ
    -- КАРТОЧКАМИ. Признак денежного совета в карточке один - benefitKind
    -- «gold», и он не должен разойтись с таблицей, по которой отсеивают.
    for kind in pairs(ns.MONEY_FLOOR_KINDS) do
        H.ok(ns.KIND[kind] == kind, "в перечне денежных видов настоящий вид: " .. kind)
    end
    local misfit = {}
    for _, profile in ipairs(ns.PROFILE_ORDER) do
        ns.Config:SetProfile(profile)
        H.build(env)
        for _, card in ipairs(ns.ActionEngine.cards or {}) do
            if card.benefitKind == "gold" and not ns.MONEY_FLOOR_KINDS[card.kind] then
                misfit[#misfit + 1] = tostring(card.kind) .. " / " .. tostring(card.title)
            end
        end
    end
    ns.Config:SetProfile(ns.PROFILE.POWER)
    H.eq(#misfit, 0, "ни один совет с денежной выгодой не остался вне перечня"
        .. ((#misfit > 0) and ("  <- " .. table.concat(misfit, "; ")) or ""))

    H.build(env)
    local money = 0
    for _, card in ipairs(ns.ActionEngine.cards or {}) do
        if ns.MONEY_FLOOR_KINDS[card.kind] then money = money + 1 end
    end
    H.ok(money > 0, "денежных советов до порога: " .. money)

    -- Порог снят - строки про него нет: иначе она была бы шумом.
    local line, details = nowStrip(env)
    H.ok(details:find("орог мелкой", 1, true) == nil, "порог снят — строки про него нет")

    -- Порог в 30 золотых: ровно то число, про которое спрашивал игрок. В этом
    -- мире под него уходит вся денежная половина списка.
    ns.Config:SetMoneyFloorMode(ns.MONEY_FLOOR_MODE.FIXED)
    ns.Config:SetMoneyFloorOwn(300000)
    H.build(env)
    local left = 0
    for _, card in ipairs(ns.ActionEngine.cards or {}) do
        if ns.MONEY_FLOOR_KINDS[card.kind] then left = left + 1 end
    end
    H.eq(left, 0, "при пороге 30з денежных советов не осталось")
    H.eq((ns.ActionEngine.meta or {}).moneyFloorDropped, money,
        "убрано ровно столько, сколько их было: " .. money)
    H.eq(hiddenRecords(env), 0, "и ни один из них не записан в скрытые: это не скрытие")

    line, details = nowStrip(env)
    checkStripLine(env, line, "порог")
    if line then
        H.ok(line:find(tostring(money), 1, true) ~= nil,
            "в ней сказано, сколько убрано: " .. money)
        H.ok(line:find("порог", 1, true) ~= nil, "и что это порог: " .. line)
        -- А ЧИСЛА ПОРОГА, ПОЛОСЫ И РАЗДЕЛА НАСТРОЕК В НЕЙ НЕТ, И ЭТО НАРОЧНО:
        -- это ответ на вопрос, который игрок ещё не задал, и место ему под
        -- курсором. Строка над списком отвечает «часть советов не показана», а
        -- не рассказывает, как устроен порог.
        H.eq(line:find(ns.ActionEngine.MONEY_FLOOR_SECTION, 1, true), nil,
            "раздела настроек в короткой строке нет — он в подробностях")
    end
    local full = details:match("[^\n]*орог мелкой[^\n]*")
    H.ok(full ~= nil, "под курсором — подробная строка про порог: " .. tostring(full))
    if full then
        H.ok(full:find(tostring(money), 1, true) ~= nil,
            "в ней сказано, сколько убрано: " .. money)
        H.ok(full:find(ns.Util.money(300000), 1, true) ~= nil,
            "и сам порог: " .. ns.Util.money(300000))
        H.ok(full:find("настройк", 1, true) ~= nil, "и где его снять")
        H.ok(full:find(ns.ActionEngine.MONEY_FLOOR_SECTION, 1, true) ~= nil,
            "названием раздела, а не намёком")
    end

    -- Выбор переживает перезагрузку - значит, и строка обязана.
    local saved = ns.Config:Get()
    local env2 = S.load(H)
    env2.ns.Config:Bind(saved, {})
    S.populate(env2, H)
    H.eq(env2.ns.Config:MoneyFloorMode(), env2.ns.MONEY_FLOOR_MODE.FIXED,
        "после перезагрузки порог тот же")
    local line2, details2 = nowStrip(env2)
    checkStripLine(env2, line2, "порог после перезагрузки")
    H.ok(details2:find("орог мелкой", 1, true) ~= nil,
        "и подробности про него снова на месте — вспоминать о вчерашнем выборе не надо")

    -- Снять порог - и всё вернулось, без всяких «вернуть скрытые».
    ns.Config:SetMoneyFloorMode(ns.MONEY_FLOOR_MODE.OFF)
    H.build(env)
    local back = 0
    for _, card in ipairs(ns.ActionEngine.cards or {}) do
        if ns.MONEY_FLOOR_KINDS[card.kind] then back = back + 1 end
    end
    H.eq(back, money, "порог снят — вернулись все " .. money)
    line, details = nowStrip(env)
    H.ok(details:find("орог мелкой", 1, true) == nil, "и строки про порог снова нет")
end

H.suite("Порог мелкой выгоды: стенд снимает его в одном месте, и это место названо")
do
    -- В фикстурных мирах порог снят (деньги там игрушечные, см. H.setMoneyFloor
    -- в Tests/harness.lua). Подмена поведения, которое в игре работает иначе, -
    -- это та же тихая пропажа, только в наборе проверок: шесть тысяч зелёных
    -- утверждений про аддон, который в игре ведёт себя не так. Поэтому таких
    -- мест ровно одно, и их число проверяется.
    local function codeOf(rel)
        local f = assert(io.open(ROOT .. "/" .. rel, "rb"))
        local code = D.stripped(f:read("*a"))
        f:close()
        return code
    end
    local harness = codeOf("Tests/harness.lua")
    local declared, called = 0, 0
    for _ in harness:gmatch("function H%.setMoneyFloor") do declared = declared + 1 end
    for _ in harness:gmatch("H%.setMoneyFloor%(") do called = called + 1 end
    H.eq(declared, 1, "снятие порога объявлено в стенде один раз")
    -- Объявление `function H.setMoneyFloor(` в счёт вызовов тоже попадает -
    -- вычитается, иначе проверка сравнивала бы 2 с 1 и падала на пустом месте.
    H.eq(called - declared, 1, "и зовётся из одного места — H.load (вхождений "
        .. called .. ")")

    -- И значение по умолчанию проверяется по самим дефолтам, а не по стенду:
    -- иначе смену дефолта подмена бы спрятала.
    local env = fresh()
    H.eq(env.ns.Config.DEFAULTS.show.moneyFloorMode, env.ns.MONEY_FLOOR_MODE.LEVEL,
        "в игре порог по умолчанию включён и берётся по полосам уровня")
    H.eq(env.ns.Config:MoneyFloorMode(), env.ns.MONEY_FLOOR_MODE.OFF,
        "а в этом фикстурном мире он снят — и это написано в Tests/harness.lua")
end

-- В. НЕ ПОМЕСТИЛОСЬ -----------------------------------------------------

H.suite("Список ограничен по длине: если советов больше, это сказано на экране")
do
    local env = fresh()
    local ns = env.ns
    local all = #(ns.ActionEngine.cards or {})
    local saved = ns.MAX_CARDS
    ns.MAX_CARDS = 3
    H.build(env)
    H.eq(#(ns.ActionEngine.cards or {}), 3, "в списке оставлено 3")
    H.eq((ns.ActionEngine.meta or {}).generated, all, "а построено было " .. all)

    local line, details = nowStrip(env)
    checkStripLine(env, line, "длина списка")
    if line then
        H.ok(line:find(tostring(all - 3), 1, true) ~= nil,
            "в ней число не поместившихся: " .. (all - 3))
    end
    local full = details:match("[^\n]*не поместил[^\n]*")
    H.ok(full ~= nil, "под курсором — подробная строка про это: " .. tostring(full))
    if full then
        H.ok(full:find("3", 1, true) ~= nil and full:find(tostring(all), 1, true) ~= nil,
            "с числами: показано 3 из " .. all)
    end

    ns.MAX_CARDS = saved
    H.build(env)
    line, details = nowStrip(env)
    H.ok(details:find("не поместил", 1, true) == nil, "всё поместилось — строки нет")
end

-- Г. ПРОПАЛ ЭКРАН, А НЕ СОВЕТ -------------------------------------------
--
-- Панель можно убрать, свернуть, окно - закрыть, бой прячет и то и другое. Для
-- игрока это выглядит похоже («было и нет»), поэтому в перечне оно есть. Но
-- советы при этом целы: их столько же, ни один не записан в скрытые, и там,
-- где экран убран самим игроком, сказано, как его вернуть.

H.suite("Убран экран, а не совет: советов столько же и ни один не скрыт")
do
    local WAYS = {
        { "кнопка «убрать» на панели", function(ns)
            local f = ns.StepPanel.frame
            f.close.__scripts.OnClick(f.close)
        end, says = "/fp panel" },
        { "кнопка «свернуть» на панели", function(ns)
            local f = ns.StepPanel.frame
            f.collapse.__scripts.OnClick(f.collapse)
        end },
        { "команда закрытия окна", function(ns)
            ns.MainFrame.frame:Show()
            ns.MainFrame:Hide()
        end, says = "/fp" },
        { "бой: окно и панель прячутся по правилу", function(ns)
            ns.Config:Get().panel.combat = "hide"
            ns.MainFrame:OnCombat(true)
        end },
        { "подземелье: панель прячется по правилу", function(ns)
            ns.Config:Get().panel.instance = "hide"
            ns.StepPanel:OnZone(true)
        end },
        { "галочка «Показывать панель» снята", function(ns)
            ns.StepPanel:SetEnabled(false)
        end },
    }
    for _, way in ipairs(WAYS) do
        local env = fresh()
        local ns = env.ns
        buildEverything(env)
        local before = #(ns.ActionEngine.cards or {})
        env.said = {}
        local ok, err = pcall(way[2], ns)
        drainTimers(env)
        H.ok(ok, way[1] .. ": не падает", tostring(err))
        H.eq(hiddenRecords(env), 0, way[1] .. ": ни один совет не записан в скрытые")
        H.eq(#(ns.ActionEngine.cards or {}), before,
            way[1] .. ": советов по-прежнему " .. before)
        if way.says then
            local told = false
            for _, line in ipairs(env.said) do
                if S.plain(line):find(way.says, 1, true) then told = true end
            end
            H.ok(told, way[1] .. ": в чате названо, как вернуть (" .. way.says .. ")")
        end
        -- И после пересчёта советы на месте: убранный экран не выключает движок.
        H.build(env)
        H.eq(#(ns.ActionEngine.cards or {}), before,
            way[1] .. ": и после пересчёта их столько же")
    end
end


end
