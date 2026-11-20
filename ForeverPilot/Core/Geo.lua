-- ForeverPilot / Core/Geo.lua
--
-- The navigation maths, kept pure so it can be tested without the game.
--
-- Coordinate conventions, which is where this kind of code usually goes wrong:
--
--   MAP SPACE. The client gives map positions as two fractions in 0..1.
--   x grows EASTWARD. y grows SOUTHWARD - y = 0 is the top (north) edge of the
--   map, not the bottom. Every formula below assumes that.
--
--   BEARING. We measure bearings clockwise from north, in radians:
--   north = 0, east = pi/2, south = pi, west = -pi/2 (or equivalently 3pi/2).
--
--   PLAYER FACING. GetPlayerFacing returns radians where 0 is north and the
--   value grows COUNTER-CLOCKWISE (so pi/2 is west). That is the opposite
--   handedness from our bearings, which is why the two are added rather than
--   subtracted when working out where to point the arrow.
--
--   TEXTURE ROTATION. Texture:SetRotation rotates counter-clockwise. To turn
--   the arrow clockwise by a, we pass -a.
local ADDON, ns = ...

local Geo = {}
ns.Geo = Geo

local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
local sqrt, pi, abs = math.sqrt, math.pi, math.abs
local floor, fmod = math.floor, math.fmod

Geo.TWO_PI = pi * 2

-- Normalise an angle into (-pi, pi].
function Geo.normalize(angle)
    angle = tonumber(angle)
    if not angle then return nil end
    angle = fmod(angle, Geo.TWO_PI)
    if angle > pi then angle = angle - Geo.TWO_PI end
    if angle <= -pi then angle = angle + Geo.TWO_PI end
    return angle
end

-- Bearing from one map point to another, clockwise from north, in radians.
-- Returns nil when the two points coincide, because a bearing to where you
-- already stand has no meaning and the caller must not draw an arrow for it.
function Geo.Bearing(px, py, tx, ty)
    px, py, tx, ty = tonumber(px), tonumber(py), tonumber(tx), tonumber(ty)
    if not (px and py and tx and ty) then return nil end
    local dx = tx - px
    local dy = ty - py          -- positive means the target is further south
    if abs(dx) < 1e-9 and abs(dy) < 1e-9 then return nil end
    -- atan2(east component, north component); north component is -dy because
    -- y grows southward.
    return Geo.normalize(atan2(dx, -dy))
end

-- Where to point the arrow on screen, as a value for Texture:SetRotation.
-- `bearing` is clockwise from north; `facing` is GetPlayerFacing's radians
-- (counter-clockwise from north), or nil when the client will not tell us.
-- Returns nil without a facing: an arrow that cannot account for which way the
-- player is turned is worse than no arrow, so the caller hides it.
function Geo.ArrowRotation(bearing, facing)
    bearing, facing = tonumber(bearing), tonumber(facing)
    if not (bearing and facing) then return nil end
    -- Our bearings run clockwise, the facing runs counter-clockwise, so the
    -- screen-relative clockwise angle is their sum.
    local clockwise = Geo.normalize(bearing + facing)
    -- SetRotation turns counter-clockwise, hence the negation.
    return -clockwise, clockwise
end

-- Straight-line distance in yards between two points on the SAME map.
-- `widthYards` and `heightYards` come from C_Map.GetMapWorldSize. Without them
-- there is no honest way to turn fractions into yards, so this returns nil and
-- the caller says the distance is unknown rather than inventing a unit.
function Geo.Distance(px, py, tx, ty, widthYards, heightYards)
    px, py, tx, ty = tonumber(px), tonumber(py), tonumber(tx), tonumber(ty)
    if not (px and py and tx and ty) then return nil end
    widthYards, heightYards = tonumber(widthYards), tonumber(heightYards)
    if not (widthYards and heightYards) or widthYards <= 0 or heightYards <= 0 then
        return nil
    end
    local dx = (tx - px) * widthYards
    local dy = (ty - py) * heightYards
    return sqrt(dx * dx + dy * dy)
end

-- Distance as a fraction of the map diagonal. Always available, and useful for
-- "am I close?" decisions even when yards are not known. 0..~1.41.
function Geo.MapDistance(px, py, tx, ty)
    px, py, tx, ty = tonumber(px), tonumber(py), tonumber(tx), tonumber(ty)
    if not (px and py and tx and ty) then return nil end
    local dx, dy = tx - px, ty - py
    return sqrt(dx * dx + dy * dy)
