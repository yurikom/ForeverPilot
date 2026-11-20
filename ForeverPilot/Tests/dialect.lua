-- ForeverPilot / Tests/dialect.lua
--
-- ДИАЛЕКТ ИГРЫ - LUA 5.1. ДИАЛЕКТ ТЕСТОВ - НЕТ.
--
-- Тесты и проверка загружаемости гоняются через texluajit, а LuaJIT принимает
-- расширения Lua 5.2: `goto`, метки `::имя::`, и ещё несколько вещей, которых в
-- клиенте нет вовсе. Поэтому `loadfile` в тестах говорил «ok» про файл, который
-- игра прочитать не может.
--
-- Так и случилось: в Logic\ActionEngine.lua стоял `goto continue`. Файл не
-- компилировался в игре, вместе с ним не выполнялось `ns.ActionEngine = Engine`,
-- и за одну сессию игрок получил 140 ошибок «attempt to index field
-- 'ActionEngine' (a nil value)». Все 46 файлов при этом «проходили проверку».
--
-- Этот модуль читает файл как текст и ищет синтаксис, которого в Lua 5.1 нет.
-- Проверка лексическая, а не компиляцией, и это сознательно: заставить LuaJIT
-- отвергнуть `goto` нельзя, а другого интерпретатора у набора тестов нет.
-- Строки и комментарии вырезаются ДО поиска, иначе слово в комментарии - а в
-- этом файле оно есть - считалось бы нарушением.

local D = {}

