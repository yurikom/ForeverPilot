-- ForeverPilot / Core/Const.lua
-- Immutable constants. No game API calls here, no UI. Loadable by plain Lua for tests.
local ADDON, ns = ...

ns.ADDON_NAME = ADDON or "ForeverPilot"
ns.VERSION = "0.3.0"

-- Money ------------------------------------------------------------------
ns.COPPER_PER_SILVER = 100
ns.COPPER_PER_GOLD = 10000

-- The unit the gear and enchant advice is measured in ---------------------
--
-- It is a weighted sum over THIS character's stat weights: for an arcane mage
-- that is intellect, spell power and spirit, and strength contributes nothing
-- at all. It used to be printed as "ед. силы", which names the one stat the
-- mage has no use for - the player read "+16 ед. силы" as advice to stack
-- Strength and said so. The word lives here now so the cards, the tooltips and
-- the character tab cannot drift apart again.
--
-- А ПОТОМ ОНО СТАЛО «ед. пользы», И ЭТО ТОЖЕ БЫЛО НЕ ПО-ЧЕЛОВЕЧЕСКИ.
--
-- «ед.» - сокращение из таблицы разработчика: игрок прочитал «+0 ед. пользы» и
-- спросил, в чём именно это измеряется. Ответить нечем: единицы «пользы» не
-- существует, это наш условный счёт по весам характеристик. Так он и называется
-- теперь - БАЛЛ, тем же словом, которым объясняет себя вкладка настроек («мой
-- условный балл по этим весам»). Слово знакомое, не выдаёт себя за величину из
-- игры, и в столбце справа его невозможно спутать с деньгами.
--
-- Здесь лежит ОСНОВА слова, без числа и без падежа: печатать его должен
-- ns.Util.benefit(n), который согласует «1 балл / 2 балла / 5 баллов». Писать
-- `U.round(x) .. " " .. ns.UNIT_BENEFIT` по месту нельзя - именно так на экране
-- получается «2 балл».
--
-- Короткой формы («ед.») здесь больше нет. Она была мёртвым полем: писалась в
-- Core/Const.lua и не читалась ни одной строкой аддона - то есть выглядела
-- вторым, запасным словом для того же числа, которого на экране никогда не было.
--
-- The priority profile called "Сила" is a different word in a different role:
-- it is a goal ("be stronger now"), not a unit, and PROFILE_TIP says so.
ns.UNIT_BENEFIT = "балл"
ns.UNIT_BENEFIT_FORMS = { "балл", "балла", "баллов" }

-- СКОЛЬКО ПОЛЬЗЫ - УЖЕ УЛУЧШЕНИЕ, А СКОЛЬКО - РАЗМЕН.
--
-- Порог стоял на 0.01, то есть «любой плюс сверх нуля», а на экране число
-- печатается целым. Между этими двумя правилами и живёт дефект, который игрок
-- прислал скриншотом: «Теневые очки» дают ему +5 интеллекта за -8 выносливости,
-- -1 духа и -4 брони, по его весам это +0.27 - и карточка честно напечатала
-- «+0 ед. пользы», предложив потратить материалы на вещь, которая не лучше.
--
-- Правило теперь одно и простое: УЛУЧШЕНИЕМ НАЗЫВАЕТСЯ ТОЛЬКО ТО, ЧТО АДДОН
-- МОЖЕТ НАПЕЧАТАТЬ КАК УЛУЧШЕНИЕ. Меньше половины балла округляется в ноль,
-- значит это не улучшение, а размен: что-то выросло, что-то упало, итог нулевой.
-- Такой совет не попадает в список ни при каком раскладе - ни в ветку «скрафтить
-- и надеть», ни в «надеть своё», ни в развилку путей; причина пишется в воронку
-- словами, чтобы «куда делся совет» имело ответ.
ns.MIN_BENEFIT_GAIN = 0.5

-- СКОЛЬКО ДЕНЕГ - УЖЕ СОВЕТ, А СКОЛЬКО - ВОДА. ПОЛОСАМИ ПО УРОВНЮ.
--
-- Игрок сказал дословно: «если я выигрываю меньше 20 или 30 золотых, слоя
-- золотых, серебряных, то смысла нету это показывать, особенно выше чем в 20-м
-- левеле. Если ты находишься на мелких левелах персонажа до 15-го, тогда можно
-- показывать с 10-го и выше серебра выигрыш. Если там выше 15-го левела или
-- 20-го, больше 30-ти как минимум.»
--
-- Два края он назвал сам - 15 и 20, - поэтому полос три, а не две и не пять.
-- Промежуточная полоса не придумана «чтобы было»: это его второй край, и именно
-- в ней сейчас стоит его персонаж (16 ур.).
--
-- ЕДИНИЦУ ЕГО «30» РЕШАЕТ ОН, А НЕ МЫ, И ЧИСЛА ЗДЕСЬ - ТОЛЬКО ОТПРАВНАЯ ТОЧКА.
-- На его собственных сохранениях (чернокнижник, 16 ур., 47 золота) вся денежная
-- половина аддона лежит между 4с 28м и 97с 95м: пятнадцать советов, и ни один
-- не дотягивает до золотого. Порог «30 золотых» оставил бы ноль из пятнадцати -
-- то есть выключил бы деньги целиком, а не отсеял воду. Поэтому «30» прочитано
-- как СЕРЕБРО, и лестница получилась ровно из его чисел: 10 - 20 - 30 серебра.
-- Сколько на этих порогах остаётся на его данных, видно числами:
--   без порога 15, 10с - 7, 20с - 4, 30с - 2, 1з - 0, 30з - 0.
--
-- Полосы и числа - настройка игрока (Config:MoneyFloor, раздел «Мелкая денежная
-- выгода» в настройках), а не приговор: их видно, и их можно сменить или
-- выключить порог вовсе.
--
-- `upTo` - последний уровень полосы; `false` означает «и выше». Подпись лежит
-- рядом с числом, чтобы экран настроек и строка под списком не могли разойтись.
ns.MONEY_FLOOR_BANDS = {
    { upTo = 15,    copper = 1000, label = "1-15 ур." },
    { upTo = 20,    copper = 2000, label = "16-20 ур." },
    { upTo = false, copper = 3000, label = "21 ур. и выше" },
}

