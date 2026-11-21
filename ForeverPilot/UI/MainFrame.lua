-- ForeverPilot / UI/MainFrame.lua
--
-- The window: four tabs, movable, resizable, scalable, and it remembers where
-- the player left it. "Сейчас" is open by default, so opening the addon is
-- already the answer.
local ADDON, ns = ...

local U = ns.Util
local W = ns.Widgets

local Main = {}
ns.MainFrame = Main

-- РАЗДЕЛЫ ОКНА - КНОПКАМИ В ЛЕВОЙ ПОЛОСЕ, как в большом окне Polestar: значок и
-- подпись, выбранный раздел светлее, с золотой полоской и золотым значком.
-- «Настройки» стоят внизу полосы, отдельно от рабочих разделов.
--
-- glyph - значок из своего набора (Media\icon-*.tga); icon - картинка игры на то
--         время, пока клиент своих файлов не видит (до перезапуска игры).
-- full  - раздел занимает всю площадь окна (у «Советов» свои колонки и шапка).
--         У остальных шапку с названием и строкой «что здесь» рисует само окно.
--
-- РАЗДЕЛОВ ТРИ. Было четыре: ещё «Персонаж» (что аддон знает о персонаже) и
-- «Крафт» (любой рецепт до материалов). Игрок спросил про оба, зачем они
-- (2026-11-21): уровень и профессии он знает сам, а крафтит в окне профессии.
-- «Персонаж» убран; от «Крафта» оставлено то, чего в игре нет, - общий список
-- покупок под все советы, и раздел назван тем, что в нём лежит.
Main.TABS = {
    { key = "NOW",    label = "Советы",    module = "TabNow", full = true, glyph = "bulb",
      icon = "Interface\\Icons\\INV_Misc_Note_01" },
    { key = "CRAFT",  label = "Покупки",   module = "TabCraft", glyph = "wallet",
      icon = "Interface\\Icons\\INV_Misc_Bag_08",
      about = "Всё, что нужно докупить для советов: что, где и почём." },
    { key = "CONFIG", label = "Настройки", module = "TabSettings", bottom = true, glyph = "sliders",
      icon = "Interface\\Icons\\Trade_Engineering",
      about = "Вид окна, панель шага, навигация и то, что учитывать в советах." },
}

-- РАЗМЕТКА ОКНА, ЧИСЛАМИ В ОДНОМ МЕСТЕ.
Main.RAIL_W = 68             -- полоса разделов слева
Main.RAIL_BUTTON_H = 52
Main.RAIL_TOP = 62           -- первая кнопка полосы, под значком аддона
Main.BAND_H = 78             -- шапка раздела (у «Советов» своя)
Main.STATUS_W = 156          -- строка «кто и сколько золота» под фильтром
-- Три колонки «Советов»: фильтр, список, карточка совета - плюс полоса
-- разделов. Меньше этого окно не сжимается.
Main.MIN_WIDTH, Main.MIN_HEIGHT = 860, 480
Main.DEFAULT_WIDTH, Main.DEFAULT_HEIGHT = 1000, 600
-- И БОЛЬШЕ ЭКРАНА НЕ РАСТЁТ. Игрок растянул окно за край экрана, угол для
-- изменения размера уехал туда же, и вернуть окно стало нечем (2026-11-21:
-- «кроме как закрыть, не могу ни сузить, ни чё»). Окно занимает не больше этой
-- доли экрана - и при растягивании, и при открытии с сохранённым размером.
Main.SCREEN_SHARE = 0.94

-- Свой значок аддона. Файл клиент видит только после полного перезапуска игры;
-- до тех пор стоит запасной значок из игры.
Main.LOGO = "Interface\\AddOns\\ForeverPilot\\Media\\Icon"
Main.LOGO_FALLBACK = "Interface\\Icons\\INV_Misc_PocketWatch_01"

-- Площадь разделов по размеру окна. Одна функция на код и на проверки
-- (Tests/uistub.lua, S.layout): числа разметки не повторяются в двух местах.
function Main.HostSize(width, height)
    return (tonumber(width) or 0) - Main.RAIL_W - 2, (tonumber(height) or 0) - 2
end

-- Сколько места на экране - в единицах самого окна (у окна свой масштаб).
function Main:ScreenLimit()
    local parent = _G.UIParent
    local sw = parent and parent.GetWidth and tonumber(parent:GetWidth()) or 0
    local sh = parent and parent.GetHeight and tonumber(parent:GetHeight()) or 0
    if sw <= 0 or sh <= 0 then return nil end
    local scale = ns.Config:Scale()
    return math.floor(sw / scale * Main.SCREEN_SHARE), math.floor(sh / scale * Main.SCREEN_SHARE)
end

