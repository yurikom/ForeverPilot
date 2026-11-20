-- ForeverPilot / Logic/Appearance.lua
--
-- ОБЛИК ВЕЩИ: ЕДИНСТВЕННАЯ ОШИБКА ЭТОГО АДДОНА, КОТОРУЮ НЕЛЬЗЯ ОТМЕНИТЬ.
--
-- Все остальные советы можно не выполнять или переделать: не покупать, не
-- крафтить, перезачаровать. А непривязанная вещь необычного качества и выше,
-- которую продали торговцу, выставили на аукцион, отправили почтой или
-- распылили, из коллекции облика пропадает НАВСЕГДА - второй такой у игрока не
-- будет. При этом аддон прямо сейчас советует и продавать, и распылять, и
-- пересылать вещи другому персонажу.
--
-- Поэтому вопрос «а облик с неё уже собран?» задаётся ДО совета, и ответ на
-- него собран в одном месте: иначе четыре ветки ответили бы на него
-- по-разному.
--
-- ЧТО ИЗВЕСТНО ПРО ОБЛИК В FOREVER, И ОТКУДА:
--
--   * трансмог здесь есть, и это подтверждают два независимых источника;
--   * серое и белое учится по подбору - значит продажа хлама облик не теряет;
--   * привязанное к персонажу необычное и выше из подземелья учится всем, кто
--     имел право на добычу, - значит привязанная вещь уже «ваша»;
--   * награда за задание даёт облик за ВСЕ варианты, а не только за выбранный.
--
-- ЧЕГО ЗДЕСЬ СОЗНАТЕЛЬНО НЕТ:
--
--   * правила «продал торговцу - облик всё равно выучился». Такое говорят, но
--     не подтверждено, а похоже на ошибку. Правило, по которому аддон МОЛЧИТ,
--     обязано быть доказанным: ошибись оно - и игрок теряет облик, прочитав у
--     нас «всё в порядке»;
--   * правила по уровню персонажа. Уровневое ограничение трансмога здесь ведёт
--     себя несвязно: по рассказам игроков на 41 работает, на 40 работает, на 37
--     нет, на 33 нет, на 32 работает, на 26 нет, на 21 нет, на 17 работает. Из
--     такого ряда правило не выводится, а выдуманное было бы хуже его
--     отсутствия: оно молчало бы ровно там, где облик теряется.
--
-- АДДОН НИЧЕГО НЕ ЗАПРЕЩАЕТ. Продать зелёнку ради денег - нормальное решение, и
-- принимает его игрок. Дело этого файла одно: чтобы он принимал его ЗНАЯ.
local ADDON, ns = ...

local U = ns.Util
local Api = ns.Api
local CONF = ns.CONF

local AP = {}
ns.Appearance = AP

-- Качество, начиная с которого облик теряется. Серое и белое учится по
-- подбору, и к нему это не относится вовсе.
AP.MIN_QUALITY = 2

-- У чего облик бывает: оружие (2) и доспехи (4). Всё остальное - расходники,
-- материалы, патроны, задания - облика не имеет, и спрашивать про него клиента
-- незачем. Та же пара чисел, по той же причине, стоит в Logic/Disenchant.lua.
AP.CLASSES = { [2] = true, [4] = true }

-- СОСТОЯНИЯ. ПЕРЕЧЕНЬ ЗАКРЫТЫЙ: по нему ходят и ветки советов, и самопроверка,
-- и ни одна из них не имеет права придумать своё.
AP.STATE = {
    OFF       = "OFF",        -- трансмога на этом клиенте нет
    LOW       = "LOW",        -- серое или белое: учится по подбору
    NO_LOOK   = "NO_LOOK",    -- у такой вещи облика не бывает
    BOUND     = "BOUND",      -- вещь привязана, облик с неё уже ваш
    COLLECTED = "COLLECTED",  -- облик собран, терять нечего
    LOSES     = "LOSES",      -- НЕ собран, вещь непривязанная: потеряется
    UNKNOWN   = "UNKNOWN",    -- спросить нечем, и это тоже ответ
}

-- ЧТО ИМЕННО СОБИРАЕТСЯ СДЕЛАТЬ ИГРОК. От этого зависит одно слово в тексте, и
-- слово это важное: «распылите» и «отправите почтой» - разные поступки, а
-- последствие у них одно.
AP.DEED = {
    sell       = "продадите на аукционе",
    vendor     = "продадите торговцу",
    mail       = "отправите почтой",
    disenchant = "распылите",
}
AP.DEED_DEFAULT = "расстанетесь с ней"

