-- ForeverPilot / UI/TabNow.lua
--
-- Раздел «Советы» - первый экран окна. Три колонки, как в большом окне Polestar
-- (игрок попросил сделать так же, 2026-11-21: «непонятно, на какую кнопку что,
-- куда нажимать»):
--
--   слева   - профиль (что важнее) и категории советов со счётчиками;
--   в центре - шапка с названием категории и сам список, по разделам;
--   справа  - карточка выбранного совета: полный текст и ОДНА золотая кнопка.
--
-- В строке списка - только что сделать и что это даст; кнопок в строках нет.
-- Щелчок по строке выбирает совет, и всё остальное - почему, чего не хватает,
-- что нажать - стоит в карточке справа. Первый совет выбран сразу: ответ
-- по-прежнему виден без единого щелчка.
local ADDON, ns = ...

local U = ns.Util
local W = ns.Widgets
local Card = ns.Card

local Tab = {}
ns.TabNow = Tab

-- РАЗМЕТКА, ЧИСЛАМИ В ОДНОМ МЕСТЕ ---------------------------------------
--
-- Игрок присылал скриншот, на котором кнопка фильтра была нарисована ПОВЕРХ
-- строки с числами: два элемента делили одну полосу вслепую. С тех пор каждая
-- полоса своя, числа названы здесь, а Tests/test_nonsense.lua считает
-- прямоугольники по привязкам и требует, чтобы они не пересекались.
Tab.PAD = 12
Tab.SIDE_W = 170             -- левая колонка: профиль и категории
Tab.DETAIL_W = 280           -- правая колонка: карточка совета
Tab.MAIN_MIN = 240           -- меньше этого список не сжимается
Tab.BAND_H = 62              -- шапка над списком
Tab.LIST_TOP = Tab.BAND_H + 6
Tab.LIST_SIDE = 8            -- список от краёв своей колонки
Tab.SCROLLBAR_W = 22
Tab.LABEL_H = 12             -- строка мелкого шрифта
Tab.NAV_H = 22               -- строка левой колонки
Tab.SIDE_TOP = 48            -- первая подпись левой колонки, под названием аддона
Tab.SECTION_H = 22           -- заголовок раздела в списке
Tab.STRIP_H = 14             -- строка над списком: ровно одна

-- Подпись к строке над списком и путь к подробностям - словами, в одном месте.
Tab.STRIP_TITLE = "Что не показано и почему"
Tab.DETAILS_HINT = "Подробнее — наведите мышь."

-- Название категории в шапке. В левой колонке стоит короткое (ns.CHIP_LABEL).
Tab.HEADING = { ALL = "Все советы" }

-- Ширины колонок по ширине вкладки. Одна функция на код и на проверки: числа
-- разметки не повторяются в двух местах (Tests/uistub.lua, S.layout).
function Tab.Columns(width)
    width = tonumber(width) or 0
    local main = math.max(Tab.MAIN_MIN, width - Tab.SIDE_W - Tab.DETAIL_W)
    return {
        side = Tab.SIDE_W, main = main, detail = Tab.DETAIL_W,
        list = main - Tab.LIST_SIDE - (Tab.LIST_SIDE + Tab.SCROLLBAR_W),
    }
end

-- КАРТОЧКА ВЫБРАННОГО СОВЕТА (правая колонка) ----------------------------
--
-- Здесь совет стоит целиком: название, что это даст, почему, чего не хватает,
-- материалы - всё с переносом строк и без обрезки. И здесь же единственная
-- кнопка действия на всём экране - золотая. Если кнопки у совета нет (игра не
-- даёт аддонам открывать окно профессии), на её месте словами сказано, что
-- сделать самому.
--
-- Живёт в этом же файле, а не в отдельном: новый файл клиент видит только
-- после полного перезапуска игры, а не после /reload.
local Detail = {}
ns.Detail = Detail

Detail.PAD = 16
Detail.ICON = 36
Detail.BUTTON_H = 28
Detail.LINE_H = 12
Detail.TITLE_LINE_H = 14
Detail.HEAD_TOP = 14         -- строка «вид совета» от верхнего края
Detail.CLOSE_ROOM = 30       -- справа вверху стоит крестик окна

Detail.EMPTY_TITLE = "Совет не выбран"
Detail.EMPTY_BODY = "Выберите совет в списке — здесь будет, что делать."
Detail.NO_CARDS_BODY = "Под этот фильтр не попал ни один совет. Выберите другой слева."
Detail.MORE_FACTS = "Остальное — под курсором: наведите мышь на этот совет в списке."

function Detail:Build(parent)
    if self.frame then return self.frame end
    local T = W.THEME
    local f = CreateFrame("Frame", nil, parent)
    f:SetAllPoints(parent)
    self.frame = f

    self.kind = W.Label(f, "", W.FONT_SMALL, T.muted[1], T.muted[2], T.muted[3])
    self.kind:SetWordWrap(false)

    -- Иконка под курсором показывает игровую подсказку самого предмета.
    local iconHit = CreateFrame("Frame", nil, f)
    iconHit:SetSize(Detail.ICON, Detail.ICON)
    iconHit:EnableMouse(true)
    local icon = iconHit:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(iconHit)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    iconHit:SetScript("OnEnter", function(self2)
        local card = Detail.card
        if card and card.link then W.ShowItemTip(self2, card.link, nil) end
    end)
    iconHit:SetScript("OnLeave", W.HideTip)
    self.iconHit, self.icon = iconHit, icon

    self.title = W.Label(f, "", W.FONT_NORMAL, T.text[1], T.text[2], T.text[3])
    self.benefit = W.Label(f, "", W.FONT_NORMAL)
    self.badge = W.ConfBadge(f, ns.CONF.UNKNOWN)
    self.state = W.Label(f, "", W.FONT_SMALL, T.muted[1], T.muted[2], T.muted[3])
    self.meter = W.Meter(f, 54, 4)

    local rule = f:CreateTexture(nil, "BORDER")
    W.Paint(rule, T.line)
    rule:SetHeight(1)
    self.rule = rule

    self.why = W.Label(f, "", W.FONT_SMALL, T.dim[1], T.dim[2], T.dim[3])
    self.need = W.Label(f, "", W.FONT_SMALL)
    self.facts = W.Label(f, "", W.FONT_SMALL, T.muted[1], T.muted[2], T.muted[3])
    self.note = W.Label(f, "", W.FONT_SMALL, 1.00, 0.80, 0.40)
    self.place = W.Label(f, "", W.FONT_SMALL, T.muted[1], T.muted[2], T.muted[3])

    -- ГЛАВНАЯ КНОПКА. Что на ней написано и что она делает, решает
    -- Card.LiveAction в момент показа: у аукциона это «Искать на аукционе»,
    -- у рецепта - «Показать в профессии».
    self.action = W.Button(f, "", 120, Detail.BUTTON_H, function()
        if Detail.card then Card.Activate(Detail.card) end
    end)
    self.action:SetPrimary(true)
    self.action:SetScript("OnEnter", function(self2)
        self2:Repaint(true)
        local title, body = Card.ActionTip(Detail.card)
        if title then W.ShowTip(self2, title, body) end
    end)
    self.action:SetScript("OnLeave", function(self2)
        self2:Repaint(false)
        W.HideTip()
    end)

    self.route = W.Button(f, "Показать путь", 110, Detail.BUTTON_H, function()
        if Detail.card then Card.Route(Detail.card) end
    end)
    self.route:SetScript("OnEnter", function(self2)
        self2:Repaint(true)
        local card = Detail.card
        W.ShowTip(self2, "Показать путь", {
            (card and card.place and ns.Places:Describe(card.place)) or "",
            "Поставлю метку на карте и стрелку на экране.",
            "Иду я туда не сам — идёте вы.",
        })
    end)
    self.route:SetScript("OnLeave", function(self2)
        self2:Repaint(false)
        W.HideTip()
    end)

    self.emptyTitle = W.Label(f, "", W.FONT_NORMAL, T.dim[1], T.dim[2], T.dim[3])
    self.emptyBody = W.Label(f, "", W.FONT_SMALL, T.muted[1], T.muted[2], T.muted[3])
    self:Show(nil)
    return f
