-- ForeverPilot / Tests/test_stats.lua
-- Stat weights, gear comparison, the Forever level rule, enchant slot mapping.
local H = ...

return function()

local S

H.suite("Веса: канонизация ключей клиента")
do
    local env = H.load()
    local ns = env.ns
    S = ns.STAT
    local raw = {
        ITEM_MOD_INTELLECT_SHORT = 10,
        ITEM_MOD_STAMINA_SHORT = 8,
        ITEM_MOD_SPELL_POWER_SHORT = 12,
        ITEM_MOD_STRENGTH_SHORT = 0,         -- zeroes are dropped
        ["ITEM_MOD_НЕИЗВЕСТНО"] = 99,        -- unknown keys are ignored
    }
    local canon = ns.StatWeights:Canonical(raw)
    H.eq(canon[S.INT], 10, "интеллект")
    H.eq(canon[S.STA], 8, "выносливость")
    -- UPDATED, and the old expectation was the bug. "+12 spell power" is not a
    -- stat of its own: in this era it MEANS "+12 damage and +12 healing", and
    -- the item database reports the same bonus already split that way. Keeping
    -- a third key for it put one pribavka in the table twice, and the main stat
    -- group summed both: item 253885 read 8 instead of 4 and the weaker belt
    -- won its slot. See Tests/test_live.lua.
    H.eq(canon[S.SPELLDMG], 12, "совмещённая сила магии — это урон от магии")
    H.eq(canon[S.HEALPOWER], 12, "и лечение, тем же числом")
    H.eq(canon[S.SPELLPOWER], nil, "отдельного ключа под неё больше нет")
    H.eq(canon[S.STR], nil, "нулевые значения отброшены")
    H.eq(env.ns.Util.count(canon), 4, "лишние ключи не попали")
    H.eq(ns.StatWeights:Canonical(nil), nil, "nil на входе - nil на выходе")
end

H.suite("Веса: оценка предмета")
do
    local env = H.load()
    local ns = env.ns
    local set = ns.StatWeights:Set("CASTER_DPS")
    -- 10 int * 1.00 + 8 sta * 0.55 + 12 damage * 1.60 = 10 + 4.4 + 19.2 = 33.6
    -- The healing half of a combined bonus is weighted at zero for a damage
    -- profile, so it adds nothing - which is the point.
    local score = ns.StatWeights:Score({
        [S.INT] = 10, [S.STA] = 8, [S.SPELLDMG] = 12, [S.HEALPOWER] = 12,
    }, set)
    H.near(score, 33.6, 0.001, "оценка мага-аркана 33.6")

    -- The same item for a warrior should be nearly worthless.
    local melee = ns.StatWeights:Set("MELEE_DPS")
    local meleeScore = ns.StatWeights:Score({
        [S.INT] = 10, [S.STA] = 8, [S.SPELLDMG] = 12, [S.HEALPOWER] = 12,
    }, melee)
    H.ok(meleeScore < score / 5,
        "та же вещь воину почти бесполезна (" .. string.format("%.1f", meleeScore) .. ")")
end

H.suite("Веса: приоритет интеллекта у мага-аркана")
do
    local env = H.load()
    local ns = env.ns
    local set = ns.StatWeights:Set("CASTER_DPS")
    H.ok(set[S.INT] > set[S.STA], "интеллект важнее выносливости")
    H.ok(set[S.SPELLDMG] > set[S.INT], "сила магии важнее интеллекта")
    H.ok(set[S.STR] == 0, "сила не нужна вообще")
    H.ok(set[S.ATTACKPOWER] == 0, "сила атаки не нужна")
    H.ok(set[S.SPI] < set[S.INT], "дух дешевле интеллекта для урона")
end

-- UPDATED, and the old expectations were the bug. This suite used to assert
-- that an arcane mage, a demonology warlock and a shadow priest all resolved to
-- the same school-blind CASTER_DPS. That is exactly what let an arcane mage be
-- offered the fire, frost and healing versions of the same robe as if they were
-- interchangeable, and one of them as an upgrade over his own arcane gear. The
-- assertions below are the same checks against the behaviour we actually want:
-- one spec, one school. See Tests/test_schools.lua for the full story.
H.suite("Веса: определение набора по классу и спеку")
do
    local env = H.load()
    local ns = env.ns
    H.eq(select(1, ns.StatWeights:Resolve("MAGE", "Тайная магия")), "CASTER_ARCANE",
        "маг-аркан — свой набор под тайную магию")
    H.eq(select(1, ns.StatWeights:Resolve("MAGE", "Огонь")), "CASTER_FIRE",
        "маг-огонь — свой")
    H.eq(select(1, ns.StatWeights:Resolve("MAGE", "Лед")), "CASTER_FROST",
        "маг-лёд — свой")
    H.eq(select(1, ns.StatWeights:Resolve("MAGE", nil)), "CASTER_DPS",
        "маг без спека — школьно-нейтральный, школу не угадываем")
    H.eq(select(1, ns.StatWeights:Resolve("WARLOCK", "Демонология")), "CASTER_SHADOW",
        "чернокнижник — тень")
    H.eq(select(1, ns.StatWeights:Resolve("WARRIOR", "Защита")), "TANK", "воин-защита")
    H.eq(select(1, ns.StatWeights:Resolve("PRIEST", "Темная магия")), "CASTER_SHADOW",
        "жрец-тьма — тень")
    H.eq(select(1, ns.StatWeights:Resolve("PRIEST", nil)), "CASTER_HEAL", "жрец по умолчанию")
    local set, conf = ns.StatWeights:Resolve(nil, nil)
    H.eq(conf, ns.CONF.UNKNOWN, "без класса достоверность неизвестна")
end

H.suite("Веса: ручное переопределение игроком")
do
    local env = H.load()
    local ns = env.ns
    ns.Config:Char().statWeightOverride = "TANK"
    local _, key, conf = ns.StatWeights:Active("MAGE", "Тайная магия")
    H.eq(key, "TANK", "ручной выбор перебивает автоопределение")
    H.eq(conf, ns.CONF.EXACT, "ручной выбор - точно")
    ns.Config:Char().statWeightOverride = nil
    local _, key2 = ns.StatWeights:Active("MAGE", "Тайная магия")
    H.eq(key2, "CASTER_ARCANE", "после сброса снова авто")
end

-- Gear comparison -----------------------------------------------------