-- Из чего игрок выбирает своё одно число на все уровни. Лестница, а не
-- ползунок: ползунок печатает «20.00», а это не деньги. Ноль - «показывать
-- любую выгоду»; 30 золотых в списке есть сознательно - это ровно то число, про
-- которое игрок спрашивал, и он имеет право его поставить и увидеть результат.
ns.MONEY_FLOOR_CHOICES = { 0, 500, 1000, 2000, 3000, 5000, 10000, 50000, 300000 }

-- ПОРОГ КАСАЕТСЯ ТОЛЬКО ДЕНЕЖНЫХ ВЕТОК.
--
-- Экипировка, чары и прокачка навыка деньгами не меряются: их выгода - баллы и
-- пункты навыка, и мерить их золотом неправильно. Покупка материалов (BUY) тоже
-- не здесь: это расход под чужой совет, а не выигрыш. Список закрыт, и
-- Tests/test_vanish.lua держит его закрытым.
--
-- ЛАГЕРЯ (CAMP) ЗДЕСЬ НЕТ, И ЭТО РЕШЕНИЕ, А НЕ ЗАБЫВЧИВОСТЬ. Совет про лагерь
-- не приносит денег - он их ТРАТИТ: реагенты на предмет стоят 86 медяков,
-- чертёж на аукционе - золотые. Выигрыш у него в бонусе у костра, и в деньгах
-- его не выразить. Порог по смыслу отсекает мелкую ВЫРУЧКУ; приложенный к
-- трате, он выбросил бы самый дешёвый совет в аддоне именно за то, что тот
-- дешёвый. Проверка - в Tests/test_camp.lua: при пороге 30 золотых советы про
-- лагерь остаются на экране.
ns.MONEY_FLOOR_KINDS = {
    CRAFT_PROFIT = true,   -- «на продажу»
    ARBITRAGE    = true,   -- купить у торговца и перепродать
    RESELL       = true,   -- перекупить дешёвый лот
    DISENCHANT   = true,   -- распыление
    SELL_JUNK    = true,   -- продать хлам
}

ns.MONEY_FLOOR_MODE = {
    LEVEL = "level",   -- по полосам выше
    FIXED = "fixed",   -- одно своё число на все уровни
    OFF   = "off",     -- порога нет
}

-- Equipment slots we reason about. Keys are our own stable ids (never shown raw
-- to the player unless a localised name is missing).
ns.SLOT = {
    HEAD     = "HEAD",
    NECK     = "NECK",
    SHOULDER = "SHOULDER",
    BACK     = "BACK",
    CHEST    = "CHEST",
    WRIST    = "WRIST",
    HANDS    = "HANDS",
    WAIST    = "WAIST",
    LEGS     = "LEGS",
    FEET     = "FEET",
    FINGER   = "FINGER",
    TRINKET  = "TRINKET",
    MAINHAND = "MAINHAND",
    OFFHAND  = "OFFHAND",
    RANGED   = "RANGED",
    TWOHAND  = "TWOHAND",
    SHIELD   = "SHIELD",
    HELDINHAND = "HELDINHAND",
    SHIRT    = "SHIRT",
    TABARD   = "TABARD",
    BAG      = "BAG",
}

-- Our slot id -> the inventory slot id the game uses for GetInventoryItemLink.
-- Only slots that map 1:1 are listed; FINGER/TRINKET are handled as pairs.
ns.SLOT_INVENTORY_ID = {
    HEAD = 1, NECK = 2, SHOULDER = 3, SHIRT = 4, CHEST = 5, WAIST = 6,
    LEGS = 7, FEET = 8, WRIST = 9, HANDS = 10, BACK = 15,
    MAINHAND = 16, OFFHAND = 17, RANGED = 18, TABARD = 19,
}
ns.SLOT_INVENTORY_PAIRS = {
    FINGER = { 11, 12 },
    TRINKET = { 13, 14 },
}

-- Slots that can take an enchant in this expansion's ruleset.
ns.ENCHANTABLE_SLOTS = {
    "HEAD", "SHOULDER", "BACK", "CHEST", "WRIST", "HANDS", "LEGS", "FEET",
    "MAINHAND", "OFFHAND", "SHIELD", "RANGED", "NECK",
}

