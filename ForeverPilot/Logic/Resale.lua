-- ForeverPilot / Logic/Resale.lua
--
-- ПЕРЕКУПИТЬ ЛОТ ЗАМЕТНО НИЖЕ РЫНКА.
--
-- САМЫЙ ОПАСНЫЙ СОВЕТ, КОТОРЫЙ ЭТОТ АДДОН МОЖЕТ ДАТЬ, и формулировка задания
-- называет причину прямо: «НЕ рекомендовать предмет только потому, что он
-- дешевле соседнего лота».
--
-- Почему это опасно. «Дешевле рынка» бывает трёх совершенно разных видов:
--   1. кто-то ошибся при выставлении - настоящая возможность;
--   2. рынок на этот предмет упал, и «рынок» в нашей памяти устарел - тогда
--      покупка это убыток, а не выгода;
--   3. предмет никто не покупает вообще, и дешёвый лот стоит месяц - тогда
--      деньги просто заморожены.
-- Отличить их можно только по ИСТОРИИ и по ОБЪЁМУ, и поэтому ни то, ни другое
-- здесь не опционально: без своей истории по предмету совета не будет.
--
-- ЧТО СЧИТАЕТСЯ, И ПОЧЕМУ КАЖДОЕ:
--   история    - чтобы «ниже рынка» значило «ниже того, что я видел», а не
--                «ниже соседнего лота»;
--   разброс    - предмет, который гуляет втрое, «дешевле рынка» бывает каждый
--                день, и это не возможность;
--   объём      - сколько лотов было в наблюдениях: один лот в день это не
--                рынок, это случай;
--   ликвидность- сколько дней из наблюдённых предмет вообще появлялся: вещь,
--                которую видели раз в неделю, перепродавать некому;
--   комиссия   - 5% сбора при продаже;
--   залог      - его платят при выставлении, и он не возвращается, если лот
--                не продался;
--   риск и максимальный убыток - через Logic/Risk.lua, как у всех денежных.
--
-- Аддон НИЧЕГО не покупает и не выставляет: он считает и говорит словами.
local ADDON, ns = ...

local U = ns.Util
local Api = ns.Api
local CONF = ns.CONF

local RS = {}
ns.Resale = RS

-- Сколько дней своей истории нужно, чтобы вообще иметь мнение. Один день - это
-- не история, а одно число; на двух можно отличить «дёшево» от «обычно».
RS.MIN_HISTORY_DAYS = 2
-- Насколько ниже наблюдённого должен стоять лот. Полцены - это уже не шум
-- рынка, а либо ошибка продавца, либо что-то, чего мы не знаем.
RS.MIN_DISCOUNT_SHARE = 0.40
-- Разброс, после которого предмет считается неустойчивым: если максимум больше
-- минимума втрое, «ниже рынка» у него бывает каждый вторник.
RS.MAX_SPREAD_RATIO = 3.0
-- И минимальная прибыль, ниже которой не стоит и начинать.
RS.MIN_PROFIT = 2000
RS.MAX_CANDIDATES = 250

-- Ликвидность ------------------------------------------------------------
--
-- Из своей истории: в скольких днях из наблюдённых предмет вообще имел цену.
-- Это единственная мера «его покупают», которая у нас есть: число лотов
-- Auctionator через стабильный API не отдаёт.
--   { days, span, coverage, liquid, text }
function RS:Liquidity(itemID)
    local st = ns.MarketHistory and ns.MarketHistory:Stats(itemID) or nil
    if not st then
        return { days = 0, liquid = false,
                 text = "своей истории по предмету нет — про ликвидность сказать нечего" }
    end
    local span = (st.latestDay or 0) - (st.firstDay or 0) + 1
    local coverage = (span > 0) and (st.days / span) or 0
    -- Появлялся меньше чем в половине дней - значит лоты редкие, и быстро
    -- перепродать не выйдет.
    local liquid = (st.days >= RS.MIN_HISTORY_DAYS) and (coverage >= 0.5)
    local text
    if st.days < RS.MIN_HISTORY_DAYS then
        text = "наблюдений всего " .. st.days .. " — этого мало, чтобы судить"
    elseif liquid then
        text = "предмет был на аукционе " .. st.days .. " из " .. span .. " "
            .. U.plural(span, "дня", "дней", "дней") .. " наблюдений"
    else
        text = "предмет появлялся на аукционе редко (" .. st.days .. " из "
            .. span .. ") — быстро перепродать, скорее всего, не выйдет"
    end
    return { days = st.days, span = span, coverage = coverage,
             liquid = liquid, text = text }
