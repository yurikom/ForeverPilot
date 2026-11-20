-- ForeverPilot / UI/TabNow.lua
--
-- The default tab. Zero clicks to an answer: the four priority profiles sit
-- directly above the list, the filter chips sit under them, and the list itself
-- is one ranked pile of cards of every kind.
local ADDON, ns = ...

local U = ns.Util
local W = ns.Widgets
local Card = ns.Card

local Tab = {}
ns.TabNow = Tab

-- РАЗМЕТКА ШАПКИ, ЧИСЛАМИ В ОДНОМ МЕСТЕ ----------------------------------
--
-- Игрок прислал скриншот, на котором кнопка фильтра «Золото» НАРИСОВАНА ПОВЕРХ
-- строки «75 рецептов известно • материалы по советам: 4з 34с»: строка с
-- числами стояла в одном ряду с кнопками фильтров и в этот ряд не умещалась.
--
-- Причина была в том, что ряд и строка делили одну полосу по горизонтали
-- ВСЛЕПУЮ: кнопки растут слева направо по своей ширине (а она зависит от
-- длины подписи и от шрифта клиента), строка прижата к правому краю и растёт
-- справа налево по длине текста. Ни одна из сторон не знала про другую, и
-- пересечение было вопросом длины слов.
--
-- Теперь каждая полоса своя, и считаются они одна из другой - как в
-- UI/Card.lua. Поделить полосу с кем-то ряд кнопок больше не может: под ним
-- нет никого, а проверка в Tests/test_nonsense.lua считает прямоугольники по
-- привязкам во всех состояниях мира и требует, чтобы полосы не пересекались.
Tab.PAD = 12
Tab.LABEL_H = 12             -- строка мелкого шрифта
Tab.PROFILE_H = 24           -- высота кнопки профиля
Tab.CHIP_H = 20              -- высота кнопки фильтра
Tab.GAP = 6
Tab.PROFILE_TOP = Tab.PAD + 18                                   -- 30
Tab.CHIPS_TOP = Tab.PROFILE_TOP + Tab.PROFILE_H + Tab.GAP        -- 60
Tab.STATS_TOP = Tab.CHIPS_TOP + Tab.CHIP_H + 4                   -- 84
Tab.LIST_TOP = Tab.STATS_TOP + Tab.LABEL_H + Tab.GAP             -- 102
Tab.STRIP_H = 14             -- строка над списком: ровно одна

-- Подпись к строке над списком и путь к подробностям - словами, в одном месте.
Tab.STRIP_TITLE = "Что не показано и почему"
Tab.DETAILS_HINT = "Подробнее — наведите мышь."

