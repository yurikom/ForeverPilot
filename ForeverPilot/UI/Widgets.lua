-- ForeverPilot / UI/Widgets.lua
-- Small frame builders shared by every tab. Pure presentation.
local ADDON, ns = ...

local U = ns.Util
local W = {}
ns.Widgets = W

-- ШРИФТЫ. Имена здесь - то, чем пользуются все разделы; что за ними стоит,
-- решается один раз при загрузке (W.InitFonts ниже).
--
-- Пока клиент не видит файлов аддона (до полного перезапуска игры), это шрифты
-- самой игры - и не самые мелкие из них: на мелкий текст игрок жаловался
-- отдельно («буквы мелкие, нечитабельные», 2026-11-21).
W.FONT_HERO = "GameFontNormalLarge"      -- название раздела в шапке
W.FONT_TITLE = "GameFontNormalLarge"     -- заголовок блока, название совета
W.FONT_NORMAL = "GameFontNormal"         -- строка списка, выделенный текст
W.FONT_SMALL = "GameFontHighlight"       -- основной текст
W.FONT_DISABLED = "GameFontDisable"      -- приглушённый текст
W.FONT_CAPTION = "GameFontHighlightSmall" -- подпись, счётчик, примечание
W.LINE = 15                              -- высота строки основного текста

W.COLOR = {
    gold      = { 0.96, 0.80, 0.42 },
    power     = { 0.52, 0.80, 1.00 },
    skill     = { 0.62, 0.90, 0.62 },
    spend     = { 1.00, 0.62, 0.50 },
    muted     = { 0.60, 0.64, 0.73 },
    text      = { 0.95, 0.96, 0.98 },
    setup     = { 1.00, 0.76, 0.36 },
    rowOdd    = { 1, 1, 1, 0.025 },
    rowHover  = { 1, 1, 1, 0.05 },
    chipOn    = { 0.89, 0.72, 0.38, 0.34 },   -- выбранное - тем же золотым, что в окне
    chipOff   = { 1, 1, 1, 0.08 },
}

-- ТЕМА ОКНА. Раскладка и вид большого окна - по образцу Polestar (жалоба игрока
-- 2026-11-21: «херовый UX, непонятно, куда нажимать… сделай так же, как у
-- него»): ночной тёмно-синий фон, белая лесенка текста, линии в один пиксель и
-- один тёплый золотой акцент - только на выбранном и на главной кнопке. Цвета,
-- код и картинки здесь свои; у Polestar взят принцип, а не файлы.
--
-- ВСЕ ФОНЫ НЕПРОЗРАЧНЫЕ. Фон окна был прозрачен на три процента, и сквозь
-- список просвечивали панели и чат игры - игрок прислал это скриншотом.
W.THEME = {
    bg       = { 0.090, 0.110, 0.169, 1.00 },   -- окно и список
    side     = { 0.071, 0.086, 0.141, 1.00 },   -- колонка фильтра
    rail     = { 0.055, 0.069, 0.118, 1.00 },   -- полоса разделов
    band     = { 0.118, 0.149, 0.247, 1.00 },   -- шапка над списком (низ)
    bandTop  = { 0.086, 0.110, 0.196, 1.00 },   -- шапка над списком (верх)
    panel    = { 0.104, 0.127, 0.196, 1.00 },   -- карточка совета справа
    foot     = { 0.071, 0.086, 0.141, 1.00 },
    text     = { 0.95, 0.96, 0.98 },
    dim      = { 0.76, 0.79, 0.87 },
    muted    = { 0.60, 0.64, 0.73 },
    line     = { 1, 1, 1, 0.09 },
    hover    = { 1, 1, 1, 0.05 },
    selected = { 1, 1, 1, 0.09 },
    accent   = { 0.90, 0.73, 0.40 },
    onAccent = { 0.07, 0.08, 0.11 },
    good     = { 0.45, 0.85, 0.62 },
    warn     = { 0.98, 0.76, 0.34 },
    button      = { 0.17, 0.20, 0.31, 1.00 },
    buttonHover = { 0.24, 0.28, 0.42, 1.00 },
}

-- СВОИ ФАЙЛЫ: шрифт Fira Sans (открытая лицензия OFL, тот же шрифт стоит в окне
-- Polestar на русском клиенте) и значки, нарисованные для аддона
-- (tools/make_media.py). Новые файлы клиент находит только после полного
-- перезапуска игры, поэтому всё здесь умеет жить без них: W.ready отвечает,
-- видит ли их клиент (Api:FontsReady), и до тех пор окно рисуется шрифтами игры,
-- без значков и с прямыми углами. Проще, но целое - без пустых строк и зелёных
-- квадратов на месте ненайденных картинок.
W.MEDIA = (ns.Api and ns.Api.MEDIA) or ("Interface\\AddOns\\" .. tostring(ADDON) .. "\\Media\\")
W.ready = false

W.FONTS = {
    -- имя шрифта,                 файл,                     размер, цвет по умолчанию
    { "FONT_HERO",     "ForeverPilotFontHero",    "FiraSans-SemiBold.ttf", 23, "text" },
    { "FONT_TITLE",    "ForeverPilotFontTitle",   "FiraSans-SemiBold.ttf", 15, "accent" },
    { "FONT_NORMAL",   "ForeverPilotFontRow",     "FiraSans-Medium.ttf",   13, "accent" },
    { "FONT_SMALL",    "ForeverPilotFontBody",    "FiraSans-Regular.ttf",  12.5, "text" },
    { "FONT_DISABLED", "ForeverPilotFontMuted",   "FiraSans-Regular.ttf",  12.5, "muted" },
    { "FONT_CAPTION",  "ForeverPilotFontCaption", "FiraSans-Medium.ttf",   11.5, "dim" },
}

