-- ForeverPilot / Tests/inspect_ledger.lua
--
-- ПОСМОТРЕТЬ НА СВОЮ КНИГУ ЗАКУПОК И НА СЛОВАРЬ ПУСТОТЫ ГЛАЗАМИ - на
-- настоящих сохранённых данных игрока, без игры.
--
-- Это не тест: он ничего не утверждает и ничего не возвращает коду. Он нужен
-- для одного - чтобы человек увидел, что получается, прежде чем поверить
-- четырём тысячам «ok». Числа в книге закупок - это деньги игрока, и смотреть
-- на них надо глазами хотя бы один раз.
--
-- Мир собирается ТЕМ ЖЕ скриптом, которым его смотрит человек
-- (Tests/inspect_real.lua): второго описания «как собрать настоящий мир без
-- игры» в проекте нет, и заводить второе нельзя - разойдутся.
--
-- Run with:  texluajit Tests/inspect_ledger.lua

local here = debug.getinfo(1, "S").source:sub(2)
local dir = here:match("^(.*)[/\\]inspect_ledger%.lua$") or "."
local ROOT = dir:match("^(.*)[/\\]Tests$") or "."
local H = assert(loadfile(dir .. "/harness.lua"))()

-- Настоящий мир, собранный скриптом осмотра -----------------------------

local function realWorld()
    local chunk = assert(loadfile(dir .. "/inspect_real.lua"),
        "нет Tests/inspect_real.lua")
    local captured
    local proxyH = setmetatable({
        load = function(opts)
            local env = H.load(opts)
            captured = captured or env
            return env
        end,
    }, { __index = H })
    local osProxy = setmetatable({ exit = function() error("выход", 0) end },
        { __index = os })
    local sandbox = setmetatable({
        print = function() end,
        os = osProxy,
        io = setmetatable({ write = function() end }, { __index = io }),
        loadfile = function(p, ...)
            if type(p) == "string" and p:match("[/\\]harness%.lua$") then
                return function() return proxyH end
            end
            return loadfile(p, ...)
        end,
    }, { __index = _G })
    setfenv(chunk, sandbox)
    pcall(chunk)
    return captured
end

local env = realWorld()
if not env then
    print("!! настоящий мир собрать не удалось — нет сохранённых данных игрока")
    os.exit(1)
end
local ns = env.ns
local U = ns.Util
local L = ns.Ledger

local function line(ch) print(string.rep(ch or "-", 72)) end
local function head(text)
    print("")
    line("=")
    print(text)
    line("=")
end

print("ForeverPilot — книга закупок и словарь пустоты на настоящих данных ("
    .. _VERSION .. ")")
print("персонаж: " .. tostring(env.player.name) .. " "
    .. tostring(env.player.surname or "") .. ", " .. tostring(env.player.level)
    .. " ур., " .. U.money(env.money or 0))
print("база предметов: " .. H.itemDBSourceText())

-- 1. СЛОВАРЬ ПУСТОТЫ ----------------------------------------------------

head("1. Четыре состояния пустоты: как они выглядят рядом")
print(string.format("  %-14s %-12s %s", "состояние", "на экране", "словами"))
line()
for _, key in ipairs({ "IMPOSSIBLE", "UNKNOWN", "NO_PRICE" }) do
    print(string.format("  %-14s %-12s %s", key, ns.VOID_TEXT[key], ns.VOID_WHY[key]))
end
print(string.format("  %-14s %-12s %s", "ESTIMATE",
    U.priceText(2500, ns.CONF.ESTIMATE, 7200), "число есть, но посчитано мной"))
print("")
print("  одна и та же цена при разном возрасте:")
for _, age in ipairs({ 10, 600, 90000, 400000 }) do
    print("    " .. U.priceText(25081, ns.CONF.CACHED, age))
