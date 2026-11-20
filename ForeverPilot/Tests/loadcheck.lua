-- ForeverPilot / Tests/loadcheck.lua
--
-- Does every file the .toc lists still compile?
--
-- This is not a unit test, it is a safety net for a specific hazard: the player
-- reloads their interface while the addon folder is being edited. A file left
-- half-written, or with one syntax error, takes the whole addon down and the
-- player sees nothing at all. So after every edit this runs over the .toc in
-- order and reports anything that will not load.
--
-- It only COMPILES each chunk; it does not run it, because the UI files need a
-- live client. A syntax error, an unterminated string or a truncated file are
-- exactly what it catches, and those are the ways an in-progress edit breaks.
--
-- И ВТОРАЯ ПРОВЕРКА, БЕЗ КОТОРОЙ ПЕРВАЯ ОДИН РАЗ УЖЕ СОВРАЛА.
--
-- `loadfile` здесь - это loadfile ТОГО интерпретатора, которым запущен файл, то
-- есть texluajit. LuaJIT принимает расширения Lua 5.2, а клиент игры - Lua 5.1.
-- Из-за этого `goto continue` в Logic\ActionEngine.lua прошёл проверку как «ok»,
-- в игре файл не скомпилировался целиком, и аддон остался без движка: 140
-- ошибок за сессию и красная строка «пересчёт не удался».
--
-- Поэтому рядом с компиляцией стоит лексическая проверка диалекта
-- (Tests/dialect.lua): она ищет синтаксис, которого в Lua 5.1 нет, и ей
-- безразлично, каким интерпретатором её запустили. Тот же набор проверок
-- повторяется в Tests/test_load.lua, чтобы полный прогон тоже за этим следил.
--
-- Run with:  texluajit Tests/loadcheck.lua

local here = debug.getinfo(1, "S").source:sub(2)
local root = here:match("^(.*)[/\\]Tests[/\\]loadcheck%.lua$") or "."
local D = assert(loadfile(root .. "/Tests/dialect.lua"))()

local toc = assert(io.open(root .. "/ForeverPilot.toc", "r"),
    "ForeverPilot.toc не найден рядом с Tests/")

