-- ForeverPilot / Tests/test_diag.lua
--
-- The diagnostics module, and every sanity check in it. A diagnostic that lies
-- is worse than none, so each check is given a world where it SHOULD fire and
-- a world where it should NOT.
local H = ...

return function()

local function world(opts)
    opts = opts or {}
    local env = H.load()
    local ns = env.ns
    env.player.level = opts.level or 26
    env.player.classFile = "MAGE"
    env.player.className = "Маг"
    env.player.name = "Гендольф"
    env.spec = "Тайная магия"
    env.money = opts.money or 25081

    H.item(env, 2589, { name = "Льняная ткань", sellPrice = 5 })
    H.item(env, 11137, { name = "Магическая пыль", sellPrice = 120 })
    H.item(env, 100, { name = "Старый капюшон", equipLoc = "INVTYPE_HEAD",
        reqLevel = 20, classID = 4, subclassID = 1, sellPrice = 50 })
    H.item(env, 101, { name = "Новый капюшон", equipLoc = "INVTYPE_HEAD",
        reqLevel = 24, classID = 4, subclassID = 1, sellPrice = 300 })
    H.item(env, 110, { name = "Наручи", equipLoc = "INVTYPE_WRIST",
        reqLevel = 20, classID = 4, subclassID = 1 })
    env.stats[100] = { ITEM_MOD_INTELLECT_SHORT = 3 }
    env.stats[101] = { ITEM_MOD_INTELLECT_SHORT = 14 }
    env.prices[2589] = 50
    env.prices[11137] = 900
    env.prices[101] = 3000
    env.equipped.HEAD = { itemID = 100 }
    env.equipped.WRIST = { itemID = 110 }
    env.bags[2589] = 6

    H.profession(env, "Tailoring", opts.skill or 180, 225, {
        H.recipe { id = 1, name = "Новый капюшон", output = 101, outputQty = 1,
                   reagents = { { itemID = 2589, qty = 6 } }, diff = "optimal",
                   category = "Капюшоны", categoryID = 1 },
    })
    H.profession(env, "Enchanting", 225, 225, {
        H.recipe { id = 2, name = "Чары для браслетов: интеллект III",
                   reagents = { { itemID = 11137, qty = 1 } }, learned = true,
                   category = "Чары для наручей", categoryID = 10, diff = "medium" },
    })
    return env
end

local function suspicions(env)
    local s = env.ns.Diag:Init()
    local byCode = {}
    for _, e in ipairs(s.suspicious) do
        byCode[e.code] = byCode[e.code] or {}
        table.insert(byCode[e.code], e)
    end
    return byCode, s.suspicious
end

local function fired(env, code)
    return (suspicions(env))[code] ~= nil
end

-- Structure --------------------------------------------------------------

