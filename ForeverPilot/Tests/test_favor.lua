-- ForeverPilot / Tests/test_favor.lua
--
-- БЛАГОСКЛОННОСТЬ ТОРГОВЦА: ГЕЙТ ПО НАВЫКУ, А НЕ ПО УРОВНЮ.
--
-- Это самый полезный вывод про этого персонажа, и сам он его не сделает: в игре
-- нигде не написано, что рецепты за Merchant's Favor требуют НАВЫКА, а не
-- уровня. У него навык 225 при уровне 26 - значит ему доступно то, за чем
-- остальные приходят к 35.
--
-- Набор держит четыре контракта:
--   1. доступность решается навыком, и уровень персонажа на неё не влияет;
--   2. «носится прямо сейчас» решается уровнем ПРЕДМЕТА из данных, а не словами;
--   3. то, что у игрока уже есть, покупать не советуется (на живых данных
--      первая же карточка предлагала паттерн посоха, лежавшего в сумке);
--   4. про школу магии ветка не заявляет ничего - она показывает цифры.
local H = ...

return function()

local function favEnv(opts)
    opts = opts or {}
    local env = H.load()
    local ns = env.ns
    env.player.level = opts.level or 26
    env.money = 58052

    -- Жемчужные сапоги: порог навыка 60, требуют 25 уровень предмета.
    H.item(env, 253897, { name = "Жемчужные сапоги", equipLoc = "INVTYPE_FEET",
        reqLevel = 25, classID = 4, subclassID = 1, quality = 2, sellPrice = 400 })
    env.foreignItemStats[253897] = { sta = 6, spArcane = 7 }
    env.foreignItemRecords[253897] = { id = 253897, inv = 8, ilvl = 35, req = 25,
        quality = 2, class = 4, subclass = 1, stats = { sta = 6, spArcane = 7 } }
    -- Мерцающий посох: порог навыка 140 по чарам, требует 30 уровень.
    H.item(env, 249392, { name = "Мерцающий посох", equipLoc = "INVTYPE_2HWEAPON",
        reqLevel = 30, classID = 2, subclassID = 10, quality = 2, sellPrice = 900 })
    env.foreignItemStats[249392] = { int = 10, spArcane = 14 }
    env.foreignItemRecords[249392] = { id = 249392, inv = 17, ilvl = 40, req = 30,
        quality = 2, class = 2, subclass = 10, stats = { int = 10, spArcane = 14 } }
    env.itemDBMirror = false

    env.professions[#env.professions + 1] = {
        name = "Портняжное дело", skill = opts.tailoring or 225,
        max = 225, maxKnown = true, skillTrusted = true, skillLineID = 197,
    }
    env.professions[#env.professions + 1] = {
        name = "Наложение чар", skill = opts.enchanting or 225,
        max = 225, maxKnown = true, skillTrusted = true, skillLineID = 333,
    }
    ns.RecipeBook:Store("Портняжное дело", {}, "own", ns.CONF.EXACT, H.serverTime)
    ns.RecipeBook:Store("Наложение чар", {}, "own", ns.CONF.EXACT, H.serverTime)
    ns.RecipeBook:Reindex()
    H.itemsChanged(env)
    return env
end

local function findFavor(cards, ns, titlePart)
    for _, c in ipairs(cards) do
        if c.kind == ns.KIND.FAVOR
           and (not titlePart or ns.Util.contains(c.title, titlePart)) then
            return c
        end
    end
    return nil
end

