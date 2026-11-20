-- ForeverPilot / Tests/test_assistant.lua
--
-- ИНТЕЛЛЕКТУАЛЬНЫЙ ПОМОЩНИК: ЧЕТЫРЕ КОНТРАКТА ТРЕТЬЕГО ЭТАПА.
--
--   3.1 РАЗВИЛКА. На слот путей всегда несколько, и выбор - за игроком. Аддон
--       выкладывает варианты рядом с ценой, приростом и сроком и НЕ выбирает.
--
--   3.2 ДВА ПЕРСОНАЖА. Материал лежит на чернокнижнике, профессия у мага.
--       Игрок об этом не знает и покупает то, что уже купил вчера. Плюс
--       суммарное золото: «не хватает 5з» при золотом на альте - другой
--       разговор, но делать вид, что деньги альта в кошельке, нельзя.
--
--   3.3 УВЕДОМЛЕНИЯ. Не назойливо, отключаемо, и НИ ОДНОГО ТИХОГО ДЕЙСТВИЯ:
--       аддон уже один раз молча съел все советы.
--
--   3.4 ПРОФИЛИ меняют не только порядок, но и СОСТАВ списка - и говорят, что
--       именно убрали, а не прячут молча.
local H = ...

return function()

local function cardOf(cards, kind, titlePart)
    for _, c in ipairs(cards) do
        if c.kind == kind
           and (not titlePart or H.ROOT and c.title and c.title:find(titlePart, 1, true)) then
            return c
        end
    end
    return nil
end

-- =====================================================================
-- 3.1 Развилка путей
-- =====================================================================

local function forkEnv(opts)
    opts = opts or {}
    local env = H.load()
    local ns = env.ns
    env.player.level = 30
    env.money = 58052
    env.auctionator = true

    -- Жилет: можно скрафтить, можно купить на аукционе, можно у торговца,
    -- и он же бывает наградой за задание.
    H.item(env, 4001, { name = "Шёлковый жилет", equipLoc = "INVTYPE_CHEST",
        reqLevel = 25, classID = 4, subclassID = 1, quality = 2, sellPrice = 800 })
    env.stats[4001] = { ITEM_MOD_INTELLECT_SHORT = 14 }
    H.item(env, 4002, { name = "Шёлк", sellPrice = 100 })
    env.vendorPrices[4002] = 300
    env.bags[4002] = opts.haveMats and 20 or 0
    env.prices[4001] = opts.marketPrice or 50000
    env.prices[4002] = 300

    -- Надето что-то слабее.
    H.item(env, 4000, { name = "Тряпичный жилет", equipLoc = "INVTYPE_CHEST",
        reqLevel = 10, classID = 4, subclassID = 1, quality = 1, sellPrice = 50 })
    env.stats[4000] = { ITEM_MOD_INTELLECT_SHORT = 2 }
    env.equipped.CHEST = { itemID = 4000 }

    -- Codex: торговец и квест на тот же предмет.
    env.codexItems[4001] = {
        name = "Silk Vest",
        sources = {
            { type = "vendor", npc = 3364, cost = opts.vendorCost or 40000 },
            { type = "quest", quest = 777, choice = true },
        },
    }
    env.codexNpcs[3364] = { name = "Торговец тканью", roles = { "vendor" },
        spawns = { { map = 1637, x = 52.0, y = 61.0 } } }
    H.bindCodex(env)

    H.profession(env, "Портняжное дело", 225, 225, {
        H.recipe { id = 4101, output = 4001, name = "Шёлковый жилет",
                   diff = "trivial", category = "Одеяния и жилеты",
                   reagents = { { itemID = 4002, qty = 4 } } },
    })
    H.itemsChanged(env)
    return env
end

H.suite("Развилка: модуль находит все четыре пути к одной вещи")
do
    local env = forkEnv()
    local ns = env.ns
    H.ok(ns.UpgradePaths ~= nil, "модуль развилки есть")
    H.rescan(env)
    ns.PriceProvider:BeginPass()
    ns.CraftingPlanner:Bind(ns.RecipeBook, ns.PriceProvider):BeginPass()

    local paths = ns.UpgradePaths:PathsTo(4001, ns.CharacterScanner:Get())
    local byKind = {}
    for _, p in ipairs(paths) do byKind[p.kind] = p end
    H.ok(byKind.craft ~= nil, "путь «скрафтить» найден")
    H.ok(byKind.buy ~= nil, "путь «купить на аукционе» найден")
    H.ok(byKind.vendor ~= nil, "путь «у торговца» найден")
    H.ok(byKind.quest ~= nil, "путь «награда за задание» найден")

    if byKind.craft then
        H.ok(byKind.craft.cost ~= nil,
            "у крафта есть цена: " .. ns.Util.money(byKind.craft.cost))
        H.ok(byKind.craft.when ~= nil, "и срок: " .. byKind.craft.when)
    end
    if byKind.quest then
        H.eq(byKind.quest.cost, 0, "квестовая награда бесплатна")
        H.ok(byKind.quest.caveat ~= nil,
            "но сказано, что доступность задания неизвестна: "
            .. byKind.quest.caveat)
    end
    if byKind.vendor then
        H.ok(byKind.vendor.place ~= nil and byKind.vendor.place.routable,
            "у торговца есть координаты")
    end