end

-- Разброс: во сколько раз максимум больше минимума.
function RS:Spread(itemID)
    local st = ns.MarketHistory and ns.MarketHistory:Stats(itemID) or nil
    if not st or st.min == nil or st.min <= 0 then return nil end
    local ratio = st.max / st.min
    return {
        ratio = ratio, min = st.min, max = st.max, median = st.median,
        stable = (ratio <= RS.MAX_SPREAD_RATIO),
        text = (st.min == st.max)
            and ("все наблюдения дали одно и то же: " .. U.money(st.min))
            or string.format("разброс %s..%s, это в %s",
                U.money(st.min), U.money(st.max), U.times(ratio) or "несколько раз"),
    }
end

-- Одна возможность --------------------------------------------------------

-- `live` - цена лота сейчас. Передаётся отдельно, потому что Price:Sell её
-- уже мог подменить медианой (если история назвала лот выбросом), а здесь
-- нужна именно живая.
function RS:Evaluate(itemID, live)
    itemID = tonumber(itemID)
    if not itemID then return nil, "no-id" end
    live = tonumber(live) or Api:AuctionPrice(itemID)
    if not live or live <= 0 then return nil, "no-live-price" end

    -- 0. ВЕНДОРНЫЙ ПОТОЛОК. «Дешевле рынка» ничего не значит, если тот же
    --    предмет лежит у торговца с неограниченным запасом дешевле этого лота:
    --    тогда выгодная покупка - не лот, а полка, а перепродавать это некому
    --    по той же причине. Это четвёртый вид «дешевле рынка», которого в шапке
    --    файла не было, и единственный, который виден не по истории.
    --
    --    Отказ НАЗВАН (funnel:Drop ниже печатает причину): молча пропавший
    --    совет - это то самое тихое поведение, от которого аддон отказался.
    local ceiling = ns.PriceProvider and ns.PriceProvider:Ceiling(itemID) or nil
    if ceiling and ceiling.ceiling and live >= ceiling.ceiling then
        return nil, "vendor-cheaper", ceiling.text
    end

    -- 1. ИСТОРИЯ - ОБЯЗАТЕЛЬНА. Без неё «ниже рынка» не определено.
    local st = ns.MarketHistory and ns.MarketHistory:Stats(itemID) or nil
    if not st then return nil, "no-history" end
    if st.days < RS.MIN_HISTORY_DAYS then return nil, "history-too-short" end

    -- 2. НАСКОЛЬКО НИЖЕ - от медианы наблюдённого, а не от соседнего лота.
    local reference = st.median
    if not reference or reference <= 0 then return nil, "no-reference" end
    local discount = (reference - live) / reference
    if discount < RS.MIN_DISCOUNT_SHARE then return nil, "not-cheap-enough" end

    -- 3. РАЗБРОС. Предмет, который гуляет втрое, «дешёвый» каждый день.
    local spread = RS:Spread(itemID)
    if spread and not spread.stable then return nil, "too-volatile" end

    -- 4. ЛИКВИДНОСТЬ. Перепродавать некому - значит это не сделка.
    local liq = RS:Liquidity(itemID)
    if not liq.liquid then return nil, "illiquid" end

    -- 5. ДЕНЬГИ. Продать можно по медиане (обещать максимум нельзя), минус
    -- сбор аукциона, минус залог.
    local cut = ns.PriceProvider.AH_CUT or 0.05
    local gross = reference * (1 - cut)
    local deposit, depConf, depText = ns.Risk and ns.Risk:Deposit(
        { itemID = itemID, outputQty = 1 }, 1) or nil
    local profit = gross - live - (deposit or 0)
    if profit < RS.MIN_PROFIT then return nil, "too-small" end

    local info = Api:ItemInfo(itemID)

    -- ОБЛИК. Перепродажа - это «купить и продать снова», то есть вещь через
    -- руки игрока пройдёт и уйдёт. Лот с аукциона привязанным не бывает (своё
    -- привязанное туда не выставить), поэтому ответ про привязку здесь известен
    -- точно: НЕ привязана - и он едет с находкой. Сам вопрос задаётся у
    -- карточки (Logic/ActionEngine.lua, Engine:AddResaleCards): кандидатов
    -- перебирается две с половиной сотни, а советом становится один.
    return {
        itemID = itemID,
        name = (info and info.name) or U.itemFallbackName(itemID),
        link = info and info.link or nil,
        texture = info and info.texture or nil,
        bound = false,
        live = live,
        reference = reference,
        discount = discount,
        resellAt = reference,
        gross = gross,
        cut = cut,
        deposit = deposit, depositConf = depConf, depositText = depText,
        profit = profit,
        spread = spread,
        liquidity = liq,
        historyDays = st.days,
        -- Достоверность: не выше ESTIMATE. Всё это стоит на двух-трёх днях
        -- наблюдений на молодом сервере, и называть такое «из кеша» нельзя.
        conf = (st.days >= 5) and CONF.CACHED or CONF.ESTIMATE,
    }
