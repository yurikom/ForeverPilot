-- ForeverPilot / UI/TabNow.lua
--
-- Раздел «Советы» - первый экран окна. Три колонки, как в большом окне Polestar
-- (игрок попросил сделать так же, 2026-11-21: «непонятно, на какую кнопку что,
-- куда нажимать»):
--
--   слева   - фильтр: один список со значками и счётчиками;
--   в центре - шапка с названием, под ней вкладки профиля («что важнее») и сам
--              список советов, по разделам;
--   справа  - карточка выбранного совета и ОДНА золотая кнопка.
--
-- Фильтр и профиль разведены нарочно: в первой версии они стояли двумя списками
-- в одной колонке, и игрок сказал, что непонятно, что где («фильтры вместе,
-- профиль вместе»). Теперь слева только «что показывать», а «в каком порядке» -
-- вкладками над списком.
--
-- НА ЭКРАНЕ - ТОЛЬКО ТО, ЧТО НУЖНО, ЧТОБЫ СДЕЛАТЬ: что это, что даст, где
-- купить или продать, сколько стоит. Откуда взято число и насколько ему
-- верить, здесь не пишется: игрок назвал это лишним («мне не нужно знать,
-- откуда ты брал эти данные»). Всё это по-прежнему есть в файле диагностики.
local ADDON, ns = ...

local U = ns.Util
local W = ns.Widgets
local Card = ns.Card

local Tab = {}
ns.TabNow = Tab

-- РАЗМЕТКА, ЧИСЛАМИ В ОДНОМ МЕСТЕ ---------------------------------------
--
-- Игрок присылал скриншоты, где одно нарисовано поверх другого. С тех пор
-- каждая полоса своя, числа названы здесь, а проверки считают прямоугольники
-- по привязкам и требуют, чтобы они не пересекались.
Tab.PAD = 12
Tab.SIDE_W = 184             -- левая колонка: фильтр
Tab.DETAIL_W = 292           -- правая колонка: карточка совета
Tab.MAIN_MIN = 250           -- меньше этого список не сжимается
Tab.BAND_H = 108             -- шапка: название, строка под ним, вкладки профиля
Tab.TABS_H = 28
Tab.LIST_TOP = Tab.BAND_H + 8
Tab.LIST_SIDE = 12           -- список от краёв своей колонки
Tab.SCROLLBAR_W = 16
Tab.NAV_H = 30               -- строка фильтра
Tab.SIDE_TOP = 76            -- первая строка фильтра, под названием аддона
Tab.SECTION_H = 30           -- заголовок раздела в списке

-- Название фильтра в шапке. В левой колонке стоит короткое (ns.CHIP_LABEL).
Tab.HEADING = { ALL = "Все советы" }
-- Значки фильтра и профиля - из своего набора (Media\icon-*.tga).
Tab.CHIP_ICON = { ALL = "list", READY = "ready", GEAR = "shield", ENCHANT = "sparkle",
                  CRAFT = "hammer", GOLD = "coin" }
Tab.PROFILE_PREFIX = "Что важнее:"
Tab.RESTORE_LABEL = "Вернуть скрытые"

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
-- Сверху вниз: вид совета, иконка с названием, метки (что даст, готово ли),
-- короткий текст, строки «подпись - значение», что и где купить, и внизу
-- кнопки - тихая и золотая. Если кнопки у совета нет, на её месте словами
-- сказано, что сделать самому. Что именно показать, решает Card.Sheet
-- (UI/Card.lua); здесь только раскладка.
--
-- Живёт в этом же файле, а не в отдельном: новый файл клиент видит только
-- после полного перезапуска игры, а не после /reload.
local Detail = {}
ns.Detail = Detail

Detail.PAD = 20
Detail.ICON = 44
Detail.BUTTON_H = 32
Detail.LINE_H = W.LINE
Detail.TITLE_LINE_H = 19
Detail.HEAD_TOP = 18         -- строка «вид совета» от верхнего края
Detail.CORNER_ROOM = 64      -- справа вверху стоят «обновить» и «закрыть»
Detail.LABEL_W = 86          -- колонка подписей в строках «подпись - значение»
Detail.ROW_GAP = 7
Detail.BLOCK_GAP = 12        -- перед заголовком блока покупок
Detail.CAPTION_H = 20        -- заголовок блока («Купить на аукционе»)
Detail.ITEM_H = 20           -- строка блока: название слева, цена справа
Detail.MAX_ROWS = 8
Detail.MAX_BLOCKS = 4
Detail.MAX_ITEMS = 14

