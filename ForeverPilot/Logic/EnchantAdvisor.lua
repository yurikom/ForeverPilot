-- ForeverPilot / Logic/EnchantAdvisor.lua
--
-- "Which of my slots is missing an enchant, and do I know a formula for it?"
--
-- An enchanting recipe is recognised by having no output item at all: the
-- schematic produces nothing, because the product is an effect on a slot. The
-- slot itself comes from the recipe's categoryID - the client groups "Чары для
-- наручей" under its own category, so one lookup per category is all it takes
-- and no external database is needed. The guess per category is stored by id,
-- and the player can correct it once in Settings and never again.
--
-- Only formulas the player has actually learned are offered. Reagent cost comes
-- from the planner, so an enchant whose dust is already in the bags ranks above
-- one that needs a shopping trip.
local ADDON, ns = ...

local U = ns.Util
local Api = ns.Api
local CONF = ns.CONF

local Enchant = {}
ns.EnchantAdvisor = Enchant

-- A crafting recipe either produces an item or it is an enchant: there is no
-- third kind. So "no output item, but it does consume reagents" identifies an
-- enchant without reading a single word of localised text.
--
-- The reagent check is what separates a real enchant from a recipe whose
-- schematic the client has not sent yet: both have no output, but an unloaded
-- schematic has no reagents either, because reagents come from the same call.
function Enchant:IsEnchantRecipe(recipe)
    if type(recipe) ~= "table" then return false end
    if recipe.output then return false end
    if #(recipe.reagents or {}) == 0 then return false end
    return true
end

function Enchant:LearnedFormulas()
    return ns.RecipeBook:Iterate(function(r)
        return r.learned and Enchant:IsEnchantRecipe(r)
    end)
end

