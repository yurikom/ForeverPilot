-- ForeverPilot / Tests/test_camp.lua
--
-- ЛАГЕРЬ У КОСТРА: ЧТО ВЕТКА ОБЯЗАНА ГОВОРИТЬ И ЧЕГО ОБЯЗАНА НЕ ГОВОРИТЬ.
--
-- Набор держит восемь контрактов, и каждый из них - про отдельную ошибку,
-- которую легко сделать именно в этой ветке:
--
--   1. ПОРОГИ НАВЫКА НЕ ЗАБИТЫ В КОД. Они в Data/Camp.lua, двумя числами из
--      двух баз; где числа расходятся, ветка берёт бо́льшее и говорит, что
--      порог спорный. Blizzard уже правила эти пороги хотфиксом, и код,
--      который «знает» число, через месяц врёт.
--   2. СЧИТАЕТСЯ ПО ОБОИМ ПЕРСОНАЖАМ. Предмет лагеря даёт каждая профессия,
--      включая добычные; у игрока профессии разложены на двух персонажей, и
--      ответ «сколько предметов мне доступно» без второго персонажа неверен.
--   3. ВЫУЧЕН ЛИ РЕЦЕПТ - СПРАШИВАЕТСЯ У КНИГИ РЕЦЕПТОВ. Предметы лагеря лежат
--      в окне профессии рецептами; «не выучен» без этой проверки было бы
--      утверждением из незнания.
--   4. ЧЕРТЁЖ - ЭТО ПОКУПКА. Он предмет, он торгуется, и совет про него -
--      «иди на аукцион», а не «качай навык».
--   5. API ЛАГЕРЯ НЕ СУЩЕСТВУЕТ, И ЭТО СКАЗАНО ИГРОКУ СЛОВАМИ. Ни C_Camping,
--      ни PLAYER_CAMPING (это древний выход из игры) в аддоне нет.
--   6. ПОРОГ МЕЛКОЙ ДЕНЕЖНОЙ ВЫГОДЫ ЛАГЕРЯ НЕ КАСАЕТСЯ. Совет про лагерь не
--      приносит денег, он их тратит: порог, приложенный к трате, выбросил бы
--      самый дешёвый совет аддона за то, что тот дешёвый.
--   7. НИ ОДНА ПРОПАЖА НЕ МОЛЧИТ. Ветка без карточек обязана сказать, почему.
--   8. ЦЕНА РАБОТЫ МЕРИТСЯ ВЫЗОВАМИ. Объектов 38, и полный разбор каждого на
--      каждом пересчёте стоил бы около 170 вопросов о цене.
local H = ...
local D = assert(loadfile((H.ROOT or ".") .. "/Tests/dialect.lua"))()

return function()

local ROOT = H.ROOT or "."

-- Мир лагеря -------------------------------------------------------------
--
-- Настоящие числа игрока: маг 29 ур. с рыбалкой 225 и кулинарией 225, у него
-- выучен аквариум и НЕ выучен костёр подмастерья, а алхимия лежит на втором
-- персонаже. Имена, номера и реагенты - те же, что в Data/Camp.lua.
local FISH_BOWL = 279967
local BASIC_FIRE = 279981
local JOURNEY_FIRE = 279961
local JOURNEY_BP = 273087
local MANA_WELL = 279956
local BANNER = 279972