function W.InitFonts()
    W.ready = (ns.Api and ns.Api.FontsReady and ns.Api:FontsReady()) and true or false
    if not W.ready then return false end
    local create = _G.CreateFont
    if type(create) ~= "function" then
        W.ready = false
        return false
    end
    for _, def in ipairs(W.FONTS) do
        local name, file, size, colour = def[2], def[3], def[4], def[5]
        local ok, loaded = pcall(function()
            local font = _G[name] or create(name)
            if not ns.Api:LoadFont(font, "Fonts\\" .. file, size) then return false end
            local c = W.THEME[colour]
            font:SetTextColor(c[1], c[2], c[3])
            -- Без тени: на тёмном ровном фоне она только мажет буквы.
            if font.SetShadowOffset then font:SetShadowOffset(0, 0) end
            if font.SetShadowColor then font:SetShadowColor(0, 0, 0, 0) end
            if font.SetSpacing then font:SetSpacing(2) end
            return true
        end)
        -- Один шрифт не загрузился - остаёмся на шрифтах игры целиком: половина
        -- окна одним шрифтом, половина другим хуже любого из них.
        if not (ok and loaded) then
            W.ready = false
            return false
        end
    end
    for _, def in ipairs(W.FONTS) do W[def[1]] = def[2] end
    return true
end
W.InitFonts()

-- ЗНАЧОК ИЗ СВОЕГО НАБОРА: белая линия на прозрачном, цвет задаётся здесь.
-- Пока клиент файлов не видит, значок просто не показывается.
function W.SetIcon(tex, name, colour)
    tex.iconName = name
    if not (W.ready and name) then
        tex:Hide()
        return false
    end
    tex:SetTexture(W.MEDIA .. "icon-" .. name)
    tex:SetTexCoord(0, 1, 0, 1)
    local c = colour or W.THEME.text
    tex:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
    tex:Show()
    return true
end

function W.Icon(parent, name, size, colour, layer)
    local tex = parent:CreateTexture(nil, layer or "ARTWORK")
    tex:SetSize(size or 16, size or 16)
    W.SetIcon(tex, name, colour)
    return tex
end

-- ПЛАШКА СО СКРУГЛЁННЫМИ УГЛАМИ - из трёх кусков одной картинки: левый край,
-- растянутая середина, правый край. Высоту задаёт рамка, ширина краёв считается
-- от неё. Нужна кнопкам и меткам; прямоугольников со скруглением у клиента нет.
--   shape: "round" (кнопка), "round-line" (контур), "pill" (метка), "pill-line"
function W.Plate(frame, shape, layer)
    if not W.ready then return nil end
    local cap = (shape:sub(1, 4) == "pill") and 0.5 or 0.25
    local file = W.MEDIA .. shape
    local plate = { parts = {}, cap = cap, frame = frame }
    local coords = { { 0, cap }, { cap, 1 - cap }, { 1 - cap, 1 } }
    if cap == 0.5 then coords[2] = { 0.49, 0.51 } end
    for i = 1, 3 do
        local t = frame:CreateTexture(nil, layer or "BACKGROUND")
        t:SetTexture(file)
        t:SetTexCoord(coords[i][1], coords[i][2], 0, 1)
        -- Без привязки к сетке пикселей: иначе между кусками видна щель.
        if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false) end
        if t.SetTexelSnappingBias then t:SetTexelSnappingBias(0) end
        plate.parts[i] = t
    end
    local L, M, R = plate.parts[1], plate.parts[2], plate.parts[3]
    L:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    L:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    R:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    R:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    M:SetPoint("TOPLEFT", L, "TOPRIGHT", 0, 0)
    M:SetPoint("BOTTOMRIGHT", R, "BOTTOMLEFT", 0, 0)
    function plate:Fit(height)
        local w = math.max(1, (tonumber(height) or 0) * self.cap)
        L:SetWidth(w)
        R:SetWidth(w)
    end
    function plate:Colour(r, g, b, a)
        for _, t in ipairs(self.parts) do t:SetVertexColor(r, g, b, a or 1) end
    end
    function plate:SetShown(on)
        for _, t in ipairs(self.parts) do
            if on then t:Show() else t:Hide() end
        end
    end
    plate:Fit(frame:GetHeight())
    return plate
end

function W.Paint(tex, c, alpha)
    tex:SetColorTexture(c[1], c[2], c[3], alpha or c[4] or 1)
end

-- Тонкая линия-разделитель. side: "TOP", "BOTTOM", "LEFT" или "RIGHT".
function W.Hairline(frame, side)
    local line = frame:CreateTexture(nil, "BORDER")
    W.Paint(line, W.THEME.line)
    if side == "TOP" then
        line:SetPoint("TOPLEFT"); line:SetPoint("TOPRIGHT"); line:SetHeight(1)
    elseif side == "BOTTOM" then
        line:SetPoint("BOTTOMLEFT"); line:SetPoint("BOTTOMRIGHT"); line:SetHeight(1)
    elseif side == "LEFT" then
        line:SetPoint("TOPLEFT"); line:SetPoint("BOTTOMLEFT"); line:SetWidth(1)
    else
        line:SetPoint("TOPRIGHT"); line:SetPoint("BOTTOMRIGHT"); line:SetWidth(1)
    end
    return line
