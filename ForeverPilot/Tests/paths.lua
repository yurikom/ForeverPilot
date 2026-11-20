-- ForeverPilot / Tests/paths.lua
--
-- ГДЕ ЛЕЖАТ ЖИВЫЕ SavedVariables. ОДИН ОТВЕТ НА ВЕСЬ ПРОЕКТ.
--
-- Проверки «на настоящих данных» читают файлы из папки WTF того, кто играет:
-- кеш рецептов Mastercraft, инвентарь Syndicator, суточные слепки цен самого
-- аддона. Путь к этой папке зависит от машины, и раньше он был вписан в код
-- четырёх файлов - шестью строками с ИМЕНЕМ АККАУНТА ИГРОКА внутри. Это и
-- неверно по сути (имя аккаунта - личные данные, а исходники публичные), и
-- ломается четырьмя способами: правка в одном месте, три забытых.
--
-- Поэтому вопрос задаётся здесь, и только здесь.
--
-- ПОРЯДОК ОТВЕТОВ:
--
--   1. FP_WTF      - полный путь к папке SavedVariables аккаунта;
--   2. FP_ACCOUNT  - только имя папки аккаунта, саму WTF ищем рядом с аддоном;
--   3. Tests/local_paths.lua - те же значения файлом, для того, кто не хочет
--      каждый раз выставлять переменные. Файл в git НЕ ПОПАДАЕТ
--      (см. .gitignore): он для одной машины и содержит имя аккаунта.
--
-- ЕСЛИ НЕ ОТВЕТИЛ НИКТО - возвращается ok = false и причина словами, а наборы
-- обязаны её НАПЕЧАТАТЬ и пропуститься явно. Молча проверять ничего нельзя:
-- именно так `run.lua real` однажды тихо не запускал 31 раздел и выглядел
-- зелёным. Поэтому здесь нет значения по умолчанию и нет «а вдруг повезёт».
--
-- ПЕРЕЧИСЛЕНИЕМ ПАПОК ТУТ НЕ ПОЛЬЗУЮТСЯ, И ЭТО НЕ ЛЕНЬ.
--
-- Угадать имя аккаунта чтением каталога нельзя: под настоящим PUC Lua 5.1
-- (Tests/run_puc51.py - тот же интерпретатор, что в клиенте) io.popen ЕСТЬ, но
-- на вызове отвечает «'popen' not supported», а lfs там нет вовсе. На этом уже
-- падал целиком test_skillcap. Так что имя аккаунта приходит только снаружи -
-- из переменной окружения или из local_paths.lua.

local P = {}

-- Папка WTF относительно корня аддона. Аддон стоит в
-- <игра>/Interface/AddOns/ForeverPilot, то есть WTF - три уровня вверх; два
-- других варианта - когда папки смонтированы рядом, а не вложенно (так лежит
-- песочница). Абсолютного пути к одной конкретной машине здесь нет сознательно:
-- он протухает при первом же переносе папки, и тогда набор молча проверяет
-- пустоту.
P.WTF_RELATIVE = { "/../../..", "/..", "/../.." }

-- По какому файлу понятно, что папка - та самая. Кеш рецептов Mastercraft:
-- без него наборам на настоящих данных нечего делать, они на нём и
-- останавливаются первым же утверждением.
P.PROBE = "Mastercraft.lua"

