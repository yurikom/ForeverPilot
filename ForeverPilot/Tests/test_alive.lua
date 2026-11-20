-- ForeverPilot / Tests/test_alive.lua
--
-- АДДОН ЖИВЁТ ВМЕСТЕ С ПЕРСОНАЖЕМ, А НЕ СРАБАТЫВАЕТ ОДИН РАЗ.
--
-- Слова игрока: «он мне один раз вызвал результаты, и всё». Это ощущение имело
-- под собой две настоящие причины, и набор держит обе.
--
--   1. ПЕРЕСЧЁТ БЫЛ ТОЛЬКО ПО СОБЫТИЯМ. Events:Tick выходил сразу, если ни один
--      флаг не выставлен, а значит: стоишь в городе - цены стареют, возраст на
--      карточках не меняется, список выглядит замороженным. Теперь есть
--      холостой пересчёт по времени.
--
--   2. ПОДПИСКА БЫЛА НЕПРОВЕРЯЕМОЙ. Регистрация шла через pcall, и событие,
--      которого на этом клиенте нет, молча не подписывалось - а узнать об этом
--      было негде. Теперь каждое событие проверяется через
--      C_EventUtils.IsEventValid, результат попадает в диагностику, и
--      Events:Report() отдаёт таблицу «событие → есть в клиенте → подписаны →
--      вызывает пересчёт».
--
-- Третий контракт - про бой: события в бою ОТКЛАДЫВАЮТСЯ, а не теряются.
local H = ...

return function()

-- Каркас: кадр-пустышка, который запоминает подписки, как это делает клиент.
local function fakeFrame()
    local f = { registered = {}, scripts = {} }
    function f:RegisterEvent(name) self.registered[name] = true end
    function f:UnregisterEvent(name) self.registered[name] = nil end
    function f:SetScript(which, fn) self.scripts[which] = fn end
    return f
end

-- Клиент, который знает только часть событий. Ровно так ведёт себя настоящий:
-- C_EventUtils.IsEventValid отвечает про каждое имя отдельно.
local function withEventValidator(env, known)
    env.G.C_EventUtils = {
        IsEventValid = function(name) return known[name] and true or false end,
    }
end

