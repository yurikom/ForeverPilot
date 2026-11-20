-- ForeverPilot / Logic/SourceCheck.lua
--
-- Does the outside world still match the game?
--
-- Data/ForeverSource.lua was collected from outside the client: Mastercraft's
-- tables, which were generated from Wowhead Forever, spot-checked by hand
-- against Wowhead Forever's own endpoints. That makes it useful on day one and
-- untrustworthy forever after. Patches move recipes, hotfixes move vendors, and
-- a table collected on 2026-11-16 has no way of knowing.
--
-- So this module does the one thing a collected table cannot do for itself: on
-- the next login, it compares every claim against what the client actually
-- says, and writes the differences down. It is the difference between "our data
-- might be wrong" and "our data is wrong HERE, in this row, by this much".
--
-- Four rules, borrowed from Core/Diag.lua because they are the right rules:
--
--   1. It never changes behaviour. SourceCheck decides nothing. It does not
--      correct ForeverSource, does not feed the planner, and does not touch a
--      card. The addon behaves identically with this file absent.
--
--   2. It never costs a scan. Every check runs over data another module has
--      already read for its own reasons - RecipeBook's scan, Api:Professions,
--      the merchant window the player opened. There is no second pass and no
--      extra API call made for the sake of checking.
--
--   3. A finding names the row. "Reagents differ" is useless. "Spell 8758:
--      source says 4305x4, client says 4305x5" can be acted on.
--
--   4. Silence is a finding too. If the client offers no recipes at all, or the
--      recipe ids do not line up with the source's spell ids, that is recorded
--      as "could not compare" and never as "everything matches".
--
-- Findings go to FOREVERPILOT_DIAG through Diag:Suspect, and a deduplicated
-- summary is kept in ForeverPilotDB.sourceCheck so it survives a reload and can
-- be read without catching the session it happened in.
local ADDON, ns = ...

local U = ns.Util
local Api = ns.Api
local Diag = ns.Diag

local SC = {}
ns.SourceCheck = SC

SC.SCHEMA = 1

-- Caps, for the same reason Diag has them: a report that grows without limit is
-- a bug. Mismatches past the cap are counted but not described individually.
SC.CAP = {
    recipeMismatch = 40,
    vendorMismatch = 30,
    placeMismatch  = 30,
    perRun         = 120,
}

-- How far a stored coordinate may sit from where the player stood when the
-- vendor window opened, before we call it a disagreement. The player is not
-- standing inside the NPC: a few map percent is normal, and map percent is a
-- different number of yards in every zone. 4.0 is loose enough not to cry wolf
-- in a city and tight enough to catch a vendor who has actually moved zone or
-- been copied from the Classic coordinates by mistake.
SC.COORD_TOLERANCE = 4.0

SC.findings = nil   -- the live run; attached to the store on first use

-- Store ------------------------------------------------------------------

local function emptyReport()
    return {
        schema = SC.SCHEMA,
        firstRunAt = nil,
        lastRunAt = nil,
        runs = 0,
        source = nil,          -- copy of FS.PROVENANCE, so a stale report is obvious
        compared = {},         -- what we were actually able to compare, and how much
        recipes = {},          -- spellID -> finding
        vendors = {},          -- npcID   -> finding
        places  = {},          -- npcID   -> finding
        slots   = nil,
        skills  = nil,          -- observed current/max per profession, no ladder
        names   = {},          -- npcID -> the client's own localised name
        notes   = {},
    }
end

-- The report lives in the settings DB, not the diagnostics one: it is a
-- cumulative record across sessions, and the diagnostics file keeps only three.
function SC:Report()
    local db = ns.ForeverPilotDB or _G.ForeverPilotDB
    if type(db) ~= "table" then
        -- No store yet (we are being called before the bootstrap bound it, or
        -- outside the game in the test harness). Keep it in memory so the run
        -- still produces findings; it just will not persist.
        self.memory = self.memory or emptyReport()
        return self.memory
    end
    if type(db.sourceCheck) ~= "table" or db.sourceCheck.schema ~= SC.SCHEMA then
        db.sourceCheck = emptyReport()
    end
    return db.sourceCheck
end

local function now()
    return (Api and Api.ServerTime and Api:ServerTime()) or (os and os.time and os.time()) or 0
end

-- Record a finding once, with a count, exactly like Diag:Suspect does. The
-- first time it is also reported to the diagnostics file; after that only the
-- counter moves, so a vendor the player visits daily does not fill the file.
local function note(bucket, key, data, cap)
    local existing = bucket[key]
    if existing then
        existing.seen = (existing.seen or 1) + 1
        existing.lastAt = now()
        return existing, false
    end
    local n = 0
    for _ in pairs(bucket) do n = n + 1 end
    if n >= cap then
        bucket.__overflow = (bucket.__overflow or 0) + 1
        return nil, false
    end
    data.firstAt = now()
    data.lastAt = data.firstAt
    data.seen = 1
    bucket[key] = data
    return data, true
end

-- Reagent comparison -----------------------------------------------------

-- "4305:4,6260:2" -> { [4305] = 4, [6260] = 2 }
function SC:ParseReagents(text)
    if type(text) ~= "string" then return nil end
    local out, n = {}, 0
    for idText, qtyText in text:gmatch("(%d+):(%d+)") do
        local id, qty = tonumber(idText), tonumber(qtyText)
        if id and qty then
            out[id] = (out[id] or 0) + qty
            n = n + 1
        end
    end
    if n == 0 then return nil end
    return out
