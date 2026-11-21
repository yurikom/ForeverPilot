-- ForeverPilot / Core/Api.lua
--
-- THE adapter. Every single call into the game client happens in this file and
-- nowhere else. If WoW: Forever disagrees with us about an API, this is the one
-- file that needs editing.
--
-- Rules followed here:
--   * Functions whose existence is proven on this client (either the client
--     itself wrote their output into SavedVariables, or a working addon calls
--     them with no guard at all) are called directly.
--   * Everything else is feature-detected with type(x) == "function" before the
--     first call, and every caller gets a confidence value back so the UI can
--     say "we do not know" instead of inventing a number.
--   * Nothing in here automates gameplay. No buying, no selling, no crafting,
--     no protected calls, nothing during combat.
local ADDON, ns = ...

local Api = {}
ns.Api = Api

local U = ns.Util
local CONF = ns.CONF

-- Detection --------------------------------------------------------------

Api.has = {}
Api.missing = {}

local function detect(key, fn, path)
    local ok = type(fn) == "function"
    Api.has[key] = ok
    if not ok then Api.missing[#Api.missing + 1] = key end
    -- Record the result under the real API path, not our short key, so the
    -- diagnostics file reads as a list of game functions.
    if ns.Diag then ns.Diag:Detect(path or key, ok) end
    return ok
end

-- Resolve a dotted path like "C_Item.GetItemStats" without erroring on a
-- missing namespace.
local function reach(path)
    local cur = _G
    for part in path:gmatch("[^%.]+") do
        if type(cur) ~= "table" then return nil end
        cur = cur[part]
    end
    return cur
end

local F = {} -- resolved functions, keyed the same as Api.has

function Api:Detect()
    Api.has, Api.missing, F = {}, {}, {}
    local paths = {
        -- proven on this client
        recipeIDs        = "C_TradeSkillUI.GetAllRecipeIDs",
        recipeInfo       = "C_TradeSkillUI.GetRecipeInfo",
        recipeSchematic  = "C_TradeSkillUI.GetRecipeSchematic",
        categoryInfo     = "C_TradeSkillUI.GetCategoryInfo",
        recipeCooldown   = "C_TradeSkillUI.GetRecipeCooldown",
        bagNumSlots      = "C_Container.GetContainerNumSlots",
        bagItemLink      = "C_Container.GetContainerItemLink",
        bagItemInfo      = "C_Container.GetContainerItemInfo",
        itemInfo         = "C_Item.GetItemInfo",
        tooltipByID      = "C_TooltipInfo.GetItemByID",
        -- not proven: used only behind Api.has[...]
        itemStats        = "C_Item.GetItemStats",
        itemStatsLegacy  = "GetItemStats",
        professions      = "GetProfessions",
        professionInfo   = "GetProfessionInfo",
        baseProfession   = "C_TradeSkillUI.GetBaseProfessionInfo",
        profLines        = "C_TradeSkillUI.GetAllProfessionTradeSkillLines",
        profBySkillLine  = "C_TradeSkillUI.GetProfessionInfoBySkillLineID",
        profByRecipe     = "C_TradeSkillUI.GetProfessionInfoByRecipeID",
        -- ОТКРЫТИЯ РЕЦЕПТА ЗДЕСЬ НЕТ, И ЭТО НЕ ПРОПУСК. Функция на клиенте
        -- есть - в диагностике игрока она числилась доступной, - но она
        -- защищённая: вызов из аддона игра блокирует и обвиняет аддон. Почему
        -- её нет даже в проверке наличия, написано ниже, у Items.
        isTradeLinked    = "C_TradeSkillUI.IsTradeSkillLinked",
        isTradeGuild     = "C_TradeSkillUI.IsTradeSkillGuild",
        invItemLink      = "GetInventoryItemLink",
        invItemID        = "GetInventoryItemID",
        bankTabs         = "C_Bank.FetchPurchasedBankTabData",
        itemCount        = "C_Item.GetItemCount",
        itemCountLegacy  = "GetItemCount",
        itemCachedByID   = "C_Item.IsItemDataCachedByID",
        requestItemData  = "C_Item.RequestLoadItemDataByID",
        talentTabInfo    = "GetTalentTabInfo",
        specialization   = "GetSpecialization",
        specInfo         = "GetSpecializationInfo",
        surfaceArgs      = "TooltipUtil.SurfaceArgs",
        unitLevel        = "UnitLevel",
        unitClass        = "UnitClass",
        unitRace         = "UnitRace",
        unitFactionGroup = "UnitFactionGroup",
        unitName         = "UnitName",
        unitGUID         = "UnitGUID",
        money            = "GetMoney",
        realmName        = "GetRealmName",
        realmNormalized  = "GetNormalizedRealmName",
        -- Skill lines. The C_SkillInfo namespace is Forever's own (the wiki
        -- marks GetSkillLineInfoByID as exclusive to 1.60.1) and it is the only
        -- route that reports the real pair rank / maxRank, plus the client's own
        -- minLevel. The two globals below are the Classic-era spelling: they are
        -- nil on this client, kept here only so the diagnostics file records
        -- their absence instead of leaving a hole.
        skillByID        = "C_SkillInfo.GetSkillLineInfoByID",
        skillNumLines    = "C_SkillInfo.GetNumSkillLines",
        skillLineAt      = "C_SkillInfo.GetSkillLineInfo",
        numSkillLines    = "GetNumSkillLines",
        skillLineInfo    = "GetSkillLineInfo",
        expandSkillHdr   = "ExpandSkillHeader",
        inCombat         = "InCombatLockdown",
        locale           = "GetLocale",
        bestMapForUnit   = "C_Map.GetBestMapForUnit",
        playerMapPos     = "C_Map.GetPlayerMapPosition",
        mapInfo          = "C_Map.GetMapInfo",
        mapWorldSize     = "C_Map.GetMapWorldSize",
        playerFacing     = "GetPlayerFacing",
        unitGUIDFor      = "UnitGUID",
        unitIsNPC        = "UnitExists",
        merchantNumItems = "GetMerchantNumItems",
        merchantItemInfo = "GetMerchantItemInfo",
        merchantItemLink = "GetMerchantItemLink",
        -- ОБЛИК ВЕЩИ. Зачем это адаптеру и какими именно функциями - в разделе
        -- «Облик (трансмог)» ниже. Здесь только то, что относится к поиску:
        -- ни одна из трёх не считается доказанной, все три спрашиваются через
        -- Api.has, и ответ про каждую уезжает в диагностику под её настоящим
        -- именем - чтобы в файле игрока было видно, что на клиенте есть.
        transmogItemInfo = "C_TransmogCollection.GetItemInfo",
        transmogHasSource = "C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance",
        transmogSourceInfo = "C_TransmogCollection.GetSourceInfo",
        gameRuleActive   = "C_GameRules.IsGameRuleActive",
    }
    for key, path in pairs(paths) do
        local fn = reach(path)
        if detect(key, fn, path) then F[key] = fn end
    end
    -- НАЛИЧИЕ ЗАПИСАНО, ПОЗВАТЬ НЕЧЕМ.
    --
    -- C_TransmogCollection.PlayerHasTransmogByItemInfo выглядит ровно тем, что
    -- нужно: «собран ли облик этой вещи» одним вызовом. Единственное упоминание
    -- этой функции во всех установленных у игрока аддонах - комментарий в
    -- Plumber (API.lua, строка 2748) «PlayerHasTransmogByItemInfo isn't
    -- reliable», после которого он считает то же самое через sourceID. Так что
    -- наличие её в файл диагностики пишется (пригодится, когда станет понятно,
    -- врёт она или нет), а в F её нет - значит и позвать её нельзя.
    do
        local path = "C_TransmogCollection.PlayerHasTransmogByItemInfo"
        detect("transmogByItemInfo", reach(path), path)
        F.transmogByItemInfo = nil
    end
    table.sort(Api.missing)
    Api.detected = true
    -- Память ответов про облик живёт сессию, а обнаружение - это и есть начало
    -- сессии. Пересмотрели, что у клиента есть, - значит прежние ответы могли
    -- быть получены другими функциями, и держать их нельзя.
    Api.appearanceSourceCache = {}
    Api.appearanceCollected = {}
    Api.transmogRule = nil

    -- Globals and constants we read rather than call. Their absence changes
    -- behaviour just as much, so they belong in the same report.
    if ns.Diag then
        for _, name in ipairs({
            "WOW_PROJECT_CAMELOT", "BACKPACK_CONTAINER", "NUM_BAG_SLOTS",
            "NUM_TOTAL_EQUIPPED_BAG_SLOTS", "Enum", "GameTooltip",
            "UIParent", "Minimap", "C_Map", "C_Container", "C_Item",
            "C_TradeSkillUI", "C_SkillInfo", "C_TooltipInfo", "C_Bank", "C_Timer",
            "Auctionator", "Syndicator", "MastercraftDB", "TomTom",
            "ITEM_MOD_INTELLECT_SHORT", "INVTYPE_HEAD",
            "Enum.CraftingReagentType", "Enum.BankType",
            -- Облик: сами пространства имён и признак «трансмог включён».
            -- Их отсутствие значит то же, что отсутствие функций, - проверить
            -- облик нечем, - и записано должно быть так же.
            "C_TransmogCollection", "C_TransmogOutfitInfo", "C_GameRules",
            "Enum.GameRule.TransmogEnabled",
        }) do
            ns.Diag:Detect("[global] " .. name, reach(name) ~= nil)
        end
    end
    return Api.has
end

