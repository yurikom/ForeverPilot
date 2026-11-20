-- ForeverPilot / Data/Horizon.lua
--
-- ЗАДЕЛ НА ВПЕРЁД. Персонаж упёрся в потолок навыка 225 на 26 уровне; потолок
-- снимается на 35 (см. H.SKILL_GATE). Этот файл держит то, что понадобится
-- ПОСЛЕ снятия потолка, и то, что надо начать собирать ДО него - прежде всего
-- историю цен на реагенты будущих рецептов: задним числом она не собирается.
--
-- НИЧЕГО ЗДЕСЬ НЕ ВЫКАЧАНО ИЗ СЕТИ, КРОМЕ H.MF_* (см. ниже). Рецепты, пороги,
-- реагенты и цены торговцев извлечены из баз, уже стоящих у игрока, и сверены
-- между двумя независимыми из них. Источник и достоверность у каждой таблицы.
--
-- ИМЕНА АНГЛИЙСКИЕ И ТОЛЬКО ДЛЯ ЧТЕНИЯ ЧЕЛОВЕКОМ (поле en). Русские названия
-- берутся у клиента: ForeverSource:ItemName(itemID). Руками здесь не переведено
-- ничего.
local ADDON, ns = ...

local H = {}
ns.Horizon = H

H.BUILT = "2026-11-17"
-- ПОД КОГО СОБИРАЛИ ЭТОТ СПРАВОЧНИК - ЭТО ПРОВЕНАНС, А НЕ НАСТРОЙКА.
--
-- Здесь стояла таблица H.FOR = { level = 26, class = "MAGE", line = "spArcane",
-- faction = "Horde", tailoring = 225, enchanting = 225 } - конкретный персонаж,
-- объявленный данными модуля. Её никто не читал (проверено по всем файлам), но
-- она выглядела как настройка, под которую подогнан остальной файл, и первое,
-- что с ней хотелось сделать, - начать на неё опираться. А опираться нельзя: у
-- игрока два персонажа, и у второго ни класс, ни профессии, ни уровень не
-- совпадают ни в одной графе.
--
-- Поэтому то же самое осталось СТРОКОЙ в провенансе ниже (H.PROVENANCE.scope):
-- это честное описание границ справочника, которое нельзя случайно принять за
-- признак текущего персонажа. Кем игрок играет, спрашивают у
-- CharacterScanner:Get(), и только у него.

H.PROVENANCE = {
    scope     = "Собран под портняжное дело и наложение чар, навык 225, Орда,"
             .. " уровень 26-35. По другим профессиям данных в этом файле нет —"
             .. " это граница справочника, а не признак текущего персонажа:"
             .. " H:WatchList и H:RecipesFor отвечают по профессиям того, кем"
             .. " играют сейчас, и честно говорят «no-data», когда их нет",
    recipes   = "Mastercraft 2.0.4 RecipeData.lua (из Wowhead Forever), пороги сверены с WhatsTraining Camelot",
    reagents  = "те же рецепты Mastercraft: поле r = \"itemID:qty\"",
    vendorBuy = "Polestar_Codex Items*.lua, запись v<npcID>,<медяки> (build 1.60.1.70888, собран 2026-11-16)",
    itemIds   = "Mastercraft ItemData.lua (имя -> id) и Polestar_Codex (id -> имя), сверено в обе стороны",
    mfCrates  = "theforeverguides.com/professions/merchants-favor (прочитан 2026-11-17); номера ящиков сверены с Polestar_Codex",
    skillGate = "wow-professions.com/forever + theforeverguides.com, прочитаны 2026-11-17",
}

-- Достоверность по таблицам. FACT = из клиентских данных через базу на диске;
-- CACHED = из базы на диске, сверено со вторым источником; WEB = с сайта
-- сообщества, в игре не проверено; ESTIMATE = оценка, не факт.
H.CONFIDENCE = {
    FUTURE_RECIPES = "CACHED",
    PRICE_WATCH    = "CACHED",
    MF_CRATES      = "WEB",
    MF_FAVOR       = "WEB",
    MF_REP         = "WEB",
    MF_NPCS        = "WEB",
    SKILL_GATE     = "WEB",
}

-- ПОТОЛОК НАВЫКА. Клиент - главный источник; это запасной путь и объяснение
-- игроку, почему 225 не двигается. Везде нужен 35 уровень персонажа.
-- openedBy: "trainer" - учится у тренера, "quest" - даётся за задание.
H.SKILL_GATE = {
    [197] = { cap = 225, next = 300, needLevel = 35, openedBy = "trainer", npc = 2399,  en = "Daryl Stack", note = "Artisan Tailoring: навык 200 + уровень 35" },
    [333] = { cap = 225, next = 300, needLevel = 35, openedBy = "trainer", npc = 11073, en = "Annora", note = "единственный тренер Artisan Enchanting; навык 200 + уровень 35; места в базах на диске нет" },
    [185] = { cap = 225, next = 300, needLevel = 35, openedBy = "quest",   npc = 8125,  en = "Dirge Quikcleave", note = "задание Clamlette Surprise" },
    [129] = { cap = 225, next = 300, needLevel = 35, openedBy = "quest",   npc = 12920, en = "Doctor Gregory Victor", note = "задание Triage" },
}
-- npcID сверены по именам в двух базах на диске (Polestar_Codex Npcs*.lua и
-- Mastercraft TrainerData.lua). Координаты и зона - в H.NPCS. То, что потолок
-- снимается именно на 35 уровне, - утверждение сайтов сообщества (WEB), клиент
-- всегда главнее: читать потолок у него, а это объяснение для игрока.

