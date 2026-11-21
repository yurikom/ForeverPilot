-- ForeverPilot / UI/TabSettings.lua
--
-- Settings, plus the honest diagnostics: which game functions this client
-- actually gave us, and which enchant categories we had to guess a slot for.
-- The guesses are editable here, because a wrong guess is better fixed once by
-- the player than argued with forever.
local ADDON, ns = ...

local U = ns.Util
local W = ns.Widgets

local Tab = {}
ns.TabSettings = Tab

Tab.PAD = 12

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
    scroll:SetPoint("TOPLEFT", Tab.PAD, -Tab.PAD)
    scroll:SetPoint("BOTTOMRIGHT", -(Tab.PAD + 22), Tab.PAD)
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

function Tab:Render()
    if not self.frame then return end
    for _, w in pairs(self.pool) do w:Hide() end

    local cfg = ns.Config:Get()
    local width = (self.scroll:GetWidth() or 620) - 8
    local y = 0
    local counters = { head = 0, stat = 0, note = 0, check = 0, slider = 0, button = 0, slot = 0 }

    local function place(w, h)
        w:ClearAllPoints()
        w:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -y)
        y = y + h
    end
    local function head(text)
        counters.head = counters.head + 1
        local w = self:Widget("head", counters.head, function()
            return W.SectionHeader(self.content, "", width)
        end)
        w:SetWidth(width); w.text:SetText(text); place(w, 28)
    end
    local function stat(label, value)
        counters.stat = counters.stat + 1
        local w = self:Widget("stat", counters.stat, function()
            return W.StatRow(self.content, "", "", width)
        end)
        -- Нет значения - «не знаю», а не прочерк: см. ns.VOID в Core/Const.lua.
        w:SetWidth(width); w.label:SetText(label)
        w.value:SetText(value or U.void(ns.VOID.UNKNOWN))
        place(w, 18)
    end
    local function note(text)
        counters.note = counters.note + 1
        local w = self:Widget("note", counters.note, function()
            local fs = W.Label(self.content, "", W.FONT_SMALL, 0.58, 0.58, 0.58)
            fs:SetWordWrap(true); fs:SetJustifyH("LEFT")
            return fs
        end)
        w:SetWidth(width); w:SetText(text)
        place(w, math.max(14, (w:GetStringHeight() or 12) + 6))
    end
    local function check(label, value, onToggle)
        counters.check = counters.check + 1
        local w = self:Widget("check", counters.check, function()
            return W.Checkbox(self.content, "", nil)
        end)
        w:SetWidth(width)
        w.label:SetText(label)
        w:SetChecked(value)
        w:SetScript("OnClick", function(self2)
            self2:SetChecked(not self2.checked)
            onToggle(self2.checked)
        end)
        place(w, 22)
    end
    local function button(label, onClick, btnWidth)
        counters.button = counters.button + 1
        local w = self:Widget("button", counters.button, function()
            return W.Button(self.content, "", btnWidth or 180, 22, nil)
        end)
        w:SetWidth(btnWidth or 180)
        w:SetLabel(label)
        w:SetScript("OnClick", onClick)
        place(w, 28)
    end

    -- Appearance -------------------------------------------------------
    head("Внешний вид")
    counters.slider = counters.slider + 1
    local slider = self:Widget("slider", counters.slider, function()
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
    note("Кнопку можно таскать мышью по краю миникарты — место запоминается.")
    -- Сбрасывается и РАЗМЕР тоже. Кнопка и команда /fp reset делали разное:
    -- команда возвращала 720x560, а кнопка — только координаты, и растянутое
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

    -- Compact panel ----------------------------------------------------
    head("Панель текущего шага")
    -- Описание — только когда панель есть. Иначе строка рассказывает про «✕ в
    -- её углу» у панели, которой на экране нет, и спорит с соседней строкой
    -- «Панель убрана».
    if cfg.panel.enabled then
        note("Маленькая панель всегда на экране: один верхний совет, кнопка пути"
            .. " и кнопка самого совета. Щелчок по панели открывает это окно,"
            .. " а кнопка " .. ns.GLYPH.CLOSE
            .. " в её правом верхнем углу убирает её.")
    end
    -- Через те же TurnOn/TurnOff, что и все остальные пути: галочка раньше была
    -- единственным путём, который молчал в чат, а в подземелье ещё и выглядела
    -- сломанной — поставил, и ничего не появилось без объяснений.
    check("Показывать панель", cfg.panel.enabled, function(on)
        if on then ns.StepPanel:TurnOn() else ns.StepPanel:TurnOff() end
        Tab:Render()
    end)

    -- ВЫКЛЮЧЕННАЯ ПАНЕЛЬ НЕ ПОКАЗЫВАЕТ СВОИХ НАСТРОЕК.
    --
    -- Все галочки ниже управляют панелью, которой нет на экране: щёлкаешь — и
    -- ничего не происходит. Контрол, который виден и ничего не делает, выглядит
    -- точно так же, как сломанный. Поэтому их просто нет, пока панель убрана, а
    -- вместо них одна строка, объясняющая, куда они делись.
    if not cfg.panel.enabled then
        note("Панель убрана, поэтому остальные её настройки спрятаны —"
            .. " управлять нечем. Поставьте галочку выше, и они вернутся."
            .. " То же делает команда /fp panel.")
    else
    check("Свернуть панель", cfg.panel.collapsed, function()
        ns.StepPanel:ToggleCollapsed()
    end)
    check("Закрепить (не перетаскивать)", cfg.panel.locked, function(on)
        cfg.panel.locked = on
    end)
    -- Здесь была галочка «Меньше анимации». Она управляла ровно одной вещью -
    -- анимацией «готово», которую проигрывала «Дальше», прежде чем спрятать
    -- совет. «Дальше» больше ничего не прячет и анимации у неё нет, так что
    -- галочка осталась бы на экране и не делала ничего. Настройка, которая
    -- ничего не меняет, - тот же мусор, что и текст про кнопку, которой нет.
    for _, opt in ipairs({
        { "show", "В бою: показывать как обычно" },
        { "fade", "В бою: приглушить" },
        { "hide", "В бою: скрыть" },
    }) do
        local isOn = (cfg.panel.combat == opt[1])
        check((isOn and ns.GLYPH.RADIO_ON or ns.GLYPH.RADIO_OFF) .. opt[2], isOn, function()
            cfg.panel.combat = opt[1]
            ns.StepPanel:ApplyVisibility()
            Tab:Render()
        end)
    end
    local hideInInstance = (cfg.panel.instance == "hide")
    check("Скрывать в подземельях", hideInInstance, function(on)
        cfg.panel.instance = on and "hide" or "show"
        ns.StepPanel:ApplyVisibility()
    end)
    note("Правила боя и подземелий не трогают саму галочку «Показывать панель»"
        .. " — выйдя из боя, вы получите ровно то состояние, которое выбрали.")
    button("Вернуть панель на место", function()
        ns.StepPanel:ResetPosition()
    end)
    end

    -- Navigation -------------------------------------------------------
    head("Навигация")
    local places = ns.Places:Summary()
    for _, opt in ipairs({
        { "own", "Своя стрелка (ничего не нужно устанавливать)" },
        { "tomtom", "Отдавать точку TomTom" },
        { "off", "Выключить навигацию" },
    }) do
        local isOn = (cfg.nav.provider == opt[1])
        local label = opt[2]
        if opt[1] == "tomtom" and not places.tomtom then
            label = label .. "  |cff808080(TomTom не загружен)|r"
        end
        check((isOn and ns.GLYPH.RADIO_ON or ns.GLYPH.RADIO_OFF) .. label, isOn, function()
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

    stat("Направление взгляда", places.hasFacing
        and "|cff60c060игра сообщает|r"
        or "|cffffcc40игра не сообщает — вместо стрелки будет направление по карте|r")
    stat("Записано мест", places.npcs .. ", из них с координатами " .. places.routable)
    stat("Торговцы по предметам", tostring(places.items))
    stat("Тренеры", tostring(places.trainers))
    note("Координаты я записываю сам, когда вы открываете торговца или тренера."
        .. " Готовую базу координат из другого аддона прочитать нельзя: она лежит"
        .. " в его приватной области, недоступной извне. Поэтому в первый запуск"
        .. " маршрутов нет, и они появляются по мере игры.")
    note("Стрелка показывает направление по прямой и расстояние. Это не"
        .. " прокладка маршрута: обойти скалу она не подскажет. Если цель в"
        .. " другой зоне, стрелки не будет — будет зона и координаты текстом.")

    -- What counts ------------------------------------------------------
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
    note("Проверка брони по классу — моё собственное правило, а не данные клиента."
        .. " Если оно ошибается, выключите его: тогда я буду предлагать надеть всё,"
        .. " что подходит по уровню.")

    -- МЕЛКАЯ ДЕНЕЖНАЯ ВЫГОДА ------------------------------------------
    --
    -- Порог, полосы и числа видны здесь целиком, и ни одно из них не зашито
    -- намертво: игрок может сменить полосу на своё число или снять порог вовсе.
    -- Числа берутся из ns.MONEY_FLOOR_BANDS, а действующий порог - из
    -- Config:MoneyFloor, то есть из того же места, которым отсеивает движок.
    -- Второго ответа на вопрос «какой сейчас порог» в аддоне нет.
    head(ns.ActionEngine.MONEY_FLOOR_SECTION)
    note("Мелкий денежный выигрыш — вода: строку он занимает, а идти за ним не"
        .. " стоит. Поэтому денежные советы, которые дают меньше порога, я в"
        .. " список не ставлю — но и не съедаю молча: над списком пишу, сколько"
        .. " их и какой был самый крупный из убранных. Порог касается только"
        .. " денег: советы про экипировку, чары и прокачку навыка он не трогает,"
        .. " их выгода не в золоте.")
    local who = ns.CharacterScanner:Get()
    local myLevel = who and who.level or nil
    local floorMode = ns.Config:MoneyFloorMode()
    for _, opt in ipairs({
        { ns.MONEY_FLOOR_MODE.LEVEL, "По уровню персонажа: чем выше уровень, тем выше порог" },
        { ns.MONEY_FLOOR_MODE.FIXED, "Одно моё число на все уровни" },
        { ns.MONEY_FLOOR_MODE.OFF, "Показывать любую денежную выгоду, даже в пару медяков" },
    }) do
        local isOn = (floorMode == opt[1])
        check((isOn and ns.GLYPH.RADIO_ON or ns.GLYPH.RADIO_OFF) .. opt[2], isOn, function()
            ns.Config:SetMoneyFloorMode(opt[1])
            ns.MainFrame:Rebuild(true)
            Tab:Render()
        end)
    end
    local myBand = ns.Config:MoneyFloorBand(myLevel)
    for _, band in ipairs(ns.MONEY_FLOOR_BANDS) do
        stat(band.label .. ((band == myBand) and "  |cff60c060(ваша полоса)|r" or ""),
            "от " .. U.money(band.copper))
    end
    if floorMode == ns.MONEY_FLOOR_MODE.FIXED then
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
    -- ПОДПИСЬ МЕНЯЕТСЯ ВМЕСТЕ СО ЗНАЧЕНИЕМ. «Не показываю советы ниже: порога
    -- нет» - это строка, которая спорит сама с собой; при снятом пороге вопрос
    -- другой, и назван он по-другому.
    -- Скобки вокруг вызова обязательны: Config:MoneyFloor возвращает НЕСКОЛЬКО
    -- значений, и без них второе уехало бы в tonumber как основание счисления.
    local floorNow = tonumber((ns.Config:MoneyFloor(myLevel))) or 0
    if floorNow > 0 then
        stat("Сейчас не показываю денежные советы ниже", U.money(floorNow))
    else
        stat("Сейчас порог", "|cff60c060снят — показываю любую денежную выгоду|r")
    end
    local cut = (ns.ActionEngine.meta or {}).moneyFloorDropped or 0
    if cut > 0 then
        stat("Убрано на прошлом пересчёте", cut .. " "
            .. U.plural(cut, "совет", "совета", "советов"))
    end

    -- Notifications ----------------------------------------------------
    --
    -- Три повода сказать что-то в чат по своей инициативе, и каждый
    -- выключается отдельно. Главное, что здесь написано словами: выключается
    -- СООБЩЕНИЕ, а не работа. Выключатель, который втихую отключал бы расчёт,
    -- был бы тем же самым тихим поведением, от которого игрок уже пострадал.
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
    note("Выключается сообщение, а не работа: карточки, пересчёт и запись цен"
        .. " идут при любой галочке. Про сделку говорю не больше одного раза за"
        .. " посещение аукциона, про один и тот же подъём потолка — один раз.")

    -- Stat weights -----------------------------------------------------
    head("Веса характеристик")
    local snap = ns.CharacterScanner:Get()
    -- СПРАШИВАТЬ У СНИМКА, А НЕ СЧИТАТЬ ЗАНОВО.
    --
    -- Здесь стоял повторный вызов StatWeights:Active БЕЗ снимка - а именно
    -- снимок включает вывод школы по надетым вещам. Поэтому раздел настроек
    -- мог показывать «школа не определена» в тот момент, когда все карточки
    -- считались по школе, выведенной из вещей: два разных ответа на один
    -- вопрос на двух экранах. Снимок - тот самый ответ, по которому считаются
    -- советы, поэтому берём его.
    local activeKey = snap and snap.weightSetKey
    local wConf = snap and snap.weightConf
    if not activeKey then
        local _, key, conf = ns.StatWeights:Active(snap and snap.classFile,
            snap and snap.spec, snap)
        activeKey, wConf = key, conf
    end
    stat("Сейчас используется", (ns.StatWeights.SET_LABEL[activeKey] or activeKey)
        .. "  |cff808080(" .. (ns.CONF_LABEL[wConf] or "?") .. ")|r")
    local charDB = ns.Config:Char()
    -- ВЫБРАТЬ РУКАМИ МОЖНО ЛЮБОЙ НАБОР, ВКЛЮЧАЯ ШКОЛЬНЫЕ.
    --
    -- Список был из пяти «ролей», а школьных наборов (тайный, огонь, лёд, тень,
    -- природа) в нём не было вовсе - при том что именно по школе считается
    -- главная характеристика кастера. Если автоопределение промахнулось - а оно
    -- выводит школу по надетым вещам, то есть по улике, а не по факту, -
    -- исправить его было нечем. Порядок берётся из ns.StatWeights.SETS через
    -- явный список ключей, чтобы экран не зависел от порядка обхода таблицы.
    for _, key in ipairs(ns.StatWeights.OVERRIDE_ORDER) do
        local label = ns.StatWeights.SET_LABEL[key] or key
        local isOn = (charDB.statWeightOverride == key)
        check((isOn and ns.GLYPH.RADIO_ON or ns.GLYPH.RADIO_OFF) .. label, isOn, function()
            charDB.statWeightOverride = (charDB.statWeightOverride == key) and nil or key
            ns.MainFrame:Rebuild(true)
            Tab:Render()
        end)
    end
    -- ЧТО ИДЁТ В БАЛЛ - ИЗ АКТИВНОГО НАБОРА, А НЕ ВПИСАНО.
    --
    -- Здесь стояло «для вашего класса в балл идут интеллект, сила магии и дух, а
    -- сила не идёт вовсе» - перечисление кастерских характеристик, выданное за
    -- характеристики «вашего класса». Воин с набором MELEE_DPS читал, что сила
    -- не идёт вовсе, тогда как в его наборе она как раз главная. Теперь строка
    -- собирается из самого набора: что весит больше всего и что весит ноль.
    local counted, ignored = ns.StatWeights:WeightSummary(activeKey)
    local tail
    if counted and #counted > 0 then
        tail = "для вашего набора весов в балл идут " .. table.concat(counted, ", ")
        if ignored and #ignored > 0 then
            tail = tail .. ", а " .. table.concat(ignored, ", ") .. " не идут вовсе"
        end
        tail = tail .. "."
    else
        tail = "что именно идёт в балл, видно в разделе «Персонаж»."
    end
    -- ОДНО СЛОВО НА ВСЁ ОКНО. Здесь единица подставлялась из ns.UNIT_BENEFIT и
    -- тут же объяснялась словом «балл» - то есть в одной фразе стояли и
    -- «прирост „ед. пользы“», и «мой условный балл». Это два названия одного
    -- числа, а игрок читает их как два разных. Теперь название одно, и это то
    -- же слово, которое стоит на карточках (см. ns.UNIT_BENEFIT).
    note("Пустой выбор = определяю сам по классу и специализации."
        .. " Веса — оценка, а не факт из клиента: прирост в баллах — это мой"
        .. " условный счёт по этим весам, им удобно сравнивать вещи между собой."
        .. " Балл — не характеристика «сила» и вообще не характеристика из игры: "
        .. tail)

    -- Enchant slot mapping ---------------------------------------------
    head("Чары: какой слот у какой категории")
    local cats = ns.RecipeBook:EnchantCategories()
    if #cats == 0 then
        note("Пока ни одной категории чар не найдено. Откройте окно наложения чар —"
            .. " я прочитаю категории и разложу формулы по слотам.")
    else
        note("Слот определяется по категории рецепта, внешняя база не нужна."
            .. " Если я угадал мимо — нажмите на строку, слот сменится на следующий"
            .. " по списку, и выбор запомнится.")
        for _, cat in ipairs(cats) do
            counters.slot = counters.slot + 1
            local w = self:Widget("slot", counters.slot, function()
                local btn = CreateFrame("Button", nil, self.content)
                btn:SetHeight(18)
                btn.label = W.Label(btn, "", W.FONT_SMALL, 0.70, 0.70, 0.70)
                btn.label:SetPoint("LEFT", 0, 0)
                btn.value = W.Label(btn, "", W.FONT_SMALL, 0.92, 0.92, 0.92)
                btn.value:SetPoint("LEFT", btn, "LEFT", 240, 0)
                btn:SetScript("OnEnter", function(s)
                    s.label:SetTextColor(1, 0.82, 0)
                end)
                btn:SetScript("OnLeave", function(s)
                    s.label:SetTextColor(0.70, 0.70, 0.70)
                end)
                return btn
            end)
            w:SetWidth(width)
            w.label:SetText(cat.categoryName)
            local current = cat.slot
            local text = current and ns.SlotMap:Label(current) or "|cffff8040не определён|r"
            if cat.override then text = text .. "  |cff60c060(вручную)|r"
            elseif current then text = text .. "  |cff808080(угадал)|r" end
            w.value:SetText(text)
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
            place(w, 19)
        end
    end

    local unmapped = ns.EnchantAdvisor:Unmapped()
    if #unmapped > 0 then
        note("|cffff8040Не разложил по слотам: " .. #unmapped .. " "
            .. U.plural(#unmapped, "категорию", "категории", "категорий")
            .. ". Формулы из них в советы не попадают, пока слот не назначен.|r")
    end

    -- Client capabilities ----------------------------------------------
    -- СЛОВАМИ, А НЕ ИМЕНАМИ ФУНКЦИЙ. Здесь стояло «Все вызовы игрового API
    -- идут через один слой-адаптер», а в строках - перечень внутренних ключей
    -- («нет: itemStats, tooltipByID»). Игроку из этого раздела нужно одно:
    -- каких сведений игра аддону не даёт. Имена лежат в файле диагностики.
    head("Что эта игра мне сообщает")
    note("Здесь видно, какие сведения эта версия игры мне даёт, а какие нет."
        .. " Чего она не даёт, то я помечаю как неизвестное — аддон от этого"
        .. " не ломается.")
    for _, group in ipairs(ns.Api:Report()) do
        local text
        if group.state == "ok" then
            text = "|cff60c060всё на месте|r"
        elseif group.state == "none" then
            text = "|cffff6060игра этого не сообщает|r"
        else
            text = "|cffffcc40частично|r — не хватает " .. #group.missing .. " из "
                .. (#group.missing + #group.ok)
        end
        stat(group.group, text)
    end
    stat("Это клиент Forever", ns.Api:IsForever() and "да" or "не определил")
    stat("Локаль", ns.Api:Locale())

    head("Дополнительные аддоны")
    stat("Auctionator", ns.Api:AuctionatorPresent() and "|cff60c060есть|r"
        or "|cff808080нет — цены помечаю как неизвестные|r")
    stat("Syndicator", ns.Api:SyndicatorPresent() and "|cff60c060есть|r"
        or "|cff808080нет — вижу только свои сумки|r")
    stat("Кеш рецептов другого аддона", ns.Api:MastercraftDB() and "|cff60c060есть|r"
        or "|cff808080нет|r")
    note("Ни один из них не обязателен. Я только читаю их данные, ничего в них"
        .. " не пишу и ни одной строки их кода не использую.")

    -- СВОЯ КНИГА ЗАКУПОК ------------------------------------------------
    head("Своя книга закупок")
    if ns.Ledger then
        local rep = ns.Ledger:Report()
        stat("Записей", tostring(rep.entries), (rep.entries > 0) and ns.CONF.EXACT or nil)
        stat("Предметов с ценой покупки", tostring(rep.items))
        if rep.lastT then
            stat("Последняя запись", U.ageWord(ns.Api:ServerTime() - rep.lastT))
        else
            stat("Последняя запись", U.void(ns.VOID.UNKNOWN))
        end
        note(ns.Ledger:Headline())
        note("Я смотрю, как у вас меняются деньги и сумки, когда открыто окно"
            .. " торговца или аукциона. Если деньги убыли ровно настолько,"
            .. " насколько прибыл один предмет — это покупка, и цену за штуку я"
            .. " знаю точно. Если понять однозначно нельзя, я не записываю"
            .. " ничего: выдуманная себестоимость хуже пустой строки.")
        for _, gap in ipairs(rep.gaps or {}) do
            note("|cff808080Чего я не вижу: " .. gap .. ".|r")
        end
        if (rep.skipped or 0) > 0 then
            stat("Отказов сверки", tostring(rep.skipped))
        end
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
    else
        note("Книга закупок не загрузилась.")
    end

    -- ЧУЖАЯ КНИГА: названа чужой, и тут же сказано, что с ней будет.
    if ns.Api:MastercraftDB() then
        head("Чужая книга закупок (запасной источник)")
        stat("Источник", ns.FOREIGN_BOOK.name)
        note(U.capitalize(ns.FOREIGN_BOOK.why) .. ".")
        note(U.capitalize(ns.FOREIGN_BOOK.plan) .. ".")
    end

    -- Price history ----------------------------------------------------
    head("Своя история цен")
    local meta = ns.Config:PriceHistoryMeta()
    stat("Накоплено", (meta.items or 0) .. " предметов, " .. (meta.days or 0) .. " дней")
    local progress, total = ns.PriceProvider:SnapshotProgress()
    if progress then
        stat("Слепок сегодня", progress .. " из " .. total .. " — идёт")
    else
        stat("Слепок сегодня", meta.lastWritten and (meta.lastWritten .. " записей") or "ещё не делал")
    end
    note("Один раз в сутки я прохожу по вашим реагентам и записываю цену Auctionator."
        .. " Сервер открылся 4 ноября 2026, истории цен нет ни у кого и собрать её"
        .. " задним числом нельзя — поэтому копим с первого дня. В этой версии"
        .. " данные только складываются, выводов по ним я пока не делаю.")

    -- Rules ------------------------------------------------------------
    head("Чего аддон не делает")
    note("Не покупает и не продаёт. Не крафтит. Не нажимает ничего за вас."
        .. " Не обходит защищённые функции и не делает ничего в бою."
        .. " Только советует — действуете вы.")

    head("Служебное")
    stat("Версия", ns.VERSION)
    stat("Пересчётов за сессию", tostring((cfg.stats and cfg.stats.recomputes) or 0))
    button("Пересчитать сейчас", function() ns.MainFrame:Rebuild(true) end)
    -- Через ту же Card.RestoreHidden, что и кнопка «Вернуть все» на карточке и
    -- команда /fp show. Раньше здесь чистилась таблица руками: мимо
    -- Config:ClearDismissed, а значит и мимо очистки lastDismiss — после этой
    -- кнопки /fp undo отвечал «вернул: ‹карточка›» про уже не скрытую карточку.
    -- И сообщение было своё, третье по счёту, на одно и то же действие.
    button("Вернуть все скрытые советы", function()
        ns.Card.RestoreHidden()
    end)
    -- НЕОБРАТИМОЕ - В ДВА НАЖАТИЯ. Раньше эта кнопка стирала список с одного
    -- щелчка, прямо отсюда, без вопроса и без слова в ответ. Теперь первое
    -- нажатие только спрашивает, и кнопка на время вопроса сама меняет
    -- подпись - игрок, который не читает чат, видит это на ней самой. Решает
    -- ShoppingList:RequestClear; здесь только слова и перерисовка.
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

    self.content:SetSize(width, math.max(1, y + 10))
end

function Tab:OnShow() Tab:Render() end

return Tab
