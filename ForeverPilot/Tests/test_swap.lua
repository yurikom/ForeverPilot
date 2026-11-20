-- ForeverPilot / Tests/test_swap.lua
--
-- СМЕННОЕ ОРУЖИЕ И ИНСТРУМЕНТЫ ПРОФЕССИЙ.
--
-- Живая находка: игрок надел удочку, чтобы порыбачить, и аддон начал советовать
-- оружие - потому что слот оценивался ТОЛЬКО по надетому, а удочка боевых
-- характеристик почти не даёт. У игрока при этом оружие есть, просто лежит в
-- сумке. Правильный ответ в такой ситуации - не «скрафти оружие», а «надень то,
-- что у тебя уже есть», и это самый дешёвый совет из возможных.
--
-- Проверяется три вещи:
--   1. инструмент профессии определяется по ТИПУ предмета, а не по названию;
--   2. слот оценивается по лучшему боевому предмету, который есть у игрока -
--      надетому, в сумках или в банке;
--   3. когда в сумке лежит лучше надетого, аддон говорит «надень», а не
--      «скрафти».
local H = ...

return function()

-- Реальные числа из клиента пользователя (Polestar_ItemDB, 2026-11-17):
--   6367  Большая железная удочка   class 2 sub 20  dmin45 dmax69 speed3000
--   13062 Громодерево (палочка)     class 2 sub 19  dmin36 dmax67 speed1900
--   7005  Нож для снятия шкур       class 2 sub 14  dmin2 dmax5 speed1600
local POLE, WAND, KNIFE = 6367, 13062, 7005
local STAFF, WEAK = 900001, 900002

local function world()
    local env = H.load()
    local ns = env.ns
    env.player.level = 26
    env.player.classFile = "MAGE"
    env.player.className = "Маг"
    env.spec = "Тайная магия"
    env.money = 50000

    -- Инструменты. Урон у удочки есть, и он выше, чем у слабого посоха: именно
    -- поэтому отличать её по характеристикам нельзя, только по типу.
    H.item(env, POLE, { name = "Большая железная удочка", equipLoc = "INVTYPE_2HWEAPON",
        reqLevel = 25, classID = 2, subclassID = 20, quality = 1 })
    env.foreignItemStats[POLE] = { dps = 19.0 }
    H.item(env, KNIFE, { name = "Нож для снятия шкур", equipLoc = "INVTYPE_WEAPON",
        reqLevel = 1, classID = 2, subclassID = 14, quality = 1 })
    env.foreignItemStats[KNIFE] = { dps = 2.2 }

    -- Палочка в слоте дальнего боя - оружие, не инструмент.
    H.item(env, WAND, { name = "Громодерево", equipLoc = "INVTYPE_RANGEDRIGHT",
        reqLevel = 22, classID = 2, subclassID = 19, quality = 3 })
    env.foreignItemStats[WAND] = { dps = 27.1 }

    -- Посох в сумке: тот самый случай из игры.
    H.item(env, STAFF, { name = "Мерцающий посох", equipLoc = "INVTYPE_2HWEAPON",
        reqLevel = 24, classID = 2, subclassID = 10, quality = 3 })
    env.foreignItemStats[STAFF] = { int = 10, sp = 8, heal = 8, dps = 27.1 }

    -- Слабый посох, который умеет крафтить игрок. Лучше удочки по очкам и
    -- заметно хуже того, что уже лежит в сумке.
    H.item(env, WEAK, { name = "Ученический посох", equipLoc = "INVTYPE_2HWEAPON",
        reqLevel = 20, classID = 2, subclassID = 10, quality = 2, sellPrice = 100 })
    env.foreignItemStats[WEAK] = { int = 6, dps = 10.0 }
    env.prices[WEAK] = 3000

    H.item(env, 2589, { name = "Льняная ткань", sellPrice = 5 })
    env.prices[2589] = 50
    env.bags[2589] = 20
    env.bags[STAFF] = 1
    env.bags[KNIFE] = 1

    env.equipped.MAINHAND = { itemID = POLE }
    env.equipped.RANGED = { itemID = WAND }

    H.profession(env, "Tailoring", 225, 225, {
        H.recipe { id = 71, name = "Ученический посох", output = WEAK, outputQty = 1,
                   reagents = { { itemID = 2589, qty = 4 } }, diff = "optimal",
                   category = "Посохи", categoryID = 7 },
    })
    return env
