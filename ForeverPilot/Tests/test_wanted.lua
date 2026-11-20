-- ForeverPilot / Tests/test_wanted.lua
--
-- СПИСОК ЗАКАЗА ДАННЫХ: ЧЕГО АДДОНУ НЕ ХВАТИЛО, СТРУКТУРОЙ.
--
-- Зачем набор. Петля «играю → аддон записал, чего не хватило → данные добавили
-- → играю дальше» держалась на том, что кто-то вычитывал нехватку между строк:
-- часть фактов лежала в странностях, часть в воронках, часть в счётчиках, и всё
-- словами. По словам пополнять базу нельзя. Поэтому FOREVERPILOT_DIAG.wanted -
-- это ID, частота и пометка «где встретилось», и этот набор держит именно
-- машинную читаемость: не «есть ли текст», а есть ли id, n и where.
local H = ...

return function()

local function wantedOf(ns, kind)
    return (ns.Diag:Init().wanted or {})[kind]
end

H.suite("Заказ данных: раздел есть и пуст, пока всё в порядке")
do
    local env = H.load()
    local ns = env.ns
    H.ok(type(ns.Diag:Init().wanted) == "table", "раздел wanted существует")
    H.eq(ns.Diag:WantedTotals().grandTotal, 0, "и на чистой сессии он пуст")
    H.eq(ns.Diag:WantedLine(), nil,
        "и строки «данных не хватило» нет, когда всё хватило")
end

H.suite("Заказ данных: запись содержит id, частоту и место")
do
    local env = H.load()
    local ns = env.ns
    ns.Diag:Want("itemsNotInDB", 12345, "bags", { reason = "not-in-db" })
    ns.Diag:Want("itemsNotInDB", 12345, "bank")
    ns.Diag:Want("itemsNotInDB", 777, "craft-candidate")

    local b = wantedOf(ns, "itemsNotInDB")
    H.ok(b ~= nil, "корзина заказа создана")
    if b then
        H.eq(b.total, 2, "два разных предмета")
        H.eq(b.hits, 3, "три попадания")
        local e = b.items["12345"]
        H.ok(e ~= nil, "предмет найден по ключу")
        if e then
            H.eq(e.id, 12345, "id сохранён числом, а не строкой")
            H.eq(e.n, 2, "частота посчитана")
            H.eq(e.where.bags, 1, "место «сумка» записано")
            H.eq(e.where.bank, 1, "и «банк» тоже — одно не вытеснило другое")
            H.eq(e.reason, "not-in-db", "причина сохранена")
        end
    end
end

H.suite("Заказ данных: размер ограничен, но общее число известно")
do
    local env = H.load()
    local ns = env.ns
    local KEEP = ns.Diag.WANT_KEEP
    for i = 1, KEEP + 25 do
        ns.Diag:Want("itemsNoPrice", 100000 + i, "profit")
    end
    local b = wantedOf(ns, "itemsNoPrice")
    H.eq(b.kept, KEEP, "сохранено ровно " .. KEEP .. " позиций")
    H.eq(b.total, KEEP + 25, "а общее число известно целиком")
    H.eq(b.truncated, true, "и отмечено, что список урезан")
end

H.suite("Заказ данных: одна строка для игрока, когда чего-то не хватает")
do
    local env = H.load()
    local ns = env.ns
    ns.Diag:Want("itemsNotInDB", 1, "bags")
    ns.Diag:Want("itemsNoPrice", 2, "profit")
    ns.Diag:Want("npcNoCoords", 3, "route-request")
    local line = ns.Diag:WantedLine()
    H.ok(line ~= nil, "строка собрана")
    if line then
        H.ok(ns.Util.contains(line, "предмет"), "названы предметы: " .. line)
        H.ok(ns.Util.contains(line, "цен"), "названы цены")
        H.ok(ns.Util.contains(line, "торговц"), "названы торговцы")
        H.ok(ns.Util.contains(line, "wanted"),
            "и сказано, где лежит сам список")
    end

    -- И она попадает в сводку, которую читает игрок, а не только в структуру.
    ns.Diag:WriteSummary()
    local found = false
    for _, l in ipairs(ns.Diag:Init().summary or {}) do
        if ns.Util.contains(l, "Данных не хватило") then found = true end
    end
    H.ok(found, "строка попала в сводку /fp diag")
