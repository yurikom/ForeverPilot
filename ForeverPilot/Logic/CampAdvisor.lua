-- ForeverPilot / Logic/CampAdvisor.lua
--
-- ЛАГЕРЬ: ЧТО ПОСТАВИТЬ У КОСТРА, ЧЕМ ЭТО СДЕЛАТЬ И ЧЕГО НЕ ХВАТАЕТ.
--
-- Система простая и ровно поэтому легко пропускается: игрок ставит у костра
-- предметы, они дают бонусы всем, кто рядом. Предметы делаются профессиями, и
-- КАЖДАЯ профессия даёт свой - включая добычные, у которых нет окна крафта
-- (рыбалка, травничество, горное дело, снятие шкур). Поэтому первый тир лагеря
-- закрывается не тем, что персонаж «умеет крафтить», а тем, какие профессии
-- есть на аккаунте вообще - и у человека с двумя персонажами ответ шире, чем он
-- думает.
--
-- ЧЕГО ЭТА ВЕТКА НЕ ЗНАЕТ И ЗНАТЬ НЕ МОЖЕТ. В клиенте нет НИ ОДНОЙ функции про
-- лагерь: ни «что уже поставлено», ни «идёт ли откат». (Событие
-- PLAYER_CAMPING - древний выход из игры, к лагерю отношения не имеет; на него
-- мы не подписываемся.) Значит ветка не может сказать «у вас уже стоит
-- аквариум» или «подождите 40 минут» - и обязана сказать об этом вслух, а не
-- молча советовать то, что, может быть, уже сделано. Советы строятся по тому,
-- что видно: профессии и навык (клиент + свой реестр), сумки, цены.
--
-- ЧТО СКЛАДЫВАЕТСЯ С ЧЕМ. В данных на диске про это есть ровно одно поле -
-- `over`: объект второго тира ставится ПОВЕРХ своего первого и бонус первого
-- сохраняет. Это и говорится. А про то, складывается ли бонус лагеря с тем,
-- что персонаж даёт себе сам (интеллект от мага, выносливость от еды), в обеих
-- базах на диске нет ничего - ни слова, ни числа. Поэтому ветка про это НЕ
-- ЗАЯВЛЯЕТ НИЧЕГО и прямо говорит, что не проверяла: догадка здесь стоила бы
-- игроку реагентов.
--
-- ПОРОГИ НАВЫКА НЕ ЗАБИТЫ В КОД. Они в Data/Camp.lua, двумя числами из двух
-- независимых баз, и там же сказано, где эти числа расходятся. Blizzard уже
-- меняла их хотфиксом, поэтому единственное честное поведение - взять бо́льшее
-- и назвать спор словами (Camp:Threshold).
local ADDON, ns = ...

local U = ns.Util
local Api = ns.Api
local CONF = ns.CONF

local Camp = {}
ns.CampAdvisor = Camp

-- ОСИ ЭТОЙ ВЕТКИ - ПОРЯДОК ВНУТРИ НЕЁ, А НЕ БАЛЛЫ.
--
-- Бонус лагеря - это процент от характеристик или возможность («костёр держит
-- ещё 3 предмета»), а балл в этом аддоне считается по весам характеристик
-- предмета. Перевести одно в другое нечем, и делать вид, что перевели, нельзя:
-- «+8% ко всем характеристикам» в баллах - это выдуманное число. Поэтому
-- power - постоянная по виду бонуса, и она отвечает только на один вопрос:
-- какой из камповых советов показать выше другого камповoго.
--
-- Порядок выведен из ДАННЫХ, а не из вкуса: сначала то, что даёт все
-- характеристики и у чего в описании есть число; потом то, что даёт все
-- характеристики без числа; потом одна характеристика; потом костёр (без него
-- остальное не поставить); потом возможности.
Camp.POWER = {
    ALL_STATS_PCT = 0.60,
    ALL_STATS     = 0.45,
    STAT_PCT      = 0.35,
    STAT          = 0.30,
    FIRE          = 0.25,
    OTHER         = 0.15,
}

