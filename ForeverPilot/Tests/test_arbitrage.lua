-- ForeverPilot / Tests/test_arbitrage.lua
--
-- КУПИТЬ У ТОРГОВЦА, ПРОДАТЬ НА АУКЦИОНЕ.
--
-- Набор держит ровно тот список, без которого совет бесполезен: русское
-- название из клиента, itemID, имя NPC с зоной и координатами, валюта и цена,
-- ограничения продажи, прибыль ПОСЛЕ сбора аукциона.
--
-- И две отдельные ловушки, обе из настоящих данных:
--   * СПЕЦВАЛЮТА. У 210 записей о торговцах в пакете Polestar_Codex цены нет
--     вовсе - почти наверняка потому, что платят не золотом. Считать такую
--     цену нулём значит советовать «купи даром и продай».
--   * ШТУЧНЫЙ ТОВАР. Поле «осталось N» в том же пакете не заполнено НИ У ОДНОЙ
--     из 7219 записей. Значит, постоянство товара из внешней базы не выводится,
--     и выдавать штучный за постоянный нельзя.
local H = ...

return function()

local function arbEnv(opts)
    opts = opts or {}
    local env = H.load()
    local ns = env.ns
    env.money = 58052
    env.auctionator = true
    H.item(env, 2324, { name = "Белила", sellPrice = 30, stackCount = 20 })
    -- Торговец просит 1с 50м, аукцион даёт 8с: наценка больше пяти раз.
    if opts.ownVendorPrice ~= false then
        ns.Config:RememberVendorPrice(2324, opts.ask or 150)
    end
    env.prices[2324] = opts.auction or 800
    return env
end

local function arbCard(cards, ns)
    for _, c in ipairs(cards) do
        if c.kind == ns.KIND.ARBITRAGE then return c end
    end
    return nil
end

H.suite("Арбитраж: модуль есть и находит возможность")
do
    local env = arbEnv()
    local ns = env.ns
    H.ok(ns.VendorArbitrage ~= nil, "модуль перепродажи есть")
    H.rescan(env)
    ns.PriceProvider:BeginPass()
    local opp = ns.VendorArbitrage:Evaluate(2324)
    H.ok(opp ~= nil, "возможность найдена")
    if opp then
        H.eq(opp.itemID, 2324, "itemID на месте")
        H.eq(opp.name, "Белила", "русское название из клиента, а не из базы")
        H.eq(opp.ask, 150, "цена торговца")
        -- 800 минус 5% сбора = 760; 760 - 150 = 610
        H.eq(ns.Util.round(opp.revenue), 760,
            "выручка с вычтенным сбором аукциона: " .. tostring(opp.revenue))
        H.eq(ns.Util.round(opp.profit), 610, "прибыль после сбора")
        H.eq(opp.provenStock, true,
            "и товар постоянный: цену я записал сам, стоя у торговца")
    end
end

H.suite("Арбитраж: карточка несёт всё, без чего совет бесполезен")
do
    local env = arbEnv()
    local ns = env.ns
    -- Торговец, перед которым игрок стоял: запись о месте с координатами идёт
    -- через настоящий путь - чтение окна торговца, ровно как в игре.
    -- numAvailable = -1 означает неограниченный запас: именно такой товар
    -- Price:RecordMerchant и соглашается запоминать.
    env.npcUnit = { id = 3364, name = "Темный Торговец" }
    env.playerMap = { mapID = 1637, x = 0.52, y = 0.61, zone = "Оргриммар" }
    env.merchantItems = {
        { itemID = 2324, price = 150, stack = 1, numAvailable = -1 },
    }
    ns.Places:RecordMerchant()

    H.rescan(env)
    local cards = H.build(env)
    local c = arbCard(cards, ns)
    H.ok(c ~= nil, "карточка перепродажи построена")
    if c then
        H.eq(c.itemID, 2324, "itemID на карточке")
        H.ok(ns.Util.contains(c.title, "Белила"),
            "русское название в заголовке: " .. c.title)
        H.ok(ns.Util.contains(c.benefit, "з") or ns.Util.contains(c.benefit, "с"),
            "прибыль в заголовке: " .. c.benefit)
        H.ok(ns.Util.contains(c.why, "сбор аукциона"),
            "сказано, что сбор вычтен: " .. ns.Util.truncate(c.why, 150))
        H.ok(ns.Util.contains(c.why, "наценк"), "и какая наценка")
        H.ok(ns.Util.contains(c.need, "Торговец"),
            "торговец назван: " .. ns.Util.truncate(c.need, 150))
        H.ok(c.place ~= nil and c.place.routable,
            "с координатами, по которым можно построить путь")
        H.eq(c.cost, 150, "требуемый капитал = цена покупки")
        H.ok(c.risk ~= nil, "и оценка риска приложена")
    end
