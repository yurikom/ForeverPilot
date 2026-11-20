-- ForeverPilot / Logic/Disenchant.lua
--
-- КУПИТЬ И РАСПЫЛИТЬ: ЭТО ОЖИДАНИЕ, А НЕ ОБЕЩАНИЕ.
--
-- Распыление - единственный совет в этом аддоне, где результат РАНДОМНЫЙ. У
-- зелёной вещи 75% шанс дать пыль, 20% - эссенцию, 5% - осколок, и на одной
-- вещи может выпасть что угодно. Значит, число, которое считает этот файл, -
-- математическое ожидание: «в среднем за много распылов». На одном распыле оно
-- не сбудется почти никогда, и говорить об этом надо прямым текстом, а не
-- сноской.
--
-- ТРИ ПРИЧИНЫ НЕ ВЕРИТЬ ЭТИМ ЧИСЛАМ, И ВСЕ ТРИ НАЗЫВАЮТСЯ:
--
--   1. ВЕРОЯТНОСТИ НЕ ИЗ FOREVER. Они взяты из данных Classic
--      (Data/ForeverSource.lua, FS.DISENCHANT, помечено ESTIMATE) - источника
--      по Forever для них не существует. Сам файл данных об этом пишет в
--      поле caveat, и карточка повторяет это игроку, а не прячет.
--
--   2. ARCANE SALVAGER. В Forever есть предмет 279985 (Наложение чар 140,
--      лагерный объект), который «повышает эффективность распыления». Размер
--      бонуса не документирован НИГДЕ. Значит, посчитанное здесь - это выход
--      БЕЗ лагеря, то есть нижняя граница, и так и сказано: с лагерем выйдет
--      больше, насколько - неизвестно.
--
--   3. GetDisenchantPriceByItemID НА ЭТОМ КЛИЕНТЕ ВСЕГДА nil. Auctionator
--      умеет считать стоимость распыла сам, но на camelot эта функция не
--      отвечает - проверено. Поэтому считаем сами, из вероятностей и цен на
--      продукты, и это ещё одна причина называть результат ожиданием.
--
-- Никакой автоматизации: аддон ничего не покупает и не распыляет.
local ADDON, ns = ...

local U = ns.Util
local Api = ns.Api
local CONF = ns.CONF

local DE = {}
ns.Disenchant = DE

-- Ниже этой ожидаемой выгоды советовать не стоит.
DE.MIN_PROFIT = 1000              -- 10 серебра
-- И ниже этой доли: распыл - это рандом, и на тонкой марже он чаще даёт убыток,
-- чем прибыль. Четверть от вложенного - порог, после которого разброс перестаёт
-- съедать всю выгоду.
DE.MIN_MARGIN_SHARE = 0.25
DE.MAX_CANDIDATES = 250

-- Умеет ли персонаж распылять вообще. Без Наложения чар совет бессмысленен.
function DE:CanDisenchant(snap)
    for _, prof in ipairs((snap and snap.professions) or {}) do
        -- По имени сравнивать нельзя (локализация), поэтому спрашиваем книгу
        -- рецептов: формулы чар есть только у зачарователя.
        if ns.EnchantAdvisor and ns.RecipeBook
           and ns.RecipeBook:HasProfession(prof.name) then
            local bucket = ns.RecipeBook:Bucket(prof.name)
            for _, r in ipairs((bucket and bucket.list) or {}) do
                if ns.EnchantAdvisor:IsEnchantRecipe(r) then return true, prof.name end
            end
        end
    end
    return false, nil
end

