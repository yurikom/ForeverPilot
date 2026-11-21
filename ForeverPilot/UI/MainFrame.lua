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

Main.TABS = {
    { key = "NOW",    label = "Сейчас",       module = "TabNow" },
    { key = "CHAR",   label = "Мой персонаж", module = "TabCharacter" },
    { key = "CRAFT",  label = "Крафт",        module = "TabCraft" },
    { key = "CONFIG", label = "Настройки",    module = "TabSettings" },
}

Main.MIN_WIDTH, Main.MIN_HEIGHT = 560, 400

function Main:Build()
    if self.frame then return self.frame end

    local f = CreateFrame("Frame", "ForeverPilotFrame", UIParent)
    self.frame = f
    f:SetFrameStrata("MEDIUM")
    f:SetToplevel(true)
    f:Hide()
    W.Backdrop(f, 0.04, 0.04, 0.05, 0.95, 0.16)

    f:SetMovable(true)
    f:SetResizable(true)
    -- Прижать к экрану. Без этого окно утаскивается за край мышью, а сохранённая
    -- позиция возвращает его туда же после перезагрузки — и схватить его нечем.
    -- У панели и у стрелки это стояло с самого начала, у окна — нет.
    f:SetClampedToScreen(true)
    if f.SetResizeBounds then
        f:SetResizeBounds(Main.MIN_WIDTH, Main.MIN_HEIGHT)
    elseif f.SetMinResize then
        f:SetMinResize(Main.MIN_WIDTH, Main.MIN_HEIGHT)
    end
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

    -- Title bar.
    local title = W.Label(f, "ForeverPilot", W.FONT_TITLE, 1, 0.82, 0)
    title:SetPoint("TOPLEFT", 14, -12)
    self.title = title

    self.subtitle = W.Label(f, "", W.FONT_SMALL, 0.52, 0.52, 0.52)
    self.subtitle:SetPoint("LEFT", title, "RIGHT", 10, -1)

    -- КНОПКА, НА КОТОРОЙ БЫЛО ТОЛЬКО КВАДРАТИК.
    --
    -- Подписью стоял символ ✕, которого в шрифте клиента нет: игрок видел
    -- пустой квадрат и спросил, делает ли эта кнопка вообще что-нибудь. Делала -
    -- закрывала окно, - но узнать это было нельзя: ни читаемой подписи, ни
    -- подсказки при наведении у неё не было, в отличие от соседей. Теперь
    -- подпись из ns.GLYPH (её рисует любой шрифт), и подсказка есть, как у
    -- «Обновить» и «Вернуть панель».
    local close = W.Button(f, ns.GLYPH.CLOSE, 24, 20, function() Main:Hide() end)
    close:SetPoint("TOPRIGHT", -10, -12)
    close:SetScript("OnEnter", function(self)
        self.fpBG:SetColorTexture(0.55, 0.22, 0.22, 0.95)
        W.ShowTip(self, "Закрыть окно", Main:HowToShow())
    end)
    close:SetScript("OnLeave", function(self)
        self.fpBG:SetColorTexture(0.14, 0.16, 0.22, 0.95)
        W.HideTip()
    end)

    local refresh = W.Button(f, "Обновить", 84, 20, function() Main:Rebuild(true) end)
    refresh:SetPoint("RIGHT", close, "LEFT", -6, 0)
    refresh:SetScript("OnEnter", function(self)
        self.fpBG:SetColorTexture(0.22, 0.34, 0.55, 0.95)
        W.ShowTip(self, "Пересчитать", "Обычно я пересчитываю сам, когда что-то"
            .. " меняется. Эта кнопка — если хочется прямо сейчас.")
    end)
    refresh:SetScript("OnLeave", function(self)
        self.fpBG:SetColorTexture(0.14, 0.16, 0.22, 0.95)
        W.HideTip()
    end)
    self.closeButton, self.refreshButton = close, refresh

    -- КНОПКА, КОТОРАЯ СУЩЕСТВУЕТ РОВНО ПОКА ЕСТЬ ЧТО ИСПРАВЛЯТЬ.
    --
    -- Панель шага теперь закрывается крестиком, и это создаёт новое состояние:
    -- панели нет, а как её вернуть — непонятно. Галочка в настройках и команда
    -- есть, но и то и другое надо знать. Поэтому пока панель убрана, в
    -- заголовке стоит кнопка «Вернуть панель», и путь от /fp до панели — один
    -- щелчок по видимой кнопке, а не три действия по памяти.
    --
    -- Приём у Polestar: пустое состояние несёт кнопку, устраняющую именно эту
    -- причину пустоты, и там, где кнопка бессмысленна, её нет вовсе.
    local restore = W.Button(f, "Вернуть панель", 118, 20, function()
        -- Через TurnOn, а не SetEnabled: сообщение в чат печатает он, и
        -- печатает честно — если правило боя или подземелья всё ещё держит
        -- панель скрытой, он скажет это, а не «готово».
        if ns.StepPanel then ns.StepPanel:TurnOn() end
    end)
    restore:SetPoint("RIGHT", refresh, "LEFT", -6, 0)
    restore:Hide()
    restore:SetScript("OnEnter", function(self)
        self.fpBG:SetColorTexture(0.22, 0.34, 0.55, 0.95)
        W.ShowTip(self, "Вернуть панель текущего шага",
            "Маленькая панель с одним верхним советом. Вы её убрали;"
            .. " эта кнопка ставит её обратно.")
    end)
    restore:SetScript("OnLeave", function(self)
        self.fpBG:SetColorTexture(0.14, 0.16, 0.22, 0.95)
        W.HideTip()
    end)
    self.restorePanel = restore

    -- Tab strip.
    self.tabButtons = {}
    local x = 12
    for _, def in ipairs(Main.TABS) do
        local btn = W.Chip(f, def.label, function()
            Main:Select(def.key)
        end, 24)
        btn:SetPoint("TOPLEFT", f, "TOPLEFT", x, -42)
        x = x + btn:GetWidth() + 5
        self.tabButtons[def.key] = btn
    end

    -- Content host.
    local host = CreateFrame("Frame", nil, f)
    host:SetPoint("TOPLEFT", 8, -70)
    host:SetPoint("BOTTOMRIGHT", -8, 24)
    W.Backdrop(host, 0.05, 0.05, 0.06, 0.70, 0.08)
    self.host = host

    -- Status line and resize grip.
    self.status = W.Label(f, "", W.FONT_SMALL, 0.45, 0.45, 0.45)
    self.status:SetPoint("BOTTOMLEFT", 14, 8)
    self.status:SetPoint("RIGHT", f, "RIGHT", -30, 0)
    self.status:SetJustifyH("LEFT")
    self.status:SetWordWrap(false)

    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    local gripTex = grip:CreateTexture(nil, "OVERLAY")
    gripTex:SetAllPoints()
    gripTex:SetColorTexture(1, 1, 1, 0.14)
    grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        Main:SavePosition()
        Main:RenderActive()
    end)

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

