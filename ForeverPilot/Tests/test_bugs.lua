-- ForeverPilot / Tests/test_bugs.lua
--
-- Defects found by reading the player's own diagnostics file after a live run,
-- not by reading the code. Each suite here reproduces one of them from the same
-- shape of data that produced it in game, so a regression brings the test back
-- rather than waiting for the next screenshot.
--
-- The run they came from: 12 cards, 0 errors, and four of the twelve were exact
-- duplicates of two other cards.
local H = ...

return function()

local function cardsByKind(cards, kind)
    local out = {}
    for _, c in ipairs(cards) do
        if c.kind == kind then out[#out + 1] = c end
    end
    return out
end

local function findCard(cards, key)
    for _, c in ipairs(cards) do
        if c.key == key then return c end
    end
    return nil
end

-- =====================================================================
-- BUG-13: the same recipe arrives under two profession names
-- =====================================================================
--
-- The recipe book is keyed by profession NAME. Our own cache stores the
-- localised name the client gave us ("Портняжное дело"); the foreign cache
-- stores the English one ("Tailoring"). Store() ranks sources so the better one
-- wins - but only when the key matches, and these two never do. So both buckets
-- survived, byProfession held ten entries for five professions, Iterate yielded
-- every recipe twice, and the Now tab showed "Льняные сапоги" twice with
-- identical scores down to the last digit.

local function twinSourceEnv()
    local env = H.load()
    local ns = env.ns

    H.item(env, 2569, { name = "Льняные сапоги", equipLoc = "INVTYPE_FEET",
        reqLevel = 10, classID = 4, subclassID = 1, sellPrice = 300 })
    H.item(env, 2320, { name = "Грубая нить", sellPrice = 2 })
    env.vendorPrices[2320] = 9
    env.prices[2569] = 20000
    env.bags[2320] = 10
    env.money = 224635

    local list = {
        H.recipe { id = 2386, output = 2569, outputQty = 1,
                   reagents = { { itemID = 2320, qty = 1 } },
                   name = "Льняные сапоги", diff = "trivial", category = "Обувь" },
    }
    -- Exactly what the two caches do in game: same recipe, two profession keys.
    env.professions[#env.professions + 1] = {
        name = "Портняжное дело", skill = 225, max = 225, skillTrusted = true,
    }
    ns.RecipeBook:Store("Портняжное дело", list, "stored", ns.CONF.CACHED, H.serverTime)
    ns.RecipeBook:Store("Tailoring", list, "foreign", ns.CONF.CACHED, H.serverTime)
    ns.RecipeBook:Reindex()
    return env
end

H.suite("BUG-13: одна профессия под двумя именами — один набор рецептов")
do
    local env = twinSourceEnv()
    local ns = env.ns

    local buckets = 0
    for _ in pairs(ns.RecipeBook.byProfession) do buckets = buckets + 1 end
    H.eq(buckets, 1, "в книге одна профессия, а не две под разными именами")

    local seen = ns.RecipeBook:Iterate(function(r) return r.id == 2386 end)
    H.eq(#seen, 1, "Iterate отдаёт рецепт один раз")
    H.eq(ns.RecipeBook:LearnedCount(), 1, "выученных рецептов посчитано один раз")

    -- The localised name is the one the player sees, so it must be the survivor.
    local bucket = ns.RecipeBook:Bucket("Портняжное дело")
    H.ok(bucket ~= nil, "по русскому имени профессия находится")
    H.ok(ns.RecipeBook.byProfession["Портняжное дело"] ~= nil,
        "уцелело русское имя, а не английское")
    H.ok(ns.RecipeBook:Bucket("Tailoring") ~= nil,
        "и по английскому имени та же профессия всё ещё находится")
end

H.suite("BUG-13: карточка «на продажу» не повторяется")
do
    local env = twinSourceEnv()
    local ns = env.ns
    local cards = H.build(env)

    local profit = cardsByKind(cards, ns.KIND.CRAFT_PROFIT)
    H.eq(#profit, 1, "ровно одна карточка на продажу, а не две одинаковых")

    -- And no two cards anywhere in the list may share a key.
    local byKey, dupes = {}, 0
    for _, c in ipairs(cards) do
        if byKey[c.key] then dupes = dupes + 1 end
        byKey[c.key] = true
    end
    H.eq(dupes, 0, "в списке нет двух карточек с одним ключом")
end

H.suite("BUG-13: защёлка на уровне движка, а не только книги")
do
    -- Even if some future branch hands the same action in twice, the list must
    -- not show it twice. The guard is on the action, not on the source key.
    local env = H.load()
    local ns = env.ns
    ns.ActionEngine.cards = {}
    ns.ActionEngine.hidden = {}
    ns.ActionEngine.dupes = nil

    local function card(key)
        return {
            key = key, kind = ns.KIND.CRAFT_PROFIT, title = "Тест",
            recipeID = 777, itemID = 42,
            benefit = "x", why = "y", need = "z", conf = ns.CONF.EXACT,
            action = { kind = "noop", label = "Понятно" },
        }
    end

    H.ok(ns.ActionEngine:Add(card("profit:777")) ~= nil, "первая карточка добавлена")
    H.eq(ns.ActionEngine:Add(card("profit:777")), nil, "вторая с тем же ключом отклонена")
    H.eq(ns.ActionEngine:Add(card("profit:777:другой-ключ")), nil,
        "и та же цель под другим ключом тоже отклонена")
    H.eq(#ns.ActionEngine.cards, 1, "в списке осталась одна")
    H.ok((ns.ActionEngine.dupes or 0) >= 2, "схлопывания посчитаны для диагностики")
end

-- =====================================================================
-- BUG-14: "ед. силы" reads as Strength
-- =====================================================================
--
-- The number is a weighted sum over the character's own stat weights - for an
-- arcane mage that is intellect, spell power and spirit. Calling it "силы" named
-- the one stat the mage has no use for, and the player read the card as advice
-- to stack Strength.

local function gearEnv()
    local env = H.load()
    local ns = env.ns

    H.item(env, 100, { name = "Старый капюшон", equipLoc = "INVTYPE_HEAD",
        reqLevel = 20, classID = 4, subclassID = 1, sellPrice = 100 })
    env.stats[100] = { ITEM_MOD_INTELLECT_SHORT = 4, ITEM_MOD_STAMINA_SHORT = 3 }
    env.equipped.HEAD = { itemID = 100 }

    H.item(env, 101, { name = "Хороший капюшон", equipLoc = "INVTYPE_HEAD",
        reqLevel = 25, classID = 4, subclassID = 1, sellPrice = 400 })
    env.stats[101] = { ITEM_MOD_INTELLECT_SHORT = 12, ITEM_MOD_STAMINA_SHORT = 9 }

    H.item(env, 200, { name = "Ткань", sellPrice = 10 })
    env.prices[200] = 50
    env.prices[101] = 3000
    env.money = 50000

    H.profession(env, "Портняжное дело", 225, 225, {
        H.recipe { id = 1, output = 101, reagents = { { itemID = 200, qty = 4 } },
                   name = "Хороший капюшон", diff = "optimal", category = "Капюшоны" },
    })
    return env
end

H.suite("BUG-14: прирост называется пользой, а не силой")
do
    local env = gearEnv()
    local ns = env.ns

    H.ok(type(ns.UNIT_BENEFIT) == "string" and ns.UNIT_BENEFIT ~= "",
        "единица измерения названа в одном месте: ns.UNIT_BENEFIT")
    H.ok(not ns.Util.contains(ns.UNIT_BENEFIT, "сил"),
        "и в этом названии нет слова «сила»")

    local cards = H.build(env)
    local gear = cardsByKind(cards, ns.KIND.CRAFT_GEAR)
    H.ok(#gear > 0, "карточка улучшения построена")

    local said = 0
    for _, c in ipairs(cards) do
        local text = table.concat({ c.title or "", c.benefit or "", c.why or "",
                                    c.need or "" }, " ")
        H.ok(not ns.Util.contains(text, "ед. силы"),
            "«" .. ns.Util.truncate(c.title, 34) .. "»: нет «ед. силы»")
        if ns.Util.contains(text, ns.UNIT_BENEFIT) then said = said + 1 end
    end
    H.ok(said > 0, "хотя бы одна карточка называет прирост в " .. ns.UNIT_BENEFIT)

    local g = gear[1]
    H.ok(ns.Util.contains(g.benefit, ns.UNIT_BENEFIT),
        "выгода подписана как «" .. ns.UNIT_BENEFIT .. "»: " .. tostring(g.benefit))
end

-- =====================================================================
-- BUG-14, вторая часть: «ед. пользы» — единица, которой не существует
-- =====================================================================
--
-- Игрок прочитал «+0 ед. пользы» и спросил, в чём это измеряется. Ответить
-- было нечем: «ед.» - сокращение из таблицы разработчика, а «пользы» -
-- название, которого нет ни в игре, ни в жизни. И в том же столбце рядом
-- стояли деньги («+11с 93м»), то есть один столбец говорил на двух языках, и
-- один из них был непонятен.
--
-- Теперь это БАЛЛ - то же слово, которым аддон объясняет себя в настройках
-- («мой условный счёт по этим весам»). Слово живое, поэтому склоняется, и
-- склонение здесь же проверяется: «2 балл» на экране - такая же чушь, как
-- «ед. пользы».

H.suite("BUG-14: единица называется словом и согласуется с числом")
do
    local env = H.load()
    local ns, U = env.ns, env.ns.Util

    H.eq(ns.UNIT_BENEFIT, "балл", "единица называется баллом")
    H.eq(ns.Util.contains(ns.UNIT_BENEFIT, "ед."), false,
        "и это не сокращение разработчика")
    -- МЁРТВОЕ ПОЛЕ УБРАНО. ns.UNIT_BENEFIT_SHORT = "ед." писалось в
    -- Core/Const.lua и не читалось ни одной строкой аддона: второе название
    -- того же числа, которого на экране никогда не было. Такое поле - готовая
    -- ловушка: следующий, кто его увидит, напишет им подпись.
    H.eq(ns.UNIT_BENEFIT_SHORT, nil, "короткой формы «ед.» больше нет вовсе")

    H.eq(U.benefit(1), "1 балл", "один балл")
    H.eq(U.benefit(2), "2 балла", "два балла")
    H.eq(U.benefit(4), "4 балла", "четыре балла")
    H.eq(U.benefit(5), "5 баллов", "пять баллов")
    H.eq(U.benefit(11), "11 баллов", "одиннадцать — особый случай")
    H.eq(U.benefit(21), "21 балл", "двадцать один")
    H.eq(U.benefit(0), "0 баллов", "ноль баллов (само число в советы не попадает)")
    H.eq(U.benefit(2.4), "2 балла", "дробь округляется: сравнивать по десятым нечего")
    H.eq(U.benefitDelta(3), "+3 балла", "в столбце выгоды — со знаком")
    H.eq(U.benefitDelta(-3), ns.GLYPH.MINUS .. "3 балла",
        "и минус берётся из набора значков, который клиент рисует")
    -- «За золотой» - скорость, а не количество: её округлять нельзя, и дробное
    -- число требует «балла» при любом значении.
    H.eq(U.benefitRate(3.5), "3,5 балла", "дробная скорость: с запятой и «балла»")
    H.eq(U.benefitRate(2), "2 балла", "целая — обычное согласование")
end

H.suite("BUG-14: «ед.» не возвращается ни в один текст")
do
    -- Правило на все тексты сразу, а не на одну карточку: сокращение
    -- запрещено после числа в любом виде.
    local env = gearEnv()
    local ns = env.ns
    local cards = H.build(env)
    for _, c in ipairs(cards) do
        local text = table.concat({ c.title or "", c.benefit or "", c.why or "",
                                    c.need or "" }, " ")
        H.eq(text:find("%d+%s*ед%."), nil,
            "«" .. ns.Util.truncate(c.title, 30) .. "»: нет «N ед.»")
        H.eq(ns.Util.contains(text, "ед. пользы"), false,
            "   и нет «ед. пользы»")
    end

    -- И в исходниках аддона этого сокращения тоже не осталось: иначе оно
    -- вернётся на экран следующей правкой.
    local D = assert(loadfile((H.ROOT or ".") .. "/Tests/dialect.lua"))()
    local files = assert(D.tocFiles(H.ROOT or "."))
    local offenders = {}
    for _, rel in ipairs(files) do
        local f = io.open((H.ROOT or ".") .. "/" .. rel, "r")
        if f then
            local n = 0
            for line in f:lines() do
                n = n + 1
                local code = line:gsub("%-%-.*$", "")
                if code:find("UNIT_BENEFIT_SHORT")
                    or code:find('"ед%. пользы"') then
                    offenders[#offenders + 1] = rel .. ":" .. n
                end
            end
            f:close()
        end
    end
    H.ok(#files >= 40, "файлов из .toc просмотрено: " .. #files)
    H.eq(#offenders, 0, "ни «ед. пользы», ни мёртвого поля в коде нет"
        .. ((#offenders > 0) and ("  <- " .. table.concat(offenders, "; ")) or ""))
end

-- =====================================================================
-- BUG-19: «улучшение на ноль» — порог пропускал размен
-- =====================================================================
--
-- ПРИСЛАНО СКРИНШОТОМ ИЗ ИГРЫ. Чернокнижник 14 уровня, профиль «Прокачка»,
-- вторая карточка из восемнадцати:
--
--     Скрафтить: Теневые очки                        +0 ед. пользы
--     Слот «Голова»: лучше, чем Зеленые тонированные очки, на 0 ед. пользы.
--     Но просадки: -8 выносливости, -1 духа, -4 брони.
--
-- Числа настоящие и проверяются ниже: надетые «Зеленые тонированные очки»
-- (4385) это sta8 spi7 armor35, «Теневые очки» (4373) - int5 spi6 armor31. По
-- весам чернокнижника-тени (int 1.00, sta 0.55, spi 0.25, armor 0.02) это
-- 7.12 против 6.85, то есть +0.27. Порог стоял на `gain > 0.01` - «любой плюс
-- сверх нуля», - а на экран число выводится целым, и получилось предложение
-- потратить материалы на вещь, которая не лучше ни на сколько и при этом хуже
-- по трём характеристикам.
--
-- Это НЕ ошибка в весах (её уже чинили, см. BUG-14 и школы) и не ошибка в
-- тексте: карточка честно написала «на 0». Ошибка в пороге: улучшением
-- называлось то, что аддон не может напечатать как улучшение.
--
-- Правило теперь одно на три ветки - крафт, «надеть своё» и развилку путей:
-- ns.MIN_BENEFIT_GAIN и U.isGain. Размен с нулевым итогом в список не попадает
-- вовсе, а причина пишется в воронку словами («even-trade»).

-- Ровно те две вещи со скриншота, на настоящих числах из базы предметов.
local function evenTradeEnv()
    local env = H.load()
    local ns = env.ns

    env.player.classFile = "WARLOCK"
    env.player.className = "Чернокнижник"
    env.player.level = 14

    -- Надето: «Зеленые тонированные очки» (4385).
    H.item(env, 4385, { name = "Зеленые тонированные очки", equipLoc = "INVTYPE_HEAD",
        reqLevel = 0, classID = 4, subclassID = 1, sellPrice = 2800 })
    env.stats[4385] = { ITEM_MOD_STAMINA_SHORT = 8, ITEM_MOD_SPIRIT_SHORT = 7,
                        RESISTANCE0_NAME = 35 }
    env.equipped.HEAD = { itemID = 4385 }

    -- Можно скрафтить: «Теневые очки» (4373).
    H.item(env, 4373, { name = "Теневые очки", equipLoc = "INVTYPE_HEAD",
        reqLevel = 0, classID = 4, subclassID = 1, sellPrice = 2800 })
    env.stats[4373] = { ITEM_MOD_INTELLECT_SHORT = 5, ITEM_MOD_SPIRIT_SHORT = 6,
                        RESISTANCE0_NAME = 31 }

    H.item(env, 2319, { name = "Средняя кожа", sellPrice = 40 })
    env.prices[2319] = 226
    env.prices[4373] = 1400
    env.bags[2319] = 10
    env.money = 468977

    H.profession(env, "Инженерное дело", 150, 150, {
        H.recipe { id = 3966, output = 4373, outputQty = 1,
                   reagents = { { itemID = 2319, qty = 4 } },
                   name = "Теневые очки", diff = "optimal", category = "Очки" },
    })
    return env
end

H.suite("BUG-19: размен с нулевым итогом не советуется")
do
    local env = evenTradeEnv()
    local ns = env.ns
    local U = ns.Util

    -- Сначала - что стенд воспроизводит именно тот случай: прирост есть, но
    -- он меньше половины балла. Без этого проверка ниже зелёная по случайности.
    local snap = ns.CharacterScanner:Scan()
    H.eq(snap.weightSetKey, "CASTER_SHADOW", "веса чернокнижника-тени")
    local worn = ns.GearAdvisor:ItemScore(4385, snap.weights)
    local cand = ns.GearAdvisor:ItemScore(4373, snap.weights)
    H.near(worn, 6.85, 0.01, "надетые «Зеленые тонированные очки»: 6.85 по весам")
    H.near(cand, 7.12, 0.01, "«Теневые очки»: 7.12 по весам")
    H.ok(cand > worn, "формально прирост есть: " .. string.format("%.2f", cand - worn))
    H.ok((cand - worn) < 0.5, "но меньше половины балла — на экране это ноль")

    local cards = H.build(env)

    -- И главное: такого совета в списке нет ни под каким видом.
    for _, c in ipairs(cards) do
        H.ok(c.itemID ~= 4373 or c.kind == ns.KIND.CRAFT_PROFIT,
            "«" .. tostring(c.title) .. "» (" .. tostring(ns.KIND_LABEL[c.kind])
            .. "): размен не выдан за улучшение")
    end
    H.eq(#cardsByKind(cards, ns.KIND.CRAFT_GEAR), 0,
        "ветка «скрафтить и надеть» промолчала")
    H.eq(#cardsByKind(cards, ns.KIND.PATHS), 0,
        "и развилка путей к той же вещи тоже")

    -- Причина не потерялась: она в воронке, словами.
    local f = ns.Diag:Init().funnels.gearUpgrades
    H.ok(f ~= nil, "воронка улучшений отчиталась")
    local drop = f and f.drops and f.drops["even-trade"]
    H.ok(drop ~= nil and drop.n > 0, "размен отсеян с названной причиной")
    H.ok(drop and U.contains(table.concat(drop.examples or {}, " "), "размен"),
        "и в причине сказано слово «размен»: "
        .. tostring(drop and (drop.examples or {})[1]))
end

H.suite("BUG-19: ни одна карточка не обещает «+0»")
do
    -- Правило общее, а не про одну вещь: любой совет, который измеряет пользу
    -- в баллах, обязан обещать хотя бы один балл. «+0» в столбце выгоды - это
    -- либо размен (его отсеивает порог), либо ошибка округления.
    local env = evenTradeEnv()
    local ns = env.ns
    local cards = H.build(env)
    for _, c in ipairs(cards) do
        if c.benefitKind == "power" and type(c.benefitValue) == "number" then
            H.ok(ns.Util.round(c.benefitValue) ~= 0,
                "«" .. tostring(c.title) .. "»: польза не ноль ("
                .. tostring(c.benefit) .. ")")
        end
        H.ok(not ns.Util.contains(tostring(c.benefit or ""),
                "+0 " .. ns.UNIT_BENEFIT),
            "«" .. tostring(c.title) .. "»: в выгоде нет «+0 "
            .. ns.UNIT_BENEFIT .. "»")
    end

    -- И у обычного улучшения порог ничего не сломал: карточка на месте.
    local good = gearEnv()
    local gcards = H.build(good)
    H.ok(#cardsByKind(gcards, good.ns.KIND.CRAFT_GEAR) > 0,
        "настоящее улучшение по-прежнему советуется")
end

H.suite("BUG-19: порог один на весь аддон")
do
    local env = H.load()
    local ns, U = env.ns, env.ns.Util
    H.ok(type(ns.MIN_BENEFIT_GAIN) == "number" and ns.MIN_BENEFIT_GAIN > 0,
        "порог назван числом в одном месте: ns.MIN_BENEFIT_GAIN")
    H.eq(U.isGain(nil), false, "нет сравнения — нет и улучшения")
    H.eq(U.isGain(0), false, "ноль не улучшение")
    H.eq(U.isGain(-5), false, "минус тем более")
    H.eq(U.isGain(0.27), false, "0.27 — это размен: на экране ноль")
    H.eq(U.isGain(0.5), true, "половина балла округляется в единицу — улучшение")
    H.eq(U.isGain(3), true, "и три балла, разумеется, тоже")
    -- Порог и округление обязаны быть согласованы: что проходит порог, то и
    -- печатается числом не меньше единицы.
    for _, v in ipairs({ 0.5, 0.51, 0.9, 1, 2.4, 17 }) do
        H.ok(U.round(v) >= 1, "прошло порог — печатается как " .. U.benefit(v))
    end
end

-- =====================================================================
-- BUG-15: the auction cut was claimed over a vendor price
-- =====================================================================
--
-- The profit card's text said "(сбор аукциона уже вычтен)" unconditionally,
-- while PriceProvider:Sell returns the vendor's offer whenever it beats the
-- market - and then no cut was taken off anything. Separately, the diagnostics
-- recorded priceSource from plan.shopping[1], which is the MATERIAL price, and
-- printed it next to the revenue figure. The pair "vendor / сбор вычтен" on one
-- card is what made this visible.

local function profitEnv(opts)
    opts = opts or {}
    local env = H.load()
    local ns = env.ns

    H.item(env, 300, { name = "Товар", sellPrice = opts.vendorSell or 10 })
    H.item(env, 301, { name = "Материал", sellPrice = 1 })
    env.vendorPrices[301] = 100
    env.bags[301] = 0
    if opts.auction then env.prices[300] = opts.auction end
    env.money = 500000

    H.profession(env, "Портняжное дело", 225, 225, {
        H.recipe { id = 50, output = 300, outputQty = 1,
                   reagents = { { itemID = 301, qty = 1 } },
                   name = "Товар", diff = "trivial", category = "Обувь" },
    })
    return env
end

H.suite("BUG-15: про сбор аукциона говорим только когда он правда вычтен")
do
    -- No auction price at all; the vendor pays well. Revenue is the vendor's
    -- offer, and the auction house has nothing to do with it.
    local env = profitEnv { vendorSell = 50000, auction = nil }
    local ns = env.ns
    local cards = H.build(env)
    local profit = cardsByKind(cards, ns.KIND.CRAFT_PROFIT)
    H.ok(#profit > 0, "карточка на продажу есть")
    local c = profit[1]
    H.ok(not ns.Util.contains(c.why, "сбор аукциона"),
        "выручка от торговца — про сбор аукциона не упомянуто: " .. tostring(c.why))
    H.ok(ns.Util.contains(c.why, "торговц"),
        "и прямо сказано, что платит торговец: " .. tostring(c.why))
end

H.suite("BUG-15: про сбор аукциона говорим, когда он вычтен")
do
    local env = profitEnv { vendorSell = 10, auction = 50000 }
    local ns = env.ns
    local cards = H.build(env)
    local profit = cardsByKind(cards, ns.KIND.CRAFT_PROFIT)
    H.ok(#profit > 0, "карточка на продажу есть")
    H.ok(ns.Util.contains(profit[1].why, "сбор аукциона"),
        "рыночная выручка — сбор назван: " .. tostring(profit[1].why))
end

H.suite("BUG-15: диагностика различает цену материалов и цену продажи")
do
    local env = profitEnv { vendorSell = 10, auction = 50000 }
    local ns = env.ns
    H.build(env)
    local s = ns.Diag:Init()

    local rec
    for _, c in ipairs(s.cards or {}) do
        if c.kind == ns.KIND.CRAFT_PROFIT then rec = c; break end
    end
    H.ok(rec ~= nil, "карточка записана в диагностику")
    if rec then
        H.ok(rec.matPriceSource ~= nil,
            "источник цены материалов записан: " .. tostring(rec.matPriceSource))
        H.ok(rec.revenueSource ~= nil,
            "источник выручки записан отдельно: " .. tostring(rec.revenueSource))
        H.ok(rec.revenueConf ~= nil, "и его достоверность тоже")
        H.eq(rec.priceSource, nil,
            "неоднозначного поля priceSource больше нет")
        -- The contradiction itself, as one assertion: a revenue figure whose
        -- source is the vendor must never be described with an auction cut.
        local cutMentioned = ns.Util.contains(rec.why or "", "сбор аукциона")
        local vendorRevenue = (rec.revenueSource == "vendor")
        H.ok(not (cutMentioned and vendorRevenue),
            "источник выручки и упоминание сбора не противоречат друг другу")
    end
end

-- =====================================================================
-- BUG-16: the enchant branch went silent while seven slots were done
-- =====================================================================
--
-- The player has every enchantable slot enchanted except the neck, and knows no
-- neck formula. That is good news, and the card said "Слоты без чар, формул
-- нет / нечего предложить" - which reads as a failure of the addon. The branch
-- note was worse: "формул 130, свободных слотов 1 - но ни одна формула не
-- подходит", where 130 was the duplicated count of 65.

local function enchantEnv()
    local env = H.load()
    local ns = env.ns

    H.item(env, 400, { name = "Одеяние", equipLoc = "INVTYPE_CHEST",
        reqLevel = 20, classID = 4, subclassID = 1 })
    H.item(env, 401, { name = "Ожерелье", equipLoc = "INVTYPE_NECK",
        reqLevel = 20, classID = 4, subclassID = 0 })
    H.item(env, 402, { name = "Наручи", equipLoc = "INVTYPE_WRIST",
        reqLevel = 20, classID = 4, subclassID = 1 })
    H.item(env, 410, { name = "Пыль", sellPrice = 100 })
    env.prices[410] = 500
    env.bags[410] = 20

    -- Chest and wrist are enchanted; the neck is bare.
    env.equipped.CHEST = { itemID = 400, enchantID = 843 }
    env.equipped.WRIST = { itemID = 402, enchantID = 8734 }
    env.equipped.NECK = { itemID = 401 }

    H.profession(env, "Наложение чар", 225, 225, {
        H.recipe { id = 601, reagents = { { itemID = 410, qty = 2 } },
                   name = "Чары для нагрудника: здоровье", category = "Чары для нагрудника" },
        H.recipe { id = 602, reagents = { { itemID = 410, qty = 2 } },
                   name = "Чары для наручей: интеллект", category = "Чары для наручей" },
        -- The five neck formulas exist on this realm and are NOT learned.
        H.recipe { id = 1249019, learned = false, reagents = { { itemID = 410, qty = 4 } },
                   name = "Чары для ожерелья: сила", category = "Чары для амулетов" },
        H.recipe { id = 1249057, learned = false, reagents = { { itemID = 410, qty = 4 } },
                   name = "Чары для ожерелья: сила заклинаний", category = "Чары для амулетов" },
    })
    return env
end

H.suite("BUG-16: ветка чар говорит, сколько слотов уже зачаровано")
do
    local env = enchantEnv()
    local ns = env.ns
    local cards = H.build(env)

    local card = findCard(cards, "ench:noformula")
    H.ok(card ~= nil, "карточка про слоты без формул есть")
    if card then
        H.ok(ns.Util.contains(card.why, "Шея") or ns.Util.contains(card.why, "шея"),
            "назван слот шеи: " .. tostring(card.why))
        -- The good news has to be in there: this is not a hole in the addon.
        H.ok(card.why:find("2") ~= nil,
            "сказано, сколько слотов уже зачаровано: " .. tostring(card.why))
        H.ok(not ns.Util.contains(card.benefit, "нечего предложить"),
            "выгода больше не читается как «аддон ничего не нашёл»: "
            .. tostring(card.benefit))
    end

    -- And the branch note must not quote a doubled formula count.
    local note = ns.ActionEngine.branchNote.enchant
    H.ok(note == nil or not ns.Util.contains(note or "", "130"),
        "в примечании ветки нет удвоенного числа формул")
end

H.suite("BUG-16: известно, что формулы на этот слот в игре есть")
do
    local env = enchantEnv()
    local ns = env.ns
    local cards = H.build(env)
    local card = findCard(cards, "ench:noformula")
    H.ok(card ~= nil, "карточка есть")
    if card then
        -- Two neck formulas sit in the book unlearned. Saying so turns "нечего
        -- предложить" into something the player can act on.
        local text = (card.why or "") .. " " .. (card.need or "")
        H.ok(ns.Util.contains(text, "не выучен") or ns.Util.contains(text, "выучить"),
            "сказано, что формулы существуют, но не выучены: " .. text)
    end
end

-- =====================================================================
-- BUG-17: "причина не указана — это дефект самой диагностики"
-- =====================================================================
--
-- The bank module reported out = 0 with seen = true: the player HAD opened the
-- bank and it was simply empty. No reason was supplied for the zero, so Diag
-- filled in its own placeholder and the file accused itself of a defect.

H.suite("BUG-17: у нуля всегда есть причина, даже когда банк просто пуст")
do
    local env = H.load()
    local ns = env.ns
    env.bank = {}          -- opened, and empty
    H.profession(env, "Портняжное дело", 225, 225, {})
    H.build(env)

    local m = ns.Diag:Init().modules.bank
    H.ok(m ~= nil, "модуль банка отчитался")
    H.eq(m.out, 0, "в банке ничего нет")
    H.eq(m.seen, true, "но банк мы видели")
    H.ok(m.reason ~= nil, "причина нуля указана")
    H.ok(not ns.Util.contains(m.reason or "", "дефект"),
        "и это не заглушка про дефект диагностики: " .. tostring(m.reason))
    H.ok(ns.Util.contains(m.reason or "", "пуст"),
        "сказано прямо: банк пуст — " .. tostring(m.reason))
    H.ok(m.reasonCode ~= nil, "и у причины есть машиночитаемый код: "
        .. tostring(m.reasonCode))
end

H.suite("BUG-17: ни один модуль не остаётся без кода причины при нуле")
do
    local env = H.load()
    local ns = env.ns
    H.build(env)
    local s = ns.Diag:Init()
    local nocode = {}
    for name, m in pairs(s.modules) do
        if (tonumber(m.out) or 0) == 0 and not m.reasonCode then
            nocode[#nocode + 1] = name
        end
    end
    table.sort(nocode)
    H.eq(#nocode, 0, "у всех нулей есть код причины"
        .. (#nocode > 0 and (": " .. table.concat(nocode, ", ")) or ""))
end

-- =====================================================================
-- BUG-18: a buy card shows a price with no source
-- =====================================================================

H.suite("BUG-18: у карточки покупки записан источник цены")
do
    local env = profitEnv { vendorSell = 10, auction = 50000 }
    local ns = env.ns
    local cards = H.build(env)

    local buy = cardsByKind(cards, ns.KIND.BUY)
    H.ok(#buy > 0, "карточка покупки построена")

    local s = ns.Diag:Init()
    local rec
    for _, c in ipairs(s.cards or {}) do
        if c.kind == ns.KIND.BUY then rec = c; break end
    end
    H.ok(rec ~= nil, "и записана в диагностику")
    if rec then
        H.ok(rec.matPriceSource ~= nil,
            "источник цены покупки записан: " .. tostring(rec.matPriceSource))
        H.ok(rec.matPriceConf ~= nil,
            "достоверность цены покупки записана: " .. tostring(rec.matPriceConf))
    end
end

end
