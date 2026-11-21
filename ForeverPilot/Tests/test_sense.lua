-- ForeverPilot / Tests/test_sense.lua
--
-- АДДОН НЕ НЕСЁТ ЧУШЬ. ПОСТОЯННАЯ ПРОВЕРКА.
--
-- Игрок сказал дословно: «проверь, что мой аддон вообще не несёт чушь». Он не
-- технический и ловит её глазами: кнопка «Показать предмет» отвечает «наденьте
-- сами», сводка пишет «ветка молчит» при трёх её карточках на экране, карточка
-- обещает наценку 2433%. Каждая такая находка стоила ему захода в игру.
--
-- Этот набор делает то же самое без него. Он собирает ВСЁ, что аддон говорит, -
-- советы, экраны, подсказки, чат, сводку диагностики - из многих состояний
-- мира (Tests/corpus.lua) и проверяет по правилам (Tests/sense.lua):
--
--   1. текст: склейки, обрывы, крик, мусор, слова разработчика, согласование
--      числа со словом, числа без смысла;
--   2. совет не противоречит сам себе;
--   3. кнопка отвечает на то, что на ней написано, и у каждого действия есть
--      записанный договор - новое действие без договора не пройдёт;
--   4. одно и то же в чат дважды подряд не пишется;
--   5. экран и сводка диагностики говорят одно и то же;
--   6. всё, что аддон обещает от первого лица, записано и подтверждено; всё,
--      чего он обещает НЕ делать, в коде отсутствует;
--   7. те же правила - на настоящих данных игрока, когда они рядом.
--
-- КОНКРЕТНЫЕ находки, которые правилом не выразить (ложное утверждение, гладкое
-- на вид), лежат в Tests/test_nonsense.lua.
local H = ...
local ROOT = H.ROOT or "."
local S = assert(loadfile(ROOT .. "/Tests/uistub.lua"))()
local C = assert(loadfile(ROOT .. "/Tests/corpus.lua"))()
local Sense = assert(loadfile(ROOT .. "/Tests/sense.lua"))()
local D = assert(loadfile(ROOT .. "/Tests/dialect.lua"))()

-- Файлы аддона из .toc. Список берётся у Tests/dialect.lua, а не читается
-- здесь третий раз: разойдись они - и часть файлов тихо выпадет из проверок.
local function tocFiles() return assert(D.tocFiles(ROOT)) end

return function()

local CORPUS = C.build(H, S)

-- ЧТО КАКОМУ ПРАВИЛУ НЕ ПОДЛЕЖИТ - И ПОЧЕМУ. Перечень закрытый и короткий.
--
-- Сводка в файле диагностики («summary») и сырой дамп команды /fp diag full
-- («dump») пишутся не игроку, а тому, кто будет разбирать находку: имена функций
-- игры и внутренние коды причин там - содержание, ради которого их и открывают.
-- Поэтому там не действует правило про слова разработчика - и только оно: крик,
-- склейки, мусор, согласование и числа без смысла проверяются и там.
-- Всё, что игрок видит сам (советы, экраны, подсказки, чат, ответ на /fp diag),
-- проверяется по всем правилам без исключений.
local EXEMPT = {
    summary = { ["жаргон"] = true },
    dump = { ["жаргон"] = true },
}

