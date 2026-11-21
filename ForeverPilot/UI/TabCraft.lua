-- ForeverPilot / UI/TabCraft.lua
--
-- Раздел «Покупки»: всё, что надо докупить под советы, одним списком - что,
-- где (у торговца или на аукционе) и почём, итог, сколько золота у игрока и
-- сколько не хватает. При открытом аукционе - кнопка, которая отдаёт список в
-- поиск Auctionator.
--
-- ФАЙЛ НАЗЫВАЕТСЯ ПО-СТАРОМУ, И ЭТО НАРОЧНО. Раньше здесь был раздел «Крафт»:
-- слева список рецептов с поиском, справа выбранный рецепт до материалов, и
-- под ним этот список покупок. Игрок спросил, зачем он (2026-11-21: «У меня
-- есть профессии, в них я захожу, делаю крафт. Что она мне даёт?»). Разбор
-- рецепта уже стоит в карточке совета - что купить у торговца, что на аукционе
-- и почём, - поэтому список рецептов убран, а список покупок остался и стал
-- разделом. Переименовать файл - значит завести новый, а новый файл клиент
-- видит только после полного перезапуска игры.
local ADDON, ns = ...

local U = ns.Util
local W = ns.Widgets

local Tab = {}
ns.TabCraft = Tab

Tab.PAD = 24
Tab.MAX_W = 560              -- шире этого список не растягивается: цена не уезжает от названия
Tab.LIMIT = 40               -- строк списка на экране; остальное названо числом
Tab.ROW_H = 24

Tab.SHOP_CAPTION = { vendor = "У торговца", auctionator = "На аукционе" }
Tab.SHOP_CAPTION_OTHER = "Где купить — неизвестно"
Tab.SHOP_ORDER = { "vendor", "auctionator" }
Tab.TITLE = "Общий список покупок"

function Tab:Build(parent)
    if self.frame then return self.frame end
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)
    self.frame = frame

    local scroll, content = W.ScrollArea(frame)
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", Tab.PAD, -16)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -Tab.PAD, 14)
    self.scroll, self.content = scroll, content
    self.widgets = {}
    return frame
end

-- Ширина списка - от размера окна, а не от того, успел ли клиент разложить
-- рамки (у только что построенной рамки ширина нулевая).
function Tab:Width()
    local hostW = ns.MainFrame:HostNow()
    return math.min(Tab.MAX_W, math.max(240, hostW - 2 * Tab.PAD - 14))
end

-- Строки берутся из общего набора и в начале каждой отрисовки спрятаны: то,
-- что в этот раз не попросили, на экране не остаётся.
function Tab:Row(kind, index)
    local key = kind .. index
    local w = self.widgets[key]
    if w then w:Show(); return w end
    local T = W.THEME
    if kind == "head" then
        w = W.SectionHeader(self.content, "", 360)
    elseif kind == "stat" then
        w = W.StatRow(self.content, "", "", 360)
    elseif kind == "button" then
        w = W.Button(self.content, "", 200, 32)
    elseif kind == "caption" then
        w = W.Label(self.content, "", W.FONT_CAPTION, T.muted[1], T.muted[2], T.muted[3])
    elseif kind == "rule" then
        w = self.content:CreateTexture(nil, "ARTWORK")
        W.Paint(w, T.line)
        w:SetHeight(1)
    else
        w = W.Label(self.content, "", W.FONT_SMALL, T.dim[1], T.dim[2], T.dim[3])
    end
    self.widgets[key] = w
    return w
end