-- ИНСТРУМЕНТЫ ПРОФЕССИЙ - НЕ БОЕВАЯ ЭКИПИРОВКА.
--
-- Игрок надел удочку, чтобы порыбачить, и аддон начал советовать ему оружие:
-- слот оценивался по надетому, а у удочки боевой ценности нет. Отличать их по
-- названию нельзя (имя приходит на языке клиента и у каждого инструмента своё),
-- зато тип предмета - это число из клиента: класс 2 (оружие) и подкласс.
--   14 - «разное»: кирка, молот кузнеца, нож для снятия шкур
--   20 - удочка
-- Числа проверены по установленной базе предметов: 6367 «Большая железная
-- удочка» = 2/20, 7005 «Нож для снятия шкур» = 2/14, а палочка Громодерево
-- (13062) = 2/19 и инструментом не считается.
--
-- Если клиент выдаёт Enum.ItemWeaponSubclass, номера берутся оттуда, а эта
-- таблица остаётся запасным путём (см. GearAdvisor:ToolSubclasses).
ns.TOOL_WEAPON_SUBCLASS = { [14] = true, [20] = true }
ns.TOOL_WEAPON_SUBCLASS_NAMES = { "Generic", "Miscellaneous", "Fishingpole", "FishingPole" }

-- Canonical stat keys. We map the client's localised stat keys onto these.
--
-- THE SCHOOL KEYS ARE NOT OPTIONAL. Armour in this patch comes in families of
-- six that are identical except for which school of magic their spell power
-- applies to: Pristine gives generic spell power plus healing, Pearly gives
-- Arcane, Silky gives Frost, Flame gives Fire, Shadow gives Shadow, Shining
-- gives Holy. Without separate keys for the schools, the worn Pearly Circlet
-- (sta10 armor35 spArcane11) scored as 6.2 - stamina and armour only, its main
-- stat invisible - while the Pristine one (sta12 armor38 sp8 heal22) scored
-- 22.36, and the addon told an arcane mage to craft a downgrade. He did.
ns.STAT = {
    INT = "INT", SPI = "SPI", STA = "STA", STR = "STR", AGI = "AGI",
    SPELLPOWER = "SPELLPOWER", SPELLDMG = "SPELLDMG", HEALPOWER = "HEALPOWER",
    SPELLDMG_ARCANE = "SPELLDMG_ARCANE",
    SPELLDMG_FIRE   = "SPELLDMG_FIRE",
    SPELLDMG_FROST  = "SPELLDMG_FROST",
    SPELLDMG_NATURE = "SPELLDMG_NATURE",
    SPELLDMG_SHADOW = "SPELLDMG_SHADOW",
    SPELLDMG_HOLY   = "SPELLDMG_HOLY",
    SPELLCRIT = "SPELLCRIT", SPELLHIT = "SPELLHIT", SPELLHASTE = "SPELLHASTE",
    MP5 = "MP5", ATTACKPOWER = "ATTACKPOWER",
    CRIT = "CRIT", HIT = "HIT", HASTE = "HASTE", EXPERTISE = "EXPERTISE",
    ARMOR = "ARMOR", DEFENSE = "DEFENSE", DODGE = "DODGE", PARRY = "PARRY", BLOCK = "BLOCK",
    RESIST_ARCANE = "RESIST_ARCANE", RESIST_FIRE = "RESIST_FIRE",
    RESIST_FROST = "RESIST_FROST", RESIST_NATURE = "RESIST_NATURE",
    RESIST_SHADOW = "RESIST_SHADOW",
    HEALTH = "HEALTH", MANA = "MANA",
    -- Weapon damage per second, derived from the damage range and the swing
    -- speed. THE ADDON USED TO IGNORE IT ENTIRELY, which made every weapon
    -- comparison meaningless and every wand comparison impossible: a wand's
    -- only stat IS its damage. The player's own "Громодерево" is dmin36 dmax67
    -- speed1900, i.e. 27.1 per second, and the addon reported "характеристики
    -- клиент не отдаёт" about it while offering a weaker one in its place.
    DPS = "DPS",
}

-- The spell schools, and the single place that says which stat key belongs to
-- which school. Order is the client's own school numbering (0 physical,
-- 1 holy, 2 fire, 3 nature, 4 frost, 5 shadow, 6 arcane), so a label can be
-- asked of the client rather than written here by hand.
ns.SPELL_SCHOOLS = {
    { key = "ARCANE", stat = "SPELLDMG_ARCANE", schoolIndex = 6, resist = "RESIST_ARCANE" },
    { key = "FIRE",   stat = "SPELLDMG_FIRE",   schoolIndex = 2, resist = "RESIST_FIRE" },
    { key = "FROST",  stat = "SPELLDMG_FROST",  schoolIndex = 4, resist = "RESIST_FROST" },
    { key = "NATURE", stat = "SPELLDMG_NATURE", schoolIndex = 3, resist = "RESIST_NATURE" },
    { key = "SHADOW", stat = "SPELLDMG_SHADOW", schoolIndex = 5, resist = "RESIST_SHADOW" },
    { key = "HOLY",   stat = "SPELLDMG_HOLY",   schoolIndex = 1, resist = nil },
}

-- stat key -> school entry, for the scorer's cap and for the card text.
ns.SCHOOL_BY_STAT = {}
for _, s in ipairs(ns.SPELL_SCHOOLS) do ns.SCHOOL_BY_STAT[s.stat] = s end

-- Priority profiles. The four buttons above the list.
ns.PROFILE = {
    POWER   = "POWER",
    LEVEL   = "LEVEL",
    THRIFT  = "THRIFT",
    EARN    = "EARN",
}
ns.PROFILE_ORDER = { "POWER", "LEVEL", "THRIFT", "EARN" }