local function trim(s)
    return (tostring(s):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function nonEmpty(s)
    if type(s) ~= "string" then return nil end
    s = trim(s)
    if s == "" then return nil end
    return s
end

local function env(name)
    return nonEmpty(os.getenv(name))
end

local function exists(path)
    local f = io.open(path, "r")
    if not f then return false end
    f:close()
    return true
end

-- Tests/local_paths.lua ---------------------------------------------------
--
-- Читается как данные, а не как код проекта: отдельное окружение, никаких
-- глобальных переменных наружу. Файла может не быть - это нормальный случай, а
-- не ошибка: в публичном репозитории его нет.
--
-- Что в нём можно написать:
--
--   return {
--       account = "ИМЯ_ПАПКИ_АККАУНТА",
--       wtf     = "<...>/WTF/Account/ИМЯ/SavedVariables",  -- не обязательно
--       chars   = { "93/Имя-Фамилия", "93/Имя-Фамилия2" },
--   }
local function loadLocal(dir)
    local path = dir .. "/local_paths.lua"
    local chunk = loadfile(path)
    if not chunk then return nil, path end
    setfenv(chunk, setmetatable({}, { __index = function() return nil end }))
    local ok, value = pcall(chunk)
    if not ok or type(value) ~= "table" then return nil, path end
    return value, path
end

-- Где лежит этот файл, то есть папка Tests.
P.DIR = (function()
    local src = debug.getinfo(1, "S").source:sub(2)
    return src:match("^(.*)[/\\]paths%.lua$") or "."
end)()

function P.localConfig()
    if P._localChecked then return P._local end
    P._localChecked = true
    P._local = (loadLocal(P.DIR))
    return P._local
end

-- Главный ответ -----------------------------------------------------------
--
-- root - корень аддона (H.ROOT). Возвращается таблица:
--
--   ok             - нашли или нет;
--   savedVariables - папка SavedVariables аккаунта (когда ok);
--   accountRoot    - <...>/Account/<аккаунт> (когда его видно из пути);
--   account        - имя папки аккаунта, если мы его знаем;
--   source         - кто ответил: "FP_WTF" / "FP_ACCOUNT" / "local_paths.lua";
--   tried          - все проверенные пути, по порядку;
--   reason         - почему не нашли, словами (когда not ok).
function P.resolve(root)
    root = root or "."
    local tried, sources = {}, {}
    local cfg = P.localConfig()

    local function addDir(dir, source, account)
        if not dir then return end
        dir = (tostring(dir):gsub("[/\\]+$", ""))
        tried[#tried + 1] = dir
        sources[dir] = { source = source, account = account }
    end

    local function addAccount(account, source)
        for _, up in ipairs(P.WTF_RELATIVE) do
            addDir(root .. up .. "/WTF/Account/" .. account .. "/SavedVariables",
                source, account)
        end
    end

    -- 1. FP_WTF - готовый путь, спрашивать больше нечего.
    local wtf = env("FP_WTF")
    if wtf then addDir(wtf, "FP_WTF", nil) end

    -- 2. FP_ACCOUNT - имя папки, WTF ищем рядом с аддоном.
    local account = env("FP_ACCOUNT")
    if account then addAccount(account, "FP_ACCOUNT") end

    -- 3. local_paths.lua - то же самое файлом.
    if cfg then
        if nonEmpty(cfg.wtf) then addDir(cfg.wtf, "local_paths.lua", nonEmpty(cfg.account)) end
        if nonEmpty(cfg.account) then addAccount(nonEmpty(cfg.account), "local_paths.lua") end
    end

    for _, dir in ipairs(tried) do
        if exists(dir .. "/" .. P.PROBE) then
            local meta = sources[dir] or {}
            local accountRoot, name = dir:match("^(.*[/\\]Account[/\\]([^/\\]+))[/\\]SavedVariables$")
            return {
                ok = true,
                savedVariables = dir,
                accountRoot = accountRoot,
                account = meta.account or name,
                source = meta.source,
                tried = tried,
            }
        end
    end

    return {
        ok = false,
        tried = tried,
        reason = P.reasonText(tried, cfg),
    }
end

-- ПОЧЕМУ НЕ НАШЛИ - ОДНИМ АБЗАЦЕМ, КОТОРЫЙ МОЖНО НАПЕЧАТАТЬ.
--
-- Текст сознательно говорит не только «нет», но и что сделать: иначе пропуск
-- выглядит как поломка, а поломка - как пропуск.
function P.reasonText(tried, cfg)
    local parts = {}
    parts[#parts + 1] = "живых SavedVariables не нашли:"
    if not env("FP_WTF") then
        parts[#parts + 1] = " FP_WTF не задан;"
    else
        parts[#parts + 1] = " FP_WTF задан, но " .. P.PROBE .. " там нет;"
    end
    if not env("FP_ACCOUNT") then
        parts[#parts + 1] = " FP_ACCOUNT не задан;"
    else
        parts[#parts + 1] = " по FP_ACCOUNT папка не нашлась;"
    end
    if not cfg then
        parts[#parts + 1] = " Tests/local_paths.lua нет (он в .gitignore и для каждой машины свой);"
    else
        parts[#parts + 1] = " Tests/local_paths.lua прочитан, но путь из него не подошёл;"
    end
    parts[#parts + 1] = " проверено путей: " .. #(tried or {}) .. "."
    parts[#parts + 1] = " Задайте FP_WTF=<...>/WTF/Account/<аккаунт>/SavedVariables"
        .. " или FP_ACCOUNT=<аккаунт>, либо создайте Tests/local_paths.lua"
        .. " (образец - в шапке Tests/paths.lua)."
    return table.concat(parts)
end

-- Удобная обёртка: папка или nil и причина.
function P.savedVariables(root)
    local info = P.resolve(root)
    if info.ok then return info.savedVariables, info end
    return nil, info
end

-- Папки персонажей --------------------------------------------------------
--
-- Внутри аккаунта персонаж лежит как <аккаунт>/<реалм>/<Имя-Фамилия>, и
-- «реалм» - это номер вроде 93. Ни имени папки персонажа, ни номера реалма
-- перечислением каталога не узнать (см. шапку), поэтому список берётся из
-- local_paths.lua, а номер реалма - из префиксов этого же списка. Так в коде не
-- остаётся ни имён персонажей, ни номеров.
--
-- preferred - папка, которую стоит попробовать первой (обычно «Имя-Фамилия»
-- того персонажа, которого как раз смотрим). Префикса реалма у неё нет, поэтому
-- она пробуется со всеми известными префиксами и без них.
function P.characterFiles(info, preferred, file)
    file = file or "ForeverPilot.lua"
    local cfg = P.localConfig() or {}
    local list, out, seen = {}, {}, {}

    local realms, haveRealm = {}, {}
    local function addRealm(r)
        r = nonEmpty(r)
        if r and not haveRealm[r] then haveRealm[r] = true; realms[#realms + 1] = r end
    end
    local fromEnv = env("FP_REALM")
    if fromEnv then
        for piece in fromEnv:gmatch("[^,]+") do addRealm(piece) end
    end
    for _, entry in ipairs(cfg.chars or {}) do
        addRealm(tostring(entry):match("^([^/\\]+)[/\\]"))
    end

    local function add(rel)
        rel = nonEmpty(rel)
        if not rel then return end
        if rel:find("[/\\]") then
            list[#list + 1] = rel
        else
            -- Без префикса: со всеми известными реалмами и без реалма вовсе.
            for _, r in ipairs(realms) do list[#list + 1] = r .. "/" .. rel end
            list[#list + 1] = rel
        end
    end

    add(preferred)
    for _, entry in ipairs(cfg.chars or {}) do add(entry) end

    local base = info and info.accountRoot
    if not base and info and info.savedVariables then
        base = info.savedVariables:match("^(.*)[/\\]SavedVariables$")
    end
    if not base then return out end

    for _, rel in ipairs(list) do
        local path = base .. "/" .. rel .. "/SavedVariables/" .. file
        if not seen[path] then
            seen[path] = true
            out[#out + 1] = { path = path, folder = (rel:gsub("^[^/\\]+[/\\]", "")), rel = rel }
        end
    end
    return out
end

return P
