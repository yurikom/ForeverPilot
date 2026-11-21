-- ForeverPilot / Logic/Favor.lua
--
-- БЛАГОСКЛОННОСТЬ ТОРГОВЦА: РЕЦЕПТЫ ГЕЙТЯТСЯ НАВЫКОМ, А НЕ УРОВНЕМ.
--
-- Это самая полезная находка про этого персонажа, и она держится на одном
-- наблюдении: у него навык 225 при уровне 26. Рецепты за Merchant's Favor
-- требуют НАВЫКА - жемчужный набор портняжки просит 60..125, посох и сфера от
-- чар 140 - и ни один из этих порогов не требует уровня персонажа. То есть он
-- может забрать сейчас то, за чем остальные приходят на 35+.
--
-- Поэтому ветка отвечает на четыре вопроса, и ровно в этом порядке:
--   1. сколько Favor нужно всего;
--   2. что за него брать и в каком порядке;
--   3. что из этого надевается ПРЯМО СЕЙЧАС (а это решается уровнем предмета
--      из клиентской базы, а не словами сайта);
--   4. как Favor вообще зарабатывается.
--
-- ОТКУДА ДАННЫЕ И ЧЕМУ ЗДЕСЬ МОЖНО ВЕРИТЬ. Data/Horizon.lua разделяет это
-- честно, и ветка обязана разделение сохранить:
--   * itemID, пороги навыка и реагенты - с диска (Mastercraft + Polestar_Codex,
--     сверено между собой), это CACHED;
--   * сколько Favor стоит покупка и сколько даёт ящик - слова сайта сообщества
--     (H.CONFIDENCE.MF_* = "WEB"), в игре не проверено;
--   * «жемчужный набор = аркан» - тоже слова сайта. Поэтому про школу ветка НЕ
--     заявляет ничего: она берёт характеристики предмета из Polestar_ItemDB и
--     показывает ЦИФРЫ. Сам файл данных на этом настаивает, и это правильно -
--     цифры игрок может проверить, ярлык нет.
--
-- Никакой автоматизации: аддон ничего не покупает, не сдаёт и не учит.
local ADDON, ns = ...

local U = ns.Util
local Api = ns.Api
local CONF = ns.CONF

local F = {}
ns.Favor = F

-- Покупки, доступные ПО НАВЫКУ ------------------------------------------

-- Навык персонажа по линии профессии. Линия (197 портняжка, 333 чары) - это то,
-- чем размечены записи в Horizon; имя профессии локализовано и сравнивать по
-- нему нельзя.
-- НОМЕР БЕРЁТСЯ ЧЕРЕЗ ForeverSource:ResolveSkillLine, А НЕ НАПРЯМУЮ.
--
-- Напрямую было так: `line = tonumber(prof.skillLineID)`, и если номер есть -
-- имя профессии уже не спрашивалось. В живой игре клиент отдаёт портняжке
-- номер 2948, а не 197, - сверка не находила ничего, навык выходил nil, и ветка
-- сообщала «навыка пока не хватает» при навыке 225 против порога 60. Разведка
-- данных была права, ветка - нет.
--
-- Возвращает skill, prof, resolved: третье значение отвечает на вопрос,
-- УДАЛОСЬ ли вообще сопоставить профессию с линией навыка. Без него «навыка
-- нет» и «я не понял, какой это навык» выглядят одинаково, а это разные вещи и
-- говорить игроку про них надо разное.
function F:SkillOf(snap, skillLineID)
    local FS = ns.ForeverSource
    local anyResolved = false
    for _, prof in ipairs((snap and snap.professions) or {}) do
        local line
        if FS and FS.ResolveSkillLine then
            line = FS:ResolveSkillLine(prof)
        else
            line = tonumber(prof.skillLineID)
        end
        if line then anyResolved = true end
        if line == skillLineID then
            -- Навыку, которому мы не верим, гейт не доверяем: лучше не
            -- предложить, чем предложить недоступное.
            if prof.skillTrusted == false then return nil, prof, true end
            return tonumber(prof.skill), prof, true
        end
    end
    return nil, nil, anyResolved
