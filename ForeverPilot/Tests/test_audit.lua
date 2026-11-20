-- ForeverPilot / Tests/test_audit.lua
--
-- Six confirmed discrepancies from an independent end-to-end audit, plus the
-- structural holes that let them through. Every fixture here is a real row:
-- Tests/fixtures/real_items.lua was copied verbatim out of the installed
-- Polestar_ItemDB and out of the player's own SavedVariables.
--
-- The structural finding matters as much as the six: the harness used to fake
-- the "independent" item database by mirroring the fake CLIENT's stat table,
-- and that mirror is built from a map with no school keys in it. So no amount
-- of testing could have caught the spArcane bug. Suites here use H.useRealItems,
-- which keeps the two halves genuinely separate.
local H = ...

return function()

local F = H.fixtures()
if not F then
    H.suite("Аудит: фикстуры")
    H.ok(false, "Tests/fixtures/real_items.lua не найден — проверки пропущены")
    return
end

-- =====================================================================
-- 1. A LOT PRICE PASSED OFF AS A UNIT PRICE
-- =====================================================================
--
-- Mastercraft's own Cost.lua says it in as many words:
--   [itemID] = { { q = how many, c = copper for them ALL, t = when,
--                  m = made by you }, ... }
-- The adapter read `c` and ignored `q`. For item 4338 the player's real lot is
-- q = 250, c = 124920, so the addon reported 12 gold 49 silver EACH for a
-- reagent that costs 4 silver 99 - a 250-fold error, and the audit found lots
-- up to 362.
--
-- `m` is worse than wrong, it is backwards: it marks the player's OWN crafting
-- cost. Using it as a market price means selling to yourself, and the sell path
-- then took the auction house's cut off it too.

H.suite("АУДИТ-1: цена партии делится на количество")
do
    local env = H.load()
    local ns = env.ns
    -- The real lots, verbatim.
    env.foreignDB = {
        costs = { ["eu-pvp-Horde"] = F.COST_LOTS },
    }
    -- Restore the production reader: this is the function under test.
    ns.Api.MastercraftObservedPrice = env.real.MastercraftObservedPrice

    local lots = F.COST_LOTS[4338]
    H.ok(lots ~= nil, "реальная партия по предмету 4338 есть в фикстуре")
    if lots then
        local lot = lots[1]
        H.ok(lot.q and lot.q > 1, "в партии " .. tostring(lot.q) .. " штук")
        local price, conf = ns.Api:MastercraftObservedPrice(4338, "eu-pvp-Horde")
        local expected = lot.c / lot.q
        H.ok(price ~= nil, "цена получена")
        if price then
            H.near(price, expected, 1, string.format(
                "цена за ШТУКУ %.0f, а не за всю партию %d", expected, lot.c))
            H.ok(price < lot.c / 2, string.format(
                "и это точно не %s за штуку", ns.Util.money(lot.c)))
        end
    end
end

H.suite("АУДИТ-1: «сделано мной» — не рыночная цена")
do
    local env = H.load()
    local ns = env.ns
    ns.Api.MastercraftObservedPrice = env.real.MastercraftObservedPrice

    -- Find a real lot flagged as the player's own craft.
    local madeID, madeLot
    for itemID, lots in pairs(F.COST_LOTS) do
        for _, lot in pairs(lots) do
            if lot.m then madeID, madeLot = itemID, lot end
        end
    end
    H.ok(madeID ~= nil, "в фикстуре есть партия с флагом «сделано мной»: "
        .. tostring(madeID))
    if madeID then
        env.foreignDB = { costs = { ["eu-pvp-Horde"] = { [madeID] = { madeLot } } } }
        local price = ns.Api:MastercraftObservedPrice(madeID, "eu-pvp-Horde")
        H.eq(price, nil,
            "своя себестоимость не выдаётся за рыночную цену")
    end
end

H.suite("АУДИТ-1: расхождение с аукционом — подозрение")
do
    local env = H.load()
    local ns = env.ns
    H.item(env, 4338, { name = "Магическая ткань", sellPrice = 30 })
    H.item(env, 700, { name = "Изделие", sellPrice = 10 })
    env.prices[4338] = 148            -- what Auctionator says
    env.observedPrices = { [4338] = 50000 }   -- a foreign observation 338x higher
    env.money = 50000
    H.profession(env, "Портняжное дело", 225, 225, {
        H.recipe { id = 70, output = 700, reagents = { { itemID = 4338, qty = 1 } },
                   name = "Изделие", diff = "trivial", category = "Обувь" },
    })
    H.build(env)
    local found
    for _, e in ipairs(ns.Diag:Init().suspicious) do
        if e.code == "foreign-price-disagrees" then found = e end
    end
    H.ok(found ~= nil,
        "расхождение чужого наблюдения с аукционом помечено подозрением")
end

