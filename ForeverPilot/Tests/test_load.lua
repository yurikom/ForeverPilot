-- ForeverPilot / Tests/test_load.lua
--
-- ЗАГРУЖАЕТСЯ ЛИ АДДОН В ИГРЕ, а не в тестовом интерпретаторе.
--
-- Этот набор существует из-за одной ошибки, которую весь остальной набор
-- пропустил. В Logic\ActionEngine.lua стоял `goto continue` - синтаксис Lua 5.2.
-- Клиент игры - Lua 5.1, где его нет вовсе: файл не компилировался целиком,
-- вместе с ним не выполнялось `ns.ActionEngine = Engine`, и дальше падало всё,
-- что обращалось к движку. В диагностике игрока за одну сессию: 72 падения
-- MainFrame:Rebuild, 65 Events:recompute, 3 StepPanel:Render - и красная строка
-- «пересчёт не удался» на экране.
--
-- ПОЧЕМУ НЕ ПОЙМАЛИ. Tests/loadcheck.lua написан ровно под этот риск, но
-- гоняется через texluajit, а LuaJIT принимает расширения 5.2 и `goto`
-- проглатывает. Проверка загружаемости проверяла не тем диалектом, то есть не
-- проверяла ничего. Заменить интерпретатор у набора нельзя, поэтому диалект
-- проверяется лексически - Tests/dialect.lua.
--
-- Здесь же живут две вещи, которых не хватало рядом:
--   * перепись модулей (Main.MODULES) сверяется с .toc в обе стороны, чтобы
--     новый файл нельзя было добавить в .toc и забыть в переписи;
--   * поведение при непрочитанном файле: одна внятная фраза с именем файла
--     вместо потока «attempt to index field» каждые несколько секунд.
local H = ...
local D = assert(loadfile((H.ROOT or ".") .. "/Tests/dialect.lua"))()
local S = assert(loadfile((H.ROOT or ".") .. "/Tests/uistub.lua"))()

return function()

-- САМОПРОВЕРКА ДЕТЕКТОРА ------------------------------------------------
--
-- Зелёный тест, который ничего не умеет провалить, хуже отсутствующего: ровно
-- так и вышло с loadcheck. Поэтому сначала детектор проверяется сам.

