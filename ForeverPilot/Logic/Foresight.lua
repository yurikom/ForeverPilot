-- ForeverPilot / Logic/Foresight.lua
--
-- ЧТО ПОНАДОБИТСЯ ДАЛЬШЕ, А НЕ ЧТО УЖЕ НЕ СРАБОТАЛО.
--
-- Diag.wanted отвечает на вопрос «чего не хватило»: он заполняется, когда
-- что-то уже сломалось. Этого мало по одной конкретной причине - ИСТОРИЮ ЦЕН
-- ЗАДНИМ ЧИСЛОМ НЕ СОБРАТЬ. Сервер открылся 4 ноября, у нас два-три дня
-- наблюдений, и если начать записывать цену на рунную ткань в тот день, когда
-- потолок портняжки наконец поднимется, то сравнивать эту цену будет не с чем
-- ещё неделю. А стоит запись почти ничего.
--
-- Поэтому здесь считается ГОРИЗОНТ: куда персонаж движется, и что для этого
-- понадобится. Результат уходит двумя путями:
--   * в FOREVERPILOT_DIAG.wantedAhead - структурой, чтобы данные можно было
--     добыть заранее;
--   * в список предметов для суточных слепков цен - чтобы история на будущие
--     материалы начала копиться СЕГОДНЯ.
--
-- ЧЕСТНОСТЬ. Всё, что здесь собрано, - это предсказание, и оно помечено как
-- предсказание: каждая группа несёт `source` (откуда взято) и `conf`. Советов
-- из этого не делается: пока рецепт не выучен и уровня не хватает, карточки по
-- нему не появляется - появится, когда станет применимым.
--
-- СТОИМОСТЬ. Сбор идёт РЕДКО: один раз за сессию, плюс при смене уровня и при
-- подъёме потолка навыка. В пересчёте советов он не участвует вовсе. Обход
-- внешних баз ограничен бюджетом, а размер результата - ограничителями ниже.
local ADDON, ns = ...

local U = ns.Util
local Api = ns.Api
local CONF = ns.CONF

local FSight = {}
ns.Foresight = FSight

-- Горизонты --------------------------------------------------------------
--
-- Не вся игра до 60 сразу: это раздуло бы и файл, и время сбора, а пользы на
-- тридцать уровней вперёд нет - рецепты и вещи там он получит не скоро.
FSight.LEVEL_HORIZON = 10      -- следующие 10 уровней
FSight.SKILL_HORIZON = 75      -- один ранг профессии (225 -> 300)
FSight.MAX_PER_GROUP = 60      -- сколько позиций группы хранить в файле
FSight.MAX_REAGENTS = 120      -- материалов впереди - больше, они самые ценные
FSight.CODEX_BUDGET = 25000    -- сколько записей Codex обходить за сбор

-- Как часто пересобирать, даже если ничего не произошло. Сбор дешёвый, но не
-- бесплатный, и каждый пересчёт ему делать нечего.
FSight.MIN_INTERVAL = 900      -- 15 минут

FSight.result = nil
FSight.lastAt = nil
FSight.lastLevel = nil
FSight.lastSkillKey = nil

-- Нужно ли собирать заново ------------------------------------------------

