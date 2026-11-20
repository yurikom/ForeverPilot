-- ForeverPilot / Data/SlotMap.lua
--
-- Turns what the game tells us into our own slot keys.
--
-- Two independent routes, in this order of trust:
--   1. The item's own equip location from C_Item.GetItemInfo ("INVTYPE_HEAD").
--      Language-independent and exact. Used for everything a recipe produces.
--   2. The recipe's category name, for recipes that produce no item at all -
--      i.e. enchants. The category comes from the recipe's categoryID, so the
--      mapping is stored per categoryID and only has to be guessed once; the
--      player can correct it in Settings and the correction sticks.
local ADDON, ns = ...

local U = ns.Util
local SlotMap = {}
ns.SlotMap = SlotMap

-- Route 1: INVTYPE -> our slot key. This is a game constant, not a translation.
SlotMap.INVTYPE = {
    INVTYPE_HEAD            = "HEAD",
    INVTYPE_NECK            = "NECK",
    INVTYPE_SHOULDER        = "SHOULDER",
    INVTYPE_BODY            = "SHIRT",
    INVTYPE_CHEST           = "CHEST",
    INVTYPE_ROBE            = "CHEST",
    INVTYPE_WAIST           = "WAIST",
    INVTYPE_LEGS            = "LEGS",
    INVTYPE_FEET            = "FEET",
    INVTYPE_WRIST           = "WRIST",
    INVTYPE_HAND            = "HANDS",
    INVTYPE_FINGER          = "FINGER",
    INVTYPE_TRINKET         = "TRINKET",
    INVTYPE_CLOAK           = "BACK",
    INVTYPE_WEAPON          = "MAINHAND",
    INVTYPE_SHIELD          = "SHIELD",
    INVTYPE_2HWEAPON        = "TWOHAND",
    INVTYPE_WEAPONMAINHAND  = "MAINHAND",
    INVTYPE_WEAPONOFFHAND   = "OFFHAND",
    INVTYPE_HOLDABLE        = "HELDINHAND",
    INVTYPE_RANGED          = "RANGED",
    INVTYPE_RANGEDRIGHT     = "RANGED",
    INVTYPE_THROWN          = "RANGED",
    INVTYPE_RELIC           = "RANGED",
    INVTYPE_TABARD          = "TABARD",
    INVTYPE_BAG             = "BAG",
}

function SlotMap:FromEquipLoc(equipLoc)
    if type(equipLoc) ~= "string" then return nil end
    return SlotMap.INVTYPE[equipLoc]
end

-- Route 1b: the NUMERIC inventory type, for an item the client has not cached.
--
-- GetItemInfo answers with the INVTYPE string, and for anything in the player's
-- bags it always answers. The bank is the gap: its contents are remembered from
-- the last time it was open, and the client may have forgotten the item itself.
-- The external item database stores the numeric type instead, so this is the
-- bridge. The numbers are the game's own InventoryType values, unchanged since
-- vanilla, and they were checked against the installed database: 6367 (удочка)
-- and 249392 (Мерцающий посох) are 17 = two-hand, 13062 (палочка) is 26 =
-- ranged right, 7005 (нож для снятия шкур) is 13 = one-hand.
SlotMap.INV_NUMBER = {
    [1] = "HEAD", [2] = "NECK", [3] = "SHOULDER", [4] = "SHIRT", [5] = "CHEST",
    [6] = "WAIST", [7] = "LEGS", [8] = "FEET", [9] = "WRIST", [10] = "HANDS",
    [11] = "FINGER", [12] = "TRINKET", [13] = "MAINHAND", [14] = "SHIELD",
    [15] = "RANGED", [16] = "BACK", [17] = "TWOHAND", [18] = "BAG",
    [19] = "TABARD", [20] = "CHEST", [21] = "MAINHAND", [22] = "OFFHAND",
    [23] = "HELDINHAND", [25] = "RANGED", [26] = "RANGED", [28] = "RANGED",
}

function SlotMap:FromInvNumber(inv)
    inv = tonumber(inv)
    if not inv then return nil end
    return SlotMap.INV_NUMBER[inv]
end

