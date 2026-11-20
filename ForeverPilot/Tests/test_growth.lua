-- ForeverPilot / Tests/test_growth.lua
--
-- АДДОН НЕ ПЕРЕСТАЁТ БЫТЬ ПОЛЕЗНЫМ ПО МЕРЕ РОСТА УРОВНЯ.
--
-- Вопрос, на который отвечает набор: что произойдёт, когда игрок возьмёт 27,
-- 30, 35, 45 уровень? Четыре вещи должны случиться САМИ, без единого ручного
-- действия:
--
--   1. рецепты и вещи выше по уровню попадут в сравнение (сейчас они отсеяны
--      как «нельзя надеть»);
--   2. часть советов «надеть нельзя, но продать можно» перейдёт в «теперь
--      можно надеть»;
--   3. поднявшийся потолок навыка будет замечен и назван;
--   4. горизонт пересоберётся и начнёт копить цены на следующий ранг.
--
-- И отдельно - то, из-за чего набор вообще нужен: НИГДЕ НЕ ДОЛЖНО БЫТЬ ЗАШИТЫХ
-- ГРАНИЦ. Ни «до 60 уровня», ни «225 это максимум»: в Forever потолок навыка
-- двигается сам, и аддон уже один раз на этом ошибся.
--
-- Набор прогоняется на одном и том же наборе рецептов с разными уровнями
-- персонажа, и печатает, что изменилось, - чтобы это мог прочитать человек.
local H = ...

return function()

-- Один мир, одни рецепты, разный уровень. Вещи специально разложены по полосам
-- уровней: 20 (доступна сразу), 28, 35, 42.
local function worldAt(level)
    local env = H.load()
    local ns = env.ns
    env.player.level = level
    env.money = 58052
    env.auctionator = true

    local GEAR = {
        { id = 9101, req = 20, name = "Шёлковый пояс",        slot = "INVTYPE_WAIST", arc = 4 },
        { id = 9102, req = 28, name = "Пояс из ткани Грез",   slot = "INVTYPE_WAIST", arc = 9 },
        { id = 9103, req = 35, name = "Пояс из рунной ткани", slot = "INVTYPE_WAIST", arc = 14 },
        { id = 9104, req = 42, name = "Пояс из тьмы",         slot = "INVTYPE_WAIST", arc = 20 },
    }
    H.item(env, 9001, { name = "Ткань", sellPrice = 50 })
    env.vendorPrices[9001] = 200
    env.bags[9001] = 200

    local recipes = {}
    for i, g in ipairs(GEAR) do
        H.item(env, g.id, { name = g.name, equipLoc = g.slot, reqLevel = g.req,
            classID = 4, subclassID = 1, quality = 2, sellPrice = 400 + i * 100 })
        -- Школьный урон кладём во внешнюю базу: именно он делает эти вещи
        -- сравнимыми для мага-арканиста, и именно его клиент не отдаёт.
        env.foreignItemStats[g.id] = { sta = 5 + i, spArcane = g.arc }
        env.foreignItemRecords[g.id] = {
            id = g.id, inv = 6, ilvl = g.req + 5, req = g.req, quality = 2,
            class = 4, subclass = 1,
            stats = { sta = 5 + i, spArcane = g.arc },
        }
        env.prices[g.id] = 20000 + i * 5000
        recipes[#recipes + 1] = H.recipe {
            id = 9200 + i, output = g.id, name = g.name,
            diff = (i == 1) and "trivial" or "optimal",
            category = "Пояса",
            reagents = { { itemID = 9001, qty = 2 } },
        }
    end
    -- Надето что-то слабое, чтобы было что улучшать.
    H.item(env, 9000, { name = "Старый поясок", equipLoc = "INVTYPE_WAIST",
        reqLevel = 10, classID = 4, subclassID = 1, quality = 1, sellPrice = 50 })
    env.foreignItemStats[9000] = { sta = 2, spArcane = 1 }
    env.foreignItemRecords[9000] = { id = 9000, inv = 6, ilvl = 15, req = 10,
        quality = 1, class = 4, subclass = 1, stats = { sta = 2, spArcane = 1 } }
    env.equipped.WAIST = { itemID = 9000 }

    -- И ЖЕМЧУЖНАЯ ЛИНИЯ НА ОСТАЛЬНОМ, как у настоящего персонажа (у него по
    -- надетым вещам ARCANE=38). Без этого школа не определяется, и аддон
    -- правильно отказывается утверждать «лучше» - но тогда проверяется уже не
    -- рост уровня, а определение школы, то есть совсем другой контракт.
    local WORN = {
        { id = 9010, slot = "INVTYPE_HEAD",     inv = 1,  arc = 11 },
        { id = 9011, slot = "INVTYPE_CHEST",    inv = 5,  arc = 13 },
        { id = 9012, slot = "INVTYPE_SHOULDER", inv = 3,  arc = 5 },
    }
    local slotOf = { INVTYPE_HEAD = "HEAD", INVTYPE_CHEST = "CHEST",
                     INVTYPE_SHOULDER = "SHOULDER" }
    for _, w in ipairs(WORN) do
        H.item(env, w.id, { name = "Жемчужное #" .. w.id, equipLoc = w.slot,
            reqLevel = 20, classID = 4, subclassID = 1, quality = 2, sellPrice = 300 })
        env.foreignItemStats[w.id] = { sta = 8, spArcane = w.arc }
        env.foreignItemRecords[w.id] = { id = w.id, inv = w.inv, ilvl = 30,
            req = 20, quality = 2, class = 4, subclass = 1,
            stats = { sta = 8, spArcane = w.arc } }
        env.equipped[slotOf[w.slot]] = { itemID = w.id }
    end
    env.itemDBMirror = false

    H.profession(env, "Портняжное дело", 225, 225, recipes)
    H.itemsChanged(env)
    return env, GEAR
