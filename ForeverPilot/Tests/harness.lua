-- ForeverPilot / Tests/harness.lua
--
-- Loads the addon's logic modules in plain Lua 5.1 (the same version WoW runs)
-- with a fake game API, so the business logic can be tested without the game.
--
-- Only the modules that contain no frame code are loaded. The UI is deliberately
-- left out: it is presentation, and it is the one part that genuinely needs the
-- client. Everything that makes a decision is in here.
--
-- Run with:  lua Tests/run.lua

local H = {}

H.ROOT = (function()
    local src = debug.getinfo(1, "S").source:sub(2)
    return src:match("^(.*)[/\\]Tests[/\\]harness%.lua$") or "."
end)()

-- Fake game environment -------------------------------------------------

function H.makeGlobals()
    local G = {
        -- Globals the addon genuinely reads.
        WOW_PROJECT_CAMELOT = 1,
        BACKPACK_CONTAINER = 0,
        NUM_BAG_SLOTS = 4,
        NUM_TOTAL_EQUIPPED_BAG_SLOTS = 4,
        UISpecialFrames = {},
        -- Localised stat strings, exactly as a ruRU client spells them.
        ITEM_MOD_INTELLECT_SHORT = "+%d к интеллекту",
        ITEM_MOD_SPIRIT_SHORT = "+%d к духу",
        ITEM_MOD_STAMINA_SHORT = "+%d к выносливости",
        ITEM_MOD_STRENGTH_SHORT = "+%d к силе",
        ITEM_MOD_AGILITY_SHORT = "+%d к ловкости",
        ITEM_MOD_SPELL_POWER_SHORT = "+%d к силе магии",
        ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "+%d к урону от магии",
        ITEM_MOD_CRIT_SPELL_RATING_SHORT = "+%d к рейтингу крит. удара заклинаний",
        ITEM_MOD_HIT_SPELL_RATING_SHORT = "+%d к рейтингу меткости заклинаний",
        ITEM_MOD_MANA_SHORT = "+%d к мане",
        ITEM_MOD_HEALTH_SHORT = "+%d к здоровью",
        INVTYPE_HEAD = "Голова",
        INVTYPE_CHEST = "Грудь",
        INVTYPE_WRIST = "Запястья",
        INVTYPE_FEET = "Ступни",
        INVTYPE_HAND = "Кисти рук",
        INVTYPE_LEGS = "Ноги",
        INVTYPE_CLOAK = "Спина",
        INVTYPE_WAIST = "Пояс",
        INVTYPE_SHOULDER = "Плечи",
        INVTYPE_NECK = "Шея",
        INVTYPE_WEAPONMAINHAND = "Правая рука",
        INVTYPE_WEAPONOFFHAND = "Левая рука",
        INVTYPE_RANGED = "Дальний бой",
        INVTYPE_2HWEAPON = "Двуручное",
        INVTYPE_SHIELD = "Щит",
        INVTYPE_HOLDABLE = "В левой руке",
        INVTYPE_BODY = "Рубашка",
        INVTYPE_TABARD = "Гербовая накидка",
        INVTYPE_FINGER = "Палец",
        INVTYPE_TRINKET = "Аксессуар",
        INVTYPE_BAG = "Сумка",
        Enum = {
            CraftingReagentType = { Basic = 1, Modifying = 2, Finishing = 3 },
            BankType = { Character = 0, Account = 1 },
            ItemQuality = { Poor = 0, Common = 1, Uncommon = 2, Rare = 3, Epic = 4 },
        },
        -- Номер класса -> (локализованное имя, код). Syndicator отдаёт класс
        -- другого персонажа ЧИСЛОМ, и перевод делает клиент: без этого фейка
        -- ветка «другие персонажи» в тестах не работала бы, хотя в игре
        -- работает. Номера те же, что в игре.
        GetClassInfo = function(classID)
            local map = {
                [1] = { "Воин", "WARRIOR" }, [2] = { "Паладин", "PALADIN" },
                [3] = { "Охотник", "HUNTER" }, [4] = { "Разбойник", "ROGUE" },
                [5] = { "Жрец", "PRIEST" }, [6] = { "Рыцарь смерти", "DEATHKNIGHT" },
                [7] = { "Шаман", "SHAMAN" }, [8] = { "Маг", "MAGE" },
                [9] = { "Чернокнижник", "WARLOCK" }, [11] = { "Друид", "DRUID" },
            }
            local e = map[tonumber(classID) or 0]
            if not e then return nil end
            return e[1], e[2], tonumber(classID)
        end,
        GetTime = function() return H.clock end,
        GetServerTime = function() return H.serverTime end,
        print = function(...)
            if H.verbose then print("[game]", ...) end
        end,
        -- UnitName НА FOREVER ОТДАЁТ ДВА ЗНАЧЕНИЯ: имя и ФАМИЛИЮ. На обычном
        -- клиенте второе значение - реалм, и у самого игрока оно nil. Фейк
        -- ведёт себя так же, чтобы адаптер проверялся на настоящей форме
        -- ответа: H.unitNameSecond задаёт, что вернуть вторым.
        UnitName = function(unit)
            if unit == "player" then
                return H.unitNameFirst, H.unitNameSecond
            end
            return H.unitNameNpc
        end,
        GetRealmName = function() return H.realmName end,
        GetNormalizedRealmName = function() return H.realmNormalized end,
    }
    G._G = G
    return G
end

-- Что отдаёт фейковый UnitName("player"). Значения по умолчанию - обычный
-- клиент: имя есть, второго значения нет.
H.unitNameFirst = "Тест"
H.unitNameSecond = nil
H.unitNameNpc = nil
H.realmName = "CAMWOW EU5 Realm 4 PvP"
H.realmNormalized = "CAMWOWEU5Realm4PvP"

-- Module loading --------------------------------------------------------

H.LOGIC_FILES = {
    "Core/Const.lua",
    "Core/Util.lua",
    "Core/Diag.lua",
    "Core/Geo.lua",
    "Core/Api.lua",
    "Core/Config.lua",
    "Core/Events.lua",
    "Data/SlotMap.lua",
    "Data/StatWeights.lua",
    "Data/ForeverSource.lua",
    "Data/Horizon.lua",
    "Data/Camp.lua",
    "Logic/RecipeBook.lua",
    "Logic/Roster.lua",
    "Logic/CharacterScanner.lua",
    "Logic/MarketHistory.lua",
    "Logic/Ledger.lua",
    "Logic/PriceProvider.lua",
    "Logic/Risk.lua",
    "Logic/CraftingPlanner.lua",
    "Logic/GearAdvisor.lua",
    "Logic/EnchantAdvisor.lua",
    "Logic/Places.lua",
    "Logic/ShoppingList.lua",
    "Logic/Dismissal.lua",
    "Logic/SanityChecks.lua",
    "Logic/SourceCheck.lua",
    "Logic/Appearance.lua",
    "Logic/Foresight.lua",
    "Logic/ActionEngine.lua",
    "Logic/VendorArbitrage.lua",
    "Logic/Favor.lua",
    "Logic/CampAdvisor.lua",
    "Logic/UpgradePaths.lua",
    "Logic/CrossCharacter.lua",
    "Logic/Disenchant.lua",
    "Logic/Resale.lua",
    "Logic/AuctionMoment.lua",
    "Logic/Notifier.lua",
    "Logic/Provenance.lua",
}

-- Build a fresh addon namespace with a fresh fake client behind it.
function H.load(opts)
    opts = opts or {}
    H.clock = 1000
    H.serverTime = opts.serverTime or 1794800000
    H.verbose = opts.verbose

    local G = H.makeGlobals()
    local ns = {}

    -- The sandbox: addon files see our fake globals, and fall through to the
    -- real Lua standard library for things like table and string.
    local sandbox = setmetatable({}, {
        __index = function(t, k)
            local v = G[k]
            if v ~= nil then return v end
            return _G[k]
        end,
        __newindex = function(t, k, v) G[k] = v end,
    })

    for _, rel in ipairs(H.LOGIC_FILES) do
        local path = H.ROOT .. "/" .. rel
        local chunk, err = loadfile(path)
        if not chunk then error("не загрузился " .. rel .. ": " .. tostring(err)) end
        setfenv(chunk, sandbox)
        local ok, loadErr = pcall(chunk, "ForeverPilot", ns)
        if not ok then error("ошибка при загрузке " .. rel .. ": " .. tostring(loadErr)) end
    end

    -- SourceCheck subscribes itself to "recompute" when it loads, so that the
    -- addon needs no bootstrap edit. In the tests that would run the whole
    -- source comparison on every single build and fill other suites' assertions
    -- with its findings, so the subscription is dropped here. Tests that want
    -- it call ns.SourceCheck directly, which is what test_audit does.
    if ns.Events and ns.Events.listeners then
        ns.Events.listeners.recompute = nil
        ns.Events.listeners.merchant = nil
        -- AuctionMoment и Notifier тоже подписываются сами (Bind вызывается из
        -- Main). В тестах подписка снимается по той же причине: иначе каждый
        -- build начинал бы писать игроку в чат из чужого набора.
        ns.Events.listeners.auction = nil
        ns.Events.listeners.skill = nil
    end
    if ns.AuctionMoment then
        ns.AuctionMoment.bound = false
        ns.AuctionMoment.atAuction = false
        ns.AuctionMoment.toldThisVisit = false
        ns.AuctionMoment.visits = 0
    end
    if ns.Notifier then
        ns.Notifier.bound = false
        ns.Notifier.told = {}
        ns.Notifier.lastStaleAt = nil
    end
    -- Книга закупок тоже подписывается сама (Bind зовётся из Main). В тестах
    -- подписка снимается вместе с остальными выше: иначе каждый build начинал
    -- бы сверять мир и писать в книгу из чужого набора. Наборы, которым нужна
    -- именно подписка, зовут ns.Ledger:Bind() сами.
    if ns.Ledger then
        ns.Ledger.bound = false
        ns.Ledger:Reset()
    end

    -- A fresh diagnostics store per load, so one test's suspicions never leak
    -- into another's assertions.
    G.FOREVERPILOT_DIAG = {}
    ns.Diag.session = nil
    ns.Diag:Bind(G.FOREVERPILOT_DIAG)

    ns.Config:Bind({}, {})
    H.setMoneyFloor(ns, opts.moneyFloor)
    ns.Api:Detect()

    local env = { ns = ns, G = G, sandbox = sandbox }
    H.installFakes(env, opts)
    return env
