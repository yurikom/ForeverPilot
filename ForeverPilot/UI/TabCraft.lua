-- ForeverPilot / UI/TabCraft.lua
--
-- The craft workbench: pick a recipe, see the whole material tree worked out,
-- what is already in your bags, what has to be bought, and what each step costs.
-- Plus the merged shopping list for everything the Now tab suggested.
local ADDON, ns = ...

local U = ns.Util
local W = ns.Widgets

local Tab = {}
ns.TabCraft = Tab

Tab.PAD = 12
Tab.selected = nil
Tab.quantity = 1
Tab.query = ""   -- the search text; the edit box itself is Tab.searchBox

function Tab:Build(parent)
    if self.frame then return self.frame end
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)
    self.frame = frame

    -- Left: recipe list with a search box.
    local search = CreateFrame("EditBox", nil, frame)
    search:SetSize(240, 20)
    search:SetPoint("TOPLEFT", Tab.PAD, -Tab.PAD)
    search:SetAutoFocus(false)
    search:SetFontObject("GameFontHighlightSmall")
    search:SetTextInsets(6, 6, 0, 0)
    W.Backdrop(search, 1, 1, 1, 0.07, 0.14)
    search:SetScript("OnTextChanged", function(self)
        -- Util.lower, not string.lower: the recipe names are Russian and Lua's
        -- own lower leaves Cyrillic untouched, so searching "рулон" for
        -- "Рулон шелка" would find nothing.
        Tab.query = ns.Util.lower(self:GetText() or "") or ""
        Tab:RenderList()
    end)
    search:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    self.searchBox = search

    local hint = W.Label(frame, "поиск по названию", W.FONT_SMALL, 0.45, 0.45, 0.45)
    hint:SetPoint("LEFT", search, "LEFT", 7, 0)
    search:SetScript("OnEditFocusGained", function() hint:Hide() end)
    search:SetScript("OnEditFocusLost", function(self)
        if (self:GetText() or "") == "" then hint:Show() end
    end)

    self.onlyLearned = W.Checkbox(frame, "только выученные", function()
        Tab:RenderList()
    end)
    self.onlyLearned:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -6)
    self.onlyLearned:SetWidth(240)
    self.onlyLearned:SetChecked(true)

    local listScroll, listContent = W.ScrollArea(frame)
    listScroll:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -30)
    listScroll:SetPoint("BOTTOMLEFT", Tab.PAD, Tab.PAD)
    listScroll:SetWidth(240)
    self.listScroll, self.listContent = listScroll, listContent
    self.listRows = {}

    -- Right: the plan for the selected recipe.
    local planScroll, planContent = W.ScrollArea(frame)
    planScroll:SetPoint("TOPLEFT", listScroll, "TOPRIGHT", 26, 30)
    planScroll:SetPoint("BOTTOMRIGHT", -(Tab.PAD + 22), Tab.PAD)
    self.planScroll, self.planContent = planScroll, planContent
    self.planWidgets = {}

    return frame
end

-- Recipe list -----------------------------------------------------------

