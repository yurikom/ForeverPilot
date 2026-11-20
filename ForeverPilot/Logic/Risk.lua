-- ForeverPilot / Logic/Risk.lua
--
-- ЧЕГО СОВЕТ МОЖЕТ СТОИТЬ, ЕСЛИ ОН НЕ СРАБОТАЕТ.
--
-- Каждый денежный совет в этом аддоне до сих пор говорил только половину
-- правды: сколько можно заработать. Вторая половина - сколько надо вложить и
-- сколько можно потерять - не называлась вообще. Для персонажа с пятью
-- золотыми это не мелочь: карточка «Купить: Рулон магической ткани x42 за
-- 168з» формально верна и совершенно бесполезна, а карточка «скрафтить на 2з
-- прибыли» умалчивает, что 1з надо выложить вперёд и покупателя может не быть.
--
-- Поэтому модуль считает для любой карточки четыре величины и отдаёт их одной
-- фразой, которую карточка печатает рядом с выгодой, а не вместо неё:
--
--   capital    сколько золота должно уйти из кошелька ПЕРЕД тем, как что-то
--              вернётся. Для крафта это материалы, для покупки - сама покупка.
--   buyerRisk  кто вообще заберёт результат. Торговец берёт всегда и по
--              известной цене; аукцион - это чьё-то объявление, за которое
--              никто ещё не заплатил; «никто не подтверждал» - это третий,
--              худший, случай, и он не то же самое, что второй.
--   priceRisk  насколько цифра выручки устойчива: что говорит своя история,
--              насколько она глубока и насколько свежа цена.
--   maxLoss    сколько можно потерять в худшем случае. Не выдуманное число:
--              вложенное минус то, за что результат заведомо заберёт торговец.
--              Пола нет - значит теряется всё вложенное, и так и сказано.
--
-- И ещё одно, отдельное: ПРАВДОПОДОБИЕ. Числа одной карточки умеют друг другу
-- противоречить. «Выручка 2з 66с» рядом с «цена торговца 5м» - это расхождение
-- в 5320 раз, которого у крафта не бывает; самопроверка это ловила и писала в
-- файл, а карточка всё равно уходила игроку без единого слова. Такая карточка
-- теперь помечается сомнительной, достоверность падает до «неизвестно», и в
-- ранжировании она опускается ниже всего, что игрок может сделать сегодня.
--
-- Никаких игровых действий здесь нет: это арифметика над числами, которые
-- движок уже посчитал.
local ADDON, ns = ...

local U = ns.Util
local CONF = ns.CONF

local Risk = {}
ns.Risk = Risk

-- Уровни ----------------------------------------------------------------

Risk.LEVEL = {
    NONE   = "NONE",
    LOW    = "LOW",
    MEDIUM = "MEDIUM",
    HIGH   = "HIGH",
}

Risk.LEVEL_RANK = { NONE = 0, LOW = 1, MEDIUM = 2, HIGH = 3 }

Risk.LEVEL_LABEL = {
    NONE   = "без риска",
    LOW    = "риск низкий",
    MEDIUM = "риск средний",
    HIGH   = "риск высокий",
}

Risk.LEVEL_COLOR = {
    NONE   = { 0.45, 0.85, 0.45 },
    LOW    = { 0.75, 0.85, 0.45 },
    MEDIUM = { 0.90, 0.75, 0.35 },
    HIGH   = { 0.90, 0.45, 0.45 },
}

-- Худший из двух уровней. Возвращает сам уровень, а не число, чтобы вызывающий
-- мог сразу положить его в карточку.
function Risk:Worse(a, b)
    local ra = Risk.LEVEL_RANK[a]
    local rb = Risk.LEVEL_RANK[b]
    if ra == nil then return b end
    if rb == nil then return a end
    return (ra >= rb) and a or b
end

-- Пороги ----------------------------------------------------------------

-- ДВА ПОРОГА, И ОНИ ОТВЕЧАЮТ НА РАЗНЫЕ ВОПРОСЫ.
--
--   VENDOR_RATIO_NOTE  - «это стоит упомянуть». Крафт обычно продаётся в
--     несколько раз, иногда в десятки раз дороже того, что даёт торговец. Сто
--     раз - много, но бывает: тканевый пояс за 9з при цене торговца 5с - это
--     171 раз, и это настоящий рынок молодого сервера. Самопроверка ругается
--     именно по этому порогу, и порог у неё берётся ОТСЮДА, чтобы запись в
--     файле и текст на карточке не разъехались - они уже разъезжались.
--
--   VENDOR_RATIO_LIMIT - «я этой цене не верю». Тысяча раз - это не рынок. У
--     настоящих случаев, из-за которых всё это появилось, разрыв был 2510 раз
--     (льняные сапоги: один лот на 50200 при неделе по 200) и 5320 раз
--     (тренировочный жезл: выручка 2з 66с при цене торговца 5м). Оба проходят
--     порог с запасом, а пояс за 171 - нет, и это ровно то разделение,
--     которое нужно: упомянуть - не то же самое, что не поверить.
Risk.VENDOR_RATIO_NOTE = 100
Risk.VENDOR_RATIO_LIMIT = 1000

