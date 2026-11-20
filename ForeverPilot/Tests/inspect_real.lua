-- ForeverPilot / Tests/inspect_real.lua
--
-- Not a test: a readable dump of what the engine says about the player's actual
-- character, built from their real SavedVariables. This is the thing to look at
-- after a change, because a green suite and sensible advice are two different
-- questions and only a human can answer the second one.
--
-- Run with:  FP_WTF=<...>/SavedVariables texluajit Tests/inspect_real.lua
--            FP_ACCOUNT=<аккаунт> texluajit Tests/inspect_real.lua
--            texluajit Tests/inspect_real.lua   (путь из Tests/local_paths.lua)

local here = debug.getinfo(1, "S").source:sub(2)
local dir = here:match("^(.*)[/\\]inspect_real%.lua$") or "."
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
    local ok = pcall(chunk)
    if not ok then return nil end
    return env
end

-- The real foreign item database -----------------------------------------
--
-- In game the addon calls Polestar.ItemDB.Get(itemID) and Polestar does the
-- parsing. Offline there is no Polestar, so this reads its two generated data
-- files and parses the compact entry format the module documents in its own
-- header:
--   "<inv> <ilvl> <req> <quality> <classID> <subclassID> [<stat><n> ...]"
-- This parser is test scaffolding only; nothing in the addon does it.
local function loadItemDB()
    -- The addon folder is normally the parent of this one; FP_ADDONS overrides
    -- it, which is what the sandbox needs when ForeverPilot is mounted on its
    -- own rather than inside Interface/AddOns.
    local bases = {}
    if os.getenv("FP_ADDONS") then
        bases[#bases + 1] = os.getenv("FP_ADDONS") .. "/Polestar_ItemDB/"
    end
    bases[#bases + 1] = H.ROOT .. "/../Polestar_ItemDB/"
    bases[#bases + 1] = H.ROOT .. "/../../AddOns/Polestar_ItemDB/"
    local base
    for _, dir in ipairs(bases) do
        local probe = io.open(dir .. "Items.lua", "r")
        if probe then probe:close(); base = dir; break end
    end
    if not base then return nil end
    local raw, names = {}, {}
    local stub = {
        Register = function(_, items)
            if type(items) ~= "table" then return end
            for id, s in pairs(items) do raw[id] = s end
        end,
        RegisterLeveling = function(_, data)
            if type(data) == "table" and type(data.names) == "table" then
                for id, n in pairs(data.names) do names[id] = n end
            end
        end,
    }
    local ok = false
    for _, file in ipairs({ "Items.lua", "Forever.lua" }) do
        local chunk = loadfile(base .. file)
        if chunk then
            local env = setmetatable({ Polestar = { ItemDB = stub } },
                { __index = function(_, k) return _G[k] end })
            setfenv(chunk, env)
            if pcall(chunk) then ok = true end
        end
    end
    if not ok then return nil, nil end

    local UNTOKEN = { mpr = "mp5", hpr = "hp5" }
    local SKIP = { dmin = true, dmax = true, speed = true, cls = true, uniq = true }
    local cache = {}
    local function get(id)
        if cache[id] ~= nil then return cache[id] or nil end
        local s = raw[id]
        if type(s) ~= "string" then cache[id] = false; return nil end
        local inv, ilvl, req, quality, class, sub =
            s:match("^(%d+) (%d+) (%d+) (%d+) (%d+) (%d+)")
        if not inv then cache[id] = false; return nil end
        local stats = {}
        for key, n in s:gmatch("(%a+)(%-?%d+)") do
            if not SKIP[key] then stats[UNTOKEN[key] or key] = tonumber(n) end
        end
        local rec = {
            id = id, inv = tonumber(inv), ilvl = tonumber(ilvl),
            req = tonumber(req), quality = tonumber(quality),
            class = tonumber(class), subclass = tonumber(sub), stats = stats,
        }
        cache[id] = rec
        return rec
    end
    local n = 0
    for _ in pairs(raw) do n = n + 1 end
    return { get = get, count = n, names = names }
end

local mc = loadSV("Mastercraft.lua")
local syn = loadSV("Syndicator.lua")
local fp = loadSV("ForeverPilot.lua")
local au = loadSV("Auctionator.lua")

-- КЕШ ЦЕН ТОРГОВЦЕВ AUCTIONATOR - ЕДИНСТВЕННЫЕ ЧЕСТНЫЕ ПОТОЛКИ В ФАЙЛАХ ИГРОКА.
--
-- В игре их отдаёт Auctionator.API.v1.GetVendorPriceByItemID, то есть
-- Api:VendorPrice, то есть env.vendorPrices в стенде. Офлайн таблица читается
-- прямо из его SavedVariables: AUCTIONATOR_VENDOR_PRICE_CACHE, ключи - строки.
-- Его собственный код (Source/CraftingInfo/Main.lua) пишет туда запись ТОЛЬКО
-- при numAvailable == -1 и делит цену окна на размер стопки - то есть это
-- именно цены с неограниченной полки, а не «сколько торговец даёт».
--
-- Без этого чтения стенд на настоящих данных не видел ни одного потолка: цена
-- материала приходила только с аукциона, и правило min(аукцион, торговец)
-- проверять было нечем. База цен аукциона у Auctionator лежит рядом сжатым
-- блобом (CBOR) и офлайн не читается - её роль по-прежнему играют наблюдения
-- Mastercraft.
local function vendorCeilings(sv)
    local out, n = {}, 0
    for key, value in pairs((sv and sv.AUCTIONATOR_VENDOR_PRICE_CACHE) or {}) do
        local id, copper = tonumber(key), tonumber(value)
        if id and copper and copper > 0 then out[id] = copper; n = n + 1 end
    end
    return out, n
end
if not (mc and mc.MastercraftDB) then
    print("!! не нашёл Mastercraft.lua в " .. tostring(WTF))
    os.exit(1)
end
local db = mc.MastercraftDB

-- КАКИМ ПЕРСОНАЖЕМ СМОТРЕТЬ.
--
-- По умолчанию берётся тот, у кого профессий больше - то есть маг. Это и было
-- проблемой: аддон смотрели ТОЛЬКО на маге-портняжнике, и ровно поэтому
-- предположения про мага никто не ловил. У игрока два персонажа, и второй -
-- чернокнижник с алхимией, инженерным делом и кулинарией.
--
--   FP_CHAR=Белыйй texluajit Tests/inspect_real.lua
--
-- Сравнение по вхождению и без учёта регистра: подойдёт и фамилия, и полное
-- имя, и код класса.
local WANT_CHAR = os.getenv("FP_CHAR")
local GUID, charInfo
if WANT_CHAR and WANT_CHAR ~= "" then
    local want = ns and ns.Util and ns.Util.lower(WANT_CHAR) or WANT_CHAR:lower()
    for guid, info in pairs(db.chars or {}) do
        local hay = table.concat({ tostring(info.name), tostring(info.surname),
            tostring(info.classFile), tostring(info.class) }, " "):lower()
        if hay:find(want, 1, true) then GUID, charInfo = guid, info; break end
    end
    if not charInfo then
        print("!! персонаж по FP_CHAR=" .. tostring(WANT_CHAR) .. " не найден")
        os.exit(1)
    end
end
if not charInfo then
    for guid, info in pairs(db.chars or {}) do
        local n = #(info.professions or {})
        if (not charInfo) or n > #(charInfo.professions or {}) then
            GUID, charInfo = guid, info
        end
    end
end
print("персонаж: " .. tostring(charInfo.name) .. " " .. tostring(charInfo.surname)
    .. ", " .. tostring(charInfo.level) .. " ур., " .. tostring(charInfo.class)
    .. " (" .. tostring(charInfo.classFile) .. ")")

-- ПОРОГ МЕЛКОЙ ДЕНЕЖНОЙ ВЫГОДЫ - КАК В ИГРЕ, А НЕ КАК В ФИКСТУРАХ.
--
-- H.load по умолчанию снимает порог: в выдуманных мирах деньги игрушечные, и
-- рабочий порог срезал бы там механику (см. H.setMoneyFloor в
-- Tests/harness.lua). Но этот скрипт - не фикстура: он показывает человеку
-- ровно тот список, который увидит игрок. Показывать здесь другой список
-- значило бы смотреть не на тот аддон, который работает в игре.
local env = H.load({ serverTime = (charInfo and charInfo.updated) or 1794800000,
                     moneyFloor = "default" })
local ns = env.ns

-- The real item database, wired in where the game would call Polestar.
local itemDB = loadItemDB()
env.itemDBMirror = false
env.foreignItemStats = setmetatable({}, { __index = function(_, itemID)
    if not itemDB then return nil end
    local rec = itemDB.get(itemID)
    return rec and rec.stats or nil
end })
-- И ЗАПИСЬ ЦЕЛИКОМ, А НЕ ТОЛЬКО ХАРАКТЕРИСТИКИ.
--
-- Здесь отдавались только stats, и из-за этого числовой тип предмета (inv) до
-- аддона не доходил. На настоящих данных это выглядело так: «Лунная винтовка»
-- (4383, inv = 26, дальний бой) попадала в советы с пометкой «это расходник» -
-- потому что клиент в этом стенде про неё молчит, а второй путь определения
-- (внешняя база) был не подключён. В игре запись приходит целиком: Polestar
-- отдаёт одну таблицу с inv, class, subclass и stats.
env.foreignItemRecords = setmetatable({}, { __index = function(_, itemID)
    if not itemDB then return nil end
    return itemDB.get(itemID)
end })
print(itemDB and ("внешняя база предметов: " .. itemDB.count .. " записей")
    or "!! внешняя база предметов не найдена — школьные характеристики читать нечем")

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
env.foreignDB = db

for _, prof in ipairs(charInfo.professions or {}) do
    env.professions[#env.professions + 1] = {
        name = prof.name, skill = prof.skill, max = prof.max,
        maxKnown = (tonumber(prof.max) or 0) > 0, skillTrusted = true,
    }
end

-- Real observed auction prices.
local realm = next(db.costs or {})
local observed, scanNames = {}, {}
if realm and db.prices and db.prices[realm] and db.prices[realm].items then
    for itemID, e in pairs(db.prices[realm].items) do
        local p = tonumber(e.p)
        if p and p > 0 then observed[itemID] = p end
    end
end
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
env.prices = observed
env.auctionator = true
-- FP_NO_CEILING=1 - ТОТ ЖЕ СПИСОК БЕЗ ВЕНДОРНЫХ ПОТОЛКОВ.
--
-- Это не настройка аддона, а ручка осмотра: ровно так стенд вёл себя до того,
-- как научился читать кеш цен торговцев, и ровно так его видели прошлые
-- сессии. Нужна она для одного - сравнить «было» и «стало» на ОДНИХ И ТЕХ ЖЕ
-- настоящих данных, а не на честном слове.
local ceilings, ceilingCount = vendorCeilings(au)
if os.getenv("FP_NO_CEILING") then
    ceilings, ceilingCount = {}, 0
    print("ВЕНДОРНЫЕ ПОТОЛКИ ОТКЛЮЧЕНЫ (FP_NO_CEILING) — это состояние «было»")
end
env.vendorPrices = ceilings
print("вендорных потолков из кеша Auctionator: " .. ceilingCount)

-- The player's own daily price snapshots, which is what the history analysis
-- reads. Copied into the config exactly as the game stores them.
if fp and fp.ForeverPilotDB then
    local cfg = ns.Config:Get()
    cfg.priceHistory = fp.ForeverPilotDB.priceHistory or {}
    cfg.priceHistoryMeta = fp.ForeverPilotDB.priceHistoryMeta or cfg.priceHistoryMeta
    cfg.vendorPrices = fp.ForeverPilotDB.vendorPrices or {}
    cfg.places = fp.ForeverPilotDB.places or cfg.places
    -- И СВОЙ РЕЕСТР ПЕРСОНАЖЕЙ - ТОТ ЖЕ, ЧТО В ИГРЕ.
    --
    -- В игре он приезжает из этой же сохранёнки (Logic/Roster.lua, cfg.chars), и
    -- в нём лежит единственное место, где у аддона есть профессии ВТОРОГО
    -- персонажа с русскими именами и точным навыком. Без него осмотр отвечал
    -- про второго персонажа из чужого кеша (английские имена) или не отвечал
    -- вовсе - то есть показывал не тот мир, который видит игрок. Ветки, которые
    -- считают по обоим персонажам (лагерь, «между персонажами»), на этом и
    -- расходились со игрой.
    cfg.chars = fp.ForeverPilotDB.chars or cfg.chars
end

local CATEGORY_EQUIPLOC = {
    ["Капюшоны"] = "INVTYPE_HEAD", ["Наплечья"] = "INVTYPE_SHOULDER",
    ["Наручи"] = "INVTYPE_WRIST", ["Обувь"] = "INVTYPE_FEET",
    ["Одеяния и жилеты"] = "INVTYPE_CHEST", ["Перчатки"] = "INVTYPE_HAND",
    ["Плащи"] = "INVTYPE_CLOAK", ["Поножи"] = "INVTYPE_LEGS",
    ["Пояса"] = "INVTYPE_WAIST", ["Рубашки"] = "INVTYPE_BODY",
    ["Сумки"] = "INVTYPE_BAG", ["Особые сумки"] = "INVTYPE_BAG",
}

-- ТИП ПРЕДМЕТА БЕРЁТСЯ ИЗ БАЗЫ, А НЕ ИЗ НАЗВАНИЯ КАТЕГОРИИ РЕЦЕПТА.
--
-- Таблица выше - это категории ПОРТНЯЖНОГО ДЕЛА, и больше ничьи. На маге она
-- работала, а на чернокнижнике-инженере весь гардероб уезжал в «не
-- экипировка»: категории инженерных рецептов («Очки», «Бомбы») в ней нет, и
-- стенд отдавал аддону предмет без equipLoc. Из-за этого ветка экипировки
-- молчала - воронка писала «not-equipment 75 из 75» - и ни одного совета
-- «скрафтить и надеть» на настоящих данных нельзя было увидеть вовсе. То есть
-- именно та карточка, на которую жалуется игрок, в стенде не рождалась.
--
-- В игре этого вопроса нет: equipLoc отдаёт клиент. Здесь клиента нет, зато
-- есть установленная база Polestar_ItemDB с числовым типом (inv), и перевод
-- числа в INVTYPE - ровно то, что делает ns.SlotMap. Карта ниже - обратная к
-- SlotMap.INVTYPE: числа те же, что в SlotMap.INV_NUMBER.
local INV_EQUIPLOC = {
    [1] = "INVTYPE_HEAD", [2] = "INVTYPE_NECK", [3] = "INVTYPE_SHOULDER",
    [4] = "INVTYPE_BODY", [5] = "INVTYPE_CHEST", [6] = "INVTYPE_WAIST",
    [7] = "INVTYPE_LEGS", [8] = "INVTYPE_FEET", [9] = "INVTYPE_WRIST",
    [10] = "INVTYPE_HAND", [11] = "INVTYPE_FINGER", [12] = "INVTYPE_TRINKET",
    [13] = "INVTYPE_WEAPON", [14] = "INVTYPE_SHIELD", [15] = "INVTYPE_RANGED",
    [16] = "INVTYPE_CLOAK", [17] = "INVTYPE_2HWEAPON", [18] = "INVTYPE_BAG",
    [19] = "INVTYPE_TABARD", [20] = "INVTYPE_ROBE",
    [21] = "INVTYPE_WEAPONMAINHAND", [22] = "INVTYPE_WEAPONOFFHAND",
    [23] = "INVTYPE_HOLDABLE", [25] = "INVTYPE_THROWN",
    [26] = "INVTYPE_RANGEDRIGHT", [28] = "INVTYPE_RELIC",
}

local function dbEquipLoc(itemID)
    if not itemDB then return nil end
    local rec = itemDB.get(itemID)
    if not rec then return nil end
    return INV_EQUIPLOC[rec.inv or -1], rec
end

-- ИМЯ ПРЕДМЕТА, КОТОРОЕ В ИГРЕ ЗНАЕТ КЛИЕНТ.
--
-- В игре клиент называет всё, что он кешировал, - в том числе реагенты, по
-- которым у игрока нет рецепта («Простое дерево», «Пустой флакон»). Офлайн
-- клиента нет, и до этой строки в осмотре стояло «Материалы: 84м — Предмет
-- #6291, Предмет #3371»: цена есть, а что покупать - не сказано. Имена берутся
-- оттуда же, откуда их берёт игра, когда клиент молчит: из установленного
-- пакета имён (см. H.loadInstalledCodex, ruName). Подставляется ПОСЛЕДНИМ - за
-- именем из рецепта и за именем из сканов аукциона.
-- Пакет имён грузится ЗДЕСЬ, а не вместе с Codex ниже: имена нужны уже при
-- разборе рецептов, то есть раньше. Загрузка запомнена (H.loadInstalledCodex
-- отдаёт один и тот же разбор), так что второй раз файлы не читаются.
local function clientName(itemID)
    local codex = H.loadInstalledCodex()
    if type(codex) ~= "table" or type(codex.ruName) ~= "function" then return nil end
    return codex.ruName(itemID)
end

local function ensureItem(itemID, name, equipLoc)
    if not itemID then return end
    local fromDB, rec = dbEquipLoc(itemID)
    equipLoc = equipLoc or fromDB
    local existing = env.items[itemID]
    if existing then
        existing.name = existing.name or name
        existing.equipLoc = existing.equipLoc or equipLoc
        return
    end
    env.items[itemID] = {
        name = name or scanNames[itemID] or clientName(itemID)
            or ("Предмет #" .. itemID),
        equipLoc = equipLoc,
        -- Класс и подкласс - из базы, когда она про предмет знает: по ним
        -- аддон отличает инструмент профессии от оружия.
        classID = (rec and rec.class) or (equipLoc and 4 or nil),
        subclassID = (rec and rec.subclass) or (equipLoc and 1 or nil),
        reqLevel = rec and rec.req or nil,
        sellPrice = observed[itemID] and math.floor(observed[itemID] / 5) or 0,
        quality = (rec and rec.quality) or 1,
    }
end

-- The real recipe book: the player's own per-character cache (Russian profession
-- names) AND the foreign one (English), which is the pair that used to produce
-- every card twice.
local charSV
do
    -- ПАПКА ТОГО ПЕРСОНАЖА, КОТОРОГО СМОТРИМ. Раньше брался первый найденный
    -- файл, то есть всегда маг - даже когда остальной стенд был настроен на
    -- чернокнижника. Получался персонаж с классом чернокнижника и рецептами
    -- портняжки: ни одного настоящего состояния игры.
    --
    -- Первой пробуется папка как раз смотримого персонажа, дальше - список из
    -- Tests/local_paths.lua. Ни имён персонажей, ни номера реалма здесь нет:
    -- и то и другое - личные данные, и живут они в одном непубликуемом файле
    -- (см. Tests/paths.lua).
    local preferred
    if charInfo and charInfo.name and charInfo.surname then
        preferred = charInfo.name .. "-" .. charInfo.surname
    end
    for _, cand in ipairs(P.characterFiles(pathInfo, preferred)) do
        local chunk = loadfile(cand.path)
        if chunk then
            local e = {}
            setfenv(chunk, setmetatable(e, { __index = function() return nil end }))
            if pcall(chunk) and e.ForeverPilotCharDB then
                charSV = e.ForeverPilotCharDB
                print("рецепты из папки: " .. cand.folder)
                break
            end
        end
    end
end

local function ingest(cache, source)
    local n = 0
    for profName, bucket in pairs(cache or {}) do
        if type(bucket) == "table" and type(bucket.list) == "table" then
            local list = {}
            for _, r in pairs(bucket.list) do
                list[#list + 1] = {
                    id = r.id, name = r.name, learned = r.learned,
                    output = r.output, outputQty = r.outputQty,
                    reagents = r.reagents, diff = r.diff,
                    category = r.category or r.categoryName,
                    group = r.group or r.groupName,
                    categoryID = r.categoryID or r.category,
                    icon = r.icon,
                }
                local equipLoc = CATEGORY_EQUIPLOC[(r.category or r.categoryName) or ""]
                ensureItem(r.output, r.name, equipLoc)
                for _, g in ipairs(r.reagents or {}) do ensureItem(g.itemID) end
            end
            n = n + ns.RecipeBook:Store(profName, list, source, ns.CONF.CACHED,
                bucket.scanned or 0)
        end
    end
    return n
end

ingest(charSV and charSV.recipes, "stored")
ingest(db.recipes and db.recipes[GUID], "foreign")
ns.RecipeBook:Reindex()

-- Real bags and equipment.
local synChar
if syn and syn.SYNDICATOR_DATA then
    local best, bestScore = nil, -1
    for name, data in pairs(syn.SYNDICATOR_DATA.Characters or {}) do
        local details = data.details or {}
        local score = ((details.className == charInfo.classFile) and 10000 or 0)
        if score > bestScore then best, bestScore = data, score end
    end
    synChar = best
end
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
if synChar then
    for _, bag in pairs(synChar.bags or {}) do
        for _, slot in pairs(bag) do
            if type(slot) == "table" and slot.itemID then
                env.bags[slot.itemID] = (env.bags[slot.itemID] or 0) + (slot.itemCount or 1)
                ensureItem(slot.itemID, slot.itemLink
                    and ns.Util.itemNameFromLink(slot.itemLink) or nil)
                if env.items[slot.itemID] then
                    env.items[slot.itemID].quality = slot.quality or 1
                end
                -- ПРИВЯЗАНА ЛИ ИМЕННО ЭТА ВЕЩЬ. В игре это поле ответа клиента
                -- по ячейке (Api:BagCounts), здесь - то же поле из сохранёнки
                -- Syndicator: он пишет его по каждой ячейке и берёт из того же
                -- ответа. Без него проверка облика на настоящих данных не
                -- различала бы надетую зелёнку и купленную.
                if slot.isBound == false then
                    env.bagBound[slot.itemID] = false
                elseif env.bagBound[slot.itemID] == nil and slot.isBound ~= nil then
                    env.bagBound[slot.itemID] = slot.isBound and true or false
                end
            end
        end
    end
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
                ensureItem(item.itemID, item.itemLink
                    and ns.Util.itemNameFromLink(item.itemLink) or nil)
            end
        end
    end
    env.money = tonumber(synChar.money) or env.money
end

-- Alt characters, as Syndicator reports them.
env.syndicator = true
env.altNames, env.altData = {}, {}
if syn and syn.SYNDICATOR_DATA then
    for name, data in pairs(syn.SYNDICATOR_DATA.Characters or {}) do
        env.altNames[#env.altNames + 1] = name
        env.altData[name] = data
    end
    table.sort(env.altNames)
end

-- УСТАНОВЛЕННЫЙ Codex: без него ветка перепродажи здесь молчит, а в игре
-- говорит - и именно это расхождение дало шесть неверных карточек.
local realCodex = H.installRealCodex(env)
print(realCodex
    and ("Codex: " .. realCodex.itemCount .. " предметов, "
         .. realCodex.npcCount .. " NPC")
    or "!! Polestar_Codex не найден — ветка перепродажи будет молчать")

-- ПРЕДМЕТЫ ЛАГЕРЯ, ИХ ЧЕРТЕЖИ И РЕАГЕНТЫ - В КЕШ ПРЕДМЕТОВ.
--
-- Это не выдумка мира, а то, что в игре делает клиент: предметы лагеря лежат в
-- окне профессии рецептами, их реагенты - на аукционе, и имена всего этого
-- клиент знает. В стенде кеш предметов заполняется только из рецептов игрока и
-- его сумок, поэтому реагенты лагеря оставались без имён и строка «Материалы»
-- в осмотре читалась как «Предмет #6291» - то есть осмотр показывал не тот
-- текст, который увидит человек. Имена берутся из пакета имён (clientName), и
-- если его нет - запись не появляется вовсе, как и в игре.
if ns.CampData then
    local added = 0
    local function campItem(id)
        if not id or env.items[id] then return end
        if not clientName(id) then return end
        ensureItem(id)
        added = added + 1
    end
    for _, row in ipairs(ns.CampData.OBJECTS) do
        campItem(row.item)
        campItem(row.bp)
        for _, pair in ipairs(row.reag or {}) do campItem(pair[1]) end
    end
    print("предметы лагеря в кеше предметов: +" .. added)
end

-- Run -------------------------------------------------------------------

print(string.rep("=", 78))
print("ForeverPilot — что движок говорит о настоящем персонаже")
print(string.rep("=", 78))
print(string.format("%s %s, %d ур., %s. Золото: %s",
    tostring(charInfo.name), tostring(charInfo.surname or ""),
    charInfo.level or 0, tostring(charInfo.class),
    ns.Util.money(env.money, true)))

do
    local probe = ns.CharacterScanner:Scan()
    print(string.format("Профиль весов: %s (%s, источник: %s). Спек от клиента: %s",
        tostring(probe.weightSetKey),
        tostring(ns.StatWeights.SET_LABEL[probe.weightSetKey or ""]),
        tostring(probe.weightSource), tostring(probe.spec)))
    local school, _, detail = ns.StatWeights:InferSchoolFromGear(probe)
    local parts = {}
    for k, v in pairs((detail and detail.counts) or {}) do
        parts[#parts + 1] = k .. "=" .. v
    end
    table.sort(parts)
    print("Школа по надетым вещам: " .. tostring(school)
        .. "  (" .. table.concat(parts, ", ") .. ")")
end

local sum = ns.RecipeBook:Summary()
print("")
print("Книга рецептов (" .. #sum .. " профессий, выучено "
    .. ns.RecipeBook:LearnedCount() .. "):")
for _, s in ipairs(sum) do
    print(string.format("   %-22s %4d всего, %4d выучено   [%s]",
        s.name, s.total, s.learned, s.source))
end

local profiles = os.getenv("FP_PROFILES")
local want = {}
if profiles then
    for p in profiles:gmatch("[^,]+") do want[#want + 1] = p end
else
    want = ns.PROFILE_ORDER
end

for _, profile in ipairs(want) do
    ns.Config:SetProfile(profile)
    local cards, meta = H.build(env)
    print("")
    print(string.rep("-", 78))
    print("ПРОФИЛЬ: " .. (ns.PROFILE_LABEL[profile] or profile)
        .. "   (" .. #cards .. " карточек)")
    print(string.rep("-", 78))
    -- ШИРИНА СТРОКИ ОСМОТРА. По умолчанию 150 - столько влезает в терминал и
    -- примерно столько видно игроку. FP_WIDE=400 показывает строку целиком: без
    -- этого «было → стало» по длинным строкам сравнивать нечем, обе обрезаны в
    -- одном и том же месте и выглядят одинаково.
    local wide = tonumber(os.getenv("FP_WIDE")) or 150
    for i, c in ipairs(cards) do
        print(string.format("%2d. [%-22s] %-46s %s", i,
            ns.KIND_LABEL[c.kind] or c.kind,
            ns.Util.truncate(c.title, 46), tostring(c.benefit)))
        print("      почему: " .. ns.Util.truncate(c.why or "", wide))
        if c.need and c.need ~= "" then
            print("      нужно:  " .. ns.Util.truncate(c.need, wide))
        end
        print(string.format("      score %.4f  достоверность %s%s", c.score or 0,
            ns.CONF_LABEL[c.conf] or "?",
            c.revOrigin and ("  выручка из: " .. tostring(c.revOrigin.src)
                .. (c.revOrigin.cutApplied and " (сбор вычтен)" or " (сбора нет)")) or ""))
    end

    -- What every "craft to sell" card actually rests on. This is the table that
    -- answers "is this a real price or one listing".
    local profit = {}
    for _, c in ipairs(cards) do
        if c.kind == ns.KIND.CRAFT_PROFIT then profit[#profit + 1] = c end
    end
    if #profit > 0 then
        print("")
        print("   НА ЧЁМ ОСНОВАНА КАЖДАЯ КАРТОЧКА «НА ПРОДАЖУ»")
        print(string.format("   %-34s %-10s %-10s %-5s %-16s %-9s %s",
            "предмет", "живая", "взято", "дней", "вердикт", "торговец", "выручка/торговец"))
        for _, c in ipairs(profit) do
            local o = c.revOrigin or {}
            local v = o.verdict or {}
            local info = ns.Api:ItemInfo(c.itemID)
            local vendorPays = info and tonumber(info.sellPrice) or 0
            local ratio = (vendorPays > 0 and c.revenue) and (c.revenue / vendorPays) or nil
            print(string.format("   %-34s %-10s %-10s %-5s %-16s %-9s %s",
                ns.Util.truncate((info and info.name) or ("#" .. tostring(c.itemID)), 34),
                ns.Util.money(o.liveCopper),
                ns.Util.money(c.revenue),
                tostring(v.days or 0),
                tostring(v.flag or "?"),
                ns.Util.money(vendorPays),
                ratio and string.format("%.0fx", ratio) or "—"))
        end
    end

    -- Duplicate check, on real data.
    local byKey, byAction, dupKeys, dupActions = {}, {}, 0, 0
    for _, c in ipairs(cards) do
        if byKey[c.key] then dupKeys = dupKeys + 1 end
        byKey[c.key] = true
        if c.actionIdentity then
            if byAction[c.actionIdentity] then dupActions = dupActions + 1 end
            byAction[c.actionIdentity] = true
        end
    end
    print("")
    print(string.format("   дублей по ключу: %d, по действию: %d, схлопнуто движком: %d",
        dupKeys, dupActions, ns.ActionEngine.dupes or 0))
end

-- ОБЛИК ВЕЩИ НА НАСТОЯЩИХ ДАННЫХ -----------------------------------------
--
-- Сколько вещей игрока попадает под предупреждение, и чего при этом не хватает.
-- Настоящего ответа «собран ли облик» здесь нет и быть не может: его знает
-- только клиент. Поэтому считается две разные величины, и путать их нельзя:
--
--   УЯЗВИМЫЕ   - непривязанные оружие и доспехи необычного качества и выше,
--                то есть те вещи, на которых облик теряется. Это число игрок
--                увидит как число предупреждений в игре, если облик с них не
--                собран;
--   БЕЗОПАСНЫЕ - всё остальное, с разбивкой по причине.
do
    local AP = ns.Appearance
    local snap = ns.CharacterScanner:Get() or ns.CharacterScanner:Scan()
    local binding = AP:BagBinding(snap)
    local byState, vulnerable, total = {}, {}, 0
    local seen = {}
    local function look(itemID, where)
        itemID = tonumber(itemID)
        if not itemID or seen[itemID] then return end
        seen[itemID] = true
        total = total + 1
        local info = ns.Api:ItemInfo(itemID)
        local v = AP:Check({
            itemID = itemID,
            link = info and info.link or nil,
            bound = binding[itemID],
            bindType = info and info.bindType or nil,
        }, "sell", where)
        byState[v.state] = (byState[v.state] or 0) + 1
        if v.state == AP.STATE.UNKNOWN and not v.quiet then
            vulnerable[#vulnerable + 1] = {
                itemID = itemID,
                name = (info and info.name) or ("Предмет #" .. itemID),
                bound = binding[itemID],
                quality = info and info.quality or nil,
            }
        end
    end
    -- Карточки пересобираются здесь: тот список, что печатался выше, лежал в
    -- локальной переменной цикла по профилям, и смотреть надо на тот же мир.
    local cards = H.build(env)
    -- ЦЕНА ИМЕННО ПЕРЕСЧЁТА, А НЕ ЭТОГО ОСМОТРА. Счётчики снимаются сразу после
    -- сборки: обход предметов ниже задаёт свои вопросы, и смешивать их с
    -- вопросами пересчёта значило бы завысить цену работы вдвое.
    local askedInBuild = ns.Api.appearanceAsked or 0
    local readsInBuild = ns.Api.appearanceReads or 0
    local hitsInBuild = ns.Api.appearanceHits or 0
    for itemID in pairs(snap.bags or {}) do look(itemID, "bags") end
    for itemID in pairs(snap.bank or {}) do look(itemID, "bank") end
    for _, card in ipairs(cards or {}) do
        if card.itemID then look(card.itemID, "card") end
    end

    print("")
    print(string.rep("=", 78))
    print("ОБЛИК ВЕЩЕЙ: СКОЛЬКО ПОПАДАЕТ ПОД ПРЕДУПРЕЖДЕНИЕ")
    print(string.rep("=", 78))
    print(string.format("  предметов просмотрено: %d", total))
    local order = {}
    for state in pairs(byState) do order[#order + 1] = state end
    table.sort(order)
    for _, state in ipairs(order) do
        print(string.format("  %-10s %4d", state, byState[state]))
    end
    print(string.format("  под предупреждение попадает: %d", #vulnerable))
    for _, e in ipairs(vulnerable) do
        print(string.format("      %-34s качество %s, привязана: %s",
            ns.Util.truncate(e.name, 34), tostring(e.quality), tostring(e.bound)))
    end
    -- И что про облик сказали сами карточки.
    local said, asked = 0, 0
    for _, card in ipairs(cards or {}) do
        if type(card.looks) == "table" then
            asked = asked + 1
            if AP:Speaks(card.looks) then said = said + 1 end
        end
    end
    print(string.format("  советов расстаться с вещью: %d, из них предупреждают: %d",
        asked, said))
    print(string.format("  вопросов про облик за пересчёт: %d"
        .. " (обращений к клиенту %d, ответов из памяти %d)",
        askedInBuild, readsInBuild, hitsInBuild))
    print("  ПРО САМ ОБЛИК ЗДЕСЬ ОТВЕТА НЕТ: его знает только клиент, и в этом"
        .. " стенде его нет ни у кого.")
end

-- The diagnostics the player would send us.
local s = ns.Diag:Init()
print("")
print(string.rep("=", 78))
print("ТЕКСТОВАЯ СВОДКА (поле summary в SavedVariables)")
print(string.rep("=", 78))
for _, line in ipairs(s.summary or {}) do print("  " .. line) end

print("")
print("ВОРОНКИ ПОТЕРЬ (поле funnels)")
local fnames = {}
for name in pairs(s.funnels or {}) do fnames[#fnames + 1] = name end
table.sort(fnames)
for _, name in ipairs(fnames) do
    local f = s.funnels[name]
    print(string.format("  %s: вошло %d → вышло %d (отсеяно %d, необъяснённых %d)",
        name, f["in"] or 0, f.out or 0, f.dropped or 0, f.unaccounted or 0))
    for _, filter in ipairs(f.order or {}) do
        local e = f.drops[filter]
        print(string.format("      %-22s %5d   напр.: %s", filter, e.n,
            ns.Util.truncate(table.concat(e.examples, " | "), 90)))
    end
end

print("")
print("МОДУЛИ С НУЛЁМ (поле modules, с кодом причины)")
local mnames = {}
for name in pairs(s.modules or {}) do mnames[#mnames + 1] = name end
table.sort(mnames)
for _, name in ipairs(mnames) do
    local m = s.modules[name]
    if (tonumber(m.out) or 0) == 0 then
        print(string.format("  %-18s [%s] %s", name, tostring(m.reasonCode),
            ns.Util.truncate(tostring(m.reason), 70)))
    end
end

print("")
print("РЕШЕНИЯ ПО ЦЕНАМ (поле prices, первые 8)")
local pk = {}
for k in pairs(s.prices or {}) do pk[#pk + 1] = k end
table.sort(pk)
for i = 1, math.min(8, #pk) do
    local d = s.prices[pk[i]]
    local parts = {}
    for _, a in ipairs(d.asked or {}) do
        parts[#parts + 1] = tostring(a.src) .. "=" .. ns.Util.money(a.copper)
    end
    print(string.format("  %-14s %-34s → %s %s  (%s)",
        pk[i],
        (#parts > 0) and table.concat(parts, ", ") or "никто не ответил",
        tostring(d.chosenSrc), ns.Util.money(d.chosenCopper), tostring(d.why)))
end

print("")
print("ДУБЛИ (поле dedupe)")
local dd = s.dedupe or {}
print(string.format("  схлопнуто %d (по ключу %d, по действию %d), слияний книги %d",
    dd.collapsed or 0, dd.byKey or 0, dd.byAction or 0, dd.recipeBookMerges or 0))
for _, e in ipairs(dd.examples or {}) do
    print("      " .. tostring(e.reason) .. ": " .. tostring(e.title))
end

print("")
print("СТРАННОСТИ (" .. #s.suspicious .. ")")
for _, e in ipairs(s.suspicious) do
    print("  [" .. e.code .. "] " .. ns.Util.truncate(e.text, 110))
end
print("ОШИБКИ (" .. #s.errors .. ")")
for _, e in ipairs(s.errors) do
    print("  ! " .. e.where .. ": " .. ns.Util.truncate(e.message, 110))
end
ns.Diag:Trim()
print(string.format("размер сессии примерно %.0f КБ", (s.sizeEstimate or 0) / 1024))
print(string.format("пересчётов %d, средний %.2f мс, пик %.2f мс",
    s.perf.recomputes, s.perf.avgMs or 0, s.perf.peakMs or 0))

-- РАЗБОР ВЕТКИ ПЕРЕПРОДАЖИ: что отсеялось и почему ----------------------
--
-- Та самая ветка, которая в живом прогоне дала шесть неверных карточек.
-- Печатается по каждому товару Mister Graphed: цена из пакета, цена выкупа у
-- предмета, цена аукциона, наценка и вердикт.
do
    print("")
    print(string.rep("-", 78))
    print("ВЕТКА ПЕРЕПРОДАЖИ: товар Mister Graphed (263384) по одному")
    print(string.rep("-", 78))
    ns.Config:SetProfile("POWER")
    H.build(env)
    ns.PriceProvider:BeginPass()
    local ids = { 13468, 12363, 248819, 248820, 248822, 249274, 249391, 249399,
                  249424, 249425, 249426, 249427, 249428, 249429, 271871 }
    for _, id in ipairs(ids) do
        local info = ns.Api:ItemInfo(id)
        local ask, askConf, askSrc, proven, note, code = ns.VendorArbitrage:VendorAsk(id)
        local rev = ns.PriceProvider:Sell(id)
        local opp, why, detail = ns.VendorArbitrage:Evaluate(id)
        print(string.format("%7d %-26s выкуп %-9s прилавок %-10s аукцион %-10s %s",
            id, ns.Util.truncate(tostring(info and info.name or "?"), 24),
            info and info.sellPrice and ns.Util.money(info.sellPrice) or "?",
            ask and ns.Util.money(ask) or ("нет (" .. tostring(code or note or "?") .. ")"),
            rev and ns.Util.money(rev) or "нет",
            opp and string.format("наценка x%.1f  %s", opp.markup,
                opp.markupVerdict and opp.markupVerdict.code or "верю")
                or ("отсеян: " .. tostring(why))))
        if detail then print("          " .. ns.Util.truncate(tostring(detail), 150)) end
    end
    local conc = ns.VendorArbitrage.lastConcentration
    print("концентрация: " .. (conc and string.format(
        "%d из %d на %s (#%d)", conc.count, conc.total,
        tostring(conc.npcName), conc.npcID) or "нет"))
end

-- РАЗБОР ВЕТКИ ЛАГЕРЯ: все 38 предметов по одному ------------------------
--
-- Зачем это здесь. Решения ветки лагеря зависят от четырёх разных источников
-- сразу (профессии обоих персонажей, книга рецептов, цены, имена предметов), и
-- по списку советов не видно, ПОЧЕМУ предмет в него не попал: имени не
-- дождались, рецепт не выучен, навыка не хватает или профессии нет ни у кого.
-- Таблица отвечает на это по каждому предмету - ровно так же, как таблица
-- перепродажи выше отвечает про каждый товар торговца.
do
    print("")
    print(string.rep("-", 78))
    print("ВЕТКА ЛАГЕРЯ: все предметы по одному")
    print(string.rep("-", 78))
    ns.Config:SetProfile("POWER")
    H.build(env)
    ns.PriceProvider:BeginPass()
    local Camp = ns.CampAdvisor
    local snap = ns.CharacterScanner:Get() or ns.CharacterScanner:Scan()
    local plan = Camp:Plan(snap)
    -- Разбор по одному - полный (cheap = false) и с тем же индексом профессий,
    -- каким его строит сам план: иначе в таблице не было бы ни цен, ни альтов.
    local index = ns.Roster:ProfessionIndex()
    print(string.format("%-28s %-16s %4s %4s %-9s %-9s %-10s %s",
        "предмет", "профессия", "тир", "пор.", "навык", "рецепт", "матер.", "готовый/чертёж"))
    for _, row in ipairs(ns.CampData.OBJECTS) do
        local d = Camp:Describe(row, snap, index, false)
        if not d then
            print(string.format("%-28s чужая фракция", row.en))
        else
            local tail = d.buyCopper and ns.Util.money(d.buyCopper) or "нет цены"
            if d.bpItem then
                tail = tail .. " / чертёж "
                    .. (d.bpCopper and ns.Util.money(d.bpCopper) or "нет цены")
                    .. (d.bpName and "" or " (имени нет)")
            end
            print(string.format("%-28s %-16s %4d %4s %-9s %-9s %-10s %s",
                ns.Util.truncate(d.name or ("#" .. row.item), 28),
                ns.Util.truncate(tostring(d.profLabel or "?"), 16),
                row.tier, tostring(d.need),
                d.skill and tostring(d.skill)
                    or (d.holder and ("альт " .. tostring(d.holder.skill)) or "нет"),
                tostring(d.recipeState),
                d.haveAll and "всё есть"
                    or (d.costKnown and ns.Util.money(d.cost) or "цена ?"),
                tail))
        end
    end
    -- НА ЧЁМ ОСНОВАНА КАЖДАЯ ЦЕНА ЛАГЕРЯ. У карточки в строке стоит одно число,
    -- а источников у него до шести; без этой таблицы «почему тут 1с 60м, а не
    -- 1с 34м» не ответить ничем, кроме догадки.
    if plan then
        print("")
        print("   ЦЕНЫ ЛАГЕРЯ: откуда взято число")
        local seen = {}
        local function routesOf(id, label)
            if not id or seen[id] then return end
            seen[id] = true
            local copper, conf, src = ns.PriceProvider:Buy(id)
            local bits = {}
            for _, r in ipairs(ns.PriceProvider:Routes(id)) do
                bits[#bits + 1] = tostring(r.src) .. "=" .. ns.Util.money(r.copper)
            end
            print(string.format("   %-30s %-10s %-12s %s",
                ns.Util.truncate(label, 30),
                copper and ns.Util.money(copper) or "нет",
                tostring(src),
                (#bits > 0) and table.concat(bits, ", ") or "никто не ответил"))
        end
        for _, list in ipairs({ plan.here, plan.gated, plan.elsewhere, plan.teach }) do
            for _, d in ipairs(list) do
                routesOf(d.item, d.name or ("#" .. d.item))
                routesOf(d.bpItem, (d.bpName or "чертёж") .. " (чертёж)")
                for _, line in ipairs(d.reagents or {}) do
                    routesOf(line.itemID, line.name)
                end
            end
        end
    end
    if plan then
        local function names(list)
            local out = {}
            for i = 1, math.min(4, #list) do out[#out + 1] = list[i].name end
            return (#out > 0) and table.concat(out, ", ") or "ничего"
        end
        print("")
        print("сделать сейчас (" .. #plan.here .. "): " .. names(plan.here))
        print("нужен чертёж (" .. #plan.gated .. "): " .. names(plan.gated))
        print("нужен тренер (" .. #plan.teach .. "): " .. names(plan.teach))
        print("сделает другой (" .. #plan.elsewhere .. "): " .. names(plan.elsewhere))
        print("закрыто профессиями аккаунта: " .. plan.covered .. " из " .. plan.total
            .. "; нет ни у кого: " .. table.concat(plan.uncovered, ", "))
        print("имён не дождались: " .. plan.nameless
            .. ", рецептов не прочитано: " .. plan.unread
            .. ", спорных порогов: " .. plan.disputed)
        print("самый вместительный костёр сейчас: "
            .. (plan.fireNow and plan.fireNow.name or "ни одного"))
    end
end