Detail.EMPTY_TITLE = "Совет не выбран"
Detail.EMPTY_BODY = "Щёлкните совет в списке — здесь будет, что делать."
Detail.NO_CARDS_BODY = "Под этот фильтр не попал ни один совет. Выберите другой слева."
Detail.STATE_READY = "всё есть"
Detail.STATE_SHORT = "нужны материалы"

-- Значок на кнопке - по тому, что она сделает.
Detail.ACTION_ICON = { auction = "search", showRecipe = "book", shop = "plus",
                       unpin = "undo", showItem = "eye", undismiss = "undo",
                       openProfession = "check" }

function Detail:Build(parent)
    if self.frame then return self.frame end
    local T = W.THEME
    local f = CreateFrame("Frame", nil, parent)
    f:SetAllPoints(parent)
    self.frame = f

    self.kind = W.Label(f, "", W.FONT_CAPTION, T.muted[1], T.muted[2], T.muted[3])
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

    self.title = W.Label(f, "", W.FONT_TITLE, T.text[1], T.text[2], T.text[3])
    self.benefit = W.Pill(f, "", T.accent)
    -- Длинная выгода («костёр для готовки и место ещё под 3 предмета лагеря»)
    -- в метку не помещается: она идёт обычной строкой с переносом.
    self.benefitLine = W.Label(f, "", W.FONT_NORMAL)
    self.state = W.Pill(f, "", T.good)

    local rule = f:CreateTexture(nil, "BORDER")
    W.Paint(rule, T.line)
    rule:SetHeight(1)
    self.rule = rule

    self.warn = W.Label(f, "", W.FONT_SMALL, T.warn[1], T.warn[2], T.warn[3])
    self.lead = W.Label(f, "", W.FONT_SMALL, T.dim[1], T.dim[2], T.dim[3])
    self.need = W.Label(f, "", W.FONT_SMALL, T.text[1], T.text[2], T.text[3])

    -- Строки «подпись - значение».
    self.rows = {}
    for i = 1, Detail.MAX_ROWS do
        local label = W.Label(f, "", W.FONT_CAPTION, T.muted[1], T.muted[2], T.muted[3])
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
        local value = W.Label(f, "", W.FONT_SMALL, T.text[1], T.text[2], T.text[3])
        value:SetJustifyH("LEFT")
        self.rows[i] = { label = label, value = value }
    end

    -- Блоки покупок: заголовок («Купить у торговца») и строки под ним.
    self.captions = {}
    for i = 1, Detail.MAX_BLOCKS do
        local caption = W.Label(f, "", W.FONT_CAPTION, T.muted[1], T.muted[2], T.muted[3])
        caption:SetJustifyH("LEFT")
        caption:SetWordWrap(false)
        self.captions[i] = caption
    end
    self.items = {}
    for i = 1, Detail.MAX_ITEMS do
        local left = W.Label(f, "", W.FONT_SMALL, T.text[1], T.text[2], T.text[3])
        left:SetJustifyH("LEFT")
        left:SetWordWrap(false)
        local right = W.Label(f, "", W.FONT_SMALL, T.dim[1], T.dim[2], T.dim[3])
        right:SetJustifyH("RIGHT")
        right:SetWordWrap(false)
        self.items[i] = { left = left, right = right }
    end
    self.more = W.Label(f, "", W.FONT_CAPTION, T.muted[1], T.muted[2], T.muted[3])
    self.more:SetWordWrap(false)

    self.note = W.Label(f, "", W.FONT_SMALL, T.text[1], T.text[2], T.text[3])

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
    self.route:SetIcon("route", 14)
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

    self.emptyTitle = W.Label(f, "", W.FONT_TITLE, T.dim[1], T.dim[2], T.dim[3])
    self.emptyBody = W.Label(f, "", W.FONT_SMALL, T.muted[1], T.muted[2], T.muted[3])
    self:Show(nil)
    return f
end

