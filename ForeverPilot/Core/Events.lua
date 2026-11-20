-- ForeverPilot / Core/Events.lua
--
-- Event plumbing and the recompute scheduler. Nothing is recalculated per frame:
-- game events set dirty flags, a debounce timer coalesces them, and a minimum
-- interval keeps the engine from running back to back. Combat suspends all work.
--
-- ТРИ ВЕЩИ, КОТОРЫЕ ЗДЕСЬ ИСПРАВЛЕНЫ, И ВСЕ ТРИ ИЗ ОДНОЙ ЖАЛОБЫ ИГРОКА:
-- «он мне один раз вызвал результаты, и всё».
--
--   1. ПОДПИСКА БЫЛА НЕПРОВЕРЯЕМОЙ. Регистрация шла через pcall, и событие,
--      которого на этом клиенте нет, молча не подписывалось. Узнать, что аддон
--      глух к половине событий, было негде. Теперь каждое имя проверяется через
--      C_EventUtils.IsEventValid - эта функция на клиенте есть, её без всяких
--      оговорок зовут Plumber и Platynator, - результат пишется в диагностику,
--      а Events:Report() отдаёт таблицу «событие → есть в клиенте → подписаны →
--      вызывает пересчёт». Нет самой проверялки - подписываемся как раньше и
--      пишем «проверить было нечем», а не выдумываем ответ.
--
--   2. ПЕРЕСЧЁТ БЫЛ ТОЛЬКО ПО СОБЫТИЯМ. Tick() выходил сразу, когда ни один
--      флаг не выставлен. Стоишь в городе - цены стареют, возраст на карточках
--      не меняется, предупреждение «цены старше суток» не появляется, список
--      выглядит замороженным. Теперь есть холостой пересчёт по времени.
--
--   3. СОБЫТИЙ НЕ ХВАТАЛО. Не было ни подъёма навыка по сообщению клиента
--      (CHAT_MSG_SKILL - единственный надёжный признак, что потолок поехал), ни
--      смены талантов, ни современных событий аукциона, ни ITEM_DATA_LOAD_RESULT.
--
-- Ничего игрового здесь не автоматизируется: события только читаются.
local ADDON, ns = ...

local U = ns.Util
local Events = {}
ns.Events = Events

Events.dirty = {}
Events.listeners = {}
Events.suspended = false

local lastRun, pendingSince = 0, nil

-- Which dirty flag each game event raises.
--
-- Порядок в таблице не важен; важно, что КАЖДОЕ событие, на которое аддон
-- подписан ради пересчёта, лежит здесь - именно по этой таблице строится отчёт
-- Events:Report(), и событие, подписанное в обход неё, в отчёт не попадёт.
Events.EVENT_MAP = {
    -- вход в игру и перезагрузка интерфейса
    PLAYER_ENTERING_WORLD          = { "character", "bags", "equipment", "recipes" },
    -- сумки и банк
    BAG_UPDATE_DELAYED             = { "bags" },
    PLAYERBANKSLOTS_CHANGED        = { "bank" },
    BANKFRAME_OPENED               = { "bank" },
    BANKFRAME_CLOSED               = { "bank" },
    -- На этом клиенте банк современный (C_Bank есть, GetNumSkillLines нет), и
    -- Syndicator здесь подписывается на вкладки вместо PLAYERBANKBAGSLOTS_CHANGED.
    BANK_TABS_CHANGED              = { "bank" },
    BANK_TAB_SETTINGS_UPDATED      = { "bank" },
    -- экипировка
    PLAYER_EQUIPMENT_CHANGED       = { "equipment" },
    UNIT_INVENTORY_CHANGED         = { "equipment" },
    -- золото
    PLAYER_MONEY                   = { "money" },
    -- уровень
    PLAYER_LEVEL_UP                = { "character", "level" },
    UNIT_LEVEL                     = { "character", "level" },
    -- таланты и специализация
    CHARACTER_POINTS_CHANGED       = { "character" },
    PLAYER_TALENT_UPDATE           = { "character", "spec" },
    ACTIVE_TALENT_GROUP_CHANGED    = { "character", "spec" },
    -- навык профессии и его потолок
    SKILL_LINES_CHANGED            = { "character", "skillcap" },
    -- окно профессии и рецепты
    TRADE_SKILL_SHOW               = { "recipes" },
    TRADE_SKILL_LIST_UPDATE        = { "recipes" },
    TRADE_SKILL_DATA_SOURCE_CHANGED = { "recipes" },
    TRADE_SKILL_CLOSE              = { "recipes" },
    NEW_RECIPE_LEARNED             = { "recipes" },
    -- торговец и тренер
    MERCHANT_SHOW                  = { "vendor" },
    MERCHANT_UPDATE                = { "vendor" },
    MERCHANT_CLOSED                = { "vendor" },
    TRAINER_SHOW                   = { "places" },
    TRAINER_UPDATE                 = { "places" },
    -- аукцион: и классические имена (они на этом клиенте работают - в файле
    -- игрока есть event.AUCTION_HOUSE_SHOW = 1), и современные результаты
    -- поиска, потому что аукцион здесь современный (C_AuctionHouse).
    AUCTION_HOUSE_SHOW             = { "prices" },
    AUCTION_HOUSE_CLOSED           = { "prices" },
    AUCTION_HOUSE_BROWSE_RESULTS_UPDATED = { "prices", "auctionScan" },
    COMMODITY_SEARCH_RESULTS_UPDATED     = { "prices", "auctionScan" },
    ITEM_SEARCH_RESULTS_UPDATED          = { "prices", "auctionScan" },
    OWNED_AUCTIONS_UPDATED               = { "prices" },
    AUCTION_HOUSE_AUCTION_CREATED        = { "prices" },
    -- данные предметов
    GET_ITEM_INFO_RECEIVED         = { "items" },
    ITEM_DATA_LOAD_RESULT          = { "items" },
}

