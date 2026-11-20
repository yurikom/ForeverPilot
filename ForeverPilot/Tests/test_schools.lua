-- ForeverPilot / Tests/test_schools.lua
--
-- THE WORST FAILURE THIS ADDON HAS HAD. It told an arcane mage to craft gear
-- that was worse than what he was wearing, he believed it, and he spent the
-- materials.
--
-- WHAT THE GEAR ACTUALLY LOOKS LIKE IN THIS PATCH. Armour comes in families of
-- six. Armour, stamina, intellect, spirit and item level are IDENTICAL across
-- the family; only the kind of spell power differs:
--
--   Pristine  sp (generic) + heal      Silky   spFrost
--   Flame     spFire                   Shadow  spShadow
--   Pearly    spArcane                 Shining spHoly
--
-- The three cases from the player's own character, by itemID:
--
--   253957 Pearly Circlet              sta10 armor35 spArcane11   <- was worn
--   253975 Filigreed Pristine Circlet  sta12 armor38 sp8 heal22   <- WAS ADVISED
--   253983 Filigreed Pearly Circlet    sta12 armor38 spArcane14   <- right answer
--
-- TWO FAULTS, AND THE ARITHMETIC PROVES BOTH. The card claimed "+16 ед. пользы":
--
--   advised  12*0.55 + 38*0.02 + 8*1.60 + 22*0.10 = 22.36
--   worn     10*0.55 + 35*0.02                    =  6.20   <- spArcane11 SCORED ZERO
--   gain                                            16.16   <- exactly what it printed
--
--   1. spArcane was not a stat the addon knew, so the main stat of the worn
--      item was invisible and the item looked like a scrap of cloth.
--   2. healing carried weight 0.10 for a DPS caster, which is 2.2 of those
--      points for a stat an arcane mage cannot use at all.
--
-- Every assertion below is on the real itemIDs and the real numbers.
local H = ...

return function()

-- The real family, as Polestar's item database states it. Keys are its own
-- vocabulary, which is what the runtime API hands back.
local ITEMS = {
    [253957] = { name = "Жемчужный венец",            inv = 1, ilvl = 25, req = 20,
                 stats = { sta = 10, armor = 35, spArcane = 11 } },
    [253975] = { name = "Расшитый безупречный венец", inv = 1, ilvl = 30, req = 25,
                 stats = { sta = 12, armor = 38, sp = 8, heal = 22 } },
    [253983] = { name = "Расшитый жемчужный венец",   inv = 1, ilvl = 30, req = 25,
                 stats = { sta = 12, armor = 38, spArcane = 14 } },
    [253979] = { name = "Расшитый шёлковый венец",    inv = 1, ilvl = 30, req = 25,
                 stats = { sta = 12, armor = 38, spFrost = 14 } },
    [253977] = { name = "Расшитый пламенный венец",   inv = 1, ilvl = 30, req = 25,
                 stats = { sta = 12, armor = 38, spFire = 14 } },
    [253981] = { name = "Расшитый теневой венец",     inv = 1, ilvl = 30, req = 25,
                 stats = { sta = 12, armor = 38, spShadow = 14 } },
    [253985] = { name = "Расшитый сияющий венец",     inv = 1, ilvl = 30, req = 25,
                 stats = { sta = 12, armor = 38, spHoly = 14 } },
    -- Legs and belt, the other two cards that were poisoned.
    [253937] = { name = "Расшитые безупречные поножи", inv = 7, ilvl = 25, req = 20,
                 stats = { sta = 5, int = 6, spi = 4, armor = 37, sp = 6, heal = 18 } },
    [253945] = { name = "Расшитые жемчужные поножи",   inv = 7, ilvl = 25, req = 20,
                 stats = { sta = 5, int = 6, spi = 4, armor = 37, spArcane = 11 } },
    [253995] = { name = "Жемчужные поножи",            inv = 7, ilvl = 25, req = 20,
                 stats = { sta = 5, int = 6, spi = 4, armor = 37, spArcane = 11 } },
    [253885] = { name = "Кушак начинающего чародея",   inv = 6, ilvl = 15, req = 10,
                 stats = { sta = 3, int = 3, armor = 17, sp = 4, heal = 4 } },
    [253933] = { name = "Жемчужный кушак",             inv = 6, ilvl = 22, req = 17,
                 stats = { sta = 5, int = 4, armor = 22, spArcane = 7 } },
    [2911]   = { name = "Ремень Келлера",              inv = 6, ilvl = 20, req = 15,
                 stats = { sta = 2, int = 2, armor = 18 } },
}