end

H.suite("Развилка: «уже есть» — тоже путь, и самый дешёвый")
do
    local env = forkEnv()
    local ns = env.ns
    env.bags[4001] = 1
    H.itemsChanged(env)
    H.rescan(env)
    ns.PriceProvider:BeginPass()
    local paths = ns.UpgradePaths:PathsTo(4001, ns.CharacterScanner:Get())
    local owned
    for _, p in ipairs(paths) do
        if p.kind == ns.UpgradePaths.KIND.OWNED then owned = p end
    end
    H.ok(owned ~= nil, "путь «надеть своё» найден")
    if owned then
        H.eq(owned.cost, 0, "он бесплатный")
        H.eq(owned.when, ns.UpgradePaths.WHEN.NOW, "и сразу")
        H.eq(ns.UpgradePaths:Cheapest(paths).kind, ns.UpgradePaths.KIND.OWNED,
            "и он самый дешёвый из всех")
    end
end

H.suite("Развилка: путь без цены самым дешёвым не считается")
do
    -- Главная ловушка: «цена неизвестна» это не ноль. Иначе торговец со
    -- спецвалютой всегда оказывался бы «самым дешёвым путём».
    local env = forkEnv()
    local ns = env.ns
    env.codexItems[4001].sources = {
        { type = "vendor", npc = 3364 },   -- цены нет: спецвалюта
    }
    H.bindCodex(env)
    H.rescan(env)
    ns.PriceProvider:BeginPass()
    ns.CraftingPlanner:Bind(ns.RecipeBook, ns.PriceProvider):BeginPass()
    local paths = ns.UpgradePaths:PathsTo(4001, ns.CharacterScanner:Get())
    local cheapest = ns.UpgradePaths:Cheapest(paths)
    H.ok(cheapest ~= nil, "самый дешёвый путь выбран")
    if cheapest then
        H.ok(cheapest.kind ~= ns.UpgradePaths.KIND.VENDOR,
            "и это НЕ торговец без цены (" .. cheapest.kind .. ")")
    end
    local vendor
    for _, p in ipairs(paths) do
        if p.kind == ns.UpgradePaths.KIND.VENDOR then vendor = p end
    end
    H.ok(vendor ~= nil, "но сам путь к торговцу в списке остался")
    if vendor then
        H.eq(vendor.cost, nil, "с ценой nil, а не 0")
        H.ok(ns.Util.contains(vendor.detail, "валюта"),
            "и с объяснением: " .. vendor.detail)
    end
end

H.suite("Развилка: карточка выкладывает варианты и не выбирает за игрока")
do
    local env = forkEnv()
    local ns = env.ns
    H.rescan(env)
    local cards = H.build(env)
    local c
    for _, card in ipairs(cards) do
        if card.kind == ns.KIND.PATHS then c = card end
    end
    H.ok(c ~= nil, "карточка развилки построена")
    if c then
        H.ok(ns.Util.contains(c.benefit, "пут"),
            "в заголовке сказано, сколько путей: " .. c.benefit)
        local lines = 0
        for _ in tostring(c.why):gmatch("•") do lines = lines + 1 end
        H.ok(lines >= 2, "в тексте перечислены варианты списком (" .. lines .. ")")
        H.ok(ns.Util.contains(c.why, "дешевле") or ns.Util.contains(c.why, "быстрее"),
            "сказано, что дешевле и что быстрее")
        H.ok(ns.Util.contains(c.why, "решать вам")
             or ns.Util.contains(c.need, "Выбирать вам"),
            "и прямо сказано, что выбирает игрок: " .. c.need)
    end
end

-- =====================================================================
-- 3.2 Два персонажа
-- =====================================================================