end

H.suite("Сменное оружие: инструмент профессии опознаётся по типу предмета")
do
    local env = world()
    local ns = env.ns
    local Gear = ns.GearAdvisor
    H.eq(Gear:IsProfessionTool(POLE), true, "удочка - инструмент (class 2, sub 20)")
    H.eq(Gear:IsProfessionTool(KNIFE), true, "нож для снятия шкур - инструмент (sub 14)")
    H.eq(Gear:IsProfessionTool(WAND), false, "палочка - оружие, а не инструмент")
    H.eq(Gear:IsProfessionTool(STAFF), false, "посох - оружие")
    -- По названию не отличаем ничего: имя может быть на любом языке.
    H.eq(Gear:IsProfessionTool(900777), false, "незнакомый предмет инструментом не считается")
end

H.suite("Сменное оружие: слот оценивается по лучшему, что есть у игрока")
do
    local env = world()
    local ns = env.ns
    local snap = ns.CharacterScanner:Scan()
    local Gear = ns.GearAdvisor
    local base = Gear:SlotBaseline("MAINHAND", snap, snap.weights)

    H.ok(base ~= nil, "ответ про слот есть")
    H.eq(base.toolEquipped, true, "видно, что в слоте инструмент")
    H.eq(base.itemID, STAFF, "за основу взят посох из сумки, а не удочка")
    H.eq(base.where, "bags", "и сказано, где он лежит")
    H.ok((base.score or 0) > 0, "слот не считается пустым: "
        .. string.format("%.2f %s", base.score or 0, ns.UNIT_BENEFIT))

    -- Удочка сама по себе боевой ценности слота не задаёт.
    local poleScore = Gear:ItemScore(POLE, snap.weights)
    H.ok((base.score or 0) > (poleScore or 0),
        string.format("посох (%.2f) выше удочки (%.2f)", base.score or 0, poleScore or 0))

    -- А в слоте дальнего боя надето настоящее оружие, и подменять его нечем.
    local ranged = Gear:SlotBaseline("RANGED", snap, snap.weights)
    H.eq(ranged.toolEquipped, nil, "в дальнем бою инструмента нет")
    H.eq(ranged.where, "equipped", "там надето лучшее из имеющегося")
end

H.suite("Сменное оружие: советуем надеть своё, а не крафтить хуже")
do
    local env = world()
    local ns = env.ns
    local cards = H.build(env)

    -- Предпосылка: слабый посох действительно лучше удочки по очкам, иначе
    -- проверка ниже ничего не проверяет (ровно так эта ошибка и держалась).
    local snap = ns.CharacterScanner:Get()
    local weak = ns.GearAdvisor:ItemScore(WEAK, snap.weights)
    local pole = ns.GearAdvisor:ItemScore(POLE, snap.weights)
    H.ok((weak or 0) > (pole or 0), string.format(
        "предпосылка: крафт (%.2f) выглядел бы апгрейдом к удочке (%.2f)",
        weak or 0, pole or 0))

    local crafted, equipCard
    for _, card in ipairs(cards) do
        if card.kind == ns.KIND.CRAFT_GEAR and card.itemID == WEAK then crafted = card end
        if card.kind == ns.KIND.EQUIP then equipCard = card end
    end
    H.eq(crafted, nil, "крафт слабого посоха не предложен")
    H.ok(equipCard ~= nil, "есть совет надеть то, что уже есть")
    if equipCard then
        H.eq(equipCard.itemID, STAFF, "речь про посох из сумки")
        H.eq(equipCard.cost or 0, 0, "совет ничего не стоит")
        H.ok(ns.Util.contains(equipCard.title, "Надеть"), "заголовок: " .. equipCard.title)
        H.ok(ns.Util.contains(equipCard.why, "удочк")
            or ns.Util.contains(equipCard.why, "инструмент")
            or ns.Util.contains(equipCard.need, "инструмент"),
            "сказано, что в слоте инструмент",
            "why = " .. tostring(equipCard.why) .. " / need = " .. tostring(equipCard.need))
    end