-- The client on this realm reports BASE stats only - stamina, intellect,
-- spirit, armour - and nothing for the equip bonuses. That is not a guess: the
-- gear module of another addon running on this exact client says so in as many
-- words, and it is why it reads bonuses out of its own item database.
local CLIENT_BASE = { sta = "ITEM_MOD_STAMINA_SHORT", int = "ITEM_MOD_INTELLECT_SHORT",
                      spi = "ITEM_MOD_SPIRIT_SHORT", str = "ITEM_MOD_STRENGTH_SHORT",
                      agi = "ITEM_MOD_AGILITY_SHORT" }

local function schoolEnv(opts)
    opts = opts or {}
    local env = H.load()
    local ns = env.ns

    -- The client's half and the database's half are described separately here,
    -- so mirroring is off: this suite is precisely about the case where the
    -- client knows LESS than the database.
    env.itemDBMirror = false
    env.foreignItemStats = {}
    for itemID, def in pairs(ITEMS) do
        local equipLoc = ({ [1] = "INVTYPE_HEAD", [6] = "INVTYPE_WAIST",
                            [7] = "INVTYPE_LEGS" })[def.inv]
        H.item(env, itemID, {
            name = def.name, equipLoc = equipLoc, reqLevel = def.req,
            classID = 4, subclassID = 1, itemLevel = def.ilvl, sellPrice = 100,
        })
        -- Only the base stats reach us from the client.
        local raw = {}
        for key, clientKey in pairs(CLIENT_BASE) do
            if def.stats[key] then raw[clientKey] = def.stats[key] end
        end
        if next(raw) then env.stats[itemID] = raw end
        -- Everything else comes from the foreign item database, unless the
        -- test asked for it to be unavailable.
        if not opts.noForeign then
            local fs = {}
            for k, v in pairs(def.stats) do fs[k] = v end
            env.foreignItemStats[itemID] = fs
        end
    end

    env.player.classFile = "MAGE"
    env.player.className = "Маг"
    env.spec = opts.spec or "Тайная магия"
    env.money = 500000

    H.item(env, 9000, { name = "Ткань", sellPrice = 10 })
    env.prices[9000] = 50
    env.bags[9000] = 400

    env.equipped.HEAD = { itemID = 253957 }
    env.equipped.LEGS = { itemID = 253995 }
    env.equipped.WAIST = { itemID = 2911 }

    local recipes = {}
    local function craft(id, out)
        recipes[#recipes + 1] = H.recipe {
            id = id, output = out, reagents = { { itemID = 9000, qty = 4 } },
            name = ITEMS[out].name, diff = "trivial", category = "Капюшоны",
        }
    end
    craft(1257413, 253975)   -- Pristine circlet, the bad advice
    craft(1257417, 253983)   -- Pearly circlet, the right answer
    craft(1257415, 253979)   -- Silky
    craft(1257414, 253977)   -- Flame
    craft(1257416, 253981)   -- Shadow
    craft(1257418, 253985)   -- Shining
    craft(1257394, 253937)   -- Pristine leggings
    craft(1257398, 253945)   -- Pearly leggings
    craft(1257368, 253885)   -- Novice sash
    craft(1257392, 253933)   -- Pearly sash
    H.profession(env, "Портняжное дело", 225, 225, recipes)
    H.rescan(env)
    ns.PriceProvider:BeginPass()
    ns.CraftingPlanner:Bind(ns.RecipeBook, ns.PriceProvider):BeginPass()
    ns.GearAdvisor:BeginPass()
    return env
end

-- =====================================================================
-- Weights: healing is worth nothing to a DPS caster
-- =====================================================================

H.suite("Веса: лечение не считается пользой для боевых профилей")
do
    local env = H.load()
    local ns = env.ns
    local S = ns.STAT
    for _, key in ipairs({ "CASTER_DPS", "CASTER_ARCANE", "CASTER_FIRE",
                           "CASTER_FROST", "CASTER_SHADOW", "MELEE_DPS",
                           "HYBRID_PHYS" }) do
        local set = ns.StatWeights.SETS[key]
        H.ok(set ~= nil, "набор весов " .. key .. " существует")
        if set then
            H.eq(set[S.HEALPOWER] or 0, 0, key .. ": вес лечения ноль")
        end
    end
    -- A healer still values healing, obviously.
    H.ok((ns.StatWeights.SETS.CASTER_HEAL[S.HEALPOWER] or 0) > 1,
        "а лекарю лечение по-прежнему нужно")
