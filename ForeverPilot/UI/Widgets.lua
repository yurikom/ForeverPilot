-- ForeverPilot / UI/Widgets.lua
-- Small frame builders shared by every tab. Pure presentation.
local ADDON, ns = ...

local U = ns.Util
local W = {}
ns.Widgets = W

W.FONT_TITLE = "GameFontNormalLarge"
W.FONT_NORMAL = "GameFontNormal"
W.FONT_SMALL = "GameFontHighlightSmall"
W.FONT_DISABLED = "GameFontDisableSmall"

W.COLOR = {
    gold      = { 1.00, 0.82, 0.00 },
    power     = { 0.45, 0.80, 1.00 },
    skill     = { 0.70, 1.00, 0.60 },
    spend     = { 1.00, 0.55, 0.45 },
    muted     = { 0.62, 0.62, 0.62 },
    text      = { 0.92, 0.92, 0.92 },
    setup     = { 1.00, 0.72, 0.25 },
    rowOdd    = { 1, 1, 1, 0.025 },
    rowHover  = { 0.35, 0.60, 0.95, 0.12 },
    chipOn    = { 0.25, 0.50, 0.90, 0.85 },
    chipOff   = { 1, 1, 1, 0.08 },
}

function W.benefitColor(kind)
    if kind == "gold" then return W.COLOR.gold end
    if kind == "power" then return W.COLOR.power end
    if kind == "skill" then return W.COLOR.skill end
    if kind == "spend" then return W.COLOR.spend end
    if kind == "setup" then return W.COLOR.setup end
    return W.COLOR.muted
end

