-- ForeverPilot / Logic/Roster.lua
--
-- СВОЙ РЕЕСТР ПЕРСОНАЖЕЙ: ТО, ЧТО АДДОН ВИДЕЛ САМ.
--
-- Задача, которую больше нечем закрыть. Профессии персонажа лежат в
-- SavedVariablesPerCharacter - то есть пока игрок играет магом, файла
-- чернокнижника для него не существует: игра его просто не загружает. А
-- Syndicator, из которого берутся сумки и деньги альтов, профессий не хранит
-- вовсе (в живом файле у персонажа есть bags, bank, equipped, money - и ни
-- слова про навыки). Поэтому ветка «между персонажами» писала «у него
-- профессий нет»: это было не знание, а отсутствие знания, выданное за знание.
--
-- Пока у чернокнижника и правда не было профессий, фраза случайно совпадала с
-- правдой. Теперь у него алхимия, инженерное дело и кулинария - и фраза стала
-- ложью, которую нечем опровергнуть.
--
-- Решение: аддон ЗАПИСЫВАЕТ то, что сам увидел, в аккаунтную сохранёнку, по
-- одному разу на персонажа. Сыграли чернокнижником - запись о нём появилась;
-- зашли магом - она прочитана. Ничего не выдумывается и ничего не берётся из
-- чужих аддонов: в реестре лежит ровно то, что клиент сообщил про персонажа,
-- которым играли, вместе со временем, когда это было.
--
-- ЧЕГО ЗДЕСЬ НЕТ:
--   * догадок про персонажа, которым ни разу не играли. Его в реестре нет, и
--     ответ на вопрос о его профессиях - «не знаю», а не «нет»;
--   * чужих данных как основного источника. Кеш другого аддона может
--     подсказать класс и уровень (так уже делает Api:MastercraftCharacters),
--     но своя запись всегда впереди - по той же причине, что у книги закупок
--     в Core/Const.lua: чужая схема недокументирована и меняется без нас.
--
-- Запись стареет, и возраст виден. Персонаж, которым не играли месяц, мог за
-- этот месяц выучить что угодно: реестр отвечает «вот что было тогда-то», а не
-- «вот что есть».
local ADDON, ns = ...

local U = ns.Util
local CONF = ns.CONF

local Roster = {}
ns.Roster = Roster

-- Сколько персонажей помнить. Больше аккаунта не бывает, но сохранёнка живёт
-- дольше кода, и расти без предела она не должна.
Roster.MAX_CHARACTERS = 40

-- Сколько профессий помнить на персонажа. В игре их меньше, но данные приходят
-- из клиента, и верить его числам на слово здесь нельзя.
Roster.MAX_PROFESSIONS = 16

local function store()
    local cfg = ns.Config and ns.Config:Get()
    if not cfg then return nil end
    -- Сохранёнки старше этого модуля поля не имеют. Заводим на месте, как это
    -- делает Config:Ledger для книги закупок: дефолты объявлены, но файл мог
    -- быть записан до их появления.
    if type(cfg.chars) ~= "table" then cfg.chars = {} end
    return cfg.chars
end

-- Ключ персонажа. ПОЛНОЕ ИМЯ, а не имя: у игрока два персонажа по имени
-- «Гендольф», и ключ без фамилии склеил бы мага с чернокнижником - ровно та же
-- ошибка, из-за которой текущий персонаж числился чужим (см.
-- CrossCharacter:IsCurrent). GUID уникальнее, но его не знают ни Syndicator, ни
-- подпись карточки, а искать персонажа приходится именно по имени.
function Roster:Key(fullName)
    if type(fullName) ~= "string" or fullName == "" then return nil end
    return U.trim(fullName)
end