end
print("    " .. U.priceText(25081, ns.CONF.CACHED, nil) .. "   <- возраста нет")
print("    " .. U.priceText(300, ns.CONF.EXACT, false) .. "   <- цена торговца")

-- 2. КНИГА ЗАКУПОК НА СТАРТЕ --------------------------------------------

head("2. Своя книга закупок на настоящих сохранениях игрока")
local rep = L:Report()
print("  записей: " .. rep.entries .. ", предметов: " .. rep.items
    .. ", отказов сверки: " .. rep.skipped)
print("  " .. L:Headline())
print("")
print("  чего книга не видит:")
for _, gap in ipairs(rep.gaps) do
    print("    - " .. gap)
end
print("")
print("  нужные ей события — есть ли они на этом клиенте:")
for _, e in ipairs(select(1, L:EventHealth())) do
    print(string.format("    %-42s есть: %-14s подписаны: %s",
        e.event,
        (e.exists == nil) and "проверить нечем" or tostring(e.exists),
        tostring(e.subscribed)))
end

-- 3. ЧТО СЧИТАЕТСЯ БЕЗ КНИГИ -------------------------------------------

local function learnedWithOutput(limit)
    local out = {}
    for _, prof in ipairs(ns.CharacterScanner:CraftingProfessions()) do
        local bucket = ns.RecipeBook:Bucket(prof.name)
        for _, r in ipairs((bucket and bucket.list) or {}) do
            if r.learned and r.output and #(ns.RecipeBook:MergedReagents(r)) > 0 then
                out[#out + 1] = r
                if #out >= (limit or 8) then return out end
            end
        end
    end
    return out
end

ns.PriceProvider:BeginPass()
ns.CraftingPlanner:Bind(ns.RecipeBook, ns.PriceProvider):BeginPass()
local recipes = learnedWithOutput(8)

head("3. Безубыточность по настоящим рецептам игрока (книга ещё пуста)")
if #recipes == 0 then
    print("  выученных рецептов с составом в данных нет — считать нечего")
end
for _, r in ipairs(recipes) do
    local be = L:Breakeven(r, ns.PriceProvider)
    print("  " .. U.truncate(tostring(r.name or r.id), 34))
    if be then
        print(string.format("      себестоимость штуки %-12s выставлять не ниже %-12s источник: %s",
            U.money(be.unitCost), U.money(be.listPrice), be.source))
        print("      " .. L:BreakevenText(r, ns.PriceProvider))
    else
        print("      " .. L:BreakevenText(r, ns.PriceProvider))
    end
end

-- 4. ТА ЖЕ АРИФМЕТИКА, КОГДА КНИГА ЗАПОЛНИЛАСЬ -------------------------
--
-- ЭТО ЯВНАЯ ПОДСТАНОВКА, И ОНА НАЗВАНА. Настоящих покупок у игрока в книге
-- пока нет - книга появилась только что. Чтобы показать, что меняется, когда
-- он начнёт покупать, сюда подставлены ЕГО ЖЕ цены: те, что аддон сам записал
-- у торговцев (ForeverPilotDB.vendorPrices) и те, что видит на аукционе.
-- Выдуманных чисел здесь нет, но и покупок этих не было: это «как будет».

head("4. Та же арифметика, когда игрок начнёт покупать (подстановка его цен)")
local filled, want = 0, {}
for _, r in ipairs(recipes) do
    for _, g in ipairs(ns.RecipeBook:MergedReagents(r)) do want[g.itemID] = true end
end
local money = math.max(10000000, (env.money or 0))
for itemID in pairs(want) do
    local price = ns.PriceProvider:Buy(itemID)
    if price and price > 0 then
        local qty = 10
        local spend = U.round(price * qty)
        local before = { money = money, items = { [itemID] = 0 } }
        local after = { money = money - spend, items = { [itemID] = qty } }
        local entry, why = L:Observe(before, after, L.WHERE.VENDOR, H.serverTime - 3600)
        if entry then
            L:Note(entry)
            money = money - spend
            filled = filled + 1
        else
            print("  сверка отказалась по предмету " .. itemID .. ": " .. tostring(why))
        end
    end
end
print("  подставлено покупок: " .. filled .. "; " .. L:Headline())
print("")
ns.PriceProvider:BeginPass()
ns.CraftingPlanner:Bind(ns.RecipeBook, ns.PriceProvider):BeginPass()
for _, r in ipairs(recipes) do
    local be = L:Breakeven(r, ns.PriceProvider)
    print("  " .. U.truncate(tostring(r.name or r.id), 34))
    if be then
        print(string.format("      себестоимость штуки %-12s выставлять не ниже %-12s источник: %s (своих материалов %d из %d)",
            U.money(be.unitCost), U.money(be.listPrice), be.source,
            be.coverage and be.coverage.known or 0,
            be.coverage and be.coverage.total or 0))
    else
        print("      " .. L:BreakevenText(r, ns.PriceProvider))
    end
end

-- 5. ЧТО Я ЗАПЛАТИЛ ПРОТИВ РЫНКА ---------------------------------------

head("5. «Что я заплатил» против «что сейчас на рынке»")
local shown = 0
for itemID in pairs(want) do
    local cmp = L:PaidVsMarket(itemID, ns.PriceProvider)
    if cmp then
        -- Имя берётся из установленной базы предметов: офлайновый клиент имён
        -- не отдаёт, и без этого в отчёте стояли бы «Предмет #5504».
        local name = H.itemDBName(itemID) or ns.ActionEngine.nameOf(itemID)
        print("  " .. U.truncate(tostring(name), 28)
            .. "  [" .. cmp.verdict .. "]")
        print("      " .. cmp.text)
        shown = shown + 1
        if shown >= 10 then break end
    end
end
if shown == 0 then print("  сравнивать пока нечего") end

-- 6. ЧУЖАЯ КНИГА -------------------------------------------------------

head("6. Чужая книга закупок: где она теперь стоит")
print("  источник: " .. ns.FOREIGN_BOOK.name)
print("  почему меньше веры: " .. ns.FOREIGN_BOOK.why)
print("  план: " .. ns.FOREIGN_BOOK.plan)
print("")
local tried, ours, foreign, none = 0, 0, 0, 0
ns.PriceProvider:BeginPass()
for itemID in pairs(want) do
    tried = tried + 1
    local _, _, src = ns.PriceProvider:Buy(itemID)
    if src == "ledger" then ours = ours + 1
    elseif ns.PriceProvider:IsForeignSource(src) then foreign = foreign + 1
    elseif src == "none" then none = none + 1 end
end
print(string.format("  по %d материалам: своя книга ответила %d, чужая %d, никто %d",
    tried, ours, foreign, none))

-- 7. КАРТОЧКИ ----------------------------------------------------------

head("7. Настоящие советы «на продажу»: что теперь написано")
local cards = ns.ActionEngine:Build()
local said = 0
for _, c in ipairs(cards or {}) do
    if c.kind == ns.KIND.CRAFT_PROFIT then
        print("  " .. tostring(c.title) .. "   " .. tostring(c.benefit))
        print("      " .. U.truncate(tostring(c.why), 420))
        if c.breakeven then
            print("      [граница " .. U.money(c.breakeven.listPrice)
                .. ", источник " .. tostring(c.breakeven.source) .. "]")
        end
        said = said + 1
        if said >= 5 then break end
    end
end
if said == 0 then print("  советов «на продажу» в этом мире нет") end

-- Книга в файле игрока НЕ меняется: эти записи живут только в памяти этого
-- прогона. Сказать это надо вслух - иначе человек решит, что скрипт осмотра
-- что-то ему записал.
print("")
line("=")
print("Подставленные покупки существуют только в памяти этого прогона:")
print("файл сохранений игрока этот скрипт не открывает на запись.")
line("=")