-- A flat background with a thin border, used for every panel in the addon.
function W.Backdrop(frame, r, g, b, a, borderAlpha)
    if frame.fpBG then
        frame.fpBG:SetColorTexture(r or 0.06, g or 0.06, b or 0.08, a or 0.92)
        return frame
    end
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(frame)
    bg:SetColorTexture(r or 0.06, g or 0.06, b or 0.08, a or 0.92)
    frame.fpBG = bg

    local edges = {}
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local line = frame:CreateTexture(nil, "BORDER")
        line:SetColorTexture(1, 1, 1, borderAlpha or 0.10)
        if side == "TOP" then
            line:SetPoint("TOPLEFT"); line:SetPoint("TOPRIGHT"); line:SetHeight(1)
        elseif side == "BOTTOM" then
            line:SetPoint("BOTTOMLEFT"); line:SetPoint("BOTTOMRIGHT"); line:SetHeight(1)
        elseif side == "LEFT" then
            line:SetPoint("TOPLEFT"); line:SetPoint("BOTTOMLEFT"); line:SetWidth(1)
        else
            line:SetPoint("TOPRIGHT"); line:SetPoint("BOTTOMRIGHT"); line:SetWidth(1)
        end
        edges[#edges + 1] = line
    end
    frame.fpEdges = edges
    return frame
end

-- ТЕКСТ, КОТОРЫЙ ВЛЕЗАЕТ, И ЧИСЛО, КОТОРОЕ НЕ РАЗРЕЗАНО -------------------
--
-- Строки карточки стоят без переноса, поэтому всё, что не влезло по ширине,
-- обрезает клиент - по пикселям, то есть посреди числа. Игрок прислал
-- скриншот: «Разница +8з 80…», «Торговец: Mister Graphed, Лесоречье, 78.2 5…»
-- и «Цены торговца —…». Обрезалось ровно то, ради чего строку читают.
--
-- Поэтому текст укорачиваем сами и до того, как до него дотянется клиент:
-- варианты даёт U.shortenings (целыми кусками, от ценного к ненужному, числа
-- не трогая), а шрифт отвечает, какой из них влезает. Выбирается ПЕРВЫЙ
-- влезающий - то есть самый ценный, а не самый длинный.
--
-- Возвращает выбранный текст и то, укорочен ли он. Кто рисует, тот обязан
-- положить полный текст туда, где ширина не мешает (подсказка под курсором):
-- молча в этом проекте не исчезает ничего.
-- Ширина, уже которой мерить нечего: это не узкое окно, а «клиент ещё не
-- разложил привязки» (у свежего фрейма ширина нулевая). В таком случае текст
-- ставится целиком: следующая отрисовка придёт с настоящей шириной.
W.FIT_MIN = 24

-- Готовые варианты, от ценного к ненужному: ставим первый, который влезает.
-- Тем, кто собирает строку сам (строка над списком, строка статистики), этого
-- достаточно - свои варианты они знают лучше общего правила.
function W.SetFittedFrom(fs, variants, width)
    local first = variants[1] or ""
    if not fs then return first, false end
    fs:SetText(first)
    width = tonumber(width) or 0
    if width < W.FIT_MIN then return first, false end
    for i = 1, #variants do
        fs:SetText(variants[i])
        if (fs:GetStringWidth() or 0) <= width then
            return variants[i], variants[i] ~= first
        end
    end
    -- Не влезло даже самое короткое: оставляем его, а не исходное - в нём
    -- хотя бы число целое.
    local last = variants[#variants] or first
    fs:SetText(last)
    return last, last ~= first
end

-- ОДИН И ТОТ ЖЕ ОТВЕТ НЕ СЧИТАЕТСЯ ДВАЖДЫ ---------------------------------
--
-- ЧИСЛА, А НЕ ОЩУЩЕНИЯ. На настоящих данных игрока (26 советов на экране) одна
-- отрисовка списка стоила: 78 обращений сюда, 39 построений вариантов
-- (U.shortenings), 685 построенных строк-вариантов и 351 измерение ширины
-- шрифтом у клиента. И это при КАЖДОЙ отрисовке - в том числе при той, где ни
-- один совет не изменился: прокрутка, наведение мыши, смена фильтра, возврат
-- на вкладку.
--
-- Хуже того, в диагностике этого не видно вовсе: таймер пересчёта
-- (Diag:TimerStart/TimerStop) обнимает только ActionEngine:Build, а отрисовка
-- идёт ПОСЛЕ него и в «средний пересчёт 40 мс» не входит.
--
-- Память здесь точная, а не приблизительная, и живёт она НА САМОЙ СТРОКЕ.
-- Ответ зависит от трёх вещей: текста, ширины и шрифта. Текст и ширину
-- сравниваем, а шрифт сравнивать не нужно - у одного и того же объекта он тот
-- же, пока его не сменили, а меняется он только вместе с текстом. Поэтому
-- ключ - сам объект: никаких совпадений ключей между разными строками, никаких
-- догадок про шрифт.
--
-- Сбрасывать её не нужно: другой текст или другая ширина - это другой ключ, и
-- память просто не совпадёт.
function W.SetFitted(fs, text, width)
    text = tostring(text or "")
    if not fs then return text, false end
    width = tonumber(width) or 0

    local memo = fs.fpFit
    if memo and memo.text == text and memo.width == width then
        W.fitMemoHits = (W.fitMemoHits or 0) + 1
        -- Строку всё равно ставим: между отрисовками её мог сменить кто угодно.
        fs:SetText(memo.out)
        return memo.out, memo.cut
    end
    W.fitMemoMisses = (W.fitMemoMisses or 0) + 1

    local out, cut
    fs:SetText(text)
    if width < W.FIT_MIN then
        -- Ширины ещё нет (клиент не разложил привязки). Это НЕ ответ, и
        -- запоминать его нельзя: следующая отрисовка придёт с настоящей
        -- шириной, и тогда текст надо померить заново.
        return text, false
    elseif (fs:GetStringWidth() or 0) <= width then
        out, cut = text, false
    else
        out, cut = W.SetFittedFrom(fs, U.shortenings(text), width)
    end
    fs.fpFit = { text = text, width = width, out = out, cut = cut }
    return out, cut
end

function W.Label(parent, text, font, r, g, b)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or W.FONT_NORMAL)
    fs:SetText(text or "")
    fs:SetJustifyH("LEFT")
    if r then fs:SetTextColor(r, g, b) end
    return fs
end

-- A plain text button that does not try to look like a Blizzard dialog button.
function W.Button(parent, text, width, height, onClick)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(width or 100, height or 22)
    W.Backdrop(btn, 0.14, 0.16, 0.22, 0.95, 0.18)
    btn.text = W.Label(btn, text, W.FONT_SMALL)
    btn.text:SetPoint("CENTER")
    btn.text:SetJustifyH("CENTER")
    btn:SetScript("OnEnter", function(self)
        self.fpBG:SetColorTexture(0.22, 0.34, 0.55, 0.95)
    end)
    btn:SetScript("OnLeave", function(self)
        self.fpBG:SetColorTexture(0.14, 0.16, 0.22, 0.95)
    end)
    if onClick then btn:SetScript("OnClick", onClick) end
    function btn:SetLabel(t) self.text:SetText(t or "") end
    function btn:SetEnabledState(on)
        self:EnableMouse(on and true or false)
        self.text:SetTextColor(on and 0.92 or 0.45, on and 0.92 or 0.45, on and 0.92 or 0.45)
    end
    return btn
end

-- A toggle used for the profile buttons and the filter chips.
function W.Chip(parent, text, onClick, height)
    local chip = CreateFrame("Button", nil, parent)
    chip:SetHeight(height or 22)
    W.Backdrop(chip, 1, 1, 1, 0.08, 0.10)
    chip.text = W.Label(chip, text, W.FONT_SMALL)
    chip.text:SetPoint("CENTER", 0, 0)
    chip.text:SetJustifyH("CENTER")
    local textWidth = chip.text:GetStringWidth() or 40
    chip:SetWidth(math.max(54, textWidth + 20))
    chip.selected = false

    function chip:SetSelected(on)
        self.selected = on and true or false
        if self.selected then
            local c = W.COLOR.chipOn
            self.fpBG:SetColorTexture(c[1], c[2], c[3], c[4])
            self.text:SetTextColor(1, 1, 1)
        else
            local c = W.COLOR.chipOff
            self.fpBG:SetColorTexture(c[1], c[2], c[3], c[4])
            self.text:SetTextColor(0.75, 0.75, 0.75)
        end
    end
    chip:SetScript("OnEnter", function(self)
        if not self.selected then self.fpBG:SetColorTexture(1, 1, 1, 0.16) end
        if self.tooltipText then W.ShowTip(self, self.tooltipTitle or self.text:GetText(), self.tooltipText) end
    end)
    chip:SetScript("OnLeave", function(self)
        if not self.selected then
            local c = W.COLOR.chipOff
            self.fpBG:SetColorTexture(c[1], c[2], c[3], c[4])
        end
        W.HideTip()
    end)
    if onClick then chip:SetScript("OnClick", onClick) end
    chip:SetSelected(false)
    return chip
end

-- Tooltips. Respects the player's setting; never shows during combat because
-- the frame may be hidden underneath other things then.
function W.ShowTip(owner, title, body, anchor)
    if not (ns.Config:Get() and ns.Config:Get().ui.tooltips) then return end
    if not GameTooltip then return end
    GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    if title then GameTooltip:AddLine(title, 1, 0.82, 0) end
    if type(body) == "table" then
        for _, line in ipairs(body) do
            GameTooltip:AddLine(line, 0.9, 0.9, 0.9, true)
        end
    elseif body then
        GameTooltip:AddLine(body, 0.9, 0.9, 0.9, true)
    end
    GameTooltip:Show()
end

function W.ShowItemTip(owner, link, extra)
    if not (ns.Config:Get() and ns.Config:Get().ui.tooltips) then return end
    if not (GameTooltip and link) then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(link)
    if extra then
        for _, line in ipairs(extra) do GameTooltip:AddLine(line, 0.7, 0.85, 1, true) end
    end
    GameTooltip:Show()
end

function W.HideTip()
    if GameTooltip then GameTooltip:Hide() end
end

-- Run `fn` after `delay` seconds. C_Timer is present on every modern client,
-- but this is the only place that assumes it, so the fallback lives here:
-- a one-shot OnUpdate frame, which works on anything.
local timerFrame
function W.After(delay, fn)
    if type(fn) ~= "function" then return end
    if _G.C_Timer and type(_G.C_Timer.After) == "function" then
        _G.C_Timer.After(delay, fn)
        return
    end
    timerFrame = timerFrame or CreateFrame("Frame")
    timerFrame.queue = timerFrame.queue or {}
    table.insert(timerFrame.queue, { at = (GetTime and GetTime() or 0) + delay, fn = fn })
    timerFrame:SetScript("OnUpdate", function(self)
        local now = GetTime and GetTime() or 0
        for i = #self.queue, 1, -1 do
            if self.queue[i].at <= now then
                local entry = table.remove(self.queue, i)
                pcall(entry.fn)
            end
        end
        if #self.queue == 0 then self:SetScript("OnUpdate", nil) end
    end)
end

-- A repeating timer with a Cancel method, same contract as C_Timer.NewTicker.
function W.Ticker(interval, fn)
    if _G.C_Timer and type(_G.C_Timer.NewTicker) == "function" then
        return _G.C_Timer.NewTicker(interval, fn)
    end
    local frame = CreateFrame("Frame")
    local elapsed, cancelled = 0, false
    frame:SetScript("OnUpdate", function(_, dt)
        if cancelled then return end
        elapsed = elapsed + (dt or 0)
        if elapsed >= interval then
            elapsed = 0
            pcall(fn)
        end
    end)
    return {
        Cancel = function()
            cancelled = true
            frame:SetScript("OnUpdate", nil)
        end,
    }
end

-- A scrolling container with a simple content frame inside.
function W.ScrollArea(parent)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    scroll.content = content

    -- The default template's scrollbar sits a little too far right for our
    -- padding, so nudge it in.
    local bar = scroll.ScrollBar or _G[(scroll:GetName() or "") .. "ScrollBar"]
    if bar then
        bar:ClearAllPoints()
        bar:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 18, -16)
        bar:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 18, 16)
    end
    return scroll, content