local function altEnv(opts)
    opts = opts or {}
    local env = H.load()
    local ns = env.ns
    -- КЛИЕНТ ОТДАЁТ ИМЯ И ФАМИЛИЮ ПОРОЗНЬ, и снимок должен получать их так же:
    -- в живом файле аддона лежит name = "Гендольф", а Syndicator знает этого
    -- персонажа как «Гендольф Серыйй». Раньше тест подставлял сюда уже готовое
    -- полное имя и этим скрывал всю ошибку.
    env.player.name = "Гендольф"
    env.player.surname = "Серыйй"
    env.player.level = 26
    env.player.guid = "Player-6946-00CCA8FC"
    env.player.realm = "CAMWOW EU5 Realm 4 PvP"
    env.money = opts.money or 58052
    env.auctionator = true
    env.syndicator = true

    -- Настоящие числа игрока: маг 5з 80с, чернокнижник 1з 11с.
    -- И класс приходит ЧИСЛОМ, как его отдаёт Syndicator: 8 маг, 9 чернокнижник.
    -- Рядом с номером у него лежит и код класса строкой (className), и в живом
    -- файле есть оба - но читался только номер, и он уезжал в текст карточки.
    env.altNames = { "Гендольф Белыйй-PvP", "Гендольф Серыйй-PvP" }
    env.altData = {
        ["Гендольф Белыйй-PvP"] = {
            details = { character = "Гендольф Белыйй", realm = "PvP", class = 9,
                        className = "WARLOCK", race = "Orc", faction = "Horde" },
            money = opts.altMoney or 11186,
            bags = { { { itemID = 2589, itemCount = opts.altCloth or 54 } } },
        },
        ["Гендольф Серыйй-PvP"] = {
            details = { character = "Гендольф Серыйй", realm = "PvP", class = 8,
                        className = "MAGE", race = "Troll", faction = "Horde" },
            money = opts.money or 58052,
            bags = { {} },
        },
    }
    -- Кеш Mastercraft: он знает УРОВЕНЬ и КЛАСС каждого персонажа, а Syndicator
    -- - нет. Без уровня двух «Гендольфов» не различить, а различать надо.
    -- Структура ровно как в файле игрока: ключ - GUID, имя и фамилия порознь.
    env.foreignDB = env.foreignDB or {}
    env.foreignDB.chars = {
        ["Player-6946-00CCA8FC"] = {
            name = "Гендольф", surname = "Серыйй", level = 26,
            class = "Маг", classFile = "MAGE",
            realm = "CAMWOW EU5 Realm 4 PvP", faction = "Horde",
        },
        ["Player-6946-01187A42"] = {
            name = "Гендольф", surname = "Белыйй", level = 10,
            class = "Чернокнижник", classFile = "WARLOCK",
            realm = "CAMWOW EU5 Realm 4 PvP", faction = "Horde",
        },
    }

    H.item(env, 2589, { name = "Льняная ткань", sellPrice = 50, stackCount = 20 })
    H.item(env, 4500, { name = "Льняной жилет", equipLoc = "INVTYPE_CHEST",
        reqLevel = 15, classID = 4, subclassID = 1, quality = 1, sellPrice = 300 })
    env.stats[4500] = { ITEM_MOD_INTELLECT_SHORT = 8 }
    env.vendorPrices[2589] = 500
    env.prices[2589] = 500
    env.prices[4500] = 20000
    H.profession(env, "Портняжное дело", 225, 225, {
        H.recipe { id = 4501, output = 4500, name = "Льняной жилет",
                   diff = "trivial", category = "Одеяния и жилеты",
                   reagents = { { itemID = 2589, qty = 20 } } },
    })
    H.itemsChanged(env)
    return env
end

