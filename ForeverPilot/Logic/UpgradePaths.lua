-- ForeverPilot / Logic/UpgradePaths.lua
--
-- РАЗВИЛКА, А НЕ ОДИН ВАРИАНТ.
--
-- До сих пор на слот выдавался один совет - «скрафтить вот это», - и выбор за
-- игрока делал аддон. Но у одного слота путей всегда несколько, и они стоят
-- разного не только в золоте:
--
--   скрафтить         - дешевле по деньгам, если материалы свои; дорого по
--                       времени, если их надо купить;
--   купить готовое    - дороже, но сразу, и без материалов;
--   квестовая награда - бесплатно, но надо пройти задание, и оно может быть
--                       недоступно по уровню;
--   у торговца        - фиксированная цена, никакого рынка, но ассортимент
--                       редко бывает лучшим.
--
-- Решать, что из этого правильно, - дело игрока: кто-то не хочет тратить
-- золото, кто-то не хочет бегать. Дело аддона - выложить варианты рядом с
-- ценой, приростом и сроком, и НЕ выбирать за него.
--
-- ЧТО ЗНАЧИТ «СРОК». Не время в минутах - его аддон знать не может, - а то, что
-- стоит между игроком и вещью: «сразу», «нужен поход к торговцу», «нужно
-- задание», «нужно купить материалы». Срок словами честнее срока в минутах.
--
-- ОТКУДА ВАРИАНТЫ: Polestar.Codex даёт источники предмета (vendor / quest /
-- craft / drop), книга рецептов - крафт, аукцион - готовое. Чего нет в данных,
-- того в развилке и нет: выдуманный путь хуже отсутствующего.
local ADDON, ns = ...

local U = ns.Util
local Api = ns.Api
local CONF = ns.CONF

local UP = {}
ns.UpgradePaths = UP

-- Виды путей, в порядке, в котором их показываем. Порядок - не рейтинг: это
-- порядок «от самого обычного к самому редкому», чтобы глаз привык.
UP.KIND = {
    CRAFT  = "craft",
    BUY    = "buy",
    QUEST  = "quest",
    VENDOR = "vendor",
    OWNED  = "owned",
}

UP.KIND_LABEL = {
    craft  = "скрафтить",
    buy    = "купить на аукционе",
    quest  = "награда за задание",
    vendor = "купить у торговца",
    owned  = "надеть своё",
}

-- Срок словами. Единственное честное измерение, которое у нас есть.
UP.WHEN = {
    NOW       = "сразу",
    SHOPPING  = "после покупки материалов",
    TRIP      = "после похода к торговцу",
    QUEST     = "после задания",
    UNKNOWN   = "срок неизвестен",
}

-- Пути для одного предмета -----------------------------------------------