end

-- A one-line "nothing here, and here is why" panel. Used instead of a blank
-- area anywhere a list can come back empty.
function W.EmptyState(parent, title, body, actionText, onAction)
    local frame = CreateFrame("Frame", nil, parent)
    W.Backdrop(frame, 0.10, 0.09, 0.07, 0.75, 0.14)
    frame:SetHeight(actionText and 112 or 84)

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(28, 28)
    icon:SetPoint("TOPLEFT", 14, -14)
    icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")

    local head = W.Label(frame, title, W.FONT_NORMAL, 1, 0.82, 0)
    head:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -2)
    head:SetPoint("RIGHT", frame, "RIGHT", -14, 0)
    head:SetJustifyH("LEFT")

    local text = W.Label(frame, body, W.FONT_SMALL, 0.85, 0.85, 0.85)
    text:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -6)
    text:SetPoint("RIGHT", frame, "RIGHT", -14, 0)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(true)

    if actionText then
        local btn = W.Button(frame, actionText, 160, 22, onAction)
        btn:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -10)
        frame.button = btn
    end
    frame.title, frame.body, frame.icon = head, text, icon
    return frame
end

-- A confidence pill: "точно" / "из кеша" / "оценка" / "неизвестно".
function W.ConfBadge(parent, conf)
    local badge = CreateFrame("Frame", nil, parent)
    badge:SetSize(58, 14)
    W.Backdrop(badge, 0, 0, 0, 0.35, 0.08)
    badge.text = W.Label(badge, "", W.FONT_SMALL)
    badge.text:SetPoint("CENTER")
    badge.text:SetJustifyH("CENTER")

    function badge:Set(c)
        local label = ns.CONF_LABEL[c] or ns.CONF_LABEL.UNKNOWN
        local col = ns.CONF_COLOR[c] or ns.CONF_COLOR.UNKNOWN
        self.text:SetText(label)
        self.text:SetTextColor(col[1], col[2], col[3])
        self:SetWidth(math.max(44, (self.text:GetStringWidth() or 30) + 12))
        self.conf = c
    end
    badge:EnableMouse(true)
    badge:SetScript("OnEnter", function(self)
        W.ShowTip(self, "Насколько можно верить", {
            "точно — прочитано из игры в этой сессии",
            "из кеша — сохранённые данные, могли устареть",
            "оценка — посчитано мной, не факт из клиента",
            "неизвестно — данных нет, число не придумываю",
        })
    end)
    badge:SetScript("OnLeave", W.HideTip)
    badge:Set(conf)
    return badge
