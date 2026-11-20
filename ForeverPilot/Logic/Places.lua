-- ForeverPilot / Logic/Places.lua
--
-- "Where do I go for this?" - the data behind the Show the way button.
--
-- Where the coordinates come from, and the honest limitation:
--
-- Mastercraft ships a complete vendor coordinate table, but it lives in that
-- addon's private namespace (local ADDON, ns = ...), which no other addon can
-- reach at runtime - there is no API for reading another addon's namespace, and
-- its SavedVariables do not contain it. Copying the table is out of the
-- question. So ForeverPilot builds its own, from the player's own play:
--
--   * open a merchant  -> we record that NPC, where it stands, and what it sells
--   * open a trainer   -> we record that NPC and which profession it teaches
--
-- That means the first run has no routes and the data fills in as the player
-- walks around, which is slower than a shipped database but is ours, is always
-- correct for this realm, and needs no dependency. If some addon ever publishes
-- its places table as a global, Api:ForeignPlaces picks it up automatically.
--
-- Everything here degrades to "no place known", and every caller has to handle
-- that: no TomTom means no button, no coordinates means no button either.
local ADDON, ns = ...

local U = ns.Util
local Api = ns.Api
local CONF = ns.CONF

local Places = {}
ns.Places = Places

-- Storage ---------------------------------------------------------------

local function store()
    local cfg = ns.Config:Get()
    if not cfg then return nil end
    cfg.places = cfg.places or {}
    local p = cfg.places
    p.npc = p.npc or {}            -- npcID -> { name, mapID, x, y, zone, seen, kind }
    p.itemVendors = p.itemVendors or {} -- itemID -> { npcID, ... }
    p.trainers = p.trainers or {}  -- lowercased profession name -> { npcID, ... }
    return p
end

function Places:Count()
    local p = store()
    if not p then return 0, 0, 0 end
    return U.count(p.npc), U.count(p.itemVendors), U.count(p.trainers)
end

-- Recording -------------------------------------------------------------

-- Remember where an NPC stands. Returns the stored place, or nil when the
-- client would not tell us the position.
function Places:RecordNpc(npcID, name, kind)
    local p = store()
    if not (p and npcID) then return nil end

    local mapID, x, y, zone = Api:PlayerPosition()
    if not (mapID and x and y) then
        -- Instances and a few outdoor spots report no position. Keep the name
        -- so the card can still say who to look for, just without a route.
        local existing = p.npc[npcID]
        if existing then return existing end
        p.npc[npcID] = {
            name = name, kind = kind, seen = Api:ServerTime(),
            mapID = nil, x = nil, y = nil, zone = nil,
        }
        return p.npc[npcID]
    end

    p.npc[npcID] = {
        name = name or (p.npc[npcID] and p.npc[npcID].name),
        kind = kind or (p.npc[npcID] and p.npc[npcID].kind),
        mapID = mapID, x = x, y = y, zone = zone,
        seen = Api:ServerTime(),
    }
    return p.npc[npcID]
end

