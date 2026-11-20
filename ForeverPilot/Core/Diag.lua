-- ForeverPilot / Core/Diag.lua
--
-- Self-diagnostics. The addon writes down what it actually did, so a problem
-- can be read out of a file afterwards instead of guessed at from "it doesn't
-- work".
--
-- Three rules this module lives by:
--
--   1. It never changes behaviour. Every number recorded here is a number the
--      addon already computed. There is no extra scanning, no extra API call,
--      no second pass over anything. If recording a fact would cost work, the
--      fact is not recorded.
--
--   2. It never touches the global error handler. seterrorhandler is a shared
--      resource: hooking it would hide or corrupt other addons' error reports.
--      Instead our own entry points are wrapped in xpcall, so we catch only
--      what happens inside our own code.
--
--   3. It is bounded. Every list has a cap, only the last three sessions are
--      kept, and the whole table is trimmed on every write. A diagnostics file
--      that grows without limit is a bug of its own.
--
-- The data goes to its own SavedVariables, FOREVERPILOT_DIAG, kept separate
-- from the settings so it can be deleted or shared without touching anything
-- the player configured.
local ADDON, ns = ...

local Diag = {}
ns.Diag = Diag

Diag.SCHEMA = 1
Diag.MAX_SESSIONS = 3

-- Caps. Chosen so a session is a few tens of kilobytes at worst.
Diag.CAP = {
    errors = 25,
    suspicious = 60,
    cards = 20,
    perf = 20,
    log = 60,
    calls = 80,
    detect = 120,
    funnelExamples = 2,    -- per filter, per funnel: an example, not a dump
    priceDecisions = 40,
    -- СВОДКА УРЕЗАЛАСЬ МОЛЧА, И ЭТО СЪЕДАЛО САМОЕ ВАЖНОЕ.
    --
    -- Предел был 16 строк, и этого хватало ровно до тех пор, пока в сводку не
    -- добавили ещё две про расход пересчёта: за ними из файла молча исчезли
    -- строки «Против прошлого запуска» и «Странность: …», то есть находки
    -- самопроверки - то, ради чего сводку и читают. Теперь предел с запасом, а
    -- об урезании, если оно всё-таки случится, сводка говорит сама (см. add).
    summaryLines = 28,
}

-- Reason codes -----------------------------------------------------------
--
-- A zero with no reason is the least useful thing a diagnostic can record, and
-- free text is only slightly better: it cannot be compared between sessions and
-- it cannot be grepped. So every zero carries a code out of THIS list, and the
-- human sentence is looked up from it. A module that reports zero without a
-- code gets the code NO_REASON_GIVEN, which is itself a defect and is reported
-- as one - the same rule the bank module tripped over, now applied everywhere.
Diag.REASON = {
    -- nothing was read
    NOT_SEEN           = "мы этого ещё ни разу не видели",
    EMPTY              = "источник прочитан, но он пуст",
    NO_API             = "нужной функции нет на этом клиенте",
    API_SILENT         = "функция есть, но данных не вернула",
    -- recipes and professions
    NO_PROFESSION      = "подходящих профессий у персонажа нет",
    WINDOW_NEVER_OPEN  = "окно профессии ни разу не открывали — игра не отдаёт рецепты",
    NOTHING_LEARNED    = "рецепты есть, но ни один не помечен выученным",
    -- prices
    NO_PRICES          = "цен нет, считать не из чего",
    NO_PRICE_SOURCE    = "ни один источник цен не ответил",
    -- advice
    NOT_PROFITABLE     = "ничего не продаётся дороже материалов",
    NO_UPGRADE         = "ничего лучше текущего не нашлось",
    NO_STATS           = "характеристики не читаются, сравнивать нечем",
    AT_SKILL_CAP       = "навык на пределе — крафт прироста не даёт",
    ALL_DONE           = "всё, что можно было сделать, уже сделано",
    NOTHING_TO_BUY     = "покупать нечего",
    NOT_BUYABLE        = "это добыча, а не товар — купить негде",
    FILTERED_OUT       = "кандидаты были, но все отсеялись фильтрами",
    HIDDEN_BY_PLAYER   = "всё скрыто игроком",
    -- сверка справочника с игрой (Logic/SourceCheck.lua)
    SOURCE_NOT_COVERED = "справочник не покрывает ваши профессии — сверять не с чем",
    SOURCE_IDS_DIFFER  = "номера рецептов клиента не совпали с номерами справочника",
    -- the defect itself
    NO_REASON_GIVEN    = "причина не указана — это дефект самой диагностики",
}

function Diag:ReasonText(code)
    return Diag.REASON[code]
end

-- The live session. Built in memory at load and attached to the SavedVariables
-- table on ADDON_LOADED, so every later mutation persists without copying.
Diag.session = nil
Diag.enabled = true

local function now()
    return (ns.Api and ns.Api.ServerTime and ns.Api:ServerTime())
        or (os and os.time and os.time()) or 0
end

local function clock()
    -- Milliseconds. debugprofilestop is the only high-resolution clock a WoW
    -- addon gets; os.clock is the fallback outside the game.
    local f = _G and _G.debugprofilestop
    if type(f) == "function" then
        local ok, ms = pcall(f)
        if ok and type(ms) == "number" then return ms end
    end
    if os and os.clock then return os.clock() * 1000 end
    return 0
end
Diag.clock = clock

local function stamp(t)
    t = t or now()
    if os and os.date then
        local ok, text = pcall(os.date, "%Y-%m-%d %H:%M:%S", t)
        if ok then return text end
    end
    return tostring(t)
end

-- Session scaffolding ----------------------------------------------------

local function newSession()
    return {
        schema = Diag.SCHEMA,
        startedAt = now(),
        startedAtText = stamp(),
        env = {},
        detect = {},        -- name -> true/false  (does the function exist)
        calls = {},         -- name -> { tries, gotData, empty, failed, note }
        modules = {},       -- module -> { in, out, reason, ... }
        errors = {},        -- { where, message, traceback, at, count }
        suspicious = {},    -- { code, text, detail, at }
        perf = { recomputes = 0, totalMs = 0, peakMs = 0, lastMs = 0, samples = {} },
        cards = {},         -- the first N cards exactly as shown
        log = {},           -- notable one-off events
        counters = {},      -- free-form tallies
        funnels = {},       -- branch -> where the candidates went
        prices = {},        -- itemID -> which sources answered and which won
        dedupe = {},        -- how many cards collapsed, and why
        -- СПИСОК ЗАКАЗА ДАННЫХ. См. Diag:Want ниже: не текст, а структура,
        -- по которой данные можно пополнять программно.
        wanted = {},
        dataVersions = nil, -- какие внешние базы доступны и насколько они свежи
        summary = nil,      -- the plain-Russian report, written on each build
        delta = nil,        -- what changed since the previous session
    }
end

function Diag:Init()
    if not self.session then
        self.session = newSession()
        -- Память счётчика заказа - на сессию: она существует ровно затем, чтобы
        -- `total` считал РАЗНЫЕ позиции этой сессии, и переносить её из
        -- предыдущей было бы такой же ложью, только в другую сторону.
        Diag.wantSeen = {}
    end
    return self.session
end

