-- ForeverPilot / Tests/dump_wanted.lua
--
-- Не тест: распечатать СПИСОК ЗАКАЗА ДАННЫХ, собранный на настоящих
-- SavedVariables игрока. Нужно затем, чтобы по нему можно было идти добывать
-- данные - и чтобы видеть, что раздел не пустой и не бессмысленный.
--
--   FP_ADDONS=<...>/AddOns texluajit Tests/dump_wanted.lua

local here = debug.getinfo(1, "S").source:sub(2)
local dir = here:match("^(.*)[/\\]dump_wanted%.lua$") or "."
local H = assert(loadfile(dir .. "/harness.lua"))()

-- Где живые SavedVariables - спрашивается в Tests/paths.lua, и только там.
-- Здесь этого пути нет: он зависит от машины и содержит имя папки аккаунта.
local P = assert(loadfile(dir .. "/paths.lua"))()
local WTF, pathInfo = P.savedVariables(H.ROOT)
if not WTF then
    print("!! " .. pathInfo.reason)
    os.exit(1)
end

local function loadSV(name)
    local chunk = loadfile(WTF .. "/" .. name)
    if not chunk then return nil end
    local env = {}
    setfenv(chunk, setmetatable(env, { __index = function() return nil end }))
    if not pcall(chunk) then return nil end
    return env
end

local mc = assert(loadSV("Mastercraft.lua"), "Mastercraft.lua не читается")
local db = assert(mc.MastercraftDB)

local GUID, charInfo
for guid, info in pairs(db.chars or {}) do
    local n = #(info.professions or {})
    if (not charInfo) or n > #(charInfo.professions or {}) then
        GUID, charInfo = guid, info
    end
end

local env = H.load({ serverTime = charInfo.updated or 1794800000 })
local ns = env.ns
env.player.name = charInfo.name
env.player.level = charInfo.level
env.player.classFile = charInfo.classFile
env.player.className = charInfo.class
env.player.raceName = charInfo.race
env.player.factionFile = charInfo.faction
env.player.guid = GUID
env.player.realm = charInfo.realm
env.money = charInfo.money or 0
for _, prof in ipairs(charInfo.professions or {}) do
    env.professions[#env.professions + 1] = {
        name = prof.name, skill = prof.skill, max = prof.max,
        maxKnown = (tonumber(prof.max) or 0) > 0, skillTrusted = true,
    }
end
env.foreignDB = db
H.installRealItemDB(env)

-- Цены и предметы из настоящих данных.
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
if realm and db.prices and db.prices[realm] and db.prices[realm].versions then
    for itemID, versions in pairs(db.prices[realm].versions) do
        local cheapest
        for _, v in pairs(versions) do
            local p = tonumber(v.p)
            if p and p > 0 and ((not cheapest) or p < cheapest) then cheapest = p end
        end
        if cheapest then observed[itemID] = observed[itemID] or cheapest end
    end
end
env.prices = observed
env.observedPrices = observed
env.foreignVendorPrices = db.vendorPrices or {}

local function ensureItem(itemID, name, equipLoc)
    if not itemID or env.items[itemID] then return end
    env.items[itemID] = {
        name = name, equipLoc = equipLoc,
        classID = equipLoc and 4 or nil, subclassID = equipLoc and 1 or nil,
        sellPrice = observed[itemID] and math.floor(observed[itemID] / 5) or 0,
        quality = 1,
    }
end
local CATEGORY_EQUIPLOC = {
    ["Капюшоны"] = "INVTYPE_HEAD", ["Наплечья"] = "INVTYPE_SHOULDER",
    ["Наручи"] = "INVTYPE_WRIST", ["Обувь"] = "INVTYPE_FEET",
    ["Одеяния и жилеты"] = "INVTYPE_CHEST", ["Перчатки"] = "INVTYPE_HAND",
    ["Плащи"] = "INVTYPE_CLOAK", ["Поножи"] = "INVTYPE_LEGS",
    ["Пояса"] = "INVTYPE_WAIST",
}
for profName, bucket in pairs((db.recipes or {})[GUID] or {}) do
    local list = {}
    for _, r in pairs(bucket.list or {}) do
        list[#list + 1] = {
            id = r.id, name = r.name, learned = r.learned, output = r.output,
            outputQty = r.outputQty, reagents = r.reagents, diff = r.diff,
            category = r.category, categoryID = r.category, icon = r.icon,
        }
        ensureItem(r.output, r.name, CATEGORY_EQUIPLOC[r.category or ""])
        for _, g in ipairs(r.reagents or {}) do ensureItem(g.itemID) end
    end
    ns.RecipeBook:Store(profName, list, "stored", ns.CONF.CACHED, H.serverTime)
end
ns.RecipeBook:Reindex()

