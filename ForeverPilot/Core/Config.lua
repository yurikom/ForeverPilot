-- ForeverPilot / Core/Config.lua
-- SavedVariables: defaults, migration, accessors. Pure Lua, no game API.
local ADDON, ns = ...

local U = ns.Util
local Config = {}
ns.Config = Config

Config.SCHEMA = 1

Config.DEFAULTS = {
    schema = Config.SCHEMA,
    profile = ns.PROFILE.POWER,
    chip = ns.CHIP.ALL,
    tab = "NOW",
    -- Приветствие в чат показано один раз. Писалось в SavedVariables, а в
    -- дефолтах не объявлялось — тот же недосмотр, что был у show.skipClassCheck.
    welcomed = false,
    ui = {
        scale = 1.0,
        point = "CENTER",
        relPoint = "CENTER",
        x = 0,
        y = 0,
        width = 720,
        height = 560,
        minimapButton = true,
        -- Положение кнопки у миникарты УГЛОМ в градусах, а не координатами:
        -- карта бывает разного размера и формы, и координаты, посчитанные для
        -- одной, на другой оказываются не на кромке. 135 - слева сверху, там,
        -- где кнопка стояла до того, как её научили ездить.
        minimapAngle = 135,
        tooltips = true,
        -- БЫЛО ЛИ ОКНО ОТКРЫТО, КОГДА ИГРОК В ПОСЛЕДНИЙ РАЗ ВЫХОДИЛ.
        --
        -- Пишут это только явные действия игрока: крестик, Esc, /fp, кнопка у
        -- миникарты. Скрытие по правилам (бой) НЕ пишет - иначе после первой
        -- же драки окно перестанет возвращаться. Это тот же приём, что у
        -- панели ниже, и подсмотрен он у Polestar (изучено, не скопировано:
        -- GPL-3.0, ни строки его кода здесь нет).
        --
        -- По умолчанию false: на свежей установке окно не выскакивает само,
        -- ровно как было до появления этого поля.
        shown = false,
    },
    show = {
        hideTrivialSkill = true,  -- do not suggest grey crafts for skill
        includeOtherChars = true, -- count alts' bags via Syndicator
        includeBank = true,
        maxSpendShare = 0.6,      -- never suggest spending more than this share of the wallet
        -- Проверка брони по классу - наше собственное правило, и игрок может
        -- его выключить. Галочка в настройках была, а поля в дефолтах не было:
        -- единственная настройка аддона, которой не существовало, пока её не
        -- тронут.
        skipClassCheck = false,
        -- МЕЛКАЯ ДЕНЕЖНАЯ ВЫГОДА. Полосы по уровню - в ns.MONEY_FLOOR_BANDS,
        -- там же написано, откуда взялись числа. Здесь только выбор игрока:
        -- "level" - по полосам (по умолчанию), "fixed" - одно своё число,
        -- "off" - порога нет. `moneyFloorOwn` читается ТОЛЬКО в "fixed".
        moneyFloorMode = "level",
        moneyFloorOwn = 2000,
    },
    -- УВЕДОМЛЕНИЯ. Два повода сказать что-то в чат по своей инициативе, и
    -- каждый выключается отдельно.
    --
    -- По умолчанию ВКЛЮЧЕНЫ, и это осознанно: аддон уже один раз тихо съел все
    -- советы, и игрок остался с пустым окном, не зная почему. Молчание по
    -- умолчанию - та же ошибка с другой стороны. Назойливость при этом
    -- ограничена не выключателем, а правилами: одно сообщение на посещение
    -- аукциона, порог по сумме, и ни одного повтора про тот же потолок навыка.
    --
    -- ВЫКЛЮЧЕНО СООБЩЕНИЕ, А НЕ РАБОТА. Пересчёт, слепок цен и карточки
    -- работают при любом значении: эти поля решают только, говорить ли вслух.
    notify = {
        auctionDeals = true,   -- «пока вы у аукциона: вот это заметно выгодно»
        skillCap = true,       -- «потолок навыка поднялся»
        stalePrices = true,    -- «цены старше суток, зайдите на аукцион»
    },
    -- The small always-on-screen panel. `enabled` is the player's own switch and
    -- nothing but the player ever writes it: the combat and instance rules are
    -- a separate, derived veto, so leaving combat restores what they had.
    panel = {
        enabled = true,
        collapsed = false,
        locked = false,
        width = 300,
        scale = 1.0,
        opacity = 1.0,
        pos = nil,                -- { left, bottom } from the screen corner
        combat = "show",          -- "show" | "fade" | "hide"
        instance = "show",        -- "show" | "hide"
        -- reduceMotion здесь больше нет: анимация, которой оно управляло,
        -- убрана вместе со скрытием по кнопке «Дальше». В сохранённых
        -- настройках старое значение может остаться - его никто не читает.
    },
    -- categoryID -> our slot key, learned once and editable by the player.
    enchantSlotMap = {},
    -- itemID -> copper, filled in as the player visits merchants.
    vendorPrices = {},
    -- our own price observations: itemID -> { c = copper, t = timestamp, src = "..." }
    priceCache = {},
    -- Daily price snapshot. The realm opened on 4 Nov 2026, so nobody has a
    -- price history yet and it cannot be reconstructed after the fact. We start
    -- accumulating from the very first login and do nothing clever with it in
    -- this version - just keep it.
    --   priceHistory[itemID] = { [dayStamp] = copper, ... }
    priceHistory = {},
    priceHistoryMeta = { lastDay = nil, days = 0, items = 0, firstDay = nil },
    -- СВОЯ КНИГА ЗАКУПОК: что игрок реально заплатил и когда. См.
    -- Logic/Ledger.lua - там же написано, почему чужой книге верить нельзя.
    --   entries - журнал, новое в конце: { id, k, w, q, c, u, t }
    --   byItem  - итоги по предмету, чтобы себестоимость считалась за один шаг
    --   meta    - сколько всего записано и сколько раз сверка отказалась
    ledger = {
        entries = {},
        byItem = {},
        meta = { entries = 0, observed = 0, skipped = 0, skips = {},
                 firstT = nil, lastT = nil },
    },
    -- СВОЙ РЕЕСТР ПЕРСОНАЖЕЙ: что аддон видел сам, по одной записи на
    -- персонажа. Единственный источник, из которого, играя магом, можно узнать
    -- профессии чернокнижника: его SavedVariablesPerCharacter игра не
    -- загружает, а Syndicator профессий не хранит. См. Logic/Roster.lua.
    --   chars[полное имя] = { classFile, level, professions = {...},
    --                         skillCaps = { имя профессии -> потолок }, seenAt }
    chars = {},
    -- ПОТОЛКИ НАВЫКА ЛЕЖАТ В chars[персонаж].skillCaps, А НЕ ЗДЕСЬ.
    --
    -- Это поле осталось от той версии, где они были общими на аккаунт и
    -- заведёнными по имени профессии: у мага кулинария 225, у чернокнижника она
    -- качается, и его подъём потолка пропадал молча. Поле объявлено, чтобы в
    -- старых сохранёнках оно не выглядело неизвестно откуда взявшимся, и чтобы
    -- миграция ниже имела что читать; НИКТО его больше не пишет.
    skillCaps = {},
    -- itemID -> qty the player asked us to remember buying
    shoppingList = {},
    -- Where things are, built from the player's own play. See Logic/Places.lua
    -- for why this is not read from another addon's shipped table.
    -- `trainers` only holds attributions we could make unambiguously;
    -- `trainersUnknown` is the NPCs we saw but could not pin to a profession.
    places = { npc = {}, itemVendors = {}, trainers = {}, trainersUnknown = {} },
    -- Navigation. "own" draws our own arrow and needs nothing installed;
    -- "tomtom" hands the point to TomTom instead; "off" disables routing.
    nav = {
        provider = "own",
        locked = false,
        scale = 1.0,
        pos = nil,                -- { left, bottom } from the screen corner
        hideInCombat = true,
    },
    dismissed = {},  -- cardKey -> expiry timestamp
    -- The last card hidden, so a mis-click is one undo away rather than a
    -- hunt. { key, title, at, seconds }
    lastDismiss = nil,
    history = {},    -- recent completed actions, newest last
    stats = { recomputes = 0, lastRecompute = 0 },
}

