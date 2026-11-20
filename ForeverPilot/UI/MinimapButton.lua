-- ForeverPilot / UI/MinimapButton.lua
--
-- Кнопка у миникарты: стандартное золотое кольцо, иконка внутри него и
-- перетаскивание по кромке карты.
--
-- ПОЧЕМУ ЭТОТ ФАЙЛ ВООБЩЕ ПОЯВИЛСЯ. Старая кнопка жила десятью строками в
-- MainFrame и выглядела чужой: рамка 52x52 вешалась в TOPLEFT кнопки 26x26,
-- то есть съезжала на четверть размера, иконка ничем не обрезалась, и в итоге
-- на фоне остальных аддонов это был тёмный круг без кольца. Двигать её было
-- нельзя вообще.
--
-- ЧТО ЗДЕСЬ ФАКТ, А ЧТО РЕШЕНИЕ.
--   * Пути текстур - факт: ровно эти три есть в этом клиенте, их используют
--     установленные аддоны (MiniMap-TrackingBorder - 15 мест,
--     UI-Minimap-ZoomButton-Highlight - 8, TempPortraitAlphaMask - 29).
--     Ничего не выдумано и ничего не скопировано.
--   * Размеры 31 / 53 / 17 и отступы (7,-6) - тоже факт, а не вкус: кольцо в
--     этой текстуре нарисовано со смещением, поэтому рамка крупнее кнопки,
--     вешается в TOPLEFT, а иконка сдвигается внутрь. Ровно эти числа
--     использует OpenMap (MIT) на этом же клиенте, и его кнопка выглядит как
--     все остальные - по ней и сверено. Код свой; у OpenMap лицензия
--     разрешает и копирование, но копировать не пришлось.
--   * Позиция хранится УГЛОМ, а не координатами: миникарта бывает разного
--     размера, а Leatrix_Plus умеет делать её квадратной и подменять
--     GetMinimapShape. Координаты, посчитанные для круга 140 пикселей, на
--     квадрате 200 оказались бы внутри карты.
--
-- Всё внешнее - через проверку наличия: клиент может не отдать ни курсор, ни
-- форму карты, и тогда кнопка просто остаётся там, где стояла.
local ADDON, ns = ...

local MB = {}
ns.MinimapButton = MB

-- Разметка. Кнопка 31, кольцо 53 в TOPLEFT, тёмная подложка 20 в (7,-5),
-- иконка 17 в (7,-6).
MB.SIZE          = 31
MB.BORDER_SIZE   = 53
MB.BACKDROP_SIZE = 20
MB.ICON_SIZE     = 17
MB.ICON_OFFSET   = { 7, -6 }
MB.BACKDROP_OFFSET = { 7, -5 }
-- Насколько кнопка отстоит от кромки карты. Радиус считается от РАЗМЕРА
-- миникарты плюс этот отступ, а не фиксированным числом: иначе на увеличенной
-- карте кнопка уезжает внутрь, а на уменьшенной висит в воздухе.
MB.RADIUS_PAD  = 5
MB.DEFAULT_ANGLE = 135   -- слева сверху, там же, где кнопка стояла раньше

MB.TEXTURE_BORDER    = "Interface\\Minimap\\MiniMap-TrackingBorder"
MB.TEXTURE_BACKDROP  = "Interface\\Minimap\\UI-Minimap-Background"
MB.TEXTURE_HIGHLIGHT = "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight"
MB.TEXTURE_MASK      = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
MB.TEXTURE_ICON      = "Interface\\Icons\\INV_Misc_PocketWatch_01"

-- Геометрия ------------------------------------------------------------
--
-- Чистая функция: ни фреймов, ни клиента. Поэтому её можно проверить тестом,
-- а не только глазами в игре.
--
-- Возвращает смещение от ЦЕНТРА миникарты. Для круглой карты это точка на
-- окружности; для квадратной - на её кромке, иначе кнопка повиснет в стороне
-- от карты.
function MB.Place(angleDeg, width, height, shape)
    angleDeg = tonumber(angleDeg) or MB.DEFAULT_ANGLE
    angleDeg = angleDeg % 360
    local w = (tonumber(width) or 140) / 2 + MB.RADIUS_PAD
    local h = (tonumber(height) or tonumber(width) or 140) / 2 + MB.RADIUS_PAD

    local rad = math.rad(angleDeg)
    local cos, sin = math.cos(rad), math.sin(rad)

    if shape == "SQUARE" then
        -- Луч из центра до кромки прямоугольника: делим на большую из
        -- относительных проекций, и та из координат, что дошла до края,
        -- оказывается ровно на нём.
        local scale = math.max(math.abs(cos) / w, math.abs(sin) / h)
        if scale <= 0 then return w, 0 end
        return cos / scale, sin / scale
    end

    return w * cos, h * sin