end

H.suite("Веса: ничего неуместного не считается пользой")
do
    local env = H.load()
    local ns = env.ns
    local S = ns.STAT
    local dps = ns.StatWeights.SETS.CASTER_DPS
    H.eq(dps[S.STR] or 0, 0, "сила магу не нужна")
    H.eq(dps[S.ATTACKPOWER] or 0, 0, "сила атаки магу не нужна")
    H.eq(dps[S.EXPERTISE] or 0, 0, "опыт боя магу не нужен")
    H.eq(dps[S.PARRY] or 0, 0, "парирование магу не нужно")
    H.eq(dps[S.BLOCK] or 0, 0, "блокирование магу не нужно")
    H.eq(dps[S.DEFENSE] or 0, 0, "защита магу не нужна")
    H.eq(dps[S.DODGE] or 0, 0, "уворот магу не нужен")
    H.eq(dps[S.AGI] or 0, 0, "ловкость магу не нужна")
    -- Resistances are not a DPS stat either: a point of shadow resistance does
    -- not make a single spell hit harder.
    for _, stat in ipairs({ S.RESIST_ARCANE, S.RESIST_FIRE, S.RESIST_FROST,
                            S.RESIST_NATURE, S.RESIST_SHADOW }) do
        H.eq(dps[stat] or 0, 0, "сопротивление " .. stat .. " не польза для урона")
    end
    local tank = ns.StatWeights.SETS.TANK
    H.ok((tank[S.DEFENSE] or 0) > 0, "а танку защита нужна")
end

-- =====================================================================
-- Schools: arcane for an arcane mage, not "spell power is spell power"
-- =====================================================================

H.suite("Школы магии: различаются и взвешиваются по специализации")
do
    local env = H.load()
    local ns = env.ns
    local S = ns.STAT
    H.ok(S.SPELLDMG_ARCANE ~= nil, "есть отдельная характеристика «урон тайной магией»")
    H.ok(S.SPELLDMG_FIRE ~= nil, "и огнём")
    H.ok(S.SPELLDMG_FROST ~= nil, "и льдом")
    H.ok(S.SPELLDMG_SHADOW ~= nil, "и тенью")
    H.ok(S.SPELLDMG_HOLY ~= nil, "и светом")

    local arc = ns.StatWeights.SETS.CASTER_ARCANE
    H.ok((arc[S.SPELLDMG_ARCANE] or 0) > 1, "аркану тайная магия весит много")
    H.ok((arc[S.SPELLDMG_FIRE] or 0) > 0, "огонь не ноль — маг кастует Огненную глыбу")
    H.ok((arc[S.SPELLDMG_FIRE] or 0) < (arc[S.SPELLDMG_ARCANE] or 0) / 2,
        "но сильно меньше тайной")
    H.eq(arc[S.SPELLDMG_SHADOW] or 0, 0, "тень магу недоступна вовсе")
    H.eq(arc[S.SPELLDMG_HOLY] or 0, 0, "свет тоже")

    local fire = ns.StatWeights.SETS.CASTER_FIRE
    H.ok((fire[S.SPELLDMG_FIRE] or 0) > (fire[S.SPELLDMG_ARCANE] or 0),
        "огневику наоборот: огонь важнее тайной")
end

H.suite("Школы магии: специализация выбирает набор весов")
do
    local env = H.load()
    local ns = env.ns
    local SW = ns.StatWeights
    H.eq(select(1, SW:Resolve("MAGE", "Тайная магия")), "CASTER_ARCANE",
        "аркан -> CASTER_ARCANE")
    H.eq(select(1, SW:Resolve("MAGE", "Огонь")), "CASTER_FIRE", "огонь -> CASTER_FIRE")
    H.eq(select(1, SW:Resolve("MAGE", "Лед")), "CASTER_FROST", "лёд -> CASTER_FROST")
    H.eq(select(1, SW:Resolve("WARLOCK", "Демонология")), "CASTER_SHADOW",
        "чернокнижник -> CASTER_SHADOW")
    -- With no spec the class default must not pick a school at random.
    H.eq(select(1, SW:Resolve("MAGE", nil)), "CASTER_DPS",
        "без специализации — школьно-нейтральный набор")