-- Ожидание от одного распыла ---------------------------------------------
--
-- Возвращает { expected, conf, products = { { itemID, name, chance, avgQty,
-- unit, value } }, priced, unpriced, caveats = {...} } или nil с причиной.
--
-- `binding` - необязательная карта «привязана ли эта вещь в сумках»
-- (ns.Appearance:BagBinding). Нужна одному вопросу: распыл необратим, и облик
-- с распылённой непривязанной зелёнки пропадает навсегда.
function DE:Expectation(itemID, binding)
    itemID = tonumber(itemID)
    if not itemID then return nil, "no-id" end

    local info = Api:ItemInfo(itemID)
    local quality = info and tonumber(info.quality) or nil
    local ilvl = info and tonumber(info.itemLevel) or nil
    local classID = info and tonumber(info.classID) or nil
    -- Уровень предмета клиент отдаёт не всегда; тогда берём из внешней базы.
    if not (quality and ilvl) then
        local _, rec = Api:ForeignItemStats(itemID)
        if type(rec) == "table" then
            quality = quality or tonumber(rec.quality)
            ilvl = ilvl or tonumber(rec.ilvl)
            classID = classID or tonumber(rec.class)
        end
    end
    if not quality then return nil, "no-quality" end
    if not ilvl then return nil, "no-itemlevel" end
    -- Распыляются только вещи и оружие, и только зелёные и выше.
    if quality < 2 then return nil, "too-common" end
    -- «ВЕЩИ И ОРУЖИЕ» РАНЬШЕ БЫЛО ТОЛЬКО В КОММЕНТАРИИ. Проверялось одно
    -- качество, а зелёными бывают и ремесленные товары: в игре аддон
    -- посоветовал купить «Слиток истинного серебра» и распылить его «в среднем
    -- на 65с». Слиток распылить нельзя вовсе. Класс предмета: 2 - оружие,
    -- 4 - доспехи; всё остальное не распыляется.
    --
    -- Класс неизвестен - тоже нет. Совет «купи и распыли» на догадке о том,
    -- что это вообще можно распылить, - это совет потратить деньги наугад.
    if not classID then
        if ns.Diag then
            ns.Diag:Want("itemsNotInDB", itemID, "disenchant-class",
                { reason = "no-class", name = info and info.name or nil })
        end
        return nil, "no-class"
    end
    if classID ~= 2 and classID ~= 4 then return nil, "not-equipment" end

    local FS = ns.ForeverSource
    if not (FS and FS.DisenchantResults) then return nil, "no-data" end
    local isWeapon = (classID == 2)
    local results = FS:DisenchantResults(quality, ilvl, isWeapon)
    if not results then
        -- ДАННЫХ ПО ЭТОМУ ПРЕДМЕТУ НЕТ - И ЭТО ОТВЕТ, А НЕ НОЛЬ.
        if ns.Diag then
            ns.Diag:Want("disenchantUnknown", itemID, "expectation", {
                quality = quality, ilvl = ilvl, isWeapon = isWeapon,
                name = info and info.name or nil,
            })
        end
        return nil, "no-probabilities"
    end

    local expected, priced, unpriced = 0, 0, 0
    local products = {}
    local worstConf = CONF.CACHED
    for _, r in ipairs(results) do
        local unit, uConf = ns.PriceProvider:Sell(r.itemID)
        local pInfo = Api:ItemInfo(r.itemID)
        local value = nil
        if unit then
            value = unit * r.chance * (r.avgQty or 1)
            expected = expected + value
            priced = priced + 1
            worstConf = U.worstConf(worstConf, uConf or CONF.UNKNOWN)
        else
            unpriced = unpriced + 1
            if ns.Diag then
                ns.Diag:Want("itemsNoPrice", r.itemID, "disenchant-product")
            end
        end
        products[#products + 1] = {
            itemID = r.itemID,
            name = (pInfo and pInfo.name) or U.itemFallbackName(r.itemID),
            chance = r.chance, avgQty = r.avgQty,
            min = r.min, max = r.max,
            unit = unit, value = value,
        }
    end
    if priced == 0 then return nil, "no-product-prices" end

    -- Достоверность: не выше ESTIMATE НИКОГДА. Вероятности не из Forever, и
    -- называть такой расчёт «из кеша» значило бы врать про его надёжность.
    local conf = U.worstConf(worstConf, CONF.ESTIMATE)
    if unpriced > 0 then conf = CONF.UNKNOWN end

    -- ОГОВОРКИ - ЦЕЛЫМИ ФРАЗАМИ, КАК ИХ ПРОЧТЁТ ИГРОК.
    --
    -- Раньше оговорка из данных проходила через U.lower и склеивалась через
    -- «. »: на экране получалось «…из данных classic, не из источника по
    -- forever. бонус arcane salvager не учтён..» - названия с маленькой буквы,
    -- вторая фраза с маленькой буквы и две точки в конце. Теперь каждая
    -- оговорка - готовая фраза без точки на конце; точки ставит CaveatText.
    local caveats = {}
    caveats[#caveats + 1] = "Это ожидание, а не обещание: на одном распыле"
        .. " выпадет что-то одно, и это может быть что угодно"
    local fsCaveat = ns.ForeverSource and ns.ForeverSource.DISENCHANT
        and ns.ForeverSource.DISENCHANT.caveat or nil
    if type(fsCaveat) == "string" then
        for sentence in fsCaveat:gmatch("[^%.]+") do
            sentence = sentence:gsub("^%s+", ""):gsub("%s+$", "")
            if sentence ~= "" then caveats[#caveats + 1] = sentence end
        end
    end
    caveats[#caveats + 1] = "В Forever есть Arcane Salvager, который повышает"
        .. " эффективность распыления на неизвестную величину — значит с ним"
        .. " выйдет больше, чем тут посчитано"
    if unpriced > 0 then
        caveats[#caveats + 1] = "Цены на " .. unpriced .. " из "
            .. #products .. " возможных результатов я не знаю, так что"
            .. " настоящее ожидание выше этого числа"
    end

    return {
        itemID = itemID,
        name = (info and info.name) or U.itemFallbackName(itemID),
        quality = quality, itemLevel = ilvl, isWeapon = isWeapon,
        expected = expected, conf = conf,
        products = products, priced = priced, unpriced = unpriced,
        caveats = caveats,
        -- ВСЁ, ЧТО НУЖНО ДЛЯ ВОПРОСА ПРО ОБЛИК, ЕДЕТ С НАХОДКОЙ, А САМ ВОПРОС
        -- ЗАДАЁТСЯ У КАРТОЧКИ (Logic/ActionEngine.lua, Engine:AddDisenchantCards).
        --
        -- Это про цену работы. Ожидание считается по всем кандидатам, советом
        -- становится единица: на настоящих данных это 41 расчёт за пересчёт
        -- против одной карточки. Вопрос, заданный здесь, стоил бы 41 обращение
        -- к клиенту за ответы, которые тут же выбрасываются.
        bound = binding and binding[itemID] or nil,
        bindType = info and info.bindType or nil,
        classID = classID,
        link = info and info.link or nil,
    }
end

-- Стоит ли покупать именно для распыла -----------------------------------

function DE:Evaluate(itemID, binding)
    local exp, why = DE:Expectation(itemID, binding)
    if not exp then return nil, why end

    -- Во что обойдётся сама вещь. Только подтверждённые источники: «оценка по
    -- цене продажи» для схемы «купи и распыли» - это умножение гадания на
    -- гадание.
    local cost, costConf, costSrc = ns.PriceProvider:Buy(itemID)
    if not cost then return nil, "no-buy-price" end
    if not ns.PriceProvider.PROVEN_SOURCES[costSrc] then return nil, "unproven-cost" end

    local profit = exp.expected - cost
    if profit < DE.MIN_PROFIT then return nil, "too-small" end
    if profit / cost < DE.MIN_MARGIN_SHARE then return nil, "thin-margin" end

    exp.cost = cost
    exp.costConf = costConf
    exp.costSrc = costSrc
    exp.profit = profit
    exp.marginShare = profit / cost
    exp.conf = U.worstConf(exp.conf, costConf or CONF.UNKNOWN)

    return exp
end

-- Все возможности ---------------------------------------------------------

function DE:Opportunities(snap)
    local can = DE:CanDisenchant(snap)
    if not can then
        DE.lastReason = "распылять некому: Наложение чар не изучено"
        return {}
    end
    local out = {}
    local funnel = ns.Diag and ns.Diag:Funnel("disenchant") or nil
    local n = 0
    local dropped = {}      -- причина отсева -> сколько раз
    -- Привязанность вещей в сумках спрашивается ОДИН раз на ветку: ячеек у
    -- игрока сотня, кандидатов - до двух с половиной сотен.
    local binding = ns.Appearance and ns.Appearance:BagBinding(snap) or nil
    for _, itemID in ipairs(DE:Candidates(snap)) do
        n = n + 1
        if n > DE.MAX_CANDIDATES then break end
        local item = { itemID = itemID, name = tostring(itemID) }
        if funnel then funnel:In(item) end
        local opp, why = DE:Evaluate(itemID, binding)
        if opp then
            out[#out + 1] = opp
        else
            why = why or "unknown"
            dropped[why] = (dropped[why] or 0) + 1
            if funnel then funnel:Drop(why, item) end
        end
    end
    table.sort(out, function(a, b)
        if a.profit ~= b.profit then return a.profit > b.profit end
        return a.itemID < b.itemID
    end)
    if funnel then funnel:Finish(#out) end
    DE.lastReason = (#out == 0) and DE:QuietReason(dropped) or nil
    return out
end

-- ПОЧЕМУ ВЕТКА МОЛЧИТ - ПО ТОМУ, ЧТО БЫЛО НА САМОМ ДЕЛЕ.
--
-- Раньше причина была одна на все случаи: «ожидание ниже цены покупки». В
-- сводке она стояла рядом с воронкой, где все 250 кандидатов отсеялись с
-- пометкой «уровень предмета неизвестен», - то есть ни одного ожидания никто
-- не считал, а аддон уверенно объяснял, чем оно плохо. Причина теперь
-- выбирается по тому, на чём кандидаты отсеялись в большинстве.
DE.DATA_GAPS = {
    ["no-quality"] = true, ["no-itemlevel"] = true, ["no-class"] = true,
    ["no-probabilities"] = true, ["no-product-prices"] = true,
    ["no-buy-price"] = true, ["unproven-cost"] = true, ["no-data"] = true,
    ["no-id"] = true, ["unknown"] = true,
}
DE.NOT_FOR_DISENCHANT = { ["too-common"] = true, ["not-equipment"] = true }

function DE:QuietReason(dropped)
    local gaps, unfit, weak, total = 0, 0, 0, 0
    for why, n in pairs(dropped or {}) do
        total = total + n
        if DE.DATA_GAPS[why] then gaps = gaps + n
        elseif DE.NOT_FOR_DISENCHANT[why] then unfit = unfit + n
        else weak = weak + n end
    end
    if total == 0 then
        return "среди известных мне предметов нет ни одного кандидата на распыл"
    end
    if weak > 0 and weak >= gaps then
        return "ничего, что выгодно купить ради распыла: ожидание ниже цены покупки"
    end
    if gaps > 0 and gaps >= unfit then
        return "посчитать распыл не из чего: по " .. gaps .. " "
            .. U.plural(gaps, "предмету", "предметам", "предметам")
            .. " не хватило данных (уровень предмета, его род или цены)"
    end
    return "среди известных мне предметов нет доспехов и оружия, которые стоит"
        .. " покупать ради распыла"
end

-- Круг поиска: зелёные и выше вещи, про которые аддон и так знает. Полного
-- обхода базы здесь нет - он не влез бы в бюджет пересчёта.
function DE:Candidates(snap)
    local set = {}
    for itemID in pairs((snap and snap.bags) or {}) do set[itemID] = true end
    -- Выходы рецептов: вещь, которую игрок умеет сделать, он умеет и купить.
    for _, recipe in ipairs(ns.RecipeBook and ns.RecipeBook:Iterate(
            function(r) return r.output end) or {}) do
        set[recipe.output] = true
    end
    local cfg = ns.Config and ns.Config:Get() or nil
    for itemID in pairs((cfg and cfg.priceHistory) or {}) do
        set[tonumber(itemID) or itemID] = true
    end
    local out = {}
    for itemID in pairs(set) do
        local id = tonumber(itemID)
        if id then out[#out + 1] = id end
    end
    table.sort(out)
    return out
end

-- Текст -------------------------------------------------------------------

-- Что именно и с какой вероятностью. Без этого «ожидание 2з» - просто число.
function DE:ProductsText(exp)
    local bits = {}
    table.sort(exp.products, function(a, b)
        return (a.chance or 0) > (b.chance or 0)
    end)
    for i = 1, math.min(3, #exp.products) do
        local p = exp.products[i]
        local qty = (p.min == p.max) and tostring(p.min)
            or (tostring(p.min) .. "-" .. tostring(p.max))
        bits[#bits + 1] = U.pct(p.chance) .. " " .. p.name .. " x" .. qty
            .. (p.unit and (" по " .. U.money(p.unit)) or (" (" .. U.void(ns.VOID.NO_PRICE) .. ")"))
    end
    return table.concat(bits, ", ")
end

function DE:CaveatText(exp)
    local out = {}
    for _, c in ipairs(exp.caveats or {}) do
        -- Точка на конце оговорки - лишняя: её ставит склейка. Иначе в тексте
        -- оказываются две точки подряд.
        local sentence = tostring(c):gsub("[%.%s]+$", "")
        if sentence ~= "" then out[#out + 1] = U.capitalize(sentence) end
    end
    if #out == 0 then return "" end
    return table.concat(out, ". ") .. "."
end

return DE
