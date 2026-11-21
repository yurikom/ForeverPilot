-- ForeverPilot / UI/StepPanel.lua
--
-- The small always-on-screen panel: the ONE thing to do right now, a button to
-- route to it, a button to put it aside, and a click anywhere else to open the
-- full window.
--
-- Patterns taken from Polestar (studied, not copied - Polestar is GPL-3.0 and
-- not a line of its code is here). Worth naming, because each of these is a
-- decision I would otherwise have got wrong:
--
--   * One derived predicate decides whether to hide, and it NEVER writes the
--     player's own on/off setting. So leaving combat or a dungeon restores
--     exactly what they had, instead of silently turning the panel off.
--   * Combat is three-way: show / fade to 35% / hide. Fading on every pull is
--     distracting, so "show" is the default.
--   * The frame is not created at all until the panel is first enabled. Off
--     costs nothing.
--   * Position is saved on drag stop as two numbers from the screen's
--     bottom-left, not as a point name plus offsets.
--   * «Дальше» ЛИСТАЕТ, А НЕ ПРЯЧЕТ. Раньше она откладывала совет на час и
--     проигрывала анимацию «готово» - то есть называлась «дальше», а делала
--     «убрать». Игрок трижды остался без советов и каждый раз решал, что аддон
--     сломан. Теперь панель помнит, на каком совете игрок остановился, и ходит
--     по списку по кругу; число скрытых от «Дальше» не меняется никогда.
--   * Hover highlight lives on the HIGHLIGHT draw layer, so the client shows
--     and hides it with no script of ours running every frame.
--   * A derived estimate is always written with a tilde, and when the input is
--     missing we say nothing rather than inventing a number.
local ADDON, ns = ...

local U = ns.Util
local W = ns.Widgets

local Panel = {}
ns.StepPanel = Panel

Panel.WIDTH_MIN, Panel.WIDTH_MAX = 220, 460
-- Просвет между «Дальше» и кнопками «свернуть»/«убрать» в заголовке панели.
Panel.NEXT_GAP = 14

-- Как убрать панель снова. Одна строка на все места, где об этом говорится:
-- иначе «крестик на самой панели» живёт в трёх файлах тремя формулировками.
Panel.CLOSE_HINT = "Убрать её снова — кнопка " .. ns.GLYPH.CLOSE
    .. " в её правом верхнем углу."
Panel.COMBAT_ALPHA = 0.35
-- Здесь стояли FOLD_HOLD, POP_TIME и REDUCED_TIME - времена анимации «готово»,
-- которую проигрывала «Дальше» перед тем, как спрятать совет. «Дальше» больше
-- ничего не прячет и ничего не «завершает», так что анимации нет, а константа
-- для несуществующей анимации - это обещание в коде. Убраны вместе с ней и с
-- галочкой «Меньше анимации» в настройках, которой стало нечем управлять.

-- State -----------------------------------------------------------------

Panel.current = nil     -- the card we are showing
Panel.inCombat = false
Panel.inInstance = false

-- ГДЕ ИГРОК ОСТАНОВИЛСЯ. Позиция в списке вместо скрытия просмотренного.
--
--   cursorKey   - ключ совета, до которого игрок долистал кнопкой «Дальше».
--                 nil значит «не листал»: панель показывает верх списка и
--                 следует за ним, как и раньше, когда ранжирование меняется.
--   cursorIndex - его номер среди кандидатов. Нужен на случай, когда сам совет
--                 пропал (выполнен, сменился профиль): тогда панель продолжает
--                 с того же места, а не прыгает в начало.
--
-- Живёт только в памяти, не в SavedVariables: каждый вход в игру начинается с
-- самого важного совета, а не с того, на котором вчера остановились.
Panel.cursorKey = nil
Panel.cursorIndex = 1
-- Panel.folding тоже убрано: объявлено, задокументировано и не прочитано ни
-- разу - единственное упоминание в файле было здесь.

-- Visibility ------------------------------------------------------------

-- Derived, never stored. This is the Polestar pattern: the rules compute a
-- veto, the player's own setting stays untouched.
function Panel:RulesHide()
    local cfg = ns.Config:Get()
    if not cfg then return false end
    local p = cfg.panel
    if self.inCombat and p.combat == "hide" then return true end
    if self.inInstance and p.instance == "hide" then return true end
    return false
end

function Panel:Wanted()
    local cfg = ns.Config:Get()
    if not (cfg and cfg.panel.enabled) then return false end
    if self:RulesHide() then return false end
    return true
end

function Panel:TargetAlpha()
    local cfg = ns.Config:Get()
    local base = (cfg and cfg.panel.opacity) or 1
    if self.inCombat and cfg and cfg.panel.combat == "fade" then
        base = base * Panel.COMBAT_ALPHA
    end
    return U.clamp(base, 0.1, 1)
end

function Panel:ApplyVisibility()
    if not self.frame then
        -- Nothing exists yet. Build only when the panel is actually wanted.
        if self:Wanted() then self:Build() else return end
    end
    if self:Wanted() then
        self.frame:Show()
        self.frame:SetAlpha(self:TargetAlpha())
    else
        self.frame:Hide()
        -- Флаг перетаскивания снимается и здесь. Он сбрасывался только в
        -- OnDragStop, а панель может быть скрыта правилом боя посреди
        -- перетаскивания — тогда OnDragStop не придёт, флаг останется, и
        -- щелчок по панели перестанет открывать окно до перезахода в игру.
        Panel.dragging = nil
    end