end

-- Одна покупка, разобранная по фактам.
--   { en, favor, skillNeeded, skill, affordableBySkill, outItemID, name,
--     reqLevel, wearableNow, slot, stats, statText, vendors, reagents }
function F:Describe(entry, snap)
    if type(entry) ~= "table" then return nil end
    local skill, prof, lineResolved = F:SkillOf(snap, entry.prof)
    local out = tonumber(entry.out)

    local info = out and Api:ItemInfo(out) or nil
    -- УРОВЕНЬ ПРЕДМЕТА - ИЗ ДАННЫХ, А НЕ ИЗ ОБЕЩАНИЙ. «Носится уже на 26» надо
    -- проверить, а не повторить: клиент или внешняя база скажут требование.
    local reqLevel = info and tonumber(info.reqLevel) or nil
    local slot = info and ns.SlotMap:FromEquipLoc(info.equipLoc) or nil
    if not reqLevel or not slot then
        local classID, sub, inv, req = Api:ForeignItemClass(out)
        reqLevel = reqLevel or req
        slot = slot or (inv and ns.SlotMap:FromInvNumber(inv)) or nil
    end
    local level = tonumber(snap and snap.level)
    local wearableNow = nil
    if reqLevel and level then wearableNow = (reqLevel <= level) end

    -- Характеристики - ЦИФРАМИ. Про «школу» ветка не заявляет ничего.
    local stats, statText
    if out and ns.GearAdvisor then
        stats = ns.GearAdvisor:ItemStats(out)
        if stats then
            -- Характеристики перечисляются ЦИФРАМИ и по-русски, самые крупные
            -- первыми. Школьный урон здесь - такая же строка, как остальное: мы
            -- не говорим «это аркановый набор», мы говорим «+11 к урону от
            -- тайной магии», и это игрок может проверить в подсказке предмета.
            local rows = {}
            for stat, value in pairs(stats) do
                rows[#rows + 1] = { stat = stat, value = value,
                                    label = ns.GearAdvisor:StatLabel(stat) }
            end
            table.sort(rows, function(a, b)
                if a.value ~= b.value then return a.value > b.value end
                return tostring(a.stat) < tostring(b.stat)
            end)
            local bits = {}
            for i = 1, math.min(4, #rows) do
                bits[#bits + 1] = "+" .. U.round(rows[i].value) .. " "
                    .. tostring(rows[i].label)
            end
            if #bits > 0 then statText = table.concat(bits, ", ") end
        end
    end
    local score
    if stats and ns.StatWeights and snap and snap.weights then
        score = ns.StatWeights:Score(stats, snap.weights)
    end

    -- ПРИРОСТ ПРОТИВ ТОГО, ЧТО УЖЕ ЕСТЬ, А НЕ ПОЛНАЯ ОЦЕНКА ВЕЩИ.
    --
    -- Живая жалоба (маг 31 ур., 2026-11-21): карточка «За Благосклонность:
    -- Жемчужные сапоги, +15 баллов» при надетых Сапогах из паучьего шелка,
    -- которые лучше по каждой характеристике. «+15» было ПОЛНОЙ оценкой сапог,
    -- как будто слот пуст: `score` выше ни с чем не сравнивается. Игрок купил
    -- выкройку и реагенты под вещь хуже своей.
    --
    -- Вторая половина той же ошибки: «Сфера мистического прозрения» в левую
    -- руку при двуручном посохе в правой. «Носится уже сейчас» проверяло
    -- только уровень, а надеть её можно, лишь сняв посох.
    --
    -- Сравнение - тем же способом, что у ветки экипировки (Gear:Upgrades):
    -- против надетого и против лучшего из того, что уже лежит в сумках.
    --   gain             - прирост в баллах; nil = сравнить не с чем или нечем
    --   notUpgrade       - посчитано, и вещь не лучше того, что есть
    --   blockedByTwoHand - вещь в левую руку, а в правой двуручное
    local gain, againstName, blockedByTwoHand, mainStatDrop = nil, nil, nil, nil
    if score and slot and ns.GearAdvisor and ns.GearAdvisor.DisplacedValue
        and snap and snap.weights then
        local G = ns.GearAdvisor
        local targetSlot, curScore, _, displaced =
            G:DisplacedValue(slot, snap, snap.weights)
        local floorScore, floorEntry = G:OwnedFloor(slot, snap, snap.weights)
        local base, againstID = curScore, nil
        local worn = targetSlot and snap.equipped and snap.equipped[targetSlot] or nil
        if worn then againstID = worn.itemID end
        if curScore ~= nil and floorScore and floorScore > curScore then
            base = floorScore
            if floorEntry and floorEntry.itemID then againstID = floorEntry.itemID end
        end
        if base ~= nil then gain = score - base end

        -- То же вето, что у ветки экипировки: вещь, которая просаживает
        -- главную характеристику профиля, улучшением не называется, что бы ни
        -- говорила сумма.
        if worn and displaced and #displaced <= 1 and G.Compare then
            local cmp = G:Compare(worn.link or worn.itemID, out, snap.weights,
                snap.weightSetKey)
            if cmp and cmp.mainStatDrop then mainStatDrop = true end
        end

        -- ЛЕВАЯ РУКА ПРИ ДВУРУЧНОМ ОРУЖИИ. Слот левой руки у такого персонажа
        -- пуст, и «прирост против пустого слота» - это вся оценка вещи, то
        -- есть та же ошибка ещё раз. Честное сравнение: пара «лучшее
        -- одноручное из своих + эта вещь» против двуручного, которое придётся
        -- снять.
        if targetSlot == "OFFHAND" and G.OwnedBySlot then
            local twoScore, twoID, bestOne = nil, nil, 0
            for _, e in ipairs(G:OwnedBySlot(snap)["MAINHAND"] or {}) do
                if e.canEquip and not e.tool then
                    local s = G:ItemScore(e.link or e.itemID, snap.weights)
                    if e.twoHand then
                        if e.where == "equipped" then twoScore, twoID = s, e.itemID end
                    elseif s and s > bestOne then
                        bestOne = s
                    end
                end
            end
            if twoID then
                blockedByTwoHand = true
                againstID = twoID
                gain = (twoScore ~= nil) and ((bestOne + score) - twoScore) or nil
            end
        end
        if againstID and G.ItemLabel then againstName = G:ItemLabel(againstID) end
    end
    -- Полбалла - это «+0 баллов» на карточке: улучшением не считается.
    local notUpgrade = ((gain ~= nil and gain <= 0.5) or mainStatDrop) and true or false

    -- ШКОЛА ПРОВЕРЯЕТСЯ, И ПРОВЕРЯЕТСЯ ЧИСЛАМИ.
    --
    -- Справочник H.MF_FIRST_BUYS_ARCANE собран по одному семейству - сайт
    -- называет жемчужный набор арканом. Отбор шёл только по линии навыка, и
    -- чернокнижник-портняжник получал тайную магию, которой не кастует. Это
    -- ровно та ошибка, которую уже починили в весах: «лечение» и чужая школа
    -- считались пользой.
    --
    -- Поэтому здесь не сверяется ни название набора, ни заученный список школ:
    -- берётся школьный урон самого предмета и вес ЭТОГО персонажа на него.
    -- Вес ноль - утверждение «ему это не даёт ничего», и тогда покупка
    -- отбирается из плана (F:Plan), а не выбрасывается молча.
    local schoolAmount, schoolValue, schoolRows = 0, 0, {}
    if stats and ns.StatWeights then
        schoolAmount, schoolValue, schoolRows =
            ns.StatWeights:SchoolValue(stats, snap and snap.weights)
    end
    -- Названия школ - через GearAdvisor:StatLabel, то есть оттуда же, откуда
    -- берутся названия всех остальных характеристик. Второй словарь школ рядом
    -- неизбежно разошёлся бы с первым.
    local schoolText
    if #schoolRows > 0 and ns.GearAdvisor then
        local bits = {}
        for i = 1, math.min(2, #schoolRows) do
            bits[#bits + 1] = "+" .. U.round(schoolRows[i].points) .. " "
                .. tostring(ns.GearAdvisor:StatLabel(schoolRows[i].stat))
        end
        schoolText = table.concat(bits, ", ")
    end

    local reagents = {}
    for id, qty in tostring(entry.reag or ""):gmatch("(%d+):(%d+)") do
        reagents[#reagents + 1] = { itemID = tonumber(id), qty = tonumber(qty) }
    end

    -- УЖЕ ЕСТЬ - ЗНАЧИТ НЕ НАДО ПОКУПАТЬ.
    --
    -- Это не придирка: на настоящих данных первая же карточка советовала
    -- потратить 45 Favor на паттерн Мерцающего посоха, который лежал у игрока
    -- В СУМКЕ. Два разных «уже есть», и путать их нельзя:
    --   * рецепт выучен - паттерн покупать не за чем, предмет уже можно делать;
    --   * сам предмет на руках - второй экземпляр брони магу не нужен.
    local alreadyKnown = (out and ns.RecipeBook and ns.RecipeBook.CanCraft)
        and ns.RecipeBook:CanCraft(out) or false
    local ownedWhere = nil
    if out and snap then
        if (snap.bags or {})[out] then ownedWhere = "bags"
        elseif (snap.bank or {})[out] then ownedWhere = "bank" end
        if not ownedWhere then
            for _, e in pairs(snap.equipped or {}) do
                if tonumber(e.itemID) == out then ownedWhere = "equipped"; break end
            end
        end
    end

    return {
        en = entry.en,
        favor = tonumber(entry.favor),
        alreadyKnown = alreadyKnown,
        ownedWhere = ownedWhere,
        alreadyHave = (alreadyKnown or ownedWhere ~= nil) or false,
        skillLineID = entry.prof,
        skillNeeded = tonumber(entry.skill),
        skill = skill,
        -- УДАЛОСЬ ЛИ СОПОСТАВИТЬ ПРОФЕССИЮ С ПОРОГОМ. Отдельное поле, потому
        -- что «навыка мало» и «я не понял, какой навык смотреть» - разные
        -- ответы, и путать их значит винить игрока в своей слепоте.
        lineResolved = lineResolved and true or false,
        professionName = prof and prof.name or nil,
        -- ГЛАВНОЕ ПОЛЕ ЭТОГО ФАЙЛА: хватает ли НАВЫКА, без оглядки на уровень.
        affordableBySkill = (skill ~= nil and entry.skill ~= nil)
            and (skill >= entry.skill) or nil,
        patternItemID = tonumber(entry.pat),
        outItemID = out,
        name = (info and info.name) or (out and U.itemFallbackName(out)) or entry.en,
        reqLevel = reqLevel,
        wearableNow = wearableNow,
        slot = slot,
        slotLabel = slot and ns.SlotMap:Label(slot) or nil,
        stats = stats, statText = statText, score = score,
        -- Прирост против надетого/лежащего в сумках - см. блок выше. Карточка
        -- обязана показывать ЕГО, а не score.
        gain = gain,
        againstName = againstName,
        notUpgrade = notUpgrade,
        blockedByTwoHand = blockedByTwoHand or false,
        mainStatDrop = mainStatDrop or false,
        -- Школьный урон предмета и чего он стоит по весам персонажа.
        -- schoolOffProfile = «школьный урон на предмете есть, и весит он у
        -- этого персонажа ровно ноль». Числа рядом, чтобы карточка могла
        -- сказать, сколько именно не учтено.
        schoolAmount = schoolAmount,
        schoolValue = schoolValue,
        schoolRows = schoolRows,
        schoolText = schoolText,
        schoolOffProfile = (schoolAmount > 0 and schoolValue <= 0) or false,
        vendors = entry.vend,
        reagents = reagents,
        -- Цена в Favor - со слов сайта, и это надо помнить при любом подсчёте.
        favorConf = CONF.ESTIMATE,
    }
end

-- Весь план покупок, упорядоченный -------------------------------------
--
-- Порядок: сначала то, что навык уже позволяет И что носится прямо сейчас,
-- внутри - по пользе на единицу Favor. Потому что Favor - это время, а польза
-- на единицу времени и есть то, что игрок хочет максимизировать.
-- ЧЬИ ЛИНИИ НАВЫКА ЕСТЬ В ПЛАНЕ, И ЕСТЬ ЛИ ОНИ У ЭТОГО ПЕРСОНАЖА.
--
-- Записи плана размечены номером линии навыка (prof = 197 портняжка, 333 чары).
-- Персонаж, у которого ни той, ни другой нет, получал полный список с пометкой
-- «навыка пока не хватает» у каждой позиции - то есть аддон винил игрока в
-- нехватке навыка по профессии, которой у него и не было. Это разные ответы:
-- «качай навык» и «данных по твоим профессиям у меня нет».
function F:LinesOfCharacter(snap)
    local out = {}
    -- tonumber ДО индексации, а не внутри. `out[tonumber(x)] = true` при
    -- нечисловом x - это `out[nil] = true`, то есть падение на ровном месте.
    -- Сейчас все маршруты Api:Professions кладут туда число, но полагаться на
    -- это нельзя: номер приходит от клиента.
    local function add(id)
        id = tonumber(id)
        if id then out[id] = true end
    end
    for _, prof in ipairs((snap and snap.professions) or {}) do
        for _, id in ipairs(prof.skillLineIDs or {}) do add(id) end
        add(prof.skillLineID)
        -- Номер линии клиент отдаёт не всегда. Тогда сопоставляем так же, как
        -- это делает F:SkillOf - через ForeverSource, которому передаётся ВСЯ
        -- запись профессии, а не одно имя: он сам решает, по номеру ему
        -- отвечать или по имени, и порядок там от сильного к слабому.
        local FS = ns.ForeverSource
        if FS and FS.ResolveSkillLine then
            add(FS:ResolveSkillLine(prof))
        end
    end
    return out
end

function F:Plan(snap)
    snap = snap or (ns.CharacterScanner and ns.CharacterScanner:Get()) or nil
    local H = ns.Horizon
    if not (H and H.MF_FIRST_BUYS_ARCANE) then return nil, "no-data" end

    -- ДАННЫХ ПО ЕГО ПРОФЕССИЯМ НЕТ - ЭТО ОТДЕЛЬНЫЙ ОТВЕТ.
    --
    -- Проверяется ДО сборки списка: иначе алхимик получит план из портняжных
    -- паттернов, у каждого из которых честно написано «навыка пока не хватает»,
    -- и прочитает это как «надо качать навык». Если персонаж вовсе без
    -- профессий (клиент ещё не ответил) - план строится как раньше: молчать на
    -- пустом снимке значило бы прятать ветку до первого открытия окна.
    local mine = F:LinesOfCharacter(snap)
    if next(mine) then
        local any = false
        for _, entry in ipairs(H.MF_FIRST_BUYS_ARCANE) do
            if mine[tonumber(entry.prof)] then any = true; break end
        end
        if not any then return nil, "no-data-for-professions" end
    end

    -- ЗНАЕМ ЛИ МЫ ШКОЛУ ЭТОГО ПЕРСОНАЖА. Спрашивается у самих весов, а не у
    -- названия набора: Data/StatWeights.lua отвечает по числам.
    local certainty = ns.StatWeights and ns.StatWeights.SchoolCertainty
        and ns.StatWeights:SchoolCertainty(snap and snap.weights) or "no-weights"

    local list, offSchool = {}, {}
    local totalFavor, nowCount, nowFavor = 0, 0, 0
    local offFavor = 0
    for _, entry in ipairs(H.MF_FIRST_BUYS_ARCANE) do
        local d = F:Describe(entry, snap)
        if d then
            -- ОТБОР ПО ШКОЛЕ - ЗДЕСЬ, И ТОЛЬКО ПО ЧИСЛАМ.
            --
            -- Покупка, весь школьный урон которой весит у этого персонажа
            -- ноль, в план не идёт: это и есть «жемчужный набор
            -- чернокнижнику». Но она не исчезает - уходит в offSchool, чтобы
            -- карточка могла сказать, сколько позиций отложено и почему.
            if d.schoolOffProfile then
                offSchool[#offSchool + 1] = d
                offFavor = offFavor + (d.favor or 0)
            else
                list[#list + 1] = d
                totalFavor = totalFavor + (d.favor or 0)
                -- «Носится сейчас» - это ещё и «есть смысл надеть»: вещь хуже
                -- надетой в этот счёт не идёт.
                if d.affordableBySkill and d.wearableNow and not d.notUpgrade then
                    nowCount = nowCount + 1
                    nowFavor = nowFavor + (d.favor or 0)
                end
            end
        end
    end
    if #list == 0 then
        -- НИ ОДНОЙ ПОДХОДЯЩЕЙ ПОКУПКИ, И ПРИЧИНА РАЗНАЯ.
        --
        -- «Справочник пуст» и «весь справочник - чужая школа» выглядели
        -- одинаково, а значат разное: во втором случае персонаж и профессия в
        -- порядке, просто данных под его школу у меня нет. Так и надо сказать.
        if #offSchool > 0 then
            local amount, favor = 0, 0
            local names = {}
            for _, d in ipairs(offSchool) do
                amount = amount + (d.schoolAmount or 0)
                favor = favor + (d.favor or 0)
                for _, row in ipairs(d.schoolRows or {}) do names[row.stat] = true end
            end
            local stats = {}
            for stat in pairs(names) do stats[#stats + 1] = stat end
            table.sort(stats)
            return nil, "off-school", {
                count = #offSchool, favor = favor, amount = amount,
                stats = stats, certainty = certainty,
            }
        end
        return nil, "no-entries"
    end

    table.sort(list, function(a, b)
        local an = (a.affordableBySkill and a.wearableNow and not a.notUpgrade) and 1 or 0
        local bn = (b.affordableBySkill and b.wearableNow and not b.notUpgrade) and 1 or 0
        if an ~= bn then return an > bn end
        -- Польза на единицу Favor - это ПРИРОСТ на единицу, а не полная оценка
        -- вещи; без прироста (сравнить было нечем) - полная оценка, без неё -
        -- по порогу навыка, то есть сначала то, что дешевле всего даётся.
        local av = a.gain or a.score
        local bv = b.gain or b.score
        local ap = (av and a.favor and a.favor > 0) and (av / a.favor) or -1
        local bp = (bv and b.favor and b.favor > 0) and (bv / b.favor) or -1
        if ap ~= bp then return ap > bp end
        return (a.skillNeeded or 0) < (b.skillNeeded or 0)
    end)

    return {
        items = list,
        -- Отложенное по школе - рядом с планом, а не выброшено. Карточка
        -- обязана это проговорить: тихо укоротившийся список читается как
        -- «больше ничего и нет».
        offSchool = offSchool,
        offSchoolFavor = offFavor,
        -- "known" / "unknown" / "none" / "no-weights" - см. SW:SchoolCertainty.
        -- Нужно карточке: при "unknown" она говорит, что школу я не определил,
        -- а не делает вид, что определил.
        schoolCertainty = certainty,
        totalFavor = totalFavor,
        wearableNowCount = nowCount,
        wearableNowFavor = nowFavor,
        -- Достоверность плана целиком: не выше оценки, потому что цена в Favor
        -- не проверена в игре.
        conf = CONF.ESTIMATE,
    }
end

-- Как Favor зарабатывается ----------------------------------------------
--
-- Ящики. Один ящик заполняется ЛЮБЫМ ОДНИМ из своих наборов, и материал должен
-- лежать одним стаком - так написано в источнике, и это важно: иначе игрок
-- соберёт по чуть-чуть из трёх наборов и ящик не закроется.
--
-- Считаем только то, что проверяемо: есть ли у игрока нужное количество
-- материала прямо сейчас (сумки, банк, другие персонажи через Syndicator).
function F:EarnRoutes(snap)
    local H = ns.Horizon
    if not (H and H.MF_CRATES) then return {}, "no-data" end
    snap = snap or (ns.CharacterScanner and ns.CharacterScanner:Get()) or nil
    local level = tonumber(snap and snap.level) or 0

    local have = {}
    for itemID, qty in pairs((snap and snap.bags) or {}) do
        have[itemID] = (have[itemID] or 0) + (tonumber(qty) or 0)
    end
    for itemID, qty in pairs((snap and snap.bank) or {}) do
        have[itemID] = (have[itemID] or 0) + (tonumber(qty) or 0)
    end

    local out = {}
    for crateID, crate in pairs(H.MF_CRATES) do
        if crate.bundles and (tonumber(crate.lvl) or 0) <= level then
            for _, bundle in ipairs(crate.bundles) do
                local itemID, need = bundle[1], bundle[2]
                local got = have[itemID] or 0
                if got > 0 then
                    local info = Api:ItemInfo(itemID)
                    out[#out + 1] = {
                        crateID = crateID,
                        rank = crate.rank, kind = crate.kind,
                        favor = crate.favor,          -- nil = источник не знает
                        silver = crate.silver,
                        itemID = itemID,
                        name = (info and info.name) or U.itemFallbackName(itemID),
                        need = need, have = got,
                        ready = (got >= need),
                        short = math.max(0, need - got),
                    }
                end
            end
        end
    end
    table.sort(out, function(a, b)
        -- Сначала то, что можно сдать сразу, потом то, до чего ближе всего.
        if a.ready ~= b.ready then return a.ready end
        if a.short ~= b.short then return a.short < b.short end
        return a.itemID < b.itemID
    end)
    return out
end

-- Сколько Favor можно получить сдав всё готовое прямо сейчас. Ящики с
-- неизвестной наградой считаются отдельно - их нельзя ни сложить, ни забыть.
function F:ReadyFavor(routes)
    local favor, unknown, ready = 0, 0, 0
    local seen = {}
    for _, r in ipairs(routes or {}) do
        -- Один ящик закрывается одним набором: второй набор того же ящика
        -- второй раз не считаем.
        if r.ready and not seen[r.crateID] then
            seen[r.crateID] = true
            ready = ready + 1
            if r.favor then favor = favor + r.favor else unknown = unknown + 1 end
        end
    end
    return favor, unknown, ready
end

-- Текст -----------------------------------------------------------------

-- Чем Favor хорош именно для этого персонажа, одной фразой. Это тот самый
-- вывод, который человек сам не сделает: гейт по навыку, а не по уровню.
function F:HeadlineText(plan, snap)
    local level = tonumber(snap and snap.level) or 0
    local skills = {}
    for _, d in ipairs(plan.items) do
        if d.skill and d.professionName and not skills[d.professionName] then
            skills[d.professionName] = d.skill
        end
    end
    local bits = {}
    for name, skill in pairs(skills) do
        -- Имя профессии - для человека: в раннем состоянии оно приходит из
        -- чужого кеша по-английски (U.profLabel, Core/Util.lua).
        bits[#bits + 1] = tostring(ns.Util.profLabel(name)) .. " " .. tostring(skill)
    end
    table.sort(bits)
    return "Рецепты за Благосклонность торговца открываются по навыку"
        .. " профессии, а не по уровню персонажа. У вас " .. table.concat(bits, ", ")
        .. " при уровне " .. level .. " — значит доступно то, за чем остальные"
        .. " приходят к 35 уровню."
end

-- ЧТО СО ШКОЛОЙ - СЛОВАМИ, И БЕЗ УГАДЫВАНИЯ.
--
-- Три разных ответа, и ни один из них не «набор вам подходит»:
--   * школу персонажа я определил - тогда про неё молчим, отбор уже сделан по
--     весам, и говорить нечего;
--   * школу я НЕ определил - так и сказано: оценка усреднённая по школам, и
--     значит в этом месте мне верить меньше;
--   * часть позиций отложена - сказано, сколько и сколько Favor это было.
--
-- Возвращает nil, когда сказать нечего: пустая фраза на карточке хуже, чем её
-- отсутствие.
function F:SchoolText(plan)
    if type(plan) ~= "table" then return nil end
    local bits = {}
    if plan.schoolCertainty == "unknown" then
        bits[#bits + 1] = "Школу вашего персонажа я не определил — ни по спеку,"
            .. " ни по надетым вещам, — поэтому школьный урон считаю"
            .. " усреднённо, а не как свой."
    elseif plan.schoolCertainty == "no-weights" then
        bits[#bits + 1] = "Профиля весов у вас нет, поэтому школьный урон этих"
            .. " вещей я не оценивал вовсе."
    end
    local off = plan.offSchool or {}
    if #off > 0 then
        local names = {}
        for i = 1, math.min(2, #off) do names[#names + 1] = off[i].name end
        bits[#bits + 1] = #off .. " "
            .. U.plural(#off, "позицию", "позиции", "позиций")
            .. " я отложил: их школьный урон по вашим весам стоит ноль ("
            .. table.concat(names, ", ")
            .. ((#off > 2) and (" и ещё " .. (#off - 2)) or "")
            .. ") — это "
            .. (tonumber(plan.offSchoolFavor) or 0) .. " Favor, которые я вам"
            .. " не предлагаю тратить."
    end
    if #bits == 0 then return nil end
    return table.concat(bits, " ")
end

-- Обязательная оговорка. Цена в Favor и сама механика - со слов сайта
-- сообщества; в игре это не проверено, и прятать такое нельзя.
--
-- АДРЕС ИСТОЧНИКА С КАРТОЧКИ УБРАН, А САМА ОГОВОРКА ОСТАЛАСЬ.
--
-- Было: «…со слов сообщества (theforeverguides.com/professions/merchants-favor
-- (прочитан 2026-11-17); номера ящиков сверены с Polestar_Codex), в игре я
-- этого не проверял. Пороги навыка и реагенты — из баз, которые у вас
-- установлены, и сверены между собой.» Сто с лишним символов из 558 в строке
-- «почему» самой длинной карточки аддона уходили на адрес сайта, дату его
-- чтения и бухгалтерию сверок. Игроку это не отвечает ни на один вопрос: ему
-- важно ОДНО - что число не проверено в игре. Адрес нужен ровно тогда, когда
-- он хочет проверить сам, и для этого есть подсказка под курсором - там же, где
-- стоит достоверность (см. UI/Card.lua, card.sourceNote).
function F:CaveatText()
    return "Сколько это стоит в Favor и сколько Favor даёт ящик — со слов"
        .. " сообщества, в игре я этого не проверял."
end

-- Откуда взяты числа, словами и с адресом. Едет в подсказку, не на карточку.
function F:SourceText()
    local H = ns.Horizon
    local src = (H and H.PROVENANCE and H.PROVENANCE.mfCrates) or "сайт сообщества"
    return "Откуда числа: " .. tostring(src)
        .. ". Пороги навыка и реагенты — из баз, которые у вас установлены."
end

return F
