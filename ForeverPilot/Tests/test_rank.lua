-- ForeverPilot / Tests/test_rank.lua
-- Ranking: profile weights, normalisation, pinned setup cards, chips,
-- degradation when Auctionator or the bank is missing, and the skill-zero trap.
local H = ...

return function()

-- A world with one of everything: a wearable upgrade, an enchant, a profitable
-- craft the character cannot wear, a skill-up craft, and some junk.
local function world(opts)
    opts = opts or {}
    local env = H.load()
    local ns = env.ns
    env.player.level = 26
    env.player.classFile = "MAGE"
    env.player.className = "Маг"
    env.spec = "Тайная магия"
    env.money = opts.money or 25081
    env.auctionator = (opts.auctionator ~= false)
    env.bank = opts.bank

    -- Materials.
    H.item(env, 2589, { name = "Льняная ткань", sellPrice = 5 })
    H.item(env, 14047, { name = "Рунная ткань", sellPrice = 50 })
    H.item(env, 11137, { name = "Магическая пыль", sellPrice = 120 })
    env.prices[2589] = 50
    env.prices[14047] = 400
    env.prices[11137] = 900

    -- Worn head, weak.
    H.item(env, 100, { name = "Старый капюшон", equipLoc = "INVTYPE_HEAD",
        reqLevel = 20, classID = 4, subclassID = 1, sellPrice = 50 })
    env.stats[100] = { ITEM_MOD_INTELLECT_SHORT = 3 }
    env.equipped.HEAD = { itemID = 100 }

    -- Worn bracers, bare, enchantable.
    H.item(env, 110, { name = "Наручи", equipLoc = "INVTYPE_WRIST",
        reqLevel = 20, classID = 4, subclassID = 1 })
    env.equipped.WRIST = { itemID = 110 }

    -- Craftable wearable upgrade.
    H.item(env, 101, { name = "Новый капюшон", equipLoc = "INVTYPE_HEAD",
        reqLevel = 24, classID = 4, subclassID = 1, sellPrice = 300 })
    env.stats[101] = { ITEM_MOD_INTELLECT_SHORT = 14, ITEM_MOD_STAMINA_SHORT = 8 }
    env.prices[101] = 2500

    -- Craftable, very profitable, NOT wearable (the Forever case).
    H.item(env, 13856, { name = "Пояс из рунной ткани", equipLoc = "INVTYPE_WAIST",
        reqLevel = 55, classID = 4, subclassID = 1, sellPrice = 2000 })
    env.stats[13856] = { ITEM_MOD_INTELLECT_SHORT = 40 }
    env.prices[13856] = 60000     -- sells for 6 gold, mats cost 1.2 gold

    -- Junk in the bags.
    H.item(env, 9000, { name = "Рваная шкура", sellPrice = 70, quality = 0 })
    env.bags[9000] = 8

    env.bags[2589] = 6
    if opts.extraBags then
        for id, qty in pairs(opts.extraBags) do env.bags[id] = qty end
    end

    H.profession(env, "Tailoring", opts.tailoringSkill or 225, 225, {
        H.recipe { id = 1, name = "Новый капюшон", output = 101, outputQty = 1,
                   reagents = { { itemID = 2589, qty = 6 } }, diff = "optimal",
                   category = "Капюшоны", categoryID = 1 },
        H.recipe { id = 2, name = "Пояс из рунной ткани", output = 13856, outputQty = 1,
                   reagents = { { itemID = 14047, qty = 3 } }, diff = "medium",
                   category = "Пояса", categoryID = 2 },
        H.recipe { id = 3, name = "Льняные бинты", output = 2581, outputQty = 1,
                   reagents = { { itemID = 2589, qty = 2 } }, diff = "trivial",
                   category = "Бинты", categoryID = 3 },
    })
    H.item(env, 2581, { name = "Льняные бинты", sellPrice = 6 })
    env.prices[2581] = 30

    H.profession(env, "Enchanting", 225, 225, {
        H.recipe { id = 13822, name = "Чары для браслетов: интеллект III",
                   reagents = { { itemID = 11137, qty = 1 } }, learned = true,
                   category = "Чары для наручей", categoryID = 10, diff = "medium" },
    })
    if opts.enchantMats then env.bags[11137] = opts.enchantMats end

    return env
end