-- Всё, что рисуется только при выбранном совете.
function Detail:Parts()
    local parts = { self.kind, self.iconHit, self.title, self.benefit, self.benefitLine,
                    self.state, self.rule, self.warn, self.lead, self.need, self.more,
                    self.note, self.action, self.route }
    for _, row in ipairs(self.rows) do
        parts[#parts + 1] = row.label
        parts[#parts + 1] = row.value
    end
    for _, caption in ipairs(self.captions) do parts[#parts + 1] = caption end
    for _, item in ipairs(self.items) do
        parts[#parts + 1] = item.left
        parts[#parts + 1] = item.right
    end
    return parts
end

-- ЧТО СЕЙЧАС НАРИСОВАНО В КАРТОЧКЕ, ПО ЧАСТЯМ: имя части и её строка.
-- Нужно проверкам (ничто не налезает, тексты не обрезаны, оговорок об источнике
-- нет) и картинке окна; сама карточка этим не пользуется.
--   body = true - содержание совета (без шапки: вида, названия и меток)
function Detail:Shown(body)
    local out = {}
    local function add(role, fs)
        if fs and fs:IsShown() and (fs:GetText() or "") ~= "" then
            out[#out + 1] = { role = role, fs = fs }
        end
    end
    if not self.frame or not self.card then return out end
    if not body then
        add("вид совета", self.kind)
        add("название", self.title)
        if self.benefit:IsShown() then add("выгода", self.benefit.text) end
        add("выгода", self.benefitLine)
        if self.state:IsShown() then add("готовность", self.state.text) end
    end
    add("сомнение", self.warn)
    add("суть", self.lead)
    for i, row in ipairs(self.rows) do
        add("подпись строки " .. i, row.label)
        add("значение строки " .. i, row.value)
    end
    for i, caption in ipairs(self.captions) do add("заголовок блока " .. i, caption) end
    for i, item in ipairs(self.items) do
        add("позиция " .. i, item.left)
        add("цена позиции " .. i, item.right)
    end
    add("ещё позиции", self.more)
    add("что сделать", self.need)
    add("что сделать самому", self.note)
    return out
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
    self.emptyTitle:SetPoint("TOPLEFT", f, "TOPLEFT", P, -(Detail.HEAD_TOP + 34))
    self.emptyTitle:SetText(Detail.EMPTY_TITLE)
    self.emptyTitle:Show()
    W.SetWrapped(self.emptyBody, body or Detail.EMPTY_BODY, inner, Detail.LINE_H)
    self.emptyBody:ClearAllPoints()
    self.emptyBody:SetPoint("TOPLEFT", f, "TOPLEFT", P, -(Detail.HEAD_TOP + 34 + 26))
    self.emptyBody:Show()
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
    local line = Detail.LINE_H
    local width, height = self:Size()
    local inner = width - 2 * P
    local sheet = Card.Sheet(card)
    self.sheet = sheet

    local function put(el, x, y)
        el:ClearAllPoints()
        el:SetPoint("TOPLEFT", f, "TOPLEFT", x, -y)
        el:Show()
    end

    -- НИЗ: кнопки, а если кнопки нет - что сделать самому. Считается первым:
    -- тексту сверху достаётся то, что осталось.
    local live = Card.LiveAction(card)
    local showAction = not (card.action and card.action.kind == "noop")
        and Card.ActionReady(card)
    local canRoute = card.place and card.place.routable and ns.Places:CanRoute()
    local bottom = P
    self.action:ClearAllPoints()
    self.route:ClearAllPoints()
    self.action:SetLabel(Card.ActionLabel(card))
    local glyph = live and Detail.ACTION_ICON[live.kind] or nil
    if live and live.kind == "showRecipe" and live.shown then glyph = "undo" end
    self.action:SetIcon(glyph, 14)
    local stacked = false
    if showAction and canRoute then
        self.route:SetPrimary(false)
        -- Рядом - только если обе подписи помещаются целиком; иначе одна над
        -- другой: золотая внизу, тихая над ней. Подпись, вылезшая за край
        -- кнопки, - тот же дефект, что текст поверх текста.
        local need = self.route:LabelWidth() + self.action:LabelWidth() + 8
        if need <= inner then
            local rw = math.floor(self.route:LabelWidth()
                + (inner - need) * 0.4)
            self.route:Resize(rw, Detail.BUTTON_H)
            self.route:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", P, P)
            self.action:Resize(inner - 8 - rw, Detail.BUTTON_H)
            self.action:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", P + rw + 8, P)
        else
            stacked = true
            self.action:Resize(inner, Detail.BUTTON_H)
            self.action:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", P, P)
            self.route:Resize(inner, Detail.BUTTON_H)
            self.route:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", P, P + Detail.BUTTON_H + 8)
        end
        self.route:Show()
        self.action:Show()
    elseif showAction then
        self.action:Resize(inner, Detail.BUTTON_H)
        self.action:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", P, P)
        self.action:Show()
        self.route:Hide()
    elseif canRoute then
        -- Единственное, что здесь можно нажать, и есть главное действие.
        self.route:Resize(inner, Detail.BUTTON_H)
        self.route:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", P, P)
        self.route:SetPrimary(true)
        self.route:Show()
        self.action:Hide()
    else
        self.action:Hide()
        self.route:Hide()
    end
    if showAction or canRoute then bottom = bottom + Detail.BUTTON_H + 12 end
    if stacked then bottom = bottom + Detail.BUTTON_H + 8 end

    -- КНОПКИ НЕТ - НА ЕЁ МЕСТЕ СКАЗАНО, ЧТО СДЕЛАТЬ САМОМУ: какую профессию
    -- открыть и что в ней найти. Одной фразой и про этот рецепт.
    local note = U.essence(Card.ActionNoteShort(card) or "", 2)
    if note ~= "" then
        local nh = W.SetWrapped(self.note, note, inner, line)
        self.note:ClearAllPoints()
        self.note:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", P, bottom)
        self.note:Show()
        bottom = bottom + nh + 12
    else
        self.note:Hide()
    end
    local limit = height - bottom

    -- ВЕРХ: вид совета, иконка с названием, метки.
    local y = Detail.HEAD_TOP
    W.SetFitted(self.kind, ns.KIND_LABEL[card.kind] or "", inner - Detail.CORNER_ROOM)
    put(self.kind, P, y)
    y = y + line + 12

    self.icon:SetTexture(card.icon or ns.KIND_ICON[card.kind]
        or "Interface\\Icons\\INV_Misc_QuestionMark")
    put(self.iconHit, P, y)
    if card.pinTop then
        self.title:SetTextColor(T.warn[1], T.warn[2], T.warn[3])
    else
        self.title:SetTextColor(T.text[1], T.text[2], T.text[3])
    end
    local th = W.SetWrapped(self.title, card.title or "", inner - Detail.ICON - 12,
        Detail.TITLE_LINE_H)
    put(self.title, P + Detail.ICON + 12, y)
    y = y + math.max(Detail.ICON, th) + 14

    -- Метки: что это даст и, если у совета есть план, готово ли всё для него.
    local benefit = tostring(card.benefit or "")
    local colour = W.benefitColor(card.benefitKind)
    local x = P
    self.benefit:Hide()
    self.benefitLine:Hide()
    if benefit ~= "" then
        self.benefit:Set(benefit, colour)
        if (tonumber(self.benefit:GetWidth()) or 0) <= inner then
            put(self.benefit, x, y)
            x = x + (tonumber(self.benefit:GetWidth()) or 0) + 6
        else
            self.benefitLine:SetTextColor(colour[1], colour[2], colour[3])
            local bh = W.SetWrapped(self.benefitLine, benefit, inner, line)
            put(self.benefitLine, P, y)
            y = y + bh + 8
        end
    end
    if card.plan then
        local done = card.plan.ready and true or false
        self.state:Set(done and Detail.STATE_READY or Detail.STATE_SHORT,
            done and T.good or T.warn)
        local sw = tonumber(self.state:GetWidth()) or 0
        if x > P and x + sw > P + inner then
            -- Не поместилась рядом - встаёт строкой ниже.
            y = y + 20 + 6
            x = P
        end
        put(self.state, x, y)
        x = x + sw
    else
        self.state:Hide()
    end
    if x > P then y = y + 20 end
    y = y + 14

    self.rule:SetWidth(inner)
    put(self.rule, P, y)
    y = y + 1 + 12

    -- ТЕКСТ. Если окно низкое и текст не поместился, он обрезается по целой
    -- строке, а не налезает на кнопку.
    local function whole(h) return math.floor(h / line) * line end
    local function block(fs, text, gap)
        text = tostring(text or "")
        if text == "" or (limit - y) < line then
            fs:Hide()
            return false
        end
        local h = W.SetWrapped(fs, text, inner, line)
        if h > limit - y then
            h = whole(limit - y)
            fs:SetHeight(h)
        end
        put(fs, P, y)
        y = y + h + (gap or 12)
        return true
    end
    block(self.warn, sheet.warn)
    block(self.lead, sheet.lead)

    -- «ЧТО СДЕЛАТЬ» СТОИТ ПОСЛЕДНИМ, НО МЕСТО ЕМУ ОТВЕДЕНО ЗАРАНЕЕ: в низком
    -- окне длинный список покупок иначе вытеснил бы фразу с координатами
    -- торговца. Строки и блоки кончаются там, где начинается она.
    local needH = 0
    if sheet.need ~= "" then
        needH = W.SetWrapped(self.need, sheet.need, inner, line) + 12
    end
    local roomEnd = math.max(y, limit - needH)

    -- СТРОКИ «ПОДПИСЬ - ЗНАЧЕНИЕ»: то, ради чего карточку открывают.
    local valueW = inner - Detail.LABEL_W
    local shown = 0
    for i, slot in ipairs(self.rows) do
        local row = sheet.rows[i]
        local fits = false
        if row then
            local h = W.SetWrapped(slot.value, row.value, valueW, line)
            if y + h <= roomEnd then
                slot.label:SetText(row.label)
                local c = (row.tone == "warn") and T.warn or T.text
                slot.value:SetTextColor(c[1], c[2], c[3])
                put(slot.label, P, y + 1)
                put(slot.value, P + Detail.LABEL_W, y)
                y = y + math.max(line, h) + Detail.ROW_GAP
                shown = shown + 1
                fits = true
            end
        end
        if not fits then
            slot.label:Hide()
            slot.value:Hide()
        end
    end
    if shown > 0 then y = y + 5 end

    -- ЧТО И ГДЕ КУПИТЬ: блоками по месту покупки, цена справа. Что не
    -- поместилось по высоте, названо числом в последней строке.
    local total = 0
    for _, b in ipairs(sheet.blocks) do total = total + #b.lines end
    local usedCaptions, usedItems, placed = 0, 0, 0
    local full = false
    for _, b in ipairs(sheet.blocks) do
        if full then break end
        local rest = total - placed
        local room = roomEnd - y
        -- Заголовок ставится только вместе с первой своей строкой, а если после
        -- неё останется ещё что-то - с местом под строку «и ещё N».
        local need = Detail.BLOCK_GAP + Detail.CAPTION_H + Detail.ITEM_H
            + ((rest > 1) and Detail.ITEM_H or 0)
        if usedCaptions >= Detail.MAX_BLOCKS or room < need then
            full = true
        else
            if placed > 0 or shown > 0 then y = y + Detail.BLOCK_GAP end
            usedCaptions = usedCaptions + 1
            local caption = self.captions[usedCaptions]
            caption:SetText(b.caption or "")
            put(caption, P, y)
            y = y + Detail.CAPTION_H
            for _, entry in ipairs(b.lines) do
                local left = total - placed
                local needs = Detail.ITEM_H + ((left > 1) and Detail.ITEM_H or 0)
                if usedItems >= Detail.MAX_ITEMS or (roomEnd - y) < needs then
                    full = true
                    break
                end
                usedItems = usedItems + 1
                local item = self.items[usedItems]
                item.right:SetText(entry.right or "")
                local rw = tonumber(item.right:GetStringWidth()) or 0
                item.right:ClearAllPoints()
                item.right:SetPoint("TOPRIGHT", f, "TOPLEFT", P + inner, -y)
                item.right:Show()
                W.SetFittedFrom(item.left, entry.variants or { entry.left or "" },
                    math.max(40, inner - rw - 12))
                put(item.left, P, y)
                y = y + Detail.ITEM_H
                placed = placed + 1
            end
        end
    end
    for i = usedCaptions + 1, #self.captions do self.captions[i]:Hide() end
    for i = usedItems + 1, #self.items do
        self.items[i].left:Hide()
        self.items[i].right:Hide()
    end
    if total > placed and (roomEnd - y) >= Detail.ITEM_H then
        local rest = total - placed
        self.more:SetText("и ещё " .. rest .. " "
            .. U.plural(rest, "позиция", "позиции", "позиций"))
        put(self.more, P, y + 2)
        y = y + Detail.ITEM_H
    else
        self.more:Hide()
    end
    if placed > 0 then y = y + 6 end

    -- Что ещё сделать или чего не хватает.
    local short = sheet.need ~= "" and (U.contains(U.lower(sheet.need), "не хватает")
        or (card.risk and card.risk.overWallet))
    local c = short and T.warn or T.text
    self.need:SetTextColor(c[1], c[2], c[3])
    block(self.need, sheet.need)
end

function Tab:Build(parent)
    if self.frame then return self.frame end
    local T = W.THEME
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)
    self.frame = frame

    -- ЛЕВАЯ КОЛОНКА: фильтр ---------------------------------------------------
    local side = CreateFrame("Frame", nil, frame)
    side:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    side:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    side:SetWidth(Tab.SIDE_W)
    W.Ground(side, T.side)
    W.Hairline(side, "RIGHT")
    self.side = side

    local mark = W.Label(side, "ForeverPilot", W.FONT_TITLE,
        T.accent[1], T.accent[2], T.accent[3])
    mark:SetPoint("TOPLEFT", side, "TOPLEFT", 18, -20)
    self.wordmark = mark
    local tagline = W.Label(side, "что сделать дальше", W.FONT_CAPTION,
        T.muted[1], T.muted[2], T.muted[3])
    tagline:SetPoint("TOPLEFT", side, "TOPLEFT", 18, -42)
    self.tagline = tagline

    -- Фильтр: тот же список, суженный. Число справа - сколько советов внутри;
    -- пустой фильтр виден сразу, ещё до щелчка.
    self.filterChips = {}
    local y = Tab.SIDE_TOP
    for _, key in ipairs(ns.CHIP_ORDER) do
        local row = W.NavRow(side, ns.CHIP_LABEL[key], function()
            ns.Config:SetChip(key)
            Tab:SyncChips()
            -- Другой фильтр - другой список: он показывается с начала.
            if Tab.scroll then Tab.scroll:SetVerticalScroll(0) end
            Tab:Render()
        end, Tab.NAV_H, Tab.CHIP_ICON[key])
        row:SetWidth(Tab.SIDE_W - 1)
        row:SetPoint("TOPLEFT", side, "TOPLEFT", 0, -y)
        y = y + Tab.NAV_H
        self.filterChips[key] = row
    end
    Tab.SIDE_USED = y

    -- СРЕДНЯЯ КОЛОНКА: шапка, вкладки профиля и список -----------------------
    local mainCol = CreateFrame("Frame", nil, frame)
    mainCol:SetPoint("TOPLEFT", frame, "TOPLEFT", Tab.SIDE_W, 0)
    mainCol:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -Tab.DETAIL_W, 0)
    self.mainCol = mainCol

    local band = W.Band(mainCol, Tab.BAND_H)
    band:SetPoint("TOPLEFT", mainCol, "TOPLEFT", 0, 0)
    band:SetPoint("TOPRIGHT", mainCol, "TOPRIGHT", 0, 0)
    self.band = band

    self.heading = W.Label(band, "", W.FONT_HERO, T.text[1], T.text[2], T.text[3])
    self.heading:SetPoint("TOPLEFT", band, "TOPLEFT", 24, -16)

    -- Под названием - одна короткая строка: сколько советов и во что обойдутся
    -- материалы на них.
    self.summary = W.Label(band, "", W.FONT_SMALL, T.dim[1], T.dim[2], T.dim[3])
    self.summary:SetPoint("TOPLEFT", band, "TOPLEFT", 24, -48)
    self.summary:SetJustifyH("LEFT")
    self.summary:SetWordWrap(false)

    local summaryHit = CreateFrame("Frame", nil, band)
    summaryHit:SetPoint("TOPLEFT", self.summary, "TOPLEFT", -4, 4)
    summaryHit:SetPoint("BOTTOMRIGHT", self.summary, "BOTTOMRIGHT", 4, -4)
    summaryHit:EnableMouse(true)
    summaryHit:SetScript("OnEnter", function(self2)
        local lines = Tab.summaryTip
        if lines and #lines > 0 then
            W.ShowTip(self2, "Почему советов столько", lines)
        end
    end)
    summaryHit:SetScript("OnLeave", W.HideTip)
    self.summaryHit = summaryHit

    -- ПРОФИЛЬ - ВКЛАДКАМИ НАД СПИСКОМ. Он отвечает на вопрос «в каком порядке»,
    -- а не «что показывать», поэтому стоит отдельно от фильтра. Подпись слева
    -- говорит, что это за выбор; под выбранным - золотая черта.
    local tabsTop = Tab.BAND_H - Tab.TABS_H
    local profileLabel = W.Label(band, Tab.PROFILE_PREFIX, W.FONT_CAPTION,
        T.muted[1], T.muted[2], T.muted[3])
    profileLabel:SetPoint("TOPLEFT", band, "TOPLEFT", 24, -(tabsTop + 8))
    self.profileLabel = profileLabel
    self.profileChips = {}
    for _, key in ipairs(ns.PROFILE_ORDER) do
        local tab = W.Tab(band, ns.PROFILE_LABEL[key], function()
            ns.Config:SetProfile(key)
            Tab:SyncProfiles()
            -- Жест игрока в самом окне: не откладывается ни на бегу, ни по
            -- «недавно считали» (Main:ShouldDefer, причина opened).
            ns.MainFrame:Rebuild(false, { opened = true })
        end)
        tab:SetHeight(Tab.TABS_H)
        tab.tooltipTitle = ns.PROFILE_LABEL[key]
        tab.tooltipText = ns.PROFILE_TIP[key]
        self.profileChips[key] = tab
    end
    self:LayoutProfiles(Tab.Columns(ns.MainFrame:HostNow()).main)

    -- Скрытые советы возвращаются одной кнопкой - и она есть только тогда,
    -- когда есть что возвращать.
    local hidden = W.Button(band, Tab.RESTORE_LABEL, 138, 22, function()
        Card.RestoreHidden()
    end)
    hidden:SetIcon("undo", 12)
    hidden:SetPoint("TOPRIGHT", band, "TOPRIGHT", -14, -18)
    hidden:SetScript("OnEnter", function(self2)
        self2:Repaint(true)
        W.ShowTip(self2, Tab.RESTORE_LABEL, { Tab.hiddenTip or "" })
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
    self.empty:SetPoint("TOPLEFT", scroll, "TOPLEFT", 4, -8)
    self.empty:Hide()

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

-- ВКЛАДКИ ПРОФИЛЯ ВСТАЮТ ПО ИЗМЕРЕННОЙ ШИРИНЕ. В узком окне четыре вкладки с
-- подписью «Что важнее:» шире своей колонки, и последняя вылезала на карточку
-- совета (найдено на отрисовке самого маленького окна, 2026-11-21). Порядок
-- уступок: сначала уходит подпись, потом сжимаются поля вокруг слов.
Tab.TAB_PAD = 22             -- поля вкладки: слово плюс это
Tab.TAB_PAD_MIN = 8
function Tab:LayoutProfiles(mainWidth)
    if not self.profileChips then return end
    local left, right = 24, 12
    local room = (tonumber(mainWidth) or 0) - left - right
    local tabsTop = Tab.BAND_H - Tab.TABS_H
    local words, sum = {}, 0
    for _, key in ipairs(ns.PROFILE_ORDER) do
        local w = tonumber(self.profileChips[key].text:GetStringWidth()) or 40
        words[key] = w
        sum = sum + w
    end
    local n = #ns.PROFILE_ORDER
    local labelW = (tonumber(self.profileLabel:GetStringWidth()) or 70) + 6
    local pad = Tab.TAB_PAD
    local showLabel = (labelW + sum + n * pad) <= room
    if not showLabel and (sum + n * pad) > room then
        pad = math.max(Tab.TAB_PAD_MIN, math.floor((room - sum) / n))
    end
    if showLabel then self.profileLabel:Show() else self.profileLabel:Hide() end
    -- Без подписи первая вкладка встаёт так, чтобы её слово стояло на той же
    -- вертикали, что и заголовок.
    local x = showLabel and (left + labelW) or (left - math.floor(pad / 2))
    for _, key in ipairs(ns.PROFILE_ORDER) do
        local tab = self.profileChips[key]
        tab:SetWidth(words[key] + pad)
        tab:ClearAllPoints()
        tab:SetPoint("TOPLEFT", self.band, "TOPLEFT", x, -tabsTop)
        x = x + words[key] + pad
    end
    Tab.TABS_RIGHT = x
end

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
    sec.text = W.Label(sec, "", W.FONT_CAPTION, T.muted[1], T.muted[2], T.muted[3])
    sec.text:SetPoint("BOTTOMLEFT", sec, "BOTTOMLEFT", 6, 7)
    sec.text:SetJustifyH("LEFT")
    sec.text:SetWordWrap(false)
    sec.count = W.Label(sec, "", W.FONT_CAPTION, T.muted[1], T.muted[2], T.muted[3])
    sec.count:SetPoint("BOTTOMRIGHT", sec, "BOTTOMRIGHT", -8, 7)
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
    local chip = ns.Config:Chip()
    local cards = ns.ActionEngine:Filtered(chip)
    local meta = ns.ActionEngine.meta or {}
    local total = #(ns.ActionEngine.cards or {})

    -- Счётчики фильтра и название выбранного - в шапке.
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
    self.band:SetStarWidth(cols.main)
    self:LayoutProfiles(cols.main)
    local y = 0
    local shown = 0

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
        y = y + Tab.SECTION_H + 2
        for _, card in ipairs(group) do
            shown = shown + 1
            local row = Card.Acquire(self.content, shown)
            row:SetWidth(width)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -y)
            Card.Fill(row, card, card == chosen)
            y = y + Card.HEIGHT
        end
        y = y + 10
    end
    Card.ReleaseFrom(shown + 1)
    for i = sections + 1, #self.sections do self.sections[i]:Hide() end

    self.content:SetSize(width, math.max(1, y))
    self.scroll:Refresh()

    if shown == 0 then
        local title, body = self:EmptyReason(meta, chip, total)
        self.empty:Fill(title, body, width - 8)
        self.empty:Show()
    else
        self.empty:Hide()
    end

    -- Что скрыто руками - возвращается кнопкой в шапке.
    local hiddenCount = tonumber(meta.hiddenByDismissal) or 0
    if hiddenCount > 0 then self.hiddenButton:Show() else self.hiddenButton:Hide() end
    self.hiddenTip = "Скрыто советов: " .. hiddenCount
        .. ". Вы прятали их правым щелчком; эта кнопка возвращает все сразу."

    -- Строка под названием: сколько советов, сколько не показано и во что
    -- обойдутся материалы.
    local room = cols.main - 48 - ((hiddenCount > 0) and 150 or 0)
    W.SetFittedFrom(self.summary, self:SummaryVariants(meta, chip, #cards, total),
        math.max(100, room))
    -- Почему советов столько - под курсором у этой строки: что не показано
    -- (Tab:Notices) и какие виды советов сейчас молчат и почему (BranchGaps).
    local tip = self:Notices(meta, chip, #cards, total, {})
    for _, line in ipairs(self:BranchGaps(meta)) do tip[#tip + 1] = line end
    self.summaryTip = tip

    -- Карточка справа - последней: она читает то же, что только что нарисовано.
    if chosen then
        Detail:Show(chosen)
    else
        Detail:Show(nil, (total > 0) and Detail.NO_CARDS_BODY or nil)
    end
end

-- СКОЛЬКО СОВЕТОВ УБРАЛИ ПРАВИЛА: порог мелкой выгоды, профиль, длина списка.
-- Фильтр сюда не входит (он виден слева, со счётчиками), скрытое руками - тоже
-- (для него в шапке кнопка «Вернуть скрытые»).
function Tab:HiddenByRules(meta, total)
    meta = meta or {}
    total = tonumber(total) or 0
    local n = (tonumber(meta.moneyFloorDropped) or 0) + (tonumber(meta.profileDropped) or 0)
    local generated = tonumber(meta.generated) or 0
    if total > 0 and generated > total then n = n + (generated - total) end
    return n
end

-- СТРОКА ПОД НАЗВАНИЕМ, ОТ ПОЛНОЙ К КОРОТКОЙ.
--
-- Над списком когда-то стояла простыня про порог, профиль и длину списка,
-- потом - одна строка с причинами. Игрок назвал лишним и это (2026-11-21).
-- Теперь здесь факт и число: сколько советов показано и сколько нет. Почему -
-- под курсором у этой же строки (Tab:Notices). Число не показанных не
-- выбрасывается ни в одном варианте: сокращается только сумма за материалы.
--   shown - сколько советов в списке под текущим фильтром
--   total - сколько их без фильтра
function Tab:SummaryVariants(meta, chip, shown, total)
    meta = meta or {}
    shown, total = tonumber(shown) or 0, tonumber(total) or 0
    local head
    if chip and chip ~= ns.CHIP.ALL and shown < total then
        -- Слово стоит после «из N», то есть в родительном падеже.
        head = shown .. " из " .. total .. " " .. U.plural(total, "совета", "советов", "советов")
    else
        head = shown .. " " .. U.plural(shown, "совет", "совета", "советов")
    end
    local hidden = self:HiddenByRules(meta, total)
    if hidden > 0 then head = head .. "  ·  ещё " .. hidden .. " не показано" end
    local out = {}
    if meta.shoppingLines and meta.shoppingLines > 0 and meta.shoppingTotal then
        out[#out + 1] = head .. "  ·  материалы по всем советам: "
            .. U.money(meta.shoppingTotal)
    end
    out[#out + 1] = head
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
-- Про скрытые игроком советы здесь НЕ говорится: для них в шапке есть кнопка
-- «Вернуть скрытые», а когда скрыто всё - об этом отдельная карточка.
--
-- НА ЭКРАНЕ ЭТИХ СТРОК НЕТ, ПОКА О НИХ НЕ СПРОСИЛИ. Раньше они стояли над
-- списком строкой и под списком абзацем; игрок назвал это лишним (2026-11-21).
-- Теперь это подсказка под курсором у строки «N советов» в шапке: кто хочет
-- знать, почему советов столько, наводит мышь; остальным ничего не мешает.
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
            .. " Откройте окно любой своей профессии один раз."
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
    lines[#lines + 1] = "Можно попробовать другой профиль — вкладки над списком."
    return "Пока советовать нечего", table.concat(lines, "\n")
end

function Tab:OnShow()
    Tab:SyncProfiles()
    Tab:SyncChips()
    Tab:Render()
end

return Tab