-- События, которые помечают грязным ничего, но несут сигнал: обработчик их
-- разбирает сам (CHAT_MSG_SKILL несёт текст, окна аукциона - свой сигнал).
Events.SIGNAL_ONLY = {
    -- Подъём навыка. На этом клиенте это ЕДИНСТВЕННЫЙ надёжный признак, что
    -- потолок профессии мог поехать: SKILL_LINES_CHANGED приходит и по другим
    -- поводам, а сообщение в чат приходит ровно на повышение.
    CHAT_MSG_SKILL = true,
    -- Современный путь открытия окон на этом клиенте: Auctionator здесь
    -- подписан именно на них, а не на AUCTION_HOUSE_*.
    PLAYER_INTERACTION_MANAGER_FRAME_SHOW = true,
    PLAYER_INTERACTION_MANAGER_FRAME_HIDE = true,
    -- Награда за задание может быть вещью: ветка «развилка путей» про неё
    -- спрашивает, и после сдачи задания ответ меняется.
    QUEST_TURNED_IN = true,
    -- бой
    PLAYER_REGEN_DISABLED = true,
    PLAYER_REGEN_ENABLED = true,
    ZONE_CHANGED_NEW_AREA = true,
    -- ИГРА ЗАБЛОКИРОВАЛА НАШ ВЫЗОВ. Эти два события - единственный способ
    -- УЗНАТЬ об этом из кода: заблокированный вызов не бросает ошибку Lua, он
    -- просто не выполняется, и pcall вокруг него отвечает «получилось».
    --
    -- Именно поэтому блокировка C_TradeSkillUI.OpenRecipe прожила до жалобы
    -- игрока: окно «Модификация "ForeverPilot" заблокирована…» видел он, а в
    -- диагностике за три сессии не было ни ошибки, ни записи. Сам вызов убран
    -- (Core/Api.lua), но убран ОДИН, а подписка здесь - про любой следующий:
    -- если игра ещё что-то у нас заблокирует, это будет видно в /fp diag, а не
    -- только в окне у игрока.
    ADDON_ACTION_BLOCKED = true,
    ADDON_ACTION_FORBIDDEN = true,
}

-- ХОЛОСТОЙ ПЕРЕСЧЁТ. Пять минут - это компромисс: цены за это время заметно не
-- стареют, но возраст на карточке и предупреждение «цены старше суток» успевают
-- появиться сами, без единого действия игрока. Пересчёт стоит около 4.5 мс.
Events.IDLE_SECONDS = 300
Events.lastIdleAt = nil
Events.lastIdleReason = nil
Events.deferredTicks = 0

-- Registration -----------------------------------------------------------