end

-- ПОРОГ МЕЛКОЙ ДЕНЕЖНОЙ ВЫГОДЫ В ВЫДУМАННЫХ МИРАХ СНЯТ, И ЭТО СКАЗАНО ЗДЕСЬ.
--
-- В игре порог включён по умолчанию (Config.DEFAULTS.show.moneyFloorMode =
-- "level", полосы и числа - в Core/Const.lua). В фикстурных мирах этого набора
-- деньги игрушечные: жезл за 5 медных, хлам на десятки медяков, прибыль с
-- крафта в 1-2 серебра при персонаже 26 уровня. На настоящих данных игрока того
-- же порядка советы стоят 4с..98с, то есть фикстуры занижены в десятки раз, и
-- рабочий порог срезал бы в них ровно то, что эти наборы проверяют, - механику,
-- а не суммы. Тридцать проверок стали бы красными не потому, что что-то
-- сломано.
--
-- Поэтому порог здесь снимается ОДНОЙ строкой и НЕ МОЛЧА:
--
--   * сам порог проверяется там, где суммы настоящие или заданы нарочно:
--     Tests/test_economy.lua (раздел про полосы по уровню, все три полосы и все
--     пять денежных веток), Tests/test_vanish.lua (перечень путей исчезновения)
--     и проверки «на настоящих данных» в Tests/test_real.lua;
--   * значение по умолчанию тоже проверяется - отдельным утверждением в
--     Tests/test_economy.lua: подмена здесь не может спрятать его смену;
--   * Tests/test_vanish.lua держит число таких подмен в наборе равным одной:
--     второй такой строки появиться не может.
--
-- `want`: nil - снять порог (поведение по умолчанию для фикстур);
--         "default" - оставить ровно то, что стоит в игре;
--         число - поставить это число медью на все уровни.
function H.setMoneyFloor(ns, want)
    if want == "default" then return "default" end
    if type(want) == "number" then
        ns.Config:SetMoneyFloorMode(ns.MONEY_FLOOR_MODE.FIXED)
        ns.Config:SetMoneyFloorOwn(want)
        return "fixed"
    end
    ns.Config:SetMoneyFloorMode(ns.MONEY_FLOOR_MODE.OFF)
    return "off"
end

-- Fakes -----------------------------------------------------------------