function Camp:PowerOf(row)
    local gain = (type(row) == "table") and row.gain or nil
    if type(gain) ~= "table" then return Camp.POWER.OTHER end
    if gain.kind == "ALL_STATS" then
        return gain.pct and Camp.POWER.ALL_STATS_PCT or Camp.POWER.ALL_STATS
    end
    if gain.kind == "STAT" then
        return gain.pct and Camp.POWER.STAT_PCT or Camp.POWER.STAT
    end
    if gain.kind == "FIRE" then return Camp.POWER.FIRE end
    return Camp.POWER.OTHER
end

-- Порог навыка: сколько надо, и спорно ли это -----------------------------
--
-- Возвращает need, disputed, low, high. need - БО́ЛЬШЕЕ из двух чисел: ошибка
-- «не предложил доступное» стоит игроку ничего, ошибка «предложил недоступное»
-- стоит ему дороги к костру и собранных впустую реагентов.
function Camp:Threshold(row)
    if type(row) ~= "table" then return nil, false end
    local a, b = tonumber(row.skill), tonumber(row.skillWT)
    if not a and not b then return nil, false end
    if not a then return b, false, b, b end
    if not b then return a, false, a, a end
    if a == b then return a, false, a, a end
    local low, high = math.min(a, b), math.max(a, b)
    return high, true, low, high
end

-- Имя предмета: клиент, иначе Codex ---------------------------------------
--
-- БЕЗ ИМЕНИ ПРЕДМЕТА КАРТОЧКИ НЕТ - то же правило, что у ветки
-- Благосклонности: «Сделать для лагеря: Предмет #279967» не совет, игрок не
-- найдёт в игре то, чего не может прочитать.
--
-- Но здесь молчать пришлось бы почти всегда, и это важное отличие от других
-- веток: предметы лагеря игрок в руках не держал, а клиент знает имя только
-- того, что видел. Поэтому вторым путём спрашивается Codex - он отдаёт имя на
-- языке клиента, когда пакет имён установлен (у игрока он есть), и английское
-- из пакета, когда нет. Третьего пути не придумано: карточки просто не будет, и
-- ветка скажет, сколько имён не дождалась.
function Camp:ItemName(itemID)
    itemID = tonumber(itemID)
    if not itemID then return nil end
    local info = Api:ItemInfo(itemID)
    if info and info.name and info.name ~= "" then return info.name, "client" end
    local name = Api.CodexItemName and Api:CodexItemName(itemID) or nil
    if name then return name, "codex" end
    return nil
end

-- Общий бафф лагеря на игроке ----------------------------------------------
--
-- { active = true, name, remaining } или nil. remaining - секунды до конца;
-- nil, если игра не сказала, когда бафф кончится.
function Camp:BuffState(snap)
    local auras = snap and snap.auras
    if type(auras) ~= "table" then return nil end
    local ids = ns.CampData and ns.CampData.CAMP_BUFF_SPELLS or {}
    for _, a in ipairs(auras) do
        if a.spellID and ids[a.spellID] then
            local remaining = nil
            if a.expires and a.expires > 0 then
                remaining = a.expires - Api:Now()
                if remaining < 0 then remaining = 0 end
            end
            return { active = true, name = a.name, remaining = remaining }
        end
    end
    return nil
end

-- Что из лагеря уже действует на игрока ------------------------------------
--
-- Функций про лагерь в клиенте нет, но бонус объекта - это бафф, а баффы
-- читаются (Api:PlayerAuras, снимок персонажа). Сравнение идёт по номеру
-- заклинания (CampData.ITEM_BY_SPELL), а если клиент номера не отдал - по
-- имени: бафф, названный в точности как предмет лагеря.
--
-- Возвращает { [itemID] = бафф }. Пустая таблица значит «ничего не видно», и
-- это НЕ «ничего не стоит»: объекты без баффа (верстаки, костёр) так не
-- увидеть вовсе.
function Camp:ActiveEffects(snap)
    local out = {}
    local auras = snap and snap.auras
    if type(auras) ~= "table" or #auras == 0 then return out end
    local data = ns.CampData
    if not data then return out end
    local bySpell = data.ITEM_BY_SPELL or {}
    local byName = nil
    for _, a in ipairs(auras) do
        local item = a.spellID and bySpell[a.spellID] or nil
        if not item and a.name then
            if not byName then
                byName = {}
                for itemID in pairs(data.BY_ITEM or {}) do
                    local name = self:ItemName(itemID)
                    if name then byName[name] = itemID end
                end
            end
            item = byName[a.name]
        end
        if item then out[item] = a end
    end
    return out
