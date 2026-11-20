-- ForeverPilot / Logic/CraftingPlanner.lua
--
-- "What do I actually need to make this?"
--
-- The planner runs in two phases, and the split is what makes the hard cases
-- come out right.
--
-- Phase A - costing. For every item it asks, pool-free: what is one of these
--   worth, if I had to get it right now? Either the market price, or the cost of
--   the materials of a recipe I know that makes it, whichever is cheaper. This
--   is where the "craft the intermediate or buy it" decision is made, and where
--   cyclic recipes are detected and broken.
--
-- Phase B - allocation. Walks the recipe tree spending a single shared pool of
--   materials. Because the pool is one table that every branch consumes from,
--   an ingredient needed by three different sub-recipes is counted once and
--   runs out once. Leftovers from rounding (a craft that makes 2 when 1 was
--   wanted) go back into the pool so the next branch can use them.
--
-- Nothing here calls the game API directly: materials come from the snapshot,
-- prices from PriceProvider, recipes from RecipeBook. That is what makes it
-- testable outside the game.
local ADDON, ns = ...

local U = ns.Util
local CONF = ns.CONF

local Planner = {}
ns.CraftingPlanner = Planner

local MAX_DEPTH = ns.PLANNER_MAX_DEPTH
local MAX_NODES = ns.PLANNER_MAX_NODES

-- Injected so the tests can drive the planner with fakes.
function Planner:Bind(recipeBook, priceProvider)
    self.book = recipeBook or ns.RecipeBook
    self.price = priceProvider or ns.PriceProvider
    return self
end

function Planner:Book() return self.book or ns.RecipeBook end
function Planner:Price() return self.price or ns.PriceProvider end

-- Phase A: costing ------------------------------------------------------

function Planner:BeginPass()
    self.unitCostMemo = {}
    self.cyclesSeen = {}
    self.nodes = 0
    -- Both of these used to survive the pass. `truncated` leaking meant that
    -- after one oversized tree every later plan claimed to be cut short.
    self.truncated = false
    self.cycleCount = 0
end

-- The cheapest learned recipe that produces `itemID`, by material cost.
-- Returns recipe, unitCost, conf.
local function cheapestRecipeFor(self, itemID, depth, visiting)
    local candidates = self:Book():RecipesFor(itemID)
    local bestRecipe, bestUnit, bestConf = nil, nil, CONF.UNKNOWN
    for _, recipe in ipairs(candidates) do
        local matCost, matConf = self:RecipeMaterialCost(recipe, depth + 1, visiting)
        if matCost then
            local unit = matCost / math.max(1, recipe.outputQty or 1)
            if (not bestUnit) or unit < bestUnit then
                bestRecipe, bestUnit, bestConf = recipe, unit, matConf
            end
        end
    end
    return bestRecipe, bestUnit, bestConf
end

-- What one `itemID` costs, and how we would get it.
-- Returns copper (or nil), confidence, method ("buy" | "craft"), recipe.
function Planner:UnitCost(itemID, depth, visiting)
    if not itemID then return nil, CONF.UNKNOWN, nil, nil end
    depth = depth or 0
    visiting = visiting or {}

    local memo = self.unitCostMemo and self.unitCostMemo[itemID]
    if memo then return memo.copper, memo.conf, memo.method, memo.recipe end

    -- A recipe that needs its own output, directly or through a chain, cannot
    -- be the way we get it. Record the cycle and fall back to buying.
    --
    -- `cycleCount` is bumped here and checked by every caller below: a cost
    -- worked out while an ancestor was temporarily forbidden is only valid in
    -- that one context, and memoising it made the answer depend on which item
    -- happened to be asked about first.
    if visiting[itemID] then
        self.cyclesSeen[itemID] = true
        self.cycleCount = (self.cycleCount or 0) + 1
        local buy, buyConf = self:Price():Buy(itemID)
        return buy, buyConf or CONF.UNKNOWN, buy and "buy" or nil, nil
    end

    if depth >= MAX_DEPTH then
        self.cycleCount = (self.cycleCount or 0) + 1  -- same reasoning: context-bound
        local buy, buyConf = self:Price():Buy(itemID)
        return buy, buyConf or CONF.UNKNOWN, buy and "buy" or nil, nil
    end

    self.nodes = (self.nodes or 0) + 1
    if self.nodes > MAX_NODES then
        self.truncated = true
        self.cycleCount = (self.cycleCount or 0) + 1
        local buy, buyConf = self:Price():Buy(itemID)
        return buy, buyConf or CONF.UNKNOWN, buy and "buy" or nil, nil
    end

    local buyCost, buyConf = self:Price():Buy(itemID)

    local cyclesBefore = self.cycleCount or 0
    visiting[itemID] = true
    local recipe, craftUnit, craftConf = cheapestRecipeFor(self, itemID, depth, visiting)
    visiting[itemID] = nil
    local contextBound = (self.cycleCount or 0) ~= cyclesBefore

    local copper, conf, method, chosen
    if craftUnit and buyCost then
        if craftUnit <= buyCost then
            copper, conf, method, chosen = craftUnit, craftConf, "craft", recipe
        else
            copper, conf, method, chosen = buyCost, buyConf, "buy", nil
        end
    elseif craftUnit then
        copper, conf, method, chosen = craftUnit, craftConf, "craft", recipe
    elseif buyCost then
        copper, conf, method, chosen = buyCost, buyConf, "buy", nil
    else
        copper, conf, method, chosen = nil, CONF.UNKNOWN, nil, nil
    end

    -- Only a context-free answer is worth keeping.
    if self.unitCostMemo and not contextBound then
        self.unitCostMemo[itemID] = { copper = copper, conf = conf, method = method, recipe = chosen }
    end
    return copper, conf, method, chosen