-- ПРИВЯЗАНА ЛИ ВЕЩЬ ------------------------------------------------------
--
-- Два разных вопроса, и путать их нельзя:
--   `bound`    - привязана ли ИМЕННО ЭТА вещь. Это ответ клиента по ячейке
--                сумки (Api:BagCounts, поле bound) или чужого аддона по сумке
--                другого персонажа. Он и решает.
--   `bindType` - правило привязки у такого рода вещей вообще: 1 - привязывается
--                при подборе, 2 - при надевании. Нужен там, где самой вещи ещё
--                нет: её только собираются скрафтить.
--
-- Возвращает true (привязана или привяжется к вам), false (нет) или nil
-- («клиент не сказал»).
function AP:Bound(item)
    if type(item) ~= "table" then return nil end
    if item.bound ~= nil then return item.bound and true or false end
    local bindType = tonumber(item.bindType)
    -- Привязка при подборе: такая вещь станет вашей, как только появится в
    -- сумках, то есть её облик запишется сам.
    if bindType == 1 then return true end
    if bindType == 2 or bindType == 0 then return false end
    return nil
end

-- ЕСТЬ ЛИ В СУМКАХ НЕПРИВЯЗАННЫЙ ЭКЗЕМПЛЯР ------------------------------
--
-- Один и тот же предмет может лежать в двух ячейках: одна вещь надета и
-- привязана, вторая куплена и нет. Терять облик можно только на второй, поэтому
-- ответ про предмет - это ответ про САМЫЙ ОПАСНЫЙ его экземпляр.
--
-- Считается один раз на проход: ячеек у игрока сотня, а кандидатов на продажу и
-- распыл - до двух с половиной сотен, и спрашивать по каждому заново значило бы
-- обойти сумки двадцать пять тысяч раз.
-- Память держится на самом снимке, а не на поле ВНУТРИ него: снимок читают и
-- обходят другие модули, и подкладывать им своё служебное поле - значит
-- однажды увидеть его в чужом перечислении. Каждое сканирование делает новую
-- таблицу (Scanner:Scan), так что сравнение по тождеству и означает «тот же
-- снимок».
AP.bindingOf = nil
AP.bindingSnap = nil

function AP:BagBinding(snap)
    if type(snap) ~= "table" then return {} end
    if AP.bindingSnap == snap and AP.bindingOf then return AP.bindingOf end
    local out = {}
    for _, slot in ipairs(snap.bagSlots or {}) do
        local id = tonumber(slot.itemID)
        if id then
            if slot.bound == false then
                out[id] = false
            elseif out[id] == nil and slot.bound ~= nil then
                out[id] = slot.bound and true or false
            end
        end
    end
    AP.bindingSnap, AP.bindingOf = snap, out
    return out
end

