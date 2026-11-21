-- ForeverPilot / UI/Card.lua
--
-- One row of the ranked list, and it is exactly three lines:
--   1. what to do, with the payoff on the right
--   2. why
--   3. what is missing, and the button
--
-- Все три строки стоят БЕЗ ПЕРЕНОСА, то есть всё, что не влезло по ширине,
-- обрезал бы клиент - по пикселям, посреди числа. Поэтому текст укорачиваем
-- сами и по измеренному месту (Card.RoomFor + W.SetFitted), а полный остаётся
-- в подсказке под курсором.
--
-- Cards are pooled and reused: the list is rebuilt often and creating frames
-- every time would churn.
local ADDON, ns = ...

local U = ns.Util
local W = ns.Widgets
local Card = {}
ns.Card = Card

Card.HEIGHT = 74

-- РАЗМЕТКА ТРЁХ СТРОК, ЧИСЛАМИ В ОДНОМ МЕСТЕ -----------------------------
--
-- Игрок прислал скриншот, на котором вторая и третья строки карточки
-- НАРИСОВАНЫ ДРУГ ПОВЕРХ ДРУГА: получилась каша из «Цена «Ж…» и обрывка
-- другого текста. Это не шрифт и не чужой аддон - это была наша арифметика.
--
-- Строка «почему» висела на нижней границе строки заголовка (сверху вниз), а
-- строка «чего не хватает» - на нижней границе иконки (снизу вверх). Два
-- отсчёта от разных краёв: пока шрифт мелкий, между ними оставался зазор, а
-- при настоящих высотах шрифтов клиента (заголовок ~14, мелкий ~12) они
-- налезали друг на друга на несколько пикселей. Ни одна проверка этого не
-- видела, потому что проверять было нечего: числа стояли по месту, каждое в
-- своём SetPoint.
--
-- Теперь они здесь, и выведены одно из другого:
--   * третья строка стоит НА РЯДУ КНОПОК, по их середине, а не над ними;
--   * ряд кнопок стоит от нижнего края;
--   * первая и вторая строки идут сверху вниз цепочкой.
-- Между второй и третьей строками остаётся зазор, и он проверяется:
-- Tests/test_nonsense.lua считает прямоугольники всех трёх строк по их
-- привязкам - так же, как их считает клиент, - и требует, чтобы ни одна пара
-- не пересекалась.
Card.PAD = 11                -- отступ слева, он же у иконки
Card.ICON = 34               -- сторона иконки
Card.TEXT_LEFT = Card.PAD + Card.ICON + 10   -- где начинается текст
Card.LINE_H = 12             -- высота строки мелкого шрифта
Card.BUTTON_H = 20
Card.BUTTON_BOTTOM = 9       -- ряд кнопок от нижнего края карточки
-- Третья строка по середине ряда кнопок: так она читается как часть этого
-- ряда, а не как ещё одна строка текста, которой некуда встать.
Card.ROW3_BOTTOM = Card.BUTTON_BOTTOM + (Card.BUTTON_H - Card.LINE_H) / 2
Card.TEXT_RIGHT = 12        -- от правого края карточки до текста и до кнопок
Card.GAP = 8                -- между текстом и тем, что стоит справа от него

Card.pool = {}