end

-- Форма миникарты. GetMinimapShape - соглашение, которым аддоны (в том числе
-- Leatrix_Plus) сообщают, что сделали карту квадратной. Нет функции - считаем
-- карту круглой, как она и выглядит по умолчанию.
function MB:Shape()
    local fn = _G.GetMinimapShape
    if type(fn) ~= "function" then return "ROUND" end
    local ok, shape = pcall(fn)
    if not ok or type(shape) ~= "string" then return "ROUND" end
    if shape:find("SQUARE") then return "SQUARE" end
    return "ROUND"
end

function MB:Reposition()
    local btn = self.button
    if not btn or not _G.Minimap then return end
    local w = (_G.Minimap.GetWidth and _G.Minimap:GetWidth()) or 140
    local h = (_G.Minimap.GetHeight and _G.Minimap:GetHeight()) or w
    local x, y = MB.Place(ns.Config:MinimapAngle(), w, h, self:Shape())
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", _G.Minimap, "CENTER", x, y)
end

-- Угол по положению курсора. nil, когда клиент не отдаёт ни курсор, ни центр
-- карты: тогда кнопка остаётся на месте, а не прыгает в ноль.
function MB:AngleFromCursor()
    local getPos = _G.GetCursorPosition
    local map = _G.Minimap
    if type(getPos) ~= "function" or not map or not map.GetCenter then return nil end
    local okC, cx, cy = pcall(map.GetCenter, map)
    if not okC or type(cx) ~= "number" or type(cy) ~= "number" then return nil end
    local okP, mx, my = pcall(getPos)
    if not okP or type(mx) ~= "number" or type(my) ~= "number" then return nil end
    local scale = (map.GetEffectiveScale and map:GetEffectiveScale()) or 1
    if type(scale) ~= "number" or scale == 0 then scale = 1 end
    mx, my = mx / scale, my / scale
    if mx == cx and my == cy then return nil end
    return math.deg(math.atan2(my - cy, mx - cx)) % 360
end

-- Создание и показ -----------------------------------------------------