H.suite("Диалект: детектор ловит то, из-за чего аддон не загрузился")
do
    local withGoto = table.concat({
        "local x = 1",
        "for i = 1, 3 do",
        "    if i == 2 then go" .. "to continue end",
        "    x = x + i",
        "    ::continue" .. "::",
        "end",
        "return x",
    }, "\n")
    local found = D.violations(withGoto)
    H.ok(#found >= 2, "нарушения найдены: " .. #found)
    local sawGoto, sawLabel = false, false
    for _, v in ipairs(found) do
        if v.why:find("5.2", 1, true) then
            if v.text:find("::", 1, true) then sawLabel = true else sawGoto = true end
        end
    end
    H.ok(sawGoto, "сам переход найден")
    H.ok(sawLabel, "и метка тоже")

    -- И ровно та форма, что была в файле: `goto continue` внутри цикла.
    H.ok(#D.violations("go" .. "to continue") > 0,
        "«goto continue» — именно эта строка — считается нарушением")
end

H.suite("Диалект: детектор не придирается к словам в комментариях и строках")
do
    H.eq(#D.violations("-- тут слово go" .. "to в комментарии\nreturn 1"), 0,
        "в комментарии не считается")
    H.eq(#D.violations("local s = 'go" .. "to continue'\nreturn s"), 0,
        "в строке не считается")
    H.eq(#D.violations("--[[ go" .. "to\n::метка" .. ":: ]]\nreturn 1"), 0,
        "в длинном комментарии не считается")
    H.eq(#D.violations("local s = [==[ go" .. "to ]==]\nreturn s"), 0,
        "в длинной строке не считается")
    H.eq(#D.violations('local url = "https://example.com//x"\nreturn url'), 0,
        "двойная косая в строке — не целочисленное деление")
    H.eq(#D.violations("local a = 7 / 2\nreturn a"), 0,
        "обычное деление не трогаем")
    -- Номер строки у находки должен быть настоящим: иначе отчёт бесполезен.
    local v = D.violations("return 1\nreturn 2\nlocal z = 1 // 2\n")
    H.ok(#v == 1 and v[1].line == 3,
        "строка нарушения названа верно: " .. tostring(v[1] and v[1].line))
end

-- ГЛАВНОЕ ---------------------------------------------------------------

H.suite("Загрузка: ни один файл из .toc не содержит синтаксиса, которого нет в Lua 5.1")
do
    local files = assert(D.tocFiles(H.ROOT or "."), "ForeverPilot.toc не прочитан")
    H.ok(#files > 40, "файлов в .toc: " .. #files)
    for _, rel in ipairs(files) do
        local found, err = D.violationsInFile((H.ROOT or ".") .. "/" .. rel)
        H.ok(found ~= nil, rel .. ": файл прочитан", tostring(err))
        if found then
            local bits = {}
            for _, v in ipairs(found) do
                bits[#bits + 1] = "строка " .. v.line .. ": " .. v.why
                    .. " («" .. v.text .. "»)"
            end
            H.eq(#found, 0, rel .. ": диалект клиента соблюдён"
                .. ((#found > 0) and ("  <- " .. table.concat(bits, "; ")) or ""))
        end
    end
end

H.suite("Загрузка: каждый файл из .toc компилируется")
do
    local files = assert(D.tocFiles(H.ROOT or "."))
    for _, rel in ipairs(files) do
        local chunk, err = loadfile((H.ROOT or ".") .. "/" .. rel)
        H.ok(chunk ~= nil, rel .. " компилируется", tostring(err))
    end
end

-- ПРЕДЕЛЫ LUA 5.1 -------------------------------------------------------
--
-- Размер файла пределом не является: это проверено, когда загрузку подозревали
-- именно в нём (181 КБ грузятся, а не грузились 146 КБ - из-за двух строк).
-- Настоящие пределы - число локальных в одной функции, число захваченных
-- внешних локальных, число констант и вложенность. К ним можно подойти молча,
-- поэтому оценка считается заранее и предупреждает на 80% (Tests/dialect.lua).

local function sourceWithLocals(n)
    local t = {}
    for i = 1, n do t[#t + 1] = "local v" .. i .. " = " .. i end
    return table.concat(t, "\n")
end

local function sourceWithUpvalues(n)
    local t, refs = {}, {}
    for i = 1, n do
        t[#t + 1] = "local u" .. i .. " = " .. i
        refs[#refs + 1] = "u" .. i
    end
    t[#t + 1] = "local function f()"
    t[#t + 1] = "    return " .. table.concat(refs, " + ")
    t[#t + 1] = "end"
    t[#t + 1] = "return f"
    return table.concat(t, "\n")
end

H.suite("Пределы Lua 5.1: оценка сходится с интерпретатором на самой границе")
do
    -- Самопроверка: оценка, которую не с чем сверить, - это мнение. Предел на
    -- локальные у тестового интерпретатора тот же, что у клиента, поэтому на
    -- границе оценка обязана совпасть с тем, что он говорит на самом деле.
    for _, n in ipairs({ 199, 200, 201 }) do
        local src = sourceWithLocals(n)
        local loads = (loadstring(src) ~= nil)
        local m = D.limitsOfSource(src)
        H.eq(m.locals.value, n, n .. " локальных посчитаны как " .. n)
        H.eq(#m.errors == 0, loads, n .. " локальных: оценка «"
            .. ((#m.errors == 0) and "грузится" or "не грузится")
            .. "» совпала с интерпретатором («"
            .. (loads and "грузится" or "не грузится") .. "»)")
    end
    H.eq(loadstring(sourceWithLocals(200)) ~= nil, true, "200 локальных — ещё можно")
    H.eq(loadstring(sourceWithLocals(201)) ~= nil, false, "201 — уже нет")

    -- ЗАХВАТЫ: ЗДЕСЬ ТЕСТОВЫЙ ИНТЕРПРЕТАТОР СНОВА МЯГЧЕ ИГРОВОГО.
    --
    -- Настоящий Lua 5.1 отказывается от функции с 61 захваченной внешней
    -- локальной («function at line N has more than 60 upvalues»), а texluajit
    -- такой файл принимает. То есть это вторая, после `goto`, вещь, которую
    -- loadfile в тестах пропустил бы, а клиент - нет. Поэтому оценка здесь
    -- сверяется с пределом из документации клиента, а не с интерпретатором, а
    -- что говорит интерпретатор - печатается для сведения.
    for _, n in ipairs({ 59, 60, 61 }) do
        local src = sourceWithUpvalues(n)
        local m = D.limitsOfSource(src)
        H.eq(m.upvalues.value, n, n .. " захватов посчитаны как " .. n)
        H.eq(#m.errors == 0, n <= 60, n .. " захватов: "
            .. ((n <= 60) and "в пределах" or "за пределом — клиент не скомпилирует"))
    end
    print("     для сведения: этот интерпретатор файл с 61 захватом "
        .. ((loadstring(sourceWithUpvalues(61)) ~= nil)
            and "ГРУЗИТ — клиент игры отказывается, проверка выше это и ловит"
            or "не грузит, как и клиент"))
end

H.suite("Пределы Lua 5.1: предупреждение приходит заранее, а не вместе с отказом")
do
    local calm = D.limitsOfSource(sourceWithLocals(120))
    H.eq(#calm.warnings + #calm.errors, 0, "120 локальных из 200 — тихо")

    local near = D.limitsOfSource(sourceWithLocals(170))
    H.eq(#near.errors, 0, "170 из 200 — ещё не отказ")
    H.eq(#near.warnings, 1, "но уже предупреждение: " .. tostring(near.warnings[1]))

    local over = D.limitsOfSource(sourceWithLocals(230))
    H.eq(#over.errors, 1, "230 из 200 — отказ: " .. tostring(over.errors[1]))

    local nearUp = D.limitsOfSource(sourceWithUpvalues(50))
    H.eq(#nearUp.warnings, 1, "50 захватов из 60 — предупреждение: "
        .. tostring(nearUp.warnings[1]))

    -- Счёт не обманывается тем, что локальными не является.
    local tricky = D.measure(table.concat({
        "local a, b, c = 1, 2, 3            -- три",
        "local t = { local_like = 1, x = 2 } -- одна; ключи таблицы не в счёт",
        "local s = 'local z = 1'             -- одна; слово в строке не в счёт",
        "-- local y = 1                         в комментарии не в счёт",
        "for i, v in ipairs(t) do end        -- две переменные цикла",
        "local function f(p, q) return p end -- имя f здесь; p и q внутри f",
        "return a + b + c + #s + f(1, 2)",
    }, "\n"))
    H.eq(tricky.mainLocals, 8, "на верхнем уровне 8 локальных: a b c t s i v f")
    H.eq(tricky.upvalues.value, 0, "функция f ничего не захватывает")

    local nested = D.measure(table.concat({
        "local outer1, outer2, unused = 1, 2, 3",
        "local function a()",
        "    local mine = outer1",
        "    return function() return mine + outer2 end",
        "end",
        "return a",
    }, "\n"))
    H.eq(nested.upvalues.value, 2, "захваты считаются сквозь вложенные функции:"
        .. " внешняя тянет outer1 и outer2, внутренняя — mine и outer2")
end

H.suite("Пределы Lua 5.1: ни один файл аддона к ним не подошёл")
do
    local files = assert(D.tocFiles(H.ROOT or "."))
    local worst = {}
    for _, key in ipairs(D.LIMIT_ORDER) do worst[key] = { value = -1 } end
    local warned = 0
    for _, rel in ipairs(files) do
        local m, err = D.limits((H.ROOT or ".") .. "/" .. rel)
        H.ok(m ~= nil, rel .. ": измерен", tostring(err))
        if m then
            H.eq(#m.errors, 0, rel .. ": пределы Lua 5.1 не превышены"
                .. ((#m.errors > 0) and ("  <- " .. table.concat(m.errors, "; ")) or ""))
            for _, w in ipairs(m.warnings) do
                warned = warned + 1
                -- Предупреждение - не провал, но оно обязано попасть в итог
                -- прогона: ради этого проверка и заведена.
                H.note(rel .. " подходит к пределу Lua 5.1: " .. w)
            end
            for _, key in ipairs(D.LIMIT_ORDER) do
                if m[key].value > worst[key].value then
                    worst[key] = { value = m[key].value, rel = rel,
                                   name = m[key].name, line = m[key].line }
                end
            end
        end
    end
    -- Запас до каждого предела - числом, чтобы приближение было видно по
    -- прогонам, а не только когда сработает порог.
    for _, key in ipairs(D.LIMIT_ORDER) do
        local w, spec = worst[key], D.LIMITS[key]
        print(string.format("     %-9s самое большое: %d из %d (%d%%) — %s%s",
            key, w.value, spec.limit, math.floor(w.value / spec.limit * 100 + 0.5),
            tostring(w.rel),
            w.name and (", " .. tostring(w.name) .. ", строка " .. tostring(w.line)) or ""))
    end
    H.ok(true, "файлов измерено: " .. #files .. ", предупреждений: " .. warned)
end

-- ПЕРЕПИСЬ МОДУЛЕЙ ------------------------------------------------------

H.suite("Перепись модулей сверена с .toc в обе стороны")
do
    local env = S.load(H)
    local ns = env.ns
    local chunk = assert(loadfile(H.ROOT .. "/Main.lua"))
    setfenv(chunk, env.sandbox)
    chunk("ForeverPilot", ns)
    local Boot = ns.Bootstrap
    H.ok(Boot ~= nil, "Main.lua загружен")
    H.ok(type(Boot.MODULES) == "table", "перепись модулей есть")

    local inToc = {}
    for _, rel in ipairs(assert(D.tocFiles(H.ROOT or "."))) do inToc[rel] = true end

    local inCensus = {}
    for _, m in ipairs(Boot.MODULES) do
        local rel = (m.file:gsub("\\", "/"))
        inCensus[rel] = m.name
        H.ok(inToc[rel] == true,
            "файл из переписи есть в .toc: " .. m.file)
    end
    for rel in pairs(inToc) do
        H.ok(inCensus[rel] ~= nil,
            "файл из .toc есть в переписи: " .. rel
            .. " — иначе его пропажу аддон не заметит")
    end
end

H.suite("После полной загрузки не пропал ни один модуль")
do
    local env = S.load(H)
    local ns = env.ns
    local chunk = assert(loadfile(H.ROOT .. "/Main.lua"))
    setfenv(chunk, env.sandbox)
    chunk("ForeverPilot", ns)

    local missing = ns.Bootstrap:MissingModules()
    local names = {}
    for _, m in ipairs(missing) do names[#names + 1] = m.file end
    H.eq(#missing, 0, "все модули на месте"
        .. ((#missing > 0) and ("  <- нет: " .. table.concat(names, ", ")) or ""))
end

-- ПОВЕДЕНИЕ ПРИ НЕПРОЧИТАННОМ ФАЙЛЕ -------------------------------------

H.suite("Непрочитанный файл: назван именно он, одной фразой")
do
    local env = S.load(H)
    local ns = env.ns
    local G = env.G
    local chunk = assert(loadfile(H.ROOT .. "/Main.lua"))
    setfenv(chunk, env.sandbox)
    chunk("ForeverPilot", ns)

    -- Так это выглядит в игре: файл не скомпилировался, таблицы в ns нет.
    ns.ActionEngine = nil
    local missing = ns.Bootstrap:MissingModules()
    H.eq(#missing, 1, "пропажа замечена ровно одна")
    H.eq(missing[1] and missing[1].file, "Logic\\ActionEngine.lua",
        "и назван тот самый файл")

    local said = {}
    G.print = function(...)
        local bits = {}
        for i = 1, select("#", ...) do bits[#bits + 1] = tostring((select(i, ...))) end
        said[#said + 1] = table.concat(bits, " ")
    end
    ns.Bootstrap:ReportBrokenLoad(missing)
    local joined = table.concat(said, "\n")
    H.ok(#said > 0, "в чат что-то написано")
    H.ok(joined:find("ActionEngine.lua", 1, true) ~= nil,
        "имя файла в сообщении есть: " .. tostring(said[1]))
    H.ok(joined:find("attempt to index", 1, true) == nil,
        "и это НЕ сырая ошибка Lua — игроку такое читать нечем")
    H.ok(joined:find("выключен", 1, true) ~= nil,
        "сказано, что аддон выключен, а не «работает как-то»")
    H.ok(#said <= 6, "сообщение короткое: строк " .. #said)
end

H.suite("Непрочитанный файл: аддон не подписывается на события и не сыпет ошибками")
do
    local env = S.load(H)
    local ns = env.ns
    local G = env.G
    G.SlashCmdList = {}
    local chunk = assert(loadfile(H.ROOT .. "/Main.lua"))
    setfenv(chunk, env.sandbox)
    chunk("ForeverPilot", ns)
    ns.ActionEngine = nil

    local said = {}
    G.print = function(...) said[#said + 1] = tostring((...)) end

    local driver = G.ForeverPilotDriver
    H.ok(driver ~= nil, "кадр-драйвер создан")
    local onEvent = driver and driver.__scripts and driver.__scripts.OnEvent
    H.ok(onEvent ~= nil, "и у него есть обработчик событий")

    if onEvent then
        local ok1 = pcall(onEvent, driver, "ADDON_LOADED", "ForeverPilot")
        local ok2 = pcall(onEvent, driver, "PLAYER_LOGIN")
        H.ok(ok1 and ok2, "вход в игру не падает, хотя модуля нет")

        H.eq(ns.Bootstrap.ready, nil, "аддон НЕ объявил себя готовым")
        H.eq(ns.Bootstrap.halted, true, "и остановился осознанно")

        -- Главное: поток событий больше не доходит до пересчёта. Пробуем
        -- отправить то самое событие, которое в игре повторялось каждые
        -- несколько секунд.
        local before = #(ns.Diag:Init().errors or {})
        for _ = 1, 20 do
            pcall(onEvent, driver, "BAG_UPDATE_DELAYED")
            pcall(onEvent, driver, "PLAYER_MONEY")
        end
        local after = #(ns.Diag:Init().errors or {})
        H.eq(after, before, "ни одной новой ошибки за 40 событий"
            .. " (в игре их было 140 за сессию)")
        H.ok(#said <= 6, "и в чат не добавилось ни строки: " .. #said)

        -- И /fp отвечает тем же самым, а не молчит.
        local slash = G.SlashCmdList and G.SlashCmdList.FOREVERPILOT
        H.ok(slash ~= nil, "команда /fp всё равно зарегистрирована")
        if slash then
            said = {}
            pcall(slash, "")
            H.ok(#said > 0 and table.concat(said, "\n"):find("ActionEngine.lua", 1, true),
                "и она повторяет, какой файл не прочитан")
        end
    end
end

H.suite("Полная загрузка: аддон запускается и объявляет себя готовым")
do
    -- Обратная сторона предыдущего: остановка должна случаться ТОЛЬКО когда
    -- что-то действительно пропало. Иначе «не сыпет ошибками» достигается тем,
    -- что аддон не работает никогда.
    local env = S.load(H)
    local ns = env.ns
    local G = env.G
    G.SlashCmdList = {}
    local chunk = assert(loadfile(H.ROOT .. "/Main.lua"))
    setfenv(chunk, env.sandbox)
    chunk("ForeverPilot", ns)
    S.populate(env, H)

    local driver = G.ForeverPilotDriver
    local onEvent = driver and driver.__scripts and driver.__scripts.OnEvent
    if onEvent then
        local ok1, err1 = pcall(onEvent, driver, "ADDON_LOADED", "ForeverPilot")
        H.ok(ok1, "ADDON_LOADED обработан", tostring(err1))
        local ok2, err2 = pcall(onEvent, driver, "PLAYER_LOGIN")
        H.ok(ok2, "PLAYER_LOGIN обработан", tostring(err2))
        H.eq(ns.Bootstrap.ready, true, "аддон готов")
        H.eq(ns.Bootstrap.halted, nil, "и не останавливался")
        H.ok(ns.ActionEngine ~= nil and #(ns.ActionEngine.cards or {}) >= 0,
            "движок на месте")
    end
end

end