-- Events that belong to whoever set the frame up (Main), not to the scheduler.
-- Taking over OnEvent used to silently swallow these: PLAYER_LOGOUT stopped
-- reaching Main, so Diag:Finish() never ran and every diagnostics session was
-- left looking truncated. They are now dispatched through one handler.
Events.PASSTHROUGH = {
    ADDON_LOADED = true, PLAYER_LOGIN = true, PLAYER_LOGOUT = true,
}

-- Существует ли событие на этом клиенте. nil - «проверить было нечем», и это
-- не то же самое, что false.
function Events:EventValid(name)
    local util = _G.C_EventUtils
    local fn = type(util) == "table" and util.IsEventValid or nil
    if type(fn) ~= "function" then return nil end
    local ok, valid = pcall(fn, name)
    if not ok then return nil end
    return valid and true or false
end

-- Подписаться на одно событие, записав результат. Возвращает
-- subscribed, exists.
function Events:Subscribe(frame, name)
    local exists = Events:EventValid(name)
    self.eventState = self.eventState or {}
    if exists == false then
        self.eventState[name] = { exists = false, subscribed = false }
        if ns.Diag then ns.Diag:Detect("событие " .. name, false) end
        return false, false
    end
    local ok = pcall(frame.RegisterEvent, frame, name)
    self.eventState[name] = { exists = exists, subscribed = ok and true or false }
    if ns.Diag then
        -- Когда проверялки нет, exists остаётся nil: «подписались, а есть ли оно
        -- на самом деле - не знаем». Записываем именно так.
        if exists == nil then
            ns.Diag:Detect("событие " .. name .. " (проверить нечем)", ok and true or false)
        else
            ns.Diag:Detect("событие " .. name, true)
        end
    end
    return ok and true or false, exists
end

-- `owner(event, ...)` is called for the passthrough events above, before the
-- scheduler sees anything.
function Events:Init(frame, owner)
    self.frame = frame
    self.owner = owner or self.owner
    self.eventState = {}
    if not frame then return end

    local wanted, subscribed, absent, absentNames = 0, 0, 0, {}
    local function want(name)
        wanted = wanted + 1
        local ok, exists = Events:Subscribe(frame, name)
        if ok then subscribed = subscribed + 1 end
        if exists == false then
            absent = absent + 1
            if #absentNames < 30 then absentNames[#absentNames + 1] = name end
        end
    end

    for name in pairs(self.EVENT_MAP) do want(name) end
    for name in pairs(self.SIGNAL_ONLY) do want(name) end
    for name in pairs(Events.PASSTHROUGH) do want(name) end

    frame:SetScript("OnEvent", function(_, event, ...) Events:Dispatch(event, ...) end)
    frame:SetScript("OnUpdate", function(_, elapsed) Events:OnUpdate(elapsed) end)

    -- ЧТО КЛИЕНТ ЗНАЕТ И НА ЧТО МЫ ПОДПИСАНЫ - ОДНОЙ ЗАПИСЬЮ. Без неё
    -- «аддон глух к половине событий» было невозможно обнаружить иначе, чем
    -- заметив, что список не обновляется.
    table.sort(absentNames)
    if ns.Diag then
        -- Вся таблица целиком, машиночитаемо: событие → есть в клиенте →
        -- подписаны → вызывает пересчёт. Это то, по чему можно сверить
        -- ожидаемое поведение с действительным, не заходя в игру.
        ns.Diag:Init().events = Events:Report()
        ns.Diag:Module("events", {
            ["in"] = wanted, out = subscribed,
            absent = absent, absentNames = absentNames,
            validator = (Events:EventValid("PLAYER_ENTERING_WORLD") ~= nil)
                and "C_EventUtils.IsEventValid" or "нет — подписка через pcall",
            idleSeconds = Events.IDLE_SECONDS,
            reason = (subscribed == 0) and "ни на одно событие подписаться не удалось" or nil,
            reasonCode = (subscribed == 0) and "NO_API" or nil,
        })
    end
    return wanted, subscribed, absent
end

-- Таблица «событие → есть в клиенте → подписаны → вызывает пересчёт».
-- Отдаётся наружу: её печатает /fp api и читает набор тестов.
function Events:Report()
    local out = {}
    local function add(name, flags)
        local st = (self.eventState or {})[name] or {}
        out[#out + 1] = {
            event = name,
            exists = st.exists,
            subscribed = st.subscribed and true or false,
            causesRecompute = (flags ~= nil),
            flags = flags,
            role = (flags and "пересчёт")
                or (Events.PASSTHROUGH[name] and "служебное")
                or "сигнал",
        }
    end
    for name, flags in pairs(self.EVENT_MAP) do add(name, flags) end
    for name in pairs(self.SIGNAL_ONLY) do add(name, nil) end
    for name in pairs(Events.PASSTHROUGH) do add(name, nil) end
    table.sort(out, function(a, b) return a.event < b.event end)
    return out