end

-- Имя профессии на языке клиента ------------------------------------------
--
-- В данных профессия названа по-английски («Fishing»), потому что так её
-- называет источник. Игроку английское имя профессии показывать запрещено
-- (правило держит Tests/test_sense.lua), и переводить его здесь нечем: перевод
-- один и он в RecipeBook.NAME_BRIDGE - туда и ведёт U.profLabel.
--
-- nil означает «перевода нет»: тогда профессия в тексте НЕ НАЗЫВАЕТСЯ вовсе.
-- Подставить сюда английское имя было бы ровно той находкой, из-за которой
-- правило и появилось: «нет рецептов ни по одной из ваших профессий (Alchemy,
-- Cooking, Engineering)» в русском клиенте.
function Camp:ProfessionLabel(profEn)
    if type(profEn) ~= "string" or profEn == "" then return nil end
    local label = U.profLabel(profEn)
    if type(label) ~= "string" or label == "" then return nil end
    if label == profEn then return nil end
    return label
end

-- Чей это навык и сколько его -------------------------------------------
--
-- Три разных ответа, и путать их нельзя:
--   * профессия есть ЗДЕСЬ, навык такой-то - можно делать самому;
--   * профессии здесь нет, а на аккаунте есть - сделает другой и пришлёт;
--   * нет ни у кого - этот предмет лагеря не закрыт вовсе, и это не упрёк
--     игроку, а просто факт про аккаунт.
--
-- Навык текущего персонажа берётся из снимка (клиент), остальных - из своего
-- реестра и чужого кеша (Roster:ProfessionIndex). Имя профессии приходит с той
-- стороны то русским, то английским, поэтому сравниваем по обоим.
-- `index` - готовый Roster:ProfessionIndex(). Передаётся снаружи НАРОЧНО: он
-- обходит весь реестр и чужой кеш, а спрашивают про 38 объектов за пересчёт -
-- то есть без этого индекс собирался бы 38 раз на каждый пересчёт. Кто не дал
-- индекс, получает честный ответ без альтов: выдумывать его здесь нечем.
function Camp:Owners(profEn, snap, index)
    local out = { here = nil, holders = {} }
    local ru = Camp:ProfessionLabel(profEn)
    local want = { [U.lower(profEn or "")] = true }
    if ru then want[U.lower(ru)] = true end

    for _, prof in ipairs((snap and snap.professions) or {}) do
        if prof.name and want[U.lower(prof.name)] then
            -- Навыку, которому мы не верим, гейт не доверяем: лучше не
            -- предложить, чем предложить недоступное.
            if prof.skillTrusted ~= false then
                out.here = tonumber(prof.skill)
            end
            out.hereName = prof.name
            out.hereKnown = true
        end
    end

    local mine = snap and (snap.fullName or snap.name) or nil
    for name, holders in pairs(index or {}) do
        if want[U.lower(name)] then
            for _, h in ipairs(holders) do
                if h.fullName ~= mine then
                    out.holders[#out.holders + 1] = {
                        fullName = h.fullName, skill = tonumber(h.skill),
                        level = h.level, className = h.className,
                        source = h.source,
                    }
                end
            end
        end
    end
    table.sort(out.holders, function(a, b)
        local sa, sb = a.skill or -1, b.skill or -1
        if sa ~= sb then return sa > sb end
        return tostring(a.fullName) < tostring(b.fullName)
    end)
    return out
end