H.suite("Живость: событие проверяется у клиента, а не подписывается наугад")
do
    local env = H.load()
    local ns = env.ns
    local frame = fakeFrame()
    withEventValidator(env, {
        PLAYER_ENTERING_WORLD = true,
        BAG_UPDATE_DELAYED = true,
        PLAYER_MONEY = true,
        -- а вот этого на клиенте якобы нет
    })
    ns.Events:Init(frame, function() end)

    H.eq(frame.registered.PLAYER_ENTERING_WORLD, true,
        "существующее событие подписано")
    H.eq(frame.registered.AUCTION_ITEM_LIST_UPDATE, nil,
        "несуществующее — не подписано, и это не ошибка")

    local report = ns.Events:Report()
    H.ok(report ~= nil and #report > 0, "отчёт по событиям построен: " .. #report)
    local byName = {}
    for _, row in ipairs(report) do byName[row.event] = row end

    local a = byName.PLAYER_ENTERING_WORLD
    H.ok(a ~= nil, "строка про PLAYER_ENTERING_WORLD есть")
    if a then
        H.eq(a.exists, true, "клиент его знает")
        H.eq(a.subscribed, true, "подписаны")
        H.ok(a.causesRecompute, "и оно вызывает пересчёт")
        H.ok(a.flags ~= nil and #a.flags > 0,
            "с перечислением, что именно оно помечает грязным: "
            .. table.concat(a.flags, ","))
    end

    local b = byName.AUCTION_ITEM_LIST_UPDATE
    if b then
        H.eq(b.exists, false, "про отсутствующее сказано, что его нет")
        H.eq(b.subscribed, false, "и что мы не подписаны")
    end
end

H.suite("Живость: все события из отчёта названы, ничего не пропало")
do
    local env = H.load()
    local ns = env.ns
    -- Клиент знает ВСЁ: проверяем, что аддон не забыл подписаться.
    local frame = fakeFrame()
    env.G.C_EventUtils = { IsEventValid = function() return true end }
    ns.Events:Init(frame, function() end)

    -- Минимум, который требуется от живого аддона. Каждое из этих событий
    -- должно быть и в карте, и подписано, когда клиент его знает.
    local MUST = {
        "PLAYER_ENTERING_WORLD",        -- вход и перезагрузка интерфейса
        "PLAYER_LEVEL_UP",              -- получение уровня
        "PLAYER_EQUIPMENT_CHANGED",     -- смена экипировки
        "UNIT_INVENTORY_CHANGED",
        "BAG_UPDATE_DELAYED",           -- изменение сумок
        "PLAYERBANKSLOTS_CHANGED",      -- изменение банка
        "BANKFRAME_OPENED",
        "PLAYER_MONEY",                 -- изменение золота
        "TRADE_SKILL_SHOW",             -- открытие окна профессии
        "NEW_RECIPE_LEARNED",           -- изучение нового рецепта
        "SKILL_LINES_CHANGED",          -- изменение навыка
        "CHAT_MSG_SKILL",               -- и подъём потолка навыка
        "MERCHANT_SHOW",                -- посещение торговца
        "AUCTION_HOUSE_SHOW",           -- открытие аукциона
        "AUCTION_HOUSE_CLOSED",         -- и закрытие
        "CHARACTER_POINTS_CHANGED",     -- смена талантов
        "PLAYER_TALENT_UPDATE",
    }
    for _, name in ipairs(MUST) do
        H.eq(frame.registered[name], true, name .. " — подписаны")
    end
end

H.suite("Живость: холостой пересчёт — список не выглядит замороженным")
do
    local env = H.load()
    local ns = env.ns
    local frame = fakeFrame()
    env.G.C_EventUtils = { IsEventValid = function() return true end }
    ns.Events:Init(frame, function() end)

    local runs = 0
    ns.Events:On("recompute", function() runs = runs + 1 end)

    -- Ни одного события: раньше здесь не происходило вообще ничего, и возраст
    -- цен на экране застывал.
    H.clock = 1000
    ns.Events:Reset()
    ns.Events:Tick()
    H.eq(runs, 0, "сразу после сброса холостого пересчёта нет")

    H.clock = 1000 + ns.Events.IDLE_SECONDS - 1
    ns.Events:Tick()
    H.eq(runs, 0, "до срока — по-прежнему нет")

    H.clock = 1000 + ns.Events.IDLE_SECONDS + 1
    ns.Events:Tick()
    H.eq(runs, 1, "по сроку холостой пересчёт случился сам")

    -- И повторяется, а не один раз.
    H.clock = H.clock + ns.Events.IDLE_SECONDS + 1
    ns.Events:Tick()
    H.eq(runs, 2, "и повторяется")

    -- Причина названа: иначе в диагностике «пересчёт без причины».
    H.ok(ns.Events.lastIdleReason ~= nil,
        "и у холостого пересчёта есть причина: "
        .. tostring(ns.Events.lastIdleReason))
end

H.suite("Живость: в бою холостой пересчёт не делается")
do
    local env = H.load()
    local ns = env.ns
    local frame = fakeFrame()
    env.G.C_EventUtils = { IsEventValid = function() return true end }
    ns.Events:Init(frame, function() end)
    local runs = 0
    ns.Events:On("recompute", function() runs = runs + 1 end)

    H.clock = 1000
    ns.Events:Reset()
    ns.Events:OnEvent("PLAYER_REGEN_DISABLED")
    H.clock = 1000 + ns.Events.IDLE_SECONDS + 1
    ns.Events:Tick()
    H.eq(runs, 0, "в бою холостого пересчёта нет")

    -- Выход из боя сам помечает сумки грязными (в бою могло выпасть), поэтому
    -- дальше работает обычный путь с задержкой, а не холостой. Это и правильно:
    -- отдельный холостой пересчёт поверх настоящего был бы лишним.
    ns.Events:OnEvent("PLAYER_REGEN_ENABLED")
    ns.Events:Tick()
    H.eq(runs, 0, "сразу после боя — ещё нет: работает обычная задержка")
    H.clock = H.clock + ns.RECOMPUTE_DEBOUNCE + 0.01
    ns.Events:Tick()
    H.eq(runs, 1, "а по истечении задержки пересчёт случается")
end

H.suite("Троттлинг: событие в бою откладывается, а не теряется")
do
    local env = H.load()
    local ns = env.ns
    local frame = fakeFrame()
    env.G.C_EventUtils = { IsEventValid = function() return true end }
    ns.Events:Init(frame, function() end)
    local reasons = {}
    ns.Events:On("recompute", function(r) reasons[#reasons + 1] = r end)

    H.clock = 1000
    ns.Events:Reset()
    ns.Events:OnEvent("PLAYER_REGEN_DISABLED")

    -- В бою игрок получил уровень, надел вещь и подобрал золото. Ни одно из
    -- этого не должно пропасть.
    ns.Events:OnEvent("PLAYER_LEVEL_UP")
    ns.Events:OnEvent("PLAYER_EQUIPMENT_CHANGED")
    ns.Events:OnEvent("PLAYER_MONEY")
    H.eq(ns.Events:IsDirty("character"), true, "флаг «персонаж» выставлен в бою")
    H.eq(ns.Events:IsDirty("equipment"), true, "флаг «экипировка» тоже")
    H.eq(ns.Events:IsDirty("money"), true, "и «золото»")

    H.clock = 1010
    ns.Events:Tick()
    H.eq(#reasons, 0, "в бою пересчёта не было")
    H.eq(ns.Events:IsDirty("character"), true,
        "и флаги НЕ сброшены — событие отложено, а не потеряно")
    H.ok(ns.Events:Pending() ~= nil,
        "и аддон помнит, что он кому-то должен пересчёт")
    H.ok((ns.Events.deferredTicks or 0) > 0,
        "отложенные такты посчитаны: " .. tostring(ns.Events.deferredTicks))

    -- Бой кончился.
    ns.Events:OnEvent("PLAYER_REGEN_ENABLED")
    H.clock = 1011
    ns.Events:Tick()
    H.eq(#reasons, 1, "после боя пересчёт случился ровно один раз на все события")
    if reasons[1] then
        H.eq(reasons[1].character, true, "и в причинах — «персонаж»")
        H.eq(reasons[1].equipment, true, "и «экипировка»")
        H.eq(reasons[1].money, true, "и «золото»: ни одно не потерялось")
    end
    H.eq(ns.Events:IsDirty("character"), false, "после пересчёта флаги сброшены")
end

H.suite("Троттлинг: пересчёт не чаще разумного")
do
    local env = H.load()
    local ns = env.ns
    local frame = fakeFrame()
    env.G.C_EventUtils = { IsEventValid = function() return true end }
    ns.Events:Init(frame, function() end)
    local runs = 0
    ns.Events:On("recompute", function() runs = runs + 1 end)

    H.clock = 1000
    ns.Events:Reset()
    ns.Events:OnEvent("BAG_UPDATE_DELAYED")
    H.clock = 1000 + ns.RECOMPUTE_DEBOUNCE + 0.01
    ns.Events:Tick()
    H.eq(runs, 1, "первый пересчёт прошёл")

    -- Сразу ещё одно событие: должно подождать минимальный интервал.
    ns.Events:OnEvent("BAG_UPDATE_DELAYED")
    H.clock = H.clock + ns.RECOMPUTE_DEBOUNCE + 0.01
    ns.Events:Tick()
    H.eq(runs, 1, "второй пересчёт подряд не запустился")
    H.eq(ns.Events:IsDirty("bags"), true, "но событие не потерялось")

    H.clock = H.clock + ns.RECOMPUTE_MIN_INTERVAL
    ns.Events:Tick()
    H.eq(runs, 2, "и прошёл, когда интервал истёк")
end

H.suite("Живость: подъём потолка навыка замечается по сообщению клиента")
do
    local env = H.load()
    local ns = env.ns
    local frame = fakeFrame()
    env.G.C_EventUtils = { IsEventValid = function() return true end }
    ns.Events:Init(frame, function() end)
    H.clock = 1000
    ns.Events:Reset()

    -- Клиент пишет в чат «Ваш навык портняжного дела повысился до 226».
    ns.Events:OnEvent("CHAT_MSG_SKILL", "Ваш навык портняжного дела повысился до 226.")
    H.eq(ns.Events:IsDirty("character"), true,
        "сообщение о навыке помечает персонажа грязным")
    H.eq(ns.Events:IsDirty("skillcap"), true,
        "и отдельно — что потолок навыка мог поехать")
end

H.suite("Живость: аукцион — отдельный сигнал, а не просто грязные цены")
do
    local env = H.load()
    local ns = env.ns
    local frame = fakeFrame()
    env.G.C_EventUtils = { IsEventValid = function() return true end }
    ns.Events:Init(frame, function() end)
    local auctionSignals = {}
    ns.Events:On("auction", function(what) auctionSignals[#auctionSignals + 1] = what end)

    H.clock = 1000
    ns.Events:Reset()
    ns.Events:OnEvent("AUCTION_HOUSE_SHOW")
    H.eq(auctionSignals[1], "open", "открытие аукциона — отдельный сигнал")
    H.eq(ns.Events:IsDirty("prices"), true, "и цены помечены грязными")

    ns.Events:OnEvent("AUCTION_HOUSE_CLOSED")
    H.eq(auctionSignals[2], "close", "закрытие — тоже")
end

H.suite("Живость: отчёт по событиям попадает в диагностику")
do
    local env = H.load()
    local ns = env.ns
    local frame = fakeFrame()
    withEventValidator(env, { PLAYER_ENTERING_WORLD = true, PLAYER_MONEY = true })
    ns.Events:Init(frame, function() end)

    local m = ns.Diag:Init().modules.events
    H.ok(m ~= nil, "модуль events записан в диагностику")
    if m then
        H.ok((m["in"] or 0) > 0, "сколько событий хотели: " .. tostring(m["in"]))
        H.ok((m.out or 0) > 0, "сколько подписали: " .. tostring(m.out))
        H.ok((m.absent or 0) > 0,
            "и сколько клиент не знает: " .. tostring(m.absent))
        H.ok(type(m.absentNames) == "table",
            "с именами — по ним и видно, чего на этом клиенте нет")
    end
    -- Проверка существования каждого события тоже записана, по имени.
    local d = ns.Diag:Init().detect
    H.ok(d["событие PLAYER_ENTERING_WORLD"] == true
         or d["PLAYER_ENTERING_WORLD"] == true,
        "существование события отмечено в feature-detect")
end

H.suite("Живость: без C_EventUtils аддон подписывается, а не сдаётся")
do
    -- На клиенте без проверялки событий feature-detect невозможен. Тогда
    -- подписка идёт через pcall, как раньше, и это ЗАПИСАНО: «проверить было
    -- нечем» - честный ответ, а «не подписались» - нет.
    local env = H.load()
    local ns = env.ns
    env.G.C_EventUtils = nil
    local frame = fakeFrame()
    ns.Events:Init(frame, function() end)
    H.eq(frame.registered.PLAYER_ENTERING_WORLD, true,
        "подписка состоялась и без проверялки")
    local report = ns.Events:Report()
    local row
    for _, r in ipairs(report) do
        if r.event == "PLAYER_ENTERING_WORLD" then row = r end
    end
    H.ok(row ~= nil, "строка отчёта есть")
    if row then
        H.eq(row.exists, nil, "а «есть ли оно в клиенте» — неизвестно, не выдумано")
        H.eq(row.subscribed, true, "при этом подписаны")
    end
end

-- БЛОКИРОВКА ВЫЗОВА: ЗАМЕТИТЬ ЕЁ МОЖНО ТОЛЬКО СОБЫТИЕМ --------------------
--
-- Игрок увидел окно «Модификация "ForeverPilot" заблокирована при попытке
-- выполнения действия, доступного только интерфейсу Blizzard». Сам вызов
-- (C_TradeSkillUI.OpenRecipe) убран - Core/Api.lua, Logic/RecipeBook.lua, - но
-- убран ОДИН, а эта подписка про любой следующий.
--
-- И она не «на всякий случай»: заблокированный вызов НЕ БРОСАЕТ ОШИБКУ Lua.
-- Игра просто его не делает, pcall вокруг отвечает «получилось», и узнать о
-- блокировке из кода больше нечем. Ровно поэтому прошлая прожила три сессии:
-- окно видел игрок, а в FOREVERPILOT_DIAG не было ни ошибки, ни записи.
H.suite("Живость: игра заблокировала наш вызов — это видно в диагностике")
do
    local env = H.load()
    local ns = env.ns
    local frame = fakeFrame()
    ns.Events:Init(frame, function() end)
    H.eq(frame.registered.ADDON_ACTION_BLOCKED, true, "подписка на блокировку есть")
    H.eq(frame.registered.ADDON_ACTION_FORBIDDEN, true, "и на запрещённое действие тоже")
    local report = ns.Events:Report()
    local named = {}
    for _, r in ipairs(report) do named[r.event] = r end
    H.ok(named.ADDON_ACTION_BLOCKED ~= nil,
        "и событие названо в отчёте: иначе подписка в него не попадёт")
    H.eq(named.ADDON_ACTION_BLOCKED.causesRecompute, false,
        "пересчёта оно не вызывает: это не новость о мире")

    ns.Diag:ClearSuspicions()
    ns.Events.blockedTold = 0
    env.said = {}
    ns.Events:Dispatch("ADDON_ACTION_BLOCKED", "ForeverPilot", "C_TradeSkillUI.OpenRecipe")

    -- 1. В ДИАГНОСТИКЕ: и счётчик, и запись, и находка самопроверки.
    local counters = ns.Diag:Init().counters or {}
    H.eq(counters["blocked.C_TradeSkillUI.OpenRecipe"], 1,
        "блокировка посчитана по имени вызова")
    local logged
    for _, entry in ipairs(ns.Diag:Init().log or {}) do
        if tostring(entry.text):find("заблокировала", 1, true) then logged = entry end
    end
    H.ok(logged ~= nil, "и записана в журнал")
    if logged then
        H.eq(tostring(logged.detail and logged.detail.func), "C_TradeSkillUI.OpenRecipe",
            "с именем того самого вызова")
    end
    local suspects = ns.Diag:Init().suspicious or {}
    H.eq(#suspects, 1, "и это названо странностью: аддон не упал, но так нельзя")
    if suspects[1] then
        H.eq(suspects[1].code, "addon-action-blocked", "у находки свой код")
        H.ok(tostring(suspects[1].text):find("OpenRecipe", 1, true) ~= nil,
            "и в ней сказано, какой вызов: " .. tostring(suspects[1].text))
    end

    -- 2. ИГРОКУ: один раз, и не «отключите аддон».
    H.eq(#env.said, 1, "игроку сказано ровно одной строкой")
    local line = tostring(env.said[1])
    H.ok(line:find("OpenRecipe", 1, true) ~= nil, "и в ней назван вызов: " .. line)
    H.ok(line:find("Пропустить", 1, true) ~= nil,
        "и сказано, что в окне игры нажать")
    H.eq(line:find("Отключите", 1, true), nil,
        "а отключать себя аддон не предлагает: чинить надо вызов")

    -- 3. И ВТОРОЙ РАЗ В ЧАТ НЕ ПИШЕТСЯ. Блокировка повторяется на каждый
    --    вызов, и строка на каждую превратила бы одну неприятность в
    --    непрерывную - ровно то, на что игрок жаловался как на фриз.
    env.said = {}
    for _ = 1, 5 do
        ns.Events:Dispatch("ADDON_ACTION_BLOCKED", "ForeverPilot", "C_TradeSkillUI.OpenRecipe")
    end
    H.eq(#env.said, 0, "повторные блокировки в чат не пишутся")
    H.eq((ns.Diag:Init().counters or {})["blocked.C_TradeSkillUI.OpenRecipe"], 6,
        "а в диагностике посчитаны все шесть")
    H.eq(#(ns.Diag:Init().suspicious or {}), 1,
        "и находка одна, со счётчиком, а не шесть одинаковых")

    -- 4. ЧУЖАЯ БЛОКИРОВКА - НЕ НАША. Записать её себе было бы ложью.
    ns.Diag:ClearSuspicions()
    env.said = {}
    ns.Events:Dispatch("ADDON_ACTION_BLOCKED", "Questie", "TargetUnit")
    H.eq((ns.Diag:Init().counters or {})["blocked.TargetUnit"], nil,
        "блокировка чужого аддона себе не записывается")
    H.eq(#env.said, 0, "и игроку про чужой аддон ничего не говорится")
    H.eq(#(ns.Diag:Init().suspicious or {}), 0, "и находки на ней нет")
    H.eq(#(ns.Diag:Init().errors or {}), 0,
        "и ошибок за всё это нет: блокировка — не падение аддона")
end

end