end

-- Заливка без рамки: колонки окна отделяются одной линией, а не коробкой.
function W.Ground(frame, c)
    if not frame.fpBG then
        local bg = frame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(frame)
        frame.fpBG = bg
    end
    W.Paint(frame.fpBG, c)
    return frame
end

-- Текстура из своего файла, а пока клиент его не видит - запасная из игры.
--
-- Новый файл в папке аддона клиент находит только после полного перезапуска,
-- не после /reload; до тех пор на его месте был бы зелёный квадрат. Видит ли
-- он новые файлы, отвечает Api:MediaReady (по метке в .toc). И второй сторож:
-- если SetTexture сам ответил «нет», тоже ставим запасную.
function W.SetTextureOr(tex, path, fallback)
    local ready = ns.Api and ns.Api.MediaReady and ns.Api:MediaReady()
    if ready then
        local ok, result = pcall(tex.SetTexture, tex, path)
        if ok and result ~= false then return true end
    end
    tex:SetTexture(fallback)
    return false
end

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
    local base = W.THEME.button
    W.Backdrop(btn, base[1], base[2], base[3], base[4], 0.14)
    -- Со своими картинками кнопка скруглённая, и прямоугольный фон с рамкой
    -- под ней прячется. Без них остаётся ровный прямоугольник.
    btn.plate = W.Plate(btn, "round")
    if btn.plate then
        btn.fpBG:Hide()
        for _, edge in ipairs(btn.fpEdges or {}) do edge:Hide() end
    end
    local font = ((height or 22) >= 24) and W.FONT_NORMAL or W.FONT_CAPTION
    btn.text = W.Label(btn, text, font, 0.92, 0.93, 0.96)
    btn.text:SetPoint("CENTER")
    btn.text:SetJustifyH("CENTER")
    btn.icon = btn:CreateTexture(nil, "OVERLAY")
    btn.icon:SetSize(14, 14)
    btn.icon:Hide()
    btn:SetScript("OnEnter", function(self) self:Repaint(true) end)
    btn:SetScript("OnLeave", function(self) self:Repaint(false) end)
    if onClick then btn:SetScript("OnClick", onClick) end

    -- Значок слева от подписи; вместе они стоят по центру кнопки. Кнопка без
    -- подписи (крестик, «обновить») - один значок по центру.
    function btn:Arrange()
        self.text:ClearAllPoints()
        self.icon:ClearAllPoints()
        local shown = self.iconName ~= nil and W.ready
        local label = self.text:GetText() or ""
        if shown and label == "" then
            self.icon:SetPoint("CENTER", self, "CENTER", 0, 0)
        elseif shown then
            local gap = 6
            local half = ((tonumber(self.icon:GetWidth()) or 14) + gap) / 2
            self.text:SetPoint("CENTER", self, "CENTER", half, 0)
            self.icon:SetPoint("RIGHT", self.text, "LEFT", -gap, 0)
        else
            self.text:SetPoint("CENTER", self, "CENTER", 0, 0)
        end
    end
    function btn:Tint()
        local c = self.primary and W.THEME.onAccent or (self.inkColour or { 0.92, 0.93, 0.96 })
        if self.disabled then c = { 0.45, 0.47, 0.54 } end
        self.text:SetTextColor(c[1], c[2], c[3])
        if self.iconName then W.SetIcon(self.icon, self.iconName, c) end
    end
    function btn:SetIcon(name, size)
        self.iconName = name
        if size then self.icon:SetSize(size, size) end
        self:Tint()
        self:Arrange()
    end
    -- Запасная подпись для кнопки-значка: видна, пока значков нет.
    function btn:SetGlyph(name, fallback, size)
        self.glyphFallback = fallback
        self.text:SetText(W.ready and "" or (fallback or ""))
        self:SetIcon(name, size)
    end
    function btn:SetLabel(t)
        self.text:SetText(t or "")
        self:Arrange()
    end
    -- Сколько места нужно кнопке, чтобы подпись со значком стояли целиком.
    function btn:LabelWidth()
        local w = (tonumber(self.text:GetStringWidth()) or 0) + 28
        if self.iconName ~= nil and W.ready then
            w = w + (tonumber(self.icon:GetWidth()) or 14) + 6
        end
        return w
    end
    -- ГЛАВНАЯ КНОПКА - ОДНА НА ЭКРАН, И ОНА ЗОЛОТАЯ. Всё остальное остаётся
    -- тихим: так сразу видно, куда нажимать.
    function btn:Repaint(hover)
        local T = W.THEME
        local c
        if self.primary then
            local a, k = T.accent, hover and 1.10 or 1.0
            c = { math.min(1, a[1] * k), math.min(1, a[2] * k), math.min(1, a[3] * k), 1 }
        elseif self.quiet then
            -- Тихая кнопка (значок в углу): фона нет, пока на неё не навели.
            c = hover and { 1, 1, 1, 0.10 } or { 1, 1, 1, 0 }
        else
            c = hover and T.buttonHover or T.button
        end
        if self.plate then
            self.plate:Colour(c[1], c[2], c[3], c[4] or 1)
        else
            self.fpBG:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
        end
    end
    -- Залить кнопку своим цветом (красный у «убрать панель» под курсором).
    function btn:Wash(r, g, b, a)
        if self.plate then
            self.plate:Colour(r, g, b, a or 1)
        else
            self.fpBG:SetColorTexture(r, g, b, a or 1)
        end
    end
    function btn:SetPrimary(on)
        self.primary = on and true or false
        self:Tint()
        self:Repaint(false)
    end
    function btn:SetQuiet(on)
        self.quiet = on and true or false
        if not self.plate then
            for _, edge in ipairs(self.fpEdges or {}) do
                if self.quiet then edge:Hide() else edge:Show() end
            end
        end
        self:Repaint(false)
    end
    function btn:SetEnabledState(on)
        self.disabled = not on
        self:EnableMouse(on and true or false)
        self:Tint()
    end
    -- Размер поменяли - края плашки подгоняются под новую высоту.
    function btn:Resize(w, h)
        self:SetSize(w, h)
        if self.plate then self.plate:Fit(h) end
    end
    btn:Repaint(false)
    return btn
