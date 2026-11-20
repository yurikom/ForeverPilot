-- ForeverPilot / Data/ForeverSource.lua
--
-- Facts the Forever client does not hand us, collected from outside the game so
-- the addon has routes and honest numbers on day one instead of after a week of
-- walking into vendors. Nothing here replaces what the client says: every table
-- is a starting point that Logic/SourceCheck.lua compares against the real
-- client data on the next login and reports on, rather than trusting forever.
--
-- WHERE IT COMES FROM
--   * Vendors, places, recipe sources: the Mastercraft addon's own data files
--     (VendorData.lua / TrainerData.lua / RecipeData.lua, v1.9.9), which state
--     they were generated from Wowhead Forever. Narrowed here to what a 1-60
--     tailor/enchanter actually walks to.
--   * Spot-checked by me against Wowhead Forever's own structured endpoints
--     (nether.wowhead.com/tooltip/{npc,item,spell}/<id>?dataEnv=16, where
--     dataEnv=16 is the Forever branch) on 2026-11-16. Coordinates matched
--     exactly on every NPC sampled; reagents matched exactly on every recipe
--     sampled. See the report that came with this file for the sample list.
--   * Disenchant probabilities: NOT from a Forever source. See DISENCHANT below -
--     the provenance is spelled out there because it is the weakest data here.
--
-- NAMES ARE ENGLISH ON PURPOSE. The `en` field is the Wowhead name, kept only so
-- a human can read this file. Nothing in the addon should show it to the player:
-- call ForeverSource:ItemName(itemID) / :PlaceLabel(npcID), which ask the client
-- for the localised name and fall back to a marked "#<id>" when the client has
-- not loaded it. No Russian in this file was written by hand.
local ADDON, ns = ...

local FS = {}
ns.ForeverSource = FS

-- НОМЕРА ЛИНИЙ НАВЫКА (skillLineID).
--
-- Нужны ровно для одного: спросить у Polestar.Codex тренеров роли
-- "trainer:<skillLineID>". Клиент эти номера отдаёт сам (C_SkillInfo), и он
-- всегда главный источник; таблица - запасной путь для случая, когда
-- C_SkillInfo промолчал, а тренера найти всё равно надо.
--
-- Откуда числа: из установленного Polestar_Codex/Skills1.lua, то есть из той
-- же базы, которой мы потом задаём вопрос про тренеров. Ничего по памяти здесь
-- не вписано. Имена английские - их и отдаёт пакет; локализованное имя берётся
-- через Codex.Name("skill", id) во время работы.
FS.SKILL_LINES = {
    [129] = "First Aid",
    [164] = "Blacksmithing",
    [165] = "Leatherworking",
    [171] = "Alchemy",
    [182] = "Herbalism",
    [185] = "Cooking",
    [186] = "Mining",
    [197] = "Tailoring",
    [202] = "Engineering",
    [333] = "Enchanting",
    [356] = "Fishing",
    [393] = "Skinning",
}

-- Номер линии навыка по имени профессии. Сначала как есть, потом без учёта
-- регистра: имя может прийти и из клиента, и из чужого кеша.
function FS:SkillLineByName(name)
    if type(name) ~= "string" then return nil end
    for id, en in pairs(FS.SKILL_LINES) do
        if en == name then return id, "en" end
    end
    local lower = ns.Util.lower(name)
    for id, en in pairs(FS.SKILL_LINES) do
        if ns.Util.lower(en) == lower then return id, "en-ci" end
    end
    -- Локализованное имя: его знает Codex, и спрашивать надо у него, а не
    -- угадывать перевод здесь.
    if ns.Api and ns.Api.CodexSkillName then
        for id in pairs(FS.SKILL_LINES) do
            local localised = ns.Api:CodexSkillName(id)
            if localised and ns.Util.lower(localised) == lower then
                return id, "codex"
            end
        end
    end
    -- И СВОЙ СЛОВАРЬ ИМЁН, КОГДА CODEX НЕ УСТАНОВЛЕН.
    --
    -- Это не новый перевод, вписанный здесь: RecipeBook.NAME_BRIDGE - тот
    -- единственный словарь ru<->en, которым книга рецептов склеивает свои и
    -- чужие имена профессий, и он покрывает все одиннадцать крафтовых. Без
    -- этого шага «Алхимия» не сопоставлялась ни с чем, и ветки, которые ходят
    -- по номеру линии навыка, отвечали «не смог сопоставить ваши профессии» на
    -- любом клиенте без Codex - то есть сваливали на свою слепоту то, что
    -- вполне можно было узнать.
    local bridge = ns.RecipeBook and ns.RecipeBook.NAME_BRIDGE or nil
    local en = bridge and bridge[lower] or nil
    if en then
        for id, name in pairs(FS.SKILL_LINES) do
            if ns.Util.lower(name) == en then return id, "bridge" end
        end
    end
    return nil
end

-- Знают ли НАШИ данные этот номер линии навыка.
--
-- Вопрос не праздный: клиент Forever отдаёт одну профессию дважды и с разными
-- номерами - список профессий современными (2948 портняжка, 2940 чары), окно
-- навыков классическими (197, 333). Таблица выше, роли тренеров в Codex и
-- пороги в Data/Horizon.lua размечены КЛАССИЧЕСКИМИ. Номер, которого в таблице
-- нет, для наших данных бесполезен: по нему ничего не найдётся.
function FS:KnowsSkillLine(id)
    id = tonumber(id)
    return (id ~= nil) and (FS.SKILL_LINES[id] ~= nil)
end

-- НОМЕР ЛИНИИ НАВЫКА ДЛЯ ОДНОЙ ПРОФЕССИИ ИЗ СНИМКА.
--
-- Один ответ на вопрос «какой номер у этой профессии в наших данных», чтобы
-- ветки не повторяли выбор каждая по-своему. Порядок - от сильного к слабому:
--
--   1. номер, который наши данные ЗНАЮТ, из всех, что отдал клиент (снимок
--      хранит их все в skillLineIDs, см. CharacterScanner);
--   2. главный номер, если он знаком;
--   3. имя профессии - через SkillLineByName, включая локализованное;
--   4. ничего. Тогда так и возвращается nil, а не выдуманный номер: ветка
--      обязана сказать «не смог сопоставить», а не делать вид, что сопоставила.
--
-- Возвращает line, откуда ("client-known" | "client" | "en" | "en-ci" | "codex").
function FS:ResolveSkillLine(prof)
    if type(prof) ~= "table" then return nil end
    for _, id in ipairs(prof.skillLineIDs or {}) do
        if FS:KnowsSkillLine(id) then return tonumber(id), "client-known" end
    end
    local main = tonumber(prof.skillLineID)
    if main and FS:KnowsSkillLine(main) then return main, "client-known" end
    local byName, how = FS:SkillLineByName(prof.name)
    if byName then return byName, how end
    return nil
end

-- Короткие поля для раздела dataVersions в диагностике: по ним видно, насколько
-- устарели наши собственные данные, без разбора всей таблицы PROVENANCE.
FS.BUILT = "2026-11-16"
FS.ORIGIN = "Mastercraft 1.9.9 + Wowhead Forever (dataEnv=16), сверено выборочно"

FS.PROVENANCE = {
    collectedAt   = "2026-11-16",
    mastercraft   = "1.9.9",
    wowheadBranch = "forever (dataEnv=16)",
    clientBuild   = "1.60.1 / Interface 16001",
    note          = "ruRU client; vendor set narrowed to a Horde 1-60 tailor/enchanter",
}

-- Confidence per table, so callers can label advice honestly instead of
-- presenting everything as fact. Keys are ns.CONF values.
FS.CONFIDENCE = {
    VENDOR_PLACES  = "CACHED",   -- coords verified against Wowhead Forever, sampled
    MAT_VENDORS    = "CACHED",
    RECIPE_VENDORS = "CACHED",
    ENCHANT_SLOTS  = "CACHED",   -- derived from the full Forever enchant list
    -- No entry for profession ranks on purpose: there is no rank table here any
    -- more, and the skill ceiling is read from the client, not from this file.
    -- See FS.SKILL_CAP below.
    DISENCHANT     = "ESTIMATE", -- probabilities are Classic-derived, not Forever
}

-- MAT_VENDORS[itemID] = { npcID, ... }
--
-- Only materials a tailor or enchanter buys for cash, and only vendors worth
-- walking to: at most one per zone, Horde first, then neutral, then Alliance.
-- Mastercraft lists up to 122 vendors for a single thread; that is a database,
-- not a route, so this is the trimmed version. The full lists stay in
-- Mastercraft if the player has it - see FS.TRIMMED_FROM for the original counts.
FS.MAT_VENDORS = {
    -- dye
    [2324] = { 3364, 4561, 3005, 3168, 3081, 2118, 3482, 2381, 3499 },  -- Bleach
    [2325] = { 3364, 4561, 3005, 12943, 3485, 3954, 2394, 12245 },  -- Black Dye
    [2604] = { 3364, 4561, 3005, 3168, 3081, 2118, 3482, 3954, 12245 },  -- Red Dye
    [2605] = { 3364, 4561, 3005, 12943, 3482, 3958, 2394, 2670 },  -- Green Dye
    [4340] = { 3364, 4561, 3005, 12943, 3485, 3954, 2394, 12245 },  -- Gray Dye
    [4341] = { 3364, 4561, 3005, 12943, 3485, 3954, 2394, 12245 },  -- Yellow Dye
    [4342] = { 3364, 4561, 3005, 12943, 3485, 3954, 2394, 12245 },  -- Purple Dye
    [6260] = { 3364, 4561, 3005, 3168, 3081, 2118, 3482, 3958, 2670 },  -- Blue Dye
    [6261] = { 3364, 4577, 3005, 12943, 3485, 3958, 2394, 2670 },  -- Orange Dye
    [10290] = { 3364, 4577, 3005, 12943, 3485, 3958, 2394, 2670 },  -- Pink Dye
    -- ench
    [4470] = { 3313, 4553, 3012, 3164, 3076, 2134, 3481, 4084, 3498 },  -- Simple Wood
    [6217] = { 3346, 4561, 3012, 3168, 3081, 2118, 3482, 3954, 3499 },  -- Copper Rod
    [10938] = { 3346, 4617, 3012, 5695, 5757, 257004, 15419, 1318 },  -- Lesser Magic Essence
    [10940] = { 3346, 4617, 3012, 5695, 5757, 257004, 15419, 1318 },  -- Strange Dust
    [11291] = { 3313, 4553, 3012, 8307, 5757, 4082, 3962, 3498 },  -- Star Wood
    [17034] = { 3323, 4562, 8361, 3490, 4083, 3970, 3542, 29537 },  -- Maple Seed
    [17035] = { 3323, 4562, 8361, 3490, 4083, 3970, 3542, 29537 },  -- Stranglethorn Seed
    [247786] = { 3346, 4617, 3012, 5695, 5757, 257004, 15419, 1318 },  -- Mote of Magic
    -- forever
    [249391] = { 263384 },  -- Pyrite
    [249399] = { 263384 },  -- Frilled Lichen
    [249427] = { 263384 },  -- Pristine Leather
    -- thread
    [2320] = { 3364, 4561, 3005, 3168, 3081, 2118, 3482, 3954, 3499 },  -- Coarse Thread
    [2321] = { 3364, 4561, 3005, 12943, 3482, 3556, 12043, 3954, 3499 },  -- Fine Thread
    [4291] = { 3364, 4561, 3005, 12943, 3485, 3954, 2393, 12245 },  -- Silken Thread
    [8343] = { 3364, 4561, 3005, 12943, 3485, 3954, 2394, 12245 },  -- Heavy Silken Thread
    [14341] = { 3364, 4577, 3005, 12943, 3485, 3958, 2394, 2670 },  -- Rune Thread
    -- vial
    [3371] = { 3334, 4561, 3010, 3168, 3081, 2118, 3482, 3954, 14847 },  -- Empty Vial
    [3372] = { 3334, 4561, 3010, 14847, 3548, 3490, 3551, 3954 },  -- Leaded Vial
}

FS.TRIMMED_FROM = {  -- itemID -> how many vendors the source actually lists
    [2324] = 73,
    [2325] = 85,
    [2604] = 100,
    [2605] = 71,
    [4340] = 85,
    [4341] = 85,
    [4342] = 85,
    [6260] = 79,
    [6261] = 56,
    [10290] = 56,
    [4470] = 100,
    [6217] = 67,
    [10938] = 12,
    [10940] = 12,
    [11291] = 76,
    [17034] = 36,
    [17035] = 36,
    [247786] = 12,
    [249391] = 1,
    [249399] = 1,
    [249427] = 1,
    [2320] = 122,
    [2321] = 104,
    [4291] = 94,
    [8343] = 85,
    [14341] = 56,
    [3371] = 112,
    [3372] = 97,
}

-- VENDOR_PLACES[npcID] = { name, faction, uiMapID, x, y, zone, tag }
--
-- faction: "H" Horde only, "A" Alliance only, "" either. x/y are 0-100 map
-- percentages, the same scale the client's map APIs use. `zone` is a label for
-- the player; uiMapID is what the code should navigate by. Those two disagree
-- for at least one NPC on the Forever-new maps - see the report - so never
-- derive a map from the zone string.
FS.VENDOR_PLACES = {
    [3313] = { en = "Trak'gen", faction = "H", uiMapID = 1454, x = 48, y = 80.2, zone = "Orgrimmar", tag = "General Goods Merchant" },
    [3323] = { en = "Horthus", faction = "H", uiMapID = 1454, x = 45.4, y = 56.4, zone = "Orgrimmar", tag = "Reagents Vendor" },
    [3334] = { en = "Rekkul", faction = "H", uiMapID = 1454, x = 42.2, y = 49.4, zone = "Orgrimmar", tag = "Poison Vendor" },
    [3346] = { en = "Kithas", faction = "H", uiMapID = 1454, x = 53.4, y = 37.2, zone = "Orgrimmar", tag = "Enchanting Supplies" },
    [3364] = { en = "Borya", faction = "H", uiMapID = 1454, x = 63, y = 51.2, zone = "Orgrimmar", tag = "Tailoring Supplies" },
    [258463] = { en = "Darah", faction = "H", uiMapID = 1454, x = 63.4, y = 50.4, zone = "Orgrimmar", tag = "Recipe Vendor" },
    [4553] = { en = "Ronald Burch", faction = "H", uiMapID = 1458, x = 62.4, y = 43.4, zone = "Undercity", tag = "Cooking Supplier" },
    [4561] = { en = "Daniel Bartlett", faction = "H", uiMapID = 1458, x = 64, y = 38.8, zone = "Undercity", tag = "General Trade Supplier" },
    [4562] = { en = "Thomas Mordan", faction = "H", uiMapID = 1458, x = 69.4, y = 39.2, zone = "Undercity", tag = "Reagent Vendor" },
    [4577] = { en = "Millie Gregorian", faction = "H", uiMapID = 1458, x = 70.4, y = 29.4, zone = "Undercity", tag = "Tailoring Supplies" },
    [4617] = { en = "Thaddeus Webb", faction = "H", uiMapID = 1458, x = 61.4, y = 60.4, zone = "Undercity", tag = "Enchanting Supplies" },
    [258415] = { en = "Angela Ward", faction = "H", uiMapID = 1458, x = 70.4, y = 29.4, zone = "Undercity", tag = "Tailoring Recipes" },
    [3005] = { en = "Mahu", faction = "H", uiMapID = 1456, x = 43.4, y = 43.8, zone = "Thunder Bluff", tag = "Leatherworking & Tailoring Supplies" },
    [3010] = { en = "Mani Winterhoof", faction = "H", uiMapID = 1456, x = 47, y = 33.4, zone = "Thunder Bluff", tag = "Alchemy Supplies" },
    [3012] = { en = "Nata Dawnstrider", faction = "H", uiMapID = 1456, x = 45, y = 38.4, zone = "Thunder Bluff", tag = "Enchanting Supplies" },
    [8361] = { en = "Chepi", faction = "H", uiMapID = 1456, x = 36.4, y = 54.4, zone = "Thunder Bluff", tag = "Reagent Vendor" },
    [258466] = { en = "Boramu", faction = "H", uiMapID = 1456, x = 44, y = 44.8, zone = "Thunder Bluff", tag = "Tailoring Recipes" },
    [3164] = { en = "Jark", faction = "H", uiMapID = 1411, x = 54.2, y = 42.2, zone = "Durotar", tag = "General Goods" },
    [3168] = { en = "Flakk", faction = "H", uiMapID = 1411, x = 52.8, y = 42, zone = "Durotar", tag = "Trade Supplies" },
    [3076] = { en = "Moorat Longstride", faction = "H", uiMapID = 1412, x = 45.2, y = 61.4, zone = "Mulgore", tag = "General Goods" },
    [3081] = { en = "Wunna Darkmane", faction = "H", uiMapID = 1412, x = 45.4, y = 61.8, zone = "Mulgore", tag = "Trade Goods" },
    [14847] = { en = "Professor Thaddeus Paleo", faction = "", uiMapID = 1412, x = 36.4, y = 38, zone = "Mulgore", tag = "Darkmoon Faire Cards & Exotic Goods" },
    [264078] = { en = "Sutara Plainstalker", faction = "", uiMapID = 1412, x = 34.4, y = 22.8, zone = "Mulgore", tag = "Quartermaster" },
    [2118] = { en = "Abigail Shiel", faction = "H", uiMapID = 1420, x = 61, y = 52.4, zone = "Tirisfal Glades", tag = "Trade Supplies" },
    [2134] = { en = "Mrs. Winters", faction = "H", uiMapID = 1420, x = 61, y = 52.4, zone = "Tirisfal Glades", tag = "General Supplies" },
    [3548] = { en = "Selina Weston", faction = "H", uiMapID = 1420, x = 61.8, y = 50, zone = "Tirisfal Glades", tag = "Alchemy & Herbalism Supplies" },
    [5695] = { en = "Vance Undergloom", faction = "H", uiMapID = 1420, x = 61.6, y = 51.6, zone = "Tirisfal Glades", tag = "Journeyman Enchanter" },
    [12943] = { en = "Werg Thickblade", faction = "H", uiMapID = 1420, x = 83.2, y = 69.6, zone = "Tirisfal Glades", tag = "Leatherworking Supplies" },
    [3481] = { en = "Barg", faction = "H", uiMapID = 1413, x = 51.6, y = 30, zone = "The Barrens", tag = "General Supplies" },
    [3482] = { en = "Tari'qa", faction = "H", uiMapID = 1413, x = 51.6, y = 30, zone = "The Barrens", tag = "Trade Supplies" },
    [3485] = { en = "Wrahk", faction = "H", uiMapID = 1413, x = 52.2, y = 31.6, zone = "The Barrens", tag = "Tailoring Supplies" },
    [3490] = { en = "Hula'mahi", faction = "H", uiMapID = 1413, x = 51.4, y = 30.2, zone = "The Barrens", tag = "Reagents and Herbs" },
    [3498] = { en = "Jazzik", faction = "", uiMapID = 1413, x = 61.8, y = 38.8, zone = "The Barrens", tag = "General Supplies" },
    [3499] = { en = "Ranik", faction = "", uiMapID = 1413, x = 61.8, y = 38.6, zone = "The Barrens", tag = "Trade Supplies" },
    [5944] = { en = "Yonada", faction = "H", uiMapID = 1413, x = 45, y = 59.2, zone = "The Barrens", tag = "Tailoring & Leatherworking Supplies" },
    [8307] = { en = "Tarban Hearthgrain", faction = "H", uiMapID = 1413, x = 55, y = 32, zone = "The Barrens", tag = "Baker" },
    [248199] = { en = "Beneris", faction = "", uiMapID = 1413, x = 49.6, y = 29.8, zone = "The Barrens", tag = "Enchanting" },
    [248202] = { en = "Jim'bek", faction = "", uiMapID = 1413, x = 49.6, y = 29.4, zone = "The Barrens", tag = "Tailor" },
    [3551] = { en = "Patrice Dwyer", faction = "H", uiMapID = 1421, x = 43, y = 41.8, zone = "Silverpine Forest", tag = "Poison Supplies" },
    [3556] = { en = "Andrew Hilbert", faction = "H", uiMapID = 1421, x = 43.2, y = 40.6, zone = "Silverpine Forest", tag = "Trade Goods" },
    [5757] = { en = "Lilly", faction = "H", uiMapID = 1421, x = 43, y = 50.8, zone = "Silverpine Forest", tag = "Enchanting Supplies" },
    [5758] = { en = "Leo Sarn", faction = "H", uiMapID = 1421, x = 53.8, y = 82.6, zone = "Silverpine Forest", tag = "Enchanting Supplies" },
    [4082] = { en = "Grawnal", faction = "H", uiMapID = 1442, x = 45.8, y = 58.6, zone = "Stonetalon Mountains", tag = "General Goods" },
    [4083] = { en = "Jeeda", faction = "H", uiMapID = 1442, x = 47.4, y = 61.8, zone = "Stonetalon Mountains", tag = "Apprentice Witch Doctor" },
    [4084] = { en = "Chylina", faction = "A", uiMapID = 1442, x = 35.4, y = 6.2, zone = "Stonetalon Mountains", tag = "General Supplies" },
    [12043] = { en = "Kulwia", faction = "H", uiMapID = 1442, x = 45.4, y = 59.4, zone = "Stonetalon Mountains", tag = "Trade Supplies" },
    [3954] = { en = "Dalria", faction = "A", uiMapID = 1440, x = 35, y = 52, zone = "Ashenvale", tag = "Trade Goods" },
    [3958] = { en = "Lardan", faction = "A", uiMapID = 1440, x = 34.8, y = 49.8, zone = "Ashenvale", tag = "Leatherworking Supplies" },
    [3962] = { en = "Haljan Oakheart", faction = "A", uiMapID = 1440, x = 34.8, y = 50.8, zone = "Ashenvale", tag = "General Goods" },
    [3970] = { en = "Llana", faction = "A", uiMapID = 1440, x = 35, y = 48.4, zone = "Ashenvale", tag = "Reagent Supplies" },
    [2381] = { en = "Micha Yance", faction = "A", uiMapID = 1424, x = 49, y = 55, zone = "Hillsbrad Foothills", tag = "Trade Goods" },
    [2393] = { en = "Christoph Jeffcoat", faction = "H", uiMapID = 1424, x = 62.2, y = 19, zone = "Hillsbrad Foothills", tag = "Tradesman" },
    [2394] = { en = "Mallen Swain", faction = "H", uiMapID = 1424, x = 62, y = 21, zone = "Hillsbrad Foothills", tag = "Tailoring Supplies" },
    [3537] = { en = "Zixil", faction = "", uiMapID = 1424, x = 50.4, y = 50.8, zone = "Hillsbrad Foothills", tag = "Merchant Supreme" },
    [3542] = { en = "Jaysin Lanyda", faction = "A", uiMapID = 1424, x = 50.8, y = 59, zone = "Hillsbrad Foothills", tag = "Poisons & Reagents" },
    [12245] = { en = "Vendor-Tron 1000", faction = "", uiMapID = 1443, x = 60.2, y = 38.2, zone = "Desolace", tag = "" },
    [12246] = { en = "Super-Seller 680", faction = "", uiMapID = 1443, x = 40.4, y = 79.2, zone = "Desolace", tag = "" },
    [253139] = { en = "Gorhak", faction = "", uiMapID = 1443, x = 66.2, y = 79.4, zone = "Desolace", tag = "Magram Clan Quartermaster" },
    [253140] = { en = "Molkar", faction = "", uiMapID = 1443, x = 35.6, y = 92, zone = "Desolace", tag = "Gelkis Clan Quartermaster" },
    [6567] = { en = "Ghok'kah", faction = "H", uiMapID = 1445, x = 35.2, y = 30.8, zone = "Dustwallow Marsh", tag = "Tailoring Supplies" },
    [6574] = { en = "Jun'ha", faction = "H", uiMapID = 1417, x = 72.6, y = 36.4, zone = "Arathi Highlands", tag = "Tailoring Supplies" },
    [2670] = { en = "Xizk Goodstitch", faction = "", uiMapID = 1434, x = 28.6, y = 76.8, zone = "Stranglethorn Vale", tag = "Tailoring Supplies" },
    [6568] = { en = "Vizzklick", faction = "", uiMapID = 1446, x = 51, y = 27.4, zone = "Tanaris", tag = "Tailoring Supplies" },
    [6576] = { en = "Brienna Starglow", faction = "A", uiMapID = 1444, x = 89, y = 45.8, zone = "Feralas", tag = "Tailoring Supplies" },
    [251991] = { en = "Taleen Shimmerthread", faction = "", uiMapID = 2521, x = 44.8, y = 44.2, zone = "Zephras Isle", tag = "Tailor" },
    [252380] = { en = "Othesia Evengale", faction = "", uiMapID = 2521, x = 64.4, y = 81, zone = "Zephras Isle", tag = "Tailor" },
    [254151] = { en = "Vayn Moongaze", faction = "", uiMapID = 2521, x = 63.8, y = 36, zone = "Zephras Isle", tag = "" },
    [257004] = { en = "Eaysaa Brightgust", faction = "", uiMapID = 2521, x = 59.2, y = 76.2, zone = "Zephras Isle", tag = "Enchanter" },
    [257020] = { en = "Nasalanna Windsinger", faction = "", uiMapID = 2521, x = 43.2, y = 43.2, zone = "Zephras Isle", tag = "Enchanter" },
    [260570] = { en = "Stitch Pinwizzle", faction = "", uiMapID = 2548, x = 77.2, y = 51.4, zone = "Riverglades", tag = "Tailoring Supplies" },
    [263384] = { en = "Mister Graphed", faction = "", uiMapID = 2548, x = 78.2, y = 51.8, zone = "Riverglades", tag = "Agent of the Black Market" },
    [29537] = { en = "Darahir", faction = "", uiMapID = 1416, x = 21.6, y = 69, zone = "Alterac Mountains", tag = "Reagents & Magical Goods" },
    [251997] = { en = "Norvin Alderman", faction = "", uiMapID = 1416, x = 16, y = 65.4, zone = "Alterac Mountains", tag = "Cloaks" },
    [11189] = { en = "Qia", faction = "", uiMapID = 1452, x = 61.2, y = 37.2, zone = "Winterspring", tag = "Trade Goods Supplies" },
    [7940] = { en = "Darnall", faction = "", uiMapID = 1450, x = 51.4, y = 33.2, zone = "Moonglade", tag = "Tailoring Supplies" },
    [15419] = { en = "Kania", faction = "", uiMapID = 1451, x = 52, y = 39.4, zone = "Silithus", tag = "Enchanting Supplier" },
    [1318] = { en = "Jessara Cordell", faction = "A", uiMapID = 1453, x = 53, y = 74, zone = "Stormwind City", tag = "Enchanting Supplies" },
    [1347] = { en = "Alexandra Bolero", faction = "A", uiMapID = 1453, x = 53.2, y = 81.6, zone = "Stormwind City", tag = "Tailoring Supplies" },
    [5158] = { en = "Tilli Thistlefuzz", faction = "A", uiMapID = 1455, x = 60.4, y = 44.2, zone = "Ironforge", tag = "Enchanting Supplies" },
    [8681] = { en = "Outfitter Eric", faction = "A", uiMapID = 1455, x = 43.2, y = 29.2, zone = "Ironforge", tag = "Speciality Tailoring Supplies" },
    [4168] = { en = "Elynna", faction = "A", uiMapID = 1457, x = 64.2, y = 21.4, zone = "Darnassus", tag = "Tailoring Supplies" },
    [4228] = { en = "Vaean", faction = "A", uiMapID = 1457, x = 58.4, y = 14.4, zone = "Darnassus", tag = "Enchanting Supplies" },
    [242498] = { en = "Reagent Bot", faction = "", uiMapID = 1436, x = 33.2, y = 56, zone = "Westfall", tag = "" },
    [254695] = { en = "Repair Bot", faction = "", uiMapID = 1436, x = 37, y = 88.6, zone = "Westfall", tag = "" },
    [1474] = { en = "Rann Flamespinner", faction = "A", uiMapID = 1432, x = 36, y = 46, zone = "Loch Modan", tag = "Tailoring Supplies" },
    [3096] = { en = "Captured Servant of Azora", faction = "", uiMapID = 1433, x = 69.2, y = 79.4, zone = "Redridge Mountains", tag = "Specialist Tailoring Supplies" },
    [256732] = { en = "Alynsia", faction = "", uiMapID = 1433, x = 11.2, y = 71.4, zone = "Redridge Mountains", tag = "Enchanter" },
    [256735] = { en = "Mivin Shadowweave", faction = "", uiMapID = 1433, x = 10, y = 72.2, zone = "Redridge Mountains", tag = "Tailor" },
    [2668] = { en = "Danielle Zipstitch", faction = "A", uiMapID = 1431, x = 75.8, y = 45.4, zone = "Duskwood", tag = "Tailoring Supplies" },
    [2669] = { en = "Sheri Zipstitch", faction = "A", uiMapID = 1431, x = 75.6, y = 45.4, zone = "Duskwood", tag = "Tailoring Supplies" },
    [4189] = { en = "Valdaron", faction = "A", uiMapID = 1439, x = 38, y = 40.6, zone = "Darkshore", tag = "Tailoring Supplies" },
    [1454] = { en = "Jennabink Powerseam", faction = "A", uiMapID = 1437, x = 8, y = 55.8, zone = "Wetlands", tag = "Tailoring Supplies & Specialty Goods" },
}