end

-- Всё, что рисуется только при выбранном совете.
function Detail:Parts()
    return { self.kind, self.iconHit, self.title, self.benefit, self.badge,
             self.state, self.meter, self.rule, self.why, self.need, self.facts,
             self.note, self.place, self.action, self.route }
end

-- Ширина карточки задана числом, высота - по окну (Main:HostNow): обе известны
-- сразу, без ожидания, пока клиент разложит вложенные рамки.
function Detail:Size()
    local _, height = ns.MainFrame:HostNow()
    return Tab.DETAIL_W, height
end

function Detail:ShowEmpty(body)
    local f = self.frame
    if not f then return end
    for _, el in ipairs(self:Parts()) do el:Hide() end
    local P = Detail.PAD
    local width = self:Size()
    local inner = width - 2 * P
    self.emptyTitle:ClearAllPoints()
    self.emptyTitle:SetPoint("TOPLEFT", f, "TOPLEFT", P, -(Detail.HEAD_TOP + 22))
    self.emptyTitle:SetText(Detail.EMPTY_TITLE)
    self.emptyTitle:Show()
    W.SetWrapped(self.emptyBody, body or Detail.EMPTY_BODY, inner, Detail.LINE_H)
    self.emptyBody:ClearAllPoints()
    self.emptyBody:SetPoint("TOPLEFT", f, "TOPLEFT", P, -(Detail.HEAD_TOP + 22 + 20))
    self.emptyBody:Show()
end

-- Сколько строк текста займёт фраза при такой ширине. Нужна, чтобы решить,
-- сколько строк подробностей влезет, ДО того как их ставить.
local function linesFor(text, width)
    local n = math.ceil(U.charLen(tostring(text)) * 6 / math.max(1, width * 0.9))
    return math.max(1, n)
end

