-- ForeverPilot / Logic/RecipeBook.lua
--
-- Everything the addon knows about recipes, in one place and in one shape.
--
-- Three sources, strongest first:
--   own    - we scanned the profession window ourselves this session (EXACT)
--   stored - our own scan from a previous session, in SavedVariables (CACHED)
--   foreign- another addon's cache sitting in a global SavedVariables table,
--            read-only (CACHED). This is what lets the Now tab say something
--            useful before the player has opened a single profession window.
--
-- When a profession has no source at all we record that fact, and the engine
-- turns it into a "open your tailoring window once" card instead of silence.
local ADDON, ns = ...

local U = ns.Util
local Api = ns.Api
local CONF = ns.CONF

local RecipeBook = {}
ns.RecipeBook = RecipeBook

RecipeBook.byProfession = {}  -- professionName -> { source, scanned, conf, list = {recipe,...} }
RecipeBook.byID = {}          -- recipeID -> recipe
RecipeBook.byOutput = {}      -- itemID -> { recipe, ... }  (learned recipes only)
RecipeBook.enchantsBySlot = {} -- slotKey -> { recipe, ... } (learned only)
RecipeBook.missingProfessions = {}

function RecipeBook:Reset()
    self.byProfession, self.byID, self.byOutput = {}, {}, {}
    self.enchantsBySlot, self.missingProfessions = {}, {}
    self:InvalidateEnchantCache()
end

-- Normalisation ----------------------------------------------------------