-- ОДИН ОТВЕТ ПРО ОДНУ ВЕЩЬ ------------------------------------------------
--
-- item - { itemID, link, quality, classID, bound, bindType }. Чего в нём нет,
-- то спрашивается у клиента через уже прочитанные данные предмета (Api:ItemInfo
-- кеширует их, так что это бесплатно).
-- deed - что с вещью собираются сделать: ключ из AP.DEED.
--
-- Возвращает таблицу:
--   state   - из AP.STATE;
--   loses   - потеряется ли облик (true / false / nil, когда неизвестно);
--   known   - знаем ли мы ответ;
--   quiet   - сказать игроку нечего (про эту вещь вопрос не стоит вовсе);
--   conf    - достоверность ответа;
--   short   - одна фраза для строки совета (или nil);
--   detail  - подробность под курсор (или nil).
function AP:Check(item, deed, where)
    if type(item) == "number" or type(item) == "string" then
        item = { itemID = tonumber(item) or nil, link = item }
    end
    if type(item) ~= "table" then
        return AP:Verdict(AP.STATE.UNKNOWN, { quiet = true, why = "no-item" })
    end

    local key = item.link or item.itemID
    local info = key and Api:ItemInfo(key) or nil
    local quality = tonumber(item.quality) or (info and tonumber(info.quality)) or nil
    local classID = tonumber(item.classID) or (info and tonumber(info.classID)) or nil
    local bound = AP:Bound({
        bound = item.bound,
        bindType = item.bindType ~= nil and item.bindType or (info and info.bindType or nil),
    })
    local name = item.name or (info and info.name) or (item.itemID and U.itemFallbackName(item.itemID))

    -- 1. Качества не знаем - значит не знаем ничего: именно качество решает,
    --    стоит ли вопрос вообще. Это не повод пугать игрока, но повод записать,
    --    каких данных не хватило.
    if not quality then
        AP:Note(item, "no-quality", where)
        return AP:Verdict(AP.STATE.UNKNOWN, { quiet = true, why = "no-quality", name = name })
    end

    -- 2. Серое и белое учится по подбору: такую вещь можно продавать без
    --    оглядки, и говорить тут нечего.
    if quality < AP.MIN_QUALITY then
        return AP:Verdict(AP.STATE.LOW, { name = name })
    end

    -- 3. Привязанная вещь уже ваша, и облик с неё уже записан. Это самый
    --    дешёвый ответ: он приходит вместе с ячейкой сумки, без единого
    --    отдельного вызова.
    if bound == true then
        return AP:Verdict(AP.STATE.BOUND, { name = name })
    end

    -- 4. Трансмога на клиенте нет - терять нечего.
    if Api:TransmogEnabled() == false then
        return AP:Verdict(AP.STATE.OFF, { name = name })
    end

    -- 5. Род вещи. Известен и это не оружие и не доспех - облика нет. Не
    --    известен - спрашивать клиента не о чем, но дырка в данных записывается:
    --    так же поступает ветка распыла, и по той же причине (совет на догадке о
    --    том, есть ли у вещи облик, - это не совет).
    if classID == nil then
        AP:Note(item, "no-class", where)
        return AP:Verdict(AP.STATE.UNKNOWN, { quiet = true, why = "no-class", name = name })
    end
    if not AP.CLASSES[classID] then
        return AP:Verdict(AP.STATE.NO_LOOK, { name = name })
    end

    -- 6. ВЕЩЬ ЛЕЖИТ У ДРУГОГО ПЕРСОНАЖА - И ТУТ КЛИЕНТ НЕ ПОМОЩНИК.
    --
    --    Клиент отвечает про коллекцию ТОГО персонажа, которым играют сейчас, а
    --    общая ли коллекция облика на аккаунте в Forever - неизвестно. Значит
    --    ответ «у меня этот облик есть» про чужую вещь ничего не доказывает, и
    --    выдавать его за ответ нельзя.
    if item.mine == false then
        AP:Note(item, "other-character", where)
        return AP:Verdict(AP.STATE.UNKNOWN,
            { name = name, deed = deed, bound = bound, why = "other-character" })
    end

    -- 7. И только теперь - вопрос к клиенту. До сюда доходят лишь
    --    непривязанные оружие и доспехи необычного качества и выше, то есть
    --    ровно те вещи, на которых облик и теряется.
    local collected, why = Api:AppearanceCollected(key)
    if collected == true then
        return AP:Verdict(AP.STATE.COLLECTED, { name = name })
    end
    if collected == false then
        return AP:Verdict(AP.STATE.LOSES,
            { name = name, deed = deed, bound = bound })
    end
    if why == "no-source" then
        -- Клиент ответил, и ответ отрицательный: облика у этой вещи не бывает.
        return AP:Verdict(AP.STATE.NO_LOOK, { name = name })
    end
    AP:Note(item, why or "no-answer", where)
    return AP:Verdict(AP.STATE.UNKNOWN,
        { name = name, deed = deed, bound = bound, why = why or "no-answer" })
end

-- Записать, каких данных не хватило. Это та же книга заказов, по которой аддон
-- докупает себе данные (Core/Diag.lua, Diag:Want), и она же - единственный
-- честный способ узнать офлайн, отвечает ли клиент про облик вообще: в стенде
-- ответа нет ни у кого, а в файле игрока число этих заказов видно.
function AP:Note(item, why, where)
    if not ns.Diag then return end
    local id = item and tonumber(item.itemID) or nil
    if not id then return end
    ns.Diag:Want("appearanceUnknown", id, where or "appearance",
        { reason = why, name = item.name })
end