end

-- A thin horizontal progress bar, used for readiness.
function W.Meter(parent, width, height)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetSize(width or 60, height or 4)
    W.Backdrop(bar, 1, 1, 1, 0.08, 0)
    local fill = bar:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT")
    fill:SetPoint("BOTTOMLEFT")
    fill:SetColorTexture(0.35, 0.75, 0.45, 0.9)
    bar.fill = fill
    function bar:SetValue(v)
        v = U.clamp(tonumber(v) or 0, 0, 1)
        if v <= 0 then self.fill:Hide() else
            self.fill:Show()
            self.fill:SetWidth(math.max(1, self:GetWidth() * v))
        end
        if v >= 1 then self.fill:SetColorTexture(0.35, 0.80, 0.45, 0.95)
        elseif v >= 0.5 then self.fill:SetColorTexture(0.85, 0.75, 0.30, 0.95)
        else self.fill:SetColorTexture(0.80, 0.45, 0.35, 0.95) end
    end
    bar:SetValue(0)
    return bar
end

-- A simple key/value row for the character and settings tabs.
function W.StatRow(parent, labelText, valueText, width)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(width or 300, 18)
    local l = W.Label(row, labelText, W.FONT_SMALL, 0.62, 0.62, 0.62)
    l:SetPoint("LEFT", 0, 0)
    local v = W.Label(row, valueText, W.FONT_SMALL, 0.92, 0.92, 0.92)
    v:SetPoint("LEFT", row, "LEFT", 150, 0)
    v:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    v:SetJustifyH("LEFT")
    row.label, row.value = l, v
    function row:Set(t) self.value:SetText(t or "") end
    return row
