-- ForeverPilot / Tests/test_live.lua
--
-- Cases taken verbatim off the player's screen, with their numbers. Each one is
-- here because it was observed in a live session rather than reasoned about.
--
-- A NOTE ON THE SESSION THAT PRODUCED MOST OF THESE. The run of 11:57 was
-- reported as "the fixes do not work", and the first thing to establish was
-- whether the code under test was the code on disk. It was not: the session
-- started at 11:06 and every fix in question was written to disk between 11:22
-- and 11:35. The addon reads its Lua once at login. The proof is in the file
-- itself - its `sanityChecks` module carries only `failed/in/out`, while the
-- version from 11:25 also writes `checks`, `ran` and `findings`; and the item
-- database was hit 280 times per rebuild, which is the uncached number.
--
-- So the range-text suites below PASS on the current code, and that is the
-- point of them: they pin behaviour that was fixed but never loaded. The belt
-- suite is different - that one is a real defect, found while checking the
-- player's observation, and it was live in the current code until now.
local H = ...

return function()

local F = H.fixtures()

-- =====================================================================
-- THE FIVE "укладывается в разброс" CARDS, WITH THEIR REAL NUMBERS
-- =====================================================================
--
-- Straight off the screen. In every one the live price is BELOW the whole
-- observed record, and the card said it fell inside it. Two of the five quote a
-- "range" built from a single observation.
local RANGE_CASES = {
    { name = "Венец из ткани Грез",      live = 58900,
      history = { [20773] = 60099, [20774] = 61900 } },
    { name = "Перчатки из ткани Грез",   live = 32000,
      history = { [20773] = 34500, [20774] = 39000 } },
    { name = "Тренировочный жезл",       live = 28000,
      history = { [20773] = 29600, [20774] = 29800 } },
    { name = "Розовая рубашка",          live = 28500,
      history = { [20774] = 34900 } },
    { name = "Рубашка под смокинг",      live = 25000,
      history = { [20774] = 25100 } },
}

H.suite("ЖИВОЕ: пять карточек с «укладывается» — цена вне разброса")
do
    for i, case in ipairs(RANGE_CASES) do
        local env = H.load()
        local ns = env.ns
        local itemID = 900000 + i
        local cfg = ns.Config:Get()
        cfg.priceHistory[itemID] = {}
        for day, copper in pairs(case.history) do
            cfg.priceHistory[itemID][day] = copper
        end

        local st = ns.MarketHistory:Stats(itemID)
        local v = ns.MarketHistory:Verdict(itemID, case.live)

        -- The precondition, so this suite cannot go hollow: the price really is
        -- outside everything observed.
        H.ok(case.live < st.min, string.format(
            "%s: ПРЕДУСЛОВИЕ — %s ниже минимума %s",
            case.name, ns.Util.money(case.live), ns.Util.money(st.min)))

        H.ok(not ns.Util.contains(v.text, "укладывается"), string.format(
            "%s: не сказано «укладывается» — %s", case.name,
            ns.Util.truncate(v.text, 90)))
        H.eq(v.outsideRange, true, case.name .. ": помечено как вне разброса")
        H.eq(v.belowRange, true, case.name .. ": именно ниже")

        -- And the confidence drops, which is what puts "оценка ≈" on the card.
        local _, conf = ns.MarketHistory:Expected(itemID, case.live)
        H.eq(conf, ns.CONF.ESTIMATE, case.name .. ": достоверность понижена")
    end
end

H.suite("ЖИВОЕ: два вырожденных разброса не выдаются за диапазон")
do
    for _, case in ipairs({ RANGE_CASES[4], RANGE_CASES[5] }) do
        local env = H.load()
        local ns = env.ns
        local itemID = 910000
        local cfg = ns.Config:Get()
        cfg.priceHistory[itemID] = {}
        for day, copper in pairs(case.history) do
            cfg.priceHistory[itemID][day] = copper
        end
        local only = select(2, next(case.history))
        local v = ns.MarketHistory:Verdict(itemID, case.live)
        H.eq(v.degenerate, true, case.name .. ": одно наблюдение помечено")
        -- The exact shape of the old lie: "3з 49с..3з 49с".
        local lie = ns.Util.money(only) .. ".." .. ns.Util.money(only)
        H.ok(not ns.Util.contains(v.text, lie), string.format(
            "%s: нет «%s» — %s", case.name, lie, ns.Util.truncate(v.text, 80)))
    end