-- Доля кошелька, после которой вложение называется заметным, и доля, после
-- которой - тяжёлым. Проценты от СВОИХ денег, а не абсолютные суммы: для
-- персонажа с пятью золотыми золотой - это пятая часть всего, что у него есть.
Risk.CAPITAL_NOTABLE_SHARE = 0.25
Risk.CAPITAL_HEAVY_SHARE   = 0.60

-- Залог аукциона. Клиент не сообщает формулу залога (CalculateAuctionDeposit
-- работает только когда предмет уже лежит в слоте продажи), поэтому считаем по
-- доле от цены торговца за сутки и ВСЕГДА помечаем оценкой. Если клиент
-- когда-нибудь отдаст свою функцию, Api:AuctionDeposit её подхватит и пометка
-- сменится - проверка на это есть в наборе.
Risk.DEPOSIT_SHARE_PER_DAY = 0.05

-- Капитал ---------------------------------------------------------------

-- Сколько денег должно уйти вперёд. Явный ноль - это ответ («ничего не надо
-- тратить»), а nil - это «не знаю», и путать их нельзя.
function Risk:Capital(card)
    if type(card) ~= "table" then return nil end
    local cost = tonumber(card.cost)
    if cost and cost >= 0 then return cost end
    return nil
end

-- ПОТОЛОК ВЫРУЧКИ ПРОТИВ ПОЛА ВЫРУЧКИ - ДВА РАЗНЫХ ЧИСЛА, И ПУТАТЬ ИХ НЕЛЬЗЯ.
--
--   Risk:VendorFloor   - сколько торговец ДАСТ за результат. Пол: ниже него не
--                        упадёшь, он лежит в данных самого предмета.
--   Risk:VendorCeiling - сколько торговец ПРОСИТ за такой же предмет, имея его
--                        в неограниченном количестве. Потолок: выше него никто
--                        у игрока покупать не станет - сходит к прилавку и
--                        возьмёт сколько надо, когда надо.
--
-- Потолок спрашивается у Logic/PriceProvider.lua и только у него: там один
-- ответ на весь аддон и там же решается, какой источник вообще доказывает
-- неограниченный запас. Своего перечня источников здесь нет сознательно.
function Risk:VendorCeiling(card)
    if type(card) ~= "table" then return nil end
    local itemID = tonumber(card.itemID)
    if not itemID or not ns.PriceProvider then return nil end
    -- Решение могло уже приехать с ценой продажи - тогда второй раз не считаем.
    local fromCard = card.revOrigin and card.revOrigin.ceiling
    local v = fromCard or ns.PriceProvider:Ceiling(itemID)
    if type(v) ~= "table" or not v.ceiling then return nil end
    return v.ceiling, v
end

-- ВЫРУЧКА ВЫШЕ ПРИЛАВКА - ЭТО СОМНЕНИЕ, А НЕ ЗАПРЕТ.
--
-- Так бывает: за готовое и под рукой платят надбавку. Но весь расчёт тогда
-- держится на том, что покупатель не знает про прилавок, и говорить об этом
-- надо игроку, а не себе в файл. Поэтому ступень - «я бы это проверил»
-- (Risk.DOUBT_SOFT), а не «числа не сходятся».
--
-- ПЕРЕПРОДАЖА У ТОРГОВЦА (KIND.ARBITRAGE) СЮДА НЕ ВХОДИТ, И ЭТО НЕ ПРОПУСК:
-- там «аукцион дороже прилавка» - не побочный признак, а сама схема, и
-- правдоподобие наценки считается собственными порогами ветки по наблюдениям
-- игрока (VendorArbitrage.MARKUP_NOTE / MARKUP_LIMIT). Второе сомнение об том
-- же числе дало бы на карточке две разные формулировки одного состояния - то,
-- от чего этот файл и избавлялся.
Risk.CEILING_DOUBT_KINDS = {
    [ns.KIND.CRAFT_PROFIT] = true,
    [ns.KIND.RESELL] = true,
}

-- Возвращает nil или { code, ceiling, revenue, ratio, text }.
function Risk:CeilingDoubt(card)
    if type(card) ~= "table" then return nil end
    if not Risk.CEILING_DOUBT_KINDS[card.kind] then return nil end
    local revenue = tonumber(card.revenue)
    if not (revenue and revenue > 0) then return nil end
    local ceiling, v = Risk:VendorCeiling(card)
    if not ceiling or revenue <= ceiling then return nil end
    local seen = v and v.seenBy
    return {
        code = "revenue-above-vendor-ceiling",
        ceiling = ceiling,
        ceilingSrc = v and v.ceilingSrc or nil,
        revenue = revenue,
        ratio = revenue / ceiling,
        text = string.format(
            "выручка %s, а такой же предмет торговец продаёт по %s и запас у"
            .. " него неограниченный (%s). Выше прилавка у вас покупать незачем:"
            .. " за готовое иногда доплачивают, но весь расчёт держится на этом",
            U.money(revenue), U.money(ceiling),
            seen or "цена торговца у меня записана"),
    }