local files, bad, checked = {}, {}, 0
for line in toc:lines() do
    line = line:gsub("\r", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if line ~= "" and not line:match("^#") then
        files[#files + 1] = (line:gsub("\\", "/"))
    end
end
toc:close()

print("ForeverPilot — проверка загружаемости (" .. _VERSION .. ")")
print(string.rep("=", 64))

local wrongDialect = {}
-- ПРЕДЕЛЫ LUA 5.1: предупредить заранее, а не узнать по ошибке в чате.
-- Подробности и сами пределы - в Tests/dialect.lua. Здесь по каждому файлу
-- считается запас, и самый малый запас по каждому пределу печатается в конце.
local nearLimit, overLimit = {}, {}
local worst = {}
for _, key in ipairs(D.LIMIT_ORDER) do worst[key] = { value = -1 } end

for _, rel in ipairs(files) do
    local path = root .. "/" .. rel
    local chunk, err = loadfile(path)
    checked = checked + 1
    -- Диалект проверяется ВСЕГДА, даже если чанк скомпилировался: именно этот
    -- случай - «компилируется здесь, не компилируется в игре» - и был пропущен.
    local found = D.violationsInFile(path) or {}
    local measured = D.limits(path)
    if measured then
        for _, key in ipairs(D.LIMIT_ORDER) do
            if measured[key].value > worst[key].value then
                worst[key] = { value = measured[key].value, rel = rel,
                               name = measured[key].name, line = measured[key].line }
            end
        end
        for _, w in ipairs(measured.warnings) do nearLimit[#nearLimit + 1] = rel .. ": " .. w end
    end
    if chunk and measured and #measured.errors > 0 then
        -- Тоже «компилируется здесь, не компилируется в игре»: предел на
        -- захваченные внешние локальные у texluajit мягче, чем у клиента.
        print(string.format("  ПРЕВЫШЕН ПРЕДЕЛ LUA 5.1 %s", rel))
        for _, e in ipairs(measured.errors) do
            print("         " .. e)
            overLimit[#overLimit + 1] = rel .. ": " .. e
        end
        bad[#bad + 1] = rel
        wrongDialect[#wrongDialect + 1] = rel
    elseif chunk and #found == 0 then
        print(string.format("  ok   %s", rel))
    elseif not chunk then
        print(string.format("  СЛОМАН %s\n         %s", rel, tostring(err)))
        bad[#bad + 1] = rel
    else
        print(string.format("  НЕ ТОТ ДИАЛЕКТ %s", rel))
        for _, v in ipairs(found) do
            print(string.format("         строка %d: %s\n           %s",
                v.line, v.why, v.text))
        end
        bad[#bad + 1] = rel
        wrongDialect[#wrongDialect + 1] = rel
    end
end

-- The test files are not in the .toc and never load in game, but a broken one
-- hides every other test behind it, so they are checked too.
--
-- СПИСОК БЕРЁТСЯ С ДИСКА, А НЕ ИЗ ПАМЯТИ. Раньше здесь были перечислены 23
-- файла, а в папке их уже 38: новые наборы добавлялись, а в этот список - нет,
-- и сломанный новый набор проверка загружаемости не увидела бы. У texluajit
-- есть lfs, так что папка читается как есть; без lfs остаётся прежний
-- перечень - и об этом сказано в итоге, чтобы неполная проверка не выглядела
-- полной.
local extras, extrasFrom = {}, nil
do
    local fs = rawget(_G, "lfs")
    if type(fs) ~= "table" then
        local ok, mod = pcall(require, "lfs")
        if ok and type(mod) == "table" then fs = mod end
    end
    if type(fs) == "table" and type(fs.dir) == "function" then
        local ok = pcall(function()
            for name in fs.dir(root .. "/Tests") do
                if name:match("%.lua$") then extras[#extras + 1] = "Tests/" .. name end
            end
        end)
        if ok and #extras > 0 then
            table.sort(extras)
            extrasFrom = "папка Tests целиком"
        else
            extras = {}
        end
    end
end
if #extras == 0 then
    extras = {
        "Tests/harness.lua", "Tests/uistub.lua", "Tests/dialect.lua",
        "Tests/run.lua", "Tests/one.lua", "Tests/_run_nocap.lua",
        "Tests/test_load.lua",
        "Tests/test_planner.lua", "Tests/test_cost.lua", "Tests/test_stats.lua",
        "Tests/test_rank.lua", "Tests/test_nav.lua", "Tests/test_diag.lua",
        "Tests/test_ui.lua", "Tests/test_regress.lua", "Tests/test_skillcap.lua",
        "Tests/test_bugs.lua", "Tests/test_economy.lua", "Tests/test_assistant.lua",
        "Tests/test_real.lua", "Tests/test_risk.lua", "Tests/test_live.lua",
        "Tests/test_schools.lua", "Tests/test_audit.lua", "Tests/test_swap.lua",
        "Tests/test_alive.lua", "Tests/test_growth.lua", "Tests/test_text.lua",
        "Tests/test_wanted.lua", "Tests/test_ahead.lua", "Tests/test_auction.lua",
        "Tests/test_sources.lua", "Tests/test_arbitrage.lua", "Tests/test_market.lua",
        "Tests/test_favor.lua", "Tests/test_handoff.lua",
        "Tests/test_vanish.lua", "Tests/test_recipe.lua", "Tests/test_confirm.lua",
        "Tests/test_nonsense.lua", "Tests/test_sense.lua",
        "Tests/test_void.lua", "Tests/test_ledger.lua", "Tests/test_ceiling.lua",
        "Tests/test_anyclass.lua",
        "Tests/corpus.lua", "Tests/sense.lua",
        -- Поиск живых SavedVariables: один на все наборы. Сломайся он - и
        -- проверки на настоящих данных пропустятся все сразу, так что
        -- компилируемость его важна ровно настолько же.
        "Tests/paths.lua",
        -- И ИНСТРУМЕНТЫ, А НЕ ТОЛЬКО НАБОРЫ. Эти три в перечне отсутствовали, и
        -- под интерпретатором без lfs (обычный Lua 5.1) они не проверялись
        -- вовсе: 83 файла против 86. Сломанный инструмент осмотра - это
        -- сломанный способ проверить работу, то есть именно то, чем этот файл
        -- и занимается.
        "Tests/loadcheck.lua", "Tests/inspect_real.lua", "Tests/dump_wanted.lua",
        "Tests/inspect_ledger.lua",
    }
    extrasFrom = "заученный перечень (lfs недоступен — новые файлы могли в него не попасть)"
end
local missing = {}
for _, rel in ipairs(extras) do
    local f = io.open(root .. "/" .. rel, "r")
    if not f then
        missing[#missing + 1] = rel
    else
        f:close()
        local chunk, err = loadfile(root .. "/" .. rel)
        checked = checked + 1
        if not chunk then
            print(string.format("  СЛОМАН %s\n         %s", rel, tostring(err)))
            bad[#bad + 1] = rel
        end
    end
end

print(string.rep("-", 64))
print(string.format("Проверено файлов: %d, сломанных: %d", checked, #bad))
print("Файлы тестов: " .. tostring(extrasFrom) .. ", " .. #extras .. " шт.")
if #missing > 0 then
    print("Нет на диске (это нормально, если набор ещё не создан): "
        .. table.concat(missing, ", "))
end
if #bad > 0 then
    print("")
    print("АДДОН НЕ ЗАГРУЗИТСЯ. Сломаны:")
    for _, rel in ipairs(bad) do print("  * " .. rel) end
end
if #wrongDialect > 0 then
    print("")
    print("ВАЖНО: эти файлы компилируются здесь, но НЕ в игре — клиент это"
        .. " Lua 5.1. Проверять их через texluajit бесполезно.")
end

-- Запас до пределов Lua 5.1. Печатается всегда, а не только при тревоге:
-- приближение должно быть видно по числам от прогона к прогону.
print("")
print("Запас до пределов Lua 5.1 (самое большое значение среди файлов аддона):")
for _, key in ipairs(D.LIMIT_ORDER) do
    local w, spec = worst[key], D.LIMITS[key]
    if w.value >= 0 then
        print(string.format("  %-9s %6d из %-6d (%2d%%)  %s%s", key, w.value, spec.limit,
            math.floor(w.value / spec.limit * 100 + 0.5), tostring(w.rel),
            w.name and (" — " .. tostring(w.name) .. ", строка " .. tostring(w.line)) or ""))
    end
end
if #nearLimit > 0 then
    print("")
    print("ПРЕДУПРЕЖДЕНИЕ: до предела осталось меньше "
        .. math.floor((1 - D.WARN_SHARE) * 100 + 0.5) .. "%. Файл ещё грузится, но"
        .. " следующая правка может это изменить:")
    for _, line in ipairs(nearLimit) do print("  ! " .. line) end
else
    print("  ни один файл не подошёл к пределу ближе чем на "
        .. math.floor((1 - D.WARN_SHARE) * 100 + 0.5) .. "%")
end
print(string.rep("-", 64))
os.exit(#bad == 0 and 0 or 1)