end

H.suite("Заказ данных: нечитаемый предмет попадает в заказ сам")
do
    -- Предмет, которого нет во внешней базе: клиент знает имя, база молчит.
    -- Это должно появиться в заказе без единого вызова Diag:Want из теста.
    local env = H.load({})
    local ns = env.ns
    env.itemDBMirror = false
    H.item(env, 950001, { name = "Безымянный пояс", equipLoc = "INVTYPE_WAIST",
        reqLevel = 10, classID = 4, subclassID = 1, sellPrice = 100 })
    env.stats[950001] = { ITEM_MOD_SPELL_POWER_SHORT = 5 }
    env.bags[950001] = 1
    H.item(env, 950002, { name = "Материал", sellPrice = 1 })
    env.vendorPrices[950002] = 10
    H.profession(env, "Портняжное дело", 225, 225, {
        H.recipe { id = 95001, output = 950001, name = "Безымянный пояс",
                   reagents = { { itemID = 950002, qty = 1 } },
                   diff = "trivial", category = "Пояса" },
    })
    H.itemsChanged(env)
    H.build(env)

    local b = wantedOf(ns, "itemsNotInDB")
    H.ok(b ~= nil and b.total > 0,
        "заказ на предметы заполнился сам: " .. tostring(b and b.total))
    if b then
        local e = b.items["950001"]
        H.ok(e ~= nil, "и в нём именно тот предмет, чьи бонусы не прочитались")
        if e then
            local places = {}
            for w, n in pairs(e.where) do places[#places + 1] = w .. "=" .. n end
            table.sort(places)
            H.ok(e.where.bags ~= nil, "с пометкой «в сумке», а не «неизвестно где»: "
                .. table.concat(places, ","))
            H.eq(e.where.unknown, nil,
                "и пометки «неизвестно где» среди них нет")
        end
    end
end

H.suite("Заказ данных: рецепт без состава попадает в заказ по recipeID")
do
    local env = H.load()
    local ns = env.ns
    H.item(env, 960001, { name = "Изделие", sellPrice = 50 })
    H.profession(env, "Портняжное дело", 225, 225, {
        H.recipe { id = 96001, output = 960001, name = "Изделие без схемы",
                   reagents = {}, diff = "trivial", category = "Пояса" },
    })
    H.build(env)
    local b = wantedOf(ns, "recipesNoSchematic")
    H.ok(b ~= nil and b.total > 0, "заказ на схемы рецептов заполнен")
    if b then
        local e = b.items["96001"]
        H.ok(e ~= nil, "и в нём нужный recipeID")
        if e then
            H.eq(e.name, "Изделие без схемы", "с названием рецепта")
            H.eq(e.output, 960001, "и с тем, что он делает")
        end
    end
end

H.suite("Заказ данных: предмет без цены попадает в заказ с веткой")
do
    local env = H.load()
    local ns = env.ns
    env.auctionator = false
    H.item(env, 970001, { name = "Изделие", sellPrice = 0 })
    H.item(env, 970002, { name = "Недобываемый материал", sellPrice = 0 })
    H.profession(env, "Портняжное дело", 225, 225, {
        H.recipe { id = 97001, output = 970001, name = "Изделие",
                   reagents = { { itemID = 970002, qty = 2 } },
                   diff = "optimal", category = "Пояса" },
    })
    H.build(env)
    local b = wantedOf(ns, "itemsNoPrice")
    H.ok(b ~= nil and b.total > 0, "заказ на цены заполнен")
    if b then
        local any
        for _, e in pairs(b.items) do any = any or e end
        H.ok(any ~= nil and next(any.where) ~= nil,
            "и у записи есть пометка, в какой ветке цена понадобилась")
    end
end

-- «ДАННЫХ НЕ ХВАТИЛО ПО 5741 ЦЕНЕ» - ЧИСЛО, КОТОРОГО НЕ БЫЛО =============
--
-- Живая сводка сообщала «Данных не хватило по 5 предметам, 5741 цене». Пять
-- тысяч - это половина базы предметов, и первый вывод из такой строки - что
-- горизонт предсказания тянет цены на пол-игры. Это оказалось неправдой: за
-- пересчёт аддон спрашивает цену по 227 РАЗНЫМ предметам, и это круг его
-- собственных рецептов.
--
-- Врал сам счётчик. Когда список сохранённых позиций заполнен (WANT_KEEP = 40),
-- новая позиция НЕ ЗАПОМИНАЛАСЬ - и на следующем пересчёте считалась новой
-- опять. `total` поэтому рос не по числу разных предметов, а по числу
-- пересчётов. Проверяется это прямо: в живом файле 66 пересчётов дали 7849, а
-- 50 пересчётов - 5740, то есть ровно 119 и 115 «новых» позиций за пересчёт.

H.suite("Заказ данных: повтор того же ID не раздувает счётчик")
do
    local env = H.load()
    local ns = env.ns
    local KEEP = ns.Diag.WANT_KEEP
    -- Сто разных предметов, и каждый встречается пять раз - как пять пересчётов.
    for _ = 1, 5 do
        for i = 1, 100 do
            ns.Diag:Want("pricesStale", 200000 + i, "profit", { ageSeconds = 86400 })
        end
    end
    local b = wantedOf(ns, "pricesStale")
    H.ok(b ~= nil, "корзина заказа есть")
    if b then
        H.eq(b.kept, KEEP, "сохранено " .. KEEP .. " позиций — файл не растёт")
        H.eq(b.hits, 500, "попаданий 500, как и было вызовов")
        H.eq(b.total, 100,
            "а РАЗНЫХ предметов сто, а не пятьсот: " .. tostring(b.total))
        H.eq(b.truncated, true, "и отмечено, что список урезан")
    end
end

H.suite("Заказ данных: старая цена — это не «нет данных»")
do
    -- Цена, которой сутки, у аддона ЕСТЬ. Складывать её с «цены нет ни в одном
    -- источнике» в одно число «данных не хватило по N ценам» - значит выдавать
    -- известное за неизвестное.
    local env = H.load()
    local ns = env.ns
    ns.Diag:Want("itemsNoPrice", 11, "profit")
    for i = 1, 7 do
        ns.Diag:Want("pricesStale", 20 + i, "profit", { ageSeconds = 86400 })
    end
    local t = ns.Diag:WantedTotals()
    H.eq(t.itemsNoPrice, 1, "без цены — один предмет")
    H.eq(t.pricesStale, 7, "со старой ценой — семь")
    H.eq(t.pricesMissingTotal, 1,
        "и «не хватило цен» считает только то, чего правда нет")
    H.eq(t.pricesStaleTotal, 7, "а старые цены считаются отдельно")

    local line = ns.Diag:WantedLine()
    H.ok(line ~= nil, "строка собрана")
    if line then
        H.ok(ns.Util.contains(line, "1 цене") or ns.Util.contains(line, "1 цена"),
            "в «не хватило» попала одна цена, а не восемь: " .. line)
        H.ok(ns.Util.contains(line, "старше суток")
             or ns.Util.contains(line, "не сегодняшн"),
            "а про семь старых сказано отдельно и другими словами: " .. line)
        H.eq(ns.Util.contains(line, "8 цен"), false,
            "и нигде не сложено в одно число")
    end
end

H.suite("Заказ данных: всё свежо — про старые цены молчим")
do
    local env = H.load()
    local ns = env.ns
    ns.Diag:Want("itemsNotInDB", 1, "bags")
    local line = ns.Diag:WantedLine()
    H.ok(line ~= nil, "строка есть")
    if line then
        H.eq(ns.Util.contains(line, "старше суток"), false,
            "но про старые цены в ней ничего: " .. line)
    end
end

H.suite("Версии внешних данных: раздел собирается")
do
    local env = H.load()
    local ns = env.ns
    local dv = ns.Diag:CaptureDataVersions()
    H.ok(dv ~= nil, "раздел dataVersions собран")
    if dv then
        H.ok(type(dv.ours) == "table", "про свои данные есть")
        H.eq(dv.ours.addonVersion, ns.VERSION, "версия аддона записана")
        H.ok(dv.ours.foreverSourceOrigin ~= nil or dv.ours.foreverSource ~= nil,
            "и происхождение своего файла данных")
        H.ok(type(dv.external) == "table" and #dv.external > 0,
            "и список внешних баз: " .. #dv.external)
        H.ok(type(dv.rows) == "table", "и сколько строк они реально отдали")
    end
end

end