-- Возвращает список путей к предмету `itemID`: { kind, label, cost, costConf,
-- when, detail, place, recipeID, questID, blocked, blockReason }
function UP:PathsTo(itemID, snap)
    itemID = tonumber(itemID)
    if not itemID then return {} end
    local out = {}

    -- 1. УЖЕ ЕСТЬ. Самый дешёвый путь из всех, и его легко не заметить.
    if snap then
        local where
        if (snap.bags or {})[itemID] then where = "в сумке"
        elseif (snap.bank or {})[itemID] then where = "в банке" end
        if where then
            out[#out + 1] = {
                kind = UP.KIND.OWNED, label = UP.KIND_LABEL.owned,
                cost = 0, costConf = CONF.EXACT,
                when = UP.WHEN.NOW,
                detail = "предмет уже " .. where .. " — надеть и всё",
            }
        end
    end

    -- 2. СКРАФТИТЬ. Цену и готовность считает планировщик - тот же, что у
    -- остальных советов, иначе числа в развилке и в карточке разъедутся.
    for _, recipe in ipairs(ns.RecipeBook and ns.RecipeBook:RecipesFor(itemID) or {}) do
        local plan = ns.CraftingPlanner and ns.CraftingPlanner:Plan(recipe, 1) or nil
        local cost = plan and plan.cost or nil
        local ready = plan and plan.ready
        out[#out + 1] = {
            kind = UP.KIND.CRAFT, label = UP.KIND_LABEL.craft,
            cost = cost, costConf = plan and plan.conf or CONF.UNKNOWN,
            when = ready and UP.WHEN.NOW or UP.WHEN.SHOPPING,
            detail = ready
                and "материалы уже в сумках"
                or (plan and ns.CraftingPlanner:MissingText(plan, function(id)
                        local i = Api:ItemInfo(id)
                        return (i and i.name) or U.itemFallbackName(id)
                    end) or "состав рецепта неизвестен"),
            recipeID = recipe.id,
            plan = plan,
        }
    end

    -- 3. КУПИТЬ ГОТОВОЕ на аукционе. Только если там действительно есть цена:
    -- «купи на аукционе» без цены - это не вариант, а пожелание.
    local market, mConf, mSrc, mAge = ns.PriceProvider:Buy(itemID)
    if market and ns.PriceProvider.PROVEN_SOURCES[mSrc] then
        out[#out + 1] = {
            kind = UP.KIND.BUY, label = UP.KIND_LABEL.buy,
            cost = market, costConf = mConf,
            when = UP.WHEN.NOW,
            detail = "цена: " .. ns.PriceProvider:Label(market, mConf, mSrc, mAge),
            priceAge = mAge,
        }
    end

    -- 4. КВЕСТОВАЯ НАГРАДА и 5. ТОРГОВЕЦ - из Codex, если он есть.
    for _, src in ipairs(Api.CodexItemSources and Api:CodexItemSources(itemID) or {}) do
        if src.type == "quest" then
            out[#out + 1] = {
                kind = UP.KIND.QUEST, label = UP.KIND_LABEL.quest,
                cost = 0, costConf = CONF.EXACT,
                when = UP.WHEN.QUEST,
                detail = src.choice
                    and "задание даёт на выбор — этот предмет один из вариантов"
                    or "выдаётся за задание",
                questID = src.quest,
                -- Задание само может быть недоступно; проверить это аддон не
                -- может, и честнее сказать, чем промолчать.
                caveat = "доступно ли вам это задание, я не знаю",
            }
        elseif src.type == "vendor" then
            local cost = tonumber(src.cost)
            local place
            if src.npc then
                local mapID, x, y, name = Api:CodexNpcSpawn(src.npc)
                if mapID then
                    place = { npcID = src.npc, name = name, mapID = mapID,
                              x = x, y = y, zone = Api:MapName(mapID),
                              routable = true, conf = CONF.ESTIMATE }
                end
            end
            out[#out + 1] = {
                kind = UP.KIND.VENDOR, label = UP.KIND_LABEL.vendor,
                -- Цены нет - значит она не в золоте или неизвестна. НЕ НОЛЬ.
                cost = (cost and cost > 0) and cost or nil,
                costConf = (cost and cost > 0) and CONF.ESTIMATE or CONF.UNKNOWN,
                when = UP.WHEN.TRIP,
                detail = (cost and cost > 0)
                    and ("у торговца " .. U.money(cost))
                    or "у торговца, но цена в данных не указана — скорее всего"
                       .. " это не золото, а особая валюта",
                place = place,
                npcID = src.npc,
            }
        end
    end

    return out
end

-- Развилка для слота ------------------------------------------------------

