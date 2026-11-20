-- ForeverPilot / Tests/test_sources.lua
--
-- ЧЕСТНОСТЬ ПРО ИСТОЧНИКИ И ПРО ВОЗРАСТ ЦЕН.
--
-- Аддон сшит из пяти источников с разной надёжностью, и пользователь не
-- технический: спрашивать его «а Auctionator у вас сканировал?» бессмысленно.
-- Значит, ответ должен быть собран целиком и в одном месте.
--
-- И отдельный, более узкий контракт - ВОЗРАСТ ЦЕНЫ. Auctionator отдаёт его в
-- ДНЯХ (его GetPriceAge это GetScanDay() минус последний день наблюдения), а
-- адаптер считал это число секундами. Следствия были два, и оба тихие:
--   * цена двухдневной давности печаталась как «2 минуты назад»;
--   * устаревшей она не становилась НИКОГДА - порог 172800 секунд против
--     числа вроде 2.
-- То есть обещание «цены старше суток помечаются» не выполнялось вообще, при
-- том что механизм пометки работал исправно.
local H = ...

return function()

-- ПРОВЕРЯЕТСЯ ПРОИЗВОДСТВЕННЫЙ ЧИТАТЕЛЬ, А НЕ ФЕЙК.
--
-- Это важнее, чем выглядит. Харнесс подменяет Api:ReadAuctionPrice целиком, то
-- есть перевод дней в секунды - ту самую строчку, из-за которой цена
-- двухдневной давности печаталась как «2 минуты назад», - в тестах НЕ
-- выполняется. Проверка, написанная поверх фейка, проверяла фейк: мутация
-- «возраст снова считается секундами» проходила мимо неё незамеченной.
--
-- Поэтому здесь восстанавливается настоящий Api:ReadAuctionPrice (харнесс
-- хранит его в env.real), а подделывается то, что подделывает игра: глобальный
-- объект Auctionator с его публичным API. Возраст он отдаёт в ДНЯХ - так же,
-- как настоящий.
local function withRealAuctionReader(env, opts)
    local ns = env.ns
    ns.Api.ReadAuctionPrice = env.real.ReadAuctionPrice
    env.G.Auctionator = {
        API = { v1 = {
            GetAuctionPriceByItemID = function(_, itemID)
                return (opts.prices or {})[itemID]
            end,
            GetAuctionAgeByItemID = function(_, itemID)
                -- ДНИ, как у настоящего Auctionator.
                return (opts.ageDays or {})[itemID]
            end,
            IsAuctionDataExactByItemID = function() return true end,
        } },
    }
    ns.Api:ClearAuctionCache("тест: подменён читатель цен")
end

H.suite("Возраст цены: дни от Auctionator переводятся в секунды")
do
    local env = H.load()
    local ns = env.ns
    H.item(env, 500, { name = "Товар", sellPrice = 100 })
    H.itemsChanged(env)
    withRealAuctionReader(env, {
        prices = { [500] = 10000 },
        ageDays = { [500] = 2 },
    })

    local copper, conf, age, exact, ageDays = ns.Api:AuctionPrice(500)
    H.eq(copper, 10000, "цена прочитана производственным кодом")
    H.eq(ageDays, 2, "возраст в днях отдан отдельно")
    H.eq(age, 2 * 86400, "и переведён в секунды: 2 дня = 172800")
    H.eq(ns.Util.ageText(age), "2 дня назад",
        "и текст теперь правильный, а не «2 минуты назад»")
    H.eq(conf, ns.CONF.ESTIMATE,
        "двухдневная цена перестала считаться свежей: " .. tostring(conf))
end

