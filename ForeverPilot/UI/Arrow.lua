-- ForeverPilot / UI/Arrow.lua
--
-- Our own direction arrow. A small draggable window: a rotating arrow, the
-- distance, and the name of what we are pointing at.
--
-- What it does NOT do: pathfinding. It points in a straight line at the target,
-- which is honest about what it knows. There is no route, no ETA invented from
-- a guess, and no claim about how to get around a cliff.
--
-- The four states it has to handle, all of which are normal:
--   drawable   - same map, position and facing all known: the arrow turns
--   no-facing  - the client will not say which way we are looking (happens in
--                some instances and on taxi flights). The arrow hides; the
--                distance and the compass direction stay, because those are
--                still true.
--   other-map  - the target is in another zone. A bearing across two maps
--                points nowhere, so there is no arrow: just the zone name and
--                the coordinates as text.
--   arrived    - close enough that an arrow would only spin.
--
-- Updates are driven by one throttled ticker at 10 Hz, started when a target is
-- set and stopped the moment it is cleared. Nothing runs per frame, and nothing
-- runs at all with no target.
local ADDON, ns = ...

local U = ns.Util
local W = ns.Widgets
local Geo = ns.Geo

local Arrow = {}
ns.Arrow = Arrow

Arrow.UPDATE_INTERVAL = 0.1   -- 10 times a second, the cap the design asks for
Arrow.SIZE = 150

Arrow.target = nil     -- { mapID, x, y, title, zone }
Arrow.ticker = nil
Arrow.state = nil

-- Build -----------------------------------------------------------------

function Arrow:Build()
    if self.frame then return self.frame end

    local f = CreateFrame("Button", "ForeverPilotArrow", UIParent)
    self.frame = f
    f:SetSize(Arrow.SIZE, 92)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:Hide()
    W.Backdrop(f, 0.04, 0.04, 0.06, 0.72, 0.12)

    local hl = f:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(f)
    hl:SetColorTexture(1, 1, 1, 0.04)

    -- The arrow itself. A plain texture we rotate: no model frame, no sprite
    -- sheet, so it works on any client that can rotate a texture at all.
    local dial = CreateFrame("Frame", nil, f)
    dial:SetSize(40, 40)
    dial:SetPoint("TOP", 0, -8)
    f.dial = dial

    local glyph = dial:CreateTexture(nil, "ARTWORK")
    glyph:SetAllPoints(dial)
    glyph:SetTexture("Interface\\Minimap\\MinimapArrow")
    glyph:SetVertexColor(0.45, 0.80, 1.0, 1)
    f.glyph = glyph

    -- Shown instead of the arrow when there is nothing to rotate it by.
    f.compass = W.Label(f, "", W.FONT_NORMAL, 0.85, 0.85, 0.85)
    f.compass:SetPoint("TOP", 0, -16)
    f.compass:SetJustifyH("CENTER")
    f.compass:Hide()

    f.distance = W.Label(f, "", W.FONT_NORMAL, 1, 0.82, 0)
    f.distance:SetPoint("TOP", dial, "BOTTOM", 0, -2)
    f.distance:SetJustifyH("CENTER")
    f.distance:SetPoint("LEFT", f, "LEFT", 4, 0)
    f.distance:SetPoint("RIGHT", f, "RIGHT", -4, 0)

    f.label = W.Label(f, "", W.FONT_SMALL, 0.70, 0.70, 0.70)
    f.label:SetPoint("TOP", f.distance, "BOTTOM", 0, -2)
    f.label:SetPoint("LEFT", f, "LEFT", 4, 0)
    f.label:SetPoint("RIGHT", f, "RIGHT", -4, 0)
    f.label:SetJustifyH("CENTER")
    f.label:SetWordWrap(true)
    f.label:SetHeight(24)

    f.close = W.Button(f, ns.GLYPH.CLOSE, 16, 14, function() Arrow:Clear() end)
    f.close:SetPoint("TOPRIGHT", -3, -3)

    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f:SetScript("OnDragStart", function(self2)
        if ns.Config:Get().nav.locked then return end
        self2:StartMoving()
        Arrow.dragging = true
    end)
    f:SetScript("OnDragStop", function(self2)
        self2:StopMovingOrSizing()
        Arrow.dragging = nil
        Arrow:SavePosition()
    end)
    f:SetScript("OnClick", function(_, button)
        if Arrow.dragging then return end
        if button == "RightButton" then Arrow:Clear() end
    end)
    f:SetScript("OnEnter", function(self2)
        local lines = {
            "Правый щелчок — убрать стрелку",
        }
        if not ns.Config:Get().nav.locked then
            table.insert(lines, 1, "Потяните, чтобы передвинуть")
        end
        if Arrow.state and Arrow.state.reason == "no-facing" then
            table.insert(lines, "Игра не сообщает, куда вы смотрите,"
                .. " поэтому стрелку повернуть нечем — направление по карте выше.")
        end
        if Arrow.state and Arrow.state.reason == "other-map" then
            table.insert(lines, "Цель в другой зоне — стрелка здесь бессмысленна.")
        end
        W.ShowTip(self2, Arrow.target and Arrow.target.title or "Цель", lines)
    end)
    f:SetScript("OnLeave", W.HideTip)

    Arrow:ApplyPosition()
    Arrow:ApplyScale()
    return f