-- ТЕКСТ ПРИ КАЖДОМ СОСТОЯНИИ. Один словарь на весь аддон: четыре ветки не имеют
-- права рассказывать про облик разными словами.
function AP:Verdict(state, opts)
    opts = opts or {}
    local v = {
        state = state,
        loses = false,
        known = true,
        quiet = opts.quiet and true or false,
        conf = CONF.EXACT,
        name = opts.name,
        why = opts.why,
        -- ПУСТОТА - ИЗ ОБЩЕГО СЛОВАРЯ (ns.VOID), А НЕ СВОЯ.
        --
        -- У отсутствующего ответа про облик те же две причины, что у
        -- отсутствующего числа, и называть их аддон обязан теми же знаками:
        --   UNKNOWN    - ответ бывает, а у меня его нет (клиент не сказал);
        --   IMPOSSIBLE - такого значения не бывает вовсе (у вещи нет облика,
        --                трансмог выключен).
        -- Так знак «?» в одном месте экрана значит то же, что в другом.
        void = nil,
    }
    if state == AP.STATE.LOSES then
        v.loses = true
        v.short = "Облик этой вещи у вас не собран: "
            .. (AP.DEED[opts.deed or ""] or AP.DEED_DEFAULT)
            .. " — и потеряете его навсегда"
        local parts = {}
        parts[#parts + 1] = "Непривязанную вещь необычного качества и выше вы"
            .. " теряете вместе с её обликом навсегда: проданную, отправленную"
            .. " почтой или распылённую вещь в коллекцию облика уже не записать."
        if opts.bound == false then
            parts[#parts + 1] = "Эта вещь не привязана, а облик с неё не собран."
        else
            parts[#parts + 1] = "Облик с неё не собран, а привязана она или нет,"
                .. " клиент мне не сказал."
        end
        parts[#parts + 1] = "Продать вещь ради денег — ваше право: я"
            .. " предупреждаю, а не запрещаю."
        v.detail = table.concat(parts, " ")
    elseif state == AP.STATE.UNKNOWN then
        v.known = false
        v.loses = nil
        v.conf = CONF.UNKNOWN
        v.void = ns.VOID.UNKNOWN
        if not v.quiet then
            v.short = "Собран ли облик этой вещи, я не знаю"
            -- ПОЧЕМУ НЕ ЗНАЮ - ДВЕ РАЗНЫЕ ПРИЧИНЫ, И СОВЕТ ПРИ НИХ РАЗНЫЙ.
            -- Про свою вещь игрок может посмотреть сам; про вещь другого
            -- персонажа его собственное окно облика не ответит, и посылать его
            -- туда значило бы дать бесполезный совет.
            local parts = {}
            if opts.why == "other-character" then
                parts[#parts + 1] = "Вещь лежит у другого персонажа, а клиент"
                    .. " показывает мне коллекцию облика только того, кем играют"
                    .. " сейчас; общая ли она на аккаунте, я не знаю."
                parts[#parts + 1] = "Вещь необычного качества, и если она не"
                    .. " привязана, пересылка может стоить облика тому"
                    .. " персонажу, у которого она лежит."
            else
                parts[#parts + 1] = "Облик вещи мне показывает клиент, и на этот"
                    .. " вопрос он не ответил, так что проверить нечем."
                if opts.bound == false then
                    parts[#parts + 1] = "Вещь необычного качества и не привязана,"
                        .. " а такую вещь можно потерять вместе с обликом"
                        .. " навсегда."
                else
                    parts[#parts + 1] = "Вещь необычного качества, а такую вещь"
                        .. " можно потерять вместе с обликом навсегда."
                end
                parts[#parts + 1] = "Посмотрите сами в окне облика (в Forever это"
                    .. " Shift+P): вернуть облик потом будет нельзя."
            end
            v.detail = table.concat(parts, " ")
        end
    elseif state == AP.STATE.LOW then
        v.detail = "Серое и белое учится по подбору, так что облик с этой вещи"
            .. " у вас уже есть."
    elseif state == AP.STATE.BOUND then
        v.detail = "Вещь привязана к персонажу, значит облик с неё уже ваш."
    elseif state == AP.STATE.COLLECTED then
        v.detail = "Облик этой вещи у вас уже собран — продажа его не тронет."
    elseif state == AP.STATE.NO_LOOK then
        v.quiet = true
        v.void = ns.VOID.IMPOSSIBLE
    elseif state == AP.STATE.OFF then
        v.quiet = true
        v.void = ns.VOID.IMPOSSIBLE
        v.detail = "Трансмог на этом клиенте выключен, терять нечего."
    end
    return v
end

-- ЕСТЬ ЛИ ЧТО СКАЗАТЬ. Карточки спрашивают это, а не сравнивают состояния
-- сами: иначе новое состояние пришлось бы вписывать в каждую ветку.
function AP:Speaks(v)
    return type(v) == "table" and type(v.short) == "string" and v.short ~= ""
end

-- САМОЕ ОПАСНОЕ ИЗ НЕСКОЛЬКИХ. Карточка «продать хлам» говорит сразу про много
-- предметов, а строка у неё одна: называется тот, на котором теряется больше
-- всего, то есть сначала «точно потеряется», потом «не знаю».
function AP:Worst(list)
    local best, unknown, first
    for _, v in ipairs(list or {}) do
        if type(v) == "table" then
            first = first or v
            if v.loses == true then
                best = best or v
            elseif v.known == false and AP:Speaks(v) then
                unknown = unknown or v
            end
        end
    end
    -- Если сказать нечего, возвращается всё равно ОТВЕТ, а не пустота: по нему
    -- самопроверка видит, что вопрос был задан. Карточка без ответа и карточка,
    -- у которой ответ «терять нечего», - это разные вещи.
    return best or unknown or first
end

return AP