end

-- СТРОКА БОКОВОЙ КОЛОНКИ: значок, название, справа счётчик. Выбранная строка
-- светлее и с золотой полоской слева - как категории в окне, с которого взят
-- образец. Умеет то же, что прежняя кнопка-чип (SetSelected, подсказка), чтобы
-- остальной код и проверки не заметили подмены.
W.NAV_ICON = 16
W.NAV_PAD = 16

function W.NavRow(parent, text, onClick, height, iconName)
    local T = W.THEME
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(height or 28)
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(row)
    bg:SetColorTexture(1, 1, 1, 0)
    row.fpBG = bg
    local bar = row:CreateTexture(nil, "ARTWORK")
    bar:SetPoint("TOPLEFT", 0, 0)
    bar:SetPoint("BOTTOMLEFT", 0, 0)
    bar:SetWidth(3)
    W.Paint(bar, T.accent, 1)
    bar:Hide()
    row.bar = bar

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(W.NAV_ICON, W.NAV_ICON)
    row.icon:SetPoint("LEFT", row, "LEFT", W.NAV_PAD, 0)
    row.iconName = iconName

    row.count = W.Label(row, "", W.FONT_CAPTION, T.muted[1], T.muted[2], T.muted[3])
    row.count:SetPoint("RIGHT", row, "RIGHT", -14, 0)
    row.count:SetJustifyH("RIGHT")
    row.text = W.Label(row, text, W.FONT_NORMAL, T.dim[1], T.dim[2], T.dim[3])
    -- Место под значок оставлено всегда: появятся значки - строки не поедут.
    row.text:SetPoint("LEFT", row, "LEFT", W.NAV_PAD + W.NAV_ICON + 10, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    row.selected = false

    function row:SetSelected(on)
        self.selected = on and true or false
        local c
        if self.selected then
            W.Paint(self.fpBG, T.selected)
            self.bar:Show()
            c = T.text
        else
            self.fpBG:SetColorTexture(1, 1, 1, 0)
            self.bar:Hide()
            c = self.dim and T.muted or T.dim
        end
        self.text:SetTextColor(c[1], c[2], c[3])
        W.SetIcon(self.icon, self.iconName, self.selected and T.accent or c)
    end
    function row:SetCount(n)
        self.count:SetText((n ~= nil) and tostring(n) or "")
    end
    -- Пустой фильтр - приглушённо: нажать можно, но видно, что там ноль.
    function row:SetDim(on)
        self.dim = on and true or false
        self:SetSelected(self.selected)
    end
    row:SetScript("OnEnter", function(self)
        if not self.selected then W.Paint(self.fpBG, T.hover) end
        if self.tooltipText then
            W.ShowTip(self, self.tooltipTitle or self.text:GetText(), self.tooltipText)
        end
    end)
    row:SetScript("OnLeave", function(self)
        if not self.selected then self.fpBG:SetColorTexture(1, 1, 1, 0) end
        W.HideTip()
    end)
    if onClick then row:SetScript("OnClick", onClick) end
    row:SetSelected(false)
    return row
end

-- КНОПКА ПОЛОСЫ РАЗДЕЛОВ: значок, под ним подпись. Выбранный раздел светлее, с
-- золотой полоской слева и золотым значком.
--   iconName - значок из своего набора; fallbackTexture - картинка игры на то
--   время, пока своих файлов клиент не видит.
function W.RailButton(parent, iconName, text, onClick, width, height, fallbackTexture)
    local T = W.THEME
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(width or 66, height or 50)
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(btn)
    bg:SetColorTexture(1, 1, 1, 0)
    btn.fpBG = bg
    local bar = btn:CreateTexture(nil, "ARTWORK")
    bar:SetPoint("TOPLEFT", 0, 0)
    bar:SetPoint("BOTTOMLEFT", 0, 0)
    bar:SetWidth(3)
    W.Paint(bar, T.accent, 1)
    bar:Hide()
    btn.bar = bar
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("TOP", btn, "TOP", 0, -8)
    btn.icon = icon
    btn.iconName, btn.fallbackTexture = iconName, fallbackTexture
    btn.text = W.Label(btn, text, W.FONT_CAPTION, T.dim[1], T.dim[2], T.dim[3])
    btn.text:SetPoint("BOTTOM", btn, "BOTTOM", 0, 7)
    btn.text:SetJustifyH("CENTER")
    btn.selected = false

    function btn:PaintIcon(colour)
        if W.SetIcon(self.icon, self.iconName, colour) then return end
        if self.fallbackTexture then
            self.icon:SetTexture(self.fallbackTexture)
            self.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            self.icon:SetVertexColor(1, 1, 1, 1)
            self.icon:Show()
        end
    end
    function btn:SetSelected(on)
        self.selected = on and true or false
        if self.selected then
            W.Paint(self.fpBG, T.selected)
            self.bar:Show()
            self.text:SetTextColor(T.text[1], T.text[2], T.text[3])
            self:PaintIcon(T.accent)
        else
            self.fpBG:SetColorTexture(1, 1, 1, 0)
            self.bar:Hide()
            self.text:SetTextColor(T.dim[1], T.dim[2], T.dim[3])
            self:PaintIcon(T.dim)
        end
    end
    btn:SetScript("OnEnter", function(self)
        if not self.selected then W.Paint(self.fpBG, T.hover) end
        if self.tooltipText then
            W.ShowTip(self, self.tooltipTitle or self.text:GetText(), self.tooltipText)
        end
    end)
    btn:SetScript("OnLeave", function(self)
        if not self.selected then self.fpBG:SetColorTexture(1, 1, 1, 0) end
        W.HideTip()
    end)
    if onClick then btn:SetScript("OnClick", onClick) end
    btn:SetSelected(false)
    return btn
end

-- ВКЛАДКА С ПОДЧЁРКИВАНИЕМ: слово, под выбранным - золотая черта. Так в окне
-- Polestar стоят «Главная / Обзор / Текущий»; у нас так выбирается профиль.
function W.Tab(parent, text, onClick)
    local T = W.THEME
    local tab = CreateFrame("Button", nil, parent)
    tab.text = W.Label(tab, text, W.FONT_NORMAL, T.dim[1], T.dim[2], T.dim[3])
    tab.text:SetPoint("CENTER", tab, "CENTER", 0, 1)
    tab.text:SetJustifyH("CENTER")
    tab:SetSize(math.max(40, (tonumber(tab.text:GetStringWidth()) or 40) + 22), 28)
    local line = tab:CreateTexture(nil, "ARTWORK")
    line:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 0, 0)
    line:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", 0, 0)
    line:SetHeight(2)
    W.Paint(line, T.accent, 1)
    line:Hide()
    tab.line = line
    tab.selected = false
    function tab:SetSelected(on)
        self.selected = on and true or false
        local c = self.selected and T.text or T.dim
        self.text:SetTextColor(c[1], c[2], c[3])
        if self.selected then self.line:Show() else self.line:Hide() end
    end
    tab:SetScript("OnEnter", function(self)
        if not self.selected then self.text:SetTextColor(T.text[1], T.text[2], T.text[3]) end
        if self.tooltipText then
            W.ShowTip(self, self.tooltipTitle or self.text:GetText(), self.tooltipText)
        end
    end)
    tab:SetScript("OnLeave", function(self)
        if not self.selected then self.text:SetTextColor(T.dim[1], T.dim[2], T.dim[3]) end
        W.HideTip()
    end)
    if onClick then tab:SetScript("OnClick", onClick) end
    return tab