function Tab:Build(parent)
    if self.frame then return self.frame end
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)
    self.frame = frame

    -- Profile row: four buttons above the list, not buried in settings.
    local profileLabel = W.Label(frame, "Что для вас сейчас важнее:", W.FONT_SMALL, 0.62, 0.62, 0.62)
    profileLabel:SetPoint("TOPLEFT", Tab.PAD, -Tab.PAD)
    self.profileLabel = profileLabel

    self.profileChips = {}
    local x = Tab.PAD
    for _, key in ipairs(ns.PROFILE_ORDER) do
        local chip = W.Chip(frame, ns.PROFILE_LABEL[key], function()
            ns.Config:SetProfile(key)
            Tab:SyncProfiles()
            ns.MainFrame:Rebuild()
        end, Tab.PROFILE_H)
        chip:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -Tab.PROFILE_TOP)
        chip.tooltipTitle = ns.PROFILE_LABEL[key]
        chip.tooltipText = ns.PROFILE_TIP[key]
        x = x + chip:GetWidth() + 6
        self.profileChips[key] = chip
    end

    -- Filter chips: the same list, narrowed. "Золото" and "Крафт" are chips,
    -- not tabs, so the ranking stays shared.
    self.filterChips = {}
    local fx = Tab.PAD
    for _, key in ipairs(ns.CHIP_ORDER) do
        local chip = W.Chip(frame, ns.CHIP_LABEL[key], function()
            ns.Config:SetChip(key)
            Tab:SyncChips()
            Tab:Render()
        end, Tab.CHIP_H)
        chip:SetPoint("TOPLEFT", frame, "TOPLEFT", fx, -Tab.CHIPS_TOP)
        fx = fx + chip:GetWidth() + 5
        self.filterChips[key] = chip
    end

    -- Строка статистики - своей полосой под кнопками, а не рядом с ними.
    self.summary = W.Label(frame, "", W.FONT_SMALL, 0.55, 0.55, 0.55)
    self.summary:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -Tab.PAD, -Tab.STATS_TOP)
    self.summary:SetJustifyH("RIGHT")
    self.summary:SetWordWrap(false)

    local scroll, content = W.ScrollArea(frame)
    scroll:SetPoint("TOPLEFT", Tab.PAD, -Tab.LIST_TOP)
    scroll:SetPoint("BOTTOMRIGHT", -(Tab.PAD + 22), Tab.PAD)
    self.scroll, self.content = scroll, content

    self.empty = W.EmptyState(frame,
        "Пока советовать нечего",
        "Это не ошибка. Ниже написано, чего мне не хватает, чтобы начать.",
        nil, nil)
    self.empty:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
    self.empty:SetPoint("RIGHT", scroll, "RIGHT", -4, 0)
    self.empty:Hide()

    -- A short list leaves most of a 560px window blank, and blank space answers
    -- nothing. The same per-branch report the empty state shows goes under the
    -- cards: four cards plus "why there are only four" is a more useful screen
    -- than four cards and a void. Parented to the scroll child so it scrolls
    -- with the list instead of floating over it.
    self.note = W.EmptyState(content, "Почему советов так мало", "", nil, nil)
    self.note:Hide()

    -- СТРОКА НАД СПИСКОМ - ОДНА, КОРОТКАЯ, И ЭТО ТЕПЕРЬ ПРАВИЛО.
    --
    -- Здесь стояла простыня: четыре абзаца подряд (порог мелкой выгоды с
    -- разбором по видам советов, профиль, длина списка, инструкция про окно
    -- профессий) - пять строк текста до первого совета. Игрок сказал про это
    -- дословно: «всё должно быть кратко, понятно и без всяких хрени, воды, я
    -- тебе сказал это уже». И он прав: это наш регресс - убирая повторы из
    -- карточек, общие фразы перенесли сюда, и здесь они выросли.
    --
    -- Осталась ОДНА строка: часть советов не показана, и сколько их.
    -- Подробности (какой порог, по чему он выбран, где снимается, что именно
    -- убрано, почему у советов нет кнопки) отвечают на вопрос, который игрок
    -- ещё не задал, - поэтому они под курсором, а не над списком.
    --
    -- Молчанием это не становится, и это проверяется: строка есть всегда, когда
    -- что-то не показано, число в ней есть, и путь к подробностям назван в ней
    -- самой (Tests/test_vanish.lua, Tests/test_nonsense.lua).
    local strip = CreateFrame("Frame", nil, content)
    strip:SetHeight(Tab.STRIP_H)
    strip:EnableMouse(true)
    strip.text = W.Label(strip, "", W.FONT_SMALL, 1.00, 0.80, 0.40)
    strip.text:SetPoint("LEFT", strip, "LEFT", 0, 0)
    strip.text:SetJustifyH("LEFT")
    strip.text:SetWordWrap(false)
    strip:SetScript("OnEnter", function(self2)
        W.ShowTip(self2, Tab.STRIP_TITLE, self2.details or {})
    end)
    strip:SetScript("OnLeave", W.HideTip)
    strip:Hide()
    self.strip = strip

    Tab:SyncProfiles()
    Tab:SyncChips()
    return frame
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

-- Render ----------------------------------------------------------------