-- Размер окна в допустимых пределах: не меньше минимума и не больше экрана.
-- Если экран меньше минимума (очень крупный масштаб), побеждает экран: тесное
-- окно лучше окна, до угла которого не дотянуться.
function Main:FitSize(width, height)
    width = math.max(Main.MIN_WIDTH, tonumber(width) or Main.DEFAULT_WIDTH)
    height = math.max(Main.MIN_HEIGHT, tonumber(height) or Main.DEFAULT_HEIGHT)
    local maxW, maxH = self:ScreenLimit()
    if maxW then
        width = math.min(width, maxW)
        height = math.min(height, maxH)
    end
    return math.floor(width), math.floor(height)
end

function Main:ApplyResizeBounds()
    local f = self.frame
    if not f then return end
    local maxW, maxH = self:ScreenLimit()
    local minW, minH = Main.MIN_WIDTH, Main.MIN_HEIGHT
    if maxW then
        minW, minH = math.min(minW, maxW), math.min(minH, maxH)
    end
    if f.SetResizeBounds then
        if maxW then
            f:SetResizeBounds(minW, minH, maxW, maxH)
        else
            f:SetResizeBounds(minW, minH)
        end
    elseif f.SetMinResize then
        f:SetMinResize(minW, minH)
        if maxW and f.SetMaxResize then f:SetMaxResize(maxW, maxH) end
    end
end