-- Подпись персонажа: полное имя, уровень и класс словом. У игрока два персонажа
-- по имени «Гендольф», и одного имени здесь не хватает - та же причина, по
-- которой подпись собирается в CrossCharacter:Label.
function Camp:HolderLabel(holder)
    if type(holder) ~= "table" then return "?" end
    local bits = {}
    if holder.skill then bits[#bits + 1] = "навык " .. holder.skill end
    if holder.level then bits[#bits + 1] = holder.level .. " ур." end
    if holder.className then bits[#bits + 1] = tostring(holder.className) end
    local who = tostring(holder.fullName or "?")
    if #bits > 0 then who = who .. " (" .. table.concat(bits, ", ") .. ")" end
    return who
end

-- Что объект даёт, словами ------------------------------------------------
--
-- Числа - только те, что есть в данных. Где числа нет, так и сказано: «сколько
-- именно, в данных не написано» - это ЧЕСТНЕЕ, чем бодрая фраза без числа, и
-- заметно честнее нуля.
--
-- Названия характеристик берутся из единственного словаря аддона
-- (GearAdvisor.STAT_LABEL, родительный падеж), поэтому второй словарь здесь не
-- появляется и разойтись им не с чем.
function Camp:GainText(row)
    local gain = (type(row) == "table") and row.gain or nil
    if type(gain) ~= "table" then return nil end
    local function stat(key)
        return (ns.GearAdvisor and ns.GearAdvisor:StatLabel(key)) or tostring(key)
    end
    local kind = gain.kind
    if kind == "ALL_STATS" then
        if gain.pct then return "+" .. gain.pct .. "% ко всем характеристикам" end
        local bits = { "больше всех характеристик" }
        if gain.armor then bits[#bits + 1] = "брони" end
        if gain.resist then bits[#bits + 1] = "сопротивлений" end
        return table.concat(bits, ", ")
    elseif kind == "STAT" then
        if gain.pct then return "+" .. gain.pct .. "% " .. stat(gain.stat) end
        return "больше " .. stat(gain.stat)
    elseif kind == "RESTED" then
        return "отдых: до " .. tostring(gain.pct) .. "% уровня"
    elseif kind == "FIRE" then
        local n = tonumber(gain.slots) or 0
        return "костёр для готовки и место ещё под " .. n .. " "
            .. U.plural(n, "предмет", "предмета", "предметов") .. " лагеря"
    elseif kind == "STATION" then
        return "рабочее место для рецептов, которым оно нужно"
    elseif kind == "MAKES" then
        return "делает расходники на месте"
    elseif kind == "VENDOR" then
        return gain.repair and "продаёт реагенты и починит" or "продаёт реагенты"
    elseif kind == "GATHER" then
        return "растит добычу сам"
    elseif kind == "FOOD" then
        return "стол с едой на " .. stat(gain.stat)
    elseif kind == "FISHING" then
        return "час ловится рыба получше"
    elseif kind == "DISENCHANT" then
        return "распыление даёт больше"
    elseif kind == "TRACK" then
        return "даёт слежку за зверями"
    elseif kind == "TRAP" then
        return "держит ловушку"
    end
    return nil
end

-- ВЫУЧЕН ЛИ РЕЦЕПТ - ВОПРОС К КНИГЕ РЕЦЕПТОВ, А НЕ К ПУСТОТЕ.
--
-- Предметы лагеря лежат в окне профессии обычными рецептами, и книга аддона их
-- уже читает: у мага в «Рыбной ловле» три рецепта, два выучены. Поэтому здесь
-- ТРИ разных ответа, и путать их нельзя:
--   "learned"   - рецепт выучен, предмет можно делать;
--   "missing"   - рецепты этой профессии прочитаны, этого среди выученных нет;
--   "no-book"   - рецептов этой профессии у меня нет вовсе (окно профессии в
--                 этой сессии не открывали), и тогда «не выучен» - не ответ, а
--                 моя слепота.
function Camp:RecipeState(row, snap)
    local book = ns.RecipeBook
    if not book then return "no-book" end
    if book.CanCraft and book:CanCraft(row.item) then
        local list = book:RecipesFor(row.item) or {}
        return "learned", list[1] and list[1].id or nil
    end
    -- Есть ли у меня список рецептов этой профессии вообще. Спрашиваем обоими
    -- именами: книга хранит то, которым её назвал источник.
    local known = false
    if book.HasProfession then
        if book:HasProfession(row.prof) then known = true end
        local ru = Camp:ProfessionLabel(row.prof)
        if ru and book:HasProfession(ru) then known = true end
    end
    if not known then return "no-book" end
    return "missing"
end

-- Один объект, разобранный по фактам -------------------------------------
--
--   { row, item, name, nameSource, prof, profLabel, need, disputed, low, high,
--     skill, canHere, recipeState, recipeID, learned, holders, holder,
--     reagents, cost, costKnown, missing, haveAll, buyCopper, buyConf,
--     bpItem, bpName, bpCopper, bpConf, gainText, overName, conf }
--
-- ЦЕНА РАБОТЫ И ДВА РЕЖИМА. Полный разбор одного объекта - это имя предмета,
-- имя каждого реагента, цена каждого реагента, цена готового предмета и цена
-- чертежа: до восьми обращений к ценам и до пяти к именам. Объектов 38, и
-- полный разбор всех на каждом пересчёте стоил бы около 170 вопросов о цене -
-- ровно та беда, из-за которой ветка перепродажи однажды подняла пересчёт с 9
-- до 71 мс (см. Core/Api.lua про кеш Codex).
--
-- Поэтому разбор делится на два: `cheap` отвечает на вопрос «кому и что это
-- вообще доступно» (профессия, навык, порог, рецепт - всё из данных и из
-- памяти, ни одного обращения к ценам), а полный зовётся только для тех
-- объектов, которые и правда могут стать советом. Числа - в Tests/test_camp.lua:
-- там это измерено вызовами, а не миллисекундами.
function Camp:Describe(row, snap, index, cheap)
    if type(row) ~= "table" then return nil end
    -- ПРЕДМЕТ ЧУЖОЙ ФРАКЦИИ НЕ СОВЕТУЕТСЯ. У портняжного знамени две версии, и
    -- в данных лежит только ордынская: альянсовому игроку советовать её нельзя,
    -- а подставить вместо неё альянсовую - нечем.
    if row.faction and snap and snap.factionFile
        and row.faction ~= snap.factionFile then
        return nil
    end
    local need, disputed, low, high = Camp:Threshold(row)
    local owners = Camp:Owners(row.prof, snap, index)
    local skill = owners.here
    local name, nameSource
    if not cheap then name, nameSource = Camp:ItemName(row.item) end

    -- ИМЯ СПРАШИВАЕТСЯ ПЕРВЫМ, И ЭТО НЕ ПОРЯДОК РАДИ ПОРЯДКА. Без имени
    -- карточки не будет вовсе, а значит не нужны и цены: восемь вопросов о цене
    -- про предмет, о котором я всё равно промолчу, - это и лишняя работа, и
    -- лишние «нет цены» в списке того, чего мне не хватает (его видит игрок,
    -- Core/Diag.lua, wanted).
    local priced = (not cheap) and (name ~= nil)

    local reagents, cost, costKnown, missing = {}, 0, true, {}
    if priced then
        for _, pair in ipairs(row.reag or {}) do
            local itemID, qty = pair[1], pair[2]
            local owned = (snap and snap.owned and snap.owned[itemID]) or nil
            local here = (snap and snap.bags and tonumber(snap.bags[itemID])) or 0
            local total = (owned and tonumber(owned.total)) or here
            local short = math.max(0, qty - here)
            local unit, unitConf = ns.PriceProvider:Buy(itemID)
            -- ИМЯ РЕАГЕНТА - ПО ТОМУ ЖЕ ПУТИ, ЧТО ИМЯ ПРЕДМЕТА. Реагенты лагеря
            -- игрок тоже мог не держать в руках («Звёздное дерево» покупается
            -- на аукционе), и тогда клиент о них молчит, а Codex - нет. Без
            -- этого в строке стояло «Материалы: 84м — Предмет #6291, Предмет
            -- #3371», то есть цена без ответа на вопрос, что покупать.
            local reagentName = Camp:ItemName(itemID)
            local line = {
                itemID = itemID, qty = qty, here = here, total = total,
                short = short, unit = unit, unitConf = unitConf,
                name = reagentName or U.itemFallbackName(itemID),
                named = (reagentName ~= nil),
            }
            if short > 0 then
                if unit then
                    cost = cost + unit * short
                else
                    costKnown = false
                end
                missing[#missing + 1] = line
            end
            reagents[#reagents + 1] = line
        end
    end

    local buyCopper, buyConf, bpCopper, bpConf, bpName, overName
    if priced then
        buyCopper, buyConf = ns.PriceProvider:Buy(row.item)
        if row.bp then
            bpCopper, bpConf = ns.PriceProvider:Buy(row.bp)
            bpName = Camp:ItemName(row.bp)
        end
        if row.over then overName = Camp:ItemName(row.over) end
    end

    local recipeState, recipeID = Camp:RecipeState(row, snap)

    -- Достоверность карточки целиком. Пороги и реагенты - из двух баз (CACHED);
    -- спорный порог опускает до оценки; цены приносят свою.
    local conf = U.worstConf(
        ns.CampData and ns.CampData.CONFIDENCE.SKILLS or CONF.CACHED,
        disputed and CONF.ESTIMATE or CONF.CACHED,
        (#missing > 0) and (costKnown and (buyConf or CONF.CACHED) or CONF.UNKNOWN)
            or CONF.CACHED)

    return {
        row = row,
        item = row.item,
        name = name, nameSource = nameSource,
        prof = row.prof,
        -- nil - перевода имени профессии нет; тогда она не называется вовсе.
        profLabel = Camp:ProfessionLabel(row.prof),
        need = need, disputed = disputed, low = low, high = high,
        skill = skill,
        -- ГЛАВНОЕ ПОЛЕ: может ли ЭТОТ персонаж сделать это сам. Два условия, и
        -- оба обязательны: навыка хватает И рецепт выучен.
        canHere = (skill ~= nil and need ~= nil) and (skill >= need) or false,
        hereKnown = owners.hereKnown or false,
        recipeState = recipeState,
        recipeID = recipeID,
        learned = (recipeState == "learned"),
        holders = owners.holders,
        holder = owners.holders[1],
        reagents = reagents,
        cost = cost, costKnown = costKnown, missing = missing,
        -- В дешёвом разборе реагенты не считались вовсе, и «всё есть в сумках»
        -- было бы утверждением из незнания: поле отвечает только после полного.
        haveAll = priced and (#missing == 0) or false,
        cheap = cheap and true or false,
        priced = priced and true or false,
        buyCopper = buyCopper, buyConf = buyConf,
        bpItem = row.bp, bpName = bpName,
        bpCopper = bpCopper, bpConf = bpConf,
        gainText = Camp:GainText(row),
        overName = overName,
        power = Camp:PowerOf(row),
        conf = conf,
    }
end

-- План: что делать сейчас -------------------------------------------------
--
-- Четыре списка, и они отвечают на четыре РАЗНЫХ вопроса - в этом вся ветка:
--   here     - рецепт выучен и навыка хватает: это «иди и сделай»;
--   gated    - навыка хватает, рецепта нет, а он с чертежа: чертёж предмет и он
--              торгуется, значит ответ - идти на аукцион, а не качать навык;
--   teach    - навыка хватает, рецепта нет, и он у тренера: ответ - к тренеру;
--   elsewhere- здесь не сделать, а на аккаунте есть кому.
--
-- И два числа про аккаунт: сколько предметов первого тира закрыто профессиями
-- аккаунта и каких профессий нет ни у кого.
--
-- ДВА ПРОХОДА, И ВТОРОЙ УЗКИЙ. Первый проход идёт по всем 38 объектам и не
-- задаёт НИ ОДНОГО вопроса о цене: раскладка по спискам решается профессией,
-- навыком, порогом и книгой рецептов. Цены и имена нужны только тем объектам,
-- которые реально могут стать советом, - их и разбирают полностью, по
-- Camp.DEEP на список. Разница измерима и измерена: см. Tests/test_camp.lua.
Camp.DEEP = 2

function Camp:Plan(snap)
    snap = snap or (ns.CharacterScanner and ns.CharacterScanner:Get()) or nil
    local data = ns.CampData
    if not (data and data.OBJECTS and #data.OBJECTS > 0) then return nil, "no-data" end

    -- Индекс профессий аккаунта - ОДИН на весь план: он обходит реестр и чужой
    -- кеш, а спрашивают про него 38 раз.
    local index = ns.Roster and ns.Roster.ProfessionIndex
        and ns.Roster:ProfessionIndex() or {}

    local here, gated, teach, elsewhere = {}, {}, {}, {}
    local covered, uncovered = 0, {}
    local nameless, disputed, unread = 0, 0, 0

    for _, row in ipairs(data.OBJECTS) do
        local d = Camp:Describe(row, snap, index, true)
        if d then
            if d.disputed then disputed = disputed + 1 end
            if row.tier == 1 then
                -- «Навык есть, но меньше порога» - это тоже «закрыто»: порог
                -- первого тира 20, а навык растёт сам. Не закрыто - когда
                -- профессии нет ни у кого на аккаунте.
                if d.hereKnown or #d.holders > 0 then
                    covered = covered + 1
                elseif d.profLabel then
                    uncovered[#uncovered + 1] = d.profLabel
                end
            end
            if d.canHere then
                if d.learned then
                    here[#here + 1] = d
                elseif d.recipeState == "no-book" then
                    -- Рецептов этой профессии у меня нет: «не выучен» было бы
                    -- утверждением из незнания. Считаем отдельно и молчим -
                    -- про закрытое окно профессии говорит ветка «Настроить».
                    unread = unread + 1
                elseif row.bp then
                    gated[#gated + 1] = d
                else
                    teach[#teach + 1] = d
                end
            elseif #d.holders > 0 then
                local best = d.holders[1]
                if (tonumber(best.skill) or -1) >= (d.need or 0) then
                    elsewhere[#elsewhere + 1] = d
                end
            end
        end
    end

    -- Порядок первого прохода: сильнее по данным, потом ниже тиром, потом по
    -- номеру - чтобы ответ не зависел от обхода таблицы. Цены здесь ещё не
    -- спрошены, поэтому «дешевле» в этом сравнении не участвует.
    local function byPower(a, b)
        if a.power ~= b.power then return a.power > b.power end
        if a.row.tier ~= b.row.tier then return a.row.tier < b.row.tier end
        return a.item < b.item
    end
    -- Второй проход: верхние Camp.DEEP каждого списка разбираются полностью, и
    -- уже среди них «дешевле» решает порядок. Объект без имени из списка
    -- выбывает - карточки без имени не бывает, - и это считается, а не
    -- замалчивается.
    local function deepen(list)
        table.sort(list, byPower)
        local out = {}
        for i = 1, math.min(Camp.DEEP, #list) do
            local full = Camp:Describe(list[i].row, snap, index, false)
            if full and full.name then
                out[#out + 1] = full
            elseif full then
                nameless = nameless + 1
            end
        end
        table.sort(out, function(a, b)
            if a.power ~= b.power then return a.power > b.power end
            local ac = a.costKnown and a.cost or math.huge
            local bc = b.costKnown and b.cost or math.huge
            if ac ~= bc then return ac < bc end
            if a.row.tier ~= b.row.tier then return a.row.tier < b.row.tier end
            return a.item < b.item
        end)
        return out, #list
    end

    local hereDeep, hereTotal = deepen(here)
    local gatedDeep, gatedTotal = deepen(gated)
    local teachDeep, teachTotal = deepen(teach)
    local elseDeep, elseTotal = deepen(elsewhere)
    table.sort(uncovered)

    -- САМЫЙ ВМЕСТИТЕЛЬНЫЙ КОСТЁР, КОТОРЫЙ УЖЕ МОЖНО ПОСТАВИТЬ. Нужен затем, что
    -- костёр с чертежа - это не «ещё один предмет», а замена: он держит больше.
    -- Сказать «5 мест вместо 3» можно только зная, что есть сейчас. Ищется по
    -- ВСЕМУ списку, а не по разобранным: сравнение считается по числу мест из
    -- данных, и цена для него не нужна.
    local fireNow, fireRow
    for _, d in ipairs(here) do
        local gain = d.row.gain
        if type(gain) == "table" and gain.kind == "FIRE" then
            if (not fireRow) or (tonumber(gain.slots) or 0)
                > (tonumber(fireRow.gain.slots) or 0) then
                fireRow = d.row
            end
        end
    end
    if fireRow then
        -- Уже разобранный костёр берём как есть, иначе разбираем именно его.
        for _, d in ipairs(hereDeep) do
            if d.item == fireRow.item then fireNow = d end
        end
        if not fireNow then
            local full = Camp:Describe(fireRow, snap, index, false)
            if full and full.name then fireNow = full end
        end
    end

    return {
        here = hereDeep, gated = gatedDeep, teach = teachDeep,
        elsewhere = elseDeep,
        -- Сколько их всего было до сужения: число в сводке и в проверках должно
        -- говорить про аккаунт, а не про то, сколько я успел разобрать.
        hereTotal = hereTotal, gatedTotal = gatedTotal,
        teachTotal = teachTotal, elsewhereTotal = elseTotal,
        fireNow = fireNow,
        covered = covered, total = data.TIER1_COUNT,
        uncovered = uncovered,
        nameless = nameless, disputed = disputed, unread = unread,
        conf = (#hereDeep > 0) and hereDeep[1].conf or CONF.CACHED,
    }
end

-- Текст ------------------------------------------------------------------

-- Сколько предметов лагеря закрывают профессии аккаунта. Это тот вывод, который
-- человек сам не сделает: он смотрит в свои профессии, а считать надо по обоим
-- персонажам, потому что добычные профессии тоже дают предмет.
function Camp:CoverText(plan)
    if type(plan) ~= "table" then return nil end
    local covered = tonumber(plan.covered) or 0
    local total = tonumber(plan.total) or 0
    if total <= 0 then return nil end
    return "Ваши профессии закрывают " .. covered .. " из " .. total
        .. " предметов первого тира."
end

-- ОГРАНИЧЕНИЕ, КОТОРОЕ НЕЛЬЗЯ ПРЯТАТЬ. Короткая форма - на карточку, в строку
-- «что делать»: она одна и она видна. Полная - под курсор.
function Camp:LimitShort()
    return "Что в лагере уже стоит, игра мне не говорит — проверьте у костра."
end

function Camp:LimitText()
    return "Про лагерь в клиенте нет ни одной функции: что уже поставлено, идёт"
        .. " ли откат и сколько места у костра осталось, аддону не сообщают."
        .. " Поэтому советую по профессиям, сумкам и ценам, а не по вашему"
        .. " лагерю. Складывается ли бонус лагеря с тем, что персонаж даёт себе"
        .. " сам, в моих данных не написано — не проверял и утверждать не буду."
end

-- Откуда числа. Едет в подсказку, не на карточку: в строке «почему» это сто
-- символов на месте самого совета (та же причина, что у Favor:CaveatText).
function Camp:SourceText(plan)
    local data = ns.CampData
    local src = (data and data.PROVENANCE and data.PROVENANCE.skills) or "базы на диске"
    local text = "Откуда числа: " .. tostring(src)
    if plan and (tonumber(plan.disputed) or 0) > 0 then
        text = text .. ". Сейчас спорных порогов: " .. plan.disputed
            .. " — по ним беру бо́льшее число"
    end
    return U.endSentence(text)
end

return Camp