-- RECIPE_VENDORS[npcID] = { { prof, en, skill, pattern }, ... }
--
-- Who sells tailoring patterns and enchanting formulae usable at or below skill
-- 235. `pattern` is the recipe ITEM id (what you buy); skill is what you need to
-- learn it. Vendors selling only one recipe are left out unless Horde-reachable.
-- Two Forever-only vendors carry most of it: see the report.
FS.RECIPE_VENDORS = {
    [3364] = {  -- Borya (Orgrimmar), 9 recipes
        { prof = "Tailoring", en = "Linen Reagent Bag", skill = 5, pattern = 253665, note = "Sold by Xizk Goodstitch - Stranglethorn" },
        { prof = "Tailoring", en = "Blue Linen Vest", skill = 35, pattern = 6270, note = "Sold by Tharynn Bouden (A) - Elwynn Forest - limited stock" },
        { prof = "Tailoring", en = "Woolen Reagent Bag", skill = 70, pattern = 253668, note = "Sold by Xizk Goodstitch - Stranglethorn" },
        { prof = "Tailoring", en = "Blue Overalls", skill = 75, pattern = 6274, note = "Sold by Gina MacGregor (A) - Westfall - limited stock" },
        { prof = "Tailoring", en = "Red Woolen Bag", skill = 90, pattern = 5772, note = "Sold by Zixil - Hillsbrad - limited stock" },
        { prof = "Tailoring", en = "Invoker's Mantle", skill = 150, pattern = 215370, note = "Sold by Elynna (A) - Darnassus" },
        { prof = "Tailoring", en = "Invoker's Cord", skill = 150, pattern = 215369, note = "Sold by Elynna (A) - Darnassus" },
        { prof = "Tailoring", en = "Lavender Mageweave Shirt", skill = 190, pattern = 10314, note = "Sold by Outfitter Eric (A) - Ironforge - limited stock" },
        { prof = "Tailoring", en = "Pink Mageweave Shirt", skill = 195, pattern = 10317, note = "Sold by Outfitter Eric (A) - Ironforge - limited stock" },
    },
    [3346] = {  -- Kithas (Orgrimmar), 7 recipes
        { prof = "Enchanting", en = "Minor Wizard Oil", skill = 5, pattern = 20758, note = "Sold by Kania - Silithus" },
        { prof = "Enchanting", en = "Enchant Chest - Minor Intellect", skill = 20, pattern = 6342, note = "Sold by Kania - Silithus" },
        { prof = "Enchanting", en = "Enchant Chest - Lesser Intellect", skill = 80, pattern = 6346, note = "Sold by Kithas (H) - Orgrimmar - limited stock" },
        { prof = "Enchanting", en = "Enchant 2H Weapon - Lesser Intellect", skill = 100, pattern = 6349, note = "Sold by Tilli Thistlefuzz (A) - Ironforge - limited stock" },
        { prof = "Enchanting", en = "Minor Mana Oil", skill = 150, pattern = 20752, note = "Sold by Kania - Silithus" },
        { prof = "Enchanting", en = "Lesser Wizard Oil", skill = 200, pattern = 20753, note = "Sold by Kania - Silithus" },
        { prof = "Tailoring", en = "Enchanted Mageweave Pouch", skill = 190, pattern = 22307, note = "Sold by Kania - Silithus" },
    },
    [258463] = {  -- Darah (Orgrimmar), 2 recipes
        { prof = "Tailoring", en = "Linen Reagent Bag", skill = 5, pattern = 253665, note = "Sold by Xizk Goodstitch - Stranglethorn" },
        { prof = "Tailoring", en = "Woolen Reagent Bag", skill = 70, pattern = 253668, note = "Sold by Xizk Goodstitch - Stranglethorn" },
    },
    [4577] = {  -- Millie Gregorian (Undercity), 7 recipes
        { prof = "Tailoring", en = "Linen Reagent Bag", skill = 5, pattern = 253665, note = "Sold by Xizk Goodstitch - Stranglethorn" },
        { prof = "Tailoring", en = "Woolen Reagent Bag", skill = 70, pattern = 253668, note = "Sold by Xizk Goodstitch - Stranglethorn" },
        { prof = "Tailoring", en = "Red Woolen Bag", skill = 90, pattern = 5772, note = "Sold by Zixil - Hillsbrad - limited stock" },
        { prof = "Tailoring", en = "Greater Adept's Robe", skill = 90, pattern = 6275, note = "Sold by Ranik - Barrens - limited stock" },
        { prof = "Tailoring", en = "Tuxedo Jacket", skill = 140, pattern = 10326, note = "Sold by Outfitter Eric (A) - Ironforge - limited stock" },
        { prof = "Tailoring", en = "Tuxedo Pants", skill = 140, pattern = 10323, note = "Sold by Outfitter Eric (A) - Ironforge - limited stock" },
        { prof = "Tailoring", en = "Tuxedo Shirt", skill = 200, pattern = 10321, note = "Sold by Outfitter Eric (A) - Ironforge - limited stock" },
    },
    [4617] = {  -- Thaddeus Webb (Undercity), 5 recipes
        { prof = "Enchanting", en = "Minor Wizard Oil", skill = 5, pattern = 20758, note = "Sold by Kania - Silithus" },
        { prof = "Enchanting", en = "Enchant Chest - Minor Intellect", skill = 20, pattern = 6342, note = "Sold by Kania - Silithus" },
        { prof = "Enchanting", en = "Minor Mana Oil", skill = 150, pattern = 20752, note = "Sold by Kania - Silithus" },
        { prof = "Enchanting", en = "Lesser Wizard Oil", skill = 200, pattern = 20753, note = "Sold by Kania - Silithus" },
        { prof = "Tailoring", en = "Enchanted Mageweave Pouch", skill = 190, pattern = 22307, note = "Sold by Kania - Silithus" },
    },
    [258415] = {  -- Angela Ward (Undercity), 2 recipes
        { prof = "Tailoring", en = "Linen Reagent Bag", skill = 5, pattern = 253665, note = "Sold by Xizk Goodstitch - Stranglethorn" },
        { prof = "Tailoring", en = "Woolen Reagent Bag", skill = 70, pattern = 253668, note = "Sold by Xizk Goodstitch - Stranglethorn" },
    },
    [3012] = {  -- Nata Dawnstrider (Thunder Bluff), 7 recipes
        { prof = "Enchanting", en = "Minor Wizard Oil", skill = 5, pattern = 20758, note = "Sold by Kania - Silithus" },
        { prof = "Enchanting", en = "Enchant Chest - Minor Intellect", skill = 20, pattern = 6342, note = "Sold by Kania - Silithus" },
        { prof = "Enchanting", en = "Enchant 2H Weapon - Lesser Intellect", skill = 100, pattern = 6349, note = "Sold by Tilli Thistlefuzz (A) - Ironforge - limited stock" },
        { prof = "Enchanting", en = "Enchant Boots - Minor Agility", skill = 125, pattern = 6377, note = "Sold by Zixil - Hillsbrad - limited stock" },
        { prof = "Enchanting", en = "Minor Mana Oil", skill = 150, pattern = 20752, note = "Sold by Kania - Silithus" },
        { prof = "Enchanting", en = "Lesser Wizard Oil", skill = 200, pattern = 20753, note = "Sold by Kania - Silithus" },
        { prof = "Tailoring", en = "Enchanted Mageweave Pouch", skill = 190, pattern = 22307, note = "Sold by Kania - Silithus" },
    },
    [3005] = {  -- Mahu (Thunder Bluff), 6 recipes
        { prof = "Tailoring", en = "Linen Reagent Bag", skill = 5, pattern = 253665, note = "Sold by Xizk Goodstitch - Stranglethorn" },
        { prof = "Tailoring", en = "Red Linen Bag", skill = 50, pattern = 5771, note = "Sold by Gina MacGregor (A) - Westfall - limited stock" },
        { prof = "Tailoring", en = "Woolen Reagent Bag", skill = 70, pattern = 253668, note = "Sold by Xizk Goodstitch - Stranglethorn" },
        { prof = "Tailoring", en = "Red Woolen Bag", skill = 90, pattern = 5772, note = "Sold by Zixil - Hillsbrad - limited stock" },
        { prof = "Tailoring", en = "White Wedding Dress", skill = 140, pattern = 10325, note = "Sold by Alexandra Bolero (A) - Stormwind - limited stock" },
        { prof = "Tailoring", en = "Orange Martial Shirt", skill = 185, pattern = 10311, note = "Sold by Elynna (A) - Darnassus - limited stock" },
    },
    [258466] = {  -- Boramu (Thunder Bluff), 2 recipes
        { prof = "Tailoring", en = "Linen Reagent Bag", skill = 5, pattern = 253665, note = "Sold by Xizk Goodstitch - Stranglethorn" },
        { prof = "Tailoring", en = "Woolen Reagent Bag", skill = 70, pattern = 253668, note = "Sold by Xizk Goodstitch - Stranglethorn" },
    },
    [264078] = {  -- Sutara Plainstalker (Mulgore), 2 recipes
        { prof = "Tailoring", en = "Cloudy Stormsewn Cowl", skill = 175, pattern = 276982, note = "Sold by Sutara Plainstalker (H) - Mulgore" },
        { prof = "Tailoring", en = "Cloudy Stormsewn Epaulets", skill = 175, pattern = 276983, note = "Sold by Sutara Plainstalker (H) - Mulgore" },
    },
    [248202] = {  -- Jim'bek (The Barrens), 67 recipes
        { prof = "Tailoring", en = "Silky Boots", skill = 60, pattern = 253892, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Shining Boots", skill = 60, pattern = 253900, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Shadow Boots", skill = 60, pattern = 253896, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Flame Boots", skill = 60, pattern = 253894, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Pristine Boots", skill = 60, pattern = 253890, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Pearly Boots", skill = 60, pattern = 253898, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Flame Gloves", skill = 75, pattern = 253918, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Silky Gloves", skill = 75, pattern = 253916, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Shadow Gloves", skill = 75, pattern = 253920, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Shining Gloves", skill = 75, pattern = 253924, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Pristine Gloves", skill = 75, pattern = 253914, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Pearly Gloves", skill = 75, pattern = 253922, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Shadow Sash", skill = 85, pattern = 253932, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Pristine Sash", skill = 85, pattern = 253926, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Silky Sash", skill = 85, pattern = 253928, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Shining Sash", skill = 85, pattern = 253936, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Flame Sash", skill = 85, pattern = 253930, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Pearly Sash", skill = 85, pattern = 253934, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Silky Circlet", skill = 100, pattern = 253952, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Shadow Circlet", skill = 100, pattern = 253956, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Pearly Circlet", skill = 100, pattern = 253958, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Shining Circlet", skill = 100, pattern = 253960, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Pristine Circlet", skill = 100, pattern = 253950, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Flame Circlet", skill = 100, pattern = 253954, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Pristine Gown", skill = 110, pattern = 253962, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Shining Gown", skill = 110, pattern = 253972, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Pearly Gown", skill = 110, pattern = 253970, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Flame Gown", skill = 110, pattern = 253966, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Silky Gown", skill = 110, pattern = 253964, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Shadow Gown", skill = 110, pattern = 253968, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Silky Leggings", skill = 125, pattern = 253990, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Shadow Leggings", skill = 125, pattern = 253994, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Shining Leggings", skill = 125, pattern = 253998, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Flame Leggings", skill = 125, pattern = 253992, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Pristine Leggings", skill = 125, pattern = 253988, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Pearly Leggings", skill = 125, pattern = 253996, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Frothing Handwraps", skill = 165, pattern = 254024, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Radiant Handwraps", skill = 165, pattern = 254032, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Golden Handwraps", skill = 165, pattern = 254030, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Fiery Handwraps", skill = 165, pattern = 254026, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Black Handwraps", skill = 165, pattern = 254028, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Mageweave Reagent Bag", skill = 190, pattern = 254036, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Netherflame Shoulders", skill = 195, pattern = 254054, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Netherlight Shoulders", skill = 195, pattern = 254060, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Netherfroth Shoulders", skill = 195, pattern = 254052, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Nethershine Shoulders", skill = 195, pattern = 254058, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Netherpearl Shoulders", skill = 195, pattern = 254056, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Nethergeld Shoulders", skill = 195, pattern = 254050, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Nethergeld Cuffs", skill = 205, pattern = 254062, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Nethershine Cuffs", skill = 205, pattern = 254070, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Netherflame Cuffs", skill = 205, pattern = 254066, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Netherfroth Cuffs", skill = 205, pattern = 254064, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Netherlight Cuffs", skill = 205, pattern = 254072, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Netherpearl Cuffs", skill = 205, pattern = 254068, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Frothing Waistcord", skill = 215, pattern = 254084, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Radiant Waistcord", skill = 215, pattern = 254092, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Gilded Waistcord", skill = 215, pattern = 254082, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Golden Waistcord", skill = 215, pattern = 254090, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Runecloth Reagent Bag", skill = 215, pattern = 254080, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Black Waistcord", skill = 215, pattern = 254088, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Fiery Waistcord", skill = 215, pattern = 254086, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Frothing Sandals", skill = 235, pattern = 254110, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Gilded Sandals", skill = 235, pattern = 254108, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Radiant Sandals", skill = 235, pattern = 254118, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Fiery Sandals", skill = 235, pattern = 254112, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Black Sandals", skill = 235, pattern = 254114, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Golden Sandals", skill = 235, pattern = 254116, note = "Sold by Mivin Shadowweave (A) - Redridge" },
    },
    [248199] = {  -- Beneris (The Barrens), 23 recipes
        { prof = "Enchanting", en = "Tenets of the Silver Hand", skill = 130, pattern = 249477, note = "Sold by Alynsia (A) - Redridge" },
        { prof = "Enchanting", en = "Mystic Mushroom", skill = 130, pattern = 249476, note = "Sold by Alynsia (A) - Redridge" },
        { prof = "Enchanting", en = "Polished Driftwood Icon", skill = 130, pattern = 249478, note = "Sold by Alynsia (A) - Redridge" },
        { prof = "Enchanting", en = "Soulstaff", skill = 140, pattern = 249483, note = "Sold by Alynsia (A) - Redridge" },
        { prof = "Enchanting", en = "Enchant Weapon - Recovery", skill = 140, pattern = 249480, note = "Sold by Alynsia (A) - Redridge" },
        { prof = "Enchanting", en = "Enchant Weapon - Insight", skill = 140, pattern = 249479, note = "Sold by Alynsia (A) - Redridge" },
        { prof = "Enchanting", en = "Orb of Souls", skill = 140, pattern = 249485, note = "Sold by Alynsia (A) - Redridge" },
        { prof = "Enchanting", en = "Orb of Mystic Insight", skill = 140, pattern = 249484, note = "Sold by Alynsia (A) - Redridge" },
        { prof = "Enchanting", en = "Glimmering Staff", skill = 140, pattern = 249482, note = "Sold by Alynsia (A) - Redridge" },
        { prof = "Enchanting", en = "Enchant Weapon - Revelation", skill = 140, pattern = 249481, note = "Sold by Alynsia (A) - Redridge" },
        { prof = "Enchanting", en = "Enchant Necklace - Healing Power", skill = 210, pattern = 249503, note = "Sold by Alynsia (A) - Redridge" },
        { prof = "Enchanting", en = "Enchant Necklace - Agility", skill = 210, pattern = 249504, note = "Sold by Alynsia (A) - Redridge" },
        { prof = "Enchanting", en = "Enchant Necklace - Deflection", skill = 210, pattern = 249505, note = "Sold by Alynsia (A) - Redridge" },
        { prof = "Enchanting", en = "Enchant Necklace - Strength", skill = 210, pattern = 249496, note = "Sold by Alynsia (A) - Redridge" },
        { prof = "Enchanting", en = "Talons of Wrath", skill = 210, pattern = 249493, note = "Sold by Alynsia (A) - Redridge" },
        { prof = "Enchanting", en = "Totem of Ancestral Protection", skill = 210, pattern = 249495, note = "Sold by Alynsia (A) - Redridge" },
        { prof = "Enchanting", en = "Libram of Invocation", skill = 210, pattern = 249494, note = "Sold by Alynsia (A) - Redridge" },
        { prof = "Enchanting", en = "Enchant Necklace - Spell Power", skill = 210, pattern = 249502, note = "Sold by Alynsia (A) - Redridge" },
        { prof = "Enchanting", en = "Twisting Essence Jar", skill = 220, pattern = 249509, note = "Sold by Alynsia (A) - Redridge" },
        { prof = "Enchanting", en = "Dreamstaff", skill = 220, pattern = 249507, note = "Sold by Alynsia (A) - Redridge" },
        { prof = "Enchanting", en = "Truesilver Conduit", skill = 220, pattern = 249508, note = "Sold by Alynsia (A) - Redridge" },
        { prof = "Enchanting", en = "Radiant Staff", skill = 220, pattern = 249506, note = "Sold by Alynsia (A) - Redridge" },
        { prof = "Enchanting", en = "Enchant Chest - Absorption", skill = 220, pattern = 249510, note = "Sold by Alynsia (A) - Redridge" },
    },
    [3485] = {  -- Wrahk (The Barrens), 5 recipes
        { prof = "Tailoring", en = "Linen Reagent Bag", skill = 5, pattern = 253665, note = "Sold by Xizk Goodstitch - Stranglethorn" },
        { prof = "Tailoring", en = "Blue Linen Vest", skill = 35, pattern = 6270, note = "Sold by Tharynn Bouden (A) - Elwynn Forest - limited stock" },
        { prof = "Tailoring", en = "Blue Linen Robe", skill = 45, pattern = 6272, note = "Sold by Ranik - Barrens - limited stock" },
        { prof = "Tailoring", en = "Woolen Reagent Bag", skill = 70, pattern = 253668, note = "Sold by Xizk Goodstitch - Stranglethorn" },
        { prof = "Tailoring", en = "Red Woolen Bag", skill = 90, pattern = 5772, note = "Sold by Zixil - Hillsbrad - limited stock" },
    },
    [5944] = {  -- Yonada (The Barrens), 4 recipes
        { prof = "Tailoring", en = "Linen Reagent Bag", skill = 5, pattern = 253665, note = "Sold by Xizk Goodstitch - Stranglethorn" },
        { prof = "Tailoring", en = "Woolen Reagent Bag", skill = 70, pattern = 253668, note = "Sold by Xizk Goodstitch - Stranglethorn" },
        { prof = "Tailoring", en = "Blue Overalls", skill = 75, pattern = 6274, note = "Sold by Gina MacGregor (A) - Westfall - limited stock" },
        { prof = "Tailoring", en = "Red Woolen Bag", skill = 90, pattern = 5772, note = "Sold by Zixil - Hillsbrad - limited stock" },
    },
    [3499] = {  -- Ranik (The Barrens), 2 recipes
        { prof = "Tailoring", en = "Blue Linen Robe", skill = 45, pattern = 6272, note = "Sold by Ranik - Barrens - limited stock" },
        { prof = "Tailoring", en = "Greater Adept's Robe", skill = 90, pattern = 6275, note = "Sold by Ranik - Barrens - limited stock" },
    },
    [5757] = {  -- Lilly (Silverpine Forest), 6 recipes
        { prof = "Enchanting", en = "Minor Wizard Oil", skill = 5, pattern = 20758, note = "Sold by Kania - Silithus" },
        { prof = "Enchanting", en = "Enchant Chest - Minor Intellect", skill = 20, pattern = 6342, note = "Sold by Kania - Silithus" },
        { prof = "Enchanting", en = "Enchant Chest - Lesser Intellect", skill = 80, pattern = 6346, note = "Sold by Kithas (H) - Orgrimmar - limited stock" },
        { prof = "Enchanting", en = "Minor Mana Oil", skill = 150, pattern = 20752, note = "Sold by Kania - Silithus" },
        { prof = "Enchanting", en = "Lesser Wizard Oil", skill = 200, pattern = 20753, note = "Sold by Kania - Silithus" },
        { prof = "Tailoring", en = "Enchanted Mageweave Pouch", skill = 190, pattern = 22307, note = "Sold by Kania - Silithus" },
    },
    [5758] = {  -- Leo Sarn (Silverpine Forest), 6 recipes
        { prof = "Enchanting", en = "Minor Wizard Oil", skill = 5, pattern = 20758, note = "Sold by Kania - Silithus" },
        { prof = "Enchanting", en = "Enchant Chest - Minor Intellect", skill = 20, pattern = 6342, note = "Sold by Kania - Silithus" },
        { prof = "Enchanting", en = "Enchant 2H Weapon - Lesser Intellect", skill = 100, pattern = 6349, note = "Sold by Tilli Thistlefuzz (A) - Ironforge - limited stock" },
        { prof = "Enchanting", en = "Minor Mana Oil", skill = 150, pattern = 20752, note = "Sold by Kania - Silithus" },
        { prof = "Enchanting", en = "Lesser Wizard Oil", skill = 200, pattern = 20753, note = "Sold by Kania - Silithus" },
        { prof = "Tailoring", en = "Enchanted Mageweave Pouch", skill = 190, pattern = 22307, note = "Sold by Kania - Silithus" },
    },
    [3556] = {  -- Andrew Hilbert (Silverpine Forest), 2 recipes
        { prof = "Tailoring", en = "Blue Linen Robe", skill = 45, pattern = 6272, note = "Sold by Ranik - Barrens - limited stock" },
        { prof = "Tailoring", en = "Red Linen Bag", skill = 50, pattern = 5771, note = "Sold by Gina MacGregor (A) - Westfall - limited stock" },
    },
    [12043] = {  -- Kulwia (Stonetalon Mountains), 2 recipes
        { prof = "Enchanting", en = "Enchant Cloak - Minor Agility", skill = 110, pattern = 11039, note = "Sold by Dalria (A) - Ashenvale - limited stock" },
        { prof = "Enchanting", en = "Enchant Bracer - Lesser Strength", skill = 140, pattern = 11101, note = "Sold by Dalria (A) - Ashenvale - limited stock" },
    },
    [2394] = {  -- Mallen Swain (Hillsbrad Foothills), 4 recipes
        { prof = "Tailoring", en = "Linen Reagent Bag", skill = 5, pattern = 253665, note = "Sold by Xizk Goodstitch - Stranglethorn" },
        { prof = "Tailoring", en = "Woolen Reagent Bag", skill = 70, pattern = 253668, note = "Sold by Xizk Goodstitch - Stranglethorn" },
        { prof = "Tailoring", en = "Blue Overalls", skill = 75, pattern = 6274, note = "Sold by Gina MacGregor (A) - Westfall - limited stock" },
        { prof = "Tailoring", en = "Dark Silk Shirt", skill = 120, pattern = 6401, note = "Sold by Super-Seller 680 - Desolace" },
    },
    [3537] = {  -- Zixil (Hillsbrad Foothills), 2 recipes
        { prof = "Enchanting", en = "Enchant Boots - Minor Agility", skill = 125, pattern = 6377, note = "Sold by Zixil - Hillsbrad - limited stock" },
        { prof = "Tailoring", en = "Red Woolen Bag", skill = 90, pattern = 5772, note = "Sold by Zixil - Hillsbrad - limited stock" },
    },
    [12246] = {  -- Super-Seller 680 (Desolace), 3 recipes
        { prof = "Tailoring", en = "Dark Silk Shirt", skill = 120, pattern = 6401, note = "Sold by Super-Seller 680 - Desolace" },
        { prof = "Tailoring", en = "Enchanter's Cowl", skill = 130, pattern = 14630, note = "Sold by Super-Seller 680 - Desolace" },
        { prof = "Tailoring", en = "Crimson Silk Cloak", skill = 145, pattern = 7087, note = "Sold by Super-Seller 680 - Desolace" },
    },
    [253140] = {  -- Molkar (Desolace), 3 recipes
        { prof = "Enchanting", en = "Enchant Bracer - Lesser Agility", skill = 140, pattern = 249486 },
        { prof = "Enchanting", en = "Enchant Bracer - Lesser Healing Power", skill = 205, pattern = 249489 },
        { prof = "Tailoring", en = "Silk Reagent Bag", skill = 125, pattern = 253974 },
    },
    [253139] = {  -- Gorhak (Desolace), 3 recipes
        { prof = "Enchanting", en = "Enchant Bracer - Lesser Agility", skill = 140, pattern = 249486 },
        { prof = "Enchanting", en = "Enchant Bracer - Lesser Healing Power", skill = 205, pattern = 249489 },
        { prof = "Tailoring", en = "Silk Reagent Bag", skill = 125, pattern = 253974 },
    },
    [6567] = {  -- Ghok'kah (Dustwallow Marsh), 3 recipes
        { prof = "Tailoring", en = "Linen Reagent Bag", skill = 5, pattern = 253665, note = "Sold by Xizk Goodstitch - Stranglethorn" },
        { prof = "Tailoring", en = "Woolen Reagent Bag", skill = 70, pattern = 253668, note = "Sold by Xizk Goodstitch - Stranglethorn" },
        { prof = "Tailoring", en = "Icy Cloak", skill = 165, pattern = 4355, note = "Sold by Micha Yance (A) - Hillsbrad - limited stock" },
    },
    [6574] = {  -- Jun'ha (Arathi Highlands), 3 recipes
        { prof = "Tailoring", en = "Linen Reagent Bag", skill = 5, pattern = 253665, note = "Sold by Xizk Goodstitch - Stranglethorn" },
        { prof = "Tailoring", en = "Woolen Reagent Bag", skill = 70, pattern = 253668, note = "Sold by Xizk Goodstitch - Stranglethorn" },
        { prof = "Tailoring", en = "Azure Silk Cloak", skill = 140, pattern = 7089, note = "Sold by Norvin Alderman (A) - Alterac" },
    },
    [2670] = {  -- Xizk Goodstitch (Stranglethorn Vale), 4 recipes
        { prof = "Tailoring", en = "Linen Reagent Bag", skill = 5, pattern = 253665, note = "Sold by Xizk Goodstitch - Stranglethorn" },
        { prof = "Tailoring", en = "Woolen Reagent Bag", skill = 70, pattern = 253668, note = "Sold by Xizk Goodstitch - Stranglethorn" },
        { prof = "Tailoring", en = "Enchanter's Cowl", skill = 130, pattern = 14630, note = "Sold by Super-Seller 680 - Desolace" },
        { prof = "Tailoring", en = "Crimson Silk Cloak", skill = 145, pattern = 7087, note = "Sold by Super-Seller 680 - Desolace" },
    },
    [6568] = {  -- Vizzklick (Tanaris), 4 recipes
        { prof = "Tailoring", en = "Linen Reagent Bag", skill = 5, pattern = 253665, note = "Sold by Xizk Goodstitch - Stranglethorn" },
        { prof = "Tailoring", en = "Woolen Reagent Bag", skill = 70, pattern = 253668, note = "Sold by Xizk Goodstitch - Stranglethorn" },
        { prof = "Tailoring", en = "Crimson Silk Robe", skill = 170, pattern = 7088, note = "Sold by Stitch Pinwizzle - Riverglades" },
        { prof = "Tailoring", en = "Soul Pouch", skill = 215, pattern = 21358, note = "Sold by Vizzklick - Tanaris" },
    },
    [6576] = {  -- Brienna Starglow (Feralas), 3 recipes
        { prof = "Tailoring", en = "Linen Reagent Bag", skill = 5, pattern = 253665, note = "Sold by Xizk Goodstitch - Stranglethorn" },
        { prof = "Tailoring", en = "Woolen Reagent Bag", skill = 70, pattern = 253668, note = "Sold by Xizk Goodstitch - Stranglethorn" },
        { prof = "Tailoring", en = "Azure Silk Cloak", skill = 140, pattern = 7089, note = "Sold by Norvin Alderman (A) - Alterac" },
    },
    [254151] = {  -- Vayn Moongaze (Zephras Isle), 12 recipes
        { prof = "Tailoring", en = "Cloudy Stormsewn Cord", skill = 50, pattern = 276949, note = "Sold by Vayn Moongaze - Zephras Isle" },
        { prof = "Tailoring", en = "Azure Stormsewn Cuffs", skill = 50, pattern = 276971, note = "Sold by Vayn Moongaze - Zephras Isle" },
        { prof = "Tailoring", en = "Cloudy Stormsewn Cuffs", skill = 50, pattern = 276947, note = "Sold by Vayn Moongaze - Zephras Isle" },
        { prof = "Tailoring", en = "Azure Stormsewn Cord", skill = 50, pattern = 276973, note = "Sold by Vayn Moongaze - Zephras Isle" },
        { prof = "Tailoring", en = "Cloudy Stormsewn Shoes", skill = 55, pattern = 276951, note = "Sold by Vayn Moongaze - Zephras Isle" },
        { prof = "Tailoring", en = "Azure Stormsewn Handwraps", skill = 55, pattern = 276972, note = "Sold by Vayn Moongaze - Zephras Isle" },
        { prof = "Tailoring", en = "Cloudy Stormsewn Handwraps", skill = 55, pattern = 276948, note = "Sold by Vayn Moongaze - Zephras Isle" },
        { prof = "Tailoring", en = "Azure Stormsewn Shoes", skill = 55, pattern = 276975, note = "Sold by Vayn Moongaze - Zephras Isle" },
        { prof = "Tailoring", en = "Azure Stormsewn Vest", skill = 60, pattern = 276970, note = "Sold by Vayn Moongaze - Zephras Isle" },
        { prof = "Tailoring", en = "Cloudy Stormsewn Vest", skill = 60, pattern = 276946, note = "Sold by Vayn Moongaze - Zephras Isle" },
        { prof = "Tailoring", en = "Azure Stormsewn Leggings", skill = 60, pattern = 276974, note = "Sold by Vayn Moongaze - Zephras Isle" },
        { prof = "Tailoring", en = "Cloudy Stormsewn Leggings", skill = 60, pattern = 276950, note = "Sold by Vayn Moongaze - Zephras Isle" },
    },
    [257020] = {  -- Nasalanna Windsinger (Zephras Isle), 5 recipes
        { prof = "Enchanting", en = "Minor Wizard Oil", skill = 5, pattern = 20758, note = "Sold by Kania - Silithus" },
        { prof = "Enchanting", en = "Enchant Chest - Minor Intellect", skill = 20, pattern = 6342, note = "Sold by Kania - Silithus" },
        { prof = "Enchanting", en = "Minor Mana Oil", skill = 150, pattern = 20752, note = "Sold by Kania - Silithus" },
        { prof = "Enchanting", en = "Lesser Wizard Oil", skill = 200, pattern = 20753, note = "Sold by Kania - Silithus" },
        { prof = "Tailoring", en = "Enchanted Mageweave Pouch", skill = 190, pattern = 22307, note = "Sold by Kania - Silithus" },
    },
    [251991] = {  -- Taleen Shimmerthread (Zephras Isle), 2 recipes
        { prof = "Tailoring", en = "Linen Reagent Bag", skill = 5, pattern = 253665, note = "Sold by Xizk Goodstitch - Stranglethorn" },
        { prof = "Tailoring", en = "Woolen Reagent Bag", skill = 70, pattern = 253668, note = "Sold by Xizk Goodstitch - Stranglethorn" },
    },
    [252380] = {  -- Othesia Evengale (Zephras Isle), 2 recipes
        { prof = "Tailoring", en = "Linen Reagent Bag", skill = 5, pattern = 253665, note = "Sold by Xizk Goodstitch - Stranglethorn" },
        { prof = "Tailoring", en = "Woolen Reagent Bag", skill = 70, pattern = 253668, note = "Sold by Xizk Goodstitch - Stranglethorn" },
    },
    [260570] = {  -- Stitch Pinwizzle (Riverglades), 4 recipes
        { prof = "Tailoring", en = "Linen Reagent Bag", skill = 5, pattern = 253665, note = "Sold by Xizk Goodstitch - Stranglethorn" },
        { prof = "Tailoring", en = "Woolen Reagent Bag", skill = 70, pattern = 253668, note = "Sold by Xizk Goodstitch - Stranglethorn" },
        { prof = "Tailoring", en = "Crimson Silk Robe", skill = 170, pattern = 7088, note = "Sold by Stitch Pinwizzle - Riverglades" },
        { prof = "Tailoring", en = "Soul Pouch", skill = 215, pattern = 21358, note = "Sold by Vizzklick - Tanaris" },
    },
    [251997] = {  -- Norvin Alderman (Alterac Mountains), 2 recipes
        { prof = "Tailoring", en = "Azure Silk Cloak", skill = 140, pattern = 7089, note = "Sold by Norvin Alderman (A) - Alterac" },
        { prof = "Tailoring", en = "Crimson Silk Cloak", skill = 145, pattern = 7087, note = "Sold by Super-Seller 680 - Desolace" },
    },
    [11189] = {  -- Qia (Winterspring), 3 recipes
        { prof = "Tailoring", en = "Runecloth Bag", skill = 215, pattern = 14468, note = "Sold by Qia - Winterspring - limited stock" },
        { prof = "Tailoring", en = "Mooncloth", skill = 230, pattern = 14526, note = "Sold by Qia - Winterspring" },
        { prof = "Tailoring", en = "Runecloth Gloves", skill = 230, pattern = 14481, note = "Sold by Qia - Winterspring - limited stock" },
    },
    [7940] = {  -- Darnall (Moonglade), 5 recipes
        { prof = "Tailoring", en = "Linen Reagent Bag", skill = 5, pattern = 253665, note = "Sold by Xizk Goodstitch - Stranglethorn" },
        { prof = "Tailoring", en = "Woolen Reagent Bag", skill = 70, pattern = 253668, note = "Sold by Xizk Goodstitch - Stranglethorn" },
        { prof = "Tailoring", en = "Runecloth Robe", skill = 215, pattern = 14469, note = "Sold by Darnall - Moonglade - limited stock" },
        { prof = "Tailoring", en = "Runecloth Cloak", skill = 220, pattern = 14472, note = "Sold by Darnall - Moonglade - limited stock" },
        { prof = "Tailoring", en = "Runecloth Boots", skill = 235, pattern = 14488, note = "Sold by Darnall - Moonglade - limited stock" },
    },
    [15419] = {  -- Kania (Silithus), 6 recipes
        { prof = "Enchanting", en = "Minor Wizard Oil", skill = 5, pattern = 20758, note = "Sold by Kania - Silithus" },
        { prof = "Enchanting", en = "Enchant Chest - Minor Intellect", skill = 20, pattern = 6342, note = "Sold by Kania - Silithus" },
        { prof = "Enchanting", en = "Minor Mana Oil", skill = 150, pattern = 20752, note = "Sold by Kania - Silithus" },
        { prof = "Enchanting", en = "Lesser Wizard Oil", skill = 200, pattern = 20753, note = "Sold by Kania - Silithus" },
        { prof = "Tailoring", en = "Enchanted Mageweave Pouch", skill = 190, pattern = 22307, note = "Sold by Kania - Silithus" },
        { prof = "Tailoring", en = "Enchanted Runecloth Bag", skill = 230, pattern = 22308, note = "Sold by Lokhtos Darkbargainer - BRD" },
    },
    [1318] = {  -- Jessara Cordell (Stormwind City), 5 recipes
        { prof = "Enchanting", en = "Minor Wizard Oil", skill = 5, pattern = 20758, note = "Sold by Kania - Silithus" },
        { prof = "Enchanting", en = "Enchant Chest - Minor Intellect", skill = 20, pattern = 6342, note = "Sold by Kania - Silithus" },
        { prof = "Enchanting", en = "Minor Mana Oil", skill = 150, pattern = 20752, note = "Sold by Kania - Silithus" },
        { prof = "Enchanting", en = "Lesser Wizard Oil", skill = 200, pattern = 20753, note = "Sold by Kania - Silithus" },
        { prof = "Tailoring", en = "Enchanted Mageweave Pouch", skill = 190, pattern = 22307, note = "Sold by Kania - Silithus" },
    },
    [1347] = {  -- Alexandra Bolero (Stormwind City), 4 recipes
        { prof = "Tailoring", en = "Linen Reagent Bag", skill = 5, pattern = 253665, note = "Sold by Xizk Goodstitch - Stranglethorn" },
        { prof = "Tailoring", en = "Woolen Reagent Bag", skill = 70, pattern = 253668, note = "Sold by Xizk Goodstitch - Stranglethorn" },
        { prof = "Tailoring", en = "Blue Overalls", skill = 75, pattern = 6274, note = "Sold by Gina MacGregor (A) - Westfall - limited stock" },
        { prof = "Tailoring", en = "White Wedding Dress", skill = 140, pattern = 10325, note = "Sold by Alexandra Bolero (A) - Stormwind - limited stock" },
    },
    [8681] = {  -- Outfitter Eric (Ironforge), 7 recipes
        { prof = "Tailoring", en = "Linen Reagent Bag", skill = 5, pattern = 253665, note = "Sold by Xizk Goodstitch - Stranglethorn" },
        { prof = "Tailoring", en = "Woolen Reagent Bag", skill = 70, pattern = 253668, note = "Sold by Xizk Goodstitch - Stranglethorn" },
        { prof = "Tailoring", en = "Tuxedo Jacket", skill = 140, pattern = 10326, note = "Sold by Outfitter Eric (A) - Ironforge - limited stock" },
        { prof = "Tailoring", en = "Tuxedo Pants", skill = 140, pattern = 10323, note = "Sold by Outfitter Eric (A) - Ironforge - limited stock" },
        { prof = "Tailoring", en = "Lavender Mageweave Shirt", skill = 190, pattern = 10314, note = "Sold by Outfitter Eric (A) - Ironforge - limited stock" },
        { prof = "Tailoring", en = "Pink Mageweave Shirt", skill = 195, pattern = 10317, note = "Sold by Outfitter Eric (A) - Ironforge - limited stock" },
        { prof = "Tailoring", en = "Tuxedo Shirt", skill = 200, pattern = 10321, note = "Sold by Outfitter Eric (A) - Ironforge - limited stock" },
    },
    [5158] = {  -- Tilli Thistlefuzz (Ironforge), 6 recipes
        { prof = "Enchanting", en = "Minor Wizard Oil", skill = 5, pattern = 20758, note = "Sold by Kania - Silithus" },
        { prof = "Enchanting", en = "Enchant Chest - Minor Intellect", skill = 20, pattern = 6342, note = "Sold by Kania - Silithus" },
        { prof = "Enchanting", en = "Enchant 2H Weapon - Lesser Intellect", skill = 100, pattern = 6349, note = "Sold by Tilli Thistlefuzz (A) - Ironforge - limited stock" },
        { prof = "Enchanting", en = "Minor Mana Oil", skill = 150, pattern = 20752, note = "Sold by Kania - Silithus" },
        { prof = "Enchanting", en = "Lesser Wizard Oil", skill = 200, pattern = 20753, note = "Sold by Kania - Silithus" },
        { prof = "Tailoring", en = "Enchanted Mageweave Pouch", skill = 190, pattern = 22307, note = "Sold by Kania - Silithus" },
    },
    [4168] = {  -- Elynna (Darnassus), 7 recipes
        { prof = "Tailoring", en = "Linen Reagent Bag", skill = 5, pattern = 253665, note = "Sold by Xizk Goodstitch - Stranglethorn" },
        { prof = "Tailoring", en = "Blue Linen Robe", skill = 45, pattern = 6272, note = "Sold by Ranik - Barrens - limited stock" },
        { prof = "Tailoring", en = "Woolen Reagent Bag", skill = 70, pattern = 253668, note = "Sold by Xizk Goodstitch - Stranglethorn" },
        { prof = "Tailoring", en = "Greater Adept's Robe", skill = 90, pattern = 6275, note = "Sold by Ranik - Barrens - limited stock" },
        { prof = "Tailoring", en = "Invoker's Mantle", skill = 150, pattern = 215370, note = "Sold by Elynna (A) - Darnassus" },
        { prof = "Tailoring", en = "Invoker's Cord", skill = 150, pattern = 215369, note = "Sold by Elynna (A) - Darnassus" },
        { prof = "Tailoring", en = "Orange Martial Shirt", skill = 185, pattern = 10311, note = "Sold by Elynna (A) - Darnassus - limited stock" },
    },
    [4228] = {  -- Vaean (Darnassus), 5 recipes
        { prof = "Enchanting", en = "Minor Wizard Oil", skill = 5, pattern = 20758, note = "Sold by Kania - Silithus" },
        { prof = "Enchanting", en = "Enchant Chest - Minor Intellect", skill = 20, pattern = 6342, note = "Sold by Kania - Silithus" },
        { prof = "Enchanting", en = "Minor Mana Oil", skill = 150, pattern = 20752, note = "Sold by Kania - Silithus" },
        { prof = "Enchanting", en = "Lesser Wizard Oil", skill = 200, pattern = 20753, note = "Sold by Kania - Silithus" },
        { prof = "Tailoring", en = "Enchanted Mageweave Pouch", skill = 190, pattern = 22307, note = "Sold by Kania - Silithus" },
    },
    [242498] = {  -- Reagent Bot (Westfall), 2 recipes
        { prof = "Tailoring", en = "Linen Reagent Bag", skill = 5, pattern = 253665, note = "Sold by Xizk Goodstitch - Stranglethorn" },
        { prof = "Tailoring", en = "Woolen Reagent Bag", skill = 70, pattern = 253668, note = "Sold by Xizk Goodstitch - Stranglethorn" },
    },
    [254695] = {  -- Repair Bot (Westfall), 2 recipes
        { prof = "Tailoring", en = "Linen Reagent Bag", skill = 5, pattern = 253665, note = "Sold by Xizk Goodstitch - Stranglethorn" },
        { prof = "Tailoring", en = "Woolen Reagent Bag", skill = 70, pattern = 253668, note = "Sold by Xizk Goodstitch - Stranglethorn" },
    },
    [1474] = {  -- Rann Flamespinner (Loch Modan), 4 recipes
        { prof = "Tailoring", en = "Linen Reagent Bag", skill = 5, pattern = 253665, note = "Sold by Xizk Goodstitch - Stranglethorn" },
        { prof = "Tailoring", en = "Woolen Reagent Bag", skill = 70, pattern = 253668, note = "Sold by Xizk Goodstitch - Stranglethorn" },
        { prof = "Tailoring", en = "Red Woolen Bag", skill = 90, pattern = 5772, note = "Sold by Zixil - Hillsbrad - limited stock" },
        { prof = "Tailoring", en = "Greater Adept's Robe", skill = 90, pattern = 6275, note = "Sold by Ranik - Barrens - limited stock" },
    },
    [256735] = {  -- Mivin Shadowweave (Redridge Mountains), 67 recipes
        { prof = "Tailoring", en = "Silky Boots", skill = 60, pattern = 253892, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Shining Boots", skill = 60, pattern = 253900, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Shadow Boots", skill = 60, pattern = 253896, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Flame Boots", skill = 60, pattern = 253894, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Pristine Boots", skill = 60, pattern = 253890, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Pearly Boots", skill = 60, pattern = 253898, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Flame Gloves", skill = 75, pattern = 253918, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Silky Gloves", skill = 75, pattern = 253916, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Shadow Gloves", skill = 75, pattern = 253920, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Shining Gloves", skill = 75, pattern = 253924, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Pristine Gloves", skill = 75, pattern = 253914, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Pearly Gloves", skill = 75, pattern = 253922, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Shadow Sash", skill = 85, pattern = 253932, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Pristine Sash", skill = 85, pattern = 253926, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Silky Sash", skill = 85, pattern = 253928, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Shining Sash", skill = 85, pattern = 253936, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Flame Sash", skill = 85, pattern = 253930, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Pearly Sash", skill = 85, pattern = 253934, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Silky Circlet", skill = 100, pattern = 253952, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Shadow Circlet", skill = 100, pattern = 253956, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Pearly Circlet", skill = 100, pattern = 253958, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Shining Circlet", skill = 100, pattern = 253960, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Pristine Circlet", skill = 100, pattern = 253950, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Flame Circlet", skill = 100, pattern = 253954, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Pristine Gown", skill = 110, pattern = 253962, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Shining Gown", skill = 110, pattern = 253972, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Pearly Gown", skill = 110, pattern = 253970, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Flame Gown", skill = 110, pattern = 253966, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Silky Gown", skill = 110, pattern = 253964, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Shadow Gown", skill = 110, pattern = 253968, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Silky Leggings", skill = 125, pattern = 253990, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Shadow Leggings", skill = 125, pattern = 253994, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Shining Leggings", skill = 125, pattern = 253998, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Flame Leggings", skill = 125, pattern = 253992, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Pristine Leggings", skill = 125, pattern = 253988, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Pearly Leggings", skill = 125, pattern = 253996, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Frothing Handwraps", skill = 165, pattern = 254024, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Radiant Handwraps", skill = 165, pattern = 254032, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Golden Handwraps", skill = 165, pattern = 254030, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Fiery Handwraps", skill = 165, pattern = 254026, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Black Handwraps", skill = 165, pattern = 254028, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Mageweave Reagent Bag", skill = 190, pattern = 254036, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Netherflame Shoulders", skill = 195, pattern = 254054, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Netherlight Shoulders", skill = 195, pattern = 254060, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Netherfroth Shoulders", skill = 195, pattern = 254052, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Nethershine Shoulders", skill = 195, pattern = 254058, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Netherpearl Shoulders", skill = 195, pattern = 254056, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Nethergeld Shoulders", skill = 195, pattern = 254050, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Nethergeld Cuffs", skill = 205, pattern = 254062, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Nethershine Cuffs", skill = 205, pattern = 254070, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Netherflame Cuffs", skill = 205, pattern = 254066, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Netherfroth Cuffs", skill = 205, pattern = 254064, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Netherlight Cuffs", skill = 205, pattern = 254072, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Netherpearl Cuffs", skill = 205, pattern = 254068, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Frothing Waistcord", skill = 215, pattern = 254084, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Radiant Waistcord", skill = 215, pattern = 254092, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Gilded Waistcord", skill = 215, pattern = 254082, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Golden Waistcord", skill = 215, pattern = 254090, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Runecloth Reagent Bag", skill = 215, pattern = 254080, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Black Waistcord", skill = 215, pattern = 254088, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Fiery Waistcord", skill = 215, pattern = 254086, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Frothing Sandals", skill = 235, pattern = 254110, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Gilded Sandals", skill = 235, pattern = 254108, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Radiant Sandals", skill = 235, pattern = 254118, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Fiery Sandals", skill = 235, pattern = 254112, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Black Sandals", skill = 235, pattern = 254114, note = "Sold by Mivin Shadowweave (A) - Redridge" },
        { prof = "Tailoring", en = "Golden Sandals", skill = 235, pattern = 254116, note = "Sold by Mivin Shadowweave (A) - Redridge" },
    },
    [256732] = {  -- Alynsia (Redridge Mountains), 23 recipes
        { prof = "Enchanting", en = "Tenets of the Silver Hand", skill = 130, pattern = 249477, note = "Sold by Alynsia (A) - Redridge" },
        { prof = "Enchanting", en = "Mystic Mushroom", skill = 130, pattern = 249476, note = "Sold by Alynsia (A) - Redridge" },
        { prof = "Enchanting", en = "Polished Driftwood Icon", skill = 130, pattern = 249478, note = "Sold by Alynsia (A) - Redridge" },
        { prof = "Enchanting", en = "Soulstaff", skill = 140, pattern = 249483, note = "Sold by Alynsia (A) - Redridge" },
        { prof = "Enchanting", en = "Enchant Weapon - Recovery", skill = 140, pattern = 249480, note = "Sold by Alynsia (A) - Redridge" },
        { prof = "Enchanting", en = "Enchant Weapon - Insight", skill = 140, pattern = 249479, note = "Sold by Alynsia (A) - Redridge" },
        { prof = "Enchanting", en = "Orb of Souls", skill = 140, pattern = 249485, note = "Sold by Alynsia (A) - Redridge" },
        { prof = "Enchanting", en = "Orb of Mystic Insight", skill = 140, pattern = 249484, note = "Sold by Alynsia (A) - Redridge" },
        { prof = "Enchanting", en = "Glimmering Staff", skill = 140, pattern = 249482, note = "Sold by Alynsia (A) - Redridge" },
        { prof = "Enchanting", en = "Enchant Weapon - Revelation", skill = 140, pattern = 249481, note = "Sold by Alynsia (A) - Redridge" },
        { prof = "Enchanting", en = "Enchant Necklace - Healing Power", skill = 210, pattern = 249503, note = "Sold by Alynsia (A) - Redridge" },
        { prof = "Enchanting", en = "Enchant Necklace - Agility", skill = 210, pattern = 249504, note = "Sold by Alynsia (A) - Redridge" },
        { prof = "Enchanting", en = "Enchant Necklace - Deflection", skill = 210, pattern = 249505, note = "Sold by Alynsia (A) - Redridge" },
        { prof = "Enchanting", en = "Enchant Necklace - Strength", skill = 210, pattern = 249496, note = "Sold by Alynsia (A) - Redridge" },
        { prof = "Enchanting", en = "Talons of Wrath", skill = 210, pattern = 249493, note = "Sold by Alynsia (A) - Redridge" },
        { prof = "Enchanting", en = "Totem of Ancestral Protection", skill = 210, pattern = 249495, note = "Sold by Alynsia (A) - Redridge" },
        { prof = "Enchanting", en = "Libram of Invocation", skill = 210, pattern = 249494, note = "Sold by Alynsia (A) - Redridge" },
        { prof = "Enchanting", en = "Enchant Necklace - Spell Power", skill = 210, pattern = 249502, note = "Sold by Alynsia (A) - Redridge" },
        { prof = "Enchanting", en = "Twisting Essence Jar", skill = 220, pattern = 249509, note = "Sold by Alynsia (A) - Redridge" },
        { prof = "Enchanting", en = "Dreamstaff", skill = 220, pattern = 249507, note = "Sold by Alynsia (A) - Redridge" },
        { prof = "Enchanting", en = "Truesilver Conduit", skill = 220, pattern = 249508, note = "Sold by Alynsia (A) - Redridge" },
        { prof = "Enchanting", en = "Radiant Staff", skill = 220, pattern = 249506, note = "Sold by Alynsia (A) - Redridge" },
        { prof = "Enchanting", en = "Enchant Chest - Absorption", skill = 220, pattern = 249510, note = "Sold by Alynsia (A) - Redridge" },
    },
    [3096] = {  -- Captured Servant of Azora (Redridge Mountains), 2 recipes
        { prof = "Tailoring", en = "Linen Reagent Bag", skill = 5, pattern = 253665, note = "Sold by Xizk Goodstitch - Stranglethorn" },
        { prof = "Tailoring", en = "Woolen Reagent Bag", skill = 70, pattern = 253668, note = "Sold by Xizk Goodstitch - Stranglethorn" },
    },
    [2669] = {  -- Sheri Zipstitch (Duskwood), 4 recipes
        { prof = "Tailoring", en = "Linen Reagent Bag", skill = 5, pattern = 253665, note = "Sold by Xizk Goodstitch - Stranglethorn" },
        { prof = "Tailoring", en = "Woolen Reagent Bag", skill = 70, pattern = 253668, note = "Sold by Xizk Goodstitch - Stranglethorn" },
        { prof = "Tailoring", en = "Greater Adept's Robe", skill = 90, pattern = 6275, note = "Sold by Ranik - Barrens - limited stock" },
        { prof = "Tailoring", en = "Dark Silk Shirt", skill = 120, pattern = 6401, note = "Sold by Super-Seller 680 - Desolace" },
    },
    [2668] = {  -- Danielle Zipstitch (Duskwood), 3 recipes
        { prof = "Tailoring", en = "Linen Reagent Bag", skill = 5, pattern = 253665, note = "Sold by Xizk Goodstitch - Stranglethorn" },
        { prof = "Tailoring", en = "Woolen Reagent Bag", skill = 70, pattern = 253668, note = "Sold by Xizk Goodstitch - Stranglethorn" },
        { prof = "Tailoring", en = "Bright Yellow Shirt", skill = 110, pattern = 14627, note = "Sold by Danielle Zipstitch (A) - Duskwood - limited stock" },
    },
    [4189] = {  -- Valdaron (Darkshore), 5 recipes
        { prof = "Tailoring", en = "Linen Reagent Bag", skill = 5, pattern = 253665, note = "Sold by Xizk Goodstitch - Stranglethorn" },
        { prof = "Tailoring", en = "Blue Linen Vest", skill = 35, pattern = 6270, note = "Sold by Tharynn Bouden (A) - Elwynn Forest - limited stock" },
        { prof = "Tailoring", en = "Red Linen Bag", skill = 50, pattern = 5771, note = "Sold by Gina MacGregor (A) - Westfall - limited stock" },
        { prof = "Tailoring", en = "Woolen Reagent Bag", skill = 70, pattern = 253668, note = "Sold by Xizk Goodstitch - Stranglethorn" },
        { prof = "Tailoring", en = "Red Woolen Bag", skill = 90, pattern = 5772, note = "Sold by Zixil - Hillsbrad - limited stock" },
    },
    [1454] = {  -- Jennabink Powerseam (Wetlands), 4 recipes
        { prof = "Tailoring", en = "Linen Reagent Bag", skill = 5, pattern = 253665, note = "Sold by Xizk Goodstitch - Stranglethorn" },
        { prof = "Tailoring", en = "Woolen Reagent Bag", skill = 70, pattern = 253668, note = "Sold by Xizk Goodstitch - Stranglethorn" },
        { prof = "Tailoring", en = "Red Woolen Bag", skill = 90, pattern = 5772, note = "Sold by Zixil - Hillsbrad - limited stock" },
        { prof = "Tailoring", en = "Greater Adept's Robe", skill = 90, pattern = 6275, note = "Sold by Ranik - Barrens - limited stock" },
    },
}

-- =====================================================================
-- DISENCHANTING
-- =====================================================================
--
-- READ THIS BEFORE TRUSTING A NUMBER HERE. This is the weakest data in the
-- file and the only table whose confidence is ESTIMATE rather than CACHED.
--
-- What is sourced from Forever:
--   * which dust / essence / shard each item-level band yields, and the
--     quantity ranges. wow-professions.com/forever/disenchanting-guide gives
--     exactly these bands and quantities (keyed by required level, which is
--     ilvl-5 for greens, so the two line up row for row).
--   * that Nexus Crystal (20725) is a Forever disenchant product.
--   * that the yield is tied to item level at all:
--     warcrafttavern.com/forever/guides/enchanting.
--
-- What is NOT sourced from Forever - the probabilities:
--   The per-band percentages below come from warcraft.wiki.gg/wiki/Disenchanting_tables,
--   which is community datamining of CLASSIC, is flagged outdated on its own
--   page, and was last edited 2021-03-05. The Forever guide only gives rounded
--   figures ("75% armor / 20% / shard 3-5%"), which agree with the Classic
--   table but are too coarse to tell whether Forever kept Classic's per-band
--   exceptions. No Blizzard source states any disenchant probability.
--   => Treat every `chance` below as ESTIMATE. Never show it as a fact.
--
-- Three corrections against the table Mastercraft ships, all deliberate:
--   1. Mastercraft applies a flat 75/20/5 to every green band. Classic is not
--      flat: ilvl <=15 is 80/20/0 (no shard at all) and ilvl 21-25 is 75/15/10.
--      Weapons at ilvl 51-65 are 22/75/3, not 20/75/5.
--   2. Mastercraft says green WEAPONS of ilvl 21-30 yield Greater Magic Essence
--      instead of Astral. Both sources contradict this: weapons and armour yield
--      the SAME essence in every band and differ only in probability. Dropped.
--   3. Mastercraft gives blue items a flat 100% shard. From ilvl 56 up it is
--      99.5% shard + 0.5% Nexus Crystal.
--
-- Forever-only unknown that bounds all of this: the Arcane Salvager (item
-- 279985, Enchanting 140, a camp object) "enables more efficient disenchanting",
-- and a Blizzard hotfix of 2026-11-10 confirms it has a disenchanting bonus.
-- The size of that bonus is documented nowhere. Expected value computed from
-- this table is therefore the value WITHOUT a camp - FS.DISENCHANT.caveat says
-- so, and the UI should repeat it rather than quietly understating the yield.

FS.DE_DUST    = { strange = 10940, soul = 11083, vision = 11137, dream = 11176, illusion = 16204 }
FS.DE_ESSENCE = {
    lMagic = 10938, gMagic = 10939, lAstral = 10998, gAstral = 11082, lMystic = 11134,
    gMystic = 11135, lNether = 11174, gNether = 11175, lEternal = 16202, gEternal = 16203,
}
FS.DE_SHARD = {
    sGlimmer = 10978, lGlimmer = 11084, sGlow = 11138, lGlow = 11139,
    sRadiant = 11177, lRadiant = 11178, sBrilliant = 14343, lBrilliant = 14344,
}
FS.DE_CRYSTAL = { nexus = 20725 }

-- Green (quality 2). One row per item-level band, inclusive of maxIlvl.
--   dust/essence/shard = { id, min, max, armorChance, weaponChance }
-- min/max are the quantity the game rolls; the average is (min+max)/2 because
-- the Classic source states quantity outcomes are evenly distributed.
FS.DISENCHANT = {
    caveat = "Вероятности взяты из данных Classic, не из источника по Forever. Бонус Arcane Salvager не учтён.",
    green = {
        { maxIlvl = 15,
          dust    = { id = 10940, min = 1, max = 2, armor = 0.80, weapon = 0.20 },
          essence = { id = 10938, min = 1, max = 2, armor = 0.20, weapon = 0.80 } },
        { maxIlvl = 20,
          dust    = { id = 10940, min = 2, max = 3, armor = 0.75, weapon = 0.20 },
          essence = { id = 10939, min = 1, max = 2, armor = 0.20, weapon = 0.75 },
          shard   = { id = 10978, min = 1, max = 1, armor = 0.05, weapon = 0.05 } },
        { maxIlvl = 25,
          dust    = { id = 10940, min = 4, max = 6, armor = 0.75, weapon = 0.15 },
          essence = { id = 10998, min = 1, max = 2, armor = 0.15, weapon = 0.75 },
          shard   = { id = 10978, min = 1, max = 1, armor = 0.10, weapon = 0.10 } },
        { maxIlvl = 30,
          dust    = { id = 11083, min = 1, max = 2, armor = 0.75, weapon = 0.20 },
          essence = { id = 11082, min = 1, max = 2, armor = 0.20, weapon = 0.75 },
          shard   = { id = 11084, min = 1, max = 1, armor = 0.05, weapon = 0.05 } },
        { maxIlvl = 35,
          dust    = { id = 11083, min = 2, max = 5, armor = 0.75, weapon = 0.20 },
          essence = { id = 11134, min = 1, max = 2, armor = 0.20, weapon = 0.75 },
          shard   = { id = 11138, min = 1, max = 1, armor = 0.05, weapon = 0.05 } },
        { maxIlvl = 40,
          dust    = { id = 11137, min = 1, max = 2, armor = 0.75, weapon = 0.20 },
          essence = { id = 11135, min = 1, max = 2, armor = 0.20, weapon = 0.75 },
          shard   = { id = 11139, min = 1, max = 1, armor = 0.05, weapon = 0.05 } },
        { maxIlvl = 45,
          dust    = { id = 11137, min = 2, max = 5, armor = 0.75, weapon = 0.20 },
          essence = { id = 11174, min = 1, max = 2, armor = 0.20, weapon = 0.75 },
          shard   = { id = 11177, min = 1, max = 1, armor = 0.05, weapon = 0.05 } },
        { maxIlvl = 50,
          dust    = { id = 11176, min = 1, max = 2, armor = 0.75, weapon = 0.20 },
          essence = { id = 11175, min = 1, max = 2, armor = 0.20, weapon = 0.75 },
          shard   = { id = 11178, min = 1, max = 1, armor = 0.05, weapon = 0.05 } },
        { maxIlvl = 55,
          dust    = { id = 11176, min = 2, max = 5, armor = 0.75, weapon = 0.22 },
          essence = { id = 16202, min = 1, max = 2, armor = 0.20, weapon = 0.75 },
          shard   = { id = 14343, min = 1, max = 1, armor = 0.05, weapon = 0.03 } },
        { maxIlvl = 60,
          dust    = { id = 16204, min = 1, max = 2, armor = 0.75, weapon = 0.22 },
          essence = { id = 16203, min = 1, max = 2, armor = 0.20, weapon = 0.75 },
          shard   = { id = 14344, min = 1, max = 1, armor = 0.05, weapon = 0.03 } },
        { maxIlvl = 99999,
          dust    = { id = 16204, min = 2, max = 5, armor = 0.75, weapon = 0.22 },
          essence = { id = 16203, min = 2, max = 3, armor = 0.20, weapon = 0.75 },
          shard   = { id = 14344, min = 1, max = 1, armor = 0.05, weapon = 0.03 } },
    },
    -- Blue (quality 3). A shard every time, except at the top where the crystal
    -- replaces it half a percent of the time.
    blue = {
        { maxIlvl = 25,    results = { { id = 10978, min = 1, max = 1, chance = 1.00 } } },
        { maxIlvl = 30,    results = { { id = 11084, min = 1, max = 1, chance = 1.00 } } },
        { maxIlvl = 35,    results = { { id = 11138, min = 1, max = 1, chance = 1.00 } } },
        { maxIlvl = 40,    results = { { id = 11139, min = 1, max = 1, chance = 1.00 } } },
        { maxIlvl = 45,    results = { { id = 11177, min = 1, max = 1, chance = 1.00 } } },
        { maxIlvl = 50,    results = { { id = 11178, min = 1, max = 1, chance = 1.00 } } },
        { maxIlvl = 55,    results = { { id = 14343, min = 1, max = 1, chance = 1.00 } } },
        { maxIlvl = 99999, results = { { id = 14344, min = 1, max = 1, chance = 0.995 },
                                       { id = 20725, min = 1, max = 1, chance = 0.005 } } },
    },
    -- Epic (quality 4). Classic-derived in full; the Forever guide only says
    -- "epic at level 50 and below -> shard, high-level epic -> crystal", which
    -- agrees with the shape but not with any band edge.
    epic = {
        { maxIlvl = 45,    results = { { id = 11177, min = 2, max = 4, chance = 1.00 } } },
        { maxIlvl = 50,    results = { { id = 11178, min = 2, max = 4, chance = 1.00 } } },
        { maxIlvl = 55,    results = { { id = 14343, min = 2, max = 4, chance = 1.00 } } },
        { maxIlvl = 60,    results = { { id = 20725, min = 1, max = 1, chance = 1.00 } } },
        { maxIlvl = 99999, results = { { id = 20725, min = 1, max = 2, chance = 1.00 } } },
    },
}

-- Expected results for one disenchant: { { itemID, chance, min, max, avgQty }, ... }
-- Returns nil for qualities that cannot be disenchanted, so callers can tell
-- "nothing" apart from "we do not know".
function FS:DisenchantResults(quality, itemLevel, isWeapon)
    if type(itemLevel) ~= "number" then return nil end
    local function pack(e, which)
        local chance = e[which] or e.chance
        if not chance or chance <= 0 then return nil end
        return { itemID = e.id, chance = chance, min = e.min, max = e.max,
                 avgQty = (e.min + e.max) / 2 }
    end
    if quality == 2 then
        for _, row in ipairs(self.DISENCHANT.green) do
            if itemLevel <= row.maxIlvl then
                local which = isWeapon and "weapon" or "armor"
                local out = {}
                for _, key in ipairs({ "dust", "essence", "shard" }) do
                    local e = row[key] and pack(row[key], which)
                    if e then out[#out + 1] = e end
                end
                return out
            end
        end
    elseif quality == 3 or quality == 4 then
        local bands = (quality == 3) and self.DISENCHANT.blue or self.DISENCHANT.epic
        for _, row in ipairs(bands) do
            if itemLevel <= row.maxIlvl then
                local out = {}
                for _, e in ipairs(row.results) do
                    local p = pack(e, "chance")
                    if p then out[#out + 1] = p end
                end
                return out
            end
        end
    end
    return nil
end

-- Every item any disenchant can produce - for the price scanner, so it knows
-- what to look up before the player has disenchanted anything.
function FS:AllDisenchantProducts()
    local out = {}
    for _, row in ipairs(self.DISENCHANT.green) do
        for _, key in ipairs({ "dust", "essence", "shard" }) do
            if row[key] then out[row[key].id] = true end
        end
    end
    for _, group in ipairs({ self.DISENCHANT.blue, self.DISENCHANT.epic }) do
        for _, row in ipairs(group) do
            for _, e in ipairs(row.results) do out[e.id] = true end
        end
    end
    return out
end

-- =====================================================================
-- WHICH SLOTS FOREVER ACTUALLY ENCHANTS
-- =====================================================================
--
-- Derived by bucketing all 260 Forever enchanting recipes in Mastercraft's
-- RecipeData by slot, at every skill level, not just 1-225. This is the whole
-- list, so an absence here is evidence of absence rather than a gap.
--
-- It confirms what Data/SlotMap.lua already suspected: Forever has NECK
-- enchants (5 of them, all skill 210, spells 1249019 / 1249057-1249060 - these
-- do not exist in Classic) and has NO head, shoulder, waist, leg or ranged
-- enchants. ns.ENCHANTABLE_SLOTS in Core/Const.lua lists HEAD, SHOULDER, LEGS
-- and RANGED, so before the first profession scan the addon would both invent
-- four slots that cannot be enchanted and miss NECK. SlotMap:IsEnchantable
-- already prefers the scanned list; this table is the better fallback for
-- before that scan.
--
-- Spot-checked: spell 1249060 "Enchant Necklace - Deflection" on Wowhead
-- Forever reports "Requires Necklaces" and the same five reagents Mastercraft
-- lists. Crafted HEAD armour exists (e.g. spell 1301532 Cloudy Stormsewn Cowl,
-- a Head cloth item) - that is armour, not an enchant, and does not change this.
FS.ENCHANT_SLOTS = {
    NECK = 5, BACK = 19, CHEST = 21, WRIST = 36, HANDS = 24, FEET = 12,
    SHIELD = 14, TWOHAND = 18, MAINHAND = 27, OFFHAND = 3,
}
FS.ENCHANT_SLOTS_ABSENT = {
    "HEAD", "SHOULDER", "WAIST", "LEGS", "RANGED", "FINGER", "TRINKET",
}

-- =====================================================================
-- THE SKILL CEILING: READ FROM THE CLIENT, AND NOTHING ELSE IS KNOWN.
-- =====================================================================
--
-- WHAT USED TO BE HERE. First, a rank ladder - apprentice 75 / journeyman 150 /
-- expert 225 / artisan 300, with character level gates of 10 / 20 / 35 - plus
-- a NEXT_RANK table naming the artisan trainers. It came from two guide sites
-- (warcrafttavern.com, wow-professions.com), not from the client.
--
-- Then the ladder was removed on the strength of a "measurement" that was a
-- MISREADING, and this block said so in capitals for two days:
--
--     MastercraftDB.history[guid][date].s[profession] = { a, b }
--
-- was read as { current, max }, and b over nine days - 84, 93, 160, 224, 225
-- for Tailoring - was declared "the maximum moving". It is not the maximum.
-- Mastercraft writes (Data.lua, RecordHistory):
--
--     if s then s[2] = p.skill else d.s[p.name] = { p.skill, p.skill } end
--
-- i.e. { the SKILL first seen that day, the SKILL last seen that day }. The
-- numbers chain exactly as a skill does and a cap does not: each day's b is the
-- next day's a (84|84, 93|93, 160|160, 224|224). 84 -> 93 was the player
-- gaining nine points. The addon then told that player, on a card, that "the
-- ceiling has risen four times, most recently 224 -> 225".
--
-- WHAT IS ACTUALLY KNOWN (2026-11-18). The client reports max 225 for every
-- profession of the level-27 character and 75 for the level-10 one. Both sit on
-- the old ladder, so the ladder was probably right and its removal wrong. That
-- is NOT restored here: whether Forever keeps the classic level gates and where
-- its trainers stand has to be checked in the game, not re-derived from a guide
-- a second time.
--
-- WHAT THE CODE DOES. The pair (current, max) comes from the client through
-- Api:Professions (C_SkillInfo.GetSkillLineInfoByID: rank / maxRank), with the
-- player's own cache as a fallback. Three states, all honest: below the ceiling
-- the planner aims at max; at the ceiling the advice says so and stops; with no
-- max reported the advice says the maximum is unknown. No history of the
-- maximum exists in any source the addon reads, so it claims none.
FS.SKILL_CAP = {
    -- Было `dynamic = true`. Отозвано: вывод сделан из неверно прочитанных
    -- данных. Ни «динамический», ни «лестница» отсюда не утверждается.
    dynamic     = nil,
    retracted   = "2026-11-18",
    source      = "клиент: C_SkillInfo.GetSkillLineInfoByID (rank / maxRank)",
    -- Максимумы, которые сообщил сам клиент. Свидетельство, не пороги: ничто
    -- не читает их, чтобы что-то решить, и никакой код не должен начать.
    reportedByClient = {
        { level = 27, max = 225 },   -- Player-6946-00CCA8FC, все пять профессий
        { level = 10, max = 75 },    -- Player-6946-01187A42
    },
    note = "максимум навыка известен только из клиента и только на сейчас;"
        .. " истории максимума нет ни в одном источнике",
    -- Recipes needing more than 300 exist in the Forever recipe data (17
    -- tailoring, 19 enchanting, at 315-320): a later ceiling than any seen yet.
    recipesAboveSeenCap = { tailoring = 17, enchanting = 19, maxSeen = 320 },
}

-- =====================================================================
-- NAMES - ASK THE CLIENT, NEVER TRANSLATE
-- =====================================================================

-- The localised item name, or a marked placeholder. Never the English `en`.
function FS:ItemName(itemID)
    if not itemID then return "?" end
    local get = (_G.C_Item and _G.C_Item.GetItemInfo) or _G.GetItemInfo
    if type(get) == "function" then
        local ok, name = pcall(get, itemID)
        if ok and type(name) == "string" and name ~= "" then return name, true end
    end
    return "#" .. tostring(itemID), false
end

-- A vendor's label. The client cannot name an NPC we have never met, so this
-- returns the English name with a flag saying it is untranslated; callers that
-- show it to the player should mark it the way the rest of the addon marks
-- anything unverified.
function FS:PlaceLabel(npcID)
    local p = self.VENDOR_PLACES[npcID]
    if not p then return "#" .. tostring(npcID), false end
    return p.en, false
end

-- Vendors for an item, nearest-first is NOT attempted here: Logic/Places.lua
-- already knows how to compare distances, and this file has no business
-- guessing. Returns the raw list plus how many the source actually had.
function FS:VendorsFor(itemID)
    local list = self.MAT_VENDORS[itemID]
    if not list then return nil end
    return list, self.TRIMMED_FROM[itemID]
end

function FS:Place(npcID) return self.VENDOR_PLACES[npcID] end

-- Vendors of this faction only. faction is "Horde" / "Alliance" as the client
-- reports it; neutral vendors are always included.
function FS:VendorsForFaction(itemID, faction)
    local list = self.MAT_VENDORS[itemID]
    if not list then return nil end
    local want = (faction == "Horde") and "H" or "A"
    local out = {}
    for _, npcID in ipairs(list) do
        local p = self.VENDOR_PLACES[npcID]
        if p and (p.faction == "" or p.faction == want) then out[#out + 1] = npcID end
    end
    return out
end


-- =====================================================================
-- REFERENCE RECIPE TABLE - the thing Logic/SourceCheck.lua diffs against
-- =====================================================================
--
-- Every Tailoring and Enchanting recipe the source knows, as the source
-- states it. This is NOT here for the addon to use instead of the client -
-- RecipeBook always wins. It is here so that on the next login SourceCheck
-- can compare what the client actually says against what the source claims
-- and report the differences, which is the only way to find out whether the
-- Forever client and Wowhead Forever have drifted apart.
--
-- Key is the recipe spell id, which is what both Mastercraft records and
-- what C_TradeSkillUI hands back as the recipeID on this client. If that
-- assumption is wrong the checker will find zero matches and say so, rather
-- than quietly reporting everything as a mismatch.
--
--   s = skill required, r = "itemID:qty,..." reagents,
--   o = item produced (nil for enchants), n = units per craft (nil = 1),
--   en = English name, for reading this file only
FS.RECIPE_REF = {
    -- ---- Tailoring: 444 recipes ----
    [2963] = { s = 1, r = "2589:2", o = 2996, prof = "Tailoring", en = "Bolt of Linen Cloth" },
    [3915] = { s = 1, r = "2996:1,2320:1", o = 4344, prof = "Tailoring", en = "Brown Linen Shirt" },
    [2387] = { s = 1, r = "2996:1,2320:1", o = 2570, prof = "Tailoring", en = "Linen Cloak" },
    [12044] = { s = 1, r = "2996:1,2320:1", o = 10045, prof = "Tailoring", en = "Simple Linen Pants" },
    [2393] = { s = 1, r = "2996:1,2320:1,2324:1", o = 2576, prof = "Tailoring", en = "White Linen Shirt" },
    [3755] = { s = 5, r = "2996:3,2320:3", o = 4238, prof = "Tailoring", en = "Linen Bag" },
    [1257013] = { s = 5, r = "2996:6,2320:6", o = 253664, prof = "Tailoring", en = "Linen Reagent Bag" },
    [2385] = { s = 10, r = "2996:1,2320:1", o = 2568, prof = "Tailoring", en = "Brown Linen Vest" },
    [8776] = { s = 15, r = "2996:1,2320:1", o = 7026, prof = "Tailoring", en = "Linen Belt" },
    [1229504] = { s = 20, r = "2996:1,2320:1", o = 279972, prof = "Tailoring", en = "Faction Banner" },
    [12045] = { s = 20, r = "2996:2,2318:1,2320:1", o = 10046, prof = "Tailoring", en = "Simple Linen Boots" },
    [2394] = { s = 25, r = "2996:2,2320:1,6260:1", o = 2577, prof = "Tailoring", en = "Blue Linen Shirt" },
    [3914] = { s = 25, r = "2996:2,2320:1", o = 4343, prof = "Tailoring", en = "Brown Linen Pants" },
    [7623] = { s = 25, r = "2996:3,2320:1", o = 6238, prof = "Tailoring", en = "Brown Linen Robe" },
    [3840] = { s = 25, r = "2996:2,2320:1", o = 4307, prof = "Tailoring", en = "Heavy Linen Gloves" },
    [2389] = { s = 25, r = "2996:3,2320:2,2604:2", o = 2572, prof = "Tailoring", en = "Red Linen Robe" },
    [2392] = { s = 25, r = "2996:2,2320:1,2604:1", o = 2575, prof = "Tailoring", en = "Red Linen Shirt" },
    [8465] = { s = 25, r = "2996:2,2320:1,6260:1,2324:1", o = 6786, prof = "Tailoring", en = "Simple Dress" },
    [7624] = { s = 25, r = "2996:3,2320:1,2324:1", o = 6241, prof = "Tailoring", en = "White Linen Robe" },
    [7630] = { s = 35, r = "2996:3,2320:1,6260:1", o = 6240, prof = "Tailoring", en = "Blue Linen Vest" },
    [3841] = { s = 35, r = "2996:3,2320:2,2605:1", o = 4308, prof = "Tailoring", en = "Green Linen Bracers" },
    [1257368] = { s = 35, r = "2996:8,2321:2,2455:2", o = 253885, prof = "Tailoring", en = "Novice Arcanist's Sash" },
    [1257369] = { s = 35, r = "2996:12,2321:2,118:2", o = 253887, prof = "Tailoring", en = "Novice Ardent's Sash" },
    [7629] = { s = 35, r = "2996:3,2320:1,2604:1", o = 6239, prof = "Tailoring", en = "Red Linen Vest" },
    [2397] = { s = 35, r = "2996:2,2320:3", o = 2580, prof = "Tailoring", en = "Reinforced Linen Cape" },
    [2395] = { s = 40, r = "2996:4,2318:1,2321:1", o = 2578, prof = "Tailoring", en = "Barbaric Linen Vest" },
    [2396] = { s = 40, r = "2996:3,2321:1,2605:1", o = 2579, prof = "Tailoring", en = "Green Linen Shirt" },
    [2386] = { s = 40, r = "2996:3,2320:1,2318:1", o = 2569, prof = "Tailoring", en = "Linen Boots" },
    [7633] = { s = 45, r = "2996:4,2320:2,6260:2", o = 6242, prof = "Tailoring", en = "Blue Linen Robe" },
    [3842] = { s = 45, r = "2996:4,2321:2", o = 4309, prof = "Tailoring", en = "Handstitched Linen Britches" },
    [1301466] = { s = 50, r = "2996:3,2320:3", o = 277037, prof = "Tailoring", en = "Azure Stormsewn Cord" },
    [1301464] = { s = 50, r = "2996:3,2320:3", o = 277035, prof = "Tailoring", en = "Azure Stormsewn Cuffs" },
    [1301442] = { s = 50, r = "2996:3,2320:3", o = 277013, prof = "Tailoring", en = "Cloudy Stormsewn Cord" },
    [1301440] = { s = 50, r = "2996:3,2320:3", o = 277011, prof = "Tailoring", en = "Cloudy Stormsewn Cuffs" },
    [6686] = { s = 50, r = "2996:4,2321:1,2604:1", o = 5762, prof = "Tailoring", en = "Red Linen Bag" },
    [12046] = { s = 50, r = "2996:4,2321:1", o = 10047, prof = "Tailoring", en = "Simple Kilt" },
    [3757] = { s = 50, r = "2997:3,2321:1", o = 4240, prof = "Tailoring", en = "Woolen Bag" },
    [1301465] = { s = 55, r = "2996:4,2320:4", o = 277036, prof = "Tailoring", en = "Azure Stormsewn Handwraps" },
    [1301469] = { s = 55, r = "2996:4,2320:3", o = 277039, prof = "Tailoring", en = "Azure Stormsewn Shoes" },
    [2964] = { s = 55, r = "2592:3", o = 2997, prof = "Tailoring", en = "Bolt of Woolen Cloth" },
    [1301441] = { s = 55, r = "2996:4,2320:4", o = 277012, prof = "Tailoring", en = "Cloudy Stormsewn Handwraps" },
    [1301444] = { s = 55, r = "2996:4,2320:3", o = 277015, prof = "Tailoring", en = "Cloudy Stormsewn Shoes" },
    [3845] = { s = 55, r = "2996:5,2318:2,2321:1", o = 4312, prof = "Tailoring", en = "Soft-soled Linen Boots" },
    [2402] = { s = 55, r = "2997:1,2321:1", o = 2584, prof = "Tailoring", en = "Woolen Cape" },
    [1301468] = { s = 60, r = "2996:5,2320:2", o = 277038, prof = "Tailoring", en = "Azure Stormsewn Leggings" },
    [1301463] = { s = 60, r = "2996:5,2320:2", o = 277034, prof = "Tailoring", en = "Azure Stormsewn Vest" },
    [1301443] = { s = 60, r = "2996:5,2320:2", o = 277014, prof = "Tailoring", en = "Cloudy Stormsewn Leggings" },
    [1301439] = { s = 60, r = "2996:5,2320:2", o = 277010, prof = "Tailoring", en = "Cloudy Stormsewn Vest" },
    [1257372] = { s = 60, r = "2997:8,2321:2,249409:2,6371:1", o = 253893, prof = "Tailoring", en = "Flame Boots" },
    [2399] = { s = 60, r = "2997:2,2321:2,2605:1", o = 2582, prof = "Tailoring", en = "Green Woolen Vest" },
    [3843] = { s = 60, r = "2997:3,2321:1", o = 4310, prof = "Tailoring", en = "Heavy Woolen Gloves" },
    [1257374] = { s = 60, r = "2997:8,2321:2,249409:2,5498:1", o = 253897, prof = "Tailoring", en = "Pearly Boots" },
    [1257370] = { s = 60, r = "2997:8,2321:2,249409:2,249427:1", o = 253889, prof = "Tailoring", en = "Pristine Boots" },
    [1257373] = { s = 60, r = "2997:8,2321:2,249409:2,1210:1", o = 253895, prof = "Tailoring", en = "Shadow Boots" },
    [1257375] = { s = 60, r = "2997:8,2321:2,249409:2,249391:1", o = 253899, prof = "Tailoring", en = "Shining Boots" },
    [1257371] = { s = 60, r = "2997:8,2321:2,249409:2,3182:1", o = 253891, prof = "Tailoring", en = "Silky Boots" },
    [12047] = { s = 70, r = "2997:5,2604:3,2321:1", o = 10048, prof = "Tailoring", en = "Colorful Kilt" },
    [6521] = { s = 70, r = "2997:3,2321:2,5498:1", o = 5542, prof = "Tailoring", en = "Pearl-clasped Cloak" },
    [2401] = { s = 70, r = "2997:4,2321:2,2318:2", o = 2583, prof = "Tailoring", en = "Woolen Boots" },
    [1257017] = { s = 70, r = "2997:3,2321:1,249409:1", o = 253667, prof = "Tailoring", en = "Woolen Reagent Bag" },
    [7639] = { s = 75, r = "2997:4,2321:2,6260:2", o = 6263, prof = "Tailoring", en = "Blue Overalls" },
    [1257378] = { s = 75, r = "2997:8,2321:4,249409:2,6371:2", o = 253905, prof = "Tailoring", en = "Filigreed Flame Gown" },
    [1257380] = { s = 75, r = "2997:8,2321:4,249409:2,5498:2", o = 253909, prof = "Tailoring", en = "Filigreed Pearly Gown" },
    [1257376] = { s = 75, r = "2997:8,2321:4,249409:2,249427:2", o = 253901, prof = "Tailoring", en = "Filigreed Pristine Gown" },
    [1257379] = { s = 75, r = "2997:8,2321:4,249409:2,1210:2", o = 253907, prof = "Tailoring", en = "Filigreed Shadow Gown" },
    [1257381] = { s = 75, r = "2997:8,2321:4,249409:2,249391:2", o = 253911, prof = "Tailoring", en = "Filigreed Shining Gown" },
    [1257377] = { s = 75, r = "2997:8,2321:4,249409:2,3182:2", o = 253903, prof = "Tailoring", en = "Filigreed Silky Gown" },
    [1257384] = { s = 75, r = "2997:6,2321:4,249409:3,6371:2", o = 253917, prof = "Tailoring", en = "Flame Gloves" },
    [3758] = { s = 75, r = "2997:5,2605:1,2321:1", o = 4241, prof = "Tailoring", en = "Green Woolen Bag" },
    [1257386] = { s = 75, r = "2997:6,2321:4,249409:3,5498:2", o = 253921, prof = "Tailoring", en = "Pearly Gloves" },
    [1257382] = { s = 75, r = "2997:6,2321:4,249409:3,249427:2", o = 253913, prof = "Tailoring", en = "Pristine Gloves" },
    [3847] = { s = 75, r = "2997:4,2318:2,2321:1,2604:2", o = 4313, prof = "Tailoring", en = "Red Woolen Boots" },
    [1257385] = { s = 75, r = "2997:6,2321:4,249409:3,1210:2", o = 253919, prof = "Tailoring", en = "Shadow Gloves" },
    [1257387] = { s = 75, r = "2997:6,2321:4,249409:3,249391:2", o = 253923, prof = "Tailoring", en = "Shining Gloves" },
    [1257383] = { s = 75, r = "2997:6,2321:4,249409:3,3182:2", o = 253915, prof = "Tailoring", en = "Silky Gloves" },
    [2403] = { s = 80, r = "2997:4,2321:3,4340:1", o = 2585, prof = "Tailoring", en = "Gray Woolen Robe" },
    [2406] = { s = 80, r = "2997:2,2321:1,4340:1", o = 2587, prof = "Tailoring", en = "Gray Woolen Shirt" },
    [3844] = { s = 80, r = "2997:3,2321:2,5498:2", o = 4311, prof = "Tailoring", en = "Heavy Woolen Cloak" },
    [3848] = { s = 85, r = "2997:3,2321:2", o = 4314, prof = "Tailoring", en = "Double-stitched Woolen Shoulders" },
    [1257390] = { s = 85, r = "4305:8,2321:4,249409:3,6371:3", o = 253929, prof = "Tailoring", en = "Flame Sash" },
    [3850] = { s = 85, r = "2997:5,2321:4", o = 4316, prof = "Tailoring", en = "Heavy Woolen Pants" },
    [1257392] = { s = 85, r = "4305:8,2321:4,249409:3,5498:3", o = 253933, prof = "Tailoring", en = "Pearly Sash" },
    [1257388] = { s = 85, r = "4305:8,2321:4,249409:3,249427:3", o = 253925, prof = "Tailoring", en = "Pristine Sash" },
    [1257391] = { s = 85, r = "4305:8,2321:4,249409:3,1210:3", o = 253931, prof = "Tailoring", en = "Shadow Sash" },
    [1257393] = { s = 85, r = "4305:8,2321:4,249409:3,249391:3", o = 253935, prof = "Tailoring", en = "Shining Sash" },
    [1257389] = { s = 85, r = "4305:8,2321:4,249409:3,3182:3", o = 253927, prof = "Tailoring", en = "Silky Sash" },
    [3866] = { s = 85, r = "2997:3,2604:2,2321:1", o = 4330, prof = "Tailoring", en = "Stylish Red Shirt" },
    [8467] = { s = 85, r = "2997:3,2324:4,2321:1", o = 6787, prof = "Tailoring", en = "White Woolen Dress" },
    [7643] = { s = 90, r = "2997:5,2321:3,2604:3", o = 6264, prof = "Tailoring", en = "Greater Adept's Robe" },
    [6688] = { s = 90, r = "2997:5,2604:1,2321:1", o = 5763, prof = "Tailoring", en = "Red Woolen Bag" },
    [3849] = { s = 95, r = "2997:6,2319:2,2321:2", o = 4315, prof = "Tailoring", en = "Reinforced Woolen Shoulders" },
    [7892] = { s = 95, r = "2997:4,6260:2,4340:1,2321:1", o = 6384, prof = "Tailoring", en = "Stylish Blue Shirt" },
    [7893] = { s = 95, r = "2997:4,2605:2,4340:1,2321:1", o = 6385, prof = "Tailoring", en = "Stylish Green Shirt" },
    [3839] = { s = 100, r = "4306:4", o = 4305, prof = "Tailoring", en = "Bolt of Silk Cloth" },
    [1257396] = { s = 100, r = "4305:8,2321:4,249409:2,6371:4", o = 253941, prof = "Tailoring", en = "Filigreed Flame Leggings" },
    [1257398] = { s = 100, r = "4305:8,2321:4,249409:2,5498:4", o = 253945, prof = "Tailoring", en = "Filigreed Pearly Leggings" },
    [1257394] = { s = 100, r = "4305:8,2321:4,249409:2,249427:4", o = 253937, prof = "Tailoring", en = "Filigreed Pristine Leggings" },
    [1257397] = { s = 100, r = "4305:8,2321:4,249409:2,1210:4", o = 253943, prof = "Tailoring", en = "Filigreed Shadow Leggings" },
    [1257399] = { s = 100, r = "4305:8,2321:4,249409:2,249391:4", o = 253947, prof = "Tailoring", en = "Filigreed Shining Leggings" },
    [1257395] = { s = 100, r = "4305:8,2321:4,249409:2,3182:4", o = 253939, prof = "Tailoring", en = "Filigreed Silky Leggings" },
    [1257402] = { s = 100, r = "4305:10,4291:2,249409:4,6371:4,2842:1,11082:2", o = 253953, prof = "Tailoring", en = "Flame Circlet" },
    [1257404] = { s = 100, r = "4305:10,4291:2,249409:4,5498:4,2842:1,11082:2", o = 253957, prof = "Tailoring", en = "Pearly Circlet" },
    [3868] = { s = 100, r = "2997:4,5500:1,2321:4,2324:2", o = 4331, prof = "Tailoring", en = "Phoenix Gloves" },
    [3851] = { s = 100, r = "2997:6,5500:1,2321:3", o = 4317, prof = "Tailoring", en = "Phoenix Pants" },
    [1257400] = { s = 100, r = "4305:10,4291:2,249409:4,249427:4,2842:1,11082:2", o = 253949, prof = "Tailoring", en = "Pristine Circlet" },
    [1257403] = { s = 100, r = "4305:10,4291:2,249409:4,1210:4,2842:1,11082:2", o = 253955, prof = "Tailoring", en = "Shadow Circlet" },
    [1257405] = { s = 100, r = "4305:10,4291:2,249409:4,249391:4,2842:1,11082:2", o = 253959, prof = "Tailoring", en = "Shining Circlet" },
    [1257401] = { s = 100, r = "4305:10,4291:2,249409:4,3182:4,2842:1,11082:2", o = 253951, prof = "Tailoring", en = "Silky Circlet" },
    [3855] = { s = 100, r = "4305:2,2319:4,3182:4,5500:1", o = 4320, prof = "Tailoring", en = "Spidersilk Boots" },
    [3852] = { s = 105, r = "2997:4,2321:3,3383:1", o = 4318, prof = "Tailoring", en = "Gloves of Meditation" },
    [3869] = { s = 110, r = "4305:1,4341:1,2321:1", o = 4332, prof = "Tailoring", en = "Bright Yellow Shirt" },
    [1257408] = { s = 110, r = "4305:12,4291:2,249409:6,6371:6,2842:2,11082:2", o = 253965, prof = "Tailoring", en = "Flame Gown" },
    [6690] = { s = 110, r = "4305:2,2321:2,3182:2", o = 5766, prof = "Tailoring", en = "Lesser Wizard's Robe" },
    [1257410] = { s = 110, r = "4305:12,4291:2,249409:6,5498:6,2842:2,11082:2", o = 253969, prof = "Tailoring", en = "Pearly Gown" },
    [1257406] = { s = 110, r = "4305:12,4291:2,249409:6,249427:6,2842:2,11082:2", o = 253961, prof = "Tailoring", en = "Pristine Gown" },
    [1257409] = { s = 110, r = "4305:12,4291:2,249409:6,1210:6,2842:2,11082:2", o = 253967, prof = "Tailoring", en = "Shadow Gown" },
    [1257411] = { s = 110, r = "4305:12,4291:2,249409:6,249391:6,2842:2,11082:2", o = 253971, prof = "Tailoring", en = "Shining Gown" },
    [1257407] = { s = 110, r = "4305:12,4291:2,249409:6,3182:6,2842:2,11082:2", o = 253963, prof = "Tailoring", en = "Silky Gown" },
    [8758] = { s = 115, r = "4305:4,6260:2,2321:3", o = 7046, prof = "Tailoring", en = "Azure Silk Pants" },
    [3856] = { s = 115, r = "4305:3,3182:1,2321:2", o = 4321, prof = "Tailoring", en = "Spider Silk Slippers" },
    [3854] = { s = 120, r = "4305:3,4234:2,6260:2,2321:2", o = 4319, prof = "Tailoring", en = "Azure Silk Gloves" },
    [8760] = { s = 120, r = "4305:2,6260:2,2321:1", o = 7048, prof = "Tailoring", en = "Azure Silk Hood" },
    [3870] = { s = 120, r = "4305:2,4340:2,2321:1", o = 4333, prof = "Tailoring", en = "Dark Silk Shirt" },
    [8780] = { s = 120, r = "4305:3,4234:2,6048:2,2321:2", o = 7047, prof = "Tailoring", en = "Hands of Darkness" },
    [3859] = { s = 125, r = "4305:5,6260:4", o = 4324, prof = "Tailoring", en = "Azure Silk Vest" },
    [1257415] = { s = 125, r = "4305:8,2321:4,249409:2,6371:6", o = 253979, prof = "Tailoring", en = "Filigreed Flame Circlet" },
    [1257417] = { s = 125, r = "4305:8,2321:4,249409:2,5498:6", o = 253983, prof = "Tailoring", en = "Filigreed Pearly Circlet" },
    [1257413] = { s = 125, r = "4305:8,2321:4,249409:2,249427:6", o = 253975, prof = "Tailoring", en = "Filigreed Pristine Circlet" },
    [1257416] = { s = 125, r = "4305:8,2321:4,249409:2,1210:6", o = 253981, prof = "Tailoring", en = "Filigreed Shadow Circlet" },
    [1257418] = { s = 125, r = "4305:8,2321:4,249409:2,249391:6", o = 253985, prof = "Tailoring", en = "Filigreed Shining Circlet" },
    [1257414] = { s = 125, r = "4305:8,2321:4,249409:2,3182:6", o = 253977, prof = "Tailoring", en = "Filigreed Silky Circlet" },
    [1257421] = { s = 125, r = "4305:14,2321:3,249409:8,6371:8,2842:2,11082:3", o = 253991, prof = "Tailoring", en = "Flame Leggings" },
    [1257423] = { s = 125, r = "4305:14,2321:3,249409:8,5498:8,2842:2,11082:3", o = 253995, prof = "Tailoring", en = "Pearly Leggings" },
    [428424] = { s = 125, r = "2997:6,814:2,2321:2", o = 210781, prof = "Tailoring", en = "Phoenix Bindings" },
    [1257419] = { s = 125, r = "4305:14,2321:3,249409:8,249427:8,2842:2,11082:3", o = 253987, prof = "Tailoring", en = "Pristine Leggings" },
    [6692] = { s = 125, r = "4305:4,2321:2,3182:2", o = 5770, prof = "Tailoring", en = "Robes of Arcana" },
    [1257422] = { s = 125, r = "4305:14,2321:3,249409:8,1210:8,2842:2,11082:3", o = 253993, prof = "Tailoring", en = "Shadow Leggings" },
    [1257424] = { s = 125, r = "4305:14,2321:3,249409:8,249391:8,2842:2,11082:3", o = 253997, prof = "Tailoring", en = "Shining Leggings" },
    [8762] = { s = 125, r = "4305:3,2321:2", o = 7050, prof = "Tailoring", en = "Silk Headband" },
    [1257412] = { s = 125, r = "4305:3,4234:2,2321:3,249409:3", o = 253973, prof = "Tailoring", en = "Silk Reagent Bag" },
    [1257420] = { s = 125, r = "4305:14,2321:3,249409:8,3182:8,2842:2,11082:3", o = 253989, prof = "Tailoring", en = "Silky Leggings" },
    [3813] = { s = 125, r = "4305:3,4234:2,2321:3", o = 4245, prof = "Tailoring", en = "Small Silk Pack" },
    [8782] = { s = 125, r = "4305:3,4234:2,929:4,2321:1", o = 7049, prof = "Tailoring", en = "Truefaith Gloves" },
    [8483] = { s = 125, r = "4305:3,2324:2,4291:1", o = 6795, prof = "Tailoring", en = "White Swashbuckler's Shirt" },
    [3857] = { s = 130, r = "4305:3,2321:2,4337:2", o = 4322, prof = "Tailoring", en = "Enchanter's Cowl" },
    [8784] = { s = 130, r = "4305:5,2605:2,4291:1", o = 7065, prof = "Tailoring", en = "Green Silk Armor" },
    [8764] = { s = 135, r = "4305:3,7067:1,2321:2", o = 7051, prof = "Tailoring", en = "Earthen Vest" },
    [3871] = { s = 135, r = "4305:3,2324:2,2321:1", o = 4334, prof = "Tailoring", en = "Formal White Shirt" },
    [3858] = { s = 135, r = "4305:4,4291:1,3824:1", o = 4323, prof = "Tailoring", en = "Shadow Hood" },
    [8766] = { s = 140, r = "4305:4,7070:1,6260:2,2321:2,7071:1", o = 7052, prof = "Tailoring", en = "Azure Silk Belt" },
    [8786] = { s = 140, r = "4305:3,6260:2,2321:2", o = 7053, prof = "Tailoring", en = "Azure Silk Cloak" },
    [3865] = { s = 140, r = "4338:5", o = 4339, prof = "Tailoring", en = "Bolt of Mageweave" },
    [3860] = { s = 140, r = "4305:4,4291:1,4337:2", o = 4325, prof = "Tailoring", en = "Boots of the Enchanter" },
    [8772] = { s = 140, r = "4305:4,7071:1,2604:2,4291:1", o = 7055, prof = "Tailoring", en = "Crimson Silk Belt" },
    [1257425] = { s = 140, r = "4305:4,7067:1,2321:2", o = 253999, prof = "Tailoring", en = "Earthen Leggings" },
    [6693] = { s = 140, r = "4305:5,4234:3,2321:3,2605:1", o = 5764, prof = "Tailoring", en = "Green Silk Pack" },
    [8489] = { s = 140, r = "4305:3,2604:2,4291:1", o = 6796, prof = "Tailoring", en = "Red Swashbuckler's Shirt" },
    [1263032] = { s = 140, r = "4470:2,4305:5,2321:3", o = 279943, prof = "Tailoring", en = "Spinning Wheel" },
    [12093] = { s = 140, r = "4339:5,8343:3", o = 10036, prof = "Tailoring", en = "Tuxedo Jacket" },
    [12089] = { s = 140, r = "4339:4,8343:3", o = 10035, prof = "Tailoring", en = "Tuxedo Pants" },
    [12091] = { s = 140, r = "4339:5,8343:3,2324:1", o = 10040, prof = "Tailoring", en = "White Wedding Dress" },
    [8789] = { s = 145, r = "4305:5,2604:2,6371:2,4291:1", o = 7056, prof = "Tailoring", en = "Crimson Silk Cloak" },
    [1257432] = { s = 145, r = "4305:4,7067:1,2321:2,4234:2", o = 254013, prof = "Tailoring", en = "Earthen Silk Slippers" },
    [8774] = { s = 145, r = "4305:5,4291:2", o = 7057, prof = "Tailoring", en = "Green Silken Shoulders" },
    [3863] = { s = 145, r = "4305:4,4337:2,7071:1", o = 4328, prof = "Tailoring", en = "Spider Belt" },
    [6695] = { s = 150, r = "4305:6,2325:1,2321:4", o = 5765, prof = "Tailoring", en = "Black Silk Pack" },
    [1257429] = { s = 150, r = "4339:8,8343:4,249430:2,249409:2,7971:2", o = 254007, prof = "Tailoring", en = "Black Slippers" },
    [8791] = { s = 150, r = "4305:4,2604:2,2321:2", o = 7058, prof = "Tailoring", en = "Crimson Silk Vest" },
    [1257433] = { s = 150, r = "4305:4,7067:2,2321:2", o = 254015, prof = "Tailoring", en = "Earthen Silk Hood" },
    [429351] = { s = 150, r = "211422:1,4320:1", prof = "Tailoring", en = "Extraplanar Spidersilk Boots" },
    [1257428] = { s = 150, r = "4339:8,8343:4,249430:2,249409:2,7077:2", o = 254005, prof = "Tailoring", en = "Fiery Slippers" },
    [1257427] = { s = 150, r = "4339:8,8343:4,249430:2,249409:2,7079:2", o = 254003, prof = "Tailoring", en = "Frothing Slippers" },
    [1257426] = { s = 150, r = "4339:8,8343:4,249430:2,249409:2,3577:2", o = 254001, prof = "Tailoring", en = "Gilded Slippers" },
    [1257430] = { s = 150, r = "4339:8,8343:4,249430:2,249409:2,13926:2", o = 254009, prof = "Tailoring", en = "Golden Slippers" },
    [435841] = { s = 150, r = "4305:3,1210:1,2321:1,4340:1", o = 215366, prof = "Tailoring", en = "Invoker's Cord" },
    [435848] = { s = 150, r = "4305:4,4340:4,2321:1,6260:4", o = 215365, prof = "Tailoring", en = "Invoker's Mantle" },
    [3861] = { s = 150, r = "4305:4,3827:1,4291:1", o = 4326, prof = "Tailoring", en = "Long Silken Cloak" },
    [1257431] = { s = 150, r = "4339:8,8343:4,249430:2,249409:2,11178:2", o = 254011, prof = "Tailoring", en = "Radiant Slippers" },
    [3872] = { s = 150, r = "4305:4,4342:1,4291:1", o = 4335, prof = "Tailoring", en = "Rich Purple Silk Shirt" },
    [8795] = { s = 155, r = "4305:6,7072:2,6260:2,4291:2", o = 7060, prof = "Tailoring", en = "Azure Shoulders" },
    [8793] = { s = 155, r = "4305:5,6371:2,2604:2,4291:2", o = 7059, prof = "Tailoring", en = "Crimson Silk Shoulders" },
    [21945] = { s = 155, r = "4305:5,2605:4,4291:1", o = 17723, prof = "Tailoring", en = "Green Holiday Shirt" },
    [8770] = { s = 155, r = "4339:2,7067:2,7070:2,7068:2,7069:2,4291:2", o = 7054, prof = "Tailoring", en = "Robe of Power" },
    [8799] = { s = 160, r = "4305:4,2604:2,4291:2", o = 7062, prof = "Tailoring", en = "Crimson Silk Pantaloons" },
    [8797] = { s = 160, r = "4305:5,7067:4,4234:4,7071:1,4291:2", o = 7061, prof = "Tailoring", en = "Earthen Silk Belt" },
    [1257434] = { s = 160, r = "4305:5,7067:2,4291:2", o = 254017, prof = "Tailoring", en = "Earthen Silk Gloves" },
    [1257439] = { s = 165, r = "4339:12,8343:4,249430:2,249409:1,7971:4", o = 254027, prof = "Tailoring", en = "Black Handwraps" },
    [3873] = { s = 165, r = "4305:5,2325:1,4291:1", o = 4336, prof = "Tailoring", en = "Black Swashbuckler's Shirt" },
    [1257435] = { s = 165, r = "4305:4,7067:1,4291:1", o = 254019, prof = "Tailoring", en = "Earthen Silk Cuffs" },
    [1257438] = { s = 165, r = "4339:12,8343:4,249430:2,249409:1,7077:4", o = 254025, prof = "Tailoring", en = "Fiery Handwraps" },
    [1257437] = { s = 165, r = "4339:12,8343:4,249430:2,249409:1,7079:4", o = 254023, prof = "Tailoring", en = "Frothing Handwraps" },
    [1257436] = { s = 165, r = "4339:12,8343:4,249430:2,249409:1,3577:4", o = 254021, prof = "Tailoring", en = "Gilded Handwraps" },
    [1257440] = { s = 165, r = "4339:12,8343:4,249430:2,249409:1,13926:4", o = 254029, prof = "Tailoring", en = "Golden Handwraps" },
    [3862] = { s = 165, r = "4339:3,4291:2,3829:1,4337:2", o = 4327, prof = "Tailoring", en = "Icy Cloak" },
    [1257441] = { s = 165, r = "4339:12,8343:4,249430:2,249409:1,11178:4", o = 254031, prof = "Tailoring", en = "Radiant Handwraps" },
    [3864] = { s = 165, r = "4339:4,4234:4,3864:1,7071:1,4291:1", o = 4329, prof = "Tailoring", en = "Star Belt" },
    [12049] = { s = 170, r = "4339:2,4291:3", o = 9999, prof = "Tailoring", en = "Black Mageweave Leggings" },
    [12048] = { s = 170, r = "4339:2,4291:3", o = 9998, prof = "Tailoring", en = "Black Mageweave Vest" },
    [8802] = { s = 170, r = "4305:8,7068:4,3827:2,2604:4,4291:1", o = 7063, prof = "Tailoring", en = "Crimson Silk Robe" },
    [1257442] = { s = 170, r = "4305:6,7067:2,4291:3", o = 254033, prof = "Tailoring", en = "Earthen Silk Shoulders" },
    [1301540] = { s = 175, r = "4305:7,11134:2,8343:1,6260:4", o = 277054, prof = "Tailoring", en = "Azure Stormsewn Cowl" },
    [1301541] = { s = 175, r = "4305:5,11134:1,8343:1,6260:3", o = 277055, prof = "Tailoring", en = "Azure Stormsewn Epaulets" },
    [12050] = { s = 175, r = "4339:3,8343:1", o = 10001, prof = "Tailoring", en = "Black Mageweave Robe" },
    [1301532] = { s = 175, r = "4305:7,11134:2,8343:1,2324:8", o = 277046, prof = "Tailoring", en = "Cloudy Stormsewn Cowl" },
    [1301533] = { s = 175, r = "4305:5,11134:1,8343:1,2324:6", o = 277047, prof = "Tailoring", en = "Cloudy Stormsewn Epaulets" },
    [8804] = { s = 175, r = "4305:6,7068:2,6371:2,4304:2,2604:4,4291:2", o = 7064, prof = "Tailoring", en = "Crimson Silk Gloves" },
    [12052] = { s = 175, r = "4339:3,10285:2,8343:1", o = 10002, prof = "Tailoring", en = "Shadoweave Pants" },
    [12053] = { s = 180, r = "4339:2,8343:2", o = 10003, prof = "Tailoring", en = "Black Mageweave Gloves" },
    [12061] = { s = 180, r = "4339:1,6261:1,8343:1", o = 10056, prof = "Tailoring", en = "Orange Mageweave Shirt" },
    [12060] = { s = 180, r = "4339:3,2604:2,8343:1", o = 10009, prof = "Tailoring", en = "Red Mageweave Pants" },
    [12056] = { s = 180, r = "4339:3,2604:2,8343:1", o = 10007, prof = "Tailoring", en = "Red Mageweave Vest" },
    [12055] = { s = 180, r = "4339:3,10285:2,8343:1", o = 10004, prof = "Tailoring", en = "Shadoweave Robe" },
    [12059] = { s = 180, r = "4339:1,2324:1,8343:1", o = 10008, prof = "Tailoring", en = "White Bandit Mask" },
    [12064] = { s = 185, r = "4339:2,6261:2,8343:1", o = 10052, prof = "Tailoring", en = "Orange Martial Shirt" },
    [1257447] = { s = 190, r = "4339:28,8343:4,249430:6,249409:4,7971:12", o = 254043, prof = "Tailoring", en = "Black Cord" },
    [12073] = { s = 190, r = "4339:3,8343:2,4304:2", o = 10026, prof = "Tailoring", en = "Black Mageweave Boots" },
    [12072] = { s = 190, r = "4339:3,8343:2", o = 10024, prof = "Tailoring", en = "Black Mageweave Headband" },
    [12074] = { s = 190, r = "4339:3,8343:2", o = 10027, prof = "Tailoring", en = "Black Mageweave Shoulders" },
    [12069] = { s = 190, r = "4339:5,7077:2,8343:2", o = 10042, prof = "Tailoring", en = "Cindercloth Robe" },
    [12067] = { s = 190, r = "4339:4,8153:4,10286:2,8343:2", o = 10019, prof = "Tailoring", en = "Dreamweave Gloves" },
    [12070] = { s = 190, r = "4339:6,8153:6,10286:2,8343:2", o = 10021, prof = "Tailoring", en = "Dreamweave Vest" },
    [27658] = { s = 190, r = "4339:4,11137:4,8343:2", o = 22246, prof = "Tailoring", en = "Enchanted Mageweave Pouch" },
    [1257446] = { s = 190, r = "4339:28,8343:4,249430:6,249409:4,7077:12", o = 254041, prof = "Tailoring", en = "Fiery Cord" },
    [1257445] = { s = 190, r = "4339:28,8343:4,249430:6,249409:4,7079:12", o = 254039, prof = "Tailoring", en = "Frothing Cord" },
    [1257444] = { s = 190, r = "4339:28,8343:4,249430:6,249409:4,3577:12", o = 254037, prof = "Tailoring", en = "Gilded Cord" },
    [1257448] = { s = 190, r = "4339:28,8343:4,249430:6,249409:4,13926:12", o = 254045, prof = "Tailoring", en = "Golden Cord" },
    [12075] = { s = 190, r = "4339:2,4342:2,8343:2", o = 10054, prof = "Tailoring", en = "Lavender Mageweave Shirt" },
    [12065] = { s = 190, r = "4339:4,4291:2", o = 10050, prof = "Tailoring", en = "Mageweave Bag" },
    [1257443] = { s = 190, r = "4339:4,8343:2,249430:1,249409:1", o = 254035, prof = "Tailoring", en = "Mageweave Reagent Bag" },
    [1257449] = { s = 190, r = "4339:28,8343:4,249430:6,249409:4,11178:12", o = 254047, prof = "Tailoring", en = "Radiant Cord" },
    [12066] = { s = 190, r = "4339:3,2604:2,8343:2", o = 10018, prof = "Tailoring", en = "Red Mageweave Gloves" },
    [12071] = { s = 190, r = "4339:5,10285:5,8343:2", o = 10023, prof = "Tailoring", en = "Shadoweave Gloves" },
    [1257452] = { s = 195, r = "4339:16,8343:3,249430:4,249409:3,7077:8,11175:2", o = 254053, prof = "Tailoring", en = "Netherflame Shoulders" },
    [1257451] = { s = 195, r = "4339:16,8343:3,249430:4,249409:3,7079:8,11175:2", o = 254051, prof = "Tailoring", en = "Netherfroth Shoulders" },
    [1257450] = { s = 195, r = "4339:16,8343:3,249430:4,249409:3,3577:8,11175:2", o = 254049, prof = "Tailoring", en = "Nethergeld Shoulders" },
    [1257455] = { s = 195, r = "4339:16,8343:3,249430:4,249409:3,11178:8,11175:2", o = 254059, prof = "Tailoring", en = "Netherlight Shoulders" },
    [1257453] = { s = 195, r = "4339:16,8343:3,249430:4,249409:3,7971:8,11175:2", o = 254055, prof = "Tailoring", en = "Netherpearl Shoulders" },
    [1257454] = { s = 195, r = "4339:16,8343:3,249430:4,249409:3,13926:8,11175:2", o = 254057, prof = "Tailoring", en = "Nethershine Shoulders" },
    [12080] = { s = 195, r = "4339:3,10290:1,8343:1", o = 10055, prof = "Tailoring", en = "Pink Mageweave Shirt" },
    [12079] = { s = 195, r = "4339:5,2604:2,8343:2", o = 10051, prof = "Tailoring", en = "Red Mageweave Bag" },
    [12078] = { s = 195, r = "4339:4,2604:2,8343:3", o = 10029, prof = "Tailoring", en = "Red Mageweave Shoulders" },
    [12076] = { s = 195, r = "4339:5,10285:4,8343:2", o = 10028, prof = "Tailoring", en = "Shadoweave Shoulders" },
    [12077] = { s = 195, r = "4339:3,2325:1,8343:1,2324:1", o = 10053, prof = "Tailoring", en = "Simple Black Dress" },
    [12081] = { s = 200, r = "4339:3,4589:6,8343:2", o = 10030, prof = "Tailoring", en = "Admiral's Hat" },
    [12088] = { s = 200, r = "4339:5,7077:1,8343:3,4304:2", o = 10044, prof = "Tailoring", en = "Cindercloth Boots" },
    [435827] = { s = 200, r = "4339:2,213378:5,8343:5", o = 213379, prof = "Tailoring", en = "Hyperconductive Arcano-Filament" },
    [12084] = { s = 200, r = "4339:4,2604:2,8343:2", o = 10033, prof = "Tailoring", en = "Red Mageweave Headband" },
    [12082] = { s = 200, r = "4339:6,10285:6,8343:3,4304:2", o = 10031, prof = "Tailoring", en = "Shadoweave Boots" },
    [12086] = { s = 200, r = "4339:2,10285:8,8343:2", o = 10025, prof = "Tailoring", en = "Shadoweave Mask" },
    [12085] = { s = 200, r = "4339:4,8343:2", o = 10034, prof = "Tailoring", en = "Tuxedo Shirt" },
    [18401] = { s = 205, r = "14047:5", o = 14048, prof = "Tailoring", en = "Bolt of Runecloth" },
    [12092] = { s = 205, r = "4339:8,8153:4,10286:2,8343:3,6037:1,1529:1", o = 10041, prof = "Tailoring", en = "Dreamweave Circlet" },
    [26403] = { s = 205, r = "14048:4,4625:2,2604:2,14341:1", o = 21154, prof = "Tailoring", en = "Festival Dress" },
    [26407] = { s = 205, r = "14048:4,4625:2,2604:2,14341:1", o = 21542, prof = "Tailoring", en = "Festival Suit" },
    [1257458] = { s = 205, r = "4339:18,8343:3,249430:6,249409:4,7077:10,11175:4", o = 254065, prof = "Tailoring", en = "Netherflame Cuffs" },
    [1257457] = { s = 205, r = "4339:18,8343:3,249430:6,249409:4,7079:10,11175:4", o = 254063, prof = "Tailoring", en = "Netherfroth Cuffs" },
    [1257456] = { s = 205, r = "4339:18,8343:3,249430:6,249409:4,3577:10,11175:4", o = 254061, prof = "Tailoring", en = "Nethergeld Cuffs" },
    [1257461] = { s = 205, r = "4339:18,8343:3,249430:6,249409:4,11178:10,11175:4", o = 254071, prof = "Tailoring", en = "Netherlight Cuffs" },
    [1257459] = { s = 205, r = "4339:18,8343:3,249430:6,249409:4,7971:10,11175:4", o = 254067, prof = "Tailoring", en = "Netherpearl Cuffs" },
    [1257460] = { s = 205, r = "4339:18,8343:3,249430:6,249409:4,13926:10,11175:4", o = 254069, prof = "Tailoring", en = "Nethershine Cuffs" },
    [18404] = { s = 210, r = "14048:5,7079:2,14341:1", o = 13868, prof = "Tailoring", en = "Frostweave Robe" },
    [18403] = { s = 210, r = "14048:5,7079:2,14341:1", o = 13869, prof = "Tailoring", en = "Frostweave Tunic" },
    [18402] = { s = 210, r = "14048:3,14341:1", o = 13856, prof = "Tailoring", en = "Runecloth Belt" },
    [1257469] = { s = 215, r = "14048:8,8343:4,249430:8,249409:5,7971:12", o = 254087, prof = "Tailoring", en = "Black Waistcord" },
    [18408] = { s = 215, r = "14048:5,7077:3,14341:1", o = 14042, prof = "Tailoring", en = "Cindercloth Vest" },
    [1257464] = { s = 215, r = "14048:4,7076:2,14341:1", o = 254077, prof = "Tailoring", en = "Earthenweave Cord" },
    [1257463] = { s = 215, r = "14048:6,7076:1,14341:1", o = 254075, prof = "Tailoring", en = "Earthenweave Gloves" },
    [1257468] = { s = 215, r = "14048:8,8343:4,249430:8,249409:5,7077:12", o = 254085, prof = "Tailoring", en = "Fiery Waistcord" },
    [18411] = { s = 215, r = "14048:3,7080:1,14341:1", o = 13870, prof = "Tailoring", en = "Frostweave Gloves" },
    [1257467] = { s = 215, r = "14048:8,8343:4,249430:8,249409:5,7079:12", o = 254083, prof = "Tailoring", en = "Frothing Waistcord" },
    [1257462] = { s = 215, r = "14048:4,9210:1,14227:1,14341:1", o = 254073, prof = "Tailoring", en = "Ghostweave Cord" },
    [1257466] = { s = 215, r = "14048:8,8343:4,249430:8,249409:5,3577:12", o = 254081, prof = "Tailoring", en = "Gilded Waistcord" },
    [1257470] = { s = 215, r = "14048:8,8343:4,249430:8,249409:5,13926:12", o = 254089, prof = "Tailoring", en = "Golden Waistcord" },
    [1257471] = { s = 215, r = "14048:8,8343:4,249430:8,249409:5,11178:12", o = 254091, prof = "Tailoring", en = "Radiant Waistcord" },
    [18405] = { s = 215, r = "14048:5,8170:2,14341:1,249430:4,249409:2", o = 14046, prof = "Tailoring", en = "Runecloth Bag" },
    [1257465] = { s = 215, r = "14048:5,8170:2,14341:1,249431:1", o = 254079, prof = "Tailoring", en = "Runecloth Reagent Bag" },
    [18406] = { s = 215, r = "14048:5,14227:1,14341:1", o = 13858, prof = "Tailoring", en = "Runecloth Robe" },
    [18407] = { s = 215, r = "14048:5,14227:1,14341:1", o = 13857, prof = "Tailoring", en = "Runecloth Tunic" },
    [26085] = { s = 215, r = "14048:6,8170:4,7972:2,14341:1", o = 21340, prof = "Tailoring", en = "Soul Pouch" },
    [18410] = { s = 220, r = "14048:3,9210:2,14227:1,14341:1", o = 14143, prof = "Tailoring", en = "Ghostweave Belt" },
    [18409] = { s = 220, r = "14048:4,14227:1,14341:1", o = 13860, prof = "Tailoring", en = "Runecloth Cloak" },
    [18415] = { s = 225, r = "14048:4,3577:2,14341:1", o = 14101, prof = "Tailoring", en = "Brightcloth Gloves" },
    [18414] = { s = 225, r = "14048:5,3577:2,14341:1", o = 14100, prof = "Tailoring", en = "Brightcloth Robe" },
    [18412] = { s = 225, r = "14048:4,7077:3,14341:1", o = 14043, prof = "Tailoring", en = "Cindercloth Gloves" },
    [1257472] = { s = 225, r = "14048:4,7076:2,8170:2,14341:1", o = 254093, prof = "Tailoring", en = "Earthenweave Boots" },
    [18413] = { s = 225, r = "14048:4,9210:2,14227:1,14341:1", o = 14142, prof = "Tailoring", en = "Ghostweave Gloves" },
    [18416] = { s = 225, r = "14048:6,9210:4,14227:1,14341:1", o = 14141, prof = "Tailoring", en = "Ghostweave Vest" },
    [435610] = { s = 225, r = "213379:5,213369:1,213372:1,11137:10,4339:10", prof = "Tailoring", en = "Gneuro-Linked Arcano-Filament Monocle" },
    [18420] = { s = 230, r = "14048:4,3577:2,14341:1", o = 14103, prof = "Tailoring", en = "Brightcloth Cloak" },
    [27724] = { s = 230, r = "14048:5,8831:10,11040:8,14341:2", o = 22251, prof = "Tailoring", en = "Cenarion Herb Bag" },
    [18418] = { s = 230, r = "14048:5,7078:1,14341:1", o = 14044, prof = "Tailoring", en = "Cindercloth Cloak" },
    [27659] = { s = 230, r = "14048:5,16203:2,14341:2", o = 22248, prof = "Tailoring", en = "Enchanted Runecloth Bag" },
    [18419] = { s = 230, r = "14048:5,14256:4,14341:1", o = 14107, prof = "Tailoring", en = "Felcloth Pants" },
    [18560] = { s = 230, r = "14256:2", o = 14342, prof = "Tailoring", en = "Mooncloth" },
    [18417] = { s = 230, r = "14048:4,8170:4,14341:1", o = 13863, prof = "Tailoring", en = "Runecloth Gloves" },
    [18421] = { s = 230, r = "14048:6,11176:1,14341:1", o = 14132, prof = "Tailoring", en = "Wizardweave Leggings" },
    [1257476] = { s = 235, r = "14048:8,8343:4,249430:4,249409:4,7971:4", o = 254101, prof = "Tailoring", en = "Black Gloves" },
    [1257482] = { s = 235, r = "14048:10,8343:4,249430:10,249409:6,7971:14,249427:4", o = 254113, prof = "Tailoring", en = "Black Sandals" },
    [18434] = { s = 235, r = "14048:6,7078:1,14341:1", o = 14045, prof = "Tailoring", en = "Cindercloth Pants" },
    [18422] = { s = 235, r = "14048:6,7078:4,7077:4,7068:4,14341:1", o = 14134, prof = "Tailoring", en = "Cloak of Fire" },
    [1257475] = { s = 235, r = "14048:8,8343:4,249430:4,249409:4,7077:4", o = 254099, prof = "Tailoring", en = "Fiery Gloves" },
    [1257481] = { s = 235, r = "14048:10,8343:4,249430:10,249409:6,7077:14,249427:4", o = 254111, prof = "Tailoring", en = "Fiery Sandals" },
    [18424] = { s = 235, r = "14048:6,7080:1,14341:1", o = 13871, prof = "Tailoring", en = "Frostweave Pants" },
    [1257474] = { s = 235, r = "14048:8,8343:4,249430:4,249409:4,7079:4", o = 254097, prof = "Tailoring", en = "Frothing Gloves" },
    [1257480] = { s = 235, r = "14048:10,8343:4,249430:10,249409:6,7079:14,249427:4", o = 254109, prof = "Tailoring", en = "Frothing Sandals" },
    [1257473] = { s = 235, r = "14048:8,8343:4,249430:4,249409:4,3577:4", o = 254095, prof = "Tailoring", en = "Gilded Gloves" },
    [1257479] = { s = 235, r = "14048:10,8343:4,249430:10,249409:6,3577:14,249427:4", o = 254107, prof = "Tailoring", en = "Gilded Sandals" },
    [1257477] = { s = 235, r = "14048:8,8343:4,249430:4,249409:4,13926:4", o = 254103, prof = "Tailoring", en = "Golden Gloves" },
    [1257483] = { s = 235, r = "14048:10,8343:4,249430:10,249409:6,13926:14,249427:4", o = 254115, prof = "Tailoring", en = "Golden Sandals" },
    [1257478] = { s = 235, r = "14048:8,8343:4,249430:4,249409:4,11178:4", o = 254105, prof = "Tailoring", en = "Radiant Gloves" },
    [1257484] = { s = 235, r = "14048:10,8343:4,249430:10,249409:6,11178:14,249427:4", o = 254117, prof = "Tailoring", en = "Radiant Sandals" },
    [18423] = { s = 235, r = "14048:4,14227:2,8170:4,14341:1", o = 13864, prof = "Tailoring", en = "Runecloth Boots" },
    [1257485] = { s = 240, r = "14048:6,7076:1,14341:1", o = 254119, prof = "Tailoring", en = "Earthenweave Mantle" },
    [18437] = { s = 240, r = "14048:6,14256:4,8170:4,14341:1", o = 14108, prof = "Tailoring", en = "Felcloth Boots" },
    [18438] = { s = 240, r = "14048:6,14227:2,14341:1", o = 13865, prof = "Tailoring", en = "Runecloth Pants" },
    [18439] = { s = 245, r = "14048:6,3577:4,14227:1,14341:1", o = 14104, prof = "Tailoring", en = "Brightcloth Pants" },
    [1257488] = { s = 245, r = "14048:6,7076:2,14341:1", o = 254125, prof = "Tailoring", en = "Earthenweave Leggings" },
    [18442] = { s = 245, r = "14048:5,14256:4,14341:1", o = 14111, prof = "Tailoring", en = "Felcloth Hood" },
    [18441] = { s = 245, r = "14048:6,9210:4,14341:1", o = 14144, prof = "Tailoring", en = "Ghostweave Pants" },
    [18440] = { s = 245, r = "14048:6,14342:4,14341:1", o = 14137, prof = "Tailoring", en = "Mooncloth Leggings" },
    [18436] = { s = 245, r = "14048:10,14256:12,12808:4,7080:4,14341:1", o = 14136, prof = "Tailoring", en = "Robe of Winter Night" },
    [1227723] = { s = 250, r = "12811:1,14048:14,2604:8,14227:3", o = 239147, prof = "Tailoring", en = "Crusader's Knapsack" },
    [1257486] = { s = 250, r = "14048:8,7076:1,14341:1", o = 254121, prof = "Tailoring", en = "Earthenweave Vest" },
    [446193] = { s = 250, r = "221021:10,220688:1,14256:8,14048:8", prof = "Tailoring", en = "Fractured Mind Pauldrons" },
    [1257489] = { s = 250, r = "14048:5,9210:3,14227:1,14341:1", o = 254127, prof = "Tailoring", en = "Ghostweave Mantle" },
    [44950] = { s = 250, r = "14048:4,2997:1,2605:2,14341:1", o = 34087, prof = "Tailoring", en = "Green Winter Clothes" },
    [446194] = { s = 250, r = "221021:10,220688:1,12803:4,14048:10", prof = "Tailoring", en = "Mantle of Insanity" },
    [44958] = { s = 250, r = "14048:4,2997:1,2604:2,14341:1", o = 34085, prof = "Tailoring", en = "Red Winter Clothes" },
    [1257487] = { s = 250, r = "14048:5,14227:1,14341:1", o = 254123, prof = "Tailoring", en = "Runecloth Cuffs" },
    [18444] = { s = 250, r = "14048:4,14227:2,14341:1", o = 13866, prof = "Tailoring", en = "Runecloth Headband" },
    [1224610] = { s = 250, r = "14048:8", prof = "Tailoring", en = "Scarlet Augur's Cuffs" },
    [1224612] = { s = 250, r = "12811:1,14048:10", prof = "Tailoring", en = "Scarlet Augur's Strap" },
    [446195] = { s = 250, r = "221021:10,220688:1,14256:6,7080:1,14048:3", prof = "Tailoring", en = "Shoulderpads of the Deranged" },
    [23664] = { s = 255, r = "14048:6,12810:4,13926:2,12809:2,14227:2", o = 19056, prof = "Tailoring", en = "Argent Boots" },
    [27660] = { s = 255, r = "14048:6,14344:4,12810:4,14227:4", o = 22249, prof = "Tailoring", en = "Big Bag of Enchantment" },
    [1257491] = { s = 255, r = "14048:5,7076:1,14341:1", o = 254131, prof = "Tailoring", en = "Earthenweave Cuffs" },
    [1257490] = { s = 255, r = "14048:4,9210:2,14227:1,8170:2,14341:1", o = 254129, prof = "Tailoring", en = "Ghostweave Boots" },
    [18445] = { s = 255, r = "14048:4,14342:1,14341:1,249431:10,249430:2,249409:4", o = 14155, prof = "Tailoring", en = "Mooncloth Bag" },
    [1257492] = { s = 255, r = "14048:4,14342:1,14341:1,249431:10,249430:1,249409:1", o = 254133, prof = "Tailoring", en = "Mooncloth Reagent Bag" },
    [27725] = { s = 255, r = "14048:6,14342:2,13468:1,14227:4", o = 22252, prof = "Tailoring", en = "Satchel of Cenarius" },
    [23662] = { s = 255, r = "14048:8,7076:3,12803:3,14227:2", o = 19047, prof = "Tailoring", en = "Wisdom of the Timbermaw" },
    [18446] = { s = 255, r = "14048:8,11176:2,14341:1", o = 14128, prof = "Tailoring", en = "Wizardweave Robe" },
    [1257494] = { s = 260, r = "14048:6,7076:3,14341:1", o = 254137, prof = "Tailoring", en = "Earthenweave Crown" },
    [18451] = { s = 260, r = "14048:8,14256:8,12662:4,14341:2", o = 14106, prof = "Tailoring", en = "Felcloth Robe" },
    [1257493] = { s = 260, r = "14048:6,9210:3,14227:2,14341:1", o = 254135, prof = "Tailoring", en = "Ghostweave Hood" },
    [18449] = { s = 260, r = "14048:7,14227:2,8170:4,14341:1", o = 13867, prof = "Tailoring", en = "Runecloth Shoulders" },
    [1224611] = { s = 260, r = "12811:1,14048:10", prof = "Tailoring", en = "Scarlet Augur's Mitts" },
    [1224614] = { s = 260, r = "12811:1,14048:10", prof = "Tailoring", en = "Scarlet Augur's Soles" },
    [18450] = { s = 260, r = "14048:6,11176:4,7910:1,14341:1", o = 14130, prof = "Tailoring", en = "Wizardweave Turban" },
    [18453] = { s = 265, r = "14048:7,14256:6,12662:4,8170:4,14341:2", o = 14112, prof = "Tailoring", en = "Felcloth Shoulders" },
    [18447] = { s = 270, r = "14048:6,14342:4,14341:1", o = 14138, prof = "Tailoring", en = "Mooncloth Vest" },
    [1224613] = { s = 270, r = "12938:1,12811:1,14048:12", prof = "Tailoring", en = "Scarlet Augur's Leggings" },
    [22902] = { s = 275, r = "14048:6,14342:4,13926:2,14341:2", o = 18486, prof = "Tailoring", en = "Mooncloth Robe" },
    [18448] = { s = 275, r = "14048:5,14342:5,14341:1", o = 14139, prof = "Tailoring", en = "Mooncloth Shoulders" },
    [22870] = { s = 280, r = "14048:12,12809:4,12360:1,14341:2", o = 18413, prof = "Tailoring", en = "Cloak of Warding" },
    [22867] = { s = 280, r = "14048:12,14256:20,12662:6,12808:8,14341:2", o = 18407, prof = "Tailoring", en = "Felcloth Gloves" },
    [22868] = { s = 280, r = "14048:12,7078:10,7910:2,14341:2", o = 18408, prof = "Tailoring", en = "Inferno Gloves" },
    [18452] = { s = 280, r = "14048:4,14342:6,12800:1,12810:2,14341:2", o = 14140, prof = "Tailoring", en = "Mooncloth Circlet" },
    [22869] = { s = 280, r = "14048:12,14342:6,13926:2,14341:2", o = 18409, prof = "Tailoring", en = "Mooncloth Gloves" },
    [1224607] = { s = 280, r = "12938:1,12811:2,14048:12", prof = "Tailoring", en = "Scarlet Augur's Hood" },
    [1224608] = { s = 280, r = "12811:1,14048:10", prof = "Tailoring", en = "Scarlet Augur's Mantle" },
    [1224609] = { s = 280, r = "12938:1,12811:1,14048:12", prof = "Tailoring", en = "Scarlet Augur's Vestments" },
    [26086] = { s = 285, r = "14256:12,12810:6,20520:2,14227:4", o = 21341, prof = "Tailoring", en = "Felcloth Bag" },
    [22813] = { s = 285, r = "14048:2,8170:4,18240:1,14341:1", o = 18258, prof = "Tailoring", en = "Gordok Ogre Suit" },
    [19435] = { s = 285, r = "14048:6,14342:4,7971:2,14341:1", o = 15802, prof = "Tailoring", en = "Mooncloth Boots" },
    [24902] = { s = 285, r = "14048:2,20520:6,14256:2,12810:2,14227:2", o = 20539, prof = "Tailoring", en = "Runed Stygian Belt" },
    [24903] = { s = 285, r = "14048:4,20520:6,14256:4,12810:2,14227:2", o = 20537, prof = "Tailoring", en = "Runed Stygian Boots" },
    [24901] = { s = 285, r = "14048:6,20520:8,14256:6,14227:2", o = 20538, prof = "Tailoring", en = "Runed Stygian Leggings" },
    [1297123] = { s = 285, r = "14048:4,14343:1,7080:3,14341:6", o = 275607, prof = "Tailoring", en = "Swarmtender's Gloves" },
    [461692] = { s = 285, r = "8170:4,14048:2,18240:1,14341:1", prof = "Tailoring", en = "Synthetic Gordok Ogre Suit" },
    [1297120] = { s = 285, r = "14048:4,14343:1,7082:3,14341:6", o = 275604, prof = "Tailoring", en = "Venomspew Gloves" },
    [23665] = { s = 290, r = "14342:5,12809:2,14227:2", o = 19059, prof = "Tailoring", en = "Argent Shoulders" },
    [1227724] = { s = 290, r = "12938:1,14048:24,2604:4,12808:2,12811:2", o = 239148, prof = "Tailoring", en = "Crimson Dawnwoven Bag" },
    [461752] = { s = 290, r = "14048:6,14342:4,14341:1", prof = "Tailoring", en = "Incandescent Mooncloth Leggings" },
    [23663] = { s = 290, r = "14342:5,7076:5,12803:5,14227:2", o = 19050, prof = "Tailoring", en = "Mantle of the Timbermaw" },
    [1297124] = { s = 290, r = "14048:6,14343:1,7080:3,14341:6", o = 275608, prof = "Tailoring", en = "Swarmtender's Cord" },
    [1297121] = { s = 290, r = "14048:6,14343:1,7082:3,14341:6", o = 275605, prof = "Tailoring", en = "Venomspew Cord" },
    [22866] = { s = 295, r = "14048:16,9210:8,14342:8,7080:10,7078:10,14344:4,14341:6,249431:10", o = 18405, prof = "Tailoring", en = "Belt of the Archmage" },
    [18454] = { s = 295, r = "14048:10,14342:8,9210:8,13926:4,12364:4,12810:6,14341:2,249431:10", o = 14146, prof = "Tailoring", en = "Gloves of Spell Mastery" },
    [18457] = { s = 295, r = "14048:12,7078:8,7082:8,7076:8,7080:8,14341:2,249431:10", o = 14152, prof = "Tailoring", en = "Robe of the Archmage" },
    [18458] = { s = 295, r = "14048:12,12662:20,14256:40,7078:8,12808:8,14341:2,249431:10", o = 14153, prof = "Tailoring", en = "Robe of the Void" },
    [1297125] = { s = 295, r = "14048:5,14343:1,7080:3,14341:6", o = 275609, prof = "Tailoring", en = "Swarmtender's Footpads" },
    [18456] = { s = 295, r = "14048:12,14342:8,12811:2,13926:2,9210:8,14341:2,249431:10", o = 14154, prof = "Tailoring", en = "Truefaith Vestments" },
    [1297122] = { s = 295, r = "14048:5,14343:1,7082:3,14341:6", o = 275606, prof = "Tailoring", en = "Venomspew Footpads" },
    [24093] = { s = 300, r = "14342:3,19726:3,12810:4,14048:4,14227:4", o = 19684, prof = "Tailoring", en = "Bloodvine Boots" },
    [24092] = { s = 300, r = "14342:4,19726:4,12804:4,14048:4,14227:2", o = 19683, prof = "Tailoring", en = "Bloodvine Leggings" },
    [24091] = { s = 300, r = "14342:3,19726:5,12804:4,14048:4,14227:2", o = 19682, prof = "Tailoring", en = "Bloodvine Vest" },
    [1292964] = { s = 300, r = "274030:3,14342:2,14048:16,14341:8", o = 273927, prof = "Tailoring", en = "Boots of Conviction" },
    [18455] = { s = 300, r = "14048:8,14342:12,14344:2,249429:5,249428:5,249431:8,14341:2", o = 14156, prof = "Tailoring", en = "Bottomless Bag" },
    [1257495] = { s = 300, r = "14048:8,14342:12,14344:2,249427:5,14341:2,249428:5,249429:5", o = 254139, prof = "Tailoring", en = "Bottomless Reagent Bag" },
    [1306544] = { s = 300, r = "274030:1,14342:1,14048:5", o = 279270, prof = "Tailoring", en = "Cloak of Earth and Sky" },
    [26087] = { s = 300, r = "14256:20,17012:16,19726:8,7078:4,14227:4", o = 21342, prof = "Tailoring", en = "Core Felcloth Bag" },
    [1292980] = { s = 300, r = "274030:3,14342:2,14048:16,14341:8", o = 273943, prof = "Tailoring", en = "Demonheart Boots" },
    [1292978] = { s = 300, r = "274030:3,14342:2,14048:16,14341:8", o = 273941, prof = "Tailoring", en = "Demonheart Gloves" },
    [1292977] = { s = 300, r = "274030:5,14342:3,14048:22,14341:8", o = 273940, prof = "Tailoring", en = "Demonheart Leggings" },
    [1292979] = { s = 300, r = "274030:3,14342:2,14048:16,14341:8", o = 273942, prof = "Tailoring", en = "Demonheart Spaulders" },
    [462282] = { s = 300, r = "14048:16,9210:10,14342:10,7080:12,7078:12,14344:6,14341:6", prof = "Tailoring", en = "Embroidered Belt of the Archmage" },
    [1306543] = { s = 300, r = "274030:1,14342:1,14048:5", o = 279269, prof = "Tailoring", en = "Fel Cape" },
    [1306545] = { s = 300, r = "14256:8,14048:6", o = 279271, prof = "Tailoring", en = "Felblood Soul Bag" },
    [20849] = { s = 300, r = "14048:8,17010:6,7078:4,12810:2,14341:2", o = 16979, prof = "Tailoring", en = "Flarecore Gloves" },
    [23667] = { s = 300, r = "14342:8,17010:5,17011:3,7078:10,14227:4", o = 19165, prof = "Tailoring", en = "Flarecore Leggings" },
    [20848] = { s = 300, r = "14048:12,17010:4,17011:4,12810:6,14341:2", o = 16980, prof = "Tailoring", en = "Flarecore Mantle" },
    [23666] = { s = 300, r = "14342:10,17010:2,17011:3,7078:6,14227:4", o = 19156, prof = "Tailoring", en = "Flarecore Robe" },
    [22759] = { s = 300, r = "14342:6,17010:8,7078:2,12810:6,14341:4", o = 18263, prof = "Tailoring", en = "Flarecore Wraps" },
    [28210] = { s = 300, r = "19726:1,14342:2,12803:4,14227:4", o = 22660, prof = "Tailoring", en = "Gaea's Embrace" },
    [1292958] = { s = 300, r = "274030:3,14342:2,14048:16,14341:8", o = 273921, prof = "Tailoring", en = "Gloves of Conviction" },
    [1292962] = { s = 300, r = "274030:3,14342:2,14048:16,14341:8", o = 273925, prof = "Tailoring", en = "Handguards of Conviction" },
    [461750] = { s = 300, r = "14048:4,14342:6,12800:1,12810:2,14341:2", prof = "Tailoring", en = "Incandescent Mooncloth Circlet" },
    [461708] = { s = 300, r = "14048:6,14342:4,13926:2,14341:2", prof = "Tailoring", en = "Incandescent Mooncloth Robe" },
    [461747] = { s = 300, r = "14048:6,14342:4,14341:1", prof = "Tailoring", en = "Incandescent Mooncloth Vest" },
    [461727] = { s = 300, r = "14048:5,8170:2,14341:1,15407:1", o = 227844, prof = "Tailoring", en = "Leather-Reinforced Runecloth Bag" },
    [1292961] = { s = 300, r = "274030:5,14342:3,14048:22,14341:8", o = 273924, prof = "Tailoring", en = "Leggings of Conviction" },
    [1263080] = { s = 300, r = "273131:1,14048:4,4470:4", o = 279959, prof = "Tailoring", en = "Loom" },
    [1306541] = { s = 300, r = "274030:2,14342:2,14048:7", o = 279267, prof = "Tailoring", en = "Mana-infused Cord" },
    [1292944] = { s = 300, r = "274030:3,14342:2,14048:16,14341:8", o = 273907, prof = "Tailoring", en = "Manaflare Boots" },
    [1292942] = { s = 300, r = "274030:3,14342:2,14048:16,14341:8", o = 273905, prof = "Tailoring", en = "Manaflare Gloves" },
    [1292943] = { s = 300, r = "274030:3,14342:2,14048:16,14341:8", o = 273906, prof = "Tailoring", en = "Manaflare Mantle" },
    [1292941] = { s = 300, r = "274030:5,14342:3,14048:22,14341:8", o = 273904, prof = "Tailoring", en = "Manaflare Pants" },
    [1292959] = { s = 300, r = "274030:3,14342:2,14048:16,14341:8", o = 273922, prof = "Tailoring", en = "Mantle of Conviction" },
    [1292957] = { s = 300, r = "274030:5,14342:3,14048:22,14341:8", o = 273920, prof = "Tailoring", en = "Pants of Conviction" },
    [1292963] = { s = 300, r = "274030:3,14342:2,14048:16,14341:8", o = 273926, prof = "Tailoring", en = "Pauldrons of Conviction" },
    [1306542] = { s = 300, r = "274030:2,14342:2,14048:7", o = 279268, prof = "Tailoring", en = "Rime-encrusted Boots" },
    [1306540] = { s = 300, r = "274030:3,14342:3,14048:9", o = 279266, prof = "Tailoring", en = "Robes of Fiery Devastation" },
    [28481] = { s = 300, r = "14048:4,14342:2,12803:2,14227:2", o = 22757, prof = "Tailoring", en = "Sylvan Crown" },
    [28482] = { s = 300, r = "14048:2,12803:4,14227:2", o = 22758, prof = "Tailoring", en = "Sylvan Shoulders" },
    [28480] = { s = 300, r = "14048:4,19726:2,12803:2,14227:2", o = 22756, prof = "Tailoring", en = "Sylvan Vest" },
    [1292960] = { s = 300, r = "274030:3,14342:2,14048:16,14341:8", o = 273923, prof = "Tailoring", en = "Treads of Conviction" },
    [1214173] = { s = 315, r = "234008:5", prof = "Tailoring", en = "Bolt of Qiraji Silk" },
    [1223770] = { s = 315, r = "236656:5,14048:4,7080:4,14227:4", prof = "Tailoring", en = "Frosty Gloves" },
    [1223768] = { s = 315, r = "236656:7,14048:8,7080:6,14227:8", prof = "Tailoring", en = "Frosty Vest" },
    [1223772] = { s = 315, r = "236656:4,14048:2,7080:2,14227:4", prof = "Tailoring", en = "Frosty Wrists" },
    [28208] = { s = 315, r = "22682:5,14048:4,7080:2,14227:4", o = 22658, prof = "Tailoring", en = "Glacial Cloak" },
    [28205] = { s = 315, r = "22682:5,14048:4,7080:4,14227:4", o = 22654, prof = "Tailoring", en = "Glacial Gloves" },
    [28207] = { s = 315, r = "22682:7,14048:8,7080:6,14227:8", o = 22652, prof = "Tailoring", en = "Glacial Vest" },
    [28209] = { s = 315, r = "22682:4,14048:2,7080:2,14227:4", o = 22655, prof = "Tailoring", en = "Glacial Wrists" },
    [1213527] = { s = 315, r = "234009:15,14342:8,12810:8,14341:1", prof = "Tailoring", en = "Vampiric Cowl" },
    [1213532] = { s = 315, r = "234009:25,14342:12,12810:12,14341:1", prof = "Tailoring", en = "Vampiric Robe" },
    [1213530] = { s = 315, r = "234009:15,14342:8,12810:8,14341:1", prof = "Tailoring", en = "Vampiric Shawl" },
    [1214306] = { s = 320, r = "14048:30,20381:4,12803:4,14342:4,14227:6", prof = "Tailoring", en = "Dreamscale Bracers" },
    [1214307] = { s = 320, r = "14048:30,20381:5,12803:4,14342:4,14227:6", prof = "Tailoring", en = "Dreamscale Mitts" },
    [1213536] = { s = 320, r = "234009:9,234007:8,15407:4,12810:8,14341:1", prof = "Tailoring", en = "Qiraji Silk Cape" },
    [1213538] = { s = 320, r = "234009:9,234007:8,15407:4,12810:8,14341:1", prof = "Tailoring", en = "Qiraji Silk Cloak" },
    [1213540] = { s = 320, r = "234009:9,234007:8,15407:4,12810:8,14341:1", prof = "Tailoring", en = "Qiraji Silk Drape" },
    [1213534] = { s = 320, r = "234009:9,234007:8,15407:4,12810:8,14341:1", prof = "Tailoring", en = "Qiraji Silk Scarf" },
    -- ---- Enchanting: 260 recipes ----
    [1245320] = { s = 1, r = "10940:1", o = 247786, n = 3, prof = "Enchanting", en = "Dust to Motes" },
    [7418] = { s = 1, r = "247786:1", prof = "Enchanting", en = "Enchant Bracer - Inferior Stamina" },
    [1245321] = { s = 1, r = "4470:1,247786:1", o = 247789, prof = "Enchanting", en = "Novice's Practice Wand" },
    [7421] = { s = 1, r = "6217:1,247786:1", o = 6218, prof = "Enchanting", en = "Runed Copper Rod" },
    [25124] = { s = 5, r = "10940:1,17034:1,3371:1", o = 20744, prof = "Enchanting", en = "Minor Wizard Oil" },
    [14293] = { s = 10, r = "4470:1,10938:1", o = 11287, prof = "Enchanting", en = "Lesser Magic Wand" },
    [7420] = { s = 15, r = "10940:1", prof = "Enchanting", en = "Enchant Chest - Inferior Stamina" },
    [7443] = { s = 20, r = "10938:1", prof = "Enchanting", en = "Enchant Chest - Minor Intellect" },
    [1230643] = { s = 20, r = "4470:1,10940:1", o = 279976, prof = "Enchanting", en = "Enchanted Lute" },
    [7426] = { s = 40, r = "10938:1", prof = "Enchanting", en = "Enchant Chest - Minor Absorption" },
    [7454] = { s = 45, r = "10940:1,10938:1", prof = "Enchanting", en = "Enchant Cloak - Minor Resistance" },
    [7457] = { s = 50, r = "10940:2", prof = "Enchanting", en = "Enchant Bracer - Minor Stamina" },
    [7766] = { s = 60, r = "10938:1", prof = "Enchanting", en = "Enchant Bracer - Minor Spirit" },
    [7748] = { s = 60, r = "10940:1,10938:1", prof = "Enchanting", en = "Enchant Chest - Lesser Stamina" },
    [1248458] = { s = 70, r = "10938:1", prof = "Enchanting", en = "Enchant Bracer - Minor Intellect" },
    [7771] = { s = 70, r = "10940:2", prof = "Enchanting", en = "Enchant Cloak - Minor Protection" },
    [14807] = { s = 70, r = "4470:1,10938:2", o = 11288, prof = "Enchanting", en = "Greater Magic Wand" },
    [7779] = { s = 80, r = "10940:1,10938:2", prof = "Enchanting", en = "Enchant Bracer - Minor Agility" },
    [7428] = { s = 80, r = "10938:1", prof = "Enchanting", en = "Enchant Bracer - Minor Deflect" },
    [7782] = { s = 80, r = "10940:3", prof = "Enchanting", en = "Enchant Bracer - Minor Strength" },
    [7776] = { s = 80, r = "10938:2", prof = "Enchanting", en = "Enchant Chest - Lesser Intellect" },
    [1248459] = { s = 90, r = "10938:2", prof = "Enchanting", en = "Enchant Bracer - Minor Healing Power" },
    [7786] = { s = 90, r = "10940:2,10939:1", prof = "Enchanting", en = "Enchant Weapon - Minor Beastslayer" },
    [7788] = { s = 90, r = "10940:1,10938:1,10978:1", prof = "Enchanting", en = "Enchant Weapon - Minor Striking" },
    [430409] = { s = 100, r = "3372:1,10939:1,10940:5", prof = "Enchanting", en = "Blackfathom Mana Oil" },
    [7793] = { s = 100, r = "10938:4", prof = "Enchanting", en = "Enchant 2H Weapon - Lesser Intellect" },
    [7745] = { s = 100, r = "10940:1,10978:1", prof = "Enchanting", en = "Enchant 2H Weapon - Minor Impact" },
    [7795] = { s = 100, r = "6338:1,10940:3,10938:4,1210:1", o = 6339, prof = "Enchanting", en = "Runed Silver Rod" },
    [13378] = { s = 105, r = "10998:1,10940:1", prof = "Enchanting", en = "Enchant Shield - Minor Stamina" },
    [13380] = { s = 110, r = "10998:1,10940:3", prof = "Enchanting", en = "Enchant 2H Weapon - Lesser Spirit" },
    [13419] = { s = 110, r = "10998:1", prof = "Enchanting", en = "Enchant Cloak - Minor Agility" },
    [13421] = { s = 115, r = "10940:3,10978:1", prof = "Enchanting", en = "Enchant Cloak - Lesser Protection" },
    [13464] = { s = 115, r = "10940:1,10978:1", prof = "Enchanting", en = "Enchant Shield - Lesser Protection" },
    [7859] = { s = 120, r = "10998:1", prof = "Enchanting", en = "Enchant Bracer - Lesser Spirit" },
    [7857] = { s = 120, r = "10940:2,10998:1", prof = "Enchanting", en = "Enchant Chest - Stamina" },
    [448624] = { s = 120, r = "4470:1,10940:4", o = 220792, prof = "Enchanting", en = "Scroll of Spatial Mending" },
    [7867] = { s = 125, r = "10940:3,10998:1", prof = "Enchanting", en = "Enchant Boots - Minor Agility" },
    [7863] = { s = 125, r = "10940:4", prof = "Enchanting", en = "Enchant Boots - Minor Stamina" },
    [7861] = { s = 125, r = "6371:1,10998:1", prof = "Enchanting", en = "Enchant Cloak - Lesser Fire Resistance" },
    [13501] = { s = 130, r = "11083:1", prof = "Enchanting", en = "Enchant Bracer - Lesser Stamina" },
    [13485] = { s = 130, r = "10998:1,10940:2", prof = "Enchanting", en = "Enchant Shield - Lesser Spirit" },
    [1248752] = { s = 130, r = "10978:1,10939:2,10940:5,4605:1", o = 249396, prof = "Enchanting", en = "Mystic Mushroom" },
    [1248755] = { s = 130, r = "11084:1,10939:2,10940:3,4470:1", o = 249398, prof = "Enchanting", en = "Polished Driftwood Icon" },
    [1248754] = { s = 130, r = "11084:1,10939:1,10940:2,3013:5", o = 249397, prof = "Enchanting", en = "Tenets of the Silver Hand" },
    [13522] = { s = 135, r = "10998:1,6048:1", prof = "Enchanting", en = "Enchant Cloak - Lesser Shadow Resistance" },
    [1263056] = { s = 140, r = "11137:2,11174:1", o = 279985, prof = "Enchanting", en = "Arcane Salvager" },
    [1248460] = { s = 140, r = "11134:1", prof = "Enchanting", en = "Enchant Bracer - Lesser Agility" },
    [13536] = { s = 140, r = "11083:1", prof = "Enchanting", en = "Enchant Bracer - Lesser Strength" },
    [13538] = { s = 140, r = "10940:1,10998:1,11084:1", prof = "Enchanting", en = "Enchant Chest - Lesser Absorption" },
    [1248757] = { s = 140, r = "10940:10,11084:4,11082:4,249391:4,249399:4", prof = "Enchanting", en = "Enchant Weapon - Insight" },
    [13503] = { s = 140, r = "11083:1,11084:1", prof = "Enchanting", en = "Enchant Weapon - Lesser Striking" },
    [1248760] = { s = 140, r = "11083:6,11084:4,11082:6,249391:4,2775:4", prof = "Enchanting", en = "Enchant Weapon - Recovery" },
    [1248805] = { s = 140, r = "11083:8,11084:6,11082:2,249409:4,249410:4", prof = "Enchanting", en = "Enchant Weapon - Revelation" },
    [1248703] = { s = 140, r = "11084:4,10978:2,11291:4,11082:1,10940:5,249391:3", o = 249392, prof = "Enchanting", en = "Glimmering Staff" },
    [1248745] = { s = 140, r = "10978:2,11082:2,10940:5", o = 249394, prof = "Enchanting", en = "Orb of Mystic Insight" },
    [1248748] = { s = 140, r = "10978:2,11082:2,11083:2", o = 249395, prof = "Enchanting", en = "Orb of Souls" },
    [1248739] = { s = 140, r = "11084:2,10978:1,11291:4,11082:1,11083:6,1210:2", o = 249393, prof = "Enchanting", en = "Soulstaff" },
    [13529] = { s = 145, r = "11083:1,11084:1", prof = "Enchanting", en = "Enchant 2H Weapon - Lesser Impact" },
    [13607] = { s = 145, r = "11082:1", prof = "Enchanting", en = "Enchant Chest - Intellect" },
    [13620] = { s = 145, r = "11083:1,6370:1", prof = "Enchanting", en = "Enchant Gloves - Fishing" },
    [13617] = { s = 145, r = "11083:1,3356:1", prof = "Enchanting", en = "Enchant Gloves - Herbalism" },
    [13612] = { s = 145, r = "11083:1,2772:1", prof = "Enchanting", en = "Enchant Gloves - Mining" },
    [13622] = { s = 150, r = "11082:1", prof = "Enchanting", en = "Enchant Bracer - Lesser Intellect" },
    [13626] = { s = 150, r = "10998:1,11083:1,11084:1", prof = "Enchanting", en = "Enchant Chest - Minor Stats" },
    [25125] = { s = 150, r = "11083:1,17034:2,3372:1", o = 20745, prof = "Enchanting", en = "Minor Mana Oil" },
    [13628] = { s = 150, r = "11128:1,5500:1,11082:1,11083:1", o = 11130, prof = "Enchanting", en = "Runed Golden Rod" },
    [13635] = { s = 155, r = "11138:1,11083:1", prof = "Enchanting", en = "Enchant Cloak - Defense" },
    [13631] = { s = 155, r = "11134:1", prof = "Enchanting", en = "Enchant Shield - Lesser Stamina" },
    [14809] = { s = 155, r = "11291:1,11134:1", o = 11289, prof = "Enchanting", en = "Lesser Mystic Wand" },
    [13637] = { s = 160, r = "11083:1", prof = "Enchanting", en = "Enchant Boots - Lesser Agility" },
    [13640] = { s = 160, r = "11083:2", prof = "Enchanting", en = "Enchant Chest - Greater Stamina" },
    [13642] = { s = 165, r = "11134:1", prof = "Enchanting", en = "Enchant Bracer - Spirit" },
    [13644] = { s = 170, r = "11083:2", prof = "Enchanting", en = "Enchant Boots - Lesser Stamina" },
    [13646] = { s = 170, r = "11134:1,11083:1", prof = "Enchanting", en = "Enchant Bracer - Lesser Deflection" },
    [13648] = { s = 170, r = "11083:3", prof = "Enchanting", en = "Enchant Bracer - Stamina" },
    [13657] = { s = 175, r = "11134:1,7068:1", prof = "Enchanting", en = "Enchant Cloak - Fire Resistance" },
    [13653] = { s = 175, r = "5637:1,11138:1", prof = "Enchanting", en = "Enchant Weapon - Lesser Beastslayer" },
    [13655] = { s = 175, r = "7067:1,11138:1", prof = "Enchanting", en = "Enchant Weapon - Lesser Elemental Slayer" },
    [14810] = { s = 175, r = "11291:1,11134:1,11137:1", o = 217287, prof = "Enchanting", en = "Greater Mystic Wand" },
    [13661] = { s = 180, r = "11137:1", prof = "Enchanting", en = "Enchant Bracer - Strength" },
    [13659] = { s = 180, r = "11134:1,11137:1", prof = "Enchanting", en = "Enchant Shield - Spirit" },
    [13663] = { s = 185, r = "11134:1", prof = "Enchanting", en = "Enchant Chest - Greater Intellect" },
    [1248461] = { s = 185, r = "11174:1,11176:1,11291:1", o = 249144, prof = "Enchanting", en = "Twisted Nether Wand" },
    [13687] = { s = 190, r = "11134:2", prof = "Enchanting", en = "Enchant Boots - Lesser Spirit" },
    [1248497] = { s = 190, r = "11137:1", prof = "Enchanting", en = "Enchant Bracer - Agility" },
    [21931] = { s = 190, r = "11135:1,11137:1,11139:1,3819:1", prof = "Enchanting", en = "Enchant Weapon - Winter's Might" },
    [13689] = { s = 195, r = "11135:1,11137:1,11139:1", prof = "Enchanting", en = "Enchant Shield - Lesser Block" },
    [13693] = { s = 195, r = "11135:1,11139:1", prof = "Enchanting", en = "Enchant Weapon - Striking" },
    [13695] = { s = 200, r = "11137:2,11139:1", prof = "Enchanting", en = "Enchant 2H Weapon - Impact" },
    [13700] = { s = 200, r = "11135:1,11137:1,11139:1", prof = "Enchanting", en = "Enchant Chest - Lesser Stats" },
    [13698] = { s = 200, r = "11137:1,7392:1", prof = "Enchanting", en = "Enchant Gloves - Skinning" },
    [25126] = { s = 200, r = "11137:1,17035:2,3372:1", o = 20746, prof = "Enchanting", en = "Lesser Wizard Oil" },
    [13702] = { s = 200, r = "11144:1,7971:1,11135:1,11137:1", o = 11145, prof = "Enchanting", en = "Runed Truesilver Rod" },
    [1248498] = { s = 205, r = "11134:2", prof = "Enchanting", en = "Enchant Bracer - Lesser Healing Power" },
    [13746] = { s = 205, r = "11137:1", prof = "Enchanting", en = "Enchant Cloak - Greater Defense" },
    [13794] = { s = 205, r = "11174:1", prof = "Enchanting", en = "Enchant Cloak - Resistance" },
    [1248510] = { s = 210, r = "11137:2,11139:1,11174:1", prof = "Enchanting", en = "Enchant 2H Weapon - Lesser Agility" },
    [13822] = { s = 210, r = "11174:1", prof = "Enchanting", en = "Enchant Bracer - Intellect" },
    [13815] = { s = 210, r = "11137:1", prof = "Enchanting", en = "Enchant Gloves - Agility" },
    [1249059] = { s = 210, r = "11175:2,11178:8,11176:6,249410:4,249430:4", prof = "Enchanting", en = "Enchant Necklace - Agility" },
    [1249060] = { s = 210, r = "11175:8,11178:2,11176:2,249409:4,249430:4", prof = "Enchanting", en = "Enchant Necklace - Deflection" },
    [1249058] = { s = 210, r = "11175:3,11178:5,11176:4,249391:4,249424:4", prof = "Enchanting", en = "Enchant Necklace - Healing Power" },
    [1249057] = { s = 210, r = "11175:5,11178:3,11176:8,249409:4,249430:4", prof = "Enchanting", en = "Enchant Necklace - Spell Power" },
    [1249019] = { s = 210, r = "11175:4,11178:4,11176:10,249410:4,249425:4", prof = "Enchanting", en = "Enchant Necklace - Strength" },
    [13817] = { s = 210, r = "11137:2", prof = "Enchanting", en = "Enchant Shield - Stamina" },
    [1249006] = { s = 210, r = "11178:3,11175:3,11176:4,249430:2,249409:1,2289:4", o = 249442, prof = "Enchanting", en = "Libram of Invocation" },
    [1248974] = { s = 210, r = "11178:2,11175:4,11176:6,249430:2,249409:1,11291:1", o = 249441, prof = "Enchanting", en = "Talons of Wrath" },
    [1249015] = { s = 210, r = "11178:4,11175:2,11176:2,249432:4,249410:2,11291:2", o = 249443, prof = "Enchanting", en = "Totem of Ancestral Protection" },
    [1248509] = { s = 215, r = "11174:2,11137:1,11291:1", o = 249234, prof = "Enchanting", en = "Dreambough Wand" },
    [13836] = { s = 215, r = "11137:2", prof = "Enchanting", en = "Enchant Boots - Stamina" },
    [13841] = { s = 215, r = "11137:2,6037:1", prof = "Enchanting", en = "Enchant Gloves - Advanced Mining" },
    [1249064] = { s = 220, r = "11178:4,11177:4,11291:4,11175:6,11176:8,249409:2,249430:4", o = 249454, prof = "Enchanting", en = "Dreamstaff" },
    [1248511] = { s = 220, r = "11137:1,11139:1,11174:2", prof = "Enchanting", en = "Enchant 2H Weapon - Lesser Strength" },
    [13846] = { s = 220, r = "11174:1,11137:1", prof = "Enchanting", en = "Enchant Bracer - Greater Spirit" },
    [1249071] = { s = 220, r = "11176:10,11175:4,11178:2", prof = "Enchanting", en = "Enchant Chest - Absorption" },
    [13858] = { s = 220, r = "11137:3", prof = "Enchanting", en = "Enchant Chest - Superior Stamina" },
    [1249061] = { s = 220, r = "11178:6,11177:2,11291:4,11175:4,11176:6,249409:2,249430:4", o = 249453, prof = "Enchanting", en = "Radiant Staff" },
    [1249069] = { s = 220, r = "11178:3,11177:1,11291:2,11175:2,11176:3,249409:1,249430:2", o = 249455, prof = "Enchanting", en = "Truesilver Conduit" },
    [1249070] = { s = 220, r = "6037:4,11175:12,11135:12,249409:1,249430:2", o = 249456, prof = "Enchanting", en = "Twisting Essence Jar" },
    [13890] = { s = 225, r = "11177:1,7909:1,11174:1", prof = "Enchanting", en = "Enchant Boots - Minor Speed" },
    [435903] = { s = 225, r = "11177:1,11176:2", prof = "Enchanting", en = "Enchant Chest - Retricutioner" },
    [13882] = { s = 225, r = "11174:1", prof = "Enchanting", en = "Enchant Cloak - Lesser Agility" },
    [13868] = { s = 225, r = "11137:2,8838:1", prof = "Enchanting", en = "Enchant Gloves - Advanced Herbalism" },
    [13887] = { s = 225, r = "11174:1,11137:2", prof = "Enchanting", en = "Enchant Gloves - Strength" },
    [435481] = { s = 225, r = "11174:4,5637:2,11177:2", prof = "Enchanting", en = "Enchant Weapon - Dismantle" },
    [439156] = { s = 225, r = "11137:5", o = 217308, prof = "Enchanting", en = "Sigil of Innovation" },
    [13917] = { s = 230, r = "11175:1", prof = "Enchanting", en = "Enchant Chest - Superior Intellect" },
    [13905] = { s = 230, r = "11174:2,11176:1", prof = "Enchanting", en = "Enchant Shield - Greater Spirit" },
    [13915] = { s = 230, r = "11177:1,11176:1,9224:1", prof = "Enchanting", en = "Enchant Weapon - Demonslaying" },
    [13935] = { s = 235, r = "11175:1", prof = "Enchanting", en = "Enchant Boots - Agility" },
    [13931] = { s = 235, r = "11174:2,11176:1", prof = "Enchanting", en = "Enchant Bracer - Deflection" },
    [13933] = { s = 235, r = "11178:1,3829:1", prof = "Enchanting", en = "Enchant Shield - Frost Resistance" },
    [13937] = { s = 240, r = "11178:1,11176:1", prof = "Enchanting", en = "Enchant 2H Weapon - Greater Impact" },
    [1248500] = { s = 240, r = "11176:3,11174:1", prof = "Enchanting", en = "Enchant Bracer - Greater Agility" },
    [13939] = { s = 240, r = "11176:1,11174:2", prof = "Enchanting", en = "Enchant Bracer - Greater Strength" },
    [13945] = { s = 245, r = "11176:3", prof = "Enchanting", en = "Enchant Bracer - Greater Stamina" },
    [13941] = { s = 245, r = "11178:1,11176:1,11175:1", prof = "Enchanting", en = "Enchant Chest - Stats" },
    [13943] = { s = 245, r = "11178:1,11175:1", prof = "Enchanting", en = "Enchant Weapon - Greater Striking" },
    [1248505] = { s = 245, r = "16202:1,11176:1,11291:1", o = 249232, prof = "Enchanting", en = "Lesser Eternal Wand" },
    [1248528] = { s = 250, r = "11176:2,15407:1", prof = "Enchanting", en = "Enchant Gloves - Advanced Skinning" },
    [13948] = { s = 250, r = "11178:1,8153:1", prof = "Enchanting", en = "Enchant Gloves - Minor Haste" },
    [13947] = { s = 250, r = "11178:1,11176:2", prof = "Enchanting", en = "Enchant Gloves - Riding Skill" },
    [17181] = { s = 250, r = "8170:1,16202:1", o = 12810, prof = "Enchanting", en = "Enchanted Leather" },
    [17180] = { s = 250, r = "12359:1,11176:3", o = 12655, prof = "Enchanting", en = "Enchanted Thorium" },
    [25127] = { s = 250, r = "11176:1,8831:1,8925:1", o = 20747, prof = "Enchanting", en = "Lesser Mana Oil" },
    [446243] = { s = 250, r = "11176:5", prof = "Enchanting", en = "Sigil of Living Dreams" },
    [20008] = { s = 255, r = "16202:2", prof = "Enchanting", en = "Enchant Bracer - Greater Intellect" },
    [20020] = { s = 260, r = "11176:6", prof = "Enchanting", en = "Enchant Boots - Greater Stamina" },
    [1249114] = { s = 265, r = "11382:1,7080:1,14343:3", o = 249473, prof = "Enchanting", en = "Dormant Heart of the Mountain" },
    [20014] = { s = 265, r = "16202:1,7077:1,7075:1,7079:1,7081:1,7972:1", prof = "Enchanting", en = "Enchant Cloak - Greater Resistance" },
    [20017] = { s = 265, r = "11176:6", prof = "Enchanting", en = "Enchant Shield - Greater Stamina" },
    [13898] = { s = 265, r = "11177:2,7078:1", prof = "Enchanting", en = "Enchant Weapon - Fiery Weapon" },
    [1249107] = { s = 265, r = "11382:1,12808:1,14343:3", o = 249469, prof = "Enchanting", en = "Frozen Heart of the Mountain" },
    [1249112] = { s = 265, r = "11382:1,7076:1,14343:3", o = 249470, prof = "Enchanting", en = "Molten Heart of the Mountain" },
    [15596] = { s = 265, r = "11382:1,7078:1,14343:3", o = 11811, prof = "Enchanting", en = "Smoking Heart of the Mountain" },
    [20009] = { s = 270, r = "16202:2,11176:7", prof = "Enchanting", en = "Enchant Bracer - Superior Spirit" },
    [20012] = { s = 270, r = "16202:2,16204:2", prof = "Enchanting", en = "Enchant Gloves - Greater Agility" },
    [1248650] = { s = 275, r = "16203:1,16204:3,14344:2,11291:1", o = 249385, prof = "Enchanting", en = "Brilliant Wand" },
    [463869] = { s = 275, r = "16204:2,4625:1,8925:1", o = 228980, prof = "Enchanting", en = "Conductive Shield Coating" },
    [20024] = { s = 275, r = "16203:2,16202:1", prof = "Enchanting", en = "Enchant Boots - Spirit" },
    [20026] = { s = 275, r = "16204:6,14343:1", prof = "Enchanting", en = "Enchant Chest - Major Stamina" },
    [1248515] = { s = 275, r = "16203:2,16204:1,11291:1", o = 249237, prof = "Enchanting", en = "Greater Eternal Wand" },
    [25128] = { s = 275, r = "16204:3,4625:2,8925:1", o = 20750, prof = "Enchanting", en = "Wizard Oil" },
    [1231139] = { s = 280, r = "14344:10,12811:4,20725:4,12938:1", prof = "Enchanting", en = "Enchant 2H Weapon - Grand Arcanist" },
    [1232172] = { s = 280, r = "14344:10,12811:6,20725:4,12938:1", prof = "Enchanting", en = "Enchant 2H Weapon - Grand Inquisitor" },
    [1328948] = { s = 280, r = "11178:2,11176:8,11175:2,12361:1", prof = "Enchanting", en = "Enchant Boots - Speed" },
    [20016] = { s = 280, r = "16203:2,16204:4", prof = "Enchanting", en = "Enchant Shield - Superior Spirit" },
    [1231128] = { s = 280, r = "14344:5,12811:2,20725:2,12938:1", prof = "Enchanting", en = "Enchant Weapon - Grand Crusader" },
    [1231164] = { s = 280, r = "14344:6,12811:3,20725:2,12938:1", prof = "Enchanting", en = "Enchant Weapon - Grand Sorcerer" },
    [20015] = { s = 285, r = "16204:8", prof = "Enchanting", en = "Enchant Cloak - Superior Defense" },
    [20029] = { s = 285, r = "14343:4,7080:1,7082:1,13467:1", prof = "Enchanting", en = "Enchant Weapon - Icy Chill" },
    [27837] = { s = 290, r = "14344:10,16203:6,16204:14,7082:4", prof = "Enchanting", en = "Enchant 2H Weapon - Agility" },
    [1248668] = { s = 290, r = "14344:8,16203:10,16204:8,12363:4", prof = "Enchanting", en = "Enchant 2H Weapon - Strength" },
    [23801] = { s = 290, r = "16204:16,16203:4,7080:2", prof = "Enchanting", en = "Enchant Bracer - Mana Regeneration" },
    [20028] = { s = 290, r = "16203:3,14343:1", prof = "Enchanting", en = "Enchant Chest - Major Intellect" },
    [23800] = { s = 290, r = "14344:6,16203:6,16204:4,7082:2", prof = "Enchanting", en = "Enchant Weapon - Agility" },
    [23799] = { s = 290, r = "14344:6,16203:6,16204:4,7076:2", prof = "Enchanting", en = "Enchant Weapon - Strength" },
    [20051] = { s = 290, r = "16206:1,13926:1,16204:10,16203:4,14343:4,14344:2", o = 16207, prof = "Enchanting", en = "Runed Arcanite Rod" },
    [463866] = { s = 290, r = "16204:1", o = 228978, prof = "Enchanting", en = "Sigil of Flowing Waters" },
    [20030] = { s = 295, r = "14344:4,16204:10", prof = "Enchanting", en = "Enchant 2H Weapon - Superior Impact" },
    [20023] = { s = 295, r = "16203:8", prof = "Enchanting", en = "Enchant Boots - Greater Agility" },
    [1248599] = { s = 295, r = "16204:3,16203:3,14344:1", prof = "Enchanting", en = "Enchant Bracer - Superior Agility" },
    [20010] = { s = 295, r = "16204:6,16203:6", prof = "Enchanting", en = "Enchant Bracer - Superior Strength" },
    [20013] = { s = 295, r = "16203:4,16204:4", prof = "Enchanting", en = "Enchant Gloves - Greater Strength" },
    [1294054] = { s = 295, r = "248822:1,14343:2,16204:12,16202:4", prof = "Enchanting", en = "Enchant Gloves - Lotus Claw" },
    [20033] = { s = 295, r = "14344:4,12808:4", prof = "Enchanting", en = "Enchant Weapon - Unholy Weapon" },
    [1263082] = { s = 300, r = "273128:1,14344:2,16203:4", o = 279987, prof = "Enchanting", en = "Arcane Forge" },
    [25130] = { s = 300, r = "14344:2,8831:3,18256:1", o = 20748, prof = "Enchanting", en = "Brilliant Mana Oil" },
    [25129] = { s = 300, r = "14344:2,4625:3,18256:1", o = 20749, prof = "Enchanting", en = "Brilliant Wizard Oil" },
    [20036] = { s = 300, r = "16203:12,14344:2", prof = "Enchanting", en = "Enchant 2H Weapon - Major Intellect" },
    [20035] = { s = 300, r = "16203:12,14344:2", prof = "Enchanting", en = "Enchant 2H Weapon - Major Spirit" },
    [1248636] = { s = 300, r = "248819:4,16203:6,249726:4,249274:4,20725:4,248820:4", prof = "Enchanting", en = "Enchant 2H Weapon - Mighty Healing Power" },
    [1248607] = { s = 300, r = "248819:4,16203:6,7076:4,12808:4,20725:4,248820:2", prof = "Enchanting", en = "Enchant 2H Weapon - Mighty Spell Power" },
    [1219580] = { s = 300, r = "20725:3,16204:24,12938:1,8831:6", prof = "Enchanting", en = "Enchant 2H Weapon - Spellblasting" },
    [1220624] = { s = 300, r = "16203:3,16204:9,12808:12,8831:2", prof = "Enchanting", en = "Enchant Bracer - Greater Spellpower" },
    [23802] = { s = 300, r = "14344:2,16204:20,16203:4,12803:6", prof = "Enchanting", en = "Enchant Bracer - Healing Power" },
    [1248665] = { s = 300, r = "14344:3", prof = "Enchanting", en = "Enchant Bracer - Superior Deflection" },
    [1248661] = { s = 300, r = "16203:10", prof = "Enchanting", en = "Enchant Bracer - Superior Intellect" },
    [20011] = { s = 300, r = "16204:15", prof = "Enchanting", en = "Enchant Bracer - Superior Stamina" },
    [20025] = { s = 300, r = "14344:4,16204:15,16203:10", prof = "Enchanting", en = "Enchant Chest - Greater Stats" },
    [1219587] = { s = 300, r = "16203:3,16204:9,7078:1", prof = "Enchanting", en = "Enchant Cloak - Agility" },
    [25086] = { s = 300, r = "20725:3,14344:8,12809:8", prof = "Enchanting", en = "Enchant Cloak - Dodge" },
    [25081] = { s = 300, r = "20725:3,14344:8,7078:4", prof = "Enchanting", en = "Enchant Cloak - Greater Fire Resistance" },
    [25082] = { s = 300, r = "20725:2,14344:8,12803:4", prof = "Enchanting", en = "Enchant Cloak - Greater Nature Resistance" },
    [25083] = { s = 300, r = "20725:3,14344:8,13468:2", prof = "Enchanting", en = "Enchant Cloak - Stealth" },
    [25084] = { s = 300, r = "20725:4,14344:6,11754:2", prof = "Enchanting", en = "Enchant Cloak - Subtlety" },
    [1213626] = { s = 300, r = "20725:2,14344:5,12753:2", prof = "Enchanting", en = "Enchant Gloves - Arcane Power" },
    [25078] = { s = 300, r = "20725:2,14344:10,7078:4", prof = "Enchanting", en = "Enchant Gloves - Fire Power" },
    [25074] = { s = 300, r = "20725:3,14344:10,7080:4", prof = "Enchanting", en = "Enchant Gloves - Frost Power" },
    [25079] = { s = 300, r = "20725:3,14344:8,12811:1", prof = "Enchanting", en = "Enchant Gloves - Healing Power" },
    [1213622] = { s = 300, r = "20725:2,14344:5,13180:5,12735:2", prof = "Enchanting", en = "Enchant Gloves - Holy Power" },
    [1248645] = { s = 300, r = "20725:2,14344:5,248822:4", prof = "Enchanting", en = "Enchant Gloves - Natural Power" },
    [25073] = { s = 300, r = "20725:3,14344:10,12808:6", prof = "Enchanting", en = "Enchant Gloves - Shadow Power" },
    [25080] = { s = 300, r = "20725:3,14344:8,7082:4", prof = "Enchanting", en = "Enchant Gloves - Superior Agility" },
    [1248640] = { s = 300, r = "20725:4,16203:8,7076:4", prof = "Enchanting", en = "Enchant Gloves - Superior Strength" },
    [25072] = { s = 300, r = "20725:4,14344:6,18512:8", prof = "Enchanting", en = "Enchant Gloves - Threat" },
    [1219578] = { s = 300, r = "20725:2,16204:18,7080:2", prof = "Enchanting", en = "Enchant Off-Hand - Excellent Spirit" },
    [1219577] = { s = 300, r = "20725:2,16204:18,7082:2", prof = "Enchanting", en = "Enchant Off-Hand - Superior Intellect" },
    [1219579] = { s = 300, r = "14344:6,16204:18,7082:1,7080:1", prof = "Enchanting", en = "Enchant Off-Hand - Wisdom" },
    [1220623] = { s = 300, r = "14344:5,16204:15,12938:1", prof = "Enchanting", en = "Enchant Shield - Critical Strike" },
    [1219581] = { s = 300, r = "14344:6,16204:18,7076:2", prof = "Enchanting", en = "Enchant Shield - Excellent Stamina" },
    [463871] = { s = 300, r = "14344:4,16203:12,7078:4,7080:4,7076:1,12811:1", prof = "Enchanting", en = "Enchant Shield - Law of Nature" },
    [20034] = { s = 300, r = "14344:4,12811:2", prof = "Enchanting", en = "Enchant Weapon - Crusader" },
    [22750] = { s = 300, r = "14344:4,16203:8,12803:6,7080:6,12811:1", prof = "Enchanting", en = "Enchant Weapon - Healing Power" },
    [20032] = { s = 300, r = "14344:6,12808:6,12803:6", prof = "Enchanting", en = "Enchant Weapon - Lifestealing" },
    [23804] = { s = 300, r = "14344:15,16203:12,16204:20", prof = "Enchanting", en = "Enchant Weapon - Mighty Intellect" },
    [23803] = { s = 300, r = "14344:10,16203:8,16204:15", prof = "Enchanting", en = "Enchant Weapon - Mighty Spirit" },
    [22749] = { s = 300, r = "14344:4,16203:12,7078:4,7080:4,7082:4,13926:2", prof = "Enchanting", en = "Enchant Weapon - Spell Power" },
    [20031] = { s = 300, r = "14344:2,16203:10", prof = "Enchanting", en = "Enchant Weapon - Superior Striking" },
    [1213610] = { s = 300, r = "234011:3,234012:3,16204:2", prof = "Enchanting", en = "Enchanted Repellent" },
    [1306524] = { s = 300, r = "274030:1,20725:1,16203:2,16204:12", o = 279250, prof = "Enchanting", en = "Idol of Swiftness" },
    [1249128] = { s = 300, r = "14344:2,16203:4,16204:6,249431:8,249430:4,249409:2,11291:4", o = 220606, prof = "Enchanting", en = "Idol of the Dream" },
    [1306525] = { s = 300, r = "274030:1,20725:1,16203:2,16204:12", o = 279251, prof = "Enchanting", en = "Idol of the Ursine Twins" },
    [1249152] = { s = 300, r = "14344:4,16203:3,16204:4,249431:8,249430:4,249409:2,10308:4", o = 228175, prof = "Enchanting", en = "Libram of Holy Alacrity" },
    [1306522] = { s = 300, r = "274030:1,20725:1,16203:2,16204:12", o = 279248, prof = "Enchanting", en = "Libram of Infusion" },
    [471400] = { s = 300, r = "8151:3,8152:3,14344:2,18256:1", o = 232611, prof = "Enchanting", en = "Magnificent Trollshine" },
    [1213607] = { s = 300, r = "16203:1,14047:1", prof = "Enchanting", en = "Scroll: Wrath of the Swarm" },
    [1306521] = { s = 300, r = "274030:1,20725:1,16203:2,16204:12", o = 279247, prof = "Enchanting", en = "Steadfast Libram" },
    [1306520] = { s = 300, r = "274030:2,20725:1,14344:6,16202:5", o = 279246, prof = "Enchanting", en = "Torch of Light" },
    [1249154] = { s = 300, r = "14344:1,16203:8,16204:10,249431:8,249430:4,249409:2,11291:4", o = 228176, prof = "Enchanting", en = "Totem of Thunder" },
    [1306523] = { s = 300, r = "274030:1,20725:1,16203:2,16204:12", o = 279249, prof = "Enchanting", en = "Totem of Urgency" },
    [1217189] = { s = 320, r = "14344:2,16204:20,16203:4,7080:2,7078:2,7082:2", prof = "Enchanting", en = "Enchant Bracer - Spell Power" },
    [1213616] = { s = 320, r = "20725:2,16204:8,16203:5,13458:10,234011:2,234010:2", prof = "Enchanting", en = "Enchant Chest - Living Stats" },
    [1213635] = { s = 320, r = "20725:2,234012:20,12810:3,234011:4,234010:4", prof = "Enchanting", en = "Enchanted Mushroom" },
    [1213628] = { s = 320, r = "20725:3,234008:10,234003:2,12810:4", prof = "Enchanting", en = "Enchanted Prayer Tome" },
    [1213600] = { s = 320, r = "234003:3,234005:6,14344:4,2459:3", prof = "Enchanting", en = "Enchanted Stopwatch" },
    [1213633] = { s = 320, r = "20725:3,234012:10,234003:2,12810:3", prof = "Enchanting", en = "Enchanted Totem" },
    [1216022] = { s = 320, r = "20725:2,234012:20,12810:3,234011:4,234010:4", prof = "Enchanting", en = "Idol of Feline Ferocity" },
    [1216020] = { s = 320, r = "20725:2,234012:20,12810:3,234011:4,234010:4", prof = "Enchanting", en = "Idol of Sidereal Wrath" },
    [1216024] = { s = 320, r = "20725:2,234012:20,12810:3,234011:4,234010:4", prof = "Enchanting", en = "Idol of Ursin Power" },
    [1216005] = { s = 320, r = "20725:3,234008:10,234003:2,12810:4", prof = "Enchanting", en = "Libram of Righteousness" },
    [1216010] = { s = 320, r = "20725:3,234008:10,234003:2,12810:4", prof = "Enchanting", en = "Libram of Sanctity" },
    [1216007] = { s = 320, r = "20725:3,234008:10,234003:2,12810:4", prof = "Enchanting", en = "Libram of the Exorcist" },
    [1213598] = { s = 320, r = "234007:10,234010:5,20725:4,234003:10,234011:10", prof = "Enchanting", en = "Lodestone of Retaliation" },
    [1213603] = { s = 320, r = "234007:10,234010:5,20725:6,234003:10,234012:10,234011:10", prof = "Enchanting", en = "Ruby-Encrusted Broach" },
    [1213593] = { s = 320, r = "234006:10,234010:10,20725:6,234004:6,2452:20", prof = "Enchanting", en = "Speedstone" },
    [1213595] = { s = 320, r = "234006:10,234010:10,20725:4,234003:10,234012:10", prof = "Enchanting", en = "Tear of the Dreamer" },
    [1216018] = { s = 320, r = "20725:3,234012:10,234003:2,12810:3", prof = "Enchanting", en = "Totem of Flowing Magma" },
    [1216014] = { s = 320, r = "20725:3,234012:10,234003:2,12810:3", prof = "Enchanting", en = "Totem of Pyroclastic Thunder" },
    [1216016] = { s = 320, r = "20725:3,234012:10,234003:2,12810:3", prof = "Enchanting", en = "Totem of Thunderous Strikes" },
}


return FS
