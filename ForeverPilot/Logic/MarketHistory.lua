-- ForeverPilot / Logic/MarketHistory.lua
--
-- "Is today's price normal for this item?"
--
-- WHY THIS FILE EXISTS. The realm opened on 4 November 2026, so nobody has a
-- price history for it and the market is thin enough that a single listing can
-- be the whole market. On 17 November Auctionator's cheapest listing for Linen
-- Boots was 50200 copper. The seven days before that, in the same database,
-- were 200, 200, 200, 180, 210, 244 and 300 copper, on roughly a hundred
-- listings a day instead of two. The addon took the 50200, called it the
-- market, put "На продажу: Льняные сапоги, +4з 74с" at the top of the list, and
-- the player listed the boots at 5 gold on the strength of it.
--
-- One absurd listing, 167 times the going rate, and nothing in the addon was
-- looking. That is what this module is for, and the thresholds below are chosen
-- so that THAT case is caught.
--
-- WHAT IT READS. The addon's own daily snapshot, ForeverPilotDB.priceHistory:
-- one price per item per day, written once a day since the first login. That is
-- a deliberately modest source - on this account it is two days deep for 290
-- items - and the honesty rule follows from it: a short sample is reported as a
-- short sample, and a short sample needs a much bigger gap before this module
-- is willing to call a live price wrong.
--
-- WHAT IT DOES NOT DO. It does not forecast. "It was 200 for a week" supports
-- "50200 is not the market"; it does not support "it will be 200 tomorrow", so
-- nothing here predicts a price. It does not read Auctionator's own per-day
-- history either: that lives inside a CBOR blob in its SavedVariables with no
-- documented accessor, and guessing at an internal API is exactly the kind of
-- thing that breaks silently on the next update.
local ADDON, ns = ...

local U = ns.Util
local CONF = ns.CONF

local MH = {}
ns.MarketHistory = MH

-- How far a live price may sit from the item's own record before we stop
-- believing it, by how many days we have to compare against.
--
-- A single observation is weak evidence, so it takes a tenfold gap to overrule
-- a live price on one day of history; a week of agreement is strong, so three
-- times is enough. The 167x case clears every one of these, which is the point:
-- the thresholds are generous and it was still obvious.
MH.OUTLIER_FACTOR = {
    [0] = math.huge,   -- no history: no opinion
    [1] = 10.0,
    [2] = 5.0,
    [3] = 5.0,
    [4] = 5.0,
}
MH.OUTLIER_FACTOR_LONG = 3.0   -- five days or more

-- Below this a sample is described to the player as short, whatever the verdict.
MH.SHORT_SAMPLE_DAYS = 4

function MH:FactorFor(days)
    days = tonumber(days) or 0
    if days <= 0 then return math.huge end
    if days >= 5 then return MH.OUTLIER_FACTOR_LONG end
    return MH.OUTLIER_FACTOR[days] or MH.OUTLIER_FACTOR_LONG
end

-- Statistics -------------------------------------------------------------