ns.PROFILE_LABEL = {
    POWER  = "Сила",
    LEVEL  = "Прокачка",
    THRIFT = "Экономия",
    EARN   = "Заработок",
}
ns.PROFILE_TIP = {
    POWER  = "Сильнее прямо сейчас: экипировка и чары важнее денег."
        .. " Речь об общей боевой пользе по вашим весам, а не о характеристике «сила».",
    LEVEL  = "Поднять профессии: ценится прирост навыка за крафт.",
    THRIFT = "Не тратить золото: сначала то, что уже есть в сумках.",
    EARN   = "Заработать: крафт на продажу и чистка хлама.",
}

-- Axis weights per profile. Axes are normalised to 0..1 before weighting.
-- power  = stat-weight gain from gear/enchants
-- skill  = expected profession skill-up
-- profit = expected gold gained
-- spend  = gold that leaves the wallet (always negative weight)
-- ready  = can be done right now with what is on hand
ns.PROFILE_WEIGHTS = {
    POWER  = { power = 1.00, skill = 0.15, profit = 0.10, spend = -0.25, ready = 0.30 },
    LEVEL  = { power = 0.35, skill = 1.00, profit = 0.10, spend = -0.30, ready = 0.35 },
    THRIFT = { power = 0.45, skill = 0.30, profit = 0.35, spend = -1.00, ready = 0.60 },
    EARN   = { power = 0.15, skill = 0.20, profit = 1.00, spend = -0.35, ready = 0.30 },
}

-- ПРОФИЛЬ МЕНЯЕТ НЕ ТОЛЬКО ПОРЯДОК, НО И СОСТАВ.
--
-- Весами одного порядка не добиться: карточка с нулевой пользой по профилю всё
-- равно набирает очки по другим осям и остаётся в списке - просто ниже. На
-- экране это выглядит так, будто кнопки профиля почти ничего не делают, и
-- именно так это и выглядело.
--
-- Поэтому у каждого профиля есть ещё две таблицы:
--
--   PROFILE_EXCLUDE - виды карточек, которых в этом профиле быть НЕ ДОЛЖНО.
--     Не «ниже», а не быть: «Экономия» не показывает перекупку лотов, потому
--     что перекупка - это по определению вложить деньги и подождать, то есть
--     ровно то, чего человек в этом профиле не хочет. Выброшенные карточки не
--     исчезают молча: их число и причина пишутся в branchNote и видны в окне.
--
--   PROFILE_BOOST - множитель к очкам вида, который этому профилю по смыслу
--     ближе всего. Это не замена весам, а усиление того, что весами уже
--     выражено: в «Заработке» денежные ветки должны стоять заметно выше, а не
--     на полпункта.
ns.PROFILE_EXCLUDE = {
    -- Сильнее прямо сейчас: деньги ради денег в этом профиле не нужны,
    -- а вот справка про цены - шум.
    POWER  = { RESELL = true, PRICE_INFO = true },
    -- Поднять профессии: перекупка и справка про цены к навыку не ведут.
    LEVEL  = { RESELL = true, PRICE_INFO = true, ARBITRAGE = true },
    -- Не тратить золото: всё, что начинается с «вложить», отсюда уходит.
    -- Распыление тоже: это покупка ради рандома.
    THRIFT = { RESELL = true, DISENCHANT = true },
    -- Заработать: ничего не исключаем, но ниже усиливаем денежное.
    EARN   = {},
}

ns.PROFILE_BOOST = {
    -- Лагерь усилен только в «Силе»: бонус у костра - это именно «сильнее
    -- прямо сейчас», и стоит он дешевле любой вещи. В «Прокачке» его нет
    -- нарочно: единственный предмет лагеря, который ускоряет уровень, - палатка
    -- с отдыхом, и она требует кожевничества, которого у игрока ни на одном
    -- персонаже нет. Усиливать ветку за бонус, до которого ему не дойти,
    -- значило бы поднимать её ни за что.
    POWER  = { CRAFT_GEAR = 1.25, EQUIP = 1.25, ENCHANT = 1.15, FAVOR = 1.20,
               PATHS = 1.20, CAMP = 1.15 },
    LEVEL  = { CRAFT_SKILL = 1.40, FAVOR = 1.15 },
    THRIFT = { EQUIP = 1.40, SELL_JUNK = 1.25, CROSS_CHAR = 1.30 },
    EARN   = { CRAFT_PROFIT = 1.30, ARBITRAGE = 1.40, RESELL = 1.30,
               DISENCHANT = 1.20, SELL_JUNK = 1.20, PRICE_INFO = 1.15 },
}

