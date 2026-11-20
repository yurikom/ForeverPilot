-- ForeverPilot / Tests/test_confirm.lua
--
-- НЕОБРАТИМОЕ - НЕ ОДНИМ НАЖАТИЕМ.
--
-- Кнопка «Очистить мой список покупок» стирала список, который игрок собирал
-- руками, с одного нажатия: без вопроса, без слова в ответ и без пути назад.
-- Это тот же класс, что скрытие совета одним правым щелчком, - а на нём игрок
-- дважды остался без советов, прежде чем скрытие стало двухшаговым.
--
-- Здесь две вещи:
--
--   1. Сама кнопка: первое нажатие только спрашивает, второе в отведённое время
--      очищает, и аддон говорит, сколько позиций убрал.
--
--   2. ВЕСЬ КЛАСС, чтобы четвёртая такая кнопка не появилась незаметно: ни один
--      одиночный щелчок ни по одному элементу интерфейса и ни одна команда не
--      уменьшают сохранённые данные игрока. Исключения перечислены поимённо и
--      с причиной - это возвраты, а не уничтожение.
local H = ...
local S = assert(loadfile((H.ROOT or ".") .. "/Tests/uistub.lua"))()

return function()

local LABEL = "Очистить мой список покупок"

local function fresh()
    local env = S.load(H)
    S.populate(env, H)
    return env
end

local function pinned(env)
    local n = 0
    for _ in pairs(env.ns.Config:Shopping()) do n = n + 1 end
    return n
end

local function showSettings(env)
    local ns = env.ns
    ns.MainFrame:Build()
    ns.MainFrame:Select("CONFIG")
    ns.MainFrame:RenderActive()
end