H.suite("Ранжирование: самый выгодный совет не по карману стоит ниже выполнимых")
do
    -- В кошельке 1 серебро. Пояс из рунной ткани - САМЫЙ выгодный совет в
    -- списке по очкам (профиль «Заработок» ценит деньги выше всего), но
    -- материалы на него стоят двенадцать таких кошельков. Совет остаётся в
    -- списке и честно называет цену, но выше того, что игрок может сделать
    -- сегодня, не встаёт.
    --
    -- Порог «в разы дороже кошелька» посчитан ЗДЕСЬ своей арифметикой, а не
    -- взят из проверяемого модуля. Проверка, которая берёт порог у кода,
    -- остаётся зелёной, когда порог убирают: ровно так этот контракт и
    -- оказался непокрытым (мутация M7 в Tests/mutate.py).
    local WALLET, FAR = 100, 3
    local env = world({ money = WALLET, enchantMats = 3 })
    local ns = env.ns
    ns.Config:SetProfile("EARN")
    local cards = H.build(env)

    -- Предпосылка: в списке действительно есть совет, который и дороже
    -- кошелька в разы, и выгоднее всего остального. Без неё проверка ниже
    -- ничего не проверяет, поэтому она утверждение, а не комментарий.
    local best, bestAt
    for i, card in ipairs(cards) do
        if not card.pinTop and (not best or (card.score or 0) > (best.score or 0)) then
            best, bestAt = card, i
        end
    end
    H.ok(best ~= nil and best.cost ~= nil and best.cost > FAR * WALLET,
        "предпосылка: самый выгодный совет дороже кошелька в разы",
        best and string.format("%s за %s при кошельке %s",
            ns.Util.truncate(best.title, 30), ns.Util.money(best.cost or 0),
            ns.Util.money(WALLET)) or "такого совета нет")
    H.eq(best and best.outOfReach, true, "он помечен как недоступный")
    H.ok(best and tostring(best.need):find("в %d+ раз[^ ]* больше, чем у вас есть") ~= nil,
        "и в тексте названо, во сколько раз",
        best and ns.Util.truncate(best.need, 90))

    -- Выполнимое сегодня: ничего не стоит дороже кошелька, не информационное,
    -- не убыточное.
    local doable, below = {}, {}
    for i, card in ipairs(cards) do
        local affordable = (card.cost == nil) or (card.cost <= WALLET)
        if affordable and not card.informational and not card.losesMoney
            and not card.outOfReach and (card.score or 0) >= 0
            and card.kind ~= ns.KIND.SETUP then
            doable[#doable + 1] = card
            if i > (bestAt or 0) then below[#below + 1] = ns.Util.truncate(card.title, 30) end
        end
    end
    H.ok(#doable >= 2, "предпосылка: выполнимых советов в списке " .. #doable)
    H.eq(#below, 0, "ни один выполнимый совет не оказался ниже недоступного"
        .. ((#below > 0) and (": " .. table.concat(below, ", ")) or ""))
end

local function byKind(cards)
    local out = {}
    for _, card in ipairs(cards) do
        out[card.kind] = out[card.kind] or {}
        table.insert(out[card.kind], card)
    end
    return out
end

H.suite("Ранжирование: список не пустой и разнородный")
do
    local env = world()
    local ns = env.ns
    local cards, meta = H.build(env)
    H.ok(#cards > 0, "карточки есть (" .. #cards .. ")")
    local kinds = byKind(cards)
    H.ok(kinds[ns.KIND.CRAFT_GEAR] ~= nil, "есть совет надеть")
    H.ok(kinds[ns.KIND.CRAFT_PROFIT] ~= nil, "есть совет продать")
    H.ok(kinds[ns.KIND.ENCHANT] ~= nil, "есть совет по чарам")
    H.ok(kinds[ns.KIND.SELL_JUNK] ~= nil, "есть совет про хлам")
    H.ok(ns.Util.count(kinds) >= 4, "в одном списке минимум 4 типа карточек")
end

H.suite("Карточка: три строки и достоверность у каждой")
do
    local env = world()
    local cards = H.build(env)
    local bad = 0
    for _, card in ipairs(cards) do
        if not (card.title and card.title ~= "") then bad = bad + 1 end
        if not (card.why and card.why ~= "") then bad = bad + 1 end
        if not (card.need and card.need ~= "") then bad = bad + 1 end
        if not card.benefit then bad = bad + 1 end
        if not card.conf then bad = bad + 1 end
        if not card.key then bad = bad + 1 end
        if not card.action then bad = bad + 1 end
    end
    H.eq(bad, 0, "у всех карточек заполнены: что / почему / чего не хватает / выгода / достоверность")
end

H.suite("Карточка: ключи уникальны")
do
    local env = world()
    local cards = H.build(env)
    local seen, dupes = {}, 0
    for _, card in ipairs(cards) do
        if seen[card.key] then dupes = dupes + 1 end
        seen[card.key] = true
    end
    H.eq(dupes, 0, "дублей ключей нет")
end

H.suite("Ранжирование: профиль «Сила» ставит экипировку выше денег")
do
    local env = world({ enchantMats = 3 })
    local ns = env.ns
    ns.Config:SetProfile("POWER")
    local cards = H.build(env)
    local gearPos, profitPos
    for i, card in ipairs(cards) do
        if card.kind == ns.KIND.CRAFT_GEAR and not gearPos then gearPos = i end
        if card.kind == ns.KIND.CRAFT_PROFIT and not profitPos then profitPos = i end
    end
    H.ok(gearPos and profitPos, "обе карточки на месте")
    H.ok(gearPos < profitPos,
        "при «Силе» экипировка (" .. tostring(gearPos) .. ") выше продажи ("
        .. tostring(profitPos) .. ")")
end

H.suite("Ранжирование: профиль «Заработок» ставит деньги выше экипировки")
do
    local env = world({ enchantMats = 3 })
    local ns = env.ns
    ns.Config:SetProfile("EARN")
    local cards = H.build(env)
    local gearPos, profitPos
    for i, card in ipairs(cards) do
        if card.kind == ns.KIND.CRAFT_GEAR and not gearPos then gearPos = i end
        if card.kind == ns.KIND.CRAFT_PROFIT and not profitPos then profitPos = i end
    end
    H.ok(gearPos and profitPos, "обе карточки на месте")
    H.ok(profitPos < gearPos,
        "при «Заработке» продажа (" .. tostring(profitPos) .. ") выше экипировки ("
        .. tostring(gearPos) .. ")")
end

H.suite("Ранжирование: смена профиля меняет порядок")
do
    local env = world({ enchantMats = 3 })
    local ns = env.ns
    local order = {}
    for _, profile in ipairs(ns.PROFILE_ORDER) do
        ns.Config:SetProfile(profile)
        local cards = H.build(env)
        local keys = {}
        for i = 1, math.min(5, #cards) do keys[i] = cards[i].key end
        order[profile] = table.concat(keys, "|")
    end
    local distinct = {}
    for _, v in pairs(order) do distinct[v] = true end
    H.ok(ns.Util.count(distinct) > 1,
        "разные профили дают разный порядок (" .. ns.Util.count(distinct) .. " вариантов)")
end

H.suite("Ранжирование: «Экономия» предпочитает то, что уже есть")
do
    -- Two profitable crafts: one fully covered by the bags, one needing a trip.
    local env = world({ extraBags = { [14047] = 3 } })
    local ns = env.ns
    ns.Config:SetProfile("THRIFT")
    local cards = H.build(env)
    local readyFirst = true
    local seenUnready = false
    for _, card in ipairs(cards) do
        if card.plan and not card.pinTop then
            if card.plan.ready and seenUnready then readyFirst = false end
            if not card.plan.ready then seenUnready = true end
        end
    end
    H.ok(readyFirst, "при «Экономии» готовое идёт раньше требующего покупок")
end

H.suite("Ранжирование: карточка настройки прибита наверх")
do
    local env = world()
    local ns = env.ns
    -- Pretend tailoring recipes were never read: the engine must say so.
    ns.RecipeBook.byProfession["Tailoring"] = nil
    ns.RecipeBook:Reindex()
    local cards = H.build(env)
    H.ok(#cards > 0, "список не пуст даже без рецептов")
    H.eq(cards[1].kind, ns.KIND.SETUP, "первая карточка - «откройте окно»")
    H.ok(cards[1].pinTop, "она прибита наверх")
    -- ИМЯ ПРОФЕССИИ НА КАРТОЧКЕ - ТО, ЧТО УВИДИТ ИГРОК. Клиент стенда
    -- отдаёт английское «Tailoring» (так же отдаёт чужой кеш Mastercraft,
    -- когда клиент ещё молчит), а на экране должно стоять имя на языке
    -- игрока: перевод делает U.profLabel. Проверка держится за ту же
    -- функцию, а не за вписанную строку, чтобы не зависеть от языка стенда.
    H.ok(cards[1].title:find(ns.Util.profLabel("Tailoring"), 1, true),
        "и называет конкретную профессию, именем для игрока: " .. cards[1].title)
    H.ok(cards[1].title:find("Tailoring", 1, true) == nil,
        "и внутреннее английское имя на карточку не попало")
    H.ok(cards[1].blocking, "её нельзя скрыть")
end

H.suite("Ранжирование: карточка настройки на каждую профессию")
do
    local env = world()
    local ns = env.ns
    ns.RecipeBook.byProfession["Tailoring"] = nil
    ns.RecipeBook.byProfession["Enchanting"] = nil
    ns.RecipeBook:Reindex()
    local cards = H.build(env)
    local setupProfs = {}
    for _, card in ipairs(cards) do
        if card.kind == ns.KIND.SETUP and card.action
           and card.action.kind == "openProfession" then
            setupProfs[card.action.profession] = true
        end
    end
    H.ok(setupProfs["Tailoring"], "карточка для портняжки")
    H.ok(setupProfs["Enchanting"], "карточка для наложения чар")
end

H.suite("Пустых экранов нет: причина всегда есть")
do
    local env = H.load()
    local ns = env.ns
    env.player.level = 26
    env.professions = { { name = "Tailoring", skill = 225, max = 225, skillTrusted = true } }
    local cards, meta = H.build(env)
    H.ok(#cards > 0, "даже без всяких данных карточки есть")
    H.eq(cards[1].kind, ns.KIND.SETUP, "и это объяснение, а не пустота")
end

H.suite("Ловушка нулевого навыка: нулю не верим")
do
    local env = world()
    local ns = env.ns
    -- Simulate GetProfessionInfoBySkillLineID: names fine, skill 0.
    env.professions = {
        { name = "Tailoring", skill = 0, max = 0, skillTrusted = false, skillBroken = true },
        { name = "Enchanting", skill = 0, max = 0, skillTrusted = false, skillBroken = true },
    }
    env.professionRoute = "GetProfessionInfoBySkillLineID"
    local cards, meta, snap = H.build(env)

    local tailoring
    for _, p in ipairs(snap.professions) do
        if p.name == "Tailoring" then tailoring = p end
    end
    H.ok(tailoring ~= nil, "профессия найдена")
    H.eq(tailoring.skill, nil, "ноль заменён на «неизвестно», а не принят за правду")
    H.eq(tailoring.skillBroken, true, "помечено как сломанные данные")

    -- And the advice must NOT collapse: recipes exist, so cards exist.
    local kinds = byKind(cards)
    H.ok(kinds[ns.KIND.CRAFT_GEAR] ~= nil or kinds[ns.KIND.CRAFT_PROFIT] ~= nil,
        "советы по крафту остались, несмотря на нулевой навык")
    local warned = false
    for _, card in ipairs(cards) do
        if card.key == "setup:skill:Tailoring" then warned = true end
    end
    H.ok(warned, "игрок предупреждён, что уровень навыка неизвестен")
end

H.suite("Навык: советы на прокачку используют сложность рецепта")
do
    -- Below the rank ceiling, so skill-up advice is meaningful.
    local env = world({ extraBags = { [2589] = 60 }, tailoringSkill = 180 })
    local ns = env.ns
    ns.Config:SetProfile("LEVEL")
    local cards = H.build(env)
    local skillCards = byKind(cards)[ns.KIND.CRAFT_SKILL]
    H.ok(skillCards and #skillCards > 0, "есть карточки на навык")
    local withChance = 0
    for _, card in ipairs(skillCards or {}) do
        if card.recipeID and card.benefitValue and card.benefitValue > 0 then
            withChance = withChance + 1
        end
    end
    H.ok(withChance > 0, "хотя бы один совет с реальным шансом навыка")
    -- The optimal recipe must be preferred over the trivial one.
    local tailoringCard
    for _, card in ipairs(skillCards or {}) do
        if card.profession == "Tailoring" and card.recipeID then tailoringCard = card end
    end
    H.ok(tailoringCard ~= nil, "совет по портняжке есть")
    if tailoringCard then
        local recipe = ns.RecipeBook:Get(tailoringCard.recipeID)
        H.ok(recipe.diff ~= "trivial", "выбран не серый рецепт (" .. tostring(recipe.diff) .. ")")
    end
end

H.suite("Навык: на пределе честно говорим про потолок, а не про тренера")
do
    -- This is the player's real situation: 225/225 on everything.
    --
    -- This suite used to assert the opposite of what it asserts now. It
    -- demanded the card say "нужен тренер", because the project believed 225
    -- was the Expert rank cap and that an Artisan trainer at character level 35
    -- would lift it. The player's own MastercraftDB history disproved that: the
    -- ceiling moved 84 -> 93 -> 160 -> 224 -> 225 in nine days, through numbers
    -- that are not ranks in any table. The card must now say the skill is at
    -- its limit and that the limit rises as the game goes on, and must NOT
    -- name a cause it cannot know. See Tests/test_skillcap.lua for the full set.
    local env = world({ extraBags = { [2589] = 60 }, tailoringSkill = 225 })
    local ns = env.ns
    ns.Config:SetProfile("LEVEL")
    local cards = H.build(env)
    local rankCard, craftSkillCard, rankCards = nil, nil, 0
    for _, card in ipairs(cards) do
        if card.cappedProfessions then rankCard = card; rankCards = rankCards + 1 end
        if card.kind == ns.KIND.CRAFT_SKILL and card.recipeID
           and card.profession == "Tailoring" then craftSkillCard = card end
    end
    H.ok(rankCard ~= nil, "есть карточка про предел навыка")
    H.eq(craftSkillCard, nil, "и НЕТ ложного совета «крафти ради навыка»")
    H.eq(rankCards, 1, "одна карточка на все упёршиеся профессии, а не по одной на каждую")
    if rankCard then
        H.ok(rankCard.why:find("225/225", 1, true), "показан упёршийся навык")
        -- Было: «сказано, что потолок поднимется по ходу игры». Аддон этого
        -- не знает (вывод был сделан из неверно прочитанной истории навыка),
        -- поэтому теперь он говорит ровно то, что знает и чего не знает.
        H.eq(rankCard.why:find("по ходу игры", 1, true), nil,
            "не сказано, что максимум «поднимается по ходу игры»: аддон этого не знает")
        H.ok(rankCard.need:find("не знаю", 1, true),
            "и прямо сказано, что когда максимум поднимется — неизвестно")
        H.eq((rankCard.need .. " " .. rankCard.why .. " " .. rankCard.benefit)
            :find("тренер", 1, true), nil,
            "и НЕ сказано про тренера - причину потолка мы не знаем")
        -- It must not dominate: under "Сила" real advice has to outrank it.
        ns.Config:SetProfile("POWER")
        local powerCards = H.build(env)
        local rankPos, gearPos
        for i, card in ipairs(powerCards) do
            if card.cappedProfessions and not rankPos then rankPos = i end
            if card.kind == ns.KIND.CRAFT_GEAR and not gearPos then gearPos = i end
        end
        if gearPos and rankPos then
            H.ok(gearPos < rankPos,
                "при «Силе» экипировка выше справки про предел ("
                .. gearPos .. " < " .. rankPos .. ")")
        else
            H.ok(true, "нечего сравнивать - экипировочных советов нет")
        end
    end
end

H.suite("Навык: серые рецепты не предлагаются")
do
    local env = world({ extraBags = { [2589] = 60 }, tailoringSkill = 180 })
    local ns = env.ns
    ns.Config:Get().show.hideTrivialSkill = true
    local cards = H.build(env)
    local checked = 0
    for _, card in ipairs(cards) do
        if card.kind == ns.KIND.CRAFT_SKILL and card.recipeID then
            local recipe = ns.RecipeBook:Get(card.recipeID)
            checked = checked + 1
            H.ok(recipe.diff ~= "trivial",
                "«" .. card.title .. "» не серый рецепт")
        end
    end
    H.ok(checked > 0, "было что проверять (" .. checked .. ")")
end

-- Degradation ---------------------------------------------------------

H.suite("Деградация: Auctionator выключен")
do
    local env = world({ auctionator = false, enchantMats = 3 })
    local ns = env.ns
    local cards, meta = H.build(env)

    H.ok(#cards > 0, "список не пуст без Auctionator (" .. #cards .. ")")
    H.eq(meta.priceSources.auctionatorAvailable, false, "сводка знает, что аукциона нет")

    local warned = false
    for _, card in ipairs(cards) do
        if card.key == "setup:auctionator" then warned = true end
    end
    H.ok(warned, "игрок предупреждён про отсутствие цен")

    -- Power and enchant advice must survive: they do not depend on gold.
    local kinds = byKind(cards)
    H.ok(kinds[ns.KIND.CRAFT_GEAR] ~= nil, "советы по экипировке живы")
    H.ok(kinds[ns.KIND.ENCHANT] ~= nil, "советы по чарам живы")

    -- Junk advice uses the client's own sell price, so it stays exact.
    local junk = kinds[ns.KIND.SELL_JUNK]
    H.ok(junk and junk[1].conf == ns.CONF.EXACT,
        "цена хлама остаётся точной - она из клиента, а не из аукциона")
end

H.suite("Деградация: нет данных банка")
do
    local env = world({ bank = nil, enchantMats = 3 })
    local ns = env.ns
    local cards, meta, snap = H.build(env)
    H.eq(snap.bank, nil, "банк неизвестен")
    H.eq(snap.bankConf, ns.CONF.UNKNOWN, "и помечен как неизвестный, а не пустой")

    local warned = false
    for _, card in ipairs(cards) do
        if card.key == "setup:bank" then warned = true end
    end
    H.ok(warned, "карточка про банк показана")
    H.ok(#cards > 0, "советы всё равно строятся")
end

H.suite("Деградация: банк виден и пуст - это не «неизвестно»")
do
    local env = world({ bank = {}, enchantMats = 3 })
    local ns = env.ns
    local cards, meta, snap = H.build(env)
    H.ok(snap.bank ~= nil, "банк виден")
    H.eq(snap.bankConf, ns.CONF.EXACT, "пустой банк - точные данные")
    for _, card in ipairs(cards) do
        H.ok(card.key ~= "setup:bank", "карточки про банк нет")
    end
end

H.suite("Деградация: мало золота - не советуем тратить всё")
do
    local env = world({ money = 500, enchantMats = 0 })
    local ns = env.ns
    local cards = H.build(env)
    local afford = ns.ShoppingList:Affordability(ns.CharacterScanner:Get())
    H.eq(afford.money, 500, "денег 5 серебра")
    -- Affordability is now a three-state answer: yes, no, or "some lines have
    -- no price so the total is an understatement and I will not conclude".
    -- Claiming "you cannot afford it" from an incomplete total was a verdict
    -- the data did not support.
    if afford.complete then
        if afford.total > 500 then
            H.eq(afford.affordable, false, "список не по карману и это видно")
            H.ok(afford.shortfall > 0, "посчитана недостающая сумма")
        else
            H.eq(afford.affordable, true, "список по карману")
        end
    else
        H.eq(afford.affordable, nil, "при неизвестных ценах вывод не делается")
        H.ok(afford.unknownLines > 0,
            afford.unknownLines .. " позиций без цены — это и есть причина")
    end
    local buyCard
    for _, card in ipairs(cards) do
        if card.kind == ns.KIND.BUY then buyCard = card; break end
    end
    if buyCard then
        H.ok(buyCard.need:find("хватает") or buyCard.need:find("цены нет"),
            "карточка покупки честно пишет про деньги",
            "need = " .. tostring(buyCard.need))
    else
        H.ok(true, "карточек покупки нет - тоже допустимо при пустом кошельке")
    end
end

-- Chips ---------------------------------------------------------------

H.suite("Чипы: фильтруют один и тот же список")
do
    local env = world({ enchantMats = 3 })
    local ns = env.ns
    local cards = H.build(env)
    local all = ns.ActionEngine:Filtered(ns.CHIP.ALL)
    H.eq(#all, #cards, "«Всё» - весь список")

    -- СПИСОК РАЗРЕШЁННЫХ ТИПОВ БЕРЁТСЯ ИЗ ns.CHIP_KINDS, А НЕ ПЕРЕПИСЫВАЕТСЯ
    -- ЗДЕСЬ. Переписанный от руки, он устаревал при каждом новом виде карточек
    -- (так случилось с FAVOR), то есть проверка начинала падать на правильном
    -- коде. Контракт на самом деле такой: чип пропускает ровно те виды, которые
    -- сам объявил, и ничего больше.
    local allowedGear = ns.CHIP_KINDS.GEAR
    H.ok(allowedGear ~= nil, "чип «Экипировка» объявляет свой список типов")
    local gear = ns.ActionEngine:Filtered(ns.CHIP.GEAR)
    for _, card in ipairs(gear) do
        H.ok(allowedGear[card.kind] == true,
            "в «Экипировке» только подходящие типы (" .. card.kind .. ")")
    end

    local allowedGold = ns.CHIP_KINDS.GOLD
    local gold = ns.ActionEngine:Filtered(ns.CHIP.GOLD)
    for _, card in ipairs(gold) do
        H.ok(allowedGold[card.kind] == true,
            "в «Золоте» только денежные типы (" .. card.kind .. ")")
    end

    local ench = ns.ActionEngine:Filtered(ns.CHIP.ENCHANT)
    H.ok(#ench > 0, "в «Чарах» что-то есть")

    local ready = ns.ActionEngine:Filtered(ns.CHIP.READY)
    for _, card in ipairs(ready) do
        local isReady = card.pinTop or (card.plan and card.plan.ready)
            or card.kind == ns.KIND.SELL_JUNK or card.kind == ns.KIND.SETUP
        H.ok(isReady, "в «Можно сейчас» только готовое (" .. card.title .. ")")
    end

    -- The relative order inside a chip must match the global order.
    local positions = {}
    for i, card in ipairs(all) do positions[card.key] = i end
    local monotonic = true
    local last = 0
    for _, card in ipairs(gold) do
        if positions[card.key] < last then monotonic = false end
        last = positions[card.key]
    end
    H.ok(monotonic, "фильтр сохраняет общий порядок приоритета")
end

-- Shopping list -------------------------------------------------------

H.suite("Список покупок: объединяет позиции между карточками")
do
    local env = world({ enchantMats = 0 })
    local ns = env.ns
    local cards = H.build(env)
    local lines = ns.ShoppingList:Lines()
    local seen = {}
    local dupes = 0
    for _, line in ipairs(lines) do
        if seen[line.itemID] then dupes = dupes + 1 end
        seen[line.itemID] = true
    end
    H.eq(dupes, 0, "каждая позиция в списке один раз")
    local total, conf, unknown = ns.ShoppingList:Total()
    H.ok(total >= 0, "итог посчитан")
    for _, line in ipairs(lines) do
        H.ok(#line.uses > 0, "у позиции «" .. line.name .. "» указано, зачем она")
    end
end

H.suite("Список покупок: количество суммируется, а не перезаписывается")
do
    local env = world()
    local ns = env.ns
    ns.ShoppingList:Reset()
    ns.PriceProvider:BeginPass()
    ns.ShoppingList:Add(2589, 4, "a", "Карточка А")
    ns.ShoppingList:Add(2589, 6, "b", "Карточка Б")
    local lines = ns.ShoppingList:Lines()
    H.eq(#lines, 1, "одна позиция")
    H.eq(lines[1].qty, 10, "4 + 6 = 10")
    H.eq(#lines[1].uses, 2, "две причины")
end

-- Normalisation -------------------------------------------------------

H.suite("Нормализация: мягкое сжатие")
do
    local env = H.load()
    local U = env.ns.Util
    H.near(U.soft(0, 100), 0, 0.0001, "ноль в ноль")
    H.near(U.soft(100, 100), 0.5, 0.0001, "на масштабе - половина")
    H.near(U.soft(300, 100), 0.75, 0.0001, "трёхкратно - 0.75")
    H.ok(U.soft(1e9, 100) < 1, "никогда не достигает единицы")
    H.ok(U.soft(-5, 100) == 0, "отрицательное обрезается в ноль")
    H.ok(U.soft(50, 100) < U.soft(60, 100), "монотонно растёт")
end

H.suite("Нормализация: масштаб привязан к кошельку игрока")
do
    local poor = world({ money = 2000 })
    local rich = world({ money = 2000000 })
    local sPoor = poor.ns.ActionEngine:Scales(poor.ns.CharacterScanner:Scan())
    local sRich = rich.ns.ActionEngine:Scales(rich.ns.CharacterScanner:Scan())
    H.ok(sRich.profit > sPoor.profit, "для богатого планка прибыли выше")
    H.ok(sRich.spend > sPoor.spend, "и планка траты тоже")
    -- 1 gold of profit should matter a lot to the poor character.
    local U = poor.ns.Util
    H.ok(U.soft(10000, sPoor.profit) > 0.7, "1з для бедного - заметно")
    H.ok(U.soft(10000, sRich.profit) < 0.1, "1з для богатого - шум")
end

H.suite("Ранжирование: достоверность влияет, но не отменяет")
do
    local env = world()
    local ns = env.ns
    local Engine = ns.ActionEngine
    local weights = ns.PROFILE_WEIGHTS.POWER
    local good = { axes = { power = 0.5, skill = 0, profit = 0, spend = 0, ready = 1 },
                   conf = ns.CONF.EXACT }
    local guessed = { axes = { power = 0.5, skill = 0, profit = 0, spend = 0, ready = 1 },
                      conf = ns.CONF.UNKNOWN }
    Engine:Score(good, weights)
    Engine:Score(guessed, weights)
    H.ok(good.score > guessed.score, "точные данные ранжируются выше")
    H.ok(guessed.score > good.score * 0.5, "но догадка не обнуляется полностью")
end

H.suite("Ранжирование: стабильно между пересчётами")
do
    local env = world({ enchantMats = 3 })
    local ns = env.ns
    local first = {}
    for _, card in ipairs(H.build(env)) do first[#first + 1] = card.key end
    local second = {}
    for _, card in ipairs(H.build(env)) do second[#second + 1] = card.key end
    H.eq(table.concat(first, "|"), table.concat(second, "|"),
        "одинаковые входные данные дают одинаковый порядок")
end

H.suite("Скрытие карточек")
do
    local env = world({ enchantMats = 3 })
    local ns = env.ns
    local cards = H.build(env)
    local target
    for _, card in ipairs(cards) do
        if not card.pinTop then target = card; break end
    end
    H.ok(target ~= nil, "есть что скрыть")
    ns.Config:Dismiss(target.key, env.Api:ServerTime(), 86400)
    local after = H.build(env)
    local stillThere = false
    for _, card in ipairs(after) do
        if card.key == target.key then stillThere = true end
    end
    H.eq(stillThere, false, "скрытая карточка не возвращается")

    -- And it comes back once the dismissal expires.
    H.serverTime = H.serverTime + 90000
    local later = H.build(env)
    local back = false
    for _, card in ipairs(later) do
        if card.key == target.key then back = true end
    end
    H.ok(back, "через сутки карточка возвращается")
end

H.suite("Отслеживаемые предметы для истории цен")
do
    local env = world()
    local ns = env.ns
    H.build(env)
    local tracked = ns.ActionEngine:TrackedItems()
    H.ok(tracked[2589], "реагент отслеживается")
    H.ok(tracked[14047], "реагент из второго рецепта отслеживается")
    H.ok(tracked[101], "результат крафта отслеживается")
    H.ok(tracked[9000], "то, что лежит в сумках, отслеживается")
end

H.suite("История цен: один слепок в сутки")
do
    local env = world()
    local ns = env.ns
    H.build(env)
    local ok, count = ns.PriceProvider:QueueDailySnapshot(ns.ActionEngine:TrackedItems())
    H.ok(ok, "первый слепок за сутки разрешён")
    while ns.PriceProvider:StepDailySnapshot(1000) do end
    local meta = ns.Config:PriceHistoryMeta()
    H.ok((meta.items or 0) > 0, "что-то записано (" .. tostring(meta.items) .. ")")
    H.eq(meta.days, 1, "один день")

    local again = ns.PriceProvider:QueueDailySnapshot(ns.ActionEngine:TrackedItems())
    H.eq(again, false, "повторный слепок в тот же день не делается")

    -- Next day: a new entry per item.
    H.serverTime = H.serverTime + 86400
    local ok2 = ns.PriceProvider:QueueDailySnapshot(ns.ActionEngine:TrackedItems())
    H.ok(ok2, "на следующий день слепок снова разрешён")
    while ns.PriceProvider:StepDailySnapshot(1000) do end
    H.eq(ns.Config:PriceHistoryMeta().days, 2, "два дня в истории")
    local hist = ns.Config:PriceHistoryFor(2589)
    H.eq(ns.Util.count(hist), 2, "у предмета две точки истории")
end

H.suite("История цен: без Auctionator не пишется")
do
    local env = world({ auctionator = false })
    local ns = env.ns
    H.build(env)
    local ok, reason = ns.PriceProvider:QueueDailySnapshot(ns.ActionEngine:TrackedItems())
    H.eq(ok, false, "слепок не делается")
    H.eq(reason, "no-auctionator", "и причина названа")
end

end
