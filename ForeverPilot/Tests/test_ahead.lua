-- ForeverPilot / Tests/test_ahead.lua
--
-- ПРЕДСКАЗАТЕЛЬНЫЙ ЗАКАЗ ДАННЫХ: что понадобится дальше.
--
-- Зачем набор. Diag.wanted отвечает «чего не хватило» - то есть заполняется,
-- когда уже сломалось. Для одной вещи этого принципиально мало: ИСТОРИЮ ЦЕН
-- ЗАДНИМ ЧИСЛОМ НЕ СОБРАТЬ. Сервер открылся 4 ноября, своей истории два-три
-- дня, и если начать записывать цену рунной ткани в тот день, когда потолок
-- портняжки поднимется, сравнивать её будет не с чем ещё неделю.
--
-- Поэтому набор держит три контракта:
--   1. горизонт собирается РЕДКО, а не в каждом пересчёте;
--   2. материалы невыученных рецептов попадают в суточные слепки цен СЕГОДНЯ;
--   3. всё собранное помечено как предсказание и советов из себя не делает.
local H = ...

return function()

-- Мир: одна выученная вещь и три невыученные, с разными материалами. Ровно та
-- же картина, что у игрока: 270 выучено из 900.
local function aheadEnv(opts)
    opts = opts or {}
    local env = H.load()
    local ns = env.ns
    env.money = 58052
    env.player.level = opts.level or 26

    H.item(env, 8001, { name = "Выученная вещь", equipLoc = "INVTYPE_WAIST",
        reqLevel = 20, classID = 4, subclassID = 1, sellPrice = 300 })
    H.item(env, 8002, { name = "Лён", sellPrice = 10 })
    H.item(env, 8011, { name = "Пояс из рунной ткани", equipLoc = "INVTYPE_WAIST",
        reqLevel = 50, classID = 4, subclassID = 1, sellPrice = 900 })
    H.item(env, 8012, { name = "Рунная ткань", sellPrice = 200 })
    H.item(env, 8013, { name = "Жилет из рунной ткани", equipLoc = "INVTYPE_CHEST",
        reqLevel = 52, classID = 4, subclassID = 1, sellPrice = 1200 })
    H.item(env, 8014, { name = "Чары на ожерелье", sellPrice = 0 })
    env.vendorPrices[8002] = 20
    env.vendorPrices[8012] = 400
    env.bags[8002] = 40

    H.profession(env, "Портняжное дело", 225, 225, {
        H.recipe { id = 8101, output = 8001, name = "Выученная вещь",
                   learned = true, diff = "trivial", category = "Пояса",
                   reagents = { { itemID = 8002, qty = 2 } } },
        H.recipe { id = 8102, output = 8011, name = "Пояс из рунной ткани",
                   learned = false, category = "Пояса",
                   reagents = { { itemID = 8012, qty = 4 } } },
        H.recipe { id = 8103, output = 8013, name = "Жилет из рунной ткани",
                   learned = false, category = "Одеяния и жилеты",
                   reagents = { { itemID = 8012, qty = 6 }, { itemID = 8002, qty = 2 } } },
    })
    return env
end