-- Кнопка НА ЭКРАНЕ с такой подписью (сравнение по началу - подпись на время
-- вопроса другая, и её тест узнаёт отдельно).
local function visibleButtons(env, root)
    local out = {}
    for _, frame in ipairs(env.world.frames) do
        if frame.__type == "Button" and frame.__shown and S.descends(frame, root) then
            local fs = rawget(frame, "text") or rawget(frame, "label")
            if type(fs) == "table" and fs.__text and fs.__text ~= "" then
                -- виден ли весь путь до корня
                local node, ok = frame.__parent, true
                while node and node ~= root do
                    if not node.__shown then ok = false; break end
                    node = node.__parent
                end
                if ok then out[#out + 1] = frame end
            end
        end
    end
    return out
end

local function labelOf(frame)
    local fs = rawget(frame, "text") or rawget(frame, "label")
    return S.plain((type(fs) == "table" and fs.__text) or "")
end

local function buttonByLabel(env, label)
    for _, frame in ipairs(visibleButtons(env, env.ns.MainFrame.frame)) do
        if labelOf(frame) == label then return frame end
    end
    return nil
end

local function press(frame, ...)
    local handler = frame and frame.__scripts and frame.__scripts.OnClick
    if not handler then return false, "нет обработчика" end
    return pcall(handler, frame, ...)
end

local function drainTimers(env)
    for _ = 1, 5 do
        local pending = env.pendingTimers or {}
        env.pendingTimers = {}
        if #pending == 0 then break end
        for _, fn in ipairs(pending) do pcall(fn) end
    end
end

local function saidAny(env, needle)
    for _, line in ipairs(env.said or {}) do
        if S.plain(line):find(needle, 1, true) then return line end
    end
    return nil
end

local function errorCount(env) return #(env.ns.Diag:Init().errors or {}) end

-- 1. САМА КНОПКА -----------------------------------------------------------

H.suite("Очистка списка покупок: одно нажатие ничего не стирает")
do
    local env = fresh()
    local ns = env.ns
    ns.ShoppingList:Pin(2589, 12)
    ns.ShoppingList:Pin(11137, 3)
    showSettings(env)
    H.eq(pinned(env), 2, "в списке игрока две позиции")
    local btn = buttonByLabel(env, LABEL)
    H.ok(btn ~= nil, "кнопка «" .. LABEL .. "» на экране")

    env.said = {}
    local ok, err = press(btn)
    H.ok(ok, "нажатие не падает", tostring(err))
    H.eq(pinned(env), 2, "после одного нажатия список цел")
    H.eq(ns.ShoppingList:ClearArmed(), true, "аддон ждёт второго нажатия")

    -- Вопрос задан словами, и в нём названо, СКОЛЬКО будет стёрто и сколько
    -- времени на ответ: число берётся из кода, а не выучено тестом.
    local asked = saidAny(env, "очистить")
    H.ok(asked ~= nil, "в чате задан вопрос")
    H.ok(asked and S.plain(asked):find("2 позиции", 1, true) ~= nil,
        "вопрос называет, сколько позиций будет стёрто: " .. tostring(asked))
    local window = ns.Util.durationText(ns.ShoppingList.CLEAR_CONFIRM_SECONDS)
    H.ok(asked and window and S.plain(asked):find(window, 1, true) ~= nil,
        "и срок на ответ — тот, что в коде: " .. tostring(window))
    -- «ернуть»: слово стоит в начале предложения, с заглавной буквы.
    H.ok(asked and S.plain(asked):find("ернуть", 1, true) ~= nil
        and S.plain(asked):find("нельзя", 1, true) ~= nil,
        "и предупреждает, что вернуть будет нельзя")

    -- Кнопка сама говорит, что она сейчас сделает.
    H.eq(buttonByLabel(env, LABEL), nil, "на время вопроса прежней подписи на экране нет")
    local armed
    for _, frame in ipairs(visibleButtons(env, ns.MainFrame.frame)) do
        if labelOf(frame):find("ещё раз", 1, true) then armed = frame end
    end
    H.ok(armed ~= nil, "кнопка переподписана: просит нажать ещё раз")
    H.eq(errorCount(env), 0, "ошибок в диагностике нет")
end

H.suite("Очистка списка покупок: второе нажатие в срок очищает и говорит сколько")
do
    local env = fresh()
    local ns = env.ns
    ns.ShoppingList:Pin(2589, 12)
    ns.ShoppingList:Pin(11137, 3)
    showSettings(env)
    local builds = ns.ActionEngine.buildCount
    press(buttonByLabel(env, LABEL))
    env.said = {}
    local armed
    for _, frame in ipairs(visibleButtons(env, ns.MainFrame.frame)) do
        if labelOf(frame):find("ещё раз", 1, true) then armed = frame end
    end
    local ok, err = press(armed)
    H.ok(ok, "второе нажатие не падает", tostring(err))
    H.eq(pinned(env), 0, "список очищен")
    local done = saidAny(env, "очистил")
    H.ok(done ~= nil, "аддон сказал, что очистил")
    H.ok(done and S.plain(done):find("2 позиции", 1, true) ~= nil,
        "и сколько именно: " .. tostring(done))
    H.eq(ns.ShoppingList:ClearArmed(), false, "вопрос снят")
    H.ok(buttonByLabel(env, LABEL) ~= nil, "кнопка снова подписана как обычно")
    H.ok((ns.ActionEngine.buildCount or 0) > (builds or 0),
        "советы пересчитаны: список покупок в них участвует")
    H.eq(errorCount(env), 0, "ошибок в диагностике нет")
end

H.suite("Очистка списка покупок: второе нажатие после срока — снова вопрос, а не очистка")
do
    local env = fresh()
    local ns = env.ns
    ns.ShoppingList:Pin(2589, 12)
    showSettings(env)
    press(buttonByLabel(env, LABEL))
    H.eq(ns.ShoppingList:ClearArmed(), true, "вопрос задан")

    -- Срок вышел. Подпись обязана вернуться сама: иначе кнопка обещает
    -- «нажмите ещё раз - очищу», а нажатие только спросит заново.
    H.clock = H.clock + ns.ShoppingList.CLEAR_CONFIRM_SECONDS + 1
    drainTimers(env)
    H.eq(ns.ShoppingList:ClearArmed(), false, "срок вышел — вопрос снят")
    local btn = buttonByLabel(env, LABEL)
    H.ok(btn ~= nil, "подпись вернулась сама, без щелчка")

    press(btn)
    H.eq(pinned(env), 1, "нажатие после срока ничего не стёрло")
    H.eq(ns.ShoppingList:ClearArmed(), true, "оно снова только спросило")

    -- И ровно на границе срока второе нажатие ещё считается.
    H.clock = H.clock + ns.ShoppingList.CLEAR_CONFIRM_SECONDS
    H.eq(ns.ShoppingList:ClearArmed(), true, "на последней секунде срока вопрос ещё действует")
end

H.suite("Очистка списка покупок: пустой список — так и сказано, вопрос не задаётся")
do
    local env = fresh()
    local ns = env.ns
    showSettings(env)
    H.eq(pinned(env), 0, "своих позиций у игрока нет")
    env.said = {}
    local ok, err = press(buttonByLabel(env, LABEL))
    H.ok(ok, "нажатие не падает", tostring(err))
    H.eq(ns.ShoppingList:ClearArmed(), false, "спрашивать не о чем — вопрос не задан")
    H.ok(saidAny(env, "нечего") ~= nil, "сказано, что очищать нечего")
    H.ok(buttonByLabel(env, LABEL) ~= nil, "подпись кнопки не изменилась")
end

H.suite("Очистка списка покупок: решение принимает логика, а не обработчик кнопки")
do
    local env = H.load()
    local ns = env.ns
    ns.ShoppingList:Pin(100, 2)
    ns.ShoppingList:Pin(101, 1)
    ns.ShoppingList:Pin(110, 7)
    local outcome, message = ns.ShoppingList:RequestClear()
    H.eq(outcome, "armed", "первый запрос — вопрос")
    H.ok(type(message) == "string" and message ~= "", "с текстом")
    H.eq(ns.Config:ShoppingCount(), 3, "ничего не стёрто")
    outcome, message = ns.ShoppingList:RequestClear()
    H.eq(outcome, "cleared", "второй запрос в срок — очистка")
    H.eq(ns.Config:ShoppingCount(), 0, "список пуст")
    H.eq(next(ns.Config:Shopping()), nil, "и в сохранённых данных не осталось ни одной записи")
    H.ok(S.plain(message):find("3 позиции", 1, true) ~= nil, "названо, сколько убрано: " .. tostring(message))
    outcome = ns.ShoppingList:RequestClear()
    H.eq(outcome, "empty", "третий запрос — очищать нечего")

    -- Запрос, снятый другим действием, вторым нажатием не считается.
    ns.ShoppingList:Pin(100, 2)
    H.eq((ns.ShoppingList:RequestClear()), "armed", "снова вопрос")
    ns.ShoppingList:DisarmClear()
    H.eq((ns.ShoppingList:RequestClear()), "armed", "после снятия вопроса — опять вопрос, а не очистка")
    H.eq(ns.Config:ShoppingCount(), 1, "позиция на месте")

    -- В коде интерфейса нет ни одного места, которое стирает список само, в
    -- обход вопроса: писать в него может только Core/Config.lua.
    local offenders = {}
    for _, rel in ipairs({ "UI/TabSettings.lua", "UI/TabCraft.lua", "UI/TabNow.lua",
                           "UI/TabCharacter.lua", "UI/Card.lua", "UI/StepPanel.lua",
                           "UI/MainFrame.lua", "UI/MinimapButton.lua", "UI/Arrow.lua",
                           "UI/Widgets.lua", "Main.lua" }) do
        local f = io.open(H.ROOT .. "/" .. rel, "r")
        if f then
            local n = 0
            for line in f:lines() do
                n = n + 1
                local code = line:gsub("%-%-.*$", "")
                if code:find("shoppingList%s*%[") or code:find("shoppingList%s*=") then
                    offenders[#offenders + 1] = rel .. ":" .. n
                end
            end
            f:close()
        end
    end
    H.eq(#offenders, 0, "интерфейс не пишет в список покупок напрямую"
        .. ((#offenders > 0) and ("  <- " .. table.concat(offenders, ", ")) or ""))
end

-- 2. ВЕСЬ КЛАСС ------------------------------------------------------------
--
-- Сохранённые данные игрока - всё, что лежит в настройках и переживает выход
-- из игры: свой список покупок, скрытые советы, назначенные вручную слоты чар,
-- записанные торговцы и цены. Правило: ОДНО действие их не уменьшает.

-- Сколько записей в каждой таблице сохранённых данных (со вложенными).
local function leaves(t, seen)
    if type(t) ~= "table" then return 1 end
    seen = seen or {}
    if seen[t] then return 0 end
    seen[t] = true
    local n = 0
    for _, v in pairs(t) do n = n + leaves(v, seen) end
    return n
end

local function snapshot(env)
    local out = {}
    for key, value in pairs(env.ns.Config:Get()) do
        if type(value) == "table" then out[key] = leaves(value) end
    end
    return out
end

-- Что уменьшилось. Таблицы, которые аддон ведёт сам и чистит по сроку, сюда не
-- входят: это не данные игрока, а служебная память (кеш цен, статистика).
local SERVICE = { priceCache = true, stats = true, sourceCheck = true, notify = true,
                  history = true, priceHistoryMeta = true }
local function lost(before, after)
    local out = {}
    for key, n in pairs(before) do
        if not SERVICE[key] and (after[key] or 0) < n then
            out[#out + 1] = key .. " " .. n .. "→" .. tostring(after[key] or 0)
        end
    end
    table.sort(out)
    return out
end

-- Мир, в котором есть что терять.
local function seeded()
    local env = fresh()
    local ns = env.ns
    ns.ShoppingList:Pin(2589, 12)
    ns.ShoppingList:Pin(11137, 3)
    local hidden = 0
    for _, card in ipairs(ns.ActionEngine.cards or {}) do
        if not card.blocking and hidden < 2 then
            ns.Config:Dismiss(card.key, env.ns.Api:ServerTime(), 3600)
            hidden = hidden + 1
        end
    end
    ns.Config:SetEnchantSlot(10, "WRIST")
    pcall(function() ns.Places:RecordMerchant() end)
    H.build(env)
    return env
end

-- ВОЗВРАТЫ, А НЕ УНИЧТОЖЕНИЕ. Эти действия уменьшают ровно одну таблицу -
-- список скрытых советов - и в этом их смысл: они возвращают советы на экран.
-- «Вернуть все» к тому же единственный выход из пустого списка, и двух нажатий
-- от него требовать нельзя.
local RESTORES = {
    ["Вернуть все скрытые советы"] = "dismissed",
    ["Вернуть все"] = "dismissed",
    ["/fp show"] = "dismissed", ["/fp вернуть"] = "dismissed", ["/fp показать"] = "dismissed",
    ["/fp undo"] = "dismissed", ["/fp отмена"] = "dismissed", ["/fp назад"] = "dismissed",
}
local function allowed(name, losses)
    local only = RESTORES[name]
    if not only then return false end
    for _, entry in ipairs(losses) do
        if entry:match("^(%S+)") ~= only then return false end
    end
    return true
end

H.suite("Необратимое: ни один одиночный щелчок в окне не уменьшает сохранённые данные")
do
    -- Сначала - что вообще есть на экранах: подписи всех нажимаемых элементов
    -- по вкладкам. Потом каждый нажимается ОДИН раз в свежем мире.
    local probe = seeded()
    probe.ns.MainFrame:Build()
    local plan = {}
    for _, def in ipairs(probe.ns.MainFrame.TABS) do
        probe.ns.MainFrame:Select(def.key)
        probe.ns.MainFrame:RenderActive()
        local seenLabel = {}
        for _, frame in ipairs(visibleButtons(probe, probe.ns.MainFrame.frame)) do
            local label = labelOf(frame)
            if frame.__scripts and frame.__scripts.OnClick and not seenLabel[label] then
                seenLabel[label] = true
                plan[#plan + 1] = { tab = def.key, tabLabel = def.label, label = label }
            end
        end
    end
    H.ok(#plan > 25, "нажимаемых элементов к проверке: " .. #plan)
    local before0 = snapshot(probe)
    H.ok((before0.shoppingList or 0) >= 2 and (before0.dismissed or 0) >= 2,
        "в мире есть что терять: список покупок и скрытые советы")

    local culprits, pressed = {}, 0
    for _, item in ipairs(plan) do
        local env = seeded()
        local ns = env.ns
        ns.MainFrame:Build()
        ns.MainFrame:Select(item.tab)
        ns.MainFrame:RenderActive()
        local target
        for _, frame in ipairs(visibleButtons(env, ns.MainFrame.frame)) do
            if labelOf(frame) == item.label and frame.__scripts and frame.__scripts.OnClick then
                target = frame; break
            end
        end
        if target then
            local before = snapshot(env)
            pcall(target.__scripts.OnClick, target, "LeftButton")
            drainTimers(env)
            pressed = pressed + 1
            local losses = lost(before, snapshot(env))
            if #losses > 0 and not allowed(item.label, losses) then
                culprits[#culprits + 1] = "«" .. item.label .. "» (" .. item.tabLabel .. "): "
                    .. table.concat(losses, ", ")
            end
        end
    end
    H.ok(pressed >= #plan - 2, "нажато элементов: " .. pressed .. " из " .. #plan)
    H.eq(#culprits, 0, "одиночный щелчок нигде не стирает данные игрока"
        .. ((#culprits > 0) and ("  <- стирают: " .. table.concat(culprits, "; ")) or ""))
end

H.suite("Необратимое: возврат скрытых — единственное исключение, и оно настоящее")
do
    -- Исключение не должно быть мёртвой записью: кнопка есть, и она правда
    -- уменьшает только список скрытых.
    local env = seeded()
    local ns = env.ns
    showSettings(env)
    local btn = buttonByLabel(env, "Вернуть все скрытые советы")
    H.ok(btn ~= nil, "кнопка возврата на экране")
    local before = snapshot(env)
    press(btn)
    local losses = lost(before, snapshot(env))
    H.ok(#losses >= 1, "она действительно что-то убирает: " .. table.concat(losses, ", "))
    H.eq(allowed("Вернуть все скрытые советы", losses), true,
        "и только из списка скрытых советов")
    H.eq(pinned(env), 2, "список покупок при этом цел")
end

H.suite("Необратимое: ни одна команда одним вводом не уменьшает сохранённые данные")
do
    local commands = { "", "now", "сейчас", "char", "craft", "config", "scan", "обновить",
        "panel", "panel on", "panel off", "панель", "show", "вернуть", "показать",
        "undo", "отмена", "назад", "hidden", "скрытые", "reset", "api", "diag",
        "diag full", "diag reset", "сила", "прокачка", "экономия", "заработок",
        "hide", "скрыть", "dismiss", "next", "дальше", "clear", "очистить", "wipe",
        "абракадабра" }
    local culprits = {}
    for _, cmd in ipairs(commands) do
        local env = seeded()
        local ns, G = env.ns, env.G
        G.SlashCmdList = {}
        G.GetMerchantNumItems = function() return 0 end
        local chunk = assert(loadfile(H.ROOT .. "/Main.lua"))
        setfenv(chunk, env.sandbox)
        chunk("ForeverPilot", ns)
        ns.Bootstrap:RegisterSlash()
        local slash = G.SlashCmdList.FOREVERPILOT
        local before = snapshot(env)
        pcall(slash, cmd)
        drainTimers(env)
        local losses = lost(before, snapshot(env))
        if #losses > 0 and not allowed("/fp " .. cmd, losses) then
            culprits[#culprits + 1] = "/fp " .. cmd .. ": " .. table.concat(losses, ", ")
        end
    end
    H.eq(#culprits, 0, "команд проверено: " .. #commands .. ", данные игрока не стирает ни одна"
        .. ((#culprits > 0) and ("  <- стирают: " .. table.concat(culprits, "; ")) or ""))
end

end