end

-- The single entry point for everything the frame receives.
function Events:Dispatch(event, ...)
    if Events.PASSTHROUGH[event] then
        if self.owner then
            local ok, err = ns.Diag:Guard("Events:owner:" .. tostring(event), self.owner, event, ...)
            if not ok and ns.Api then
                ns.Api:Print("ошибка в обработчике " .. tostring(event) .. ": " .. tostring(err))
            end
        elseif event == "PLAYER_LOGOUT" and ns.Diag then
            -- Nobody claimed the event: still stamp the session rather than
            -- lose it. Logout is the one moment we cannot get back.
            ns.Diag:Finish()
        end
        if ns.Diag then ns.Diag:Count("event." .. tostring(event)) end
        return
    end
    return self:OnEvent(event, ...)
end

-- callback(reasons) is called after a recompute finishes.
function Events:On(name, callback)
    self.listeners[name] = self.listeners[name] or {}
    table.insert(self.listeners[name], callback)
end

function Events:Emit(name, ...)
    for _, cb in ipairs(self.listeners[name] or {}) do
        -- xpcall on OUR OWN callback only. The global error handler is left
        -- alone on purpose: hooking it would interfere with every other addon's
        -- error reporting.
        local ok, err = ns.Diag:Guard("Events:" .. tostring(name), cb, ...)
        if not ok and ns.Api then
            ns.Api:Print("ошибка в обработчике " .. tostring(name)
                .. ": " .. tostring(err))
        end
    end
end

-- Dirty flags ------------------------------------------------------------

function Events:MarkDirty(...)
    local now = ns.Api and ns.Api:Now() or 0
    for i = 1, select("#", ...) do
        local flag = select(i, ...)
        if flag then self.dirty[flag] = true end
    end
    if next(self.dirty) and not pendingSince then pendingSince = now end
end

function Events:IsDirty(flag)
    return self.dirty[flag] and true or false
end

-- С какого момента аддон кому-то должен пересчёт. nil - никому не должен.
-- Нужно наружу ровно для одного: доказать, что событие в бою ОТЛОЖЕНО, а не
-- потеряно - «флаг стоит» и «долг помнится» это два разных утверждения.
function Events:Pending()
    return pendingSince
end

function Events:ClearDirty()
    local snapshot = U.copy(self.dirty)
    self.dirty = {}
    pendingSince = nil
    return snapshot
end

-- Items the client had not cached yet; we coalesce these hard because
-- GET_ITEM_INFO_RECEIVED can fire hundreds of times in a second.
--
-- AND HARDER THAN THAT NOW. One live session took 4268 of these events, and
-- the one-second window still let each burst ask for a rebuild. An arriving
-- item name changes almost nothing on screen - it fills a "Предмет #12345"
-- placeholder and occasionally lets one more candidate be compared - so it does
-- not deserve the same urgency as the player's bags changing. The window below
-- is the minimum gap between rebuilds caused by item data ALONE; anything else
-- dirty in the same tick goes at the normal pace.
local itemInfoBurst, itemInfoBurstAt = 0, 0
Events.ITEM_INFO_QUIET_SECONDS = 10
local lastItemOnlyRun = 0

-- Сколько раз про блокировку говорится в чат за заход. Записывается в
-- диагностику КАЖДАЯ, а в чат - только первая: окно с «Отключить/Пропустить»
-- игра покажет и без нас, и дублировать его строкой на каждый такт - это ровно
-- тот способ превратить одну неприятность в непрерывную.
Events.BLOCKED_TOLD_LIMIT = 1
Events.blockedTold = 0