function Main:Build()
    if self.frame then return self.frame end

    local f = CreateFrame("Frame", "ForeverPilotFrame", UIParent)
    self.frame = f
    f:SetFrameStrata("MEDIUM")
    f:SetToplevel(true)
    f:Hide()
    local T = W.THEME
    W.Backdrop(f, T.bg[1], T.bg[2], T.bg[3], 1, 0.16)

    f:SetMovable(true)
    f:SetResizable(true)
    -- Прижать к экрану. Без этого окно утаскивается за край мышью, а сохранённая
    -- позиция возвращает его туда же после перезагрузки — и схватить его нечем.
    -- У панели и у стрелки это стояло с самого начала, у окна — нет.
    f:SetClampedToScreen(true)
    Main:ApplyResizeBounds()
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        Main:SavePosition()
    end)
    f:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            Main:Hide()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)
    f:EnableKeyboard(true)
    f:SetPropagateKeyboardInput(true)
    table.insert(UISpecialFrames, "ForeverPilotFrame")

    -- ЗАКРЫТИЕ ЛЮБЫМ ПУТЁМ ПОПАДАЕТ В ОДНО МЕСТО.
    --
    -- Закрыть окно можно не только нашим крестиком: Esc через UISpecialFrames
    -- зовёт Hide у самого фрейма и мимо Main:Hide проходит насквозь. Если
    -- состояние пишет только Main:Hide, то окно, закрытое по Esc, вернётся само
    -- при следующем входе в игру — и игрок решит, что крестик не работает.
    --
    -- Hook, а не SetScript: свой OnHide у окна может появиться позже, и затирать
    -- его нельзя. Скрытие по правилам (бой) ставит suppress и сюда не доходит -
    -- это приём Polestar (изучен, не скопирован; GPL-3.0): правила никогда не
    -- переписывают выбор игрока, иначе после первой драки окно перестанет
    -- возвращаться.
    f:HookScript("OnHide", function()
        if Main.rulesHiding then return end
        -- ВЕСЬ ИНТЕРФЕЙС СПРЯТАН - ЭТО НЕ ЗАКРЫТИЕ ОКНА.
        --
        -- Alt+Z, кинематика, загрузочный экран: клиент скрывает UIParent, и
        -- OnHide приходит каждому дочернему окну. Без этой проверки скриншот по
        -- Alt+Z стоил бы игроку запомненного состояния окна и строки в чат, а
        -- после перезагрузки окно бы не вернулось.
        local parentHidden = UIParent and UIParent.IsShown
            and not UIParent:IsShown()
        if parentHidden then return end
        ns.Config:SetWindowShown(false)
        -- И правило боя больше не должно воскрешать окно: игрок закрыл его
        -- ПОЗЖЕ, чем бой его спрятал, и последнее слово за игроком.
        Main.wasShown = nil
        Main:SayHowToShow()
    end)

    -- ПОЛОСА РАЗДЕЛОВ -------------------------------------------------------
    local rail = CreateFrame("Frame", nil, f)
    rail:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    rail:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, 1)
    rail:SetWidth(Main.RAIL_W)
    W.Ground(rail, T.rail)
    W.Hairline(rail, "RIGHT")
    self.rail = rail

    local logo = rail:CreateTexture(nil, "ARTWORK")
    logo:SetSize(36, 36)
    logo:SetPoint("TOP", rail, "TOP", 0, -12)
    W.SetTextureOr(logo, Main.LOGO, Main.LOGO_FALLBACK)
    self.logo = logo

    self.tabButtons = {}
    local top = Main.RAIL_TOP
    for _, def in ipairs(Main.TABS) do
        local btn = W.RailButton(rail, def.glyph, def.label, function()
            Main:Select(def.key)
        end, Main.RAIL_W, Main.RAIL_BUTTON_H, def.icon)
        if def.bottom then
            btn:SetPoint("BOTTOMLEFT", rail, "BOTTOMLEFT", 0, 8)
        else
            btn:SetPoint("TOPLEFT", rail, "TOPLEFT", 0, -top)
            top = top + Main.RAIL_BUTTON_H + 2
        end
        if def.about then
            btn.tooltipTitle = def.label
            btn.tooltipText = def.about
        end
        self.tabButtons[def.key] = btn
    end

    -- КНОПКА, КОТОРАЯ СУЩЕСТВУЕТ РОВНО ПОКА ЕСТЬ ЧТО ИСПРАВЛЯТЬ.
    --
    -- Панель шага закрывается крестиком, и это создаёт состояние «панели нет, а
    -- как её вернуть — непонятно». Пока панель убрана, в полосе над
    -- «Настройками» стоит кнопка «Панель»: один щелчок по видимой кнопке, а не
    -- три действия по памяти. Там, где кнопка бессмысленна, её нет вовсе.
    local restore = W.RailButton(rail, "undo", "Панель", function()
        -- Через TurnOn, а не SetEnabled: сообщение в чат печатает он, и
        -- печатает честно — если правило боя или подземелья всё ещё держит
        -- панель скрытой, он скажет это, а не «готово».
        if ns.StepPanel then ns.StepPanel:TurnOn() end
    end, Main.RAIL_W, Main.RAIL_BUTTON_H, "Interface\\Icons\\INV_Misc_PocketWatch_01")
    restore:SetPoint("BOTTOMLEFT", rail, "BOTTOMLEFT", 0, 8 + Main.RAIL_BUTTON_H + 2)
    restore.tooltipTitle = "Вернуть панель текущего шага"
    restore.tooltipText = "Маленькая панель с одним верхним советом. Вы её убрали;"
        .. " эта кнопка ставит её обратно."
    restore:Hide()
    self.restorePanel = restore

    -- ПЛОЩАДЬ РАЗДЕЛОВ ------------------------------------------------------
    -- host - вся площадь справа от полосы: её целиком занимают «Советы».
    local host = CreateFrame("Frame", nil, f)
    host:SetPoint("TOPLEFT", f, "TOPLEFT", Main.RAIL_W + 1, -1)
    host:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    self.host = host

    -- У остальных разделов сверху шапка: название и одна строка «что здесь».
    local band = W.Band(host, Main.BAND_H)
    band:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    band:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, 0)
    band:Hide()
    self.band = band
    self.bandTitle = W.Label(band, "", W.FONT_HERO, T.text[1], T.text[2], T.text[3])
    self.bandTitle:SetPoint("TOPLEFT", band, "TOPLEFT", 24, -16)
    self.bandAbout = W.Label(band, "", W.FONT_SMALL, T.dim[1], T.dim[2], T.dim[3])
    self.bandAbout:SetPoint("TOPLEFT", band, "TOPLEFT", 24, -48)
    self.bandAbout:SetJustifyH("LEFT")
    self.bandAbout:SetWordWrap(false)

    local page = CreateFrame("Frame", nil, host)
    page:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -Main.BAND_H)
    page:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0)
    self.page = page

    -- В УГЛУ ОКНА: «обновить» и «закрыть» - значками, поверх раздела.
    --
    -- Подписью крестика когда-то стоял символ ✕, которого в шрифте клиента нет:
    -- игрок видел пустой квадрат и спросил, делает ли эта кнопка вообще
    -- что-нибудь. Теперь это свой значок, а пока клиент своих файлов не видит -
    -- буква из ns.GLYPH (её рисует любой шрифт). Подсказка есть в обоих случаях.
    local level = (f:GetFrameLevel() or 1) + 30
    local close = W.Button(f, "", 26, 26, function() Main:Hide() end)
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -10)
    close:SetFrameLevel(level)
    close:SetQuiet(true)
    close:SetGlyph("close", ns.GLYPH.CLOSE, 14)
    close:SetScript("OnEnter", function(self)
        self:Repaint(true)
        W.ShowTip(self, "Закрыть окно", Main:HowToShow())
    end)
    close:SetScript("OnLeave", function(self)
        self:Repaint(false)
        W.HideTip()
    end)

    local refresh = W.Button(f, "", W.ready and 26 or 80, 26, function() Main:Rebuild(true) end)
    refresh:SetPoint("RIGHT", close, "LEFT", -4, 0)
    refresh:SetFrameLevel(level)
    refresh:SetQuiet(true)
    refresh:SetGlyph("reload", "Обновить", 14)
    refresh:SetScript("OnEnter", function(self)
        self:Repaint(true)
        W.ShowTip(self, "Обновить", "Обычно я пересчитываю сам, когда что-то"
            .. " меняется. Эта кнопка — если хочется прямо сейчас.")
    end)
    refresh:SetScript("OnLeave", function(self)
        self:Repaint(false)
        W.HideTip()
    end)
    self.closeButton, self.refreshButton = close, refresh

    -- Кто и сколько у него золота - две тихие строки внизу колонки фильтра.
    -- Стоят на своей рамке поверх раздела: колонка фильтра - дочерняя рамка со
    -- своим фоном, и строка, нарисованная прямо на окне, оказалась бы под ним.
    local statusHost = CreateFrame("Frame", nil, f)
    statusHost:SetSize(Main.STATUS_W, 34)
    statusHost:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", Main.RAIL_W + 18, 12)
    statusHost:SetFrameLevel(level)
    self.statusHost = statusHost
    self.status = W.Label(statusHost, "", W.FONT_CAPTION, T.muted[1], T.muted[2], T.muted[3])
    self.status:SetPoint("BOTTOMLEFT", statusHost, "BOTTOMLEFT", 0, 0)
    self.status:SetJustifyH("LEFT")
    self.status:SetWidth(Main.STATUS_W)

    -- УГОЛ ДЛЯ ИЗМЕНЕНИЯ РАЗМЕРА.
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(18, 18)
    grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
    grip:SetFrameLevel(level)
    local gripTex = grip:CreateTexture(nil, "OVERLAY")
    gripTex:SetAllPoints()
    if not W.SetIcon(gripTex, "grip", { 1, 1, 1, 0.35 }) then
        gripTex:SetColorTexture(1, 1, 1, 0.14)
        gripTex:Show()
    end
    grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        -- Что бы ни вышло из-под мыши, размер возвращается в пределы экрана.
        local w, h = Main:FitSize(f:GetWidth(), f:GetHeight())
        f:SetSize(w, h)
        Main:SavePosition()
        Main:RenderActive()
    end)
    grip:SetScript("OnEnter", function(self)
        W.ShowTip(self, "Размер окна", "Потяните за угол. Вернуть как было — /fp reset.")
    end)
    grip:SetScript("OnLeave", W.HideTip)
    self.grip = grip

    f:SetScript("OnSizeChanged", function()
        if Main.resizeThrottle then return end
        Main.resizeThrottle = true
        W.After(0.1, function()
            Main.resizeThrottle = nil
            Main:RenderActive()
        end)
    end)

    Main:ApplyPosition()
    Main:ApplyScale()
    return f
