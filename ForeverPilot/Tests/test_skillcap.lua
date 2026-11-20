-- ForeverPilot / Tests/test_skillcap.lua
--
-- THE SKILL CEILING COMES FROM THE CLIENT, AND FROM NOWHERE ELSE.
--
-- This suite was born from a misreading, and its header said so for two days in
-- the opposite sense: "THE SKILL CEILING IS DYNAMIC", proven by the player's
-- MastercraftDB history -
--
--   Tailoring   84 -> 93 -> 160 -> 224 -> 225
--   Enchanting  80 -> 106 -> 120 -> 225
--
-- - "those are MAXIMA, not current values". They are not. Mastercraft writes
-- history[guid][day].s[profession] = { the SKILL first seen that day, the SKILL
-- last seen that day } (its Data.lua, RecordHistory). 84 -> 93 is the player
-- gaining nine points. The proof is in the numbers themselves and is a test
-- below: each day's second number is the next day's first.
--
-- What survives is the rule the suite enforces, and it was right all along: the
-- only source of truth is the pair (current, max) the client hands us, no rank
-- table is hardcoded, and the only honest answer when max is missing is "I do
-- not know". What does NOT survive is every claim about the HISTORY of the
-- maximum - the addon has none, and must not show one to the player.
--
-- Every assertion below is written against that pair and nothing else.
local H = ...

return function()

local CAP_EVIDENCE = {
    -- date, profession, first, last - the SKILL as first and last seen that
    -- day, copied verbatim from the player's MastercraftDB.history for
    -- Player-6946-00CCA8FC. (Was labelled "current, max". It never was.)
    { "2026-11-07", "Tailoring",   82,  84  },
    { "2026-11-08", "Tailoring",   84,  93  },
    { "2026-11-09", "Tailoring",   93,  93  },
    { "2026-11-13", "Tailoring",   93,  160 },
    { "2026-11-14", "Tailoring",   160, 224 },
    { "2026-11-15", "Tailoring",   224, 225 },
    { "2026-11-16", "Tailoring",   225, 225 },
}

-- 1. No hardcoded ladder anywhere ---------------------------------------

H.suite("Потолок навыка: таблицы рангов в коде больше нет")
do
    local env = H.load()
    local ns = env.ns

    -- ForeverSource is data-only and not in LOGIC_FILES, so load it here.
    local chunk = loadfile(H.ROOT .. "/Data/ForeverSource.lua")
    H.ok(chunk ~= nil, "Data/ForeverSource.lua читается")
    if chunk then
        setfenv(chunk, env.sandbox)
        chunk("ForeverPilot", ns)
        local FS = ns.ForeverSource
        H.ok(FS ~= nil, "ForeverSource загрузился")
        H.eq(FS.PROF_RANKS, nil, "FS.PROF_RANKS удалён (лестница рангов)")
        H.eq(FS.PROF_RANKS_NOTE, nil, "FS.PROF_RANKS_NOTE удалён")
        H.eq(FS.NEXT_RANK, nil, "FS.NEXT_RANK удалён (требования уровня 35)")
        H.eq(FS.ABOVE_300, nil, "FS.ABOVE_300 удалён (кап 300 не документирован - значит не факт)")
        H.eq(FS.CONFIDENCE and FS.CONFIDENCE.PROF_RANKS, nil,
            "и из карты достоверности PROF_RANKS тоже убран")
        -- What replaces it: a record of what is known, with no thresholds in it.
        -- Запись раньше утверждала `dynamic = true` - вывод из неверно
        -- прочитанной истории (там навык, а не максимум). Он отозван, и
        -- отозван явно: молча убранное поле никто бы не заметил.
        H.ok(type(FS.SKILL_CAP) == "table", "вместо таблицы - запись FS.SKILL_CAP")
        H.eq(FS.SKILL_CAP and FS.SKILL_CAP.dynamic, nil,
            "«потолок динамический» больше не утверждается")
        H.ok(type(FS.SKILL_CAP and FS.SKILL_CAP.retracted) == "string",
            "и сказано, когда вывод отозван: " .. tostring(FS.SKILL_CAP and FS.SKILL_CAP.retracted))
        H.eq(FS.SKILL_CAP and FS.SKILL_CAP.observed, nil,
            "«наблюдённых максимумов» из чужой истории навыка в записи нет")
        H.eq(FS.SKILL_CAP and FS.SKILL_CAP.thresholds, nil,
            "и никаких порогов в ней не лежит")
    end
end

