-- ForeverPilot / UI/TabSettings.lua
--
-- Раздел «Настройки»: вид окна, панель текущего шага, навигация, что учитывать
-- в советах и служебные кнопки.
--
-- ЗДЕСЬ ТОЛЬКО ТО, ЧТО МОЖНО ПЕРЕКЛЮЧИТЬ, И КОРОТКАЯ СТРОКА ТАМ, ГДЕ БЕЗ НЕЁ
-- НЕПОНЯТНО. Раньше раздел наполовину состоял из абзацев о том, как аддон
-- устроен и откуда берёт данные («Что эта игра мне сообщает», «Своя история
-- цен», «Чужая книга закупок»). Игрок назвал это лишним (2026-11-21); всё это
-- есть в файле диагностики (/fp diag).
--
-- Широкое окно - две колонки, узкое - одна.
local ADDON, ns = ...

local U = ns.Util
local W = ns.Widgets

local Tab = {}
ns.TabSettings = Tab

Tab.PAD = 24
Tab.COL_GAP = 40
Tab.TWO_COL_MIN = 700
Tab.COL_MAX = 480
Tab.CHECK_H = 26
Tab.BUTTON_H = 26
Tab.SLOT_COL = 210           -- где стоит слот в строке «категория чар - слот»

local SLOT_CHOICES = {
    "HEAD", "NECK", "SHOULDER", "BACK", "CHEST", "WRIST", "HANDS",
    "WAIST", "LEGS", "FEET", "MAINHAND", "OFFHAND", "SHIELD", "RANGED", "NONE",
}

function Tab:Build(parent)
    if self.frame then return self.frame end
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)
    self.frame = frame

    local scroll, content = W.ScrollArea(frame)
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", Tab.PAD, -16)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -Tab.PAD, 14)
    self.scroll, self.content = scroll, content
    self.pool = {}
    return frame
end

function Tab:Widget(kind, index, builder)
    local key = kind .. index
    local w = self.pool[key]
    if w then w:Show(); return w end
    w = builder()
    self.pool[key] = w
    return w
end

-- Ширина содержимого и колонок - от размера окна, а не от того, успел ли
-- клиент разложить рамки.
function Tab:Columns()
    local hostW = ns.MainFrame:HostNow()
    local width = math.max(260, hostW - 2 * Tab.PAD - 14)
    if width >= Tab.TWO_COL_MIN then
        local col = math.min(Tab.COL_MAX, math.floor((width - Tab.COL_GAP) / 2))
        return width, { { x = 0, w = col, y = 0 }, { x = col + Tab.COL_GAP, w = col, y = 0 } }
    end
    return width, { { x = 0, w = math.min(Tab.COL_MAX, width), y = 0 } }
end