end

-- Что заведомо вернётся, если рынок не заберёт: цена торговца за результат.
-- Берётся из данных самого предмета, то есть это точное число, а не оценка.
function Risk:VendorFloor(card)
    if type(card) ~= "table" then return nil end
    local itemID = tonumber(card.itemID)
    if not itemID then return nil end
    local info = ns.Api and ns.Api:ItemInfo(itemID) or nil
    local sell = info and tonumber(info.sellPrice) or nil
    if not sell or sell <= 0 then return nil end
    local qty = math.max(1, tonumber(card.outputQty) or 1)
    return sell * qty
end

-- Залог: сколько придётся положить на стол, чтобы выставить лот, и вернётся ли
-- он. Возвращает copper, confidence, текст-пояснение.
function Risk:Deposit(card, days)
    days = math.max(1, tonumber(days) or 1)
    local floor_ = Risk:VendorFloor(card)
    if not floor_ then return nil, CONF.UNKNOWN, nil end

    -- Сначала спрашиваем клиент: если он умеет считать залог сам, его число
    -- точнее любой нашей доли.
    if ns.Api and ns.Api.AuctionDeposit then
        local exact = ns.Api:AuctionDeposit(card.itemID, days)
        if exact then
            return exact, CONF.EXACT,
                "залог " .. U.money(exact) .. " (посчитал клиент)"
        end
    end
    local est = U.round(floor_ * Risk.DEPOSIT_SHARE_PER_DAY * days)
    if est <= 0 then return nil, CONF.UNKNOWN, nil end
    return est, CONF.ESTIMATE,
        "залог примерно " .. U.money(est)
        .. " (точную формулу залога клиент не сообщает — это оценка)"
end

-- Риск покупателя -------------------------------------------------------

-- Кто заберёт результат, и насколько это надёжно. Три разных ответа, и
-- смешивать их нельзя: «торговец» - гарантия, «аукцион» - наблюдение,
-- «никто» - отсутствие данных.
function Risk:BuyerRisk(card)
    local origin = (type(card) == "table" and card.revOrigin) or nil
    -- Карточка, которая ничего не продаёт, покупателя не ищет.
    if not origin then
        if type(card) == "table" and (card.kind == ns.KIND.BUY
            or card.kind == ns.KIND.CRAFT_GEAR or card.kind == ns.KIND.EQUIP
            or card.kind == ns.KIND.ENCHANT or card.kind == ns.KIND.SETUP) then
            return Risk.LEVEL.NONE, "продавать ничего не нужно"
        end
        return nil, nil
    end
    if origin.market then
        return Risk.LEVEL.MEDIUM,
            "цена с аукциона: это чьё-то объявление, за него ещё никто не заплатил"
    end
    if origin.observed then
        return Risk.LEVEL.NONE, "торговец заберёт по известной цене в любой момент"
    end
    return Risk.LEVEL.HIGH,
        "эту цену никто не подтверждал — ни аукцион, ни торговец"
end

-- Риск цены -------------------------------------------------------------

-- Насколько устойчива сама цифра выручки. Своя история, её глубина и возраст
-- цены - три разных повода не доверять, и каждый называется словами.
function Risk:PriceRisk(card)
    if type(card) ~= "table" then return nil, nil end
    local origin = card.revOrigin or {}
    local verdict = origin.verdict
    local level, why = Risk.LEVEL.LOW, nil

    local MH = ns.MarketHistory
    if verdict and MH then
        if verdict.flag == MH.FLAG.HIGH_OUTLIER or verdict.flag == MH.FLAG.LOW_OUTLIER then
            level = Risk:Worse(level, Risk.LEVEL.HIGH)
            why = "своя история называет эту цену нетипичной"
        elseif verdict.flag == MH.FLAG.NO_HISTORY then
            level = Risk:Worse(level, Risk.LEVEL.MEDIUM)
            why = "своей истории по предмету нет — проверить цену нечем"
        elseif verdict.outsideRange then
            level = Risk:Worse(level, Risk.LEVEL.MEDIUM)
            why = "цена вышла за всё, что я наблюдал"
        elseif verdict.days and verdict.days <= (MH.SHORT_SAMPLE_DAYS or 4) then
            level = Risk:Worse(level, Risk.LEVEL.MEDIUM)
            why = "наблюдений всего " .. verdict.days .. " "
                .. U.plural(verdict.days, "день", "дня", "дней")
        end
    elseif card.revenue then
        level = Risk:Worse(level, Risk.LEVEL.MEDIUM)
        why = "истории по этой цене у меня нет"
    end

    -- Возраст цены - отдельный повод. Старая цена может быть верной, но
    -- опираться на неё как на сегодняшнюю нельзя.
    local age = tonumber(origin.age)
    if age and age >= (ns.PRICE_STALE_SECONDS or 172800) then
        level = Risk:Worse(level, Risk.LEVEL.HIGH)
        why = "цене " .. (U.ageText(age) or "много времени")
            .. " — на аукционе с тех пор всё могло поменяться"
    elseif age and age >= (ns.PRICE_AGE_SAY_SECONDS or 86400) then
        level = Risk:Worse(level, Risk.LEVEL.MEDIUM)
        why = why or ("цена не сегодняшняя: " .. (U.ageText(age) or "давно"))
    end

    if card.conf == CONF.UNKNOWN then
        level = Risk:Worse(level, Risk.LEVEL.HIGH)
        -- Словами из общего словаря пустоты (ns.VOID), а не своей фразой: эта
        -- же причина объясняется игроку в карточке, в окне крафта и в
        -- настройках, и три разные формулировки одной причины он читает как
        -- три разные причины.
        why = why or U.voidWhy(ns.VOID.NO_PRICE)
    end
    return level, why