end

H.suite("Сменное оружие: проверки разумности на страже")
do
    local env = world()
    local ns = env.ns
    local cards = H.build(env)

    -- Обе проверки должны МОЛЧАТЬ на исправленном коде - и обе обязаны быть
    -- зарегистрированы, иначе «не сработала» ничего не значит.
    H.ok(ns.SanityChecks:HasCheck("equip-advice-without-item"),
        "проверка «надеть то, чего нет» зарегистрирована")
    H.ok(ns.SanityChecks:HasCheck("advice-worse-than-owned"),
        "проверка «совет хуже имеющегося» зарегистрирована")
    local fired = {}
    for _, e in ipairs(ns.Diag:Init().suspicious or {}) do fired[e.code] = e end
    H.eq(fired["equip-advice-without-item"], nil,
        "совета надеть несуществующее нет")
    H.eq(fired["advice-worse-than-owned"], nil,
        "совета крафтить хуже имеющегося нет")

    -- А теперь наоборот: подсунем проверке заведомо плохую карточку и убедимся,
    -- что она её ловит. Проверка, которая молчит всегда, бесполезна.
    local snap = ns.CharacterScanner:Get()
    local before = #(ns.Diag:Init().suspicious or {})
    ns.SanityChecks:Run({
        cards = {
            { kind = ns.KIND.EQUIP, key = "equip:HEAD:900999", itemID = 900999,
              title = "Надеть: предмет, которого нет" },
            { kind = ns.KIND.CRAFT_GEAR, key = "gear:71", itemID = WEAK,
              title = "Скрафтить: Ученический посох" },
        },
        snap = snap, counts = {}, generated = 2,
    })
    local after = {}
    for i = before + 1, #(ns.Diag:Init().suspicious or {}) do
        after[(ns.Diag:Init().suspicious[i] or {}).code] = ns.Diag:Init().suspicious[i]
    end
    H.ok(after["equip-advice-without-item"] ~= nil,
        "плохой совет «надеть» поймали: "
        .. tostring(after["equip-advice-without-item"]
            and after["equip-advice-without-item"].text))
    H.ok(after["advice-worse-than-owned"] ~= nil,
        "крафт хуже имеющегося поймали: "
        .. tostring(after["advice-worse-than-owned"]
            and after["advice-worse-than-owned"].text))
end

