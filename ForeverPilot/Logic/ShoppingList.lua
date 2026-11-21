-- ForeverPilot / Logic/ShoppingList.lua
--
-- One list of everything the suggested actions would need the player to buy,
-- with quantities, merged across cards so the same cloth is not listed twice.
--
-- Auctionator can take the list over and search it for us, but that call is one
-- of the ones its own README marks as liable to break, and MultiSearch also
-- needs the auction house to be open. So the list is ours: we keep the
-- quantities, we show the totals, and handing it to Auctionator is a bonus that
-- is allowed to fail without costing the player anything.
local ADDON, ns = ...

local U = ns.Util
local Api = ns.Api
local CONF = ns.CONF

local Shopping = {}
ns.ShoppingList = Shopping

-- itemID -> { gross, pinned, unit, conf, src, age, forCards = {} }
--
-- `gross` is the total the suggested actions ask for, BEFORE the player's own
-- stock is taken off. The stock is subtracted once, at the end, by Lines(): two
-- cards that each need ten bolts of cloth cannot both be covered by the same
-- seven in the bags, and summing their individual shortfalls said they could.
Shopping.items = {}
Shopping.order = {}
Shopping.inventory = nil   -- itemID -> qty the player already owns

function Shopping:Reset()
    self.items, self.order = {}, {}
    self.inventory = nil
end

-- The stock the whole list is allowed to count against. Called once per
-- rebuild, from the snapshot, so the subtraction matches what the planner used.
function Shopping:SetInventory(snap)
    if type(snap) ~= "table" then self.inventory = nil; return end
    local cfg = ns.Config:Get()
    local useBank = not (cfg and cfg.show and cfg.show.includeBank == false)
    local have = {}
    for itemID, qty in pairs(snap.bags or {}) do
        have[itemID] = (have[itemID] or 0) + (tonumber(qty) or 0)
    end
    if useBank then
        for itemID, e in pairs(snap.owned or {}) do
            local extra = (tonumber(e.bank) or 0) + (tonumber(e.alts) or 0)
            if extra > 0 then have[itemID] = (have[itemID] or 0) + extra end
        end
    end
    self.inventory = have
end

function Shopping:Have(itemID)
    if not (self.inventory and itemID) then return 0 end
    return self.inventory[itemID] or 0
end

-- Fold a plan's materials into the list, at gross quantities.
--
-- `suspectWhy` - когда карточка, попросившая этот материал, сама помечена
-- сомнительной (её числа друг другу противоречат). Материал всё равно попадает
-- в список: выкинуть его молча означало бы менять сумму покупок из-за
-- суждения, которого игрок не видит. Вместо этого причина едет вместе со
-- строкой, и если ВСЕ, кому материал нужен, сомнительны - карточка покупки
-- говорит об этом прямо.
function Shopping:AddPlan(plan, cardKey, cardTitle, suspectWhy)
    if type(plan) ~= "table" then return end

    -- Price and buyability come from the plan's own priced lines.
    local priced = {}
    for _, line in ipairs(plan.shopping or {}) do priced[line.itemID] = line end

    local gross = plan.needGross
    if type(gross) ~= "table" or next(gross) == nil then
        -- A plan from before gross tracking: fall back to its net lines.
        for _, line in ipairs(plan.shopping or {}) do
            self:Add(line.itemID, line.qty, cardKey, cardTitle, line, suspectWhy)
        end
        return
    end

    for _, itemID in ipairs(U.sortedKeys(gross)) do
        -- Only things the plan acquires rather than crafts belong on a shopping
        -- list; a crafted intermediate is represented by its own reagents.
        local decision = plan.decisions and plan.decisions[itemID]
        if not (decision and decision.method == "craft") then
            self:Add(itemID, gross[itemID], cardKey, cardTitle, priced[itemID],
                suspectWhy)
        end
    end
end