Config.CHAR_DEFAULTS = {
    schema = Config.SCHEMA,
    -- professionName -> { scanned = timestamp, recipes = { ... } }
    recipes = {},
    statWeightOverride = nil,
    lastSeenLevel = nil,
}

local db, charDB

-- Bind the two SavedVariables tables. Called once from Main on ADDON_LOADED.
function Config:Bind(globalTable, charTable)
    db = U.applyDefaults(globalTable or {}, Config.DEFAULTS)
    charDB = U.applyDefaults(charTable or {}, Config.CHAR_DEFAULTS)
    Config:Migrate()
    return db, charDB
end

function Config:Migrate()
    if not db then return end
    if (db.schema or 0) < Config.SCHEMA then
        db.schema = Config.SCHEMA
    end
    if charDB and (charDB.schema or 0) < Config.SCHEMA then
        charDB.schema = Config.SCHEMA
    end
    -- ОБЩИЕ ПОТОЛКИ НАВЫКА РАЗДАТЬ ПО ПЕРСОНАЖАМ НЕЛЬЗЯ, И ГАДАТЬ НЕ БУДЕМ.
    --
    -- Старая таблица db.skillCaps была одна на аккаунт и заведена по имени
    -- профессии, поэтому по записи «Кулинария = 225» определить, чья она -
    -- мага или чернокнижника, - невозможно в принципе. Приписать её текущему
    -- персонажу значило бы объявить чужой потолок своим, а это ровно та ошибка,
    -- из-за которой подъём у второго персонажа пропадал молча.
    --
    -- Поэтому записи не раздаются, а снимаются. Последствие ровно одно и оно
    -- безвредное: при первом входе каждым персонажем его потолки запоминаются
    -- заново и НИЧЕГО не объявляется - это штатное поведение «первой встречи»
    -- в Logic/Notifier.lua, а не потеря новости. Сколько записей снято -
    -- остаётся числом, чтобы это не было тихим действием.
    if type(db.skillCaps) == "table" and next(db.skillCaps) then
        local n = 0
        for key in pairs(db.skillCaps) do db.skillCaps[key] = nil; n = n + 1 end
        db.skillCapsMigrated = n
        if ns.Diag then
            ns.Diag:Log("общие потолки навыка сняты: их нельзя отнести к персонажу", {
                dropped = n,
                why = "таблица была одна на аккаунт и заведена по имени профессии",
            })
        end
    end
    -- Drop dismissals that have expired so the table does not grow forever.
    local now = ns.Api and ns.Api:ServerTime() or 0
    if db.dismissed then
        for key, expiry in pairs(db.dismissed) do
            if type(expiry) ~= "number" or (now > 0 and expiry < now) then
                db.dismissed[key] = nil
            end
        end
    end
    if db.history and #db.history > 100 then
        local trimmed = {}
        for i = #db.history - 99, #db.history do trimmed[#trimmed + 1] = db.history[i] end
        db.history = trimmed
    end
