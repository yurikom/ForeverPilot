-- ForeverPilot / UI/TabCharacter.lua
--
-- Раздел «Персонаж»: что аддон знает о персонаже - кто он, какие профессии,
-- что надето и зачаровано, сколько материалов под рукой. По этим данным
-- строятся советы; если здесь что-то неверно, неверны и они.
--
-- НА ЭКРАНЕ - САМИ ДАННЫЕ, БЕЗ РАССКАЗА О ТОМ, ОТКУДА ОНИ. Раньше у каждой
-- строки стояло «(из кеша)», а внизу были разделы «Откуда я всё это знаю» и
-- «Откуда берутся цены». Игрок назвал это лишним (2026-11-21: «мне не нужно
-- знать, откуда ты брал эти данные»). Всё это по-прежнему пишется в файл
-- диагностики (/fp diag).
--
-- Широкое окно - две колонки: слева персонаж, профессии и материалы, справа
-- экипировка. Узкое - одна, друг под другом.
local ADDON, ns = ...

local U = ns.Util
local W = ns.Widgets

local Tab = {}
ns.TabCharacter = Tab

Tab.PAD = 24
Tab.COL_GAP = 36
Tab.TWO_COL_MIN = 700        -- от этой ширины содержимого колонок две
Tab.COL_MAX = 520            -- шире этого колонка не растягивается
Tab.STAT_COL = 150           -- колонка значений в строках «подпись - значение»
Tab.TRIO_COL = 116           -- где начинается середина строки из трёх частей
Tab.ROW_H = W.STAT_H

-- Фракцию клиент отдаёт английским кодом («Horde»); на экране - по-русски.
Tab.FACTION = { Horde = "Орда", Alliance = "Альянс" }

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

-- Строка из трёх частей: подпись слева, текст в середине, короткая пометка у
-- правого края. Так стоят экипировка («Голова - Жемчужный венец - без чар») и
-- профессии («Портняжное дело - 80 из 82 рецептов - 225/225»). Середина
-- укорачивается под то, что осталось между подписью и пометкой.
local function trioRow(parent)
    local T = W.THEME
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(320, Tab.ROW_H)
    row.label = W.Label(row, "", W.FONT_SMALL, T.muted[1], T.muted[2], T.muted[3])
    row.label:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.label:SetWordWrap(false)
    row.middle = W.Label(row, "", W.FONT_SMALL, T.text[1], T.text[2], T.text[3])
    row.middle:SetWordWrap(false)
    row.meta = W.Label(row, "", W.FONT_SMALL, T.muted[1], T.muted[2], T.muted[3])
    row.meta:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.meta:SetJustifyH("RIGHT")
    row.meta:SetWordWrap(false)
    function row:Fill(label, middle, meta, col)
        local full = tonumber(self:GetWidth()) or 320
        self.meta:SetText(meta or "")
        local mw = tonumber(self.meta:GetStringWidth()) or 0
        col = col or Tab.TRIO_COL
        W.SetFitted(self.label, label or "", col - 10)
        self.middle:ClearAllPoints()
        self.middle:SetPoint("LEFT", self, "LEFT", col, 0)
        W.SetFitted(self.middle, middle or "",
            math.max(40, full - col - mw - ((mw > 0) and 12 or 0)))
    end
    return row
end

-- Builders reuse a single pool of rows so switching tabs does not leak frames.
function Tab:Row(kind, index)
    local key = kind .. index
    local w = self.widgets[key]
    if w then w:Show(); return w end
    local T = W.THEME
    if kind == "head" then
        w = W.SectionHeader(self.content, "", 400)
    elseif kind == "stat" then
        w = W.StatRow(self.content, "", "", 400)
        w.column = Tab.STAT_COL
    elseif kind == "trio" then
        w = trioRow(self.content)
    else
        w = W.Label(self.content, "", W.FONT_SMALL, T.dim[1], T.dim[2], T.dim[3])
    end
    self.widgets[key] = w
    return w
end

-- Ширина содержимого и колонок - от размера окна, а не от того, успел ли
-- клиент разложить рамки.
function Tab:Columns()
    local hostW = ns.MainFrame:HostNow()
    local width = math.max(260, hostW - 2 * Tab.PAD - 14)
    if width >= Tab.TWO_COL_MIN then
        local col = math.min(Tab.COL_MAX, math.floor((width - Tab.COL_GAP) / 2))
        return width, { { x = 0, w = col }, { x = col + Tab.COL_GAP, w = col } }
    end
    return width, { { x = 0, w = math.min(Tab.COL_MAX, width) } }