H.suite("Возраст цены: порог «устарела» перешагивается днями, а не секундами")
do
    -- Та же проверка с другой стороны, и именно она ловит возврат к секундам:
    -- при возрасте в днях число 2 никогда не превысит порога 172800, то есть
    -- цена НИКОГДА не станет устаревшей. Это и был настоящий дефект.
    local env = H.load()
    local ns = env.ns
    H.item(env, 501, { name = "Товар", sellPrice = 100 })
    H.itemsChanged(env)
    withRealAuctionReader(env, {
        prices = { [501] = 10000 },
        ageDays = { [501] = 7 },
    })
    local _, conf, age = ns.Api:AuctionPrice(501)
    H.ok(age >= ns.PRICE_STALE_SECONDS, string.format(
        "недельная цена перешагнула порог устаревания: %s >= %s",
        tostring(age), tostring(ns.PRICE_STALE_SECONDS)))
    H.eq(conf, ns.CONF.ESTIMATE, "и достоверность опущена до оценки")

    -- А свежая - не перешагивает.
    H.item(env, 502, { name = "Товар", sellPrice = 100 })
    H.itemsChanged(env)
    withRealAuctionReader(env, {
        prices = { [502] = 10000 },
        ageDays = { [502] = 0 },
    })
    local _, conf0, age0 = ns.Api:AuctionPrice(502)
    H.eq(age0, 0, "сегодняшняя цена: возраст 0")
    H.ok(conf0 ~= ns.CONF.ESTIMATE,
        "и она не помечена оценкой: " .. tostring(conf0))
end

H.suite("Возраст цены: суточная цена помечается, а сегодняшняя — нет")
do
    local env = H.load()
    local ns = env.ns
    env.auctionator = true
    H.item(env, 501, { name = "Товар", sellPrice = 100 })
    env.prices[501] = 10000

    env.priceAgeDays = 0
    ns.Api:ClearAuctionCache("тест")
    local _, conf0, age0 = ns.Api:AuctionPrice(501)
    H.eq(age0, 0, "сегодняшняя цена: возраст 0")
    H.ok(conf0 ~= ns.CONF.ESTIMATE, "и она не помечена оценкой: " .. tostring(conf0))

    env.priceAgeDays = 1
    ns.Api:ClearAuctionCache("тест")
    local _, _, age1 = ns.Api:AuctionPrice(501)
    H.eq(age1, 86400, "суточная цена: ровно сутки в секундах")
    H.ok(age1 >= ns.PRICE_AGE_SAY_SECONDS,
        "и она достигает порога «назвать возраст»")
end

H.suite("Возраст цены: карточка говорит о старой цене сама")
do
    local env = H.load()
    local ns = env.ns
    env.auctionator = true
    env.priceAgeDays = 3
    H.item(env, 510, { name = "Шёлковый пояс", equipLoc = "INVTYPE_WAIST",
        reqLevel = 20, classID = 4, subclassID = 1, sellPrice = 600 })
    H.item(env, 511, { name = "Шёлк", sellPrice = 100 })
    env.vendorPrices[511] = 300
    env.bags[511] = 20
    env.prices[510] = 30000
    env.prices[511] = 300
    H.profession(env, "Портняжное дело", 225, 225, {
        H.recipe { id = 5101, output = 510, name = "Шёлковый пояс",
                   diff = "trivial", category = "Пояса",
                   reagents = { { itemID = 511, qty = 3 } } },
    })
    H.itemsChanged(env)
    local cards = H.build(env)
    local c
    for _, card in ipairs(cards) do
        if card.kind == ns.KIND.CRAFT_PROFIT then c = card end
    end
    H.ok(c ~= nil, "карточка на продажу есть")
    if c then
        H.ok(ns.Util.contains(c.why, "не сегодняшняя")
             or ns.Util.contains(c.why, "дня назад"),
            "и в ней сказано, что цена старая: " .. ns.Util.truncate(c.why, 200))
        H.ok(ns.Util.contains(c.why, "аукцион"),
            "и предложено зайти на аукцион")
    end
end