end

-- Build -----------------------------------------------------------------

function Panel:Build()
    if self.frame then return self.frame end
    local cfg = ns.Config:Get()

    local f = CreateFrame("Button", "ForeverPilotStepPanel", UIParent)
    self.frame = f
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:Hide()
    W.Backdrop(f, 0.05, 0.05, 0.07, 0.88, 0.14)

    -- Hover on the HIGHLIGHT layer: the client toggles it for us.
    local hl = f:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(f)
    hl:SetColorTexture(1, 1, 1, 0.05)

    -- A coloured spine so the kind of advice reads at a glance, same language
    -- as the cards in the big window.
    local spine = f:CreateTexture(nil, "ARTWORK")
    spine:SetPoint("TOPLEFT")
    spine:SetPoint("BOTTOMLEFT")
    spine:SetWidth(3)
    f.spine = spine

    -- Header: a tiny title that doubles as the drag handle hint.
    f.header = W.Label(f, "Сейчас", W.FONT_SMALL, 0.55, 0.55, 0.55)
    f.header:SetPoint("TOPLEFT", 10, -7)

    -- ЗАКРЫТЬ И СВЕРНУТЬ - ЭТО ДВА РАЗНЫХ ДЕЙСТВИЯ, И ОБА ДОЛЖНЫ БЫТЬ.
    --
    -- Раньше тут был только «—». Панель всегда на экране, свернуть её можно, а
    -- УБРАТЬ - нельзя: галочка «Показывать панель» лежала в настройках, куда
    -- надо ещё догадаться пойти. Для игрока это выглядит как окно без крестика.
    --
    -- Крестик правее, свернуть левее: крестик у края - это общее место во всех
    -- окнах игры, и рука идёт туда сама.
    f.close = W.Button(f, ns.GLYPH.CLOSE, 18, 14, function() Panel:CloseByPlayer() end)
    f.close:SetPoint("TOPRIGHT", -8, -6)
    f.close:SetScript("OnEnter", function(self2)
        self2.fpBG:SetColorTexture(0.45, 0.18, 0.18, 0.95)
        W.ShowTip(self2, "Убрать панель", {
            "Советы считаться не перестанут — исчезнет только эта панель.",
            Panel:HowToShow(),
        })
    end)
    f.close:SetScript("OnLeave", function(self2)
        self2.fpBG:SetColorTexture(0.14, 0.16, 0.22, 0.95)
        W.HideTip()
    end)

    f.collapse = W.Button(f, "—", 18, 14, function() Panel:ToggleCollapsed() end)
    f.collapse:SetPoint("TOPRIGHT", f.close, "TOPLEFT", -4, 0)
    f.collapse:SetScript("OnEnter", function(self2)
        self2.fpBG:SetColorTexture(0.22, 0.34, 0.55, 0.95)
        W.ShowTip(self2, ns.Config:Get().panel.collapsed
            and "Развернуть панель" or "Свернуть панель",
            "Свёрнутая панель — одна строка с названием совета."
            .. " Она остаётся на экране; чтобы убрать её совсем, нажмите кнопку "
                .. ns.GLYPH.CLOSE .. ".")
    end)
    f.collapse:SetScript("OnLeave", function(self2)
        self2.fpBG:SetColorTexture(0.14, 0.16, 0.22, 0.95)
        W.HideTip()
    end)

    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(28, 28)
    f.icon:SetPoint("TOPLEFT", 10, -22)
    f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    f.benefit = W.Label(f, "", W.FONT_SMALL)
    f.benefit:SetPoint("TOPRIGHT", -8, -23)
    f.benefit:SetJustifyH("RIGHT")

    f.title = W.Label(f, "", W.FONT_NORMAL, 1, 1, 1)
    f.title:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 8, 1)
    f.title:SetPoint("RIGHT", f.benefit, "LEFT", -6, 0)
    f.title:SetJustifyH("LEFT")
    f.title:SetWordWrap(false)

    f.detail = W.Label(f, "", W.FONT_SMALL, 0.72, 0.72, 0.72)
    f.detail:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -3)
    f.detail:SetPoint("RIGHT", f, "RIGHT", -8, 0)
    f.detail:SetJustifyH("LEFT")
    f.detail:SetWordWrap(true)
    f.detail:SetHeight(26)

    -- Buttons row. The route button appears only when there is a place to go
    -- AND something to draw the arrow with.
    f.route = W.Button(f, "Показать путь", 104, 18, function() Panel:Route() end)
    f.route:SetPoint("BOTTOMLEFT", 10, 8)

    -- «ДАЛЬШЕ» ЖИВЁТ В ЗАГОЛОВКЕ, А НЕ НА МЕСТЕ КНОПКИ ДЕЙСТВИЯ.
    --
    -- Раньше она делила одно место с кнопкой действия: есть у совета своё
    -- действие - стоит оно, нет - стоит «Дальше». Своё действие есть почти у
    -- каждого совета, так что «Дальше» игрок почти не видел, а пойти дальше мог
    -- только правым щелчком - который совет прячет. В заголовке она есть у
    -- любого совета и ни с чем не спорит за место.
    --
    -- И она НИЧЕГО НЕ ПРЯЧЕТ: см. Panel:Advance. Показывается только когда
    -- листать есть куда - кнопка, которая ничего не делает, это тот же дефект,
    -- что текст про кнопку, которой нет.
    -- НЕ ВПЛОТНУЮ К «СВЕРНУТЬ» И «УБРАТЬ». «Дальше» - самая нажимаемая кнопка
    -- панели, а справа от неё стоят две, после которых панель меняется целиком:
    -- одна сворачивает её в строку, другая убирает с экрана. Между ними и
    -- «Дальше» оставлен просвет втрое шире обычного, чтобы промах мимо «Дальше»
    -- попадал в пустое место, а не в соседнюю кнопку.
    f.next = W.Button(f, "Дальше", 52, 14, function() Panel:Advance() end)
    f.next:SetPoint("TOPRIGHT", f.collapse, "TOPLEFT", -Panel.NEXT_GAP, 0)
    f.next:Hide()
    f.next:SetScript("OnEnter", function(self2)
        self2.fpBG:SetColorTexture(0.22, 0.34, 0.55, 0.95)
        W.ShowTip(self2, "Следующий совет", {
            "Листаю советы по кругу: этот никуда не денется и вернётся,"
                .. " когда круг замкнётся.",
            "Ничего не прячу и из списка не убираю.",
        })
    end)
    f.next:SetScript("OnLeave", function(self2)
        self2.fpBG:SetColorTexture(0.14, 0.16, 0.22, 0.95)
        W.HideTip()
    end)

    -- СОБСТВЕННОЕ ДЕЙСТВИЕ СОВЕТА, А НЕ ОДНА КНОПКА НА ВСЕ СЛУЧАИ.
    --
    -- Вот из-за чего эта кнопка появилась. Карточка «Скрытых советов: 15»
    -- несёт действие «Вернуть все» и её текст прямо просит это нажать - а
    -- панель рисовала только «Дальше»/«Открыть» и действие карточки
    -- игнорировала. Текст отправлял игрока нажать то, чего на экране не было.
    --
    -- Кнопка справа внизу одна и подписана тем, что реально сделает: своим
    -- действием совета, если оно есть, и «Открыть» (полное окно), если нет.
    f.action = W.Button(f, "", 104, 18, function() Panel:DoAction() end)
    f.action:SetPoint("BOTTOMRIGHT", -8, 8)
    f.action:Hide()

    f.badge = W.ConfBadge(f, ns.CONF.UNKNOWN)
    f.badge:SetPoint("BOTTOMRIGHT", f.action, "BOTTOMLEFT", -6, 0)

    -- Drag. Shift is not required; the player can lock it in settings.
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f:SetScript("OnDragStart", function(self2)
        if ns.Config:Get().panel.locked then return end
        self2:StartMoving()
        Panel.dragging = true
    end)
    f:SetScript("OnDragStop", function(self2)
        self2:StopMovingOrSizing()
        Panel.dragging = nil
        Panel:SavePosition()
    end)
    f:SetScript("OnClick", function(_, button)
        if Panel.dragging then return end
        if button == "RightButton" then
            -- Два осознанных щелчка, а не один случайный: см. Panel:Dismiss.
            Panel:Dismiss()
        else
            -- Любой левый щелчок - это «я имел в виду другое»: вопрос «скрыть?»
            -- снимается, как и в списке.
            ns.Card.Disarm()
            -- Clicking the panel opens the full window, which is the whole
            -- point of having a small panel at all.
            ns.MainFrame:Show()
            ns.MainFrame:Select("NOW")
        end
    end)
    f:SetScript("OnEnter", function(self2)
        if not (ns.Config:Get().ui.tooltips) then return end
        local card = Panel.current
        local lines = { "Щелчок — открыть полное окно" }
        -- ПОДСКАЗКА ГОВОРИТ ТО, ЧТО РЕАЛЬНО ПРОИЗОЙДЁТ.
        --
        -- «Правый щелчок — отложить этот совет» стояло здесь всегда, в том
        -- числе на обязательных советах, которые отложить нельзя: щелчок по
        -- ним только печатает отказ. Подсказка обещала действие, которого на
        -- этой карточке нет.
        --
        -- Правый щелчок - ЕДИНСТВЕННОЕ на панели, что прячет совет, поэтому
        -- здесь названо всё сразу: что он делает, на какой срок и как вернуть.
        -- И названо честно: щелчков нужно ДВА, первый только спрашивает.
        if card and card.blocking then
            lines[#lines + 1] = "Этот совет не прячется: без него остальные"
                .. " будут неполными"
        else
            lines[#lines + 1] = "Два правых щелчка — спрятать этот совет на "
                .. (U.durationText(ns.SNOOZE_SECONDS) or "время")
                .. " (вернуть: /fp undo)"
        end
        -- Про «Дальше» - только когда она на экране: иначе подсказка называла
        -- бы кнопку, которой нет.
        if self2.next and self2.next:IsShown() then
            lines[#lines + 1] = "«Дальше» — следующий совет по кругу; ничего не прячет"
        end
        lines[#lines + 1] = ns.GLYPH.CLOSE .. " — убрать панель. " .. Panel:HowToShow()
        if not ns.Config:Get().panel.locked then
            table.insert(lines, 1, "Потяните, чтобы передвинуть")
        end
        if card and card.why then table.insert(lines, 1, card.why) end
        -- Почему у совета нет своей кнопки (если нет): та же строка, что в окне.
        local actionNote = card and ns.Card.ActionNote(card)
        if actionNote then lines[#lines + 1] = actionNote end
        W.ShowTip(self2, card and card.title or "ForeverPilot", lines)
    end)
    f:SetScript("OnLeave", W.HideTip)

    -- РАЗМЕР ПЕРВЫМ, ПОТОМ ПОЗИЦИЯ.
    --
    -- Порядок здесь не вкусовой. ApplyPosition проверяет, не осталась ли
    -- сохранённая позиция за краем экрана, а для этого нужна геометрия: у
    -- свежего CreateFrame размер 0x0, пока не позвали SetSize. На нулевом
    -- фрейме проверка объявляла панель потерянной, стирала cfg.panel.pos и
    -- печатала в чат, что поставила её на место, — и это происходило при
    -- каждом входе в игру. Стрелка и окно всегда делали в этом порядке.
    Panel:ApplySize()
    Panel:ApplyPosition()
    Panel:ApplyCollapsed()
    return f
end

-- Geometry --------------------------------------------------------------

function Panel:ApplySize()
    if not self.frame then return end
    local cfg = ns.Config:Get()
    local width = U.clamp(cfg.panel.width or 300, Panel.WIDTH_MIN, Panel.WIDTH_MAX)
    self.frame:SetWidth(width)
    self.frame:SetScale(U.clamp(cfg.panel.scale or 1, 0.7, 1.6))
    self.frame:SetHeight(cfg.panel.collapsed and 24 or 104)
end

-- Saved as two numbers from the screen's bottom-left, which survives a
-- resolution change better than a point name plus offsets.
function Panel:SavePosition()
    if not self.frame then return end
    local cfg = ns.Config:Get()
    local left = self.frame:GetLeft()
    local bottom = self.frame:GetBottom()
    if left and bottom then
        cfg.panel.pos = { U.round(left), U.round(bottom) }
    end
end

function Panel:ApplyPosition()
    if not self.frame then return end
    local cfg = ns.Config:Get()
    -- СОХРАНЁННАЯ ПОЗИЦИЯ МОГЛА СТАТЬ НЕГОДНОЙ, ПОКА ИГРОК НЕ ИГРАЛ.
    --
    -- SetClampedToScreen не даёт УТАЩИТЬ панель за край, но ничего не делает с
    -- координатами, которые были правильными на другом разрешении. Панель
    -- тогда возвращается за кадром, и схватить её нечем. Проверяем перед
    -- применением и в этом случае ставим на место по умолчанию.
    local pos = cfg.panel.pos
    if type(pos) == "table" and tonumber(pos[1]) and tonumber(pos[2]) then
        local w = self.frame:GetWidth() or 300
        local h = self.frame:GetHeight() or 104
        local sw = (UIParent and UIParent.GetWidth and UIParent:GetWidth()) or nil
        local sh = (UIParent and UIParent.GetHeight and UIParent:GetHeight()) or nil
        if U.frameOffScreen(pos[1], pos[2], pos[1] + w, pos[2] + h, sw, sh) then
            cfg.panel.pos = nil
            pos = nil
            ns.Api:Print("панель оказалась за краем экрана — поставил её на место")
        end
    end
    self.frame:ClearAllPoints()
    if type(pos) == "table" and pos[1] and pos[2] then
        self.frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", pos[1], pos[2])
    else
        self.frame:SetPoint("TOP", UIParent, "TOP", 0, -140)
    end
end

function Panel:ResetPosition()
    ns.Config:Get().panel.pos = nil
    self:ApplyPosition()
end

function Panel:ToggleCollapsed()
    local cfg = ns.Config:Get()
    cfg.panel.collapsed = not cfg.panel.collapsed
    self:ApplyCollapsed()
end

function Panel:ApplyCollapsed()
    if not self.frame then return end
    local collapsed = ns.Config:Get().panel.collapsed
    local f = self.frame
    for _, part in ipairs({ f.icon, f.title, f.detail, f.benefit, f.route,
                            f.next, f.action, f.badge }) do
        if collapsed then part:Hide() else part:Show() end
    end
    f.collapse:SetLabel(collapsed and "+" or "—")
    f.header:SetText(collapsed and self:CollapsedSummary() or "Сейчас")
    self:ApplySize()
    if not collapsed then self:Render() end
end

function Panel:CollapsedSummary()
    local card = self.current
    if not card then return "ForeverPilot" end
    -- U.fitChars, а не U.truncate: по символам резать можно что угодно, кроме
    -- числа, а в заголовке оно есть («Предмет #249429», «Чары: 1/9»).
    return U.fitChars(card.title, 34)
end

-- Content ---------------------------------------------------------------

-- Есть ли у совета СВОЁ действие, под которое на панели стоит кнопка.
-- Информационный совет (noop) своего действия не имеет: его кнопка открывает
-- полное окно, где он написан целиком.
function Panel.HasOwnAction(card)
    local act = card and card.action
    if not (act and act.kind and act.kind ~= "noop" and act.label) then return false end
    -- Действие есть, но нажать его сейчас нельзя (показ рецепта до того, как
    -- игра загрузила окно профессий): своей кнопки у совета нет - как и в
    -- списке. Кнопка панели тогда подписана «Открыть» и открывает окно.
    return ns.Card.ActionReady(card) and true or false
end

-- Из чего панель выбирает. Возвращает список и признак «обязательный совет».
--
--   * Обязательный совет (pinTop) панель держит на виду одного: без него
--     остальные неполны, и пролистать его нельзя - список из одного элемента.
--   * Иначе - советы, по которым можно что-то сделать, в порядке ранжирования;
--     чисто информационные панель пропускает, это «что делать сейчас».
--   * Если делать нечего вовсе, остаются информационные: лучше показать их по
--     кругу, чем один и тот же вечно.
function Panel:Candidates()
    local cards = (ns.ActionEngine and ns.ActionEngine.cards) or {}
    for _, card in ipairs(cards) do
        if card.pinTop then return { card }, true end
    end
    local list = {}
    for _, card in ipairs(cards) do
        if card.action and card.action.kind ~= "noop" then list[#list + 1] = card end
    end
    if #list == 0 then
        for _, card in ipairs(cards) do list[#list + 1] = card end
    end
    return list, false
end

-- Совет, который панель показывает, и его место: card, index, total.
--
-- ПОКА ИГРОК НЕ ЛИСТАЛ, ПАНЕЛЬ ПОКАЗЫВАЕТ ВЕРХ СПИСКА и следует за ним: если
-- пересчёт поставил наверх другой совет, на панели окажется он. Долистал
-- «Дальше» до какого-то совета - панель остаётся на нём, пока он есть в списке
-- (по ключу, а не по номеру: ранжирование меняется при каждом пересчёте). Совет
-- пропал - продолжаем с того же номера. Вернулся по кругу на первый - панель
-- снова следует за верхом списка.
function Panel:PickCard()
    local list, pinned = self:Candidates()
    if #list == 0 then return nil, 0, 0 end
    -- Обязательный совет позицию не трогает: когда он уйдёт, игрок окажется
    -- там же, где остановился.
    if pinned then return list[1], 1, 1 end

    local index = 1
    if self.cursorKey then
        local found
        for i, card in ipairs(list) do
            if card.key == self.cursorKey then found = i; break end
        end
        if found then
            index = found
        else
            index = tonumber(self.cursorIndex) or 1
            if index < 1 or index > #list then index = 1 end
        end
    end
    self.cursorIndex = index
    self.cursorKey = (index > 1) and list[index].key or nil
    return list[index], index, #list
end

function Panel:Render()
    return ns.Diag:Guard("StepPanel:Render", Panel.RenderInner, self)
end

function Panel:RenderInner()
    if not self.frame then return end
    -- Совет выбирается ДО проверки «свёрнута ли панель»: свёрнутая панель - это
    -- одна строка с названием текущего совета, и раньше она показывала тот
    -- совет, на котором её свернули, сколько бы пересчётов ни прошло.
    local card = self:PickCard()
    self.current = card
    if ns.Config:Get().panel.collapsed then
        self.frame.header:SetText(self:CollapsedSummary())
        return
    end
    return self:RenderCard(card)
end

-- Заголовок и кнопка «Дальше» для совета, который сейчас на панели.
--
-- «Совет 2 из 5» вместо «Сейчас» - это не украшение. Игрок, нажавший «Дальше»,
-- должен видеть, что произошло: он перешёл ко второму из пяти, а первый никуда
-- не делся. Раньше после нажатия совет просто исчезал, и это читалось как
-- поломка.
function Panel:UpdateHeader(card)
    local f = self.frame
    if not f then return end
    local list, pinned = self:Candidates()
    local index
    if card and not pinned then
        for i, c in ipairs(list) do
            if c.key == card.key then index = i; break end
        end
    end
    if index and #list > 1 then
        f.header:SetText("Совет " .. index .. " из " .. #list)
        f.next:Show()
    else
        f.header:SetText("Сейчас")
        f.next:Hide()
    end
end

-- Draw one card. Split out of RenderInner so a test can hand the panel a
-- specific card instead of having to arrange a world where PickCard chooses it.
function Panel:RenderCard(card)
    local f = self.frame
    if not f then return end
    self.current = card

    if not card then
        f.spine:SetColorTexture(0.4, 0.4, 0.4, 0.9)
        f.icon:SetTexture("Interface\\Icons\\INV_Misc_PocketWatch_01")
        f.title:SetTextColor(0.8, 0.8, 0.8)
        f.benefit:SetText("")
        f.route:Hide()
        f.next:Hide()
        f.action:Hide()
        f.header:SetText("Сейчас")
        f.badge:Set(ns.CONF.UNKNOWN)

        -- «ПОКА НЕЧЕГО СОВЕТОВАТЬ» - ЭТО УТВЕРЖДЕНИЕ, И ОНО БЫВАЕТ ЛОЖНЫМ.
        --
        -- Живая жалоба: панель постоянно писала это при трёх десятках советов в
        -- окне. Панель берёт тот же список, что и окно, поэтому отсутствие
        -- карточки означает одно из трёх, и все три - разные вещи:
        --
        --   * пересчёта ещё не было. Правда, но «нечего советовать» - не те
        --     слова: игрок по ним идёт искать поломку;
        --   * пересчёт был, список правда пуст. Вот это и есть «нечего»;
        --   * список НЕ пуст, а карточка не выбралась. Это расхождение, и
        --     молчать о нём нельзя: панель показывает верх списка, а раз
        --     список есть - показывает его, и пишет о странности в файл.
        local cards = (ns.ActionEngine and ns.ActionEngine.cards) or {}
        if #cards > 0 then
            if ns.Diag then
                ns.Diag:Suspect("panel-empty-while-list-is-not", string.format(
                    "панель не нашла, что показать, а в списке %d %s —"
                    .. " показываю верх списка", #cards,
                    U.plural(#cards, "совет", "совета", "советов")),
                    { cards = #cards })
            end
            -- Не врать и не пустовать: верх списка есть, его и показываем.
            return self:RenderCard(cards[1])
        end
        local built = (ns.ActionEngine and ns.ActionEngine.buildCount) or 0
        if built == 0 then
            f.title:SetText("Ещё считаю")
            f.detail:SetText("Первый пересчёт ещё не прошёл — сейчас посчитаю"
                .. " и покажу, что делать.")
            return
        end
        -- No branch here for "the player hid everything": the engine always
        -- emits the hidden:restore card in that state, so PickCard would have
        -- returned it and this code would not be running. The window is where
        -- the reasons live, and that is what this line points at.
        f.title:SetText("Пока нечего советовать")
        f.detail:SetText("Откройте полное окно — там написано, каких данных мне не хватает.")
        return
    end

    local spine = ns.Card.SpineColor(card.kind)
    f.spine:SetColorTexture(spine[1], spine[2], spine[3], 0.95)
    f.icon:SetTexture(card.icon or ns.KIND_ICON[card.kind]
        or "Interface\\Icons\\INV_Misc_QuestionMark")

    f.benefit:SetText(card.benefit or "")
    local bc = W.benefitColor(card.benefitKind)
    f.benefit:SetTextColor(bc[1], bc[2], bc[3])

    -- ЗАГОЛОВОК - ПО МЕСТУ, А НЕ ЧЕМ ПРИДЁТСЯ. Строка стоит без переноса, и
    -- лишнее обрезал клиент - по пикселям, то есть посреди номера предмета
    -- («Предмет #2494…»). Место считается от иконки до столбца выгоды, поэтому
    -- выгода заполняется первой: без неё ширину заголовка не узнать.
    local titleRoom = (tonumber(f:GetWidth()) or 0) - 46
        - ((tonumber(f.benefit:GetStringWidth()) or 0) + 14)
    W.SetFitted(f.title, card.title or "", titleRoom)
    -- Обязательный совет золотистым, обычный белым. Красный канал раньше был
    -- написан как `card.pinTop and 1 or 1`, то есть всегда 1 - по двум соседним
    -- каналам видно, что имелось в виду. Цвет тот же, что у таких карточек в
    -- списке (UI/Card.lua), чтобы оба экрана говорили одним языком.
    if card.pinTop then
        f.title:SetTextColor(1, 0.86, 0.55)
    else
        f.title:SetTextColor(1, 1, 1)
    end

    -- The panel has room for one explanatory line, so it shows what is missing
    -- when something is missing, and why otherwise.
    local detail = card.need
    if card.plan and card.plan.ready then detail = card.why end
    f.detail:SetText(detail or card.why or "")

    f.badge:Set(card.conf)
    f.badge:Show()

    -- ОДНА КНОПКА СПРАВА, И ПОДПИСАНА ОНА ТЕМ, ЧТО СДЕЛАЕТ.
    --
    -- Три кнопки плюс значок достоверности в панель шириной 220-460 не влезают,
    -- а прятать значок достоверности нельзя - он и есть главное обещание этого
    -- аддона. Поэтому справа внизу ровно одна кнопка:
    --   * есть своё действие у совета - подписана им («Вернуть все»,
    --     «Показать предмет», «В список покупок»);
    --   * нет - «Открыть»: полное окно, где совет написан целиком.
    -- «Дальше» сюда больше не попадает - она в заголовке, у любого совета, и
    -- ничего не прячет. Спрятать совет можно только правым щелчком, и подсказка
    -- говорит об этом прямо.
    local hasOwnAction = Panel.HasOwnAction(card)
    local right = f.action
    right:Show()
    right:SetLabel(hasOwnAction and ns.Card.ActionLabel(card) or "Открыть")
    self:UpdateHeader(card)
    -- Ширина по подписи: «Дальше» и «В список покупок» разной длины, а
    -- обрезанная подпись - это снова текст, который врёт о том, что видно.
    local rightWidth = ((right.text and right.text:GetStringWidth()) or 70) + 16
    right:SetWidth(U.clamp(rightWidth, 64, 150))
    f.badge:ClearAllPoints()
    f.badge:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT", -6, 0)

    local canRoute = card.place and card.place.routable and ns.Places:CanRoute()
    local routeLabel
    if canRoute then
        -- Once the arrow is already on this place, the button turns into the
        -- live reading, so the panel doubles as a tiny status line.
        local following = ns.Arrow and ns.Arrow:HasTarget()
            and ns.Arrow.target and ns.Arrow.target.mapID == card.place.mapID
            and math.abs((ns.Arrow.target.x or 0) - (card.place.x or 0)) < 1e-6
        routeLabel = following and (ns.Arrow:Describe() or "иду") or "Показать путь"
    end
    Panel:LayoutRow(right, routeLabel)
end

-- РАСКЛАДКА НИЖНЕЙ СТРОКИ, ПОСЧИТАННАЯ, А НЕ УГАДАННАЯ.
--
-- Ширины кнопок считаются по подписям, и подписи бывают длинные: «В список
-- покупок» справа и живое показание стрелки «Тернистая долина, 420 м» слева.
-- На панели в 220 пикселей они бы наехали друг на друга и на значок
-- достоверности - то есть на экране оказалось бы три подписи поверх одной
-- другой, и ни одну нельзя прочесть.
--
-- Порядок уступок осознанный: сначала сжимается кнопка пути, потом она
-- пропадает совсем. Значок достоверности и кнопка действия не уступают
-- никогда: без первого аддон перестаёт честно говорить, чего он не знает, а
-- второй - то самое единственное дело, ради которого панель существует.
-- Место, которое занимает пропавшая кнопка пути, не теряется: само место
-- написано в строке «detail», а полный адрес - в подсказке при наведении.
Panel.ROW_PAD = 18          -- отступы по краям строки
Panel.ROW_GAP = 8           -- просвет между кнопкой пути и значком
Panel.ROUTE_MIN = 72        -- уже этого кнопка пути нечитаема
Panel.ROUTE_MAX = 170

function Panel:LayoutRow(right, routeLabel)
    local f = self.frame
    if not f then return end

    if not routeLabel then
        f.route:Hide()
        return
    end

    f.route:SetLabel(routeLabel)
    local wanted = ((f.route.text and f.route.text:GetStringWidth()) or 96) + 16
    wanted = U.clamp(wanted, Panel.ROUTE_MIN, Panel.ROUTE_MAX)

    local total = f:GetWidth() or 300
    local taken = (right:GetWidth() or 72) + (f.badge:GetWidth() or 44)
        + Panel.ROW_PAD + Panel.ROW_GAP + 6
    local room = total - taken

    if room < Panel.ROUTE_MIN then
        f.route:Hide()
        return
    end
    f.route:Show()
    f.route:SetWidth(math.min(wanted, room))
end

-- Actions ---------------------------------------------------------------

function Panel:Route()
    local card = self.current
    if not card then return end
    ns.Card.Route(card)
end

-- Кнопка справа внизу. У совета со своим действием - оно, тем же путём, что и в
-- списке (Card.Activate), так что панель и окно не могут сделать разное по
-- одной и той же кнопке. У совета без своего действия кнопка подписана
-- «Открыть» и открывает полное окно: там совет написан целиком.
function Panel:DoAction()
    local card = self.current
    if not card then return end
    -- Нажата кнопка, а не подтверждён вопрос «скрыть?»: вопрос снимается.
    ns.Card.Disarm()
    if not Panel.HasOwnAction(card) then
        ns.MainFrame:Show()
        ns.MainFrame:Select("NOW")
        return
    end
    ns.Card.Activate(card)
    -- Восстановление скрытых и покупки меняют сам список, так что панель надо
    -- перерисовать: иначе кнопка «Вернуть все» остаётся на экране после того,
    -- как возвращать стало нечего.
    Panel:Render()
end

-- «ДАЛЬШЕ»: СЛЕДУЮЩИЙ СОВЕТ ПО КРУГУ. НИЧЕГО НЕ ПРЯЧЕТ.
--
-- Раньше эта кнопка откладывала совет на час: записывала его в скрытые и
-- пересобирала список. Слово «дальше» такого не обещает, и игрок трижды остался
-- без советов - нажимал «Дальше», пока список не опустел, и решал, что аддон
-- сломан. Цена этой ошибки выше любой пользы от автоскрытия.
--
-- Теперь здесь нет ни одного обращения к скрытию: меняется только позиция
-- панели. Список советов, число скрытых и сохранённые настройки остаются ровно
-- такими, какими были; это проверяется тестом на N нажатий подряд. Возвращает
-- true, если было куда перейти.
function Panel:Advance()
    -- Игрок пошёл дальше, а не подтвердил вопрос «скрыть?»: вопрос снимается.
    ns.Card.Disarm()
    local list, pinned = self:Candidates()
    if pinned or #list < 2 then return false end
    local _, index = self:PickCard()
    index = tonumber(index) or 1
    local nextIndex = (index % #list) + 1
    self.cursorIndex = nextIndex
    -- Вернулись на первый - значит, круг пройден, и панель снова следует за
    -- верхом списка, а не держится за конкретный совет.
    self.cursorKey = (nextIndex > 1) and list[nextIndex].key or nil
    self:Render()
    return true
end

-- ПРАВЫЙ ЩЕЛЧОК ПО ПАНЕЛИ: ДВА ЩЕЛЧКА, КАК В СПИСКЕ.
--
-- Это был последний путь, которым совет исчезал от одного движения. В списке
-- правый щелчок давно требует подтверждения вторым; на панели один щелчок
-- прятал совет на час. В подсказке это было написано, но подсказку игрок не
-- читает - он кликает, и трижды остался без советов. Комментарий, стоявший
-- здесь, оправдывал один шаг тем, что «кнопка панели - осознанное нажатие»; но
-- это не кнопка, а правый щелчок по всей панели, то есть ровно тот случайный
-- щелчок, от которого защищён список.
--
-- Теперь путь тот же, что в списке, - Card.RequestDismiss: первый щелчок
-- спрашивает (и говорит об этом в чате), второй в течение нескольких секунд
-- прячет, любое другое действие вопрос снимает. Обязательный совет не прячется
-- вовсе, и отказ печатает то же место, что и для списка. Срок остаётся час:
-- панель - это «отложить», а не «убрать с глаз».
--
-- Возвращает исход: "armed", "hidden", "blocked" или "failed".
function Panel:Dismiss()
    local card = self.current
    if not card then return nil end
    local _, outcome = ns.Card.RequestDismiss(card, ns.SNOOZE_SECONDS)
    self:Render()
    return outcome
end

-- Lifecycle -------------------------------------------------------------

function Panel:OnCombat(inCombat)
    self.inCombat = inCombat and true or false
    self:ApplyVisibility()
end

function Panel:OnZone(inInstance)
    self.inInstance = inInstance and true or false
    self:ApplyVisibility()
end

function Panel:Refresh()
    self:ApplyVisibility()
    if self.frame and self.frame:IsShown() then self:Render() end
end

function Panel:SetEnabled(on)
    ns.Config:Get().panel.enabled = on and true or false
    if on then
        self:Build()
        self:ApplyVisibility()
        self:Render()
    elseif self.frame then
        self.frame:Hide()
    end
    -- The window's title bar carries a "bring the panel back" button that only
    -- exists while the panel is away, so it has to be re-evaluated here.
    if ns.MainFrame and ns.MainFrame.UpdateRestoreButton then
        ns.MainFrame:UpdateRestoreButton()
    end
end

function Panel:IsEnabled()
    local cfg = ns.Config:Get()
    return (cfg and cfg.panel.enabled) and true or false
end

-- ВКЛЮЧИТЬ И СКАЗАТЬ ПРАВДУ О РЕЗУЛЬТАТЕ.
--
-- «Панель вернул» печаталось сразу после записи настройки — а правило боя или
-- подземелья могло продолжать держать её скрытой. Игрок в подземелье получал
-- сообщение об успехе, пустой экран и исчезнувшую кнопку возврата в заголовке
-- (она привязана к настройке, а не к видимости). Поэтому сообщение сверяется
-- с тем, что на экране, и если панель всё ещё не видно, называет причину.
function Panel:TurnOn()
    self:SetEnabled(true)
    if self.frame and self.frame:IsShown() then
        ns.Api:Print("панель вернул. " .. Panel.CLOSE_HINT)
        return true
    end
    local cfg = ns.Config:Get()
    if self.inCombat and cfg.panel.combat == "hide" then
        ns.Api:Print("панель включил, но сейчас бой, а в настройках выбрано"
            .. " скрывать её в бою — появится, когда бой закончится")
    elseif self.inInstance and cfg.panel.instance == "hide" then
        ns.Api:Print("панель включил, но в настройках выбрано скрывать её"
            .. " в подземельях — появится, когда выйдете")
    else
        ns.Api:Print("панель включил, но показать её не удалось —"
            .. " посмотрите /fp diag")
    end
    return false
end

function Panel:TurnOff()
    self:SetEnabled(false)
    ns.Api:Print("панель убрана. Советы считаю по-прежнему. " .. self:HowToShow())
    return false
end

-- Единственный переключатель, которым пользуются все пути: крестик, команда,
-- Shift-щелчок по кнопке миникарты и кнопка в заголовке окна. Формулировки
-- живут в TurnOn/TurnOff, а не по одной в каждом вызывающем месте — иначе на
-- одно действие получается четыре разных сообщения, и три из них забывают
-- обновить при следующей правке.
function Panel:Toggle()
    if self:IsEnabled() then self:TurnOff() else self:TurnOn() end
    return self:IsEnabled()
end

-- КАК ВЕРНУТЬ ПАНЕЛЬ - СОБИРАЕТСЯ ПО ТОМУ, ЧТО РЕАЛЬНО ЕСТЬ.
--
-- Приём у Polestar (изучен, не скопирован - GPL-3.0): он строит эту фразу из
-- доступных путей, а не печатает один заученный. Там же видно, зачем: его
-- собственное сообщение при закрытии окна называет слэш-команду, которая на
-- геймпадном интерфейсе не регистрируется, - то есть обещает путь, которого в
-- этой конфигурации нет. Ровно та же ошибка, что и «нажмите кнопку, которой
-- нет на экране», только в чате.
--
-- Поэтому кнопка у миникарты упоминается только когда она на самом деле
-- создана, а не когда она включена в настройках.
function Panel:HowToShow()
    local ways = {}
    if ns.MinimapButton and ns.MinimapButton.button
        and ns.Config:Get().ui.minimapButton then
        ways[#ways + 1] = "Shift+щелчок по кнопке у миникарты"
    end
    ways[#ways + 1] = "команда /fp panel"
    ways[#ways + 1] = "галочка «Показывать панель» в настройках"
    return "Вернуть: " .. table.concat(ways, ", или ") .. "."
end

-- The player pressed the ✕. Routed through TurnOff like every other close, so
-- the state write and the message cannot drift apart - which is the mistake
-- Polestar made by duplicating its own close in two files.
function Panel:CloseByPlayer()
    self:TurnOff()
end

return Panel
