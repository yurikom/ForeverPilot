-- ForeverPilot / Data/Camp.lua
--
-- ЛАГЕРЬ: ПРЕДМЕТЫ, КОТОРЫЕ СТАВЯТСЯ У КОСТРА, И ЧТО ОНИ ДАЮТ.
--
-- ОТКУДА ЭТО ВЗЯТО. Ни одной строки из сети: обе базы уже стоят у игрока, и
-- таблица собрана из них и сверена между ними.
--
--   * Mastercraft/CampData.lua (аддон Shadowblade, его шапка говорит: Wowhead
--     Forever, гайд 34796) - профессия, тир, порог навыка, реагенты, номер
--     объекта, номер чертежа, над чем ставится. ЭТО ЕДИНСТВЕННЫЙ ИСТОЧНИК
--     ДЛЯ ПОЛЕЙ `over` И ОПИСАНИЯ ЭФФЕКТА.
--   * WhatsTraining/Crafting/Recipes/Camelot/*.lua (пакет Camelot) - порог
--     навыка и номер чертежа, собранные по заклинаниям клиента. Независимый
--     второй источник: у него своя сборка и другой автор.
--   * Mastercraft/RecipeData.lua - третий взгляд на те же пороги, но только по
--     КРАФТОВЫМ профессиям: добычных (рыбалка, травничество, горное дело,
--     снятие шкур) в окне профессии нет, и в этой таблице их нет тоже.
--
-- У Mastercraft в LICENSE.txt стоит «all rights reserved», и это сказано вслух
-- в Core/Const.lua (ns.FOREIGN_BOOK): на его данных нельзя ДЕРЖАТЬСЯ. Поэтому
-- каждое число здесь имеет второй источник, а поля, у которых его нет, помечены
-- как односторонние - см. C.CONFIDENCE ниже. Читать таблицу Mastercraft прямо
-- из его аддона нельзя: `ns.CAMPING` лежит в его собственном пространстве имён
-- и в игре снаружи не видно.
--
-- ЧТО СОШЛОСЬ И ЧТО НЕТ. 38 объектов, 12 профессий. Номера объектов, номера
-- чертежей и реагенты совпали у обоих источников полностью. Пороги навыка
-- расходятся у ДВУХ объектов, и оба расхождения оставлены в таблице как есть:
--
--   Basic Campfire  - 1 (CampData) против 20 (WhatsTraining, RecipeData);
--   Tanning Rack    - 140 (CampData, RecipeData) против 125 (WhatsTraining).
--
-- Это то самое «скрафтить можно на 125, поставить на 140», и выдумывать, какое
-- из чисел верное, здесь нечем: Blizzard уже правила эти пороги хотфиксом
-- (Journeyman Campfire с 140 на 90 - в обеих базах уже 90). Поэтому в коде
-- порогов НЕТ: Camp:Threshold отдаёт оба числа и признак спора, берёт бо́льшее
-- (лучше не пообещать, чем пообещать недоступное) и говорит об этом словами.
--
-- ИМЕНА АНГЛИЙСКИЕ И ТОЛЬКО ДЛЯ ЧЕЛОВЕКА (поля `en`, `does`, `prof`). Игроку
-- они не показываются ни разу: имя предмета берётся у клиента (Api:ItemInfo),
-- имя профессии - у клиента же через RecipeBook.NAME_BRIDGE. Руками здесь не
-- переведено ничего.
--
-- ЧТО ЭТИ ПРЕДМЕТЫ ЕСТЬ В КЛИЕНТЕ КАК РЕЦЕПТЫ - ПРОВЕРЕНО, И ЭТО МЕНЯЕТ ОТВЕТ.
--
-- Сначала казалось, что про «выучен или нет» сказать нечего: функций про лагерь
-- в клиенте нет. Но предметы лагеря лежат в ОКНЕ ПРОФЕССИИ обычными рецептами,
-- и книга рецептов аддона их уже читает. На сохранениях игрока это видно прямо:
-- у мага в «Рыбной ловле» три рецепта, и два из них выучены - это и есть
-- аквариум с рамой для рыбы. Поэтому ветка НЕ спрашивает «выучен ли чертёж» у
-- пустоты: она спрашивает у книги рецептов (RecipeBook:CanCraft).
--
-- Чего это по-прежнему не даёт: что уже ПОСТАВЛЕНО в лагере и идёт ли откат.
-- Это не рецепт и не предмет в сумке, и спросить про это нечем.
--
-- ПОЛЕ `learn` - ОТКУДА РЕЦЕПТ БЕРЁТСЯ, ЕСЛИ ОН НЕ ВЫУЧЕН. Первый тир учится у
-- тренера профессии (WhatsTraining: source = trainer, у десяти из двенадцати
-- рядом стоит ещё и квестовый путь; cost = 100 медяков у всех двенадцати).
-- Второй тир и выше - только чертёж, и чертёж это предмет: он торгуется.
--
-- ПОЛЕ `faction` ЕСТЬ РОВНО У ОДНОГО ОБЪЕКТА, и это не прихоть: у портняжного
-- знамени две версии - ордынская (279972) и альянсовая (279973). В CampData
-- лежит только ордынская, альянсовой там нет вовсе, и без пометки аддон
-- советовал бы альянсовому игроку предмет, которого у него в списке нет.
--
-- ПОЛЕ `gain` - НАША КЛАССИФИКАЦИЯ, А НЕ ДАННЫЕ. Описание эффекта в источнике -
-- английская фраза свободной формы («8% more stats», «More Spirit»); показывать
-- её русскому игроку нельзя, а переводить фразы руками - значит выдумывать. Из
-- каждой фразы выведен вид бонуса и число, если оно в ней есть; сама фраза
-- оставлена рядом в поле `does`, чтобы классификацию можно было сверить глазами
-- строка за строкой. Где числа в источнике нет - его нет и здесь, и карточка
-- говорит «сколько именно - не сказано», а не подставляет ноль.
local ADDON, ns = ...

local C = {}
ns.CampData = C

C.BUILT = "2026-11-20"

C.PROVENANCE = {
    objects  = "Mastercraft/CampData.lua (Wowhead Forever, гайд 34796)",
    skills   = "те же CampData + WhatsTraining Camelot (по заклинаниям клиента),"
            .. " сверены между собой; у 2 объектов из 38 расходятся",
    reagents = "CampData, поле reagents; совпало с RecipeData по всем крафтовым",
    blueprints = "CampData (blueprint) и WhatsTraining (teach), совпали полностью",
    effects  = "описания объектов из CampData; вид бонуса в поле gain выведен из"
            .. " них нами, число взято только там, где оно в описании есть",
    slots    = "из описания костров в CampData, второго источника нет",
    api      = "в клиенте нет ни одной функции про лагерь: что уже поставлено и"
            .. " идёт ли откат, аддону не сообщают",
    spells   = "ForeverAuras/SpellNameData.lua: номера заклинаний с именем"
            .. " объекта, прочитаны клиентом (сборка 70374); какой из них бафф,"
            .. " не проверено",
}

-- Достоверность по полям. CACHED - из баз на диске, сверено со вторым
-- источником; ESTIMATE - источник один или числа расходятся; UNKNOWN - данных
-- нет вовсе и взять их негде.
C.CONFIDENCE = {
    ITEMS      = "CACHED",
    SKILLS     = "CACHED",     -- спорные пороги помечаются по месту, см. Threshold
    REAGENTS   = "CACHED",
    BLUEPRINTS = "CACHED",
    EFFECTS    = "ESTIMATE",   -- один источник, и классификация наша
    SLOTS      = "ESTIMATE",   -- один источник
    PLACED     = "UNKNOWN",    -- что стоит в лагере, узнать нечем
}

-- Виды бонуса и как они называются по-русски. Названия характеристик здесь НЕ
-- повторяются: они берутся из единственного словаря GearAdvisor.STAT_LABEL
-- (родительный падеж - «выносливости», «силы атаки»), поэтому «больше
-- выносливости» и «+2% крита» собираются сами.
C.GAIN = {
    ALL_STATS = "все характеристики",
    STAT      = "одна характеристика",
    RESTED    = "отдых",
    FIRE      = "костёр",
    STATION   = "рабочее место",
    MAKES     = "делает расходники",
    VENDOR    = "торговец на месте",
    GATHER    = "добыча",
    FOOD      = "стол с едой",
    FISHING   = "рыба получше",
    DISENCHANT = "распыление",
    TRACK     = "слежка",
    TRAP      = "ловушка",
}

-- Поля записи:
--   prof     профессия (имя источника, английское; переводится NAME_BRIDGE)
--   tier     тир объекта
--   en       английское имя объекта - для чтения этого файла человеком
--   item     номер самого объекта (он же предмет: объекты торгуются)
--   skill    порог навыка по CampData
--   skillWT  порог навыка по WhatsTraining (nil - этот пакет объект не знает)
--   faction  предмет есть только у этой фракции (есть у одного объекта)
--   learn    откуда рецепт: "trainer" (первый тир) или "blueprint"
--   learnCost сколько просит тренер, медью (только у первого тира)
--   bp       номер чертежа (nil - учится у тренера или за задание)
--   over     объект первого тира, поверх которого ставится (его бонус остаётся)
--   reag     реагенты: { номер, сколько }
--   gain     вид бонуса, число - только если оно есть в описании
--   does     исходное описание эффекта: для сверки классификации, не для показа
C.OBJECTS = {
    { prof = "Alchemy", tier = 1, en = "Mana Well", item = 279956, skill = 20, skillWT = 20, bp = nil, learn = "trainer", learnCost = 100, over = nil, reag = { { 2447, 1 }, { 3371, 1 } }, gain = { kind = "STAT", stat = "MP5" }, does = "Mana regeneration" },
    { prof = "Alchemy", tier = 2, en = "Fermenter", item = 279970, skill = 140, skillWT = 140, learn = "blueprint", bp = 273085, over = 279956, reag = { { 3372, 1 }, { 3356, 1 }, { 2452, 1 } }, gain = { kind = "MAKES" }, does = "Creates certain reagents" },
    { prof = "Alchemy", tier = 3, en = "Alchemy Laboratory", item = 279990, skill = 300, skillWT = 300, learn = "blueprint", bp = 273112, over = 279956, reag = { { 273125, 1 }, { 8925, 1 }, { 13463, 2 } }, gain = { kind = "STATION" }, does = "For recipes that need an Alchemy Lab" },
    { prof = "Blacksmithing", tier = 1, en = "Sharpening Wheel", item = 279944, skill = 20, skillWT = 20, bp = nil, learn = "trainer", learnCost = 100, over = nil, reag = { { 2835, 1 }, { 2840, 1 } }, gain = { kind = "STAT", stat = "STR" }, does = "More Strength" },
    { prof = "Blacksmithing", tier = 2, en = "Anvil", item = 279988, skill = 140, skillWT = 140, learn = "blueprint", bp = 273086, over = 279944, reag = { { 2841, 5 }, { 3478, 2 }, { 2319, 2 } }, gain = { kind = "STATION" }, does = "An anvil you can use" },
    { prof = "Blacksmithing", tier = 3, en = "Master Forge", item = 279955, skill = 300, skillWT = 300, learn = "blueprint", bp = 273113, over = 279944, reag = { { 273127, 1 }, { 12359, 5 }, { 8170, 2 } }, gain = { kind = "STATION" }, does = "For recipes that need a forge" },
    { prof = "Enchanting", tier = 1, en = "Enchanted Lute", item = 279976, skill = 20, skillWT = 20, bp = nil, learn = "trainer", learnCost = 100, over = nil, reag = { { 4470, 1 }, { 10940, 1 } }, gain = { kind = "ALL_STATS", armor = true, resist = true }, does = "More Armor, all stats and resistances" },
    { prof = "Enchanting", tier = 2, en = "Arcane Salvager", item = 279985, skill = 140, skillWT = 140, learn = "blueprint", bp = 273103, over = 279976, reag = { { 11137, 2 }, { 11174, 1 } }, gain = { kind = "DISENCHANT" }, does = "Better disenchanting" },
    { prof = "Enchanting", tier = 3, en = "Arcane Forge", item = 279987, skill = 300, skillWT = 300, learn = "blueprint", bp = 273116, over = 279976, reag = { { 273128, 1 }, { 14344, 2 }, { 16203, 4 } }, gain = { kind = "STATION" }, does = "For recipes that need an Arcane Forge" },
    { prof = "Engineering", tier = 1, en = "Reagent Bot", item = 279950, skill = 20, skillWT = 20, bp = nil, learn = "trainer", learnCost = 100, over = nil, reag = { { 4359, 1 }, { 4361, 1 } }, gain = { kind = "VENDOR" }, does = "Sells reagents" },
    { prof = "Engineering", tier = 2, en = "Repair Bot", item = 279949, skill = 140, skillWT = 140, learn = "blueprint", bp = 273092, over = nil, reag = { { 4375, 2 }, { 4371, 1 }, { 4234, 1 } }, gain = { kind = "VENDOR", repair = true }, does = "Sells reagents and repairs gear" },
    { prof = "Engineering", tier = 3, en = "Anarchist's Workbench", item = 279989, skill = 300, skillWT = 300, learn = "blueprint", bp = 273117, over = nil, reag = { { 273129, 1 }, { 15994, 2 } }, gain = { kind = "STATION" }, does = "For recipes that need it" },
    { prof = "Herbalism", tier = 1, en = "Incense Candle", item = 279962, skill = 20, skillWT = 20, bp = nil, learn = "trainer", learnCost = 100, over = nil, reag = { { 2447, 1 }, { 765, 1 } }, gain = { kind = "STAT", stat = "INT" }, does = "More Intellect" },
    { prof = "Herbalism", tier = 2, en = "Greenhouse", item = 279964, skill = 140, skillWT = 140, learn = "blueprint", bp = 273106, over = 279962, reag = { { 4470, 2 }, { 8836, 1 }, { 8831, 1 } }, gain = { kind = "GATHER" }, does = "Grows herbs from planted seeds" },
    { prof = "Herbalism", tier = 3, en = "Seed Hybridizer", item = 279947, skill = 300, skillWT = 300, learn = "blueprint", bp = 273120, over = 279962, reag = { { 13465, 4 }, { 8925, 1 }, { 14047, 2 } }, gain = { kind = "GATHER" }, does = "Turns seeds into rarer ones" },
    { prof = "Leatherworking", tier = 1, en = "Camp Tent", item = 279978, skill = 20, skillWT = 20, bp = nil, learn = "trainer", learnCost = 100, over = nil, reag = { { 2318, 5 } }, gain = { kind = "RESTED", pct = 5 }, does = "Rested XP, up to 5% of a level" },
    { prof = "Leatherworking", tier = 2, en = "Tanning Rack", item = 279941, skill = 140, skillWT = 125, learn = "blueprint", bp = 273096, over = 279978, reag = { { 2319, 5 }, { 2321, 3 }, { 4470, 2 } }, gain = { kind = "MAKES" }, does = "Creates certain reagents" },
    { prof = "Leatherworking", tier = 3, en = "Sewing Machine", item = 279945, skill = 300, skillWT = 300, learn = "blueprint", bp = 273121, over = 279978, reag = { { 273130, 1 }, { 8170, 5 }, { 14341, 1 } }, gain = { kind = "STATION" }, does = "For recipes that need it" },
    { prof = "Mining", tier = 1, en = "Lodestone", item = 279960, skill = 20, skillWT = 20, bp = nil, learn = "trainer", learnCost = 100, over = nil, reag = { { 2835, 1 }, { 2840, 1 } }, gain = { kind = "STAT", stat = "ATTACKPOWER" }, does = "More melee Attack Power" },
    { prof = "Mining", tier = 2, en = "Rock Garden", item = 279948, skill = 140, skillWT = 140, learn = "blueprint", bp = 273097, over = 279960, reag = { { 2838, 2 }, { 2772, 1 }, { 2842, 1 } }, gain = { kind = "GATHER" }, does = "Grows a common mining node over time" },
    { prof = "Mining", tier = 3, en = "Molten Foundry", item = 279952, skill = 300, skillWT = 300, learn = "blueprint", bp = 273122, over = 279960, reag = { { 12359, 5 }, { 12365, 2 }, { 6037, 1 } }, gain = { kind = "STATION" }, does = "For recipes that need it" },
    { prof = "Skinning", tier = 1, en = "Camp Chair", item = 279979, skill = 20, skillWT = 20, bp = nil, learn = "trainer", learnCost = 100, over = nil, reag = { { 2318, 3 }, { 4470, 2 } }, gain = { kind = "STAT", stat = "CRIT", pct = 2 }, does = "2% critical strike" },
    { prof = "Skinning", tier = 2, en = "Field Guide", item = 279969, skill = 140, skillWT = 140, learn = "blueprint", bp = 273098, over = 279979, reag = { { 2319, 3 }, { 5784, 2 }, { 2321, 1 } }, gain = { kind = "TRACK" }, does = "Gives Track Beasts" },
    { prof = "Skinning", tier = 3, en = "Trapper's Workbench", item = 279938, skill = 300, skillWT = 300, learn = "blueprint", bp = 273109, over = 279979, reag = { { 4470, 2 }, { 4234, 4 }, { 3575, 1 } }, gain = { kind = "TRAP" }, does = "Holds a trap" },
    { prof = "Tailoring", tier = 1, en = "Faction Banner", item = 279972, faction = "Horde", skill = 20, skillWT = 20, bp = nil, learn = "trainer", learnCost = 100, over = nil, reag = { { 2996, 1 }, { 2320, 1 } }, gain = { kind = "STAT", stat = "SPI" }, does = "More Spirit" },
    { prof = "Tailoring", tier = 2, en = "Spinning Wheel", item = 279943, skill = 140, skillWT = 140, learn = "blueprint", bp = 273099, over = 279972, reag = { { 4470, 2 }, { 4305, 5 }, { 2321, 3 } }, gain = { kind = "MAKES" }, does = "Creates certain reagents" },
    { prof = "Tailoring", tier = 3, en = "Loom", item = 279959, skill = 300, skillWT = 300, learn = "blueprint", bp = 273124, over = 279972, reag = { { 273131, 1 }, { 14048, 4 }, { 4470, 4 } }, gain = { kind = "STATION" }, does = "For recipes that need it" },
    { prof = "Cooking", tier = 1, en = "Basic Campfire", item = 279981, skill = 1, skillWT = 20, bp = nil, learn = "trainer", learnCost = 100, over = nil, reag = { { 4470, 1 } }, gain = { kind = "FIRE", slots = 3 }, does = "Cooking fire, room for 3 more camp features" },
    { prof = "Cooking", tier = 2, en = "Journeyman Campfire", item = 279961, skill = 90, skillWT = 90, learn = "blueprint", bp = 273087, over = nil, reag = { { 11291, 1 } }, gain = { kind = "FIRE", slots = 5 }, does = "Cooking fire, room for 5 more camp features" },
    { prof = "Cooking", tier = 2, en = "Cookie's Feast", item = 279957, skill = 140, skillWT = 140, learn = "blueprint", bp = 273102, over = nil, reag = { { 12037, 2 }, { 12204, 1 }, { 3713, 1 } }, gain = { kind = "FOOD", stat = "STA" }, does = "A table of Stamina food" },
    { prof = "Cooking", tier = 3, en = "Expert Campfire", item = 279974, skill = 200, skillWT = 200, learn = "blueprint", bp = 273101, over = nil, reag = { { 272941, 1 } }, gain = { kind = "FIRE", slots = 10 }, does = "Cooking fire, room for 10 more camp features" },
    { prof = "Cooking", tier = 4, en = "Iron Oven", item = 279982, skill = 300, skillWT = 300, learn = "blueprint", bp = 273115, over = nil, reag = { { 10284, 10 }, { 159, 5 }, { 3713, 4 } }, gain = { kind = "STATION" }, does = "For the most advanced cooking recipes" },
    { prof = "First Aid", tier = 1, en = "First Aid Kit", item = 279968, skill = 20, skillWT = 20, bp = nil, learn = "trainer", learnCost = 100, over = nil, reag = { { 1251, 3 }, { 159, 1 } }, gain = { kind = "STAT", stat = "STA" }, does = "More Stamina" },
    { prof = "First Aid", tier = 2, en = "Toxin Study", item = 279940, skill = 140, skillWT = 140, learn = "blueprint", bp = 273105, over = nil, reag = { { 6452, 1 }, { 8544, 2 }, { 4470, 2 } }, gain = { kind = "MAKES" }, does = "Healing potions and anti-venom" },
    { prof = "First Aid", tier = 3, en = "Plague Doctor's Laboratory", item = 279951, skill = 300, skillWT = 300, learn = "blueprint", bp = 273118, over = nil, reag = { { 4470, 2 }, { 6453, 2 }, { 14530, 5 } }, gain = { kind = "MAKES" }, does = "Healing potions and poultices" },
    { prof = "Fishing", tier = 1, en = "Fish Bowl", item = 279967, skill = 20, skillWT = 20, bp = nil, learn = "trainer", learnCost = 100, over = nil, reag = { { 6291, 1 }, { 3371, 1 } }, gain = { kind = "ALL_STATS", pct = 8 }, does = "8% more stats" },
    { prof = "Fishing", tier = 2, en = "Fishing Rack", item = 279965, skill = 140, skillWT = 140, learn = "blueprint", bp = 273141, over = 279967, reag = { { 4470, 2 }, { 8925, 1 }, { 8365, 2 } }, gain = { kind = "FISHING" }, does = "Catch uncommon fish for 1 hour" },
    { prof = "Fishing", tier = 3, en = "Fishing Hut", item = 279966, skill = 300, skillWT = 300, learn = "blueprint", bp = 273119, over = 279967, reag = { { 4470, 5 }, { 14048, 2 }, { 273295, 1 } }, gain = { kind = "FISHING" }, does = "Catch rare fish for 1 hour" },
}

-- ЗАКЛИНАНИЯ С ТЕМ ЖЕ ИМЕНЕМ, ЧТО У ОБЪЕКТА ЛАГЕРЯ ------------------------
--
-- Зачем. Что стоит у костра, игра не говорит. Но объект первого тира даёт
-- бонус, а бонус - это бафф на игроке, и баффы прочитать можно. Если на игроке
-- висит заклинание с именем объекта лагеря, объект уже работает - и советовать
-- его поставить незачем.
--
-- Откуда. ForeverAuras/SpellNameData.lua (GNU GPL v2): номера заклинаний,
-- у которых в клиенте одно и то же имя, прочитанные самим клиентом (сборка
-- 70374, C_Spell.GetSpellName по всему диапазону). Имена сопоставлены с полем
-- `en` точно, все 38 нашлись. Из списка убраны два номера классической игры у
-- обычного костра (818, 1290): это не лагерь.
--
-- КАКОЙ ИЗ НОМЕРОВ - БАФФ, ЗДЕСЬ НЕ СКАЗАНО, И ЭТО НЕ НУЖНО. Первый в списке -
-- рецепт (он совпадает с номерами рецептов в окне профессии), последний, судя
-- по сплошному ряду 1307xxx у всех 38, - сама установка. У объектов первого
-- тира есть ещё один, из ряда 12552xx, - по всей видимости, он и есть бафф.
-- Проверить это без игры нечем, поэтому сравнение идёт со ВСЕМ списком: рецепт
-- и установка на игроке баффом не висят, и лишние номера ничего не портят.
C.EFFECT_SPELLS = {
    [279956] = { 1230564, 1255259, 1307259 },
    [279970] = { 1263005, 1307242 },
    [279990] = { 1263078, 1307172 },
    [279944] = { 1230171, 1255257, 1307392 },
    [279988] = { 1231768, 1231770, 1263041, 1307175 },
    [279955] = { 1263073, 1307261 },
    [279976] = { 1230643, 1255260, 1307234 },
    [279985] = { 1263056, 1307223 },
    [279987] = { 1263082, 1307176 },
    [279950] = { 1230656, 1255261, 1307266 },
    [279949] = { 1263034, 1307385 },
    [279989] = { 1263083, 1307174 },
    [279962] = { 1229705, 1255251, 1307251 },
    [279964] = { 1262980, 1307248 },
    [279947] = { 1263070, 1307387 },
    [279978] = { 1229432, 1229487, 1255248, 1307230 },
    [279941] = { 1263031, 1307395 },
    [279945] = { 1263079, 1307391 },
    [279960] = { 1230161, 1255256, 1307254 },
    [279948] = { 1262975, 1279455, 1279456, 1279459, 1279537, 1279538, 1279539, 1307386 },
    [279952] = { 1263071, 1307264 },
    [279979] = { 1229517, 1255250, 1307229 },
    [279969] = { 1225479, 1262985, 1307243 },
    [279938] = { 1262982, 1307397 },
    [279972] = { 1229504, 1255249, 1263425, 1290398, 1307239, 1307240 },
    [279943] = { 1263032, 1307393 },
    [279959] = { 1263080, 1307255 },
    [279981] = { 1229737, 1307227 },
    [279961] = { 1283400, 1307252 },
    [279957] = { 1262978, 1307257 },
    [279974] = { 1291341, 1307237 },
    [279982] = { 1263067, 1307226 },
    [279968] = { 1230117, 1255255, 1307244 },
    [279940] = { 1262996, 1307396 },
    [279951] = { 1263001, 1307265 },
    [279967] = { 1229745, 1255254, 1307245 },
    [279965] = { 1262990, 1307247 },
    [279966] = { 1262998, 1307246 },
}
C.ITEM_BY_SPELL = {}
for itemID, list in pairs(C.EFFECT_SPELLS) do
    for _, spellID in ipairs(list) do C.ITEM_BY_SPELL[spellID] = itemID end
end

-- Индексы: по номеру объекта и по профессии. Строятся один раз при загрузке.
C.BY_ITEM = {}
C.BY_PROFESSION = {}
C.PROFESSIONS = {}
for _, row in ipairs(C.OBJECTS) do
    C.BY_ITEM[row.item] = row
    local list = C.BY_PROFESSION[row.prof]
    if not list then
        list = {}
        C.BY_PROFESSION[row.prof] = list
        C.PROFESSIONS[#C.PROFESSIONS + 1] = row.prof
    end
    list[#list + 1] = row
end
table.sort(C.PROFESSIONS)

-- Сколько всего профессий у лагеря и сколько объектов первого тира: число «из
-- скольких» на карточке берётся отсюда, а не вписывается в текст руками.
C.TIER1_COUNT = 0
for _, row in ipairs(C.OBJECTS) do
    if row.tier == 1 then C.TIER1_COUNT = C.TIER1_COUNT + 1 end
end

return C