function Tab:Render()
    if not self.frame then return end
    local chip = ns.Config:Chip()
    local cards = ns.ActionEngine:Filtered(chip)
    local meta = ns.ActionEngine.meta or {}

    -- Ширина списка - то, по чему укорачиваются строки карточек. Ноль значит
    -- «клиент ещё не разложил окно»: мерить нечем, и тогда берётся обычная
    -- ширина окна, а не ноль - иначе от строк останутся огрызки.
    local width = tonumber(self.scroll:GetWidth()) or 0
    if width <= 0 then width = 640 end
    local y = 0
    local shown = 0

    -- ЧТО НЕ ПОКАЗАНО - ОДНОЙ СТРОКОЙ, ДО СОВЕТОВ. Подробности - под курсором.
    local total = #(ns.ActionEngine.cards or {})
    local notices = self:Notices(meta, chip, #cards, total, cards)
    local variants = self:NoticeShort(meta, chip, #cards, total)
    if #cards > 0 and #variants > 0 then
        local room = math.max(120, width - 12)
        self.strip:SetWidth(room)
        self.strip.details = notices
        W.SetFittedFrom(self.strip.text, variants, room)
        self.strip:ClearAllPoints()
        self.strip:SetPoint("TOPLEFT", self.content, "TOPLEFT", 6, -4)
        self.strip:Show()
        y = Tab.STRIP_H + 10
    else
        -- Подробности живут ровно столько, сколько видна строка: иначе
        -- подсказка переживёт сообщение, к которому относилась.
        self.strip.details = nil
        self.strip:Hide()
    end

    for i, card in ipairs(cards) do
        shown = shown + 1
        local row = Card.Acquire(self.content, shown)
        row:SetWidth(width)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -y)
        Card.Fill(row, card)
        y = y + Card.HEIGHT + 4
    end
    Card.ReleaseFrom(shown + 1)

    -- Under the cards: what the silent branches were missing. Only when there
    -- is something to say and the list did not already fill the window. Not
    -- computed at all when the list is empty - the empty state below asks for
    -- the same lines itself, and building them twice per render is waste.
    local roomLeft = (self.scroll:GetHeight() or 400) - y
    local gaps = (shown > 0 and roomLeft > 90) and self:BranchGaps(meta) or {}
    if shown > 0 and #gaps > 0 and roomLeft > 90 then
        self.note.body:SetText(table.concat(gaps, "\n"))
        local h = math.max(60, 44 + #gaps * 15)
        self.note:SetHeight(h)
        self.note:ClearAllPoints()
        self.note:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -(y + 10))
        self.note:SetWidth(math.max(120, width - 4))
        self.note:Show()
        y = y + h + 10
    else
        self.note:Hide()
    end

    self.content:SetSize(width, math.max(1, y))

    if shown == 0 then
        self.empty:Show()
        local title, body = self:EmptyReason(meta, chip, #(ns.ActionEngine.cards or {}))
        -- Над пустым списком полоски нет, а сказать то же самое надо: всё, что
        -- не показано по причине, которую EmptyReason сама не называет.
        if #notices > 0 then
            body = tostring(body or "") .. "\n" .. table.concat(notices, "\n")
        end
        self.empty.title:SetText(title)
        self.empty.body:SetText(body)
        -- The window is tall and the panel was a fixed 84px, so a body that
        -- lists six branches was cut off halfway. Grow to fit what we wrote.
        local lines = 1
        for _ in tostring(body or ""):gmatch("\n") do lines = lines + 1 end
        self.empty:SetHeight(math.max(84, 46 + lines * 15))
    else
        self.empty:Hide()
    end

    -- The line on the right that says what this list is built on.
    local bits = {}
    bits[#bits + 1] = (meta.learnedRecipes or 0) .. " "
        .. U.plural(meta.learnedRecipes or 0, "рецепт", "рецепта", "рецептов") .. " известно"
    if meta.shoppingLines and meta.shoppingLines > 0 then
        -- «ЗАКУПКА 5з» - ЭТО НЕ ФРАЗА, А ПОМЕТКА ДЛЯ ТОГО, КТО ЗНАЕТ.
        --
        -- Игрок прочитал «75 рецептов известно • закупка 5з» и спросил, что
        -- это за деньги: его собственные? уже потраченные? Это сумма
        -- материалов, которых не хватает на советы из списка, - то есть
        -- сколько придётся потратить, если делать всё, что я насоветовал.
        -- Так и сказано; «(неполная)» заменено на причину, а не на пометку.
        local total, conf = meta.shoppingTotal, meta.shoppingConf
        bits[#bits + 1] = "материалы по советам: " .. U.money(total)
            .. (conf == ns.CONF.UNKNOWN and " и больше (часть цен не знаю)" or "")
    end
    local ps = meta.priceSources
    if ps and not ps.auctionatorAvailable then
        bits[#bits + 1] = "цен аукциона нет"
    end
    -- Hidden cards are invisible by definition, so the count has to be said
    -- somewhere the player will see it without having to suspect anything.
    if (meta.hiddenByDismissal or 0) > 0 then
        bits[#bits + 1] = "скрыто " .. meta.hiddenByDismissal .. " (/fp show)"
    end
    -- Строка статистики - тоже числа, и резать их нельзя. Варианты - это сама
    -- строка и её части с конца: ширину она делит только с отступами.
    local stats = {}
    for i = #bits, 1, -1 do
        stats[#stats + 1] = table.concat(bits, "  •  ", 1, i)
            .. ((i < #bits) and ("  " .. U.MORE_MARK) or "")
    end
    W.SetFittedFrom(self.summary, stats, math.max(120, width))
end

-- ОДНА СТРОКА НАД СПИСКОМ: СКОЛЬКО СОВЕТОВ НЕ ПОКАЗАНО.
--
-- Три сообщения о скрытом - порог мелкой выгоды, профиль, длина списка - это
-- ОДНА мысль «часть советов не на экране», а не три абзаца. Игроку здесь нужен
-- факт и число; какой именно порог, как он выбран и где снимается - ответ на
-- вопрос, который он ещё не задал, и лежит он в подробностях под курсором
-- (Tab:Notices) и в настройках.
--
-- Возвращает варианты строки от полного к короткому: первый - с причинами,
-- последний - только факт, число и путь к подробностям. Путь назван в КАЖДОМ
-- варианте: сокращая, нельзя превратить объявление в молчание.
--
-- Скрытое самим игроком здесь не считается: его число стоит в строке
-- статистики справа, а когда скрыто всё - об этом отдельная карточка.
function Tab:NoticeShort(meta, chip, shown, total)
    meta = meta or {}
    shown, total = tonumber(shown) or 0, tonumber(total) or 0
    local hidden, causes = 0, {}
    local function cause(n, text)
        n = tonumber(n) or 0
        if n <= 0 then return end
        hidden = hidden + n
        causes[#causes + 1] = text
    end
    if chip and chip ~= ns.CHIP.ALL and shown < total then
        cause(total - shown, "фильтр «" .. (ns.CHIP_LABEL[chip] or tostring(chip)) .. "»")
    end
    cause(meta.moneyFloorDropped, "порог выгоды")
    cause(meta.profileDropped,
        "профиль «" .. (ns.PROFILE_LABEL[ns.Config:Profile()] or "?") .. "»")
    local generated = tonumber(meta.generated) or 0
    if total > 0 then cause(generated - total, "длина списка") end
    if hidden <= 0 then return {}, 0 end

    -- Число стоит после двоеточия, а не перед словом: так строка верна при
    -- любом числе и не требует согласования («1 совет», «2 совета», «5
    -- советов» - три разных слова на одном месте).
    local head = "Не показано советов: " .. hidden
    local out = {}
    if #causes > 0 then
        out[#out + 1] = head .. " — " .. table.concat(causes, ", ") .. ". " .. Tab.DETAILS_HINT
    end
    out[#out + 1] = head .. ". " .. Tab.DETAILS_HINT
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
-- Про скрытые игроком советы здесь НЕ говорится: их число стоит в сводке
-- справа, а когда скрыто всё - об этом отдельная карточка.
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
            .. " Загляните на вкладку «Мой персонаж» — там видно, что именно я прочитал."
    end

    -- A. There really are cards; this chip just lets none of them through.
    -- Guarded by `total > 0`, which is the whole point of this rewrite.
    if total > 0 then
        if chip ~= ns.CHIP.ALL then
            return "В этом фильтре пусто",
                "Советов у меня " .. total .. ", но ни один не подходит под фильтр «"
                .. (ns.CHIP_LABEL[chip] or chip) .. "». Нажмите «Всё»,"
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
    lines[#lines + 1] = "Можно попробовать другой профиль приоритетов над списком."
    return "Пока советовать нечего", table.concat(lines, "\n")
end

function Tab:OnShow()
    Tab:SyncProfiles()
    Tab:SyncChips()
    Tab:Render()
end

return Tab