end

-- Правдоподобие ---------------------------------------------------------

-- Числа карточки, которые противоречат друг другу. Возвращает nil, когда всё
-- в порядке, иначе { code, text, ratio, detail }.
--
-- Сейчас здесь одна проверка - та, что уже один раз пропустила карточку игроку.
-- Место для остальных готово: добавление новой не требует правок ни в движке,
-- ни в самопроверке, потому что оба спрашивают этот один вход.
function Risk:Plausibility(card)
    if type(card) ~= "table" then return nil end
    if card.kind ~= ns.KIND.CRAFT_PROFIT and card.kind ~= ns.KIND.RESELL then
        return nil
    end
    local revenue = tonumber(card.revenue)
    local vendorPays = Risk:VendorFloor({ itemID = card.itemID, outputQty = 1 })
    if not (revenue and revenue > 0 and vendorPays and vendorPays > 0) then
        return nil
    end
    local ratio = revenue / vendorPays
    if ratio < Risk.VENDOR_RATIO_LIMIT then return nil end

    return {
        code = "revenue-far-above-vendor",
        ratio = ratio,
        revenue = revenue,
        vendor = vendorPays,
        text = string.format(
            "выручка %s против цены торговца %s — это в %s больше."
            .. " У крафта такого разрыва не бывает, поэтому самой цене я не верю:"
            .. " либо кто-то выставил лот с опечаткой, либо данные о предмете"
            .. " неполные. Проверьте цену на аукционе сами, прежде чем вкладываться",
            U.money(revenue), U.money(vendorPays), U.times(U.round(ratio))),
    }
end

-- Разрыв, который стоит упомянуть, но не повод не верить: между
-- VENDOR_RATIO_NOTE и VENDOR_RATIO_LIMIT. Возвращает { ratio, text } или nil.
function Risk:VendorRatioNote(card)
    if type(card) ~= "table" then return nil end
    if card.kind ~= ns.KIND.CRAFT_PROFIT and card.kind ~= ns.KIND.RESELL
       and card.kind ~= ns.KIND.ARBITRAGE then
        return nil
    end
    local revenue = tonumber(card.revenue)
    local vendorPays = Risk:VendorFloor({ itemID = card.itemID, outputQty = 1 })
    if not (revenue and revenue > 0 and vendorPays and vendorPays > 0) then
        return nil
    end
    local ratio = revenue / vendorPays
    if ratio < Risk.VENDOR_RATIO_NOTE or ratio >= Risk.VENDOR_RATIO_LIMIT then
        return nil
    end
    return {
        ratio = ratio,
        text = string.format(
            "выручка в %s больше цены торговца (%s) — наценка большая."
            .. " Так бывает, но весь расчёт висит на одной рыночной цене,"
            .. " и проверить её стоит до того, как вкладываться",
            U.times(U.round(ratio)), U.money(vendorPays)),
    }
end