function MB:Apply()
    local cfg = ns.Config:Get()
    if not (cfg and cfg.ui and cfg.ui.minimapButton) then
        if self.button then self.button:Hide() end
        return self.button
    end
    if self.button then
        self.button:Show()
        self:Reposition()
        return self.button
    end
    if not _G.Minimap or type(_G.CreateFrame) ~= "function" then return nil end

    local btn = _G.CreateFrame("Button", "ForeverPilotMinimapButton", _G.Minimap)
    self.button = btn
    btn:SetSize(MB.SIZE, MB.SIZE)
    btn:SetFrameStrata("MEDIUM")
    -- Выше самой миникарты, иначе кольцо и иконка окажутся под ней.
    local base = (_G.Minimap.GetFrameLevel and _G.Minimap:GetFrameLevel()) or 0
    btn:SetFrameLevel((tonumber(base) or 0) + 8)
    if btn.SetClampedToScreen then btn:SetClampedToScreen(true) end

    -- Тёмная подложка под иконкой: без неё иконка висит на прозрачном фоне и
    -- кнопка выглядит светлее остальных.
    local backdrop = btn:CreateTexture(nil, "BACKGROUND")
    self.backdrop = backdrop
    backdrop:SetTexture(MB.TEXTURE_BACKDROP)
    backdrop:SetSize(MB.BACKDROP_SIZE, MB.BACKDROP_SIZE)
    backdrop:SetPoint("TOPLEFT", btn, "TOPLEFT",
        MB.BACKDROP_OFFSET[1], MB.BACKDROP_OFFSET[2])

    local icon = btn:CreateTexture(nil, "ARTWORK")
    self.icon = icon
    icon:SetTexture(MB.TEXTURE_ICON)
    icon:SetSize(MB.ICON_SIZE, MB.ICON_SIZE)
    -- Не по центру кнопки: центр кольца в этой текстуре смещён, и иконка
    -- ставится по нему, иначе она съезжает вниз-вправо.
    icon:SetPoint("TOPLEFT", btn, "TOPLEFT",
        MB.ICON_OFFSET[1], MB.ICON_OFFSET[2])
    -- Обрезаем квадратную иконку, чтобы её углы не выпирали из кольца.
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    -- А если клиент умеет маски - делаем её по-настоящему круглой. Умеет не
    -- каждый, поэтому через проверку: без маски обрезки выше уже достаточно.
    if type(icon.SetMask) == "function" then
        local ok = pcall(icon.SetMask, icon, MB.TEXTURE_MASK)
        if ns.Diag then
            ns.Diag:Call("Texture:SetMask", ok and true or nil,
                ok and "иконка в круглой маске"
                   or "маска не применилась — иконка просто обрезана")
        end
    elseif ns.Diag then
        ns.Diag:Call("Texture:SetMask", nil,
            "клиент не умеет маски текстур — иконка просто обрезана")
    end

    local border = btn:CreateTexture(nil, "OVERLAY")
    self.border = border
    border:SetTexture(MB.TEXTURE_BORDER)
    border:SetSize(MB.BORDER_SIZE, MB.BORDER_SIZE)
    -- Кольцо нарисовано с запасом вокруг иконки, поэтому крупнее кнопки и
    -- вешается в TOPLEFT: так центр кольца совпадает с центром кнопки.
    border:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)

    btn:SetHighlightTexture(MB.TEXTURE_HIGHLIGHT)

    btn:RegisterForDrag("LeftButton")
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    btn:SetScript("OnClick", function(frame, mouseButton)
        -- Shift+ЛКМ — показать/убрать панель шага. Это третий путь вернуть
        -- панель после того, как её закрыли крестиком, и единственный, который
        -- не требует ни открывать окно, ни помнить команду. Shift проверяется
        -- через наличие функции: клиент может её не отдать, и тогда щелчок
        -- просто остаётся обычным.
        local shift = _G.IsShiftKeyDown
        if mouseButton == "LeftButton" and type(shift) == "function" then
            local ok, down = pcall(shift)
            if ok and down and ns.StepPanel then
                -- Сообщение печатает сам Toggle: одна формулировка на все пути.
                ns.StepPanel:Toggle()
                -- Подсказка перерисовывается на месте, чтобы в ней было
                -- написано, что сделает СЛЕДУЮЩИЙ щелчок, а не предыдущий.
                -- Приём у Polestar (изучен, не скопирован; GPL-3.0).
                local enter = frame.GetScript and frame:GetScript("OnEnter")
                if enter then pcall(enter, frame) end
                return
            end
        end
        if mouseButton == "RightButton" then
            ns.MainFrame:Select("CONFIG")
            if not ns.MainFrame:IsShown() then ns.MainFrame:Toggle() end
            return
        end
        ns.MainFrame:Toggle()
    end)
    btn:SetScript("OnEnter", function(frame)
        if MB.dragging then return end
        local lines = {
            "Что делать дальше: крафт, покупки, чары, продажа.",
            "Левый щелчок — открыть окно, правый — настройки.",
        }
        -- Состояние панели называется прямо здесь, потому что это единственное
        -- место, где игрок на него смотрит, не открывая ничего.
        local panelOn = ns.StepPanel and ns.StepPanel:IsEnabled()
        lines[#lines + 1] = panelOn
            and "Shift и левый щелчок — убрать панель текущего шага."
            or "|cffffcc40Панель текущего шага убрана.|r Shift и левый щелчок — вернуть."
        lines[#lines + 1] = "Тянуть — переставить кнопку по кромке карты."
        ns.Widgets.ShowTip(frame, "ForeverPilot", lines)
    end)
    btn:SetScript("OnLeave", function() ns.Widgets.HideTip() end)

    btn:SetScript("OnDragStart", function(frame)
        MB.dragging = true
        ns.Widgets.HideTip()
        frame:SetScript("OnUpdate", MB.OnDragUpdate)
    end)
    btn:SetScript("OnDragStop", function(frame)
        MB.dragging = nil
        frame:SetScript("OnUpdate", nil)
        -- Последнее положение курсора уже записано в настройки на OnUpdate;
        -- здесь только фиксируем кнопку по нему.
        MB:Reposition()
    end)

    self:Reposition()
    return btn
end

-- Пока кнопку тянут: угол считается по курсору и сразу же сохраняется, чтобы
-- после /reload кнопка осталась там, куда её поставили.
function MB.OnDragUpdate(frame)
    local angle = MB:AngleFromCursor()
    if not angle then return end
    ns.Config:SetMinimapAngle(angle)
    MB:Reposition()
end

return MB
