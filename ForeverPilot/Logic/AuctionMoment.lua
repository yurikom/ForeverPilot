-- ForeverPilot / Logic/AuctionMoment.lua
--
-- САМЫЙ ПОЛЕЗНЫЙ МОМЕНТ ЗА СЕССИЮ, КОТОРЫЙ НЕ ИСПОЛЬЗОВАЛСЯ.
--
-- Auctionator знает только то, что игрок отсканировал сам - это принципиальное
-- ограничение, обойти его нельзя. Значит, ровно в тот момент, когда игрок стоит
-- у аукциона, у аддона появляется свежий срез рынка, и этот момент за сессию
-- бывает один раз. Делать в него надо четыре вещи:
--
--   1. забыть прежние ответы Auctionator - они только что устарели;
--   2. пересчитать денежную часть на новых ценах;
--   3. обновить суточный слепок цен, НЕ ДОЖИДАЯСЬ следующих суток - историю
--      задним числом не собрать, а игрок может сюда больше не зайти;
--   4. если появилось что-то заметно выгодное - сказать об этом ОДНОЙ короткой
--      фразой.
--
-- Раньше делалось только первое.
--
-- ПРО НАЗОЙЛИВОСТЬ. Auctionator присылает результаты поиска пачками, и три
-- сообщения подряд - это ровно то, из-за чего уведомления выключают навсегда.
-- Поэтому: одно сообщение на посещение, порог по сумме, выключается в
-- настройках. И ни одного тихого действия: выключено СООБЩЕНИЕ, а не пересчёт,
-- и в настройках это так и написано.
--
-- Никакой автоматизации: аддон ничего не покупает, не продаёт и не выставляет.
-- Он читает цены, которые Auctionator уже собрал, и говорит словами.
local ADDON, ns = ...

local U = ns.Util
local Api = ns.Api

local AM = {}
ns.AuctionMoment = AM

-- Ниже этой выгоды за один крафт игрока не дёргают. Для персонажа с пятью
-- золотыми золотой - это заметно, десять медных - нет.
AM.MIN_DEAL_COPPER = 5000

AM.atAuction = false
AM.toldThisVisit = false
AM.visits = 0

-- Подписка. Ставится один раз; модуль сам решает, что делать с сигналом.
function AM:Bind()
    if AM.bound then return end
    AM.bound = true
    ns.Events:On("auction", function(what) AM:OnAuction(what) end)
end

-- Главный вход. `what` - "open" | "close" | "results".
-- Возвращает, сколько сделок было названо (0 или 1).
function AM:OnAuction(what)
    if what == "close" then
        AM.atAuction = false
        AM.toldThisVisit = false
        return 0
    end
    if what == "open" then
        AM.atAuction = true
        AM.toldThisVisit = false
        AM.visits = AM.visits + 1
    end

    -- 1. Прежние ответы Auctionator больше не действительны.
    --
    -- С ОГРАНИЧИТЕЛЕМ, И ЭТО ГЛАВНАЯ ЦЕНА ЭТОГО МОДУЛЯ. Сигналов аукциона за
    -- вечер 276 (открытие и закрытие окна, каждая пачка результатов поиска,
    -- каждое обновление своих лотов), а сканирование у Auctionator одно.
    -- Забывание стоит 367 чтений цен и 80-125 мс на следующем пересчёте, и в
    -- живом файле игрока оно случилось 108 раз - отсюда 41 804 обращения к
    -- Auctionator за сессию и пик пересчёта в 124.7 мс против 33 средних.
    -- Второй аргумент означает «это обычный сигнал»: такие забывания проходят
    -- не чаще раза в ns.AUCTION_RESCAN_GUARD, а отложенное не теряется.
    if Api.ClearAuctionCache then
        Api:ClearAuctionCache("игрок у аукциона: " .. tostring(what), true)
    end

    -- 2. Пересчёт денежной части. Делается через обычный механизм - помечаем
    -- цены грязными и отдаём планировщику; он сам соблюдёт троттлинг и не
    -- станет пересчитывать три раза на три пачки результатов.
    ns.Events:MarkDirty("prices")

    -- 3. Суточный слепок - СЕЙЧАС, а не по расписанию. Это единственное место,
    -- где цены заведомо свежие, и единственный момент, который нельзя
    -- отложить: история за сегодня либо запишется сейчас, либо не запишется.
    local queued = AM:Snapshot()

    -- 4. Одна фраза про одну сделку.
    local told = AM:MaybeTellBestDeal()

    if ns.Diag then
        ns.Diag:Module("auctionMoment", {
            ["in"] = 1, out = told,
            what = what, visits = AM.visits,
            snapshotQueued = queued,
            toldThisVisit = AM.toldThisVisit,
            reason = (told == 0) and AM.lastSilenceReason or nil,
            reasonCode = (told == 0) and "FILTERED_OUT" or nil,
        })
    end
    return told
end