-- Находки по группе правил: уникальные, с адресом первой встречи.
local function findingsIn(lines)
    local byGroup, seenText = {}, {}
    for _, l in ipairs(lines) do
        local seenKey = tostring(l.channel) .. "\0" .. l.text
        if not seenText[seenKey] then
            seenText[seenKey] = true
            local exempt = EXEMPT[l.channel] or {}
            for _, f in ipairs(Sense.check(S, l.text)) do
                if not exempt[f.group] then
                    local list = byGroup[f.group]
                    if not list then list = {}; byGroup[f.group] = list end
                    list[#list + 1] = { rule = f.rule, hit = f.hit, where = l.where }
                end
            end
        end
    end
    return byGroup
end

local function preview(list, n)
    local out, seen = {}, {}
    for _, f in ipairs(list) do
        local line = f.rule .. ": «" .. tostring(f.hit):gsub("\n", " ") .. "» [" .. tostring(f.where) .. "]"
        if not seen[line] then
            seen[line] = true
            if #out < (n or 6) then out[#out + 1] = line end
        end
    end
    return table.concat(out, "  ;;  ")
end

-- 0. ЕСТЬ ЧТО ПРОВЕРЯТЬ -------------------------------------------------------

H.suite("Смысл: собрание текстов не пустое")
do
    local perChannel = {}
    for _, l in ipairs(CORPUS.lines) do
        perChannel[l.channel] = (perChannel[l.channel] or 0) + 1
    end
    H.ok(#CORPUS.states >= 14, "состояний мира: " .. #CORPUS.states)
    H.ok(#CORPUS.lines > 5000, "строк собрано: " .. #CORPUS.lines)
    for _, channel in ipairs({ "title", "benefit", "why", "need", "label", "screen",
                               "tip", "chat", "summary", "diag", "dump" }) do
        H.ok((perChannel[channel] or 0) > 0,
            "канал «" .. channel .. "»: " .. tostring(perChannel[channel] or 0))
    end
    H.ok(#CORPUS.presses > 60, "нажатий кнопок советов: " .. #CORPUS.presses)
    H.ok(CORPUS.hovered > 500, "наведений мыши: " .. CORPUS.hovered)
    H.ok((perChannel.chat or 0) > 150, "строк чата (кнопки советов, команды, все кнопки окна): "
        .. tostring(perChannel.chat or 0))
    -- И ФРАЗЫ ПРО ОБЛИК В СОБРАНИИ ЕСТЬ.
    --
    -- Правила ниже проверяют то, что собрание УВИДЕЛО. Фраза, которой ни в
    -- одном состоянии мира не сказали, не проверяется ни одним правилом - и
    -- именно так уже трижды доживала до игрока чушь. А предупреждение про облик
    -- стоит первой фразой в самых опасных советах аддона, и оговорки у него
    -- две: «не собран» (утверждение) и «не знаю» (клиент не ответил).
    local looks = { loses = 0, unknown = 0 }
    for _, l in ipairs(CORPUS.lines) do
        if l.text:find("Облик этой вещи у вас не собран", 1, true) then
            looks.loses = looks.loses + 1
        end
        if l.text:find("Собран ли облик этой вещи, я не знаю", 1, true) then
            looks.unknown = looks.unknown + 1
        end
    end
    H.ok(looks.loses > 0, "фраза «облик не собран» в собрании есть: " .. looks.loses)
    H.ok(looks.unknown > 0, "и фраза «про облик не знаю» тоже: " .. looks.unknown)
end

-- 0a. КОМАНДЫ И ВСЕ КНОПКИ -------------------------------------------------------

local function split(text, sep)
    local out, pos = {}, 1
    while true do
        local s, e = text:find(sep, pos, true)
        if not s then out[#out + 1] = text:sub(pos); break end
        out[#out + 1] = text:sub(pos, s - 1)
        pos = e + 1
    end
    return out
end

H.suite("Смысл: команды /fp и все кнопки окна нажаты, ничего не упало")
do
    local commands = CORPUS.commands or {}
    H.ok(#commands >= #C.COMMANDS * #C.CHATTER_STATES,
        "команд выполнено: " .. #commands)
    H.ok((CORPUS.clicked or 0) > 300, "щелчков по кнопкам окна и панели: " .. tostring(CORPUS.clicked))
    local crashes = CORPUS.crashes or {}
    H.eq(#crashes, 0, "ни команда, ни щелчок не падают"
        .. ((#crashes > 0) and ("  <- " .. table.concat(crashes, "  ;;  ", 1, math.min(4, #crashes))) or ""))

    -- Справка - ответ на неизвестную команду. Каждая команда, которую она
    -- называет, есть в списке выполняемых: новая команда без проверки её слов
    -- не появится.
    local help
    for _, l in ipairs(CORPUS.lines) do
        if l.channel == "chat" and l.where:find("такой команды нет", 1, true) then
            help = C.chatText(S, l.text)
        end
    end
    H.ok(help ~= nil and help:find("команды", 1, true) ~= nil,
        "на неизвестную команду аддон отвечает справкой")
    local known, named, unknown = {}, 0, {}
    for _, cmd in ipairs(C.COMMANDS) do known[cmd] = true end
    for _, piece in ipairs(split((help or ""):gsub("^%s*команды:", ""), "•")) do
        piece = piece:gsub("%b()", "")
        for _, name in ipairs(split(piece, "/")) do
            name = name:gsub("^%s+", ""):gsub("%s+$", "")
            if name ~= "" and name ~= "fp" then
                named = named + 1
                if not known[name] then unknown[#unknown + 1] = name end
            end
        end
    end
    H.ok(named >= 15, "команд названо в справке: " .. named)
    H.eq(#unknown, 0, "каждая названная в справке команда выполняется этим набором"
        .. ((#unknown > 0) and ("  <- " .. table.concat(unknown, ", ")) or ""))

    -- СПРАВКА ОБЕЩАЕТ КОМАНДЫ - ЗНАЧИТ, ОНИ РАБОТАЮТ. Четыре из них («сила»,
    -- «прокачка», «экономия», «заработок») отвечали самой справкой: аддон их не
    -- узнавал. Правило: на настоящую команду справкой не отвечают.
    local unrecognised, checked = {}, 0
    for _, c in ipairs(commands) do
        if c.command ~= "такой команды нет" then
            checked = checked + 1
            for _, line in ipairs(c.said) do
                if line:find("^команды:") then
                    unrecognised[#unrecognised + 1] = "/fp " .. c.command .. " (" .. c.state .. ")"
                end
            end
        end
    end
    H.ok(checked >= 60, "настоящих команд проверено: " .. checked)
    H.eq(#unrecognised, 0, "ни одна названная команда не отвечает справкой вместо дела"
        .. ((#unrecognised > 0) and ("  <- " .. table.concat(unrecognised, "; ", 1, math.min(8, #unrecognised))) or ""))

    -- Смена профиля отвечает именем профиля - того, который попросили.
    local wrongProfile = {}
    for _, c in ipairs(commands) do
        for _, want in ipairs({ "сила", "прокачка", "экономия", "заработок" }) do
            if c.command == want then
                local line = Sense.lower(c.said[1] or "")
                if not (line:find("профиль", 1, true) and line:find(want, 1, true)) then
                    wrongProfile[#wrongProfile + 1] = "/fp " .. want .. " -> " .. tostring(c.said[1])
                end
            end
        end
    end
    H.eq(#wrongProfile, 0, "команда профиля отвечает именем этого профиля"
        .. ((#wrongProfile > 0) and ("  <- " .. table.concat(wrongProfile, "; ", 1, math.min(4, #wrongProfile))) or ""))
end

-- 1. САМИ ДЕТЕКТОРЫ ------------------------------------------------------------
--
-- Правило, которое ничего не ловит, проходит всегда. Поэтому сначала каждое
-- правило показывает, что ловит ту чушь, ради которой написано (все образцы -
-- настоящие, из игры или из кода), и молчит на здоровом тексте.

H.suite("Смысл: детекторы ловят настоящую чушь и не придираются к здоровому тексту")
do
    local function has(text, rulePart)
        for _, f in ipairs(Sense.check(S, text)) do
            if f.rule:find(rulePart, 1, true) then return true end
        end
        return false
    end
    local function clean(text)
        local all = Sense.check(S, text)
        return #all == 0, (#all > 0) and (all[1].rule .. ": " .. tostring(all[1].hit)) or ""
    end

    local BAD = {
        { "Вероятности взяты из данных classic, не из источника по forever. бонус arcane salvager не учтён..",
          "две точки подряд" },
        { "Сейчас 54с 97м, ровно как единственное наблюдение — 54с 97м. наблюдение всего одно.",
          "с маленькой буквы после точки" },
        { "3 дня наблюдений (выборка короткая: истории ещё мало) За 3 дня цена выросла на 16%.",
          "склеены без точки" },
        { "не хватает: Рунная ткань x12 и ещё 2 позиции Это в 10 раз больше, чем у вас есть.",
          "склеены без точки" },
        { "Сейчас 32с — это НИЖЕ всего, что я видел.", "заглавными" },
        { "Это НЕ характеристика «сила».", "заглавными" },
        { "без него сравнение вещей для магa неверно", "русские и латинские" },
        { "итого: %d позиций", "мусор" },
        { "источник: nil", "мусор" },
        { "Пороги навыка, реагенты и itemID — с диска.", "слово разработчика" },
        { "Рецепты за Благосклонность гейтятся навыком.", "слово разработчика" },
        { "больше всего отсеял фильтр «drops-main-stat» (55).", "слово разработчика" },
        { "нет на этом клиенте: C_Item.GetItemStats", "слово разработчика" },
        { "чтение сумок не сработало (достоверность: EXACT)", "слово разработчика" },
        { "Ветка gearUpgrades: вошло 71, вышло 3.", "слово разработчика" },
        { "Это может быть одна ошибка, а не 7 находки.", "не согласованы" },
        { "аукцион против прилавка — это в 25.3 раз.", "не согласованы" },
        { "26 ур., 2 видов в сумках, 2з 50с", "не согласованы" },
        { "самый дешёвый рецепт, который ещё даёт навык (0м за крафт).", "ноль вместо" },
        { "Материалы: 0м", "ноль вместо" },
        { "Это в 600 раз больше, чем у вас есть (0м).", "сравнение с нулём" },
        { "свои записи не устаревают. С координатами: 0 из 0.", "0 из 0" },
        { "Требуется 0 уровень.", "нулевой уровень" },
        { "Это 142.0 балла за золотой.", ".0" },
        { "разброс 73с 52м..1з 66с, это 2.3x; предмет был на аукционе", "множитель" },
        { "Разница +8з 80с за штуку, это 1468% наценки.", "без единого слова сомнения" },
        { "Пустой выбор = определяю сама по классу.", "женском роде" },
        { "Стоит отметить, что цена выше обычного.", "вводный оборот" },
        { "Как вы могли заметить, рецептов пока нет.", "вводный оборот" },
        { "К сведению: банк я ещё не видел.", "вводный оборот" },
        { "Наблюдений ещё нет. Суточных слепков цен ещё нет — первый появится"
          .. " после входа в игру.", "дважды сказано, что данных нет" },
        -- ВЕНДОРНЫЙ ПОТОЛОК: «дешевле» без разницы в цене. Фразы про потолок
        -- собираются из цены на полке, цены на аукционе и их разности, и при
        -- равных ценах разность - ноль. Такое «дешевле» - неправда, а
        -- «экономия 0м» - неправда с числом.
        { "У торговца дешевле: 18с против 18с на аукционе, экономия 0м за штуку.",
          "экономия, которой нет" },
        { "На аукционе дешевле на 0м — у торговца та же вещь есть всегда.",
          "«дешевле» при равных ценах" },
        { "У торговца дешевле: 18с против 0м на аукционе.", "сравнение с нулём" },
        { "У торговца дешевле: 18с против 17с, экономия -1с за штуку.",
          "отрицательная экономия" },
        -- ЗАПРЕТ ВМЕСТО ПРЕДУПРЕЖДЕНИЯ. Соблазн появился с проверкой облика:
        -- потеря необратима, и запретить выглядит заботой. Но решает игрок.
        { "Облик с неё не собран — не продавайте эту вещь.", "запрещает игроку" },
        { "Ни в коем случае не распыляйте: облик пропадёт.", "запрещает игроку" },
        { "Вам нельзя отправлять её почтой.", "запрещает игроку" },
    }
    for _, case in ipairs(BAD) do
        H.ok(has(case[1], case[2]), "ловится (" .. case[2] .. "): " .. case[1])
    end

    -- Новые правила: перечисление с повтором и дорога в настройки.
    H.ok(has("Серый хлам в сумках: Длинный волос из хвоста, Отрубленный коготь,"
        .. " Отрубленный коготь и ещё 8.", "дважды подряд"),
        "ловится повтор в перечислении (тот самый, со скриншота)")
    H.eq(#Sense.listRepeat("Без чар: Спина, Ступни, Кисти рук, Голова и ещё 4."), 0,
        "и не придирается к разным именам подряд")
    H.eq(#Sense.listRepeat("Наложение чар 225 — Гендольф Серыйй, 28 ур., Маг;"
        .. " Первая помощь 225 — Гендольф Серыйй, 28 ур., Маг."), 0,
        "ни к повтору, который стоит не подряд")
    H.ok(Sense.settingsHint("Торговец: Кварц, Тернистая долина, 34.0 76.0"
        .. " (навигация выключена в настройках)") ~= nil,
        "ловится дорога в настройки в строке совета")
    H.eq(Sense.settingsHint("Торговец: Кварц, Тернистая долина, 34.0 76.0"), nil,
        "и не придирается к строке с одними координатами")

    local GOOD = {
        "Слот «Голова»: лучше, чем Старый капюшон, на 11 баллов. Материалы ничего не стоят: всё уже в сумках.",
        "Материалы 3с, выручка 23с 75м за штуку (сбор аукциона уже вычтен). Своей истории по этому предмету нет.",
        "1з укладывается в наблюдённый разброс 85с..1з. 3 дня наблюдений.",
        "Гендольф, 26 ур.   •   2з 50с   •   9 советов",
        "( ) В бою: приглушить",
        "Откройте «Портняжное дело» и найдите «Новый капюшон». Окон игры я не открываю.",
        "Не хватает 60з 93с на весь список.",
        "Это в 10 раз больше, чем у вас есть (3з 37с). На свои деньги хватит на 85 шт. из 405.",
        "показано 1 из 9 советов. Нажмите «Всё», чтобы увидеть остальные.",
        "Скрыто вами — 3, вернуть всё: /fp show",
        "3 покупки доступны по навыку",
        "Разница +8з 80с за штуку, это 1468% наценки. Числа этой карточки не сходятся — проверьте цену на месте.",
        "в 2,5 раза больше торговца",
        "самопроверка нашла странности (2) — наберите /fp diag",
        "Купить: [Льняная ткань] x12",
        "Auctionator не загружен — список остаётся здесь.",
        -- Честная оговорка про то, чего аддон не знает, - не вводный оборот:
        -- она меняет смысл утверждения, а не украшает его.
        "Банк я ещё не видел, возможно, покупать не нужно.",
        "Торговец есть, но цена в данных не указана — скорее всего это ошибка данных.",
        -- Одно «нет» и объяснение к нему - это не повтор: вторая фраза говорит
        -- новое. Ругаться правило обязано только на второе «нет».
        "Выученных формул на них у вас нет, и ни одной такой формулы я вообще не видел.",
        "Записанных мест пока нет. Свои — те, перед кем вы стояли сами, им можно верить.",
        -- И сами фразы про потолок, которые обязаны проходить: разница есть,
        -- числа настоящие (Heavy Silken Thread из кеша игрока).
        "У торговца дешевле: 18с против 18с 80м на аукционе, экономия 80м за штуку.",
        "На аукционе дешевле всего на 4м, и за этой ценой стоит одно наблюдение;"
            .. " у торговца та же вещь есть всегда за 1с.",
        "У какого торговца — не знаю: цена есть, а его имени в записи нет.",
        "Выручка 2з, а такой же предмет торговец продаёт по 1з и запас у него"
            .. " неограниченный (кеш цен торговцев Auctionator).",
        "Эту цену записал Auctionator, когда вы открывали окно торговца, и только"
            .. " для неограниченного запаса — товар постоянный.",
        "У торговца это дешевле, чем на аукционе: Крепкая шелковая нить —"
            .. " экономия 7с 20м на весь план.",
        -- И САМИ ФРАЗЫ ПРО ОБЛИК: предупреждение проходит, потому что оно
        -- предупреждение. Решение в нём оставлено игроку словами.
        "Облик этой вещи у вас не собран: продадите на аукционе — и потеряете"
            .. " его навсегда.",
        "Собран ли облик этой вещи, я не знаю.",
        "Непривязанную вещь необычного качества и выше вы теряете вместе с её"
            .. " обликом навсегда: проданную, отправленную почтой или"
            .. " распылённую вещь в коллекцию облика уже не записать.",
        "Продать вещь ради денег — ваше право: я предупреждаю, а не запрещаю.",
        -- Утверждение про числа, а не запрет игроку: оно обязано проходить.
        "Дешевле 1з 20с за штуку выставлять нельзя: это продажа в минус.",
    }
    for _, text in ipairs(GOOD) do
        local ok, why = clean(text)
        H.ok(ok, "здоровый текст проходит: " .. text .. ((not ok) and ("  <- " .. why) or ""))
    end
end

-- 2. ВЕСЬ ТЕКСТ ПО ПРАВИЛАМ -------------------------------------------------------

do
    local found = findingsIn(CORPUS.lines)
    for _, rule in ipairs(Sense.RULES) do
        H.suite("Смысл: " .. rule.name .. " — во всём, что аддон говорит")
        local list = found[rule.name] or {}
        H.eq(#list, 0, "находок нет" .. ((#list > 0) and ("  <- " .. preview(list, 8)) or ""))
    end
end

-- 2a. ТЕ ЖЕ ПРАВИЛА - ПО СТРОКАМ ПРЯМО ИЗ КОДА ------------------------------------
--
-- Собрание видит только сказанное в тестовых мирах. Сообщение об ошибке,
-- которая там не случилась, в него не попадает. Поэтому правила, которым не
-- нужен целый текст, идут по каждой русской строке каждого файла аддона.

H.suite("Смысл: крик, два алфавита и род — по всем русским строкам кода, а не только по сказанным")
do
    local probe = Sense.literals('local a = "ПЕРВАЯ" -- "в комментарии"\n'
        .. 'local b = [[вторая]]\nlocal c = \'тре\\\'тья\' .. "--не комментарий"\n')
    local got = {}
    for _, lit in ipairs(probe) do got[#got + 1] = lit.line .. ":" .. lit.text end
    H.eq(table.concat(got, "|"), "1:ПЕРВАЯ|2:вторая|3:тре'тья|3:--не комментарий",
        "разбор строк: комментарии пропущены, длинные скобки и экранирование поняты")

    local files = {}
    for line in io.lines(ROOT .. "/ForeverPilot.toc") do
        local rel = line:gsub("\r", ""):gsub("\\", "/"):gsub("^%s+", ""):gsub("%s+$", "")
        if rel:match("%.lua$") then files[#files + 1] = rel end
    end
    local scanned, found = 0, {}
    for _, rel in ipairs(files) do
        local f = io.open(ROOT .. "/" .. rel, "rb")
        if f then
            local src = f:read("*a")
            f:close()
            for _, lit in ipairs(Sense.literals(src)) do
                if Sense.hasCyrillic(lit.text) then
                    scanned = scanned + 1
                    local plain = Sense.strip(S, lit.text)
                    for _, rule in ipairs(Sense.STATIC_RULES) do
                        for _, f2 in ipairs(rule.fn(plain)) do
                            found[#found + 1] = rel .. ":" .. lit.line .. " " .. f2.rule
                                .. ": «" .. tostring(f2.hit) .. "»"
                        end
                    end
                end
            end
        end
    end
    H.ok(#files >= 40, "файлов из .toc просмотрено: " .. #files)
    H.ok(scanned > 1500, "русских строк в коде: " .. scanned)
    H.eq(#found, 0, "находок нет"
        .. ((#found > 0) and ("  <- " .. table.concat(found, "  ;;  ", 1, math.min(12, #found))) or ""))
end

-- 3. СОВЕТ НЕ ПРОТИВОРЕЧИТ САМ СЕБЕ -----------------------------------------------

H.suite("Смысл: совет не противоречит сам себе")
do
    local low = Sense.lower
    local pathsClash, perGold, buyAbove, buyPinned = {}, {}, {}, {}
    for _, rec in ipairs(CORPUS.cards) do
        local card = rec.card
        local why, need = low(S.plain(card.why or "")), low(S.plain(card.need or ""))
        local where = rec.state .. " / «" .. tostring(card.title) .. "»"

        -- Один путь и дешевле, и быстрее остальных («выбирать не из чего») - и
        -- тут же «Выбирать вам» на той же карточке.
        if (why:find("выбирать не из чего", 1, true) or why:find("и дешевле, и быстрее", 1, true))
            and need:find("выбирать вам", 1, true) then
            pathsClash[#pathsClash + 1] = where
        end
        -- «N баллов за золотой» у вещи, которая стоит меньше золотого: число
        -- получается из деления на долю золотого и не значит ничего.
        if why:find("за золотой", 1, true) and (tonumber(card.cost) or 0) < 10000 then
            perGold[#perGold + 1] = where .. " (цена " .. tostring(card.cost) .. ")"
        end
        -- «нужно для N советов выше»: карточка покупки не знает, что окажется
        -- выше неё после ранжирования, профиля и обрезки списка.
        if card.kind == "BUY" and (why:find("советов выше", 1, true)
            or why:find("совета выше", 1, true)) then
            buyAbove[#buyAbove + 1] = where
        end
        -- Купить больше, чем нужно советам, - только потому, что игрок сам
        -- закрепил столько. Тогда это обязано быть сказано.
        if card.kind == "BUY" and rec.pinned and card.action
            and (tonumber(card.action.qty) or 0) > 0
            and not (why .. " " .. need):find("закреп", 1, true) then
            buyPinned[#buyPinned + 1] = where
        end
    end
    H.eq(#pathsClash, 0, "нет совета «один путь и дешевле, и быстрее» с припиской «Выбирать вам»"
        .. ((#pathsClash > 0) and ("  <- " .. table.concat(pathsClash, "; ")) or ""))
    H.eq(#perGold, 0, "«баллов за золотой» нет у вещей дешевле золотого"
        .. ((#perGold > 0) and ("  <- " .. table.concat(perGold, "; ")) or ""))
    H.eq(#buyAbove, 0, "покупка не утверждает, что нужные ей советы стоят «выше»"
        .. ((#buyAbove > 0) and ("  <- " .. table.concat(buyAbove, "; ")) or ""))
    H.eq(#buyPinned, 0, "покупка закреплённого руками так и названа"
        .. ((#buyPinned > 0) and ("  <- " .. table.concat(buyPinned, "; ")) or ""))

    -- НАВЫК ПРОФЕССИИ НЕИЗВЕСТЕН - И ОБА СОВЕТА ГОВОРЯТ ОДНО. Совет «Уровень
    -- навыка неизвестен: X» стоял рядом с советом «На навык» по той же
    -- профессии и утверждал «не считаю прирост навыка для этой профессии».
    -- Правило: совет «На навык» по такой профессии сам говорит «неизвестен» и
    -- не называет навык числом «N/M», а совет о неизвестном навыке не обещает,
    -- что прирост «не считается».
    local byState = {}
    for _, rec in ipairs(CORPUS.cards) do
        byState[rec.state] = byState[rec.state] or {}
        table.insert(byState[rec.state], rec.card)
    end
    local clash, pairsSeen = {}, 0
    for state, cards in pairs(byState) do
        local unknown = {}
        for _, card in ipairs(cards) do
            local name = tostring(card.key or ""):match("^setup:skill:(.+)$")
            if name then unknown[name] = card end
        end
        for _, card in ipairs(cards) do
            local prof = (card.kind == "CRAFT_SKILL") and card.profession or nil
            if prof and unknown[prof] then
                pairsSeen = pairsSeen + 1
                local text = low(S.plain(card.why or ""))
                if not text:find("неизвестен", 1, true) or text:find("%d+/%d+") then
                    clash[#clash + 1] = state .. " / «" .. tostring(card.title)
                        .. "»: навык назван числом, хотя рядом сказано, что он неизвестен"
                end
                if low(S.plain(unknown[prof].why or "")):find("не считаю прирост", 1, true) then
                    clash[#clash + 1] = state .. " / «" .. tostring(unknown[prof].title)
                        .. "»: «не считаю прирост», а совет «На навык» по этой профессии стоит рядом"
                end
            end
        end
    end
    H.ok(pairsSeen > 0, "случаев «навык неизвестен» вместе с советом «На навык»: " .. pairsSeen)
    H.eq(#clash, 0, "совет о неизвестном навыке и совет «На навык» не спорят"
        .. ((#clash > 0) and ("  <- " .. table.concat(clash, "; ")) or ""))
end

H.suite("Смысл: совет не отрицает себя первой же фразой")
do
    -- ЖИВАЯ НАХОДКА, ДЕСЯТАЯ СТРОКА СПИСКА ИГРОКА:
    --
    --   «Купить: Небесно-голубая краска x6»
    --   «Ни одному совету это сейчас не нужно. Цена: ~1з 31с … В вашем списке
    --    покупок это уже закреплено (6 шт.).»
    --
    -- Карточка предлагает купить и первой же фразой сообщает, что покупать
    -- незачем. Правило закрыто классом, а не этим одним случаем: перечень прямых
    -- отрицаний - Sense.SELF_DENIAL, проверяется ПЕРВАЯ фраза «почему» (на
    -- экране строка одна и обрезается шириной окна, так что читают именно её).
    --
    -- Самопроверка детектора идёт первой: правило, которое ничего не ловит,
    -- зелено всегда.
    local probe = Sense.selfRefuting("Ни одному совету это сейчас не нужно."
        .. " Цена: ~1з 31с за штуку.")
    H.ok(probe ~= nil, "детектор ловит прежнюю формулировку живой карточки")
    H.eq(Sense.selfRefuting("Это ваше закрепление: вы просили держать это в"
        .. " списке покупок, и я держу. Моим советам столько сейчас не нужно,"
        .. " но список ваш."), nil,
        "и не придирается к карточке, которая сначала говорит, чей это заказ")
    H.eq(Sense.selfRefuting("Я считаю только сумки. Если материалы лежат в"
        .. " банке, часть покупок из списка может оказаться лишней."), nil,
        "ни к оговорке про то, чего аддон не знает")

    local bad, checked = {}, 0
    for _, rec in ipairs(CORPUS.cards) do
        local card = rec.card
        checked = checked + 1
        local f = Sense.selfRefuting(S.plain(card.why or ""))
        if f then
            bad[#bad + 1] = rec.state .. " / «" .. tostring(card.title)
                .. "»: " .. f.hit
        end
    end
    H.ok(checked > 100, "карточек просмотрено: " .. checked)
    H.eq(#bad, 0, "ни одна карточка не отрицает себя первой фразой"
        .. ((#bad > 0) and ("  <- " .. table.concat(bad, "  ;;  ", 1,
            math.min(4, #bad))) or ""))

    -- И ПО СТРОКАМ КОДА, А НЕ ТОЛЬКО ПО СКАЗАННОМУ. Состояние, в котором фраза
    -- появляется, в собрании может и не случиться - именно так эта находка и
    -- дожила до игрока: оба закрепления в фикстурном мире кому-то были нужны.
    local inCode, scanned = {}, 0
    for _, rel in ipairs(tocFiles()) do
        local f = io.open(ROOT .. "/" .. rel, "rb")
        if f then
            local src = f:read("*a")
            f:close()
            for _, lit in ipairs(Sense.literals(src)) do
                if Sense.hasCyrillic(lit.text) then
                    scanned = scanned + 1
                    local low = Sense.lower(lit.text)
                    for _, phrase in ipairs(Sense.SELF_DENIAL) do
                        if low:find(phrase, 1, true) then
                            inCode[#inCode + 1] = rel .. ":" .. lit.line
                                .. " «" .. phrase .. "»"
                        end
                    end
                end
            end
        end
    end
    H.ok(scanned > 1500, "русских строк в коде просмотрено: " .. scanned)
    H.eq(#inCode, 0, "и в коде такой фразы больше нет вовсе"
        .. ((#inCode > 0) and ("  <- " .. table.concat(inCode, "  ;;  ")) or ""))
end

H.suite("Смысл: закреплённое игроком называется его списком, а не советом")
do
    -- Карточка, которая осталась в списке только из-за закрепления, обязана
    -- говорить, ЧЕЙ это заказ, не выглядеть советом аддона и не спорить с
    -- советами за место. Состояние - «закреплено то, что ни одному совету не
    -- нужно» в Tests/corpus.lua.
    local own, states = {}, {}
    for _, rec in ipairs(CORPUS.cards) do
        states[rec.state] = true
        if rec.card.ownList then own[#own + 1] = rec end
    end
    H.ok(states["закреплено то, что ни одному совету не нужно"],
        "состояние с ненужным закреплением в собрании есть")
    H.ok(#own > 0, "карточка своего списка построена: " .. #own)
    for _, rec in ipairs(own) do
        local card = rec.card
        local where = rec.state .. " / «" .. tostring(card.title) .. "»"
        H.ok(S.plain(card.title or ""):find("Ваш список покупок", 1, true) ~= nil,
            where .. ": заголовок не выглядит советом")
        H.ok(Sense.lower(S.plain(card.why or "")):find("ваше закрепление", 1, true) ~= nil,
            where .. ": первая фраза говорит, чей это заказ")
        H.ok(Sense.lower(S.plain(card.need or "")):find("снять закрепление", 1, true) ~= nil,
            where .. ": сказано, как снять закрепление")
        H.eq(card.action and card.action.kind, "unpin",
            where .. ": и кнопка снимает его, а не добавляет заново")
        H.eq(rec.card.informational, true, where .. ": помечена сведениями")
        local ns = CORPUS.summaries[1] and CORPUS.summaries[1].ns
        if ns then
            H.eq(ns.ActionEngine.TierOf(card), 1,
                where .. ": за место с советами не спорит")
        end
    end
end

-- 4. КНОПКА ОТВЕЧАЕТ НА ТО, ЧТО НА НЕЙ НАПИСАНО ------------------------------------
--
-- У каждого действия совета - ДОГОВОР: что обязано произойти в ответ на
-- нажатие. Перечень закрытый: действие, которого здесь нет, роняет тест, пока
-- для него не написан договор. Так «Показать предмет», отвечающая «наденьте
-- сами», не появится второй раз под другим именем.

-- Подпись кнопки -> какое действие за ней стоит.
-- Действия «найти рецепт» здесь нет, и это не пропуск: у него нет подписи,
-- потому что нет кнопки - открыть окно профессий игра аддонам запрещает
-- (Logic/RecipeBook.lua). Договор у него всё равно есть, см. CONTRACT.findRecipe.
local LABEL_ACTION = {
    ["Показать предмет"] = "showItem", ["В список покупок"] = "shop",
    ["Вернуть все"] = "undismiss", ["Понятно"] = "openProfession",
    ["Убрать из списка"] = "unpin",
    -- Подписи, которые зависят от того, что открыто (Card.LiveAction).
    ["Искать на аукционе"] = "auction",
    ["Показать в профессии"] = "showRecipe", ["Вернуть весь список"] = "showRecipe",
}

-- Слова, которыми кнопка «показать» отвечать не должна: это ответ на другой
-- вопрос - «сделай за меня».
local OFF_TOPIC = { "наденьте", "экипировкой", "не управляю", "сами" }

local CONTRACT = {}

-- Информационный совет: кнопки нет вовсе, нажимать нечего.
CONTRACT.noop = function(p)
    if p.drawn then return false, "у информационного совета нарисована кнопка" end
    return true
end

-- Найти рецепт: КНОПКИ НЕТ ВОВСЕ И КЛИЕНТ НЕ ТРОНУТ НИ В ОДНОМ СОСТОЯНИИ
-- МИРА. Открытие рецепта в окне профессий - защищённый вызов: игра его
-- блокирует и обвиняет аддон (Core/Api.lua). Вместо кнопки у совета стоит
-- строка «откройте такую-то профессию и найдите такой-то рецепт», и щелчок по
-- самой карточке отвечает ею же.
CONTRACT.findRecipe = function(p)
    if p.drawn then return false, "у совета про рецепт нарисована кнопка" end
    if p.recipeCalls ~= 0 then
        return false, "клиент позван " .. p.recipeCalls .. " раз, а звать его нельзя"
    end
    return true
end

-- Искать на аукционе (кнопка на самом совете): одна строка, и в ней либо
-- «передал в поиск», либо причина, почему нет. Список покупок при этом не
-- меняется: искать - не закреплять.
CONTRACT.auction = function(p)
    if #p.said ~= 1 then return false, "строк в чате " .. #p.said .. " вместо одной" end
    local line = Sense.lower(p.said[1])
    if line:find("передал в поиск", 1, true) then return true end
    if line:find("не принял", 1, true) or line:find("нечем", 1, true)
        or line:find("нечего", 1, true) then return true end
    return false, "нажали «искать», а ответ ни про поиск, ни про отказ: " .. p.said[1]
end

-- Показать в профессии: одна строка с именем рецепта, и запрещённый вызов
-- открытия окна не сделан ни разу.
CONTRACT.showRecipe = function(p)
    if p.recipeCalls ~= 0 then
        return false, "клиент позван открыть рецепт " .. p.recipeCalls .. " раз, а звать его нельзя"
    end
    if #p.said ~= 1 then return false, "строк в чате " .. #p.said .. " вместо одной" end
    return true
end

-- Показать предмет: одна строка, и в ней сам предмет, а не совет, что с ним делать.
CONTRACT.showItem = function(p)
    if #p.said ~= 1 then return false, "строк в чате " .. #p.said .. " вместо одной" end
    local line = Sense.lower(p.said[1])
    for _, word in ipairs(OFF_TOPIC) do
        if line:find(word, 1, true) then
            return false, "просили показать, а ответ про другое («" .. word .. "»): " .. p.said[1]
        end
    end
    local act = p.card.action or {}
    local info = act.itemID and p.items and p.items[act.itemID] or nil
    local name = info and info.name
    local raw = table.concat(p.raw or {}, " ")
    if raw:find("|Hitem:", 1, true) then return true end
    if name and p.said[1]:find(name, 1, true) then return true end
    if line:find("показать нечем", 1, true) then return true end
    return false, "в ответе нет ни ссылки на предмет, ни его названия: " .. p.said[1]
end

-- В список покупок: либо позиция появилась в списке, либо сказано, что она там уже есть.
CONTRACT.shop = function(p)
    if #p.said ~= 1 then return false, "строк в чате " .. #p.said .. " вместо одной" end
    local line = Sense.lower(p.said[1])
    if p.changed then
        if not line:find("добавил", 1, true) then
            return false, "список изменился, а сказано не про добавление: " .. p.said[1]
        end
        return true
    end
    if line:find("добавил", 1, true) then
        return false, "сказано «добавил», а в списке ничего не изменилось: " .. p.said[1]
    end
    if not line:find("уже", 1, true) then
        return false, "ничего не изменилось и не сказано почему: " .. p.said[1]
    end
    return true
end

-- «Убрать из списка» у карточки своего списка: позиция из списка ушла, сказано
-- что именно и как вернуть.
--
-- ДОГОВОР НУЖЕН ИМЕННО ЗДЕСЬ. На этой карточке раньше стояла кнопка «В список
-- покупок», и нажатие отвечало «уже в вашем списке» - то есть кнопка не делала
-- ничего. Это тот же класс, что «Показать предмет», отвечавшая «наденьте сами»:
-- подпись обещает одно, ответ про другое.
CONTRACT.unpin = function(p)
    if #p.said ~= 1 then return false, "строк в чате " .. #p.said .. " вместо одной" end
    local line = Sense.lower(p.said[1])
    if not p.changed then
        -- Ничего не изменилось - значит, закрепления и не было, и это сказано.
        if line:find("нет", 1, true) then return true end
        return false, "ничего не изменилось и не сказано почему: " .. p.said[1]
    end
    if not line:find("убрал", 1, true) then
        return false, "список изменился, а сказано не про снятие: " .. p.said[1]
    end
    -- И названо, как вернуть: кнопка, которая отнимает и не говорит, как
    -- отменить, - это тихое действие.
    if not line:find("вернуть", 1, true) then
        return false, "не сказано, как вернуть: " .. p.said[1]
    end
    return true
end

-- «Понятно» у совета «откройте окно профессии»: напоминание называет профессию.
--
-- ИМЕНЕМ ДЛЯ ИГРОКА, А НЕ ТЕМ, ЧТО ЛЕЖИТ В ДЕЙСТВИИ. В карточке хранится имя
-- как его дал источник (клиент - по-русски, чужой кеш Mastercraft - «Tailoring»),
-- и на экран оно идёт через U.profLabel. Сравнение с сырым именем требовало бы
-- от ответа в чате английского слова на русском клиенте - то есть ровно той
-- находки, которую этот набор и ловит правилом «профессии».
CONTRACT.openProfession = function(p)
    if #p.said ~= 1 then return false, "строк в чате " .. #p.said .. " вместо одной" end
    local prof = p.card.action and p.card.action.profession
    local shown = (prof and p.ns and p.ns.Util and p.ns.Util.profLabel(prof)) or prof
    if prof and not p.said[1]:find(tostring(shown), 1, true) then
        return false, "в ответе не названа профессия «" .. tostring(shown) .. "»"
    end
    return true
end

-- Вернуть все скрытые: что-то изменилось, и сказано сколько.
CONTRACT.undismiss = function(p)
    if not p.changed then return false, "после «Вернуть все» ничего не изменилось" end
    if #p.said ~= 1 then return false, "строк в чате " .. #p.said .. " вместо одной" end
    if not Sense.lower(p.said[1]):find("вернул", 1, true) then
        return false, "не сказано, что возвращено: " .. p.said[1]
    end
    -- На карточке «Скрытых советов: 8» - и в ответе то же число, а не другое.
    local promised = tostring(p.card.title or ""):match("(%d+)")
    local answered = p.said[1]:match("(%d+)")
    if promised and answered ~= promised then
        return false, "на карточке " .. promised .. ", а в ответе " .. tostring(answered)
            .. ": " .. p.said[1]
    end
    return true
end

-- 3a. ВОДА: ТО, ЧТО ПОКАЗЫВАЕТСЯ «ПРОСТО ТАК» --------------------------------------
--
-- Игрок попросил ещё раз пройтись по всему, что аддон показывает, и искать то,
-- что показывается просто так. Классы находок - его слова: повтор того, что уже
-- видно рядом; вежливые обороты без ответа; объяснение длиннее совета; совет,
-- который ничего не предлагает сделать.
--
-- Правила, которые выражаются одной строкой текста (вводные обороты, мусор,
-- числа без смысла), живут в Tests/sense.lua и идут по всему собранию выше.
-- Здесь - то, что видно только ЦЕЛЫМ ЭКРАНОМ или целой карточкой.

H.suite("Вода: одна и та же фраза не стоит на экране дважды")
do
    -- Самопроверка детектора: ряды «ключ - значение» на вкладке персонажа
    -- законно повторяются («1 выучено из 1 • прочитал сам • 1 минуту назад» у
    -- двух профессий), и придираться к ним нельзя. Отличие - в том, что это не
    -- фраза: у фразы есть конец, то есть точка.
    local function isSentence(text)
        if #text < 60 then return false end
        local last = text:sub(-1)
        return last == "." or last == "!" or last == "?"
    end
    H.ok(isSentence("Игра не отдаёт список рецептов, пока окно профессии не открыли"
        .. " хотя бы раз за сессию."), "детектор считает фразой то, что кончается точкой")
    H.eq(isSentence("1 выучено из 1  •  прочитал сам  •  1 минуту назад"), false,
        "и не считает фразой строку значения в таблице")
    H.eq(isSentence("Коротко."), false, "короткое не считается: повтор в пару слов — не вода")

    local repeats, screens = {}, 0
    for _, scr in ipairs(CORPUS.screens) do
        screens = screens + 1
        local count = {}
        for _, text in ipairs(scr.texts) do
            local plain = S.plain(text)
            if isSentence(plain) then count[plain] = (count[plain] or 0) + 1 end
        end
        for text, n in pairs(count) do
            if n > 1 then
                repeats[#repeats + 1] = scr.where .. ": x" .. n .. " «"
                    .. text:sub(1, 70) .. "»"
            end
        end
    end
    H.ok(screens > 100, "экранов просмотрено: " .. screens)
    H.eq(#repeats, 0, "ни одна фраза не повторяется на одном экране"
        .. ((#repeats > 0) and ("  <- " .. table.concat(repeats, "  ;;  ", 1,
            math.min(5, #repeats))) or ""))
end

-- 3b. ВОДА, КОТОРУЮ ВИДНО ТОЛЬКО РАЗМЕТКОЙ -----------------------------------------
--
-- Три жалобы одного скриншота, и ни одну из них не видно в тексте: простыня над
-- списком, кнопка фильтра поверх строки с числами и обрезанное на половине
-- числа «Разница +8з 80…». Поэтому проверяются измерения, собранные вместе с
-- текстами (Tests/corpus.lua, measureNow): по всем состояниям мира, а не по
-- одному.

H.suite("Вода: над списком не больше одной короткой строки")
do
    -- НА ЧЁМ ДЕРЖИТСЯ ЭТА ПРОВЕРКА: хотя бы в двух состояниях строка есть. Без
    -- этого «ни одной длинной строки» значит «строки не было вовсе» - именно
    -- так простыня и выросла бы обратно незамеченной.
    local shown, withCauses = 0, 0
    for _, s in ipairs(CORPUS.strips) do
        if s.shown then shown = shown + 1 end
    end
    H.ok(shown >= 2, "состояний, где над списком что-то сказано: " .. shown)

    -- Обещание игроку, записанное числом: одна строка, не длиннее 110 символов.
    -- Было пять строк и 506 символов в одной из них.
    local LIMIT = 110
    local tooLong, tooMany, silent, noPath = {}, {}, {}, {}
    for _, s in ipairs(CORPUS.strips) do
        if s.shown then
            if s.lines ~= 1 then
                tooMany[#tooMany + 1] = s.state .. ": строк " .. s.lines
            end
            local len = 0
            for _ in s.text:gmatch("[%z\1-\127\194-\244]") do len = len + 1 end
            if len > LIMIT then
                tooLong[#tooLong + 1] = s.state .. ": " .. len .. " символов — " .. s.text
            end
            if s.width > s.room + 0.5 then
                tooLong[#tooLong + 1] = s.state .. ": не влезает (" .. s.width
                    .. " при " .. s.room .. ") — " .. s.text
            end
            -- Объявление не превращается в молчание: число есть, и путь к
            -- подробностям есть, и сами подробности есть.
            if not s.text:find("%d") then
                silent[#silent + 1] = s.state .. ": без числа — " .. s.text
            end
            if #s.details == 0 then
                silent[#silent + 1] = s.state .. ": подробностей нет вовсе"
            end
            if not s.text:find("наведите мышь", 1, true) then
                noPath[#noPath + 1] = s.state .. ": путь к подробностям не назван — " .. s.text
            end
            -- И подробности не стоят на экране второй раз: они под курсором.
            for _, d in ipairs(s.details) do
                if #d > 120 and s.text:find(d:sub(1, 60), 1, true) then
                    tooLong[#tooLong + 1] = s.state .. ": подробность попала в строку"
                end
            end
        else
            if #s.details > 0 then
                silent[#silent + 1] = s.state .. ": подробности есть, а строки нет"
            end
        end
    end
    H.eq(#tooMany, 0, "строка ровно одна"
        .. ((#tooMany > 0) and ("  <- " .. table.concat(tooMany, "; ")) or ""))
    H.eq(#tooLong, 0, "и короткая, не длиннее " .. LIMIT .. " символов"
        .. ((#tooLong > 0) and ("  <- " .. table.concat(tooLong, "; ", 1,
            math.min(3, #tooLong))) or ""))
    H.eq(#silent, 0, "и ничего не исчезает молча: число и подробности на месте"
        .. ((#silent > 0) and ("  <- " .. table.concat(silent, "; ", 1,
            math.min(3, #silent))) or ""))
    H.eq(#noPath, 0, "и путь к подробностям назван в самой строке"
        .. ((#noPath > 0) and ("  <- " .. table.concat(noPath, "; ")) or ""))
end

H.suite("Разметка шапки: ничто не нарисовано поверх другого")
do
    -- Самопроверка счётчика: без неё «налезаний нет» не значит ничего.
    local a = { top = -60, bottom = -80, left = 0, right = 100 }
    local b = { top = -62, bottom = -74, left = 50, right = 300 }
    local ox, oy = S.rectOverlap(a, b)
    H.ok(ox > 0 and oy > 0, "счётчик находит налезание кнопки на строку")
    local below = { top = -84, bottom = -96, left = 50, right = 300 }
    local ox2, oy2 = S.rectOverlap(a, below)
    H.eq(ox2 == 0 or oy2 == 0, true, "и не находит там, где полосы разные")
    local beside = { top = -60, bottom = -80, left = 200, right = 300 }
    local ox3, oy3 = S.rectOverlap(a, beside)
    H.eq(ox3 == 0 or oy3 == 0, true, "ни там, где они стоят рядом")

    H.ok(#CORPUS.bands >= 14, "состояний с измеренной шапкой: " .. #CORPUS.bands)
    local clash, outside, sameBand = {}, {}, {}
    local checked = 0
    for _, st in ipairs(CORPUS.bands) do
        H.ok(st.width > 0, st.state .. ": ширина вкладки известна (" .. st.width .. ")")
        for i = 1, #st.bands do
            local one = st.bands[i]
            if one.rect.right > st.width + 0.5 then
                outside[#outside + 1] = st.state .. ": «" .. one.name .. "» за краем ("
                    .. string.format("%.0f", one.rect.right) .. " при " .. st.width .. ")"
            end
            for j = i + 1, #st.bands do
                local two = st.bands[j]
                checked = checked + 1
                local dx, dy = S.rectOverlap(one.rect, two.rect)
                if dx > 0 and dy > 0 then
                    clash[#clash + 1] = st.state .. ": «" .. one.name .. "» и «"
                        .. two.name .. "» налезают на "
                        .. string.format("%.0f x %.0f px", dx, dy)
                end
            end
        end
        -- И отдельно то, из-за чего эта проверка появилась: строка статистики
        -- не делит место с фильтрами. Раньше она стояла своей полосой под их
        -- рядом; теперь фильтры - колонкой слева, а строка - в шапке списка,
        -- то есть целиком ПРАВЕЕ любого из них.
        local stats
        for _, one in ipairs(st.bands) do
            if one.name == "строка статистики" then stats = one end
        end
        for _, one in ipairs(st.bands) do
            if stats and one.name:find("^фильтр") and stats.rect.left < one.rect.right - 0.5 then
                sameBand[#sameBand + 1] = st.state .. ": строка статистики в одной полосе с фильтрами"
                break
            end
        end
    end
    H.ok(checked > 500, "пар элементов шапки сверено: " .. checked)
    H.eq(#clash, 0, "ни одной пары, нарисованной друг поверх друга"
        .. ((#clash > 0) and ("  <- " .. table.concat(clash, "; ", 1,
            math.min(4, #clash))) or ""))
    H.eq(#outside, 0, "и ничего не ушло за край вкладки"
        .. ((#outside > 0) and ("  <- " .. table.concat(outside, "; ", 1,
            math.min(4, #outside))) or ""))
    H.eq(#sameBand, 0, "строка статистики не делит полосу с кнопками фильтров"
        .. ((#sameBand > 0) and ("  <- " .. table.concat(sameBand, "; ", 1,
            math.min(3, #sameBand))) or ""))
end

H.suite("Разметка карточки совета: ничто не нарисовано поверх другого")
do
    -- Карточка справа от списка собирается руками: высота каждого куска текста
    -- считается, и следующий ставится под ним. Ошибка в этом счёте видна только
    -- на экране - текст поверх текста или поверх кнопки. Поэтому для КАЖДОГО
    -- совета в КАЖДОМ состоянии мира прямоугольники частей карточки сверяются
    -- попарно, по тем же привязкам, по которым их ставит клиент.
    H.ok(#CORPUS.details > 60, "карточек советов измерено: " .. #CORPUS.details)
    local clash, outside, unpicked, checked = {}, {}, {}, 0
    for _, d in ipairs(CORPUS.details) do
        local where = d.state .. " / «" .. tostring(d.card.title) .. "»"
        if not d.picked then unpicked[#unpicked + 1] = where end
        for i = 1, #d.parts do
            local one = d.parts[i]
            if not one.rect then
                outside[#outside + 1] = where .. ": «" .. one.name .. "» ни к чему не привязано"
            else
                if one.rect.left < -0.5 or one.rect.right > d.width + 0.5
                    or one.rect.top > 0.5 or one.rect.bottom < -d.height - 0.5 then
                    outside[#outside + 1] = where .. ": «" .. one.name .. "» за краем карточки"
                end
                for j = i + 1, #d.parts do
                    local two = d.parts[j]
                    if two.rect then
                        checked = checked + 1
                        local dx, dy = S.rectOverlap(one.rect, two.rect)
                        if dx > 0 and dy > 0 then
                            clash[#clash + 1] = where .. ": «" .. one.name .. "» и «" .. two.name
                                .. "» налезают на " .. string.format("%.0f x %.0f px", dx, dy)
                        end
                    end
                end
            end
        end
    end
    H.ok(checked > 1500, "пар частей карточки сверено: " .. checked)
    H.eq(#unpicked, 0, "щелчок по строке каждый раз открывал именно этот совет"
        .. ((#unpicked > 0) and ("  <- " .. table.concat(unpicked, "; ", 1, math.min(3, #unpicked))) or ""))
    H.eq(#clash, 0, "ни одной пары, нарисованной друг поверх друга"
        .. ((#clash > 0) and ("  <- " .. table.concat(clash, "; ", 1, math.min(4, #clash))) or ""))
    H.eq(#outside, 0, "и ничего не ушло за край карточки"
        .. ((#outside > 0) and ("  <- " .. table.concat(outside, "; ", 1, math.min(4, #outside))) or ""))

    -- И ТЕКСТ В КАРТОЧКЕ - ЦЕЛИКОМ: то, что показано, равно тому, что в совете.
    local shortened, compared = {}, 0
    for _, d in ipairs(CORPUS.details) do
        for _, part in ipairs(d.parts) do
            if part.full and part.drawn then
                compared = compared + 1
                if part.drawn ~= part.full then
                    shortened[#shortened + 1] = d.state .. " / «" .. tostring(d.card.title)
                        .. "»: «" .. part.name .. "» — " .. part.drawn
                end
            end
        end
    end
    H.ok(compared > 200, "текстов карточки сверено с советом: " .. compared)
    H.eq(#shortened, 0, "в карточке ничего не укорочено"
        .. ((#shortened > 0) and ("  <- " .. table.concat(shortened, "; ", 1, math.min(3, #shortened))) or ""))
end

H.suite("Вода: в строке совета не обрезано ни одно число и ни одни координаты")
do
    -- Числовая группа: деньги, координаты, доля, проценты - то, что клиент
    -- обрезал посреди («Разница +8з 80…»). Группы считаются так же, как их
    -- собирает аддон (U.atoms), и каждая группа нарисованной строки обязана
    -- стоять в полном тексте целиком.
    local function groupsOf(ns, text)
        local out = {}
        for _, atom in ipairs(ns.Util.atoms(text)) do
            if atom.number then out[#out + 1] = atom.text end
        end
        return out
    end
    -- Пространство имён берём у первого состояния: оно у всех одинаковое.
    local anyNS = CORPUS.summaries[1] and CORPUS.summaries[1].ns
    H.ok(anyNS ~= nil, "пространство имён аддона доступно")
    local MARK = anyNS and anyNS.Util.MORE_MARK or "…"
    H.ok(#CORPUS.rows > 100, "строк карточек измерено: " .. #CORPUS.rows)

    local overflow, cutNumber, noMark, lostCoords = {}, {}, {}, {}
    local shortened, measured = 0, 0
    for _, row in ipairs(CORPUS.rows) do
        for _, line in ipairs(row.lines) do
            if line.drawn ~= "" then
                measured = measured + 1
                local width = S.textWidth(line.drawn)
                if width > line.room + 0.5 then
                    overflow[#overflow + 1] = row.state .. " / " .. line.name .. ": "
                        .. width .. " при " .. string.format("%.0f", line.room)
                        .. " — " .. line.drawn
                end
                if line.drawn ~= line.full then
                    shortened = shortened + 1
                    if not line.drawn:find(MARK, 1, true) then
                        noMark[#noMark + 1] = row.state .. " / " .. line.name
                            .. ": укорочено без пометки — " .. line.drawn
                    end
                    for _, group in ipairs(groupsOf(anyNS, line.drawn)) do
                        -- Знак в конце не считается: см. ту же оговорку в
                        -- проверке на настоящих данных ниже.
                        group = group:gsub("[%.,;:…]+$", "")
                        if group ~= "" and not line.full:find(group, 1, true) then
                            cutNumber[#cutNumber + 1] = row.state .. " / " .. line.name
                                .. ": «" .. group .. "» в полном тексте так не стоит — "
                                .. line.full
                        end
                    end
                    local coords = line.full:match("%d+%.%d+ %d+%.%d+")
                    if coords and not line.drawn:find(coords, 1, true) then
                        lostCoords[#lostCoords + 1] = row.state .. " / " .. line.name
                            .. ": координаты «" .. coords .. "» выброшены — " .. line.drawn
                    end
                end
            end
        end
    end
    H.ok(measured > 300, "непустых строк на экране: " .. measured)
    H.ok(shortened > 0, "и укороченные среди них есть: " .. shortened
        .. " (иначе правило проверяло бы пустоту)")
    H.eq(#overflow, 0, "ни одна строка не вылезает за своё место — клиенту обрезать нечего"
        .. ((#overflow > 0) and ("  <- " .. table.concat(overflow, "  ;;  ", 1,
            math.min(4, #overflow))) or ""))
    H.eq(#cutNumber, 0, "ни одно число не разрезано"
        .. ((#cutNumber > 0) and ("  <- " .. table.concat(cutNumber, "  ;;  ", 1,
            math.min(4, #cutNumber))) or ""))
    H.eq(#noMark, 0, "укороченная строка помечена «…»"
        .. ((#noMark > 0) and ("  <- " .. table.concat(noMark, "  ;;  ", 1,
            math.min(4, #noMark))) or ""))
    H.eq(#lostCoords, 0, "и координаты не выброшены: их читают ради них самих"
        .. ((#lostCoords > 0) and ("  <- " .. table.concat(lostCoords, "  ;;  ", 1,
            math.min(4, #lostCoords))) or ""))
end

H.suite("Вода: дорога в настройки не стоит в тексте совета")
do
    -- Самопроверка правила - в наборе детекторов выше. Здесь оно идёт по всем
    -- карточкам всех состояний: заголовок, выгода, почему, нужно.
    local bad, checked = {}, 0
    for _, rec in ipairs(CORPUS.cards) do
        local card = rec.card
        for _, field in ipairs({ "title", "benefit", "why", "need" }) do
            local text = card[field]
            if type(text) == "string" and text ~= "" then
                checked = checked + 1
                local f = Sense.settingsHint(S.plain(text))
                if f then
                    bad[#bad + 1] = "«" .. tostring(card.title) .. "» / " .. field
                        .. ": " .. tostring(f.hit)
                end
            end
        end
    end
    H.ok(checked > 200, "строк карточек просмотрено: " .. checked)
    H.eq(#bad, 0, "ни одна карточка не рассказывает, где это настраивается"
        .. ((#bad > 0) and ("  <- " .. table.concat(bad, "  ;;  ", 1,
            math.min(4, #bad))) or ""))
end

H.suite("Вода: на карточке нет того, что отвечает не игроку")
do
    -- АДРЕС ИСТОЧНИКА, ДАТА ЕГО ЧТЕНИЯ И БУХГАЛТЕРИЯ СВЕРОК - НЕ СОВЕТ.
    --
    -- В строке «почему» самой длинной карточки аддона (Благосклонность
    -- торговца, 558 символов) сто с лишним уходило на «со слов сообщества
    -- (theforeverguides.com/… (прочитан 2026-11-17); номера ящиков сверены с
    -- Polestar_Codex)». Сама оговорка - «в игре я этого не проверял» - нужна и
    -- осталась; адрес уехал в подсказку под курсором, туда же, где стоит
    -- достоверность. Правило закрывает это для ВСЕХ карточек сразу.
    local PROVENANCE = {
        { "%a+%.com", "адрес сайта" },
        { "%a+%.ru%f[%A]", "адрес сайта" },
        { "прочитан %d%d%d%d%-%d%d%-%d%d", "дата чтения источника" },
        { "сверен[ыоа]? с ", "бухгалтерия сверок" },
    }
    local bad, checked = {}, 0
    for _, rec in ipairs(CORPUS.cards) do
        local card = rec.card
        for _, field in ipairs({ "title", "benefit", "why", "need" }) do
            local text = card[field]
            if type(text) == "string" and text ~= "" then
                checked = checked + 1
                for _, pat in ipairs(PROVENANCE) do
                    local s, e = S.plain(text):find(pat[1])
                    if s then
                        bad[#bad + 1] = "«" .. tostring(card.title) .. "» / " .. field
                            .. ": " .. pat[2] .. " — " .. S.plain(text):sub(s, e)
                    end
                end
            end
        end
    end
    H.ok(checked > 200, "строк карточек просмотрено: " .. checked)
    H.eq(#bad, 0, "ни одна карточка не носит адрес источника в своём тексте"
        .. ((#bad > 0) and ("  <- " .. table.concat(bad, "  ;;  ", 1, math.min(4, #bad))) or ""))

    -- И оговорка, ради которой адрес там стоял, никуда не делась.
    local said = false
    for _, l in ipairs(CORPUS.lines) do
        if l.channel == "why" and Sense.lower(S.plain(l.text)):find("в игре я этого не проверял", 1, true) then
            said = true
        end
    end
    H.ok(said, "а «в игре я этого не проверял» на карточке осталось")
end

H.suite("Вода: аддон не сомневается в том, что сам же и проверил")
do
    -- «Если умеете это делать — сейчас хороший момент продать» стояло у совета
    -- про цену, который отбирается РОВНО по выученным рецептам этого персонажа.
    -- То есть аддон сомневался вслух в том, что сам только что проверил. Такие
    -- обороты перечислены: каждый - это вопрос, на который ответ у аддона есть.
    local KNOWN = {
        { "если умеете", "рецепт отобран по r.learned — аддон это знает" },
        { "если вы умеете", "то же" },
        { "если у вас есть такая профессия", "профессии аддон читает сам" },
        { "если этот предмет у вас есть", "сумки аддон читает сам" },
    }
    -- ПО СТРОКАМ КОДА, А НЕ ТОЛЬКО ПО СКАЗАННОМУ. Совет про цену рождается лишь
    -- тогда, когда у игрока есть своя история цен с выбросом; в фикстурных
    -- мирах такого состояния почти нет, и проверка по собранию была бы зелёной,
    -- ничего не проверив. Поэтому так же, как с криком: по каждой русской
    -- строке каждого файла из .toc.
    local bad, scanned = {}, 0
    for _, rel in ipairs(tocFiles()) do
        local f = io.open(ROOT .. "/" .. rel, "rb")
        if f then
            local src = f:read("*a")
            f:close()
            for _, lit in ipairs(Sense.literals(src)) do
                if Sense.hasCyrillic(lit.text) then
                    scanned = scanned + 1
                    local low = Sense.lower(lit.text)
                    for _, pair in ipairs(KNOWN) do
                        if low:find(pair[1], 1, true) then
                            bad[#bad + 1] = rel .. ":" .. lit.line .. " «"
                                .. pair[1] .. "» — " .. pair[2]
                        end
                    end
                end
            end
        end
    end
    H.ok(scanned > 1500, "русских строк в коде просмотрено: " .. scanned)
    -- Самопроверка: на той самой фразе, которая там стояла, правило срабатывает.
    local probe = Sense.lower("Если умеете это делать — сейчас хороший момент продать.")
    H.ok(probe:find(KNOWN[1][1], 1, true) ~= nil,
        "детектор ловит прежнюю формулировку из совета про цену")
    H.eq(#bad, 0, "ни одной оговорки про то, что аддон и так знает"
        .. ((#bad > 0) and ("  <- " .. table.concat(bad, "  ;;  ", 1, math.min(4, #bad))) or ""))
end

H.suite("Вода: в столбце выгоды у каждого числа есть единица")
do
    -- «ПОЧТИ ВЕРНЫЙ +1» - ПЛЮС ОДИН ЧЕГО?
    --
    -- Столбец выгоды - то место, куда игрок смотрит первым, и в нём рядом стоят
    -- «+11 баллов», «+5с 60м», «270 Favor». На этом фоне «+1» читается как ещё
    -- одна такая величина, хотя это пункт навыка. Правило закрывает весь
    -- столбец: у каждого числа в строке выгоды обязана быть единица, и список
    -- единиц - здесь.
    local UNITS = {}
    for _, u in ipairs({
        "з", "с", "м",                                  -- деньги
        "балл", "балла", "баллов",                      -- польза по весам
        "пункт", "пункта", "пунктов",                   -- навык
        "Favor",                                        -- валюта торговца
        "раз", "раза",                                  -- «нужно 1 раз»
        "шт", "путь", "пути", "позиция", "позиции", "позиций",
        -- ПРЕДМЕТЫ И МЕСТА У КОСТРА, ПРОФЕССИИ У ДРУГИХ ПЕРСОНАЖЕЙ.
        --
        -- Правило про то, что у числа в столбце выгоды обязана быть единица, а
        -- не про то, что единиц бывает ровно двенадцать. «Место ещё под 3
        -- предмета лагеря» и «2 профессии» - это числа с единицей; без этих
        -- слов правило ругалось на верный текст. Вторую строку («2 профессии»)
        -- пишет ветка «между персонажами», и до появления в собрании мира с
        -- двумя персонажами её не читал никто.
        "предмет", "предмета", "предметов",
        "место", "места", "мест",
        "профессия", "профессии", "профессий",
    }) do UNITS[u] = true end

    -- Разбор идёт лексемами Tests/sense.lua, а не образцом: классы символов
    -- Lua 5.1 побайтовые, и «%a» русских букв не видит - первая версия этого
    -- правила ругалась на «11 баллов», не найдя за числом единицы.
    --
    -- Доля «N/M» единицы не требует: чего именно доля, сказано в заголовке
    -- совета («Чары: 1/9, без чар: …»).
    local function numbersWithoutUnit(text)
        local toks = Sense.tokens(tostring(text))
        local out, skip = {}, {}
        for i, t in ipairs(toks) do
            if t.kind == "num" and not skip[i] then
                local a, b = toks[i + 1], toks[i + 2]
                local ok = false
                if a and a.kind == "other" and a.text == "%" then
                    ok = true
                elseif a and a.kind == "other" and a.text == "/"
                    and b and b.kind == "num" then
                    ok = true
                    skip[i + 2] = true
                elseif a and a.kind == "word" and UNITS[a.text] then
                    ok = true
                elseif a and a.kind == "other" and a.text == " "
                    and b and b.kind == "word" and UNITS[b.text] then
                    ok = true
                end
                if not ok then
                    out[#out + 1] = t.text
                        .. ((a and a.kind ~= "other") and (" " .. a.text) or "")
                end
            end
        end
        return out
    end

    -- Самопроверка: на прежней формулировке правило срабатывает, на нынешних -
    -- молчит.
    H.ok(#numbersWithoutUnit("почти верный +1") == 1,
        "детектор ловит «почти верный +1»")
    H.eq(#numbersWithoutUnit("+1 пункт навыка, шанс 75%"), 0, "и не придирается к «+1 пункт навыка, шанс 75%»")
    H.eq(#numbersWithoutUnit("+11 баллов / продать за 20с 75м"), 0, "ни к деньгам с баллами")
    H.eq(#numbersWithoutUnit("0/2 готово"), 0, "ни к доле «0/2»")
    H.eq(#numbersWithoutUnit("270 Favor"), 0, "ни к «270 Favor»")

    local bad, checked = {}, 0
    for _, rec in ipairs(CORPUS.cards) do
        local text = rec.card.benefit
        if type(text) == "string" and text ~= "" then
            checked = checked + 1
            local hits = numbersWithoutUnit(S.plain(text))
            for _, hit in ipairs(hits) do
                bad[#bad + 1] = "«" .. S.plain(text) .. "» (" .. tostring(rec.card.kind)
                    .. "): число «" .. hit .. "» без единицы"
            end
        end
    end
    H.ok(checked > 100, "строк выгоды просмотрено: " .. checked)
    H.eq(#bad, 0, "ни одного числа без единицы"
        .. ((#bad > 0) and ("  <- " .. table.concat(bad, "  ;;  ", 1, math.min(5, #bad))) or ""))
end

H.suite("Вода: покупка не называет советов, которых на экране нет")
do
    -- Ветка покупок работает ДО порога мелкой денежной выгоды, и на настоящих
    -- данных из-за этого выходило четыре карточки «Купить материалы» со строкой
    -- «Нужно для: На продажу: Лунная винтовка» - про совет, который порог только
    -- что убрал. Правило простое: каждый заказчик, которого покупка называет,
    -- обязан быть на том же экране (или быть закреплением самого игрока).
    local bad, buys = {}, 0
    for _, summary in ipairs(CORPUS.summaries) do
        local pinnedMark = summary.ns and summary.ns.ActionEngine.PINNED_BY_HAND
        local onScreen, titles = {}, {}
        for _, card in ipairs(summary.cards or {}) do
            onScreen[card.key] = true
            titles[S.plain(tostring(card.title))] = true
        end
        for _, card in ipairs(summary.cards or {}) do
            if card.kind == "BUY" and type(card.buyFor) == "table" then
                buys = buys + 1
                local live = 0
                for key, title in pairs(card.buyFor) do
                    local pinned = (title == pinnedMark)
                    if pinned or onScreen[key] then live = live + 1 end
                end
                if live == 0 then
                    bad[#bad + 1] = summary.state .. " / «" .. tostring(card.title)
                        .. "»: ни одного заказчика на экране"
                end
                -- И названные в тексте имена - это имена советов с экрана.
                local why = S.plain(tostring(card.why or ""))
                local list = why:match("^Нужно для[^:]*: ([^%.]+)")
                for piece in tostring(list or ""):gmatch("[^;]+") do
                    local name = piece:gsub("^%s+", ""):gsub("%s+$", "")
                    if name ~= "" and not titles[name] and name ~= pinnedMark then
                        bad[#bad + 1] = summary.state .. " / «" .. tostring(card.title)
                            .. "»: назван совет «" .. name .. "», которого на экране нет"
                    end
                end
            end
        end
    end
    H.ok(buys > 0, "карточек покупки проверено: " .. buys)
    H.eq(#bad, 0, "покупка называет только то, что на экране есть"
        .. ((#bad > 0) and ("  <- " .. table.concat(bad, "  ;;  ", 1, math.min(4, #bad))) or ""))
end

H.suite("Смысл: кнопка совета отвечает на то, что на ней написано")
do
    local seenKinds, unknownKinds, unknownLabels, broken, crashed, dead = {}, {}, {}, {}, {}, {}
    for _, p in ipairs(CORPUS.presses) do
        local kind = tostring(p.kind)
        seenKinds[kind] = (seenKinds[kind] or 0) + 1
        local where = p.state .. " / «" .. tostring(p.card.title) .. "»"
        if not p.ok then
            crashed[#crashed + 1] = where .. ": " .. tostring(p.err)
        end
        local contract = CONTRACT[kind]
        if not contract then
            unknownKinds[kind] = where
        else
            local ok, why = contract(p)
            if not ok then broken[#broken + 1] = where .. " [" .. kind .. "]: " .. tostring(why) end
        end
        if p.label and LABEL_ACTION[p.label] == nil then
            unknownLabels[p.label] = where
        elseif p.label and LABEL_ACTION[p.label] ~= kind then
            broken[#broken + 1] = where .. ": подпись «" .. p.label .. "» стоит на действии "
                .. kind .. ", а договор у неё с " .. tostring(LABEL_ACTION[p.label])
        end
        -- Мёртвая кнопка: нарисована, нажата - и ничего: ни слова, ни изменения.
        if p.drawn and p.pressed and not p.changed and #p.said == 0 and p.recipeCalls == 0 then
            dead[#dead + 1] = where .. " «" .. tostring(p.label) .. "»"
        end
    end

    local kindsList = {}
    for kind, n in pairs(seenKinds) do kindsList[#kindsList + 1] = kind .. "×" .. n end
    table.sort(kindsList)
    H.ok(#kindsList >= 5, "действий проверено: " .. table.concat(kindsList, ", "))

    local missing = {}
    for kind, where in pairs(unknownKinds) do missing[#missing + 1] = kind .. " (" .. where .. ")" end
    H.eq(#missing, 0, "у каждого действия есть договор"
        .. ((#missing > 0) and ("  <- без договора: " .. table.concat(missing, "; ")) or ""))
    local newLabels = {}
    for label, where in pairs(unknownLabels) do newLabels[#newLabels + 1] = "«" .. label .. "» (" .. where .. ")" end
    H.eq(#newLabels, 0, "у каждой подписи записано, какое действие за ней стоит"
        .. ((#newLabels > 0) and ("  <- новые подписи: " .. table.concat(newLabels, "; ")) or ""))
    H.eq(#crashed, 0, "ни одно нажатие не падает"
        .. ((#crashed > 0) and ("  <- " .. table.concat(crashed, "; ")) or ""))
    H.eq(#dead, 0, "мёртвых кнопок нет: каждое нажатие что-то делает или что-то говорит"
        .. ((#dead > 0) and ("  <- " .. table.concat(dead, "; ")) or ""))
    H.eq(#broken, 0, "каждая кнопка выполняет свой договор"
        .. ((#broken > 0) and ("  <- " .. table.concat(broken, "  ;;  ", 1, math.min(6, #broken))) or ""))
end

-- 5. ОДНО И ТО ЖЕ В ЧАТ ДВАЖДЫ ПОДРЯД НЕ ПИШЕТСЯ -----------------------------------

local function repeatsIn(said)
    local n = 0
    for i = 2, #said do
        if said[i] == said[i - 1] then n = n + 1 end
    end
    return n
end

H.suite("Смысл: десять нажатий одной кнопки — не десять одинаковых строк")
do
    local env = C.fresh(H, S, { prepare = function(e)
        e.ns.ShoppingList:Pin(2589, 12)
    end })
    local ns = env.ns
    ns.MainFrame:Build()
    ns.MainFrame:Select("NOW")
    ns.MainFrame:RenderActive()
    local worst, pressedRows = {}, 0
    for _, row in ipairs(ns.Card.pool) do
        if row.__shown and row.card then
            -- КНОПКА В КАРТОЧКЕ СОВЕТА, А ЕСЛИ ЕЁ НЕТ - САМА СТРОКА.
            --
            -- Кнопка действия стоит в карточке справа: щелчок по строке
            -- открывает совет, и нажимается она. У советов про рецепт кнопки
            -- нет вовсе (открыть окно профессий игра аддонам запрещает) - у них
            -- десять раз щёлкается сама строка, и повторяться в чат ей нельзя
            -- точно так же.
            local target, handler, what
            local button = S.actionOf(ns, row)
            if button then
                target, what = button, tostring(row.card.action.label)
                handler = button.__scripts and button.__scripts.OnClick
            else
                target, what = row, "щелчок по совету «"
                    .. tostring(row.card.title) .. "»"
                handler = row.__scripts and row.__scripts.OnClick
            end
            if handler then
                pressedRows = pressedRows + 1
                env.said = {}
                ns.Api.lastSaid = nil
                for _ = 1, 10 do pcall(handler, target, "LeftButton") end
                local repeats = repeatsIn(env.said)
                if repeats > 0 then
                    worst[#worst + 1] = "«" .. what .. "»: "
                        .. (repeats + 1) .. " одинаковых подряд — " .. C.chatText(S, env.said[1])
                end
            end
        end
    end
    H.ok(pressedRows >= 4, "кнопок и советов нажато по десять раз: " .. pressedRows)
    H.eq(#worst, 0, "одинаковых строк подряд нет"
        .. ((#worst > 0) and ("  <- " .. table.concat(worst, "; ")) or ""))
end

H.suite("Смысл: события игры и пересчёты не повторяют в чат одно и то же")
do
    local env = C.fresh(H, S)
    local ns, G = env.ns, env.G
    G.SlashCmdList = {}
    G.GetMerchantNumItems = function() return 0 end
    local chunk = assert(loadfile(ROOT .. "/Main.lua"))
    setfenv(chunk, env.sandbox)
    chunk("ForeverPilot", ns)
    local driver = G.ForeverPilotDriver
    local onEvent = driver and driver.__scripts and driver.__scripts.OnEvent
    H.ok(onEvent ~= nil, "обработчик событий есть")
    pcall(onEvent, driver, "ADDON_LOADED", "ForeverPilot")
    pcall(onEvent, driver, "PLAYER_LOGIN")
    S.populate(env, H)
    env.said = {}
    ns.Api.lastSaid = nil

    local events = {}
    for name in pairs(ns.Events.EVENT_MAP or {}) do events[#events + 1] = name end
    for name in pairs(ns.Events.SIGNAL_ONLY or {}) do events[#events + 1] = name end
    table.sort(events)
    local function drain()
        for _ = 1, 5 do
            local pending = env.pendingTimers or {}
            env.pendingTimers = {}
            if #pending == 0 then break end
            for _, fn in ipairs(pending) do pcall(fn) end
        end
    end
    for _ = 1, 3 do
        for _, name in ipairs(events) do
            pcall(onEvent, driver, name, 1, 2, 3)
            H.clock = (H.clock or 0) + 2
            if ns.Events.Tick then pcall(function() ns.Events:Tick() end) end
            drain()
        end
        pcall(function() ns.MainFrame:Rebuild(true) end)
    end
    H.ok(#events > 20, "событий прогнано по три раза: " .. #events)
    local repeats = repeatsIn(env.said)
    local sample
    for i = 2, #env.said do
        if env.said[i] == env.said[i - 1] then sample = C.chatText(S, env.said[i]); break end
    end
    H.eq(repeats, 0, "одинаковых строк подряд нет (сказано всего " .. #env.said .. ")"
        .. (sample and ("  <- " .. sample) or ""))
end

H.suite("Смысл: повтор после паузы — это новый повод, а не шум")
do
    -- Сворачивание повторов не должно делать кнопку мёртвой навсегда. Игрок
    -- нажал «Показать предмет», ссылка уехала вверх за чужими сообщениями;
    -- через пять минут он нажимает снова - и обязан получить ответ.
    local env = H.load()
    local ns = env.ns
    env.said = {}
    ns.Api.lastSaid = nil
    ns.Api:Print("одно и то же")
    ns.Api:Print("одно и то же")
    H.eq(#env.said, 1, "сразу подряд — одна строка")
    local quiet = ns.Api.REPEAT_QUIET_SECONDS
    H.ok(type(quiet) == "number" and quiet >= 5 and quiet <= 120,
        "срок, после которого повтор снова уместен, задан: " .. tostring(quiet) .. " c")
    H.clock = H.clock + (quiet or 30) - 1
    ns.Api:Print("одно и то же")
    H.eq(#env.said, 1, "до истечения срока — всё ещё одна")
    H.clock = H.clock + 2
    ns.Api:Print("одно и то же")
    H.eq(#env.said, 2, "после паузы то же сообщение печатается снова")
    ns.Api:Print("одно и то же")
    H.eq(#env.said, 2, "и опять не дважды подряд")
end

H.suite("Смысл: в чат пишет только Api:Print — в обход сворачивания повторов не пишет никто")
do
    local offenders = {}
    local files = { "Main.lua" }
    for _, dir in ipairs({ "Core", "Logic", "UI", "Data" }) do
        for line in io.lines(ROOT .. "/ForeverPilot.toc") do
            local rel = line:gsub("\r", ""):gsub("\\", "/")
            if rel:match("^" .. dir .. "/.+%.lua$") then files[#files + 1] = rel end
        end
    end
    for _, rel in ipairs(files) do
        local f = io.open(ROOT .. "/" .. rel, "r")
        if f then
            local n = 0
            for line in f:lines() do
                n = n + 1
                local code = line:gsub("%-%-.*$", "")
                local direct = code:find("AddMessage", 1, true)
                    or code:find("DEFAULT_CHAT_FRAME", 1, true)
                    or code:find("SendChatMessage", 1, true)
                -- print(...) как вызов, но не Api:Print и не чужое поле .print
                local bare = code:find("%f[%w_]print%s*%(")
                local ownSeam = (rel == "Core/Api.lua") or (rel == "Main.lua"
                    and code:find("_G.print", 1, true))
                if direct or (bare and not ownSeam and not code:find("[%.:]print%s*%(")) then
                    offenders[#offenders + 1] = rel .. ":" .. n
                end
            end
            f:close()
        end
    end
    H.ok(#files > 40, "файлов аддона просмотрено: " .. #files)
    H.eq(#offenders, 0, "прямой печати в чат нет"
        .. ((#offenders > 0) and ("  <- " .. table.concat(offenders, ", ")) or ""))
end

-- 6. ЭКРАН И СВОДКА ГОВОРЯТ ОДНО И ТО ЖЕ -------------------------------------------

H.suite("Смысл: сводка диагностики не спорит с экраном")
do
    local checked = 0
    for _, s in ipairs(CORPUS.summaries) do
        -- Состояние «фильтр, под который ничего не подходит» подрезает список
        -- советов руками, без пересчёта, - сводка про него не знает по построению.
        if not s.state:find("фильтр", 1, true) then
            checked = checked + 1
            local text = table.concat(s.lines, "\n")
            local said = tonumber(text:match("Советов на экране: (%d+)"))
            H.eq(said, s.total, s.state .. ": «Советов на экране» в сводке равно числу советов на экране")

            -- Ветка, названная молчащей, не имеет ни одного совета на экране.
            local onScreen = {}
            for _, card in ipairs(s.cards or {}) do
                local branch = s.branchByKind and s.branchByKind[card.kind]
                if branch then onScreen[branch] = (onScreen[branch] or 0) + 1 end
            end
            local liars = {}
            for _, key in ipairs(s.branchOrder or {}) do
                local label = s.branchLabel and s.branchLabel[key] or key
                if (onScreen[key] or 0) > 0
                    and text:find("— " .. label .. " (", 1, true) then
                    liars[#liars + 1] = label .. " (на экране " .. onScreen[key] .. ")"
                end
            end
            H.eq(#liars, 0, s.state .. ": молчащей не названа ни одна ветка, чьи советы на экране"
                .. ((#liars > 0) and ("  <- " .. table.concat(liars, "; ")) or ""))

            -- И счёт по веткам в данных окна - тот же, что на экране.
            local off = {}
            for _, br in ipairs((s.meta or {}).branches or {}) do
                if (br.count or 0) ~= (onScreen[br.key] or 0) then
                    off[#off + 1] = tostring(br.label) .. ": сказано " .. tostring(br.count)
                        .. ", на экране " .. tostring(onScreen[br.key] or 0)
                end
            end
            H.eq(#off, 0, s.state .. ": число советов каждой ветки сходится с экраном"
                .. ((#off > 0) and ("  <- " .. table.concat(off, "; ")) or ""))

            -- «Ни один модуль ничего не выдал» - только если и правда никто
            -- ничего не построил. Скрытое игроком - не «ничего не выдал».
            local built = 0
            for _, n in pairs((s.meta or {}).branchBuilt or {}) do built = built + (tonumber(n) or 0) end
            if built > 0 then
                H.ok(text:find("ничего не выдал", 1, true) == nil,
                    s.state .. ": при построенных советах (" .. built
                    .. ") сводка не говорит «никто ничего не выдал»")
            end
        end
    end
    H.ok(checked >= 12, "состояний сверено: " .. checked)
end

H.suite("Смысл: строка под списком не называет пустой ветку, советы которой на экране")
do
    local liars = {}
    for _, scr in ipairs(CORPUS.screens) do
        if scr.tab == "NOW" and not scr.state:find("фильтр", 1, true) then
            local summary
            for _, s in ipairs(CORPUS.summaries) do
                if s.state == scr.state then summary = s end
            end
            for _, text in ipairs(scr.texts) do
                for line in S.plain(text):gmatch("[^\n]+") do
                    local label = line:match("^• (.-) — ")
                    if label and summary then
                        for key, lbl in pairs(summary.branchLabel or {}) do
                            if lbl == label then
                                local n = 0
                                for kind, count in pairs(scr.kinds or {}) do
                                    if summary.branchByKind[kind] == key then n = n + count end
                                end
                                if n > 0 then
                                    liars[#liars + 1] = scr.state .. ": «" .. label .. "» (на экране " .. n .. ")"
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    H.eq(#liars, 0, "таких строк нет"
        .. ((#liars > 0) and ("  <- " .. table.concat(liars, "; ")) or ""))
end

-- 7. ОБЕЩАНИЯ ОТ ПЕРВОГО ЛИЦА --------------------------------------------------------
--
-- Инвариант текстов следит за названными кнопками. Это его продолжение на то,
-- что названо ГЛАГОЛОМ: «я прочитаю», «я запишу», «я покажу». Каждый глагол, с
-- которым аддон говорит о себе, записан здесь вместе с тем, чем сказанное
-- подтверждается. Новый глагол - новая запись, иначе тест падает: обещание,
-- которое никто не проверил, в текст не попадёт.

local PROMISES = {
    -- что аддон делает
    ["считаю"] = "движок советов и планировщик: считает на каждом пересчёте",
    ["посчитаю"] = "то же", ["пересчитаю"] = "MainFrame:Rebuild по событию аукциона",
    ["пересчитываю"] = "MainFrame:Rebuild по событиям игры",
    ["прочитаю"] = "RecipeBook: чтение окна профессии по TRADE_SKILL_SHOW",
    ["читаю"] = "CharacterScanner / RecipeBook: чтение сумок, надетого и рецептов",
    ["беру"] = "CraftingPlanner:SkillChance — шанс прироста по цвету рецепта; цены — PriceProvider",
    ["запомню"] = "Config:StoreRecipes — рецепты в SavedVariables",
    ["запишу"] = "Places:RecordMerchant — торговец записывается при открытии",
    ["записываю"] = "Places:RecordMerchant, PriceProvider: суточный слепок цен,"
        .. " Ledger:Settle — своя книга закупок",
    ["заполняю"] = "Ledger:Settle — своя книга закупок пишется из сверки денег"
        .. " с сумками у торговца и у аукциона, test_ledger",
    ["складываю"] = "PriceProvider: суточный слепок цен",
    -- «вы просили держать это в списке покупок, и я держу» - карточка своего
    -- списка. Держит Config:Shopping (SavedVariables) плюс
    -- ShoppingList:LoadPinned: закрепление становится нижней границей закупки на
    -- каждом пересчёте, сколько бы советам ни было нужно.
    ["держу"] = "Config:Shopping + ShoppingList:LoadPinned — закрепление игрока"
        .. " переживает вход в игру и на каждом пересчёте остаётся нижней"
        .. " границей закупки, test_sense (карточка своего списка)",
    ["пишу"] = "PriceProvider: суточный слепок цен",
    ["прохожу"] = "PriceProvider: обход реагентов для слепка цен",
    ["показываю"] = "окно, панель и подсказки",
    ["покажу"] = "RecipeBook:Show / Places:Route — проверяется test_recipe и test_nav",
    ["поставлю"] = "Places:Route: метка и стрелка — test_nav",
    ["передам"] = "ShoppingList:SendToAuctionator — test_handoff",
    ["открою"] = "ShoppingList:SendToAuctionator открывает вкладку покупок — test_handoff",
    ["запущу"] = "то же: поиск Auctionator — test_handoff",
    ["открываю"] = "то же",
    ["листаю"] = "StepPanel:Advance — test_text",
    ["очищу"] = "ShoppingList:RequestClear — test_confirm",
    ["скрою"] = "Dismissal:Request — test_vanish",
    ["оставлю"] = "Dismissal / RequestClear: без второго нажатия ничего не меняется",
    ["помечаю"] = "достоверность у каждого числа (значок на карточке)",
    ["определяю"] = "StatWeights: профиль весов по классу и надетому",
    ["разберу"] = "CraftingPlanner: дерево материалов на вкладке «Крафт»",
    ["вычту"] = "то же: вычитание своих запасов",
    ["сравню"] = "то же: крафт против покупки",
    ["советую"] = "движок советов",
    ["вижу"] = "CharacterScanner: сумки, банк, надетое",
    ["смотрю"] = "Ledger:Settle — сверка денег и сумок у торговца и у аукциона,"
        .. " из неё и берётся книга закупок, test_ledger",
    ["знаю"] = "данные аддона: знает или прямо говорит, что не знает",
    ["верю"] = "SanityChecks / SourceCheck: кому из источников доверие",
    ["могу"] = "ограничения клиента, названные прямо",
    ["буду"] = "настройка «не проверять броню по классу»: GearAdvisor",
    ["назову"] = "ShoppingList:Affordability: сумма списка",
    ["говорю"] = "Notifier: сообщения о сделке и потолке",
    -- «я предупреждаю, а не запрещаю» - подробность про облик вещи
    -- (Logic/Appearance.lua). Обещание именно в том, что аддон НЕ запрещает:
    -- карточка остаётся, кнопка остаётся, выгода остаётся - проверяется
    -- test_appearance, а запрета в текстах не бывает вовсе (правило «запрет» в
    -- Tests/sense.lua).
    ["предупреждаю"] = "Logic/Appearance.lua: про облик сказано ДО продажи,"
        .. " распыла и пересылки, и совет при этом остаётся исполнимым -"
        .. " test_appearance",
    ["прошу"] = "RecipeBook:Show: не просит клиент повторно после отказа — test_recipe",
    ["берусь"] = "RecipeBook:ShowState: не открывает окно профессий первым — test_recipe",
    ["спрашивал"] = "—",
    -- чего аддон НЕ делает (проверяется набором «в коде нет ни одного такого вызова»)
    ["покупаю"] = "НЕ делает: вызовов покупки в коде нет",
    ["продаю"] = "НЕ делает: вызовов продажи в коде нет",
    ["выставляю"] = "НЕ делает: вызовов аукциона в коде нет",
    ["делаю"] = "НЕ делает сам: только советует",
    ["надеваю"] = "НЕ делает: вызовов экипировки в коде нет",
    ["управляю"] = "НЕ делает: экипировка, почта, банк, аукцион",
    ["пересылаю"] = "НЕ делает: вызовов почты в коде нет",
    ["распыляю"] = "НЕ делает: вызовов применения предметов в коде нет",
    ["выбираю"] = "НЕ делает: выбор пути оставлен игроку",
    ["прячу"] = "НЕ делает без двух щелчков: test_vanish",
    ["убираю"] = "то же",
    ["гадаю"] = "НЕ делает: неизвестное названо неизвестным",
    -- «под ваши профессии я справочник не дополняю» - строка раздела «Откуда я
    -- всё это знаю». Проверяется test_sources: справочник - статический файл
    -- Data/ForeverSource.lua, и ни пересчёт, ни сверка в него не пишут.
    ["дополняю"] = "НЕ делает: справочник статический, test_sources проверяет,"
        .. " что сверка его не меняет",
    ["придумываю"] = "то же", ["выдумываю"] = "то же",
    ["утверждаю"] = "то же", ["использую"] = "НЕ делает: чужой код не используется",
    ["трогаю"] = "НЕ делает: чужие окна и данные",
    -- «денежные советы ниже порога я в список не ставлю» - раздел настроек
    -- «Мелкая денежная выгода». Делает Engine:ApplyMoneyFloor; что при этом на
    -- экране сказано, сколько убрано, проверяет test_economy и test_vanish.
    ["ставлю"] = "Engine:ApplyMoneyFloor: денежный совет ниже порога в список не"
        .. " попадает, и об этом сказано строкой над списком - test_economy,"
        .. " test_vanish",
}

-- Слова на «-у/-ю», которые глаголами не являются.
local NOT_VERBS = {}
for _, w in ipairs({ "цену", "вещь", "эту", "одну", "ту", "свою", "всю", "формулу", "карточку",
    "позицию", "штуку", "минуту", "секунду", "профессию", "покупку", "находку", "строку",
    "ветку", "категорию", "ошибку", "сумму", "стрелку", "метку", "точку", "кнопку",
    "вкладку", "панель", "игру", "броню", "стоимость", "почту", "базу", "историю",
    "выручку", "прибыль", "сделку", "экипировку", "причину", "разницу", "полную",
    "рыночную", "такую", "готовую", "любую", "каждую", "саму", "нужную", "внешнюю",
    "вашу", "мою", "нашу", "его", "её", "их", "ничего", "ещё", "уже", "тут", "ему",
    "одному", "этому", "тому", "всему", "самому", "списку", "совету", "торговцу",
    "навыку", "классу", "слоту", "поиску", "уровню", "аукциону", "почему", "потому",
    "поэтому", "сколько-нибудь", "никому", "кому", "чему", "сейчас" }) do NOT_VERBS[w] = true end

local function firstPersonVerbs(text)
    local out = {}
    local toks = Sense.tokens(S.plain(text))
    local words = {}
    for _, t in ipairs(toks) do
        if t.kind == "word" then
            words[#words + 1] = Sense.lower(t.text)
        elseif t.kind == "other" and t.text:match("[%.!%?;:]") then
            words[#words + 1] = "."          -- граница фразы
        end
    end
    for i, w in ipairs(words) do
        if w == "я" then
            for j = i + 1, math.min(#words, i + 4) do
                local cand = words[j]
                if cand == "." then break end
                local tail = cand:sub(-2)
                if (tail == "\209\131" or tail == "\209\142") and not NOT_VERBS[cand] then
                    out[#out + 1] = cand
                    break
                end
            end
        end
    end
    return out
end

H.suite("Смысл: всё, что аддон говорит о себе от первого лица, записано и подтверждено")
do
    -- Сам детектор: находит глагол и не принимает за него существительное.
    local probe = firstPersonVerbs("Я ничего не покупаю. Цену я не знаю — поэтому не гадаю. я прочитаю рецепты сам")
    H.eq(table.concat(probe, ","), "покупаю,знаю,прочитаю", "детектор находит глаголы первого лица")
    H.eq(#firstPersonVerbs("я эту цену уже видел"), 0, "и не принимает «цену» за глагол")

    local seen, unknown = {}, {}
    for _, l in ipairs(CORPUS.lines) do
        for _, verb in ipairs(firstPersonVerbs(l.text)) do
            seen[verb] = (seen[verb] or 0) + 1
            if not PROMISES[verb] and not unknown[verb] then unknown[verb] = l.where end
        end
    end
    local count = 0
    for _ in pairs(seen) do count = count + 1 end
    H.ok(count >= 15, "разных глаголов первого лица в текстах: " .. count)
    local list = {}
    for verb, where in pairs(unknown) do list[#list + 1] = "«я … " .. verb .. "» [" .. where .. "]" end
    table.sort(list)
    H.eq(#list, 0, "незаписанных обещаний нет"
        .. ((#list > 0) and ("  <- " .. table.concat(list, "; ")) or ""))
end

H.suite("Смысл: «не покупаю, не продаю, не крафчу» — в коде нет ни одного такого вызова")
do
    -- То, что аддон обещает НЕ делать, проверяется не текстом, а кодом: имён
    -- этих функций игры в файлах аддона быть не должно вовсе.
    local FORBIDDEN = {
        "BuyMerchantItem", "PickupMerchantItem", "BuybackItem", "SellCursorItem",
        "UseContainerItem", "PickupContainerItem", "UseItemByName", "EquipItemByName",
        "EquipCursorItem", "DeleteCursorItem", "PlaceAuctionBid", "PostAuction",
        "StartAuction", "C_AuctionHouse%.PlaceBid", "C_AuctionHouse%.PostItem",
        "C_AuctionHouse%.PostCommodity", "C_AuctionHouse%.StartCommoditiesPurchase",
        "C_AuctionHouse%.ConfirmCommoditiesPurchase", "SendMail", "TakeInboxItem",
        "C_TradeSkillUI%.CraftRecipe", "DoTradeSkill", "DoCraft", "CastSpellByName",
        "CastSpellByID", "BuyTrainerService", "AcceptTrade", "InitiateTrade",
        "C_Bank%.AutoDepositItemsIntoBank", "UseInventoryItem", "RunMacroText",
        "C_TradeSkillUI%.OpenTradeSkill", "ShowUIPanel", "HideUIPanel",
    }
    local files, offenders = {}, {}
    for line in io.lines(ROOT .. "/ForeverPilot.toc") do
        local rel = line:gsub("\r", ""):gsub("\\", "/"):gsub("^%s+", ""):gsub("%s+$", "")
        if rel:match("%.lua$") then files[#files + 1] = rel end
    end
    for _, rel in ipairs(files) do
        local f = io.open(ROOT .. "/" .. rel, "r")
        if f then
            local n = 0
            for line in f:lines() do
                n = n + 1
                local code = line:gsub("%-%-.*$", "")
                for _, name in ipairs(FORBIDDEN) do
                    if code:find("%f[%w_]" .. name .. "%f[^%w_]") then
                        offenders[#offenders + 1] = rel .. ":" .. n .. " " .. name:gsub("%%", "")
                    end
                end
            end
            f:close()
        end
    end
    H.ok(#files >= 40, "файлов из .toc просмотрено: " .. #files)
    H.eq(#offenders, 0, "ни одного действующего вызова в коде нет"
        .. ((#offenders > 0) and ("  <- " .. table.concat(offenders, "; ")) or ""))
end

-- 8. НАСТОЯЩИЕ ДАННЫЕ ИГРОКА ---------------------------------------------------------
--
-- Числа без смысла приходят из данных: «2433% наценки» и «в 25.3 раз» не
-- родятся в мире из трёх предметов. Поэтому те же правила идут по советам,
-- построенным на настоящих сохранённых данных, во всех четырёх профилях.
-- Мир строит тот же скрипт, которым его смотрит человек (Tests/inspect_real.lua):
-- второго описания «как собрать настоящий мир без игры» в проекте нет.

local function realWorld()
    local path = ROOT .. "/Tests/inspect_real.lua"
    local chunk = loadfile(path)
    if not chunk then return nil, "нет Tests/inspect_real.lua" end
    local captured
    local proxyH = setmetatable({
        load = function(opts)
            local env = H.load(opts)
            captured = captured or env
            return env
        end,
    }, { __index = H })
    local osProxy = setmetatable({ exit = function() error("выход из скрипта осмотра", 0) end },
        { __index = os })
    local sandbox = setmetatable({
        print = function() end,
        os = osProxy,
        io = setmetatable({ write = function() end }, { __index = io }),
        loadfile = function(p, ...)
            if type(p) == "string" and p:match("[/\\]harness%.lua$") then
                return function() return proxyH end
            end
            return loadfile(p, ...)
        end,
    }, { __index = _G })
    setfenv(chunk, sandbox)
    local savedClock, savedServer = H.clock, H.serverTime
    local ok, err = pcall(chunk)
    if not captured then
        H.clock, H.serverTime = savedClock, savedServer
        return nil, tostring(err)
    end
    return captured
end

do
    -- Есть ли рядом настоящие данные - спрашивается в Tests/paths.lua, тем же
    -- способом, которым их потом и читают. Своего описания «где лежит WTF» у
    -- этого набора нет сознательно: разойдись они - и набор либо пропустит
    -- проверку при живых данных, либо пойдёт по пустоте.
    local P = assert(loadfile(ROOT .. "/Tests/paths.lua"))()
    local realSV, pathInfo = P.savedVariables(ROOT)

    if not realSV then
        H.note("test_sense: проверка «на настоящих данных» пропущена — " .. pathInfo.reason)
    else
        H.suite("Смысл: те же правила на настоящих данных игрока")
        local env, why = realWorld()
        H.ok(env ~= nil, "настоящий мир собран" .. ((not env) and (": " .. tostring(why)) or ""))
        if env then
            local ns = env.ns
            local lines, cards = {}, 0
            for _, profile in ipairs(ns.PROFILE_ORDER or { "POWER" }) do
                ns.Config:SetProfile(profile)
                H.build(env)
                local label = (ns.PROFILE_LABEL and ns.PROFILE_LABEL[profile]) or profile
                for _, card in ipairs(ns.ActionEngine.cards or {}) do
                    cards = cards + 1
                    local where = "настоящие данные / " .. label .. " / «" .. tostring(card.title) .. "»"
                    for _, field in ipairs({ "title", "benefit", "why", "need" }) do
                        if type(card[field]) == "string" and card[field] ~= "" then
                            lines[#lines + 1] = { text = card[field], channel = field, where = where }
                        end
                    end
                end
                pcall(function() ns.Diag:WriteSummary() end)
                for _, line in ipairs(ns.Diag:Init().summary or {}) do
                    lines[#lines + 1] = { text = tostring(line), channel = "summary",
                        where = "настоящие данные / " .. label .. " / сводка" }
                end
            end
            H.ok(cards > 40, "советов на настоящих данных: " .. cards .. " (во всех профилях)")
            local found = findingsIn(lines)
            for _, rule in ipairs(Sense.RULES) do
                local list = found[rule.name] or {}
                H.eq(#list, 0, rule.name .. ": находок нет"
                    .. ((#list > 0) and ("  <- " .. preview(list, 6)) or ""))
            end

            -- И РАЗМЕТКА - ТОЖЕ НА НАСТОЯЩИХ ДАННЫХ.
            --
            -- Выдуманные советы короткие, и по ним не видно того, на что игрок
            -- жалуется: «Разница +8з 80…», «Торговец: …, 78.2 5…». Настоящий
            -- совет - 400 с лишним символов в строке на 100, и именно здесь
            -- видно, что из него останется на экране.
            S.attachUI(H, env)
            ns.Config:SetProfile(ns.PROFILE_ORDER[1])
            H.build(env)
            ns.MainFrame:Build()
            ns.MainFrame:Select("NOW")
            S.layout(env)
            ns.MainFrame:RenderActive()

            local strip = ns.TabNow.strip
            local stripText = (strip and strip.__shown and strip.text:GetText()) or nil
            if stripText then
                H.eq(stripText:find("\n", 1, true), nil,
                    "над списком одна строка: " .. stripText)
                H.ok(S.textWidth(S.plain(stripText)) <= (strip.__width or 0) + 0.5,
                    "и она влезает: " .. S.textWidth(S.plain(stripText))
                    .. " при " .. tostring(strip.__width))
                H.ok(stripText:find(ns.TabNow.DETAILS_HINT, 1, true) ~= nil,
                    "и путь к подробностям в ней назван")
                H.ok(#(strip.details or {}) > 0, "а подробности есть под курсором")
            else
                H.ok(true, "над списком сейчас нечего говорить — строки нет")
            end

            local drawn, over, lost = 0, {}, {}
            for _, row in ipairs(ns.Card.pool) do
                if row.__shown and row.card then
                    local room = ns.Card.RoomFor(row, row.card)
                    for _, pair in ipairs({ { "заголовок", row.title, row.card.title, room.title },
                                            { "выгода", row.benefit, row.card.benefit, room.benefit } }) do
                        local text = S.plain(pair[2]:GetText() or "")
                        if text ~= "" then
                            drawn = drawn + 1
                            local width = S.textWidth(text)
                            if width > pair[4] + 0.5 then
                                over[#over + 1] = pair[1] .. ": " .. width .. " при "
                                    .. string.format("%.0f", pair[4]) .. " — " .. text
                            end
                            local full = S.plain(tostring(pair[3] or ""))
                            local coords = full:match(ns.Util.COORDS)
                            if coords and not text:find(coords, 1, true) then
                                lost[#lost + 1] = pair[1] .. ": координаты «" .. coords
                                    .. "» выброшены — " .. text
                            end
                            for _, atom in ipairs(ns.Util.atoms(text)) do
                                -- Знак в конце не считается: снятое пояснение в
                                -- скобках притягивает к числу точку самой
                                -- фразы («Кулинария 150/150 (…)» → «150/150.»).
                                local group = atom.text:gsub("[%.,;:…]+$", "")
                                if atom.number and group ~= ""
                                    and not full:find(group, 1, true) then
                                    lost[#lost + 1] = pair[1] .. ": число «" .. group
                                        .. "» разрезано — " .. text
                                end
                            end
                        end
                    end
                end
            end
            H.ok(drawn > 10, "строк на экране по настоящим данным: " .. drawn)

            -- И ЦЕНА ЭТОЙ ОТРИСОВКИ - В ВЫЗОВАХ, НА НАСТОЯЩИХ ДАННЫХ.
            --
            -- Игрок пожаловался на фризы. В FOREVERPILOT_DIAG видно только
            -- пересчёт (средний 40 мс, пик 112), и это неполная картина:
            -- таймер обнимает ActionEngine:Build, а отрисовка идёт после него и
            -- в эти числа не входит вовсе.
            --
            -- А стоила она дорого, и видно это только здесь: выдуманный совет
            -- короткий, а настоящий - 400 с лишним символов в строке на 100,
            -- то есть укорачивать приходится почти каждую. Измерено на этом же
            -- мире: одна отрисовка строила 663 строки-варианта и просила
            -- клиент померить ширину 330 раз - и делала это ЗАНОВО при каждой
            -- отрисовке, включая те, где не изменилось ничего.
            --
            -- Миллисекунды здесь мерить нельзя (поддельный GetStringWidth -
            -- обращение к таблице, настоящий дороже на три порядка), а число
            -- вызовов переносится в игру один в один.
            local W = ns.Widgets
            local counted = { calls = 0, variants = 0 }
            local realShort = ns.Util.shortenings
            ns.Util.shortenings = function(text)
                counted.calls = counted.calls + 1
                local out = realShort(text)
                counted.variants = counted.variants + #out
                return out
            end
            -- Окно другой ширины - то же, что игрок делает мышью за край.
            -- Место у каждой строки изменилось, значит мерить надо заново: это
            -- и есть «первая» отрисовка, и считать её надо на изменившемся
            -- мире, а не на том, который только что нарисовали.
            -- Берётся самое узкое окно: в нём укорачивать приходится больше
            -- всего, то есть это и самая дорогая отрисовка из возможных.
            W.fitMemoHits, W.fitMemoMisses = 0, 0
            S.layout(env, ns.MainFrame.MIN_WIDTH, ns.MainFrame.MIN_HEIGHT)
            ns.MainFrame:RenderActive()
            local firstCalls, firstVariants = counted.calls, counted.variants
            H.ok(firstCalls > 0, "отрисовка в окне другой ширины строит варианты"
                .. " заново: " .. firstCalls .. " обращений, " .. firstVariants .. " строк")
            H.ok((W.fitMemoMisses or 0) > 0,
                "память на другой ширине не отвечает: промахов "
                .. tostring(W.fitMemoMisses))
            -- Повторные: ни одного.
            counted.calls, counted.variants = 0, 0
            W.fitMemoHits = 0
            for _ = 1, 3 do ns.MainFrame:RenderActive() end
            ns.Util.shortenings = realShort
            H.eq(counted.calls, 0, "три повторные отрисовки не строят вариантов"
                .. " (было бы " .. (firstCalls * 3) .. " обращений)")
            H.eq(counted.variants, 0, "и ни одной строки-варианта"
                .. " (было бы " .. (firstVariants * 3) .. ")")
            H.ok((W.fitMemoHits or 0) > 0,
                "память укороченных строк отвечала на настоящих данных: попаданий "
                .. tostring(W.fitMemoHits))
            print(string.format("     отрисовка списка: после смены ширины — %d"
                .. " обращений и %d вариантов, повторные — 0",
                firstCalls, firstVariants))
            H.eq(#over, 0, "ни одна не вылезает за своё место"
                .. ((#over > 0) and ("  <- " .. table.concat(over, "  ;;  ", 1,
                    math.min(4, #over))) or ""))
            H.eq(#lost, 0, "ни одно число и ни одни координаты не потеряны"
                .. ((#lost > 0) and ("  <- " .. table.concat(lost, "  ;;  ", 1,
                    math.min(4, #lost))) or ""))
        end
    end
end

end