function Tab:Render()
    if not self.frame then return end
    for _, w in pairs(self.widgets) do w:Hide() end
    local T = W.THEME
    local width = self:Width()
    local y = 0
    local count = { head = 0, stat = 0, note = 0, caption = 0, button = 0, rule = 0 }
    local function take(kind)
        count[kind] = count[kind] + 1
        return self:Row(kind, count[kind])
    end
    local function place(w, height, gapBefore)
        w:ClearAllPoints()
        w:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -(y + (gapBefore or 0)))
        y = y + (gapBefore or 0) + height
    end

    local function head(text)
        local w = take("head")
        w:SetWidth(width)
        w.text:SetText(text)
        place(w, 26 + 8, (y > 0) and 14 or 0)
    end
    -- Строка «название - цена»: цена у правого края, столбцом.
    local function stat(label, value, tone, bright)
        local w = take("stat")
        w:SetWidth(width)
        w.alignRight = true
        local c = (tone == "warn" and T.warn) or (tone == "good" and T.good) or T.text
        w.value:SetTextColor(c[1], c[2], c[3])
        local lc = bright and T.text or T.muted
        w.label:SetTextColor(lc[1], lc[2], lc[3])
        -- Нет значения - это «не знаю» (ns.VOID), а не прочерк.
        w:SetBoth(label, value or U.void(ns.VOID.UNKNOWN))
        place(w, Tab.ROW_H)
    end
    local function note(text, tone)
        local w = take("note")
        local c = (tone == "warn" and T.warn) or (tone == "good" and T.good) or T.dim
        w:SetTextColor(c[1], c[2], c[3])
        w:SetJustifyH("LEFT")
        local h = W.SetWrapped(w, text, width, W.LINE)
        place(w, h + 6, 6)
    end
    local function caption(text)
        local w = take("caption")
        w:SetText(text)
        place(w, 18, 10)
    end
    local function rule()
        local w = take("rule")
        w:SetWidth(width)
        place(w, 1, 8)
        y = y + 6
    end
    local function button(label, onClick, tipTitle, tipLines)
        local w = take("button")
        w:SetLabel(label)
        w:SetIcon("search", 14)
        w:SetPrimary(true)
        w:Resize(U.clamp(w:LabelWidth() + 20, 180, width), 32)
        w:SetScript("OnClick", onClick)
        -- Кнопка из набора: подсказка ставится заново каждый раз.
        w:SetScript("OnEnter", function(self2)
            self2:Repaint(true)
            if tipTitle then W.ShowTip(self2, tipTitle, tipLines) end
        end)
        w:SetScript("OnLeave", function(self2)
            self2:Repaint(false)
            W.HideTip()
        end)
        place(w, 32, 14)
        return w
    end

    local function finish()
        self.content:SetSize(width, math.max(1, y + 10))
        self.scroll:Refresh()
    end

    local lines = ns.ShoppingList:Lines()
    head(Tab.TITLE)
    if #lines == 0 then
        note("Пусто: всё, что я советую, можно сделать из того, что у вас уже есть.")
        return finish()
    end
    local snap = ns.CharacterScanner:Get()
    local afford = ns.ShoppingList:Affordability(snap)

    -- По месту покупки, в порядке списка (он уже отсортирован по сумме).
    local groups, order = {}, {}
    local limit = math.min(Tab.LIMIT, #lines)
    for i = 1, limit do
        local line = lines[i]
        local key = Tab.SHOP_CAPTION[line.src] and line.src or "other"
        groups[key] = groups[key] or {}
        table.insert(groups[key], line)
    end
    for _, key in ipairs(Tab.SHOP_ORDER) do
        if groups[key] then order[#order + 1] = key end
    end
    if groups.other then order[#order + 1] = "other" end

    for _, key in ipairs(order) do
        caption(Tab.SHOP_CAPTION[key] or Tab.SHOP_CAPTION_OTHER)
        for _, line in ipairs(groups[key]) do
            local label = line.name .. " x" .. line.qty
            if line.pinned then label = label .. " (добавлено вами)" end
            stat(label, line.subtotal and U.money(line.subtotal) or U.void(ns.VOID.NO_PRICE),
                (not line.subtotal) and "warn" or nil, true)
        end
    end
    if #lines > limit then
        local rest = #lines - limit
        note("и ещё " .. rest .. " " .. U.plural(rest, "позиция", "позиции", "позиций"))
    end

    rule()
    stat("Итого", U.money(afford.total)
        .. (afford.unknownLines > 0 and (" + " .. afford.unknownLines .. " без цены") or ""))
    stat("У вас", U.money(afford.money))
    if afford.affordable == nil then
        note("Полную сумму не назову: на " .. (afford.unknownLines or 0)
            .. " " .. U.plural(afford.unknownLines or 0, "позицию", "позиции", "позиций")
            .. " цены нет, так что итог ниже настоящего.", "warn")
    elseif afford.affordable == false then
        stat("Не хватает", U.money(afford.shortfall), "warn")
    elseif not afford.withinCap then
        note("Список съест больше, чем " .. U.pct(ns.Config:Get().show.maxSpendShare)
            .. " вашего золота.", "warn")
    end
    -- ИТОГ ПО ТОРГОВЦУ: сколько экономит поход к нему вместо аукциона.
    -- Считает Logic/ShoppingList по тем же строкам, что показаны выше.
    local save = ns.ShoppingList:VendorSaving()
    if save then
        note("У торговца " .. save.lines .. " "
            .. U.plural(save.lines, "позиция", "позиции", "позиций")
            .. " из этого списка " .. U.plural(save.lines, "стоит", "стоят", "стоят")
            .. " дешевле, чем на аукционе: экономия " .. U.money(save.saving) .. ".", "good")
    end
    -- ПЕРЕДАЧА СПИСКА В AUCTIONATOR: КНОПКА ТОЛЬКО ТОГДА, КОГДА ОНА СРАБОТАЕТ.
    --
    -- Все условия проверяет ShoppingList:Handoff. Здесь - одно правило: кнопка
    -- рисуется только в состоянии "ready". Нет Auctionator, нет в нём поиска,
    -- закрыт аукцион, нечего искать, прошлый вызов не удался - кнопки нет
    -- вовсе, а строка под списком говорит почему.
    local handoff = ns.ShoppingList:Handoff()
    if handoff.state == "ready" then
        button(ns.ShoppingList.HANDOFF_LABEL, function() Tab:SendToAuction() end,
            "Передать список в поиск Auctionator", {
                "Открою вкладку покупок Auctionator и запущу в ней поиск по"
                    .. " позициям этого списка.",
                "Ничего не покупаю и не выставляю — дальше действуете вы.",
            })
    end
    if handoff.note then note(handoff.note) end
    return finish()
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
    Tab:Render()
    return ok
end

-- ПЕРЕРИСОВКА ПО ПЕРЕСЧЁТУ. Окно после каждого пересчёта зовёт Render у
-- активного раздела (MainFrame:RenderActive): аукцион открывают как раз тогда,
-- когда раздел уже на экране, и кнопка «Искать на аукционе» обязана появиться
-- сама, а суммы - не остаться вчерашними.
function Tab:OnShow()
    Tab:Render()
end

return Tab