end

H.suite("ЖИВОЕ: карточка «на продажу» получает «оценка ≈»")
do
    -- End to end, with the Pink Magecloth Shirt numbers: one observation at
    -- 3з 49с, live 2з 85с. The headline must not read as a measured profit.
    local env = H.load()
    local ns = env.ns
    H.item(env, 920001, { name = "Розовая рубашка", sellPrice = 300 })
    H.item(env, 920002, { name = "Материал", sellPrice = 10 })
    env.vendorPrices[920002] = 100
    env.prices[920001] = 28500
    env.money = 500000
    ns.Config:Get().priceHistory[920001] = { [20774] = 34900 }
    H.profession(env, "Портняжное дело", 225, 225, {
        H.recipe { id = 920, output = 920001, name = "Розовая рубашка",
                   reagents = { { itemID = 920002, qty = 1 } },
                   diff = "trivial", category = "Рубашки" },
    })
    local cards = H.build(env)
    local card
    for _, c in ipairs(cards) do
        if c.kind == ns.KIND.CRAFT_PROFIT then card = c end
    end
    H.ok(card ~= nil, "карточка есть")
    if card then
        H.ok(ns.Util.contains(card.benefit, "оценка"), string.format(
            "в заголовке «оценка»: %s", tostring(card.benefit)))
        H.ok(not ns.Util.contains(card.why, "укладывается"),
            "и в объяснении нет ложного «укладывается»")
        H.ok(card.conf == ns.CONF.ESTIMATE or card.conf == ns.CONF.UNKNOWN,
            "достоверность не выше оценки: " .. tostring(card.conf))
    end
end

-- =====================================================================
-- THE BELT: ONE BONUS COUNTED TWICE
-- =====================================================================
--
-- A REAL DEFECT, found by checking the player's observation rather than by
-- reading the code. Card 1 of the live run read "Кушак начинающего чародея …
-- Силы магии по тайной школе: 0 → 8", and the database says item 253885 is
-- sta3 int3 armor17 sp4 heal4 - four, not eight.
--
-- Both halves were right and the sum was wrong. The item database reports
-- `sp = 4`, which is spell DAMAGE. The client reports the same bonus as the
-- combined line ITEM_MOD_SPELL_POWER_SHORT = 4, which in this era means "+4
-- damage AND +4 healing" - one bonus, written two ways. The merge put them
-- under two different canonical keys, SPELLDMG and SPELLPOWER, and the main
-- stat group summed both.
--
-- The consequence was not cosmetic. With the double count the Novice
-- Arcanist's Sash scored 17.79 against the Pearly Sash's 17.69 and won the
-- slot by a tenth of a point. Counted once it scores 11.39 and loses properly.

local SASH_NOVICE = 253885   -- sta3 int3 armor17 sp4 heal4,  ilvl 15
local SASH_PEARLY = 253933   -- sta5 int4 armor22 spArcane7,  ilvl 22

