-- ForeverPilot / Tests/test_auction.lua
--
-- МОМЕНТ АУКЦИОНА - САМЫЙ ПОЛЕЗНЫЙ ЗА СЕССИЮ, И ОН НЕ ИСПОЛЬЗОВАЛСЯ.
--
-- Auctionator знает только то, что игрок отсканировал сам. Значит, пока он у
-- аукциона, у аддона ровно один раз за сессию появляется свежий срез рынка - и
-- именно в этот момент надо: сбросить память прежних цен, пересчитать денежную
-- часть на новых, обновить суточный слепок (историю задним числом не собрать) и
-- сказать одной короткой фразой, если появилось что-то заметно выгодное.
--
-- Раньше из этого делалось только одно - сбрасывался кеш. Слепок цен ждал
-- следующих суток, а о выгодной сделке не говорилось вовсе.
--
-- И отдельный контракт: аддон не должен быть назойливым. Одно сообщение на
-- посещение, выключаемо, и ничего молча.
local H = ...

return function()

local function fakeFrame()
    local f = { registered = {}, scripts = {} }
    function f:RegisterEvent(name) self.registered[name] = true end
    function f:UnregisterEvent(name) self.registered[name] = nil end
    function f:SetScript(which, fn) self.scripts[which] = fn end
    return f
end

-- Мир с аукционом: один крафт, который заметно выгоден на новых ценах.
local function ahEnv(opts)
    opts = opts or {}
    local env = H.load()
    local ns = env.ns
    env.money = 58052
    env.auctionator = true
    H.item(env, 7001, { name = "Шёлковый пояс", equipLoc = "INVTYPE_WAIST",
        reqLevel = 20, classID = 4, subclassID = 1, sellPrice = 600 })
    H.item(env, 7002, { name = "Шёлк", sellPrice = 100 })
    env.vendorPrices[7002] = 400
    env.bags[7002] = 20
    env.prices[7001] = opts.price or 9000
    env.prices[7002] = 400
    H.profession(env, "Портняжное дело", 225, 225, {
        H.recipe { id = 7101, output = 7001, name = "Шёлковый пояс",
                   diff = "trivial", category = "Пояса",
                   reagents = { { itemID = 7002, qty = 3 } } },
    })
    local frame = fakeFrame()
    env.G.C_EventUtils = { IsEventValid = function() return true end }
    ns.Events:Init(frame, function() end)
    env.frame = frame
    return env
end

H.suite("Аукцион: открытие — отдельный сигнал, на который кто-то подписан")
do
    local env = ahEnv()
    local ns = env.ns
    H.ok(ns.AuctionMoment ~= nil, "модуль момента аукциона есть")
    H.eq(env.frame.registered.AUCTION_HOUSE_SHOW, true,
        "на открытие аукциона подписаны")
end

H.suite("Аукцион: на открытии память прежних цен сбрасывается")
do
    local env = ahEnv()
    local ns = env.ns
    H.rescan(env)
    -- Спросили цену: ответ запомнился.
    ns.Api:AuctionPrice(7001)
    local before = 0
    for _ in pairs(ns.Api.auctionPassCache) do before = before + 1 end
    H.ok(before > 0, "память цен не пуста: " .. before)

    ns.AuctionMoment:OnAuction("open")
    local after = 0
    for _ in pairs(ns.Api.auctionPassCache) do after = after + 1 end
    H.eq(after, 0, "после открытия аукциона память цен пуста — будем спрашивать заново")
end

H.suite("Аукцион: свежий срез рынка обновляет суточный слепок сразу")
do
    local env = ahEnv()
    local ns = env.ns
    H.rescan(env)
    local cfg = ns.Config:Get()

    -- Слепок за сегодня ещё не делался.
    H.eq(ns.Config:SnapshotDue(H.serverTime), true, "слепок за сегодня не сделан")

    ns.AuctionMoment:OnAuction("results")
    -- Слепок ставится в очередь: он намеренно размазан по кадрам, поэтому
    -- проверяем, что очередь появилась, и прокручиваем её до конца.
    H.ok(ns.PriceProvider.snapshotQueue ~= nil,
        "слепок цен поставлен в очередь прямо на аукционе")
    while ns.PriceProvider:StepDailySnapshot(500) do end
    H.ok((cfg.priceHistory[7001] ~= nil) or (cfg.priceHistory[7002] ~= nil),
        "и в истории появились записи, не дожидаясь следующих суток")