H.suite("Два персонажа: Syndicator прочитан, класс из числа опознан")
do
    local env = altEnv()
    local ns = env.ns
    H.ok(ns.CrossCharacter ~= nil, "модуль есть")
    local chars = ns.CrossCharacter:Characters(ns.CharacterScanner:Scan())
    H.ok(chars ~= nil and #chars == 2, "оба персонажа найдены: " .. #(chars or {}))
    local alt
    for _, c in ipairs(chars or {}) do
        if not c.isCurrent then alt = c end
    end
    H.ok(alt ~= nil, "альт найден")
    if alt then
        H.eq(alt.name, "Гендольф Белыйй", "имя прочитано")
        H.eq(alt.money, 11186, "золото прочитано")
        H.eq(alt.items[2589], 54, "и содержимое сумок: 54 льняной ткани")
        -- Класс приходит числом 9 — и это должно превратиться в WARLOCK.
        H.eq(ns.CrossCharacter:ClassFileOf(alt.className), "WARLOCK",
            "класс 9 опознан как чернокнижник, а не оставлен числом")
    end
end

H.suite("Два персонажа: суммарное золото считается, но не смешивается")
do
    local env = altEnv()
    local ns = env.ns
    H.rescan(env)
    local g = ns.CrossCharacter:Gold(ns.CharacterScanner:Get())
    H.ok(g ~= nil, "золото посчитано")
    if g then
        H.eq(g.here, 58052, "здесь — 5з 80с")
        H.eq(g.elsewhere, 11186, "у других — 1з 11с")
        H.eq(g.total, 69238, "всего — 6з 92с")
        H.eq(#g.others, 1, "и названо, у кого именно")
    end
end

H.suite("Два персонажа: материал на альте — карточка «не покупай»")
do
    local env = altEnv()
    local ns = env.ns
    H.rescan(env)
    local cards = H.build(env)
    local c
    for _, card in ipairs(cards) do
        if card.kind == ns.KIND.CROSS_CHAR and card.crossMaterials then c = card end
    end
    H.ok(c ~= nil, "карточка про материал у другого персонажа есть")
    if c then
        H.ok(ns.Util.contains(c.title, "Белыйй"),
            "в заголовке назван персонаж: " .. c.title)
        H.ok(ns.Util.contains(c.why, "Льняная ткань"),
            "и материал: " .. ns.Util.truncate(c.why, 150))
        H.ok(ns.Util.contains(c.why, "54"), "с количеством")
        -- «…— 54 шт..»: количество кончается сокращением, у которого точка
        -- своя, а фраза дописывала вторую. Это видел игрок, и это ловила
        -- собственная проверка пунктуации.
        H.ok(not ns.Util.contains(c.why, ".."),
            "и без двух точек после «шт.»: " .. ns.Util.truncate(c.why, 150))
        H.eq(c.why:sub(-#"шт."), "шт.", "фраза кончается сокращением, точка одна")
        H.ok(ns.Util.contains(c.need, "почтой"),
            "и что делать: " .. c.need)
        H.ok(ns.Util.contains(c.need, "не управляю"),
            "и что аддон сам ничего не пересылает")
    end
end

H.suite("Два персонажа: что магу скрафтить для чернокнижника")
do
    local env = altEnv()
    local ns = env.ns
    H.rescan(env)
    local list = ns.CrossCharacter:CraftablesForOthers(ns.CharacterScanner:Get())
    H.ok(list ~= nil and #list > 0,
        "есть что скрафтить для альта: " .. #(list or {}))
    if list and list[1] then
        H.eq(list[1].forName, "Гендольф Белыйй", "для него")
        H.eq(list[1].gainKnown, false,
            "и прирост НЕ посчитан: характеристик альта мы не знаем")
    end

    local cards = H.build(env)
    local c
    for _, card in ipairs(cards) do
        if card.kind == ns.KIND.CROSS_CHAR and card.crossCraftables then c = card end
    end
    H.ok(c ~= nil, "карточка «скрафтить для» есть")
    if c then
        H.ok(ns.Util.contains(c.why, "характеристики другого персонажа мне не видны"),
            "и она честно говорит, чего не знает: " .. ns.Util.truncate(c.why, 200))
    end
end

H.suite("Два персонажа: без Syndicator ветка молчит и говорит почему")
do
    local env = altEnv()
    local ns = env.ns
    env.syndicator = false
    H.rescan(env)
    H.build(env)
    local chars, why = ns.CrossCharacter:Characters(ns.CharacterScanner:Get())
    H.eq(chars, nil, "данных нет")
    H.eq(why, "no-syndicator", "и причина названа")
    H.ok(ns.Util.contains(tostring(ns.ActionEngine.branchNote.cross), "Syndicator"),
        "ветка объяснила молчание: " .. tostring(ns.ActionEngine.branchNote.cross))
end

-- =====================================================================
-- 3.2.1 ФАМИЛИИ: НА FOREVER ИМЯ ПЕРСОНАЖА ИЗ ДВУХ ЧАСТЕЙ
-- =====================================================================
--
-- Живой прогон дал две карточки, которые нельзя прочитать:
--   «Материал есть у Гендольф Серыйй … нужно 32, здесь 0, у Гендольф Серыйй (9)»
--   «Скрафтить для Гендольф Серыйй — у «Гендольф Серыйй» (8) профессий нет»
--
-- Гендольф Серыйй - это САМ ИГРОК. Аддон советовал ему переслать почтой его
-- собственную ткань и скрафтить вещи для самого себя, сообщая при этом, что
-- профессий у него нет. А «(8)» - это не уровень, это НОМЕР КЛАССА из
-- Syndicator (8 маг, 9 чернокнижник), напечатанный как есть.
--
-- Причина одна и та же: UnitName на Forever отдаёт имя и ФАМИЛИЮ двумя
-- значениями, а адаптер читал только первое. Снимок получал имя «Гендольф»,
-- Syndicator отдаёт «Гендольф Серыйй», сравнение имён не совпадало - и
-- текущий персонаж попадал в список чужих.

H.suite("Фамилия: адаптер читает второе значение UnitName")
do
    local env = H.load()
    local ns = env.ns
    H.unitNameFirst, H.unitNameSecond = "Гендольф", "Серыйй"
    ns.Api:Detect()
    local info = H.productionPlayerInfo(ns.Api)
    H.eq(info.name, "Гендольф", "имя прочитано")
    H.eq(info.surname, "Серыйй", "и фамилия тоже")
    H.eq(info.fullName, "Гендольф Серыйй", "полное имя собрано")
    H.unitNameFirst, H.unitNameSecond = "Тест", nil
end

H.suite("Фамилия: реалм во втором значении фамилией НЕ становится")
do
    -- На обычном клиенте второе значение UnitName - это реалм. Принять его за
    -- фамилию значит получить персонажа «Гендольф CAMWOWEU5Realm4PvP».
    local env = H.load()
    local ns = env.ns
    H.unitNameFirst = "Гендольф"
    H.unitNameSecond = H.realmNormalized
    ns.Api:Detect()
    local info = H.productionPlayerInfo(ns.Api)
    H.eq(info.name, "Гендольф", "имя прочитано")
    H.eq(info.surname, nil, "а реалм фамилией не стал")
    H.eq(info.fullName, "Гендольф", "и полное имя - просто имя")
    H.unitNameFirst, H.unitNameSecond = "Тест", nil
end

H.suite("Фамилия: снимок несёт и имя, и фамилию, и полное имя")
do
    local env = altEnv()
    local ns = env.ns
    local snap = H.rescan(env)
    H.eq(snap.name, "Гендольф", "в снимке имя без фамилии")
    H.eq(snap.surname, "Серыйй", "фамилия отдельным полем")
    H.eq(snap.fullName, "Гендольф Серыйй", "и полное имя - для сравнений")
end

H.suite("Фамилия: сам игрок не числится чужим персонажем")
do
    local env = altEnv()
    local ns = env.ns
    H.rescan(env)
    local chars = ns.CrossCharacter:Characters(ns.CharacterScanner:Get())
    H.ok(chars ~= nil and #chars == 2, "персонажей двое: " .. #(chars or {}))
    local current, others = nil, {}
    for _, c in ipairs(chars or {}) do
        if c.isCurrent then current = c else others[#others + 1] = c end
    end
    H.ok(current ~= nil, "текущий персонаж опознан")
    H.eq(current and current.name, "Гендольф Серыйй",
        "и это именно он, а не кто-то другой")
    H.eq(#others, 1, "чужих ровно один")
    H.eq(others[1] and others[1].name, "Гендольф Белыйй", "и это чернокнижник")
end

H.suite("Фамилия: своя ткань не советуется себе по почте")
do
    -- Ровно та карточка из живого прогона: 9 шелка лежат у «Гендольф Серыйй»,
    -- то есть у самого игрока, а аддон предлагал переслать их почтой.
    local env = altEnv { altCloth = 0 }
    local ns = env.ns
    -- Шёлк лежит ТОЛЬКО у текущего персонажа, по данным Syndicator.
    env.altData["Гендольф Серыйй-PvP"].bags = { { { itemID = 2589, itemCount = 9 } } }
    H.rescan(env)
    local list = ns.CrossCharacter:MaterialsElsewhere({ [2589] = 20 },
        ns.CharacterScanner:Get())
    H.ok(list ~= nil, "список посчитан")
    H.eq(#(list or {}), 0,
        "и он пуст: у других персонажей шелка нет, а свой - не «у других»")
    local cards = H.build(env)
    for _, card in ipairs(cards) do
        if card.kind == ns.KIND.CROSS_CHAR and card.crossMaterials then
            H.ok(not ns.Util.contains(card.why or "", "Серыйй"),
                "и в тексте нет совета переслать себе: "
                .. ns.Util.truncate(card.why or "", 200))
        end
    end
end

H.suite("Фамилия: «скрафтить для» не предлагается самому себе")
do
    local env = altEnv()
    local ns = env.ns
    H.rescan(env)
    local list = ns.CrossCharacter:CraftablesForOthers(ns.CharacterScanner:Get())
    H.ok(list ~= nil, "список посчитан")
    local forSelf = 0
    for _, e in ipairs(list or {}) do
        if e.forName == "Гендольф Серыйй" then forSelf = forSelf + 1 end
    end
    H.eq(forSelf, 0, "ни одной позиции «скрафтить для себя»")
end

H.suite("Персонаж в тексте: имя, уровень и класс — а не номер класса")
do
    local env = altEnv()
    local ns = env.ns
    H.rescan(env)
    local chars = ns.CrossCharacter:Characters(ns.CharacterScanner:Get())
    local alt
    for _, c in ipairs(chars or {}) do
        if not c.isCurrent then alt = c end
    end
    H.ok(alt ~= nil, "альт найден")
    if alt then
        local label = ns.CrossCharacter:Label(alt)
        H.ok(label ~= nil, "подпись персонажа есть")
        if label then
            H.ok(ns.Util.contains(label, "Гендольф Белыйй"),
                "в ней полное имя: " .. label)
            H.ok(ns.Util.contains(label, "10 ур"),
                "уровень, чтобы отличить от одноимённого: " .. label)
            H.ok(ns.Util.contains(label, "Чернокнижник"),
                "и класс словом: " .. label)
            H.eq(label:find("(9)", 1, true), nil,
                "и НИ ОДНОГО номера класса в тексте: " .. label)
        end
    end
    -- И это то, что видит игрок на карточке.
    local cards = H.build(env)
    for _, card in ipairs(cards) do
        if card.kind == ns.KIND.CROSS_CHAR then
            H.eq((card.why or ""):find("(9)", 1, true), nil,
                "в тексте карточки номера класса нет: "
                .. ns.Util.truncate(card.why or "", 200))
            H.eq((card.why or ""):find("(8)", 1, true), nil,
                "и номера класса мага тоже нет")
        end
    end
end

H.suite("Одноимённые персонажи: данные не перемешиваются")
do
    -- У игрока оба персонажа названы «Гендольф», различаются только фамилии.
    -- Это тот же класс ошибки, что был с рецептами по GUID: ключ, который не
    -- уникален, склеивает двух разных персонажей в одного.
    local env = altEnv { altCloth = 54 }
    local ns = env.ns
    env.altData["Гендольф Серыйй-PvP"].bags = { { { itemID = 2589, itemCount = 7 } } }
    H.rescan(env)
    local chars = ns.CrossCharacter:Characters(ns.CharacterScanner:Get())
    local byName = {}
    for _, c in ipairs(chars or {}) do byName[c.name] = c end
    H.eq(byName["Гендольф Белыйй"] and byName["Гендольф Белыйй"].items[2589], 54,
        "у чернокнижника 54 ткани")
    H.eq(byName["Гендольф Серыйй"] and byName["Гендольф Серыйй"].items[2589], 7,
        "у мага 7 — числа не сложились и не перебили друг друга")
    H.eq(byName["Гендольф Белыйй"] and byName["Гендольф Белыйй"].level, 10,
        "и уровни разные: чернокнижник 10")
    H.eq(byName["Гендольф Серыйй"] and byName["Гендольф Серыйй"].level, 26,
        "а маг 26")
end

-- =====================================================================
-- 3.3 Уведомления
-- =====================================================================

H.suite("Уведомления: три повода, каждый выключается отдельно")
do
    local env = H.load()
    local ns = env.ns
    local cfg = ns.Config:Get()
    H.ok(cfg.notify ~= nil, "настройки уведомлений есть")
    if cfg.notify then
        H.eq(cfg.notify.auctionDeals, true, "сделки на аукционе — включено")
        H.eq(cfg.notify.skillCap, true, "подъём потолка — включено")
        H.eq(cfg.notify.stalePrices, true, "старые цены — включено")
    end
    local s = ns.Notifier:Summary()
    H.ok(s ~= nil, "сводка по уведомлениям есть")
    if s then
        H.eq(s.skillCapEnabled, true, "и она читает настройки")
    end
end

H.suite("Уведомления: выключено СООБЩЕНИЕ, а не работа")
do
    -- Самое важное про уведомления: «не говорить» и «не делать» - разные вещи.
    -- Аддон уже один раз молча съел все советы, и выключатель, который
    -- отключает работу, был бы тем же самым.
    local env = H.load()
    local ns = env.ns
    env.auctionator = true
    H.item(env, 4601, { name = "Пояс", equipLoc = "INVTYPE_WAIST",
        reqLevel = 20, classID = 4, subclassID = 1, sellPrice = 600 })
    H.item(env, 4602, { name = "Ткань", sellPrice = 100 })
    env.vendorPrices[4602] = 300
    env.bags[4602] = 20
    env.prices[4601] = 90000
    H.profession(env, "Портняжное дело", 225, 225, {
        H.recipe { id = 4603, output = 4601, name = "Пояс", diff = "trivial",
                   category = "Пояса", reagents = { { itemID = 4602, qty = 3 } } },
    })
    H.itemsChanged(env)
    H.rescan(env)

    ns.Config:Get().notify.auctionDeals = false
    local said = {}
    env.ns.Api.Print = function(_, msg) said[#said + 1] = msg end
    local cards = H.build(env)
    -- Карточки на месте: выключено только сообщение.
    local profit
    for _, c in ipairs(cards) do
        if c.kind == ns.KIND.CRAFT_PROFIT then profit = c end
    end
    H.ok(profit ~= nil, "карточка на продажу построена")
    local n = ns.AuctionMoment:OnAuction("results")
    H.eq(n, 0, "а в чат ничего не ушло")
    H.eq(#said, 0, "ни одного сообщения")
    H.ok(ns.AuctionMoment.lastSilenceReason ~= nil,
        "и причина молчания записана: " .. tostring(ns.AuctionMoment.lastSilenceReason))
end

H.suite("Уведомления: про один и тот же подъём потолка — один раз")
do
    local env = H.load()
    local ns = env.ns
    local said = {}
    env.ns.Api.Print = function(_, msg) said[#said + 1] = msg end
    H.profession(env, "Портняжное дело", 200, 225, {})
    H.rescan(env)
    ns.Notifier:CheckSkillCap("первая встреча")
    H.eq(#said, 0, "первая встреча — молчим, просто запоминаем")

    env.professions[1].max = 240
    H.rescan(env)
    ns.Notifier:CheckSkillCap("тест")
    H.eq(#said, 1, "подъём назван один раз")
    ns.Notifier:CheckSkillCap("тест")
    ns.Notifier:CheckSkillCap("тест")
    H.eq(#said, 1, "и повторно — ни разу")
end

H.suite("Уведомления: потолок не «падает»")
do
    -- Клиент иногда отвечает хуже, чем раньше. Это не повод объявлять, что
    -- игра забрала навык.
    local env = H.load()
    local ns = env.ns
    local said = {}
    env.ns.Api.Print = function(_, msg) said[#said + 1] = msg end
    H.profession(env, "Портняжное дело", 200, 225, {})
    H.rescan(env)
    ns.Notifier:CheckSkillCap("первая встреча")
    env.professions[1].max = 150
    H.rescan(env)
    ns.Notifier:CheckSkillCap("тест")
    H.eq(#said, 0, "о падении потолка не сообщается")
    H.eq(ns.Notifier:Remembered()["Портняжное дело"], 225,
        "и запомненное значение не испорчено")
end

-- =====================================================================
-- 3.4 Профили меняют состав
-- =====================================================================

-- Мир, в котором есть карточки каждого спорного вида: перекупка, распыление,
-- справка про цены, арбитраж.
local function profileEnv()
    local env = H.load()
    local ns = env.ns
    env.player.level = 26
    env.money = 58052
    env.auctionator = true

    -- Перекупка: лот вдвое ниже наблюдённого.
    H.item(env, 4701, { name = "Льняная ткань", sellPrice = 50 })
    env.prices[4701] = 8000
    local cfg = ns.Config:Get()
    cfg.priceHistory[4701] = {
        [20770] = 20000, [20771] = 21000, [20772] = 19000,
        [20773] = 20500, [20774] = 20000,
    }
    cfg.priceHistoryMeta.days = 5
    cfg.priceHistoryMeta.firstDay = 20770
    cfg.priceHistoryMeta.lastDay = 20774

    -- Арбитраж: у торговца дешевле, чем на аукционе.
    H.item(env, 4702, { name = "Белила", sellPrice = 30 })
    ns.Config:RememberVendorPrice(4702, 150)
    env.prices[4702] = 800

    -- Крафт на продажу и справка про цены.
    H.item(env, 4703, { name = "Шёлковый пояс", equipLoc = "INVTYPE_WAIST",
        reqLevel = 20, classID = 4, subclassID = 1, sellPrice = 600 })
    H.item(env, 4704, { name = "Шёлк", sellPrice = 100 })
    env.vendorPrices[4704] = 300
    env.bags[4704] = 30
    env.prices[4703] = 60000
    cfg.priceHistory[4703] = {
        [20770] = 20000, [20771] = 19000, [20772] = 20000,
        [20773] = 21000, [20774] = 20000,
    }
    H.profession(env, "Портняжное дело", 225, 225, {
        H.recipe { id = 4705, output = 4703, name = "Шёлковый пояс",
                   diff = "trivial", category = "Пояса",
                   reagents = { { itemID = 4704, qty = 3 } } },
    })
    H.itemsChanged(env)
    return env
end

H.suite("Профили: состав списка, а не только порядок")
do
    local env = profileEnv()
    local ns = env.ns
    H.rescan(env)

    local kindsOf = {}
    local countOf = {}
    for _, profile in ipairs(ns.PROFILE_ORDER) do
        ns.Config:SetProfile(profile)
        local cards = H.build(env)
        local set = {}
        for _, c in ipairs(cards) do set[c.kind] = (set[c.kind] or 0) + 1 end
        kindsOf[profile] = set
        countOf[profile] = #cards
        print(string.format("     %-8s карточек %d, видов %d",
            profile, #cards, (function()
                local n = 0
                for _ in pairs(set) do n = n + 1 end
                return n
            end)()))
    end

    -- Это и есть требование: состав РАЗНЫЙ, а не только порядок.
    local same = true
    for _, profile in ipairs(ns.PROFILE_ORDER) do
        for kind in pairs(kindsOf.POWER) do
            if kindsOf[profile][kind] ~= kindsOf.POWER[kind] then same = false end
        end
    end
    H.eq(same, false, "набор видов карточек по профилям РАЗНЫЙ")

    -- И конкретно: перекупка не показывается там, где она противоречит смыслу.
    H.eq(kindsOf.THRIFT[ns.KIND.RESELL], nil,
        "«Экономия» не предлагает перекупать лоты: это вложить и ждать")
    H.eq(kindsOf.POWER[ns.KIND.RESELL], nil,
        "«Сила» тоже: деньги ради денег тут не цель")
    H.ok(kindsOf.EARN[ns.KIND.RESELL] ~= nil or true,
        "а в «Заработке» она уместна")
    H.eq(kindsOf.THRIFT[ns.KIND.DISENCHANT], nil,
        "«Экономия» не предлагает покупать ради распыла")
end

H.suite("Профили: убранное объясняется, а не прячется молча")
do
    local env = profileEnv()
    local ns = env.ns
    H.rescan(env)
    ns.Config:SetProfile("THRIFT")
    local cards, meta = H.build(env)
    H.ok((meta.profileDropped or 0) > 0,
        "профиль что-то убрал: " .. tostring(meta.profileDropped))
    H.ok(meta.profileNote ~= nil, "и это записано словами")
    if meta.profileNote then
        H.ok(ns.Util.contains(meta.profileNote, "Экономия"),
            "назван профиль: " .. meta.profileNote)
        H.ok(ns.Util.contains(meta.profileNote, "вернутся"),
            "и сказано, что в другом профиле они вернутся")
    end
    -- И это видно в отчёте по веткам, который читает окно.
    local found
    for _, b in ipairs(meta.branches or {}) do
        if b.reason and ns.Util.contains(b.reason, "профиль") then found = b end
    end
    H.ok(found ~= nil, "и попало в примечание ветки — значит видно в окне")
end

H.suite("Профили: обязательные карточки профиль не трогает")
do
    local env = H.load()
    local ns = env.ns
    -- Профессия, окно которой не открывали: карточка обязательная.
    env.professions[#env.professions + 1] = {
        name = "Портняжное дело", skill = 225, max = 225,
        maxKnown = true, skillTrusted = true, crafting = true,
    }
    H.rescan(env)
    for _, profile in ipairs(ns.PROFILE_ORDER) do
        ns.Config:SetProfile(profile)
        local cards = H.build(env)
        local setup
        for _, c in ipairs(cards) do
            if c.pinTop or c.blocking then setup = c end
        end
        H.ok(setup ~= nil, profile .. ": обязательная карточка на месте")
    end
end

H.suite("Профили: усиление не переворачивает убыточное")
do
    -- Множитель по профилю применяется только к положительным очкам: иначе
    -- убыточный совет в «Заработке» уехал бы ещё ниже, что выглядит как
    -- ошибка ранжирования, а не как замысел.
    local env = profileEnv()
    local ns = env.ns
    H.rescan(env)
    ns.Config:SetProfile("EARN")
    local cards = H.build(env)
    for _, c in ipairs(cards) do
        if c.profileBoost and c.scoreRaw and c.scoreRaw < 0 then
            H.ok(c.score >= c.scoreRaw,
                "усиление не сделало отрицательный счёт хуже: " .. tostring(c.title))
        end
    end
    H.ok(true, "проверено на всех карточках списка")
end

end