-- ВЕСЬ РЕЕСТР - КОПИЕЙ, А НЕ САМОЙ ТАБЛИЦЕЙ ИЗ СОХРАНЁНКИ.
--
-- Раньше здесь отдавалась живая таблица, и любой вызывающий мог править реестр
-- в обход Remember - то есть в обход ВСЕГО, что Remember соблюдает: порядка
-- источников («незнание не стирает знание»), предела в 40 персонажей и
-- обрезки, которая о себе сообщает. Сейчас ни один вызывающий этим не
-- пользуется (все три только читают), и именно поэтому закрыть дверь надо
-- сейчас, а не после первой правки, которая запишется мимо правил.
--
-- Копия глубокая: поверхностной хватило бы ровно до первого
-- `entry.professions[1].skill = ...`. Реестр - сорок записей по десятку полей,
-- и читают его на пересчёте, а не в цикле отрисовки.
--
-- КОМУ НУЖНА ЖИВАЯ ЗАПИСЬ, тот зовёт Roster:SkillCaps - там это сказано явно и
-- там это единственный осмысленный способ копить память между сессиями.
function Roster:All()
    return U.deepCopy(store() or {})
end

-- ИМЯ ПРОФЕССИИ ДЛЯ ЭКРАНА.
--
-- Чужой кеш пишет имена по-английски («Enchanting», «First Aid»), а клиент у
-- игрока русский: карточка «эти профессии есть у другого персонажа» читалась
-- как «Enchanting 225 — Гендольф Серыйй». Перевод берётся из единственного
-- словаря ru<->en, который в аддоне есть - RecipeBook.NAME_BRIDGE, тот же,
-- которым книга рецептов склеивает свои и чужие имена. Второй словарь рядом
-- неизбежно разошёлся бы с первым.
--
-- Имя, которого словарь не знает, отдаётся КАК ПРИШЛО: подставить прочерк
-- значило бы потерять единственное, что про эту профессию известно.
function Roster:DisplayName(professionName)
    if type(professionName) ~= "string" or professionName == "" then
        return professionName
    end
    local bridge = ns.RecipeBook and ns.RecipeBook.NAME_BRIDGE or nil
    if not bridge then return professionName end
    local ru = bridge[U.lower(professionName)]
    if not ru then return professionName end
    -- В словаре обе стороны лежат в нижнем регистре, и для английского имени
    -- ответом будет русское, а для русского - английское. Нужно только первое:
    -- если в ответе латиница, значит спрашивали русским именем, и менять нечего.
    if ru:find("^[%a]") and not ru:find("[\208\209]") then return professionName end
    -- Первую букву - заглавной, как её пишет клиент.
    local first = ru:sub(1, 2)
    local CAP = {
        ["а"] = "А", ["б"] = "Б", ["в"] = "В", ["г"] = "Г", ["д"] = "Д",
        ["е"] = "Е", ["ж"] = "Ж", ["з"] = "З", ["и"] = "И", ["к"] = "К",
        ["л"] = "Л", ["м"] = "М", ["н"] = "Н", ["о"] = "О", ["п"] = "П",
        ["р"] = "Р", ["с"] = "С", ["т"] = "Т", ["у"] = "У", ["ф"] = "Ф",
        ["х"] = "Х", ["ц"] = "Ц", ["ч"] = "Ч", ["ш"] = "Ш", ["э"] = "Э",
        ["ю"] = "Ю", ["я"] = "Я", ["ы"] = "Ы",
    }
    return (CAP[first] or first) .. ru:sub(3)
end