-- Card kinds. Each kind is one row type in the single ranked list.
ns.KIND = {
    CRAFT_GEAR   = "CRAFT_GEAR",
    CRAFT_MAT    = "CRAFT_MAT",
    CRAFT_SKILL  = "CRAFT_SKILL",
    CRAFT_PROFIT = "CRAFT_PROFIT",
    ENCHANT      = "ENCHANT",
    EQUIP        = "EQUIP",
    BUY          = "BUY",
    SELL_JUNK    = "SELL_JUNK",
    SETUP        = "SETUP",
    -- Экономика второго этапа. Все четыре - в тот же единый список, отдельных
    -- экранов не появляется: это такие же строки, как «скрафтить» и «надеть».
    ARBITRAGE    = "ARBITRAGE",    -- купить у торговца, продать на аукционе
    DISENCHANT   = "DISENCHANT",   -- купить и распылить (ОЖИДАНИЕ, не обещание)
    RESELL       = "RESELL",       -- перекупить лот заметно ниже рынка
    PRICE_INFO   = "PRICE_INFO",   -- что своя история говорит о цене предмета
    -- Третий этап.
    PATHS        = "PATHS",        -- развилка: скрафтить / купить / квест / торговец
    CROSS_CHAR   = "CROSS_CHAR",   -- материал у одного персонажа, профессия у другого
    -- Благосклонность торговца. Отдельный вид, потому что это не золото и не
    -- крафт: это покупка за репутационную валюту, и гейт у неё по НАВЫКУ.
    FAVOR        = "FAVOR",
    -- Лагерь. Отдельный вид, потому что выгода у него не в золоте и не в
    -- баллах: это бонус всем у костра, и считается он процентами, которых в
    -- весах характеристик нет. Чем он при этом ОСОБЕННЫЙ: предмет лагеря даёт
    -- любая профессия, включая добычные, - значит ветка считает по обоим
    -- персонажам аккаунта, а не по тому, кем играют сейчас.
    CAMP         = "CAMP",
}
-- НАЗВАНИЕ ВИДА ЧИТАЕТСЯ САМО ПО СЕБЕ.
--
-- Эти названия стоят не только значком на карточке: из них собирается строка
-- «Профиль «Прокачка» не показывает 13 советов: Купить и перепродать (8),
-- Перекупить (4), Про цену (1)». Игрок прочитал её и спросил, что такое
-- «Перекупить»: слово называет действие, но не говорит, с чем оно делается, а
-- рядом стоит похожее «Купить и перепродать» - и различить их нечем.
--
-- Разница между ними как раз в том, ГДЕ покупается: у торговца по фиксированной
-- цене (ARBITRAGE) или на аукционе, где кто-то выставил лот заметно ниже рынка
-- (RESELL). Это и написано.
--
-- «Надеть» и «Купить» остались короткими: там действие и предмет видны в самом
-- заголовке совета («Надеть: Мерцающий посох»), а догадываться не о чем.
ns.KIND_LABEL = {
    EQUIP        = "Надеть своё",
    CRAFT_GEAR   = "Скрафтить и надеть",
    CRAFT_MAT    = "Скрафтить материал",
    CRAFT_SKILL  = "Крафт на навык",
    CRAFT_PROFIT = "Скрафтить на продажу",
    ENCHANT      = "Наложить чары",
    BUY          = "Купить материалы",
    SELL_JUNK    = "Продать хлам",
    SETUP        = "Настроить",
    ARBITRAGE    = "Купить у торговца и перепродать",
    DISENCHANT   = "Распылить",
    RESELL       = "Перекупить дешёвый лот с аукциона",
    PRICE_INFO   = "Про цену",
    PATHS        = "Выбор пути",
    CROSS_CHAR   = "Между персонажами",
    FAVOR        = "Благосклонность",
    -- «Лагерь» коротко и однозначно: игра называет это место костром, и ни с
    -- одним другим видом советов спутать его нельзя.
    CAMP         = "Лагерь у костра",
}
-- ЗАПАСНЫЕ ИКОНКИ НЕ НАЗЫВАЮТ ЧУЖУЮ ПРОФЕССИЮ.
--
-- У видов «скрафтить» и «скрафтить материал» здесь стояли Trade_Tailoring
-- (иголка с нитками) и INV_Fabric_Silk_02 (рулон шёлка). Это ОБЩИЕ запасные
-- иконки для любого крафта: алхимик видел над зельем иголку, инженер над
-- бомбой - шёлк. Аддон вырос на маге-портняжнике, и это один из следов.
--
-- Что стоит вместо них: INV_Misc_QuestionMark - та самая заглушка, которой
-- клиент сам отвечает «не знаю, как это выглядит». Выбрана по двум причинам.
-- Во-первых, она честная: запасная иконка берётся ровно тогда, когда ни у
-- предмета, ни у рецепта текстуры нет, то есть мы и правда не знаем. Во-вторых,
-- она точно есть в клиенте - а иконка, которой в наборе не оказалось, рисуется
-- пустым квадратом, и это ровно та беда, про которую написано у ns.GLYPH ниже.
--
-- На экране это видно редко: карточка почти всегда берёт иконку самого предмета
-- (Api:ItemInfo().texture) или рецепта, и до запасной дело не доходит.
ns.KIND_ICON = {
    -- Запасная иконка нужна редко: карточка «надеть» почти всегда берёт иконку
    -- самого предмета, которую даёт клиент.
    EQUIP        = "Interface\\Icons\\INV_Misc_Gear_01",
    CRAFT_GEAR   = "Interface\\Icons\\INV_Misc_QuestionMark",
    CRAFT_MAT    = "Interface\\Icons\\INV_Misc_QuestionMark",
    CRAFT_SKILL  = "Interface\\Icons\\INV_Misc_Book_09",
    CRAFT_PROFIT = "Interface\\Icons\\INV_Misc_Coin_02",
    ENCHANT      = "Interface\\Icons\\Trade_Engraving",
    BUY          = "Interface\\Icons\\INV_Misc_Bag_10",
    SELL_JUNK    = "Interface\\Icons\\INV_Misc_Coin_06",
    SETUP        = "Interface\\Icons\\INV_Misc_PocketWatch_01",
    ARBITRAGE    = "Interface\\Icons\\INV_Misc_Coin_17",
    DISENCHANT   = "Interface\\Icons\\INV_Enchant_DustIllusion",
    RESELL       = "Interface\\Icons\\INV_Misc_Coin_04",
    PRICE_INFO   = "Interface\\Icons\\INV_Misc_Note_01",
    PATHS        = "Interface\\Icons\\INV_Misc_Map_01",
    CROSS_CHAR   = "Interface\\Icons\\INV_Misc_GroupLooking",
    FAVOR        = "Interface\\Icons\\INV_Misc_Note_02",
    -- Костёр. Иконка огня есть в клиенте с первого дня (это Spell_Fire_Fire,
    -- «Огненный взрыв»), а иконки самих предметов лагеря карточка берёт у
    -- предмета, когда клиент его назвал, - до запасной дело доходит редко.
    CAMP         = "Interface\\Icons\\Spell_Fire_Fire",
}