H.suite("Горизонт: модуль есть и собирает раздел")
do
    local env = aheadEnv()
    local ns = env.ns
    H.ok(ns.Foresight ~= nil, "модуль горизонта есть")
    H.rescan(env)
    local r = ns.Foresight:Collect(ns.CharacterScanner:Get(), 1000)
    H.ok(r ~= nil, "горизонт собран")
    if r then
        H.eq(r.kind, "prediction", "раздел назван предсказанием, а не фактом")
        H.ok(r.disclaimer ~= nil and ns.Util.contains(r.disclaimer, "на вырост"),
            "и это написано словами: " .. ns.Util.truncate(r.disclaimer, 90))
        H.eq(r.forLevel, 26, "уровень, от которого считали, записан")
        H.eq(r.levelBand.from, 27, "полоса уровней начинается со следующего")
        H.eq(r.levelBand.to, 36, "и кончается через " .. r.horizonLevels)
        H.ok(r.notes ~= nil and #r.notes > 0,
            "и записано, чего собрать не удалось (" .. #r.notes .. " пометок)")
    end

    -- Раздел уходит в диагностику под своим именем.
    H.ok(ns.Diag:Init().wantedAhead ~= nil,
        "раздел лежит в FOREVERPILOT_DIAG.wantedAhead")
end

H.suite("Горизонт: невыученные рецепты — это и есть «что дальше»")
do
    local env = aheadEnv()
    local ns = env.ns
    H.rescan(env)
    local r = ns.Foresight:Collect(ns.CharacterScanner:Get(), 1000)
    H.eq(r.recipes.total, 2, "два невыученных рецепта найдены")
    local ids = {}
    for _, e in ipairs(r.recipes.items) do ids[e.id] = true end
    H.ok(ids[8102] and ids[8103], "и это именно они, по recipeID")
    H.eq(ids[8101], nil, "выученный в горизонт не попал — он уже доступен")
    H.ok(ns.Util.contains(r.recipes.source, "клиент"),
        "источник назван: " .. r.recipes.source)
end

H.suite("Горизонт: материалы впереди, по частоте")
do
    local env = aheadEnv()
    local ns = env.ns
    H.rescan(env)
    local r = ns.Foresight:Collect(ns.CharacterScanner:Get(), 1000)
    H.ok(r.reagents.total >= 2, "материалы впереди собраны: " .. r.reagents.total)
    local first = r.reagents.items[1]
    H.ok(first ~= nil, "и отсортированы")
    if first then
        H.eq(first.itemID, 8012, "самый нужный материал — рунная ткань (2 рецепта)")
        H.eq(first.recipes, 2, "и это посчитано")
        H.eq(first.qty, 10, "суммарное количество тоже: 4 + 6")
    end
end

H.suite("Горизонт: материалы впереди попадают в суточные слепки цен СЕГОДНЯ")
do
    -- Самый важный тест файла. Если этого не делать, история цен на материалы
    -- будущего ранга начнётся только тогда, когда ранг откроется, и первую
    -- неделю сравнивать будет не с чем.
    local env = aheadEnv()
    local ns = env.ns
    H.rescan(env)
    ns.Foresight:Collect(ns.CharacterScanner:Get(), 1000)

    local tracked = ns.ActionEngine:TrackedItems()
    H.eq(tracked[8002], true, "материал выученного рецепта в слепке (как и раньше)")
    H.eq(tracked[8012], true,
        "И МАТЕРИАЛ НЕВЫУЧЕННОГО ТОЖЕ — рунная ткань начинает копить историю"
        .. " до того, как потолок навыка поднимется")

    -- И это записано в диагностику, чтобы было видно, сколько добавил горизонт.
    local m = ns.Diag:Init().modules.priceSnapshotScope
    H.ok(m ~= nil, "охват слепка записан в диагностику")
    if m then
        H.ok((m.aheadOnly or 0) >= 1,
            "и сказано, сколько предметов добавил горизонт: " .. tostring(m.aheadOnly))
    end
end

H.suite("Горизонт: собирается редко, а не в каждом пересчёте")
do
    local env = aheadEnv()
    local ns = env.ns
    H.rescan(env)
    local snap = ns.CharacterScanner:Get()

    local due1 = ns.Foresight:Due(snap, 1000)
    H.eq(due1, true, "в первый раз — пора")
    ns.Foresight:Collect(snap, 1000)

    H.eq(ns.Foresight:Due(snap, 1001), false, "сразу после сбора — не пора")
    H.eq(ns.Foresight:Due(snap, 1000 + 60), false, "через минуту — всё ещё не пора")
    H.eq(ns.Foresight:Due(snap, 1000 + ns.Foresight.MIN_INTERVAL), true,
        "через " .. (ns.Foresight.MIN_INTERVAL / 60) .. " минут — пора")

    -- Смена уровня — повод пересобрать немедленно, не дожидаясь таймера.
    snap.level = 27
    local due2, why = ns.Foresight:Due(snap, 1001)
    H.eq(due2, true, "вырос уровень — пора немедленно")
    H.ok(why and ns.Util.contains(why, "уровень"), "и причина названа: " .. tostring(why))
end

H.suite("Горизонт: подъём потолка навыка пересобирает горизонт")
do
    local env = aheadEnv()
    local ns = env.ns
    H.rescan(env)
    local snap = ns.CharacterScanner:Get()
    ns.Foresight:Collect(snap, 1000)
    H.eq(ns.Foresight:Due(snap, 1001), false, "пока ничего не менялось — не пора")

    -- Потолок поехал: ровно тот случай, под который всё это и собирается.
    env.professions[1].max = 300
    H.rescan(env)
    local snap2 = ns.CharacterScanner:Get()
    local due, why = ns.Foresight:Due(snap2, 1002)
    H.eq(due, true, "потолок поднялся — пора пересобрать")
    H.ok(why and ns.Util.contains(why, "потолок"), "и причина названа: " .. tostring(why))
end

H.suite("Горизонт: полоса навыка — один ранг вперёд, а не вся игра")
do
    local env = aheadEnv()
    local ns = env.ns
    H.rescan(env)
    local r = ns.Foresight:Collect(ns.CharacterScanner:Get(), 1000)
    local prof
    for _, s in ipairs(r.skills) do
        if s.name == "Портняжное дело" then prof = s end
    end
    H.ok(prof ~= nil, "профессия в горизонте есть")
    if prof then
        H.eq(prof.max, 225, "текущий потолок записан")
        H.eq(prof.aheadTo, 300, "и горизонт — один ранг вперёд, 225 → 300")
        H.eq(prof.atCeiling, true, "и что навык сейчас упёрт в потолок")
    end
end

H.suite("Горизонт: размер под контролем, общее число известно")
do
    local env = H.load()
    local ns = env.ns
    env.player.level = 26
    H.item(env, 8500, { name = "Материал", sellPrice = 1 })
    local recipes = {}
    for i = 1, ns.Foresight.MAX_PER_GROUP + 30 do
        H.item(env, 8600 + i, { name = "Вещь " .. i, sellPrice = 10 })
        recipes[#recipes + 1] = H.recipe {
            id = 8700 + i, output = 8600 + i, name = "Вещь " .. i,
            learned = false, category = "Пояса",
            reagents = { { itemID = 8500, qty = 1 } },
        }
    end
    H.profession(env, "Портняжное дело", 225, 225, recipes)
    H.rescan(env)
    local r = ns.Foresight:Collect(ns.CharacterScanner:Get(), 1000)
    H.eq(r.recipes.kept, ns.Foresight.MAX_PER_GROUP,
        "сохранено ровно " .. ns.Foresight.MAX_PER_GROUP)
    H.eq(r.recipes.total, ns.Foresight.MAX_PER_GROUP + 30,
        "а общее число известно целиком")
end

H.suite("Горизонт: предсказание не превращается в советы")
do
    -- Вещь из будущего (требует 50 уровень при 26) не должна появиться ни в
    -- одной карточке: предсказание - это данные на вырост, а не совет.
    local env = aheadEnv()
    local ns = env.ns
    H.rescan(env)
    ns.Foresight:Collect(ns.CharacterScanner:Get(), 1000)
    local cards = H.build(env)
    for _, c in ipairs(cards) do
        H.ok(c.itemID ~= 8011 and c.itemID ~= 8013,
            "карточка «" .. ns.Util.truncate(tostring(c.title), 40)
            .. "» не про вещь из будущего")
        H.ok(c.recipeID ~= 8102 and c.recipeID ~= 8103,
            "и не про невыученный рецепт")
    end
end

end