-- =====================================================================
-- 2. THE RANGE SENTENCE WAS FALSE
-- =====================================================================
--
-- Straight off the player's screen:
--   "Розовая рубашка: 2з 85с укладывается в наблюдённый разброс 3з 49с..3з 49с"
--   "Рубашка под смокинг: 2з 50с укладывается в 2з 51с..2з 51с"
-- Neither price is inside its range. The outlier branch only fires past five
-- times the maximum, so everything short of that was called typical and the
-- sentence was printed anyway. And "3з 49с..3з 49с" is one observation dressed
-- up as a range.

local function historyEnv(itemID, days)
    local env = H.load()
    local cfg = env.ns.Config:Get()
    cfg.priceHistory[itemID] = {}
    for day, copper in pairs(days) do cfg.priceHistory[itemID][day] = copper end
    return env
end

H.suite("АУДИТ-2: цена вне разброса не называется «укладывается»")
do
    -- The real numbers from the Pink Magecloth Shirt card: one observation at
    -- 3з 49с, a live price of 2з 85с.
    local env = historyEnv(777, { [20774] = 34900 })
    local ns = env.ns
    local v = ns.MarketHistory:Verdict(777, 28500)
    H.ok(not ns.Util.contains(v.text, "укладывается"),
        "не утверждаем, что укладывается: " .. tostring(v.text))
    H.ok(ns.Util.contains(v.text, "ниже") or ns.Util.contains(v.text, "вне"),
        "сказано, что цена вне наблюдённого: " .. tostring(v.text))
    H.eq(v.outsideRange, true, "флаг «вне разброса» выставлен")
    H.eq(v.belowRange, true, "и именно ниже")

    -- Confidence must drop: we are extrapolating past everything we saw.
    local use, conf, note = ns.MarketHistory:Expected(777, 28500)
    H.eq(use, 28500, "цену не подменяем — это не выброс, просто ниже наблюдённого")
    H.eq(conf, ns.CONF.ESTIMATE, "но достоверность понижена до оценки")
    H.ok(note and not ns.Util.contains(note, "укладывается"),
        "и в пояснении нет ложного «укладывается»: " .. tostring(note))
end

H.suite("АУДИТ-2: вырожденный разброс не выдаётся за диапазон")
do
    local env = historyEnv(778, { [20774] = 25100 })
    local ns = env.ns
    local v = ns.MarketHistory:Verdict(778, 25100)
    H.ok(not v.text:find("25100"), "не печатаем сырые медяки")
    H.ok(not ns.Util.contains(v.text, "разброс"),
        "при одном наблюдении слова «разброс» нет: " .. tostring(v.text))
    H.ok(ns.Util.contains(v.text, "единственное наблюдение")
         or ns.Util.contains(v.text, "наблюдение всего одно"),
        "сказано, что наблюдение одно: " .. tostring(v.text))
    H.eq(v.degenerate, true, "флаг вырожденной выборки выставлен")
end

H.suite("АУДИТ-2: цена внутри разброса по-прежнему так и называется")
do
    -- The two honest cards from the same screen: 3з 19с inside 1з 75с..3з 38с.
    local env = historyEnv(779, { [20772] = 17500, [20773] = 33800, [20774] = 25000 })
    local ns = env.ns
    local v = ns.MarketHistory:Verdict(779, 31900)
    H.ok(ns.Util.contains(v.text, "укладывается"),
        "внутри разброса — «укладывается»: " .. tostring(v.text))
    H.eq(v.outsideRange, false, "флага «вне разброса» нет")
    local _, conf = ns.MarketHistory:Expected(779, 31900)
    H.eq(conf, nil, "и достоверность не понижается без причины")
end

H.suite("АУДИТ-2: карточка не печатает ложное «укладывается»")
do
    local env = historyEnv(780, { [20774] = 34900 })
    local ns = env.ns
    H.item(env, 780, { name = "Розовая рубашка", sellPrice = 300 })
    H.item(env, 781, { name = "Материал", sellPrice = 10 })
    env.vendorPrices[781] = 100
    env.prices[780] = 28500
    env.money = 500000
    H.profession(env, "Портняжное дело", 225, 225, {
        H.recipe { id = 80, output = 780, reagents = { { itemID = 781, qty = 1 } },
                   name = "Розовая рубашка", diff = "trivial", category = "Рубашки" },
    })
    local cards = H.build(env)
    local card
    for _, c in ipairs(cards) do
        if c.kind == ns.KIND.CRAFT_PROFIT then card = c end
    end
    H.ok(card ~= nil, "карточка есть")
    if card then
        H.ok(not ns.Util.contains(card.why, "укладывается"),
            "в карточке нет ложного «укладывается»: " .. ns.Util.truncate(card.why, 140))
    end
end