end

H.suite("Арбитраж: постоянный товар и непроверенный — разные тексты")
do
    -- 1. Стояли сами: Price:RecordMerchant кладёт в наши записи ТОЛЬКО товар с
    -- неограниченным запасом, поэтому «постоянный» здесь доказано.
    local env = arbEnv()
    local ns = env.ns
    H.rescan(env)
    ns.PriceProvider:BeginPass()
    local own = ns.VendorArbitrage:Evaluate(2324)
    H.ok(own ~= nil, "возможность из своих записей есть")
    if own then
        local text = ns.VendorArbitrage:StockText(own)
        H.ok(ns.Util.contains(text, "постоянн"),
            "про свой товар сказано, что он постоянный: "
            .. ns.Util.truncate(text, 120))
    end

    -- 2. Не стояли: цена из Codex, про запас он молчит.
    local env2 = arbEnv { ownVendorPrice = false }
    local ns2 = env2.ns
    env2.codexItems[2324] = {
        name = "Bleach",
        sources = { { type = "vendor", npc = 3364, cost = 150 } },
    }
    env2.codexNpcs[3364] = {
        name = "Темный Торговец", roles = { "vendor" },
        spawns = { { map = 1637, x = 52.0, y = 61.0 } },
    }
    H.bindCodex(env2)
    H.rescan(env2)
    ns2.PriceProvider:BeginPass()
    local codex = ns2.VendorArbitrage:Evaluate(2324)
    H.ok(codex ~= nil, "возможность из Codex найдена")
    if codex then
        H.eq(codex.provenStock, false, "но постоянство НЕ утверждается")
        local text = ns2.VendorArbitrage:StockText(codex)
        H.ok(ns2.Util.contains(text, "не проверял"),
            "и сказано прямо: " .. ns2.Util.truncate(text, 140))
        H.ok(ns2.Util.contains(text, "штучн"),
            "с предупреждением про штучный товар")
        -- Координаты из Codex всё равно есть: совет остаётся исполнимым.
        H.ok(codex.place ~= nil and codex.place.routable,
            "и координаты торговца из Codex подтянуты")
        H.eq(codex.place.source, "codex", "с указанием, что данные чужие")
    end
end

H.suite("Арбитраж: полярность чужой цены проверяется арифметикой")
do
    -- Число из чужого кеша может означать «торговец просит» или «торговец
    -- даёт». Для схемы «купи дешевле — продай дороже» это разница между
    -- советом и убытком, и верить тут нельзя — надо считать.
    --
    -- Настоящие числа из файла игрока (MastercraftDB.vendorPrices): грубая
    -- нить 2320 записана как 9, а выкупают её за 2. Ровно 90% от обычной цены
    -- продажи в 10 медных — это скидка за репутацию, и это именно цена, по
    -- которой ПОКУПАЮТ.
    local env = arbEnv { ownVendorPrice = false }
    local ns = env.ns
    H.item(env, 2320, { name = "Грубая нить", sellPrice = 2 })
    env.foreignVendorPrices = { [2320] = 9 }
    H.itemsChanged(env)
    local ok, why = ns.VendorArbitrage:AskPolarityOK(2320, 9)
    H.eq(ok, true, "9 против выкупа 2 — это цена продажи")
    H.ok(ns.Util.contains(why, "выкуп"), "и сказано почему: " .. tostring(why))

    -- А вот число, равное цене выкупа, ценой продажи быть не может.
    local bad, badWhy = ns.VendorArbitrage:AskPolarityOK(2320, 2)
    H.eq(bad, false, "2 против выкупа 2 — это не цена продажи")
    H.ok(ns.Util.contains(badWhy, "ДАЁТ") or ns.Util.contains(badWhy, "даёт"),
        "и сказано, что это скорее цена выкупа: " .. tostring(badWhy))

    -- Своя запись перебивает арифметику: мы это видели своими глазами.
    ns.Config:RememberVendorPrice(2320, 9)
    local own, ownWhy = ns.VendorArbitrage:AskPolarityOK(2320, 9)
    H.eq(own, true, "своя запись подтверждает")
    H.ok(ns.Util.contains(ownWhy, "сам"), "и говорит об этом: " .. tostring(ownWhy))
    -- И расхождение со своей записью — повод не верить чужой.
    local dis = ns.VendorArbitrage:AskPolarityOK(2320, 9000)
    H.eq(dis, false, "чужой кеш, расходящийся со своей записью, не принимается")