end

function W.SectionHeader(parent, text, width)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(width or 300, 22)
    local fs = W.Label(frame, text, W.FONT_NORMAL, 1, 0.82, 0)
    fs:SetPoint("BOTTOMLEFT", 0, 4)
    local line = frame:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.10)
    line:SetPoint("BOTTOMLEFT", 0, 0)
    line:SetPoint("BOTTOMRIGHT", 0, 0)
    line:SetHeight(1)
    frame.text = fs
    return frame
end

-- A slider with a label, used for the UI scale setting.
function W.Slider(parent, labelText, minV, maxV, step, onChange)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(300, 46)
    local l = W.Label(frame, labelText, W.FONT_SMALL, 0.85, 0.85, 0.85)
    l:SetPoint("TOPLEFT", 0, 0)

    local slider = CreateFrame("Slider", nil, frame)
    slider:SetPoint("TOPLEFT", l, "BOTTOMLEFT", 0, -8)
    slider:SetSize(200, 16)
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(minV, maxV)
    slider:SetValueStep(step)
    -- Not present on every client flavour; the slider works without it.
    if slider.SetObeyStepOnDrag then pcall(slider.SetObeyStepOnDrag, slider, true) end
    W.Backdrop(slider, 1, 1, 1, 0.08, 0)

    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(0.45, 0.65, 1.0, 0.95)
    thumb:SetSize(10, 18)
    slider:SetThumbTexture(thumb)

    local value = W.Label(frame, "", W.FONT_SMALL, 1, 0.82, 0)
    value:SetPoint("LEFT", slider, "RIGHT", 10, 0)

    slider:SetScript("OnValueChanged", function(self, v)
        value:SetText(string.format("%.2f", v))
        if onChange and not self.suppress then onChange(v) end
    end)
    frame.slider, frame.valueText = slider, value
    function frame:SetValue(v)
        slider.suppress = true
        slider:SetValue(v)
        slider.suppress = false
        value:SetText(string.format("%.2f", v))
    end
    return frame
end

function W.Checkbox(parent, labelText, onToggle)
    local frame = CreateFrame("Button", nil, parent)
    frame:SetSize(300, 20)
    local box = CreateFrame("Frame", nil, frame)
    box:SetSize(14, 14)
    box:SetPoint("LEFT", 0, 0)
    W.Backdrop(box, 1, 1, 1, 0.08, 0.20)
    local tick = box:CreateTexture(nil, "OVERLAY")
    tick:SetPoint("CENTER")
    tick:SetSize(8, 8)
    tick:SetColorTexture(0.45, 0.80, 1.0, 1)
    tick:Hide()

    local l = W.Label(frame, labelText, W.FONT_SMALL, 0.88, 0.88, 0.88)
    l:SetPoint("LEFT", box, "RIGHT", 8, 0)
    l:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
    l:SetJustifyH("LEFT")

    frame.checked = false
    function frame:SetChecked(on)
        self.checked = on and true or false
        if self.checked then tick:Show() else tick:Hide() end
    end
    frame:SetScript("OnClick", function(self)
        self:SetChecked(not self.checked)
        if onToggle then onToggle(self.checked) end
    end)
    frame.label = l
    return frame
end

return W
