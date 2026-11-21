-- ForeverPilot / Logic/CharacterScanner.lua
--
-- One snapshot of the character: who they are, what they are wearing, what is
-- in their bags and bank, what they can make and how much gold they have.
-- Every field carries its own confidence, because "the bank is empty" and "we
-- have never seen the bank" are different answers and the player deserves to
-- know which one they are getting.
local ADDON, ns = ...

local U = ns.Util
local Api = ns.Api
local CONF = ns.CONF

local Scanner = {}
ns.CharacterScanner = Scanner

Scanner.snapshot = nil

local function emptySnapshot()
    return {
        name = nil, surname = nil, fullName = nil,
        level = nil, classFile = nil, className = nil,
        raceName = nil, factionFile = nil, realm = nil, guid = nil,
        spec = nil, weightSetKey = nil, weights = nil,
        money = 0, moneyConf = CONF.UNKNOWN,
        professions = {}, professionsConf = CONF.UNKNOWN,
        equipped = {}, equippedConf = CONF.UNKNOWN,
        bags = {}, bagsConf = CONF.UNKNOWN, bagSlots = {},
        bank = nil, bankConf = CONF.UNKNOWN,
        alts = nil, altsConf = CONF.UNKNOWN,
        owned = {}, ownedConf = CONF.UNKNOWN,
        -- Баффы на игроке. auraSource = nil значит «прочитать было нечем», а
        -- не «баффов нет» (см. Api:PlayerAuras).
        auras = {}, auraByName = {}, auraSource = nil,
        scannedAt = 0,
    }
end

-- Known profession names, in every spelling we may be handed. Used to filter
-- the skill window, which also lists weapon skills and languages.
local PROFESSION_HINTS = {
    "портняж", "tailor", "кожевн", "leatherwork", "кузнеч", "blacksmith",
    "инженер", "engineer", "ювелир", "jewelcraft", "начертан", "inscription",
    "алхим", "alchemy", "наложение чар", "чары", "enchant",
    "кулинар", "cooking", "первая помощь", "first aid",
    "рыбная ловля", "рыбол", "fishing",
    "горное дело", "mining", "травнич", "herbal", "снятие шкур", "skinning",
    "археолог", "archaeolog",
}

local function looksLikeProfession(name)
    if type(name) ~= "string" then return false end
    local lower = U.lower(name)
    for _, hint in ipairs(PROFESSION_HINTS) do
        if lower:find(hint, 1, true) then return true end
    end
    return false
end

-- Gathering professions make nothing, so the crafting advice ignores them.
local GATHERING_HINTS = {
    "горное дело", "mining", "травнич", "herbal", "снятие шкур", "skinning",
    "рыбная ловля", "рыбол", "fishing", "археолог", "archaeolog",
}

local function isGathering(name)
    if type(name) ~= "string" then return false end
    local lower = U.lower(name)
    for _, hint in ipairs(GATHERING_HINTS) do
        if lower:find(hint, 1, true) then return true end
    end
    return false
end

-- Scan -------------------------------------------------------------------

