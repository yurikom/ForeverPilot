-- ForeverPilot / Logic/CrossCharacter.lua
--
-- ДВА ПЕРСОНАЖА - ОДИН КОШЕЛЁК И ОДИН СКЛАД.
--
-- У игрока маг-портняжник-зачарователь и чернокнижник. Ситуация, которую аддон
-- до сих пор не видел: материал лежит на чернокнижнике, профессия у мага.
-- Игрок об этом не знает - он смотрит в сумки мага и идёт покупать то, что
-- уже купил вчера другим персонажем.
--
-- Что ветка умеет сказать:
--   1. материал для нужного крафта лежит НЕ ЗДЕСЬ - и у кого именно;
--   2. что магу стоит скрафтить ДЛЯ чернокнижника: у того профессий нет, а
--      сумки и слоты есть;
--   3. сколько золота на всех персонажах вместе - потому что «не хватает 5з»
--      при 1з на альте это другой разговор.
--
-- ОТКУДА ДАННЫЕ: Syndicator, через публичный API (Api:SyndicatorCharacters).
-- Его нет - ветка молчит и говорит, почему. Ничего не перекладывается и не
-- пересылается: аддон не управляет ни почтой, ни банком.
local ADDON, ns = ...

local U = ns.Util
local Api = ns.Api
local CONF = ns.CONF

local CC = {}
ns.CrossCharacter = CC

-- Кто у нас есть ---------------------------------------------------------

-- КТО ИЗ НИХ - ЭТО САМ ИГРОК.
--
-- Самый дорогой вопрос в этом файле, и раньше он отвечался неверно. Сравнение
-- было `name == snap.name`, то есть «Гендольф Серыйй» против «Гендольф»: на
-- Forever у персонажа есть фамилия, клиент отдаёт её отдельным значением, а
-- Syndicator хранит имя целиком. Совпадения не было никогда, и текущий
-- персонаж числился чужим - аддон советовал игроку переслать себе почтой его
-- же ткань и скрафтить вещи для себя самого, сообщая, что профессий у него нет.
--
-- Теперь сравнение идёт по тому, что действительно уникально, и в таком
-- порядке:
--   1. GUID, если чужой аддон его отдаёт, - он уникален по определению;
--   2. полное имя (имя с фамилией), и реалм, когда он известен у обоих;
--   3. имя без фамилии - только если фамилии нет ни у кого. Это и есть старое
--      поведение, оставленное для клиента без фамилий.
function CC:IsCurrent(entry, snap)
    if type(entry) ~= "table" or type(snap) ~= "table" then return false end
    if entry.guid and snap.guid and entry.guid == snap.guid then return true end
    local mine = snap.fullName or snap.name
    if not mine then return false end
    local theirs = entry.name
    if theirs ~= mine then return false end
    -- Имена совпали. Реалм сверяем, только если он известен с ОБЕИХ сторон:
    -- у Syndicator он нормализованный («PvP»), у клиента полный («CAMWOW EU5
    -- Realm 4 PvP»), поэтому сравнение идёт по вхождению, а не по равенству.
    if entry.realm and snap.realm then
        local a, b = U.lower(entry.realm), U.lower(snap.realm)
        if a ~= b and not b:find(a, 1, true) and not a:find(b, 1, true) then
            return false
        end
    end
    return true
end