-- Everything we know about one item's recorded prices.
--   { days, min, max, median, mean, first, latest, firstDay, latestDay, series }
-- nil when nothing has been recorded for it - which is different from an empty
-- table, and callers have to tell those apart.
function MH:Stats(itemID)
    if not itemID then return nil end
    local bucket = ns.Config and ns.Config:PriceHistoryFor(itemID)
    if type(bucket) ~= "table" then return nil end

    local days, values = {}, {}
    for day, copper in pairs(bucket) do
        local d, c = tonumber(day), tonumber(copper)
        if d and c and c > 0 then
            days[#days + 1] = d
            values[d] = c
        end
    end
    if #days == 0 then return nil end
    table.sort(days)

    local series, sorted, sum = {}, {}, 0
    for i, d in ipairs(days) do
        series[i] = { day = d, copper = values[d] }
        sorted[i] = values[d]
        sum = sum + values[d]
    end
    table.sort(sorted)

    local n = #sorted
    local median
    if n % 2 == 1 then
        median = sorted[(n + 1) / 2]
    else
        -- Even sample: the lower of the two middles, not their average. An
        -- average invents a price that was never observed, and every number
        -- this module hands out should be one the game actually showed.
        median = sorted[n / 2]
    end

    return {
        days = n,
        min = sorted[1],
        max = sorted[n],
        median = median,
        mean = sum / n,
        first = values[days[1]],
        latest = values[days[n]],
        firstDay = days[1],
        latestDay = days[n],
        series = series,
    }
end

-- Direction of travel across the recorded span. Descriptive only: this says
-- where the price HAS been, never where it is going.
--   { direction = "up" | "down" | "flat", changePct, from, to, days }
function MH:Trend(itemID)
    local st = self:Stats(itemID)
    if not st or st.days < 2 then return nil end
    local from, to = st.first, st.latest
    local changePct = U.div(to - from, from, 0) * 100
    local direction = "flat"
    -- A tenth of the starting price is the smallest move worth a word; below
    -- that, on a market this thin, it is noise.
    if changePct > 10 then direction = "up"
    elseif changePct < -10 then direction = "down" end
    return {
        direction = direction, changePct = changePct,
        from = from, to = to, days = st.days,
        span = (st.latestDay or 0) - (st.firstDay or 0),
    }
end

-- Verdict ----------------------------------------------------------------

MH.FLAG = {
    NO_HISTORY   = "NO_HISTORY",
    TYPICAL      = "TYPICAL",
    HIGH_OUTLIER = "HIGH_OUTLIER",
    LOW_OUTLIER  = "LOW_OUTLIER",
}

MH.FLAG_LABEL = {
    NO_HISTORY   = "истории нет",
    TYPICAL      = "обычная цена",
    HIGH_OUTLIER = "нетипично высокая",
    LOW_OUTLIER  = "нетипично низкая",
}

local function sampleText(days, span)
    if days <= 0 then return "своей истории по этому предмету у меня нет" end
    if days == 1 then
        return "наблюдение всего одно — сравнивать почти не с чем"
    end
    local text = days .. " " .. U.plural(days, "день", "дня", "дней") .. " наблюдений"
    if days <= MH.SHORT_SAMPLE_DAYS then
        text = text .. " (выборка короткая: сервер молодой, истории ещё мало)"
    end
    return text
end

-- How to describe what we saw. ONE observation is not a range, and printing it
-- as "3з 49с..3з 49с" was the addon inventing a spread out of a single point -
-- which it then claimed a price of 2з 85с fell inside.
local function seenText(st)
    if st.days == 1 then
        return "единственное наблюдение — " .. U.money(st.min)
    end
    if st.min == st.max then
        return "все " .. st.days .. " "
            .. U.plural(st.days, "наблюдение", "наблюдения", "наблюдений")
            .. " дали одно и то же: " .. U.money(st.min)
    end
    return "наблюдённый разброс " .. U.money(st.min) .. ".." .. U.money(st.max)
end

-- Is `live` a believable price for this item?
--   { flag, ratio, days, median, min, max, text, factor }
-- `ratio` is how many times the live price exceeds the recorded maximum (for a
-- high outlier) or how many times the recorded minimum exceeds it (for a low
-- one); 1 means "inside the observed range".
function MH:Verdict(itemID, live)
    live = tonumber(live)
    local st = self:Stats(itemID)

    if not st then
        return {
            flag = MH.FLAG.NO_HISTORY, days = 0, ratio = 1,
            text = sampleText(0),
        }
    end
    if not live or live <= 0 then
        return {
            flag = MH.FLAG.NO_HISTORY, days = st.days, ratio = 1,
            median = st.median, min = st.min, max = st.max,
            text = "живой цены нет, сравнивать нечего. " .. U.capitalize(sampleText(st.days)),
        }
    end

    local factor = self:FactorFor(st.days)
    local highRatio = U.div(live, st.max, 1)
    local lowRatio = U.div(st.min, live, 1)

    local flag, ratio = MH.FLAG.TYPICAL, 1
    if highRatio >= factor then
        flag, ratio = MH.FLAG.HIGH_OUTLIER, highRatio
    elseif lowRatio >= factor then
        flag, ratio = MH.FLAG.LOW_OUTLIER, lowRatio
    end

    -- OUTSIDE THE RANGE IS NOT THE SAME AS AN OUTLIER, and conflating the two
    -- is what made the card lie. The outlier test only fires past several times
    -- the extreme; everything short of that was called typical and the sentence
    -- "укладывается в наблюдённый разброс" was printed regardless. On the
    -- player's screen that produced "2з 85с укладывается в наблюдённый разброс
    -- 3з 49с..3з 49с", which is false twice over: the price is below the range,
    -- and a single observation is not a range at all.
    local above = live > st.max
    local below = live < st.min
    local outside = above or below
    local degenerate = (st.days == 1) or (st.min == st.max)

    -- ВТОРАЯ ФРАЗА НАЧИНАЕТСЯ С БОЛЬШОЙ БУКВЫ, И БЕЗ КРИКА. Оговорка о выборке
    -- приклеивалась после точки как была - «…54с 97м. наблюдение всего одно»,
    -- а «выше» и «ниже» стояли заглавными посреди фразы.
    local sample = U.capitalize(sampleText(st.days))
    local text
    if flag == MH.FLAG.HIGH_OUTLIER then
        text = string.format(
            "сейчас %s — это в %s больше, чем я когда-либо видел (%s). %s",
            U.money(live), MH:TimesText(ratio), seenText(st), sample)
    elseif flag == MH.FLAG.LOW_OUTLIER then
        text = string.format(
            "сейчас %s — это в %s меньше, чем я когда-либо видел (%s). %s",
            U.money(live), MH:TimesText(ratio), seenText(st), sample)
    elseif above then
        -- «Выше всего, что я видел» про одну-единственную цену - громко;
        -- тогда так и сказано: выше той цены, что была.
        text = string.format(degenerate
                and "сейчас %s — выше той цены, что я видел (%s). %s"
                or "сейчас %s — это выше всего, что я видел (%s). %s",
            U.money(live), seenText(st), sample)
    elseif below then
        text = string.format(degenerate
                and "сейчас %s — ниже той цены, что я видел (%s). %s"
                or "сейчас %s — это ниже всего, что я видел (%s). %s",
            U.money(live), seenText(st), sample)
    elseif degenerate then
        -- Inside a range of one point means equal to it.
        text = string.format("сейчас %s, ровно как %s. %s",
            U.money(live), seenText(st), sample)
    else
        text = string.format("%s укладывается в %s. %s",
            U.money(live), seenText(st), sample)
    end

    return {
        flag = flag, ratio = ratio, days = st.days, factor = factor,
        median = st.median, min = st.min, max = st.max,
        latest = st.latest, live = live,
        outsideRange = outside, aboveRange = above, belowRange = below,
        degenerate = degenerate,
        text = text,
    }
end

-- «в 167 раз», «в 22 раза», «в 2,3 раза» - число вместе со словом «раз».
--
-- Раньше число и окончание собирались порознь (RatioText и RatioSuffix), и
-- окончание было неверным для всего, что не кончается на единицу: «в 167
-- раза», «в 5 раза». Теперь слово согласует одно место на весь аддон - U.times.
-- Десять и больше - без дробной части: такому грубому отношению она ни к чему.
function MH:TimesText(ratio)
    ratio = tonumber(ratio) or 1
    return U.times((ratio >= 10) and U.round(ratio) or ratio) or "несколько раз"
end

-- The price advice should actually use ------------------------------------
--
-- Returns copper, confidence (or nil to leave it alone), explanation, verdict.
--
-- The asymmetry is deliberate, and it is about which way a mistake hurts:
--
--   A live price far ABOVE the record is replaced by the median, because
--   believing it tells the player to go and do something on the strength of a
--   number that is almost certainly one person's typo. That is the mistake that
--   already happened.
--
--   A live price far BELOW the record is kept, because for a SALE a low
--   estimate only understates the profit, and the honest conservative answer is
--   the one that does not promise anything. It is still flagged, because the
--   same observation is a buying opportunity and the resale branch wants it.
function MH:Expected(itemID, live)
    local verdict = self:Verdict(itemID, live)
    live = tonumber(live)

    if verdict.flag == MH.FLAG.HIGH_OUTLIER then
        local note = string.format(
            "считаю по истории (%s), а не по сегодняшнему лоту: %s",
            U.money(verdict.median), verdict.text)
        return verdict.median, CONF.ESTIMATE, note, verdict
    end
    if verdict.flag == MH.FLAG.LOW_OUTLIER then
        return live, CONF.ESTIMATE,
            "беру сегодняшнюю цену как есть, хотя она подозрительно низкая: "
            .. verdict.text, verdict
    end
    if verdict.flag == MH.FLAG.NO_HISTORY then
        return live, nil,
            "своей истории по этому предмету нет — проверить эту цену мне нечем",
            verdict
    end
    -- Inside the factor but outside everything we have seen. The price is used
    -- as given - it is the live market and it is probably right - but it is an
    -- extrapolation past the whole record, and a figure built on one is an
    -- estimate rather than a measurement.
    if verdict.outsideRange then
        return live, CONF.ESTIMATE, verdict.text, verdict
    end
    return live, nil, verdict.text, verdict
end

-- A short badge for a card: "нетипично высокая (в 167 раз)" or nil when
-- ordinary. It used to read "(167x)" - a multiplier sign in a Russian sentence.
function MH:Badge(verdict)
    if type(verdict) ~= "table" then return nil end
    if verdict.flag == MH.FLAG.HIGH_OUTLIER or verdict.flag == MH.FLAG.LOW_OUTLIER then
        return MH.FLAG_LABEL[verdict.flag] .. " (в "
            .. MH:TimesText(verdict.ratio) .. ")"
    end
    return nil
end

-- Coverage ---------------------------------------------------------------

-- How much history there is overall, for the character tab and the summary.
function MH:Coverage()
    local meta = ns.Config and ns.Config:PriceHistoryMeta() or {}
    local cfg = ns.Config and ns.Config:Get()
    local items, points, deepest = 0, 0, 0
    for _, bucket in pairs((cfg and cfg.priceHistory) or {}) do
        items = items + 1
        local n = 0
        for _ in pairs(bucket) do n = n + 1 end
        points = points + n
        if n > deepest then deepest = n end
    end
    return {
        items = items, points = points, deepestDays = deepest,
        days = meta.days or 0,
        firstDay = meta.firstDay, lastDay = meta.lastDay,
        -- Said plainly, because every verdict above rests on it.
        short = (deepest <= MH.SHORT_SAMPLE_DAYS),
        text = (items == 0)
            and "суточных слепков цен ещё нет — первый появится после входа в игру"
            or string.format(
                "слепки цен: %d предметов, самая длинная история %d %s",
                items, deepest, U.plural(deepest, "день", "дня", "дней")),
    }
end

return MH