function Scanner:Scan()
    local snap = emptySnapshot()
    snap.scannedAt = Api:ServerTime()

    local p = Api:PlayerInfo()
    snap.name, snap.guid, snap.level = p.name, p.guid, p.level
    -- ФАМИЛИЯ И ПОЛНОЕ ИМЯ ОТДЕЛЬНЫМИ ПОЛЯМИ.
    --
    -- snap.name остаётся именем без фамилии: так его показывает клиент, и так
    -- он выглядит в заголовке окна. А сравнивать с чужими аддонами надо ПОЛНЫМ
    -- именем - по нему персонажа знают почта, Syndicator и Mastercraft. Из-за
    -- того, что раньше было только одно поле, текущий персонаж не узнавался
    -- среди своих же и попадал в список чужих.
    snap.surname = p.surname
    snap.fullName = p.fullName
        or (Api.FullName and Api:FullName(p.name, p.surname)) or p.name
    snap.classFile, snap.className = p.classFile, p.className
    snap.raceName, snap.factionFile = p.raceName, p.factionFile
    snap.realm = p.realm

    local spec = Api:SpecInfo()
    snap.spec = spec and spec.name or nil
    snap.specConf = spec and spec.conf or CONF.UNKNOWN

    snap.money, snap.moneyConf = Api:Money()

    -- Professions. The scanner keeps everything the game reports but tags the
    -- crafting ones, because only those can be acted on.
    --
    -- One profession, one entry. This client hands the same skill line back
    -- under more than one id - the profession list and the skill window both
    -- report it - and the adapter faithfully returns both, so the real
    -- character arrived here with every profession twice: ten entries for five
    -- professions, eight "crafting professions" for four. The duplicates
    -- reached the player as a card reading "Навык на пределе: 8 профессий" with
    -- each name printed twice. Merged on the name, because the name is what the
    -- player has and what the recipe book is keyed by; the id is the thing that
    -- differs between the duplicates and so cannot be the key.
    local profs, profConf = Api:Professions()
    local filtered, byName = {}, {}

    -- НОМЕР ЛИНИИ НАВЫКА ТЕРЯЛСЯ ВМЕСТЕ С ДУБЛИКАТОМ, И ЭТО СТОИЛО ВЕТКИ.
    --
    -- Клиент отдаёт одну профессию дважды и с РАЗНЫМИ номерами линии: список
    -- профессий - современными (2948 портняжка, 2940 чары), окно навыков -
    -- классическими (197, 333). Склейка оставляла один номер, и это оказывался
    -- современный, а все наши данные - пороги в Data/Horizon.lua и роли
    -- тренеров в Codex - размечены классическими. В живой игре ветка
    -- «Благосклонность торговца» из-за этого сообщала «навыка пока не хватает»
    -- при навыке 225 против порога 60, а Codex отвечал пусто на запросы
    -- trainer:2940 и trainer:2948.
    --
    -- Теперь склейка НИЧЕГО НЕ ВЫБРАСЫВАЕТ: все номера, которые отдал клиент,
    -- остаются в skillLineIDs, а главным становится тот, который наши данные
    -- знают. Ни один номер здесь не выдумывается - все приходят от клиента.
    local function mergeLines(keep, other)
        local seen, list = {}, {}
        local function add(id)
            id = tonumber(id)
            if not id or seen[id] then return end
            seen[id] = true
            list[#list + 1] = id
        end
        for _, row in ipairs({ keep, other }) do
            for _, id in ipairs((row and row.skillLineIDs) or {}) do add(id) end
            add(row and row.skillLineID)
        end
        table.sort(list)
        keep.skillLineIDs = list
        -- Главный номер: знакомый нашим данным, иначе тот, что уже стоял.
        local FS = ns.ForeverSource
        if FS and FS.KnowsSkillLine then
            for _, id in ipairs(list) do
                if FS:KnowsSkillLine(id) then
                    keep.skillLineID = id
                    return keep
                end
            end
        end
        keep.skillLineID = tonumber(keep.skillLineID) or list[1]
        return keep
    end

    -- Which of two records for one profession to believe: real numbers beat
    -- blanks, a known ceiling beats an unknown one, and a higher skill beats a
    -- lower one. Never invents a value by mixing the two.
    local function betterProf(a, b)
        if (a.skillTrusted and true or false) ~= (b.skillTrusted and true or false) then
            return a.skillTrusted and a or b
        end
        local aMax = (tonumber(a.max) or 0) > 0
        local bMax = (tonumber(b.max) or 0) > 0
        if aMax ~= bMax then return aMax and a or b end
        if (tonumber(a.skill) or 0) ~= (tonumber(b.skill) or 0) then
            return ((tonumber(a.skill) or 0) > (tonumber(b.skill) or 0)) and a or b
        end
        -- Equal evidence: keep the one that did not come from the skill window,
        -- because that is the profession-authoritative source.
        if (a.fromSkillWindow and true or false) ~= (b.fromSkillWindow and true or false) then
            return a.fromSkillWindow and b or a
        end
        return a
    end

    for _, prof in ipairs(profs) do
        if (not prof.fromSkillWindow) or looksLikeProfession(prof.name) then
            prof.gathering = isGathering(prof.name)
            prof.crafting = not prof.gathering
            -- Merged on the name, so a record without one cannot be merged:
            -- two nameless professions are not evidence of one profession,
            -- and "" as a key would silently make them the same.
            local key = (type(prof.name) == "string" and prof.name ~= "")
                and U.lower(prof.name) or nil
            local seen = key and byName[key] or nil
            if not key then
                filtered[#filtered + 1] = prof
            elseif seen then
                local keep = betterProf(seen.prof, prof)
                local other = (keep == seen.prof) and prof or seen.prof
                -- The duplicate is recorded rather than dropped silently: the
                -- diagnostics should be able to say the client double-reported.
                keep.duplicates = (seen.prof.duplicates or 0) + 1
                mergeLines(keep, other)
                filtered[seen.index] = keep
                byName[key] = { prof = keep, index = seen.index }
            else
                filtered[#filtered + 1] = prof
                byName[key] = { prof = prof, index = #filtered }
            end
        end
    end
    table.sort(filtered, function(a, b)
        if a.crafting ~= b.crafting then return a.crafting end
        return (a.name or "") < (b.name or "")
    end)
    snap.professions, snap.professionsConf = filtered, profConf

    -- Equipment, with the enchant already decoded out of each item link.
    snap.equipped, snap.equippedConf = Api:Equipped()

    -- Баффы: что на игроке действует прямо сейчас.
    if Api.PlayerAuras then
        snap.auras, snap.auraSource = Api:PlayerAuras()
        for _, a in ipairs(snap.auras) do
            if a.name then snap.auraByName[a.name] = a end
        end
    end

    -- STAT WEIGHTS COME AFTER THE EQUIPMENT, ON PURPOSE. When the client will
    -- not say what spec the character is - and at low level there may be no
    -- talents to read - the school is worked out from what they are wearing
    -- instead. That needs the equipment list, so this cannot run before it.
    -- Picking the school-blind set here is what let an arcane mage be told to
    -- craft a robe with healing on it.
    local weights, setKey, wConf, how =
        ns.StatWeights:Active(snap.classFile, snap.spec, snap)
    snap.weights, snap.weightSetKey, snap.weightConf = weights, setKey, wConf
    snap.weightSource = how

    -- Bags.
    local bagCounts, bagConf, bagSlots = Api:BagCounts()
    snap.bags, snap.bagsConf, snap.bagSlots = bagCounts, bagConf, bagSlots

    -- Bank. nil means "we have not seen it", which is not the same as empty.
    local cfg = ns.Config:Get()
    if cfg.show.includeBank then
        local bankCounts, bankConf = Api:BankCounts()
        snap.bank, snap.bankConf = bankCounts, bankConf
    else
        snap.bank, snap.bankConf = nil, CONF.UNKNOWN
    end

    -- Other characters, if an inventory addon is sharing its cache.
    if cfg.show.includeOtherChars then
        snap.alts, snap.altsConf = self:ScanAlts(snap)
    end

    snap.owned, snap.ownedConf = self:BuildOwned(snap)
    self.snapshot = snap

    -- ЗАПИСАТЬ СЕБЯ В РЕЕСТР - ПОСЛЕДНИМ ДЕЛОМ И ПОСЛЕ ВСЕГО.
    --
    -- Профессии персонажа лежат в SavedVariablesPerCharacter, и пока игрок
    -- играет магом, файла чернокнижника для него не существует: игра его не
    -- загружает. Syndicator, из которого берутся сумки альтов, профессий не
    -- хранит вовсе. Значит единственный способ узнать потом, что у
    -- чернокнижника есть алхимия, - запомнить это сейчас, пока им играют.
    -- Отсюда же ветка «между персонажами» перестаёт утверждать «профессий
    -- нет» про того, про кого она просто ничего не знала.
    --
    -- Зовётся ПОСЛЕ заполнения снимка, потому что пишет из него; и обёрнуто в
    -- pcall, потому что запись в сохранёнку не должна иметь права уронить
    -- сканирование - без снимка не работает вообще ничего.
    if ns.Roster then
        local ok, err = pcall(function() return ns.Roster:Remember(snap) end)
        if not ok and ns.Diag then
            ns.Diag:Log("реестр персонажей не записался", { error = tostring(err) })
        end
    end
    return snap
end

-- Other characters' bags and banks, read from an optional inventory addon.
function Scanner:ScanAlts(snap)
    if not Api:SyndicatorPresent() then return nil, CONF.UNKNOWN end
    local names = Api:SyndicatorCharacters()
    if type(names) ~= "table" then return nil, CONF.UNKNOWN end

    local out = {}
    for _, fullName in ipairs(names) do
        local data = Api:SyndicatorCharacter(fullName)
        if type(data) == "table" then
            local isSelf = snap.name and data.details and data.details.character == snap.name
                and data.details.realm == snap.realm
            local counts = {}
            local function take(container)
                for _, slot in pairs(container or {}) do
                    if type(slot) == "table" and slot.itemID then
                        U.addTo(counts, slot.itemID, tonumber(slot.itemCount) or 1)
                    end
                end
            end
            for _, bag in pairs(data.bags or {}) do take(bag) end
            take(data.bank)
            for _, tab in pairs(data.bankTabs or {}) do take(tab.slots) end

            out[#out + 1] = {
                fullName = fullName,
                name = data.details and data.details.character or fullName,
                className = data.details and data.details.className or nil,
                money = tonumber(data.money) or 0,
                counts = counts,
                isSelf = isSelf and true or false,
            }
        end
    end
    if #out == 0 then return nil, CONF.UNKNOWN end
    table.sort(out, function(a, b) return (a.fullName or "") < (b.fullName or "") end)
    return out, CONF.CACHED
end

-- What the player can reach without buying anything.
--   owned[itemID] = { here = n, bank = n, alts = n, total = n }
-- "here" is what a craft can consume right now; bank and alt stock still count
-- as owned but the card has to tell the player to go and fetch it.
function Scanner:BuildOwned(snap)
    local owned = {}
    local function bump(itemID, field, qty)
        qty = tonumber(qty) or 0
        if qty <= 0 then return end
        local e = owned[itemID]
        if not e then e = { here = 0, bank = 0, alts = 0, total = 0 }; owned[itemID] = e end
        e[field] = e[field] + qty
        e.total = e.total + qty
    end

    for itemID, qty in pairs(snap.bags or {}) do bump(itemID, "here", qty) end
    for itemID, qty in pairs(snap.bank or {}) do bump(itemID, "bank", qty) end

    if snap.alts then
        for _, alt in ipairs(snap.alts) do
            if not alt.isSelf then
                for itemID, qty in pairs(alt.counts) do bump(itemID, "alts", qty) end
            end
        end
    end

    local conf = U.worstConf(snap.bagsConf, snap.bank and snap.bankConf or CONF.EXACT)
    return owned, conf
end

-- Accessors --------------------------------------------------------------

function Scanner:Get()
    return self.snapshot
end

-- How many of this item the player can use for a craft started right now.
function Scanner:Here(itemID)
    local snap = self.snapshot
    if not snap then return 0 end
    return (snap.bags and snap.bags[itemID]) or 0
end

function Scanner:Owned(itemID)
    local snap = self.snapshot
    if not snap then return nil end
    return snap.owned and snap.owned[itemID] or nil
end

function Scanner:TotalOwned(itemID)
    local e = self:Owned(itemID)
    return e and e.total or 0
end

-- A copy of the "here" counts, for the planner to spend down without touching
-- the real snapshot.
function Scanner:HereCopy()
    local snap = self.snapshot
    if not snap then return {} end
    return U.copy(snap.bags or {})
end

function Scanner:OwnedCopy(includeBank, includeAlts)
    local snap = self.snapshot
    if not snap then return {} end
    local out = {}
    for itemID, e in pairs(snap.owned or {}) do
        local n = e.here
        if includeBank then n = n + e.bank end
        if includeAlts then n = n + e.alts end
        if n > 0 then out[itemID] = n end
    end
    return out
end

-- The crafting professions, which is what the advice modules iterate.
function Scanner:CraftingProfessions()
    local snap = self.snapshot
    if not snap then return {} end
    local out = {}
    for _, prof in ipairs(snap.professions or {}) do
        if prof.crafting then out[#out + 1] = prof end
    end
    return out
end

-- ЕСТЬ ЛИ У ПЕРСОНАЖА НАЛОЖЕНИЕ ЧАР.
--
-- Здесь было сравнение локализованного имени по подстроке - lower:find("чар") -
-- то есть ровно тот приём, против которого предупреждают комментарии в
-- Logic/Favor.lua и Core/Api.lua: имя приходит на языке клиента, и "чар"
-- совпадёт с любым словом, где эти три буквы встретились. Функция при этом
-- НИКЕМ не вызывалась, то есть была мёртвым кодом с неправильным способом -
-- худшее сочетание: пример, с которого его скопируют.
--
-- Теперь спрашивается у книги рецептов: формулы чар есть только у
-- зачарователя, и это свойство самих рецептов (нет выхода + есть реагенты), а
-- не имени профессии. Так же отвечает Logic/Disenchant.lua - одним способом, а
-- не двумя разными.
function Scanner:HasEnchanting()
    local FS = ns.ForeverSource
    for _, prof in ipairs(self:CraftingProfessions()) do
        -- Номер линии навыка, а не имя: 333 - наложение чар, и этот номер
        -- одинаков на любом языке клиента.
        local line = FS and FS.ResolveSkillLine and FS:ResolveSkillLine(prof) or nil
        if tonumber(line) == 333 then return true, prof end
    end
    -- Запасной путь, когда номер линии не сопоставился: выученные формулы чар.
    -- Формула - рецепт без выходного предмета, и ни у одной другой профессии
    -- таких нет.
    if ns.EnchantAdvisor and ns.EnchantAdvisor.LearnedFormulas then
        local formulas = ns.EnchantAdvisor:LearnedFormulas()
        if formulas and #formulas > 0 then return true, nil end
    end
    return false
end

-- The junk the player is carrying: poor-quality items with a sell price.
function Scanner:Junk()
    local snap = self.snapshot
    if not snap then return {} end
    local out = {}
    for _, slot in ipairs(snap.bagSlots or {}) do
        if slot.quality == ns.QUALITY_POOR and not slot.noValue then
            local info = Api:ItemInfo(slot.itemID)
            local unit = info and info.sellPrice or 0
            if unit > 0 then
                out[#out + 1] = {
                    itemID = slot.itemID, qty = slot.qty, unit = unit,
                    total = unit * slot.qty,
                    name = info and info.name or U.itemFallbackName(slot.itemID),
                    link = slot.link,
                    -- Качество и привязанность едут с позицией, а не
                    -- пересчитываются потом: по ним ветка «продать хлам»
                    -- спрашивает про облик, и спрашивать она обязана про ту же
                    -- вещь, которую отобрали здесь.
                    quality = slot.quality,
                    bound = slot.bound,
                }
            end
        end
    end
    table.sort(out, function(a, b) return a.total > b.total end)
    return out
end

return Scanner