-- Filter chips over the single list.
ns.CHIP = {
    ALL     = "ALL",
    GEAR    = "GEAR",
    ENCHANT = "ENCHANT",
    CRAFT   = "CRAFT",
    GOLD    = "GOLD",
    READY   = "READY",
}
ns.CHIP_ORDER = { "ALL", "READY", "GEAR", "ENCHANT", "CRAFT", "GOLD" }
ns.CHIP_LABEL = {
    ALL = "Всё", READY = "Можно сейчас", GEAR = "Экипировка",
    ENCHANT = "Чары", CRAFT = "Крафт", GOLD = "Золото",
}
-- Which card kinds each chip lets through.
ns.CHIP_KINDS = {
    ALL     = nil, -- everything
    READY   = nil, -- special: readiness filter, not a kind filter
    GEAR    = { CRAFT_GEAR = true, EQUIP = true, BUY = true, SETUP = true,
                PATHS = true, CROSS_CHAR = true, FAVOR = true },
    ENCHANT = { ENCHANT = true, SETUP = true, DISENCHANT = true },
    -- Лагерь - под фильтром «Крафт»: предметы лагеря делаются профессиями, и
    -- ищет их игрок там же, где остальной крафт. Под «Экипировкой» их нет: это
    -- не вещь в слот, и фильтр экипировки от этого стал бы шире своего имени.
    CRAFT   = { CRAFT_GEAR = true, CRAFT_MAT = true, CRAFT_SKILL = true, CRAFT_PROFIT = true,
                SETUP = true, PATHS = true, CROSS_CHAR = true, FAVOR = true,
                CAMP = true },
    GOLD    = { CRAFT_PROFIT = true, SELL_JUNK = true, BUY = true, SETUP = true,
                ARBITRAGE = true, DISENCHANT = true, RESELL = true, PRICE_INFO = true },
}

-- Data confidence. Shown on every card so the player knows what we actually know.
ns.CONF = {
    EXACT    = "EXACT",    -- read from the game this session
    CACHED   = "CACHED",   -- from our own or another addon's cache
    ESTIMATE = "ESTIMATE", -- derived (vendor price heuristics, stat guesses)
    UNKNOWN  = "UNKNOWN",  -- we do not know; never pretend we do
}
ns.CONF_LABEL = {
    EXACT = "точно", CACHED = "из кеша", ESTIMATE = "оценка", UNKNOWN = "неизвестно",
}
ns.CONF_COLOR = {
    EXACT    = { 0.45, 0.85, 0.45 },
    CACHED   = { 0.80, 0.80, 0.45 },
    ESTIMATE = { 0.90, 0.65, 0.30 },
    UNKNOWN  = { 0.70, 0.40, 0.40 },
}
ns.CONF_SCORE = { EXACT = 1.0, CACHED = 0.85, ESTIMATE = 0.6, UNKNOWN = 0.35 }

-- Recipe difficulty as the modern API reports it -> expected skill-ups per craft.
-- Values are deliberately conservative: a guess that is too high would push
-- useless crafts to the top of the list.
ns.DIFF_SKILL_CHANCE = {
    optimal = 1.00, -- orange
    medium  = 0.75, -- yellow
    easy    = 0.25, -- green
    trivial = 0.00, -- grey
}

