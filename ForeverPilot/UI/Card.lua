-- ForeverPilot / UI/Card.lua
--
-- Строка списка советов. В ней ОДНА строка текста и НИ ОДНОЙ КНОПКИ: слева
-- иконка и что сделать, справа - что это даст.
--
-- ЩЕЛЧОК ПО СТРОКЕ ВЫБИРАЕТ СОВЕТ: справа от списка открывается его карточка
-- (UI/TabNow.lua, Detail) - там всё остальное: почему, чего не хватает,
-- материалы, целиком и с переносом строк, и одна золотая кнопка. Так устроено
-- большое окно Polestar, и игрок попросил сделать так же: раньше в каждой
-- строке было три строки текста и кнопка, и было «непонятно, на какую кнопку
-- что, куда нажимать» (2026-11-21). Теперь список читается одним взглядом, а
-- кнопка на экране одна - у выбранного совета.
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

Card.HEIGHT = 30

-- РАЗМЕТКА СТРОКИ, ЧИСЛАМИ В ОДНОМ МЕСТЕ.
--
-- Все отступы названы здесь и выведены одно из другого: когда они были вписаны
-- по месту, строки карточки налезали друг на друга на несколько пикселей, и ни
-- одна проверка этого не видела. Tests/test_nonsense.lua считает прямоугольники
-- по привязкам - так же, как их считает клиент, - и требует, чтобы они лежали
-- внутри строки и не пересекались.
Card.PAD = 12                -- отступ слева, он же у иконки
Card.ICON = 20               -- сторона иконки
Card.TEXT_LEFT = Card.PAD + Card.ICON + 8    -- где начинается текст
Card.LINE_H = 12             -- высота строки мелкого шрифта
Card.TITLE_H = 14            -- высота строки заголовка
Card.TITLE_TOP = (Card.HEIGHT - Card.TITLE_H) / 2   -- заголовок по середине строки
Card.TEXT_RIGHT = 12         -- от правого края строки до текста
Card.GAP = 10                -- между заголовком и выгодой
-- Выгоде справа отведена эта доля строки - и всё, что не занял заголовок:
-- «костёр для готовки и место ещё под 3 предмета лагеря» иначе не оставляет
-- заголовку места.
Card.BENEFIT_SHARE = 0.40

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
    out.title = area - (tonumber(frame.benefit:GetStringWidth()) or 0) - Card.GAP
    return out
end