end

H.suite("Арбитраж: цена выкупа вместо цены продажи — не схема")
do
    local env = arbEnv { ownVendorPrice = false }
    local ns = env.ns
    -- Чужой кеш отдаёт число, равное цене выкупа: полярность не та.
    env.items[2324].sellPrice = 150
    env.foreignVendorPrices = { [2324] = 150 }
    H.itemsChanged(env)
    H.rescan(env)
    ns.PriceProvider:BeginPass()
    local opp, why, detail = ns.VendorArbitrage:Evaluate(2324)
    H.eq(opp, nil, "возможности нет")
    H.eq(why, "vendor-polarity", "и причина отдельная: полярность числа не та")
    H.ok(detail ~= nil and (ns.Util.contains(detail, "ДАЁТ")
         or ns.Util.contains(detail, "даёт")),
        "с объяснением: " .. ns.Util.truncate(tostring(detail), 130))
end

H.suite("Арбитраж: спецвалюта не считается нулём")
do
    local env = arbEnv { ownVendorPrice = false }
    local ns = env.ns
    -- Ровно та запись, какой она бывает в настоящем пакете: торговец есть,
    -- цены нет.
    env.codexItems[2324] = {
        name = "Bleach",
        sources = { { type = "vendor", npc = 3364 } },
    }
    env.codexNpcs[3364] = { name = "Торговец жетонами", roles = { "vendor" },
        spawns = { { map = 1637, x = 50.0, y = 50.0 } } }
    H.bindCodex(env)
    H.rescan(env)
    ns.PriceProvider:BeginPass()

    local opp, why, detail = ns.VendorArbitrage:Evaluate(2324)
    H.eq(opp, nil, "возможности нет: цену в золоте назвать нечем")
    H.eq(why, "vendor-currency", "и причина именно такая")
    H.ok(detail ~= nil and ns.Util.contains(detail, "валюта"),
        "с объяснением: " .. ns.Util.truncate(tostring(detail), 140))

    -- И это заказ на данные, а не молчание.
    ns.VendorArbitrage:Opportunities()
    local b = (ns.Diag:Init().wanted or {}).itemsNoPrice
    local found = b and b.items["2324"]
    H.ok(found ~= nil, "предмет попал в список заказа данных")
    if found then
        H.ok(found.where["vendor-currency"] ~= nil,
            "с пометкой, что дело в валюте")
    end
end

H.suite("Арбитраж: непродаваемое не советуется")
do
    local env = arbEnv()
    local ns = env.ns
    -- Привязка при получении: на аукцион не выставить, значит схемы нет.
    env.items[2324].bindType = 1
    H.itemsChanged(env)
    H.rescan(env)
    ns.PriceProvider:BeginPass()
    local opp, why, detail = ns.VendorArbitrage:Evaluate(2324)
    H.eq(opp, nil, "возможности нет")
    H.eq(why, "not-sellable", "причина — нельзя продать")
    H.ok(detail ~= nil and ns.Util.contains(detail, "привязыва"),
        "и сказано почему: " .. tostring(detail))
end

H.suite("Арбитраж: цена торговца вместо рыночной — не схема")
do
    -- Если «выручка» это то, что даст торговец, то схема вырождается в
    -- «купи у торговца и продай торговцу», то есть в гарантированный убыток.
    local env = arbEnv()
    local ns = env.ns
    env.auctionator = false
    env.prices = {}
    env.items[2324].sellPrice = 10000   -- торговец даёт много
    H.itemsChanged(env)
    H.rescan(env)
    ns.PriceProvider:BeginPass()
    local opp, why = ns.VendorArbitrage:Evaluate(2324)
    H.eq(opp, nil, "возможности нет")
    H.eq(why, "no-market-only-vendor", "причина — рыночной цены нет")
end