end

-- Total material cost of one run of `recipe`, at market/craft prices.
-- Returns copper (or nil when any reagent's price is unknown), confidence.
function Planner:RecipeMaterialCost(recipe, depth, visiting)
    if type(recipe) ~= "table" then return nil, CONF.UNKNOWN end
    local reagents = self:Book():MergedReagents(recipe)
    if #reagents == 0 then return nil, CONF.UNKNOWN end

    local total, conf, anyUnknown = 0, CONF.EXACT, false
    for _, r in ipairs(reagents) do
        local unit, uConf = self:UnitCost(r.itemID, (depth or 0), visiting)
        if unit then
            total = total + unit * r.qty
            conf = U.worstConf(conf, uConf)
        else
            anyUnknown = true
            conf = CONF.UNKNOWN
        end
    end
    if anyUnknown then return nil, CONF.UNKNOWN end
    -- A slot that accepts several different reagents was read as "whatever the
    -- client listed first". The sum is still the best number we have, but it is
    -- not the exact cost of what the player would actually use.
    if (tonumber(recipe.reagentChoices) or 1) > 1 then
        conf = U.worstConf(conf, CONF.ESTIMATE)
    end
    return total, conf
end

-- Is this recipe on cooldown right now? The client gives us the remaining
-- seconds through C_TradeSkillUI.GetRecipeCooldown, which Api feature-detects;
-- when it is missing we simply do not know and say nothing.
function Planner:OnCooldown(recipe)
    if type(recipe) ~= "table" then return false end
    local cd = tonumber(recipe.cooldown)
    return (cd ~= nil and cd > 0) and true or false
end

function Planner:CooldownLeft(recipe)
    if type(recipe) ~= "table" then return nil end
    local cd = tonumber(recipe.cooldown)
    if cd and cd > 0 then return cd end
    return nil
end

-- Unit cost of what a recipe produces, at current prices.
function Planner:RecipeUnitCost(recipe)
    local total, conf = self:RecipeMaterialCost(recipe, 0, {})
    if not total then return nil, CONF.UNKNOWN end
    return total / math.max(1, recipe.outputQty or 1), conf
end

-- Phase B: allocation ---------------------------------------------------

local function newPlan(recipe, times)
    return {
        recipe = recipe,
        times = times,
        crafts = {},          -- ordered, dependencies first
        craftIndex = {},      -- recipeID -> index into crafts
        needRaw = {},         -- itemID -> qty still to acquire
        needRawOrder = {},
        needGross = {},       -- itemID -> qty the tree asks for, before stock
        usedHere = {},        -- itemID -> qty taken from bags
        usedBank = {},        -- itemID -> qty taken from bank/alts
        usedSurplus = {},     -- itemID -> qty taken from this plan's own overrun
        surplus = {},         -- itemID -> qty a craft here produced beyond need
        decisions = {},       -- itemID -> { method, craftCost, buyCost }
        cycles = {},
        truncated = false,
        conf = CONF.EXACT,
        depthReached = 0,
    }
end

local function addCraft(plan, recipe, times)
    local idx = plan.craftIndex[recipe.id]
    if idx then
        plan.crafts[idx].times = plan.crafts[idx].times + times
        return plan.crafts[idx]
    end
    local entry = {
        recipeID = recipe.id, recipe = recipe, times = times,
        output = recipe.output, outputQty = recipe.outputQty or 1,
    }
    plan.crafts[#plan.crafts + 1] = entry
    plan.craftIndex[recipe.id] = #plan.crafts
    return entry
end

local function addNeed(plan, itemID, qty)
    if plan.needRaw[itemID] == nil then
        plan.needRawOrder[#plan.needRawOrder + 1] = itemID
    end
    plan.needRaw[itemID] = (plan.needRaw[itemID] or 0) + qty
end

-- Pull `want` of `itemID` out of the shared pool, recursing into a sub-craft
-- when that is how we decided to get it. `path` holds the items currently being
-- expanded, which is what stops a cyclic recipe chain dead.
function Planner:Require(itemID, want, pool, plan, depth, path, bankPool)
    if want <= 0 then return end
    plan.depthReached = math.max(plan.depthReached, depth)

    -- The gross requirement: what the tree asks for before any of the player's
    -- own stock is taken off. The merged shopping list needs this, because two
    -- cards cannot each spend the same five bolts of cloth.
    U.addTo(plan.needGross, itemID, want)

    -- 1. What is already in the pool: the player's own stock first, then this
    --    plan's own leftovers, then bank and alts (which cost a trip).
    local tookHere = U.takeFrom(pool, itemID, want)
    if tookHere > 0 then
        U.addTo(plan.usedHere, itemID, tookHere)
        want = want - tookHere
    end
    if want > 0 then
        -- Surplus from an earlier over-producing craft in THIS plan. It used to
        -- go back into `pool`, where the next branch picked it up and recorded
        -- it as "already in your bags" - which it was not.
        local tookSurplus = U.takeFrom(plan.surplus, itemID, want)
        if tookSurplus > 0 then
            U.addTo(plan.usedSurplus, itemID, tookSurplus)
            want = want - tookSurplus
        end
    end
    if want > 0 and bankPool then
        local tookBank = U.takeFrom(bankPool, itemID, want)
        if tookBank > 0 then
            U.addTo(plan.usedBank, itemID, tookBank)
            want = want - tookBank
        end
    end
    if want <= 0 then return end

    -- 2. Can we, and should we, make the rest?
    local canRecurse = depth < MAX_DEPTH and not path[itemID]
    if path[itemID] then plan.cycles[itemID] = true end

    local _, _, method, recipe = self:UnitCost(itemID, depth, {})
    local buyCost = select(1, self:Price():Buy(itemID))

    if canRecurse and method == "craft" and recipe then
        local perCraft = math.max(1, recipe.outputQty or 1)
        local runs = U.ceilDiv(want, perCraft)
        addCraft(plan, recipe, runs)
        plan.decisions[itemID] = {
            method = "craft", recipeID = recipe.id, recipeName = recipe.name,
            buyCost = buyCost, craftCost = select(1, self:RecipeUnitCost(recipe)),
        }

        -- A craft that makes more than we asked for leaves a surplus; keep it in
        -- the plan's own surplus bucket so another branch can use it instead of
        -- making its own, without it being mistaken for bag stock.
        local produced = runs * perCraft
        if produced > want then U.addTo(plan.surplus, itemID, produced - want) end

        path[itemID] = true
        for _, r in ipairs(self:Book():MergedReagents(recipe)) do
            self:Require(r.itemID, r.qty * runs, pool, plan, depth + 1, path, bankPool)
        end
        path[itemID] = nil
        return
    end

    -- 3. Otherwise it has to be acquired.
    addNeed(plan, itemID, want)
    if not plan.decisions[itemID] then
        plan.decisions[itemID] = {
            method = "buy", buyCost = buyCost,
            craftCost = recipe and select(1, self:RecipeUnitCost(recipe)) or nil,
            blockedByCycle = path[itemID] and true or nil,
        }
    end
end

-- Order the craft steps so every step's crafted reagents come earlier.
-- A cycle (which the costing phase already reports) is left in build order and
-- flagged rather than silently reshuffled.
function Planner:TopoOrder(plan)
    local book = self:Book()
    local byOutput = {}
    for _, entry in ipairs(plan.crafts) do
        if entry.output then byOutput[entry.output] = entry end
    end

    local out, state = {}, {}
    local function visit(entry)
        if not entry then return end
        local s = state[entry]
        if s == "done" then return end
        if s == "open" then
            plan.orderCycle = true
            return
        end
        state[entry] = "open"
        for _, r in ipairs(book:MergedReagents(entry.recipe)) do
            visit(byOutput[r.itemID])
        end
        state[entry] = "done"
        out[#out + 1] = entry
    end
    for _, entry in ipairs(plan.crafts) do visit(entry) end

    -- Nothing may be lost: anything the walk somehow missed is appended.
    if #out ~= #plan.crafts then
        for _, entry in ipairs(plan.crafts) do
            if state[entry] ~= "done" then out[#out + 1] = entry end
        end
    end
    return out
end

-- The public entry point.
--   opts.useBank  - let the plan draw on bank and alt stock (default true)
--   opts.pool     - override the material pool entirely (tests use this)
--   opts.bankPool - override the bank pool
function Planner:Plan(recipe, times, opts)
    opts = opts or {}
    times = math.max(1, math.floor(tonumber(times) or 1))
    if type(recipe) == "number" then recipe = self:Book():Get(recipe) end
    if type(recipe) ~= "table" then return nil end

    if not self.unitCostMemo then self:BeginPass() end

    local snap = ns.CharacterScanner and ns.CharacterScanner:Get() or nil
    local pool = opts.pool and U.copy(opts.pool)
        or (snap and U.copy(snap.bags or {}) or {})

    local bankPool
    local useBank = opts.useBank
    if useBank == nil then useBank = true end
    if opts.bankPool then
        bankPool = U.copy(opts.bankPool)
    elseif useBank and snap then
        bankPool = {}
        for itemID, e in pairs(snap.owned or {}) do
            local n = (e.bank or 0) + (e.alts or 0)
            if n > 0 then bankPool[itemID] = n end
        end
    end

    local plan = newPlan(recipe, times)
    addCraft(plan, recipe, times)

    local path = { [recipe.output or -1] = true }
    for _, r in ipairs(self:Book():MergedReagents(recipe)) do
        self:Require(r.itemID, r.qty * times, pool, plan, 1, path, bankPool)
    end

    -- Dependencies must be crafted before the thing that needs them. Reversing
    -- the build order is not enough: when an intermediate is reached through two
    -- branches it keeps its first position, and the reversal then puts it after
    -- a step that consumes it. A proper post-order walk is what makes the listed
    -- sequence something the player can actually carry out top to bottom.
    plan.crafts = self:TopoOrder(plan)
    plan.craftIndex = nil

    self:Finalize(plan)
    return plan
end

-- Cost of the shopping list, readiness, and the overall confidence.
function Planner:Finalize(plan)
    local total, conf, unknown = 0, CONF.EXACT, {}
    local items = {}
    for _, itemID in ipairs(plan.needRawOrder) do
        local qty = plan.needRaw[itemID]
        if qty and qty > 0 then
            local unit, uConf, src, age = self:Price():Buy(itemID)
            local buyable = self:Price():Buyable(itemID)
            local line = {
                itemID = itemID, qty = qty, unit = unit, conf = uConf,
                src = src, age = age, buyable = buyable,
                subtotal = unit and unit * qty or nil,
            }
            items[#items + 1] = line
            if unit then
                total = total + unit * qty
                conf = U.worstConf(conf, uConf)
            else
                unknown[#unknown + 1] = itemID
                conf = CONF.UNKNOWN
            end
        end
    end
    table.sort(items, function(a, b)
        local sa, sb = a.subtotal or -1, b.subtotal or -1
        if sa ~= sb then return sa > sb end
        return a.itemID < b.itemID
    end)

    plan.shopping = items
    plan.missingCount = #items
    plan.cost = (#unknown == 0) and total or nil
    plan.costPartial = total
    plan.costConf = conf
    plan.unknownPrices = unknown

    -- A recipe on cooldown cannot be run now, however full the bags are.
    plan.cooldown = self:CooldownLeft(plan.recipe)
    plan.ready = (#items == 0) and not plan.cooldown

    -- Readiness as a fraction: how much of what we need is already in hand.
    -- Surplus this plan produces for itself is NOT "in hand": it still has to
    -- be crafted first.
    local needTotal, haveTotal = 0, 0
    for _, qty in pairs(plan.needRaw) do needTotal = needTotal + qty end
    for _, qty in pairs(plan.usedHere) do haveTotal = haveTotal + qty end
    for _, qty in pairs(plan.usedBank) do haveTotal = haveTotal + qty end
    plan.readiness = (needTotal + haveTotal > 0)
        and (haveTotal / (needTotal + haveTotal)) or 1
    if plan.ready then plan.readiness = 1 end
    if plan.cooldown then plan.readiness = math.min(plan.readiness, 0.5) end

    plan.needsTrip = next(plan.usedBank) ~= nil
    plan.cycleList = U.sortedKeys(plan.cycles)
    plan.hasCycle = #plan.cycleList > 0
    plan.truncated = plan.truncated or self.truncated or false

    local confs = { plan.costConf }
    if plan.recipe and plan.recipe.conf then confs[#confs + 1] = plan.recipe.conf end
    plan.conf = U.worstConf(unpack(confs))
    return plan
end

-- Convenience ------------------------------------------------------------

-- The largest number of this recipe the player can make right now with nothing
-- but what is in their bags. Used for "you can make 3 of these now" lines.
function Planner:MaxCraftableNow(recipe, pool)
    if type(recipe) == "number" then recipe = self:Book():Get(recipe) end
    if type(recipe) ~= "table" then return 0 end
    -- "Now" means now: a recipe on cooldown cannot be run however much of the
    -- material is sitting in the bags.
    if self:OnCooldown(recipe) then return 0 end
    local reagents = self:Book():MergedReagents(recipe)
    if #reagents == 0 then return 0 end
    local snap = ns.CharacterScanner and ns.CharacterScanner:Get() or nil
    pool = pool or (snap and snap.bags) or {}
    local best = math.huge
    for _, r in ipairs(reagents) do
        local have = pool[r.itemID] or 0
        best = math.min(best, math.floor(have / math.max(1, r.qty)))
    end
    if best == math.huge then return 0 end
    return math.max(0, best)
end

-- Profit of making and selling ONE UNIT, given current prices.
--
-- Returns unitMargin, confidence, unitRevenue, unitCost, craft, revenue
-- where `craft` carries the same arithmetic for one run of the recipe:
--   { margin, revenue, cost, outputQty }
-- A recipe that yields five of something has a per-craft profit five times the
-- per-item one, and the two numbers must never be shown interchangeably.
--
-- The sixth return is WHERE the revenue figure came from:
--   { src, conf, age, cut, cutApplied, market }
-- It exists because the card text used to assert "(сбор аукциона уже вычтен)"
-- over every revenue figure, including the ones that are the vendor's offer
-- with no auction involved at all. On the real character that produced the
-- pair "priceSource = vendor" next to "сбор аукциона уже вычтен" on one card,
-- which is two claims that cannot both be true.
function Planner:Margin(recipe)
    if type(recipe) == "number" then recipe = self:Book():Get(recipe) end
    if type(recipe) ~= "table" or not recipe.output then return nil, CONF.UNKNOWN end
    local cost, costConf = self:RecipeUnitCost(recipe)
    local revenue, revConf, revSrc, revAge, sellInfo = self:Price():Sell(recipe.output)
    local market = self:Price():IsMarketSource(revSrc)
    local origin = {
        src = revSrc, conf = revConf, age = revAge,
        market = market,
        -- Price:Sell takes the auction house's cut off a market price and off
        -- nothing else, so this flag is the one honest answer to "was a fee
        -- deducted from the number you are showing me".
        cutApplied = market and true or false,
        cut = market and self:Price().AH_CUT or nil,
        -- Was the figure confirmed by somebody listing or buying the item?
        observed = self:Price():IsObservedSource(revSrc),
        -- And what the item's own price history says about it.
        liveCopper = sellInfo and sellInfo.liveCopper or nil,
        historyNote = sellInfo and sellInfo.historyNote or nil,
        outlier = sellInfo and sellInfo.outlier or nil,
        verdict = sellInfo and sellInfo.verdict or nil,
    }
    -- NO PRICE, NO CARD. A missing sell price used to fall through to a nil
    -- margin, which is already the right answer; it is spelled out here because
    -- the rule matters more than the mechanism: zero data must never become a
    -- figure on a card.
    if not (cost and revenue) then
        return nil, CONF.UNKNOWN, revenue, cost, nil, origin
    end
    local qty = math.max(1, tonumber(recipe.outputQty) or 1)
    local unitMargin = revenue - cost
    local craft = {
        outputQty = qty,
        cost = cost * qty,
        revenue = revenue * qty,
        margin = unitMargin * qty,
    }
    return unitMargin, U.worstConf(costConf, revConf), revenue, cost, craft, origin
end

-- РАСХОДНИК - НЕ ШМОТКА, И ЭКОНОМИКА У НИХ РАЗНАЯ ---------------------
--
-- Алхимия и инженерное дело делают ЗЕЛЬЯ, БОМБЫ И ПАТРОНЫ, а не экипировку.
-- Такой товар продаётся постоянно и малыми партиями: двадцать зелий за день -
-- обычное дело. Мантия продаётся один раз, и второй такой же в тот же день уже
-- не продать - покупатель на неё один.
--
-- Ветка «на продажу» считала и то и другое ОДНОЙ меркой - маржой за один крафт.
-- Из-за этого зелье с маржой 3 серебра всегда проигрывало мантии с маржой 4
-- золотых, хотя зелий игрок продаст двадцать, а мантию может не продать вовсе.
-- Для алхимика и инженера это означало, что денежная ветка молча считала их
-- профессии бесперспективными.
--
-- ЧЕМ ОТЛИЧАЕМ, И ПОЧЕМУ ИМЕННО ЭТИМ. Номера классов предметов здесь не
-- вписаны: они разные в разных сборках, и «classID == 0 значит расходник» - это
-- как раз то предположение, которое мы и убираем. Вместо этого спрашиваем
-- клиент о двух его собственных свойствах предмета:
--
--   stackCount > 1 - предмет СКЛАДЫВАЕТСЯ в стопку. Зелья, бомбы, патроны,
--     еда, материалы складываются; ни одна надеваемая вещь - нет. Это и есть
--     признак товара, который существует во множестве.
--   equipLoc пустой - предмет не надевается. Сумка складывается в стопку? Нет.
--     Надеваемое с stackCount > 1 в этом клиенте не встречается, но проверка
--     стоит, потому что полагаться на отсутствие - плохая опора.
--
-- Оба значения приходят из C_Item.GetItemInfo, то есть из игры, а не из нашей
-- таблицы. Предмета нет в кеше клиента - отвечаем nil («не знаю»), а не
-- «шмотка»: выдуманная форма продажи поехала бы в ранжирование.
Planner.SALE_BATCH  = "BATCH"    -- продаётся партиями и постоянно
Planner.SALE_ONEOFF = "ONEOFF"   -- продаётся по одной штуке

-- Сколько штук расходника имеет смысл считать «партией на сейчас».
--
-- Это НЕ прогноз спроса: сколько рынок проглотит, мы не знаем и знать не можем
-- - аукцион показывает цены, а не оборот. Это ограничение сверху на то, что мы
-- вообще готовы поставить в один совет, чтобы «сделай 400 зелий» не выглядело
-- обещанием, что их купят. Одна стопка - естественная единица: столько игрок
-- выставляет одним лотом.
Planner.BATCH_MAX_STACKS = 1

function Planner:SaleShape(itemID)
    if not itemID then return nil end
    local Api = ns.Api
    local info = Api and Api.ItemInfo and Api:ItemInfo(itemID) or nil
    if not info then return nil end
    -- Клиент не сказал размер стопки - значит не знаем. Единица здесь была бы
    -- не ответом, а догадкой в пользу шмотки, и именно её подставляет
    -- Api:ItemInfo в поле stackCount - поэтому спрашиваем признак, а не число.
    if info.stackCountKnown == false then return nil end
    local stack = tonumber(info.stackCount)
    if not stack then return nil end
    local equippable = type(info.equipLoc) == "string" and info.equipLoc ~= ""
        and info.equipLoc ~= "INVTYPE_NON_EQUIP"
        and info.equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE"
    -- ВТОРОЙ ПУТЬ: ЧИСЛОВОЙ ТИП ИЗ ВНЕШНЕЙ БАЗЫ.
    --
    -- Клиент забывает предметы, которые игрок видел в банке, и тогда equipLoc
    -- пустой у НАДЕВАЕМОЙ вещи - Diag для этого держит счётчик
    -- itemInfo.noEquipLoc. Без этой проверки правило «стопка больше одной и не
    -- надевается» принимало за расходник хоть мантию, и прибыль разовой вещи
    -- умножалась на стопку. Путь тот же, которым ходит GearAdvisor, когда
    -- клиент молчит: тип предмета числом (InventoryType) через
    -- SlotMap:FromInvNumber. Своего словаря номеров здесь нет.
    if not equippable and Api and Api.ForeignItemClass and ns.SlotMap then
        local _, _, inv = Api:ForeignItemClass(itemID)
        if ns.SlotMap:FromInvNumber(inv) then equippable = true end
    end
    if stack > 1 and not equippable then return Planner.SALE_BATCH end
    return Planner.SALE_ONEOFF
end

-- Прибыль, посчитанная по форме продажи предмета.
--
-- Возвращает { shape, runs, margin, unitMargin, perCraft, outputQty, stack,
--              limitedBy } или nil, когда маржи нет вовсе.
--
--   runs       - сколько крафтов идёт в зачёт. У разовой вещи это один, и
--                никакое количество материала этого не меняет: вторую такую же
--                мантию в тот же день не продать.
--   margin     - прибыль того, что в зачёте. Для расходника это партия, которую
--                игрок МОЖЕТ СДЕЛАТЬ СЕЙЧАС из своего, но не больше одной
--                стопки: и то и другое - настоящие границы, а не оценка спроса.
--   limitedBy  - что именно ограничило партию: "materials" | "stack" | "oneoff".
--                Нужно тексту карточки: «хватает на 12» и «больше стопки за раз
--                не выставить» - разные сообщения.
--
-- Поле `perCraft` остаётся прежней прибылью за один крафт, и ни одно место не
-- имеет права показать одно вместо другого - ровно как с unitMargin и craft
-- margin в Planner:Margin выше.
function Planner:BatchProfit(recipe)
    if type(recipe) == "number" then recipe = self:Book():Get(recipe) end
    if type(recipe) ~= "table" or not recipe.output then return nil end
    local unitMargin, conf, revenue, cost, craft, origin = self:Margin(recipe)
    if not unitMargin then return nil end

    local perCraft = (craft and craft.margin) or unitMargin
    local outputQty = (craft and craft.outputQty) or 1
    local shape = self:SaleShape(recipe.output)

    -- Формы не знаем - считаем по одному крафту, и говорим об этом словом, а не
    -- молчанием. shapeKnown = false едет с ответом именно для этого: три числа
    -- (штука, крафт, стопка) слишком похожи, чтобы разница пряталась.
    if shape ~= Planner.SALE_BATCH then
        return {
            shape = shape or Planner.SALE_ONEOFF, shapeKnown = shape ~= nil,
            runs = 1, margin = perCraft, perCraft = perCraft,
            unitMargin = unitMargin, outputQty = outputQty,
            conf = conf, revenue = revenue, cost = cost, origin = origin,
            limitedBy = "oneoff",
        }
    end

    local info = ns.Api and ns.Api.ItemInfo and ns.Api:ItemInfo(recipe.output) or nil
    local stack = info and info.stackCountKnown ~= false
        and tonumber(info.stackCount) or nil
    -- РАЗМЕРА СТОПКИ НЕТ - ПАРТИИ НЕТ.
    --
    -- Здесь стояло `or 1`, и это была та самая подстановка, которую запрещает
    -- Planner:SaleShape шестьюдесятью строками выше: «Клиент не сказал размер
    -- стопки - значит не знаем. Единица здесь была бы не ответом, а догадкой».
    -- Единица делала из незнания утверждение «партия - одна штука», причём
    -- молча: карточка показывала прибыль одного крафта там, где речь о партии,
    -- и ничем это не помечала. Теперь форма продажи честно помечена
    -- неизвестной, а в зачёте один крафт - то же число, что было, но названное
    -- тем, что оно есть.
    if not stack then
        return {
            shape = Planner.SALE_BATCH, shapeKnown = false,
            runs = 1, margin = perCraft, perCraft = perCraft,
            unitMargin = unitMargin, outputQty = outputQty,
            conf = conf, revenue = revenue, cost = cost, origin = origin,
            limitedBy = "stack-unknown",
        }
    end
    local cap = math.max(1, stack * Planner.BATCH_MAX_STACKS)
    local canMake = self:MaxCraftableNow(recipe)

    -- Материала нет - партии нет, и в зачёт идёт один крафт. Это не «ноль
    -- прибыли»: рецепт по-прежнему выгоден, просто партию считать не из чего.
    local runs, limitedBy
    if canMake <= 0 then
        runs, limitedBy = 1, "materials"
    else
        local madeUnits = canMake * outputQty
        if madeUnits > cap then
            runs = math.max(1, math.floor(cap / outputQty))
            limitedBy = "stack"
        else
            runs, limitedBy = canMake, "materials"
        end
    end

    return {
        shape = Planner.SALE_BATCH, shapeKnown = true,
        runs = runs, margin = perCraft * runs, perCraft = perCraft,
        unitMargin = unitMargin, outputQty = outputQty,
        stack = stack, canMake = canMake, cap = cap,
        conf = conf, revenue = revenue, cost = cost, origin = origin,
        limitedBy = limitedBy,
    }
end

-- Expected skill-ups from one craft, from the difficulty the client reports.
function Planner:SkillChance(recipe)
    if type(recipe) ~= "table" then return 0, CONF.UNKNOWN end
    local chance = ns.DIFF_SKILL_CHANCE[recipe.diff or ""]
    if chance == nil then return 0, CONF.UNKNOWN end
    return chance, CONF.CACHED
end

-- Levelling a profession ------------------------------------------------
--
-- THE GOAL IS THE CLIENT'S max, AND ONLY THE CLIENT'S max. (This comment used
-- to say the ceiling "moves as the character plays - 84, 93, 160, 224, 225".
-- Those were the player's SKILL, misread from Mastercraft's history; see
-- Api:MastercraftSkillHistory. The rule below never depended on it.) No
-- constant is aimed at. Three honest answers, in order:
--
--   skill < max   -> the goal is max, and the distance is max - skill
--   skill == max  -> no goal: there is nothing to gain by crafting right now
--   max unknown   -> no goal, and we say so rather than substituting a number
--
-- A skill level we do not trust (the known GetProfessionInfoBySkillLineID zero)
-- is also no goal: aiming at a ceiling from a fake floor would invent a plan.
function Planner:SkillGoal(prof)
    if type(prof) ~= "table" then return nil end
    if not prof.skillTrusted then return nil end
    local skill, max = tonumber(prof.skill), tonumber(prof.max)
    if not (skill and max) then return nil end
    if max <= 0 or skill >= max then return nil end
    return max, max - skill
end

-- The cheapest route from where the skill is now to the ceiling the client
-- reports. "Cheapest" is cost per expected skill point: a recipe with a 25%
-- chance costs four crafts per point, so a cheap green can easily lose to a
-- dearer orange. Returns nil whenever SkillGoal does - no goal, no path.
function Planner:PathToGoal(prof, opts)
    opts = opts or {}
    local goal, remaining = self:SkillGoal(prof)
    if not goal then return nil end

    -- Open a costing pass if nobody has. RecipeUnitCost below walks the
    -- material tree and its cycle guard writes into self.cyclesSeen, which only
    -- BeginPass creates - and Plan, the usual caller, is the only other place
    -- that opens one. Reached from a fresh planner this used to die on any
    -- recipe whose materials loop.
    if not self.unitCostMemo then self:BeginPass() end

    local book = self:Book()
    local bucket = book and book:Bucket(prof.name)
    if not (bucket and bucket.list) then return nil end

    local best
    for _, recipe in ipairs(bucket.list) do
        if recipe.learned and not self:OnCooldown(recipe) then
            local chance = self:SkillChance(recipe)
            if chance and chance > 0 then
                local unit = self:RecipeUnitCost(recipe)
                -- Crafts needed for the whole gap at this recipe's chance. A
                -- 25% green needs four crafts per expected point, so a cheap
                -- green can easily lose to a dearer orange.
                local crafts = math.ceil(remaining / chance)
                local cost = unit and (unit * crafts) or nil
                -- Ranking key: cost per point when we have prices, otherwise
                -- the best chance. An unpriced recipe never beats a priced one.
                local key = cost and (cost / remaining) or math.huge
                if (not best)
                   or (key < best.key)
                   or (key == best.key and chance > best.chance) then
                    best = { recipe = recipe, chance = chance, crafts = crafts,
                             cost = cost, key = key, unit = unit }
                end
            end
        end
    end
    if not best then return nil end

    local plan = self:Plan(best.recipe, math.min(best.crafts, opts.maxPlanRuns or 200))
    return {
        profession  = prof.name,
        from        = tonumber(prof.skill),
        goal        = goal,
        remaining   = remaining,
        recipe      = best.recipe,
        chance      = best.chance,
        crafts      = best.crafts,
        unitCost    = best.unit,
        cost        = best.cost,
        plan        = plan,
        conf        = best.cost and CONF.ESTIMATE or CONF.UNKNOWN,
    }
end

-- A compact, human-readable "what is missing" line for a card.
-- Самая старая цена в плане: возраст и предмет. Нужна и тексту карточки, и
-- самопроверке - чтобы они говорили об одном и том же.
function Planner:OldestPrice(plan)
    local age, itemID
    for _, line in ipairs((plan and plan.shopping) or {}) do
        if line.age and (not age or line.age > age) then
            age, itemID = line.age, line.itemID
        end
    end
    return age, itemID
end

function Planner:MissingText(plan, nameOf)
    if not plan then return "нет данных" end
    if plan.cooldown and plan.missingCount == 0 then
        return "материалы есть, но рецепт на перезарядке: ещё "
            .. (U.durationText and U.durationText(plan.cooldown) or (plan.cooldown .. " с"))
    end
    if plan.ready then
        if plan.needsTrip then return "всё есть, но часть лежит в банке" end
        return "всё есть в сумках"
    end
    local parts = {}
    for i = 1, math.min(3, #plan.shopping) do
        local line = plan.shopping[i]
        local name = nameOf and nameOf(line.itemID) or U.itemFallbackName(line.itemID)
        parts[#parts + 1] = name .. " x" .. line.qty
    end
    local text = table.concat(parts, ", ")
    if #plan.shopping > 3 then
        local rest = #plan.shopping - 3
        text = text .. " и ещё " .. rest .. " " .. U.plural(rest, "позиция", "позиции", "позиций")
    end
    text = "не хватает: " .. text

    -- ВОЗРАСТ ЦЕНЫ ВИДЕН. Если самая старая цена в плане старше суток, об этом
    -- говорится прямо в строке «чего не хватает»: сумма, посчитанная по
    -- вчерашней цене, - это не та же сумма, что по сегодняшней.
    local age, itemID = Planner:OldestPrice(plan)
    if age and age > (ns.PRICE_AGE_SAY_SECONDS or 86400) then
        local name = (nameOf and nameOf(itemID)) or U.itemFallbackName(itemID)
        text = text .. ". Цена «" .. tostring(name) .. "» видена "
            .. (U.ageText(age) or "давно")
    end
    return text
end

return Planner