end

-- The client's recipe, in the same shape. RecipeBook has already merged
-- duplicate slots, which matters: a recipe listing the same cloth in two slots
-- must compare equal to a source that adds them up.
local function clientReagents(recipe)
    local merged = ns.RecipeBook:MergedReagents(recipe)
    if #merged == 0 then return nil end
    local out = {}
    for _, r in ipairs(merged) do out[r.itemID] = (out[r.itemID] or 0) + r.qty end
    return out
end

-- Returns nil when they agree, or a list of human-readable differences.
function SC:DiffReagents(sourceMap, clientMap)
    local diffs, seen = {}, {}
    for id, qty in pairs(sourceMap) do
        seen[id] = true
        local got = clientMap[id]
        if got == nil then
            diffs[#diffs + 1] = string.format("нет в клиенте: %d x%d", id, qty)
        elseif got ~= qty then
            diffs[#diffs + 1] = string.format("%d: источник %d, клиент %d", id, qty, got)
        end
    end
    for id, qty in pairs(clientMap) do
        if not seen[id] then
            diffs[#diffs + 1] = string.format("нет в источнике: %d x%d", id, qty)
        end
    end
    if #diffs == 0 then return nil end
    table.sort(diffs)
    return diffs
end

-- Check 1: recipes ------------------------------------------------------
--
-- Runs over RecipeBook's own list, so it costs nothing beyond the loop. Only
-- recipes present in BOTH the client and the reference are compared: a recipe
-- the source has and the client does not is not a mismatch, it is a recipe this
-- character has not learned, and we cannot tell those apart from here.

-- ЧЬИ РЕЦЕПТЫ СВЕРЯТЬ: ПРОФЕССИИ ЭТОГО ПЕРСОНАЖА, А НЕ ВПИСАННАЯ ПАРА.
--
-- Здесь стоял список { "Tailoring", "Enchanting" } - единственное место во всём
-- аддоне, где профессии были перечислены руками. Для алхимика сверка не
-- состоялась ни разу: `compared` выходил нулём, правило «молчание - это
-- находка» ниже срабатывало, и причиной называлось «откройте окно портняжного
-- дела и наложения чар» - совет персонажу, у которого этих профессий нет.
--
-- Берём то, что есть в книге рецептов, и переводим в английские имена, которыми
-- размечен справочник. Перевод идёт через RecipeBook.NAME_BRIDGE - тот же
-- словарь, которым книга склеивает свои и чужие имена, а не второй экземпляр,
-- который может с ним разойтись.
--
-- Возвращает список английских имён. Профессия, которой в словаре нет, в список
-- не попадает, и это честно: справочник размечен английскими именами, и имени,
-- которого мы не знаем, в нём всё равно нет.
function SC:ProfessionsToCompare()
    local out, seen = {}, {}
    local function add(name)
        if type(name) ~= "string" or name == "" then return end
        local en = ns.RecipeBook.NAME_BRIDGE[ns.Util.lower(name)] or ns.Util.lower(name)
        -- Справочник пишет имена с заглавной буквы («Tailoring», «First Aid»).
        local titled = en:gsub("(%a[%w]*)", function(w)
            return w:sub(1, 1):upper() .. w:sub(2)
        end)
        if not seen[titled] then
            seen[titled] = true
            out[#out + 1] = titled
        end
    end
    -- Сначала то, чем персонаж реально владеет.
    for _, prof in ipairs((ns.CharacterScanner and ns.CharacterScanner:Get()
            and ns.CharacterScanner:Get().professions) or {}) do
        add(prof.name)
    end
    -- И всё, что лежит в книге: рецепты могли прийти из чужого кеша по
    -- профессии, которую клиент в этой сессии ещё не назвал.
    for name in pairs((ns.RecipeBook and ns.RecipeBook.byProfession) or {}) do
        add(name)
    end
    table.sort(out)
    return out
end

-- ИМЕНА ПРОФЕССИЙ ДЛЯ ЧЕЛОВЕКА, А НЕ ДЛЯ ПОИСКА ПО СПРАВОЧНИКУ.
--
-- Список выше - ВНУТРЕННИЙ: он английский потому, что английским размечен
-- справочник (Data/ForeverSource.lua прямо запрещает показывать эти имена
-- игроку). Ровно это и уехало наружу: в живом файле стояло «в справочнике нет
-- рецептов ни по одной из ваших профессий (Alchemy, Cooking, Engineering)» -
-- русская фраза с английскими именами, на русском клиенте. Предыдущая сессия
-- решила, что это артефакт стенда; стенд тут не при чём - имена подставляли мы.
--
-- Перевод идёт через Roster:DisplayName, то есть через тот же единственный
-- словарь NAME_BRIDGE (а он, в свою очередь, спрашивает локализованное имя у
-- Codex). Второго словаря здесь нет и быть не должно.
function SC:DisplayNames(names)
    local out = {}
    for _, name in ipairs(names or {}) do
        local shown = (ns.Roster and ns.Roster.DisplayName)
            and ns.Roster:DisplayName(name) or name
        out[#out + 1] = tostring(shown)
    end
    return out
end

-- Какие профессии справочник вообще знает - СЧИТАЕТСЯ ПО ДАННЫМ, А НЕ ВПИСАНО.
--
-- «Собрано по портняжному делу и наложению чар» - верно сегодня и протухнет при
-- первом же пополнении справочника. Поэтому список берётся из самой таблицы:
-- добавится третья профессия - текст скажет о ней сам.
function SC:ReferenceProfessions()
    local FS = ns.ForeverSource
    if not (FS and FS.RECIPE_REF) then return {} end
    if self.refProfessions then return self.refProfessions end
    local seen, out = {}, {}
    for _, ref in pairs(FS.RECIPE_REF) do
        if type(ref.prof) == "string" and ref.prof ~= "" and not seen[ref.prof] then
            seen[ref.prof] = true
            out[#out + 1] = ref.prof
        end
    end
    table.sort(out)
    self.refProfessions = out
    return out
end

-- Есть ли в справочнике хоть одна строка по этим профессиям. Отвечает на
-- вопрос «сверять не с чем» отдельно от «сверка сломалась»: это два разных
-- ответа, и до их разделения любой нуль объяснялся поломкой.
-- ОТВЕТ ЗАПОМИНАЕТСЯ ПО СОСТАВУ ПРОФЕССИЙ. Спрашивают его теперь на каждом
-- пересчёте (раздел «Откуда я всё это знаю» читает SC:Verdict), а перебор
-- справочника - это 704 строки: ровно та мелочь, из которой складывается пик.
-- Профессии за пересчёт не меняются, а меняются - меняется и ключ.
function SC:ReferenceCovers(profNames)
    local FS = ns.ForeverSource
    if not (FS and FS.RECIPE_REF) then return false end
    local key = table.concat(profNames or {}, "\31")
    self.coversCache = self.coversCache or {}
    if self.coversCache[key] ~= nil then return self.coversCache[key] end
    local want = {}
    for _, n in ipairs(profNames or {}) do want[n] = true end
    local covered = false
    for _, ref in pairs(FS.RECIPE_REF) do
        if ref.prof and want[ref.prof] then covered = true; break end
    end
    self.coversCache[key] = covered
    return covered
end

function SC:CheckRecipes()
    local FS = ns.ForeverSource
    if not (FS and FS.RECIPE_REF) then return nil end
    local report = self:Report()

    local compared, matched, mismatched, unknownID = 0, 0, 0, 0
    local noReagents = 0

    -- ONE LOOKUP, ONE LIST. This used to read byProfession["Tailoring"]
    -- directly, which is always nil because the book is keyed by the name the
    -- player's own client uses ("Портняжное дело"), and then fall back to
    -- scanning EVERY profession - once per English name, so twice. Every recipe
    -- was therefore compared twice and counted as belonging to the wrong
    -- profession on the pass where it did not match: `wrongProfession` came out
    -- at 704, exactly the size of the comparison, while the comparison itself
    -- found zero real disagreements. RecipeBook:Bucket resolves the name
    -- properly, so there is nothing to fall back to.
    local seenRecipe = {}
    local profNames = self:ProfessionsToCompare()
    for _, profName in ipairs(profNames) do
        local entry = ns.RecipeBook:Bucket(profName)
        local lists = {}
        if entry and entry.list then lists[#lists + 1] = entry.list end

        for _, list in ipairs(lists) do
            for _, recipe in ipairs(list) do
              if not seenRecipe[recipe.id] then
                seenRecipe[recipe.id] = true
                local ref = FS.RECIPE_REF[recipe.id]
                if ref and ref.prof == profName then
                    local src = self:ParseReagents(ref.r)
                    local cli = clientReagents(recipe)
                    if not src then
                        noReagents = noReagents + 1
                    elseif not cli then
                        -- The client knows the recipe but gave us no reagents.
                        -- That is a client-read problem, not a data mismatch,
                        -- and RecipeBook already records it; do not double-count.
                        noReagents = noReagents + 1
                    else
                        compared = compared + 1
                        local diffs = self:DiffReagents(src, cli)
                        if diffs then
                            mismatched = mismatched + 1
                            local f, isNew = note(report.recipes, recipe.id, {
                                prof = profName,
                                en = ref.en,
                                clientName = recipe.name,
                                sourceSkill = ref.s,
                                sourceReagents = ref.r,
                                diffs = diffs,
                            }, SC.CAP.recipeMismatch)
                            if isNew and f then
                                Diag:Suspect("source-recipe-differs", string.format(
                                    "рецепт «%s» (id %d): состав в клиенте не совпадает с источником - %s",
                                    recipe.name or ref.en, recipe.id,
                                    table.concat(diffs, "; ")), f)
                            end
                        else
                            matched = matched + 1
                        end

                        -- Output item and quantity, checked separately: a recipe
                        -- can have the right reagents and make something else.
                        local refQty = ref.n or 1
                        if ref.o and recipe.output and ref.o ~= recipe.output then
                            local f, isNew = note(report.recipes, -recipe.id, {
                                prof = profName, en = ref.en, kind = "output",
                                sourceOutput = ref.o, clientOutput = recipe.output,
                            }, SC.CAP.recipeMismatch)
                            if isNew and f then
                                Diag:Suspect("source-recipe-output-differs", string.format(
                                    "рецепт «%s» (id %d): источник делает предмет %d, клиент - %d",
                                    recipe.name or ref.en, recipe.id, ref.o, recipe.output), f)
                            end
                        elseif recipe.outputQty and refQty ~= recipe.outputQty then
                            local f, isNew = note(report.recipes, -recipe.id, {
                                prof = profName, en = ref.en, kind = "outputQty",
                                sourceQty = refQty, clientQty = recipe.outputQty,
                            }, SC.CAP.recipeMismatch)
                            if isNew and f then
                                Diag:Suspect("source-recipe-qty-differs", string.format(
                                    "рецепт «%s» (id %d): источник даёт %d шт. за крафт, клиент - %d",
                                    recipe.name or ref.en, recipe.id, refQty, recipe.outputQty), f)
                            end
                        end
                    end
                elseif ref then
                    -- Same id, different profession in the reference. Worth
                    -- knowing: it means the id spaces do not mean what we think.
                    unknownID = unknownID + 1
                end
              end
            end
        end
    end

    report.compared.recipes = {
        compared = compared, matched = matched, mismatched = mismatched,
        skippedNoReagents = noReagents, wrongProfession = unknownID,
    }

    -- Rule 4: silence is a finding. Zero comparisons means we learned nothing,
    -- and that must not read as success.
    if compared == 0 then
        local why, code
        if next(ns.RecipeBook.byProfession) == nil then
            -- ИМЕНА ПРОФЕССИЙ - ЭТОГО ПЕРСОНАЖА. Здесь стояло «откройте окно
            -- портняжного дела и наложения чар»: совет персонажу, у которого
            -- этих профессий нет. Теперь называются те, что у него есть, а если
            -- клиент не назвал ни одной - так и говорится.
            local mine = {}
            for _, prof in ipairs((ns.CharacterScanner and ns.CharacterScanner:Get()
                    and ns.CharacterScanner:Get().professions) or {}) do
                if prof.crafting and prof.name then mine[#mine + 1] = prof.name end
            end
            -- Имена - через тот же перевод, что ниже: раннее состояние берёт
            -- профессии из чужого кеша, а там они английские.
            mine = SC:DisplayNames(mine)
            why = (#mine > 0)
                and ("рецептов из клиента ещё нет - откройте окно профессии: "
                     .. table.concat(mine, ", "))
                or "рецептов из клиента ещё нет, и ни одной профессии клиент пока не назвал"
            code = "WINDOW_NEVER_OPEN"
        elseif not SC:ReferenceCovers(profNames) then
            -- СПРАВОЧНИК ЗНАЕТ НЕ ВСЕ ПРОФЕССИИ, и это не поломка сверки.
            -- Раньше любой нуль объяснялся «recipeID не равен spellID» - то
            -- есть поломкой механизма; у алхимика же механизм цел, просто
            -- сверять не с чем. Два разных ответа, и решают они разное.
            why = "в справочнике нет рецептов ни по одной из ваших профессий ("
                .. table.concat(SC:DisplayNames(profNames), ", ")
                .. "): сверять не с чем. Справочник собран под другие профессии ("
                .. table.concat(SC:DisplayNames(SC:ReferenceProfessions()), ", ")
                .. "), и под ваши я его не дополняю"
            code = "SOURCE_NOT_COVERED"
        else
            why = "ни один id рецепта из клиента не нашёлся в таблице источника - "
                .. "вероятно, recipeID на этом клиенте не равен spellID, и сверка рецептов невозможна"
            code = "SOURCE_IDS_DIFFER"
        end
        report.compared.recipes.reason = why
        report.compared.recipes.reasonCode = code
        Diag:Suspect("source-recipes-not-compared", "сверка рецептов не состоялась: " .. why)
    end

    return report.compared.recipes
end

-- Check 2: which slots can be enchanted ---------------------------------
--
-- The strongest check in the file, because the client's own enchanting recipes
-- are the definitive answer and ForeverSource states a specific claim: Forever
-- enchants NECK and does not enchant HEAD, SHOULDER, WAIST, LEGS or RANGED.

function SC:CheckEnchantSlots()
    local FS = ns.ForeverSource
    if not (FS and FS.ENCHANT_SLOTS) then return nil end
    local report = self:Report()

    local derived = ns.RecipeBook.EnchantableSlots and ns.RecipeBook:EnchantableSlots()
    if type(derived) ~= "table" or next(derived) == nil then
        report.slots = { compared = false,
            reason = "клиент ещё не показал ни одного рецепта чар - сверять нечего" }
        return report.slots
    end

    local extra, missing = {}, {}
    for slot in pairs(derived) do
        if not FS.ENCHANT_SLOTS[slot] then extra[#extra + 1] = slot end
    end
    for slot in pairs(FS.ENCHANT_SLOTS) do
        if not derived[slot] then missing[#missing + 1] = slot end
    end
    table.sort(extra); table.sort(missing)

    report.slots = {
        compared = true,
        clientSlots = (function()
            local t = {}
            for slot in pairs(derived) do t[#t + 1] = slot end
            table.sort(t); return t
        end)(),
        inClientNotInSource = extra,
        inSourceNotInClient = missing,
    }

    if #extra > 0 then
        Diag:Suspect("source-slots-extra", "клиент зачаровывает слоты, которых нет в нашей таблице: "
            .. table.concat(extra, ", "), report.slots)
    end
    -- A slot in the source and not in the client is expected while the player
    -- knows few recipes: the derived list only covers recipes they have seen.
    -- Only flag it once the client has shown a decent spread, otherwise it is
    -- noise on every new character.
    if #missing > 0 and #report.slots.clientSlots >= 6 then
        Diag:Suspect("source-slots-missing", "в таблице есть слоты, которых клиент не подтвердил: "
            .. table.concat(missing, ", ") .. " (возможно, рецепты просто не изучены)",
            report.slots)
    end
    return report.slots
end

-- Check 3: the skill ceiling, recorded rather than judged -----------------
--
-- THIS CHECK USED TO BE WRONG. It compared the client's maxSkill against a rank
-- ladder taken from two guide sites (75 / 150 / 225 / 300) and raised a
-- suspicion whenever the client disagreed. The client was right every time: the
-- player's own MastercraftDB history has Tailoring capped at 84, then 93, then
-- 160, then 224, then 225 over nine days. A ceiling of 160 was being reported as
-- a bug in the game's data.
--
-- So there is nothing left to compare against, and a check with no claim to test
-- would normally be deleted. This one is kept for the opposite reason: the
-- ceiling MOVES, and nobody else is writing down where it was. Each run records
-- the pair the client reports, and - when the player's cache has a history -
-- when the ceiling last moved. No ladder, no "unrecognised cap", no suspicion
-- raised for a number simply being unfamiliar.

function SC:CheckSkillCaps()
    local report = self:Report()

    -- Rule 2 of this file: never cost a scan. The scanner has already read the
    -- professions for its own reasons, so we read its snapshot - which is also
    -- the list that went through SanityCheckSkills, so what gets recorded here
    -- is what the advice actually saw. Api:Professions is only the fallback for
    -- a call that arrives before the first scan.
    local snap = ns.CharacterScanner and ns.CharacterScanner.snapshot
    local profs, conf
    if snap and type(snap.professions) == "table" and #snap.professions > 0 then
        profs, conf = snap.professions, snap.professionsConf
    else
        profs, conf = Api:Professions()
    end
    if type(profs) ~= "table" or #profs == 0 then
        report.skills = { compared = false, reason = "клиент не отдал список профессий" }
        return report.skills
    end

    local guid = Api.PlayerGUID and Api:PlayerGUID()

    -- СВЕРКА С ЧУЖИМ КЕШЕМ: КЛИЕНТ ПРОТИВ MASTERCRAFT.
    --
    -- У навыка есть второй, независимый источник - кеш Mastercraft. Поводом
    -- стала рыбалка: аддон показал 225/225, а в дневной записи Mastercraft за
    -- тот же день стояло 155/225. Игрок подтвердил, что докачал её сегодня:
    -- прав был клиент, чужая запись просто отстала.
    --
    -- Отсюда правило, и другого здесь нет:
    --   * ВЕРИМ КЛИЕНТУ. Клиент - это игра сейчас, кеш - это игра на момент
    --     последней записи. Число в отчёте и в советах остаётся клиентским.
    --   * Достоверность клиентских данных от расхождения НЕ понижается: не
    --     наоборот и не «оба под сомнением».
    --   * Расхождение записывается - в отчёт и в журнал диагностики - как
    --     признак, что чужой кеш отстал. Не «странностью»: навык растёт каждую
    --     игровую сессию, кеш пишется при выходе, так что отставание - обычное
    --     дело, и поднимать по нему тревогу при входе значило бы врать.
    --
    -- Запись в журнал одна на профессию за сессию, а не на каждое очко навыка:
    -- иначе вечер рыбалки дал бы семьдесят одинаковых строк.
    local cacheByKey, cacheRoute, cacheSkipped
    local routeIsCache = false
    for _, p in ipairs(profs) do
        if p.fromCache or (type(p.route) == "string" and p.route:find("^MastercraftDB")) then
            routeIsCache = true
        end
    end
    if routeIsCache then
        cacheSkipped = "клиент промолчал, навыки уже взяты из кеша Mastercraft —"
            .. " сверять кеш с самим собой нечего"
    elseif not guid then
        cacheSkipped = "GUID персонажа неизвестен — чужой кеш читать нельзя"
    elseif not Api.MastercraftProfessions then
        cacheSkipped = "чтение кеша Mastercraft недоступно"
    else
        local cached, route = Api:MastercraftProfessions(guid)
        if type(cached) == "table" and #cached > 0 then
            cacheByKey, cacheRoute = {}, route
            for _, c in ipairs(cached) do
                if type(c.name) == "string" then cacheByKey[c.name] = c end
            end
        else
            cacheSkipped = "в кеше Mastercraft навыков этого персонажа нет"
        end
    end
    local cacheCompared, cacheDisagreements = 0, 0

    local rows, unknown = {}, 0
    for _, p in ipairs(profs) do
        local row = {
            name = p.name, skill = p.skill, max = p.max,
            maxKnown = p.maxKnown and true or false,
            atCap = (p.skillTrusted and p.skill and p.max and p.skill >= p.max) or false,
            -- The client's own level gate when it offers one. Recorded, never
            -- supplied: this is the field the old rank table was pretending to
            -- know, and only the client can actually answer it.
            minLevel = p.minLevel,
            route = p.route, conf = conf,
        }
        -- «Подъёмов потолка» в сверке больше нет: они считались по истории
        -- Mastercraft, а в ней записан навык, не максимум (см.
        -- Api:MastercraftSkillHistory).

        -- Что про эту же профессию говорит чужой кеш.
        local key = cacheByKey and Api.MastercraftProfessionKey
            and Api:MastercraftProfessionKey(p) or nil
        local cached = key and cacheByKey[key] or nil
        if cached then
            cacheCompared = cacheCompared + 1
            local cs, cm = tonumber(cached.skill), tonumber(cached.max)
            local ps, pm = tonumber(p.skill), tonumber(p.max)
            local differs = (p.skillTrusted and ps and cs and ps ~= cs)
                or (pm and cm and pm ~= cm)
            if differs then
                cacheDisagreements = cacheDisagreements + 1
                -- «Отстаёт» - когда в кеше меньше, чем в клиенте: обычный
                -- случай, навык вырос после последней записи. Больше, чем в
                -- клиенте, - уже не отставание, а расхождение (профессию
                -- бросили и взяли заново). Клиенту верим в обоих случаях.
                local lags = ((cs or 0) < (ps or 0))
                    or ((cs or 0) == (ps or 0) and (cm or 0) < (pm or 0))
                row.cache = {
                    skill = cs, max = cm, route = cacheRoute, key = key, lags = lags,
                }
                local f, isNew = note(report.notes, "cache:" .. tostring(p.name), {
                    kind = lags and "cache-lags" or "cache-differs",
                    profession = p.name, cacheKey = key,
                }, 40)
                if isNew and f then
                    Diag:Log(lags
                        and "кеш навыков Mastercraft отстаёт от клиента — верю клиенту"
                        or "кеш навыков Mastercraft расходится с клиентом — верю клиенту", {
                            profession = p.name, cacheKey = key,
                            client = tostring(ps or "?") .. "/" .. tostring(pm or "?"),
                            cache = tostring(cs or "?") .. "/" .. tostring(cm or "?"),
                            cacheRoute = cacheRoute, clientRoute = p.route,
                        })
                end
            end
        end
        rows[#rows + 1] = row

        -- A ceiling the client would not report is the one thing worth noting,
        -- because advice downstream has to cope with it. It is a gap in what we
        -- were told, not a disagreement with anybody.
        if not row.maxKnown then
            unknown = unknown + 1
            local f, isNew = note(report.notes, "nomax:" .. tostring(p.name), {
                kind = "max-unknown", profession = p.name, route = p.route,
            }, 20)
            if isNew and f then
                Diag:Log("максимум навыка не сообщён клиентом", {
                    profession = p.name, route = p.route,
                })
            end
        end
    end
    report.skills = {
        compared = true, professions = rows, maxUnknown = unknown,
        -- Сверка с кешем Mastercraft: сколько профессий сверено, сколько
        -- разошлось, и - если сверки не было - почему. «Не было» и «была, всё
        -- сошлось» - разные ответы, и по одному нулю их не различить.
        cacheCompared = cacheCompared, cacheDisagreements = cacheDisagreements,
        cacheRoute = cacheRoute, cacheSkipped = cacheSkipped,
    }
    return report.skills
end

-- Check 4: the vendor in front of the player ----------------------------
--
-- Runs only when the player has opened a merchant window, over the items the
-- window already listed. Three claims get tested at once: the NPC's position,
-- what we said they sell, and - the useful side effect - their real localised
-- name, which the client will only ever tell us at this exact moment. That name
-- is stored so the UI can stop showing an English one.

function SC:CheckMerchant()
    local FS = ns.ForeverSource
    if not FS then return nil end
    local npcID = Api:UnitNpcID("npc")
    if not npcID then return nil end

    local report = self:Report()
    local place = FS.VENDOR_PLACES[npcID]

    -- The client's own name for this NPC. Recorded for every vendor, known to
    -- us or not: it is free, it is exact, and it is the only route to a Russian
    -- name we did not invent.
    local clientName = Api:UnitName("npc")
    if clientName then
        local prev = report.names[npcID]
        report.names[npcID] = clientName
        if place and not prev then
            Diag:Log("имя торговца из клиента", { npcID = npcID, client = clientName, en = place.en })
        end
    end

    if not place then
        -- A vendor we have no row for. Not an error - our table is deliberately
        -- a subset - but if they sell something we track, that is a gap worth
        -- recording rather than a mismatch.
        local items = Api:MerchantItems()
        if type(items) == "table" then
            local interesting = {}
            for _, it in ipairs(items) do
                if FS.MAT_VENDORS[it.itemID] then interesting[#interesting + 1] = it.itemID end
            end
            if #interesting > 0 then
                local f, isNew = note(report.vendors, npcID, {
                    kind = "missing-from-table", clientName = clientName,
                    sells = interesting,
                }, SC.CAP.vendorMismatch)
                if isNew and f then
                    Diag:Log("торговец не в нашей таблице, но продаёт нужное", f)
                end
            end
        end
        return nil
    end

    -- Position. The player is standing at the counter, not inside the NPC, so
    -- this is a sanity check on the row, not a measurement of the NPC.
    local mapID, px, py = Api:PlayerPosition()
    if mapID and px and py then
        -- PlayerPosition returns 0-1; the table stores 0-100.
        px, py = px * 100, py * 100
        if place.uiMapID and mapID ~= place.uiMapID then
            local f, isNew = note(report.places, npcID, {
                kind = "map", clientName = clientName, en = place.en,
                sourceMap = place.uiMapID, clientMap = mapID,
                sourceZone = place.zone, clientZone = Api:MapName(mapID),
            }, SC.CAP.placeMismatch)
            if isNew and f then
                Diag:Suspect("source-vendor-wrong-map", string.format(
                    "торговец «%s» (id %d): в таблице карта %s (%s), а игрок стоит на карте %s (%s)",
                    clientName or place.en, npcID, tostring(place.uiMapID),
                    tostring(place.zone), tostring(mapID), tostring(Api:MapName(mapID))), f)
            end
        elseif place.x and place.y then
            local dx, dy = px - place.x, py - place.y
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist > SC.COORD_TOLERANCE then
                local f, isNew = note(report.places, npcID, {
                    kind = "coords", clientName = clientName, en = place.en,
                    sourceX = place.x, sourceY = place.y,
                    playerX = px, playerY = py, distance = dist,
                }, SC.CAP.placeMismatch)
                if isNew and f then
                    Diag:Suspect("source-vendor-coords-far", string.format(
                        "торговец «%s» (id %d): в таблице %.1f, %.1f, а игрок у прилавка на %.1f, %.1f "
                        .. "(расхождение %.1f%% карты)",
                        clientName or place.en, npcID, place.x, place.y, px, py, dist), f)
                end
            end
        end
    end

    -- Stock. Only the materials we claim this NPC sells are checked; everything
    -- else in the window is none of our business.
    local items = Api:MerchantItems()
    if type(items) ~= "table" then return nil end
    local onSale = {}
    for _, it in ipairs(items) do onSale[it.itemID] = it end

    local claimed, confirmed, absent = 0, 0, {}
    for itemID, npcList in pairs(FS.MAT_VENDORS) do
        for _, id in ipairs(npcList) do
            if id == npcID then
                claimed = claimed + 1
                if onSale[itemID] then
                    confirmed = confirmed + 1
                else
                    absent[#absent + 1] = itemID
                end
                break
            end
        end
    end

    if #absent > 0 then
        table.sort(absent)
        local f, isNew = note(report.vendors, npcID, {
            kind = "stock", clientName = clientName, en = place.en,
            claimed = claimed, confirmed = confirmed, notOnSale = absent,
        }, SC.CAP.vendorMismatch)
        if isNew and f then
            local names = {}
            for i = 1, math.min(5, #absent) do
                names[#names + 1] = (FS.ItemName and select(1, FS:ItemName(absent[i])))
                    or tostring(absent[i])
            end
            Diag:Suspect("source-vendor-stock-differs", string.format(
                "торговец «%s» (id %d): в таблице за ним записано %d наших материалов, "
                .. "в окне нет %d из них (%s)",
                clientName or place.en, npcID, claimed, #absent,
                table.concat(names, ", ")), f)
        end
    end

    local v = report.compared
    v.vendorsSeen = (v.vendorsSeen or 0) + 1
    v.vendorItemsConfirmed = (v.vendorItemsConfirmed or 0) + confirmed
    return { npcID = npcID, claimed = claimed, confirmed = confirmed, absent = #absent }
end

-- Runner ----------------------------------------------------------------

-- The static half: everything checkable without the player standing anywhere
-- particular. Called after a recompute, and cheap enough to call often, but
-- there is no point repeating it until the recipe data has changed.
function SC:RunStatic(reasons)
    local FS = ns.ForeverSource
    if not FS then return nil end

    -- Only redo the recipe diff when the recipes actually changed. The slot and
    -- skill checks are a handful of comparisons, so they run either way.
    local wantRecipes = (reasons == nil) or (reasons and reasons.recipes)
        or not self.ranStatic

    local report = self:Report()
    report.source = FS.PROVENANCE
    report.runs = (report.runs or 0) + 1
    report.lastRunAt = now()
    report.firstRunAt = report.firstRunAt or report.lastRunAt

    if wantRecipes then
        Diag:Guard("SourceCheck:CheckRecipes", function() SC:CheckRecipes() end)
    end
    Diag:Guard("SourceCheck:CheckEnchantSlots", function() SC:CheckEnchantSlots() end)
    Diag:Guard("SourceCheck:CheckSkillCaps", function() SC:CheckSkillCaps() end)

    self.ranStatic = true

    local r = report.compared.recipes or {}
    Diag:Module("SourceCheck", {
        ["in"] = r.compared or 0,
        out = (r.mismatched or 0) + ((report.slots and #(report.slots.inClientNotInSource or {})) or 0),
        reason = (r.compared or 0) == 0 and (r.reason or "сверять было нечего") or nil,
        -- КОД ПРИЧИНЫ, А НЕ ТОЛЬКО ТЕКСТ. Без кода Diag:Module ставит
        -- «FREETEXT» и считает это дефектом диагностики (counters.
        -- diag.reasonWithoutCode = 1 в живом файле - это была ровно эта
        -- строка): свободный текст нельзя сравнить между сессиями.
        reasonCode = (r.compared or 0) == 0 and (r.reasonCode or "NO_REASON_GIVEN") or nil,
        matched = r.matched,
        mismatched = r.mismatched,
    })
    return report
end

-- ЧТО СВЕРКА СКАЗАЛА - ОДНОЙ ЗАПИСЬЮ, ДЛЯ ЭКРАНА.
--
-- Сверка умеет молчать осмысленно: «сверять не с чем» - такой же результат, как
-- «всё сошлось». Но до этой функции результат жил ТОЛЬКО в файле диагностики и
-- в ответе на /fp, а со стороны игрока «ветка ничего не сделала» и «всё
-- сошлось» выглядели одинаково. Отсюда её читает Logic/Provenance.lua, то есть
-- раздел «Откуда я всё это знаю» на вкладке «Персонаж».
--
-- НИЧЕГО НЕ СЧИТАЕТ И НЕ СПРАШИВАЕТ КЛИЕНТА: только читает сохранённый отчёт.
-- Правило 2 этого файла («никогда не стоить лишнего чтения») действует и здесь.
function SC:Verdict()
    local report = self:Report()
    local r = (report.compared or {}).recipes
    local v = {
        runs = report.runs or 0,
        ran = (report.runs or 0) > 0 and r ~= nil,
        compared = (r and r.compared) or 0,
        matched = (r and r.matched) or 0,
        mismatched = (r and r.mismatched) or 0,
        reason = r and r.reason or nil,
        reasonCode = r and r.reasonCode or nil,
        lastRunAt = report.lastRunAt,
        -- Чьи профессии сверяли и что справочник вообще знает: оба списка -
        -- именами для человека.
        mine = self:DisplayNames(self:ProfessionsToCompare()),
        reference = self:DisplayNames(self:ReferenceProfessions()),
    }
    v.covered = self:ReferenceCovers(self:ProfessionsToCompare())
    return v
end

-- Wire into the addon without touching a line of it. Events:On appends to a
-- list of listeners, so subscribing here cannot displace Main.lua's handlers,
-- and Events.listeners exists from the moment Core/Events.lua loaded - which is
-- before this file, given where the .toc line goes. No bootstrap edit needed.
function SC:Init()
    if self.wired then return false end
    if not (ns.Events and ns.Events.On) then return false end
    self.wired = true
    ns.Events:On("recompute", function(reasons)
        SC:RunStatic(reasons)
    end)
    ns.Events:On("merchant", function()
        Diag:Guard("SourceCheck:CheckMerchant", function() SC:CheckMerchant() end)
    end)
    return true
end

-- Self-wiring. Normally the call below is all it takes. If this file is ever
-- loaded before Core/Events.lua it would find nothing to subscribe to, so there
-- is a one-shot retry on PLAYER_LOGIN rather than a silent no-op - a checker
-- that quietly fails to run is worse than no checker.
if not SC:Init() then
    local f = CreateFrame and CreateFrame("Frame")
    if f then
        f:RegisterEvent("PLAYER_LOGIN")
        f:SetScript("OnEvent", function(self)
            if SC:Init() then
                self:UnregisterAllEvents()
            elseif ns.Diag then
                ns.Diag:Suspect("sourcecheck-not-wired",
                    "SourceCheck не смог подписаться на события - сверка с источником не запустится")
            end
        end)
    end
end

-- Readable summary, for /dump or a chat command. Deliberately short: the detail
-- lives in the saved report.
function SC:Summary()
    local report = self:Report()
    local lines = {}
    local r = report.compared.recipes

    if not r then
        lines[#lines + 1] = "сверка с источником ещё не запускалась"
        return lines
    end

    if (r.compared or 0) == 0 then
        lines[#lines + 1] = "рецепты: не сверялись - " .. (r.reason or "причина не записана")
    else
        lines[#lines + 1] = string.format(
            "рецепты: сверено %d, совпало %d, расходится %d",
            r.compared, r.matched or 0, r.mismatched or 0)
        local shown = 0
        for id, f in pairs(report.recipes) do
            if type(f) == "table" and f.diffs and shown < 5 then
                shown = shown + 1
                lines[#lines + 1] = "  • " .. tostring(f.clientName or f.en)
                    .. ": " .. table.concat(f.diffs, "; ")
            end
        end
    end

    if report.slots then
        if report.slots.compared then
            local extra = report.slots.inClientNotInSource or {}
            local miss = report.slots.inSourceNotInClient or {}
            if #extra == 0 and #miss == 0 then
                lines[#lines + 1] = "слоты чар: совпадают с источником"
            else
                lines[#lines + 1] = "слоты чар: лишних у клиента " .. #extra
                    .. ", не подтверждено клиентом " .. #miss
            end
        else
            lines[#lines + 1] = "слоты чар: " .. tostring(report.slots.reason)
        end
    end

    if report.skills and report.skills.compared then
        for _, p in ipairs(report.skills.professions or {}) do
            -- An unknown maximum is printed as "?" rather than as a zero or a
            -- borrowed number, so the summary never reads like a measurement
            -- when it is a gap.
            local tail
            if not p.maxKnown then
                tail = " (максимум клиент не сообщил)"
            elseif p.atCap then
                tail = " (на пределе)"
            else
                tail = ""
            end
            -- Чужой кеш разошёлся с клиентом: названо, что в нём стояло, и
            -- кому аддон верит. Число слева остаётся клиентским.
            if type(p.cache) == "table" then
                tail = tail .. string.format("; в кеше Mastercraft %s/%s — кеш %s, верю клиенту",
                    tostring(p.cache.skill or "?"), tostring(p.cache.max or "?"),
                    p.cache.lags and "отстаёт" or "расходится")
            end
            lines[#lines + 1] = string.format("  %s: %s/%s%s",
                tostring(p.name), tostring(p.skill or "?"), tostring(p.max or "?"), tail)
        end
        if report.skills.cacheSkipped then
            lines[#lines + 1] = "  сверка навыков с кешем Mastercraft не проводилась: "
                .. tostring(report.skills.cacheSkipped)
        elseif (report.skills.cacheCompared or 0) > 0 then
            lines[#lines + 1] = string.format(
                "  навыки сверены с кешем Mastercraft: %d, разошлось: %d",
                report.skills.cacheCompared, report.skills.cacheDisagreements or 0)
        end
    end

    local seen = report.compared.vendorsSeen or 0
    local vmis = 0
    for k, v in pairs(report.vendors) do if type(v) == "table" then vmis = vmis + 1 end end
    lines[#lines + 1] = string.format("торговцев проверено: %d, с расхождениями: %d", seen, vmis)

    local named = 0
    for _ in pairs(report.names) do named = named + 1 end
    if named > 0 then
        lines[#lines + 1] = "имён торговцев получено из клиента: " .. named
    end
    return lines
end

function SC:Print()
    for _, line in ipairs(self:Summary()) do Api:Print(line) end
end

return SC