end

-- МЕТКА: короткое слово на цветной скруглённой плашке («+14 баллов», «всё
-- есть»). Ширина - по тексту.
function W.Pill(parent, text, colour)
    local pill = CreateFrame("Frame", nil, parent)
    pill:SetHeight(20)
    pill.plate = W.Plate(pill, "pill")
    if not pill.plate then
        local bg = pill:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(pill)
        pill.fpBG = bg
    end
    pill.text = W.Label(pill, "", W.FONT_CAPTION)
    pill.text:SetPoint("CENTER", pill, "CENTER", 0, 0)
    pill.text:SetJustifyH("CENTER")
    pill.text:SetWordWrap(false)
    function pill:Set(label, c, maxWidth)
        c = c or W.THEME.dim
        local room = maxWidth and (maxWidth - 20) or nil
        if room then
            W.SetFitted(self.text, label or "", room)
        else
            self.text:SetText(label or "")
        end
        self.text:SetTextColor(c[1], c[2], c[3])
        if self.plate then
            self.plate:Colour(c[1], c[2], c[3], 0.16)
        else
            self.fpBG:SetColorTexture(c[1], c[2], c[3], 0.16)
        end
        self:SetWidth(math.max(28, (tonumber(self.text:GetStringWidth()) or 20) + 20))
    end
    pill:Set(text, colour)
    return pill
end