-- Поставить суточный слепок в очередь, даже если он уже делался сегодня: цены
-- на аукционе точно свежее, чем те, что лежали в базе при входе в игру.
function AM:Snapshot()
    if not ns.PriceProvider then return false end
    local items = ns.ActionEngine and ns.ActionEngine:TrackedItems() or nil
    if not items then return false end
    local ok = ns.PriceProvider:QueueDailySnapshot(items)
    if ok then return true end
    -- Слепок за сегодня уже есть. Это не повод ничего не делать: цены сейчас
    -- точно свежее, и перезапись сегодняшней записи - то, что надо.
    if ns.PriceProvider.RequeueToday then
        return ns.PriceProvider:RequeueToday(items) and true or false
    end
    return false
end

-- Настройки уведомлений, с безопасным ответом по умолчанию.
function AM:Enabled()
    local cfg = ns.Config and ns.Config:Get()
    local n = cfg and cfg.notify
    if not n then return true end
    return n.auctionDeals ~= false
end

-- Лучшая сделка из того, что УЖЕ посчитал движок. Никаких своих расчётов: если
-- карточки нет в списке, то и сделки нет - иначе уведомление и экран начнут
-- расходиться, а расхождение между ними игрок читает как вранье.
function AM:BestDeal()
    local best
    for _, card in ipairs((ns.ActionEngine and ns.ActionEngine.cards) or {}) do
        local money = card.benefitValue
        -- ЧТО СЧИТАЕТСЯ ДЕНЕЖНЫМ СОВЕТОМ - ОДИН ПЕРЕЧЕНЬ НА ВЕСЬ АДДОН.
        --
        -- Здесь стоял свой список из четырёх видов, и распыление в него не
        -- попало: сделка «купить и распылить» у аукциона не называлась никогда,
        -- хотя это ровно такой же денежный совет. Теперь перечень один
        -- (ns.MONEY_FLOOR_KINDS, Core/Const.lua) - тот же, по которому работает
        -- порог мелкой выгоды, и разойтись им больше негде.
        local isMoney = (ns.MONEY_FLOOR_KINDS or {})[card.kind] == true
        -- СОМНИТЕЛЬНЫМ НЕ ХВАЛЯТСЯ. Карточка, числам которой аддон сам не
        -- верит, в уведомление попасть не может: это было бы худшее возможное
        -- применение уведомлений.
        --
        -- НО СОМНЕНИЕ БЫВАЕТ СЛАБЕЕ НЕДОВЕРИЯ, И ТОГДА МОЛЧАНИЕ - НЕ ОТВЕТ.
        -- Разрыв в полтораста раз между выручкой и ценой торговца на молодом
        -- сервере - настоящий рынок (см. Risk.VENDOR_RATIO_NOTE), и выкинуть все
        -- такие сделки значило бы выключить уведомления целиком. Поэтому такая
        -- сделка называется, но НАЗЫВАЕТСЯ СОМНИТЕЛЬНОЙ - тем же словом, что
        -- стоит у неё в заголовке выгоды (см. MaybeTellBestDeal ниже).
        local distrusted = card.suspect ~= nil
            or (ns.Risk and card.doubtLevel == ns.Risk.DOUBT_DISTRUST)
        if isMoney and not distrusted and money and money >= AM.MIN_DEAL_COPPER then
            if (not best) or money > best.benefitValue then best = card end
        end
    end
    return best
end

function AM:MaybeTellBestDeal()
    AM.lastSilenceReason = nil
    if not AM:Enabled() then
        AM.lastSilenceReason = "уведомления о сделках выключены в настройках"
        return 0
    end
    if AM.toldThisVisit then
        AM.lastSilenceReason = "за это посещение аукциона уже говорили"
        return 0
    end
    local card = AM:BestDeal()
    if not card then
        AM.lastSilenceReason = "заметно выгодного нет: порог "
            .. U.money(AM.MIN_DEAL_COPPER)
        return 0
    end

    AM.toldThisVisit = true
    -- Коротко: что сделать, сколько это даёт, и насколько этому можно верить.
    -- Больше одной строки в чат не идёт - за подробностями /fp.
    local conf = ns.CONF_LABEL[card.conf] or "?"
    local risk = card.risk and ns.Risk and ns.Risk:Badge(card.risk) or nil
    -- СОМНЕНИЕ ЕДЕТ И В ЧАТ, ТЕМ ЖЕ СЛОВОМ, ЧТО В ЗАГОЛОВКЕ ВЫГОДЫ. Иначе
    -- получилось бы ровно то, с чего всё началось: на карточке «под вопросом», а
    -- в чате то же число без оговорки - и в чат игрок смотрит первым.
    local mark = (ns.Risk and card.doubtLevel)
        and ns.Risk.DOUBT_MARK[card.doubtLevel] or nil
    Api:Print("пока вы у аукциона: «" .. tostring(card.title) .. "» — "
        .. (mark and (mark .. ": ") or "")
        .. U.moneyDelta(card.benefitValue) .. " (" .. conf .. ")"
        .. (risk and (", " .. risk) or "")
        .. ". Подробнее — /fp")
    if ns.Diag then ns.Diag:Count("auction.dealTold") end
    return 1
end

return AM