H.suite("Благосклонность: данные на месте")
do
    local env = favEnv()
    local ns = env.ns
    H.ok(ns.Horizon ~= nil, "Data/Horizon.lua загружен")
    H.ok(ns.Favor ~= nil, "модуль Благосклонности есть")
    if ns.Horizon then
        H.ok(ns.Horizon.MF_FIRST_BUYS_ARCANE ~= nil
             and #ns.Horizon.MF_FIRST_BUYS_ARCANE > 0,
            "список первых покупок есть: " .. #ns.Horizon.MF_FIRST_BUYS_ARCANE)
        H.ok(ns.Horizon.MF_CRATES ~= nil, "ящики есть")
        local n = 0
        for _ in pairs(ns.Horizon.MF_CRATES) do n = n + 1 end
        H.eq(n, 26, "и их 26, как в отчёте")
        H.eq(ns.Horizon.CONFIDENCE.MF_CRATES, "WEB",
            "и помечены как данные с сайта, а не из клиента")
    end
end

H.suite("Благосклонность: доступность решает НАВЫК, а не уровень")
do
    -- 26 уровень, навык 225: всё должно быть доступно.
    local low = favEnv { level = 26 }
    local plan = low.ns.Favor:Plan(low.ns.CharacterScanner:Scan())
    H.ok(plan ~= nil, "план построен")
    if plan then
        local n = 0
        for _, d in ipairs(plan.items) do
            if d.affordableBySkill then n = n + 1 end
        end
        H.eq(n, #plan.items,
            "на 26 уровне доступно ВСЁ (" .. n .. " из " .. #plan.items
            .. "): пороги у этих покупок по навыку")
    end

    -- Тот же навык, 60 уровень: доступность не изменилась.
    local high = favEnv { level = 60 }
    local plan2 = high.ns.Favor:Plan(high.ns.CharacterScanner:Scan())
    local n2 = 0
    for _, d in ipairs(plan2.items) do
        if d.affordableBySkill then n2 = n2 + 1 end
    end
    H.eq(n2, #plan2.items, "на 60 уровне столько же: уровень тут ни при чём")

    -- А вот низкий НАВЫК доступность срезает.
    local weak = favEnv { tailoring = 50, enchanting = 50, level = 60 }
    local plan3 = weak.ns.Favor:Plan(weak.ns.CharacterScanner:Scan())
    local n3 = 0
    for _, d in ipairs(plan3.items) do
        if d.affordableBySkill then n3 = n3 + 1 end
    end
    H.ok(n3 < #plan3.items,
        "при навыке 50 доступно меньше (" .. n3 .. " из " .. #plan3.items
        .. ") — значит гейт и правда по навыку")
end

H.suite("Благосклонность: «носится сейчас» проверяется по данным предмета")
do
    local env = favEnv { level = 26 }
    local ns = env.ns
    local plan = ns.Favor:Plan(ns.CharacterScanner:Scan())
    local boots, staff
    for _, d in ipairs(plan.items) do
        if d.outItemID == 253897 then boots = d end
        if d.outItemID == 249392 then staff = d end
    end
    H.ok(boots ~= nil, "сапоги в плане есть")
    if boots then
        H.eq(boots.reqLevel, 25, "их требование уровня прочитано из данных")
        H.eq(boots.wearableNow, true, "на 26 уровне носятся")
        H.eq(boots.slot, "FEET", "и слот определён")
    end
    H.ok(staff ~= nil, "посох в плане есть")
    if staff then
        H.eq(staff.reqLevel, 30, "его требование — 30 уровень")
        H.eq(staff.wearableNow, false,
            "и на 26 он НЕ носится, хотя рецепт доступен уже сейчас")
    end
end

H.suite("Благосклонность: про школу не заявляется — показываются цифры")
do
    local env = favEnv()
    local ns = env.ns
    local plan = ns.Favor:Plan(ns.CharacterScanner:Scan())
    local boots
    for _, d in ipairs(plan.items) do
        if d.outItemID == 253897 then boots = d end
    end
    H.ok(boots ~= nil, "сапоги есть")
    if boots then
        H.ok(boots.statText ~= nil, "характеристики собраны: " .. tostring(boots.statText))
        H.ok(ns.Util.contains(boots.statText, "7"),
            "и это ЦИФРЫ, а не ярлык «аркановый набор»")
        H.eq(ns.Util.contains(boots.statText, "жемчуж"), false,
            "слова про жемчужную линию в характеристиках нет")
        H.ok(boots.score ~= nil and boots.score > 0,
            "и польза по весам персонажа посчитана: " .. tostring(boots.score))
    end
end

-- =====================================================================
-- ШКОЛА МАГИИ: ОТБОР, А НЕ ТОЛЬКО ПОКАЗ ЦИФР
-- =====================================================================
--
-- Справочник H.MF_FIRST_BUYS_ARCANE собран по одному семейству - жемчужному,
-- то есть по тайной магии. Фильтр шёл только по линии навыка, и
-- чернокнижник-портняжник получал полный набор тайной магии, которой не
-- кастует. Цифры рядом стояли верные, а отбор - нет: это та же ошибка, из-за
-- которой веса однажды считали «лечение» пользой, и игрок потратил материалы.
--
-- Отбор теперь идёт по ЧИСЛАМ: школьный урон предмета против веса этого
-- персонажа. Вес ноль - «ему это не даёт ничего», и такая покупка в план не
-- попадает. Названия школ и заученных семейств в проверке нет.

H.suite("Школа за Благосклонность: чернокнижнику не предлагают тайную магию")
do
    local env = favEnv()
    local ns = env.ns
    -- Тот же портняжник с тем же навыком - меняется только класс.
    env.player.classFile = "WARLOCK"
    env.player.className = "Чернокнижник"
    env.spec = nil
    local snap = ns.CharacterScanner:Scan()
    H.eq(snap.weightSetKey, "CASTER_SHADOW", "профиль чернокнижника: тень")
    H.eq(ns.StatWeights:SchoolCertainty(snap.weights), "known",
        "и школа у этого профиля известна — по числам, а не по названию набора")

    local plan, why, detail = ns.Favor:Plan(snap)
    -- В стенде у чернокнижника есть и чары: посох с общей силой магии ему
    -- подходит, а жемчужные вещи - нет.
    local arcane, generic = 0, 0
    for _, d in ipairs((plan and plan.items) or {}) do
        if d.schoolOffProfile then arcane = arcane + 1 end
        if (d.schoolAmount or 0) == 0 then generic = generic + 1 end
    end
    H.eq(arcane, 0, "в плане нет ни одной покупки с чужой школой")
    H.ok(plan == nil or #(plan.offSchool or {}) > 0,
        "а отложенное названо: " .. tostring(plan and #(plan.offSchool or {}) or why))
    if plan then
        for _, d in ipairs(plan.offSchool or {}) do
            H.eq(d.schoolValue, 0,
                "отложено «" .. tostring(d.name) .. "»: по весам стоит ноль")
            H.ok((d.schoolAmount or 0) > 0,
                "и отложено именно из-за школьного урона: "
                .. tostring(d.schoolAmount))
        end
        H.ok((plan.offSchoolFavor or 0) > 0,
            "сколько Favor это было — посчитано: " .. tostring(plan.offSchoolFavor))
        H.eq(plan.schoolCertainty, "known", "школа персонажа известна")
    end
    H.ok(detail == nil or detail.count > 0, "а когда плана нет — сказано, сколько отложено")
end

H.suite("Школа за Благосклонность: отложенное по школе не выдаётся за нехватку навыка")
do
    -- Низкий навык И чужая школа одновременно. Если сказать только про навык,
    -- игрок пойдёт качать навык - а шесть позиций отложены не из-за него.
    local env = favEnv { tailoring = 1, enchanting = 1 }
    local ns = env.ns
    env.player.classFile = "WARLOCK"
    env.player.className = "Чернокнижник"
    env.spec = nil
    H.rescan(env)
    H.build(env)
    local note = ns.ActionEngine.branchNote and ns.ActionEngine.branchNote.favor
    H.ok(type(note) == "string", "ветка молчит и объясняет почему: " .. tostring(note))
    if type(note) == "string" then
        H.ok(ns.Util.contains(note, "не из-за навыка"),
            "сказано, что часть отложена НЕ из-за навыка")
        H.ok(ns.Util.contains(note, "стоит ноль"),
            "и названа настоящая причина — школьный урон по весам стоит ноль")
    end
end

H.suite("Школа за Благосклонность: магу-аркану набор по-прежнему предлагается")
do
    -- Контрольный случай. Проверка, которая просто всё выбрасывает, зелёная и
    -- бесполезная: тому, кто эту школу кастует, набор нужен.
    local env = favEnv()
    local ns = env.ns
    env.spec = "Тайная магия"
    local snap = ns.CharacterScanner:Scan()
    H.eq(snap.weightSetKey, "CASTER_ARCANE", "профиль мага-аркана")
    local plan = ns.Favor:Plan(snap)
    H.ok(plan ~= nil, "план построен")
    if plan then
        H.eq(#(plan.offSchool or {}), 0, "ничего не отложено")
        local withSchool = 0
        for _, d in ipairs(plan.items) do
            if (d.schoolAmount or 0) > 0 then withSchool = withSchool + 1 end
        end
        H.ok(withSchool > 0,
            "и школьные вещи в плане остались: " .. withSchool)
        H.eq(ns.Favor:SchoolText(plan), nil,
            "про школу на карточке ничего не написано — писать нечего")
    end
end

H.suite("Школа за Благосклонность: школа неизвестна — так и сказано на карточке")
do
    -- Школьно-нейтральный профиль: все школы весят одинаково и не ноль. Это и
    -- есть «школу я не определил», и карточка обязана это сказать, а не делать
    -- вид, что определила.
    local env = favEnv()
    local ns = env.ns
    env.spec = nil
    env.equipped = {}
    local snap = ns.CharacterScanner:Scan()
    H.eq(snap.weightSetKey, "CASTER_DPS", "остался школьно-нейтральный набор")
    H.eq(ns.StatWeights:SchoolCertainty(snap.weights), "unknown",
        "и по числам это «школа неизвестна», а не «школа есть»")

    local plan = ns.Favor:Plan(snap)
    H.ok(plan ~= nil, "план построен — нейтральный набор школьные вещи не обесценивает")
    if plan then
        H.eq(#(plan.offSchool or {}), 0, "ничего не отложено: все школы весят одинаково")
        local text = ns.Favor:SchoolText(plan)
        H.ok(text ~= nil and ns.Util.contains(text, "не определил"),
            "и сказано, что школу я не определил: " .. tostring(text))
    end

    H.rescan(env)
    local cards = H.build(env)
    local c = findFavor(cards, ns, "Благосклонность торговца")
    H.ok(c ~= nil, "сводная карточка построена")
    if c then
        H.ok(ns.Util.contains(c.why, "Школу вашего персонажа я не определил"),
            "и на самой карточке это написано: " .. ns.Util.truncate(c.why, 260))
    end
end

H.suite("Школа за Благосклонность: цифры школы считаются, а не угадываются")
do
    local env = favEnv()
    local ns = env.ns
    local SW = ns.StatWeights
    local S = ns.STAT
    local stats = { [S.SPELLDMG_ARCANE] = 11, [S.STA] = 10, [S.ARMOR] = 35 }
    local amount, value, rows = SW:SchoolValue(stats, SW:Set("CASTER_ARCANE"))
    H.eq(amount, 11, "школьного урона на предмете: 11")
    H.near(value, 11 * 1.50, 0.001, "магу-аркану он стоит 16,5")
    H.eq(#rows, 1, "и перечислено по школам: одна строка")
    local amount2, value2 = SW:SchoolValue(stats, SW:Set("CASTER_SHADOW"))
    H.eq(amount2, 11, "тот же предмет, те же 11")
    H.eq(value2, 0, "а чернокнижнику он стоит ровно ноль")
    local amount3, value3 = SW:SchoolValue({ [S.STA] = 10 }, SW:Set("CASTER_SHADOW"))
    H.eq(amount3, 0, "на вещи без школьного урона школы нет")
    H.eq(value3, 0, "и стоит она ноль — это не «чужая школа», а «школы нет»")

    H.eq(SW:SchoolCertainty(SW:Set("CASTER_ARCANE")), "known", "аркан: школа известна")
    H.eq(SW:SchoolCertainty(SW:Set("CASTER_FIRE")), "known", "огонь: школа известна")
    H.eq(SW:SchoolCertainty(SW:Set("CASTER_DPS")), "unknown", "нейтральный: неизвестна")
    H.eq(SW:SchoolCertainty(SW:Set("MELEE_DPS")), "none", "воину школа не нужна вовсе")
    H.eq(SW:SchoolCertainty(SW:Set("TANK")), "none", "танку тоже")
    H.eq(SW:SchoolCertainty(nil), "no-weights", "без весов — четвёртый ответ")
end

H.suite("Благосклонность: то, что уже есть, покупать не советуется")
do
    -- Ровно живой случай: посох лежит в сумке, а аддон советовал его паттерн.
    local env = favEnv { level = 60 }
    local ns = env.ns
    env.bags[249392] = 1
    H.itemsChanged(env)
    local snap = ns.CharacterScanner:Scan()
    local plan = ns.Favor:Plan(snap)
    local staff
    for _, d in ipairs(plan.items) do
        if d.outItemID == 249392 then staff = d end
    end
    H.ok(staff ~= nil, "посох в плане есть")
    if staff then
        H.eq(staff.ownedWhere, "bags", "и видно, что он в сумке")
        H.eq(staff.alreadyHave, true, "значит покупать не надо")
    end

    local cards = H.build(env)
    for _, c in ipairs(cards) do
        if c.kind == ns.KIND.FAVOR and c.favorBuy then
            H.ok(c.favorBuy.outItemID ~= 249392,
                "карточки «купить паттерн посоха» нет: он уже в сумке")
        end
    end
    local summary = findFavor(cards, ns, "Благосклонность торговца")
    H.ok(summary ~= nil, "сводная карточка есть")
    if summary then
        H.ok(ns.Util.contains(summary.why, "покупать не нужно"),
            "и она говорит, чего покупать не надо: "
            .. ns.Util.truncate(summary.why, 260))
        H.ok(ns.Util.contains(summary.why, "Favor, которые можно не тратить"),
            "и сколько Favor это экономит")
    end
end

H.suite("Благосклонность: выученный рецепт тоже считается «уже есть»")
do
    local env = favEnv { level = 60 }
    local ns = env.ns
    -- Рецепт сапог выучен: паттерн за Favor больше не нужен.
    ns.RecipeBook:Store("Портняжное дело", {
        H.recipe { id = 9999, output = 253897, name = "Жемчужные сапоги",
                   learned = true, category = "Обувь", reagents = {} },
    }, "own", ns.CONF.EXACT, H.serverTime)
    ns.RecipeBook:Reindex()
    local plan = ns.Favor:Plan(ns.CharacterScanner:Scan())
    local boots
    for _, d in ipairs(plan.items) do
        if d.outItemID == 253897 then boots = d end
    end
    H.ok(boots ~= nil, "сапоги в плане есть")
    if boots then
        H.eq(boots.alreadyKnown, true, "рецепт опознан как выученный")
        H.eq(boots.alreadyHave, true, "и покупать его не надо")
    end
end

H.suite("Благосклонность: сводная карточка отвечает на все четыре вопроса")
do
    local env = favEnv()
    local ns = env.ns
    H.rescan(env)
    local cards = H.build(env)
    local c = findFavor(cards, ns, "Благосклонность торговца")
    H.ok(c ~= nil, "сводная карточка построена")
    if c then
        H.ok(ns.Util.contains(c.why, "по навыку профессии")
             and ns.Util.contains(c.why, "а не по уровню"),
            "1) сказано, что порог — навык, а не уровень: " .. ns.Util.truncate(c.why, 150))
        H.ok(ns.Util.contains(c.why, "Favor"), "2) сколько Favor нужно")
        H.ok(ns.Util.contains(c.why, "надевается уже сейчас")
             or ns.Util.contains(c.why, "носится"),
            "3) что носится прямо сейчас")
        H.ok(c.need ~= nil and c.need ~= "", "4) и как Favor заработать: " .. c.need)
        -- Оговорка обязательна: цена в Favor - слова сайта.
        H.ok(ns.Util.contains(c.why, "со слов"),
            "и честно сказано, что часть данных не из клиента")
        H.eq(c.conf, ns.CONF.ESTIMATE, "достоверность — оценка")
    end
end

H.suite("Благосклонность: ящики считаются из того, что в сумках")
do
    local env = favEnv()
    local ns = env.ns
    -- Ящик «Apprentice Textiles» закрывается 40 льняной ткани (2589).
    H.item(env, 2589, { name = "Льняная ткань", sellPrice = 50, stackCount = 20 })
    env.bags[2589] = 40
    H.itemsChanged(env)
    local snap = ns.CharacterScanner:Scan()
    local routes = ns.Favor:EarnRoutes(snap)
    local lin
    for _, r in ipairs(routes) do
        if r.itemID == 2589 then lin = r end
    end
    H.ok(lin ~= nil, "маршрут через льняную ткань найден")
    if lin then
        H.eq(lin.need, 40, "нужно 40")
        H.eq(lin.have, 40, "есть 40")
        H.eq(lin.ready, true, "значит можно сдавать")
        H.eq(lin.favor, 5, "и это 5 Favor по данным")
    end

    local favor, unknown, ready = ns.Favor:ReadyFavor(routes)
    H.ok(ready >= 1, "готовых ящиков: " .. ready)
    H.ok(favor >= 5, "суммарный Favor: " .. favor)
    H.ok(unknown >= 0, "и отдельно — ящики с неизвестной награой: " .. unknown)
end

H.suite("Благосклонность: неизвестная награда не складывается с известной")
do
    -- У ящиков Expert и Artisan favor = nil: источник не знает. Складывать nil
    -- с числами нельзя, и считать их нулём - тоже: это «неизвестно», а не «0».
    local env = favEnv()
    local ns = env.ns
    local routes = {
        { crateID = 1, ready = true, favor = 10 },
        { crateID = 2, ready = true, favor = nil },
        { crateID = 3, ready = true, favor = 20 },
    }
    local favor, unknown, ready = ns.Favor:ReadyFavor(routes)
    H.eq(favor, 30, "сложены только известные: 10 + 20")
    H.eq(unknown, 1, "и один ящик посчитан как неизвестный")
    H.eq(ready, 3, "а готовых всё равно три")
end

H.suite("Благосклонность: один ящик не считается дважды")
do
    local env = favEnv()
    local ns = env.ns
    -- Один ящик закрывается ЛЮБЫМ ОДНИМ набором: если у игрока есть материал
    -- на два набора одного ящика, Favor он получит один раз.
    local routes = {
        { crateID = 248684, ready = true, favor = 5 },
        { crateID = 248684, ready = true, favor = 5 },
    }
    local favor, _, ready = ns.Favor:ReadyFavor(routes)
    H.eq(favor, 5, "Favor посчитан один раз")
    H.eq(ready, 1, "и ящик один")
end

H.suite("Благосклонность: 97 реагентов из Horizon попали в слепки цен")
do
    local env = favEnv()
    local ns = env.ns
    H.rescan(env)
    local tracked = ns.ActionEngine:TrackedItems()
    local watch = ns.Horizon:WatchList()
    H.ok(#watch > 0, "список наблюдения в Horizon есть: " .. #watch)
    H.eq(ns.Horizon.PRICE_WATCH_COUNT, 97, "и в нём 97 позиций, как в отчёте")
    local missing = 0
    for _, itemID in ipairs(watch) do
        if not tracked[itemID] then missing = missing + 1 end
    end
    H.eq(missing, 0, "и все они попали в суточные слепки цен")
end

H.suite("Благосклонность: «уровень 0» значит «не требуется», а не «нулевой»")
do
    -- На настоящих данных у жемчужных вещей req = 0, и первая версия карточки
    -- писала «Предмет требует 0 уровень» - это читается как сбой, а не как
    -- «надеть можно сразу».
    local env = favEnv { level = 26 }
    local ns = env.ns
    env.items[253897].reqLevel = 0
    env.foreignItemRecords[253897].req = 0
    H.itemsChanged(env)
    H.rescan(env)
    local cards = H.build(env)
    local c
    for _, card in ipairs(cards) do
        if card.favorBuy and card.favorBuy.outItemID == 253897 then c = card end
    end
    H.ok(c ~= nil, "карточка про сапоги есть")
    if c then
        H.eq(ns.Util.contains(c.why, "требует 0 уровень"), false,
            "текста «требует 0 уровень» в карточке нет")
        H.ok(ns.Util.contains(c.why, "не нужен вовсе")
             or ns.Util.contains(c.why, "наденете сразу"),
            "вместо него сказано, что уровень не нужен: "
            .. ns.Util.truncate(c.why, 170))
    end
end

H.suite("Благосклонность: честные дыры перечислены в горизонте")
do
    local env = favEnv()
    local ns = env.ns
    H.rescan(env)
    local r = ns.Foresight:Collect(ns.CharacterScanner:Get(), 1000)
    local text = table.concat(r.notes or {}, " | ")
    H.ok(ns.Util.contains(text, "дыра в данных"),
        "дыры из Horizon.lua попали в пометки горизонта")
    H.ok(ns.Util.contains(text, "Salvager") or ns.Util.contains(text, "распыл"),
        "включая те, что аддон закрыть не может: "
        .. ns.Util.truncate(text, 200))
end

-- НОМЕР ЛИНИИ НАВЫКА: КЛИЕНТ ОТДАЁТ ЕГО ДВАЖДЫ И ПО-РАЗНОМУ ================
--
-- Это и было причиной, по которой в живой игре ветка молчала, а разведка данных
-- говорила обратное - и права была разведка.
--
-- Клиент Forever отдаёт одну профессию ДВА РАЗА, с ДВУМЯ РАЗНЫМИ номерами
-- линии навыка: список профессий (C_TradeSkillUI.GetAllProfessionTradeSkillLines)
-- даёт современные номера, окно навыков (C_SkillInfo) - классические. В живом
-- файле это видно прямо:
--
--   Кулинария        line=185   <- совпадают
--   Первая помощь    line=129   <- совпадают
--   Рыбная ловля     line=356   <- совпадают
--   Наложение чар    line=2940  <- а классический 333
--   Портняжное дело  line=2948  <- а классический 197
--
-- Данные аддона (Data/Horizon.lua, роли тренеров в Codex) размечены
-- КЛАССИЧЕСКИМИ номерами. Снимок персонажа оставлял после склейки дубликатов
-- один номер - современный, - и сверка «навык по линии 197» не находила ничего.
-- Навык выходил nil, доступность - nil, и ветка сообщала «навыка не хватает»
-- при навыке 225 против порога 60.
--
-- Подтверждение из того же файла: Codex спрашивали про тренеров пять раз, и
-- ровно ДВА запроса вернули пусто - trainer:2940 и trainer:2948.

local function dualLineEnv(opts)
    opts = opts or {}
    local env = favEnv(opts)
    local ns = env.ns
    -- Начисто: ниже профессии выкладываются ровно так, как их отдаёт живой
    -- клиент - по две записи на профессию.
    env.professions = {}
    local function pair_(name, modern, classic, skill)
        -- Запись из списка профессий: современный номер.
        env.professions[#env.professions + 1] = {
            name = name, skill = skill, max = 225, maxKnown = true,
            skillTrusted = true, skillLineID = modern, fromSkillWindow = false,
        }
        -- Запись из окна навыков: классический номер, то же имя.
        env.professions[#env.professions + 1] = {
            name = name, skill = skill, max = 225, maxKnown = true,
            skillTrusted = true, skillLineID = classic, fromSkillWindow = true,
        }
    end
    pair_("Портняжное дело", 2948, 197, opts.tailoring or 225)
    pair_("Наложение чар", 2940, 333, opts.enchanting or 225)
    return env
end

H.suite("Линия навыка: склейка дубликатов не теряет классический номер")
do
    local env = dualLineEnv()
    local ns = env.ns
    local snap = H.rescan(env)
    H.eq(#snap.professions, 2, "две профессии, а не четыре: дубликаты склеены")
    local byName = {}
    for _, p in ipairs(snap.professions) do byName[p.name] = p end

    local tailor = byName["Портняжное дело"]
    H.ok(tailor ~= nil, "портняжка в снимке есть")
    if tailor then
        H.ok(type(tailor.skillLineIDs) == "table",
            "все номера линии, которые отдал клиент, сохранены")
        local seen = {}
        for _, id in ipairs(tailor.skillLineIDs or {}) do seen[id] = true end
        H.eq(seen[197], true, "классический номер 197 на месте")
        H.eq(seen[2948], true, "и современный 2948 тоже — ничего не выброшено")
        -- Главное поле: оно должно отдавать тот номер, которым размечены НАШИ
        -- данные, иначе сверка не найдёт ничего.
        H.eq(tonumber(tailor.skillLineID), 197,
            "а основной номер - тот, который знают наши данные")
    end
    local ench = byName["Наложение чар"]
    if ench then
        H.eq(tonumber(ench.skillLineID), 333,
            "у чар то же самое: 333, а не 2940")
    end
end

H.suite("Линия навыка: неизвестный номер не перебивает известный")
do
    -- Обратный случай: наши данные номера не знают вовсе. Тогда и сказать
    -- нечего, но выдумывать номер нельзя.
    local env = favEnv()
    local ns = env.ns
    env.professions = { {
        name = "Неведомое ремесло", skill = 100, max = 225, maxKnown = true,
        skillTrusted = true, skillLineID = 9999,
    } }
    local snap = H.rescan(env)
    local p = snap.professions[1]
    H.ok(p ~= nil, "профессия в снимке есть")
    if p then
        H.eq(tonumber(p.skillLineID), 9999,
            "номер клиента сохранён как есть — подменять его нечем")
        local line, from = ns.ForeverSource:ResolveSkillLine(p)
        H.eq(line, nil, "но наши данные его не признают")
        H.eq(from, nil, "и источника у него нет")
    end
end

H.suite("Благосклонность: при живом наборе номеров покупки находятся")
do
    local env = dualLineEnv()
    local ns = env.ns
    H.rescan(env)
    local plan = ns.Favor:Plan(ns.CharacterScanner:Get())
    H.ok(plan ~= nil, "план покупок построен")
    if plan then
        local affordable = 0
        for _, d in ipairs(plan.items) do
            if d.affordableBySkill then affordable = affordable + 1 end
        end
        H.ok(affordable > 0,
            "и навыка хватает хотя бы на одну покупку: " .. affordable)
        H.eq(affordable, #plan.items,
            "при навыке 225 против порогов 60..140 хватает на все: "
            .. affordable .. " из " .. #plan.items)
    end
    local cards = H.build(env)
    local c = findFavor(cards, ns)
    H.ok(c ~= nil, "и карточка за Благосклонность на экране есть")
    H.eq(ns.ActionEngine.branchNote.favor, nil,
        "ветка не отговаривается нехваткой навыка: "
        .. tostring(ns.ActionEngine.branchNote.favor))
end

H.suite("Благосклонность: номер линии не прочитан — так и сказано, а не «навыка мало»")
do
    -- Навык у персонажа есть и он высокий, но сопоставить его с порогом нечем:
    -- номер линии клиент не отдал, а имя профессии нашим данным незнакомо.
    -- Отвечать на это «навыка не хватает» - значит винить игрока в своей
    -- слепоте.
    local env = favEnv()
    local ns = env.ns
    env.professions = { {
        name = "Ремесло без имени", skill = 225, max = 225, maxKnown = true,
        skillTrusted = true,
    } }
    H.rescan(env)
    H.build(env)
    local note = ns.ActionEngine.branchNote.favor
    H.ok(note ~= nil, "причина молчания названа")
    if note then
        H.eq(ns.Util.contains(note, "навыка пока не хватает"), false,
            "и это НЕ «навыка не хватает»: " .. tostring(note))
        H.ok(ns.Util.contains(note, "номер") or ns.Util.contains(note, "сопоставить")
             or ns.Util.contains(note, "не прочитал"),
            "а честное «не смог сопоставить навык с порогом»: " .. tostring(note))
    end
end

H.suite("Благосклонность: навыка правда не хватает — текст про навык остаётся")
do
    -- И обратный случай, иначе предыдущая правка просто убрала бы настоящую
    -- причину вместе с ложной.
    local env = dualLineEnv { tailoring = 10, enchanting = 10 }
    local ns = env.ns
    H.rescan(env)
    H.build(env)
    local note = ns.ActionEngine.branchNote.favor
    H.ok(note ~= nil, "причина молчания названа")
    if note then
        H.ok(ns.Util.contains(note, "навыка пока не хватает"),
            "и она про навык, потому что навык и правда мал: " .. tostring(note))
    end
end

-- ГОРИЗОНТ НЕ ТЯНЕТ ЦЕНЫ НА ПОЛ-ИГРЫ ======================================
--
-- Слепок цен берёт цену по каждой позиции списка наблюдения ежедневно, а список
-- строился по ВСЕМ невыученным рецептам в книге. Книга растёт с каждым
-- открытым рангом, и граница тут нужна не из бережливости, а потому что без
-- неё список растёт без предела.

H.suite("Горизонт: список наблюдения ограничен и отрезан с хвоста")
do
    local env = favEnv()
    local ns = env.ns
    local FS = ns.Foresight
    H.ok(FS.MAX_TRACK_AHEAD ~= nil, "граница объявлена: "
        .. tostring(FS.MAX_TRACK_AHEAD))

    -- Книга с заведомо большим числом невыученных рецептов: по три реагента на
    -- рецепт, у разных рецептов разные реагенты.
    local recipes = {}
    for i = 1, 200 do
        recipes[#recipes + 1] = H.recipe {
            id = 500000 + i, output = 600000 + i, learned = false,
            name = "Будущее изделие " .. i, category = "Пояса",
            reagents = {
                -- Первый реагент общий для всех: он обязан попасть в список.
                { itemID = 700001, qty = 1 },
                { itemID = 700000 + i, qty = 2 },
            },
        }
    end
    ns.RecipeBook:Store("Портняжное дело", recipes, "own", ns.CONF.EXACT, H.serverTime)
    ns.RecipeBook:Reindex()
    FS.reagentSet = nil
    -- СНИМОК НУЖЕН, И ЭТО НЕ ФОРМАЛЬНОСТЬ. В список из Horizon идут реагенты
    -- ТОЛЬКО своих профессий (иначе алхимик ежедневно снимал цену на рунную
    -- ткань), а профессии живут в снимке персонажа. В игре Main сканирует до
    -- пересчёта; здесь это надо сделать явно, иначе проверка пойдёт по
    -- состоянию «профессий не знаю», какого при пересчёте не бывает.
    H.rescan(env)

    local set = FS:TrackItems()
    local n = 0
    for _ in pairs(set) do n = n + 1 end
    local watch = (ns.Horizon and ns.Horizon.WatchList) and #ns.Horizon:WatchList() or 0
    H.ok(n <= FS.MAX_TRACK_AHEAD + watch, string.format(
        "в списке %d позиций — не больше границы %d плюс выверенные %d из Horizon",
        n, FS.MAX_TRACK_AHEAD, watch))
    H.ok(FS.trackAheadTotal and FS.trackAheadTotal > FS.MAX_TRACK_AHEAD,
        "материалов впереди нашлось больше границы: "
        .. tostring(FS.trackAheadTotal))
    H.ok((FS.trackAheadDropped or 0) > 0,
        "и отрезанное посчитано, а не забыто: " .. tostring(FS.trackAheadDropped))
    -- ОТРЕЗАН ХВОСТ, А НЕ СЕРЕДИНА: самый нужный материал остался.
    H.eq(set[700001], true,
        "реагент, который нужен всем 200 рецептам, в списке есть")
    -- И выверенные позиции Horizon граница не съела.
    if ns.Horizon and ns.Horizon.WatchList then
        local missing = 0
        for _, itemID in ipairs(ns.Horizon:WatchList()) do
            if not set[itemID] then missing = missing + 1 end
        end
        H.eq(missing, 0, "и все " .. watch .. " позиций Horizon на месте")
    end
end

H.suite("Горизонт: сбор не отменяет границу списка наблюдения")
do
    -- Сбор горизонта кладёт своё множество в тот же кеш, и раньше оно было
    -- НЕограниченным: после первого же сбора граница переставала действовать.
    local env = favEnv()
    local ns = env.ns
    local FS = ns.Foresight
    local recipes = {}
    for i = 1, 200 do
        recipes[#recipes + 1] = H.recipe {
            id = 510000 + i, output = 610000 + i, learned = false,
            name = "Будущее изделие " .. i, category = "Пояса",
            reagents = { { itemID = 710001, qty = 1 }, { itemID = 710000 + i, qty = 2 } },
        }
    end
    ns.RecipeBook:Store("Портняжное дело", recipes, "own", ns.CONF.EXACT, H.serverTime)
    ns.RecipeBook:Reindex()
    FS.reagentSet = nil
    H.rescan(env)
    FS:Collect(ns.CharacterScanner:Get(), 1000)

    local set = FS:TrackItems()
    local n = 0
    for _ in pairs(set) do n = n + 1 end
    local watch = (ns.Horizon and ns.Horizon.WatchList) and #ns.Horizon:WatchList() or 0
    H.ok(n <= FS.MAX_TRACK_AHEAD + watch, string.format(
        "после сбора горизонта список всё ещё ограничен: %d <= %d + %d",
        n, FS.MAX_TRACK_AHEAD, watch))
    -- И выверенные позиции Horizon после сбора тоже на месте.
    if ns.Horizon and ns.Horizon.WatchList then
        local missing = 0
        for _, itemID in ipairs(ns.Horizon:WatchList()) do
            if not set[itemID] then missing = missing + 1 end
        end
        H.eq(missing, 0, "и выверенные позиции Horizon не потерялись")
    end
end

H.suite("Тренеры впереди: спрашиваем Codex по тому номеру, который он знает")
do
    local env = dualLineEnv()
    local ns = env.ns
    -- Тренер портняжки в Codex размечен классическим номером.
    env.codexNpcs[2399] = {
        name = "Daryl Stack", roles = { "trainer:197" },
        spawns = { { map = 1424, x = 63.4, y = 20.8 } },
    }
    H.rescan(env)
    local r = ns.Foresight:Collect(ns.CharacterScanner:Get(), 1000)
    local found = false
    for _, t in ipairs((r.trainers or {}).items or {}) do
        if t.npcID == 2399 then found = true end
    end
    H.ok(found, "тренер по линии 197 найден, хотя клиент назвал линию 2948")
end

end