end

-- Geometry --------------------------------------------------------------

function Arrow:SavePosition()
    if not self.frame then return end
    local left, bottom = self.frame:GetLeft(), self.frame:GetBottom()
    if left and bottom then
        ns.Config:Get().nav.pos = { U.round(left), U.round(bottom) }
    end
end

function Arrow:ApplyPosition()
    if not self.frame then return end
    local cfg = ns.Config:Get()
    local pos = cfg.nav.pos
    -- Та же проверка, что у окна и у панели: координаты могли быть годными на
    -- прошлом разрешении. Стрелка меньше остальных, и потерять её за краем
    -- проще всего — а без неё «Показать путь» выглядит как кнопка, которая
    -- ничего не делает.
    if type(pos) == "table" and tonumber(pos[1]) and tonumber(pos[2]) then
        local w = self.frame:GetWidth() or 90
        local h = self.frame:GetHeight() or 90
        local sw = (UIParent and UIParent.GetWidth and UIParent:GetWidth()) or nil
        local sh = (UIParent and UIParent.GetHeight and UIParent:GetHeight()) or nil
        if U.frameOffScreen(pos[1], pos[2], pos[1] + w, pos[2] + h, sw, sh) then
            cfg.nav.pos = nil
            pos = nil
            ns.Api:Print("стрелка была за краем экрана — поставил её на место")
        end
    end
    self.frame:ClearAllPoints()
    if type(pos) == "table" and pos[1] and pos[2] then
        self.frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", pos[1], pos[2])
    else
        self.frame:SetPoint("CENTER", UIParent, "CENTER", 220, 60)
    end
end

function Arrow:ResetPosition()
    ns.Config:Get().nav.pos = nil
    self:ApplyPosition()
end

function Arrow:ApplyScale()
    if not self.frame then return end
    self.frame:SetScale(U.clamp(ns.Config:Get().nav.scale or 1, 0.7, 1.6))
end

-- Target ----------------------------------------------------------------

-- Point at a place. Returns ok, reason - and the reason matters, because the
-- caller tells the player what happened.
function Arrow:SetTarget(place, title)
    if type(place) ~= "table" then return false, "no-place" end
    if not (place.mapID and place.x and place.y) then return false, "no-coords" end

    local cfg = ns.Config:Get()
    if cfg.nav.provider == "off" then return false, "disabled" end

    -- TomTom only when the player asked for it.
    if cfg.nav.provider == "tomtom" then
        local ok, reason = ns.Api:TomTomWaypoint(place.mapID, place.x, place.y,
            title or place.name)
        if ok then return true, nil, "tomtom" end
        if reason == "no-tomtom" then
            ns.Api:Print("TomTom выбран в настройках, но не загружен — рисую свою стрелку")
        else
            return false, reason, "tomtom"
        end
    end

    self.target = {
        mapID = place.mapID, x = place.x, y = place.y,
        title = title or place.name or "Цель",
        zone = place.zone,
    }
    self:Build()
    self:Start()
    self:Update()
    return true, nil, "own"
end

function Arrow:Clear()
    self.target = nil
    self.state = nil
    self:Stop()
    if self.frame then self.frame:Hide() end
end

function Arrow:HasTarget()
    return self.target ~= nil
end

-- Ticker ----------------------------------------------------------------
-- Runs only while a target is set. Stopped on clear, on arrival and in combat.

function Arrow:Start()
    if self.ticker then return end
    self.ticker = W.Ticker(Arrow.UPDATE_INTERVAL, function() Arrow:Update() end)