H.suite("Арбитраж: тонкая маржа и мелочь отсеиваются")
do
    -- 10% наценки на дорогом товаре — это риск ради риска.
    local env = arbEnv { ask = 100000, auction = 115000 }
    local ns = env.ns
    H.rescan(env)
    ns.PriceProvider:BeginPass()
    local opp, why = ns.VendorArbitrage:Evaluate(2324)
    H.eq(opp, nil, "тонкая маржа отсеяна")
    H.ok(why == "thin-margin" or why == "too-small",
        "по понятной причине: " .. tostring(why))

    -- И копейки тоже.
    local env2 = arbEnv { ask = 100, auction = 300 }
    local ns2 = env2.ns
    H.rescan(env2)
    ns2.PriceProvider:BeginPass()
    local o2, w2 = ns2.VendorArbitrage:Evaluate(2324)
    H.eq(o2, nil, "мелочь отсеяна")
    H.eq(w2, "too-small", "по причине «слишком мало»")
end

H.suite("Арбитраж: ветка объясняет своё молчание")
do
    local env = arbEnv { ask = 100000, auction = 115000 }
    local ns = env.ns
    H.rescan(env)
    local cards = H.build(env)
    H.eq(arbCard(cards, ns), nil, "карточки нет")
    H.ok(ns.ActionEngine.branchNote.arbitrage ~= nil,
        "и ветка сказала почему: "
        .. tostring(ns.ActionEngine.branchNote.arbitrage))

    -- И это видно в отчёте по веткам, который читает окно.
    local found
    for _, b in ipairs(ns.ActionEngine.meta.branches or {}) do
        if b.key == "arbitrage" then found = b end
    end
    H.ok(found ~= nil, "ветка есть в отчёте")
    if found then
        H.eq(found.count, 0, "с нулём карточек")
        H.ok(found.reason ~= nil, "и с причиной")
        H.eq(found.label, "Перепродажа у торговцев", "и с понятным названием")
    end
end

H.suite("Арбитраж: воронка говорит, где отсеялось")
do
    local env = arbEnv { ask = 100000, auction = 115000 }
    local ns = env.ns
    H.rescan(env)
    H.build(env)
    local f = ns.Diag:Init().funnels.vendorArbitrage
    H.ok(f ~= nil, "воронка записана")
    if f then
        H.ok((f["in"] or 0) > 0, "кандидаты были: " .. tostring(f["in"]))
        local any = false
        for _ in pairs(f.drops or {}) do any = true end
        H.ok(any, "и есть названные фильтры, которые их отсеяли")
    end
end

-- ПОТОЛОК ПРАВДОПОДОБИЯ НАЦЕНКИ ===========================================
--
-- Живой прогон выдал шесть карточек с наценкой от 419% до 2433%, и все они
-- оказались ошибкой данных, а не кладом. Порог взят не с потолка, он опирается
-- на два независимых числа - см. комментарий над VA.MARKUP_NOTE.

H.suite("Арбитраж: пороги наценки объявлены и выведены, а не вписаны")
do
    local env = arbEnv()
    local ns = env.ns
    local VA = ns.VendorArbitrage
    H.ok(VA.MARKUP_NOTE ~= nil, "порог «упомянуть» есть")
    H.ok(VA.MARKUP_LIMIT ~= nil, "порог «не верю» есть")
    if VA.MARKUP_NOTE and VA.MARKUP_LIMIT then
        H.ok(VA.MARKUP_NOTE < VA.MARKUP_LIMIT,
            "упомянуть строго раньше, чем не поверить: "
            .. VA.MARKUP_NOTE .. " < " .. VA.MARKUP_LIMIT)
        -- Оба выведены из наценки самой игры: торговец продаёт вчетверо дороже
        -- того, что даёт (Price.VENDOR_MARKUP). Если порог однажды оторвётся от
        -- этого числа, тест об этом скажет.
        H.eq(VA.MARKUP_NOTE, 2 * ns.PriceProvider.VENDOR_MARKUP,
            "порог «упомянуть» - две наценки игры")
        H.eq(VA.MARKUP_LIMIT, 5 * ns.PriceProvider.VENDOR_MARKUP,
            "порог «не верю» - пять наценок игры")
    end
end

