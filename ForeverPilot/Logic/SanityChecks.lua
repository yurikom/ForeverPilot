-- ForeverPilot / Logic/SanityChecks.lua
--
-- Automatic "is this advice actually sane?" checks, run once per recompute over
-- the finished card list.
--
-- The point is not to catch Lua errors - xpcall does that. The point is to
-- catch advice that runs but is WRONG: a negative profit ranked at the top, a
-- level 50 robe in the "wear this" list, an agility enchant for a mage, a price
-- from last week presented as fact. Those fail silently in a way no crash log
-- would ever show, and they are exactly what the player cannot be expected to
-- notice.
--
-- Everything here reads values the engine already computed. No prices are
-- fetched, no plans are rebuilt, nothing is scanned. The whole pass is a loop
-- over at most forty cards.
local ADDON, ns = ...

local U = ns.Util
local Diag = ns.Diag

local Checks = {}
ns.SanityChecks = Checks

-- Each check gets the whole context and reports through Diag:Suspect.
-- code is stable so repeats collapse; text is what the player or I will read.
Checks.LIST = {}

local function check(code, fn)
    Checks.LIST[#Checks.LIST + 1] = { code = code, run = fn }
end

-- КОМУ АДРЕСОВАНА НАХОДКА. ПЕРЕЧЕНЬ ЗАКРЫТЫЙ.
--
-- До этого все находки ехали в один адрес - файл диагностики, - и половина из
-- них адресована не тому. «„На продажу: Небесно-голубая краска“: выручка 1з 24с
-- против цены торговца 75м - это в 166 раз больше» - это предупреждение ИГРОКУ
-- о числе, на которое он собирается потратить материалы; оно обязано стоять на
-- карточке. «У совета №3 приоритет = nan» - это дефект кода; игроку от него
-- нужно только одно: знать, что этой карточке верить нельзя.
--
-- Поэтому у каждого кода есть адрес, и он один из трёх:
--
--   "say"     - текст находки написан словами для игрока, и карточка печатает
--               его как есть. Сомнение видно в заголовке выгоды, стоит первой
--               фразой в «почему» и опускает карточку ниже исполнимых советов.
--   "defect"  - находка написана для того, кто чинит: индексы, коды, упрёки
--               самому себе. На карточке от неё одна фраза - «числам этой
--               карточки я сам не верю», - и карточка уходит вниз, к убыточным.
--   "list"    - находка не про одну карточку (пустые сумки, обрезанный список,
--               концентрация ветки на одном торговце). Прикладывать её некуда.
--
-- Перечень ЗАКРЫТЫЙ: проверка, кода которой здесь нет, роняет набор
-- (Tests/test_diag.lua). Иначе новая проверка молча вернулась бы к прежнему
-- поведению - срабатывать и никуда не доходить, - а именно это и чинится.
Checks.SCOPE = {
    -- словами для игрока
    ["useless-enchant"]              = "say",
    ["implausible-profit"]           = "say",
    ["profit-without-market"]        = "say",
    ["profit-on-outlier-price"]      = "say",
    ["revenue-far-above-vendor"]     = "say",
    ["revenue-above-vendor-ceiling"] = "say",
    ["equip-advice-without-item"]    = "say",
    ["advice-worse-than-owned"]      = "say",
    ["arbitrage-markup-impossible"]  = "say",
    -- дефект: игроку - «не верьте этой карточке», подробности в файле
    ["negative-benefit-on-top"]      = "defect",
    ["unwearable-in-gear-branch"]    = "defect",
    ["stale-price-unmarked"]         = "defect",
    ["bad-quantity"]                 = "defect",
    ["recipe-cycle"]                 = "defect",
    ["bad-cost"]                     = "defect",
    ["bad-score"]                    = "defect",
    ["overclaimed-confidence"]       = "defect",
    ["empty-card-field"]             = "defect",
    ["duplicate-key"]                = "defect",
    ["unaffordable-unmarked"]        = "defect",
    ["bad-gear-gain"]                = "defect",
    ["bad-place"]                    = "defect",
    ["contradictory-plan"]           = "defect",
    ["pointless-skill-craft"]        = "defect",
    ["revenue-source-contradiction"] = "defect",
    ["upgrade-drops-main-stat"]      = "defect",
    ["silent-stat-loss"]             = "defect",
    ["suspect-card-unmarked"]        = "defect",
    ["appearance-unchecked"]         = "defect",
    -- про список целиком, а не про одну карточку
    ["zero-skill-with-recipes"]      = "list",
    ["empty-bag-scan"]               = "list",
    ["empty-equipment-scan"]         = "list",
    ["unnamed-items"]                = "list",
    ["recipe-without-reagents"]      = "list",
    ["enchant-slot-unmapped"]        = "list",
    ["list-truncated"]               = "list",
    ["all-branches-empty"]           = "list",
    ["candidates-produced-nothing"]  = "list",
    ["item-bonuses-unreadable"]      = "list",
    ["foreign-price-disagrees"]      = "list",
    ["spell-power-double-counted"]   = "list",
    ["advice-concentrated-on-one-source"] = "list",
}

-- Адрес находки. Неизвестный код считается дефектом, а не «ничем»: карточку
-- всё равно надо опустить и пометить, даже если формулировку ещё не написали.
function Checks:Scope(code)
    return Checks.SCOPE[code] or "defect"
end

local function money(copper)
    return U.money(copper or 0)
end

-- 1. A suggestion that loses money, ranked where the player will act on it.
check("negative-benefit-on-top", function(ctx)
    for i = 1, math.min(5, #ctx.cards) do
        local card = ctx.cards[i]
        if card.benefitValue and card.benefitValue < 0
           and card.kind ~= ns.KIND.BUY then
            Diag:Suspect("negative-benefit-on-top",
                string.format("совет №%d «%s» наверху, но выгода отрицательная (%s)",
                    i, card.title or "?", money(card.benefitValue)),
                { key = card.key, kind = card.kind, value = card.benefitValue })
        end
    end
end)

-- 2. Gear in the "wear this" branch that the character cannot wear. The branch
--    is supposed to filter this; if one gets through, the filter is broken.
check("unwearable-in-gear-branch", function(ctx)
    local level = ctx.snap and ctx.snap.level or 0
    for _, card in ipairs(ctx.cards) do
        if card.kind == ns.KIND.CRAFT_GEAR and card.itemID then
            local info = ns.Api:ItemInfo(card.itemID)
            if info then
                local req = tonumber(info.reqLevel) or 0
                if level > 0 and req > level then
                    Diag:Suspect("unwearable-in-gear-branch",
                        string.format("«%s» в ветке «надеть», но нужен уровень %d при %d",
                            card.title or "?", req, level),
                        { key = card.key, itemID = card.itemID, req = req, level = level })
                end
                local ok, reason = ns.GearAdvisor:CanEquip(info, ctx.snap)
                if not ok then
                    Diag:Suspect("unwearable-in-gear-branch",
                        string.format("«%s» в ветке «надеть», но надеть нельзя: %s",
                            card.title or "?", tostring(reason)),
                        { key = card.key, itemID = card.itemID, reason = reason })
                end
            end
        end
    end
end)

-- 3. An enchant whose stat this character does not care about. Legitimate when
--    it is the only formula for the slot, so the check records whether a better
--    one existed.
check("useless-enchant", function(ctx)
    for _, card in ipairs(ctx.cards) do
        if card.kind == ns.KIND.ENCHANT and card.recipeID then
            local s = ctx.enchantBySlot and ctx.enchantBySlot[card.key]
            local usefulness = s and s.usefulness
            if usefulness ~= nil and usefulness <= 0 then
                local better = 0
                for _, alt in ipairs((s and s.altList) or {}) do
                    if (alt.usefulness or 0) > 0 then better = better + 1 end
                end
                Diag:Suspect("useless-enchant",
                    string.format("«%s» ничего не даёт этому классу%s",
                        card.title or "?",
                        better > 0 and (", а полезных формул на слот было " .. better)
                            or " (других формул на слот нет — это нормально)"),
                    { key = card.key, usefulness = usefulness, better = better,
                      class = ctx.snap and ctx.snap.classFile })
            end
        end
    end
end)

-- 4. A stale price presented without saying it is stale.
check("stale-price-unmarked", function(ctx)
    -- Тот же порог, что у текста карточки: два разных числа здесь и в
    -- PriceProvider и были причиной этого замечания в живом файле.
    local DAY = ns.PRICE_AGE_SAY_SECONDS or 86400
    for _, card in ipairs(ctx.cards) do
        local plan = card.plan
        for _, line in ipairs((plan and plan.shopping) or {}) do
            if line.age and line.age > DAY then
                local marked = (line.conf == ns.CONF.ESTIMATE)
                    or (card.why and card.why:find("назад"))
                    or (card.need and card.need:find("назад"))
                if not marked then
                    Diag:Suspect("stale-price-unmarked",
                        string.format("цена предмета %d старше суток (%s), но как устаревшая не помечена",
                            line.itemID, U.ageText(line.age) or "?"),
                        { key = card.key, itemID = line.itemID,
                          age = line.age, conf = line.conf })
                end
            end
        end
    end
end)

-- 5. A material quantity at or below zero. Means the pool arithmetic leaked.
check("bad-quantity", function(ctx)
    for _, card in ipairs(ctx.cards) do
        local plan = card.plan
        if plan then
            for itemID, qty in pairs(plan.needRaw or {}) do
                if type(qty) ~= "number" or qty <= 0 then
                    Diag:Suspect("bad-quantity",
                        string.format("в плане «%s» предмет %d нужен в количестве %s",
                            card.title or "?", itemID, tostring(qty)),
                        { key = card.key, itemID = itemID, qty = qty })
                end
            end
            for itemID, qty in pairs(plan.usedHere or {}) do
                if type(qty) ~= "number" or qty <= 0 then
                    Diag:Suspect("bad-quantity",
                        string.format("в плане «%s» из сумок взято %s предмета %d",
                            card.title or "?", tostring(qty), itemID),
                        { key = card.key, itemID = itemID, qty = qty })
                end
            end
        end
    end
end)

-- 6. A recipe that needs its own output. The planner breaks the cycle, so this
--    is informational rather than broken, but it means a chain was unusable.
check("recipe-cycle", function(ctx)
    for _, card in ipairs(ctx.cards) do
        local plan = card.plan
        if plan and plan.hasCycle then
            local names = {}
            for _, itemID in ipairs(plan.cycleList or {}) do
                names[#names + 1] = tostring(itemID)
            end
            Diag:Suspect("recipe-cycle",
                string.format("в цепочке «%s» замкнутый круг по предметам: %s",
                    card.title or "?", table.concat(names, ", ")),
                { key = card.key, items = plan.cycleList })
        end
    end
end)

-- 7. A cost that cannot be right.
check("bad-cost", function(ctx)
    for _, card in ipairs(ctx.cards) do
        if card.cost and (card.cost < 0 or card.cost ~= card.cost) then
            Diag:Suspect("bad-cost",
                string.format("у «%s» стоимость %s", card.title or "?", tostring(card.cost)),
                { key = card.key, cost = card.cost })
        end
        local plan = card.plan
        if plan and plan.cost and plan.cost < 0 then
            Diag:Suspect("bad-cost",
                string.format("у плана «%s» отрицательная закупка: %s",
                    card.title or "?", money(plan.cost)),
                { key = card.key, cost = plan.cost })
        end
    end
end)

-- 8. A score that is not a number. Would scramble the whole ranking.
check("bad-score", function(ctx)
    for i, card in ipairs(ctx.cards) do
        local score = card.score
        if type(score) ~= "number" or score ~= score
           or score == math.huge or score == -math.huge then
            Diag:Suspect("bad-score",
                string.format("у совета №%d «%s» приоритет = %s",
                    i, card.title or "?", tostring(score)),
                { key = card.key, score = score })
        end
        local r = card.plan and card.plan.readiness
        if r and (r < 0 or r > 1 or r ~= r) then
            Diag:Suspect("bad-score",
                string.format("у «%s» готовность вне диапазона: %s",
                    card.title or "?", tostring(r)),
                { key = card.key, readiness = r })
        end
    end
end)

-- 9. Claiming exact confidence on a guessed price.
check("overclaimed-confidence", function(ctx)
    for _, card in ipairs(ctx.cards) do
        local plan = card.plan
        for _, line in ipairs((plan and plan.shopping) or {}) do
            if line.src == "markup" and line.conf == ns.CONF.EXACT then
                Diag:Suspect("overclaimed-confidence",
                    string.format("цена предмета %d — грубая оценка, а помечена как точная",
                        line.itemID),
                    { key = card.key, itemID = line.itemID, src = line.src })
            end
        end
        if card.conf == ns.CONF.EXACT and card.kind == ns.KIND.CRAFT_PROFIT
           and not ns.PriceProvider:AuctionatorEnabled() then
            Diag:Suspect("overclaimed-confidence",
                string.format("«%s» заявлен как точный, хотя цен с аукциона нет",
                    card.title or "?"),
                { key = card.key })
        end
    end
end)

-- 10. An empty field on a card. The UI has exactly three lines and each must
--     say something; a blank one is a hole the player stares at.
check("empty-card-field", function(ctx)
    for i, card in ipairs(ctx.cards) do
        local missing = {}
        if not (card.title and card.title ~= "") then missing[#missing + 1] = "заголовок" end
        if not (card.why and card.why ~= "") then missing[#missing + 1] = "почему" end
        if not (card.need and card.need ~= "") then missing[#missing + 1] = "чего не хватает" end
        if not (card.benefit and card.benefit ~= "") then missing[#missing + 1] = "выгода" end
        if not card.action then missing[#missing + 1] = "действие" end
        if #missing > 0 then
            Diag:Suspect("empty-card-field",
                string.format("у совета №%d пустые поля: %s", i, table.concat(missing, ", ")),
                { key = card.key, kind = card.kind })
        end
        -- Placeholder text leaking into the UI.
        for _, field in ipairs({ "title", "why", "need", "benefit" }) do
            local text = card[field]
            if type(text) == "string" and (text:find("nil") or text:find("nan")
               or text:find("inf")) then
                Diag:Suspect("empty-card-field",
                    string.format("в поле «%s» совета «%s» просочился мусор: %s",
                        field, card.title or "?", U.truncate(text, 80)),
                    { key = card.key, field = field })
            end
        end
    end
end)

-- 11. Two cards with the same key: the second would be unhidable.
check("duplicate-key", function(ctx)
    local seen = {}
    for _, card in ipairs(ctx.cards) do
        if card.key then
            if seen[card.key] then
                Diag:Suspect("duplicate-key",
                    "две карточки с одинаковым ключом: " .. card.key,
                    { key = card.key })
            end
            seen[card.key] = true
        end
    end
end)

-- 12. Telling a poor character to spend more than they have, without saying so.
check("unaffordable-unmarked", function(ctx)
    local money_ = (ctx.snap and ctx.snap.money) or 0
    for _, card in ipairs(ctx.cards) do
        if card.cost and card.cost > money_ and money_ > 0 then
            -- ЧТО СЧИТАЕТСЯ СКАЗАННЫМ - СПРАШИВАЕМ У Logic/Risk.lua, а не
            -- решаем здесь. Пока у проверки был свой список формулировок, она
            -- расходилась с карточкой: ветка покупок писала «это в 4 раза
            -- больше, чем у вас есть» - то есть говорила игроку именно то, что
            -- нужно, - а проверка такой фразы не знала и ругалась на исправную
            -- карточку. На живых данных это давало четыре ложных срабатывания
            -- за пересчёт, и именно такие ложные срабатывания учат не читать
            -- самопроверку вообще.
            local says = ns.Risk and ns.Risk:SaysUnaffordable(card)
            if not says then
                Diag:Suspect("unaffordable-unmarked",
                    string.format("«%s» стоит %s при %s в кошельке, и в карточке об этом не сказано",
                        card.title or "?", money(card.cost), money(money_)),
                    { key = card.key, cost = card.cost, money = money_ })
            end
        end
    end
end)

-- 13. A profit figure too large to believe for this character. Almost always a
--     bad price in the cache rather than a real opportunity.
check("implausible-profit", function(ctx)
    local level = (ctx.snap and ctx.snap.level) or 1
    -- A rough ceiling: a low-level character making tens of gold per craft is
    -- far more likely to be a price glitch than a goldmine.
    local ceiling = math.max(50000, level * 20000)
    for _, card in ipairs(ctx.cards) do
        if card.kind == ns.KIND.CRAFT_PROFIT and card.benefitValue
           and card.benefitValue > ceiling then
            Diag:Suspect("implausible-profit",
                string.format("«%s» обещает %s прибыли на %d уровне — скорее битая цена, чем находка",
                    card.title or "?", money(card.benefitValue), level),
                { key = card.key, value = card.benefitValue, ceiling = ceiling })
        end
    end
end)

-- 14. The known client bug: a profession reporting skill 0 while we hold
--     recipes for it.
check("zero-skill-with-recipes", function(ctx)
    for _, prof in ipairs((ctx.snap and ctx.snap.professions) or {}) do
        local bucket = ns.RecipeBook:Bucket(prof.name)
        local count = bucket and #bucket.list or 0
        if count > 0 and (prof.skillBroken or prof.skill == nil) then
            Diag:Suspect("zero-skill-with-recipes",
                -- Имя профессии - для человека (U.profLabel): эту строку игрок
                -- читает в сводке и в ответе на /fp diag, а в раннем состоянии
                -- имя приходит из чужого кеша по-английски.
                string.format("профессия «%s»: клиент не даёт уровень навыка, хотя рецепты по ней есть (%d)",
                    tostring(U.profLabel(prof.name)), count),
                { profession = prof.name, recipes = count, route = prof.route })
        end
    end
end)

-- 15. The bag scan came back empty while the player evidently has bags.
check("empty-bag-scan", function(ctx)
    local snap = ctx.snap
    if not snap then return end
    local items = U.count(snap.bags)
    if items == 0 then
        Diag:Suspect("empty-bag-scan",
            "в сумках не найдено ни одного предмета — либо они правда пусты,"
            .. " либо чтение сумок не сработало",
            { conf = snap.bagsConf })
    end
end)

-- 16. No equipment read at all, which cannot be true above level 1.
check("empty-equipment-scan", function(ctx)
    local snap = ctx.snap
    if not snap then return end
    local slots = U.count(snap.equipped)
    if slots == 0 and (snap.level or 0) > 1 then
        Diag:Suspect("empty-equipment-scan",
            string.format("прочитано 0 слотов экипировки на %d уровне — чтение не сработало",
                snap.level or 0),
            { conf = snap.equippedConf, level = snap.level })
    end
end)

-- 17. Items the client has no name for. A few are normal right after login;
--     many at once means the item cache never warmed up and the whole list is
--     showing numbers instead of names.
check("unnamed-items", function(ctx)
    local unnamed = 0
    for _, card in ipairs(ctx.cards) do
        if card.title and card.title:find("Предмет #") then unnamed = unnamed + 1 end
    end
    if unnamed >= 3 then
        Diag:Suspect("unnamed-items",
            unnamed .. " " .. U.plural(unnamed, "совет показывает", "совета показывают",
                "советов показывают") .. " «Предмет #N» вместо названия —"
            .. " игра ещё не отдала названия этих предметов",
            { count = unnamed })
    end
end)

-- 18. A recipe with an output but no reagents: the schematic never arrived, so
--     any plan built on it is fiction.
check("recipe-without-reagents", function(ctx)
    local broken, examples = 0, {}
    for _, recipe in pairs(ns.RecipeBook.byID or {}) do
        if recipe.learned and recipe.output and #(recipe.reagents or {}) == 0 then
            broken = broken + 1
            if #examples < 3 then examples[#examples + 1] = recipe.name or recipe.id end
            -- В список заказа - по recipeID, а не одним счётчиком: добывать
            -- состав надо для конкретных рецептов.
            Diag:Want("recipesNoSchematic", recipe.id, "recipe-book", {
                name = recipe.name, output = recipe.output,
                profession = recipe.profession,
            })
        end
    end
    if broken > 0 then
        Diag:Suspect("recipe-without-reagents",
            string.format("%d выученных рецептов без реагентов (схема не пришла), например: %s",
                broken, table.concat(examples, ", ")),
            { count = broken, examples = examples })
    end
end)

-- 19. An enchant mapped to a slot this server has no formulas for, or a formula
--     we could not place at all.
check("enchant-slot-unmapped", function(ctx)
    local unmapped = ns.EnchantAdvisor:Unmapped()
    if #unmapped > 0 then
        local names = {}
        for i = 1, math.min(4, #unmapped) do
            names[#names + 1] = unmapped[i].categoryName or "?"
        end
        Diag:Suspect("enchant-slot-unmapped",
            string.format("%d категорий чар не разложены по слотам: %s",
                #unmapped, table.concat(names, ", ")),
            { count = #unmapped, categories = names })
    end
end)

-- 20. The card list was truncated, so something was dropped unseen.
check("list-truncated", function(ctx)
    if ctx.generated and ctx.generated > #ctx.cards then
        -- ЧИСЛО И СЛОВО СОГЛАСОВАНЫ. Здесь стояло «%d советов» при любом числе,
        -- и на настоящих данных строка читалась «сгенерировано 41 советов».
        -- Число приходит из движка и бывает любым, так что глазами это не
        -- проверить - проверяет правило «согласование» в Tests/sense.lua.
        Diag:Suspect("list-truncated",
            string.format("сгенерировано %d %s, показано %d — остальные обрезаны лимитом",
                ctx.generated,
                U.plural(ctx.generated, "совет", "совета", "советов"),
                #ctx.cards),
            { generated = ctx.generated, shown = #ctx.cards })
    end
end)

-- 21. A gear upgrade whose claimed gain is implausible, or non-positive.
--
-- A card with no number is legitimate in exactly one case: the worn item's
-- stats are unreadable, so there is nothing to compare against. That card has
-- to SAY it cannot compare - a blank number with an upgrade-shaped title would
-- be the dishonest version, and that is what this check looks for now.
check("bad-gear-gain", function(ctx)
    for _, card in ipairs(ctx.cards) do
        if card.kind == ns.KIND.CRAFT_GEAR then
            local gain = card.benefitValue
            if gain == nil then
                local admits = (card.benefit and card.benefit:find("не могу"))
                    or (card.why and card.why:find("не отда"))
                    or (card.why and card.why:find("не могу"))
                if not admits then
                    Diag:Suspect("bad-gear-gain",
                        string.format("«%s» в ветке «надеть» без числа прироста"
                            .. " и без объяснения почему", card.title or "?"),
                        { key = card.key })
                end
            elseif gain <= 0 then
                Diag:Suspect("bad-gear-gain",
                    string.format("«%s» предложен как улучшение, но прирост %s",
                        card.title or "?", tostring(gain)),
                    { key = card.key, gain = gain })
            end
        end
    end
end)

-- 22. Routing offered where there is nothing to route to, or a place with
--     coordinates outside the map.
check("bad-place", function(ctx)
    for _, card in ipairs(ctx.cards) do
        local place = card.place
        if place then
            if place.routable then
                local x, y = place.x, place.y
                if not (x and y) or x <= 0 or y <= 0 or x > 1 or y > 1 then
                    Diag:Suspect("bad-place",
                        string.format("у «%s» место помечено пригодным, но координаты (%s, %s)",
                            card.title or "?", tostring(x), tostring(y)),
                        { key = card.key, x = x, y = y, mapID = place.mapID })
                end
                if not place.mapID then
                    Diag:Suspect("bad-place",
                        string.format("у «%s» есть координаты, но нет карты", card.title or "?"),
                        { key = card.key })
                end
            end
        end
    end
end)

-- 23. A plan that says it is ready while still listing things to buy.
check("contradictory-plan", function(ctx)
    for _, card in ipairs(ctx.cards) do
        local plan = card.plan
        if plan then
            if plan.ready and #(plan.shopping or {}) > 0 then
                Diag:Suspect("contradictory-plan",
                    string.format("план «%s» помечен готовым, но в списке покупок %d позиций",
                        card.title or "?", #plan.shopping),
                    { key = card.key, shopping = #plan.shopping })
            end
            if plan.ready and (plan.readiness or 1) < 1 then
                Diag:Suspect("contradictory-plan",
                    string.format("план «%s» готов, но готовность %.2f",
                        card.title or "?", plan.readiness or 0),
                    { key = card.key, readiness = plan.readiness })
            end
            if not plan.ready and plan.cost == 0 then
                Diag:Suspect("contradictory-plan",
                    string.format("план «%s» не готов, но докупать нечего (0)",
                        card.title or "?"),
                    { key = card.key })
            end
        end
    end
end)

-- 24. The skill branch suggesting a craft that cannot give a skill-up.
check("pointless-skill-craft", function(ctx)
    for _, card in ipairs(ctx.cards) do
        if card.kind == ns.KIND.CRAFT_SKILL and card.recipeID then
            local recipe = ns.RecipeBook:Get(card.recipeID)
            if recipe then
                local chance = ns.CraftingPlanner:SkillChance(recipe)
                if (chance or 0) <= 0 then
                    Diag:Suspect("pointless-skill-craft",
                        string.format("«%s» предложен ради навыка, но шанс прироста %s (сложность %s)",
                            card.title or "?", tostring(chance), tostring(recipe.diff)),
                        { key = card.key, chance = chance, diff = recipe.diff })
                end
            end
        end
    end
end)

-- 25. Every branch came back empty. Not necessarily wrong, but it is the state
--     the player would describe as "it does nothing", so it must be on record.
check("all-branches-empty", function(ctx)
    local counts = ctx.counts or {}
    local total = 0
    -- "hidden" is not a branch: it counts the card that explains an empty list,
    -- so including it would have let this check fall silent in exactly the
    -- state it exists to report.
    for key, n in pairs(counts) do
        if key ~= "hidden" then total = total + (n or 0) end
    end
    -- СКРЫТОЕ ИГРОКОМ - НЕ «НИЧЕГО НЕ ВЫДАЛ». Счёт здесь идёт по экрану, и
    -- когда игрок сам спрятал все советы, проверка объявляла странностью его
    -- собственный выбор: «ни один модуль советов ничего не выдал» - при девяти
    -- построенных и восьми скрытых. Про это состояние уже говорит карточка
    -- «Скрытых советов: N»; странность - только когда и скрытых нет.
    if total == 0 and (tonumber(ctx.hidden) or 0) == 0 then
        Diag:Suspect("all-branches-empty",
            "ни одна ветка советов ничего не выдала — причины записаны в файле диагностики",
            { counts = counts, hidden = ctx.hidden or 0 })
    end
end)

-- 26. The branches produced candidates and none of them reached the player.
--     This is the hole check 25 left open, and the real character fell straight
--     into it: gear=4, enchant=0, profit=8, skill=1 - thirteen candidates, so
--     "all branches empty" never fired - while every single key sat in
--     ForeverPilotDB.dismissed and the window showed "0 советов". The counts
--     looked healthy, the list was empty, and nothing on record connected the
--     two. Setup cards are excluded on purpose: a list made only of "open your
--     profession window" is still a list with no advice in it.
check("candidates-produced-nothing", function(ctx)
    local counts = ctx.counts or {}
    local produced = 0
    for key, n in pairs(counts) do
        if key ~= "hidden" then produced = produced + (n or 0) end
    end
    if produced == 0 then return end  -- check 25 owns that case

    local actionable = 0
    for _, card in ipairs(ctx.cards) do
        if card.kind ~= ns.KIND.SETUP then actionable = actionable + 1 end
    end
    if actionable > 0 then return end

    local hidden = ctx.hidden or 0
    Diag:Suspect("candidates-produced-nothing",
        hidden > 0
            and ("ветки выдали " .. produced .. " кандидатов, до игрока не дошло"
                 .. " ни одного: " .. hidden .. " скрыто самим игроком (/fp show"
                 .. " вернёт их)")
            or ("ветки выдали " .. produced .. " кандидатов, а в списке нет ни"
                .. " одного совета — потеря между Add и выдачей"),
        { counts = counts, hidden = hidden, cards = #ctx.cards })
end)

-- 27. A profit figure nobody confirmed by listing or buying the item.
--
--     THIS IS THE CHECK THAT SHOULD HAVE CAUGHT THE BOOTS. The top card
--     promised 4 gold 74 for Linen Boots on the strength of one listing at 167
--     times the item's own week-long price, and the player listed boots at 5
--     gold because of it. Two separate things are suspicious here and both get
--     their own code, because they have different fixes: a revenue with no
--     market observation behind it at all, and a revenue the history says is
--     an outlier.
check("profit-without-market", function(ctx)
    for _, card in ipairs(ctx.cards) do
        if card.kind == ns.KIND.CRAFT_PROFIT then
            -- "No market price" means nobody listed or bought this item. The
            -- vendor's offer is not a market price: it is a fixed number out of
            -- the item's own data, and selling a crafted item to a vendor is
            -- not the trade the card is describing.
            local origin = card.revOrigin or {}
            if origin.market == false then
                -- ИСТОЧНИК НАЗЫВАЕТСЯ СЛОВАМИ, А НЕ КОДОМ. Здесь стояло
                -- tostring(origin.src), и на карточке это читалось как
                -- «Единственная цена здесь — vendor, то есть сколько даст
                -- торговец». Слово «vendor» игрок в игре не видел нигде. Слова
                -- берутся у того, кто цену и отдал (PriceProvider.SRC_LABEL):
                -- название источника - одно на весь аддон.
                local srcText = (ns.PriceProvider
                    and ns.PriceProvider:SourceLabel(origin.src))
                    or "источник, которого я сам не узнал"
                Diag:Suspect("profit-without-market",
                    string.format("«%s»: обещано %s, но рыночной цены никто не"
                        .. " подтверждал — ни аукциона, ни моего наблюдения."
                        .. " Расчёт стоит на цене из другого источника (%s),"
                        .. " а это не рынок",
                        card.title or "?", money(card.benefitValue),
                        srcText),
                    { key = card.key, itemID = card.itemID,
                      revenue = card.revenue, src = origin.src })
            end
            local outlier = card.priceOutlier
            if outlier then
                local v = card.revOrigin and card.revOrigin.verdict or {}
                Diag:Suspect("profit-on-outlier-price",
                    string.format("«%s»: цена предмета помечена как %s (отличается от"
                        .. " наблюдённого в %s, выборка %s %s) — прибыль считаю по истории",
                        card.title or "?",
                        (ns.MarketHistory and ns.MarketHistory.FLAG_LABEL[outlier])
                            or tostring(outlier),
                        (ns.MarketHistory and ns.MarketHistory:TimesText(v.ratio or 1))
                            or "несколько раз",
                        tostring(v.days or 0),
                        U.plural(v.days or 0, "день", "дня", "дней")),
                    { key = card.key, itemID = card.itemID, flag = outlier,
                      ratio = v.ratio, days = v.days, median = v.median,
                      live = card.revOrigin and card.revOrigin.liveCopper or nil })
            end
        end
    end
end)

-- 28. A revenue figure wildly above what a vendor pays for the same item.
--
--     A crafted item normally sells on the auction house for some multiple of
--     what a vendor would pay - a few times, sometimes ten or twenty. Two
--     thousand times is not a market, it is a typo in somebody's listing. This
--     catches the same class of error as check 27 even when there is no price
--     history to compare against, which is the state every item is in on the
--     first day of a realm.
--
--     ПОРОГ ЖИВЁТ В Logic/Risk.lua, А НЕ ЗДЕСЬ. Та же цифра решает, пометить
--     ли карточку сомнительной на экране; когда их было две, предупреждение для
--     игрока и запись в файле могли разъехаться, и разъехались: файл ругался на
--     жезл, а карточка выглядела обычной.
--
--     А ПОТОМ РАЗЪЕХАЛИСЬ СЛОВА ПРИ ОДНОМ ПОРОГЕ. Живой прогон: файл писал про
--     краску «это в 166 раз больше, для крафта такого разрыва НЕ БЫВАЕТ», а
--     карточка про тот же разрыв - «наценка большая, так БЫВАЕТ». Одно число,
--     два противоположных утверждения, и игрок видел только второе. Утверждение
--     «не бывает» принадлежит порогу недоверия (Risk.VENDOR_RATIO_LIMIT) и
--     осталось только там; здесь остались числа и то, что с ними делать.
--
--     И ПРОВЕРКА СТАЛА СТОРОЖЕМ. Разрыв называет сама карточка: до тысячи раз -
--     Risk:VendorRatioNote, дальше - Risk:Plausibility. Поэтому находка
--     записывается только тогда, когда карточка про разрыв МОЛЧИТ, то есть
--     когда механизм не сработал. Её молчание - и есть доказательство, что
--     сомнение доехало до экрана. А если она всё-таки сработает, текст написан
--     словами для игрока (Checks.SCOPE = "say") и встанет на саму карточку.
Checks.VENDOR_RATIO_LIMIT = (ns.Risk and ns.Risk.VENDOR_RATIO_NOTE) or 100

-- Сказала ли карточка про разрыв сама. Спрашивается у тех же пометок, которые
-- его и ставят, а не по словам в тексте: слова можно переписать.
function Checks:SaysVendorGap(card)
    if type(card) ~= "table" then return false end
    if card.vendorRatioNote ~= nil then return true end
    if card.suspect ~= nil then return true end
    for _, d in ipairs(card.doubts or {}) do
        if d.code == "revenue-far-above-vendor" then return true end
    end
    return false
end

check("revenue-far-above-vendor", function(ctx)
    for _, card in ipairs(ctx.cards) do
        if card.kind == ns.KIND.CRAFT_PROFIT and card.revenue and card.itemID then
            local info = ns.Api:ItemInfo(card.itemID)
            local vendorPays = info and tonumber(info.sellPrice) or nil
            if vendorPays and vendorPays > 0 then
                local ratio = card.revenue / vendorPays
                if ratio >= Checks.VENDOR_RATIO_LIMIT
                   and not Checks:SaysVendorGap(card) then
                    Diag:Suspect("revenue-far-above-vendor",
                        string.format("выручка %s против цены торговца %s — это в"
                            .. " %s больше. Весь расчёт держится на одной рыночной"
                            .. " цене: проверьте её на аукционе сами, прежде чем"
                            .. " вкладываться",
                            money(card.revenue), money(vendorPays),
                            U.times(U.round(ratio))),
                        { key = card.key, itemID = card.itemID,
                          revenue = card.revenue, vendor = vendorPays,
                          ratio = ratio })
                end
            end
        end
    end
end)

-- 29. A card that says the auction fee was deducted while its revenue came
--     from a vendor, or the other way round. Two claims that cannot both be
--     about the same number, and the pair was sitting on the player's screen.
check("revenue-source-contradiction", function(ctx)
    for _, card in ipairs(ctx.cards) do
        if card.kind == ns.KIND.CRAFT_PROFIT and card.revOrigin then
            local saysCut = card.why and card.why:find("сбор аукциона") ~= nil
            local isMarket = card.revOrigin.market and true or false
            if saysCut ~= isMarket then
                Diag:Suspect("revenue-source-contradiction",
                    string.format("«%s»: источник выручки %s, а текст %s про сбор"
                        .. " аукциона — одно из двух неверно",
                        card.title or "?", tostring(card.revOrigin.src),
                        saysCut and "говорит" or "молчит"),
                    { key = card.key, src = card.revOrigin.src,
                      market = isMarket, saysCut = saysCut })
            end
        end
    end
end)

-- 30. A recommended item that lowers the stat the character's profile is about.
--
--     THE CHECK FOR THE WORST FAILURE THIS ADDON HAS HAD. The gear branch now
--     vetoes these outright, so this check should never fire - which is exactly
--     why it exists. If a main-stat drop ever reaches the card list again, the
--     file says so on the next rebuild instead of waiting for the player to
--     spend the materials and notice.
check("upgrade-drops-main-stat", function(ctx)
    local setKey = ctx.snap and ctx.snap.weightSetKey or nil
    for _, card in ipairs(ctx.cards) do
        if card.kind == ns.KIND.CRAFT_GEAR and card.mainStatDrop then
            local cmp = card.compareDetail or {}
            Diag:Suspect("upgrade-drops-main-stat",
                string.format("«%s» предложено как улучшение, но главная"
                    .. " характеристика профиля «%s» падает: %s -> %s%s",
                    card.title or "?", tostring(setKey),
                    tostring(cmp.mainFrom), tostring(cmp.mainTo),
                    cmp.lossText and (" (" .. cmp.lossText .. ")") or ""),
                { key = card.key, itemID = card.itemID,
                  mainFrom = cmp.mainFrom, mainTo = cmp.mainTo,
                  losses = cmp.losses })
        end
    end
end)

-- 31. A gear card that lost a weighted stat without saying so.
--
--     The veto above only covers the profile's MAIN stat. An item can still be
--     a real upgrade overall while costing stamina or spirit, and the player is
--     entitled to read that on the card rather than discover it afterwards.
check("silent-stat-loss", function(ctx)
    for _, card in ipairs(ctx.cards) do
        if card.kind == ns.KIND.CRAFT_GEAR and card.statLosses
           and #card.statLosses > 0 then
            -- Минус ищется ПРОСТЫМ поиском, а не паттерном: «-» в паттерне
            -- Lua - это квантификатор, и полагаться на то, что одиночный минус
            -- он поймёт как литерал, значит оставить проверку на удачу. Символ
            -- взят из ns.GLYPH: раньше здесь стоял типографский минус U+2212,
            -- которого нет в шрифте клиента, а в карточке - он же, и совпадение
            -- держалось только на том, что оба места правили одновременно.
            local said = card.why and (card.why:find("просадк")
                or card.why:find(ns.GLYPH.MINUS, 1, true) or card.why:find("хуже"))
            if not said then
                local names = {}
                for i = 1, math.min(3, #card.statLosses) do
                    names[#names + 1] = tostring(card.statLosses[i].label)
                end
                Diag:Suspect("silent-stat-loss",
                    string.format("«%s»: вещь просаживает %s, но в тексте"
                        .. " карточки об этом не сказано",
                        card.title or "?", table.concat(names, ", ")),
                    { key = card.key, itemID = card.itemID,
                      losses = card.statLosses })
            end
        end
    end
end)

-- 32. The equip bonuses of an item could not be read at all.
--
--     On this client C_Item.GetItemStats returns base stats only; the equip
--     bonuses - spell damage, healing, school damage - come from the foreign
--     item database. Without it the gear advice is blind to exactly the stats
--     that matter, and must say so rather than compare half an item.
--
--     AND THE MESSAGE HAS TO BE TRUE. It used to say "внешней базы предметов
--     нет" for every kind of miss, including the common one: the database is
--     installed, working for every other item on screen, and simply has no row
--     for this one. Three facts, three sentences.
Checks.MISS_REASON_TEXT = {
    ["no-db"] = "внешней базы предметов нет вовсе",
    ["loading"] = "внешняя база ещё не загрузилась — следующий пересчёт её увидит",
    ["not-in-db"] = "этих предметов нет в базе (база работает, строки по ним нет)",
    ["no-stats"] = "в базе есть строка, но без характеристик",
    ["unknown"] = "причина не определена",
}

check("item-bonuses-unreadable", function(ctx)
    local Gear = ns.GearAdvisor
    local n = Gear and Gear.statsIncomplete or 0
    if n <= 0 then return end

    local reasons = (Gear and Gear.missReasons) or {}
    local parts = {}
    for code, count in pairs(reasons) do
        parts[#parts + 1] = (Checks.MISS_REASON_TEXT[code] or code)
            .. " — " .. count
    end
    table.sort(parts)
    local why = (#parts > 0) and table.concat(parts, "; ")
        or "причина не записана"

    Diag:Suspect("item-bonuses-unreadable",
        string.format("у %d %s не удалось прочитать бонусы экипировки"
            .. " (сила магии, лечение, школьный урон). Причина: %s."
            .. " Сравнения по этим вещам помечены как неточные",
            n, U.plural(n, "предмета", "предметов", "предметов"), why),
        { items = n, reasons = reasons,
          examples = Gear and Gear.missExamples or nil,
          itemDBState = ns.Api and ns.Api.ItemDBState and ns.Api:ItemDBState() or nil })
end)

-- 33. A foreign price observation that disagrees wildly with the auction house.
--
--     The bug this guards was a lot price read as a unit price: 12 gold 49 for
--     a reagent the auction house sells at 4 silver 99, because the quantity
--     field was ignored. The arithmetic is fixed, but the class of error -
--     a foreign number that is orders of magnitude off - deserves a watchdog
--     rather than trust.
Checks.FOREIGN_DISAGREE_FACTOR = 20

check("foreign-price-disagrees", function(ctx)
    local Price = ns.PriceProvider
    for itemID, entry in pairs(Price.session or {}) do
        local auction, foreign
        for _, route in ipairs((entry and entry.routes) or {}) do
            if route.src == "auctionator" then auction = route.copper end
            if route.src == "foreign" then foreign = route.copper end
        end
        if auction and foreign and auction > 0 and foreign > 0 then
            local ratio = (foreign > auction) and (foreign / auction) or (auction / foreign)
            if ratio >= Checks.FOREIGN_DISAGREE_FACTOR then
                Diag:Suspect("foreign-price-disagrees", string.format(
                    "предмет %d: чужое наблюдение %s против аукциона %s — расходятся"
                    .. " в %s, одному из двух верить нельзя",
                    itemID, money(foreign), money(auction), U.times(U.round(ratio))),
                    { itemID = itemID, foreign = foreign, auction = auction,
                      ratio = ratio })
            end
        end
    end
end)

-- 34. The same spell power bonus counted twice.
--
--     In this era "+N spell power" IS "+N damage and +N healing" - one bonus,
--     one number. The client writes it as a single combined line; the item
--     database writes it split in two. Putting the combined line in a stat of
--     its own meant the same pribavka appeared twice under two names, and the
--     main stat group summed both: item 253885's group read 8 instead of 4 and
--     the weaker belt won the slot by a tenth of a point.
--
--     SW:Canonical now splits the combined line, so SPELLPOWER is populated by
--     nobody and this check should never fire. That is why it exists: if a
--     future source starts filling it, the file says so instead of a score
--     quietly inflating.
check("spell-power-double-counted", function(ctx)
    local Gear = ns.GearAdvisor
    if not (Gear and Gear.ItemStats) then return end
    local seen = {}
    local function inspect(itemID, where)
        if not itemID or seen[itemID] then return end
        seen[itemID] = true
        local stats = Gear:ItemStats(itemID)
        if not stats then return end
        local combined = stats[ns.STAT.SPELLPOWER]
        if combined and combined > 0 then
            Diag:Suspect("spell-power-double-counted", string.format(
                "предмет %d (%s): отдельная «сила магии» %s вместе с уроном %s"
                .. " — это одна и та же прибавка, записанная дважды",
                itemID, tostring(where), tostring(combined),
                tostring(stats[ns.STAT.SPELLDMG] or 0)),
                { itemID = itemID, spellPower = combined,
                  spellDamage = stats[ns.STAT.SPELLDMG] })
        end
    end
    for _, equipped in pairs((ctx.snap and ctx.snap.equipped) or {}) do
        inspect(equipped.itemID, "надето")
    end
    for _, card in ipairs(ctx.cards) do
        if card.kind == ns.KIND.CRAFT_GEAR then inspect(card.itemID, card.title) end
    end
end)

-- 35. Совет «надень своё» про вещь, которой у игрока нет.
--
--     Карточка обещает бесплатный прирост: вещь уже есть, надо только надеть.
--     Если её на самом деле нет ни в сумках, ни в банке, это не совет, а
--     издевательство, и игрок пойдёт её искать.
check("equip-advice-without-item", function(ctx)
    local snap = ctx.snap
    if not snap then return end
    for _, card in ipairs(ctx.cards) do
        if card.kind == ns.KIND.EQUIP and card.itemID then
            local here = (snap.bags and snap.bags[card.itemID]) or 0
            local bank = (snap.bank and snap.bank[card.itemID]) or 0
            if here + bank <= 0 then
                Diag:Suspect("equip-advice-without-item", string.format(
                    "«%s»: предмета %d нет ни в сумках, ни в банке —"
                    .. " надевать нечего",
                    card.title or "?", card.itemID),
                    { key = card.key, itemID = card.itemID,
                      where = card.equipSwap and card.equipSwap.where or nil })
            end
        end
    end
end)

-- 36. Крафт или покупка вещи, которая хуже той, что у игрока уже лежит.
--
--     Живая находка: в правой руке удочка, в сумке Мерцающий посох, а аддон
--     советует крафтить оружие. Ветка экипировки теперь сравнивает кандидата с
--     лучшим из ИМЕЮЩЕГОСЯ, поэтому проверка обязана молчать - и именно поэтому
--     она здесь: если такой совет снова доедет до списка, это будет написано в
--     файле на следующем пересчёте, а не выяснится после потраченных материалов.
check("advice-worse-than-owned", function(ctx)
    local Gear = ns.GearAdvisor
    local snap = ctx.snap
    if not (snap and Gear and Gear.SlotBaseline) then return end
    for _, card in ipairs(ctx.cards) do
        if card.kind == ns.KIND.CRAFT_GEAR and card.itemID then
            local info = ns.Api:ItemInfo(card.itemID)
            local itemSlot = info and ns.SlotMap:FromEquipLoc(info.equipLoc) or nil
            local targets = itemSlot and ns.SlotMap:TargetSlots(itemSlot) or {}
            local score = Gear:ItemScore(card.link or card.itemID, snap.weights)
            for _, target in ipairs(targets) do
                local base = Gear:SlotBaseline(target, snap, snap.weights)
                if score and base and base.itemID and base.where ~= "equipped"
                    and base.score > score + 0.01 then
                    -- Числа здесь дробные (это сравнение, а не подпись на
                    -- карточке), поэтому единица названа не существительным, а
                    -- шкалой: «2 балл» после дробного числа не напишешь, а
                    -- «по вашим весам» говорит ровно то, что нужно. Слово
                    -- «балл» печатает U.benefit, и только для целых чисел.
                    Diag:Suspect("advice-worse-than-owned", string.format(
                        "«%s» (%.1f по вашим весам) предложено, хотя %s уже лежит"
                        .. " «%s» (%.1f) на тот же слот «%s»",
                        card.title or "?", score,
                        (base.where == "bank") and "в банке" or "в сумке",
                        tostring(base.label), base.score,
                        ns.SlotMap:Label(target)),
                        { key = card.key, itemID = card.itemID,
                          ownedItemID = base.itemID, ownedScore = base.score,
                          cardScore = score })
                end
            end
        end
    end
end)

-- 37. Карточка, чьи числа не сходятся, доехала до игрока БЕЗ предупреждения.
--
--     Эта проверка существует потому, что предыдущая версия аддона делала
--     именно так. Проверка 28 ловила жезл с выручкой 2з 66с против цены
--     торговца 5м, писала про него в файл - и карточка всё равно уходила на
--     экран восьмой строкой, с заголовком «оценка ≈2з 64с» и без слова о том,
--     что числа друг другу противоречат. Теперь неправдоподобие помечается в
--     движке (Logic/Risk.lua), и проверка следит, что пометка действительно
--     доехала: достоверность опущена, заголовок предупреждает, текст объясняет.
--     Молчание этой проверки - и есть доказательство, что механизм работает.
check("suspect-card-unmarked", function(ctx)
    if not ns.Risk then return end
    for _, card in ipairs(ctx.cards) do
        local p = ns.Risk:Plausibility(card)
        if p then
            local marked = card.suspect ~= nil
            local confDropped = (card.conf == ns.CONF.UNKNOWN)
            local headWarns = U.contains(card.benefit or "", "сомнительно")
            local bodyWarns = U.contains(card.why or "", "не сходятся")
            if not (marked and confDropped and headWarns and bodyWarns) then
                Diag:Suspect("suspect-card-unmarked", string.format(
                    "«%s»: %s — а на карточке об этом %s (пометка %s,"
                    .. " достоверность %s, заголовок %s, текст %s)",
                    card.title or "?", p.text,
                    marked and "сказано не до конца" or "не сказано",
                    marked and "есть" or "нет",
                    tostring(card.conf),
                    headWarns and "предупреждает" or "молчит",
                    bodyWarns and "объясняет" or "молчит"),
                    { key = card.key, itemID = card.itemID, code = p.code,
                      ratio = p.ratio, marked = marked, conf = card.conf })
            end
        end
    end
end)

-- 38. НАЦЕНКА, КОТОРОЙ НЕ БЫВАЕТ.
--
--     Шесть карточек живого прогона обещали наценку от 419% до 2433% на товаре
--     одного торговца. Ни одна не была правдой: цена торговца в данных на два
--     порядка ниже той, что в игре. Порог и его обоснование лежат в
--     Logic/VendorArbitrage.lua (MARKUP_LIMIT), здесь - только запись в файл,
--     потому что странности, поднятые во время сборки, до файла не доживают.
check("arbitrage-markup-impossible", function(ctx)
    -- Такие находки на экран больше не идут (Engine:AddArbitrageCards), но в
    -- файле остаться обязаны: движок отдаёт их отдельным списком.
    local hidden = ns.ActionEngine and ns.ActionEngine.meta
        and ns.ActionEngine.meta.arbitrageImpossible or {}
    for _, card in ipairs(hidden) do
        local v = card.markupVerdict
        local opp = card.arbitrage or {}
        Diag:Suspect("arbitrage-markup-impossible", string.format(
            "«%s» (в список не поставлено): %s", card.title or tostring(card.itemID), v.text),
            { key = card.key, itemID = card.itemID, hidden = true,
              ask = v.ask, revenue = v.revenue, markup = v.markup,
              npcID = opp.npcID, npcName = opp.npcName,
              askSrc = opp.askSrc })
    end
    for _, card in ipairs(ctx.cards) do
        local v = card.markupVerdict
        if v and v.code == "markup-impossible" then
            local opp = card.arbitrage or {}
            Diag:Suspect("arbitrage-markup-impossible", string.format(
                "«%s»: %s", card.title or tostring(card.itemID), v.text),
                { key = card.key, itemID = card.itemID,
                  ask = v.ask, revenue = v.revenue, markup = v.markup,
                  npcID = opp.npcID, npcName = opp.npcName,
                  askSrc = opp.askSrc })
        end
    end
end)

-- 39. БОЛЬШИНСТВО СОВЕТОВ ОДНОЙ ВЕТКИ ВЕДЁТ К ОДНОМУ ИСТОЧНИКУ.
--
--     Проверка не про цену и не про прибыль: она про ФОРМУ списка. В живом
--     прогоне семь из восьми карточек «Купить и перепродать» вели к одному NPC
--     (Mister Graphed, 263384), и каждая по отдельности выглядела прилично -
--     цена есть, координаты есть, прибыль посчитана. Неправильным был один
--     набор записей в данных, а не семь разных фактов, и увидеть это можно
--     было ровно по тому, что советы сошлись в одну точку.
--
--     Поэтому вопрос здесь - «а не одна ли это находка, посчитанная семь раз».
--     Ветка с двумя советами на одного торговца ничего не доказывает, поэтому
--     порог снизу (CONCENTRATION_MIN); доля больше половины - уже не
--     совпадение.
check("advice-concentrated-on-one-source", function(ctx)
    local MIN = (ns.VendorArbitrage and ns.VendorArbitrage.CONCENTRATION_MIN) or 3
    local SHARE = (ns.VendorArbitrage and ns.VendorArbitrage.CONCENTRATION_SHARE) or 0.5

    -- Источник карточки - тот NPC, к которому она посылает. Берётся из места,
    -- куда ведёт стрелка, а не из текста: текст можно переписать, а стрелка
    -- показывает, куда игрок пойдёт.
    local function sourceOf(card)
        if card.place and tonumber(card.place.npcID) then
            return tonumber(card.place.npcID), card.place.name
        end
        if card.arbitrage and tonumber(card.arbitrage.npcID) then
            return tonumber(card.arbitrage.npcID), card.arbitrage.npcName
        end
        return nil
    end

    local byKind = {}
    for _, card in ipairs(ctx.cards) do
        local id, name = sourceOf(card)
        if id and card.kind then
            local bucket = byKind[card.kind]
            if not bucket then
                bucket = { total = 0, tally = {}, names = {} }
                byKind[card.kind] = bucket
            end
            bucket.total = bucket.total + 1
            bucket.tally[id] = (bucket.tally[id] or 0) + 1
            bucket.names[id] = bucket.names[id] or name
        end
    end

    for kind, bucket in pairs(byKind) do
        if bucket.total >= MIN then
            local topID, topCount = nil, 0
            for id, n in pairs(bucket.tally) do
                if n > topCount or (n == topCount and topID and id < topID) then
                    topID, topCount = id, n
                end
            end
            local share = topID and (topCount / bucket.total) or 0
            if topID and share >= SHARE then
                Diag:Suspect("advice-concentrated-on-one-source", string.format(
                    "ветка «%s»: %d из %d советов ведут к одному источнику (%s)."
                    .. " Это может быть одна ошибка в данных, посчитанная %s,"
                    .. " а не %s",
                    tostring(kind), topCount, bucket.total,
                    bucket.names[topID] and tostring(bucket.names[topID])
                        or ("#" .. tostring(topID)),
                    U.times(topCount) or "несколько раз",
                    topCount .. " " .. U.plural(topCount, "независимая находка",
                        "независимые находки", "независимых находок")),
                    { kind = kind, npcID = topID, npcName = bucket.names[topID],
                      count = topCount, total = bucket.total, share = share })
            end
        end
    end
end)

-- 40. ВЫРУЧКА ВЫШЕ ЦЕНЫ НА НЕОГРАНИЧЕННОЙ ПОЛКЕ, А КАРТОЧКА ОБ ЭТОМ МОЛЧИТ.
--
--     Это СТОРОЖ, а не вторая проверка того же. Разрыв называет сама карточка
--     (Risk:CeilingDoubt из Risk:Attach), и находка записывается только тогда,
--     когда пометка до карточки НЕ доехала. Молчание проверки - и есть
--     доказательство, что механизм работает; сработает - текст написан словами
--     для игрока и встанет на саму карточку (Checks.SCOPE = "say").
--
--     Тот же класс ошибки, что у льняных сапог, но с другой стороны. Там одна
--     завышенная цена лота обещала прибыль; здесь цена может быть настоящей, а
--     покупателя нет: тот же предмет стоит у торговца дешевле и в
--     неограниченном количестве, и покупать у игрока дороже незачем.
check("revenue-above-vendor-ceiling", function(ctx)
    if not ns.Risk then return end
    for _, card in ipairs(ctx.cards) do
        local doubt = ns.Risk:CeilingDoubt(card)
        if doubt then
            local said = false
            for _, d in ipairs(card.doubts or {}) do
                if d.code == doubt.code then said = true end
            end
            if not said then
                Diag:Suspect("revenue-above-vendor-ceiling", string.format(
                    "«%s»: %s", card.title or "?", doubt.text),
                    { key = card.key, itemID = card.itemID,
                      revenue = doubt.revenue, ceiling = doubt.ceiling,
                      ratio = doubt.ratio, src = doubt.ceilingSrc })
            end
        end
    end
end)

-- 41. СОВЕТ РАССТАТЬСЯ С ВЕЩЬЮ, У КОТОРОГО НЕ СПРОСИЛИ ПРО ОБЛИК.
--
--     Эта проверка не про текст, а про то, что ВОПРОС БЫЛ ЗАДАН. Потерянный
--     облик - единственная ошибка этого аддона, которую игрок не отменит, и
--     поэтому способ её допустить должен быть закрыт не в шести ветках по
--     отдельности, а один раз и здесь: новая ветка, которая советует продать,
--     распылить или переслать, без ответа про облик не пройдёт.
--
--     Перечень видов ЗАКРЫТЫЙ, и в нём именно те шесть, которые расстаются с
--     вещью. Из них две карточки «между персонажами» не расстаются ни с чем
--     (сумма золота на всех и перечень профессий альтов) - они перечислены по
--     ключу, тоже закрытым списком.
Checks.PARTING_KINDS = {}
Checks.PARTING_EXEMPT = { ["cross:gold"] = true, ["cross:professions"] = true }
do
    for _, kind in ipairs({ "SELL_JUNK", "DISENCHANT", "RESELL", "ARBITRAGE",
                            "CRAFT_PROFIT", "CROSS_CHAR" }) do
        local value = ns.KIND[kind]
        if value then Checks.PARTING_KINDS[value] = true end
    end
end

check("appearance-unchecked", function(ctx)
    for _, card in ipairs(ctx.cards) do
        -- Карточка «скрафтить и надеть», которая вторым вариантом называет
        -- продажу, расстаётся с вещью ровно так же - её вид в перечне не стоит,
        -- а спросить про облик она обязана.
        local parts = Checks.PARTING_KINDS[card.kind] or (card.alsoSell ~= nil)
        if parts and not Checks.PARTING_EXEMPT[card.key or ""] then
            if type(card.looks) ~= "table" then
                Diag:Suspect("appearance-unchecked", string.format(
                    "«%s»: совет расстаться с вещью, а про облик не спрошено —"
                    .. " облик теряется навсегда, и предупредить об этом"
                    .. " было негде", card.title or "?"),
                    { key = card.key, kind = card.kind, itemID = card.itemID })
            end
        end
    end
end)

-- Runner -----------------------------------------------------------------

-- ctx = { cards, snap, counts, generated, hidden, enchantBySlot }
-- `out` USED TO MEAN "CHECKS RUN", which read as thirty-two findings on six
-- cards and sent a reader looking for thirty-one problems that were not there.
-- The fields are named for what they are now, and `out` is the findings count,
-- because that is the number a zero needs a reason for.
function Checks:Run(ctx)
    if not ctx or type(ctx.cards) ~= "table" then return 0 end
    local before = #(Diag:Init().suspicious or {})
    local ran, failed = 0, 0
    -- НА ВРЕМЯ ПРОХОДА КАРТОЧКИ ПРИВЯЗАНЫ, И НАХОДКА ЕДЕТ НА СВОЮ КАРТОЧКУ.
    -- Привязка снимается в любом случае: каждая проверка идёт под Diag:Guard,
    -- то есть наружу отсюда ничего не выбрасывается.
    Diag:BindCards(ctx.cards)
    for _, entry in ipairs(Checks.LIST) do
        -- A broken check must never take the addon down with it, and it must be
        -- visible rather than silently skipped.
        local ok = Diag:Guard("SanityChecks:" .. entry.code, entry.run, ctx)
        ran = ran + 1
        if not ok then failed = failed + 1 end
    end
    local onCards, lost = Diag:UnbindCards()
    local findings = #(Diag:Init().suspicious or {}) - before
    if findings < 0 then findings = 0 end
    Diag:Module("sanityChecks", {
        ["in"] = #ctx.cards,
        out = findings,
        checks = #Checks.LIST,
        ran = ran,
        findings = findings,
        failed = failed,
        -- Сколько находок доехало до своей карточки и сколько назвали ключ,
        -- которого в списке нет. Второе - дефект маршрута, а не ноль: по этому
        -- числу видно, что сомнение осталось только в файле.
        onCards = onCards,
        lostDoubts = lost,
        reason = (findings == 0)
            and ((ran == 0) and "нет зарегистрированных проверок"
                or "проверки прошли, замечаний нет") or nil,
        reasonCode = (findings == 0)
            and ((ran == 0) and "NO_API" or "ALL_DONE") or nil,
    })
    return ran, failed, findings
end

function Checks:Count()
    return #Checks.LIST
end

-- Is a given check registered? Used by the tests to assert that a guard which
-- is SUPPOSED to stay silent exists at all - "it did not fire" is worthless
-- evidence if the check was never there.
function Checks:HasCheck(code)
    for _, entry in ipairs(Checks.LIST) do
        if entry.code == code then return true end
    end
    return false
end

return Checks