-- `qty` here is a GROSS requirement: what is needed in total, before stock.
function Shopping:Add(itemID, qty, cardKey, cardTitle, priced, suspectWhy)
    if not itemID then return end
    qty = tonumber(qty) or 0
    if qty <= 0 then return end

    local entry = self.items[itemID]
    if not entry then
        entry = {
            itemID = itemID, gross = 0, pinned = 0, unit = nil,
            conf = CONF.UNKNOWN, src = nil, age = nil, forCards = {},
            buyable = false,
            trustedUses = 0, suspectUses = 0, suspectWhy = nil,
        }
        self.items[itemID] = entry
        self.order[#self.order + 1] = itemID
    end
    entry.gross = entry.gross + qty
    -- Кто попросил: совет, которому я верю, или тот, которому нет. Считаются
    -- оба, потому что «нужен только сомнительным» и «нужен и нормальным тоже» -
    -- это разные советы для игрока.
    if suspectWhy then
        entry.suspectUses = (entry.suspectUses or 0) + 1
        entry.suspectWhy = entry.suspectWhy or suspectWhy
    else
        entry.trustedUses = (entry.trustedUses or 0) + 1
    end

    -- A price the first card did not have may be known by the second one, so
    -- the best answer available wins instead of whichever arrived first.
    if entry.unit == nil then
        local unit, conf, src, age, buyable
        if priced and priced.unit ~= nil then
            unit, conf, src, age = priced.unit, priced.conf, priced.src, priced.age
            buyable = priced.buyable
        else
            unit, conf, src, age = ns.PriceProvider:Buy(itemID)
            buyable = ns.PriceProvider:Buyable(itemID)
        end
        if unit ~= nil then
            entry.unit, entry.conf, entry.src, entry.age = unit, conf or CONF.UNKNOWN, src, age
            entry.buyable = buyable and true or false
        elseif priced == nil then
            entry.buyable = buyable and true or false
        end
        -- ГДЕ КУПИТЬ ДЕШЕВЛЕ - РЕШЕНО ОДИН РАЗ И ЧИТАЕТСЯ ЗДЕСЬ.
        --
        -- Решение по вендорному потолку живёт в Logic/PriceProvider.lua; список
        -- покупок его не считает заново, иначе текст строки и цена в ней
        -- разъехались бы при первой же правке порога.
        entry.ceiling = ns.PriceProvider and ns.PriceProvider:Ceiling(itemID) or nil
    end

    if cardKey and not entry.forCards[cardKey] then
        entry.forCards[cardKey] = cardTitle or cardKey
    end
end

-- What actually has to be bought for an entry: the gross need less the stock,
-- and never less than what the player pinned by hand.
function Shopping:NetQty(entry)
    if type(entry) ~= "table" then return 0 end
    local have = self:Have(entry.itemID)
    local net = math.max(0, (entry.gross or 0) - have)
    return math.max(net, entry.pinned or 0)
end

-- The list, biggest spend first. Items with no price sort last and are flagged.
function Shopping:Lines()
    local out = {}
    for _, itemID in ipairs(self.order) do
        local e = self.items[itemID]
        local qty = self:NetQty(e)
        if e and qty > 0 then
            local info = Api:ItemInfo(itemID)
            local uses = {}
            for _, title in pairs(e.forCards) do uses[#uses + 1] = title end
            table.sort(uses)
            out[#out + 1] = {
                itemID = itemID,
                name = info and info.name or U.itemFallbackName(itemID),
                link = info and info.link or nil,
                texture = info and info.texture or nil,
                qty = qty,
                gross = e.gross,
                have = self:Have(itemID),
                pinned = (e.pinned or 0) > 0 and e.pinned or nil,
                unit = e.unit,
                subtotal = e.unit and e.unit * qty or nil,
                conf = e.conf,
                src = e.src,
                age = e.age,
                buyable = e.buyable,
                uses = uses,
                -- КТО ИМЕННО ПОПРОСИЛ, ПО КЛЮЧАМ СОВЕТОВ, А НЕ ТОЛЬКО ПО ИМЕНАМ.
                --
                -- Имена нужны, чтобы написать «нужно для: На продажу: …».
                -- Ключи нужны затем, что совет-заказчик может до экрана не
                -- дойти (его убрал порог мелкой денежной выгоды, игрок его
                -- скрыл), и тогда карточка покупки обязана либо переписать
                -- строку, либо уйти вместе с ним. Без ключей отличить
                -- оставшихся заказчиков от ушедших нечем.
                forCards = e.forCards,
                -- Нужен ТОЛЬКО под советы, числам которых я не верю.
                suspectOnly = ((e.suspectUses or 0) > 0
                    and (e.trustedUses or 0) == 0 and (e.pinned or 0) == 0) or nil,
                suspectWhy = e.suspectWhy,
                -- ВЕНДОРНЫЙ ПОТОЛОК ЭТОЙ СТРОКИ. `vendorCheaper` - у торговца
                -- дешевле, чем на аукционе; `vendorSaving` - сколько это даёт
                -- на ВСЁ количество, а не за штуку: игрок покупает qty.
                ceiling = e.ceiling,
                vendorCheaper = (e.ceiling and e.ceiling.cheaper == "vendor"
                    and e.ceiling.saving) and true or nil,
                vendorSaving = (e.ceiling and e.ceiling.cheaper == "vendor"
                    and e.ceiling.saving) and (e.ceiling.saving * qty) or nil,
                ceilingText = (e.ceiling and ns.PriceProvider
                    and ns.PriceProvider:CeilingText(itemID)) or nil,
            }
        end
    end
    table.sort(out, function(a, b)
        local sa, sb = a.subtotal or -1, b.subtotal or -1
        if sa ~= sb then return sa > sb end
        return a.itemID < b.itemID
    end)
    return out
end

-- Returns total copper, confidence, and how many lines had no price.
function Shopping:Total()
    local total, conf, unknown = 0, CONF.EXACT, 0
    for _, itemID in ipairs(self.order) do
        local e = self.items[itemID]
        local qty = self:NetQty(e)
        if e and qty > 0 then
            if e.unit then
                total = total + e.unit * qty
                conf = U.worstConf(conf, e.conf)
            else
                unknown = unknown + 1
                conf = CONF.UNKNOWN
            end
        end
    end
    return total, conf, unknown
end

function Shopping:Count()
    local n = 0
    for _, itemID in ipairs(self.order) do
        if self:NetQty(self.items[itemID]) > 0 then n = n + 1 end
    end
    return n
end

-- СКОЛЬКО ВСЕГО СЭКОНОМИТ ПОХОД К ТОРГОВЦУ ВМЕСТО АУКЦИОНА.
--
-- Возвращает { lines, saving, names } или nil, когда экономить нечего. Считается
-- по тем же строкам и тем же решениям, что показаны в списке: отдельная
-- арифметика «на глаз» разошлась бы с суммой в списке на первой же правке.
function Shopping:VendorSaving()
    local lines, saving, names = 0, 0, {}
    for _, line in ipairs(self:Lines()) do
        if line.vendorSaving and line.vendorSaving > 0 then
            lines = lines + 1
            saving = saving + line.vendorSaving
            if #names < 3 then names[#names + 1] = line.name end
        end
    end
    if lines == 0 then return nil end
    return { lines = lines, saving = saving, names = names }
end

-- Can the player afford the whole list, and should they? The spend cap keeps us
-- from telling someone with 2 gold to go and spend 2 gold.
--
-- With any line unpriced the total is an understatement, so "you can afford it"
-- is not a conclusion we are entitled to: `affordable` and `withinCap` come
-- back nil and the caller has to say it does not know.
function Shopping:Affordability(snap)
    local total, conf, unknown = self:Total()
    local money = (snap and snap.money) or 0
    local cfg = ns.Config:Get()
    local share = (cfg and cfg.show and cfg.show.maxSpendShare) or 0.6
    local cap = share * money
    local complete = (unknown == 0)
    -- Written out rather than with and/or: `complete and (total <= money) or nil`
    -- collapses a legitimate `false` into `nil`, which is how "you cannot afford
    -- this" turned into "I have no idea".
    local affordable, withinCap, shortfall
    if complete then
        affordable = (total <= money)
        withinCap = (total <= cap)
        shortfall = math.max(0, total - money)
    end
    return {
        total = total, conf = conf, unknownLines = unknown, complete = complete,
        money = money,
        affordable = affordable,
        withinCap = withinCap,
        cap = cap,
        shortfall = shortfall,
    }
end

-- Handoff to Auctionator ------------------------------------------------
--
-- КНОПКА «ИСКАТЬ НА АУКЦИОНЕ» И ВСЁ, ЧТО РЕШАЕТ, БЫТЬ ЕЙ ИЛИ НЕТ.
--
-- История короткая и поучительная. Сначала здесь была написана передача списка
-- в Auctionator, а под списком покупок стоял текст «Открой аукцион и нажми
-- „Искать на аукционе“». Кнопки при этом не было: ни одна строка интерфейса
-- передачу не вызывала. Текст обещал игроку нажать то, чего не существует.
-- Обещание убрали, а потом сделали саму кнопку - она в UI/TabCraft.lua.
--
-- В ИГРЕ ПЕРЕДАЧУ ПРОВЕРИТЬ НЕЛЬЗЯ. Поэтому правило одно: кнопка есть только
-- тогда, когда нажатие заведомо имеет смысл. Каждое условие проверяется до
-- вызова (Shopping:Handoff), и если хоть одного нет - кнопки нет вовсе, а под
-- списком сказано почему. «Кнопка, которая отвечает ошибкой» здесь не вариант:
-- для игрока это то же самое, что текст про кнопку, которой нет.
--
-- Аддон при этом ничего не покупает: он открывает вкладку покупок Auctionator
-- и запускает в ней поиск. Покупает игрок.

-- Подпись кнопки. Одна строка на кнопку и на все тексты, которые её называют.
Shopping.HANDOFF_LABEL = "Искать на аукционе"

-- Прошлый вызов Auctionator не удался. Пока это стоит, кнопки нет: упереться в
-- ту же ошибку второй раз игрок не должен. Живёт до перезагрузки интерфейса.
Shopping.handoffBroken = nil

-- Позиции, которые есть смысл искать на аукционе, и почему остальные не идут.
-- Возвращает список { itemID, name, qty } и счётчики пропущенного:
--   vendor  - дешевле всего у торговца: её незачем искать на аукционе
--   unnamed - у предмета нет настоящего имени (клиент его не закешировал)
--   unsafe  - в имени «;», «^» или оно целиком в кавычках: Auctionator такое
--             отвергает ошибкой, и из-за одной позиции не ушёл бы весь список
--   zero    - покупать нечего
function Shopping:AuctionItems()
    local items = {}
    local skipped = { vendor = 0, unnamed = 0, unsafe = 0, zero = 0 }
    for _, line in ipairs(self:Lines()) do
        local qty = tonumber(line.qty) or 0
        local name = line.name
        if qty <= 0 then
            skipped.zero = skipped.zero + 1
        elseif type(name) ~= "string" or name == ""
            or name == U.itemFallbackName(line.itemID) then
            skipped.unnamed = skipped.unnamed + 1
        elseif line.src == "vendor" then
            skipped.vendor = skipped.vendor + 1
        elseif not Api:AuctionatorNameOk(name) then
            skipped.unsafe = skipped.unsafe + 1
        else
            items[#items + 1] = { itemID = line.itemID, name = name, qty = qty }
        end
    end
    return items, skipped
end

-- В КАКОМ СОСТОЯНИИ ПЕРЕДАЧА. Возвращает таблицу:
--   state - "ready"   всё на месте: кнопка есть
--           "none"    Auctionator не загружен
--           "partial" Auctionator есть, но поиска списком или вкладки покупок
--                     в нём нет
--           "broken"  прошлый вызов не удался
--           "closed"  аукцион не открыт
--           "nothing" в списке нечего искать на аукционе
--   note  - что сказать под списком (всегда есть)
--   items, skipped, route - что уйдёт в поиск и каким путём
--
-- Порядок проверок - от «этого не будет вовсе» к «этого нет прямо сейчас»:
-- игроку без Auctionator незачем читать «откройте аукцион».
function Shopping:Handoff()
    local items, skipped = self:AuctionItems()
    local info = { state = "none", items = items, skipped = skipped }

    if not Api:AuctionatorPresent() then
        info.note = "Auctionator не загружен — список остаётся здесь."
        return info
    end

    local route = Api:AuctionatorSearchRoute()
    info.route = route
    if not route then
        info.state = "partial"
        info.note = "Auctionator загружен, но поиска списком в этой его версии"
            .. " нет — ищите эти позиции на аукционе по названиям."
        return info
    end

    if Shopping.handoffBroken then
        info.state = "broken"
        info.note = "Auctionator не принял этот список, так что передавать его"
            .. " я перестал — ищите позиции по названиям. Что именно он ответил,"
            .. " записано в /fp diag. Попробую снова после перезагрузки интерфейса."
        return info
    end

    if not Api:AuctionHouseOpen() then
        -- ИГРА ГОВОРИТ «АУКЦИОН ОТКРЫТ», А ОКНА НЕТ. Открыт ли аукцион, аддон
        -- знает из двух мест: по событиям игры и по самому окну. Auctionator
        -- ищет только в двух окнах - нового и старого образца. Если событие
        -- пришло, а ни одного из них на экране нет, значит, на этом клиенте
        -- аукцион устроен иначе, и кнопка не появится никогда. Обещать её
        -- («когда откроете аукцион…») в таком случае - снова текст про кнопку,
        -- которой нет. Проверить это без игры нельзя, поэтому оба ответа
        -- написаны заранее.
        if ns.AuctionMoment and ns.AuctionMoment.atAuction then
            info.state = "partial"
            info.note = "Похоже, аукцион открыт, но окна, в котором Auctionator умеет"
                .. " искать, я не вижу — передать список некуда. Ищите позиции"
                .. " по названиям."
            return info
        end
        info.state = "closed"
        info.note = "Когда откроете аукцион, здесь появится кнопка: она передаст"
            .. " этот список в поиск Auctionator."
        return info
    end

    if not Api:AuctionatorShoppingTab() then
        info.state = "partial"
        info.note = "Аукцион открыт, но вкладки покупок Auctionator в нём нет —"
            .. " передать список некуда. Ищите позиции по названиям."
        return info
    end

    if #items == 0 then
        info.state = "nothing"
        if (skipped.vendor or 0) > 0 then
            -- СКОЛЬКО ЭТО ЭКОНОМИТ - ЧИСЛОМ, А НЕ ТОЛЬКО СЛОВОМ «ДЕШЕВЛЕ».
            local save = self:VendorSaving()
            info.note = "Искать на аукционе нечего: всё из этого списка дешевле"
                .. " купить у торговца"
                .. ((save and save.saving > 0)
                    and (" — на аукционе это обошлось бы на "
                         .. U.money(save.saving) .. " дороже.")
                    or ".")
        else
            info.note = "Искать на аукционе нечего: в списке нет позиций,"
                .. " которые можно назвать поиску по имени."
        end
        return info
    end

    info.state = "ready"
    local note = "Передам в поиск Auctionator " .. #items .. " "
        .. U.plural(#items, "позицию", "позиции", "позиций")
        .. ". Покупаете вы сами — я только открываю поиск."
    if (skipped.vendor or 0) > 0 then
        local save = self:VendorSaving()
        note = note .. " То, что дешевле у торговца (" .. skipped.vendor
            .. "), в поиск не идёт"
            .. ((save and save.saving > 0)
                and (": на аукционе это стоило бы на " .. U.money(save.saving)
                     .. " дороже.")
                or ".")
    end
    local lost = (skipped.unnamed or 0) + (skipped.unsafe or 0)
    if lost > 0 then
        note = note .. " Ещё " .. lost .. " "
            .. U.plural(lost, "позицию", "позиции", "позиций")
            .. " передать не могу: у них нет имени, годного для поиска."
    end
    info.note = note
    return info
end

-- Состояние и текст под списком - для вызывающих, которым хватает двух значений.
-- ПОИСК НА АУКЦИОНЕ ПРЯМО С СОВЕТА -----------------------------------------
--
-- Жалоба игрока (2026-11-21): на совете «Купить: Золотая жемчужина» и на
-- совете «Скрафтить: …» с нехваткой материалов нет кнопки, которая искала бы
-- это на аукционе, - надо идти во вкладку «Крафт» или набирать имя руками.
-- Путь тот же, что у кнопки под списком покупок (Api:AuctionatorSearchItems),
-- только позиции берутся у одного совета.

-- Можно ли искать прямо сейчас: Auctionator с поиском списком, аукцион открыт,
-- вкладка покупок есть, прошлая передача не ломалась, боя нет.
function Shopping:CanSearchNow()
    if Shopping.handoffBroken then return false end
    if Api:InCombat() then return false end
    if not Api:AuctionatorPresent() then return false end
    if not Api:AuctionatorSearchRoute() then return false end
    if not Api:AuctionHouseOpen() then return false end
    if not Api:AuctionatorShoppingTab() then return false end
    return true
end

-- Что у этого совета есть смысл искать на аукционе: сам предмет (совет
-- «Купить») или материалы, которых не хватает (совет с планом крафта).
-- Позиции, которые дешевле у торговца, без настоящего имени или с именем,
-- которое Auctionator отвергает, в поиск не идут - как и под списком покупок.
function Shopping:CardAuctionItems(card)
    local items = {}
    if type(card) ~= "table" then return items end
    local function take(itemID, name, qty, src, buyable)
        qty = tonumber(qty) or 0
        if qty <= 0 or buyable == false or src == "vendor" then return end
        if type(name) ~= "string" or name == "" then return end
        if name == U.itemFallbackName(itemID) then return end
        if not Api:AuctionatorNameOk(name) then return end
        items[#items + 1] = { itemID = itemID, name = name, qty = qty }
    end
    local act = card.action
    if act and act.kind == "shop" and act.itemID then
        local price = card.matPrice or {}
        take(act.itemID, card.buyName or ns.ActionEngine.nameOf(act.itemID),
            act.qty or card.buyQty, price.src, nil)
    elseif card.plan and type(card.plan.shopping) == "table" then
        for _, line in ipairs(card.plan.shopping) do
            take(line.itemID, ns.ActionEngine.nameOf(line.itemID), line.qty,
                line.src, line.buyable)
        end
    end
    return items
end

-- Нажатие кнопки на совете. Возвращает ok и одну строку для игрока.
function Shopping:SearchCard(card)
    if not self:CanSearchNow() then
        return false, "искать на аукционе сейчас нечем: аукцион закрыт или"
            .. " Auctionator поиск не принимает"
    end
    local items = self:CardAuctionItems(card)
    if #items == 0 then return false, "искать на аукционе по этому совету нечего" end
    local ok, route, detail = Api:AuctionatorSearchItems(items)
    if ok then
        return true, "передал в поиск Auctionator: " .. #items .. " "
            .. U.plural(#items, "позиция", "позиции", "позиций")
            .. ". Покупаете вы сами."
    end
    Shopping.handoffBroken = { reason = route, error = detail }
    if ns.Diag then
        ns.Diag:Log("Auctionator не принял поиск с совета", {
            reason = route, error = detail, items = #items,
        })
    end
    return false, "Auctionator не принял поиск — ищите на аукционе по названиям."
        .. " Подробности записал в /fp diag."
end

function Shopping:HandoffState()
    local info = self:Handoff()
    return info.state, info.note, info
end

-- ПЕРЕДАТЬ СПИСОК В ПОИСК. Возвращает ok и то, что сказать игроку.
--
-- Состояние проверяется ЗАНОВО, а не берётся с момента отрисовки: между
-- отрисовкой кнопки и нажатием аукцион могли закрыть. Такое нажатие - не отказ
-- Auctionator и не поломка: аддон говорит, что произошло, и ничего не зовёт.
function Shopping:SendToAuctionator()
    if Api:InCombat() then
        return false, "в бою список в Auctionator не передаю"
    end
    local info = self:Handoff()
    if info.state ~= "ready" then
        local why = {
            none = "Auctionator не загружен — передавать список некуда",
            partial = "в Auctionator нет поиска списком — передать не могу",
            broken = "Auctionator в прошлый раз не принял список —"
                .. " больше не передаю до перезагрузки интерфейса",
            closed = "аукцион уже закрыт — список передам, когда откроете его снова",
            nothing = "искать на аукционе нечего",
        }
        return false, why[info.state] or "передать список сейчас нельзя"
    end

    local ok, route, detail = Api:AuctionatorSearchItems(info.items)
    if ok then
        return true, "передал в поиск Auctionator: " .. #info.items .. " "
            .. U.plural(#info.items, "позиция", "позиции", "позиций")
            .. ". Покупаете вы сами."
    end

    -- Auctionator ответил ошибкой. Игроку - словами и без чужого английского
    -- текста; дословный ответ - в диагностику, где его прочтёт тот, кто чинит.
    Shopping.handoffBroken = { reason = route, error = detail }
    if ns.Diag then
        ns.Diag:Log("Auctionator не принял список покупок", {
            reason = route, error = detail, items = #info.items, route = info.route,
        })
    end
    return false, "Auctionator не принял список — ищите позиции на аукционе по"
        .. " названиям. Подробности записал в /fp diag."
end

-- Manual list ----------------------------------------------------------
-- Things the player pinned by hand, kept across sessions.

function Shopping:Pin(itemID, qty)
    ns.Config:SetShopping(itemID, qty)
end

function Shopping:Unpin(itemID)
    ns.Config:SetShopping(itemID, 0)
end

-- ОЧИСТИТЬ СВОЙ СПИСОК: ДВА НАЖАТИЯ, А НЕ ОДНО.
--
-- Этот список игрок собирает руками, и вернуть стёртое нечем. Кнопка в
-- настройках стирала его с одного нажатия - без вопроса и без слова в ответ.
-- Это тот же класс, что скрытие совета одним щелчком (Logic/Dismissal.lua), и
-- лечится так же: первое нажатие спрашивает, второе в отведённое время делает.
-- Решение живёт здесь, а не в обработчике кнопки, чтобы его можно было
-- проверить без интерфейса (Tests/test_confirm.lua).
Shopping.CLEAR_CONFIRM_SECONDS = 5
Shopping.clearArmedAt = nil

function Shopping:ClearArmed()
    local at = Shopping.clearArmedAt
    if not at then return false end
    return (Api:Now() - at) <= Shopping.CLEAR_CONFIRM_SECONDS
end

function Shopping:DisarmClear()
    local had = Shopping.clearArmedAt ~= nil
    Shopping.clearArmedAt = nil
    return had
end

-- Возвращает outcome, message:
--   "empty"   - стирать нечего; вопрос не задаётся
--   "armed"   - первое нажатие: задан вопрос, ничего не стёрто
--   "cleared" - второе нажатие в срок: список стёрт
function Shopping:RequestClear()
    local n = ns.Config:ShoppingCount()
    if n == 0 then
        self:DisarmClear()
        return "empty", "в вашем списке покупок ничего нет — очищать нечего"
    end
    local what = n .. " " .. U.plural(n, "позиция", "позиции", "позиций")
    if not self:ClearArmed() then
        Shopping.clearArmedAt = Api:Now()
        return "armed",
            "|cffffcc40очистить ваш список покупок (" .. what .. ")?|r"
            .. " Вернуть его потом будет нельзя. Нажмите ту же кнопку ещё раз —"
            .. " очищу; на это есть "
            .. (U.durationText(Shopping.CLEAR_CONFIRM_SECONDS) or "несколько секунд")
            .. ". Не нажмёте — оставлю как есть."
    end
    self:DisarmClear()
    local removed = ns.Config:ClearShopping()
    return "cleared", "очистил ваш список покупок: " .. removed .. " "
        .. U.plural(removed, "позиция", "позиции", "позиций")
end

-- A pinned item is a FLOOR, not an extra order: "make sure I buy at least this
-- many". Adding it on top of what the plans already asked for doubled the
-- number the moment the player clicked "в список покупок" on a card.
function Shopping:LoadPinned()
    for itemID, qty in pairs(ns.Config:Shopping()) do
        itemID = tonumber(itemID)
        qty = tonumber(qty) or 0
        if itemID and qty > 0 then
            local entry = self.items[itemID]
            if not entry then
                self:Add(itemID, qty, "pinned", "закреплено вручную")
                entry = self.items[itemID]
                -- Added as gross; the pin itself is the floor, and the stock
                -- still counts against it the same way.
                if entry then entry.gross = qty end
            else
                entry.forCards["pinned"] = "закреплено вручную"
            end
            if entry then entry.pinned = math.max(entry.pinned or 0, qty) end
        end
    end
end

return Shopping