-- Вырезать комментарии и строковые литералы, сохранив переводы строк, чтобы
-- номер строки у находки остался настоящим.
--
-- Разбор идёт посимвольно, а не паттернами: длинные скобки [[...]] и [==[...]==]
-- и экранированные кавычки паттернами не разбираются, а именно в них проще
-- всего спрятать и ложное срабатывание, и настоящее нарушение.
function D.stripped(src)
    local out, i, n = {}, 1, #src
    local function keepNewlines(chunk)
        out[#out + 1] = (chunk:gsub("[^\n]", " "))
    end
    while i <= n do
        local c = src:sub(i, i)
        local two = src:sub(i, i + 1)

        -- Длинная скобка: [[ ]] или [=[ ]=] и так далее.
        local eq = src:match("^%[(=*)%[", i)
        local isComment = (two == "--")
        local commentEq = isComment and src:match("^%-%-%[(=*)%[", i) or nil

        if isComment and commentEq then
            local close = "]" .. commentEq .. "]"
            local stop = src:find(close, i + 4 + #commentEq, true)
            local last = stop and (stop + #close - 1) or n
            keepNewlines(src:sub(i, last))
            i = last + 1
        elseif isComment then
            local stop = src:find("\n", i, true) or (n + 1)
            keepNewlines(src:sub(i, stop - 1))
            i = stop
        elseif eq then
            local close = "]" .. eq .. "]"
            local stop = src:find(close, i + 2 + #eq, true)
            local last = stop and (stop + #close - 1) or n
            keepNewlines(src:sub(i, last))
            i = last + 1
        elseif c == '"' or c == "'" then
            local j = i + 1
            while j <= n do
                local ch = src:sub(j, j)
                if ch == "\\" then
                    j = j + 2
                elseif ch == c then
                    j = j + 1
                    break
                elseif ch == "\n" then
                    break
                else
                    j = j + 1
                end
            end
            keepNewlines(src:sub(i, j - 1))
            i = j
        else
            out[#out + 1] = c
            i = i + 1
        end
    end
    return table.concat(out)
end

-- Синтаксис, которого в Lua 5.1 нет. Каждому - своё объяснение словами: в
-- отчёте должно быть видно не только «нельзя», но и почему.
D.RULES = {
    { pattern = "%f[%w_]goto%f[^%w_]",
      why = "`goto` появился в Lua 5.2; клиент игры — Lua 5.1" },
    { pattern = "::%s*[%a_][%w_]*%s*::",
      why = "метки `::имя::` появились в Lua 5.2; клиент игры — Lua 5.1" },
    { pattern = "[^/]//[^/]",
      why = "целочисленное деление `//` появилось в Lua 5.3" },
    { pattern = "%f[%w_]continue%f[^%w_]",
      why = "`continue` не ключевое слово ни в одной версии Lua" },
    { pattern = "<<",
      why = "побитовый сдвиг `<<` появился в Lua 5.3" },
    { pattern = ">>",
      why = "побитовый сдвиг `>>` появился в Lua 5.3" },
    { pattern = "%f[%w_]table%.pack%f[^%w_]",
      why = "table.pack появился в Lua 5.2; в клиенте его нет" },
    { pattern = "%f[%w_]table%.unpack%f[^%w_]",
      why = "table.unpack появился в Lua 5.2; в клиенте только глобальный unpack" },
    { pattern = "%f[%w_]math%.type%f[^%w_]",
      why = "math.type появился в Lua 5.3" },
    { pattern = "%f[%w_]bit32%f[^%w_]",
      why = "библиотека bit32 появилась в Lua 5.2; в клиенте её нет" },
    { pattern = "\\z",
      why = "экранирование `\\z` появилось в Lua 5.2" },
}

-- Найденные нарушения в одном тексте: { line, rule, why, text }
function D.violations(src)
    local code = D.stripped(src)
    local found = {}
    for _, rule in ipairs(D.RULES) do
        local from = 1
        while true do
            local s, e = code:find(rule.pattern, from)
            if not s then break end
            -- Номер строки: считаем переводы строк до находки.
            local _, lineNo = code:sub(1, s):gsub("\n", "")
            found[#found + 1] = {
                line = lineNo + 1,
                why = rule.why,
                text = (code:sub(math.max(1, s - 20), e + 20):gsub("%s+", " ")),
            }
            from = e + 1
        end
    end
    table.sort(found, function(a, b)
        if a.line ~= b.line then return a.line < b.line end
        return a.why < b.why
    end)
    return found
end

function D.violationsInFile(path)
    local f = io.open(path, "rb")
    if not f then return nil, "файл не открылся: " .. tostring(path) end
    local src = f:read("*a")
    f:close()
    return D.violations(src)
end

-- Файлы из .toc, в порядке загрузки, пути уже с косой чертой.
function D.tocFiles(root)
    local toc = io.open(root .. "/ForeverPilot.toc", "r")
    if not toc then return nil, "ForeverPilot.toc не найден" end
    local out = {}
    for line in toc:lines() do
        line = line:gsub("\r", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" and not line:match("^#") then
            out[#out + 1] = (line:gsub("\\", "/"))
        end
    end
    toc:close()
    return out
end

-- ПРЕДЕЛЫ LUA 5.1, К КОТОРЫМ МОЖНО ПОДОЙТИ МОЛЧА ------------------------
--
-- Повод был такой: аддон не загрузился, и первой версией стало «клиент
-- отказывается от слишком большого файла». Версия не подтвердилась - файл на
-- 181 КБ грузится, а падал файл на 146 КБ из-за двух строк синтаксиса. Но сам
-- вопрос справедливый: у Lua 5.1 есть жёсткие пределы, и упереться в них можно
-- без предупреждения. Тогда файл перестаёт компилироваться целиком, а игрок
-- видит то же самое, что видел в этот раз.
--
-- Размер файла в байтах и строках пределом НЕ является. Настоящие пределы:
--
--   locals    200     локальных переменных, одновременно живых в одной функции
--                     (LUAI_MAXVARS). «Функция» - это и сам файл: всё, что
--                     объявлено через local на верхнем уровне, считается сюда.
--                     Большой файл упирается именно в это.
--   upvalues  60      внешних локальных, которые одна функция захватывает из
--                     охватывающих (LUAI_MAXUPVALUES).
--   constants 262144  разных констант (строк и чисел) в одной функции
--                     (MAXARG_Bx). Актуально для файлов с данными.
--   depth     200     вложенных уровней синтаксиса (LUAI_MAXCCALLS).
--
-- Оценки здесь - СВЕРХУ: считаются все объявления в функции, а не только
-- одновременно живые, и все имена внешних локальных, без учёта порядка и
-- перекрытий. Поэтому «ниже порога» значит «точно безопасно», а «выше порога»
-- - «пора посмотреть», и для этого порог предупреждения стоит на 80% предела.
-- Самопроверка в Tests/test_load.lua сверяет оценку с тем, что на границе
-- говорит сам интерпретатор (у LuaJIT пределы на local и upvalue те же).

D.LIMITS = {
    locals    = { limit = 200,
        what = "локальных переменных в одной функции (верхний уровень файла — тоже функция)" },
    upvalues  = { limit = 60,
        what = "внешних локальных, захваченных одной функцией" },
    constants = { limit = 262144,
        what = "разных констант (строк и чисел) в файле" },
    depth     = { limit = 200,
        what = "вложенных уровней синтаксиса" },
}
-- Порядок, в котором пределы перечисляются в отчётах.
D.LIMIT_ORDER = { "locals", "upvalues", "constants", "depth" }
-- С какой доли предела предупреждать.
D.WARN_SHARE = 0.8

local KEYWORDS = {}
for _, kw in ipairs({ "and", "break", "do", "else", "elseif", "end", "false", "for",
    "function", "if", "in", "local", "nil", "not", "or", "repeat", "return", "then",
    "true", "until", "while" }) do KEYWORDS[kw] = true end

-- Разбить исходник на лексемы: { t = "kw"|"name"|"str"|"num"|"sym", v, line }.
-- Комментарии выбрасываются, строки остаются одной лексемой.
function D.tokens(src)
    local out, i, n, line = {}, 1, #src, 1
    local function push(t, v) out[#out + 1] = { t = t, v = v, line = line } end
    local function countLines(chunk)
        local _, c = chunk:gsub("\n", "")
        line = line + c
    end
    while i <= n do
        local c = src:sub(i, i)
        if c == "\n" then
            line = line + 1; i = i + 1
        elseif c:match("%s") then
            i = i + 1
        elseif src:sub(i, i + 1) == "--" then
            local eq = src:match("^%-%-%[(=*)%[", i)
            if eq then
                local close = "]" .. eq .. "]"
                local stop = src:find(close, i + 4 + #eq, true)
                local last = stop and (stop + #close - 1) or n
                countLines(src:sub(i, last))
                i = last + 1
            else
                local stop = src:find("\n", i, true) or (n + 1)
                i = stop
            end
        elseif src:match("^%[=*%[", i) then
            local eq = src:match("^%[(=*)%[", i)
            local close = "]" .. eq .. "]"
            local stop = src:find(close, i + 2 + #eq, true)
            local last = stop and (stop + #close - 1) or n
            local body = src:sub(i, last)
            push("str", body)
            countLines(body)
            i = last + 1
        elseif c == '"' or c == "'" then
            local j = i + 1
            while j <= n do
                local ch = src:sub(j, j)
                if ch == "\\" then j = j + 2
                elseif ch == c then break
                elseif ch == "\n" then break
                else j = j + 1 end
            end
            local body = src:sub(i, j)
            push("str", body)
            countLines(body)
            i = j + 1
        elseif c:match("%d") or (c == "." and src:sub(i + 1, i + 1):match("%d")) then
            local num = src:match("^0[xX]%x+", i)
                or src:match("^%d+%.?%d*[eE][%+%-]?%d+", i)
                or src:match("^%d+%.?%d*", i)
                or src:match("^%.%d+[eE][%+%-]?%d+", i)
                or src:match("^%.%d+", i)
            push("num", num)
            i = i + #num
        elseif c:match("[%a_]") then
            local name = src:match("^[%a_][%w_]*", i)
            push(KEYWORDS[name] and "kw" or "name", name)
            i = i + #name
        else
            local three, two = src:sub(i, i + 2), src:sub(i, i + 1)
            if three == "..." then push("sym", three); i = i + 3
            elseif two == ".." or two == "==" or two == "~=" or two == "<=" or two == ">=" then
                push("sym", two); i = i + 2
            else
                push("sym", c); i = i + 1
            end
        end
    end
    return out
end

-- Посчитать по исходнику то, что упирается в пределы. Возвращает таблицу:
--   locals    = { value, line, name }  - самая «локальная» функция
--   upvalues  = { value, line, name }  - функция с наибольшим числом захватов
--   constants = { value }              - разных констант в файле
--   depth     = { value, line }        - наибольшая вложенность
--   mainLocals                         - локальных на верхнем уровне файла
function D.measure(src)
    local toks = D.tokens(src)
    local scopes = { { name = "верхний уровень файла", line = 1, names = {},
                       declared = 0, upvalues = {}, nUp = 0, openDepth = 0 } }
    local depth, braces = 0, 0
    local best = {
        locals = { value = 0, line = 1, name = "верхний уровень файла" },
        upvalues = { value = 0, line = 1, name = "—" },
        depth = { value = 0, line = 1 },
    }
    local constants, nConst = {}, 0

    local function declare(scope, name)
        if not scope.names[name] then
            scope.names[name] = true
        end
        -- Считаются объявления, а не разные имена: `local x` в двух ветках -
        -- две переменные, хоть и с одним именем.
        scope.declared = scope.declared + 1
    end
    local function finish(scope)
        if scope.declared > best.locals.value then
            best.locals = { value = scope.declared, line = scope.line, name = scope.name }
        end
        if scope.nUp > best.upvalues.value then
            best.upvalues = { value = scope.nUp, line = scope.line, name = scope.name }
        end
    end
    local function open(line)
        depth = depth + 1
        if depth > best.depth.value then best.depth = { value = depth, line = line } end
    end

    local i = 1
    while i <= #toks do
        local tk = toks[i]
        local top = scopes[#scopes]
        if tk.t == "str" or tk.t == "num" then
            local key = tk.t .. ":" .. tk.v
            if not constants[key] then constants[key] = true; nConst = nConst + 1 end
        elseif tk.t == "sym" then
            if tk.v == "{" then braces = braces + 1
            elseif tk.v == "}" then braces = math.max(0, braces - 1) end
        elseif tk.t == "kw" then
            if tk.v == "function" then
                -- Имя до скобки: `function a.b:c(` или безымянная `function(`.
                local j, parts, isMethod = i + 1, {}, false
                while toks[j] and not (toks[j].t == "sym" and toks[j].v == "(") do
                    if toks[j].t == "sym" and toks[j].v == ":" then isMethod = true end
                    parts[#parts + 1] = toks[j].v
                    j = j + 1
                end
                local scope = {
                    name = (#parts > 0) and table.concat(parts) or "безымянная функция",
                    line = tk.line, names = {}, declared = 0, upvalues = {}, nUp = 0,
                    openDepth = depth + 1,
                }
                open(tk.line)
                if isMethod then declare(scope, "self") end
                -- Параметры.
                j = j + 1
                while toks[j] and not (toks[j].t == "sym" and toks[j].v == ")") do
                    if toks[j].t == "name" then declare(scope, toks[j].v) end
                    j = j + 1
                end
                scopes[#scopes + 1] = scope
                i = j
            elseif tk.v == "do" or tk.v == "if" or tk.v == "repeat" then
                open(tk.line)
            elseif tk.v == "end" or tk.v == "until" then
                if #scopes > 1 and top.openDepth == depth then
                    finish(top)
                    scopes[#scopes] = nil
                end
                depth = math.max(0, depth - 1)
            elseif tk.v == "local" then
                local nxt = toks[i + 1]
                if nxt and nxt.t == "kw" and nxt.v == "function" then
                    -- Имя локальной функции объявлено в охватывающей функции.
                    if toks[i + 2] and toks[i + 2].t == "name" then
                        declare(top, toks[i + 2].v)
                    end
                else
                    local j = i + 1
                    while toks[j] and toks[j].t == "name" do
                        declare(top, toks[j].v)
                        if toks[j + 1] and toks[j + 1].t == "sym" and toks[j + 1].v == "," then
                            j = j + 2
                        else
                            j = j + 1
                            break
                        end
                    end
                    i = j - 1
                end
            elseif tk.v == "for" then
                local j = i + 1
                while toks[j] and toks[j].t == "name" do
                    declare(top, toks[j].v)
                    if toks[j + 1] and toks[j + 1].t == "sym" and toks[j + 1].v == "," then
                        j = j + 2
                    else
                        j = j + 1
                        break
                    end
                end
                i = j - 1
            end
        elseif tk.t == "name" then
            local prev, nxt = toks[i - 1], toks[i + 1]
            local isField = prev and prev.t == "sym" and (prev.v == "." or prev.v == ":")
            -- `имя =` внутри фигурных скобок - ключ таблицы, а не переменная.
            local isKey = braces > 0 and nxt and nxt.t == "sym" and nxt.v == "="
                and prev and prev.t == "sym" and (prev.v == "{" or prev.v == "," or prev.v == ";")
            if not isField and not isKey then
                for s = #scopes, 1, -1 do
                    if scopes[s].names[tk.v] then
                        -- Объявлено снаружи: захватывает и эта функция, и все
                        -- промежуточные - замыкание тянется через каждую.
                        for k = s + 1, #scopes do
                            if not scopes[k].upvalues[tk.v] then
                                scopes[k].upvalues[tk.v] = true
                                scopes[k].nUp = scopes[k].nUp + 1
                            end
                        end
                        break
                    end
                end
            end
        end
        i = i + 1
    end
    for s = #scopes, 1, -1 do finish(scopes[s]) end

    local lines = 1
    for _ in src:gmatch("\n") do lines = lines + 1 end
    return {
        bytes = #src, lines = lines,
        mainLocals = scopes[1].declared,
        locals = best.locals, upvalues = best.upvalues,
        constants = { value = nConst },
        depth = best.depth,
    }
end

-- Оценить исходник против пределов. Возвращает measure + два списка строк:
--   warnings - подошли к пределу ближе, чем на D.WARN_SHARE
--   errors   - оценка ПРЕВЫСИЛА предел: такой файл клиент не скомпилирует
--
-- Ровно на пределе - ещё не ошибка: 200 локальных Lua 5.1 принимает, 201 уже
-- нет. Это сверено с настоящим интерпретатором, см. самопроверку в test_load.
function D.limitsOfSource(src)
    local m = D.measure(src)
    m.warnings, m.errors = {}, {}
    for _, key in ipairs(D.LIMIT_ORDER) do
        local spec, got = D.LIMITS[key], m[key]
        local value = got and got.value or 0
        local where = ""
        if got and got.name and got.line then
            where = " — " .. tostring(got.name) .. ", строка " .. tostring(got.line)
        elseif got and got.line then
            where = " — строка " .. tostring(got.line)
        end
        local text = string.format("%d при пределе %d %s%s", value, spec.limit, spec.what, where)
        if value > spec.limit then
            m.errors[#m.errors + 1] = text
        elseif value >= spec.limit * D.WARN_SHARE then
            m.warnings[#m.warnings + 1] = text
        end
    end
    return m
end

function D.limits(path)
    local f = io.open(path, "rb")
    if not f then return nil, "файл не открылся: " .. tostring(path) end
    local src = f:read("*a")
    f:close()
    return D.limitsOfSource(src)
end

-- Прежнее имя, под которым этот расчёт звали до появления D.limits.
function D.chunkStats(path)
    local m = D.limits(path)
    if not m then return nil end
    return { bytes = m.bytes, lines = m.lines, maxLocalsPerFunction = m.locals.value }
end
D.MAX_LOCALS_PER_FUNCTION = D.LIMITS.locals.limit

return D
