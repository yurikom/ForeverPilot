-- ForeverPilot / Tests/test_real.lua
--
-- Integration test against the player's actual SavedVariables: the 900 cached
-- recipes, the real bags and equipment, the real money. The point is not to
-- assert exact numbers - those move every time the player plays - but to prove
-- the pipeline produces a sensible, non-empty, non-garbage list from real input,
-- and to print it so a human can judge it.
--
-- Run with:  lua Tests/run.lua real
local H = ...

return function()

-- Where the live SavedVariables are: asked once, in Tests/paths.lua. The path
-- depends on the machine and contains the player's account folder name, so it
-- is not written here - it comes from FP_WTF, FP_ACCOUNT or Tests/local_paths.lua.
--
-- И ЕСЛИ НЕ ОТВЕТИЛ НИКТО - ЭТОТ НАБОР ГОВОРИТ ОБ ЭТОМ И ПРОПУСКАЕТСЯ.
-- Не «проходит», не падает - именно пропускается с названной причиной. Молчать
-- тут нельзя: `run.lua real` однажды уже не запускал 31 раздел и выглядел
-- зелёным, и узнать об этом было неоткуда.
local P = assert(loadfile(H.ROOT .. "/Tests/paths.lua"))()
local WTF, pathInfo = P.savedVariables(H.ROOT)
if not WTF then
    H.suite("Реальные данные: пропущены")
    H.note("набор на настоящих данных пропущен — " .. pathInfo.reason)
    return
end

-- Load a SavedVariables file into a table of its globals.
local function loadSV(name)
    local path = WTF .. "/" .. name
    local chunk = loadfile(path)
    if not chunk then return nil, path end
    local env = {}
    setfenv(chunk, setmetatable(env, { __index = function() return nil end }))
    local ok, err = pcall(chunk)
    if not ok then return nil, path, err end
    return env, path
end

local mc, mcPath = loadSV("Mastercraft.lua")
local syn = loadSV("Syndicator.lua")
-- Собственные суточные слепки цен игрока: единственные настоящие наблюдения
-- рынка, которые читаются офлайн (база Auctionator лежит сжатым блобом).
local fp = loadSV("ForeverPilot.lua")
local au = loadSV("Auctionator.lua")

-- КЕШ ЦЕН ТОРГОВЦЕВ AUCTIONATOR - ЕДИНСТВЕННЫЕ ЧЕСТНЫЕ ПОТОЛКИ В ЕГО ФАЙЛАХ.
--
-- В игре их отдаёт Auctionator.API.v1.GetVendorPriceByItemID, то есть
-- Api:VendorPrice, то есть env.vendorPrices в стенде. Его собственный код
-- (Source/CraftingInfo/Main.lua) пишет запись ТОЛЬКО при numAvailable == -1 и
-- делит цену окна на размер стопки - значит это цены с неограниченной полки, а
-- не «сколько торговец даёт».
--
-- Без этого чтения набор на настоящих данных не видел НИ ОДНОГО потолка: цена
-- материала приходила только с аукциона, и правило min(аукцион, торговец)
-- проверять было нечем. Ровно тот случай, из-за которого в этом проекте и
-- появилось правило «меряй на настоящих данных»: на выдуманных фикстурах всё
-- было зелёным.
local function vendorCeilings(sv)
    local out, n = {}, 0
    for key, value in pairs((sv and sv.AUCTIONATOR_VENDOR_PRICE_CACHE) or {}) do
        local id, copper = tonumber(key), tonumber(value)
        if id and copper and copper > 0 then out[id] = copper; n = n + 1 end
    end
    return out, n
end

H.suite("Реальные данные: файлы на месте")
H.ok(mc and mc.MastercraftDB, "кеш рецептов прочитан (" .. tostring(mcPath) .. ")")
H.ok(syn and syn.SYNDICATOR_DATA, "кеш инвентаря прочитан")
-- И КЕШ ЦЕН ТОРГОВЦЕВ - ОТДЕЛЬНОЙ СТРОКОЙ. Пока его не читали, проверки
-- вендорного потолка на настоящих данных пропускались молча: «потолков 0»
-- выглядело как «их у игрока нет», а не как «мы их не прочли».
H.ok(au ~= nil, "кеш цен торговцев Auctionator прочитан"
    .. ((au == nil) and "  <- файла Auctionator.lua рядом нет" or ""))
if au ~= nil then
    local _, n = vendorCeilings(au)
    H.ok(n > 0, "вендорных цен в нём: " .. n)
end
if not (mc and mc.MastercraftDB) then
    print("  !! без кеша рецептов остальные проверки пропущены")
    return
end

local db = mc.MastercraftDB

-- Pick the character with the most professions: that is the mage.
local GUID, charInfo
for guid, info in pairs(db.chars or {}) do
    local n = #(info.professions or {})
    if (not charInfo) or n > #(charInfo.professions or {}) then
        GUID, charInfo = guid, info
    end
end

H.suite("Реальные данные: персонаж")
H.ok(GUID ~= nil, "персонаж найден: " .. tostring(charInfo and charInfo.name))
H.ok(charInfo and charInfo.level and charInfo.level > 0,
    "уровень " .. tostring(charInfo and charInfo.level))