-- =====================================================================
-- 3. THE GENERIC MEMBER FELL OUT OF ITS OWN FAMILY
-- =====================================================================
--
-- All six ilvl-30 circlets are learned. The addon said "семейство из 5" and
-- gave the one the player is wearing - 253975, the generic one - no family at
-- all. The signature included sp and heal, which are exactly the stats that
-- vary across the family, so the generic member could never match.

local CIRCLETS = { 253975, 253977, 253979, 253981, 253983, 253985 }

local function familyEnv()
    local env = H.load()
    env.player.classFile = "MAGE"
    env.spec = "Тайная магия"
    env.money = 500000
    H.useRealItems(env, CIRCLETS)
    H.useRealRecipes(env, CIRCLETS)
    -- Reagents for the real recipes.
    for _, r in ipairs(F.RECIPES) do
        for _, g in ipairs(r.reagents or {}) do
            H.item(env, g.itemID, { name = "Материал " .. g.itemID, sellPrice = 5 })
            env.prices[g.itemID] = 50
            env.bags[g.itemID] = 500
        end
    end
    env.equipped.HEAD = { itemID = 253975 }
    H.useRealItems(env, { 253975 })
    H.rescan(env)
    env.ns.PriceProvider:BeginPass()
    env.ns.CraftingPlanner:Bind(env.ns.RecipeBook, env.ns.PriceProvider):BeginPass()
    env.ns.GearAdvisor:BeginPass()
    return env
end

H.suite("АУДИТ-3: в семействе все шесть вариантов")
do
    local env = familyEnv()
    local ns = env.ns
    local snap = ns.CharacterScanner:Get()

    local fam = ns.GearAdvisor:SchoolFamily(253983, snap)
    H.ok(fam ~= nil, "семейство найдено")
    if fam then
        H.eq(fam.size, 6, "шесть вариантов, а не пять")
        local ids = {}
        for _, m in ipairs(fam.members) do ids[m.itemID] = true end
        for _, id in ipairs(CIRCLETS) do
            H.ok(ids[id], "в семье есть " .. id)
        end
        H.eq(fam.best, 253983, "лучший для аркана — жемчужный 253983")
    end
end

H.suite("АУДИТ-3: универсальный член тоже имеет семью")
do
    local env = familyEnv()
    local ns = env.ns
    local snap = ns.CharacterScanner:Get()
    local fam = ns.GearAdvisor:SchoolFamily(253975, snap)
    H.ok(fam ~= nil, "у 253975 (sp8 heal22) семья есть, а не nil")
    if fam then
        H.eq(fam.size, 6, "и в ней те же шесть")
        H.eq(fam.best, 253983, "а лучший всё равно жемчужный")
        H.ok(fam.text and ns.Util.contains(fam.text, "школ"),
            "и есть текст для карточки")
    end
end

-- =====================================================================
-- 4. TWO DIFFERENT ITEMS, ONE NAME
-- =====================================================================
--
-- Exactly one name collision among the player's 265 learned recipes, and it is
-- on the item they are wearing: "Расшитый безупречный венец" is both 253975
-- (sp8 heal22) and 253979 (spFire14). Advice that names the item without the
-- id is ambiguous precisely where it matters most.