function Main:TabModule(key)
    for _, def in ipairs(Main.TABS) do
        if def.key == key then return ns[def.module] end
    end
    return nil
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

    local mod = self:TabModule(key)
    if mod then
        local built, frame = ns.Diag:Guard("Tab:Build:" .. tostring(key),
            mod.Build, mod, self.host)
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
    self.frame:SetSize(
        math.max(Main.MIN_WIDTH, ui.width or 720),
        math.max(Main.MIN_HEIGHT, ui.height or 560))
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

function Main:UpdateStatus()
    if not self.status then return end
    local meta = ns.ActionEngine.meta or {}
    local snap = ns.CharacterScanner:Get()

    local bits = {}
    if snap then
        bits[#bits + 1] = (snap.name or "?") .. ", " .. (snap.level or "?") .. " ур."
        bits[#bits + 1] = U.money(snap.money)
    end
    bits[#bits + 1] = #(ns.ActionEngine.cards or {}) .. " "
        .. U.plural(#(ns.ActionEngine.cards or {}), "совет", "совета", "советов")
    if meta.builtAt and meta.builtAt > 0 then
        local age = ns.Api:ServerTime() - meta.builtAt
        if age > 60 then bits[#bits + 1] = "обновлено " .. (U.ageText(age) or "") end
    end
    self.status:SetText(table.concat(bits, "   •   "))

    if self.subtitle then
        local profile = ns.PROFILE_LABEL[ns.Config:Profile()] or ""
        self.subtitle:SetText("профиль: " .. profile)
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