-- Route 2: keyword sets per slot, for enchant categories. Keywords are matched
-- case-insensitively as substrings against the lowercased category name. Both
-- the Russian the player's client uses and the English fallback are listed,
-- because the category name is whatever the client hands us.
--
-- Order matters: the first slot whose keyword matches wins, so the more
-- specific entries ("двуручного оружия") come before the general ones
-- ("оружия").
-- Stems are written lowercase; matching goes through Util.lower, which knows
-- Cyrillic (Lua's own string.lower does not, so "Чары" would never match
-- "чары" without it). Stems are kept short enough to survive Russian case
-- endings: "перчат" matches both "перчатки" and "перчаток".
SlotMap.CATEGORY_KEYWORDS = {
    { slot = "TWOHAND",    words = { "двуручн", "two%-hand", "2h" } },
    { slot = "SHIELD",     words = { "щит", "shield" } },
    { slot = "HELDINHAND", words = { "левой рук", "off%-hand", "held in off" } },
    { slot = "HEAD",       words = { "шлем", "голов", "капюшон", "head", "helm" } },
    { slot = "NECK",       words = { "амулет", "ожерель", "neck", "amulet" } },
    { slot = "SHOULDER",   words = { "наплеч", "плеч", "shoulder" } },
    { slot = "BACK",       words = { "плащ", "накидк", "cloak", "back" } },
    { slot = "CHEST",      words = { "нагрудник", "доспех", "жилет", "одеян", "chest", "robe" } },
    { slot = "WRIST",      words = { "наруч", "браслет", "wrist", "bracer" } },
    { slot = "HANDS",      words = { "перчат", "рукавиц", "glove", "hand" } },
    { slot = "WAIST",      words = { "пояс", "ремен", "belt", "waist" } },
    { slot = "LEGS",       words = { "понож", "штан", "брюк", "leg", "pant" } },
    { slot = "FEET",       words = { "обув", "сапог", "боти", "feet", "boot" } },
    { slot = "RANGED",     words = { "стрелков", "лук", "ranged", "bow", "gun" } },
    { slot = "MAINHAND",   words = { "оруж", "weapon" } },
}

-- Category names that look like a slot but are not enchants: these produce an
-- item, and route 1 already handles them. Listed so a recipe that produces a
-- "Капюшон" is never mistaken for a head enchant.
SlotMap.ENCHANT_HINTS = { "чары", "зачаров", "enchant" }

function SlotMap:LooksLikeEnchantCategory(categoryName)
    if type(categoryName) ~= "string" then return false end
    local lower = U.lower(categoryName)
    for _, hint in ipairs(SlotMap.ENCHANT_HINTS) do
        if lower:find(hint, 1, true) then return true end
    end
    return false
end

-- Guess the slot an enchant category applies to. Returns slotKey, confidence.
function SlotMap:GuessSlotFromCategory(categoryName)
    if type(categoryName) ~= "string" then return nil, ns.CONF.UNKNOWN end
    local lower = U.lower(categoryName)
    for _, entry in ipairs(SlotMap.CATEGORY_KEYWORDS) do
        for _, word in ipairs(entry.words) do
            if lower:find(word) then
                return entry.slot, ns.CONF.ESTIMATE
            end
        end
    end
    return nil, ns.CONF.UNKNOWN
end

-- The resolved slot for an enchant recipe. The player's own correction, stored
-- per categoryID, always wins over our guess.
function SlotMap:EnchantSlot(recipe)
    if type(recipe) ~= "table" then return nil, ns.CONF.UNKNOWN end
    local override = ns.Config and ns.Config:EnchantSlot(recipe.categoryID)
    if override then
        if override == "NONE" then return nil, ns.CONF.EXACT end
        return override, ns.CONF.EXACT
    end
    return SlotMap:GuessSlotFromCategory(recipe.categoryName)
end

-- Localised slot names. Falls back to the key itself, clearly marked, when the
-- client gives us nothing - we never invent a translation.
SlotMap.SLOT_LABEL_RU = {
    HEAD = "голова", NECK = "шея", SHOULDER = "плечи", BACK = "спина",
    CHEST = "грудь", WRIST = "запястья", HANDS = "кисти", WAIST = "пояс",
    LEGS = "ноги", FEET = "ступни", FINGER = "палец", TRINKET = "аксессуар",
    MAINHAND = "правая рука", OFFHAND = "левая рука", RANGED = "дальний бой",
    TWOHAND = "двуручное", SHIELD = "щит", HELDINHAND = "в левой руке",
    SHIRT = "рубашка", TABARD = "гербовая накидка", BAG = "сумка",
}

-- Prefer the client's own global strings so the words match the rest of the UI.
SlotMap.SLOT_GLOBAL = {
    HEAD = "INVTYPE_HEAD", NECK = "INVTYPE_NECK", SHOULDER = "INVTYPE_SHOULDER",
    BACK = "INVTYPE_CLOAK", CHEST = "INVTYPE_CHEST", WRIST = "INVTYPE_WRIST",
    HANDS = "INVTYPE_HAND", WAIST = "INVTYPE_WAIST", LEGS = "INVTYPE_LEGS",
    FEET = "INVTYPE_FEET", FINGER = "INVTYPE_FINGER", TRINKET = "INVTYPE_TRINKET",
    MAINHAND = "INVTYPE_WEAPONMAINHAND", OFFHAND = "INVTYPE_WEAPONOFFHAND",
    RANGED = "INVTYPE_RANGED", TWOHAND = "INVTYPE_2HWEAPON",
    SHIELD = "INVTYPE_SHIELD", HELDINHAND = "INVTYPE_HOLDABLE",
    SHIRT = "INVTYPE_BODY", TABARD = "INVTYPE_TABARD", BAG = "INVTYPE_BAG",
}