-- ЧТО ИГРА У НАС ЗАБЛОКИРОВАЛА, И КОГДА.
--
-- Первым аргументом клиент отдаёт имя аддона, вторым - имя функции. Нас
-- касается только своё имя: заблокированный вызов чужого аддона - не наше
-- дело, и записывать его себе в диагностику было бы ложью.
function Events:OnActionBlocked(event, addon, func)
    if tostring(addon) ~= ADDON then return false end
    local what = tostring(func or "неизвестный вызов")
    if ns.Diag then
        ns.Diag:Count("blocked." .. what)
        ns.Diag:Log("игра заблокировала вызов аддона", {
            event = tostring(event), func = what,
        })
        -- Это именно «странность», а не ошибка аддона: аддон не упал. Но
        -- молчать нельзя - ровно это молчание и стоило игроку сессии.
        ns.Diag:Suspect("addon-action-blocked",
            "игра заблокировала мой вызов «" .. what .. "»: такое действие"
            .. " доступно только интерфейсу игры. Чинить надо вызов, а не"
            .. " блокировку — его в аддоне быть не должно вовсе.",
            { func = what, event = tostring(event) })
    end
    if Events.blockedTold < Events.BLOCKED_TOLD_LIMIT and ns.Api then
        Events.blockedTold = Events.blockedTold + 1
        ns.Api:Print("игра заблокировала мой вызов «" .. what .. "» —"
            .. " это моя ошибка, а не ваша. Отключать меня не нужно:"
            .. " нажмите «Пропустить». Подробности — /fp diag")
    end
    return true
end