H.suite("АУДИТ-4: коллизия имён существует в реальных данных")
do
    local byName = {}
    for _, r in ipairs(F.RECIPES) do
        byName[r.name] = byName[r.name] or {}
        local list = byName[r.name]
        local seen = false
        for _, id in ipairs(list) do if id == r.output then seen = true end end
        if not seen then list[#list + 1] = r.output end
    end
    local collisions = 0
    for _, list in pairs(byName) do
        if #list > 1 then collisions = collisions + 1 end
    end
    H.ok(collisions >= 1, "в фикстуре есть хотя бы одна коллизия имён")
    local pristine = F.RU_NAMES[253975]
    local flame = F.RU_NAMES[253979]
    H.ok(pristine ~= nil and pristine == flame, string.format(
        "253975 и 253979 носят одно имя: «%s» / «%s»",
        tostring(pristine), tostring(flame)))
end

H.suite("АУДИТ-4: одинаковые имена различаются в тексте")
do
    local env = familyEnv()
    local ns = env.ns
    -- The player is wearing 253975; both it and 253979 share a name.
    local label975 = ns.GearAdvisor:ItemLabel(253975)
    local label979 = ns.GearAdvisor:ItemLabel(253979)
    H.ok(label975 ~= label979, string.format(
        "ярлыки различаются: «%s» против «%s»", tostring(label975), tostring(label979)))
    H.ok(ns.Util.contains(label975, "253975") or ns.Util.contains(label975, "тайн")
         or ns.Util.contains(label975, "лечен") or ns.Util.contains(label975, "универс"),
        "и ярлык говорит, какой именно это предмет: " .. tostring(label975))

    -- An item whose name is unique keeps its plain name.
    local plain = ns.GearAdvisor:ItemLabel(253983)
    H.ok(plain ~= nil and plain ~= "", "у уникального имени ярлык есть")
end

H.suite("АУДИТ-4: карточка на спорное имя не двусмысленна")
do
    local env = familyEnv()
    local ns = env.ns
    local cards = H.build(env)
    for _, c in ipairs(cards) do
        if c.kind == ns.KIND.CRAFT_GEAR and c.itemID then
            -- Whenever the name is shared, the card has to carry something that
            -- tells the two apart.
            local shared = false
            for _, other in pairs(F.RU_NAMES) do
                if other == F.RU_NAMES[c.itemID] then shared = shared end
            end
            local n = 0
            for id, name in pairs(F.RU_NAMES) do
                if name == F.RU_NAMES[c.itemID] then n = n + 1 end
            end
            if n > 1 then
                H.ok(ns.Util.contains(c.title .. c.why, tostring(c.itemID))
                     or ns.Util.contains(c.why, "школ"),
                    "карточка «" .. ns.Util.truncate(c.title, 40)
                    .. "» различает предметы с одним именем")
            end
        end
    end
    H.ok(true, "проверено карточек: " .. #cards)
end

-- =====================================================================
-- 5. WEAPON DAMAGE WAS NOT READ AT ALL
-- =====================================================================
--
-- The addon said "характеристики клиент не отдаёт" about the player's wand,
-- while the database holds dmin36 dmax67 speed1900 for it - a wand whose only
-- stat IS its damage. The candidate it offered instead was worse: 25.4 damage
-- per second against 27.1.

H.suite("АУДИТ-5: урон и скорость оружия читаются")
do
    local env = H.load()
    local ns = env.ns
    H.useRealItems(env, { 13062, 5198, 249392 })
    H.rescan(env)
    ns.GearAdvisor:BeginPass()

    local worn = ns.GearAdvisor:ItemStats(13062)
    H.ok(worn ~= nil, "характеристики надетой палочки прочитаны")
    if worn then
        H.ok(worn[ns.STAT.DPS] ~= nil, "урон в секунду есть среди характеристик")
        -- (36 + 67) / 2 / 1.9 = 27.1
        H.near(worn[ns.STAT.DPS], 27.1, 0.1, "и он равен 27.1")
    end

    local rod = ns.GearAdvisor:ItemStats(5198)
    H.ok(rod and rod[ns.STAT.DPS] ~= nil, "и у второй палочки тоже")
    if rod and rod[ns.STAT.DPS] then
        H.ok(rod[ns.STAT.DPS] < worn[ns.STAT.DPS], string.format(
            "кандидат слабее надетого: %.1f против %.1f",
            rod[ns.STAT.DPS], worn[ns.STAT.DPS]))
    end
end

H.suite("АУДИТ-5: более слабая палочка не предлагается")
do
    local env = H.load()
    local ns = env.ns
    env.player.classFile = "MAGE"
    env.spec = "Тайная магия"
    env.money = 500000
    H.useRealItems(env, { 13062, 5198 })
    H.item(env, 9001, { name = "Материал", sellPrice = 5 })
    env.prices[9001] = 50
    env.bags[9001] = 100
    env.equipped.RANGED = { itemID = 13062 }
    H.profession(env, "Портняжное дело", 225, 225, {
        H.recipe { id = 90, output = 5198, reagents = { { itemID = 9001, qty = 1 } },
                   name = "Поварешка", diff = "trivial", category = "Палочки" },
    })
    H.rescan(env)
    ns.PriceProvider:BeginPass()
    ns.CraftingPlanner:Bind(ns.RecipeBook, ns.PriceProvider):BeginPass()
    ns.GearAdvisor:BeginPass()
    local snap = ns.CharacterScanner:Get()
    local ups = ns.GearAdvisor:Upgrades(snap, ns.CraftingPlanner)
    for _, up in ipairs(ups) do
        H.ok(up.info.itemID ~= 5198,
            "палочка с меньшим уроном не предложена как улучшение")
    end
    H.ok(true, "кандидатов: " .. #ups)
end

H.suite("АУДИТ-5: вес урона в секунду задан для всех профилей")
do
    local env = H.load()
    local ns = env.ns
    local S = ns.STAT
    H.ok(S.DPS ~= nil, "характеристика «урон в секунду» существует")
    for _, key in ipairs({ "CASTER_ARCANE", "MELEE_DPS", "HYBRID_PHYS", "TANK" }) do
        local set = ns.StatWeights.SETS[key]
        H.ok((set[S.DPS] or 0) > 0, key .. ": урон в секунду имеет вес")
    end
    H.ok((ns.StatWeights.SETS.MELEE_DPS[S.DPS] or 0)
         > (ns.StatWeights.SETS.CASTER_ARCANE[S.DPS] or 0),
        "ближнему бою урон оружия важнее, чем магу")
end

-- =====================================================================
-- 6. A DOUBLE WALK REPORTED AS 704 MISMATCHES
-- =====================================================================
--
-- The source check looked up byProfession["Tailoring"], which is nil because
-- the book is keyed by the localised name, and then fell back to scanning every
-- profession. Twice, once per English profession name. So every recipe was
-- compared twice and `wrongProfession` came out at exactly the size of the
-- comparison itself - 704 - while the comparison it was warning about had zero
-- real disagreements.

H.suite("АУДИТ-6: сверка не ходит по списку дважды")
do
    local env = H.load()
    local ns = env.ns
    -- The book keyed the way the real one is: each recipe under the LOCALISED
    -- profession name the player's own client gave it. Putting them all in one
    -- bucket would itself manufacture "wrong profession" findings.
    local ids = {}
    for _, r in ipairs(F.RECIPES) do ids[#ids + 1] = r.output end
    local stored, byProf = H.useRealRecipes(env, ids)
    H.ok(stored > 0, stored .. " реальных рецептов в книге")
    local profCount = 0
    for _ in pairs(byProf) do profCount = profCount + 1 end
    H.ok(profCount >= 2, profCount .. " профессии, как в жизни")

    local result = ns.SourceCheck:CheckRecipes()
    H.ok(result ~= nil, "сверка выполнилась")
    if result then
        H.eq(result.wrongProfession, 0,
            "ложных «не та профессия» нет (было 704)")
        H.ok((result.compared or 0) > 0,
            "и сверено по делу: " .. tostring(result.compared))
        -- The shape of the old defect: the false count was exactly the size of
        -- the comparison itself, because every recipe was walked twice.
        H.ok((result.wrongProfession or 0) < (result.compared or 1),
            "счётчик расхождений больше не равен размеру самой сверки")
        H.ok((result.compared or 0) + (result.skippedNoReagents or 0) <= stored,
            string.format("каждый рецепт посмотрели один раз: сверено %d + пропущено %d <= %d",
                result.compared or 0, result.skippedNoReagents or 0, stored))
    end
end

H.suite("АУДИТ-6: профессия находится по русскому имени")
do
    local env = H.load()
    local ns = env.ns
    ns.RecipeBook:Store("Портняжное дело", {
        { id = 1, name = "Тест", learned = true, output = 1,
          reagents = { { itemID = 2, qty = 1 } } },
    }, "stored", ns.CONF.CACHED, H.serverTime)
    ns.RecipeBook:Reindex()
    H.ok(ns.RecipeBook:Bucket("Tailoring") ~= nil,
        "книга находит Tailoring по русскому ведру")
    H.ok(ns.RecipeBook:Bucket("Портняжное дело") ~= nil, "и по русскому имени")
end

-- =====================================================================
-- STRUCTURAL: the mirror, and the mutations that must be caught
-- =====================================================================

H.suite("СТРУКТУРА: фальшивая база независима от фальшивого клиента")
do
    local env = H.load()
    local ns = env.ns
    H.useRealItems(env, { 253983 })   -- sta12 armor38 spArcane14
    ns.GearAdvisor:BeginPass()

    -- The client half must NOT contain the school stat...
    local raw = ns.Api:ItemStatsRaw(253983)
    local fromClient = ns.StatWeights:Canonical(raw)
    H.ok(fromClient ~= nil, "клиент отдал базовые характеристики")
    H.eq(fromClient and fromClient[ns.STAT.SPELLDMG_ARCANE], nil,
        "и школьной магии среди них нет — как в игре")

    -- ...while the database half must.
    local foreign = ns.Api:ForeignItemStats(253983)
    H.ok(foreign ~= nil, "база отдала строку")
    H.eq(foreign and foreign.spArcane, 14,
        "и в ней есть spArcane 14 — зеркало из клиента такого выдать не могло")

    -- Which is the whole point: the merged answer has the school stat.
    local merged = ns.GearAdvisor:ItemStats(253983)
    H.eq(merged and merged[ns.STAT.SPELLDMG_ARCANE], 14,
        "в итоговых характеристиках школьная магия есть")
end

H.suite("СТРУКТУРА: словарь характеристик покрывает реальную базу")
do
    -- Deleting a mapping is a silent, invisible loss of a stat - which is how
    -- the schools were lost. This asserts the mapping against every token that
    -- actually appears in the real data, so a deletion fails the suite.
    local env = H.load()
    local ns = env.ns
    local keys = F.AllStatKeys()
    local KNOWN_UNMAPPED = { hp5 = true }
    local missing = {}
    local n = 0
    for key in pairs(keys) do
        n = n + 1
        if not ns.StatWeights.FOREIGN_KEY_TO_STAT[key] and not KNOWN_UNMAPPED[key] then
            missing[#missing + 1] = key
        end
    end
    table.sort(missing)
    H.ok(n >= 25, n .. " разных характеристик встречается в реальных строках")
    H.eq(#missing, 0, "все они понятны аддону"
        .. (#missing > 0 and (": не хватает " .. table.concat(missing, ", ")) or ""))
end

H.suite("МУТАЦИЯ: снятие вето главного стата ловится")
do
    -- THE CASE HAS TO BE CHOSEN CAREFULLY, and the first attempt at this suite
    -- was useless: it paired the worn Pearly Circlet against an item with a
    -- LOWER total, so the score ordering rejected the candidate on its own and
    -- the veto never ran. Deleting the veto changed nothing and the suite still
    -- passed - exactly the kind of hollow test the audit was complaining about.
    --
    -- This pair is real and it is the right shape: item 10751 is a cloth head
    -- piece (agi5 sta9 int17 spi18 armor63) worth MORE in total than the worn
    -- 253957 (sta10 armor35 spArcane11), while its spell power is zero. The
    -- total goes up, the thing an arcane mage exists for goes to nothing, and
    -- the veto is the only thing between the player and another wasted craft.
    local env = H.load()
    local ns = env.ns
    env.player.classFile = "MAGE"
    env.player.level = 60
    env.spec = "Тайная магия"
    env.money = 500000
    H.useRealItems(env, { 253957, 10751 })
    H.item(env, 9002, { name = "Материал", sellPrice = 5 })
    env.prices[9002] = 10
    env.bags[9002] = 100
    env.equipped.HEAD = { itemID = 253957 }
    H.profession(env, "Портняжное дело", 225, 225, {
        H.recipe { id = 95, output = 10751, reagents = { { itemID = 9002, qty = 1 } },
                   name = "Чужая шапка", diff = "trivial", category = "Капюшоны" },
    })
    H.rescan(env)
    ns.PriceProvider:BeginPass()
    ns.CraftingPlanner:Bind(ns.RecipeBook, ns.PriceProvider):BeginPass()
    ns.GearAdvisor:BeginPass()
    local snap = ns.CharacterScanner:Get()

    -- The precondition: without the veto this WOULD be offered, because the
    -- total really is higher. If this assertion ever fails the suite has gone
    -- hollow again and the veto is no longer being exercised.
    local wornScore = ns.StatWeights:Score(
        ns.GearAdvisor:ItemStats(253957) or {}, snap.weights)
    local candScore = ns.StatWeights:Score(
        ns.GearAdvisor:ItemStats(10751) or {}, snap.weights)
    H.ok(candScore > wornScore, string.format(
        "ПРЕДУСЛОВИЕ: по сумме кандидат выше надетого (%.2f против %.2f),"
        .. " иначе вето не проверяется", candScore, wornScore))

    local cmp = ns.GearAdvisor:Compare(253957, 10751, snap.weights, snap.weightSetKey)
    H.ok(cmp ~= nil, "сравнение посчитано")
    if cmp then
        H.ok(cmp.mainStatDrop == true, string.format(
            "главная характеристика падает: %d → %d", cmp.mainFrom, cmp.mainTo))
        H.ok((cmp.total or 0) > 0, string.format(
            "а итог при этом растёт (+%.2f) — ровно та ловушка", cmp.total or 0))
    end

    local ups = ns.GearAdvisor:Upgrades(snap, ns.CraftingPlanner)
    for _, up in ipairs(ups) do
        H.ok(up.info.itemID ~= 10751,
            "вещь без силы магии не предложена магу как улучшение,"
            .. " хотя по сумме она выше")
    end
    H.eq(#ups, 0, "ни одного улучшения — и это правильный ответ")
end

H.suite("МУТАЦИЯ: приоритет источников в Merge ловится")
do
    -- The live client wins for the stats it reports; the cached database fills
    -- the rest. Flipping that makes the addon trust a weeks-old copy over the
    -- game, and nothing used to notice.
    local env = H.load()
    local ns = env.ns
    local raw = { ITEM_MOD_STAMINA_SHORT = 12 }
    local foreign = { sta = 99, spArcane = 14 }
    local merged, conf, info = ns.StatWeights:Merge(raw, foreign)
    H.ok(merged ~= nil, "слияние состоялось")
    H.eq(merged[ns.STAT.STA], 12,
        "выносливость взята у КЛИЕНТА (12), а не из кеша (99)")
    H.eq(merged[ns.STAT.SPELLDMG_ARCANE], 14,
        "а школьная магия — из базы, клиент её не отдаёт")
    H.eq(info.complete, true, "и слияние помечено полным")
end

H.suite("МУТАЦИЯ: охранник двуручного оружия ловится")
do
    -- A two-hander frees the off hand, so it has to be compared against both
    -- hands together. Comparing it against the main hand alone makes a weak
    -- staff look like an upgrade over a decent weapon plus an off-hand.
    local env = H.load()
    local ns = env.ns
    env.player.classFile = "MAGE"
    env.player.level = 60
    env.money = 500000
    H.item(env, 9010, { name = "Кинжал", equipLoc = "INVTYPE_WEAPONMAINHAND",
                        classID = 2, subclassID = 15 })
    env.stats[9010] = { ITEM_MOD_INTELLECT_SHORT = 4 }
    H.item(env, 9011, { name = "Книга", equipLoc = "INVTYPE_HOLDABLE",
                        classID = 4, subclassID = 0 })
    env.stats[9011] = { ITEM_MOD_INTELLECT_SHORT = 10 }
    H.item(env, 9012, { name = "Посох", equipLoc = "INVTYPE_2HWEAPON",
                        classID = 2, subclassID = 10 })
    env.stats[9012] = { ITEM_MOD_INTELLECT_SHORT = 6 }
    H.item(env, 9013, { name = "Дерево", sellPrice = 1 })
    env.prices[9013] = 10
    env.bags[9013] = 10
    env.equipped.MAINHAND = { itemID = 9010 }
    env.equipped.OFFHAND = { itemID = 9011 }
    H.profession(env, "Портняжное дело", 225, 225, {
        H.recipe { id = 96, output = 9012, reagents = { { itemID = 9013, qty = 1 } },
                   name = "Посох", diff = "trivial", category = "Посохи" },
    })
    H.rescan(env)
    ns.PriceProvider:BeginPass()
    ns.CraftingPlanner:Bind(ns.RecipeBook, ns.PriceProvider):BeginPass()
    ns.GearAdvisor:BeginPass()
    local snap = ns.CharacterScanner:Get()

    -- The explicit contract, not just the outcome: both hands are displaced.
    local target, score, _, displaced =
        ns.GearAdvisor:DisplacedValue("TWOHAND", snap, snap.weights)
    H.eq(#displaced, 2, "двуручное снимает два слота")
    H.near(score, 14, 0.001, "и стоит обе руки вместе: 4 + 10 = 14")

    local ups = ns.GearAdvisor:Upgrades(snap, ns.CraftingPlanner)
    H.eq(#ups, 0, "посох на 6 не улучшение против 14")
end

H.suite("СТРУКТУРА: причина промаха базы названа точно")
do
    -- "внешней базы предметов нет" is false when the database is there and
    -- working for every other item on screen. Three different facts, three
    -- different sentences.
    local env = H.load()
    local ns = env.ns
    H.useRealItems(env, { 253983 })
    -- An item the client knows and the database does not.
    H.item(env, 999001, { name = "Новый предмет", equipLoc = "INVTYPE_HEAD",
                          classID = 4, subclassID = 1, reqLevel = 1 })
    env.stats[999001] = { ITEM_MOD_STAMINA_SHORT = 5 }
    ns.GearAdvisor:BeginPass()

    local _, _, info = ns.GearAdvisor:ItemStats(999001)
    H.ok(info ~= nil, "сведения о слиянии получены")
    H.eq(info and info.missingBonuses, true, "бонусы не прочитаны")
    H.eq(info and info.missReason, "not-in-db",
        "и причина — предмета нет в базе, а не «базы нет»")

    H.build(env)
    local found
    for _, e in ipairs(ns.Diag:Init().suspicious) do
        if e.code == "item-bonuses-unreadable" then found = e end
    end
    if found then
        H.ok(not ns.Util.contains(found.text, "внешней базы предметов нет"),
            "в тексте нет ложного «базы нет»: " .. ns.Util.truncate(found.text, 120))
        H.ok(ns.Util.contains(found.text, "нет в базе")
             or ns.Util.contains(found.text, "не нашлось"),
            "сказана точная причина: " .. ns.Util.truncate(found.text, 120))
    else
        H.ok(true, "подозрение не выставлено (бонусов не ждут от этого предмета)")
    end
end

-- =====================================================================
-- HIDING MUST NOT HAPPEN BY ACCIDENT
-- =====================================================================
--
-- The player has now hidden a pile of advice unintentionally TWICE, and the
-- second time it cost them the thing all of this was for: the corrected gear
-- advice was on screen and they never saw it, because ten cards were sitting
-- in `dismissed`. One stray right-click used to hide a card for a day.

H.suite("СКРЫТИЕ: один правый щелчок не скрывает")
do
    local env = H.load()
    local ns = env.ns
    local card = { key = "test:1", title = "Тестовый совет" }

    ns.Dismissal:Disarm()
    local first = (ns.Dismissal:Request(card) ~= "blocked")
    H.ok(first, "первый щелчок принят")
    H.eq(ns.Config:IsDismissed("test:1", ns.Api:ServerTime()), false,
        "но карточка НЕ скрыта")
    H.ok(ns.Dismissal:IsArmed(card.key), "она только взята на прицел")

    local second = (ns.Dismissal:Request(card) ~= "blocked")
    H.ok(second, "второй щелчок подтверждает")
    H.eq(ns.Config:IsDismissed("test:1", ns.Api:ServerTime()), true,
        "и теперь скрыта")
    H.ok(not ns.Dismissal:IsArmed(card.key), "прицел снят")
end

H.suite("СКРЫТИЕ: прицел снимается другим действием и временем")
do
    local env = H.load()
    local ns = env.ns
    local card = { key = "test:2", title = "Второй" }

    ns.Dismissal:Request(card)
    H.ok(ns.Dismissal:IsArmed(card.key), "взята на прицел")
    ns.Dismissal:Disarm()
    H.ok(not ns.Dismissal:IsArmed(card.key), "любое другое действие снимает прицел")
    H.eq(ns.Config:IsDismissed("test:2", ns.Api:ServerTime()), false, "и не скрывает")

    -- And the window expires on its own.
    ns.Dismissal:Request(card)
    H.ok(ns.Dismissal:IsArmed(card.key), "снова на прицеле")
    H.clock = H.clock + ns.Dismissal.CONFIRM_SECONDS + 1
    H.ok(not ns.Dismissal:IsArmed(card.key), "через паузу прицел истёк сам")
    -- So the next click arms again rather than hiding.
    ns.Dismissal:Request(card)
    H.eq(ns.Config:IsDismissed("test:2", ns.Api:ServerTime()), false,
        "и щелчок после паузы снова только прицеливается")
end

H.suite("СКРЫТИЕ: отмена последнего — один шаг")
do
    local env = H.load()
    local ns = env.ns
    local card = { key = "test:3", title = "Третий" }
    ns.Dismissal:Disarm()
    ns.Dismissal:Request(card)
    ns.Dismissal:Request(card)
    H.eq(ns.Config:IsDismissed("test:3", ns.Api:ServerTime()), true, "скрыто")

    local last = ns.Config:LastDismiss()
    H.ok(last ~= nil, "последнее скрытие запомнено")
    H.eq(last and last.key, "test:3", "и это именно он")

    local undone = (ns.Dismissal:UndoLast())
    H.ok(undone ~= nil, "отмена сработала")
    H.eq(ns.Config:IsDismissed("test:3", ns.Api:ServerTime()), false,
        "карточка вернулась")
    H.eq(ns.Config:LastDismiss(), nil, "и повторная отмена уже нечего отменять")
end

H.suite("СКРЫТИЕ: правый щелчок по панели убирает на час, а не на сутки")
do
    -- Раньше набор назывался «„Понятно“ убирает на час»: так прятал левый
    -- щелчок по информационному совету. Тот путь убран целиком - щелчок, у
    -- которого нет подписи, ничего прятать не должен (Tests/test_text.lua).
    -- Короткий срок остался у единственного места, которое им пользуется:
    -- у правого щелчка по панели, и это тот же вызов Dismissal:Hide.
    local env = H.load()
    local ns = env.ns
    local card = { key = "test:4", title = "Информационный",
                   action = { kind = "noop" } }
    ns.Dismissal:Hide(card, ns.SNOOZE_SECONDS)
    local _, until_ = ns.Config:IsDismissed("test:4", ns.Api:ServerTime())
    H.ok(until_ ~= nil, "скрыто")
    if until_ then
        local left = until_ - ns.Api:ServerTime()
        H.near(left, ns.SNOOZE_SECONDS, 2, "на час (" .. tostring(left) .. " с)")
        H.ok(left < ns.DISMISS_SECONDS, "а не на сутки")
    end
end

H.suite("СКРЫТИЕ: блокирующую карточку не скрыть и с подтверждением")
do
    local env = H.load()
    local ns = env.ns
    local card = { key = "test:5", title = "Важное", blocking = true }
    ns.Dismissal:Disarm()
    H.eq(select(1, ns.Dismissal:Request(card)), "blocked", "первый щелчок отклонён")
    H.eq(select(1, ns.Dismissal:Request(card)), "blocked", "и второй тоже")
    H.eq(ns.Config:IsDismissed("test:5", ns.Api:ServerTime()), false, "не скрыта")
end

H.suite("СТРУКТУРА: проверки разумности не путают счёт с находками")
do
    -- The file read "sanityChecks in=6 out=32": 32 is how many CHECKS RAN, not
    -- how many findings there were, and the field name said otherwise.
    local env = H.load()
    local ns = env.ns
    H.profession(env, "Портняжное дело", 225, 225, {})
    H.build(env)
    local m = ns.Diag:Init().modules.sanityChecks
    H.ok(m ~= nil, "модуль проверок отчитался")
    if m then
        H.ok(m.checks and m.checks > 10,
            "сколько проверок зарегистрировано: " .. tostring(m.checks))
        H.ok(m.ran and m.ran == m.checks, "все они выполнены: " .. tostring(m.ran))
        H.ok(m.findings ~= nil, "и отдельно — сколько находок: " .. tostring(m.findings))
        H.eq(m.out, m.findings, "out означает находки, а не число проверок")
    end
end

end
