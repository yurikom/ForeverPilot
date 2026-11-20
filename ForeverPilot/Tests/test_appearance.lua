-- ForeverPilot / Tests/test_appearance.lua
--
-- ОБЛИК ВЕЩИ: ЕДИНСТВЕННАЯ НЕОТМЕНИМАЯ ОШИБКА ЭТОГО АДДОНА.
--
-- Непривязанная вещь необычного качества и выше, которую продали, отправили
-- почтой или распылили, из коллекции облика пропадает навсегда. Всё остальное,
-- что советует аддон, игрок может не делать или переделать; это - нет. А
-- советует он и продавать, и распылять, и пересылать.
--
-- ЧЕГО В ЭТОМ НАБОРЕ ПРИНЦИПИАЛЬНО НЕТ: настоящего ответа про облик. Офлайн
-- клиента нет, значит нет и ответа «собран ли облик» - его здесь не может знать
-- никто. Поэтому набор проверяет две разные вещи и не путает их:
--
--   1. ЧТО АДДОН ГОВОРИТ, КОГДА ОТВЕТА НЕТ. Это состояние стенда по умолчанию,
--      и оно же - состояние любого клиента, где этих функций не оказалось.
--      Правильный ответ один: «не знаю», и ни в каком виде не «всё в порядке».
--   2. ЧТО АДДОН ГОВОРИТ ПРИ ОТВЕТЕ. Ответ ПОДСТАВЛЯЕТСЯ явно
--      (H.setAppearances), и видно это в самой проверке - чтобы заглушка
--      никогда не выглядела как ответ игры.
local H = ...

return function()

local function cardOf(cards, kind)
    for _, c in ipairs(cards) do
        if c.kind == kind then return c end
    end
    return nil
end

local function cardByKey(cards, key)
    for _, c in ipairs(cards) do
        if c.key == key then return c end
    end
    return nil
end

-- Мир с зелёной вещью, которую можно и продать, и распылить: портной с чарами,
-- то есть ровно тот персонаж, что у игрока. Предмет 6001 - зелёный плащ.
local function looksEnv(opts)
    opts = opts or {}
    local env = H.load()
    local ns = env.ns
    env.money = 58052
    env.auctionator = true

    H.item(env, 6001, { name = "Зелёный плащик", equipLoc = "INVTYPE_CLOAK",
        reqLevel = 20, classID = 4, subclassID = 1, quality = 2,
        itemLevel = 25, sellPrice = 500, bindType = opts.bindType or 2 })
    H.item(env, 10940, { name = "Странная пыль", sellPrice = 100 })
    H.item(env, 10998, { name = "Малая астральная эссенция", sellPrice = 300 })
    H.item(env, 10978, { name = "Мерцающий осколок", sellPrice = 2000 })
    env.prices[10940] = 2000
    env.prices[10998] = 4000
    env.prices[10978] = 30000
    env.prices[6001] = 3000
    env.vendorPrices[6001] = 3000

    H.profession(env, "Наложение чар", 225, 225, {
        H.recipe { id = 6101, name = "Чары для плаща: малое сопротивление",
                   category = "Плащ", diff = "trivial",
                   reagents = { { itemID = 10940, qty = 1 } } },
    })
    H.profession(env, "Портняжное дело", 225, 225, {
        H.recipe { id = 6102, name = "Зелёный плащик", output = 6001,
                   category = "Плащи", diff = "trivial",
                   reagents = { { itemID = 10940, qty = 1 } } },
    })
    if opts.appearances then H.setAppearances(env, opts.appearances) end
    H.itemsChanged(env)
    H.rescan(env)
    return env
end

-- Запрос про один предмет, как его задаёт любая ветка.
local function ask(env, fields, deed)
    local item = { itemID = 6001 }
    for k, v in pairs(fields or {}) do item[k] = v end
    return env.ns.Appearance:Check(item, deed or "sell", "test")
end

-- =====================================================================
-- Адаптер
-- =====================================================================