end

H.suite("Школы магии: несколько школ на одной вещи не складываются")
do
    -- An item giving +14 fire and +14 frost is worth about ONE +14, not two:
    -- the damage you actually deal splits over the schools you cast, and you do
    -- not cast both at once. Without this cap a six-school item would score as
    -- the best object in the game.
    local env = H.load()
    local ns = env.ns
    local S = ns.STAT
    local w = ns.StatWeights.SETS.CASTER_ARCANE
    local one = ns.StatWeights:Score({ [S.SPELLDMG_ARCANE] = 14 }, w)
    local many = ns.StatWeights:Score({ [S.SPELLDMG_ARCANE] = 14,
                                        [S.SPELLDMG_FIRE] = 14,
                                        [S.SPELLDMG_FROST] = 14 }, w)
    local naive = 14 * ((w[S.SPELLDMG_ARCANE] or 0) + (w[S.SPELLDMG_FIRE] or 0)
                        + (w[S.SPELLDMG_FROST] or 0))
    local generic = ns.StatWeights:Score({ [S.SPELLDMG] = 14 }, w)

    H.ok(many < naive * 0.75, string.format(
        "три школы по 14 не складываются: %.1f вместо наивных %.1f", many, naive))
    -- The cap is exactly right at this value: a bonus to every school you cast
    -- IS generic spell damage of the same size, and cannot beat it.
    H.near(many, generic, 0.01, string.format(
        "и ровно равны универсальной силе того же размера (%.1f)", generic))
    H.ok(many >= one, string.format(
        "но не меньше одной своей школы (%.1f против %.1f)", many, one))
end

-- =====================================================================
-- Reading the stats at all
-- =====================================================================

H.suite("Чтение характеристик: школьная сила магии доходит до оценки")
do
    local env = schoolEnv()
    local ns = env.ns

    local worn = ns.GearAdvisor:ItemStats(253957)
    H.ok(worn ~= nil, "характеристики надетого венца прочитаны")
    if worn then
        H.eq(worn[ns.STAT.STA], 10, "выносливость 10")
        H.eq(worn[ns.STAT.SPELLDMG_ARCANE], 11,
            "и тайная магия 11 — именно её раньше не было видно")
    end

    local pristine = ns.GearAdvisor:ItemStats(253975)
    H.ok(pristine ~= nil, "и у безупречного тоже")
    if pristine then
        H.eq(pristine[ns.STAT.SPELLDMG] or pristine[ns.STAT.SPELLPOWER], 8,
            "универсальная сила магии 8")
        H.eq(pristine[ns.STAT.HEALPOWER], 22, "лечение 22 прочитано (и весит ноль)")
    end
end