local function campEnv(opts)
    opts = opts or {}
    local env = H.load()
    local ns = env.ns
    env.player.name = "Гендольф"
    env.player.surname = "Серыйй"
    env.player.level = opts.level or 29
    env.player.classFile = "MAGE"
    env.player.className = "Маг"
    env.player.factionFile = opts.faction or "Horde"
    env.player.guid = "Player-6946-00CCA8FC"
    env.money = opts.money or 107040
    env.auctionator = true

    -- Предметы лагеря и реагенты: имена, как их отдаёт клиент.
    H.item(env, FISH_BOWL, { name = "Аквариум", sellPrice = 32 })
    H.item(env, BASIC_FIRE, { name = "Обычный костер", sellPrice = 13 })
    H.item(env, JOURNEY_FIRE, { name = "Костер подмастерья", sellPrice = 90 })
    H.item(env, JOURNEY_BP, { name = "Чертеж: костер подмастерья", sellPrice = 3000 })
    H.item(env, MANA_WELL, { name = "Колодец маны", sellPrice = 39 })
    H.item(env, BANNER, { name = "Знамя фракции", sellPrice = 12 })
    H.item(env, 6291, { name = "Сырая блестящая рыбка", sellPrice = 18 })
    H.item(env, 3371, { name = "Пустая колба", sellPrice = 1 })
    H.item(env, 4470, { name = "Простая древесина", sellPrice = 9 })
    H.item(env, 11291, { name = "Звездная древесина", sellPrice = 100 })
    H.item(env, 2447, { name = "Мироцвет", sellPrice = 40 })
    H.item(env, 2996, { name = "Рулон льняной ткани", sellPrice = 15 })
    H.item(env, 2320, { name = "Грубая нить", sellPrice = 2 })

    env.prices[FISH_BOWL] = 160
    env.prices[JOURNEY_BP] = opts.bpPrice or 157095
    env.prices[MANA_WELL] = 197
    env.prices[6291] = 90
    env.prices[3371] = 5
    env.prices[4470] = 39
    env.prices[11291] = 4150
    env.prices[2447] = 179
    env.prices[2996] = 60
    env.prices[2320] = 11
    env.vendorPrices[3371] = 4
    env.vendorPrices[4470] = 38

    -- Простая древесина в сумках: костёр собирается без покупок.
    if opts.wood ~= false then env.bags[4470] = 3 end

    -- МИР БЕЗ ЦЕН. Нужен не для полноты: именно в нём у ветки лагеря пропадают
    -- сразу две фразы - «готовый на аукционе стоит столько» и «мест у костра
    -- станет больше», - и склейка строки получает nil вместо куска текста.
    -- Так и было найдено падение всего пересчёта (Engine.JoinSentences).
    if opts.noPrices then
        env.prices = {}
        env.vendorPrices = {}
        env.observedPrices = nil
        env.auctionator = false
        -- И цену выкупа у предмета тоже в ноль: по ней провайдер цен считает
        -- последнюю, самую слабую оценку (sellPrice x 4), и пока она есть -
        -- «цены нет» не наступает вовсе, то есть проверялся бы не тот мир.
        for _, info in pairs(env.items) do info.sellPrice = 0 end
    end

    -- Рыбалка: три рецепта, как в окне профессии у игрока. Аквариум выучен.
    H.profession(env, "Рыбная ловля", opts.fishing or 225, 225, {
        H.recipe { id = 1229745, name = "Аквариум", output = FISH_BOWL,
                   learned = (opts.fishBowlLearned ~= false),
                   reagents = { { itemID = 6291, qty = 1 }, { itemID = 3371, qty = 1 } } },
    })
    -- Кулинария: обычный костёр выучен, костёр подмастерья - нет.
    H.profession(env, "Кулинария", opts.cooking or 225, 225, {
        H.recipe { id = 1229737, name = "Обычный костер", output = BASIC_FIRE,
                   learned = true, reagents = { { itemID = 4470, qty = 1 } } },
        H.recipe { id = 1283400, name = "Костер подмастерья", output = JOURNEY_FIRE,
                   learned = false, reagents = { { itemID = 11291, qty = 1 } } },
    })
    if opts.tailoring ~= false then
        H.profession(env, "Портняжное дело", 225, 225, {
            H.recipe { id = 1229504, name = "Знамя фракции", output = BANNER,
                       learned = true,
                       reagents = { { itemID = 2996, qty = 1 }, { itemID = 2320, qty = 1 } } },
        })
    end

    -- Второй персонаж: чужой кеш знает его класс, уровень и профессии. Ровно
    -- так аддон видит чернокнижника, пока играют магом.
    if opts.alt ~= false then
        env.foreignDB = env.foreignDB or {}
        env.foreignDB.chars = {
            ["Player-6946-01187A42"] = {
                name = "Гендольф", surname = "Белыйй", level = 20,
                class = "Чернокнижник", classFile = "WARLOCK",
                realm = "CAMWOW EU5 Realm 4 PvP", faction = "Horde",
                professions = {
                    { name = "Alchemy", skill = 225, max = 225 },
                    { name = "Engineering", skill = 225, max = 225 },
                },
            },
        }
    end

    H.itemsChanged(env)
    H.rescan(env)
    return env
end

