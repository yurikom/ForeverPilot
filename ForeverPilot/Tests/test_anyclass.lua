-- ForeverPilot / Tests/test_anyclass.lua
--
-- АДДОН НЕ ЗАТОЧЕН ПОД МАГА-ПОРТНЯЖНИКА.
--
-- У игрока два персонажа: маг-аркан с портняжкой и чарами, и чернокнижник-
-- демонолог с алхимией, инженерным делом и кулинарией. Аддон вырос на первом, и
-- всё, что про второго, он либо не умел, либо отвечал как про мага. Каждый
-- набор здесь воспроизводит одну такую ошибку на данных того же вида, что
-- пришли из игры.
--
-- Что проверяется:
--   1. профиль весов берётся у КЛАССА и спека, а не остаётся магическим;
--   2. любая профессия работает так же, как портняжка;
--   3. расходник (зелье, бомба, патрон) оценивается партией, а не как шмотка;
--   4. потолки навыка разведены по персонажам: кулинария мага не съедает
--      кулинарию чернокнижника;
--   5. профессии другого персонажа - настоящие данные, а не «профессий нет».
local H = ...

return function()

local function findCard(cards, key)
    for _, c in ipairs(cards) do
        if c.key == key then return c end
    end
    return nil
end

local function cardsByKind(cards, kind)
    local out = {}
    for _, c in ipairs(cards) do
        if c.kind == kind then out[#out + 1] = c end
    end
    return out
end

-- =====================================================================
-- 1. ПРОФИЛЬ ВЕСОВ: КЛАСС, А НЕ МАГИЯ ПО УМОЛЧАНИЮ
-- =====================================================================
--
-- Все три спека чернокнижника - тень с огнём рядом; это написано в самом
-- SPEC_HINTS. А CLASS_DEFAULT отдавал WARLOCK школо-слепой CASTER_DPS, в
-- котором ВСЕ шесть школ стоят 0.80 - включая тайную магию, лёд и силы природы,
-- которых чернокнижник не кастует вообще. Десятый уровень без талантов - это
-- ровно то состояние, в котором спек не читается, и именно в нём игрок играет.

H.suite("Класс решает профиль: чернокнижник без спека - не школо-слепой кастер")
do
    local SW = H.load().ns.StatWeights
    local key = SW.CLASS_DEFAULT.WARLOCK
    H.ok(key ~= "CASTER_DPS",
        "у чернокнижника без спека профиль не школо-слепой",
        "получили " .. tostring(key))

    local set = SW:Set(key)
    H.eq(set.SPELLDMG_SHADOW, 1.50, "тень весит как своя школа")
    H.eq(set.SPELLDMG_ARCANE, 0.00, "тайная магия чернокнижнику не нужна")
    H.eq(set.SPELLDMG_FROST, 0.00, "лёд чернокнижнику не нужен")
    H.eq(set.SPELLDMG_NATURE, 0.00, "силы природы чернокнижнику не нужны")
end

H.suite("Демонолог - это тень, а не тайная магия")
do
    local SW = H.load().ns.StatWeights
    local set, conf, how = SW:Resolve("WARLOCK", "Демонология")
    H.eq(set, "CASTER_SHADOW", "«Демонология» -> тень")
    H.eq(how, "spec", "школа взята из спека")

    -- И тот же вопрос у мага не поехал: его спеки по-прежнему свои.
    H.eq(SW:Resolve("MAGE", "Тайная магия"), "CASTER_ARCANE", "маг-аркан не тронут")
    H.eq(SW:Resolve("MAGE", nil), "CASTER_DPS", "маг без спека по-прежнему школо-слепой")
end

-- НЕЗНАКОМЫЙ КЛАСС НЕ ПОЛУЧАЕТ ПРОФИЛЬ МАГА.
--
-- Последним ответом SW:Resolve был CASTER_DPS с пометкой CONF.UNKNOWN. Пометка
-- честная, а числа - кастерские: класс, которого нет в CLASS_DEFAULT, получал
-- прирост экипировки, посчитанный по чужим весам, и отличить такой совет от
-- настоящего игроку нечем. Это та же ошибка, что «профессий нет» про
-- персонажа, про которого просто ничего не знали.

H.suite("Незнакомый класс: профиля нет вовсе, и сказано почему")
do
    local env = H.load()
    local SW = env.ns.StatWeights

    local key, conf, how = SW:Resolve("SPELLBLADE", nil)
    H.eq(key, nil, "профиля для незнакомого класса нет")
    H.eq(conf, env.ns.CONF.UNKNOWN, "и это «не знаю», а не оценка")
    H.eq(how, "unknown-class", "и названо, почему именно")
    local reason = SW:NoProfileReason(how, "SPELLBLADE")
    H.ok(reason and env.ns.Util.contains(reason, "незнаком"),
        "причина словами: " .. tostring(reason))

    -- Класса ещё не назвали - это ДРУГОЕ незнание: оно пройдёт само.
    local key2, _, how2 = SW:Resolve(nil, nil)
    H.eq(key2, nil, "без класса профиля тоже нет")
    H.eq(how2, "no-class", "но причина другая: класс ещё не назвали")
    H.ok(SW:NoProfileReason(how2) ~= SW:NoProfileReason("unknown-class", "X"),
        "и формулировки разные")
    H.eq(SW:NoProfileReason("class"), nil, "когда профиль есть, объяснять нечего")

    -- И все тринадцать классов игры профиль по-прежнему получают: проверка,
    -- которая просто всё запрещает, зелёная и бесполезная.
    local missing = {}
    for _, cls in ipairs({ "MAGE", "WARLOCK", "PRIEST", "DRUID", "SHAMAN",
                           "PALADIN", "WARRIOR", "ROGUE", "HUNTER",
                           "DEATHKNIGHT", "MONK", "DEMONHUNTER", "EVOKER" }) do
        if SW:Resolve(cls, nil) == nil then missing[#missing + 1] = cls end
    end
    H.eq(#missing, 0, "у всех известных классов профиль есть"
        .. ((#missing > 0) and ("  <- " .. table.concat(missing, ", ")) or ""))
end

H.suite("Незнакомый класс: баллов нет, а не ноль, и советы по вещам молчат")
do
    local env = H.load()
    local ns = env.ns
    local SW = ns.StatWeights
    local S = ns.STAT

    -- Балл без весов - это «не знаю», а не «ничего не даёт». Ноль был бы
    -- утверждением, которое нечем подтвердить.
    H.eq(SW:Score({ [S.INT] = 10 }, nil), nil, "без весов балла нет")
    H.ok(SW:Score({ [S.INT] = 10 }, SW:Set("CASTER_ARCANE")) > 0,
        "с весами — есть")

    env.player.classFile = "SPELLBLADE"
    env.player.className = "Клинок чар"
    local snap = ns.CharacterScanner:Scan()
    H.eq(snap.weights, nil, "в снимке весов нет")
    H.eq(snap.weightSetKey, nil, "и набор не выбран")
    H.eq(snap.weightSource, "unknown-class", "и записано, почему")

    -- Ни одна ветка по вещам не выдаёт чисел, посчитанных чужими весами.
    H.eq(#ns.GearAdvisor:Upgrades(snap), 0, "улучшений не предложено")
    H.eq(#ns.GearAdvisor:EquipSwaps(snap), 0, "«надень то, что есть» молчит")
    H.eq(ns.GearAdvisor:SlotItem("HEAD", snap), nil, "слот не оценён")
    H.eq(ns.GearAdvisor:Compare(4500, 4500, nil), nil, "сравнение без весов не делается")

    H.eq(#ns.EnchantAdvisor:Suggestions(snap), 0, "и формулы чар не подбираются")

    -- И весь список советов строится без падения: карточки по вещам просто не
    -- появляются, а всё остальное работает.
    local cards = H.build(env)
    H.ok(cards ~= nil, "список советов собран")
    local gear = 0
    for _, c in ipairs(cards or {}) do
        if c.benefitKind == "power" and c.benefitValue then gear = gear + 1 end
    end
    H.eq(gear, 0, "и ни одной карточки с приростом по весам в нём нет")

    -- А ВЕТКИ НЕ МОЛЧАТ МОЛЧА: причина названа словами, и в ней нет ни слова
    -- про нехватку чего-то у игрока - это моя слепота, а не его.
    local notes = ns.ActionEngine.branchNote or {}
    for _, branch in ipairs({ "gear", "equip", "enchant" }) do
        local note = notes[branch]
        H.ok(type(note) == "string" and ns.Util.contains(note, "незнаком"),
            "ветка «" .. branch .. "» объясняет своё молчание: " .. tostring(note))
    end
end

-- ШКОЛА ПО НАДЕТЫМ ВЕЩАМ - ТОЛЬКО ИЗ ШКОЛ СВОЕГО КЛАССА.
--
-- Вывод школы по вещам был классо-слепым: чернокнижник, надевший кинжал с
-- тайным уроном (а на низких уровнях надевают что дали), получал профиль
-- CASTER_ARCANE - то есть веса мага. Вещь - это улика о вещи, а не о том, какие
-- заклинания персонаж умеет бросать.
H.suite("Школа по вещам ограничена школами класса")
do
    local SW = H.load().ns.StatWeights
    local castable = SW:SchoolsOfClass("WARLOCK")
    H.ok(castable and castable.SHADOW, "чернокнижник кастует тень")
    H.ok(castable and castable.FIRE, "чернокнижник кастует огонь")
    H.ok(not (castable and castable.ARCANE), "тайную магию не кастует")

    local snap = {
        equipped = { MAINHAND = { itemID = 777 } },
        classFile = "WARLOCK",
    }
    local school = SW:InferSchoolFromGear(snap, "WARLOCK")
    H.ok(school ~= "ARCANE",
        "тайный урон на вещи не делает чернокнижника магом",
        "получили " .. tostring(school))
end

H.suite("Школа по вещам: у мага тайный урон по-прежнему читается")
do
    local env = H.load()
    local ns = env.ns
    H.item(env, 7777, { name = "Жемчужный венец", equipLoc = "INVTYPE_HEAD",
        classID = 4, subclassID = 1, reqLevel = 20 })
    env.foreignItemStats[7777] = { sta = 10, armor = 35, spArcane = 11 }
    H.itemsChanged(env)
    env.equipped.HEAD = { itemID = 7777 }
    local snap = H.rescan(env)
    local school = ns.StatWeights:InferSchoolFromGear(snap, "MAGE")
    H.eq(school, "ARCANE", "маг в жемчужном венце - аркан")
end

-- =====================================================================
-- 2. ЛЮБАЯ ПРОФЕССИЯ РАБОТАЕТ КАК ПОРТНЯЖКА
-- =====================================================================

H.suite("Алхимия: рецепты читаются, себестоимость и прибыль считаются")
do
    local env = H.load()
    local ns = env.ns
    env.player = { name = "Гендольф", surname = "Белыйй", level = 10,
                   classFile = "WARLOCK", className = "Чернокнижник",
                   raceName = "Орк", factionFile = "Horde",
                   guid = "Player-1-2", realm = "Test" }
    -- Малое лечебное зелье: стопка 5, не экипировка.
    H.item(env, 118, { name = "Слабое лечебное зелье", sellPrice = 25,
        stackCount = 5, classID = 0, subclassID = 1 })
    H.item(env, 2447, { name = "Мироцвет", sellPrice = 1, stackCount = 20,
        classID = 7, subclassID = 9 })
    H.item(env, 3371, { name = "Пустой флакон", sellPrice = 1, stackCount = 20,
        classID = 7, subclassID = 12 })
    env.prices[118] = 400
    env.prices[2447] = 50
    env.prices[3371] = 20
    env.bags[2447] = 20
    env.bags[3371] = 20

    H.profession(env, "Алхимия", 150, 150, {
        H.recipe { id = 2330, output = 118, outputQty = 1, learned = true,
                   reagents = { { itemID = 2447, qty = 1 }, { itemID = 3371, qty = 1 } },
                   name = "Слабое лечебное зелье", diff = "trivial" },
    })

    local cards, meta, snap = H.build(env)
    H.eq(#snap.professions, 1, "алхимия в снимке")
    H.ok(snap.professions[1].crafting, "алхимия - крафтовая профессия")

    local unit = ns.CraftingPlanner:RecipeUnitCost(ns.RecipeBook:Get(2330))
    H.eq(unit, 70, "себестоимость зелья - сумма материалов")

    local margin = ns.CraftingPlanner:Margin(ns.RecipeBook:Get(2330))
    H.ok(margin and margin > 0, "прибыль на зелье посчиталась",
        "получили " .. tostring(margin))

    local profit = cardsByKind(cards, ns.KIND.CRAFT_PROFIT)
    H.ok(#profit > 0, "ветка «на продажу» видит алхимию",
        "карточек: " .. #profit)
end

H.suite("Инженерное дело и кулинария - такие же профессии")
do
    local env = H.load()
    local ns = env.ns
    env.player = { name = "Гендольф", surname = "Белыйй", level = 10,
                   classFile = "WARLOCK", className = "Чернокнижник",
                   raceName = "Орк", factionFile = "Horde",
                   guid = "Player-1-2", realm = "Test" }
    H.item(env, 4360, { name = "Грубая динамитная шашка", sellPrice = 50,
        stackCount = 10, classID = 7, subclassID = 1 })
    H.item(env, 2835, { name = "Грубый камень", sellPrice = 1, stackCount = 20,
        classID = 7, subclassID = 7 })
    H.item(env, 2589, { name = "Полотно", sellPrice = 2, stackCount = 20,
        classID = 7, subclassID = 5 })
    H.item(env, 2672, { name = "Жёсткое мясо", sellPrice = 2, stackCount = 20,
        classID = 7, subclassID = 8 })
    H.item(env, 2679, { name = "Мясо с приправами", sellPrice = 8,
        stackCount = 20, classID = 0, subclassID = 5 })
    env.prices[4360] = 300
    env.prices[2835] = 30
    env.prices[2589] = 40
    env.prices[2672] = 20
    env.prices[2679] = 150
    env.bags[2835] = 20
    env.bags[2589] = 20
    env.bags[2672] = 20

    H.profession(env, "Инженерное дело", 150, 150, {
        H.recipe { id = 3919, output = 4360, outputQty = 1, learned = true,
                   reagents = { { itemID = 2835, qty = 1 }, { itemID = 2589, qty = 1 } },
                   name = "Грубая динамитная шашка", diff = "optimal" },
    })
    H.profession(env, "Кулинария", 40, 150, {
        H.recipe { id = 2538, output = 2679, outputQty = 1, learned = true,
                   reagents = { { itemID = 2672, qty = 1 } },
                   name = "Мясо с приправами", diff = "optimal" },
    })

    local cards, meta, snap = H.build(env)
    H.eq(#ns.CharacterScanner:CraftingProfessions(), 2,
        "обе профессии считаются крафтовыми")

    local bomb = ns.CraftingPlanner:Margin(ns.RecipeBook:Get(3919))
    H.ok(bomb and bomb > 0, "прибыль на бомбе посчиталась",
        "получили " .. tostring(bomb))
    local food = ns.CraftingPlanner:Margin(ns.RecipeBook:Get(2538))
    H.ok(food and food > 0, "прибыль на еде посчиталась",
        "получили " .. tostring(food))

    -- И крафт на навык: кулинария ещё не на пределе, значит ветка обязана жить.
    local skill = cardsByKind(cards, ns.KIND.CRAFT_SKILL)
    H.ok(#skill > 0, "крафт на навык работает на кулинарии", "карточек: " .. #skill)
end

-- СВЕРКА С ВНЕШНИМ СПРАВОЧНИКОМ ШЛА ПО ДВУМ ПРОФЕССИЯМ, ВПИСАННЫМ В КОД.
--
-- Logic/SourceCheck.lua перебирал список { "Tailoring", "Enchanting" }: у
-- алхимика сверка не состоялась ни разу, и аддон об этом даже не сообщал -
-- `compared` был ноль, а причина не называлась.
H.suite("Сверка рецептов идёт по профессиям персонажа, а не по вписанному списку")
do
    local env = H.load()
    local ns = env.ns
    local names = ns.SourceCheck:ProfessionsToCompare()
    H.ok(type(names) == "table", "список профессий для сверки есть")

    env.professions[#env.professions + 1] = {
        name = "Алхимия", skill = 150, max = 150, skillTrusted = true,
    }
    H.rescan(env)
    local after = ns.SourceCheck:ProfessionsToCompare()
    local found = false
    for _, n in ipairs(after) do
        if n == "Alchemy" or n == "Алхимия" then found = true end
    end
    H.ok(found, "алхимия попала в сверку", table.concat(after, ", "))
end

-- =====================================================================
-- 3. РАСХОДНИК - НЕ ШМОТКА: ЭКОНОМИКА ПАРТИИ
-- =====================================================================
--
-- Зелья, бомбы и патроны продаются постоянно и малыми партиями; мантия
-- продаётся один раз. Ветка «на продажу» считала и то и другое по марже за один
-- крафт, и расходник с маржой 3 серебра всегда проигрывал шмотке с маржой 4
-- золотых - при том что зелий игрок продаёт двадцать штук в день, а мантию
-- может не продать вовсе.
H.suite("Расходник узнаётся по данным клиента, а не по списку предметов")
do
    local env = H.load()
    local ns = env.ns
    H.item(env, 118, { name = "Слабое лечебное зелье", stackCount = 5,
        classID = 0, subclassID = 1, sellPrice = 25 })
    H.item(env, 2569, { name = "Льняные сапоги", equipLoc = "INVTYPE_FEET",
        stackCount = 1, classID = 4, subclassID = 1, sellPrice = 300 })
    H.item(env, 2589, { name = "Полотно", stackCount = 20, classID = 7,
        subclassID = 5, sellPrice = 2 })

    H.eq(ns.CraftingPlanner:SaleShape(118), "BATCH", "зелье продаётся партиями")
    H.eq(ns.CraftingPlanner:SaleShape(2589), "BATCH", "материал продаётся партиями")
    H.eq(ns.CraftingPlanner:SaleShape(2569), "ONEOFF", "сапоги продаются разово")
    -- Предмета нет в кеше клиента - значит не знаем, а не «шмотка».
    H.eq(ns.CraftingPlanner:SaleShape(999999), nil,
        "про незнакомый предмет форма продажи не выдумывается")
end

-- ОРУЖИЕ, КОТОРОЕ КЛИЕНТ НЕ ЗАКЕШИРОВАЛ, - ВСЁ РАВНО НЕ РАСХОДНИК.
--
-- Это не выдуманный случай: клиент забывает предметы, которые игрок видел в
-- банке, и Diag для этого держит счётчик itemInfo.noEquipLoc. У такого предмета
-- equipLoc пустой, и правило «стопка больше одной И не надевается» приняло бы
-- за расходник хоть мантию. Тип предмета в этом случае берётся из внешней базы
-- числом - ровно тем же вторым путём, которым ходит GearAdvisor:749.
H.suite("Надеваемое без equipLoc узнаётся по внешней базе, а не считается расходником")
do
    local env = H.load()
    local ns = env.ns
    -- Лунная винтовка: клиент про неё молчит (equipLoc нет), стопка выглядит
    -- большой - именно то состояние, в котором она читалась расходником.
    H.item(env, 2825, { name = "Лунная винтовка", stackCount = 20,
        equipLoc = nil, sellPrice = 1000 })
    -- А во внешней базе у неё есть числовой тип: 15 - дальний бой. Вместе с
    -- типом там лежат и характеристики - так и в настоящей базе, одной записью.
    env.itemDBMirror = false
    env.foreignItemStats[2825] = { dps = 12 }
    env.foreignItemRecords[2825] = { id = 2825, inv = 15, ilvl = 30, req = 25,
        quality = 2, class = 2, subclass = 3, stats = { dps = 12 } }
    H.itemsChanged(env)

    H.eq(ns.SlotMap:FromInvNumber(15), "RANGED", "15 - это дальний бой")
    H.eq(ns.CraftingPlanner:SaleShape(2825), "ONEOFF",
        "винтовка продаётся разово, хоть клиент про неё и молчит")

    -- А настоящий расходник, которого тоже нет в клиенте, остаётся партией:
    -- у него во внешней базе числовой тип нулевой или отсутствует.
    H.item(env, 3928, { name = "Сильное лечебное зелье", stackCount = 5,
        equipLoc = nil, sellPrice = 50 })
    env.foreignItemStats[3928] = { health = 1 }
    env.foreignItemRecords[3928] = { id = 3928, inv = 0, ilvl = 35, req = 0,
        quality = 1, class = 0, subclass = 1, stats = { health = 1 } }
    H.itemsChanged(env)
    H.eq(ns.CraftingPlanner:SaleShape(3928), "BATCH",
        "зелье осталось расходником")
end

H.suite("Расходник оценивается партией, которую можно сделать и продать")
do
    local env = H.load()
    local ns = env.ns
    H.item(env, 118, { name = "Слабое лечебное зелье", stackCount = 5,
        classID = 0, subclassID = 1, sellPrice = 25 })
    H.item(env, 2447, { name = "Мироцвет", stackCount = 20, classID = 7,
        subclassID = 9, sellPrice = 1 })
    env.prices[118] = 400
    env.prices[2447] = 50
    env.bags[2447] = 40

    H.profession(env, "Алхимия", 150, 150, {
        H.recipe { id = 2330, output = 118, outputQty = 1, learned = true,
                   reagents = { { itemID = 2447, qty = 1 } },
                   name = "Слабое лечебное зелье", diff = "trivial" },
    })
    H.rescan(env)

    local recipe = ns.RecipeBook:Get(2330)
    local unitMargin = ns.CraftingPlanner:Margin(recipe)

    -- МАТЕРИАЛА ХВАТАЕТ НА БОЛЬШЕ, ЧЕМ ОДНУ СТОПКУ. В зачёт идёт стопка: это
    -- то, что игрок выставляет одним лотом, и дальше начинается не расчёт, а
    -- догадка про спрос. Мироцвета 40, зелий можно сделать 40, стопка - 5.
    local batch = ns.CraftingPlanner:BatchProfit(recipe)
    H.ok(batch, "у расходника есть прибыль партии")
    H.eq(batch.shape, "BATCH", "форма продажи - партия")
    H.eq(batch.canMake, 40, "сделать можно 40 - столько материала")
    H.eq(batch.runs, 5, "в зачёт идёт стопка, а не всё, что можно сделать")
    H.eq(batch.limitedBy, "stack", "ограничила стопка, а не материал")
    H.near(batch.margin, unitMargin * 5, 1, "прибыль партии - маржа на стопку")
    H.ok(batch.margin > unitMargin, "партия стоит больше одной штуки")

    -- А КОГДА МАТЕРИАЛА МЕНЬШЕ СТОПКИ, ограничивает материал, и число в зачёте
    -- настоящее: обещать стопку, которой не из чего сделать, нельзя.
    env.bags[2447] = 3
    H.rescan(env)
    local small = ns.CraftingPlanner:BatchProfit(recipe)
    H.eq(small.runs, 3, "хватает на три - значит три")
    H.eq(small.limitedBy, "materials", "ограничил материал")
    H.near(small.margin, unitMargin * 3, 1, "и прибыль посчитана по трём")

    -- Материала нет вовсе: партии нет, но рецепт не перестал быть выгодным.
    env.bags[2447] = nil
    H.rescan(env)
    local none = ns.CraftingPlanner:BatchProfit(recipe)
    H.eq(none.runs, 1, "без материала в зачёте один крафт, а не ноль")
    H.near(none.margin, unitMargin, 1, "и прибыль за этот один крафт")
end

H.suite("Шмотка партией не считается: её продают по одной")
do
    local env = H.load()
    local ns = env.ns
    H.item(env, 2569, { name = "Льняные сапоги", equipLoc = "INVTYPE_FEET",
        stackCount = 1, classID = 4, subclassID = 1, reqLevel = 10,
        sellPrice = 300 })
    H.item(env, 2589, { name = "Полотно", stackCount = 20, classID = 7,
        subclassID = 5, sellPrice = 2 })
    env.prices[2569] = 20000
    env.prices[2589] = 40
    env.bags[2589] = 40

    H.profession(env, "Портняжное дело", 225, 225, {
        H.recipe { id = 2386, output = 2569, outputQty = 1, learned = true,
                   reagents = { { itemID = 2589, qty = 1 } },
                   name = "Льняные сапоги", diff = "trivial" },
    })
    H.rescan(env)

    local recipe = ns.RecipeBook:Get(2386)
    local batch = ns.CraftingPlanner:BatchProfit(recipe)
    H.eq(batch.shape, "ONEOFF", "сапоги - разовая продажа")
    H.eq(batch.runs, 1, "в зачёт идёт одна пара, а не сорок")
    local unitMargin = ns.CraftingPlanner:Margin(recipe)
    H.near(batch.margin, unitMargin, 1, "прибыль разовой вещи - маржа одной штуки")
end

H.suite("Карточка расходника говорит про партию словами")
do
    local env = H.load()
    local ns = env.ns
    H.item(env, 118, { name = "Слабое лечебное зелье", stackCount = 5,
        classID = 0, subclassID = 1, sellPrice = 25 })
    H.item(env, 2447, { name = "Мироцвет", stackCount = 20, classID = 7,
        subclassID = 9, sellPrice = 1 })
    env.prices[118] = 400
    env.prices[2447] = 50
    env.bags[2447] = 40
    env.money = 50000

    H.profession(env, "Алхимия", 150, 150, {
        H.recipe { id = 2330, output = 118, outputQty = 1, learned = true,
                   reagents = { { itemID = 2447, qty = 1 } },
                   name = "Слабое лечебное зелье", diff = "trivial" },
    })

    local cards = H.build(env)
    local card = findCard(cards, "profit:2330")
    H.ok(card, "карточка «на продажу» для зелья есть")
    if card then
        H.ok(card.saleShape == "BATCH", "карточка знает, что это расходник")
        H.ok(tostring(card.why):find("парти", 1, true)
             or tostring(card.why):find("продают", 1, true),
            "текст объясняет, что расходник продаётся не разово",
            tostring(card.why))
    end
end

-- =====================================================================
-- 4. ПОТОЛКИ НАВЫКА - ПО ПЕРСОНАЖУ
-- =====================================================================
--
-- `skillCaps` лежал в аккаунтной сохранёнке и был заведён по ИМЕНИ профессии. У
-- мага кулинария 225, у чернокнижника она качается с единицы - и его подъём
-- потолка 75 -> 150 попадал в ветку «клиент ответил хуже, чем раньше» и
-- пропадал молча. В живом файле игрока там и лежит: Кулинария = 225 (мага),
-- Алхимия = 75, Инженерное дело = 75.

H.suite("Потолок навыка объявлен в дефолтах")
do
    local ns = H.load().ns
    H.ok(type(ns.Config.DEFAULTS.skillCaps) == "table",
        "skillCaps есть в DEFAULTS, а не заводится на месте")
end

H.suite("Кулинария мага не съедает кулинарию чернокнижника")
do
    local env = H.load()
    local ns = env.ns

    -- Маг: кулинария на пределе 225. Первая встреча - запомнить и молчать.
    env.player = { name = "Гендольф", surname = "Серыйй", level = 28,
                   classFile = "MAGE", className = "Маг", raceName = "Тролль",
                   factionFile = "Horde", guid = "Player-1-1", realm = "Test" }
    env.professions = { { name = "Кулинария", skill = 225, max = 225,
                          skillTrusted = true } }
    H.rescan(env)
    H.eq(ns.Notifier:CheckSkillCap("тест"), 0, "первая встреча молчит")

    -- Тот же аккаунт, другой персонаж: кулинария 1/75.
    env.said = nil
    env.player = { name = "Гендольф", surname = "Белыйй", level = 10,
                   classFile = "WARLOCK", className = "Чернокнижник",
                   raceName = "Орк", factionFile = "Horde",
                   guid = "Player-1-2", realm = "Test" }
    env.professions = { { name = "Кулинария", skill = 1, max = 75,
                          skillTrusted = true } }
    H.rescan(env)
    H.eq(ns.Notifier:CheckSkillCap("тест"), 0,
        "у второго персонажа это тоже первая встреча, а не падение потолка")

    -- А теперь его собственный потолок вырос. Это и есть главная новость.
    env.professions = { { name = "Кулинария", skill = 60, max = 150,
                          skillTrusted = true } }
    H.rescan(env)
    H.eq(ns.Notifier:CheckSkillCap("тест"), 1,
        "подъём 75 -> 150 у чернокнижника объявлен")
    local said = table.concat(env.said or {}, " | ")
    H.ok(said:find("75", 1, true) and said:find("150", 1, true),
        "в сообщении его собственные числа", said)

    -- И мага это не тронуло: его 225 на месте.
    env.said = nil
    env.player.surname = "Серыйй"
    env.player.guid = "Player-1-1"
    env.player.classFile = "MAGE"
    env.professions = { { name = "Кулинария", skill = 225, max = 225,
                          skillTrusted = true } }
    H.rescan(env)
    H.eq(ns.Notifier:CheckSkillCap("тест"), 0,
        "у мага потолок не «вырос» с 150 до 225 - он там и был")
end

-- =====================================================================
-- 5. ПРОФЕССИИ ДРУГОГО ПЕРСОНАЖА - НАСТОЯЩИЕ ДАННЫЕ
-- =====================================================================
--
-- Syndicator отдаёт сумки альта, но не его профессии; поэтому ветка писала «у
-- него профессий нет» - и это было правдой, пока у чернокнижника их не было.
-- Теперь профессии есть, а фраза осталась бы. Аддон обязан помнить то, что сам
-- видел: своя запись о каждом персонаже, по которому он хоть раз считал.

H.suite("Реестр персонажей помнит профессии того, кем играли")
do
    local env = H.load()
    local ns = env.ns
    env.player = { name = "Гендольф", surname = "Белыйй", level = 10,
                   classFile = "WARLOCK", className = "Чернокнижник",
                   raceName = "Орк", factionFile = "Horde",
                   guid = "Player-1-2", realm = "Test" }
    env.professions = {
        { name = "Алхимия", skill = 150, max = 150, skillTrusted = true },
        { name = "Инженерное дело", skill = 150, max = 150, skillTrusted = true },
        { name = "Кулинария", skill = 40, max = 150, skillTrusted = true },
    }
    H.rescan(env)

    local roster = ns.Roster:All()
    H.ok(roster and next(roster), "в реестре кто-то есть")
    local me = ns.Roster:Find("Гендольф Белыйй")
    H.ok(me, "чернокнижник найден по полному имени")
    if me then
        H.eq(me.classFile, "WARLOCK", "класс записан")
        H.eq(me.level, 10, "уровень записан")
        H.eq(#me.professions, 3, "все три профессии записаны")
        H.eq(ns.Roster:SkillOf("Гендольф Белыйй", "Алхимия"), 150,
            "навык алхимии виден из реестра")
    end
end

H.suite("Карточка «профессий нет» исчезает, когда профессии появились")
do
    local env = H.load()
    local ns = env.ns

    -- Сначала чернокнижник: пусть аддон запомнит его профессии.
    env.player = { name = "Гендольф", surname = "Белыйй", level = 10,
                   classFile = "WARLOCK", className = "Чернокнижник",
                   raceName = "Орк", factionFile = "Horde",
                   guid = "Player-1-2", realm = "Test" }
    env.professions = {
        { name = "Алхимия", skill = 150, max = 150, skillTrusted = true },
    }
    H.rescan(env)

    -- Теперь играем магом, а чернокнижник - «другой персонаж» через Syndicator.
    env.player = { name = "Гендольф", surname = "Серыйй", level = 28,
                   classFile = "MAGE", className = "Маг", raceName = "Тролль",
                   factionFile = "Horde", guid = "Player-1-1", realm = "Test" }
    env.professions = {
        { name = "Портняжное дело", skill = 225, max = 225, skillTrusted = true },
    }
    env.syndicator = true
    env.altNames = { "Гендольф Белыйй-PvP", "Гендольф Серыйй-PvP" }
    env.altData = {
        ["Гендольф Белыйй-PvP"] = {
            details = { character = "Гендольф Белыйй", class = 9,
                        className = "WARLOCK", realm = "PvP" },
            money = 467, bags = { { { itemID = 2589, itemCount = 10 } } },
        },
        ["Гендольф Серыйй-PvP"] = {
            details = { character = "Гендольф Серыйй", class = 8,
                        className = "MAGE", realm = "PvP" },
            money = 4676, bags = { {} },
        },
    }
    local snap = H.rescan(env)

    local chars = ns.CrossCharacter:Characters(snap)
    H.ok(chars, "список персонажей собрался")
    local warlock
    for _, c in ipairs(chars or {}) do
        if c.name == "Гендольф Белыйй" then warlock = c end
    end
    H.ok(warlock, "чернокнижник есть в списке")
    if warlock then
        H.ok(warlock.professions and #warlock.professions > 0,
            "профессии чернокнижника видны с мага",
            "получили " .. tostring(warlock.professions and #warlock.professions))
        H.eq(ns.CrossCharacter:ProfessionCount(warlock), 1,
            "одна профессия, и это число, а не предположение")
    end

    -- И самое главное: фразы «профессий нет» в карточках больше нет.
    local cards = H.build(env)
    for _, c in ipairs(cards) do
        H.ok(not tostring(c.why or ""):find("профессий нет", 1, true),
            "ни одна карточка не утверждает, что профессий нет",
            tostring(c.key) .. ": " .. tostring(c.why))
    end
end

-- ЧУЖОЙ КЕШ - ЗАПАСНОЙ ПУТЬ, И НАЗЫВАЕТСЯ ЧУЖИМ.
--
-- Своя запись появляется только после того, как этим персонажем сыграли при
-- установленном аддоне. До тех пор про его профессии сказать нечего - а в кеше
-- Mastercraft они есть, и аддон этот кеш уже читает (уровень и класс альта
-- берутся оттуда). Правило то же, что у книги закупок в Core/Const.lua: своё
-- впереди, чужое работает запасным путём и на экране называется чужим.
H.suite("Профессии альта из чужого кеша: запасной путь с пометкой")
do
    local env = H.load()
    local ns = env.ns
    env.foreignDB = {
        chars = {
            ["Player-1-2"] = {
                name = "Гендольф", surname = "Белыйй", level = 10,
                classFile = "WARLOCK", class = "Чернокнижник",
                professions = {
                    { name = "Alchemy", skill = 150, max = 150 },
                    { name = "Engineering", skill = 150, max = 150 },
                },
            },
        },
    }
    local profs, conf, age, source = ns.Roster:Professions("Гендольф Белыйй")
    H.ok(profs and #profs == 2, "профессии нашлись в чужом кеше",
        "получили " .. tostring(profs and #profs))
    H.eq(source, "foreign", "и источник назван чужим")
    H.ok(conf == ns.CONF.CACHED or conf == ns.CONF.ESTIMATE,
        "достоверность не выше «из кеша»", tostring(conf))

    -- А СВОЯ ЗАПИСЬ ВСЕГДА ВПЕРЕДИ. Сыграли этим персонажем - читается она.
    env.player = { name = "Гендольф", surname = "Белыйй", level = 10,
                   classFile = "WARLOCK", className = "Чернокнижник",
                   raceName = "Орк", factionFile = "Horde",
                   guid = "Player-1-2", realm = "Test" }
    env.professions = {
        { name = "Алхимия", skill = 150, max = 150, skillTrusted = true },
        { name = "Инженерное дело", skill = 150, max = 150, skillTrusted = true },
        { name = "Кулинария", skill = 40, max = 150, skillTrusted = true },
    }
    H.rescan(env)
    local own, ownConf, _, ownSource = ns.Roster:Professions("Гендольф Белыйй")
    H.eq(#own, 3, "своя запись знает три профессии, а чужой кеш знал две")
    H.eq(ownSource, "own", "и источник - свой")
    H.eq(own[1].name, "Алхимия", "имена в своей записи те, что отдал клиент")
end

-- ИМЯ ПРОФЕССИИ НА ЭКРАНЕ - ПО-РУССКИ, ДАЖЕ КОГДА ПРИШЛО ПО-АНГЛИЙСКИ.
--
-- Чужой кеш пишет «Enchanting», «First Aid»; клиент у игрока ruRU. Карточка
-- «эти профессии есть у другого персонажа» на настоящих данных читалась как
-- «Enchanting 225 — Гендольф Серыйй». Перевод берётся из того же единственного
-- словаря NAME_BRIDGE, которым книга рецептов склеивает свои и чужие имена, а
-- не из второго, вписанного рядом.
H.suite("Английское имя профессии из чужого кеша показывается по-русски")
do
    local ns = H.load().ns
    H.eq(ns.Roster:DisplayName("Enchanting"), "Наложение чар", "Enchanting")
    H.eq(ns.Roster:DisplayName("First Aid"), "Первая помощь", "First Aid")
    H.eq(ns.Roster:DisplayName("Alchemy"), "Алхимия", "Alchemy")
    -- Своё имя не портится.
    H.eq(ns.Roster:DisplayName("Алхимия"), "Алхимия", "русское имя не меняется")
    -- Незнакомое имя отдаётся как есть, а не заменяется прочерком.
    H.eq(ns.Roster:DisplayName("Пекарство"), "Пекарство", "незнакомое - как пришло")
    H.eq(ns.Roster:DisplayName(nil), nil, "ничего из ничего")
end

H.suite("Про кого не знаем - так и говорим, а не «профессий нет»")
do
    local env = H.load()
    local ns = env.ns
    env.player = { name = "Гендольф", surname = "Серыйй", level = 28,
                   classFile = "MAGE", className = "Маг", raceName = "Тролль",
                   factionFile = "Horde", guid = "Player-1-1", realm = "Test" }
    env.professions = {
        { name = "Портняжное дело", skill = 225, max = 225, skillTrusted = true },
    }
    env.syndicator = true
    env.altNames = { "Незнакомец-PvP" }
    env.altData = {
        ["Незнакомец-PvP"] = {
            details = { character = "Незнакомец", class = 9,
                        className = "WARLOCK", realm = "PvP" },
            money = 10, bags = { {} },
        },
    }
    local snap = H.rescan(env)
    local chars = ns.CrossCharacter:Characters(snap)
    local stranger
    for _, c in ipairs(chars or {}) do
        if c.name == "Незнакомец" then stranger = c end
    end
    H.ok(stranger, "незнакомец в списке")
    if stranger then
        H.eq(ns.CrossCharacter:ProfessionCount(stranger), nil,
            "про профессии незнакомца число не выдумывается")
        H.ok(ns.CrossCharacter:ProfessionText(stranger):find("не зна", 1, true)
             or ns.CrossCharacter:ProfessionText(stranger):find("не вид", 1, true),
            "текст говорит, что не знаем",
            ns.CrossCharacter:ProfessionText(stranger))
    end
end

-- ЧЬЯ ПРОФЕССИЯ ЗАКРЫВАЕТ НУЖДУ ДРУГОГО.
--
-- Теперь у обоих есть профессии, и появляется осмысленный вопрос: материал,
-- которого здесь не хватает, другой персонаж умеет СДЕЛАТЬ, а не только
-- «держит в сумках».
H.suite("Нужду закрывает профессия другого персонажа")
do
    local env = H.load()
    local ns = env.ns

    -- Чернокнижник-алхимик: умеет делать зелье.
    env.player = { name = "Гендольф", surname = "Белыйй", level = 10,
                   classFile = "WARLOCK", className = "Чернокнижник",
                   raceName = "Орк", factionFile = "Horde",
                   guid = "Player-1-2", realm = "Test" }
    env.professions = {
        { name = "Алхимия", skill = 150, max = 150, skillTrusted = true },
    }
    H.rescan(env)

    -- Маг. Ему нужен предмет, который умеет сделать алхимик.
    env.player = { name = "Гендольф", surname = "Серыйй", level = 28,
                   classFile = "MAGE", className = "Маг", raceName = "Тролль",
                   factionFile = "Horde", guid = "Player-1-1", realm = "Test" }
    env.professions = {
        { name = "Портняжное дело", skill = 225, max = 225, skillTrusted = true },
    }
    H.rescan(env)

    local who = ns.CrossCharacter:WhoCanMake("Алхимия")
    H.ok(who and #who > 0, "аддон знает, у кого алхимия",
        "получили " .. tostring(who and #who))
    if who and who[1] then
        -- ИМЯ ДОЛЖНО РАЗЛИЧАТЬ: у игрока два «Гендольфа», и «у Гендольфа есть
        -- алхимия» не отвечает на вопрос «у которого».
        H.ok(tostring(who[1].name):find("Белыйй", 1, true),
            "имя различает персонажа", tostring(who[1].name))
        H.ok(tostring(who[1].label):find("Чернокнижник", 1, true),
            "в подписи есть класс", tostring(who[1].label))
        H.eq(who[1].skill, 150, "и его навык")
    end
end

-- =====================================================================
-- 6. ДАННЫЕ ПО ДВУМ ПРОФЕССИЯМ НЕ РАЗДАЮТСЯ ВСЕМ
-- =====================================================================
--
-- Data/Horizon.lua - справочник, собранный под портняжку и чары: 97 реагентов
-- будущих рецептов, пороги потолка по четырём линиям навыка, план покупок за
-- Благосклонность торговца. Сам справочник честный, у каждой записи есть поле
-- профессии. Ограничением его делали места, которые это поле не читали.

H.suite("Слепок цен берёт реагенты своих профессий, а не всех")
do
    local ns = H.load().ns
    local HZ = ns.Horizon
    local all = HZ:WatchList()
    H.ok(#all > 0, "список наблюдения не пуст", "позиций: " .. #all)

    -- Портняжник: позиции с пометкой T и E+T.
    local tailor = HZ:WatchList({ "Портняжное дело" })
    H.ok(#tailor > 0, "у портняжника есть что наблюдать", "позиций: " .. #tailor)
    H.ok(#tailor < #all, "но не весь список целиком",
        #tailor .. " из " .. #all)

    -- Алхимик: в справочнике его реагентов нет, и это ПУСТО, а не «всё».
    local alch = HZ:WatchList({ "Алхимия" })
    H.eq(#alch, 0, "алхимику из этого списка наблюдать нечего")

    -- Чары дают свой набор, и он не равен портняжному.
    local ench = HZ:WatchList({ "Наложение чар" })
    H.ok(#ench > 0, "у зачарователя есть что наблюдать")
    H.ok(#ench ~= #tailor, "наборы разные")
end

H.suite("Чернокнижник-алхимик не снимает цены на рунную ткань")
do
    local env = H.load()
    local ns = env.ns
    env.player = { name = "Гендольф", surname = "Белыйй", level = 10,
                   classFile = "WARLOCK", className = "Чернокнижник",
                   raceName = "Орк", factionFile = "Horde",
                   guid = "Player-1-2", realm = "Test" }
    env.professions = {
        { name = "Алхимия", skill = 150, max = 150, skillTrusted = true },
    }
    H.rescan(env)
    ns.Foresight.reagentSet = nil
    local set = ns.Foresight:TrackItems()
    -- 14048 - «Bolt of Runecloth», реагент портняжки из H.PRICE_WATCH.
    H.ok(not set[14048],
        "рунная ткань не попала в слепок цен алхимика")
    -- 16204 - «Illusion Dust», реагент чар.
    H.ok(not set[16204], "пыль иллюзий тоже не попала")
end

H.suite("Портняжник свои реагенты наблюдать не перестал")
do
    local env = H.load()
    local ns = env.ns
    env.professions = {
        { name = "Портняжное дело", skill = 225, max = 225, skillTrusted = true },
    }
    H.rescan(env)
    ns.Foresight.reagentSet = nil
    local set = ns.Foresight:TrackItems()
    H.ok(set[14048], "рунная ткань на месте")
end

H.suite("«Данных нет» и «рецептов нет» - разные ответы")
do
    local ns = H.load().ns
    local HZ = ns.Horizon
    local list = HZ:RecipesFor(197)
    H.ok(type(list) == "table" and #list > 0, "по портняжке рецепты есть")

    -- 171 - линия алхимии. Данных по ней в справочнике нет, и сказать надо
    -- именно это, а не вернуть nil без объяснения.
    local none, why = HZ:RecipesFor(171)
    H.eq(none, nil, "по алхимии рецептов не отдаётся")
    H.eq(why, "no-data", "и причина названа словом")
    H.ok(not HZ:KnowsLine(171), "справочник честно говорит, что линии не знает")
    H.ok(HZ:KnowsLine(197), "а портняжку знает")
end

H.suite("Благосклонность: «данных нет» не выдаётся за «навыка не хватает»")
do
    local env = H.load()
    local ns = env.ns
    env.player = { name = "Гендольф", surname = "Белыйй", level = 10,
                   classFile = "WARLOCK", className = "Чернокнижник",
                   raceName = "Орк", factionFile = "Horde",
                   guid = "Player-1-2", realm = "Test" }
    env.professions = {
        { name = "Алхимия", skill = 150, max = 150, skillTrusted = true },
    }
    local snap = H.rescan(env)
    local plan, why = ns.Favor:Plan(snap)
    H.eq(plan, nil, "плана у алхимика нет")
    H.eq(why, "no-data-for-professions",
        "и причина - «нет данных по вашим профессиям», а не нехватка навыка")

    local cards = H.build(env)
    local note = (ns.ActionEngine.branchNote or {}).favor
    if note then
        H.ok(not tostring(note):find("навыка", 1, true)
             or tostring(note):find("данных", 1, true),
            "заметка ветки не винит навык", tostring(note))
    end
end

H.suite("Благосклонность у портняжника работает как раньше")
do
    local env = H.load()
    local ns = env.ns
    env.professions = {
        { name = "Портняжное дело", skill = 225, max = 225, skillTrusted = true,
          skillLineID = 197, skillLineIDs = { 197 } },
    }
    local snap = H.rescan(env)
    local plan, why = ns.Favor:Plan(snap)
    H.ok(plan ~= nil, "план есть", tostring(why))
    if plan then H.ok(#plan.items > 0, "и в нём есть позиции") end
end

H.suite("Раздел «Мой персонаж» показывает профессии других персонажей")
do
    local env = H.load()
    local ns = env.ns

    -- Сначала чернокнижник, чтобы реестр его запомнил.
    env.player = { name = "Гендольф", surname = "Белыйй", level = 10,
                   classFile = "WARLOCK", className = "Чернокнижник",
                   raceName = "Орк", factionFile = "Horde",
                   guid = "Player-1-2", realm = "Test" }
    env.professions = {
        { name = "Алхимия", skill = 150, max = 150, skillTrusted = true },
        { name = "Инженерное дело", skill = 150, max = 150, skillTrusted = true },
    }
    H.rescan(env)

    -- Теперь маг смотрит окно.
    env.player = { name = "Гендольф", surname = "Серыйй", level = 28,
                   classFile = "MAGE", className = "Маг", raceName = "Тролль",
                   factionFile = "Horde", guid = "Player-1-1", realm = "Test" }
    env.professions = {
        { name = "Портняжное дело", skill = 225, max = 225, skillTrusted = true },
    }
    H.rescan(env)

    -- Строки собирает Logic/Roster.lua, а не файл UI: это утверждения о мире,
    -- и проверять их надо тестом, а UI в стенд не загружается вовсе.
    local lines = ns.Roster:OtherCharacterLines()
    H.ok(lines and #lines > 0, "строки про других персонажей есть",
        "получили " .. tostring(lines and #lines))
    local text = ""
    for _, l in ipairs(lines or {}) do
        text = text .. tostring(l.label) .. " " .. tostring(l.value) .. " | "
    end
    H.ok(text:find("Белыйй", 1, true), "чернокнижник назван", text)
    H.ok(text:find("Алхимия", 1, true), "и его алхимия видна", text)
    H.ok(text:find("150", 1, true), "с навыком", text)
    -- Сам маг в этот список не идёт: он и так выше, в своём разделе.
    H.ok(not text:find("Портняжное дело", 1, true),
        "своих профессий здесь нет — они выше", text)
end

-- =====================================================================
-- 6a. ПАМЯТЬ НЕ СТИРАЕТСЯ ХУДШИМ ОТВЕТОМ
-- =====================================================================
--
-- Реестр перезаписывается на КАЖДОМ пересчёте, а пересчёт бывает рано - когда
-- ни один маршрут чтения профессий ещё не ответил. Если в такой момент в запись
-- уедет пустой список, память о персонаже будет стёрта тем, что мы про него
-- ничего не узнали. Это тот же случай, от которого защищается RecipeBook:Store
-- своим рангом источников, и защита нужна по той же причине.

H.suite("Пустой ответ клиента не стирает запомненные профессии")
do
    local env = H.load()
    local ns = env.ns
    env.player = { name = "Гендольф", surname = "Белыйй", level = 10,
                   classFile = "WARLOCK", className = "Чернокнижник",
                   raceName = "Орк", factionFile = "Horde",
                   guid = "Player-1-2", realm = "Test" }
    env.professions = {
        { name = "Алхимия", skill = 150, max = 150, skillTrusted = true },
        { name = "Инженерное дело", skill = 150, max = 150, skillTrusted = true },
        { name = "Кулинария", skill = 40, max = 150, skillTrusted = true },
    }
    H.rescan(env)
    H.eq(#ns.Roster:Find("Гендольф Белыйй").professions, 3, "три профессии записаны")

    -- А теперь клиент не ответил: профессий ноль, достоверность «неизвестно».
    -- Так бывает на раннем пересчёте, до того как игра отдала список.
    env.professions = {}
    H.rescan(env)
    local profs, conf, age, source = ns.Roster:Professions("Гендольф Белыйй")
    H.ok(profs and #profs == 3,
        "запись не стёрта пустым ответом",
        "получили " .. tostring(profs and #profs))
    H.eq(source, "own", "и она по-прежнему своя")

    -- Зато настоящее изменение проходит: профессию сбросили и взяли другую.
    env.professions = {
        { name = "Кузнечное дело", skill = 1, max = 75, skillTrusted = true },
    }
    H.rescan(env)
    local after = ns.Roster:Professions("Гендольф Белыйй")
    H.eq(#after, 1, "настоящая смена профессий записана")
    H.eq(after[1].name, "Кузнечное дело", "и это новая профессия")
end

H.suite("Партия не считается, когда размер стопки неизвестен")
do
    local env = H.load()
    local ns = env.ns
    -- Предмет есть в клиенте, но размер стопки клиент не назвал.
    H.item(env, 118, { name = "Слабое лечебное зелье", noStackCount = true,
        classID = 0, subclassID = 1, sellPrice = 25 })
    H.item(env, 2447, { name = "Мироцвет", stackCount = 20, classID = 7,
        subclassID = 9, sellPrice = 1 })
    env.prices[118] = 400
    env.prices[2447] = 50
    env.bags[2447] = 40
    H.profession(env, "Алхимия", 150, 150, {
        H.recipe { id = 2330, output = 118, outputQty = 1, learned = true,
                   reagents = { { itemID = 2447, qty = 1 } },
                   name = "Слабое лечебное зелье", diff = "trivial" },
    })
    H.rescan(env)

    H.eq(ns.CraftingPlanner:SaleShape(118), nil,
        "без размера стопки форма продажи неизвестна")
    local batch = ns.CraftingPlanner:BatchProfit(ns.RecipeBook:Get(2330))
    H.ok(batch, "прибыль всё равно посчиталась")
    H.eq(batch.shapeKnown, false, "но форма продажи помечена как неизвестная")
    H.eq(batch.runs, 1, "и в зачёте один крафт, а не выдуманная стопка")
    local unitMargin = ns.CraftingPlanner:Margin(ns.RecipeBook:Get(2330))
    H.near(batch.margin, unitMargin, 1, "прибыль - за один крафт")
end

H.suite("Чужие данные про альта не выдаются за свои наблюдения")
do
    local env = H.load()
    local ns = env.ns
    env.foreignDB = {
        chars = {
            ["Player-1-2"] = {
                name = "Гендольф", surname = "Белыйй", level = 10,
                classFile = "WARLOCK", class = "Чернокнижник",
                professions = { { name = "Alchemy", skill = 150, max = 150 } },
            },
        },
    }
    env.player = { name = "Гендольф", surname = "Серыйй", level = 28,
                   classFile = "MAGE", className = "Маг", raceName = "Тролль",
                   factionFile = "Horde", guid = "Player-1-1", realm = "Test" }
    env.professions = {
        { name = "Портняжное дело", skill = 225, max = 225, skillTrusted = true },
    }
    env.syndicator = true
    env.altNames = { "Гендольф Белыйй-PvP" }
    env.altData = {
        ["Гендольф Белыйй-PvP"] = {
            details = { character = "Гендольф Белыйй", class = 9,
                        className = "WARLOCK", realm = "PvP" },
            money = 467, bags = { {} },
        },
    }
    local snap = H.rescan(env)
    local chars = ns.CrossCharacter:Characters(snap)
    local warlock
    for _, c in ipairs(chars or {}) do
        if c.name == "Гендольф Белыйй" then warlock = c end
    end
    H.ok(warlock, "чернокнижник в списке")
    if warlock then
        H.eq(warlock.professionsSource, "foreign", "источник - чужой кеш")
        local text = ns.CrossCharacter:ProfessionText(warlock)
        H.ok(text:find(ns.FOREIGN_BOOK.short, 1, true),
            "текст называет чужую книгу", text)
        -- И имя профессии по-русски, а не английским из чужого кеша.
        H.ok(text:find("Алхимия", 1, true), "имя профессии по-русски", text)
        H.ok(not text:find("Alchemy", 1, true), "английского имени на экране нет", text)
    end
end

H.suite("«Никто не умеет» и «я не знаю» - разные ответы")
do
    local env = H.load()
    local ns = env.ns
    env.player = { name = "Гендольф", surname = "Серыйй", level = 28,
                   classFile = "MAGE", className = "Маг", raceName = "Тролль",
                   factionFile = "Horde", guid = "Player-1-1", realm = "Test" }
    env.professions = {
        { name = "Портняжное дело", skill = 225, max = 225, skillTrusted = true },
    }
    H.rescan(env)
    -- В реестре только текущий персонаж: про остальных сказать нечего.
    local who, why = ns.CrossCharacter:WhoCanMake("Алхимия")
    H.eq(who, nil, "пустого списка здесь быть не должно")
    H.eq(why, "no-other-characters",
        "причина названа: других персонажей я не видел")

    -- А когда другой персонаж в реестре есть и алхимии у него нет - это уже
    -- утверждение, и список пустой.
    env.player = { name = "Гендольф", surname = "Белыйй", level = 10,
                   classFile = "WARLOCK", className = "Чернокнижник",
                   raceName = "Орк", factionFile = "Horde",
                   guid = "Player-1-2", realm = "Test" }
    env.professions = {
        { name = "Инженерное дело", skill = 150, max = 150, skillTrusted = true },
    }
    H.rescan(env)
    env.player.surname = "Серыйй"
    env.player.guid = "Player-1-1"
    env.player.classFile = "MAGE"
    env.professions = {
        { name = "Портняжное дело", skill = 225, max = 225, skillTrusted = true },
    }
    H.rescan(env)
    local none, why2 = ns.CrossCharacter:WhoCanMake("Алхимия")
    H.ok(none and #none == 0, "список есть и он пуст - это утверждение",
        tostring(none) .. " / " .. tostring(why2))
    local eng = ns.CrossCharacter:WhoCanMake("Инженерное дело")
    H.ok(eng and #eng == 1, "а инженерное дело нашлось",
        "получили " .. tostring(eng and #eng))
end

-- =====================================================================
-- 7. ТЕКСТЫ И ЗНАЧКИ НЕ ГОВОРЯТ ПРО МАГА
-- =====================================================================

H.suite("Общие значки крафта не из портняжной мастерской")
do
    local ns = H.load().ns
    H.ok(not tostring(ns.KIND_ICON.CRAFT_GEAR):find("Tailoring", 1, true),
        "запасной значок «скрафтить» не иголка с нитками",
        tostring(ns.KIND_ICON.CRAFT_GEAR))
    H.ok(not tostring(ns.KIND_ICON.CRAFT_MAT):find("Silk", 1, true),
        "запасной значок материала не рулон шёлка",
        tostring(ns.KIND_ICON.CRAFT_MAT))
end

H.suite("Происхождение данных не рассказывает про мага")
do
    local env = H.load()
    local ns = env.ns
    env.player.classFile = "WARLOCK"
    env.player.className = "Чернокнижник"
    H.rescan(env)
    local text = ns.Provenance and ns.Provenance.Text and ns.Provenance:Text() or nil
    if type(text) ~= "string" then
        local rows = ns.Provenance and ns.Provenance.Rows and ns.Provenance:Rows() or {}
        local bits = {}
        for _, r in ipairs(rows) do
            bits[#bits + 1] = tostring(r.text or r.why or r.value or "")
        end
        text = table.concat(bits, " ")
    end
    H.ok(not text:find("для мага", 1, true),
        "в разделе «происхождение» слова «для мага» нет")
end

-- СОГЛАСОВАНИЕ ПОСЛЕ «ИЗ N» - РОДИТЕЛЬНЫЙ ПАДЕЖ, А НЕ ИМЕНИТЕЛЬНЫЙ.
--
-- «2 из 82 рецептов» правильно, «2 из 82 рецепта» - нет; а «1 из 1 рецепта»
-- правильно, «1 из 1 рецепт» - нет. То есть набор форм здесь СДВИНУТ
-- относительно обычного, и сдвинут нарочно. Набор проверяет именно это, потому
-- что «исправление» сдвига на обычный набор выглядит правдоподобно и ломает
-- единицу - так один раз и вышло.
H.suite("Согласование после «из N»: «из 1 рецепта», «из 82 рецептов»")
do
    local U = H.load().ns.Util
    local function afterIz(n)
        return U.plural(n, "рецепта", "рецептов", "рецептов")
    end
    H.eq(afterIz(1), "рецепта", "из 1 рецепта")
    H.eq(afterIz(2), "рецептов", "из 2 рецептов")
    H.eq(afterIz(82), "рецептов", "из 82 рецептов")
    H.eq(afterIz(85), "рецептов", "из 85 рецептов")
    -- А обычный, несдвинутый набор - для фраз без «из».
    H.eq(U.plural(1, "рецепт", "рецепта", "рецептов"), "рецепт", "1 рецепт")
    H.eq(U.plural(82, "рецепт", "рецепта", "рецептов"), "рецепта", "82 рецепта")
end

-- =====================================================================
-- РЕЕСТР: НАРУЖУ КОПИЯ, И ОТВЕТ НЕ ЗАВИСИТ ОТ ОБХОДА ТАБЛИЦЫ
-- =====================================================================

H.suite("Реестр: Roster:All отдаёт копию, а не живую таблицу сохранёнки")
do
    local env = H.load()
    local ns = env.ns
    H.rescan(env)
    local me = ns.CharacterScanner:Get().fullName
    H.ok(ns.Roster:Find(me) ~= nil, "запись о текущем персонаже есть: " .. tostring(me))

    local copy = ns.Roster:All()
    -- Любой вызывающий может сделать с полученной таблицей что угодно - и это
    -- не должно попасть в реестр в обход Remember, его порядка источников и
    -- его обрезки.
    copy["Самозванец"] = { fullName = "Самозванец", professions = {} }
    copy[me] = nil
    local entry = copy["Подделка"]
    H.eq(ns.Roster:Find("Самозванец"), nil, "дописанного в копию в реестре нет")
    H.ok(ns.Roster:Find(me) ~= nil, "и стёртое в копии в реестре осталось")
    H.eq(entry, nil, "а чего в реестре нет, того нет и в копии")

    -- Копия глубокая: правка вложенной таблицы тоже не доходит до реестра.
    local again = ns.Roster:All()
    local first
    for _, e in pairs(again) do first = e; break end
    H.ok(first ~= nil, "в копии кто-то есть")
    if first then
        first.level = 999
        first.professions = first.professions or {}
        first.professions[#first.professions + 1] = { name = "Выдумка" }
        local live = ns.Roster:Find(first.fullName)
        H.ok(live == nil or live.level ~= 999, "уровень в реестре не переписан")
        local names = {}
        for _, prof in ipairs((live and live.professions) or {}) do
            names[#names + 1] = prof.name
        end
        H.eq(ns.Util.contains(table.concat(names, ","), "Выдумка"), false,
            "и выдуманная профессия в реестр не попала: " .. table.concat(names, ", "))
    end
end

H.suite("Реестр: два ключа, различающиеся регистром, дают один и тот же ответ")
do
    -- ОТВЕТ НЕ ДОЛЖЕН ЗАВИСЕТЬ ОТ ВНУТРЕННЕЙ РАСКЛАДКИ ТАБЛИЦЫ.
    --
    -- Поиск без учёта регистра брал первое совпадение из pairs, а порядок pairs
    -- определяется хешами ключей, то есть НАБОРОМ ключей в таблице. Поэтому
    -- проверяется одно и то же на нескольких наборах-пустышках: при разной
    -- раскладке ответ обязан совпасть. Это ровно то свойство, которого не было.
    local answers, levels = {}, {}
    local decoySets = {
        {},
        { "Аарон", "Борис", "Виктор" },
        { "Зигмунд", "Ярослав", "Эдуард", "Юлий", "Тимофей" },
        { "a", "bb", "ccc", "dddd", "eeeee", "ffffff" },
        { "Один", "Два", "Три", "Четыре", "Пять", "Шесть", "Семь", "Восемь" },
    }
    for i, decoys in ipairs(decoySets) do
        local env = H.load()
        local ns = env.ns
        local db = ns.Config:Get()
        db.chars = {}
        -- Порядок вставки тоже меняется: на чётных наборах сначала строчный.
        local pair_ = (i % 2 == 0)
            and { { "гендольф белыйй", 10 }, { "Гендольф Белыйй", 20 } }
            or { { "Гендольф Белыйй", 20 }, { "гендольф белыйй", 10 } }
        for _, p in ipairs(pair_) do
            db.chars[p[1]] = { fullName = p[1], level = p[2], professions = {},
                               professionsKnown = true,
                               professionsConf = ns.CONF.EXACT, seenAt = 1 }
        end
        for j, name in ipairs(decoys) do
            db.chars[name] = { fullName = name, level = j, professions = {},
                               professionsKnown = true,
                               professionsConf = ns.CONF.EXACT, seenAt = 1 }
        end
        local found = ns.Roster:Find("ГЕНДОЛЬФ БЕЛЫЙЙ")
        answers[#answers + 1] = tostring(found and found.fullName)
        levels[#levels + 1] = tostring(found and found.level)
    end
    local sameName, sameLevel = true, true
    for i = 2, #answers do
        if answers[i] ~= answers[1] then sameName = false end
        if levels[i] ~= levels[1] then sameLevel = false end
    end
    H.ok(sameName, "ответ один и тот же при любой раскладке таблицы: "
        .. table.concat(answers, " | "))
    H.ok(sameLevel, "и это одна и та же запись: уровни "
        .. table.concat(levels, " | "))
    H.eq(answers[1], "Гендольф Белыйй",
        "выбран наименьший ключ по порядку строк — произвольно, но устойчиво")
end

H.suite("Чужой кеш: две записи на одного персонажа дают один и тот же ответ")
do
    local answers = {}
    local decoySets = {
        { "Player-1-A" },
        { "Player-1-A", "Player-9-Z", "Player-3-M", "Player-7-Q" },
        { "Player-1-A", "Player-2-B", "Player-4-D", "Player-5-E", "Player-6-F",
          "Player-8-H" },
    }
    for _, decoys in ipairs(decoySets) do
        local env = H.load()
        local ns = env.ns
        env.foreignDB = env.foreignDB or {}
        env.foreignDB.chars = {}
        -- Один и тот же персонаж под двумя GUID: так бывает после переноса,
        -- старая запись из кеша не исчезает. Профессии в них РАЗНЫЕ, поэтому
        -- видно, какую запись прочитали.
        env.foreignDB.chars["Player-0-OLD"] = {
            name = "Гендольф", surname = "Белыйй", level = 10,
            class = "Чернокнижник", classFile = "WARLOCK",
            professions = { { name = "Alchemy", skill = 1 } },
        }
        env.foreignDB.chars["Player-Z-NEW"] = {
            name = "Гендольф", surname = "Белыйй", level = 10,
            class = "Чернокнижник", classFile = "WARLOCK",
            professions = { { name = "Engineering", skill = 300 },
                            { name = "Cooking", skill = 1 } },
        }
        for i, guid in ipairs(decoys) do
            env.foreignDB.chars[guid] = {
                name = "Чужой" .. i, level = i, class = "Маг", classFile = "MAGE",
                professions = { { name = "Tailoring", skill = i } },
            }
        end
        local profs = ns.Roster:ForeignProfessions("Гендольф Белыйй")
        local bits = {}
        for _, prof in ipairs(profs or {}) do bits[#bits + 1] = prof.name end
        table.sort(bits)
        answers[#answers + 1] = table.concat(bits, ",")
    end
    local same = true
    for i = 2, #answers do
        if answers[i] ~= answers[1] then same = false end
    end
    H.ok(same, "ответ один и тот же при любой раскладке кеша: "
        .. table.concat(answers, " | "))
    H.eq(answers[1], "Alchemy",
        "прочитана запись с наименьшим ключом — произвольно, но устойчиво")
end

-- =====================================================================
-- ДОСТОВЕРНОСТЬ ЗАПИСИ О ПРОФЕССИЯХ ЧИТАЕТСЯ, А НЕ ТОЛЬКО ПИШЕТСЯ
-- =====================================================================
--
-- Поле entry.professionsConf писалось и не читалось нигде: со стороны оно
-- выглядело работающим рангом источников, а работал двоичный признак «клиент
-- ответил / не ответил». Между ними прячется случай «ответ есть, но хуже
-- прежнего» - и он стирал лучшую запись.

H.suite("Реестр: менее достоверный ответ не стирает более достоверный")
do
    local env = H.load()
    local ns = env.ns
    env.player = { name = "Гендольф", surname = "Белыйй", level = 10,
                   classFile = "WARLOCK", className = "Чернокнижник",
                   raceName = "Орк", factionFile = "Horde",
                   guid = "Player-1-2", realm = "Test" }
    local snap = {
        fullName = "Гендольф Белыйй", name = "Гендольф", surname = "Белыйй",
        level = 10, classFile = "WARLOCK", className = "Чернокнижник",
        scannedAt = 100,
        professionsConf = ns.CONF.EXACT,
        professions = {
            { name = "Алхимия", skill = 150, max = 150, skillTrusted = true },
            { name = "Инженерное дело", skill = 150, max = 150, skillTrusted = true },
            { name = "Кулинария", skill = 40, max = 150, skillTrusted = true },
        },
    }
    ns.Roster:Remember(snap)
    H.eq(#ns.Roster:Find("Гендольф Белыйй").professions, 3,
        "три профессии записаны ответом EXACT")
    H.eq(ns.Roster:Find("Гендольф Белыйй").professionsConf, ns.CONF.EXACT,
        "и достоверность записана")

    -- Ответ ЕСТЬ (клиент не промолчал), но он хуже: одна профессия, прочитанная
    -- из чужого кеша. По двоичному признаку такой ответ проходил и стирал три.
    local worse = {
        fullName = "Гендольф Белыйй", name = "Гендольф", surname = "Белыйй",
        level = 10, classFile = "WARLOCK", className = "Чернокнижник",
        scannedAt = 200,
        professionsConf = ns.CONF.ESTIMATE,
        professions = { { name = "Алхимия", skill = 1, skillTrusted = true } },
    }
    ns.Roster:Remember(worse)
    local kept = ns.Roster:Find("Гендольф Белыйй")
    H.eq(#kept.professions, 3, "худший ответ три профессии не стёр")
    H.eq(kept.professionsConf, ns.CONF.EXACT, "и достоверность осталась прежней")
    H.eq(kept.level, 10, "а то, что УЗНАЛИ, обновлено")

    -- Равный по достоверности ответ проходит целиком - в том числе когда
    -- профессий стало меньше: это настоящая смена, а не деградация маршрута.
    local changed = {
        fullName = "Гендольф Белыйй", name = "Гендольф", surname = "Белыйй",
        level = 11, classFile = "WARLOCK", className = "Чернокнижник",
        scannedAt = 300,
        professionsConf = ns.CONF.EXACT,
        professions = { { name = "Кузнечное дело", skill = 1, skillTrusted = true } },
    }
    ns.Roster:Remember(changed)
    local after = ns.Roster:Find("Гендольф Белыйй")
    H.eq(#after.professions, 1, "равный по достоверности ответ проходит")
    H.eq(after.professions[1].name, "Кузнечное дело", "и это новая профессия")
end

H.suite("Реестр: чтение с диска не делает оценочный ответ достовернее")
do
    local env = H.load()
    local ns = env.ns
    ns.Roster:Remember({
        fullName = "Гендольф Серыйй", name = "Гендольф", surname = "Серыйй",
        level = 28, classFile = "MAGE", className = "Маг", scannedAt = 100,
        professionsConf = ns.CONF.ESTIMATE,
        professions = { { name = "Портняжное дело", skill = 225, max = 225,
                          skillTrusted = true } },
    })
    local profs, conf, _, source = ns.Roster:Professions("Гендольф Серыйй")
    H.eq(#profs, 1, "профессия прочитана")
    H.eq(source, "own", "запись своя")
    H.eq(conf, ns.CONF.ESTIMATE,
        "но достоверность не выше той, с которой записали: " .. tostring(conf))

    -- А запись, сделанную точным ответом, диск честно отдаёт как «из кеша»:
    -- она старше текущего момента, и это всё, что про неё можно сказать.
    ns.Roster:Remember({
        fullName = "Гендольф Белыйй", name = "Гендольф", surname = "Белыйй",
        level = 13, classFile = "WARLOCK", className = "Чернокнижник",
        scannedAt = 100,
        professionsConf = ns.CONF.EXACT,
        professions = { { name = "Алхимия", skill = 150, skillTrusted = true } },
    })
    local _, conf2 = ns.Roster:Professions("Гендольф Белыйй")
    H.eq(conf2, ns.CONF.CACHED, "точный ответ с диска — «из кеша»")
end

-- =====================================================================
-- СПИСОК НАБЛЮДЕНИЯ: ИМЯ ЗАВИСИТ ОТ ЯЗЫКА, НОМЕР ЛИНИИ - НЕТ
-- =====================================================================
--
-- Сверка шла по русским именам профессий. На клиенте ruRU совпадало прямо, на
-- enUS спасала английская пара из NAME_BRIDGE. На любом третьем языке не
-- совпадало ничего - и список наблюдения обнулялся МОЛЧА: суточные слепки цен
-- просто перестали бы записываться, а сказать об этом было нечем.

H.suite("Список наблюдения: сверка идёт по номеру линии навыка, а не по имени")
do
    local ns = H.load().ns
    local HZ = ns.Horizon
    H.eq(HZ.WATCH_PROF_LINE.T, 197, "у кода T записан номер портняжки")
    H.eq(HZ.WATCH_PROF_LINE.E, 333, "у кода E — номер чар")

    local byName = HZ:WatchList({ "Портняжное дело" })
    -- Имя на языке, которого аддон не знает, а номер линии тот же.
    local byLine, report = HZ:WatchList({
        { name = "Schneiderei", skillLineID = 197 },
    })
    H.ok(#byName > 0, "по русскому имени список есть: " .. #byName)
    H.eq(#byLine, #byName,
        "по незнакомому имени с номером линии — тот же список: " .. #byLine)
    H.ok(report and report.byLine > 0,
        "и сверка прошла по номеру: " .. tostring(report and report.byLine))
    H.ok(report and report.recognised, "профессия опознана")
end

H.suite("Список наблюдения: незнакомая локаль не обнуляет список молча")
do
    local ns = H.load().ns
    local HZ = ns.Horizon
    local all = HZ:WatchList()

    -- Ни номера линии, ни узнаваемого имени: клиент на языке, которого ни
    -- Codex, ни наш словарь не знают.
    local list, report = HZ:WatchList({ { name = "Schneiderei" } })
    H.ok(report ~= nil, "отчёт о сверке есть — молча отвечать нельзя")
    H.eq(report.recognised, false, "и в нём сказано, что профессию не опознали")
    H.eq(#(report.unresolved or {}), 1, "и названо, какую именно")
    H.eq(report.unresolved[1], "Schneiderei", "именно её: " .. tostring(report.unresolved[1]))
    H.eq(#list, #all,
        "а список не обнулён: наблюдаю за всем справочником, " .. #list
        .. " из " .. #all)

    -- КОНТРОЛЬ. Опознанная профессия, которой в справочнике нет, по-прежнему
    -- даёт ПУСТО - это утверждение «ему тут наблюдать нечего», и подменять его
    -- полным списком было бы ошибкой в другую сторону.
    local alch, alchReport = HZ:WatchList({ { name = "Алхимия" } })
    H.eq(#alch, 0, "алхимику наблюдать нечего")
    H.ok(alchReport and alchReport.recognised,
        "и это именно «нечего», а не «я не понял, кто он»")
end

H.suite("Список наблюдения: незнакомая локаль видна в слепке цен, а не пропадает")
do
    local env = H.load()
    local ns = env.ns
    env.professions = {
        { name = "Schneiderei", skill = 225, max = 225, skillTrusted = true },
    }
    H.rescan(env)
    ns.Foresight.reagentSet = nil
    local set = ns.Foresight:TrackItems()
    -- 14048 - «Bolt of Runecloth», реагент портняжки из H.PRICE_WATCH.
    H.ok(set[14048],
        "слепки цен не прекратились: реагент портняжки в наблюдении есть")
    local report = ns.Foresight.horizonMatch
    H.ok(report ~= nil, "и отчёт о сверке сохранён, а не выброшен")
    H.eq(report and report.recognised, false,
        "в нём сказано, что профессии не опознаны")
end

end