H.suite("Чтение характеристик: без внешней базы не врём о сравнении")
do
    -- No foreign item database: the client gives base stats only, so the equip
    -- bonuses of BOTH items are invisible. The only honest answer is "I cannot
    -- compare these", never a gain computed from half the stats.
    local env = schoolEnv { noForeign = true }
    local ns = env.ns
    local snap = ns.CharacterScanner:Get()
    local ups = ns.GearAdvisor:Upgrades(snap, ns.CraftingPlanner)
    for _, up in ipairs(ups) do
        H.ok(up.compare ~= "exact", string.format(
            "«%s»: сравнение не выдаётся за точное", tostring(up.info.name)))
        H.eq(up.gain, nil, "и прирост не называется числом")
    end
    H.ok(true, "улучшений предложено: " .. #ups .. " (все без заявленного прироста)")
end

-- =====================================================================
-- THE REGRESSION. The exact case that cost the player materials.
-- =====================================================================

H.suite("РЕГРЕСС: мага-аркана нельзя уговорить надеть безупречный венец")
do
    local env = schoolEnv()
    local ns = env.ns
    local snap = ns.CharacterScanner:Get()

    local sw = snap.weights
    local S = ns.STAT
    local scoreOf = function(id)
        return ns.StatWeights:Score(ns.GearAdvisor:ItemStats(id), sw)
    end
    local worn      = scoreOf(253957)   -- Pearly Circlet, spArcane11
    local pristine  = scoreOf(253975)   -- sp8 heal22
    local pearly    = scoreOf(253983)   -- spArcane14

    print(string.format("     надето %.2f | безупречный %.2f | жемчужный %.2f",
        worn, pristine, pearly))
    H.ok(pristine < worn, string.format(
        "безупречный (%.1f) ХУЖЕ надетого (%.1f) — раньше считался лучше на 16",
        pristine, worn))
    H.ok(pearly > worn, string.format(
        "жемчужный (%.1f) действительно лучше надетого (%.1f)", pearly, worn))
    H.ok(pearly > pristine, "и лучше безупречного")

    local ups = ns.GearAdvisor:Upgrades(snap, ns.CraftingPlanner)
    local byItem = {}
    for _, up in ipairs(ups) do byItem[up.info.itemID] = up end

    H.eq(byItem[253975], nil,
        "расшитый БЕЗУПРЕЧНЫЙ венец больше НЕ предлагается как улучшение")
    H.ok(byItem[253983] ~= nil,
        "расшитый ЖЕМЧУЖНЫЙ венец предложен")
    if byItem[253983] then
        H.eq(byItem[253983].targetSlot, "HEAD", "на слот головы")
        H.ok(byItem[253983].gain and byItem[253983].gain > 0,
            string.format("с настоящим приростом %.1f",
                byItem[253983].gain or 0))
    end
    -- And none of the off-school siblings may be offered to an arcane mage.
    for _, id in ipairs({ 253979, 253977, 253981, 253985 }) do
        H.eq(byItem[id], nil, "вариант другой школы (" .. id .. ") не предложен")
    end
end

H.suite("РЕГРЕСС: поножи и кушак — те же две отравленные карточки")
do
    local env = schoolEnv()
    local ns = env.ns
    local snap = ns.CharacterScanner:Get()
    local ups = ns.GearAdvisor:Upgrades(snap, ns.CraftingPlanner)
    local byItem = {}
    for _, up in ipairs(ups) do byItem[up.info.itemID] = up end

    H.eq(byItem[253937], nil,
        "расшитые безупречные поножи больше не предлагаются")
    H.eq(byItem[253885], nil,
        "кушак начинающего чародея (ilvl 15, sp4 heal4) больше не предлагается")

    -- The belt is the one slot where there IS a real upgrade.
    local sw = snap.weights
    local wornBelt = ns.StatWeights:Score(ns.GearAdvisor:ItemStats(2911), sw)
    local pearlyBelt = ns.StatWeights:Score(ns.GearAdvisor:ItemStats(253933), sw)
    local noviceBelt = ns.StatWeights:Score(ns.GearAdvisor:ItemStats(253885), sw)
    print(string.format("     пояс: надето %.2f | жемчужный %.2f | начинающего %.2f",
        wornBelt, pearlyBelt, noviceBelt))
    H.ok(pearlyBelt > wornBelt, "жемчужный кушак лучше Ремня Келлера")
    H.ok(pearlyBelt > noviceBelt, "и лучше кушака начинающего чародея")
    H.ok(byItem[253933] ~= nil, "именно он и предложен на пояс")
end

-- =====================================================================
-- Losses must be shown, never netted away
-- =====================================================================

H.suite("Просадки характеристик показываются, а не прячутся за плюсом")
do
    local env = schoolEnv()
    local ns = env.ns
    local snap = ns.CharacterScanner:Get()

    -- Compare the bad swap directly: it gains stamina and armour and loses the
    -- main stat. Even if the total came out positive, the card would have to
    -- say what went down.
    local cmp = ns.GearAdvisor:Compare(253957, 253975, snap.weights)
    H.ok(cmp ~= nil, "сравнение двух предметов доступно отдельным вызовом")
    if cmp then
        H.ok(#cmp.losses > 0, "просадки найдены")
        -- Generic spell damage and the school the character casts are ONE
        -- quantity: they feed the same spells. So the comparison reports the
        -- group - 11 arcane against 8 generic - rather than listing "−11
        -- arcane" next to "+8 generic", which reads as nonsense in both
        -- directions.
        local main
        for _, l in ipairs(cmp.losses) do
            if l.main then main = l end
        end
        H.ok(main ~= nil, "главная характеристика в списке просадок")
        if main then
            H.eq(main.from, 11, "было 11 (тайная магия надетого)")
            H.eq(main.to, 8, "стало 8 (универсальная сила нового)")
            H.eq(main.delta, -3, "итого −3 по главной характеристике")
            H.ok(ns.Util.contains(main.label, "магии"),
                "подписано как сила магии: " .. tostring(main.label))
        end
        H.eq(cmp.mainFrom, 11, "сумма главной характеристики надетого")
        H.eq(cmp.mainTo, 8, "и нового")
        H.ok(cmp.mainStatDrop == true,
            "просадка главной характеристики профиля помечена отдельно")
        H.ok(cmp.lossText and ns.Util.contains(cmp.lossText, "магии"),
            "и есть готовый текст для карточки: " .. tostring(cmp.lossText))
        -- Healing is not a loss and not a gain: it has no weight at all now.
        for _, l in ipairs(cmp.losses) do
            H.ok(l.stat ~= ns.STAT.HEALPOWER, "лечение не фигурирует как просадка")
        end
        for _, g in ipairs(cmp.gains) do
            H.ok(g.stat ~= ns.STAT.HEALPOWER, "и не фигурирует как прирост")
        end
    end
end

H.suite("Карточка улучшения перечисляет просадки")
do
    -- Build a case where the item really is better overall but still loses a
    -- weighted stat: more arcane damage, less stamina.
    local env = schoolEnv()
    local ns = env.ns
    env.foreignItemStats[253983] = { sta = 4, armor = 38, spArcane = 20 }
    env.stats[253983] = { ITEM_MOD_STAMINA_SHORT = 4 }
    ns.GearAdvisor:BeginPass()
    local cards = H.build(env)
    local card
    for _, c in ipairs(cards) do
        if c.kind == ns.KIND.CRAFT_GEAR and c.itemID == 253983 then card = c end
    end
    H.ok(card ~= nil, "карточка на жемчужный венец есть")
    if card then
        H.ok(ns.Util.contains(card.why, "−") or ns.Util.contains(card.why, "хуже")
             or ns.Util.contains(card.why, "просад"),
            "в объяснении показана просадка: " .. ns.Util.truncate(card.why, 160))
        H.ok(ns.Util.contains(card.why, "выносл"),
            "и названа именно выносливость: " .. ns.Util.truncate(card.why, 160))
    end
end

-- =====================================================================
-- Variant families
-- =====================================================================

H.suite("Семейство вариантов: выбирается вариант под специализацию")
do
    local env = schoolEnv()
    local ns = env.ns
    local snap = ns.CharacterScanner:Get()

    local fam = ns.GearAdvisor:SchoolFamily(253983, snap)
    H.ok(fam ~= nil, "семейство распознано")
    if fam then
        H.ok(fam.size >= 5, "в семействе " .. fam.size .. " вариантов")
        H.eq(fam.best, 253983, "лучший для аркана — жемчужный")
        H.ok(fam.text and ns.Util.contains(fam.text, "школ"),
            "и есть пояснение для карточки: " .. tostring(fam.text))
    end
end

H.suite("Семейство вариантов: для огневика выбор другой")
do
    local env = schoolEnv { spec = "Огонь" }
    local ns = env.ns
    local snap = ns.CharacterScanner:Get()
    H.eq(snap.weightSetKey, "CASTER_FIRE", "профиль огневика определён")
    local fam = ns.GearAdvisor:SchoolFamily(253977, snap)
    H.ok(fam ~= nil, "семейство распознано")
    if fam then
        H.eq(fam.best, 253977, "лучший для огня — пламенный")
    end
end

H.suite("Школа определяется по надетым вещам, когда спек не читается")
do
    -- No spec at all, which is the state at low level and on this client more
    -- often than not. The character is wearing arcane gear in three slots, so
    -- the arcane set is the honest answer - and picking the school-blind one
    -- instead is what let a healing robe through as an upgrade.
    local env = schoolEnv { spec = false }
    local ns = env.ns
    env.spec = nil
    local snap = ns.CharacterScanner:Scan()

    H.eq(snap.weightSetKey, "CASTER_ARCANE",
        "школа взята из экипировки: " .. tostring(snap.weightSetKey))
    H.eq(snap.weightSource, "gear", "и помечено, что источник — вещи, а не спек")
    H.eq(snap.weightConf, ns.CONF.ESTIMATE, "это оценка, не факт")

    local school, conf, detail = ns.StatWeights:InferSchoolFromGear(snap)
    H.eq(school, "ARCANE", "вывод: тайная магия")
    H.ok(detail and detail.counts and detail.counts.ARCANE > 0,
        "и видно, по каким числам: тайной "
        .. tostring(detail and detail.counts and detail.counts.ARCANE))
end

H.suite("Школа по вещам: при ничьей ничего не выдумываем")
do
    local env = schoolEnv()
    local ns = env.ns
    env.spec = nil
    -- Arcane 14 in one slot, fire 14 in another: no school is ahead.
    env.equipped.HEAD = { itemID = 253983 }   -- spArcane 14
    env.equipped.LEGS = { itemID = 253977 }   -- spFire 14
    env.equipped.WAIST = nil
    local snap = ns.CharacterScanner:Scan()
    local school = ns.StatWeights:InferSchoolFromGear(snap)
    H.eq(school, nil, "школу не выбрали — поровну")
    H.eq(snap.weightSetKey, "CASTER_DPS", "остался школьно-нейтральный набор")
end

H.suite("Школьно-нейтральный набор не обесценивает школьные вещи")
do
    -- The neutral set is the weak answer, but it must not be the WRONG answer:
    -- with the old off-school weight of 0.40 a generic item looked four times
    -- better per point than a school one, which is the shape of the bug.
    local env = H.load()
    local ns = env.ns
    local S = ns.STAT
    local w = ns.StatWeights.SETS.CASTER_DPS
    local school = w[S.SPELLDMG_ARCANE] or 0
    local generic = w[S.SPELLDMG] or 0
    H.ok(school > 0.5, string.format(
        "школьная сила весит %.2f — не мелочь", school))
    H.ok(school >= generic * 0.4, string.format(
        "и не в разы меньше универсальной (%.2f против %.2f)", school, generic))
    -- And the honest limit of the neutral set, stated rather than papered over.
    -- With the school genuinely unknown, a +8 generic bonus really IS worth
    -- slightly more in expectation than a +14 single-school one: the generic
    -- helps whatever the character casts, the school bonus helps it only if the
    -- school happens to match. So the two come out close, and neither is
    -- dismissed - which is all the neutral set is allowed to claim.
    local pearly = ns.StatWeights:Score({ [S.STA] = 12, [S.ARMOR] = 38,
                                          [S.SPELLDMG_ARCANE] = 14 }, w)
    local pristine = ns.StatWeights:Score({ [S.STA] = 12, [S.ARMOR] = 38,
                                            [S.SPELLDMG] = 8, [S.HEALPOWER] = 22 }, w)
    H.ok(math.abs(pearly - pristine) < pristine * 0.25, string.format(
        "без знания школы они близки, а не в разы (%.1f против %.1f)",
        pearly, pristine))
    -- The protection that actually matters: a swap involving school damage
    -- while the school is unknown is NOT offered as a measured upgrade.
    local env2 = schoolEnv()
    local ns2 = env2.ns
    env2.spec = nil
    -- Wear arcane in one slot only and keep the amount under the inference
    -- threshold, so the school honestly cannot be worked out.
    env2.equipped = { HEAD = { itemID = 253957 } }
    env2.foreignItemStats[253957] = { sta = 10, armor = 35, spArcane = 3 }
    local snap2 = ns2.CharacterScanner:Scan()
    H.eq(snap2.weightSetKey, "CASTER_DPS", "школа действительно не определилась")
    local ups = ns2.GearAdvisor:Upgrades(snap2, ns2.CraftingPlanner)
    for _, up in ipairs(ups) do
        if up.targetSlot == "HEAD" then
            H.ok(up.compare ~= "exact", string.format(
                "«%s»: при неизвестной школе прирост не выдаётся за измеренный",
                tostring(up.info.name)))
            H.ok(up.schoolUncertain == true,
                "и причина помечена: школа неизвестна, а в сравнении есть школьная магия")
        end
    end
    H.ok(true, "кандидатов на голову: " .. #ups)
end

H.suite("Проверка разумности: совет со просадкой главной характеристики")
do
    local env = schoolEnv()
    local ns = env.ns
    H.build(env)
    -- With the fix in place this must NOT fire: the bad swap is gone.
    local fired
    for _, e in ipairs(ns.Diag:Init().suspicious) do
        if e.code == "upgrade-drops-main-stat" then fired = e end
    end
    H.eq(fired, nil, "ни один совет не просаживает главную характеристику")
    H.ok(ns.SanityChecks:HasCheck("upgrade-drops-main-stat"),
        "но проверка на это зарегистрирована")
end

end