-- ЧАРЫ НА УДОЧКУ.
--
-- Живой прогон 13:13: «Чары для двуручного оружия: малый интеллект — Слот
-- «Правая рука» без чар (Большая железная удочка)». То есть аддон предложил
-- зачаровать удочку, а настоящее оружие - Мерцающий посох - лежало в сумке и
-- было УЖЕ зачаровано («Откровение», 8217). Из-за того же счёт шёл как «5/7»
-- вместо «6/7»: оружейный слот считался незачарованным.
--
-- Ветка чар читала ТОЛЬКО надетое. Правка про инструменты в GearAdvisor её не
-- касалась, поэтому теперь обе ветки спрашивают один и тот же источник истины -
-- Gear:SlotItem.
local function enchantWorld(opts)
    opts = opts or {}
    local env = world()
    local ns = env.ns
    -- Зачарованные вещи в остальных слотах, чтобы счётчик был осмысленным.
    H.item(env, 910001, { name = "Наручи", equipLoc = "INVTYPE_WRIST",
        reqLevel = 20, classID = 4, subclassID = 1 })
    env.equipped.WRIST = { itemID = 910001, enchantID = 1000 }
    H.item(env, 910002, { name = "Плащ", equipLoc = "INVTYPE_CLOAK",
        reqLevel = 20, classID = 4, subclassID = 1 })
    env.equipped.BACK = { itemID = 910002, enchantID = 1001 }

    -- Формула на двуручное оружие, которую игрок знает.
    H.item(env, 11137, { name = "Магическая пыль", sellPrice = 120 })
    env.prices[11137] = 900
    env.bags[11137] = 5
    H.profession(env, "Enchanting", 225, 225, {
        H.recipe { id = 13700, name = "Чары для двуручного оружия: малый интеллект",
                   reagents = { { itemID = 11137, qty = 1 } }, learned = true,
                   category = "Чары для двуручного оружия", categoryID = 20,
                   diff = "medium" },
        H.recipe { id = 13701, name = "Чары для наручей: интеллект",
                   reagents = { { itemID = 11137, qty = 1 } }, learned = true,
                   category = "Чары для наручей", categoryID = 10,
                   diff = "medium" },
        H.recipe { id = 13702, name = "Чары для плаща: малое сопротивление",
                   reagents = { { itemID = 11137, qty = 1 } }, learned = true,
                   category = "Чары для плаща", categoryID = 11,
                   diff = "medium" },
    })
    if opts.enchanted then env.bagEnchant[STAFF] = 8217 end
    return env
end

H.suite("Чары: удочку не зачаровываем, зачарованный посох в сумке виден")
do
    local env = enchantWorld({ enchanted = true })
    local ns = env.ns
    local snap = ns.CharacterScanner:Scan()

    -- Предпосылка: посох в сумке и он действительно зачарован.
    local item = ns.GearAdvisor:SlotItem("MAINHAND", snap, snap.weights)
    H.eq(item.itemID, STAFF, "предмет слота — посох из сумки")
    H.eq(item.where, "bags", "и он в сумке")
    H.eq(item.enchantID, 8217, "и чара с него прочитана")
    H.eq(item.toolEquipped, true, "а в руке инструмент")

    -- Советов по чарам на оружейный слот быть не должно.
    local bare = ns.EnchantAdvisor:BareSlots(snap)
    for _, b in ipairs(bare) do
        H.ok(b.slot ~= "MAINHAND", "слот «" .. tostring(b.slot)
            .. "» в списке без чар — оружейного тут быть не должно")
    end
    local sug = ns.EnchantAdvisor:Suggestions(snap, ns.CraftingPlanner)
    for _, s in ipairs(sug) do
        H.ok(s.slot ~= "MAINHAND", "нет совета зачаровать оружейный слот")
    end

    -- И счётчик: оружейный слот считается зачарованным.
    local st = ns.EnchantAdvisor:SlotStatus(snap)
    -- Считаются только слоты, на которые игрок знает формулы: иначе
    -- знаменатель зависел бы не от его книги, а от наших предположений.
    H.eq(st.enchantable, 3, "зачаровываемых слотов 3: наручи, плащ, оружие")
    H.eq(st.enchanted, 3, string.format(
        "и все три зачарованы (посох - из сумки), получили %d из %d",
        st.enchanted, st.enchantable))
    H.eq(st.bare, 0, "слотов без чар нет")
end