end

-- Tabs ------------------------------------------------------------------

-- Площадь разделов ПРЯМО СЕЙЧАС - по размеру самого окна. Размер окна задан
-- явно (SetSize), поэтому он известен сразу; ширину вложенных колонок клиент
-- досчитывает позже, и на первой отрисовке она ещё нулевая.
function Main:HostNow()
    local f = self.frame
    local w = f and tonumber(f:GetWidth()) or 0
    local h = f and tonumber(f:GetHeight()) or 0
    if w <= 0 then w = Main.DEFAULT_WIDTH end
    if h <= 0 then h = Main.DEFAULT_HEIGHT end
    return Main.HostSize(w, h)
end

function Main:TabDef(key)
    for _, def in ipairs(Main.TABS) do
        if def.key == key then return def end
    end
    return nil
end

function Main:TabModule(key)
    local def = self:TabDef(key)
    return def and ns[def.module] or nil
end

-- СНАЧАЛА СПРЯТАТЬ ВСЁ, ПОТОМ ПОКАЗАТЬ ОДНО, И РИСОВАТЬ ТОЛЬКО ПОД ЗАЩИТОЙ.
--
-- Раньше это был один проход по вкладкам: он прятал вкладки, попадавшиеся до
-- выбранной, показывал выбранную и тут же звал её mod:OnShow() - НЕЗАЩИЩЁННЫМ,
-- внутри того же цикла. Любая ошибка в отрисовке роняла проход на середине, и
-- всё, до чего он не дошёл, оставалось на экране и в подсветке.
--
-- Именно это игрок и увидел: содержимое «Мой персонаж» поверх содержимого
-- «Сейчас», текст на тексте, подсвечены обе вкладки, а после следующего щелчка
-- три. Порядок вкладок объяснял и направление: переход на вкладку ЛЕВЕЕ текущей
-- оставлял текущую висеть, потому что до неё цикл уже не доходил.
--
-- Сама ошибка была в другом месте (не загружался Logic\ActionEngine.lua, см.
-- Main.MODULES), и она исправлена. Но переключение вкладок не имеет права
-- зависеть от того, чем закончилась отрисовка: сначала экран приводится в
-- единственно верное состояние - ровно одна вкладка показана и подсвечена, -
-- и только потом рисуется содержимое, под Diag:Guard. Упавшая отрисовка теперь
-- стоит пустой вкладки и записи в диагностике, а не сломанного окна.
function Main:Select(key)
    self:Build()
    -- Раздела с таким ключом нет (его убрали, а ключ остался в сохранённых
    -- настройках или в команде) - открываются «Советы».
    if not self:TabDef(key) then key = "NOW" end
    local cfg = ns.Config:Get()
    cfg.tab = key

    for _, def in ipairs(Main.TABS) do
        local btn = self.tabButtons[def.key]
        if btn then btn:SetSelected(false) end
        local mod = ns[def.module]
        if mod and mod.frame then mod.frame:Hide() end
    end

    -- Активная вкладка записана ДО отрисовки: если отрисовка упадёт, состояние
    -- всё равно непротиворечиво, а не «активна одна, показана другая».
    self.activeTab = key
    local chosen = self.tabButtons[key]
    if chosen then chosen:SetSelected(true) end

    -- Шапка раздела: у «Советов» своя, у остальных её рисует окно.
    local def = self:TabDef(key)
    if def and not def.full then
        local hostW = self:HostNow()
        self.bandTitle:SetText(def.label)
        -- Справа в шапке стоят «обновить» и «закрыть»: строке оставлено место.
        W.SetFitted(self.bandAbout, def.about or "", math.max(120, hostW - 48 - 90))
        self.band:SetStarWidth(hostW)
        self.band:Show()
    else
        self.band:Hide()
    end
    -- Строка «кто и сколько золота» стоит под фильтром - то есть только там,
    -- где он есть.
    if self.statusHost then
        if def and def.full then self.statusHost:Show() else self.statusHost:Hide() end
    end

    local mod = self:TabModule(key)
    if mod then
        local built, frame = ns.Diag:Guard("Tab:Build:" .. tostring(key),
            mod.Build, mod, (def and def.full) and self.host or self.page)
        if built and type(frame) == "table" and frame.Show then frame:Show() end
        if mod.OnShow then
            ns.Diag:Guard("Tab:OnShow:" .. tostring(key), mod.OnShow, mod)
        end
    end
    -- Строка состояния читает движок, то есть тоже может упасть. Для выбора
    -- вкладки это не повод остаться с двумя вкладками на экране.
    ns.Diag:Guard("MainFrame:UpdateStatus", Main.UpdateStatus, self)