-- Инвентарь из Syndicator.
local syn = loadSV("Syndicator.lua")
local data = syn and syn.SYNDICATOR_DATA
if data and data.Characters then
    for _, ch in pairs(data.Characters) do
        if ch.details and ch.details.character == charInfo.name then
            for _, bag in ipairs(ch.bags or {}) do
                for _, slot in ipairs(bag or {}) do
                    if slot and slot.itemID then
                        ensureItem(slot.itemID)
                        env.bags[slot.itemID] = (env.bags[slot.itemID] or 0)
                            + (slot.itemCount or 1)
                        env.bagLinks[slot.itemID] = slot.itemLink
                    end
                end
            end
            for slotKey, inv in pairs(ns.SLOT_INVENTORY_ID or {}) do
                local e = ch.equipped and ch.equipped[inv]
                if e and e.itemID then
                    ensureItem(e.itemID)
                    env.equipped[slotKey] = { itemID = e.itemID, link = e.itemLink }
                end
            end
        end
    end
end
H.itemsChanged(env)
H.build(env)
ns.Diag:Trim()

-- Печать -----------------------------------------------------------------

local s = ns.Diag:Init()
print("ForeverPilot — список заказа данных на настоящих данных")
print(("="):rep(78))
print(charInfo.name .. ", " .. tostring(charInfo.level) .. " ур., золото "
    .. ns.Util.money(env.money))
print("")

local order = {}
for kind in pairs(ns.Diag.WANT) do order[#order + 1] = kind end
table.sort(order)

for _, kind in ipairs(order) do
    local b = (s.wanted or {})[kind]
    if b and b.total > 0 then
        print(string.format("%-20s всего %d, сохранено %d, попаданий %d%s",
            kind, b.total, b.kept, b.hits, b.truncated and " (УРЕЗАН)" or ""))
        print("                     " .. (ns.Diag.WANT_LABEL[kind] or ""))
        -- Самые частые сначала.
        local list = {}
        for _, e in pairs(b.items) do list[#list + 1] = e end
        table.sort(list, function(a, c)
            if a.n ~= c.n then return a.n > c.n end
            return tostring(a.id) < tostring(c.id)
        end)
        for i = 1, math.min(8, #list) do
            local e = list[i]
            local places = {}
            for w, n in pairs(e.where or {}) do places[#places + 1] = w .. "×" .. n end
            table.sort(places)
            local extra = {}
            for k, v in pairs(e) do
                if k ~= "id" and k ~= "n" and k ~= "where" then
                    extra[#extra + 1] = k .. "=" .. tostring(v)
                end
            end
            table.sort(extra)
            print(string.format("   %-10s n=%-3d [%s] %s",
                tostring(e.id), e.n, table.concat(places, ","),
                ns.Util.truncate(table.concat(extra, " "), 70)))
        end
        if #list > 8 then print("   …и ещё " .. (#list - 8)) end
        print("")
    end
end

print(("-"):rep(78))
local t = ns.Diag:WantedTotals()
print("итоги: " .. (ns.Diag:WantedLine() or "всего хватило"))
print(string.format("предметы %d / цены %d / торговцы %d / всего %d",
    t.itemsTotal or 0, t.pricesTotal or 0, t.npcsTotal or 0, t.grandTotal or 0))
print(("-"):rep(78))

-- ПРЕДСКАЗАТЕЛЬНЫЙ ЗАКАЗ ------------------------------------------------
print("")
print("ПРЕДСКАЗАТЕЛЬНЫЙ ЗАКАЗ (wantedAhead)")
print(("="):rep(78))
local ahead = ns.Foresight:Collect(ns.CharacterScanner:Get(), 1000)
print(string.format("от уровня %d, полоса %d..%d, школа %s",
    ahead.forLevel, ahead.levelBand.from or 0, ahead.levelBand.to or 0,
    tostring(ahead.schoolStat)))
for _, s in ipairs(ahead.skills) do
    print(string.format("   навык %-18s %s/%s → горизонт %d%s",
        tostring(s.name), tostring(s.skill), tostring(s.max), s.aheadTo,
        s.atCeiling and "  (упёрт в потолок)" or ""))
end
print("")
for _, group in ipairs({ "reagents", "recipes", "gear", "enchants", "trainers", "zones" }) do
    local g = ahead[group]
    if g then
        print(string.format("%-10s всего %-5d сохранено %-4d  %s",
            group, g.total, g.kept, ns.Util.truncate(g.source, 44)))
        for i = 1, math.min(6, #g.items) do
            local e = g.items[i]
            local bits = {}
            for k, v in pairs(e) do
                if type(v) ~= "table" then bits[#bits + 1] = k .. "=" .. tostring(v) end
            end
            table.sort(bits)
            print("     " .. ns.Util.truncate(table.concat(bits, " "), 100))
        end
    end
end
print("")
print("пометки:")
for _, n in ipairs(ahead.notes or {}) do
    print("   — " .. ns.Util.truncate(n, 100))
end
print(("-"):rep(78))
local tracked = ns.ActionEngine:TrackedItems()
local n = 0
for _ in pairs(tracked) do n = n + 1 end
print("предметов в суточном слепке цен: " .. n
    .. " (из них добавил горизонт: "
    .. tostring((ns.Diag:Init().modules.priceSnapshotScope or {}).aheadOnly) .. ")")
print(("-"):rep(78))