-- СКОЛЬКО МЕСТА У КАЖДОЙ СТРОКИ - ПО ТЕМ ЖЕ ЧИСЛАМ, ПО КОТОРЫМ СТОЯТ ПРИВЯЗКИ.
--
-- Строки без переноса, и то, что не влезло, обрезает клиент посреди числа.
-- Чтобы этого не было, ширину надо ЗНАТЬ, а не угадывать: здесь она считается
-- из разметки выше и из того, что сейчас нарисовано справа (кнопка, путь,
-- значок достоверности, полоска готовности). Кто меняет разметку, меняет и
-- это - иначе проверка в Tests/test_nonsense.lua поймает расхождение.
function Card.RoomFor(frame, card, showAction, canRoute)
    local full = tonumber(frame:GetWidth()) or 0
    local left = Card.TEXT_LEFT
    local out = {}
    -- Первая строка: от текста до столбца выгоды.
    out.title = full - left - (tonumber(frame.benefit:GetStringWidth()) or 0)
        - Card.GAP - Card.TEXT_RIGHT
    -- Вторая строка: до правого края карточки.
    out.why = full - left - Card.TEXT_RIGHT
    -- Третья строка: до того, что стоит справа.
    local right = Card.TEXT_RIGHT
    if showAction then right = right + (tonumber(frame.action:GetWidth()) or 0) end
    if canRoute then right = right + (tonumber(frame.route:GetWidth()) or 0) + 6 end
    right = right + (tonumber(frame.badge:GetWidth()) or 0) + Card.GAP
    if card.plan then right = right + (tonumber(frame.meter:GetWidth()) or 0) + Card.GAP end
    out.need = full - left - right - Card.GAP
    return out
end