end

function Main:RenderActive()
    local mod = self:TabModule(self.activeTab or "NOW")
    if mod and mod.frame and mod.frame:IsShown() then
        if mod.Render then
            ns.Diag:Guard("Render:" .. tostring(self.activeTab), mod.Render, mod)
        end
    end
end

-- Show / hide -----------------------------------------------------------

function Main:Show()
    self:Build()
    self.frame:Show()
    -- Явно поднять. SetToplevel делает это при щелчке, но окно, открытое
    -- командой или кнопкой у миникарты, щелчка не видело и может оказаться под
    -- чужим окном той же страты — а игрок решит, что /fp не сработал.
    if self.frame.Raise then self.frame:Raise() end
    ns.Config:SetWindowShown(true)
    self.saidHowToShow = nil
    -- Zero clicks to an answer: the default tab is the ranked list.
    self:Select(ns.Config:Get().tab or "NOW")
    -- Окно открыли руками: считать надо сейчас, даже на бегу (см. ShouldDefer).
    self:Rebuild(false, { opened = true })
    -- В запомненной категории пусто, а советы есть - показываем все.
    if ns.TabNow and ns.TabNow.LeaveEmptyFilter and ns.TabNow:LeaveEmptyFilter() then
        self:RenderActive()
    end
end

function Main:Hide()
    -- Состояние и сообщение пишет хук OnHide: он один на все пути закрытия.
    if self.frame then self.frame:Hide() end
    W.HideTip()
end

function Main:Toggle()
    self:Build()
    if self.frame:IsShown() then self:Hide() else self:Show() end
end

function Main:IsShown()
    return self.frame and self.frame:IsShown()
end

