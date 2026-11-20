-- ForeverPilot / Logic/GearAdvisor.lua
--
-- "Does anything I can make beat what I am wearing?"
--
-- The level rule, which matters a lot on this realm: WoW: Forever lifted the
-- character-level gate on professions, so a level 26 mage can legitimately hold
-- Tailoring 225 and know recipes for gear twenty levels above them. That means
-- "I cannot wear this" must NEVER be a reason to throw a recipe away. It is only
-- a reason not to put it in the WEAR list.
--
-- So this module answers two separate questions and keeps them separate:
--   Upgrades()  - gear I can equip that beats what I have on. Level and class
--                 restrictions apply in full here.
--   Unwearable() - gear I can make but cannot use. Handed straight to the
--                 profit branch, because for this character that is the main
--                 way the professions pay for themselves.
local ADDON, ns = ...

local U = ns.Util
local Api = ns.Api
local CONF = ns.CONF
local SW = ns.StatWeights

local Gear = {}
ns.GearAdvisor = Gear

-- ВЕСА ДЛЯ ОЦЕНКИ - ИЛИ НИЧЕГО, И ОДИН ОТВЕТ НА ВСЕ СЕМЬ МЕСТ.
--
-- В семи функциях этого файла стояло `weights or (snap and snap.weights) or
-- SW:Set("CASTER_DPS")`: профиля нет - считаем кастерскими весами. Это «если
-- не знаю, считай магом», размноженное семь раз; при этом сверху всё
-- выглядело посчитанным, а посчитано было по чужому классу.
--
-- Теперь nil значит nil, и каждая точка входа обязана на нём остановиться и
-- сказать почему (StatWeights:NoProfileReason). Профиль есть у всех тринадцати
-- классов игры (SW.CLASS_DEFAULT), так что это не обычный путь, а состояние
-- «класс мне незнаком» - то самое, при котором совет давать нечем.
local function weightsOf(snap, weights)
    return weights or (snap and snap.weights) or nil
end

-- Class usability -------------------------------------------------------
-- The client does not tell us "this class can use this item", so this is our
-- own table of the game's armour rules. Everything derived from it is reported
-- as an ESTIMATE, and the player can switch the check off in Settings.

-- Enum.ItemClass.Armor == 4, Enum.ItemClass.Weapon == 2 (stable since vanilla).
Gear.CLASS_ARMOR = 4
Gear.CLASS_WEAPON = 2
Gear.CLASS_CONTAINER = 1

-- Armour subclasses: 0 misc (jewelry, cloaks are cloth), 1 cloth, 2 leather,
-- 3 mail, 4 plate, 6 shield, 7 librams, 8 idols, 9 totems, 10 sigils.
Gear.ARMOR_BY_CLASS = {
    MAGE        = { [0] = true, [1] = true },
    PRIEST      = { [0] = true, [1] = true },
    WARLOCK     = { [0] = true, [1] = true },
    ROGUE       = { [0] = true, [1] = true, [2] = true },
    DRUID       = { [0] = true, [1] = true, [2] = true, [8] = true },
    MONK        = { [0] = true, [1] = true, [2] = true },
    DEMONHUNTER = { [0] = true, [1] = true, [2] = true },
    HUNTER      = { [0] = true, [1] = true, [2] = true, [3] = true },
    SHAMAN      = { [0] = true, [1] = true, [2] = true, [3] = true, [6] = true, [9] = true },
    PALADIN     = { [0] = true, [1] = true, [2] = true, [3] = true, [4] = true, [6] = true, [7] = true },
    WARRIOR     = { [0] = true, [1] = true, [2] = true, [3] = true, [4] = true, [6] = true },
    DEATHKNIGHT = { [0] = true, [1] = true, [2] = true, [3] = true, [4] = true, [10] = true },
    EVOKER      = { [0] = true, [1] = true, [2] = true, [3] = true },
}

-- Weapon subclasses a class can hold. Only used to avoid suggesting a staff to
-- someone who cannot hold one; an unknown class means "do not judge".
Gear.WEAPON_BY_CLASS = {
    MAGE    = { [7] = true, [10] = true, [15] = true, [19] = true },
    PRIEST  = { [4] = true, [10] = true, [15] = true, [19] = true },
    WARLOCK = { [7] = true, [10] = true, [15] = true, [19] = true },
}

-- Can this character physically equip the item? Returns ok, reason, confidence.
function Gear:CanEquip(info, snap)
    if type(info) ~= "table" then return false, "нет данных о предмете", CONF.UNKNOWN end

    -- Level gate. This is real game data, not a guess.
    local req = tonumber(info.reqLevel) or 0
    local level = tonumber(snap and snap.level) or 0
    if level > 0 and req > level then
        -- «нужен 45 уровень» - число и слово не согласованы, и это видно на
        -- экране: эта фраза попадает в карточку «на продажу» целиком («Вы это
        -- надеть не можете (нужен 45 уровень, у вас 28)»). Существительное
        -- впереди числа согласования не требует ни при каком N, поэтому так и
        -- написано - и так же в двух других местах, где это число называется
        -- (окно крафта и ветка Благосклонности).
        return false, "нужен уровень " .. req .. ", у вас " .. level,
            CONF.EXACT, req - level
    end

    local cfg = ns.Config:Get()
    if cfg and cfg.show and cfg.show.skipClassCheck then
        return true, nil, CONF.ESTIMATE
    end

    local classFile = snap and snap.classFile
    if not classFile then return true, nil, CONF.UNKNOWN end

    if info.classID == Gear.CLASS_ARMOR then
        local allowed = Gear.ARMOR_BY_CLASS[classFile]
        if allowed and info.subclassID ~= nil and not allowed[info.subclassID] then
            return false, "ваш класс не носит такую броню", CONF.ESTIMATE
        end
    elseif info.classID == Gear.CLASS_WEAPON then
        local allowed = Gear.WEAPON_BY_CLASS[classFile]
        if allowed and info.subclassID ~= nil and not allowed[info.subclassID] then
            return false, "ваш класс не владеет таким оружием", CONF.ESTIMATE
        end
    end
    return true, nil, CONF.ESTIMATE
end

-- Scoring ---------------------------------------------------------------

-- CACHE LIFETIMES, AND WHY THEY DIFFER.
--
-- A rebuild used to ask the client for item data 934 times and for item stats
-- 282 times, because the candidate walk runs four times over (Upgrades,
-- Unwearable from the profit branch, Unwearable again from the diagnostics)
-- and nothing was remembered between them. In game that was a 64 ms recompute
-- against 2.8 ms before the gear branch could see anything at all.
--
--   statsCache / signatureCache / familyIndex - an item's stats and an item's
--     family are properties of the ITEM, not of this pass. They survive
--     rebuilds and are dropped only when the recipe set changes or the client
--     says new item data arrived. Failures are never cached.
--   scoreCache - a score depends on the WEIGHTS, which change when the player
--     switches profile or we work out their school. Per pass.
--   candidateCache - the candidate split depends on the snapshot. Per pass.
Gear.scoreCache = nil
Gear.statsCache = {}
Gear.signatureCache = {}
Gear.familyIndex = nil

function Gear:BeginPass()
    self.scoreCache = {}
    self.candidateCache = nil
    self.ownedSlotCache = nil
    self.nameIndex = nil
    self.statsIncomplete = 0
    self.missReasons, self.missExamples, self.missItems = nil, nil, nil
    self.statsCache = self.statsCache or {}
    self.signatureCache = self.signatureCache or {}
end

-- ДВА РАЗНЫХ СОБЫТИЯ, И СВАЛИТЬ ИХ В ОДНО СТОИЛО ТРИДЦАТИ МИЛЛИСЕКУНД.
--
-- Книга рецептов пересобирается на КАЖДОМ пересчёте (Main:RebuildInner), и она
-- звала полный сброс кешей - вместе с данными предметов. В живом файле это
-- видно прямо: itemInfo.cacheCleared = 215 при 216 пересчётах, а
-- C_Item.GetItemInfo - 50760 вызовов, то есть 235 за пересчёт. При этом новый
-- набор рецептов не меняет НИ ОДНОГО свойства предмета: ни характеристик, ни
-- класса, ни цены продажи торговцу. Он меняет только то, что выведено из самого
-- набора: список кандидатов, совпадения имён и семейства.

-- Сменился набор рецептов. Сбрасываем выведенное из него - и только.
function Gear:InvalidateRecipeSet(why)
    self.candidateCache = nil
    self.nameIndex = nil
    self.familyIndex = nil
    self.scoreCache = {}
    if ns.Diag then ns.Diag:Count("gear.recipeSetInvalidated") end
end

-- Изменились данные ПРЕДМЕТОВ (клиент догрузил, игрок позвал сброс вручную).
-- Вот тут сбрасывается всё, включая кеши в Api.
function Gear:InvalidateItemData(why)
    self.statsCache = {}
    self.signatureCache = {}
    self.familyIndex = nil
    self.scoreCache = {}
    self.candidateCache = nil
    self.ownedSlotCache = nil
    self.nameIndex = nil
    self.pendingItems = {}
    if ns.Api and ns.Api.ClearForeignItemCache then ns.Api:ClearForeignItemCache() end
    if ns.Api and ns.Api.ClearItemCache then ns.Api:ClearItemCache(why) end
end

-- Старое имя полного сброса: оставлено, потому что его зовут команды /fp и
-- тесты, и означает оно именно «данные предметов могли измениться».
Gear.InvalidateItemCache = Gear.InvalidateItemData