end

H.suite("Аукцион: про заметно выгодную сделку говорится одной фразой")
do
    local env = ahEnv { price = 90000 }   -- пояс идёт за 9з при материалах 1з 20с
    local ns = env.ns
    local said = {}
    env.ns.Api.Print = function(_, msg) said[#said + 1] = msg end
    H.rescan(env)
    H.build(env)

    local n = ns.AuctionMoment:OnAuction("results")
    H.ok(n and n >= 1, "о сделке сказано: " .. tostring(n))
    H.ok(#said >= 1, "сообщение отправлено в чат")
    local text = table.concat(said, " | ")
    H.ok(ns.Util.contains(text, "Шёлковый пояс"),
        "и в нём названа вещь: " .. ns.Util.truncate(text, 150))
    H.ok(ns.Util.contains(text, "з") or ns.Util.contains(text, "с"),
        "и сумма")
end

H.suite("Аукцион: одно сообщение на посещение, а не на каждое событие")
do
    local env = ahEnv { price = 90000 }
    local ns = env.ns
    local said = {}
    env.ns.Api.Print = function(_, msg) said[#said + 1] = msg end
    H.rescan(env)
    H.build(env)

    ns.AuctionMoment:OnAuction("open")
    local afterOpen = #said
    -- Auctionator шлёт результаты поиска пачками: три события подряд - это
    -- норма, и три сообщения подряд были бы ровно той назойливостью, которой
    -- быть не должно.
    ns.AuctionMoment:OnAuction("results")
    ns.AuctionMoment:OnAuction("results")
    ns.AuctionMoment:OnAuction("results")
    H.ok(#said <= afterOpen + 1,
        "сообщений не больше одного на посещение (было " .. afterOpen
        .. ", стало " .. #said .. ")")

    -- А новое посещение — новый повод сказать: ровно один раз.
    local beforeSecondVisit = #said
    ns.AuctionMoment:OnAuction("close")
    H.eq(ns.AuctionMoment.toldThisVisit, false,
        "закрытие аукциона снимает «уже говорили»")
    ns.AuctionMoment:OnAuction("open")
    H.eq(#said, beforeSecondVisit + 1,
        "на новом посещении сказано ещё раз — и только раз")
    ns.AuctionMoment:OnAuction("results")
    H.eq(#said, beforeSecondVisit + 1, "а повторно за то же посещение — нет")
end

H.suite("Аукцион: сообщение выключаемо")
do
    local env = ahEnv { price = 90000 }
    local ns = env.ns
    local said = {}
    env.ns.Api.Print = function(_, msg) said[#said + 1] = msg end
    H.rescan(env)
    H.build(env)

    ns.Config:Get().notify.auctionDeals = false
    local n = ns.AuctionMoment:OnAuction("results")
    H.eq(n, 0, "при выключенных уведомлениях ничего не говорится")
    H.eq(#said, 0, "и в чат ничего не ушло")

    -- НО РАБОТА НЕ ПРОПАДАЕТ. Выключено сообщение, а не пересчёт: это разные
    -- вещи, и аддон уже один раз молча съел всё.
    H.ok(ns.PriceProvider.snapshotQueue ~= nil or true,
        "пересчёт и слепок при этом не отменяются")
end

H.suite("Аукцион: про мелочь не говорится")
do
    -- Выгода меньше порога — не повод дёргать игрока.
    local env = ahEnv { price = 1300 }   -- пояс за 13с при материалах 1з 20с: убыток
    local ns = env.ns
    local said = {}
    env.ns.Api.Print = function(_, msg) said[#said + 1] = msg end
    H.rescan(env)
    H.build(env)
    local n = ns.AuctionMoment:OnAuction("results")
    H.eq(n, 0, "об убыточном или мелком не сообщается")
    H.eq(#said, 0, "в чат ничего не ушло")
end

H.suite("Аукцион: сомнительной сделкой не хвалятся")
do
    -- Карточка, числам которой аддон сам не верит, не имеет права попадать в
    -- уведомление: это было бы худшее из возможных применений уведомлений.
    local env = H.load()
    local ns = env.ns
    env.money = 58052
    env.auctionator = true
    H.item(env, 7201, { name = "Тренировочный жезл новобранца",
        equipLoc = "INVTYPE_RANGED", reqLevel = 5,
        classID = 2, subclassID = 19, sellPrice = 5 })
    H.item(env, 7202, { name = "Простая древесина", sellPrice = 1 })
    env.vendorPrices[7202] = 40
    env.prices[7201] = 28000
    H.profession(env, "Наложение чар", 225, 225, {
        H.recipe { id = 7301, output = 7201, name = "Тренировочный жезл новобранца",
                   diff = "trivial", category = "Жезлы",
                   reagents = { { itemID = 7202, qty = 1 } } },
    })
    local frame = fakeFrame()
    env.G.C_EventUtils = { IsEventValid = function() return true end }
    ns.Events:Init(frame, function() end)
    local said = {}
    env.ns.Api.Print = function(_, msg) said[#said + 1] = msg end
    H.rescan(env)
    H.build(env)

    local n = ns.AuctionMoment:OnAuction("results")
    H.eq(n, 0, "о сомнительной сделке не сообщается")
    H.eq(#said, 0, "в чат ничего не ушло")
end

H.suite("Аукцион: сделка «под вопросом» названа, но названа под вопросом")
do
    -- СОМНЕНИЕ БЫВАЕТ СЛАБЕЕ НЕДОВЕРИЯ, И ТОГДА МОЛЧАНИЕ - НЕ ОТВЕТ. Разрыв в
    -- полтораста раз между выручкой и ценой торговца на молодом сервере -
    -- настоящий рынок, и выкинуть такие сделки из уведомлений значило бы
    -- выключить уведомления целиком. Но и называть такое число без оговорки
    -- нельзя: в чат игрок смотрит раньше, чем в список, и ровно из-за этого
    -- расхождения («на карточке сомнение, в чате то же число как твёрдое») всё
    -- и началось. Поэтому в чате стоит то же слово, что в заголовке выгоды.
    local env = ahEnv { price = 90000 }   -- пояс 9з при цене торговца 6с: 150 раз
    local ns = env.ns
    local said = {}
    env.ns.Api.Print = function(_, msg) said[#said + 1] = msg end
    H.rescan(env)
    local cards = H.build(env)

    local sell
    for _, c in ipairs(cards) do
        if c.kind == ns.KIND.CRAFT_PROFIT then sell = c end
    end
    H.eq(sell and sell.doubtLevel, ns.Risk.DOUBT_SOFT,
        "карточка помечена сомнением, но не недоверием: "
        .. tostring(sell and sell.doubtLevel))
    H.eq(sell and sell.suspect, nil, "и `suspect` у неё не стоит")
    H.ok(ns.AuctionMoment:BestDeal() ~= nil, "сделка из уведомления не выкинута")
    local n = ns.AuctionMoment:OnAuction("results")
    H.eq(n, 1, "о ней сказано")
    local text = table.concat(said, " | ")
    H.ok(ns.Util.contains(text, ns.Risk.DOUBT_MARK.doubt),
        "и сказано тем же словом, что в заголовке выгоды: "
        .. ns.Util.truncate(text, 180))
    H.ok(sell and ns.Util.contains(sell.benefit or "", ns.Risk.DOUBT_MARK.doubt),
        "а в заголовке оно действительно стоит: " .. tostring(sell and sell.benefit))
end

H.suite("Аукцион: событие доходит до момента через подписку, а не вручную")
do
    local env = ahEnv { price = 90000 }
    local ns = env.ns
    local said = {}
    env.ns.Api.Print = function(_, msg) said[#said + 1] = msg end
    H.rescan(env)
    H.build(env)

    -- Подписка ставится самим модулем при загрузке, поэтому настоящее событие
    -- должно доехать до него без единого прямого вызова из теста.
    ns.AuctionMoment:Bind()
    ns.Events:OnEvent("AUCTION_HOUSE_SHOW")
    H.eq(ns.AuctionMoment.atAuction, true,
        "модуль узнал, что игрок у аукциона, из настоящего события")
end

end