function Detail:Show(card, emptyBody)
    self.card = card
    local f = self.frame
    if not f then return end
    if not card then return self:ShowEmpty(emptyBody) end
    self.emptyTitle:Hide()
    self.emptyBody:Hide()

    local T = W.THEME
    local P = Detail.PAD
    local width, height = self:Size()
    local inner = width - 2 * P

    local function put(el, x, y)
        el:ClearAllPoints()
        el:SetPoint("TOPLEFT", f, "TOPLEFT", x, -y)
        el:Show()
    end

    -- НИЗ: кнопки, над ними - место совета в общем списке, ещё выше - что
    -- делать, если кнопки нет. Считается первым: тексту сверху достаётся то,
    -- что осталось.
    local showAction = not (card.action and card.action.kind == "noop")
        and Card.ActionReady(card)
    local canRoute = card.place and card.place.routable and ns.Places:CanRoute()
    local bottom = P
    self.action:ClearAllPoints()
    self.route:ClearAllPoints()
    self.action:SetLabel(Card.ActionLabel(card))
    if showAction and canRoute then
        local rw = math.floor((inner - 8) * 0.42)
        self.route:SetSize(rw, Detail.BUTTON_H)
        self.route:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", P, P)
        self.route:SetPrimary(false)
        self.action:SetSize(inner - 8 - rw, Detail.BUTTON_H)
        self.action:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", P + rw + 8, P)
        self.route:Show()
        self.action:Show()
    elseif showAction then
        self.action:SetSize(inner, Detail.BUTTON_H)
        self.action:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", P, P)
        self.action:Show()
        self.route:Hide()
    elseif canRoute then
        -- Единственное, что здесь можно нажать, и есть главное действие.
        self.route:SetSize(inner, Detail.BUTTON_H)
        self.route:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", P, P)
        self.route:SetPrimary(true)
        self.route:Show()
        self.action:Hide()
    else
        self.action:Hide()
        self.route:Hide()
    end
    if showAction or canRoute then bottom = bottom + Detail.BUTTON_H + 10 end

    local place = Card.PlaceLine(card)
    if place then
        local ph = W.SetWrapped(self.place, place, inner, Detail.LINE_H)
        self.place:ClearAllPoints()
        self.place:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", P, bottom)
        self.place:Show()
        bottom = bottom + ph + 8
    else
        self.place:Hide()
    end

    -- КНОПКИ НЕТ - НА ЕЁ МЕСТЕ СКАЗАНО, ЧТО СДЕЛАТЬ САМОМУ: какую профессию
    -- открыть и что в ней найти (Card.ActionNoteShort). Одной фразой и про
    -- этот рецепт; длинное объяснение, почему кнопки нет, сюда не идёт - игрок
    -- просил его убрать с глаз, и оно осталось в подсказке панели.
    local note = Card.ActionNoteShort(card)
    if note and note ~= "" then
        local nh = W.SetWrapped(self.note, note, inner, Detail.LINE_H)
        self.note:ClearAllPoints()
        self.note:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", P, bottom)
        self.note:Show()
        bottom = bottom + nh + 10
    else
        self.note:Hide()
    end
    local limit = height - bottom

    -- ВЕРХ: вид совета, иконка с названием, выгода, достоверность.
    local y = Detail.HEAD_TOP
    W.SetFitted(self.kind, ns.KIND_LABEL[card.kind] or "", inner - Detail.CLOSE_ROOM)
    put(self.kind, P, y)
    y = y + Detail.LINE_H + 10

    self.icon:SetTexture(card.icon or ns.KIND_ICON[card.kind]
        or "Interface\\Icons\\INV_Misc_QuestionMark")
    put(self.iconHit, P, y)
    if card.pinTop then
        self.title:SetTextColor(1, 0.86, 0.55)
    else
        self.title:SetTextColor(T.text[1], T.text[2], T.text[3])
    end
    local th = W.SetWrapped(self.title, card.title or "", inner - Detail.ICON - 10,
        Detail.TITLE_LINE_H)
    put(self.title, P + Detail.ICON + 10, y)
    y = y + math.max(Detail.ICON, th) + 10

    local benefit = tostring(card.benefit or "")
    if benefit ~= "" then
        local bc = W.benefitColor(card.benefitKind)
        self.benefit:SetTextColor(bc[1], bc[2], bc[3])
        local bh = W.SetWrapped(self.benefit, benefit, inner, Detail.TITLE_LINE_H)
        put(self.benefit, P, y)
        y = y + bh + 8
    else
        self.benefit:Hide()
    end

    self.badge:Set(card.conf)
    put(self.badge, P, y)
    if card.plan then
        local done = card.plan.ready and (card.plan.readiness or 1) >= 1
        self.state:SetText(done and "всё есть" or "готовность")
        if done then
            self.state:SetTextColor(0.50, 0.85, 0.55)
        else
            self.state:SetTextColor(T.muted[1], T.muted[2], T.muted[3])
        end
        self.state:ClearAllPoints()
        self.state:SetPoint("LEFT", self.badge, "RIGHT", 10, 0)
        self.state:Show()
        self.meter:SetValue(card.plan.readiness or 0)
        self.meter:ClearAllPoints()
        self.meter:SetPoint("LEFT", self.state, "RIGHT", 8, 0)
        self.meter:Show()
    else
        self.state:Hide()
        self.meter:Hide()
    end
    y = y + 14 + 10

    self.rule:SetWidth(inner)
    put(self.rule, P, y)
    y = y + 1 + 10

    -- ТЕКСТ: почему, чего не хватает, подробности - с переносом и целиком.
    --
    -- Если окно низкое и всё не поместилось, место делится по важности: сначала
    -- «чего не хватает» (это то, что делать), потом «почему», и что осталось -
    -- подробностям. Обрезанное не налезает на кнопку, а про то, где прочитать
    -- остальное, сказано словами.
    local line = Detail.LINE_H
    local function whole(h) return math.floor(h / line) * line end
    local whyText, needText = tostring(card.why or ""), tostring(card.need or "")
    local cut = false

    local needH = (needText ~= "") and W.SetWrapped(self.need, needText, inner, line) or 0
    local needKeep = math.min(needH, line * 5)
    local whyRoom = (limit - y) - ((needKeep > 0) and (needKeep + 10) or 0)
    -- Строка «где прочитать остальное»: если текст придётся резать, место под
    -- неё отнимается у него же - обрезать и не сказать, где целое, нельзя.
    local pointerH = linesFor(Detail.MORE_FACTS, inner) * line
    if whyText ~= "" and whyRoom >= line then
        local h = W.SetWrapped(self.why, whyText, inner, line)
        if h > whyRoom then
            h = whole(math.max(line, whyRoom - pointerH - 8))
            self.why:SetHeight(h)
            cut = true
        end
        put(self.why, P, y)
        y = y + h + 8
    else
        self.why:Hide()
        if whyText ~= "" then cut = true end
    end

    local ready = card.plan and card.plan.ready
    if ready then
        self.need:SetTextColor(0.50, 0.85, 0.55)
    elseif card.kind == ns.KIND.SETUP then
        self.need:SetTextColor(1.00, 0.80, 0.40)
    else
        self.need:SetTextColor(0.85, 0.72, 0.45)
    end
    if needText ~= "" and (limit - y) >= line then
        local h = needH
        if h > limit - y then
            h = whole(limit - y)
            self.need:SetHeight(h)
            cut = true
        end
        put(self.need, P, y)
        y = y + h + 10
    else
        self.need:Hide()
        if needText ~= "" then cut = true end
    end

    -- Подробности: столько строк, сколько влезает. Остальное - в подсказке
    -- строки списка, и об этом сказано словами.
    local facts = Card.FactLines(card, true)
    local fit, used = {}, 0
    local room = limit - y
    if not cut then
        for i, fact in ipairs(facts) do
            local h = linesFor(fact, inner) * line
            local reserve = (i < #facts) and pointerH or 0
            if used + h + reserve > room then break end
            fit[#fit + 1] = fact
            used = used + h
        end
    end
    if (cut or #fit < #facts) and room >= pointerH then
        fit[#fit + 1] = Detail.MORE_FACTS
    end
    local factsText = table.concat(fit, "\n")
    if factsText ~= "" and room >= line then
        local h = W.SetWrapped(self.facts, factsText, inner, line)
        if h > room then
            h = whole(room)
            self.facts:SetHeight(h)
        end
        put(self.facts, P, y)
        y = y + h + 8
    else
        self.facts:Hide()
    end
end

function Tab:Build(parent)
    if self.frame then return self.frame end
    local T = W.THEME
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)
    self.frame = frame

    -- ЛЕВАЯ КОЛОНКА: что важнее и категории ----------------------------------
    local side = CreateFrame("Frame", nil, frame)
    side:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    side:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    side:SetWidth(Tab.SIDE_W)
    W.Ground(side, T.side)
    W.Hairline(side, "RIGHT")
    self.side = side

    local mark = W.Label(side, "ForeverPilot", W.FONT_TITLE,
        T.accent[1], T.accent[2], T.accent[3])
    mark:SetPoint("TOPLEFT", side, "TOPLEFT", 14, -14)
    self.wordmark = mark

    local y = Tab.SIDE_TOP
    -- Профиль - это не настройка, а первый вопрос: от него зависит порядок
    -- всего списка. Поэтому он здесь, на виду, а не в настройках.
    local profileLabel = W.Label(side, "Профиль: что важнее", W.FONT_SMALL,
        T.muted[1], T.muted[2], T.muted[3])
    profileLabel:SetPoint("TOPLEFT", side, "TOPLEFT", 14, -y)
    self.profileLabel = profileLabel
    y = y + Tab.LABEL_H + 6

    self.profileChips = {}
    for _, key in ipairs(ns.PROFILE_ORDER) do
        local row = W.NavRow(side, ns.PROFILE_LABEL[key], function()
            ns.Config:SetProfile(key)
            Tab:SyncProfiles()
            -- Жест игрока в самом окне: не откладывается ни на бегу, ни по
            -- «недавно считали» (Main:ShouldDefer, причина opened).
            ns.MainFrame:Rebuild(false, { opened = true })
        end, Tab.NAV_H)
        row:SetWidth(Tab.SIDE_W - 1)
        row:SetPoint("TOPLEFT", side, "TOPLEFT", 0, -y)
        row.tooltipTitle = ns.PROFILE_LABEL[key]
        row.tooltipText = ns.PROFILE_TIP[key]
        y = y + Tab.NAV_H
        self.profileChips[key] = row
    end

    -- Фильтр: тот же список, суженный. Число справа - сколько советов внутри;
    -- пустой фильтр виден сразу, ещё до щелчка.
    y = y + 12
    local filterLabel = W.Label(side, "Фильтр", W.FONT_SMALL,
        T.muted[1], T.muted[2], T.muted[3])
    filterLabel:SetPoint("TOPLEFT", side, "TOPLEFT", 14, -y)
    self.filterLabel = filterLabel
    y = y + Tab.LABEL_H + 6

    self.filterChips = {}
    for _, key in ipairs(ns.CHIP_ORDER) do
        local row = W.NavRow(side, ns.CHIP_LABEL[key], function()
            ns.Config:SetChip(key)
            Tab:SyncChips()
            Tab:Render()
        end, Tab.NAV_H)
        row:SetWidth(Tab.SIDE_W - 1)
        row:SetPoint("TOPLEFT", side, "TOPLEFT", 0, -y)
        y = y + Tab.NAV_H
        self.filterChips[key] = row
    end
    Tab.SIDE_USED = y

    local version = W.Label(side, "версия " .. tostring(ns.VERSION or "?"), W.FONT_SMALL,
        T.muted[1], T.muted[2], T.muted[3])
    version:SetPoint("BOTTOMLEFT", side, "BOTTOMLEFT", 14, 10)
    self.version = version

    -- СРЕДНЯЯ КОЛОНКА: шапка и список ----------------------------------------
    local mainCol = CreateFrame("Frame", nil, frame)
    mainCol:SetPoint("TOPLEFT", frame, "TOPLEFT", Tab.SIDE_W, 0)
    mainCol:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -Tab.DETAIL_W, 0)
    self.mainCol = mainCol

    local band = CreateFrame("Frame", nil, mainCol)
    band:SetPoint("TOPLEFT", mainCol, "TOPLEFT", 0, 0)
    band:SetPoint("TOPRIGHT", mainCol, "TOPRIGHT", 0, 0)
    band:SetHeight(Tab.BAND_H)
    W.Ground(band, T.band)
    W.Hairline(band, "BOTTOM")
    self.band = band

    self.heading = W.Label(band, "", W.FONT_TITLE, T.text[1], T.text[2], T.text[3])
    self.heading:SetPoint("TOPLEFT", band, "TOPLEFT", 16, -12)

    -- Строка с числами - подзаголовком в шапке, своей полосой.
    self.summary = W.Label(band, "", W.FONT_SMALL, T.dim[1], T.dim[2], T.dim[3])
    self.summary:SetPoint("TOPLEFT", band, "TOPLEFT", 16, -40)
    self.summary:SetJustifyH("LEFT")
    self.summary:SetWordWrap(false)

    -- Скрытые советы возвращаются одной кнопкой - и она есть только тогда,
    -- когда есть что возвращать.
    local hidden = W.Button(band, Tab.RESTORE_LABEL, 118, 18, function()
        Card.RestoreHidden()
    end)
    hidden:SetPoint("TOPRIGHT", band, "TOPRIGHT", -12, -12)
    hidden:SetScript("OnEnter", function(self2)
        self2:Repaint(true)
        W.ShowTip(self2, Tab.RESTORE_LABEL, {
            "Вы прятали советы правым щелчком. Эта кнопка возвращает их все.",
        })
    end)
    hidden:SetScript("OnLeave", function(self2)
        self2:Repaint(false)
        W.HideTip()
    end)
    hidden:Hide()
    self.hiddenButton = hidden

    local scroll, content = W.ScrollArea(mainCol)
    scroll:SetPoint("TOPLEFT", mainCol, "TOPLEFT", Tab.LIST_SIDE, -Tab.LIST_TOP)
    scroll:SetPoint("BOTTOMRIGHT", mainCol, "BOTTOMRIGHT",
        -(Tab.LIST_SIDE + Tab.SCROLLBAR_W), Tab.LIST_SIDE)
    self.scroll, self.content = scroll, content

    self.empty = W.EmptyState(mainCol,
        "Пока советовать нечего",
        "Это не ошибка. Ниже написано, чего мне не хватает, чтобы начать.",
        nil, nil)
    self.empty:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
    self.empty:SetPoint("RIGHT", scroll, "RIGHT", -4, 0)
    self.empty:Hide()

    -- A short list leaves most of the window blank, and blank space answers
    -- nothing. The same per-branch report the empty state shows goes under the
    -- cards: four cards plus "why there are only four" is a more useful screen
    -- than four cards and a void. Parented to the scroll child so it scrolls
    -- with the list instead of floating over it.
    self.note = W.EmptyState(content, "Почему советов так мало", "", nil, nil)
    self.note:Hide()

    -- СТРОКА НАД СПИСКОМ - ОДНА, КОРОТКАЯ, И ЭТО ТЕПЕРЬ ПРАВИЛО.
    --
    -- Здесь стояла простыня: четыре абзаца подряд (порог мелкой выгоды с
    -- разбором по видам советов, профиль, длина списка, инструкция про окно
    -- профессий) - пять строк текста до первого совета. Игрок сказал про это
    -- дословно: «всё должно быть кратко, понятно и без всяких хрени, воды, я
    -- тебе сказал это уже». И он прав: это наш регресс - убирая повторы из
    -- карточек, общие фразы перенесли сюда, и здесь они выросли.
    --
    -- Осталась ОДНА строка: часть советов не показана, и сколько их.
    -- Подробности (какой порог, по чему он выбран, где снимается, что именно
    -- убрано, почему у советов нет кнопки) отвечают на вопрос, который игрок
    -- ещё не задал, - поэтому они под курсором, а не над списком.
    --
    -- Молчанием это не становится, и это проверяется: строка есть всегда, когда
    -- что-то не показано, число в ней есть, и путь к подробностям назван в ней
    -- самой (Tests/test_vanish.lua, Tests/test_nonsense.lua).
    local strip = CreateFrame("Frame", nil, content)
    strip:SetHeight(Tab.STRIP_H)
    strip:EnableMouse(true)
    strip.text = W.Label(strip, "", W.FONT_SMALL, 1.00, 0.80, 0.40)
    strip.text:SetPoint("LEFT", strip, "LEFT", 0, 0)
    strip.text:SetJustifyH("LEFT")
    strip.text:SetWordWrap(false)
    strip:SetScript("OnEnter", function(self2)
        W.ShowTip(self2, Tab.STRIP_TITLE, self2.details or {})
    end)
    strip:SetScript("OnLeave", W.HideTip)
    strip:Hide()
    self.strip = strip

    self.sections = {}

    -- ПРАВАЯ КОЛОНКА: карточка выбранного совета ------------------------------
    local pane = CreateFrame("Frame", nil, frame)
    pane:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    pane:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    pane:SetWidth(Tab.DETAIL_W)
    W.Ground(pane, T.panel)
    W.Hairline(pane, "LEFT")
    self.pane = pane
    Detail:Build(pane)

    -- Щелчок по строке списка выбирает совет (UI/Card.lua, Card.Pick).
    Card.OnPick = function(card) Tab:SelectCard(card) end

    Tab:SyncProfiles()
    Tab:SyncChips()
    return frame
end

Tab.RESTORE_LABEL = "Вернуть скрытые"

function Tab:SyncProfiles()
    local active = ns.Config:Profile()
    for key, chip in pairs(self.profileChips or {}) do
        chip:SetSelected(key == active)
    end
end

function Tab:SyncChips()
    local active = ns.Config:Chip()
    for key, chip in pairs(self.filterChips or {}) do
        chip:SetSelected(key == active)
    end
end

-- Заголовок раздела в списке: название вида советов и сколько их.
function Tab:Section(index)
    local sec = self.sections[index]
    if sec then
        sec:Show()
        return sec
    end
    local T = W.THEME
    sec = CreateFrame("Frame", nil, self.content)
    sec:SetHeight(Tab.SECTION_H)
    sec.text = W.Label(sec, "", W.FONT_SMALL, T.dim[1], T.dim[2], T.dim[3])
    sec.text:SetPoint("BOTTOMLEFT", sec, "BOTTOMLEFT", 4, 5)
    sec.text:SetJustifyH("LEFT")
    sec.text:SetWordWrap(false)
    sec.count = W.Label(sec, "", W.FONT_SMALL, T.muted[1], T.muted[2], T.muted[3])
    sec.count:SetPoint("BOTTOMRIGHT", sec, "BOTTOMRIGHT", -8, 5)
    sec.count:SetJustifyH("RIGHT")
    W.Hairline(sec, "BOTTOM")
    self.sections[index] = sec
    return sec
end

-- ВЫБОР СОВЕТА. Только подсветка строки и карточка справа: список при этом не
-- пересчитывается и не перерисовывается.
function Tab:SelectCard(card)
    if not card then return end
    self.selected, self.selectedKey = card, card.key
    for _, row in ipairs(Card.pool) do
        if row.card and row:IsShown() then
            Card.SetSelected(row, row.card == card)
        end
    end
    Detail:Show(card)
end

-- Какой совет выбран после перерисовки: тот же, что был (по ключу - сами
-- карточки при пересчёте создаются заново), а если его больше нет - первый.
function Tab:Chosen(cards)
    local key = self.selectedKey
    if key ~= nil then
        for _, card in ipairs(cards) do
            if card.key == key then return card end
        end
    end
    return cards[1]
end

-- ОКНО ОТКРЫЛИ, А ПОД ЗАПОМНЕННЫЙ ФИЛЬТР НЕ ПОПАЛО НИЧЕГО. Игрок прислал
-- именно такой скриншот: «Можно сейчас», ноль советов - и остальные 21 где-то
-- рядом. При открытии окна пустой фильтр заменяется на «Всё»; выбрать пустой
-- руками по-прежнему можно - счётчик слева покажет ноль.
function Tab:LeaveEmptyFilter()
    local chip = ns.Config:Chip()
    if chip == ns.CHIP.ALL then return false end
    if #(ns.ActionEngine.cards or {}) == 0 then return false end
    if #ns.ActionEngine:Filtered(chip) > 0 then return false end
    ns.Config:SetChip(ns.CHIP.ALL)
    self:SyncChips()
    return true
end

function Tab:Render()
    if not self.frame then return end
    local T = W.THEME
    local chip = ns.Config:Chip()
    local cards = ns.ActionEngine:Filtered(chip)
    local meta = ns.ActionEngine.meta or {}
    local total = #(ns.ActionEngine.cards or {})

    -- Счётчики категорий и название выбранной - в шапке.
    for key, row in pairs(self.filterChips or {}) do
        local n = (key == chip) and #cards or #ns.ActionEngine:Filtered(key)
        row:SetCount(n)
        row:SetDim(n == 0)
    end
    self.heading:SetText(Tab.HEADING[chip] or ns.CHIP_LABEL[chip] or "")

    -- Ширина списка считается от окна при каждой отрисовке: так список следует
    -- за размером окна и не зависит от того, успел ли клиент разложить колонки.
    local hostW, hostH = ns.MainFrame:HostNow()
    local cols = Tab.Columns(hostW)
    local width = cols.list
    local listHeight = hostH - Tab.LIST_TOP - Tab.LIST_SIDE
    local y = 0
    local shown = 0

    -- Что скрыто и почему - ОДНОЙ строкой. Причины целиком лежат в подсказке
    -- этой же строки: показать их нужно, а читать их каждый раз - нет.
    local notices = self:Notices(meta, chip, #cards, total, cards)
    local variants = self:NoticeShort(meta, chip, #cards, total)
    if #cards > 0 and #variants > 0 then
        -- Строка стоит внутри списка с отступом 6 слева и столько же справа.
        local room = math.max(120, width - 12)
        self.strip:SetWidth(room)
        self.strip.details = notices
        W.SetFittedFrom(self.strip.text, variants, room)
        self.strip:ClearAllPoints()
        self.strip:SetPoint("TOPLEFT", self.content, "TOPLEFT", 6, -4)
        self.strip:Show()
        y = Tab.STRIP_H + 10
    else
        self.strip.details = nil
        self.strip:Hide()
    end

    -- РАЗДЕЛЫ: советы одного вида стоят вместе, под заголовком со счётчиком.
    -- Порядок разделов - по лучшему совету в каждом, порядок внутри - тот, что
    -- задал профиль. Самый важный совет по-прежнему стоит первым.
    local order, groups = {}, {}
    for _, card in ipairs(cards) do
        local kind = card.kind or "?"
        if not groups[kind] then
            groups[kind] = {}
            order[#order + 1] = kind
        end
        local g = groups[kind]
        g[#g + 1] = card
    end

    local chosen = self:Chosen(cards)
    self.selected, self.selectedKey = chosen, chosen and chosen.key or nil

    local sections = 0
    for _, kind in ipairs(order) do
        local group = groups[kind]
        sections = sections + 1
        local sec = self:Section(sections)
        sec:SetWidth(width)
        sec:ClearAllPoints()
        sec:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -y)
        sec.count:SetText(tostring(#group))
        W.SetFitted(sec.text, ns.KIND_LABEL[kind] or "Прочее", math.max(60, width - 44))
        y = y + Tab.SECTION_H
        for _, card in ipairs(group) do
            shown = shown + 1
            local row = Card.Acquire(self.content, shown)
            row:SetWidth(width)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -y)
            Card.Fill(row, card, card == chosen)
            y = y + Card.HEIGHT
        end
        y = y + 8
    end
    Card.ReleaseFrom(shown + 1)
    for i = sections + 1, #self.sections do self.sections[i]:Hide() end

    -- Under the cards: which branches produced nothing, and why. Only when
    -- there is room and something to say - a full list needs no apology.
    local roomLeft = listHeight - y
    local gaps = (shown > 0 and roomLeft > 90) and self:BranchGaps(meta) or {}
    if shown > 0 and #gaps > 0 and roomLeft > 90 then
        self.note.body:SetText(table.concat(gaps, "\n"))
        local h = math.max(60, 44 + #gaps * 15)
        self.note:SetHeight(h)
        self.note:ClearAllPoints()
        self.note:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -(y + 10))
        self.note:SetWidth(math.max(120, width - 4))
        self.note:Show()
        y = y + h + 10
    else
        self.note:Hide()
    end

    self.content:SetSize(width, math.max(1, y))

    if shown == 0 then
        self.empty:Show()
        local title, body = self:EmptyReason(meta, chip, #(ns.ActionEngine.cards or {}))
        -- Даже над пустым списком сказано, если что-то скрыто: молчаливо пустой
        -- список - ровно тот случай, ради которого объявление и существует.
        -- Здесь причины стоят целиком: читать больше нечего, и короткая строка
        -- с отсылкой к подсказке была бы хуже прямого ответа.
        if #notices > 0 then
            body = tostring(body or "") .. "\n" .. table.concat(notices, "\n")
        end
        self.empty.title:SetText(title)
        self.empty.body:SetText(body)
        -- Причин бывает несколько строк: без подстройки высоты они вылезали бы
        -- за рамку пустого состояния.
        local lines = 1
        for _ in tostring(body or ""):gmatch("\n") do lines = lines + 1 end
        -- В узкой колонке строки ещё и переносятся.
        lines = lines + math.ceil(U.charLen(tostring(body or "")) * 6 / math.max(120, width - 70))
        self.empty:SetHeight(math.max(84, 46 + lines * 15))
    else
        self.empty:Hide()
    end

    -- Что скрыто руками - возвращается кнопкой в шапке.
    local hiddenCount = tonumber(meta.hiddenByDismissal) or 0
    if hiddenCount > 0 then self.hiddenButton:Show() else self.hiddenButton:Hide() end

    local bits = {}
    bits[#bits + 1] = (meta.learnedRecipes or 0) .. " "
        .. U.plural(meta.learnedRecipes or 0, "рецепт", "рецепта", "рецептов") .. " известно"
    if meta.shoppingLines and meta.shoppingLines > 0 then
        -- «ЗАКУПКА 5з» - ЭТО НЕ ФРАЗА, А ПОМЕТКА ДЛЯ ТОГО, КТО ЗНАЕТ.
        --
        -- Игрок прочитал «75 рецептов известно • закупка 5з» и спросил, что
        -- это за деньги: его собственные? уже потраченные? Это сумма
        -- материалов, которых не хватает на советы из списка, - то есть
        -- сколько придётся потратить, если делать всё, что я насоветовал.
        -- Так и сказано; «(неполная)» заменено на причину, а не на пометку.
        local totalCost, conf = meta.shoppingTotal, meta.shoppingConf
        bits[#bits + 1] = "материалы по советам: " .. U.money(totalCost)
            .. (conf == ns.CONF.UNKNOWN and " и больше (часть цен не знаю)" or "")
    end
    local ps = meta.priceSources
    if ps and not ps.auctionatorAvailable then
        bits[#bits + 1] = "цен аукциона нет"
    end
    -- Hidden cards are invisible by definition, so the count has to be said
    -- somewhere the player will see it without having to suspect anything.
    if hiddenCount > 0 then
        bits[#bits + 1] = "скрыто " .. hiddenCount .. " (/fp show)"
    end
    -- Строка статистики - тоже числа, и резать их нельзя. Варианты - это сама
    -- строка и её части с конца: ширину она делит только с отступами.
    local stats = {}
    for i = #bits, 1, -1 do
        stats[#stats + 1] = table.concat(bits, "  •  ", 1, i)
            .. ((i < #bits) and ("  " .. U.MORE_MARK) or "")
    end
    -- В шапке строка стоит своей полосой, под названием и под кнопкой возврата.
    W.SetFittedFrom(self.summary, stats, math.max(120, cols.main - 32))

    -- Карточка справа - последней: она читает то же, что только что нарисовано.
    if chosen then
        Detail:Show(chosen)
    else
        Detail:Show(nil, (total > 0) and Detail.NO_CARDS_BODY or nil)
    end
end

-- ОДНА СТРОКА НАД СПИСКОМ: СКОЛЬКО СОВЕТОВ НЕ ПОКАЗАНО.
--
-- Три сообщения о скрытом - порог мелкой выгоды, профиль, длина списка - это
-- ОДНА мысль «часть советов не на экране», а не три абзаца. Игроку здесь нужен
-- факт и число; какой именно порог, как он выбран и где снимается - ответ на
-- вопрос, который он ещё не задал, и лежит он в подробностях под курсором
-- (Tab:Notices) и в настройках.
--
-- Возвращает варианты строки от полного к короткому: первый - с причинами,
-- последний - только факт, число и путь к подробностям. Путь назван в КАЖДОМ
-- варианте: сокращая, нельзя превратить объявление в молчание.
--
-- Скрытое самим игроком здесь не считается: его число стоит в строке
-- статистики справа, а когда скрыто всё - об этом отдельная карточка.
function Tab:NoticeShort(meta, chip, shown, total)
    meta = meta or {}
    shown, total = tonumber(shown) or 0, tonumber(total) or 0
    local hidden, causes = 0, {}
    local function cause(n, text)
        n = tonumber(n) or 0
        if n <= 0 then return end
        hidden = hidden + n
        causes[#causes + 1] = text
    end
    if chip and chip ~= ns.CHIP.ALL and shown < total then
        cause(total - shown, "фильтр «" .. (ns.CHIP_LABEL[chip] or tostring(chip)) .. "»")
    end
    cause(meta.moneyFloorDropped, "порог выгоды")
    cause(meta.profileDropped,
        "профиль «" .. (ns.PROFILE_LABEL[ns.Config:Profile()] or "?") .. "»")
    local generated = tonumber(meta.generated) or 0
    if total > 0 then cause(generated - total, "длина списка") end
    if hidden <= 0 then return {}, 0 end

    -- Число стоит после двоеточия, а не перед словом: так строка верна при
    -- любом числе и не требует согласования («1 совет», «2 совета», «5
    -- советов» - три разных слова на одном месте).
    local head = "Не показано советов: " .. hidden
    local out = {}
    if #causes > 0 then
        local why = " — " .. table.concat(causes, ", ") .. ". " .. Tab.DETAILS_HINT
        out[#out + 1] = head .. why
        -- Список теперь уже (рядом с ним колонка категорий и карточка совета),
        -- поэтому есть средний вариант: причина остаётся, уходит одно слово.
        out[#out + 1] = "Не показано: " .. hidden .. why
    end
    out[#out + 1] = head .. ". " .. Tab.DETAILS_HINT
    return out, hidden
end

-- ЧТО ИЗ СОВЕТОВ СЕЙЧАС НЕ ПОКАЗАНО, ХОТЯ ОНО ЕСТЬ. По строке на причину.
--
-- Совет может не быть на экране по трём причинам, и ни одна из них не скрытие:
--
--   1. ФИЛЬТР. Щелчок по «Чары» оставляет в списке одни чары. Выбор
--      сохраняется между сессиями, и на следующий день это выглядит как
--      «советов стало мало»: подсветка маленькой кнопки - единственное, что об
--      этом напоминало.
--   2. ПРОФИЛЬ. Каждый профиль убирает часть советов (перекупку, справку про
--      цены, распыление). В движке так и написано: убирает «НЕ МОЛЧА», причина
--      «видна в окне». Видна она не была: показывалась только у веток, не
--      выдавших ни одного совета, а профиль убирает их у веток, которые как
--      раз выдали. У игрока в диагностике 72 убранных совета за сессию и ни
--      слова об этом на экране.
--   3. ДЛИНА. Список ограничен, и то, что не поместилось, раньше пропадало
--      без следа (замечала это только самопроверка в /fp diag).
--
-- Про скрытые игроком советы здесь НЕ говорится: их число стоит в сводке
-- справа, а когда скрыто всё - об этом отдельная карточка.
--
--   shown - сколько советов в списке под текущим фильтром
--   total - сколько их без фильтра
function Tab:Notices(meta, chip, shown, total, cards)
    meta = meta or {}
    shown, total = tonumber(shown) or 0, tonumber(total) or 0
    local out = {}

    -- Пустой список под фильтром объясняет EmptyReason: теми же словами второй
    -- раз говорить незачем.
    if chip and chip ~= ns.CHIP.ALL and shown > 0 and shown < total then
        out[#out + 1] = "Фильтр «" .. (ns.CHIP_LABEL[chip] or tostring(chip))
            .. "»: показано " .. shown .. " из " .. total .. " "
            .. U.plural(total, "совета", "советов", "советов")
            .. ". Нажмите «" .. ns.CHIP_LABEL[ns.CHIP.ALL] .. "», чтобы увидеть остальные."
    end

    -- ПОРОГ МЕЛКОЙ ДЕНЕЖНОЙ ВЫГОДЫ. Отдельной строкой и раньше профиля: это
    -- правило самого игрока, и если оно съело половину денежных советов, он
    -- должен прочитать это первым, а не догадываться. Слова собирает движок
    -- (Engine.MoneyFloorText) - здесь они только ставятся с большой буквы и
    -- заканчиваются точкой.
    local byFloor = tonumber(meta.moneyFloorDropped) or 0
    if byFloor > 0 and meta.moneyFloorNote then
        out[#out + 1] = U.endSentence(U.capitalize(meta.moneyFloorNote))
    end

    local dropped = tonumber(meta.profileDropped) or 0
    if dropped > 0 then
        local names = {}
        for kind, n in pairs(meta.profileDroppedByKind or {}) do
            names[#names + 1] = (ns.KIND_LABEL[kind] or tostring(kind)) .. " (" .. n .. ")"
        end
        table.sort(names)
        out[#out + 1] = "Профиль «" .. (ns.PROFILE_LABEL[ns.Config:Profile()] or "?")
            .. "» не показывает " .. dropped .. " "
            .. U.plural(dropped, "совет", "совета", "советов")
            .. ((#names > 0) and (": " .. table.concat(names, ", ")) or "")
            .. " — в другом профиле они вернутся."
    end

    local generated = tonumber(meta.generated) or 0
    if generated > total and total > 0 then
        -- Сказуемое согласуется с числом: «не поместился 1 совет», «не
        -- поместились 2 совета», «не поместилось 5 советов».
        local over = generated - total
        out[#out + 1] = "В список "
            .. U.plural(over, "не поместился", "не поместились", "не поместилось")
            .. " " .. over .. " " .. U.plural(over, "совет", "совета", "советов")
            .. ": показаны " .. total .. " лучших из " .. generated .. "."
    end

    -- У СОВЕТА НЕТ КНОПКИ - И СКАЗАНО ПОЧЕМУ. Одна строка на все такие советы,
    -- а не по строке на каждый: причина у них общая (см. Card.ActionNote).
    local said = {}
    for _, card in ipairs(cards or {}) do
        local note = ns.Card.ActionNote(card)
        if note and not said[note] then
            said[note] = true
            out[#out + 1] = note
        end
    end
    return out
end

-- One line per branch that produced nothing, in the branch's own words. The
-- reasons come straight out of the build - the UI invents none of them - so a
-- branch with no recorded reason says so rather than being quietly skipped.
-- Shared by the empty state and by the note under a short list.
function Tab:BranchGaps(meta)
    local out = {}
    for _, br in ipairs((meta or {}).branches or {}) do
        if (br.count or 0) == 0 then
            out[#out + 1] = "• " .. (br.label or br.key or "?") .. " — "
                .. (br.reason or "причина не записана — это дефект диагностики")
        end
    end
    local ps = (meta or {}).priceSources
    if ps and not ps.auctionatorAvailable then
        out[#out + 1] = "• Цены — Auctionator не загружен, поэтому всё про деньги"
            .. " я считать не могу. Сила и навык от этого не зависят."
    end
    if ((meta or {}).hiddenByDismissal or 0) > 0 then
        out[#out + 1] = "• Скрыто вами — " .. meta.hiddenByDismissal
            .. ", вернуть всё: /fp show"
    end
    return out
end

-- There is always a reason. Never a blank panel.
--
-- Three different situations, three different answers, and the counter in the
-- status bar decides which. Saying "советы есть, но не этого типа" while the
-- counter reads "0 советов" is the one thing this function must never do: it
-- sends the player hunting for a list that does not exist.
--   A. the list has cards, this filter has none of them
--   B. the list is empty, and here is what each branch is missing
--   C. nothing has been read yet, so there is nothing to be empty about
--
-- `total` is the number of cards the engine built, filter-independent.
function Tab:EmptyReason(meta, chip, total)
    meta = meta or {}
    total = tonumber(total) or 0

    -- C. Nothing collected yet. A build that never finished leaves no builtAt,
    -- and a profession window the player has not opened leaves no recipes -
    -- both mean "ask me later", not "there is nothing to do".
    if meta.error then
        return "Данные ещё не собраны",
            "Пересчёт не дошёл до конца: " .. tostring(meta.error)
            .. ". Нажмите «Обновить» — если повторится, посмотрите /fp diag."
    end
    if not meta.builtAt or meta.builtAt == 0 then
        return "Данные ещё не собраны",
            "Я ещё ни разу не считал этот список. Нажмите «Обновить»"
            .. " или откройте окно любой профессии — пересчёт пойдёт сам."
    end

    local missing = meta.missingProfessions or {}
    if #missing > 0 then
        local names = {}
        for _, p in ipairs(missing) do names[#names + 1] = p.name end
        return "Данные ещё не собраны: не вижу рецептов",
            "Откройте окно профессии один раз: " .. table.concat(names, ", ")
            .. ". Игра не отдаёт список рецептов, пока окно не открыли,"
            .. " поэтому до этого мне нечего считать."
    end

    if (meta.learnedRecipes or 0) == 0 then
        return "Данные ещё не собраны: выученных рецептов не найдено",
            "Либо профессий ещё нет, либо окно профессии не открывали."
            .. " Загляните в раздел «Персонаж» — там видно, что именно я прочитал."
    end

    -- A. There really are cards; this chip just lets none of them through.
    -- Guarded by `total > 0`, which is the whole point of this rewrite.
    if total > 0 then
        if chip ~= ns.CHIP.ALL then
            return "В этом фильтре пусто",
                "Советов у меня " .. total .. ", но ни один не подходит под фильтр «"
                .. (ns.CHIP_LABEL[chip] or chip) .. "». Нажмите «Всё» слева,"
                .. " чтобы увидеть весь список."
        end
        -- Cards exist and the filter is "Всё", so an empty panel here is a
        -- drawing fault, not a data one. Say that rather than invent a reason.
        return "Советы есть, но список не нарисовался",
            "Их " .. total .. ", а на экране ни одного — это ошибка отображения,"
            .. " а не отсутствие советов. Нажмите «Обновить» и загляните в /fp diag."
    end

    -- B. Genuinely nothing. List what each branch was missing, by name.
    local hidden = meta.hiddenByDismissal or 0
    if hidden > 0 then
        -- Два разных срока за два разных действия, и оба названы вместе с
        -- местом: в списке - два правых щелчка и сутки, на панели - правый
        -- щелчок и час. «Кнопка на самом совете — на час» здесь стояло зря:
        -- такой кнопки не было, а прятали на час «Дальше» и левый щелчок по
        -- информационному совету, которые теперь не прячут ничего.
        -- И никакая кнопка по имени тут не называется: на пустом экране её нет,
        -- а движок в этом состоянии и так выдаёт карточку с «Вернуть все».
        return "Все советы скрыты вами",
            "Скрыто карточек: " .. hidden .. ". Два правых щелчка по совету"
            .. " прячут его: в списке — на "
            .. (U.durationText(ns.DISMISS_SECONDS) or "сутки")
            .. ", на панели — на "
            .. (U.durationText(ns.SNOOZE_SECONDS) or "час") .. "."
            .. " Наберите /fp show — вернутся все сразу."
    end

    local lines = { "Советов нет ни одного. Вот чего не хватает каждой ветке:" }
    for _, line in ipairs(self:BranchGaps(meta)) do
        lines[#lines + 1] = line
    end
    if #lines == 1 then
        lines[#lines + 1] = "• ни одна ветка не записала причину — это дефект"
            .. " диагностики, покажите /fp diag"
    end
    lines[#lines + 1] = "Можно попробовать другой профиль — он слева от списка."
    return "Пока советовать нечего", table.concat(lines, "\n")
end

function Tab:OnShow()
    Tab:SyncProfiles()
    Tab:SyncChips()
    Tab:Render()
end

return Tab