end

function RS:Opportunities(snap)
    local out = {}
    local funnel = ns.Diag and ns.Diag:Funnel("resale") or nil
    local cfg = ns.Config and ns.Config:Get() or nil
    local n = 0
    -- Круг поиска - предметы, по которым есть СВОЯ история: других мы и так
    -- оценить не можем, так что обходить больше нечего.
    local ids = {}
    for itemID in pairs((cfg and cfg.priceHistory) or {}) do
        local id = tonumber(itemID)
        if id then ids[#ids + 1] = id end
    end
    table.sort(ids)
    for _, itemID in ipairs(ids) do
        n = n + 1
        if n > RS.MAX_CANDIDATES then break end
        local item = { itemID = itemID, name = tostring(itemID) }
        if funnel then funnel:In(item) end
        local opp, why, detail = RS:Evaluate(itemID)
        if opp then
            out[#out + 1] = opp
        elseif funnel then
            funnel:Drop(why or "unknown", item, detail)
        end
    end
    table.sort(out, function(a, b)
        if a.profit ~= b.profit then return a.profit > b.profit end
        return a.itemID < b.itemID
    end)
    if funnel then funnel:Finish(#out) end
    -- Ноль предметов с историей - это «сравнивать не с чем», а не «среди 0
    -- предметов ни одного лота ниже рынка».
    RS.lastReason = (#out == 0)
        and ((#ids == 0)
            and "своей истории цен у меня пока нет ни по одному предмету — сравнивать лоты не с чем"
            or ("ни одного лота заметно ниже рынка среди " .. #ids .. " "
                .. U.plural(#ids, "предмета", "предметов", "предметов")
                .. ", по которым у меня есть своя история"))
        or nil
    return out
end

-- Текст -------------------------------------------------------------------

function RS:WhyText(opp)
    local bits = {}
    bits[#bits + 1] = "лот стоит " .. U.money(opp.live)
        .. ", а по моим наблюдениям этот предмет обычно "
        .. U.money(opp.reference) .. " — это на " .. U.pct(opp.discount) .. " дешевле"
    if opp.spread then bits[#bits + 1] = opp.spread.text end
    bits[#bits + 1] = opp.liquidity.text
    bits[#bits + 1] = "перепродать считаю по " .. U.money(opp.reference)
        .. ": минус сбор " .. U.pct(opp.cut)
        .. (opp.deposit and (", минус " .. (opp.depositText or ("залог " .. U.money(opp.deposit)))) or "")
        .. " — остаётся " .. U.moneyDelta(opp.profit)
    return U.capitalize(table.concat(bits, "; ")) .. "."
end

return RS