-- ПАМЯТЬ ЦЕН ЗАБЫВАЕТСЯ НЕ ЧАЩЕ, ЧЕМ СКАНИРУЕТСЯ АУКЦИОН.
--
-- Забыть ответы Auctionator - значит на следующем пересчёте спросить его заново
-- про каждый предмет: на настоящих данных это 367 чтений и пик пересчёта. В
-- живом файле игрока память забывалась 108 раз за сессию, потому что её
-- сбрасывал каждый сигнал аукциона, а их 276 на одно сканирование. Здесь -
-- механика окна; цена в обращениях измеряется на настоящих данных
-- (Tests/test_real.lua).
H.suite("Память цен: буря сигналов забывает её один раз, и отложенное не теряется")
do
    local env = H.load()
    local ns = env.ns
    env.auctionator = true
    H.item(env, 530, { name = "Товар", sellPrice = 100 })
    env.prices[530] = 10000

    local function cleared()
        return (ns.Diag:Init().counters or {})["auction.cacheCleared"] or 0
    end
    local function deferred()
        return (ns.Diag:Init().counters or {})["auction.cacheClearDeferred"] or 0
    end

    -- Прямое требование (без ограничителя) проходит всегда: так зовут тесты,
    -- замеры и страховка по времени.
    ns.Api:AuctionPrice(530)
    local n0 = cleared()
    H.ok(ns.Api:ClearAuctionCache("тест: прямое требование") > 0,
        "прямое забывание проходит и что-то забывает")
    H.eq(cleared(), n0 + 1, "и оно посчитано")

    -- А сигнал аукциона - только если окно прошло. Окно считается от ЛЮБОГО
    -- забывания, включая прямое выше, поэтому время сдвигаем.
    H.clock = H.clock + (ns.AUCTION_RESCAN_GUARD or 60) + 1
    ns.Api:AuctionPrice(530)
    local n1, d1 = cleared(), deferred()
    H.ok(ns.Api:ClearAuctionCache("сигнал 1", true) >= 0, "первый сигнал проходит")
    H.eq(cleared(), n1 + 1, "первый сигнал забыл память")
    for i = 2, 10 do
        ns.Api:AuctionPrice(530)
        H.eq(ns.Api:ClearAuctionCache("сигнал " .. i, true), 0,
            "сигнал " .. i .. " память не забыл")
    end
    H.eq(cleared(), n1 + 1, "на десять сигналов - одно забывание")
    H.eq(deferred(), d1 + 9, "а девять отложены, и это видно в диагностике")
    H.ok(ns.Api.auctionClearPending ~= nil, "отложенное забывание помнится")

    -- ОТЛОЖЕННОЕ НЕ ТЕРЯЕТСЯ: окно прошло - следующий проход его выполняет,
    -- даже если нового сигнала не было.
    ns.Api:AuctionPrice(530)
    H.clock = H.clock + (ns.AUCTION_RESCAN_GUARD or 60) + 1
    local n2 = cleared()
    ns.Api:BeginPass()
    H.eq(cleared(), n2 + 1, "проход после истечения окна забыл память сам")
    H.eq(ns.Api.auctionClearPending, nil, "и отложенного больше нет")
end

H.suite("Свежесть цен: сводка по сессии")
do
    local env = H.load()
    local ns = env.ns
    env.auctionator = true
    H.item(env, 520, { name = "A", sellPrice = 10 })
    H.item(env, 521, { name = "B", sellPrice = 10 })
    env.prices[520] = 1000
    env.prices[521] = 2000

    ns.PriceProvider:BeginPass()
    env.priceAgeDays = 0
    ns.Api:ClearAuctionCache("тест")
    ns.PriceProvider:Buy(520)
    env.priceAgeDays = 4
    ns.Api:ClearAuctionCache("тест")
    ns.PriceProvider:Buy(521)

    local f = ns.PriceProvider:Freshness()
    H.ok(f ~= nil, "сводка свежести построена")
    if f then
        H.eq(f.priced, 2, "две цены получены")
        H.eq(f.staleCount, 1, "из них одна старая")
        H.eq(f.stale, true, "и сводка это говорит")
        H.eq(f.oldestDays, 4, "самой старой 4 дня")
        H.ok(ns.Util.contains(f.text, "не сегодняшние"),
            "словами: " .. tostring(f.text))
    end
end