H.suite("Чары: посох в сумке без чары — совет есть и называет посох")
do
    local env = enchantWorld({ enchanted = false })
    local ns = env.ns
    local snap = ns.CharacterScanner:Scan()

    local item = ns.GearAdvisor:SlotItem("MAINHAND", snap, snap.weights)
    H.eq(item.enchantID, nil, "предпосылка: чары на посохе нет")

    local sug = ns.EnchantAdvisor:Suggestions(snap, ns.CraftingPlanner)
    local weapon
    for _, s in ipairs(sug) do if s.slot == "MAINHAND" then weapon = s end end
    H.ok(weapon ~= nil, "совет по оружейному слоту есть")
    if weapon then
        H.eq(weapon.itemID, STAFF, "речь про посох, а не про удочку")
        H.eq(weapon.inBag, true, "и видно, что он в сумке")
        H.ok(ns.Util.contains(weapon.equippedName or "", "Мерцающий посох"),
            "назван предмет: " .. tostring(weapon.equippedName))
        -- Формула должна быть именно двуручная: слот определён по предмету,
        -- а не по тому, что сейчас в руке.
        H.ok(ns.Util.contains(weapon.recipe.name, "двуручн"),
            "формула для двуручного: " .. tostring(weapon.recipe.name))
    end

    -- Карточка должна говорить про сумку, а не делать вид, что вещь надета.
    local cards = H.build(env)
    local card
    for _, c in ipairs(cards) do
        if c.kind == ns.KIND.ENCHANT and c.slot == "MAINHAND" then card = c end
    end
    H.ok(card ~= nil, "карточка чар по оружию есть")
    if card then
        H.ok(ns.Util.contains(card.why, "сумке"),
            "сказано, что вещь в сумке: " .. ns.Util.truncate(card.why, 120))
        H.ok(not ns.Util.contains(card.why, "удочк"),
            "и удочка в тексте не упомянута как цель")
    end
end

-- ЦЕНА СТАРШЕ СУТОК.
--
-- Самопроверка игрока поймала: «цена предмета 11082 старше суток (1 день
-- назад), но как устаревшая не помечена». Причина - два разных определения
-- устаревшего: PriceProvider понижал достоверность только после 48 часов, а
-- проверка ругалась уже после 24. Молчать об этом нельзя: возраст цены - это
-- как раз то, что игрок обязан видеть рядом с суммой.
H.suite("Цена: возраст старше суток назван в карточке")
do
    local env = H.load()
    local ns = env.ns
    env.player.level = 26
    env.player.classFile = "MAGE"
    env.money = 500000
    -- Auctionator есть и знает цену ТОВАРА, но не знает цену материала:
    -- по материалу остаётся только своя память, и именно её возраст важен.
    env.auctionator = true

    H.item(env, 11082, { name = "Рунная ткань", sellPrice = 50 })
    H.item(env, 930001, { name = "Мантия на продажу", sellPrice = 500 })
    env.prices[930001] = 40000
    -- Своя наблюдённая цена, записанная 30 часов назад: это между сутками и
    -- порогом «устаревшая», то самое окно, в котором аддон молчал.
    local now = ns.Api:ServerTime()
    ns.Config:RememberPrice(11082, 4000, "own", now - 30 * 3600)
    H.profession(env, "Портняжное дело", 225, 225, {
        H.recipe { id = 930, name = "Мантия на продажу", output = 930001,
                   reagents = { { itemID = 11082, qty = 2 } },
                   diff = "optimal", category = "Мантии" },
    })

    -- Предпосылка: цена действительно пришла из своей памяти и ей больше суток.
    ns.PriceProvider:BeginPass()
    local copper, conf, src, age = ns.PriceProvider:Buy(11082)
    H.eq(src, "own", "цена взята из своей памяти")
    H.ok(age and age > 86400, string.format("и ей %s", ns.Util.ageText(age or 0)))

    local cards = H.build(env)
    local card
    for _, c in ipairs(cards) do
        if c.plan and c.plan.shopping and #c.plan.shopping > 0 then card = c end
    end
    H.ok(card ~= nil, "карточка с покупкой материалов есть")
    if card then
        local said = (card.need and ns.Util.contains(card.need, "назад"))
            or (card.why and ns.Util.contains(card.why, "назад"))
        H.ok(said, "возраст цены назван: " .. ns.Util.truncate(tostring(card.need), 120))
    end

    -- И самопроверка на этом больше не срабатывает.
    local fired
    for _, e in ipairs(ns.Diag:Init().suspicious or {}) do
        if e.code == "stale-price-unmarked" then fired = e end
    end
    H.eq(fired, nil, "проверка «цена не помечена» молчит: "
        .. tostring(fired and fired.text))
    H.ok(ns.SanityChecks:HasCheck("stale-price-unmarked"),
        "но сама проверка на месте")
end

end