-- Как вернуть окно. Собирается по доступным путям, как и у панели.
function Main:HowToShow()
    local ways = {}
    if ns.MinimapButton and ns.MinimapButton.button
        and ns.Config:Get().ui.minimapButton then
        ways[#ways + 1] = "щелчок по кнопке у миникарты"
    end
    ways[#ways + 1] = "команда /fp"
    return "Вернуть: " .. table.concat(ways, ", или ") .. "."
end

-- Сказать это один раз на закрытие, а не на каждое событие скрытия: по Esc
-- фрейм может быть скрыт и нашим обработчиком, и UISpecialFrames, и тогда
-- строка печатается дважды. Повтор одной и той же фразы подряд — это ещё одна
-- мелочь, из-за которой аддон выглядит неисправным.
function Main:SayHowToShow()
    if self.saidHowToShow then return end
    self.saidHowToShow = true
    ns.Api:Print("окно закрыто. " .. self:HowToShow())
end

-- Login: put the window back the way the player left it. Nothing happens on a
-- fresh install, where ui.shown is false.
function Main:RestoreShown()
    if not ns.Config:WindowShown() then
        self:UpdateRestoreButton()
        return false
    end
    self:Show()
    return true
end

-- The title-bar button that brings the step panel back exists only while the
-- panel is away.
function Main:UpdateRestoreButton()
    if not self.restorePanel then return end
    local away = ns.StepPanel and not ns.StepPanel:IsEnabled()
    if away then self.restorePanel:Show() else self.restorePanel:Hide() end
end

-- Layout ----------------------------------------------------------------

function Main:ApplyPosition()
    if not self.frame then return end
    local ui = ns.Config:Frame()
    self.frame:ClearAllPoints()
    self.frame:SetPoint(ui.point or "CENTER", UIParent, ui.relPoint or "CENTER",
        ui.x or 0, ui.y or 0)
    -- Сохранённый размер от прежнего окна (720 на 560) меньше нынешнего
    -- минимума: вместо того чтобы зажать три колонки в минимум, берём размер
    -- по умолчанию. Размер, выставленный игроком уже в новом окне, сохраняется.
    local width, height = tonumber(ui.width), tonumber(ui.height)
    if not width or width < Main.MIN_WIDTH then width = Main.DEFAULT_WIDTH end
    if not height or height < Main.MIN_HEIGHT then height = Main.DEFAULT_HEIGHT end
    -- И не больше экрана: сохранённый размер мог остаться от окна, растянутого
    -- за его край.
    width, height = self:FitSize(width, height)
    self.frame:SetSize(width, height)
    self:ApplyResizeBounds()
    self:RescueOffScreen()
end

-- СПАСЕНИЕ ОКНА, ОКАЗАВШЕГОСЯ ЗА КАДРОМ.
--
-- SetClampedToScreen не даёт утащить окно за край МЫШЬЮ, но ничего не делает с
-- координатами, которые были правильными на другом разрешении: сменили монитор,
-- вытащили второй, поменяли масштаб интерфейса — и окно возвращается туда, где
-- его больше нет. Схватить его нечем, потому что хватать надо как раз за то,
-- что уехало.
--
-- Проверяем ПОСЛЕ применения позиции, по настоящим границам фрейма: считать
-- геометрию самим для произвольной точки привязки значит повторять арифметику
-- клиента и ошибаться в ней. Решение принимает чистая функция из Core/Util.
function Main:RescueOffScreen()
    local f = self.frame
    if not f then return false end
    local left, bottom = f:GetLeft(), f:GetBottom()
    local right, top = f:GetRight(), f:GetTop()
    local sw = (UIParent and UIParent.GetWidth and UIParent:GetWidth()) or nil
    local sh = (UIParent and UIParent.GetHeight and UIParent:GetHeight()) or nil
    if not U.frameOffScreen(left, bottom, right, top, sw, sh) then return false end

    ns.Config:SaveFrame("CENTER", "CENTER", 0, 0)
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    ns.Api:Print("окно было за краем экрана — вернул его в центр")
    if ns.Diag then
        ns.Diag:Log("окно спасено из-за экрана", {
            left = left, bottom = bottom, screenW = sw, screenH = sh,
        })
    end
    return true
end

function Main:SavePosition()
    if not self.frame then return end
    local point, _, relPoint, x, y = self.frame:GetPoint()
    ns.Config:SaveFrame(point, relPoint, U.round(x), U.round(y),
        U.round(self.frame:GetWidth()), U.round(self.frame:GetHeight()))
end

function Main:ApplyScale()
    if not self.frame then return end
    self.frame:SetScale(ns.Config:Scale())
    -- Масштаб меняет то, сколько окна помещается на экране.
    local w, h = self:FitSize(self.frame:GetWidth(), self.frame:GetHeight())
    self.frame:SetSize(w, h)
    self:ApplyResizeBounds()
end

-- Minimap button --------------------------------------------------------
--
-- Сама кнопка живёт в UI/MinimapButton.lua: там рамка, маска, слои и езда по
-- кромке карты. Здесь только вход, которым пользуются Main.lua и настройки.
function Main:ApplyMinimapButton()
    if not ns.MinimapButton then return nil end
    local btn = ns.MinimapButton:Apply()
    self.minimapButton = ns.MinimapButton.button
    return btn
end

-- Rebuild ---------------------------------------------------------------

-- Full pipeline: rescan the character, rebuild the recipe book, rebuild the
-- cards. Called from the event scheduler, not per frame.
-- Guarded so a failure anywhere in the pipeline lands in the diagnostics file
-- with a traceback instead of taking the whole addon down.
function Main:Rebuild(force, reasons)
    local ok = ns.Diag:Guard("MainFrame:Rebuild", Main.RebuildInner, self, force, reasons)
    if not ok then
        -- The list may be half-built; say so rather than showing stale advice
        -- as if it were current.
        if self.status then
            self.status:SetText("|cffff6060пересчёт не удался — подробности в /fp diag|r")
        end
    end
    return ok
end

-- КТО-НИБУДЬ СМОТРИТ НА СОВЕТЫ? Окно или панель шага на экране.
function Main:AnyoneWatching()
    if self.frame and self.frame:IsShown() then return true end
    local P = ns.StepPanel
    if P and P.frame and P.frame.IsShown and P.frame:IsShown() then return true end
    return false
end

-- Причины, из-за которых считать надо, даже когда никто не смотрит: от них
-- зависят уведомления и суточный слепок цен, а не только картинка.
--
-- «recipes» И «prices» ЗДЕСЬ НЕТ, И ЭТО НАМЕРЕННО. Окно профессии шлёт
-- TRADE_SKILL_LIST_UPDATE на каждую сделанную вещь, а аукцион - событие на
-- каждый поиск: с ними в списке закрытый аддон дёргал бы кадр раз в полторы
-- секунды всё время, пока игрок крафтит или листает аукцион. Данные при этом
-- не теряются: окно профессии читается и кеш цен сбрасывается в самом
-- слушателе (Main.lua), до Rebuild, а список пересчитается, как только окно
-- аддона откроют.
Main.IMPORTANT_REASONS = {
    opened = true, forced = true, deferredImportant = true,
    character = true, level = true, skillcap = true, spec = true,
}

-- ОТЛОЖИТЬ ЛИ ПЕРЕСЧЁТ. Возвращает причину словом или nil.
--
-- Живые цифры (маг 31 ур., сеанс 23 минуты, окно и панель закрыты): 83 полных
-- пересчёта, в среднем 84 мс, пик 143 мс - рывок кадра раз в 17 секунд ради
-- списка, на который никто не смотрел. Правила:
--   * на бегу не считаем вовсе (кроме «окно только что открыли руками»):
--     рывок на бегу виден, на месте - нет; догоняем, когда игрок встал;
--   * никто не смотрит - считаем только по важной причине или раз в
--     ns.HIDDEN_REBUILD_SECONDS; сумки, деньги и подгрузка имён предметов сами
--     по себе пересчёта закрытого окна не стоят.
-- Принудительный пересчёт (кнопка «Обновить», смена профиля) сюда не заходит.
function Main:ShouldDefer(reasons)
    reasons = reasons or {}
    local important = false
    for flag in pairs(reasons) do
        if Main.IMPORTANT_REASONS[flag] then important = true; break end
    end
    if not reasons.opened and ns.Api.PlayerMoving and ns.Api:PlayerMoving() then
        return "moving", important
    end
    -- Идёт полоска заклинания или крафта: считать посреди неё - значит дёрнуть
    -- кадр ровно тогда, когда игрок смотрит на полоску. Догоним, когда кончится.
    if not reasons.opened and ns.Api.PlayerCasting and ns.Api:PlayerCasting() then
        return "casting", important
    end
    if self:AnyoneWatching() then
        -- СМОТРЯТ - СЧИТАЕМ, НО НЕ ЧАЩЕ РАЗА В VISIBLE_SOFT_SECONDS ПО МЕЛОЧАМ.
        -- У аукциона и торговца события идут пачками (имена предметов, сумки,
        -- деньги), и пересчёт на каждую пачку - это рывок кадра раз в полторы
        -- секунды всё время, пока окно открыто. Важная причина и жест игрока
        -- не ждут; мелочь догоняется через несколько секунд (Main:CatchUp).
        local last = self.lastBuildAt
        if (not important) and last
            and (ns.Api:Now() - last) < (ns.VISIBLE_SOFT_SECONDS or 5) then
            return "recent", important
        end
        return nil, important
    end
    if important then return nil, important end
    local last = self.lastBuildAt
    if (not last) or (ns.Api:Now() - last) >= (ns.HIDDEN_REBUILD_SECONDS or 900) then
        return nil, important
    end
    return "hidden", important
end

-- Догнать отложенное. Зовётся планировщиком раз в такт (Events:Tick); сама по
-- себе - несколько сравнений. Пересчёт случится, только когда ShouldDefer
-- перестанет возражать.
function Main:CatchUp(now)
    if not self.stale then return false end
    now = now or ns.Api:Now()
    if self.lastCatchUpTry and (now - self.lastCatchUpTry) < (ns.DEFERRED_RETRY_SECONDS or 1) then
        return false
    end
    self.lastCatchUpTry = now
    if ns.Api:InCombat() then return false end
    local reasons = { deferred = true }
    if self.staleImportant then reasons.deferredImportant = true end
    -- Окно открыто - догоняем сразу, как только можно; закрыто - ждём своей
    -- причины или своего срока, как и любой другой пересчёт.
    if self:ShouldDefer(reasons) then return false end
    return self:Rebuild(false, reasons)
end

function Main:RebuildInner(force, reasons)
    if ns.Api:InCombat() and not force then
        -- В бою не считаем, но и не забываем: догоним после.
        self.stale = true
        return
    end

    if not force then
        local why, important = self:ShouldDefer(reasons)
        if why then
            self.stale = true
            if important then self.staleImportant = true end
            if ns.Diag then ns.Diag:Count("recompute.deferred." .. why) end
            return
        end
    end
    self.stale, self.staleImportant = nil, nil
    self.lastBuildAt = ns.Api:Now()

    local snap = ns.CharacterScanner:Scan()

    -- Professions first, then the book, then the sanity check that refuses to
    -- believe a skill level of zero when we are holding recipes for it.
    ns.RecipeBook:Build(ns.CharacterScanner:CraftingProfessions(), snap.guid)
    ns.Api:SanityCheckSkills(snap.professions, function(name)
        local bucket = ns.RecipeBook:Bucket(name)
        return bucket and #bucket.list or 0
    end)
    -- The book's "missing" list has to be recomputed against crafting
    -- professions only, now that they are tagged.
    ns.RecipeBook.missingProfessions = {}
    for _, prof in ipairs(ns.CharacterScanner:CraftingProfessions()) do
        if not ns.RecipeBook:HasProfession(prof.name) then
            table.insert(ns.RecipeBook.missingProfessions, prof)
        end
    end

    ns.ActionEngine:Build()
    self:RenderActive()
    self:UpdateStatus()
    if ns.StepPanel then ns.StepPanel:Refresh() end
end

function Main:Refresh()
    self:RenderActive()
    self:UpdateStatus()
    if ns.StepPanel then ns.StepPanel:Refresh() end
end

-- Перерисовать, только если есть кому смотреть. Нужен событиям, которые
-- меняют подписи кнопок (открыли аукцион, открыли профессию), а пересчёта не
-- требуют: при закрытом окне рисовать нечего.
function Main:RefreshIfShown()
    if not self:AnyoneWatching() then return false end
    if ns.Api:InCombat() then return false end
    self:Refresh()
    return true
end

-- Rebuild the card list without rescanning the character.
--
-- Hiding a card changes which cards the engine may emit and nothing else: not
-- the bags, not the equipment, not the recipe book. Refresh() was too little -
-- it only redraws the list the engine already built, so the card the player
-- just hid stayed on screen - and Rebuild() is too much, because it rescans
-- everything for a click that moved no items. This is the middle: one
-- ActionEngine:Build, then draw.
function Main:RebuildCards()
    local ok = ns.Diag:Guard("MainFrame:RebuildCards", Main.RebuildCardsInner, self)
    if not ok and self.status then
        self.status:SetText("|cffff6060пересчёт не удался — подробности в /fp diag|r")
    end
    return ok
end

function Main:RebuildCardsInner()
    ns.ActionEngine:Build()
    self:RenderActive()
    self:UpdateStatus()
    if ns.StepPanel then ns.StepPanel:Refresh() end
end

-- КТО И СКОЛЬКО ЗОЛОТА. Раньше в этой строке стояло ещё число советов и «когда
-- обновлено»: первое видно в шапке списка, второе игроку ни к чему.
function Main:UpdateStatus()
    if not self.status then return end
    local snap = ns.CharacterScanner:Get()
    local lines = {}
    if snap then
        local who = tostring(snap.name or "?")
        if snap.level then who = who .. " · " .. tostring(snap.level) .. " ур." end
        lines[#lines + 1] = who
        lines[#lines + 1] = U.money(snap.money)
    end
    W.SetFitted(self.status, lines[1] or "", Main.STATUS_W)
    if lines[2] then
        self.status:SetText((self.status:GetText() or "") .. "\n" .. lines[2])
    end
    self:UpdateRestoreButton()
end

-- Combat ----------------------------------------------------------------

function Main:OnCombat(inCombat)
    -- The panel and the arrow have their own combat rules, and they are not the
    -- window's: a small panel is usable in a fight where the big window is not.
    if ns.StepPanel then ns.StepPanel:OnCombat(inCombat) end
    if ns.Arrow then ns.Arrow:OnCombat(inCombat) end

    if not self.frame then return end
    if inCombat then
        self.wasShown = self.frame:IsShown()
        if self.wasShown then
            -- Скрытие ПО ПРАВИЛУ, не по решению игрока: флаг держит хук OnHide
            -- от записи «окно закрыто» и от строки в чат. Иначе первая же драка
            -- означала бы, что окно больше не возвращается после перезагрузки, а
            -- в чате на каждый бой появлялась бы инструкция, как его открыть.
            self.rulesHiding = true
            self.frame:Hide()
            self.rulesHiding = nil
        end
        W.HideTip()
    elseif self.wasShown then
        self.frame:Show()
        if self.frame.Raise then self.frame:Raise() end
        self.wasShown = nil
        -- Окно вернулось на экран: это то же, что «открыли».
        self:Rebuild(false, { opened = true })
    end
end

-- Instance state, so the panel's own rule can act on it. Derived, never stored.
function Main:OnZoneChanged()
    local inInstance = false
    local fn = _G.IsInInstance
    if type(fn) == "function" then
        local ok, inside, kind = pcall(fn)
        if ok and inside then
            -- Scenarios deliberately excluded: they play like open world.
            inInstance = (kind == "party" or kind == "raid"
                or kind == "pvp" or kind == "arena")
        end
    end
    if ns.StepPanel then ns.StepPanel:OnZone(inInstance) end
end

return Main