H.suite("Свежесть цен: про старые цены говорится один раз за сессию")
do
    local env = H.load()
    local ns = env.ns
    local said = {}
    env.ns.Api.Print = function(_, msg) said[#said + 1] = msg end
    env.auctionator = true
    H.item(env, 530, { name = "A", sellPrice = 10 })
    env.prices[530] = 1000
    ns.PriceProvider:BeginPass()
    env.priceAgeDays = 5
    ns.PriceProvider:Buy(530)

    H.eq(ns.Notifier:CheckStalePrices(), 1, "сказано")
    H.eq(ns.Notifier:CheckStalePrices(), 0, "и повторно — нет")
    H.ok(#said == 1 and ns.Util.contains(said[1], "аукцион"),
        "в сообщении есть, что делать: " .. ns.Util.truncate(said[1] or "", 140))
end

H.suite("Свежесть цен: сообщение выключаемо")
do
    local env = H.load()
    local ns = env.ns
    local said = {}
    env.ns.Api.Print = function(_, msg) said[#said + 1] = msg end
    env.auctionator = true
    H.item(env, 540, { name = "A", sellPrice = 10 })
    env.prices[540] = 1000
    ns.PriceProvider:BeginPass()
    env.priceAgeDays = 5
    ns.PriceProvider:Buy(540)
    ns.Config:Get().notify.stalePrices = false
    H.eq(ns.Notifier:CheckStalePrices(), 0, "выключено — молчит")
    H.eq(#said, 0, "и в чат ничего не ушло")
end

-- =====================================================================
-- Источники в одном месте
-- =====================================================================

H.suite("Источники: сводка собирается и называет все пять")
do
    local env = H.load()
    local ns = env.ns
    H.rescan(env)
    local rows = ns.Provenance:Rows()
    H.ok(rows ~= nil and #rows >= 5, "строк не меньше пяти: " .. #rows)

    local byKey = {}
    for _, r in ipairs(rows) do byKey[r.key] = r end
    for _, key in ipairs({ "character", "prices", "itemStats", "places", "priceHistory" }) do
        local r = byKey[key]
        H.ok(r ~= nil, "строка «" .. key .. "» есть")
        if r then
            H.ok(r.label and r.label ~= "", key .. ": название понятное человеку")
            H.ok(r.source and r.source ~= "", key .. ": источник назван — " .. r.source)
            H.ok(r.conf ~= nil, key .. ": достоверность названа — " .. tostring(r.conf))
            H.ok(r.fresh and r.fresh ~= "", key .. ": свежесть названа")
        end
    end
end

H.suite("Источники: про пустое не говорится, что оно не устаревает")
do
    -- ВОДА, НАЙДЕННАЯ НА ЭКРАНЕ «МОЙ ПЕРСОНАЖ».
    --
    -- Строка про места читалась так: «Свои записи не устаревают: NPC стоят на
    -- месте. Записанных мест пока нет.» Первая фраза - утверждение о сроке
    -- годности пустоты; игроку она не отвечает ни на что, а место на экране
    -- занимает. То же было у истории цен: «Наблюдений ещё нет. Суточных слепков
    -- цен ещё нет» - одно и то же дважды в одной строке.
    local env = H.load()
    local ns = env.ns
    H.rescan(env)
    local byKey = {}
    for _, r in ipairs(ns.Provenance:Rows()) do byKey[r.key] = r end

    -- Мест не записано ни одного: это состояние первого запуска.
    local places = ns.Places:Summary()
    H.eq(places.npcs or 0, 0, "предпосылка: записанных мест нет")
    local row = byKey.places
    H.ok(row ~= nil, "строка про места есть")
    if row then
        H.ok(row.fresh and row.fresh ~= "", "свежесть названа: " .. tostring(row.fresh))
        H.eq(ns.Util.contains(row.fresh, "не устаревают"), false,
            "и она не обещает, что пустые записи не устаревают: " .. tostring(row.fresh))
        local text = ns.Provenance:RowText(row)
        H.ok(ns.Util.contains(text, "записанных мест пока нет"),
            "а то, что записей нет, сказано: " .. ns.Util.truncate(text, 110))
        H.ok(ns.Util.contains(text, "зайдите к любому торговцу"),
            "и сказано, что сделать")
    end

    -- История цен пуста: одно «нет» на строку, а не два.
    local hist = byKey.priceHistory
    H.ok(hist ~= nil, "строка про историю цен есть")
    if hist then
        local text = ns.Provenance:RowText(hist)
        local Sense = assert(loadfile((H.ROOT or ".") .. "/Tests/sense.lua"))()
        H.eq(#Sense.deniesTwice(text), 0,
            "в одной строке не сказано дважды, что данных нет: "
            .. ns.Util.truncate(text, 140))
        H.ok(ns.Util.contains(text, "задним числом"),
            "а главное про историю цен осталось")
    end

    -- И когда записи ЕСТЬ, число их видно в той же графе свежести. Записывает
    -- их тот же путь, которым это происходит в игре: Places:RecordNpc.
    ns.Places:RecordNpc(777, "Торговец Кварц", "vendor")
    byKey = {}
    for _, r in ipairs(ns.Provenance:Rows()) do byKey[r.key] = r end
    local full = byKey.places
    H.ok(full and ns.Util.contains(full.fresh, "не устаревают"),
        "при непустых записях свежесть названа по-прежнему: " .. tostring(full and full.fresh))
    H.ok(full and full.fresh:find("%d"),
        "и в ней есть число записей: " .. tostring(full and full.fresh))
end

H.suite("Источники: персонаж — всегда свежий, цены — с возрастом")
do
    local env = H.load()
    local ns = env.ns
    env.auctionator = true
    H.rescan(env)
    local rows = ns.Provenance:Rows()
    local byKey = {}
    for _, r in ipairs(rows) do byKey[r.key] = r end

    H.ok(ns.Util.contains(byKey.character.fresh, "всегда"),
        "про персонажа сказано, что данные всегда свежие: "
        .. byKey.character.fresh)
    H.ok(ns.Util.contains(byKey.prices.detail, "отсканировали")
         or ns.Util.contains(byKey.prices.detail, "не загружен"),
        "про цены сказано главное ограничение: "
        .. ns.Util.truncate(byKey.prices.detail, 120))
    H.ok(ns.Util.contains(byKey.itemStats.detail, "клиент"),
        "про характеристики сказано, почему нужна внешняя база: "
        .. ns.Util.truncate(byKey.itemStats.detail, 120))
    H.ok(ns.Util.contains(byKey.priceHistory.detail, "задним числом"),
        "про историю цен сказано, что её не собрать назад")
end

-- ЗАВИСИМОСТЬ ОТ ВНЕШНЕЙ БАЗЫ НАЗВАНА ВСЛУХ.
--
-- В живом файле: C_Item.GetItemStats отвечает 786 раз, и ни одного школьного
-- урона в ответах нет - клиент на этом сервере отдаёт только базовые
-- характеристики. То есть сравнение вещей целиком держится на внешней базе
-- Polestar_ItemDB, и мешало это мало ровно потому, что база установлена. Пока
-- зависимость не названа - она невидимая: у игрока без этой базы будут те же
-- уверенные карточки, посчитанные по половине характеристик.
H.suite("Источники: сказано прямо, что без внешней базы сравнение вещей не работает")
do
    local env = H.load()
    local ns = env.ns
    H.rescan(env)
    local rows = ns.Provenance:Rows()
    local byKey = {}
    for _, r in ipairs(rows) do byKey[r.key] = r end
    local row = byKey.itemStats
    H.ok(row ~= nil, "строка про бонусы экипировки есть")
    if row then
        local text = ns.Provenance:RowText(row)
        print("     " .. text)
        H.ok(text:find("не работает", 1, true) ~= nil,
            "сказано, что без неё сравнение вещей не работает")
        H.ok(text:find("Polestar", 1, true) ~= nil, "и названо, что именно нужно")
        H.ok(text:find("базовые характеристики", 1, true) ~= nil,
            "и сказано, что отдаёт клиент")
    end
end

H.suite("Источники: отсутствующий источник помечен и сказано, что делать")
do
    local env = H.load()
    local ns = env.ns
    env.auctionator = false
    env.itemDBMirror = false
    env.foreignItemStats = {}
    env.foreignItemRecords = {}
    env.itemDBInstalled = false
    H.bindItemDB(env)
    H.rescan(env)

    local rows = ns.Provenance:Rows()
    local byKey = {}
    for _, r in ipairs(rows) do byKey[r.key] = r end
    H.eq(byKey.prices.conf, ns.CONF.UNKNOWN, "без Auctionator цены — неизвестно")
    H.ok(byKey.prices.action ~= nil and ns.Util.contains(byKey.prices.action, "Auctionator"),
        "и сказано, что делать: " .. tostring(byKey.prices.action))
    H.eq(byKey.itemStats.conf, ns.CONF.UNKNOWN, "без базы предметов — неизвестно")
    H.ok(byKey.itemStats.action ~= nil,
        "и тоже сказано, что делать: " .. tostring(byKey.itemStats.action))

    local head = ns.Provenance:Headline()
    H.ok(ns.Util.contains(head, "Не хватает"),
        "и итог одной строкой: " .. ns.Util.truncate(head, 150))
end

-- =====================================================================
-- СВЕРКА СПРАВОЧНИКА С ИГРОЙ: ЧТО ОНА ГОВОРИТ ТОМУ, ЧЬИХ ПРОФЕССИЙ В
-- СПРАВОЧНИКЕ НЕТ
-- =====================================================================
--
-- Живой файл игрока, второй персонаж: алхимия, инженерное дело, кулинария.
-- Справочник собран по портняжному делу и наложению чар, и сверка не состоялась
-- ни разу: modules.SourceCheck = { in = 0, out = 0, matched = 0 }. Две находки
-- из одного места:
--
--   1. причина была написана ПО-АНГЛИЙСКИ - «(Alchemy, Cooking, Engineering)» -
--      в русской фразе на русском клиенте. Английские имена подставляли мы
--      сами: они нужны для поиска по справочнику, и обратно их не перевели;
--   2. причина жила ТОЛЬКО в файле диагностики, то есть со стороны игрока
--      «сверять не с чем» было неотличимо от «всё сошлось».
--
-- Мир здесь - тот самый: профессии, которых справочник не знает, и имена из
-- клиента ruRU.
local function alchemistWorld()
    local env = H.load()
    local ns = env.ns
    env.professions = {}
    ns.RecipeBook.byProfession = {}
    H.item(env, 2447, { name = "Мироцвет", sellPrice = 1, stackCount = 20 })
    H.item(env, 118, { name = "Слабое исцеляющее зелье", sellPrice = 5, stackCount = 5 })
    H.profession(env, "Алхимия", 150, 150, {
        H.recipe { id = 2330, name = "Слабое исцеляющее зелье", output = 118,
                   outputQty = 1, reagents = { { itemID = 2447, qty = 1 } },
                   diff = "optimal" },
    })
    H.profession(env, "Инженерное дело", 150, 150, {})
    H.profession(env, "Кулинария", 150, 150, {})
    ns.RecipeBook:Reindex()
    H.build(env)
    ns.SourceCheck:RunStatic()
    return env
end

H.suite("Сверка: причина названа именами профессий из клиента, а не английскими")
do
    local env = alchemistWorld()
    local ns = env.ns
    local v = ns.SourceCheck:Verdict()

    H.ok(v.ran, "сверка запускалась")
    H.eq(v.compared, 0, "и сверять оказалось нечего")
    H.eq(v.covered, false, "справочник эти профессии не покрывает")
    H.eq(v.reasonCode, "SOURCE_NOT_COVERED",
        "у причины есть КОД, а не только свободный текст")
    -- И код доезжает до диагностики: без него Diag:Module ставит «FREETEXT» и
    -- считает это дефектом (counters.diag.reasonWithoutCode в живом файле был
    -- ровно про эту строку).
    local m = ns.Diag:Init().modules.SourceCheck
    H.ok(m ~= nil, "модуль сверки отчитался")
    if m then
        H.eq(m.reasonCode, "SOURCE_NOT_COVERED", "и в диагностике стоит тот же код")
        H.eq((ns.Diag:Init().counters or {})["diag.reasonWithoutCode"], nil,
            "свободного текста без кода больше нет")
    end

    local why = tostring(v.reason)
    print("     " .. why)
    for _, name in ipairs({ "Алхимия", "Инженерное дело", "Кулинария" }) do
        H.ok(why:find(name, 1, true) ~= nil,
            "в причине названа профессия «" .. name .. "»")
    end
    for _, name in ipairs({ "Alchemy", "Cooking", "Engineering" }) do
        H.ok(why:find(name, 1, true) == nil,
            "и английского «" .. name .. "» в причине нет")
    end
    -- И сказано, по чему справочник собран - тоже по-русски.
    H.ok(why:find("Портняжное дело", 1, true) ~= nil
         and why:find("Наложение чар", 1, true) ~= nil,
        "сказано, под какие профессии справочник собран: " .. why)
    H.ok(why:find("Tailoring", 1, true) == nil
         and why:find("Enchanting", 1, true) == nil,
        "и тоже без английских имён")

    -- Для поиска по справочнику имена по-прежнему английские: это внутренний
    -- список, и ломать его перевод нельзя - иначе сверка перестанет находить
    -- строки у портняжника.
    local internal = ns.SourceCheck:ProfessionsToCompare()
    local joined = table.concat(internal, ",")
    H.ok(joined:find("Alchemy", 1, true) ~= nil,
        "внутренний список для поиска по справочнику остался английским: " .. joined)
end

H.suite("Сверка: её результат виден игроку, а не только в диагностике")
do
    local env = alchemistWorld()
    local ns = env.ns
    local rows = ns.Provenance:Rows()
    local byKey = {}
    for _, r in ipairs(rows) do byKey[r.key] = r end

    local row = byKey.sourceCheck
    H.ok(row ~= nil, "в разделе «Откуда я всё это знаю» есть строка про справочник")
    if row then
        local text = ns.Provenance:RowText(row)
        print("     " .. tostring(row.label) .. ": " .. text)
        H.eq(row.conf, ns.CONF.ESTIMATE,
            "непроверенный справочник - это оценка, а не факт и не «неизвестно»")
        H.ok(text:find("не сверено", 1, true) ~= nil
             or text:find("сверки не было", 1, true) ~= nil,
            "сказано словами, что сверки не было")
        H.ok(text:find("Алхимия", 1, true) ~= nil,
            "и названы профессии игрока: " .. text)
        H.ok(text:find("Alchemy", 1, true) == nil, "без английских имён")
        -- Честно сказано, что справочник под эти профессии не пополняется.
        H.ok(text:find("не дополняю", 1, true) ~= nil,
            "и сказано, что справочник под эти профессии не дополняется")
    end

    -- Итог одной строкой не должен превращать это в «не хватает источника»:
    -- справочник есть и работает, непроверено согласие с игрой.
    local head = ns.Provenance:Headline()
    H.ok(head:find("справочник", 1, true) == nil
         and head:find("Справочник", 1, true) == nil,
        "в итоговой строке справочник не числится отсутствующим: " .. head)
end

H.suite("Сверка: справочник остаётся прежним — его никто не дополняет")
do
    -- Обещание «под ваши профессии я его не дополняю» - проверяемое:
    -- Data/ForeverSource.lua статический, и ни пересчёт, ни сверка в него не
    -- пишут. Считаем строки и покрытые профессии до и после.
    local env = alchemistWorld()
    local ns = env.ns
    local FS = ns.ForeverSource
    local function shape()
        local n, profs = 0, {}
        for _, ref in pairs(FS.RECIPE_REF) do
            n = n + 1
            if ref.prof then profs[ref.prof] = true end
        end
        local names = {}
        for name in pairs(profs) do names[#names + 1] = name end
        table.sort(names)
        return n, table.concat(names, ",")
    end
    local n1, p1 = shape()
    H.ok(n1 > 500, "строк в справочнике: " .. n1)
    H.eq(p1, "Enchanting,Tailoring", "и покрывает он две профессии: " .. p1)
    for _ = 1, 3 do
        H.build(env)
        ns.SourceCheck:RunStatic()
    end
    local n2, p2 = shape()
    H.eq(n2, n1, "после трёх пересчётов со сверкой строк столько же")
    H.eq(p2, p1, "и покрытие то же")
end

H.suite("Источники: сводка уходит в диагностику")
do
    local env = H.load()
    local ns = env.ns
    H.rescan(env)
    ns.Provenance:Report()
    H.ok(ns.Diag:Init().provenance ~= nil, "раздел provenance в файле есть")
    local m = ns.Diag:Init().modules.provenance
    H.ok(m ~= nil, "и модуль записан")
    if m then
        H.ok((m["in"] or 0) >= 5, "со числом источников: " .. tostring(m["in"]))
        H.ok(m.headline ~= nil, "и с итоговой строкой")
    end
end

end