local function gearEnv()
    local env = H.load()
    local ns = env.ns
    env.player.level = 26
    env.player.classFile = "MAGE"
    env.money = 25081

    -- Currently worn: a weak cloth hood.
    H.item(env, 100, { name = "Старый капюшон", equipLoc = "INVTYPE_HEAD",
        reqLevel = 20, classID = 4, subclassID = 1, sellPrice = 100 })
    env.stats[100] = { ITEM_MOD_INTELLECT_SHORT = 4, ITEM_MOD_STAMINA_SHORT = 3 }
    env.equipped.HEAD = { itemID = 100 }

    -- Craftable, wearable at 26, clearly better.
    H.item(env, 101, { name = "Хороший капюшон", equipLoc = "INVTYPE_HEAD",
        reqLevel = 25, classID = 4, subclassID = 1, sellPrice = 400 })
    env.stats[101] = { ITEM_MOD_INTELLECT_SHORT = 12, ITEM_MOD_STAMINA_SHORT = 9 }

    -- Craftable, better still, but needs level 50. This is the Forever case:
    -- a level 26 character with 225 tailoring knows this recipe.
    H.item(env, 102, { name = "Отличный капюшон", equipLoc = "INVTYPE_HEAD",
        reqLevel = 50, classID = 4, subclassID = 1, sellPrice = 900 })
    env.stats[102] = { ITEM_MOD_INTELLECT_SHORT = 30, ITEM_MOD_STAMINA_SHORT = 20 }

    -- Craftable plate: a mage cannot wear it at any level.
    H.item(env, 103, { name = "Латный шлем", equipLoc = "INVTYPE_HEAD",
        reqLevel = 20, classID = 4, subclassID = 4, sellPrice = 900 })
    env.stats[103] = { ITEM_MOD_STRENGTH_SHORT = 20, ITEM_MOD_STAMINA_SHORT = 30 }

    H.item(env, 200, { name = "Ткань", sellPrice = 10 })
    env.prices[200] = 50
    env.prices[101] = 3000
    env.prices[102] = 20000
    env.prices[103] = 15000

    H.profession(env, "Tailoring", 225, 225, {
        H.recipe { id = 1, output = 101, reagents = { { itemID = 200, qty = 4 } },
                   name = "Хороший капюшон", diff = "optimal", category = "Капюшоны" },
        H.recipe { id = 2, output = 102, reagents = { { itemID = 200, qty = 10 } },
                   name = "Отличный капюшон", diff = "medium", category = "Капюшоны" },
        H.recipe { id = 3, output = 103, reagents = { { itemID = 200, qty = 8 } },
                   name = "Латный шлем", diff = "medium", category = "Капюшоны" },
    })
    H.rescan(env)
    ns.PriceProvider:BeginPass()
    ns.CraftingPlanner:Bind(ns.RecipeBook, ns.PriceProvider):BeginPass()
    ns.GearAdvisor:BeginPass()
    return env
end

H.suite("Экипировка: проверка уровня и класса")
do
    local env = gearEnv()
    local ns = env.ns
    local snap = ns.CharacterScanner:Get()

    local ok1 = ns.GearAdvisor:CanEquip(env.Api:ItemInfo(101), snap)
    H.eq(ok1, true, "капюшон 25 уровня надеть можно")

    local ok2, reason2, _, short = ns.GearAdvisor:CanEquip(env.Api:ItemInfo(102), snap)
    H.eq(ok2, false, "капюшон 50 уровня надеть нельзя")
    H.ok(reason2 and reason2:find("50"), "причина называет нужный уровень")
    H.eq(short, 24, "не хватает 24 уровней")

    local ok3, reason3 = ns.GearAdvisor:CanEquip(env.Api:ItemInfo(103), snap)
    H.eq(ok3, false, "латы магу нельзя")
    H.ok(reason3 and reason3:find("броню"), "причина про броню")
end