local function skillKey(snap)
    local bits = {}
    for _, p in ipairs((snap and snap.professions) or {}) do
        bits[#bits + 1] = tostring(p.name) .. ":" .. tostring(p.max)
    end
    table.sort(bits)
    return table.concat(bits, "|")
end

-- Три повода собрать: ещё не собирали, персонаж вырос, потолок навыка поехал.
-- Плюс страховка по времени. Возвращает true/false и причину словами.
function FSight:Due(snap, now)
    now = tonumber(now) or (Api.Now and Api:Now()) or 0
    if not FSight.result then return true, "ещё не собирали" end
    local level = snap and snap.level
    if level and FSight.lastLevel and level ~= FSight.lastLevel then
        return true, "уровень изменился: " .. tostring(FSight.lastLevel)
            .. " -> " .. tostring(level)
    end
    local key = skillKey(snap)
    if key ~= FSight.lastSkillKey then
        return true, "потолок навыка изменился"
    end
    if FSight.lastAt and (now - FSight.lastAt) >= FSight.MIN_INTERVAL then
        return true, "прошло " .. U.round((now - FSight.lastAt) / 60) .. " мин"
    end
    return false, nil
end

-- Сбор -------------------------------------------------------------------

local function bounded(list, limit)
    local out, n = {}, 0
    for _, e in ipairs(list) do
        n = n + 1
        if n <= limit then out[n] = e end
    end
    return out, #list
end

-- Рецепты, которые уже лежат в книге, но НЕ выучены. Это самый надёжный
-- источник «что будет дальше»: его дал сам клиент, в нём есть и состав, и
-- результат, и внешние базы для него не нужны вовсе. На настоящем персонаже это
-- 630 рецептов из 900.
function FSight:RecipesAhead()
    local out = {}
    local book = ns.RecipeBook
    if not book then return out end
    for _, recipe in ipairs(book:Iterate(function(r) return not r.learned end)) do
        out[#out + 1] = {
            id = recipe.id,
            name = recipe.name,
            profession = recipe.profession,
            output = recipe.output,
            outputQty = recipe.outputQty,
            category = recipe.category,
            reagents = recipe.reagents,
        }
    end
    table.sort(out, function(a, b) return (a.id or 0) < (b.id or 0) end)
    return out
end

-- МАТЕРИАЛЫ ВПЕРЁД - самое ценное в этом файле.
--
-- Реагенты невыученных рецептов, по частоте: материал, который нужен двадцати
-- рецептам, важнее материала на один. Возвращает список { itemID, recipes, qty }
-- и множество itemID для слепков цен.
function FSight:ReagentsAhead(recipesAhead)
    local tally, set = {}, {}
    for _, r in ipairs(recipesAhead or FSight:RecipesAhead()) do
        for _, g in ipairs(r.reagents or {}) do
            local id = tonumber(g.itemID)
            if id then
                local e = tally[id]
                if not e then
                    e = { itemID = id, recipes = 0, qty = 0 }
                    tally[id] = e
                end
                e.recipes = e.recipes + 1
                e.qty = e.qty + (tonumber(g.qty) or 0)
                set[id] = true
            end
        end
    end
    local list = {}
    for _, e in pairs(tally) do list[#list + 1] = e end
    table.sort(list, function(a, b)
        if a.recipes ~= b.recipes then return a.recipes > b.recipes end
        return a.itemID < b.itemID
    end)
    return list, set
end

-- Экипировка в полосе уровней впереди, под класс и школу этого персонажа.
--
-- Два источника, и оба честно помечены:
--   * выходы невыученных рецептов - это точно то, что он сможет сделать сам;
--   * обход Codex - шире, но только когда Codex установлен и загружен.
-- Без Codex группа не пустеет, а просто становится уже, и в notes сказано, что
-- именно поэтому.
function FSight:GearAhead(snap, recipesAhead)
    local level = tonumber(snap and snap.level) or 0
    local from, to = level + 1, level + FSight.LEVEL_HORIZON
    local out, seen = {}, {}
    -- ШКОЛА БЕРЁТСЯ ИЗ НАБОРА ВЕСОВ, а не из отдельного поля: отдельного поля
    -- нет, школа у этого персонажа определена по надетым вещам и записана в
    -- snap.weightSetKey ("CASTER_ARCANE"). MAIN_STAT превращает набор в сам
    -- ключ характеристики - SPELLDMG_ARCANE, то есть жемчужную линию.
    local setKey = snap and snap.weightSetKey or nil
    local mainStat = (ns.StatWeights and ns.StatWeights.MAIN_STAT
        and ns.StatWeights.MAIN_STAT[setKey or ""]) or nil
    local schoolStat = ns.SCHOOL_BY_STAT and ns.SCHOOL_BY_STAT[mainStat or ""]
        and mainStat or nil

    local function consider(itemID, source)
        itemID = tonumber(itemID)
        if not itemID or seen[itemID] then return end
        local classID, subclass, inv, req, quality = Api:ForeignItemClass(itemID)
        if not req then return end
        if req < from or req > to then return end
        local slot = inv and ns.SlotMap:FromInvNumber(inv) or nil
        if not slot then return end
        local stats = Api:ForeignItemStats(itemID)
        local mine = nil
        if stats and schoolStat then
            -- Переводим ключи базы в наши и смотрим, есть ли школьный урон.
            for key, value in pairs(stats) do
                local stat = ns.StatWeights.FOREIGN_KEY_TO_STAT[key]
                if stat == schoolStat then mine = value end
            end
        end
        seen[itemID] = true
        out[#out + 1] = {
            itemID = itemID, reqLevel = req, slot = slot,
            classID = classID, subclassID = subclass, quality = quality,
            schoolStat = schoolStat, schoolAmount = mine,
            source = source,
        }
    end

    for _, r in ipairs(recipesAhead or {}) do consider(r.output, "unlearned-recipe") end

    -- Codex: тот же отбор, но по всему списку предметов. Бюджет обхода - чтобы
    -- сбор не превратился в секундную паузу на входе в игру.
    if Api.CodexReady and Api:CodexReady() then
        local budget = FSight.CODEX_BUDGET
        Api:CodexEach("item", function(id)
            budget = budget - 1
            if budget <= 0 then return false end
            consider(id, "codex")
            if #out >= FSight.MAX_PER_GROUP * 3 then return false end
            return true
        end)
    end

    table.sort(out, function(a, b)
        if a.reqLevel ~= b.reqLevel then return a.reqLevel < b.reqLevel end
        return a.itemID < b.itemID
    end)
    return out, mainStat, schoolStat, from, to
end

-- Формулы чар, которые откроются: невыученные формулы из книги. Слот и порог
-- навыка - то, что про них известно; чего не известно, то и не пишем.
function FSight:EnchantsAhead()
    local out = {}
    local book = ns.RecipeBook
    if not (book and ns.EnchantAdvisor) then return out end
    for _, recipe in ipairs(book:Iterate(function(r)
        return (not r.learned) and ns.EnchantAdvisor:IsEnchantRecipe(r)
    end)) do
        local slot, conf = ns.SlotMap:EnchantSlot(recipe)
        out[#out + 1] = {
            id = recipe.id, name = recipe.name,
            slot = slot, slotConf = conf,
            category = recipe.category,
            reagents = recipe.reagents,
        }
    end
    table.sort(out, function(a, b) return (a.id or 0) < (b.id or 0) end)
    return out
end

-- Тренеры следующего ранга. Своих записей тут почти никогда нет (игрок ещё не
-- дошёл), поэтому основной источник - Codex по роли "trainer:<skillLineID>".
-- Нет skillLineID - нет и запроса: угадывать номер профессии нельзя, иначе
-- стрелка поедет к чужому NPC.
function FSight:TrainersAhead(snap)
    local out, notes = {}, {}
    local noLine, noAnswer = {}, {}
    for _, prof in ipairs((snap and snap.professions) or {}) do
        -- НОМЕР БЕРЁТСЯ ЧЕРЕЗ ForeverSource:ResolveSkillLine. Клиент отдаёт
        -- одну профессию под двумя номерами - современным и классическим, - а
        -- роли тренеров в Codex размечены классическими. Брать первый
        -- попавшийся номер клиента значило спрашивать Codex про trainer:2948,
        -- на что он честно отвечал пусто: в живом файле ровно два из пяти
        -- запросов вернулись пустыми, и это были чары и портняжка.
        local FS = ns.ForeverSource
        local line, lineFrom
        if FS and FS.ResolveSkillLine then
            line, lineFrom = FS:ResolveSkillLine(prof)
        else
            line = tonumber(prof.skillLineID)
            lineFrom = line and "client" or nil
        end
        if not line then
            noLine[#noLine + 1] = tostring(prof.name)
        else
            local list = Api.CodexWithRole and Api:CodexWithRole("trainer:" .. line) or nil
            if not list then
                noAnswer[#noAnswer + 1] = tostring(prof.name)
            else
                for _, npcID in ipairs(list) do
                    local mapID, x, y, name = Api:CodexNpcSpawn(npcID)
                    out[#out + 1] = {
                        npcID = npcID, profession = prof.name,
                        skillLineID = line, skillLineFrom = lineFrom, name = name,
                        mapID = mapID, x = x, y = y,
                        routable = (mapID and x and y) and true or false,
                    }
                    if #out >= FSight.MAX_PER_GROUP then break end
                end
            end
        end
    end
    -- ОДНА ПОМЕТКА НА ВСЕХ, а не пять одинаковых: пять строк об одном и том же
    -- - это шум, в котором тонут настоящие пометки.
    if #noLine > 0 then
        table.sort(noLine)
        notes[#notes + 1] = "номер линии навыка неизвестен у "
            .. #noLine .. " " .. U.plural(#noLine, "профессии", "профессий", "профессий")
            .. " (" .. table.concat(noLine, ", ") .. ") — тренеров по ним не спросить"
    end
    if #noAnswer > 0 then
        table.sort(noAnswer)
        notes[#notes + 1] = "Codex не ответил про тренеров по "
            .. #noAnswer .. " " .. U.plural(#noAnswer, "профессии", "профессиям", "профессиям")
            .. " (" .. table.concat(noAnswer, ", ") .. ")"
    end
    return out, notes
end

-- Зоны, где персонаж будет качаться дальше.
--
-- ЧЕСТНЫЙ ОТВЕТ ЗДЕСЬ - ЧАЩЕ ВСЕГО «НЕ ЗНАЮ». Полос уровней по зонам нет ни в
-- клиенте, ни в наших данных; Codex хранит зоны, но без диапазона уровней.
-- Поэтому вместо выдуманного маршрута прокачки пишется то, что действительно
-- известно: зоны, где стоят NPC из уже собранного заказа (тренеры следующего
-- ранга и торговцы будущих материалов). Это не «куда он пойдёт», а «куда ему
-- придётся прийти», и так и подписано.
function FSight:ZonesAhead(trainers, reagents)
    local tally = {}
    local function note(mapID, why)
        mapID = tonumber(mapID)
        if not mapID then return end
        local e = tally[mapID]
        if not e then
            e = { mapID = mapID, name = Api:MapName(mapID), reasons = {}, n = 0 }
            tally[mapID] = e
        end
        e.n = e.n + 1
        e.reasons[why] = (e.reasons[why] or 0) + 1
    end
    for _, t in ipairs(trainers or {}) do note(t.mapID, "trainer") end
    -- Торговцы будущих материалов: по нашим же данным о местах.
    for i = 1, math.min(30, #(reagents or {})) do
        local r = reagents[i]
        local place = ns.Places and ns.Places:ForItem(r.itemID) or nil
        if place and place.mapID then note(place.mapID, "material-vendor") end
    end
    local out = {}
    for _, e in pairs(tally) do out[#out + 1] = e end
    table.sort(out, function(a, b)
        if a.n ~= b.n then return a.n > b.n end
        return a.mapID < b.mapID
    end)
    return out
end

-- Собрать всё ------------------------------------------------------------

function FSight:Collect(snap, now)
    snap = snap or (ns.CharacterScanner and ns.CharacterScanner:Get()) or nil
    now = tonumber(now) or (Api.Now and Api:Now()) or 0

    local level = tonumber(snap and snap.level) or 0
    local notes = {}

    local recipes = FSight:RecipesAhead()
    local reagents = FSight:ReagentsAhead(recipes)
    local gear, mainStat, schoolStat, lvFrom, lvTo = FSight:GearAhead(snap, recipes)
    local setKey = snap and snap.weightSetKey or nil
    local enchants = FSight:EnchantsAhead()
    local trainers, trainerNotes = FSight:TrainersAhead(snap)
    for _, n in ipairs(trainerNotes) do notes[#notes + 1] = n end
    local zones = FSight:ZonesAhead(trainers, reagents)

    if not (Api.CodexReady and Api:CodexReady()) then
        notes[#notes + 1] = "Codex не загружен: вещи впереди взяты только из"
            .. " невыученных рецептов, тренеры и зоны — из своих записей"
    end
    if not Api:ItemDBReady() then
        notes[#notes + 1] = "внешней базы предметов нет: уровень требования у"
            .. " вещей впереди проверить нечем, группа gear будет пустой"
    end
    notes[#notes + 1] = "диапазонов уровней по зонам нет ни в клиенте, ни в наших"
        .. " данных — zones это «куда придётся прийти», а не маршрут прокачки"

    -- Горизонт из Data/Horizon.lua: там посчитано то же самое, но по рецептам
    -- диапазона 226-300 целиком, а не только по тем, что клиент уже показал.
    -- Плюс честные дыры этого файла - их надо перечислить, а не умолчать.
    local HZ = ns.Horizon
    if HZ then
        -- СКОЛЬКО ДОБАВЛЕНО ЭТОМУ ПЕРСОНАЖУ, А НЕ СКОЛЬКО В ФАЙЛЕ.
        --
        -- Здесь печаталось HZ.PRICE_WATCH_COUNT - размер всего справочника (97),
        -- при том что справочник собран по портняжке и чарам. Алхимик читал
        -- «добавил 97 реагентов будущих рецептов» и не имел никакой возможности
        -- узнать, что ни один из них к его профессиям не относится. Теперь
        -- называется число, которое и правда попало в слепок, и чьи это
        -- реагенты.
        local added = tonumber(FSight.horizonWatched)
        if added == nil and HZ.PRICE_WATCH_COUNT then
            -- Слепок ещё не собирался: сказать можно только про файл, и
            -- сказано именно это.
            notes[#notes + 1] = "в Data/Horizon.lua есть "
                .. HZ.PRICE_WATCH_COUNT
                .. " реагентов будущих рецептов (портняжка и чары);"
                .. " сколько из них попадёт в слепки, станет видно на пересчёте"
        elseif added == 0 then
            notes[#notes + 1] = "из Data/Horizon.lua в слепки цен не попало"
                .. " ничего: там только реагенты портняжного дела и наложения"
                .. " чар, а у этого персонажа этих профессий нет"
        elseif added then
            notes[#notes + 1] = "Data/Horizon.lua добавил " .. added .. " "
                .. U.plural(added, "реагент", "реагента", "реагентов")
                .. " будущих рецептов в слепки цен — по профессиям этого"
                .. " персонажа, а не весь список"
        end
        for _, text in pairs(HZ.GAPS or {}) do
            notes[#notes + 1] = "дыра в данных: " .. U.truncate(tostring(text), 160)
        end
    end

    -- Полосы навыка: от текущего максимума на один ранг вперёд.
    local skills = {}
    for _, prof in ipairs((snap and snap.professions) or {}) do
        local max = tonumber(prof.max)
        if max and max > 0 then
            skills[#skills + 1] = {
                name = prof.name, skill = prof.skill, max = max,
                aheadTo = max + FSight.SKILL_HORIZON,
                atCeiling = (tonumber(prof.skill) or 0) >= max,
                skillLineID = prof.skillLineID,
            }
        end
    end
    table.sort(skills, function(a, b) return tostring(a.name) < tostring(b.name) end)

    local recipesKept, recipesTotal = bounded(recipes, FSight.MAX_PER_GROUP)
    local reagentsKept, reagentsTotal = bounded(reagents, FSight.MAX_REAGENTS)
    local gearKept, gearTotal = bounded(gear, FSight.MAX_PER_GROUP)
    local enchantsKept, enchantsTotal = bounded(enchants, FSight.MAX_PER_GROUP)
    local trainersKept, trainersTotal = bounded(trainers, FSight.MAX_PER_GROUP)
    local zonesKept, zonesTotal = bounded(zones, FSight.MAX_PER_GROUP)

    local result = {
        -- ЭТО ПРЕДСКАЗАНИЕ, и первое поле об этом и говорит.
        kind = "prediction",
        disclaimer = "собрано на вырост: ничего из этого ещё не применимо."
            .. " Советов по этим позициям не выдаётся, пока уровень не дорос и"
            .. " рецепт не выучен",
        builtAt = now,
        forLevel = level,
        horizonLevels = FSight.LEVEL_HORIZON,
        levelBand = { from = lvFrom, to = lvTo },
        horizonSkill = FSight.SKILL_HORIZON,
        mainStat = mainStat,
        schoolStat = schoolStat,
        weightSetKey = setKey,
        skills = skills,

        recipes = { source = "клиент: невыученные рецепты в книге",
                    conf = CONF.CACHED,
                    total = recipesTotal, kept = #recipesKept, items = recipesKept },
        reagents = { source = "состав невыученных рецептов",
                     conf = CONF.CACHED,
                     note = "по этим предметам уже начаты суточные слепки цен",
                     total = reagentsTotal, kept = #reagentsKept, items = reagentsKept },
        gear = { source = "выходы невыученных рецептов + Polestar.Codex",
                 conf = CONF.ESTIMATE,
                 total = gearTotal, kept = #gearKept, items = gearKept },
        enchants = { source = "клиент: невыученные формулы чар",
                     conf = CONF.CACHED,
                     total = enchantsTotal, kept = #enchantsKept, items = enchantsKept },
        trainers = { source = "Polestar.Codex, роль trainer:<skillLineID>",
                     conf = CONF.ESTIMATE,
                     total = trainersTotal, kept = #trainersKept, items = trainersKept },
        zones = { source = "карты NPC из заказа выше",
                  conf = CONF.ESTIMATE,
                  total = zonesTotal, kept = #zonesKept, items = zonesKept },
        notes = notes,
    }

    FSight.result = result
    -- Множество для слепков собирается ОДНИМ путём - через TrackItems, - чтобы
    -- и граница, и список из Horizon применялись к нему всегда. Раньше сбор
    -- кладывал сюда свой набор, и TrackItems отдавал его как есть: без границы
    -- и без выверенных 97 позиций Horizon.
    FSight.reagentSet = nil
    FSight:TrackItems()
    FSight.lastAt = now
    FSight.lastLevel = level
    FSight.lastSkillKey = skillKey(snap)

    if ns.Diag then
        ns.Diag:Init().wantedAhead = result
        ns.Diag:Count("foresight.collected")
        ns.Diag:Module("foresight", {
            ["in"] = recipesTotal, out = reagentsTotal,
            level = level, levelBandTo = lvTo,
            recipesAhead = recipesTotal, reagentsAhead = reagentsTotal,
            gearAhead = gearTotal, enchantsAhead = enchantsTotal,
            trainersAhead = trainersTotal,
            reason = (reagentsTotal == 0)
                and "невыученных рецептов в книге нет — предсказывать нечего" or nil,
            reasonCode = (reagentsTotal == 0) and "NOTHING_LEARNED" or nil,
        })
    end
    return result
end

-- Собрать, если пора. Это то, что зовут события.
function FSight:Refresh(snap, now)
    local due, why = FSight:Due(snap, now)
    if not due then return nil, "not-due" end
    if Api:InCombat() then return nil, "combat" end
    local result = FSight:Collect(snap, now)
    if ns.Diag and why then
        ns.Diag:Log("горизонт пересобран: " .. why, {
            level = result.forLevel,
            reagentsAhead = result.reagents.total,
        })
    end
    return result, why
end

-- Предметы для суточных слепков цен ---------------------------------------
--
-- ЭТО ГЛАВНОЕ ПРИМЕНЕНИЕ ВСЕГО ФАЙЛА. История цен задним числом не собирается,
-- поэтому слепок должен брать не только то, что нужно сейчас, но и то, что
-- понадобится через ранг профессии. Возвращает множество itemID.
-- СКОЛЬКО МАТЕРИАЛОВ ВПЕРЁД ПОПАДАЕТ В СЛЕПКИ ЦЕН.
--
-- Граница нужна, и вот почему. Список строился по ВСЕМ невыученным рецептам в
-- книге - на этом персонаже их 630 из 900, и это ещё немного. Книга растёт с
-- каждым открытым рангом профессии, а слепок берёт цену по каждой позиции
-- ежедневно; расти без предела он не должен. Живая сводка «данных не хватило
-- по 5741 цене» заставила посмотреть на это вплотную: сам счётчик тогда врал
-- (см. Diag:Want), но вопрос «а не тянем ли мы цены на пол-игры» остался
-- законным, и ответ на него должен быть границей, а не надеждой.
--
-- Число то же, что у FSight.MAX_REAGENTS, и по той же причине: сто двадцать
-- самых нужных материалов - это уже весь ранг профессии вперёд, а позиция
-- номер триста нужна одному рецепту из трёхсот.
--
-- Отбор не случайный: ReagentsAhead отдаёт список, упорядоченный по тому, в
-- сколько будущих рецептов материал входит. Отрезается хвост, а не середина.
FSight.MAX_TRACK_AHEAD = 120
FSight.trackAheadTotal = nil
FSight.trackAheadDropped = nil

-- Множество для слепков из уже посчитанного упорядоченного списка. Отдельной
-- функцией затем, что звать её надо из двух мест - из сбора горизонта и из
-- TrackItems, - и граница обязана быть одна на оба.
function FSight:BoundedTrackSet(ranked)
    local set = {}
    local kept = 0
    for _, e in ipairs(ranked or {}) do
        if kept >= FSight.MAX_TRACK_AHEAD then break end
        set[e.itemID] = true
        kept = kept + 1
    end
    FSight.trackAheadTotal = #(ranked or {})
    FSight.trackAheadDropped = math.max(0, FSight.trackAheadTotal - kept)
    return set, kept
end

function FSight:TrackItems()
    if FSight.reagentSet then return FSight.reagentSet end
    local ranked = FSight:ReagentsAhead()
    local set, kept = FSight:BoundedTrackSet(ranked)

    -- И СПИСОК ИЗ Data/Horizon.lua. Там те же реагенты, но посчитанные по
    -- рецептам диапазона 226-300 целиком, включая те, которых в книге у игрока
    -- ещё нет: 97 позиций, сверенных между двумя базами на диске. Наш обход по
    -- книге видит только то, что клиент уже показал, и этого меньше.
    --
    -- Эти позиции границей НЕ отрезаются: они не «всё, что нашлось», а
    -- выверенный список, и каждая позиция в нём уже отобрана по частоте.
    --
    -- НО ТОЛЬКО СВОИХ ПРОФЕССИЙ. Весь список целиком - это реагенты портняжки и
    -- чар, и он попадал в слепок цен ЛЮБОМУ персонажу: чернокнижник-алхимик
    -- каждый день снимал цену на рунную ткань и лунную ткань, которые ему не
    -- нужны ни для чего. Поле профессии у каждой записи было с самого начала,
    -- его просто никто не читал.
    local snap = ns.CharacterScanner and ns.CharacterScanner:Get() or nil
    local watched = 0
    if ns.Horizon and ns.Horizon.WatchList then
        -- ЗАПИСИ ПРОФЕССИЙ ЦЕЛИКОМ, А НЕ ОДНИ ИМЕНА.
        --
        -- Имя зависит от языка клиента, а номер линии навыка - нет. Справочник
        -- сверялся только по именам, русским: на клиенте, язык которого нам
        -- незнаком, не совпадало ничего, и список наблюдения обнулялся МОЛЧА -
        -- суточные слепки цен просто прекращались. Теперь запись уходит
        -- целиком, и Horizon сам решает, по номеру ему сверять или по имени.
        local mine, names = {}, {}
        for _, prof in ipairs((snap and snap.professions) or {}) do
            if prof.name then
                mine[#mine + 1] = prof
                names[#names + 1] = prof.name
            end
        end
        -- Профессий не знаем вовсе - берём пустой список, а не весь: наблюдать
        -- «на всякий случай» за чужими материалами значит писать в историю цен
        -- шум, который потом нечем отличить от своих наблюдений.
        local list, report = ns.Horizon:WatchList(mine)
        for _, itemID in ipairs(list) do
            set[itemID] = true
            watched = watched + 1
        end
        FSight.horizonWatched = watched
        FSight.horizonProfessions = names
        -- ОТЧЁТ О СВЕРКЕ ХРАНИТСЯ, А НЕ ВЫБРАСЫВАЕТСЯ. Это единственное, по
        -- чему потом видно, за своими материалами мы наблюдаем или за всеми -
        -- и почему.
        FSight.horizonMatch = report
        if report and report.recognised == false and ns.Diag then
            ns.Diag:Count("horizon.professionsUnrecognised", 1)
        end
    end
    if ns.Diag and FSight.trackAheadDropped > 0 then
        ns.Diag:Log("список наблюдения за ценами ограничен", {
            kept = kept, total = FSight.trackAheadTotal,
            dropped = FSight.trackAheadDropped,
            limit = FSight.MAX_TRACK_AHEAD,
            note = "материалы впереди отобраны по числу будущих рецептов;"
                .. " отрезан хвост, а не середина",
        })
    end
    -- ОТВЕТ, ПОСЧИТАННЫЙ БЕЗ СНИМКА, НЕ ЗАПОМИНАЕТСЯ.
    --
    -- Теперь в множество идут реагенты ТОЛЬКО своих профессий, а профессии
    -- живут в снимке персонажа. Пока снимка нет (а Main сканирует до первого
    -- пересчёта, так что в игре это окно до первого входа в мир), профессий мы
    -- не знаем, и из Horizon не берётся ничего - это правильный ответ на
    -- «не знаю». Но запоминать его нельзя: кеш живёт всю сессию, и один
    -- случайный вызов до сканирования оставил бы игрока без слепка цен на
    -- горизонте до самого выхода из игры, причём молча.
    if snap then
        FSight.reagentSet = set
    elseif ns.Diag then
        ns.Diag:Log("список наблюдения посчитан без снимка персонажа и не запомнен", {
            why = "профессии живут в снимке; ответ без него неполон по построению",
        })
    end
    return set
end

return FSight