function Tab:Render()
    if not self.frame then return end
    for _, w in pairs(self.pool) do w:Hide() end
    local T = W.THEME

    local cfg = ns.Config:Get()
    local width, cols = self:Columns()
    -- Колонка, в которую сейчас ставятся строки. В узком окне она одна.
    local cur = cols[1]
    local counters = { head = 0, stat = 0, note = 0, check = 0, radio = 0, slider = 0,
                       button = 0, slot = 0 }
    local function take(kind, builder)
        counters[kind] = counters[kind] + 1
        return self:Widget(kind, counters[kind], builder)
    end

    local function place(w, h, gapBefore)
        w:ClearAllPoints()
        w:SetPoint("TOPLEFT", self.content, "TOPLEFT", cur.x, -(cur.y + (gapBefore or 0)))
        cur.y = cur.y + (gapBefore or 0) + h
    end
    local function head(text)
        local w = take("head", function() return W.SectionHeader(self.content, "", cur.w) end)
        w:SetWidth(cur.w)
        w.text:SetText(text)
        place(w, 26 + 8, (cur.y > 0) and 16 or 0)
    end
    local function stat(label, value, tone)
        local w = take("stat", function() return W.StatRow(self.content, "", "", cur.w) end)
        w:SetWidth(cur.w)
        local c = (tone == "warn" and T.warn) or (tone == "good" and T.good) or T.text
        w.value:SetTextColor(c[1], c[2], c[3])
        -- Нет значения - «не знаю», а не прочерк: см. ns.VOID в Core/Const.lua.
        w:SetBoth(label, value or U.void(ns.VOID.UNKNOWN))
        place(w, W.STAT_H)
    end
    local function note(text, tone)
        local w = take("note", function()
            local fs = W.Label(self.content, "", W.FONT_SMALL)
            fs:SetJustifyH("LEFT")
            return fs
        end)
        local c = (tone == "warn" and T.warn) or T.muted
        w:SetTextColor(c[1], c[2], c[3])
        local h = W.SetWrapped(w, text, cur.w, W.LINE)
        place(w, h + 8, 2)
    end
    local function check(label, value, onToggle)
        local w = take("check", function() return W.Checkbox(self.content, "", nil) end)
        w:SetWidth(cur.w)
        w.label:SetText(label)
        w:SetChecked(value)
        w:SetScript("OnClick", function(self2)
            self2:SetChecked(not self2.checked)
            onToggle(self2.checked)
        end)
        place(w, Tab.CHECK_H)
    end
    -- Один из нескольких. Щелчок по уже выбранному ничего не меняет.
    local function radio(label, isOn, onPick)
        local w = take("radio", function() return W.Radio(self.content, "", nil) end)
        w:SetWidth(cur.w)
        w.label:SetText(label)
        w:SetChecked(isOn)
        w:SetScript("OnClick", function() onPick() end)
        place(w, Tab.CHECK_H)
    end
    local function button(label, onClick, minWidth)
        local w = take("button", function()
            return W.Button(self.content, "", 180, Tab.BUTTON_H, nil)
        end)
        w:SetLabel(label)
        w:Resize(U.clamp((tonumber(w.text:GetStringWidth()) or 150) + 28,
            minWidth or 150, cur.w), Tab.BUTTON_H)
        w:SetScript("OnClick", onClick)
        place(w, Tab.BUTTON_H, 6)
        return w
    end

    -- Вид окна -----------------------------------------------------------
    head("Вид окна")
    local slider = take("slider", function()
        return W.Slider(self.content, "Масштаб окна", 0.70, 1.60, 0.05, function(v)
            ns.Config:SetScale(v)
            ns.MainFrame:ApplyScale()
        end)
    end)
    slider:SetValue(ns.Config:Scale())
    place(slider, 52)

    check("Показывать подсказки при наведении", cfg.ui.tooltips, function(on)
        cfg.ui.tooltips = on
    end)
    check("Кнопка у миникарты", cfg.ui.minimapButton, function(on)
        cfg.ui.minimapButton = on
        ns.MainFrame:ApplyMinimapButton()
    end)
    -- Сбрасывается и РАЗМЕР тоже. Кнопка и команда /fp reset делали разное:
    -- команда возвращала размер, а кнопка — только координаты, и растянутое
    -- окно оставалось растянутым. Одно название, два поведения.
    button("Сбросить позицию и размер окна", function()
        ns.Config:SaveFrame("CENTER", "CENTER", 0, 0, 720, 560)
        ns.MainFrame:ApplyPosition()
    end)
    button("Вернуть кнопку миникарты на место", function()
        ns.Config:SetMinimapAngle(
            (ns.MinimapButton and ns.MinimapButton.DEFAULT_ANGLE) or 135)
        ns.MainFrame:ApplyMinimapButton()
    end)

    -- Панель текущего шага -------------------------------------------------
    head("Панель текущего шага")
    -- Через те же TurnOn/TurnOff, что и все остальные пути: галочка раньше была
    -- единственным путём, который молчал в чат, а в подземелье ещё и выглядела
    -- сломанной — поставил, и ничего не появилось без объяснений.
    check("Показывать панель", cfg.panel.enabled, function(on)
        if on then ns.StepPanel:TurnOn() else ns.StepPanel:TurnOff() end
        Tab:Render()
    end)

    -- ВЫКЛЮЧЕННАЯ ПАНЕЛЬ НЕ ПОКАЗЫВАЕТ СВОИХ НАСТРОЕК: контрол, который виден и
    -- ничего не делает, выглядит точно так же, как сломанный.
    if cfg.panel.enabled then
        check("Свернуть панель", cfg.panel.collapsed, function()
            ns.StepPanel:ToggleCollapsed()
        end)
        check("Закрепить (не перетаскивать)", cfg.panel.locked, function(on)
            cfg.panel.locked = on
        end)
        for _, opt in ipairs({
            { "show", "В бою: показывать как обычно" },
            { "fade", "В бою: приглушить" },
            { "hide", "В бою: скрыть" },
        }) do
            radio(opt[2], cfg.panel.combat == opt[1], function()
                cfg.panel.combat = opt[1]
                ns.StepPanel:ApplyVisibility()
                Tab:Render()
            end)
        end
        check("Скрывать в подземельях", cfg.panel.instance == "hide", function(on)
            cfg.panel.instance = on and "hide" or "show"
            ns.StepPanel:ApplyVisibility()
        end)
        button("Вернуть панель на место", function()
            ns.StepPanel:ResetPosition()
        end)
    end

    -- Навигация ----------------------------------------------------------
    head("Навигация")
    local places = ns.Places:Summary()
    for _, opt in ipairs({
        { "own", "Своя стрелка" },
        { "tomtom", "Отдавать точку аддону TomTom" },
        { "off", "Выключить навигацию" },
    }) do
        local label = opt[2]
        if opt[1] == "tomtom" and not places.tomtom then
            label = label .. " (не установлен)"
        end
        radio(label, cfg.nav.provider == opt[1], function()
            cfg.nav.provider = opt[1]
            if opt[1] ~= "own" then ns.Arrow:Clear() end
            ns.MainFrame:Rebuild(true)
            Tab:Render()
        end)
    end
    check("Закрепить стрелку (не перетаскивать)", cfg.nav.locked, function(on)
        cfg.nav.locked = on
    end)
    check("Убирать стрелку в бою", cfg.nav.hideInCombat, function(on)
        cfg.nav.hideInCombat = on
    end)
    button("Вернуть стрелку на место", function() ns.Arrow:ResetPosition() end)
    button("Убрать стрелку", function() ns.Arrow:Clear() end)
    note("Стрелка показывает направление по прямой и расстояние. Торговцы и"
        .. " тренеры попадают в список мест, когда вы к ним подходите.")

    -- Когда писать в чат ---------------------------------------------------
    --
    -- Три повода сказать что-то в чат по своей инициативе, и каждый
    -- выключается отдельно. Выключается СООБЩЕНИЕ, а не работа.
    head("Когда писать мне в чат")
    cfg.notify = cfg.notify or {}
    check("Про выгодную сделку, пока вы у аукциона",
        cfg.notify.auctionDeals ~= false, function(on)
        cfg.notify.auctionDeals = on
    end)
    check("Когда поднимется потолок навыка",
        cfg.notify.skillCap ~= false, function(on)
        cfg.notify.skillCap = on
    end)
    check("Когда цены старше суток",
        cfg.notify.stalePrices ~= false, function(on)
        cfg.notify.stalePrices = on
    end)

    -- Дальше - вторая колонка (в узком окне - та же, продолжением).
    if cols[2] then cur = cols[2] end

    -- Что учитывать --------------------------------------------------------
    head("Что учитывать в советах")
    check("Считать материалы в банке", cfg.show.includeBank, function(on)
        cfg.show.includeBank = on
        ns.MainFrame:Rebuild(true)
    end)
    check("Считать материалы у других персонажей", cfg.show.includeOtherChars, function(on)
        cfg.show.includeOtherChars = on
        ns.MainFrame:Rebuild(true)
    end)
    check("Не предлагать серые рецепты ради навыка", cfg.show.hideTrivialSkill, function(on)
        cfg.show.hideTrivialSkill = on
        ns.MainFrame:Rebuild(true)
    end)
    check("Не проверять, подходит ли броня классу", cfg.show.skipClassCheck, function(on)
        cfg.show.skipClassCheck = on
        ns.MainFrame:Rebuild(true)
    end)

    -- МЕЛКАЯ ДЕНЕЖНАЯ ВЫГОДА ------------------------------------------
    --
    -- Порог, полосы и числа видны здесь целиком, и ни одно из них не зашито
    -- намертво: игрок может сменить полосу на своё число или снять порог вовсе.
    -- Числа берутся из ns.MONEY_FLOOR_BANDS, а действующий порог - из
    -- Config:MoneyFloor, то есть из того же места, которым отсеивает движок.
    head(ns.ActionEngine.MONEY_FLOOR_SECTION)
    note("Денежные советы с выгодой меньше порога в список не попадают."
        .. " Экипировки, чар и навыка порог не касается.")
    local who = ns.CharacterScanner:Get()
    local myLevel = who and who.level or nil
    local floorMode = ns.Config:MoneyFloorMode()
    for _, opt in ipairs({
        { ns.MONEY_FLOOR_MODE.LEVEL, "По уровню персонажа" },
        { ns.MONEY_FLOOR_MODE.FIXED, "Одно моё число на все уровни" },
        { ns.MONEY_FLOOR_MODE.OFF, "Показывать любую выгоду, даже в пару медяков" },
    }) do
        radio(opt[2], floorMode == opt[1], function()
            ns.Config:SetMoneyFloorMode(opt[1])
            ns.MainFrame:Rebuild(true)
            Tab:Render()
        end)
    end
    if floorMode == ns.MONEY_FLOOR_MODE.LEVEL then
        local myBand = ns.Config:MoneyFloorBand(myLevel)
        for _, band in ipairs(ns.MONEY_FLOOR_BANDS) do
            stat(band.label .. ((band == myBand) and " — вы здесь" or ""),
                "от " .. U.money(band.copper), (band == myBand) and "good" or nil)
        end
    elseif floorMode == ns.MONEY_FLOOR_MODE.FIXED then
        -- Лестница, а не ползунок: ползунок печатал бы «20.00», и это не деньги.
        -- Тот же приём, что у категорий чар ниже, - нажатие берёт следующее.
        button("Моё число: " .. U.money(ns.Config:MoneyFloorOwn())
            .. " — нажмите, чтобы взять следующее", function()
            local now = ns.Config:MoneyFloorOwn()
            local list = ns.MONEY_FLOOR_CHOICES
            local idx = 1
            for i, v in ipairs(list) do
                if v == now then idx = i; break end
            end
            ns.Config:SetMoneyFloorOwn(list[(idx % #list) + 1])
            ns.MainFrame:Rebuild(true)
            Tab:Render()
        end, 330)
    end
    -- Скобки вокруг вызова обязательны: Config:MoneyFloor возвращает НЕСКОЛЬКО
    -- значений, и без них второе уехало бы в tonumber как основание счисления.
    local floorNow = tonumber((ns.Config:MoneyFloor(myLevel))) or 0
    if floorNow > 0 then
        stat("Сейчас порог", U.money(floorNow))
    else
        stat("Сейчас порог", "снят", "good")
    end

    -- Веса характеристик ---------------------------------------------------
    head("Веса характеристик")
    local snap = ns.CharacterScanner:Get()
    -- СПРАШИВАТЬ У СНИМКА, А НЕ СЧИТАТЬ ЗАНОВО: снимок - тот самый ответ, по
    -- которому считаются советы. Повторный вызов StatWeights:Active без снимка
    -- давал здесь другой ответ, чем на карточках.
    local activeKey = snap and snap.weightSetKey
    if not activeKey then
        local _, key = ns.StatWeights:Active(snap and snap.classFile,
            snap and snap.spec, snap)
        activeKey = key
    end
    stat("Сейчас используется", ns.StatWeights.SET_LABEL[activeKey] or activeKey)
    note("По весам считается, какая вещь лучше. Ничего не выбрано — определяю"
        .. " сам по классу и специализации.")
    local charDB = ns.Config:Char()
    -- ВЫБРАТЬ РУКАМИ МОЖНО ЛЮБОЙ НАБОР, ВКЛЮЧАЯ ШКОЛЬНЫЕ. Порядок берётся из
    -- явного списка ключей, чтобы экран не зависел от порядка обхода таблицы.
    -- Повторный щелчок по выбранному снимает выбор.
    for _, key in ipairs(ns.StatWeights.OVERRIDE_ORDER) do
        radio(ns.StatWeights.SET_LABEL[key] or key, charDB.statWeightOverride == key,
            function()
                charDB.statWeightOverride = (charDB.statWeightOverride ~= key) and key or nil
                ns.MainFrame:Rebuild(true)
                Tab:Render()
            end)
    end

    -- Чары: слот категории -------------------------------------------------
    local cats = ns.RecipeBook:EnchantCategories()
    if #cats > 0 then
        head("Чары: какой слот у какой категории")
        note("Слот не тот — нажмите на строку, он сменится на следующий.")
        for _, cat in ipairs(cats) do
            local w = take("slot", function()
                local btn = CreateFrame("Button", nil, self.content)
                btn:SetHeight(W.STAT_H)
                btn.label = W.Label(btn, "", W.FONT_SMALL, T.muted[1], T.muted[2], T.muted[3])
                btn.label:SetPoint("LEFT", 0, 0)
                btn.label:SetWordWrap(false)
                btn.value = W.Label(btn, "", W.FONT_SMALL, T.text[1], T.text[2], T.text[3])
                btn.value:SetPoint("LEFT", btn, "LEFT", Tab.SLOT_COL, 0)
                btn.value:SetWordWrap(false)
                btn:SetScript("OnEnter", function(s)
                    s.label:SetTextColor(T.accent[1], T.accent[2], T.accent[3])
                end)
                btn:SetScript("OnLeave", function(s)
                    s.label:SetTextColor(T.muted[1], T.muted[2], T.muted[3])
                end)
                return btn
            end)
            w:SetWidth(cur.w)
            W.SetFitted(w.label, cat.categoryName or "?", Tab.SLOT_COL - 12)
            local current = cat.slot
            local c = current and T.text or T.warn
            w.value:SetTextColor(c[1], c[2], c[3])
            W.SetFitted(w.value, (current and ns.SlotMap:Label(current) or "не определён")
                .. (cat.override and " (выбрано вами)" or ""), cur.w - Tab.SLOT_COL)
            local catID = cat.categoryID
            w:SetScript("OnClick", function()
                local idx = 0
                for i, s in ipairs(SLOT_CHOICES) do
                    if s == (ns.Config:EnchantSlot(catID) or current) then idx = i; break end
                end
                local nextSlot = SLOT_CHOICES[(idx % #SLOT_CHOICES) + 1]
                ns.Config:SetEnchantSlot(catID, nextSlot)
                ns.MainFrame:Rebuild(true)
                Tab:Render()
            end)
            place(w, W.STAT_H)
        end
    end
    local unmapped = ns.EnchantAdvisor:Unmapped()
    if #unmapped > 0 then
        note("Без слота: " .. #unmapped .. " "
            .. U.plural(#unmapped, "категория", "категории", "категорий")
            .. " чар. Формулы из них в советы не попадают, пока слот не назначен.", "warn")
    end

    -- Аддоны-помощники -----------------------------------------------------
    head("Аддоны-помощники")
    if ns.Api:AuctionatorPresent() then
        stat("Auctionator", "есть", "good")
    else
        stat("Auctionator", "нет — без него не знаю цен", "warn")
    end
    if ns.Api:SyndicatorPresent() then
        stat("Syndicator", "есть", "good")
    else
        stat("Syndicator", "нет — вижу только свои сумки", "warn")
    end

    -- СВОЯ КНИГА ЗАКУПОК ------------------------------------------------
    if ns.Ledger then
        head("Книга закупок")
        local rep = ns.Ledger:Report()
        stat("Записано покупок", tostring(rep.entries))
        stat("Предметов с ценой покупки", tostring(rep.items))
        note("Здесь записано, за сколько вы покупали материалы: по этим ценам"
            .. " точнее считается, ниже какой цены не продавать.")
        -- НЕОБРАТИМОЕ - В ДВА НАЖАТИЯ, тем же приёмом, что у списка покупок.
        button(Tab.ledgerArmed and "Точно стереть книгу — нажмите ещё раз"
            or "Стереть свою книгу закупок", function()
            if not Tab.ledgerArmed then
                Tab.ledgerArmed = true
                ns.Api:Print("сотру книгу закупок — нажмите ту же кнопку ещё раз."
                    .. " Вернуть её будет нельзя: эти записи нигде больше не"
                    .. " хранятся.")
                Tab:Render()
                local timer = _G.C_Timer
                if type(timer) == "table" and type(timer.After) == "function" then
                    timer.After(6, function()
                        Tab.ledgerArmed = nil
                        if Tab.frame and Tab.frame:IsShown() then Tab:Render() end
                    end)
                end
                return
            end
            Tab.ledgerArmed = nil
            local n = ns.Config:ClearLedger()
            ns.Api:Print("книга закупок стёрта, записей было " .. n)
            ns.MainFrame:Rebuild(true)
            Tab:Render()
        end, 250)
    end

    -- Служебное ----------------------------------------------------------
    head("Служебное")
    stat("Версия", ns.VERSION)
    button("Пересчитать сейчас", function() ns.MainFrame:Rebuild(true) end)
    -- Через ту же Card.RestoreHidden, что и кнопка в шапке списка и команда
    -- /fp show: одно действие - одно сообщение.
    button("Вернуть все скрытые советы", function()
        ns.Card.RestoreHidden()
    end)
    -- НЕОБРАТИМОЕ - В ДВА НАЖАТИЯ. Первое нажатие только спрашивает, и кнопка
    -- на время вопроса сама меняет подпись - игрок, который не читает чат,
    -- видит это на ней самой. Решает ShoppingList:RequestClear; здесь только
    -- слова и перерисовка.
    local clearArmed = ns.ShoppingList:ClearArmed()
    button(clearArmed and "Точно очистить — нажмите ещё раз"
        or "Очистить мой список покупок", function()
        local outcome, message = ns.ShoppingList:RequestClear()
        if message then ns.Api:Print(message) end
        if outcome == "cleared" then ns.MainFrame:Rebuild(true) end
        Tab:Render()
        if outcome == "armed" then
            -- Вопрос живёт несколько секунд. Когда срок выйдет, подпись обязана
            -- вернуться сама: иначе кнопка обещает «нажмите ещё раз — очищу»,
            -- а нажатие только спросит заново.
            local timer = _G.C_Timer
            if type(timer) == "table" and type(timer.After) == "function" then
                timer.After(ns.ShoppingList.CLEAR_CONFIRM_SECONDS + 0.2, function()
                    if Tab.frame and Tab.frame:IsShown() then Tab:Render() end
                end)
            end
        end
    end, 250)
    note("Файл диагностики со всеми подробностями — команда /fp diag.")

    local tallest = 0
    for _, col in ipairs(cols) do tallest = math.max(tallest, col.y) end
    self.content:SetSize(width, math.max(1, tallest + 10))
    self.scroll:Refresh()
end

function Tab:OnShow() Tab:Render() end

return Tab