-- СОМНЕНИЕ НА КАРТОЧКЕ ----------------------------------------------------
--
-- ОДНО МЕСТО НА ВСЕ СОМНЕНИЯ, ОТКУДА БЫ ОНИ НИ ПРИШЛИ.
--
-- Сомнений у аддона три источника: правдоподобие (выше), большой разрыв с ценой
-- торговца (выше) и самопроверки (Logic/SanityChecks.lua, два с лишним десятка
-- находок «про эту карточку»). До этого первые два дописывали текст руками и
-- по-разному, а третий не доходил до экрана вовсе: находка уезжала в файл, и
-- карточка с числом, которому аддон сам не верил, стояла вторым советом сверху
-- без единого слова об этом.
--
-- Теперь все трое кладут сомнение в card.doubts, а печатает его одна функция -
-- и печатает в трёх местах сразу, потому что ни одного из них по отдельности
-- недостаточно:
--
--   * ЗАГОЛОВОК ВЫГОДЫ. Его читают первым и часто единственным.
--   * ПЕРВАЯ ФРАЗА «ПОЧЕМУ», а не последняя. Строка «почему» на экране одна и
--     обрезается шириной окна (UI/Card.lua, SetWordWrap(false)): дописанное в
--     конец игрок не видит никогда. Именно так и вышло с краской - текст про
--     разрыв в 166 раз в карточке БЫЛ, в самом хвосте строки, за краем окна.
--   * МЕСТО В СПИСКЕ. tierOf в Logic/ActionEngine.lua опускает сомнительную
--     карточку ниже всего исполнимого, а ту, чьи числа не сходятся, - к
--     убыточным. С экрана не убирает ни ту, ни другую: разрыв может быть и
--     настоящим, и решать игроку.
--
-- Две ступени, и они отвечают на разные вопросы:
--   "doubt"    - «я бы это проверил». Число может быть настоящим.
--   "distrust" - «числа друг другу противоречат». Этому числу я не верю.
Risk.DOUBT_SOFT = "doubt"
Risk.DOUBT_DISTRUST = "distrust"
Risk.DOUBT_RANK = { doubt = 1, distrust = 2 }

-- Слово в заголовке выгоды. «сомнительно» стоит там с тех пор, как появилось
-- правдоподобие, и самопроверка ищет именно его (проверка 37), поэтому слово
-- не меняется.
Risk.DOUBT_MARK = { doubt = "под вопросом", distrust = "сомнительно" }

-- Чем начинается первая фраза «почему».
Risk.DOUBT_LEAD = {
    doubt = "Сам сомневаюсь: ",
    distrust = "Числа этой карточки не сходятся: ",
}

-- Что говорится игроку, когда находка написана не для него: индекс совета, код
-- причины, упрёк аддона самому себе. Подробности остаются в файле - на карточке
-- от такой находки нужен один вывод, и он здесь.
Risk.DOUBT_DEFECT_SAY = "моя собственная проверка нашла в числах этой карточки"
    .. " ошибку, поэтому опираться на них я бы не стал. Что именно не сошлось —"
    .. " в файле диагностики"