local function beltEnv()
    local env = H.load()
    local ns = env.ns
    env.player.classFile = "MAGE"
    env.player.level = 26
    env.spec = "Тайная магия"
    env.money = 500000
    H.installRealItemDB(env)
    -- The client half, exactly as a real client reports it: base stats plus
    -- the COMBINED spell power line, which is the whole source of the bug.
    env.stats[SASH_NOVICE] = {
        ITEM_MOD_STAMINA_SHORT = 3, ITEM_MOD_INTELLECT_SHORT = 3,
        ITEM_MOD_SPELL_POWER_SHORT = 4,
    }
    env.stats[SASH_PEARLY] = {
        ITEM_MOD_STAMINA_SHORT = 5, ITEM_MOD_INTELLECT_SHORT = 4,
    }
    for _, id in ipairs({ SASH_NOVICE, SASH_PEARLY, 2911 }) do
        local rec = F.Record(id)
        env.items[id] = {
            name = F.RU_NAMES[id] or F.EN_NAMES[id] or ("Предмет #" .. id),
            equipLoc = "INVTYPE_WAIST", reqLevel = rec and rec.req or 0,
            itemLevel = rec and rec.ilvl or 0, quality = rec and rec.quality or 1,
            classID = 4, subclassID = 1, sellPrice = 10,
        }
    end
    env.equipped.WAIST = { itemID = 2911 }
    H.item(env, 930001, { name = "Материал", sellPrice = 5 })
    env.prices[930001] = 10
    env.bags[930001] = 200
    H.profession(env, "Портняжное дело", 225, 225, {
        H.recipe { id = 1257368, output = SASH_NOVICE, name = "Кушак начинающего чародея",
                   reagents = { { itemID = 930001, qty = 1 } },
                   diff = "trivial", category = "Пояса" },
        H.recipe { id = 1257392, output = SASH_PEARLY, name = "Жемчужный кушак",
                   reagents = { { itemID = 930001, qty = 1 } },
                   diff = "trivial", category = "Пояса" },
    })
    H.rescan(env)
    ns.PriceProvider:BeginPass()
    ns.CraftingPlanner:Bind(ns.RecipeBook, ns.PriceProvider):BeginPass()
    ns.GearAdvisor:BeginPass()
    return env
end

H.suite("ЖИВОЕ: совмещённая сила магии не удваивается")
do
    local env = beltEnv()
    local ns = env.ns
    local st = ns.GearAdvisor:ItemStats(SASH_NOVICE)
    H.ok(st ~= nil, "характеристики кушака прочитаны")
    if st then
        H.eq(st[ns.STAT.SPELLDMG], 4, "урон от магии 4 — как в базе")
        H.eq(st[ns.STAT.HEALPOWER], 4, "лечение 4 — как в базе")
        -- The key the client's combined line used to land in, on top.
        H.eq(st[ns.STAT.SPELLPOWER], nil,
            "отдельной «силы магии» больше нет: это та же прибавка, не третья")
    end

    local mains = ns.StatWeights:MainStats("CASTER_ARCANE")
    local sum = 0
    for stat in pairs(mains) do sum = sum + ((st or {})[stat] or 0) end
    H.eq(sum, 4, "главная группа = 4, а не 8")
end

H.suite("ЖИВОЕ: оценки кушаков совпадают с арифметикой")
do
    local env = beltEnv()
    local ns = env.ns
    local w = ns.StatWeights.SETS.CASTER_ARCANE
    local novice = ns.StatWeights:Score(ns.GearAdvisor:ItemStats(SASH_NOVICE) or {}, w)
    local pearly = ns.StatWeights:Score(ns.GearAdvisor:ItemStats(SASH_PEARLY) or {}, w)
    print(string.format("     начинающего %.2f | жемчужный %.2f", novice, pearly))
    -- 3*0.55 + 3*1.00 + 17*0.02 + 4*1.60 = 11.39
    H.near(novice, 11.39, 0.01, "кушак начинающего чародея = 11.39 (было 17.79)")
    -- 5*0.55 + 4*1.00 + 22*0.02 + 7*1.50 = 17.69
    H.near(pearly, 17.69, 0.01, "жемчужный кушак = 17.69")
    H.ok(pearly > novice, "жемчужный выигрывает, как и должен")
end