H.suite("Адаптер: про облик спрашивают четыре функции, ненадёжную не зовут")
do
    local env = looksEnv()
    local ns = env.ns
    local Api = ns.Api
    Api:Detect()
    for _, key in ipairs({ "transmogItemInfo", "transmogHasSource",
                           "transmogSourceInfo", "gameRuleActive" }) do
        H.ok(Api.has[key] ~= nil, "адаптер ищет " .. key
            .. " (ключ есть, то есть искали)")
    end
    -- Ненадёжную функцию адаптер ЗАПИСЫВАЕТ, но не зовёт: единственное
    -- упоминание её во всех установленных аддонах - комментарий Plumber
    -- «isn't reliable», после которого он считает то же через sourceID.
    H.ok(Api.has.transmogByItemInfo ~= nil,
        "наличие PlayerHasTransmogByItemInfo записано")
    local detected = ns.Diag:Init().detect or {}
    for _, name in ipairs({ "C_TransmogCollection.GetItemInfo",
            "C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance",
            "C_TransmogCollection.PlayerHasTransmogByItemInfo",
            "C_GameRules.IsGameRuleActive" }) do
        H.ok(detected[name] ~= nil, "в диагностику записано наличие " .. name)
    end

    -- И САМОЕ ВАЖНОЕ: ненадёжную функцию никто не зовёт, а менять облик нечем.
    -- Перечень закрытый: это те вызовы, которыми облик НАДЕВАЮТ и СОХРАНЯЮТ, то
    -- есть действие вместо игрока.
    local FORBIDDEN = {
        "PlayerHasTransmogByItemInfo",
        "ApplyAllPending", "ClearAllPending", "SetPendingTransmog",
        "PickupOutfit", "SaveOutfit", "DeleteOutfit", "ModifyOutfit",
        "SetIsAppearanceFavorite",
    }
    local files, hits = {}, {}
    local toc = io.open(H.ROOT .. "/ForeverPilot.toc", "r")
    if toc then
        for line in toc:lines() do
            local rel = line:match("^%s*([%w_]+[\\/][%w_]+%.lua)%s*$")
                or line:match("^%s*([%w_]+%.lua)%s*$")
            if rel then files[#files + 1] = rel:gsub("\\", "/") end
        end
        toc:close()
    end
    H.ok(#files >= 28, "файлов из .toc просмотрено: " .. #files)
    for _, rel in ipairs(files) do
        local fh = io.open(H.ROOT .. "/" .. rel, "r")
        if fh then
            local src = fh:read("*a")
            fh:close()
            for line in (src .. "\n"):gmatch("([^\n]*)\n") do
                local code = line:gsub("%-%-.*$", "")
                for _, name in ipairs(FORBIDDEN) do
                    -- Ищем ВЫЗОВ, а не упоминание: имя ненадёжной функции
                    -- лежит в адаптере строкой, потому что её наличие
                    -- записывается в диагностику. Строка - это не вызов, и
                    -- именно эта разница тут и проверяется.
                    if code:find(name .. "%s*%(") then
                        hits[#hits + 1] = rel .. " -> " .. name
                    end
                end
            end
        end
    end
    H.eq(#hits, 0, "ни одного вызова, который меняет облик или считается"
        .. " ненадёжным" .. ((#hits > 0) and (": " .. table.concat(hits, ", ")) or ""))
end

H.suite("Облик: без ответа клиента аддон говорит «не знаю», а не «всё в порядке»")
do
    -- Шва нет - значит нет и ответа. Это НЕ выдуманное состояние: ровно так
    -- выглядит клиент, на котором этих функций не оказалось.
    local env = looksEnv()
    local ns = env.ns
    H.eq(ns.Api.transmogFakes, nil, "ответа про облик в стенде нет ни у кого")
    local collected, why, conf = ns.Api:AppearanceCollected(6001)
    H.eq(collected, nil, "ответ про сбор облика — не «да» и не «нет»")
    H.eq(why, "no-api", "а «спросить нечем»")
    H.eq(conf, ns.CONF.UNKNOWN, "и достоверность неизвестна")

    local v = ask(env, { bound = false })
    H.eq(v.state, ns.Appearance.STATE.UNKNOWN, "состояние: не знаю")
    H.eq(v.known, false, "и это прямо сказано")
    H.ok(v.loses ~= false, "и НЕ сказано, что терять нечего: " .. tostring(v.loses))
    H.eq(v.conf, ns.CONF.UNKNOWN, "достоверность из общего словаря")
    -- ПУСТОТА ТОЖЕ ИЗ ОБЩЕГО СЛОВАРЯ, А НЕ СВОЯ: знак «?» в одном месте экрана
    -- обязан значить то же, что в другом.
    H.eq(v.void, ns.VOID.UNKNOWN, "и вид пустоты — из ns.VOID")
    H.eq(ns.Util.void(v.void), ns.VOID_TEXT.UNKNOWN,
        "и рисуется тем же знаком, что остальная неизвестность: "
        .. tostring(ns.Util.void(v.void)))
    H.ok(ns.Appearance:Speaks(v), "игроку есть что сказать")
    H.ok(ns.Util.contains(v.short, "не знаю"), "строка: " .. tostring(v.short))
    H.ok(ns.Util.contains(v.detail, "не привязана"),
        "подробность называет и то, что вещь непривязанная")
    -- И заказ на данные записан: по нему в файле игрока видно, отвечает ли
    -- клиент про облик вообще. Другого способа узнать это офлайн нет.
    local wanted = (ns.Diag:Init().wanted or {})["appearanceUnknown"]
    H.ok(wanted ~= nil and (wanted.total or 0) > 0,
        "незнание записано в заказы данных: " .. tostring(wanted and wanted.total))
end

H.suite("Облик: подставленный ответ — «собран» и «не собран» различимы")
do
    local env = looksEnv({ appearances = { rule = true, collected = { [6001] = false } } })
    local ns = env.ns
    local v = ask(env, { bound = false }, "disenchant")
    H.eq(v.state, ns.Appearance.STATE.LOSES, "облик не собран — потеряется")
    H.eq(v.loses, true, "и это утверждение, а не догадка")
    H.eq(v.known, true, "ответ есть")
    H.ok(ns.Util.contains(v.short, "не собран"), "строка: " .. tostring(v.short))
    H.ok(ns.Util.contains(v.short, "распылите"),
        "и названо именно то, что игрок собрался делать: " .. tostring(v.short))
    H.ok(ns.Util.contains(v.detail, "навсегда"), "подробность говорит, что это навсегда")
    -- И НЕ ЗАПРЕЩАЕТ. Это не формальность: потеря необратима, запретить
    -- выглядит заботой, а решение всё равно за игроком.
    H.ok(ns.Util.contains(v.detail, "ваше право"),
        "и что решение за игроком: " .. ns.Util.truncate(v.detail, 200))
    for _, word in ipairs({ "не продавайте", "не распыляйте", "ни в коем случае" }) do
        H.eq(ns.Util.contains(v.detail, word), false,
            "и ничего не запрещает словами «" .. word .. "»")
        H.eq(ns.Util.contains(v.short, word), false,
            "ни в строке совета")
    end

    -- ПРИВЯЗАНА ЛИ ВЕЩЬ, МОЖЕТ БЫТЬ НЕИЗВЕСТНО, И ТОГДА ТАК И СКАЗАНО.
    -- Это не придирка: предупреждение остаётся (облик не собран), но называть
    -- вещь непривязанной, не зная этого, было бы утверждением из незнания.
    H.item(env, 6009, { name = "Вещь без правила привязки", equipLoc = "INVTYPE_CLOAK",
        classID = 4, subclassID = 1, quality = 2 })
    H.setAppearances(env, { rule = true, collected = { [6009] = false } })
    H.itemsChanged(env)
    local blind = ask(env, { itemID = 6009 }, "sell")
    H.eq(blind.state, ns.Appearance.STATE.LOSES, "предупреждение остаётся")
    H.ok(ns.Util.contains(blind.detail, "клиент мне не сказал"),
        "а про привязку сказано честно: " .. ns.Util.truncate(blind.detail, 200))
    H.eq(ns.Util.contains(blind.detail, "Эта вещь не привязана"), false,
        "и непривязанной она не названа")

    -- Тот же мир, ответ другой.
    H.setAppearances(env, { rule = true, collected = { [6001] = true } })
    local ok2 = ask(env, { bound = false })
    H.eq(ok2.state, ns.Appearance.STATE.COLLECTED, "облик собран — терять нечего")
    H.eq(ok2.loses, false, "и это сказано числом, а не умолчанием")
    H.eq(ns.Appearance:Speaks(ok2), false, "в строке совета про это молчим")

    -- Ответ про один предмет не уезжает к другому.
    H.setAppearances(env, { rule = true, collected = { [6001] = false, [6002] = true } })
    H.item(env, 6002, { name = "Второй плащик", equipLoc = "INVTYPE_CLOAK",
        classID = 4, subclassID = 1, quality = 2, bindType = 2 })
    H.itemsChanged(env)
    H.eq(ask(env, { itemID = 6001, bound = false }).state,
        ns.Appearance.STATE.LOSES, "по первому предмету ответ свой")
    H.eq(ask(env, { itemID = 6002, bound = false }).state,
        ns.Appearance.STATE.COLLECTED, "и по второму свой")
end

H.suite("Облик: то, что потеряться не может, до клиента не доходит")
do
    local env = looksEnv({ appearances = { rule = true, collected = { [6001] = false } } })
    local ns = env.ns

    -- Серое и белое учится по подбору.
    env.appearanceReads = 0
    local grey = ask(env, { quality = 0, bound = false }, "vendor")
    H.eq(grey.state, ns.Appearance.STATE.LOW, "серое: облик уже есть")
    H.eq(grey.loses, false, "терять нечего")
    local white = ask(env, { quality = 1, bound = false }, "vendor")
    H.eq(white.state, ns.Appearance.STATE.LOW, "белое — то же самое")

    -- Привязанная вещь уже ваша.
    local bound = ask(env, { bound = true })
    H.eq(bound.state, ns.Appearance.STATE.BOUND, "привязанная: облик уже записан")
    H.eq(bound.loses, false, "и не теряется")

    -- У расходника и материала облика не бывает.
    local mat = ask(env, { quality = 2, classID = 7, bound = false })
    H.eq(mat.state, ns.Appearance.STATE.NO_LOOK, "у товара облика нет")
    H.eq(mat.loses, false, "терять нечего")
    -- «Такого значения не бывает» - это другая пустота, чем «не знаю», и в
    -- общем словаре она названа отдельно.
    H.eq(mat.void, ns.VOID.IMPOSSIBLE, "и вид пустоты другой: такого не бывает")

    H.eq(env.appearanceReads, 0,
        "и ни одного вопроса клиенту ни в одном из этих случаев:"
        .. " обращений " .. tostring(env.appearanceReads))

    -- Трансмог выключен - терять нечего, и клиента про вещи не спрашиваем.
    H.setAppearances(env, { rule = false, collected = { [6001] = false } })
    env.appearanceReads = 0
    local off = ask(env, { bound = false })
    H.eq(off.state, ns.Appearance.STATE.OFF, "трансмога нет — терять нечего")
    H.eq(off.loses, false, "и не теряется")
    H.eq(env.appearanceReads, 0, "про предмет клиента не спрашивали")

    -- Рода вещи не знаем - значит не знаем, бывает ли у неё облик вовсе.
    -- Пугать нечем, но дырка в данных записывается. Предмет, про род которого
    -- клиент молчит, - это настоящее состояние: в сумках игрока так лежат
    -- патроны и предмет задания.
    H.setAppearances(env, { rule = true, collected = { [6003] = false } })
    H.item(env, 6003, { name = "Оперенная стрела", quality = 2 })
    H.itemsChanged(env)
    local blind = ask(env, { itemID = 6003, bound = false })
    H.eq(blind.state, ns.Appearance.STATE.UNKNOWN, "род неизвестен — не знаю")
    H.eq(blind.quiet, true, "и в строке совета про это молчим")
    H.eq(ns.Appearance:Speaks(blind), false, "говорить нечего")
end

-- ПРАВИЛА ПО УРОВНЮ ПЕРСОНАЖА НЕТ, И ЭТО ПРОВЕРЯЕТСЯ -----------------------
--
-- Уровневое ограничение трансмога на Forever ведёт себя несвязно: по рассказам
-- игроков на 41 работает, на 40 работает, на 37 нет, на 33 нет, на 32
-- работает, на 26 нет, на 21 нет, на 17 работает. Из такого ряда правило не
-- выводится, а выдуманное правило молчало бы ровно там, где облик теряется.
-- Проверка держит отсутствие правила: ответ на всех этих уровнях ОДИН.
H.suite("Облик: правила по уровню персонажа в аддоне нет")
do
    local env = looksEnv({ appearances = { rule = true, collected = { [6001] = false } } })
    local ns = env.ns
    local states = {}
    for _, level in ipairs({ 17, 21, 26, 32, 33, 37, 40, 41 }) do
        env.player.level = level
        H.rescan(env)
        local v = ask(env, { bound = false })
        states[#states + 1] = level .. ":" .. tostring(v.state)
        H.eq(v.state, ns.Appearance.STATE.LOSES,
            "на уровне " .. level .. " ответ тот же")
    end
    H.ok(#states == 8, "уровней проверено: " .. table.concat(states, " "))
end

H.suite("Облик: привязанность читается по самому опасному экземпляру")
do
    local env = looksEnv()
    local ns = env.ns
    local AP = ns.Appearance

    H.eq(AP:Bound({ bound = true }), true, "ответ по ячейке сильнее правила")
    H.eq(AP:Bound({ bound = false, bindType = 1 }), false, "и сильнее в обе стороны")
    H.eq(AP:Bound({ bindType = 1 }), true, "привязка при подборе: вещь станет вашей")
    H.eq(AP:Bound({ bindType = 2 }), false, "привязка при надевании: пока не ваша")
    H.eq(AP:Bound({}), nil, "клиент не сказал — значит не знаем")

    -- Один предмет в двух ячейках: одна вещь привязана, вторая нет. Опасна
    -- вторая, и ответ про предмет - про неё.
    local snap = { bagSlots = {
        { itemID = 6001, bound = true },
        { itemID = 6001, bound = false },
        { itemID = 10940, bound = true },
    } }
    local map = AP:BagBinding(snap)
    H.eq(map[6001], false, "при двух экземплярах отвечаем за непривязанный")
    H.eq(map[10940], true, "а где все привязаны — привязан")
    H.ok(AP:BagBinding(snap) == map, "второй раз сумки не обходим")
end

H.suite("Сумки: привязанность приходит полем isBound из ответа по ячейке")
do
    local env = looksEnv()
    local ns = env.ns
    -- Производственное чтение сумок, а не подмена из стенда: именно оно
    -- забирает поле isBound из ответа клиента. Поле проверено на данных
    -- игрока - его Syndicator пишет isBound по каждой ячейке и берёт его из
    -- этого же ответа.
    local realBags = env.real.BagCounts
    H.ok(realBags ~= nil, "производственное чтение сумок доступно")
    local answers = {
        [1] = { itemID = 6001, stackCount = 1, quality = 2, isBound = false },
        [2] = { itemID = 6001, stackCount = 1, quality = 2, isBound = true },
        [3] = { itemID = 10940, stackCount = 5, quality = 1 },
    }
    ns.Api:InjectBagFakes({
        numSlots = function(bag) return (bag == 0) and 3 or 0 end,
        itemInfo = function(bag, slot) return (bag == 0) and answers[slot] or nil end,
    })
    local counts, conf, slots = realBags(ns.Api)
    slots = slots or {}
    H.eq(#slots, 3, "три занятых ячейки прочитаны")
    H.eq(slots[1] and slots[1].bound, false, "непривязанная вещь — так и сказано")
    H.eq(slots[2] and slots[2].bound, true, "привязанная — так и сказано")
    H.eq(slots[3] and slots[3].bound, nil, "а молчание клиента осталось молчанием")
    H.eq(conf, ns.CONF.EXACT, "данные точные")
    H.eq((counts or {})[6001], 2, "количество не пострадало")
    ns.Api:InjectBagFakes(nil)
end

-- =====================================================================
-- Советы
-- =====================================================================

H.suite("Совет распылить: про облик сказано ДО распыла")
do
    local env = looksEnv({ appearances = { rule = true, collected = { [6001] = false } } })
    local ns = env.ns
    env.bags[6001] = 1
    env.bagBound[6001] = false
    H.itemsChanged(env)
    local cards = H.build(env)
    local c = cardOf(cards, ns.KIND.DISENCHANT)
    H.ok(c ~= nil, "карточка распыления есть")
    if c then
        H.ok(type(c.looks) == "table", "ответ про облик едет с карточкой")
        H.eq(c.looks and c.looks.state, ns.Appearance.STATE.LOSES,
            "и он: облик потеряется")
        H.ok(ns.Util.contains(c.why, "Облик"),
            "в строке «почему» это сказано: " .. ns.Util.truncate(c.why, 90))
        local lead = "Облик этой вещи"
        H.eq(c.why:sub(1, #lead), lead, "и сказано ПЕРВОЙ фразой, а не в конце")
        H.ok(ns.Util.contains(c.tipNote or "", "навсегда"),
            "подробности — под курсор: " .. ns.Util.truncate(c.tipNote or "", 120))
    end

    -- Собранный облик карточку не трогает.
    H.setAppearances(env, { rule = true, collected = { [6001] = true } })
    H.itemsChanged(env)
    local c2 = cardOf(H.build(env), ns.KIND.DISENCHANT)
    H.ok(c2 ~= nil, "карточка на месте")
    if c2 then
        H.eq(c2.looks.state, ns.Appearance.STATE.COLLECTED, "облик собран")
        H.eq(ns.Util.contains(c2.why, "Облик этой вещи"), false,
            "и в строке совета про облик ни слова")
    end
end

H.suite("Совет «на продажу»: про облик сказано, а запрета нет")
do
    local env = looksEnv({ appearances = { rule = true, collected = { [6001] = false } } })
    local ns = env.ns
    env.bags[10940] = 20
    H.itemsChanged(env)
    local cards = H.build(env)
    local c = cardByKey(cards, "profit:6102") or cardOf(cards, ns.KIND.CRAFT_PROFIT)
    H.ok(c ~= nil, "карточка «на продажу» есть")
    if c then
        H.eq(c.looks and c.looks.state, ns.Appearance.STATE.LOSES,
            "облик потеряется")
        H.ok(ns.Util.contains(c.why, "не собран"), "и это сказано в строке")
        -- НЕ ЗАПРЕЩАЕМ: карточка осталась, кнопка осталась, выгода осталась.
        H.ok((c.benefitValue or 0) > 0, "совет никуда не делся: выгода на месте")
        H.ok(c.action ~= nil, "и действие у карточки то же")
    end
end

H.suite("Перекупить и перепродать: лот с аукциона непривязан, и это сказано")
do
    local env = H.load()
    local ns = env.ns
    env.money = 58052
    env.auctionator = true
    -- Цена выкупа настоящая по порядку: иначе самопроверка справедливо
    -- усомнится в наценке и её сомнение встанет в строке первым.
    H.item(env, 2589, { name = "Зелёный поясок", equipLoc = "INVTYPE_WAIST",
        classID = 4, subclassID = 1, quality = 2, sellPrice = 4000, bindType = 2 })
    env.prices[2589] = 8000
    local cfg = ns.Config:Get()
    cfg.priceHistory[2589] = {
        [20770] = 20000, [20771] = 21000, [20772] = 19000,
        [20773] = 20500, [20774] = 20000,
    }
    cfg.priceHistoryMeta.days = 5
    cfg.priceHistoryMeta.firstDay = 20770
    cfg.priceHistoryMeta.lastDay = 20774
    H.setAppearances(env, { rule = true, collected = { [2589] = false } })
    -- Профиль задан явно: перекупку профили «Сила» и «Экономия» намеренно не
    -- показывают (ns.PROFILE_EXCLUDE), и проверять надо в том профиле, которому
    -- этот совет адресован.
    ns.Config:SetProfile("EARN")
    H.itemsChanged(env)
    H.rescan(env)
    local c = cardOf(H.build(env), ns.KIND.RESELL)
    H.ok(c ~= nil, "карточка перекупки есть")
    if c then
        H.ok(type(c.looks) == "table", "ответ про облик едет с карточкой")
        H.eq(c.looks and c.looks.state, ns.Appearance.STATE.LOSES,
            "лот с аукциона привязанным не бывает — значит облик потеряется")
        H.ok(ns.Util.contains(c.why, "не собран"),
            "и сказано до покупки: " .. ns.Util.truncate(c.why, 100))
    end
end

H.suite("Купить у торговца и перепродать: та же схема, тот же ответ")
do
    local env = H.load()
    local ns = env.ns
    env.money = 58052
    env.auctionator = true
    -- Зелёная вещь с полки торговца: редкий, но настоящий случай, и схема у него
    -- та же, что у перекупки лота - купить и продать снова.
    H.item(env, 2324, { name = "Зелёный поясок торговца", equipLoc = "INVTYPE_WAIST",
        classID = 4, subclassID = 1, quality = 2, sellPrice = 300, bindType = 2 })
    ns.Config:RememberVendorPrice(2324, 1500)
    env.prices[2324] = 8000
    H.setAppearances(env, { rule = true, collected = { [2324] = false } })
    ns.Config:SetProfile("EARN")
    H.itemsChanged(env)
    H.rescan(env)
    local c = cardOf(H.build(env), ns.KIND.ARBITRAGE)
    H.ok(c ~= nil, "карточка перепродажи у торговца есть")
    if c then
        H.ok(type(c.looks) == "table", "ответ про облик едет с карточкой")
        H.eq(c.looks and c.looks.state, ns.Appearance.STATE.LOSES,
            "товар с полки непривязан — облик потеряется")
        H.ok(ns.Util.contains(c.why, "не собран"),
            "и это сказано: " .. ns.Util.truncate(c.why, 100))
    end
end

H.suite("Скрафтить для другого: карточка пересылки тоже предупреждает")
do
    local env = looksEnv({ appearances = { rule = true, collected = { [6001] = false } } })
    local ns = env.ns
    env.syndicator = true
    env.player.name, env.player.surname = "Гендольф", "Серыйй"
    env.altNames = { "Гендольф Белыйй-PvP" }
    env.altData = {
        ["Гендольф Белыйй-PvP"] = {
            details = { character = "Гендольф Белыйй", realm = "PvP", class = 9,
                        className = "WARLOCK" },
            money = 11186, bags = { {} },
        },
    }
    H.rescan(env)
    local cards = H.build(env)
    local c
    for _, card in ipairs(cards) do
        if card.key and card.key:find("cross:craftfor", 1, true) then c = card end
    end
    H.ok(c ~= nil, "карточка «скрафтить для другого» есть")
    if c then
        H.ok(type(c.looks) == "table", "ответ про облик едет с карточкой")
        H.eq(c.looks and c.looks.state, ns.Appearance.STATE.LOSES,
            "отправленную почтой вещь теряешь вместе с обликом")
        H.ok(ns.Util.contains(c.why, "почтой"),
            "и сказано именно про пересылку: " .. ns.Util.truncate(c.why, 110))
    end
end

H.suite("Продать хлам: серое не теряется, а вопрос всё равно задан")
do
    local env = looksEnv({ appearances = { rule = true, collected = { [6001] = false } } })
    local ns = env.ns
    H.item(env, 9000, { name = "Рваная шкура", sellPrice = 70, quality = 0 })
    env.bags[9000] = 4
    H.itemsChanged(env)
    H.rescan(env)
    env.bagBound[9000] = false
    H.rescan(env)
    -- Позиция хлама несёт качество и привязанность с собой: по ним ветка и
    -- спрашивает про облик, и спрашивать она обязана про ту вещь, которую
    -- сканер отобрал, а не про какую-то другую.
    local junk = ns.CharacterScanner:Junk()
    H.ok(#junk > 0, "хлам найден: " .. #junk)
    if junk[1] then
        H.eq(junk[1].quality, 0, "качество едет с позицией")
        H.eq(junk[1].bound, false, "и привязанность тоже")
    end
    local c = cardOf(H.build(env), ns.KIND.SELL_JUNK)
    H.ok(c ~= nil, "карточка хлама есть")
    if c then
        H.ok(type(c.looks) == "table", "вопрос про облик задан и у хлама")
        H.eq(c.looks and c.looks.state, ns.Appearance.STATE.LOW,
            "серое учится по подбору")
        H.eq(ns.Util.contains(c.why, "Облик"), false,
            "и пугать игрока нечем: " .. ns.Util.truncate(c.why, 80))
    end

    -- А ЕСЛИ В ХЛАМ ПОПАДЁТ НЕ СЕРОЕ. Условие «серое» живёт в сканере и
    -- держится на одном поле ответа клиента; поменяйся оно - и карточка
    -- «продать хлам» стала бы необратимой ошибкой. Поэтому ветка спрашивает
    -- каждую позицию, а не делает вывод из того, что их отобрал сканер.
    local realJunk = ns.CharacterScanner.Junk
    ns.CharacterScanner.Junk = function()
        return { { itemID = 6001, qty = 1, unit = 500, total = 500,
                   name = "Зелёный плащик", quality = 2, bound = false } }
    end
    local c2 = cardOf(H.build(env), ns.KIND.SELL_JUNK)
    ns.CharacterScanner.Junk = realJunk
    H.ok(c2 ~= nil, "карточка собрана")
    if c2 then
        H.eq(c2.looks and c2.looks.state, ns.Appearance.STATE.LOSES,
            "зелёная вещь в хламе — предупреждение")
        H.ok(ns.Util.contains(c2.why, "не собран"),
            "и оно на карточке: " .. ns.Util.truncate(c2.why, 90))
        H.ok(ns.Util.contains(c2.why, "торговцу"),
            "и названо именно то, что игрок сделает")
    end
end

-- НАДЕТЬ ИЛИ ПРОДАТЬ: ОДНА КАРТОЧКА, ДВА ВАРИАНТА, И ОПАСЕН ТОЛЬКО ВТОРОЙ ----
--
-- Когда ту же вещь советуют и надеть, и продать, карточка остаётся одна и
-- называет оба варианта (Engine:FoldSellIntoGear). Надеть безопасно: надетая
-- вещь привязывается, и облик с неё записывается сам. Поэтому предупреждение
-- обязано переехать вместе со вторым вариантом - иначе оно пропало бы вместе
-- со свёрнутой карточкой, причём именно у той вещи, которую игрок собрался
-- продать. И стоять оно обязано НЕ первым: карточка советует надеть.
H.suite("Надеть или продать: предупреждение переезжает со вторым вариантом")
do
    local env = H.load()
    local ns = env.ns
    env.player.level = 26
    env.money = 468977
    H.item(env, 300, { name = "Простой капюшон", equipLoc = "INVTYPE_HEAD",
        reqLevel = 10, classID = 4, subclassID = 1, sellPrice = 100, quality = 1 })
    env.stats[300] = { ITEM_MOD_INTELLECT_SHORT = 4, ITEM_MOD_STAMINA_SHORT = 3 }
    env.equipped.HEAD = { itemID = 300 }
    H.item(env, 301, { name = "Расшитый капюшон", equipLoc = "INVTYPE_HEAD",
        reqLevel = 20, classID = 4, subclassID = 1, sellPrice = 400,
        quality = 2, bindType = 2 })
    env.stats[301] = { ITEM_MOD_INTELLECT_SHORT = 14, ITEM_MOD_STAMINA_SHORT = 9 }
    H.item(env, 302, { name = "Тонкая ткань", sellPrice = 10 })
    env.prices[302] = 50
    env.prices[301] = 40000
    env.bags[302] = 12
    H.profession(env, "Портняжное дело", 225, 225, {
        H.recipe { id = 701, output = 301, outputQty = 1,
                   reagents = { { itemID = 302, qty = 4 } },
                   name = "Расшитый капюшон", diff = "optimal",
                   category = "Капюшоны", categoryID = 1 },
    })
    H.setAppearances(env, { rule = true, collected = { [301] = false } })
    H.itemsChanged(env)
    H.rescan(env)
    local cards = H.build(env)
    local gear = cardOf(cards, ns.KIND.CRAFT_GEAR)
    H.ok(gear ~= nil, "совет «скрафтить и надеть» построен")
    if gear then
        H.ok(gear.alsoSell ~= nil, "и второй вариант в нём назван")
        H.ok(type(gear.looks) == "table", "ответ про облик доехал до карточки")
        H.eq(gear.looks and gear.looks.state, ns.Appearance.STATE.LOSES,
            "и он: облик потеряется")
        H.ok(ns.Util.contains(gear.why, "не собран"),
            "предупреждение на карточке: " .. ns.Util.truncate(gear.why, 240))
        local lead = "Облик этой вещи"
        H.ok(gear.why:sub(1, #lead) ~= lead,
            "но НЕ первой фразой: карточка советует надеть, а это безопасно")
        H.ok(type(gear.alsoSell.looks) == "table",
            "и со вторым вариантом ответ едет дальше")
    end
end

H.suite("Самопроверка: совет расстаться с вещью без ответа про облик — находка")
do
    local env = looksEnv({ appearances = { rule = true, collected = { [6001] = false } } })
    local ns = env.ns
    env.bags[6001] = 1
    env.bags[10940] = 20
    H.itemsChanged(env)
    local cards = H.build(env)

    H.ok(ns.SanityChecks:HasCheck("appearance-unchecked"), "проверка зарегистрирована")
    H.ok(ns.SanityChecks.SCOPE["appearance-unchecked"] ~= nil,
        "и её адрес назван в закрытом перечне")

    -- 1. Как есть - находок нет.
    local parting = 0
    for _, c in ipairs(cards) do
        if ns.SanityChecks.PARTING_KINDS[c.kind] or c.alsoSell then
            if not ns.SanityChecks.PARTING_EXEMPT[c.key or ""] then
                parting = parting + 1
                H.ok(type(c.looks) == "table",
                    "у совета «" .. tostring(c.title) .. "» ответ про облик есть")
            end
        end
    end
    H.ok(parting > 0, "советов расстаться с вещью в списке: " .. parting)

    ns.Diag:ClearSuspicions()
    ns.SanityChecks:Run({ cards = cards, snap = ns.CharacterScanner:Get() })
    local found = 0
    for _, s in ipairs(ns.Diag:Init().suspicious or {}) do
        if s.code == "appearance-unchecked" then found = found + 1 end
    end
    H.eq(found, 0, "пока вопрос задаётся, проверка молчит")

    -- 2. Отнимаем ответ у одной карточки - проверка обязана это увидеть.
    local victim
    for _, c in ipairs(cards) do
        if ns.SanityChecks.PARTING_KINDS[c.kind]
            and not ns.SanityChecks.PARTING_EXEMPT[c.key or ""] then
            victim = victim or c
        end
    end
    H.ok(victim ~= nil, "карточка для опыта нашлась")
    if victim then
        victim.looks = nil
        ns.Diag:ClearSuspicions()
        ns.SanityChecks:Run({ cards = cards, snap = ns.CharacterScanner:Get() })
        local said = 0
        for _, s in ipairs(ns.Diag:Init().suspicious or {}) do
            if s.code == "appearance-unchecked" then said = said + 1 end
        end
        H.eq(said, 1, "совет без ответа про облик — находка")
    end
end

H.suite("Пересылка другому персонажу: про чужую коллекцию облика аддон не врёт")
do
    local env = looksEnv({ appearances = { rule = true, collected = { [6001] = true } } })
    local ns = env.ns
    env.syndicator = true
    env.player.name, env.player.surname = "Гендольф", "Серыйй"
    env.altNames = { "Гендольф Белыйй-PvP" }
    env.altData = {
        ["Гендольф Белыйй-PvP"] = {
            details = { character = "Гендольф Белыйй", realm = "PvP", class = 9,
                        className = "WARLOCK" },
            money = 11186,
            bags = { { { itemID = 6001, itemCount = 1, isBound = false } } },
        },
    }
    H.rescan(env)
    local snap = ns.CharacterScanner:Get()
    local list = ns.CrossCharacter:MaterialsElsewhere({ [6001] = 1 }, snap)
    H.ok(list ~= nil and #list == 1, "вещь у другого персонажа найдена")
    if list and list[1] then
        local v = list[1].looks
        H.ok(type(v) == "table", "ответ про облик едет с находкой")
        v = (type(v) == "table") and v or {}
        -- Клиент ответил «у меня этот облик есть» - но ответил ПРО ТЕКУЩЕГО
        -- персонажа, а вещь у другого. Общая ли коллекция на аккаунте в
        -- Forever, неизвестно, поэтому «собран» здесь ничего не доказывает.
        H.eq(v.state, ns.Appearance.STATE.UNKNOWN,
            "про чужую вещь ответ один: не знаю")
        H.eq(v.known, false, "и это сказано")
        H.ok(ns.Util.contains(v.detail, "другого персонажа"),
            "и объяснено, почему: " .. ns.Util.truncate(v.detail or "", 160))
        H.eq(ns.Util.contains(v.detail or "", "Shift"), false,
            "в чужое окно облика игрока не посылаем: там этого не видно")
    end
end

H.suite("Совет скрафтить для другого: продадите не вы, но облик теряете вы")
do
    local env = looksEnv({ appearances = { rule = true, collected = { [6001] = false } } })
    local ns = env.ns
    env.syndicator = true
    env.player.name, env.player.surname = "Гендольф", "Серыйй"
    env.altNames = { "Гендольф Белыйй-PvP" }
    env.altData = {
        ["Гендольф Белыйй-PvP"] = {
            details = { character = "Гендольф Белыйй", realm = "PvP", class = 9,
                        className = "WARLOCK" },
            money = 11186, bags = { {} },
        },
    }
    H.rescan(env)
    local forOthers = ns.CrossCharacter:CraftablesForOthers(ns.CharacterScanner:Get())
    H.ok(forOthers ~= nil and #forOthers > 0,
        "вещь для другого персонажа нашлась: " .. #(forOthers or {}))
    if forOthers and forOthers[1] then
        local v = forOthers[1].looks
        H.ok(type(v) == "table", "ответ про облик есть")
        H.eq(v.state, ns.Appearance.STATE.LOSES, "облик потеряет тот, кто отправит")
        H.ok(ns.Util.contains(v.short, "отправите почтой"),
            "и названо именно это: " .. tostring(v.short))
    end
end

-- =====================================================================
-- Цена работы - в числе вызовов за пересчёт, не в миллисекундах
-- =====================================================================

H.suite("Цена вопроса про облик: вызовы за пересчёт, и их мало")
do
    local env = looksEnv({ appearances = { rule = true, collected = { [6001] = false } } })
    local ns = env.ns
    env.bags[6001] = 1
    env.bags[10940] = 20
    H.itemsChanged(env)

    H.build(env)
    local first = ns.Api.appearanceReads or 0
    H.ok(first > 0, "за первый пересчёт клиента спросили: " .. first)
    H.ok(first <= 12, "и спросили мало: " .. first .. " обращений")

    -- Второй пересчёт: «какой у вещи облик» - свойство вещи, его помним всю
    -- сессию. «Собран ли он» игрок может изменить в любую секунду, поэтому
    -- спрашивается заново - но ровно по одному разу на вещь.
    H.build(env)
    local second = ns.Api.appearanceReads or 0
    H.ok(second > 0, "на втором пересчёте «собран ли» спросили снова: " .. second)
    H.ok(second <= first, "а источник облика переспрашивать не стали: "
        .. second .. " против " .. first)
    H.ok((ns.Api.appearanceHits or 0) > 0,
        "часть ответов пришла из памяти: " .. tostring(ns.Api.appearanceHits))

    -- И ГЛАВНОЕ: ЦЕНА НЕ РАСТЁТ ОТ ЧИСЛА КАНДИДАТОВ.
    --
    -- Это не придирка к быстродействию, а живое число: когда вопрос стоял
    -- внутри обхода кандидатов, на настоящих данных выходило 140 вопросов за
    -- пересчёт при восьми советах - то есть 132 ответа клиента выбрасывались.
    -- Спрашивать надо про те вещи, которые попадут на карточку.
    local before = ns.Api.appearanceAsked or 0
    local extra = {}
    for i = 1, 40 do
        local id = 7000 + i
        H.item(env, id, { name = "Зелёная вещь " .. i, equipLoc = "INVTYPE_CLOAK",
            reqLevel = 20, classID = 4, subclassID = 1, quality = 2,
            itemLevel = 25, sellPrice = 500, bindType = 2 })
        env.prices[id] = 3000
        env.bags[id] = 1
        extra[#extra + 1] = H.recipe { id = 8000 + i, name = "Зелёная вещь " .. i,
            output = id, category = "Плащи", diff = "trivial",
            reagents = { { itemID = 10940, qty = 1 } } }
    end
    ns.RecipeBook:Store("Портняжное дело", extra, "own", ns.CONF.EXACT, H.serverTime)
    ns.RecipeBook:Reindex()
    H.itemsChanged(env)
    H.rescan(env)
    local cards = H.build(env)
    local asked = (ns.Api.appearanceAsked or 0)
    local parting = 0
    for _, c in ipairs(cards) do
        if ns.SanityChecks.PARTING_KINDS[c.kind] or c.alsoSell then parting = parting + 1 end
    end
    H.ok(parting > 0, "советов расстаться с вещью: " .. parting)
    H.ok(asked <= parting + 4,
        "вопросов про облик " .. asked .. " при " .. parting .. " советах:"
        .. " спрашиваем про то, что попадёт на карточку, а не про 40 кандидатов")
    H.ok(asked < 40, "и уж точно не про каждого кандидата: " .. asked
        .. " против 40 (до правки было бы больше)")
    H.ok(before >= 0, "счётчик вопросов есть")

    -- Правило игры спрашивается один раз за сессию, а не на каждый предмет.
    local rule = 0
    local realRead = ns.Api.ReadTransmogRule
    ns.Api.ReadTransmogRule = function(self)
        rule = rule + 1
        return realRead(self)
    end
    ns.Api.transmogRule = nil
    for _ = 1, 5 do ns.Api:TransmogEnabled() end
    ns.Api.ReadTransmogRule = realRead
    H.eq(rule, 1, "«включён ли трансмог» спрошено один раз на пять вопросов")

    -- И ЭТИ ЧИСЛА ПОПАДАЮТ В ФАЙЛ ДИАГНОСТИКИ. Без них цену работы в игре
    -- мерить нечем: остальные дорогие обращения к клиенту там под присмотром, а
    -- это было бы не под присмотром.
    local mod = (ns.Diag:Init().modules or {})["actionEngine"] or {}
    local calls = mod.clientCalls or {}
    H.ok(calls.appearanceAsked ~= nil, "в файл пишется число вопросов про облик")
    H.ok(calls.appearanceReads ~= nil, "и число обращений к клиенту")
    H.ok(calls.appearanceCacheHits ~= nil, "и сколько ответов нашлось у нас")
end

end