-- ТЕКСТ В НЕСКОЛЬКО СТРОК ПО ЗАДАННОЙ ШИРИНЕ. Возвращает высоту, которую он
-- займёт: по ней следующий блок ставится под этим.
--
-- Высоту знает клиент (GetStringHeight), и ему верим первому: своя оценка по
-- длине строки всегда с запасом, и от неё между блоками остаются дыры. Оценка
-- нужна в двух случаях: клиент старый и ширину без переноса не отдаёт, или он
-- ответил «одна строка» про текст, которого заведомо на несколько, - значит,
-- перенос ещё не посчитан. Тогда лишний зазор лучше, чем текст поверх кнопки.
function W.SetWrapped(fs, text, width, lineHeight)
    text = tostring(text or "")
    lineHeight = lineHeight or 12
    fs:SetWidth(width)
    -- Высота сбрасывается в «сама по тексту»: заданная прошлым показом высота
    -- иначе обрезала бы новый текст и занизила бы ответ клиента о его высоте.
    fs:SetHeight(0)
    if fs.SetWordWrap then fs:SetWordWrap(true) end
    fs:SetText(text)
    if text == "" then return 0 end
    local unbounded = fs.GetUnboundedStringWidth and tonumber(fs:GetUnboundedStringWidth()) or nil
    local full = unbounded or tonumber(fs:GetStringWidth()) or 0
    local breaks = 0
    for _ in text:gmatch("\n") do breaks = breaks + 1 end
    local lines = math.max(1, math.ceil(full / math.max(1, width * 0.9))) + breaks
    local estimate = lines * lineHeight
    local real = fs.GetStringHeight and tonumber(fs:GetStringHeight()) or 0
    -- Высоту самой строке не задаём: она остаётся «по тексту», и клиент ничего
    -- не обрежет, даже если наш счёт разошёлся с его на пиксель. Число нужно
    -- только тому, кто ставит следующий блок.
    if unbounded and real > 0 and not (real <= lineHeight * 1.3 and lines >= 3) then
        return math.ceil(real)
    end
    return math.max(estimate, math.ceil(real))
end

-- ШАПКА РАЗДЕЛА: тёмно-синяя полоса с переходом сверху вниз и редкими звёздами,
-- в ней крупное название. Звёзды - своя картинка; она кладётся плитками нужной
-- ширины, а не растягивается, иначе точки превращаются в чёрточки.
function W.Band(parent, height)
    local T = W.THEME
    local band = CreateFrame("Frame", nil, parent)
    band:SetHeight(height)
    local bg = band:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(band)
    W.Paint(bg, T.band)
    if bg.SetGradient and type(_G.CreateColor) == "function" then
        local ok = pcall(function()
            bg:SetColorTexture(1, 1, 1, 1)
            bg:SetGradient("VERTICAL",
                _G.CreateColor(T.band[1], T.band[2], T.band[3], 1),
                _G.CreateColor(T.bandTop[1], T.bandTop[2], T.bandTop[3], 1))
        end)
        -- Клиент перехода цвета в таком виде не принял - шапка остаётся ровной
        -- тёмно-синей, а не белой (под переход текстура красится в белый).
        if not ok then W.Paint(bg, T.band) end
    end
    band.fpBG = bg
    W.Hairline(band, "BOTTOM")
    band.stars = {}
    -- Плитка звёзд вчетверо шире своей высоты (так нарисована картинка).
    function band:SetStarWidth(width)
        if not W.ready then return end
        local h = tonumber(self:GetHeight()) or height
        local tile = h * 4
        local x, i = 0, 0
        width = tonumber(width) or 0
        while x < width - 0.5 do
            i = i + 1
            local t = self.stars[i]
            if not t then
                t = self:CreateTexture(nil, "BORDER")
                t:SetTexture(W.MEDIA .. "stars")
                t:SetVertexColor(0.86, 0.90, 1.0, 0.85)
                self.stars[i] = t
            end
            local w = math.min(tile, width - x)
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", self, "TOPLEFT", x, 0)
            t:SetSize(w, h)
            t:SetTexCoord(0, w / tile, 0, 1)
            t:Show()
            x = x + w
        end
        for k = i + 1, #self.stars do self.stars[k]:Hide() end
    end
    return band
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
-- СПИСОК С ПРОКРУТКОЙ - со своей тонкой полосой.
--
-- Готовая полоса из игры на этом клиенте рисуется каменными кнопками со
-- стрелками: в тёмном плоском окне они выглядели чужими серыми квадратами
-- (скриншот игрока, 2026-11-21). Здесь полоса - узкая светлая черта у правого
-- края; её видно только тогда, когда список не помещается. Колесо мыши
-- работает над всем списком, черту можно тянуть.
W.SCROLL_STEP = 48
W.SCROLL_THUMB_MIN = 28