end

function Config:Get() return db end
function Config:Char() return charDB end

function Config:Profile()
    local p = db and db.profile
    if ns.PROFILE_WEIGHTS[p] then return p end
    return ns.PROFILE.POWER
end

function Config:SetProfile(p)
    if ns.PROFILE_WEIGHTS[p] and db then db.profile = p end
end

function Config:Chip()
    local c = db and db.chip
    if c and ns.CHIP[c] then return c end
    return ns.CHIP.ALL
end

function Config:SetChip(c)
    if db and ns.CHIP[c] then db.chip = c end
end

function Config:Weights()
    return ns.PROFILE_WEIGHTS[Config:Profile()] or ns.PROFILE_WEIGHTS.POWER
end

-- МЕЛКАЯ ДЕНЕЖНАЯ ВЫГОДА: ОДИН ОТВЕТ НА ВЕСЬ АДДОН ----------------------
--
-- Числа и полосы лежат в Core/Const.lua, выбор игрока - в db.show, а
-- вопрос «какой порог действует прямо сейчас» задаётся здесь и только здесь.
-- Движок, настройки и строка под списком берут ответ отсюда: разойдись они - и
-- на экране будет один порог, а отсеивать будет другой.

function Config:MoneyFloorMode()
    local m = db and db.show and db.show.moneyFloorMode
    for _, known in pairs(ns.MONEY_FLOOR_MODE) do
        if m == known then return m end
    end
    return ns.MONEY_FLOOR_MODE.LEVEL