-- ЧТО ИЗВЕСТНО О СОВЕТЕ СВЕРХ ЕГО СТРОК: материалы и шаги плана, второй
-- вариант с той же вещью, где искать рецепт, чем проверить.
--
-- Одни и те же строки идут в два места: в подсказку под курсором и в карточку
-- совета справа от списка. Раньше они жили только в подсказке, то есть до них
-- надо было догадаться навести мышь.
--
-- forDetail: в карточке справа короткой строки «где искать рецепт» нет - там
-- на месте кнопки стоит полное объяснение (Card.ActionNote), и вторая такая же
-- фраза рядом была бы повтором.
function Card.FactLines(card, forDetail)
    local out = {}
    if not card then return out end
    if card.plan then
        local plan = card.plan
        if plan.cost == 0 then
            -- Ноль - это не цена: «Материалы: 0м» читалось как «стоят ноль».
            table.insert(out, "Материалы: всё уже есть")
        elseif plan.cost then
            table.insert(out, "Материалы: " .. U.money(plan.cost))
        elseif plan.costPartial and plan.costPartial > 0 then
            table.insert(out, "Материалы: от " .. U.money(plan.costPartial)
                .. " (часть цен неизвестна)")
        end
        if #plan.crafts > 1 then
            table.insert(out, "Шагов крафта: " .. #plan.crafts)
            for i = 1, math.min(5, #plan.crafts) do
                local step = plan.crafts[i]
                table.insert(out, "  " .. i .. ". " .. (step.recipe.name or "?")
                    .. " x" .. step.times)
            end
        end
        if plan.needsTrip then
            table.insert(out, "Часть материалов в банке или у других персонажей")
        end
        if plan.hasCycle then
            table.insert(out, "В цепочке есть циклическая зависимость — я её разорвал")
        end
        for _, line in ipairs(plan.shopping or {}) do
            local name = ns.ActionEngine.nameOf(line.itemID)
            local price = line.unit and U.money(line.unit * line.qty) or U.void(ns.VOID.NO_PRICE)
            table.insert(out, "Нужно: " .. name .. " x" .. line.qty .. " — " .. price)
        end
    end
    -- ВТОРОЙ ВАРИАНТ С ТОЙ ЖЕ ВЕЩЬЮ. Надеть и продать - взаимоисключающие
    -- действия, и раньше про них было две спорящих карточки (см.
    -- Engine:FoldSellIntoGear). Теперь карточка одна, и подсказка называет
    -- второй вариант числом: в строке «почему» он есть, но она на экране
    -- обрезается шириной окна, а подсказка - нет.
    if card.alsoSell then
        table.insert(out, "Или продать, а не надевать: прибыль "
            .. tostring(card.alsoSell.benefit)
            .. (card.alsoSell.revenue
                and (", выручка " .. U.money(card.alsoSell.revenue)) or ""))
    end
    if not forDetail then
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
        if short then table.insert(out, short) end
    end
    -- И то, что относится к делу один раз: где это поправить, чем проверить.
    -- В строке совета такой подсказке места нет - она занимает место совета.
    if type(card.tipNote) == "string" and card.tipNote ~= "" then
        table.insert(out, card.tipNote)
    end
    local placeTip = card.place and ns.Places:CardTip(card.place)
    if placeTip then table.insert(out, placeTip) end
    -- ОТКУДА ЧИСЛА - РЯДОМ С ДОСТОВЕРНОСТЬЮ, А НЕ В СТРОКЕ «ПОЧЕМУ».
    --
    -- Адрес сайта, дата его чтения и то, с чем сверены номера, - это ответ на
    -- вопрос «а проверить можно?», и задаёт его тот, кто уже наводит мышь.
    -- В строке «почему» на экране это сто с лишним символов, из-за которых
    -- сам совет не виден (см. Logic/Favor.lua, CaveatText).
    if type(card.sourceNote) == "string" and card.sourceNote ~= "" then
        table.insert(out, card.sourceNote)
    end
    return out
end

-- МЕСТО В СПИСКЕ, А НЕ БАЛЛ. Здесь стояло «Приоритет: 0.46 (профиль
-- «Сила»)»: число без шкалы - много это или мало, игроку понять нечем. То,
-- что он за ним хотел бы узнать, - какой этот совет по счёту и что решает
-- порядок. Это и сказано. Сам балл остаётся в файле диагностики.
function Card.PlaceLine(card)
    if not card then return nil end
    local position, total = nil, 0
    for i, other in ipairs((ns.ActionEngine and ns.ActionEngine.cards) or {}) do
        total = i
        if other == card or (other.key ~= nil and other.key == card.key) then
            position = position or i
        end
    end
    if not position then return nil end
    return "Место в общем списке: " .. position .. " из " .. total
        .. " (порядок задаёт профиль «"
        .. (ns.PROFILE_LABEL[ns.Config:Profile()] or "?") .. "»)"
end

-- Подсказка строки списка. cut - что в строке было укорочено (frame.cut).
function Card.TipLines(card, cut)
    local extra = {}
    if not card then return extra end
    cut = cut or {}
    -- ПОЛНЫЙ ТЕКСТ ТОГО, ЧТО НЕ ВЛЕЗЛО В СТРОКУ.
    --
    -- Строки укорачиваются по ширине окна (W.SetFitted) и помечаются «…».
    -- Подсказка - то место, где ширина не мешает, поэтому здесь стоит ровно то,
    -- что было укорочено, и целиком. Не укорочено - не повторяем: второй раз та
    -- же фраза ничего не сообщает.
    if cut.title and card.title then extra[#extra + 1] = card.title end
    if cut.benefit and card.benefit then extra[#extra + 1] = card.benefit end
    -- «Почему» и «чего не хватает» в строке списка нет вовсе (они в карточке
    -- справа), поэтому под курсором они есть всегда.
    if card.why and card.why ~= "" then extra[#extra + 1] = card.why end
    if card.need and card.need ~= "" then extra[#extra + 1] = card.need end
    for _, line in ipairs(Card.FactLines(card)) do
        if line == card.sourceNote then
            -- Достоверность стоит перед источником чисел, как и раньше.
            extra[#extra + 1] = "Достоверность: " .. (ns.CONF_LABEL[card.conf] or "?")
        end
        extra[#extra + 1] = line
    end
    if not (type(card.sourceNote) == "string" and card.sourceNote ~= "") then
        extra[#extra + 1] = "Достоверность: " .. (ns.CONF_LABEL[card.conf] or "?")
    end
    local place = Card.PlaceLine(card)
    if place then extra[#extra + 1] = place end
    return extra
end

local function onCardEnter(self)
    self.hover:Show()
    local card = self.card
    if not card then return end
    local extra = Card.TipLines(card, self.cut)
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
        -(Card.HEIGHT - Card.LINE_H) / 2)
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
            for k = #atoms - 1, 1, -1 do
                local last = atoms[k]
                if last.number or U.charLen(last.text) > 2 then
                    local parts = {}
                    for i = 1, k do parts[i] = atoms[i].text end
                    variants[#variants + 1] = table.concat(parts, " ") .. " " .. U.MORE_MARK
                end
            end
            out, cut = W.SetFittedFrom(fs, variants, room)
        else
            out, cut = W.SetFitted(fs, text, room)
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
    local title = tostring(card.title or "")
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
    frame.cut = { title = titleCut, benefit = benefitCut }
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
