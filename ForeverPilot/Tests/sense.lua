-- ForeverPilot / Tests/sense.lua
--
-- ДЕТЕКТОРЫ ЧУШИ. Не набор тестов: набор правил, по которым Tests/test_sense.lua
-- проверяет всё, что аддон говорит игроку (собрание - Tests/corpus.lua).
--
-- Игрок не технический и ловит чушь глазами. Каждое правило здесь - это то, что
-- он уже поймал или поймал бы, записанное так, чтобы в следующий раз это поймал
-- прогон тестов, а не он:
--
--   * склеенные и оборванные фразы: «…мало) За 3 дня», «не учтён..», фраза с
--     маленькой буквы после точки;
--   * крик: СЛОВА ЗАГЛАВНЫМИ посреди обычного текста;
--   * слово из двух алфавитов («магa» с латинской «a»);
--   * мусор вместо значения: %d, nil, table:, nan;
--   * слова разработчика: itemID, EXACT, «drops-main-stat», C_Item.GetItemInfo;
--   * число и слово не согласованы: «7 находки», «2 видов», «в 25.3 раз»;
--   * числа без смысла: «0м за крафт», «0 из 0», «в 600 раз больше, чем 0м»,
--     «0 уровень», проценты, которых не бывает.
--
-- Каждое правило возвращает список находок: { rule, text, hit }. Пустой список -
-- текст чист. Правила не знают, откуда текст: это знает собрание.
local Sense = {}

-- UTF-8 -----------------------------------------------------------------------

local function utf8chars(s)
    return tostring(s):gmatch("[%z\1-\127\194-\244][\128-\191]*")
end

local function isUpperCyr(ch)
    local a, b = ch:byte(1, 2)
    return a == 208 and b ~= nil and ((b >= 144 and b <= 175) or b == 129)
end

local function isLowerCyr(ch)
    local a, b = ch:byte(1, 2)
    if a == 208 then return b ~= nil and b >= 176 and b <= 191 end
    if a == 209 then return b ~= nil and ((b >= 128 and b <= 143) or b == 145) end
    return false
end

local function isLatin(ch) return #ch == 1 and ch:match("%a") ~= nil end
local function isLetter(ch) return isLatin(ch) or isUpperCyr(ch) or isLowerCyr(ch) end