H.suite("ЖИВОЕ: на пояс предлагается жемчужный кушак")
do
    local env = beltEnv()
    local ns = env.ns
    local snap = ns.CharacterScanner:Get()
    local ups = ns.GearAdvisor:Upgrades(snap, ns.CraftingPlanner)
    local byItem = {}
    for _, up in ipairs(ups) do byItem[up.info.itemID] = up end
    H.ok(byItem[SASH_PEARLY] ~= nil, "жемчужный кушак предложен")
    H.eq(byItem[SASH_NOVICE], nil,
        "кушак начинающего чародея — нет (он слабее, и выбор на слот один)")

    local card
    for _, c in ipairs(H.build(env)) do
        if c.kind == ns.KIND.CRAFT_GEAR and c.itemID == SASH_PEARLY then card = c end
    end
    H.ok(card ~= nil, "и карточка на него построена")
    if card then
        H.ok(ns.Util.contains(card.why, "0 → 7") or ns.Util.contains(card.why, "7"),
            "в тексте настоящая прибавка: " .. ns.Util.truncate(card.why, 120))
    end
end

-- =====================================================================
-- PERFORMANCE IS BEHAVIOUR TOO
-- =====================================================================
--
-- A live session averaged 69 ms a rebuild and peaked at 118. Two things were
-- responsible and both are now contracts rather than hopes, because a cache
-- that quietly stops working looks exactly like a cache that works.

-- ПРИЧИНА, А НЕ ОБЩАЯ ФРАЗА.
--
-- На экране для трёх предметов стояло «внешней базы предметов нет» - и это был
-- неверный диагноз: база была, строк по этим предметам в ней не было. Четыре
-- состояния - четыре разных текста, и каждый проверяется здесь.
H.suite("ЖИВОЕ: почему бонусы не прочитались — четыре разные причины")
do
    local CASES = {
        { code = "no-db", must = "базы предметов нет вовсе", prep = function(e)
            e.itemDBMirror = false
            e.foreignItemStats, e.foreignItemRecords = {}, {}
            -- Базы в игре нет вовсе: убираем сам объект из песочницы, а не
            -- только данные - именно так это выглядит без Polestar_ItemDB.
            H.bindItemDB(e)
            H.item(e, 999002, { name = "Пояс", equipLoc = "INVTYPE_WAIST",
                classID = 4, subclassID = 1 })
            e.stats[999002] = { ITEM_MOD_STAMINA_SHORT = 3 }
            return 999002
        end },
        { code = "loading", must = "ещё не загрузилась", prep = function(e)
            H.installRealItemDB(e)
            e.itemDBLoading = true
            e.ns.Api.itemDBLoadTried = false
            H.useRealItems(e, { 253885 })
            return 253885
        end },
        { code = "not-in-db", must = "нет в базе", prep = function(e)
            H.installRealItemDB(e)
            H.item(e, 999001, { name = "Выдуманный пояс", equipLoc = "INVTYPE_WAIST",
                classID = 4, subclassID = 1 })
            e.stats[999001] = { ITEM_MOD_STAMINA_SHORT = 3 }
            return 999001
        end },
        { code = "no-stats", must = "без характеристик", prep = function(e)
            H.installRealItemDB(e)
            -- «СТРОКА ЕСТЬ, ХАРАКТЕРИСТИК НЕТ» - ЭТО СВОЙСТВО, А НЕ НОМЕР 1131.
            --
            -- Раньше здесь стоял предмет 1131, подобранный по установленной
            -- базе. Стоило набору пойти по другой базе (папка аддона без
            -- соседей - и вместо 10 тысяч строк берётся фикстура на 131), как
            -- предмета 1131 в ней не оказывалось, причина выходила «нет в
            -- базе», и проверка падала - хотя код отвечал правильно. Теперь
            -- предмет с нужным свойством ищется в той базе, которая есть.
            local id = H.findItemInDB(function(rec)
                return type(rec.stats) == "table" and next(rec.stats) == nil
            end)
            if id then
                print("     no-stats: предмет со строкой без характеристик найден в базе — "
                    .. id .. " " .. tostring(H.itemDBName(id) or ""))
            else
                -- В этой базе таких строк нет вовсе. Свойство задаётся явно:
                -- читатель в коде аддона тот же, строка просто своя.
                id = 999003
                e.foreignItemRecords[id] = { id = id, inv = 6, ilvl = 1, req = 0,
                    quality = 1, class = 4, subclass = 1, stats = {} }
                e.foreignItemStats[id] = {}
                H.note("no-stats: в базе, с которой идут тесты, нет ни одной строки"
                    .. " без характеристик — случай проверен на явно заданной строке")
            end
            e.stats[id] = { ITEM_MOD_STAMINA_SHORT = 1 }
            return id
        end },
    }
    for _, case in ipairs(CASES) do
        local env = H.load()
        local ns = env.ns
        env.player.level = 26
        env.player.classFile = "MAGE"
        local itemID = case.prep(env)
        env.equipped.WAIST = { itemID = itemID }
        local snap = ns.CharacterScanner:Scan()
        ns.GearAdvisor:ItemStats(itemID)

        -- Предпосылка: причина действительно та, которую мы собрались печатать.
        H.eq((ns.GearAdvisor.missReasons or {})[case.code], 1,
            case.code .. ": причина записана именно этим кодом")

        ns.SanityChecks:Run({ cards = {}, snap = snap, counts = {}, generated = 0 })
        local said
        for _, e in ipairs(ns.Diag:Init().suspicious or {}) do
            if e.code == "item-bonuses-unreadable" then said = e end
        end
        H.ok(said ~= nil, case.code .. ": предупреждение выдано")
        if said then
            H.ok(ns.Util.contains(said.text, case.must), string.format(
                "%s: сказано «%s» — %s", case.code, case.must,
                ns.Util.truncate(said.text, 100)))
            if case.code ~= "no-db" then
                H.ok(not ns.Util.contains(said.text, "базы предметов нет вовсе"),
                    case.code .. ": не свалено в «базы нет»")
            end
        end
    end