function W.ScrollArea(parent)
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    scroll.content = content

    local bar = CreateFrame("Frame", nil, parent)
    bar:SetWidth(8)
    bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 6, 0)
    bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 6, 0)
    local thumb = bar:CreateTexture(nil, "ARTWORK")
    thumb:SetColorTexture(1, 1, 1, 0.22)
    thumb:SetWidth(4)
    bar:Hide()
    scroll.bar, scroll.thumb = bar, thumb

    -- Высота окна списка, высота содержимого и на сколько его можно сдвинуть.
    function scroll:Range()
        local view = tonumber(self:GetHeight()) or 0
        local total = tonumber(content:GetHeight()) or 0
        return view, total, math.max(0, total - view)
    end
    function scroll:Refresh()
        local view, total, max = self:Range()
        local pos = tonumber(self:GetVerticalScroll()) or 0
        if max <= 0.5 or view <= 0 then
            bar:Hide()
            if pos ~= 0 then self:SetVerticalScroll(0) end
            return
        end
        if pos > max then
            pos = max
            self:SetVerticalScroll(pos)
        end
        local h = math.max(W.SCROLL_THUMB_MIN, view * view / total)
        thumb:SetHeight(h)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, -((view - h) * pos / max))
        bar:Show()
    end
    function scroll:ScrollBy(delta)
        local _, _, max = self:Range()
        local pos = U.clamp((tonumber(self:GetVerticalScroll()) or 0) + delta, 0, max)
        self:SetVerticalScroll(pos)
        self:Refresh()
    end

    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        self:ScrollBy(-(tonumber(delta) or 0) * W.SCROLL_STEP)
    end)
    scroll:SetScript("OnSizeChanged", function(self) self:Refresh() end)
    content:SetScript("OnSizeChanged", function() scroll:Refresh() end)

    -- Тянуть черту: список следует за курсором, пока кнопка мыши нажата.
    local function follow()
        local getPos = _G.GetCursorPosition
        if type(getPos) ~= "function" then return end
        local _, cy = getPos()
        local scale = (bar.GetEffectiveScale and bar:GetEffectiveScale()) or 1
        local top, bottom = bar:GetTop(), bar:GetBottom()
        if type(cy) ~= "number" or not (top and bottom) or top <= bottom then return end
        local view, total, max = scroll:Range()
        if max <= 0 then return end
        local h = math.max(W.SCROLL_THUMB_MIN, view * view / total)
        local frac = U.clamp(((top - cy / scale) - h / 2) / math.max(1, (top - bottom) - h), 0, 1)
        scroll:SetVerticalScroll(frac * max)
        scroll:Refresh()
    end
    bar:EnableMouse(true)
    bar:SetScript("OnMouseDown", function(self)
        follow()
        self:SetScript("OnUpdate", follow)
    end)
    bar:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
    bar:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)
    return scroll, content
end

-- A one-line "nothing here, and here is why" panel. Used instead of a blank
-- area anywhere a list can come back empty.
function W.EmptyState(parent, title, body, actionText, onAction)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetHeight(actionText and 112 or 84)

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(22, 22)
    icon:SetPoint("TOPLEFT", 4, -6)
    W.SetIcon(icon, "bulb", W.THEME.muted)

    local head = W.Label(frame, title, W.FONT_TITLE,
        W.THEME.text[1], W.THEME.text[2], W.THEME.text[3])
    head:SetPoint("TOPLEFT", frame, "TOPLEFT", 36, -6)
    head:SetPoint("RIGHT", frame, "RIGHT", -8, 0)
    head:SetJustifyH("LEFT")

    local text = W.Label(frame, body, W.FONT_SMALL,
        W.THEME.dim[1], W.THEME.dim[2], W.THEME.dim[3])
    text:SetPoint("TOPLEFT", frame, "TOPLEFT", 36, -30)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(true)

    if actionText then
        local btn = W.Button(frame, actionText, 160, 24, onAction)
        btn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 36, 6)
        frame.button = btn
    end
    frame.title, frame.body, frame.icon = head, text, icon

    -- ТЕКСТ И ВЫСОТА - ВМЕСТЕ. Высота считалась по числу строк в тексте, а в
    -- узкой колонке каждая строка переносится в несколько: текст вылезал из
    -- рамки вниз, поверх того, что стояло под ней (скриншот игрока). Теперь
    -- высоту отвечает сам текст при той ширине, которая у него есть.
    function frame:Fill(titleText, bodyText, width)
        width = math.max(120, tonumber(width) or 300)
        self:SetWidth(width)
        self.title:SetText(titleText or "")
        local h = W.SetWrapped(self.body, bodyText or "", width - 44, W.LINE)
        local total = 30 + h + 10 + (self.button and 34 or 0)
        self:SetHeight(math.max(44, total))
        return self:GetHeight()
    end
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
-- СТРОКА «ПОДПИСЬ - ЗНАЧЕНИЕ».
--
-- Значение стояло на фиксированном отступе 150, и длинная подпись заезжала на
-- него: в списке покупок цены были нарисованы поверх названий (скриншот игрока,
-- 2026-11-21: «всё на всё налазит»). Теперь место делится по измеренной ширине:
--   * подпись короткая - значения стоят ровной колонкой;
--   * подпись длиннее колонки - значение сразу за ней;
--   * вместе не помещаются - значение целиком у правого края, а подпись
--     укорачивается до него с пометкой «…».
-- Строка с ценой (row.alignRight) ставит значение у правого края всегда: цены
-- в списке покупок читаются столбцом.
--
-- Полные тексты строка помнит сама (SetBoth): при новой ширине она считает от
-- них, а не от того, что осталось после прошлого сокращения.
W.STAT_COL = 170
W.STAT_GAP = 16
W.STAT_H = 22