local function addLink(bucket, key, npcID)
    if not (bucket and key and npcID) then return end
    local list = bucket[key]
    if not list then list = {}; bucket[key] = list end
    for _, id in ipairs(list) do
        if id == npcID then return end
    end
    list[#list + 1] = npcID
    -- A handful of sources per item is plenty; the nearest is what matters.
    while #list > 6 do table.remove(list, 1) end
end

-- Called when the player opens a merchant window. Records the NPC's position
-- and what it sells, so "buy this reagent" can become a route later.
function Places:RecordMerchant()
    local p = store()
    if not p then return 0 end

    local npcID = Api:UnitNpcID("npc")
    local name = Api:UnitName("npc")
    if not npcID then return 0 end

    Places:RecordNpc(npcID, name, "vendor")

    local items = Api:MerchantItems()
    local learned, limited = 0, 0
    for _, entry in ipairs(items or {}) do
        -- A finite pile is still worth remembering as "this NPC had it", but it
        -- is not a price the player can count on, so PriceProvider decides.
        local kept = ns.PriceProvider:RecordMerchant(entry.itemID, entry.price,
            entry.stack, entry.numAvailable)
        if kept then
            addLink(p.itemVendors, entry.itemID, npcID)
            learned = learned + 1
        else
            limited = limited + 1
        end
    end
    return learned, npcID, name, limited
end

-- Called when the player opens a profession trainer.
--
-- No API tells us which profession a trainer teaches. Attributing the NPC to
-- every crafting profession the player has looked harmless and was not: with
-- four professions, the tailoring trainer became the enchanting trainer too and
-- the arrow pointed at the wrong person. So the attribution is only made when
-- it is unambiguous - exactly one candidate profession - and otherwise the NPC
-- is kept as a trainer whose profession we do not know, which the card says.
--
-- `teaches` is an optional single profession name for the day we can read it
-- from the trainer window; passing it makes the attribution certain.
function Places:RecordTrainer(professionNames, teaches)
    local p = store()
    if not p then return nil end

    local npcID = Api:UnitNpcID("npc")
    local name = Api:UnitName("npc")
    if not npcID then return nil end

    Places:RecordNpc(npcID, name, "trainer")

    local candidates = {}
    for _, prof in ipairs(professionNames or {}) do
        local key = U.lower(prof)
        if key then candidates[#candidates + 1] = key end
    end

    local certain = teaches and U.lower(teaches) or nil
    if certain then
        addLink(p.trainers, certain, npcID)
        return npcID, name, certain
    end
    if #candidates == 1 then
        addLink(p.trainers, candidates[1], npcID)
        return npcID, name, candidates[1]
    end

    -- Ambiguous: remember the NPC, but do not claim a profession for it.
    p.trainersUnknown = p.trainersUnknown or {}
    for _, id in ipairs(p.trainersUnknown) do
        if id == npcID then return npcID, name, nil end
    end
    p.trainersUnknown[#p.trainersUnknown + 1] = npcID
    while #p.trainersUnknown > 12 do table.remove(p.trainersUnknown, 1) end
    return npcID, name, nil
end

-- Lookup ----------------------------------------------------------------

-- A place in our own shape:
--   { npcID, name, mapID, x, y, zone, conf, routable, source }
local function shape(npcID, raw, source)
    if type(raw) ~= "table" then return nil end
    local x, y = tonumber(raw.x), tonumber(raw.y)
    -- Foreign tables tend to store percentages; ours stores fractions.
    if x and x > 1 then x = x / 100 end
    if y and y > 1 then y = y / 100 end
    local mapID = tonumber(raw.mapID or raw.uiMapID)
    return {
        npcID = npcID,
        name = U.trim(raw.name),
        mapID = mapID,
        x = x, y = y,
        zone = U.trim(raw.zone) or (mapID and Api:MapName(mapID)) or nil,
        seen = tonumber(raw.seen),
        kind = raw.kind,
        source = source,
        conf = (source == "own") and CONF.CACHED or CONF.ESTIMATE,
        routable = (mapID and x and y) and true or false,
    }
end

function Places:Lookup(npcID)
    if not npcID then return nil end
    local p = store()
    local own = p and p.npc[npcID]
    if own then
        local place = shape(npcID, own, "own")
        if place then return place end
    end
    local foreign, who = Api:ForeignPlaces()
    if foreign and foreign[npcID] then
        return shape(npcID, foreign[npcID], who or "foreign")
    end
    -- ТРЕТИЙ ПУТЬ: Polestar.Codex. До него маршрут существовал только к тем
    -- торговцам, перед которыми игрок уже стоял, - то есть совет «купи у
    -- торговца в Оргриммаре» нельзя было показать, пока игрок туда не пришёл
    -- сам. Codex знает точки появления 10 000 NPC; данные не наши, поэтому
    -- достоверность ESTIMATE и источник назван.
    local mapID, x, y, name, rec = Api:CodexNpcSpawn(npcID)
    if mapID and x and y then
        local place = shape(npcID, {
            name = name, mapID = mapID, x = x, y = y,
            kind = rec and rec.subName or nil,
        }, "codex")
        if place then
            place.conf = CONF.ESTIMATE
            place.foreignSource = "Polestar.Codex"
            return place
        end
    end
    -- Ни одного источника. Это заказ на данные: NPC понадобился для маршрута,
    -- а координат нет ни у нас, ни в чужих базах.
    if ns.Diag then
        ns.Diag:Want("npcNoCoords", npcID, "route-request",
            { name = rec and rec.name or nil })
    end
    return nil
end

-- The best place to buy `itemID`: the one we have real coordinates for, newest
-- first. Returns nil when we have never seen a vendor for it.
function Places:ForItem(itemID)
    local p = store()
    if not (p and itemID) then return nil end
    local best
    for _, npcID in ipairs(p.itemVendors[itemID] or {}) do
        local place = Places:Lookup(npcID)
        if place then
            if place.routable and (not best or not best.routable
               or (place.seen or 0) > (best.seen or 0)) then
                best = place
            elseif not best then
                best = place
            end
        end
    end
    return best
end

function Places:ForTrainer(professionName)
    local p = store()
    if not (p and professionName) then return nil end
    local key = U.lower(professionName)
    local best
    for _, npcID in ipairs((key and p.trainers[key]) or {}) do
        local place = Places:Lookup(npcID)
        if place and (not best or (place.routable and not best.routable)) then
            best = place
        end
    end
    if best then best.professionKnown = true end
    return best
end

-- Any trainer we have seen, including the ones whose profession we could not
-- work out. The card uses this to say "a trainer stood here, I am not sure
-- which one" instead of claiming knowledge it does not have.
function Places:AnyTrainer()
    local p = store()
    if not p then return nil end
    local best
    for _, npcID in ipairs(p.trainersUnknown or {}) do
        local place = Places:Lookup(npcID)
        if place and (not best or (place.routable and not best.routable)) then
            best = place
        end
    end
    if best then best.professionKnown = false end
    return best
end

-- Presentation ----------------------------------------------------------

-- Can we point at anything at all? Our own arrow needs only a player position,
-- so this is normally true; it goes false when the player has turned routing
-- off, or picked TomTom without having TomTom.
function Places:CanRoute()
    return Api:NavProvider() ~= nil
end

function Places:RouteProviderLabel()
    local provider = Api:NavProvider()
    if not provider then return nil end
    return Api.NAV_PROVIDER_LABEL[provider] or provider
end

-- "Тернистая долина, 34.2 76.8" - what the card shows when there is no TomTom
-- to draw an arrow with.
function Places:Describe(place)
    if type(place) ~= "table" then return nil end
    local bits = {}
    if place.name then bits[#bits + 1] = place.name end
    if place.zone then bits[#bits + 1] = place.zone end
    if place.x and place.y then
        bits[#bits + 1] = string.format("%.1f %.1f", place.x * 100, place.y * 100)
    end
    if #bits == 0 then return nil end
    return table.concat(bits, ", ")
end

-- The one-line hint a card appends. Three cases, all of them honest:
--   TomTom + coords  -> the button does the work, so just name the place
--   coords, no TomTom-> the coordinates in text
--   no coords        -> who to look for, and that we do not know where
--
-- КООРДИНАТЫ И НИЧЕГО КРОМЕ. Здесь к координатам приписывалось «(навигация
-- выключена в настройках)» - дорога в настройки прямо посреди строки совета, и
-- именно она отжимала координаты за край окна: обрезалось «78.2 5…», то есть
-- ровно то, ради чего строку читают. Объяснение, почему нет кнопки пути,
-- уехало под курсор - Places:CardTip, подсказка совета.
function Places:CardHint(place)
    if type(place) ~= "table" then return nil end
    local where = Places:Describe(place)
    if not where then return nil end
    if place.routable then return where end
    return (place.name or "этот NPC") .. " — координат я не записал"
end

-- Почему у совета с координатами нет кнопки «Показать путь». nil - кнопка есть
-- или объяснять нечего.
function Places:CardTip(place)
    if type(place) ~= "table" then return nil end
    if not place.routable then return nil end
    if Places:CanRoute() then return nil end
    return "Кнопки пути нет: навигация выключена в настройках."
        .. " Координаты в строке совета от этого не портятся."
end

-- Point at a place. Our own arrow by default; TomTom when the player chose it.
-- Returns ok, reason, provider.
function Places:Route(place, title)
    if type(place) ~= "table" then return false, "no-place" end
    if not place.routable then return false, "no-coords" end
    if Api:InCombat() then return false, "combat" end
    if not ns.Arrow then return false, "no-navigator" end
    return ns.Arrow:SetTarget(place, title or place.name)
end

function Places:StopRoute()
    if ns.Arrow then ns.Arrow:Clear() end
end

-- Diagnostics for the character tab.
function Places:Summary()
    local npcs, items, trainers = Places:Count()
    local routable = 0
    local p = store()
    for npcID, raw in pairs((p and p.npc) or {}) do
        local place = shape(npcID, raw, "own")
        if place and place.routable then routable = routable + 1 end
    end
    local foreign, who = Api:ForeignPlaces()
    return {
        npcs = npcs, routable = routable,
        items = items, trainers = trainers,
        canRoute = Places:CanRoute(),
        provider = Places:RouteProviderLabel(),
        hasFacing = Api:HasPlayerFacing(),
        tomtom = Api:TomTomPresent(),
        foreign = foreign and who or nil,
    }
end

return Places