-- Список персонажей с золотом и сумками, кроме текущего.
--   { { name, realm, money, level, classFile, className, items, isCurrent } }
function CC:Characters(snap)
    if not Api:SyndicatorPresent() then return nil, "no-syndicator" end
    local list = Api:SyndicatorCharacters()
    if type(list) ~= "table" then return nil, "no-data" end

    -- Уровень и класс Syndicator не знает, а без них двух «Гендольфов» не
    -- различить. Их знает кеш Mastercraft, и соединяются они по полному имени.
    local known = Api.MastercraftCharacters and Api:MastercraftCharacters() or nil

    local out = {}
    for _, fullName in ipairs(list) do
        local data = Api:SyndicatorCharacter(fullName)
        if type(data) == "table" then
            local details = data.details or {}
            local name = details.character or fullName
            local extra = known and known[name] or nil
            local entry = {
                fullName = fullName,
                name = name,
                realm = details.realm,
                -- Код класса строкой, если чужой аддон его отдаёт: в живом
                -- файле Syndicator пишет и номер (class = 9), и код
                -- (className = "WARLOCK"), а читался только номер - и уезжал
                -- в текст карточки как «(9)».
                classFile = details.className or (extra and extra.classFile) or nil,
                className = details.class,
                level = extra and extra.level or nil,
                localizedClass = extra and extra.className or nil,
                guid = extra and extra.guid or nil,
                money = tonumber(data.money) or nil,
                items = {},
            }
            entry.isCurrent = CC:IsCurrent(entry, snap)
            -- ПРОФЕССИИ АЛЬТА - ИЗ СВОЕГО РЕЕСТРА, А НЕ ИЗ ДОГАДКИ.
            --
            -- Syndicator профессий не хранит: в живом файле у персонажа есть
            -- bags, bank, equipped, money - и ни слова про навыки. Поэтому
            -- ветка писала «у него профессий нет», и это было не знание, а его
            -- отсутствие, выданное за знание. Пока у чернокнижника и правда не
            -- было профессий, фраза случайно совпадала с правдой; теперь у него
            -- алхимия, инженерное дело и кулинария.
            --
            -- Реестр (Logic/Roster.lua) помнит то, что аддон видел сам, пока
            -- этим персонажем играли. Нет записи - профессии остаются nil, то
            -- есть «не знаю», и это НЕ пустой список: пустой список - это
            -- утверждение «профессий нет».
            if ns.Roster then
                local profs, conf, age, source = ns.Roster:Professions(entry.fullName)
                if not profs then
                    -- Полное имя из чужого аддона приходит с реалмом
                    -- («Гендольф Белыйй-PvP»), а реестр ведётся по имени без
                    -- него. Пробуем и так.
                    profs, conf, age, source = ns.Roster:Professions(name)
                end
                entry.professions = profs
                entry.professionsConf = conf
                entry.professionsAge = age
                -- ИСТОЧНИК ЕДЕТ ВМЕСТЕ С ДАННЫМИ, и это не формальность: своё
                -- наблюдение и чужой кеш Mastercraft - разные по надёжности
                -- вещи, и у чужого нет ни возраста, ни русских имён. Без этого
                -- поля текст карточки выдавал чужое за своё.
                entry.professionsSource = source
            end
            -- Сумки и банк: обе коллекции в одном формате у Syndicator.
            --
            -- ПРИВЯЗАННОСТЬ ЕДЕТ ВМЕСТЕ С КОЛИЧЕСТВОМ, и это не лишнее поле.
            -- Совет «перешлите почтой» про непривязанную зелёнку стоит облика, а
            -- узнать, привязана ли вещь у другого персонажа, больше негде:
            -- клиент про чужие сумки не отвечает вовсе. Syndicator пишет isBound
            -- по каждой ячейке - в живом файле игрока оно стоит у всех 144
            -- ячеек. Если хоть один экземпляр не привязан, опасен именно он.
            entry.unbound = {}
            for _, collection in ipairs({ data.bags, data.bank }) do
                for _, container in ipairs(collection or {}) do
                    for _, slot in ipairs(container or {}) do
                        local id = slot and tonumber(slot.itemID)
                        if id then
                            entry.items[id] = (entry.items[id] or 0)
                                + (tonumber(slot.itemCount) or 1)
                            if slot.isBound == false then entry.unbound[id] = true end
                        end
                    end
                end
            end
            out[#out + 1] = entry
        end
    end
    table.sort(out, function(a, b) return tostring(a.name) < tostring(b.name) end)
    return out
end

-- ПОДПИСЬ ПЕРСОНАЖА: ИМЯ, УРОВЕНЬ, КЛАСС ---------------------------------
--
-- У игрока ДВА персонажа по имени «Гендольф», и различить их по имени нельзя.
-- Поэтому подпись несёт то, что их различает: полное имя (с фамилией), уровень
-- и класс словом. Раньше в текст уезжал НОМЕР класса из Syndicator - карточка
-- читалась как «у «Гендольф Белыйй» (9) профессий нет», и «(9)» выглядело как
-- уровень.
--
-- Чего не знаем, того не пишем: нет уровня - нет и уровня в подписи, а не ноль.
function CC:Label(entry)
    if type(entry) ~= "table" then return nil end
    local name = entry.name or entry.fullName
    if not name then return nil end
    local bits = {}
    if entry.level then bits[#bits + 1] = entry.level .. " ур." end
    local cls = entry.localizedClass or CC:ClassName(entry)
    if cls then bits[#bits + 1] = cls end
    if entry.realm and not entry.level and not cls then
        bits[#bits + 1] = tostring(entry.realm)
    end
    if #bits == 0 then return name end
    return name .. ", " .. table.concat(bits, ", ")
end

-- Класс СЛОВОМ. Локализованное имя спрашивается у клиента по тому же номеру,
-- который отдал чужой аддон; номер в текст не попадает никогда.
function CC:ClassName(entry)
    if type(entry) ~= "table" then return nil end
    if entry.localizedClass then return entry.localizedClass end
    local classID = tonumber(entry.className)
    if classID then
        local fn = _G.GetClassInfo
            or (_G.C_CreatureInfo and _G.C_CreatureInfo.GetClassInfo)
        if type(fn) == "function" then
            local ok, a = pcall(fn, classID)
            if ok then
                if type(a) == "table" and a.className then return a.className end
                if type(a) == "string" then return a end
            end
        end
        -- Номер есть, слова нет: тогда ничего. Печатать номер нельзя - его
        -- читают как уровень.
        return nil
    end
    if type(entry.className) == "string" and entry.className ~= "" then
        local localized = _G.LOCALIZED_CLASS_NAMES_MALE
        local file = entry.classFile or entry.className:upper()
        if type(localized) == "table" and localized[file] then return localized[file] end
        return nil
    end
    return nil
end

-- ЧТО МЫ ЗНАЕМ О ЕГО ПРОФЕССИЯХ ------------------------------------------
--
-- Три разных ответа, и до реестра все три выглядели на экране одним: «у него
-- профессий нет».
--   число   - запись есть, профессии перечислены;
--   0       - запись есть, и профессий действительно ни одной. Это утверждение,
--             и его теперь можно делать: клиент отдаёт список профессий сразу,
--             без открывания окон, так что пустой список при точной
--             достоверности - правда, а не недосмотр;
--   nil     - записи нет. Этим персонажем при установленном аддоне не играли, и
--             сказать про его профессии нечего.
function CC:ProfessionCount(entry)
    if type(entry) ~= "table" then return nil end
    if type(entry.professions) ~= "table" then return nil end
    return #entry.professions
end

-- То же словами, для карточки. Возраст записи называется: персонаж, которым не
-- играли месяц, мог за этот месяц выучить что угодно, и «вот что было тогда» -
-- это не то же самое, что «вот что есть».
function CC:ProfessionText(entry)
    local n = CC:ProfessionCount(entry)
    if n == nil then
        return "какие у него профессии, я не знаю: этим персонажем при мне не"
            .. " играли, а чужие аддоны профессий не хранят"
    end
    if n == 0 then
        return "профессий у него нет"
    end
    local bits = {}
    for _, prof in ipairs(entry.professions) do
        -- ИМЯ ПО-РУССКИ. Чужой кеш пишет «Alchemy», клиент у игрока ruRU, и на
        -- экране стояло «его профессии: Alchemy 150». Перевод - через
        -- Roster:DisplayName, то есть через единственный словарь NAME_BRIDGE.
        local line = tostring(ns.Roster and ns.Roster:DisplayName(prof.name)
            or prof.name)
        if prof.skill then
            line = line .. " " .. prof.skill
            if prof.max and prof.max > 0 then line = line .. "/" .. prof.max end
        end
        bits[#bits + 1] = line
    end
    local text = "его профессии: " .. table.concat(bits, ", ")
    -- ОТКУДА ЭТО ИЗВЕСТНО. Своё наблюдение и чужой кеш - разные по надёжности
    -- вещи, и до этой пометки чужое выдавалось за своё: «его профессии:
    -- Alchemy 150» читалось как «я это видел», хотя аддон этим персонажем ни
    -- разу не играл и прочитал запись в кеше Mastercraft.
    if entry.professionsSource == "foreign" then
        text = text .. " (" .. ns.FOREIGN_BOOK.short .. ": сам я этим"
            .. " персонажем при вас не играл, так что когда это записали —"
            .. " не знаю)"
        return text
    end
    local age = tonumber(entry.professionsAge)
    if age and age > (ns.PRICE_AGE_SAY_SECONDS or 86400) then
        text = text .. " (это я видел " .. (U.ageText(age) or "давно")
            .. ", с тех пор он мог выучить что угодно)"
    end
    return text
end

-- У КОГО ЕСТЬ НУЖНАЯ ПРОФЕССИЯ.
--
-- Новый вопрос, и осмысленным он стал ровно сейчас: пока профессии были у
-- одного персонажа, спрашивать было нечего. Теперь у мага портняжка с чарами, у
-- чернокнижника алхимия с инженерным делом - и «это умеет сделать другой» стало
-- таким же настоящим ответом, как «это лежит у другого в сумках».
--
-- Текущий персонаж из ответа исключается: совет «попроси себя» бессмысленен.
--
-- ТРИ ОТВЕТА, А НЕ ДВА. Пустой список здесь значил сразу и «ни у кого этой
-- профессии нет», и «кроме вас я никого не видел» - то есть утверждение и
-- незнание выглядели одинаково. Теперь:
--   список       - вот у кого эта профессия есть (может быть пустым);
--   пустой список - УТВЕРЖДЕНИЕ: других персонажей я знаю, и ни у одного её нет;
--   nil + why     - сказать нечего: реестра нет, имя пустое, или кроме текущего
--                   персонажа в реестре никого.
function CC:WhoCanMake(professionName, snap)
    if not ns.Roster then return nil, "no-roster" end
    if type(professionName) ~= "string" or professionName == "" then
        return nil, "no-profession"
    end
    snap = snap or (ns.CharacterScanner and ns.CharacterScanner:Get()) or nil
    local me = snap and (snap.fullName or snap.name) or nil

    -- Знаем ли мы вообще кого-то, кроме текущего персонажа. Без этой проверки
    -- «ни у кого нет» утверждалось бы на реестре из одного себя.
    local others = 0
    local mine = me and U.lower(me) or nil
    for name in pairs(ns.Roster:All()) do
        if (not mine) or U.lower(name) ~= mine then others = others + 1 end
    end
    if others == 0 then
        -- Чужой кеш может знать персонажей, которых аддон сам не видел: тогда
        -- сказать всё-таки есть что.
        local Api = ns.Api
        local foreign = (Api and Api.MastercraftCharacters)
            and Api:MastercraftCharacters() or nil
        for full in pairs(foreign or {}) do
            if (not mine) or U.lower(full) ~= mine then others = others + 1 end
        end
    end
    if others == 0 then return nil, "no-other-characters" end

    -- Своё впереди, чужое запасным путём - через тот же индекс, которым
    -- пользуется ветка «между персонажами», чтобы два места не отвечали
    -- по-разному на один вопрос.
    local want = U.lower(professionName)
    local alias = ns.RecipeBook and ns.RecipeBook.NAME_BRIDGE
        and ns.RecipeBook.NAME_BRIDGE[want] or nil
    local out = {}
    for profName, holders in pairs(ns.Roster:ProfessionIndex()) do
        local have = U.lower(profName)
        if have == want or (alias and have == alias) then
            for _, h in ipairs(holders) do
                if (not mine) or U.lower(tostring(h.fullName)) ~= mine then
                    local bits = {}
                    if h.level then bits[#bits + 1] = h.level .. " ур." end
                    if h.className then bits[#bits + 1] = h.className end
                    out[#out + 1] = {
                        fullName = h.fullName, name = h.fullName,
                        label = tostring(h.fullName)
                            .. ((#bits > 0) and (", " .. table.concat(bits, ", ")) or ""),
                        profession = profName,
                        skill = h.skill, max = h.max,
                        level = h.level, className = h.className,
                        source = h.source,
                    }
                end
            end
        end
    end
    table.sort(out, function(a, b)
        local sa, sb = a.skill or -1, b.skill or -1
        if sa ~= sb then return sa > sb end
        return tostring(a.fullName) < tostring(b.fullName)
    end)
    return out
end

-- Суммарное золото -------------------------------------------------------
--
-- Три числа, и все три нужны: у текущего персонажа, у остальных, и всего.
-- «Не хватает 5 золотых» при 1 золотом на альте - это другой разговор, но
-- делать вид, что деньги альта лежат в кошельке, нельзя: их надо переслать.
function CC:Gold(snap)
    local chars, why = CC:Characters(snap)
    if not chars then return nil, why end
    local here, elsewhere, known, unknown = 0, 0, 0, 0
    local others = {}
    for _, c in ipairs(chars) do
        if c.money then
            known = known + 1
            if c.isCurrent then
                here = here + c.money
            else
                elsewhere = elsewhere + c.money
                others[#others + 1] = { name = c.name, money = c.money }
            end
        else
            unknown = unknown + 1
        end
    end
    -- Если текущего персонажа Syndicator не знает, берём его деньги у клиента -
    -- они точнее любого кеша.
    if here == 0 and snap and snap.money then here = snap.money end
    table.sort(others, function(a, b) return (a.money or 0) > (b.money or 0) end)
    return {
        here = here, elsewhere = elsewhere, total = here + elsewhere,
        others = others, charactersKnown = known, charactersUnknown = unknown,
        conf = (unknown > 0) and CONF.ESTIMATE or CONF.CACHED,
    }
end

-- Материал лежит не здесь ------------------------------------------------

-- По списку нужных материалов (itemID -> нужное количество) - у кого они есть.
--   { { itemID, name, need, hereHave, elsewhere = { { name, qty } }, total } }
function CC:MaterialsElsewhere(needed, snap)
    local chars, why = CC:Characters(snap)
    if not chars then return nil, why end
    local out = {}
    for itemID, need in pairs(needed or {}) do
        itemID = tonumber(itemID)
        if itemID then
            local hereHave = (snap and (snap.bags or {})[itemID] or 0)
                + (snap and (snap.bank or {})[itemID] or 0)
            local elsewhere, total, anyUnbound = {}, 0, false
            for _, c in ipairs(chars) do
                if not c.isCurrent then
                    local qty = c.items[itemID]
                    if qty and qty > 0 then
                        if c.unbound and c.unbound[itemID] then anyUnbound = true end
                        elsewhere[#elsewhere + 1] = {
                            name = c.name, qty = qty,
                            -- Подпись с уровнем и классом едет вместе с
                            -- количеством: иначе «у Гендольф» не отвечает на
                            -- вопрос «у которого из двух».
                            label = CC:Label(c),
                        }
                        total = total + qty
                    end
                end
            end
            -- Говорить стоит только если здесь НЕ ХВАТАЕТ, а там есть.
            if total > 0 and hereHave < need then
                local info = Api:ItemInfo(itemID)
                table.sort(elsewhere, function(a, b) return a.qty > b.qty end)
                out[#out + 1] = {
                    itemID = itemID,
                    name = (info and info.name) or U.itemFallbackName(itemID),
                    need = need, hereHave = hereHave,
                    elsewhere = elsewhere, total = total,
                    covers = (hereHave + total) >= need,
                    -- ЧТО СТАНЕТ С ОБЛИКОМ, ЕСЛИ ЭТО ПЕРЕСЛАТЬ. Для ткани и руды
                    -- ответ пустой (облика у них не бывает), и это нормальный
                    -- случай - здесь он и будет почти всегда. А вот зелёная
                    -- вещь, отправленная почтой, стоит облика, и советует её
                    -- переслать именно эта ветка.
                    looks = ns.Appearance and ns.Appearance:Check({
                        itemID = itemID,
                        link = info and info.link or nil,
                        name = info and info.name or nil,
                        bound = anyUnbound and false or nil,
                        mine = false,
                    }, "mail", "cross-materials") or nil,
                }
            end
        end
    end
    table.sort(out, function(a, b)
        if a.total ~= b.total then return a.total > b.total end
        return a.itemID < b.itemID
    end)
    return out
end

-- Что скрафтить для другого персонажа -----------------------------------
--
-- Вещь, которую этот персонаж умеет сделать и которая подходит классу альта, -
-- это бесплатное улучшение альта. Повод у совета один: слоты у альта есть, а
-- этого рецепта у него нет.
--
-- ПРИЧИНА БОЛЬШЕ НЕ «У НЕГО ПРОФЕССИЙ НЕТ». Так было написано, пока их у
-- чернокнижника действительно не было, и проверить фразу было нечем: чужие
-- аддоны профессий не хранят. Теперь у него алхимия, инженерное дело и
-- кулинария, а реестр (Logic/Roster.lua) об этом знает - и причина у совета
-- стала точной: не «у него ничего нет», а «этой профессии у него нет».
-- Карточка несёт с собой всё, что реестр сказал (entry.professions), чтобы
-- текст не пересобирал это заново и не разошёлся со словами CC:ProfessionText.
--
-- ЧЕГО ЗДЕСЬ НЕ БУДЕТ: оценки «насколько лучше». Характеристики альта мы не
-- знаем - Syndicator отдаёт его сумки, а не веса характеристик, - и считать
-- прирост было бы выдумкой. Поэтому ветка говорит «подойдёт по классу и
-- уровню», а не «+15 ед. пользы».
function CC:CraftablesForOthers(snap)
    local chars, why = CC:Characters(snap)
    if not chars then return nil, why end
    local out = {}

    for _, c in ipairs(chars) do
        if not c.isCurrent and (c.classFile or c.className) then
            -- Код класса, если чужой аддон отдал его строкой, иначе перевод
            -- номера клиентом. Строка надёжнее: номер приходится переводить.
            local classFile = c.classFile
            if not (classFile and ns.GearAdvisor
                    and ns.GearAdvisor.ARMOR_BY_CLASS[classFile]) then
                classFile = CC:ClassFileOf(c.className)
            end
            local armor = classFile and ns.GearAdvisor
                and ns.GearAdvisor.ARMOR_BY_CLASS[classFile] or nil
            if armor then
                for _, recipe in ipairs(ns.RecipeBook:Iterate(function(r)
                    return r.learned and r.output
                end)) do
                    local info = Api:ItemInfo(recipe.output)
                    local slot = info and ns.SlotMap:FromEquipLoc(info.equipLoc)
                    if slot and info.classID == ns.GearAdvisor.CLASS_ARMOR
                       and info.subclassID ~= nil and armor[info.subclassID] then
                        out[#out + 1] = {
                            forName = c.name,
                            -- КЛАСС СЛОВОМ, а не номером: «(9)» в тексте
                            -- карточки читалось как уровень.
                            forClass = CC:ClassName(c),
                            forClassFile = classFile,
                            forLabel = CC:Label(c),
                            forLevel = c.level,
                            -- Что реестр знает про ЕГО профессии: число и
                            -- слова едут с находкой, чтобы карточка не
                            -- пересобирала их заново.
                            forProfessions = c.professions,
                            forProfessionCount = CC:ProfessionCount(c),
                            forProfessionText = CC:ProfessionText(c),
                            itemID = recipe.output,
                            name = info.name or U.itemFallbackName(recipe.output),
                            recipeID = recipe.id,
                            slot = slot, slotLabel = ns.SlotMap:Label(slot),
                            reqLevel = info.reqLevel,
                            -- Прирост НЕ считаем: характеристик альта мы не знаем.
                            gainKnown = false,
                            -- Что нужно, чтобы спросить про облик. Сам вопрос -
                            -- ниже, после сортировки: см. там, почему.
                            link = info.link,
                            quality = info.quality,
                            classID = info.classID,
                            bindType = info.bindType,
                        }
                    end
                end
            end
        end
    end
    table.sort(out, function(a, b)
        local ar, br = a.reqLevel or 0, b.reqLevel or 0
        if ar ~= br then return ar > br end
        return a.itemID < b.itemID
    end)

    -- ПРО ОБЛИК СПРАШИВАЕМ ТОЛЬКО ПРО ТУ ВЕЩЬ, КОТОРАЯ ПОПАДЁТ НА КАРТОЧКУ.
    --
    -- Вещь скрафтит ЭТОТ персонаж и отправит почтой - то есть расстанется с ней
    -- именно он, а про свою коллекцию облика клиент отвечает. Вещи ещё нет,
    -- поэтому привязанность берётся из правила привязки: привязка при подборе
    -- значит, что вещь станет вашей и облик запишется сам.
    --
    -- А ВОТ ЦЕНА РАБОТЫ: на настоящих данных этот список - 130 вещей за
    -- пересчёт, а карточка из него одна. Вопрос, заданный внутри обхода, стоил
    -- бы 130 вопросов и до 260 обращений к клиенту за ответы, которые тут же
    -- выбрасываются. Поэтому вопрос один, и про первую вещь после сортировки -
    -- ту самую, которую назовёт карточка.
    if ns.Appearance and out[1] then
        out[1].looks = ns.Appearance:Check({
            itemID = out[1].itemID,
            link = out[1].link,
            name = out[1].name,
            quality = out[1].quality,
            classID = out[1].classID,
            bindType = out[1].bindType,
        }, "mail", "cross-craft")
    end
    return out
end

-- Класс другого персонажа -> код класса ("MAGE", "WARLOCK").
--
-- SYNDICATOR ОТДАЁТ КЛАСС ЧИСЛОМ, А НЕ ИМЕНЕМ. В файле игрока у чернокнижника
-- стоит class = 9, у мага class = 8 - это номера классов, а не названия. Пока
-- мы ждали строку, ветка не умела определить класс ни одного персонажа и
-- молчала про всех. Номер переводится в код КЛИЕНТОМ (GetClassInfo), а не
-- таблицей, вписанной здесь: таблица была бы ещё одним местом, которое может
-- разойтись с игрой.
function CC:ClassFileOf(className)
    local classID = tonumber(className)
    if classID then
        local fn = _G.GetClassInfo
            or (_G.C_CreatureInfo and _G.C_CreatureInfo.GetClassInfo)
        if type(fn) == "function" then
            local ok, a, b = pcall(fn, classID)
            if ok then
                -- GetClassInfo отдаёт (localizedName, classFile, classID);
                -- C_CreatureInfo.GetClassInfo - таблицу { className, classFile }.
                if type(a) == "table" then
                    if ns.Diag then ns.Diag:Call("C_CreatureInfo.GetClassInfo", true) end
                    return a.classFile
                end
                if type(b) == "string" then
                    if ns.Diag then ns.Diag:Call("GetClassInfo", true) end
                    return b
                end
            end
        end
        if ns.Diag then
            ns.Diag:Call("GetClassInfo", false,
                "класс " .. classID .. " в код не перевести — клиент не отдал функцию")
        end
        return nil
    end
    if type(className) ~= "string" then return nil end
    local localized = _G.LOCALIZED_CLASS_NAMES_MALE
    if type(localized) == "table" then
        for file, name in pairs(localized) do
            if name == className then return file end
        end
    end
    local female = _G.LOCALIZED_CLASS_NAMES_FEMALE
    if type(female) == "table" then
        for file, name in pairs(female) do
            if name == className then return file end
        end
    end
    -- Клиент не отдал таблицу имён классов: английское имя всё же может
    -- совпасть с кодом.
    local upper = className:upper():gsub("%s", "")
    if ns.GearAdvisor and ns.GearAdvisor.ARMOR_BY_CLASS[upper] then return upper end
    return nil
end

return CC