local function lowerCyr(word)
    local out = {}
    for ch in utf8chars(word) do
        local a, b = ch:byte(1, 2)
        if a == 208 and b and b >= 144 and b <= 159 then
            out[#out + 1] = string.char(208, b + 32)
        elseif a == 208 and b and b >= 160 and b <= 175 then
            out[#out + 1] = string.char(209, b - 32)
        elseif a == 208 and b == 129 then
            out[#out + 1] = string.char(209, 145)
        else
            out[#out + 1] = ch:lower()
        end
    end
    return table.concat(out)
end
Sense.lower = lowerCyr
Sense.isUpperCyr, Sense.isLowerCyr = isUpperCyr, isLowerCyr

-- Текст как список лексем: { kind = "word"|"num"|"other", text = ... }.
-- Слово - подряд идущие буквы (и дефис внутри); число - цифры с точкой/запятой.
local function tokens(text)
    local out, cur, curKind = {}, {}, nil
    local function flush()
        if #cur > 0 then
            out[#out + 1] = { kind = curKind, text = table.concat(cur) }
            cur, curKind = {}, nil
        end
    end
    local list = {}
    for ch in utf8chars(text) do list[#list + 1] = ch end
    for i, ch in ipairs(list) do
        local kind
        if isLetter(ch) then
            kind = "word"
        elseif ch:match("%d") then
            kind = (curKind == "word") and "word" or "num"
        elseif (ch == "." or ch == ",") and curKind == "num"
            and list[i + 1] and list[i + 1]:match("%d") then
            kind = "num"
        elseif ch == "-" and curKind == "word" and list[i + 1] and isLetter(list[i + 1]) then
            kind = "word"
        else
            kind = "other"
        end
        if kind == "other" then
            flush()
            out[#out + 1] = { kind = "other", text = ch }
        else
            if curKind and curKind ~= kind then flush() end
            curKind = kind
            cur[#cur + 1] = ch
        end
    end
    flush()
    return out
end
Sense.tokens = tokens

local function finding(rule, text, hit)
    return { rule = rule, text = text, hit = hit }
end

-- Кусок текста вокруг позиции - чтобы находку можно было узнать.
local function around(text, s, e)
    local from = math.max(1, s - 40)
    local to = math.min(#text, (e or s) + 40)
    -- не резать посреди символа UTF-8
    while from > 1 and text:byte(from) >= 128 and text:byte(from) < 192 do from = from - 1 end
    while to < #text and text:byte(to + 1) and text:byte(to + 1) >= 128
        and text:byte(to + 1) < 192 do to = to + 1 end
    return (from > 1 and "…" or "") .. text:sub(from, to) .. (to < #text and "…" or "")
end

-- 1. ПУНКТУАЦИЯ ---------------------------------------------------------------

-- Сокращения, после точки которых фраза продолжается с маленькой буквы.
Sense.ABBREVIATIONS = {
    ["ед"] = true, ["ур"] = true, ["шт"] = true, ["напр"] = true, ["см"] = true,
    ["мин"] = true, ["сек"] = true, ["макс"] = true, ["физ"] = true, ["т"] = true,
    ["др"] = true, ["тыс"] = true, ["стр"] = true, ["г"] = true, ["п"] = true,
}

function Sense.punctuation(text)
    local out = {}
    local n = #text

    -- «..»: две точки, после которых пробел или конец. Диапазон цен «85с..1з»
    -- сюда не попадает (после точек сразу значение), многоточие - тоже.
    local pos = 1
    while true do
        local s, e = text:find("%.%.+", pos)
        if not s then break end
        local len = e - s + 1
        local after = text:sub(e + 1, e + 1)
        if len == 2 and (after == "" or after:match("%s")) then
            out[#out + 1] = finding("две точки подряд", text, around(text, s, e))
        end
        pos = e + 1
    end

    for _, bad in ipairs({ { ",,", "две запятые подряд" }, { " ,", "пробел перед запятой" },
                           { " %.%f[%s%z]", "пробел перед точкой" }, { "!!", "два восклицательных знака" },
                           { "%?%?", "два вопросительных знака" }, { ":%.", "двоеточие и точка" },
                           { "%.:", "точка и двоеточие" }, { ",%.", "запятая и точка" },
                           { ".%(%s*%)", "пустые скобки" } }) do
        -- «( ) Лечение» в начале подписи - невыбранный переключатель, а не
        -- пустые скобки: образец требует хотя бы одного символа перед ними.
        local s, e = text:find(bad[1])
        if s then out[#out + 1] = finding(bad[2], text, around(text, s, e)) end
    end

    -- Фраза с маленькой буквы после точки.
    local toks = tokens(text)
    for i = 2, #toks - 1 do
        local t = toks[i]
        if t.kind == "other" and (t.text == "." or t.text == "!" or t.text == "?") then
            -- следующая значимая лексема
            local j = i + 1
            local sawSpace = false
            while toks[j] and toks[j].kind == "other" and toks[j].text:match("^%s$") do
                sawSpace = true
                j = j + 1
            end
            local nextTok, prevTok = toks[j], toks[i - 1]
            if sawSpace and nextTok and nextTok.kind == "word" and prevTok then
                local first = nextTok.text:match("^[%z\1-\127\194-\244][\128-\191]*")
                local abbr = prevTok.kind == "word" and Sense.ABBREVIATIONS[lowerCyr(prevTok.text)]
                -- «1 час назад.. Auctionator» ловит правило про две точки; здесь
                -- только русская маленькая буква после настоящего конца фразы.
                if first and isLowerCyr(first) and not abbr and t.text == "."
                    and prevTok.kind ~= "other" then
                    out[#out + 1] = finding("фраза с маленькой буквы после точки", text,
                        prevTok.text .. ". " .. nextTok.text)
                end
            end
        end
    end

    -- Две фразы склеены без точки: «…мало) За 3 дня», «…2 позиции Это в 10 раз».
    for i = 3, #toks do
        local t = toks[i]
        if t.kind == "word" and Sense.SENTENCE_STARTERS[t.text]
            and toks[i - 1].kind == "other" and toks[i - 1].text == " " then
            local prev = toks[i - 2]
            local glued = false
            if prev.kind == "other" and prev.text == ")" then
                glued = true
            elseif prev.kind == "word" or prev.kind == "num" then
                local last = prev.text:match("[%z\1-\127\194-\244][\128-\191]*$")
                glued = last ~= nil and (isLowerCyr(last) or last:match("%d") ~= nil)
            end
            if glued then
                out[#out + 1] = finding("две фразы склеены без точки", text,
                    prev.text .. " " .. t.text)
            end
        end
    end
    return out
end

-- Слова, с которых в этих текстах начинается новая фраза. Имена собственные
-- (названия предметов, зон) сюда не входят, поэтому «лучше, чем Ремень Келлера»
-- склейкой не считается.
Sense.SENTENCE_STARTERS = {}
for _, w in ipairs({ "Это", "Сейчас", "За", "На", "Цена", "Цену", "Если", "Но", "Может",
    "Наличие", "Осторожно", "Вероятности", "Ещё", "Раньше", "Когда", "Выборка",
    "Зайдите", "Откройте", "Нажмите", "Я", "Вы", "Что", "Чтобы", "Сколько", "Так",
    "Значит", "Поэтому", "Только", "Формулы", "Выученных", "Наценка", "Разница",
    "Материалы", "Своей", "Всего", "Покупать", "Перешлите", "Сделать", "Считал",
    -- Слова, которыми начинаются фразы про вендорный потолок: «У торговца
    -- дешевле…», «У какого торговца — не знаю…», «Эту цену записал
    -- Auctionator…», «Из этого списка N позиций дешевле…», «Выше прилавка у вас
    -- покупать незачем…», «Дешевле N за штуку выставлять нельзя…». Без них
    -- правило про склейку эти фразы не читало вовсе: оно ищет начало новой
    -- фразы по известному слову.
    "У", "Эту", "Из", "Выше", "Дешевле" }) do
    Sense.SENTENCE_STARTERS[w] = true
end

-- 2. КРИК И ДВА АЛФАВИТА ---------------------------------------------------------

-- Заглавными пишутся только настоящие сокращения. Список пуст намеренно: «ЛКМ»
-- и «ПКМ» игроку, который не играет годами, тоже ничего не говорят.
Sense.CAPS_ALLOWED = {}

function Sense.shouting(text)
    local out = {}
    for _, t in ipairs(tokens(text)) do
        if t.kind == "word" then
            local upper, lower, n = 0, 0, 0
            for ch in utf8chars(t.text) do
                n = n + 1
                if isUpperCyr(ch) then upper = upper + 1
                elseif isLowerCyr(ch) then lower = lower + 1 end
            end
            if lower == 0 and upper == n and (n >= 3 or t.text == "НЕ")
                and not Sense.CAPS_ALLOWED[t.text] then
                out[#out + 1] = finding("слово заглавными буквами", text, t.text)
            end
        end
    end
    return out
end

function Sense.mixedScript(text)
    local out = {}
    for _, t in ipairs(tokens(text)) do
        if t.kind == "word" then
            local lat, cyr = 0, 0
            for ch in utf8chars(t.text) do
                if isLatin(ch) then lat = lat + 1
                elseif isUpperCyr(ch) or isLowerCyr(ch) then cyr = cyr + 1 end
            end
            if lat > 0 and cyr > 0 then
                out[#out + 1] = finding("в одном слове русские и латинские буквы", text, t.text)
            end
        end
    end
    return out
end

-- 3. МУСОР И СЛОВА РАЗРАБОТЧИКА ---------------------------------------------------

function Sense.garbage(text)
    local out = {}
    for _, bad in ipairs({
        { "%%[sdfiq]", "непрочитанная подстановка" }, { "%%%.%d", "непрочитанная подстановка" },
        { "%f[%a]nil%f[%A]", "nil вместо значения" }, { "table: 0?x?%x+", "адрес таблицы" },
        { "function: ", "адрес функции" }, { "userdata", "userdata" },
        { "%f[%a]nan%f[%A]", "nan" }, { "%f[%a]inf%f[%A]", "inf" }, { "%-nan", "nan" },
        { "{%.%.%.}", "заглушка {...}" },
    }) do
        local s, e = text:find(bad[1])
        if s then out[#out + 1] = finding("мусор вместо значения: " .. bad[2], text, around(text, s, e)) end
    end
    return out
end

-- Чего в тексте для игрока быть не должно. Образцы Lua; рядом - что это.
Sense.JARGON = {
    { "itemID", "имя поля" }, { "npcID", "имя поля" }, { "spellID", "имя поля" },
    { "recipeID", "имя поля" }, { "skillLineID", "имя поля" }, { "categoryID", "имя поля" },
    { "%f[%a]GUID%f[%A]", "служебное слово" },
    { "%f[%a]EXACT%f[%A]", "код достоверности" }, { "%f[%a]CACHED%f[%A]", "код достоверности" },
    { "%f[%a]ESTIMATE%f[%A]", "код достоверности" }, { "%f[%a]UNKNOWN%f[%A]", "код достоверности" },
    -- «SavedVariables» сюда не входит: это имя папки, и назвать его - единственный
    -- способ сказать игроку, где лежит файл диагностики.
    { "FOREVERPILOT_DIAG", "имя переменной" }, { "WOW_PROJECT", "имя константы" },
    { "%f[%a]modules%f[%A]", "имя поля" }, { "%f[%a]recordings%f[%A]", "имя источника данных" },
    { "C_%a+%.%a+", "имя функции игры" }, { "%f[%a]Get%u%a+", "имя функции игры" },
    { "«%l[%l%-]*%-[%l%-]+»", "внутренний код причины" },
    { "%f[%a]%l+%u%l+%f[%A]", "имя из кода" },
    { "гейт", "жаргон" }, { "слой%-адаптер", "жаргон разработчика" },
    { "%f[%a]API%f[%A]", "жаргон разработчика" },
    { "оценка кита", "жаргон" },
    -- «ед. пользы» - единица измерения, которой не существует. Игрок прочитал
    -- «+0 ед. пользы» и спросил, в чём это измеряется; ответить было нечем.
    -- Теперь то же число называется баллом (ns.UNIT_BENEFIT), а старое
    -- сокращение стоит здесь, чтобы не вернулось: ни «ед. пользы», ни «ед.»
    -- после числа.
    { "ед%. пользы", "единица, которой не существует" },
    { "%d+%s*ед%.", "сокращение разработчика вместо слова" },
}

function Sense.jargon(text)
    local out = {}
    for _, bad in ipairs(Sense.JARGON) do
        local s, e = text:find(bad[1])
        if s then
            out[#out + 1] = finding("слово разработчика (" .. bad[2] .. ")", text, text:sub(s, e))
        end
    end
    return out
end

-- 3a. АНГЛИЙСКОЕ ИМЯ ПРОФЕССИИ В РУССКОМ ТЕКСТЕ ------------------------------------
--
-- Живой файл игрока: «в справочнике нет рецептов ни по одной из ваших профессий
-- (Alchemy, Cooking, Engineering): сверять не с чем». Клиент русский, и ни одно
-- из этих трёх слов игрок у себя в игре не видел: так профессии называет наш
-- справочник (Data/ForeverSource.lua), и показывать эти имена он прямо
-- запрещает. Прошлая сессия списала находку на тестовый стенд - зря: имена
-- подставлял Logic/SourceCheck.lua, переведя клиентские в английские ради
-- поиска по справочнику и забыв перевести обратно.
--
-- Правило закрывает ВСЕ такие места сразу, а не одно: любое английское имя
-- профессии в русской фразе - находка. Имена - те же, что в
-- RecipeBook.NAME_BRIDGE, то есть список закрыт и известен.
--
-- ПОЧЕМУ ТОЛЬКО В ТЕКСТЕ С КИРИЛЛИЦЕЙ: строка без русских букв - это ключ,
-- имя файла или адрес, а не речь (так же поступает Sense.hasCyrillic ниже).
Sense.PROFESSIONS_EN = {}
for _, name in ipairs({ "tailoring", "leatherworking", "blacksmithing", "engineering",
    "jewelcrafting", "inscription", "alchemy", "enchanting", "cooking",
    "fishing", "mining", "herbalism", "skinning", "archaeology" }) do
    Sense.PROFESSIONS_EN[name] = true
end
-- «First Aid» - два слова, и по лексемам его не узнать: ловится целиком.
Sense.PROFESSIONS_EN_PHRASES = { "first aid" }

function Sense.professionNames(text)
    local out = {}
    if not Sense.hasCyrillic(text) then return out end
    for _, t in ipairs(tokens(text)) do
        if t.kind == "word" and Sense.PROFESSIONS_EN[t.text:lower()] then
            out[#out + 1] = finding("английское имя профессии в русском тексте", text, t.text)
        end
    end
    local low = text:lower()
    for _, phrase in ipairs(Sense.PROFESSIONS_EN_PHRASES) do
        local s, e = low:find(phrase, 1, true)
        if s then
            out[#out + 1] = finding("английское имя профессии в русском тексте", text,
                text:sub(s, e))
        end
    end
    return out
end

-- 4. ЧИСЛО И СЛОВО ------------------------------------------------------------------

-- Существительные, которые в текстах стоят после числа: { один, два-четыре,
-- пять и больше [, винительный единственного, если отличается] }.
Sense.NOUNS = {
    { "совет", "совета", "советов" }, { "позиция", "позиции", "позиций", "позицию" },
    { "рецепт", "рецепта", "рецептов" }, { "раз", "раза", "раз" },
    { "находка", "находки", "находок", "находку" }, { "штука", "штуки", "штук", "штуку" },
    { "слот", "слота", "слотов" }, { "профессия", "профессии", "профессий", "профессию" },
    { "покупка", "покупки", "покупок", "покупку" }, { "вариант", "варианта", "вариантов" },
    { "день", "дня", "дней" }, { "час", "часа", "часов" },
    { "минута", "минуты", "минут", "минуту" }, { "секунда", "секунды", "секунд", "секунду" },
    { "карточка", "карточки", "карточек", "карточку" }, { "запись", "записи", "записей" },
    { "предмет", "предмета", "предметов" }, { "формула", "формулы", "формул", "формулу" },
    { "путь", "пути", "путей" }, { "вид", "вида", "видов" }, { "пункт", "пункта", "пунктов" },
    { "торговец", "торговца", "торговцев" }, { "ветка", "ветки", "веток", "ветку" },
    { "наблюдение", "наблюдения", "наблюдений" }, { "лот", "лота", "лотов" },
    { "крафт", "крафта", "крафтов" }, { "шаг", "шага", "шагов" },
    { "персонаж", "персонажа", "персонажей" }, { "место", "места", "мест" },
    { "запрос", "запроса", "запросов" }, { "категория", "категории", "категорий", "категорию" },
    { "ошибка", "ошибки", "ошибок", "ошибку" }, { "странность", "странности", "странностей" },
    { "пересчёт", "пересчёта", "пересчётов" }, { "источник", "источника", "источников" },
    { "строка", "строки", "строк", "строку" }, { "уровень", "уровня", "уровней" },
    -- Польза от вещи, которую аддон считает по весам характеристик. Слово
    -- добавлено вместе с заменой «ед. пользы» на «балл»: сокращение не
    -- склоняется и потому согласования не требовало, а живое слово требует, и
    -- «+2 балл» в столбце выгоды - ровно та чушь, которую этот раздел ловит.
    { "балл", "балла", "баллов" },
}
local NOUN_BY_FORM = {}
for _, forms in ipairs(Sense.NOUNS) do
    for _, form in ipairs(forms) do
        NOUN_BY_FORM[form] = NOUN_BY_FORM[form] or forms
    end
end

-- Предлоги, после которых число с существительным стоит в родительном падеже:
-- «из 9 советов», «для 3 советов», «по 44 предметам» сюда не входит.
local GENITIVE = {}
for _, w in ipairs({ "из", "для", "без", "до", "от", "у", "около", "более", "менее",
                     "больше", "меньше", "после", "кроме", "среди", "против", "ради",
                     "нет", "не" }) do GENITIVE[w] = true end
-- После этих слов форма зависит от управления, которое правило не разбирает.
local SKIP_AFTER = { ["по"] = true, ["к"] = true, ["о"] = true, ["об"] = true,
                     ["при"] = true, ["с"] = true, ["со"] = true, ["над"] = true,
                     ["между"] = true, ["перед"] = true }

function Sense.agreement(text)
    local out = {}
    local toks = tokens(text)
    for i, t in ipairs(toks) do
        if t.kind == "num" then
            -- существительное сразу за числом (через один пробел)
            local sp, noun = toks[i + 1], toks[i + 2]
            if sp and sp.kind == "other" and sp.text == " " and noun and noun.kind == "word" then
                local word = lowerCyr(noun.text)
                local forms = NOUN_BY_FORM[word]
                -- слово перед числом
                local before
                local j = i - 1
                while toks[j] and toks[j].kind == "other" and toks[j].text == " " do j = j - 1 end
                if toks[j] and toks[j].kind == "word" then before = lowerCyr(toks[j].text) end
                if forms and not (before and SKIP_AFTER[before]) then
                    local fractional = t.text:find("[%.,]") ~= nil
                    local n = tonumber((t.text:gsub(",", "."))) or 0
                    local whole = math.floor(n)
                    local m10, m100 = whole % 10, whole % 100
                    local expect = {}
                    if fractional then
                        expect[forms[2]] = true                 -- «в 2,5 раза»
                    elseif before and GENITIVE[before] then
                        if m10 == 1 and m100 ~= 11 then expect[forms[2]] = true
                        else expect[forms[3]] = true end
                    else
                        if m10 == 1 and m100 ~= 11 then
                            expect[forms[1]] = true
                            if forms[4] then expect[forms[4]] = true end
                        elseif m10 >= 2 and m10 <= 4 and not (m100 >= 12 and m100 <= 14) then
                            expect[forms[2]] = true
                        else
                            expect[forms[3]] = true
                        end
                    end
                    if not expect[word] then
                        out[#out + 1] = finding("число и слово не согласованы", text,
                            (before and (before .. " ") or "") .. t.text .. " " .. noun.text)
                    end
                end
            end
        end
    end
    return out
end

-- 5. ЧИСЛА БЕЗ СМЫСЛА ------------------------------------------------------------------

Sense.PERCENT_LIMIT = 1000   -- больше - только рядом со словами сомнения
Sense.DOUBT_WORDS = { "сомнительно", "не сходятся", "ошибка в", "не верю", "проверьте" }

function Sense.numbers(text)
    local out = {}
    for _, bad in ipairs({
        { "%f[%d]0м за ", "ноль вместо «бесплатно» или «неизвестно»" },
        { "Материалы: 0м", "ноль вместо «бесплатно» или «неизвестно»" },
        { "%(0м%)", "сравнение с нулём" },
        { "%f[%d]0 из 0%f[%D]", "«0 из 0» — считать было нечего" },
        { "среди 0%f[%D]", "«среди 0» — выбирать было не из чего" },
        { "%f[%w]x0%f[%D]", "количество ноль" },
        { "%f[%d]0 уровень", "нулевой уровень" }, { "уровень 0%f[%D]", "нулевой уровень" },
        { "%f[%d]0 ур%.", "нулевой уровень" }, { "уровня 0%f[%D]", "нулевой уровень" },
        -- «142.0 балла» - не ноль: перед нулём стоит точка, и граница числа
        -- считается вместе с ней. Слово «балл» - это ns.UNIT_BENEFIT; до него
        -- на этом месте стояло «ед. пользы», и образцы были написаны под него.
        { "%+0 балл", "нулевой прирост" }, { "%f[%d%.,]0 балл", "нулевая польза" },
        { "в 0 раз", "«в 0 раз»" }, { "в 1 раз%f[^а]", "«в 1 раз»" },
        { "%f[%d%.,]0%%", "ноль процентов" },
        { "%d%.0 балл", "дробная часть «.0»" },
        { "%d%.0 ед%.", "дробная часть «.0»" },
        { "%d[%.,]?%d*x%f[%s%p%z]", "множитель «x» вместо «в N раз»" },
        { "%-%-%d", "двойной минус" }, { "%+%-%d", "плюс-минус" },
        -- ЭКОНОМИЯ, КОТОРОЙ НЕТ. Разница между ценой на полке и ценой на
        -- аукционе бывает нулевой, и тогда «дешевле у торговца» - неправда, а
        -- «экономия 0м» - неправда с числом. Фразы про потолок собираются из
        -- кусков (Logic/PriceProvider.lua), и равенство цен там - отдельная
        -- ветка именно поэтому; правило держит её на месте.
        { "экономия 0м", "экономия, которой нет" },
        { "дешевле на 0м", "«дешевле» при равных ценах" },
        { "против 0м", "сравнение с нулём" },
        { "экономия %-", "отрицательная экономия" },
    }) do
        local s, e = text:find(bad[1])
        if s then out[#out + 1] = finding("число без смысла: " .. bad[2], text, around(text, s, e)) end
    end

    -- Проценты, которых не бывает, - только вместе с прямым словом сомнения.
    for num in text:gmatch("(%d+)%%") do
        if (tonumber(num) or 0) >= Sense.PERCENT_LIMIT then
            local doubted = false
            local low = lowerCyr(text)
            for _, w in ipairs(Sense.DOUBT_WORDS) do
                if low:find(w, 1, true) then doubted = true end
            end
            if not doubted then
                out[#out + 1] = finding("число без смысла: " .. num .. "% без единого слова сомнения",
                    text, num .. "%")
            end
        end
    end
    return out
end

-- 5a. ВОДА: ВВОДНЫЕ СЛОВА И ВЕЖЛИВЫЕ ОБОРОТЫ ---------------------------------------
--
-- Игрок попросил пройтись по всему, что показывается «просто так». Вводный
-- оборот - самый дешёвый способ занять строку, ничего не ответив: «стоит
-- отметить», «как вы могли заметить», «обратите внимание» перед фразой не
-- добавляют к ней ничего, а на карточке в три строки съедают полстроки.
--
-- Правило закрытое и лексическое: список оборотов известен, и он здесь. Сейчас
-- в аддоне ни одного такого оборота нет - это не значит, что правило лишнее:
-- оно держит их отсутствие, а не чинит их наличие.
--
-- ЧЕГО ЗДЕСЬ НЕТ И ПОЧЕМУ: «возможно», «скорее всего», «вероятно» - это НЕ
-- вода, а честная оговорка про то, чего аддон не знает («возможно, покупать не
-- нужно» у совета про невидимый банк). Разница ровно одна: оговорка меняет
-- смысл утверждения, вводный оборот - нет.
Sense.FILLER = {
    "стоит отметить", "следует отметить", "надо отметить", "хочется отметить",
    "как вы могли заметить", "как вы заметили", "обратите внимание",
    "как известно", "не секрет", "разумеется", "как видите", "как видно",
    "между прочим", "так или иначе", "вообще говоря", "надо сказать",
    "честно говоря", "в общем-то", "как уже было сказано", "как уже говорилось",
    "хочу заметить", "заметим", "имейте в виду", "к вашему сведению",
    "к сведению", "вот такие дела", "как ни странно", "само собой",
    "нельзя не отметить", "хотелось бы отметить",
}

-- ДВАЖДЫ «НЕТ» В ОДНОЙ СТРОКЕ - ЭТО ОДНО «НЕТ» И ОДНА ЛИШНЯЯ ФРАЗА.
--
-- Живая находка: «Наблюдений ещё нет. Суточных слепков цен ещё нет — первый
-- появится после входа в игру.» Первую фразу даёт графа свежести, вторую -
-- пояснение, и вторая не добавляет ничего. Такие пары появляются сами, когда
-- строка собирается из кусков, у каждого из которых свой автор.
--
-- Правило считает ФРАЗЫ, в которых утверждается отсутствие, и ругается на
-- вторую. Разбор по лексемам, а не по образцу: классы символов Lua 5.1
-- побайтовые, и `%f[%a]нет%f[%A]` на русском слове не срабатывает вовсе - первая
-- версия этого правила была зелёной и не ловила ничего.
local function sentencesOf(text)
    local out = {}
    for piece in (tostring(text) .. " "):gmatch("([^%.!%?\n]+)") do
        piece = piece:gsub("^%s+", ""):gsub("%s+$", "")
        if piece ~= "" then out[#out + 1] = piece end
    end
    return out
end
Sense.sentences = sentencesOf

-- ПО СТРОКАМ, А НЕ ПО ВСЕМУ ТЕКСТУ СРАЗУ.
--
-- Правило про ОДНУ строку, собранную из кусков. Перечень причин по веткам -
-- это много сообщений в одном поле, по строке на ветку («• Надеть своё — в
-- сумках нет вещи лучше», «• Перепродажа — ни одного товара дешевле»), и две
-- разные ветки, у каждой из которых своя причина, повтором не являются.
function Sense.deniesTwice(text)
    local out = {}
    for line in (tostring(text) .. "\n"):gmatch("([^\n]*)\n") do
        local hits = {}
        for _, s in ipairs(sentencesOf(line)) do
            local low = lowerCyr(s)
            local denies = low:find("ни одн", 1, true) ~= nil
            if not denies then
                for _, t in ipairs(tokens(low)) do
                    if t.kind == "word" and (t.text == "нет" or t.text == "нету") then
                        denies = true
                    end
                end
            end
            if denies then hits[#hits + 1] = s end
        end
        if #hits >= 2 then
            out[#out + 1] = finding("в одной строке дважды сказано, что данных нет",
                text, hits[1] .. " / " .. hits[2])
        end
    end
    return out
end

function Sense.filler(text)
    local out = {}
    local low = lowerCyr(text)
    for _, phrase in ipairs(Sense.FILLER) do
        local s, e = low:find(phrase, 1, true)
        if s then
            out[#out + 1] = finding("вводный оборот, который ничего не отвечает",
                text, around(text, s, e))
        end
    end
    return out
end

-- 5b. СОВЕТ, КОТОРЫЙ САМ ГОВОРИТ, ЧТО ОН НЕ НУЖЕН --------------------------------
--
-- Живая находка, десятая строка списка игрока:
--
--   «Купить: Небесно-голубая краска x6»
--   «Ни одному совету это сейчас не нужно. Цена: ~1з 31с … В вашем списке
--    покупок это уже закреплено (6 шт.).»
--
-- Карточка предлагает купить и первой же фразой сообщает, что покупать незачем.
-- Место в списке она занимала только потому, что игрок когда-то закрепил
-- предмет руками, - и при этом выглядела как совет аддона.
--
-- КЛАСС, А НЕ СЛУЧАЙ: любая карточка собирается из куска «зачем» и куска «что
-- это стоит», и кусок «зачем» бывает пустым. Поэтому правило смотрит ПЕРВУЮ
-- фразу - ту, которую игрок на экране и читает (строка «почему» одна и
-- обрезается шириной окна), - и ищет в ней прямое отрицание смысла самой
-- карточки. Перечень отрицаний закрытый и лежит здесь; «возможно, покупать не
-- нужно» у совета про невидимый банк сюда не попадает и попасть не должно - это
-- оговорка про незнание, а не отрицание себя.
Sense.SELF_DENIAL = {
    "ни одному совету это сейчас не нужно",
    "ни одному совету это не нужно",
    "ни одному совету этого не нужно",
    "никому это сейчас не нужно",
    "никому это не нужно",
    "это сейчас никому не нужно",
    "делать это сейчас незачем",
    "смысла в этом сейчас нет",
    "пользы от этого никакой",
}

-- Отрицает ли ПЕРВАЯ фраза текста смысл самого совета. Возвращает находку или
-- nil: в Sense.RULES правило не входит, потому что относится к карточке целиком
-- (у информационного совета отрицать себя нечем - он ничего и не предлагает),
-- и применяется по собранию карточек в Tests/test_sense.lua.
function Sense.selfRefuting(text)
    local first = sentencesOf(text or "")[1]
    if not first then return nil end
    local low = lowerCyr(first)
    for _, phrase in ipairs(Sense.SELF_DENIAL) do
        if low:find(phrase, 1, true) then
            return finding("первая фраза отрицает сам совет", tostring(text), first)
        end
    end
    return nil
end

-- 5c. ОДНО И ТО ЖЕ ИМЯ ДВАЖДЫ ПОДРЯД В ПЕРЕЧИСЛЕНИИ ------------------------------
--
-- Живая находка со скриншота: «Серый хлам в сумках: Длинный волос из хвоста,
-- Отрубленный коготь, Отрубленный коготь и ещё 8. Цены торговца —…». Один и тот
-- же предмет назван дважды подряд - он лежал в двух ячейках сумки. Для игрока
-- это один предмет и одно количество, а два одинаковых имени рядом читаются как
-- ошибка аддона - и правильно читаются.
--
-- Правило разбирает перечисления через запятую и точку с запятой: два соседних
-- РАВНЫХ элемента - находка. Разные элементы с общим началом («Отрубленный
-- коготь» и «Отрубленный клык») находкой не считаются: сравнение точное.
function Sense.listRepeat(text)
    local out = {}
    -- Элемент перечисления - в границах ОДНОЙ фразы и без того, что к
    -- перечислению не относится:
    --   * зачин «Серый хлам в сумках: » у первого элемента;
    --   * хвост « и ещё 8» и точка у последнего.
    -- Без этого «Серый хлам в сумках: Рваная шкура» и «Рваная шкура» - разные
    -- строки, и тот самый повтор со скриншота правило не находило вовсе.
    --
    -- Зачин снимается ТОЛЬКО с первого элемента и ТОЛЬКО по первому двоеточию:
    -- в «Нужно для 2 советов: На навык: Новый капюшон; Скрафтить: Новый
    -- капюшон» элементы перечисления - это «На навык: …» и «Скрафтить: …», то
    -- есть разные советы, и снятие по последнему двоеточию превращало их в один
    -- и то же имя.
    local function itemOf(piece, first)
        local item = piece:gsub("^%s+", ""):gsub("%s+$", "")
        if first then item = item:gsub("^[^:]*:%s+", "") end
        item = item:gsub("%s+и ещё%s+%d+.*$", ""):gsub("[%.;:,]+$", "")
        return (item:gsub("%s+$", ""))
    end
    for _, sentence in ipairs(sentencesOf(text)) do
        local norm = sentence:gsub(", ", "\1"):gsub("; ", "\1")
        local prev, index = nil, 0
        for piece in (norm .. "\1"):gmatch("([^\1]*)\1") do
            index = index + 1
            local item = itemOf(piece, index == 1)
            if item ~= "" then
                if prev and item == prev then
                    out[#out + 1] = finding("одно и то же названо дважды подряд", text,
                        item .. ", " .. item)
                end
                prev = item
            end
        end
    end
    return out
end

-- 5d. «ГДЕ ЭТО НАСТРАИВАЕТСЯ» - НЕ В ТЕКСТЕ СОВЕТА --------------------------------
--
-- Дорога в настройки в строке совета стоит НА МЕСТЕ САМОГО СОВЕТА: строка одна,
-- она не переносится, и лишние слова выдавливают за край окна ровно то, ради
-- чего её читают. Живая находка: «Торговец: Mister Graphed, Лесоречье, 78.2 5…»
-- - за координатами стояло «(навигация выключена в настройках)», и за край ушли
-- координаты, а не приписка.
--
-- Это ответ на вопрос, который игрок ещё не задал. Его место - под курсором, в
-- самих настройках и в подробностях над списком; в подсказке, в пустом
-- состоянии и в сводке диагностики такая строка уместна. Поэтому правило не
-- входит в Sense.RULES: его применяет Tests/test_sense.lua к тексту САМИХ
-- карточек (заголовок, выгода, почему, нужно).
Sense.SETTINGS_HINTS = {
    "в настройках", "в настройки", "в настройке", "/fp config",
    "в разделе настроек", "раздел настроек",
}

function Sense.settingsHint(text)
    local plain = tostring(text or "")
    local low = lowerCyr(plain)
    for _, phrase in ipairs(Sense.SETTINGS_HINTS) do
        local s, e = low:find(phrase, 1, true)
        if s then
            return finding("дорога в настройки в тексте совета", plain, around(plain, s, e))
        end
    end
    return nil
end

-- 5e. АДДОН ПРЕДУПРЕЖДАЕТ, А НЕ ЗАПРЕЩАЕТ ----------------------------------------
--
-- Главное правило аддона - он ничего не делает за игрока. Запрет - это то же
-- самое, только словами: решение всё равно принимается не игроком.
--
-- Соблазн появился ровно с проверкой облика. Потеря облика необратима, и «не
-- продавайте эту вещь» выглядит заботой - но продать зелёнку ради денег
-- нормальное решение, особенно на двадцать восьмом уровне, и принимает его
-- игрок. Дело аддона - чтобы он принимал его ЗНАЯ, а не чтобы за него решили.
--
-- Перечень закрытый и лексический: прямое запрещение в повелительном
-- наклонении и обороты вида «вам нельзя». Сюда НЕ входит «дешевле 1з за штуку
-- выставлять нельзя: это продажа в минус» - это не запрет игроку, а
-- утверждение про числа, и оно обязано проходить.
Sense.PROHIBITIONS = {
    "не продавайте", "не продавай ", "не распыляйте", "не распыляй ",
    "не отправляйте", "не пересылайте", "не выставляйте", "не покупайте",
    "ни в коем случае", "вам запрещено", "вам нельзя", "не смейте",
    "оставьте эту вещь", "обязаны оставить",
}

function Sense.prohibits(text)
    local out = {}
    local low = lowerCyr(text)
    for _, phrase in ipairs(Sense.PROHIBITIONS) do
        local s, e = low:find(phrase, 1, true)
        if s then
            out[#out + 1] = finding("аддон запрещает игроку вместо того, чтобы"
                .. " предупредить", text, around(text, s, e))
        end
    end
    return out
end

-- 6. РОД: аддон говорит о себе в мужском роде («прочитал», «записал») ---------------

function Sense.gender(text)
    local out = {}
    local toks = tokens(text)
    for i, t in ipairs(toks) do
        if t.kind == "word" then
            local w = lowerCyr(t.text)
            -- «сама» - всегда о себе; глагол на «-ла» - только сразу после «я»
            -- («самопроверка нашла» - это про самопроверку, и это верно).
            local afterI = toks[i - 2] and toks[i - 2].kind == "word"
                and lowerCyr(toks[i - 2].text) == "я"
            if w == "сама" or (afterI and w:sub(-4) == "ла") then
                out[#out + 1] = finding("аддон говорит о себе в женском роде", text, t.text)
            end
        end
    end
    return out
end

-- Все правила разом ---------------------------------------------------------------

Sense.RULES = {
    { name = "пунктуация", fn = Sense.punctuation },
    { name = "крик", fn = Sense.shouting },
    { name = "два алфавита", fn = Sense.mixedScript },
    { name = "мусор", fn = Sense.garbage },
    { name = "жаргон", fn = Sense.jargon },
    { name = "профессии", fn = Sense.professionNames },
    { name = "согласование", fn = Sense.agreement },
    { name = "числа", fn = Sense.numbers },
    { name = "вода", fn = Sense.filler },
    { name = "повтор", fn = Sense.deniesTwice },
    { name = "перечисление", fn = Sense.listRepeat },
    { name = "запрет", fn = Sense.prohibits },
    { name = "род", fn = Sense.gender },
}

-- Что в тексте - данные, а не слова аддона: ссылки, цветовые коды, имена
-- предметов из игры (в кавычках-ёлочках и в квадратных скобках). Данные
-- проверке не подлежат: «Mister Graphed» написал не аддон.
function Sense.strip(S, text)
    local plain = S.plain(text)
    plain = plain:gsub("%[[^%]]*%]", "[…]")
    return plain
end

function Sense.check(S, text)
    local plain = Sense.strip(S, text)
    local all = {}
    for _, rule in ipairs(Sense.RULES) do
        for _, f in ipairs(rule.fn(plain)) do
            f.group = rule.name
            all[#all + 1] = f
        end
    end
    return all
end

-- СТРОКИ ПРЯМО ИЗ КОДА ------------------------------------------------------------
--
-- Собрание текстов видит только то, что аддон сказал в шестнадцати состояниях
-- мира. Сообщение об ошибке, которая в них не случилась, туда не попадает - и
-- крик в нём доживёт до игрока. Поэтому три правила, которым не нужен целый
-- текст (крик, два алфавита, род), идут ещё и по всем строковым литералам кода:
-- по каждой русской строке каждого файла, сказана она в тестовом мире или нет.

-- Строковые литералы файла: { line = номер строки, text = содержимое }.
-- Разбор посимвольный: комментарии, длинные скобки и экранированные кавычки
-- паттернами не разбираются.
function Sense.literals(src)
    local out, i, n, line = {}, 1, #src, 1
    local function countLines(chunk)
        for _ in chunk:gmatch("\n") do line = line + 1 end
    end
    while i <= n do
        local c = src:sub(i, i)
        local two = src:sub(i, i + 1)
        local commentEq = (two == "--") and src:match("^%-%-%[(=*)%[", i) or nil
        local eq = src:match("^%[(=*)%[", i)
        if two == "--" and commentEq then
            local close = "]" .. commentEq .. "]"
            local stop = src:find(close, i + 4 + #commentEq, true)
            local last = stop and (stop + #close - 1) or n
            countLines(src:sub(i, last))
            i = last + 1
        elseif two == "--" then
            local stop = src:find("\n", i, true) or (n + 1)
            i = stop
        elseif eq then
            local close = "]" .. eq .. "]"
            local stop = src:find(close, i + 2 + #eq, true)
            local last = stop and (stop + #close - 1) or n
            out[#out + 1] = { line = line, text = src:sub(i + 2 + #eq, (stop or (n + 1)) - 1) }
            countLines(src:sub(i, last))
            i = last + 1
        elseif c == '"' or c == "'" then
            local j, buf = i + 1, {}
            while j <= n do
                local ch = src:sub(j, j)
                if ch == "\\" then
                    buf[#buf + 1] = src:sub(j + 1, j + 1)
                    j = j + 2
                elseif ch == c or ch == "\n" then
                    break
                else
                    buf[#buf + 1] = ch
                    j = j + 1
                end
            end
            out[#out + 1] = { line = line, text = table.concat(buf) }
            i = j + 1
        else
            if c == "\n" then line = line + 1 end
            i = i + 1
        end
    end
    return out
end

Sense.STATIC_RULES = {
    { name = "крик", fn = Sense.shouting },
    { name = "два алфавита", fn = Sense.mixedScript },
    { name = "род", fn = Sense.gender },
}

-- Есть ли в строке русские буквы: строки без них - ключи и имена, а не речь.
function Sense.hasCyrillic(text)
    return tostring(text):find("[\208\209][\128-\191]") ~= nil
end

return Sense
