-- ForeverPilot / Tests/test_nonsense.lua
--
-- КОНКРЕТНАЯ ЧУШЬ, НАЙДЕННАЯ СПЛОШНОЙ ПРОВЕРКОЙ, - ПО ОДНОМУ НАБОРУ НА НАХОДКУ.
--
-- Tests/test_sense.lua ловит классы (склеенная фраза, крик, число без смысла).
-- Здесь - то, что правилом не выразить: утверждение, которое выглядит гладко и
-- при этом неправда. Каждый набор назван тем, что аддон говорил, и проверяет,
-- что он больше так не говорит - на том же входе, на котором говорил.
local H = ...
local S = assert(loadfile((H.ROOT or ".") .. "/Tests/uistub.lua"))()

return function()

local function said(env)
    local out = {}
    for _, line in ipairs(env.said or {}) do
        local plain = S.plain(line)
        out[#out + 1] = (plain:gsub("^ForeverPilot: ", ""))
    end
    return out
end

local function cardsOfKind(ns, kind)
    local out = {}
    for _, card in ipairs(ns.ActionEngine.cards or {}) do
        if card.kind == kind then out[#out + 1] = card end
    end
    return out
end

-- 1. «РАСПЫЛИТЬ: СЛИТОК ИСТИННОГО СЕРЕБРА» ---------------------------------
--
-- В игре аддон посоветовал купить слиток за 14с и распылить его «в среднем на
-- 65с». Слиток распылить нельзя: распыляются доспехи и оружие. Проверялось
-- только качество («зелёное и выше»), а зелёными бывают и ремесленные товары.

local function deWorld()
    local env = H.load()
    local ns = env.ns
    -- Продукты распыла с ценами.
    H.item(env, 10940, { name = "Странная пыль", sellPrice = 100 })
    H.item(env, 10998, { name = "Малая астральная эссенция", sellPrice = 300 })
    H.item(env, 10978, { name = "Мерцающий осколок", sellPrice = 2000 })
    env.prices[10940], env.prices[10998], env.prices[10978] = 2000, 4000, 30000
    H.profession(env, "Наложение чар", 225, 225, {
        H.recipe { id = 6101, name = "Чары для плаща: малое сопротивление",
                   category = "Плащ", diff = "trivial",
                   reagents = { { itemID = 10940, qty = 1 } } },
    })
    return env
end

H.suite("Чушь: «распылить слиток» — распыляются только доспехи и оружие")
do
    local env = deWorld()
    local ns = env.ns
    -- Зелёный слиток: качество 2, уровень предмета есть, класс 7 (ремесло).
    H.item(env, 6037, { name = "Слиток истинного серебра", quality = 2,
        itemLevel = 50, classID = 7, subclassID = 7, sellPrice = 1250 })
    -- Зелёный плащ: доспех, распыляется.
    H.item(env, 6001, { name = "Зелёный плащик", equipLoc = "INVTYPE_CLOAK",
        quality = 2, itemLevel = 25, classID = 4, subclassID = 1, sellPrice = 500 })
    -- Зелёный меч: оружие, распыляется.
    H.item(env, 6005, { name = "Зелёный меч", equipLoc = "INVTYPE_WEAPONMAINHAND",
        quality = 2, itemLevel = 25, classID = 2, subclassID = 7, sellPrice = 500 })
    -- Зелёная вещь, про которую неизвестно, что это вообще такое.
    H.item(env, 6006, { name = "Неизвестно что", quality = 2, itemLevel = 25, sellPrice = 10 })
    env.prices[6037], env.prices[6001], env.prices[6005], env.prices[6006] = 1474, 300, 300, 300
    env.bags[6037], env.bags[6001], env.bags[6005], env.bags[6006] = 1, 1, 1, 1
    H.itemsChanged(env)
    H.rescan(env)
    ns.PriceProvider:BeginPass()

    local bar, why = ns.Disenchant:Expectation(6037)
    H.eq(bar, nil, "для слитка ожидания от распыла нет")
    H.eq(why, "not-equipment", "причина названа: это не доспех и не оружие")

    H.ok(ns.Disenchant:Expectation(6001) ~= nil, "доспех распыляется, как и раньше")
    local sword = ns.Disenchant:Expectation(6005)
    H.ok(sword ~= nil, "оружие распыляется")
    H.eq(sword and sword.isWeapon, true, "и считается именно оружием")

    local unknown, whyUnknown = ns.Disenchant:Expectation(6006)
    H.eq(unknown, nil, "вещь неизвестного рода распылять не советуем")
    H.eq(whyUnknown, "no-class", "причина: неизвестно, что это за предмет")

    -- И до экрана слиток не доходит.
    H.build(env)
    local offenders = {}
    for _, card in ipairs(cardsOfKind(ns, ns.KIND.DISENCHANT)) do
        if card.itemID == 6037 or card.itemID == 6006 then
            offenders[#offenders + 1] = tostring(card.title)
        end
    end
    H.eq(#offenders, 0, "совета распылить слиток на экране нет"
        .. ((#offenders > 0) and ("  <- " .. table.concat(offenders, "; ")) or ""))
end

H.suite("Чушь: оговорки к распылу — целые фразы, без крика и без двух точек")
do
    local env = deWorld()
    local ns = env.ns
    H.item(env, 6001, { name = "Зелёный плащик", equipLoc = "INVTYPE_CLOAK",
        quality = 2, itemLevel = 25, classID = 4, subclassID = 1, sellPrice = 500 })
    env.prices[6001] = 300
    H.itemsChanged(env)
    H.rescan(env)
    ns.PriceProvider:BeginPass()
    local exp = ns.Disenchant:Expectation(6001)
    H.ok(exp ~= nil, "ожидание есть")
    local text = exp and ns.Disenchant:CaveatText(exp) or ""
    H.ok(text:find("%.%.") == nil, "двух точек подряд нет: " .. ns.Util.truncate(text, 80))
    H.ok(text:find("Classic", 1, true) ~= nil and text:find("Forever", 1, true) ~= nil,
        "названия Classic и Forever написаны как названия, с заглавной")
    H.ok(text:find("Arcane Salvager", 1, true) ~= nil, "Arcane Salvager — тоже")
    H.ok(text:find("ОЖИДАНИЕ", 1, true) == nil and text:find("ВЫШЕ", 1, true) == nil,
        "слов заглавными буквами нет")
    H.ok(text:find("%. [а-яё]") == nil or text:find("%. %l") == nil,
        "после точки фраза не начинается с маленькой латинской буквы")
end

H.suite("Чушь: причина молчания распыления — та, что была на самом деле")
do
    -- Все кандидаты отсеялись, потому что у них не прочитан уровень предмета.
    -- Ветка при этом говорила «ожидание ниже цены покупки» - хотя ни одного
    -- ожидания не посчитала.
    local env = deWorld()
    local ns = env.ns
    H.item(env, 6003, { name = "Загадка", quality = 2, classID = 4,
        equipLoc = "INVTYPE_CLOAK", sellPrice = 10 })
    env.bags[6003] = 1
    H.itemsChanged(env)
    H.rescan(env)
    ns.PriceProvider:BeginPass()
    local opps = ns.Disenchant:Opportunities(ns.CharacterScanner:Get())
    H.eq(#opps, 0, "возможностей нет")
    local reason = tostring(ns.Disenchant.lastReason)
    H.ok(reason:find("ожидание ниже цены", 1, true) == nil,
        "причина не говорит про «ожидание ниже цены»: его никто не считал — " .. reason)
    H.ok(reason:find("данн", 1, true) ~= nil,
        "причина говорит, что не хватило данных о предметах")
end

-- 2. «ПОТОЛОК УЖЕ ПОДНИМАЛСЯ (4 РАЗА): ПОСЛЕДНИЙ РАЗ 2026-11-15, 224 -> 225» ---
--
-- Карточка «Навык на пределе» говорила это о МАКСИМУМЕ навыка. Числа брались из
-- истории Mastercraft: history[персонаж][день].s[профессия] = { a, b }. Аддон
-- читал пару как { навык, максимум }. У Mastercraft (Data.lua, RecordHistory)
-- это { навык, каким он был увиден первым в этот день; каким - последним }:
--
--     if s then s[2] = p.skill else d.s[p.name] = { p.skill, p.skill } end
--
-- Оба числа - НАВЫК. «Потолок поднялся с 224 до 225» - это игрок докачал один
-- пункт. Максимума в этой записи нет вовсе, и про его историю аддон не знает
-- ничего; значит, и говорить о ней не должен.

-- Ровно те дни, что лежат в файле игрока (портняжное дело).
local TAILORING_DAYS = {
    ["2026-11-07"] = { 82, 84 },  ["2026-11-08"] = { 84, 93 },
    ["2026-11-09"] = { 93, 93 },  ["2026-11-13"] = { 93, 160 },
    ["2026-11-14"] = { 160, 224 }, ["2026-11-15"] = { 224, 225 },
    ["2026-11-16"] = { 225, 225 },
}

local function historyWorld()
    local env = S.load(H)
    S.populate(env, H)
    local days = {}
    for date, pair in pairs(TAILORING_DAYS) do
        days[date] = { s = { Tailoring = { pair[1], pair[2] } } }
    end
    env.foreignDB = {
        chars = { [env.player.guid] = { professions = {
            { name = "Tailoring", skill = 225, max = 225 },
            { name = "Enchanting", skill = 225, max = 225 },
        } } },
        history = { [env.player.guid] = days },
    }
    -- Оба навыка на пределе: только тогда карточка про предел и появляется.
    for _, prof in ipairs(env.professions) do prof.skill, prof.max = 225, 225 end
    H.build(env)
    return env
end

H.suite("Чушь: «потолок уже поднимался: 224 -> 225» — в истории Mastercraft записан навык, а не потолок")
do
    local env = historyWorld()
    local ns = env.ns
    local hist = ns.Api:MastercraftSkillHistory(env.player.guid, "Tailoring")
    H.ok(type(hist) == "table" and #hist == 7, "история прочитана: 7 дней")
    hist = hist or {}
    H.eq(hist[1] and hist[1].first, 82, "первое число дня — навык, каким он был увиден первым")
    H.eq(hist[1] and hist[1].last, 84, "второе — каким он был увиден последним")
    local sawMax = false
    for _, day in ipairs(hist) do
        if day.max ~= nil then sawMax = true end
    end
    H.eq(sawMax, false, "поля «максимум» в записи нет: его в истории не бывает")

    -- Доказательство прочтения на самих числах: последний навык одного дня -
    -- это первый навык следующего. У пары «навык, максимум» так не бывает.
    local chained, links = 0, 0
    for i = 2, #hist do
        links = links + 1
        if hist[i].first == hist[i - 1].last then chained = chained + 1 end
    end
    H.eq(chained, links, "дни сцеплены: вчерашнее второе число равно сегодняшнему первому ("
        .. chained .. " из " .. links .. ")")

    H.eq(ns.Api.SkillCapMoves, nil,
        "функции «подъёмы потолка» больше нет: считать их не из чего")
end

H.suite("Чушь: карточка «Навык на пределе» не рассказывает историю потолка")
do
    local env = historyWorld()
    local ns = env.ns
    local card
    for _, c in ipairs(ns.ActionEngine.cards or {}) do
        if c.cappedProfessions then card = c end
    end
    H.ok(card ~= nil, "карточка про предел навыка есть")
    local text = card and (tostring(card.title) .. " " .. tostring(card.why) .. " "
        .. tostring(card.need) .. " " .. tostring(card.benefit)) or ""
    H.ok(text:find("поднимался", 1, true) == nil, "не говорит, что потолок «уже поднимался»")
    H.ok(text:find("%d%d%d%d%-%d%d%-%d%d") == nil, "не называет дату «подъёма»")
    H.ok(text:find("224", 1, true) == nil, "числа из чужой истории навыка в тексте нет")
    H.ok(text:find("по ходу игры", 1, true) == nil,
        "не обещает, что максимум «поднимается по ходу игры»: аддон этого не знает")
    H.ok(text:find("225/225", 1, true) ~= nil, "а то, что известно, сказано: навык равен максимуму")
    H.ok(text:find("не знаю", 1, true) ~= nil, "и прямо сказано, чего аддон не знает")
end

H.suite("Чушь: «потолок поднимался» нет ни на вкладке персонажа, ни в сверке")
do
    local env = historyWorld()
    local ns = env.ns
    -- Самого раздела «Персонаж» в окне больше нет (игрок назвал его
    -- бесполезным, 2026-11-21); строка проверяется на всех разделах, какие
    -- есть, - её не должно быть нигде.
    ns.MainFrame:Build()
    H.eq(ns.MainFrame:TabDef("CHAR"), nil, "раздела «Персонаж» в окне нет")
    local screen = {}
    for _, def in ipairs(ns.MainFrame.TABS) do
        ns.MainFrame:Select(def.key)
        ns.MainFrame:RenderActive()
        local _, texts = S.harvest(env.world, ns.MainFrame.frame)
        for _, t in ipairs(texts) do screen[#screen + 1] = S.plain(t) end
    end
    screen = table.concat(screen, "\n")
    H.ok(#screen > 200, "разделы окна отрисованы")
    H.ok(screen:find("поднимался", 1, true) == nil, "строки «потолок поднимался» в окне нет")

    local report = ns.SourceCheck and ns.SourceCheck.CheckSkillCaps
        and ns.SourceCheck:CheckSkillCaps() or nil
    local leaked = false
    local function walk(t, depth)
        if type(t) ~= "table" or depth > 4 then return end
        for k, v in pairs(t) do
            if type(k) == "string" and k:find("^cap[ML]") then leaked = true end
            if type(v) == "string" and v:find("поднимался", 1, true) then leaked = true end
            walk(v, depth + 1)
        end
    end
    walk(report, 0)
    H.eq(leaked, false, "в сверке навыков нет ни «подъёмов потолка», ни текста о них")
end

H.suite("Чушь: навык из истории — это последнее число дня, а максимум неизвестен")
do
    -- В кеше Mastercraft нет строки персонажа, есть только история. Раньше из
    -- неё брали { навык = первое, максимум = второе }: рыбалка 155/225 там, где
    -- на самом деле навык вырос за день со 155 до 225, а максимум не записан.
    local env = H.load()
    local ns = env.ns
    env.foreignDB = { history = { ["Player-1-1"] = {
        ["2026-11-16"] = { s = { Fishing = { 155, 155 } } },
        ["2026-11-17"] = { s = { Fishing = { 155, 225 } } },
    } } }
    local rows, route = ns.Api:MastercraftProfessions("Player-1-1")
    H.ok(type(rows) == "table" and #rows == 1, "навык из истории прочитан")
    local row = rows and rows[1] or {}
    H.eq(route, "MastercraftDB.history", "источник назван")
    H.eq(row.skill, 225, "навык — последнее число самого свежего дня")
    H.ok(row.max == nil or row.maxKnown == false,
        "максимум не выдуман: в истории его нет (получили " .. tostring(row.max) .. ")")
end

-- =====================================================================
-- ВТОРАЯ ПАРТИЯ: то, что нашла сплошная проверка текстов и команд.
-- =====================================================================

H.suite("Чушь: «в 3 раз», «в 167 раза», «в 25.3 раз» — число раз согласовано со словом")
do
    local env = H.load()
    local ns = env.ns
    local U = ns.Util
    for _, c in ipairs({
        { 1, "1 раз" }, { 2, "2 раза" }, { 3, "3 раза" }, { 4, "4 раза" }, { 5, "5 раз" },
        { 11, "11 раз" }, { 12, "12 раз" }, { 21, "21 раз" }, { 22, "22 раза" },
        { 25, "25 раз" }, { 167, "167 раз" }, { 600, "600 раз" },
        { 2.5, "2,5 раза" }, { 25.3, "25,3 раза" }, { 3.04, "3 раза" }, { 4.96, "5 раз" },
    }) do
        H.eq(U.times(c[1]), c[2], "U.times(" .. tostring(c[1]) .. ")")
    end
    H.eq(U.times(nil), nil, "не число — не текст")

    local MH = ns.MarketHistory
    H.eq(MH:TimesText(167.3), "167 раз", "история цен: 167.3 -> «167 раз» (было «167 раза»)")
    H.eq(MH:TimesText(22), "22 раза", "история цен: 22 -> «22 раза»")
    H.eq(MH:TimesText(2.34), "2,3 раза", "история цен: 2.34 -> «2,3 раза»")
    local badge = MH:Badge({ flag = MH.FLAG.HIGH_OUTLIER, ratio = 167 })
    H.ok(type(badge) == "string" and badge:find("в 167 раз", 1, true) ~= nil
        and badge:find("167x", 1, true) == nil,
        "заголовок совета о цене: «в 167 раз», а не «167x»: " .. tostring(badge))
    H.eq(MH.RatioSuffix, nil, "прежней функции с неверным окончанием больше нет")
end

H.suite("Чушь: «в 600 раз больше, чем у вас есть (0м)» — с нулём не сравниваем")
do
    local env = H.load()
    local ns = env.ns
    local E = ns.ActionEngine
    local zero = E.OutOfReachText(60000, 0, 60000)
    H.ok(zero:find("не хватает", 1, true) ~= nil, "при нуле денег сказано, сколько не хватает: " .. zero)
    H.ok(zero:find("раз", 1, true) == nil and zero:find("(0м)", 1, true) == nil,
        "и нет ни «в N раз», ни «(0м)»")
    local three = E.OutOfReachText(30000, 10000, 3)
    H.ok(three:find("в 3 раза больше, чем у вас есть", 1, true) ~= nil,
        "при деньгах — «в 3 раза», а не «в 3 раз»: " .. three)
    H.ok(ns.Risk:SaysUnaffordable({ need = zero }) and ns.Risk:SaysUnaffordable({ need = three }),
        "и самопроверка обе формулировки считает сказанными")

    H.eq(E.JoinSentences("не хватает: Рунная ткань x12 и ещё 2 позиции", "Это в 10 раз больше."),
        "не хватает: Рунная ткань x12 и ещё 2 позиции. Это в 10 раз больше.",
        "вторая фраза приписывается через точку, а не через пробел")
    H.eq(E.JoinSentences("Уже с точкой.", "Вторая."), "Уже с точкой. Вторая.", "вторая точка не ставится")
    H.eq(E.JoinSentences(nil, "Одна."), "Одна.", "к пустому тексту — просто фраза")
end

H.suite("Чушь: «/fp diag» отвечал именами функций игры и внутренних модулей")
do
    local env = H.load()
    local ns = env.ns
    local s = ns.Diag:Init()
    s.detect["C_Item.GetItemStats"] = false
    s.calls["C_Container.GetContainerItemInfo"] = { tries = 3, gotData = 0, empty = 3, failed = 0 }
    s.modules["gearUpgrades"] = { ["in"] = 0, out = 0 }
    ns.Api.Report = function()
        return {
            { group = "Сумки", ok = { "bagNumSlots" }, missing = {}, state = "ok" },
            { group = "Банк", ok = {}, missing = { "bankTabs" }, state = "none" },
            { group = "Предметы", ok = { "itemInfo" }, missing = { "itemStats" }, state = "partial" },
        }
    end
    local text = table.concat(ns.Diag:Summary(), "\n")
    for _, name in ipairs({ "GetItemStats", "GetContainerItemInfo", "gearUpgrades",
                            "bankTabs", "itemStats", "FOREVERPILOT_DIAG" }) do
        H.ok(text:find(name, 1, true) == nil, "в ответе нет имени «" .. name .. "»")
    end
    H.ok(text:find("Банк — нет совсем", 1, true) ~= nil
        and text:find("Предметы — частично", 1, true) ~= nil,
        "чего игра не даёт, названо темами, понятными игроку")
    H.ok(text:find("Сумки", 1, true) == nil, "а то, что на месте, не перечисляется")
    H.ok(text:find("SavedVariables", 1, true) ~= nil, "и сказано, где лежит полная запись")

    ns.Api.Report = function() return {} end
    H.ok(table.concat(ns.Diag:Summary(), "\n"):find("она сообщает", 1, true) ~= nil,
        "когда всё на месте — одна спокойная строка")
end

H.suite("Чушь: на карточке «Скрытых советов: N», а в ответе на её кнопку — другое число")
do
    local env = S.load(H)
    S.populate(env, H)
    local ns = env.ns
    for _, card in ipairs(ns.ActionEngine.cards or {}) do
        if not card.blocking then
            ns.Config:Dismiss(card.key, ns.Api:ServerTime(), 86400)
        end
    end
    H.build(env)
    local onCard = (ns.ActionEngine:HiddenSummary())
    local stored = ns.Config:DismissedCount(ns.Api:ServerTime())
    H.ok(onCard > 0 and stored >= onCard,
        "предпосылка: скрыто сейчас " .. tostring(onCard) .. ", записей о скрытии " .. tostring(stored))
    local n, message = ns.Dismissal:RestoreAll()
    H.eq(n, stored, "стёрты все записи о скрытии")
    H.eq(tonumber(tostring(message):match("(%d+)")), onCard,
        "в ответе — то же число, что стояло на карточке: " .. tostring(message))

    -- Запись есть, а прятать ей нечего: такого совета движок не строит.
    H.build(env)
    ns.Config:Dismiss("нет:такого:совета", ns.Api:ServerTime(), 86400)
    H.build(env)
    H.eq((ns.ActionEngine:HiddenSummary()), 0, "предпосылка: на экране ничего не скрыто")
    local n2, message2 = ns.Dismissal:RestoreAll()
    H.eq(n2, 1, "устаревшая запись стёрта")
    H.ok(tostring(message2):find("устаревш", 1, true) ~= nil
        and tostring(message2):find("вернул", 1, true) == nil,
        "и не сказано «вернул», раз возвращать было нечего: " .. tostring(message2))
    local n3, message3 = ns.Dismissal:RestoreAll()
    H.eq(n3, 0, "третий раз — нечего")
    H.eq(message3, "скрытых советов нет", "и ответ прежний")
end

H.suite("Чушь: «В список покупок» отвечала «добавил», ничего не добавив, и уменьшала закреплённое")
do
    local env = S.load(H)
    S.populate(env, H)
    local ns = env.ns
    H.build(env)
    local buy
    for _, card in ipairs(ns.ActionEngine.cards or {}) do
        if card.kind == ns.KIND.BUY and card.action and card.action.kind == "shop" then buy = card end
    end
    H.ok(buy ~= nil, "предпосылка: совет о покупке есть")
    if buy then
        local itemID, qty = buy.action.itemID, buy.action.qty or 1
        -- Игрок закрепил больше, чем просит совет.
        ns.ShoppingList:Pin(itemID, qty + 8)
        H.build(env)
        local again
        for _, card in ipairs(ns.ActionEngine.cards or {}) do
            if card.kind == ns.KIND.BUY and card.action and card.action.itemID == itemID then again = card end
        end
        H.ok(again ~= nil, "совет о покупке остался")
        if again then
            H.ok((tostring(again.why) .. " " .. tostring(again.need)):find("закреп", 1, true) ~= nil,
                "на карточке сказано, что количество закреплено игроком: " .. tostring(again.why))
            H.ok(tostring(again.why):find("выше", 1, true) == nil,
                "и нет слов о советах «выше»")
            ns.MainFrame:Build()
            ns.MainFrame:Select("NOW")
            ns.MainFrame:RenderActive()
            local row
            for _, r in ipairs(ns.Card.pool) do
                if r.__shown and r.card and r.card.key == again.key then row = r end
            end
            -- Кнопка совета теперь в карточке справа: щелчок по строке, потом она.
            local button = row and S.actionOf(ns, row) or nil
            H.ok(button ~= nil, "кнопка совета нарисована")
            if button then
                env.said = {}
                ns.Api.lastSaid = nil
                button.__scripts.OnClick(button)
                local lines = said(env)
                H.eq(#lines, 1, "ответ один")
                H.ok(tostring(lines[1]):find("уже в вашем списке покупок", 1, true) ~= nil,
                    "и он говорит, что позиция уже в списке: " .. tostring(lines[1]))
                H.eq(ns.Config:Shopping()[itemID], qty + 8,
                    "закреплённое руками количество нажатием не уменьшено")
            end
        end
    end
end

H.suite("Чушь: «это ниже всего, что я видел. За 3 дня цена выросла на 50%»")
do
    local env = H.load()
    local ns = env.ns
    ns.Config:SetProfile("EARN")
    env.money = 58052
    env.auctionator = true
    H.item(env, 7777, { name = "Шёлковый пояс", equipLoc = "INVTYPE_WAIST",
        reqLevel = 20, classID = 4, subclassID = 1, sellPrice = 600 })
    H.item(env, 7778, { name = "Шёлк", sellPrice = 100 })
    env.vendorPrices[7778] = 300
    env.bags[7778] = 20
    -- Записи три дня росли, а сейчас цена ниже любой из них.
    env.prices[7777] = 9000
    local cfg = ns.Config:Get()
    cfg.priceHistory[7777] = { [20772] = 20000, [20773] = 25000, [20774] = 30000 }
    cfg.priceHistoryMeta.days = 3
    cfg.priceHistoryMeta.firstDay = 20772
    cfg.priceHistoryMeta.lastDay = 20774
    H.profession(env, "Портняжное дело", 225, 225, {
        H.recipe { id = 7701, output = 7777, name = "Шёлковый пояс",
                   diff = "trivial", category = "Пояса",
                   reagents = { { itemID = 7778, qty = 3 } } },
    })
    H.itemsChanged(env)
    H.rescan(env)
    local c
    for _, card in ipairs(H.build(env)) do
        if card.kind == ns.KIND.PRICE_INFO then c = card end
    end
    H.ok(c ~= nil, "предпосылка: совет о цене построен")
    if c then
        local why = tostring(c.why)
        H.ok(ns.Util.contains(c.title, "дешево"), "совет говорит, что сейчас дёшево: " .. tostring(c.title))
        H.ok(why:find("выросла", 1, true) == nil,
            "и не говорит следом, что цена выросла: " .. why)
        H.ok(why:find(") За", 1, true) == nil and why:find(") Выборка", 1, true) == nil
            and why:find(") Это", 1, true) == nil,
            "следующая фраза не приклеена к скобке без точки")
        local _, shorts = ns.Util.lower(why):gsub("выборка короткая", "")
        H.ok(shorts <= 1, "«выборка короткая» сказано не больше одного раза (сказано " .. shorts .. ")")
        H.eq(why:sub(-1), ".", "текст кончается точкой")
    end
end

H.suite("Чушь: «среди 0 предметов, по которым у меня есть своя история»")
do
    local env = H.load()
    local ns = env.ns
    ns.Config:Get().priceHistory = {}
    ns.Resale:Opportunities(ns.CharacterScanner:Scan())
    local reason = tostring(ns.Resale.lastReason)
    H.ok(reason:find("среди 0", 1, true) == nil, "нуля предметов в причине нет: " .. reason)
    H.ok(reason:find("истории", 1, true) ~= nil and reason:find("нет", 1, true) ~= nil,
        "сказано прямо: истории цен нет")
end

H.suite("Чушь: «В список не поместилось 1 совет» — сказуемое согласовано с числом")
do
    local env = S.load(H)
    S.populate(env, H)
    local ns = env.ns
    local function overflow(over)
        local lines = ns.TabNow:Notices({ generated = 5 + over }, nil, 5, 5, {})
        return table.concat(lines, " | ")
    end
    H.ok(overflow(1):find("не поместился 1 совет:", 1, true) ~= nil, "один: " .. overflow(1))
    H.ok(overflow(2):find("не поместились 2 совета:", 1, true) ~= nil, "два: " .. overflow(2))
    H.ok(overflow(5):find("не поместилось 5 советов:", 1, true) ~= nil, "пять: " .. overflow(5))
    H.ok(overflow(21):find("не поместился 21 совет:", 1, true) ~= nil, "двадцать один: " .. overflow(21))
end

H.suite("Чушь: «…54с 97м. наблюдение всего одно» — вторая фраза с маленькой буквы")
do
    local env = H.load()
    local ns = env.ns
    local cfg = ns.Config:Get()
    cfg.priceHistory[778] = { [20774] = 25100 }
    cfg.priceHistoryMeta.days = 1
    cfg.priceHistoryMeta.firstDay = 20774
    cfg.priceHistoryMeta.lastDay = 20774
    for _, live in ipairs({ 25100, 20000, 30000 }) do
        local text = tostring(ns.MarketHistory:Verdict(778, live).text)
        H.ok(text:find(". Наблюдение всего одно", 1, true) ~= nil,
            "оговорка начинается с большой буквы: " .. text)
        H.ok(text:find("%. \208[\176-\191]") == nil and text:find("%. \209[\128-\143]") == nil,
            "после точки нет русской маленькой буквы")
        H.ok(text:find("ВЫШЕ", 1, true) == nil and text:find("НИЖЕ", 1, true) == nil,
            "и никто не кричит заглавными")
    end
    local above = tostring(ns.MarketHistory:Verdict(778, 30000).text)
    H.ok(above:find("всего, что я видел", 1, true) == nil,
        "про одну-единственную цену не сказано «выше всего, что я видел»: " .. above)
end

H.suite("Чушь: «Чары: 6/7, остался Шея», «Остался без чар: Голова, Запястья… формул на него»")
do
    local env = S.load(H)
    S.populate(env, H)
    local ns = env.ns
    -- Формул нет вовсе: остаётся один совет - про слоты без чар.
    ns.RecipeBook.byProfession = {}
    ns.RecipeBook:Reindex()
    H.build(env)
    local function noFormula()
        for _, c in ipairs(ns.ActionEngine.cards or {}) do
            if c.key == "ench:noformula" then return c end
        end
        return nil
    end
    local card = noFormula()
    H.ok(card ~= nil and card.enchantStatus ~= nil, "предпосылка: совет про слоты без чар есть")
    if card and card.enchantStatus then
        local bare = card.enchantStatus.bare or 0
        local text = tostring(card.title) .. " " .. tostring(card.why)
        H.ok(bare >= 2, "предпосылка: слотов без чар несколько (" .. bare .. ")")
        H.ok(text:find("стался", 1, true) == nil,
            "нет «остался» перед перечнем слотов: " .. text)
        H.ok(text:find("на него", 1, true) == nil and text:find("на этот слот", 1, true) == nil,
            "про несколько слотов не сказано «на него» и «на этот слот»")
        H.ok(text:find("на них", 1, true) ~= nil or text:find("на эти слоты", 1, true) ~= nil,
            "сказано во множественном числе")

        -- Один слот зачарован, один остался: заголовок с ходом дела.
        local firstLabel = (card.enchantStatus.bareLabels or {})[1]
        local done
        for slot, entry in pairs(env.equipped) do
            if not done and ns.SlotMap:Label(slot) == firstLabel then
                entry.enchantID = 999
                done = slot
            end
        end
        H.ok(done ~= nil, "предпосылка: нашёлся слот, который можно пометить зачарованным")
        H.itemsChanged(env)
        H.build(env)
        local one = noFormula()
        H.ok(one ~= nil and one.enchantStatus and one.enchantStatus.enchanted == 1
            and one.enchantStatus.bare == bare - 1,
            "предпосылка: теперь зачарован один слот")
        if one then
            local title, why = tostring(one.title), tostring(one.why)
            H.ok(title:find("^Чары: 1/") ~= nil, "заголовок говорит о ходе дела: " .. title)
            H.ok(title:find("стался", 1, true) == nil and title:find("без чар: ", 1, true) ~= nil,
                "и называет слоты без «остался»: " .. title)
            if (one.enchantStatus.bare or 0) == 1 then
                H.ok(why:find("на них", 1, true) == nil and why:find("на эти слоты", 1, true) == nil,
                    "про один слот — в единственном числе: " .. why)
            end
        end
    end
end

H.suite("Чушь: «а не 3 независимых находки», «3 носится сейчас»")
do
    local env = H.load()
    local ns = env.ns
    local VA = ns.VendorArbitrage
    H.ok(type(VA.IndependentFinds) == "function", "слова про независимые находки собирает одна функция")
    if type(VA.IndependentFinds) == "function" then
        H.eq(VA.IndependentFinds(1), "1 независимая находка", "одна")
        H.eq(VA.IndependentFinds(3), "3 независимые находки", "три (было «3 независимых находки»)")
        H.eq(VA.IndependentFinds(5), "5 независимых находок", "пять")
        H.eq(VA.IndependentFinds(21), "21 независимая находка", "двадцать одна")
        H.eq(VA.IndependentFinds(12), "12 независимых находок", "двенадцать")
    end
    -- «3 носится сейчас» стояло в заголовке совета про Благосклонность. На
    -- стенде такого совета нет (носить там нечего), поэтому проверяются сами
    -- строки кода - строки, а не комментарии.
    local Sense = assert(loadfile((H.ROOT or ".") .. "/Tests/sense.lua"))()
    local f = assert(io.open((H.ROOT or ".") .. "/Logic/ActionEngine.lua", "rb"))
    local src = f:read("*a")
    f:close()
    local stale, fresh = 0, 0
    for _, lit in ipairs(Sense.literals(src)) do
        if lit.text:find("носится сейчас", 1, true) then stale = stale + 1 end
        if lit.text:find("можно носить сейчас", 1, true) then fresh = fresh + 1 end
    end
    H.eq(stale, 0, "в текстах советов нет «N носится сейчас»")
    H.eq(fresh, 1, "сказано по-человечески: «N можно носить сейчас»")
end

H.suite("Чушь: «Приоритет: 0.46» в подсказке совета — число без шкалы и без смысла для игрока")
do
    local env = S.load(H)
    S.populate(env, H)
    local ns = env.ns
    ns.MainFrame:Build()
    ns.MainFrame:Select("NOW")
    ns.MainFrame:RenderActive()
    local total = #(ns.ActionEngine.cards or {})
    local place = {}
    for i, card in ipairs(ns.ActionEngine.cards or {}) do place[card.key] = i end
    local hovered, bad, retold = 0, {}, {}
    for _, row in ipairs(ns.Card.pool) do
        local enter = row.__shown and row.card and row.__scripts and row.__scripts.OnEnter
        if enter then
            local lines = {}
            local tip = env.G.GameTooltip
            tip.AddLine = function(_, text) lines[#lines + 1] = S.plain(tostring(text)) end
            tip.AddDoubleLine = function(_, a, b) lines[#lines + 1] = S.plain(tostring(a) .. " " .. tostring(b)) end
            tip.SetHyperlink = function() end
            enter(row)
            hovered = hovered + 1
            local text = table.concat(lines, "\n")
            if text:find("Приоритет", 1, true) or text:find("%d%.%d%d %(профиль") then
                bad[#bad + 1] = tostring(row.card.title)
            end
            -- И СЛУЖЕБНЫХ СТРОК В ПОДСКАЗКЕ НЕТ ВОВСЕ. Сначала балл заменили
            -- на «Место в общем списке: N из M»; игрок назвал лишним и это, и
            -- «достоверность» (2026-11-21). Место совета видно по самому
            -- списку, а под курсором - подсказка предмета, как в игре.
            if text:find("Место в общем списке", 1, true) or text:find("Достоверность", 1, true) then
                retold[#retold + 1] = tostring(row.card.title)
            end
        end
    end
    H.ok(hovered >= 5, "подсказок просмотрено: " .. hovered)
    H.eq(#bad, 0, "числа «Приоритет: 0.NN» в подсказках нет"
        .. ((#bad > 0) and ("  <- " .. table.concat(bad, "; ")) or ""))
    H.eq(#retold, 0, "и строк «место в списке» и «достоверность» там тоже нет"
        .. ((#retold > 0) and ("  <- " .. table.concat(retold, "; ", 1, math.min(3, #retold))) or ""))
    H.ok(total > 0 and place ~= nil, "советов в списке: " .. total)
end

H.suite("Чушь: «Материал есть у Гендольф Белыйй, 13 ур., Чернокнижник — 46 шт..» — две точки")
do
    local env = H.load()
    local ns = env.ns
    local U = ns.Util
    local Sense = assert(loadfile((H.ROOT or ".") .. "/Tests/sense.lua"))()

    -- ОДНО ПРАВИЛО НА ВЕСЬ АДДОН, А НЕ ЗАПЛАТКА В ОДНОМ МЕСТЕ. Точку в конце
    -- фразы ставит U.endSentence, и она смотрит на последний знак - значит
    -- работает для любого сокращения, а не для трёх перечисленных.
    H.ok(type(U.endSentence) == "function", "точку в конце фразы ставит одна функция")
    for _, c in ipairs({
        { "Это уже куплено: Льняная ткань — 46 шт.", "Это уже куплено: Льняная ткань — 46 шт." },
        { "на аккаунте есть: Алхимия 150 — Гендольф Белыйй, 13 ур.",
          "на аккаунте есть: Алхимия 150 — Гендольф Белыйй, 13 ур." },
        { "стоит 5 з.", "стоит 5 з." },
        { "прирост 8 ед.", "прирост 8 ед." },
        { "обычная фраза", "обычная фраза." },
        { "уже с точкой.", "уже с точкой." },
        { "восклицание!", "восклицание!" },
        { "вопрос?", "вопрос?" },
        { "двоеточие:", "двоеточие:" },
        { "многоточие…", "многоточие…" },
        { "хвостовой пробел ", "хвостовой пробел." },
        { "хвост после сокращения 46 шт. ", "хвост после сокращения 46 шт." },
        { "", "" },
    }) do
        H.eq(U.endSentence(c[1]), c[2], "U.endSentence(«" .. c[1] .. "»)")
    end
    H.eq(U.endSentence(nil), nil, "не строка — не текст")

    -- И ПРАВИЛО НЕ РАСХОДИТСЯ С ПРОВЕРЯЮЩИМ. Список сокращений знает
    -- Tests/sense.lua; U.endSentence списка не держит сознательно. Поэтому
    -- согласие проверяется по ВСЕМУ списку сразу: допиши туда сокращение - и
    -- эта проверка сама скажет, если конец фразы с ним ломается.
    local abbr = { "з" }
    for word in pairs(Sense.ABBREVIATIONS) do abbr[#abbr + 1] = word end
    table.sort(abbr)
    local bad = {}
    for _, word in ipairs(abbr) do
        local text = U.endSentence("Материал есть у Гендольф Белыйй — 46 " .. word .. ".")
        if #Sense.punctuation(text) > 0 then bad[#bad + 1] = text end
    end
    H.ok(#abbr > 10, "сокращений в списке проверки: " .. #abbr)
    H.eq(#bad, 0, "ни на одном из них конец фразы не даёт двух точек"
        .. ((#bad > 0) and ("  <- " .. table.concat(bad, "; ", 1, math.min(3, #bad))) or ""))

    -- Прежние две самодельные проверки «последний знак из трёх» убраны: именно
    -- они не знали про сокращения. Склейка фраз ходит через то же правило.
    local E = ns.ActionEngine
    H.eq(E.JoinSentences("Льняная ткань — 46 шт.", "Это в 10 раз больше."),
        "Льняная ткань — 46 шт. Это в 10 раз больше.",
        "склейка после сокращения не ставит вторую точку")
    local src = {}
    for _, file in ipairs({ "Logic/ActionEngine.lua" }) do
        local f = assert(io.open((H.ROOT or ".") .. "/" .. file, "rb"))
        src[#src + 1] = f:read("*a")
        f:close()
    end
    local text = table.concat(src, "\n")
    H.eq(select(2, text:gsub('last ~= "%."', "")), 0,
        "своего списка знаков в ActionEngine больше нет")
    H.eq(select(2, text:gsub('%[%%%.!%%%?%]%$', "")), 0,
        "и своего образца конца фразы тоже")
end


-- 7. СКРИНШОТ ИЗ ИГРЫ: ЧЕРНОКНИЖНИК 14 УРОВНЯ, ПРОФИЛЬ «ПРОКАЧКА» -----------
--
-- Четыре находки с одного экрана, каждая своим набором. Разметка карточки,
-- подсказка, шапка списка и один предмет в двух спорящих советах.

-- Мир, в котором одна и та же вещь и лучше надетой, и выгодна на продажу.
-- Это не редкий случай: ремесленная вещь продаётся на аукционе всегда, а
-- надеть её можно только одну.
local function wearOrSellWorld()
    local env = S.load(H)
    local ns = env.ns

    env.player.level = 26
    env.player.classFile = "MAGE"
    env.player.className = "Маг"

    H.item(env, 300, { name = "Простой капюшон", equipLoc = "INVTYPE_HEAD",
        reqLevel = 10, classID = 4, subclassID = 1, sellPrice = 100 })
    env.stats[300] = { ITEM_MOD_INTELLECT_SHORT = 4, ITEM_MOD_STAMINA_SHORT = 3 }
    env.equipped.HEAD = { itemID = 300 }

    H.item(env, 301, { name = "Расшитый капюшон", equipLoc = "INVTYPE_HEAD",
        reqLevel = 20, classID = 4, subclassID = 1, sellPrice = 400 })
    env.stats[301] = { ITEM_MOD_INTELLECT_SHORT = 14, ITEM_MOD_STAMINA_SHORT = 9 }

    H.item(env, 302, { name = "Тонкая ткань", sellPrice = 10 })
    env.prices[302] = 50
    env.prices[301] = 4000
    env.bags[302] = 12
    env.money = 468977

    H.profession(env, "Портняжное дело", 225, 225, {
        H.recipe { id = 701, output = 301, outputQty = 1,
                   reagents = { { itemID = 302, qty = 4 } },
                   name = "Расшитый капюшон", diff = "optimal",
                   category = "Капюшоны", categoryID = 1 },
    })
    H.build(env)
    return env
end

H.suite("Чушь: одну вещь советовали и надеть, и продать — двумя карточками")
do
    local env = wearOrSellWorld()
    local ns, U = env.ns, env.ns.Util

    local gear = cardsOfKind(ns, ns.KIND.CRAFT_GEAR)
    local profit = cardsOfKind(ns, ns.KIND.CRAFT_PROFIT)
    H.eq(#gear, 1, "совет «скрафтить и надеть» построен")
    H.eq(#profit, 0, "а второй карточки про ту же вещь нет")

    -- И про оба варианта сказано в одной карточке, с числами.
    local card = gear[1]
    H.ok(card.alsoSell ~= nil, "карточка знает про второй вариант")
    H.ok(U.contains(card.benefit or "", "продать"),
        "и называет его там, где игрок читает выгоду: " .. tostring(card.benefit))
    H.ok(U.contains(card.why or "", "выбирать вам"),
        "выбор оставлен игроку: " .. ns.Util.truncate(card.why, 220))
    H.ok(U.contains(card.why or "", "исключает"),
        "и сказано, что одно исключает другое")

    -- ПРАВИЛО ЦЕЛИКОМ: про один предмет не бывает одновременно совета надеть
    -- и совета продать. Это взаимоисключающие действия, и две карточки про них
    -- спорят друг с другом - в отличие от карточки «Выбор пути», которая
    -- отвечает на другой вопрос («откуда взять»), а не на тот же.
    local WEAR = { [ns.KIND.CRAFT_GEAR] = true, [ns.KIND.EQUIP] = true }
    local SELL = { [ns.KIND.CRAFT_PROFIT] = true, [ns.KIND.ARBITRAGE] = true,
                   [ns.KIND.RESELL] = true }
    local wear, sell = {}, {}
    for _, c in ipairs(ns.ActionEngine.cards) do
        if c.itemID then
            if WEAR[c.kind] then wear[c.itemID] = c.title end
            if SELL[c.kind] then sell[c.itemID] = c.title end
        end
    end
    local clash = {}
    for itemID, title in pairs(wear) do
        if sell[itemID] then
            clash[#clash + 1] = tostring(title) .. " / " .. tostring(sell[itemID])
        end
    end
    H.eq(#clash, 0, "ни об одном предмете не сказано разом «надеть» и «продать»"
        .. ((#clash > 0) and (": " .. table.concat(clash, "; ")) or ""))

    -- И ДЕНЬГИ НЕ ПОТЕРЯЛИСЬ В РАНЖИРОВАНИИ. До свёртки выгодный крафт держала
    -- в верху списка отдельная карточка «на продажу»; после свёртки её нет, и
    -- если бы очки за деньги ушли вместе с ней, тот же совет провалился бы вниз
    -- в профиле «Заработок» - то есть ровно там, где он нужнее всего.
    H.ok((card.axes and card.axes.profit or 0) > 0,
        "карточка считается и денежной тоже: ось прибыли "
        .. string.format("%.3f", (card.axes and card.axes.profit) or 0))

    -- Причина, по которой карточки продажи нет, записана: это не потеря.
    local f = ns.Diag:Init().funnels.craftProfit
    local drop = f and f.drops and f.drops["same-item-advised-to-wear"]
    H.ok(drop ~= nil and drop.n > 0,
        "и в воронке сказано, куда делась карточка продажи")
end

-- РАЗМЕТКА: три строки карточки не налезают друг на друга ------------------
--
-- На скриншоте вторая строка карточки нарисована ПОВЕРХ третьей - вместо двух
-- фраз каша. Причина была в UI/Card.lua: строка «почему» отсчитывалась сверху
-- (от заголовка), строка «чего не хватает» - снизу (от иконки), и при
-- настоящих высотах шрифтов клиента они сходились.
--
-- Глазами это не проверить, а по исходнику бессмысленно: вопрос не «какие там
-- числа», а «что из них получается». Поэтому прямоугольники строк считаются по
-- тем же привязкам, по которым их считает клиент.

-- Привязка в том виде, в каком её принимает клиент: либо (точка, x, y) с
-- неявным родителем, либо (точка, кто, его точка, x, y).
local function pointsOf(el)
    local out = {}
    for _, p in ipairs(el.__points or {}) do
        if type(p[2]) == "table" then
            out[#out + 1] = { point = p[1], rel = p[2], relPoint = p[3] or p[1],
                              y = tonumber(p[5]) or 0 }
        else
            out[#out + 1] = { point = p[1], rel = el.__parent, relPoint = p[1],
                              y = tonumber(p[3]) or 0 }
        end
    end
    return out
end

-- Высота: заданная, а у текста без заданной - одна строка шрифта, ровно
-- столько же, сколько отвечает про неё заглушка (GetStringHeight).
local function heightOf(el)
    if (tonumber(el.__height) or 0) > 0 then return el.__height end
    if el.__type == "FontString" then return 12 end
    return 0
end

-- Верх и низ элемента в координатах карточки: 0 - её верхний край, вниз
-- отрицательно. nil - привязка никуда не ведёт (например, к UIParent).
local function rangeY(el, card, depth)
    if not el then return nil end
    if el == card then return 0, -heightOf(card) end
    depth = (depth or 0) + 1
    if depth > 12 then return nil end
    local h = heightOf(el)
    for _, p in ipairs(pointsOf(el)) do
        local rt, rb = rangeY(p.rel, card, depth)
        if rt then
            local ry
            if p.relPoint:find("TOP") then ry = rt
            elseif p.relPoint:find("BOTTOM") then ry = rb
            else ry = (rt + rb) / 2 end
            ry = ry + p.y
            if p.point:find("TOP") then return ry, ry - h end
            if p.point:find("BOTTOM") then return ry + h, ry end
            return ry + h / 2, ry - h / 2
        end
    end
    return nil
end

local function overlapY(a, b)
    local top, bottom = math.min(a[1], b[1]), math.max(a[2], b[2])
    return (top > bottom) and (top - bottom) or 0
end

H.suite("Чушь: вторая строка карточки была нарисована поверх третьей")
do
    -- Самопроверка: без неё «пересечений нет» не значит ничего.
    H.ok(overlapY({ -10, -20 }, { -18, -30 }) > 0,
        "счётчик пересечений находит пересечение")
    H.eq(overlapY({ -10, -20 }, { -25, -35 }), 0,
        "и не находит там, где строки разнесены")

    local env = wearOrSellWorld()
    local ns = env.ns
    ns.MainFrame:Build()
    ns.MainFrame:Select("NOW")

    local cards = ns.ActionEngine.cards
    H.ok(#cards > 0, "карточки для разметки есть: " .. #cards)
    local worst, worstWhere = 0, nil
    for i, card in ipairs(cards) do
        local frame = ns.Card.Acquire(ns.TabNow.content, i)
        frame:SetWidth(640)
        ns.Card.Fill(frame, card)
        local box = {}
        for _, l in ipairs({ { "заголовок", frame.title }, { "выгода", frame.benefit },
                             { "иконка", frame.icon } }) do
            local t, b = rangeY(l[2], frame)
            H.ok(t ~= nil, "строка «" .. l[1] .. "» привязана к карточке")
            if t then
                box[l[1]] = { t, b }
                H.ok(t <= 0.001 and b >= -ns.Card.HEIGHT - 0.001,
                    "строка «" .. l[1] .. "» лежит внутри карточки ("
                    .. string.format("%.0f..%.0f", t, b) .. " при высоте "
                    .. ns.Card.HEIGHT .. ")")
            end
        end
        -- Строка в одну линию: заголовок и выгода стоят рядом, а не друг над
        -- другом, так что по вертикали им пересекаться можно - проверяется,
        -- что они не налезают ПО ГОРИЗОНТАЛИ (и на иконку тоже).
        local rects = {}
        for _, l in ipairs({ { "заголовок", frame.title }, { "выгода", frame.benefit },
                             { "иконка", frame.icon } }) do
            rects[l[1]] = S.rectOf(l[2], frame)
        end
        -- У заголовка ширина - сколько нарисовано, а не сколько отведено.
        if rects["заголовок"] then
            rects["заголовок"].right = rects["заголовок"].left
                + S.textWidth(S.plain(frame.title:GetText() or ""))
        end
        for _, pair in ipairs({ { "заголовок", "выгода" }, { "иконка", "заголовок" } }) do
            local ox, oy = S.rectOverlap(rects[pair[1]], rects[pair[2]])
            local over = (ox > 0 and oy > 0) and ox or 0
            if over > worst then
                worst, worstWhere = over, pair[1] .. " / " .. pair[2]
            end
            H.eq(over, 0, "«" .. pair[1] .. "» и «" .. pair[2]
                .. "» не налезают друг на друга (карточка " .. i .. ")")
        end
    end
    H.eq(worst, 0, "самое большое наложение по всему списку — ноль"
        .. ((worst > 0) and (": " .. worst .. " px на " .. tostring(worstWhere)) or ""))

    -- И числа разметки названы в одном месте, а не вписаны по месту: иначе
    -- следующая правка разведёт их снова.
    for _, key in ipairs({ "HEIGHT", "PAD", "ICON", "TEXT_LEFT", "LINE_H",
                           "TITLE_H", "TITLE_TOP", "TEXT_RIGHT", "GAP" }) do
        H.ok(type(ns.Card[key]) == "number", "разметка названа: ns.Card." .. key)
    end
end

-- СКРИНШОТ С ПРОСТЫНЁЙ, НАЛЕЗАНИЕМ И ОБРЕЗАННЫМ ЧИСЛОМ --------------------
--
-- Один скриншот, три находки, и игрок сказал про них дословно: «всё должно быть
-- кратко, понятно и без всяких хрени, воды, я тебе сказал это уже».
--
--   1. над списком - четыре абзаца подряд, пять строк до первого совета;
--   2. кнопка фильтра «Золото» нарисована поверх строки «75 рецептов известно
--      • материалы по советам: 4з 34с»;
--   3. в карточках обрезано ровно то, ради чего строку читают: «Разница
--      +8з 80…», «Торговец: Mister Graphed, Лесоречье, 78.2 5…».
--
-- Классы этих находок держат проверки по всем состояниям мира в
-- Tests/test_sense.lua. Здесь - сам случай, теми же словами и числами.

local function screenshotWorld()
    local env = S.load(H)
    local ns = env.ns
    S.populate(env, H)
    -- Ровно те причины, которые на скриншоте и дали четыре абзаца: порог
    -- мелкой выгоды, профиль, длина списка. Плюс окно профессий, которое в
    -- этом заходе не открывали, - четвёртым абзацем стояла инструкция про него.
    env.professionsUI = false
    ns.Config:SetMoneyFloorMode(ns.MONEY_FLOOR_MODE.FIXED)
    ns.Config:SetMoneyFloorOwn(1000)
    ns.PROFILE_EXCLUDE[ns.Config:Profile()] = { BUY = true }
    ns.MAX_CARDS = 4
    H.build(env)
    ns.MainFrame:Build()
    ns.MainFrame:Select("NOW")
    S.layout(env)
    ns.MainFrame:RenderActive()
    return env
end

H.suite("Чушь: над списком стояла простыня в пять строк")
do
    local env = screenshotWorld()
    local ns = env.ns
    local chip = ns.Config:Chip()
    local shown = ns.ActionEngine:Filtered(chip)

    -- Подробности на месте - все четыре, как и раньше.
    -- (Без строк «почему у совета нет кнопки»: они теперь стоят в карточке
    -- самого совета, на месте кнопки.)
    local notices = ns.TabNow:Notices(ns.ActionEngine.meta, chip, #shown,
        #ns.ActionEngine.cards, {})
    H.ok(#notices >= 3, "причин, о которых есть что сказать: " .. #notices)
    local joined = table.concat(notices, " ")
    H.ok(ns.Util.contains(joined, "порог мелкой"), "порог среди них")
    H.ok(ns.Util.contains(joined, "Профиль «"), "профиль тоже")
    H.ok(ns.Util.contains(joined, "не поместил"), "и длина списка")
    H.ok(#joined > 250, "вместе это " .. #joined .. " символов — та самая простыня")

    -- А НА ЭКРАНЕ - ОДНА КОРОТКАЯ СТРОКА В ШАПКЕ: сколько советов и сколько не
    -- показано. Отдельной полосы над списком и абзаца под ним больше нет.
    local tab = ns.TabNow
    H.eq(tab.strip, nil, "отдельной строки над списком нет")
    H.eq(tab.note, nil, "и абзаца под списком тоже")
    local line = S.plain(tab.summary:GetText() or "")
    H.eq(line:find("\n", 1, true), nil, "строка в шапке ровно одна: " .. line)
    H.ok(ns.Util.charLen(line) <= 110,
        "и короткая: " .. ns.Util.charLen(line) .. " символов вместо " .. #joined)
    H.ok(line:find("не показано", 1, true) ~= nil and line:find("%d") ~= nil,
        "число не показанных советов в ней есть")
    -- Под курсором у неё - все подробности (и причины молчащих веток).
    local tipText = table.concat(tab.summaryTip or {}, " ")
    for _, notice in ipairs(notices) do
        H.ok(tipText:find(notice, 1, true) ~= nil,
            "под курсором есть: " .. ns.Util.truncate(S.plain(notice), 40))
    end

    -- ПЕРВЫЙ СОВЕТ НАЧИНАЕТСЯ СРАЗУ ПОД ШАПКОЙ: над ним только заголовок его
    -- раздела.
    local first
    for _, row in ipairs(ns.Card.pool) do
        if row.__shown and row.card and not first then first = row end
    end
    H.ok(first ~= nil, "первый совет нарисован")
    if first then
        local rect = S.rectOf(first, ns.TabNow.content)
        H.ok(rect ~= nil and rect.top >= -(ns.TabNow.SECTION_H + 4),
            "и он стоит сразу под заголовком раздела ("
            .. string.format("%.0f", rect and rect.top or 0) .. ")")
    end

    -- Инструкция про окно профессий над списком больше не висит.
    H.eq(line:find("окне профессий", 1, true), nil,
        "инструкции про окно профессий в строке нет")
end

H.suite("Чушь: кнопка фильтра «Золото» была нарисована поверх строки с числами")
do
    -- Проверка идёт по нескольким ширинам окна: налезание зависит от длины
    -- подписей и строки, а не от одного размера. 560 - минимальная ширина окна
    -- (UI/MainFrame.lua, Main.MIN_WIDTH).
    local env = screenshotWorld()
    local ns = env.ns
    local clash, checked = {}, 0
    for _, width in ipairs({ ns.MainFrame.MIN_WIDTH, 980, 1280 }) do
        S.layout(env, width, 600)
        ns.MainFrame:RenderActive()
        local tab = ns.TabNow
        local parts = { { "строка статистики", tab.summary },
                        { "подпись профилей", tab.profileLabel } }
        for key, chip in pairs(tab.filterChips) do
            parts[#parts + 1] = { "фильтр «" .. ns.CHIP_LABEL[key] .. "»", chip }
        end
        for key, chip in pairs(tab.profileChips) do
            parts[#parts + 1] = { "профиль «" .. ns.PROFILE_LABEL[key] .. "»", chip }
        end
        H.ok(S.plain(tab.summary:GetText() or ""):find("совет") ~= nil,
            "при ширине " .. width .. " строка статистики непустая: "
            .. S.plain(tab.summary:GetText() or ""))
        for i = 1, #parts do
            for j = i + 1, #parts do
                local a = S.rectOf(parts[i][2], tab.frame)
                local b = S.rectOf(parts[j][2], tab.frame)
                checked = checked + 1
                local ox, oy = S.rectOverlap(a, b)
                -- Чего на экране нет (подпись «Что важнее:» в узком окне
                -- уступает место вкладкам), то ни на что и не налезает.
                if parts[i][2].__shown == false or parts[j][2].__shown == false then
                    ox, oy = 0, 0
                end
                if ox > 0 and oy > 0 then
                    clash[#clash + 1] = width .. "px: «" .. parts[i][1] .. "» и «"
                        .. parts[j][1] .. "» на " .. string.format("%.0f x %.0f", ox, oy)
                end
            end
        end
    end
    H.ok(checked > 100, "пар сверено: " .. checked)
    H.eq(#clash, 0, "ни одна пара не налезает ни при какой ширине"
        .. ((#clash > 0) and ("  <- " .. table.concat(clash, "; ", 1,
            math.min(4, #clash))) or ""))
end

H.suite("Чушь: «Разница +8з 80…» — обрезано было само число")
do
    local env = screenshotWorld()
    local ns = env.ns
    -- Те самые строки со скриншота, слово в слово.
    local WHY = "У торговца ~60с (оценка, возраст неизвестен), на аукционе дают"
        .. " 9з 40с (сбор аукциона уже вычтен). Разница +8з 80с за штуку, это"
        .. " 1468% наценки. Наличие я не проверял: у этого торговца я не стоял,"
        .. " а внешние базы про запас ничего не говорят."
    local NEED = "Торговец: Mister Graphed, Лесоречье, 78.2 51.9."
        .. " Выставляется ли эта вещь на аукцион, я пока не проверил: клиент"
        .. " ещё не отдал её данные."
    -- Совет того вида, у которого своих строк «подпись - значение» нет:
    -- карточка показывает его текст, и проверяется именно текст.
    local card = {
        kind = ns.KIND.RESELL, key = "test:resell", title = "Перекупить: Шёлковая ткань",
        benefit = "+8з 80с за штуку", benefitKind = "gold",
        why = WHY, need = NEED, action = { kind = "noop" },
    }
    local row = ns.Card.Acquire(ns.TabNow.content, 1)
    row:SetWidth(640)
    ns.Card.Fill(row, card)

    -- В СТРОКЕ СПИСКА теперь только заголовок и выгода: длинному тексту там не
    -- место, и резать его больше незачем.
    H.eq(rawget(row, "why"), nil, "строки «почему» в списке нет")
    H.eq(rawget(row, "need"), nil, "и строки «чего не хватает» тоже")

    -- А В КАРТОЧКЕ СПРАВА - СУТЬ, ЦЕЛЫМИ ФРАЗАМИ. Оговорки об источнике числа
    -- («оценка, возраст неизвестен», «наличие я не проверял») убраны: игрок
    -- назвал их лишними (2026-11-21). Но ни одна сумма и ни одни координаты
    -- при этом не разрезаны - фраза либо стоит целиком, либо её нет.
    S.layout(env)
    ns.TabNow:SelectCard(card)
    local detail = ns.Detail
    H.eq(detail.card, card, "совет открыт в карточке справа")
    H.eq(detail.lead.__shown, true, "суть совета в карточке показана")
    local lead = S.plain(detail.lead:GetText() or "")
    H.eq(lead, "У торговца ~60с, на аукционе дают 9з 40с."
        .. " Разница +8з 80с за штуку, это 1468% наценки.",
        "и стоит целыми фразами, с целыми числами")
    H.eq(lead:find("возраст", 1, true), nil, "оговорки об источнике числа в ней нет")
    H.eq(detail.need.__shown, true, "«что сделать» в карточке показано")
    local need = S.plain(detail.need:GetText() or "")
    H.ok(need:find("Торговец: Mister Graphed, Лесоречье, 78.2 51.9.", 1, true) ~= nil,
        "фраза с торговцем стоит целиком: " .. need)
    H.ok(need:find("78.2 51.9", 1, true) ~= nil,
        "координаты остались целыми: " .. need)

    -- Оговорка про недоверие к числу не выброшена: 1468% без неё - ложь.
    card.why = WHY .. " Числа этой карточки не сходятся — проверьте цену на месте."
    ns.Card.Fill(row, card)
    ns.TabNow:SelectCard(card)
    local doubted = S.plain(detail.lead:GetText() or "")
    H.ok(doubted:find("не сходятся", 1, true) ~= nil,
        "оговорка осталась на экране: " .. doubted)
    H.ok(doubted:find("1468%", 1, true) ~= nil, "и стоит рядом со своим числом")

    -- И ДАЖЕ ТАМ, ГДЕ ТЕКСТ «ЧТО СДЕЛАТЬ» ЗАМЕНЁН СТРОКАМИ (у совета с планом
    -- крафта его заменяет блок покупок), координаты и предупреждения из него
    -- не пропадают.
    local planned = {
        kind = ns.KIND.CRAFT_MAT, key = "test:planned", title = "Скрафтить: Рулон ткани",
        benefit = "+1 навык", why = "Нужен для двух советов.", need = NEED,
        action = { kind = "noop" },
        plan = { ready = false, cost = 150, crafts = {},
                 shopping = { { itemID = 2589, qty = 3, unit = 50, subtotal = 150,
                                src = "auctionator" } } },
    }
    local sheet = ns.Card.Sheet(planned)
    H.eq(#sheet.blocks, 1, "у совета с планом крафта есть блок покупок")
    H.ok(sheet.need:find("78.2 51.9", 1, true) ~= nil,
        "и координаты из его текста остались: " .. tostring(sheet.need))
    H.eq(sheet.need:find("не проверил", 1, true), nil,
        "а остальное из этого текста уже сказано блоком покупок")

    -- Под курсором у строки списка совет не пересказывается: там то, что в
    -- строке не поместилось, и подсказка предмета.
    local tip = {}
    env.G.GameTooltip.AddLine = function(_, text) tip[#tip + 1] = S.plain(text) end
    env.G.GameTooltip.AddDoubleLine = function() end
    env.G.GameTooltip.SetHyperlink = function() end
    local enter = row.__scripts and row.__scripts.OnEnter
    H.ok(enter ~= nil, "у строки списка есть подсказка")
    if enter then pcall(enter, row) end
    local joined = table.concat(tip, "\n")
    H.eq(joined:find("я не стоял", 1, true), nil,
        "оговорок об источнике под курсором тоже нет")

    -- ТО ЖЕ ПРАВИЛО ТАМ, ГДЕ РЕЖУТ ПО СИМВОЛАМ: подпись стрелки и свёрнутая
    -- панель. U.truncate режет ровно по счёту и попадает в середину номера.
    local TITLE = "Купить и перепродать: Предмет #249429"
    local old = ns.Util.truncate(TITLE, 34)
    H.eq(old:find("#249429", 1, true), nil,
        "по счёту символов номер предмета разрезался: " .. old)
    local new = ns.Util.fitChars(TITLE, 34)
    H.ok(new:find("#249429", 1, true) ~= nil, "а так он цел: " .. new)
    H.ok(ns.Util.charLen(new) <= 34, "и в 34 символа укладывается: "
        .. ns.Util.charLen(new))
    H.eq(ns.Util.fitChars(TITLE, 80), TITLE, "а когда места хватает, режется нечего")
end

H.suite("Чушь: на панели заголовок обрезался посреди номера предмета")
do
    local env = screenshotWorld()
    local ns = env.ns
    ns.Config:Get().panel.enabled = true
    ns.StepPanel:Build()
    ns.StepPanel:ApplyVisibility()
    local card = ns.StepPanel.current or (ns.ActionEngine.cards or {})[1]
    H.ok(card ~= nil, "совет для панели есть")
    card.title = "Купить и перепродать: Предмет #249429"
    card.benefit = "+21с 10м за штуку"
    ns.StepPanel.current = card
    ns.StepPanel:Render()

    local f = ns.StepPanel.frame
    local drawn = S.plain(f.title:GetText() or "")
    local room = (tonumber(f:GetWidth()) or 0) - 46
        - ((tonumber(f.benefit:GetStringWidth()) or 0) + 14)
    H.ok(room > 0, "место под заголовок посчитано: " .. string.format("%.0f", room))
    H.ok(S.textWidth(drawn) <= room,
        "заголовок влезает: " .. S.textWidth(drawn) .. " при "
        .. string.format("%.0f", room) .. " — " .. drawn)
    H.ok(drawn:find("#249429", 1, true) ~= nil,
        "и номер предмета в нём цел: " .. drawn)
end

-- ПОДСКАЗКА: длинная инструкция стояла в ней второй раз --------------------
--
-- Длинное объяснение про окно профессий («Окно профессий я не открываю: игра
-- это аддонам запрещает…») стоит над списком. В подсказке предмета его быть не
-- должно: там оно занимало пять строк поверх игровых данных о предмете - то
-- есть поверх того, за чем игрок на подсказку и наводил мышь. Вместо него в
-- подсказке стоит ОДНА строка, и она про этот рецепт: что открыть и что найти.

local function tipLines(env, frame)
    local tip = env.G.GameTooltip
    local lines = {}
    local savedAdd, savedLink = tip.AddLine, tip.SetHyperlink
    tip.AddLine = function(_, text) lines[#lines + 1] = tostring(text) end
    tip.SetHyperlink = function() end
    local enter = frame.__scripts and frame.__scripts.OnEnter
    if enter then pcall(enter, frame) end
    tip.AddLine, tip.SetHyperlink = savedAdd, savedLink
    return lines
end

H.suite("Чушь: подсказка повторяла инструкцию про окно профессий")
do
    local env = wearOrSellWorld()
    local ns = env.ns
    ns.MainFrame:Build()
    ns.MainFrame:Select("NOW")

    local note = ns.RecipeBook:ShowState().note
    H.ok(note ~= nil and #tostring(note) > 60,
        "инструкция существует и она длинная: " .. ns.Util.truncate(note, 60))

    local withRecipe, checked = 0, 0
    for i, card in ipairs(ns.ActionEngine.cards) do
        local frame = ns.Card.Acquire(ns.TabNow.content, i)
        ns.Card.Fill(frame, card)
        if card.action and card.action.kind == "findRecipe" then
            withRecipe = withRecipe + 1
            local joined = table.concat(tipLines(env, frame), " ")
            checked = checked + 1
            H.eq(ns.Util.contains(joined, "аддонам запрещает"), false,
                "«" .. ns.Util.truncate(card.title, 26)
                .. "»: в подсказке длинного объяснения нет")
            H.eq(ns.Util.contains(joined, "написано в строке под ним"), false,
                "   и его второй половины тоже")
            -- А ОДНА СТРОКА ПРО ЭТОТ РЕЦЕПТ - В КАРТОЧКЕ СОВЕТА, на месте
            -- кнопки: именно её и не хватало.
            ns.TabNow:SelectCard(card)
            H.ok(ns.Detail.note.__shown
                and ns.Util.contains(ns.Detail.note:GetText() or "", "айдите"),
                "   а в карточке совета сказано, что рецепт надо найти самому")
        end
    end
    H.ok(withRecipe > 0, "советы с рецептом в списке есть: " .. withRecipe)
    H.ok(checked > 0, "и их подсказки проверены")

    -- Над списком она осталась: одна строка на все такие советы.
    local chip = ns.Config:Chip()
    local shown = ns.ActionEngine:Filtered(chip)
    local notices = ns.TabNow:Notices(ns.ActionEngine.meta, chip, #shown,
        #ns.ActionEngine.cards, shown)
    local said = false
    for _, line in ipairs(notices) do
        if ns.Util.contains(line, "Окно профессий я не открываю") then said = true end
    end
    H.ok(said, "а над списком инструкция на месте")
    -- И ОДНА, А НЕ ПО СТРОКЕ НА СОВЕТ. Советов с рецептом несколько, причина у
    -- них общая, и Notices обязан свернуть её в одну строку: иначе над списком
    -- снова выросла бы простыня, из-за которой этот набор и появился.
    local repeats = 0
    for _, line in ipairs(notices) do
        if ns.Util.contains(line, "Окно профессий я не открываю") then
            repeats = repeats + 1
        end
    end
    H.eq(repeats, 1, "и ровно одна на все " .. withRecipe .. " совета с рецептом")
end

-- ШАПКА: «закупка 5з» и «Перекупить» ---------------------------------------
--
-- Две строки, которые игрок прочитал и не понял, что они значат:
--   «75 рецептов известно • закупка 5з» - что такое «закупка 5з»;
--   «Профиль «Прокачка» не показывает 13 советов: ... Перекупить (4) ...» -
--   «Перекупить» не говорит, что это за совет.

H.suite("Чушь: «закупка 5з» — из строки непонятно, что это за деньги")
do
    local env = wearOrSellWorld()
    local ns = env.ns
    -- МАТЕРИАЛОВ В СУМКАХ НЕТ, иначе покупать нечего и строки про деньги в
    -- шапке не будет вовсе - проверять было бы нечего.
    env.bags[302] = nil
    H.itemsChanged(env)
    H.build(env)
    ns.MainFrame:Build()
    ns.MainFrame:Select("NOW")
    ns.TabNow:Render()

    H.ok((ns.ActionEngine.meta.shoppingLines or 0) > 0,
        "список покупок непустой: позиций "
        .. tostring(ns.ActionEngine.meta.shoppingLines))
    local text = S.plain(ns.TabNow.summary:GetText() or "")
    H.ok(#text > 0, "строка в шапке непустая: " .. text)
    H.eq(ns.Util.contains(text, "закупка"), false,
        "слова «закупка» в ней больше нет: " .. text)
    H.ok(ns.Util.contains(text, "материал"),
        "сказано, за что эти деньги — за материалы: " .. text)
    H.ok(ns.Util.contains(text, "по всем советам"),
        "и откуда взялся список — из советов этого экрана: " .. text)
end

H.suite("Чушь: «Перекупить» не говорило, что это за совет")
do
    local env = wearOrSellWorld()
    local ns = env.ns
    local resell = ns.KIND_LABEL[ns.KIND.RESELL]
    local arb = ns.KIND_LABEL[ns.KIND.ARBITRAGE]
    H.ok(type(resell) == "string" and resell ~= "", "у вида совета есть название")
    H.ok(ns.Util.contains(resell, "лот"),
        "сказано, что перекупается лот: «" .. resell .. "»")
    H.ok(ns.Util.contains(resell, "аукцион"),
        "и что лот с аукциона — иначе это не отличить от покупки у торговца")
    H.ok(ns.Util.contains(arb, "торговц"),
        "а у соседнего вида названо его место покупки: «" .. arb .. "»")

    -- Названия видов стоят в одной строке рядом («не показывает 13 советов:
    -- ... (8), ... (4)»), поэтому они обязаны быть разными и не путаться.
    local seen = {}
    for kind in pairs(ns.KIND) do
        local text = ns.KIND_LABEL[kind]
        H.ok(type(text) == "string" and text ~= "",
            "у вида «" .. kind .. "» есть название")
        if text then
            H.ok(seen[text] == nil, "название «" .. tostring(text)
                .. "» не повторяется у двух видов"
                .. (seen[text] and (" (уже у " .. seen[text] .. ")") or ""))
            seen[text] = kind
        end
    end

    -- И строка, в которой они стоят, собирается этими же словами.
    local line = ns.TabNow:Notices({ profileDropped = 4,
        profileDroppedByKind = { [ns.KIND.RESELL] = 4 } }, ns.CHIP.ALL, 2, 2, {})
    local joined = table.concat(line, " ")
    H.ok(ns.Util.contains(joined, resell),
        "в строке «профиль не показывает N советов» стоит полное название: "
        .. joined)
end

end