function Tab:ListRow(index)
    local row = self.listRows[index]
    if row then row:Show(); return row end
    row = CreateFrame("Button", nil, self.listContent)
    row:SetHeight(20)
    W.Backdrop(row, 1, 1, 1, 0.03, 0)
    row.text = W.Label(row, "", W.FONT_SMALL, 0.85, 0.85, 0.85)
    row.text:SetPoint("LEFT", 6, 0)
    row.text:SetPoint("RIGHT", -6, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    row:SetScript("OnEnter", function(self)
        self.fpBG:SetColorTexture(0.30, 0.50, 0.85, 0.25)
    end)
    row:SetScript("OnLeave", function(self)
        self.fpBG:SetColorTexture(1, 1, 1, self.selected and 0.12 or 0.03)
    end)
    row:SetScript("OnClick", function(self)
        Tab.selected = self.recipeID
        Tab:RenderList()
        Tab:RenderPlan()
    end)
    self.listRows[index] = row
    return row
end

function Tab:RenderList()
    local onlyLearned = self.onlyLearned and self.onlyLearned.checked
    local query = Tab.query or ""
    local recipes = ns.RecipeBook:Iterate(function(r)
        if onlyLearned and not r.learned then return false end
        if query ~= "" and not ns.Util.contains(r.name or "", query) then
            return false
        end
        return true
    end)

    local y, shown = 0, 0
    for _, recipe in ipairs(recipes) do
        if shown >= 300 then break end
        shown = shown + 1
        local row = self:ListRow(shown)
        row:SetWidth(232)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", self.listContent, "TOPLEFT", 0, -y)
        row.recipeID = recipe.id
        row.selected = (recipe.id == Tab.selected)
        row.fpBG:SetColorTexture(1, 1, 1, row.selected and 0.12 or 0.03)

        -- Пометка «не выучен» словом, а не кружком: кружок клиент рисует
        -- квадратиком (см. ns.GLYPH в Core/Const.lua).
        local prefix = recipe.learned and "" or "|cff808080(не выучен)|r "
        row.text:SetText(prefix .. (recipe.name or ("#" .. recipe.id)))
        if recipe.learned then
            row.text:SetTextColor(0.88, 0.88, 0.88)
        else
            row.text:SetTextColor(0.55, 0.55, 0.55)
        end
        y = y + 21
    end
    for i = shown + 1, #self.listRows do self.listRows[i]:Hide() end
    self.listContent:SetSize(232, math.max(1, y))
end

-- Plan panel ------------------------------------------------------------

function Tab:PlanRow(kind, index)
    local key = kind .. index
    local w = self.planWidgets[key]
    if w then w:Show(); return w end
    if kind == "head" then
        w = W.SectionHeader(self.planContent, "", 360)
    elseif kind == "stat" then
        w = W.StatRow(self.planContent, "", "", 360)
    elseif kind == "button" then
        w = W.Button(self.planContent, "", 180, 22)
    else
        w = W.Label(self.planContent, "", W.FONT_SMALL, 0.65, 0.65, 0.65)
    end
    self.planWidgets[key] = w
    return w
end

function Tab:RenderPlan()
    for _, w in pairs(self.planWidgets) do w:Hide() end
    local width = (self.planScroll:GetWidth() or 380) - 8
    local y, heads, stats, notes = 0, 0, 0, 0

    local function head(text)
        heads = heads + 1
        local w = self:PlanRow("head", heads)
        w:SetWidth(width); w.text:SetText(text)
        w:ClearAllPoints(); w:SetPoint("TOPLEFT", self.planContent, "TOPLEFT", 0, -y)
        y = y + 26
    end
    local function stat(label, value, conf)
        stats = stats + 1
        local w = self:PlanRow("stat", stats)
        w:SetWidth(width); w.label:SetText(label)
        -- Нет значения - это «не знаю» (ns.VOID), а не прочерк: прочерк в
        -- словаре пустоты означает «такого значения не бывает».
        local text = value or U.void(ns.VOID.UNKNOWN)
        if conf and conf ~= ns.CONF.EXACT then
            text = text .. "  |cff808080(" .. (ns.CONF_LABEL[conf] or "?") .. ")|r"
        end
        w.value:SetText(text)
        w:ClearAllPoints(); w:SetPoint("TOPLEFT", self.planContent, "TOPLEFT", 0, -y)
        y = y + 18
    end
    local function note(text)
        notes = notes + 1
        local w = self:PlanRow("note", notes)
        w:SetWidth(width); w:SetText(text)
        w:SetJustifyH("LEFT"); w:SetWordWrap(true)
        w:ClearAllPoints(); w:SetPoint("TOPLEFT", self.planContent, "TOPLEFT", 0, -y)
        y = y + math.max(14, (w:GetStringHeight() or 12) + 4)
    end
    -- Кнопка в этой панели. Как и остальные строки, берётся из пула и в начале
    -- каждой отрисовки спрятана: кнопка, которую в этот раз не попросили, на
    -- экране не остаётся.
    local buttons = 0
    local function button(label, onClick, tipTitle, tipLines)
        buttons = buttons + 1
        local w = self:PlanRow("button", buttons)
        w:SetLabel(label)
        w:SetWidth(U.clamp(((w.text and w.text:GetStringWidth()) or 150) + 24, 120, width))
        w:SetScript("OnClick", onClick)
        -- Кнопка из пула: подсказка ставится заново каждый раз, иначе на ней
        -- осталась бы подсказка от прошлого назначения.
        w:SetScript("OnEnter", function(self2)
            self2:Repaint(true)
            if tipTitle then W.ShowTip(self2, tipTitle, tipLines) end
        end)
        w:SetScript("OnLeave", function(self2)
            self2:Repaint(false)
            W.HideTip()
        end)
        w:ClearAllPoints(); w:SetPoint("TOPLEFT", self.planContent, "TOPLEFT", 0, -(y + 4))
        y = y + 30
        return w
    end

    local recipe = Tab.selected and ns.RecipeBook:Get(Tab.selected) or nil

    if not recipe then
        head("Выберите рецепт слева")
        local learned = ns.RecipeBook:LearnedCount()
        if learned == 0 then
            note("Список пуст, потому что игра не отдаёт рецепты, пока окно"
                .. " профессии не открыли хотя бы раз за сессию. Откройте его —"
                .. " список появится сам.")
        else
            note("Я разберу рецепт на материалы до самого низа: вычту то, что"
                .. " лежит в сумках и банке, посчитаю, что придётся купить,"
                .. " и сравню «скрафтить промежуточный материал» с «купить готовый».")
        end
        self:RenderShopping(head, stat, note, button)
        self.planContent:SetSize(width, math.max(1, y))
        return
    end

    ns.PriceProvider:BeginPass()
    ns.CraftingPlanner:Bind(ns.RecipeBook, ns.PriceProvider):BeginPass()
    local plan = ns.CraftingPlanner:Plan(recipe, Tab.quantity)

    head(recipe.name or ("#" .. recipe.id))
    -- Имя профессии у рецепта - это ключ книги рецептов, а он приходит и из
    -- чужого кеша («Tailoring»). На экран - через U.profLabel, как везде.
    stat("Профессия", U.profLabel(recipe.profession) or U.void(ns.VOID.UNKNOWN))
    stat("Категория", recipe.categoryName or U.void(ns.VOID.UNKNOWN))
    stat("Выучен", recipe.learned and "да" or "|cffff8040нет|r", recipe.conf)
    if recipe.output then
        local info = ns.Api:ItemInfo(recipe.output)
        stat("Делает", ((info and info.name) or U.itemFallbackName(recipe.output))
            .. " x" .. (recipe.outputQty or 1))
        if info and info.reqLevel and info.reqLevel > 0 then
            local snap = ns.CharacterScanner:Get()
            local mine = snap and snap.level or 0
            -- Существительное впереди числа: «нужен уровень 45» согласуется
            -- при любом N, «нужен 45 уровень» - ни при каком.
            local text = "нужен уровень " .. info.reqLevel
            if mine > 0 and info.reqLevel > mine then
                text = "|cffff8040" .. text .. ", у вас " .. mine
                    .. " — надеть нельзя, но продать можно|r"
            end
            stat("Требование", text, ns.CONF.EXACT)
        end
    else
        stat("Делает", "это чары — предмета нет")
        local slot, slotConf = ns.SlotMap:EnchantSlot(recipe)
        stat("Слот", slot and ns.SlotMap:Label(slot) or "|cffff8040не определён|r", slotConf)
    end
    if recipe.diff then
        local chance = ns.CraftingPlanner:SkillChance(recipe)
        stat("Шанс на навык", U.pct(chance), ns.CONF.CACHED)
    end

    if not plan then
        note("Не смог построить план — у рецепта нет реагентов в данных клиента.")
        self:RenderShopping(head, stat, note, button)
        self.planContent:SetSize(width, math.max(1, y))
        return
    end

    head("Что потребуется")
    if plan.cost then
        stat("Докупить на", U.money(plan.cost), plan.costConf)
    elseif plan.costPartial and plan.costPartial > 0 then
        stat("Докупить на", "от " .. U.money(plan.costPartial)
            .. " (часть цен неизвестна)", ns.CONF.UNKNOWN)
    else
        stat("Докупить на", plan.ready and "ничего — всё есть" or U.void(ns.VOID.NO_PRICE),
            plan.ready and ns.CONF.EXACT or ns.CONF.UNKNOWN)
    end
    stat("Готовность", U.pct(plan.readiness or 0))

    if U.count(plan.usedHere) > 0 then
        for itemID, qty in pairs(plan.usedHere) do
            stat("   из сумок", ns.ActionEngine.nameOf(itemID) .. " x" .. qty, ns.CONF.EXACT)
        end
    end
    if U.count(plan.usedBank) > 0 then
        for itemID, qty in pairs(plan.usedBank) do
            stat("   из банка", ns.ActionEngine.nameOf(itemID) .. " x" .. qty, ns.CONF.CACHED)
        end
        note("Часть материалов не в сумках — придётся зайти в банк или к другому персонажу.")
    end
    -- Overrun from a step inside this very plan. Listed separately so it is
    -- never read as something already sitting in the bags.
    if U.count(plan.usedSurplus or {}) > 0 then
        for itemID, qty in pairs(plan.usedSurplus) do
            stat("   из излишка", ns.ActionEngine.nameOf(itemID) .. " x" .. qty, ns.CONF.EXACT)
        end
        note("Часть материалов получится попутно: крафт выше делает больше, чем нужно.")
    end
    for _, line in ipairs(plan.shopping or {}) do
        local price = line.subtotal and U.money(line.subtotal) or U.void(ns.VOID.NO_PRICE)
        local suffix = line.buyable and "" or "  |cff808080(на аукционе не найти)|r"
        stat("   купить", ns.ActionEngine.nameOf(line.itemID) .. " x" .. line.qty
            .. " — " .. price .. suffix, line.conf)
        -- ЧТО ИГРОК ЗА ЭТО ПЛАТИЛ - РЯДОМ С ТЕМ, ЧТО ПРОСЯТ СЕЙЧАС. Это его
        -- собственные деньги и его собственная история: сравнивать «дорого
        -- или нет» ему больше не с чем. См. Logic/Ledger.lua.
        local cmp = ns.Ledger and ns.Ledger:PaidVsMarket(line.itemID, ns.PriceProvider) or nil
        if cmp then stat("      ", cmp.text, ns.CONF.EXACT) end
    end
    if plan.ready then note("|cff60c060Всё нужное уже есть.|r") end

    -- The craft order, including intermediates the planner decided to make.
    if #plan.crafts > 1 then
        head("Порядок крафта")
        for i, step in ipairs(plan.crafts) do
            stat(i .. ".", (step.recipe.name or "?") .. " x" .. step.times)
        end
        note("Промежуточные материалы я делаю сам только когда это дешевле,"
            .. " чем купить готовые. Иначе они попадают в список покупок.")
    end

    -- The buy-or-craft calls we made, so the player can disagree with us.
    local decisions = {}
    for itemID, d in pairs(plan.decisions or {}) do
        if d.craftCost and d.buyCost then decisions[#decisions + 1] = { itemID, d } end
    end
    if #decisions > 0 then
        head("Скрафтить или купить")
        table.sort(decisions, function(a, b) return a[1] < b[1] end)
        for _, pair in ipairs(decisions) do
            local itemID, d = pair[1], pair[2]
            local verdict = (d.method == "craft") and "делаю сам" or "покупаю"
            stat(ns.ActionEngine.nameOf(itemID),
                verdict .. ": крафт " .. U.money(d.craftCost)
                .. " против покупки " .. U.money(d.buyCost))
        end
    end

    if plan.hasCycle then
        note("|cffff8040В цепочке материалов есть замкнутый круг — я его разорвал"
            .. " и считаю такие позиции покупаемыми.|r")
    end
    if plan.truncated then
        note("|cffff8040Дерево материалов оказалось слишком глубоким, я его обрезал."
            .. " Нижние уровни считаю по цене покупки.|r")
    end

    -- Margin, which for this character is the main point.
    if not recipe.output then
        -- ЧАРЫ НЕ ПРОДАЮТСЯ, И ЭТО «ТАК НЕЛЬЗЯ», А НЕ «НЕ ЗНАЮ».
        --
        -- Раньше раздела «Экономика» здесь просто не было, и игрок не мог
        -- отличить «аддон не умеет считать выручку с чар» от «выручки не
        -- бывает». Разница для него решающая: в первом случае есть чего ждать,
        -- во втором - нечего. Словарь пустоты (ns.VOID) для этого и заведён.
        head("Экономика")
        stat("Выручка за штуку", U.void(ns.VOID.IMPOSSIBLE) .. "  |cff808080("
            .. U.voidWhy(ns.VOID.IMPOSSIBLE) .. ": чары накладываются на вещь,"
            .. " продавать нечего)|r")
        stat("Прибыль", U.void(ns.VOID.IMPOSSIBLE))
    end
    if recipe.output then
        local margin, mConf, revenue, cost, craft = ns.CraftingPlanner:Margin(recipe)
        local qty = (craft and craft.outputQty) or 1
        head("Экономика")
        -- Per item and per craft are two different numbers. With a recipe that
        -- yields five, showing one of them unlabelled next to a material list
        -- for a whole run is how a 75-copper margin reads as 375.
        stat("Себестоимость за штуку",
            cost and U.money(cost) or U.void(ns.VOID.NO_PRICE), mConf)
        stat("Выручка за штуку",
            revenue and U.money(revenue) or U.void(ns.VOID.NO_PRICE), mConf)
        if margin then
            stat("Прибыль за штуку", U.moneyDelta(margin), mConf)
        else
            stat("Прибыль", U.void(ns.VOID.NO_PRICE) .. "  |cff808080("
                .. U.voidWhy(ns.VOID.NO_PRICE) .. ")|r", ns.CONF.UNKNOWN)
        end

        -- ГРАНИЦА, НИЖЕ КОТОРОЙ ПРОДАВАТЬ В МИНУС. Отдельной строкой и
        -- словами: это единственное число, которое игроку нужно, когда он
        -- выставляет лот сам. См. Logic/Ledger.lua.
        local be = ns.Ledger and ns.Ledger:Breakeven(recipe, ns.PriceProvider) or nil
        if be then
            stat("Безубыточность (выставлять не ниже)", U.money(be.listPrice), be.conf)
            note((be.source == "ledger")
                and ("|cff60c060Себестоимость посчитана по вашим собственным"
                     .. " покупкам, а не по оценке.|r")
                or ((be.source == "mixed")
                    and ("|cffffcc40Часть материалов посчитана по вашим покупкам ("
                         .. (be.coverage and be.coverage.known or 0) .. " из "
                         .. (be.coverage and be.coverage.total or 0)
                         .. "), остальное — оценка.|r")
                    or "Своих покупок по этим материалам нет — себестоимость"
                       .. " пока оценочная."))
            note("Дешевле " .. U.money(be.listPrice) .. " за штуку выставлять"
                .. " нельзя: это продажа в минус. Аукцион забирает "
                .. U.pct(be.cut) .. " с цены продажи, поэтому граница выше"
                .. " себестоимости (" .. U.money(be.unitCost) .. ").")
        else
            stat("Безубыточность", U.void(ns.VOID.NO_PRICE), ns.CONF.UNKNOWN)
        end
        if craft and qty > 1 then
            stat("Выход за крафт", qty .. " шт.")
            stat("Материалы на крафт", U.money(craft.cost), mConf)
            stat("Выручка с крафта", U.money(craft.revenue), mConf)
            stat("Прибыль за крафт", U.moneyDelta(craft.margin), mConf)
        end
        local cdLeft = ns.CraftingPlanner:CooldownLeft(recipe)
        if cdLeft then
            stat("Перезарядка", "ещё " .. (U.durationText(cdLeft) or "?"), ns.CONF.EXACT)
            note("|cffffcc40Рецепт на перезарядке — сейчас его не сделать.|r")
        end
        stat("Можно сделать сейчас",
            ns.CraftingPlanner:MaxCraftableNow(recipe) .. " шт. из того, что в сумках")
    end

    self:RenderShopping(head, stat, note, button)
    self.planContent:SetSize(width, math.max(1, y))
end

function Tab:RenderShopping(head, stat, note, button)
    local lines = ns.ShoppingList:Lines()
    head("Общий список покупок")
    if #lines == 0 then
        note("Пусто: всё, что я советую в разделе «Советы», можно сделать"
            .. " из того, что у вас уже есть.")
        return
    end
    local snap = ns.CharacterScanner:Get()
    local afford = ns.ShoppingList:Affordability(snap)
    note("Это сумма на случай, если делать всё из раздела «Советы». Своё уже"
        .. " вычтено — и вычтено один раз, а не по разу на каждый совет.")
    for i = 1, math.min(15, #lines) do
        local line = lines[i]
        local label = line.name .. " x" .. line.qty
        if line.have and line.have > 0 and line.gross then
            label = label .. "  |cff808080(нужно " .. line.gross
                .. ", своего " .. line.have .. ")|r"
        end
        if line.pinned then label = label .. "  |cff80c0ff(закреплено)|r" end
        -- ДЕШЕВЛЕ У ТОРГОВЦА - ПОМЕТКОЙ У САМОЙ СТРОКИ. Сумма уже посчитана по
        -- потолку (Logic/PriceProvider.lua), а идти за этой строкой надо не на
        -- аукцион, и видно это должно быть там же, где цена.
        if line.vendorSaving and line.vendorSaving > 0 then
            label = label .. "  |cff60c060(у торговца, экономия "
                .. U.money(line.vendorSaving) .. ")|r"
        end
        stat(label, line.subtotal and U.money(line.subtotal) or U.void(ns.VOID.NO_PRICE), line.conf)
    end
    if #lines > 15 then note("…и ещё " .. (#lines - 15) .. " позиций.") end
    stat("Итого", U.money(afford.total)
        .. (afford.unknownLines > 0 and ("  + " .. afford.unknownLines .. " без цены") or ""),
        afford.conf)
    stat("У вас", U.money(afford.money), snap and snap.moneyConf or ns.CONF.UNKNOWN)
    -- ИТОГ ПО ПОТОЛКУ: сколько всего экономит поход к торговцу вместо аукциона.
    -- Считает Logic/ShoppingList по тем же строкам, что показаны выше.
    local save = ns.ShoppingList:VendorSaving()
    if save then
        -- «там ОНИ стоили бы» не годится: позиция бывает и одна. Без
        -- местоимения фраза согласована при любом числе.
        note("|cff60c060Из этого списка " .. save.lines .. " "
            .. U.plural(save.lines, "позицию", "позиции", "позиций")
            .. " дешевле взять у торговца, а не на аукционе: на аукционе это"
            .. " стоило бы на " .. U.money(save.saving) .. " дороже.|r")
    end
    if afford.affordable == nil then
        note("|cffffcc40Полную сумму не назову: на " .. (afford.unknownLines or 0)
            .. " " .. U.plural(afford.unknownLines or 0, "позицию", "позиции", "позиций")
            .. " цены нет, так что итог ниже настоящего.|r")
    elseif afford.affordable == false then
        note("|cffff6060Не хватает " .. U.money(afford.shortfall) .. " на весь список.|r")
    elseif not afford.withinCap then
        note("|cffffcc40Список съест больше, чем "
            .. U.pct(ns.Config:Get().show.maxSpendShare)
            .. " вашего золота. Я не советую тратить всё.|r")
    end
    -- ПЕРЕДАЧА СПИСКА В AUCTIONATOR: КНОПКА ТОЛЬКО ТОГДА, КОГДА ОНА СРАБОТАЕТ.
    --
    -- Все условия проверяет ShoppingList:Handoff. Здесь - одно правило: кнопка
    -- рисуется только в состоянии "ready". Нет Auctionator, нет в нём поиска,
    -- закрыт аукцион, нечего искать, прошлый вызов не удался - кнопки нет
    -- вовсе, а строка под списком говорит почему.
    local handoff = ns.ShoppingList:Handoff()
    if handoff.state == "ready" and button then
        button(ns.ShoppingList.HANDOFF_LABEL, function() Tab:SendToAuction() end,
            "Передать список в поиск Auctionator", {
                "Открою вкладку покупок Auctionator и запущу в ней поиск по"
                    .. " позициям этого списка.",
                "Ничего не покупаю и не выставляю — дальше действуете вы.",
            })
    end
    if handoff.note then note(handoff.note) end
end

-- Нажатие кнопки «Искать на аукционе». Под Diag:Guard: щелчок - ровно то место,
-- где игрок упирается в ошибку, а этот вызов уходит в чужой аддон.
function Tab:SendToAuction()
    return ns.Diag:Guard("TabCraft:SendToAuction", Tab.SendToAuctionInner, self)
end

function Tab:SendToAuctionInner()
    local ok, message = ns.ShoppingList:SendToAuctionator()
    if message then ns.Api:Print(message) end
    -- Состояние могло измениться прямо сейчас - аукцион закрыли, Auctionator
    -- ответил ошибкой, - и кнопка обязана ему соответствовать сразу, а не после
    -- следующего пересчёта.
    Tab:RenderPlan()
    return ok
end

-- ПЕРЕРИСОВКА ПО ПЕРЕСЧЁТУ. У этой вкладки её не было.
--
-- Окно после каждого пересчёта зовёт Render у активной вкладки (MainFrame:
-- RenderActive). У «Сейчас», «Мой персонаж» и «Настройки» он есть, а у «Крафт»
-- был только OnShow - то есть вкладка обновлялась, когда на неё переключались,
-- и больше никогда. Пока она открыта, список покупок показывал суммы на момент
-- входа, сколько бы пересчётов ни прошло, а кнопка «Искать на аукционе» не
-- появилась бы, пока игрок не уйдёт с вкладки и не вернётся: аукцион открывают
-- как раз тогда, когда вкладка уже на экране.
function Tab:Render()
    if not self.frame then return end
    Tab:RenderList()
    Tab:RenderPlan()
end

function Tab:OnShow()
    Tab:Render()
end

return Tab