end

function Config:SetMoneyFloorMode(mode)
    if not (db and db.show) then return false end
    for _, known in pairs(ns.MONEY_FLOOR_MODE) do
        if mode == known then
            db.show.moneyFloorMode = mode
            return true
        end
    end
    return false
end

-- Своё число. Округляется к ближайшему из ns.MONEY_FLOOR_CHOICES: настройка
-- предлагает лестницу, и значение вне лестницы на экране было бы не выбрать.
function Config:MoneyFloorOwn()
    local v = tonumber(db and db.show and db.show.moneyFloorOwn)
    if not v or v < 0 then return Config.DEFAULTS.show.moneyFloorOwn end
    return math.floor(v)
end

function Config:SetMoneyFloorOwn(copper)
    copper = tonumber(copper)
    if not (db and db.show) or not copper or copper < 0 then return false end
    db.show.moneyFloorOwn = math.floor(copper)
    return true
end

-- Какая полоса подходит уровню. Возвращает полосу и её номер; без уровня -
-- последнюю, самую строгую: угадывать уровень вниз значило бы показывать игроку
-- 60-го уровня мелочь, которую он просил не показывать.
function Config:MoneyFloorBand(level)
    local bands = ns.MONEY_FLOOR_BANDS or {}
    level = tonumber(level)
    if level then
        for i, band in ipairs(bands) do
            if band.upTo and level <= band.upTo then return band, i end
        end
    end
    return bands[#bands], #bands
end

-- Порог, действующий сейчас: медь, откуда он взялся и полоса (если по полосам).
-- Ноль означает «порога нет» - и это НЕ то же, что nil: ноль выбрал игрок.
function Config:MoneyFloor(level)
    local mode = Config:MoneyFloorMode()
    if mode == ns.MONEY_FLOOR_MODE.OFF then
        return 0, mode, nil
    end
    if mode == ns.MONEY_FLOOR_MODE.FIXED then
        return Config:MoneyFloorOwn(), mode, nil
    end
    local band, index = Config:MoneyFloorBand(level)
    return (band and band.copper) or 0, ns.MONEY_FLOOR_MODE.LEVEL, band, index
end

-- Window position / size -------------------------------------------------

function Config:SaveFrame(point, relPoint, x, y, width, height)
    if not db then return end
    local ui = db.ui
    ui.point, ui.relPoint = point or ui.point, relPoint or ui.relPoint
    ui.x, ui.y = x or ui.x, y or ui.y
    ui.width, ui.height = width or ui.width, height or ui.height
end

function Config:Frame()
    return (db and db.ui) or Config.DEFAULTS.ui
end

-- Был ли открыт главное окно. См. комментарий у ui.shown в дефолтах: пишется
-- только по явному действию игрока, скрытие по правилам сюда не ходит.
function Config:WindowShown()
    if not db then return false end
    return db.ui.shown and true or false
end

function Config:SetWindowShown(on)
    if not db then return end
    db.ui.shown = on and true or false
end

-- Кнопка у миникарты: угол в градусах, 0 - справа от центра, против часовой.
function Config:MinimapAngle()
    local v = db and db.ui and tonumber(db.ui.minimapAngle)
    if not v then
        return (ns.MinimapButton and ns.MinimapButton.DEFAULT_ANGLE) or 135
    end
    return v % 360
end

function Config:SetMinimapAngle(deg)
    deg = tonumber(deg)
    if not deg or not (db and db.ui) then return false end
    db.ui.minimapAngle = deg % 360
    return true
end

function Config:Scale()
    local s = db and db.ui and db.ui.scale
    return U.clamp(tonumber(s) or 1.0, 0.7, 1.6)
end

function Config:SetScale(s)
    if db then db.ui.scale = U.clamp(tonumber(s) or 1.0, 0.7, 1.6) end
end

-- Enchant slot mapping ---------------------------------------------------

function Config:EnchantSlot(categoryID)
    if not (db and categoryID) then return nil end
    return db.enchantSlotMap[categoryID]
end

function Config:SetEnchantSlot(categoryID, slotKey)
    if not (db and categoryID) then return end
    db.enchantSlotMap[categoryID] = slotKey
    -- The derived slot set is memoised, so a manual re-assignment has to drop it.
    if ns.RecipeBook and ns.RecipeBook.InvalidateEnchantCache then
        ns.RecipeBook:InvalidateEnchantCache()
    end
end

-- Prices we observed ourselves ------------------------------------------

function Config:RememberVendorPrice(itemID, copper)
    if not (db and itemID) then return end
    copper = tonumber(copper)
    if copper and copper > 0 then db.vendorPrices[itemID] = copper end
end

function Config:VendorPrice(itemID)
    if not (db and itemID) then return nil end
    local p = tonumber(db.vendorPrices[itemID])
    return (p and p > 0) and p or nil
end

function Config:RememberPrice(itemID, copper, src, now)
    if not (db and itemID) then return end
    copper = tonumber(copper)
    if not copper or copper <= 0 then return end
    db.priceCache[itemID] = { c = copper, t = now or 0, src = src or "own" }
end

function Config:CachedPrice(itemID)
    if not (db and itemID) then return nil end
    local e = db.priceCache[itemID]
    if type(e) ~= "table" then return nil end
    return tonumber(e.c), tonumber(e.t) or 0, e.src
end

-- Daily price snapshot ---------------------------------------------------
-- Cheap on purpose: one number per item per day, no analysis in this version.
-- Capped so a long-lived account cannot grow the SavedVariables without bound.

Config.PRICE_HISTORY_MAX_DAYS = 120
Config.PRICE_HISTORY_MAX_ITEMS = 4000

function Config:DayStamp(serverTime)
    return math.floor((tonumber(serverTime) or 0) / 86400)
end

function Config:SnapshotDue(serverTime)
    if not db then return false end
    local today = Config:DayStamp(serverTime)
    return db.priceHistoryMeta.lastDay ~= today
end

-- Record one item's price for today. Returns true when it was a new entry.
--
-- `overwrite` - перезаписать сегодняшнюю запись. Нужно ровно для одного случая:
-- игрок стоит у аукциона, и вот сейчас цена точно свежее той, что лежала в базе
-- Auctionator при входе в игру. В обычном ходе дел перезаписи нет: один день -
-- одно число, иначе история перестаёт быть историей.
function Config:RecordPriceSnapshot(itemID, copper, serverTime, overwrite)
    if not (db and itemID) then return false end
    copper = tonumber(copper)
    if not copper or copper <= 0 then return false end

    local day = Config:DayStamp(serverTime)
    local hist = db.priceHistory
    local bucket = hist[itemID]
    if not bucket then
        local itemCount = 0
        for _ in pairs(hist) do itemCount = itemCount + 1 end
        if itemCount >= Config.PRICE_HISTORY_MAX_ITEMS then return false end
        bucket = {}
        hist[itemID] = bucket
    end
    if bucket[day] ~= nil and not overwrite then return false end
    local fresh = (bucket[day] == nil)
    bucket[day] = math.floor(copper + 0.5)
    if not fresh then
        -- Перезапись - это не новая запись, и считать её новой нельзя: иначе
        -- «записей за сегодня: 500» будет означать пятисотую перезапись одного
        -- и того же, а не пятьсот предметов.
        return true
    end

    -- Trim the oldest day for this item if it has grown too long.
    local days = {}
    for d in pairs(bucket) do days[#days + 1] = d end
    if #days > Config.PRICE_HISTORY_MAX_DAYS then
        table.sort(days)
        for i = 1, #days - Config.PRICE_HISTORY_MAX_DAYS do bucket[days[i]] = nil end
    end
    return true
end

function Config:FinishSnapshot(serverTime, written)
    if not db then return end
    local day = Config:DayStamp(serverTime)
    local meta = db.priceHistoryMeta
    if meta.lastDay ~= day then
        meta.lastDay = day
        meta.days = (meta.days or 0) + 1
        if not meta.firstDay then meta.firstDay = day end
    end
    local items = 0
    for _ in pairs(db.priceHistory) do items = items + 1 end
    meta.items = items
    meta.lastWritten = written or 0
end

function Config:PriceHistoryMeta()
    return (db and db.priceHistoryMeta) or { days = 0, items = 0 }
end

function Config:PriceHistoryFor(itemID)
    if not (db and itemID) then return nil end
    return db.priceHistory[itemID]
end

-- Dismissals -------------------------------------------------------------

-- Returns true when the dismissal was actually recorded, so the caller does not
-- tell the player "скрыл на сутки" about a card that is still there.
function Config:Dismiss(cardKey, now, seconds)
    if not (db and cardKey) then return false end
    -- A dismissal we cannot date is not a dismissal. Without a real clock the
    -- expiry lands in 1970 (already expired, so the click does nothing) or, if
    -- the clock comes back as nothing on the read side, never expires at all.
    -- Neither is what the player asked for, so nothing is written.
    now = tonumber(now)
    if not now or now <= 0 then return false end
    db.dismissed[cardKey] = now + (tonumber(seconds) or ns.DISMISS_SECONDS)
    return true
end

-- Returns whether the card is hidden, and until when. The second value is what
-- lets the advice say "they come back in four hours" instead of leaving the
-- player staring at an empty list with no idea why.
function Config:IsDismissed(cardKey, now)
    if not (db and cardKey) then return false end
    local expiry = db.dismissed[cardKey]
    if type(expiry) ~= "number" then return false end
    -- No usable clock: every dismissal would compare as still in force and the
    -- whole advice list would go dark with no expiry to wait out. Showing a
    -- card the player hid is the smaller mistake, and the record is kept so
    -- the dismissal resumes as soon as the clock answers again.
    now = tonumber(now)
    if not now or now <= 0 then return false end
    if now > expiry then
        db.dismissed[cardKey] = nil
        return false
    end
    return true, expiry
end

-- THE LAST THING HIDDEN, so undoing it is always one step away.
--
-- The player has now twice hidden a pile of advice without meaning to, and the
-- second time it cost them the thing this was all for: the corrected gear
-- advice was on screen and they never saw it, because ten cards were hidden by
-- accident. "Вернуть все" exists, but it is a sledgehammer and it is only
-- discoverable if you already know what happened.
function Config:RememberLastDismiss(cardKey, title, now, seconds)
    if not db then return end
    db.lastDismiss = {
        key = cardKey, title = title, at = now, seconds = seconds,
    }
end

function Config:LastDismiss()
    return db and db.lastDismiss or nil
end

-- Undo exactly the last hide. Returns the entry it undid, or nil.
function Config:UndoLastDismiss()
    if not (db and type(db.lastDismiss) == "table") then return nil end
    local entry = db.lastDismiss
    if entry.key and db.dismissed then db.dismissed[entry.key] = nil end
    db.lastDismiss = nil
    return entry
end

-- Unhide everything at once. Dismissals are the one setting a player can
-- accumulate until the addon has nothing left to say, so there has to be a way
-- back that does not involve deleting the SavedVariables. Returns how many were
-- cleared; nothing else in the config is touched.
function Config:ClearDismissed()
    if not (db and type(db.dismissed) == "table") then return 0 end
    local n = 0
    for key in pairs(db.dismissed) do
        db.dismissed[key] = nil
        n = n + 1
    end
    -- И ПАМЯТЬ О ПОСЛЕДНЕМ СКРЫТИИ ТОЖЕ.
    --
    -- Иначе после «Вернуть все» команда /fp undo отвечает «вернул: ‹карточка›»
    -- про карточку, которая уже не скрыта: сообщение есть, действия нет.
    -- Нечего возвращать - значит, и записи быть не должно.
    db.lastDismiss = nil
    return n
end

function Config:DismissedCount(now)
    if not (db and type(db.dismissed) == "table") then return 0 end
    local n = 0
    for _, expiry in pairs(db.dismissed) do
        if type(expiry) == "number" and expiry >= (now or 0) then n = n + 1 end
    end
    return n
end

-- СВОЯ КНИГА ЗАКУПОК ----------------------------------------------------
--
-- Хранение и пределы. Вся арифметика и вся сверка - в Logic/Ledger.lua; здесь
-- только запись, чтение и то, чтобы файл сохранений не рос бесконечно.
--
-- Пределы разные у журнала и у итогов, и это нарочно: журнал нужен, чтобы
-- человек мог посмотреть «что я покупал», и ему хватает последних записей; а
-- итоги по предмету - то, на чём держится себестоимость, и их терять нельзя.
-- Поэтому обрезка журнала НЕ вычитает ничего из итогов.

Config.LEDGER_MAX_ENTRIES  = 600    -- журнал: сколько последних записей помнить
Config.LEDGER_MAX_ITEMS    = 2000   -- по скольким предметам вести итоги
Config.LEDGER_MAX_PER_ITEM = 12     -- сколько последних цен помнить по предмету

-- Книгу достраивает Config:Bind через U.applyDefaults (ledger лежит в
-- DEFAULTS), поэтому здесь ПРОСТОЙ доступ, без доработки на каждом обращении.
-- Это не экономия на спичках: Price:Buy зовётся 269 раз за пересчёт, и каждый
-- вызов спрашивает книгу - рекурсивный обход дефолтов на этом пути ничего не
-- проверял бы, а стоил бы на каждом из них.
function Config:Ledger()
    if not db then return nil end
    -- Единственный случай, когда достраивать всё-таки надо: книги нет вовсе
    -- (старые сохранения, записанные до её появления).
    if type(db.ledger) ~= "table" then
        db.ledger = U.deepCopy(Config.DEFAULTS.ledger)
    end
    return db.ledger
end

function Config:LedgerMeta()
    local L = Config:Ledger()
    return (L and L.meta) or { entries = 0 }
end

function Config:LedgerEntries()
    local L = Config:Ledger()
    return (L and L.entries) or {}
end

function Config:LedgerFor(itemID)
    local L = Config:Ledger()
    if not (L and itemID) then return nil end
    return L.byItem[itemID]
end

local function blankSide()
    return { n = 0, qty = 0, copper = 0, firstT = nil, lastT = nil,
             minUnit = nil, maxUnit = nil, lastUnit = nil }
end

-- Записать одну сверенную сделку. Возвращает true, когда запись легла в книгу.
--
-- `entry` приходит из Ledger:Observe и уже проверен: itemID, kind, qty > 0,
-- copper > 0, unit > 0, t > 0. Здесь ничего не досчитывается - иначе правило
-- «цена за штуку считается в одном месте» потеряется.
function Config:LedgerAdd(entry)
    local L = Config:Ledger()
    if not (L and type(entry) == "table") then return false end
    -- Половины книги не бывает, но сохранения живут дольше кода: поля, которых
    -- в файле не оказалось, заводятся здесь, а не роняют запись.
    if type(L.entries) ~= "table" then L.entries = {} end
    if type(L.byItem) ~= "table" then L.byItem = {} end
    if type(L.meta) ~= "table" then L.meta = { entries = 0 } end
    local id = tonumber(entry.itemID)
    local qty, copper, unit = tonumber(entry.qty), tonumber(entry.copper), tonumber(entry.unit)
    local t = tonumber(entry.t)
    local kind = entry.kind
    if not (id and qty and copper and unit and t) then return false end
    if qty <= 0 or copper <= 0 or unit <= 0 or t <= 0 then return false end
    if kind ~= "buy" and kind ~= "sell" then return false end

    local bucket = L.byItem[id]
    if not bucket then
        local n = 0
        for _ in pairs(L.byItem) do n = n + 1 end
        if n >= Config.LEDGER_MAX_ITEMS then return false end
        bucket = { buy = blankSide(), sell = blankSide(), recent = {} }
        L.byItem[id] = bucket
    end
    bucket.buy = bucket.buy or blankSide()
    bucket.sell = bucket.sell or blankSide()
    bucket.recent = bucket.recent or {}

    local side = bucket[kind]
    side.n = (side.n or 0) + 1
    side.qty = (side.qty or 0) + qty
    side.copper = (side.copper or 0) + copper
    side.lastT = t
    side.lastUnit = unit
    if not side.firstT or t < side.firstT then side.firstT = t end
    if not side.minUnit or unit < side.minUnit then side.minUnit = unit end
    if not side.maxUnit or unit > side.maxUnit then side.maxUnit = unit end

    bucket.recent[#bucket.recent + 1] = { u = unit, q = qty, t = t,
                                          k = kind, w = entry.where }
    while #bucket.recent > Config.LEDGER_MAX_PER_ITEM do
        table.remove(bucket.recent, 1)
    end

    L.entries[#L.entries + 1] = { id = id, k = kind, w = entry.where,
                                  q = qty, c = copper, u = unit, t = t }
    -- Обрезается СТАРОЕ, и только в журнале: итоги выше уже сложены.
    while #L.entries > Config.LEDGER_MAX_ENTRIES do table.remove(L.entries, 1) end

    local meta = L.meta
    meta.entries = (meta.entries or 0) + 1
    meta.lastT = t
    if not meta.firstT or t < meta.firstT then meta.firstT = t end
    return true
end

-- Сверка отказалась записывать. Причина запоминается не ради статистики: из
-- неё видно, чего книга НЕ видит, и это попадает в отчёт для человека.
function Config:LedgerSkip(reason)
    local L = Config:Ledger()
    if not L then return end
    local meta = L.meta
    meta.skipped = (meta.skipped or 0) + 1
    if reason then
        meta.skips = meta.skips or {}
        meta.skips[reason] = (meta.skips[reason] or 0) + 1
    end
end

function Config:ClearLedger()
    local L = Config:Ledger()
    if not L then return 0 end
    local n = #L.entries
    L.entries = {}
    L.byItem = {}
    L.meta = { entries = 0, observed = 0, skipped = 0, skips = {} }
    return n
end

-- Shopping list ----------------------------------------------------------

function Config:SetShopping(itemID, qty)
    if not (db and itemID) then return end
    qty = tonumber(qty) or 0
    if qty <= 0 then db.shoppingList[itemID] = nil else db.shoppingList[itemID] = qty end
end

function Config:Shopping()
    return (db and db.shoppingList) or {}
end

-- Сколько позиций игрок закрепил в своём списке.
function Config:ShoppingCount()
    local n = 0
    for _ in pairs(self:Shopping()) do n = n + 1 end
    return n
end

-- Стереть список целиком. Возвращает, сколько позиций убрано. Единственное
-- место, которое это делает: интерфейс сюда попадает только через вопрос
-- ShoppingList:RequestClear.
function Config:ClearShopping()
    if not (db and type(db.shoppingList) == "table") then return 0 end
    local n = 0
    for key in pairs(db.shoppingList) do
        db.shoppingList[key] = nil
        n = n + 1
    end
    return n
end

-- Recipe cache (per character) ------------------------------------------

function Config:StoreRecipes(professionName, list, now)
    if not (charDB and professionName) then return end
    charDB.recipes[professionName] = { scanned = now or 0, list = list or {} }
end

function Config:StoredRecipes()
    return (charDB and charDB.recipes) or {}
end

function Config:NoteHistory(entry)
    if not db then return end
    db.history[#db.history + 1] = entry
    if #db.history > 100 then table.remove(db.history, 1) end
end

return Config
