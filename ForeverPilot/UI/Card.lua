-- ForeverPilot / UI/Card.lua
--
-- Строка списка советов. В ней ОДНА строка текста и НИ ОДНОЙ КНОПКИ: слева
-- иконка и что сделать, справа - что это даст.
--
-- ЩЕЛЧОК ПО СТРОКЕ ВЫБИРАЕТ СОВЕТ: справа от списка открывается его карточка
-- (UI/TabNow.lua, Detail) - там всё остальное и одна золотая кнопка. Так
-- устроено большое окно Polestar, и игрок попросил сделать так же: раньше в
-- каждой строке было три строки текста и кнопка, и было «непонятно, на какую
-- кнопку что, куда нажимать» (2026-11-21).
--
-- Строка стоит БЕЗ ПЕРЕНОСА, то есть всё, что не влезло по ширине, обрезал бы
-- клиент - по пикселям, посреди числа. Поэтому текст укорачиваем сами и по
-- измеренному месту (Card.RoomFor + W.SetFitted), а полный стоит в карточке
-- справа и в подсказке под курсором.
--
-- Cards are pooled and reused: the list is rebuilt often and creating frames
-- every time would churn.
local ADDON, ns = ...

local U = ns.Util
local W = ns.Widgets
local Card = {}
ns.Card = Card

Card.HEIGHT = 34

-- РАЗМЕТКА СТРОКИ, ЧИСЛАМИ В ОДНОМ МЕСТЕ.
--
-- Все отступы названы здесь и выведены одно из другого: когда они были вписаны
-- по месту, строки карточки налезали друг на друга на несколько пикселей, и ни
-- одна проверка этого не видела. Tests/test_nonsense.lua считает прямоугольники
-- по привязкам - так же, как их считает клиент, - и требует, чтобы они лежали
-- внутри строки и не пересекались.
Card.PAD = 12                -- отступ слева, он же у иконки
Card.ICON = 22               -- сторона иконки
Card.TEXT_LEFT = Card.PAD + Card.ICON + 10   -- где начинается текст
Card.LINE_H = 15             -- высота строки выгоды
Card.TITLE_H = 16            -- высота строки заголовка
Card.TITLE_TOP = (Card.HEIGHT - Card.TITLE_H) / 2   -- заголовок по середине строки
Card.TEXT_RIGHT = 12         -- от правого края строки до текста
Card.GAP = 12                -- между заголовком и выгодой
-- ЗАГОЛОВОК ВАЖНЕЕ ВЫГОДЫ. Когда вместе они не помещаются, выгоде остаётся
-- эта доля строки - и всё, что не занял заголовок. Не поместилась и так -
-- выгода, начатая с числа, укорачивается с хвоста («+8% ко всем …»), а
-- начатая со слов убирается из строки совсем: обрывок «… 3 предмета лагеря»
-- ничего не сообщает, а полная выгода стоит в карточке совета справа.
Card.BENEFIT_SHARE = 0.30

-- В СПИСКЕ ЗАГОЛОВОК СТОИТ БЕЗ СЛОВА, КОТОРОЕ УЖЕ СКАЗАНО ЗАГОЛОВКОМ РАЗДЕЛА.
-- Советы собраны по видам, и над каждой группой написано, что это за вид:
-- «Скрафтить и надеть», «Купить материалы». Повторять то же в каждой строке -
-- «Скрафтить: …», «Скрафтить: …» - значит отнимать место у названия вещи, и в
-- узкой колонке от него оставалось «Скрафтить: Зеленые …». Полный заголовок
-- стоит в карточке совета справа.
Card.LIST_PREFIX = {
    CRAFT_GEAR   = "Скрафтить: ",
    EQUIP        = "Надеть: ",
    CRAFT_PROFIT = "На продажу: ",
    CRAFT_SKILL  = "На навык: ",
    BUY          = "Купить: ",
    ARBITRAGE    = "Купить и перепродать: ",
    DISENCHANT   = "Распылить: ",
    RESELL       = "Перекупить: ",
    PATHS        = "Как получить: ",
    FAVOR        = "За Благосклонность: ",
}