end

function Arrow:Stop()
    if self.ticker then
        self.ticker:Cancel()
        self.ticker = nil
    end
end

-- Guarded because this runs on a ticker: an unguarded error here would spam
-- the error frame ten times a second.
function Arrow:Update()
    local ok = ns.Diag:Guard("Arrow:Update", Arrow.UpdateInner, self)
    if not ok then
        -- A failing arrow must not keep failing. Stop the ticker and leave the
        -- window showing whatever it last managed to draw.
        self:Stop()
    end
    return ok
end

function Arrow:UpdateInner()
    if not self.target then self:Stop(); return end
    if not self.frame then return end
    if ns.Config:Get().nav.provider == "off" then self:Clear(); return end

    local player = ns.Api:NavPlayerState()
    local worldSize = ns.Api:MapWorldSize(self.target.mapID)
    local solution = Geo.Solve(player, self.target, worldSize)
    self.state = solution
    self:Paint(solution)
end

-- Paint -----------------------------------------------------------------

function Arrow:Paint(s)
    local f = self.frame
    if not f then return end
    f:Show()

    -- U.fitChars, а не U.truncate: подпись стрелки - тот же заголовок совета, и
    -- резать в нём число («Предмет #249429») нельзя.
    f.label:SetText(U.fitChars(self.target.title or "", 54))

    if s.reason == "no-player" then
        f.dial:Hide(); f.compass:Hide()
        f.distance:SetText("не вижу, где вы")
        f.distance:SetTextColor(0.85, 0.55, 0.45)
        return
    end

    if s.reason == "other-map" then
        -- A bearing between two different maps is meaningless, so there is no
        -- arrow. The zone and the coordinates are still exactly what the player
        -- needs to get going.
        f.dial:Hide()
        f.compass:Show()
        f.compass:SetText(self.target.zone or "другая зона")
        f.distance:SetText(string.format("%.1f  %.1f",
            (self.target.x or 0) * 100, (self.target.y or 0) * 100))
        f.distance:SetTextColor(0.80, 0.80, 0.80)
        return
    end

    if s.arrived then
        f.dial:Hide()
        f.compass:Show()
        f.compass:SetText("на месте")
        f.compass:SetTextColor(0.45, 0.85, 0.45)
        f.distance:SetText("")
        self:Stop()  -- nothing left to track
        return
    end

    -- Distance, in yards when the client told us the map's size and in plain
    -- words when it did not. We never print a number in a unit we invented.
    local distanceText
    if s.yards then
        distanceText = Geo.DistanceText(s.yards)
    else
        distanceText = Geo.RoughText(s.mapDistance)
    end
    f.distance:SetText(distanceText or "")
    f.distance:SetTextColor(1, 0.82, 0)

    if s.rotation then
        f.dial:Show()
        f.compass:Hide()
        f.glyph:SetRotation(s.rotation)
        -- Blue far away, green as you close in: a continuous cue, not a jump.
        local near = 0
        if s.yards then
            near = U.clamp(1 - (s.yards / 300), 0, 1)
        elseif s.mapDistance then
            near = U.clamp(1 - (s.mapDistance / 0.35), 0, 1)
        end
        f.glyph:SetVertexColor(0.45 - 0.1 * near, 0.80 + 0.05 * near, 1.0 - 0.55 * near, 1)
    else
        -- no-facing: the direction is known, it just cannot be drawn.
        f.dial:Hide()
        f.compass:Show()
        f.compass:SetText(s.compass or "направление неизвестно")
        f.compass:SetTextColor(0.85, 0.85, 0.85)
    end
end

-- Lifecycle -------------------------------------------------------------

function Arrow:OnCombat(inCombat)
    if inCombat then
        self:Stop()
        if self.frame and ns.Config:Get().nav.hideInCombat then self.frame:Hide() end
    elseif self.target then
        if self.frame then self.frame:Show() end
        self:Start()
        self:Update()
    end
end

function Arrow:Describe()
    if not self.target then return nil end
    local s = self.state
    if not s then return self.target.title end
    if s.reason == "other-map" then
        return (self.target.zone or "другая зона") .. ", стрелки нет"
    end
    if s.reason == "no-facing" then
        return (s.compass or "направление") .. ", стрелку повернуть нечем"
    end
    if s.arrived then return "на месте" end
    if s.yards then return Geo.DistanceText(s.yards) end
    return Geo.RoughText(s.mapDistance)
end

return Arrow