function W.StatRow(parent, labelText, valueText, width)
    local T = W.THEME
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(width or 300, W.STAT_H)
    local l = W.Label(row, "", W.FONT_SMALL, T.muted[1], T.muted[2], T.muted[3])
    l:SetPoint("LEFT", row, "LEFT", 0, 0)
    l:SetJustifyH("LEFT")
    l:SetWordWrap(false)
    local v = W.Label(row, "", W.FONT_SMALL, T.text[1], T.text[2], T.text[3])
    v:SetPoint("LEFT", row, "LEFT", W.STAT_COL, 0)
    v:SetJustifyH("LEFT")
    v:SetWordWrap(false)
    row.label, row.value = l, v
    row.fullLabel, row.fullValue = "", ""

    function row:Arrange()
        local full = tonumber(self:GetWidth()) or 300
        local gap = W.STAT_GAP
        self.label:SetText(self.fullLabel)
        self.value:SetText(self.fullValue)
        local lw = tonumber(self.label:GetStringWidth()) or 0
        local vw = tonumber(self.value:GetStringWidth()) or 0
        local col = self.column or W.STAT_COL
        self.value:ClearAllPoints()
        if not self.alignRight and lw + gap <= col and col + vw <= full then
            self.value:SetPoint("LEFT", self, "LEFT", col, 0)
        elseif not self.alignRight and lw + gap + vw <= full then
            self.value:SetPoint("LEFT", self, "LEFT", lw + gap, 0)
        else
            -- Значению - не больше 60% строки, остальное подписи.
            local room = math.floor(full * 0.6)
            if vw > room then
                W.SetFitted(self.value, self.fullValue, room)
                vw = tonumber(self.value:GetStringWidth()) or room
            end
            self.value:SetPoint("LEFT", self, "LEFT", math.max(0, full - vw), 0)
            if lw + gap + vw > full then
                W.SetFitted(self.label, self.fullLabel, math.max(40, full - vw - gap))
            end
        end
    end
    function row:SetBoth(label, value)
        self.fullLabel = tostring(label or "")
        self.fullValue = tostring(value or "")
        self:Arrange()
    end
    function row:Set(t)
        self.fullValue = tostring(t or "")
        self:Arrange()
    end
    row:SetBoth(labelText, valueText)
    return row
end

function W.SectionHeader(parent, text, width)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(width or 300, 26)
    local fs = W.Label(frame, text, W.FONT_TITLE,
        W.THEME.accent[1], W.THEME.accent[2], W.THEME.accent[3])
    fs:SetPoint("BOTTOMLEFT", 0, 6)
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
    local l = W.Label(frame, labelText, W.FONT_SMALL,
        W.THEME.dim[1], W.THEME.dim[2], W.THEME.dim[3])
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
    thumb:SetColorTexture(W.THEME.accent[1], W.THEME.accent[2], W.THEME.accent[3], 0.95)
    thumb:SetSize(10, 18)
    slider:SetThumbTexture(thumb)

    local value = W.Label(frame, "", W.FONT_SMALL,
        W.THEME.accent[1], W.THEME.accent[2], W.THEME.accent[3])
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

-- ОДИН ИЗ НЕСКОЛЬКИХ: кружок с точкой у выбранного варианта. Раньше выбор
-- «или то, или это» рисовался галочкой и скобками в самой подписи - «(•) В бою:
-- скрыть»; теперь у него свой знак, и подпись читается без скобок.
-- Пока клиент своих картинок не видит, это квадрат с золотой серединой.
function W.Radio(parent, labelText, onPick)
    local T = W.THEME
    local frame = CreateFrame("Button", nil, parent)
    frame:SetSize(300, 22)
    local box = CreateFrame("Frame", nil, frame)
    box:SetSize(16, 16)
    box:SetPoint("LEFT", 0, 0)
    local ring = W.Plate(box, "pill-line")
    if ring then
        ring:Colour(1, 1, 1, 0.38)
    else
        W.Backdrop(box, 1, 1, 1, 0.07, 0.22)
    end
    local dot = CreateFrame("Frame", nil, box)
    dot:SetSize(8, 8)
    dot:SetPoint("CENTER", box, "CENTER", 0, 0)
    local fill = W.Plate(dot, "pill", "OVERLAY")
    if fill then
        fill:Colour(T.accent[1], T.accent[2], T.accent[3], 1)
    else
        local tex = dot:CreateTexture(nil, "OVERLAY")
        tex:SetAllPoints(dot)
        tex:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 1)
    end
    dot:Hide()

    local l = W.Label(frame, labelText, W.FONT_SMALL, T.dim[1], T.dim[2], T.dim[3])
    l:SetPoint("LEFT", box, "RIGHT", 9, 0)
    l:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
    l:SetJustifyH("LEFT")

    frame.checked = false
    function frame:SetChecked(on)
        self.checked = on and true or false
        if self.checked then dot:Show() else dot:Hide() end
        local c = self.checked and T.text or T.dim
        l:SetTextColor(c[1], c[2], c[3])
    end
    frame:SetScript("OnClick", function(self)
        if onPick then onPick() end
    end)
    frame.label = l
    return frame
end

function W.Checkbox(parent, labelText, onToggle)
    local T = W.THEME
    local frame = CreateFrame("Button", nil, parent)
    frame:SetSize(300, 22)
    local box = CreateFrame("Frame", nil, frame)
    box:SetSize(16, 16)
    box:SetPoint("LEFT", 0, 0)
    W.Backdrop(box, 1, 1, 1, 0.07, 0.22)
    -- Галочка - свой значок; пока клиент его не видит - золотой квадрат.
    local tick = box:CreateTexture(nil, "OVERLAY")
    tick:SetPoint("CENTER")
    if W.ready then
        tick:SetSize(12, 12)
        W.SetIcon(tick, "check", T.accent)
    else
        tick:SetSize(8, 8)
        tick:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 1)
    end
    tick:Hide()

    local l = W.Label(frame, labelText, W.FONT_SMALL, T.dim[1], T.dim[2], T.dim[3])
    l:SetPoint("LEFT", box, "RIGHT", 9, 0)
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