end

-- И то же самое на втором пересчёте: ответ берётся из кеша, но предупреждение
-- не должно исчезать - сравнения по этим вещам по-прежнему неточные.
H.suite("ЖИВОЕ: предупреждение о нечитаемых бонусах не исчезает на втором пересчёте")
do
    local env = H.load()
    local ns = env.ns
    env.player.level = 26
    env.player.classFile = "MAGE"
    H.installRealItemDB(env)
    H.item(env, 999001, { name = "Выдуманный пояс", equipLoc = "INVTYPE_WAIST",
        classID = 4, subclassID = 1 })
    env.stats[999001] = { ITEM_MOD_STAMINA_SHORT = 3 }
    env.equipped.WAIST = { itemID = 999001 }
    ns.CharacterScanner:Scan()

    ns.GearAdvisor:BeginPass()
    ns.GearAdvisor:ItemStats(999001)
    H.eq(ns.GearAdvisor.statsIncomplete, 1, "первый пересчёт: один предмет")
    local firstReads = ns.Api.itemDBReads or 0

    ns.GearAdvisor:BeginPass()
    ns.GearAdvisor:ItemStats(999001)
    H.eq(ns.GearAdvisor.statsIncomplete, 1, "второй пересчёт: всё ещё один")
    H.eq((ns.GearAdvisor.missReasons or {})["not-in-db"], 1,
        "и причина та же")
    H.ok((ns.Api.itemDBReads or 0) <= firstReads,
        "а базу при этом повторно не опрашивали")
end

H.suite("ЖИВОЕ: данные предмета читаются один раз, а не каждый пересчёт")
do
    local env = H.load()
    local ns = env.ns
    H.installRealItemDB(env)
    env.stats[253983] = { ITEM_MOD_STAMINA_SHORT = 12 }

    ns.GearAdvisor:BeginPass()
    ns.Api:BeginPass()
    local first = ns.GearAdvisor:ItemStats(253983)
    H.ok(first ~= nil, "первый раз прочитано")
    local readsAfterFirst = ns.Api.itemDBReads or 0
    H.ok(readsAfterFirst >= 1, "и база была опрошена: " .. readsAfterFirst)

    -- A second pass must not go back to the client or the database.
    ns.GearAdvisor:BeginPass()
    ns.Api:BeginPass()
    local again = ns.GearAdvisor:ItemStats(253983)
    H.ok(again ~= nil, "второй раз тоже получено")
    H.eq(ns.Api.itemDBReads, 0, "но базу больше не опрашивали")
    H.eq(again[ns.STAT.SPELLDMG_ARCANE], 14, "и ответ тот же")
