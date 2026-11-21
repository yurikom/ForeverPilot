-- ForeverPilot / Tests/test_window.lua
--
-- БОЛЬШОЕ ОКНО ПО ОБРАЗЦУ POLESTAR: ПОЛОСА РАЗДЕЛОВ, ФИЛЬТР СО СЧЁТЧИКАМИ, СПИСОК
-- В ОДНУ СТРОКУ НА СОВЕТ И КАРТОЧКА СОВЕТА С ОДНОЙ ЗОЛОТОЙ КНОПКОЙ.
--
-- Жалоба игрока (маг 32 ур., 2026-11-21, скриншот окна с фильтром «Можно
-- сейчас» и пустым списком): «Что-то вообще херовый как-то у тебя UX. Непонятно,
-- на какую кнопку что, куда нажимать… посмотри, как работает аддон Polestar. Вот
-- там всё продумано, всё красивенько, всё понятно, куда нажимать. Сделай точно
-- так же». И следом: «Смотри только, чтобы ничего не фризило».
--
-- Что здесь закреплено:
--   1. щелчок по строке списка ВЫБИРАЕТ совет и ничего не запускает; действие -
--      только на кнопке в карточке справа;
--   2. золотая кнопка на экране одна;
--   3. в карточке совета всё, что она решила показать (Card.Sheet), показано
--      целиком, и ничто там ни на что не налезает, ни в обычном окне, ни в
--      самом маленьком; оговорок об источнике чисел в ней нет;
--   4. счётчики фильтра слева - это ровно то, что фильтр покажет;
--   5. окно открыли, а под запомненный фильтр не попало ничего - показывается
--      всё (тот самый скриншот);
--   6. выбор совета переживает пересчёт и не вызывает его: щелчок по строке не
--      трогает движок - иначе по списку нельзя было бы ходить без рывков;
--   7. прежний сохранённый размер окна (720 на 560) меньше нового минимума - окно
--      открывается размером по умолчанию, а не зажатым;
--   8. свой значок, свой шрифт и свои картинки ставятся только когда клиент
--      уже видит новые файлы - до перезапуска игры окно рисуется шрифтами игры
--      и без значков, а не зелёными квадратами и пустыми строками;
--   9. окно не бывает больше экрана: ни при растягивании, ни при открытии с
--      сохранённым размером (игрок растянул его за край и не смог вернуть).
local H = ...
local S = assert(loadfile((H.ROOT or ".") .. "/Tests/uistub.lua"))()

return function()

local function fresh(prepare, opts)
    local env = S.load(H, opts)
    if prepare then prepare(env) end
    S.populate(env, H)
    return env
end

local function open(env, width, height)
    local ns = env.ns
    ns.MainFrame:Build()
    ns.MainFrame:Select("NOW")
    S.layout(env, width, height)
    ns.MainFrame:RenderActive()
    return ns
end