function SlotMap:Label(slotKey)
    if not slotKey then return "?" end
    local base = slotKey:gsub("%d$", "")
    local globalKey = SlotMap.SLOT_GLOBAL[base]
    if globalKey and type(_G) == "table" then
        local text = _G[globalKey]
        if type(text) == "string" and U.trim(text) then return text end
    end
    local ru = SlotMap.SLOT_LABEL_RU[base]
    if ru then return ru end
    return base .. " (без перевода)"
end

-- Equipment slots a recipe's output can actually go into. TWOHAND fills
-- MAINHAND, and a ring or trinket can go in either of its two slots.
function SlotMap:TargetSlots(slotKey)
    if slotKey == "TWOHAND" then return { "MAINHAND" } end
    if slotKey == "FINGER" then return { "FINGER1", "FINGER2" } end
    if slotKey == "TRINKET" then return { "TRINKET1", "TRINKET2" } end
    if slotKey == "SHIELD" or slotKey == "HELDINHAND" then return { "OFFHAND" } end
    return { slotKey }
end

-- Every slot a candidate actually empties when it is put on. A two-hander takes
-- the main hand AND frees the off hand, so comparing it against the main hand
-- alone made a weak staff look better than a decent weapon plus an off-hand.
function SlotMap:DisplacedSlots(slotKey)
    if slotKey == "TWOHAND" then return { "MAINHAND", "OFFHAND" } end
    return SlotMap:TargetSlots(slotKey)
end

-- Which enchant categories an item in a slot can take.
--
-- The enchant categories are named after item TYPES ("двуручное оружие",
-- "щит"), while equipment slots are named after places on the body
-- (MAINHAND, OFFHAND). Matching the two by name meant a known two-hand
-- enchant was never offered for the staff the player was holding, because the
-- staff lives in MAINHAND and the formula was filed under TWOHAND.
--
-- `info` is the equipped item's ItemInfo; without it we fall back to the slot.
function SlotMap:EnchantKeysForItem(slotKey, info)
    local base = slotKey and slotKey:gsub("%d$", "") or nil
    local equipLoc = info and info.equipLoc
    if type(equipLoc) == "string" and equipLoc ~= "" then
        local itemSlot = SlotMap.INVTYPE[equipLoc]
        if itemSlot == "TWOHAND" then
            -- A two-hander takes two-hand enchants and plain weapon ones.
            return { "TWOHAND", "MAINHAND" }
        elseif itemSlot == "SHIELD" then
            return { "SHIELD" }
        elseif itemSlot == "HELDINHAND" then
            return { "HELDINHAND" }
        elseif itemSlot == "MAINHAND" then
            -- A one-hander in either hand takes weapon enchants.
            return { "MAINHAND" }
        elseif itemSlot == "OFFHAND" then
            return { "MAINHAND", "OFFHAND" }
        elseif itemSlot then
            return { itemSlot }
        end
    end
    -- Unknown item: the slot name is the only thing we have.
    if base == "MAINHAND" then return { "MAINHAND" } end
    if base == "OFFHAND" then return { "MAINHAND", "OFFHAND", "SHIELD", "HELDINHAND" } end
    return base and { base } or {}
end

-- Whether a slot can take an enchant at all.
--
-- Prefer the evidence over the assumption: if the client has shown us
-- enchanting recipes, the slots those recipes target ARE the enchantable
-- slots on this realm, and anything else is not. Forever proves why this
-- matters - it has neck enchants and no head, leg or ranged ones, so the
-- vanilla-era hardcoded list would both miss real slots and invent fake ones.
-- The static list in Const is only the fallback for before the first scan.
function SlotMap:IsEnchantable(slotKey)
    if not slotKey then return false end
    local base = slotKey:gsub("%d$", "")

    local derived = ns.RecipeBook and ns.RecipeBook.EnchantableSlots
        and ns.RecipeBook:EnchantableSlots()
    if derived then
        return (derived[base] or derived[slotKey]) and true or false
    end

    for _, s in ipairs(ns.ENCHANTABLE_SLOTS) do
        if s == base then return true end
    end
    return false
end

return SlotMap