H.suite("Диагностика: сессия и привязка к SavedVariables")
do
    local env = H.load()
    local ns = env.ns
    local store = env.G.FOREVERPILOT_DIAG
    H.ok(type(store) == "table", "хранилище создано")
    H.eq(store.schema, ns.Diag.SCHEMA, "схема записана")
    H.eq(#store.sessions, 1, "одна сессия")
    -- The session must be the SAME table, not a copy, or later writes are lost.
    ns.Diag:Log("проверка")
    H.eq(#store.sessions[1].log, 1, "запись в сессию видна в хранилище (не копия)")
end

H.suite("Диагностика: хранится ровно три последние сессии")
do
    local env = H.load()
    local ns = env.ns
    local store = env.G.FOREVERPILOT_DIAG
    for i = 1, 5 do
        ns.Diag.session = nil
        ns.Diag:Bind(store)
        ns.Diag:Log("сессия " .. i)
    end
    H.eq(#store.sessions, ns.Diag.MAX_SESSIONS, "не больше трёх сессий")
    H.eq(store.latest, 3, "указатель на последнюю")
    -- The oldest must have been dropped, not the newest.
    H.eq(store.sessions[3].log[1].text, "сессия 5", "последняя сессия самая новая")
end

H.suite("Диагностика: окружение")
do
    local env = H.load()
    local ns = env.ns
    env.player.level = 26
    env.player.classFile = "MAGE"
    env.player.name = "Гендольф"
    local e = ns.Diag:CaptureEnvironment()
    H.eq(e.addonVersion, ns.VERSION, "версия аддона")
    H.ok(e.character ~= nil, "блок персонажа есть")
    H.eq(e.character.level, 26, "уровень")
    H.eq(e.character.classFile, "MAGE", "класс")
    H.eq(e.character.name, "Гендольф", "имя")
    H.eq(e.locale, "ruRU", "локаль")
    H.eq(e.isForever, true, "тип игры определён")
    H.ok(type(e.addons) == "table", "список внешних аддонов есть")
    H.ok(type(e.reachable) == "table", "и отдельно — достижимость их API")
    H.ok(e.loginAtText ~= nil, "время входа записано")
end

H.suite("Диагностика: feature-detect попадает в файл")
do
    local env = H.load()
    local ns = env.ns
    local s = ns.Diag:Init()
    local found, missing = 0, 0
    for name, exists in pairs(s.detect) do
        if exists then found = found + 1 else missing = missing + 1 end
    end
    H.ok(found + missing > 20, (found + missing) .. " функций проверено")
    -- Names must be real API paths, not our internal short keys.
    H.ok(s.detect["C_Item.GetItemInfo"] ~= nil,
        "записано под настоящим путём API, а не внутренним ключом")
    H.ok(s.detect["[global] WOW_PROJECT_CAMELOT"] ~= nil,
        "глобалы тоже проверяются")

    -- A deliberately absent function must be recorded as false, not omitted.
    ns.Diag:Detect("ЗаведомоНетТакойФункции", false)
    H.eq(s.detect["ЗаведомоНетТакойФункции"], false, "отсутствие пишется как false")
end

H.suite("Диагностика: результат вызова, а не только наличие функции")
do
    local env = H.load()
    local ns = env.ns
    ns.Diag:Call("Тест.Функция", true)
    ns.Diag:Call("Тест.Функция", false, "вернула пусто")
    ns.Diag:Call("Тест.Функция", nil, "вызов упал")
    local e = ns.Diag:Init().calls["Тест.Функция"]
    H.eq(e.tries, 3, "три попытки")
    H.eq(e.gotData, 1, "одна с данными")
    H.eq(e.empty, 1, "одна пустая")
    H.eq(e.failed, 1, "одна провалилась")
    H.eq(e.note, "вызов упал", "последняя пометка сохранена")
end

H.suite("Диагностика: ноль на выходе всегда с причиной")
do
    local env = H.load()
    local ns = env.ns
    -- A module reporting zero without a reason is itself a defect, and the
    -- module records that fact about itself rather than hiding it.
    ns.Diag:Module("безПричины", { ["in"] = 5, out = 0 })
    local m = ns.Diag:Init().modules["безПричины"]
    H.ok(m.reason ~= nil, "причина подставлена автоматически")
    H.ok(m.reason:find("дефект"), "и помечена как дефект диагностики: " .. m.reason)

    ns.Diag:Module("сПричиной", { ["in"] = 5, out = 0, reason = "нечего выдавать" })
    H.eq(ns.Diag:Init().modules["сПричиной"].reason, "нечего выдавать",
        "своя причина не перезаписывается")

    -- А вот наоборот: модуль выдал ноль с причиной, следующий пересчёт выдал
    -- результат - причина обязана уйти. Модули сливаются по ключам, а nil в
    -- pairs не попадает, поэтому старая причина переживала пересчёт и
    -- /fp diag продолжал показывать «ни одна ветка советов ничего не выдала»
    -- при непустом списке. Именно по этой строке и ищут причину нуля.
    ns.Diag:Module("ожил", { ["in"] = 5, out = 0, reason = "пока нечего" })
    H.eq(ns.Diag:Init().modules["ожил"].reason, "пока нечего", "причина записана")
    ns.Diag:Module("ожил", { ["in"] = 5, out = 3 })
    H.eq(ns.Diag:Init().modules["ожил"].reason, nil,
        "после непустого прогона причина снята")
    H.eq(ns.Diag:Init().modules["ожил"].out, 3, "а результат остался")

    -- И если новая причина пришла вместе с результатом - её не выбрасываем.
    ns.Diag:Module("ожил", { ["in"] = 5, out = 3, reason = "предупреждение" })
    H.eq(ns.Diag:Init().modules["ожил"].reason, "предупреждение",
        "явную причину при непустом выходе сохраняем")
end

H.suite("Диагностика: ошибки с traceback и свёрткой повторов")
do
    local env = H.load()
    local ns = env.ns
    -- One failing function, called twice from the same place - which is what a
    -- real bug looks like, firing again on every recompute.
    local boom = function() error("нарочная ошибка") end

    local ok = ns.Diag:Guard("ТестТочка", boom)
    H.eq(ok, false, "Guard вернул false")
    local s = ns.Diag:Init()
    H.eq(#s.errors, 1, "ошибка записана")
    H.eq(s.errors[1].where, "ТестТочка", "место записано")
    H.ok(s.errors[1].message:find("нарочная"), "сообщение записано")
    H.ok(s.errors[1].traceback ~= nil, "traceback записан")
    H.eq(s.errors[1].count, 1, "счётчик 1")

    -- The same error again must bump the count, not add a second entry: it
    -- repeats every recompute and would otherwise flood the file.
    ns.Diag:Guard("ТестТочка", boom)
    H.eq(#s.errors, 1, "по-прежнему одна запись")
    H.eq(s.errors[1].count, 2, "счётчик 2")
    H.ok(s.errors[1].lastAt ~= nil, "время последнего повтора записано")

    -- A different error is a different entry.
    ns.Diag:Guard("ДругаяТочка", function() error("другая") end)
    H.eq(#s.errors, 2, "другая ошибка — другая запись")

    -- The same message from a different place is also a separate entry: the
    -- place is what tells me which of our modules broke.
    ns.Diag:Guard("ТретьяТочка", boom)
    H.eq(#s.errors, 3, "то же сообщение из другого места — отдельная запись")
end

H.suite("Диагностика: Guard пропускает успешный результат")
do
    local env = H.load()
    local ns = env.ns
    local ok, result = ns.Diag:Guard("ok", function(a, b) return a + b end, 2, 3)
    H.eq(ok, true, "успех")
    H.eq(result, 5, "аргументы и возврат проходят через Guard")
    H.eq(#ns.Diag:Init().errors, 0, "ошибок нет")
end

H.suite("Диагностика: глобальный обработчик ошибок не трогаем")
do
    -- Hooking seterrorhandler would break other addons' error reporting, so it
    -- must not appear anywhere in the source. This is a hard rule, checked the
    -- same way as the automation ban.
    local hits = {}
    for _, rel in ipairs(H.LOGIC_FILES) do
        local fh = io.open(H.ROOT .. "/" .. rel, "r")
        if fh then
            local src = fh:read("*a"); fh:close()
            local code = {}
            for line in (src .. "\n"):gmatch("([^\n]*)\n") do
                if not line:match("^%s*%-%-") then code[#code + 1] = line end
            end
            if table.concat(code, "\n"):find("seterrorhandler") then
                hits[#hits + 1] = rel
            end
        end
    end
    for _, rel in ipairs({ "UI/Widgets.lua", "UI/Card.lua", "UI/StepPanel.lua",
                           "UI/Arrow.lua", "UI/MainFrame.lua", "Main.lua",
                           "Core/Diag.lua" }) do
        local fh = io.open(H.ROOT .. "/" .. rel, "r")
        if fh then
            local src = fh:read("*a"); fh:close()
            local code = {}
            for line in (src .. "\n"):gmatch("([^\n]*)\n") do
                if not line:match("^%s*%-%-") then code[#code + 1] = line end
            end
            if table.concat(code, "\n"):find("seterrorhandler") then
                hits[#hits + 1] = rel
            end
        end
    end
    H.eq(#hits, 0, "seterrorhandler не вызывается нигде"
        .. (#hits > 0 and (": " .. table.concat(hits, ", ")) or ""))
end

H.suite("Диагностика: тайминги")
do
    local env = H.load()
    local ns = env.ns
    local t = ns.Diag:TimerStart()
    local ms = ns.Diag:TimerStop(t, "тест")
    local p = ns.Diag:Init().perf
    H.eq(p.recomputes, 1, "пересчёт посчитан")
    H.ok(ms >= 0, "время неотрицательное")
    H.ok(p.peakMs >= 0, "пик записан")
    H.eq(#p.samples, 1, "образец сохранён")

    -- Peak must track the maximum, not the last.
    ns.Diag:TimerStop(ns.Diag:TimerStart() - 500, "большой")
    H.ok(p.peakMs >= 500, "пик обновился на большом значении: " .. p.peakMs)
    ns.Diag:TimerStop(ns.Diag:TimerStart(), "маленький")
    H.ok(p.peakMs >= 500, "и не сбросился маленьким")
    H.eq(p.recomputes, 3, "счётчик пересчётов растёт")
    H.ok(p.avgMs ~= nil, "среднее считается")
end

H.suite("Диагностика: списки имеют предел")
do
    local env = H.load()
    local ns = env.ns
    for i = 1, 200 do ns.Diag:Log("строка " .. i) end
    for i = 1, 200 do ns.Diag:Suspect("код" .. i, "странность " .. i) end
    for i = 1, 200 do ns.Diag:TimerStop(ns.Diag:TimerStart(), "t" .. i) end
    ns.Diag:Trim()
    local s = ns.Diag:Init()
    H.ok(#s.log <= ns.Diag.CAP.log, "журнал обрезан до " .. #s.log)
    H.ok(#s.suspicious <= ns.Diag.CAP.suspicious, "странности обрезаны до " .. #s.suspicious)
    H.ok(#s.perf.samples <= ns.Diag.CAP.perf, "образцы обрезаны до " .. #s.perf.samples)
    -- The newest entries must survive, not the oldest.
    H.eq(s.log[#s.log].text, "строка 200", "последняя запись сохранена")
    H.ok(s.sizeEstimate ~= nil, "оценка размера записана")
end

H.suite("Диагностика: повторная странность сворачивается в счётчик")
do
    local env = H.load()
    local ns = env.ns
    for _ = 1, 5 do ns.Diag:Suspect("повтор", "одно и то же") end
    local s = ns.Diag:Init()
    H.eq(#s.suspicious, 1, "одна запись")
    H.eq(s.suspicious[1].count, 5, "счётчик 5")
end

H.suite("Диагностика: сводка для чата")
do
    local env = world()
    local ns = env.ns
    H.build(env)
    local lines = ns.Diag:Summary()
    H.ok(#lines > 3, #lines .. " строк в сводке")
    local joined = table.concat(lines, "\n")
    H.ok(joined:find("диагностика"), "есть вердикт")
    H.ok(joined:find("ошибок"), "есть счёт ошибок")
    H.ok(joined:find("пересчёт"), "есть тайминги")
    H.ok(joined:find("ForeverPilot.lua", 1, true) and joined:find("SavedVariables", 1, true),
        "сказано, где лежит файл")
    H.ok(joined:find("FOREVERPILOT_DIAG", 1, true) == nil,
        "и без имени переменной: игроку оно ничего не говорит")
    local ok = pcall(function() ns.Diag:Print() end)
    H.ok(ok, "Print() не падает")
    local ok2 = pcall(function() ns.Diag:PrintFull() end)
    H.ok(ok2, "PrintFull() не падает")
end

H.suite("Диагностика: вердикт зависит от находок")
do
    local env = world()
    local ns = env.ns
    H.build(env)
    ns.Diag:ClearSuspicions()
    ns.Diag:Init().errors = {}
    H.ok(table.concat(ns.Diag:Summary(), "\n"):find("в порядке"),
        "чисто - вердикт «всё в порядке»")

    ns.Diag:Suspect("тест", "странность")
    H.ok(table.concat(ns.Diag:Summary(), "\n"):find("странности"),
        "со странностью - вердикт меняется")

    ns.Diag:Error("где-то", "беда")
    H.ok(table.concat(ns.Diag:Summary(), "\n"):find("есть ошибки"),
        "с ошибкой - вердикт «есть ошибки»")
end

-- Module metrics ---------------------------------------------------------

H.suite("Диагностика: метрики модулей заполняются при сборке")
do
    local env = world()
    local ns = env.ns
    H.build(env)
    local m = ns.Diag:Init().modules
    for _, name in ipairs({ "characterScanner", "bags", "bank", "equipment",
                            "recipeBook", "enchantSlots", "prices", "places",
                            "actionEngine", "gearAdvisor", "sanityChecks" }) do
        H.ok(m[name] ~= nil, "есть метрика модуля " .. name)
        if m[name] then
            H.ok(m[name]["in"] ~= nil and m[name].out ~= nil,
                "   у " .. name .. " записаны вход и выход")
        end
    end
    H.ok((m.recipeBook.learned or 0) > 0, "рецепты посчитаны")
    H.ok((m.actionEngine.out or 0) > 0, "карточки посчитаны")
    H.ok(type(m.actionEngine.byKind) == "table", "карточки разбиты по типам")
end

H.suite("Диагностика: ноль с причиной на реальном сценарии")
do
    local env = world()
    local ns = env.ns
    -- Nobody has opened a profession window: the zero must carry the reason.
    ns.RecipeBook.byProfession = {}
    ns.RecipeBook:Reindex()
    H.build(env)
    local m = ns.Diag:Init().modules.recipeBook
    H.eq(m.out, 0, "рецептов ноль")
    H.ok(m.reason and m.reason:find("окно профессии"),
        "и причина названа: " .. tostring(m.reason))

    local bank = ns.Diag:Init().modules.bank
    H.eq(bank.out, 0, "банк ноль")
    H.ok(bank.reason and bank.reason:find("банк"), "с причиной: " .. tostring(bank.reason))
end

H.suite("Диагностика: карточки записаны целиком")
do
    local env = world()
    local ns = env.ns
    local cards = H.build(env)
    local s = ns.Diag:Init()
    H.ok(#s.cards > 0, #s.cards .. " карточек записано")
    H.ok(#s.cards <= ns.Diag.CAP.cards, "не больше предела")
    H.eq(s.cardsTotal, #cards, "общее число тоже записано")
    local c = s.cards[1]
    for _, field in ipairs({ "rank", "kind", "title", "benefit", "why", "need",
                             "conf", "confLabel", "score" }) do
        H.ok(c[field] ~= nil, "у записанной карточки есть поле " .. field)
    end
    H.eq(c.rank, 1, "порядок сохранён")
    H.eq(c.title, cards[1].title, "заголовок совпадает с показанным")
end

-- Sanity checks: each must fire when it should ---------------------------

H.suite("Проверка: все проверки зарегистрированы и не падают")
do
    local env = world()
    local ns = env.ns
    H.ok(ns.SanityChecks:Count() >= 20,
        ns.SanityChecks:Count() .. " проверок зарегистрировано")
    H.build(env)
    local m = ns.Diag:Init().modules.sanityChecks
    H.eq(m.failed, 0, "ни одна проверка не упала")
    -- `out` is the number of FINDINGS, not the number of checks. It used to be
    -- the latter, and the file then read "sanityChecks in=6 out=32", which a
    -- reader takes as thirty-two problems on six cards. `ran` is the count.
    H.eq(m.ran, ns.SanityChecks:Count(), "все проверки отработали")
    H.eq(m.checks, ns.SanityChecks:Count(), "и их число записано")
    H.ok(m.findings ~= nil, "находки посчитаны отдельно: " .. tostring(m.findings))
    H.eq(m.out, m.findings, "out — это находки")
    H.ok(m.onCards ~= nil, "и записано, сколько находок доехало до карточек: "
        .. tostring(m.onCards))
    H.eq(m.lostDoubts, 0, "а потерянных по пути нет")
end

-- НАХОДКА «ПРО ЭТУ КАРТОЧКУ» ДОЕЗЖАЕТ ДО КАРТОЧКИ =========================
--
-- Живой прогон игрока: самопроверка писала в файл «„На продажу: Небесно-голубая
-- краска“: … в 166 раз больше» на каждом пересчёте, а карточка стояла вторым
-- советом сверху без единого слова об этом. Дело было не в одной проверке:
-- проход шёл после ранжирования и писал ТОЛЬКО в файл, то есть ни одна из двух
-- с лишним десятков находок «про эту карточку» дойти до экрана не могла.
-- Проверяется то, чем это закрыто: один маршрут на все такие находки.

H.suite("Самопроверка: адрес есть у каждой проверки, и перечень закрыт")
do
    local env = world()
    local ns = env.ns
    local missing, byScope = {}, { say = 0, defect = 0, list = 0 }
    for _, entry in ipairs(ns.SanityChecks.LIST) do
        local scope = ns.SanityChecks.SCOPE[entry.code]
        if scope == nil then missing[#missing + 1] = entry.code end
        if scope then byScope[scope] = (byScope[scope] or 0) + 1 end
    end
    H.eq(#missing, 0, "у каждой зарегистрированной проверки назван адрес"
        .. ((#missing > 0) and ("  <- " .. table.concat(missing, ", ")) or ""))
    -- Второй код проверки 27: она поднимает две разные находки.
    H.ok(ns.SanityChecks.SCOPE["profit-on-outlier-price"] ~= nil,
        "и у второго кода проверки про выбросы цены тоже")
    H.ok(byScope.say > 0 and byScope.defect > 0 and byScope.list > 0,
        string.format("адреса распределены: словами игроку %d, дефект %d, про список %d",
            byScope.say, byScope.defect, byScope.list))
    -- Неизвестный код - это дефект, а не «ничего»: карточку всё равно надо
    -- опустить и пометить.
    H.eq(ns.SanityChecks:Scope("такого-кода-нет"), "defect",
        "незнакомый код считается дефектом, а не пропускается")
end

H.suite("Самопроверка: находка с ключом карточки прикладывается к этой карточке")
do
    local env = world()
    local ns = env.ns
    local a = { key = "a", title = "Первый" }
    local b = { key = "b", title = "Второй" }
    ns.Diag:BindCards({ a, b })
    ns.Diag:Suspect("implausible-profit", "«Второй»: обещает слишком много",
        { key = "b" })
    ns.Diag:Suspect("implausible-profit", "«Второй»: обещает слишком много",
        { key = "b" })
    ns.Diag:Suspect("unnamed-items", "про список целиком", {})
    ns.Diag:Suspect("bad-cost", "про карточку, которой нет", { key = "нет такой" })
    local routed, lost = ns.Diag:UnbindCards()
    H.eq(#(b.doubts or {}), 1, "одна находка на второй карточке (повтор не удвоился)")
    H.eq(a.doubts, nil, "на первой карточке — ничего")
    H.eq(routed, 1, "доехала одна")
    H.eq(lost, 1, "и одна назвала ключ, которого в списке нет")
    -- После снятия привязки находки на карточки больше не едут.
    local c = { key = "c", title = "Третий" }
    ns.Diag:Suspect("bad-cost", "после прохода", { key = "c" })
    H.eq(c.doubts, nil, "вне прохода маршрут закрыт")
end

H.suite("Самопроверка: сомнение на карточке не зависит от того, включена ли диагностика")
do
    -- ЧЕСТНОСТЬ НА ЭКРАНЕ НЕ ПОДПИСКА НА ДИАГНОСТИКУ. Диагностику можно
    -- выключить; запись в файл при этом не идёт, а сомнение на карточке идти
    -- обязано - иначе «аддон сам себе не верит и молчит» вернётся целиком.
    local env = world()
    local ns = env.ns
    local card = { key = "z", title = "Карточка" }
    local was = ns.Diag.enabled
    ns.Diag.enabled = false
    ns.Diag:BindCards({ card })
    ns.Diag:Suspect("revenue-far-above-vendor", "выручка много больше", { key = "z" })
    ns.Diag:UnbindCards()
    ns.Diag.enabled = was
    H.eq(#(card.doubts or {}), 1, "сомнение доехало до карточки и при выключенной диагностике")
end

H.suite("Проверка: отрицательная выгода наверху")
do
    local env = world()
    local ns = env.ns
    ns.SanityChecks:Run({
        cards = { { key = "a", kind = ns.KIND.CRAFT_PROFIT,
                    title = "Убыточный крафт", benefitValue = -5000,
                    why = "x", need = "y", benefit = "-50с",
                    action = {}, conf = ns.CONF.CACHED, score = 1 } },
        snap = ns.CharacterScanner:Scan(),
    })
    H.ok(fired(env, "negative-benefit-on-top"), "сработала")
end

H.suite("Проверка: ненадеваемое в ветке «надеть»")
do
    local env = world()
    local ns = env.ns
    -- A level-50 robe smuggled into the gear branch.
    H.item(env, 500, { name = "Высокий капюшон", equipLoc = "INVTYPE_HEAD",
        reqLevel = 50, classID = 4, subclassID = 1 })
    ns.SanityChecks:Run({
        cards = { { key = "g", kind = ns.KIND.CRAFT_GEAR, itemID = 500,
                    title = "Высокий капюшон", benefitValue = 30,
                    why = "x", need = "y", benefit = "+30", action = {},
                    conf = ns.CONF.CACHED, score = 1 } },
        snap = ns.CharacterScanner:Scan(),
    })
    H.ok(fired(env, "unwearable-in-gear-branch"), "сработала")
    local hits = (suspicions(env))["unwearable-in-gear-branch"]
    H.ok(hits[1].text:find("50"), "в тексте назван нужный уровень")
end

H.suite("Проверка: ненадеваемое в ветке «надеть» — не ложное срабатывание")
do
    local env = world()
    local ns = env.ns
    -- The real build must not trip this check: the branch filters correctly.
    H.build(env)
    H.eq(fired(env, "unwearable-in-gear-branch"), false,
        "на нормальной сборке не срабатывает")
end

H.suite("Проверка: бесполезные чары")
do
    local env = world()
    local ns = env.ns
    ns.SanityChecks:Run({
        cards = { { key = "ench:9:WRIST", kind = ns.KIND.ENCHANT, recipeID = 9,
                    title = "Чары: сила", why = "x", need = "y",
                    benefit = "z", action = {}, conf = ns.CONF.CACHED, score = 1 } },
        snap = ns.CharacterScanner:Scan(),
        enchantBySlot = {
            ["ench:9:WRIST"] = {
                usefulness = 0,
                altList = { { usefulness = 1.0 }, { usefulness = 0 } },
            },
        },
    })
    H.ok(fired(env, "useless-enchant"), "сработала")
    local hits = (suspicions(env))["useless-enchant"]
    H.ok(hits[1].text:find("полезных формул"),
        "сказано, что была альтернатива: " .. hits[1].text)
end

H.suite("Проверка: устаревшая цена без пометки")
do
    local env = world()
    local ns = env.ns
    ns.SanityChecks:Run({
        cards = { { key = "p", kind = ns.KIND.BUY, title = "Купить",
                    why = "без упоминания возраста", need = "тоже без",
                    benefit = "z", action = {}, conf = ns.CONF.CACHED, score = 1,
                    plan = { shopping = { { itemID = 2589, qty = 1,
                        age = 200000, conf = ns.CONF.CACHED } } } } },
        snap = ns.CharacterScanner:Scan(),
    })
    H.ok(fired(env, "stale-price-unmarked"), "сработала")
end

H.suite("Проверка: устаревшая цена с пометкой — молчит")
do
    local env = world()
    local ns = env.ns
    ns.SanityChecks:Run({
        cards = { { key = "p", kind = ns.KIND.BUY, title = "Купить",
                    why = "цена 2 дня назад", need = "y",
                    benefit = "z", action = {}, conf = ns.CONF.CACHED, score = 1,
                    plan = { shopping = { { itemID = 2589, qty = 1,
                        age = 200000, conf = ns.CONF.CACHED } } } } },
        snap = ns.CharacterScanner:Scan(),
    })
    H.eq(fired(env, "stale-price-unmarked"), false,
        "если возраст упомянут в тексте — не срабатывает")
end

H.suite("Проверка: количество меньше нуля")
do
    local env = world()
    local ns = env.ns
    ns.SanityChecks:Run({
        cards = { { key = "q", kind = ns.KIND.CRAFT_GEAR, title = "Крафт",
                    why = "x", need = "y", benefit = "z", action = {},
                    conf = ns.CONF.CACHED, score = 1, benefitValue = 1,
                    plan = { needRaw = { [2589] = -3 }, usedHere = {} } } },
        snap = ns.CharacterScanner:Scan(),
    })
    H.ok(fired(env, "bad-quantity"), "сработала на отрицательном количестве")
end

H.suite("Проверка: циклический рецепт")
do
    local env = world()
    local ns = env.ns
    ns.SanityChecks:Run({
        cards = { { key = "c", kind = ns.KIND.CRAFT_GEAR, title = "Крафт",
                    why = "x", need = "y", benefit = "z", action = {},
                    conf = ns.CONF.CACHED, score = 1, benefitValue = 1,
                    plan = { hasCycle = true, cycleList = { 10, 11 } } } },
        snap = ns.CharacterScanner:Scan(),
    })
    H.ok(fired(env, "recipe-cycle"), "сработала")
end

H.suite("Проверка: битый приоритет")
do
    local env = world()
    local ns = env.ns
    local nan = 0 / 0
    ns.SanityChecks:Run({
        cards = { { key = "s", kind = ns.KIND.CRAFT_GEAR, title = "Крафт",
                    why = "x", need = "y", benefit = "z", action = {},
                    conf = ns.CONF.CACHED, score = nan, benefitValue = 1 } },
        snap = ns.CharacterScanner:Scan(),
    })
    H.ok(fired(env, "bad-score"), "nan в приоритете замечен")
end

H.suite("Проверка: завышенная достоверность")
do
    local env = world()
    local ns = env.ns
    ns.SanityChecks:Run({
        cards = { { key = "o", kind = ns.KIND.BUY, title = "Купить",
                    why = "x", need = "y", benefit = "z", action = {},
                    conf = ns.CONF.CACHED, score = 1,
                    plan = { shopping = { { itemID = 2589, qty = 1,
                        src = "markup", conf = ns.CONF.EXACT } } } } },
        snap = ns.CharacterScanner:Scan(),
    })
    H.ok(fired(env, "overclaimed-confidence"),
        "оценка, помеченная как точная, замечена")
end

H.suite("Проверка: пустое поле карточки")
do
    local env = world()
    local ns = env.ns
    ns.SanityChecks:Run({
        cards = { { key = "e", kind = ns.KIND.BUY, title = "",
                    why = nil, need = "y", benefit = "z", action = nil,
                    conf = ns.CONF.CACHED, score = 1 } },
        snap = ns.CharacterScanner:Scan(),
    })
    H.ok(fired(env, "empty-card-field"), "сработала")
    local hits = (suspicions(env))["empty-card-field"]
    H.ok(hits[1].text:find("заголовок"), "перечислены пустые поля: " .. hits[1].text)
end

H.suite("Проверка: мусор в тексте карточки")
do
    local env = world()
    local ns = env.ns
    ns.SanityChecks:Run({
        cards = { { key = "n", kind = ns.KIND.BUY, title = "Купить nil штук",
                    why = "x", need = "y", benefit = "z", action = {},
                    conf = ns.CONF.CACHED, score = 1 } },
        snap = ns.CharacterScanner:Scan(),
    })
    H.ok(fired(env, "empty-card-field"), "nil в тексте замечен")
end

H.suite("Проверка: дубль ключа")
do
    local env = world()
    local ns = env.ns
    local card = { key = "same", kind = ns.KIND.BUY, title = "A", why = "x",
                   need = "y", benefit = "z", action = {},
                   conf = ns.CONF.CACHED, score = 1 }
    ns.SanityChecks:Run({
        cards = { card, card },
        snap = ns.CharacterScanner:Scan(),
    })
    H.ok(fired(env, "duplicate-key"), "сработала")
end

H.suite("Проверка: неподъёмная трата без предупреждения")
do
    local env = world({ money = 500 })
    local ns = env.ns
    ns.SanityChecks:Run({
        cards = { { key = "u", kind = ns.KIND.BUY, title = "Купить дорого",
                    why = "x", need = "просто купите", benefit = "z",
                    action = {}, conf = ns.CONF.CACHED, score = 1,
                    cost = 100000 } },
        snap = ns.CharacterScanner:Scan(),
    })
    H.ok(fired(env, "unaffordable-unmarked"), "сработала")

    -- With the shortfall spelled out, it must stay quiet.
    ns.Diag:ClearSuspicions()
    ns.SanityChecks:Run({
        cards = { { key = "u", kind = ns.KIND.BUY, title = "Купить дорого",
                    why = "x", need = "Не хватает 9з", benefit = "z",
                    action = {}, conf = ns.CONF.CACHED, score = 1,
                    cost = 100000 } },
        snap = ns.CharacterScanner:Scan(),
    })
    H.eq(fired(env, "unaffordable-unmarked"), false,
        "если в карточке сказано про нехватку — молчит")
end

H.suite("Проверка: неправдоподобная прибыль")
do
    local env = world({ level = 26 })
    local ns = env.ns
    ns.SanityChecks:Run({
        cards = { { key = "i", kind = ns.KIND.CRAFT_PROFIT,
                    title = "Золотая жила", benefitValue = 50000000,
                    why = "x", need = "y", benefit = "+5000з", action = {},
                    conf = ns.CONF.CACHED, score = 1 } },
        snap = ns.CharacterScanner:Scan(),
    })
    H.ok(fired(env, "implausible-profit"), "сработала на 5000 золота у 26 уровня")
end

H.suite("Проверка: нулевой навык при наличии рецептов")
do
    local env = world()
    local ns = env.ns
    env.professions = {
        { name = "Tailoring", skill = 0, max = 0, skillTrusted = false },
    }
    env.professionRoute = "GetProfessionInfoBySkillLineID"
    H.build(env)
    H.ok(fired(env, "zero-skill-with-recipes"),
        "известная ловушка клиента попадает в отчёт")
    local hits = (suspicions(env))["zero-skill-with-recipes"]
    -- Маршрут - имя функции игры. Тому, кто разбирает находку, оно нужно, и
    -- оно лежит в записи; игроку, который набрал /fp diag, оно не говорит
    -- ничего, поэтому в самом тексте его нет.
    H.eq(type(hits[1].detail) == "table" and hits[1].detail.route,
        "GetProfessionInfoBySkillLineID", "в записи назван маршрут, который соврал")
    H.ok(hits[1].text:find("GetProfessionInfoBySkillLineID", 1, true) == nil,
        "а в тексте для чата имени функции нет: " .. hits[1].text)
    -- Профессия названа ИМЕНЕМ ДЛЯ ИГРОКА: эту строку он читает в сводке и
    -- в ответе на /fp diag (U.profLabel, Core/Util.lua).
    H.ok(hits[1].text:find(ns.Util.profLabel("Tailoring"), 1, true) ~= nil,
        "и названа профессия: " .. hits[1].text)
end

H.suite("Проверка: пустые сумки и пустая экипировка")
do
    local env = world()
    local ns = env.ns
    env.bags = {}
    env.equipped = {}
    H.build(env)
    H.ok(fired(env, "empty-bag-scan"), "пустые сумки замечены")
    H.ok(fired(env, "empty-equipment-scan"), "пустая экипировка замечена")
    local hits = (suspicions(env))["empty-equipment-scan"]
    H.ok(hits[1].text:find("26"), "указан уровень персонажа: " .. hits[1].text)
end

H.suite("Проверка: предметы без названий")
do
    local env = world()
    local ns = env.ns
    local cards = {}
    for i = 1, 4 do
        cards[i] = { key = "k" .. i, kind = ns.KIND.BUY,
                     title = "Купить: Предмет #" .. (1000 + i),
                     why = "x", need = "y", benefit = "z", action = {},
                     conf = ns.CONF.CACHED, score = 1 }
    end
    ns.SanityChecks:Run({ cards = cards, snap = ns.CharacterScanner:Scan() })
    H.ok(fired(env, "unnamed-items"), "холодный кеш предметов замечен")
end

H.suite("Проверка: рецепт без реагентов")
do
    local env = world()
    local ns = env.ns
    -- A learned recipe with an output but no reagents: the schematic never came.
    H.profession(env, "Cooking", 225, 225, {
        H.recipe { id = 77, name = "Пустая схема", output = 999, reagents = {} },
    })
    H.item(env, 999, { name = "Непонятное блюдо" })
    H.build(env)
    H.ok(fired(env, "recipe-without-reagents"), "сработала")
end

H.suite("Проверка: обрезанный список")
do
    local env = world()
    local ns = env.ns
    ns.SanityChecks:Run({
        cards = { { key = "a", kind = ns.KIND.BUY, title = "A", why = "x",
                    need = "y", benefit = "z", action = {},
                    conf = ns.CONF.CACHED, score = 1 } },
        snap = ns.CharacterScanner:Scan(),
        generated = 90,
    })
    H.ok(fired(env, "list-truncated"), "сработала")
end

H.suite("Проверка: противоречивый план")
do
    local env = world()
    local ns = env.ns
    ns.SanityChecks:Run({
        cards = { { key = "x", kind = ns.KIND.CRAFT_GEAR, title = "Крафт",
                    why = "x", need = "y", benefit = "z", action = {},
                    conf = ns.CONF.CACHED, score = 1, benefitValue = 1,
                    plan = { ready = true, readiness = 0.5,
                             shopping = { { itemID = 1, qty = 2 } } } } },
        snap = ns.CharacterScanner:Scan(),
    })
    H.ok(fired(env, "contradictory-plan"), "сработала")
    local hits = (suspicions(env))["contradictory-plan"]
    H.ok(#hits >= 2, "обе нестыковки замечены (" .. #hits .. ")")
end

H.suite("Проверка: бесполезный крафт ради навыка")
do
    local env = world()
    local ns = env.ns
    -- A grey recipe offered for a skill-up.
    H.profession(env, "Cooking", 100, 225, {
        H.recipe { id = 55, name = "Серый рецепт", output = 998,
                   reagents = { { itemID = 2589, qty = 1 } }, diff = "trivial" },
    })
    H.item(env, 998, { name = "Сухарь" })
    ns.SanityChecks:Run({
        cards = { { key = "sk", kind = ns.KIND.CRAFT_SKILL, recipeID = 55,
                    title = "На навык: Серый рецепт", why = "x", need = "y",
                    benefit = "z", action = {}, conf = ns.CONF.CACHED, score = 1 } },
        snap = ns.CharacterScanner:Scan(),
    })
    H.ok(fired(env, "pointless-skill-craft"), "сработала")
end

H.suite("Проверка: битое место")
do
    local env = world()
    local ns = env.ns
    ns.SanityChecks:Run({
        cards = { { key = "pl", kind = ns.KIND.BUY, title = "Купить",
                    why = "x", need = "y", benefit = "z", action = {},
                    conf = ns.CONF.CACHED, score = 1,
                    place = { routable = true, x = 34, y = 76, mapID = 1434 } } },
        snap = ns.CharacterScanner:Scan(),
    })
    H.ok(fired(env, "bad-place"), "координаты вне диапазона 0..1 замечены")
end

H.suite("Проверка: все ветки пусты")
do
    local env = world()
    local ns = env.ns
    ns.SanityChecks:Run({
        cards = {}, snap = ns.CharacterScanner:Scan(),
        counts = { gear = 0, enchant = 0, profit = 0, skill = 0, buy = 0, junk = 0 },
    })
    H.ok(fired(env, "all-branches-empty"), "сработала")

    -- Карточка «вернуть скрытые» идёт в counts под ключом hidden. Она не
    -- ветка советов, и считать её — значит заглушить эту проверку ровно в том
    -- состоянии, для которого она написана.
    ns.Diag:ClearSuspicions()
    ns.SanityChecks:Run({
        cards = {}, snap = ns.CharacterScanner:Scan(),
        counts = { gear = 0, enchant = 0, profit = 0, skill = 0, buy = 0,
                   junk = 0, hidden = 1 },
        hidden = 0,
    })
    H.ok(fired(env, "all-branches-empty"),
        "карточка про скрытое не считается веткой — проверка всё равно сработала")

    -- А ВОТ СОВЕТЫ, КОТОРЫЕ ИГРОК СКРЫЛ САМ, - ЭТО НЕ «НИКТО НИЧЕГО НЕ ВЫДАЛ».
    --
    -- Здесь раньше стояло обратное ожидание (hidden = 3 - и проверка обязана
    -- сработать), и оно было ошибкой: счёт по веткам приходит сюда уже БЕЗ
    -- скрытых советов, поэтому у игрока, спрятавшего всё, проверка писала «ни
    -- один модуль советов ничего не выдал» - при восьми построенных советах,
    -- карточке «Скрытых советов: 8» на экране и строке «Вы скрыли 8 советов» в
    -- той же сводке. Запись об этом состоянии не теряется: её ведёт модуль
    -- actionEngine с кодом HIDDEN_BY_PLAYER.
    ns.Diag:ClearSuspicions()
    ns.SanityChecks:Run({
        cards = {}, snap = ns.CharacterScanner:Scan(),
        counts = { gear = 0, enchant = 0, profit = 0, skill = 0, buy = 0,
                   junk = 0, hidden = 1 },
        hidden = 3,
    })
    H.ok(not fired(env, "all-branches-empty"),
        "скрытое самим игроком не объявляется «никто ничего не выдал»")
end

-- То же на настоящем движке, а не на подставленных числах: игрок скрыл все
-- советы - и самопроверка не говорит, что советов никто не строил.
H.suite("Проверка: игрок скрыл всё — это не «ни одна ветка ничего не выдала»")
do
    local env = world()
    local ns = env.ns
    H.build(env)
    local hiddenNow = 0
    for _, card in ipairs(ns.ActionEngine.cards or {}) do
        if not card.blocking then
            ns.Config:Dismiss(card.key, ns.Api:ServerTime(), 86400)
            hiddenNow = hiddenNow + 1
        end
    end
    H.ok(hiddenNow > 0, "предпосылка: было что скрывать (" .. hiddenNow .. ")")
    H.build(env)
    H.ok((ns.ActionEngine.meta.hiddenByDismissal or 0) > 0,
        "движок видит, что советы скрыты игроком: "
        .. tostring(ns.ActionEngine.meta.hiddenByDismissal))
    H.ok(not fired(env, "all-branches-empty"),
        "проверка «все ветки пусты» молчит")
    local joined = table.concat(ns.Diag:Summary(), "\n")
    H.ok(joined:find("ничего не выдал", 1, true) == nil,
        "и ответ на /fp diag не говорит, что никто ничего не выдал")
end

-- Дыра, в которую провалился живой персонаж: ветки выдали кандидатов,
-- до игрока не дошло ничего. Сумма counts была 13, поэтому проверка
-- «все ветки пусты» молчала, а окно показывало «0 советов».
H.suite("Проверка: кандидаты есть, советов нет")
do
    local env = world()
    local ns = env.ns
    ns.Diag:ClearSuspicions()
    ns.SanityChecks:Run({
        cards = {}, snap = ns.CharacterScanner:Scan(),
        counts = { gear = 4, enchant = 0, profit = 8, skill = 1, buy = 0, junk = 0 },
        hidden = 14,
    })
    H.ok(fired(env, "candidates-produced-nothing"), "сработала")
    H.eq(fired(env, "all-branches-empty"), false,
        "а «все ветки пусты» молчит — она и молчала в игре")
    local hit = (suspicions(env))["candidates-produced-nothing"][1]
    H.ok(hit.text:find("13") ~= nil, "названо число кандидатов: " .. hit.text)
    H.ok(hit.text:find("скрыто") ~= nil, "и что их скрыл игрок")
    H.ok(hit.text:find("/fp show") ~= nil, "и как вернуть")

    -- Без скрывашек текст другой: это уже потеря внутри движка.
    ns.Diag:ClearSuspicions()
    ns.SanityChecks:Run({
        cards = {}, snap = ns.CharacterScanner:Scan(),
        counts = { gear = 4, profit = 8 }, hidden = 0,
    })
    local hit2 = (suspicions(env))["candidates-produced-nothing"][1]
    H.ok(hit2 and hit2.text:find("потеря") ~= nil,
        "сказано про потерю внутри движка: " .. tostring(hit2 and hit2.text))

    -- Карточки-настройки за советы не считаются: список из одного
    -- «откройте окно профессии» — это список без советов.
    ns.Diag:ClearSuspicions()
    ns.SanityChecks:Run({
        cards = { { kind = ns.KIND.SETUP, key = "setup:prof:X", title = "Откройте" } },
        snap = ns.CharacterScanner:Scan(),
        counts = { gear = 4 }, hidden = 0,
    })
    H.ok(fired(env, "candidates-produced-nothing"),
        "список из одной карточки-настройки не считается советом")

    -- А настоящий совет проверку гасит.
    ns.Diag:ClearSuspicions()
    ns.SanityChecks:Run({
        cards = { { kind = ns.KIND.CRAFT_PROFIT, key = "profit:1", title = "На продажу" } },
        snap = ns.CharacterScanner:Scan(),
        counts = { gear = 4 }, hidden = 9,
    })
    H.eq(fired(env, "candidates-produced-nothing"), false,
        "с настоящим советом в списке проверка молчит")
end

H.suite("Проверка: нормальная сборка не плодит ложных срабатываний")
do
    local env = world()
    local ns = env.ns
    H.build(env)
    local byCode, all = suspicions(env)
    -- These would be real defects on a healthy world; the known-benign ones
    -- (no bank seen, no places recorded) are allowed.
    local benign = {
        ["empty-bag-scan"] = true,          -- the fixture has few items
        ["recipe-without-reagents"] = true, -- enchants have no output by design
        ["enchant-slot-unmapped"] = true,
        ["list-truncated"] = true,
    }
    local bad = {}
    for code, hits in pairs(byCode) do
        if not benign[code] then
            bad[#bad + 1] = code .. " (" .. hits[1].text .. ")"
        end
    end
    H.eq(#bad, 0, "нет неожиданных срабатываний"
        .. (#bad > 0 and (": " .. table.concat(bad, "; ")) or ""))
end

H.suite("Производительность: набор зачаровываемых слотов кешируется")
do
    -- This was a real 35 ms-per-rebuild bug, found by this very module:
    -- IsEnchantable rebuilt the slot set from all recipes on every call, and it
    -- is called once per equipment slot. The cache must hold, and must drop
    -- when the recipe set or the player's slot mapping changes.
    local env = world()
    local ns = env.ns

    local calls = 0
    local realEnchantSlot = ns.SlotMap.EnchantSlot
    ns.SlotMap.EnchantSlot = function(self, recipe)
        calls = calls + 1
        return realEnchantSlot(self, recipe)
    end

    ns.RecipeBook:InvalidateEnchantCache()
    ns.SlotMap:IsEnchantable("WRIST")
    local first = calls
    H.ok(first > 0, "первый вызов действительно считает (" .. first .. " обращений)")

    calls = 0
    for _ = 1, 20 do ns.SlotMap:IsEnchantable("WRIST") end
    H.eq(calls, 0, "20 повторных вызовов не пересчитывают ничего")

    -- Reindex must drop the cache: a new scan can add slots.
    ns.RecipeBook:Reindex()
    calls = 0
    ns.SlotMap:IsEnchantable("WRIST")
    H.ok(calls > 0, "после Reindex кеш сброшен и пересчитан")

    -- A manual slot re-assignment must drop it too.
    calls = 0
    ns.SlotMap:IsEnchantable("WRIST")
    H.eq(calls, 0, "кеш снова держит")
    ns.Config:SetEnchantSlot(10, "FEET")
    calls = 0
    ns.SlotMap:IsEnchantable("WRIST")
    H.ok(calls > 0, "ручная правка слота сбрасывает кеш")

    ns.SlotMap.EnchantSlot = realEnchantSlot
end

H.suite("Производительность: пересчёт укладывается в бюджет")
do
    local env = world()
    local ns = env.ns
    H.build(env)   -- warm
    local s = ns.Diag:Init()
    s.perf = { recomputes = 0, totalMs = 0, peakMs = 0, lastMs = 0, samples = {} }
    for _ = 1, 5 do H.build(env) end
    H.eq(s.perf.recomputes, 5, "пять пересчётов замерено")
    -- Generous by design: the harness is slower than the game's Lua, and the
    -- assertion exists to catch a regression of the 20x kind, not to tune.
    H.ok(s.perf.avgMs < 60,
        string.format("средний пересчёт %.1f мс", s.perf.avgMs or 0))
    H.ok(s.perf.peakMs < 200,
        string.format("пиковый пересчёт %.1f мс", s.perf.peakMs or 0))
    H.ok(ns.ActionEngine.meta.branchMs ~= nil, "разбивка по ветвям записана")
end

H.suite("Производительность: ветка продажи не планирует всё подряд")
do
    local env = world()
    local ns = env.ns
    -- Make many profitable recipes, then check only a shortlist gets planned:
    -- a full plan per candidate was the other hot path.
    local list = {}
    for i = 1, 60 do
        local out = 2000 + i
        H.item(env, out, { name = "Товар " .. i, sellPrice = 100 })
        env.prices[out] = 5000 + i * 10
        list[#list + 1] = H.recipe { id = 300 + i, name = "Товар " .. i,
            output = out, reagents = { { itemID = 2589, qty = 2 } },
            diff = "medium", category = "Разное", categoryID = 9 }
    end
    ns.RecipeBook.byProfession["Tailoring"] = nil
    ns.RecipeBook:Store("Tailoring", list, "own", ns.CONF.EXACT, 0)
    ns.RecipeBook:Reindex()
    H.build(env)

    local m = ns.Diag:Init().modules.craftProfit
    H.ok(m ~= nil, "метрика ветки есть")
    H.ok(m["in"] >= 50, m["in"] .. " рецептов рассмотрено")
    H.ok(m.planned <= m.shortlist,
        string.format("планов построено %d, не больше шортлиста %d",
            m.planned, m.shortlist))
    H.ok(m.planned < m["in"],
        "планируется меньше, чем рассматривается (" .. m.planned
        .. " из " .. m["in"] .. ")")
    H.ok(m.out <= ns.MAX_CARDS_PER_KIND, "карточек не больше лимита")
end

H.suite("Диагностика: не влияет на результат советов")
do
    -- The whole promise of the module: turning it off must change nothing about
    -- the advice itself.
    local a = world()
    local cardsA = H.build(a)
    local keysA = {}
    for _, c in ipairs(cardsA) do keysA[#keysA + 1] = c.key end

    local b = world()
    b.ns.Diag.enabled = false
    local cardsB = H.build(b)
    local keysB = {}
    for _, c in ipairs(cardsB) do keysB[#keysB + 1] = c.key end

    H.eq(table.concat(keysB, "|"), table.concat(keysA, "|"),
        "с диагностикой и без неё список советов одинаковый")
    H.eq(#b.ns.Diag:Init().suspicious, 0, "выключенная диагностика ничего не пишет")
end

-- СВОДКА НЕ ИМЕЕТ ПРАВА ПРОТИВОРЕЧИТЬ ЭКРАНУ ==============================
--
-- Живая жалоба: в диагностике «Молчат 2 из 14 веток: Благосклонность торговца
-- (навыка пока не хватает ни на одну покупку)», а на экране три карточки
-- Благосклонности. Ветка работает, сводка говорит, что молчит.
--
-- Причина общая и не про Благосклонность: сводка считала то, что ветка
-- ПОСТРОИЛА, а игрок видит то, что на экране ОСТАЛОСЬ. Это два разных числа, и
-- расходятся они штатно - профиль убирает карточки после всех веток. В живом
-- файле это видно прямо: resale=4 и priceinfo=1 при пометке «профиль убрал из
-- списка», то есть на экране их ноль, а молчащими они не считались.
--
-- Поэтому «молчит» теперь означает «на экране ничего нет», и это проверяется с
-- двух сторон: ветка с карточками молчащей не числится, а ветка, чьи карточки
-- убрал профиль, числится - и говорит, что убрал их профиль.

H.suite("Сводка: ветка с карточками на экране не числится молчащей")
do
    local env = world()
    local ns = env.ns
    local cards = H.build(env)
    local onScreen = {}
    for _, c in ipairs(cards) do
        local branch = ns.ActionEngine.BRANCH_BY_KIND[c.kind]
        if branch then onScreen[branch] = (onScreen[branch] or 0) + 1 end
    end
    ns.Diag:WriteSummary()
    local summary = table.concat(ns.Diag:Init().summary or {}, "\n")

    -- Ни одна ветка, у которой есть карточка на экране, не названа молчащей.
    local wrong = {}
    for branch, n in pairs(onScreen) do
        local label = ns.ActionEngine.BRANCH_LABEL[branch] or branch
        -- «Молчат ...» перечисляет ветки строками «    — Название (причина)».
        if ns.Util.contains(summary, "— " .. label .. " (")
           or ns.Util.contains(summary, "— " .. label .. "\n") then
            wrong[#wrong + 1] = label .. ":" .. n
        end
    end
    H.eq(#wrong, 0,
        "ветки с карточками на экране не названы молчащими: "
        .. table.concat(wrong, ", "))

    -- И то же самое числом: в отчёте по веткам count равен тому, что на экране.
    for _, b in ipairs(ns.ActionEngine.meta.branches or {}) do
        H.eq(b.count, onScreen[b.key] or 0,
            "ветка «" .. b.label .. "»: в отчёте " .. b.count
            .. ", на экране " .. (onScreen[b.key] or 0))
    end
end

H.suite("Сводка: карточки убрал профиль — ветка молчит и говорит, кто виноват")
do
    local env = world()
    local ns = env.ns
    -- Профиль «Сила» убирает перекупку и «про цену». Берём ветку, которая
    -- что-то построила, и смотрим, что сводка скажет про неё после фильтра.
    ns.Config:SetProfile("POWER")
    H.build(env)
    local built = ns.ActionEngine.meta.branchBuilt or {}
    local onScreen = {}
    for _, c in ipairs(ns.ActionEngine.cards) do
        local branch = ns.ActionEngine.BRANCH_BY_KIND[c.kind]
        if branch then onScreen[branch] = (onScreen[branch] or 0) + 1 end
    end
    H.ok(next(built) ~= nil, "число построенных карточек по веткам записано")
    -- Та ветка, что построила и потеряла всё: должна считаться молчащей и
    -- объяснять это профилем, а не выдумывать свою причину.
    local victim
    for branch, n in pairs(built) do
        if n > 0 and (onScreen[branch] or 0) == 0 then victim = branch end
    end
    if not victim then
        H.ok(true, "в этом мире профиль ничего не убрал целиком — пропущено")
    else
        local note = ns.ActionEngine.branchNote[victim]
        H.ok(note ~= nil, "у ветки «" .. victim .. "» есть причина")
        H.ok(note and ns.Util.contains(note, "профиль"),
            "и причина - профиль, а не выдуманная нехватка: " .. tostring(note))
        for _, b in ipairs(ns.ActionEngine.meta.branches or {}) do
            if b.key == victim then
                H.eq(b.count, 0, "в отчёте у неё ноль — столько и на экране")
                H.ok(b.reason ~= nil, "и причина доехала до отчёта")
            end
        end
    end
end

H.suite("Сводка: построенное и показанное - два разных числа, и оба записаны")
do
    local env = world()
    local ns = env.ns
    H.build(env)
    local ae = ns.Diag:Init().modules.actionEngine
    H.ok(ae ~= nil, "модуль записан")
    if ae then
        H.ok(type(ae.branchCounts) == "table", "сколько на экране — записано")
        H.ok(type(ae.branchBuilt) == "table", "и сколько построено — тоже")
        -- Сумма по веткам плюс карточки, у которых ветки нет вовсе
        -- (настройка, «вернуть скрытые»), даёт ровно то, что на экране.
        local screen = 0
        for _, n in pairs(ae.branchCounts) do screen = screen + n end
        local branchless = 0
        for _, c in ipairs(ns.ActionEngine.cards) do
            if not ns.ActionEngine.BRANCH_BY_KIND[c.kind] then
                branchless = branchless + 1
            end
        end
        H.eq(screen + branchless, tonumber(ae.out) or -1,
            "сумма по веткам плюс безветочные сходится с числом советов: "
            .. screen .. " + " .. branchless .. " и " .. tostring(ae.out))
    end
end

H.suite("Сводка: у каждой ветки есть русское название")
do
    local env = world()
    local ns = env.ns
    -- Три названия лежали в соседней таблице (BRANCH_BY_KIND вместо
    -- BRANCH_LABEL), и русская сводка печатала «disenchant» английским ключом
    -- посреди русского текста. Проверка держит обе таблицы на месте.
    for _, key in ipairs(ns.ActionEngine.BRANCH_ORDER) do
        local label = ns.ActionEngine.BRANCH_LABEL[key]
        H.ok(label ~= nil and label ~= key,
            "ветка «" .. key .. "» названа по-русски: " .. tostring(label))
    end
    -- И в обратной таблице нет лишних ключей: там только ВИДЫ карточек.
    for kind, branch in pairs(ns.ActionEngine.BRANCH_BY_KIND) do
        H.ok(ns.KIND[kind] ~= nil,
            "в «вид -> ветка» ключ «" .. tostring(kind) .. "» - настоящий вид карточки")
        H.ok(ns.ActionEngine.BRANCH_LABEL[branch] ~= nil,
            "и ведёт к существующей ветке: " .. tostring(branch))
    end
end

H.suite("Сводка: число обращений за пересчёт попадает в текст")
do
    local env = world()
    local ns = env.ns
    H.build(env)
    ns.Diag:WriteSummary()
    local text = table.concat(ns.Diag:Init().summary or {}, "\n")
    H.ok(ns.Util.contains(text, "Обращений за пересчёт"),
        "строка про обращения есть: сводка отвечает на «почему дорого» числом")
    H.ok(ns.Util.contains(text, "Codex"), "и Codex в ней назван")
    H.ok(ns.Util.contains(text, "из памяти"),
        "вместе с тем, сколько ответов пришло из памяти")
    H.ok(ns.Util.contains(text, "Дороже всех ветка"),
        "и названа самая дорогая ветка")
end

H.suite("Сводка: находки самопроверки не вытесняются из текста")
do
    -- Предел на число строк урезал сводку МОЛЧА, и первым из файла исчезало
    -- самое нужное: строки «Странность: …» стоят в конце. Две новые строки про
    -- расход пересчёта этот предел и переполнили.
    local env = world()
    local ns = env.ns
    H.build(env)
    -- Набиваем странностей больше, чем сводка печатает, и смотрим, что они
    -- всё равно в неё попали.
    for i = 1, 5 do
        ns.Diag:Suspect("тест-странность-" .. i, "выдуманная странность номер " .. i)
    end
    ns.Diag:WriteSummary()
    local lines = ns.Diag:Init().summary or {}
    local text = table.concat(lines, "\n")
    H.ok(#lines <= ns.Diag.CAP.summaryLines,
        "сводка укладывается в предел: " .. #lines .. " из "
        .. ns.Diag.CAP.summaryLines)
    H.ok(ns.Util.contains(text, "Странность"),
        "и строка про странность в ней есть: её не вытеснило")
    H.ok(ns.Util.contains(text, "Пересчётов"),
        "и строка про пересчёты тоже")
end

H.suite("Сводка: что не влезло — сказано, а не выброшено молча")
do
    local env = world()
    local ns = env.ns
    H.build(env)
    local realCap = ns.Diag.CAP.summaryLines
    ns.Diag.CAP.summaryLines = 4   -- заведомо мало
    ns.Diag:WriteSummary()
    ns.Diag.CAP.summaryLines = realCap
    local lines = ns.Diag:Init().summary or {}
    local last = lines[#lines] or ""
    H.ok(ns.Util.contains(last, "не влезла") or ns.Util.contains(last, "не влезло"),
        "последняя строка говорит, сколько строк не поместилось: " .. last)
    H.ok(ns.Util.contains(last, "FOREVERPILOT_DIAG"),
        "и куда смотреть за полными данными")
end

end