H.suite("Арбитраж: наценка в разумных пределах — верим молча")
do
    -- 150 -> 800, за вычетом сбора 760: наценка 5.07 раз. Это внутри того, что
    -- на настоящих данных игрока наблюдалось (максимум 4.6), так что никаких
    -- пометок быть не должно.
    local env = arbEnv()
    local ns = env.ns
    H.rescan(env)
    ns.PriceProvider:BeginPass()
    local opp = ns.VendorArbitrage:Evaluate(2324)
    H.ok(opp ~= nil, "возможность найдена")
    if opp then
        H.eq(opp.markupVerdict, nil, "вердикта о неправдоподобии нет")
        H.ok(opp.markup ~= nil, "но сама наценка посчитана: " .. tostring(opp.markup))
    end
    local cards = H.build(env)
    local c = arbCard(cards, ns)
    H.ok(c ~= nil, "карточка есть")
    if c then
        H.ok(not ns.Util.contains(c.why or "", "не сходятся"),
            "и на ней нет предупреждения о несходящихся числах")
    end
end

H.suite("Арбитраж: наценка выше порога «упомянуть» — сказано, достоверность ниже")
do
    -- 150 -> 2000 (1900 после сбора): наценка 12.7 раз. Между 8 и 20.
    local env = arbEnv { auction = 2000 }
    local ns = env.ns
    H.rescan(env)
    ns.PriceProvider:BeginPass()
    local opp = ns.VendorArbitrage:Evaluate(2324)
    H.ok(opp ~= nil, "возможность всё ещё есть — карточку мы не прячем")
    if opp then
        H.ok(opp.markupVerdict ~= nil, "вердикт о наценке приложен")
        H.eq(opp.markupVerdict and opp.markupVerdict.code, "markup-note",
            "и он именно «стоит упомянуть»")
    end
    local cards = H.build(env)
    local c = arbCard(cards, ns)
    H.ok(c ~= nil, "карточка построена")
    if c then
        H.ok(ns.Util.contains(c.why or "", "наценка такого размера"),
            "про размер наценки сказано в тексте: "
            .. ns.Util.truncate(c.why or "", 220))
        H.ok(c.conf ~= ns.CONF.EXACT and c.conf ~= ns.CONF.CACHED,
            "достоверность опущена: " .. tostring(c.conf))
    end
end