-- Throttling. The engine never recomputes more often than this.
ns.RECOMPUTE_MIN_INTERVAL = 1.5   -- seconds between full recomputes
ns.RECOMPUTE_DEBOUNCE     = 0.4   -- seconds to wait after the last event
-- ПОКА НИКТО НЕ СМОТРИТ - НЕ СЧИТАЕМ. Полный пересчёт - это десятки миллисекунд
-- одним куском (в живом файле игрока: в среднем 84 мс, пик 143 мс), то есть
-- рывок кадра. При закрытом окне и выключенной панели он не нужен никому, и
-- делается не чаще, чем раз в столько секунд - чтобы суточный слепок цен и
-- уведомления не протухали совсем. См. MainFrame:ShouldDefer.
-- Окно на экране: по мелочам (сумки, деньги, подгрузка имён, цены) считаем не
-- чаще раза в столько секунд. Важная причина и жест игрока этого не ждут.
ns.VISIBLE_SOFT_SECONDS = 5
ns.HIDDEN_REBUILD_SECONDS = 900
-- Как часто отложенный пересчёт проверяет, не пора ли (секунды). Сама проверка
-- - два сравнения, пересчёта в ней нет.
ns.DEFERRED_RETRY_SECONDS = 1.0
ns.PRICE_STALE_SECONDS    = 48 * 3600
-- ДВА РАЗНЫХ ВОПРОСА, И ПУТАНИЦА МЕЖДУ НИМИ СТОИЛА ВРАНЬЯ НА ЭКРАНЕ.
--   PRICE_STALE_SECONDS - когда цене перестаёт быть веры (достоверность падает
--     до «оценки»);
--   PRICE_AGE_SAY_SECONDS - когда возраст цены обязан быть НАПИСАН, даже если
--     цене ещё верим.
-- Самопроверка ругалась по второму порогу, а понижение достоверности шло по
-- первому: цена возрастом в сутки считалась свежей и возраст не называла.
ns.PRICE_AGE_SAY_SECONDS  = 24 * 3600
-- Сколько живёт наша память об ответах Auctionator. База Auctionator меняется
-- только при его сканировании аукциона; это окно - страховка на случай, когда
-- сканирование прошло мимо наших событий.
ns.AUCTION_CACHE_SECONDS  = 600
-- КАК ЧАСТО ЭТУ ПАМЯТЬ ВООБЩЕ МОЖНО ЗАБЫВАТЬ, И ПОЧЕМУ ЭТО ОТДЕЛЬНОЕ ЧИСЛО.
--
-- Забыть память цен - значит на следующем пересчёте спросить Auctionator заново
-- про каждый предмет: на настоящих данных это 367 чтений и 80-125 мс против
-- 30 мс обычного пересчёта. В живом файле игрока память забывалась 108 раз за
-- сессию (41 804 обращения к Auctionator), потому что сбрасывал её КАЖДЫЙ
-- сигнал аукциона: открытие окна, закрытие, каждая пачка результатов поиска,
-- каждое обновление своих лотов - 276 сигналов за вечер. Сканирование аукциона
-- при этом одно, а сигналов от него десятки.
--
-- Поэтому между двумя забываниями есть минимум времени. Данные от этого
-- отстают от базы Auctionator не больше чем на минуту - при том что сами цены в
-- ней старше суток у 39 предметов из 96. Отложенное забывание не теряется:
-- первый же проход после истечения окна его выполняет (см. Api:BeginPass).
ns.AUCTION_RESCAN_GUARD   = 60
ns.PRICE_FRESH_SECONDS    = 6 * 3600

-- How many cards the Now tab builds / shows.
-- 40 И 5. Предел на ветку (5 вместо 8) - вот что убирает воду: восемь
-- перепродаж подряд топили список. Общий предел при этом оставлен 40, и это
-- проверено на живом файле игрока (2026-11-21): советов генерируется 33, и при
-- пределе 20 с экрана пропали сводка по чарам (в ней слова наложенных чар),
-- пять перепродаж и пять вещей на себя - то есть обрезалось нужное, а не вода.
-- Что обрезано, если обрезано, сказано в диагностике (list-truncated).
ns.MAX_CARDS = 40
ns.MAX_CARDS_PER_KIND = 5

-- Лагерь: бонусы ещё висят дольше этого - советовать ставить лагерь заново
-- незачем (Engine:AddCampCards).
ns.CAMP_BUFF_REFRESH_SECONDS = 300

-- How long a hidden card stays hidden. Two durations for two places, and the
-- same gesture in both: two right clicks. On the small panel they put the step
-- aside for an hour, on a card in the list they put it away for a day. (The
-- panel used to hide on a single click; it no longer does.) Named here so the
-- player reads cannot drift away from the number in the code - the card used to
-- promise "на сутки" while the panel hid for an hour.
--
-- «Дальше» В ЭТОМ СПИСКЕ БОЛЬШЕ НЕТ. Она прятала совет на час, а называлась
-- «дальше», и игрок трижды остался без советов. Теперь она только листает; ни
-- один из этих сроков к ней не относится. То же с «Понятно»: левый щелчок по
-- информационному совету раньше прятал его на час, теперь не делает ничего.
ns.DISMISS_SECONDS = 86400
ns.SNOOZE_SECONDS = 3600

-- Recursion guards for the crafting planner.
ns.PLANNER_MAX_DEPTH = 6
ns.PLANNER_MAX_NODES = 4000

-- Quality ids (Enum.ItemQuality mirror; we only compare, never display).
ns.QUALITY_POOR = 0

-- ЗНАЧКИ, КОТОРЫЕ ЭТОТ КЛИЕНТ ТОЧНО РИСУЕТ.
--
-- Игрок прислал скриншот, на котором вместо значков стоят пустые квадратики: в
-- кнопке закрытия окна, в трёх подписях «В бою: …» и в подсказке панели. Это
-- значит ровно одно - в шрифте клиента таких символов нет, и он рисует
-- заглушку. Подпись из одного квадратика - это кнопка без подписи: игрок
-- спрашивал, делает ли она вообще что-нибудь.
--
-- Правило, по которому выбраны замены: шрифты ruRU-клиента покрывают то, что
-- было в кодировке Windows-1251. Оттуда можно брать «» — – • … № · ° ±, и всё
-- это на экране читается. А ✕ (U+2715), ● (U+25CF), ○ (U+25CB), → (U+2192),
-- − (U+2212, это НЕ дефис) и ≈ (U+2248) в 1251 не входят - их и рисовало
-- квадратиками.
--
-- Значки названы здесь, а не вписаны по месту, чтобы подпись кнопки и текст,
-- который про эту кнопку рассказывает, не могли разойтись: оба берут одну
-- строку. Набор запрещённых символов проверяется в Tests/test_text.lua.
ns.GLYPH = {
    -- Закрыть. Латинская X, а не «крестик» из набора символов: её рисует любой
    -- шрифт, и она привычна как кнопка закрытия.
    CLOSE      = "X",
    -- Выбранный и невыбранный вариант в списке «или то, или это». Круглые
    -- скобки с точкой внутри читаются как переключатель и целиком лежат в
    -- 1251. Подписи вида «(•) В бою: скрыть».
    RADIO_ON   = "(•) ",
    RADIO_OFF  = "( ) ",
    -- «Стало из»: было -> стало. Две ASCII-литеры вместо стрелки.
    ARROW      = "->",
    -- Минус перед числом и «примерно столько». Оба - обычные ASCII.
    MINUS      = "-",
    APPROX     = "~",
}