-- Запись о персонаже по полному имени. Ищет сначала точно, потом без учёта
-- регистра: имя приходит то от клиента, то из чужого кеша.
-- ОТВЕТ НЕ ЗАВИСИТ ОТ ПОРЯДКА ОБХОДА ТАБЛИЦЫ.
--
-- Поиск без учёта регистра брал ПЕРВОЕ совпадение из pairs, а порядок pairs в
-- Lua не определён. При двух ключах, различающихся только регистром
-- («Гендольф» и «гендольф» - так бывает, когда имя пришло один раз от клиента,
-- а другой из чужого кеша), ответ менялся от пересчёта к пересчёту: в одном
-- проходе читались потолки навыка одной записи, в другом - другой, и
-- «первая встреча» объявлялась заново.
--
-- Поэтому совпадения собираются все и выбирается НАИМЕНЬШИЙ ключ по порядку
-- строк. Выбор произвольный, но устойчивый - а это именно то, чего здесь не
-- хватало. И он не молчит: два ключа на одного персонажа - это дубль в
-- реестре, и его видно в диагностике.
function Roster:Find(fullName)
    local db = store()
    local key = Roster:Key(fullName)
    if not (db and key) then return nil end
    if db[key] then return db[key] end
    local want = U.lower(key)
    local hits = {}
    for name in pairs(db) do
        if U.lower(name) == want then hits[#hits + 1] = name end
    end
    if #hits == 0 then return nil end
    table.sort(hits)
    if #hits > 1 and ns.Diag then
        ns.Diag:Log("в реестре несколько ключей на одного персонажа", {
            asked = key, keys = hits, chosen = hits[1],
            why = "ключи различаются только регистром; беру первый по порядку"
                .. " строк, чтобы ответ не зависел от обхода таблицы",
        })
    end
    return db[hits[1]]
end

-- Записать то, что видно про ТЕКУЩЕГО персонажа. Зовётся из CharacterScanner
-- после сканирования, то есть ровно тогда, когда данные самые свежие.
--
-- ПЕРЕЗАПИСЫВАЕТСЯ ЦЕЛИКОМ, и это нарочно: профессию можно забыть (игрок
-- сбросил и взял другую), и дописывание оставило бы в реестре профессию,
-- которой у персонажа больше нет. Слияние со старой записью создало бы
-- персонажа с пятью профессиями, какого в игре не бывает.
function Roster:Remember(snap)
    local db = store()
    if not (db and type(snap) == "table") then return nil end
    local key = Roster:Key(snap.fullName or snap.name)
    if not key then return nil end

    local profs = {}
    for _, prof in ipairs(snap.professions or {}) do
        if #profs >= Roster.MAX_PROFESSIONS then break end
        if type(prof.name) == "string" and prof.name ~= "" then
            profs[#profs + 1] = {
                name = prof.name,
                -- Навык и потолок - только когда им верим. Ноль из
                -- GetProfessionInfoBySkillLineID значит «клиент не сказал», и
                -- записать его числом означало бы объявить навык нулевым.
                skill = prof.skillTrusted and tonumber(prof.skill) or nil,
                max = (tonumber(prof.max) or 0) > 0 and tonumber(prof.max) or nil,
                crafting = prof.crafting and true or false,
                gathering = prof.gathering and true or false,
            }
        end
    end

    local entry = {
        fullName = key,
        name = snap.name,
        surname = snap.surname,
        guid = snap.guid,
        realm = snap.realm,
        classFile = snap.classFile,
        className = snap.className,
        level = tonumber(snap.level),
        factionFile = snap.factionFile,
        professions = profs,
        -- КОНЕЧНОСТЬ СПИСКА - ОТДЕЛЬНОЕ УТВЕРЖДЕНИЕ. «Профессий ноль» и
        -- «клиент не назвал ни одной» на экране выглядели одинаково, а значат
        -- разное: первое - повод предложить крафт для этого персонажа, второе -
        -- повод открыть окно профессии. Клиент отдаёт список профессий сразу,
        -- без открытия окон, поэтому пустой список при EXACT - это правда.
        professionsKnown = (snap.professionsConf ~= CONF.UNKNOWN),
        professionsConf = snap.professionsConf,
        seenAt = tonumber(snap.scannedAt) or 0,
    }
    -- ПОТОЛКИ НАВЫКА ПЕРЕЖИВАЮТ ПЕРЕЗАПИСЬ ЗАПИСИ.
    --
    -- Профессии перезаписываются целиком нарочно (см. выше: профессию можно
    -- сбросить, и дописывание оставило бы в реестре чужую). А skillCaps - не
    -- наблюдение, а ПАМЯТЬ о прошлом наблюдении: её смысл именно в том, что она
    -- старше текущего снимка. Стирая её на каждом сканировании, модуль
    -- уведомлений получал «первую встречу» бесконечно и не мог объявить ни
    -- одного подъёма - то есть правка «потолки по персонажу» выглядела
    -- сделанной и не работала.
    local prev = Roster:Find(key)
    if prev and type(prev.skillCaps) == "table" then
        entry.skillCaps = prev.skillCaps
    end

    -- И ГЛАВНОЕ: НЕЗНАНИЕ НЕ СТИРАЕТ ЗНАНИЕ.
    --
    -- Пересчёт случается на каждом обновлении окна, в том числе рано - до того
    -- как игра отдала список профессий. В такой момент снимок приходит сюда с
    -- professionsConf = UNKNOWN и пустым списком, и безусловная запись СТИРАЛА
    -- полную запись прошлой сессии: про персонажа, которого знали, аддон
    -- начинал отвечать «не знаю». То же при деградации маршрута - когда
    -- профессии читаются из чужого кеша и их там меньше.
    --
    -- Правило простое и то же, что у RecipeBook:Store с его рангом источников:
    -- худшим ответом хорошую запись не трогаем. А настоящая смена профессий
    -- приходит с ответом НЕ ХУЖЕ прежнего и проходит целиком, в том числе если
    -- профессий стало меньше.
    --
    -- СРАВНИВАЕТСЯ ДОСТОВЕРНОСТЬ, А НЕ ТОЛЬКО ПРИЗНАК «КЛИЕНТ ОТВЕТИЛ».
    --
    -- Поле professionsConf записывалось с самого начала и не читалось нигде -
    -- то есть выглядело работающим рангом источников, а работал двоичный
    -- professionsKnown (есть ответ / нет ответа). Между ними прячется целый
    -- случай: ответ ЕСТЬ, но он хуже прежнего - профессии прочитаны из чужого
    -- кеша (ESTIMATE) там, где раньше их назвал клиент (EXACT). По двоичному
    -- признаку такой ответ проходил и стирал лучшую запись. Ранг - тот же, что
    -- у всех остальных источников в аддоне (U.confScore), второго порядка
    -- рядом не завели.
    local prevRank = U.confScore(prev and prev.professionsConf)
    local newRank = U.confScore(entry.professionsConf)
    if prev and prev.professionsKnown
        and (not entry.professionsKnown or newRank < prevRank) then
        if ns.Diag then
            ns.Diag:Log("реестр: худший ответ не стёр запомненные профессии", {
                character = key,
                remembered = #(prev.professions or {}),
                was = prev.professionsConf, now = entry.professionsConf,
                why = (not entry.professionsKnown)
                    and "клиент профессий не назвал — это не «их нет»"
                    or "ответ есть, но он менее достоверный, чем запомненный",
            })
        end
        -- Обновляем то, что УЗНАЛИ (класс, уровень, время), и сохраняем то, что
        -- знали раньше: профессии и признак их известности.
        entry.professions = prev.professions
        entry.professionsKnown = prev.professionsKnown
        entry.professionsConf = prev.professionsConf
        entry.seenAt = prev.seenAt
    end
    db[key] = entry

    -- Обрезка: самые старые записи уходят. Текущий персонаж только что записан,
    -- так что его не выбросит.
    local names = {}
    for name in pairs(db) do names[#names + 1] = name end
    if #names > Roster.MAX_CHARACTERS then
        table.sort(names, function(a, b)
            local ta = tonumber(db[a] and db[a].seenAt) or 0
            local tb = tonumber(db[b] and db[b].seenAt) or 0
            if ta ~= tb then return ta < tb end
            return a < b
        end)
        -- ОБРЕЗКА НЕ МОЛЧИТ. Выброшенная запись - это забытый персонаж, и
        -- вместе с ним забытые потолки его навыков. Тихое удаление памяти -
        -- ровно то поведение, от которого этот аддон избавляется везде.
        local dropped = {}
        for i = 1, #names - Roster.MAX_CHARACTERS do
            dropped[#dropped + 1] = names[i]
            db[names[i]] = nil
        end
        if ns.Diag then
            ns.Diag:Log("реестр персонажей обрезан", {
                dropped = #dropped, names = dropped,
                limit = Roster.MAX_CHARACTERS,
                why = "забыты самые давно не виденные; вместе с ними забыты их"
                    .. " потолки навыков",
            })
        end
    end
    return entry
end

-- ЧУЖОЙ КЕШ КАК ЗАПАСНОЙ ПУТЬ.
--
-- Своя запись появляется только после того, как этим персонажем сыграли при
-- установленном аддоне. До тех пор своих данных нет вовсе - а в кеше
-- Mastercraft профессии альта лежат, и аддон этот кеш уже читает: уровень и
-- класс другого персонажа берутся именно оттуда (Api:MastercraftCharacters).
--
-- Правило то же, что у книги закупок в Core/Const.lua, и по тем же причинам:
-- СВОЁ ВСЕГДА ВПЕРЕДИ, чужое работает запасным путём только пока своего нет, и
-- на экране называется чужим. Имена профессий там английские («Alchemy»), и это
-- видно: переводить их здесь было бы ещё одним местом, которое может разойтись
-- с книгой рецептов.
function Roster:ForeignProfessions(fullName)
    local Api = ns.Api
    if not (Api and Api.MastercraftDB) then return nil end
    local db = Api:MastercraftDB()
    if not (db and type(db.chars) == "table") then return nil end
    local key = Roster:Key(fullName)
    if not key then return nil end
    local want = U.lower(key)
    -- И ЗДЕСЬ ОТВЕТ НЕ ЗАВИСИТ ОТ ОБХОДА ТАБЛИЦЫ - по той же причине, что в
    -- Roster:Find. Чужой кеш разложен по GUID, и один персонаж может лежать в
    -- нём дважды: GUID меняется при переносе персонажа, а старая запись
    -- остаётся. Первое совпадение из pairs означало, что в одном пересчёте
    -- читается свежая запись, в другом - прошлогодняя, и профессии альта то
    -- появляются, то исчезают. Поэтому совпадения собираются все и ключи
    -- сортируются.
    local hits = {}
    for guid, c in pairs(db.chars) do
        if type(c) == "table" and type(c.name) == "string" then
            local full = (Api.FullName and Api:FullName(c.name, c.surname)) or c.name
            if full and U.lower(full) == want and type(c.professions) == "table" then
                hits[#hits + 1] = { key = tostring(guid), char = c }
            end
        end
    end
    if #hits == 0 then return nil end
    table.sort(hits, function(a, b) return a.key < b.key end)
    if #hits > 1 and ns.Diag then
        local keys = {}
        for _, hit in ipairs(hits) do keys[#keys + 1] = hit.key end
        ns.Diag:Log("в чужом кеше несколько записей на одного персонажа", {
            asked = key, keys = keys, chosen = hits[1].key,
            why = "беру первую по порядку ключей, чтобы ответ не зависел от"
                .. " обхода таблицы",
        })
    end
    local out = {}
    for _, prof in ipairs(hits[1].char.professions) do
        if type(prof) == "table" and type(prof.name) == "string" then
            if #out >= Roster.MAX_PROFESSIONS then break end
            out[#out + 1] = {
                name = prof.name,
                skill = tonumber(prof.skill),
                max = (tonumber(prof.max) or 0) > 0 and tonumber(prof.max) or nil,
                -- Крафтовая эта профессия или добычная, чужой кеш не
                -- говорит, и выдумывать мы не будем: поля просто нет.
                foreign = true,
            }
        end
    end
    if #out > 0 then return out end
    return nil
end

-- Профессии персонажа и то, насколько им можно верить.
-- Возвращает список, достоверность, возраст записи в секундах, источник
-- ("own" | "foreign").
--
-- nil вместо списка значит «не знаю», и это НЕ пустой список: пустой список -
-- утверждение «профессий нет», а его можно делать только про персонажа, по
-- которому запись есть.
function Roster:Professions(fullName)
    local entry = Roster:Find(fullName)
    if entry and entry.professionsKnown then
        local now = ns.Api and ns.Api.ServerTime and ns.Api:ServerTime() or 0
        local age = (now > 0 and (tonumber(entry.seenAt) or 0) > 0)
            and (now - entry.seenAt) or nil
        -- Своя запись - но записанная когда-то, а не сейчас: достоверность
        -- «из кеша», и возраст едет вместе с ней.
        --
        -- И НЕ ЛУЧШЕ, ЧЕМ БЫЛ САМ ОТВЕТ. Запись, сделанную с оценочного
        -- ответа, нельзя отдавать как «из кеша»: чтение с диска не добавляет
        -- достоверности тому, что в него положили. Поэтому берётся худшее из
        -- двух - тем же U.worstConf, которым считается достоверность любого
        -- вывода в аддоне. Это второе место, где читается professionsConf;
        -- первое - правило «худший ответ не стирает лучший» в Remember.
        return entry.professions or {},
            U.worstConf(CONF.CACHED, entry.professionsConf or CONF.CACHED),
            age, "own"
    end
    -- Своего нет - пробуем чужое, и помечаем как чужое.
    local foreign = Roster:ForeignProfessions(fullName)
    if foreign then
        -- Возраста у чужой записи мы не знаем: когда её писали, нам не сказали.
        return foreign, CONF.CACHED, nil, "foreign"
    end
    return nil, CONF.UNKNOWN, nil, nil
end

-- Навык конкретной профессии у конкретного персонажа, или nil.
function Roster:SkillOf(fullName, professionName)
    local profs = Roster:Professions(fullName)
    if not profs then return nil end
    local want = U.lower(professionName or "")
    for _, prof in ipairs(profs) do
        if U.lower(prof.name or "") == want then return tonumber(prof.skill), prof end
    end
    return nil
end

-- У КОГО ЕСТЬ ЭТА ПРОФЕССИЯ. Обратный вопрос, и именно он даёт осмысленные
-- советы теперь, когда профессии есть у обоих: «этот материал умеет сделать
-- Гендольф Белыйй, у него алхимия 150» - это не то же самое, что «он лежит у
-- него в сумках».
--
-- Возвращает список { fullName, name, label, skill, max, level, classFile,
-- seenAt }, лучшие по навыку первыми. Текущий персонаж исключается: совет
-- «попроси себя» бессмысленен.
function Roster:WhoHas(professionName, exceptFullName)
    local db = store()
    if not db then return {} end
    local want = U.lower(professionName or "")
    if want == "" then return {} end
    -- И АНГЛИЙСКАЯ ПАРА ИМЕНИ. Своя запись несёт имя, которое отдал клиент
    -- («Алхимия»), а чужой кеш - английское («Alchemy»). Спрашивают сюда с тем,
    -- которое есть под рукой, и ответ не должен зависеть от того, с каким.
    -- Словарь - тот же единственный NAME_BRIDGE, что у книги рецептов.
    local alias = ns.RecipeBook and ns.RecipeBook.NAME_BRIDGE
        and ns.RecipeBook.NAME_BRIDGE[want] or nil
    local except = exceptFullName and U.lower(Roster:Key(exceptFullName) or "") or nil
    local out = {}
    for name, entry in pairs(db) do
        if (not except) or U.lower(name) ~= except then
            for _, prof in ipairs(entry.professions or {}) do
                local have = U.lower(prof.name or "")
                if have == want or (alias and have == alias) then
                    -- ПОДПИСЬ, А НЕ ОДНО ИМЯ. У игрока два персонажа по имени
                    -- «Гендольф», и «у Гендольфа есть алхимия» не отвечает на
                    -- вопрос «у которого из двух». Поэтому рядом с именем едет
                    -- подпись: полное имя, уровень и класс словом - то же
                    -- правило, что в CrossCharacter:Label, и по той же причине.
                    local bits = {}
                    if entry.level then bits[#bits + 1] = entry.level .. " ур." end
                    if entry.className then bits[#bits + 1] = entry.className end
                    local label = (entry.fullName or name)
                        .. ((#bits > 0) and (", " .. table.concat(bits, ", ")) or "")
                    out[#out + 1] = {
                        fullName = entry.fullName or name,
                        -- `name` - полное имя, а не имя без фамилии: короткое
                        -- имя здесь неразличимо, и всякий, кто возьмёт это поле
                        -- для текста, получил бы ровно ту путаницу.
                        name = entry.fullName or name,
                        shortName = entry.name,
                        label = label,
                        surname = entry.surname,
                        skill = tonumber(prof.skill),
                        max = tonumber(prof.max),
                        level = entry.level,
                        classFile = entry.classFile,
                        className = entry.className,
                        profession = prof.name,
                        seenAt = entry.seenAt,
                    }
                end
            end
        end
    end
    table.sort(out, function(a, b)
        local sa, sb = a.skill or -1, b.skill or -1
        if sa ~= sb then return sa > sb end
        return tostring(a.fullName) < tostring(b.fullName)
    end)
    return out
end

-- Порядок держателей профессии: сильнее навык - раньше, при равном навыке - по
-- имени. Второй ключ не вкусовщина: обход pairs в Lua не упорядочен, и без него
-- при двух персонажах с одинаковым (или неизвестным) навыком выбранный «лучший»
-- менялся бы от пересчёта к пересчёту, а вместе с ним прыгало бы имя в
-- карточке.
local function bySkillThenName(a, b)
    local sa, sb = tonumber(a.skill) or -1, tonumber(b.skill) or -1
    if sa ~= sb then return sa > sb end
    return tostring(a.fullName) < tostring(b.fullName)
end

-- Все профессии, какие есть на аккаунте, и у кого. Нужно разделу «мой
-- персонаж» и ветке «между персонажами»: из этого видно, какая профессия
-- закрывает нужду, которую здесь закрыть нечем.
--
-- Своё и чужое вместе, но с пометкой: `source` у каждой записи говорит, видел
-- аддон это сам или прочитал в чужом кеше.
function Roster:ProfessionIndex()
    local db = store()
    local out = {}
    local seen = {}
    local function add(key, holder)
        if type(key) ~= "string" or key == "" then return end
        out[key] = out[key] or {}
        out[key][#out[key] + 1] = holder
    end
    for name, entry in pairs(db or {}) do
        seen[U.lower(name)] = true
        for _, prof in ipairs(entry.professions or {}) do
            add(prof.name, {
                fullName = entry.fullName or name,
                level = entry.level, className = entry.className,
                skill = tonumber(prof.skill), max = tonumber(prof.max),
                source = "own",
            })
        end
    end
    -- И персонажи, которых аддон сам не видел, но которые есть в чужом кеше.
    -- Запасной путь: своё уже разобрано выше, и перезаписать его это не может.
    local Api = ns.Api
    local foreignChars = (Api and Api.MastercraftCharacters)
        and Api:MastercraftCharacters() or nil
    for full, c in pairs(foreignChars or {}) do
        if not seen[U.lower(full)] then
            local profs = Roster:ForeignProfessions(full)
            for _, prof in ipairs(profs or {}) do
                add(prof.name, {
                    fullName = full, level = c.level, className = c.className,
                    skill = tonumber(prof.skill), max = tonumber(prof.max),
                    source = "foreign",
                })
            end
        end
    end
    -- Детерминированный порядок внутри каждой профессии: вызывающий выбирает
    -- «лучшего» строгим сравнением, и без сортировки при равных навыках ответ
    -- зависел бы от порядка обхода pairs.
    for _, holders in pairs(out) do table.sort(holders, bySkillThenName) end
    return out
end

-- ЧТО АДДОН ПОМНИТ О ДРУГИХ ПЕРСОНАЖАХ, ГОТОВЫМИ СТРОКАМИ.
--
-- Живёт ЗДЕСЬ, а не в UI/TabCharacter.lua, и это не вкусовщина: это
-- утверждения о мире («у него алхимия 150», «про него я не знаю»), и их надо
-- проверять тестом. Рисование проверить нечем - фреймов в тестах нет, UI в
-- стенд не загружается вовсе, - так что любое утверждение, уехавшее в файл UI,
-- становится непроверяемым. Отрисовка остаётся отрисовкой: она берёт эти
-- строки и ставит их в ряд.
--
-- Текущий персонаж исключён: его профессии стоят выше, в своём разделе.
--
-- Возвращает { { label, value, conf, source } }, по персонажу на строку.
function Roster:OtherCharacterLines()
    local snap = ns.CharacterScanner and ns.CharacterScanner:Get() or nil
    local me = snap and U.lower(snap.fullName or snap.name or "") or nil
    local out = {}
    for name, entry in pairs(Roster:All()) do
        if (not me) or U.lower(name) ~= me then
            local profs, conf, age, source = Roster:Professions(name)
            local bits = {}
            for _, prof in ipairs(profs or {}) do
                local line = Roster:DisplayName(prof.name)
                if prof.skill then
                    line = line .. " " .. prof.skill
                    if prof.max and prof.max > 0 then line = line .. "/" .. prof.max end
                end
                bits[#bits + 1] = line
            end
            -- ТРИ РАЗНЫХ ОТВЕТА, И НИ ОДИН НЕ «ПРОФЕССИЙ НЕТ» ПО УМОЛЧАНИЮ.
            local value
            if not profs then
                value = "профессий его я не знаю"
            elseif #bits == 0 then
                value = "профессий нет"
            else
                value = table.concat(bits, ", ")
                if source == "foreign" then
                    value = value .. " (" .. ns.FOREIGN_BOOK.short .. ")"
                elseif age and age > (ns.PRICE_AGE_SAY_SECONDS or 86400) then
                    value = value .. " (видел " .. (U.ageText(age) or "давно") .. ")"
                end
            end
            local label = entry.fullName or name
            local tail = {}
            if entry.level then tail[#tail + 1] = entry.level .. " ур." end
            if entry.className then tail[#tail + 1] = entry.className end
            if #tail > 0 then label = label .. ", " .. table.concat(tail, ", ") end
            out[#out + 1] = { label = label, value = value, conf = conf,
                              source = source }
        end
    end
    table.sort(out, function(a, b) return tostring(a.label) < tostring(b.label) end)
    return out
end

-- ПОТОЛКИ НАВЫКА - ПО ПЕРСОНАЖУ -----------------------------------------
--
-- Жили в аккаунтной сохранёнке одной таблицей, заведённой по ИМЕНИ профессии.
-- У мага кулинария 225, у чернокнижника она качается с единицы - и в живом
-- файле игрока там лежит ровно это: Кулинария = 225 (мага), Алхимия = 75,
-- Инженерное дело = 75 (чернокнижника). Из-за общей таблицы подъём потолка
-- кулинарии у чернокнижника (75 -> 150) попадал в ветку «клиент ответил хуже,
-- чем раньше», записывался в счётчик skillCapWentDown и пропадал молча - то
-- есть ровно та новость, которую модуль существует чтобы сообщать.
--
-- Это тот же класс ошибки, что был с рецептами по GUID: одно имя, два
-- персонажа, одна ячейка.
function Roster:SkillCaps(fullName)
    local db = store()
    local key = Roster:Key(fullName)
    if not (db and key) then return {} end
    -- ЧЕРЕЗ Roster:Find, А НЕ ПО ТОЧНОМУ КЛЮЧУ.
    --
    -- Поиск без учёта регистра здесь не придирка: это хранилище ПАМЯТИ между
    -- сессиями. Имя, пришедшее с другим регистром, завело бы вторую запись, а
    -- вместе с ней - второй, пустой набор потолков; накопленное при этом не
    -- потерялось бы, но перестало бы читаться, и каждый вход снова был бы
    -- «первой встречей».
    local entry = Roster:Find(key)
    if not entry then
        -- Персонажа в реестре ещё нет (первый вход до первого сканирования).
        -- Заводим пустую запись: потолки надо куда-то писать, а выдумывать для
        -- них отдельное хранилище значило бы развести два места, которые потом
        -- разойдутся.
        entry = { fullName = key, professions = {}, seenAt = 0 }
        db[key] = entry
    end
    if type(entry.skillCaps) ~= "table" then entry.skillCaps = {} end
    return entry.skillCaps
end

return Roster