end

-- Compass points, for when there is no facing to rotate an arrow by. This is
-- the honest fallback: the direction on the map is still true, it just cannot
-- be drawn relative to where the player is looking.
Geo.COMPASS = {
    "на север", "на северо-восток", "на восток", "на юго-восток",
    "на юг", "на юго-запад", "на запад", "на северо-запад",
}
Geo.COMPASS_SHORT = { "С", "СВ", "В", "ЮВ", "Ю", "ЮЗ", "З", "СЗ" }

local function compassIndex(bearing)
    bearing = Geo.normalize(bearing)
    if not bearing then return nil end
    if bearing < 0 then bearing = bearing + Geo.TWO_PI end
    -- Eight sectors of 45 degrees, centred on the compass points.
    return (floor((bearing + pi / 8) / (pi / 4)) % 8) + 1
end

function Geo.CompassName(bearing)
    local idx = compassIndex(bearing)
    return idx and Geo.COMPASS[idx] or nil
end

function Geo.CompassShort(bearing)
    local idx = compassIndex(bearing)
    return idx and Geo.COMPASS_SHORT[idx] or nil
end

-- Formatting -------------------------------------------------------------

function Geo.DistanceText(yards)
    yards = tonumber(yards)
    if not yards then return nil end
    if yards < 1 then return "меньше метра" end
    if yards < 1000 then return floor(yards + 0.5) .. " м" end
    return string.format("%.1f км", yards / 1000)
end

-- Fraction-of-map distance, when yards are unavailable. Deliberately vague,
-- because the number itself means nothing to a player.
function Geo.RoughText(mapDistance)
    mapDistance = tonumber(mapDistance)
    if not mapDistance then return nil end
    if mapDistance < 0.02 then return "совсем рядом" end
    if mapDistance < 0.08 then return "близко" end
    if mapDistance < 0.25 then return "недалеко" end
    if mapDistance < 0.55 then return "далеко" end
    return "очень далеко"
end

-- A full solution ---------------------------------------------------------

-- Everything the arrow needs, worked out in one call, with the reason it
-- cannot be drawn when it cannot.
--
--   player = { mapID, x, y, facing }   facing may be nil
--   target = { mapID, x, y }
--   worldSize = { width, height } in yards, or nil
--
-- Returns a table:
--   { ok, reason, bearing, rotation, yards, mapDistance, compass, arrived,
--     sameMap }
--
-- reason is one of:
--   "no-player"   we do not know where the player is
--   "no-target"   the target has no coordinates
--   "other-map"   the target is on a different map; direction is meaningless
--   "no-facing"   we know the direction but not which way the player is turned
--   "arrived"     close enough that an arrow would just spin
Geo.ARRIVE_YARDS = 12
Geo.ARRIVE_MAP = 0.004

function Geo.Solve(player, target, worldSize)
    local out = { ok = false }
    if type(player) ~= "table" or not (player.mapID and player.x and player.y) then
        out.reason = "no-player"
        return out
    end
    if type(target) ~= "table" or not (target.mapID and target.x and target.y) then
        out.reason = "no-target"
        return out
    end

    out.sameMap = (player.mapID == target.mapID)
    if not out.sameMap then
        -- A bearing computed across two different maps points nowhere real.
        out.reason = "other-map"
        return out
    end

    out.mapDistance = Geo.MapDistance(player.x, player.y, target.x, target.y)
    if worldSize then
        out.yards = Geo.Distance(player.x, player.y, target.x, target.y,
            worldSize.width, worldSize.height)
    end

    local arrived
    if out.yards then
        arrived = out.yards <= Geo.ARRIVE_YARDS
    else
        arrived = (out.mapDistance or 1) <= Geo.ARRIVE_MAP
    end
    if arrived then
        out.arrived = true
        out.reason = "arrived"
        out.ok = true
        return out
    end

    out.bearing = Geo.Bearing(player.x, player.y, target.x, target.y)
    if not out.bearing then
        out.arrived = true
        out.reason = "arrived"
        out.ok = true
        return out
    end
    out.compass = Geo.CompassName(out.bearing)

    local rotation, clockwise = Geo.ArrowRotation(out.bearing, player.facing)
    if not rotation then
        -- Direction is known, the arrow is not drawable. Still useful.
        out.reason = "no-facing"
        out.ok = true
        return out
    end
    out.rotation = rotation
    out.clockwise = clockwise
    out.ok = true
    return out
end

return Geo