-- Заголовок карточки, повторённый в начале находки, на самой карточке не нужен:
-- он стоит строкой выше. Срезается простым сравнением, а не образцом: в
-- названиях предметов бывает всё, включая знаки образцов Lua.
function Risk:StripTitle(card, text)
    if type(text) ~= "string" then return text end
    local title = type(card) == "table" and card.title or nil
    if type(title) ~= "string" or title == "" then return text end
    for _, prefix in ipairs({ "«" .. title .. "»: ", "«" .. title .. "» " }) do
        if text:sub(1, #prefix) == prefix then
            return text:sub(#prefix + 1)
        end
    end
    return text
end

-- Дописать сомнение к карточке и перерисовать её. Повтор по тому же коду - это
-- одно сомнение: проверка может назвать карточку дважды за проход.
function Risk:AddDoubt(card, doubt)
    if type(card) ~= "table" or type(doubt) ~= "table" or doubt.code == nil then
        return nil
    end
    local list = card.doubts
    if not list then list = {}; card.doubts = list end
    local entry
    for _, d in ipairs(list) do
        if d.code == doubt.code then entry = d; break end
    end
    if not entry then
        entry = { code = doubt.code }
        list[#list + 1] = entry
    end
    entry.text = doubt.text or entry.text
    entry.scope = doubt.scope or entry.scope
    entry.level = doubt.level or entry.level
    entry.say = doubt.say or entry.say
    Risk:RenderDoubts(card)
    return entry
end

-- Адрес и формулировка находки, если их ещё нет. Адрес спрашивается у самих
-- проверок (SanityChecks.SCOPE), а не решается здесь: иначе перечень оказался
-- бы в двух местах и разошёлся.
local function normalizeDoubt(card, doubt)
    if not doubt.scope then
        doubt.scope = (ns.SanityChecks and ns.SanityChecks:Scope(doubt.code))
            or "defect"
    end
    if not doubt.level then
        doubt.level = (doubt.scope == "say") and Risk.DOUBT_SOFT or Risk.DOUBT_DISTRUST
    end
    if not doubt.say then
        doubt.say = (doubt.scope == "say")
            and Risk:StripTitle(card, doubt.text or "")
            or Risk.DOUBT_DEFECT_SAY
    end
    return doubt
end

-- Перерисовать карточку по её сомнениям. Идемпотентно: исходные заголовок и
-- текст запоминаются один раз, и всё собирается от них, сколько бы раз функцию
-- ни позвали.
function Risk:RenderDoubts(card)
    if type(card) ~= "table" then return nil end
    local list = card.doubts
    if type(list) ~= "table" or #list == 0 then return nil end
    if card.whyBase == nil then card.whyBase = card.why or "" end
    if card.benefitBase == nil then card.benefitBase = card.benefit end

    local worst, phrases, seen = nil, {}, {}
    for _, d in ipairs(list) do
        normalizeDoubt(card, d)
        if (Risk.DOUBT_RANK[d.level] or 0) > (Risk.DOUBT_RANK[worst] or 0) then
            worst = d.level
        end
        -- То, что карточка уже говорит своими словами, второй раз не печатается:
        -- ветка перепродажи, например, пишет свой приговор сама.
        if d.say ~= "" and not U.contains(card.whyBase, d.say) and not seen[d.say] then
            seen[d.say] = true
            -- Сомнения худшей ступени идут первыми: заголовок карточки помечен
            -- по худшей, и текст обязан начинаться с того же.
            if d.level == Risk.DOUBT_DISTRUST then
                table.insert(phrases, 1, d.say)
            else
                phrases[#phrases + 1] = d.say
            end
        end
    end
    card.doubtLevel = worst

    -- ЗАЧИН ОДИН, СКОЛЬКО БЫ СОМНЕНИЙ НИ БЫЛО. Пока зачин приписывался к
    -- каждому, карточка живого прогона начиналась с «Сам сомневаюсь: … Сам
    -- сомневаюсь: …» - два раза одно и то же вступление в строке, которая на
    -- экране всё равно обрезается. Остальные сомнения идут обычными фразами.
    local text = ""
    for i, say in ipairs(phrases) do
        local piece = (i == 1)
            and U.capitalize(U.endSentence((Risk.DOUBT_LEAD[worst] or "") .. say))
            or U.capitalize(U.endSentence(say))
        text = (text == "") and piece or (text .. " " .. piece)
    end
    if text ~= "" and card.whyBase ~= "" then
        card.why = text .. " " .. card.whyBase
    elseif text ~= "" then
        card.why = text
    else
        card.why = card.whyBase
    end

    local mark = Risk.DOUBT_MARK[worst]
    local base = card.benefitBase
    if mark then
        if base == nil or base == "" then
            card.benefit = mark
        elseif U.contains(base, Risk.DOUBT_MARK.distrust)
            or U.contains(base, Risk.DOUBT_MARK.doubt) then
            card.benefit = base
        else
            card.benefit = mark .. ": " .. base
        end
    end

    -- Достоверность падает ровно на ту ступень, которой сомнение стоит: «я бы
    -- проверил» - это оценка, «числа не сходятся» - это «неизвестно».
    if worst == Risk.DOUBT_DISTRUST then
        card.conf = CONF.UNKNOWN
    elseif worst == Risk.DOUBT_SOFT then
        card.conf = U.worstConf(card.conf or CONF.UNKNOWN, CONF.ESTIMATE)
    end
    return card.doubtLevel
end

-- Оценка целиком --------------------------------------------------------

local function shareText(share)
    if not share then return nil end
    if share >= 10 then return "в " .. U.times(U.round(share)) .. " больше, чем у вас есть" end
    if share >= 1 then
        return "это " .. U.pct(share) .. " от всего, что у вас есть"
    end
    return "это " .. U.pct(share) .. " ваших денег"
end

-- Полная оценка одной карточки. snap нужен только ради кошелька, и когда его
-- нет, доля кошелька просто не называется - вместо выдуманной.
function Risk:Assess(card, snap)
    if type(card) ~= "table" then return nil end

    local money = snap and tonumber(snap.money) or nil
    local capital = Risk:Capital(card)
    local share
    if capital and capital > 0 and money and money > 0 then
        share = capital / money
    end

    local buyerRisk, buyerWhy = Risk:BuyerRisk(card)
    local priceRisk, priceWhy = Risk:PriceRisk(card)
    local vendorFloor = Risk:VendorFloor(card)

    -- Максимальный убыток. Вложенное минус то, за что результат заведомо
    -- заберёт торговец. Для карточки, которая ничего не производит (покупка
    -- материалов под другой совет), пола нет по определению: материал не товар.
    local maxLoss
    if capital and capital > 0 then
        if buyerRisk == Risk.LEVEL.NONE and card.revenue then
            -- Покупатель гарантирован: потерять можно только разницу, и если
            -- выручка выше вложенного, то терять нечего.
            maxLoss = math.max(0, capital - math.min(capital, tonumber(card.revenue) or 0))
        elseif vendorFloor then
            maxLoss = math.max(0, capital - vendorFloor)
        else
            maxLoss = capital
        end
    elseif capital == 0 then
        maxLoss = 0
    end

    local capitalRisk = Risk.LEVEL.NONE
    if capital and capital > 0 then
        capitalRisk = Risk.LEVEL.LOW
        if share and share > 1 then capitalRisk = Risk.LEVEL.HIGH
        elseif share and share >= Risk.CAPITAL_HEAVY_SHARE then capitalRisk = Risk.LEVEL.HIGH
        elseif share and share >= Risk.CAPITAL_NOTABLE_SHARE then capitalRisk = Risk.LEVEL.MEDIUM
        elseif not money then capitalRisk = Risk.LEVEL.MEDIUM end
    end

    local level = Risk:Worse(Risk:Worse(capitalRisk, buyerRisk or Risk.LEVEL.NONE),
        priceRisk or Risk.LEVEL.NONE)

    local plausibility = Risk:Plausibility(card)
    if plausibility then level = Risk.LEVEL.HIGH end

    -- Фраза для карточки. Собирается из того, что действительно известно:
    -- ни одного пункта «неизвестно» в ней не появляется ради симметрии.
    local bits = {}
    if capital and capital > 0 then
        local line = "вложить " .. U.money(capital)
        if money then
            if capital > money then
                line = line .. " — у вас " .. U.money(money)
                    .. ", этого не хватает"
                if share then line = line .. " (" .. (shareText(share) or "") .. ")" end
            elseif share and share >= Risk.CAPITAL_NOTABLE_SHARE then
                line = line .. " из " .. U.money(money)
                    .. " (" .. (shareText(share) or "") .. ")"
            end
        end
        bits[#bits + 1] = line
    elseif capital == 0 then
        bits[#bits + 1] = "вкладывать ничего не нужно"
    end
    if maxLoss and maxLoss > 0 then
        bits[#bits + 1] = "в худшем случае потеряете " .. U.money(maxLoss)
            .. (vendorFloor and (" (торговец заберёт за " .. U.money(vendorFloor) .. ")")
                or " — заберёт это только рынок, торговец ничего не даёт")
    elseif maxLoss == 0 and capital and capital > 0 then
        bits[#bits + 1] = "потерять нечего: результат заведомо стоит дороже вложенного"
    end
    if buyerWhy then bits[#bits + 1] = buyerWhy end
    if priceWhy then bits[#bits + 1] = priceWhy end

    return {
        level = level,
        label = Risk.LEVEL_LABEL[level],
        capital = capital,
        capitalShare = share,
        capitalRisk = capitalRisk,
        overWallet = (capital ~= nil and money ~= nil and capital > money) or false,
        money = money,
        buyerRisk = buyerRisk,
        buyerWhy = buyerWhy,
        priceRisk = priceRisk,
        priceWhy = priceWhy,
        vendorFloor = vendorFloor,
        maxLoss = maxLoss,
        plausibility = plausibility,
        text = (#bits > 0) and (U.capitalize(table.concat(bits, "; ")) .. ".") or nil,
    }
end

-- СКАЗАНО ЛИ НА КАРТОЧКЕ, ЧТО ДЕНЕГ НЕ ХВАТАЕТ.
--
-- Один предикат на весь аддон, и это важно: его спрашивают ДВОЕ - этот модуль
-- (дописать фразу, если её нет) и самопроверка (пожаловаться, если её нет).
-- Пока у них были свои представления, они расходились: ветка покупок писала
-- «это в 4 раза больше, чем у вас есть», что игроку говорит ровно то, что нужно,
-- а самопроверка такой формулировки не знала и ругалась на исправную карточку -
-- четыре ложных срабатывания за пересчёт на живых данных.
--
-- Любая из этих формулировок считается сказанной:
--   «...хватает» / «Не хватает N»      - прямая
--   «в N раз больше, чем у вас есть»   - ветка покупок и out-of-reach
--   «цены нет»                         - сумму назвать нечем, и это тоже честно
Risk.UNAFFORDABLE_PHRASES = {
    "хватает",
    "больше, чем у вас есть",
    "цены нет",
    "не назову",
}

function Risk:SaysUnaffordable(card)
    if type(card) ~= "table" then return false end
    local text = tostring(card.need or "") .. " " .. tostring(card.why or "")
    for _, phrase in ipairs(Risk.UNAFFORDABLE_PHRASES) do
        if U.contains(text, phrase) then return true end
    end
    return false
end

-- Приложить оценку к карточке -------------------------------------------
--
-- Вызывается движком ОДИН раз на карточку, до ранжирования. Делает три вещи и
-- ничего больше: кладёт оценку в card.risk, и если числа карточки друг другу
-- противоречат - помечает её сомнительной, опускает достоверность и вписывает
-- предупреждение в заголовок выгоды и в текст. Никакого «тихого» поведения:
-- карточка остаётся на экране, просто перестаёт выглядеть надёжной.
function Risk:Attach(card, snap)
    if type(card) ~= "table" then return nil end
    local risk = Risk:Assess(card, snap)
    card.risk = risk
    if not risk then return nil end

    -- Сомнительную карточку метит одна функция - Risk:RenderDoubts: заголовок,
    -- первая фраза «почему», достоверность. Раньше это делалось здесь руками, а
    -- в ветке перепродажи - ещё раз и своими словами; два набора формулировок на
    -- одно состояние расходятся, и уже расходились.
    local p = risk.plausibility
    if p then
        card.suspect = p
        Risk:AddDoubt(card, { code = p.code or "numbers-do-not-add-up",
            scope = "say", level = Risk.DOUBT_DISTRUST,
            text = p.text, say = p.text })
        if ns.Diag then ns.Diag:Count("cards.suspect") end
        return risk
    end

    -- Пометить карточку сомнительной может и сама ветка - так делает
    -- перепродажа, когда наценка невозможна (Engine:AddArbitrageCards). Печатает
    -- пометку всё равно эта функция: пока ветка писала свой текст сама, на одно
    -- состояние было два набора формулировок, и правка одного не меняла другого.
    if card.suspect then
        Risk:AddDoubt(card, {
            code = card.suspect.code or "numbers-do-not-add-up",
            scope = "say", level = Risk.DOUBT_DISTRUST,
            text = card.suspect.text, say = card.suspect.text })
    end

    -- НЕ ПО КАРМАНУ - СКАЗАНО НА КАРТОЧКЕ, А НЕ ТОЛЬКО ПОСЧИТАНО.
    --
    -- У игрока около пяти золотых, и совет, требующий больше, обязан это
    -- говорить явно - это прямое требование, и самопроверка (check 12) его
    -- сторожит. Раньше текст дописывала только ветка покупок и только при
    -- разрыве больше трёх раз; все остальные денежные карточки - крафт,
    -- развилка путей, перепродажа - молчали, и на живых данных самопроверка
    -- ловила четыре таких карточки за пересчёт. Теперь это делается ОДИН раз
    -- здесь, для любой карточки с ценой, и новая ветка не может об этом забыть.
    if risk.overWallet and risk.money then
        if not Risk:SaysUnaffordable(card) then
            local short = math.max(0, (risk.capital or 0) - risk.money)
            local note = "Денег на это не хватает: нужно "
                .. U.money(risk.capital) .. ", у вас " .. U.money(risk.money)
                .. " — не хватает " .. U.money(short) .. "."
            card.need = (card.need and card.need ~= "")
                and (card.need .. " " .. note) or note
            card.unaffordableSaid = true
        end
    end

    -- ВЫРУЧКА ВЫШЕ ВЕНДОРНОГО ПОТОЛКА. Тем же механизмом сомнения, что и всё
    -- остальное: ступень «я бы это проверил», текст словами для игрока, место в
    -- списке - ниже исполнимого. Карточка с экрана не убирается: надбавка за
    -- готовое бывает настоящей, и решать игроку.
    local ceilingDoubt = Risk:CeilingDoubt(card)
    if ceilingDoubt then
        card.ceilingDoubt = ceilingDoubt
        Risk:AddDoubt(card, { code = ceilingDoubt.code,
            scope = "say", level = Risk.DOUBT_SOFT,
            text = ceilingDoubt.text, say = ceilingDoubt.text })
        if ns.Diag then ns.Diag:Count("cards.aboveVendorCeiling") end
    end

    -- Разрыв в сотни раз: верим, но упоминаем и снимаем одну ступень
    -- достоверности. Не поверить тут нельзя - такое бывает на настоящем рынке -
    -- а промолчать нечестно: весь расчёт висит на одной рыночной цене.
    local note = Risk:VendorRatioNote(card)
    if note then
        card.vendorRatioNote = note
        -- ЗДЕСЬ ТЕКСТ ДОПИСЫВАЛСЯ В КОНЕЦ «ПОЧЕМУ», И ЭТО БЫЛО РАВНО МОЛЧАНИЮ.
        --
        -- Живая находка: «На продажу: Небесно-голубая краска», разрыв в 166 раз.
        -- Самопроверка писала про него в файл, а на карточке он БЫЛ - последней
        -- фразой строки, которая на экране обрезается шириной окна. Игрок видел
        -- заголовок «оценка ~1з 22с» без единой оговорки и карточку вторым
        -- советом сверху. Теперь оговорка идёт первой фразой, стоит в самом
        -- заголовке и опускает карточку ниже исполнимых советов.
        Risk:AddDoubt(card, { code = "revenue-far-above-vendor",
            scope = "say", level = Risk.DOUBT_SOFT,
            text = note.text, say = note.text })
        if ns.Diag then ns.Diag:Count("cards.wideVendorGap") end
    end
    return risk
end

-- Одна короткая строка для панели и подсказки: «риск средний · вложить 1з ·
-- потерять до 96с». Возвращает nil, когда оценивать нечего.
function Risk:Badge(risk)
    if type(risk) ~= "table" then return nil end
    local bits = { Risk.LEVEL_LABEL[risk.level] or "риск неизвестен" }
    if risk.capital and risk.capital > 0 then
        bits[#bits + 1] = "вложить " .. U.money(risk.capital)
    end
    if risk.maxLoss and risk.maxLoss > 0 then
        bits[#bits + 1] = "потерять до " .. U.money(risk.maxLoss)
    end
    return table.concat(bits, " · ")
end

return Risk