local function shownRows(ns)
    local rows = {}
    for _, row in ipairs(ns.Card.pool) do
        if row.__shown and row.card then rows[#rows + 1] = row end
    end
    return rows
end

-- Видимые золотые кнопки во всём окне.
local function primaryButtons(env, root)
    local out = {}
    local function visible(f)
        local node, seen = f, {}
        while node do
            if seen[node] then return false end
            seen[node] = true
            if node == root then return true end
            if not node.__shown then return false end
            node = node.__parent
        end
        return false
    end
    for _, f in ipairs(env.world.frames) do
        if f.__type == "Button" and rawget(f, "primary") and visible(f) then
            out[#out + 1] = f
        end
    end
    return out
end

H.suite("Окно: щелчок по строке выбирает совет и ничего не запускает")
do
    local env = fresh()
    local ns = open(env)
    local rows = shownRows(ns)
    H.ok(#rows >= 4, "советов в списке: " .. #rows)

    -- Первый совет выбран сразу: ответ виден без единого щелчка.
    H.eq(ns.Detail.card, rows[1].card, "первый совет уже открыт в карточке справа")
    H.eq(rows[1].selected, true, "и его строка подсвечена")

    local activated = 0
    local realActivate = ns.Card.Activate
    ns.Card.Activate = function(...) activated = activated + 1; return realActivate(...) end

    env.said = {}
    local before = S.plain(ns.Detail.title:GetText() or "")
    local target = rows[#rows]
    target.__scripts.OnClick(target, "LeftButton")
    H.eq(ns.Detail.card, target.card, "щелчок открыл в карточке именно этот совет")
    H.eq(S.plain(ns.Detail.title:GetText() or ""), S.plain(tostring(target.card.title)),
        "в карточке его название целиком")
    H.ok(S.plain(ns.Detail.title:GetText() or "") ~= before, "карточка сменилась")
    H.eq(activated, 0, "действие совета при этом не запущено")
    H.eq(#env.said, 0, "и в чат ничего не написано")

    -- Подсвечена ровно одна строка - выбранная.
    local selected = 0
    for _, row in ipairs(shownRows(ns)) do
        if row.selected then selected = selected + 1 end
    end
    H.eq(selected, 1, "подсвечена ровно одна строка")
    H.eq(target.selected, true, "и это та, по которой щёлкнули")

    -- В строках списка кнопок нет вовсе.
    for _, row in ipairs(rows) do
        H.eq(rawget(row, "action"), nil, "в строке «"
            .. ns.Util.truncate(tostring(row.card.title), 24) .. "» кнопки нет")
    end

    -- А кнопка карточки делает то, что на ней написано.
    local withButton
    for _, row in ipairs(rows) do
        if not withButton and S.actionOf(ns, row) then withButton = row end
    end
    H.ok(withButton ~= nil, "есть совет с кнопкой действия")
    if withButton then
        local button = S.actionOf(ns, withButton)
        activated = 0
        button.__scripts.OnClick(button)
        H.eq(activated, 1, "нажатие кнопки карточки запускает действие совета - один раз")
        H.eq(S.plain(button.text:GetText() or ""), ns.Card.ActionLabel(withButton.card),
            "и подпись на ней та, которую даёт совет")
    end
    ns.Card.Activate = realActivate
end

H.suite("Окно: золотая кнопка на экране одна")
do
    local env = fresh()
    local ns = open(env)
    local checked, worst = 0, 0
    for _, row in ipairs(shownRows(ns)) do
        S.pick(ns, row)
        local gold = primaryButtons(env, ns.MainFrame.frame)
        checked = checked + 1
        if #gold > worst then worst = #gold end
        H.ok(#gold <= 1, "«" .. ns.Util.truncate(tostring(row.card.title), 28)
            .. "»: золотых кнопок " .. #gold)
        -- Если у совета есть что нажать, золотая кнопка есть.
        local detail = ns.Detail
        if detail.action.__shown or detail.route.__shown then
            H.eq(#gold, 1, "   и раз нажать есть что - она есть")
        end
    end
    H.ok(checked >= 4, "советов проверено: " .. checked)
    H.ok(worst <= 1, "больше одной золотой кнопки не было ни разу")

    -- И на остальных разделах золотая кнопка тоже не больше чем одна (в
    -- «Крафте» это «Искать на аукционе», когда аукцион открыт).
    for _, def in ipairs(ns.MainFrame.TABS) do
        if def.key ~= "NOW" then
            ns.MainFrame:Select(def.key)
            ns.MainFrame:RenderActive()
            H.ok(#primaryButtons(env, ns.MainFrame.frame) <= 1,
                "раздел «" .. def.label .. "»: золотых кнопок не больше одной")
        end
    end
end

-- Части карточки, которые сейчас на экране, с прямоугольниками: один перечень
-- на все проверки (Tests/uistub.lua, S.detailParts).
local function detailParts(ns)
    return S.detailParts(ns)
end

-- Сверка разметки карточки для всех советов списка при нескольких размерах
-- окна. Одна и та же для обоих видов окна: шрифтами игры (до перезапуска) и
-- своим шрифтом со значками (после).
local function checkDetailGeometry(env, ns, label)
    local sizes = { { 980, 600, "обычное окно" }, { 1280, 760, "большое окно" },
                    { ns.MainFrame.MIN_WIDTH, ns.MainFrame.MIN_HEIGHT, "самое маленькое окно" } }
    for _, size in ipairs(sizes) do
        S.layout(env, size[1], size[2])
        ns.MainFrame:RenderActive()
        local _, hostH = ns.MainFrame.HostSize(size[1], size[2])
        local clash, outside, checked = {}, {}, 0
        for _, row in ipairs(shownRows(ns)) do
            S.pick(ns, row)
            local parts = detailParts(ns)
            local title = ns.Util.truncate(tostring(row.card.title), 24)
            for i = 1, #parts do
                local one = parts[i]
                if not one.rect then
                    outside[#outside + 1] = "«" .. title .. "»: «" .. one.name .. "» ни к чему не привязано"
                else
                    if one.rect.left < -0.5 or one.rect.right > ns.TabNow.DETAIL_W + 0.5
                        or one.rect.top > 0.5 or one.rect.bottom < -hostH - 0.5 then
                        outside[#outside + 1] = "«" .. title .. "»: «" .. one.name .. "» за краем карточки ("
                            .. string.format("%.0f..%.0f по высоте при %d, %.0f..%.0f по ширине",
                                -one.rect.top, -one.rect.bottom, hostH, one.rect.left, one.rect.right) .. ")"
                    end
                    for j = i + 1, #parts do
                        local two = parts[j]
                        if two.rect then
                            checked = checked + 1
                            local ox, oy = S.rectOverlap(one.rect, two.rect)
                            if ox > 0 and oy > 0 then
                                clash[#clash + 1] = "«" .. title .. "»: «" .. one.name .. "» и «"
                                    .. two.name .. "» на " .. string.format("%.0f x %.0f", ox, oy)
                            end
                        end
                    end
                end
            end
        end
        local where = label .. ", " .. size[3]
        H.ok(checked > 40, where .. " " .. size[1] .. "x" .. size[2] .. ": пар сверено " .. checked)
        H.eq(#clash, 0, where .. ": ничто ни на что не налезает"
            .. ((#clash > 0) and ("  <- " .. table.concat(clash, "; ", 1, math.min(4, #clash))) or ""))
        H.eq(#outside, 0, where .. ": всё лежит внутри карточки"
            .. ((#outside > 0) and ("  <- " .. table.concat(outside, "; ", 1, math.min(4, #outside))) or ""))
    end
end

H.suite("Окно: в карточке совета ничто ни на что не налезает")
do
    -- Шрифтами игры и без значков - так окно выглядит до перезапуска игры.
    local env = fresh()
    local ns = open(env)
    H.eq(ns.Widgets.ready, false, "своих файлов клиент не видит: окно на шрифтах игры")
    checkDetailGeometry(env, ns, "шрифты игры")

    -- И своим шрифтом со значками - так оно выглядит после перезапуска.
    local env2 = fresh(nil, { media = true })
    local ns2 = open(env2)
    H.eq(ns2.Widgets.ready, true, "свои файлы клиент видит: шрифт и значки свои")
    checkDetailGeometry(env2, ns2, "свой шрифт")
end

-- Слова, которыми аддон рассказывает, откуда число и насколько ему верить.
-- На экране советов их быть не должно (жалоба игрока 2026-11-21: «мне не нужно
-- знать, откуда ты брал эти данные»).
local PROVENANCE = { "из кеша", "кеш", "возраст неизвестен", "не стареет", "час назад",
                     "дней назад", "дня назад", "день назад", "Достоверность",
                     "Место в общем списке", "выборка короткая", "сбор аукциона",
                     "Откуда числа", "наблюдений" }

H.suite("Окно: в карточке совета показано всё, что она решила показать")
do
    local env = fresh()
    local ns = open(env)
    local checked, withRows, withBlocks = 0, 0, 0
    for _, row in ipairs(shownRows(ns)) do
        local card = row.card
        S.pick(ns, row)
        local d = ns.Detail
        local sheet = ns.Card.Sheet(card)
        local name = ns.Util.truncate(tostring(card.title), 24)
        H.eq(S.plain(d.title:GetText() or ""), S.plain(tostring(card.title or "")),
            "«" .. name .. "»: название целиком")
        if tostring(card.benefit or "") ~= "" then
            local shown = d.benefit.__shown and d.benefit.text:GetText()
                or (d.benefitLine.__shown and d.benefitLine:GetText()) or ""
            H.eq(S.plain(shown), S.plain(tostring(card.benefit)),
                "«" .. name .. "»: выгода целиком")
        end
        -- Тексты - ровно те, что собрала Card.Sheet, без обрезки по высоте.
        for _, part in ipairs({ { "сомнение", sheet.warn, d.warn }, { "суть", sheet.lead, d.lead },
                                { "что сделать", sheet.need, d.need } }) do
            if part[2] ~= "" then
                H.eq(part[3].__shown, true, "«" .. name .. "»: «" .. part[1] .. "» показано")
                H.eq(S.plain(part[3]:GetText() or ""), S.plain(part[2]), "   и целиком")
            else
                H.eq(part[3].__shown, false, "«" .. name .. "»: пустого «" .. part[1] .. "» на экране нет")
            end
        end
        -- Строки «подпись - значение»: все, по порядку.
        for i, want in ipairs(sheet.rows) do
            local slot = d.rows[i]
            H.ok(slot ~= nil and slot.value.__shown, "«" .. name .. "»: строка «" .. want.label .. "» показана")
            if slot then
                H.eq(S.plain(slot.label:GetText() or ""), want.label, "   подпись та же")
                H.eq(S.plain(slot.value:GetText() or ""), S.plain(want.value), "   и значение целиком")
            end
        end
        if #sheet.rows > 0 then withRows = withRows + 1 end
        -- Блоки покупок: в обычном окне помещаются все позиции.
        local lines = 0
        for _, block in ipairs(sheet.blocks) do lines = lines + #block.lines end
        local shownLines = 0
        for _, item in ipairs(d.items) do
            if item.left.__shown then shownLines = shownLines + 1 end
        end
        H.eq(shownLines, lines, "«" .. name .. "»: позиций покупки показано столько, сколько есть (" .. lines .. ")")
        H.eq(d.more.__shown, false, "   и строки «и ещё N» нет")
        if lines > 0 then withBlocks = withBlocks + 1 end
        -- Кнопка есть - значит, на ней подпись совета; кнопки нет у совета про
        -- рецепт - значит, на её месте сказано, что сделать самому.
        if d.action.__shown then
            H.eq(S.plain(d.action.text:GetText() or ""), ns.Card.ActionLabel(card),
                "«" .. name .. "»: на кнопке подпись этого совета")
        elseif card.action and card.action.kind == "findRecipe" then
            H.eq(d.note.__shown, true, "«" .. name .. "»: вместо кнопки сказано, что сделать")
        end
        -- И ни в одной части карточки нет рассказа о том, откуда число.
        for _, part in ipairs(d:Shown()) do
            local text = S.plain(part.fs:GetText() or "")
            for _, word in ipairs(PROVENANCE) do
                H.eq(text:find(word, 1, true), nil, "«" .. name .. "»: в «" .. part.role
                    .. "» нет слов «" .. word .. "»: " .. ns.Util.truncate(text, 60))
            end
        end
        checked = checked + 1
    end
    H.ok(checked >= 4, "советов проверено: " .. checked)
    H.ok(withRows >= 1, "и среди них есть советы со строками «подпись - значение»: " .. withRows)
    H.ok(withBlocks >= 1, "и с блоком покупок: " .. withBlocks)
end

H.suite("Окно: в низком окне длинный список покупок не вытесняет то, что надо сделать")
do
    local env = fresh()
    local ns = open(env, nil, nil)
    S.layout(env, ns.MainFrame.MIN_WIDTH, ns.MainFrame.MIN_HEIGHT)
    ns.MainFrame:RenderActive()
    local shopping = {}
    for i = 1, 14 do
        shopping[i] = { itemID = 2589, qty = i, unit = 50, subtotal = 50 * i, src = "auctionator" }
    end
    local card = {
        kind = ns.KIND.CRAFT_MAT, key = "test:low", title = "Скрафтить: Очень нужная вещь",
        benefit = "+1 навык", benefitKind = "skill",
        why = "Нужна для трёх советов сразу.",
        need = "Торговец: Кварц, Тернистая долина, 34.0 76.0.",
        action = { kind = "noop" },
        plan = { ready = false, cost = 5250, crafts = {}, shopping = shopping },
    }
    ns.TabNow:SelectCard(card)
    local d = ns.Detail
    local _, hostH = ns.MainFrame:HostNow()
    H.eq(d.need.__shown, true, "фраза с торговцем на экране")
    H.eq(S.plain(d.need:GetText() or ""), card.need, "и целиком, с координатами")
    local shownLines, lastBottom = 0, 0
    for _, item in ipairs(d.items) do
        if item.left.__shown then
            shownLines = shownLines + 1
            local r = S.rectOf(item.left, d.frame)
            if r and r.bottom < lastBottom then lastBottom = r.bottom end
        end
    end
    H.ok(shownLines >= 1 and shownLines < #shopping,
        "позиций покупки показано сколько влезло: " .. shownLines .. " из " .. #shopping)
    H.eq(d.more.__shown, true, "и сказано, сколько не влезло")
    H.ok(S.plain(d.more:GetText() or ""):find(tostring(#shopping - shownLines), 1, true) ~= nil,
        "числом: " .. S.plain(d.more:GetText() or ""))
    local needRect, moreRect = S.rectOf(d.need, d.frame), S.rectOf(d.more, d.frame)
    H.ok(moreRect.bottom >= needRect.top - 0.5, "список кончается выше, чем начинается эта фраза")
    H.ok(needRect.bottom >= -hostH, "и всё это внутри карточки")
end

H.suite("Окно: счётчики фильтра — ровно то, что фильтр покажет")
do
    local env = fresh()
    local ns = open(env)
    local tab = ns.TabNow
    for _, key in ipairs(ns.CHIP_ORDER) do
        local row = tab.filterChips[key]
        local want = #ns.ActionEngine:Filtered(key)
        H.eq(tonumber(row.count:GetText()), want,
            "«" .. ns.CHIP_LABEL[key] .. "»: счётчик " .. tostring(row.count:GetText()))
        -- И щелчок показывает столько же строк.
        row.__scripts.OnClick(row)
        H.eq(ns.Config:Chip(), key, "   щелчок выбрал этот фильтр")
        H.eq(#shownRows(ns), want, "   и в списке столько же советов")
        H.eq(row.selected, true, "   строка фильтра подсвечена")
        H.eq(S.plain(tab.heading:GetText() or ""),
            tab.HEADING[key] or ns.CHIP_LABEL[key], "   и название стоит в шапке")
        -- Разделы списка в сумме дают то же число.
        local inSections = 0
        for _, sec in ipairs(tab.sections) do
            if sec.__shown then inSections = inSections + (tonumber(sec.count:GetText()) or 0) end
        end
        H.eq(inSections, want, "   счётчики разделов в сумме дают то же")
    end
    ns.Config:SetChip(ns.CHIP.ALL)

    -- Профиль: выбран ровно один, и щелчок его меняет.
    for _, profile in ipairs(ns.PROFILE_ORDER) do
        local row = tab.profileChips[profile]
        row.__scripts.OnClick(row)
        local selected = 0
        for _, other in pairs(tab.profileChips) do
            if other.selected then selected = selected + 1 end
        end
        H.eq(selected, 1, "профиль «" .. ns.PROFILE_LABEL[profile] .. "»: выбран ровно один")
        H.eq(row.selected, true, "   и это он")
    end
end

H.suite("Окно: открыли, а под запомненный фильтр не попало ничего — показано всё")
do
    -- Тот самый скриншот: фильтр «Можно сейчас», ноль советов, и ни слова о
    -- том, что остальные лежат под «Всё».
    local env = fresh()
    local ns = env.ns
    local empty
    for _, key in ipairs(ns.CHIP_ORDER) do
        if key ~= ns.CHIP.ALL and #ns.ActionEngine:Filtered(key) == 0 then empty = empty or key end
    end
    if not empty then
        -- В этом мире пустого фильтра нет - делаем его: прячем всё, что под
        -- «Чары».
        empty = "ENCHANT"
        local keep = {}
        for _, card in ipairs(ns.ActionEngine.cards) do
            if not ns.CHIP_KINDS.ENCHANT[card.kind] then keep[#keep + 1] = card end
        end
        ns.ActionEngine.cards = keep
    end
    H.ok(#ns.ActionEngine.cards > 0, "советы есть: " .. #ns.ActionEngine.cards)
    H.eq(#ns.ActionEngine:Filtered(empty), 0, "под «" .. ns.CHIP_LABEL[empty] .. "» — ни одного")
    ns.Config:SetChip(empty)
    H.eq(ns.TabNow:LeaveEmptyFilter(), true, "пустой фильтр при открытии заменён")
    H.eq(ns.Config:Chip(), ns.CHIP.ALL, "на «Всё»")

    -- Непустой фильтр не трогается: его игрок выбрал сам.
    local full
    for _, key in ipairs(ns.CHIP_ORDER) do
        if key ~= ns.CHIP.ALL and #ns.ActionEngine:Filtered(key) > 0 then full = full or key end
    end
    H.ok(full ~= nil, "непустой фильтр есть")
    if full then
        ns.Config:SetChip(full)
        H.eq(ns.TabNow:LeaveEmptyFilter(), false, "непустой фильтр оставлен как есть")
        H.eq(ns.Config:Chip(), full, "«" .. ns.CHIP_LABEL[full] .. "» на месте")
    end

    -- Советов нет вовсе - менять не на что, и фильтр не трогается: пустой
    -- экран тогда объясняет себя сам.
    ns.ActionEngine.cards = {}
    ns.Config:SetChip(empty)
    H.eq(ns.TabNow:LeaveEmptyFilter(), false, "когда советов нет совсем, фильтр не меняется")
    ns.Config:SetChip(ns.CHIP.ALL)
end

H.suite("Окно: выбор совета переживает пересчёт и сам пересчёта не вызывает")
do
    local env = fresh()
    local ns = open(env)
    local rows = shownRows(ns)
    H.ok(#rows >= 3, "советов в списке: " .. #rows)

    -- Считаем обращения к движку: щелчок по строке не должен дойти ни до
    -- пересчёта, ни до перерисовки списка.
    local builds, renders, rebuilds = 0, 0, 0
    local realBuild, realRender, realRebuild = ns.ActionEngine.Build, ns.TabNow.Render, ns.MainFrame.Rebuild
    ns.ActionEngine.Build = function(...) builds = builds + 1; return realBuild(...) end
    ns.TabNow.Render = function(...) renders = renders + 1; return realRender(...) end
    ns.MainFrame.Rebuild = function(...) rebuilds = rebuilds + 1; return realRebuild(...) end
    for _ = 1, 3 do
        for _, row in ipairs(rows) do row.__scripts.OnClick(row, "LeftButton") end
    end
    H.eq(builds, 0, "щелчки по строкам не пересчитывают советы (щелчков: " .. (#rows * 3) .. ")")
    H.eq(rebuilds, 0, "и окно не просит пересчёта")
    H.eq(renders, 0, "и список не перерисовывается - меняется только карточка")
    ns.ActionEngine.Build, ns.TabNow.Render, ns.MainFrame.Rebuild = realBuild, realRender, realRebuild

    -- Выбрали третий совет, движок пересчитал (карточки создаются заново) -
    -- выбран по-прежнему он.
    local third = rows[3].card
    rows[3].__scripts.OnClick(rows[3], "LeftButton")
    H.build(env)
    ns.MainFrame:RenderActive()
    local same
    for _, card in ipairs(ns.ActionEngine.cards) do
        if card.key == third.key then same = card end
    end
    H.ok(same ~= nil, "после пересчёта этот совет по-прежнему в списке")
    if same then
        H.ok(same ~= third, "и это уже другая таблица - совет построен заново")
        H.eq(ns.Detail.card, same, "а в карточке справа по-прежнему он")
        local selected = {}
        for _, row in ipairs(shownRows(ns)) do
            if row.selected then selected[#selected + 1] = row.card.key end
        end
        H.eq(#selected, 1, "подсвечена одна строка")
        H.eq(selected[1], third.key, "и это он")
    end

    -- Выбранный совет пропал из списка (сменили фильтр) - выбран первый.
    ns.TabNow.selectedKey = "такого-совета-нет"
    ns.MainFrame:RenderActive()
    local now = shownRows(ns)
    H.eq(ns.Detail.card, now[1] and now[1].card, "совета больше нет - в карточке первый из списка")

    -- Список пуст - карточка говорит об этом словами, а не висит со старым.
    ns.ActionEngine.cards = {}
    ns.MainFrame:RenderActive()
    H.eq(ns.Detail.card, nil, "в пустом списке выбранного совета нет")
    H.eq(ns.Detail.action.__shown, false, "и кнопки действия нет")
    H.eq(ns.Detail.emptyTitle.__shown, true, "вместо него - пояснение")
end

H.suite("Окно: полоса разделов — четыре кнопки, подсвечена одна, подписи влезают")
do
    local env = fresh()
    local ns = env.ns
    ns.MainFrame:Build()
    S.layout(env)
    local main = ns.MainFrame
    local rects = {}
    for _, def in ipairs(main.TABS) do
        local btn = main.tabButtons[def.key]
        H.ok(btn ~= nil, "кнопка раздела «" .. def.label .. "» есть")
        H.eq(S.plain(btn.text:GetText() or ""), def.label, "   и подписана")
        H.ok(S.textWidth(def.label) <= main.RAIL_W - 6,
            "   подпись влезает в полосу: " .. S.textWidth(def.label) .. " при " .. main.RAIL_W)
        rects[#rects + 1] = { def.label, S.rectOf(btn, main.rail) }
    end
    for i = 1, #rects do
        H.ok(rects[i][2] ~= nil, "«" .. rects[i][1] .. "» привязана к полосе")
        for j = i + 1, #rects do
            local ox, oy = S.rectOverlap(rects[i][2], rects[j][2])
            H.ok(not (ox > 0 and oy > 0), "«" .. rects[i][1] .. "» и «" .. rects[j][1]
                .. "» не налезают друг на друга")
        end
    end
    -- У остальных разделов шапку с названием рисует окно; у «Советов» своя.
    for _, def in ipairs(main.TABS) do
        main:Select(def.key)
        if def.full then
            H.eq(main.band.__shown, false, "«" .. def.label .. "»: общая шапка спрятана - у раздела своя")
            H.eq(S.plain(ns.TabNow.heading:GetText() or "") ~= "", true, "   и в ней есть название")
        else
            H.eq(main.band.__shown, true, "«" .. def.label .. "»: шапка показана")
            H.eq(S.plain(main.bandTitle:GetText() or ""), def.label, "   в ней название раздела")
            H.ok(S.plain(main.bandAbout:GetText() or "") ~= "", "   и строка о том, что здесь")
        end
    end
    main:Select("NOW")

    -- Левая колонка умещается в самое низкое окно.
    local _, hostH = main.HostSize(main.MIN_WIDTH, main.MIN_HEIGHT)
    H.ok((ns.TabNow.SIDE_USED or 0) + 30 <= hostH,
        "профиль и фильтр помещаются по высоте в самое маленькое окно: "
        .. tostring(ns.TabNow.SIDE_USED) .. " из " .. hostH)
    -- И три колонки - по ширине.
    local hostW = main.HostSize(main.MIN_WIDTH, main.MIN_HEIGHT)
    local cols = ns.TabNow.Columns(hostW)
    H.eq(cols.side + cols.main + cols.detail, hostW, "три колонки занимают ровно ширину окна")
    H.ok(cols.list >= 240, "и списку в самом узком окне остаётся " .. cols.list)
end

H.suite("Окно: прежний сохранённый размер меньше нового минимума")
do
    local env = fresh()
    local ns = env.ns
    -- Таким окно было до переделки.
    ns.Config:SaveFrame("CENTER", "CENTER", 0, 0, 720, 560)
    ns.MainFrame:Build()
    local main = ns.MainFrame
    H.eq(main.frame:GetWidth(), main.DEFAULT_WIDTH,
        "окно открыто шириной по умолчанию, а не зажато в минимум")
    H.eq(main.frame:GetHeight(), 560, "высота, которая и так годится, не тронута")
    H.ok(main.DEFAULT_WIDTH >= main.MIN_WIDTH and main.DEFAULT_HEIGHT >= main.MIN_HEIGHT,
        "размер по умолчанию не меньше минимального")

    -- А размер, выставленный уже в новом окне, сохраняется.
    ns.Config:SaveFrame("CENTER", "CENTER", 0, 0, 1100, 700)
    main:ApplyPosition()
    H.eq(main.frame:GetWidth(), 1100, "новая ширина принята")
    H.eq(main.frame:GetHeight(), 700, "и высота тоже")
end

H.suite("Окно: свой значок — только когда клиент уже видит новый файл")
do
    -- Клиент .toc не перечитал (после /reload так и есть): метки нет.
    local env = fresh()
    local ns = env.ns
    ns.Api.mediaReady, ns.Api.fontsReady = nil, nil
    env.G.C_AddOns = nil
    env.G.GetAddOnMetadata = nil
    H.eq(ns.Api:MediaReady(), false, "метки в .toc клиент не отдаёт - новых файлов он не видит")
    ns.MainFrame:Build()
    H.eq(ns.MainFrame.logo.__texture, ns.MainFrame.LOGO_FALLBACK,
        "в окне стоит запасной значок из игры")
    ns.MainFrame:ApplyMinimapButton()
    local mb = ns.MinimapButton
    H.ok(mb.icon ~= nil, "кнопка у миникарты создана")
    if mb.icon then
        H.eq(mb.icon.__texture, mb.TEXTURE_ICON_FALLBACK, "и на ней тоже запасной значок")
    end

    -- Клиент перезапущен: .toc перечитан, метка на месте.
    local env2 = fresh()
    local ns2 = env2.ns
    ns2.Api.mediaReady, ns2.Api.fontsReady = nil, nil
    local asked
    env2.G.C_AddOns = { GetAddOnMetadata = function(addon, field)
        asked = tostring(addon) .. "/" .. tostring(field)
        if field == "X-Media" then return tostring(ns2.Api.MEDIA_STAMP_ICON) end
        return nil
    end }
    H.eq(ns2.Api:MediaReady(), true, "метка есть - клиент видит новые файлы")
    H.ok(asked ~= nil and asked:find("X-Media", 1, true) ~= nil, "спрошена именно метка: " .. tostring(asked))
    ns2.MainFrame:Build()
    H.eq(ns2.MainFrame.logo.__texture, ns2.MainFrame.LOGO, "в окне стоит свой значок")
    ns2.MainFrame:ApplyMinimapButton()
    if ns2.MinimapButton.icon then
        H.eq(ns2.MinimapButton.icon.__texture, ns2.MinimapButton.TEXTURE_ICON,
            "и на кнопке у миникарты тоже")
    end

    -- Метка есть, а клиент всё равно ответил, что файла нет, - запасной.
    local tex = env2.world.newFrame("Texture")
    tex.SetTexture = function(self, v)
        self.__texture = v
        if v == "нет-такого-файла" then return false end
        return true
    end
    H.eq(ns2.Widgets.SetTextureOr(tex, "нет-такого-файла", "запасной"), false,
        "клиент сказал «нет» - это услышано")
    H.eq(tex.__texture, "запасной", "и поставлен запасной значок")

    -- И значок аддона в .toc указан свой, и файл его на месте.
    local toc = assert(io.open((H.ROOT or ".") .. "/ForeverPilot.toc", "r"))
    local text = toc:read("*a")
    toc:close()
    H.ok(text:find("Media\\Icon", 1, true) ~= nil, "значок аддона в .toc указан свой")
    local icon = io.open((H.ROOT or ".") .. "/Media/Icon.tga", "rb")
    H.ok(icon ~= nil, "файл значка лежит в папке аддона")
    if icon then
        local head = icon:read(18)
        icon:close()
        local w = head:byte(13) + head:byte(14) * 256
        local h = head:byte(15) + head:byte(16) * 256
        H.eq(head:byte(3), 2, "формат - несжатый TGA")
        H.eq(head:byte(17), 32, "32 бита с прозрачностью")
        H.ok(w == h and (w == 32 or w == 64 or w == 128 or w == 256),
            "сторона - степень двойки: " .. w .. "x" .. h)
    end
end

H.suite("Окно: свой шрифт и значки — только когда клиент их действительно видит")
do
    -- 1. После /reload без перезапуска: метка в .toc прежняя (значок уже есть,
    --    шрифта ещё нет). Окно обязано остаться на шрифтах игры.
    local env = S.load(H)
    local ns = env.ns
    ns.Api.mediaReady, ns.Api.fontsReady = nil, nil
    env.G.C_AddOns = { GetAddOnMetadata = function(_, field)
        if field == "X-Media" then return tostring(ns.Api.MEDIA_STAMP_ICON) end
        return nil
    end }
    env.G.CreateFont = function(name)
        local font = env.world.newFrame("Font", name)
        if name then env.G[name] = font end
        return font
    end
    H.eq(ns.Api:MediaReady(), true, "значок клиент уже видит")
    H.eq(ns.Api:FontsReady(), false, "а шрифта ещё нет: метка меньше нужной")
    H.eq(ns.Widgets.InitFonts(), false, "окно остаётся на шрифтах игры")
    H.eq(ns.Widgets.ready, false, "и значков не рисует")

    -- 2. Метка новая, но шрифт клиент не принял (файла он не нашёл): тоже нет.
    ns.Api.mediaReady, ns.Api.fontsReady = nil, nil
    env.G.C_AddOns = { GetAddOnMetadata = function(_, field)
        if field == "X-Media" then return tostring(ns.Api.MEDIA_STAMP_FONTS) end
        return nil
    end }
    env.world.rejectFonts = true
    H.eq(ns.Api:FontsReady(), false, "метка есть, а шрифт не загрузился - своих файлов нет")
    H.eq(ns.Widgets.InitFonts(), false, "и окно остаётся на шрифтах игры")
    -- Объект шрифта, которому файл не подошёл, шрифтом не считается, даже
    -- если клиент на SetFont промолчал.
    local silent = env.world.newFrame("Font", "ТестШрифт")
    silent.SetFont = function() return nil end
    H.eq(ns.Api:LoadFont(silent, "Fonts\\FiraSans-Regular.ttf", 12), false,
        "клиент промолчал, шрифта у объекта нет - не загружен")

    -- 3. Метка новая, шрифт принят: окно на своём шрифте, значки свои.
    env.world.rejectFonts = false
    ns.Api.mediaReady, ns.Api.fontsReady = nil, nil
    H.eq(ns.Api:FontsReady(), true, "метка есть и шрифт загрузился")
    H.eq(ns.Widgets.InitFonts(), true, "окно переходит на свой шрифт")
    H.eq(ns.Widgets.ready, true, "и рисует свои значки")
    for _, def in ipairs(ns.Widgets.FONTS) do
        local font = env.G[def[2]]
        H.ok(font ~= nil, "объект шрифта «" .. def[2] .. "» создан")
        H.eq(ns.Widgets[def[1]], def[2], "   и имя " .. def[1] .. " указывает на него")
        if font then
            H.ok(tostring(font.__fontFile):find(def[3], 1, true) ~= nil,
                "   файл: " .. tostring(font.__fontFile))
            local file = io.open((H.ROOT or ".") .. "/Media/Fonts/" .. def[3], "rb")
            H.ok(file ~= nil, "   и этот файл лежит в папке аддона")
            if file then file:close() end
        end
    end

    -- 4. Метка в .toc - та, с которой шрифт разрешён, и лицензия шрифта рядом.
    local toc = assert(io.open((H.ROOT or ".") .. "/ForeverPilot.toc", "r"))
    local text = toc:read("*a")
    toc:close()
    H.eq(tonumber(text:match("## X%-Media:%s*(%S+)")), ns.Api.MEDIA_STAMP_FONTS,
        "метка в .toc совпадает с той, которую ждёт код")
    local licence = io.open((H.ROOT or ".") .. "/Media/Fonts/FiraSans-OFL.txt", "r")
    H.ok(licence ~= nil, "текст лицензии шрифта лежит рядом с ним")
    if licence then
        H.ok(licence:read("*a"):find("SIL Open Font License", 1, true) ~= nil,
            "и это открытая лицензия OFL")
        licence:close()
    end

    -- 5. У каждого значка, который просит код, есть файл.
    local asked, missing = {}, {}
    for _, rel in ipairs(S.UI_FILES) do
        local f = assert(io.open((H.ROOT or ".") .. "/" .. rel, "r"))
        local src = f:read("*a")
        f:close()
        for name in src:gmatch('SetIcon%([^,%)]+,%s*"([%a%-]+)"') do asked[name] = rel end
        for name in src:gmatch('SetGlyph%(%s*"([%a%-]+)"') do asked[name] = rel end
        for name in src:gmatch('W%.Icon%([^,%)]+,%s*"([%a%-]+)"') do asked[name] = rel end
        for name in src:gmatch('glyph = "([%a%-]+)"') do asked[name] = rel end
    end
    for _, map in ipairs({ ns.TabNow.CHIP_ICON, ns.Detail.ACTION_ICON }) do
        for _, name in pairs(map) do asked[name] = "таблица значков" end
    end
    local count = 0
    for name, where in pairs(asked) do
        count = count + 1
        local file = io.open((H.ROOT or ".") .. "/Media/icon-" .. name .. ".tga", "rb")
        if file then file:close() else missing[#missing + 1] = name .. " (" .. where .. ")" end
    end
    H.ok(count >= 12, "значков, которые просит код: " .. count)
    H.eq(#missing, 0, "у каждого есть файл в папке Media"
        .. ((#missing > 0) and ("  <- " .. table.concat(missing, ", ")) or ""))
    for _, shape in ipairs({ "round", "pill", "pill-line", "stars" }) do
        local file = io.open((H.ROOT or ".") .. "/Media/" .. shape .. ".tga", "rb")
        H.ok(file ~= nil, "картинка «" .. shape .. "» на месте")
        if file then file:close() end
    end
end

H.suite("Окно: не бывает больше экрана")
do
    -- Игрок растянул окно за край экрана; угол для изменения размера уехал
    -- туда же, и вернуть окно стало нечем (2026-11-21).
    local env = fresh()
    local ns = env.ns
    local main = ns.MainFrame
    local screenW, screenH = env.G.UIParent:GetWidth(), env.G.UIParent:GetHeight()

    -- Сохранён размер больше экрана - окно открывается в его пределах.
    ns.Config:SaveFrame("CENTER", "CENTER", 0, 0, 5000, 4000)
    main:Build()
    H.ok(main.frame:GetWidth() <= screenW, "ширина не больше экрана: "
        .. main.frame:GetWidth() .. " при " .. screenW)
    H.ok(main.frame:GetHeight() <= screenH, "высота не больше экрана: "
        .. main.frame:GetHeight() .. " при " .. screenH)
    H.ok(main.frame:GetWidth() <= screenW * main.SCREEN_SHARE + 1,
        "и с запасом до края - угол окна остаётся под рукой")

    -- Пределы растягивания заданы клиенту: и нижний, и верхний.
    local bounds
    main.frame.SetResizeBounds = function(_, minW, minH, maxW, maxH)
        bounds = { minW, minH, maxW, maxH }
    end
    main:ApplyResizeBounds()
    H.ok(bounds ~= nil, "пределы размера переданы клиенту")
    if bounds then
        H.eq(bounds[1], main.MIN_WIDTH, "наименьшая ширина")
        H.ok(bounds[3] ~= nil and bounds[3] <= screenW, "наибольшая ширина задана и не больше экрана: "
            .. tostring(bounds[3]))
        H.ok(bounds[4] ~= nil and bounds[4] <= screenH, "наибольшая высота тоже: " .. tostring(bounds[4]))
    end

    -- Крупный масштаб окна: экран в единицах окна становится меньше.
    local wide = { main:FitSize(5000, 4000) }
    ns.Config:SetScale(1.6)
    local scaled = { main:FitSize(5000, 4000) }
    H.ok(scaled[1] < wide[1], "при крупном масштабе предел ширины меньше: "
        .. scaled[1] .. " против " .. wide[1])
    H.ok(scaled[1] * 1.6 <= screenW + 1, "и окно с этим масштабом всё равно на экране")
    ns.Config:SetScale(1.0)

    -- Маленький экран (или очень крупный масштаб): побеждает экран, а не
    -- минимальный размер окна.
    env.G.UIParent:SetSize(700, 420)
    local w, h = main:FitSize(main.DEFAULT_WIDTH, main.DEFAULT_HEIGHT)
    H.ok(w <= 700 and h <= 420, "на маленьком экране окно меньше своего минимума, но целиком видно: "
        .. w .. "x" .. h)
    env.G.UIParent:SetSize(screenW, screenH)

    -- Отпустили угол - размер возвращён в пределы, что бы ни вышло из-под мыши.
    main.frame:SetSize(9000, 9000)
    local up = main.grip.__scripts.OnMouseUp
    H.ok(up ~= nil, "у угла есть обработчик отпускания")
    if up then
        up(main.grip)
        H.ok(main.frame:GetWidth() <= screenW and main.frame:GetHeight() <= screenH,
            "после отпускания окно снова в пределах экрана: "
            .. main.frame:GetWidth() .. "x" .. main.frame:GetHeight())
    end
end

end