end

local function counts(env)
    local ns = env.ns
    local cards = H.build(env)
    local out = { cards = #cards, gear = 0, profit = 0, wearable = 0, unwearable = 0,
                  titles = {} }
    for _, c in ipairs(cards) do
        if c.kind == ns.KIND.CRAFT_GEAR then
            out.gear = out.gear + 1
            out.titles[#out.titles + 1] = c.title
        elseif c.kind == ns.KIND.CRAFT_PROFIT then
            out.profit = out.profit + 1
        end
    end
    -- Что ветка экипировки считает надеваемым на этом уровне.
    local stats = ns.GearAdvisor.lastStats or {}
    out.wearable = stats.wearable or 0
    out.unwearable = stats.unwearable or 0
    return out, cards
end

H.suite("Рост уровня: с уровнем в сравнение попадает больше вещей")
do
    local seen = {}
    for _, level in ipairs({ 26, 30, 35, 45 }) do
        local env = worldAt(level)
        local c = counts(env)
        seen[level] = c
        print(string.format("     %2d ур.: надеваемых %d, не надеть %d,"
            .. " советов «скрафтить» %d, «на продажу» %d",
            level, c.wearable, c.unwearable, c.gear, c.profit))
    end

    -- НЕ УМЕНЬШАЕТСЯ НИ НА ОДНОМ ШАГЕ: с ростом уровня вещи только становятся
    -- доступны, обратно не отбираются.
    H.ok(seen[30].wearable >= seen[26].wearable,
        "на 30 надеваемых не меньше, чем на 26: "
        .. seen[26].wearable .. " → " .. seen[30].wearable)
    H.ok(seen[35].wearable >= seen[30].wearable,
        "на 35 не меньше, чем на 30: "
        .. seen[30].wearable .. " → " .. seen[35].wearable)
    H.ok(seen[45].wearable >= seen[35].wearable,
        "на 45 не меньше, чем на 35: "
        .. seen[35].wearable .. " → " .. seen[45].wearable)
    -- И РОСТ ЕСТЬ: иначе проверка выше проходила бы на вечном нуле.
    H.ok(seen[45].wearable > seen[26].wearable,
        "от 26 к 45 надеваемых стало заметно больше: "
        .. seen[26].wearable .. " → " .. seen[45].wearable)
    H.ok(seen[45].unwearable < seen[26].unwearable,
        "а «нельзя надеть» — меньше: "
        .. seen[26].unwearable .. " → " .. seen[45].unwearable)
end

H.suite("Рост уровня: «нельзя надеть, но продать» становится «можно надеть»")
do
    local low = worldAt(26)
    local lowCards = select(2, counts(low))
    local ns = low.ns
    -- На 26 уровне пояс с требованием 35 продаётся, но не надевается.
    local sellOnly35
    for _, c in ipairs(lowCards) do
        if c.itemID == 9103 then sellOnly35 = c end
    end
    H.ok(sellOnly35 ~= nil, "про пояс 35 уровня совет на 26 есть")
    if sellOnly35 then
        H.eq(sellOnly35.kind, ns.KIND.CRAFT_PROFIT,
            "и это совет ПРОДАТЬ, а не надеть")
        H.ok(ns.Util.contains(sellOnly35.why, "надеть")
             or ns.Util.contains(sellOnly35.why, "не можете"),
            "и сказано, что надеть нельзя: "
            .. ns.Util.truncate(sellOnly35.why, 110))
    end

    -- На 35 он же — улучшение экипировки.
    local hi = worldAt(35)
    local hiCards = select(2, counts(hi))
    local nsHi = hi.ns
    local upgrade35
    for _, c in ipairs(hiCards) do
        if c.itemID == 9103 and c.kind == nsHi.KIND.CRAFT_GEAR then upgrade35 = c end
    end
    H.ok(upgrade35 ~= nil,
        "на 35 уровне тот же пояс — уже совет НАДЕТЬ (скрафтить под себя)")
    if upgrade35 then
        H.ok(upgrade35.benefitValue and upgrade35.benefitValue > 0,
            "с посчитанным приростом: " .. tostring(upgrade35.benefit))
    end
end

H.suite("Рост уровня: ничего из этого не требует ручных действий")
do
    -- Один и тот же мир, уровень меняется «в игре»: событие PLAYER_LEVEL_UP,
    -- пересчёт, и советы другие. Никаких /fp scan.
    local env = worldAt(26)
    local ns = env.ns
    local frame = { registered = {}, scripts = {} }
    function frame:RegisterEvent(n) self.registered[n] = true end
    function frame:UnregisterEvent(n) self.registered[n] = nil end
    function frame:SetScript(w, f) self.scripts[w] = f end
    env.G.C_EventUtils = { IsEventValid = function() return true end }
    ns.Events:Init(frame, function() end)

    local rebuilds = 0
    ns.Events:On("recompute", function()
        rebuilds = rebuilds + 1
        ns.CharacterScanner:Scan()
        ns.ActionEngine:Build()
    end)

    H.clock = 1000
    ns.Events:Reset()
    H.build(env)
    local before = (ns.GearAdvisor.lastStats or {}).wearable or 0

    -- Игрок взял уровни. Ровно так, как это приходит из игры.
    env.player.level = 36
    ns.Events:OnEvent("PLAYER_LEVEL_UP")
    H.clock = 1000 + ns.RECOMPUTE_DEBOUNCE + 0.01
    ns.Events:Tick()
    H.eq(rebuilds, 1, "пересчёт случился сам, по событию уровня")

    local after = (ns.GearAdvisor.lastStats or {}).wearable or 0
    H.ok(after > before,
        "и в сравнение попало больше вещей без единого ручного действия: "
        .. before .. " → " .. after)
end

H.suite("Рост уровня: поднявшийся потолок навыка замечается и называется")
do
    local env = worldAt(26)
    local ns = env.ns
    local said = {}
    env.ns.Api.Print = function(_, msg) said[#said + 1] = msg end
    H.rescan(env)

    ns.Notifier:CheckSkillCap("первая встреча")
    H.eq(#said, 0, "при первой встрече ничего не объявляется — просто запомнили")

    -- Потолок поехал: ровно то, что в Forever происходит само.
    env.professions[1].max = 240
    H.rescan(env)
    ns.Notifier:CheckSkillCap("тест")
    H.ok(#said >= 1, "о подъёме сказано")
    local text = table.concat(said, " | ")
    H.ok(ns.Util.contains(text, "225") and ns.Util.contains(text, "240"),
        "с обоими числами: " .. ns.Util.truncate(text, 140))
    H.ok(ns.Util.contains(text, "15") or ns.Util.contains(text, "пункт"),
        "и сколько теперь можно качать")

    -- Второй раз про то же не говорится.
    local n = #said
    ns.Notifier:CheckSkillCap("тест")
    H.eq(#said, n, "и повторно про тот же подъём — молчок")
end

H.suite("Рост уровня: потолок навыка нигде не зашит числом")
do
    -- В Forever лестницы 75/150/225/300 нет, и аддон уже один раз на этом
    -- ошибся. Проверяется по исходникам: ни один файл логики не вправе
    -- содержать «потолок = 225» или подобное.
    local files = {
        "Logic/CraftingPlanner.lua", "Logic/ActionEngine.lua",
        "Logic/Foresight.lua", "Logic/Notifier.lua",
        "Logic/CharacterScanner.lua", "Core/Const.lua",
    }
    for _, rel in ipairs(files) do
        local fh = io.open(H.ROOT .. "/" .. rel, "r")
        if fh then
            local src = fh:read("*a")
            fh:close()
            local code = src:gsub("%-%-[^\n]*", "")
            -- Ищем присваивания максимума/потолка числом.
            local bad = code:match("max%s*=%s*225") or code:match("MAX_SKILL%s*=%s*%d")
                or code:match("SKILL_CAP%s*=%s*%d+") or code:match("maxSkill%s*=%s*%d+")
            H.eq(bad, nil, rel .. ": потолок навыка числом не зашит")
            -- И уровень 60 как граница тоже.
            local lvl = code:match("MAX_LEVEL%s*=%s*%d+") or code:match("level%s*>%s*60")
            H.eq(lvl, nil, rel .. ": предел уровня числом не зашит")
        end
    end
end

H.suite("Рост уровня: горизонт двигается вместе с персонажем")
do
    local env = worldAt(26)
    local ns = env.ns
    H.rescan(env)
    local a = ns.Foresight:Collect(ns.CharacterScanner:Get(), 1000)
    H.eq(a.levelBand.from, 27, "на 26 горизонт начинается с 27")
    H.eq(a.levelBand.to, 36, "и кончается на 36")

    env.player.level = 40
    H.rescan(env)
    local b = ns.Foresight:Collect(ns.CharacterScanner:Get(), 2000)
    H.eq(b.levelBand.from, 41, "на 40 — с 41")
    H.eq(b.levelBand.to, 50, "и до 50: полоса едет за персонажем, а не стоит")

    -- И горизонт навыка тоже от текущего максимума, а не от зашитого числа.
    env.professions[1].max = 300
    H.rescan(env)
    local c = ns.Foresight:Collect(ns.CharacterScanner:Get(), 3000)
    local prof
    for _, s in ipairs(c.skills) do
        if s.name == "Портняжное дело" then prof = s end
    end
    H.ok(prof ~= nil, "профессия в горизонте есть")
    if prof then
        H.eq(prof.aheadTo, 375,
            "потолок 300 → горизонт 375: никакого «300 это конец»")
    end
end

H.suite("Рост уровня: на каждом уровне список непустой и осмысленный")
do
    -- Самое простое и самое важное: аддон не должен замолчать ни на одном
    -- уровне. Пустой список на 45 уровне - это и есть «перестал быть полезным».
    for _, level in ipairs({ 26, 27, 30, 35, 45, 60 }) do
        local env = worldAt(level)
        local ns = env.ns
        local cards = H.build(env)
        H.ok(#cards > 0, level .. " ур.: список не пустой (" .. #cards .. ")")
        local actionable = 0
        for _, c in ipairs(cards) do
            if not c.informational and c.kind ~= ns.KIND.SETUP then
                actionable = actionable + 1
            end
        end
        H.ok(actionable > 0, level .. " ур.: есть что сделать, а не только справка ("
            .. actionable .. ")")
    end
end

end