-- Group learned formulas by the slot they apply to.
--   { slotKey -> { recipe, ... } }, { unresolved recipe, ... }
--
-- Memoised alongside RecipeBook's slot set, because this is called several
-- times per rebuild (suggestions, bare slots, diagnostics) and each call used
-- to re-walk and re-sort the whole recipe list.
function Enchant:BySlot()
    local book = ns.RecipeBook
    local cached = book.bySlotCache
    if cached then return cached.bySlot, cached.unresolved end

    local out, unresolved = {}, {}
    for _, recipe in ipairs(self:LearnedFormulas()) do
        local slot, conf = ns.SlotMap:EnchantSlot(recipe)
        if slot then
            recipe.enchantSlot, recipe.enchantSlotConf = slot, conf
            out[slot] = out[slot] or {}
            table.insert(out[slot], recipe)
        else
            unresolved[#unresolved + 1] = recipe
            -- Заказ на данные: формула есть, а на какой она слот - неизвестно,
            -- и без слота совет по ней построить нельзя. Нужен recipeID и
            -- категория, по которой мы пытались угадать.
            if ns.Diag then
                ns.Diag:Want("enchantsUnknownSlot", recipe.id, "enchant-book", {
                    name = recipe.name,
                    category = recipe.category,
                    categoryID = recipe.categoryID,
                })
            end
        end
    end
    book.bySlotCache = { bySlot = out, unresolved = unresolved }
    return out, unresolved
end

-- Advice ----------------------------------------------------------------

-- Slots that are wearing something, can take an enchant, and have none.
--
-- Each entry also carries `enchantKeys`: the enchant categories the item in
-- that slot can actually take. A staff sits in MAINHAND but takes TWOHAND
-- formulas, and matching slot name to category name meant those never showed.
-- ЧТО СЧИТАТЬ ПРЕДМЕТОМ СЛОТА - спрашиваем у GearAdvisor, а не у надетого.
--
-- Своя логика здесь стоила вот этого на экране игрока: «Слот «Правая рука» без
-- чар (Большая железная удочка)» - предложение зачаровать удочку, пока
-- настоящее оружие лежало в сумке уже зачарованным. Инструмент не считается
-- предметом слота, а вещь из сумки - считается, вместе со своими чарами.
function Enchant:SlotItems(snap)
    local out = {}
    if not snap then return out end
    local Gear = ns.GearAdvisor
    if not (Gear and Gear.SlotItem) then
        -- Деградация без GearAdvisor: старое поведение по надетому, но тогда
        -- хотя бы не врём - помечаем источник.
        for slotKey, equipped in pairs(snap.equipped or {}) do
            out[slotKey] = {
                itemID = equipped.itemID, link = equipped.link,
                enchantID = equipped.enchantID, where = "equipped",
                enchantText = equipped.enchantText,
                info = equipped.itemID and Api:ItemInfo(equipped.itemID) or nil,
            }
        end
        return out
    end
    for _, slotKey in ipairs(Gear:SlotsToCheck()) do
        local item = Gear:SlotItem(slotKey, snap, snap.weights)
        if item and item.itemID then
            -- ЗАЧАРОВЫВАЕМ ПРЕДМЕТ, А НЕ МЕСТО НА ТЕЛЕ. Вопрос «можно ли на это
            -- наложить чары» решается по предмету: посох лежит в правой руке, а
            -- формулы на него - в категории «двуручное оружие», и слот
            -- «правая рука» сам по себе в выведенном списке не числится.
            local keys = ns.SlotMap:EnchantKeysForItem(slotKey, item.info)
            local can = false
            for _, key in ipairs(keys) do
                if ns.SlotMap:IsEnchantable(key) then can = true; break end
            end
            if can then
                item.enchantKeys = keys
                out[slotKey] = item
            end
        end
    end
    return out
end

function Enchant:BareSlots(snap)
    local out = {}
    for slotKey, item in pairs(self:SlotItems(snap)) do
        if not item.enchantID then
            local info = item.info or (item.itemID and Api:ItemInfo(item.itemID)) or nil
            out[#out + 1] = {
                slot = slotKey,
                -- `equipped` историческое имя поля: теперь это ПРЕДМЕТ СЛОТА,
                -- и он может лежать в сумке. Где именно - в `where`/`inBag`.
                equipped = item,
                item = item,
                where = item.where,
                inBag = item.inBag,
                info = info,
                enchantKeys = item.enchantKeys
                    or ns.SlotMap:EnchantKeysForItem(slotKey, info),
            }
        end
    end
    table.sort(out, function(a, b) return a.slot < b.slot end)
    return out
end

-- Every learned formula that fits the item in this bare slot, deduplicated.
function Enchant:FormulasFor(bare, bySlot)
    local out, seen = {}, {}
    for _, key in ipairs((bare and bare.enchantKeys) or {}) do
        for _, recipe in ipairs(bySlot[key] or {}) do
            if not seen[recipe.id] then
                seen[recipe.id] = true
                out[#out + 1] = recipe
            end
        end
    end
    return out
end

-- Сила чары - это порог навыка формулы, а не слово в её названии -------
--
-- СКОЛЬКО ИМЕННО ДАЁТ ЧАРА, НЕ ЗНАЕТ НИКТО ИЗ ТЕХ, КОГО МОЖНО СПРОСИТЬ.
-- У формулы нет предмета, значит нет и характеристик (GetItemStats звать не на
-- что); во внешней базе предметов чар нет вовсе; а от наложенной чары на вещи
-- игрока остаётся ОДИН НОМЕР в ссылке (item:ID:ENCHANT:...), и таблицы этих
-- номеров нет ни в одном установленном аддоне - проверено поиском по всем
-- папкам Interface/AddOns по номерам с вещей этого персонажа (884, 843, 911,
-- 846, 8217, 8734): ни одного совпадения, и это не спелл-id рецептов.
-- Поэтому «что стоит на слоте сейчас» здесь НЕ УТВЕРЖДАЕТСЯ, а называется
-- номером, и причина названа словами на карточке.
--
-- ЧТО ПРИ ЭТОМ ИЗВЕСТНО ТОЧНО: порог навыка формулы. Он лежит в справочнике
-- рецептов Forever (Data/ForeverSource.lua, FS.RECIPE_REF) и на этом персонаже
-- известен для ВСЕХ 65 его формул, без единого пропуска. Внутри одной
-- характеристики он монотонен по силе - это видно по английским именам того же
-- справочника:
--   Enchant Chest - Inferior Stamina    15
--   Enchant Chest - Lesser Stamina      60
--   Enchant Chest - Stamina            120
--   Enchant Chest - Greater Stamina    160
--   Enchant Chest - Superior Stamina   220
-- Так что навык работает здесь как ПОРЯДОК («эта сильнее той»), и никогда как
-- величина: «на сколько больше» отсюда не утверждается и на экран не попадает.
function Enchant:SkillNeeded(recipe)
    local FS = ns.ForeverSource
    if not (FS and FS.RECIPE_REF) then return nil end
    if type(recipe) ~= "table" or not recipe.id then return nil end
    local ref = FS.RECIPE_REF[recipe.id]
    return ref and tonumber(ref.s) or nil
end

-- Навык игрока по профессии этой формулы, когда его удаётся сопоставить.
-- Не удалось - возвращается nil, и число на карточку просто не попадает.
--
-- ДВА ИМЕНИ ОДНОЙ ПРОФЕССИИ, И СРАВНИВАТЬ ИХ НАПРЯМУЮ НЕЛЬЗЯ. Книга рецептов
-- на этом клиенте хранит русское «Наложение чар» (так его называет окно
-- профессии), а список профессий в снимке приходит английским - «Enchanting».
-- Прямое сравнение давало nil всегда, и на карточке вместо «порог навыка 185, у
-- вас 225» стояло только «порог навыка 185». Мостик между именами в проекте
-- уже есть и один - RecipeBook.NAME_BRIDGE.
function Enchant:SkillHave(snap, recipe)
    if not (snap and type(recipe) == "table") then return nil end
    local book = ns.RecipeBook
    local own = recipe.profession or recipe.groupName
    local key = book and book.ResolveKey and book:ResolveKey(own) or nil
    local want = U.lower(key or own or "")
    if not want or want == "" then return nil end
    local bridged = book and book.NAME_BRIDGE and book.NAME_BRIDGE[want] or nil
    for _, prof in ipairs(snap.professions or {}) do
        local have = U.lower(prof.name or "")
        if (have == want or (bridged and have == bridged))
            and prof.skillTrusted ~= false then
            return tonumber(prof.skill), prof.name
        end
    end
    return nil
end

-- Что формула даёт ИМЕННО ЭТОМУ персонажу: вес характеристики по его профилю,
-- её название словами клиента и порог навыка формулы.
function Enchant:Rate(recipe, weights)
    local useful, conf, stats = ns.StatWeights:TextUsefulness(recipe.name, weights)
    local keys = {}
    for stat in pairs(stats or {}) do keys[#keys + 1] = stat end
    -- Сначала та характеристика, которую персонаж ценит выше: она и есть
    -- причина брать эту формулу.
    table.sort(keys, function(a, b)
        local wa = (weights and weights[a]) or 0
        local wb = (weights and weights[b]) or 0
        if wa ~= wb then return wa > wb end
        return a < b
    end)
    local labels = {}
    for _, stat in ipairs(keys) do
        labels[#labels + 1] = (ns.GearAdvisor and ns.GearAdvisor.StatLabel)
            and ns.GearAdvisor:StatLabel(stat) or tostring(stat)
    end
    return {
        weight = useful, conf = conf, stats = stats, statKeys = keys,
        statText = (#labels > 0) and table.concat(labels, " и ") or nil,
        skill = self:SkillNeeded(recipe),
    }
end

-- Класс формулы для этого персонажа, в порядке убывания:
--   2 - даёт характеристику, которую он ценит (вес больше нуля);
--   1 - что даёт, из названия прочитать не удалось;
--   0 - даёт ровно то, что ему не нужно (вес ноль).
local function rateClass(weight)
    if weight == nil then return 1 end
    if weight > 0 then return 2 end
    return 0
end

-- Разложить формулы одного слота по тому, что они дают ЭТОМУ персонажу.
--
-- ЦЕНА БЫЛА ГЛАВНЫМ КРИТЕРИЕМ, И ИМЕННО ЭТО ЛОМАЛО СОВЕТ. Полезность
-- сворачивалась в четыре грубые ступени («больше 0.3» - одна ступень на всё),
-- а внутри ступени выигрывала САМАЯ ДЕШЁВАЯ формула. На настоящем
-- маге-зачарователе (вес интеллекта 1.00, выносливости 0.55) это давало на
-- грудь «Чары для нагрудника: низшая выносливость» за 90м вместо «сильный
-- интеллект» за 8с 98м, а на наручи - «Чары для наручей: низшая выносливость»
-- за 4м вместо «Чары для браслетов: интеллект III». То есть из тринадцати
-- известных формул советовалась самая слабая, потому что она же самая дешёвая.
--
-- Теперь порядок такой же, как в ветке экипировки: сперва вес характеристики,
-- потом сила формулы (порог навыка), и только в самом конце - готовность
-- реагентов и цена. Формулы, про которые из названия ничего не прочиталось,
-- стоят ниже понятных и выше бесполезных: не знать - не то же самое, что знать,
-- что плохо.
--
-- И ПЛАН СТРОИТСЯ НЕ ДЛЯ ВСЕХ, А ТОЛЬКО ДЛЯ ТЕХ, КТО ЕЩЁ МОЖЕТ ВЫИГРАТЬ.
-- Полный план по каждой формуле стоил 60 вызовов планировщика за пересчёт на
-- настоящем персонаже - при 95 на весь остальной аддон. Ровно эту цену ветка
-- крафта уже один раз платила и перестала (см. два прохода в
-- Engine:AddProfitCards). Вес и порог навыка считаются БЕЗ плана, а план нужен
-- только там, где цена и готовность реагентов ещё что-то решают:
--   * у лидера есть ценная характеристика - планируются только те, кто с ним
--     ровня по весу и по порогу навыка;
--   * у лидера характеристика не прочиталась или ничего не стоит - решает цена,
--     и планируется весь его класс (но не классы ниже: они всё равно проиграют).
function Enchant:RankFormulas(formulas, weights, planner)
    planner = planner or ns.CraftingPlanner
    local scored = {}
    for _, recipe in ipairs(formulas or {}) do
        local rate = self:Rate(recipe, weights)
        scored[#scored + 1] = {
            recipe = recipe,
            usefulness = rate.weight,
            usefulConf = rate.conf,
            stats = rate.stats,
            statText = rate.statText,
            skill = rate.skill,
            cls = rateClass(rate.weight),
            ready = false,
        }
    end
    -- Предварительный порядок - без единого плана.
    table.sort(scored, function(a, b)
        if a.cls ~= b.cls then return a.cls > b.cls end
        local wa, wb = a.usefulness or 0, b.usefulness or 0
        if wa ~= wb then return wa > wb end
        local sa, sb = a.skill or -1, b.skill or -1
        if sa ~= sb then return sa > sb end
        return (a.recipe.id or 0) < (b.recipe.id or 0)
    end)
    local lead = scored[1]
    if lead then
        for _, e in ipairs(scored) do
            local sameClass = (e.cls == lead.cls)
            local tiedOnTop = sameClass and (lead.cls ~= 2
                or ((e.usefulness or 0) == (lead.usefulness or 0)
                    and (e.skill or -1) == (lead.skill or -1)))
            if tiedOnTop then
                local plan = planner:Plan(e.recipe, 1)
                e.plan = plan
                e.cost = plan and plan.cost or nil
                e.costPartial = plan and plan.costPartial or nil
                e.ready = plan and plan.ready or false
                e.readiness = plan and plan.readiness or 0
                e.planned = true
            end
        end
    end
    table.sort(scored, function(a, b)
        if a.cls ~= b.cls then return a.cls > b.cls end
        if a.cls == 2 then
            local wa, wb = a.usefulness or 0, b.usefulness or 0
            if wa ~= wb then return wa > wb end
            -- Та же характеристика, но формула сильнее: порог навыка выше.
            local sa, sb = a.skill or -1, b.skill or -1
            if sa ~= sb then return sa > sb end
        end
        if a.ready ~= b.ready then return a.ready end
        local ca, cb = a.cost or math.huge, b.cost or math.huge
        if ca ~= cb then return ca < cb end
        return (a.recipe.id or 0) < (b.recipe.id or 0)
    end)
    return scored
end

-- Советы по чарам на все слоты сразу: и на пустые, и на занятые -------
--
-- ЗДЕСЬ ТЕРЯЛИСЬ ШЕСТЬДЕСЯТ ФОРМУЛ ИЗ ШЕСТИДЕСЯТИ ПЯТИ, И МОЛЧА.
--
-- Ветка смотрела только на слоты БЕЗ чар (Enchant:BareSlots). У настоящего
-- мага-зачарователя зачарованы шесть слотов из семи, незачарована одна шея, и
-- формул на шею он не знает. Поэтому советов выходило ноль, примечание ветки
-- писало «выученных формул 65, но ни одна сюда не подходит» - а это неправда:
-- к надетым вещам подходили 60 из 65, просто все их слоты уже были чем-то
-- заняты. Воронки у ветки не было вовсе, так что пропажу шестидесяти формул не
-- показывало ни одно число.
--
-- Отдаёт два списка:
--   bare    - слот без чар: обычный совет, «наложить вот это»;
--   replace - слот, на котором чары уже стоят. Что они дают, нам неизвестно
--             (см. Enchant:SkillNeeded), поэтому «лучше» здесь не утверждается
--             и достоверность у такого совета - UNKNOWN. Он выдаётся только
--             тогда, когда у игрока есть формула на характеристику, которую он
--             действительно ценит: без размена и без «вдруг пригодится».
function Enchant:Advise(snap, planner)
    planner = planner or ns.CraftingPlanner
    local res = { bare = {}, replace = {}, slots = {} }
    local funnel = ns.Diag and ns.Diag:Funnel("enchants") or nil

    -- БЕЗ ВЕСОВ СОВЕТА НЕТ. Здесь стояло `or SW:Set("CASTER_DPS")`, и персонаж
    -- незнакомого класса получал формулы, отобранные по кастерским весам -
    -- ровно то, от чего избавлена оценка вещей (см. weightsOf в
    -- Logic/GearAdvisor.lua). Пустой список - честный ответ, а ветка говорит
    -- почему (StatWeights:NoProfileReason).
    local weights = snap and snap.weights or nil
    if not weights then
        res.noWeights = true
        if funnel then funnel:Finish(0) end
        return res
    end

    local bySlot = self:BySlot()
    local items = self:SlotItems(snap)
    local slotKeys = {}
    for slotKey in pairs(items) do slotKeys[#slotKeys + 1] = slotKey end
    table.sort(slotKeys)

    for _, slotKey in ipairs(slotKeys) do
        local item = items[slotKey]
        local info = item.info or (item.itemID and Api:ItemInfo(item.itemID)) or nil
        local keys = item.enchantKeys
            or ns.SlotMap:EnchantKeysForItem(slotKey, info)
        local formulas = self:FormulasFor({ slot = slotKey, enchantKeys = keys }, bySlot)
        local occupied = item.enchantID and true or false
        local slotNote = {
            slot = slotKey, label = ns.SlotMap:Label(slotKey),
            occupied = occupied, enchantID = item.enchantID,
            formulas = #formulas, where = item.where, inBag = item.inBag,
            itemName = (info and info.name) or U.itemFallbackName(item.itemID),
        }
        res.slots[#res.slots + 1] = slotNote

        if #formulas == 0 then
            -- Ни одной формулы на этот слот: это говорит отдельная карточка
            -- (Enchant:BareWithoutFormula), кандидатов здесь не было.
            slotNote.dropped = "no-formula-known"
        else
            local scored = self:RankFormulas(formulas, weights, planner)
            for i, e in ipairs(scored) do
                if funnel then funnel:In(e.recipe) end
                if i > 1 and funnel then
                    funnel:Drop("beaten-in-same-slot", e.recipe,
                        "на слот «" .. tostring(slotNote.label)
                        .. "» нашлась формула лучше")
                end
            end
            local best = scored[1]
            local entry = {
                slot = slotKey,
                label = ns.SlotMap:Label(slotKey),
                recipe = best.recipe,
                equipped = item,
                item = item,
                itemID = item.itemID,
                where = item.where,
                inBag = item.inBag,
                info = info,
                equippedName = (info and info.name)
                    or U.itemFallbackName(item.itemID),
                currentEnchantID = item.enchantID,
                occupied = occupied,
                plan = best.plan,
                cost = best.cost,
                costPartial = best.costPartial,
                ready = best.ready,
                readiness = best.readiness,
                slotConf = best.recipe.enchantSlotConf or CONF.ESTIMATE,
                usefulness = best.usefulness,
                stats = best.stats,
                statText = best.statText,
                skillNeeded = best.skill,
                skillHave = self:SkillHave(snap, best.recipe),
                alternatives = #scored - 1,
                altList = scored,
            }
            entry.conf = U.worstConf(
                best.recipe.enchantSlotConf or CONF.ESTIMATE,
                best.plan and best.plan.conf or CONF.UNKNOWN,
                snap and snap.equippedConf or CONF.UNKNOWN
            )
            if not occupied then
                res.bare[#res.bare + 1] = entry
                slotNote.advised = "bare"
            elseif (best.usefulness or 0) > 0 then
                -- ЧТО СТОИТ СЕЙЧАС - НЕИЗВЕСТНО, И ПОЭТОМУ СРАВНЕНИЯ НЕТ.
                -- Достоверность падает до UNKNOWN: совет остаётся советом, но
                -- «лучше на столько-то» он не обещает.
                entry.conf = CONF.UNKNOWN
                entry.currentUnknown = true
                res.replace[#res.replace + 1] = entry
                slotNote.advised = "replace"
            else
                -- Занятый слот и ни одной формулы, которую этот персонаж
                -- ценит: перекрывать неизвестное неизвестным мы не предлагаем.
                slotNote.dropped = "occupied-nothing-better-known"
                if funnel then
                    funnel:Drop("occupied-nothing-better-known", best.recipe,
                        "на «" .. tostring(slotNote.label) .. "» чары уже стоят,"
                        .. " а из " .. #scored .. " ваших формул на этот слот"
                        .. " ни одна не даёт того, что вы цените")
                end
            end
        end
    end

    local function order(a, b)
        -- Надетое раньше того, что лежит в сумке: зачаровать вещь на себе
        -- полезнее, чем ту, которую ещё надо достать и надеть.
        local ba, bb = a.inBag and 1 or 0, b.inBag and 1 or 0
        if ba ~= bb then return ba < bb end
        -- Чем ценнее то, что формула даёт, тем раньше совет.
        local wa, wb = a.usefulness or -1, b.usefulness or -1
        if wa ~= wb then return wa > wb end
        if a.ready ~= b.ready then return a.ready end
        local ca, cb = a.cost or math.huge, b.cost or math.huge
        if ca ~= cb then return ca < cb end
        return a.slot < b.slot
    end
    table.sort(res.bare, order)
    table.sort(res.replace, order)
    if funnel then funnel:Finish(#res.bare + #res.replace) end
    return res
end

-- One suggestion per bare slot, with the reagents the player is missing worked
-- out. Slots that already carry an enchant are Enchant:Replacements.
--   { slot, label, recipe, equipped, plan, cost, ready, conf, alternatives }
function Enchant:Suggestions(snap, planner)
    return self:Advise(snap, planner).bare
end

-- Слоты, на которых чары уже стоят, и лучшая известная игроку формула на них.
function Enchant:Replacements(snap, planner)
    return self:Advise(snap, planner).replace
end

-- ЧТО УЖЕ СТОИТ НА ВЕЩАХ. Вторая половина вопроса игрока - «какие чанты у меня
-- есть», - и до этого на неё не отвечало ни одно место в аддоне: карточка
-- писала «6 из 7», а какие именно шесть и что на них - нигде.
--   { { slot, label, itemName, enchantID, where }, ... }, по слоту
function Enchant:Worn(snap)
    local out = {}
    for slotKey, item in pairs(self:SlotItems(snap)) do
        if item.enchantID then
            local info = item.info or (item.itemID and Api:ItemInfo(item.itemID)) or nil
            out[#out + 1] = {
                slot = slotKey, label = ns.SlotMap:Label(slotKey),
                itemName = (info and info.name) or U.itemFallbackName(item.itemID),
                itemID = item.itemID,
                enchantID = item.enchantID,
                enchantText = item.enchantText,
                where = item.where, inBag = item.inBag,
            }
        end
    end
    table.sort(out, function(a, b) return a.label < b.label end)
    return out
end

-- Diagnostics -----------------------------------------------------------

-- Enchants we know but cannot place, because the category name did not match
-- any slot. Surfaced in Settings so the player can map them by hand instead of
-- wondering why their bracer enchant never shows up.
function Enchant:Unmapped()
    local unresolved = select(2, self:BySlot())
    local byCategory, out = {}, {}
    for _, recipe in ipairs(unresolved) do
        local key = recipe.categoryID or recipe.categoryName or "?"
        if not byCategory[key] then
            byCategory[key] = true
            out[#out + 1] = {
                categoryID = recipe.categoryID,
                categoryName = recipe.categoryName
                    or ("Категория #" .. tostring(recipe.categoryID)),
                example = recipe.name,
            }
        end
    end
    table.sort(out, function(a, b) return (a.categoryName or "") < (b.categoryName or "") end)
    return out
end

-- Slots that are bare but for which we know no formula at all. Honest "nothing
-- to suggest here" rather than silence.
--
-- Each entry also carries what we DO know about that slot: how many formulas
-- for it exist in the recipe book unlearned. On the real character the bare
-- slot was the neck, this realm has five neck formulas at skill 210, and the
-- player (Enchanting 225) knows none of them. "Нечего предложить" was true
-- about the player's spellbook and useless as advice; "пять формул на шею
-- существуют, ни одна не выучена" is something they can act on.
function Enchant:BareWithoutFormula(snap)
    local bySlot = self:BySlot()
    local unlearned = self:UnlearnedBySlot()
    local out = {}
    for _, bare in ipairs(self:BareSlots(snap)) do
        if #self:FormulasFor(bare, bySlot) == 0 then
            local exist, example = 0, nil
            for _, key in ipairs(bare.enchantKeys or {}) do
                for _, recipe in ipairs(unlearned[key] or {}) do
                    exist = exist + 1
                    example = example or recipe.name
                end
            end
            out[#out + 1] = {
                slot = bare.slot, label = ns.SlotMap:Label(bare.slot),
                unlearnedCount = exist, unlearnedExample = example,
            }
        end
    end
    return out
end

-- Formulas the recipe book has seen but the player has NOT learned, by slot.
-- Evidence that a slot is enchantable on this realm even when the player's own
-- book has nothing to offer for it yet.
-- Cached on the recipe book's own cache, which RecipeBook:Reindex clears. This
-- walks every recipe the player does NOT know - six hundred of them on this
-- character - and the answer changes only when the book does.
function Enchant:UnlearnedBySlot()
    local book = ns.RecipeBook
    if book.unlearnedBySlotCache then return book.unlearnedBySlotCache end
    local out = {}
    for _, recipe in ipairs(book:Iterate(function(r)
        return (not r.learned) and (not r.output) and #(r.reagents or {}) > 0
    end)) do
        local slot = ns.SlotMap:EnchantSlot(recipe)
        if slot then
            out[slot] = out[slot] or {}
            out[slot][#out[slot] + 1] = recipe
        end
    end
    book.unlearnedBySlotCache = out
    return out
end

-- The whole enchant picture in four numbers, for the card and the diagnostics.
--
-- This exists because the file said "enchantSlots in=130 out=8" next to a card
-- reading "формул нет, нечего предложить", and neither line contained the fact
-- that mattered: seven of the eight enchantable slots were already enchanted.
-- A branch with nothing to advise because the work is DONE has to read
-- differently from a branch with nothing to advise because it is broken.
function Enchant:SlotStatus(snap)
    local status = {
        enchantable = 0, enchanted = 0, bare = 0,
        bareWithFormula = 0, bareWithoutFormula = 0,
        bareLabels = {},
    }
    if not snap then return status end

    local bySlot = self:BySlot()
    -- По ПРЕДМЕТАМ СЛОТОВ, а не по надетому: зачарованный посох в сумке делает
    -- оружейный слот зачарованным, и «5 из 7» превращается в честные «6 из 7».
    for _, item in pairs(self:SlotItems(snap)) do
        status.enchantable = status.enchantable + 1
        if item.enchantID then
            status.enchanted = status.enchanted + 1
        elseif item.enchantUnknown then
            -- Вещь в банке: ссылки нет, про чары неизвестно. Не считаем ни
            -- зачарованной, ни голой - считаем отдельно и говорим об этом.
            status.unknown = (status.unknown or 0) + 1
        else
            status.bare = status.bare + 1
        end
    end
    for _, bare in ipairs(self:BareSlots(snap)) do
        local n = #self:FormulasFor(bare, bySlot)
        if n > 0 then
            status.bareWithFormula = status.bareWithFormula + 1
        else
            status.bareWithoutFormula = status.bareWithoutFormula + 1
        end
        status.bareLabels[#status.bareLabels + 1] = ns.SlotMap:Label(bare.slot)
    end
    table.sort(status.bareLabels)
    return status
end

-- Enchants the player knows that are worth selling as a service or applied to
-- crafted goods for resale. Reagent cost only; there is no reliable price for
-- an applied enchant, so this is listed, not scored as profit.
function Enchant:CheapestKnown(planner, limit)
    planner = planner or ns.CraftingPlanner
    local out = {}
    for _, recipe in ipairs(self:LearnedFormulas()) do
        local plan = planner:Plan(recipe, 1)
        out[#out + 1] = {
            recipe = recipe, plan = plan,
            cost = plan and plan.cost or nil,
            ready = plan and plan.ready or false,
            slot = recipe.enchantSlot,
        }
    end
    table.sort(out, function(a, b)
        local ca, cb = a.cost or math.huge, b.cost or math.huge
        if ca ~= cb then return ca < cb end
        return a.recipe.id < b.recipe.id
    end)
    if limit then
        local trimmed = {}
        for i = 1, math.min(limit, #out) do trimmed[i] = out[i] end
        return trimmed
    end
    return out
end

return Enchant