-- Replace the adapter's game-facing functions with ones driven by plain tables.
-- Everything above the adapter is the real production code.
function H.installFakes(env, opts)
    local ns, G = env.ns, env.G
    local Api = ns.Api

    -- The production implementations, kept before they are replaced, so a test
    -- can exercise the real adapter logic (container arithmetic, GUID checks)
    -- instead of only the fake standing in for it.
    env.real = {}
    for _, name in ipairs({
        "BankCounts", "BagCounts", "Equipped", "MastercraftRecipes",
        "MastercraftVendorPrice", "MastercraftObservedPrice", "MerchantItems",
        "AuctionPrice", "ReadAuctionPrice", "ItemInfo", "ItemStatsRaw", "ReadRecipe",
        -- The profession reader is the production route table (C_SkillInfo ->
        -- GetProfessions -> ... -> MastercraftDB). Tests that care about WHICH
        -- route answered restore this one instead of using the fake.
        "Professions",
        -- Отчёт «что игра мне сообщает». Стенд подменяет его пустым списком, и
        -- из-за этого раздел настроек и команда /fp api не показывали в тестах
        -- НИ ОДНОЙ строки - а в игре состояли из имён функций. Собрание текстов
        -- (Tests/corpus.lua) возвращает настоящий в одном из состояний мира.
        "Report",
    }) do
        env.real[name] = Api[name]
    end

    env.items = {}      -- itemID -> info table (our ItemInfo shape)
    env.stats = {}      -- itemID -> raw client-style stat table
    env.recipes = {}    -- professionName -> { list = { ... } }
    env.bags = {}       -- itemID -> qty
    -- ПРИВЯЗАНА ЛИ ВЕЩЬ В СУМКЕ: itemID -> true / false. По умолчанию ЗДЕСЬ
    -- НИЧЕГО, и это не лень: nil значит «клиент не сказал», и проверка облика
    -- обязана уметь отвечать и в этом состоянии. Настоящий клиент это поле
    -- отдаёт (в сохранёнке Syndicator у игрока isBound стоит у каждой ячейки).
    env.bagBound = {}
    env.bank = nil      -- itemID -> qty, or nil for "never seen"
    env.equipped = {}   -- slotKey -> { itemID, link, enchantID }
    env.prices = {}     -- itemID -> copper (auction)
    env.vendorPrices = {}
    env.money = 0
    env.player = { name = "Тест", level = 26, classFile = "MAGE", className = "Маг",
                   raceName = "Тролль", factionFile = "Horde", guid = "Player-1-1",
                   realm = "Test" }
    env.professions = {}
    env.spec = nil
    env.auctionator = true
    -- Navigation inputs. nil facing models a client that will not say which way
    -- the player is looking, which is a normal state in some instances.
    env.playerMap = nil        -- { mapID, x, y, zone }
    env.facing = nil
    env.worldSizes = {}        -- mapID -> { width, height }
    env.tomtom = false
    env.tomtomCalls = {}
    env.npcUnit = nil          -- { id, name }

    function Api:Now() return H.clock end
    function Api:ServerTime() return H.serverTime end
    function Api:InCombat() return env.inCombat and true or false end
    function Api:IsForever() return true end
    function Api:Locale() return "ruRU" end
    -- Вывод в чат подменяется ШВОМ, а не методом целиком: сворачивание
    -- повторов живёт в производственном Api:Print, и подмена метода уносила бы
    -- его вместе с собой.
    Api:InjectPrinter(function(line)
        env.said = env.said or {}
        env.said[#env.said + 1] = line
        if H.verbose then print("[fp]", line) end
    end)

    -- Производственный Api:PlayerInfo сохраняется ДО подмены, чтобы адаптер
    -- можно было проверить по-настоящему: фамилия персонажа приходит вторым
    -- значением UnitName, и единственное место, где это читается, - именно он.
    -- Без этого правка «читать фамилию» осталась бы непроверенной, а на ней
    -- держится всё различение одноимённых персонажей.
    H.productionPlayerInfo = Api.PlayerInfo
    function Api:PlayerInfo()
        local p = {}
        for k, v in pairs(env.player) do p[k] = v end
        p.conf = ns.CONF.EXACT
        -- Полное имя собирается там же, где в игре: фейк не должен знать
        -- правило склейки, иначе тест проверял бы сам себя.
        if Api.FullName then p.fullName = Api:FullName(p.name, p.surname) end
        return p
    end
    function Api:PlayerGUID() return env.player.guid end
    function Api:Money() return env.money, ns.CONF.EXACT end
    function Api:SpecInfo()
        if env.spec then return { name = env.spec, conf = ns.CONF.ESTIMATE } end
        return { conf = ns.CONF.UNKNOWN }
    end
    -- ПУСТОЙ СПИСОК ПРОФЕССИЙ - ЭТО «НЕ ЗНАЮ», А НЕ «ИХ НЕТ».
    --
    -- Фейк отдавал CONF.EXACT всегда, в том числе на пустом списке, а
    -- производственный Api:Professions начинает с conf = CONF.UNKNOWN и
    -- поднимает её только когда хоть один маршрут что-то вернул (Core/Api.lua,
    -- `if #out > 0 then conf = CONF.EXACT`). Расхождение прятало целое
    -- состояние игры - раннее, до того как клиент отдал список, - и в нём
    -- Logic/Roster.lua стирал запомненные профессии персонажа, считая пустой
    -- ответ утверждением.
    function Api:Professions()
        local out = {}
        for _, p in ipairs(env.professions) do
            local copy = {}
            for k, v in pairs(p) do copy[k] = v end
            copy.conf = copy.conf or ns.CONF.EXACT
            copy.route = env.professionRoute or "fake"
            if copy.skillTrusted == nil then copy.skillTrusted = true end
            out[#out + 1] = copy
        end
        local conf = (#out > 0) and ns.CONF.EXACT or ns.CONF.UNKNOWN
        return out, conf, env.professionRoute or "fake"
    end

    -- The fakes report into Diag exactly as the real adapter does, so the
    -- diagnostics pipeline is exercised offline instead of only in game.
    -- ПОДМЕНЯЕТСЯ ТОЛЬКО ЧТЕНИЕ У КЛИЕНТА, А НЕ ВЕСЬ Api:ItemInfo.
    --
    -- Раньше фейк заменял метод целиком - вместе с кешем, промахами и
    -- счётчиками, то есть именно с тем, от чего зависит скорость в игре. Из-за
    -- этого офлайновый замер показывал «5.9 мс», а живой пересчёт стоил 35 мс и
    -- 235 обращений к клиенту за предметами. Теперь в тестах работает
    -- производственный учёт, а фейк отвечает ровно как C_Item.GetItemInfo:
    -- кортежем значений.
    ns.Api:InjectItemReader(function(key)
        local itemID = type(key) == "number" and key or ns.Util.itemIDFromLink(key)
        local info = itemID and env.items[itemID] or nil
        if not info then return nil end
        env.itemReads = (env.itemReads or 0) + 1
        local link = info.link or ("|Hitem:" .. itemID .. "::::::::26:1482:::::::::|h["
            .. (info.name or ("Предмет " .. itemID)) .. "]|h|r")
        -- Размер стопки отдельной переменной, а не выражением в кортеже:
        -- `(info.noStackCount and nil) or info.stackCount or 20` даёт 20,
        -- потому что `or` продолжает цепочку после nil. См. комментарий ниже.
        local stackCount = info.stackCount or 20
        if info.noStackCount then stackCount = nil end
        return info.name or ("Предмет " .. itemID),
               link,
               info.quality or 1,
               info.itemLevel,
               info.reqLevel or 0,
               info.className,
               info.subclassName,
               -- РАЗМЕР СТОПКИ, КОТОРЫЙ КЛИЕНТ НЕ НАЗВАЛ, - ЭТО nil, А НЕ 20.
               --
               -- Двадцать по умолчанию удобно почти везде, но есть состояние, в
               -- котором подстановка скрывает проверку: клиент потерял предмет
               -- из кеша и размера стопки не знает. От этого состояния зависит
               -- Planner:SaleShape («расходник или вещь»), и без возможности
               -- его выразить правило «не знаю - значит не знаю» проверить
               -- нечем. `noStackCount = true` в фикстуре и означает «не назвал».
               stackCount,
               info.equipLoc,
               info.texture,
               info.sellPrice or 0,
               info.classID,
               info.subclassID,
               info.bindType
    end)

    -- ОТВЕТА ПРО ОБЛИК В СТЕНДЕ НЕТ, ПОКА ЕГО НЕ ПОПРОСЯТ ЯВНО.
    --
    -- Офлайн клиента нет, значит нет и ответа «собран ли облик»: его здесь не
    -- может знать никто. Поэтому шва по умолчанию нет вовсе, и адаптер в стенде
    -- честно отвечает «не знаю». Набор, которому нужен определённый ответ,
    -- просит его сам - и тогда в самом наборе видно, что ответ ПОДСТАВЛЕН, а не
    -- получен от игры. Заглушка, молча отвечающая «облик собран», превратила бы
    -- всю проверку в её отсутствие.
    --
    --   H.setAppearances(env, {
    --       rule = true,                    -- трансмог включён
    --       collected = { [123] = false },  -- облик этой вещи НЕ собран
    --       noLook = { [456] = true },      -- у этой вещи облика не бывает
    --   })
    --
    -- Чего нет в `collected`, про то фальшивый клиент отвечает «не знаю» - то
    -- же, что настоящий, пока предмет не в кеше.
    env.appearanceReads = 0
    env.appearances = nil

    function H.setAppearances(e, spec)
        e.appearances = spec
        if not spec then
            e.ns.Api:InjectTransmogReader(nil)
            return
        end
        local function idOf(key)
            if type(key) == "number" then return key end
            return e.ns.Util.itemIDFromLink(key)
        end
        e.ns.Api:InjectTransmogReader({
            rule = function()
                return spec.rule
            end,
            source = function(key)
                e.appearanceReads = (e.appearanceReads or 0) + 1
                local id = idOf(key)
                if not id then return nil, nil end
                if spec.noLook and spec.noLook[id] then return nil, 0 end
                -- Номер облика и номер источника выдуманы, но выдуманы
                -- ОДИНАКОВО: по ним проверяется, что ответ про одну вещь не
                -- уехал к другой.
                return id * 10, id
            end,
            collected = function(sourceID)
                e.appearanceReads = (e.appearanceReads or 0) + 1
                if not spec.collected then return nil end
                return spec.collected[tonumber(sourceID) or -1]
            end,
            sourceInfo = spec.sourceInfo,
        })
    end

    function Api:ItemStatsRaw(key)
        local itemID = type(key) == "number" and key or ns.Util.itemIDFromLink(key)
        local s = env.stats[itemID]
        if not s then
            ns.Diag:Call("C_Item.GetItemStats", false,
                "характеристик нет (в SavedVariables их не бывает вообще)")
            return nil, ns.CONF.UNKNOWN
        end
        ns.Diag:Call("C_Item.GetItemStats", true)
        return s, env.statConf or ns.CONF.EXACT
    end

    -- The foreign item database, which on this client is the ONLY source of
    -- equip bonuses: the client reports base stats and nothing else. Keys are
    -- that database's own vocabulary (sta/int/armor/sp/heal/spArcane/...).
    --
    -- `itemDBMirror` is on by default and makes the fake database know exactly
    -- what the fake client knows. That is what keeps the older fixtures honest:
    -- they describe items whose whole stat list the client reported, and on a
    -- real client an item like that has a row in the item database too. A test
    -- that wants the blind case - bonuses nobody can read, which is what made
    -- the addon recommend a downgrade - turns mirroring off.
    env.foreignItemStats = {}
    env.foreignItemRecords = {}
    env.bagEnchant = {}   -- itemID -> enchantID у вещи, лежащей в сумке
    env.bagLinks = {}     -- itemID -> настоящая ссылка из кеша инвентаря
    env.foreignItemSources = {}
    env.itemDBMirror = true

    -- canonical stat -> the foreign database's own key, built from the
    -- production mapping so the two cannot drift apart.
    local foreignKeyOf
    local function reverseForeign()
        if foreignKeyOf then return foreignKeyOf end
        foreignKeyOf = {}
        for key, stat in pairs(ns.StatWeights.FOREIGN_KEY_TO_STAT) do
            if foreignKeyOf[stat] == nil then foreignKeyOf[stat] = key end
        end
        return foreignKeyOf
    end

    local function mirrored(itemID)
        local raw = env.stats[itemID]
        if not raw then return nil end
        local rev = reverseForeign()
        local out
        for clientKey, value in pairs(raw) do
            local stat = ns.StatWeights.CLIENT_KEY_TO_STAT[clientKey]
            local fkey = stat and rev[stat]
            if fkey then
                out = out or {}
                out[fkey] = (out[fkey] or 0) + value
            end
        end
        return out
    end
    -- Доступно и снаружи: объект базы собирается из этих же данных.
    env.mirrorStats = mirrored

    -- ВНЕШНЯЯ БАЗА ПОДСТАВЛЯЕТСЯ КАК БАЗА, А НЕ КАК ОТВЕТ.
    --
    -- Раньше фейк заменял Api:ForeignItemStats целиком - то есть вместе с
    -- кешем, счётчиками и кодами причин. Из-за этого в тестах нельзя было ни
    -- увидеть «базу спросили дважды», ни получить состояния «грузится» и «в
    -- строке нет характеристик»: они рождаются в производственном читателе.
    -- Теперь в песочницу кладётся объект Polestar.ItemDB с методом Get - ровно
    -- то, что аддон ищет в игре, - и весь учёт работает настоящий.
    env.itemDBRecords = env.itemDBRecords or nil
    H.bindItemDB(env)

    function Api:ForeignItemSources(itemID)
        return env.foreignItemSources and env.foreignItemSources[itemID] or nil
    end

    function Api:BagCounts()
        local counts, slots = {}, {}
        for itemID, qty in pairs(env.bags) do
            counts[itemID] = qty
            local info = env.items[itemID]
            -- Ссылка, как её отдаёт настоящий C_Container.GetContainerItemInfo:
            -- в ней едут чары, и без неё нельзя увидеть, что вещь в сумке уже
            -- зачарована. env.bagEnchant[itemID] вшивает чару в ссылку - ровно
            -- так она выглядит в данных игрока (|Hitem:249392:8217:...).
            -- Настоящая ссылка из кеша инвентаря, если тест её дал: в ней
            -- едут чары этой КОНКРЕТНОЙ вещи в сумке.
            local link = (env.bagLinks and env.bagLinks[itemID])
                or (info and info.link) or nil
            local ench = env.bagEnchant and env.bagEnchant[itemID] or nil
            if ench then
                link = "|Hitem:" .. itemID .. ":" .. ench
                    .. "::::::26:1482:::::::::|h["
                    .. ((info and info.name) or ("Предмет " .. itemID)) .. "]|h|r"
            elseif not link then
                local full = Api:ItemInfo(itemID)
                link = full and full.link or nil
            end
            -- ОДИН ПРЕДМЕТ МОЖЕТ ЛЕЖАТЬ В НЕСКОЛЬКИХ ЯЧЕЙКАХ, И ЭТО НЕ РЕДКОСТЬ.
            --
            -- Здесь на каждый предмет создавалась РОВНО ОДНА ячейка, и целый
            -- класс находок был невидим: у игрока «Отрубленный коготь» лежал в
            -- двух ячейках, и перечисление хлама называло его дважды подряд -
            -- «Отрубленный коготь, Отрубленный коготь и ещё 8». В выдуманном
            -- мире такого состояния не существовало вовсе, и ни одно правило
            -- его не читало.
            --
            -- env.bagStacks[itemID] = { 5, 3 } - две ячейки; сумма обязана
            -- совпадать с env.bags[itemID], иначе мир противоречив.
            local stacks = env.bagStacks and env.bagStacks[itemID]
            if type(stacks) ~= "table" then stacks = { qty } end
            for _, part in ipairs(stacks) do
                slots[#slots + 1] = {
                    bag = 0, slot = #slots + 1, itemID = itemID,
                    qty = tonumber(part) or 1,
                    link = link,
                    quality = info and info.quality or 1,
                    noValue = info and info.noValue or false,
                    -- Привязана ли вещь в ячейке. Настоящий клиент отвечает
                    -- по каждой ячейке; nil - «не сказал», и это состояние
                    -- в стенде тоже должно быть выразимо.
                    bound = env.bagBound and env.bagBound[itemID],
                }
            end
        end
        ns.Diag:Call("C_Container.GetContainerItemInfo", #slots > 0,
            "занятых ячеек: " .. #slots)
        return counts, ns.CONF.EXACT, slots
    end

    function Api:BankCounts()
        if env.bank == nil then
            ns.Diag:Call("C_Bank / банковские контейнеры", false,
                "банк ни разу не открывали в этой сессии")
            return nil, ns.CONF.UNKNOWN
        end
        local copy = {}
        for k, v in pairs(env.bank) do copy[k] = v end
        ns.Diag:Call("C_Bank / банковские контейнеры", true,
            "видов предметов в банке: " .. ns.Util.count(copy))
        return copy, ns.CONF.EXACT
    end

    function Api:Equipped()
        local out = {}
        for slot, e in pairs(env.equipped) do
            local info = env.items[e.itemID]
            out[slot] = {
                slot = slot, itemID = e.itemID, enchantID = e.enchantID,
                link = e.link or (info and Api:ItemInfo(e.itemID).link) or nil,
            }
        end
        ns.Diag:Call("GetInventoryItemLink", ns.Util.count(out) > 0,
            "слотов занято: " .. ns.Util.count(out))
        return out, ns.CONF.EXACT
    end

    function Api:AuctionatorPresent() return env.auctionator and true or false end
    -- Mirrors the real adapter's contract, not just its happy path: a
    -- non-positive number is not a price, and an old one is only an estimate.
    -- Without those two rules the fake was kinder than the game and the tests
    -- proved less than they looked.
    -- Подменяется ЧТЕНИЕ цены, а не Api:AuctionPrice: сверху лежит память на
    -- один пересчёт, и она должна работать в тестах так же, как в игре.
    function Api:ReadAuctionPrice(itemID)
        if not env.auctionator then
            ns.Diag:Call("Auctionator.API.v1.GetAuctionPriceByItemID", nil,
                "Auctionator не загружен")
            return nil, ns.CONF.UNKNOWN
        end
        local p = tonumber(env.prices[itemID])
        if not p or p <= 0 then
            ns.Diag:Call("Auctionator.API.v1.GetAuctionPriceByItemID", false,
                "цены по этому предмету нет")
            return nil, ns.CONF.UNKNOWN
        end
        ns.Diag:Call("Auctionator.API.v1.GetAuctionPriceByItemID", true)
        -- ВОЗРАСТ ЗАДАЁТСЯ В ДНЯХ, КАК У НАСТОЯЩЕГО AUCTIONATOR.
        --
        -- Его GetAuctionAgeByItemID возвращает ДНИ (внутри GetScanDay() минус
        -- последний день наблюдения), а фейк раньше отдавал секунды - и тем
        -- самым скрывал ровно ту ошибку, из-за которой цена двухдневной
        -- давности печаталась как «2 минуты назад». Теперь фейк врёт так же,
        -- как врёт игра: env.priceAgeDays - дни, перевод в секунды делает
        -- производственный код.
        --
        -- env.priceAge (в секундах) оставлен для наборов, написанных до этого:
        -- они задают возраст прямо, и для них ничего не меняется.
        local age, ageDays
        if env.priceAgeDays ~= nil then
            ageDays = tonumber(env.priceAgeDays)
            age = ageDays and (ageDays * 86400) or nil
        else
            age = env.priceAge or 3600
        end
        local conf = ns.CONF.CACHED
        if age and age >= ns.PRICE_STALE_SECONDS then conf = ns.CONF.ESTIMATE end
        return p, conf, age, true, ageDays
    end
    function Api:VendorPrice(itemID)
        local p = env.vendorPrices[itemID]
        if not p then return nil, ns.CONF.UNKNOWN end
        return p, ns.CONF.CACHED
    end
    function Api:DisenchantPrice() return nil, ns.CONF.UNKNOWN end
    function Api:MastercraftDB() return env.foreignDB end
    function Api:MastercraftRecipes(guid) return env.foreignRecipes, guid end
    function Api:MastercraftVendorPrice(itemID)
        local p = env.foreignVendorPrices and env.foreignVendorPrices[itemID]
        if not p then return nil, ns.CONF.UNKNOWN end
        return p, ns.CONF.CACHED
    end
    -- НАБЛЮДЁННАЯ ЦЕНА: фейк только там, где настоящей таблицы лотов нет.
    --
    -- Подмена целиком уносила вместе с собой и разбор лотов (деление на `q`,
    -- пропуск «сделано мной»), и память ответов - то есть ровно то, что стоит
    -- денег и ровно то, что надо проверять. Когда тест дал настоящий кеш
    -- (env.foreignDB.costs, как делает набор на живых данных), работает
    -- производственный читатель; синтетическим мирам достаётся короткий фейк.
    local productionObserved = Api.MastercraftObservedPrice
    function Api:MastercraftObservedPrice(itemID, realmKey)
        local db = env.foreignDB
        if type(db) == "table" and type(db.costs) == "table" then
            return productionObserved(self, itemID, realmKey)
        end
        local p = env.observedPrices and env.observedPrices[itemID]
        if not p then return nil, ns.CONF.UNKNOWN end
        return p, ns.CONF.CACHED, 7200
    end
    function Api:SyndicatorPresent() return env.syndicator and true or false end
    function Api:SyndicatorCharacters() return env.altNames end
    function Api:SyndicatorCharacter(name) return env.altData and env.altData[name] end
    -- Передача списка в Auctionator НЕ подменяется: Api:AuctionatorSearchRoute,
    -- AuctionHouseOpen, AuctionatorShoppingTab и AuctionatorSearchItems в тестах
    -- работают настоящие, а отвечает им поддельный Auctionator в песочнице
    -- (env.G.Auctionator, env.G.AuctionHouseFrame, env.G.AuctionatorTabs_Shopping).
    -- Раньше здесь стояли три подмены, которые всегда отвечали «нет», - и код
    -- передачи в тестах не выполнялся ни разу.
    -- ЗАЩИЩЁННЫЙ ВЫЗОВ - МЫШЕЛОВКА, А НЕ ПОДМЕНА АДАПТЕРА.
    --
    -- Раньше здесь подменялся сам адаптер (Api:ShowRecipe), и проверялось,
    -- доходит ли дело до него. Это оказалось слишком высоко: вызов, который
    -- игра блокирует, - C_TradeSkillUI.OpenRecipe, и обвиняет игра аддон за
    -- него, а не за наш метод. Поэтому ловушка стоит на САМОЙ ФУНКЦИИ КЛИЕНТА,
    -- в песочнице: кто бы и откуда её ни позвал - через адаптер, напрямую, из
    -- кнопки, щелчка или панели - обращение попадёт в env.openRecipeCalls.
    --
    -- Клиент при этом отвечает ровно так, как ответил у игрока: НИЧЕГО. Он не
    -- бросает ошибку - он просто не делает того, о чём просят, и показывает
    -- игроку окно про блокировку. Именно поэтому pcall в адаптере возвращал
    -- «получилось», и отказа было нечем заметить.
    --
    -- Список обязан остаться пустым во всех наборах. Проверяют это
    -- Tests/test_recipe.lua (по всем путям нажатия) и Tests/test_sense.lua
    -- (по всем состояниям мира).
    env.openRecipeCalls = {}
    env.G.C_TradeSkillUI = env.G.C_TradeSkillUI or {}
    env.G.C_TradeSkillUI.OpenRecipe = function(recipeID)
        env.openRecipeCalls[#env.openRecipeCalls + 1] = recipeID
        -- Ответа нет и ошибки нет: так ведёт себя заблокированный вызов.
        return nil
    end
    function Api:OpenProfessionName() return env.openProfession end
    function Api:AllRecipeIDs() return env.openRecipeIDs end
    function Api:ReadRecipe(id) return env.readRecipe and env.readRecipe(id) end
    function Api:CategoryInfo(id)
        local c = env.categories and env.categories[id]
        if not c then return nil end
        return c.name, c.top, c.parentID
    end
    function Api:Report() return {} end

    -- Navigation fakes. These replace exactly the four client calls the arrow
    -- depends on, so Geo and Arrow are exercised for real.
    function Api:PlayerPosition()
        local p = env.playerMap
        if not p then
            ns.Diag:Call("C_Map.GetPlayerMapPosition", false, "позиция неизвестна")
            return nil, nil, nil, nil
        end
        ns.Diag:Call("C_Map.GetPlayerMapPosition", true)
        return p.mapID, p.x, p.y, p.zone
    end
    function Api:HasPlayerFacing() return env.facing ~= nil end
    function Api:PlayerFacing()
        ns.Diag:Call("GetPlayerFacing", env.facing ~= nil,
            env.facing == nil and "направление не вернулось — стрелка скроется" or nil)
        return env.facing
    end
    function Api:MapWorldSize(mapID)
        local s = env.worldSizes[mapID]
        ns.Diag:Call("C_Map.GetMapWorldSize", s ~= nil,
            s == nil and ("размер карты " .. tostring(mapID) .. " неизвестен") or nil)
        return s
    end
    function Api:MapName(mapID)
        local s = env.worldSizes[mapID]
        return (s and s.name) or ("Карта #" .. tostring(mapID))
    end
    function Api:NavPlayerState()
        local p = env.playerMap
        if not p then return nil end
        return { mapID = p.mapID, x = p.x, y = p.y, zone = p.zone, facing = env.facing }
    end
    function Api:TomTomPresent() return env.tomtom and true or false end
    -- Records what TomTom would have been handed, after the real coordinate
    -- normalisation, so the test can check the units actually sent.
    function Api:TomTomWaypoint(mapID, x, y, title)
        if not env.tomtom then return false, "no-tomtom" end
        local fx, fy = ns.Api:NavFractions(x, y)
        if not (tonumber(mapID) and fx) then return false, "bad-coords" end
        table.insert(env.tomtomCalls, { mapID = mapID, x = fx, y = fy, title = title })
        return true
    end
    function Api:NavProvider()
        local cfg = ns.Config:Get()
        local pref = cfg and cfg.nav and cfg.nav.provider or "own"
        if pref == "off" then return nil end
        if pref == "tomtom" and env.tomtom then return "tomtom" end
        if env.playerMap or env.navAvailable then return "own" end
        if env.tomtom then return "tomtom" end
        return "own"
    end
    function Api:UnitNpcID() return env.npcUnit and env.npcUnit.id or nil end
    function Api:UnitName() return env.npcUnit and env.npcUnit.name or nil end
    function Api:MerchantItems() return env.merchantItems end
    function Api:ForeignPlaces() return env.foreignPlaces end

    -- Api:SanityCheckSkills is deliberately NOT faked. It touches no game API -
    -- it only reasons about numbers the caller already has - and the fake that
    -- used to stand here was a weaker copy: it did not blank a zero maximum, so
    -- `max = 0` flowed through the test pipeline while the real game blanked it.
    -- That difference hid a live bug behind a green suite. The production
    -- version runs here.

    env.Api = Api
    return env
end

-- Real items ------------------------------------------------------------
--
-- THE FIXTURE PROBLEM THIS SOLVES. The fake "independent item database" used to
-- be MIRRORED from the fake client's own stat table, and that mirror is built
-- from CLIENT_KEY_TO_STAT, which has no school keys at all. So no mirror could
-- ever produce spArcane, and the bug that cost the player materials was
-- untestable by construction - a whole class of error that the suite could not
-- see however many tests were added.
--
-- H.useRealItems wires in real rows instead: the client half gets only the base
-- stats a real client reports, the database half gets the full row out of
-- Tests/fixtures/real_items.lua, which was copied verbatim from the installed
-- data. The two halves now disagree in exactly the way the real ones do.

H.realItems = nil

function H.fixtures()
    if H.realItems == nil then
        local chunk = loadfile(H.ROOT .. "/Tests/fixtures/real_items.lua")
        H.realItems = chunk and chunk() or false
    end
    if H.realItems == false then return nil end
    return H.realItems
end

-- Which stats a real client on this realm actually reports: base stats only.
H.CLIENT_REPORTED = {
    sta = "ITEM_MOD_STAMINA_SHORT", int = "ITEM_MOD_INTELLECT_SHORT",
    spi = "ITEM_MOD_SPIRIT_SHORT", str = "ITEM_MOD_STRENGTH_SHORT",
    agi = "ITEM_MOD_AGILITY_SHORT",
}

-- `opts.noDB`     - the item database has no row for these items at all
-- `opts.noClient` - the client has not cached them yet
function H.useRealItems(env, ids, opts)
    opts = opts or {}
    local F = H.fixtures()
    if not F then error("Tests/fixtures/real_items.lua не найден") end
    env.itemDBMirror = false
    env.foreignItemStats = env.foreignItemStats or {}

    local used = {}
    for _, itemID in ipairs(ids) do
        local rec = F.Record(itemID)
        if rec then
            used[#used + 1] = itemID
            if not opts.noClient then
                env.items[itemID] = {
                    name = F.RU_NAMES[itemID] or F.EN_NAMES[itemID]
                        or ("Предмет #" .. itemID),
                    equipLoc = F.INV_TO_EQUIPLOC[rec.inv],
                    reqLevel = rec.req, itemLevel = rec.ilvl,
                    quality = rec.quality,
                    classID = rec.class, subclassID = rec.subclass,
                    sellPrice = 10, stackCount = 20,
                }
                -- The client half: base stats and nothing else.
                local raw = {}
                for key, value in pairs(rec.stats) do
                    local clientKey = H.CLIENT_REPORTED[key]
                    if clientKey then raw[clientKey] = value end
                end
                if next(raw) then env.stats[itemID] = raw end
            end
            -- The database half: the whole row, independent of the client.
            if not opts.noDB then
                local copy = {}
                for k, v in pairs(rec.stats) do copy[k] = v end
                env.foreignItemStats[itemID] = copy
            end
        end
    end
    return used
end

-- Register the real recipes that make the given items, under the profession
-- name the player's own client used.
function H.useRealRecipes(env, itemIDs, opts)
    opts = opts or {}
    local F = H.fixtures()
    if not F then error("Tests/fixtures/real_items.lua не найден") end
    local want = {}
    for _, id in ipairs(itemIDs) do want[id] = true end

    local byProf = {}
    for _, r in ipairs(F.RECIPES) do
        if want[r.output] then
            byProf[r.profession] = byProf[r.profession] or {}
            local list = byProf[r.profession]
            list[#list + 1] = {
                id = r.id, name = r.name, learned = true, output = r.output,
                outputQty = r.outputQty, diff = r.diff,
                category = r.category, categoryID = r.category,
                reagents = r.reagents,
            }
        end
    end
    local n = 0
    for prof, list in pairs(byProf) do
        env.professions[#env.professions + 1] = {
            name = prof, skill = 225, max = 225, skillTrusted = true,
        }
        n = n + env.ns.RecipeBook:Store(prof, list, "stored",
            env.ns.CONF.CACHED, H.serverTime)
    end
    env.ns.RecipeBook:Reindex()
    return n, byProf
end

-- The player's own equipment, as the fixture recorded it.
function H.useRealEquipment(env, slots)
    local F = H.fixtures()
    if not F then error("Tests/fixtures/real_items.lua не найден") end
    local ids = {}
    for slot, itemID in pairs(F.EQUIPPED) do
        if (not slots) or slots[slot] then
            ids[#ids + 1] = itemID
            env.equipped[slot] = { itemID = itemID }
        end
    end
    H.useRealItems(env, ids)
    return ids
end

-- The installed item database, for the integration tests ----------------
--
-- In game the addon calls Polestar.ItemDB.Get(itemID) and that addon parses its
-- own data. Offline there is no Polestar, so this reads its two generated files
-- and parses the compact row format its header documents. Falls back to the
-- committed fixture when the addon is not installed, so the suite runs on a
-- machine that only has this folder.
--
-- The parser is test scaffolding. Nothing in the addon does it.
H.itemDBRows = nil

function H.loadInstalledItemDB()
    if H.itemDBRows ~= nil then return H.itemDBRows or nil end
    local bases = {}
    if os.getenv("FP_ADDONS") then
        bases[#bases + 1] = os.getenv("FP_ADDONS") .. "/Polestar_ItemDB/"
    end
    bases[#bases + 1] = H.ROOT .. "/../Polestar_ItemDB/"
    bases[#bases + 1] = H.ROOT .. "/../../AddOns/Polestar_ItemDB/"
    -- И раскладка, где папки аддонов лежат рядом, а не вложенно. Без неё набор
    -- тихо брал фикстуру на 131 предмет вместо установленной базы на 10621 и
    -- «проверял» совсем не то, что в игре.
    bases[#bases + 1] = H.ROOT .. "/../AddOns/Polestar_ItemDB/"

    local raw, names = {}, {}
    local stub = {
        Register = function(_, items)
            if type(items) == "table" then
                for id, s in pairs(items) do raw[id] = s end
            end
        end,
        RegisterLeveling = function(_, data)
            if type(data) == "table" and type(data.names) == "table" then
                for id, n in pairs(data.names) do names[id] = n end
            end
        end,
    }
    local found, foundAt = false, nil
    for _, base in ipairs(bases) do
        local probe = io.open(base .. "Items.lua", "r")
        if probe then
            probe:close()
            for _, file in ipairs({ "Items.lua", "Forever.lua" }) do
                local chunk = loadfile(base .. file)
                if chunk then
                    setfenv(chunk, setmetatable({ Polestar = { ItemDB = stub } },
                        { __index = function(_, k) return _G[k] end }))
                    if pcall(chunk) then found = true; foundAt = base end
                end
            end
            break
        end
    end
    H.itemDBSearched = bases
    if not found then H.itemDBRows = false; return nil end

    local UNTOKEN = { mpr = "mp5", hpr = "hp5" }
    local HEADER_ONLY = { cls = true, uniq = true }
    local cache = {}
    local function get(itemID)
        if cache[itemID] ~= nil then return cache[itemID] or nil end
        local s = raw[itemID]
        if type(s) ~= "string" then cache[itemID] = false; return nil end
        local inv, ilvl, req, quality, class, sub =
            s:match("^(%d+) (%d+) (%d+) (%d+) (%d+) (%d+)")
        if not inv then cache[itemID] = false; return nil end
        local stats, dmin, dmax, speed = {}, nil, nil, nil
        for key, n in s:gmatch("(%a+)(%-?%d+)") do
            n = tonumber(n)
            if key == "dmin" then dmin = n
            elseif key == "dmax" then dmax = n
            elseif key == "speed" then speed = n
            elseif not HEADER_ONLY[key] then stats[UNTOKEN[key] or key] = n end
        end
        if dmin and dmax and speed and speed > 0 then
            stats.dps = math.floor((dmin + dmax) / 2 / (speed / 1000) * 10 + 0.5) / 10
        end
        local rec = {
            id = itemID, inv = tonumber(inv), ilvl = tonumber(ilvl),
            req = tonumber(req), quality = tonumber(quality),
            class = tonumber(class), subclass = tonumber(sub), stats = stats,
        }
        cache[itemID] = rec
        return rec
    end
    local count = 0
    for _ in pairs(raw) do count = count + 1 end
    -- Все номера предметов по возрастанию: чтобы тест, который ищет в базе
    -- предмет с нужным свойством, каждый раз находил один и тот же.
    local sortedIDs
    local function ids()
        if not sortedIDs then
            sortedIDs = {}
            for id in pairs(raw) do
                if type(id) == "number" then sortedIDs[#sortedIDs + 1] = id end
            end
            table.sort(sortedIDs)
        end
        return sortedIDs
    end
    H.itemDBRows = { get = get, names = names, count = count, ids = ids, path = foundAt }
    return H.itemDBRows
end

-- С КАКОЙ БАЗОЙ ПРЕДМЕТОВ НА САМОМ ДЕЛЕ ИДУТ ТЕСТЫ.
--
-- Их две: установленная Polestar_ItemDB (около 10 тысяч строк, та же, что в
-- игре) и фикстура Tests/fixtures/real_items.lua (131 строка), на которую набор
-- переходит, когда установленной рядом нет. Переход был МОЛЧАЛИВЫМ, и это
-- стоило целого неверного вывода: три проверки, привязанные к номерам 1131 и
-- 6367, падали, и по ним было решено, что «в установленной базе этих предметов
-- нет». Они там есть. Не было самой базы - папка аддона была подключена одна,
-- без соседей, - и набор тихо проверял другие данные.
--
-- Возвращает { kind = "installed" | "fixture" | "none", count, path }.
function H.itemDBSource()
    local db = H.loadInstalledItemDB()
    if db then
        return { kind = "installed", count = db.count, path = db.path }
    end
    local F = H.fixtures()
    if F then
        local n = 0
        for _ in pairs(F.ITEM_ROWS or {}) do n = n + 1 end
        return { kind = "fixture", count = n, path = H.ROOT .. "/Tests/fixtures/real_items.lua" }
    end
    return { kind = "none", count = 0 }
end

function H.itemDBSourceText()
    local src = H.itemDBSource()
    if src.kind == "installed" then
        return "установленная Polestar_ItemDB, строк " .. src.count
    elseif src.kind == "fixture" then
        return "ФИКСТУРА на " .. src.count .. " строк — установленная Polestar_ItemDB"
            .. " рядом с аддоном не найдена"
    end
    return "НЕТ НИКАКОЙ — ни установленной, ни фикстуры"
end

-- Перебор базы, с которой идут тесты, по возрастанию номера. fn(itemID, rec);
-- вернёт true - перебор остановится.
function H.itemDBEach(fn)
    local db = H.loadInstalledItemDB()
    if db then
        for _, id in ipairs(db.ids()) do
            local rec = db.get(id)
            if rec and fn(id, rec) then return end
        end
        return
    end
    local F = H.fixtures()
    if not F then return end
    local ids = {}
    for id in pairs(F.ITEM_ROWS or {}) do
        if type(id) == "number" then ids[#ids + 1] = id end
    end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local rec = F.Record(id)
        if rec and fn(id, rec) then return end
    end
end

-- Найти в базе предмет с нужным свойством - ВМЕСТО НОМЕРА, ВПИСАННОГО В ТЕСТ.
--
-- Номер, вписанный в тест, верен ровно для той базы, по которой его подбирали.
-- Сменилась база (обновился аддон с данными, тесты пошли по фикстуре) - и тест
-- проверяет уже не то свойство, а «есть ли в базе предмет №1131». Свойство же
-- - «строка есть, характеристик нет», «это удочка» - находится в любой базе,
-- где такие предметы есть, а где их нет, тест об этом скажет прямо.
--
-- Возвращает itemID, rec или nil.
function H.findItemInDB(predicate)
    local foundID, foundRec
    H.itemDBEach(function(id, rec)
        if predicate(rec, id) then
            foundID, foundRec = id, rec
            return true
        end
    end)
    return foundID, foundRec
end

-- Строка одного предмета из базы, с которой идут тесты, или nil.
function H.itemDBRecord(itemID)
    local db = H.loadInstalledItemDB()
    if db then return db.get(itemID) end
    local F = H.fixtures()
    return F and F.Record(itemID) or nil
end

-- Название предмета из базы, если она его знает (для подписей проверок).
function H.itemDBName(itemID)
    local db = H.loadInstalledItemDB()
    if db and db.names and db.names[itemID] then return tostring(db.names[itemID]) end
    local F = H.fixtures()
    if F then
        return (F.RU_NAMES and F.RU_NAMES[itemID]) or (F.EN_NAMES and F.EN_NAMES[itemID])
    end
    return nil
end

-- УСТАНОВЛЕННЫЙ Polestar_Codex, А НЕ ВЫДУМАННЫЕ ТРИ ЗАПИСИ ------------------
--
-- До этого в наборе был только самодельный Codex (H.bindCodex кормит его
-- env.codexItems), и в него тесты вписывали по две-три записи руками. Половина
-- аддона - торговцы, их цены, координаты NPC - проверялась поэтому на данных,
-- которых в игре нет. Живой прогон это и показал: ветка арбитража выдала шесть
-- карточек на одного NPC с наценкой в 2270%, а в наборе ветка молчала, потому
-- что спрашивать было некого.
--
-- Этот загрузчик читает те же файлы, что Codex читает в игре
-- (Polestar_Codex/Items*.lua и Npcs*.lua), и разбирает компактный формат,
-- документированный в Polestar/Lookup/Codex.lua:
--
--   строка записи:  <id>\t<q><status>;<reqLevel>;<spell>;<repFaction>;
--                   <repStanding>;<reqSkill>;<reqSkillRank>;<источник>;...
--   источник:       v<npc>,<cost>,<limited>,<провенанс>   - торговец
--                   d<npc>,<шанс>,<инстанс>,<провенанс>   - добыча
--                   o / q / g / c / r / p / n / w          - остальные виды
--   провенанс:      буквы источников факта (l recordings, q questie,
--                   p pfquest, c client, w web, e forever, ...)
--
-- Разбор - строительные леса теста. В аддоне этого нет: там за разбор отвечает
-- сам Codex, у которого есть публичный API.
H.codexRows = nil

local CODEX_FROM = {
    a = "atlasloot", c = "client", d = "dungeons", g = "guides", j = "journal",
    l = "recordings", p = "pfquest", q = "questie", r = "rarescanner",
    u = "curated", w = "web", e = "forever",
}
local CODEX_SOURCE = {
    v = { "vendor", { "npc", "cost", "limited" } },
    d = { "drop", { "npc", "chance", "instance" } },
    o = { "object", { "object", "chance" } },
    q = { "quest", { "quest", "choice" } },
    g = { "gift", { "npc", "spell" } },
    c = { "craft", { "spell", "skillLine", "skill" } },
    r = { "rep", { "faction", "standing", "npc" } },
    p = { "pvp", { "rank", "npc" } },
    n = { "container", { "item", "chance" } },
    w = { "world", { "minLevel", "maxLevel" } },
}
local CODEX_BOOL = { limited = true, choice = true }

local function codexSplit(s, sep)
    local out, n = {}, 0
    local pattern = (sep == ";") and "([^;]*);" or "([^,]*),"
    for field in (s .. sep):gmatch(pattern) do
        n = n + 1
        out[n] = field
    end
    return out, n
end

local function codexProvenance(s)
    local out = {}
    for i = 1, #(s or "") do
        local name = CODEX_FROM[s:sub(i, i)]
        if name then out[#out + 1] = name end
    end
    return out
end

local function codexDecodeSource(field)
    local def = CODEX_SOURCE[field:sub(1, 1)]
    if not def then return nil end
    local parts = codexSplit(field:sub(2), ",")
    local fields = def[2]
    local src = { type = def[1] }
    for i = 1, #fields do
        local key, v = fields[i], parts[i]
        if v and v ~= "" then
            if CODEX_BOOL[key] then src[key] = (v == "1")
            elseif key == "instance" then src[key] = v
            else src[key] = tonumber(v) end
        end
    end
    src.from = codexProvenance(parts[#fields + 1] or "")
    return src
end

-- "map,f,x,y,x,y" -> { { map, x, y }, ... }; координаты Codex в десятых долях
-- процента, как и в игре - делением занимается сам аддон.
local function codexSpawns(fields, firstIndex, lastIndex)
    local out = {}
    for i = firstIndex, lastIndex do
        local group = fields[i]
        if group and group ~= "" and group:sub(1, 1) ~= "z" and group:sub(1, 1) ~= "t" then
            local parts = codexSplit(group, ",")
            local map = tonumber(parts[1])
            if map then
                local k = 3
                while parts[k] and parts[k + 1] do
                    local x, y = tonumber(parts[k]), tonumber(parts[k + 1])
                    if x and y then out[#out + 1] = { map = map, x = x / 10, y = y / 10 } end
                    k = k + 2
                end
            end
        end
    end
    return out
end

function H.loadInstalledCodex()
    if H.codexRows ~= nil then return H.codexRows or nil end
    local bases = {}
    if os.getenv("FP_ADDONS") then
        bases[#bases + 1] = os.getenv("FP_ADDONS") .. "/Polestar_Codex/"
    end
    bases[#bases + 1] = H.ROOT .. "/../Polestar_Codex/"
    bases[#bases + 1] = H.ROOT .. "/../../AddOns/Polestar_Codex/"
    bases[#bases + 1] = H.ROOT .. "/../AddOns/Polestar_Codex/"

    local base
    for _, dir in ipairs(bases) do
        local probe = io.open(dir .. "Items1.lua", "r")
        if probe then probe:close(); base = dir; break end
    end
    if not base then H.codexRows = false; return nil end

    -- Codex.Register(group, names, recs, lo, hi): names - "id\tflags\tимя",
    -- recs - "id\tполя;...". Нам нужны оба: имя для подписи, recs для разбора.
    local groups = {}
    local stub = {
        Register = function(group, names, recs)
            if group == "meta" then return end
            if type(group) ~= "string" or type(names) ~= "string" then return end
            local list = groups[group]
            if not list then list = {}; groups[group] = list end
            list[#list + 1] = { names = names, recs = (type(recs) == "string") and recs or nil }
        end,
        RegisterIndex = function() end,
    }
    -- «Recipes» ЗДЕСЬ ОБЯЗАТЕЛЕН, И ЭТО НЕ ПОЛНОТА РАДИ ПОЛНОТЫ.
    --
    -- В игре Codex.Item(id) ищет по пяти группам сразу - item, mount, pet,
    -- recipe, tabard (Polestar/Lookup/Codex.lua, ITEM_GROUPS), - и чертежи
    -- лагеря лежат именно в группе recipe: в пакете предметов их нет вовсе
    -- (273085..273141 в Items5/Items6 отсутствуют). Стенд читал только Items* и
    -- Npcs*, то есть его Codex был УЖЕ игрового: на настоящих данных ветка
    -- лагеря не получала ни одного имени чертежа и молча не выдавала карточку
    -- «купить чертёж», которая в игре выдаётся. Расхождение стенда с игрой -
    -- это зелёный набор проверок про аддон, который ведёт себя иначе.
    local files = {}
    for _, prefix in ipairs({ "Items", "Npcs", "Recipes" }) do
        for i = 1, 9 do
            local path = base .. prefix .. i .. ".lua"
            local probe = io.open(path, "r")
            if probe then probe:close(); files[#files + 1] = path end
        end
    end
    for _, path in ipairs(files) do
        local chunk = loadfile(path)
        if chunk then
            setfenv(chunk, setmetatable({ Polestar = { Codex = stub } },
                { __index = function(_, k) return _G[k] end }))
            pcall(chunk)
        end
    end

    -- ИМЕНА НА ЯЗЫКЕ КЛИЕНТА - ИЗ ТОГО ЖЕ ПАКЕТА, ЧТО В ИГРЕ.
    --
    -- В игре Codex отдаёт имя через shown(): сначала кеш предметов клиента,
    -- потом пакет имён на языке клиента (Polestar_ruRU/Names.lua), и только
    -- потом английское имя своего пакета. Стенд знал лишь третье, и на экране
    -- осмотра стояло «Mana Well» там, где игрок видит «Колодец маны», - то есть
    -- стенд показывал не тот текст, который читает человек.
    --
    -- Формат пакета описан в его шапке: N.AddChunk(язык, вид, lo, hi, текст),
    -- внутри строки «<id>\t<имя>», а символы % ; , : | табуляция и перевод
    -- строки записаны как %XX. Читаются только имена предметов: остального
    -- стенду не нужно.
    local ruNames = {}
    do
        local ruBases = {}
        if os.getenv("FP_ADDONS") then
            ruBases[#ruBases + 1] = os.getenv("FP_ADDONS") .. "/Polestar_ruRU/Names.lua"
        end
        ruBases[#ruBases + 1] = H.ROOT .. "/../Polestar_ruRU/Names.lua"
        ruBases[#ruBases + 1] = H.ROOT .. "/../../AddOns/Polestar_ruRU/Names.lua"
        local chunks = {}
        local namesStub = {
            AddChunk = function(locale, kind, lo, hi, text)
                if kind == "item" and type(text) == "string" then
                    chunks[#chunks + 1] = text
                end
            end,
        }
        for _, path in ipairs(ruBases) do
            local chunk = loadfile(path)
            if chunk then
                setfenv(chunk, setmetatable({ Polestar = { Names = namesStub } },
                    { __index = function(_, k) return _G[k] end }))
                pcall(chunk)
                break
            end
        end
        for _, text in ipairs(chunks) do
            for line in (text .. "\n"):gmatch("([^\n]*)\n") do
                local id, name = line:match("^(%d+)\t(.*)$")
                if id and name ~= "" then
                    name = name:gsub("%%(%x%x)", function(hex)
                        return string.char(tonumber(hex, 16))
                    end)
                    ruNames[tonumber(id)] = name
                end
            end
        end
    end

    -- Индексы по id собираются один раз: построчный проход по всем блобам.
    local function indexOf(group)
        local byName, byRec = {}, {}
        for _, c in ipairs(groups[group] or {}) do
            for line in (c.names .. "\n"):gmatch("([^\n]*)\n") do
                local id, rest = line:match("^(%d+)\t(.*)$")
                if id then byName[tonumber(id)] = rest:match("^[^\t]*\t(.*)$") or rest end
            end
            if c.recs then
                for line in (c.recs .. "\n"):gmatch("([^\n]*)\n") do
                    local id, rest = line:match("^(%d+)\t(.*)$")
                    if id then byRec[tonumber(id)] = rest end
                end
            end
        end
        return { names = byName, recs = byRec }
    end

    local itemIdx, npcIdx = {}, {}
    for _, g in ipairs({ "item", "mount", "pet", "recipe", "tabard" }) do
        itemIdx[#itemIdx + 1] = indexOf(g)
    end
    for _, g in ipairs({ "npc", "rare" }) do
        npcIdx[#npcIdx + 1] = indexOf(g)
    end

    local itemCache, npcCache = {}, {}
    local counts = { items = 0, npcs = 0 }

    local function item(itemID)
        if itemCache[itemID] ~= nil then return itemCache[itemID] or nil end
        counts.items = counts.items + 1
        for _, idx in ipairs(itemIdx) do
            local name = idx.names[itemID]
            if name then
                -- Имя на языке клиента, как его отдаёт Codex в игре; английское
                -- из пакета остаётся запасным.
                local rec = { id = itemID, name = ruNames[itemID] or name,
                              englishName = name, sources = {} }
                local raw = idx.recs[itemID]
                if raw then
                    local fields, n = codexSplit(raw, ";")
                    local q, st = (fields[1] or ""):match("^(%d*)(%a?)$")
                    rec.quality = tonumber(q)
                    rec.status = (st ~= "" and st) or nil
                    rec.reqLevel = tonumber(fields[2])
                    rec.repFaction = tonumber(fields[4])
                    rec.repStanding = tonumber(fields[5])
                    rec.reqSkill = tonumber(fields[6])
                    rec.reqSkillRank = tonumber(fields[7])
                    for i = 8, n do
                        local src = codexDecodeSource(fields[i] or "")
                        if src then rec.sources[#rec.sources + 1] = src end
                    end
                end
                itemCache[itemID] = rec
                return rec
            end
        end
        itemCache[itemID] = false
        return nil
    end

    local function npc(npcID)
        if npcCache[npcID] ~= nil then return npcCache[npcID] or nil end
        counts.npcs = counts.npcs + 1
        for _, idx in ipairs(npcIdx) do
            local name = idx.names[npcID]
            if name then
                local rec = { id = npcID, name = name, roles = {}, spawns = {} }
                local raw = idx.recs[npcID]
                if raw then
                    local fields, n = codexSplit(raw, ";")
                    -- Подпись NPC («Agent of the Black Market») идёт последним
                    -- полем с префиксом t. Без неё нельзя сказать, ЧТО это за
                    -- торговец, а в этой задаче именно подпись всё и объяснила.
                    if n >= 8 and (fields[n] or ""):sub(1, 1) == "t" then
                        rec.subName = fields[n]:sub(2)
                        n = n - 1
                    end
                    rec.level = tonumber(fields[1])
                    rec.faction = (fields[3] ~= "" and fields[3]) or nil
                    if fields[6] and fields[6] ~= "" then
                        for role in (fields[6] .. ","):gmatch("([^,]*),") do
                            if role ~= "" then rec.roles[#rec.roles + 1] = role end
                        end
                    end
                    rec.spawns = codexSpawns(fields, 8, n)
                end
                npcCache[npcID] = rec
                return rec
            end
        end
        npcCache[npcID] = false
        return nil
    end

    local itemTotal = 0
    for _, idx in ipairs(itemIdx) do
        for _ in pairs(idx.names) do itemTotal = itemTotal + 1 end
    end
    local npcTotal = 0
    for _, idx in ipairs(npcIdx) do
        for _ in pairs(idx.names) do npcTotal = npcTotal + 1 end
    end

    H.codexRows = {
        item = item, npc = npc, path = base,
        -- Имя предмета на языке клиента ОТДЕЛЬНО от записи Codex.
        --
        -- В игре такие имена отдаёт сам клиент (C_Item.GetItemInfo) по всему,
        -- что он кешировал, - и реагенты вроде «Простое дерево» он знает.
        -- Офлайн клиента нет, и стенд берёт имя из того же пакета имён, из
        -- которого его берёт игра, когда клиент молчит. ЗАПИСЬЮ Codex это не
        -- становится: Codex.Item(id) про предмет, которого в его пакете нет,
        -- отвечает «нет» и в игре - иначе стенд умел бы больше игры.
        ruName = function(itemID) return ruNames[tonumber(itemID) or -1] end,
        itemCount = itemTotal, npcCount = npcTotal,
        counts = counts,
        itemIDs = function()
            local out = {}
            for _, idx in ipairs(itemIdx) do
                for id in pairs(idx.names) do out[#out + 1] = id end
            end
            table.sort(out)
            return out
        end,
        npcIDs = function()
            local out = {}
            for _, idx in ipairs(npcIdx) do
                for id in pairs(idx.names) do out[#out + 1] = id end
            end
            table.sort(out)
            return out
        end,
    }
    return H.codexRows
end

-- Подключить установленный Codex как источник для песочницы. Возвращает
-- таблицу загрузчика или nil, когда пакета рядом нет.
--
-- СКОЛЬКО РАЗ АДДОН СПРОСИЛ CODEX - здесь же: env.codexCalls растёт на каждом
-- обращении, и именно это число проверяет контракт производительности. Мерить
-- миллисекунды на разборе-в-таблицу бессмысленно, а число обращений переносится
-- из теста в игру один в один: в игре каждое обращение - это двоичный поиск по
-- блобу на 900 килобайт плюс обращение к кешу предметов клиента.
function H.installRealCodex(env)
    local codex = H.loadInstalledCodex()
    if not codex then return nil end
    env.codexCalls = 0
    env.codexItemCalls = 0
    env.codexNpcCalls = 0
    env.codexItems = setmetatable({}, { __index = function(_, itemID)
        env.codexCalls = env.codexCalls + 1
        env.codexItemCalls = env.codexItemCalls + 1
        return codex.item(itemID)
    end })
    env.codexNpcs = setmetatable({}, { __index = function(_, npcID)
        env.codexCalls = env.codexCalls + 1
        env.codexNpcCalls = env.codexNpcCalls + 1
        return codex.npc(npcID)
    end })
    env.codexLoaded = true
    env.codexAbsent = false
    env.realCodex = codex
    H.bindCodex(env)
    return codex
end

-- Положить в песочницу объект Polestar.ItemDB, который аддон найдёт сам.
--
-- Запись собирается из того, что тест дал: своей таблицы характеристик
-- (env.foreignItemStats), зеркала клиентских статов (env.itemDBMirror) или
-- установленной базы (env.itemDBRecords). Пустая таблица характеристик - это
-- «строка есть, характеристик нет», и производственный читатель сам ответит
-- «no-stats»; отсутствие записи - «not-in-db»; env.itemDBLoading - «loading»;
-- полное отсутствие объекта - «no-db».
function H.bindItemDB(env)
    local ns, G = env.ns, env.G
    local function present()
        if env.itemDBInstalled then return true end
        if env.itemDBMirror then return true end
        return env.foreignItemStats ~= nil and next(env.foreignItemStats) ~= nil
    end
    -- Codex привязывается ВСЕГДА, независимо от базы предметов: это две разные
    -- базы, и отсутствие одной не означает отсутствия другой.
    H.bindCodex(env)
    if not present() then
        if G.Polestar then G.Polestar.ItemDB = nil end
        return
    end
    local function recordFor(itemID)
        local rec = env.foreignItemRecords and env.foreignItemRecords[itemID] or nil
        local stats = env.foreignItemStats and env.foreignItemStats[itemID] or nil
        if not stats and env.itemDBMirror and env.mirrorStats then
            stats = env.mirrorStats(itemID)
        end
        if rec then
            local copy = {}
            for k, v in pairs(rec) do copy[k] = v end
            copy.stats = stats or rec.stats or {}
            return copy
        end
        if stats then
            return { id = itemID, stats = stats }
        end
        return nil
    end
    G.Polestar = G.Polestar or {}
    G.Polestar.ItemDB = {
        Get = function(itemID) return recordFor(itemID) end,
        IsLoaded = function() return not env.itemDBLoading end,
        Load = function() return not env.itemDBLoading end,
    }
    H.bindCodex(env)
end

-- Polestar.Codex, тот же публичный API, что в игре ------------------------
--
-- Раньше его в наборе не было вовсе, и весь код, который спрашивает Codex -
-- координаты торговцев, тренеры следующего ранга, источники предмета - в
-- тестах просто не выполнялся: Api:CodexReady возвращал false, и ветка
-- молчала. Непроверенный код, который в игре работает по-другому, - это ровно
-- тот способ ломаться, от которого весь этот набор и существует.
--
--   env.codexItems[itemID] = { sources = { { type="vendor", npc=.., cost=.. } } }
--   env.codexNpcs[npcID]   = { name, subName, roles = {...},
--                              spawns = { { map, x, y } } }   -- x,y в процентах
--   env.codexLoaded = false  -> база «не загружена», как до Codex.Load()
function H.bindCodex(env)
    local G = env.G
    env.codexItems = env.codexItems or {}
    env.codexNpcs = env.codexNpcs or {}
    env.codexSkills = env.codexSkills or {}
    if env.codexLoaded == nil then env.codexLoaded = true end
    if env.codexAbsent then
        if G.Polestar then G.Polestar.Codex = nil end
        return
    end
    G.Polestar = G.Polestar or {}
    G.Polestar.Codex = {
        Item = function(id) return env.codexItems[id] end,
        Npc = function(id) return env.codexNpcs[id] end,
        Name = function(kind, id)
            if kind == "skill" then return env.codexSkills[id] end
            return nil
        end,
        IsLoaded = function() return env.codexLoaded and true or false end,
        Load = function()
            env.codexLoaded = true
            return true
        end,
        WithRole = function(role)
            -- Установленный Codex: роли берутся из него, иначе из таблицы теста.
            -- Через pairs по env.codexNpcs установленный пакет не обойти - он
            -- ленивый, и pairs по нему вернёт пусто.
            local real = env.realCodex
            if real then
                real.roleIndex = real.roleIndex or (function()
                    local idx = {}
                    for _, npcID in ipairs(real.npcIDs()) do
                        local rec = real.npc(npcID)
                        for _, r in ipairs((rec and rec.roles) or {}) do
                            idx[r] = idx[r] or {}
                            idx[r][#idx[r] + 1] = npcID
                        end
                    end
                    for _, list in pairs(idx) do table.sort(list) end
                    return idx
                end)()
                local out = {}
                for _, id in ipairs(real.roleIndex[role] or {}) do out[#out + 1] = id end
                return out
            end
            local out = {}
            for npcID, rec in pairs(env.codexNpcs) do
                for _, r in ipairs(rec.roles or {}) do
                    if r == role then out[#out + 1] = npcID end
                end
            end
            table.sort(out)
            return out
        end,
        Each = function(kind, fn)
            if kind ~= "item" then return end
            local real = env.realCodex
            if real then
                for _, id in ipairs(real.itemIDs()) do
                    local rec = real.item(id)
                    if rec and fn(id, rec.name, rec.quality, rec.status) == false then return end
                end
                return
            end
            for id, rec in pairs(env.codexItems) do
                if fn(id, rec.name, rec.quality, rec.status) == false then return end
            end
        end,
    }
end

-- Wire the installed database (or the fixture) in as the foreign source.
-- Returns how many rows it holds, or nil when neither is available.
function H.installRealItemDB(env)
    env.itemDBMirror = false
    local db = H.loadInstalledItemDB()
    if db then
        env.foreignItemStats = setmetatable({}, { __index = function(_, itemID)
            local rec = db.get(itemID)
            return rec and rec.stats or nil
        end })
        env.foreignItemRecords = setmetatable({}, { __index = function(_, itemID)
            return db.get(itemID)
        end })
        env.realItemDBCount = db.count
        env.itemDBInstalled = true
        H.bindItemDB(env)
        return db.count, db
    end
    local F = H.fixtures()
    if not F then return nil end
    env.foreignItemStats = setmetatable({}, { __index = function(_, itemID)
        return F.Stats(itemID)
    end })
    env.foreignItemRecords = setmetatable({}, { __index = function(_, itemID)
        return F.Record(itemID)
    end })
    local n = 0
    for _ in pairs(F.ITEM_ROWS) do n = n + 1 end
    env.realItemDBCount = n
    env.itemDBInstalled = true
    H.bindItemDB(env)
    return n, nil
end

-- Convenience builders --------------------------------------------------

function H.item(env, itemID, fields)
    fields = fields or {}
    fields.name = fields.name or ("Предмет " .. itemID)
    env.items[itemID] = fields
    return itemID
end

function H.recipe(fields)
    return {
        id = fields.id,
        name = fields.name or ("Рецепт " .. fields.id),
        learned = (fields.learned ~= false),
        output = fields.output,
        outputQty = fields.outputQty or 1,
        reagents = fields.reagents or {},
        diff = fields.diff,
        category = fields.category,
        categoryID = fields.categoryID,
        group = fields.group,
        icon = fields.icon,
    }
end

-- Register a profession plus its recipes, in one call.
function H.profession(env, name, skill, max, recipes)
    env.professions[#env.professions + 1] = {
        name = name, skill = skill, max = max, skillTrusted = true,
    }
    env.ns.RecipeBook:Store(name, recipes or {}, "own", env.ns.CONF.EXACT, H.serverTime)
    env.ns.RecipeBook:Reindex()
end

function H.rescan(env)
    local snap = env.ns.CharacterScanner:Scan()
    return snap
end

-- Item stats are cached across rebuilds, because an item's data does not change
-- while the player plays. The one thing that DOES change it is the client
-- delivering data we did not have, and the addon drops its caches on that
-- event. A test that edits env.stats or env.foreignItemStats is simulating
-- exactly that, so it has to say so - otherwise it is asserting against a
-- stale answer and proving nothing.
function H.itemsChanged(env)
    local ns = env.ns
    H.bindItemDB(env)
    if ns.GearAdvisor and ns.GearAdvisor.InvalidateItemData then
        ns.GearAdvisor:InvalidateItemData("тест изменил данные предметов")
    end
    if ns.Api and ns.Api.BeginPass then ns.Api:BeginPass() end
end

-- Full pipeline, the same order Main uses in game.
function H.build(env)
    local ns = env.ns
    local snap = ns.CharacterScanner:Scan()
    ns.RecipeBook.missingProfessions = {}
    for _, prof in ipairs(ns.CharacterScanner:CraftingProfessions()) do
        if not ns.RecipeBook:HasProfession(prof.name) then
            table.insert(ns.RecipeBook.missingProfessions, prof)
        end
    end
    ns.Api:SanityCheckSkills(snap.professions, function(name)
        local bucket = ns.RecipeBook:Bucket(name)
        return bucket and #bucket.list or 0
    end)
    local cards, meta = ns.ActionEngine:Build()
    return cards, meta, snap
end

-- Assertions ------------------------------------------------------------

H.passed, H.failed, H.failures = 0, 0, {}
H.currentSuite = "?"

-- ЗАМЕТКА - не провал и не успех, а то, что читающий итог обязан увидеть:
-- проверка шла не по тем данным, по которым задумана, или заменена другой.
-- Печатается на месте и ПОВТОРЯЕТСЯ в итоге, потому что строку посреди четырёх
-- тысяч «ok» не читает никто - ровно так и потерялся переход на фикстуру.
H.notices = {}
function H.note(text)
    local line = H.currentSuite .. " / " .. tostring(text)
    for _, seen in ipairs(H.notices) do
        if seen == line then return end
    end
    H.notices[#H.notices + 1] = line
    print("  !!   " .. tostring(text))
end

function H.suite(name)
    H.currentSuite = name
    print("")
    print("== " .. name)
end

local function record(ok, label, detail)
    if ok then
        H.passed = H.passed + 1
        print("  ok   " .. label)
    else
        H.failed = H.failed + 1
        local line = H.currentSuite .. " / " .. label .. (detail and ("  <- " .. detail) or "")
        H.failures[#H.failures + 1] = line
        print("  FAIL " .. label .. (detail and ("  <- " .. detail) or ""))
    end
end

function H.ok(cond, label, detail)
    record(cond and true or false, label, (not cond) and detail or nil)
end

function H.eq(actual, expected, label)
    local ok = (actual == expected)
    record(ok, label, not ok and ("получили " .. tostring(actual)
        .. ", ждали " .. tostring(expected)) or nil)
end

function H.near(actual, expected, tol, label)
    actual, expected = tonumber(actual), tonumber(expected)
    local ok = actual ~= nil and expected ~= nil and math.abs(actual - expected) <= (tol or 0.001)
    record(ok, label, not ok and ("получили " .. tostring(actual)
        .. ", ждали " .. tostring(expected) .. " +-" .. tostring(tol)) or nil)
end

function H.summary()
    print("")
    print(string.rep("-", 64))
    print(string.format("Итого: %d пройдено, %d провалено", H.passed, H.failed))
    if H.failed > 0 then
        print("")
        for _, f in ipairs(H.failures) do print("  * " .. f) end
    end
    -- С какой базой шли проверки - в самом итоге, рядом с числом: «4000
    -- пройдено» по фикстуре на 131 строку и по установленной базе на 10 тысяч -
    -- это два разных утверждения.
    print("База предметов: " .. H.itemDBSourceText())
    if #H.notices > 0 then
        print("")
        print("Заметки (" .. #H.notices .. ") — проверки, которые шли не по тем"
            .. " данным, по которым задуманы:")
        for _, n in ipairs(H.notices) do print("  ! " .. n) end
    end
    print(string.rep("-", 64))
    return H.failed == 0
end

return H