-- A short human-readable availability report for the Settings tab.
function Api:Report()
    if not Api.detected then Api:Detect() end
    local groups = {
        { "Рецепты профессий", { "recipeIDs", "recipeInfo", "recipeSchematic", "categoryInfo" } },
        { "Сумки",             { "bagNumSlots", "bagItemInfo", "bagItemLink" } },
        { "Банк",              { "bankTabs" } },
        { "Предметы",          { "itemInfo", "itemStats", "tooltipByID" } },
        { "Профессии",         { "skillByID", "professions", "professionInfo", "baseProfession" } },
        { "Специализация",     { "specialization", "talentTabInfo" } },
    }
    local out = {}
    for _, g in ipairs(groups) do
        local okList, badList = {}, {}
        for _, k in ipairs(g[2]) do
            if Api.has[k] then okList[#okList + 1] = k else badList[#badList + 1] = k end
        end
        out[#out + 1] = {
            group = g[1],
            ok = okList,
            missing = badList,
            state = (#badList == 0) and "ok" or (#okList == 0 and "none" or "partial"),
        }
    end
    return out
end

-- Environment ------------------------------------------------------------

function Api:IsForever()
    return _G.WOW_PROJECT_CAMELOT ~= nil
end

function Api:Locale()
    if Api.has.locale then return F.locale() end
    return "enUS"
end

function Api:InCombat()
    if Api.has.inCombat then return F.inCombat() and true or false end
    return false
end

-- ДВИЖЕТСЯ ЛИ ИГРОК. Нужно одному месту: рывок кадра на бегу виден, на месте -
-- нет, поэтому пересчёт на бегу откладывается (MainFrame:ShouldDefer). Функции
-- может не быть - тогда ответ «стоит», и аддон ведёт себя как раньше.
local function movesNow(fn) return (tonumber(fn("player")) or 0) > 0 end
function Api:PlayerMoving()
    local fn = _G.GetUnitSpeed
    if type(fn) ~= "function" then return false end
    -- Сравнение - внутри защищённого вызова (см. Api:PlayerCasting).
    local ok, moving = pcall(movesNow, fn)
    return (ok and moving == true) or false
end

function Api:Now()
    local t = _G.GetTime
    if type(t) == "function" then return t() end
    return (os and os.clock and os.clock()) or 0
end

function Api:ServerTime()
    local t = _G.GetServerTime
    if type(t) == "function" then return t() end
    return (os and os.time and os.time()) or 0
end

-- Player -----------------------------------------------------------------

-- ИМЯ ПЕРСОНАЖА НА FOREVER СОСТОИТ ИЗ ДВУХ ЧАСТЕЙ.
--
-- UnitName("player") на этом клиенте отдаёт ДВА значения: имя и фамилию. На
-- обычном клиенте второе значение - реалм, и у самого игрока оно nil. Разница
-- стоила двух неверных карточек: аддон читал только первое значение, получал
-- «Гендольф», а Syndicator знает того же персонажа как «Гендольф Серыйй» -
-- сравнение имён не совпадало, и ТЕКУЩИЙ персонаж попадал в список чужих.
-- Аддон советовал игроку переслать себе почтой свою же ткань и скрафтить вещи
-- для самого себя.
--
-- Правило отсечения реалма - то же, которым пользуется Mastercraft (Data.lua,
-- ReadName): второе значение не фамилия, если оно совпадает с именем реалма в
-- любом из его написаний.
local function realmLike(value)
    if type(value) ~= "string" or value == "" then return false end
    local realm = Api.has.realmName and F.realmName() or nil
    local norm = Api.has.realmNormalized and F.realmNormalized() or nil
    if realm and (value == realm or value == realm:gsub("[%s%-]", "")) then return true end
    if norm and value == norm then return true end
    return false
end

-- Имя и фамилия в одно имя, которым персонажа знают почта и чужие аддоны.
-- Фамилии нет - возвращается имя, и никакого разделителя не появляется.
function Api:FullName(name, surname)
    if type(name) ~= "string" or name == "" then return nil end
    if type(surname) ~= "string" or surname == "" then return name end
    -- Разделитель берётся у клиента, если он его объявляет: на Forever это
    -- пробел, но объявленная константа надёжнее вписанной.
    local sep = " "
    local C = _G.Constants
    local consts = type(C) == "table" and C.CharacterNameSeparatorConsts or nil
    if type(consts) == "table" and type(consts.CHARACTERNAME_SURNAME_SEPARATOR) == "string" then
        sep = consts.CHARACTERNAME_SURNAME_SEPARATOR
    end
    local tail = sep .. surname
    if name:sub(-#tail) == tail then return name end
    return name .. tail
end

function Api:PlayerInfo()
    local info = { conf = CONF.EXACT }
    if Api.has.unitName then
        local name, second = F.unitName("player")
        info.name = name
        if type(second) == "string" and second ~= "" and not realmLike(second) then
            info.surname = second
        end
        info.fullName = Api:FullName(info.name, info.surname)
    end
    info.guid  = Api.has.unitGUID and F.unitGUID("player") or nil
    info.level = Api.has.unitLevel and F.unitLevel("player") or nil
    info.realm = Api.has.realmName and F.realmName() or nil
    if Api.has.unitClass then
        local localized, file = F.unitClass("player")
        info.className, info.classFile = localized, file
    end
    if Api.has.unitRace then
        local localized, file = F.unitRace("player")
        info.raceName, info.raceFile = localized, file
    end
    if Api.has.unitFactionGroup then
        local file, localized = F.unitFactionGroup("player")
        info.factionFile, info.factionName = file, localized
    end
    if not info.level then info.conf = CONF.UNKNOWN end
    return info
end

-- Just the GUID, for the callers that key a cache by character and have no use
-- for the rest of PlayerInfo.
function Api:PlayerGUID()
    if not Api.has.unitGUID then return nil end
    local ok, guid = pcall(F.unitGUID, "player")
    if ok and type(guid) == "string" and guid ~= "" then return guid end
    return nil
end

function Api:Money()
    if Api.has.money then return F.money() or 0, CONF.EXACT end
    return 0, CONF.UNKNOWN
end

-- Spec. Retail-style specialisation first; then the talent tree with the most
-- points (the classic answer); otherwise nil and the caller falls back to the
-- class default.
function Api:SpecInfo()
    if Api.has.specialization and Api.has.specInfo then
        local idx = F.specialization()
        if idx then
            local ok, id, name = pcall(F.specInfo, idx)
            if ok and id then return { id = id, name = name, conf = CONF.EXACT } end
        end
    end
    if Api.has.talentTabInfo then
        local best, bestPts, total = nil, -1, 0
        for tab = 1, 5 do
            local ok, a, b, c, d, e = pcall(F.talentTabInfo, tab)
            if not ok or a == nil then break end
            -- Signatures differ between flavours. Find the name (string) and the
            -- spent-points number among the first few returns.
            local name, pts
            for _, v in ipairs({ a, b, c, d, e }) do
                if type(v) == "string" and not name then name = v end
                if type(v) == "number" then pts = v end
            end
            pts = pts or 0
            total = total + pts
            if pts > bestPts then best, bestPts = name, pts end
        end
        if best and total > 0 then
            return { id = nil, name = best, points = bestPts, conf = CONF.ESTIMATE }
        end
    end
    return { id = nil, name = nil, conf = CONF.UNKNOWN }
end

-- Professions ------------------------------------------------------------

-- Returns a list of
--   { name, skill, max, maxKnown, skillLineID, skillTrusted, route, conf }
--
-- THE ONE THING THIS FILE IS FOR: the pair (skill, max) is the only source of
-- truth about how far a profession can still go. There is no rank ladder here
-- and there must never be one. The ceiling on WoW: Forever MOVES - the player's
-- own MastercraftDB history has Tailoring capped at 84, then 93, then 160, then
-- 224, then 225 over nine days, and 93 is not a rank in anybody's table. So a
-- cap is whatever the client says it is right now, and when the client will not
-- say, `max` is nil and `maxKnown` is false. Never a default, never 225.
--
-- IMPORTANT, and the reason the route order looks the way it does:
-- C_TradeSkillUI.GetProfessionInfoBySkillLineID hands back skillLevel = 0 and
-- maxSkillLevel = 0 on this client family. A player with Tailoring 225 would
-- come out as Tailoring 0, and every piece of advice that depends on skill would
-- silently evaporate. So that route is used for NAMES ONLY, its numbers are
-- marked skillTrusted = false, and the caller is expected to refuse to believe a
-- zero (see Api:SanityCheckSkills).
--
-- Routes, in order of how much we trust their numbers:
--   1. C_SkillInfo.GetSkillLineInfoByID   - Forever's own; rank / maxRank / minLevel
--   2. GetProfessions + GetProfessionInfo - real numbers (what Mastercraft uses)
--   3. GetBaseProfessionInfo              - real numbers, open window only
--   4. GetProfessionInfoBySkillLineID     - names only, numbers NOT trusted
--   5. MastercraftDB.chars[guid]          - the player's own cache, stale but real
--   6. MastercraftDB.history[guid]        - last resort, the newest day recorded
--
-- The Classic globals GetNumSkillLines / GetSkillLineInfo are deliberately NOT
-- a route: they are nil on Forever, and the namespaced C_SkillInfo pair above
-- replaces them.

-- A skill number is only a number when it is positive. Zero is how this client
-- says "I do not know", and passing a zero on as data is what produced the
-- false "the cap is 225" reading in the first place.
local function posNum(v)
    local n = tonumber(v)
    if n and n > 0 then return n end
    return nil
end

-- Read one SkillLineAttributes table, whatever the client calls its fields.
-- Documented shape on Forever is rank / maxRank; the skillLevel / maxSkillLevel
-- spelling is accepted too so a client that renames them still works.
local function readSkillLine(info)
    if type(info) ~= "table" then return nil end
    if info.isHeader then return nil end
    local name = info.name or info.skillLineName or info.professionName
    if type(name) ~= "string" or name == "" then return nil end
    local cur = posNum(info.rank) or posNum(info.skillLevel)
    local max = posNum(info.maxRank) or posNum(info.maxSkillLevel)
    return {
        name = name,
        skill = cur,
        max = max,
        maxKnown = (max ~= nil),
        -- The client's own level gate, if it offers one. Recorded, never
        -- invented: a nil here means "the client did not say".
        minLevel = posNum(info.minLevel),
        skillLineID = tonumber(info.skillID) or tonumber(info.skillLineID),
        skillTrusted = (cur ~= nil),
    }
end

-- GetProfessions returns five slots - prof1, prof2, archaeology, fishing,
-- cooking - and the empty ones come back nil. Collecting them into a table and
-- walking it with ipairs stops dead at the first hole, and archaeology is
-- normally nil on this client: that silently dropped Fishing and Cooking from
-- every answer. select() over a fixed count has no holes to trip over.
local function professionIndexes()
    if not Api.has.professions then return {} end
    local packed = { pcall(F.professions) }
    if not packed[1] then return {} end
    local out = {}
    for i = 2, 7 do
        local idx = tonumber(packed[i])
        if idx then out[#out + 1] = idx end
    end
    return out
end

-- Every skill line id we can name, and - crucially - whether the id came from
-- somewhere that only ever lists professions.
--
-- C_SkillInfo.GetNumSkillLines walks the WHOLE skill window: weapon skills,
-- Defense, languages, Riding. Those are skill lines with a rank and a maxRank
-- just like a profession, so nothing downstream can tell them apart by shape.
-- Ids harvested that way are marked windowOnly, and CharacterScanner then
-- filters them by name (looksLikeProfession) exactly as it did when the Classic
-- GetNumSkillLines route fed it. Ids from GetAllProfessionTradeSkillLines or
-- GetProfessions are professions by definition and are not marked.
local function skillLineIDs()
    local ids, seen = {}, {}
    local function add(id, windowOnly)
        id = tonumber(id)
        if not id then return end
        if seen[id] then
            -- A profession-authoritative source outranks the skill window.
            if not windowOnly then seen[id].windowOnly = false end
            return
        end
        local entry = { id = id, windowOnly = windowOnly or false }
        seen[id] = entry
        ids[#ids + 1] = entry
    end

    if Api.has.profLines then
        local ok, lines = pcall(F.profLines)
        if ok and type(lines) == "table" then
            for _, line in ipairs(lines) do add(line, false) end
        end
    end
    if Api.has.professionInfo then
        for _, idx in ipairs(professionIndexes()) do
            local ok, _, _, _, _, _, _, line = pcall(F.professionInfo, idx)
            if ok then add(line, false) end
        end
    end
    if Api.has.skillNumLines and Api.has.skillLineAt then
        local ok, n = pcall(F.skillNumLines)
        if ok and type(n) == "number" then
            for i = 1, n do
                local ok2, info = pcall(F.skillLineAt, i)
                if ok2 and type(info) == "table" and not info.isHeader then
                    add(info.skillID or info.skillLineID, true)
                end
            end
        end
    end
    return ids
end

function Api:Professions()
    local out, conf, route = {}, CONF.UNKNOWN, nil

    -- Route 1: Forever's own skill-line reader. Preferred because it is the
    -- only one that also reports the client's minLevel, and because its
    -- maxRank is the live ceiling rather than a guess.
    if Api.has.skillByID then
        for _, entry in ipairs(skillLineIDs()) do
            local ok, info = pcall(F.skillByID, entry.id)
            if ok then
                local row = readSkillLine(info)
                if row then
                    row.skillLineID = row.skillLineID or entry.id
                    -- Only the skill window could have handed us this line, so
                    -- it may well be a weapon skill or a language. Marked for
                    -- CharacterScanner's name filter.
                    row.fromSkillWindow = entry.windowOnly
                    out[#out + 1] = row
                end
            end
        end
        if #out > 0 then conf, route = CONF.EXACT, "C_SkillInfo.GetSkillLineInfoByID" end
    end

    -- Route 2: what Mastercraft reads, and its cache proves the numbers are
    -- real on this client.
    if #out == 0 and Api.has.professionInfo then
        for _, idx in ipairs(professionIndexes()) do
            local ok2, name, _, skill, maxSkill, _, _, skillLine = pcall(F.professionInfo, idx)
            if ok2 and name then
                local max = posNum(maxSkill)
                out[#out + 1] = {
                    name = name,
                    skill = posNum(skill),
                    max = max,
                    maxKnown = (max ~= nil),
                    skillLineID = skillLine,
                    index = idx,
                    skillTrusted = (posNum(skill) ~= nil),
                }
            end
        end
        if #out > 0 then conf, route = CONF.EXACT, "GetProfessions" end
    end

    -- Route 3: whatever profession window is open right now has real numbers.
    if #out == 0 then
        local name, _, skill, maxSkill = Api:OpenProfessionName()
        if name then
            local max = posNum(maxSkill)
            out[#out + 1] = {
                name = name, skill = posNum(skill), max = max, maxKnown = (max ~= nil),
                skillTrusted = (posNum(skill) ~= nil), fromOpenWindow = true,
            }
            conf, route = CONF.EXACT, "GetBaseProfessionInfo"
        end
    end

    -- Route 4: names only. Numbers from here are known bad, so we blank them
    -- rather than pass a zero down the pipe where it looks like real data.
    if #out == 0 and Api.has.profLines and Api.has.profBySkillLine then
        local ok, lines = pcall(F.profLines)
        if ok and type(lines) == "table" then
            for _, line in ipairs(lines) do
                local ok2, pinfo = pcall(F.profBySkillLine, line)
                if ok2 and type(pinfo) == "table" and pinfo.professionName then
                    local reported = tonumber(pinfo.skillLevel) or 0
                    out[#out + 1] = {
                        name = pinfo.professionName,
                        skill = posNum(reported),
                        -- NAMES ONLY, and that has to include the ceiling. This
                        -- route reports 0/0 today, but if it ever reported a
                        -- non-zero max we still could not believe it, and it
                        -- would print as a measured cap - the exact output this
                        -- whole change exists to prevent. Dropped on principle.
                        max = nil,
                        maxKnown = false,
                        skillLineID = line,
                        skillTrusted = false,
                        skillBroken = (reported == 0),
                    }
                end
            end
            if #out > 0 then conf, route = CONF.CACHED, "GetProfessionInfoBySkillLineID" end
        end
    end

    -- Routes 5 and 6: the player's own Mastercraft cache. Stale by definition -
    -- it is whatever was true when they last logged that character out - so it
    -- is CACHED, never EXACT. It is still a real pair of numbers the client
    -- wrote, which beats having none.
    if #out == 0 then
        local guid = Api:PlayerGUID()
        local cached, cachedRoute = Api:MastercraftProfessions(guid)
        if cached and #cached > 0 then
            out, conf, route = cached, CONF.CACHED, cachedRoute
        end
    end

    for _, p in ipairs(out) do
        p.conf = conf
        p.route = route
        if p.skillTrusted == nil then p.skillTrusted = false end
        if p.maxKnown == nil then p.maxKnown = (p.max ~= nil) end
    end

    if ns.Diag then
        ns.Diag:Call("GetProfessions (маршрут)", #out > 0,
            route and ("сработал маршрут: " .. route) or "ни один маршрут не дал данных")
        -- Which professions came back with a believable skill number, which
        -- came back as the known zero, and - separately - how many have a
        -- ceiling at all. A missing ceiling is not an error, it is a fact the
        -- advice has to carry.
        local trusted, zeroed, capped = 0, 0, 0
        for _, p in ipairs(out) do
            if p.skillTrusted and (p.skill or 0) > 0 then trusted = trusted + 1 end
            if p.skillBroken or p.skill == nil then zeroed = zeroed + 1 end
            if p.maxKnown then capped = capped + 1 end
        end
        ns.Diag:Call("GetProfessionInfo (уровень навыка)", trusted > 0,
            string.format("с реальным уровнем: %d, без уровня: %d", trusted, zeroed))
        ns.Diag:Call("максимум навыка (потолок)", capped > 0,
            string.format("потолок известен у %d из %d", capped, #out))
    end
    return out, conf, route
end

-- A profession that reports skill 0 while we hold recipes for it is lying to
-- us. Blank the number and say so, rather than letting a zero drive advice.
-- `recipeCountFor(name)` is supplied by the caller (RecipeBook).
function Api:SanityCheckSkills(professions, recipeCountFor)
    for _, prof in ipairs(professions or {}) do
        local skill = tonumber(prof.skill) or 0
        local haveRecipes = recipeCountFor and (recipeCountFor(prof.name) or 0) or 0
        if skill <= 0 and haveRecipes > 0 then
            prof.skill = nil
            prof.skillTrusted = false
            prof.skillBroken = true
            prof.skillNote = "клиент сообщил навык 0, но рецепты есть - не верю нулю"
        elseif skill <= 0 and not prof.skillTrusted then
            prof.skill = nil
            prof.skillBroken = true
        end
        -- A zero ceiling is the same lie as a zero skill, from the same route.
        -- Blank it rather than let `max = 0` reach the advice, where
        -- `skill >= max` would read as "at the cap" for every character.
        if (tonumber(prof.max) or 0) <= 0 then
            prof.max = nil
            prof.maxKnown = false
        elseif prof.maxKnown == nil then
            prof.maxKnown = true
        end
    end
    return professions
end

-- Recipes ----------------------------------------------------------------

-- Proven: the client wrote the output of these into another addon's
-- SavedVariables, so they are called directly.
function Api:IsTradeSkillUsable()
    if not Api.has.recipeIDs then return false end
    if Api.has.isTradeLinked and F.isTradeLinked() then return false end
    if Api.has.isTradeGuild and F.isTradeGuild() then return false end
    return true
end

function Api:OpenProfessionName()
    if not Api.has.baseProfession then return nil end
    local ok, info = pcall(F.baseProfession)
    if ok and type(info) == "table" then
        return U.trim(info.professionName), info.professionID, info.skillLevel, info.maxSkillLevel
    end
    return nil
end

function Api:AllRecipeIDs()
    if not Api:IsTradeSkillUsable() then
        if ns.Diag then
            ns.Diag:Call("C_TradeSkillUI.GetAllRecipeIDs", nil,
                "окно профессии не открыто (или открыто чужое/гильдейское)")
        end
        return nil
    end
    local ids = F.recipeIDs()
    if type(ids) ~= "table" then
        if ns.Diag then
            ns.Diag:Call("C_TradeSkillUI.GetAllRecipeIDs", false,
                "окно открыто, но список рецептов не вернулся")
        end
        return nil
    end
    if ns.Diag then
        ns.Diag:Call("C_TradeSkillUI.GetAllRecipeIDs", #ids > 0,
            "идентификаторов получено: " .. #ids)
    end
    return ids
end

-- categoryID -> { name, topName }. The category is how we tell an enchant for
-- bracers from an enchant for boots, so this one matters.
local categoryCache = {}
function Api:CategoryInfo(categoryID)
    if not (categoryID and Api.has.categoryInfo) then return nil end
    local hit = categoryCache[categoryID]
    if hit then return hit.name, hit.top, hit.parentID end
    local info = F.categoryInfo(categoryID)
    if type(info) ~= "table" or not info.name then return nil end
    local top, parent, guard = info.name, info.parentCategoryID, 0
    while parent and parent ~= 0 and guard < 5 do
        local p = F.categoryInfo(parent)
        if type(p) ~= "table" or not p.name then break end
        top, parent, guard = p.name, p.parentCategoryID, guard + 1
    end
    categoryCache[categoryID] = { name = info.name, top = top, parentID = info.parentCategoryID }
    return info.name, top, info.parentCategoryID
end

-- One recipe in our own shape. nil when the game has nothing for this id.
--   { id, name, icon, learned, diff, categoryID, categoryName, groupName,
--     output, outputQty, reagents = { {itemID, qty}, ... }, cooldown }
local DIFF = { optimal = "optimal", medium = "medium", easy = "easy", trivial = "trivial" }
local function difficultyKey(relative)
    if type(relative) == "string" then return DIFF[relative] end
    local E = _G.Enum and _G.Enum.TradeskillRelativeDifficulty
    if E and type(relative) == "number" then
        if relative == E.Optimal then return "optimal" end
        if relative == E.Medium then return "medium" end
        if relative == E.Easy then return "easy" end
        if relative == E.Trivial then return "trivial" end
    end
    return nil
end

function Api:ReadRecipe(recipeID)
    if not (recipeID and Api.has.recipeInfo) then return nil end
    local info = F.recipeInfo(recipeID)
    if type(info) ~= "table" or not info.name then return nil end

    local r = {
        id = recipeID,
        name = U.trim(info.name),
        icon = info.icon,
        learned = info.learned and true or false,
        diff = difficultyKey(info.relativeDifficulty),
        categoryID = info.categoryID,
        favorite = info.favorite and true or nil,
        reagents = {},
        conf = CONF.EXACT,
    }
    r.categoryName, r.groupName = Api:CategoryInfo(info.categoryID)

    if Api.has.recipeSchematic then
        local schematic = F.recipeSchematic(recipeID, false)
        if type(schematic) == "table" then
            r.output = schematic.outputItemID
            local qty = tonumber(schematic.quantityMin)
            r.outputQty = (qty and qty > 0) and qty or 1
            local basicType = _G.Enum and _G.Enum.CraftingReagentType
                and _G.Enum.CraftingReagentType.Basic or nil
            local choices = 0
            for _, slot in ipairs(schematic.reagentSlotSchematics or {}) do
                local isBasic = (basicType == nil) or (slot.reagentType == basicType)
                local list = slot.reagents or {}
                local reagent = list[1]
                if isBasic and reagent and reagent.itemID then
                    r.reagents[#r.reagents + 1] = {
                        itemID = reagent.itemID,
                        qty = tonumber(slot.quantityRequired) or 1,
                        -- How many items this one slot would accept. More than
                        -- one means we costed the first and the player may well
                        -- use another, so the total is an estimate.
                        choices = (#list > 1) and #list or nil,
                    }
                    if #list > 1 then choices = choices + 1 end
                end
            end
            -- Surfaced so the planner can refuse to call the cost exact.
            r.reagentChoices = (choices > 0) and (choices + 1) or nil
            if choices > 0 and ns.Diag then
                ns.Diag:Count("recipe.alternativeReagents")
            end
        end
    end
    r.outputQty = r.outputQty or 1

    if r.learned and Api.has.recipeCooldown then
        local ok, cd = pcall(F.recipeCooldown, recipeID)
        if ok then r.cooldown = tonumber(cd) or 0 end
    end
    return r
end

-- ПОЧЕМУ ЗДЕСЬ НЕТ ФУНКЦИИ «ПОКАЗАТЬ РЕЦЕПТ В ОКНЕ ПРОФЕССИЙ».
--
-- Была. Звала C_TradeSkillUI.OpenRecipe, и это ровно тот вызов, на котором
-- игра показала игроку:
--
--   «Модификация "ForeverPilot" заблокирована при попытке выполнения
--    действия, доступного только интерфейсу Blizzard.»
--
-- То есть ADDON_ACTION_BLOCKED: на этом клиенте открытие рецепта - действие,
-- доступное только самой игре. Защита, которая здесь стояла («окно профессий
-- уже загружено самой игрой»), к этому отношения не имела и помочь не могла:
-- блокируют не первую загрузку окна, а сам вызов, из кода аддона - всегда.
--
-- И ХУЖЕ ТОГО: ОТКАЗ БЫЛО НЕЧЕМ ЗАМЕТИТЬ. Заблокированный вызов не бросает
-- ошибку Lua - игра просто его не делает, - поэтому pcall возвращал ok = true,
-- адаптер отвечал «открыл», логика считала, что всё получилось, и ни кнопка не
-- исчезала, ни игроку ничего не говорилось. В FOREVERPILOT_DIAG за три сессии
-- нет ни одной записи про рецепт: ни ошибки, ни отказа. Снаружи это выглядит
-- как «нажимаю - ничего не происходит, и выскакивает окно про блокировку»,
-- и именно так игрок это и описал.
--
-- Правило, которое из этого следует и которое держит Tests/test_ui.lua
-- (закрытый перечень защищённых вызовов): ИМЕНИ ЭТОЙ ФУНКЦИИ В КОДЕ АДДОНА НЕТ
-- ВОВСЕ - ни вызова, ни проверки наличия. Аддон советник: что нажать самому,
-- он говорит СЛОВАМИ (Logic/RecipeBook.lua, RecipeBook:FindText).

-- Items ------------------------------------------------------------------

-- Item data does not change while the player plays, so it is read once and
-- kept. THIS IS A PERFORMANCE FIX WITH A MEASUREMENT BEHIND IT: a single
-- rebuild asked the client for item data 934 times, because the gear branch
-- walks the recipe list four times over and every walk re-read every item. In
-- game that was the bulk of a 64 ms recompute, against 2.8 ms before the gear
-- branch started working at all.
--
-- Only SUCCESSFUL reads are kept. A miss means the client has not cached the
-- item yet; it will fire GET_ITEM_INFO_RECEIVED and the next pass has to ask
-- again, so a miss is never remembered.
Api.itemInfoCache = {}
Api.itemInfoMissed = {}
Api.itemInfoHits = 0
Api.itemInfoReads = 0

-- Start of a rebuild. A MISS is not cached - the client may deliver the data a
-- moment later and we have to ask again - but it is remembered for the length
-- of ONE pass, because the candidate walk asks about the same item several
-- times and re-reading a known miss four times over is pure waste.
-- How many passes a remembered miss may survive without the client saying
-- anything. A backstop only: the normal route out is RetryMissedItems.
Api.MISS_MEMORY_PASSES = 20
Api.passCount = 0

function Api:BeginPass()
    Api.passCount = (Api.passCount or 0) + 1
    if Api.passCount % Api.MISS_MEMORY_PASSES == 0 then
        Api.itemInfoMissed = {}
    end
    Api.itemInfoHits, Api.itemInfoReads = 0, 0
    Api.itemStatsReads = 0
    Api.itemDBReads, Api.foreignCacheHits = 0, 0
    -- ОБЛИК: «СОБРАН ЛИ» СПРАШИВАЕТСЯ ЗАНОВО КАЖДЫЙ ПРОХОД.
    --
    -- Игрок собирает облик в любую секунду - надел вещь, сдал задание, - и
    -- запомненное «не собран» через минуту было бы ложью в ту сторону, где
    -- аддон пугает зря. Сам источник облика (какой у вещи appearanceID) память
    -- переживает: это свойство вещи, оно не меняется.
    Api.appearanceCollected = {}
    Api.appearanceReads, Api.appearanceHits, Api.appearanceAsked = 0, 0, 0
    -- Обращения к Codex считаются ЗА ПЕРЕСЧЁТ, а сам кеш пересчёт переживает:
    -- источники предмета и места NPC за сессию не меняются.
    Api.codexReads, Api.codexHits = 0, 0
    -- А наблюдённые цены из чужого кеша пересчёт НЕ переживают: чужой аддон
    -- дописывает туда лоты, пока игрок играет.
    Api.observedPriceCache = {}
    Api.observedPriceReads, Api.observedPriceHits = 0, 0
    -- А память ответов чужой книги проход ПЕРЕЖИВАЕТ: её ответ не может стать
    -- другим сам (см. Api:MastercraftObservedPrice). Сбрасывает её
    -- Api:ClearObservedPriceMemory по событиям покупки.
    Api.observedPriceSessionHits = 0
    -- Цены: память переживает пересчёт, но не переживает срок.
    local now = Api:Now()
    local limit = ns.AUCTION_CACHE_SECONDS or 600
    -- Отложенное забывание - первым: сигнал аукциона был, окно истекло, значит
    -- пора. Без этого «не чаще раза в минуту» превратилось бы в «не вообще».
    if Api.auctionClearPending and Api.auctionClearedAt
        and (now - Api.auctionClearedAt) >= (ns.AUCTION_RESCAN_GUARD or 60) then
        local why = Api.auctionClearPending
        Api:ClearAuctionCache("отложенное забывание: "
            .. ((type(why) == "string") and why or "сигнал аукциона"))
    end
    if Api.auctionCacheAt and (now - Api.auctionCacheAt) > limit then
        Api:ClearAuctionCache("прошло больше " .. limit .. " с")
    end
    if not Api.auctionCacheAt then Api.auctionCacheAt = now end
    Api.auctionCacheHits = 0
end

-- Called when the client says item data arrived, and whenever the recipe set
-- changes. Cheap: the tables are small and rebuilt on demand.
-- The client delivered item data. Forget which items were missing, so they are
-- asked about again; the successful reads are still valid.
function Api:RetryMissedItems()
    local n = 0
    for _ in pairs(Api.itemInfoMissed) do n = n + 1 end
    Api.itemInfoMissed = {}
    return n
end

function Api:ClearItemCache(why)
    local n = 0
    for _ in pairs(Api.itemInfoCache) do n = n + 1 end
    Api.itemInfoCache = {}
    if ns.Diag and n > 0 then
        ns.Diag:Count("itemInfo.cacheCleared")
        ns.Diag:Log("кеш данных предметов сброшен", { items = n, why = why })
    end
    return n
end

-- Proven available. Returns our own shape so callers never deal with the
-- 20-value return list.
-- ТЕСТОВЫЙ ШОВ, И ОН ЗДЕСЬ НЕ ДЛЯ УДОБСТВА.
--
-- Пока тесты подменяли целиком Api:ItemInfo, они подменяли вместе с ним и КЕШ -
-- то есть ровно то, от чего зависит скорость. Из-за этого замер «5.9 мс» ничего
-- не говорил про игру, где тот же пересчёт стоил 35 мс и 235 обращений к
-- клиенту за предметами. Теперь подменяется только чтение у клиента, а весь
-- учёт - кеш, промахи, счётчики, диагностика - работает в тестах тот же, что в
-- игре. Такой же шов уже есть у банка (Api:InjectBankFakes) и ровно по той же
-- причине.
function Api:InjectItemReader(fn)
    Api.itemReader = fn
end

local function readItemFromClient(itemKey)
    local reader = Api.itemReader or F.itemInfo
    if type(reader) ~= "function" then return nil end
    return reader(itemKey)
end

function Api:ItemInfo(itemKey)
    if not itemKey then return nil, CONF.UNKNOWN end
    if not (Api.has.itemInfo or Api.itemReader) then return nil, CONF.UNKNOWN end

    local cached = Api.itemInfoCache[itemKey]
    if cached then
        Api.itemInfoHits = Api.itemInfoHits + 1
        return cached, CONF.EXACT
    end
    if Api.itemInfoMissed[itemKey] then
        Api.itemInfoHits = Api.itemInfoHits + 1
        return nil, CONF.UNKNOWN
    end
    Api.itemInfoReads = Api.itemInfoReads + 1

    local name, link, quality, baseLevel, reqLevel, class, subclass, stackCount,
          equipLoc, texture, sellPrice, classID, subclassID, bindType =
          readItemFromClient(itemKey)
    if not name then
        -- Not in the client cache yet. Ask for it; the caller retries later.
        if Api.has.requestItemData and type(itemKey) == "number" then
            pcall(F.requestItemData, itemKey)
        end
        if ns.Diag then ns.Diag:Call("C_Item.GetItemInfo", false, "предмет не в кеше клиента") end
        Api.itemInfoMissed[itemKey] = true
        return nil, CONF.UNKNOWN
    end
    if ns.Diag then
        ns.Diag:Call("C_Item.GetItemInfo", true)
        if equipLoc == nil or equipLoc == "" then
            ns.Diag:Count("itemInfo.noEquipLoc")
        end
        if sellPrice == nil then ns.Diag:Count("itemInfo.noSellPrice") end
    end
    local info = {
        itemID = type(itemKey) == "number" and itemKey or U.itemIDFromLink(link),
        name = name,
        link = link,
        quality = quality,
        itemLevel = baseLevel,
        reqLevel = reqLevel or 0,
        className = class,
        subclassName = subclass,
        stackCount = stackCount or 1,
        -- СКАЗАЛ ЛИ КЛИЕНТ РАЗМЕР СТОПКИ ВООБЩЕ.
        --
        -- Поле `stackCount` выше подставляет единицу, когда клиент молчит, и
        -- для большинства читателей это безобидно. Но единица - не нейтральное
        -- значение: она означает «не складывается», то есть «надеваемая вещь», и
        -- Planner:SaleShape («расходник или вещь») на ней делал утверждение из
        -- незнания. Отдельный признак оставляет подстановку для всех, кому она
        -- удобна, и даёт честный ответ тому, для кого разница существенна.
        stackCountKnown = (stackCount ~= nil),
        equipLoc = equipLoc,
        texture = texture,
        sellPrice = tonumber(sellPrice) or 0,
        classID = classID,
        subclassID = subclassID,
        bindType = bindType,
    }
    -- Keyed by whatever the caller passed, because a link carries a suffix and
    -- an enchant that a bare id does not, and the two must not share an entry.
    Api.itemInfoCache[itemKey] = info
    return info, CONF.EXACT
end

-- НАДЕВАЕМАЯ ЛИ ЭТО ВЕЩЬ - ПО ОТВЕТУ КЛИЕНТА, А НЕ ПО ДОГАДКЕ.
--
-- Нужно одному месту: решить, стоит ли ради бонусов лезть в тултип (см.
-- Api:ItemStatsRaw). Расходник и реагент в этом не нуждаются, а их в проходе
-- большинство - на реальных данных из 338 предметов надеваемых меньше сотни.
-- Ответ берётся из уже прочитанных данных предмета, то есть бесплатно: equipLoc
-- лежит в кеше Api:ItemInfo.
function Api:LooksEquippable(itemLinkOrID)
    local info = Api:ItemInfo(itemLinkOrID)
    local loc = info and info.equipLoc
    return type(loc) == "string" and loc ~= "" and loc ~= "INVTYPE_NON_EQUIP_IGNORE"
end

function Api:ItemCached(itemID)
    if Api.has.itemCachedByID then
        local ok, cached = pcall(F.itemCachedByID, itemID)
        if ok then return cached and true or false end
    end
    return nil
end

-- ОБЛИК (ТРАНСМОГ) -------------------------------------------------------
--
-- ЕДИНСТВЕННЫЙ НЕОТМЕНИМЫЙ УБЫТОК, КОТОРЫЙ АДДОН МОЖЕТ ПОСОВЕТОВАТЬ.
--
-- Любую другую ошибку здешних советов игрок может отменить: не покупать, не
-- крафтить, переделать. Эту - нет. Непривязанная вещь необычного качества и
-- выше, которую продали торговцу, отправили почтой или распылили, из коллекции
-- облика пропадает НАВСЕГДА. Поэтому вопрос «а облик с неё уже собран?» нужен
-- ДО совета, и ответ на него спрашивается здесь.
--
-- КАКИМИ ФУНКЦИЯМИ. Доказательство - чужие аддоны, которые стоят у игрока и
-- работают (правило этого файла: «зовёт без единой проверки наличия - значит
-- функция есть»):
--
--   * C_TransmogCollection.GetItemInfo(ссылка|id) -> appearanceID, sourceID.
--     Зовут Plumber (API.lua, раздел Transmog: он собирается при IS_MODERN, а
--     Forever у него и есть IS_MODERN) и Syndicator (Search/CheckItem.lua,
--     GetSourceID) - оба без проверок.
--   * C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance(sourceID)
--     -> собран ли ИМЕННО этот источник. Тем же двоим и так же без проверок.
--   * C_TransmogCollection.GetSourceInfo(sourceID) -> .isCollected. Второй путь
--     к тому же ответу, нужен когда первого нет.
--   * C_GameRules.IsGameRuleActive(Enum.GameRule.TransmogEnabled) -> включён ли
--     трансмог на клиенте вообще. Так спрашивает Plumber
--     (Modules/OutfitSelect.lua, Modules/LootUI/EditMode.lua), а его
--     OutfitSelect разрешён для Forever строкой
--     «[AllowLoadGameType standard, mists, camelot]» в Plumber.toc - то есть
--     и C_GameRules, и Enum.GameRule.TransmogEnabled на этом клиенте есть.
--
-- ЧЕГО ЗДЕСЬ НЕТ ВТОРЫМ НОМЕРОМ: C_TransmogCollection.AccountCanCollectSource.
-- Syndicator ею пользуется и, если она отвечает «этот облик собрать нельзя»,
-- молчит про предмет вовсе (Search/CheckItem.lua). Соблазн сделать так же
-- большой - это убрало бы ложные тревоги. Но правило, по которому аддон
-- МОЛЧИТ, обязано быть доказанным: ошибись оно на Forever - и игрок потеряет
-- облик, прочитав у нас, что всё в порядке. Ложная тревога стоит игроку минуты
-- внимания, пропущенная - вещи навсегда, и цена этих ошибок несопоставима.
--
-- ЧИТАЮЩИЕ ВЫЗОВЫ, И ТОЛЬКО. Ни одной функции, которая что-то НАДЕВАЕТ или
-- СОХРАНЯЕТ облик, здесь нет и быть не может: C_Transmog.ApplyAllPending и всё
-- семейство C_TransmogOutfitInfo.Set* - это действие вместо игрока, то есть
-- ровно то, на чём аддон однажды уже получил «Модификация заблокирована» (см.
-- перечень защищённых вызовов в Tests/test_ui.lua).
--
-- ПРАВИЛА ПО УРОВНЮ ПЕРСОНАЖА ЗДЕСЬ НЕТ, И ЭТО СОЗНАТЕЛЬНО. По рассказам
-- игроков уровневое ограничение трансмога на Forever ведёт себя несвязно:
-- 41 - да, 40 - да, 37 - нет, 33 - нет, 32 - да, 26 - нет, 21 - нет, 17 - да.
-- Из такого ряда правило не выводится, а выдуманное правило было бы хуже его
-- отсутствия: оно молчало бы ровно там, где облик теряется.

-- ТЕСТОВЫЙ ШОВ, И ОН ЗДЕСЬ НУЖНЕЕ, ЧЕМ ГДЕ-ЛИБО.
--
-- Офлайн клиента нет, значит НЕТ И ОТВЕТА ПРО ОБЛИК: в стенде никто не может
-- сказать, собран он или нет. Поэтому по умолчанию шва нет вовсе, и адаптер в
-- стенде отвечает «не знаю» - то есть правду. Заглушка, которая отвечала бы
-- «собран», превратила бы всю эту проверку в её отсутствие, причём незаметно.
--
-- Шов подменяет ТОЛЬКО чтение у клиента (как Api:InjectItemReader у предметов и
-- Api:InjectBankFakes у банка): память, счётчики и диагностика в стенде
-- работают те же, что в игре.
--   fns.source(itemKey)       -> appearanceID, sourceID
--   fns.collected(sourceID)   -> true / false / nil
--   fns.rule()                -> включён ли трансмог
function Api:InjectTransmogReader(fns)
    Api.transmogFakes = fns
    Api.appearanceSourceCache = {}
    Api.appearanceCollected = {}
    Api.transmogRule = nil
end

Api.transmogFakes = nil
-- Память источника облика живёт ВСЮ СЕССИЮ: «какой у этой вещи облик» - это
-- свойство самой вещи, оно не меняется, пока игра не обновится.
Api.appearanceSourceCache = {}
-- А «собран ли он» живёт ОДИН ПРОХОД: игрок может собрать облик в любую
-- секунду, и несобранный облик не имеет права остаться несобранным в памяти.
Api.appearanceCollected = {}

-- Включён ли трансмог на этом клиенте. true / false / nil («спросить нечем»).
--
-- Спрашивается ОДИН РАЗ ЗА СЕССИЮ: правило игры не меняется, пока игрок не
-- перезашёл, а спрашивать его по каждому предмету значило бы добавить вызов на
-- каждого кандидата продажи и распыла (на настоящих данных это 250 вызовов за
-- пересчёт вместо одного).
function Api:TransmogEnabled()
    if Api.transmogRule ~= nil then
        if Api.transmogRule == "unknown" then return nil end
        return Api.transmogRule
    end
    local value = Api:ReadTransmogRule()
    Api.transmogRule = (value == nil) and "unknown" or value
    return value
end

function Api:ReadTransmogRule()
    local fakes = Api.transmogFakes
    if fakes and fakes.rule ~= nil then
        if type(fakes.rule) == "function" then
            local ok, active = pcall(fakes.rule)
            if ok then return active end
            return nil
        end
        return fakes.rule and true or false
    end
    if not Api.has.gameRuleActive then return nil end
    local rule = reach("Enum.GameRule.TransmogEnabled")
    if rule == nil then
        if ns.Diag then
            ns.Diag:Call("C_GameRules.IsGameRuleActive", false,
                "Enum.GameRule.TransmogEnabled на этом клиенте нет")
        end
        return nil
    end
    local ok, active = pcall(F.gameRuleActive, rule)
    if not ok then
        if ns.Diag then
            ns.Diag:Call("C_GameRules.IsGameRuleActive", false, "вызов не удался")
        end
        return nil
    end
    if ns.Diag then
        ns.Diag:Call("C_GameRules.IsGameRuleActive", true,
            "трансмог " .. (active and "включён" or "выключен"))
    end
    return active and true or false
end

-- Какой облик у вещи. Возвращает { appearanceID, sourceID } или nil и КОД
-- причины: "no-api" (функции нет), "no-source" (клиент ответил, а облика у
-- вещи нет), "no-item".
function Api:AppearanceSource(itemKey)
    if not itemKey then return nil, "no-item" end
    local cached = Api.appearanceSourceCache[itemKey]
    if cached ~= nil then
        Api.appearanceHits = (Api.appearanceHits or 0) + 1
        if cached == false then return nil, "no-source" end
        return cached
    end

    local reader = (Api.transmogFakes and Api.transmogFakes.source)
        or (Api.has.transmogItemInfo and F.transmogItemInfo) or nil
    if type(reader) ~= "function" then
        if ns.Diag then
            ns.Diag:Call("C_TransmogCollection.GetItemInfo", nil,
                "функции нет на этом клиенте — собран ли облик, сказать нечем")
        end
        return nil, "no-api"
    end

    Api.appearanceReads = (Api.appearanceReads or 0) + 1
    local ok, appearanceID, sourceID = pcall(reader, itemKey)
    if not ok then
        if ns.Diag then
            ns.Diag:Call("C_TransmogCollection.GetItemInfo", false, "вызов не удался")
        end
        return nil, "no-api"
    end
    sourceID = tonumber(sourceID)
    if not sourceID or sourceID == 0 then
        -- Ответ ЕСТЬ, и он отрицательный: у этой вещи облика не бывает
        -- (расходник, материал, патроны). Это не «не знаю», и помнить его можно
        -- так же долго, как и положительный.
        Api.appearanceSourceCache[itemKey] = false
        if ns.Diag then
            ns.Diag:Call("C_TransmogCollection.GetItemInfo", true, "у вещи нет облика")
        end
        return nil, "no-source"
    end
    local out = { appearanceID = tonumber(appearanceID), sourceID = sourceID }
    Api.appearanceSourceCache[itemKey] = out
    if ns.Diag then ns.Diag:Call("C_TransmogCollection.GetItemInfo", true) end
    return out
end

-- Собран ли облик этой вещи.
--   true  - собран (вещь можно продать, облик останется)
--   false - НЕ собран
--   nil   - не знаю, и код причины вторым значением
-- Третье значение - достоверность: ответ клиента это EXACT, его отсутствие
-- UNKNOWN. Своей оценки здесь не бывает: про облик угадать нельзя.
function Api:AppearanceCollected(itemKey)
    -- СКОЛЬКО РАЗ ВОПРОС ВООБЩЕ ДОШЁЛ ДО КЛИЕНТА. Это и есть цена проверки, и
    -- мерить её надо здесь, а не в миллисекундах: на клиенте без этих функций
    -- обращений не будет вовсе, а вопросов - столько же.
    Api.appearanceAsked = (Api.appearanceAsked or 0) + 1
    local source, why = Api:AppearanceSource(itemKey)
    if not source then return nil, why or "no-api", CONF.UNKNOWN end

    local sourceID = source.sourceID
    local remembered = Api.appearanceCollected[sourceID]
    if remembered ~= nil then
        Api.appearanceHits = (Api.appearanceHits or 0) + 1
        return remembered, remembered and "collected" or "not-collected", CONF.EXACT
    end

    local fakes = Api.transmogFakes
    local known = (fakes and fakes.collected)
        or (Api.has.transmogHasSource and F.transmogHasSource) or nil
    Api.appearanceReads = (Api.appearanceReads or 0) + 1
    if type(known) == "function" then
        local ok, has = pcall(known, sourceID)
        if ok and has ~= nil then
            Api.appearanceCollected[sourceID] = has and true or false
            if ns.Diag then
                ns.Diag:Call("C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance", true)
            end
            return (has and true or false), (has and "collected" or "not-collected"), CONF.EXACT
        end
        if ns.Diag then
            ns.Diag:Call("C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance",
                false, "вызов не дал ответа")
        end
    end

    -- Запасной путь: тот же ответ лежит в описании источника.
    local info = (fakes and fakes.sourceInfo)
        or (Api.has.transmogSourceInfo and F.transmogSourceInfo) or nil
    if type(info) == "function" then
        local ok, rec = pcall(info, sourceID)
        if ok and type(rec) == "table" and rec.isCollected ~= nil then
            local has = rec.isCollected and true or false
            Api.appearanceCollected[sourceID] = has
            if ns.Diag then
                ns.Diag:Call("C_TransmogCollection.GetSourceInfo", true)
            end
            return has, (has and "collected" or "not-collected"), CONF.EXACT
        end
        if ns.Diag then
            ns.Diag:Call("C_TransmogCollection.GetSourceInfo", false, "вызов не дал ответа")
        end
    end
    return nil, "no-api", CONF.UNKNOWN
end

-- КАКИЕ СТАТЫ БОНУСОВ СЧИТАЮТСЯ «БОНУСОМ», А НЕ БАЗОЙ.
--
-- На этом сервере прямой вызов отдаёт только базовые характеристики
-- (выносливость, интеллект, дух, сила, ловкость): в живом файле 786 успешных
-- ответов C_Item.GetItemStats, и ни в одном нет силы магии. А решает сравнение
-- вещей как раз бонус. Если в прямом ответе нет НИ ОДНОГО бонусного ключа,
-- тултип спрашивается дополнительно - вдруг клиент напишет его текстом.
local BONUS_KEYS = {
    ITEM_MOD_SPELL_POWER_SHORT = true,
    ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = true,
    ITEM_MOD_SPELL_HEALING_DONE_SHORT = true,
    ITEM_MOD_ATTACK_POWER_SHORT = true,
    ITEM_MOD_CRIT_SPELL_RATING_SHORT = true,
    ITEM_MOD_HIT_SPELL_RATING_SHORT = true,
    ITEM_MOD_HASTE_SPELL_RATING_SHORT = true,
    ITEM_MOD_CRIT_RATING_SHORT = true,
    ITEM_MOD_HIT_RATING_SHORT = true,
    ITEM_MOD_HASTE_RATING_SHORT = true,
    ITEM_MOD_EXPERTISE_RATING_SHORT = true,
    ITEM_MOD_POWER_REGEN0_SHORT = true,
    ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = true,
    ITEM_MOD_DODGE_RATING_SHORT = true,
    ITEM_MOD_PARRY_RATING_SHORT = true,
    ITEM_MOD_BLOCK_RATING_SHORT = true,
}

local function hasBonus(stats)
    if type(stats) ~= "table" then return false end
    for key in pairs(stats) do
        if BONUS_KEYS[key] then return true end
    end
    return false
end

-- Stats. Three routes, and we are honest when all three fail.
--   1. C_Item.GetItemStats / GetItemStats -> { ITEM_MOD_INTELLECT_SHORT = 10 }
--   2. parse the tooltip against the client's own localised ITEM_MOD_* strings
--   3. nothing: return nil with CONF.UNKNOWN
function Api:ItemStatsRaw(itemLinkOrID)
    if not itemLinkOrID then return nil, CONF.UNKNOWN end
    -- Counted because it is one of the two calls that dominate a rebuild in
    -- game, and the file had no way to say how often it happened.
    Api.itemStatsReads = (Api.itemStatsReads or 0) + 1

    local fn = (Api.has.itemStats and F.itemStats) or (Api.has.itemStatsLegacy and F.itemStatsLegacy)
    if fn then
        local link = itemLinkOrID
        if type(link) == "number" then
            local info = Api:ItemInfo(link)
            link = info and info.link
        end
        if link then
            local ok, stats = pcall(fn, link)
            if ok and type(stats) == "table" and next(stats) then
                if ns.Diag then
                    ns.Diag:Call("C_Item.GetItemStats", true, "характеристики читаются напрямую")
                end
                -- ТУЛТИП - НЕ ТОЛЬКО ПОСЛЕДНЯЯ НАДЕЖДА, НО И ДОБАВКА.
                --
                -- Прямой ответ на этом клиенте базовый, и ровно поэтому всё
                -- сравнение вещей держалось на внешней базе целиком. Для
                -- НАДЕВАЕМОЙ вещи без единого бонусного ключа спрашиваем тултип
                -- и доливаем то, чего в прямом ответе не было. Ключи берутся из
                -- тех же собственных строк клиента (ITEM_MOD_*), что и всегда:
                -- ничего не угадывается, а чего клиент не написал - того и не
                -- появится.
                if not hasBonus(stats) and Api:LooksEquippable(itemLinkOrID) then
                    local extra = Api:ParseTooltipStats(itemLinkOrID)
                    local added = 0
                    if type(extra) == "table" then
                        for key, value in pairs(extra) do
                            if stats[key] == nil and BONUS_KEYS[key] then
                                stats[key] = value
                                added = added + 1
                            end
                        end
                    end
                    if ns.Diag then
                        Api.statsFromTooltip = (Api.statsFromTooltip or 0) + added
                        ns.Diag:Call("C_TooltipInfo.GetItemByID (добавка к статам)",
                            added > 0, (added > 0)
                                and ("бонусов добралось из тултипа: " .. added)
                                or "в тултипе бонусов тоже нет — остаётся внешняя база")
                    end
                end
                return stats, CONF.EXACT
            end
            if ns.Diag then
                ns.Diag:Call("C_Item.GetItemStats", false,
                    ok and "функция есть, но вернула пусто" or "вызов упал")
            end
        end
    elseif ns.Diag then
        ns.Diag:Call("C_Item.GetItemStats", nil, "функции нет на этом клиенте")
    end

    local parsed = Api:ParseTooltipStats(itemLinkOrID)
    if parsed and next(parsed) then
        if ns.Diag then
            ns.Diag:Call("C_TooltipInfo.GetItemByID (разбор статов)", true,
                "характеристики получены разбором тултипа")
        end
        return parsed, CONF.ESTIMATE
    end
    if ns.Diag then
        ns.Diag:Call("C_TooltipInfo.GetItemByID (разбор статов)", false,
            "ни прямой вызов, ни тултип не дали характеристик")
    end
    return nil, CONF.UNKNOWN
end

-- Build "+%d к интеллекту" -> ITEM_MOD_INTELLECT_SHORT matchers out of the
-- client's own global strings, so this works in any locale without us
-- translating a single word by hand.
local statPatterns
local function buildStatPatterns()
    if statPatterns then return statPatterns end
    statPatterns = {}
    local keys = {
        "ITEM_MOD_INTELLECT_SHORT", "ITEM_MOD_SPIRIT_SHORT", "ITEM_MOD_STAMINA_SHORT",
        "ITEM_MOD_STRENGTH_SHORT", "ITEM_MOD_AGILITY_SHORT",
        "ITEM_MOD_SPELL_POWER_SHORT", "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT",
        "ITEM_MOD_SPELL_HEALING_DONE_SHORT",
        "ITEM_MOD_CRIT_SPELL_RATING_SHORT", "ITEM_MOD_HIT_SPELL_RATING_SHORT",
        "ITEM_MOD_HASTE_SPELL_RATING_SHORT",
        "ITEM_MOD_CRIT_RATING_SHORT", "ITEM_MOD_HIT_RATING_SHORT",
        "ITEM_MOD_HASTE_RATING_SHORT", "ITEM_MOD_EXPERTISE_RATING_SHORT",
        "ITEM_MOD_ATTACK_POWER_SHORT", "ITEM_MOD_POWER_REGEN0_SHORT",
        "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT", "ITEM_MOD_DODGE_RATING_SHORT",
        "ITEM_MOD_PARRY_RATING_SHORT", "ITEM_MOD_BLOCK_RATING_SHORT",
        "ITEM_MOD_HEALTH_SHORT", "ITEM_MOD_MANA_SHORT",
        "RESISTANCE6_NAME", "RESISTANCE2_NAME", "RESISTANCE3_NAME",
        "RESISTANCE4_NAME", "RESISTANCE5_NAME",
    }
    for _, key in ipairs(keys) do
        local text = _G[key]
        if type(text) == "string" and text ~= "" then
            -- "+%d к интеллекту" / "%s2 Intellect" -> a Lua pattern with one capture
            local pat = text:gsub("%%s%d?", "%%s"):gsub("%%d", "%%s")
            pat = pat:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
            pat = pat:gsub("%%%%s", "(%%d+)")
            if pat:find("%(%%d%+%)") then
                -- ОБРАЗЕЦ ЗАКРЫТ С ОБОИХ КОНЦОВ, И ЭТО НЕ ПЕДАНТИЗМ.
                --
                -- Без конца строки «+8 к силе магии» совпадало с образцом силы
                -- («+%d к силе») - то есть сила магии кастера читалась как
                -- физическая сила. Ошибка молчала только потому, что разбор
                -- тултипа на этом клиенте не возвращал вообще ничего (строки
                -- лежат в args, см. Api:TooltipLineText); починить чтение и
                -- оставить открытый образец значило бы включить её.
                statPatterns[#statPatterns + 1] = {
                    key = key, pattern = "^%s*" .. pat .. "%s*$",
                }
            else
                -- Resistance names have no number placeholder: "+%d к сопротивлению огню"
                statPatterns[#statPatterns + 1] = {
                    key = key, pattern = "(%d+)[^%d]*" .. pat, loose = true,
                }
            end
        end
    end
    -- САМЫЙ ДЛИННЫЙ ОБРАЗЕЦ - ПЕРВЫМ. Вторая половина той же защиты: из двух
    -- подходящих образцов выигрывает более подробный, а не тот, который раньше
    -- оказался в списке. Порядок устойчивый: при равной длине - по имени.
    table.sort(statPatterns, function(a, b)
        if #a.pattern ~= #b.pattern then return #a.pattern > #b.pattern end
        return a.key < b.key
    end)
    return statPatterns
end

-- ТЕКСТ ОДНОЙ СТРОКИ ТУЛТИПА - В ТОЙ ФОРМЕ, В КАКОЙ ЕГО ОТДАЁТ ЭТОТ КЛИЕНТ.
--
-- C_TooltipInfo отдаёт строки двумя разными способами, и на этом билде работает
-- ТОЛЬКО ВТОРОЙ:
--
--   1. готовым полем line.leftText - так бывает, когда клиент уже разложил
--      аргументы сам или когда их разложил TooltipUtil.SurfaceArgs;
--   2. списком line.args, где каждый элемент - { field = "leftText",
--      stringVal = "..." }. Разложить его должен TooltipUtil.SurfaceArgs, а на
--      этом клиенте этой функции НЕТ (в снимке игрока
--      detect["TooltipUtil.SurfaceArgs"] = false при существующем
--      C_TooltipInfo.GetItemByID).
--
-- Пока читалось только поле, второй случай давал nil на каждой строке: разбор
-- тултипа возвращал пусто ВСЕГДА, и в живом файле у него стоит «587 попыток,
-- 587 пустых, 0 с данными». Теперь args читаются сами, и какой формой ответил
-- клиент - видно в диагностике.
function Api:TooltipLineText(line)
    if type(line) ~= "table" then return nil end
    if type(line.leftText) == "string" then return line.leftText end
    if Api.has.surfaceArgs then
        pcall(F.surfaceArgs, line)
        if type(line.leftText) == "string" then
            Api.tooltipTextFromField = (Api.tooltipTextFromField or 0) + 1
            return line.leftText
        end
    end
    local args = line.args
    if type(args) ~= "table" then return nil end
    for _, a in pairs(args) do
        if type(a) == "table" and a.field == "leftText"
            and type(a.stringVal) == "string" then
            Api.tooltipTextFromArgs = (Api.tooltipTextFromArgs or 0) + 1
            return a.stringVal
        end
    end
    return nil
end

function Api:ParseTooltipStats(itemLinkOrID)
    if not Api.has.tooltipByID then return nil end
    local itemID = type(itemLinkOrID) == "number" and itemLinkOrID or U.itemIDFromLink(itemLinkOrID)
    if not itemID then return nil end
    local ok, data = pcall(F.tooltipByID, itemID)
    if not ok or type(data) ~= "table" or type(data.lines) ~= "table" then return nil end

    local pats = buildStatPatterns()
    local out, lines, read = {}, 0, 0
    for _, line in ipairs(data.lines) do
        lines = lines + 1
        local text = Api:TooltipLineText(line)
        if type(text) == "string" then
            read = read + 1
            for _, p in ipairs(pats) do
                local n = text:match(p.pattern)
                if n then
                    out[p.key] = (out[p.key] or 0) + (tonumber(n) or 0)
                    break
                end
            end
        end
    end
    -- СКОЛЬКО СТРОК ВООБЩЕ УДАЛОСЬ ПРОЧИТАТЬ. Разница между «строк нет» и
    -- «строки есть, а текста из них не достать» - это разница между «предмет не
    -- в кеше клиента» и «мы читаем ответ не той формы», и в живом файле их было
    -- не отличить.
    if ns.Diag and lines > 0 then
        ns.Diag:Call("C_TooltipInfo.GetItemByID (строки)", read > 0,
            string.format("строк %d, с текстом %d (из args %d, из поля %d)",
                lines, read, Api.tooltipTextFromArgs or 0,
                Api.tooltipTextFromField or 0))
    end
    return next(out) and out or nil
end

-- Containers -------------------------------------------------------------

-- Proven: C_Container.GetContainerNumSlots / GetContainerItemInfo are called
-- with no guard by a working addon on this exact client.
-- GetContainerItemInfo returns a TABLE here (verified against a working addon):
--   { itemID, stackCount, hyperlink, quality, isBound, hasNoValue, ... }
-- Тестовый шов для чтения сумок, такой же и по той же причине, как у банка
-- (Api:InjectBankFakes): в аддоне его не зовёт никто. Нужен он одному - дать
-- проверить офлайн, что из ответа клиента по ячейке мы забираем ИМЕННО те поля,
-- на которые потом опираемся. Поле isBound («привязана ли эта вещь») решает,
-- предупреждать ли про облик, а без шва ни одна проверка до производственного
-- чтения сумок не доходила вовсе.
function Api:InjectBagFakes(fakes)
    Api.bagFakes = fakes
end

function Api:BagCounts()
    local fakes = Api.bagFakes
    local numSlots = fakes and fakes.numSlots or (Api.has.bagNumSlots and F.bagNumSlots)
    local itemInfo = fakes and fakes.itemInfo or (Api.has.bagItemInfo and F.bagItemInfo)
    if not (numSlots and itemInfo) then
        if ns.Diag then
            ns.Diag:Call("C_Container.GetContainerItemInfo", nil,
                "функций чтения сумок нет на этом клиенте")
        end
        return {}, CONF.UNKNOWN, {}
    end
    local counts, slots = {}, {}
    local lastBag = _G.NUM_BAG_SLOTS or 4
    local backpack = _G.BACKPACK_CONTAINER or 0
    local scannedSlots, tableShaped = 0, nil
    for bag = backpack, lastBag do
        local n = numSlots(bag) or 0
        scannedSlots = scannedSlots + n
        for slot = 1, n do
            local info = itemInfo(bag, slot)
            if info ~= nil and tableShaped == nil then
                -- This client returns a table; a client returning the old
                -- multi-value form would break every bag read silently, so the
                -- shape is recorded once.
                tableShaped = (type(info) == "table")
            end
            if type(info) == "table" and info.itemID then
                local qty = tonumber(info.stackCount) or 1
                U.addTo(counts, info.itemID, qty)
                slots[#slots + 1] = {
                    bag = bag, slot = slot, itemID = info.itemID, qty = qty,
                    link = info.hyperlink, quality = info.quality,
                    noValue = info.hasNoValue and true or false,
                    -- ПРИВЯЗАНА ЛИ ИМЕННО ЭТА ВЕЩЬ, А НЕ «БЫВАЕТ ЛИ ТАКАЯ
                    -- ПРИВЯЗАННОЙ». Разница решает всё в проверке облика:
                    -- привязанная вещь уже ваша, и её облик уже записан, а
                    -- непривязанную зелёнку, если её продать, теряешь навсегда.
                    -- Поле проверено на данных игрока: его Syndicator пишет
                    -- isBound по каждой ячейке (true у надетого, false у
                    -- купленного), а берёт его из этого же ответа клиента -
                    -- значит клиент его отдаёт. Отдельного вызова это не стоит:
                    -- ячейки всё равно читаются.
                    bound = info.isBound,
                }
            end
        end
    end
    if ns.Diag then
        ns.Diag:Call("C_Container.GetContainerItemInfo", #slots > 0,
            string.format("ячеек просмотрено %d, занятых %d, форма ответа: %s",
                scannedSlots, #slots,
                tableShaped == nil and "нечего было проверить"
                    or (tableShaped and "таблица (ожидаемая)" or "не таблица — это сломает чтение")))
        if tableShaped == false then
            ns.Diag:Suspect("bag-info-shape",
                "C_Container.GetContainerItemInfo вернул не таблицу — чтение сумок не работает")
        end
    end
    return counts, CONF.EXACT, slots
end

-- Reagent bags and the character bank, when the client exposes them. The player
-- has to have the bank open at least once for the tabs to be readable; until
-- then we report UNKNOWN rather than pretending the bank is empty.
-- Test seam: lets the bank reading be driven by plain tables without the game.
-- Nothing in the addon calls this; it exists so the container-id arithmetic can
-- be checked, because that is exactly the part that cannot be checked in game
-- without a bank and a lot of clicking.
function Api:InjectBankFakes(fakes)
    Api.bankFakes = fakes
end

-- The containers that belong to the player's own bags, which must never be
-- counted as bank space: doing so doubles every stack the player is carrying.
function Api:PlayerBagContainers()
    if Api.bankFakes and Api.bankFakes.playerBags then return Api.bankFakes.playerBags end
    local set = { [0] = true }  -- the backpack
    local n = tonumber(_G.NUM_BAG_SLOTS) or 4
    for bag = 1, n do set[bag] = true end
    return set
end

function Api:BankCounts()
    local counts = {}
    local seenAny = false

    local fakes = Api.bankFakes
    local numSlots = fakes and fakes.numSlots or (Api.has.bagNumSlots and F.bagNumSlots)
    local itemInfo = fakes and fakes.itemInfo or (Api.has.bagItemInfo and F.bagItemInfo)

    if numSlots and itemInfo then
        local first = _G.NUM_TOTAL_EQUIPPED_BAG_SLOTS and (_G.NUM_TOTAL_EQUIPPED_BAG_SLOTS + 1) or 5
        local containers = { -1 } -- the old single bank container
        for bag = first, first + 11 do containers[#containers + 1] = bag end

        -- C_Bank.FetchPurchasedBankTabData is a modern call and its `ID` is a
        -- TAB index, not necessarily a container id. On a client where those
        -- numbering schemes overlap, feeding a tab id straight to
        -- GetContainerNumSlots reads the player's own bags and reports them as
        -- bank contents. So any id that collides with a player bag, or with a
        -- container we are already going to read, is dropped.
        local playerBags = Api:PlayerBagContainers()
        local planned = {}
        for _, bag in ipairs(containers) do planned[bag] = true end

        local tabFn = fakes and fakes.tabs or (Api.has.bankTabs and F.bankTabs)
        if tabFn then
            local ok, tabs = pcall(tabFn,
                _G.Enum and _G.Enum.BankType and _G.Enum.BankType.Character)
            if ok and type(tabs) == "table" then
                for _, tab in ipairs(tabs) do
                    local id = tonumber(tab and tab.ID)
                    if id and not playerBags[id] and not planned[id] then
                        planned[id] = true
                        containers[#containers + 1] = id
                    elseif id and playerBags[id] and ns.Diag then
                        ns.Diag:Count("bank.tabIdCollision")
                    end
                end
            end
        end

        local done = {}
        for _, bag in ipairs(containers) do
            if not done[bag] and not playerBags[bag] then
                done[bag] = true
                local n = numSlots(bag)
                if n and n > 0 then
                    seenAny = true
                    for slot = 1, n do
                        local info = itemInfo(bag, slot)
                        if type(info) == "table" and info.itemID then
                            U.addTo(counts, info.itemID, tonumber(info.stackCount) or 1)
                        end
                    end
                end
            end
        end
    end

    if ns.Diag then
        ns.Diag:Call("C_Bank / банковские контейнеры", seenAny,
            seenAny and ("видов предметов в банке: " .. U.count(counts))
                or "банк ни разу не открывали в этой сессии")
    end
    if seenAny then return counts, CONF.EXACT end
    return nil, CONF.UNKNOWN
end

-- Equipment --------------------------------------------------------------

-- slotKey -> { itemID, link, enchantID } for every slot we reason about.
-- ИГРОК ЧТО-ТО ПРОИЗНОСИТ ИЛИ ДЕЛАЕТ ВЕЩЬ ----------------------------------
--
-- Крафт - тоже произнесение: окно профессии шлёт событие на каждую сделанную
-- вещь, и пересчёт на каждое из них дёргал бы кадр всю очередь крафта. Пока
-- полоска заклинания идёт, пересчёт ждёт (Main:ShouldDefer).
--
-- Имена функций у клиентов разные: с единицей (UnitCastingInfo) и без
-- (CastingInfo старой классики). Нет ни одной - ответ «нет», и пересчёт идёт
-- как раньше.
-- Проверка «ответ не пустой» делается ВНУТРИ защищённого вызова: клиент может
-- вернуть значение, которое нельзя ни сравнивать, ни проверять на истинность
-- («секретное»), и тогда ошибка остаётся здесь, а не роняет пересчёт.
local function castsWithUnit(fn) return fn("player") ~= nil end
local function castsBare(fn) return fn() ~= nil end
local CAST_WITH_UNIT = { "UnitCastingInfo", "UnitChannelInfo" }
local CAST_BARE = { "CastingInfo", "ChannelInfo" }
function Api:PlayerCasting()
    local G = _G
    for i = 1, #CAST_WITH_UNIT do
        local fn = G[CAST_WITH_UNIT[i]]
        if type(fn) == "function" then
            local ok, casting = pcall(castsWithUnit, fn)
            if ok and casting == true then return true end
        end
    end
    for i = 1, #CAST_BARE do
        local fn = G[CAST_BARE[i]]
        if type(fn) == "function" then
            local ok, casting = pcall(castsBare, fn)
            if ok and casting == true then return true end
        end
    end
    return false
end

-- БАФФЫ НА ИГРОКЕ ----------------------------------------------------------
--
-- До сих пор аддон не читал их вовсе. Слова игрока: «он должен учитывать всё -
-- сумки, то, что поставлено от костра, баффы, которые на мне». Чтение дешёвое
-- (до сорока обращений за проход, и только когда проход вообще делается) и
-- ничего не меняет в игре.
--
-- Два пути, оба под защитой: современный C_UnitAuras и старый UnitBuff. Нет ни
-- одного - возвращается пустой список и nil вместо имени пути, и это НЕ то же
-- самое, что «баффов нет»: вызывающий обязан различать.
--   { name, spellID, expires, stacks }
--
-- ЗНАЧЕНИЕ МОЖЕТ БЫТЬ «СЕКРЕТНЫМ». У этого клиента есть значения, которые
-- можно держать в переменной, но нельзя сравнивать, складывать и склеивать (у
-- соседнего аддона на них целый файл - SecretAuraRanks). Поэтому каждое поле
-- баффа проходит через plain*: операция над ним делается внутри защищённого
-- вызова, и секретное поле становится nil, а не ошибкой посреди пересчёта.
Api.MAX_AURAS = 40
local function plainString(v)
    if type(v) ~= "string" then return nil end
    if #v == 0 then return nil end
    return v .. ""
end
local function plainNumber(v)
    if type(v) ~= "number" then return nil end
    return v + 0
end
local function plain(kind, v)
    -- Никаких сравнений снаружи защищённого вызова - даже с nil.
    local isSecret = _G.issecretvalue
    if type(isSecret) == "function" then
        local okS, secret = pcall(isSecret, v)
        if okS and secret then return nil end
    end
    local ok, out = pcall(kind, v)
    if ok then return out end
    return nil
end
Api.PlainString = function(v) return plain(plainString, v) end
Api.PlainNumber = function(v) return plain(plainNumber, v) end

local function auraFields(a)
    return a.name, a.spellId, a.expirationTime, a.applications
end
function Api:PlayerAuras()
    local out = {}
    local CU = _G.C_UnitAuras
    if type(CU) == "table" and type(CU.GetAuraDataByIndex) == "function" then
        for i = 1, Api.MAX_AURAS do
            local ok, a = pcall(CU.GetAuraDataByIndex, "player", i, "HELPFUL")
            if not ok or type(a) ~= "table" then break end
            local okF, name, spellID, expires, stacks = pcall(auraFields, a)
            if okF then
                name = plain(plainString, name)
                spellID = plain(plainNumber, spellID)
                -- Бафф без читаемого имени и без номера сравнивать не с чем.
                if name or spellID then
                    out[#out + 1] = {
                        name = name, spellID = spellID,
                        expires = plain(plainNumber, expires),
                        stacks = plain(plainNumber, stacks),
                    }
                end
            end
        end
        return out, "C_UnitAuras.GetAuraDataByIndex"
    end
    local UB = _G.UnitBuff
    if type(UB) == "function" then
        for i = 1, Api.MAX_AURAS do
            local ok, name, _, count, _, _, expires, _, _, _, spellID =
                pcall(UB, "player", i, "HELPFUL")
            if not ok then break end
            -- «Баффы кончились» - это настоящий nil. Сравнение с nil тоже идёт
            -- под защитой: упало - значит имя есть, но секретное.
            local okN, none = pcall(rawequal, name, nil)
            if okN and none then break end
            name = plain(plainString, name)
            spellID = plain(plainNumber, spellID)
            if name or spellID then
                out[#out + 1] = {
                    name = name, spellID = spellID,
                    expires = plain(plainNumber, expires),
                    stacks = plain(plainNumber, count),
                }
            end
        end
        return out, "UnitBuff"
    end
    return out, nil
end

-- ЧТО ИМЕННО НАЛОЖЕНО НА ВЕЩЬ - СЛОВАМИ, ЕСЛИ ИГРА ИХ ОТДАЁТ.
--
-- От наложенных чар в ссылке предмета есть только номер, и по номеру сказать,
-- что они дают, нечем. Но подсказка предмета эту строку показывает, и на
-- современном клиенте подсказку можно прочитать данными (C_TooltipInfo), где у
-- строки чар есть свой тип. Берётся только такая строка, по типу: угадывать её
-- по цвету или по месту в подсказке значило бы выдавать чужую строку за чары.
-- Нет функции или типа - nil, и на экране остаётся номер, как раньше.
--
-- Ответ помнится на пару «предмет + номер чар»: пока они те же, текст тот же.
--
-- «Не нашёл» помнится недолго (ENCHANT_TEXT_RETRY секунд): сразу после входа
-- подсказка бывает неполной, и запомнить этот ответ навсегда значило бы
-- остаться с номером до конца сеанса. А спрашивать каждый проход незачем.
function Api.EnchantLineOf(getTooltip, invID, kind)
    local data = getTooltip("player", invID)
    if type(data) ~= "table" or type(data.lines) ~= "table" then return nil end
    for _, line in ipairs(data.lines) do
        if type(line) == "table" and line.type == kind
           and type(line.leftText) == "string" and line.leftText ~= "" then
            -- Цветовые коды клиента из текста убираются: это разметка.
            local clean = line.leftText:gsub("|c%x%x%x%x%x%x%x%x", "")
            clean = clean:gsub("|r", "")
            return clean
        end
    end
    return nil
end
local enchantTextMemo, enchantTextMissAt = {}, {}
Api.ENCHANT_TEXT_RETRY = 60
Api.enchantTextPath = nil   -- true/false после первой попытки; nil - не пробовали
function Api:InventoryEnchantText(invID, itemID, enchantID)
    local key = tostring(itemID) .. ":" .. tostring(enchantID)
    local memo = enchantTextMemo[key]
    if memo ~= nil then return memo end
    local TI = _G.C_TooltipInfo
    local kinds = _G.Enum and _G.Enum.TooltipDataLineType
    local kind = type(kinds) == "table" and kinds.ItemEnchantmentPermanent or nil
    if type(TI) ~= "table" or type(TI.GetInventoryItem) ~= "function" or not kind then
        Api.enchantTextPath = false
        return nil
    end
    Api.enchantTextPath = true
    local now = Api:Now()
    local missed = enchantTextMissAt[key]
    if missed and (now - missed) < Api.ENCHANT_TEXT_RETRY then return nil end
    -- Весь разбор - в защищённом вызове: что бы ни лежало в подсказке, наружу
    -- выходит строка или nil.
    local ok, text = pcall(Api.EnchantLineOf, TI.GetInventoryItem, invID, kind)
    if not ok or type(text) ~= "string" or text == "" then text = nil end
    if text then
        enchantTextMemo[key] = text
        enchantTextMissAt[key] = nil
    else
        enchantTextMissAt[key] = now
    end
    return text
end

function Api:Equipped()
    if not Api.has.invItemLink then
        if ns.Diag then
            ns.Diag:Call("GetInventoryItemLink", nil, "функции нет на этом клиенте")
        end
        return {}, CONF.UNKNOWN
    end
    local out = {}
    local function readSlot(key, invID)
        local link = F.invItemLink("player", invID)
        if not link then return end
        out[key] = {
            slot = key, invID = invID, link = link,
            itemID = U.itemIDFromLink(link),
            enchantID = U.enchantIDFromLink(link),
        }
        -- Текст чар - только там, где чары есть, и только если игра его отдаёт.
        if out[key].enchantID then
            out[key].enchantText = Api:InventoryEnchantText(invID,
                out[key].itemID, out[key].enchantID)
        end
    end
    for key, invID in pairs(ns.SLOT_INVENTORY_ID) do readSlot(key, invID) end
    for key, ids in pairs(ns.SLOT_INVENTORY_PAIRS) do
        for i, invID in ipairs(ids) do readSlot(key .. i, invID) end
    end
    if ns.Diag then
        local enchanted = 0
        for _, e in pairs(out) do if e.enchantID then enchanted = enchanted + 1 end end
        ns.Diag:Call("GetInventoryItemLink", U.count(out) > 0,
            string.format("слотов занято %d, из них с чарами %d",
                U.count(out), enchanted))
        -- Отдаёт ли клиент слова чар: по этой строке в файле диагностики видно,
        -- есть ли на этом клиенте читаемая подсказка, и сколько строк нашлось.
        if enchanted > 0 then
            local worded = 0
            for _, e in pairs(out) do if e.enchantText then worded = worded + 1 end end
            -- true - слова есть, false - функция есть, но строк не нашла,
            -- nil - функции нет вовсе.
            local got = nil
            if Api.enchantTextPath == true then got = (worded > 0) end
            ns.Diag:Call("C_TooltipInfo.GetInventoryItem", got,
                (Api.enchantTextPath == false)
                    and "функции или типа строки чар на этом клиенте нет — остаются номера"
                    or string.format("слова чар прочитаны у %d из %d", worded, enchanted))
        end
    end
    return out, CONF.EXACT
end

-- Auctionator ------------------------------------------------------------
-- Only GetAuctionPriceByItemID / GetAuctionPriceByItemLink / MultiSearch are
-- declared stable by Auctionator's own README. Those three are called directly.
-- Everything else goes through pcall + an existence check and has a fallback.

local AUCTIONATOR_CALLER = "ForeverPilot"

function Api:AuctionatorPresent()
    local A = _G.Auctionator
    return (A and A.API and A.API.v1 and type(A.API.v1.GetAuctionPriceByItemID) == "function") and true or false
end

-- ОДИН ВОПРОС ПРО ОДИН ПРЕДМЕТ - ОДИН РАЗ, ПОКА ОТВЕТ НЕ МОГ ИЗМЕНИТЬСЯ.
--
-- В живом файле игрока: 73008 обращений к Auctionator за 216 пересчётов, то
-- есть 338 за пересчёт, и ветка «на продажу» стоила 15.8 мс. Спрашивали по три
-- раза об одном и том же предмете: отдельно для покупки, отдельно для продажи,
-- отдельно из списка покупок, и каждая ветка помнила ответ только у себя. Память
-- живёт до того момента, когда ответ МОЖЕТ стать другим. База Auctionator
-- меняется только когда Auctionator сканирует аукцион, а это видно по нашим же
-- событиям AUCTION_HOUSE_SHOW/CLOSED - тогда кеш сбрасывается. Плюс страховка
-- по времени: даже без событий ответы живут не дольше AUCTION_CACHE_SECONDS.
-- Возраст самих данных мы не выдумываем - его отдаёт Auctionator, и он от
-- нашего кеша не зависит.
Api.auctionPassCache = {}
Api.auctionCacheAt = nil
-- Когда память забывали последний раз и не осталось ли отложенного забывания.
Api.auctionClearedAt = nil
Api.auctionClearPending = nil

-- Забыть ответы Auctionator. `guard` - «это обычный сигнал аукциона, а не
-- прямое требование»: такие забывания проходят не чаще, чем раз в
-- ns.AUCTION_RESCAN_GUARD (см. комментарий там же, в Core/Const.lua).
-- Отложенное не теряется: Api:BeginPass выполнит его, как только окно истечёт.
function Api:ClearAuctionCache(why, guard)
    local now = Api:Now()
    if guard and Api.auctionClearedAt
        and (now - Api.auctionClearedAt) < (ns.AUCTION_RESCAN_GUARD or 60) then
        -- НЕ МОЛЧА: отложенное забывание названо и посчитано, иначе «цены не
        -- обновились» было бы нечем объяснить.
        Api.auctionClearPending = why or true
        if ns.Diag then
            ns.Diag:Count("auction.cacheClearDeferred")
            ns.Diag:Call("Auctionator: сброс памяти цен", nil,
                "сигналов аукциона много, а сканирование одно: забывание отложено"
                .. " (" .. tostring(why or "без причины") .. ")")
        end
        return 0
    end
    local n = 0
    for _ in pairs(Api.auctionPassCache) do n = n + 1 end
    Api.auctionPassCache = {}
    Api.auctionCacheAt = nil
    Api.auctionClearedAt = now
    Api.auctionClearPending = nil
    if ns.Diag and n > 0 then
        ns.Diag:Count("auction.cacheCleared")
        ns.Diag:Call("Auctionator: сброс памяти цен", true,
            (why or "причина не указана") .. ", забыто записей: " .. n)
    end
    return n
end

function Api:AuctionPrice(itemID, itemLink)
    local key = itemLink or itemID
    if key ~= nil then
        local hit = Api.auctionPassCache[key]
        if hit then
            Api.auctionCacheHits = (Api.auctionCacheHits or 0) + 1
            return hit[1], hit[2], hit[3], hit[4], hit[5]
        end
    end
    local price, conf, age, exact, ageDays = Api:ReadAuctionPrice(itemID, itemLink)
    if key ~= nil then
        Api.auctionPassCache[key] = { price, conf, age, exact, ageDays }
    end
    return price, conf, age, exact, ageDays
end

function Api:ReadAuctionPrice(itemID, itemLink)
    if not Api:AuctionatorPresent() then
        if ns.Diag then
            ns.Diag:Call("Auctionator.API.v1.GetAuctionPriceByItemID", nil,
                "Auctionator не загружен")
        end
        return nil, CONF.UNKNOWN
    end
    local v1 = _G.Auctionator.API.v1
    -- stable API: called directly, exactly as the README documents it
    local price
    if itemLink and type(v1.GetAuctionPriceByItemLink) == "function" then
        price = v1.GetAuctionPriceByItemLink(AUCTIONATOR_CALLER, itemLink)
    end
    if not price then
        price = v1.GetAuctionPriceByItemID(AUCTIONATOR_CALLER, itemID)
    end
    if type(price) ~= "number" or price <= 0 then
        if ns.Diag then
            ns.Diag:Call("Auctionator.API.v1.GetAuctionPriceByItemID", false,
                "функция есть, но цены по этому предмету нет")
        end
        return nil, CONF.UNKNOWN
    end
    if ns.Diag then ns.Diag:Call("Auctionator.API.v1.GetAuctionPriceByItemID", true) end

    -- Everything below is explicitly "may break without warning": pcall only.
    --
    -- ВОЗРАСТ ПРИХОДИТ В ДНЯХ, А НЕ В СЕКУНДАХ, И ЭТО СТОИЛО ВРАНЬЯ НА ЭКРАНЕ.
    --
    -- Auctionator про свою функцию пишет прямо: "Returns the number of days
    -- since the item was seen in the auction house" - и внутри у него
    -- GetScanDay() минус последний день наблюдения. Здесь это число принимали за
    -- секунды. Последствия: цена двухдневной давности печаталась как «2 минуты
    -- назад» (U.ageText(2)), а устаревшей не считалась НИКОГДА - порог 172800
    -- против числа вроде 2. То есть обещание «цены старше суток помечаются» не
    -- выполнялось вообще, при том что сам механизм пометки работал.
    --
    -- Переводим на границе адаптера: выше по стеку возраст везде в секундах.
    -- Гранулярность при этом суточная, и тексту об этом знать полезно -
    -- поэтому отдаём ещё и ageDays.
    local age, exact, ageDays
    if type(v1.GetAuctionAgeByItemID) == "function" then
        local ok, a = pcall(v1.GetAuctionAgeByItemID, AUCTIONATOR_CALLER, itemID)
        if ok and type(a) == "number" and a >= 0 then
            ageDays = a
            age = a * 86400
        end
        if ns.Diag then
            ns.Diag:Call("Auctionator.API.v1.GetAuctionAgeByItemID (нестабильная)",
                age ~= nil, "возраст приходит в днях, перевожу в секунды")
        end
    elseif ns.Diag then
        ns.Diag:Call("Auctionator.API.v1.GetAuctionAgeByItemID (нестабильная)", nil,
            "функции нет — возраст цены неизвестен")
    end
    if type(v1.IsAuctionDataExactByItemID) == "function" then
        local ok, e = pcall(v1.IsAuctionDataExactByItemID, AUCTIONATOR_CALLER, itemID)
        if ok then exact = e and true or false end
        if ns.Diag then
            ns.Diag:Call("Auctionator.API.v1.IsAuctionDataExactByItemID (нестабильная)",
                exact ~= nil)
        end
    elseif ns.Diag then
        ns.Diag:Call("Auctionator.API.v1.IsAuctionDataExactByItemID (нестабильная)", nil,
            "функции нет")
    end

    local conf = CONF.CACHED
    if exact == true and age and age < ns.PRICE_FRESH_SECONDS then conf = CONF.EXACT end
    -- >= , а не > : возраст приходит кратным суткам, и ровно двое суток - это
    -- уже «старая цена», а не граница, которую надо перешагнуть.
    if age and age >= ns.PRICE_STALE_SECONDS then conf = CONF.ESTIMATE end
    return price, conf, age, exact, ageDays
end

-- Unstable API with our own fallback: the item's own sell price times a markup
-- is a far worse answer, so the caller is told it is only an ESTIMATE.
function Api:VendorPrice(itemID)
    if Api:AuctionatorPresent() then
        local v1 = _G.Auctionator.API.v1
        if type(v1.GetVendorPriceByItemID) == "function" then
            local ok, p = pcall(v1.GetVendorPriceByItemID, AUCTIONATOR_CALLER, itemID)
            if ok and type(p) == "number" and p > 0 then return p, CONF.CACHED end
        end
    end
    return nil, CONF.UNKNOWN
end

-- Залог за выставление лота, если КЛИЕНТ умеет его считать.
--
-- CalculateAuctionDeposit существует в классических клиентах, но считает залог
-- для предмета, УЖЕ положенного в слот продажи - то есть вне окна аукциона она
-- либо отсутствует, либо возвращает ноль. Поэтому здесь только честная попытка:
-- функция есть и ответила положительным числом - берём её число; нет - ответа
-- нет, и Logic/Risk.lua считает свою оценку и помечает её оценкой.
-- Ничего не выставляется и не покупается: это чтение числа.
function Api:AuctionDeposit(itemID, days)
    local fn = _G.CalculateAuctionDeposit
    local present = type(fn) == "function"
    if ns.Diag then
        ns.Diag:Detect("CalculateAuctionDeposit", present)
    end
    if not present then return nil end
    local runTime = (tonumber(days) or 1) * 24 * 60   -- минуты, как у клиента
    local ok, copper = pcall(fn, runTime)
    if ok and type(copper) == "number" and copper > 0 then
        if ns.Diag then
            ns.Diag:Call("CalculateAuctionDeposit", true,
                "клиент посчитал залог сам")
        end
        return copper
    end
    if ns.Diag then
        ns.Diag:Call("CalculateAuctionDeposit", false,
            "функция есть, но вне окна аукциона залог не считается")
    end
    return nil
end

function Api:DisenchantPrice(itemID)
    if Api:AuctionatorPresent() then
        local v1 = _G.Auctionator.API.v1
        if type(v1.GetDisenchantPriceByItemID) == "function" then
            local ok, p = pcall(v1.GetDisenchantPriceByItemID, AUCTIONATOR_CALLER, itemID)
            if ok and type(p) == "number" and p > 0 then return p, CONF.ESTIMATE end
        end
    end
    return nil, CONF.UNKNOWN
end

-- ПЕРЕДАЧА СПИСКА ПОКУПОК В ПОИСК AUCTIONATOR ---------------------------
--
-- Сверено с исходником установленного Auctionator (версия 347,
-- Source/API/v1/MultiSearch.lua), а не написано по памяти:
--
--   * MultiSearchAdvanced(caller, { { searchString, isExact, quantity } })
--     - поиск с точным именем и нужным количеством. Запись может содержать
--     только строки, числа и булевы значения; строка не должна содержать «;»
--     и «^» и не должна быть целиком в кавычках - иначе Auctionator бросает
--     ошибку.
--   * MultiSearchExact(caller, { "имя", ... }) и MultiSearch(caller, {...})
--     - то же с обычными именами, без количества.
--   * Все три требуют ОТКРЫТОГО окна аукциона (AuctionHouseFrame или
--     AuctionFrame) и первым делом щёлкают по вкладке покупок
--     AuctionatorTabs_Shopping. Нет окна или вкладки - Auctionator бросает
--     ошибку.
--
-- В игре это проверить нельзя, поэтому каждое условие проверяется ЗДЕСЬ, до
-- вызова, а сам вызов идёт под pcall. Что из условий не выполнено, решает
-- Logic/ShoppingList: по этому там показывается или не показывается кнопка.

-- Какая функция поиска списком есть у установленного Auctionator. Лучшее из
-- того, что на месте: с количеством, затем точная, затем простая. nil - когда
-- нет ни одной (или нет самого Auctionator).
function Api:AuctionatorSearchRoute()
    if not Api:AuctionatorPresent() then return nil end
    -- Таблица берётся по шагам: «Auctionator есть» ещё не значит, что в нём
    -- есть всё остальное, а упасть в проверке наличия - худшее из возможного.
    local A = _G.Auctionator
    local v1 = type(A) == "table" and type(A.API) == "table" and A.API.v1 or nil
    if type(v1) ~= "table" then return nil end
    for _, name in ipairs({ "MultiSearchAdvanced", "MultiSearchExact", "MultiSearch" }) do
        if type(v1[name]) == "function" then return name, v1[name] end
    end
    return nil
end

-- Открыто ли окно аукциона. Проверяются оба окна - нового и старого образца, -
-- ровно как это делает сам Auctionator перед поиском.
function Api:AuctionHouseOpen()
    for _, name in ipairs({ "AuctionHouseFrame", "AuctionFrame" }) do
        local frame = _G[name]
        if type(frame) == "table" and type(frame.IsShown) == "function" then
            local ok, shown = pcall(frame.IsShown, frame)
            if ok and shown then return true end
        end
    end
    return false
end

-- Есть ли вкладка покупок Auctionator. Она создаётся, когда Auctionator
-- достраивает окно аукциона; поиск начинается с щелчка по ней.
function Api:AuctionatorShoppingTab()
    local tab = _G.AuctionatorTabs_Shopping
    return (type(tab) == "table" and type(tab.Click) == "function") and true or false
end

-- Годится ли имя для поиска: Auctionator отвергает «;», «^» и строку, целиком
-- взятую в кавычки.
function Api:AuctionatorNameOk(name)
    if type(name) ~= "string" or name == "" then return false end
    if name:find(";", 1, true) or name:find("^", 1, true) then return false end
    if name:find('^%s*".*"%s*$') then return false end
    return true
end

-- Запустить поиск. items = { { name = "...", qty = n }, ... }.
-- Возвращает true, имя функции, число позиций - или false, причину, подробность:
--   "combat" | "no-api" | "closed" | "no-tab" | "empty" | "error"
-- Ничего не покупает и не выставляет: открывает вкладку покупок Auctionator и
-- запускает в ней поиск - дальше игрок действует сам.
function Api:AuctionatorSearchItems(items)
    if Api:InCombat() then return false, "combat" end
    local route, fn = Api:AuctionatorSearchRoute()
    if not route then return false, "no-api" end
    if not Api:AuctionHouseOpen() then return false, "closed" end
    if not Api:AuctionatorShoppingTab() then return false, "no-tab" end

    local terms = {}
    for _, item in ipairs(items or {}) do
        if type(item) == "table" and Api:AuctionatorNameOk(item.name) then
            if route == "MultiSearchAdvanced" then
                local term = { searchString = item.name, isExact = true }
                local qty = tonumber(item.qty)
                if qty and qty > 0 then term.quantity = math.floor(qty) end
                terms[#terms + 1] = term
            else
                terms[#terms + 1] = item.name
            end
        end
    end
    if #terms == 0 then return false, "empty" end

    local ok, err = pcall(fn, AUCTIONATOR_CALLER, terms)
    if ns.Diag then
        ns.Diag:Call("Auctionator.API.v1." .. route, ok,
            ok and ("позиций передано в поиск: " .. #terms) or tostring(err))
    end
    if not ok then return false, "error", tostring(err) end
    return true, route, #terms
end

-- Syndicator -------------------------------------------------------------
-- Optional. Gives us the other characters' bags and bank without logging in.

function Api:SyndicatorPresent()
    local S = _G.Syndicator
    return (S and S.API and type(S.API.GetAllCharacters) == "function") and true or false
end

function Api:SyndicatorInventory(itemID)
    if not Api:SyndicatorPresent() then return nil, CONF.UNKNOWN end
    local S = _G.Syndicator
    if type(S.API.GetInventoryInfoByItemID) ~= "function" then return nil, CONF.UNKNOWN end
    local ok, info = pcall(S.API.GetInventoryInfoByItemID, itemID, true, true)
    if not ok or type(info) ~= "table" then return nil, CONF.UNKNOWN end
    return info, CONF.CACHED
end

function Api:SyndicatorCharacters()
    if not Api:SyndicatorPresent() then return nil end
    local ok, list = pcall(_G.Syndicator.API.GetAllCharacters)
    if not ok or type(list) ~= "table" then return nil end
    return list
end

function Api:SyndicatorCharacter(fullName)
    if not Api:SyndicatorPresent() then return nil end
    local get = _G.Syndicator.API.GetCharacter or _G.Syndicator.API.GetByCharacterFullName
    if type(get) ~= "function" then return nil end
    local ok, data = pcall(get, fullName)
    if not ok then return nil end
    return data
end

-- Foreign item database --------------------------------------------------
--
-- WHY THIS EXISTS. On this client C_Item.GetItemStats reports the BASE stats of
-- an item - stamina, intellect, spirit, armour - and nothing else. Equip
-- bonuses are not in it: spell damage, healing, and above all the per-school
-- spell damage that this patch's armour families are built around. The worn
-- "Жемчужный венец" is sta10 armor35 spArcane11, and the client told us only
-- the first two. The addon therefore scored it as a scrap of cloth and advised
-- crafting a downgrade, which the player then did.
--
-- Polestar ships a generated item database (Polestar_ItemDB, load-on-demand)
-- and exposes it as a documented public API on its own global. We call that API
-- at runtime; nothing is copied, and every entry point is feature-detected,
-- because the addon has to keep working when it is not installed.
--
--   Polestar.ItemDB.Get(itemID) -> { id, inv, ilvl, req, quality, class,
--                                    subclass, allow, unique, stats = {...} }
--   Polestar.ItemDB.IsLoaded() / .Load()
--   Polestar.ItemDB.Sources(itemID) -> { { kind = "craft"|"quest"|"drop", ... } }
--   Polestar.ItemDB.ItemName(itemID)
--
-- Load() parses a few hundred kilobytes, so it is called once, never in
-- combat, and never from inside a rebuild loop: Api:ItemDBReady does that and
-- the readers simply return nil until it answers.

function Api:ItemDB()
    local P = _G.Polestar
    local db = type(P) == "table" and P.ItemDB or nil
    if type(db) ~= "table" or type(db.Get) ~= "function" then return nil end
    return db
end

function Api:ItemDBPresent()
    return Api:ItemDB() ~= nil
end

-- "ready" | "loading" | "absent". The three states mean three different things
-- to the gear advice, and the card text has to say which one it is: absent
-- means it will never be able to compare school damage, loading means the next
-- rebuild will.
function Api:ItemDBState()
    if not Api:ItemDBPresent() then return "absent" end
    if Api:ItemDBReady() then return "ready" end
    return "loading"
end

-- True once the data is in memory. Asks for the load at most once per session,
-- and not while the player is fighting.
function Api:ItemDBReady()
    local db = Api:ItemDB()
    if not db then
        if ns.Diag and not Api.itemDBReported then
            Api.itemDBReported = true
            ns.Diag:Call("Polestar.ItemDB.Get", nil,
                "внешней базы предметов нет — бонусы экипировки читать нечем,"
                .. " сравнение вещей не будет точным")
        end
        return false
    end
    if type(db.IsLoaded) == "function" then
        local ok, loaded = pcall(db.IsLoaded)
        if ok and loaded then return true end
    end
    if Api.itemDBLoadTried then return false end
    if Api:InCombat() then return false end
    Api.itemDBLoadTried = true
    if type(db.Load) == "function" then
        local ok, loaded = pcall(db.Load)
        if ns.Diag then
            ns.Diag:Call("Polestar.ItemDB.Load", (ok and loaded) and true or false,
                (ok and loaded) and "внешняя база предметов загружена"
                    or "загрузить внешнюю базу предметов не удалось")
        end
        return (ok and loaded) and true or false
    end
    return false
end

-- The foreign database's own stat table for an item, in ITS vocabulary
-- (sta/int/armor/sp/heal/spArcane/...). StatWeights maps it onto ours.
-- Returns stats, record, reason where reason explains a nil:
--   "no-db"     - the database addon is not installed
--   "loading"   - installed, not in memory yet; the next pass will have it
--   "not-in-db" - the database is there and simply has no row for this item
-- The three are different facts and the old code reported all of them as
-- "внешней базы предметов нет", which was false whenever the database was
-- working for every other item on screen.
--
-- Cached across rebuilds: the rows are generated data and do not change while
-- the player plays. Only hits are cached; a miss is retried, because a
-- "loading" miss turns into a hit a moment later.
Api.foreignStatsCache = {}

function Api:ClearForeignItemCache()
    Api.foreignStatsCache = {}
    Api.foreignMissCache = {}
end

function Api:ForeignItemStats(itemID)
    itemID = tonumber(itemID)
    if not itemID then return nil, nil, "no-id" end

    local cached = Api.foreignStatsCache[itemID]
    if cached then
        Api.foreignCacheHits = (Api.foreignCacheHits or 0) + 1
        return cached.stats, cached.rec, nil
    end
    -- ОТРИЦАТЕЛЬНЫЙ ОТВЕТ ТОЖЕ ОТВЕТ, пока база не менялась. Внешняя база -
    -- статическая таблица: если строки по предмету в ней нет, то до конца сессии
    -- и не будет. Непомнящий отказ стоил 113 обращений за пересчёт в живом файле
    -- игрока (24426 на 216 пересчётов). Отрицательные ответы запоминаются только
    -- когда база ЗАГРУЖЕНА: пока она грузится, «нет» ещё ничего не значит, и
    -- сброс кеша (ClearForeignItemCache) стирает их вместе с остальными.
    Api.foreignMissCache = Api.foreignMissCache or {}
    local missed = Api.foreignMissCache[itemID]
    if missed then
        Api.foreignCacheHits = (Api.foreignCacheHits or 0) + 1
        return nil, missed.rec, missed.why
    end
    Api.itemDBReads = (Api.itemDBReads or 0) + 1

    if not Api:ItemDBPresent() then
        if ns.Diag then ns.Diag:Count("itemDB.absent") end
        return nil, nil, "no-db"
    end
    if not Api:ItemDBReady() then
        if ns.Diag then ns.Diag:Count("itemDB.loading") end
        return nil, nil, "loading"
    end
    local db = Api:ItemDB()
    local ok, rec = pcall(db.Get, itemID)
    if not ok or type(rec) ~= "table" then
        if ns.Diag then ns.Diag:Count("itemDB.notInDB") end
        Api.foreignMissCache[itemID] = { why = "not-in-db" }
        return nil, nil, "not-in-db"
    end
    if type(rec.stats) ~= "table" or next(rec.stats) == nil then
        if ns.Diag then ns.Diag:Count("itemDB.noStats") end
        Api.foreignMissCache[itemID] = { why = "no-stats", rec = rec }
        return nil, rec, "no-stats"
    end
    if ns.Diag then ns.Diag:Count("itemDB.hit") end
    Api.foreignStatsCache[itemID] = { stats = rec.stats, rec = rec }
    return rec.stats, rec, nil
end

-- What KIND of item the external database says this is: item class, subclass
-- and numeric inventory type, plus the required level and quality it carries.
--
-- The client is the first source for all of this and stays that way; this is
-- the fallback for an item the client has not cached - a bank item, mostly,
-- since bank contents are remembered from the last visit while the item data
-- is not. Without it the addon cannot even tell whether such an item is a
-- weapon, and "I do not know what this is" turned into "the slot is empty".
-- Returns classID, subclassID, inv, reqLevel, quality - any of them may be nil.
function Api:ForeignItemClass(itemID)
    itemID = tonumber(itemID)
    if not itemID then return nil end
    local _, rec = Api:ForeignItemStats(itemID)
    if type(rec) ~= "table" then return nil end
    return tonumber(rec.class), tonumber(rec.subclass), tonumber(rec.inv),
           tonumber(rec.req), tonumber(rec.quality)
end

-- Сколько строк во внешней базе предметов. Нужно одной вещи - показать, что
-- база не просто «установлена», а действительно загружена и велика: установлена
-- и не загружена выглядит на экране точно так же, как отсутствует.
-- Количество спрашивается у самой базы, если она умеет его сказать; выдумывать
-- число нельзя, поэтому «не умеет» - это nil, а не ноль.
function Api:ItemDBCount()
    local db = Api:ItemDB()
    if not db then return nil end
    for _, name in ipairs({ "Count", "Size", "ItemCount" }) do
        if type(db[name]) == "function" then
            local ok, n = pcall(db[name])
            if ok and type(n) == "number" and n > 0 then return n end
        end
    end
    local n = tonumber(db.count) or tonumber(db.rows)
    if n and n > 0 then return n end
    return nil
end

-- Polestar.Codex -----------------------------------------------------------
--
-- ОТКУДА БЕРУТСЯ ТОРГОВЦЫ И ИХ КООРДИНАТЫ. Codex - вторая публичная база
-- Polestar (пакет Polestar_Codex, тоже load-on-demand), и в ней лежит то, чего
-- нет ни в клиенте, ни в ItemDB: у предмета - список источников, у NPC -
-- координаты точек появления.
--
--   Codex.Item(id).sources -> { { type = "vendor", npc, cost, limited }, ... }
--   Codex.Npc(id)          -> { name, subName, faction, roles, spawns = {
--                                { map, x, y, f, z }, ... } }
--   Codex.WithRole("vendor") / ("trainer:197")
--   Codex.IsLoaded() / Codex.Load()
--
-- ЧЕГО В НЕЙ НЕТ, и это важно для советов про торговцев: поле `limited`
-- («осталось N штук») в поставляемом пакете не заполнено ни у одной из 7219
-- записей о торговцах, а у 210 записей нет самой цены. Поэтому «постоянный это
-- товар или штучный» из Codex НЕ выводится, и советы обязаны говорить, что
-- наличие не проверялось - см. Logic/VendorArbitrage.lua.
--
-- Всё через feature-detect: Codex может быть не установлен, и это нормально.

function Api:Codex()
    local P = _G.Polestar
    local C = type(P) == "table" and P.Codex or nil
    if type(C) ~= "table" or type(C.Item) ~= "function" then return nil end
    return C
end

function Api:CodexPresent()
    return Api:Codex() ~= nil
end

-- Как и у ItemDB: загрузка парсит сотни килобайт, поэтому просим один раз за
-- сессию и никогда в бою.
function Api:CodexReady()
    local C = Api:Codex()
    if not C then
        if ns.Diag and not Api.codexReported then
            Api.codexReported = true
            ns.Diag:Call("Polestar.Codex.Item", nil,
                "Codex не установлен — где что продаётся и где стоят торговцы,"
                .. " я знаю только из своих записей и из QuestieDB")
        end
        return false
    end
    if type(C.IsLoaded) == "function" then
        local ok, loaded = pcall(C.IsLoaded)
        if ok and loaded then return true end
    end
    if Api.codexLoadTried then return false end
    if Api:InCombat() then return false end
    Api.codexLoadTried = true
    if type(C.Load) == "function" then
        local ok, loaded = pcall(C.Load)
        if ns.Diag then
            ns.Diag:Call("Polestar.Codex.Load", (ok and loaded) and true or false,
                ok and "пакет Codex запрошен" or "загрузка Codex не удалась")
        end
        return (ok and loaded) and true or false
    end
    return false
end

-- ОТВЕТЫ CODEX КЕШИРУЮТСЯ У НАС, И ЭТО НЕ МИКРООПТИМИЗАЦИЯ.
--
-- Живой прогон этапов 2 и 3: средний пересчёт 71.1 мс вместо прежних 9, и 87 из
-- них - ветка перепродажи. Измерение на настоящих данных игрока показало
-- ПОЧЕМУ: 457 обращений к Codex за каждый пересчёт, и так на каждом из
-- пятидесяти.
--
-- Одно обращение в игре стоит дорого: двоичный поиск по блобу (у предметов это
-- шесть групп суммарно почти на три мегабайта), разбор записи и обращение к
-- кешу имён предметов клиента. Свои разобранные записи Codex держит СЛАБЫМИ
-- ссылками - между пересчётами их забирает сборщик мусора, и всё повторяется.
--
-- Источники предмета и места появления NPC за игровую сессию не меняются:
-- данные лежат в файлах пакета. Поэтому ответ запоминается у нас - в обычной
-- таблице, которую сборщик мусора не тронет, - и второй раз за ним никто не
-- идёт. Отрицательный ответ («такого предмета в пакете нет») запоминается
-- тоже: он самый дорогой, потому что для него перебираются ВСЕ группы.
Api.codexItemCache = {}
Api.codexNpcCache = {}
Api.codexItemCached = 0
Api.codexNpcCached = 0
Api.codexReads = 0
Api.codexHits = 0
-- Память не бесконечная, и расти без предела она не должна. Круг поиска у
-- ветки перепродажи - 400 предметов, у мест и тренеров - сотни; четыре тысячи
-- записей покрывают это с запасом, а если кто-то когда-нибудь попросит больше,
-- кеш сбросится и об этом будет запись в файле, а не тихий рост.
Api.CODEX_CACHE_MAX = 4000

function Api:ClearCodexCache(why)
    local n = Api.codexItemCached + Api.codexNpcCached
    Api.codexItemCache, Api.codexNpcCache = {}, {}
    Api.codexItemCached, Api.codexNpcCached = 0, 0
    if ns.Diag and n > 0 then
        ns.Diag:Count("codex.cacheCleared")
        ns.Diag:Log("кеш ответов Codex сброшен", { entries = n, why = why })
    end
    return n
end

-- Не дать кешу разрастись. Считается по счётчикам, а не обходом таблицы:
-- обход на каждом пересчёте стоил бы ровно того, от чего кеш избавляет.
local function codexCacheRoom()
    if (Api.codexItemCached + Api.codexNpcCached) >= Api.CODEX_CACHE_MAX then
        Api:ClearCodexCache("записей больше " .. Api.CODEX_CACHE_MAX)
    end
end

-- Источники предмета по Codex, как есть. Возвращает список или nil.
function Api:CodexItemSources(itemID)
    itemID = tonumber(itemID)
    if not itemID then return nil end
    local hit = Api.codexItemCache[itemID]
    if hit ~= nil then
        Api.codexHits = Api.codexHits + 1
        if hit == false then return nil end
        return hit.sources, hit
    end
    if not Api:CodexReady() then return nil end
    local C = Api:Codex()
    Api.codexReads = Api.codexReads + 1
    local ok, rec = pcall(C.Item, itemID)
    codexCacheRoom()
    Api.codexItemCached = Api.codexItemCached + 1
    if not ok or type(rec) ~= "table" then
        if ns.Diag then ns.Diag:Count("codex.itemMiss") end
        Api.codexItemCache[itemID] = false
        return nil
    end
    -- Запись есть, источников в ней может не быть. Запоминаем саму запись:
    -- второй раз её разбирать незачем, а вернуть надо то же самое.
    Api.codexItemCache[itemID] = rec
    -- ЗАПИСЬ ОТДАЁТСЯ И БЕЗ ИСТОЧНИКОВ. Здесь стоял `return nil` одним
    -- значением, и тогда у предмета без источников пропадала сама запись - хотя
    -- в ней есть имя и качество, а повторный вызов (из кеша) её же и возвращал
    -- вторым значением. Два разных ответа на один вопрос в зависимости от того,
    -- первый это вызов или второй.
    if type(rec.sources) ~= "table" then return nil, rec end
    return rec.sources, rec
end

-- ИМЯ ПРЕДМЕТА, КОТОРОГО ИГРОК В РУКАХ НЕ ДЕРЖАЛ.
--
-- Клиент знает имя только того, что видел: про предмет, которого не было ни в
-- сумках, ни в подсказке, C_Item.GetItemInfo молчит, и карточка про него
-- называться не может («Предмет #279967» - не совет). Для экипировки это
-- неважно (её берут из своих рецептов, то есть из того, что клиент уже
-- назвал), а для предметов лагеря - важно: их игрок как раз и не видел.
--
-- Codex отдаёт имя на языке клиента, когда пакет имён установлен, и английское
-- из своего пакета, когда нет (Polestar/Lookup/Codex.lua, Codex.Name -> shown).
-- Ответ уже кеширован вместе с записью предмета, так что второго обращения к
-- пакету это не стоит.
function Api:CodexItemName(itemID)
    itemID = tonumber(itemID)
    if not itemID then return nil end
    local _, rec = Api:CodexItemSources(itemID)
    if type(rec) ~= "table" then return nil end
    local name = rec.name
    if type(name) ~= "string" or name == "" then return nil end
    return name
end

-- NPC по Codex: имя, подпись, фракция и точки появления.
function Api:CodexNpc(npcID)
    npcID = tonumber(npcID)
    if not npcID then return nil end
    local hit = Api.codexNpcCache[npcID]
    if hit ~= nil then
        Api.codexHits = Api.codexHits + 1
        if hit == false then return nil end
        return hit
    end
    if not Api:CodexReady() then return nil end
    local C = Api:Codex()
    if type(C.Npc) ~= "function" then return nil end
    Api.codexReads = Api.codexReads + 1
    local ok, rec = pcall(C.Npc, npcID)
    codexCacheRoom()
    Api.codexNpcCached = Api.codexNpcCached + 1
    if not ok or type(rec) ~= "table" then
        if ns.Diag then ns.Diag:Count("codex.npcMiss") end
        Api.codexNpcCache[npcID] = false
        return nil
    end
    Api.codexNpcCache[npcID] = rec
    return rec
end

-- Первая точка появления NPC: uiMapID, x, y (в долях 0..1), имя карты если есть.
-- Координаты в Codex хранятся в десятых долях процента, поэтому делятся на 100.
function Api:CodexNpcSpawn(npcID)
    local rec = Api:CodexNpc(npcID)
    local spawns = rec and rec.spawns
    if type(spawns) ~= "table" or #spawns == 0 then
        if ns.Diag then
            ns.Diag:Want("npcNoCoords", npcID, "codex",
                { name = rec and rec.name or nil })
        end
        return nil
    end
    local s = spawns[1]
    local x, y = tonumber(s.x), tonumber(s.y)
    if not (x and y) then return nil end
    -- Codex отдаёт проценты (0..100); наши координаты - доли.
    if x > 1 or y > 1 then x, y = x / 100, y / 100 end
    if x <= 0 or y <= 0 or x > 1 or y > 1 then return nil end
    return tonumber(s.map), x, y, rec.name, rec
end

-- NPC-ы с нужной ролью по Codex: "vendor", "trainer:197" (по skillLineID),
-- "class:MAGE". Возвращает список npcID или nil.
function Api:CodexWithRole(role)
    if type(role) ~= "string" then return nil end
    if not Api:CodexReady() then return nil end
    local C = Api:Codex()
    if type(C.WithRole) ~= "function" then
        if ns.Diag then
            ns.Diag:Call("Polestar.Codex.WithRole", nil, "функции нет в этой версии Codex")
        end
        return nil
    end
    local ok, list = pcall(C.WithRole, role)
    if not ok or type(list) ~= "table" then return nil end
    if ns.Diag then
        ns.Diag:Call("Polestar.Codex.WithRole", #list > 0,
            "роль " .. role .. ": " .. #list .. " NPC")
    end
    return list
end

-- Локализованное имя линии навыка по её номеру, если Codex его знает.
function Api:CodexSkillName(skillLineID)
    skillLineID = tonumber(skillLineID)
    if not skillLineID then return nil end
    if not Api:CodexReady() then return nil end
    local C = Api:Codex()
    if type(C.Name) ~= "function" then return nil end
    local ok, name = pcall(C.Name, "skill", skillLineID)
    if ok and type(name) == "string" and name ~= "" then return name end
    return nil
end

-- Обход записей Codex одного вида. `fn(id, name, quality, status)`; вернуть
-- false - остановить обход. Виды: item mount pet recipe tabard npc rare quest
-- zone instance treasure object faction spell.
--
-- ОБХОД ДОРОГОЙ: в предметах десятки тысяч записей, поэтому вызывать его можно
-- только из редкого сбора (Logic/Foresight.lua), не из пересчёта, и всегда с
-- собственным ограничителем у вызывающего.
function Api:CodexEach(kind, fn)
    if type(kind) ~= "string" or type(fn) ~= "function" then return false end
    if not Api:CodexReady() then return false end
    local C = Api:Codex()
    if type(C.Each) ~= "function" then
        if ns.Diag then
            ns.Diag:Call("Polestar.Codex.Each", nil, "функции нет в этой версии Codex")
        end
        return false
    end
    local ok = pcall(C.Each, kind, fn)
    if ns.Diag then ns.Diag:Call("Polestar.Codex.Each", ok, "вид: " .. kind) end
    return ok and true or false
end

-- QuestieDB ----------------------------------------------------------------
--
-- Второй, независимый источник того же: QuestieDB кладёт свои таблицы прямо в
-- глобальные `NpcDB` и `ItemDB` (не load-on-demand), и у него 10 414 NPC с
-- координатами и 3 734 предмета с торговцами. Структура у него своя и
-- недокументированная, поэтому читается она только через pcall и только как
-- ВТОРОЙ источник: первый - Codex, у которого есть публичный API.
--
-- Нужен он ровно для одного: когда Codex не установлен или не знает NPC, у
-- QuestieDB шанс знать - и тогда советы про торговцев не пропадают совсем.

function Api:QuestieNpcDB()
    local db = _G.NpcDB
    if type(db) ~= "table" then return nil end
    return db
end

function Api:QuestieNpcCount()
    local db = Api:QuestieNpcDB()
    if not db then return nil end
    if Api.questieNpcCount then return Api.questieNpcCount end
    local n = 0
    for _ in pairs(db) do n = n + 1 end
    Api.questieNpcCount = n
    return n
end

-- Where the foreign database says an item comes from. Used by the alternative
-- paths advice: { { kind = "craft", spell, profession, skill }, ... }
function Api:ForeignItemSources(itemID)
    itemID = tonumber(itemID)
    if not itemID then return nil end
    if not Api:ItemDBReady() then return nil end
    local db = Api:ItemDB()
    if type(db.Sources) ~= "function" then return nil end
    local ok, list = pcall(db.Sources, itemID)
    if not ok or type(list) ~= "table" then return nil end
    return list
end

-- Mastercraft ------------------------------------------------------------
-- We read only its SavedVariables table, which is a global. Its internal data
-- tables live in a private addon namespace and are not reachable from here, so
-- we never rely on them. Nothing is written back.

function Api:MastercraftDB()
    local db = _G.MastercraftDB
    if type(db) ~= "table" then return nil end
    return db
end

-- ВСЕ ПЕРСОНАЖИ АККАУНТА: УРОВЕНЬ, КЛАСС И ФАМИЛИЯ.
--
-- Syndicator отдаёт сумки и золото, но НЕ отдаёт уровень, а у этого игрока два
-- персонажа с одним именем «Гендольф» - различить их можно только по фамилии,
-- уровню и классу. Эти три вещи лежат в кеше Mastercraft: он пишет их на
-- выходе из игры, ключ - GUID, имя и фамилия порознь (поля name и surname),
-- как и в самом клиенте.
--
-- Возвращает { [полное имя] = { fullName, name, surname, realm, level,
--              classFile, className, guid } } или nil. Ничего не выдумывает:
-- чего в кеше нет, того нет и здесь.
function Api:MastercraftCharacters()
    local db = Api:MastercraftDB()
    if not db or type(db.chars) ~= "table" then return nil end
    local out, n = {}, 0
    for guid, c in pairs(db.chars) do
        if type(c) == "table" and type(c.name) == "string" and c.name ~= "" then
            local full = Api:FullName(c.name, c.surname)
            if full then
                out[full] = {
                    guid = guid,
                    fullName = full,
                    name = c.name,
                    surname = (type(c.surname) == "string" and c.surname ~= "")
                        and c.surname or nil,
                    realm = c.realm,
                    level = tonumber(c.level),
                    classFile = c.classFile,
                    -- Локализованное имя класса, как его записал клиент.
                    className = c.class,
                    faction = c.faction,
                }
                n = n + 1
            end
        end
    end
    if ns.Diag then
        ns.Diag:Call("MastercraftDB.chars (персонажи)", n > 0,
            "персонажей в кеше: " .. n)
    end
    if n == 0 then return nil end
    return out
end

-- The skill pair out of the player's own cache, for when nothing in the client
-- will answer. Two places hold a skill number, and only ONE of them holds a
-- maximum:
--
--   chars[guid].professions  = { { name, skill, max, icon }, ... }  - written on
--                              logout, so it is the newest thing there is. This
--                              is the only place in the cache with a maximum.
--   history[guid][date].s    = { [name] = { first, last } }         - the skill
--                              as first seen that day and as last seen that
--                              day. NO MAXIMUM. See Api:MastercraftSkillHistory.
--
-- chars wins when both exist. When only history exists, the skill is the last
-- number of the newest day and the maximum is unknown - said as unknown.
--
-- Returns a list in the same shape as Api:Professions, plus the route name.
-- Names are English here, because that is what Mastercraft stores; the UI asks
-- the client for a localised name separately.
function Api:MastercraftProfessions(guid)
    local db = Api:MastercraftDB()
    if not db or not guid then return nil end

    local function row(name, skill, max)
        max = tonumber(max)
        if max and max <= 0 then max = nil end
        local cur = tonumber(skill)
        if cur and cur < 0 then cur = nil end
        return {
            name = name, skill = cur, max = max, maxKnown = (max ~= nil),
            skillTrusted = (cur ~= nil), fromCache = true,
        }
    end

    local char = type(db.chars) == "table" and db.chars[guid]
    if type(char) == "table" and type(char.professions) == "table" then
        local out = {}
        for _, p in ipairs(char.professions) do
            if type(p) == "table" and type(p.name) == "string" then
                out[#out + 1] = row(p.name, p.skill, p.max)
            end
        end
        if #out > 0 then
            if ns.Diag then
                ns.Diag:Call("MastercraftDB.chars (навыки)", true,
                    "профессий из кеша: " .. #out)
            end
            return out, "MastercraftDB.chars"
        end
    end

    -- Nothing in chars. Fall back to the newest history row we have.
    --
    -- НАВЫК - ПОСЛЕДНЕЕ ЧИСЛО ДНЯ, МАКСИМУМА ТАМ НЕТ. Раньше пара читалась как
    -- { навык, максимум }: из записи «рыбалка { 155, 225 }» выходило «155 из
    -- 225», хотя это навык вырос за день со 155 до 225, а максимум не записан
    -- вовсе. Теперь навык берётся последний, а максимум остаётся неизвестным.
    local hist = Api:MastercraftSkillHistory(guid)
    if hist and #hist > 0 then
        local newest = hist[#hist]
        local out = {}
        for name, pair in pairs(newest.skills or {}) do
            out[#out + 1] = row(name, pair.last or pair.first, nil)
        end
        table.sort(out, function(a, b) return (a.name or "") < (b.name or "") end)
        if #out > 0 then
            if ns.Diag then
                ns.Diag:Call("MastercraftDB.history (навыки)", true,
                    "взят самый свежий день: " .. tostring(newest.date))
            end
            return out, "MastercraftDB.history"
        end
    end

    if ns.Diag then
        ns.Diag:Call("MastercraftDB.chars (навыки)", false,
            "для этого персонажа в кеше навыков нет")
    end
    return nil
end

-- ПОД КАКИМ ИМЕНЕМ ПРОФЕССИЮ ХРАНИТ MASTERCRAFT.
--
-- Mastercraft пишет английские имена («Tailoring», «Fishing»), клиент отдаёт
-- локализованные («Портняжное дело», «Рыбная ловля»). Переводить имя по
-- словарю нельзя - это и есть угадывание. Надёжный мост один: номер линии
-- навыка. Клиент отдаёт его вместе с профессией, а Data/ForeverSource знает
-- английское имя каждой линии - оно взято из установленного Polestar_Codex, а
-- не вписано по памяти.
--
-- Принимает строку профессии (лучше: в ней есть skillLineID) или одно имя.
-- Возвращает английское имя и номер линии, либо nil - когда линию установить
-- нечем. Ничего не выдумывает: неизвестная профессия остаётся без ключа.
function Api:MastercraftProfessionKey(profession)
    local FS = ns.ForeverSource
    if not (FS and type(FS.SKILL_LINES) == "table") then return nil end
    local row = (type(profession) == "table") and profession or nil
    local name = row and row.name or profession

    -- 1. Номер линии прямо в строке профессии - так отвечает сам клиент.
    local line = row and tonumber(row.skillLineID) or nil

    -- 2. По имени: английское как есть, локализованное - через Codex.
    if not line and type(name) == "string" and FS.SkillLineByName then
        line = FS:SkillLineByName(name)
    end

    -- 3. Вызывающий знает только имя, а Codex не помог: эта же профессия уже
    --    прочитана в снимок персонажа, и номер линии там есть.
    if not line and type(name) == "string" then
        local snap = ns.CharacterScanner and ns.CharacterScanner.snapshot
        for _, prof in ipairs((snap and snap.professions) or {}) do
            if prof.name == name and tonumber(prof.skillLineID) then
                line = tonumber(prof.skillLineID)
                break
            end
        end
    end

    if not line then return nil end
    local key = FS.SKILL_LINES[line]
    if type(key) ~= "string" then return nil end
    return key, line
end

-- The day-by-day skill record, oldest first.
--
-- ЧТО ЛЕЖИТ В ПАРЕ - И ЧЕМ ЭТО КОНЧИЛОСЬ, КОГДА ЕЁ ПРОЧЛИ НЕВЕРНО.
--
-- Mastercraft пишет историю так (Data.lua, RecordHistory):
--
--     if s then s[2] = p.skill else d.s[p.name] = { p.skill, p.skill } end
--
-- то есть s[профессия] = { навык, каким он был увиден в этот день ПЕРВЫМ;
-- навык, каким он был увиден ПОСЛЕДНИМ }. ОБА ЧИСЛА - НАВЫК. Максимума в этой
-- записи нет.
--
-- Аддон читал пару как { навык, максимум }. Из этого выросло всё остальное:
-- «потолок навыка динамический», функция SkillCapMoves, строка на карточке
-- «Раньше он уже поднимался (4 раза): последний раз 2026-11-15, 224 -> 225» и
-- такая же на вкладке персонажа. «224 -> 225» - это игрок докачал один пункт.
-- Проверяется на самих числах: последнее число одного дня равно первому числу
-- следующего (84|84, 93|93, 160|160, 224|224) - у пары «навык, максимум» так
-- не бывает. Найдено сплошной проверкой текстов 2026-11-18.
--
-- With `profession` given:  { { date, first, last }, ... }
-- Without:                  { { date, skills = { [name] = { first, last } } }, ... }
-- Returns nil when there is nothing recorded - not an empty table.
function Api:MastercraftSkillHistory(guid, profession)
    local db = Api:MastercraftDB()
    if not db or not guid then return nil end
    local days = type(db.history) == "table" and db.history[guid]
    if type(days) ~= "table" then return nil end

    local out = {}
    for date, day in pairs(days) do
        if type(date) == "string" and type(day) == "table" and type(day.s) == "table" then
            if profession then
                local pair = day.s[profession]
                if type(pair) == "table" then
                    local first, last = tonumber(pair[1]), tonumber(pair[2])
                    if first or last then
                        out[#out + 1] = { date = date, first = first, last = last }
                    end
                end
            else
                local skills, any = {}, false
                for name, pair in pairs(day.s) do
                    if type(name) == "string" and type(pair) == "table" then
                        skills[name] = { first = tonumber(pair[1]), last = tonumber(pair[2]) }
                        any = true
                    end
                end
                if any then out[#out + 1] = { date = date, skills = skills } end
            end
        end
    end
    if #out == 0 then return nil end
    -- The dates are ISO (YYYY-MM-DD), so a string sort is a date sort.
    table.sort(out, function(a, b) return a.date < b.date end)
    return out
end

-- ЗДЕСЬ БЫЛА Api:SkillCapMoves - «КОГДА И НАСКОЛЬКО ПОДНИМАЛСЯ ПОТОЛОК».
--
-- Её нет, потому что считать ей нечего: единственный источник, из которого она
-- брала «потолок», - вторая цифра пары выше, а это навык. Истории максимума
-- нет ни в одном источнике, который аддон читает; когда она появится (сам
-- клиент отдаёт пару «навык / максимум» только на сейчас), её надо будет
-- копить самим, а не выводить из чужого графика навыка.

-- Cached recipes another addon already scanned for this character. This is what
-- lets us say something useful before the player has opened a single profession
-- window. Returns { [professionName] = { list = { recipe, ... } } }.
-- Ownership is checked strictly: the cache is keyed by character GUID, and a
-- GUID that is not ours belongs to an alt. There used to be a "if there is only
-- one entry it must be this player" fallback here, and on a real account it was
-- wrong - this very account has two characters and only the mage's recipes
-- cached, so the level-10 alt was being told it knew 900 tailoring recipes.
-- When we cannot prove ownership we return nothing and say why.
function Api:MastercraftRecipes(guid)
    local db = Api:MastercraftDB()
    if not db or type(db.recipes) ~= "table" then
        return nil, nil, "кеша рецептов нет"
    end
    if not guid then
        return nil, nil, "GUID персонажа неизвестен — чужой кеш читать нельзя"
    end
    if db.recipes[guid] then return db.recipes[guid], guid end

    local n = 0
    for _ in pairs(db.recipes) do n = n + 1 end
    if ns.Diag then
        ns.Diag:Call("MastercraftDB.recipes", false,
            "для этого персонажа записей нет (в базе " .. n .. ")")
    end
    return nil, nil, (n > 0)
        and ("в кеше есть " .. n .. " других персонажей, но этого нет")
        or "кеш рецептов пуст"
end

function Api:MastercraftVendorPrice(itemID)
    local db = Api:MastercraftDB()
    if not db or type(db.vendorPrices) ~= "table" then return nil, CONF.UNKNOWN end
    local p = tonumber(db.vendorPrices[itemID])
    if p and p > 0 then return p, CONF.CACHED end
    return nil, CONF.UNKNOWN
end

-- Prices another addon recorded for things the player BOUGHT.
--
-- TWO FIELDS THAT WERE BEING IGNORED, AND BOTH MATTERED.
--
-- `c` IS THE PRICE OF THE WHOLE LOT, NOT OF ONE ITEM. That addon's own
-- Cost.lua says so in the comment over the table:
--     [itemID] = { { q = how many, c = copper for them all, t = when,
--                    m = made by you }, ... }
-- We read `c` and ignored `q`. The player's real record for item 4338 is
-- q = 250, c = 124920, so the addon reported 12 gold 49 silver EACH for a
-- reagent that costs 4 silver 99 - and an audit found lots of up to 362, i.e.
-- a price inflated three hundred and sixty-two fold. Divided by `q` it comes
-- out at 4 silver 99, which agrees with the auction house.
--
-- `m` MEANS THE PLAYER MADE IT THEMSELVES, so `c` is their own cost of
-- materials, not a price anybody asked or paid. Using it as a market price is
-- selling to yourself, and the sell path then took the auction house's 5% off
-- it as well. Seven of the player's items were priced that way. Those records
-- are skipped: they are evidence about the player's spending, not about the
-- market.
--
-- What is left is the price the player PAID at the auction house for one of
-- these - a real market observation, and the only one this table offers.
-- ОТВЕТ ЗАПОМИНАЕТСЯ, И ЭТО ИЗМЕРЕННАЯ ПОТРЕБНОСТЬ.
--
-- Замер по веткам на реальных данных: ветка «крафт на продажу» зовёт эту
-- функцию 269 раз за пересчёт. Каждый вызов до этого заново искал нужный реалм
-- обходом db.costs и заново перебирал все лоты предмета.
--
-- Памятей две, и у них разный срок: эта - на проход (по ней считаются
-- «ответы из памяти» в сводке), а ниже - на сессию, до события покупки.
Api.observedPriceCache = {}
-- ПАМЯТЬ НА ВСЮ СЕССИЮ, А НЕ НА ПРОХОД.
--
-- Ответ этой таблицы не может измениться сам: лот в чужую книгу попадает только
-- когда игрок что-то купил или продал. Поэтому и «цена такая», и «записей нет»
-- помнятся до события покупки (Api:ClearObservedPriceMemory, зовётся из Main по
-- деньгам, сумкам, торговцу и аукциону), а не сбрасываются каждым проходом.
--
-- Хранится ВРЕМЯ НАБЛЮДЕНИЯ, а не посчитанный возраст: возраст и достоверность
-- считаются на каждом чтении заново. Запомнить возраст значило бы заморозить
-- его на всю сессию - то есть соврать в том единственном поле, из-за которого
-- цена двухдневной давности однажды уже печаталась как «2 минуты назад».
--   session[key] = { unit = медяки, at = когда наблюдали }   - цена есть
--   session[key] = { empty = "причина словами" }             - цены нет
Api.observedPriceSession = {}
Api.observedPriceSessionHits = 0
-- Какая книга в памяти: подменится таблица - память недействительна.
Api.observedSessionDB = nil
Api.observedBucket = nil
Api.observedBucketKey = nil

-- ЗАБЫТЬ ОТВЕТЫ ЧУЖОЙ КНИГИ. Зовётся из Main по тем же сигналам, по которым
-- чужой аддон мог дописать лот: деньги, сумки, торговец, аукцион. Возвращает,
-- сколько ответов забыто.
function Api:ClearObservedPriceMemory(why)
    local n = 0
    for _ in pairs(Api.observedPriceSession) do n = n + 1 end
    Api.observedPriceSession = {}
    Api.observedPriceCache = {}
    if ns.Diag and n > 0 then
        ns.Diag:Count("mastercraft.observedMemoryCleared")
        ns.Diag:Log("память ответов чужой книги закупок сброшена", {
            items = n, why = why,
        })
    end
    return n
end

-- Что именно сказала чужая книга закупок про предметы, по которым она молчит:
-- одна фраза на весь список, для сводки источников. nil - молчания не было.
function Api:ObservedPriceSilence()
    local byWhy, total = {}, 0
    for _, memo in pairs(Api.observedPriceSession) do
        local why = (type(memo) == "table") and memo.empty or nil
        if why then
            total = total + 1
            byWhy[why] = (byWhy[why] or 0) + 1
        end
    end
    if total == 0 then return nil end
    local best, bestN = nil, -1
    for why, n in pairs(byWhy) do
        if n > bestN or (n == bestN and tostring(why) < tostring(best)) then
            best, bestN = why, n
        end
    end
    return { items = total, why = best, n = bestN,
             hits = Api.observedPriceSessionHits or 0 }
end
-- Сколько раз таблицу лотов ПРИШЛОСЬ перебрать, и сколько раз ответ нашёлся у
-- нас. Контракт в наборе стоит на первом числе: вызовов может быть сколько
-- угодно, а работа должна делаться один раз на предмет.
Api.observedPriceReads = 0
Api.observedPriceHits = 0

function Api:MastercraftObservedPrice(itemID, realmKey)
    local db = Api:MastercraftDB()
    if not db or type(db.costs) ~= "table" then return nil, CONF.UNKNOWN end
    local memoKey = tostring(realmKey or "") .. "|" .. tostring(itemID)
    local memo = Api.observedPriceCache[memoKey]
    if memo ~= nil then
        Api.observedPriceHits = Api.observedPriceHits + 1
        if memo == false then return nil, CONF.UNKNOWN end
        return memo[1], memo[2], memo[3]
    end
    -- «ПО ЭТОМУ ПРЕДМЕТУ РЫНОЧНОЙ ЗАПИСИ НЕТ» - ОТВЕТ, КОТОРЫЙ НЕ МЕНЯЕТСЯ САМ.
    --
    -- Живой файл: 6804 обращения к этой таблице за сессию, и НИ ОДНОГО ответа
    -- (21 обход за пересчёт на настоящих данных - единственное обращение к
    -- клиенту, которое повторялось на каждом пересчёте без исключения). Причина
    -- не в поломке: у этих предметов все записи помечены «сделано мной», то
    -- есть в таблице лежит себестоимость игрока, а не цена рынка. Такой ответ
    -- не может стать другим, пока чужой аддон не допишет лот, - а дописать он
    -- может только когда игрок что-то купил или продал.
    --
    -- Поэтому отрицательный ответ помнится ДОЛЬШЕ ПРОХОДА и забывается там же,
    -- где мог появиться новый лот: по событиям денег, сумок и торговца
    -- (Api:ClearObservedPriceMemory, зовётся из Main). Причина при этом не
    -- исчезает молча - она названа словами один раз на предмет (ниже) и попадает
    -- в сводку источников.
    local function aged(unit, at)
        local age = Api:ServerTime() - (tonumber(at) or 0)
        local conf = (age < ns.PRICE_STALE_SECONDS) and CONF.CACHED or CONF.ESTIMATE
        return unit, conf, age
    end
    -- Подменилась сама книга - память недействительна целиком. Тот же приём,
    -- что у памяти реалма ниже: ключом служит сама таблица.
    if Api.observedSessionDB ~= db then
        Api.observedPriceSession = {}
        Api.observedSessionDB = db
    end
    local session = Api.observedPriceSession[memoKey]
    if session ~= nil then
        Api.observedPriceHits = Api.observedPriceHits + 1
        Api.observedPriceSessionHits = (Api.observedPriceSessionHits or 0) + 1
        if session.empty then return nil, CONF.UNKNOWN end
        return aged(session.unit, session.at)
    end
    Api.observedPriceReads = Api.observedPriceReads + 1
    local function remember(value, at, emptyWhy)
        if value then
            Api.observedPriceSession[memoKey] = { unit = value, at = at }
            local unit, conf, age = aged(value, at)
            Api.observedPriceCache[memoKey] = { unit, conf, age }
            return unit, conf, age
        end
        Api.observedPriceSession[memoKey] =
            { empty = emptyWhy or "нет записей с ценой" }
        Api.observedPriceCache[memoKey] = false
        return nil, CONF.UNKNOWN
    end
    local bucket
    if realmKey then
        bucket = db.costs[realmKey]
    elseif Api.observedBucketKey == db then
        bucket = Api.observedBucket
    else
        local n = 0
        for _, v in pairs(db.costs) do bucket, n = v, n + 1 end
        if n ~= 1 then bucket = nil end
        -- Ключом памяти служит сама таблица: подменится база - подменится и ключ.
        Api.observedBucket, Api.observedBucketKey = bucket, db
    end
    if type(bucket) ~= "table" then
        return remember(nil, nil, "в чужой книге нет записей по этому серверу")
    end
    local entries = bucket[itemID]
    if type(entries) ~= "table" then
        return remember(nil, nil, "этого предмета в чужой книге нет вовсе")
    end

    -- The lots are keyed by item quality on this client, so pairs() rather than
    -- ipairs(): an ipairs walk stops at the first hole and silently skips the
    -- rest. Each value is itself a list of lots.
    local best, bestT, skippedMade = nil, -1, 0
    local function consider(e)
        if type(e) ~= "table" then return end
        local c, q, t = tonumber(e.c), tonumber(e.q), tonumber(e.t) or 0
        if not c or c <= 0 then return end
        if e.m then
            -- Made by the player: their own cost, not a market price.
            skippedMade = skippedMade + 1
            return
        end
        -- No quantity recorded means one item; a recorded quantity is how many
        -- that `c` covers.
        local unit = c / math.max(1, q or 1)
        if unit > 0 and t > bestT then best, bestT = unit, t end
    end
    for _, e in pairs(entries) do
        if type(e) == "table" and (e.c or e.q) then
            consider(e)
        elseif type(e) == "table" then
            for _, inner in pairs(e) do consider(inner) end
        end
    end

    if ns.Diag and skippedMade > 0 then
        ns.Diag:Count("mastercraft.ownCraftSkipped", skippedMade)
    end
    if not best then
        local why = (skippedMade > 0)
            and "все записи помечены «сделано мной» — это себестоимость, не рынок"
            or "записей с ценой нет"
        if ns.Diag then
            ns.Diag:Call("MastercraftDB.costs (наблюдённая цена)", false, why)
        end
        return remember(nil, nil, why)
    end
    -- УСПЕХ ТОЖЕ ЗАПИСЫВАЕТСЯ, И ЭТО НЕ КОСМЕТИКА.
    --
    -- Записывался только неуспех, поэтому в живом файле у этой таблицы стояло
    -- «6804 попытки, 0 с данными» - и читалось как «маршрут не работает
    -- никогда». Он работает: в книге игрока 394 лота, из них 304 рыночных, и
    -- часть цен в журнале выбрана именно по нему (src = "foreign"). Счётчик,
    -- который считает только провалы, - это испорченный прибор, а решения по
    -- нему принимались.
    if ns.Diag then
        ns.Diag:Call("MastercraftDB.costs (наблюдённая цена)", true,
            "цена взята из чужой книги закупок")
    end
    return remember(best, bestT)
end

-- Maps and places --------------------------------------------------------

-- Where the player is standing right now: uiMapID, x, y (both 0..1), zone name.
-- This is how the addon builds its own location data, so it matters that it
-- fails quietly rather than returning a half-answer.
function Api:PlayerPosition()
    if not (Api.has.bestMapForUnit and Api.has.playerMapPos) then
        return nil, nil, nil, nil
    end
    local ok, mapID = pcall(F.bestMapForUnit, "player")
    if not ok or not mapID then
        if ns.Diag then
            ns.Diag:Call("C_Map.GetBestMapForUnit", false, "карта игрока не определилась")
        end
        return nil, nil, nil, nil
    end
    local ok2, pos = pcall(F.playerMapPos, mapID, "player")
    if not ok2 or type(pos) ~= "table" then
        if ns.Diag then
            ns.Diag:Call("C_Map.GetPlayerMapPosition", false,
                "карта есть, координат нет (бывает в подземельях)")
        end
        return mapID, nil, nil, Api:MapName(mapID)
    end
    local x, y
    if pos.GetXY then
        local okXY, px, py = pcall(pos.GetXY, pos)
        if okXY then x, y = px, py end
    else
        x, y = pos.x, pos.y
    end
    if not (x and y) or (x == 0 and y == 0) then
        if ns.Diag then
            ns.Diag:Call("C_Map.GetPlayerMapPosition", false,
                "координаты пришли нулевыми")
        end
        return mapID, nil, nil, Api:MapName(mapID)
    end
    if ns.Diag then ns.Diag:Call("C_Map.GetPlayerMapPosition", true) end
    return mapID, x, y, Api:MapName(mapID)
end

function Api:MapName(uiMapID)
    if not (uiMapID and Api.has.mapInfo) then return nil end
    local ok, info = pcall(F.mapInfo, uiMapID)
    if ok and type(info) == "table" then return U.trim(info.name) end
    return nil
end

-- The creature id out of a unit's GUID: "Creature-0-1234-0-0-5678-000..." -> 5678.
-- Works for Creature, Vehicle and Pet GUIDs; returns nil for players.
function Api:UnitNpcID(unit)
    if not Api.has.unitGUIDFor then return nil end
    local ok, guid = pcall(F.unitGUIDFor, unit or "npc")
    if not ok or type(guid) ~= "string" then return nil end
    local kind, _, _, _, _, id = guid:match("^(%a+)%-(%d+)%-(%d+)%-(%d+)%-(%d+)%-(%d+)")
    if kind == "Creature" or kind == "Vehicle" or kind == "GameObject" then
        return tonumber(id), kind
    end
    return nil
end

function Api:UnitName(unit)
    if not Api.has.unitName then return nil end
    local ok, name = pcall(F.unitName, unit or "npc")
    if ok then return U.trim(name) end
    return nil
end

-- Merchant window contents. Reading a window the player opened is not
-- automation; nothing here buys anything.
function Api:MerchantItems()
    if not (Api.has.merchantNumItems and Api.has.merchantItemInfo) then return nil end
    local ok, count = pcall(F.merchantNumItems)
    if not ok or type(count) ~= "number" then return nil end
    local out = {}
    for i = 1, count do
        -- GetMerchantItemInfo: name, texture, price, stackCount, numAvailable, ...
        -- numAvailable is -1 for unlimited stock and a count for a finite pile.
        local ok2, name, _, price, stack, numAvailable = pcall(F.merchantItemInfo, i)
        if ok2 and price and price > 0 then
            local itemID
            if Api.has.merchantItemLink then
                local ok3, link = pcall(F.merchantItemLink, i)
                if ok3 then itemID = U.itemIDFromLink(link) end
            end
            if itemID then
                out[#out + 1] = {
                    itemID = itemID, name = U.trim(name),
                    price = price, stack = tonumber(stack) or 1,
                    numAvailable = tonumber(numAvailable),
                }
            end
        end
    end
    return out
end

-- Navigation -------------------------------------------------------------
--
-- ForeverPilot draws its own arrow. It needs three things from the client,
-- each feature-detected because none of them is guaranteed:
--
--   C_Map.GetBestMapForUnit + C_Map.GetPlayerMapPosition  - where we are
--   GetPlayerFacing                                       - which way we look
--   C_Map.GetMapWorldSize                                 - yards per map
--
-- GetPlayerFacing is the fragile one: in some instances and on taxi flights the
-- client refuses it. The arrow then hides and the distance and compass
-- direction are shown instead. Nothing here throws, and none of it is required
-- for the rest of the addon to work.
--
-- TomTom stays as an optional alternative the player can pick in settings:
-- with it chosen and installed, we hand the point over instead of drawing.

Api.NAV_OWNER = "ForeverPilot"

function Api:HasPlayerFacing()
    return Api.has.playerFacing and true or false
end

-- Radians, 0 = north, growing counter-clockwise. nil when the client will not
-- say - which is a normal state, not an error.
function Api:PlayerFacing()
    if not Api.has.playerFacing then
        if ns.Diag then
            ns.Diag:Call("GetPlayerFacing", nil, "функции нет на этом клиенте")
        end
        return nil
    end
    local ok, facing = pcall(F.playerFacing)
    if not ok or type(facing) ~= "number" then
        if ns.Diag then
            ns.Diag:Call("GetPlayerFacing", false,
                "функция есть, но направление не вернулось — стрелка скроется,"
                .. " останется компас")
        end
        return nil
    end
    if ns.Diag then ns.Diag:Call("GetPlayerFacing", true) end
    return facing
end

-- { width, height } in yards for a map, or nil when the client does not expose
-- it. Cached: it never changes for a given map.
local worldSizeCache = {}
function Api:MapWorldSize(uiMapID)
    if not (uiMapID and Api.has.mapWorldSize) then return nil end
    local hit = worldSizeCache[uiMapID]
    if hit ~= nil then
        if hit == false then return nil end
        return hit
    end
    local ok, width, height = pcall(F.mapWorldSize, uiMapID)
    if ok and type(width) == "number" and type(height) == "number"
       and width > 0 and height > 0 then
        worldSizeCache[uiMapID] = { width = width, height = height }
        if ns.Diag then
            ns.Diag:Call("C_Map.GetMapWorldSize", true,
                string.format("карта %s: %.0f x %.0f ярдов",
                    tostring(uiMapID), width, height))
        end
        return worldSizeCache[uiMapID]
    end
    worldSizeCache[uiMapID] = false
    if ns.Diag then
        ns.Diag:Call("C_Map.GetMapWorldSize", false,
            "размер карты " .. tostring(uiMapID)
            .. " не вернулся — расстояние будет словами, не в метрах")
    end
    return nil
end

-- Everything the arrow needs about the player, in one call.
function Api:NavPlayerState()
    local mapID, x, y, zone = Api:PlayerPosition()
    if not (mapID and x and y) then return nil end
    return { mapID = mapID, x = x, y = y, zone = zone, facing = Api:PlayerFacing() }
end

-- TomTom --------------------------------------------------------------

function Api:TomTomPresent()
    local T = _G.TomTom
    return (type(T) == "table" and type(T.AddWaypoint) == "function") and true or false
end

-- Normalise to 0..1 fractions and reject anything off the map.
local function fractions(x, y)
    x, y = tonumber(x), tonumber(y)
    if not (x and y) then return nil end
    if x > 1 or y > 1 then x, y = x / 100, y / 100 end
    if x <= 0 or y <= 0 or x > 1 or y > 1 then return nil end
    return x, y
end
Api.NavFractions = function(_, x, y) return fractions(x, y) end

-- Hand a point to TomTom. Only called when the player has chosen TomTom in
-- settings; the own arrow is the default. Returns ok, reason.
function Api:TomTomWaypoint(uiMapID, x, y, title)
    if not Api:TomTomPresent() then return false, "no-tomtom" end
    uiMapID = tonumber(uiMapID)
    local fx, fy = fractions(x, y)
    if not (uiMapID and fx) then return false, "bad-coords" end
    local ok = pcall(_G.TomTom.AddWaypoint, _G.TomTom, uiMapID, fx, fy, {
        title = title or Api.NAV_OWNER,
        from = Api.NAV_OWNER,
        persistent = false,
        minimap = true,
        world = true,
        crazy = true,
    })
    if not ok then return false, "error" end
    return true
end

-- Which way a route request will be served: "own" | "tomtom" | nil.
-- Our own arrow needs nothing but a player position, so it is almost always
-- available; TomTom is used only when the player asked for it.
function Api:NavProvider()
    local cfg = ns.Config and ns.Config:Get()
    local pref = cfg and cfg.nav and cfg.nav.provider or "own"

    if pref == "tomtom" and Api:TomTomPresent() then return "tomtom" end
    if pref == "off" then return nil end

    if Api.has.bestMapForUnit and Api.has.playerMapPos then return "own" end
    if Api:TomTomPresent() then return "tomtom" end
    return nil
end

Api.NAV_PROVIDER_LABEL = {
    own = "своя стрелка",
    tomtom = "TomTom",
}

-- Places another addon might publish globally. No addon currently installed
-- exposes its vendor coordinates - Mastercraft keeps VENDOR_PLACES in its
-- private namespace, which is unreachable from here - so in practice this
-- returns nil today and the addon relies on what it recorded itself. The hook
-- costs nothing and means a future export is picked up without a code change.
function Api:ForeignPlaces()
    local candidates = {
        "ForeverPilotPlaces",
        "MastercraftPlaces",
        "MASTERCRAFT_VENDOR_PLACES",
    }
    for _, name in ipairs(candidates) do
        local t = _G[name]
        if type(t) == "table" and next(t) then return t, name end
    end
    -- An addon that published its namespace on a global object.
    for _, name in ipairs({ "Mastercraft", "Polestar" }) do
        local t = _G[name]
        if type(t) == "table" then
            local places = t.VENDOR_PLACES or t.NPC_PLACES or (t.API and t.API.Places)
            if type(places) == "table" and next(places) then return places, name end
        end
    end
    return nil
end

-- Chat -------------------------------------------------------------------

-- ОДНО И ТО ЖЕ СООБЩЕНИЕ ПОДРЯД НЕ ПЕЧАТАЕТСЯ ДВАЖДЫ.
--
-- Живая жалоба: игрок нажимал кнопку на карточке десять раз и получал десять
-- одинаковых строк в чате. Повтор одного и того же - это не информация, это
-- шум, в котором тонут настоящие сообщения.
--
-- Сворачивается ТОЛЬКО непосредственный повтор: то же сообщение после другого
-- печатается снова. Иначе аддон замолчал бы о событии, которое действительно
-- случилось во второй раз («цены устарели» через час - это новость).
--
-- Счётчик подавленных не выбрасывается: если кто-то нажал кнопку двадцать раз,
-- это видно в диагностике, а не только в его раздражении.
--
-- ПОВТОР ПОСЛЕ ПАУЗЫ - ЭТО НОВЫЙ ПОВОД. Без срока сворачивание делало кнопку
-- мёртвой: игрок нажал «Показать предмет», ссылка уехала вверх за чужими
-- сообщениями, через пять минут он нажимает снова - и не получает ничего,
-- потому что «это уже было сказано». Поэтому тот же текст сворачивается только
-- пока с его прошлой ПЕЧАТИ прошло меньше REPEAT_QUIET_SECONDS: десять нажатий
-- подряд - одна строка, нажатие через полминуты - снова ответ.
Api.REPEAT_QUIET_SECONDS = 20
Api.lastSaid = nil
Api.lastSaidAt = nil
Api.lastSaidSuppressed = 0

function Api:ShouldSay(msg)
    msg = tostring(msg)
    local now = Api:Now()
    if Api.lastSaid == msg then
        local at = Api.lastSaidAt or now
        local since = now - at
        if since >= 0 and since < Api.REPEAT_QUIET_SECONDS then
            Api.lastSaidSuppressed = Api.lastSaidSuppressed + 1
            if ns.Diag then ns.Diag:Count("print.repeatSuppressed") end
            return false
        end
    end
    Api.lastSaid = msg
    Api.lastSaidAt = now
    Api.lastSaidSuppressed = 0
    return true
end

-- ТЕСТОВЫЙ ШОВ, не удобство: подменять сам Api:Print значило бы подменять
-- вместе с ним и сворачивание повторов, то есть ровно то поведение, которое
-- надо проверить. Фейк заменяет только ВЫВОД.
Api.printer = nil

function Api:InjectPrinter(fn)
    Api.printer = (type(fn) == "function") and fn or nil
end

function Api:Print(msg)
    if not Api:ShouldSay(msg) then return false end
    local line = "|cff66ccffForeverPilot|r: " .. tostring(msg)
    if Api.printer then Api.printer(line); return true end
    local p = _G.print
    if type(p) == "function" then p(line) end
    return true
end

return Api