-- Bring a recipe from any source into our shape. Foreign caches use the same
-- field names for the parts we care about, but we never trust that: every field
-- is read defensively and a recipe missing an id or a name is dropped.
function RecipeBook:Normalize(raw, professionName)
    if type(raw) ~= "table" then return nil end
    local id = tonumber(raw.id)
    local name = U.trim(raw.name)
    if not (id and name) then return nil end

    local reagents = {}
    if type(raw.reagents) == "table" then
        for _, r in ipairs(raw.reagents) do
            local itemID = tonumber(r and r.itemID)
            local qty = tonumber(r and r.qty) or 1
            if itemID and qty > 0 then
                reagents[#reagents + 1] = { itemID = itemID, qty = qty }
            end
        end
    end

    local qty = tonumber(raw.outputQty) or 1
    return {
        id = id,
        name = name,
        icon = raw.icon,
        learned = raw.learned and true or false,
        diff = raw.diff,
        categoryID = raw.categoryID,
        categoryName = U.trim(raw.category) or U.trim(raw.categoryName),
        groupName = U.trim(raw.group) or U.trim(raw.groupName),
        output = tonumber(raw.output),
        outputQty = (qty > 0) and qty or 1,
        reagents = reagents,
        -- More than one acceptable reagent in a slot: the cost we compute is
        -- for the first one the client listed, so it is not exact.
        reagentChoices = tonumber(raw.reagentChoices),
        cooldown = tonumber(raw.cooldown),
        profession = professionName,
    }
end

-- Collapse duplicate reagent slots: two slots of the same item become one with
-- the quantities added. The planner depends on this.
function RecipeBook:MergedReagents(recipe)
    if type(recipe) ~= "table" or type(recipe.reagents) ~= "table" then return {} end
    local merged, order = {}, {}
    for _, r in ipairs(recipe.reagents) do
        if merged[r.itemID] == nil then order[#order + 1] = r.itemID end
        merged[r.itemID] = (merged[r.itemID] or 0) + r.qty
    end
    local out = {}
    for _, itemID in ipairs(order) do
        out[#out + 1] = { itemID = itemID, qty = merged[itemID] }
    end
    return out
end

-- Ingest -----------------------------------------------------------------

RecipeBook.SOURCE_RANK = { own = 3, stored = 2, foreign = 1 }

-- One profession, one bucket - whatever the source chose to call it.
--
-- THIS IS WHY THE LIST SHOWED EVERY CARD TWICE. The book is keyed by profession
-- NAME. Our own cache stores the localised name the client gave us ("Портняжное
-- дело"); the foreign cache stores the English one ("Tailoring"). The source
-- ranking below was meant to keep only the better of two records for the same
-- profession, but it compared `self.byProfession[professionName]`, and those two
-- keys never collide. So both buckets survived: byProfession held ten entries
-- for five professions, every recipe came out of Iterate twice, LearnedCount
-- read 530 instead of 265, and the Now tab showed "Льняные сапоги" twice with
-- identical scores down to the last digit.
--
-- So the key is resolved through the same bridge Bucket() uses before anything
-- is stored. Exact match or a known translation only - deliberately NOT the
-- substring fallback Bucket() ends with, because merging two professions that
-- merely share a few letters would be a far worse bug than the one being fixed.
function RecipeBook:ResolveKey(professionName)
    if not professionName then return nil end
    if self.byProfession[professionName] then return professionName end
    local want = U.lower(professionName)
    if not want then return nil end
    for name in pairs(self.byProfession) do
        if U.lower(name) == want then return name end
    end
    local bridge = RecipeBook.NAME_BRIDGE[want]
    if bridge then
        for name in pairs(self.byProfession) do
            if U.lower(name) == bridge then return name end
        end
    end
    return nil
end

-- Which of two names for one profession the player should see. The localised
-- one, because that is what their client says and what the skill window shows;
-- the English name only survives when it is all we have.
function RecipeBook:PreferredName(a, b)
    if not b then return a end
    if not a then return b end
    local function localised(name)
        local lower = U.lower(name) or ""
        -- A name that the bridge maps to an English one is the localised side.
        local mapped = RecipeBook.NAME_BRIDGE[lower]
        if not mapped then return false end
        return RecipeBook.NAME_BRIDGE[mapped] == lower and lower ~= mapped
    end
    local la, lb = localised(a), localised(b)
    if la ~= lb then return la and a or b end
    return a
end

function RecipeBook:Store(professionName, rawList, source, conf, scanned)
    professionName = U.trim(professionName)
    if not professionName then return 0 end
    local list = {}
    for _, raw in ipairs(rawList or {}) do
        local rec = self:Normalize(raw, professionName)
        if rec then list[#list + 1] = rec end
    end
    if #list == 0 then return 0 end

    local rank = RecipeBook.SOURCE_RANK
    local existingKey = self:ResolveKey(professionName)
    local existing = existingKey and self.byProfession[existingKey] or nil
    if existing and (rank[existing.source] or 0) > (rank[source] or 0) then
        -- Something better is already here. Record the alias so Bucket() finds
        -- this profession under either spelling without a second bucket.
        existing.aliases = existing.aliases or {}
        existing.aliases[professionName] = true
        if ns.Diag then ns.Diag:Count("recipeBook.sourceMerged") end
        return 0
    end

    -- The new source wins. Exactly one bucket survives, under the name the
    -- player is more likely to recognise, and the other key is dropped.
    local keepName = existingKey
        and self:PreferredName(professionName, existingKey)
        or professionName
    local aliases = (existing and existing.aliases) or {}
    aliases[professionName] = true
    if existingKey then aliases[existingKey] = true end
    aliases[keepName] = nil
    if existingKey and existingKey ~= keepName then
        self.byProfession[existingKey] = nil
        if ns.Diag then ns.Diag:Count("recipeBook.sourceUpgraded") end
    end

    self.byProfession[keepName] = {
        source = source, conf = conf, scanned = scanned or 0, list = list,
        name = keepName, aliases = aliases, storedAs = professionName,
    }
    return #list
end

function RecipeBook:Reindex()
    self:InvalidateEnchantCache()
    -- Сбрасывается ВЫВЕДЕННОЕ ИЗ НАБОРА РЕЦЕПТОВ, а не данные предметов: книга
    -- пересобирается на каждом пересчёте, и полный сброс кешей здесь стоил 235
    -- обращений к клиенту за предметами на каждый пересчёт.
    if ns.GearAdvisor and ns.GearAdvisor.InvalidateRecipeSet then
        ns.GearAdvisor:InvalidateRecipeSet("пересобрана книга рецептов")
    end
    self.byID, self.byOutput, self.enchantsBySlot = {}, {}, {}
    for _, bucket in pairs(self.byProfession) do
        for _, rec in ipairs(bucket.list) do
            rec.conf = bucket.conf
            rec.source = bucket.source
            self.byID[rec.id] = rec

            if rec.learned then
                if rec.output then
                    local arr = self.byOutput[rec.output]
                    if not arr then arr = {}; self.byOutput[rec.output] = arr end
                    arr[#arr + 1] = rec
                else
                    -- No output item: this is an enchant (or a recipe whose
                    -- schematic the client has not sent us yet).
                    local slot = ns.SlotMap:EnchantSlot(rec)
                    rec.enchantSlot = slot
                    if slot then
                        local arr = self.enchantsBySlot[slot]
                        if not arr then arr = {}; self.enchantsBySlot[slot] = arr end
                        arr[#arr + 1] = rec
                    end
                end
            end
        end
    end
end

-- Scan the profession window that is open right now. Returns profession, count.
function RecipeBook:ScanOpenWindow()
    local profName = Api:OpenProfessionName()
    local ids = Api:AllRecipeIDs()
    if not (profName and ids) then return nil, 0 end

    local list = {}
    for _, id in ipairs(ids) do
        local rec = Api:ReadRecipe(id)
        if rec then list[#list + 1] = rec end
    end
    if #list == 0 then return profName, 0 end

    local now = Api:ServerTime()
    local stored = self:Store(profName, list, "own", CONF.EXACT, now)
    -- Persist so the next session starts warm.
    ns.Config:StoreRecipes(profName, list, now)
    self:Reindex()

    if ns.Diag then
        local learned, withOutput, withReagents = 0, 0, 0
        for _, r in ipairs(list) do
            if r.learned then learned = learned + 1 end
            if r.output then withOutput = withOutput + 1 end
            if #(r.reagents or {}) > 0 then withReagents = withReagents + 1 end
        end
        ns.Diag:Log("прочитано окно профессии: " .. profName, {
            ids = #ids, parsed = #list, stored = stored,
            learned = learned, withOutput = withOutput,
            withReagents = withReagents,
            -- Recipes with no output and no reagents mean the schematic never
            -- arrived, which makes them useless to the planner.
            emptySchematics = #list - withReagents,
        })
        ns.Diag:Call("C_TradeSkillUI.GetRecipeSchematic", withReagents > 0,
            string.format("рецептов с реагентами %d из %d", withReagents, #list))
    end
    return profName, stored
end

-- Load our own cache from SavedVariables.
function RecipeBook:LoadStored()
    local total = 0
    for profName, bucket in pairs(ns.Config:StoredRecipes()) do
        if type(bucket) == "table" and type(bucket.list) == "table" then
            total = total + self:Store(profName, bucket.list, "stored", CONF.CACHED, bucket.scanned)
        end
    end
    return total
end

-- Read another addon's cache. Read-only: we never write into it, and we do not
-- depend on it existing.
function RecipeBook:LoadForeign(guid)
    local cache, usedGUID, why = Api:MastercraftRecipes(guid)
    if type(cache) ~= "table" then
        self.foreignSkipped = why
        if why and ns.Diag then
            ns.Diag:Log("чужой кеш рецептов не использован", { reason = why, guid = guid })
        end
        return 0, nil, why
    end
    self.foreignSkipped = nil
    local total = 0
    for profName, bucket in pairs(cache) do
        if type(bucket) == "table" and type(bucket.list) == "table" then
            total = total + self:Store(profName, bucket.list, "foreign", CONF.CACHED, bucket.scanned)
        end
    end
    return total, usedGUID
end

-- Build the whole book. `professions` is what CharacterScanner found, so we can
-- report which of the player's professions we have nothing for.
function RecipeBook:Build(professions, guid)
    self:Reset()
    self:LoadStored()
    self:LoadForeign(guid)
    self:Reindex()

    self.missingProfessions = {}
    for _, prof in ipairs(professions or {}) do
        if not self:HasProfession(prof.name) then
            self.missingProfessions[#self.missingProfessions + 1] = prof
        end
    end
    return self
end

-- Profession names differ between sources: the skill window may say
-- "Портняжное дело" where the recipe cache says "Tailoring". Match on either
-- side, case-insensitively, with a substring fallback.
function RecipeBook:Bucket(professionName)
    if not professionName then return nil end
    local direct = self.byProfession[professionName]
    if direct then return direct end
    -- A name some other source used for this same profession. Recorded by
    -- Store when it merged the two spellings into one bucket.
    for _, bucket in pairs(self.byProfession) do
        if bucket.aliases and bucket.aliases[professionName] then return bucket end
    end
    local want = U.lower(professionName)
    for name, bucket in pairs(self.byProfession) do
        local have = U.lower(name)
        if have == want or have:find(want, 1, true) or want:find(have, 1, true) then
            return bucket
        end
    end
    -- Last resort: the skill window and the recipe cache can name the same
    -- profession in different languages ("Портняжное дело" / "Tailoring").
    local bridge = RecipeBook.NAME_BRIDGE[want]
    if bridge then
        for name, bucket in pairs(self.byProfession) do
            if U.lower(name) == bridge then return bucket end
        end
    end
    return nil
end

-- Localised profession name -> the English name a recipe cache is likely to
-- use.
--
-- ДОБЫЧНЫЕ ПРОФЕССИИ ЗДЕСЬ ТОЖЕ. Раньше в списке были только крафтовые (плюс
-- рыбалка, которая добычная), и это выглядело безобидно, пока словарём
-- пользовалась одна книга рецептов. Теперь через него идут имена из чужого
-- кеша - там они английские, - и профессия без пары попадала на экран как
-- «Mining» в русском клиенте. Лишних записей это не создаёт: имена добычных
-- профессий так же уникальны, как остальные.
RecipeBook.NAME_BRIDGE = {
    ["портняжное дело"] = "tailoring",
    ["кожевничество"] = "leatherworking",
    ["кузнечное дело"] = "blacksmithing",
    ["инженерное дело"] = "engineering",
    ["ювелирное дело"] = "jewelcrafting",
    ["начертание"] = "inscription",
    ["алхимия"] = "alchemy",
    ["наложение чар"] = "enchanting",
    ["кулинария"] = "cooking",
    ["первая помощь"] = "first aid",
    ["рыбная ловля"] = "fishing",
    ["горное дело"] = "mining",
    ["травничество"] = "herbalism",
    ["снятие шкур"] = "skinning",
    ["археология"] = "archaeology",
}
-- And the other direction, so either source can find the other.
do
    local reverse = {}
    for ru, en in pairs(RecipeBook.NAME_BRIDGE) do reverse[en] = ru end
    for en, ru in pairs(reverse) do RecipeBook.NAME_BRIDGE[en] = ru end
end

function RecipeBook:HasProfession(professionName)
    return self:Bucket(professionName) ~= nil
end

-- Queries ----------------------------------------------------------------

function RecipeBook:Get(recipeID)
    return self.byID[recipeID]
end

-- Learned recipes that produce this item. Used by the planner to decide whether
-- a missing material can be made instead of bought.
function RecipeBook:RecipesFor(itemID)
    return self.byOutput[itemID] or {}
end

function RecipeBook:CanCraft(itemID)
    return (self.byOutput[itemID] ~= nil)
end

function RecipeBook:LearnedEnchants(slotKey)
    return self.enchantsBySlot[slotKey] or {}
end

function RecipeBook:Iterate(filter)
    local out = {}
    for _, bucket in pairs(self.byProfession) do
        for _, rec in ipairs(bucket.list) do
            if (not filter) or filter(rec) then out[#out + 1] = rec end
        end
    end
    -- Stable order so the UI does not shuffle between recomputes.
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

function RecipeBook:LearnedCount()
    local n = 0
    for _, rec in pairs(self.byID) do
        if rec.learned then n = n + 1 end
    end
    return n
end

function RecipeBook:Summary()
    local out = {}
    for name, bucket in pairs(self.byProfession) do
        local learned = 0
        for _, rec in ipairs(bucket.list) do
            if rec.learned then learned = learned + 1 end
        end
        out[#out + 1] = {
            name = name, total = #bucket.list, learned = learned,
            source = bucket.source, conf = bucket.conf, scanned = bucket.scanned,
        }
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

-- Which slots this server actually has enchanting formulas for.
--
-- Hardcoding the list is wrong on a custom realm: this one has neck enchants
-- (which vanilla never had) and no head, leg or ranged ones. So the set is
-- derived from every enchant recipe the client showed us, learned or not -
-- the recipe existing is proof the slot is enchantable, and the player not
-- knowing it yet is a separate question.
--
-- MEMOISED, and that is not an optimisation detail: this is called from
-- SlotMap:IsEnchantable, which runs once per equipment slot per pass, and the
-- uncached version walked all ~900 recipes every time. The addon's own
-- diagnostics caught it as 35 ms a rebuild.
--
-- Returns a set, or nil when we have not seen any enchanting recipes at all,
-- in which case the caller falls back to the static list.
function RecipeBook:EnchantableSlots()
    if self.enchantableCache ~= nil then
        if self.enchantableCache == false then return nil end
        return self.enchantableCache
    end

    local set, any = {}, false
    for _, rec in pairs(self.byID) do
        if (not rec.output) and #(rec.reagents or {}) > 0 then
            local slot = ns.SlotMap:EnchantSlot(rec)
            if slot then
                any = true
                for _, target in ipairs(ns.SlotMap:TargetSlots(slot)) do
                    set[target] = true
                end
                set[slot] = true
            end
        end
    end
    self.enchantableCache = any and set or false
    return any and set or nil
end

-- Called whenever the recipe set changes, or the player re-assigns a category
-- to a different slot in Settings.
function RecipeBook:InvalidateEnchantCache()
    self.enchantableCache = nil
    self.bySlotCache = nil
    self.unlearnedBySlotCache = nil
end

-- Every category id we have seen on an enchant recipe, with our current guess
-- for its slot. The Settings tab renders this so the player can correct us.
function RecipeBook:EnchantCategories()
    local seen, out = {}, {}
    for _, rec in pairs(self.byID) do
        if (not rec.output) and rec.categoryID and not seen[rec.categoryID] then
            seen[rec.categoryID] = true
            local slot, conf = ns.SlotMap:EnchantSlot(rec)
            out[#out + 1] = {
                categoryID = rec.categoryID,
                categoryName = rec.categoryName or ("Категория #" .. tostring(rec.categoryID)),
                slot = slot, conf = conf,
                override = ns.Config:EnchantSlot(rec.categoryID),
            }
        end
    end
    table.sort(out, function(a, b) return (a.categoryName or "") < (b.categoryName or "") end)
    return out
end

-- ГДЕ ИСКАТЬ РЕЦЕПТ. СЛОВАМИ, А НЕ КНОПКОЙ ---------------------------------
--
-- ЧТО ЗДЕСЬ БЫЛО И ПОЧЕМУ ЭТОГО БОЛЬШЕ НЕТ.
--
-- Была кнопка «Показать рецепт»: она звала C_TradeSkillUI.OpenRecipe и
-- открывала рецепт в окне профессий игры. На этом клиенте такой вызов
-- защищён - игра его блокирует и показывает игроку окно «Модификация
-- "ForeverPilot" заблокирована при попытке выполнения действия, доступного
-- только интерфейсу Blizzard». Подробно - в Core/Api.lua, там же, где раньше
-- стоял сам вызов.
--
-- Здесь была защита «окно профессий уже загружено игрой», и она честно
-- работала - но защищала не от того. Блокируют не первое открытие окна, а сам
-- вызов из кода аддона, и всегда. А заметить отказ было нечем: заблокированный
-- вызов не бросает ошибку, поэтому «клиент ответил ошибкой» не наступало
-- никогда, кнопка не исчезала, и игроку не говорилось ничего.
--
-- ПРАВИЛЬНЫЙ ОТВЕТ ДЛЯ СОВЕТНИКА - НЕ ДЕЛАТЬ, А СКАЗАТЬ. Кнопки нет вовсе;
-- вместо неё у совета стоит одна строка: какую профессию открыть, что в ней
-- найти и в каком разделе. Это ровно то, чего игроку не хватало, и это не
-- зависит от того, что клиент разрешает аддонам.
--
-- Состояние осталось одно, и названо оно по причине, а не по условию:
--   none - кнопки нет и не будет; аддон окон игры не открывает.
-- Обещания «кнопка появится» в текстах нет: обещать кнопку, которой не будет
-- никогда, - тот же дефект, что текст про кнопку, которой нет.

RecipeBook.NOTE = "Окно профессий я не открываю: игра это аддонам запрещает."
    .. " Откройте профессию сами — название рецепта стоит в заголовке совета,"
    .. " а где его искать, написано в строке под ним."
RecipeBook.SHORT = "Кнопки показа рецепта нет: окон игры я не открываю —"
    .. " ищите рецепт по названию."

-- ОДНА СТРОКА ПРО КОНКРЕТНЫЙ РЕЦЕПТ: что открыть и что там найти.
--
-- nil - сказать нечего: рецепта с таким номером в справочнике нет, и выдумывать
-- профессию мы не станем. Тогда на экране остаётся общая строка (SHORT выше).
function RecipeBook:FindText(recipeID)
    local recipe = recipeID and self:Get(recipeID) or nil
    if not recipe then return nil end
    local parts = {}
    if recipe.profession then
        parts[#parts + 1] = "Откройте «" .. U.profLabel(recipe.profession) .. "»"
    else
        parts[#parts + 1] = "Откройте окно профессии"
    end
    parts[#parts + 1] = "и найдите «" .. tostring(recipe.name) .. "»"
    local text = table.concat(parts, " ")
    if recipe.categoryName and recipe.categoryName ~= "" then
        text = text .. " — раздел «" .. recipe.categoryName .. "»"
    end
    return text .. ". Окон игры я не открываю."
end

-- Общее состояние. Остаётся ради одного: экрану надо знать, рисовать кнопку
-- или нет, и какими словами объяснить её отсутствие.
--
-- С 2026-11-21 состояний два. Окно аддон по-прежнему не открывает, но в окне,
-- которое игрок открыл сам, может оставить в списке один рецепт - поиском по
-- имени (Api:SetRecipeNameFilter). Тогда у совета есть кнопка:
--   ready - клиент умеет искать по имени, рецепт известен по имени, и игра этот
--           вызов ни разу не блокировала;
--   none  - всё остальное: кнопки нет, на экране строка «что открыть и что
--           найти», как раньше.
RecipeBook.SHOW_LABEL = "Показать в профессии"
RecipeBook.UNSHOW_LABEL = "Вернуть весь список"
-- Сколько живёт «покажу, когда откроете»: дольше - это уже забытая кнопка, и
-- внезапно суженный список через час был бы загадкой.
RecipeBook.PENDING_SECONDS = 600
-- Сколько секунд после постановки поиск считается «ещё ставится». Окно
-- профессии при открытии само сбрасывает свои фильтры, и если это случается
-- после нашего вызова, поиск надо поставить снова - иначе кнопка нажата, а
-- список целый. Дольше этого срока другой текст в поиске - уже рука игрока.
RecipeBook.SETTLE_SECONDS = 1.5

RecipeBook.pending = nil        -- { recipeID, name, profession, at }
RecipeBook.applied = nil        -- { recipeID, name, profession }
RecipeBook.filterBroken = nil   -- игра заблокировала или вызов упал

local function filterAllowed()
    if RecipeBook.filterBroken then return false end
    local cfg = ns.Config and ns.Config.Get and ns.Config:Get() or nil
    if cfg and cfg.recipeFilterBlocked then return false end
    return Api.CanFilterRecipes and Api:CanFilterRecipes() or false
end

function RecipeBook:ShowState(recipeID)
    local recipe = recipeID and self:Get(recipeID) or nil
    if recipe and type(recipe.name) == "string" and recipe.name ~= "" and filterAllowed() then
        local shown = self.applied and self.applied.recipeID == recipeID
        return {
            state = "ready",
            label = shown and RecipeBook.UNSHOW_LABEL or RecipeBook.SHOW_LABEL,
            shown = shown or nil,
            armed = (self.pending and self.pending.recipeID == recipeID) or nil,
        }
    end
    return { state = "none", note = RecipeBook.NOTE, short = RecipeBook.SHORT }
end

-- Ответ на вопрос «можно ли нажать» спрашивают и список, и панель, и ответ у
-- них обязан быть один. Без номера рецепта ответ «нет»: кнопка бывает только у
-- конкретного рецепта.
function RecipeBook:CanShow(recipeID)
    return self:ShowState(recipeID).state == "ready"
end

-- Одна и та же профессия под двумя написаниями: в книге она названа так, как
-- её назвал источник, а окно отдаёт имя на языке клиента.
local function sameProfession(a, b)
    if not (a and b) then return false end
    if a == b then return true end
    return U.profLabel(a) == U.profLabel(b)
end

-- Открыто ли сейчас окно этой профессии. Второй ответ - имя открытого окна.
function RecipeBook:WindowOpenFor(profession)
    local open = Api:OpenProfessionName()
    if type(open) ~= "string" or open == "" then return false, nil end
    if not profession then return true, open end
    return sameProfession(open, profession), open
end

local function profText(profession)
    if profession then return "«" .. tostring(U.profLabel(profession)) .. "»" end
    return "окно профессии"
end

function RecipeBook:ApplyFilter(want)
    local ok, why, detail = Api:SetRecipeNameFilter(want.name)
    if not ok then
        if why == "error" then
            RecipeBook.filterBroken = { error = detail }
            if ns.Diag then
                ns.Diag:Log("поиск в окне профессии не поставился", { error = detail })
            end
            return false, "игра не приняла поиск по имени — найдите «" .. want.name
                .. "» в окне профессии сами. Подробности записал в /fp diag."
        end
        if why == "combat" then return false, "в бою окно профессии не трогаю" end
        return false, self:FindText(want.recipeID) or RecipeBook.SHORT
    end
    want.settleUntil = Api:Now() + RecipeBook.SETTLE_SECONDS
    self.applied, self.pending = want, nil
    return true, "оставил в списке профессии только «" .. want.name
        .. "». Вернуть весь список — та же кнопка ещё раз."
end

-- Вернуть весь список. Зовётся вторым нажатием и при закрытии окна.
function RecipeBook:ClearShown(silent)
    local had = self.applied
    self.applied = nil
    if not had then return false, nil end
    if self:WindowOpenFor(nil) then
        -- Снимаем только СВОЙ поиск: если игрок уже набрал своё, не трогаем.
        local now = Api:RecipeNameFilter()
        if now == nil or now == had.name then Api:SetRecipeNameFilter("") end
    end
    if silent then return true, nil end
    return true, "вернул весь список рецептов"
end

-- НАЖАТИЕ КНОПКИ. Возвращает ok и одну строку для игрока.
function RecipeBook:Show(recipeID)
    local recipe = recipeID and self:Get(recipeID) or nil
    if not recipe then return false, RecipeBook.SHORT end
    if not self:CanShow(recipeID) then
        return false, self:FindText(recipeID) or RecipeBook.SHORT
    end
    if self.applied and self.applied.recipeID == recipeID then
        return self:ClearShown()
    end
    local want = {
        recipeID = recipeID, name = recipe.name,
        profession = recipe.profession, at = Api:Now(),
    }
    local openHere, openName = self:WindowOpenFor(recipe.profession)
    if openHere then return self:ApplyFilter(want) end
    -- Окно закрыто или открыта другая профессия: запоминаем и ждём.
    self.pending = want
    if openName then
        return true, "сейчас открыта другая профессия. Откройте "
            .. profText(recipe.profession) .. " — «" .. recipe.name
            .. "» в списке найду сам."
    end
    return true, "откройте " .. profText(recipe.profession) .. " — «" .. recipe.name
        .. "» в списке найду сам. Окон игры я не открываю."
end

-- ОКНО ПРОФЕССИИ ОТКРЫЛИ, ОБНОВИЛИ ИЛИ ЗАКРЫЛИ. Событий «обновили» много (по
-- одному на каждую сделанную вещь), поэтому первым делом - дешёвый выход.
-- Возвращает строку для игрока (или nil) и признак «на экране что-то
-- изменилось».
function RecipeBook:OnTradeSkill(phase)
    if not (self.pending or self.applied) then return nil, false end
    if phase == "close" then
        local changed = self.applied ~= nil
        self:ClearShown(true)
        return nil, changed
    end
    local pending = self.pending
    if pending then
        if (Api:Now() - (pending.at or 0)) > RecipeBook.PENDING_SECONDS then
            self.pending = nil
            return nil, true
        end
        if self:WindowOpenFor(pending.profession) then
            local _, message = self:ApplyFilter(pending)
            return message, true
        end
        return nil, false
    end
    local applied = self.applied
    if applied then
        local now = Api:RecipeNameFilter()
        if now ~= nil and now ~= applied.name then
            -- Окно только что открылось и сбросило фильтры уже после нашего
            -- вызова: ставим поиск ещё раз, молча.
            if Api:Now() < (applied.settleUntil or 0) then
                Api:SetRecipeNameFilter(applied.name)
                return nil, false
            end
            -- Иначе это игрок сам поменял поиск - кнопка возвращается к
            -- «Показать», а его текст остаётся как есть.
            self.applied = nil
            return nil, true
        end
    end
    return nil, false
end

return RecipeBook