function Events:OnEvent(event, ...)
    if ns.Diag then ns.Diag:Count("event." .. tostring(event)) end
    if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        Events:OnActionBlocked(event, ...)
        return
    end
    if event == "PLAYER_REGEN_DISABLED" then
        self.suspended = true
        self:Emit("combat", true)
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        self.suspended = false
        self:Emit("combat", false)
        self:MarkDirty("bags")
        return
    end

    if event == "GET_ITEM_INFO_RECEIVED" or event == "ITEM_DATA_LOAD_RESULT" then
        local now = ns.Api:Now()
        if now - itemInfoBurstAt > 1 then itemInfoBurst, itemInfoBurstAt = 0, now end
        itemInfoBurst = itemInfoBurst + 1
        -- One recompute per burst, not one per item.
        if itemInfoBurst == 1 then self:MarkDirty("items") end
        return
    end

    -- ПОДЪЁМ НАВЫКА. Текст сообщения клиент отдаёт первым аргументом; разбирать
    -- его мы не пытаемся (он локализован и формат менялся) - сам факт события
    -- уже значит, что навык изменился, а менялся он у профессии, и значит
    -- потолок мог оказаться достигнут или отодвинуться.
    if event == "CHAT_MSG_SKILL" then
        self:MarkDirty("character", "skillcap")
        self:Emit("skill", ...)
        return
    end

    -- ОКНО ТОРГОВЦА, С НАЗВАННОЙ ФАЗОЙ.
    --
    -- Фаза появилась не для красоты: книга закупок (Logic/Ledger.lua) сверяет
    -- деньги с сумками, и ей надо знать РОВНО три момента - окно открылось
    -- (запомнить состояние), окно обновилось (сверить: MERCHANT_UPDATE приходит
    -- и после покупки), окно закрылось (сверить последний раз и забыть
    -- контекст). Без закрытия контекст «я у торговца» оставался бы включённым
    -- навсегда, и добыча в поле записывалась бы как покупка.
    if event == "MERCHANT_SHOW" then
        self:Emit("merchant", "show")
    elseif event == "MERCHANT_UPDATE" then
        self:Emit("merchant", "update")
    elseif event == "MERCHANT_CLOSED" then
        self:Emit("merchant", "close")
    end

    if event == "TRAINER_SHOW" or event == "TRAINER_UPDATE" then
        self:Emit("trainer")
    end

    if event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_ENTERING_WORLD" then
        self:Emit("zone")
    end

    if event == "QUEST_TURNED_IN" then
        self:MarkDirty("quests")
    end

    -- АУКЦИОН - ОТДЕЛЬНЫЙ СИГНАЛ, а не просто грязные цены. Это самый полезный
    -- момент за сессию: только тут появляется свежий срез рынка, и подписчик
    -- (Main) по этому сигналу сбрасывает память цен, пересчитывает денежную
    -- часть, обновляет суточный слепок и может сказать об одной выгодной сделке.
    if event == "AUCTION_HOUSE_SHOW" then
        self:Emit("auction", "open")
    elseif event == "AUCTION_HOUSE_CLOSED" then
        self:Emit("auction", "close")
    elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED"
        or event == "COMMODITY_SEARCH_RESULTS_UPDATED"
        or event == "ITEM_SEARCH_RESULTS_UPDATED" then
        self:Emit("auction", "results")
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW"
        or event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
        -- Современный путь: тип взаимодействия приходит числом. Аукцион - тот,
        -- который нас интересует; номер берём у клиента, а не вписываем.
        local kind = ...
        local enum = _G.Enum and _G.Enum.PlayerInteractionType
        local auctioneer = enum and enum.Auctioneer or nil
        if auctioneer and kind == auctioneer then
            self:MarkDirty("prices")
            self:Emit("auction",
                (event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW") and "open" or "close")
        end
        return
    end

    local flags = self.EVENT_MAP[event]
    if flags then self:MarkDirty(unpack(flags)) end
end

-- Scheduler --------------------------------------------------------------

local accum = 0

function Events:OnUpdate(elapsed)
    accum = accum + (elapsed or 0)
    if accum < 0.2 then return end
    accum = 0
    self:Tick()
end

-- Is the only reason to recompute that some item names arrived?
function Events:OnlyItemsDirty()
    local n, hasItems = 0, false
    for flag in pairs(self.dirty) do
        n = n + 1
        if flag == "items" then hasItems = true end
    end
    return hasItems and n == 1
end

function Events:Tick()
    local now = ns.Api:Now()
    if self.suspended then
        -- В БОЮ НИЧЕГО НЕ ТЕРЯЕТСЯ. Флаги остаются выставленными, долг
        -- (pendingSince) остаётся, и как только бой кончится, пересчёт
        -- случится. Счётчик отложенных тактов нужен, чтобы «пересчёт не
        -- случился» и «пересчёт отложен» можно было различить в файле.
        if pendingSince then
            Events.deferredTicks = (Events.deferredTicks or 0) + 1
            if ns.Diag then ns.Diag:Count("recompute.deferredByCombat") end
        end
        return
    end

    if not pendingSince then
        -- ХОЛОСТОЙ ПЕРЕСЧЁТ. Ни одного события не было - и раньше здесь всё
        -- заканчивалось. Но время идёт и без событий: цены стареют, возраст на
        -- карточке надо пересчитать, предупреждение «цены старше суток» должно
        -- появиться само. Поэтому раз в IDLE_SECONDS пересчёт делается всё
        -- равно, и причина у него названа.
        local base = Events.lastIdleAt or lastRun
        if base == 0 then base = now end
        if (now - base) >= Events.IDLE_SECONDS then
            Events.lastIdleAt = now
            Events.lastIdleReason = "холостой пересчёт: прошло "
                .. U.round((now - base) / 60) .. " мин без событий,"
                .. " обновляю возраст цен и свежесть данных"
            self:MarkDirty("idle")
            if ns.Diag then ns.Diag:Count("recompute.idle") end
            self:Run()
        end
        return
    end

    if now - pendingSince < ns.RECOMPUTE_DEBOUNCE then return end
    if now - lastRun < ns.RECOMPUTE_MIN_INTERVAL then return end
    -- Item data arriving on its own waits longer. See ITEM_INFO_QUIET_SECONDS.
    if self:OnlyItemsDirty() then
        if now - lastItemOnlyRun < Events.ITEM_INFO_QUIET_SECONDS then
            if ns.Diag then ns.Diag:Count("recompute.itemBurstSuppressed") end
            return
        end
        lastItemOnlyRun = now
    end
    self:Run()
end

-- Force a recompute now (the player clicked Refresh or switched profile).
function Events:Run(force)
    if self.suspended and not force then return false end
    local now = ns.Api:Now()
    if not force and next(self.dirty) == nil then return false end
    lastRun = now
    Events.lastIdleAt = now
    local reasons = self:ClearDirty()
    if force then reasons.forced = true end

    local cfg = ns.Config:Get()
    if cfg and cfg.stats then
        cfg.stats.recomputes = (cfg.stats.recomputes or 0) + 1
        cfg.stats.lastRecompute = ns.Api:ServerTime()
    end

    self:Emit("recompute", reasons)
    return true
end

function Events:Reset()
    self.dirty, lastRun, pendingSince, accum = {}, 0, nil, 0
    lastItemOnlyRun = 0
    itemInfoBurst, itemInfoBurstAt = 0, 0
    Events.lastIdleAt = ns.Api and ns.Api:Now() or 0
    Events.lastIdleReason = nil
    Events.deferredTicks = 0
    Events.blockedTold = 0
end

return Events
