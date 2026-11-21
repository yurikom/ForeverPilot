-- ForeverPilot / Tests/test_text.lua
--
-- Two things live here, and they are the same thing seen from two sides.
--
-- 1. CLOSING AND OPENING. Every surface the addon puts on screen must be
--    closable, must remember that it was closed, and must be reachable again by
--    more than one route - with the routes named in chat at the moment of
--    closing, because that is the moment the player needs them.
--
-- 2. THE TEXTS INVARIANT. No text in the interface may name a control that is
--    not on the same screen. This is not a style rule. The player hit exactly
--    this: the step panel said «Нажмите "Вернуть все"» and the panel had one
--    button, called «Открыть». The text sent them to press something that did
--    not exist, which from the outside looks like the addon talking nonsense.
--
-- The invariant is checked against the frames the addon ACTUALLY BUILT, not
-- against the source. Grepping the source would prove nothing: the question is
-- whether the button is on screen at the moment the sentence is on screen.
--
-- Patterns behind the behaviour under test were taken from Polestar (studied,
-- not copied - it is GPL-3.0 and none of its code is here):
--   * rules-based hiding never writes the player's own on/off setting
--   * "how to get it back" is assembled from the routes that actually exist
--   * the ways back are deliberately redundant, and one of them is a visible
--     button rather than a command to remember
local H = ...
local S = assert(loadfile((H.ROOT or ".") .. "/Tests/uistub.lua"))()

-- Значки берём из того же файла, что и аддон, а не переписываем сюда: иначе
-- проверка начнёт искать на экране символы, которых аддон больше не рисует.
-- Core/Const.lua - чистые данные, ему не нужен ни клиент, ни песочница.
local ns = {}
assert(loadfile((H.ROOT or ".") .. "/Core/Const.lua"))("ForeverPilot", ns)
assert(type(ns.GLYPH) == "table", "ns.GLYPH не найден в Core/Const.lua")

return function()

-- Scaffolding -----------------------------------------------------------