end

H.suite("ЖИВОЕ: неполный ответ перепрашивается по сигналу клиента")
do
    -- The trap this closes: caching an answer built while the client had
    -- nothing would leave the advice permanently blind to that item. Caching
    -- nothing would re-read it on every rebuild. So it IS cached, and listed as
    -- waiting - and the client's own signal drops exactly those entries.
    local env = H.load()
    local ns = env.ns
    H.installRealItemDB(env)
    -- The client knows nothing about this item yet.
    env.stats[253983] = nil

    ns.GearAdvisor:BeginPass()
    ns.Api:BeginPass()
    local partial, _, info = ns.GearAdvisor:ItemStats(253983)
    H.ok(partial ~= nil, "характеристики из базы получены")
    H.eq(info and (info.fromClient or 0), 0, "но клиент не дал ничего")
    H.ok(ns.GearAdvisor.pendingItems ~= nil
         and next(ns.GearAdvisor.pendingItems) ~= nil,
        "предмет записан как ожидающий данных клиента")

    -- Until the signal, the answer is reused: that is the whole saving.
    ns.GearAdvisor:BeginPass()
    ns.Api:BeginPass()
    ns.GearAdvisor:ItemStats(253983)
    H.eq(ns.Api.itemDBReads, 0, "до сигнала базу не опрашиваем заново")

    -- The client delivers. Now the entry must be dropped and re-read.
    env.stats[253983] = { ITEM_MOD_STAMINA_SHORT = 12 }
    local dropped = ns.GearAdvisor:RetryPending()
    H.ok(dropped > 0, "по сигналу сброшено записей: " .. dropped)
    ns.GearAdvisor:BeginPass()
    ns.Api:BeginPass()
    local full, _, info2 = ns.GearAdvisor:ItemStats(253983)
    H.ok((info2 and info2.fromClient or 0) > 0,
        "теперь данные клиента учтены")
    H.eq(full[ns.STAT.STA], 12, "и выносливость взята у клиента")
end

H.suite("ЖИВОЕ: поток «пришли данные предмета» не гонит пересчёты")
do
    -- The client fired GET_ITEM_INFO_RECEIVED 4268 times in one session. An
    -- arriving item name fills a placeholder and almost nothing else, so it
    -- does not deserve the same urgency as the bags changing.
    local env = H.load()
    local ns = env.ns
    ns.Events:Reset()
    H.ok(ns.Events.ITEM_INFO_QUIET_SECONDS > 1, string.format(
        "окно тишины задано: %s с", tostring(ns.Events.ITEM_INFO_QUIET_SECONDS)))

    local runs = 0
    ns.Events:On("recompute", function() runs = runs + 1 end)

    -- Item data alone, over and over.
    for i = 1, 8 do
        ns.Events:OnEvent("GET_ITEM_INFO_RECEIVED")
        H.clock = H.clock + 2            -- two seconds between bursts
        ns.Events:Tick()
    end
    H.ok(runs <= 2, "за 16 секунд потока предметов пересчётов не больше двух: "
        .. runs)

    -- Something that genuinely changes the answer is not held back.
    local before = runs
    H.clock = H.clock + 2
    ns.Events:OnEvent("BAG_UPDATE_DELAYED")
    H.clock = H.clock + 1
    ns.Events:Tick()
    H.ok(runs > before, "а изменение сумок пересчитывается сразу")
end

H.suite("ЖИВОЕ: проверка разумности ловит двойной учёт")
do
    -- The guard, so the same class of error cannot come back silently: one item
    -- may never carry both the combined stat and a separate damage stat.
    local env = H.load()
    local ns = env.ns
    H.ok(ns.SanityChecks:HasCheck("spell-power-double-counted"),
        "проверка на двойной учёт силы магии зарегистрирована")
end

end