local function onCardEnter(self)
    self.hover:Show()
    local card = self.card
    if not card then return end
    local extra = {}
    -- ПОЛНЫЙ ТЕКСТ ТОГО, ЧТО НЕ ВЛЕЗЛО В СТРОКУ.
    --
    -- Строки карточки укорачиваются по ширине окна (W.SetFitted) и помечаются
    -- «…». Подсказка - то место, где ширина не мешает, поэтому здесь стоит
    -- ровно то, что было укорочено, и целиком. Не укорочено - не повторяем:
    -- второй раз та же фраза ничего не сообщает.
    local cut = self.cut or {}
    if cut.title and card.title then extra[#extra + 1] = card.title end
    if cut.why and card.why then extra[#extra + 1] = card.why end
    if cut.need and card.need then extra[#extra + 1] = card.need end
    if card.plan then
        local plan = card.plan
        if plan.cost == 0 then
            -- Ноль - это не цена: «Материалы: 0м» читалось как «стоят ноль».
            table.insert(extra, "Материалы: всё уже есть")
        elseif plan.cost then
            table.insert(extra, "Материалы: " .. U.money(plan.cost))
        elseif plan.costPartial and plan.costPartial > 0 then
            table.insert(extra, "Материалы: от " .. U.money(plan.costPartial)
                .. " (часть цен неизвестна)")
        end
        if #plan.crafts > 1 then
            table.insert(extra, "Шагов крафта: " .. #plan.crafts)
            for i = 1, math.min(5, #plan.crafts) do
                local step = plan.crafts[i]
                table.insert(extra, "  " .. i .. ". " .. (step.recipe.name or "?")
                    .. " x" .. step.times)
            end
        end
        if plan.needsTrip then
            table.insert(extra, "Часть материалов в банке или у других персонажей")
        end
        if plan.hasCycle then
            table.insert(extra, "В цепочке есть циклическая зависимость — я её разорвал")
        end
        for _, line in ipairs(plan.shopping or {}) do
            local name = ns.ActionEngine.nameOf(line.itemID)
            local price = line.unit and U.money(line.unit * line.qty) or U.void(ns.VOID.NO_PRICE)
            table.insert(extra, "Нужно: " .. name .. " x" .. line.qty .. " — " .. price)
        end
    end
    -- ВТОРОЙ ВАРИАНТ С ТОЙ ЖЕ ВЕЩЬЮ. Надеть и продать - взаимоисключающие
    -- действия, и раньше про них было две спорящих карточки (см.
    -- Engine:FoldSellIntoGear). Теперь карточка одна, и подсказка называет
    -- второй вариант числом: в строке «почему» он есть, но она на экране
    -- обрезается шириной окна, а подсказка - нет.
    if card.alsoSell then
        table.insert(extra, "Или продать, а не надевать: прибыль "
            .. tostring(card.alsoSell.benefit)
            .. (card.alsoSell.revenue
                and (", выручка " .. U.money(card.alsoSell.revenue)) or ""))
    end
    -- ГДЕ ИСКАТЬ РЕЦЕПТ - ОДНОЙ СТРОКОЙ, ЗДЕСЬ ЖЕ.
    --
    -- Длинного объяснения (Card.ActionNote: «Окно профессий я не открываю:
    -- игра это аддонам запрещает…») в подсказке нет и быть не должно: такое
    -- объяснение занимало здесь пять строк поверх игровых данных о предмете -
    -- то есть поверх того, за чем игрок на подсказку и смотрел, - и
    -- повторялось на каждом совете, которого касалась мышь.
    --
    -- Но и над списком оно больше не висит: там теперь одна короткая строка про
    -- то, что часть советов не показана (UI/TabNow.lua). Вопрос «а где кнопка?»
    -- возникает у конкретного совета, поэтому ответ стоит у него же и ровно
    -- одной строкой - Card.ActionNoteShort. Полный текст - в подробностях над
    -- списком и в подсказке панели.
    local short = Card.ActionNoteShort(card)
    if short then table.insert(extra, short) end
    -- И то, что относится к делу один раз: где это поправить, чем проверить.
    -- В строке совета такой подсказке места нет - она занимает место совета.
    if type(card.tipNote) == "string" and card.tipNote ~= "" then
        table.insert(extra, card.tipNote)
    end
    local placeTip = card.place and ns.Places:CardTip(card.place)
    if placeTip then table.insert(extra, placeTip) end
    table.insert(extra, "Достоверность: " .. (ns.CONF_LABEL[card.conf] or "?"))
    -- ОТКУДА ЧИСЛА - РЯДОМ С ДОСТОВЕРНОСТЬЮ, А НЕ В СТРОКЕ «ПОЧЕМУ».
    --
    -- Адрес сайта, дата его чтения и то, с чем сверены номера, - это ответ на
    -- вопрос «а проверить можно?», и задаёт его тот, кто уже наводит мышь.
    -- В строке «почему» на экране это сто с лишним символов, из-за которых
    -- сам совет не виден (см. Logic/Favor.lua, CaveatText).
    if type(card.sourceNote) == "string" and card.sourceNote ~= "" then
        table.insert(extra, card.sourceNote)
    end
    -- МЕСТО В СПИСКЕ, А НЕ БАЛЛ. Здесь стояло «Приоритет: 0.46 (профиль
    -- «Сила»)»: число без шкалы - много это или мало, игроку понять нечем. То,
    -- что он за ним хотел бы узнать, - какой этот совет по счёту и что решает
    -- порядок. Это и сказано. Сам балл остаётся в файле диагностики.
    local position, total = nil, 0
    for i, other in ipairs((ns.ActionEngine and ns.ActionEngine.cards) or {}) do
        total = i
        if other == card or (other.key ~= nil and other.key == card.key) then
            position = position or i
        end
    end
    if position then
        table.insert(extra, "Место в общем списке: " .. position .. " из " .. total
            .. " (порядок задаёт профиль «"
            .. (ns.PROFILE_LABEL[ns.Config:Profile()] or "?") .. "»)")
    end

    if card.link then
        W.ShowItemTip(self, card.link, extra)
    else
        W.ShowTip(self, card.title, extra)
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

    frame = CreateFrame("Button", nil, parent)
    frame:SetHeight(Card.HEIGHT)
    W.Backdrop(frame, 0.08, 0.08, 0.10, 0.80, 0.08)

    local hover = frame:CreateTexture(nil, "BORDER")
    hover:SetAllPoints(frame)
    local hc = W.COLOR.rowHover
    hover:SetColorTexture(hc[1], hc[2], hc[3], hc[4])
    hover:Hide()
    frame.hover = hover

    -- A coloured spine on the left tells the kind apart at a glance.
    local spine = frame:CreateTexture(nil, "ARTWORK")
    spine:SetPoint("TOPLEFT", 0, 0)
    spine:SetPoint("BOTTOMLEFT", 0, 0)
    spine:SetWidth(3)
    frame.spine = spine

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(Card.ICON, Card.ICON)
    icon:SetPoint("TOPLEFT", Card.PAD, -9)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    frame.icon = icon

    -- Line 1: title left, payoff right.
    frame.benefit = W.Label(frame, "", W.FONT_NORMAL)
    frame.benefit:SetPoint("TOPRIGHT", -12, -9)
    frame.benefit:SetJustifyH("RIGHT")

    frame.title = W.Label(frame, "", W.FONT_NORMAL, 1, 1, 1)
    frame.title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, 1)
    frame.title:SetPoint("RIGHT", frame.benefit, "LEFT", -8, 0)
    frame.title:SetJustifyH("LEFT")
    frame.title:SetWordWrap(false)

    -- Line 2: why.
    frame.why = W.Label(frame, "", W.FONT_SMALL, 0.72, 0.72, 0.72)
    frame.why:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -3)
    frame.why:SetPoint("RIGHT", frame, "RIGHT", -12, 0)
    frame.why:SetJustifyH("LEFT")
    frame.why:SetWordWrap(false)
    frame.why:SetHeight(Card.LINE_H)

    -- Line 3: what is missing, plus the button and the badges on the right.
    frame.action = W.Button(frame, "", 128, Card.BUTTON_H)
    frame.action:SetPoint("BOTTOMRIGHT", -12, Card.BUTTON_BOTTOM)

    -- The route button. Only shown when there is somewhere to go AND something
    -- to draw the arrow with; otherwise the place goes in the text instead.
    frame.route = W.Button(frame, "Показать путь", 110, 20)
    frame.route:SetPoint("RIGHT", frame.action, "LEFT", -6, 0)
    frame.route:Hide()

    frame.badge = W.ConfBadge(frame, ns.CONF.UNKNOWN)
    frame.badge:SetPoint("RIGHT", frame.route, "LEFT", -8, 0)

    frame.meter = W.Meter(frame, 44, 4)
    frame.meter:SetPoint("RIGHT", frame.badge, "LEFT", -8, 0)

    -- ТРЕТЬЯ СТРОКА - ОТ НИЖНЕГО КРАЯ, А НЕ ОТ ИКОНКИ.
    --
    -- Здесь стояло `SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 10, -1)`, то
    -- есть строка висела на иконке и ехала вверх, навстречу строке «почему».
    -- Так они и столкнулись (см. разметку в начале файла). Обе привязки ниже
    -- дают одну и ту же высоту - середину ряда кнопок, - поэтому спорить между
    -- собой они не могут.
    frame.need = W.Label(frame, "", W.FONT_SMALL, 0.85, 0.72, 0.45)
    frame.need:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", Card.TEXT_LEFT, Card.ROW3_BOTTOM)
    frame.need:SetPoint("RIGHT", frame.meter, "LEFT", -8, 0)
    frame.need:SetJustifyH("LEFT")
    frame.need:SetWordWrap(false)
    frame.need:SetHeight(Card.LINE_H)

    frame:SetScript("OnEnter", onCardEnter)
    frame:SetScript("OnLeave", onCardLeave)
    frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    frame:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            -- Two deliberate clicks, not one stray one. See Card.RequestDismiss.
            Card.RequestDismiss(self.card)
        else
            -- Any left-click is "I meant something else", so it disarms.
            Card.Disarm()
            Card.Activate(self.card)
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

function Card.Fill(frame, card)
    frame.card = card

    local spine = Card.SpineColor(card.kind)
    frame.spine:SetColorTexture(spine[1], spine[2], spine[3], 0.95)

    if card.pinTop then
        frame.fpBG:SetColorTexture(0.16, 0.11, 0.04, 0.92)
    else
        frame.fpBG:SetColorTexture(0.08, 0.08, 0.10, 0.80)
    end

    frame.icon:SetTexture(card.icon or ns.KIND_ICON[card.kind] or "Interface\\Icons\\INV_Misc_QuestionMark")

    -- Сам текст заголовка ставится в конце, вместе с остальными строками: его
    -- ширина зависит от столбца выгоды, а тот ещё не заполнен.
    if card.pinTop then
        frame.title:SetTextColor(1, 0.86, 0.55)
    else
        frame.title:SetTextColor(1, 1, 1)
    end

    frame.benefit:SetText(card.benefit or "")
    local bc = W.benefitColor(card.benefitKind)
    frame.benefit:SetTextColor(bc[1], bc[2], bc[3])

    local ready = card.plan and card.plan.ready
    if ready then
        frame.need:SetTextColor(0.50, 0.85, 0.55)
    elseif card.kind == ns.KIND.SETUP then
        frame.need:SetTextColor(1.00, 0.80, 0.40)
    else
        frame.need:SetTextColor(0.85, 0.72, 0.45)
    end

    frame.badge:Set(card.conf)
    frame.meter:SetValue(card.plan and card.plan.readiness or (card.pinTop and 0 or 1))
    if card.plan then frame.meter:Show() else frame.meter:Hide() end

    local label = Card.ActionLabel(card)
    frame.action:SetLabel(label)
    frame.action:SetScript("OnClick", function() Card.Activate(card) end)
    -- Подсказка кнопки: что именно она сделает сейчас. Подпись у кнопки одна, а
    -- дел у неё три (свой совет, аукцион, профессия) - без подсказки непонятно,
    -- почему она то одна, то другая.
    frame.action:SetScript("OnEnter", function(self)
        self.fpBG:SetColorTexture(0.22, 0.34, 0.55, 0.95)
        local title, body = Card.ActionTip(card)
        if title then W.ShowTip(self, title, body) end
    end)
    frame.action:SetScript("OnLeave", function(self)
        self.fpBG:SetColorTexture(0.14, 0.16, 0.22, 0.95)
        W.HideTip()
    end)
    local showAction = not (card.action and card.action.kind == "noop")
        and Card.ActionReady(card)
    if showAction then frame.action:Show() else frame.action:Hide() end

    -- Route button: needs a place with coordinates and a navigation addon to
    -- hand them to. Missing either one is normal, and then there is no button.
    local canRoute = card.place and card.place.routable and ns.Places:CanRoute()
    if canRoute then
        frame.route:Show()
        frame.route:SetScript("OnClick", function() Card.Route(card) end)
        frame.route:SetScript("OnEnter", function(self)
            self.fpBG:SetColorTexture(0.22, 0.34, 0.55, 0.95)
            W.ShowTip(self, "Показать путь", {
                ns.Places:Describe(card.place) or "",
                "Поставлю метку на карте и стрелку на экране.",
                "Иду я туда не сам — идёте вы.",
            })
        end)
        frame.route:SetScript("OnLeave", function(self)
            self.fpBG:SetColorTexture(0.14, 0.16, 0.22, 0.95)
            W.HideTip()
        end)
    else
        frame.route:Hide()
    end

    -- Keep the badge anchored to whatever is actually visible.
    frame.badge:ClearAllPoints()
    if canRoute then
        frame.badge:SetPoint("RIGHT", frame.route, "LEFT", -8, 0)
    elseif showAction then
        frame.badge:SetPoint("RIGHT", frame.action, "LEFT", -8, 0)
    else
        frame.badge:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 9)
    end

    -- ТЕКСТ - ПОСЛЕДНИМ, И ПО ИЗМЕРЕННОМУ МЕСТУ.
    --
    -- Раньше здесь стояло три SetText, а лишнее обрезал клиент - по пикселям,
    -- то есть посреди числа («Разница +8з 80…»). Теперь сколько места есть,
    -- столько и занимаем: ширина считается по разметке и по тому, что сейчас
    -- нарисовано справа, а укорачивает текст W.SetFitted - целыми кусками и не
    -- разрезая чисел. Поэтому ставится текст ПОСЛЕ кнопок: до них ширина
    -- третьей строки неизвестна.
    local room = Card.RoomFor(frame, card, showAction, canRoute)
    local _, titleCut = W.SetFitted(frame.title, card.title or "", room.title)
    local _, whyCut = W.SetFitted(frame.why, card.why or "", room.why)
    local _, needCut = W.SetFitted(frame.need, card.need or "", room.need)
    frame.cut = { title = titleCut, why = whyCut, need = needCut }
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