-- NPC, нужные на горизонте. Имя каждого сверено по двум базам на диске
-- (Polestar_Codex Npcs*.lua и Mastercraft TrainerData/VendorData); координаты -
-- из Mastercraft. nil в координатах = базы на диске места не знают, это дыра.
H.NPCS = {
    [2399] = { en = "Daryl Stack", faction = "H", map = 1424, x = 63.4, y = 20.8, zone = "Hillsbrad Foothills" },
    [4561] = { en = "Daniel Bartlett", faction = "H", map = 1458, x = 64.0, y = 38.8, zone = "Undercity" },
    [8125] = { en = "Dirge Quikcleave", faction = "", map = 1446, x = 52.6, y = 28.0, zone = "Tanaris" },
    [11052] = { en = "Timothy Worthington", faction = "A", map = 1445, x = 66.2, y = 51.6, zone = "Dustwallow Marsh" },
    [11073] = { en = "Annora", faction = nil, map = nil, note = "места нет в базах на диске" },
    [11074] = { en = "Hgarth", faction = "H", map = 1442, x = 49.2, y = 57.2, zone = "Stonetalon Mountains" },
    [11189] = { en = "Qia", faction = "", map = 1452, x = 61.2, y = 37.2, zone = "Winterspring" },
    [12920] = { en = "Doctor Gregory Victor", faction = "H", map = 1417, x = 73.4, y = 36.4, zone = "Arathi Highlands" },
    [214070] = { en = "Jornah", faction = "H", map = 1454, x = 51.4, y = 63.8, zone = "Orgrimmar" },
    [214096] = { en = "Dokimi", faction = "H", map = 1456, x = 39.4, y = 53.4, zone = "Thunder Bluff" },
    [214098] = { en = "Gishah", faction = "H", map = 1458, x = 64.4, y = 38.4, zone = "Undercity" },
    [248199] = { en = "Beneris", faction = "", map = 1413, x = 49.6, y = 29.8, zone = "The Barrens" },
    [248202] = { en = "Jim'bek", faction = "", map = 1413, x = 49.6, y = 29.4, zone = "The Barrens" },
    [256400] = { en = "Okamache", faction = nil, map = nil, note = "места нет в базах на диске" },
    [256672] = { en = "Kurvelk Shadowhoof", faction = nil, map = nil, note = "места нет в базах на диске" },
    [266901] = { en = "Pexmit", faction = "", map = 2482, x = 58.8, y = 41.8, zone = "Mount Hyjal" },
}
-- КОНФЛИКТ, не решён: сайт сообщества ставит приёмщика ящиков Dokimi в лагерь
-- в Степях (~50.0, 29.2), а Mastercraft - в Громовой Утёс. Gishah, Jornah и
-- Marcy Baker у Mastercraft тоже стоят в столицах, а не в лагере. Похоже,
-- приёмщиков несколько; какой из них настоящий - проверять в игре. Jim'bek и
-- Beneris (продавцы рецептов за Merchant's Favor) у обоих источников в Степях
-- у западных ворот Перекрёстка - вот им верить можно.

-- ГЛАВНОЕ В ЭТОМ ФАЙЛЕ: СПИСОК НА ИСТОРИЮ ЦЕН.
--
-- Реагенты рецептов портняжного дела и наложения чар с порогом навыка 226-300,
-- то есть всего, что откроется на 35 уровне. Аддону нужно начать писать цены по
-- этим itemID СЕЙЧАС: задним числом история не собирается, а экономика сервера
-- молодая и падает на десятки процентов в неделю.
--
-- recipes = в сколько будущих рецептов входит; qty = сумма количеств по всем
-- этим рецептам (грубая мера спроса, не план закупки); prof = чьи рецепты;
-- vendor/vprice = у какого NPC и за сколько медяков продаётся, если продаётся
-- (это потолок цены: дороже на аукционе брать незачем). vprice = nil - у
-- торговцев нет, только аукцион или фарм.
--
-- В список попал только тот itemID, чьё имя нашлось хотя бы в одной базе на
-- диске, собранной из клиента Forever. Реагенты, которых в этих базах нет,
-- выброшены как, скорее всего, не из Forever - см. H.GAPS.notForever.
H.PRICE_WATCH = {
    [14048] = { recipes = 130, qty = 1092, prof = "T", vendor = nil, vprice = nil, en = "Bolt of Runecloth" },
    [14341] = { recipes = 86, qty = 261, prof = "T", vendor = 989, vprice = 5000, en = "Rune Thread" },
    [14344] = { recipes = 56, qty = 297, prof = "E+T", vendor = nil, vprice = nil, en = "Large Brilliant Shard" },
    [14342] = { recipes = 51, qty = 206, prof = "T", vendor = nil, vprice = nil, en = "Mooncloth" },
    [16204] = { recipes = 42, qty = 417, prof = "E", vendor = nil, vprice = nil, en = "Illusion Dust" },
    [16203] = { recipes = 42, qty = 235, prof = "E+T", vendor = nil, vprice = nil, en = "Greater Eternal Essence" },
    [20725] = { recipes = 30, qty = 76, prof = "E", vendor = nil, vprice = nil, en = "Nexus Crystal" },
    [14227] = { recipes = 30, qty = 73, prof = "T", vendor = nil, vprice = nil, en = "Ironweb Spider Silk" },
    [274030] = { recipes = 27, qty = 72, prof = "E+T", vendor = nil, vprice = nil, en = "Malleable Essence of Nature" },
    [11176] = { recipes = 21, qty = 60, prof = "E+T", vendor = nil, vprice = nil, en = "Dream Dust" },
    [7078] = { recipes = 20, qty = 99, prof = "E+T", vendor = nil, vprice = nil, en = "Essence of Fire" },
    [7080] = { recipes = 18, qty = 70, prof = "E+T", vendor = nil, vprice = nil, en = "Essence of Water" },
    [12811] = { recipes = 18, qty = 33, prof = "E+T", vendor = nil, vprice = nil, en = "Righteous Orb" },
    [14256] = { recipes = 17, qty = 166, prof = "T", vendor = 16015, vprice = 8000, en = "Felcloth" },
    [249430] = { recipes = 17, qty = 99, prof = "E+T", vendor = nil, vprice = nil, en = "Magenta Dye" },
    [249409] = { recipes = 17, qty = 71, prof = "E+T", vendor = nil, vprice = nil, en = "Cerulean Dye" },
    [14343] = { recipes = 15, qty = 30, prof = "E+T", vendor = nil, vprice = nil, en = "Small Brilliant Shard" },
    [7076] = { recipes = 14, qty = 38, prof = "E+T", vendor = nil, vprice = nil, en = "Essence of Earth" },
    [8343] = { recipes = 12, qty = 48, prof = "T", vendor = 989, vprice = 2000, en = "Heavy Silken Thread" },
    [12810] = { recipes = 12, qty = 46, prof = "T", vendor = 14846, vprice = 2000, en = "Enchanted Leather" },
    [249431] = { recipes = 11, qty = 102, prof = "E+T", vendor = nil, vprice = nil, en = "Viridian Dye" },
    [12803] = { recipes = 11, qty = 46, prof = "E+T", vendor = nil, vprice = nil, en = "Living Essence" },
    [7082] = { recipes = 11, qty = 35, prof = "E+T", vendor = nil, vprice = nil, en = "Essence of Air" },
    [12808] = { recipes = 10, qty = 55, prof = "E+T", vendor = nil, vprice = nil, en = "Essence of Undeath" },
    [13926] = { recipes = 10, qty = 35, prof = "E+T", vendor = nil, vprice = nil, en = "Golden Pearl" },
    [8170] = { recipes = 10, qty = 33, prof = "E+T", vendor = 14846, vprice = 2000, en = "Rugged Leather" },
    [12938] = { recipes = 10, qty = 10, prof = "E+T", vendor = nil, vprice = nil, en = "Blood of Heroes" },
    [11178] = { recipes = 9, qty = 26, prof = "E+T", vendor = nil, vprice = nil, en = "Large Radiant Shard" },
    [16202] = { recipes = 9, qty = 19, prof = "E", vendor = nil, vprice = nil, en = "Lesser Eternal Essence" },
    [9210] = { recipes = 8, qty = 46, prof = "T", vendor = nil, vprice = nil, en = "Ghost Dye" },
    [249427] = { recipes = 7, qty = 29, prof = "T", vendor = 263384, vprice = 500, en = "Pristine Leather" },
    [19726] = { recipes = 6, qty = 23, prof = "T", vendor = nil, vprice = nil, en = "Bloodvine" },
    [17010] = { recipes = 5, qty = 25, prof = "T", vendor = nil, vprice = nil, en = "Fiery Core" },
    [8831] = { recipes = 5, qty = 22, prof = "E+T", vendor = nil, vprice = nil, en = "Purple Lotus" },
    [11291] = { recipes = 5, qty = 11, prof = "E", vendor = 227, vprice = 4500, en = "Star Wood" },
    [11175] = { recipes = 5, qty = 6, prof = "E", vendor = nil, vprice = nil, en = "Greater Nether Essence" },
    [12662] = { recipes = 4, qty = 34, prof = "T", vendor = nil, vprice = nil, en = "Demonic Rune" },
    [3577] = { recipes = 4, qty = 24, prof = "T", vendor = nil, vprice = nil, en = "Gold Bar" },
    [7077] = { recipes = 4, qty = 23, prof = "E+T", vendor = nil, vprice = nil, en = "Heart of Fire" },
    [20520] = { recipes = 4, qty = 22, prof = "T", vendor = nil, vprice = nil, en = "Dark Rune" },
    [12809] = { recipes = 4, qty = 16, prof = "E+T", vendor = nil, vprice = nil, en = "Guardian Stone" },
    [11174] = { recipes = 4, qty = 7, prof = "E", vendor = nil, vprice = nil, en = "Lesser Nether Essence" },
    [11382] = { recipes = 4, qty = 4, prof = "E", vendor = nil, vprice = nil, en = "Blood of the Mountain" },
    [221021] = { recipes = 3, qty = 30, prof = "T", vendor = nil, vprice = nil, en = "Nightmare Seed" },
    [7971] = { recipes = 3, qty = 20, prof = "T", vendor = nil, vprice = nil, en = "Black Pearl" },
    [7079] = { recipes = 3, qty = 19, prof = "E+T", vendor = nil, vprice = nil, en = "Globe of Water" },
    [2604] = { recipes = 3, qty = 14, prof = "T", vendor = 66, vprice = 50, en = "Red Dye" },
    [17011] = { recipes = 3, qty = 10, prof = "T", vendor = nil, vprice = nil, en = "Lava Core" },
    [4625] = { recipes = 3, qty = 6, prof = "E", vendor = nil, vprice = nil, en = "Firebloom" },
    [18256] = { recipes = 3, qty = 3, prof = "E", vendor = 844, vprice = 30000, en = "Imbued Vial" },
    [8925] = { recipes = 3, qty = 3, prof = "E", vendor = 844, vprice = 2500, en = "Crystal Vial" },
    [249429] = { recipes = 2, qty = 10, prof = "T", vendor = 263384, vprice = 1500, en = "Pristine Scale" },
    [249428] = { recipes = 2, qty = 10, prof = "T", vendor = 263384, vprice = 1000, en = "Pristine Hide" },
    [12804] = { recipes = 2, qty = 8, prof = "T", vendor = nil, vprice = nil, en = "Powerful Mojo" },
    [248819] = { recipes = 2, qty = 8, prof = "E", vendor = 263384, vprice = 12000, en = "Fel Crystal" },
    [248820] = { recipes = 2, qty = 6, prof = "E", vendor = 263384, vprice = 60000, en = "Torbernite" },
    [248822] = { recipes = 2, qty = 5, prof = "E", vendor = 263384, vprice = 6000, en = "Death Lotus" },
    [7910] = { recipes = 2, qty = 3, prof = "T", vendor = nil, vprice = nil, en = "Star Ruby" },
    [13468] = { recipes = 2, qty = 3, prof = "E+T", vendor = 263384, vprice = 4000, en = "Black Lotus" },
    [11177] = { recipes = 2, qty = 3, prof = "E", vendor = nil, vprice = nil, en = "Small Radiant Shard" },
    [18240] = { recipes = 2, qty = 2, prof = "T", vendor = nil, vprice = nil, en = "Ogre Tannin" },
    [2997] = { recipes = 2, qty = 2, prof = "T", vendor = nil, vprice = nil, en = "Bolt of Woolen Cloth" },
    [12800] = { recipes = 2, qty = 2, prof = "T", vendor = nil, vprice = nil, en = "Azerothian Diamond" },
    [15407] = { recipes = 2, qty = 2, prof = "E+T", vendor = nil, vprice = nil, en = "Cured Rugged Hide" },
    [17012] = { recipes = 1, qty = 16, prof = "T", vendor = nil, vprice = nil, en = "Core Leather" },
    [11040] = { recipes = 1, qty = 8, prof = "T", vendor = nil, vprice = nil, en = "Morrowgrain" },
    [18512] = { recipes = 1, qty = 8, prof = "E", vendor = nil, vprice = nil, en = "Larval Acid" },
    [13180] = { recipes = 1, qty = 5, prof = "E", vendor = nil, vprice = nil, en = "Stratholme Holy Water" },
    [7068] = { recipes = 1, qty = 4, prof = "T", vendor = nil, vprice = nil, en = "Elemental Fire" },
    [12364] = { recipes = 1, qty = 4, prof = "T", vendor = nil, vprice = nil, en = "Huge Emerald" },
    [4470] = { recipes = 1, qty = 4, prof = "T", vendor = 151, vprice = 38, en = "Simple Wood" },
    [249726] = { recipes = 1, qty = 4, prof = "E", vendor = nil, vprice = nil, en = "Azerothium Bar" },
    [249274] = { recipes = 1, qty = 4, prof = "E", vendor = 263384, vprice = 1000, en = "Stranglevine" },
    [12363] = { recipes = 1, qty = 4, prof = "E", vendor = 263384, vprice = 8000, en = "Arcane Crystal" },
    [10308] = { recipes = 1, qty = 4, prof = "E", vendor = 14847, vprice = 600, en = "Scroll of Intellect IV" },
    [234011] = { recipes = 1, qty = 3, prof = "E", vendor = nil, vprice = nil, en = "Qiraji Stalker Venom" },
    [234012] = { recipes = 1, qty = 3, prof = "E", vendor = nil, vprice = nil, en = "Hive Thistle" },
    [8151] = { recipes = 1, qty = 3, prof = "E", vendor = nil, vprice = nil, en = "Flask of Mojo" },
    [8152] = { recipes = 1, qty = 3, prof = "E", vendor = nil, vprice = nil, en = "Flask of Big Mojo" },
    [2605] = { recipes = 1, qty = 2, prof = "T", vendor = 843, vprice = 100, en = "Green Dye" },
    [11754] = { recipes = 1, qty = 2, prof = "E", vendor = nil, vprice = nil, en = "Black Diamond" },
    [12753] = { recipes = 1, qty = 2, prof = "E", vendor = nil, vprice = nil, en = "Skin of Shadow" },
    [12735] = { recipes = 1, qty = 2, prof = "E", vendor = nil, vprice = nil, en = "Frayed Abomination Stitching" },
    [12360] = { recipes = 1, qty = 1, prof = "T", vendor = nil, vprice = nil, en = "Arcanite Bar" },
    [273131] = { recipes = 1, qty = 1, prof = "T", vendor = nil, vprice = nil, en = "Bottled Screams" },
    [273128] = { recipes = 1, qty = 1, prof = "E", vendor = nil, vprice = nil, en = "Maker's Spark" },
    [12361] = { recipes = 1, qty = 1, prof = "E", vendor = nil, vprice = nil, en = "Blue Sapphire" },
    [7075] = { recipes = 1, qty = 1, prof = "E", vendor = nil, vprice = nil, en = "Core of Earth" },
    [7081] = { recipes = 1, qty = 1, prof = "E", vendor = nil, vprice = nil, en = "Breath of Wind" },
    [7972] = { recipes = 1, qty = 1, prof = "E", vendor = nil, vprice = nil, en = "Ichor of Undeath" },
    [8153] = { recipes = 1, qty = 1, prof = "E", vendor = nil, vprice = nil, en = "Wildvine" },
    [3829] = { recipes = 1, qty = 1, prof = "E", vendor = nil, vprice = nil, en = "Frost Oil" },
    [9224] = { recipes = 1, qty = 1, prof = "E", vendor = nil, vprice = nil, en = "Potion of Demon Slaying" },
    [13467] = { recipes = 1, qty = 1, prof = "E", vendor = nil, vprice = nil, en = "Icecap" },
    [12359] = { recipes = 1, qty = 1, prof = "E", vendor = nil, vprice = nil, en = "Thorium Bar" },
    [16206] = { recipes = 1, qty = 1, prof = "E", vendor = nil, vprice = nil, en = "Arcanite Rod" },
    [14047] = { recipes = 1, qty = 1, prof = "E", vendor = nil, vprice = nil, en = "Runecloth" },
}
H.PRICE_WATCH_COUNT = 97

-- РЕЦЕПТЫ 226-300: что именно откроется и что для этого нужно.
-- skill = порог навыка; wt = тот же порог по второй базе (WhatsTraining), nil -
-- рецепта там нет; agree = 1 пороги совпали, 0 разошлись (верить осторожно),
-- -1 второй базой не подтверждён. out = что делает, pat = предмет-рецепт,
-- kind/where = где учится, vend = NPC продавца, reag = "itemID:кол-во,...".
H.FUTURE_RECIPES_197 = {  -- Tailoring
    { en = "Brightcloth Cloak", skill = 230, wt = 230, agree = 1, spell = 18420, out = 14103, pat = 14484, kind = "world", vend = nil, reag = "14048:4,3577:2,14341:1" },
    { en = "Cenarion Herb Bag", skill = 230, wt = 230, agree = 1, spell = 27724, out = 22251, pat = 22310, kind = "vendor", vend = { 15179 }, reag = "14048:5,8831:10,11040:8,14341:2" },
    { en = "Cindercloth Cloak", skill = 230, wt = 230, agree = 1, spell = 18418, out = 14044, pat = 14482, kind = "drop", vend = nil, reag = "14048:5,7078:1,14341:1" },
    { en = "Enchanted Runecloth Bag", skill = 230, wt = 230, agree = 1, spell = 27659, out = 22248, pat = 22308, kind = "vendor", vend = { 12944, 15419 }, reag = "14048:5,16203:2,14341:2" },
    { en = "Felcloth Pants", skill = 230, wt = 230, agree = 1, spell = 18419, out = 14107, pat = 14483, kind = "vendor", vend = { 12022 }, reag = "14048:5,14256:4,14341:1" },
    { en = "Mooncloth", skill = 230, wt = 230, agree = 1, spell = 18560, out = 14342, pat = 14526, kind = "vendor", vend = { 11189 }, reag = "14256:2" },
    { en = "Runecloth Gloves", skill = 230, wt = 230, agree = 1, spell = 18417, out = 13863, pat = 14481, kind = "vendor", vend = { 11189 }, reag = "14048:4,8170:4,14341:1" },
    { en = "Wizardweave Leggings", skill = 230, wt = 230, agree = 1, spell = 18421, out = 14132, pat = 14485, kind = "drop", vend = nil, reag = "14048:6,11176:1,14341:1" },
    { en = "Black Gloves", skill = 235, wt = 235, agree = 1, spell = 1257476, out = 254101, pat = 254102, kind = "world", vend = nil, reag = "14048:8,8343:4,249430:4,249409:4,7971:4" },
    { en = "Black Sandals", skill = 235, wt = 235, agree = 1, spell = 1257482, out = 254113, pat = 254114, kind = "vendor", vend = { 248202, 256735 }, reag = "14048:10,8343:4,249430:10,249409:6,7971:14,249427:4" },
    { en = "Cindercloth Pants", skill = 235, wt = 235, agree = 1, spell = 18434, out = 14045, pat = 14490, kind = "drop", vend = nil, reag = "14048:6,7078:1,14341:1" },
    { en = "Cloak of Fire", skill = 235, wt = 235, agree = 1, spell = 18422, out = 14134, pat = 14486, kind = "drop", vend = nil, reag = "14048:6,7078:4,7077:4,7068:4,14341:1" },
    { en = "Fiery Gloves", skill = 235, wt = 235, agree = 1, spell = 1257475, out = 254099, pat = 254100, kind = "drop", vend = nil, reag = "14048:8,8343:4,249430:4,249409:4,7077:4" },
    { en = "Fiery Sandals", skill = 235, wt = 235, agree = 1, spell = 1257481, out = 254111, pat = 254112, kind = "vendor", vend = { 248202, 256735 }, reag = "14048:10,8343:4,249430:10,249409:6,7077:14,249427:4" },
    { en = "Frostweave Pants", skill = 235, wt = 235, agree = 1, spell = 18424, out = 13871, pat = 14489, kind = "world", vend = nil, reag = "14048:6,7080:1,14341:1" },
    { en = "Frothing Gloves", skill = 235, wt = 235, agree = 1, spell = 1257474, out = 254097, pat = 254098, kind = "drop", vend = nil, reag = "14048:8,8343:4,249430:4,249409:4,7079:4" },
    { en = "Frothing Sandals", skill = 235, wt = 235, agree = 1, spell = 1257480, out = 254109, pat = 254110, kind = "vendor", vend = { 248202, 256735 }, reag = "14048:10,8343:4,249430:10,249409:6,7079:14,249427:4" },
    { en = "Gilded Gloves", skill = 235, wt = 235, agree = 1, spell = 1257473, out = 254095, pat = 254096, kind = "world", vend = nil, reag = "14048:8,8343:4,249430:4,249409:4,3577:4" },
    { en = "Gilded Sandals", skill = 235, wt = 235, agree = 1, spell = 1257479, out = 254107, pat = 254108, kind = "vendor", vend = { 248202, 256735 }, reag = "14048:10,8343:4,249430:10,249409:6,3577:14,249427:4" },
    { en = "Golden Gloves", skill = 235, wt = 235, agree = 1, spell = 1257477, out = 254103, pat = 254104, kind = "world", vend = nil, reag = "14048:8,8343:4,249430:4,249409:4,13926:4" },
    { en = "Golden Sandals", skill = 235, wt = 235, agree = 1, spell = 1257483, out = 254115, pat = 254116, kind = "vendor", vend = { 248202, 256735 }, reag = "14048:10,8343:4,249430:10,249409:6,13926:14,249427:4" },
    { en = "Radiant Gloves", skill = 235, wt = 235, agree = 1, spell = 1257478, out = 254105, pat = 254106, kind = "world", vend = nil, reag = "14048:8,8343:4,249430:4,249409:4,11178:4" },
    { en = "Radiant Sandals", skill = 235, wt = 235, agree = 1, spell = 1257484, out = 254117, pat = 254118, kind = "vendor", vend = { 248202, 256735 }, reag = "14048:10,8343:4,249430:10,249409:6,11178:14,249427:4" },
    { en = "Runecloth Boots", skill = 235, wt = 235, agree = 1, spell = 18423, out = 13864, pat = 14488, kind = "vendor", vend = { 7940 }, reag = "14048:4,14227:2,8170:4,14341:1" },
    { en = "Earthenweave Mantle", skill = 240, wt = 240, agree = 1, spell = 1257485, out = 254119, pat = 254120, kind = "drop", vend = nil, reag = "14048:6,7076:1,14341:1" },
    { en = "Felcloth Boots", skill = 240, wt = 240, agree = 1, spell = 18437, out = 14108, pat = 14492, kind = "world", vend = nil, reag = "14048:6,14256:4,8170:4,14341:1" },
    { en = "Runecloth Pants", skill = 240, wt = 240, agree = 1, spell = 18438, out = 13865, pat = 14491, kind = "world", vend = nil, reag = "14048:6,14227:2,14341:1" },
    { en = "Brightcloth Pants", skill = 245, wt = 245, agree = 1, spell = 18439, out = 14104, pat = 14494, kind = "world", vend = nil, reag = "14048:6,3577:4,14227:1,14341:1" },
    { en = "Earthenweave Leggings", skill = 245, wt = 245, agree = 1, spell = 1257488, out = 254125, pat = 254126, kind = "drop", vend = nil, reag = "14048:6,7076:2,14341:1" },
    { en = "Felcloth Hood", skill = 245, wt = 245, agree = 1, spell = 18442, out = 14111, pat = 14496, kind = "world", vend = nil, reag = "14048:5,14256:4,14341:1" },
    { en = "Ghostweave Pants", skill = 245, wt = 245, agree = 1, spell = 18441, out = 14144, pat = 14495, kind = "drop", vend = nil, reag = "14048:6,9210:4,14341:1" },
    { en = "Mooncloth Leggings", skill = 245, wt = 245, agree = 1, spell = 18440, out = 14137, pat = 14497, kind = "world", vend = nil, reag = "14048:6,14342:4,14341:1" },
    { en = "Robe of Winter Night", skill = 245, wt = 245, agree = 1, spell = 18436, out = 14136, pat = 14493, kind = "drop", vend = nil, reag = "14048:10,14256:12,12808:4,7080:4,14341:1" },
    { en = "Crusader's Knapsack", skill = 250, wt = 250, agree = 1, spell = 1227723, out = 239147, pat = 239149, kind = "unknown", vend = nil, reag = "12811:1,14048:14,2604:8,14227:3" },
    { en = "Earthenweave Vest", skill = 250, wt = 250, agree = 1, spell = 1257486, out = 254121, pat = 254122, kind = "drop", vend = nil, reag = "14048:8,7076:1,14341:1" },
    { en = "Fractured Mind Pauldrons", skill = 250, wt = nil, agree = -1, spell = 446193, out = nil, pat = nil, kind = "unknown", vend = nil, reag = "221021:10,220688:1,14256:8,14048:8" },
    { en = "Ghostweave Mantle", skill = 250, wt = 250, agree = 1, spell = 1257489, out = 254127, pat = 254128, kind = "unknown", vend = nil, reag = "14048:5,9210:3,14227:1,14341:1" },
    { en = "Green Winter Clothes", skill = 250, wt = 250, agree = 1, spell = 44950, out = 34087, pat = 34261, kind = "unknown", vend = nil, reag = "14048:4,2997:1,2605:2,14341:1" },
    { en = "Mantle of Insanity", skill = 250, wt = nil, agree = -1, spell = 446194, out = nil, pat = nil, kind = "unknown", vend = nil, reag = "221021:10,220688:1,12803:4,14048:10" },
    { en = "Red Winter Clothes", skill = 250, wt = 250, agree = 1, spell = 44958, out = 34085, pat = 34319, kind = "unknown", vend = nil, reag = "14048:4,2997:1,2604:2,14341:1" },
    { en = "Runecloth Cuffs", skill = 250, wt = 250, agree = 1, spell = 1257487, out = 254123, pat = 254124, kind = "vendor", vend = { 266901 }, reag = "14048:5,14227:1,14341:1" },
    { en = "Runecloth Headband", skill = 250, wt = 250, agree = 1, spell = 18444, out = 13866, pat = 14498, kind = "world", vend = nil, reag = "14048:4,14227:2,14341:1" },
    { en = "Scarlet Augur's Cuffs", skill = 250, wt = 250, agree = 1, spell = 1224610, out = nil, pat = 238301, kind = "world", vend = nil, reag = "14048:8" },
    { en = "Scarlet Augur's Strap", skill = 250, wt = 250, agree = 1, spell = 1224612, out = nil, pat = 238303, kind = "world", vend = nil, reag = "12811:1,14048:10" },
    { en = "Shoulderpads of the Deranged", skill = 250, wt = nil, agree = -1, spell = 446195, out = nil, pat = nil, kind = "unknown", vend = nil, reag = "221021:10,220688:1,14256:6,7080:1,14048:3" },
    { en = "Argent Boots", skill = 255, wt = 255, agree = 1, spell = 23664, out = 19056, pat = 19216, kind = "vendor", vend = { 10856, 10857, 11536 }, reag = "14048:6,12810:4,13926:2,12809:2,14227:2" },
    { en = "Big Bag of Enchantment", skill = 255, wt = 255, agree = 1, spell = 27660, out = 22249, pat = 22309, kind = "drop", vend = nil, reag = "14048:6,14344:4,12810:4,14227:4" },
    { en = "Earthenweave Cuffs", skill = 255, wt = 255, agree = 1, spell = 1257491, out = 254131, pat = 254132, kind = "unknown", vend = nil, reag = "14048:5,7076:1,14341:1" },
    { en = "Ghostweave Boots", skill = 255, wt = 255, agree = 1, spell = 1257490, out = 254129, pat = 254130, kind = "unknown", vend = nil, reag = "14048:4,9210:2,14227:1,8170:2,14341:1" },
    { en = "Mooncloth Bag", skill = 255, wt = 255, agree = 1, spell = 18445, out = 14155, pat = 14499, kind = "world", vend = nil, reag = "14048:4,14342:1,14341:1,249431:10,249430:2,249409:4" },
    { en = "Mooncloth Reagent Bag", skill = 255, wt = 255, agree = 1, spell = 1257492, out = 254133, pat = 254134, kind = "vendor", vend = { 256629 }, reag = "14048:4,14342:1,14341:1,249431:10,249430:1,249409:1" },
    { en = "Satchel of Cenarius", skill = 255, wt = 255, agree = 1, spell = 27725, out = 22252, pat = 22312, kind = "vendor", vend = { 15179 }, reag = "14048:6,14342:2,13468:1,14227:4" },
    { en = "Wisdom of the Timbermaw", skill = 255, wt = 255, agree = 1, spell = 23662, out = 19047, pat = 19215, kind = "vendor", vend = { 11557 }, reag = "14048:8,7076:3,12803:3,14227:2" },
    { en = "Wizardweave Robe", skill = 255, wt = 255, agree = 1, spell = 18446, out = 14128, pat = 14500, kind = "drop", vend = nil, reag = "14048:8,11176:2,14341:1" },
    { en = "Earthenweave Crown", skill = 260, wt = 260, agree = 1, spell = 1257494, out = 254137, pat = 254138, kind = "drop", vend = nil, reag = "14048:6,7076:3,14341:1" },
    { en = "Felcloth Robe", skill = 260, wt = 260, agree = 1, spell = 18451, out = 14106, pat = 14506, kind = "world", vend = nil, reag = "14048:8,14256:8,12662:4,14341:2" },
    { en = "Ghostweave Hood", skill = 260, wt = 260, agree = 1, spell = 1257493, out = 254135, pat = 254136, kind = "unknown", vend = nil, reag = "14048:6,9210:3,14227:2,14341:1" },
    { en = "Runecloth Shoulders", skill = 260, wt = 260, agree = 1, spell = 18449, out = 13867, pat = 14504, kind = "world", vend = nil, reag = "14048:7,14227:2,8170:4,14341:1" },
    { en = "Scarlet Augur's Mitts", skill = 260, wt = 260, agree = 1, spell = 1224611, out = nil, pat = 238302, kind = "world", vend = nil, reag = "12811:1,14048:10" },
    { en = "Scarlet Augur's Soles", skill = 260, wt = 260, agree = 1, spell = 1224614, out = nil, pat = 238305, kind = "world", vend = nil, reag = "12811:1,14048:10" },
    { en = "Wizardweave Turban", skill = 260, wt = 260, agree = 1, spell = 18450, out = 14130, pat = 14505, kind = "drop", vend = nil, reag = "14048:6,11176:4,7910:1,14341:1" },
    { en = "Felcloth Shoulders", skill = 265, wt = 265, agree = 1, spell = 18453, out = 14112, pat = 14508, kind = "world", vend = nil, reag = "14048:7,14256:6,12662:4,8170:4,14341:2" },
    { en = "Mooncloth Vest", skill = 270, wt = 270, agree = 1, spell = 18447, out = 14138, pat = 14501, kind = "world", vend = nil, reag = "14048:6,14342:4,14341:1" },
    { en = "Scarlet Augur's Leggings", skill = 270, wt = 270, agree = 1, spell = 1224613, out = nil, pat = 238304, kind = "world", vend = nil, reag = "12938:1,12811:1,14048:12" },
    { en = "Mooncloth Robe", skill = 275, wt = 275, agree = 1, spell = 22902, out = 18486, pat = 18487, kind = "vendor", vend = { 14371 }, reag = "14048:6,14342:4,13926:2,14341:2" },
    { en = "Mooncloth Shoulders", skill = 275, wt = 275, agree = 1, spell = 18448, out = 14139, pat = 14507, kind = "world", vend = nil, reag = "14048:5,14342:5,14341:1" },
    { en = "Cloak of Warding", skill = 280, wt = 280, agree = 1, spell = 22870, out = 18413, pat = 18418, kind = "object", vend = nil, reag = "14048:12,12809:4,12360:1,14341:2" },
    { en = "Felcloth Gloves", skill = 280, wt = 280, agree = 1, spell = 22867, out = 18407, pat = 18415, kind = "object", vend = nil, reag = "14048:12,14256:20,12662:6,12808:8,14341:2" },
    { en = "Inferno Gloves", skill = 280, wt = 280, agree = 1, spell = 22868, out = 18408, pat = 18416, kind = "object", vend = nil, reag = "14048:12,7078:10,7910:2,14341:2" },
    { en = "Mooncloth Circlet", skill = 280, wt = 280, agree = 1, spell = 18452, out = 14140, pat = 14509, kind = "world", vend = nil, reag = "14048:4,14342:6,12800:1,12810:2,14341:2" },
    { en = "Mooncloth Gloves", skill = 280, wt = 280, agree = 1, spell = 22869, out = 18409, pat = 18417, kind = "object", vend = nil, reag = "14048:12,14342:6,13926:2,14341:2" },
    { en = "Scarlet Augur's Hood", skill = 280, wt = 280, agree = 1, spell = 1224607, out = nil, pat = 238298, kind = "drop", vend = nil, reag = "12938:1,12811:2,14048:12" },
    { en = "Scarlet Augur's Mantle", skill = 280, wt = 280, agree = 1, spell = 1224608, out = nil, pat = 238299, kind = "drop", vend = nil, reag = "12811:1,14048:10" },
    { en = "Scarlet Augur's Vestments", skill = 280, wt = 280, agree = 1, spell = 1224609, out = nil, pat = 238300, kind = "unknown", vend = nil, reag = "12938:1,12811:1,14048:12" },
    { en = "Felcloth Bag", skill = 285, wt = 285, agree = 1, spell = 26086, out = 21341, pat = nil, kind = "unknown", vend = nil, reag = "14256:12,12810:6,20520:2,14227:4" },
    { en = "Gordok Ogre Suit", skill = 285, wt = 285, agree = 1, spell = 22813, out = 18258, pat = nil, kind = "unknown", vend = nil, reag = "14048:2,8170:4,18240:1,14341:1" },
    { en = "Mooncloth Boots", skill = 285, wt = 290, agree = 0, spell = 19435, out = 15802, pat = nil, kind = "quest", vend = nil, reag = "14048:6,14342:4,7971:2,14341:1" },
    { en = "Runed Stygian Belt", skill = 285, wt = 285, agree = 1, spell = 24902, out = 20539, pat = 20548, kind = "object", vend = nil, reag = "14048:2,20520:6,14256:2,12810:2,14227:2" },
    { en = "Runed Stygian Boots", skill = 285, wt = 285, agree = 1, spell = 24903, out = 20537, pat = 20547, kind = "object", vend = nil, reag = "14048:4,20520:6,14256:4,12810:2,14227:2" },
    { en = "Runed Stygian Leggings", skill = 285, wt = 285, agree = 1, spell = 24901, out = 20538, pat = 20546, kind = "object", vend = nil, reag = "14048:6,20520:8,14256:6,14227:2" },
    { en = "Swarmtender's Gloves", skill = 285, wt = 285, agree = 1, spell = 1297123, out = 275607, pat = 275583, kind = "vendor", vend = { 15179 }, reag = "14048:4,14343:1,7080:3,14341:6" },
    { en = "Synthetic Gordok Ogre Suit", skill = 285, wt = nil, agree = -1, spell = 461692, out = nil, pat = nil, kind = "unknown", vend = nil, reag = "8170:4,14048:2,18240:1,14341:1" },
    { en = "Venomspew Gloves", skill = 285, wt = 285, agree = 1, spell = 1297120, out = 275604, pat = 275580, kind = "vendor", vend = { 15179 }, reag = "14048:4,14343:1,7082:3,14341:6" },
    { en = "Argent Shoulders", skill = 290, wt = 300, agree = 0, spell = 23665, out = 19059, pat = 19217, kind = "vendor", vend = { 10856, 10857, 11536 }, reag = "14342:5,12809:2,14227:2" },
    { en = "Crimson Dawnwoven Bag", skill = 290, wt = 290, agree = 1, spell = 1227724, out = 239148, pat = 239150, kind = "unknown", vend = nil, reag = "12938:1,14048:24,2604:4,12808:2,12811:2" },
    { en = "Incandescent Mooncloth Leggings", skill = 290, wt = nil, agree = -1, spell = 461752, out = nil, pat = 228318, kind = "world", vend = nil, reag = "14048:6,14342:4,14341:1" },
    { en = "Mantle of the Timbermaw", skill = 290, wt = 290, agree = 1, spell = 23663, out = 19050, pat = 19218, kind = "vendor", vend = { 11557 }, reag = "14342:5,7076:5,12803:5,14227:2" },
    { en = "Swarmtender's Cord", skill = 290, wt = 290, agree = 1, spell = 1297124, out = 275608, pat = 275584, kind = "vendor", vend = { 15179 }, reag = "14048:6,14343:1,7080:3,14341:6" },
    { en = "Venomspew Cord", skill = 290, wt = 290, agree = 1, spell = 1297121, out = 275605, pat = 275581, kind = "vendor", vend = { 15179 }, reag = "14048:6,14343:1,7082:3,14341:6" },
    { en = "Belt of the Archmage", skill = 295, wt = 295, agree = 1, spell = 22866, out = 18405, pat = 18414, kind = "object", vend = nil, reag = "14048:16,9210:8,14342:8,7080:10,7078:10,14344:4,14341:6,249431:10" },
    { en = "Gloves of Spell Mastery", skill = 295, wt = 295, agree = 1, spell = 18454, out = 14146, pat = 14511, kind = "world", vend = nil, reag = "14048:10,14342:8,9210:8,13926:4,12364:4,12810:6,14341:2,249431:10" },
    { en = "Robe of the Archmage", skill = 295, wt = 295, agree = 1, spell = 18457, out = 14152, pat = 14513, kind = "drop", vend = nil, reag = "14048:12,7078:8,7082:8,7076:8,7080:8,14341:2,249431:10" },
    { en = "Robe of the Void", skill = 295, wt = 295, agree = 1, spell = 18458, out = 14153, pat = 14514, kind = "drop", vend = nil, reag = "14048:12,12662:20,14256:40,7078:8,12808:8,14341:2,249431:10" },
    { en = "Swarmtender's Footpads", skill = 295, wt = 295, agree = 1, spell = 1297125, out = 275609, pat = 275585, kind = "vendor", vend = { 15179 }, reag = "14048:5,14343:1,7080:3,14341:6" },
    { en = "Truefaith Vestments", skill = 295, wt = 295, agree = 1, spell = 18456, out = 14154, pat = 14512, kind = "drop", vend = nil, reag = "14048:12,14342:8,12811:2,13926:2,9210:8,14341:2,249431:10" },
    { en = "Venomspew Footpads", skill = 295, wt = 295, agree = 1, spell = 1297122, out = 275606, pat = 275582, kind = "vendor", vend = { 15179 }, reag = "14048:5,14343:1,7082:3,14341:6" },
    { en = "Bloodvine Boots", skill = 300, wt = 300, agree = 1, spell = 24093, out = 19684, pat = 19766, kind = "vendor", vend = { 14921 }, reag = "14342:3,19726:3,12810:4,14048:4,14227:4" },
    { en = "Bloodvine Leggings", skill = 300, wt = 300, agree = 1, spell = 24092, out = 19683, pat = 19765, kind = "vendor", vend = { 14921 }, reag = "14342:4,19726:4,12804:4,14048:4,14227:2" },
    { en = "Bloodvine Vest", skill = 300, wt = 300, agree = 1, spell = 24091, out = 19682, pat = 19764, kind = "vendor", vend = { 14921 }, reag = "14342:3,19726:5,12804:4,14048:4,14227:2" },
    { en = "Boots of Conviction", skill = 300, wt = nil, agree = -1, spell = 1292964, out = 273927, pat = 273995, kind = "vendor", vend = { 264797 }, reag = "274030:3,14342:2,14048:16,14341:8" },
    { en = "Bottomless Bag", skill = 300, wt = 300, agree = 1, spell = 18455, out = 14156, pat = 14510, kind = "world", vend = nil, reag = "14048:8,14342:12,14344:2,249429:5,249428:5,249431:8,14341:2" },
    { en = "Bottomless Reagent Bag", skill = 300, wt = 300, agree = 1, spell = 1257495, out = 254139, pat = 254140, kind = "unknown", vend = nil, reag = "14048:8,14342:12,14344:2,249427:5,14341:2,249428:5,249429:5" },
    { en = "Cloak of Earth and Sky", skill = 300, wt = 300, agree = 1, spell = 1306544, out = 279270, pat = 279319, kind = "unknown", vend = nil, reag = "274030:1,14342:1,14048:5" },
    { en = "Core Felcloth Bag", skill = 300, wt = 300, agree = 1, spell = 26087, out = 21342, pat = 21371, kind = "drop", vend = nil, reag = "14256:20,17012:16,19726:8,7078:4,14227:4" },
    { en = "Demonheart Boots", skill = 300, wt = nil, agree = -1, spell = 1292980, out = 273943, pat = 274011, kind = "vendor", vend = { 264797 }, reag = "274030:3,14342:2,14048:16,14341:8" },
    { en = "Demonheart Gloves", skill = 300, wt = nil, agree = -1, spell = 1292978, out = 273941, pat = 274009, kind = "vendor", vend = { 264797 }, reag = "274030:3,14342:2,14048:16,14341:8" },
    { en = "Demonheart Leggings", skill = 300, wt = nil, agree = -1, spell = 1292977, out = 273940, pat = 274008, kind = "vendor", vend = { 264797 }, reag = "274030:5,14342:3,14048:22,14341:8" },
    { en = "Demonheart Spaulders", skill = 300, wt = nil, agree = -1, spell = 1292979, out = 273942, pat = 274010, kind = "vendor", vend = { 264797 }, reag = "274030:3,14342:2,14048:16,14341:8" },
    { en = "Embroidered Belt of the Archmage", skill = 300, wt = nil, agree = -1, spell = 462282, out = nil, pat = 228477, kind = "object", vend = nil, reag = "14048:16,9210:10,14342:10,7080:12,7078:12,14344:6,14341:6" },
    { en = "Fel Cape", skill = 300, wt = 300, agree = 1, spell = 1306543, out = 279269, pat = 279318, kind = "unknown", vend = nil, reag = "274030:1,14342:1,14048:5" },
    { en = "Felblood Soul Bag", skill = 300, wt = 300, agree = 1, spell = 1306545, out = 279271, pat = 279320, kind = "unknown", vend = nil, reag = "14256:8,14048:6" },
    { en = "Flarecore Gloves", skill = 300, wt = 300, agree = 1, spell = 20849, out = 16979, pat = 17018, kind = "vendor", vend = { 12944 }, reag = "14048:8,17010:6,7078:4,12810:2,14341:2" },
    { en = "Flarecore Leggings", skill = 300, wt = 300, agree = 1, spell = 23667, out = 19165, pat = 19220, kind = "vendor", vend = { 12944 }, reag = "14342:8,17010:5,17011:3,7078:10,14227:4" },
    { en = "Flarecore Mantle", skill = 300, wt = 300, agree = 1, spell = 20848, out = 16980, pat = 17017, kind = "vendor", vend = { 12944 }, reag = "14048:12,17010:4,17011:4,12810:6,14341:2" },
    { en = "Flarecore Robe", skill = 300, wt = 300, agree = 1, spell = 23666, out = 19156, pat = 19219, kind = "vendor", vend = { 12944 }, reag = "14342:10,17010:2,17011:3,7078:6,14227:4" },
    { en = "Flarecore Wraps", skill = 300, wt = 300, agree = 1, spell = 22759, out = 18263, pat = 18265, kind = "drop", vend = nil, reag = "14342:6,17010:8,7078:2,12810:6,14341:4" },
    { en = "Gaea's Embrace", skill = 300, wt = 300, agree = 1, spell = 28210, out = 22660, pat = 22683, kind = "vendor", vend = { 15179 }, reag = "19726:1,14342:2,12803:4,14227:4" },
    { en = "Gloves of Conviction", skill = 300, wt = nil, agree = -1, spell = 1292958, out = 273921, pat = 273989, kind = "vendor", vend = { 264797 }, reag = "274030:3,14342:2,14048:16,14341:8" },
    { en = "Handguards of Conviction", skill = 300, wt = nil, agree = -1, spell = 1292962, out = 273925, pat = 273993, kind = "vendor", vend = { 264797 }, reag = "274030:3,14342:2,14048:16,14341:8" },
    { en = "Incandescent Mooncloth Circlet", skill = 300, wt = nil, agree = -1, spell = 461750, out = nil, pat = 228317, kind = "world", vend = nil, reag = "14048:4,14342:6,12800:1,12810:2,14341:2" },
    { en = "Incandescent Mooncloth Robe", skill = 300, wt = nil, agree = -1, spell = 461708, out = nil, pat = 228303, kind = "vendor", vend = { 14371 }, reag = "14048:6,14342:4,13926:2,14341:2" },
    { en = "Incandescent Mooncloth Vest", skill = 300, wt = nil, agree = -1, spell = 461747, out = nil, pat = 228316, kind = "world", vend = nil, reag = "14048:6,14342:4,14341:1" },
    { en = "Leather-Reinforced Runecloth Bag", skill = 300, wt = nil, agree = -1, spell = 461727, out = 227844, pat = 228121, kind = "vendor", vend = { 227853 }, reag = "14048:5,8170:2,14341:1,15407:1" },
    { en = "Leggings of Conviction", skill = 300, wt = nil, agree = -1, spell = 1292961, out = 273924, pat = 273992, kind = "vendor", vend = { 264797 }, reag = "274030:5,14342:3,14048:22,14341:8" },
    { en = "Loom", skill = 300, wt = 300, agree = 1, spell = 1263080, out = 279959, pat = nil, kind = "unknown", vend = nil, reag = "273131:1,14048:4,4470:4" },
    { en = "Mana-infused Cord", skill = 300, wt = 300, agree = 1, spell = 1306541, out = 279267, pat = 279316, kind = "unknown", vend = nil, reag = "274030:2,14342:2,14048:7" },
    { en = "Manaflare Boots", skill = 300, wt = nil, agree = -1, spell = 1292944, out = 273907, pat = 273975, kind = "vendor", vend = { 264797 }, reag = "274030:3,14342:2,14048:16,14341:8" },
    { en = "Manaflare Gloves", skill = 300, wt = nil, agree = -1, spell = 1292942, out = 273905, pat = 273973, kind = "vendor", vend = { 264797 }, reag = "274030:3,14342:2,14048:16,14341:8" },
    { en = "Manaflare Mantle", skill = 300, wt = nil, agree = -1, spell = 1292943, out = 273906, pat = 273974, kind = "vendor", vend = { 264797 }, reag = "274030:3,14342:2,14048:16,14341:8" },
    { en = "Manaflare Pants", skill = 300, wt = nil, agree = -1, spell = 1292941, out = 273904, pat = 273972, kind = "vendor", vend = { 264797 }, reag = "274030:5,14342:3,14048:22,14341:8" },
    { en = "Mantle of Conviction", skill = 300, wt = nil, agree = -1, spell = 1292959, out = 273922, pat = 273990, kind = "vendor", vend = { 264797 }, reag = "274030:3,14342:2,14048:16,14341:8" },
    { en = "Pants of Conviction", skill = 300, wt = nil, agree = -1, spell = 1292957, out = 273920, pat = 273988, kind = "vendor", vend = { 264797 }, reag = "274030:5,14342:3,14048:22,14341:8" },
    { en = "Pauldrons of Conviction", skill = 300, wt = nil, agree = -1, spell = 1292963, out = 273926, pat = 273994, kind = "vendor", vend = { 264797 }, reag = "274030:3,14342:2,14048:16,14341:8" },
    { en = "Rime-encrusted Boots", skill = 300, wt = 300, agree = 1, spell = 1306542, out = 279268, pat = 279317, kind = "unknown", vend = nil, reag = "274030:2,14342:2,14048:7" },
    { en = "Robes of Fiery Devastation", skill = 300, wt = 300, agree = 1, spell = 1306540, out = 279266, pat = 279315, kind = "unknown", vend = nil, reag = "274030:3,14342:3,14048:9" },
    { en = "Sylvan Crown", skill = 300, wt = 300, agree = 1, spell = 28481, out = 22757, pat = 22773, kind = "vendor", vend = { 15179 }, reag = "14048:4,14342:2,12803:2,14227:2" },
    { en = "Sylvan Shoulders", skill = 300, wt = 300, agree = 1, spell = 28482, out = 22758, pat = 22772, kind = "vendor", vend = { 15179 }, reag = "14048:2,12803:4,14227:2" },
    { en = "Sylvan Vest", skill = 300, wt = 300, agree = 1, spell = 28480, out = 22756, pat = 22774, kind = "vendor", vend = { 15179 }, reag = "14048:4,19726:2,12803:2,14227:2" },
    { en = "Treads of Conviction", skill = 300, wt = nil, agree = -1, spell = 1292960, out = 273923, pat = 273991, kind = "vendor", vend = { 264797 }, reag = "274030:3,14342:2,14048:16,14341:8" },
}

H.FUTURE_RECIPES_333 = {  -- Enchanting
    { en = "Enchant Chest - Superior Intellect", skill = 230, wt = 230, agree = 1, spell = 13917, out = nil, pat = nil, kind = "trainer", vend = nil, reag = "11175:1" },
    { en = "Enchant Shield - Greater Spirit", skill = 230, wt = 230, agree = 1, spell = 13905, out = nil, pat = nil, kind = "trainer", vend = nil, reag = "11174:2,11176:1" },
    { en = "Enchant Weapon - Demonslaying", skill = 230, wt = 230, agree = 1, spell = 13915, out = nil, pat = 11208, kind = "world", vend = nil, reag = "11177:1,11176:1,9224:1" },
    { en = "Enchant Boots - Agility", skill = 235, wt = 235, agree = 1, spell = 13935, out = nil, pat = nil, kind = "trainer", vend = nil, reag = "11175:1" },
    { en = "Enchant Bracer - Deflection", skill = 235, wt = 235, agree = 1, spell = 13931, out = nil, pat = 11223, kind = "vendor", vend = { 989, 4229 }, reag = "11174:2,11176:1" },
    { en = "Enchant Shield - Frost Resistance", skill = 235, wt = 235, agree = 1, spell = 13933, out = nil, pat = 11224, kind = "world", vend = nil, reag = "11178:1,3829:1" },
    { en = "Enchant 2H Weapon - Greater Impact", skill = 240, wt = 240, agree = 1, spell = 13937, out = nil, pat = nil, kind = "trainer", vend = nil, reag = "11178:1,11176:1" },
    { en = "Enchant Bracer - Greater Agility", skill = 240, wt = 240, agree = 1, spell = 1248500, out = nil, pat = 249514, kind = "drop", vend = nil, reag = "11176:3,11174:1" },
    { en = "Enchant Bracer - Greater Strength", skill = 240, wt = 240, agree = 1, spell = 13939, out = nil, pat = nil, kind = "trainer", vend = nil, reag = "11176:1,11174:2" },
    { en = "Enchant Bracer - Greater Stamina", skill = 245, wt = 245, agree = 1, spell = 13945, out = nil, pat = 11225, kind = "world", vend = nil, reag = "11176:3" },
    { en = "Enchant Chest - Stats", skill = 245, wt = 245, agree = 1, spell = 13941, out = nil, pat = nil, kind = "trainer", vend = nil, reag = "11178:1,11176:1,11175:1" },
    { en = "Enchant Weapon - Greater Striking", skill = 245, wt = 245, agree = 1, spell = 13943, out = nil, pat = nil, kind = "trainer", vend = nil, reag = "11178:1,11175:1" },
    { en = "Lesser Eternal Wand", skill = 245, wt = 245, agree = 1, spell = 1248505, out = 249232, pat = 249515, kind = "drop", vend = nil, reag = "16202:1,11176:1,11291:1" },
    { en = "Enchant Gloves - Advanced Skinning", skill = 250, wt = 250, agree = 1, spell = 1248528, out = nil, pat = 249516, kind = "drop", vend = nil, reag = "11176:2,15407:1" },
    { en = "Enchant Gloves - Minor Haste", skill = 250, wt = 250, agree = 1, spell = 13948, out = nil, pat = nil, kind = "trainer", vend = nil, reag = "11178:1,8153:1" },
    { en = "Enchant Gloves - Riding Skill", skill = 250, wt = 250, agree = 1, spell = 13947, out = nil, pat = 11226, kind = "world", vend = nil, reag = "11178:1,11176:2" },
    { en = "Enchanted Leather", skill = 250, wt = 250, agree = 1, spell = 17181, out = 12810, pat = nil, kind = "trainer", vend = nil, reag = "8170:1,16202:1" },
    { en = "Enchanted Thorium", skill = 250, wt = 250, agree = 1, spell = 17180, out = 12655, pat = nil, kind = "trainer", vend = nil, reag = "12359:1,11176:3" },
    { en = "Lesser Mana Oil", skill = 250, wt = 250, agree = 1, spell = 25127, out = 20747, pat = 20754, kind = "vendor", vend = { 12944, 15419 }, reag = "11176:1,8831:1,8925:1" },
    { en = "Sigil of Living Dreams", skill = 250, wt = nil, agree = -1, spell = 446243, out = nil, pat = nil, kind = "unknown", vend = nil, reag = "11176:5" },
    { en = "Enchant Bracer - Greater Intellect", skill = 255, wt = 255, agree = 1, spell = 20008, out = nil, pat = 16214, kind = "drop", vend = nil, reag = "16202:2" },
    { en = "Enchant Boots - Greater Stamina", skill = 260, wt = 260, agree = 1, spell = 20020, out = nil, pat = 16215, kind = "world", vend = nil, reag = "11176:6" },
    { en = "Dormant Heart of the Mountain", skill = 265, wt = 265, agree = 1, spell = 1249114, out = 249473, pat = 249521, kind = "drop", vend = nil, reag = "11382:1,7080:1,14343:3" },
    { en = "Enchant Cloak - Greater Resistance", skill = 265, wt = 265, agree = 1, spell = 20014, out = nil, pat = 16216, kind = "drop", vend = nil, reag = "16202:1,7077:1,7075:1,7079:1,7081:1,7972:1" },
    { en = "Enchant Shield - Greater Stamina", skill = 265, wt = 265, agree = 1, spell = 20017, out = nil, pat = 16217, kind = "vendor", vend = { 4229, 4561 }, reag = "11176:6" },
    { en = "Enchant Weapon - Fiery Weapon", skill = 265, wt = 265, agree = 1, spell = 13898, out = nil, pat = 11207, kind = "drop", vend = nil, reag = "11177:2,7078:1" },
    { en = "Frozen Heart of the Mountain", skill = 265, wt = 265, agree = 1, spell = 1249107, out = 249469, pat = 249519, kind = "unknown", vend = nil, reag = "11382:1,12808:1,14343:3" },
    { en = "Molten Heart of the Mountain", skill = 265, wt = 265, agree = 1, spell = 1249112, out = 249470, pat = 249520, kind = "drop", vend = nil, reag = "11382:1,7076:1,14343:3" },
    { en = "Smoking Heart of the Mountain", skill = 265, wt = 265, agree = 1, spell = 15596, out = 11811, pat = 11813, kind = "drop", vend = nil, reag = "11382:1,7078:1,14343:3" },
    { en = "Enchant Bracer - Superior Spirit", skill = 270, wt = 270, agree = 1, spell = 20009, out = nil, pat = 16218, kind = "world", vend = nil, reag = "16202:2,11176:7" },
    { en = "Enchant Gloves - Greater Agility", skill = 270, wt = 270, agree = 1, spell = 20012, out = nil, pat = 16219, kind = "drop", vend = nil, reag = "16202:2,16204:2" },
    { en = "Brilliant Wand", skill = 275, wt = 275, agree = 1, spell = 1248650, out = 249385, pat = 249537, kind = "vendor", vend = { 248199, 256732 }, reag = "16203:1,16204:3,14344:2,11291:1" },
    { en = "Conductive Shield Coating", skill = 275, wt = nil, agree = -1, spell = 463869, out = 228980, pat = 228981, kind = "vendor", vend = { 12944 }, reag = "16204:2,4625:1,8925:1" },
    { en = "Enchant Boots - Spirit", skill = 275, wt = 275, agree = 1, spell = 20024, out = nil, pat = 16220, kind = "world", vend = nil, reag = "16203:2,16202:1" },
    { en = "Enchant Chest - Major Stamina", skill = 275, wt = 275, agree = 1, spell = 20026, out = nil, pat = 16221, kind = "vendor", vend = { 11189 }, reag = "16204:6,14343:1" },
    { en = "Greater Eternal Wand", skill = 275, wt = 275, agree = 1, spell = 1248515, out = 249237, pat = 249522, kind = "unknown", vend = nil, reag = "16203:2,16204:1,11291:1" },
    { en = "Wizard Oil", skill = 275, wt = 275, agree = 1, spell = 25128, out = 20750, pat = 20755, kind = "vendor", vend = { 12944, 15419 }, reag = "16204:3,4625:2,8925:1" },
    { en = "Enchant 2H Weapon - Grand Arcanist", skill = 280, wt = nil, agree = -1, spell = 1231139, out = nil, pat = 241195, kind = "unknown", vend = nil, reag = "14344:10,12811:4,20725:4,12938:1" },
    { en = "Enchant 2H Weapon - Grand Inquisitor", skill = 280, wt = nil, agree = -1, spell = 1232172, out = nil, pat = 242361, kind = "unknown", vend = nil, reag = "14344:10,12811:6,20725:4,12938:1" },
    { en = "Enchant Boots - Speed", skill = 280, wt = nil, agree = -1, spell = 1328948, out = nil, pat = 289560, kind = "vendor", vend = { 248199, 256732 }, reag = "11178:2,11176:8,11175:2,12361:1" },
    { en = "Enchant Shield - Superior Spirit", skill = 280, wt = 280, agree = 1, spell = 20016, out = nil, pat = 16222, kind = "drop", vend = nil, reag = "16203:2,16204:4" },
    { en = "Enchant Weapon - Grand Crusader", skill = 280, wt = nil, agree = -1, spell = 1231128, out = nil, pat = 241191, kind = "unknown", vend = nil, reag = "14344:5,12811:2,20725:2,12938:1" },
    { en = "Enchant Weapon - Grand Sorcerer", skill = 280, wt = nil, agree = -1, spell = 1231164, out = nil, pat = 241201, kind = "unknown", vend = nil, reag = "14344:6,12811:3,20725:2,12938:1" },
    { en = "Enchant Cloak - Superior Defense", skill = 285, wt = 285, agree = 1, spell = 20015, out = nil, pat = 16224, kind = "vendor", vend = { 12022 }, reag = "16204:8" },
    { en = "Enchant Weapon - Icy Chill", skill = 285, wt = 285, agree = 1, spell = 20029, out = nil, pat = 16223, kind = "drop", vend = nil, reag = "14343:4,7080:1,7082:1,13467:1" },
    { en = "Enchant 2H Weapon - Agility", skill = 290, wt = 290, agree = 1, spell = 27837, out = nil, pat = 22392, kind = "vendor", vend = { 11557 }, reag = "14344:10,16203:6,16204:14,7082:4" },
    { en = "Enchant 2H Weapon - Strength", skill = 290, wt = 290, agree = 1, spell = 1248668, out = nil, pat = 249523, kind = "unknown", vend = nil, reag = "14344:8,16203:10,16204:8,12363:4" },
    { en = "Enchant Bracer - Mana Regeneration", skill = 290, wt = 290, agree = 1, spell = 23801, out = nil, pat = 19446, kind = "vendor", vend = { 10856, 10857, 11536 }, reag = "16204:16,16203:4,7080:2" },
    { en = "Enchant Chest - Major Intellect", skill = 290, wt = 290, agree = 1, spell = 20028, out = nil, pat = 16242, kind = "drop", vend = nil, reag = "16203:3,14343:1" },
    { en = "Enchant Weapon - Agility", skill = 290, wt = 290, agree = 1, spell = 23800, out = nil, pat = 19445, kind = "vendor", vend = { 11557 }, reag = "14344:6,16203:6,16204:4,7082:2" },
    { en = "Enchant Weapon - Strength", skill = 290, wt = 290, agree = 1, spell = 23799, out = nil, pat = 19444, kind = "vendor", vend = { 12944 }, reag = "14344:6,16203:6,16204:4,7076:2" },
    { en = "Runed Arcanite Rod", skill = 290, wt = 290, agree = 1, spell = 20051, out = 16207, pat = 16243, kind = "vendor", vend = { 12022 }, reag = "16206:1,13926:1,16204:10,16203:4,14343:4,14344:2" },
    { en = "Sigil of Flowing Waters", skill = 290, wt = nil, agree = -1, spell = 463866, out = 228978, pat = nil, kind = "unknown", vend = nil, reag = "16204:1" },
    { en = "Enchant 2H Weapon - Superior Impact", skill = 295, wt = 295, agree = 1, spell = 20030, out = nil, pat = 16247, kind = "drop", vend = nil, reag = "14344:4,16204:10" },
    { en = "Enchant Boots - Greater Agility", skill = 295, wt = 295, agree = 1, spell = 20023, out = nil, pat = 16245, kind = "world", vend = nil, reag = "16203:8" },
    { en = "Enchant Bracer - Superior Agility", skill = 295, wt = 295, agree = 1, spell = 1248599, out = nil, pat = 249524, kind = "drop", vend = nil, reag = "16204:3,16203:3,14344:1" },
    { en = "Enchant Bracer - Superior Strength", skill = 295, wt = 295, agree = 1, spell = 20010, out = nil, pat = 16246, kind = "drop", vend = nil, reag = "16204:6,16203:6" },
    { en = "Enchant Gloves - Greater Strength", skill = 295, wt = 295, agree = 1, spell = 20013, out = nil, pat = 16244, kind = "drop", vend = nil, reag = "16203:4,16204:4" },
    { en = "Enchant Gloves - Lotus Claw", skill = 295, wt = 295, agree = 1, spell = 1294054, out = nil, pat = 274424, kind = "vendor", vend = { 256629 }, reag = "248822:1,14343:2,16204:12,16202:4" },
    { en = "Enchant Weapon - Unholy Weapon", skill = 295, wt = 295, agree = 1, spell = 20033, out = nil, pat = 16248, kind = "world", vend = nil, reag = "14344:4,12808:4" },
    { en = "Arcane Forge", skill = 300, wt = 300, agree = 1, spell = 1263082, out = 279987, pat = nil, kind = "unknown", vend = nil, reag = "273128:1,14344:2,16203:4" },
    { en = "Brilliant Mana Oil", skill = 300, wt = 300, agree = 1, spell = 25130, out = 20748, pat = 20757, kind = "vendor", vend = { 14921 }, reag = "14344:2,8831:3,18256:1" },
    { en = "Brilliant Wizard Oil", skill = 300, wt = 300, agree = 1, spell = 25129, out = 20749, pat = 20756, kind = "vendor", vend = { 14921 }, reag = "14344:2,4625:3,18256:1" },
    { en = "Enchant 2H Weapon - Major Intellect", skill = 300, wt = 300, agree = 1, spell = 20036, out = nil, pat = 16249, kind = "drop", vend = nil, reag = "16203:12,14344:2" },
    { en = "Enchant 2H Weapon - Major Spirit", skill = 300, wt = 300, agree = 1, spell = 20035, out = nil, pat = 16255, kind = "drop", vend = nil, reag = "16203:12,14344:2" },
    { en = "Enchant 2H Weapon - Mighty Healing Power", skill = 300, wt = 300, agree = 1, spell = 1248636, out = nil, pat = 249526, kind = "vendor", vend = { 248199, 256732 }, reag = "248819:4,16203:6,249726:4,249274:4,20725:4,248820:4" },
    { en = "Enchant 2H Weapon - Mighty Spell Power", skill = 300, wt = 300, agree = 1, spell = 1248607, out = nil, pat = 249525, kind = "vendor", vend = { 248199, 256732 }, reag = "248819:4,16203:6,7076:4,12808:4,20725:4,248820:2" },
    { en = "Enchant 2H Weapon - Spellblasting", skill = 300, wt = 300, agree = 1, spell = 1219580, out = nil, pat = 274394, kind = "vendor", vend = { 248199, 256732 }, reag = "20725:3,16204:24,12938:1,8831:6" },
    { en = "Enchant Bracer - Greater Spellpower", skill = 300, wt = 300, agree = 1, spell = 1220624, out = nil, pat = 274401, kind = "vendor", vend = { 248199, 256732 }, reag = "16203:3,16204:9,12808:12,8831:2" },
    { en = "Enchant Bracer - Healing Power", skill = 300, wt = 300, agree = 1, spell = 23802, out = nil, pat = 19447, kind = "vendor", vend = { 10856, 10857, 11536 }, reag = "14344:2,16204:20,16203:4,12803:6" },
    { en = "Enchant Bracer - Superior Deflection", skill = 300, wt = 300, agree = 1, spell = 1248665, out = nil, pat = 249539, kind = "vendor", vend = { 248199, 256732 }, reag = "14344:3" },
    { en = "Enchant Bracer - Superior Intellect", skill = 300, wt = 300, agree = 1, spell = 1248661, out = nil, pat = 249538, kind = "vendor", vend = { 248199, 256732 }, reag = "16203:10" },
    { en = "Enchant Bracer - Superior Stamina", skill = 300, wt = 300, agree = 1, spell = 20011, out = nil, pat = 16251, kind = "world", vend = nil, reag = "16204:15" },
    { en = "Enchant Chest - Greater Stats", skill = 300, wt = 300, agree = 1, spell = 20025, out = nil, pat = 16253, kind = "world", vend = nil, reag = "14344:4,16204:15,16203:10" },
    { en = "Enchant Cloak - Agility", skill = 300, wt = 300, agree = 1, spell = 1219587, out = nil, pat = 274399, kind = "vendor", vend = { 248199, 256732 }, reag = "16203:3,16204:9,7078:1" },
    { en = "Enchant Cloak - Dodge", skill = 300, wt = 300, agree = 1, spell = 25086, out = nil, pat = 20736, kind = "drop", vend = nil, reag = "20725:3,14344:8,12809:8" },
    { en = "Enchant Cloak - Greater Fire Resistance", skill = 300, wt = 300, agree = 1, spell = 25081, out = nil, pat = 20732, kind = "vendor", vend = { 15419 }, reag = "20725:3,14344:8,7078:4" },
    { en = "Enchant Cloak - Greater Nature Resistance", skill = 300, wt = 300, agree = 1, spell = 25082, out = nil, pat = 20733, kind = "vendor", vend = { 15419 }, reag = "20725:2,14344:8,12803:4" },
    { en = "Enchant Cloak - Stealth", skill = 300, wt = 300, agree = 1, spell = 25083, out = nil, pat = 20734, kind = "drop", vend = nil, reag = "20725:3,14344:8,13468:2" },
    { en = "Enchant Cloak - Subtlety", skill = 300, wt = 300, agree = 1, spell = 25084, out = nil, pat = 20735, kind = "drop", vend = nil, reag = "20725:4,14344:6,11754:2" },
    { en = "Enchant Gloves - Arcane Power", skill = 300, wt = 300, agree = 1, spell = 1213626, out = nil, pat = 249534, kind = "vendor", vend = { 248199, 256732 }, reag = "20725:2,14344:5,12753:2" },
    { en = "Enchant Gloves - Fire Power", skill = 300, wt = 300, agree = 1, spell = 25078, out = nil, pat = 20729, kind = "drop", vend = nil, reag = "20725:2,14344:10,7078:4" },
    { en = "Enchant Gloves - Frost Power", skill = 300, wt = 300, agree = 1, spell = 25074, out = nil, pat = 20728, kind = "drop", vend = nil, reag = "20725:3,14344:10,7080:4" },
    { en = "Enchant Gloves - Healing Power", skill = 300, wt = 300, agree = 1, spell = 25079, out = nil, pat = 20730, kind = "drop", vend = nil, reag = "20725:3,14344:8,12811:1" },
    { en = "Enchant Gloves - Holy Power", skill = 300, wt = 300, agree = 1, spell = 1213622, out = nil, pat = 249536, kind = "vendor", vend = { 248199, 256732 }, reag = "20725:2,14344:5,13180:5,12735:2" },
    { en = "Enchant Gloves - Natural Power", skill = 300, wt = 300, agree = 1, spell = 1248645, out = nil, pat = 249535, kind = "vendor", vend = { 248199, 256732 }, reag = "20725:2,14344:5,248822:4" },
    { en = "Enchant Gloves - Shadow Power", skill = 300, wt = 300, agree = 1, spell = 25073, out = nil, pat = 20727, kind = "drop", vend = nil, reag = "20725:3,14344:10,12808:6" },
    { en = "Enchant Gloves - Superior Agility", skill = 300, wt = 300, agree = 1, spell = 25080, out = nil, pat = 20731, kind = "drop", vend = nil, reag = "20725:3,14344:8,7082:4" },
    { en = "Enchant Gloves - Superior Strength", skill = 300, wt = 300, agree = 1, spell = 1248640, out = nil, pat = 274398, kind = "vendor", vend = { 248199, 256732 }, reag = "20725:4,16203:8,7076:4" },
    { en = "Enchant Gloves - Threat", skill = 300, wt = 300, agree = 1, spell = 25072, out = nil, pat = 20726, kind = "drop", vend = nil, reag = "20725:4,14344:6,18512:8" },
    { en = "Enchant Off-Hand - Excellent Spirit", skill = 300, wt = 300, agree = 1, spell = 1219578, out = nil, pat = 274392, kind = "unknown", vend = nil, reag = "20725:2,16204:18,7080:2" },
    { en = "Enchant Off-Hand - Superior Intellect", skill = 300, wt = 300, agree = 1, spell = 1219577, out = nil, pat = 274391, kind = "unknown", vend = nil, reag = "20725:2,16204:18,7082:2" },
    { en = "Enchant Off-Hand - Wisdom", skill = 300, wt = 300, agree = 1, spell = 1219579, out = nil, pat = 274393, kind = "vendor", vend = { 248199, 256732 }, reag = "14344:6,16204:18,7082:1,7080:1" },
    { en = "Enchant Shield - Critical Strike", skill = 300, wt = 300, agree = 1, spell = 1220623, out = nil, pat = 274400, kind = "unknown", vend = nil, reag = "14344:5,16204:15,12938:1" },
    { en = "Enchant Shield - Excellent Stamina", skill = 300, wt = 300, agree = 1, spell = 1219581, out = nil, pat = 274395, kind = "unknown", vend = nil, reag = "14344:6,16204:18,7076:2" },
    { en = "Enchant Shield - Law of Nature", skill = 300, wt = nil, agree = -1, spell = 463871, out = nil, pat = 228982, kind = "vendor", vend = { 11557 }, reag = "14344:4,16203:12,7078:4,7080:4,7076:1,12811:1" },
    { en = "Enchant Weapon - Crusader", skill = 300, wt = 300, agree = 1, spell = 20034, out = nil, pat = 16252, kind = "drop", vend = nil, reag = "14344:4,12811:2" },
    { en = "Enchant Weapon - Healing Power", skill = 300, wt = 300, agree = 1, spell = 22750, out = nil, pat = 18260, kind = "drop", vend = nil, reag = "14344:4,16203:8,12803:6,7080:6,12811:1" },
    { en = "Enchant Weapon - Lifestealing", skill = 300, wt = 300, agree = 1, spell = 20032, out = nil, pat = 16254, kind = "world", vend = nil, reag = "14344:6,12808:6,12803:6" },
    { en = "Enchant Weapon - Mighty Intellect", skill = 300, wt = 300, agree = 1, spell = 23804, out = nil, pat = 19449, kind = "vendor", vend = { 12944 }, reag = "14344:15,16203:12,16204:20" },
    { en = "Enchant Weapon - Mighty Spirit", skill = 300, wt = 300, agree = 1, spell = 23803, out = nil, pat = 19448, kind = "vendor", vend = { 12944 }, reag = "14344:10,16203:8,16204:15" },
    { en = "Enchant Weapon - Spell Power", skill = 300, wt = 300, agree = 1, spell = 22749, out = nil, pat = 18259, kind = "drop", vend = nil, reag = "14344:4,16203:12,7078:4,7080:4,7082:4,13926:2" },
    { en = "Enchant Weapon - Superior Striking", skill = 300, wt = 300, agree = 1, spell = 20031, out = nil, pat = 16250, kind = "drop", vend = nil, reag = "14344:2,16203:10" },
    { en = "Enchanted Repellent", skill = 300, wt = nil, agree = -1, spell = 1213610, out = nil, pat = 234272, kind = "vendor", vend = { 15419 }, reag = "234011:3,234012:3,16204:2" },
    { en = "Idol of Swiftness", skill = 300, wt = 300, agree = 1, spell = 1306524, out = 279250, pat = 279299, kind = "unknown", vend = nil, reag = "274030:1,20725:1,16203:2,16204:12" },
    { en = "Idol of the Dream", skill = 300, wt = 300, agree = 1, spell = 1249128, out = 220606, pat = 249529, kind = "vendor", vend = { 248199, 256732 }, reag = "14344:2,16203:4,16204:6,249431:8,249430:4,249409:2,11291:4" },
    { en = "Idol of the Ursine Twins", skill = 300, wt = 300, agree = 1, spell = 1306525, out = 279251, pat = 279300, kind = "unknown", vend = nil, reag = "274030:1,20725:1,16203:2,16204:12" },
    { en = "Libram of Holy Alacrity", skill = 300, wt = 300, agree = 1, spell = 1249152, out = 228175, pat = 249530, kind = "vendor", vend = { 248199, 256732 }, reag = "14344:4,16203:3,16204:4,249431:8,249430:4,249409:2,10308:4" },
    { en = "Libram of Infusion", skill = 300, wt = 300, agree = 1, spell = 1306522, out = 279248, pat = 279297, kind = "unknown", vend = nil, reag = "274030:1,20725:1,16203:2,16204:12" },
    { en = "Magnificent Trollshine", skill = 300, wt = nil, agree = -1, spell = 471400, out = 232611, pat = 232610, kind = "vendor", vend = { 14921 }, reag = "8151:3,8152:3,14344:2,18256:1" },
    { en = "Scroll: Wrath of the Swarm", skill = 300, wt = nil, agree = -1, spell = 1213607, out = nil, pat = 234271, kind = "vendor", vend = { 15419 }, reag = "16203:1,14047:1" },
    { en = "Steadfast Libram", skill = 300, wt = 300, agree = 1, spell = 1306521, out = 279247, pat = 279296, kind = "unknown", vend = nil, reag = "274030:1,20725:1,16203:2,16204:12" },
    { en = "Torch of Light", skill = 300, wt = 300, agree = 1, spell = 1306520, out = 279246, pat = 279295, kind = "unknown", vend = nil, reag = "274030:2,20725:1,14344:6,16202:5" },
    { en = "Totem of Thunder", skill = 300, wt = 300, agree = 1, spell = 1249154, out = 228176, pat = 249532, kind = "vendor", vend = { 248199, 256732 }, reag = "14344:1,16203:8,16204:10,249431:8,249430:4,249409:2,11291:4" },
    { en = "Totem of Urgency", skill = 300, wt = 300, agree = 1, spell = 1306523, out = 279249, pat = 279298, kind = "unknown", vend = nil, reag = "274030:1,20725:1,16203:2,16204:12" },
}

-- MERCHANT'S FAVOR: ЯЩИКИ WAYLAID CRATE.
--
-- Единственная таблица в файле, выкачанная из сети: структура ящиков взята с
-- theforeverguides.com/professions/merchants-favor (прочитан 2026-11-17), сам
-- сайт пишет, что данные с бета-сборок и часть помечена как непроверенная.
-- itemID ящиков и всех материалов СВЕРЕНЫ с базами на диске по именам, поэтому
-- id - факт, а вот сколько Favor даёт ящик - слова сайта.
--
-- Зачем это магу 26 уровня с навыком 225: рецепты за Favor гейтятся НАВЫКОМ, а
-- не уровнем. Жемчужный (аркановый) набор портняжки - навык 60-125, по 30 Favor
-- за паттерн; посох и офф-хенд от чар - навык 140, по 45. Всё доступно уже
-- сейчас. Поэтому Favor - самая полезная трата времени до 35 уровня.
--
-- favor/silver = за сданный ящик; nil = источник не знает. lvl = с какого уровня
-- персонажа ящик открывается. bundles = ЛЮБОЙ ОДИН из наборов заполняет ящик,
-- не все сразу; материал должен лежать одним стаком.
H.MF_CRATES = {
    [248684] = { crate = 248684, rank = "Apprentice", kind = "Textiles", colour = "white", lvl = 10, favor = 5, silver = 250, bundles = { { 2589, 40 }, { 2318, 20 } } },
    [248702] = { crate = 248702, rank = "Apprentice", kind = "Fabrics", colour = "green", lvl = 10, favor = 10, silver = 500, bundles = { { 4231, 2 }, { 2996, 20 } } },
    [248685] = { crate = 248685, rank = "Apprentice", kind = "Curiosities", colour = "white", lvl = 10, favor = 5, silver = 250, bundles = { { 10940, 20 }, { 10939, 4 }, { 10978, 6 }, { 11084, 2 } } },
    [248682] = { crate = 248682, rank = "Apprentice", kind = "Herbs", colour = "white", lvl = 10, favor = 5, silver = 250, bundles = { { 2447, 20 }, { 765, 20 }, { 2449, 10 }, { 785, 10 }, { 2450, 10 } } },
    [248683] = { crate = 248683, rank = "Apprentice", kind = "Ore", colour = "white", lvl = 10, favor = 5, silver = 250, bundles = nil },
    [248703] = { crate = 248703, rank = "Apprentice", kind = "Ingots", colour = "green", lvl = 10, favor = 10, silver = 500, bundles = nil },
    [248704] = { crate = 248704, rank = "Apprentice", kind = "Parts", colour = "green", lvl = 10, favor = 10, silver = 500, bundles = nil },
    [248688] = { crate = 248688, rank = "Journeyman", kind = "Textiles", colour = "white", lvl = 10, favor = 10, silver = 500, bundles = { { 2592, 20 }, { 4306, 40 }, { 2319, 20 } } },
    [248705] = { crate = 248705, rank = "Journeyman", kind = "Fabrics", colour = "green", lvl = 10, favor = 20, silver = 1000, bundles = { { 2997, 6 }, { 4305, 10 }, { 4233, 2 } } },
    [248689] = { crate = 248689, rank = "Journeyman", kind = "Curiosities", colour = "white", lvl = 10, favor = 10, silver = 500, bundles = { { 11083, 20 }, { 11082, 4 }, { 11138, 6 }, { 11139, 2 } } },
    [248686] = { crate = 248686, rank = "Journeyman", kind = "Herbs", colour = "white", lvl = 10, favor = 10, silver = 500, bundles = { { 3820, 10 }, { 2453, 10 }, { 3355, 10 }, { 3369, 10 }, { 3356, 10 } } },
    [248687] = { crate = 248687, rank = "Journeyman", kind = "Ore", colour = "white", lvl = 10, favor = 10, silver = 500, bundles = nil },
    [248706] = { crate = 248706, rank = "Journeyman", kind = "Ingots", colour = "green", lvl = 10, favor = 20, silver = 1000, bundles = nil },
    [248707] = { crate = 248707, rank = "Journeyman", kind = "Parts", colour = "green", lvl = 10, favor = 20, silver = 1000, bundles = nil },
    [248693] = { crate = 248693, rank = "Expert", kind = "Textiles", colour = "white", lvl = 20, favor = nil, silver = 750, bundles = { { 4338, 40 }, { 4234, 20 } } },
    [248708] = { crate = 248708, rank = "Expert", kind = "Fabrics", colour = "green", lvl = 20, favor = nil, silver = 1500, bundles = { { 4339, 8 }, { 4236, 2 } } },
    [248694] = { crate = 248694, rank = "Expert", kind = "Curiosities", colour = "white", lvl = 20, favor = nil, silver = 750, bundles = { { 11137, 20 }, { 11135, 4 }, { 11177, 6 }, { 11178, 2 } } },
    [248692] = { crate = 248692, rank = "Expert", kind = "Ore", colour = "white", lvl = 20, favor = nil, silver = 750, bundles = nil },
    [248709] = { crate = 248709, rank = "Expert", kind = "Ingots", colour = "green", lvl = 20, favor = nil, silver = 1500, bundles = nil },
    [248710] = { crate = 248710, rank = "Expert", kind = "Parts", colour = "green", lvl = 20, favor = nil, silver = 1500, bundles = nil },
    [248698] = { crate = 248698, rank = "Artisan", kind = "Textiles", colour = "white", lvl = 35, favor = nil, silver = nil, bundles = { { 14047, 40 }, { 4304, 20 }, { 8170, 20 } } },
    [248711] = { crate = 248711, rank = "Artisan", kind = "Fabrics", colour = "green", lvl = 35, favor = nil, silver = nil, bundles = { { 14048, 8 }, { 8172, 2 } } },
    [248699] = { crate = 248699, rank = "Artisan", kind = "Curiosities", colour = "white", lvl = 35, favor = nil, silver = nil, bundles = { { 11176, 20 }, { 11175, 4 }, { 14343, 6 }, { 14344, 2 } } },
    [248697] = { crate = 248697, rank = "Artisan", kind = "Ore", colour = "white", lvl = 35, favor = nil, silver = nil, bundles = nil },
    [248712] = { crate = 248712, rank = "Artisan", kind = "Ingots", colour = "green", lvl = 35, favor = nil, silver = nil, bundles = nil },
    [248713] = { crate = 248713, rank = "Artisan", kind = "Parts", colour = "green", lvl = 35, favor = nil, silver = nil, bundles = nil },
}
-- Ящики Ore / Ingots / Parts в таблице есть (их id нашлись в Polestar_Codex),
-- но bundles у них nil: наборы руды, слитков и деталей к портняжке и чарам
-- отношения не имеют, и я их не переносил. id всё равно полезны - по ним можно
-- смотреть цену пустого ящика на аукционе. Ящиков Expert/Artisan Herbs и
-- Expert/Artisan Fabrics-вариантов с раздельными наборами Earthly/Flowering в
-- Codex под такими именами нет.

-- Репутация у лагеря. Ящики дают Favor, но НЕ репутацию - репутация только с
-- расписок Craftsman's Writ и разового задания Shipping Label. Пороги Honored
-- 9000 и Exalted 42000 сайт сам помечает как взятые из Classic.
H.MF_REP = {
    shippingLabel = { rep = 2000, favor = 50, xp = 660, once = "per character", conf = "WEB" },
    writJourneyman = { rep = 75,  perDay = 1, item = 262888, en = "Sealed Journeyman's Writ", conf = "WEB" },
    writExpert     = { rep = 125, perDay = 1, item = 262889, en = "Sealed Expert's Writ", conf = "WEB" },
    writArtisan    = { rep = 200, perDay = 1, item = 262890, en = "Sealed Artisan's Writ", conf = "WEB" },
    notarized      = { rep = 50, needs = "Friendly", via = "Forged Delivery Receipt (15 Favor)", conf = "WEB" },
    honored = 9000, exalted = 42000, thresholdsFrom = "Classic, сайтом не подтверждено для Forever",
}
-- itemID расписок сверены с Polestar_Codex по именам. Предметы писаря
-- (Forged Delivery Receipt, Forger's Quill) и Shipping Label в базах на диске
-- НЕ найдены - их id здесь нет, чтобы не выдумывать.

-- Что аддону стоит советовать тратить Favor на в первую очередь, по школе
-- заклинаний персонажа. Пороги навыка - из Mastercraft (поле s), то есть с
-- диска; цену в Favor источник называет 30 за паттерн и 45 за формулу.
-- ВАЖНО: источники расходятся, нужна ли репутация для этих покупок. Сайт
-- Wowhead говорит нет, wow-professions - Friendly на средних. Не проверено.
H.MF_FIRST_BUYS_ARCANE = {
    { en = "Pearly Boots", prof = 197, skill = 60, pat = 253898, out = 253897, vend = { 248202, 256735 }, favor = 30, reag = "2997:8,2321:2,249409:2,5498:1" },
    { en = "Pearly Gloves", prof = 197, skill = 75, pat = 253922, out = 253921, vend = { 248202, 256735 }, favor = 30, reag = "2997:6,2321:4,249409:3,5498:2" },
    { en = "Pearly Sash", prof = 197, skill = 85, pat = 253934, out = 253933, vend = { 248202, 256735 }, favor = 30, reag = "4305:8,2321:4,249409:3,5498:3" },
    { en = "Pearly Circlet", prof = 197, skill = 100, pat = 253958, out = 253957, vend = { 248202, 256735 }, favor = 30, reag = "4305:10,4291:2,249409:4,5498:4,2842:1,11082:2" },
    { en = "Pearly Gown", prof = 197, skill = 110, pat = 253970, out = 253969, vend = { 248202, 256735 }, favor = 30, reag = "4305:12,4291:2,249409:6,5498:6,2842:2,11082:2" },
    { en = "Pearly Leggings", prof = 197, skill = 125, pat = 253996, out = 253995, vend = { 248202, 256735 }, favor = 30, reag = "4305:14,2321:3,249409:8,5498:8,2842:2,11082:3" },
    { en = "Glimmering Staff", prof = 333, skill = 140, pat = 249482, out = 249392, vend = { 248199, 256732 }, favor = 45, reag = "11084:4,10978:2,11291:4,11082:1,10940:5,249391:3" },
    { en = "Orb of Mystic Insight", prof = 333, skill = 140, pat = 249484, out = 249394, vend = { 248199, 256732 }, favor = 45, reag = "10978:2,11082:2,10940:5" },
}
-- Жемчужный набор = школа аркана: это утверждение сайтов сообщества, из
-- клиентских данных оно не следует. Статы самих вещей есть в Polestar_ItemDB -
-- аддон должен брать их оттуда и показывать игроку цифры, а не название школы.

-- Открытые дыры, которые этот файл НЕ закрывает. Перечислены, чтобы аддон мог
-- честно сказать "не знаю", а не делать вид.
H.GAPS = {
    disenchantForever = "Вероятности распыления в Forever. В клиенте лежит только ItemDisenchantLoot (какие качества и уровни вообще распыляемы), сам ролл делает сервер. Таблица в ForeverSource.DISENCHANT - из Classic, помечена ESTIMATE. Открытой пачки измерений не нашёл: wago.tools мне не отдался, foreverdb.net требует одобренный ключ.",
    arcaneSalvager = "Бонус Arcane Salvager (item 279985, Enchanting 140). Процент нигде не опубликован; в хотфиксах Blizzard только словами. Единственная цифра в сети - анекдот про 10-20%, другой гайд её оспаривает. Считать неизвестным.",
    annoraPlace = "Где стоит Annora (npc 11073) - единственный тренер Artisan по чарам. В базах на диске места нет; сайты говорят Uldaman, Badlands, задний вход. Координат нет.",
    expertArtisanFavor = "Сколько Favor дают ящики Expert и Artisan. Источник сам помечает как непроверенное.",
    mfRepNeeded = "Нужна ли репутация для покупки рецептов за Favor. Источники противоречат друг другу.",
    notForever = "Реагенты из рецептов Mastercraft, которых нет ни в Polestar_Codex, ни в Mastercraft ItemData, и которые поэтому в H.PRICE_WATCH не попали (вероятно, контент не из Forever): 220688 (в 3 рецептах)",
    learnSourceUnknown = "У части рецептов 226-300 поле kind = \"unknown\": Mastercraft пишет \"not on Wowhead yet\". Это значит, что неизвестно, где учиться, а не что рецепта нет: 19 из 23 таких по портняжке и 14 из 20 по чарам подтверждены второй базой (WhatsTraining). Советовать такой рецепт можно, маршрут к нему - нет.",
}

-- ЧЬИ ЭТО РЕАГЕНТЫ: БУКВА В ЗАПИСИ -> ИМЯ ПРОФЕССИИ.
--
-- Каждая запись H.PRICE_WATCH уже несёт поле prof со значением "T", "E" или
-- "E+T". До этой таблицы его никто не читал, и весь список целиком попадал в
-- слепок цен ЛЮБОМУ персонажу: чернокнижник-алхимик каждый день снимал цену на
-- рунную ткань и лунную ткань, которые ему не нужны ни для чего. Справочник был
-- честный, а ограничением его делало место, которое поле профессии не смотрело.
--
-- Имена - те же, что в RecipeBook.NAME_BRIDGE, то есть локализованные имена
-- клиента и их английские пары. Сверка идёт через этот словарь, а не вторым
-- экземпляром, который может с ним разойтись.
H.WATCH_PROF_CODE = {
    T = "портняжное дело",
    E = "наложение чар",
}

-- И НОМЕР ЛИНИИ НАВЫКА РЯДОМ С ИМЕНЕМ, ПОТОМУ ЧТО ИМЯ ЗАВИСИТ ОТ ЯЗЫКА.
--
-- Сверка шла только по именам, а имена здесь русские: на клиенте ruRU
-- совпадало прямо, на enUS спасала английская пара из NAME_BRIDGE. На любом
-- третьем языке («Schneiderei», «Couture») не совпадало НИЧЕГО - и список
-- наблюдения обнулялся молча: суточные слепки цен просто перестали бы
-- записываться, а сказать об этом было нечем.
--
-- Номер линии от языка не зависит, и спрашивается он там же, где его
-- спрашивают все остальные ветки - у ForeverSource:ResolveSkillLine, который
-- умеет и локализованное имя (через Codex), и английское, и наш словарь. Имена
-- остаются: они нужны, когда номера нет вовсе.
H.WATCH_PROF_LINE = {
    T = 197,   -- Tailoring
    E = 333,   -- Enchanting
}

-- Список наблюдения за ценами.
--
-- `professionNames` - имена профессий персонажа. Передали - вернётся только то,
-- что этим профессиям нужно. Не передали - вернётся всё: это по-прежнему
-- «весь справочник», и такой вызов нужен самому справочнику и его проверкам,
-- а не советам игроку.
--
-- Записи с prof = "E+T" идут и портняжнику, и зачарователю: материал нужен
-- обоим, и выбрасывать его у одного из них было бы ошибкой в другую сторону.
--
-- ЧТО ПРИНИМАЕТСЯ НА ВХОД: имена профессий строками (как раньше) ИЛИ записи
-- профессий из снимка. Записи лучше: у них есть номер линии навыка, а он не
-- зависит от языка клиента (см. H.WATCH_PROF_LINE).
--
-- Второе возвращаемое значение - отчёт о сверке: { matched, byLine, byName,
-- unresolved, unknownCodes }. Он нужен, чтобы ПУСТОЙ список нельзя было
-- получить молча: вызывающий обязан сказать, что сверка не удалась.
function H:WatchList(professions)
    local want, lines, unresolved
    if type(professions) == "table" then
        want, lines, unresolved = {}, {}, {}
        local bridge = (ns.RecipeBook and ns.RecipeBook.NAME_BRIDGE) or {}
        local FS = ns.ForeverSource
        for _, prof in ipairs(professions) do
            local name = (type(prof) == "table") and prof.name or prof
            -- НОМЕР - ВПЕРЕДИ ИМЕНИ. Запись профессии разбирает тот же
            -- ForeverSource, что и все остальные ветки; строку он тоже
            -- принимает, обёрнутую в запись.
            local line
            if FS and FS.ResolveSkillLine then
                line = FS:ResolveSkillLine((type(prof) == "table") and prof
                    or { name = name })
            end
            if line then lines[line] = true end
            if type(name) == "string" and name ~= "" then
                local low = ns.Util.lower(name)
                want[low] = true
                -- И английская пара, и русская: имя может прийти с любой
                -- стороны (клиент говорит по-русски, чужой кеш по-английски).
                local other = bridge[low]
                if other then want[other] = true end
                if not line then unresolved[#unresolved + 1] = name end
            end
        end
    end

    local t, unknownCode, matched = {}, nil, 0
    local byLine, byName = 0, 0
    for id, entry in pairs(H.PRICE_WATCH) do
        local take = true
        if want then
            take = false
            for code in tostring(entry.prof or ""):gmatch("[^%+]+") do
                local profName = H.WATCH_PROF_CODE[code]
                local profLine = H.WATCH_PROF_LINE[code]
                if profName or profLine then
                    if profLine and lines[profLine] then
                        take = true
                        byLine = byLine + 1
                    elseif profName and want[profName] then
                        take = true
                        byName = byName + 1
                    end
                else
                    -- КОД, КОТОРОГО МЫ НЕ ЗНАЕМ, - ЭТО НЕЗНАНИЕ, И ОНО ВИДНО.
                    -- Запись без разобранного кода в список не идёт: наблюдать
                    -- за чужим материалом значит писать в историю цен шум. Но
                    -- молча выбрасывать её нельзя - тогда первая же запись
                    -- третьей профессии тихо исчезнет из слепков.
                    unknownCode = unknownCode or {}
                    unknownCode[code] = (unknownCode[code] or 0) + 1
                end
            end
        end
        if take then
            t[#t + 1] = id
            matched = matched + 1
        end
    end
    if unknownCode and ns.Diag then
        ns.Diag:Log("в списке наблюдения есть код профессии, которого я не знаю", {
            codes = unknownCode,
            known = H.WATCH_PROF_CODE,
            why = "такие записи в слепок цен не идут — непонятно, чьи они",
        })
    end
    table.sort(t)

    -- ПУСТОЙ СПИСОК МОЛЧА НЕ ОТДАЁТСЯ.
    --
    -- Профессии назвали, но ни одну не удалось привязать ни к номеру линии, ни
    -- к имени - это НЕ «у него нет ни портняжки, ни чар»: это «я не понял, что
    -- у него за профессии». Разница видна на клиенте, язык которого нам
    -- незнаком: раньше оба случая выглядели как пустой список, и слепки цен
    -- просто прекращались.
    --
    -- В таком случае отдаётся весь справочник - чтобы история цен не
    -- прервалась, - и об этом ГОВОРИТСЯ: и в отчёте вызывающему, и в
    -- диагностике. Молчать здесь нельзя ни при каком из двух решений.
    local report = nil
    if want then
        local none = (matched == 0)
        local noLines = true
        for _ in pairs(lines) do noLines = false; break end
        report = {
            matched = matched, byLine = byLine, byName = byName,
            unresolved = unresolved, unknownCodes = unknownCode,
            recognised = not (none and noLines and #unresolved > 0),
        }
        if not report.recognised then
            if ns.Diag then
                ns.Diag:Log("профессии персонажа не опознаны — наблюдаю за всем списком", {
                    professions = unresolved,
                    known = H.WATCH_PROF_CODE,
                    lines = H.WATCH_PROF_LINE,
                    why = "ни номер линии навыка, ни имя не сопоставились: пустой"
                        .. " список наблюдения значил бы «ему ничего не нужно», а"
                        .. " это не то же самое, что «я не понял, кто он»",
                })
            end
            local all = {}
            for id in pairs(H.PRICE_WATCH) do all[#all + 1] = id end
            table.sort(all)
            report.matched = #all
            return all, report
        end
    end
    return t, report
end

function H:Gate(skillLineID) return H.SKILL_GATE[skillLineID] end

-- Есть ли в этом файле данные по линии навыка. Отдельный вопрос, и до него
-- «данных нет» и «рецептов нет» выглядели одинаково - как nil.
function H:KnowsLine(skillLineID)
    local id = tonumber(skillLineID)
    return (id == 197 or id == 333) and true or false
end

-- Рецепты диапазона 226-300 по линии навыка.
--
-- ВОЗВРАЩАЕТ ПРИЧИНУ, А НЕ ТОЛЬКО nil. Раньше для любой линии кроме 197 и 333
-- отдавался голый nil, и вызывающий не мог отличить «в справочнике нет данных
-- по этой профессии» от «данные есть, а рецептов в них нет». Для кузнеца и
-- алхимика это были два разных ответа, слитые в один, и игроку они доставались
-- как молчание.
function H:RecipesFor(skillLineID)
    local id = tonumber(skillLineID)
    if id == 197 then return H.FUTURE_RECIPES_197 end
    if id == 333 then return H.FUTURE_RECIPES_333 end
    return nil, "no-data"
end