end

function Tab:Render()
    if not self.frame then return end
    for _, w in pairs(self.widgets) do w:Hide() end
    local T = W.THEME

    local snap = ns.CharacterScanner:Get()
    local width, cols = self:Columns()
    local count = { head = 0, stat = 0, trio = 0, note = 0 }
    local function take(kind)
        count[kind] = count[kind] + 1
        return self:Row(kind, count[kind])
    end

    -- Колонка: свои x, ширина и высота; строки ставятся сверху вниз.
    local function column(def)
        local c = { x = def.x, w = def.w, y = 0 }
        local function place(w, height, gapBefore)
            w:ClearAllPoints()
            w:SetPoint("TOPLEFT", self.content, "TOPLEFT", c.x, -(c.y + (gapBefore or 0)))
            c.y = c.y + (gapBefore or 0) + height
        end
        function c.head(text)
            local w = take("head")
            w:SetWidth(c.w)
            w.text:SetText(text)
            place(w, 26 + 8, (c.y > 0) and 14 or 0)
        end
        function c.stat(label, value, tone)
            local w = take("stat")
            w:SetWidth(c.w)
            local col = (tone == "warn" and T.warn) or (tone == "good" and T.good) or T.text
            w.value:SetTextColor(col[1], col[2], col[3])
            -- Нет значения - это «не знаю», а не прочерк: прочерк в словаре
            -- пустоты означает «такого не бывает» (см. ns.VOID).
            w:SetBoth(label, value or U.void(ns.VOID.UNKNOWN))
            place(w, Tab.ROW_H)
        end
        function c.trio(label, middle, meta, tone, col, bright)
            local w = take("trio")
            w:SetWidth(c.w)
            local mc = (tone == "warn" and T.warn) or (tone == "good" and T.good)
                or (tone == "accent" and T.accent) or T.muted
            w.meta:SetTextColor(mc[1], mc[2], mc[3])
            -- bright = true: главное - подпись (название профессии), середина
            -- приглушена; "muted": приглушено всё (пустой слот).
            local lc = (bright == true) and T.text or T.muted
            w.label:SetTextColor(lc[1], lc[2], lc[3])
            local tc = bright and T.muted or T.text
            w.middle:SetTextColor(tc[1], tc[2], tc[3])
            w:Fill(label, middle, meta, col)
            place(w, Tab.ROW_H)
        end
        function c.note(text, tone)
            local w = take("note")
            local col = (tone == "warn" and T.warn) or (tone == "good" and T.good) or T.dim
            w:SetTextColor(col[1], col[2], col[3])
            w:SetJustifyH("LEFT")
            local h = W.SetWrapped(w, text, c.w, W.LINE)
            place(w, h + 6, 4)
        end
        return c
    end

    local left = column(cols[1])
    local right = cols[2] and column(cols[2]) or left

    local function finish()
        self.content:SetSize(width, math.max(1, math.max(left.y, right.y) + 10))
        self.scroll:Refresh()
    end

    if not snap then
        left.head("Данные о персонаже ещё не собраны")
        left.note("Подождите секунду после входа в игру или нажмите «Обновить».")
        return finish()
    end

    -- Персонаж -----------------------------------------------------------
    left.head("Персонаж")
    left.stat("Имя", snap.name)
    left.stat("Уровень", snap.level and tostring(snap.level) or nil)
    left.stat("Класс", snap.className)
    left.stat("Раса и фракция", (snap.raceName or U.void(ns.VOID.UNKNOWN)) .. ", "
        .. (Tab.FACTION[snap.factionFile or ""] or snap.factionFile or U.void(ns.VOID.UNKNOWN)))
    if snap.spec then
        left.stat("Специализация", snap.spec)
    else
        left.stat("Специализация", "не определена", "warn")
    end
    left.stat("Веса характеристик",
        ns.StatWeights.SET_LABEL[snap.weightSetKey] or snap.weightSetKey)
    left.stat("Золото", U.money(snap.money, true))
    if snap.weightConf ~= ns.CONF.EXACT then
        left.note("По этим весам считается, какая вещь лучше. Поменять их можно"
            .. " в настройках.")
    end

    -- Профессии ----------------------------------------------------------
    left.head("Профессии")
    if #(snap.professions or {}) == 0 then
        left.note("Профессий не видно — советы по крафту работать не будут.", "warn")
    end
    for _, prof in ipairs(snap.professions or {}) do
        local skill, tone
        if prof.skillBroken or not prof.skill then
            skill, tone = "навык неизвестен", "warn"
        else
            -- Максимум - то, что сказала игра, или ничего: «225» и «225 из
            -- неизвестного максимума» ведут к разным решениям.
            skill = tostring(prof.skill)
            if prof.max and prof.max > 0 then
                skill = skill .. "/" .. prof.max
                if prof.skill >= prof.max then tone = "accent" end
            else
                skill = skill .. " из ?"
                tone = "warn"
            end
        end
        local recipes = ""
        local bucket = ns.RecipeBook:Bucket(prof.name)
        if bucket then
            local learned = 0
            for _, r in ipairs(bucket.list) do if r.learned then learned = learned + 1 end end
            -- ФОРМЫ СДВИНУТЫ НАРОЧНО, И ЭТО НЕ ОПЕЧАТКА. Слово стоит после «из
            -- N», то есть в родительном падеже: «из 1 рецепта», «из 2
            -- рецептов», «из 82 рецептов» (Tests/test_sense.lua это ловит).
            recipes = learned .. " из " .. #bucket.list .. " "
                .. U.plural(#bucket.list, "рецепта", "рецептов", "рецептов")
        elseif prof.gathering then
            recipes = "добыча"
        elseif prof.crafting then
            recipes = "рецепты не прочитаны"
        end
        -- Имя профессии - через U.profLabel: пока клиент молчит, оно приходит
        -- из чужого кеша по-английски.
        left.trio(U.profLabel(prof.name) or "?", recipes, skill, tone, Tab.STAT_COL, true)
    end
    for _, prof in ipairs(ns.RecipeBook.missingProfessions or {}) do
        left.note("Откройте один раз окно профессии «" .. tostring(U.profLabel(prof.name))
            .. "» — рецептов по ней ещё нет.", "warn")
    end

    -- Материалы ----------------------------------------------------------
    left.head("Материалы")
    local bagCount = U.count(snap.bags)
    left.stat("В сумках", bagCount .. " " .. U.plural(bagCount, "вид", "вида", "видов")
        .. " предметов")
    if snap.bank == nil then
        left.stat("В банке", "банк ещё не открывали", "warn")
        left.note("Откройте банк один раз: часть покупок из списка может"
            .. " оказаться не нужна.")
    else
        local bankCount = U.count(snap.bank)
        left.stat("В банке", bankCount .. " " .. U.plural(bankCount, "вид", "вида", "видов")
            .. " предметов")
    end
    for _, alt in ipairs(snap.alts or {}) do
        if not alt.isSelf then
            local kinds = U.count(alt.counts)
            left.stat("У " .. (alt.name or "?"),
                kinds .. " " .. U.plural(kinds, "вид", "вида", "видов")
                    .. " предметов, " .. U.money(alt.money))
        end
    end

    -- Профессии других персонажей: чтобы совет «это есть у другого персонажа»
    -- не был чёрным ящиком. Строки собирает Logic/Roster.lua.
    local roster = ns.Roster and ns.Roster:OtherCharacterLines() or {}
    if #roster > 0 then
        left.head("Другие персонажи")
        for _, line in ipairs(roster) do
            left.note(tostring(line.label))
            left.note(U.dropProvenance(tostring(line.value or "")), nil)
        end
    end

    -- Экипировка и чары ----------------------------------------------------
    right.head("Экипировка и чары")
    local rows, total = ns.GearAdvisor:Audit(snap)
    right.stat("Всё надетое вместе", U.benefit(total or 0))
    local bare, empty = 0, 0
    for _, row in ipairs(rows) do
        if row.empty then
            empty = empty + 1
            -- Пустой слот - приглушённо: это не вещь, а её отсутствие.
            right.trio(row.label, "пусто", "", nil, nil, "muted")
        else
            local meta, tone = "", nil
            if row.enchantable then
                if row.enchantID then
                    meta, tone = "чары есть", "good"
                else
                    meta, tone = "без чар", "warn"
                    bare = bare + 1
                end
            end
            right.trio(row.label, row.name or "?", meta, tone)
        end
    end
    if bare > 0 then
        right.note(bare .. " " .. U.plural(bare, "слот", "слота", "слотов")
            .. " без чар — что с этим делать, смотрите в разделе «Советы».")
    end
    if empty > 0 then
        right.note(empty .. " "
            .. U.plural(empty, "слот пуст", "слота пусты", "слотов пусты") .. ".")
    end

    return finish()
end

function Tab:OnShow() Tab:Render() end

return Tab