-- Один предмет, чьи бонусы экипировки прочитать не удалось, с причиной.
-- Причина - код от читателя базы: no-db / loading / not-in-db / no-stats.
-- Общей фразы «внешней базы предметов нет» на все случаи больше нет: это был
-- неверный диагноз в трёх случаях из четырёх.
function Gear:NoteUnreadable(itemKey, missReason)
    -- ПО ПРЕДМЕТАМ, А НЕ ПО ЧТЕНИЯМ. Один и тот же предмет читается за пересчёт
    -- несколько раз (снимок персонажа, потом ветка экипировки), и счётчик чтений
    -- превратил бы один нечитаемый пояс в «у 2 предметов» - то есть в такое же
    -- враньё, как общая фраза про отсутствующую базу.
    -- Один и тот же предмет приходит и числом, и ссылкой (надетое читается по
    -- ссылке, чтобы видеть чары), поэтому считаем по itemID: иначе один пояс
    -- оказывался «двумя предметами».
    local item = tostring(tonumber(itemKey) or U.itemIDFromLink(itemKey) or itemKey)
    -- СПИСОК ЗАКАЗА ДАННЫХ. Этот же факт попадает в FOREVERPILOT_DIAG.wanted
    -- структурой - itemID, где встретился и сколько раз, - чтобы базу можно
    -- было пополнять программно, а не вычитывая счётчики между строк.
    -- Записывается ДО проверки «уже видели»: место встречи бывает новым у
    -- предмета, который мы уже считали, и именно это место подсказывает, где
    -- искать данные.
    if ns.Diag then
        local numeric = tonumber(itemKey) or U.itemIDFromLink(itemKey)
        -- ГДЕ ВСТРЕТИЛСЯ - берётся из индекса владения, а не из того, какой
        -- цикл сейчас выполняется. Счёт предметов и их оценка - два разных
        -- прохода, и флаг «сейчас идём по сумкам» к моменту чтения
        -- характеристик уже снят: так все записи получали пометку "unknown",
        -- то есть ровно ту бесполезность, от которой этот раздел и затевался.
        local where = (numeric and self.whereByItem and self.whereByItem[numeric])
            or self.statsWhere or "unknown"
        ns.Diag:Want("itemsNotInDB", numeric or item, where,
            { reason = missReason, name = (function()
                local i = numeric and Api:ItemInfo(numeric)
                return i and i.name or nil
            end)() })
    end
    self.missItems = self.missItems or {}
    if self.missItems[item] then return end
    local key = missReason or "unknown"
    self.missItems[item] = key
    self.statsIncomplete = (self.statsIncomplete or 0) + 1
    self.missReasons = self.missReasons or {}
    self.missReasons[key] = (self.missReasons[key] or 0) + 1
    self.missExamples = self.missExamples or {}
    if #self.missExamples < 5 then
        self.missExamples[#self.missExamples + 1] = item .. ":" .. key
    end
end

-- Every stat of an item, from both sources, in our canonical keys.
--
-- THIS IS THE FIX FOR THE WORST BUG THIS ADDON HAS HAD. It used to read
-- Api:ItemStatsRaw alone, which on this client returns the item's BASE stats
-- and nothing else - no spell damage, no healing, and no per-school spell
-- damage. The worn "Жемчужный венец" is sta10 armor35 spArcane11; the client
-- reported the first two, the eleven points of arcane damage were invisible,
-- and the item scored 6.2 instead of 22.7. The addon then offered a robe with
-- generic spell power and healing as a "+16" upgrade, and the player crafted
-- it.
--
-- Returns stats, confidence, info (see StatWeights:Merge for `info`).
function Gear:ItemStats(itemKeyOrLink)
    local cacheKey = tostring(itemKeyOrLink)
    if self.statsCache then
        local c = self.statsCache[cacheKey]
        if c then
            -- Предупреждение «бонусы не читаются» считалось только на том
            -- пересчёте, где предмет прочитали ВПЕРВЫЕ: дальше ответ брался из
            -- кеша, счётчик оставался нулевым и диагностика выглядела здоровой,
            -- хотя сравнения по этим вещам по-прежнему неточные.
            if c.incomplete and c.info and c.info.missingBonuses then
                self:NoteUnreadable(cacheKey, c.info.missReason)
            end
            return c.stats, c.conf, c.info
        end
    end

    local itemID = tonumber(itemKeyOrLink) or U.itemIDFromLink(itemKeyOrLink)
    local raw = Api:ItemStatsRaw(itemKeyOrLink)
    local foreign, _, missReason
    if itemID then foreign, _, missReason = Api:ForeignItemStats(itemID) end
    local stats, conf, info = SW:Merge(raw, foreign)
    if info then info.missReason = missReason end

    if info and info.unknownKeys and ns.Diag then
        ns.Diag:Suspect("itemdb-unknown-stat",
            "внешняя база предметов вернула характеристики, которых я не знаю: "
            .. table.concat(info.unknownKeys, ", ")
            .. " — они не учтены в оценке", { itemID = itemID })
        -- И в список заказа, по КОДУ характеристики: заказывать надо не предмет,
        -- а правило для этого кода в StatWeights (сейчас это "hp5").
        for _, code in ipairs(info.unknownKeys) do
            ns.Diag:Want("statsUnknown", code, self.statsWhere or "item-db",
                { firstItemID = itemID })
        end
    end
    -- Only an item we DID read something about counts as "bonuses unreadable".
    -- An item with no stats from anybody is a different problem - the client
    -- has not cached it yet - and the gear funnel already reports that one by
    -- name. Counting both here made the warning fire on a healthy build.
    if stats and info and info.missingBonuses then
        self:NoteUnreadable(cacheKey, missReason)
    end

    -- COMPLETE ANSWERS ONLY. A failure is a "not yet", and remembering it would
    -- make the gear advice permanently blind to an item whose data arrives a
    -- second later. A PARTIAL answer is the same trap one step along: an item
    -- read from the database while the client had nothing can still improve
    -- when the client delivers its base stats, and the client wins for those.
    --
    -- Because nothing incomplete is ever cached, GET_ITEM_INFO_RECEIVED needs
    -- no invalidation at all - the next pass re-reads exactly the items that
    -- were missing something and nothing else. That matters: the client fired
    -- that event 4268 times in one session, and clearing every cache on each
    -- burst would have cost more than the caching saved.
    -- EVERYTHING IS CACHED, AND THE INCOMPLETE ONES ARE REMEMBERED AS SUCH.
    --
    -- Three bad options were tried before this one. Caching only complete
    -- answers meant every item the client had not loaded was re-read on every
    -- single rebuild - 36 calls a pass instead of 5. Caching everything and
    -- clearing the lot on GET_ITEM_INFO_RECEIVED turned the client's 4268 such
    -- events in one session into 4268 full cache rebuilds. Caching everything
    -- and never clearing would leave the advice permanently blind to an item
    -- whose data arrived a second later.
    --
    -- So: cache all of it, and keep a list of the entries that are still
    -- waiting on the client. GET_ITEM_INFO_RECEIVED drops exactly those and
    -- nothing else - see Gear:RetryPending.
    local complete = stats and info and info.complete
        and (info.fromClient or 0) > 0
    if self.statsCache then
        self.statsCache[cacheKey] = {
            stats = stats, conf = conf, info = info, incomplete = not complete,
        }
        if not complete then
            self.pendingItems = self.pendingItems or {}
            self.pendingItems[cacheKey] = true
        end
    end
    return stats, conf, info
end

-- The client says it has delivered item data. Drop only the entries that were
-- waiting for it; everything else is a property of the item and still true.
function Gear:RetryPending()
    local n = 0
    for key in pairs(self.pendingItems or {}) do
        if self.statsCache then self.statsCache[key] = nil end
        if self.scoreCache then self.scoreCache[key] = nil end
        n = n + 1
    end
    self.pendingItems = {}
    -- A signature or a family built on a partial read is suspect too.
    if n > 0 then
        self.signatureCache = {}
        self.familyIndex = nil
        self.nameIndex = nil
        if ns.Api and ns.Api.RetryMissedItems then ns.Api:RetryMissedItems() end
        if ns.Diag then ns.Diag:Count("itemCache.retried", n) end
    end
    return n
end

-- The weighted stat score of an item, in primary-stat points.
-- Returns score, confidence, canonicalStats, info.
function Gear:ItemScore(itemKeyOrLink, weights)
    local cacheKey = tostring(itemKeyOrLink)
    if self.scoreCache and self.scoreCache[cacheKey] then
        local c = self.scoreCache[cacheKey]
        return c.score, c.conf, c.stats, c.info
    end

    local canonical, conf, info = self:ItemStats(itemKeyOrLink)
    local score = canonical and SW:Score(canonical, weights) or nil

    if self.scoreCache then
        self.scoreCache[cacheKey] = { score = score, conf = conf,
                                      stats = canonical, info = info }
    end
    return score, conf, canonical, info
end

-- Stat-by-stat comparison -----------------------------------------------
--
-- A single total hides the one thing the player most needs to see. The bad
-- advice traded 11 arcane damage for 8 generic damage and 22 healing, and the
-- card printed "+16 ед. пользы" with not a word about the loss. So every
-- comparison now produces the list of stats that went DOWN, and whether one of
-- them is the point of the character's profile.
--
-- Returns nil when either side cannot be read; otherwise
--   { gains = {...}, losses = {...}, mainStatDrop, lossText, gainText,
--     total, fromScore, toScore, complete }
-- each entry being { stat, label, from, to, delta, weight, main }
function Gear:Compare(fromKeyOrLink, toKeyOrLink, weights, setKey)
    local fromStats, fromConf, fromInfo = self:ItemStats(fromKeyOrLink)
    local toStats, toConf, toInfo = self:ItemStats(toKeyOrLink)
    if not toStats then return nil end

    -- Без весов сравнивать нечем: см. weightsOf в начале файла.
    if not weights then return nil end
    setKey = setKey or (ns.CharacterScanner and ns.CharacterScanner.snapshot
        and ns.CharacterScanner.snapshot.weightSetKey) or nil
    local mains = SW:MainStats(setKey)

    -- THE MAIN GROUP IS ONE NUMBER, NOT SEVERAL.
    --
    -- For a caster, "generic spell damage" and "damage with the school I cast"
    -- feed the same spells, so they have to be compared as one quantity. Listed
    -- separately they produce nonsense in both directions: a swap from 13
    -- arcane to 20 generic reads as "−13 урона тайной магией" when it is a
    -- gain, and a swap from 11 arcane to 8 generic plus 22 healing reads as a
    -- "+16" when it is a loss. The group below is summed once; everything else
    -- is listed stat by stat.
    local mainFrom, mainTo = 0, 0
    for stat in pairs(mains) do
        mainFrom = mainFrom + ((fromStats and fromStats[stat]) or 0)
        mainTo = mainTo + (toStats[stat] or 0)
    end
    local mainStatDrop = (mainTo < mainFrom)

    local seen, gains, losses = {}, {}, {}
    local function consider(stat)
        if seen[stat] then return end
        seen[stat] = true
        -- Members of the main group are accounted for by mainFrom/mainTo.
        if mains[stat] then return end
        local weight = weights[stat] or 0
        -- A stat nobody values is not a gain and not a loss; it is noise, and
        -- listing it would bury the two lines that matter.
        if weight <= 0 then return end
        local a = (fromStats and fromStats[stat]) or 0
        local b = toStats[stat] or 0
        if a == b then return end
        local entry = {
            stat = stat, from = a, to = b, delta = b - a,
            weight = weight, main = false,
            label = Gear:StatLabel(stat),
        }
        if entry.delta > 0 then gains[#gains + 1] = entry
        else losses[#losses + 1] = entry end
    end
    for stat in pairs(toStats) do consider(stat) end
    for stat in pairs(fromStats or {}) do consider(stat) end

    -- The group gets its own entry, in or out of the loss list as it deserves.
    local mainEntry
    if mainFrom ~= mainTo then
        mainEntry = {
            stat = "MAIN", from = mainFrom, to = mainTo, delta = mainTo - mainFrom,
            weight = 1, main = true,
            label = Gear:MainGroupLabel(setKey),
        }
        if mainEntry.delta > 0 then
            table.insert(gains, 1, mainEntry)
        else
            table.insert(losses, 1, mainEntry)
        end
    end

    -- Biggest weighted move first, except the main group which always leads:
    -- it is the point of the comparison.
    local function bySize(a, b)
        if a.main ~= b.main then return a.main end
        local wa = math.abs(a.delta) * a.weight
        local wb = math.abs(b.delta) * b.weight
        if wa ~= wb then return wa > wb end
        return tostring(a.stat) < tostring(b.stat)
    end
    table.sort(gains, bySize)
    table.sort(losses, bySize)

    local function describe(list, sign)
        local parts = {}
        for i = 1, math.min(3, #list) do
            local e = list[i]
            parts[#parts + 1] = string.format("%s%d %s", sign, math.abs(e.delta), e.label)
        end
        if #list > 3 then
            parts[#parts + 1] = "и ещё " .. (#list - 3)
        end
        return (#parts > 0) and table.concat(parts, ", ") or nil
    end

    local fromScore = fromStats and SW:Score(fromStats, weights) or nil
    local toScore = SW:Score(toStats, weights)

    return {
        gains = gains, losses = losses,
        mainStatDrop = mainStatDrop,
        mainFrom = mainFrom, mainTo = mainTo,
        -- Знак минуса из ns.GLYPH: Logic/SanityChecks.lua ищет в тексте
        -- карточки именно его, и расходиться им нельзя.
        lossText = describe(losses, ns.GLYPH.MINUS),
        gainText = describe(gains, "+"),
        fromScore = fromScore, toScore = toScore,
        total = fromScore and (toScore - fromScore) or nil,
        complete = (fromInfo and fromInfo.complete and toInfo and toInfo.complete) and true or false,
        conf = U.worstConf(fromConf, toConf),
    }
end

-- A readable name for a stat. School damage gets the client's own school word
-- where the client offers one, so nothing is translated by hand.
Gear.STAT_LABEL = {
    INT = "интеллекта", SPI = "духа", STA = "выносливости",
    STR = "силы", AGI = "ловкости", ARMOR = "брони",
    SPELLPOWER = "силы магии", SPELLDMG = "урона от магии",
    HEALPOWER = "лечения",
    SPELLCRIT = "крита заклинаний", SPELLHIT = "меткости заклинаний",
    SPELLHASTE = "скорости заклинаний",
    MP5 = "восстановления маны", MANA = "маны", HEALTH = "здоровья",
    ATTACKPOWER = "силы атаки", CRIT = "крита", HIT = "меткости",
    HASTE = "скорости", EXPERTISE = "опыта боя",
    DEFENSE = "защиты", DODGE = "уворота", PARRY = "парирования",
    BLOCK = "блокирования",
    SPELLDMG_ARCANE = "урона тайной магией",
    SPELLDMG_FIRE = "урона огнём",
    SPELLDMG_FROST = "урона льдом",
    SPELLDMG_NATURE = "урона силами природы",
    SPELLDMG_SHADOW = "урона тенью",
    SPELLDMG_HOLY = "урона светом",
    DPS = "урона оружия в секунду",
}

function Gear:StatLabel(stat)
    return Gear.STAT_LABEL[stat or ""] or tostring(stat)
end

-- What to call the main stat GROUP on a card. For a caster that is "spell
-- damage counting your school", because generic and school damage are summed.
Gear.MAIN_GROUP_LABEL = {
    CASTER_DPS    = "силы магии",
    CASTER_ARCANE = "силы магии по тайной школе",
    CASTER_FIRE   = "силы магии по школе огня",
    CASTER_FROST  = "силы магии по школе льда",
    CASTER_SHADOW = "силы магии по школе тени",
    CASTER_NATURE = "силы магии по школе природы",
    CASTER_HEAL   = "силы лечения",
    MELEE_DPS     = "силы",
    TANK          = "выносливости",
    HYBRID_PHYS   = "ловкости",
}

function Gear:MainGroupLabel(setKey)
    return Gear.MAIN_GROUP_LABEL[setKey or ""] or "главной характеристики"
end

-- Naming an item when the name is not unique -----------------------------
--
-- EXACTLY ONE NAME COLLISION among the player's 265 learned recipes, and it is
-- on the item they are wearing: "Расшитый безупречный венец" is item 253975
-- (generic spell power plus healing) AND item 253979 (fire damage). Two
-- different objects, one word. Advice that says the name and nothing else is
-- ambiguous precisely where being ambiguous costs materials.
--
-- Everything in the addon keys on the itemID already; this is about the TEXT.
-- When a name is shared, the label adds what tells the two apart - the school
-- of magic, which is the only thing that differs - and the id as a last resort.

-- itemID -> the name, and name -> how many items use it. Built once per pass
-- over the candidates we already have, so it costs nothing extra.
function Gear:NameIndex()
    if self.nameIndex then return self.nameIndex end
    local byName, byItem = {}, {}
    local function note(itemID)
        if not itemID or byItem[itemID] then return end
        local info = Api:ItemInfo(itemID)
        local name = info and info.name
        if not name then return end
        byItem[itemID] = name
        byName[name] = (byName[name] or 0) + 1
    end
    local cc = self.candidateCache
    if cc then
        for _, list in ipairs({ cc.wearable or {}, cc.unwearable or {} }) do
            for _, cand in ipairs(list) do note(cand.info and cand.info.itemID) end
        end
    else
        for _, recipe in ipairs(ns.RecipeBook:Iterate(function(r)
            return r.learned and r.output
        end)) do
            note(recipe.output)
        end
    end
    -- Equipped items too: the collision was on a worn item.
    local snap = ns.CharacterScanner and ns.CharacterScanner.snapshot
    for _, equipped in pairs((snap and snap.equipped) or {}) do
        note(equipped.itemID)
    end
    self.nameIndex = { byName = byName, byItem = byItem }
    return self.nameIndex
end

-- What this item should be CALLED in a sentence. The plain name when it is
-- unique; the name plus a distinguishing tail when it is not.
function Gear:ItemLabel(itemID)
    itemID = tonumber(itemID)
    if not itemID then return "?" end
    local info = Api:ItemInfo(itemID)
    local name = (info and info.name) or U.itemFallbackName(itemID)
    local index = self:NameIndex()
    if (index.byName[name] or 0) <= 1 then return name end

    -- Shared name. Say what differs.
    local stats = self:ItemStats(itemID)
    local school, amount
    for stat, value in pairs(stats or {}) do
        local entry = ns.SCHOOL_BY_STAT[stat]
        if entry and (not amount or value > amount) then school, amount = entry, value end
    end
    if school then
        return string.format("%s (%s, #%d)", name,
            Gear:StatLabel(school.stat), itemID)
    end
    local generic = (stats and (stats[ns.STAT.SPELLDMG] or stats[ns.STAT.SPELLPOWER])) or nil
    local heal = stats and stats[ns.STAT.HEALPOWER] or nil
    if generic or heal then
        return string.format("%s (универсальная сила магии%s, #%d)", name,
            heal and " и лечение" or "", itemID)
    end
    return string.format("%s (#%d)", name, itemID)
end

function Gear:NameIsShared(itemID)
    local info = Api:ItemInfo(itemID)
    local name = info and info.name
    if not name then return false end
    return (self:NameIndex().byName[name] or 0) > 1
end

-- What is currently in a slot, scored. Returns score, conf, info.
-- An empty slot scores 0 with full confidence: empty really is zero.
function Gear:EquippedScore(slotKey, snap, weights)
    local equipped = snap and snap.equipped and snap.equipped[slotKey]
    if not equipped then return 0, CONF.EXACT, nil end
    local score, conf = self:ItemScore(equipped.link or equipped.itemID, weights)
    if score == nil then return nil, CONF.UNKNOWN, equipped end
    return score, conf, equipped
end

-- The weakest of the slots a candidate could go into, so a ring upgrade
-- replaces the worse of the two rings rather than an arbitrary one.
function Gear:WorstTargetSlot(slotKey, snap, weights)
    local targets = ns.SlotMap:TargetSlots(slotKey)
    local worstSlot, worstScore, worstConf = nil, nil, CONF.EXACT
    for _, target in ipairs(targets) do
        local score, conf = self:EquippedScore(target, snap, weights)
        if score == nil then
            -- An unreadable slot is a real unknown; prefer a readable one but
            -- do not pretend the slot is empty.
            if worstSlot == nil then worstSlot, worstScore, worstConf = target, nil, CONF.UNKNOWN end
        elseif worstScore == nil or score < worstScore then
            worstSlot, worstScore, worstConf = target, score, conf
        end
    end
    return worstSlot or targets[1], worstScore, worstConf
end

-- What putting this candidate on would actually cost the player, in score.
--
-- For most slots that is whatever sits in the one slot it replaces. For a
-- two-hander it is the main hand PLUS the off hand, because both come off.
-- Returns targetSlot, displacedScore (nil when unreadable), confidence,
-- displacedSlots.
function Gear:DisplacedValue(slotKey, snap, weights)
    local displaced = ns.SlotMap:DisplacedSlots(slotKey)
    if #displaced <= 1 then
        local target, score, conf = self:WorstTargetSlot(slotKey, snap, weights)
        return target, score, conf, { target }
    end

    local total, conf, unreadable = 0, CONF.EXACT, false
    for _, target in ipairs(displaced) do
        local score, sConf = self:EquippedScore(target, snap, weights)
        if score == nil then
            unreadable = true
            conf = CONF.UNKNOWN
        else
            total = total + score
            conf = U.worstConf(conf, sConf)
        end
    end
    if unreadable then
        return displaced[1], nil, CONF.UNKNOWN, displaced
    end
    return displaced[1], total, conf, displaced
end

-- Инструменты профессий --------------------------------------------------
--
-- Живая находка: игрок надел удочку, чтобы порыбачить, и аддон начал советовать
-- ему оружие. Слот оценивался по НАДЕТОМУ, а боевой ценности у удочки нет -
-- хотя урон у неё как раз есть и выше, чем у слабого ученического посоха, так
-- что по характеристикам инструмент от оружия не отличить. Отличается он типом:
-- класс 2, подкласс 14 («разное»: кирка, молот, нож для снятия шкур) или 20
-- (удочка). Это числа из клиента, а не слова, поэтому решение не зависит ни от
-- языка, ни от названия предмета.

-- Номера подклассов. Если клиент отдаёт Enum.ItemWeaponSubclass, берём из него:
-- так мы узнаем номера этого клиента, а не те, которые были верны когда-то.
-- Таблица из Const остаётся запасным путём и совпадает с проверенными данными.
function Gear:ToolSubclasses()
    if self.toolSubclasses then return self.toolSubclasses end
    local set = {}
    for sub in pairs(ns.TOOL_WEAPON_SUBCLASS or {}) do set[sub] = true end
    local enum = _G.Enum and _G.Enum.ItemWeaponSubclass
    if type(enum) == "table" then
        local found = 0
        for _, name in ipairs(ns.TOOL_WEAPON_SUBCLASS_NAMES or {}) do
            local v = tonumber(enum[name])
            if v then set[v] = true; found = found + 1 end
        end
        if ns.Diag then
            ns.Diag:Call("Enum.ItemWeaponSubclass", found > 0,
                "подклассов-инструментов опознано клиентом: " .. found)
        end
    elseif ns.Diag then
        ns.Diag:Call("Enum.ItemWeaponSubclass", nil,
            "клиент не отдаёт перечисление — номера взяты из Const")
    end
    self.toolSubclasses = set
    return set
end

-- Тип предмета: сначала клиент, потом внешняя база. Возвращает classID,
-- subclassID, источник ("client"/"db"). Предмет, которого нет ни там, ни там,
-- остаётся неопознанным - и тогда мы о нём ничего не утверждаем.
function Gear:ItemClass(itemKeyOrInfo)
    local info = itemKeyOrInfo
    local itemID
    if type(info) == "table" then
        itemID = tonumber(info.itemID)
    else
        if itemKeyOrInfo == nil then return nil end
        itemID = tonumber(itemKeyOrInfo) or U.itemIDFromLink(itemKeyOrInfo)
        info = Api:ItemInfo(itemKeyOrInfo)
        if type(info) == "table" then itemID = itemID or tonumber(info.itemID) end
    end
    if type(info) == "table" then
        local classID, sub = tonumber(info.classID), tonumber(info.subclassID)
        if classID and sub then return classID, sub, "client" end
    end
    if not itemID then return nil end
    local classID, sub = Api:ForeignItemClass(itemID)
    if classID and sub then return classID, sub, "db" end
    return nil
end

-- itemID, ссылка или уже прочитанный ItemInfo.
function Gear:IsProfessionTool(itemKeyOrInfo)
    local classID, sub = self:ItemClass(itemKeyOrInfo)
    if classID ~= Gear.CLASS_WEAPON or sub == nil then return false end
    return self:ToolSubclasses()[sub] and true or false
end

-- Что у игрока ЕСТЬ на этот слот ----------------------------------------
--
-- Надетое - не единственное, что есть у игрока. Оружие может лежать в сумке,
-- потому что в руке удочка; хорошая вещь может лежать в банке, потому что её
-- туда положили и забыли. Совет «скрафти оружие» в обеих ситуациях неверен, а
-- верный совет - «надень то, что у тебя уже есть» - ещё и самый дешёвый.
--
-- Индекс строится один раз на снимок: сумки дают ссылки (а значит чары и
-- суффиксы), банк - только itemID, другие персонажи не считаются вовсе, их
-- вещь надеть нельзя.
function Gear:OwnedBySlot(snap)
    local cache = self.ownedSlotCache
    if cache and cache.snap == snap then return cache.index end

    local index = {}
    local seen = {}
    local function consider(itemID, link, where, qty)
        itemID = tonumber(itemID)
        if not itemID then return end
        local key = tostring(where) .. ":" .. tostring(link or itemID)
        if seen[key] then return end
        seen[key] = true
        local info = Api:ItemInfo(link or itemID)
        local itemSlot = info and ns.SlotMap:FromEquipLoc(info.equipLoc) or nil
        local fromDB = nil
        if not itemSlot then
            -- Клиент этот предмет не закешировал (чаще всего это банк). Тип
            -- берём из внешней базы и честно помечаем, что данные не из клиента.
            local classID, sub, inv, req, quality = Api:ForeignItemClass(itemID)
            itemSlot = ns.SlotMap:FromInvNumber(inv)
            if not itemSlot then return end
            fromDB = true
            info = {
                itemID = itemID, name = (info and info.name) or nil,
                classID = classID, subclassID = sub, reqLevel = req,
                quality = quality, equipLoc = nil,
            }
        end
        if itemSlot == "BAG" or itemSlot == "SHIRT" or itemSlot == "TABARD" then
            return
        end
        local ok = self:CanEquip(info, snap)
        local entry = {
            itemID = itemID, link = link, info = info, where = where,
            slot = itemSlot, qty = tonumber(qty) or 1,
            fromDB = fromDB,
            tool = self:IsProfessionTool(info) or nil,
            twoHand = (itemSlot == "TWOHAND") or nil,
            canEquip = ok and true or false,
        }
        for _, target in ipairs(ns.SlotMap:TargetSlots(itemSlot)) do
            index[target] = index[target] or {}
            index[target][#index[target] + 1] = entry
        end
    end

    -- ГДЕ ЛЕЖИТ КАЖДЫЙ ПРЕДМЕТ, запомненное на предмет, а не на цикл. Эта
    -- карта нужна списку заказа данных: «предмет 950001 встретился в сумке» -
    -- полезный заказ, «встретился неизвестно где» - нет. Оценка характеристик
    -- происходит позже этого обхода, поэтому флага «сейчас идём по сумкам» на
    -- тот момент уже не существует, а карта существует.
    self.whereByItem = {}
    local function note(itemID, where)
        itemID = tonumber(itemID)
        if not itemID then return end
        -- Надетое важнее сумки, сумка важнее банка: если вещь и надета, и
        -- лежит второй копией в банке, добывать данные надо под надетую.
        local rank = { equipped = 3, bags = 2, bank = 1 }
        local prev = self.whereByItem[itemID]
        if (not prev) or (rank[where] or 0) > (rank[prev] or 0) then
            self.whereByItem[itemID] = where
        end
    end
    for _, s in ipairs((snap and snap.bagSlots) or {}) do
        note(s.itemID, "bags")
        consider(s.itemID, s.link, "bags", s.qty)
    end
    for itemID, qty in pairs((snap and snap.bank) or {}) do
        note(itemID, "bank")
        consider(itemID, nil, "bank", qty)
    end
    for _, e in pairs((snap and snap.equipped) or {}) do
        note(e.itemID, "equipped")
        consider(e.itemID, e.link, "equipped", 1)
    end

    self.ownedSlotCache = { snap = snap, index = index }
    return index
end

-- Боевая ценность того, что надето в слоте. Инструмент - ноль: снять удочку
-- ничего не стоит, и это ПРАВДА, а не уловка. Возвращает score, conf, worn,
-- isTool.
function Gear:WornCombatScore(slotKey, snap, weights)
    local worn = snap and snap.equipped and snap.equipped[slotKey]
    if not worn then return 0, CONF.EXACT, nil, nil end
    local info = Api:ItemInfo(worn.link or worn.itemID)
    if self:IsProfessionTool(info or worn.itemID) then
        return 0, CONF.EXACT, worn, true
    end
    local score, conf = self:ItemScore(worn.link or worn.itemID, weights)
    if score == nil then return nil, CONF.UNKNOWN, worn, nil end
    return score, conf, worn, nil
end

-- ЕДИНЫЙ ОТВЕТ НА ВОПРОС «ЧТО У ЭТОГО СЛОТА ЗА ПРЕДМЕТ».
--
-- Им пользуются все ветки: и экипировка, и чары. Пока у каждой был свой ответ,
-- ветка чар предлагала зачаровать удочку, потому что смотрела только на тело, а
-- зачарованный посох в сумке для неё не существовал - и счётчик показывал 5 из
-- 7 вместо 6 из 7.
--
-- Возвращает таблицу:
--   score, conf, itemID, link, info, label
--   where ("equipped"/"bags"/"bank"), inBag - предмет не на теле
--   enchantID - чары этого предмета (из ссылки; у банка ссылки нет)
--   toolEquipped - в слоте инструмент профессии
--   wornItemID, wornScore - что надето сейчас и сколько это стоит
--   empty - ни на теле, ни в сумках, ни в банке ничего на этот слот нет
function Gear:SlotItem(slotKey, snap, weights)
    if not slotKey then return nil end
    weights = weightsOf(snap, weights)
    -- Без весов этот ответ был бы посчитан по чужому классу, см. weightsOf.
    if not weights then return nil end

    local wornScore, wornConf, worn, isTool = self:WornCombatScore(slotKey, snap, weights)
    local out = {
        score = wornScore or 0,
        conf = wornConf or CONF.EXACT,
        toolEquipped = isTool or nil,
        wornItemID = worn and worn.itemID or nil,
        wornScore = wornScore,
        empty = (worn == nil) or nil,
    }
    -- Предмет записывается, ДАЖЕ ЕСЛИ его характеристики не читаются. Раньше
    -- нечитаемая вещь делала слот «пустым», и ветка чар теряла её вместе с
    -- чарами: на экране это было «5 из 7» при семи занятых слотах.
    if worn and not isTool then
        out.itemID, out.link, out.where = worn.itemID, worn.link, "equipped"
        out.scoreUnknown = (wornScore == nil) or nil
    end

    for _, e in ipairs(self:OwnedBySlot(snap)[slotKey] or {}) do
        if e.canEquip and not e.tool then
            local score, conf = self:ItemScore(e.link or e.itemID, weights)
            if score and score > (out.score or 0) + 0.001 then
                out.score, out.conf = score, conf
                out.itemID, out.link, out.where = e.itemID, e.link, e.where
                out.slot = e.slot
                out.twoHand = e.twoHand
            end
        end
    end
    if out.itemID then
        out.label = self:ItemLabel(out.itemID)
        -- По ссылке, а если клиент по ней не отвечает - по номеру: без info
        -- неизвестен тип вещи, и ветка чар не поймёт, что посох - двуручный.
        out.info = Api:ItemInfo(out.link or out.itemID) or Api:ItemInfo(out.itemID)
        out.inBag = (out.where ~= "equipped") or nil
        -- Чары видны в ссылке. У надетого ссылку даёт клиент, у сумки -
        -- контейнерный читатель; у банка ссылки нет, и тогда про чары мы просто
        -- ничего не знаем - и не делаем вид, что знаем.
        if out.where == "equipped" then
            local worn = snap and snap.equipped and snap.equipped[slotKey]
            out.enchantID = worn and worn.enchantID or U.enchantIDFromLink(out.link)
        elseif out.link then
            out.enchantID = U.enchantIDFromLink(out.link)
        else
            out.enchantUnknown = true
        end
    else
        out.empty = true
    end
    return out
end

-- Старое имя той же функции: она отвечала на оба вопроса - «сколько стоит
-- слот» и «что в нём лежит», - и так и осталась одной.
Gear.SlotBaseline = Gear.SlotItem

-- Против чего крафт обязан выигрывать: не против надетого, а против лучшего из
-- того, что у игрока УЖЕ ЕСТЬ на эти слоты. Для двуручного кандидата слотов
-- два, и сравнивать надо с лучшим НАБОРОМ, который игрок может надеть: либо
-- свой двуручник, либо одноручник плюс левая рука. Сумма «двуручник + щит»
-- была бы невозможной комбинацией, то есть завышенной планкой.
function Gear:OwnedFloor(slotKey, snap, weights)
    local displaced = ns.SlotMap:DisplacedSlots(slotKey)
    if #displaced <= 1 then
        local base = self:SlotBaseline(displaced[1], snap, weights)
        return base and base.score or 0, base
    end

    weights = weightsOf(snap, weights)
    if not weights then return 0, nil end
    local index = self:OwnedBySlot(snap)
    local bestTwo, bestTwoEntry = 0, nil
    local bestOne, bestOneEntry = 0, nil
    for _, e in ipairs(index["MAINHAND"] or {}) do
        if e.canEquip and not e.tool then
            local score = self:ItemScore(e.link or e.itemID, weights)
            if score then
                if e.twoHand then
                    if score > bestTwo then bestTwo, bestTwoEntry = score, e end
                elseif score > bestOne then bestOne, bestOneEntry = score, e end
            end
        end
    end
    local off = self:SlotBaseline("OFFHAND", snap, weights)
    local pair = bestOne + ((off and off.score) or 0)
    if bestTwo >= pair then
        return bestTwo, bestTwoEntry and {
            score = bestTwo, itemID = bestTwoEntry.itemID, link = bestTwoEntry.link,
            where = bestTwoEntry.where, label = self:ItemLabel(bestTwoEntry.itemID),
        } or nil
    end
    return pair, bestOneEntry and {
        score = pair, itemID = bestOneEntry.itemID, link = bestOneEntry.link,
        where = bestOneEntry.where, label = self:ItemLabel(bestOneEntry.itemID),
    } or nil
end

-- Слоты, которые мы вообще проверяем. Рубашка, накидка и сумки сюда не входят:
-- боевой ценности у них нет, и советовать по ним нечего.
function Gear:SlotsToCheck()
    if self.slotsToCheck then return self.slotsToCheck end
    local skip = { SHIRT = true, TABARD = true, BAG = true }
    local out = {}
    for key in pairs(ns.SLOT_INVENTORY_ID) do
        if not skip[key] then out[#out + 1] = key end
    end
    for key, ids in pairs(ns.SLOT_INVENTORY_PAIRS) do
        for i = 1, #ids do out[#out + 1] = key .. i end
    end
    table.sort(out)
    self.slotsToCheck = out
    return out
end

-- «Надень то, что уже есть». Самый дешёвый совет из возможных: он не стоит
-- ничего и выполняется сразу.
-- Каждая запись: { slot, itemID, link, label, where, gain, newScore, lostScore,
--                  conf, toolReplaced, wornLabel, displacedSlots }
function Gear:EquipSwaps(snap, weights)
    weights = weightsOf(snap, weights)
    if not weights then return {} end
    local funnel = ns.Diag and ns.Diag:Funnel("equipSwaps") or nil
    local bestByItem = {}

    for _, slotKey in ipairs(self:SlotsToCheck()) do
        local base = self:SlotBaseline(slotKey, snap, weights)
        if base and base.itemID and base.where and base.where ~= "equipped" then
            if funnel then funnel:In({ itemID = base.itemID, name = base.label }) end
            -- Что уйдёт с тела, если это надеть. Двуручное снимает обе руки.
            local itemSlot = base.slot or slotKey
            local displaced = ns.SlotMap:DisplacedSlots(itemSlot)
            local lost, conf, unreadable, toolReplaced, wornLabels = 0, base.conf, false, nil, {}
            for _, d in ipairs(displaced) do
                local score, sConf, worn, isTool = self:WornCombatScore(d, snap, weights)
                if score == nil then
                    unreadable = true
                else
                    lost = lost + score
                    conf = U.worstConf(conf, sConf)
                end
                if isTool then toolReplaced = true end
                if worn then
                    wornLabels[#wornLabels + 1] = self:ItemLabel(worn.itemID)
                end
            end
            local gain = (not unreadable) and (base.score - lost) or nil
            if unreadable then
                if funnel then
                    funnel:Drop("worn-unreadable", { itemID = base.itemID, name = base.label },
                        "характеристики надетого не читаются — «лучше» не утверждаю")
                end
            elseif U.isGain(gain) then
                local entry = {
                    slot = slotKey, itemID = base.itemID, link = base.link,
                    label = base.label, where = base.where,
                    gain = gain, newScore = base.score, lostScore = lost,
                    conf = conf, toolReplaced = toolReplaced,
                    wornLabel = (#wornLabels > 0) and table.concat(wornLabels, " и ") or nil,
                    displacedSlots = displaced,
                }
                local prev = bestByItem[base.itemID]
                if not prev or (prev.gain or 0) < gain then
                    bestByItem[base.itemID] = entry
                elseif funnel then
                    funnel:Drop("same-item-better-slot", { itemID = base.itemID, name = base.label })
                end
            elseif funnel then
                -- Тот же порог, что и у крафта (ns.MIN_BENEFIT_GAIN): «надеть
                -- своё» бесплатно, но совет «лучше на 0 баллов» - это всё
                -- равно строка, которая просит игрока лезть в сумки впустую.
                local even = (gain or 0) > 0
                funnel:Drop(even and "even-trade" or "not-better-than-worn",
                    { itemID = base.itemID, name = base.label },
                    string.format("%.1f против %.1f по вашим весам%s",
                        base.score, lost,
                        even and string.format(
                            " — разница %.2f, на экране это ноль", gain) or ""))
            end
        end
    end

    local out = {}
    for _, entry in pairs(bestByItem) do out[#out + 1] = entry end
    table.sort(out, function(a, b)
        if (a.gain or 0) ~= (b.gain or 0) then return (a.gain or 0) > (b.gain or 0) end
        return (a.itemID or 0) < (b.itemID or 0)
    end)
    if funnel then funnel:Finish(#out) end
    return out
end

-- Candidate collection --------------------------------------------------

-- Every learned recipe whose output is a piece of equipment, split into what we
-- can wear and what we cannot. Nothing is discarded.
-- Returns wearable, unwearable, stats
-- where stats accounts for every recipe that did NOT end up in either list, so
-- "the gear branch produced nothing" can be answered with where the data went
-- instead of a guess. The old version returned only a `pending` count, and the
-- diagnostics then blamed missing item stats for every empty result.
-- MEMOISED PER PASS, and that alone was three quarters of the cost. This runs
-- from Upgrades, from Unwearable in the profit branch, and from Unwearable
-- again in the diagnostics - four full walks of the recipe list per rebuild,
-- each one re-reading every item from the client.
function Gear:Candidates(snap)
    local cached = self.candidateCache
    if cached and cached.snap == snap then
        return cached.wearable, cached.unwearable, cached.stats
    end
    local wearable, unwearable, stats = self:ComputeCandidates(snap)
    self.candidateCache = { snap = snap, wearable = wearable,
                            unwearable = unwearable, stats = stats }
    return wearable, unwearable, stats
end

function Gear:ComputeCandidates(snap)
    local book = ns.RecipeBook
    local weights = weightsOf(snap)

    local wearable, unwearable = {}, {}
    local stats = {
        considered = 0, pending = 0, notGear = 0, otherSlot = 0,
        noStats = 0, withStats = 0,
    }

    -- The same per-filter funnel every other branch keeps, so "in = 530,
    -- out = 4" can be read as a list of named filters with an example each
    -- instead of a number nobody can account for.
    local funnel = ns.Diag and ns.Diag:Funnel("gearCandidates") or nil

    -- Где именно встретился предмет, чьи данные не прочитались: это попадает в
    -- список заказа и подсказывает, где искать. Здесь - кандидаты на крафт.
    local prevWhere = self.statsWhere
    self.statsWhere = "craft-candidate"

    for _, recipe in ipairs(book:Iterate(function(r) return r.learned and r.output end)) do
        stats.considered = stats.considered + 1
        if funnel then funnel:In(recipe) end
        local info = Api:ItemInfo(recipe.output)
        if not info then
            -- The client has not cached this item yet. It will fire
            -- GET_ITEM_INFO_RECEIVED and we will pick it up on the next pass.
            stats.pending = stats.pending + 1
            if funnel then
                funnel:Drop("item-not-cached", recipe,
                    "предмет " .. tostring(recipe.output) .. " ещё не в кеше клиента")
            end
        else
            local slot = ns.SlotMap:FromEquipLoc(info.equipLoc)
            if not slot then
                stats.notGear = stats.notGear + 1
                if funnel then funnel:Drop("not-equipment", info) end
            elseif self:IsProfessionTool(info) then
                -- Крафт удочки или кирки - это не улучшение экипировки, даже
                -- когда слот пуст и «хоть что-то» выглядит лучше ничего.
                stats.tools = (stats.tools or 0) + 1
                if funnel then
                    funnel:Drop("profession-tool", info,
                        "инструмент профессии, а не боевая экипировка")
                end
            elseif slot == "BAG" or slot == "TABARD" or slot == "SHIRT" then
                -- Real crafts, just not something with stats to compare. They
                -- are still income, and the profit branch reads the recipe book
                -- directly, so nothing is lost by leaving them out here.
                stats.otherSlot = stats.otherSlot + 1
                if funnel then funnel:Drop("slot-without-stats", info, slot) end
            else
                local ok, reason, confEquip, levelsShort = self:CanEquip(info, snap)
                local entry = {
                    recipe = recipe, info = info, slot = slot,
                    canEquip = ok, blockReason = reason,
                    equipConf = confEquip, levelsShort = levelsShort,
                    reqLevel = info.reqLevel or 0,
                }
                if ok then
                    local score = self:ItemScore(info.link or info.itemID, weights)
                    if score == nil then
                        stats.noStats = stats.noStats + 1
                        if funnel then
                            funnel:Drop("no-item-stats", info,
                                "характеристики не читаются — сравнить не с чем")
                        end
                    else
                        stats.withStats = stats.withStats + 1
                    end
                    entry.score = score
                    wearable[#wearable + 1] = entry
                else
                    unwearable[#unwearable + 1] = entry
                    if funnel then
                        funnel:Drop("cannot-equip", info,
                            tostring(reason) .. " — ушло в ветку на продажу")
                    end
                end
            end
        end
    end
    self.statsWhere = prevWhere
    -- What comes out of here is the comparable set; the rest of the branch
    -- narrows it further and keeps its own count.
    if funnel then funnel:Finish(stats.withStats) end

    stats.wearable = #wearable
    stats.unwearable = #unwearable
    return wearable, unwearable, stats
end

-- A sentence for the diagnostics that says where the recipes went.
function Gear:LossReason(stats)
    if type(stats) ~= "table" then return nil end
    local U = ns.Util
    local bits = {}
    if (stats.pending or 0) > 0 then
        -- ЧИСЛО И СЛОВО СОГЛАСОВАНЫ. Здесь стояло «N предметов» и «N рецептов»
        -- при любом N, и на настоящих данных игрока сводка читалась «82
        -- рецептов делают не экипировку», «3 предметов ещё не в кеше». Числа
        -- приходят из книги рецептов и бывают любыми, так что глазами это не
        -- проверить - проверяет правило «согласование» в Tests/sense.lua.
        bits[#bits + 1] = stats.pending .. " "
            .. U.plural(stats.pending, "предмет", "предмета", "предметов")
            .. " ещё не в кеше клиента"
    end
    if (stats.notGear or 0) > 0 then
        -- И СКАЗУЕМОЕ ТОЖЕ: «1 рецепт делаЕТ», «82 рецепта делаЮТ». Одно
        -- согласование без другого даёт «1 рецепт делают».
        bits[#bits + 1] = stats.notGear .. " "
            .. U.plural(stats.notGear, "рецепт", "рецепта", "рецептов") .. " "
            .. U.plural(stats.notGear, "делает", "делают", "делают")
            .. " не экипировку"
    end
    if (stats.otherSlot or 0) > 0 then
        bits[#bits + 1] = stats.otherSlot .. " — сумки, рубашки и накидки"
    end
    if (stats.unwearable or 0) > 0 then
        bits[#bits + 1] = stats.unwearable .. " нельзя надеть ("
            .. U.plural(stats.unwearable, "ушёл", "ушли", "ушли")
            .. " в ветку на продажу)"
    end
    if (stats.noStats or 0) > 0 then
        bits[#bits + 1] = "у " .. stats.noStats .. " надеваемых нет характеристик"
    end
    if (stats.withStats or 0) > 0 then
        bits[#bits + 1] = stats.withStats .. " "
            .. U.plural(stats.withStats, "сравним", "сравнимы", "сравнимы")
            .. " по характеристикам"
    end
    if #bits == 0 then return nil end
    return table.concat(bits, ", ")
end

-- Advice ----------------------------------------------------------------

-- Gear I can equip that beats what I have on, best first.
-- Each entry:
--   { recipe, info, slot, targetSlot, gain, currentScore, newScore,
--     plan, cost, gainPerGold, conf }
function Gear:Upgrades(snap, planner)
    planner = planner or ns.CraftingPlanner
    local weights = weightsOf(snap)
    if not weights then return {} end
    local wearable, _, stats = self:Candidates(snap)
    self.lastStats = stats
    local out = {}

    -- Only keep the best candidate per target slot, or the list turns into
    -- fifteen near-identical robes.
    local bestPerSlot = {}

    -- The second funnel of this branch, and the one that answers the question
    -- the old report could not: on the real character 128 recipes were
    -- comparable and four became cards. "не лучше надетого" is the filter that
    -- ate most of them, and that is a perfectly good answer - it just has to
    -- be written down.
    local funnel = ns.Diag and ns.Diag:Funnel("gearUpgrades") or nil

    for _, cand in ipairs(wearable) do
        if funnel then funnel:In(cand.info) end
        local newScore, newConf, _, newInfo =
            self:ItemScore(cand.info.link or cand.info.itemID, weights)
        if not newScore then
            if funnel then funnel:Drop("no-item-stats", cand.info) end
        end
        if newScore then
            local fromIncomplete = (newInfo and newInfo.missingBonuses) and true or false
            local targetSlot, curScore, curConf, displaced =
                self:DisplacedValue(cand.slot, snap, weights)

            -- ПРОТИВ ЧЕГО СРАВНИВАЕМ. Не против надетого, а против лучшего из
            -- того, что у игрока уже есть на эти слоты: вещь из сумки можно
            -- надеть бесплатно, поэтому крафт обязан выигрывать у неё, а не у
            -- удочки, которую игрок надел порыбачить.
            local floorScore, floorEntry = self:OwnedFloor(cand.slot, snap, weights)
            local betterOwned = nil
            if curScore ~= nil and floorScore and floorScore > curScore + 0.001 then
                betterOwned = floorEntry
            end
            local compareAgainst = curScore
            if curScore ~= nil and floorScore and floorScore > curScore then
                compareAgainst = floorScore
            end

            local entry
            if curScore ~= nil then
                local gain = newScore - compareAgainst

                -- Stat by stat, before anything is called an upgrade.
                local worn = snap and snap.equipped and snap.equipped[targetSlot]
                local cmp = (#displaced <= 1) and worn and self:Compare(
                    worn.link or worn.itemID, cand.info.link or cand.info.itemID,
                    weights, snap and snap.weightSetKey) or nil

                -- THE VETO. An item that lowers the stat the profile exists for
                -- is not an upgrade, whatever the total says. This is the exact
                -- rule the Pristine Circlet broke: it gave up 11 arcane damage
                -- for 8 generic plus 22 healing and came out "+16".
                -- THE OTHER HALF OF THE SCHOOL PROBLEM. When we could not work
                -- out which school the character casts - no readable spec AND
                -- no clear answer from their gear - a swap that involves school
                -- damage at all is a coin flip we must not dress up as a
                -- measurement. The neutral weights value a school bonus at its
                -- expectation, which is right on average and wrong for this
                -- specific character in two cases out of three.
                local schoolUnknown = (snap and snap.weightSetKey == "CASTER_DPS")
                local schoolInvolved = false
                if schoolUnknown and cmp then
                    for _, list in ipairs({ cmp.gains, cmp.losses }) do
                        for _, e in ipairs(list) do
                            if ns.SCHOOL_BY_STAT[e.stat] then schoolInvolved = true end
                        end
                    end
                    -- The main group hides the school members, so check the raw
                    -- stat tables too.
                    local a = self:ItemStats(worn and (worn.link or worn.itemID))
                    local b = self:ItemStats(cand.info.link or cand.info.itemID)
                    for _, t in ipairs({ a or {}, b or {} }) do
                        for stat in pairs(t) do
                            if ns.SCHOOL_BY_STAT[stat] then schoolInvolved = true end
                        end
                    end
                end

                if cmp and cmp.mainStatDrop then
                    if funnel then
                        funnel:Drop("drops-main-stat", cand.info, string.format(
                            "просаживает главную характеристику: %d -> %d",
                            cmp.mainFrom, cmp.mainTo))
                    end
                    if ns.Diag then ns.Diag:Count("gear.vetoedMainStatDrop") end
                -- A comparison built on stats we could not fully read must not
                -- be called exact: that is how a missing stat became a gain.
                elseif (fromIncomplete or (cmp and not cmp.complete)) then
                    entry = {
                        recipe = cand.recipe, info = cand.info,
                        slot = cand.slot, targetSlot = targetSlot,
                        displacedSlots = displaced,
                        compare = "incomplete",
                        gain = nil, currentScore = curScore, newScore = newScore,
                        compareDetail = cmp,
                        conf = CONF.UNKNOWN,
                    }
                elseif schoolInvolved then
                    entry = {
                        recipe = cand.recipe, info = cand.info,
                        slot = cand.slot, targetSlot = targetSlot,
                        displacedSlots = displaced,
                        compare = "school-unknown",
                        schoolUncertain = true,
                        gain = nil, currentScore = curScore, newScore = newScore,
                        compareDetail = cmp,
                        conf = CONF.UNKNOWN,
                    }
                    if ns.Diag then ns.Diag:Count("gear.schoolUnknown") end
                elseif U.isGain(gain) then
                    entry = {
                        recipe = cand.recipe, info = cand.info,
                        slot = cand.slot, targetSlot = targetSlot,
                        displacedSlots = displaced,
                        compare = "exact",
                        gain = gain, currentScore = curScore, newScore = newScore,
                        comparedAgainst = compareAgainst,
                        betterOwned = betterOwned,
                        compareDetail = cmp,
                        conf = U.worstConf(newConf, curConf, cand.recipe.conf or CONF.CACHED),
                    }
                -- РАЗМЕН, А НЕ УЛУЧШЕНИЕ. Прирост есть, но он меньше половины
                -- балла, то есть на экране он - ноль. Это и был совет со
                -- скриншота: «Теневые очки», +5 интеллекта за -8 выносливости,
                -- -1 духа и -4 брони, итог +0.27 - карточка писала «лучше на 0
                -- баллов» и предлагала потратить материалы. Порог - у
                -- ns.MIN_BENEFIT_GAIN, правило - у U.isGain.
                elseif gain > 0 then
                    if funnel then
                        funnel:Drop("even-trade", cand.info, string.format(
                            "размен, а не улучшение: %.1f против %.1f по вашим"
                            .. " весам — разница %.2f, на экране это ноль",
                            newScore, compareAgainst, gain))
                    end
                    if ns.Diag then ns.Diag:Count("gear.evenTrade") end
                elseif betterOwned then
                    -- Проиграл не надетому, а своей же вещи из сумки или банка.
                    -- Это не «нет советов», это другой совет: надеть своё.
                    if funnel then
                        funnel:Drop("already-own-better", cand.info, string.format(
                            "у вас уже есть лучше: «%s» (%s), %.1f против %.1f"
                            .. " по вашим весам",
                            tostring(betterOwned.label or "?"),
                            tostring(betterOwned.where or "?"),
                            floorScore, newScore))
                    end
                    if ns.Diag then ns.Diag:Count("gear.alreadyOwnBetter") end
                elseif funnel then
                    funnel:Drop("not-better-than-worn", cand.info, string.format(
                        "%.1f против %.1f по вашим весам у надетого",
                        newScore, curScore))
                end
            else
                -- The worn item's stats are not readable. Before, the candidate
                -- was dropped outright, which is how 263 recipes turned into no
                -- advice at all. We keep it, but we claim nothing: no gain, no
                -- comparison, and UNKNOWN confidence so the ranking demotes it.
                entry = {
                    recipe = cand.recipe, info = cand.info,
                    slot = cand.slot, targetSlot = targetSlot,
                    displacedSlots = displaced,
                    compare = "unknown",
                    gain = nil, currentScore = nil, newScore = newScore,
                    conf = CONF.UNKNOWN,
                }
            end

            if entry then
                local existing = bestPerSlot[targetSlot]
                -- A real comparison always beats an unknown one; among equals,
                -- the bigger gain (or the better item) wins.
                local function rank(e)
                    if e.compare == "exact" then return 1, e.gain or 0 end
                    return 0, e.newScore or 0
                end
                local er, ev = rank(entry)
                if existing then
                    local xr, xv = rank(existing)
                    if er > xr or (er == xr and ev > xv) then
                        bestPerSlot[targetSlot] = entry
                        if funnel then
                            funnel:Drop("beaten-in-same-slot", existing.info,
                                "нашлось лучше на слот " .. tostring(targetSlot))
                        end
                    elseif funnel then
                        funnel:Drop("beaten-in-same-slot", entry.info,
                            "на слот " .. tostring(targetSlot) .. " уже есть лучше")
                    end
                else
                    bestPerSlot[targetSlot] = entry
                end
            end
        end
    end

    for _, entry in pairs(bestPerSlot) do
        -- Which member of its school family this is, when it has one.
        entry.family = self:SchoolFamily(entry.info.itemID, snap)
        local plan = planner:Plan(entry.recipe, 1)
        entry.plan = plan
        entry.cost = plan and plan.cost or nil
        entry.costPartial = plan and plan.costPartial or nil
        entry.ready = plan and plan.ready or false
        entry.readiness = plan and plan.readiness or 0
        -- Stat points per gold spent. A free upgrade out of bag scraps should
        -- outrank a marginally better one that costs the whole wallet. "Free"
        -- is a flag, not an infinity: math.huge leaked into formatted text and
        -- into every arithmetic that touched it.
        entry.free = (entry.cost ~= nil and entry.cost <= 0) or nil
        if entry.gain and entry.cost and entry.cost > 0 then
            entry.gainPerGold = entry.gain / (entry.cost / ns.COPPER_PER_GOLD)
        else
            entry.gainPerGold = nil
        end
        if plan then entry.conf = U.worstConf(entry.conf, plan.conf) end
        out[#out + 1] = entry
    end

    -- A claimed gain outranks an unknown comparison, and the order is total so
    -- the list does not shuffle between rebuilds.
    table.sort(out, function(a, b)
        local ea = (a.compare == "exact") and 1 or 0
        local eb = (b.compare == "exact") and 1 or 0
        if ea ~= eb then return ea > eb end
        local ga, gb = a.gain or a.newScore or 0, b.gain or b.newScore or 0
        if ga ~= gb then return ga > gb end
        return (a.recipe.id or 0) < (b.recipe.id or 0)
    end)
    if funnel then funnel:Finish(#out) end
    return out
end

-- Variant families -----------------------------------------------------
--
-- A SYSTEMIC FEATURE OF THIS PATCH, not a special case. Armour comes in sets of
-- six that are identical except for the school their spell power applies to:
-- same item level, same armour, same stamina, same intellect, same spirit, and
-- then one of generic-plus-healing, arcane, fire, frost, shadow or holy. The
-- family runs the whole level range (253880-254060 and onward, and the pattern
-- repeats under other names) and the addon has to pick the member that matches
-- the character's school rather than whichever one it met first.
--
-- Detection is by numbers, never by name: two items are siblings when they take
-- the same slot, have the same item level, and agree on everything EXCEPT the
-- spell-power block. That is a fact about the data, so it survives a rename and
-- works in any language.
--
-- THE SIGNATURE USED TO INCLUDE sp AND heal, which is exactly what varies
-- across the family. The generic member - 253975, the one the player ended up
-- wearing - therefore matched nobody: the addon reported "семейство из 5"
-- instead of six and gave that item no family at all. An audit found it in four
-- of six families available now and sixteen of eighteen over the level range.

-- The whole spell-power block, which is what a family varies. Excluded from the
-- signature for that reason, and for no other.
local function isSpellPowerStat(stat)
    if ns.SCHOOL_BY_STAT[stat] then return true end
    return stat == ns.STAT.SPELLDMG
        or stat == ns.STAT.SPELLPOWER
        or stat == ns.STAT.HEALPOWER
end
Gear.IsSpellPowerStat = function(_, stat) return isSpellPowerStat(stat) end

-- A stable signature of everything about an item EXCEPT its spell power.
--
-- Memoised per pass. Without that this was the most expensive thing in a
-- rebuild: SchoolFamily was called once per equipment slot and walked all 265
-- learned recipes computing a fresh signature for each, which is roughly three
-- thousand string builds per recompute and took the rebuild from 4 ms to 11.
function Gear:FamilySignature(itemID)
    itemID = tonumber(itemID)
    if not itemID then return nil end
    local cache = self.signatureCache
    if cache and cache[itemID] ~= nil then
        return cache[itemID] or nil
    end

    local stats = self:ItemStats(itemID)
    local info = Api:ItemInfo(itemID)
    local sig
    if stats and info then
        local parts = {}
        for _, stat in ipairs(U.sortedKeys(stats)) do
            if not isSpellPowerStat(stat) then
                parts[#parts + 1] = stat .. "=" .. tostring(stats[stat])
            end
        end
        sig = table.concat({
            tostring(info.equipLoc or "?"),
            tostring(info.itemLevel or "?"),
            tostring(info.classID or "?") .. "/" .. tostring(info.subclassID or "?"),
            table.concat(parts, ","),
        }, "|")
    end
    if cache then cache[itemID] = sig or false end
    return sig
end

-- signature -> { itemID, ... } over everything the player can craft. Built once
-- per pass, so finding an item's siblings is a single table lookup instead of a
-- walk over the whole recipe book.
-- `candidates` is the list Candidates() already produced, each entry carrying
-- its recipe and its ItemInfo. Passing it costs nothing; without it the index
-- walks the recipe book and re-reads every item, which is the expensive path
-- and is kept only for callers that have no candidate list (the tests).
function Gear:FamilyIndex(candidates)
    if self.familyIndex then return self.familyIndex end
    local index = {}
    local seen = {}
    local function consider(itemID, recipeID, info)
        if not itemID or seen[itemID] then return end
        seen[itemID] = true
        -- Only equippable items have families, and the cheap check comes
        -- first so the item database is never consulted for a bandage.
        info = info or Api:ItemInfo(itemID)
        local slot = info and ns.SlotMap:FromEquipLoc(info.equipLoc)
        if not slot then return end
        local sig = self:FamilySignature(itemID)
        if not sig then return end
        local bucket = index[sig]
        if not bucket then bucket = {}; index[sig] = bucket end
        bucket[#bucket + 1] = { itemID = itemID, recipeID = recipeID }
    end

    if candidates then
        for _, list in ipairs(candidates) do
            for _, cand in ipairs(list) do
                consider(cand.info and cand.info.itemID or cand.recipe.output,
                    cand.recipe and cand.recipe.id, cand.info)
            end
        end
    else
        for _, recipe in ipairs(ns.RecipeBook:Iterate(function(r)
            return r.learned and r.output
        end)) do
            consider(recipe.output, recipe.id, nil)
        end
    end
    self.familyIndex = index
    return index
end

-- The school variants of `itemID` among everything the player can craft, and
-- which of them is right for this character.
--   { size, members = { { itemID, school, amount, score } }, best, bestSchool,
--     text }
-- nil when the item has no school damage at all, or has no siblings.
function Gear:SchoolFamily(itemID, snap)
    itemID = tonumber(itemID)
    if not itemID then return nil end
    local stats = self:ItemStats(itemID)
    if not stats then return nil end

    local hasSchool = false
    for stat in pairs(stats) do
        if ns.SCHOOL_BY_STAT[stat] then hasSchool = true; break end
    end
    -- The generic-plus-healing member has no school stat of its own and it IS a
    -- member of the family. It gets in because the signature leaves the whole
    -- spell-power block out - which is the fix: it used to include sp and heal,
    -- so that member matched nothing and had no family.
    local signature = self:FamilySignature(itemID)
    if not signature then return nil end

    local weights = weightsOf(snap)
    if not weights then return nil end
    local members = {}
    local index = self:FamilyIndex(self.candidateCache and {
        self.candidateCache.wearable, self.candidateCache.unwearable } or nil)
    for _, sib in ipairs(index[signature] or {}) do
        local s = self:ItemStats(sib.itemID)
        local school, amount
        for stat, value in pairs(s or {}) do
            local entry = ns.SCHOOL_BY_STAT[stat]
            if entry and (not amount or value > amount) then
                school, amount = entry, value
            end
        end
        members[#members + 1] = {
            itemID = sib.itemID, recipeID = sib.recipeID,
            school = school and school.key or nil,
            schoolStat = school and school.stat or nil,
            amount = amount,
            score = s and SW:Score(s, weights) or nil,
        }
    end
    if #members < 2 then return nil end

    -- СЕМЕЙСТВО РАСПОЗНАНО ЧАСТИЧНО. В этом патче семейства собираются по шесть
    -- (общая сила магии + пять школ); меньше шести - значит часть вариантов мы
    -- не нашли, и выбор «какой вариант мой» сделан по неполному набору. Это
    -- заказ на данные: не хватает либо рецептов, либо строк в базе предметов.
    if hasSchool and #members < #(ns.SPELL_SCHOOLS or {}) + 1 and ns.Diag then
        local slotKey = (function()
            local i = Api:ItemInfo(itemID)
            return i and ns.SlotMap:FromEquipLoc(i.equipLoc) or "unknown"
        end)()
        ns.Diag:Want("familiesIncomplete", slotKey, "school-family", {
            found = #members,
            expected = #(ns.SPELL_SCHOOLS or {}) + 1,
            signature = signature,
            exampleItemID = itemID,
        })
    end

    table.sort(members, function(a, b)
        local sa, sb = a.score or -1, b.score or -1
        if sa ~= sb then return sa > sb end
        return a.itemID < b.itemID
    end)

    local best = members[1]
    local mine = snap and snap.weightSetKey or nil
    local text
    if best.school then
        text = string.format(
            "Это семейство из %d вариантов: всё одинаковое, кроме школы магии."
            .. " Под ваш профиль («%s») подходит именно этот — %s.",
            #members, tostring(SW.SET_LABEL[mine or ""] or mine or "по умолчанию"),
            Gear:StatLabel(best.schoolStat))
    else
        text = string.format(
            "Это семейство из %d вариантов, отличается только школа магии."
            .. " У этого школьной магии нет вовсе — универсальная сила плюс лечение.",
            #members)
    end

    return {
        size = #members, members = members,
        best = best.itemID, bestSchool = best.school,
        bestScore = best.score,
        hasSchool = hasSchool,
        text = text,
    }
end

-- Gear I can make but cannot use. Not advice on its own - this is the input to
-- the profit branch, and on this realm it is the big one.
function Gear:Unwearable(snap)
    local list = select(2, self:Candidates(snap))
    table.sort(list, function(a, b)
        if a.reqLevel ~= b.reqLevel then return a.reqLevel > b.reqLevel end
        return a.recipe.id < b.recipe.id
    end)
    return list
end

-- A short summary for the character tab: which slots are empty, which are
-- unreadable, and the total weighted score of the current kit.
function Gear:Audit(snap)
    local weights = weightsOf(snap)
    local rows, total, conf = {}, 0, CONF.EXACT
    local allSlots = {
        "HEAD", "NECK", "SHOULDER", "BACK", "CHEST", "WRIST", "HANDS",
        "WAIST", "LEGS", "FEET", "FINGER1", "FINGER2", "TRINKET1", "TRINKET2",
        "MAINHAND", "OFFHAND", "RANGED",
    }
    for _, slotKey in ipairs(allSlots) do
        local equipped = snap and snap.equipped and snap.equipped[slotKey]
        local score, sConf = self:EquippedScore(slotKey, snap, weights)
        local info = equipped and Api:ItemInfo(equipped.itemID) or nil
        local row = {
            slot = slotKey,
            label = ns.SlotMap:Label(slotKey),
            itemID = equipped and equipped.itemID or nil,
            link = equipped and equipped.link or nil,
            name = info and info.name or (equipped and U.itemFallbackName(equipped.itemID) or nil),
            empty = (equipped == nil),
            score = score,
            conf = sConf,
            enchantID = equipped and equipped.enchantID or nil,
            enchantable = ns.SlotMap:IsEnchantable(slotKey),
        }
        rows[#rows + 1] = row
        if score then total = total + score else conf = CONF.UNKNOWN end
        conf = U.worstConf(conf, sConf)
    end
    return rows, total, conf
end

return Gear