H.suite("Потолок навыка: числа 225 и 300 не зашиты в логику")
do
    -- A grep-style guard. Recipe skill requirements (`s = 225`) are real data
    -- and live in Data/; what must not come back is a cap or a level gate in
    -- the decision code.
    -- Every file in Logic/, found rather than listed, plus the two outside it
    -- that reason about skill. A hand-written list let a new decision file slip
    -- in unchecked, which is the whole thing this guard exists to prevent.
    -- UI/TabCraft.lua is excluded on purpose: it has `if shown >= 300`, a limit
    -- on how many rows to draw. Same number, nothing to do with skill.
    local files = {}
    do
        -- СПИСОК ФАЙЛОВ БЕРЁТСЯ ИЗ .toc, А НЕ У ОБОЛОЧКИ.
        --
        -- Раньше он добывался через io.popen('ls Logic'), с заученным перечнем
        -- из двенадцати имён на случай «оболочки нет». Оба пути оказались
        -- плохими, и выяснилось это, когда набор запустили под настоящим PUC
        -- Lua 5.1 (Tests/run_puc51.py):
        --
        --   * io.popen там ЕСТЬ, но при вызове говорит «'popen' not supported»
        --     (стандартная заглушка Lua, собранного без поддержки процессов) -
        --     и весь набор test_skillcap падал на этой строке целиком;
        --   * а заученный перечень молча проверял 12 файлов вместо тридцати,
        --     то есть делал ровно то, против чего эта проверка и заведена.
        --
        -- .toc есть всегда, он и так ведётся руками под присмотром test_load, и
        -- читать его умеет любой интерпретатор без оболочки.
        local toc = io.open(H.ROOT .. "/ForeverPilot.toc", "r")
        H.ok(toc ~= nil, "список файлов берётся из .toc")
        if toc then
            for line in toc:lines() do
                local rel = line:gsub("\r", ""):gsub("\\", "/")
                    :gsub("^%s+", ""):gsub("%s+$", "")
                if rel:match("^Logic/.+%.lua$") then files[#files + 1] = rel end
            end
            toc:close()
        end
        table.sort(files)
        files[#files + 1] = "Core/Api.lua"
        files[#files + 1] = "UI/TabCharacter.lua"
    end
    H.ok(#files >= 25, #files .. " файлов логики под проверкой")
    for _, rel in ipairs(files) do
        local f = io.open(H.ROOT .. "/" .. rel, "r")
        H.ok(f ~= nil, rel .. " открыт")
        if f then
            local src = f:read("*a")
            f:close()
            -- Strip comments: prose may legitimately mention the old numbers
            -- while explaining why they are gone.
            local code = src:gsub("%-%-[^\n]*", "")
            H.eq(code:find("PROF_RANKS", 1, true), nil, rel .. ": нет ссылок на PROF_RANKS")
            H.eq(code:find("NEXT_RANK", 1, true), nil, rel .. ": нет ссылок на NEXT_RANK")
            H.ok(not code:find("[^%w_.]225[^%w_]"), rel .. ": числа 225 в коде нет")
            H.ok(not code:find("[^%w_.]300[^%w_]"), rel .. ": числа 300 в коде нет")
        end
    end
end

-- 2. Reading current/max through feature detection -----------------------

-- These suites test the ADAPTER's route table, so they put the production
-- Api:Professions back in place of the harness fake.
local function adapterEnv(opts)
    local env = H.load(opts)
    env.ns.Api.Professions = env.real.Professions
    return env
end

H.suite("Чтение навыка: C_SkillInfo.GetSkillLineInfoByID - первый приоритет")
do
    local env = adapterEnv()
    local ns, G = env.ns, env.G

    -- The real Forever shape, from the client's own documentation: rank /
    -- maxRank / minLevel, inside a SkillLineAttributes table.
    G.C_SkillInfo = {
        GetNumSkillLines = function() return 2 end,
        GetSkillLineInfo = function(i)
            local rows = {
                { skillID = 197, name = "Портняжное дело", isHeader = false },
                { skillID = 333, name = "Наложение чар",  isHeader = false },
            }
            return rows[i]
        end,
        GetSkillLineInfoByID = function(id)
            local byID = {
                [197] = { skillID = 197, name = "Портняжное дело", isHeader = false,
                          rank = 224, maxRank = 225, minLevel = 0 },
                [333] = { skillID = 333, name = "Наложение чар", isHeader = false,
                          rank = 225, maxRank = 225, minLevel = 0 },
            }
            return byID[id]
        end,
    }
    -- A deliberately hostile neighbour: the broken route must not win.
    G.C_TradeSkillUI = G.C_TradeSkillUI or {}
    G.C_TradeSkillUI.GetAllProfessionTradeSkillLines = function() return { 197, 333 } end
    G.C_TradeSkillUI.GetProfessionInfoBySkillLineID = function(line)
        return { professionName = "Портняжное дело", skillLevel = 0, maxSkillLevel = 0 }
    end
    G.GetNumSkillLines = nil   -- nil on Forever, exactly as in game

    ns.Api:Detect()
    H.eq(ns.Api.has.skillByID, true, "C_SkillInfo.GetSkillLineInfoByID обнаружен")
    H.eq(ns.Api.has.numSkillLines, false, "глобальный GetNumSkillLines отсутствует (как в Forever)")

    local profs, conf, route = ns.Api:Professions()
    H.eq(route, "C_SkillInfo.GetSkillLineInfoByID", "сработал приоритетный маршрут")
    H.eq(conf, ns.CONF.EXACT, "и его числа считаем точными")
    H.eq(#profs, 2, "обе профессии прочитаны")
    local byName = {}
    for _, p in ipairs(profs) do byName[p.name] = p end
    local t = byName["Портняжное дело"]
    H.ok(t ~= nil, "портняжка найдена")
    if t then
        H.eq(t.skill, 224, "current взят из rank")
        H.eq(t.max, 225, "max взят из maxRank")
        H.eq(t.maxKnown, true, "и помечен как известный")
        H.eq(t.skillTrusted, true, "числам этого маршрута верим")
    end
end

H.suite("Чтение навыка: GetNumSkillLines на Forever не используется")
do
    local env = adapterEnv()
    local ns, G = env.ns, env.G
    -- A global GetNumSkillLines that would lie if anybody called it.
    local called = false
    G.GetNumSkillLines = function() called = true; return 3 end
    G.GetSkillLineInfo = function() called = true; return "Ложь", false, 0, 999, 0, 0, 999 end
    G.GetProfessions = function() return 1 end
    G.GetProfessionInfo = function() return "Портняжное дело", 1, 150, 160, 0, 0, 197 end
    ns.Api:Detect()
    local profs, _, route = ns.Api:Professions()
    H.eq(called, false, "классический список навыков не вызывался")
    H.eq(route, "GetProfessions", "вместо него сработал GetProfessions")
    H.eq(profs[1] and profs[1].max, 160, "и max пришёл настоящий (160, не 225)")
end

H.suite("Чтение навыка: нулям от GetProfessionInfoBySkillLineID не верим")
do
    local env = adapterEnv()
    local ns, G = env.ns, env.G
    G.C_TradeSkillUI = G.C_TradeSkillUI or {}
    G.C_TradeSkillUI.GetAllProfessionTradeSkillLines = function() return { 197 } end
    G.C_TradeSkillUI.GetProfessionInfoBySkillLineID = function()
        return { professionName = "Портняжное дело", skillLevel = 0, maxSkillLevel = 0 }
    end
    ns.Api:Detect()
    local profs, conf = ns.Api:Professions()
    H.eq(#profs, 1, "имя профессии взяли")
    if profs[1] then
        H.eq(profs[1].skill, nil, "а нулевой навык - нет")
        H.eq(profs[1].max, nil, "и нулевой максимум тоже нет")
        H.eq(profs[1].maxKnown, false, "максимум честно помечен неизвестным")
        H.eq(profs[1].skillTrusted, false, "числам этого маршрута не верим")
    end
    H.ok(conf ~= ns.CONF.EXACT, "и достоверность не «точно»")
end

-- ОТКУДА БЕРУТСЯ ДУБЛИ ЗАПИСЕЙ О ПРОФЕССИЯХ - НА НАСТОЯЩЕЙ ФОРМЕ ОТВЕТА.
--
-- Живой файл игрока: professions = 3, craftingProfessions = 3,
-- duplicateProfessionRecords = 3. Вопрос был «откуда дубли и не портят ли они
-- потолки навыка и реестр персонажей».
--
-- Ответ - здесь, и он про адаптер, а не про склейку: на этом клиенте ОДНА
-- профессия приходит ДВАЖДЫ, потому что номер её линии навыка нам называют два
-- разных источника и называют по-разному. C_TradeSkillUI.
-- GetAllProfessionTradeSkillLines отдаёт современные номера (2948, 2940),
-- C_SkillInfo.GetNumSkillLines (окно навыков) - классические (197, 333), а
-- C_SkillInfo.GetSkillLineInfoByID честно отвечает на каждый. Три профессии ->
-- шесть записей -> три дубля. Это НЕ ошибка клиента и не наша: это две
-- нумерации одного и того же.
--
-- Проверяется весь путь на производственном Api:Professions: сколько записей
-- пришло, во что они склеились, что стало с потолком и что попало в реестр
-- персонажей (Logic/Roster.lua) - то есть ровно то, за что спрашивали.
H.suite("Дубли профессий: две нумерации одной линии навыка, склейка и реестр")
do
    local env = adapterEnv()
    local ns, G = env.ns, env.G

    -- Персонаж - тот же, что в живом файле: алхимия, инженерное дело, кулинария.
    local RU = { [171] = "Алхимия", [202] = "Инженерное дело", [185] = "Кулинария" }
    local MODERN = { [2823] = 171, [2827] = 202, [2821] = 185 }  -- современный -> классический
    local SKILL = { [171] = 150, [202] = 150, [185] = 150 }

    G.C_TradeSkillUI = G.C_TradeSkillUI or {}
    -- Современные номера: так отвечает клиент игрока.
    G.C_TradeSkillUI.GetAllProfessionTradeSkillLines = function()
        return { 2823, 2827, 2821 }
    end
    G.C_SkillInfo = {
        -- Окно навыков: классические номера, и в нём же - языки и оружие,
        -- которые профессиями не являются.
        GetNumSkillLines = function() return 5 end,
        GetSkillLineInfo = function(i)
            local rows = {
                { skillID = 171, name = "Алхимия", isHeader = false },
                { skillID = 202, name = "Инженерное дело", isHeader = false },
                { skillID = 185, name = "Кулинария", isHeader = false },
                { skillID = 98,  name = "Язык орков", isHeader = false },
                { skillID = 95,  name = "Защита", isHeader = false },
            }
            return rows[i]
        end,
        GetSkillLineInfoByID = function(id)
            local classic = MODERN[id] or id
            local name = RU[classic]
            if name then
                return { skillID = id, name = name, isHeader = false,
                         rank = SKILL[classic], maxRank = 150, minLevel = 0 }
            end
            if id == 98 then
                return { skillID = 98, name = "Язык орков", isHeader = false,
                         rank = 300, maxRank = 300 }
            end
            if id == 95 then
                return { skillID = 95, name = "Защита", isHeader = false,
                         rank = 80, maxRank = 80 }
            end
            return nil
        end,
    }
    G.GetNumSkillLines = nil
    ns.Api:Detect()

    local profs, conf, route = ns.Api:Professions()
    H.eq(route, "C_SkillInfo.GetSkillLineInfoByID", "маршрут тот же, что в игре")
    H.eq(conf, ns.CONF.EXACT, "числа точные")
    -- Шесть записей на три профессии плюс язык и защита из окна навыков.
    H.eq(#profs, 8, "клиент отдал 8 записей: по две на профессию плюс язык и защита")

    env.professionRoute = route
    local snap = H.rescan(env)
    H.eq(#snap.professions, 3, "склеились в три профессии")
    H.eq(#ns.CharacterScanner:CraftingProfessions(), 3, "и все три крафтовые")

    local byName = {}
    for _, p in ipairs(snap.professions) do
        H.eq(byName[p.name], nil, "«" .. tostring(p.name) .. "» в снимке один раз")
        byName[p.name] = p
    end
    for _, name in ipairs({ "Алхимия", "Инженерное дело", "Кулинария" }) do
        local p = byName[name]
        H.ok(p ~= nil, name .. " в снимке есть")
        if p then
            -- ПОТОЛОК ОТ ДУБЛЯ НЕ ПОСТРАДАЛ: обе записи отдавали одно и то же,
            -- и склейка не имеет права ни занизить его, ни объявить неизвестным.
            H.eq(p.skill, 150, name .. ": навык 150")
            H.eq(p.max, 150, name .. ": потолок 150")
            H.eq(p.maxKnown, true, name .. ": потолок помечен известным")
            H.eq(p.duplicates, 1, name .. ": дубль записан, а не выброшен молча")
            -- И НОМЕР ЛИНИИ НЕ ПОТЕРЯН: наши данные размечены классическими
            -- номерами, и главным должен стать знакомый, а не современный.
            H.eq(type(p.skillLineIDs), "table", name .. ": номера линий сохранены оба")
            local seen = {}
            for _, id in ipairs(p.skillLineIDs or {}) do seen[id] = true end
            H.eq(ns.Util.count(p.skillLineIDs or {}), 2, name .. ": их ровно два")
            local classic = ({ ["Алхимия"] = 171, ["Инженерное дело"] = 202,
                               ["Кулинария"] = 185 })[name]
            H.ok(seen[classic], name .. ": классический номер на месте")
            H.eq(p.skillLineID, classic,
                name .. ": главным стал номер, который знают наши данные")
            H.eq(ns.ForeverSource:ResolveSkillLine(p), classic,
                name .. ": и справочник его находит")
        end
    end

    -- Язык и защита - не профессии, и в снимок они не попадают.
    H.eq(byName["Язык орков"], nil, "язык из окна навыков профессией не стал")
    H.eq(byName["Защита"], nil, "защита - тоже")

    -- Нуль от SanityCheckSkills: потолок не должен обнулиться после склейки.
    ns.Api:SanityCheckSkills(snap.professions, function() return 0 end)
    for _, name in ipairs({ "Алхимия", "Инженерное дело", "Кулинария" }) do
        H.eq(byName[name].max, 150, name .. ": потолок уцелел и после самопроверки")
    end

    -- РЕЕСТР ПЕРСОНАЖЕЙ. Запись делает сам сканер (Roster:Remember), и в ней
    -- тоже должно быть три профессии, а не шесть: на этом реестре стоят и
    -- потолки для сообщения «потолок поднялся», и ветка «эта профессия есть у
    -- другого персонажа».
    local entry = ns.Roster:Find(snap.fullName or snap.name)
    H.ok(entry ~= nil, "персонаж записан в реестр")
    if entry then
        H.eq(#entry.professions, 3, "в реестре три профессии, а не шесть")
        local seenR = {}
        for _, p in ipairs(entry.professions) do
            H.eq(seenR[p.name], nil, "«" .. tostring(p.name) .. "» в реестре один раз")
            seenR[p.name] = true
            H.eq(p.max, 150, tostring(p.name) .. ": потолок в реестре тот же")
        end
        H.eq(entry.professionsKnown, true, "и список считается полным")
    end

    -- Потолки, которыми пользуется сообщение «потолок поднялся»: по одной
    -- записи на профессию, с тем же числом.
    ns.Notifier:CheckSkillCap("тест: первая встреча")
    local caps = ns.Roster:SkillCaps(snap.fullName or snap.name)
    H.eq(ns.Util.count(caps), 3, "запомненных потолков три, а не шесть")
    for _, name in ipairs({ "Алхимия", "Инженерное дело", "Кулинария" }) do
        H.eq(caps[name], 150, name .. ": потолок запомнен один раз и верно")
    end

    -- И число дублей попадает в диагностику: по нему и был задан вопрос.
    H.build(env)
    local m = ns.Diag:Init().modules.characterScanner
    H.ok(m ~= nil, "сканер отчитался")
    if m then
        H.eq(m.professions, 3, "в диагностике три профессии")
        H.eq(m.duplicateProfessionRecords, 3,
            "и три дубля — по одному на профессию, как в живом файле")
    end
end

H.suite("Чтение навыка: запасной вариант - MastercraftDB")
do
    local env = adapterEnv()
    local ns, G = env.ns, env.G
    -- Nothing in the client answers. The player's cache still does. The cache
    -- is reached through the adapter's own Api:MastercraftDB seam, which the
    -- harness points at env.foreignDB.
    env.foreignDB = {
        chars = {
            ["Player-1-1"] = {
                professions = {
                    { name = "Tailoring",  skill = 225, max = 225 },
                    { name = "Fishing",    skill = 155, max = 225 },
                },
            },
        },
        history = {
            ["Player-1-1"] = {
                ["2026-11-15"] = { s = { Tailoring = { 224, 225 } } },
                ["2026-11-14"] = { s = { Tailoring = { 160, 224 } } },
            },
        },
    }
    ns.Api:Detect()
    local profs, conf, route = ns.Api:Professions()
    H.eq(route, "MastercraftDB.chars", "сработал запасной маршрут из кеша")
    H.eq(conf, ns.CONF.CACHED, "и это кеш, а не «точно»")
    local byName = {}
    for _, p in ipairs(profs) do byName[p.name] = p end
    H.eq(byName["Tailoring"] and byName["Tailoring"].max, 225, "max прочитан из кеша")
    H.eq(byName["Fishing"] and byName["Fishing"].skill, 155, "current прочитан из кеша")
    H.eq(byName["Fishing"] and byName["Fishing"].max, 225,
        "и для рыбалки max из chars (225), а не из history (155)")
end

H.suite("Чтение навыка: история НАВЫКА из MastercraftDB (потолка в ней нет)")
do
    local env = adapterEnv()
    local ns, G = env.ns, env.G
    env.foreignDB = {
        history = {
            ["Player-1-1"] = {
                ["2026-11-07"] = { s = { Tailoring = { 82, 84 } } },
                ["2026-11-08"] = { s = { Tailoring = { 84, 93 } } },
                ["2026-11-09"] = { s = { Tailoring = { 93, 93 } } },
                ["2026-11-13"] = { s = { Tailoring = { 93, 160 } } },
                ["2026-11-14"] = { s = { Tailoring = { 160, 224 } } },
                ["2026-11-15"] = { s = { Tailoring = { 224, 225 } } },
                ["2026-11-16"] = { s = { Tailoring = { 225, 225 } } },
            },
        },
    }
    ns.Api:Detect()
    local hist = ns.Api:MastercraftSkillHistory("Player-1-1", "Tailoring")
    H.ok(type(hist) == "table", "история вернулась")
    if type(hist) == "table" then
        H.eq(#hist, 7, "все 7 дней прочитаны")
        H.eq(hist[1].date, "2026-11-07", "отсортировано по дате, старое первым")
        H.eq(hist[1].first, 82, "первое число - навык, увиденный в этот день первым")
        H.eq(hist[1].last, 84, "второе - навык, увиденный последним")
        H.eq(hist[1].max, nil, "поля «максимум» в записи нет")
        H.eq(hist[#hist].last, 225, "последний навык последнего дня - 225")
    end

    -- Подъёмов потолка из этой истории не выводится: функции нет.
    H.eq(ns.Api.SkillCapMoves, nil, "Api:SkillCapMoves удалена - считать ей нечего")

    -- Nothing invented for a profession with no history.
    H.eq(ns.Api:MastercraftSkillHistory("Player-1-1", "Enchanting"), nil,
        "по профессии без истории ничего не выдумано")
    H.eq(ns.Api:MastercraftSkillHistory("Player-nope", "Tailoring"), nil,
        "и по чужому персонажу тоже")
end

-- 3. The three states: below cap, at cap, max unknown --------------------

local function world(opts)
    opts = opts or {}
    local env = H.load()
    local ns = env.ns
    ns.Config:Bind({}, {})
    env.money = 5000000
    env.auctionator = true
    H.item(env, 2589, { name = "Лён", sellPrice = 10, stackCount = 20 })
    H.item(env, 2996, { name = "Тканевый пояс", sellPrice = 500, stackCount = 1,
                        equipLoc = "INVTYPE_WAIST", quality = 1, classID = 4 })
    env.prices[2589] = 400
    env.prices[2996] = 90000
    env.bags[2589] = 60
    local recipes = {
        H.recipe({ id = 101, name = "Тканевый пояс", output = 2996, diff = "optimal",
                   reagents = { { itemID = 2589, qty = 3 } } }),
    }
    env.professions[#env.professions + 1] = {
        name = "Tailoring",
        skill = opts.skill,
        max = opts.max,
        maxKnown = (opts.max ~= nil),
        skillTrusted = (opts.skillTrusted ~= false),
    }
    ns.RecipeBook:Store("Tailoring", recipes, "own", ns.CONF.EXACT, H.serverTime)
    ns.RecipeBook:Reindex()
    return env
end

local function findCards(cards, ns)
    local atCap, skillCard
    for _, c in ipairs(cards) do
        if c.cappedProfessions then atCap = c end
        if c.kind == ns.KIND.CRAFT_SKILL and c.recipeID then skillCard = c end
    end
    return atCap, skillCard
end

H.suite("Состояние 1: current < max - добор возможен, планировщик работает")
do
    local env = world({ skill = 160, max = 224 })
    local ns = env.ns
    ns.Config:SetProfile("LEVEL")
    local atCap, skillCard = findCards(H.build(env), ns)
    H.eq(atCap, nil, "карточки «на пределе» нет")
    H.ok(skillCard ~= nil, "есть совет крафтить на навык")
    if skillCard then
        H.ok(skillCard.why:find("160", 1, true), "показан текущий навык")
        H.ok(skillCard.why:find("224", 1, true), "и потолок, взятый из max")
        H.eq(skillCard.skillGoal, 224, "цель планировщика = max из клиента")
        H.eq(skillCard.skillRemaining, 64, "и осталось 64 пункта")
    end
end

H.suite("Состояние 2: current == max - потолок, но без выдуманной причины")
do
    local env = world({ skill = 225, max = 225 })
    local ns = env.ns
    ns.Config:SetProfile("LEVEL")
    local cards = H.build(env)
    local atCap, skillCard = findCards(cards, ns)
    H.ok(atCap ~= nil, "есть карточка про предел")
    H.eq(skillCard, nil, "и НЕТ совета «крафти ради навыка»")
    if atCap then
        H.ok(atCap.why:find("225/225", 1, true), "показан упёршийся навык")
        -- Было: «сказано, что потолок поднимется по ходу игры». Этого аддон
        -- не знает - вывод был сделан из истории НАВЫКА, принятой за историю
        -- потолка. Теперь проверяется обратное: такого обещания нет.
        H.eq(atCap.why:find("по ходу игры", 1, true), nil,
            "не обещано, что максимум «поднимается по ходу игры»")
        H.ok((atCap.need or ""):find("не знаю", 1, true),
            "и сказано прямо: когда максимум поднимется — неизвестно")
        -- The invented cause must be gone from every field the player reads.
        local text = table.concat({ atCap.title or "", atCap.benefit or "",
                                    atCap.why or "", atCap.need or "" }, " ")
        H.eq(text:find("тренер", 1, true), nil,
            "и НЕ сказано «иди к тренеру» - причина потолка нам неизвестна")
        H.eq(text:find("ранг", 1, true), nil, "и слова «ранг» тоже нет")
        H.eq(atCap.informational, true, "карточка справочная")
        H.eq(atCap.benefitValue, 0, "прироста навыка не обещает")
        H.eq(atCap.skillGoal, nil, "и цели прокачки у неё нет")
    end
end

H.suite("Состояние 2: справочная карточка не стоит выше реальных действий")
do
    local env = world({ skill = 225, max = 225 })
    local ns = env.ns
    for _, profile in ipairs({ "LEVEL", "POWER", "GOLD" }) do
        ns.Config:SetProfile(profile)
        local cards = H.build(env)
        local capPos, lastActionPos, actionCount = nil, nil, 0
        for i, c in ipairs(cards) do
            if c.cappedProfessions and not capPos then capPos = i end
            if not c.informational then
                actionCount = actionCount + 1
                lastActionPos = i
            end
        end
        H.ok(capPos ~= nil, profile .. ": справочная карточка на месте")
        H.ok(actionCount > 0, profile .. ": есть с чем сравнивать ("
            .. actionCount .. " действий)")
        -- Not just "below the first action" - below the LAST of them. The
        -- weaker form passed automatically whenever an action happened to be
        -- card one, which it usually is.
        if capPos and lastActionPos then
            H.ok(capPos > lastActionPos, profile
                .. ": справка ниже всех " .. actionCount .. " реальных действий ("
                .. capPos .. " > " .. lastActionPos .. ")")
        end
    end
end

H.suite("Состояние 3: max неизвестен - так и говорим, 225 не подставляем")
do
    local env = world({ skill = 180, max = nil })
    local ns = env.ns
    ns.Config:SetProfile("LEVEL")
    local cards = H.build(env)
    local atCap, skillCard = findCards(cards, ns)
    H.eq(atCap, nil, "в предел не упираемся: сравнивать не с чем")
    H.ok(skillCard ~= nil, "совет на навык всё равно есть")
    if skillCard then
        H.eq(skillCard.skillGoal, nil, "цели нет - max неизвестен")
        H.eq(skillCard.skillRemaining, nil, "и остатка нет")
        H.ok(skillCard.why:find("максимум неизвестен", 1, true),
            "и сказано прямо: максимум неизвестен")
        for _, n in ipairs({ "225", "300" }) do
            H.eq(skillCard.why:find(n, 1, true), nil,
                "в тексте не подставлено " .. n)
        end
    end
end

-- 4. The planner's goal comes from max ----------------------------------

H.suite("Планировщик: цель прокачки берётся из max, не из константы")
do
    local env = world({ skill = 150, max = 160 })
    local ns = env.ns
    local prof = ns.CharacterScanner:Scan().professions[1]
    H.eq(ns.CraftingPlanner:SkillGoal(prof), 160, "цель = max клиента")

    local env2 = world({ skill = 150, max = 999 })
    H.eq(env2.ns.CraftingPlanner:SkillGoal(env2.ns.CharacterScanner:Scan().professions[1]),
        999, "нестандартный max (999) принят как есть")

    local env3 = world({ skill = 150, max = nil })
    H.eq(env3.ns.CraftingPlanner:SkillGoal(env3.ns.CharacterScanner:Scan().professions[1]),
        nil, "без max цели нет - не 225 и не 300")

    local env4 = world({ skill = 225, max = 225 })
    H.eq(env4.ns.CraftingPlanner:SkillGoal(env4.ns.CharacterScanner:Scan().professions[1]),
        nil, "на потолке цели тоже нет - добирать некуда")

    -- Skill we do not trust must not become a goal.
    local env5 = world({ skill = 150, max = 160, skillTrusted = false })
    H.eq(env5.ns.CraftingPlanner:SkillGoal(env5.ns.CharacterScanner:Scan().professions[1]),
        nil, "ненадёжному навыку цель не считаем")
end

H.suite("Планировщик: самый дешёвый путь до max")
do
    local env = world({ skill = 150, max = 160 })
    local ns = env.ns
    local prof = ns.CharacterScanner:Scan().professions[1]
    local path = ns.CraftingPlanner:PathToGoal(prof)
    H.ok(type(path) == "table", "путь посчитан")
    if type(path) == "table" then
        H.eq(path.goal, 160, "цель из max")
        H.eq(path.from, 150, "старт из current")
        H.eq(path.remaining, 10, "осталось 10")
        H.ok(path.recipe ~= nil, "выбран рецепт")
        H.ok(path.crafts and path.crafts >= 10,
            "крафтов не меньше, чем пунктов навыка (" .. tostring(path.crafts) .. ")")
        H.ok(path.cost ~= nil, "и стоимость посчитана")
    end

    local capped = world({ skill = 225, max = 225 })
    H.eq(capped.ns.CraftingPlanner:PathToGoal(
        capped.ns.CharacterScanner:Scan().professions[1]), nil,
        "на потолке пути нет")

    local unknown = world({ skill = 180, max = nil })
    H.eq(unknown.ns.CraftingPlanner:PathToGoal(
        unknown.ns.CharacterScanner:Scan().professions[1]), nil,
        "без max пути нет")
end

-- 5. The source check no longer judges the client by a ladder ------------

H.suite("Сверка с источником: потолок больше не сверяется с лестницей")
do
    local env = H.load()
    local ns = env.ns
    for _, rel in ipairs({ "Data/ForeverSource.lua", "Logic/SourceCheck.lua" }) do
        local chunk = assert(loadfile(H.ROOT .. "/" .. rel))
        setfenv(chunk, env.sandbox)
        chunk("ForeverPilot", ns)
    end
    local SC = ns.SourceCheck
    H.ok(SC ~= nil, "SourceCheck загрузился")

    -- A ceiling nobody documented. Previously this raised a suspicion that
    -- "the rank table is wrong"; now it is simply recorded.
    env.professions[#env.professions + 1] =
        { name = "Tailoring", skill = 93, max = 160, maxKnown = true, skillTrusted = true }
    env.professions[#env.professions + 1] =
        { name = "Fishing", skill = 1, max = 155, maxKnown = true, skillTrusted = true }

    local rep = SC:CheckSkillCaps()
    H.ok(type(rep) == "table", "сверка вернула отчёт")
    if type(rep) == "table" then
        H.eq(rep.compared, true, "сравнение состоялось")
        H.eq(#(rep.professions or {}), 2, "обе профессии записаны")
        local t = rep.professions and rep.professions[1]
        H.eq(t and t.rank, nil, "никакой «ступени» у профессии не появилось")
        H.eq(rep.unknownCaps, nil, "и счётчика «непонятных потолков» больше нет")
    end

    -- No suspicion was raised about a cap of 160 or 155.
    local suspects = 0
    for _, s in pairs((ns.Diag.session and ns.Diag.session.suspects) or {}) do
        if type(s) == "table" and tostring(s.key or ""):find("rank") then
            suspects = suspects + 1
        end
    end
    H.eq(suspects, 0, "подозрений про ранги не поднято - потолок 160 это норма")
end

-- 6. The evidence, fed through the production reader --------------------
--
-- Этот набор назывался «ни один наблюдённый потолок не ложится в лестницу» и
-- доказывал это числами 84, 93, 160, 224 - которые были не потолком, а навыком
-- игрока. Теперь те же записанные дни доказывают обратное прочтение, и
-- доказывают его свойством, которого у пары «навык, максимум» быть не может:
-- второе число каждого дня равно первому числу следующего.

H.suite("Доказательство: в истории Mastercraft навык, а не потолок — дни сцеплены")
do
    local env = adapterEnv()
    local ns = env.ns
    local days = {}
    for _, row in ipairs(CAP_EVIDENCE) do
        days[row[1]] = { s = { [row[2]] = { row[3], row[4] } } }
    end
    env.foreignDB = { history = { ["Player-1-1"] = days } }
    ns.Api:Detect()

    local hist = ns.Api:MastercraftSkillHistory("Player-1-1", "Tailoring")
    H.ok(hist ~= nil and #hist == #CAP_EVIDENCE, "записанные дни прочитаны: " .. tostring(hist and #hist))
    if hist then
        local links, chained = 0, 0
        for i = 2, #hist do
            links = links + 1
            if hist[i].first == hist[i - 1].last then chained = chained + 1 end
            H.ok(hist[i].last >= hist[i].first, string.format(
                "%s: за день навык не падал (%d -> %d)", hist[i].date, hist[i].first, hist[i].last))
        end
        H.eq(chained, links, "каждый день начинается с того числа, которым кончился предыдущий ("
            .. chained .. " из " .. links .. ")")
    end
end

-- 7. Regressions found in review ----------------------------------------

H.suite("Регресс: из окна навыков не просачиваются мечи и языки")
do
    -- C_SkillInfo enumerates the WHOLE skill window: weapon skills, Defense,
    -- languages, Riding. Before this guard, every one of them arrived as a
    -- profession, each with its own blocking "Откройте окно профессии" card
    -- pinned above the real advice. Nine junk cards on a character with two
    -- professions.
    local env = adapterEnv()
    local ns, G = env.ns, env.G
    local WINDOW = {
        { skillID = 0,   name = "Оружие",          isHeader = true },
        { skillID = 43,  name = "Мечи",            isHeader = false, rank = 100, maxRank = 130 },
        { skillID = 95,  name = "Защита",          isHeader = false, rank = 130, maxRank = 130 },
        { skillID = 0,   name = "Языки",           isHeader = true },
        { skillID = 98,  name = "Общий язык",      isHeader = false, rank = 300, maxRank = 300 },
        { skillID = 0,   name = "Основные навыки", isHeader = true },
        { skillID = 197, name = "Портняжное дело", isHeader = false, rank = 224, maxRank = 225 },
        { skillID = 333, name = "Наложение чар",   isHeader = false, rank = 225, maxRank = 225 },
        { skillID = 0,   name = "Второстепенные",  isHeader = true },
        { skillID = 762, name = "Верховая езда",   isHeader = false, rank = 75,  maxRank = 75 },
        { skillID = 185, name = "Кулинария",       isHeader = false, rank = 225, maxRank = 225 },
    }
    local byID = {}
    for _, row in ipairs(WINDOW) do
        if row.skillID > 0 then byID[row.skillID] = row end
    end
    G.C_SkillInfo = {
        GetNumSkillLines = function() return #WINDOW end,
        GetSkillLineInfo = function(i) return WINDOW[i] end,
        GetSkillLineInfoByID = function(id) return byID[id] end,
    }
    ns.Api:Detect()

    local snap = ns.CharacterScanner:Scan()
    local names = {}
    for _, p in ipairs(snap.professions or {}) do names[p.name] = true end

    H.eq(names["Мечи"], nil, "«Мечи» профессией не считаются")
    H.eq(names["Защита"], nil, "«Защита» тоже")
    H.eq(names["Общий язык"], nil, "и язык не профессия")
    H.eq(names["Верховая езда"], nil, "и верховая езда не профессия")
    H.eq(names["Портняжное дело"], true, "а портняжка - да")
    H.eq(names["Наложение чар"], true, "и чары")
    H.eq(names["Кулинария"], true, "и кулинария (второстепенная, но настоящая)")
    H.eq(#(snap.professions or {}), 3, "ровно 3 профессии, а не 7 строк окна")

    -- And nothing junk reaches the card list as a blocking "open the window".
    local junk = 0
    for _, card in ipairs((ns.ActionEngine:Build())) do
        local title = card.title or ""
        if title:find("Мечи", 1, true) or title:find("язык", 1, true)
           or title:find("Защита", 1, true) or title:find("Верховая", 1, true) then
            junk = junk + 1
        end
    end
    H.eq(junk, 0, "и ни одной карточки про мечи, языки или верховую езду")
end

H.suite("Регресс: дыра в GetProfessions не съедает рыбалку и кулинарию")
do
    -- GetProfessions() returns prof1, prof2, archaeology, fishing, cooking, and
    -- archaeology is nil on this client. Collecting those five with
    -- ipairs{...} stops at the nil, so fishing and cooking vanished silently.
    local env = adapterEnv()
    local ns, G = env.ns, env.G
    G.GetProfessions = function() return 1, 2, nil, 4, 5 end
    local INFO = {
        [1] = { "Портняжное дело", 1, 224, 225, 0, 0, 197 },
        [2] = { "Наложение чар",   1, 225, 225, 0, 0, 333 },
        [4] = { "Рыбная ловля",    1, 155, 155, 0, 0, 356 },
        [5] = { "Кулинария",       1, 225, 225, 0, 0, 185 },
    }
    G.GetProfessionInfo = function(idx)
        local r = INFO[idx]
        if not r then return nil end
        return r[1], r[2], r[3], r[4], r[5], r[6], r[7]
    end
    ns.Api:Detect()

    local profs, _, route = ns.Api:Professions()
    H.eq(route, "GetProfessions", "маршрут тот самый")
    H.eq(#profs, 4, "прочитаны все 4 профессии, а не 2 до дыры")
    local names = {}
    for _, p in ipairs(profs) do names[p.name] = p end
    H.ok(names["Рыбная ловля"] ~= nil, "рыбалка не потерялась за дырой")
    H.ok(names["Кулинария"] ~= nil, "и кулинария тоже")
    H.eq(names["Кулинария"] and names["Кулинария"].max, 225, "и её max на месте")
end

H.suite("Регресс: путь до потолка не падает на циклическом рецепте")
do
    -- PathToGoal calls RecipeUnitCost before Plan, and only Plan used to open
    -- the planner's pass. On a recipe whose material tree loops, the cycle
    -- guard indexed a nil table and the whole recompute died.
    local env = H.load()
    local ns = env.ns
    H.item(env, 500, { name = "Ткань" })
    H.item(env, 501, { name = "Свёрток" })
    env.prices[500] = 100
    env.bags[500] = 0
    local recipes = {
        -- 500 -> 501 -> 500: a loop on purpose.
        H.recipe({ id = 900, name = "Свёрток из ткани", output = 501, diff = "optimal",
                   reagents = { { itemID = 500, qty = 2 } } }),
        H.recipe({ id = 901, name = "Ткань из свёртка", output = 500, diff = "optimal",
                   reagents = { { itemID = 501, qty = 1 } } }),
    }
    env.professions[#env.professions + 1] = {
        name = "Tailoring", skill = 150, max = 160, maxKnown = true, skillTrusted = true,
    }
    ns.RecipeBook:Store("Tailoring", recipes, "own", ns.CONF.EXACT, H.serverTime)
    ns.RecipeBook:Reindex()
    local prof = ns.CharacterScanner:Scan().professions[1]

    -- Deliberately NOT calling Plan first: this is the fresh-planner state.
    ns.CraftingPlanner.unitCostMemo = nil
    ns.CraftingPlanner.cyclesSeen = nil
    local ok, res = pcall(function() return ns.CraftingPlanner:PathToGoal(prof) end)
    H.eq(ok, true, "PathToGoal не упал на цикле" .. (ok and "" or (": " .. tostring(res))))
    H.ok(res ~= nil, "и путь всё-таки посчитан")
end

H.suite("Регресс: max = 0 - это «не знаю», а не «ноль»")
do
    -- Zero is truthy in Lua, so `not prof.max` let a zero ceiling through and
    -- the card printed a bare skill number with no warning. The production
    -- SanityCheckSkills blanks it; the card must cope even if it does not.
    local env = world({ skill = 150, max = 0 })
    local ns = env.ns
    ns.Config:SetProfile("LEVEL")
    local atCap, skillCard = findCards(H.build(env), ns)
    H.eq(atCap, nil, "ноль - не потолок, в предел не упираемся")
    H.ok(skillCard ~= nil, "совет на навык есть")
    if skillCard then
        H.eq(skillCard.skillGoal, nil, "цели нет: ноль не максимум")
        H.ok(skillCard.why:find("максимум неизвестен", 1, true),
            "и сказано, что максимум неизвестен")
        H.eq(skillCard.why:find("/0", 1, true), nil, "и «/0» в тексте не напечатано")
    end
end

H.suite("Регресс: SanityCheckSkills - проверяется рабочая версия, не заглушка")
do
    -- The harness used to stub this out with a weaker copy that did not blank a
    -- zero max, which hid the bug above from 1200 green assertions.
    local env = H.load()
    local ns = env.ns
    local profs = {
        { name = "Tailoring", skill = 150, max = 0, skillTrusted = true },
        { name = "Enchanting", skill = 0, max = 0, skillTrusted = false },
    }
    ns.Api:SanityCheckSkills(profs, function() return 0 end)
    H.eq(profs[1].max, nil, "нулевой максимум обнулён в nil")
    H.eq(profs[1].maxKnown, false, "и помечен как неизвестный")
    H.eq(profs[2].skill, nil, "нулевой навык без доверия тоже обнулён")
    H.eq(profs[2].skillBroken, true, "и помечен как сломанный")
end

H.suite("Регресс: маршрут «только имена» не отдаёт максимум")
do
    -- GetProfessionInfoBySkillLineID is documented here as names-only. It must
    -- not export a max even if it happens to report a non-zero one, or that
    -- number would print as a measured ceiling.
    local env = adapterEnv()
    local ns, G = env.ns, env.G
    G.C_TradeSkillUI = G.C_TradeSkillUI or {}
    G.C_TradeSkillUI.GetAllProfessionTradeSkillLines = function() return { 197 } end
    G.C_TradeSkillUI.GetProfessionInfoBySkillLineID = function()
        return { professionName = "Портняжное дело", skillLevel = 0, maxSkillLevel = 300 }
    end
    ns.Api:Detect()
    local profs = ns.Api:Professions()
    H.eq(#profs, 1, "имя взяли")
    if profs[1] then
        H.eq(profs[1].max, nil, "а максимум 300 от этого маршрута отброшен")
        H.eq(profs[1].maxKnown, false, "и помечен неизвестным")
    end
end

-- 9. Имя профессии в клиенте русское, в кеше Mastercraft - английское -----
--
-- ЭТО РАСХОЖДЕНИЕ ТЕСТЫ НЕ ВИДЕЛИ, ПОТОМУ ЧТО ГОВОРИЛИ С АДДОНОМ ПО-АНГЛИЙСКИ.
--
-- Проверки чужого кеша выше спрашивают его по имени «Tailoring». Так профессию
-- называет Mastercraft, и набор на реальных данных собирает из его же кеша
-- «клиентский» список профессий - тоже по-английски. А настоящий клиент
-- отвечает «Портняжное дело», и под таким именем в чужом кеше нет ничего: в
-- игре запись профессии в нём не находилась ни разу.
--
-- (Нашлось это на «истории потолка», которой, как выяснилось позже, в кеше нет
-- вовсе: там история навыка. Мост между именами от этого не стал не нужен - им
-- пользуется сверка навыка с чужим кешем.)
--
-- Мост между двумя именами - номер линии навыка: клиент отдаёт его вместе с
-- профессией, а Data/ForeverSource знает, как эта линия называется по-английски.

local function loadSources(env)
    for _, rel in ipairs({ "Data/ForeverSource.lua", "Logic/SourceCheck.lua" }) do
        local chunk = assert(loadfile(H.ROOT .. "/" .. rel))
        setfenv(chunk, env.sandbox)
        chunk("ForeverPilot", env.ns)
    end
end

local TAILORING_HISTORY = {
    ["2026-11-07"] = { s = { Tailoring = { 82, 84 }, Fishing = { 1, 1 } } },
    ["2026-11-08"] = { s = { Tailoring = { 84, 93 }, Fishing = { 1, 1 } } },
    ["2026-11-13"] = { s = { Tailoring = { 93, 160 }, Fishing = { 1, 1 } } },
    ["2026-11-14"] = { s = { Tailoring = { 160, 224 }, Fishing = { 1, 1 } } },
    ["2026-11-17"] = { s = { Tailoring = { 225, 225 }, Fishing = { 155, 225 } } },
}

H.suite("Чужой кеш: запись профессии находится и по русскому имени из клиента")
do
    local env = H.load()
    local ns = env.ns
    loadSources(env)
    env.foreignDB = { history = { ["Player-1-1"] = TAILORING_HISTORY } }

    -- По английскому имени запись есть.
    local byEnglish = ns.Api:MastercraftSkillHistory("Player-1-1", "Tailoring")
    H.ok(type(byEnglish) == "table" and #byEnglish == 5,
        "по имени из кеша история навыка находится: дней "
        .. tostring(byEnglish and #byEnglish))

    -- Как в игре: профессия пришла из клиента, имя русское, номер линии есть.
    local row = { name = "Портняжное дело", skill = 225, max = 225,
                  skillLineID = 197, skillTrusted = true }
    H.eq(ns.Api:MastercraftSkillHistory("Player-1-1", row.name), nil,
        "по русскому имени напрямую в чужом кеше ничего нет")
    local key = ns.Api:MastercraftProfessionKey(row)
    local byKey = key and ns.Api:MastercraftSkillHistory("Player-1-1", key) or nil
    H.ok(type(byKey) == "table" and #byKey == 5,
        "а по ключу, найденному через номер линии, — находится")
    if type(byKey) == "table" then
        H.eq(byKey[#byKey].last, 225, "последний навык — 225")
        H.eq(byKey[#byKey].date, "2026-11-17", "и дата та же")
    end

    -- И по одному имени, когда вызывающий знает только его: номер линии
    -- берётся из снимка персонажа, где эта профессия уже прочитана.
    env.professions[#env.professions + 1] = row
    env.player.guid = "Player-1-1"
    ns.CharacterScanner:Scan()
    H.eq(ns.Api:MastercraftProfessionKey("Портняжное дело"), "Tailoring",
        "по одному русскому имени ключ тоже находится")

    -- Чужого не выдумываем.
    H.eq(ns.Api:MastercraftProfessionKey({ name = "Вязание крючком" }), nil,
        "по профессии, которой нет в таблице линий, ключа нет")

    -- Имя, под которым профессию хранит кеш.
    H.eq(ns.Api:MastercraftProfessionKey(row), "Tailoring",
        "русское имя с номером линии 197 — это «Tailoring» в кеше")
    H.eq(ns.Api:MastercraftProfessionKey("Fishing"), "Fishing",
        "английское имя остаётся собой")
    H.eq(ns.Api:MastercraftProfessionKey({ name = "Вязание крючком" }), nil,
        "неизвестная профессия ключа не получает")
end

-- 10. Клиент и чужой кеш разошлись по навыку -----------------------------
--
-- Случай с рыбалкой: аддон показал 225/225, в дневной записи Mastercraft за тот
-- же день стояло 155/225. Игрок подтвердил, что докачал её сегодня, - то есть
-- прав клиент, а чужая запись отстала. Отсюда правило, и оно проверяется
-- дословно:
--
--   * ВЕРИМ КЛИЕНТУ. Число в советах и на экране остаётся клиентским.
--   * Достоверность клиентских данных из-за расхождения НЕ понижается.
--   * Расхождение записывается в диагностику - как признак, что чужой кеш
--     отстал, а не как «странность»: тревогу при входе оно не поднимает.

local function skillWorld(clientFishing, cacheFishing, opts)
    opts = opts or {}
    local env = H.load()
    local ns = env.ns
    loadSources(env)
    env.player.guid = "Player-1-1"
    env.professionRoute = opts.route or "C_SkillInfo.GetSkillLineInfoByID"
    env.professions[#env.professions + 1] = {
        name = "Портняжное дело", skill = 225, max = 225, maxKnown = true,
        skillLineID = 197, skillTrusted = true,
    }
    env.professions[#env.professions + 1] = {
        name = "Рыбная ловля", skill = clientFishing[1], max = clientFishing[2],
        maxKnown = true, skillLineID = 356, skillTrusted = true,
        fromCache = opts.fromCache,
    }
    env.foreignDB = { chars = { ["Player-1-1"] = { professions = {
        { name = "Tailoring", skill = 225, max = 225 },
        { name = "Fishing", skill = cacheFishing[1], max = cacheFishing[2] },
    } } } }
    local snap = ns.CharacterScanner:Scan()
    return env, ns, snap
end

local function fishingRow(list)
    for _, p in ipairs(list or {}) do
        if p.name == "Рыбная ловля" then return p end
    end
    return nil
end

local function countLogs(ns, needle)
    local n = 0
    for _, e in ipairs(ns.Diag:Init().log or {}) do
        if tostring(e.text):find(needle, 1, true) then n = n + 1 end
    end
    return n
end

H.suite("Навык: клиент и кеш Mastercraft разошлись — верим клиенту")
do
    local env, ns, snap = skillWorld({ 225, 225 }, { 155, 225 })
    local suspectsBefore = #(ns.Diag:Init().suspicious or {})

    local rep = ns.SourceCheck:CheckSkillCaps()
    H.ok(type(rep) == "table" and rep.compared, "сверка состоялась")

    local row = fishingRow(rep and rep.professions)
    H.ok(row ~= nil, "рыбалка в отчёте есть")
    if row then
        -- 1. Число - клиентское.
        H.eq(row.skill, 225, "в отчёте навык клиента: 225, а не 155 из кеша")
        H.eq(row.max, 225, "и максимум клиента")
        -- 2. Достоверность не тронута.
        H.eq(row.conf, ns.CONF.EXACT, "достоверность осталась «точно»")
        -- 3. Расхождение записано, вместе с тем, что говорил кеш.
        H.ok(type(row.cache) == "table", "что говорил кеш — записано")
        if type(row.cache) == "table" then
            H.eq(row.cache.skill, 155, "навык из кеша: 155")
            H.eq(row.cache.max, 225, "максимум из кеша: 225")
            H.eq(row.cache.route, "MastercraftDB.chars", "и откуда он взят")
            H.eq(row.cache.lags, true, "кеш помечен отставшим (155 меньше 225)")
        end
    end
    H.eq(rep and rep.cacheCompared, 2, "с кешем сверены обе профессии")
    H.eq(rep and rep.cacheDisagreements, 1, "разошлась одна")

    -- Профессия, по которой расхождения нет, пометки не получает.
    local tailoring
    for _, p in ipairs(rep.professions or {}) do
        if p.name == "Портняжное дело" then tailoring = p end
    end
    H.ok(tailoring ~= nil and tailoring.cache == nil,
        "у портняжного дела, где кеш согласен, пометки нет")

    -- Снимок персонажа - то, по чему строятся советы, - не изменился.
    local live = fishingRow(snap.professions)
    H.eq(live and live.skill, 225, "в снимке персонажа навык по-прежнему клиентский")
    H.eq(live and live.conf, ns.CONF.EXACT, "и достоверность в снимке не понижена")

    -- В диагностике - запись, а не «странность».
    H.eq(countLogs(ns, "кеш навыков Mastercraft отстаёт"), 1,
        "в журнале диагностики одна запись про отставший кеш")
    H.eq(#(ns.Diag:Init().suspicious or {}), suspectsBefore,
        "«странностей» не прибавилось: тревогу при входе это не поднимает")

    -- Пересчёт идёт по многу раз в минуту: запись не должна размножаться.
    ns.SourceCheck:CheckSkillCaps()
    ns.SourceCheck:CheckSkillCaps()
    H.eq(countLogs(ns, "кеш навыков Mastercraft отстаёт"), 1,
        "после ещё двух сверок запись всё ещё одна")

    -- И это видно в сводке /fp diag словами. Сводка начинается со сверки
    -- рецептов и без неё отвечает одной строкой «ещё не запускалась», так что
    -- сначала проходит и она - как в игре, где сверки идут все вместе.
    pcall(function() ns.SourceCheck:CheckRecipes() end)
    local summary = table.concat(ns.SourceCheck:Summary() or {}, "\n")
    H.ok(summary:find("155/225", 1, true) ~= nil,
        "в сводке названо, что стояло в кеше: " .. (summary:match("[^\n]*Рыбная[^\n]*") or "?"))
    H.ok(summary:find("верю клиенту", 1, true) ~= nil,
        "и сказано, кому аддон верит")
end

H.suite("Навык: кеш согласен с клиентом — записывать нечего")
do
    local env, ns = skillWorld({ 225, 225 }, { 225, 225 })
    local rep = ns.SourceCheck:CheckSkillCaps()
    local row = fishingRow(rep and rep.professions)
    H.ok(row ~= nil and row.cache == nil, "пометки про кеш нет")
    H.eq(rep and rep.cacheCompared, 2, "сверка с кешем была")
    H.eq(rep and rep.cacheDisagreements, 0, "расхождений нет")
    H.eq(countLogs(ns, "кеш навыков Mastercraft"), 0, "и в журнале пусто")
end

H.suite("Навык: кеш впереди клиента — всё равно верим клиенту")
do
    -- Навык не падает, так что «в кеше больше, чем в клиенте» - случай редкий
    -- (профессию бросили и взяли заново). Правило то же: клиент прав.
    local env, ns = skillWorld({ 40, 75 }, { 225, 225 })
    local rep = ns.SourceCheck:CheckSkillCaps()
    local row = fishingRow(rep and rep.professions)
    H.eq(row and row.skill, 40, "навык клиентский")
    H.eq(row and row.conf, ns.CONF.EXACT, "достоверность не понижена")
    H.ok(row and type(row.cache) == "table", "расхождение записано")
    H.eq(row and row.cache and row.cache.lags, false,
        "но «отстаёт» про такой кеш не говорится — он расходится, а не отстаёт")
    H.eq(countLogs(ns, "кеш навыков Mastercraft расходится"), 1,
        "и в журнале это названо расхождением")
end

H.suite("Навык: когда клиент молчал и число само взято из кеша, кеш с собой не сверяется")
do
    -- Маршрут «MastercraftDB.chars» значит, что клиент не ответил и навык уже
    -- взят из чужого кеша. Сверять кеш с самим собой - значит получить вечное
    -- «согласен» и считать это проверкой.
    local env, ns = skillWorld({ 155, 225 }, { 155, 225 },
        { route = "MastercraftDB.chars", fromCache = true })
    local rep = ns.SourceCheck:CheckSkillCaps()
    H.eq(rep and rep.cacheCompared, 0, "сверки с кешем не было")
    H.ok(type(rep.cacheSkipped) == "string" and rep.cacheSkipped ~= "",
        "и сказано почему: " .. tostring(rep.cacheSkipped))
end

H.suite("Навык: кеша нет вовсе — сверка честно говорит, что её не было")
do
    local env, ns = skillWorld({ 225, 225 }, { 225, 225 })
    env.foreignDB = nil
    local rep = ns.SourceCheck:CheckSkillCaps()
    H.eq(rep and rep.cacheCompared, 0, "сверять не с чем")
    H.ok(type(rep.cacheSkipped) == "string" and rep.cacheSkipped ~= "",
        "причина названа: " .. tostring(rep.cacheSkipped))
    H.eq(countLogs(ns, "кеш навыков Mastercraft"), 0, "в журнале про кеш ничего")
end


end