function Card.ListTitle(card)
    local title = tostring(card and card.title or "")
    local prefix = card and Card.LIST_PREFIX[card.kind]
    if prefix and #title > #prefix and title:sub(1, #prefix) == prefix then
        return title:sub(#prefix + 1)
    end
    return title
end

Card.pool = {}

-- Место под текст в строке: от иконки до правого отступа.
function Card.TextArea(frame)
    return (tonumber(frame:GetWidth()) or 0) - Card.TEXT_LEFT - Card.TEXT_RIGHT
end

-- СКОЛЬКО МЕСТА У ЗАГОЛОВКА И У ВЫГОДЫ - ПО ТЕМ ЖЕ ЧИСЛАМ, ПО КОТОРЫМ СТОЯТ
-- ПРИВЯЗКИ.
--
-- Строка без переноса, и то, что не влезло, обрезает клиент посреди числа.
-- Чтобы этого не было, ширину надо ЗНАТЬ, а не угадывать. Выгода получает свою
-- долю и то, что заголовку не нужно (frame.benefitRoom считает Card.Fill, когда
-- меряет заголовок); заголовок - то, что осталось слева от нарисованной выгоды.
-- Кто меняет разметку, меняет и это - иначе проверка в Tests/test_nonsense.lua
-- поймает расхождение.
function Card.RoomFor(frame, card)
    local area = Card.TextArea(frame)
    local out = {}
    out.benefit = frame.benefitRoom or math.floor(area * Card.BENEFIT_SHARE)
    local drawn = tonumber(frame.benefit:GetStringWidth()) or 0
    -- Выгоды в строке нет - заголовку вся строка.
    out.title = (drawn > 0) and (area - drawn - Card.GAP) or area
    return out
end

-- КАРТОЧКА СОВЕТА: ЧТО ИЗ НЕГО ПОКАЗАТЬ И В КАКОМ ВИДЕ -------------------------
--
-- Игрок сказал прямо, что ему нужно (2026-11-21): «Мне не нужно знать, откуда
-- ты брал эти данные. Мне нужно знать, что за данные, где купить что-то, где
-- что-то продать». Поэтому карточка справа от списка собирается не из длинного
-- текста совета, а из его чисел:
--
--   lead   - одна-две фразы: в чём совет (текст движка без оговорок, U.essence);
--   rows   - строки «подпись - значение»: что даёт, что теряете, цена, где;
--   blocks - что купить и где: по строке на предмет, цена справа, предметы
--            собраны по месту покупки («На аукционе», «У торговца»);
--   need   - что ещё надо сделать или чего не хватает.
--
-- ВСЕ ЧИСЛА - ИЗ ТЕХ ЖЕ ПОЛЕЙ СОВЕТА, ИЗ КОТОРЫХ ДВИЖОК СОБРАЛ СВОЙ ТЕКСТ.
-- Здесь ничего не пересчитывается и не додумывается: нет поля - нет строки.
-- У видов совета, для которых полей нет, карточка показывает текст движка.
Card.SHOP_CAPTION = {
    auctionator = "Купить на аукционе",
    vendor = "Купить у торговца",
}
Card.SHOP_CAPTION_OTHER = "Купить"
Card.SHOP_ORDER = { "vendor", "auctionator" }
Card.RISK_WORD = { HIGH = "высокий" }

local function itemName(itemID)
    return (ns.ActionEngine and ns.ActionEngine.nameOf and ns.ActionEngine.nameOf(itemID))
        or U.itemFallbackName(itemID)
end

local function moneyOr(copper)
    if tonumber(copper) then return U.money(copper) end
    return U.void(ns.VOID.NO_PRICE)
end

-- Что купить по плану - блоками по месту покупки.
function Card.ShopBlocks(plan)
    local out = {}
    if type(plan) ~= "table" or plan.ready then return out end
    local bySrc, other = {}, {}
    for _, line in ipairs(plan.shopping or {}) do
        local entry = {
            variants = Card.NameQty(itemName(line.itemID), line.qty),
            right = moneyOr(line.subtotal or (line.unit and line.unit * (line.qty or 1))),
        }
        if Card.SHOP_CAPTION[line.src] then
            bySrc[line.src] = bySrc[line.src] or {}
            table.insert(bySrc[line.src], entry)
        else
            other[#other + 1] = entry
        end
    end
    for _, src in ipairs(Card.SHOP_ORDER) do
        if bySrc[src] then
            out[#out + 1] = { caption = Card.SHOP_CAPTION[src], lines = bySrc[src] }
        end
    end
    if #other > 0 then
        out[#out + 1] = { caption = Card.SHOP_CAPTION_OTHER, lines = other }
    end
    return out
end

-- Где это: зона и координаты, без имени (имя стоит в соседней строке).
local function whereText(place)
    if type(place) ~= "table" then return nil end
    local bits = {}
    if place.zone then bits[#bits + 1] = tostring(place.zone) end
    if place.x and place.y then
        bits[#bits + 1] = string.format("%.1f %.1f", place.x * 100, place.y * 100)
    end
    if #bits == 0 then return nil end
    return table.concat(bits, ", ")
end

-- СОМНЕНИЕ В ЧИСЛАХ СОВЕТА - ОТДЕЛЬНО И ПЕРВЫМ.
--
-- Когда числа совета не сходятся или держатся на одной странной цене, движок
-- ставит предупреждение первой фразой текста «почему» (Logic/Risk.lua,
-- RenderDoubts) и помнит текст без него (card.whyBase). Карточка берёт
-- предупреждение целиком - оно про деньги игрока, - а остальное сокращает.
function Card.DoubtText(card)
    if type(card) ~= "table" or type(card.doubts) ~= "table" or #card.doubts == 0 then
        return ""
    end
    local why, base = tostring(card.why or ""), tostring(card.whyBase or "")
    if base == "" then return U.dropProvenance(why) end
    if #why > #base and why:sub(-#base) == base then
        return U.dropProvenance((why:sub(1, #why - #base):gsub("%s+$", "")))
    end
    return ""
end

-- Название с количеством, от полного к короткому: уходят слова с конца
-- названия, количество остаётся. «Рулон магической ткани x12» ->
-- «Рулон магической … x12» -> «Рулон … x12».
function Card.NameQty(name, qty)
    name = tostring(name or "?")
    local tail = " x" .. tostring(qty or 1)
    local out = { name .. tail }
    local words = {}
    for word in name:gmatch("%S+") do words[#words + 1] = word end
    for k = #words - 1, 1, -1 do
        out[#out + 1] = table.concat(words, " ", 1, k) .. " " .. U.MORE_MARK .. tail
    end
    return out
end

local SHEET = {}

-- Вещь, которую делают, чтобы надеть: что прибавится, что убавится, во что
-- обойдутся материалы.
SHEET[ns.KIND.CRAFT_GEAR] = function(card, sheet)
    local cmp = card.compareDetail
    if type(cmp) == "table" then
        if type(cmp.gainText) == "string" and cmp.gainText ~= "" then
            sheet.rows[#sheet.rows + 1] = { label = "Даёт", value = cmp.gainText }
        end
        if type(cmp.lossText) == "string" and cmp.lossText ~= "" then
            sheet.rows[#sheet.rows + 1] = { label = "Теряете", value = cmp.lossText, tone = "warn" }
        end
    end
    sheet.leadLimit = 1
end

-- Вещь на продажу: где и за сколько уйдёт, и ниже какой цены не выставлять.
SHEET[ns.KIND.CRAFT_PROFIT] = function(card, sheet)
    if tonumber(card.revenue) then
        local origin = card.revOrigin
        if type(origin) ~= "table" then
            origin = type(card.batch) == "table" and card.batch.origin or nil
        end
        local where
        if type(origin) == "table" then
            if origin.src == "vendor" then
                where = "торговцу"
            elseif origin.cutApplied or origin.market then
                where = "на аукционе"
            end
        end
        sheet.rows[#sheet.rows + 1] = { label = "Продать",
            value = (where and (where .. " — ") or "")
                .. U.money(card.revenue) .. " за штуку" }
    end
    local be = card.breakeven
    if type(be) == "table" and tonumber(be.listPrice) then
        sheet.rows[#sheet.rows + 1] = { label = "Не дешевле",
            value = U.money(be.listPrice) .. " — иначе в минус" }
    end
    sheet.leadLimit = (#sheet.rows > 0) and 0 or 2
end

-- Купить у торговца и продать на аукционе: у кого, где он стоит, за сколько.
SHEET[ns.KIND.ARBITRAGE] = function(card, sheet)
    local arb = card.arbitrage
    if type(arb) ~= "table" then return end
    local who = (type(arb.npcName) == "string" and arb.npcName ~= "") and arb.npcName or nil
    sheet.rows[#sheet.rows + 1] = { label = "Купить",
        value = (who and ("у торговца " .. who) or "у торговца")
            .. (tonumber(arb.ask) and (" — " .. U.money(arb.ask)) or "") }
    local where = whereText(card.place or arb.place)
    if where then sheet.rows[#sheet.rows + 1] = { label = "Где", value = where } end
    if tonumber(card.revenue) then
        sheet.rows[#sheet.rows + 1] = { label = "Продать",
            value = "на аукционе — " .. U.money(card.revenue) }
    end
    sheet.leadLimit = 0
    -- Кто и где - уже в строках; фраза «Торговец: имя, зона, координаты» под
    -- ними была бы повтором.
    sheet.dropNeed = (who ~= nil and where ~= nil)
    sheet.hideNeed = (who ~= nil)
end

-- Материал под другие советы: почём, где и для чего.
SHEET[ns.KIND.BUY] = function(card, sheet)
    local price = card.matPrice
    if type(price) == "table" and tonumber(price.unit) then
        sheet.rows[#sheet.rows + 1] = { label = "Цена",
            value = U.money(price.unit) .. " за штуку" }
        local where = (price.src == "vendor") and "у торговца"
            or ((price.src == "auctionator") and "на аукционе" or nil)
        local place = type(card.place) == "table" and ns.Places:Describe(card.place) or nil
        if where and place then where = where .. ": " .. place end
        if where then sheet.rows[#sheet.rows + 1] = { label = "Где", value = where } end
    end
    if type(card.buyFor) == "table" then
        -- Названия вещей, без слова «Скрафтить:» или «На продажу:» впереди: в
        -- узкой колонке оно занимало строку на каждую вещь.
        local titles = {}
        for _, title in pairs(card.buyFor) do
            title = tostring(title)
            for _, prefix in pairs(Card.LIST_PREFIX) do
                if #title > #prefix and title:sub(1, #prefix) == prefix then
                    title = title:sub(#prefix + 1)
                    break
                end
            end
            titles[#titles + 1] = title
        end
        table.sort(titles)
        if #titles > 0 then
            local shown = {}
            for i = 1, math.min(3, #titles) do shown[i] = titles[i] end
            local value = table.concat(shown, "\n")
            if #titles > 3 then
                value = value .. "\n" .. "и ещё " .. (#titles - 3)
            end
            sheet.rows[#sheet.rows + 1] = { label = "Для чего", value = value }
        end
    end
    sheet.leadLimit = (#sheet.rows >= 2) and 0 or 2
end

-- Развилка: одна вещь, несколько способов её получить.
SHEET[ns.KIND.PATHS] = function(card, sheet)
    local fork = card.paths
    if type(fork) ~= "table" then return end
    if fork.slotLabel then
        sheet.rows[#sheet.rows + 1] = { label = "Слот", value = tostring(fork.slotLabel) }
    end
    if type(fork.baseline) == "table" and fork.baseline.label then
        sheet.rows[#sheet.rows + 1] = { label = "Вместо", value = tostring(fork.baseline.label) }
    end
    local opt = type(fork.options) == "table" and fork.options[1] or nil
    if type(opt) == "table" and type(opt.paths) == "table" and #opt.paths > 0 then
        local lines = {}
        for _, path in ipairs(opt.paths) do
            local right
            if path.cost == 0 then
                right = "бесплатно"
            else
                right = moneyOr(path.cost)
            end
            local label = U.capitalize(tostring(path.label or "?"))
            local variants = { label }
            if path.when then
                table.insert(variants, 1, label .. " · " .. tostring(path.when))
            end
            lines[#lines + 1] = { variants = variants, right = right }
        end
        sheet.blocks[#sheet.blocks + 1] = { caption = "Как получить", lines = lines }
        local choice = ns.UpgradePaths and ns.UpgradePaths:ChoiceText(opt)
        if choice then
            sheet.lead = U.essence(choice, 1)
            sheet.leadLimit = nil
        end
    end
    sheet.hideNeed = true
end

-- Справка про цену: сколько сейчас и сколько обычно.
SHEET[ns.KIND.PRICE_INFO] = function(card, sheet)
    local v = card.priceVerdict
    if type(v) ~= "table" then return end
    if tonumber(v.live) then
        sheet.rows[#sheet.rows + 1] = { label = "Сейчас", value = U.money(v.live) }
    end
    if tonumber(v.median) then
        sheet.rows[#sheet.rows + 1] = { label = "Обычно", value = U.money(v.median) }
    end
    sheet.leadLimit = (#sheet.rows == 2) and 0 or 2
end

-- Состояние чар: сколько слотов зачаровано и какие пустые.
SHEET[ns.KIND.ENCHANT] = function(card, sheet)
    local st = card.enchantStatus
    if type(st) ~= "table" then return end
    if tonumber(st.enchanted) and tonumber(st.enchantable) then
        sheet.rows[#sheet.rows + 1] = { label = "Зачаровано",
            value = st.enchanted .. " из " .. st.enchantable }
    end
    if type(st.bareLabels) == "table" and #st.bareLabels > 0 then
        sheet.rows[#sheet.rows + 1] = { label = "Без чар",
            value = table.concat(st.bareLabels, ", ") }
    end
    sheet.leadLimit = (#sheet.rows == 2) and 0 or 2
end

function Card.Sheet(card)
    local sheet = { rows = {}, blocks = {}, warn = "", lead = "", need = "", leadLimit = 2 }
    if type(card) ~= "table" then return sheet end

    local build = SHEET[card.kind]
    if build then build(card, sheet) end

    -- У совета с планом крафта - цена материалов и что докупить.
    local plan = card.plan
    local planCovers = false
    if type(plan) == "table" then
        if plan.ready then
            planCovers = not (plan.needsTrip or plan.cooldown)
        else
            if tonumber(plan.cost) and plan.cost > 0 then
                sheet.rows[#sheet.rows + 1] = { label = "Материалы", value = U.money(plan.cost) }
            elseif tonumber(plan.costPartial) and plan.costPartial > 0 then
                sheet.rows[#sheet.rows + 1] = { label = "Материалы",
                    value = "от " .. U.money(plan.costPartial) }
            end
            for _, block in ipairs(Card.ShopBlocks(plan)) do
                sheet.blocks[#sheet.blocks + 1] = block
                planCovers = true
            end
        end
    end

    -- Второй вариант с той же вещью: надеть или продать.
    if type(card.alsoSell) == "table" and card.alsoSell.benefit then
        sheet.rows[#sheet.rows + 1] = { label = "Или продать",
            value = "прибыль " .. tostring(card.alsoSell.benefit) }
    end

    -- Высокий риск называется строкой: это про деньги игрока.
    local risk = card.risk
    if type(risk) == "table" and Card.RISK_WORD[risk.level]
        and (card.benefitKind == "gold" or card.benefitKind == "spend") then
        local value = Card.RISK_WORD[risk.level]
        if tonumber(risk.maxLoss) and risk.maxLoss > 0 then
            value = value .. " — потерять можно до " .. U.money(risk.maxLoss)
        end
        sheet.rows[#sheet.rows + 1] = { label = "Риск", value = value, tone = "warn" }
    end

    -- Текст: сначала сомнение (если есть), потом суть совета без оговорок.
    -- При leadLimit = 0 от текста остаются только настоящие предупреждения
    -- (U.essence их не выбрасывает): всё остальное уже сказано строками.
    sheet.warn = Card.DoubtText(card)
    local why = card.whyBase
    if type(why) ~= "string" or sheet.warn == "" then why = card.why end
    if sheet.leadLimit then
        sheet.lead = U.essence(why, sheet.leadLimit)
        -- Строк не вышло вовсе - текст совета идёт как есть, двумя фразами.
        if sheet.lead == "" and #sheet.rows == 0 and #sheet.blocks == 0 then
            sheet.lead = U.essence(why, 2)
        end
    end
    -- Что ещё сделать. Когда это уже сказано строками или блоком покупок, от
    -- текста остаются только настоящие предупреждения и координаты (их
    -- U.essence не выбрасывает ни при каком сокращении).
    if sheet.dropNeed then
        sheet.need = ""
    elseif sheet.hideNeed or planCovers then
        sheet.need = U.essence(card.need, 0)
    else
        sheet.need = U.essence(card.need, 2)
    end
    return sheet
end

-- Подсказка строки списка: только то, что в строке не поместилось.
--
-- Раньше под курсором стоял весь совет ещё раз - почему, чего не хватает,
-- материалы, достоверность, место в списке. Всё это теперь в карточке справа,
-- а подсказка предмета показывает сам предмет, как в игре.
--   cut - что в строке было укорочено (frame.cut)
function Card.TipLines(card, cut)
    local extra = {}
    if not card then return extra end
    cut = cut or {}
    if cut.title and card.title then extra[#extra + 1] = card.title end
    if cut.benefit and card.benefit then extra[#extra + 1] = card.benefit end
    return extra
end

local function onCardEnter(self)
    self.hover:Show()
    local card = self.card
    if not card then return end
    local extra = Card.TipLines(card, self.cut)
    if card.link then
        W.ShowItemTip(self, card.link, extra)
    elseif #extra > 0 then
        W.ShowTip(self, extra[1], { extra[2] })
    end
end

local function onCardLeave(self)
    self.hover:Hide()
    W.HideTip()
end

function Card.Acquire(parent, index)
    local frame = Card.pool[index]
    if frame then
        frame:SetParent(parent)
        frame:Show()
        return frame
    end

    local T = W.THEME
    frame = CreateFrame("Button", nil, parent)
    frame:SetHeight(Card.HEIGHT)

    -- Фон: строка лежит прямо на списке, без коробки. Заливка появляется
    -- только у выбранной строки и у закреплённого сверху совета.
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(frame)
    bg:SetColorTexture(1, 1, 1, 0)
    frame.fpBG = bg

    local hover = frame:CreateTexture(nil, "BORDER")
    hover:SetAllPoints(frame)
    W.Paint(hover, T.hover)
    hover:Hide()
    frame.hover = hover

    -- Цвет вида совета - узкой полоской слева.
    local spine = frame:CreateTexture(nil, "ARTWORK")
    spine:SetPoint("TOPLEFT", 0, -5)
    spine:SetPoint("BOTTOMLEFT", 0, 5)
    spine:SetWidth(2)
    frame.spine = spine

    -- У выбранной строки вместо неё - золотая полоска во всю высоту.
    local bar = frame:CreateTexture(nil, "ARTWORK")
    bar:SetPoint("TOPLEFT", 0, 0)
    bar:SetPoint("BOTTOMLEFT", 0, 0)
    bar:SetWidth(3)
    W.Paint(bar, T.accent, 1)
    bar:Hide()
    frame.bar = bar

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(Card.ICON, Card.ICON)
    icon:SetPoint("TOPLEFT", frame, "TOPLEFT", Card.PAD, -(Card.HEIGHT - Card.ICON) / 2)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    frame.icon = icon

    frame.benefit = W.Label(frame, "", W.FONT_SMALL)
    frame.benefit:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -Card.TEXT_RIGHT,
        -math.floor((Card.HEIGHT - Card.LINE_H) / 2))
    frame.benefit:SetJustifyH("RIGHT")
    frame.benefit:SetWordWrap(false)
    frame.benefit:SetHeight(Card.LINE_H)

    frame.title = W.Label(frame, "", W.FONT_NORMAL, T.text[1], T.text[2], T.text[3])
    frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", Card.TEXT_LEFT, -Card.TITLE_TOP)
    frame.title:SetPoint("RIGHT", frame.benefit, "LEFT", -Card.GAP, 0)
    frame.title:SetJustifyH("LEFT")
    frame.title:SetWordWrap(false)
    frame.title:SetHeight(Card.TITLE_H)

    frame:SetScript("OnEnter", onCardEnter)
    frame:SetScript("OnLeave", onCardLeave)
    frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    frame:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            Card.RequestDismiss(self.card)
        else
            -- ЛЕВЫЙ ЩЕЛЧОК ВЫБИРАЕТ, А НЕ ВЫПОЛНЯЕТ. Действие - на золотой
            -- кнопке в карточке справа: так по списку можно ходить, ничего
            -- не запуская, и всегда видно, что именно будет нажато.
            Card.Disarm()
            Card.Pick(self.card)
        end
    end)

    Card.pool[index] = frame
    return frame
end

local KIND_SPINE = {
    CRAFT_GEAR   = { 0.35, 0.60, 0.95 },
    CRAFT_MAT    = { 0.45, 0.55, 0.70 },
    CRAFT_SKILL  = { 0.45, 0.80, 0.45 },
    CRAFT_PROFIT = { 0.95, 0.80, 0.25 },
    ENCHANT      = { 0.70, 0.45, 0.95 },
    BUY          = { 0.90, 0.55, 0.35 },
    SELL_JUNK    = { 0.70, 0.70, 0.45 },
    SETUP        = { 1.00, 0.55, 0.15 },
}

-- Shared with the compact panel so both surfaces speak the same colour
-- language. An unknown kind gets a neutral grey rather than a nil error.
function Card.SpineColor(kind)
    return KIND_SPINE[kind] or { 0.4, 0.4, 0.4 }
end

-- КНОПКА, КОТОРУЮ НЕЛЬЗЯ НАЖАТЬ, НЕ РИСУЕТСЯ.
--
-- Сегодня такое действие одно - рецепт: открыть его в окне профессий аддону
-- запрещает сама игра (см. Logic/RecipeBook.lua и Core/Api.lua). Кнопка,
-- которая в ответ на нажатие объясняет, почему она не работает, - тот же
-- дефект, что текст про кнопку, которой нет. Поэтому её нет вовсе, а на
-- экране стоит то, что игроку и нужно: какую профессию открыть и что в ней
-- найти (в подсказке совета, над списком и в подсказке панели).
--
-- С 2026-11-21 У РЕЦЕПТА КНОПКА БЫВАЕТ, И У ЛЮБОГО СОВЕТА ОНА ЗАВИСИТ ОТ ТОГО,
-- ЧТО СЕЙЧАС ОТКРЫТО. Жалоба игрока: «я просто на это смотрю и должен ручками
-- вбивать название в профессии… или искать на аукционе кнопочку вставить».
-- Что нажимается на совете прямо сейчас, решает одна функция - Card.LiveAction,
-- - и по ней же ставится подпись, и по ней же идёт нажатие: иначе кнопка
-- подписана одним, а делает другое.
--   * открыт аукцион и совету есть что на нём искать (сам предмет или
--     материалы, которых не хватает) - «Искать на аукционе»;
--   * совет про рецепт и клиент умеет искать по имени в окне профессии -
--     «Показать в профессии» (окно при этом открывает игрок);
--   * иначе - своё действие совета, как раньше.
-- nil - нажимать нечего, и кнопки нет.
function Card.LiveAction(card)
    local act = card and card.action
    if not act or act.kind == "noop" then return nil end

    if ns.ShoppingList and ns.ShoppingList.CanSearchNow
        and (act.kind == "shop" or act.kind == "findRecipe")
        and ns.ShoppingList:CanSearchNow() then
        local items = ns.ShoppingList:CardAuctionItems(card)
        if #items > 0 then
            return { kind = "auction", label = ns.ShoppingList.HANDOFF_LABEL, items = items }
        end
    end

    if act.kind == "findRecipe" then
        local info = ns.RecipeBook:ShowState(act.recipeID)
        if info.state == "ready" then
            return { kind = "showRecipe", label = info.label, recipeID = act.recipeID,
                     shown = info.shown, armed = info.armed }
        end
        return nil
    end
    return { kind = act.kind, label = act.label or "Открыть" }
end

function Card.ActionReady(card)
    local act = card and card.action
    if not act then return true end
    return Card.LiveAction(card) ~= nil
end

-- Подпись кнопки - та, что сейчас нажимается.
function Card.ActionLabel(card)
    local live = Card.LiveAction(card)
    if live and live.label then return live.label end
    return (card and card.action and card.action.label) or "Открыть"
end

-- Подсказка кнопки: что она сделает и чего не сделает. nil - сказать нечего.
function Card.ActionTip(card)
    local live = Card.LiveAction(card)
    if not live then return nil end
    if live.kind == "auction" then
        return live.label, {
            "Открою вкладку покупок Auctionator и запущу в ней поиск: "
                .. #live.items .. " "
                .. U.plural(#live.items, "позиция", "позиции", "позиций") .. ".",
            "Ничего не покупаю — дальше действуете вы.",
        }
    end
    if live.kind == "showRecipe" then
        if live.shown then
            return live.label, { "Сниму поиск в окне профессии — вернётся весь список." }
        end
        return live.label, {
            "Профессия открыта — оставлю в её списке только этот рецепт.",
            "Закрыта — запомню: откройте её сами, и рецепт уже будет найден.",
            "Окон игры я не открываю и ничего не создаю.",
        }
    end
    return nil
end

-- Почему у совета нет кнопки. nil - кнопка есть или объяснять нечего.
-- ОБЩЕЕ ОБЪЯСНЕНИЕ, КОТОРОЕ СТОИТ НАД СПИСКОМ ОДИН РАЗ.
--
-- Tab:Notices сворачивает одинаковые строки, поэтому карточка может отдать
-- сюда ту часть объяснения, которая у всех таких советов одна: на экране она
-- окажется ровно одной строкой, сколько бы советов её ни отдали. Так убран
-- повтор у советов «Откройте окно профессии» - при двух профессиях их два, и
-- оба печатали один и тот же абзац (см. Engine.SETUP_NOTE_RECIPES).
function Card.ActionNote(card)
    if card and type(card.aboveList) == "string" and card.aboveList ~= "" then
        return card.aboveList
    end
    local act = card and card.action
    if act and act.kind == "findRecipe" then
        -- Кнопка есть (показ в профессии или поиск на аукционе) - объяснять
        -- её отсутствие незачем.
        if Card.LiveAction(card) then return nil end
        local info = ns.RecipeBook:ShowState(act.recipeID)
        if info.state ~= "ready" then return info.note end
    end
    return nil
end

-- ТО ЖЕ САМОЕ ОДНОЙ СТРОКОЙ - И РЯДОМ С ТЕМ, ЧЕГО НЕ ХВАТАЕТ.
--
-- Полное объяснение (выше) - четыре строки, и над списком оно висело постоянно,
-- на каждом заходе в окно. Вопрос «а где кнопка?» возникает у конкретного
-- совета, поэтому ответ стоит в подсказке этого совета, одной строкой. В
-- подсказке предмета длинной инструкции по-прежнему нет: она занимала там пять
-- строк поверх игровых данных, за которыми игрок на подсказку и наводит мышь
-- (правило держит Tests/test_nonsense.lua).
--
-- И СТРОКА ЭТА - ПРО ЭТОТ РЕЦЕПТ, А НЕ ПРО КНОПКУ. Раньше здесь стояло
-- объяснение, почему кнопки нет; объяснение само по себе игроку не помогает.
-- Теперь первым идёт то, что он спрашивал: какую профессию открыть и что в
-- ней найти (RecipeBook:FindText). Общая строка остаётся на случай, когда
-- рецепта в справочнике нет и назвать профессию нечем.
function Card.ActionNoteShort(card)
    local act = card and card.action
    if act and act.kind == "findRecipe" then
        if Card.LiveAction(card) then return nil end
        local info = ns.RecipeBook:ShowState(act.recipeID)
        if info.state ~= "ready" then
            return ns.RecipeBook:FindText(act.recipeID) or info.short
        end
    end
    return nil
end

-- ВЫГОДА В УЗКОЙ СТРОКЕ. Когда она начинается с числа («+8% ко всем
-- характеристикам», «1з 70с за штуку»), ценно начало, и уходят слова с конца:
-- «+8% ко всем …». Общий сокращатель (U.shortenings) бережёт ПОСЛЕДНЕЕ число
-- фразы и от такой строки оставлял «… +8% ко» - число цело, а смысла нет.
-- Числовая группа и здесь не режется: слова уходят целиком (U.atoms), и
-- предлог в конце не остаётся висеть.
function Card.FitBenefit(fs, text, room)
    text = tostring(text or "")
    room = tonumber(room) or 0
    local memo = fs.fpBenefit
    if memo and memo.text == text and memo.room == room then
        fs:SetText(memo.out)
        return memo.out, memo.cut
    end
    fs:SetText(text)
    local out, cut = text, false
    if room >= W.FIT_MIN and (tonumber(fs:GetStringWidth()) or 0) > room then
        local atoms = U.atoms(text)
        if atoms[1] and atoms[1].number and #atoms > 1 then
            local variants = { text }
            -- Не короче, чем число со своим словом: «+7 …» не говорит, чего семь.
            for k = #atoms - 1, 2, -1 do
                local last = atoms[k]
                if last.number or U.charLen(last.text) > 2 then
                    local parts = {}
                    for i = 1, k do parts[i] = atoms[i].text end
                    variants[#variants + 1] = table.concat(parts, " ") .. " " .. U.MORE_MARK
                end
            end
            out, cut = W.SetFittedFrom(fs, variants, room)
            -- Не поместился и самый короткий вариант - выгоды в строке нет.
            if (tonumber(fs:GetStringWidth()) or 0) > room then
                fs:SetText("")
                out, cut = "", true
            end
        else
            -- Начата со слов и не поместилась: в строке её нет вовсе.
            fs:SetText("")
            out, cut = "", true
        end
    end
    fs.fpBenefit = { text = text, room = room, out = out, cut = cut }
    return out, cut
end

-- Кто-то слушает выбор строки (список советов в UI/TabNow.lua).
Card.OnPick = nil

function Card.Pick(card)
    if not (card and Card.OnPick) then return end
    return ns.Diag:Guard("Card.Pick", Card.OnPick, card)
end

-- Выбранная строка: светлее и с золотой полоской слева.
function Card.SetSelected(frame, on)
    frame.selected = on and true or false
    local card = frame.card
    if frame.selected then
        W.Paint(frame.fpBG, W.THEME.selected)
        frame.bar:Show()
        frame.spine:Hide()
    else
        if card and card.pinTop then
            -- Закреплённый сверху совет (без него остальные неполны) - тёплым.
            frame.fpBG:SetColorTexture(0.89, 0.72, 0.38, 0.07)
        else
            frame.fpBG:SetColorTexture(1, 1, 1, 0)
        end
        frame.bar:Hide()
        frame.spine:Show()
    end
end

function Card.Fill(frame, card, selected)
    frame.card = card
    local T = W.THEME

    local spine = Card.SpineColor(card.kind)
    frame.spine:SetColorTexture(spine[1], spine[2], spine[3], 0.85)
    Card.SetSelected(frame, selected)

    frame.icon:SetTexture(card.icon or ns.KIND_ICON[card.kind] or "Interface\\Icons\\INV_Misc_QuestionMark")

    if card.pinTop then
        frame.title:SetTextColor(1, 0.86, 0.55)
    else
        frame.title:SetTextColor(T.text[1], T.text[2], T.text[3])
    end

    local bc = W.benefitColor(card.benefitKind)
    frame.benefit:SetTextColor(bc[1], bc[2], bc[3])

    -- ТЕКСТ СТАВИТСЯ ПОСЛЕДНИМ И ПО ИЗМЕРЕННОМУ МЕСТУ.
    --
    -- Сначала меряется заголовок целиком: выгоде достаётся её доля строки и
    -- всё, что заголовку не нужно. Потом заголовок получает то, что осталось
    -- слева от нарисованной выгоды. Что не влезло, укорачивается по смыслу и
    -- помечается «…» (W.SetFitted): посреди числа ничего не режется, а полный
    -- текст стоит в карточке справа и в подсказке.
    local area = Card.TextArea(frame)
    local title = Card.ListTitle(card)
    -- Ширина заголовка целиком запоминается: список перерисовывается часто, а
    -- совет в строке обычно тот же - мерить его шрифтом каждый раз незачем.
    local known = frame.fpTitleWidth
    local titleNeeds
    if known and known.text == title then
        titleNeeds = known.width
    else
        frame.title:SetText(title)
        titleNeeds = tonumber(frame.title:GetStringWidth()) or 0
        frame.fpTitleWidth = { text = title, width = titleNeeds }
    end
    frame.benefitRoom = math.max(math.floor(area * Card.BENEFIT_SHARE),
        area - titleNeeds - Card.GAP)
    local _, benefitCut = Card.FitBenefit(frame.benefit, card.benefit or "", frame.benefitRoom)
    local room = Card.RoomFor(frame, card)
    local _, titleCut = W.SetFitted(frame.title, title, room.title)
    -- В строке заголовок короче полного (без слова раздела или укорочен) -
    -- полный стоит под курсором.
    frame.cut = { title = titleCut or (title ~= tostring(card.title or "")),
                  benefit = benefitCut }
    return frame
end

-- Point the arrow at this card's place. This draws a direction and a distance
-- and nothing else: no movement, no travel, no clicking anything for the player.
function Card.Route(card)
    return ns.Diag:Guard("Card.Route", Card.RouteInner, card)
end

function Card.RouteInner(card)
    if not (card and card.place) then return end
    local ok, reason, provider = ns.Places:Route(card.place, card.title)
    if ok then
        if provider == "tomtom" then
            ns.Api:Print("точка передана TomTom: "
                .. (ns.Places:Describe(card.place) or "место"))
        else
            ns.Api:Print("веду к: " .. (ns.Places:Describe(card.place) or "место"))
        end
        return
    end
    if reason == "combat" then
        ns.Api:Print("в бою стрелку не ставлю")
    elseif reason == "no-coords" then
        ns.Api:Print("координат этого места я не записал")
    elseif reason == "disabled" then
        ns.Api:Print("навигация выключена в настройках")
    else
        ns.Api:Print("не удалось навести стрелку"
            .. (reason and (" (" .. tostring(reason) .. ")") or ""))
    end
end

-- Actions. Every one of these is either a UI navigation or writing to our own
-- saved list. Nothing buys, sells, or crafts: the player does that.
-- Guarded, because a click is exactly where a player hits a bug.
function Card.Activate(card)
    return ns.Diag:Guard("Card.Activate:" .. tostring(card and card.kind),
        Card.ActivateInner, card)
end

function Card.ActivateInner(card)
    if not card or not card.action then return end
    local act = card.action

    -- ЧТО НАЖАТО - РЕШАЕТ Card.LiveAction, ТА ЖЕ, ЧТО ПОДПИСАЛА КНОПКУ.
    local live = Card.LiveAction(card)

    if live and live.kind == "auction" then
        local _, message = ns.ShoppingList:SearchCard(card)
        if message then ns.Api:Print(message) end
        ns.MainFrame:Refresh()
        return
    end

    if act.kind == "findRecipe" then
        -- ОКНО ПРОФЕССИЙ ЗДЕСЬ НЕ ОТКРЫВАЕТСЯ. Открыть рецепт игра аддонам
        -- запрещает (Core/Api.lua). Если клиент умеет искать по имени, в окне,
        -- которое открыл игрок, остаётся один этот рецепт (RecipeBook:Show);
        -- если нет - одной строкой сказано, что открыть и что найти.
        if live and live.kind == "showRecipe" then
            local _, message = ns.RecipeBook:Show(act.recipeID)
            if message then ns.Api:Print(message) end
            ns.MainFrame:Refresh()
            return
        end
        ns.Api:Print(ns.RecipeBook:FindText(act.recipeID)
            or ns.RecipeBook:ShowState().note)
        return
    end

    if act.kind == "shop" and act.itemID then
        -- «ДОБАВИЛ» - ТОЛЬКО ЕСЛИ ДОБАВИЛ. Позиция, которую игрок уже закрепил
        -- в том же количестве, от нажатия не меняется, а кнопка всё равно
        -- отвечала «добавил в список покупок». И большее количество, закреплённое
        -- руками, нажатие молча уменьшало. Теперь ответ - что произошло на деле.
        local qty = act.qty or 1
        local had = tonumber(ns.Config:Shopping()[act.itemID]) or 0
        local name = ns.ActionEngine.nameOf(act.itemID)
        if had >= qty then
            ns.Api:Print("уже в вашем списке покупок: " .. name .. " x" .. had)
            return
        end
        ns.ShoppingList:Pin(act.itemID, qty)
        ns.Api:Print("добавил в список покупок: " .. name .. " x" .. qty)
        ns.MainFrame:Refresh()
        return
    end

    -- СНЯТЬ СВОЁ ЗАКРЕПЛЕНИЕ. Кнопка стоит на карточке своего списка - той, что
    -- раньше называлась «Купить: …» и первой же фразой сообщала, что ни одному
    -- совету это не нужно (см. Engine.AsOwnListCard). Там кнопка «В список
    -- покупок» отвечала «уже в вашем списке» и не делала ничего; эта делает
    -- ровно то, что на ней написано, и говорит, как вернуть.
    if act.kind == "unpin" and act.itemID then
        local had = tonumber(ns.Config:Shopping()[act.itemID]) or 0
        local name = ns.ActionEngine.nameOf(act.itemID)
        if had <= 0 then
            ns.Api:Print("в вашем списке покупок этого нет: " .. name)
            return
        end
        ns.ShoppingList:Unpin(act.itemID)
        ns.Api:Print("убрал из вашего списка покупок: " .. name .. " x" .. had
            .. ". Вернуть — кнопкой «В список покупок» на совете, которому"
            .. " это понадобится.")
        ns.MainFrame:Refresh()
        return
    end

    if act.kind == "openProfession" then
        ns.Api:Print("откройте окно профессии «" .. tostring(ns.Util.profLabel(act.profession))
            .. "» — я прочитаю рецепты сам")
        return
    end

    -- «ПОКАЗАТЬ ПРЕДМЕТ» ПОКАЗЫВАЕТ ПРЕДМЕТ.
    --
    -- Раньше здесь печаталось «… — наденьте сами: экипировкой я не управляю».
    -- Текст был написан под совет «надень своё», а действие showItem стоит на
    -- семи ветках - и всем семи отвечало про экипировку. Живая жалоба звучала
    -- так: игрок жал кнопку на карточке Благосклонности и получал десяток
    -- одинаковых строк про экипировку, хотя просил ПОКАЗАТЬ вещь.
    --
    -- Показать вещь - значит отдать её ССЫЛКУ: по ссылке в чате видно название,
    -- качество, и подсказка со всеми характеристиками по наведению мыши. Это
    -- единственный способ показать предмет, который у аддона есть: своего окна
    -- с характеристиками у него нет, а открывать чужие он не берётся.
    --
    -- Показать нечем - так и сказано, и ровно про это: не «наденьте сами», а
    -- «данных об этом предмете у меня нет».
    --
    -- И отдельно важное: неизвестное действие раньше проваливалось в конец
    -- этой функции и ТИХО убирало карточку на час. Для этого совета это
    -- означало бы «нажал кнопку - совет исчез», а именно так пользователь
    -- однажды уже потерял всю выдачу. Теперь в конце функции скрытия нет вовсе.
    if act.kind == "showItem" then
        local link = act.link or card.link
        if not link and act.itemID then
            local info = ns.Api:ItemInfo(act.itemID)
            link = info and info.link or nil
        end
        if link then
            ns.Api:Print(tostring(link))
            return
        end
        -- Ссылки нет. Называем предмет тем, что знаем, и говорим, ЧЕГО не
        -- хватает: это заказ на данные, а не отказ помочь.
        local name = (act.itemID and ns.ActionEngine.nameOf(act.itemID)) or nil
        ns.Api:Print((name and (tostring(name) .. " — ") or "")
            .. "показать нечем: данных об этом предмете клиент мне ещё не отдал."
            .. " Наведите мышь на название в окне — подсказка появится, когда"
            .. " данные дойдут.")
        if ns.Diag and act.itemID then
            ns.Diag:Want("itemsNotInDB", act.itemID, "show-item",
                { reason = "no-link" })
        end
        return
    end

    if act.kind == "undismiss" then
        Card.RestoreHidden()
        return
    end

    -- ЗДЕСЬ СТОЯЛО СКРЫТИЕ, И ОНО БЫЛО НЕВИДИМЫМ.
    --
    -- Всё, что не узнано выше, - информационный совет (noop) и любое действие,
    -- которого этот файл не знает, - проваливалось сюда и пряталось на час. В
    -- комментарии это называлось «игрок нажал „Понятно“», но нажимать было
    -- нечего: у информационного совета кнопка скрыта (см. Card.Fill), и сюда
    -- приводил ЛЮБОЙ левый щелчок по строке. Совет исчезал от щелчка, у
    -- которого не было даже подписи.
    --
    -- Теперь левый щелчок не прячет ничего и никогда. Спрятать совет в списке
    -- можно одним способом - двумя правыми щелчками (Card.RequestDismiss): про
    -- первый сказано в чате, второй подтверждает, и оба называют себя скрытием.
    -- Правило проверяется тестом на всех советах списка сразу.
end

-- ЗДЕСЬ БЫЛИ ВТОРЫЕ, МЁРТВЫЕ ОПРЕДЕЛЕНИЯ Card.UndoLastHidden и
-- Card.RestoreHidden. Они стояли ВЫШЕ рабочих и потому ничего не делали: Lua
-- просто перекрывал их теми, что ниже. Разница была не косметическая — мёртвая
-- версия печатала сообщения сама, а рабочая берёт их у ns.Dismissal, то есть
-- два набора формулировок на одно действие, и правка одного из них не меняла
-- ничего. Удалены; рабочие версии ниже, после блока про скрытие.

-- Hiding, and above all not hiding by accident. The DECISIONS live in
-- Logic/Dismissal.lua, where the test harness can reach them: this file only
-- prints what happened and redraws. The logic used to be here, which is why the
-- most destructive action in the addon was the one with no tests on it.

Card.CONFIRM_SECONDS = nil   -- see ns.Dismissal.CONFIRM_SECONDS

function Card.IsArmed(card)
    return ns.Dismissal:IsArmed(card and card.key)
end

function Card.Disarm()
    return ns.Dismissal:Disarm()
end

-- Two deliberate right-clicks. The first arms and says so; the second hides.
function Card.RequestDismiss(card, seconds)
    local outcome, message = ns.Dismissal:Request(card, seconds)
    if message then ns.Api:Print(message) end
    if outcome == "armed" or outcome == "hidden" then
        -- Redraw either way: an armed card shows it, a hidden one disappears.
        -- Cards rebuilt, character not rescanned.
        ns.MainFrame:RebuildCards()
    end
    return outcome == "armed" or outcome == "hidden", outcome
end

-- ЗДЕСЬ БЫЛА Card.Dismiss - СКРЫТИЕ В ОДИН ШАГ. ЕЁ БОЛЬШЕ НЕТ.
--
-- Она существовала «только для осознанного нажатия собственной кнопки
-- карточки», а звали её в итоге три места, и ни одно не было осознанным
-- нажатием: «Дальше» на панели, левый щелчок по информационному совету и
-- правый щелчок по панели. Каждое по очереди оставило игрока без советов.
-- Пока в интерфейсе есть функция, которая прячет совет с одного вызова, до неё
-- рано или поздно дотянется четвёртое место. Поэтому её нет: единственный путь
-- от щелчка к скрытию - Card.RequestDismiss выше, два щелчка с вопросом.
-- Перечень всех путей и проверка, что новых не появилось, - Tests/test_vanish.lua.

-- Undo exactly the last hide. One step, and every hide message names it.
function Card.UndoLastHidden()
    local entry, message = ns.Dismissal:UndoLast()
    if message then ns.Api:Print(message) end
    if entry then ns.MainFrame:RebuildCards() end
    return entry
end

-- Bring everything back. This is the way out of the state where a player has
-- hidden enough cards that the list is empty - see the "hidden:restore" card in
-- ActionEngine. A full rebuild, not a refresh: the cards have to be produced
-- again, not just redrawn.
function Card.RestoreHidden()
    local n, message = ns.Dismissal:RestoreAll()
    if message then ns.Api:Print(message) end
    ns.MainFrame:RebuildCards()
    return n
end

function Card.ReleaseFrom(index)
    for i = index, #Card.pool do
        local frame = Card.pool[i]
        if frame then frame:Hide(); frame.card = nil end
    end
end

return Card