H.suite("Экипировка: улучшения отфильтрованы по уровню")
do
    local env = gearEnv()
    local ns = env.ns
    local snap = ns.CharacterScanner:Get()
    local ups = ns.GearAdvisor:Upgrades(snap, ns.CraftingPlanner)

    H.eq(#ups, 1, "одно улучшение, а не три")
    H.eq(ups[1].recipe.id, 1, "предложен именно надеваемый капюшон")
    -- 12*1 + 9*0.55 = 16.95 ; current 4*1 + 3*0.55 = 5.65 ; gain 11.3
    H.near(ups[1].gain, 11.3, 0.01, "прирост 11.3 ед.")
    H.eq(ups[1].targetSlot, "HEAD", "слот головы")
    H.ok(ups[1].cost ~= nil, "стоимость посчитана")
end

H.suite("Forever: ненадеваемое НЕ выбрасывается, а идёт в продажу")
do
    local env = gearEnv()
    local ns = env.ns
    local snap = ns.CharacterScanner:Get()

    local unwearable = ns.GearAdvisor:Unwearable(snap)
    H.eq(#unwearable, 2, "два ненадеваемых предмета сохранены")
    local ids = {}
    for _, u in ipairs(unwearable) do ids[u.recipe.id] = true end
    H.ok(ids[2], "капюшон 50 уровня в списке ненадеваемых")
    H.ok(ids[3], "латный шлем в списке ненадеваемых")

    -- And the profit branch must see the WHOLE recipe list.
    local cards = select(1, H.build(env))
    local profitIDs, gearIDs = {}, {}
    for _, card in ipairs(cards) do
        if card.kind == ns.KIND.CRAFT_PROFIT then profitIDs[card.recipeID] = card end
        if card.kind == ns.KIND.CRAFT_GEAR then gearIDs[card.recipeID] = card end
    end
    H.ok(profitIDs[2] ~= nil, "капюшон 50 ур. попал в карточки на продажу")
    H.ok(profitIDs[3] ~= nil, "латный шлем попал в карточки на продажу")
    H.eq(gearIDs[2], nil, "и при этом НЕ попал в «надеть»")
    H.eq(gearIDs[3], nil, "латы тоже не в «надеть»")
    if profitIDs[2] then
        H.ok(profitIDs[2].why:find("надеть не можете"),
            "карточка честно объясняет, почему это только на продажу")
    end
end

H.suite("Экипировка: пустой слот - любая вещь улучшение")
do
    local env = gearEnv()
    local ns = env.ns
    env.equipped.HEAD = nil
    H.rescan(env)
    ns.PriceProvider:BeginPass()
    ns.CraftingPlanner:BeginPass()
    ns.GearAdvisor:BeginPass()
    local ups = ns.GearAdvisor:Upgrades(ns.CharacterScanner:Get(), ns.CraftingPlanner)
    H.eq(#ups, 1, "улучшение найдено")
    H.near(ups[1].gain, 16.95, 0.01, "прирост равен всей оценке вещи")
end

H.suite("Экипировка: без данных о характеристиках улучшения не выдумываются")
do
    local env = gearEnv()
    local ns = env.ns
    env.stats = {}   -- the client gives us nothing
    H.rescan(env)
    ns.PriceProvider:BeginPass()
    ns.CraftingPlanner:BeginPass()
    ns.GearAdvisor:BeginPass()
    local ups = ns.GearAdvisor:Upgrades(ns.CharacterScanner:Get(), ns.CraftingPlanner)
    H.eq(#ups, 0, "без характеристик ни одного улучшения не предложено")
end

H.suite("Экипировка: один лучший кандидат на слот")
do
    local env = gearEnv()
    local ns = env.ns
    -- Two wearable hoods: only the better one should be offered.
    H.item(env, 104, { name = "Средний капюшон", equipLoc = "INVTYPE_HEAD",
        reqLevel = 22, classID = 4, subclassID = 1, sellPrice = 200 })
    env.stats[104] = { ITEM_MOD_INTELLECT_SHORT = 8, ITEM_MOD_STAMINA_SHORT = 5 }
    env.prices[104] = 1500
    local all = {}
    for _, r in ipairs(ns.RecipeBook:Bucket("Tailoring").list) do all[#all + 1] = r end
    all[#all + 1] = H.recipe { id = 4, output = 104,
        reagents = { { itemID = 200, qty = 3 } }, name = "Средний капюшон",
        category = "Капюшоны" }
    ns.RecipeBook.byProfession["Tailoring"] = nil
    ns.RecipeBook:Store("Tailoring", all, "own", ns.CONF.EXACT, 0)
    ns.RecipeBook:Reindex()
    H.rescan(env)
    ns.PriceProvider:BeginPass()
    ns.CraftingPlanner:BeginPass()
    ns.GearAdvisor:BeginPass()

    local ups = ns.GearAdvisor:Upgrades(ns.CharacterScanner:Get(), ns.CraftingPlanner)
    H.eq(#ups, 1, "на слот головы один совет")
    H.eq(ups[1].recipe.id, 1, "выбран лучший, а не первый попавшийся")
end

-- Enchant slot mapping ------------------------------------------------

H.suite("Чары: слот из категории рецепта")
do
    local env = H.load()
    local ns = env.ns
    local cases = {
        { "Чары для наручей", "WRIST" },
        { "Чары для нагрудника", "CHEST" },
        { "Чары для обуви", "FEET" },
        { "Чары для перчаток", "HANDS" },
        { "Чары для плащей", "BACK" },
        { "Чары для щитов", "SHIELD" },
        { "Чары для амулетов", "NECK" },
        { "Чары для двуручного оружия", "TWOHAND" },
        { "Чары для оружия", "MAINHAND" },
        { "Чары для предметов в левой руке", "HELDINHAND" },
        { "Bracer Enchantments", "WRIST" },
        { "Cloak Enchantments", "BACK" },
    }
    for _, case in ipairs(cases) do
        local slot = ns.SlotMap:GuessSlotFromCategory(case[1])
        H.eq(slot, case[2], case[1] .. " -> " .. case[2])
    end
    H.eq(ns.SlotMap:GuessSlotFromCategory("Рунические чародейские жезлы"), nil,
        "категория жезлов не считается слотом чар")
    H.eq(ns.SlotMap:GuessSlotFromCategory("Отдых в лагере"), nil,
        "категория лагеря не считается слотом чар")
end

H.suite("Чары: двуручное раньше общего оружия")
do
    local env = H.load()
    local ns = env.ns
    -- "двуручного оружия" contains "оруж", so order in the keyword table matters.
    H.eq(ns.SlotMap:GuessSlotFromCategory("Чары для двуручного оружия"), "TWOHAND",
        "не перепутано с обычным оружием")
end

H.suite("Чары: ручная правка слота перебивает догадку")
do
    local env = H.load()
    local ns = env.ns
    local recipe = { categoryID = 555, categoryName = "Какая-то категория" }
    H.eq(ns.SlotMap:EnchantSlot(recipe), nil, "сначала не определён")
    ns.Config:SetEnchantSlot(555, "WRIST")
    local slot, conf = ns.SlotMap:EnchantSlot(recipe)
    H.eq(slot, "WRIST", "после правки - запястья")
    H.eq(conf, ns.CONF.EXACT, "ручная правка точна")
    ns.Config:SetEnchantSlot(555, "NONE")
    H.eq(ns.SlotMap:EnchantSlot(recipe), nil, "NONE означает «не слот чар»")
end

H.suite("Чары: советы только по пустым слотам и выученным формулам")
do
    local env = H.load()
    local ns = env.ns
    env.player.level = 26

    H.item(env, 300, { name = "Наручи", equipLoc = "INVTYPE_WRIST",
        classID = 4, subclassID = 1 })
    H.item(env, 301, { name = "Нагрудник", equipLoc = "INVTYPE_CHEST",
        classID = 4, subclassID = 1 })
    H.item(env, 400, { name = "Пыль", sellPrice = 100 })
    env.prices[400] = 1000
    env.bags[400] = 5

    env.equipped.WRIST = { itemID = 300 }                    -- bare
    env.equipped.CHEST = { itemID = 301, enchantID = 1891 }  -- already enchanted

    H.profession(env, "Enchanting", 225, 225, {
        H.recipe { id = 13822, name = "Чары для браслетов: интеллект III",
                   reagents = { { itemID = 400, qty = 1 } }, learned = true,
                   category = "Чары для наручей", categoryID = 10, diff = "medium" },
        H.recipe { id = 13858, name = "Чары для нагрудника: выносливость",
                   reagents = { { itemID = 400, qty = 3 } }, learned = true,
                   category = "Чары для нагрудника", categoryID = 11 },
        H.recipe { id = 13890, name = "Чары для обуви: скорость",
                   reagents = { { itemID = 400, qty = 2 } }, learned = true,
                   category = "Чары для обуви", categoryID = 12 },
        H.recipe { id = 99999, name = "Чары для наручей: невыученные",
                   reagents = { { itemID = 400, qty = 1 } }, learned = false,
                   category = "Чары для наручей", categoryID = 10 },
    })
    H.rescan(env)
    ns.PriceProvider:BeginPass()
    ns.CraftingPlanner:Bind(ns.RecipeBook, ns.PriceProvider):BeginPass()

    local suggestions = ns.EnchantAdvisor:Suggestions(ns.CharacterScanner:Get(),
        ns.CraftingPlanner)
    H.eq(#suggestions, 1, "один совет: только по пустому слоту")
    H.eq(suggestions[1].slot, "WRIST", "это запястья")
    H.eq(suggestions[1].recipe.id, 13822, "выбрана выученная формула")
    H.eq(suggestions[1].ready, true, "пыль есть в сумках")
    H.eq(suggestions[1].cost, 0, "покупать нечего - пыль своя")

    -- Boots are not worn at all, so no suggestion for them.
    local bare = ns.EnchantAdvisor:BareSlots(ns.CharacterScanner:Get())
    H.eq(#bare, 1, "пустых зачаровываемых слотов ровно один")

    -- Empty the bags: now the reagents have to be bought and priced.
    env.bags[400] = nil
    H.rescan(env)
    ns.PriceProvider:BeginPass()
    ns.CraftingPlanner:BeginPass()
    local dry = ns.EnchantAdvisor:Suggestions(ns.CharacterScanner:Get(),
        ns.CraftingPlanner)
    H.eq(#dry, 1, "совет остаётся и без материалов")
    H.eq(dry[1].ready, false, "но помечен как неготовый")
    H.eq(dry[1].cost, 1000, "стоимость реагентов 1000 (1 пыль по 1000)")
end

H.suite("Чары: enchant распознаётся по отсутствию output")
do
    local env = H.load()
    local ns = env.ns
    local enchant = { output = nil, reagents = { { itemID = 1, qty = 1 } },
                      categoryName = "Чары для наручей" }
    local gear = { output = 123, reagents = { { itemID = 1, qty = 1 } },
                   categoryName = "Капюшоны" }
    local pending = { output = nil, reagents = {}, categoryName = "Капюшоны" }
    -- Odd category name, still an enchant: the test exists because relying on
    -- the localised category text was a real bug.
    local weird = { output = nil, reagents = { { itemID = 1, qty = 1 } },
                    categoryName = "СЕЗОН ОТКРЫТИЙ" }
    H.eq(ns.EnchantAdvisor:IsEnchantRecipe(enchant), true, "нет output + есть реагенты")
    H.eq(ns.EnchantAdvisor:IsEnchantRecipe(gear), false, "есть output - не чары")
    H.eq(ns.EnchantAdvisor:IsEnchantRecipe(pending), false, "нет реагентов - не чары")
    H.eq(ns.EnchantAdvisor:IsEnchantRecipe(weird), true,
        "странное название категории не мешает распознать чары")
end

H.suite("Кириллица: своя функция понижения регистра")
do
    local env = H.load()
    local U = env.ns.Util
    -- Lua's own string.lower leaves Cyrillic alone, which silently broke every
    -- Russian keyword match until this was added.
    H.eq(("Чары"):lower(), "Чары", "штатный lower кириллицу не трогает")
    H.eq(U.lower("Чары"), "чары", "наш lower понижает Ч")
    H.eq(U.lower("ЗАЩИТА"), "защита", "всё слово целиком")
    H.eq(U.lower("Чары для Перчаток"), "чары для перчаток", "фраза")
    H.eq(U.lower("Ёлка"), "ёлка", "буква Ё")
    H.eq(U.lower("Рунная Ткань"), "рунная ткань", "буквы из второй половины блока")
    H.eq(U.lower("ABC"), "abc", "латиница тоже")
    H.eq(U.lower("Tailoring 225"), "tailoring 225", "смешанная строка")
    H.eq(U.lower(nil), nil, "nil не ломает")
    H.eq(U.contains("Чары для Наручей", "наруч"), true, "contains без регистра")
    H.eq(U.contains("Капюшоны", "наруч"), false, "contains не ложно-срабатывает")
end

H.suite("Чары: стат вычитывается из названия через строки клиента")
do
    local env = H.load()
    local ns = env.ns
    -- The words come from the client's own ITEM_MOD_* globals, not from a
    -- hand-written translation table.
    local words = ns.StatWeights:StatWords()
    H.ok(#words > 0, #words .. " стат-слов извлечено из строк клиента")

    local function statsOf(text)
        return ns.StatWeights:StatsInText(text) or {}
    end
    H.ok(statsOf("Чары для браслетов: интеллект III")[ns.STAT.INT],
        "«интеллект III» -> интеллект (клиент даёт «интеллекту», дательный падеж)")
    H.ok(statsOf("Чары для обуви: малая ловкость")[ns.STAT.AGI],
        "«ловкость» -> ловкость")
    H.ok(statsOf("Чары для нагрудника: высшая выносливость")[ns.STAT.STA],
        "«выносливость» -> выносливость")
    H.ok(statsOf("Чары для щита: дух")[ns.STAT.SPI], "«дух» -> дух")
    H.eq(next(statsOf("Чары для плаща: защита IV")), nil,
        "«защита» статом не считается - такого ITEM_MOD у клиента нет")
end

H.suite("Чары: магу не советуют ловкость, когда есть интеллект")
do
    local env = H.load()
    local ns = env.ns
    env.player.level = 26
    env.player.classFile = "MAGE"
    env.spec = "Тайная магия"

    H.item(env, 300, { name = "Наручи", equipLoc = "INVTYPE_WRIST",
        classID = 4, subclassID = 1 })
    H.item(env, 400, { name = "Пыль", sellPrice = 100 })
    H.item(env, 401, { name = "Осколок", sellPrice = 400 })
    env.prices[400] = 500       -- the agility formula is CHEAPER
    env.prices[401] = 3000      -- the intellect formula costs more
    env.equipped.WRIST = { itemID = 300 }

    H.profession(env, "Enchanting", 225, 225, {
        H.recipe { id = 1, name = "Чары для браслетов: малая ловкость",
                   reagents = { { itemID = 400, qty = 1 } }, learned = true,
                   category = "Чары для наручей", categoryID = 10 },
        H.recipe { id = 2, name = "Чары для браслетов: интеллект III",
                   reagents = { { itemID = 401, qty = 1 } }, learned = true,
                   category = "Чары для наручей", categoryID = 10 },
    })
    H.rescan(env)
    ns.PriceProvider:BeginPass()
    ns.CraftingPlanner:Bind(ns.RecipeBook, ns.PriceProvider):BeginPass()

    local s = ns.EnchantAdvisor:Suggestions(ns.CharacterScanner:Get(), ns.CraftingPlanner)
    H.eq(#s, 1, "один совет на запястья")
    H.eq(s[1].recipe.id, 2, "выбран интеллект, несмотря на то что ловкость дешевле")
    H.ok((s[1].usefulness or 0) > 0, "полезность посчитана")

    -- A warrior with the same two formulas must get the opposite answer.
    ns.Config:Char().statWeightOverride = "MELEE_DPS"
    local s2 = ns.EnchantAdvisor:Suggestions(ns.CharacterScanner:Scan(), ns.CraftingPlanner)
    H.eq(s2[1] and s2[1].recipe.id, 1, "для ближнего боя выбрана ловкость")
    ns.Config:Char().statWeightOverride = nil
end

H.suite("Чары: бесполезная формула не выбрасывается, а честно помечается")
do
    local env = H.load()
    local ns = env.ns
    env.player.classFile = "MAGE"
    H.item(env, 300, { name = "Наручи", equipLoc = "INVTYPE_WRIST",
        classID = 4, subclassID = 1 })
    H.item(env, 400, { name = "Пыль", sellPrice = 100 })
    env.prices[400] = 500
    env.equipped.WRIST = { itemID = 300 }
    H.profession(env, "Enchanting", 225, 225, {
        H.recipe { id = 1, name = "Чары для браслетов: малая сила",
                   reagents = { { itemID = 400, qty = 1 } }, learned = true,
                   category = "Чары для наручей", categoryID = 10 },
    })
    H.rescan(env)
    ns.PriceProvider:BeginPass()
    ns.CraftingPlanner:Bind(ns.RecipeBook, ns.PriceProvider):BeginPass()

    local s = ns.EnchantAdvisor:Suggestions(ns.CharacterScanner:Get(), ns.CraftingPlanner)
    H.eq(#s, 1, "совет всё равно есть - других формул нет")
    H.eq(s[1].usefulness, 0, "но полезность оценена в ноль")

    local cards = H.build(env)
    local card
    for _, c in ipairs(cards) do
        if c.kind == ns.KIND.ENCHANT and c.recipeID == 1 then card = c end
    end
    H.ok(card ~= nil, "карточка построена")
    if card then
        H.ok(card.why:find("почти ничего не даёт"),
            "карточка честно говорит, что толку мало")
        H.ok(card.axes.power <= 0.1, "и ранжируется низко")
    end
end

H.suite("Профессии: мост между русским и английским названием")
do
    local env = H.load()
    local ns = env.ns
    H.item(env, 1, { name = "Ткань" })
    -- The recipe cache says "Tailoring"; the skill window says "Портняжное дело".
    ns.RecipeBook:Store("Tailoring", {
        H.recipe { id = 1, output = 2, reagents = { { itemID = 1, qty = 1 } } },
    }, "own", ns.CONF.EXACT, 0)
    ns.RecipeBook:Reindex()
    H.ok(ns.RecipeBook:Bucket("Портняжное дело") ~= nil,
        "русское название находит английский кеш")
    H.ok(ns.RecipeBook:Bucket("Tailoring") ~= nil, "и английское тоже")
    H.eq(ns.RecipeBook:Bucket("Кузнечное дело"), nil, "чужая профессия не находится")
end

H.suite("Чары: набор зачаровываемых слотов берётся из рецептов сервера")
do
    local env = H.load()
    local ns = env.ns
    -- Before any scan, the static fallback applies.
    H.eq(ns.SlotMap:IsEnchantable("HEAD"), true, "до скана голова считается зачаровываемой")

    H.item(env, 400, { name = "Пыль" })
    -- This realm has neck enchants and no head ones. Both facts come from the
    -- recipes existing, not from an assumption about the expansion.
    H.profession(env, "Enchanting", 225, 225, {
        H.recipe { id = 1, name = "Чары для амулета: интеллект",
                   reagents = { { itemID = 400, qty = 1 } }, learned = false,
                   category = "Чары для амулетов", categoryID = 1 },
        H.recipe { id = 2, name = "Чары для наручей: интеллект",
                   reagents = { { itemID = 400, qty = 1 } }, learned = true,
                   category = "Чары для наручей", categoryID = 2 },
    })
    local derived = ns.RecipeBook:EnchantableSlots()
    H.ok(derived ~= nil, "набор выведен из рецептов")
    H.eq(ns.SlotMap:IsEnchantable("NECK"), true, "шея зачаровывается - рецепт есть")
    H.eq(ns.SlotMap:IsEnchantable("WRIST"), true, "запястья тоже")
    H.eq(ns.SlotMap:IsEnchantable("HEAD"), false,
        "а голова нет - на этом сервере формул для неё не существует")
    H.eq(ns.SlotMap:IsEnchantable("LEGS"), false, "и ноги нет")
    -- The unlearned neck recipe still proves the slot exists, which is the
    -- point: "no formula learned" and "slot cannot be enchanted" differ.
    H.ok(derived["NECK"], "невыученный рецепт всё равно доказывает существование слота")
end

H.suite("Чары: формулы без слота попадают в «не разложено»")
do
    local env = H.load()
    local ns = env.ns
    H.item(env, 400, { name = "Пыль", sellPrice = 100 })
    H.profession(env, "Enchanting", 225, 225, {
        H.recipe { id = 1, name = "Чары непонятно куда",
                   reagents = { { itemID = 400, qty = 1 } }, learned = true,
                   category = "СЕЗОН ОТКРЫТИЙ", categoryID = 77 },
    })
    H.rescan(env)
    local unmapped = ns.EnchantAdvisor:Unmapped()
    H.eq(#unmapped, 1, "одна нераспознанная категория")
    H.eq(unmapped[1] and unmapped[1].categoryID, 77,
        "id категории сохранён для ручной правки")

    -- And it disappears once the player assigns a slot by hand.
    ns.Config:SetEnchantSlot(77, "WRIST")
    H.eq(#ns.EnchantAdvisor:Unmapped(), 0, "после ручной правки категория разложена")
end

-- ЧАРЫ: ТО, НА ЧТО ЖАЛОВАЛСЯ ИГРОК-ЗАЧАРОВАТЕЛЬ
-- ============================================================================
--
-- Дословно: «мой аддон не показывает нормально, какие чары… Он должен был
-- проанализировать, какие лучше мне чары поставить, особенно тем более, что у
-- меня маг — зачарователь». На его настоящих данных ветка выдавала ОДНУ
-- информационную карточку «Чары: 6/7, без чар: Шея» и ни одного совета - при
-- 65 выученных формулах, 60 из которых подходили к надетым на него вещам.
--
-- Номера рецептов в этих мирах настоящие: пороги навыка берутся из справочника
-- рецептов Forever (Data/ForeverSource.lua), и выдумывать их здесь нельзя -
-- иначе проверка проверяла бы фикстуру, а не правило.
--   7420  Enchant Chest  - Inferior Stamina   навык 15
--   7443  Enchant Chest  - Minor Intellect    навык 20
--   13663 Enchant Chest  - Greater Intellect  навык 185
--   13822 Enchant Bracer - Intellect          навык 210

-- Новый договор ветки: советы не только по пустым слотам, и видно, что уже
-- стоит. Проверяется отдельным утверждением, чтобы откат правки давал КРАСНУЮ
-- проверку, а не падение всего набора на вызове несуществующего метода.
local function hasSlotAdvice(ns)
    local E = ns.EnchantAdvisor
    return type(E.Advise) == "function" and type(E.Replacements) == "function"
        and type(E.Worn) == "function"
end

local function enchanterWorld(opts)
    opts = opts or {}
    local env = H.load()
    local ns = env.ns
    env.player.classFile = "MAGE"
    env.player.level = 29
    H.item(env, 300, { name = "Наручи", equipLoc = "INVTYPE_WRIST",
        classID = 4, subclassID = 1 })
    H.item(env, 301, { name = "Нагрудник", equipLoc = "INVTYPE_CHEST",
        classID = 4, subclassID = 1 })
    H.item(env, 400, { name = "Пыль", sellPrice = 100 })
    env.prices[400] = 1000
    env.equipped.WRIST = { itemID = 300, enchantID = opts.wristEnchant }
    env.equipped.CHEST = { itemID = 301, enchantID = opts.chestEnchant }
    H.profession(env, "Enchanting", 225, 225, opts.recipes or {})
    H.rescan(env)
    ns.PriceProvider:BeginPass()
    ns.CraftingPlanner:Bind(ns.RecipeBook, ns.PriceProvider):BeginPass()
    return env, ns
end

H.suite("Чары: «сильный интеллект» — это не сила")
do
    local env = H.load()
    local ns = env.ns
    -- Корень силы - «сил» (из клиентского «+%d к силе»), и простым поиском
    -- подстроки он находится внутри слова «сильный». На экране это было
    -- «Даёт прирост интеллекта И СИЛЫ» у чары, в которой силы нет вовсе.
    local stats = ns.StatWeights:StatsInText("Чары для нагрудника: сильный интеллект")
    H.ok(stats and stats.INT, "интеллект прочитан")
    H.eq(stats and stats.STR, nil, "а сила - нет: «сильный» это не «сила»")
    -- А настоящее упоминание силы читаться обязано.
    local real = ns.StatWeights:StatsInText("Чары для браслетов: малая сила")
    H.ok(real and real.STR, "«малая сила» - это сила")
    -- И «сила магии» по-прежнему не путается с силой.
    local sp = ns.StatWeights:StatsInText("Чары для оружия: малая сила магии")
    H.ok(sp and (sp.SPELLPOWER or sp.SPELLDMG), "«сила магии» прочитана")
    H.eq(sp and sp.STR, nil, "и силой не считается")
end

H.suite("Чары: на слот выбирается сильнейшая полезная формула, а не дешёвая")
do
    local env, ns = enchanterWorld({ recipes = {
        H.recipe { id = 7443, name = "Чары для нагрудника: слабый интеллект",
                   reagents = { { itemID = 400, qty = 1 } }, learned = true,
                   category = "Чары для нагрудника", categoryID = 11 },
        H.recipe { id = 13663, name = "Чары для нагрудника: сильный интеллект",
                   reagents = { { itemID = 400, qty = 3 } }, learned = true,
                   category = "Чары для нагрудника", categoryID = 11 },
    } })
    local snap = ns.CharacterScanner:Get()
    local s = ns.EnchantAdvisor:Suggestions(snap, ns.CraftingPlanner)
    H.eq(#s, 1, "один совет - на грудь")
    H.eq(s[1] and s[1].recipe.id, 13663,
        "выбран «сильный интеллект» (навык 185), а не втрое более дешёвый «слабый»")
    H.eq(s[1] and s[1].skillNeeded, 185, "порог формулы взят из справочника")
    H.eq(s[1] and s[1].skillHave, 225, "и навык игрока сопоставлен (Enchanting = Наложение чар)")
    H.eq(s[1] and s[1].cost, 3000, "цена реагентов - три пыли по 1000")
    H.ok(s[1] and s[1].statText and s[1].statText:find("интеллект"),
        "сказано, что даёт: " .. tostring(s[1] and s[1].statText))
end

H.suite("Чары: навык игрока находится, когда книга по-русски, а профессии по-английски")
do
    -- РОВНО КАК В ЖИВОМ СНИМКЕ. Книга рецептов хранит «Наложение чар» (так его
    -- называет окно профессии), а список профессий приходит английским -
    -- «Enchanting». Прямое сравнение имён давало nil, и на карточке вместо
    -- «порог навыка 185, у вас 225» стояло только «порог навыка 185».
    local env = H.load()
    local ns = env.ns
    env.player.classFile = "MAGE"
    H.item(env, 300, { name = "Наручи", equipLoc = "INVTYPE_WRIST",
        classID = 4, subclassID = 1 })
    H.item(env, 400, { name = "Пыль", sellPrice = 100 })
    env.prices[400] = 1000
    env.equipped.WRIST = { itemID = 300 }
    env.professions[#env.professions + 1] =
        { name = "Enchanting", skill = 225, max = 225, skillTrusted = true }
    ns.RecipeBook:Store("Наложение чар", {
        H.recipe { id = 13822, name = "Чары для браслетов: интеллект III",
                   reagents = { { itemID = 400, qty = 1 } }, learned = true,
                   category = "Чары для наручей", categoryID = 10 },
    }, "stored", ns.CONF.CACHED, 0)
    ns.RecipeBook:Reindex()
    H.rescan(env)
    ns.PriceProvider:BeginPass()
    ns.CraftingPlanner:Bind(ns.RecipeBook, ns.PriceProvider):BeginPass()

    local recipe = ns.RecipeBook:Get(13822)
    H.eq(recipe and recipe.profession, "Наложение чар", "книга хранит русское имя")
    local s = ns.EnchantAdvisor:Suggestions(ns.CharacterScanner:Get(),
        ns.CraftingPlanner)
    H.eq(#s, 1, "совет построен")
    H.eq(s[1] and s[1].skillNeeded, 210, "порог формулы из справочника")
    H.eq(s[1] and s[1].skillHave, 225,
        "и навык игрока найден через мост имён, а не вопреки ему")
end

H.suite("Чары: вес характеристики важнее цены реагентов")
do
    local env, ns = enchanterWorld({ recipes = {
        H.recipe { id = 7420, name = "Чары для нагрудника: низшая выносливость",
                   reagents = { { itemID = 400, qty = 1 } }, learned = true,
                   category = "Чары для нагрудника", categoryID = 11 },
        H.recipe { id = 13663, name = "Чары для нагрудника: сильный интеллект",
                   reagents = { { itemID = 400, qty = 3 } }, learned = true,
                   category = "Чары для нагрудника", categoryID = 11 },
    } })
    local s = ns.EnchantAdvisor:Suggestions(ns.CharacterScanner:Get(),
        ns.CraftingPlanner)
    H.eq(s[1] and s[1].recipe.id, 13663,
        "магу советуется интеллект (вес 1.00), а не выносливость (0.55) за треть цены")

    -- Воину - ровно наоборот, и это тот же код, а не исключение.
    ns.Config:Char().statWeightOverride = "TANK"
    local s2 = ns.EnchantAdvisor:Suggestions(ns.CharacterScanner:Scan(),
        ns.CraftingPlanner)
    H.eq(s2[1] and s2[1].recipe.id, 7420, "защитнику - выносливость")
    ns.Config:Char().statWeightOverride = nil
end

H.suite("Чары: занятый слот не выпадает молча, но и улучшением не называется")
do
    local env, ns = enchanterWorld({ wristEnchant = 1891, recipes = {
        H.recipe { id = 13822, name = "Чары для браслетов: интеллект III",
                   reagents = { { itemID = 400, qty = 1 } }, learned = true,
                   category = "Чары для наручей", categoryID = 10 },
    } })
    local snap = ns.CharacterScanner:Get()
    H.ok(hasSlotAdvice(ns), "ветка умеет советовать и по занятым слотам")
    if hasSlotAdvice(ns) then
        -- Старый договор цел: Suggestions - это слоты БЕЗ чар.
        H.eq(#ns.EnchantAdvisor:Suggestions(snap, ns.CraftingPlanner), 0,
            "в советах по пустым слотам занятого нет")

        local rep = ns.EnchantAdvisor:Replacements(snap, ns.CraftingPlanner)
        H.eq(#rep, 1, "а в советах по занятым - есть")
        H.eq(rep[1] and rep[1].slot, "WRIST", "это запястья")
        H.eq(rep[1] and rep[1].currentEnchantID, 1891, "номер стоящей чары назван")
        H.eq(rep[1] and rep[1].currentUnknown, true,
            "и помечено, что про неё мы ничего не знаем")
        H.eq(rep[1] and rep[1].conf, ns.CONF.UNKNOWN,
            "достоверность такого совета - «неизвестно»: сравнивать не с чем")

        local cards = H.build(env)
        local card
        for _, c in ipairs(cards) do
            if c.kind == ns.KIND.ENCHANT and c.recipeID == 13822 then card = c end
        end
        H.ok(card ~= nil, "карточка по занятому слоту построена")
        if card then
            H.ok(card.why:find("#1891"), "в карточке назван номер стоящей чары")
            H.ok(card.why:find("не утверждаю"),
                "и прямо сказано, что «лучше» мы не утверждаем")
            H.ok(card.need:find("свиток покупать не нужно"),
                "и что он сам зачарователь: нужны реагенты, а не свиток")
        end
    end
end

H.suite("Чары: занятый слот без полезной формулы отсеивается с названной причиной")
do
    local env, ns = enchanterWorld({ wristEnchant = 1891, recipes = {
        H.recipe { id = 7782, name = "Чары для браслетов: малая сила",
                   reagents = { { itemID = 400, qty = 1 } }, learned = true,
                   category = "Чары для наручей", categoryID = 10 },
    } })
    local snap = ns.CharacterScanner:Get()
    H.ok(hasSlotAdvice(ns), "ветка умеет советовать и по занятым слотам")
    if hasSlotAdvice(ns) then
        H.eq(#ns.EnchantAdvisor:Replacements(snap, ns.CraftingPlanner), 0,
            "перекрывать неизвестное бесполезным не предлагаем")
        local advice = ns.EnchantAdvisor:Advise(snap, ns.CraftingPlanner)
        local reason
        for _, slotNote in ipairs(advice.slots) do
            if slotNote.slot == "WRIST" then reason = slotNote.dropped end
        end
        H.eq(reason, "occupied-nothing-better-known",
            "и причина названа: " .. tostring(reason))
        -- И НАЗВАНА НА ЭКРАНЕ, А НЕ ТОЛЬКО В ДИАГНОСТИКЕ: воронку игрок не
        -- читает, карточку - читает.
        local cards = H.build(env)
        local info
        for _, c in ipairs(cards) do
            if c.key == "ench:noformula" then info = c end
        end
        H.ok(info ~= nil, "карточка с причиной построена")
        if info then
            H.ok(info.why:find("Запястья"), "слот назван: " .. tostring(info.title))
            H.ok(info.why:find("чего ваш класс не ценит"),
                "и сказано, почему совета нет")
            H.eq(#(info.enchantSkipped or {}), 1, "перечень лежит и в данных карточки")
        end
    end
    local f = ns.Diag:Init().funnels["enchants"]
    H.ok(f ~= nil, "у ветки чар есть воронка потерь")
    if f then
        H.ok((f["in"] or 0) > 0, "кандидаты в неё вошли: " .. tostring(f["in"]))
        H.eq(f.unaccounted, 0, "и ни один не потерялся без объяснения")
        H.ok(f.drops["occupied-nothing-better-known"] ~= nil,
            "отсев записан под своим именем")
    end
end

H.suite("Чары: что уже стоит на вещах - видно")
do
    -- Дословно вторая половина жалобы: «какие чанты у меня есть». Карточка
    -- писала «6 из 7», а какие именно шесть и что на них - не было нигде.
    local env = H.load()
    local ns = env.ns
    env.player.classFile = "MAGE"
    H.item(env, 300, { name = "Наручи", equipLoc = "INVTYPE_WRIST",
        classID = 4, subclassID = 1 })
    H.item(env, 301, { name = "Нагрудник", equipLoc = "INVTYPE_CHEST",
        classID = 4, subclassID = 1 })
    H.item(env, 302, { name = "Сапоги", equipLoc = "INVTYPE_FEET",
        classID = 4, subclassID = 1 })
    H.item(env, 400, { name = "Пыль", sellPrice = 100 })
    env.prices[400] = 1000
    env.bags[400] = 5
    env.equipped.WRIST = { itemID = 300, enchantID = 1891 }
    env.equipped.CHEST = { itemID = 301, enchantID = 843 }
    env.equipped.FEET = { itemID = 302 }                      -- без чар
    H.profession(env, "Enchanting", 225, 225, {
        H.recipe { id = 13822, name = "Чары для браслетов: интеллект III",
                   reagents = { { itemID = 400, qty = 1 } }, learned = true,
                   category = "Чары для наручей", categoryID = 10 },
        -- Невыученные: слот существует на этом сервере, формулы у игрока нет.
        H.recipe { id = 13663, name = "Чары для нагрудника: сильный интеллект",
                   reagents = { { itemID = 400, qty = 3 } }, learned = false,
                   category = "Чары для нагрудника", categoryID = 11 },
        H.recipe { id = 13836, name = "Чары для обуви: выносливость III",
                   reagents = { { itemID = 400, qty = 2 } }, learned = false,
                   category = "Чары для обуви", categoryID = 12 },
    })
    H.rescan(env)
    ns.PriceProvider:BeginPass()
    ns.CraftingPlanner:Bind(ns.RecipeBook, ns.PriceProvider):BeginPass()

    local snap = ns.CharacterScanner:Get()
    H.ok(hasSlotAdvice(ns), "аддон умеет перечислять уже наложенные чары")
    if hasSlotAdvice(ns) then
        local worn = ns.EnchantAdvisor:Worn(snap)
        H.eq(#worn, 2, "обе зачарованные вещи перечислены")
        local bySlot = {}
        for _, w in ipairs(worn) do bySlot[w.slot] = w end
        H.eq(bySlot.WRIST and bySlot.WRIST.enchantID, 1891, "на наручах чара #1891")
        H.eq(bySlot.CHEST and bySlot.CHEST.enchantID, 843, "на нагруднике чара #843")
        H.eq(bySlot.CHEST and bySlot.CHEST.itemName, "Нагрудник", "и вещь названа")
    end

    local cards = H.build(env)
    local info
    for _, c in ipairs(cards) do
        if c.key == "ench:noformula" then info = c end
    end
    H.ok(info ~= nil, "информационная карточка про чары построена")
    if info then
        H.ok(info.why:find("Уже зачарованы"),
            "в ней есть перечень того, что уже стоит")
        H.ok(info.why:find("#843"), "с номером чары нагрудника")
        H.ok(info.why:find("#1891"), "и наручей")
        H.ok(info.why:find("выдумывать не буду"),
            "и сказано, почему про саму чару мы ничего не утверждаем")
        H.eq(#(info.enchantWorn or {}), 2, "перечень лежит и в данных карточки")
    end
end

H.suite("Чары: порог мелкой денежной выгоды советы по чарам не режет")
do
    -- Чары не измеряются золотом: выгода у них - характеристики, а цена
    -- реагентов это РАСХОД. Порог мелкой выгоды считает прибыль в меди, и
    -- попасть под него карточка чар не должна ни при каком пороге.
    local env, ns = enchanterWorld({ recipes = {
        H.recipe { id = 13822, name = "Чары для браслетов: интеллект III",
                   reagents = { { itemID = 400, qty = 1 } }, learned = true,
                   category = "Чары для наручей", categoryID = 10 },
    } })
    H.eq(ns.MONEY_FLOOR_KINDS[ns.KIND.ENCHANT], nil,
        "ветка чар не числится денежной")
    -- Порог заведомо выше любой выгоды в этом мире.
    ns.Config:SetMoneyFloorMode(ns.MONEY_FLOOR_MODE.FIXED)
    ns.Config:SetMoneyFloorOwn(100 * 100 * 100)
    local cards = H.build(env)
    local found = false
    for _, c in ipairs(cards) do
        if c.kind == ns.KIND.ENCHANT and c.recipeID == 13822 then found = true end
    end
    H.ok(found, "совет по чарам жив при пороге в 100 золотых")
    H.eq(ns.ActionEngine.MoneyGainOf({ kind = ns.KIND.ENCHANT, benefitValue = 1 }), nil,
        "и порогом он вообще не меряется")
    ns.Config:SetMoneyFloorMode(ns.MONEY_FLOOR_MODE.OFF)
end

-- ХАРАКТЕРИСТИКИ ИЗ КЛИЕНТА: ФОРМА ОТВЕТА, КОТОРАЯ ЕСТЬ НА ЭТОМ БИЛДЕ
-- ============================================================================
--
-- Живой файл игрока: C_TooltipInfo.GetItemByID (разбор статов) - 587 попыток,
-- 587 пустых, 0 с данными. При этом сам C_TooltipInfo.GetItemByID в клиенте
-- ЕСТЬ (detect = true), а вот TooltipUtil.SurfaceArgs - НЕТ (detect = false).
-- Это и есть ответ: строки тултипа приезжают списком args, разложить который
-- должен SurfaceArgs, а читали мы только готовое поле line.leftText. На этом
-- билде оно пустое - значит разбор возвращал пусто ВСЕГДА, какой бы предмет ни
-- спросили.
--
-- Фикстура здесь описывает ФОРМУ ОТВЕТА КЛИЕНТА, а не выдуманные данные: тот же
-- класс подмены, что и локализованные ITEM_MOD_* в Tests/harness.lua. Числа
-- взяты из настоящей вещи игрока (жемчужные вещи дают силу магии).
H.suite("Характеристики: тултип читается, когда у клиента нет SurfaceArgs")
do
    local env = H.load()
    local ns, G = env.ns, env.G
    -- Производственный читатель вместо стендового фейка.
    ns.Api.ItemStatsRaw = env.real.ItemStatsRaw

    -- Клиент, как на этом билде: GetItemByID есть, SurfaceArgs нет, строки -
    -- только в args.
    local function argsLine(text)
        return { args = { { field = "leftText", stringVal = text } } }
    end
    G.C_TooltipInfo = {
        GetItemByID = function(itemID)
            if itemID ~= 701 then return nil end
            return { lines = {
                argsLine("Жемчужный венец"),
                argsLine("+10 к выносливости"),
                argsLine("+8 к силе магии"),
            } }
        end,
    }
    G.TooltipUtil = nil
    -- Прямого чтения статов нет вовсе: остаётся только тултип.
    G.C_Item = G.C_Item or {}
    G.C_Item.GetItemStats = nil
    G.GetItemStats = nil
    ns.Api:Detect()
    H.eq(ns.Api.has.tooltipByID, true, "C_TooltipInfo.GetItemByID обнаружен")
    H.eq(ns.Api.has.surfaceArgs, false,
        "а TooltipUtil.SurfaceArgs отсутствует — как в игре")

    H.item(env, 701, { name = "Жемчужный венец", equipLoc = "INVTYPE_HEAD",
        reqLevel = 20, classID = 4, subclassID = 1 })
    local raw = ns.Api:ItemStatsRaw(701)
    H.ok(raw ~= nil, "характеристики из клиента прочитаны")
    if raw then
        H.eq(raw.ITEM_MOD_STAMINA_SHORT, 10, "выносливость взята из строки тултипа")
        H.eq(raw.ITEM_MOD_SPELL_POWER_SHORT, 8, "и сила магии тоже")
    end
    -- И НИ ОДНОГО ЧУЖОГО СТАТА. «+8 к силе магии» совпадало с образцом силы
    -- («+%d к силе»): образец был открыт с конца и проверялся раньше более
    -- подробного - то есть сила магии кастера читалась как физическая сила.
    -- Молчала эта ошибка только потому, что разбор тултипа не возвращал ничего
    -- вовсе; чинить чтение и оставить такой разбор было нельзя. Защит теперь
    -- две (конец строки и «самый подробный образец первым»), и каждой по
    -- отдельности хватает - проверяется здесь сам ответ, а не способ.
    if raw then
        H.eq(raw.ITEM_MOD_STRENGTH_SHORT, nil,
            "«сила магии» не стала физической силой")
        H.eq(ns.Util.count(raw), 2, "и лишних характеристик не появилось")
    end

    -- И в диагностике сказано, КАКОЙ формой ответил клиент.
    local call = ns.Diag:Init().calls["C_TooltipInfo.GetItemByID (строки)"]
    H.ok(call ~= nil, "форма ответа записана в диагностику")
    if call then
        H.ok(call.gotData > 0, "строки с текстом нашлись: " .. tostring(call.note))
        H.ok(tostring(call.note):find("из args", 1, true) ~= nil,
            "и сказано, что текст пришёл из args: " .. tostring(call.note))
    end
end

-- ЕСЛИ ПРЯМОЙ ОТВЕТ ЕСТЬ, НО В НЁМ ТОЛЬКО БАЗА.
--
-- Ровно это и происходит в игре: 786 успешных ответов C_Item.GetItemStats, и ни
-- в одном нет силы магии - клиент на этом сервере отдаёт базовые
-- характеристики. Бонус при этом есть в тексте тултипа, и для НАДЕВАЕМОЙ вещи
-- его надо дочитать: без этого всё сравнение вещей держится на внешней базе
-- целиком.
H.suite("Характеристики: бонус дочитывается из тултипа, когда прямой ответ базовый")
do
    local env = H.load()
    local ns, G = env.ns, env.G
    ns.Api.ItemStatsRaw = env.real.ItemStatsRaw

    local function argsLine(text)
        return { args = { { field = "leftText", stringVal = text } } }
    end
    local tooltipAsked = {}
    G.C_TooltipInfo = {
        GetItemByID = function(itemID)
            tooltipAsked[itemID] = (tooltipAsked[itemID] or 0) + 1
            if itemID == 702 then
                return { lines = { argsLine("Жемчужные перчатки"),
                                   argsLine("+6 к выносливости"),
                                   argsLine("+7 к силе магии") } }
            end
            return { lines = { argsLine("Мироцвет") } }
        end,
    }
    G.TooltipUtil = nil
    -- Прямой ответ есть, но базовый - как на этом сервере.
    G.C_Item = G.C_Item or {}
    G.C_Item.GetItemStats = function(link)
        local id = ns.Util.itemIDFromLink(link)
        if id == 702 then return { ITEM_MOD_STAMINA_SHORT = 6 } end
        if id == 703 then return { ITEM_MOD_INTELLECT_SHORT = 3 } end
        return {}
    end
    ns.Api:Detect()
    H.eq(ns.Api.has.itemStats, true, "прямое чтение статов есть")

    H.item(env, 702, { name = "Жемчужные перчатки", equipLoc = "INVTYPE_HAND",
        reqLevel = 20, classID = 4, subclassID = 1 })
    H.item(env, 703, { name = "Мироцвет", sellPrice = 10 })

    local raw = ns.Api:ItemStatsRaw(702)
    H.ok(raw ~= nil, "характеристики надеваемой вещи прочитаны")
    if raw then
        H.eq(raw.ITEM_MOD_STAMINA_SHORT, 6, "база - из прямого вызова")
        H.eq(raw.ITEM_MOD_SPELL_POWER_SHORT, 7,
            "а бонус дочитан из тултипа — иначе его знает только внешняя база")
    end

    -- И РЕАГЕНТ В ТУЛТИП НЕ ЛАЗИТ: надевать его некуда, бонусов у него не
    -- бывает, а тултип в игре стоит денег. Это и есть ограничитель расхода.
    local before = tooltipAsked[703] or 0
    local rawHerb = ns.Api:ItemStatsRaw(703)
    H.eq(rawHerb and rawHerb.ITEM_MOD_INTELLECT_SHORT, 3, "реагент прочитан напрямую")
    H.eq(tooltipAsked[703] or 0, before, "и тултип по нему не спрашивался")
end

end