-- Load the addon with the UI, and record everything it says in chat.
local function fresh()
    local env = S.load(H)
    env.said = {}
    local Api = env.ns.Api
    function Api:Print(msg)
        env.said[#env.said + 1] = tostring(msg)
        if H.verbose then print("[fp]", msg) end
    end
    S.populate(env, H)
    return env
end

local function saidAny(env, needle)
    for _, line in ipairs(env.said or {}) do
        if S.plain(line):find(needle, 1, true) then return line end
    end
    return nil
end

-- Фразы, после которых названный в кавычках элемент ОБЯЗАН быть на экране.
-- Всё остальное в кавычках - это данные: названия профессий, предметов, зон,
-- наборов весов. Проверять их наличие среди кнопок бессмысленно, а вот
-- «нажмите X» - это обещание, и его можно сдержать или не сдержать.
--
-- СПИСОК ПРОПУСКАЛ НАСТОЯЩЕЕ НАРУШЕНИЕ, И УЖЕ ВО ВТОРОЙ РАЗ.
--
-- Первый раз в нём забыли регистр: «кнопк» было, «Кнопк» не было. Тогда оба
-- регистра стали выписывать руками - и во второй раз забыли уже не регистр, а
-- форму слова: «Нажмите» было, а «нажми» не было. Под списком покупок стояло
-- «Открой аукцион и нажми „Искать на аукционе“» - кнопки с таким названием нет
-- нигде, а проверка прошла мимо, потому что аддон там обратился на «ты».
--
-- Поэтому теперь здесь ОСНОВЫ, а не слова, и заглавный вариант строится сам:
--   * основа ловит все формы сразу - «нажми» находится и в «нажмите», и в
--     «нажми», «выбери» - и в «выберите»;
--   * регистр не выписывается руками, так что забыть его нельзя; что каждая
--     основа получила пару, проверяет самопроверка ниже.
-- В Lua 5.1 нет регистра для кириллицы, поэтому таблица заглавных своя.
local CAPITAL = {
    ["а"] = "А", ["б"] = "Б", ["в"] = "В", ["г"] = "Г", ["д"] = "Д", ["е"] = "Е",
    ["ё"] = "Ё", ["ж"] = "Ж", ["з"] = "З", ["и"] = "И", ["й"] = "Й", ["к"] = "К",
    ["л"] = "Л", ["м"] = "М", ["н"] = "Н", ["о"] = "О", ["п"] = "П", ["р"] = "Р",
    ["с"] = "С", ["т"] = "Т", ["у"] = "У", ["ф"] = "Ф", ["х"] = "Х", ["ц"] = "Ц",
    ["ч"] = "Ч", ["ш"] = "Ш", ["щ"] = "Щ", ["ъ"] = "Ъ", ["ы"] = "Ы", ["ь"] = "Ь",
    ["э"] = "Э", ["ю"] = "Ю", ["я"] = "Я",
}

-- Основа с заглавной буквы. Кириллическая буква в UTF-8 занимает два байта.
local function capitalized(stem)
    local first = stem:sub(1, 2)
    local upper = CAPITAL[first]
    if not upper then return nil end
    return upper .. stem:sub(3)
end

-- Основы слов, которыми автор текста велит что-то нажать или называет элемент
-- управления. Пишутся со строчной; «ё» и «е» - это разные основы.
--
-- «откройте» сюда не входит НАМЕРЕННО: «Откройте „Портняжное дело“ в книге
-- профессий» называет окно игры, а не наш элемент, и названия профессий -
-- данные. Зато всё, что названо в кавычках и не является ни элементом, ни
-- данными, ловит вторая проверка - unaccounted() ниже, - какими бы словами это
-- ни было сказано.
local PRESS_STEMS = {
    -- нажать: нажми, нажмите, нажать, нажатие, нажав, нажимай(те)
    "нажми", "нажать", "нажати", "нажав", "нажима",
    -- жми, жмите (заодно внутри «нажми» - не мешает)
    "жми",
    -- щёлкнуть, с «ё» и без: щелкни(те), щелчок, щелчка/щелчком/щелчке
    "щелкни", "щёлкни", "щелчок", "щёлчок", "щелчк", "щёлчк", "щелка", "щёлка",
    -- кликнуть
    "клик",
    -- выбрать, поставить, отметить, снять - то, что делают с галочкой и списком
    "выбери", "поставь", "отметь", "сними",
    -- включить и выключить, переключить
    "включи", "выключи", "переключ",
    -- сами элементы управления
    "кнопк", "галочк", "вкладк", "фильтр", "ползун",
}

local PRESS_HINTS = {}
for _, stem in ipairs(PRESS_STEMS) do
    PRESS_HINTS[#PRESS_HINTS + 1] = stem
    PRESS_HINTS[#PRESS_HINTS + 1] = assert(capitalized(stem),
        "у основы «" .. stem .. "» не нашлось заглавной буквы")
end

-- Признак обещания ищется в предложении БЕЗ самих кавычек.
--
-- Иначе название элемента запускает проверку само: «Волшебная кнопка» содержит
-- «кнопк», и фраза «Это "Волшебная кнопка"» объявлялась обещанием, хотя ничего
-- не обещает. Обещание — это слова АВТОРА, а не имя того, о чём он говорит.
local function isInstruction(sentence)
    local outsideQuotes = sentence:gsub("«.-»", " ")
    for _, hint in ipairs(PRESS_HINTS) do
        if outsideQuotes:find(hint, 1, true) then return true end
    end
    return false
end

-- Разбиваем на предложения: обещание действует в пределах одной фразы.
local function sentences(text)
    local out = {}
    for piece in (S.plain(text) .. " "):gmatch("([^%.!%?\n]+)") do
        out[#out + 1] = piece
    end
    return out
end

-- Подписи как множество, в двух видах: как написано и без маркера выбора.
local function labelSet(labels, into)
    local have = into or {}
    for _, label in ipairs(labels) do
        local plain = S.plain(label)
        have[plain] = true
        -- Кнопка может быть подписана с маркером выбора: «(•) В бою: скрыть».
        --
        -- Маркеры берутся из ns.GLYPH, а не переписываются здесь: раньше это
        -- были ● и ○, и клиент рисовал их пустыми квадратами. Снимаются
        -- сравнением начала строки, а не паттерном: «(» и «)» в паттерне Lua
        -- это захват.
        local bare = plain
        for _, marker in ipairs({ ns.GLYPH.RADIO_ON, ns.GLYPH.RADIO_OFF }) do
            if bare:sub(1, #marker) == marker then bare = bare:sub(#marker + 1) end
        end
        bare = bare:gsub("^%s+", "")
        have[bare] = true
    end
    return have
end

-- ПЕРВАЯ ПРОВЕРКА: обещание. В предложении, где автор велит что-то нажать,
-- каждое имя в кавычках обязано быть подписью на том же экране. Возвращает
-- список нарушений.
local function violations(labels, texts)
    local have = labelSet(labels)
    local bad = {}
    for _, text in ipairs(texts) do
        for _, sentence in ipairs(sentences(text)) do
            if isInstruction(sentence) then
                for _, name in ipairs(S.quotedNames(sentence)) do
                    if not have[name] then
                        bad[#bad + 1] = "«" .. name .. "» — нет на экране; сказано: "
                            .. S.plain(sentence)
                    end
                end
            end
        end
    end
    return bad
end

-- ВТОРАЯ ПРОВЕРКА: ВСЁ, ЧТО НАЗВАНО В КАВЫЧКАХ, СУЩЕСТВУЕТ.
--
-- Первая проверка держится на списке слов, а список слов всегда короче языка:
-- «„Волшебная кнопка“ вернёт все советы» не содержит ни одного слова-обещания
-- и проходит насквозь. Латать её третьим списком глаголов - значит ждать
-- четвёртого пропуска.
--
-- Вторая проверка от формулировки не зависит вовсе. В этом аддоне кавычками «»
-- называется что-то существующее: элемент интерфейса, или данные мира
-- (профессия, слот, предмет, заголовок совета), или слово-термин, которое
-- объясняют. Значит, каждое имя в кавычках обязано найтись в одном из трёх
-- множеств. Не нашлось - это либо выдуманный элемент, либо новый термин, про
-- который надо решить сознательно и вписать его в QUOTED_TERMS с объяснением.
--
--   known - множество известных имён (подписи всего интерфейса + данные мира)
-- Возвращает список { name, text } для имён, которых нет нигде.
local function unaccounted(texts, known)
    local out, seen = {}, {}
    for _, text in ipairs(texts) do
        for _, name in ipairs(S.quotedNames(text)) do
            local ok = known[name]
            -- Длинные заголовки аддон обрезает многоточием («скрыть „Благо…“»):
            -- обрезанное имя сверяется по началу.
            if not ok and name:sub(-3) == "…" then
                local head = name:sub(1, -4)
                for full in pairs(known) do
                    if #head > 0 and full:sub(1, #head) == head then ok = true; break end
                end
            end
            if not ok and not seen[name] then
                seen[name] = true
                out[#out + 1] = { name = name, text = S.plain(text) }
            end
        end
    end
    return out
end

-- Слова в кавычках, которые не элементы и не данные, а ТЕРМИНЫ: текст их
-- объясняет, а не просит нажать. Каждому - причина, почему он здесь.
local QUOTED_TERMS = {
    ["купить готовый"] = "вкладка «Крафт» объясняет, как принимается решение по"
        .. " промежуточному материалу",
    ["скрафтить промежуточный материал"] = "то же объяснение, второй вариант решения",
    ["сила"] = "настройки: «это НЕ характеристика „сила“» - слово, с которым не"
        .. " надо путать балл пользы",
    -- Строка «порог убрал N денежных советов» называет раздел настроек, где
    -- порог снимается. Раздел существует (UI/TabSettings.lua, заголовок
    -- ns.ActionEngine.MONEY_FLOOR_SECTION), но заголовок раздела - не кнопка, а
    -- в подписи интерфейса здесь попадают только кнопки; поэтому он здесь.
    ["Мелкая денежная выгода"] = "заголовок раздела настроек, где снимается"
        .. " порог мелкой денежной выгоды; строка над списком отправляет туда",
}

-- САМОПРОВЕРКА ДЕТЕКТОРА.
--
-- Сначала инвариант был зелёным и не проверял ничего: разбор кавычек молча
-- возвращал пустой список на русском тексте (побайтовые классы Lua 5.1 - см.
-- комментарий у S.quotedNames). Зелёный тест, который ничего не умеет
-- провалить, хуже отсутствующего. Поэтому детектор проверяется сам.
H.suite("Инвариант: сам детектор умеет ловить и не придираться")
do
    H.eq(#S.quotedNames("Нажмите «Вернуть все» — или наберите /fp show"), 1,
        "имя в кавычках находится в русском тексте")
    H.eq(S.quotedNames("кнопкой «Волшебная кнопка»")[1], "Волшебная кнопка",
        "и читается целиком")
    H.eq(#S.quotedNames("Скрыто: «Портняжное дело», «Чары»"), 2,
        "два имени — два элемента списка")

    local labels = { "Вернуть все", "Обновить", ns.GLYPH.RADIO_ON .. "В бою: скрыть" }
    H.eq(#violations(labels, { "Нажмите «Вернуть все»." }), 0,
        "кнопка есть — претензий нет")
    H.eq(#violations(labels, { "Нажмите «Волшебная кнопка»." }), 1,
        "кнопки нет — нарушение найдено")
    H.eq(#violations(labels, { "Нажмите «В бою: скрыть»." }), 0,
        "маркер выбора «" .. ns.GLYPH.RADIO_ON .. "» в подписи не мешает узнать кнопку")
    H.eq(#violations(labels, { "Откройте окно профессии «Портняжное дело»." }), 0,
        "название профессии — это данные, а не кнопка: не придираемся")
    H.eq(#violations(labels, { "|cffff6060Нажмите «Обновить»|r." }), 0,
        "цветовые коды не мешают")
    H.eq(#violations(labels, { "Советов нет. Нажмите «Обновить»." }), 0,
        "обещание ищется в своём предложении")
    H.eq(#violations(labels, { "Это «Волшебная кнопка». Нажмите «Обновить»." }), 0,
        "кавычки в предложении без обещания не проверяются")

    -- Формулировки, которые первая версия детектора пропускала.
    H.eq(#violations(labels, { "Кнопку «Волшебная кнопка» ищите справа." }), 1,
        "«Кнопку X» с заглавной — тоже обещание")
    H.eq(#violations(labels, { "Щелчок по «Волшебная кнопка» вернёт панель." }), 1,
        "«Щелчок по X» — обещание")
    H.eq(#violations(labels, { "Жмите «Волшебная кнопка»." }), 1,
        "«Жмите X» — обещание")
    H.eq(#violations(labels, { "Поставьте галочку «Волшебная кнопка»." }), 1,
        "«Поставьте галочку X» — обещание")

    -- ФОРМУЛИРОВКИ, КОТОРЫЕ ПРОПУСКАЛА ВТОРАЯ ВЕРСИЯ. Первая строка - дословно
    -- тот текст, что стоял под списком покупок и обещал несуществующую кнопку.
    H.eq(#violations(labels, { "Открой аукцион и нажми «Искать на аукционе»" }), 1,
        "«нажми X» на «ты» — обещание (именно так и было пропущено)")
    for _, phrase in ipairs({
        "Нажми «Волшебная кнопка».",
        "жми «Волшебная кнопка», и всё вернётся.",
        "Щёлкни «Волшебная кнопка».",
        "Щелкни по «Волшебная кнопка».",
        "После щелчка по «Волшебная кнопка» список вернётся.",
        "Выбери «Волшебная кнопка» в списке.",
        "Поставь галочку «Волшебная кнопка».",
        "Сними галочку «Волшебная кнопка».",
        "Отметьте «Волшебная кнопка».",
        "Включите «Волшебная кнопка» в настройках.",
        "Переключите «Волшебная кнопка».",
        "Загляните на вкладку «Волшебная кнопка».",
        "Смотрите вкладку «Волшебная кнопка».",
        "Под фильтр «Волшебная кнопка» ничего не подходит.",
        "Нажав «Волшебная кнопка», вы вернёте панель.",
        "Потяните ползунок «Волшебная кнопка».",
    }) do
        H.eq(#violations(labels, { phrase }), 1, "обещание распознано: " .. phrase)
    end

    -- Каждая основа получила заглавную пару: забыть регистр больше нельзя.
    H.eq(#PRESS_HINTS, #PRESS_STEMS * 2, "у каждой основы есть заглавный вариант")
    for _, stem in ipairs(PRESS_STEMS) do
        local cap = capitalized(stem)
        H.ok(cap ~= nil and cap ~= stem,
            "основа «" .. stem .. "» -> «" .. tostring(cap) .. "»")
        H.eq(#violations(labels, { cap .. " «Волшебная кнопка»." }), 1,
            "и с заглавной буквы она ловится: " .. tostring(cap))
    end

    -- И не придирается к тому, что обещанием не является.
    H.eq(#violations(labels, { "Откройте «Портняжное дело» в книге профессий." }), 0,
        "«откройте окно игры» по-прежнему не обещание нашей кнопки")
    H.eq(#violations(labels, { "Слот «Голова»: лучше на 11 баллов." }), 0,
        "название слота — данные")

    -- ВТОРАЯ ПРОВЕРКА ловит то, что первой не поймать никаким списком слов:
    -- имя в кавычках без единого слова-обещания рядом.
    local known = labelSet(labels)
    known["Портняжное дело"] = true
    H.eq(#unaccounted({ "«Волшебная кнопка» вернёт все советы." }, known), 1,
        "выдуманное имя найдено и без слова-обещания")
    H.eq(unaccounted({ "«Волшебная кнопка» вернёт все советы." }, known)[1].name,
        "Волшебная кнопка", "и названо оно само")
    H.eq(#unaccounted({ "Откройте «Портняжное дело»." }, known), 0,
        "данные мира — не нарушение")
    H.eq(#unaccounted({ "Сначала «Вернуть все», потом «Обновить»." }, known), 0,
        "настоящие подписи — не нарушение")
    known["Благосклонность торговца: 8 покупок доступны"] = true
    H.eq(#unaccounted({ "скрыть «Благосклонность торговца: 8 покуп…»?" }, known), 0,
        "обрезанное многоточием имя узнаётся по началу")
    H.eq(#unaccounted({ "скрыть «Волшебная кноп…»?" }, known), 1,
        "а обрезанное выдуманное — нет")

    H.eq(#S.slashCommands("наберите /fp show — вернутся все"), 1,
        "команда в тексте находится")
    H.eq(S.slashCommands("вернуть всё: /fp show, или /fp panel.")[2], "panel",
        "и несколько подряд тоже")
end

-- ЗНАЧКИ, КОТОРЫХ КЛИЕНТ НЕ РИСУЕТ --------------------------------------
--
-- Игрок прислал скриншот с пустыми квадратиками вместо значков: в кнопке
-- закрытия окна, в трёх подписях «В бою: …» и в подсказке панели. Кнопка, на
-- которой нарисован один квадрат, - это кнопка без подписи; игрок спросил,
-- делает ли она вообще что-нибудь.
--
-- Шрифты ruRU-клиента покрывают то, что было в Windows-1251. Поэтому «» — – •
-- … № · на экране читаются, а ✕ (U+2715), ● (U+25CF), ○ (U+25CB), → (U+2192),
-- − (U+2212) и ≈ (U+2248) - нет. Проверяется и исходник (чтобы такой символ не
-- вернулся в код), и то, что реально построено на экране (чтобы он не приехал
-- из данных).

local FORBIDDEN = {
    { bytes = "\226\156\149", name = "✕ U+2715", use = "ns.GLYPH.CLOSE" },
    { bytes = "\226\151\143", name = "● U+25CF", use = "ns.GLYPH.RADIO_ON" },
    { bytes = "\226\151\139", name = "○ U+25CB", use = "ns.GLYPH.RADIO_OFF" },
    { bytes = "\226\134\146", name = "→ U+2192", use = "ns.GLYPH.ARROW" },
    { bytes = "\226\136\146", name = "− U+2212", use = "ns.GLYPH.MINUS" },
    { bytes = "\226\137\136", name = "≈ U+2248", use = "ns.GLYPH.APPROX" },
}

local function badGlyphs(text)
    local out = {}
    for _, g in ipairs(FORBIDDEN) do
        if tostring(text or ""):find(g.bytes, 1, true) then
            out[#out + 1] = g.name .. " (брать " .. g.use .. ")"
        end
    end
    return out
end

H.suite("Значки: проверка умеет отличать рисуемое от нерисуемого")
do
    -- Самопроверка: без неё «нарушений нет» не значит ничего.
    H.eq(#badGlyphs("обычный текст — с тире, «кавычками» и • точкой"), 0,
        "то, что клиент рисует, нарушением не считается")
    H.ok(#badGlyphs("\226\156\149") == 1, "а ✕ считается")
    H.ok(#badGlyphs("было \226\134\146 стало") == 1, "и стрелка тоже")
    -- И сами замены обязаны быть безопасными.
    for _, key in ipairs({ "CLOSE", "RADIO_ON", "RADIO_OFF", "ARROW", "MINUS", "APPROX" }) do
        H.eq(#badGlyphs(ns.GLYPH[key]), 0,
            "замена ns.GLYPH." .. key .. " («" .. tostring(ns.GLYPH[key])
            .. "») сама безопасна")
    end
end

H.suite("Значки: в исходниках аддона нерисуемых символов нет")
do
    local D = assert(loadfile((H.ROOT or ".") .. "/Tests/dialect.lua"))()
    local files = assert(D.tocFiles(H.ROOT or "."))
    for _, rel in ipairs(files) do
        local f = io.open((H.ROOT or ".") .. "/" .. rel, "rb")
        H.ok(f ~= nil, rel .. ": прочитан")
        if f then
            local src = f:read("*a")
            f:close()
            -- Комментарии вырезаются: в них эти символы названы по делу -
            -- объяснением, почему их нельзя. Строки остаются: именно они
            -- попадают на экран.
            local code = D.stripped(src)
            -- stripped() заменяет и строки тоже, поэтому строковые литералы
            -- проверяются отдельным проходом, по исходнику без комментариев.
            local noComments = src:gsub("%-%-%[(=*)%[.-%]%1%]", " "):gsub("%-%-[^\n]*", "")
            local bad = badGlyphs(noComments)
            H.eq(#bad, 0, rel .. ": нерисуемых символов нет"
                .. ((#bad > 0) and ("  <- " .. table.concat(bad, ", ")) or ""))
            H.ok(code ~= nil, rel .. ": разобран")
        end
    end
end

H.suite("Значки: на построенном экране нерисуемых символов нет")
do
    local env = fresh()
    local nsr = env.ns
    nsr.Config:Get().panel.enabled = true
    nsr.Config:Get().ui.minimapButton = true
    nsr.MainFrame:Build()
    nsr.MainFrame:ApplyMinimapButton()
    nsr.StepPanel:ApplyVisibility()

    local tips = {}
    env.G.GameTooltip.AddLine = function(_, text) tips[#tips + 1] = tostring(text) end

    local checked = 0
    local function sweep(where, labels, texts)
        for _, list in ipairs({ labels, texts }) do
            for _, text in ipairs(list) do
                checked = checked + 1
                local bad = badGlyphs(text)
                H.eq(#bad, 0, where .. ": «" .. S.plain(text):sub(1, 40)
                    .. "» рисуется целиком"
                    .. ((#bad > 0) and ("  <- " .. table.concat(bad, ", ")) or ""))
            end
        end
    end

    for _, def in ipairs(nsr.MainFrame.TABS) do
        nsr.MainFrame:Select(def.key)
        nsr.MainFrame:RenderActive()
        local labels, texts = S.harvest(env.world, nsr.MainFrame.frame)
        sweep("вкладка «" .. def.label .. "»", labels, texts)
    end
    nsr.StepPanel:Render()
    local pl, pt = S.harvest(env.world, nsr.StepPanel.frame)
    sweep("панель", pl, pt)

    -- И подсказки: там жило «✕ — убрать панель».
    for _, frame in ipairs(env.world.frames) do
        local enter = frame.__scripts and frame.__scripts.OnEnter
        if enter then pcall(enter, frame) end
    end
    sweep("подсказки", {}, tips)
    H.ok(checked > 60, "подписей и текстов проверено: " .. checked)
    H.ok(#tips > 0, "строк подсказок собрано: " .. #tips)
end

H.suite("Значки: кнопка закрытия окна подписана и объясняет себя")
do
    -- Игрок спросил, делает ли эта кнопка вообще что-нибудь: подписи не было
    -- (квадрат), подсказки тоже.
    local env = fresh()
    local nsr = env.ns
    nsr.MainFrame:Build()
    local close = nsr.MainFrame.closeButton
    H.ok(close ~= nil, "кнопка закрытия есть")
    if close then
        local label = close.text and close.text:GetText() or ""
        H.ok(label ~= "" , "у неё есть подпись: «" .. tostring(label) .. "»")
        H.eq(#badGlyphs(label), 0, "и подпись рисуется, а не квадратом")

        local tips = {}
        env.G.GameTooltip.AddLine = function(_, text) tips[#tips + 1] = tostring(text) end
        local enter = close.__scripts and close.__scripts.OnEnter
        H.ok(enter ~= nil, "и подсказка при наведении")
        if enter then
            pcall(enter, close)
            local joined = S.plain(table.concat(tips, " "))
            H.ok(joined:find("акрыть", 1, true) ~= nil,
                "в подсказке сказано, что она закрывает: " .. joined)
            H.eq(#badGlyphs(joined), 0, "и сама подсказка рисуется")
        end

        -- И она действительно закрывает окно, а не просто подписана.
        nsr.MainFrame:Show()
        H.eq(nsr.MainFrame:IsShown(), true, "окно открыто")
        local click = close.__scripts and close.__scripts.OnClick
        H.ok(click ~= nil, "у неё есть обработчик щелчка")
        if click then
            pcall(click, close)
            H.eq(nsr.MainFrame:IsShown(), false, "щелчок закрыл окно")
        end
    end
end

-- ВКЛАДКИ: НА ЭКРАНЕ РОВНО ОДНА ------------------------------------------
--
-- Игрок прислал два скриншота, на которых вкладки наложены друг на друга:
-- содержимое «Мой персонаж» поверх содержимого «Сейчас», текст на тексте, и
-- подсвечены сразу три элемента - две вкладки и фильтр внутри нижней. При
-- каждом следующем щелчке подсвеченных становилось больше.
--
-- Причин было две, и обе здесь проверяются.
--
-- 1. ПЕРВОПРИЧИНА: не загружался Logic\ActionEngine.lua (`goto` в Lua 5.1 - см.
--    Tests/test_load.lua), поэтому отрисовка вкладки падала.
-- 2. ПОЧЕМУ ЭТО ЛОМАЛО ИМЕННО ВКЛАДКИ: Main:Select одним проходом прятал
--    вкладки до выбранной, показывал выбранную и сразу звал её отрисовку
--    НЕЗАЩИЩЁННОЙ. Падение роняло проход на середине, и всё, до чего он не
--    дошёл, оставалось на экране и в подсветке.
--
-- Поэтому проверка сформулирована не про ошибку, а про состояние экрана:
-- показана ровно одна вкладка и подсвечена ровно одна - ЧЕМ БЫ НИ ЗАКОНЧИЛАСЬ
-- отрисовка. Второй сюит ниже ломает отрисовку намеренно.

local function tabState(ns)
    local shown, selected = {}, {}
    for _, def in ipairs(ns.MainFrame.TABS) do
        local mod = ns[def.module]
        local frame = mod and mod.frame
        if frame and frame:IsShown() then shown[#shown + 1] = def.key end
        local btn = ns.MainFrame.tabButtons[def.key]
        if btn and btn.selected then selected[#selected + 1] = def.key end
    end
    return shown, selected
end

H.suite("Вкладки: после переключения видна ровно одна и подсвечена ровно одна")
do
    local env = fresh()
    local ns = env.ns
    ns.MainFrame:Build()

    -- Все переходы, включая «налево» - именно на них старый проход оставлял
    -- текущую вкладку висеть, потому что до неё цикл уже не доходил.
    local order = { "NOW", "CHAR", "CRAFT", "CONFIG", "NOW", "CONFIG", "CHAR",
                    "NOW", "CRAFT", "CHAR", "CONFIG", "CRAFT" }
    for _, key in ipairs(order) do
        local ok, err = pcall(function() ns.MainFrame:Select(key) end)
        H.ok(ok, "переключение на «" .. key .. "» не падает", tostring(err))
        local shown, selected = tabState(ns)
        H.eq(#shown, 1, "на «" .. key .. "» показана ровно одна вкладка: ["
            .. table.concat(shown, ", ") .. "]")
        H.eq(#selected, 1, "и подсвечена ровно одна: ["
            .. table.concat(selected, ", ") .. "]")
        H.eq(shown[1], key, "показана именно выбранная")
        H.eq(selected[1], key, "и подсвечена именно она")
        H.eq(ns.MainFrame.activeTab, key, "и движок считает активной её же")
    end
end

H.suite("Вкладки: щелчок по самой кнопке вкладки даёт то же самое")
do
    local env = fresh()
    local ns = env.ns
    ns.MainFrame:Build()
    for _, key in ipairs({ "CONFIG", "NOW", "CHAR", "NOW", "CRAFT" }) do
        local btn = ns.MainFrame.tabButtons[key]
        local handler = btn and btn.__scripts and btn.__scripts.OnClick
        H.ok(handler ~= nil, "у вкладки «" .. key .. "» есть обработчик щелчка")
        if handler then
            local ok, err = pcall(handler, btn)
            H.ok(ok, "щелчок по «" .. key .. "» не падает", tostring(err))
            local shown, selected = tabState(ns)
            H.eq(#shown, 1, "после щелчка по «" .. key .. "» видна одна: ["
                .. table.concat(shown, ", ") .. "]")
            H.eq(#selected, 1, "и подсвечена одна: ["
                .. table.concat(selected, ", ") .. "]")
        end
    end
end

H.suite("Вкладки: упавшая отрисовка не оставляет две вкладки на экране")
do
    -- ВОСПРОИЗВЕДЕНИЕ ТОГО, ЧТО ВИДЕЛ ИГРОК, но без первопричины: движок на
    -- месте, а отрисовка одной вкладки сломана намеренно. Это и есть настоящий
    -- инвариант - переключение не имеет права зависеть от отрисовки.
    for _, broken in ipairs({ "NOW", "CHAR", "CRAFT", "CONFIG" }) do
        local env = fresh()
        local ns = env.ns
        ns.MainFrame:Build()

        local mod
        for _, def in ipairs(ns.MainFrame.TABS) do
            if def.key == broken then mod = ns[def.module] end
        end
        H.ok(mod ~= nil, "вкладка «" .. broken .. "» найдена")
        if mod then
            mod.Render = function() error("сломанная отрисовка «" .. broken .. "»") end
            if mod.OnShow then
                mod.OnShow = function(self) self:Render() end
            end

            -- Проходим по всем вкладкам: сломанная встречается и «справа», и
            -- «слева» от предыдущей.
            for _, key in ipairs({ "NOW", "CHAR", "CRAFT", "CONFIG", "NOW" }) do
                local ok = pcall(function() ns.MainFrame:Select(key) end)
                H.ok(ok, "Select(«" .. key .. "») не выпускает ошибку наружу"
                    .. " (сломана «" .. broken .. "»)")
                local shown, selected = tabState(ns)
                H.eq(#shown, 1, "сломана «" .. broken .. "», выбрана «" .. key
                    .. "»: показана одна вкладка [" .. table.concat(shown, ", ") .. "]")
                H.eq(#selected, 1, "и подсвечена одна ["
                    .. table.concat(selected, ", ") .. "]")
            end

            -- И падение не потерялось: оно записано в диагностику, а не съедено.
            local errs = ns.Diag:Init().errors or {}
            local found
            for _, e in ipairs(errs) do
                if tostring(e.where):find(broken, 1, true) then found = e end
            end
            H.ok(found ~= nil,
                "падение отрисовки «" .. broken .. "» записано в диагностику")
        end
    end
end

H.suite("Вкладки: без движка окно всё равно показывает ровно одну вкладку")
do
    -- Ровно то состояние, в котором был аддон у игрока: Logic\ActionEngine.lua
    -- не выполнился, ns.ActionEngine == nil. Загрузку это больше не ломает (см.
    -- test_load), но окно обязано держаться и в таком случае.
    local env = fresh()
    local ns = env.ns
    ns.MainFrame:Build()
    ns.ActionEngine = nil
    for _, key in ipairs({ "NOW", "CHAR", "CONFIG", "NOW", "CRAFT" }) do
        local ok = pcall(function() ns.MainFrame:Select(key) end)
        H.ok(ok, "без движка Select(«" .. key .. "») не выпускает ошибку наружу")
        local shown, selected = tabState(ns)
        H.eq(#shown, 1, "показана одна вкладка [" .. table.concat(shown, ", ") .. "]")
        H.eq(#selected, 1, "и подсвечена одна [" .. table.concat(selected, ", ") .. "]")
    end
end

-- «ДАЛЬШЕ» И «ПОНЯТНО» НИЧЕГО НЕ ПРЯЧУТ ----------------------------------
--
-- Игрок трижды оставался без советов и каждый раз решал, что аддон сломан.
-- Причина каждый раз была одна: кнопка, по названию которой нельзя догадаться,
-- что совет после неё исчезнет.
--
--   * «Дальше» на панели откладывала совет на час. Слово «дальше» обещает
--     следующий совет, а не пропажу этого.
--   * «Понятно» в списке вообще не была кнопкой: у информационных советов
--     кнопка скрыта, а прятал их ЛЮБОЙ левый щелчок по строке. То есть совет
--     исчезал от щелчка, у которого не было даже подписи.
--
-- Правило теперь одно, и оно проверяется целиком: совет прячет только то
-- действие, которое прямо называет себя скрытием, - правый щелчок, про который
-- сказано в чате и в подсказке. Всё остальное - кнопки, левые щелчки, «Дальше» -
-- не трогает число скрытых НИ НА ЕДИНИЦУ. «Дальше» листает советы по кругу и
-- помнит, где игрок остановился, вместо того чтобы прятать просмотренное.

local function hiddenCount(env)
    return env.ns.Config:DismissedCount(env.Api:ServerTime())
end

local function dismissedRecords(env)
    local n = 0
    for _ in pairs(env.ns.Config:Get().dismissed or {}) do n = n + 1 end
    return n
end

local function cardKeys(nsr)
    local out = {}
    for i, card in ipairs(nsr.ActionEngine.cards or {}) do out[i] = tostring(card.key) end
    return table.concat(out, " | ")
end

-- Прежняя «Дальше» прятала совет не сразу, а из отложенного вызова (после
-- анимации «готово»). В тестах таймеры копятся, а не срабатывают, поэтому без
-- этого прогона старое поведение выглядело бы невинным: нажали - ничего не
-- скрыто. Таймеры и тикеры докручиваются несколько раз, с ходом часов.
local function drainTimers(env)
    for _ = 1, 6 do
        H.clock = (H.clock or 0) + 1
        local timers = env.pendingTimers or {}
        env.pendingTimers = {}
        for _, fn in ipairs(timers) do pcall(fn) end
        for _, fn in ipairs(env.pendingTickers or {}) do pcall(fn) end
    end
end

local function pressNext(env)
    local f = env.ns.StepPanel.frame
    local btn = f and rawget(f, "next")
    local handler = btn and btn.__scripts and btn.__scripts.OnClick
    if not handler then return false, "у кнопки «Дальше» нет обработчика" end
    local ok, err = pcall(handler, btn)
    drainTimers(env)
    return ok, err
end

local function panelWorld()
    local env = fresh()
    local nsr = env.ns
    nsr.Config:Get().panel.enabled = true
    nsr.Config:ClearDismissed()
    nsr.StepPanel:ApplyVisibility()
    H.build(env)
    nsr.StepPanel:Render()
    return env, nsr
end

H.suite("«Дальше»: N нажатий не увеличивают число скрытых")
do
    local env, nsr = panelWorld()
    local f = nsr.StepPanel.frame
    H.ok(f ~= nil and rawget(f, "next") ~= nil, "кнопка «Дальше» на панели есть")
    H.eq(hiddenCount(env), 0, "до нажатий скрытых нет")

    local keysBefore = cardKeys(nsr)
    local totalBefore = #(nsr.ActionEngine.cards or {})
    local first = nsr.StepPanel.current
    H.ok(first ~= nil, "панель показывает совет: " .. tostring(first and first.title))
    H.ok(totalBefore >= 2, "советов в списке несколько: " .. totalBefore)

    -- Много нажатий: заведомо больше, чем советов, чтобы пройти круг не раз.
    local presses = totalBefore * 3 + 1
    local seen, order = {}, {}
    for i = 1, presses do
        local ok, err = pressNext(env)
        H.ok(ok, "нажатие " .. i .. " не падает", tostring(err))
        H.eq(hiddenCount(env), 0, "после нажатия " .. i .. " скрытых по-прежнему 0")
        H.eq(dismissedRecords(env), 0,
            "и в сохранённых настройках ни одной записи о скрытии")
        H.eq(cardKeys(nsr), keysBefore, "список советов не изменился")
        local cur = nsr.StepPanel.current
        if cur and not seen[cur.key] then
            seen[cur.key] = true
            order[#order + 1] = cur.key
        end
    end
    H.eq(#(nsr.ActionEngine.cards or {}), totalBefore,
        "советов столько же, сколько было: " .. totalBefore)
    H.ok(#order >= 2, "«Дальше» действительно листает: показано разных советов "
        .. #order)

    -- В чат про скрытие не сказано ничего: скрывать было нечего.
    H.eq(saidAny(env, "скрыл"), nil, "в чате нет ни слова про скрытие")
    -- И движок не считает ничего скрытым.
    H.build(env)
    H.eq((nsr.ActionEngine.meta or {}).hiddenByDismissal or 0, 0,
        "движок после пересчёта тоже не видит скрытых")
end

H.suite("«Дальше»: листает по кругу и возвращается к началу")
do
    local env, nsr = panelWorld()
    local start = nsr.StepPanel.current
    H.ok(start ~= nil, "есть с чего начать")
    if start then
        local cycle = { start.key }
        local back = false
        for _ = 1, #(nsr.ActionEngine.cards or {}) + 1 do
            pressNext(env)
            local cur = nsr.StepPanel.current
            if cur and cur.key == start.key then back = true; break end
            cycle[#cycle + 1] = cur and cur.key or "?"
        end
        H.ok(#cycle >= 2, "в круге больше одного совета: " .. #cycle)
        H.ok(back, "после полного круга панель вернулась к первому совету")
        local distinct, dupes = {}, 0
        for _, key in ipairs(cycle) do
            if distinct[key] then dupes = dupes + 1 end
            distinct[key] = true
        end
        H.eq(dupes, 0, "за круг ни один совет не показан дважды")
    end
end

H.suite("«Дальше»: есть и у совета со своим действием")
do
    -- Раньше «Дальше» стояла на месте кнопки действия и потому пропадала у
    -- любого совета, у которого есть своя кнопка, - то есть почти у всех. Идти
    -- дальше оставалось только правым щелчком, а он прячет.
    local env, nsr = panelWorld()
    local f = nsr.StepPanel.frame
    local withAction
    for _ = 1, #(nsr.ActionEngine.cards or {}) + 1 do
        local cur = nsr.StepPanel.current
        if cur and cur.action and cur.action.kind ~= "noop" and cur.action.label then
            withAction = cur; break
        end
        pressNext(env)
    end
    H.ok(withAction ~= nil, "на панели совет со своим действием: "
        .. tostring(withAction and withAction.action.label))
    if withAction then
        local labels = select(1, S.harvest(env.world, f))
        local joined = table.concat(labels, " | ")
        H.ok(joined:find(withAction.action.label, 1, true) ~= nil,
            "его кнопка на месте: " .. joined)
        H.ok(joined:find("Дальше", 1, true) ~= nil,
            "и «Дальше» тоже на экране: " .. joined)
    end
end

H.suite("«Дальше»: стоит не вплотную к «свернуть» и «убрать», и заголовок помещается")
do
    -- «Дальше» нажимают чаще всего, а рядом в заголовке - кнопки, после которых
    -- панель сворачивается или пропадает с экрана. Промах должен попадать в
    -- пустое место.
    local env, nsr = panelWorld()
    local f = nsr.StepPanel.frame
    local point = f.next.__points and f.next.__points[#f.next.__points]
    H.ok(point ~= nil, "у «Дальше» есть привязка")
    if point then
        H.eq(point[2], f.collapse, "она привязана к кнопке «свернуть»")
        local gap = -(tonumber(point[4]) or 0)
        H.ok(gap >= 12, "просвет до «свернуть»: " .. gap .. " — не меньше 12")
        H.eq(gap, nsr.StepPanel.NEXT_GAP, "и он задан одной константой")
    end

    -- На самой узкой панели и с самым длинным заголовком всё помещается в одну
    -- строку: текст заголовка слева, «Дальше», просвет, «свернуть», «убрать».
    local longest = "Совет " .. nsr.MAX_CARDS .. " из " .. nsr.MAX_CARDS
    local headerW = S.textWidth(longest)
    local right = 8 + (f.close:GetWidth() or 18) + 4 + (f.collapse:GetWidth() or 18)
        + nsr.StepPanel.NEXT_GAP + (f.next:GetWidth() or 58)
    local used = 10 + headerW + 6 + right
    H.ok(used <= nsr.StepPanel.WIDTH_MIN, "заголовок «" .. longest .. "» и кнопки занимают "
        .. used .. " из " .. nsr.StepPanel.WIDTH_MIN .. " на самой узкой панели")
end

H.suite("«Дальше»: не предлагается, когда листать нечего")
do
    -- Кнопка, которая ничего не делает, - тот же дефект, что текст про кнопку,
    -- которой нет. Один совет - листать некуда - кнопки нет.
    local env, nsr = panelWorld()
    local f = nsr.StepPanel.frame
    local only = nsr.StepPanel.current
    H.ok(only ~= nil, "есть совет")
    if only then
        nsr.ActionEngine.cards = { only }
        nsr.StepPanel:Render()
        local labels = select(1, S.harvest(env.world, f))
        local joined = table.concat(labels, " | ")
        H.ok(joined:find("Дальше", 1, true) == nil,
            "с одним советом кнопки «Дальше» нет: " .. joined)
    end

    -- Обязательный совет (без него остальные неполны) панель держит на виду,
    -- и перелистнуть его нельзя.
    local env2, ns2 = panelWorld()
    ns2.RecipeBook.byProfession = {}
    ns2.RecipeBook:Reindex()
    H.build(env2)
    ns2.StepPanel:Render()
    local pinned = ns2.StepPanel.current
    H.ok(pinned ~= nil and pinned.pinTop, "сверху обязательный совет: "
        .. tostring(pinned and pinned.title))
    local labels2 = select(1, S.harvest(env2.world, ns2.StepPanel.frame))
    H.ok(table.concat(labels2, " | "):find("Дальше", 1, true) == nil,
        "у обязательного совета «Дальше» нет: " .. table.concat(labels2, " | "))
end

H.suite("«Дальше»: место в списке помнится и после пересчёта")
do
    local env, nsr = panelWorld()
    pressNext(env)
    local second = nsr.StepPanel.current
    H.ok(second ~= nil, "перешли на следующий совет: " .. tostring(second and second.title))
    if second then
        -- Пересчёт - событие обычное, по нескольку раз в минуту. Панель не
        -- должна от него прыгать обратно на первый совет.
        H.build(env)
        nsr.StepPanel:Render()
        H.eq(nsr.StepPanel.current and nsr.StepPanel.current.key, second.key,
            "после пересчёта панель осталась на том же совете")

        -- Совет выполнен и пропал из списка: панель продолжает с того же
        -- места, а не возвращается к началу.
        local kept, removedAt = {}, nil
        for i, card in ipairs(nsr.ActionEngine.cards or {}) do
            if card.key == second.key then removedAt = i else kept[#kept + 1] = card end
        end
        H.ok(removedAt ~= nil, "совет найден в списке")
        nsr.ActionEngine.cards = kept
        nsr.StepPanel:Render()
        local after = nsr.StepPanel.current
        H.ok(after ~= nil and after.key ~= second.key,
            "пропавший совет панель больше не показывает")
        H.eq(hiddenCount(env), 0, "и скрытых как не было, так и нет")
    end
end

H.suite("Информационный совет: левый щелчок по нему ничего не прячет")
do
    -- У таких советов кнопки нет вовсе, а прятал их любой левый щелчок по
    -- строке: в коде это называлось «игрок нажал „Понятно“», только нажимать
    -- было нечего.
    local env = fresh()
    local nsr = env.ns
    nsr.Config:ClearDismissed()
    nsr.MainFrame:Build()
    nsr.MainFrame:Select("NOW")

    local info = {
        key = "test:info", kind = nsr.KIND.SETUP, title = "Информационный совет",
        why = "Просто к сведению.", need = "Ничего делать не нужно.",
        conf = nsr.CONF.EXACT, action = { kind = "noop" },
    }
    local row = nsr.Card.Acquire(nsr.TabNow.content, 40)
    nsr.Card.Fill(row, info)

    env.said = {}
    local click = row.__scripts and row.__scripts.OnClick
    H.ok(click ~= nil, "у строки совета есть обработчик щелчка")
    if click then
        for i = 1, 5 do
            local ok, err = pcall(click, row, "LeftButton")
            drainTimers(env)
            H.ok(ok, "левый щелчок " .. i .. " не падает", tostring(err))
        end
    end
    H.eq(nsr.Config:IsDismissed(info.key, env.Api:ServerTime()), false,
        "совет не скрыт")
    H.eq(hiddenCount(env), 0, "скрытых по-прежнему 0")
    H.eq(saidAny(env, "скрыл"), nil, "и в чат про скрытие ничего не написано")

    -- Неизвестное действие - тот же случай: проваливаться в скрытие нельзя.
    local odd = { key = "test:odd", kind = nsr.KIND.SETUP, title = "Совет",
                  conf = nsr.CONF.EXACT, action = { kind = "чего-то-нового" } }
    pcall(function() nsr.Card.Activate(odd) end)
    H.eq(nsr.Config:IsDismissed(odd.key, env.Api:ServerTime()), false,
        "совет с неизвестным действием тоже не скрыт")
end

H.suite("Список: ни левый щелчок, ни кнопка действия не прячут ни один совет")
do
    -- Инвариант целиком, на настоящих советах: единственный путь спрятать совет
    -- в списке - два правых щелчка, про которые сказано словами.
    local env = fresh()
    local nsr = env.ns
    nsr.Config:ClearDismissed()
    nsr.MainFrame:Build()
    nsr.MainFrame:Select("NOW")
    nsr.MainFrame:RenderActive()

    local rows = 0
    for _, row in ipairs(nsr.Card.pool or {}) do
        local card = rawget(row, "card")
        if card and row:IsShown() then
            rows = rows + 1
            local click = row.__scripts and row.__scripts.OnClick
            if click then pcall(click, row, "LeftButton") end
            drainTimers(env)
            H.eq(hiddenCount(env), 0, "левый щелчок по «"
                .. tostring(card.title):sub(1, 40) .. "» ничего не спрятал")

            local action = rawget(row, "action")
            if action and action:IsShown() then
                local press = action.__scripts and action.__scripts.OnClick
                if press then pcall(press, action) end
                drainTimers(env)
                H.eq(hiddenCount(env), 0, "кнопка «"
                    .. tostring(action.text and action.text:GetText())
                    .. "» ничего не спрятала")
            end
        end
    end
    H.ok(rows >= 3, "строк советов проверено: " .. rows)
end

H.suite("Кнопка «Понятно» там, где она есть, совет не прячет")
do
    -- «Понятно» осталась у двух обязательных советов про окно профессии: она
    -- повторяет в чат, что открыть. Раз её подпись не говорит о скрытии, то и
    -- прятать она не имеет права.
    local env = fresh()
    local nsr = env.ns
    nsr.Config:Get().panel.enabled = true
    nsr.Config:ClearDismissed()
    nsr.RecipeBook.byProfession = {}
    nsr.RecipeBook:Reindex()
    H.build(env)
    nsr.MainFrame:Build()
    nsr.MainFrame:Select("NOW")
    nsr.MainFrame:RenderActive()
    nsr.StepPanel:ApplyVisibility()
    nsr.StepPanel:Render()

    local pressed = 0
    for _, frame in ipairs(env.world.frames) do
        if frame.__type == "Button" and frame.__shown then
            local fs = rawget(frame, "text")
            local label = type(fs) == "table" and fs.__text or nil
            if label and S.plain(label) == "Понятно" then
                local press = frame.__scripts and frame.__scripts.OnClick
                if press then
                    pressed = pressed + 1
                    pcall(press, frame)
                    drainTimers(env)
                end
            end
        end
    end
    H.ok(pressed > 0, "кнопок «Понятно» нажато: " .. pressed)
    H.eq(hiddenCount(env), 0, "после них скрытых 0")
    H.eq(dismissedRecords(env), 0, "и записей о скрытии нет")
end

-- ПРАВЫЙ ЩЕЛЧОК ПО ПАНЕЛИ: ДВА ЩЕЛЧКА, КАК В СПИСКЕ ------------------------
--
-- Это был последний путь, которым совет исчезал от одного движения. В списке
-- правый щелчок давно требует подтверждения вторым, а на панели один щелчок
-- прятал совет на час - с оговоркой в подсказке, которую игрок не читает: он
-- кликает. Защищает не текст, а то, что одного щелчка мало.

-- Щелчок по панели настоящим обработчиком. Часы при этом НЕ идут: между двумя
-- щелчками подтверждения есть окно в несколько секунд, и прогон таймеров (он
-- двигает часы) сам закрыл бы это окно. Где нужно убедиться, что ничего не
-- случается с задержкой, таймеры докручиваются явно.
local function panelClick(env, button)
    local f = env.ns.StepPanel.frame
    local handler = f and f.__scripts and f.__scripts.OnClick
    if not handler then return false, "у панели нет обработчика щелчка" end
    return pcall(handler, f, button)
end

H.suite("Панель: один правый щелчок совет не прячет")
do
    local env, nsr = panelWorld()
    local target = nsr.StepPanel.current
    H.ok(target ~= nil and not target.blocking, "на панели обычный совет: "
        .. tostring(target and target.title))
    local keysBefore = cardKeys(nsr)

    env.said = {}
    local ok, err = panelClick(env, "RightButton")
    H.ok(ok, "правый щелчок не падает", tostring(err))
    -- И с задержкой тоже ничего не происходит: отложенные вызовы докручены.
    drainTimers(env)
    H.eq(hiddenCount(env), 0, "после одного правого щелчка скрытых 0")
    H.eq(dismissedRecords(env), 0, "и записей о скрытии нет")
    H.eq(cardKeys(nsr), keysBefore, "список советов тот же")
    H.eq(nsr.StepPanel.current and nsr.StepPanel.current.key, target and target.key,
        "на панели тот же совет")
    H.eq(saidAny(env, "скрыл на"), nil, "в чате не сказано, что совет скрыт")
    H.ok(saidAny(env, "скрыть «") ~= nil,
        "зато задан вопрос — и сказано, что нужен второй щелчок: " .. tostring(env.said[1]))

    -- Прошло больше, чем окно подтверждения: вопрос забыт, и следующий одиночный
    -- щелчок снова только спрашивает. Сколько бы одиночных щелчков ни было с
    -- перерывами, совет на месте.
    for i = 1, 4 do
        H.clock = (H.clock or 0) + nsr.Dismissal.CONFIRM_SECONDS + 5
        panelClick(env, "RightButton")
        H.eq(hiddenCount(env), 0, "одиночный щелчок " .. (i + 1)
            .. " с перерывом — скрытых по-прежнему 0")
    end
end

H.suite("Панель: два правых щелчка подряд прячут — на час и с дорогой назад")
do
    local env, nsr = panelWorld()
    local target = nsr.StepPanel.current
    env.said = {}
    panelClick(env, "RightButton")
    H.eq(hiddenCount(env), 0, "после первого — ещё нет")
    panelClick(env, "RightButton")
    H.eq(nsr.Config:IsDismissed(target.key, env.Api:ServerTime()), true,
        "после второго совет скрыт")
    local expiry = nsr.Config:Get().dismissed[target.key]
    H.eq(expiry and (expiry - env.Api:ServerTime()), nsr.SNOOZE_SECONDS,
        "ровно на час, как и обещает подсказка панели")
    H.eq(hiddenCount(env), 1, "и скрыт ровно один совет, а не больше")
    H.ok(saidAny(env, "/fp undo") ~= nil, "в чате названо, как вернуть именно его")

    -- И отмена действительно возвращает.
    nsr.Card.UndoLastHidden()
    H.eq(hiddenCount(env), 0, "/fp undo вернул совет")
end

H.suite("Панель: любое другое действие между щелчками снимает вопрос")
do
    -- Левый щелчок (открыть окно), «Дальше», кнопка действия - всё это «я имел
    -- в виду другое». После любого из них правый щелчок снова только спрашивает.
    local between = {
        { "левый щелчок по панели", function(env) panelClick(env, "LeftButton") end },
        { "«Дальше»", function(env) pressNext(env) end },
        { "кнопка действия", function(env)
            local f = env.ns.StepPanel.frame
            local btn = rawget(f, "action")
            local h = btn and btn.__scripts and btn.__scripts.OnClick
            if h then pcall(h, btn) end
            drainTimers(env)
        end },
    }
    for _, case in ipairs(between) do
        local env, nsr = panelWorld()
        local asked = nsr.StepPanel.current
        panelClick(env, "RightButton")
        H.eq(nsr.Dismissal:IsArmed(asked.key), true,
            case[1] .. ": после первого щелчка вопрос задан")

        -- ЧАСЫ ВОЗВРАЩАЮТСЯ НАЗАД. Действие между щелчками докручивает таймеры,
        -- а с ними идут часы - и вопрос снялся бы сам, по времени. Тогда набор
        -- проходил бы, даже если бы действие ничего не снимало. С часами на
        -- месте объяснение остаётся одно: вопрос сняло само действие.
        local clock = H.clock
        case[2](env)
        H.clock = clock
        H.eq(nsr.Dismissal:IsArmed(asked.key), false,
            case[1] .. ": вопрос снят самим действием, а не временем")

        -- Возвращаем на панель тот же совет и щёлкаем правой ещё раз. Совет
        -- ставится текущим напрямую: левый щелчок открывает окно, а открытие
        -- окна пересобирает мир теста с нуля, так что сама панель после него
        -- показала бы уже другой список. Проверяется здесь не выбор совета, а
        -- то, что правый щелчок по ТОМУ ЖЕ совету снова только спрашивает.
        nsr.Config:Get().panel.enabled = true
        nsr.StepPanel:ApplyVisibility()
        nsr.StepPanel.current = asked
        panelClick(env, "RightButton")
        H.eq(nsr.Config:IsDismissed(asked.key, env.Api:ServerTime()), false,
            case[1] .. " между щелчками: совет, про который спрашивали, не скрыт")
        H.eq(hiddenCount(env), 0, case[1] .. " между щелчками: скрытых 0")
    end
end

H.suite("Панель: обязательный совет не прячут и два щелчка")
do
    local env, nsr = panelWorld()
    nsr.RecipeBook.byProfession = {}
    nsr.RecipeBook:Reindex()
    H.build(env)
    nsr.StepPanel:Render()
    local pinned = nsr.StepPanel.current
    H.ok(pinned ~= nil and pinned.blocking, "на панели обязательный совет")
    env.said = {}
    panelClick(env, "RightButton")
    panelClick(env, "RightButton")
    panelClick(env, "RightButton")
    H.eq(hiddenCount(env), 0, "три правых щелчка — скрытых 0")
    H.ok(saidAny(env, "не скрываю") ~= nil,
        "и сказано почему: " .. tostring(env.said[1]))
end

H.suite("Панель: то, что прячет, называет себя скрытием и свой срок")
do
    -- Правый щелчок по панели - единственное действие на ней, которое прячет, и
    -- оно обязано быть названо: в подсказке - до щелчка, в чате - после, оба
    -- раза со сроком и с тем, как вернуть. И названо честно: щелчков два.
    local env, nsr = panelWorld()
    local f = nsr.StepPanel.frame
    local target = nsr.StepPanel.current
    H.ok(target ~= nil and not target.blocking, "на панели обычный совет")

    local tips = {}
    env.G.GameTooltip.AddLine = function(_, text) tips[#tips + 1] = tostring(text) end
    local enter = f.__scripts and f.__scripts.OnEnter
    H.ok(enter ~= nil, "у панели есть подсказка")
    if enter then pcall(enter, f) end
    local tip = S.plain(table.concat(tips, " "))
    local hourText = nsr.Util.durationText(nsr.SNOOZE_SECONDS) or "час"
    H.ok(tip:find("Два правых щелчка", 1, true) ~= nil,
        "в подсказке сказано, что щелчков два: " .. tip)
    H.ok(tip:find(hourText, 1, true) ~= nil,
        "и срок, на который совет прячется: " .. hourText)
    H.ok(tip:find("/fp undo", 1, true) ~= nil, "и как вернуть")
    H.ok(tip:find("Дальше", 1, true) == nil or tip:find("не пряч", 1, true) ~= nil,
        "а про «Дальше» не сказано, что она что-то прячет")
end

-- Панель: крестик -------------------------------------------------------

H.suite("Панель шага: её можно закрыть")
do
    local env = fresh()
    local ns = env.ns
    local cfg = ns.Config:Get()
    cfg.panel.enabled = true
    ns.StepPanel:ApplyVisibility()
    ns.StepPanel:Render()

    local f = ns.StepPanel.frame
    H.ok(f ~= nil, "панель построена")
    H.ok(f and rawget(f, "close") ~= nil,
        "у панели есть кнопка закрытия — без неё панель невозможно убрать")
    H.ok(f and rawget(f, "collapse") ~= nil, "кнопка свернуть тоже на месте")

    if f and rawget(f, "close") then
        local handler = f.close.__scripts and f.close.__scripts.OnClick
        H.ok(handler ~= nil, "у крестика есть обработчик")
        if handler then
            local ok, err = pcall(handler, f.close)
            H.ok(ok, "щелчок по крестику не падает", tostring(err))
            H.eq(f:IsShown(), false, "панель убралась с экрана")
            H.eq(cfg.panel.enabled, false,
                "и это записано в настройки — значит, переживёт перезагрузку")
        end
    end
end

H.suite("Панель шага: закрыв её, игрок узнаёт, как вернуть")
do
    local env = fresh()
    local ns = env.ns
    ns.Config:Get().panel.enabled = true
    ns.StepPanel:ApplyVisibility()
    env.said = {}
    ns.StepPanel:CloseByPlayer()

    H.ok(#env.said > 0, "в чат что-то написано")
    H.ok(saidAny(env, "/fp panel") ~= nil,
        "названа команда возврата: " .. tostring(env.said[1]))
    H.ok(saidAny(env, "астройк") ~= nil,
        "и галочка в настройках тоже названа")
    -- Способы собираются по тому, что есть. Кнопки у миникарты нет - значит,
    -- её и не обещаем.
    local env2 = fresh()
    env2.ns.Config:Get().ui.minimapButton = false
    env2.ns.MinimapButton.button = nil
    local without = env2.ns.StepPanel:HowToShow()
    H.ok(not S.plain(without):find("миникарт", 1, true),
        "без кнопки у миникарты она не упоминается: " .. tostring(without))

    local env3 = fresh()
    env3.ns.Config:Get().ui.minimapButton = true
    env3.ns.MainFrame:ApplyMinimapButton()
    local with = env3.ns.StepPanel:HowToShow()
    H.ok(S.plain(with):find("миникарт", 1, true) ~= nil,
        "а с кнопкой — упоминается: " .. tostring(with))
end

H.suite("Панель шага: закрытие не выключает аддон")
do
    local env = fresh()
    local ns = env.ns
    ns.Config:Get().panel.enabled = true
    ns.StepPanel:ApplyVisibility()

    -- Сравниваем пересчёт с открытой панелью и с закрытой: именно это и есть
    -- утверждение «панель — это отображение, а не выключатель движка».
    -- Сравнивать с числом до пересчёта нельзя: полный Rebuild перестраивает
    -- книгу рецептов с нуля и даёт другое число по причинам, к панели
    -- отношения не имеющим.
    -- Diag:Call пишет в МАП по имени вызова, а не в массив, поэтому считаем
    -- попытки, а не длину таблицы: `#s.calls` на таком ключе всегда 0, и
    -- сравнение «0 против 0» выглядело бы как успешная проверка.
    local function apiTries()
        local n = 0
        for _, e in pairs((ns.Diag:Init() or {}).calls or {}) do
            n = n + (tonumber(e.tries) or 0)
        end
        return n
    end

    local ok0, err0 = pcall(function() ns.MainFrame:Rebuild(true) end)
    H.ok(ok0, "пересчёт с открытой панелью", tostring(err0))
    local withPanel = #(ns.ActionEngine.cards or {})
    local diagBefore = apiTries()

    ns.StepPanel:CloseByPlayer()
    local ok, err = pcall(function() ns.MainFrame:Rebuild(true) end)
    H.ok(ok, "пересчёт после закрытия панели работает", tostring(err))
    local withoutPanel = #(ns.ActionEngine.cards or {})
    H.ok(withoutPanel > 0, "советы всё равно считаются: " .. withoutPanel)
    H.eq(withoutPanel, withPanel,
        "столько же советов, сколько с открытой панелью")

    -- Диагностика: сессия на месте и вызовы API продолжают в неё писаться.
    -- Без этого «панель закрыта» могло бы незаметно означать «аддон больше
    -- ничего про себя не записывает», и следующая жалоба осталась бы без данных.
    local s = ns.Diag:Init()
    H.ok(type(s) == "table", "сессия диагностики на месте")
    H.ok(apiTries() > diagBefore,
        "обращений к API записано больше, чем до закрытия панели: "
        .. apiTries() .. " против " .. diagBefore)
    local ok2, err2 = pcall(function() ns.Diag:Trim() end)
    H.ok(ok2, "диагностика подрезается без ошибок", tostring(err2))
    local lines = ns.Diag.Summary and ns.Diag:Summary() or nil
    H.ok(lines == nil or type(lines) == "table",
        "сводка самопроверки строится")

    -- И окно по-прежнему открывается.
    local ok3, err3 = pcall(function() ns.MainFrame:Show() end)
    H.ok(ok3, "окно открывается при закрытой панели", tostring(err3))
    H.ok(ns.MainFrame:IsShown(), "и показано")
end

H.suite("Панель шага: несколько путей вернуть")
do
    -- 1. Команда.
    local env = fresh()
    local ns = env.ns
    local G, sandbox = env.G, env.sandbox
    G.SlashCmdList = {}
    local chunk = assert(loadfile(H.ROOT .. "/Main.lua"))
    setfenv(chunk, sandbox)
    chunk("ForeverPilot", ns)
    ns.Bootstrap:RegisterSlash()
    local slash = G.SlashCmdList and G.SlashCmdList.FOREVERPILOT
    H.ok(slash ~= nil, "слэш-команда зарегистрирована")

    ns.Config:Get().panel.enabled = false
    if slash then
        local ok, err = pcall(slash, "panel")
        H.ok(ok, "/fp panel не падает", tostring(err))
        H.eq(ns.Config:Get().panel.enabled, true, "/fp panel вернул панель")
        pcall(slash, "panel")
        H.eq(ns.Config:Get().panel.enabled, false, "и он же её убирает")
        pcall(slash, "panel on")
        H.eq(ns.Config:Get().panel.enabled, true, "/fp panel on включает явно")
        pcall(slash, "panel off")
        H.eq(ns.Config:Get().panel.enabled, false, "/fp panel off выключает явно")
    end

    -- 2. Галочка в настройках.
    local env2 = fresh()
    local ns2 = env2.ns
    ns2.Config:Get().panel.enabled = false
    -- Через Show и Select, а не Build напрямую: закрытое окно — это «не на
    -- экране», и сбор видимых подписей обязан это учитывать, иначе он находил
    -- бы кнопки в невидимом окне.
    ns2.MainFrame:Show()
    ns2.MainFrame:Select("CONFIG")
    local labels = select(1, S.harvest(env2.world, ns2.MainFrame.frame))
    local found = false
    for _, label in ipairs(labels) do
        if S.plain(label):find("Показывать панель", 1, true) then found = true end
    end
    H.ok(found, "в настройках есть галочка «Показывать панель» даже когда панель выключена")

    -- 3. Кнопка в заголовке окна: видна ровно тогда, когда панель убрана.
    local env3 = fresh()
    local ns3 = env3.ns
    ns3.Config:Get().panel.enabled = false
    ns3.MainFrame:Show()
    local restore = ns3.MainFrame.restorePanel
    H.ok(restore ~= nil, "в заголовке окна есть кнопка возврата панели")
    if restore then
        H.eq(restore:IsShown(), true, "и она видна, пока панель убрана")
        local handler = restore.__scripts and restore.__scripts.OnClick
        H.ok(handler ~= nil, "у неё есть обработчик")
        if handler then
            pcall(handler, restore)
            H.eq(ns3.Config:Get().panel.enabled, true, "щелчок вернул панель")
            H.eq(restore:IsShown(), false, "и кнопка сама убралась — ей больше нечего делать")
        end
    end

    -- 4. Shift-щелчок по кнопке у миникарты.
    local env4 = fresh()
    local ns4 = env4.ns
    ns4.Config:Get().ui.minimapButton = true
    ns4.Config:Get().panel.enabled = false
    ns4.MainFrame:ApplyMinimapButton()
    local btn = ns4.MinimapButton.button
    H.ok(btn ~= nil, "кнопка у миникарты создана")
    if btn then
        local handler = btn.__scripts and btn.__scripts.OnClick
        env4.world.shiftDown = true
        local ok, err = pcall(handler, btn, "LeftButton")
        env4.world.shiftDown = false
        H.ok(ok, "Shift+ЛКМ по кнопке не падает", tostring(err))
        H.eq(ns4.Config:Get().panel.enabled, true, "Shift+ЛКМ вернул панель")
        -- И подсказка про это говорит.
        local enter = btn.__scripts and btn.__scripts.OnEnter
        H.ok(enter ~= nil, "у кнопки есть подсказка")
        if enter then
            local lines = {}
            local G4 = env4.G
            G4.GameTooltip.AddLine = function(_, text) lines[#lines + 1] = tostring(text) end
            pcall(enter, btn)
            local joined = S.plain(table.concat(lines, " "))
            H.ok(joined:find("Shift", 1, true) ~= nil,
                "и в ней написано про Shift: " .. joined)
        end
    end
end

-- Главное окно ----------------------------------------------------------

H.suite("Главное окно: закрытое состояние запоминается")
do
    local env = fresh()
    local ns = env.ns
    ns.MainFrame:Show()
    H.eq(ns.Config:WindowShown(), true, "открытое окно записано как открытое")

    env.said = {}
    ns.MainFrame:Hide()
    H.eq(ns.Config:WindowShown(), false, "закрытое — как закрытое")
    H.ok(#env.said > 0, "и в чат написано, как вернуть")
    H.ok(saidAny(env, "/fp") ~= nil, "команда названа: " .. tostring(env.said[1]))

    -- Esc через UISpecialFrames закрывает сам фрейм, минуя Main:Hide. Состояние
    -- всё равно должно записаться, иначе после Esc окно вернётся само.
    ns.MainFrame:Show()
    H.eq(ns.Config:WindowShown(), true, "снова открыто")
    ns.MainFrame.frame:Hide()
    H.eq(ns.Config:WindowShown(), false,
        "закрытие самого фрейма (Esc) тоже записывается")
end

H.suite("Главное окно: бой не переписывает выбор игрока")
do
    local env = fresh()
    local ns = env.ns
    ns.MainFrame:Show()
    ns.MainFrame:OnCombat(true)
    H.eq(ns.MainFrame:IsShown(), false, "в бою окно скрыто")
    H.eq(ns.Config:WindowShown(), true,
        "но «окно было открыто» НЕ переписано — иначе после боя оно не вернётся")
    ns.MainFrame:OnCombat(false)
    H.eq(ns.MainFrame:IsShown(), true, "после боя вернулось")

    -- И закрытое окно бой не открывает.
    ns.MainFrame:Hide()
    ns.MainFrame:OnCombat(true)
    ns.MainFrame:OnCombat(false)
    H.eq(ns.MainFrame:IsShown(), false, "закрытое окно бой не открывает")
end

H.suite("Главное окно: открытое состояние переживает перезагрузку")
do
    local env = fresh()
    local ns = env.ns
    ns.MainFrame:Show()
    H.eq(ns.Config:WindowShown(), true, "окно открыто")
    local saved = ns.Config:Get()

    -- Перезагрузка интерфейса: новый мир, те же SavedVariables.
    local env2 = S.load(H)
    env2.ns.Config:Bind(saved, {})
    S.populate(env2, H)
    local ok, err = pcall(function() env2.ns.Bootstrap = nil end)
    H.ok(ok, "подготовка второго мира", tostring(err))
    env2.ns.MainFrame:Build()
    env2.ns.MainFrame:RestoreShown()
    H.eq(env2.ns.MainFrame:IsShown(), true,
        "после перезагрузки окно вернулось открытым")

    -- А закрытое остаётся закрытым.
    env2.ns.MainFrame:Hide()
    local saved2 = env2.ns.Config:Get()
    local env3 = S.load(H)
    env3.ns.Config:Bind(saved2, {})
    S.populate(env3, H)
    env3.ns.MainFrame:Build()
    env3.ns.MainFrame:RestoreShown()
    H.eq(env3.ns.MainFrame:IsShown(), false,
        "а закрытое осталось закрытым")
end

-- Позиции ---------------------------------------------------------------

H.suite("Окна прижаты к экрану")
do
    local env = fresh()
    local ns = env.ns
    ns.MainFrame:Build()
    H.eq(ns.MainFrame.frame.__clamped, true,
        "главное окно прижато к экрану — иначе его можно утащить за край навсегда")
    ns.Config:Get().panel.enabled = true
    ns.StepPanel:Build()
    H.eq(ns.StepPanel.frame.__clamped, true, "панель тоже")
    ns.Arrow:Build()
    H.eq(ns.Arrow.frame.__clamped, true, "и стрелка")
end

H.suite("Сохранённая позиция за экраном исправляется при загрузке")
do
    local U = (fresh()).ns.Util
    -- Чистая арифметика, без фреймов: ровно поэтому её и можно проверить.
    H.eq(U.frameOffScreen(100, 100, 800, 600, 1920, 1080), false,
        "окно в середине экрана — на месте")
    H.eq(U.frameOffScreen(-900, 100, -100, 600, 1920, 1080), true,
        "целиком левее экрана — потеряно")
    H.eq(U.frameOffScreen(1900, 100, 2600, 600, 1920, 1080), true,
        "целиком правее экрана — потеряно")
    H.eq(U.frameOffScreen(100, 1100, 800, 1600, 1920, 1080), true,
        "выше экрана — потеряно")
    H.eq(U.frameOffScreen(100, -600, 800, -100, 1920, 1080), true,
        "ниже экрана — потеряно")
    -- Край: видно немного, но достаточно, чтобы схватить мышью.
    H.eq(U.frameOffScreen(-700, 100, 100, 600, 1920, 1080), false,
        "видно 100 пикселей — хватает, чтобы вытащить")
    H.eq(U.frameOffScreen(-780, 100, 20, 600, 1920, 1080), true,
        "видно 20 пикселей — уже не схватить")
    H.eq(U.frameOffScreen(nil, 100, 800, 600, 1920, 1080), false,
        "нет размеров — не трогаем, выдумывать не из чего")

    -- И окно реально спасается.
    local env = fresh()
    local ns = env.ns
    ns.Config:SaveFrame("TOPLEFT", "BOTTOMLEFT", -5000, -5000, 720, 560)
    ns.MainFrame:Build()
    local f = ns.MainFrame.frame
    f.__left, f.__bottom = -5000, -5000
    f:SetSize(720, 560)
    env.said = {}
    ns.MainFrame:ApplyPosition()
    local ui = ns.Config:Frame()
    H.eq(ui.x, 0, "x сброшен в центр")
    H.eq(ui.y, 0, "y сброшен в центр")
    H.eq(ui.point, "CENTER", "и точка привязки тоже")
    H.ok(saidAny(env, "центр") ~= nil or saidAny(env, "экран") ~= nil,
        "игроку сказали, что окно вернули: " .. tostring(env.said[1]))
end

H.suite("Панель: позиция за экраном исправляется")
do
    local env = fresh()
    local ns = env.ns
    local cfg = ns.Config:Get()
    cfg.panel.enabled = true
    cfg.panel.pos = { -4000, -4000 }
    ns.StepPanel:Build()
    ns.StepPanel:ApplyPosition()
    H.eq(cfg.panel.pos, nil, "негодная позиция панели сброшена")

    cfg.panel.pos = { 300, 400 }
    ns.StepPanel:ApplyPosition()
    H.ok(type(cfg.panel.pos) == "table" and cfg.panel.pos[1] == 300,
        "годная позиция не тронута")

    -- Стрелка — самый маленький фрейм, потерять её за краем проще всего.
    cfg.nav.pos = { -3000, -3000 }
    ns.Arrow:Build()
    ns.Arrow:ApplyPosition()
    H.eq(cfg.nav.pos, nil, "негодная позиция стрелки сброшена")
    cfg.nav.pos = { 500, 300 }
    ns.Arrow:ApplyPosition()
    H.ok(type(cfg.nav.pos) == "table" and cfg.nav.pos[1] == 500,
        "годная позиция стрелки не тронута")
end

H.suite("Проверка «за экраном» не срабатывает на пустом фрейме")
do
    local U = (fresh()).ns.Util
    -- Свежесозданный фрейм имеет размер 0x0, пока не позвали SetSize. Судить
    -- такой фрейм нельзя: у него ещё нет геометрии, и любой ответ будет
    -- выдумкой. Первая версия отвечала «потерян» и стирала позицию.
    H.eq(U.frameOffScreen(640, 480, 640, 480, 1920, 1080), false,
        "нулевой размер — не судим")
    H.eq(U.frameOffScreen(0, 0, 0, 0, 1920, 1080), false,
        "нулевой размер в нуле координат — тоже не судим")
    H.eq(U.frameOffScreen(640, 480, 630, 470, 1920, 1080), false,
        "перевёрнутые границы — не судим, это не данные, а мусор")
    H.eq(U.frameOffScreen(640, 480, 940, 580, 1920, 1080), false,
        "нормальный фрейм в середине — на месте")
end

H.suite("Панель: вход в игру не сбивает сохранённую позицию")
do
    local env = fresh()
    local ns = env.ns
    local cfg = ns.Config:Get()
    cfg.panel.enabled = true
    cfg.panel.pos = { 640, 480 }
    env.said = {}
    -- Ровно то, что делает Main.lua при входе: Build, затем ApplyVisibility.
    ns.StepPanel:Build()
    ns.StepPanel:ApplyVisibility()
    local pos = cfg.panel.pos
    H.ok(type(pos) == "table" and pos[1] == 640 and pos[2] == 480,
        "позиция панели не тронута при построении: " .. tostring(pos and pos[1]))
    H.eq(saidAny(env, "за краем экрана"), nil,
        "и в чат ничего про край экрана не написано")
end

H.suite("Главное окно: закрытое в бою не открывается после боя")
do
    local env = fresh()
    local ns = env.ns
    ns.MainFrame:Show()
    ns.MainFrame:OnCombat(true)
    H.eq(ns.MainFrame:IsShown(), false, "в бою скрыто")

    -- Игрок открыл его прямо в бою и тут же закрыл крестиком. Правило боя не
    -- должно воскресить окно: это его собственное решение, принятое позже.
    ns.MainFrame:Show()
    H.eq(ns.MainFrame:IsShown(), true, "открыл вручную в бою")
    ns.MainFrame:Hide()
    H.eq(ns.MainFrame:IsShown(), false, "и закрыл")
    H.eq(ns.Config:WindowShown(), false, "записано как закрытое")

    ns.MainFrame:OnCombat(false)
    H.eq(ns.MainFrame:IsShown(), false,
        "после боя осталось закрытым — последнее слово за игроком")
    H.eq(ns.Config:WindowShown(), false,
        "и настройка с экраном не разошлись")
end

H.suite("Главное окно: скрытие всего интерфейса не считается закрытием")
do
    local env = fresh()
    local ns = env.ns
    ns.MainFrame:Show()
    env.said = {}
    -- Alt+Z, кинематика, загрузочный экран: клиент скрывает UIParent, и OnHide
    -- приходит каждому дочернему окну. Это не решение игрока закрыть окно.
    env.G.UIParent:Hide()
    ns.MainFrame.frame:Hide()
    H.eq(ns.Config:WindowShown(), true,
        "состояние не переписано: интерфейс спрятан, а не окно закрыто")
    H.eq(#env.said, 0, "и в чат ничего не написано")

    env.G.UIParent:Show()
    -- А вот теперь это настоящее закрытие.
    ns.MainFrame.frame:Show()
    ns.MainFrame.frame:Hide()
    H.eq(ns.Config:WindowShown(), false, "обычное закрытие по-прежнему пишется")
end

H.suite("Панель: сообщение о возврате говорит правду")
do
    local env = fresh()
    local ns = env.ns
    local cfg = ns.Config:Get()
    cfg.panel.enabled = false
    -- Панель включают, но правило подземелья всё равно держит её скрытой.
    cfg.panel.instance = "hide"
    ns.StepPanel.inInstance = true
    env.said = {}
    ns.StepPanel:TurnOn()
    H.eq(cfg.panel.enabled, true, "галочка игрока включена")
    H.ok(ns.StepPanel.frame == nil or not ns.StepPanel.frame:IsShown(),
        "но на экране её нет — действует правило подземелья")
    H.ok(saidAny(env, "подземель") ~= nil,
        "и сказано, почему её не видно: " .. tostring(env.said[1]))

    -- Вне подземелья — обычное сообщение и панель на экране.
    ns.StepPanel.inInstance = false
    cfg.panel.enabled = false
    env.said = {}
    ns.StepPanel:TurnOn()
    H.eq(ns.StepPanel.frame:IsShown(), true, "панель на экране")
    H.ok(saidAny(env, "вернул") ~= nil, "и сказано, что вернул: " .. tostring(env.said[1]))
end

H.suite("Позиция и размер переживают перезагрузку интерфейса")
do
    local env = fresh()
    local ns = env.ns
    ns.Config:Get().panel.enabled = true
    ns.StepPanel:Build()
    ns.Config:Get().panel.pos = { 640, 480 }
    ns.StepPanel:ApplyPosition()
    ns.Config:SaveFrame("TOPLEFT", "TOPLEFT", 150, -90, 920, 620)
    ns.Config:SetScale(1.15)
    ns.Config:Get().ui.minimapAngle = 42
    ns.Config:Get().tab = "CRAFT"
    local saved = ns.Config:Get()

    -- Перезагрузка: новый мир, та же таблица SavedVariables.
    local env2 = S.load(H)
    env2.ns.Config:Bind(saved, {})
    S.populate(env2, H)
    local ns2 = env2.ns
    ns2.MainFrame:Build()
    ns2.MainFrame:ApplyPosition()
    ns2.MainFrame:ApplyScale()
    ns2.StepPanel:Build()

    local ui = ns2.Config:Frame()
    H.eq(ui.point, "TOPLEFT", "точка привязки окна сохранилась")
    H.eq(ui.x, 150, "x окна сохранился")
    H.eq(ui.width, 920, "ширина окна сохранилась")
    H.eq(ui.height, 620, "высота окна сохранилась")
    H.near(ns2.Config:Scale(), 1.15, 0.001, "масштаб сохранился")
    H.eq(ns2.Config:MinimapAngle(), 42, "угол кнопки у миникарты сохранился")
    H.eq(ns2.Config:Get().tab, "CRAFT", "открытая вкладка сохранилась")
    local pos = ns2.Config:Get().panel.pos
    H.ok(type(pos) == "table" and pos[1] == 640 and pos[2] == 480,
        "позиция панели сохранилась")

    -- И окно действительно получило сохранённый размер, а не дефолтный.
    H.eq(ns2.MainFrame.frame:GetWidth(), 920, "окно построено сохранённой ширины")
    H.eq(ns2.MainFrame.frame:GetHeight(), 620, "и сохранённой высоты")
end

-- «Вернуть все» ---------------------------------------------------------

H.suite("Панель: кнопка «Вернуть все» существует, когда есть что возвращать")
do
    local env = fresh()
    local ns = env.ns
    local cfg = ns.Config:Get()
    cfg.panel.enabled = true
    ns.StepPanel:ApplyVisibility()

    -- Скрываем всё, как это сделал игрок.
    local keys = {}
    for _, card in ipairs(ns.ActionEngine.cards or {}) do
        if not card.blocking then keys[#keys + 1] = card.key end
    end
    H.ok(#keys > 0, #keys .. " карточек можно скрыть")
    for _, key in ipairs(keys) do
        ns.Config:Dismiss(key, env.Api:ServerTime(), 86400)
    end
    H.build(env)
    ns.StepPanel:Render()

    local card = ns.StepPanel.current
    H.ok(card ~= nil and card.key == "hidden:restore",
        "панель показывает карточку про скрытые советы: " .. tostring(card and card.key))

    local labels, texts = S.harvest(env.world, ns.StepPanel.frame)
    local joinedLabels = table.concat(labels, " | ")
    H.ok(joinedLabels:find("Вернуть все", 1, true) ~= nil,
        "на панели есть кнопка «Вернуть все»: " .. joinedLabels)

    -- И она работает.
    local f = ns.StepPanel.frame
    local action = rawget(f, "action")
    H.ok(action ~= nil, "кнопка действия на панели есть")
    if action then
        local handler = action.__scripts and action.__scripts.OnClick
        H.ok(handler ~= nil, "и у неё есть обработчик")
        if handler then
            local ok, err = pcall(handler, action)
            H.ok(ok, "нажатие не падает", tostring(err))
            H.eq(ns.Config:DismissedCount(env.Api:ServerTime()), 0,
                "скрытых не осталось")
        end
    end
end

H.suite("Панель: у обычного совета своя кнопка, а не «Открыть»")
do
    local env = fresh()
    local ns = env.ns
    ns.Config:Get().panel.enabled = true
    ns.StepPanel:ApplyVisibility()
    H.build(env)

    -- Берём совет с настоящим действием и ставим его текущим.
    local target
    for _, card in ipairs(ns.ActionEngine.cards or {}) do
        if card.action and card.action.kind ~= "noop" and card.action.label then
            target = card; break
        end
    end
    H.ok(target ~= nil, "есть совет с собственным действием")
    if target then
        ns.StepPanel.current = target
        ns.StepPanel:RenderCard(target)
        local labels = select(1, S.harvest(env.world, ns.StepPanel.frame))
        local joined = table.concat(labels, " | ")
        H.ok(joined:find(target.action.label, 1, true) ~= nil,
            "кнопка подписана действием совета «" .. target.action.label
            .. "»: " .. joined)
    end
end

-- Срок скрытия ----------------------------------------------------------

H.suite("Панель: кнопки в нижней строке не наезжают друг на друга")
do
    local env = fresh()
    local ns = env.ns
    local cfg = ns.Config:Get()
    cfg.panel.enabled = true
    ns.StepPanel:Build()
    H.build(env)

    -- Самая узкая панель и самые длинные подписи одновременно: именно здесь
    -- «посчитано по подписи» превращается в «наехало на соседа».
    local f = ns.StepPanel.frame
    local function fits(width, label)
        cfg.panel.width = width
        ns.StepPanel:ApplySize()
        ns.StepPanel:RenderCard({
            key = "k", kind = ns.KIND.BUY, title = "Совет", conf = ns.CONF.EXACT,
            action = { kind = "shop", label = label, itemID = 1, qty = 1 },
            place = { mapID = 1434, x = 0.3, y = 0.4, routable = true },
        })
        local right = f.action:IsShown() and f.action or f.next
        local used = 18 + (f.badge:GetWidth() or 0) + (right:GetWidth() or 0) + 14
        if f.route:IsShown() then used = used + (f.route:GetWidth() or 0) end
        return used, f.route:IsShown()
    end

    for _, label in ipairs({ "Дальше", "Вернуть все", "В список покупок" }) do
        for _, width in ipairs({ 220, 260, 300, 360, 460 }) do
            local used, routeShown = fits(width, label)
            H.ok(used <= width, "ширина " .. width .. ", подпись «" .. label
                .. "»: всё влезло (" .. used .. " из " .. width
                .. (routeShown and ", с кнопкой пути" or ", без кнопки пути") .. ")")
        end
    end

    -- И значок достоверности с кнопкой действия не уступают никогда: без
    -- первого аддон перестаёт честно говорить, чего он не знает.
    fits(220, "В список покупок")
    H.eq(f.badge:IsShown(), true, "значок достоверности остаётся на самой узкой панели")
    H.eq(f.action:IsShown(), true, "и кнопка действия тоже")
    cfg.panel.width = 300
    ns.StepPanel:ApplySize()
end

H.suite("Сроки в текстах совпадают с кодом")
do
    local env = fresh()
    local ns = env.ns
    local U = ns.Util
    local dayText = U.durationText(ns.DISMISS_SECONDS)
    local hourText = U.durationText(ns.SNOOZE_SECONDS)
    H.ok(dayText and hourText, "сроки умеют превращаться в текст")

    -- Скрываем всё и читаем карточку-объяснение.
    for _, card in ipairs(ns.ActionEngine.cards or {}) do
        if not card.blocking then
            ns.Config:Dismiss(card.key, env.Api:ServerTime(), ns.DISMISS_SECONDS)
        end
    end
    H.build(env)
    local explain
    for _, card in ipairs(ns.ActionEngine.cards or {}) do
        if card.key == "hidden:restore" then explain = card end
    end
    H.ok(explain ~= nil, "карточка-объяснение есть")
    if explain then
        local text = S.plain((explain.why or "") .. " " .. (explain.need or ""))
        -- Правый щелчок прячет на сутки, кнопка в списке - на час. Назвать
        -- один срок для обоих - это и есть вранье, которое тут проверяется.
        local saysDay = text:find("сут", 1, true) or text:find(dayText, 1, true)
        local saysHour = text:find("час", 1, true) or text:find(hourText, 1, true)
        H.ok(not (saysDay and not saysHour),
            "если назван суточный срок, то назван и часовой — у кнопки он другой: "
            .. text)
    end
end

-- ИНВАРИАНТ -------------------------------------------------------------
--
-- Ни один текст не называет элемент, которого нет на том же экране.

H.suite("Инвариант: панель не обещает кнопок, которых на ней нет")
do
    local env = fresh()
    local ns = env.ns
    ns.Config:Get().panel.enabled = true
    ns.StepPanel:ApplyVisibility()

    -- Три состояния панели, в каждом свой текст.
    local states = {
        { name = "обычный совет", prepare = function() H.build(env) end },
        { name = "всё скрыто", prepare = function()
            for _, card in ipairs(ns.ActionEngine.cards or {}) do
                if not card.blocking then
                    ns.Config:Dismiss(card.key, env.Api:ServerTime(), 86400)
                end
            end
            H.build(env)
        end },
        { name = "советовать нечего", prepare = function()
            ns.Config:ClearDismissed()
            H.build(env)
            ns.ActionEngine.cards = {}
        end },
    }
    for _, state in ipairs(states) do
        state.prepare()
        ns.StepPanel:Render()
        local labels, texts = S.harvest(env.world, ns.StepPanel.frame)
        local bad = violations(labels, texts)
        H.eq(#bad, 0, "панель, состояние «" .. state.name .. "»: обещаний без кнопок нет"
            .. ((#bad > 0) and ("  <- " .. table.concat(bad, " ;; ")) or ""))
    end
    ns.Config:ClearDismissed()
    H.build(env)
end

H.suite("Инвариант: окно не обещает кнопок, которых на нём нет")
do
    local env = fresh()
    local ns = env.ns

    -- БЕЗ Show(), И ЭТО ВАЖНО.
    --
    -- Main:Show вызывает полный Rebuild, а тот пересобирает книгу рецептов с
    -- нуля и стирает мир, который тест только что подготовил: после Show
    -- скрывать было уже нечего, состояние «всё скрыто» не наступало, и проверка
    -- подтверждала не то, что обещала. Поймано диверсией — подменённый текст
    -- валил панель и не валил окно. Build+Select рисует ровно те же фреймы, а
    -- мир не трогает; «показано ли само окно» для сбора подписей не важно.
    ns.MainFrame:Build()

    local function checkTab(key, label)
        ns.MainFrame:Select(key)
        ns.MainFrame:RenderActive()
        local labels, texts = S.harvest(env.world, ns.MainFrame.frame)
        local bad = violations(labels, texts)
        H.eq(#bad, 0, "вкладка «" .. label .. "»: обещаний без кнопок нет"
            .. ((#bad > 0) and ("  <- " .. table.concat(bad, " ;; ")) or ""))
    end

    for _, def in ipairs(ns.MainFrame.TABS) do
        checkTab(def.key, def.label)
    end

    -- Пустая выдача: именно там живут самые разговорчивые тексты.
    local saved = ns.RecipeBook.byProfession
    ns.RecipeBook.byProfession = {}
    ns.RecipeBook:Reindex()
    H.build(env)
    checkTab("NOW", "Сейчас, нечего советовать")
    ns.RecipeBook.byProfession = saved
    ns.RecipeBook:Reindex()
    H.build(env)

    -- Всё скрыто.
    for _, card in ipairs(ns.ActionEngine.cards or {}) do
        if not card.blocking then
            ns.Config:Dismiss(card.key, env.Api:ServerTime(), 86400)
        end
    end
    H.build(env)
    checkTab("NOW", "Сейчас, всё скрыто")
    ns.Config:ClearDismissed()
    H.build(env)

    -- ПАНЕЛЬ УБРАНА. Это единственное новое состояние окна, и первая версия
    -- сюита его не проверяла вовсе: panel.enabled оставался дефолтным true, так
    -- что ветка настроек «Панель убрана, поэтому остальные её настройки
    -- спрятаны…» и кнопка «Вернуть панель» в заголовке под инвариант не
    -- попадали. Проверено подстановкой нарушения: тест оставался зелёным.
    ns.Config:Get().panel.enabled = false
    ns.MainFrame:UpdateRestoreButton()
    checkTab("CONFIG", "Настройки, панель убрана")
    checkTab("NOW", "Сейчас, панель убрана")
    ns.Config:Get().panel.enabled = true
    ns.MainFrame:UpdateRestoreButton()
    checkTab("CONFIG", "Настройки, панель на месте")

    -- Фильтр, под который ничего не подходит.
    ns.Config:SetChip(ns.CHIP.ENCHANT)
    local savedCards = ns.ActionEngine.cards
    ns.ActionEngine.cards = {}
    for _, card in ipairs(savedCards or {}) do
        if card.kind ~= ns.KIND.ENCHANT and card.kind ~= ns.KIND.SETUP then
            table.insert(ns.ActionEngine.cards, card)
        end
    end
    checkTab("NOW", "Сейчас, пустой фильтр")
    ns.ActionEngine.cards = savedCards
    ns.Config:SetChip(ns.CHIP.ALL)
end

H.suite("Инвариант: все названные в текстах команды существуют")
do
    local env = fresh()
    local ns = env.ns
    local G, sandbox = env.G, env.sandbox
    G.SlashCmdList = {}
    G.GetMerchantNumItems = function() return 0 end
    local chunk = assert(loadfile(H.ROOT .. "/Main.lua"))
    setfenv(chunk, sandbox)
    chunk("ForeverPilot", ns)
    ns.Bootstrap:RegisterSlash()
    local slash = G.SlashCmdList.FOREVERPILOT
    H.ok(slash ~= nil, "команда зарегистрирована")

    -- Собираем все /fp xxx, которые упоминаются где угодно в интерфейсе.
    --
    -- НЕ ТОЛЬКО С ЭКРАНА. Первая версия брала одни FontString'и и находила ровно
    -- две команды из девяти упомянутых: «как вернуть панель» живёт в строке в
    -- чат, а «Shift+ЛКМ» — в подсказке при наведении. Команда, названная только
    -- в чате, ломается точно так же, как названная на экране, поэтому
    -- собирается и то и другое: сообщения через подменённый Api:Print, строки
    -- подсказок — через подменённый GameTooltip:AddLine.
    local mentioned = {}
    local function scan(text)
        for _, cmd in ipairs(S.slashCommands(text)) do mentioned[cmd] = true end
    end

    local said, tipLines = {}, {}
    local Api = ns.Api
    function Api:Print(m) said[#said + 1] = tostring(m); scan(tostring(m)) end
    env.G.GameTooltip.AddLine = function(_, text)
        tipLines[#tipLines + 1] = tostring(text)
        scan(tostring(text))
    end

    ns.MainFrame:Build()
    for _, def in ipairs(ns.MainFrame.TABS) do
        ns.MainFrame:Select(def.key)
        ns.MainFrame:RenderActive()
        local labels, texts = S.harvest(env.world, ns.MainFrame.frame)
        for _, t in ipairs(texts) do scan(t) end
        for _, t in ipairs(labels) do scan(t) end
    end
    ns.Config:Get().panel.enabled = true
    ns.StepPanel:ApplyVisibility()
    ns.StepPanel:Render()
    local pl, pt = S.harvest(env.world, ns.StepPanel.frame)
    for _, t in ipairs(pt) do scan(t) end
    for _, t in ipairs(pl) do scan(t) end

    -- Подсказки: наводим мышь на всё, у чего есть OnEnter, на обеих
    -- поверхностях и на кнопке у миникарты.
    ns.Config:Get().ui.minimapButton = true
    ns.MainFrame:ApplyMinimapButton()
    local hovered = 0
    for _, frame in ipairs(env.world.frames) do
        local enter = frame.__scripts and frame.__scripts.OnEnter
        if enter then
            hovered = hovered + 1
            pcall(enter, frame)
        end
    end
    H.ok(hovered > 5, "подсказок опрошено: " .. hovered)
    H.ok(#tipLines > 0, "строк подсказок собрано: " .. #tipLines)

    -- И всё, что аддон говорит, закрывая и возвращая свои поверхности.
    ns.StepPanel:TurnOff()
    ns.StepPanel:TurnOn()
    ns.MainFrame:Show()
    ns.MainFrame:Hide()
    for _, card in ipairs(ns.ActionEngine.cards or {}) do
        scan((card.why or "") .. " " .. (card.need or ""))
    end
    local _, msg = ns.Dismissal:Hide({ key = "k", title = "t" })
    scan(msg or "")
    H.ok(#said > 0, "сообщений в чат собрано: " .. #said)

    local list = {}
    for cmd in pairs(mentioned) do list[#list + 1] = cmd end
    table.sort(list)
    H.ok(#list >= 3, "в текстах упомянуты команды: " .. table.concat(list, ", "))

    -- Каждая должна что-то делать. Неизвестная команда печатает справку —
    -- значит, признак существования такой: ответ НЕ равен ответу на абракадабру.
    local answers = {}
    function Api:Print(m) answers[#answers + 1] = tostring(m) end
    answers = {}
    pcall(slash, "этойкомандынет")
    local helpText = table.concat(answers, "\n")
    -- Без этой проверки вся следующая сравнивалась бы с пустой строкой и стала
    -- бы безусловно зелёной, если справку когда-нибудь перестанут печатать.
    H.ok(helpText ~= "", "неизвестная команда печатает справку, с чем и сравниваем")

    for _, cmd in ipairs(list) do
        answers = {}
        local ok = pcall(slash, cmd)
        local answer = table.concat(answers, "\n")
        H.ok(ok, "/fp " .. cmd .. " не падает")
        H.ok(answer ~= helpText,
            "/fp " .. cmd .. " — настоящая команда, а не опечатка в тексте")
    end

    -- И наоборот: выдуманная команда обязана распознаваться как выдуманная,
    -- иначе предыдущая проверка ничего не значит.
    answers = {}
    pcall(slash, "вернутьпанельпожалуйста")
    H.eq(table.concat(answers, "\n"), helpText,
        "выдуманная команда отвечает справкой — признак работает")
end

-- ВСЁ, ЧТО АДДОН ГОВОРИТ, ВО ВСЕХ СОСТОЯНИЯХ СРАЗУ ------------------------
--
-- Три набора выше проверяют экран в тех состояниях, которые вспомнили
-- перечислить. Этого оказалось мало трижды:
--
--   * «Открой аукцион и нажми „Искать на аукционе“» рисуется только когда
--     Auctionator умеет поиск списком. В тестах такого состояния не было вовсе,
--     так что эту строку проверка не видела никогда.
--   * Подсказки при наведении проверялись только на команды /fp, но не на
--     названия элементов. А у панели объяснение совета («почему») живёт ТОЛЬКО
--     в подсказке: обещание в нём не попадало ни под одну проверку.
--   * Сообщения в чат - то же самое.
--
-- Поэтому тексты собираются один раз, из многих состояний, со всех трёх каналов
-- (экран, подсказки, чат), и дальше по этому собранию ходят три проверки.

local CORPUS_STATES = {
    { name = "обычный", prepare = function() end },
    { name = "всё скрыто", prepare = function(env)
        for _, card in ipairs(env.ns.ActionEngine.cards or {}) do
            if not card.blocking then
                env.ns.Config:Dismiss(card.key, env.Api:ServerTime(), 86400)
            end
        end
        H.build(env)
    end },
    { name = "рецепты не прочитаны", prepare = function(env)
        env.ns.RecipeBook.byProfession = {}
        env.ns.RecipeBook:Reindex()
        H.build(env)
    end },
    { name = "без Auctionator", prepare = function(env)
        env.auctionator = false
        H.build(env)
    end },
    -- То самое состояние, которого не хватало: Auctionator загружен и отдаёт
    -- поиск списком. Только в нём под списком покупок появлялась строка про
    -- кнопку «Искать на аукционе».
    { name = "Auctionator умеет поиск списком", prepare = function(env)
        env.auctionator = true
        env.G.Auctionator = { API = { v1 = {
            MultiSearch = function() end,
            CreateShoppingList = function() end,
        } } }
        H.build(env)
    end },
    -- И состояние, в котором кнопка «Искать на аукционе» на экране: Auctionator
    -- умеет поиск, аукцион открыт, вкладка покупок на месте. Тексты, которые
    -- называют эту кнопку, обязаны появляться только вместе с ней.
    { name = "аукцион открыт, список можно передать", prepare = function(env)
        env.auctionator = true
        env.G.Auctionator = { API = { v1 = {
            MultiSearchAdvanced = function() end,
        } } }
        local ah = env.world.newFrame("Frame", "AuctionHouseFrame")
        ah:Show()
        env.G.AuctionHouseFrame = ah
        env.G.AuctionatorTabs_Shopping =
            env.world.newFrame("Button", "AuctionatorTabs_Shopping")
        H.build(env)
    end },
    { name = "банк не виден", prepare = function(env)
        env.bank = nil
        H.build(env)
    end },
    -- Окно профессий в этом заходе ещё не открывалось: кнопок «Показать рецепт»
    -- и «Показать формулу» на экране нет, вместо них - объяснение. Оно обязано
    -- пройти те же проверки, что и любой другой текст.
    { name = "окно профессий ещё не открывалось", prepare = function(env)
        env.professionsUI = false
    end },
    { name = "панель убрана", prepare = function(env)
        env.ns.Config:Get().panel.enabled = false
    end },
    { name = "панель свёрнута", prepare = function(env)
        env.ns.Config:Get().panel.collapsed = true
    end },
    { name = "фильтр, под который ничего не подходит", prepare = function(env)
        local nsr = env.ns
        nsr.Config:SetChip(nsr.CHIP.ENCHANT)
        local kept = {}
        for _, card in ipairs(nsr.ActionEngine.cards or {}) do
            if card.kind ~= nsr.KIND.ENCHANT and card.kind ~= nsr.KIND.SETUP then
                kept[#kept + 1] = card
            end
        end
        nsr.ActionEngine.cards = kept
    end },
    -- Порог мелкой денежной выгоды в действии: строка над списком называет
    -- раздел настроек, и этот раздел обязан существовать (см. QUOTED_TERMS).
    { name = "порог мелкой выгоды отсекает часть советов", prepare = function(env)
        local nsr = env.ns
        nsr.Config:SetMoneyFloorMode(nsr.MONEY_FLOOR_MODE.FIXED)
        nsr.Config:SetMoneyFloorOwn(1000)
        H.build(env)
    end },
}

-- Имена, которые в этом мире - данные, а не элементы интерфейса.
local function worldNames(env, into)
    local nsr = env.ns
    for _, t in ipairs({ nsr.PROFILE_LABEL, nsr.CHIP_LABEL, nsr.KIND_LABEL, nsr.CONF_LABEL }) do
        for _, v in pairs(t or {}) do into[tostring(v)] = true end
    end
    into[tostring(nsr.UNIT_BENEFIT)] = true
    for key in pairs(nsr.SLOT or {}) do
        into[tostring(nsr.SlotMap:Label(key))] = true
    end
    -- ИМЯ ПРОФЕССИИ - И КАК ЕГО ДАЛ ИСТОЧНИК, И КАК ЕГО ПОКАЖУТ ИГРОКУ.
    -- Второе не равно первому: клиент стенда отдаёт «Tailoring», а на экран
    -- идёт «Портняжное дело» (U.profLabel, Core/Util.lua). Оба - данные, а не
    -- выдуманные имена, и оба должны считаться известными.
    local function profName(name)
        if name == nil then return end
        into[tostring(name)] = true
        into[tostring(nsr.Util.profLabel(name))] = true
    end
    local snap = nsr.CharacterScanner:Get()
    for _, prof in ipairs((snap and snap.professions) or {}) do
        profName(prof.name)
    end
    for name in pairs(nsr.RecipeBook.byProfession or {}) do profName(name) end
    -- РЕЦЕПТ И ЕГО РАЗДЕЛ - ТОЖЕ ДАННЫЕ, А НЕ ВЫДУМАННЫЕ ИМЕНА.
    --
    -- Строка «откройте «Портняжное дело» и найдите «Новый капюшон» - раздел
    -- «Капюшоны»» называет в кавычках три вещи, и все три приходят из
    -- справочника рецептов. Без этих двух строк проверка объявляла раздел
    -- выдуманным именем интерфейса.
    for _, recipe in pairs(nsr.RecipeBook.byID or {}) do
        if recipe.name then into[tostring(recipe.name)] = true end
        if recipe.categoryName then into[tostring(recipe.categoryName)] = true end
    end
    for _, prof in ipairs(nsr.RecipeBook.missingProfessions or {}) do
        profName(prof.name)
    end
    for _, card in ipairs(nsr.ActionEngine.cards or {}) do into[tostring(card.title)] = true end
    for _, h in ipairs(nsr.ActionEngine.hidden or {}) do into[tostring(h.title)] = true end
    for _, info in pairs(env.items or {}) do
        if type(info) == "table" and info.name then into[tostring(info.name)] = true end
    end
    return into
end

-- Собрать подсказки: навести мышь на всё, у чего есть OnEnter.
local function hoverAll(env, tips)
    env.G.GameTooltip.AddLine = function(_, text) tips[#tips + 1] = tostring(text) end
    env.G.GameTooltip.AddDoubleLine = function(_, a, b)
        tips[#tips + 1] = tostring(a) .. " " .. tostring(b)
    end
    local hovered = 0
    for _, frame in ipairs(env.world.frames) do
        local enter = frame.__scripts and frame.__scripts.OnEnter
        if enter then
            hovered = hovered + 1
            pcall(enter, frame)
        end
    end
    return hovered
end

local function buildCorpus()
    local corpus = {
        screens = {},       -- { where, labels, texts } - каждый экран отдельно
        tips = {},          -- строки подсказок
        said = {},          -- строки в чат
        everywhere = {},    -- подписи всего интерфейса, множество
        everywhereList = {},-- они же списком
        data = {},          -- имена-данные всех миров
        hovered = 0,
    }
    local function screen(where, labels, texts)
        corpus.screens[#corpus.screens + 1] = { where = where, labels = labels, texts = texts }
        for _, label in ipairs(labels) do
            local plain = S.plain(label)
            if not corpus.everywhere[plain] then
                corpus.everywhereList[#corpus.everywhereList + 1] = label
            end
        end
        labelSet(labels, corpus.everywhere)
    end

    for _, state in ipairs(CORPUS_STATES) do
        local env = fresh()
        local nsr = env.ns
        nsr.Config:Get().panel.enabled = true
        nsr.Config:Get().ui.minimapButton = true
        state.prepare(env)
        nsr.MainFrame:Build()
        nsr.MainFrame:ApplyMinimapButton()
        nsr.StepPanel:ApplyVisibility()
        worldNames(env, corpus.data)
        -- Что аддон собирается сказать под списком покупок в этом состоянии:
        -- по этой строке ниже проверяется, что экран с ней действительно собран.
        corpus.handoff = corpus.handoff or {}
        corpus.handoff[state.name] = select(2, nsr.ShoppingList:HandoffState())

        for _, def in ipairs(nsr.MainFrame.TABS) do
            nsr.MainFrame:Select(def.key)
            nsr.MainFrame:RenderActive()
            local labels, texts = S.harvest(env.world, nsr.MainFrame.frame)
            screen(state.name .. " / окно / " .. def.label, labels, texts)
        end

        local pf = nsr.StepPanel.frame
        if pf and pf:IsShown() then
            nsr.StepPanel:Render()
            local labels, texts = S.harvest(env.world, pf)
            screen(state.name .. " / панель", labels, texts)
            -- Панель листается: у каждого совета свой текст и своя кнопка.
            for step = 1, #(nsr.ActionEngine.cards or {}) do
                if not nsr.StepPanel:Advance() then break end
                local l2, t2 = S.harvest(env.world, pf)
                screen(state.name .. " / панель, совет " .. (step + 1), l2, t2)
                corpus.hovered = corpus.hovered + hoverAll(env, corpus.tips)
            end
        end
        corpus.hovered = corpus.hovered + hoverAll(env, corpus.tips)

        -- Чат: всё, что аддон говорит по ходу обычных действий. Идёт ПОСЛЕ
        -- сбора экранов - эти действия меняют мир.
        env.said = {}
        pcall(function() nsr.StepPanel:TurnOff(); nsr.StepPanel:TurnOn() end)
        local victim
        for _, card in ipairs(nsr.ActionEngine.cards or {}) do
            pcall(function() nsr.Card.Activate(card) end)
            if not card.blocking and not victim then victim = card end
        end
        if victim then
            pcall(function() nsr.Card.RequestDismiss(victim) end)
            pcall(function() nsr.Card.RequestDismiss(victim) end)
            pcall(function() nsr.Card.UndoLastHidden() end)
            pcall(function() nsr.Card.RequestDismiss(victim, nsr.SNOOZE_SECONDS) end)
            pcall(function() nsr.Card.RequestDismiss(victim, nsr.SNOOZE_SECONDS) end)
            pcall(function() nsr.Card.RestoreHidden() end)
        end
        pcall(function() nsr.MainFrame.frame:Show(); nsr.MainFrame:Hide() end)
        for _, line in ipairs(env.said) do corpus.said[#corpus.said + 1] = line end
    end
    return corpus
end

local CORPUS = buildCorpus()

H.suite("Инвариант: собрание текстов не пустое")
do
    -- Проверка по пустому собранию проходит всегда. Сначала - что есть что
    -- проверять, и что в нём есть ровно те места, которых раньше не было.
    H.ok(#CORPUS.screens >= #CORPUS_STATES * 4,
        "экранов собрано: " .. #CORPUS.screens)
    H.ok(#CORPUS.tips > 50, "строк подсказок: " .. #CORPUS.tips)
    H.ok(#CORPUS.said > 20, "сообщений в чат: " .. #CORPUS.said)
    H.ok(CORPUS.hovered > 100, "наведений мыши: " .. CORPUS.hovered)

    -- Строка под списком покупок в состоянии «Auctionator умеет поиск списком» -
    -- та самая, что обещала несуществующую кнопку. Сверяется с тем, что аддон
    -- в этом состоянии говорит на самом деле, а не с заученной формулировкой.
    local stateName = "Auctionator умеет поиск списком"
    local handoff = CORPUS.handoff and CORPUS.handoff[stateName]
    H.ok(type(handoff) == "string" and handoff ~= "",
        "у состояния «" .. stateName .. "» есть строка под списком покупок")
    local sawHandoff, sawPaged = false, false
    for _, scr in ipairs(CORPUS.screens) do
        if scr.where == stateName .. " / окно / Крафт" then
            for _, text in ipairs(scr.texts) do
                if handoff and S.plain(text) == S.plain(handoff) then sawHandoff = true end
            end
        end
        if scr.where:find("панель, совет", 1, true) then sawPaged = true end
    end
    H.ok(sawHandoff, "и она попала в собрание: " .. tostring(handoff))

    -- В состоянии «список можно передать» кнопка действительно на экране:
    -- иначе проверка ниже смотрела бы на тексты про кнопку без самой кнопки.
    local sawButton = false
    for _, scr in ipairs(CORPUS.screens) do
        if scr.where == "аукцион открыт, список можно передать / окно / Крафт" then
            for _, label in ipairs(scr.labels) do
                if S.plain(label) == "Искать на аукционе" then sawButton = true end
            end
        end
    end
    H.ok(sawButton, "кнопка «Искать на аукционе» есть в собрании — там, где ей положено быть")
    local elsewhere = 0
    for _, scr in ipairs(CORPUS.screens) do
        if not scr.where:find("аукцион открыт, список можно передать", 1, true) then
            for _, label in ipairs(scr.labels) do
                if S.plain(label) == "Искать на аукционе" then elsewhere = elsewhere + 1 end
            end
        end
    end
    H.eq(elsewhere, 0, "и ни в одном другом состоянии её нет")
    H.ok(sawPaged, "панель пролистана: тексты не только первого совета")
end

H.suite("Инвариант: ни один экран ни в одном состоянии не обещает кнопки, которой на нём нет")
do
    for _, scr in ipairs(CORPUS.screens) do
        local bad = violations(scr.labels, scr.texts)
        H.eq(#bad, 0, scr.where .. ": обещаний без кнопок нет"
            .. ((#bad > 0) and ("  <- " .. table.concat(bad, " ;; ")) or ""))
    end
end

H.suite("Инвариант: подсказки и чат не называют элементов, которых нет в интерфейсе")
do
    -- Здесь правило мягче, чем для экрана, и это осознанно. Подсказка и строка
    -- в чате законно отправляют на ДРУГОЙ экран («галочка „Показывать панель“ в
    -- настройках»), поэтому названный элемент обязан существовать в интерфейсе
    -- вообще, а не на том же экране. Выдуманное имя не существует нигде - и
    -- именно оно здесь ловится.
    local bad = violations(CORPUS.everywhereList, CORPUS.tips)
    H.eq(#bad, 0, "в подсказках (" .. #CORPUS.tips .. " строк) обещаний без элемента нет"
        .. ((#bad > 0) and ("  <- " .. table.concat(bad, " ;; ")) or ""))
    local badChat = violations(CORPUS.everywhereList, CORPUS.said)
    H.eq(#badChat, 0, "в чате (" .. #CORPUS.said .. " строк) обещаний без элемента нет"
        .. ((#badChat > 0) and ("  <- " .. table.concat(badChat, " ;; ")) or ""))
end

-- Известные имена: подписи всего интерфейса, данные всех миров и термины.
local function knownNames(extraData)
    local known = {}
    for name in pairs(CORPUS.everywhere) do known[name] = true end
    for name in pairs(CORPUS.data) do known[name] = true end
    for name in pairs(extraData or {}) do known[name] = true end
    for name in pairs(QUOTED_TERMS) do known[name] = true end
    return known
end

H.suite("Инвариант: всё, что названо в кавычках, существует")
do
    -- Вторая проверка, от формулировки не зависящая: см. unaccounted().
    local known = knownNames()
    local all = {}
    for _, scr in ipairs(CORPUS.screens) do
        for _, text in ipairs(scr.texts) do all[#all + 1] = text end
        for _, label in ipairs(scr.labels) do all[#all + 1] = label end
    end
    for _, line in ipairs(CORPUS.tips) do all[#all + 1] = line end
    for _, line in ipairs(CORPUS.said) do all[#all + 1] = line end
    H.ok(#all > 500, "текстов всего: " .. #all)

    local missing = unaccounted(all, known)
    local bits = {}
    for _, m in ipairs(missing) do
        bits[#bits + 1] = "«" .. m.name .. "» в: " .. m.text:sub(1, 90)
    end
    H.eq(#missing, 0, "нет ни одного имени в кавычках, которого нет ни среди"
        .. " элементов, ни среди данных, ни среди терминов"
        .. ((#missing > 0) and ("  <- " .. table.concat(bits, " ;; ")) or ""))

    -- Список терминов не должен зарастать: каждый обязан встречаться в текстах.
    local quoted = {}
    for _, text in ipairs(all) do
        for _, name in ipairs(S.quotedNames(text)) do quoted[name] = true end
    end
    for term, reason in pairs(QUOTED_TERMS) do
        H.ok(quoted[term] == true,
            "термин «" .. term .. "» действительно встречается в текстах (" .. reason .. ")")
    end
end

-- «ВОЛШЕБНАЯ КНОПКА» НА КАРТОЧКЕ «СКРЫТЫХ СОВЕТОВ» -----------------------
--
-- Тот самый случай, с которого всё началось: карточка «Скрытых советов»
-- обещала кнопку «Волшебная кнопка», которой на панели нет, а проверка
-- осталась зелёной. В коде этой строки больше нет - она была подставлена,
-- чтобы испытать саму проверку, - и вместо неё стоит «Вернуть все», настоящая
-- подпись настоящей кнопки. Но «проверка осталась зелёной» - отдельный дефект,
-- и он воспроизводится здесь: подмена делается заново, на НАСТОЯЩЕЙ карточке,
-- в настоящем состоянии «всё скрыто», во всех формулировках, которые проверка
-- пропускала, и на обоих экранах.
--
-- Что именно пропускалось (проверено на прежнем детекторе):
--   «Нажмите X» в «чего не хватает»  - ловилось и на панели, и в окне;
--   «нажми X» на «ты»                - не ловилось нигде;
--   «вкладку X»                      - не ловилось нигде;
--   «X вернёт все советы»            - не ловилось нигде (нет слова-обещания);
--   «Нажмите X» в «почему»           - в окне ловилось, на панели нет: там
--                                      «почему» показывается только в подсказке.

local function sabotagedCard(field, text)
    local env = fresh()
    local nsr = env.ns
    nsr.Config:Get().panel.enabled = true
    nsr.StepPanel:ApplyVisibility()
    for _, card in ipairs(nsr.ActionEngine.cards or {}) do
        if not card.blocking then
            nsr.Config:Dismiss(card.key, env.Api:ServerTime(), 86400)
        end
    end
    H.build(env)
    local card
    for _, c in ipairs(nsr.ActionEngine.cards or {}) do
        if c.key == "hidden:restore" then card = c end
    end
    if not card then return nil end
    card[field] = text

    local known = knownNames(worldNames(env, {}))
    local result = { card = card }

    nsr.StepPanel:Render()
    local pl, pt = S.harvest(env.world, nsr.StepPanel.frame)
    local ptips = {}
    env.G.GameTooltip.AddLine = function(_, t) ptips[#ptips + 1] = tostring(t) end
    local enter = nsr.StepPanel.frame.__scripts and nsr.StepPanel.frame.__scripts.OnEnter
    if enter then pcall(enter, nsr.StepPanel.frame) end
    result.panelShows = (nsr.StepPanel.current == card)
    result.panelPromise = #violations(pl, pt)
    result.panelTipPromise = #violations(CORPUS.everywhereList, ptips)
    local panelAll = {}
    for _, t in ipairs(pt) do panelAll[#panelAll + 1] = t end
    for _, t in ipairs(ptips) do panelAll[#panelAll + 1] = t end
    result.panelQuoted = #unaccounted(panelAll, known)

    nsr.MainFrame:Build()
    nsr.MainFrame:Select("NOW")
    nsr.MainFrame:RenderActive()
    local wl, wt = S.harvest(env.world, nsr.MainFrame.frame)
    result.windowPromise = #violations(wl, wt)
    result.windowQuoted = #unaccounted(wt, known)
    return result
end

H.suite("Скрытые советы: настоящая карточка проверку проходит")
do
    -- Сначала без подмены: иначе «нарушение найдено» ниже могло бы означать,
    -- что проверка ругается на всё подряд.
    local env = fresh()
    local nsr = env.ns
    for _, card in ipairs(nsr.ActionEngine.cards or {}) do
        if not card.blocking then
            nsr.Config:Dismiss(card.key, env.Api:ServerTime(), 86400)
        end
    end
    H.build(env)
    local card
    for _, c in ipairs(nsr.ActionEngine.cards or {}) do
        if c.key == "hidden:restore" then card = c end
    end
    H.ok(card ~= nil, "карточка «Скрытых советов» есть")
    if card then
        H.eq(card.action and card.action.label, "Вернуть все",
            "её кнопка называется «Вернуть все»")
        H.ok(S.plain(card.need or ""):find("«Вернуть все»", 1, true) ~= nil,
            "и текст называет именно её: " .. S.plain(card.need or ""))
        H.ok(not S.plain((card.why or "") .. (card.need or "")):find("Волшебн", 1, true),
            "«Волшебной кнопки» в тексте карточки нет")
        local clean = sabotagedCard("benefit", card.benefit)
        H.ok(clean ~= nil and clean.panelShows, "панель показывает эту карточку")
        if clean then
            H.eq(clean.panelPromise + clean.panelTipPromise + clean.panelQuoted, 0,
                "на панели к настоящей карточке претензий нет")
            H.eq(clean.windowPromise + clean.windowQuoted, 0,
                "и в окне тоже")
        end
    end
end

H.suite("Скрытые советы: «Волшебная кнопка» ловится в любой формулировке, на панели и в окне")
do
    local CASES = {
        { "need", "Нажмите «Волшебная кнопка» — или наберите /fp show.",
          "«Нажмите X» — как было в исходной жалобе" },
        { "need", "Открой окно и нажми «Волшебная кнопка».",
          "«нажми X» на «ты» — прежняя проверка пропускала" },
        { "need", "Загляните на вкладку «Волшебная кнопка».",
          "«вкладку X» — прежняя проверка пропускала" },
        { "need", "«Волшебная кнопка» вернёт все советы.",
          "«X вернёт…» без слова-обещания — прежняя проверка пропускала" },
        { "why", "Нажмите «Волшебная кнопка».",
          "обещание в «почему» — на панели оно только в подсказке" },
        { "why", "«Волшебная кнопка» вернёт все советы.",
          "и то же без слова-обещания" },
        { "title", "Скрытых советов: 8 — нажмите «Волшебная кнопка»",
          "обещание прямо в заголовке" },
    }
    for _, case in ipairs(CASES) do
        local r = sabotagedCard(case[1], case[2])
        H.ok(r ~= nil and r.panelShows, case[3] .. ": панель показывает карточку")
        if r then
            local onPanel = r.panelPromise + r.panelTipPromise + r.panelQuoted
            local inWindow = r.windowPromise + r.windowQuoted
            H.ok(onPanel > 0, case[3] .. ": на ПАНЕЛИ поймано"
                .. " (обещание на экране " .. r.panelPromise
                .. ", в подсказке " .. r.panelTipPromise
                .. ", имя без пары " .. r.panelQuoted .. ")")
            H.ok(inWindow > 0, case[3] .. ": в ОКНЕ поймано"
                .. " (обещание " .. r.windowPromise
                .. ", имя без пары " .. r.windowQuoted .. ")")
        end
    end
end

H.suite("Чат: выдуманная кнопка в сообщении тоже ловится")
do
    local env = fresh()
    local nsr = env.ns
    nsr.Config:Get().panel.enabled = false
    local saved = nsr.StepPanel.CLOSE_HINT
    nsr.StepPanel.CLOSE_HINT = "Нажмите «Волшебная кнопка», чтобы убрать её."
    env.said = {}
    nsr.StepPanel:TurnOn()
    nsr.StepPanel.CLOSE_HINT = saved
    H.ok(#env.said > 0, "сообщение напечатано: " .. tostring(env.said[1]))
    H.ok(#violations(CORPUS.everywhereList, env.said) > 0,
        "обещание несуществующей кнопки в чате найдено")
    H.ok(#unaccounted(env.said, knownNames(worldNames(env, {}))) > 0,
        "и второй проверкой — тоже")
end


end