-- СЛОВАРЬ ПУСТОТЫ --------------------------------------------------------
--
-- У отсутствующего числа бывает ЧЕТЫРЕ разных причины, и до этого словаря все
-- четыре выглядели на экране одинаково - прочерком, нулём или словом
-- «неизвестно», выбранным на месте. Игрок не технический, и из прочерка он
-- узнаёт только одно: аддон молчит. А молчать можно по-разному, и разница эта
-- для него главная - она решает, идти ли что-то делать:
--
--   «так нельзя»  - значения не существует в принципе. У чар нет предмета,
--                   значит нет и выручки от продажи: не «я не знаю, сколько»,
--                   а «продавать нечего». Тут ждать нечего и делать нечего.
--   «не знаю»     - значение бывает, а данных у меня нет. Это уже повод
--                   что-то сделать: зайти на аукцион, открыть окно профессии.
--   «нет цены»    - частный, самый частый случай «не знаю», и он назван
--                   отдельно СЛОВАМИ, потому что прочерк в графе с деньгами
--                   читается как «ноль», то есть «бесплатно».
--   «оценка»      - число ЕСТЬ, но посчитано нами, а не увидено на рынке.
--                   Это не пустота, это пометка на числе, и она обязана
--                   стоять рядом с самим числом, а не в отдельной графе,
--                   которую никто не читает.
--
-- И пятое, не состояние, а правило: ВОЗРАСТ ЦЕНЫ ВИДЕН ВСЕГДА. Раньше возраст
-- печатался только когда переваливал за сутки, и «2з 50с» без возраста значило
-- то «увидено минуту назад», то «увидено неизвестно когда» - два разных
-- утверждения одной строкой.
--
-- Знаки выбраны из того, что шрифты ruRU-клиента точно рисуют (см. ns.GLYPH
-- выше): прочерк «—» и вопрос «?» входили в Windows-1251 и видны оба.
ns.VOID = {
    IMPOSSIBLE = "IMPOSSIBLE",
    UNKNOWN    = "UNKNOWN",
    NO_PRICE   = "NO_PRICE",
}
ns.VOID_TEXT = {
    IMPOSSIBLE = "—",
    UNKNOWN    = "?",
    NO_PRICE   = "нет цены",
}
-- Те же четыре состояния словами - для подсказки под курсором и для чата, где
-- одного знака мало.
ns.VOID_WHY = {
    IMPOSSIBLE = "такого значения не бывает",
    UNKNOWN    = "данных у меня нет",
    NO_PRICE   = "цены нет ни в одном источнике",
}

-- Пометка на числе, которое мы посчитали сами.
ns.ESTIMATE_MARK = ns.GLYPH.APPROX
ns.ESTIMATE_WORD = "оценка"

-- Возраст: три разных ответа, и ни один не молчание.
ns.AGE_UNKNOWN  = "возраст неизвестен"
ns.AGE_TIMELESS = "не стареет"
ns.AGE_JUST_NOW = "только что"

-- ЧУЖАЯ КНИГА ЗАКУПОК ----------------------------------------------------
--
-- MastercraftDB.costs - книга закупок другого аддона, и до появления своей
-- (Logic/Ledger.lua) она была ЕДИНСТВЕННЫМ источником «сколько это стоило».
-- Держать на ней себестоимость нельзя, и причин три, каждая сама по себе
-- достаточная:
--
--   1. Схема недокументированная. Мы разобрали её по содержимому файла игрока:
--      costs[реалм][itemID] = список лотов { c = медь, q = штук, t = время,
--      m = «сделано мной» }. Никто не обещал, что завтра она будет такой же.
--   2. Аддон обновляется раз в пару дней. Сменят формат - у нас молча
--      отвалятся все цены, и узнаем мы об этом от игрока.
--   3. У Mastercraft есть LICENSE.txt с «all rights reserved», и запрет там
--      распространяется и на данные. Строить свою работу на чужих данных,
--      которые нам не разрешали брать, - плохая опора независимо от техники.
--
-- Поэтому: своя книга ВСЕГДА впереди, чужая работает запасным путём только
-- пока по этому предмету своих данных нет, и на экране она называется чужой.
ns.FOREIGN_BOOK = {
    name = "книга закупок аддона Mastercraft",
    short = "чужая книга",
    why = "схема недокументированная, аддон обновляется раз в пару дней, и"
        .. " его лицензия не разрешает брать данные — верить этому меньше,"
        .. " чем своим записям",
    plan = "запасной путь на первое время: как только своя книга закроет"
        .. " предмет, чужую по нему больше не спрашиваю. Когда своих записей"
        .. " станет хватать на всё, чужую уберу совсем",
    label = "наблюдение другого аддона",
}

return ns