-- Собирает варианты по слоту: для каждого кандидата на слот - его пути, и
-- прирост относительно того, что у игрока уже есть на этот слот.
--
-- Возвращает { slot, slotLabel, baseline, options = { { itemID, name, gain,
-- paths, best } }, conf } или nil.
function UP:ForSlot(slotKey, snap, candidates)
    if not (slotKey and snap) then return nil end
    local weights = snap.weights
    local Gear = ns.GearAdvisor
    if not Gear then return nil end

    local base = Gear:SlotBaseline(slotKey, snap, weights)
    local baseScore = base and base.score or nil

    local options = {}
    for _, cand in ipairs(candidates or {}) do
        local itemID = cand.itemID or (cand.info and cand.info.itemID)
        if itemID then
            local score = Gear:ItemScore(itemID, weights)
            local gain = (score and baseScore) and (score - baseScore) or nil
            local paths = UP:PathsTo(itemID, snap)
            if #paths > 0 then
                local info = Api:ItemInfo(itemID)
                options[#options + 1] = {
                    itemID = itemID,
                    name = (info and info.name) or U.itemFallbackName(itemID),
                    score = score, gain = gain,
                    paths = paths,
                    cheapest = UP:Cheapest(paths),
                    fastest = UP:Fastest(paths),
                }
            end
        end
    end
    if #options == 0 then return nil end

    table.sort(options, function(a, b)
        local ag, bg = a.gain or -math.huge, b.gain or -math.huge
        if ag ~= bg then return ag > bg end
        return a.itemID < b.itemID
    end)

    return {
        slot = slotKey,
        slotLabel = ns.SlotMap:Label(slotKey),
        baseline = base,
        baselineScore = baseScore,
        options = options,
        conf = CONF.ESTIMATE,
    }
end

-- Самый дешёвый путь с известной ценой. Путь без цены самым дешёвым не
-- считается: «неизвестно» - это не ноль, и это главная ловушка всей развилки.
function UP:Cheapest(paths)
    local best
    for _, p in ipairs(paths) do
        if p.cost ~= nil then
            if (not best) or p.cost < best.cost then best = p end
        end
    end
    return best
end

-- Самый быстрый. Порядок сроков задан явно, а не выводится из текста.
UP.WHEN_RANK = {
    [UP.WHEN.NOW] = 1,
    [UP.WHEN.TRIP] = 2,
    [UP.WHEN.SHOPPING] = 3,
    [UP.WHEN.QUEST] = 4,
    [UP.WHEN.UNKNOWN] = 5,
}

function UP:Fastest(paths)
    local best
    for _, p in ipairs(paths) do
        local r = UP.WHEN_RANK[p.when] or 9
        if (not best) or r < (UP.WHEN_RANK[best.when] or 9) then best = p end
    end
    return best
end

-- Текст -------------------------------------------------------------------

-- Одна строка на путь: что сделать, сколько стоит, когда будет.
function UP:PathLine(path)
    local bits = { U.capitalize(path.label) }
    if path.cost == 0 then
        bits[#bits + 1] = "бесплатно"
    elseif path.cost then
        bits[#bits + 1] = U.money(path.cost)
    else
        bits[#bits + 1] = U.void(ns.VOID.NO_PRICE)
    end
    bits[#bits + 1] = path.when
    local line = table.concat(bits, " · ")
    if path.detail then line = line .. " (" .. path.detail .. ")" end
    if path.caveat then line = line .. "; " .. path.caveat end
    return line
end

-- ВЫБОР ОСТАЁТСЯ ЗА ИГРОКОМ. Аддон говорит, какой путь дешевле и какой
-- быстрее, и не делает вид, что знает, что из этого важнее.
function UP:ChoiceText(option)
    local cheap, fast = option.cheapest, option.fastest
    if not cheap and not fast then return nil end
    if cheap and fast and cheap.kind == fast.kind then
        -- Путь назван по имени: «этот путь» под списком из двух путей не
        -- говорит, какой из них имеется в виду.
        return U.capitalize(tostring(cheap.label))
            .. " — и дешевле, и быстрее остальных путей."
    end
    local bits = {}
    if cheap then
        bits[#bits + 1] = "дешевле всего — " .. cheap.label
            .. ((cheap.cost == 0) and " (бесплатно)"
                or (cheap.cost and (" (" .. U.money(cheap.cost) .. ")") or ""))
    end
    if fast then
        bits[#bits + 1] = "быстрее всего — " .. fast.label .. " (" .. fast.when .. ")"
    end
    return U.capitalize(table.concat(bits, ", "))
        .. ". Что из этого важнее, решать вам: я не знаю, чего вам сейчас"
        .. " жальче — золота или времени."
end

return UP