-- Attach the in-memory session to the SavedVariables table. Called once from
-- the bootstrap, after the globals exist.
function Diag:Bind(store)
    self:Init()
    if type(store) ~= "table" then return self.session end

    store.schema = Diag.SCHEMA
    store.addon = ns.VERSION
    if type(store.sessions) ~= "table" then store.sessions = {} end

    -- Drop anything older than the last two, then add ours as the newest.
    while #store.sessions >= Diag.MAX_SESSIONS do
        table.remove(store.sessions, 1)
    end
    -- Kept before ours goes on the end, so the delta has something to compare
    -- against. A reference, not a copy: it is already in the file.
    Diag.prevSession = store.sessions[#store.sessions]
    store.sessions[#store.sessions + 1] = self.session
    store.latest = #store.sessions
    self.store = store
    return self.session
end

-- Recording primitives ---------------------------------------------------

local function cap(list, limit)
    while #list > limit do table.remove(list, 1) end
end

function Diag:Log(text, detail)
    if not self.enabled then return end
    local s = self:Init()
    s.log[#s.log + 1] = { at = now(), text = tostring(text), detail = detail }
    cap(s.log, Diag.CAP.log)
end

function Diag:Count(key, by)
    if not self.enabled then return end
    local s = self:Init()
    s.counters[key] = (s.counters[key] or 0) + (by or 1)
end

-- Feature detection: did this function exist at all?
function Diag:Detect(name, exists)
    if not self.enabled then return exists end
    local s = self:Init()
    s.detect[name] = exists and true or false
    return exists
end

-- Call outcome. This is the part that matters most: a function can exist and
-- still hand back nothing, which is exactly the failure mode we could not test
-- outside the game.
--   gotData == true   -> returned something usable
--   gotData == false  -> returned nil or an empty result
--   gotData == nil    -> the call itself failed
function Diag:Call(name, gotData, note)
    if not self.enabled then return end
    local s = self:Init()
    local e = s.calls[name]
    if not e then
        e = { tries = 0, gotData = 0, empty = 0, failed = 0 }
        s.calls[name] = e
    end
    e.tries = e.tries + 1
    if gotData == true then e.gotData = e.gotData + 1
    elseif gotData == false then e.empty = e.empty + 1
    else e.failed = e.failed + 1 end
    if note then e.note = note end
end

-- Module result. `reason` is required when out == 0: a zero without a reason is
-- the single least useful thing a diagnostic can record.
--
-- `reasonCode` is the machine-readable half and comes out of Diag.REASON. Pass
-- the code and the sentence is looked up; pass both and the sentence wins for
-- display while the code stays comparable between sessions.
function Diag:Module(name, data)
    if not self.enabled then return end
    local s = self:Init()
    data = data or {}
    local existing = s.modules[name] or {}
    for k, v in pairs(data) do existing[k] = v end

    -- A reason explains a zero. Once the module reports output, last pass's
    -- reason is no longer true, and merging cannot clear it on its own because
    -- `reason = nil` never appears in pairs(). Left alone, /fp diag kept
    -- printing "ни одна ветка советов ничего не выдала" over a working list -
    -- which is the first line anyone reads when hunting an empty list.
    local out = tonumber(existing.out) or 0
    if out > 0 and data.reason == nil and data.reasonCode == nil then
        existing.reason = nil
        existing.reasonCode = nil
    end

    if out <= 0 then
        if existing.reasonCode and not existing.reason then
            existing.reason = Diag.REASON[existing.reasonCode]
                or ("код причины неизвестен: " .. tostring(existing.reasonCode))
        end
        if not existing.reasonCode then
            if existing.reason then
                -- Free text with no code: still a gap, because nothing can
                -- compare it between sessions. Marked rather than accepted.
                existing.reasonCode = "FREETEXT"
                Diag:Count("diag.reasonWithoutCode")
            else
                existing.reasonCode = "NO_REASON_GIVEN"
                existing.reason = Diag.REASON.NO_REASON_GIVEN
                Diag:Suspect("diag-no-reason",
                    "модуль «" .. tostring(name) .. "» выдал 0 и не назвал причину"
                    .. " — это дефект диагностики, а не отсутствие данных")
            end
        end
    end
    s.modules[name] = existing
end

-- Loss funnel ------------------------------------------------------------
--
-- "in = 530, out = 4" says nothing about where the other 526 went, and that is
-- precisely the question every investigation starts with. So each branch counts
-- its candidates in, names the filter that threw each one away, and keeps one
-- or two examples of what that filter rejected.
--
-- Cost per candidate is one table index and one addition; the examples are
-- capped at two per filter. One funnel object per branch name is reused across
-- rebuilds so nothing is allocated in the hot loop.

local function describe(item)
    if item == nil then return "?" end
    local t = type(item)
    if t == "string" then return item end
    if t == "number" then return tostring(item) end
    if t ~= "table" then return tostring(item) end
    local name = item.name or item.title
    local id = item.id or item.itemID or item.recipeID
    if name and id then return tostring(name) .. " #" .. tostring(id) end
    if name then return tostring(name) end
    if id then return "#" .. tostring(id) end
    return "таблица"
end
Diag.describe = describe

local Funnel = {}
Funnel.__index = Funnel

function Funnel:In(item)
    self.data["in"] = (self.data["in"] or 0) + 1
    return self
end

function Funnel:Drop(filter, item, note)
    local d = self.data.drops
    local e = d[filter]
    if not e then
        e = { n = 0, examples = {} }
        d[filter] = e
        self.data.order[#self.data.order + 1] = filter
    end
    e.n = e.n + 1
    if #e.examples < Diag.CAP.funnelExamples then
        e.examples[#e.examples + 1] = describe(item) .. (note and (" — " .. note) or "")
    end
    return self
end

function Funnel:Out(n)
    self.data.out = tonumber(n) or 0
    return self
end

-- The accounting check: everything that came in must be either out or dropped.
-- A mismatch means a branch is losing candidates somewhere it does not report,
-- which is exactly the hole this whole mechanism exists to close.
function Funnel:Finish(outCount)
    if outCount ~= nil then self:Out(outCount) end
    local dropped = 0
    for _, e in pairs(self.data.drops) do dropped = dropped + e.n end
    self.data.dropped = dropped
    local accounted = (self.data.out or 0) + dropped
    self.data.unaccounted = (self.data["in"] or 0) - accounted
    if self.data.unaccounted ~= 0 then
        Diag:Suspect("funnel-unaccounted", string.format(
            "ветка «%s»: вошло %d, вышло %d, отсеяно %d — %d кандидатов"
            .. " потерялись без объяснения",
            tostring(self.name), self.data["in"] or 0, self.data.out or 0,
            dropped, self.data.unaccounted))
    end
    return self.data
end

Diag.funnelObjects = {}

function Diag:Funnel(name)
    if not self.enabled then return nil end
    local s = self:Init()
    local obj = Diag.funnelObjects[name]
    if not obj then
        obj = setmetatable({ name = name }, Funnel)
        Diag.funnelObjects[name] = obj
    end
    -- Fresh counters per build; the table lives in the session so it persists.
    local data = { ["in"] = 0, out = 0, drops = {}, order = {} }
    s.funnels[name] = data
    obj.data = data
    return obj
end

-- Price decisions --------------------------------------------------------
--
-- Which sources were asked about this item, what each answered, which one won
-- and why. Written once per item per build, straight out of the routes the
-- price provider already collected - no second lookup.
function Diag:PriceDecision(itemID, kind, routes, chosen, why, extra)
    if not self.enabled then return end
    local s = self:Init()
    local key = tostring(kind or "buy") .. ":" .. tostring(itemID)
    if s.prices[key] then return end
    local n = 0
    for _ in pairs(s.prices) do n = n + 1 end
    if n >= Diag.CAP.priceDecisions then
        s.pricesOverflow = (s.pricesOverflow or 0) + 1
        return
    end
    local asked = {}
    for _, r in ipairs(routes or {}) do
        asked[#asked + 1] = { src = r.src, copper = r.copper, conf = r.conf, age = r.age }
    end
    local e = {
        itemID = itemID, kind = kind or "buy",
        asked = asked,
        chosenSrc = chosen and chosen.src or nil,
        chosenCopper = chosen and chosen.copper or nil,
        chosenConf = chosen and chosen.conf or nil,
        why = why,
    }
    -- The history verdict, the untouched live price and whether anybody actually
    -- listed the thing. All three are what was missing when a 167x outlier came
    -- out of this function labelled only "vendor".
    for k, v in pairs(extra or {}) do e[k] = v end
    s.prices[key] = e
end

-- Errors -----------------------------------------------------------------

local function traceback(message)
    local parts = {}
    local ds = _G and _G.debugstack
    if type(ds) == "function" then
        local ok, text = pcall(ds, 2, 12, 12)
        if ok and type(text) == "string" then parts[#parts + 1] = text end
    end
    if #parts == 0 and debug and debug.traceback then
        local ok, text = pcall(debug.traceback, message, 2)
        if ok and type(text) == "string" then parts[#parts + 1] = text end
    end
    return table.concat(parts, "\n")
end

function Diag:Error(where, message, trace)
    local s = self:Init()
    message = tostring(message or "?")
    -- The same error usually repeats every recompute. Count it once.
    for _, e in ipairs(s.errors) do
        if e.where == where and e.message == message then
            e.count = e.count + 1
            e.lastAt = now()
            return e
        end
    end
    local entry = {
        where = where, message = message,
        traceback = trace or traceback(message),
        at = now(), atText = stamp(), count = 1,
    }
    s.errors[#s.errors + 1] = entry
    cap(s.errors, Diag.CAP.errors)
    return entry
end

-- Wrap one of OUR entry points. Only our code runs inside, so nothing another
-- addon does can be swallowed here, and the global error handler is untouched.
function Diag:Guard(where, fn, ...)
    if type(fn) ~= "function" then return false end
    local args = { ... }
    local n = select("#", ...)
    local captured
    local ok, result = xpcall(function()
        return fn(unpack(args, 1, n))
    end, function(err)
        captured = traceback(err)
        return err
    end)
    if not ok then
        Diag:Error(where, result, captured)
        return false, result
    end
    return true, result
end

-- Performance ------------------------------------------------------------

function Diag:TimerStart()
    return clock()
end

function Diag:TimerStop(startMs, label)
    if not self.enabled then return 0 end
    local ms = clock() - (startMs or 0)
    if ms < 0 then ms = 0 end
    local s = self:Init()
    local p = s.perf
    p.recomputes = p.recomputes + 1
    p.totalMs = p.totalMs + ms
    p.lastMs = ms
    if ms > p.peakMs then p.peakMs = ms; p.peakAt = now(); p.peakLabel = label end
    p.avgMs = p.totalMs / p.recomputes
    p.samples[#p.samples + 1] = { ms = ms, at = now(), label = label }
    cap(p.samples, Diag.CAP.perf)
    return ms
end

-- Suspicious -------------------------------------------------------------
--
-- НАХОДКА, КОТОРАЯ ОТНОСИТСЯ К ОДНОЙ КАРТОЧКЕ, ДОЕЗЖАЕТ ДО ЭТОЙ КАРТОЧКИ.
--
-- Живой прогон игрока: самопроверка писала в файл «„На продажу: Небесно-голубая
-- краска“: выручка 1з 24с против цены торговца 75м - это в 166 раз больше», и
-- счётчик говорил, что так на каждом пересчёте. Карточка при этом стояла вторым
-- советом сверху и выглядела как любой другой совет. Аддон сам себе не верил -
-- и молчал об этом на экране.
--
-- Дело было не в одной проверке. Самопроверки шли ПОСЛЕ ранжирования и писали
-- только в файл, то есть ни одна из двух с лишним десятков находок «про эту
-- карточку» не могла попасть ни в текст, ни в место в списке. Поэтому закрыто
-- это одним ходом, а не по проверке: пока карточки «привязаны», любая находка с
-- ключом карточки прикладывается к самой карточке (card.doubts), а движок
-- превращает приложенное в текст, достоверность и место (Logic/Risk.lua).
--
-- ПОЧЕМУ ДО ПРОВЕРКИ `enabled`. Диагностику можно выключить - честность на
-- карточке от этого зависеть не имеет права. Запись в файл без диагностики не
-- идёт, а сомнение на карточке идёт всегда.
Diag.cardByKey = nil
Diag.doubtsRouted = 0
Diag.doubtsLost = 0

-- Привязать список карточек на время одного прохода самопроверок.
function Diag:BindCards(cards)
    local byKey
    if type(cards) == "table" then
        byKey = {}
        for _, card in ipairs(cards) do
            if type(card) == "table" and card.key ~= nil and byKey[card.key] == nil then
                byKey[card.key] = card
            end
        end
    end
    Diag.cardByKey = byKey
    Diag.doubtsRouted, Diag.doubtsLost = 0, 0
    return byKey
end

-- Снять привязку. Возвращает, сколько находок доехало до карточек и сколько
-- назвали ключ, которого в списке нет: второе число - это дефект, а не ноль.
function Diag:UnbindCards()
    local routed, lost = Diag.doubtsRouted or 0, Diag.doubtsLost or 0
    Diag.cardByKey = nil
    return routed, lost
end

-- Приложить находку к карточке, которую она называет. Повтор по тому же коду
-- на той же карточке - это одна находка, а не две.
function Diag:RouteDoubt(code, text, detail)
    local index = Diag.cardByKey
    if not index then return nil end
    local key = (type(detail) == "table") and detail.key or nil
    if key == nil then return nil end
    local card = index[key]
    if not card then
        Diag.doubtsLost = (Diag.doubtsLost or 0) + 1
        return nil
    end
    local list = card.doubts
    if not list then list = {}; card.doubts = list end
    for _, d in ipairs(list) do
        if d.code == code then return d end
    end
    local doubt = { code = code, text = tostring(text) }
    list[#list + 1] = doubt
    Diag.doubtsRouted = (Diag.doubtsRouted or 0) + 1
    return doubt
end

function Diag:Suspect(code, text, detail)
    -- Сначала на карточку, потом в файл: см. комментарий выше.
    Diag:RouteDoubt(code, text, detail)
    if not self.enabled then return end
    local s = self:Init()
    -- Collapse repeats: the interesting thing is that it happened, plus a count.
    for _, e in ipairs(s.suspicious) do
        if e.code == code and e.text == text then
            e.count = e.count + 1
            return e
        end
    end
    local entry = {
        code = code, text = tostring(text), detail = detail,
        at = now(), count = 1,
    }
    s.suspicious[#s.suspicious + 1] = entry
    cap(s.suspicious, Diag.CAP.suspicious)
    return entry
end

function Diag:ClearSuspicions()
    local s = self:Init()
    s.suspicious = {}
end

-- Список заказа данных ---------------------------------------------------
--
-- ЗАЧЕМ ЭТО ОТДЕЛЬНЫМ РАЗДЕЛОМ. Петля «играю → аддон записал, чего не хватило
-- → данные добавили → играю дальше» до сих пор держалась на том, что кто-то
-- вычитывал нехватку между строк: часть фактов лежала в странностях, часть в
-- воронках, часть в счётчиках, и все - словами. По словам пополнять данные
-- нельзя. Поэтому здесь ровно то же самое, но структурой: ID, сколько раз
-- встретился, где именно встретился, и общий счётчик.
--
-- Что ВАЖНО понимать про размер: позиций бывает много (55 предметов без бонусов
-- в одной живой сессии), и файл не должен расти без предела. Поэтому на каждый
-- вид заказа хранятся самые частые WANT_KEEP позиций, а полное число всегда
-- известно: `total` считает все, `kept` - сколько сохранено.
--
-- Виды заказа (ключи раздела) - закрытый список, чтобы по нему можно было
-- ходить программно, не угадывая имена.
Diag.WANT = {
    itemsNotInDB        = "itemsNotInDB",
    itemsNoPrice        = "itemsNoPrice",
    pricesStale         = "pricesStale",
    vendorCeilingUnknown = "vendorCeilingUnknown",
    npcNoCoords         = "npcNoCoords",
    recipesNoSchematic  = "recipesNoSchematic",
    enchantsUnknownSlot = "enchantsUnknownSlot",
    disenchantUnknown   = "disenchantUnknown",
    statsUnknown        = "statsUnknown",
    familiesIncomplete  = "familiesIncomplete",
    -- ОБЛИК, ПРО КОТОРЫЙ НЕ ОТВЕТИЛИ. Единственный способ узнать, отвечает ли
    -- клиент про облик вообще: офлайн такого ответа нет ни у кого, а здесь
    -- видно, по скольким вещам он не пришёл в живой игре.
    appearanceUnknown   = "appearanceUnknown",
}

-- Человеческое название вида - для одной строки в сводке и для /fp diag.
Diag.WANT_LABEL = {
    itemsNotInDB        = "предметов нет во внешней базе (или без характеристик)",
    itemsNoPrice        = "предметов без цены ни в одном источнике",
    pricesStale         = "цен старше суток",
    vendorCeilingUnknown = "предметов, где цену беру с аукциона, а потолка торговца не знаю",
    npcNoCoords         = "NPC без координат",
    recipesNoSchematic  = "рецептов без состава реагентов",
    enchantsUnknownSlot = "формул чар без слота",
    disenchantUnknown   = "предметов без данных о распыле",
    statsUnknown        = "неизвестных кодов характеристик",
    familiesIncomplete  = "слотов с недособранным семейством вариантов",
    appearanceUnknown   = "вещей, про облик которых клиент не ответил",
}

-- Какие виды заказа считаются «про предметы», «про цены» и «про торговцев» -
-- для той самой одной строки, которую видит игрок.
-- СТАРАЯ ЦЕНА - ЭТО НЕ «НЕТ ДАННЫХ», И СКЛАДЫВАТЬ ИХ НЕЛЬЗЯ.
--
-- Раньше группа `prices` складывала «цены нет ни в одном источнике» и «цена
-- есть, но ей больше суток», и игрок читал «данных не хватило по 5741 цене» о
-- ценах, которые у аддона ЕСТЬ и которыми он честно пользуется. Теперь это две
-- разные величины: `prices` - чего не хватило, `stale` - что устарело.
--
-- И НЕИЗВЕСТНЫЙ ПОТОЛОК - ТРЕТЬЯ ОТДЕЛЬНАЯ ВЕЛИЧИНА. Цена у аддона ЕСТЬ и она
-- свежая; неизвестно другое - не продаёт ли это же торговец дешевле. Сложить её
-- с «цены нет» значило бы повторить ту же ошибку ещё раз.
Diag.WANT_GROUPS = {
    items        = { "itemsNotInDB", "disenchantUnknown" },
    prices       = { "itemsNoPrice" },
    pricesStale  = { "pricesStale" },
    pricesMissing = { "itemsNoPrice" },
    vendorCeiling = { "vendorCeilingUnknown" },
    npcs         = { "npcNoCoords" },
}

Diag.WANT_KEEP = 40

-- ПОЧЕМУ У СЧЁТЧИКА ЕСТЬ ОТДЕЛЬНАЯ ПАМЯТЬ, ЖИВУЩАЯ ВНЕ ФАЙЛА.
--
-- `total` обещает «сколько РАЗНЫХ позиций встретилось», и обещание было
-- неверным. Когда список сохранённых позиций заполнялся (WANT_KEEP = 40),
-- новая позиция не запоминалась НИГДЕ - и на следующем пересчёте считалась
-- новой снова. `total` поэтому рос не по числу разных позиций, а по числу
-- пересчётов.
--
-- В живом файле это видно арифметикой: 66 пересчётов дали total 7849,
-- 50 пересчётов - 5740. Это 118.9 и 114.8 «новых» позиций за пересчёт - одна
-- и та же величина, умноженная на число пересчётов. Игрок читал «данных не
-- хватило по 5741 цене» и имел все основания решить, что аддон тянет цены на
-- пол-игры; на самом деле за пересчёт он спрашивает цену по 227 разным
-- предметам, и это круг его собственных рецептов.
--
-- Поэтому встреченные ключи помнятся отдельно - в таблице на самом модуле, а
-- НЕ в сессии. Разница принципиальная: сессия уезжает в SavedVariables, и
-- пять тысяч ключей в файле - это та самая раздутость, от которой WANT_KEEP и
-- защищает. Этот же набор живёт только в памяти и в файл не попадает.
Diag.wantSeen = {}

function Diag:ResetWantSeen()
    Diag.wantSeen = {}
end

-- Записать заказ. `kind` - из Diag.WANT, `id` - itemID / npcID / recipeID или
-- строковый код (например "hp5"), `where` - короткая пометка о том, где это
-- встретилось ("equipped" / "bags" / "bank" / "craft-candidate" / "auction" /
-- ветка советов), `extra` - любые поля, которые нужны для пополнения
-- (возраст цены, имя, профессия).
--
-- Один и тот же ID, встреченный в разных местах, НЕ перезатирается: частота
-- растёт, а места копятся в `where` - иначе «попался в банке» вытесняло бы
-- «попался кандидатом на крафт», а это разные поводы добывать данные.
function Diag:Want(kind, id, where, extra)
    if not self.enabled then return end
    if id == nil then return end
    kind = Diag.WANT[kind] or kind
    if type(kind) ~= "string" then return end

    local s = self:Init()
    s.wanted = s.wanted or {}
    local bucket = s.wanted[kind]
    if not bucket then
        bucket = { items = {}, total = 0, kept = 0, hits = 0 }
        s.wanted[kind] = bucket
    end

    local key = tostring(id)
    local e = bucket.items[key]
    bucket.hits = bucket.hits + 1
    if not e then
        -- Новый ID - но новый ли? Проверяется по отдельной памяти, а не по
        -- сохранённому списку: список ограничен сороковкой, и всё, что в него
        -- не влезло, раньше считалось новым на каждом пересчёте заново.
        local seen = Diag.wantSeen[kind]
        if not seen then seen = {}; Diag.wantSeen[kind] = seen end
        if not seen[key] then
            seen[key] = true
            -- Не выбрасываем молча: общий счётчик растёт, и по нему видно, что
            -- сохранённое - только верхушка.
            bucket.total = bucket.total + 1
        end
        if bucket.kept >= Diag.WANT_KEEP then
            bucket.truncated = true
            return
        end
        e = { id = (tonumber(id) or id), n = 0, where = {} }
        bucket.items[key] = e
        bucket.kept = bucket.kept + 1
    end
    e.n = e.n + 1
    if where ~= nil then
        local w = tostring(where)
        e.where[w] = (e.where[w] or 0) + 1
    end
    if type(extra) == "table" then
        for k, v in pairs(extra) do
            -- Первое значение не затирается более поздним: возраст цены и имя
            -- предмета от первого попадания так же годятся, как от последнего,
            -- а перезапись каждый пересчёт - это просто мусор в файле.
            if e[k] == nil then e[k] = v end
        end
    end
end

-- Короткий итог заказа: сколько чего не хватило. Структура, не текст.
function Diag:WantedTotals()
    local s = self:Init()
    local out, grand = {}, 0
    for kind in pairs(Diag.WANT) do
        local b = (s.wanted or {})[kind]
        out[kind] = b and b.total or 0
        grand = grand + (b and b.total or 0)
    end
    out.grandTotal = grand
    for group, kinds in pairs(Diag.WANT_GROUPS) do
        local n = 0
        for _, kind in ipairs(kinds) do n = n + (out[kind] or 0) end
        out[group .. "Total"] = n
    end
    return out
end

-- Одна строка для игрока: «данных не хватило по N предметам, M ценам,
-- K торговцам». Нужна затем, чтобы молчание аддона не читалось как «всё знаю»:
-- он не знает, и это написано.
function Diag:WantedLine()
    local t = Diag:WantedTotals()
    if (t.grandTotal or 0) == 0 then return nil end
    local bits = {}
    local function part(n, one, few, many)
        if (n or 0) > 0 then
            bits[#bits + 1] = n .. " " .. ns.Util.plural(n, one, few, many)
        end
    end
    part(t.itemsTotal, "предмету", "предметам", "предметам")
    part(t.pricesTotal, "цене", "ценам", "ценам")
    part(t.npcsTotal, "торговцу", "торговцам", "торговцам")

    -- Старые цены - отдельным предложением и другими словами: это не нехватка
    -- данных, это их возраст, и действие от игрока требуется другое
    -- (отсканировать аукцион, а не добывать базу).
    local stale = t.pricesStaleTotal or 0
    local staleText = (stale > 0)
        and (" Ещё по " .. stale .. " "
             .. ns.Util.plural(stale, "предмету", "предметам", "предметам")
             .. " цена есть, но она старше суток — это возраст, а не нехватка.")
        or ""

    -- НЕИЗВЕСТНЫЙ ПОТОЛОК ТОРГОВЦА - ТРЕТЬЯ ФРАЗА, И ДЕЙСТВИЕ ОТ ИГРОКА ТРЕТЬЕ.
    --
    -- Цена у аддона есть и она свежая; неизвестно, не продаёт ли это же дешевле
    -- торговец с неограниченным запасом. Вендорную цену аддон знает только там,
    -- где игрок у торговца стоял, так что исполняется такой заказ одним
    -- действием - постоять у прилавка, - и путать его с «цены нет» нельзя.
    local ceiling = t.vendorCeilingTotal or 0
    if ceiling > 0 then
        staleText = staleText .. " По " .. ceiling .. " "
            .. ns.Util.plural(ceiling, "предмету", "предметам", "предметам")
            .. " цену беру с аукциона, а дешевле ли это у торговца — не знаю:"
            .. " у него вы не стояли."
    end

    if #bits == 0 then
        -- Не хватило только того, что в группы не попало (или вообще ничего,
        -- кроме старых цен). Второй случай - самый частый, и строка про
        -- нехватку в нём была бы неправдой.
        local missing = (t.grandTotal or 0) - stale - ceiling
        if missing <= 0 then
            if stale == 0 and ceiling == 0 then return nil end
            return "Все данные на месте." .. staleText
                .. " Список лежит в FOREVERPILOT_DIAG.wanted."
        end
        return "Данных не хватило: " .. missing .. " "
            .. ns.Util.plural(missing, "позиция", "позиции", "позиций") .. "."
            .. staleText
    end
    return "Данных не хватило по " .. table.concat(bits, ", ")
        .. ". Это не молчание — я просто этого не знаю; список лежит в"
        .. " FOREVERPILOT_DIAG.wanted." .. staleText
end

-- Версии внешних данных ---------------------------------------------------
--
-- Чтобы было видно, что устарело: одна таблица с версиями баз и датой сборки
-- наших собственных файлов данных. Всё через feature-detect и pcall: любая из
-- этих баз может отсутствовать, и это нормальный ответ, а не ошибка.
Diag.DATA_ADDONS = {
    "Polestar", "Polestar_ItemDB", "Polestar_Codex", "Polestar_QuestDB",
    "QuestieDB", "Questie", "Mastercraft", "Auctionator", "WhatsTraining",
    "Syndicator",
}

function Diag:CaptureDataVersions()
    local s = self:Init()
    local out = { ours = {}, external = {} }

    -- Наши собственные данные. Дата сборки - это то, что генератор вписал в
    -- сам файл; её нет - так и сказано, а не выдумана.
    out.ours.addonVersion = ns.VERSION
    out.ours.foreverSource = ns.ForeverSource and ns.ForeverSource.BUILT or nil
    out.ours.foreverSourceOrigin = ns.ForeverSource and ns.ForeverSource.ORIGIN or nil
    out.ours.statWeights = ns.StatWeights and ns.StatWeights.BUILT or nil
    local cov = ns.MarketHistory and ns.MarketHistory.Coverage
        and ns.MarketHistory:Coverage() or nil
    if cov then
        out.ours.priceHistoryDays = cov.deepestDays
        out.ours.priceHistoryItems = cov.items
        out.ours.priceHistoryShort = cov.short
    end
    -- СВОЯ КНИГА ЗАКУПОК. Здесь, а не только в разделе модулей: этот раздел
    -- отвечает на вопрос «чем аддон закрывает нехватку и насколько это старое»,
    -- а книга закупок - единственное, что он вообще знает ТОЧНО про деньги.
    -- Заодно рядом видно, стоит ли ещё чужая книга запасным путём.
    if ns.Config and ns.Config.LedgerMeta then
        local lm = ns.Config:LedgerMeta()
        out.ours.ledgerEntries = tonumber(lm.entries) or 0
        out.ours.ledgerSkipped = tonumber(lm.skipped) or 0
        out.ours.ledgerLastT = lm.lastT
        out.ours.ledgerFirstT = lm.firstT
    end

    local getMeta = (_G.C_AddOns and _G.C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
    local isLoaded = (_G.C_AddOns and _G.C_AddOns.IsAddOnLoaded) or _G.IsAddOnLoaded
    for _, name in ipairs(Diag.DATA_ADDONS) do
        local entry = { name = name }
        if type(getMeta) == "function" then
            local ok, version = pcall(getMeta, name, "Version")
            if ok and version then entry.version = version end
        end
        if type(isLoaded) == "function" then
            local ok, loaded = pcall(isLoaded, name)
            if ok then entry.loaded = loaded and true or false end
        end
        out.external[#out.external + 1] = entry
    end

    -- Сколько строк каждая база реально отдала - это важнее версии: база может
    -- быть установлена, объявлена свежей и не загружена.
    local Api = ns.Api
    if Api then
        out.rows = {
            itemDB = Api.ItemDBCount and Api:ItemDBCount() or nil,
            itemDBReady = Api.ItemDBReady and Api:ItemDBReady() or false,
            codex = Api.CodexReady and Api:CodexReady() or false,
            questieNpcs = Api.QuestieNpcCount and Api:QuestieNpcCount() or nil,
            mastercraft = (Api.MastercraftDB and Api:MastercraftDB()) ~= nil,
            auctionator = Api.AuctionatorPresent and Api:AuctionatorPresent() or false,
            syndicator = Api.SyndicatorPresent and Api:SyndicatorPresent() or false,
        }
    end

    s.dataVersions = out
    return out
end

-- Environment ------------------------------------------------------------

Diag.WATCHED_ADDONS = {
    "Auctionator", "Syndicator", "Baganator", "Scrap", "Mastercraft",
    "TomTom", "Polestar", "Polestar_Nav", "Questie", "Plumber",
    "Leatrix_Plus", "Platynator", "ForeverDungeonJournal", "WhatsTraining",
}

function Diag:CaptureEnvironment()
    local s = self:Init()
    local env = s.env
    local Api = ns.Api

    env.addonVersion = ns.VERSION
    env.schema = Diag.SCHEMA
    env.loginAt = now()
    env.loginAtText = stamp()

    -- Client build.
    local gbi = _G and _G.GetBuildInfo
    if type(gbi) == "function" then
        local ok, version, build, date, tocVersion = pcall(gbi)
        if ok then
            env.clientVersion = version
            env.clientBuild = build
            env.clientDate = date
            env.tocVersion = tocVersion
        end
    end
    env.interface = env.tocVersion
    env.locale = Api and Api:Locale() or nil
    env.isForever = Api and Api:IsForever() or false
    env.projectCamelot = _G and _G.WOW_PROJECT_CAMELOT or nil
    env.projectID = _G and _G.WOW_PROJECT_ID or nil

    -- Character.
    if Api then
        local p = Api:PlayerInfo()
        env.character = {
            name = p.name, realm = p.realm, level = p.level,
            classFile = p.classFile, className = p.className,
            race = p.raceName, faction = p.factionFile, guid = p.guid,
        }
        local spec = Api:SpecInfo()
        env.character.spec = spec and spec.name or nil
        env.character.specConf = spec and spec.conf or nil
        env.money = select(1, Api:Money())
    end

    -- External addons: name, version, and whether it is actually loaded as
    -- opposed to merely installed.
    env.addons = {}
    local getMeta = (_G.C_AddOns and _G.C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
    local isLoaded = (_G.C_AddOns and _G.C_AddOns.IsAddOnLoaded) or _G.IsAddOnLoaded
    local getEnabled = (_G.C_AddOns and _G.C_AddOns.GetAddOnEnableState) or _G.GetAddOnEnableState
    for _, name in ipairs(Diag.WATCHED_ADDONS) do
        local entry = { name = name }
        if type(getMeta) == "function" then
            local ok, version = pcall(getMeta, name, "Version")
            if ok and version then entry.version = version end
            local ok2, title = pcall(getMeta, name, "Title")
            if ok2 and title then entry.title = title end
        end
        if type(isLoaded) == "function" then
            local ok, loaded = pcall(isLoaded, name)
            if ok then entry.loaded = loaded and true or false end
        end
        if entry.version or entry.loaded then
            env.addons[#env.addons + 1] = entry
        end
    end

    -- Which of them we can actually reach through their APIs, which is a
    -- different question from "is it loaded".
    env.reachable = {
        auctionator = Api and Api:AuctionatorPresent() or false,
        syndicator = Api and Api:SyndicatorPresent() or false,
        mastercraftDB = (Api and Api:MastercraftDB()) ~= nil,
        tomtom = Api and Api:TomTomPresent() or false,
    }
    return env
end

-- Chat summary -----------------------------------------------------------

-- Deliberately short: enough for the player to see whether to send the file.
-- ЭТО ЧИТАЕТ ИГРОК, В ЧАТЕ. Сюда его посылает само окно («самопроверка нашла
-- странности — наберите /fp diag»), и раньше в ответ он получал имена функций
-- игры («нет на этом клиенте: itemStats, tooltipByID»), имена внутренних
-- модулей и имя переменной в файле. Ничего из этого ему не нужно и ничего не
-- говорит. Здесь - счёт словами и сами находки; имена лежат в файле, и где
-- лежит файл, сказано последней строкой.
function Diag:Summary()
    local s = self:Init()
    local U = ns.Util
    local lines = {}

    local errors = #s.errors
    local suspects = #s.suspicious

    local verdict
    if errors > 0 then
        verdict = "|cffff6060есть ошибки|r"
    elseif suspects > 0 then
        verdict = "|cffffcc40работает, но есть странности|r"
    else
        verdict = "|cff60c060всё в порядке|r"
    end
    lines[#lines + 1] = "диагностика: " .. verdict

    lines[#lines + 1] = string.format("ошибок: %d, странностей: %d", errors, suspects)

    local p = s.perf
    if p.recomputes > 0 then
        lines[#lines + 1] = string.format(
            "пересчётов: %d, в среднем %.1f мс, самый долгий %.1f мс",
            p.recomputes, p.avgMs or 0, p.peakMs or 0)
    else
        lines[#lines + 1] = "пересчётов ещё не было"
    end

    -- ЧЕГО ИГРА НЕ ДАЁТ - ПО ТЕМ ЖЕ ШЕСТИ ТЕМАМ, ЧТО В НАСТРОЙКАХ. Сырой счёт
    -- («нет 11 функций из 128») здесь не годится: половина из них - запасные
    -- варианты одного и того же, и у исправно работающего аддона он не ноль
    -- никогда. Тема («Банк», «Предметы») - то, что игрок может понять и
    -- проверить глазами.
    --
    -- Строк «модули с нулевым результатом» и «карточек записано» здесь больше
    -- нет: первая у здорового аддона всегда непустая (нет чар - нет советов про
    -- чары) и читалась как поломка, вторая спорила с числом советов на экране
    -- (в файл пишется только начало списка). Обе остались в файле.
    local lacking = {}
    if ns.Api and ns.Api.Report then
        for _, group in ipairs(ns.Api:Report()) do
            if group.state == "none" then
                lacking[#lacking + 1] = group.group .. " — нет совсем"
            elseif group.state ~= "ok" then
                lacking[#lacking + 1] = group.group .. " — частично"
            end
        end
    end
    if #lacking > 0 then
        lines[#lines + 1] = "эта версия игры сообщает мне не всё: "
            .. table.concat(lacking, "; ")
            .. ". Такие сведения я помечаю как неизвестные"
    else
        lines[#lines + 1] = "всё, что мне нужно от игры, она сообщает"
    end

    -- The first few suspicions in full, because they are the actionable bit.
    for i = 1, math.min(3, suspects) do
        local e = s.suspicious[i]
        lines[#lines + 1] = "  • " .. e.text
            .. ((e.count > 1) and (" (" .. (U.times(e.count) or "несколько раз") .. ")") or "")
    end
    if suspects > 3 then
        lines[#lines + 1] = "  • …и ещё " .. (suspects - 3) .. " — они записаны в файле"
    end
    for i = 1, math.min(2, errors) do
        local e = s.errors[i]
        lines[#lines + 1] = "  ! " .. e.where .. ": " .. U.truncate(tostring(e.message), 120)
    end

    lines[#lines + 1] = "полная запись — в файле ForeverPilot.lua в папке"
        .. " WTF\\Account\\<аккаунт>\\SavedVariables (файл обновляется при выходе"
        .. " из игры или по команде /reload)"
    return lines
end

function Diag:Print()
    for _, line in ipairs(self:Summary()) do
        ns.Api:Print(line)
    end
end

-- The longer version, for when the short summary says something is wrong and
-- the player wants to read it without leaving the game.
function Diag:PrintFull()
    local s = self:Init()
    local P = function(t) ns.Api:Print(t) end

    P("--- модули ---")
    local names = {}
    for name in pairs(s.modules) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        local m = s.modules[name]
        local line = string.format("%s: вход %s -> выход %s",
            name, tostring(m["in"]), tostring(m.out))
        if (m.out or 0) == 0 and m.reason then line = line .. " | " .. m.reason end
        P(line)
    end

    P("--- вызовы, не вернувшие данных ---")
    local quiet = {}
    for name, e in pairs(s.calls) do
        if e.gotData == 0 then quiet[#quiet + 1] = name end
    end
    table.sort(quiet)
    if #quiet == 0 then
        P("нет — все вызванные функции что-то вернули")
    else
        for _, name in ipairs(quiet) do
            local e = s.calls[name]
            P(string.format("%s: попыток %d%s", name, e.tries,
                e.note and (" | " .. e.note) or ""))
        end
    end

    P("--- странности (" .. #s.suspicious .. ") ---")
    for _, e in ipairs(s.suspicious) do
        P("• " .. e.text .. (e.count > 1 and (" x" .. e.count) or ""))
    end

    P("--- ошибки (" .. #s.errors .. ") ---")
    for _, e in ipairs(s.errors) do
        P("! " .. e.where .. " x" .. e.count)
        P("  " .. tostring(e.message):sub(1, 200))
    end

    P("--- верхние советы ---")
    for _, c in ipairs(s.cards) do
        P(string.format("%d. [%s] %s | %s | %s",
            c.rank, c.kindLabel or "?", c.title or "?",
            c.benefit or "?", c.confLabel or "?"))
    end
end

-- Deduplication ----------------------------------------------------------
--
-- How many cards collapsed into one, and why. The duplicate "Льняные сапоги"
-- rows should have shown up here on their own instead of waiting for the player
-- to count them on screen.
function Diag:Dedupe(data)
    if not self.enabled then return end
    local s = self:Init()
    s.dedupe = data or {}
    local total = tonumber(s.dedupe.collapsed) or 0
    if total > 0 then
        Diag:Suspect("cards-duplicated", string.format(
            "карточек схлопнулось дедупликацией: %d (по ключу %d, по действию %d)"
            .. " — ветка выдала одно и то же дважды",
            total, tonumber(s.dedupe.byKey) or 0, tonumber(s.dedupe.byAction) or 0),
            s.dedupe)
    end
end

-- The plain-Russian report ------------------------------------------------
--
-- A dozen lines a non-technical player can read without unpacking a single
-- table, written into its own field on every build. Everything in it is a number
-- some other part of the build already produced; nothing is computed here that
-- is not already on the session.
function Diag:WriteSummary()
    if not self.enabled then return nil end
    local s = self:Init()
    local lines = {}
    -- УРЕЗАНИЕ НЕ МОЛЧИТ. Строка, которая не влезла, раньше просто исчезала -
    -- и вместе с ней исчезали находки самопроверки, стоявшие в конце. Теперь
    -- непоместившиеся считаются, и в последней строке сказано, сколько их.
    local dropped = 0
    local function add(fmt, ...)
        if #lines >= Diag.CAP.summaryLines - 1 then
            dropped = dropped + 1
            return
        end
        if select("#", ...) > 0 then
            lines[#lines + 1] = string.format(fmt, ...)
        else
            lines[#lines + 1] = fmt
        end
    end
    local function finishSummary()
        if dropped > 0 then
            lines[#lines + 1] = "… и ещё " .. dropped .. " "
                .. ns.Util.plural(dropped, "строка", "строки", "строк")
                .. " не влезла в сводку: полные данные в FOREVERPILOT_DIAG."
        end
    end

    local eng = s.modules.actionEngine or {}
    local cards = tonumber(eng.out) or 0

    if #s.errors > 0 then
        add("Итог: есть ошибки (%d). Это точно надо показать разработчику.", #s.errors)
    elseif #s.suspicious > 0 then
        add("Итог: работает, но самопроверка нашла странности (%d).", #s.suspicious)
    else
        add("Итог: всё в порядке, странностей не найдено.")
    end
    add("Советов на экране: %d.", cards)

    -- КАКИЕ ВЕТКИ МОЛЧАТ - СЧИТАЕТСЯ ПО ЭКРАНУ, А НЕ ПО ПОСТРОЕННОМУ.
    --
    -- Живая жалоба: сводка писала «Благосклонность торговца молчит», а на
    -- экране было три её карточки. Считалось построенное веткой, а игрок видит
    -- оставшееся после профиля и фильтра - два разных числа. Теперь
    -- branchCounts - это «сколько видно», и расхождения со списком быть не
    -- может по построению.
    --
    -- А если ветка что-то построила, но до экрана это не дошло - так и
    -- сказано, вместе с числом: «построила 4, на экране ноль» отвечает на
    -- вопрос «куда делось», а «молчит» на него не отвечает.
    local quiet = {}
    for _, key in ipairs(ns.ActionEngine and ns.ActionEngine.BRANCH_ORDER or {}) do
        local n = (eng.branchCounts or {})[key]
        if (tonumber(n) or 0) == 0 then
            local label = (ns.ActionEngine.BRANCH_LABEL or {})[key] or key
            local note = (eng.branchNotes or {})[key]
            local built = tonumber((eng.branchBuilt or {})[key]) or 0
            local bits = {}
            if built > 0 then
                bits[#bits + 1] = "построила " .. built .. ", на экране ноль"
            end
            if note then bits[#bits + 1] = tostring(note) end
            quiet[#quiet + 1] = label
                .. ((#bits > 0) and (" (" .. table.concat(bits, "; ") .. ")") or "")
        end
    end
    if #quiet == 0 then
        add("Молчащих веток нет: каждая что-то предложила.")
    else
        add("Молчат %d из %d веток:", #quiet,
            #(ns.ActionEngine and ns.ActionEngine.BRANCH_ORDER or {}))
        for i = 1, math.min(4, #quiet) do add("  — %s", quiet[i]) end
        if #quiet > 4 then add("  — …и ещё %d, подробнее в modules", #quiet - 4) end
    end

    -- Where candidates were lost. One line per branch with the biggest filter.
    for name, f in pairs(s.funnels) do
        local biggest, biggestN = nil, 0
        for filter, e in pairs(f.drops or {}) do
            if e.n > biggestN then biggest, biggestN = filter, e.n end
        end
        if biggest then
            add("Ветка %s: вошло %d, вышло %d, больше всего отсеял фильтр «%s» (%d).",
                tostring(name), f["in"] or 0, f.out or 0, tostring(biggest), biggestN)
        end
    end

    local dd = s.dedupe or {}
    if (tonumber(dd.collapsed) or 0) > 0 then
        add("Повторов убрано: %d (одна и та же советом дважды).", dd.collapsed)
    end

    local prices = s.modules.prices or {}
    if (tonumber(prices.unknown) or 0) > 0 then
        add("Цен не нашлось по %d запросам из %d — деньги в этих советах"
            .. " посчитаны не полностью.", prices.unknown, prices["in"] or 0)
    end

    -- ЧЕГО АДДОН НЕ ЗНАЕТ, ОДНОЙ СТРОКОЙ. Без неё нехватка данных выглядела
    -- как молчание: игрок читал пустое место и думал, что советов нет, а не
    -- что по этим предметам просто нет строки в базе.
    local wantLine = Diag:WantedLine()
    if wantLine then add("%s", wantLine) end

    local hidden = tonumber(eng.hiddenByDismissal) or 0
    if hidden > 0 then
        add("Вы скрыли %d советов. Вернуть все — /fp show.", hidden)
    end

    local p = s.perf
    if (p.recomputes or 0) > 0 then
        add("Пересчётов: %d, средний %.1f мс, пик %.1f мс.",
            p.recomputes, p.avgMs or 0, p.peakMs or 0)
        -- ЧТО ИМЕННО БЫЛО ПИКОМ. Пик в полтора-четыре раза выше среднего - это
        -- не подорожание пересчёта, а один редкий тяжёлый случай, и назвать его
        -- надо прямо: иначе число читается как тревога. Подпись пика ставит
        -- Diag:TimerStop, и у первого пересчёта после входа она своя.
        if p.peakLabel and (p.peakMs or 0) > (p.avgMs or 0) * 1.5 then
            add("Пик - это «%s», а не обычный пересчёт: у него пусты все"
                .. " памяти, и за сессию он один.", tostring(p.peakLabel))
        end
        -- САМАЯ ДОРОГАЯ ВЕТКА - ЧИСЛОМ, А НЕ ДОГАДКОЙ. Без этой строки вопрос
        -- «почему пересчёт стал втрое дороже» решался чтением всего файла, а
        -- ответ был в одной ветке: перепродажа стоила 74.9 мс из 79.4.
        local worst, worstMs = nil, 0
        for key, ms in pairs(eng.branchMs or {}) do
            local n = tonumber(ms) or 0
            if n > worstMs then worst, worstMs = key, n end
        end
        if worst then
            add("Дороже всех ветка «%s»: %.1f мс на последнем пересчёте.",
                (ns.ActionEngine and ns.ActionEngine.BRANCH_LABEL
                 and ns.ActionEngine.BRANCH_LABEL[worst]) or worst, worstMs)
        end
        -- И СКОЛЬКО РАЗ ЗА ПЕРЕСЧЁТ МЫ ДЁРГАЕМ ЧУЖИЕ ДАННЫЕ. Это та величина,
        -- которая переносится из теста в игру один в один, в отличие от
        -- миллисекунд: обращение к Codex - двоичный поиск по блобу, обращение к
        -- кешу лотов - перебор записей предмета.
        local cc = eng.clientCalls
        if type(cc) == "table" and next(cc) ~= nil then
            -- НОЛЬ - ЭТО ОТВЕТ, а не повод промолчать: после прогрева памяти
            -- обращений к Codex должно быть ровно ноль, и строка «Codex 0 (из
            -- памяти 408)» - это доказательство, что память работает. Строка,
            -- которая исчезает при нуле, такого доказательства не даёт.
            local bits = {}
            local function callBit(label, reads, hits)
                bits[#bits + 1] = string.format("%s %d (из памяти %d)",
                    label, tonumber(reads) or 0, tonumber(hits) or 0)
            end
            callBit("Codex", cc.codexReads, cc.codexCacheHits)
            callBit("лоты чужого кеша", cc.observedPriceReads, cc.observedPriceCacheHits)
            callBit("данные предметов", cc.itemInfoReads, cc.itemInfoCacheHits)
            add("Обращений за пересчёт: %s.", table.concat(bits, ", "))
        end
    end

    if s.delta and s.delta.compared then
        add("Против прошлого запуска: %s.", s.delta.text or "без изменений")
    end

    for i = 1, math.min(2, #s.suspicious) do
        add("Странность: %s", tostring(s.suspicious[i].text))
    end
    for i = 1, math.min(2, #s.errors) do
        add("Ошибка в %s: %s", tostring(s.errors[i].where),
            tostring(s.errors[i].message):sub(1, 90))
    end

    finishSummary()
    s.summary = lines
    return lines
end

-- Delta against the previous session --------------------------------------
--
-- Three sessions are kept, so the one before ours is right there. A regression
-- that halves the card count or silences a branch should be visible without
-- anyone remembering what yesterday looked like.
function Diag:ComputeDelta()
    if not self.enabled then return nil end
    local s = self:Init()
    local prev = Diag.prevSession
    if type(prev) ~= "table" then
        s.delta = { compared = false, reason = "прошлой сессии в файле нет" }
        return s.delta
    end

    local function engOf(sess) return (sess.modules or {}).actionEngine or {} end
    local a, b = engOf(prev), engOf(s)
    local d = {
        compared = true,
        prevStartedAt = prev.startedAtText,
        cardsBefore = tonumber(a.out) or 0,
        cardsNow = tonumber(b.out) or 0,
        errorsBefore = #(prev.errors or {}),
        errorsNow = #(s.errors or {}),
        suspiciousBefore = #(prev.suspicious or {}),
        suspiciousNow = #(s.suspicious or {}),
        peakMsBefore = (prev.perf or {}).peakMs or 0,
        peakMsNow = (s.perf or {}).peakMs or 0,
        branchesWentQuiet = {},
        branchesWokeUp = {},
    }
    for key, before in pairs(a.branchCounts or {}) do
        local nowN = (b.branchCounts or {})[key]
        if (tonumber(before) or 0) > 0 and (tonumber(nowN) or 0) == 0 then
            d.branchesWentQuiet[#d.branchesWentQuiet + 1] = key
        end
    end
    for key, nowN in pairs(b.branchCounts or {}) do
        local before = (a.branchCounts or {})[key]
        if (tonumber(nowN) or 0) > 0 and (tonumber(before) or 0) == 0 then
            d.branchesWokeUp[#d.branchesWokeUp + 1] = key
        end
    end
    table.sort(d.branchesWentQuiet)
    table.sort(d.branchesWokeUp)

    local bits = {}
    local dc = d.cardsNow - d.cardsBefore
    if dc ~= 0 then
        bits[#bits + 1] = string.format("советов %s%d (%d -> %d)",
            dc > 0 and "+" or "", dc, d.cardsBefore, d.cardsNow)
    end
    if d.errorsNow ~= d.errorsBefore then
        bits[#bits + 1] = string.format("ошибок %d -> %d", d.errorsBefore, d.errorsNow)
    end
    if #d.branchesWentQuiet > 0 then
        bits[#bits + 1] = "замолчали ветки: " .. table.concat(d.branchesWentQuiet, ", ")
    end
    if #d.branchesWokeUp > 0 then
        bits[#bits + 1] = "заговорили ветки: " .. table.concat(d.branchesWokeUp, ", ")
    end
    if d.peakMsBefore > 0 and d.peakMsNow > d.peakMsBefore * 2 then
        bits[#bits + 1] = string.format("пик пересчёта вырос %.1f -> %.1f мс",
            d.peakMsBefore, d.peakMsNow)
    end
    d.text = (#bits > 0) and table.concat(bits, "; ") or "без изменений"
    s.delta = d

    if #d.branchesWentQuiet > 0 then
        Diag:Suspect("branch-went-quiet",
            "по сравнению с прошлым запуском замолчали ветки: "
            .. table.concat(d.branchesWentQuiet, ", "), d)
    end
    return d
end

-- Writing to disk --------------------------------------------------------
--
-- HONEST ANSWER, because it was asked directly: an addon cannot force
-- SavedVariables to disk. The client writes them at logout and on /reload, and
-- there is no API - public or otherwise - to ask for it sooner.
--
-- What IS true, and is what this does instead: the session table lives inside
-- FOREVERPILOT_DIAG from ADDON_LOADED onward, so every number recorded here is
-- already in the table the client will write. Nothing is buffered and nothing
-- is lost on a normal exit or a /reload. Only a hard crash loses the tail, and
-- a crash would lose a buffered write too.
--
-- So the one thing worth doing is making a lost tail recognisable: each build
-- stamps the clock and marks the session incomplete, and Finish marks it
-- complete. A session that ends without that mark was cut short, and the file
-- says so instead of looking like a clean run that found nothing.
function Diag:Heartbeat(label)
    if not self.enabled then return end
    local s = self:Init()
    s.lastWriteAt = now()
    s.lastWriteAtText = stamp(s.lastWriteAt)
    s.lastWriteLabel = label
    s.complete = false
    s.writes = (s.writes or 0) + 1
end

-- Size control -----------------------------------------------------------

-- Rough byte estimate, used only to record how big the file is getting. No
-- serialisation, just a walk with a cheap per-node cost.
function Diag:EstimateSize(t, depth)
    depth = depth or 0
    if depth > 8 or type(t) ~= "table" then return 16 end
    local total = 24
    for k, v in pairs(t) do
        total = total + 12 + #tostring(k)
        if type(v) == "table" then
            total = total + Diag:EstimateSize(v, depth + 1)
        else
            total = total + #tostring(v)
        end
    end
    return total
end

function Diag:Trim()
    local s = self.session
    if not s then return end
    cap(s.errors, Diag.CAP.errors)
    cap(s.suspicious, Diag.CAP.suspicious)
    cap(s.cards, Diag.CAP.cards)
    cap(s.perf.samples, Diag.CAP.perf)
    cap(s.log, Diag.CAP.log)
    -- The price journal is keyed, not a list, so it cannot be trimmed from the
    -- front. It is bounded on the way in instead (Diag.CAP.priceDecisions) and
    -- rebuilt each session; this only records that it filled up.
    if (s.pricesOverflow or 0) > 0 then
        s.pricesNote = "журнал цен заполнен: записаны первые "
            .. Diag.CAP.priceDecisions .. ", ещё " .. s.pricesOverflow .. " не влезли"
    end
    -- Итоги заказа данных пересчитываются на каждом Trim, то есть попадают в
    -- файл вместе с остальным: читающему не нужно складывать самому.
    s.wantedTotals = Diag:WantedTotals()
    s.wantedLine = Diag:WantedLine()
    s.sizeEstimate = Diag:EstimateSize(s)
end

function Diag:Finish()
    local s = self.session
    if not s then return end
    s.endedAt = now()
    s.endedAtText = stamp()
    s.durationSeconds = s.endedAt - (s.startedAt or s.endedAt)
    -- The mark that says "this session was written out in full". Its absence on
    -- a session that has a startedAt means the client went away mid-play, and
    -- the tail of the file is whatever had been recorded by then.
    s.complete = true
    Diag:Trim()
end

return Diag