H.ok(charInfo and #(charInfo.professions or {}) > 0,
    #(charInfo and charInfo.professions or {}) .. " профессий")

local recipeCache = db.recipes and db.recipes[GUID]
H.ok(recipeCache ~= nil, "кеш рецептов для этого персонажа есть")

local totalRecipes, learnedRecipes = 0, 0
for _, bucket in pairs(recipeCache or {}) do
    for _, r in pairs(bucket.list or {}) do
        totalRecipes = totalRecipes + 1
        if r.learned then learnedRecipes = learnedRecipes + 1 end
    end
end
H.ok(totalRecipes > 500, totalRecipes .. " рецептов в кеше")
H.ok(learnedRecipes > 50, learnedRecipes .. " из них выучено")

-- Build the fake client out of the real data -----------------------------

local env = H.load({ serverTime = (charInfo and charInfo.updated) or 1794800000 })
local ns = env.ns

-- ИМЯ И ФАМИЛИЯ ПОРОЗНЬ, КАК ИХ ОТДАЁТ КЛИЕНТ. Кеш Mastercraft хранит их в
-- двух полях ровно потому, что UnitName на Forever отдаёт два значения. Класть
-- сюда готовое полное имя значило бы скрыть всю ошибку с одноимёнными
-- персонажами: у игрока их двое, и оба зовутся «Гендольф».
env.player.name = charInfo.name
env.player.surname = charInfo.surname
env.player.level = charInfo.level
env.player.classFile = charInfo.classFile
env.player.className = charInfo.class
env.player.raceName = charInfo.race
env.player.factionFile = charInfo.faction
env.player.guid = GUID
env.player.realm = charInfo.realm
env.money = charInfo.money or 0
env.spec = nil  -- the real client gives us no spec at this level

for _, prof in ipairs(charInfo.professions or {}) do
    env.professions[#env.professions + 1] = {
        name = prof.name, skill = prof.skill, max = prof.max,
        maxKnown = (tonumber(prof.max) or 0) > 0, skillTrusted = true,
    }
end
env.foreignDB = db

-- The item database, wired in where the game would call Polestar. Without it
-- the client's half alone cannot see equip bonuses, which is the state the gear
-- advice has to survive - and the state the old version of this suite silently
-- asserted as correct behaviour.
local itemDBRows = H.installRealItemDB(env)
H.suite("Реальные данные: внешняя база предметов")
H.ok(itemDBRows ~= nil, "база предметов подключена: "
    .. tostring(itemDBRows) .. " строк")

-- История навыка в файле игрока: что в ней записано на самом деле ----------
--
-- Этот набор назывался «потолок навыка динамический» и доказывал это по файлу
-- игрока: мол, «потолки» 84, 93, 160, 224 не ложатся в лестницу 75/150/225/300.
-- Это были не потолки. MastercraftDB.history[персонаж][день].s[профессия] -
-- пара { навык, увиденный в этот день первым; навык, увиденный последним }.
-- Аддон из этой ошибки говорил игроку на карточке: «потолок уже поднимался
-- (4 раза): последний раз 2026-11-15, 224 -> 225».
--
-- Здесь то же проверяется на тех же настоящих данных - формой свидетельства,
-- а не сегодняшними числами: они меняются каждый раз, когда игрок играет.

H.suite("Реальные данные: в истории Mastercraft записан навык, а не потолок")
do
    local hist = ns.Api:MastercraftSkillHistory(GUID)
    H.ok(hist ~= nil, "история навыков по дням прочитана из MastercraftDB")

    if hist then
        H.ok(#hist >= 2, #hist .. " дней в истории")

        local profNames = {}
        for _, day in ipairs(hist) do
            for name in pairs(day.skills or {}) do profNames[name] = true end
        end

        -- Свойство навыка, которого нет у потолка: день начинается с того числа,
        -- которым кончился предыдущий. Считаем по всем профессиям и всем дням.
        local links, chained, fell, total = 0, 0, 0, 0
        for name in pairs(profNames) do
            total = total + 1
            local days = ns.Api:MastercraftSkillHistory(GUID, name) or {}
            for i = 1, #days do
                if days[i].first and days[i].last and days[i].last < days[i].first then
                    fell = fell + 1
                end
                if i > 1 and days[i].first and days[i - 1].last then
                    links = links + 1
                    if days[i].first == days[i - 1].last then chained = chained + 1 end
                end
            end
        end
        H.ok(links > 10, "переходов между днями проверено: " .. links
            .. " (профессий " .. total .. ")")
        H.ok(chained >= links * 0.9, string.format(
            "день начинается с числа, которым кончился предыдущий: %d из %d — это навык, а не потолок",
            chained, links))
        H.eq(fell, 0, "за день число ни разу не упало: навык растёт или стоит")
    end

    -- Максимум в кеше есть в одном месте - chars, и это число клиента.
    local cached = ns.Api:MastercraftProfessions(GUID)
    H.ok(cached ~= nil and #cached > 0, "кеш профессий читается")
    local withMax = 0
    for _, p in ipairs(cached or {}) do
        if p.max then withMax = withMax + 1 end
        local days = ns.Api:MastercraftSkillHistory(GUID, p.name)
        local newest = days and days[#days]
        if newest and newest.last and p.skill then
            H.ok(p.skill >= newest.last, string.format(
                "%s: навык в chars (%d) не меньше последнего навыка в истории (%d)",
                p.name, p.skill, newest.last))
        end
    end
    H.ok(withMax > 0, "максимум записан в chars у " .. withMax .. " профессий — и только там")
    H.eq(ns.Api.SkillCapMoves, nil, "«подъёмы потолка» из истории навыка больше не считаются")
end

H.suite("Реальные данные: цель прокачки берётся из max")
do
    for _, prof in ipairs(env.professions) do
        local goal, remaining = ns.CraftingPlanner:SkillGoal(prof)
        if prof.skill and prof.max and prof.skill < prof.max then
            H.eq(goal, prof.max, prof.name .. ": цель = max из данных (" .. prof.max .. ")")
            H.eq(remaining, prof.max - prof.skill, prof.name .. ": остаток посчитан")
        else
            H.eq(goal, nil, (prof.name or "?")
                .. ": цели нет (" .. tostring(prof.skill) .. "/" .. tostring(prof.max) .. ")")
        end
    end
end

-- Item facts we can derive honestly from the real data:
--   * every reagent and every output of every cached recipe exists
--   * names come from the recipe or the observed-auction records
--   * a crafted item's equip slot is derived from its recipe category, which is
--     exactly the fallback the addon itself uses when the client has not cached
--     the item yet
local CATEGORY_EQUIPLOC = {
    ["Капюшоны"] = "INVTYPE_HEAD",
    ["Наплечья"] = "INVTYPE_SHOULDER",
    ["Наручи"] = "INVTYPE_WRIST",
    ["Обувь"] = "INVTYPE_FEET",
    ["Одеяния и жилеты"] = "INVTYPE_CHEST",
    ["Перчатки"] = "INVTYPE_HAND",
    ["Плащи"] = "INVTYPE_CLOAK",
    ["Поножи"] = "INVTYPE_LEGS",
    ["Пояса"] = "INVTYPE_WAIST",
    ["Рубашки"] = "INVTYPE_BODY",
    ["Сумки"] = "INVTYPE_BAG",
    ["Особые сумки"] = "INVTYPE_BAG",
}

-- Observed auction prices for this realm, newest entry per item.
local realm = next(db.costs or {})
local observed = {}
if realm then
    for itemID, entries in pairs(db.costs[realm] or {}) do
        local best, bestT = nil, -1
        for _, e in ipairs(entries) do
            local t, c = tonumber(e.t) or 0, tonumber(e.c)
            if c and c > 0 and t > bestT then best, bestT = c, t end
        end
        if best then observed[itemID] = best end
    end
end
-- Scanned auction listings give us names and more prices.
local scanNames = {}
if realm and db.prices and db.prices[realm] and db.prices[realm].versions then
    for itemID, versions in pairs(db.prices[realm].versions) do
        local cheapest, name
        for _, v in pairs(versions) do
            local p = tonumber(v.p)
            if p and p > 0 and ((not cheapest) or p < cheapest) then
                cheapest, name = p, v.name
            end
        end
        if cheapest then
            observed[itemID] = observed[itemID] or cheapest
            scanNames[itemID] = name
        end
    end
end

env.observedPrices = observed
env.foreignVendorPrices = db.vendorPrices or {}
-- Auctionator is modelled as present with the observed prices as its data, so
-- the "with prices" run is realistic; a second run below turns it off.
env.prices = observed
env.auctionator = true
local realCeilings, realCeilingCount = vendorCeilings(au)
env.vendorPrices = realCeilings

-- Register every item mentioned anywhere in the recipe data.
local function ensureItem(itemID, name, equipLoc, reqLevel)
    if not itemID then return end
    local existing = env.items[itemID]
    if existing then
        existing.name = existing.name or name
        existing.equipLoc = existing.equipLoc or equipLoc
        return
    end
    env.items[itemID] = {
        name = name or scanNames[itemID] or ("Предмет #" .. itemID),
        equipLoc = equipLoc,
        reqLevel = reqLevel,
        classID = equipLoc and 4 or nil,
        subclassID = equipLoc and 1 or nil,  -- the mage's professions make cloth
        sellPrice = observed[itemID] and math.floor(observed[itemID] / 5) or 0,
        quality = 1,
    }
end

local recipesByProf = {}
for profName, bucket in pairs(recipeCache or {}) do
    local list = {}
    for _, r in pairs(bucket.list or {}) do
        list[#list + 1] = {
            id = r.id, name = r.name, learned = r.learned,
            output = r.output, outputQty = r.outputQty,
            reagents = r.reagents, diff = r.diff,
            category = r.category, group = r.group,
            categoryID = r.category,  -- the cache has no numeric id; the name is the key
            icon = r.icon,
        }
        local equipLoc = CATEGORY_EQUIPLOC[r.category or ""]
        -- Item level requirement: the cache does not store it, so we only mark
        -- the ones we can defend. Everything else is treated as wearable, which
        -- is the conservative direction for this test (it means the gear branch
        -- gets MORE candidates, not fewer).
        ensureItem(r.output, r.name, equipLoc, nil)
        for _, g in ipairs(r.reagents or {}) do ensureItem(g.itemID) end
    end
    recipesByProf[profName] = list
end

-- Real bags, bank and equipment from the inventory cache.
-- The two caches name the same character differently: one stores
-- "Гендольф" + surname "Серыйй", the other stores "Гендольф Серыйй". Match on
-- the class token, which both agree on, and break ties by stack count.
local synChar, synCharName
if syn and syn.SYNDICATOR_DATA then
    local best, bestCount = nil, -1
    for name, data in pairs(syn.SYNDICATOR_DATA.Characters or {}) do
        local details = data.details or {}
        local classMatch = (details.className == charInfo.classFile)
        local nameMatch = details.character
            and (details.character == charInfo.name
                 or details.character:find(charInfo.name, 1, true) ~= nil)
        if classMatch or nameMatch then
            local count = 0
            for _, bag in pairs(data.bags or {}) do
                for _, slot in pairs(bag) do
                    if type(slot) == "table" and slot.itemID then count = count + 1 end
                end
            end
            -- Prefer a class match; among those, the fuller inventory.
            local score = (classMatch and 10000 or 0) + count
            if score > bestCount then best, bestCount, synCharName = data, score, name end
        end
    end
    synChar = best
end
H.suite("Реальные данные: сопоставление персонажа между кешами")
H.ok(synChar ~= nil, "инвентарь найден: " .. tostring(synCharName))

-- The inventory cache stores equipped items at (inventory slot id + 1), because
-- it loops from 0. Verified against the actual data: index 2 holds the head
-- item, index 4 holds the shoulders. The addon itself does not go through this
-- cache - it reads GetInventoryItemLink with the real slot ids - so this offset
-- lives only in the test.
local SLOT_BY_INV = {}
do
    local real = {
        [1] = "HEAD", [2] = "NECK", [3] = "SHOULDER", [4] = "SHIRT", [5] = "CHEST",
        [6] = "WAIST", [7] = "LEGS", [8] = "FEET", [9] = "WRIST", [10] = "HANDS",
        [11] = "FINGER1", [12] = "FINGER2", [13] = "TRINKET1", [14] = "TRINKET2",
        [15] = "BACK", [16] = "MAINHAND", [17] = "OFFHAND", [18] = "RANGED",
    }
    for invID, slot in pairs(real) do SLOT_BY_INV[invID + 1] = slot end
end

local bagItems, equippedCount = 0, 0
if synChar then
    for _, bag in pairs(synChar.bags or {}) do
        for _, slot in pairs(bag) do
            if type(slot) == "table" and slot.itemID then
                env.bags[slot.itemID] = (env.bags[slot.itemID] or 0) + (slot.itemCount or 1)
                -- Ссылка из кеша инвентаря целиком: в ней чары этой вещи
                -- (|Hitem:249392:8217:...), а без неё ветка чар считает
                -- зачарованный посох в сумке незачарованным.
                if slot.itemLink then env.bagLinks[slot.itemID] = slot.itemLink end
                bagItems = bagItems + 1
                ensureItem(slot.itemID, slot.itemLink and
                    ns.Util.itemNameFromLink(slot.itemLink) or nil)
                if env.items[slot.itemID] then
                    env.items[slot.itemID].quality = slot.quality or 1
                end
            end
        end
    end
    -- The bank: real tabs if the player has opened it, otherwise genuinely nil.
    local bank = nil
    for _, tab in pairs(synChar.bankTabs or {}) do
        for _, slot in pairs(tab.slots or {}) do
            if type(slot) == "table" and slot.itemID then
                bank = bank or {}
                bank[slot.itemID] = (bank[slot.itemID] or 0) + (slot.itemCount or 1)
                ensureItem(slot.itemID)
            end
        end
    end
    env.bank = bank

    for invID, item in pairs(synChar.equipped or {}) do
        if type(item) == "table" and item.itemID then
            local slot = SLOT_BY_INV[invID]
            if slot then
                env.equipped[slot] = {
                    itemID = item.itemID, link = item.itemLink,
                    enchantID = ns.Util.enchantIDFromLink(item.itemLink),
                }
                equippedCount = equippedCount + 1
                ensureItem(item.itemID,
                    item.itemLink and ns.Util.itemNameFromLink(item.itemLink) or nil)
                local info = env.items[item.itemID]
                if info then
                    info.quality = item.quality or 1
                    -- Worn items have real stats in game; offline we have none,
                    -- so the addon must behave correctly WITHOUT them. That is
                    -- itself worth asserting, below.
                end
            end
        end
    end
end

H.suite("Реальные данные: инвентарь и экипировка")
H.ok(bagItems > 0, bagItems .. " стаков в сумках")
H.ok(equippedCount > 0, equippedCount .. " надетых предметов")
H.ok(env.money > 0, "золото: " .. ns.Util.money(env.money, true))
H.ok(ns.Util.count(env.items) > 100,
    ns.Util.count(env.items) .. " предметов известно по ID")

-- Register the recipes and run the real pipeline --------------------------

for profName, list in pairs(recipesByProf) do
    ns.RecipeBook:Store(profName, list, "foreign", ns.CONF.CACHED, charInfo.updated or 0)
end
ns.RecipeBook:Reindex()

H.suite("Реальные данные: книга рецептов")
local summary = ns.RecipeBook:Summary()
H.ok(#summary > 0, #summary .. " профессий в книге")
for _, s in ipairs(summary) do
    H.ok(s.total > 0, s.name .. ": " .. s.learned .. " выучено из " .. s.total)
end
H.ok(ns.RecipeBook:LearnedCount() > 50,
    ns.RecipeBook:LearnedCount() .. " выученных рецептов проиндексировано")

-- Enchants must have been separated out by having no output item.
local enchantCount, slotted = 0, 0
for _, recipe in pairs(ns.RecipeBook.byID) do
    if recipe.learned and ns.EnchantAdvisor:IsEnchantRecipe(recipe) then
        enchantCount = enchantCount + 1
        if recipe.enchantSlot then slotted = slotted + 1 end
    end
end
H.suite("Реальные данные: чары разложены по слотам")
H.ok(enchantCount > 0, enchantCount .. " выученных формул чар найдено")
H.ok(slotted > 0, slotted .. " из них разложены по слотам")
H.ok(slotted / math.max(1, enchantCount) > 0.7,
    string.format("разложено %.0f%% формул", 100 * slotted / math.max(1, enchantCount)))
local bySlot = ns.EnchantAdvisor:BySlot()
local slotNames = {}
for slot, list in pairs(bySlot) do
    slotNames[#slotNames + 1] = ns.SlotMap:Label(slot) .. "(" .. #list .. ")"
end
table.sort(slotNames)
print("     слоты чар: " .. table.concat(slotNames, ", "))

-- УСТАНОВЛЕННЫЙ Polestar_Codex, А НЕ ПУСТАЯ ЗАГЛУШКА --------------------
--
-- Без этого половина аддона в наборе не выполнялась ВООБЩЕ: торговцы, их цены,
-- координаты NPC, тренеры следующего ранга - всё это спрашивается у Codex, а в
-- тестах Codex был пустой таблицей. Ветка арбитража из-за этого молчала офлайн
-- и выдавала в игре шесть карточек с наценкой 2270%.
--
-- Это те же файлы, что читает игра, и тот же компактный формат. Разбор - в
-- Tests/harness.lua, строительные леса теста; в аддоне разбором занимается сам
-- Codex.
local realCodex = H.installRealCodex(env)
H.suite("Реальные данные: установленный Codex подключён")
H.ok(realCodex ~= nil, "пакет Polestar_Codex найден: "
    .. tostring(realCodex and realCodex.path))
if realCodex then
    H.ok(realCodex.itemCount > 20000,
        realCodex.itemCount .. " предметов в пакете")
    H.ok(realCodex.npcCount > 10000, realCodex.npcCount .. " NPC в пакете")
    -- И тот самый торговец, из-за которого всё это началось. Проверяется не
    -- «есть запись», а ЧТО В НЕЙ: подпись «Agent of the Black Market» - это и
    -- есть ответ на вопрос, что это за NPC.
    local npc = realCodex.npc(263384)
    H.ok(npc ~= nil, "Mister Graphed (263384) в пакете есть")
    if npc then
        H.eq(npc.name, "Mister Graphed", "имя")
        H.eq(npc.subName, "Agent of the Black Market",
            "подпись: " .. tostring(npc.subName))
        H.eq(npc.level, 60, "уровень 60")
        H.ok(#npc.spawns > 0, "и координаты известны")
        if npc.spawns[1] then
            H.near(npc.spawns[1].x, 78.2, 0.2, "x ≈ 78.2")
            H.near(npc.spawns[1].y, 51.9, 0.2, "y ≈ 51.9")
            H.eq(npc.spawns[1].map, 2548, "карта 2548 (Лесоречье)")
        end
    end
    -- ЧТО ПАКЕТ ПРО ЕГО ТОВАР ЗНАЕТ И ЧЕГО НЕ ЗНАЕТ. Условий покупки у этих
    -- записей НЕТ НИКАКИХ: ни репутации, ни требования навыка, ни пометки об
    -- ограниченном запасе. То есть «нужна репутация» и «товар штучный» данными
    -- не подтверждаются - подтверждается только то, что цена одна и та же.
    local lotus = realCodex.item(13468)
    H.ok(lotus ~= nil, "Чёрный лотос (13468) в пакете есть")
    if lotus then
        local v
        for _, s in ipairs(lotus.sources or {}) do
            if s.type == "vendor" and s.npc == 263384 then v = s end
        end
        H.ok(v ~= nil, "и продаёт его именно Mister Graphed")
        if v then
            H.eq(v.cost, 4000, "цена в пакете - 4000 медяков, то есть 40 серебра")
            H.eq(v.limited, nil, "пометки об ограниченном запасе нет")
            H.eq(#(v.from or {}), 1, "и провенанс один: " ..
                table.concat(v.from or {}, "+"))
        end
        H.eq(lotus.repFaction, nil, "репутация для покупки не требуется")
        H.eq(lotus.reqSkill, nil, "навык для покупки не требуется")
    end
    -- А ВОТ ЗАПИСЬ, КОТОРУЮ МОЖНО СВЕРИТЬ СНАРУЖИ. Gift of Galloping (271871)
    -- стоит в пакете 1 500 000 медяков = 150 золотых, и ровно столько за него
    -- просят по двум независимым отчётам сообщества. Значит единица измерения
    -- - медяки, и поле действительно означает цену ПРОДАЖИ, а не выкупа: с
    -- полярностью у источника всё в порядке, неверна величина у реагентов.
    -- ЧЕРТЁЖ ЛАГЕРЯ - И ОН НАЗВАН ПО-РУССКИ. Две отдельные вещи проверяются
    -- одной строкой, и обе нужны ветке лагеря:
    --   * чертежи лежат не в группе «item», а в группе «recipe» - в игре
    --     Codex.Item ищет по пяти группам сразу, и стенд обязан так же;
    --   * имя приходит на языке клиента из пакета имён, как в игре: иначе
    --     осмотр показывал «Blueprint: Journeyman Campfire» там, где игрок
    --     читает «Чертеж: костер подмастерья».
    local blueprint = realCodex.item(273087)
    H.ok(blueprint ~= nil,
        "чертёж костра подмастерья (273087) в пакете есть - в группе рецептов")
    if blueprint then
        H.ok(tostring(blueprint.name):find("[\208\209][\128-\191]") ~= nil,
            "и назван он по-русски: " .. tostring(blueprint.name))
    end

    local gift = realCodex.item(271871)
    if gift then
        local v
        for _, s in ipairs(gift.sources or {}) do
            if s.type == "vendor" and s.npc == 263384 then v = s end
        end
        H.ok(v ~= nil, "Gift of Galloping продаёт тот же NPC")
        H.eq(v and v.cost, 1500000,
            "и цена в пакете - 150 золотых, как и в отчётах сообщества:"
            .. " единица и полярность у поля верные")
    end
end

-- Full pipeline ----------------------------------------------------------

local function run(profile)
    ns.Config:SetProfile(profile)
    local cards, meta, snap = H.build(env)
    return cards, meta, snap
end

H.suite("Реальные данные: список строится")
local cards, meta, snap = run("POWER")
H.ok(#cards > 0, #cards .. " карточек построено")
H.ok(meta.learnedRecipes > 50, meta.learnedRecipes .. " рецептов учтено")

-- Garbage checks: every card must be complete and internally consistent.
--
-- Действия, у которых кнопки нет вовсе, и подписи поэтому быть не должно:
-- информационный совет (noop) и совет про рецепт (findRecipe) - открыть рецепт
-- в окне профессий игра аддонам запрещает, см. ниже.
local NO_BUTTON = { noop = true, findRecipe = true }
local bad = {}
for i, card in ipairs(cards) do
    local function fail(why) bad[#bad + 1] = i .. ":" .. tostring(card.key) .. " " .. why end
    if not card.key or card.key == "" then fail("нет ключа") end
    if not card.title or card.title == "" then fail("нет заголовка") end
    if not card.why or card.why == "" then fail("нет объяснения") end
    if not card.need or card.need == "" then fail("нет строки «чего не хватает»") end
    if not card.benefit or card.benefit == "" then fail("нет выгоды") end
    if not ns.CONF_LABEL[card.conf] then fail("недопустимая достоверность") end
    -- ДЕЙСТВИЕ ЕСТЬ У КАЖДОГО СОВЕТА, А ПОДПИСЬ - ТОЛЬКО ТАМ, ГДЕ ЕСТЬ КНОПКА.
    --
    -- Раньше здесь требовалась подпись у любого действия, и информационные
    -- советы (noop) носили подпись «Понятно». Но кнопки у них нет: список её
    -- прячет, панель рисует вместо неё «Открыть». Подпись без кнопки - это
    -- обещание кнопки, и именно из-за неё левый щелчок по такому совету
    -- считался «нажатием „Понятно“» и прятал его. Поэтому правило теперь в обе
    -- стороны: у действия с кнопкой подпись обязана быть, у действия без
    -- кнопки её быть не должно.
    --
    -- Действий без кнопки теперь ДВА, и второе появилось не по вкусу:
    -- «findRecipe» - это совет про рецепт, который игрок открывает сам. Кнопку
    -- «Показать рецепт» убрали потому, что открыть рецепт в окне профессий игра
    -- аддонам запрещает (Core/Api.lua): вызов блокируется, и игрок видит окно
    -- «Модификация "ForeverPilot" заблокирована…». Подпись у такого действия
    -- была бы обещанием кнопки, которой нет.
    if not card.action then
        fail("нет действия")
    elseif NO_BUTTON[card.action.kind] then
        if card.action.label then fail("подпись у действия, для которого нет кнопки") end
    elseif not card.action.label or card.action.label == "" then
        fail("у действия нет подписи")
    end
    if card.score ~= card.score then fail("score = nan") end
    if card.title:find("Предмет #") and card.kind ~= ns.KIND.SETUP then
        -- An unnamed item is allowed, but it has to be the honest fallback and
        -- not an empty string pretending to be a name.
        if not card.title:find("#%d+") then fail("имя-заглушка без ID") end
    end
    if card.benefit:find("nan") or card.why:find("nan") then fail("nan в тексте") end
    if card.why:find("nil") or card.need:find("nil") then fail("nil в тексте") end
end
H.eq(#bad, 0, "ни одной битой карточки" ..
    (#bad > 0 and (": " .. table.concat(bad, "; ", 1, math.min(5, #bad))) or ""))

H.suite("Реальные данные: список осмысленный, а не мусор")
local kinds = {}
for _, card in ipairs(cards) do kinds[card.kind] = (kinds[card.kind] or 0) + 1 end
local kindList = {}
for kind, n in pairs(kinds) do kindList[#kindList + 1] = (ns.KIND_LABEL[kind] or kind) .. "=" .. n end
table.sort(kindList)
print("     типы: " .. table.concat(kindList, ", "))
H.ok(ns.Util.count(kinds) >= 2, "в списке больше одного типа совета")

-- THE Forever scenario: this character knows recipes for gear far above their
-- level, and those must appear as "craft to sell", not vanish.
local profitCards = kinds[ns.KIND.CRAFT_PROFIT] or 0
H.ok(profitCards > 0, profitCards .. " советов «скрафтить на продажу»")

local topProfit
for _, card in ipairs(cards) do
    if card.kind == ns.KIND.CRAFT_PROFIT then topProfit = card; break end
end
if topProfit then
    H.ok(topProfit.benefitValue and topProfit.benefitValue > 0,
        "лучший совет на продажу приносит " .. ns.Util.money(topProfit.benefitValue))
    print("     лучший на продажу: " .. topProfit.title .. " -> " .. topProfit.benefit)
end

-- Spend sanity: with 2 gold in the wallet we must not be told to spend 50.
H.suite("Реальные данные: не советуем тратить больше, чем есть")
local afford = ns.ShoppingList:Affordability(snap)
print(string.format("     закупка %s, в кошельке %s",
    ns.Util.money(afford.total), ns.Util.money(afford.money)))
-- A purchase far beyond the wallet is allowed to EXIST - the player may want
-- to know what the materials cost - but it must say so plainly and it must not
-- sit above something they can do today. The old rule here was a flat cap on
-- the sum, which said nothing about either.
local outOfReach, ranked = 0, {}
for i, card in ipairs(cards) do ranked[card.key] = i end
for _, card in ipairs(cards) do
    if card.kind == ns.KIND.BUY and card.cost then
        local ratio = card.cost / math.max(afford.money, 1)
        if ratio > ns.ActionEngine.OUT_OF_REACH_RATIO then
            outOfReach = outOfReach + 1
            H.eq(card.outOfReach, true, string.format(
                "«%s» (%s при кошельке %s) помечена как недоступная",
                ns.Util.truncate(card.title, 40), ns.Util.money(card.cost),
                ns.Util.money(afford.money)))
            H.ok(tostring(card.need):find("в %d+ раз[^ ]* больше, чем у вас есть") ~= nil,
                "и в тексте названо, во сколько раз: "
                .. ns.Util.truncate(card.need, 110))
            -- Nothing the player can act on today may rank below it.
            local myRank = ranked[card.key]
            local affordableBelow, examples = 0, {}
            for j = myRank + 1, #cards do
                local other = cards[j]
                -- Loss-making advice (tier 0) is deliberately below
                -- everything, so it does not count: the claim is only that
                -- nothing WORTH DOING sits under an unreachable purchase.
                local actionable = not other.outOfReach
                    and not other.informational
                    and other.kind ~= ns.KIND.SETUP
                    and (other.score or 0) >= 0
                    and not other.losesMoney
                if actionable then
                    affordableBelow = affordableBelow + 1
                    if #examples < 3 then
                        examples[#examples + 1] = ns.Util.truncate(other.title, 30)
                    end
                end
            end
            H.eq(affordableBelow, 0, string.format(
                "выполнимых советов ниже неё нет (%d%s)", affordableBelow,
                (#examples > 0) and (": " .. table.concat(examples, ", ")) or ""))
        end
    end
end
print("     покупок вне кошелька: " .. outOfReach)

-- Print the top of each profile so a human can read the advice.
H.suite("Реальные данные: верх списка по каждому профилю")
for _, profile in ipairs(ns.PROFILE_ORDER) do
    local list = run(profile)
    print("")
    print("   --- " .. ns.PROFILE_LABEL[profile] .. " (" .. #list .. " карточек)")
    for i = 1, math.min(6, #list) do
        local card = list[i]
        print(string.format("   %d. [%s] %s   | %s", i,
            ns.KIND_LABEL[card.kind] or card.kind,
            ns.Util.truncate(card.title, 58), card.benefit))
        print("        почему: " .. ns.Util.truncate(card.why, 100))
        print("        нужно:  " .. ns.Util.truncate(card.need, 100)
            .. "   [" .. (ns.CONF_LABEL[card.conf] or "?") .. "]")
    end
    H.ok(#list > 0, ns.PROFILE_LABEL[profile] .. ": список не пуст")
end

-- ЛАГЕРЬ У КОСТРА НА НАСТОЯЩИХ ДАННЫХ -----------------------------------
--
-- Ветка лагеря держится на четырёх источниках разом, и каждый из них в
-- фикстурах подменён: профессии ОБОИХ персонажей, книга рецептов, цены и имена
-- предметов. Проверять её только на выдуманных мирах значит не проверять
-- главное - что на диске у игрока всё это и правда сходится.
--
-- Числа здесь настоящие: у мага рыбалка 225 и выученный аквариум, костёр
-- подмастерья не выучен и его чертёж торгуется, а алхимия с инженерным делом
-- лежат на чернокнижнике.
H.suite("Реальные данные: лагерь у костра")
do
    local list = run("POWER")
    local camp = {}
    for _, card in ipairs(list) do
        if card.kind == ns.KIND.CAMP then camp[#camp + 1] = card end
    end
    H.ok(#camp >= 3, "карточек лагеря на настоящих данных: " .. #camp)
    for _, card in ipairs(camp) do
        print("     " .. ns.Util.truncate(card.title, 52) .. "  | " .. tostring(card.benefit))
    end

    local plan = ns.CampAdvisor:Plan(ns.CharacterScanner:Get())
    H.ok(plan ~= nil, "план лагеря построен")
    if plan then
        -- 7 ИЗ 12 - И ЭТО СЧЁТ ПО ДВУМ ПЕРСОНАЖАМ. У мага пять профессий
        -- лагеря, у чернокнижника ещё две своих; без второго персонажа ответ
        -- был бы «5 из 12» и был бы неверен.
        H.eq(plan.total, 12, "предметов первого тира всего 12")
        H.eq(plan.covered, 7,
            "профессии аккаунта закрывают 7 из 12: " .. plan.covered)
        H.eq(#plan.uncovered, 5, "и пять профессий не взял никто: "
            .. table.concat(plan.uncovered, ", "))
        H.eq(plan.disputed, 2, "спорных порогов в данных: " .. plan.disputed)
        H.eq(plan.unread, 0, "и рецепты всех нужных профессий прочитаны")
    end

    -- Самый высокий совет лагеря - аквариум: единственный предмет первого тира,
    -- у которого в данных есть ЧИСЛО (+8% ко всем характеристикам).
    local best
    for _, card in ipairs(camp) do
        if (not best) or (card.score or 0) > (best.score or 0) then best = card end
    end
    H.ok(best ~= nil, "верхний совет лагеря есть")
    if best then
        H.eq(best.itemID, 279967, "и это аквариум (279967)")
        H.ok(ns.Util.contains(best.benefit, "8%"), "с числом из данных: "
            .. tostring(best.benefit))
        H.ok(ns.Util.contains(best.why, "7 из 12"),
            "и со счётом по аккаунту: " .. ns.Util.truncate(best.why, 120))
        H.ok(ns.Util.contains(best.need, "игра мне не говорит"),
            "и с оговоркой про то, чего игра не сообщает: " .. best.need)
    end

    -- ЧЕРТЁЖ НАЗВАН ПО-ИМЕНИ. Чертежей лагеря нет ни в кеше рецептов игрока, ни
    -- в пакете предметов Codex - они лежат в его группе «recipe», и без неё
    -- карточка «купить чертёж» не рождалась вовсе (имени нет - карточки нет).
    local bp
    for _, card in ipairs(camp) do
        if tostring(card.key):find("^camp:blueprint:") then bp = card end
    end
    H.ok(bp ~= nil, "карточка «купить чертёж» на настоящих данных есть")
    if bp then
        H.ok(not ns.Util.contains(bp.title, "Предмет #"),
            "и предмет в ней назван, а не пронумерован: " .. bp.title)
        -- ЦЕНА ЛИБО ПОСЧИТАНА, ЛИБО НАЗВАНА НЕИЗВЕСТНОЙ. В этом стенде цены
        -- берутся из книги закупок игрока и из сканов аукциона, а по чертежу у
        -- него ни того, ни другого - и тогда единственный честный ответ
        -- «цену я не знаю». Чего быть не может - это числа из воздуха.
        if (tonumber(bp.cost) or 0) > 0 then
            H.ok(ns.Util.contains(bp.why, "аукционе"),
                "цена покупки посчитана и названа: " .. ns.Util.money(bp.cost))
        else
            H.ok(ns.Util.contains(bp.why, "не знаю"),
                "цены чертежа тут нет, и так и сказано: "
                .. ns.Util.truncate(bp.why, 150))
        end
    end

    -- ВТОРОЙ ПЕРСОНАЖ. Профессии чернокнижника аддон знает из того, что видел
    -- сам (реестр) или из чужого кеша; без этого совет «это сделает другой»
    -- не появился бы.
    local other
    for _, card in ipairs(camp) do
        if tostring(card.key):find("^camp:other:") then other = card end
    end
    H.ok(other ~= nil, "и совет про второго персонажа тоже")
    if other then
        H.ok(ns.Util.contains(other.title, "Белыйй"),
            "в нём назван персонаж с фамилией: " .. other.title)
    end

    -- ЦЕНА РАБОТЫ - ВЫЗОВАМИ, НА НАСТОЯЩИХ ДАННЫХ.
    local realBuy = ns.PriceProvider.Buy
    local calls = 0
    ns.PriceProvider.Buy = function(self, ...)
        calls = calls + 1
        return realBuy(self, ...)
    end
    ns.PriceProvider:BeginPass()
    ns.CampAdvisor:Plan(ns.CharacterScanner:Get())
    ns.PriceProvider.Buy = realBuy
    print("     вопросов о цене за пересчёт: " .. calls)
    H.ok(calls <= 40, "лагерь спрашивает цену " .. calls
        .. " раз за пересчёт (предел 40 при 38 объектах)")
end

-- Degradation on real data ----------------------------------------------

H.suite("Реальные данные: без Auctionator")
do
    env.auctionator = false
    env.prices = {}
    env.observedPrices = nil     -- no foreign observations either
    local list, m = run("POWER")
    print("     карточек без цен: " .. #list)
    H.ok(#list > 0, "список не пустеет без цен")
    H.eq(m.priceSources.auctionatorAvailable, false, "отсутствие аукциона отмечено")
    local warned = false
    for _, card in ipairs(list) do
        if card.key == "setup:auctionator" then warned = true end
    end
    H.ok(warned, "игрок предупреждён")
    -- Nothing may claim a gold figure it cannot support.
    for _, card in ipairs(list) do
        if card.kind == ns.KIND.CRAFT_PROFIT then
            H.ok(card.conf ~= ns.CONF.EXACT,
                "прибыль без цен не выдаётся за точную: " .. card.title)
        end
    end
    -- Restore for the next block.
    env.auctionator = true
    env.prices = observed
    env.observedPrices = observed
end

H.suite("Реальные данные: без данных банка")
do
    local savedBank = env.bank
    env.bank = nil
    local list = run("THRIFT")
    H.ok(#list > 0, "список строится без банка (" .. #list .. ")")
    local warned = false
    for _, card in ipairs(list) do
        if card.key == "setup:bank" then warned = true end
    end
    H.ok(warned, "карточка про банк показана")
    env.bank = savedBank
end

H.suite("Реальные данные: окно профессии ни разу не открывали")
do
    -- Wipe the recipe book entirely: this is the state at a fresh login before
    -- the player opens anything, and the one the engine must explain.
    local saved = ns.RecipeBook.byProfession
    ns.RecipeBook.byProfession = {}
    ns.RecipeBook:Reindex()
    local list = run("POWER")
    H.ok(#list > 0, "список не пуст (" .. #list .. ")")
    H.eq(list[1].kind, ns.KIND.SETUP, "первая карточка объясняет, что делать")
    local profsAsked = 0
    for _, card in ipairs(list) do
        if card.action and card.action.kind == "openProfession" then
            profsAsked = profsAsked + 1
            print("     просим открыть: " .. card.action.profession)
        end
    end
    H.ok(profsAsked > 0, profsAsked .. " карточек «откройте окно профессии»")
    ns.RecipeBook.byProfession = saved
    ns.RecipeBook:Reindex()
end

H.suite("Реальные данные: планы по настоящим рецептам")
do
    run("POWER")
    local checked, ready, withCost, failed, deepest = 0, 0, 0, 0, 0
    for _, recipe in ipairs(ns.RecipeBook:Iterate(function(r)
        return r.learned and r.output and #r.reagents > 0
    end)) do
        checked = checked + 1
        local ok, plan = pcall(function() return ns.CraftingPlanner:Plan(recipe, 1) end)
        if not (ok and plan) then
            failed = failed + 1
            if failed <= 3 then
                print("     !! план не построился: " .. tostring(recipe.name)
                    .. " (" .. tostring(plan) .. ")")
            end
        else
            if plan.ready then ready = ready + 1 end
            if plan.cost then withCost = withCost + 1 end
            if #plan.crafts > deepest then deepest = #plan.crafts end
        end
    end
    print(string.format("     %d рецептов: %d выполнимы сразу, %d с посчитанной ценой,"
        .. " самая длинная цепочка %d шагов",
        checked, ready, withCost, deepest))
    H.ok(checked > 100, checked .. " планов построено по реальным рецептам")
    H.eq(failed, 0, "ни один план не упал и не вернул nil")
    H.ok(withCost > 0, withCost .. " планов с посчитанной стоимостью")

    -- "At least one recipe is craftable right now" is a fact about what is in
    -- the player's bags today, not about the code: they spend materials between
    -- runs, and on the run that found this the wallet had gone from 22 gold to
    -- one. So the invariant is the implication, which IS about the code: if the
    -- bags do hold every reagent of some recipe, a plan must say so.
    local shouldBeReady, example = 0, nil
    for _, recipe in ipairs(ns.RecipeBook:Iterate(function(r)
        return r.learned and r.output and #r.reagents > 0
    end)) do
        local all = true
        for _, g in ipairs(ns.RecipeBook:MergedReagents(recipe)) do
            if (env.bags[g.itemID] or 0) < g.qty then all = false; break end
        end
        -- A recipe on cooldown is not craftable now however full the bags are.
        if all and not ns.CraftingPlanner:OnCooldown(recipe) then
            shouldBeReady = shouldBeReady + 1
            example = example or recipe
        end
    end
    print(string.format("     по содержимому сумок выполнимых должно быть %d%s",
        shouldBeReady, example and (" (например «" .. tostring(example.name) .. "»)") or ""))
    if shouldBeReady > 0 then
        H.ok(ready > 0, "раз в сумках есть всё для " .. shouldBeReady
            .. " рецептов, хотя бы один план обязан быть готов")
    else
        H.eq(ready, 0, "в сумках нет полного набора ни для одного рецепта —"
            .. " и ни один план не объявлен готовым, что согласуется")
    end
end

-- REWRITTEN. This suite used to assert `#ups == 0`: it checked that the gear
-- branch produced NOTHING on real data, and called that the desired behaviour.
-- At the time it was true for the wrong reason - the client's SavedVariables
-- hold no item stats, so there was nothing to compare - but it meant the suite
-- pinned the branch shut. The whole gear fix could have been reverted and this
-- test would still have passed.
--
-- The branch now reads equip bonuses from the item database, so it works on
-- real data. What is asserted is the thing that actually matters: whatever it
-- produces must be defensible. Nothing claims a gain it cannot show, nothing
-- recommends an item that lowers the profile's own stat, and every number on a
-- card can be re-derived from the stats.
H.suite("Реальные данные: ветка экипировки отвечает за каждое число")
do
    run("POWER")
    local snap2 = ns.CharacterScanner:Get()
    local ups = ns.GearAdvisor:Upgrades(snap2, ns.CraftingPlanner)
    print("     профиль весов: " .. tostring(snap2.weightSetKey)
        .. " (источник: " .. tostring(snap2.weightSource) .. ")")
    print("     улучшений предложено: " .. #ups)

    local itemDB = ns.Api:ItemDBPresent()
    if not itemDB then
        -- No item database offline: the client half alone cannot see equip
        -- bonuses, so an honest branch says "cannot compare" rather than
        -- inventing a gain. That is a real assertion, not an empty one.
        for _, up in ipairs(ups) do
            H.ok(up.compare ~= "exact", string.format(
                "«%s»: без базы предметов прирост не выдаётся за измеренный",
                tostring(up.info.name)))
            H.eq(up.gain, nil, "и числом не называется")
        end
        H.ok(true, "базы предметов нет — ветка честно воздерживается от чисел")
    else
        H.ok(#ups > 0, "база предметов есть, ветка работает: " .. #ups
            .. " улучшений")
    end

    -- These hold either way, and they are the ones that cost the player
    -- materials when they did not.
    for _, up in ipairs(ups) do
        local name = tostring(up.info and up.info.name)
        if up.compare == "exact" then
            H.ok(up.gain and up.gain > 0, string.format(
                "«%s»: заявлен настоящий прирост (%.2f)", name, up.gain or 0))
            -- Re-derive it from the stats: the card's number must be the
            -- difference of two scores we can compute ourselves.
            local newScore = ns.StatWeights:Score(
                ns.GearAdvisor:ItemStats(up.info.link or up.info.itemID) or {},
                snap2.weights)
            H.near(up.newScore, newScore, 0.01, string.format(
                "«%s»: оценка вещи воспроизводится из характеристик", name))
        end
        local cmp = up.compareDetail
        if cmp then
            H.ok(cmp.mainStatDrop ~= true, string.format(
                "«%s»: главная характеристика не просажена (%d → %d)",
                name, cmp.mainFrom or 0, cmp.mainTo or 0))
        end
    end

    local _, kitScore, kitConf = ns.GearAdvisor:Audit(snap2)
    print("     оценка кита: " .. tostring(U and "" or "")
        .. string.format("%.1f", kitScore or 0)
        .. " (" .. tostring(ns.CONF_LABEL[kitConf] or kitConf) .. ")")

    -- The unwearable list, which feeds the profit branch, does NOT depend on
    -- stats - only on equip slots - so it has to work regardless.
    local unwearable = ns.GearAdvisor:Unwearable(snap2)
    print("     ненадеваемых крафтов распознано: " .. #unwearable)
    H.ok(true, "ветка продажи от характеристик не зависит")
end

-- ИНСТРУМЕНТ В СЛОТЕ, ОРУЖИЕ В СУМКЕ. Живая находка: игрок надел удочку, чтобы
-- порыбачить, и аддон принялся советовать ему оружие - при том что Мерцающий
-- посох лежал у него в сумке. Проверяется на настоящем файле инвентаря, а не на
-- выдуманном: что надето и что в сумках, берётся из Syndicator.
H.suite("Реальные данные: удочка в руке — не повод советовать оружие")
do
    run("POWER")
    local snap3 = ns.CharacterScanner:Get()
    local Gear = ns.GearAdvisor

    -- Что на самом деле лежит в слотах оружия у этого персонажа.
    local mh = snap3.equipped and snap3.equipped.MAINHAND
    local rg = snap3.equipped and snap3.equipped.RANGED
    print("     правая рука: " .. (mh and (tostring(mh.itemID) .. " "
        .. tostring(env.items[mh.itemID] and env.items[mh.itemID].name)) or "пусто"))
    print("     дальний бой: " .. (rg and (tostring(rg.itemID) .. " "
        .. tostring(env.items[rg.itemID] and env.items[rg.itemID].name)) or "пусто"))

    -- Инструменты опознаются по типу. Номера класса и подкласса берутся из
    -- клиента, а офлайн - из установленной базы предметов, поэтому проверка
    -- работает и здесь.
    local toolInSlot = mh and Gear:IsProfessionTool(mh.link or mh.itemID) or false
    if ns.Api:ItemDBPresent() then
        -- УДОЧКА И ОРУЖИЕ ИЩУТСЯ В БАЗЕ ПО ТИПУ, А НЕ ПО НОМЕРАМ 6367 И 13062.
        --
        -- Номера были подобраны по установленной базе. Когда набор шёл по
        -- фикстуре (папка аддона без соседних), удочки 6367 в ней не было,
        -- проверка падала, и по ней был сделан неверный вывод, будто предмета
        -- нет в установленной базе. Тип же - «оружие, подкласс 20» для удочки -
        -- это то, что о предмете говорит сама игра, и по нему предмет находится
        -- в любой базе, где он есть.
        local WEAPON, FISHING_POLE, MISC = 2, 20, 14
        local toolID = H.findItemInDB(function(rec)
            return rec.class == WEAPON and rec.subclass == FISHING_POLE
        end)
        local weaponID = H.findItemInDB(function(rec)
            return rec.class == WEAPON and rec.subclass ~= FISHING_POLE
                and rec.subclass ~= MISC
        end)
        if toolID then
            H.eq(Gear:IsProfessionTool(toolID), true, toolID .. " «"
                .. tostring(H.itemDBName(toolID) or "удочка")
                .. "» — инструмент (найден в базе по типу: оружие, подкласс 20)")
        else
            H.note("в базе, с которой идут тесты, нет ни одной удочки — «инструмент"
                .. " профессии» проверен по явно заданному типу, а не на предмете из базы")
            H.eq(Gear:IsProfessionTool({ itemID = 999100, classID = WEAPON,
                    subclassID = FISHING_POLE }), true,
                "предмет с типом удочки (оружие, подкласс 20) — инструмент")
        end
        H.ok(weaponID ~= nil, "в базе нашлось обычное оружие для сравнения")
        if weaponID then
            H.eq(Gear:IsProfessionTool(weaponID), false, weaponID .. " «"
                .. tostring(H.itemDBName(weaponID) or "оружие")
                .. "» — оружие, а не инструмент")
        end
        -- И то, что у игрока в руках на самом деле. Номера берутся из снимка
        -- персонажа, тип - из строки базы: что там лежит сегодня, то и
        -- проверяется. Посох или жезл инструментом считаться не должны.
        local checkedWorn = 0
        for _, worn in ipairs({ mh, rg }) do
            local rec = worn and H.itemDBRecord(worn.itemID)
            if rec and rec.class == WEAPON then
                checkedWorn = checkedWorn + 1
                local isTool = (rec.subclass == FISHING_POLE or rec.subclass == MISC)
                local name = env.items[worn.itemID] and env.items[worn.itemID].name
                H.eq(Gear:IsProfessionTool(worn.link or worn.itemID), isTool,
                    worn.itemID .. " «" .. tostring(name or "?") .. "» в руках игрока — "
                    .. (isTool and "инструмент" or "оружие, а не инструмент")
                    .. " (подкласс " .. tostring(rec.subclass) .. " по базе)")
            end
        end
        if checkedWorn == 0 then
            H.note("предметов из рук игрока в базе, с которой идут тесты, нет —"
                .. " их тип на этом прогоне не сверялся")
        end
    end

    -- Посох в сумке: ровно тот случай, из-за которого правка и появилась.
    local staffOwned = (snap3.bags and snap3.bags[249392] or 0) > 0
    print("     Мерцающий посох в сумках: " .. tostring(staffOwned)
        .. ", инструмент в правой руке: " .. tostring(toolInSlot))

    if toolInSlot and staffOwned and ns.Api:ItemDBPresent() then
        local base = Gear:SlotBaseline("MAINHAND", snap3, snap3.weights)
        H.eq(base.toolEquipped, true, "видно, что в слоте инструмент")
        H.eq(base.itemID, 249392, "за основу взят посох из сумки")
        H.ok((base.score or 0) > 0, string.format(
            "слот не считается пустым: %.1f %s", base.score or 0, ns.UNIT_BENEFIT))

        -- И в списке появляется самый дешёвый совет из возможных.
        local equipCard
        for _, card in ipairs(cards) do
            if card.kind == ns.KIND.EQUIP and card.itemID == 249392 then equipCard = card end
        end
        H.ok(equipCard ~= nil, "в списке есть «надеть посох»")
        if equipCard then
            print("     " .. equipCard.title .. " | " .. equipCard.benefit)
            print("     " .. equipCard.why)
            H.eq(equipCard.cost or 0, 0, "совет ничего не стоит")
        end

        -- И никакой крафт или покупка оружия не выдаётся за улучшение слота,
        -- который на самом деле занят вещью лучше.
        for _, card in ipairs(cards) do
            if card.kind == ns.KIND.CRAFT_GEAR and card.itemID then
                local slot = ns.SlotMap:FromEquipLoc(
                    (env.items[card.itemID] or {}).equipLoc)
                if slot == "MAINHAND" or slot == "TWOHAND" then
                    local score = Gear:ItemScore(card.itemID, snap3.weights) or 0
                    H.ok(score > (base.score or 0), string.format(
                        "«%s» предлагается только если лучше посоха (%.1f против %.1f)",
                        tostring(card.title), score, base.score or 0))
                end
            end
        end
    else
        -- Состояние игры изменилось (посох надет обратно или удочка снята) -
        -- это нормально, но тогда проверять нечего, и молчать об этом нельзя.
        H.ok(true, "в этом снимке инструмента с запасным оружием нет — "
            .. "сценарий не воспроизводится, проверка пропущена")
    end
end

-- ЧАРЫ НА УДОЧКУ, НА ЖИВЫХ ДАННЫХ.
--
-- 13:13: «Чары для двуручного оружия — Слот «Правая рука» без чар (Большая
-- железная удочка)» и «Чары: 5/7». Посох 249392 с чарой 8217 лежал в сумке.
H.suite("Реальные данные: чары не предлагаются на инструмент")
do
    run("POWER")
    local snap4 = ns.CharacterScanner:Get()
    local Gear, Ench = ns.GearAdvisor, ns.EnchantAdvisor
    local st = Ench:SlotStatus(snap4)
    print(string.format("     чары: %d из %d, голых %d, неизвестно %d",
        st.enchanted, st.enchantable, st.bare, st.unknown or 0))

    local mh = snap4.equipped and snap4.equipped.MAINHAND
    local toolInSlot = mh and Gear:IsProfessionTool(mh.link or mh.itemID) or false
    local staffOwned = (snap4.bags and snap4.bags[249392] or 0) > 0

    -- Никаких советов по чарам на слот, где лежит инструмент, если боевого
    -- предмета для него нет; а если есть - совет про НЕГО и с указанием места.
    for _, s in ipairs(Ench:Suggestions(snap4, ns.CraftingPlanner)) do
        if s.slot == "MAINHAND" then
            H.ok(not Gear:IsProfessionTool(s.itemID), string.format(
                "совет по правой руке не про инструмент: %s", tostring(s.equippedName)))
            if s.inBag then
                H.ok(s.where == "bags" or s.where == "bank",
                    "и сказано, где он лежит: " .. tostring(s.where))
            end
        end
    end

    if toolInSlot and staffOwned then
        local item = Gear:SlotItem("MAINHAND", snap4, snap4.weights)
        H.eq(item.itemID, 249392, "предмет оружейного слота — посох из сумки")
        H.eq(item.enchantID, 8217, "и его чара прочитана из ссылки")
        local bare = false
        for _, b in ipairs(Ench:BareSlots(snap4)) do
            if b.slot == "MAINHAND" then bare = true end
        end
        H.eq(bare, false, "оружейный слот не числится голым")
    else
        H.ok(true, "сценарий не воспроизводится в этом снимке — проверка пропущена")
    end
end

-- ЧАРЫ ЗАЧАРОВАТЕЛЮ, НА ЖИВЫХ ДАННЫХ.
--
-- Дословная жалоба: «мой аддон не показывает нормально, какие чары… Он должен
-- был проанализировать, какие лучше мне чары поставить, особенно тем более, что
-- у меня маг — зачарователь». На его снимке было 65 выученных формул, 6 из 7
-- зачаровываемых слотов уже зачарованы, и ветка выдавала ОДНУ информационную
-- карточку «Чары: 6/7, без чар: Шея» - то есть сводку вместо советов, а 60
-- подходящих формул отсеивались на `if not item.enchantID` без единого числа в
-- диагностике.
H.suite("Реальные данные: зачарователю есть что посоветовать по каждому слоту")
do
    local cards5 = run("POWER")
    local snap5 = ns.CharacterScanner:Get()
    local Ench = ns.EnchantAdvisor
    local learned = #Ench:LearnedFormulas()
    local items = Ench:SlotItems(snap5)
    local slotCount = 0
    for _ in pairs(items) do slotCount = slotCount + 1 end
    print(string.format("     формул выучено %d, зачаровываемых слотов с вещью %d",
        learned, slotCount))

    -- Договор ветки проверяется отдельным утверждением, чтобы откат правки
    -- давал КРАСНУЮ проверку, а не падение набора на несуществующем методе.
    local hasSlotAdvice = type(Ench.Advise) == "function"
        and type(Ench.Replacements) == "function"
        and type(Ench.Worn) == "function"
    H.ok(hasSlotAdvice, "ветка чар разбирает все слоты, а не только пустые")
    if learned == 0 or slotCount == 0 then
        H.ok(true, "персонаж не зачарователь или слотов нет — проверка пропущена")
    elseif not hasSlotAdvice then
        H.ok(false, string.format(
            "у зачарователя с %d формулами и %d слотами советовать нечем —"
            .. " ветка смотрит только на слоты без чар", learned, slotCount))
    else
        local advice = Ench:Advise(snap5, ns.CraftingPlanner)
        -- НИ ОДИН СЛОТ НЕ ИСЧЕЗАЕТ МОЛЧА: про каждый сказано либо «вот совет»,
        -- либо названная причина, почему совета нет.
        H.eq(#advice.slots, slotCount, "разобран каждый слот с вещью")
        for _, slotNote in ipairs(advice.slots) do
            H.ok(slotNote.advised ~= nil or slotNote.dropped ~= nil, string.format(
                "слот «%s»: %s", tostring(slotNote.label),
                tostring(slotNote.advised or slotNote.dropped)))
        end

        local advised = #advice.bare + #advice.replace
        print(string.format("     советов: %d по пустым слотам, %d по занятым",
            #advice.bare, #advice.replace))
        -- Формулы, подходящие к надетому, есть - значит и совет обязан быть
        -- хотя бы один: «ни одна не подходит» было неправдой.
        local fitting = 0
        for _, slotNote in ipairs(advice.slots) do
            fitting = fitting + (slotNote.formulas or 0)
        end
        print("     формул, подходящих к надетым вещам: " .. fitting)
        if fitting > 0 then
            H.ok(advised > 0, string.format(
                "к вещам подходит %d формул — совет есть (%d)", fitting, advised))
        else
            H.ok(true, "ни одна формула к надетому не подходит — советов и не ждём")
        end

        -- ПОРЯДОК ВНУТРИ СЛОТА: выбранная формула не слабее любой другой на
        -- тот же слот. Именно это и ломалось: выигрывала самая дешёвая.
        for _, e in ipairs(advice.bare) do
            for _, alt in ipairs(e.altList or {}) do
                H.ok((e.usefulness or -1) >= (alt.usefulness or -1)
                     or (alt.usefulness or 0) <= 0, string.format(
                    "на «%s» выбрана не менее полезная формула, чем «%s»",
                    tostring(e.label), tostring(alt.recipe.name)))
            end
        end
        for _, e in ipairs(advice.replace) do
            H.ok((e.usefulness or 0) > 0, string.format(
                "на занятый слот «%s» предложено то, что персонаж ценит: %s",
                tostring(e.label), tostring(e.statText)))
            H.eq(e.conf, ns.CONF.UNKNOWN,
                "и достоверность такого совета — «неизвестно»")
        end

        -- ЧТО УЖЕ СТОИТ. Вторая половина жалобы: «какие чанты у меня есть».
        local st = Ench:SlotStatus(snap5)
        local worn = Ench:Worn(snap5)
        H.eq(#worn, st.enchanted, string.format(
            "перечислено всё, что уже наложено: %d из %d слотов",
            #worn, st.enchantable))
        for _, w in ipairs(worn) do
            print(string.format("     уже стоит: %-14s %-34s #%s",
                w.label, ns.Util.truncate(tostring(w.itemName), 32),
                tostring(w.enchantID)))
            H.ok(w.enchantID ~= nil, "номер чары прочитан для «" .. w.label .. "»")
        end

        -- Каждая карточка чар - с числами и с названным предметом.
        local enchCards = 0
        for _, c in ipairs(cards5) do
            if c.kind == ns.KIND.ENCHANT and c.recipeID then
                enchCards = enchCards + 1
                H.ok(c.benefit and c.benefit ~= "", string.format(
                    "«%s»: выгода названа (%s)", tostring(c.title), tostring(c.benefit)))
                -- ОН САМ ЗАЧАРОВАТЕЛЬ: в строке «нужно» должны стоять
                -- реагенты, а не покупка свитка.
                local need = ns.Util.lower(tostring(c.need or ""))
                H.ok(need:find("реагент") ~= nil,
                    "и сказано про реагенты, а не про свиток: " ..
                    ns.Util.truncate(tostring(c.need), 70))
            end
        end
        print("     карточек-советов по чарам на экране: " .. enchCards)

        -- ЦЕНА ВЕТКИ - В ВЫЗОВАХ, А НЕ В МИЛЛИСЕКУНДАХ. Полный план по каждой
        -- формуле стоил 60 вызовов планировщика за пересчёт при 95 на весь
        -- остальной аддон; план нужен только там, где цена ещё что-то решает.
        do
            local planner = ns.CraftingPlanner
            local realPlan = planner.Plan
            local plans = 0
            planner.Plan = function(self, ...)
                plans = plans + 1
                return realPlan(self, ...)
            end
            local ok, err = pcall(function()
                Ench:Advise(snap5, planner)
            end)
            planner.Plan = realPlan
            H.ok(ok, "разбор чар не упал: " .. tostring(err))
            print(string.format("     планов построено %d на %d формул-кандидатов",
                plans, fitting))
            H.ok(plans <= fitting, string.format(
                "планов не больше, чем кандидатов: %d против %d", plans, fitting))
            if fitting >= 20 then
                H.ok(plans * 2 <= fitting, string.format(
                    "и заведомо меньше половины: %d против %d", plans, fitting))
            end
        end

        -- И ВОРОНКА. Без неё пропажу шестидесяти формул не показывало ни одно
        -- число в файле диагностики.
        local f = ns.Diag:Init().funnels["enchants"]
        H.ok(f ~= nil, "у ветки чар есть воронка потерь")
        if f then
            print(string.format("     воронка чар: вошло %d → вышло %d (отсеяно %d)",
                f["in"] or 0, f.out or 0, f.dropped or 0))
            H.eq(f.unaccounted, 0, "и ни один кандидат не потерялся без объяснения")
        end
    end
end

-- СКОЛЬКО РАЗ ЗА ПЕРЕСЧЁТ МЫ ДЁРГАЕМ КЛИЕНТА.
--
-- Мерить миллисекунды на фейках бессмысленно: фальшивый GetItemInfo - это
-- обращение к таблице, а настоящий стоит на три порядка дороже. В живом файле
-- игрока (216 пересчётов) видно настоящую цену: C_Item.GetItemInfo 50760
-- вызовов (235 за пересчёт), Auctionator 73008 (338 за пересчёт), и 35 мс
-- средний пересчёт. Поэтому контракт здесь - ЧИСЛО ВЫЗОВОВ за пересчёт, а не
-- время: оно переносится из теста в игру один в один.
H.suite("Реальные данные: вызовов клиента за пересчёт")
do
    run("POWER")                      -- первый пересчёт: кеши прогреты

    -- ПЕРЕСЧЁТ - ЭТО ТО, ЧТО ДЕЛАЕТ MAIN, а не только ActionEngine:Build.
    -- В игре каждый пересчёт заново собирает книгу рецептов, и именно это
    -- когда-то сбрасывало кеш данных предметов двести раз за сессию. Если
    -- мерить один Build, та ошибка снова станет невидимой.
    -- Берём ровно то звено, которое сбрасывало кеши: пересборка книги
    -- заканчивается Reindex, и именно он звал инвалидацию. Полный
    -- RecipeBook:Build здесь нельзя - он заменит книгу, собранную этим набором
    -- из кеша игрока, и следующие проверки останутся без рецептов.
    local function fullRebuild()
        ns.CharacterScanner:Scan()
        ns.RecipeBook:Reindex()
        ns.ActionEngine:Build()
    end

    local function callCount(name)
        local e = ns.Diag:Init().calls[name]
        return e and e.tries or 0
    end
    local WATCH = {
        "C_Item.GetItemInfo",
        "Auctionator.API.v1.GetAuctionPriceByItemID",
        "C_TooltipInfo.GetItemByID (разбор статов)",
        "MastercraftDB.costs (наблюдённая цена)",
        -- ХАРАКТЕРИСТИКИ ПРЕДМЕТА - ТОЖЕ ВЫЗОВ КЛИЕНТА, и его здесь не было.
        --
        -- Из-за этого мутация «данные предмета читаются заново каждый
        -- пересчёт» (Tests/mutate.py, M10) проходила незамеченной: она ломает
        -- кеш в GearAdvisor, а расход уходил в C_Item.GetItemStats, которого в
        -- этом списке не было. Остальные счётчики её не видят - ниже лежит
        -- отдельный кеш внешней базы, и он поглощает повторы.
        "C_Item.GetItemStats",
    }
    -- Холодный пересчёт: кеши пусты, и он честно дороже. Печатаем для картины,
    -- но контракт - на установившемся состоянии, потому что именно оно
    -- повторяется двести раз за сессию.
    ns.GearAdvisor:InvalidateItemData("замер: холодный старт")
    ns.Api:ClearAuctionCache("замер: холодный старт")
    local coldBefore = {}
    for _, name in ipairs(WATCH) do coldBefore[name] = callCount(name) end
    fullRebuild()
    for _, name in ipairs(WATCH) do
        print(string.format("     холодный: %-36s %7d",
            name, callCount(name) - coldBefore[name]))
    end

    local before = {}
    for _, name in ipairs(WATCH) do before[name] = callCount(name) end
    local clearedBefore = (ns.Diag:Init().counters or {})["itemInfo.cacheCleared"] or 0

    -- Счётчик обращений к внешней базе обнуляется на каждом проходе (Api:
    -- BeginPass), поэтому его надо складывать после каждого пересчёта, а не
    -- вычитать из снимка - иначе получается отрицательное число.
    local PASSES, dbTotal = 3, 0
    for _ = 1, PASSES do
        fullRebuild()
        dbTotal = dbTotal + (ns.Api.itemDBReads or 0)
    end
    local cleared = ((ns.Diag:Init().counters or {})["itemInfo.cacheCleared"] or 0)
        - clearedBefore
    H.eq(cleared, 0, "кеш предметов за три пересчёта не сбрасывался ни разу")

    local per = {}
    for _, name in ipairs(WATCH) do
        per[name] = (callCount(name) - before[name]) / PASSES
        print(string.format("     %-46s %7.1f за пересчёт", name, per[name]))
    end
    local dbPer = dbTotal / PASSES
    print(string.format("     %-46s %7.1f за пересчёт", "внешняя база предметов", dbPer))

    -- Потолки: живые числа были 235 и 338. Это не «красиво», это «в разы
    -- меньше, и если снова разрастётся - тест упадёт».
    H.ok(per["C_Item.GetItemInfo"] <= 20, string.format(
        "GetItemInfo за пересчёт не больше 20 (живое было 235): %.1f",
        per["C_Item.GetItemInfo"]))
    H.ok(per["Auctionator.API.v1.GetAuctionPriceByItemID"] <= 20, string.format(
        "Auctionator за пересчёт не больше 20 (живое было 338): %.1f",
        per["Auctionator.API.v1.GetAuctionPriceByItemID"]))
    H.ok(dbPer <= 20, string.format(
        "внешнюю базу спрашиваем не больше 20 раз (живое было 113): %.1f", dbPer))
    H.ok(per["C_TooltipInfo.GetItemByID (разбор статов)"] <= 20, string.format(
        "тултипы разбираем не больше 20 раз (живое было 7): %.1f",
        per["C_TooltipInfo.GetItemByID (разбор статов)"]))
    -- ХАРАКТЕРИСТИКИ ЧИТАЮТСЯ ОДИН РАЗ НА ПРЕДМЕТ, А НЕ НА ПЕРЕСЧЁТ.
    -- Холодный старт на этом персонаже стоит 221 чтение; в установившемся
    -- состоянии их должно быть почти ноль, потому что характеристики предмета
    -- не меняются, пока игрок играет. Двадцать - тот же потолок, что у
    -- остальных: «в разы меньше, и если снова разрастётся - тест упадёт».
    H.ok(per["C_Item.GetItemStats"] <= 20, string.format(
        "характеристики спрашиваем не больше 20 раз за пересчёт"
        .. " (холодный старт стоит 221): %.1f",
        per["C_Item.GetItemStats"]))
end

-- СКОЛЬКО РАЗ ЗА ПЕРЕСЧЁТ МЫ СПРАШИВАЕМ CODEX.
--
-- Это и оказалось главной ценой этапов 2 и 3. Живой прогон: средний пересчёт
-- 71.1 мс против 9 мс раньше, и 87 из них - ветка арбитража. Ветка осматривает
-- до 400 кандидатов и по каждому спрашивает Codex, а одно обращение к Codex в
-- игре - это двоичный поиск по блобу на 900 килобайт, разбор записи и
-- обращение к кешу предметов клиента. Записи в Codex кешируются СЛАБЫМИ
-- ссылками, то есть между пересчётами собираются сборщиком мусора и
-- разбираются заново.
--
-- Источники предмета и места NPC за сессию не меняются, поэтому спрашивать их
-- заново на каждом пересчёте незачем. Контракт - на числе обращений: оно
-- переносится из теста в игру один в один, а миллисекунды на разборе-в-таблицу
-- ничего не говорят.
H.suite("Реальные данные: обращений к Codex за пересчёт")
do
    run("POWER")
    local function rebuild()
        ns.CharacterScanner:Scan()
        ns.RecipeBook:Reindex()
        ns.ActionEngine:Build()
    end
    -- Холодный проход, и он тут обязателен: без сброса кеша «ноль обращений»
    -- ничего не доказывает - кеш мог быть прогрет предыдущими проверками этого
    -- же файла. Сброс заодно проверяет, что сбрасывать вообще умеем.
    local dropped = ns.Api:ClearCodexCache("замер: холодный старт")
    H.ok(dropped > 0, "кеш Codex был непустой и сброшен: " .. dropped
        .. " записей")
    env.codexCalls = 0
    rebuild()
    local cold = env.codexCalls or 0
    print(string.format("     холодный пересчёт: %d обращений к Codex", cold))
    H.ok(cold > 100, "на холодном проходе Codex спрашивается по-настоящему: "
        .. cold .. " обращений (именно столько стоил КАЖДЫЙ пересчёт до кеша)")

    local PASSES = 3
    env.codexCalls = 0
    for _ = 1, PASSES do rebuild() end
    local per = (env.codexCalls or 0) / PASSES
    print(string.format("     установившееся состояние: %.1f обращений за пересчёт", per))
    -- Тот же потолок, что у остальных обращений к клиенту: «в разы меньше, и
    -- если снова разрастётся - тест упадёт».
    H.ok(per <= 20, string.format(
        "Codex спрашиваем не больше 20 раз за пересчёт (без кеша это 400+): %.1f",
        per))
end

-- ЧТО СТОИТ ЧТЕНИЕ ХАРАКТЕРИСТИК ИЗ КЛИЕНТА НА НАСТОЯЩИХ ПРЕДМЕТАХ.
--
-- Стенд подменяет Api:ItemStatsRaw целиком, поэтому производственный читатель
-- (прямой вызов + добавка из тултипа для надеваемых вещей) на настоящих данных
-- не измерялся вовсе. Здесь он ставится на место - с клиентом, который отвечает
-- ровно как клиент игрока: базовые характеристики прямым вызовом, строки
-- тултипа только в args, TooltipUtil.SurfaceArgs нет. Считаются ОБРАЩЕНИЯ, а не
-- миллисекунды.
H.suite("Реальные данные: чтение характеристик из клиента и его цена")
do
    run("POWER")
    local fakeStats = ns.Api.ItemStatsRaw
    local G = env.G
    local savedItem, savedTooltip, savedUtil = G.C_Item, G.C_TooltipInfo, G.TooltipUtil

    local tooltipCalls, directCalls = 0, 0
    G.C_Item = G.C_Item or {}
    G.C_Item.GetItemStats = function(link)
        directCalls = directCalls + 1
        local id = ns.Util.itemIDFromLink(link)
        local raw = id and env.stats[id] or nil
        if not raw then return {} end
        local copy = {}
        for k, v in pairs(raw) do copy[k] = v end
        return copy
    end
    -- Тултип отвечает ровно так, как на этом билде: текст в args. Про предметы
    -- игрока он не знает ничего нового - клиент их бонусов не пишет, - и это
    -- тоже ответ: значит зависимость от внешней базы полная.
    G.C_TooltipInfo = { GetItemByID = function(itemID)
        tooltipCalls = tooltipCalls + 1
        local name = env.items[itemID] and env.items[itemID].name or ("Предмет " .. tostring(itemID))
        return { lines = { { args = { { field = "leftText", stringVal = name } } } } }
    end }
    G.TooltipUtil = nil
    ns.Api:Detect()
    ns.Api.ItemStatsRaw = env.real.ItemStatsRaw
    H.eq(ns.Api.has.itemStats, true, "прямое чтение статов на месте")
    H.eq(ns.Api.has.surfaceArgs, false, "SurfaceArgs нет — как у игрока")

    local function rebuild()
        ns.CharacterScanner:Scan()
        ns.RecipeBook:Reindex()
        ns.ActionEngine:Build()
    end

    ns.GearAdvisor:InvalidateItemData("замер: холодное чтение характеристик")
    tooltipCalls, directCalls = 0, 0
    rebuild()
    print(string.format("     холодный пересчёт: %d прямых чтений, %d тултипов",
        directCalls, tooltipCalls))
    H.ok(directCalls > 0, "прямой вызов на настоящих предметах работает: "
        .. directCalls .. " чтений")

    local PASSES = 3
    tooltipCalls, directCalls = 0, 0
    for _ = 1, PASSES do rebuild() end
    local perDirect, perTooltip = directCalls / PASSES, tooltipCalls / PASSES
    print(string.format("     установившееся состояние: %.1f прямых чтений,"
        .. " %.1f тултипов за пересчёт", perDirect, perTooltip))
    -- Тот же потолок, что у остальных обращений к клиенту: характеристики
    -- предмета не меняются, пока игрок играет.
    H.ok(perDirect <= 20, string.format(
        "характеристики спрашиваем не больше 20 раз за пересчёт: %.1f", perDirect))
    H.ok(perTooltip <= 20, string.format(
        "и тултипы - не больше 20 раз за пересчёт: %.1f", perTooltip))

    ns.Api.ItemStatsRaw = fakeStats
    G.C_Item, G.C_TooltipInfo, G.TooltipUtil = savedItem, savedTooltip, savedUtil
    ns.Api:Detect()
    ns.GearAdvisor:InvalidateItemData("замер окончен")
    run("POWER")
end

-- ПИК ПЕРЕСЧЁТА: 124.7 мс ПРОТИВ 33 СРЕДНИХ - ОТКУДА ОН БРАЛСЯ.
--
-- Живой файл игрока: 755 пересчётов, средний 33.2 мс, пик 124.7 мс, и в выборке
-- из двадцати два всплеска по 80-88 мс. Средний втрое ниже пика - значит пик
-- даёт редкий тяжёлый случай, и вот он: пересчёт, которому досталась ПУСТАЯ
-- память цен. Он честно дороже - 367 чтений у Auctionator вместо нуля, - и
-- встречался он не редко: память забывал КАЖДЫЙ сигнал аукциона, а их за вечер
-- 276 (окно аукциона открыли, закрыли, пришла пачка результатов поиска,
-- обновились свои лоты). В файле 108 забываний и 41 804 обращения к Auctionator.
--
-- Сканирование аукциона при этом одно. Поэтому между забываниями стоит минимум
-- времени (ns.AUCTION_RESCAN_GUARD), и контракт здесь - на ЧИСЛЕ ОБРАЩЕНИЙ в
-- буре сигналов, а не на миллисекундах: число переносится из теста в игру один
-- в один.
H.suite("Реальные данные: буря сигналов аукциона не стоит 367 чтений каждая")
do
    run("POWER")
    local function rebuild()
        ns.CharacterScanner:Scan()
        ns.RecipeBook:Reindex()
        ns.ActionEngine:Build()
    end
    local function reads()
        local e = ns.Diag:Init().calls["Auctionator.API.v1.GetAuctionPriceByItemID"]
        return (e and e.tries) or 0
    end

    -- 1. Сколько стоит ОДИН пересчёт с пустой памятью цен. Это и есть пик.
    ns.Api:ClearAuctionCache("замер: холодная память цен")
    local before = reads()
    rebuild()
    local cold = reads() - before
    print(string.format("     пересчёт с пустой памятью цен: %d чтений у Auctionator", cold))
    H.ok(cold > 100, "пустая память цен действительно дорогая: " .. cold
        .. " чтений (в игре это и был пик 124.7 мс)")

    -- 2. Буря сигналов, как в игре: десять пачек результатов поиска подряд.
    --    Каждая из них ДО правки забывала память целиком.
    local SIGNALS = 10
    before = reads()
    local cleared0 = (ns.Diag:Init().counters or {})["auction.cacheCleared"] or 0
    for _ = 1, SIGNALS do
        ns.AuctionMoment:OnAuction("results")
        rebuild()
    end
    local burst = reads() - before
    local cleared = ((ns.Diag:Init().counters or {})["auction.cacheCleared"] or 0) - cleared0
    print(string.format("     %d сигналов подряд: %d чтений, %d забываний памяти",
        SIGNALS, burst, cleared))
    H.ok(cleared <= 1, string.format(
        "на десять сигналов - не больше одного забывания памяти: %d", cleared))
    H.ok(burst <= cold, string.format(
        "и вся буря стоит не дороже одного холодного пересчёта (%d против %d×%d=%d"
        .. " без ограничителя)", burst, cold, SIGNALS, cold * SIGNALS))

    -- 3. ОТЛОЖЕННОЕ НЕ ТЕРЯЕТСЯ. Окно прошло - первый же проход забывает память,
    --    даже если нового сигнала не было: иначе «не чаще раза в минуту»
    --    превратилось бы в «не вообще», и цены после сканирования не обновились
    --    бы совсем.
    ns.AuctionMoment:OnAuction("results")       -- забывание отложено
    H.ok(ns.Api.auctionClearPending ~= nil, "забывание отложено, а не потеряно")
    H.clock = H.clock + (ns.AUCTION_RESCAN_GUARD or 60) + 1
    before = reads()
    rebuild()
    local after = reads() - before
    print(string.format("     после истечения окна: %d чтений", after))
    H.eq(ns.Api.auctionClearPending, nil, "отложенное забывание выполнено")
    H.ok(after > 100, "и цены действительно перечитаны: " .. after .. " чтений")
end

-- СКОЛЬКО ОБРАЩЕНИЙ ДЕЛАЕТ КАЖДАЯ ВЕТКА.
--
-- Общее число за пересчёт отвечает «дорого ли», но не отвечает «кто именно».
-- Живой прогон: 79.4 мс в среднем, из них ветка перепродажи 74.9. Чтобы такой
-- вопрос закрывался числом, а не догадкой, расход приписывается ветке - по той
-- же разметке ns.PriceProvider.askedFor, которой движок помечает заказ цен.
--
-- Потолки здесь не «красиво», а «в разы меньше, и если снова разрастётся -
-- тест упадёт». Измеренные значения на этом персонаже печатаются рядом.
H.suite("Реальные данные: обращения по веткам за пересчёт")
do
    run("POWER")
    local tally = {}
    local observedItems = {}
    local function bump(kind, itemID)
        local branch = tostring(ns.PriceProvider.askedFor or "вне ветки")
        tally[branch] = tally[branch] or {}
        tally[branch][kind] = (tally[branch][kind] or 0) + 1
        if kind == "observed" and itemID then observedItems[itemID] = true end
    end
    local real = {
        ItemInfo = ns.Api.ItemInfo,
        CodexItemSources = ns.Api.CodexItemSources,
        CodexNpc = ns.Api.CodexNpc,
        MastercraftObservedPrice = ns.Api.MastercraftObservedPrice,
    }
    local realBuy, realSell = ns.PriceProvider.Buy, ns.PriceProvider.Sell
    ns.Api.ItemInfo = function(s, ...) bump("itemInfo"); return real.ItemInfo(s, ...) end
    ns.Api.CodexItemSources = function(s, ...) bump("codex"); return real.CodexItemSources(s, ...) end
    ns.Api.CodexNpc = function(s, ...) bump("codex"); return real.CodexNpc(s, ...) end
    ns.Api.MastercraftObservedPrice = function(s, itemID, ...)
        bump("observed", itemID)
        return real.MastercraftObservedPrice(s, itemID, ...)
    end
    ns.PriceProvider.Buy = function(s, ...) bump("price"); return realBuy(s, ...) end
    ns.PriceProvider.Sell = function(s, ...) bump("price"); return realSell(s, ...) end

    ns.CharacterScanner:Scan()
    ns.RecipeBook:Reindex()
    ns.ActionEngine:Build()

    ns.Api.ItemInfo = real.ItemInfo
    ns.Api.CodexItemSources = real.CodexItemSources
    ns.Api.CodexNpc = real.CodexNpc
    ns.Api.MastercraftObservedPrice = real.MastercraftObservedPrice
    ns.PriceProvider.Buy, ns.PriceProvider.Sell = realBuy, realSell

    local KINDS = { "itemInfo", "price", "codex", "observed" }
    local rows, grand = {}, {}
    for branch, counts in pairs(tally) do
        local total = 0
        for _, k in ipairs(KINDS) do
            total = total + (counts[k] or 0)
            grand[k] = (grand[k] or 0) + (counts[k] or 0)
        end
        rows[#rows + 1] = { branch = branch, counts = counts, total = total }
    end
    table.sort(rows, function(a, b) return a.total > b.total end)
    print(string.format("     %-14s %7s %9s %7s %7s %9s",
        "ветка", "итого", "itemInfo", "цены", "codex", "observed"))
    for _, r in ipairs(rows) do
        print(string.format("     %-14s %7d %9d %7d %7d %9d", r.branch, r.total,
            r.counts.itemInfo or 0, r.counts.price or 0,
            r.counts.codex or 0, r.counts.observed or 0))
    end

    -- НАБЛЮДЁННЫЕ ЦЕНЫ ЧУЖОГО КЕША: спрашивать их можно сколько угодно, а
    -- РАБОТУ надо делать один раз на предмет. До памяти таблица лотов
    -- перебиралась на каждый вопрос - 443 раза за пересчёт.
    print(string.format("     наблюдённые цены: %d обходов таблицы, %d ответов из памяти",
        ns.Api.observedPriceReads or 0, ns.Api.observedPriceHits or 0))
    local observedDistinct = 0
    for _ in pairs(observedItems) do observedDistinct = observedDistinct + 1 end
    -- ПОЛ У ЭТОГО ЧИСЛА - «ни одного лишнего обхода», и он теперь строже, чем
    -- «один на предмет»: память ответов чужой книги переживает пересчёт, потому
    -- что её ответ не может измениться сам (лот туда попадает только когда
    -- игрок что-то купил или продал). Поэтому обходов за УСТАНОВИВШИЙСЯ
    -- пересчёт - ноль, а «один на предмет» проверяется отдельно, сразу после
    -- сброса памяти.
    H.ok((ns.Api.observedPriceReads or 0) <= observedDistinct, string.format(
        "лишних обходов таблицы лотов нет: %d обходов на %d разных предметов",
        ns.Api.observedPriceReads or 0, observedDistinct))
    H.ok((grand.observed or 0) > observedDistinct, string.format(
        "а вопросов было больше (%d), то есть повторы память съела",
        grand.observed or 0))

    -- ЧУЖАЯ КНИГА ЗАКУПОК: 21 ОБХОД КАЖДЫЙ ПЕРЕСЧЁТ - И НИ ОДНОГО ОТВЕТА.
    --
    -- Это был единственный маршрут, который повторялся на каждом пересчёте без
    -- исключения: в живом файле игрока 6804 обращения за сессию, все пустые. У
    -- этих предметов все лоты помечены «сделано мной» - то есть в книге лежит
    -- себестоимость игрока, а не цена рынка, и ответ по ним не изменится, пока
    -- игрок что-то не купит. Теперь память об этом живёт до события покупки.
    do
        -- Пересчёт - то же звено, что и в замере выше: снимок, пересборка книги
        -- рецептов и сборка советов.
        local function fullRebuild()
            ns.CharacterScanner:Scan()
            ns.RecipeBook:Reindex()
            ns.ActionEngine:Build()
        end
        local dropped = ns.Api:ClearObservedPriceMemory("замер: холодная память")
        H.ok(dropped > 0, "память ответов чужой книги была непустая: "
            .. dropped .. " предметов")
        local before = ns.Api.observedPriceReads or 0
        local asked = {}
        local realObserved = ns.Api.MastercraftObservedPrice
        ns.Api.MastercraftObservedPrice = function(self, itemID, ...)
            if itemID then asked[itemID] = true end
            return realObserved(self, itemID, ...)
        end
        fullRebuild()
        local coldReads = (ns.Api.observedPriceReads or 0)
        local coldDistinct = 0
        for _ in pairs(asked) do coldDistinct = coldDistinct + 1 end
        print(string.format("     чужая книга: холодный пересчёт - %d обходов на %d"
            .. " разных предметов", coldReads, coldDistinct))
        H.ok(coldReads > 0 and coldReads <= coldDistinct, string.format(
            "после сброса памяти обход делается не больше раза на предмет: %d на %d",
            coldReads, coldDistinct))

        -- А дальше - ни одного: событий покупки не было.
        ns.Api.observedPriceReads = 0
        local PASSES = 3
        for _ = 1, PASSES do fullRebuild() end
        ns.Api.MastercraftObservedPrice = realObserved
        local per = (ns.Api.observedPriceReads or 0) / PASSES
        print(string.format("     чужая книга: установившееся состояние - %.1f"
            .. " обходов за пересчёт", per))
        H.ok(per <= 1, string.format(
            "без покупок чужую книгу не перебираем вовсе (живое было 21 обход"
            .. " каждый пересчёт, 6804 за сессию): %.1f", per))

        -- И ПРИЧИНА МОЛЧАНИЯ ОСТАЛАСЬ СЛОВАМИ, а не исчезла вместе с обходами.
        local silence = ns.Api:ObservedPriceSilence()
        H.ok(silence ~= nil, "молчание чужой книги названо словами")
        if silence then
            print(string.format("     чужая книга молчит по %d предметам: «%s» (%d)",
                silence.items, tostring(silence.why), silence.n))
            H.ok(type(silence.why) == "string" and silence.why ~= "",
                "причина - фраза, а не код: " .. tostring(silence.why))
            H.ok(silence.items > 0, "и сказано, по скольким предметам")
        end
    end
    -- И ни одна ветка не должна делать больше трёх тысяч обращений: на этом
    -- персонаже самая дорогая (развилка путей) делает около тысячи восьмисот.
    for _, r in ipairs(rows) do
        H.ok(r.total <= 3000, string.format(
            "ветка «%s» укладывается в 3000 обращений: %d", r.branch, r.total))
    end
end

-- СКОЛЬКО РАЗНЫХ ПРЕДМЕТОВ МЫ ОЦЕНИВАЕМ ЗА ПЕРЕСЧЁТ.
--
-- Из живой сводки: «Данных не хватило по 5 предметам, 5741 цене». Число
-- огромное, и оно не про нехватку - оно про РАЗМАХ: 5741 это количество РАЗНЫХ
-- предметов, по которым за сессию спросили цену и получили ответ старше суток.
-- Пять с лишним тысяч - это половина базы предметов, и персонажу с четырьмя
-- золотыми столько цен не нужно.
--
-- Контракт - на числе РАЗНЫХ предметов за пересчёт. Оно и есть та величина,
-- которая раздувала и заказ данных, и журнал цен (23 550 записей не влезли).
H.suite("Реальные данные: разных предметов с ценой за пересчёт")
do
    run("POWER")
    local seen, calls = {}, 0
    local origBuy = ns.PriceProvider.Buy
    ns.PriceProvider.Buy = function(self, itemID, link)
        calls = calls + 1
        if itemID then seen[itemID] = (seen[itemID] or 0) + 1 end
        return origBuy(self, itemID, link)
    end
    ns.CharacterScanner:Scan()
    ns.RecipeBook:Reindex()
    ns.ActionEngine:Build()
    ns.PriceProvider.Buy = origBuy

    local distinct = 0
    for _ in pairs(seen) do distinct = distinct + 1 end
    print(string.format("     Price:Buy: %d вызовов, %d разных предметов",
        calls, distinct))
    -- Круг поиска у персонажа этого размера: сумки, реагенты выученных и
    -- невыученных рецептов, список наблюдения из Horizon и кандидаты
    -- арбитража. Всё вместе - сотни, а не тысячи.
    H.ok(distinct <= 1200, string.format(
        "разных предметов за пересчёт не больше 1200 (в живом прогоне за"
        .. " сессию их набралось 5741): %d", distinct))
end

H.suite("Реальные данные: глубокая цепочка материалов")
do
    run("POWER")
    -- Find the recipe with the deepest material tree and make sure it resolves.
    local deepest, deepestPlan = nil, nil
    local n = 0
    for _, recipe in ipairs(ns.RecipeBook:Iterate(function(r)
        return r.learned and r.output and #r.reagents > 1
    end)) do
        n = n + 1
        if n > 120 then break end
        local plan = ns.CraftingPlanner:Plan(recipe, 1)
        if plan and (not deepestPlan or #plan.crafts > #deepestPlan.crafts) then
            deepest, deepestPlan = recipe, plan
        end
    end
    H.ok(deepestPlan ~= nil, "план найден")
    if deepestPlan then
        print(string.format("     самая длинная цепочка: «%s» - %d шагов, глубина %d",
            deepest.name, #deepestPlan.crafts, deepestPlan.depthReached))
        for i, step in ipairs(deepestPlan.crafts) do
            if i <= 6 then
                print("        " .. i .. ". " .. (step.recipe.name or "?") .. " x" .. step.times)
            end
        end
        H.ok(#deepestPlan.crafts >= 1, "цепочка непустая")
        H.ok(deepestPlan.depthReached <= ns.PLANNER_MAX_DEPTH,
            "глубина в пределах лимита (" .. deepestPlan.depthReached .. ")")
        H.eq(deepestPlan.truncated, false, "обрезать дерево не пришлось")
    end
end

H.suite("Реальные данные: диагностика на настоящем персонаже")
do
    run("POWER")
    local s = ns.Diag:Init()

    H.ok(ns.Util.count(s.detect) > 20,
        ns.Util.count(s.detect) .. " функций проверено на существование")
    H.ok(ns.Util.count(s.calls) > 0,
        ns.Util.count(s.calls) .. " функций вызвано с записью результата")
    H.ok(ns.Util.count(s.modules) >= 10,
        ns.Util.count(s.modules) .. " модулей отчиталось")

    print("")
    print("   --- что диагностика напишет в файл ---")
    local names = {}
    for name in pairs(s.modules) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        local m = s.modules[name]
        local line = string.format("   %-18s вход %-6s выход %-6s",
            name, tostring(m["in"]), tostring(m.out))
        if (m.out or 0) == 0 and m.reason then
            line = line .. "| " .. ns.Util.truncate(m.reason, 70)
        end
        print(line)
    end

    print("   --- вызовы, вернувшие пусто ---")
    local quiet = {}
    for name, e in pairs(s.calls) do
        if e.gotData == 0 then quiet[#quiet + 1] = name end
    end
    table.sort(quiet)
    if #quiet == 0 then
        print("   (нет)")
    else
        for _, name in ipairs(quiet) do
            print("   " .. name .. ": " .. tostring(s.calls[name].note or ""))
        end
    end

    print("   --- странности, найденные автопроверками ---")
    if #s.suspicious == 0 then
        print("   (нет)")
    else
        for _, e in ipairs(s.suspicious) do
            print("   [" .. e.code .. "] " .. ns.Util.truncate(e.text, 110)
                .. (e.count > 1 and ("  x" .. e.count) or ""))
        end
    end

    print("   --- ошибки ---")
    if #s.errors == 0 then
        print("   (нет)")
    else
        for _, e in ipairs(s.errors) do
            print("   ! " .. e.where .. ": " .. ns.Util.truncate(e.message, 110))
        end
    end

    H.eq(#s.errors, 0, "на реальных данных ошибок не поймано")
    H.ok(#s.cards > 0, #s.cards .. " карточек записано целиком")
    H.ok(s.perf.recomputes > 0, "тайминги собраны: " .. s.perf.recomputes
        .. " пересчётов, пик " .. string.format("%.1f", s.perf.peakMs)
        .. " мс, среднее " .. string.format("%.1f", s.perf.avgMs or 0) .. " мс")

    print("   --- на что уходит время в пересчёте ---")
    local branch = s.modules.actionEngine and s.modules.actionEngine.branchMs
    if branch then
        local names = {}
        for name in pairs(branch) do names[#names + 1] = name end
        table.sort(names, function(a, b) return branch[a] > branch[b] end)
        for _, name in ipairs(names) do
            print(string.format("   %-10s %6.1f мс", name, branch[name]))
        end
    else
        print("   (нет разбивки)")
    end
    -- A rebuild is event-driven and debounced, so tens of milliseconds are
    -- acceptable; hundreds would be felt as a hitch.
    H.ok(s.perf.avgMs < 250,
        string.format("средний пересчёт укладывается в бюджет (%.1f мс)", s.perf.avgMs or 0))

    -- Size: the whole point of the caps.
    ns.Diag:Trim()
    local kb = (s.sizeEstimate or 0) / 1024
    print(string.format("   размер сессии примерно %.0f КБ (три сессии = %.0f КБ)",
        kb, kb * 3))
    H.ok(kb < 220, string.format("сессия укладывается в разумный размер (%.0f КБ)", kb))
end

H.suite("Реальные данные: интермедиаты определяются правильно")
do
    run("POWER")
    -- The real chain: 5 runecloth -> 1 bolt of runecloth (recipe 18401).
    local boltRecipe = ns.RecipeBook:Get(18401)
    if boltRecipe then
        print("     проверяем: " .. boltRecipe.name)
        H.eq(boltRecipe.output, 14048, "делает рулон рунной ткани")
        local merged = ns.RecipeBook:MergedReagents(boltRecipe)
        H.eq(#merged, 1, "один реагент")
        H.eq(merged[1].itemID, 14047, "это рунная ткань")
        H.eq(merged[1].qty, 5, "5 штук на рулон")
        -- Anything needing bolts must decide craft-or-buy, not silently stall.
        local beltRecipe = ns.RecipeBook:Get(18402)
        if beltRecipe then
            local plan = ns.CraftingPlanner:Plan(beltRecipe, 1)
            H.ok(plan ~= nil, "план на пояс из рунной ткани построен")
            if plan then
                local d = plan.decisions[14048]
                H.ok(d ~= nil, "решение по рулону принято")
                if d then
                    print(string.format("        рулон рунной ткани: %s (крафт %s / покупка %s)",
                        d.method,
                        d.craftCost and ns.Util.money(d.craftCost) or "?",
                        d.buyCost and ns.Util.money(d.buyCost) or "?"))
                    H.ok(d.method == "craft" or d.method == "buy", "решение осмысленное")
                end
            end
        end
    else
        print("     рецепт 18401 в кеше не найден - проверка пропущена")
        H.ok(true, "пропущено")
    end
end

-- ВЕТКА ПЕРЕПРОДАЖИ НА НАСТОЯЩИХ ДАННЫХ =================================
--
-- Живой прогон выдал восемь карточек «Купить и перепродать», и семь из них
-- вели к Mister Graphed с наценкой от 419% до 2433%. Проверка идёт по тем же
-- записям пакета и той же истории цен игрока.
--
-- ЧТО ИХ ОТСЕИВАЕТ. Цены выкупа у этих предметов клиент в наших файлах не
-- оставил (в журнале цен живой сессии её нет ни у одного из них), а по отчёту
-- сообщества торговец платит за Чёрный лотос около СЕРЕБРА - то есть
-- «прилавок 40с» выше цены выкупа и проверку на полярность проходит. Значит
-- работает здесь именно ПОТОЛОК НАЦЕНКИ, и проверять надо его.
--
-- Цены аукциона берутся из собственных суточных слепков игрока - это
-- настоящие наблюдения, а не выдумка. Цену выкупа мы НЕ ПОДСТАВЛЯЕМ: именно её
-- отсутствие и есть живое состояние.
H.suite("Реальные данные: вендорный потолок из собственного кеша игрока")
do
    -- ЭТО ПРОВЕРКА НА НАСТОЯЩИХ ЧИСЛАХ, И ПО-ДРУГОМУ ОНА НЕ РАБОТАЕТ.
    --
    -- В кеше игрока 561 вендорная цена, и у части реагентов его рецептов
    -- аукцион стоит ВЫШЕ прилавка: Mild Spices (2678) вдвое, Heavy Silken
    -- Thread (8343) на 80 медяков за штуку. На выдуманных фикстурах такого
    -- состояния не было вовсе.
    -- ПРОПУСК ТОЛЬКО ТОГДА, КОГДА ПОТОЛКОВ НЕТ В САМОМ ФАЙЛЕ.
    --
    -- Раньше условие смотрело на то, сколько потолков дошло до стенда, и
    -- отключённая проводка выглядела как «у игрока их нет»: набор молча
    -- пропускал ровно те проверки, ради которых и написан. Теперь файл и стенд
    -- сверяются между собой.
    local inFile = select(2, vendorCeilings(au))
    if inFile == 0 then
        H.ok(true, "вендорных цен в кеше Auctionator нет — проверка пропущена"
            .. " (это нормальный случай, а не поломка)")
    else
        H.eq(realCeilingCount, inFile,
            "стенд получил все вендорные цены из кеша: " .. inFile)
        -- Память цен НЕ сбрасывается после пересчёта: решения по потолкам
        -- живут ровно один пересчёт, и смотреть надо на те, по которым
        -- построен этот список. Сброс здесь стоял - и смотреть было не на что.
        local cards = run("POWER")

        -- 1. ГЛАВНОЕ УТВЕРЖДЕНИЕ: ни один материал не стоит дороже полки.
        --    Считается по тем же вызовам, которыми считает движок.
        local over, checked, cheaper = {}, 0, {}
        for _, card in ipairs(cards) do
            for _, line in ipairs((card.plan and card.plan.shopping) or {}) do
                local ceiling = ns.PriceProvider:VendorCeiling(line.itemID)
                if ceiling and line.unit then
                    checked = checked + 1
                    if line.unit > ceiling then
                        over[#over + 1] = string.format("%d: %s > %s",
                            line.itemID, ns.Util.money(line.unit),
                            ns.Util.money(ceiling))
                    end
                end
            end
        end
        H.eq(#over, 0, "ни один материал в планах не дороже своего потолка"
            .. " (проверено " .. checked .. ")"
            .. ((#over > 0) and ("  <- " .. table.concat(over, "; ")) or ""))

        -- 2. СКОЛЬКО ПОТОЛКОВ РЕАЛЬНО СРАБОТАЛО, И ПО КАКИМ ПРЕДМЕТАМ.
        --    Печатается списком: зелёный набор и осмысленный совет - два
        --    разных вопроса, и второй читает человек.
        for itemID in pairs(ns.PriceProvider.ceilingSession or {}) do
            local v = ns.PriceProvider:Ceiling(itemID)
            if v and v.cheaper == "vendor" and v.saving and v.saving > 0 then
                cheaper[#cheaper + 1] = { id = itemID, v = v }
            end
        end
        table.sort(cheaper, function(a, b) return a.v.saving > b.v.saving end)
        print("     --- где прилавок дешевле аукциона (за штуку) ---")
        for i = 1, math.min(10, #cheaper) do
            local e = cheaper[i]
            local info = ns.Api:ItemInfo(e.id)
            print(string.format("     %7d  %-28s торговец %-10s аукцион %-10s экономия %s",
                e.id, ns.Util.truncate((info and info.name) or "?", 28),
                ns.Util.money(e.v.ceiling), ns.Util.money(e.v.auction),
                ns.Util.money(e.v.saving)))
        end
        print("     всего таких предметов за пересчёт: " .. #cheaper)

        -- 3. И ЕСЛИ ОНИ ЕСТЬ - ЭТО СКАЗАНО СЛОВАМИ. Карточка покупки с
        --    вендорной ценой обязана называть и прилавок, и экономию.
        local said, silent = 0, {}
        for _, card in ipairs(cards) do
            if card.kind == ns.KIND.BUY and card.matPrice
                and card.matPrice.src == "vendor" then
                if ns.Util.contains(card.why or "", "У торговца дешевле") then
                    said = said + 1
                else
                    silent[#silent + 1] = tostring(card.title)
                end
            end
        end
        H.eq(#silent, 0, "каждая карточка покупки с вендорной ценой говорит об"
            .. " этом словами (" .. said .. ")"
            .. ((#silent > 0) and ("  <- " .. table.concat(silent, "; ")) or ""))
    end
end

H.suite("Реальные данные: потолок не поднимает стоимость молча")
do
    -- Обратная сторона того же правила. Там, где аукцион ЧЕСТНО дешевле полки,
    -- аддон обязан оставить аукционную цену: подменить её вендорной значило бы
    -- сказать игроку сумму больше настоящей. Единственное, что меняется, -
    -- достоверность у слабого минимума (одно наблюдение и разрыв в копейки).
    if select(2, vendorCeilings(au)) == 0 then
        H.ok(true, "вендорных цен в кеше Auctionator нет — проверка пропущена")
    else
        run("POWER")
        local kept, raised, thin, byKind = 0, {}, 0, { vendor = 0, auction = 0, equal = 0 }
        for itemID in pairs(ns.PriceProvider.ceilingSession or {}) do
            local v = ns.PriceProvider:Ceiling(itemID)
            if v then
                byKind[v.cheaper] = (byKind[v.cheaper] or 0) + 1
                if v.cheaper == "auction" then
                    local copper, conf, src = ns.PriceProvider:Buy(itemID)
                    if copper and copper <= v.auction then
                        kept = kept + 1
                    else
                        raised[#raised + 1] = string.format("%d: %s вместо %s",
                            itemID, ns.Util.money(copper), ns.Util.money(v.auction))
                    end
                    if v.thin then
                        thin = thin + 1
                        H.ok(conf == ns.CONF.ESTIMATE or conf == ns.CONF.UNKNOWN,
                            string.format("слабый минимум по предмету %d помечен"
                                .. " оценкой: %s (%s)", itemID, tostring(conf),
                                tostring(src)))
                    end
                end
            end
        end
        H.eq(#raised, 0, "ни одному предмету потолок не поднял цену"
            .. ((#raised > 0) and ("  <- " .. table.concat(raised, "; ")) or ""))
        print(string.format("     предметов с потолком за пересчёт: дешевле у"
            .. " торговца %d, дешевле на аукционе %d (из них слабых минимумов"
            .. " %d), поровну %d", byKind.vendor or 0, byKind.auction or 0,
            thin, byKind.equal or 0))
        if (byKind.auction or 0) == 0 then
            H.note("на этих данных нет ни одного предмета, где аукцион дешевле"
                .. " полки, — утверждение про «не поднимает молча» проверено"
                .. " только на фикстурах (Tests/test_ceiling.lua)")
        else
            H.ok(kept > 0, kept .. " предметов, где аукцион честно дешевле полки,"
                .. " так и остались аукционными")
        end
    end
end

H.suite("Реальные данные: наценки Mister Graphed не проходят потолок")
do
    local history = (fp and fp.ForeverPilotDB and fp.ForeverPilotDB.priceHistory) or nil
    if not history then
        H.ok(true, "суточных слепков цен у игрока нет — проверка пропущена")
    else
        local cfg = ns.Config:Get()
        cfg.priceHistory = history
        -- Предметы с прилавка этого торговца: регистрируем их в кеше клиента
        -- ровно так, как клиент их и отдаёт - БЕЗ цены выкупа.
        local WATCH = { 13468, 12363, 248819, 248822, 249399, 249274, 249429 }
        local prices = {}
        for _, id in ipairs(WATCH) do
            env.items[id] = env.items[id] or {
                name = "Предмет #" .. id, quality = 2, sellPrice = nil,
            }
            -- Цена аукциона: последняя запись из слепков игрока.
            local newestDay, newest = nil, nil
            for day, copper in pairs(history[id] or {}) do
                local d = tonumber(day)
                if d and ((not newestDay) or d > newestDay) then
                    newestDay, newest = d, tonumber(copper)
                end
            end
            if newest then prices[id] = newest end
            env.bags[id] = env.bags[id] or 0
        end
        for id, copper in pairs(prices) do env.prices[id] = copper end
        H.itemsChanged(env)
        run("POWER")
        ns.PriceProvider:BeginPass()

        local verdicts = {}
        for _, id in ipairs(WATCH) do
            local opp, why = ns.VendorArbitrage:Evaluate(id)
            local code = opp and (opp.markupVerdict and opp.markupVerdict.code or "верю")
                or ("отсеян: " .. tostring(why))
            verdicts[id] = { opp = opp, code = code }
            print(string.format("     %7d  аукцион %-10s наценка %-8s %s", id,
                prices[id] and ns.Util.money(prices[id]) or "нет",
                opp and string.format("x%.1f", opp.markup) or "-", code))
        end

        -- Чёрный лотос: 40 серебра на прилавке против 9-10 золотых на аукционе.
        -- Это наценка больше двадцати раз, и такому числу верить нельзя.
        local lotus = verdicts[13468]
        if lotus and lotus.opp then
            H.ok(lotus.opp.markup > ns.VendorArbitrage.MARKUP_LIMIT, string.format(
                "наценка на Чёрный лотос выше потолка: x%.1f > %d",
                lotus.opp.markup, ns.VendorArbitrage.MARKUP_LIMIT))
            H.eq(lotus.code, "markup-impossible",
                "и вердикт: такой наценке я не верю")
            H.eq(lotus.opp.conf, ns.CONF.UNKNOWN, "достоверность снята")
            H.eq(lotus.opp.askLone, true,
                "а цену подтверждает один источник данных — и это тоже сказано")
        else
            H.ok(true, "Чёрный лотос в советы не попал по другой причине ("
                .. tostring(lotus and lotus.code) .. ")")
        end

        -- И ни одна из этих позиций не должна остаться БЕЗ оговорки: либо
        -- отсеяна, либо помечена наценкой, либо помечена концентрацией.
        local clean = {}
        for _, id in ipairs(WATCH) do
            local v = verdicts[id]
            if v and v.opp and v.code == "верю" and not v.opp.concentration
               and not v.opp.askLone then
                clean[#clean + 1] = id
            end
        end
        H.eq(#clean, 0,
            "ни один товар этого торговца не выдан за чистую находку: "
            .. table.concat(clean, ", "))
    end
end

H.suite("Реальные данные: концентрация советов на одном торговце замечена")
do
    local cards = run("POWER")
    local conc = ns.VendorArbitrage.lastConcentration
    local arb = 0
    for _, c in ipairs(cards) do
        if c.kind == ns.KIND.ARBITRAGE then arb = arb + 1 end
    end
    print("     карточек перепродажи: " .. arb .. "; концентрация: "
        .. (conc and string.format("%d из %d на %s", conc.count, conc.total,
            tostring(conc.npcName)) or "нет"))
    if conc then
        H.ok(conc.share >= ns.VendorArbitrage.CONCENTRATION_SHARE,
            "доля - большинство: " .. string.format("%.2f", conc.share))
        -- И самопроверка должна была это записать.
        local found
        for _, s in ipairs(ns.Diag:Init().suspicious or {}) do
            if s.code == "advice-concentrated-on-one-source" then found = s end
        end
        H.ok(found ~= nil, "и самопроверка записала это в диагностику")
        if found then
            print("     " .. ns.Util.truncate(found.text or "", 200))
        end
    else
        H.ok(true, "советы разошлись по разным торговцам — концентрации нет")
    end
end

-- ДВА ПЕРСОНАЖА С ОДНИМ ИМЕНЕМ, НА НАСТОЯЩИХ ДАННЫХ ======================
--
-- В файлах игрока оба персонажа названы «Гендольф»: маг «Гендольф Серыйй»
-- 27 уровня и чернокнижник «Гендольф Белыйй» 10 уровня. Живой прогон выдал
-- карточку «Скрафтить для Гендольф Серыйй — у «Гендольф Серыйй» (8) профессий
-- нет», то есть предложил магу делать вещи для самого себя. Проверка идёт на
-- тех же данных, а не на выдуманных.
H.suite("Реальные данные: одноимённые персонажи различаются")
do

    local snap = ns.CharacterScanner:Scan()
    H.eq(snap.name, charInfo.name, "в снимке имя без фамилии: " .. tostring(snap.name))
    if charInfo.surname then
        H.eq(snap.surname, charInfo.surname,
            "фамилия прочитана: " .. tostring(snap.surname))
        H.eq(snap.fullName, charInfo.name .. " " .. charInfo.surname,
            "и полное имя собрано: " .. tostring(snap.fullName))
    else
        H.ok(true, "у этого персонажа фамилии в кеше нет — проверка пропущена")
    end

    -- Кеш Mastercraft знает оба персонажа: по нему и берутся уровень и класс.
    local known = ns.Api:MastercraftCharacters()
    H.ok(known ~= nil, "персонажи из кеша Mastercraft прочитаны")
    if known then
        local n = 0
        for _ in pairs(known) do n = n + 1 end
        H.ok(n >= 2, "их больше одного: " .. n)
        local sameName = {}
        for full, c in pairs(known) do
            sameName[c.name] = (sameName[c.name] or 0) + 1
            H.ok(c.level ~= nil, "у «" .. full .. "» известен уровень: "
                .. tostring(c.level))
        end
        local maxSame = 0
        for _, k in pairs(sameName) do if k > maxSame then maxSame = k end end
        H.ok(maxSame >= 2,
            "и среди них есть одноимённые — именно тот случай, из-за которого"
            .. " различать приходится по фамилии, уровню и классу")
    end
end

-- ПОРОГ МЕЛКОЙ ДЕНЕЖНОЙ ВЫГОДЫ, ИЗМЕРЕННЫЙ НА НАСТОЯЩИХ ДЕНЬГАХ ==========
--
-- Игрок просил не показывать мелкий денежный выигрыш и назвал два числа: «с
-- 10-го и выше серебра» на мелких уровнях и «больше 30-ти как минимум» выше.
-- Единица у «30» не названа - золотые или серебряные, - и решать это должен он.
-- Поэтому здесь порог не проверяется «работает или нет» (это делает
-- Tests/test_economy.lua на заданных числах), а ИЗМЕРЯЕТСЯ: сколько денежных
-- советов у него останется при каждом варианте. Фикстуры на этот вопрос
-- ответить не могут - в них деньги игрушечные.
--
-- Таблица печатается, потому что выбор делает человек; утверждения ниже держат
-- только то, что от чисел не зависит: порядок (строже порог - меньше советов) и
-- то, что пропажа объявлена.
H.suite("Реальные данные: порог мелкой выгоды — сколько советов он оставляет")
do
    local U = ns.Util
    local function moneyCount()
        local n, biggest = 0, nil
        for _, card in ipairs(ns.ActionEngine.cards or {}) do
            if ns.MONEY_FLOOR_KINDS[card.kind] then
                n = n + 1
                local v = tonumber(card.benefitValue)
                if v and ((not biggest) or v > biggest) then biggest = v end
            end
        end
        return n, biggest
    end

    -- Полоса, которая действует на этом персонаже по его настоящему уровню.
    local band, index = ns.Config:MoneyFloorBand(snap and snap.level)
    H.ok(band ~= nil, "по уровню " .. tostring(snap and snap.level)
        .. " подходит полоса «" .. tostring(band and band.label) .. "» ("
        .. U.money(band and band.copper) .. ")")

    -- Без порога: это и есть «сколько денежных советов сейчас».
    ns.Config:SetMoneyFloorMode(ns.MONEY_FLOOR_MODE.OFF)
    run("EARN")
    local total, biggest = moneyCount()
    H.ok(total > 0, "без порога денежных советов: " .. total)
    H.ok(biggest ~= nil, "самый крупный из них даёт " .. U.money(biggest))

    -- И те же советы при каждом из порогов, про которые был разговор.
    local VARIANTS = {}
    for _, b in ipairs(ns.MONEY_FLOOR_BANDS) do
        VARIANTS[#VARIANTS + 1] = { b.label .. " (полоса)", b.copper }
    end
    VARIANTS[#VARIANTS + 1] = { "30 серебра", 3000 }
    VARIANTS[#VARIANTS + 1] = { "1 золотой", 10000 }
    VARIANTS[#VARIANTS + 1] = { "30 золотых", 300000 }

    ns.Config:SetMoneyFloorMode(ns.MONEY_FLOOR_MODE.FIXED)
    print(string.format("     %-22s %-10s %-12s %s", "порог", "медь",
        "осталось", "убрано"))
    local prevFloor, prevLeft = -1, total
    local atThirtyGold
    for _, v in ipairs(VARIANTS) do
        ns.Config:SetMoneyFloorOwn(v[2])
        run("EARN")
        local left = moneyCount()
        local meta = ns.ActionEngine.meta or {}
        print(string.format("     %-22s %-10s %-12s %s", v[1], U.money(v[2]),
            left .. " из " .. total, tostring(meta.moneyFloorDropped)))
        H.eq(left + (meta.moneyFloorDropped or 0), total,
            v[1] .. ": осталось плюс убрано равно тому, что было (" .. total .. ")")
        if (meta.moneyFloorDropped or 0) > 0 then
            H.ok(meta.moneyFloorNote ~= nil,
                v[1] .. ": пропажа объявлена словами")
        end
        -- Порог строже - советов не больше. Это и есть «чем выше порог, тем
        -- меньше воды», и на настоящих числах это проверяемо.
        if v[2] >= prevFloor then
            H.ok(left <= prevLeft, v[1] .. ": советов не больше, чем при пороге пониже ("
                .. left .. " <= " .. prevLeft .. ")")
        end
        prevFloor, prevLeft = v[2], left
        if v[2] == 300000 then atThirtyGold = left end
    end

    -- ГЛАВНОЕ ЧИСЛО ЭТОГО РАЗДЕЛА. Подозрение было такое: «порог в 30 золотых
    -- обнулит список почти целиком». На настоящих данных он обнуляет его
    -- ЦЕЛИКОМ - ни одного денежного совета у этого персонажа не дотягивает до
    -- золотого, не говоря о тридцати. Утверждение написано не как «ноль», а как
    -- «меньше, чем оставляет самая строгая полоса»: числа в сохранениях меняются
    -- от игры к игре, а это соотношение - нет.
    ns.Config:SetMoneyFloorOwn(ns.MONEY_FLOOR_BANDS[#ns.MONEY_FLOOR_BANDS].copper)
    run("EARN")
    local atTopBand = moneyCount()
    H.ok(atThirtyGold ~= nil, "порог 30 золотых измерен: осталось "
        .. tostring(atThirtyGold) .. " из " .. total)
    H.ok((atThirtyGold or 0) <= atTopBand,
        "и он оставляет не больше, чем самая строгая полоса ("
        .. tostring(atThirtyGold) .. " против " .. atTopBand .. ")")
    H.ok(biggest ~= nil and biggest < 300000,
        "самый крупный денежный совет на настоящих данных ("
        .. U.money(biggest) .. ") до 30 золотых не дотягивает —"
        .. " значит, такой порог выключил бы деньги целиком, а не отсеял воду")

    -- И ПРИ РАБОЧЕМ ПОРОГЕ НИ ОДНА ПОКУПКА НЕ ЗОВЁТ УБРАННЫЙ СОВЕТ.
    --
    -- Ветка покупок строится до порога, и на этих самых данных выходило четыре
    -- карточки «Купить материалы» под советы «на продажу», которые порог только
    -- что убрал. Проверяется по полосе этого персонажа - то есть по тому
    -- порогу, который он и увидит.
    ns.Config:SetMoneyFloorMode(ns.MONEY_FLOOR_MODE.LEVEL)
    run("EARN")
    local onScreen, buys, orphans = {}, 0, {}
    for _, card in ipairs(ns.ActionEngine.cards or {}) do onScreen[card.key] = true end
    for _, card in ipairs(ns.ActionEngine.cards or {}) do
        if card.kind == ns.KIND.BUY and type(card.buyFor) == "table" then
            buys = buys + 1
            local live = 0
            for key, title in pairs(card.buyFor) do
                if onScreen[key] or title == ns.ActionEngine.PINNED_BY_HAND then
                    live = live + 1
                end
            end
            if live == 0 then orphans[#orphans + 1] = tostring(card.title) end
        end
    end
    H.ok(buys >= 0, "карточек покупки при рабочем пороге: " .. buys)
    H.eq(#orphans, 0, "ни одна из них не нужна только убранному совету"
        .. ((#orphans > 0) and ("  <- " .. table.concat(orphans, "; ")) or ""))

    -- Вернуть как было, чтобы следующие разделы считали тот же список.
    ns.Config:SetMoneyFloorMode(ns.MONEY_FLOOR_MODE.OFF)
    run("POWER")
end

-- САМОПРОВЕРКА НЕ МОЛЧИТ НА ЭКРАНЕ ПРО ТО, О ЧЁМ ПИШЕТ В ФАЙЛ ==============
--
-- Это проверка на НАСТОЯЩИХ данных, и только она отвечает на вопрос, из-за
-- которого всё и делалось. У игрока в файле на каждом пересчёте стояла строка
-- «„На продажу: Небесно-голубая краска“: выручка 1з 24с против цены торговца
-- 75м — это в 166 раз больше», а карточка стояла вторым советом сверху без
-- единого слова об этом. Выдуманный мир такого состояния не давал: на фикстурах
-- набор был зелёным.
--
-- Три вопроса: доехала ли каждая находка «про эту карточку» до своей карточки,
-- не отрицает ли какая-нибудь карточка себя первой фразой, и не стоит ли
-- сомнительное число наверху списка.

H.suite("Реальные данные: каждая находка «про эту карточку» доехала до карточки")
do
    local Sense = assert(loadfile(H.ROOT .. "/Tests/sense.lua"))()
    local profiles = ns.PROFILE_ORDER
    local checkedFindings, checkedCards, stray, refuting, doubtOnTop = 0, 0, {}, {}, {}
    local doubted = 0
    for _, profile in ipairs(profiles) do
        local cards = run(profile)
        local byKey = {}
        for _, card in ipairs(cards) do byKey[card.key] = card end

        -- 1. Находка с ключом карточки обязана быть НА этой карточке - и
        --    ВИДНА на ней, а не просто приложена: «приложено, но не напечатано»
        --    для игрока ровно то же, что «только в файле».
        for _, e in ipairs(ns.Diag:Init().suspicious or {}) do
            local key = type(e.detail) == "table" and e.detail.key or nil
            local scope = ns.SanityChecks:Scope(e.code)
            if key and byKey[key] and scope ~= "list" then
                checkedFindings = checkedFindings + 1
                local card = byKey[key]
                local why = tostring(card.why or "")
                local found, why2 = false, nil
                for _, d in ipairs(card.doubts or {}) do
                    if d.code == e.code then found = true end
                end
                if not found then
                    why2 = "к карточке не приложено"
                elseif card.doubtLevel == nil then
                    why2 = "приложено, но карточка не помечена сомнением"
                elseif scope == "say" then
                    local say = ns.Risk:StripTitle(card, e.text)
                    if not ns.Util.contains(why, say) then
                        why2 = "приложено, но на карточке не напечатано"
                    end
                elseif not ns.Util.contains(why, ns.Risk.DOUBT_DEFECT_SAY) then
                    why2 = "приложено, но игроку не сказано, что числам верить нельзя"
                end
                if why2 then
                    stray[#stray + 1] = profile .. " / [" .. e.code .. "] «"
                        .. tostring(card.title) .. "»: " .. why2
                end
            end
        end

        -- 2. Ни одна карточка не отрицает себя первой фразой.
        for i, card in ipairs(cards) do
            checkedCards = checkedCards + 1
            if card.doubtLevel then doubted = doubted + 1 end
            local f = Sense.selfRefuting(card.why)
            if f then
                refuting[#refuting + 1] = profile .. " / «" .. tostring(card.title)
                    .. "»: " .. f.hit
            end
            -- 3. И сомнительное число не стоит наверху: выше него обязан быть
            --    хотя бы один совет без оговорок.
            if card.doubtLevel and i <= 2 then
                local firm = false
                for j = 1, i - 1 do
                    if ns.ActionEngine.TierOf(cards[j]) == 2 then firm = true end
                end
                if not firm then
                    doubtOnTop[#doubtOnTop + 1] = profile .. " / №" .. i .. " «"
                        .. tostring(card.title) .. "»"
                end
            end
        end
    end
    H.ok(checkedCards > 20, "карточек на настоящих данных просмотрено: " .. checkedCards)
    print("     сомнительных карточек на настоящих данных: " .. doubted
        .. ", находок «про карточку» сверено: " .. checkedFindings)
    -- И что именно игрок на них прочитает - глазами. Зелёный набор и понятная
    -- оговорка - два разных вопроса, и второй решает человек.
    print("     --- что теперь написано на сомнительных карточках ---")
    local shown = 0
    for _, card in ipairs(run("POWER")) do
        if card.doubtLevel and shown < 3 then
            shown = shown + 1
            print("     " .. tostring(card.title) .. "  |  " .. tostring(card.benefit))
            print("        " .. ns.Util.truncate(tostring(card.why), 300))
        end
    end
    if shown == 0 then print("     (сомнительных карточек в профиле «Сила» нет)") end
    H.eq(#stray, 0, "ни одна находка не осталась только в файле"
        .. ((#stray > 0) and ("  <- " .. table.concat(stray, "; ")) or ""))
    H.eq(#refuting, 0, "ни одна карточка не отрицает себя первой фразой"
        .. ((#refuting > 0) and ("  <- " .. table.concat(refuting, "; ")) or ""))
    H.eq(#doubtOnTop, 0, "сомнительное число не стоит первым или вторым советом"
        .. ((#doubtOnTop > 0) and ("  <- " .. table.concat(doubtOnTop, "; ")) or ""))

    -- И маршрут не терял находок: ключ, которого в списке нет, - это дефект.
    local m = ns.Diag:Init().modules.sanityChecks
    H.ok(m ~= nil, "проход самопроверок отчитался")
    if m then
        H.eq(m.lostDoubts, 0, "ни одна находка не назвала ключ, которого в списке нет")
        H.eq(m.failed, 0, "и ни одна проверка не упала")
    end
    run("POWER")
end

-- КРЮЧОК ДЛЯ РУЧНОГО ОСМОТРА. Полный текст карточек перепродажи нужен человеку
-- глазами: зелёный набор и осмысленный совет - два разных вопроса. В обычном
-- прогоне не делает ничего.
if _G.FP_DUMP_ARBITRAGE then
    local out = {}
    for _, c in ipairs(run("POWER")) do
        if c.kind == ns.KIND.ARBITRAGE then out[#out + 1] = c end
    end
    _G.FP_ARB_CARDS = out
end


end