H.suite("Арбитраж: наценка выше порога «не верю» — совета в списке нет, причина названа")
do
    -- 40с -> 9з 98с, как Чёрный лотос в живом прогоне: наценка 23.7 раз.
    --
    -- Раньше такая карточка оставалась на экране с пометкой «сомнительно». В
    -- живом списке игрока (2026-11-21) это были пять советов купить у торговца
    -- то, чего он по такой цене не продаёт. Совет, которому не верит сам
    -- советчик, в список больше не идёт; находка при этом не пропадает молча.
    local env = arbEnv { ask = 4000, auction = 99800 }
    local ns = env.ns
    H.rescan(env)
    ns.PriceProvider:BeginPass()
    local opp = ns.VendorArbitrage:Evaluate(2324)
    H.ok(opp ~= nil, "возможность не выбрасывается молча")
    if opp then
        H.eq(opp.markupVerdict and opp.markupVerdict.code, "markup-impossible",
            "вердикт: такой наценке я не верю")
    end
    local cards = H.build(env)
    H.eq(arbCard(cards, ns), nil, "карточки на экране нет")
    local hidden = ns.ActionEngine.meta.arbitrageImpossible or {}
    H.eq(#hidden, 1, "находка лежит в отдельном списке движка")
    local note = ns.ActionEngine.branchNote.arbitrage or ""
    H.ok(ns.Util.contains(note, "наценкой, которой не бывает"),
        "пустая ветка называет причину: " .. note)
    H.ok(ns.Util.contains(note, "ошибка в данных"), "и говорит, что это ошибка данных")
    H.ok((ns.Diag:Init().counters["arbitrage.impossibleNotShown"] or 0) >= 1,
        "в счётчиках это есть")
    -- И это видно в диагностике, а не только в заметке ветки.
    local susp = ns.Diag:Init().suspicious or {}
    local found = false
    for _, s in ipairs(susp) do
        if s.code == "arbitrage-markup-impossible"
            and ns.Util.contains(s.text or "", "в список не поставлено") then
            found = true
        end
    end
    H.ok(found, "странность записана в диагностику с пометкой, что совет не показан")
end

-- ПОЛЯРНОСТЬ ЦЕНЫ НА ПУТИ ЧЕРЕЗ CODEX ====================================
--
-- Для чужого кеша полярность уже проверялась (VA:AskPolarityOK), а для Codex -
-- нет. Проверять есть чем: торговец НИКОГДА не продаёт дешевле, чем выкупает,
-- и цена выкупа лежит в данных самого предмета.

H.suite("Арбитраж: цена из Codex ниже цены выкупа — это не цена продажи")
do
    local env = H.load()
    local ns = env.ns
    env.money = 58052
    env.auctionator = true
    -- Выкуп 500, а «цена торговца» из Codex 120: торговец не может продавать
    -- дешевле, чем выкупает. Значит это не цена продажи.
    H.item(env, 7777, { name = "Подозрительный товар", sellPrice = 500, stackCount = 20 })
    env.prices[7777] = 30000
    env.codexItems[7777] = {
        sources = { { type = "vendor", npc = 263384, cost = 120, from = { "recordings" } } },
    }
    env.codexNpcs[263384] = {
        name = "Mister Graphed", subName = "Agent of the Black Market",
        roles = { "vendor" }, spawns = { { map = 2548, x = 78.2, y = 51.9 } },
    }
    H.rescan(env)
    ns.PriceProvider:BeginPass()
    local opp, why, detail = ns.VendorArbitrage:Evaluate(7777)
    H.eq(opp, nil, "возможности нет — такой цене верить нельзя")
    H.eq(why, "vendor-polarity", "и причина названа полярностью: " .. tostring(why))
    H.ok(detail ~= nil and ns.Util.contains(tostring(detail), "выкуп"),
        "в причине сказано про цену выкупа: " .. tostring(detail))
end

H.suite("Арбитраж: цена из Codex выше цены выкупа — проходит")
do
    local env = H.load()
    local ns = env.ns
    env.money = 58052
    env.auctionator = true
    H.item(env, 7778, { name = "Нормальный товар", sellPrice = 30, stackCount = 20 })
    env.prices[7778] = 800
    env.codexItems[7778] = {
        sources = { { type = "vendor", npc = 3364, cost = 150,
                      from = { "recordings", "questie", "pfquest" } } },
    }
    env.codexNpcs[3364] = {
        name = "Темный Торговец", roles = { "vendor" },
        spawns = { { map = 1637, x = 52, y = 61 } },
    }
    H.rescan(env)
    ns.PriceProvider:BeginPass()
    local opp = ns.VendorArbitrage:Evaluate(7778)
    H.ok(opp ~= nil, "возможность найдена")
    if opp then
        H.eq(opp.ask, 150, "цена торговца взята из Codex")
        H.eq(opp.askSrc, "codex", "и источник назван")
    end
end

H.suite("Арбитраж: непроверенная цена торговца и наценка выше наблюдавшейся — не верю")
do
    -- Живая жалоба (маг 31 ур., 2026-11-21): «Купить и перепродать: Лотос
    -- смерти, +10з 80с за штуку» - у торговца «~60с (оценка)», на аукционе 12з.
    -- Наценка x19 не дотянула до потолка x20, и карточка стояла с прибылью
    -- крупными цифрами. Цену торговца при этом в игре никто не видел.
    local env = H.load()
    local ns = env.ns
    env.money = 58052
    env.auctionator = true
    H.item(env, 7790, { name = "Лотос смерти", sellPrice = 100, stackCount = 20 })
    env.prices[7790] = 120000
    env.codexItems[7790] = {
        sources = { { type = "vendor", npc = 263384, cost = 6000,
                      from = { "recordings", "questie", "pfquest" } } },
    }
    env.codexNpcs[263384] = {
        name = "Mister Graphed", subName = "Agent of the Black Market",
        roles = { "vendor" }, spawns = { { map = 2548, x = 78.2, y = 51.9 } },
    }
    -- В круг поиска предмет попадает так же, как в игре: по нему есть история
    -- цен (см. VA:KnownItems).
    ns.Config:Get().priceHistory = ns.Config:Get().priceHistory or {}
    ns.Config:Get().priceHistory[7790] = { [20777] = 120000 }
    H.rescan(env)
    ns.PriceProvider:BeginPass()
    local opp = ns.VendorArbitrage:Evaluate(7790)
    H.ok(opp ~= nil, "возможность не выбрасывается молча")
    if opp then
        H.eq(opp.askConf, ns.CONF.ESTIMATE, "цена торговца — оценка из чужой базы")
        H.ok(opp.markup > ns.VendorArbitrage.MARKUP_NOTE
            and opp.markup < ns.VendorArbitrage.MARKUP_LIMIT,
            string.format("наценка между порогами: x%.1f", opp.markup))
        H.eq(opp.markupVerdict and opp.markupVerdict.code, "markup-impossible",
            "вердикт: непроверенной цене при такой наценке не верю")
        H.eq(opp.markupVerdict and opp.markupVerdict.unverifiedAsk, true,
            "и причина записана: цену никто не видел")
        H.eq(opp.conf, ns.CONF.UNKNOWN, "достоверность снята совсем")
    end
    local cards = H.build(env)
    H.eq(arbCard(cards, ns), nil,
        "карточки на экране нет: цену торговца никто не видел, а наценка невозможная")
    H.eq(#(ns.ActionEngine.meta.arbitrageImpossible or {}), 1,
        "находка лежит в отдельном списке движка, а не пропала")
end

H.suite("Арбитраж: та же наценка на цене, которую игрок видел сам, — только упомянута")
do
    -- Свою цену торговца игрок видел у прилавка: ей верить есть чем, и
    -- правило выше её не трогает.
    local env = arbEnv { auction = 2000 }
    local ns = env.ns
    H.rescan(env)
    ns.PriceProvider:BeginPass()
    local opp = ns.VendorArbitrage:Evaluate(2324)
    H.ok(opp ~= nil, "возможность есть")
    if opp then
        H.ok(opp.askConf ~= ns.CONF.ESTIMATE, "цена не оценка: " .. tostring(opp.askConf))
        H.eq(opp.markupVerdict and opp.markupVerdict.code, "markup-note",
            "вердикт остался «стоит упомянуть»")
    end
end

H.suite("Арбитраж: один общинный источник у цены — сказано вслух")
do
    -- Из 16259 записей о торговцах в Polestar_Codex провенанс «только
    -- recordings» стоит у 476, то есть у 2.9%. Это редкая пометка, и у цен
    -- Mister Graphed она стоит у 11 из 15 записей.
    local env = H.load()
    local ns = env.ns
    env.money = 58052
    env.auctionator = true
    H.item(env, 7779, { name = "Черный лотос", sellPrice = 100, stackCount = 20 })
    env.prices[7779] = 99800
    env.codexItems[7779] = {
        sources = { { type = "vendor", npc = 263384, cost = 50000, from = { "recordings" } } },
    }
    env.codexNpcs[263384] = {
        name = "Mister Graphed", subName = "Agent of the Black Market",
        roles = { "vendor" }, spawns = { { map = 2548, x = 78.2, y = 51.9 } },
    }
    H.rescan(env)
    ns.PriceProvider:BeginPass()
    local opp = ns.VendorArbitrage:Evaluate(7779)
    H.ok(opp ~= nil, "возможность найдена")
    if opp then
        H.eq(opp.askLone, true, "цена помечена как подтверждённая одним источником")
        local text = ns.VendorArbitrage.AskSourceText
            and ns.VendorArbitrage:AskSourceText(opp) or nil
        H.ok(text ~= nil, "и для карточки есть текст про источник цены")
        H.ok(text and ns.Util.contains(text, "один источник"),
            "в котором сказано, что источник один: " .. tostring(text))
    end
end

-- КОНЦЕНТРАЦИЯ: БОЛЬШИНСТВО СОВЕТОВ ВЕДЁТ К ОДНОМУ NPC ===================
--
-- Живой прогон: семь из восьми карточек «Купить и перепродать» вели к Mister
-- Graphed. Это само по себе подозрение, независимо от того, правдоподобна ли
-- каждая цена по отдельности.

H.suite("Концентрация: большинство советов на одного NPC — это подозрение")
do
    local env = H.load()
    local ns = env.ns
    env.money = 500000
    env.auctionator = true
    -- Пять товаров у одного торговца и один у другого: 5 из 6 - большинство.
    local many = { 8001, 8002, 8003, 8004, 8005 }
    for i, id in ipairs(many) do
        H.item(env, id, { name = "Товар " .. i, sellPrice = 100, stackCount = 20 })
        env.prices[id] = 3000
        -- В круг поиска кандидат попадает, только если аддон уже знает предмет
        -- по другому поводу - в сумке, в рецепте, в истории цен. Кладём в сумку:
        -- это тот же путь, которым в игре попадают настоящие кандидаты.
        env.bags[id] = 1
        env.codexItems[id] = {
            sources = { { type = "vendor", npc = 263384, cost = 500, from = { "recordings" } } },
        }
    end
    H.item(env, 8006, { name = "Товар шесть", sellPrice = 100, stackCount = 20 })
    env.prices[8006] = 3000
    env.bags[8006] = 1
    env.codexItems[8006] = {
        sources = { { type = "vendor", npc = 3364, cost = 500, from = { "recordings" } } },
    }
    env.codexNpcs[263384] = {
        name = "Mister Graphed", subName = "Agent of the Black Market",
        roles = { "vendor" }, spawns = { { map = 2548, x = 78.2, y = 51.9 } },
    }
    env.codexNpcs[3364] = {
        name = "Темный Торговец", roles = { "vendor" },
        spawns = { { map = 1637, x = 52, y = 61 } },
    }
    H.rescan(env)
    local cards = H.build(env)

    local arb = {}
    for _, c in ipairs(cards) do
        if c.kind == ns.KIND.ARBITRAGE then arb[#arb + 1] = c end
    end
    H.ok(#arb >= 3, "карточек перепродажи несколько: " .. #arb)

    -- 1. Концентрация посчитана и доступна движку.
    local conc = ns.VendorArbitrage.lastConcentration
    H.ok(conc ~= nil, "концентрация посчитана")
    if conc then
        H.eq(conc.npcID, 263384, "виновник назван по номеру")
        H.ok(conc.share >= 0.5, "и его доля - большинство: " .. tostring(conc.share))
        H.ok(conc.npcName ~= nil and ns.Util.contains(conc.npcName, "Graphed"),
            "с именем: " .. tostring(conc.npcName))
    end

    -- 2. Карточки этого торговца помечены, и достоверность у них ниже.
    local flagged, unflagged = 0, 0
    for _, c in ipairs(arb) do
        if c.arbitrage and c.arbitrage.npcID == 263384 then
            if c.concentration then flagged = flagged + 1 else unflagged = unflagged + 1 end
        end
    end
    H.ok(flagged > 0, "карточки этого торговца помечены: " .. flagged)
    H.eq(unflagged, 0, "и непомеченных среди них нет")
    for _, c in ipairs(arb) do
        if c.concentration then
            H.ok(ns.Util.contains(c.why or "", "одному торговцу"),
                "в тексте сказано про концентрацию: "
                .. ns.Util.truncate(c.why or "", 240))
            H.ok(ns.Util.contains(c.why or "", "Graphed"),
                "и назван сам торговец")
            H.ok(c.conf ~= ns.CONF.EXACT and c.conf ~= ns.CONF.CACHED,
                "и достоверность понижена: " .. tostring(c.conf))
            break
        end
    end

    -- 3. И это записано в диагностику, а не только нарисовано.
    local found
    for _, s in ipairs(ns.Diag:Init().suspicious or {}) do
        if s.code == "advice-concentrated-on-one-source" then found = s end
    end
    H.ok(found ~= nil, "странность «советы сошлись на одном источнике» записана")
    if found then
        H.ok(ns.Util.contains(found.text or "", "Graphed"),
            "и в ней назван источник: " .. ns.Util.truncate(found.text or "", 200))
    end
end

H.suite("Концентрация: разные торговцы — молчим")
do
    local env = H.load()
    local ns = env.ns
    env.money = 500000
    env.auctionator = true
    for i, pair in ipairs({ { 8101, 3364 }, { 8102, 3365 }, { 8103, 3366 },
                            { 8104, 3367 } }) do
        local id, npc = pair[1], pair[2]
        H.item(env, id, { name = "Товар " .. i, sellPrice = 100, stackCount = 20 })
        env.prices[id] = 3000
        env.bags[id] = 1
        env.codexItems[id] = {
            sources = { { type = "vendor", npc = npc, cost = 500,
                          from = { "recordings", "questie" } } },
        }
        env.codexNpcs[npc] = { name = "Торговец " .. i, roles = { "vendor" },
                               spawns = { { map = 1637, x = 50 + i, y = 60 } } }
    end
    H.rescan(env)
    local cards = H.build(env)
    local conc = ns.VendorArbitrage.lastConcentration
    H.eq(conc, nil, "концентрации нет — торговцы разные")
    for _, c in ipairs(cards) do
        if c.kind == ns.KIND.ARBITRAGE then
            H.eq(c.concentration, nil, "и карточки не помечены")
            break
        end
    end
    local found = false
    for _, s in ipairs(ns.Diag:Init().suspicious or {}) do
        if s.code == "advice-concentrated-on-one-source" then found = true end
    end
    H.eq(found, false, "и в диагностике тихо")
end

end