local function campCards(env)
    local ns = env.ns
    local cards = H.build(env)
    local out = {}
    for _, c in ipairs(cards) do
        if c.kind == ns.KIND.CAMP then out[#out + 1] = c end
    end
    return out, cards
end

local function byKeyPrefix(cards, prefix)
    for _, c in ipairs(cards) do
        if tostring(c.key):sub(1, #prefix) == prefix then return c end
    end
    return nil
end

-- 0. ДАННЫЕ -------------------------------------------------------------

H.suite("Лагерь: данные на месте и сверены между двумя базами")
do
    local env = campEnv()
    local ns = env.ns
    H.ok(ns.CampData ~= nil, "Data/Camp.lua загружен")
    H.ok(ns.CampAdvisor ~= nil, "модуль лагеря есть")
    local data = ns.CampData
    H.eq(#data.OBJECTS, 38, "объектов лагеря: 38")
    H.eq(#data.PROFESSIONS, 12, "профессий: 12")
    H.eq(data.TIER1_COUNT, 12, "и у каждой профессии ровно один предмет первого тира")

    -- У каждой записи есть всё, на чём держится совет.
    local bad = {}
    for _, row in ipairs(data.OBJECTS) do
        if not (row.item and row.prof and row.tier and row.skill
                and type(row.reag) == "table" and #row.reag > 0
                and type(row.gain) == "table" and row.gain.kind) then
            bad[#bad + 1] = tostring(row.en)
        end
        if row.tier > 1 and not row.bp then bad[#bad + 1] = tostring(row.en) .. " (без чертежа)" end
        if row.tier == 1 and row.bp then bad[#bad + 1] = tostring(row.en) .. " (чертёж у первого тира)" end
    end
    H.eq(#bad, 0, "ни одной неполной записи"
        .. ((#bad > 0) and ("  <- " .. table.concat(bad, ", ")) or ""))

    -- Происхождение и достоверность названы: это требование проекта к данным,
    -- взятым из чужого аддона.
    H.ok(type(data.PROVENANCE) == "table" and data.PROVENANCE.skills ~= nil,
        "в шапке сказано, откуда пороги")
    H.ok(ns.Util.contains(tostring(data.PROVENANCE.objects), "Mastercraft"),
        "и названо, из какого аддона взята таблица: "
        .. tostring(data.PROVENANCE.objects))
    H.ok(ns.Util.contains(tostring(data.PROVENANCE.api), "нет ни одной функции"),
        "и что про лагерь в клиенте нет функций")
    H.eq(data.CONFIDENCE.PLACED, "UNKNOWN",
        "а «что уже стоит в лагере» помечено как неизвестное")
    H.eq(data.CONFIDENCE.EFFECTS, "ESTIMATE",
        "описание эффекта - оценка: источник один и классификация наша")

    -- Каждый вид бонуса умеет назваться по-русски, и ни один не остался
    -- безымянным: иначе в столбце выгоды стоял бы пустой текст.
    local noText = {}
    for _, row in ipairs(data.OBJECTS) do
        local text = ns.CampAdvisor:GainText(row)
        if type(text) ~= "string" or text == "" then
            noText[#noText + 1] = tostring(row.en)
        end
    end
    H.eq(#noText, 0, "у каждого объекта есть русский текст бонуса"
        .. ((#noText > 0) and ("  <- " .. table.concat(noText, ", ")) or ""))
end

H.suite("Лагерь: в разделе «откуда данные» у него своя строка")
do
    local env = campEnv()
    local ns = env.ns
    local row
    for _, r in ipairs(ns.Provenance:Rows()) do
        if r.key == "camp" then row = r end
    end
    H.ok(row ~= nil, "строка про лагерь в сводке источников есть")
    if row then
        H.ok(ns.Util.contains(row.label, "агер"), "названа по-человечески: " .. row.label)
        H.eq(row.conf, ns.CONF.ESTIMATE,
            "и достоверность не выше оценки: вид бонуса выведен нами")
        local text = ns.Provenance:RowText(row)
        H.ok(ns.Util.contains(text, "38"), "сказано, сколько предметов: "
            .. ns.Util.truncate(text, 120))
        H.ok(ns.Util.contains(text, "расходятся"),
            "сказано, что часть порогов расходится")
        H.ok(ns.Util.contains(text, "функций про лагерь в клиенте нет"),
            "и что про сам лагерь игра не говорит ничего")
    end
end

-- 1. ПОРОГИ ИЗ ДАННЫХ, И СПОР НАЗВАН -------------------------------------

H.suite("Лагерь: порог берётся из данных, а спор двух баз назван словами")
do
    local env = campEnv()
    local ns = env.ns
    local data = ns.CampData

    -- Два расхождения, которые есть в базах на диске. Если их «починить»
    -- одним числом, этот набор упадёт - и правильно: расхождение надо
    -- показывать, а не прятать.
    local disputed = {}
    for _, row in ipairs(data.OBJECTS) do
        local need, isDisputed, low, high = ns.CampAdvisor:Threshold(row)
        if isDisputed then
            disputed[#disputed + 1] = row.en
            H.eq(need, high, row.en .. ": берётся бо́льшее из двух (" .. low
                .. " и " .. high .. ")")
        else
            H.eq(need, tonumber(row.skill), row.en .. ": порог как в данных")
        end
    end
    table.sort(disputed)
    H.eq(#disputed, 2, "спорных порогов ровно два: " .. table.concat(disputed, ", "))

    -- И ПОРОГОВ НЕТ В КОДЕ ВОВСЕ. Проверка лексическая, по тексту файла без
    -- комментариев и строк: число порога, вписанное в код, через месяц станет
    -- ложью - Blizzard уже меняла их хотфиксом. Единица и двадцатка в этот
    -- список не входят только потому, что это обычные числа кода (list[1],
    -- math.min), а остальные пороги ни в одном вычислении не встречаются.
    do
        local f = assert(io.open(ROOT .. "/Logic/CampAdvisor.lua", "rb"))
        local code = D.stripped(f:read("*a"))
        f:close()
        local hits = {}
        for _, n in ipairs({ 90, 125, 140, 200, 300 }) do
            if code:find("%f[%d]" .. n .. "%f[%D]") then hits[#hits + 1] = tostring(n) end
        end
        H.eq(#hits, 0, "ни одного порога навыка в коде ветки нет"
            .. ((#hits > 0) and ("  <- " .. table.concat(hits, ", ")) or ""))
    end

    -- И порог приходит ИЗ ДАННЫХ, а не из кода: меняем данные - меняется ответ.
    local row = data.BY_ITEM[FISH_BOWL]
    local savedA, savedB = row.skill, row.skillWT
    row.skill, row.skillWT = 300, 300
    local snap = ns.CharacterScanner:Get()
    local d = ns.CampAdvisor:Describe(row, snap, {}, true)
    H.eq(d.need, 300, "подняли порог в данных - ветка видит 300")
    H.eq(d.canHere, false, "и аквариум перестал быть доступным при навыке 225")
    row.skill, row.skillWT = savedA, savedB
    local back = ns.CampAdvisor:Describe(row, snap, {}, true)
    H.eq(back.need, 20, "вернули данные - вернулся и порог")

    -- Спорный порог виден на карточке. Костёр - ровно тот случай: 1 против 20.
    local cards = campCards(env)
    local fire = byKeyPrefix(cards, "camp:fire:")
    H.ok(fire ~= nil, "карточка про костёр есть")
    if fire then
        H.ok(ns.Util.contains(fire.why, "порог спорный")
             or ns.Util.contains(fire.why, "Порог спорный"),
            "и в ней сказано, что порог спорный: " .. ns.Util.truncate(fire.why, 160))
        H.ok(ns.Util.contains(fire.why, "1") and ns.Util.contains(fire.why, "20"),
            "с оба́ими числами")
        H.eq(fire.conf, ns.CONF.ESTIMATE,
            "и достоверность у такой карточки опущена до оценки")
    end
end

-- 2. СЧЁТ ПО ОБОИМ ПЕРСОНАЖАМ -------------------------------------------

H.suite("Лагерь: 7 из 12 - это счёт по ДВУМ персонажам, а не по одному")
do
    local both = campEnv()
    local ns = both.ns
    local plan = ns.CampAdvisor:Plan(ns.CharacterScanner:Get())
    H.ok(plan ~= nil, "план построен")
    H.eq(plan.total, 12, "всего предметов первого тира: 12")
    H.eq(plan.covered, 5,
        "у этого персонажа закрыто 5 (рыбалка, кулинария, портняжка + алхимия и"
        .. " инженерное дело со второго персонажа) - считается именно 5?")
    -- Числа проверяются обоими концами: без второго персонажа их меньше.
    local alone = campEnv { alt = false }
    local plan2 = alone.ns.CampAdvisor:Plan(alone.ns.CharacterScanner:Get())
    H.eq(plan2.covered, 3, "без второго персонажа закрыто только 3")
    H.ok(plan.covered > plan2.covered,
        "значит второй персонаж и правда расширяет ответ: " .. plan.covered
        .. " против " .. plan2.covered)
    -- Чего нет ни у кого - названо, и по-русски.
    H.ok(#plan.uncovered > 0, "и сказано, каких профессий нет ни у кого: "
        .. table.concat(plan.uncovered, ", "))
    local latin = {}
    for _, name in ipairs(plan.uncovered) do
        if name:find("%a") and not name:find("[\208\209]") then latin[#latin + 1] = name end
    end
    H.eq(#latin, 0, "ни одного английского имени профессии в этом списке"
        .. ((#latin > 0) and ("  <- " .. table.concat(latin, ", ")) or ""))
end

-- 3. ВЫУЧЕН ЛИ РЕЦЕПТ ----------------------------------------------------

H.suite("Лагерь: «выучен» спрашивается у книги рецептов, а не угадывается")
do
    local env = campEnv()
    local ns = env.ns
    local snap = ns.CharacterScanner:Get()
    local index = ns.Roster:ProfessionIndex()

    local bowl = ns.CampAdvisor:Describe(ns.CampData.BY_ITEM[FISH_BOWL], snap, index, true)
    H.eq(bowl.recipeState, "learned", "аквариум: рецепт выучен")
    H.eq(bowl.learned, true, "и это тот же ответ полем learned")

    local journey = ns.CampAdvisor:Describe(ns.CampData.BY_ITEM[JOURNEY_FIRE], snap, index, true)
    H.eq(journey.recipeState, "missing", "костёр подмастерья: рецепт не выучен")

    -- Профессия, по которой книги нет вовсе: «не выучен» было бы неправдой.
    local noBook = ns.CampAdvisor:Describe(ns.CampData.BY_ITEM[MANA_WELL], snap, index, true)
    H.eq(noBook.recipeState, "no-book",
        "алхимия: рецептов этой профессии у меня нет - и это НЕ «не выучен»")

    -- Карточка «сделать» появляется только на выученном.
    local cards = campCards(env)
    local make = byKeyPrefix(cards, "camp:make:")
    H.ok(make ~= nil, "карточка «сделать» есть")
    if make then
        H.eq(make.itemID, FISH_BOWL, "и это аквариум - выученный рецепт")
        H.ok(ns.Util.contains(make.why, "выучен"),
            "в ней сказано, что рецепт выучен: " .. ns.Util.truncate(make.why, 140))
    end

    -- А если рецепт не выучен - карточки «сделать» по нему нет вовсе.
    local unlearned = campEnv { fishBowlLearned = false }
    local cards2 = campCards(unlearned)
    for _, c in ipairs(cards2) do
        if tostring(c.key):sub(1, 10) == "camp:make:" then
            H.ok(c.itemID ~= FISH_BOWL,
                "невыученный аквариум в «сделать» не попал")
        end
    end
end

-- 3б. ГОТОВОЕ В СУМКАХ - ЭТО «ПОСТАВЬ», А НЕ «СДЕЛАЙ» --------------------
--
-- Живая жалоба (маг 31 ур., 2026-11-21): первой карточкой списка стояло
-- «Сделать для лагеря: Аквариум» с ценой материалов при 32 аквариумах в
-- сумках, рядом - «Сделать костёр» при шести наборах для костра.

H.suite("Лагерь: готовый предмет в сумках — «поставить», а не «сделать»")
do
    local env = campEnv()
    local ns = env.ns
    env.bags[FISH_BOWL] = 32
    env.bags[BASIC_FIRE] = 6
    H.itemsChanged(env)
    local cards = campCards(env)
    local place = byKeyPrefix(cards, "camp:place:" .. FISH_BOWL)
    H.ok(place ~= nil, "карточка «поставить аквариум» есть")
    if place then
        H.ok(ns.Util.contains(place.title, "Поставить у костра"),
            "заголовок говорит «поставить»: " .. tostring(place.title))
        H.ok(ns.Util.contains(place.why, "32"),
            "и сколько их лежит: " .. ns.Util.truncate(place.why, 160))
        H.eq(place.cost, nil, "цены материалов на ней нет: покупать нечего")
    end
    local fire = byKeyPrefix(cards, "camp:place:" .. BASIC_FIRE)
    H.ok(fire ~= nil, "карточка «разжечь костёр» есть")
    if fire then
        H.ok(ns.Util.contains(fire.title, "Разжечь костёр"),
            "заголовок говорит «разжечь»: " .. tostring(fire.title))
    end
    for _, c in ipairs(cards) do
        local key = tostring(c.key)
        if key == "camp:make:" .. FISH_BOWL or key == "camp:fire:" .. BASIC_FIRE then
            H.ok(false, "карточки «сделать» по лежащему в сумках предмету быть не должно: " .. key)
        end
    end
end

H.suite("Лагерь: предмета в сумках нет — совет «сделать» остаётся")
do
    local env = campEnv()
    local cards = campCards(env)
    H.ok(byKeyPrefix(cards, "camp:make:" .. FISH_BOWL) ~= nil,
        "без аквариума в сумках карточка «сделать» на месте")
    H.eq(byKeyPrefix(cards, "camp:place:" .. FISH_BOWL), nil,
        "а «поставить» нет: ставить нечего")
end

-- 3в. БАФФ ЛАГЕРЯ НА ИГРОКЕ - ОБЪЕКТ УЖЕ РАБОТАЕТ ------------------------
--
-- Что стоит у костра, игра не говорит. Но бонус объекта - бафф, и бафф
-- читается: если он на игроке, советовать поставить объект незачем.

local function auraWorld(env, list)
    env.G.C_UnitAuras = {
        GetAuraDataByIndex = function(unit, index, filter)
            local a = list[index]
            if not a then return nil end
            return { name = a.name, spellId = a.spellID }
        end,
    }
end

H.suite("Лагерь: бафф объекта уже на игроке — ставить его не советуем")
do
    local env = campEnv()
    local ns = env.ns
    env.bags[FISH_BOWL] = 32
    H.itemsChanged(env)
    -- 1255254 - один из номеров заклинания «Fish Bowl» (Data/Camp.lua).
    auraWorld(env, { { name = "Что-то рыбное", spellID = 1255254 } })
    local cards = campCards(env)
    for _, c in ipairs(cards) do
        H.ok(c.itemID ~= FISH_BOWL,
            "карточки про аквариум нет: " .. tostring(c.key))
    end
    local said = false
    for _, c in ipairs(cards) do
        if ns.Util.contains(c.why or "", "Уже действует на вас: Аквариум") then said = true end
    end
    H.ok(said or ns.Util.contains(ns.ActionEngine.branchNote.camp or "", "Аквариум"),
        "и сказано словами, что аквариум уже действует")
    H.ok((ns.Diag:Init().counters["camp.effectAlreadyActive"] or 0) >= 1,
        "в диагностике это посчитано")
    local active = ns.CampAdvisor:ActiveEffects(ns.CharacterScanner:Get())
    H.ok(active[FISH_BOWL] ~= nil, "ActiveEffects называет аквариум")
end

H.suite("Лагерь: бафф без номера узнаётся по имени предмета")
do
    -- Старый путь чтения баффов номер отдаёт не всегда: тогда сравнение идёт
    -- по имени - бафф назван в точности как предмет лагеря.
    local env = campEnv()
    local ns = env.ns
    auraWorld(env, { { name = "Аквариум" } })
    H.build(env)
    local active = ns.CampAdvisor:ActiveEffects(ns.CharacterScanner:Get())
    H.ok(active[FISH_BOWL] ~= nil, "аквариум узнан по имени")
end

H.suite("Лагерь: посторонний бафф ничего не отменяет")
do
    local env = campEnv()
    local ns = env.ns
    auraWorld(env, { { name = "Чародейский интеллект", spellID = 1459 } })
    local cards = campCards(env)
    H.ok(byKeyPrefix(cards, "camp:make:" .. FISH_BOWL) ~= nil,
        "совет про аквариум на месте")
    local active = ns.CampAdvisor:ActiveEffects(ns.CharacterScanner:Get())
    H.eq(next(active), nil, "и действующих объектов лагеря не найдено")
end

H.suite("Лагерь: номера заклинаний есть у всех 38 объектов")
do
    local env = campEnv()
    local data = env.ns.CampData
    local missing = 0
    for _, row in ipairs(data.OBJECTS) do
        local list = data.EFFECT_SPELLS[row.item]
        if not (type(list) == "table" and #list >= 2) then missing = missing + 1 end
    end
    H.eq(missing, 0, "у каждого объекта минимум два номера: рецепт и установка")
    H.eq(data.ITEM_BY_SPELL[1255254], FISH_BOWL, "обратный индекс собран")
    H.eq(data.ITEM_BY_SPELL[818], nil, "классический костёр в индекс не попал")
end

-- 4. ЧЕРТЁЖ - ЭТО ПОКУПКА -----------------------------------------------

H.suite("Лагерь: чертёж - предмет, и совет про него - покупка")
do
    local env = campEnv()
    local ns = env.ns
    local cards = campCards(env)
    local bp = byKeyPrefix(cards, "camp:blueprint:")
    H.ok(bp ~= nil, "карточка про чертёж есть")
    if bp then
        H.eq(bp.itemID, JOURNEY_BP, "карточка ведёт к самому ЧЕРТЕЖУ, а не к объекту")
        H.eq(bp.action.kind, "shop", "и действие - поиск на аукционе")
        H.eq(bp.action.itemID, JOURNEY_BP, "по номеру чертежа")
        H.ok(ns.Util.contains(bp.why, "Рецепт не выучен"),
            "сказано, что рецепт не выучен: " .. ns.Util.truncate(bp.why, 160))
        H.ok(ns.Util.contains(bp.why, ns.Util.money(157095)),
            "и цена чертежа с аукциона: " .. ns.Util.money(157095))
        -- Сравнение «мест станет больше» - из данных, двумя числами.
        H.ok(ns.Util.contains(bp.why, "5") and ns.Util.contains(bp.why, "3"),
            "и сказано, сколько мест станет вместо скольких")
        H.ok((tonumber(bp.cost) or 0) > 157095,
            "в цену совета входит и чертёж, и материалы: " .. ns.Util.money(bp.cost))
    end
end

-- 5. API ЛАГЕРЯ НЕТ, И ЭТО СКАЗАНО --------------------------------------

H.suite("Лагерь: функций про лагерь нет, и ограничение сказано игроку")
do
    local env = campEnv()
    local ns = env.ns
    local cards = campCards(env)
    H.ok(#cards > 0, "карточки лагеря есть: " .. #cards)

    -- Короткая форма - в строке «что делать», она видна всегда.
    local said = 0
    for _, c in ipairs(cards) do
        if ns.Util.contains(c.need or "", "игра мне не говорит") then said = said + 1 end
    end
    H.ok(said > 0, "про «что в лагере уже стоит» сказано на карточках: " .. said)

    -- Полная - в подсказке, и там же про класс.
    local tip
    for _, c in ipairs(cards) do tip = tip or c.tipNote end
    H.ok(tip ~= nil, "под курсором есть подробное объяснение")
    if tip then
        H.ok(ns.Util.contains(tip, "ни одной функции"),
            "в нём сказано, что функций про лагерь нет: " .. ns.Util.truncate(tip, 200))
        H.ok(ns.Util.contains(tip, "откат"), "и про откат тоже")
        H.ok(ns.Util.contains(tip, "не проверял"),
            "и про баффы класса сказано, что не проверял")
    end

    -- И НИ ОДНА КАРТОЧКА НЕ УТВЕРЖДАЕТ НЕДОКАЗАННОГО. В данных на диске про
    -- сложение с классовыми баффами нет ничего, значит утверждать нельзя ни
    -- «складывается», ни «не складывается».
    local claims = {}
    for _, c in ipairs(cards) do
        local text = table.concat({ tostring(c.title), tostring(c.benefit),
                                    tostring(c.why), tostring(c.need) }, " ")
        if ns.Util.contains(text, "не складыва") or ns.Util.contains(text, "складывается с") then
            claims[#claims + 1] = tostring(c.title)
        end
    end
    H.eq(#claims, 0, "ни одна карточка не утверждает, складывается бафф или нет"
        .. ((#claims > 0) and ("  <- " .. table.concat(claims, ", ")) or ""))

    -- А в коде аддона нет ни одного обращения к «API лагеря» - ни того, которого
    -- не существует, ни древнего события выхода из игры, которое легко принять
    -- за лагерь.
    local forbidden = { "C_Camping", "C_Camp%f[^%w_]", "PLAYER_CAMPING",
                        "CAMP_CHANGED", "C_CampingUI" }
    local found = {}
    for _, rel in ipairs(assert(D.tocFiles(ROOT))) do
        local f = assert(io.open(ROOT .. "/" .. rel, "rb"))
        local code = D.stripped(f:read("*a"))
        f:close()
        for _, pattern in ipairs(forbidden) do
            if code:find(pattern) then
                found[#found + 1] = rel .. ": " .. pattern
            end
        end
    end
    H.eq(#found, 0, "ни одного обращения к функциям лагеря в коде нет"
        .. ((#found > 0) and ("  <- " .. table.concat(found, "; ")) or ""))
end

-- 6. ПОРОГ МЕЛКОЙ ДЕНЕЖНОЙ ВЫГОДЫ ЛАГЕРЯ НЕ КАСАЕТСЯ ---------------------

H.suite("Лагерь: порог мелкой денежной выгоды его не трогает")
do
    local env = campEnv()
    local ns = env.ns
    H.eq(ns.MONEY_FLOOR_KINDS[ns.KIND.CAMP], nil,
        "лагеря нет в перечне денежных видов: его выгода не в золоте")

    local before = campCards(env)
    H.ok(#before > 0, "до порога карточек лагеря: " .. #before)
    -- Ни одна не притворяется денежной: иначе перечень денежных видов обязан
    -- был бы её включить (это правило держит Tests/test_vanish.lua).
    for _, c in ipairs(before) do
        H.ok(c.benefitKind ~= "gold",
            "карточка «" .. ns.Util.truncate(c.title, 40) .. "» не денежная")
    end

    ns.Config:SetMoneyFloorMode(ns.MONEY_FLOOR_MODE.FIXED)
    ns.Config:SetMoneyFloorOwn(300000)   -- 30 золотых, то самое число игрока
    local after = campCards(env)
    H.eq(#after, #before,
        "при пороге 30з советы про лагерь остались все: " .. #after)
    ns.Config:SetMoneyFloorMode(ns.MONEY_FLOOR_MODE.OFF)
end

-- 7. ПРОПАЖА ОБЪЯВЛЯЕТСЯ ------------------------------------------------

H.suite("Лагерь: ветка без карточек говорит, почему")
do
    -- Ни одной профессии лагеря: ни у кого ничего.
    local env = H.load()
    env.player.factionFile = "Horde"
    H.itemsChanged(env)
    H.rescan(env)
    local cards, all = campCards(env)
    H.eq(#cards, 0, "у персонажа без профессий карточек лагеря нет")
    local note = env.ns.ActionEngine.branchNote.camp
    H.ok(type(note) == "string" and note ~= "",
        "и причина записана: " .. tostring(note))

    -- Имени предмета нет - карточки нет, и это сказано отдельной причиной.
    local nameless = campEnv()
    nameless.ns.Api.itemInfoCache = {}
    nameless.ns.Api.itemInfoMissed = {}
    nameless.items[FISH_BOWL] = nil
    nameless.items[BASIC_FIRE] = nil
    nameless.items[JOURNEY_FIRE] = nil
    nameless.items[JOURNEY_BP] = nil
    nameless.items[MANA_WELL] = nil
    nameless.items[BANNER] = nil
    H.itemsChanged(nameless)
    local cards2 = campCards(nameless)
    H.eq(#cards2, 0, "без имён предметов карточек нет: совет, который нельзя"
        .. " прочитать, не совет")
    local note2 = nameless.ns.ActionEngine.branchNote.camp
    H.ok(type(note2) == "string" and note2:find("им") ~= nil,
        "и причина - про имена: " .. tostring(note2))
end

-- 7a. МИР БЕЗ ЦЕН: СОВЕТ ОСТАЁТСЯ, А ЧИСЛА НАЗВАНЫ НЕИЗВЕСТНЫМИ ---------

H.suite("Лагерь: без цен ветка не падает и ничего не выдумывает")
do
    local env = campEnv { noPrices = true }
    local ns = env.ns
    -- Главное здесь - что пересчёт вообще случился: склейка фраз получала nil
    -- там, где цены нет, и роняла ВЕСЬ пересчёт, а не одну карточку.
    local ok, err = pcall(function() return campCards(env) end)
    H.ok(ok, "пересчёт без цен не падает" .. (ok and "" or ("  <- " .. tostring(err))))
    if not ok then return end
    local cards = campCards(env)
    H.ok(#cards > 0, "и советы про лагерь остались: " .. #cards)
    for _, c in ipairs(cards) do
        -- Ни одного «0м» и ни одной выдуманной цены: где числа нет, его нет.
        H.ok(not ns.Util.contains(c.why or "", "Материалы: 0м"),
            "ноль не выдаётся за цену")
        H.ok(not ns.Util.contains(c.why or "", "аукционе — ?"),
            "и знак вопроса не выдаётся за цену: "
            .. ns.Util.truncate(c.why or "", 120))
    end
    -- И склейка фраз терпит отсутствие куска: это та самая строка, которая
    -- роняла пересчёт.
    H.eq(ns.ActionEngine.JoinSentences("Первая фраза.", nil), "Первая фраза.",
        "приписывать нечего - строка остаётся как была")
    H.eq(ns.ActionEngine.JoinSentences(nil, "Вторая."), "Вторая.",
        "а если не было первой - остаётся вторая")
end

-- 8. ЦЕНА РАБОТЫ - ВЫЗОВАМИ, А НЕ МИЛЛИСЕКУНДАМИ ------------------------

H.suite("Лагерь: цена пересчёта измерена вызовами")
do
    local env = campEnv()
    local ns = env.ns
    local snap = ns.CharacterScanner:Get()

    -- Сколько вопросов о цене задаёт ПЛАН целиком.
    local realBuy = ns.PriceProvider.Buy
    local calls = 0
    ns.PriceProvider.Buy = function(self, ...)
        calls = calls + 1
        return realBuy(self, ...)
    end
    ns.PriceProvider:BeginPass()
    ns.CampAdvisor:Plan(snap)
    local planCalls = calls

    -- И сколько задаёт дешёвый разбор одного объекта: ни одного.
    calls = 0
    ns.PriceProvider:BeginPass()
    for _, row in ipairs(ns.CampData.OBJECTS) do
        ns.CampAdvisor:Describe(row, snap, {}, true)
    end
    local cheapCalls = calls
    ns.PriceProvider.Buy = realBuy

    H.eq(cheapCalls, 0,
        "дешёвый разбор всех 38 объектов не спрашивает цен вовсе")
    H.ok(planCalls <= 40, "план спрашивает цену " .. planCalls
        .. " раз за пересчёт (предел 40; полный разбор всех 38 объектов стоил бы"
        .. " около 170)")
    print("     вопросов о цене за пересчёт: " .. planCalls
        .. ", дешёвый разбор всех 38 объектов: " .. cheapCalls)

    -- Сколько раз собирается индекс профессий аккаунта: один на план.
    local realIndex = ns.Roster.ProfessionIndex
    local indexCalls = 0
    ns.Roster.ProfessionIndex = function(self, ...)
        indexCalls = indexCalls + 1
        return realIndex(self, ...)
    end
    ns.CampAdvisor:Plan(snap)
    ns.Roster.ProfessionIndex = realIndex
    H.eq(indexCalls, 1, "индекс профессий собирается один раз на весь план,"
        .. " а не на каждый из 38 объектов")
end

-- 9. ДРУГОЙ ПЕРСОНАЖ ----------------------------------------------------

H.suite("Лагерь: что здесь не сделать, а другой персонаж сделает")
do
    local env = campEnv()
    local ns = env.ns
    local cards = campCards(env)
    local other = byKeyPrefix(cards, "camp:other:")
    H.ok(other ~= nil, "карточка про другого персонажа есть")
    if other then
        H.ok(ns.Util.contains(other.title, "Белыйй"),
            "в заголовке - фамилия, которой он отличается от второго Гендольфа: "
            .. other.title)
        H.ok(ns.Util.contains(other.why, "225"), "и навык того персонажа")
        H.ok(ns.Util.contains(other.why, "Чернокнижник"), "и его класс словом")
        H.ok(ns.Util.contains(other.why, "не видно"),
            "и честно сказано, чего про него не видно: "
            .. ns.Util.truncate(other.why, 170))
        H.ok(ns.Util.contains(other.need, "почтой"), "и что делать: " .. other.need)
        H.ok(ns.Util.contains(other.need, "не управляю"),
            "и что аддон сам ничего не пересылает")
    end
end

-- 10. ФРАКЦИЯ -----------------------------------------------------------

H.suite("Лагерь: знамя чужой фракции не советуется")
do
    local horde = campEnv()
    local ns = horde.ns
    local snap = ns.CharacterScanner:Get()
    local banner = ns.CampData.BY_ITEM[BANNER]
    H.eq(banner.faction, "Horde", "в данных у знамени стоит фракция")
    H.ok(ns.CampAdvisor:Describe(banner, snap, {}, true) ~= nil,
        "ордынцу знамя разбирается")

    local ally = campEnv { faction = "Alliance" }
    local snap2 = ally.ns.CharacterScanner:Get()
    H.eq(ally.ns.CampAdvisor:Describe(banner, snap2, {}, true), nil,
        "альянсовцу - нет: в данных лежит только ордынская версия, и подменить"
        .. " её нечем")
    local plan = ally.ns.CampAdvisor:Plan(snap2)
    for _, d in ipairs(plan.here) do
        H.ok(d.item ~= BANNER, "и в план она не попадает")
    end
end

-- 11. ЧТО ИГРОК ПРОЧИТАЕТ ----------------------------------------------

H.suite("Лагерь: лучший совет - тот, у которого в данных есть число")
do
    local env = campEnv()
    local ns = env.ns
    local cards = campCards(env)
    H.ok(#cards >= 3, "карточек лагеря: " .. #cards)
    local top = cards[1]
    -- Внутри ветки порядок задан пользой из данных, а не ценой: аквариум -
    -- единственный предмет первого тира, у которого в описании есть число.
    local best
    for _, c in ipairs(cards) do
        if (not best) or (c.score or 0) > (best.score or 0) then best = c end
    end
    H.eq(best.itemID, FISH_BOWL,
        "самый высокий совет лагеря - аквариум: +8% ко всем характеристикам")
    H.ok(ns.Util.contains(best.benefit, "8%"),
        "и число из данных стоит в столбце выгоды: " .. tostring(best.benefit))
    H.ok(ns.Util.contains(best.why, "7 из 12") or ns.Util.contains(best.why, "5 из 12"),
        "а в строке «почему» сказано, сколько предметов закрывают профессии: "
        .. ns.Util.truncate(best.why, 140))
    -- Цена материалов и цена готового - рядом, числами.
    H.ok(ns.Util.contains(best.why, "Материалы"), "и чего это стоит")
    H.ok(ns.Util.contains(best.why, "аукционе"),
        "и сколько просят за готовый - объекты лагеря торгуются")
    -- «Материалы: 0м» не бывает: ноль - это «всё есть в сумках».
    for _, c in ipairs(cards) do
        H.ok(not ns.Util.contains(c.why or "", "Материалы: 0м"),
            "ноль не печатается ценой")
    end
end

end
