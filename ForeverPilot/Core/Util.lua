-- ForeverPilot / Core/Util.lua
-- Pure helpers. No game API, no UI. Must stay loadable by plain Lua for the tests.
local ADDON, ns = ...

local U = {}
ns.Util = U

local floor, abs, min, max = math.floor, math.abs, math.min, math.max
local format, rep = string.format, string.rep
local sort, concat = table.sort, table.concat

-- Numbers ----------------------------------------------------------------

function U.round(x)
    if type(x) ~= "number" then return 0 end
    return floor(x + 0.5)
end

function U.clamp(x, lo, hi)
    if type(x) ~= "number" then return lo end
    if x < lo then return lo end
    if x > hi then return hi end
    return x
end

-- ПОЛЬЗА ОТ ВЕЩИ: ЧИСЛО И СЛОВО ВМЕСТЕ -----------------------------------
--
-- Единица названа в Core/Const.lua, а печатается только отсюда. Причина
-- простая: «балл» склоняется («1 балл», «2 балла», «5 баллов»), и собранная по
-- месту строка `U.round(x) .. " " .. ns.UNIT_BENEFIT` даёт «2 балл» на каждой
-- второй карточке. Склонение знает U.plural, и теперь оно в одном месте - на
-- все карточки, подсказки и вкладку персонажа сразу.
--
-- Число всегда целое: дробная польза - это внутренняя точность расчёта, игроку
-- она не нужна и сравнивать по ней нечего.
function U.benefit(x)
    local n = U.round(x)
    local forms = ns.UNIT_BENEFIT_FORMS or { ns.UNIT_BENEFIT or "" }
    return n .. " " .. U.plural(n, forms[1], forms[2] or forms[1], forms[3] or forms[1])
end

-- То же со знаком впереди: «+11 баллов». Для столбца выгоды справа.
function U.benefitDelta(x)
    local n = U.round(x)
    return ((n < 0) and ns.GLYPH.MINUS or "+") .. U.benefit(abs(n))
end

-- ДРОБНАЯ ПОЛЬЗА - ТОЛЬКО ТАМ, ГДЕ ОНА ПО СМЫСЛУ ДРОБНАЯ: «3,5 балла за
-- золотой». Это не количество, а скорость, и округлять её до целого нельзя -
-- у дешёвой вещи всё число и уедет. Дробное число в русском всегда требует
-- «балла», целое - согласования по U.plural; запятая вместо точки, как во всём
-- остальном аддоне (см. U.times).
function U.benefitRate(x)
    local v = tonumber(x) or 0
    local one = U.round(v * 10) / 10
    if one == floor(one) then return U.benefit(one) end
    local forms = ns.UNIT_BENEFIT_FORMS or { ns.UNIT_BENEFIT or "" }
    return (format("%.1f", one):gsub("%.", ",")) .. " " .. (forms[2] or forms[1])
end

-- ЭТО УЛУЧШЕНИЕ ИЛИ РАЗМЕН?
--
-- Единственный ответ на этот вопрос во всём аддоне (порог и причина - у
-- ns.MIN_BENEFIT_GAIN). Правило: улучшение - это то, что печатается как
-- улучшение. Прирост, который округляется в ноль, улучшением не называется:
-- карточка «лучше на 0 баллов» - это не совет, а предложение потратить
-- материалы впустую, и игрок уже потратил.
--
-- nil - не «нет прироста», а «сравнить не удалось»: у таких советов своя ветка
-- текста, и сюда они не попадают.
function U.isGain(x)
    if type(x) ~= "number" then return false end
    return x >= (ns.MIN_BENEFIT_GAIN or 0.5)
end

-- IS A SAVED POSITION STILL REACHABLE?
--
-- SetClampedToScreen stops the player dragging a window off the edge, but it
-- does nothing about a position that was fine when it was saved and is not any
-- more: a smaller resolution, a second monitor unplugged, a changed UI scale.
-- The window then comes back half-way off the screen and there is no way to
-- grab it, because the part you grab is the part that is gone.
--
-- Приём подсмотрен у Polestar - точнее, у того, чего у него НЕТ: он
-- полагается только на SetClampedToScreen и на проверку типа, и его же
-- собственные заметки называют это слабым местом. Код не копировался (GPL-3.0).
--
-- Pure arithmetic on purpose: no frames, so it is testable offline. Returns
-- true when less than `minVisible` pixels of the frame are on screen in either
-- direction, which is the point at which the player can no longer grab it.
-- Missing numbers answer false: there is nothing to judge, and moving a window
-- on a guess is worse than leaving it.
U.MIN_VISIBLE = 40

function U.frameOffScreen(left, bottom, right, top, screenW, screenH, minVisible)
    left, bottom = tonumber(left), tonumber(bottom)
    right, top = tonumber(right), tonumber(top)
    screenW, screenH = tonumber(screenW), tonumber(screenH)
    if not (left and bottom and right and top and screenW and screenH) then
        return false
    end
    if screenW <= 0 or screenH <= 0 then return false end
    minVisible = tonumber(minVisible) or U.MIN_VISIBLE

    -- A FRAME WITH NO SIZE IS NOT A LOST FRAME, AND THIS COST A REAL BUG.
    --
    -- A fresh CreateFrame is 0x0 until SetSize is called, and the panel asked
    -- this question before sizing itself. A zero-wide frame overlaps the screen
    -- by zero pixels, so the answer was "lost", and every login wiped the saved
    -- panel position and printed a chat line blaming the screen edge. Refusing
    -- to judge a degenerate rectangle is the honest answer: there is no
    -- geometry yet, so there is nothing to be off-screen.
    local w, h = right - left, top - bottom
    if w <= 0 or h <= 0 then return false end

    -- How much of the frame overlaps the screen on each axis.
    local visibleW = math.min(right, screenW) - math.max(left, 0)
    local visibleH = math.min(top, screenH) - math.max(bottom, 0)
    -- A frame narrower than the threshold cannot show more than itself, so it
    -- is judged against its own width instead of a fixed number.
    local needW = math.min(minVisible, w)
    local needH = math.min(minVisible, h)
    return (visibleW < needW) or (visibleH < needH)
end

-- Safe division: never returns nan/inf.
function U.div(a, b, fallback)
    a, b = tonumber(a) or 0, tonumber(b) or 0
    if b == 0 then return fallback or 0 end
    return a / b
end

function U.ceilDiv(a, b)
    a, b = tonumber(a) or 0, tonumber(b) or 1
    if b <= 0 then return 0 end
    return floor((a + b - 1) / b)
end

-- Пустота ----------------------------------------------------------------
--
-- Единственное место, которое превращает «числа нет» в то, что видит игрок.
-- Словарь и причины - в ns.VOID (Core/Const.lua); здесь только показ.
--
-- Звать это надо С ПРИЧИНОЙ. Прочерк, выбранный на месте, - это утверждение
-- «такого значения не бывает», и делать его за вызывающего нельзя: половину
-- прочерков на экране ставили те, кто просто не знал цены.

function U.void(kind)
    return ns.VOID_TEXT[kind] or ns.VOID_TEXT.UNKNOWN
end

function U.voidWhy(kind)
    return ns.VOID_WHY[kind] or ns.VOID_WHY.UNKNOWN
end

-- Является ли строка одним из обозначений пустоты. Нужно самопроверке: число,
-- которое ушло на экран как пустота, нельзя потом складывать.
function U.isVoid(text)
    if type(text) ~= "string" then return false end
    for _, v in pairs(ns.VOID_TEXT) do
        if text == v then return true end
    end
    return false
end

-- ВОЗРАСТ, КОТОРЫЙ ВИДЕН ВСЕГДА. Три разных ответа, и молчания среди них нет:
--   число  - сколько назад это видели ("только что" ближе минуты);
--   nil    - возраст неизвестен (так отвечает кеш без отметки времени);
--   false  - значение не стареет (цена продажи торговцу лежит в самих данных
--            предмета и вчера была той же).
function U.ageWord(seconds)
    if seconds == false then return ns.AGE_TIMELESS end
    local s = tonumber(seconds)
    if not s or s < 0 then return ns.AGE_UNKNOWN end
    if s < 60 then return ns.AGE_JUST_NOW end
    return U.ageText(s) or ns.AGE_UNKNOWN
end

-- Money ------------------------------------------------------------------

-- 25081 -> "2з 50с 81м". Keeps only the two highest non-zero units so cards stay short.
--
-- БЕЗ ЧИСЛА ОТВЕЧАЕТ «не знаю», А НЕ ПРОЧЕРКОМ. Прочерк в словаре пустоты
-- означает «такого значения не бывает», а эта функция про причину ничего не
-- знает: ей просто не дали числа.
function U.money(copper, full)
    copper = tonumber(copper)
    if not copper then return U.void(ns.VOID.UNKNOWN) end
    local neg = copper < 0
    copper = floor(abs(copper) + 0.5)
    local g = floor(copper / 10000)
    local s = floor((copper % 10000) / 100)
    local c = copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. "з" end
    if s > 0 and (full or #parts < 2) then parts[#parts + 1] = s .. "с" end
    if c > 0 and (full or #parts < 2) then parts[#parts + 1] = c .. "м" end
    if #parts == 0 then parts[1] = "0м" end
    return (neg and "-" or "") .. concat(parts, " ")
end

-- РАЗНИЦА, КОТОРОЙ НЕТ, - ЭТО НЕ НОЛЬ. Раньше здесь стояло `tonumber(x) or 0`,
-- и прибыль, которую не удалось посчитать, печаталась как «0м»: игрок читал
-- «ничего не заработаю», хотя сказать надо было «не знаю».
function U.moneyDelta(copper)
    copper = tonumber(copper)
    if not copper then return U.void(ns.VOID.UNKNOWN) end
    if copper == 0 then return "0м" end
    return (copper > 0 and "+" or "-") .. U.money(abs(copper))
end

-- ЦЕНА ЦЕЛИКОМ: число, пометка «оценка» и возраст - одной строкой.
--
-- Это тот самый показ, из-за которого словарь и заведён: всё, что игрок должен
-- знать про число, стоит рядом с числом, а не в соседней графе. Без числа
-- говорит ПРИЧИНУ: по умолчанию «нет цены» словами, а вызывающий может сказать
-- «так нельзя» (продавать нечего) или «не знаю».
--
-- `age`: секунды / nil («возраст неизвестен») / false («не стареет»).
function U.priceText(copper, conf, age, voidKind)
    copper = tonumber(copper)
    if not copper then return U.void(voidKind or ns.VOID.NO_PRICE) end
    local text = U.money(copper)
    local marks = {}
    if conf == ns.CONF.ESTIMATE or conf == ns.CONF.UNKNOWN then
        text = ns.ESTIMATE_MARK .. text
        marks[#marks + 1] = ns.ESTIMATE_WORD
    end
    marks[#marks + 1] = U.ageWord(age)
    return text .. " (" .. concat(marks, ", ") .. ")"
end

-- То же для разницы (прибыль, убыток): знак впереди, пометки те же.
function U.deltaText(copper, conf, age, voidKind)
    copper = tonumber(copper)
    if not copper then return U.void(voidKind or ns.VOID.NO_PRICE) end
    local text = U.moneyDelta(copper)
    local marks = {}
    if conf == ns.CONF.ESTIMATE or conf == ns.CONF.UNKNOWN then
        text = ns.ESTIMATE_MARK .. text
        marks[#marks + 1] = ns.ESTIMATE_WORD
    end
    if age ~= nil then marks[#marks + 1] = U.ageWord(age) end
    if #marks == 0 then return text end
    return text .. " (" .. concat(marks, ", ") .. ")"
end

-- Tables -----------------------------------------------------------------

function U.count(t)
    if type(t) ~= "table" then return 0 end
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

function U.isEmpty(t)
    if type(t) ~= "table" then return true end
    return next(t) == nil
end

function U.copy(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    return out
end

function U.deepCopy(t, seen)
    if type(t) ~= "table" then return t end
    seen = seen or {}
    if seen[t] then return seen[t] end
    local out = {}
    seen[t] = out
    for k, v in pairs(t) do out[U.deepCopy(k, seen)] = U.deepCopy(v, seen) end
    return out
end

-- Fill missing keys of `target` from `defaults`, recursively. Never overwrites.
function U.applyDefaults(target, defaults)
    if type(target) ~= "table" then target = {} end
    if type(defaults) ~= "table" then return target end
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            target[k] = U.applyDefaults(target[k], v)
        elseif target[k] == nil then
            target[k] = v
        end
    end
    return target
end

-- Add `qty` of `key` into `bag`, creating the entry. Returns the new total.
function U.addTo(bag, key, qty)
    if key == nil then return 0 end
    qty = tonumber(qty) or 0
    bag[key] = (bag[key] or 0) + qty
    return bag[key]
end

-- Take up to `want` of `key` out of `bag`. Returns how much was actually taken.
function U.takeFrom(bag, key, want)
    want = tonumber(want) or 0
    if want <= 0 or key == nil then return 0 end
    local have = bag[key] or 0
    if have <= 0 then return 0 end
    local took = min(have, want)
    bag[key] = have - took
    if bag[key] <= 0 then bag[key] = nil end
    return took
end

-- Sorted key list, so iteration order is stable (tests and UI both need this).
function U.sortedKeys(t, cmp)
    local ks = {}
    if type(t) ~= "table" then return ks end
    for k in pairs(t) do ks[#ks + 1] = k end
    sort(ks, cmp or function(a, b)
        local ta, tb = type(a), type(b)
        if ta == tb then
            if ta == "number" or ta == "string" then return a < b end
            return tostring(a) < tostring(b)
        end
        return ta < tb
    end)
    return ks
end

-- Stable sort by a key function (Lua's table.sort is not stable; we add the
-- original index as a tiebreak so the same input always ranks the same way).
function U.stableSortBy(list, scoreOf, descending)
    local wrapped = {}
    for i = 1, #list do
        -- nan breaks the comparator both ways round (nan < x and x < nan are
        -- both false), and Lua's table.sort raises "invalid order function" when
        -- that happens. Anything that is not a real number sorts as zero.
        local score = tonumber(scoreOf(list[i]))
        if (not score) or score ~= score then score = 0 end
        if score == math.huge then score = 1e308 end
        if score == -math.huge then score = -1e308 end
        wrapped[i] = { item = list[i], score = score, idx = i }
    end
    sort(wrapped, function(a, b)
        if a.score ~= b.score then
            if descending then return a.score > b.score end
            return a.score < b.score
        end
        return a.idx < b.idx
    end)
    local out = {}
    for i = 1, #wrapped do out[i] = wrapped[i].item end
    return out
end

-- Strings ----------------------------------------------------------------

function U.trim(s)
    if type(s) ~= "string" then return nil end
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    return s ~= "" and s or nil
end

-- Lua's string.lower only knows ASCII, so on a Russian client "Чары" stays
-- "Чары" and every lowercase keyword match silently fails. This handles the
-- Cyrillic block as well, which is all the addon needs.
--
-- UTF-8 layout of the block:
--   А..П  D0 90..D0 9F  ->  а..п  D0 B0..D0 BF   (second byte +0x20)
--   Р..Я  D0 A0..D0 AF  ->  р..я  D1 80..D1 8F   (first byte D1, second -0x20)
--   Ё     D0 81         ->  ё     D1 91
local byte, char = string.byte, string.char

function U.lower(s)
    if type(s) ~= "string" then return nil end
    s = s:lower() -- ASCII part
    if not s:find("[\208\209]") then return s end

    local out, i, n = {}, 1, #s
    while i <= n do
        local b1 = byte(s, i)
        if b1 == 208 then -- 0xD0
            local b2 = byte(s, i + 1)
            if b2 == nil then
                out[#out + 1] = char(b1)
                i = i + 1
            elseif b2 >= 144 and b2 <= 159 then       -- А..П
                out[#out + 1] = char(208, b2 + 32)
                i = i + 2
            elseif b2 >= 160 and b2 <= 175 then       -- Р..Я
                out[#out + 1] = char(209, b2 - 32)
                i = i + 2
            elseif b2 == 129 then                      -- Ё
                out[#out + 1] = char(209, 145)
                i = i + 2
            else
                out[#out + 1] = char(b1, b2)
                i = i + 2
            end
        elseif b1 >= 192 then
            -- Any other multi-byte sequence: copy it through untouched.
            local len = (b1 >= 240 and 4) or (b1 >= 224 and 3) or 2
            out[#out + 1] = s:sub(i, i + len - 1)
            i = i + len
        else
            out[#out + 1] = char(b1)
            i = i + 1
        end
    end
    return table.concat(out)
end

-- Case-insensitive plain-text containment, Cyrillic included.
function U.contains(haystack, needle)
    if type(haystack) ~= "string" or type(needle) ~= "string" then return false end
    return U.lower(haystack):find(U.lower(needle), 1, true) ~= nil
end

-- Case-insensitive pattern match, Cyrillic included. The pattern itself is
-- expected to be written lowercase.
function U.matches(haystack, pattern)
    if type(haystack) ~= "string" or type(pattern) ~= "string" then return false end
    return U.lower(haystack):find(pattern) ~= nil
end

-- How many characters (not bytes) a UTF-8 string holds. A continuation byte
-- (10xxxxxx) is part of the previous character and is not counted.
function U.charLen(s)
    if type(s) ~= "string" then return 0 end
    local n = 0
    for i = 1, #s do
        local b = s:byte(i)
        if b < 0x80 or b >= 0xC0 then n = n + 1 end
    end
    return n
end

-- Byte offset of the end of the `n`-th character, or nil when the string is
-- shorter than that.
local function byteEndOfChar(s, n)
    local chars, i, len = 0, 1, #s
    while i <= len do
        local b = s:byte(i)
        local step = (b >= 0xF0 and 4) or (b >= 0xE0 and 3) or (b >= 0xC0 and 2) or 1
        chars = chars + 1
        if chars == n then return math.min(i + step - 1, len) end
        i = i + step
    end
    return nil
end

-- Cut a string to `n` characters without breaking a UTF-8 sequence.
--
-- This used to compare `#s` (bytes) against `n` and then cut at byte `n`, so on
-- Russian text it threw away half of what it was asked to keep:
-- truncate("ПриветМир", 4) gave "Пр…" instead of "Прив…".
function U.truncate(s, n)
    if type(s) ~= "string" then return "" end
    n = tonumber(n) or 0
    if n <= 0 then return "" end
    if U.charLen(s) <= n then return s end
    local cut = byteEndOfChar(s, n)
    if not cut then return s end
    return s:sub(1, cut) .. "…"
end

-- ЧИСЛО И КООРДИНАТЫ РЕЗАТЬ НЕЛЬЗЯ ----------------------------------------
--
-- Игрок прислал скриншот, на котором строка кончается ровно на том, ради чего
-- её читают: «Разница +8з 80…», «Торговец: Mister Graphed, Лесоречье, 78.2 5…».
-- Резал не аддон: строки карточки стоят без переноса (UI/Card.lua), и всё, что
-- не влезло по ширине окна, обрезает клиент - по пикселям, то есть посреди
-- числа.
--
-- Поэтому текст укорачивается ЗДЕСЬ и только целыми кусками. Что уходит и в
-- каком порядке:
--   1. фразы без чисел, с конца («Может оказаться штучным товаром…»);
--   2. пояснения в скобках без чисел («(сбор аукциона уже вычтен)»);
--   3. фразы с числами, с конца; первая фраза остаётся всегда;
--   4. хвостовые слова первой фразы.
-- Числовая группа - «+8з 80с», «78.2 51.9», «66с 20м..72с 47м» - один кусок:
-- разрезать её нечем, и висящее число без слова тоже не остаётся.
--
-- ОГОВОРКА ПРО НЕДОВЕРИЕ К ЧИСЛУ НЕ УХОДИТ НИКОГДА. «Числа этой карточки не
-- сходятся — проверьте цену на месте» стоит в тексте ради числа, которое рядом;
-- выбросить её значит оставить число без предупреждения, то есть соврать.
U.KEEP_MARKS = { "не сходятся", "проверьте", "осторожно", "сомнитель" }

-- КООРДИНАТЫ ТОЖЕ НЕ УХОДЯТ. «Торговец: Mister Graphed, Лесоречье, 78.2 51.9»
-- читают ради этих двух чисел: без них совет превращается в «иди поищи». Поэтому
-- фраза с координатами держится так же, как оговорка, - до последнего.
U.COORDS = "%d+%.%d+%s+%d+%.%d+"

local function hasDigit(s)
    return tostring(s):find("%d") ~= nil
end

local function mustKeep(s)
    local text = tostring(s)
    if text:find(U.COORDS) then return true end
    local low = U.lower(text)
    for _, mark in ipairs(U.KEEP_MARKS) do
        if low:find(mark, 1, true) then return true end
    end
    return false
end

-- Заглавная буква в позиции i (русская или латинская). Классы символов Lua 5.1
-- побайтовые, поэтому кириллица проверяется байтами, как в Tests/sense.lua.
local function isUpperAt(s, i)
    local b1 = s:byte(i)
    if not b1 then return false end
    if b1 < 128 then return s:sub(i, i):match("%u") ~= nil end
    if b1 == 208 then
        local b2 = s:byte(i + 1)
        return b2 ~= nil and ((b2 >= 144 and b2 <= 175) or b2 == 129)
    end
    return false
end

-- Фразы текста вместе со знаком конца. Делим по «. » перед заглавной буквой:
-- «46 шт. и ещё 2» - одна фраза, «…45.0. Выставляется» - две. Сокращения
-- («13 ур., Маг») фразу не разрывают именно поэтому.
function U.sentences(text)
    text = tostring(text or "")
    local out, start, i = {}, 1, 1
    while i <= #text do
        local c = text:sub(i, i)
        if (c == "." or c == "!" or c == "?") and text:sub(i + 1, i + 1) == " "
            and isUpperAt(text, i + 2) then
            out[#out + 1] = text:sub(start, i)
            start = i + 2
            i = i + 2
        else
            i = i + 1
        end
    end
    local tail = text:sub(start):gsub("^%s+", "")
    if tail ~= "" then out[#out + 1] = tail end
    return out
end

-- Слова текста, где числовая группа - одно слово. Группа - это подряд идущие
-- слова, каждое из которых начинается цифрой и продолжает предыдущее с цифрой:
-- «+8з» «80с» «12м» или «78.2» «51.9».
function U.atoms(text)
    local out = {}
    for word in tostring(text or ""):gmatch("%S+") do
        local prev = out[#out]
        if prev and hasDigit(prev.text) and hasDigit(word)
            and word:match("^[%+%-~]?%d") then
            prev.text = prev.text .. " " .. word
            prev.number = true
        else
            out[#out + 1] = { text = word, number = hasDigit(word) }
        end
    end
    return out
end

-- Число без слова: «4» от «4 дня». Такой хвост не оставляем - он ничего не
-- значит. Буквы (в том числе русские) ловятся как «всё, что не цифра и не знак»:
-- класс %a в Lua 5.1 кириллицу не видит.
local function bareNumber(s)
    return s:find("%d") ~= nil and s:find("[^%d%+%-~%.,:;/%%%s]") == nil
end

-- Снять пояснения в скобках, в которых нет ни числа, ни оговорки.
local function dropAsides(text)
    local out = tostring(text):gsub("%s*%b()", function(piece)
        if hasDigit(piece) or mustKeep(piece) then return piece end
        return ""
    end)
    out = out:gsub("%s+([%.,;:])", "%1"):gsub("%s%s+", " ")
    return (out:gsub("^%s+", ""):gsub("%s+$", ""))
end
U.dropAsides = dropAsides

U.MORE_MARK = "…"

local function withMark(s)
    s = (tostring(s):gsub("%s+$", ""))
    if s == "" then return s end
    if s:sub(-3) == U.MORE_MARK then return s end
    return s .. " " .. U.MORE_MARK
end

-- ВАРИАНТЫ ТЕКСТА, ОТ ПОЛНОГО К КОРОТКОМУ. Кто рисует, тот и выбирает: мерит
-- шрифтом и берёт первый, который влезает (UI/Widgets.lua, W.SetFitted).
--
-- ПОРЯДОК ЗДЕСЬ - НЕ ПО ДЛИНЕ, А ПО ЦЕННОСТИ, и это главное в этой функции.
-- Сначала идут варианты, в которых целы все фразы (ушли только пояснения и
-- проза), потом - в которых от первой фразы осталось начало И ХВОСТ С
-- ПОСЛЕДНИМ ЧИСЛОМ, и только у текста без чисел вообще дело доходит до
-- выбрасывания хвостовых слов. Поэтому короткий вариант с числом стоит выше
-- длинного без числа: ради числа строку и читают.
--
-- Чистая функция и без единого обращения к клиенту - чтобы её можно было
-- проверить без игры и без окна.
function U.shortenings(text)
    local full = tostring(text or "")
    local seen, byValue = {}, {}
    local fullLen = U.charLen(full)
    -- Вариант не короче исходного - не вариант: помеченный «…» огрызок бывает
    -- длиннее целой фразы, и мерить его потом незачем.
    local function accept(s)
        s = (tostring(s):gsub("%s+$", ""))
        if s == "" or seen[s] then return nil end
        if #byValue > 0 and U.charLen(s) >= fullLen then return nil end
        seen[s] = true
        return s
    end
    local function push(s)
        s = accept(s)
        if s then byValue[#byValue + 1] = s end
    end
    push(full)
    if full == "" then return byValue end

    local sent = U.sentences(full)
    -- Оговорки стоят в тексте ради числа рядом. Выбросить их последними, а
    -- сначала - укоротить до самого предупреждающего слова: «Осторожно …»
    -- рядом с числом честнее, чем число без предупреждения.
    local locked = {}
    for i = 2, #sent do
        if mustKeep(sent[i]) then locked[i] = true end
    end

    -- Оговорка одним куском: часть фразы с самим предупреждающим словом.
    -- «Осторожно: 3 из 5 таких советов…» становится «Осторожно …» - и место,
    -- которое освободилось, достаётся числам из первых фраз.
    local function markClause(s)
        local norm = s:gsub(" — ", "\1"):gsub("; ", "\1"):gsub(": ", "\1")
        for piece in (norm .. "\1"):gmatch("([^\1]+)\1") do
            if mustKeep(piece) then return withMark(piece) end
        end
        return s
    end

    -- head - начало текста; cut - было ли что-то выброшено; from - с какой
    -- фразы дописывать оговорки; mode - в каком виде их дописывать:
    -- "full" целиком, "short" одним куском, "none" не дописывать вовсе.
    local function assemble(head, cut, from, mode)
        local parts = { cut and withMark(head) or head }
        for i = from, #sent do
            if locked[i] and mode ~= "none" then
                parts[#parts + 1] = (mode == "short") and markClause(sent[i]) or sent[i]
            end
        end
        return table.concat(parts, " ")
    end

    local function sentCandidate(n, asides, mode)
        local parts, cut = {}, false
        for i = 1, n do
            local piece = asides and dropAsides(sent[i]) or sent[i]
            if piece ~= sent[i] then cut = true end
            parts[#parts + 1] = piece
        end
        for i = n + 1, #sent do
            if (not locked[i]) or mode ~= "full" then cut = true end
        end
        return assemble(table.concat(parts, " "), cut, n + 1, mode)
    end

    local function longestFirst(list)
        table.sort(list, function(a, b)
            local la, lb = U.charLen(a), U.charLen(b)
            if la ~= lb then return la > lb end
            return a < b
        end)
        for _, s in ipairs(list) do byValue[#byValue + 1] = s end
    end

    -- 1. Целые фразы: без пояснений в скобках и без прозы с конца.
    local function wholeFamily(mode)
        local list = {}
        local function add(s)
            s = accept(s)
            if s then list[#list + 1] = s end
        end
        add(sentCandidate(#sent, true, mode))
        for n = #sent - 1, 1, -1 do
            add(sentCandidate(n, false, mode))
            add(sentCandidate(n, true, mode))
        end
        longestFirst(list)
    end

    -- 2. От первой фразы - начало и хвост с последним числом. Число не
    --    выбрасывается: «Разница … +8з 80с за штуку» остаётся числом, а
    --    «Разница +8з 80» не значит ничего.
    local atoms = U.atoms(dropAsides(sent[1]))
    local tailFrom
    for i = #atoms, 1, -1 do
        if atoms[i].number then tailFrom = i; break end
    end
    local function headOf(k)
        local parts = {}
        for i = 1, k do parts[#parts + 1] = atoms[i].text end
        return table.concat(parts, " ")
    end
    local function tailFrom_to(last)
        local tail = {}
        for i = tailFrom, last do tail[#tail + 1] = atoms[i].text end
        return table.concat(tail, " ")
    end
    local function atomFamily(mode)
        if tailFrom then
            -- Хвост бывает двух длин, и сначала идёт длинный: от числа до конца
            -- фразы. Если число стоит в начале («Нужно для 4 советов, например:
            -- …»), такой хвост - это почти вся фраза, и влезть он не может ни
            -- при какой ширине; тогда берётся короткий - само число и слово при
            -- нём («4 советов»).
            local tails = { tailFrom_to(#atoms) }
            local shortEnd = math.min(#atoms, tailFrom + 1)
            if shortEnd < #atoms then tails[#tails + 1] = tailFrom_to(shortEnd) end
            for _, tailText in ipairs(tails) do
                for k = tailFrom - 1, 1, -1 do
                    if not bareNumber(atoms[k].text) then
                        push(assemble(headOf(k) .. " " .. U.MORE_MARK .. " " .. tailText,
                            false, 2, mode))
                    end
                end
                push(assemble(U.MORE_MARK .. " " .. tailText, false, 2, mode))
            end
        else
            -- Чисел в первой фразе нет - терять нечего, уходят хвостовые слова.
            for k = #atoms - 1, 1, -1 do
                if not bareNumber(atoms[k].text) then
                    push(assemble(headOf(k), true, 2, mode))
                end
            end
        end
    end

    -- 3. Только оговорка и координаты: когда места не хватает ни на что, из
    --    строки «У вас 2з 50с — хватает. Торговец: Кварц, Тернистая долина,
    --    34.0 76.0» остаются координаты, а не «хватает». Идти по ним, а не
    --    пересчитывать деньги, - то, ради чего совет и читают.
    local function lockedOnlyFamily()
        local list = {}
        for _, mode in ipairs({ "full", "short" }) do
            local parts = {}
            for i = 2, #sent do
                if locked[i] then
                    parts[#parts + 1] = (mode == "short") and markClause(sent[i]) or sent[i]
                end
            end
            if #parts > 0 then
                local s = accept(U.MORE_MARK .. " " .. table.concat(parts, " "))
                if s then list[#list + 1] = s end
            end
        end
        for _, s in ipairs(list) do byValue[#byValue + 1] = s end
    end

    wholeFamily("full")
    wholeFamily("short")
    atomFamily("short")
    lockedOnlyFamily()
    atomFamily("none")
    return byValue
end

-- То же, что U.truncate, но без разрезанных чисел: берётся самый ценный из
-- вариантов U.shortenings, который укладывается в n символов. Там, где ширину
-- мерить нечем (подпись стрелки, свёрнутая панель), счёт идёт по символам.
function U.fitChars(text, n)
    text = tostring(text or "")
    n = tonumber(n) or 0
    if n <= 0 then return "" end
    if U.charLen(text) <= n then return text end
    for _, variant in ipairs(U.shortenings(text)) do
        if U.charLen(variant) <= n then return variant end
    end
    return U.truncate(text, n)
end

-- ПЕРЕЧИСЛЕНИЕ БЕЗ ПОВТОРОВ: одинаковые имена схлопываются с количеством.
--
-- «Серый хлам в сумках: Длинный волос из хвоста, Отрубленный коготь,
-- Отрубленный коготь и ещё 8» - игрок прочитал один и тот же предмет дважды
-- подряд. Виноват не список, а источник: хлам считается по ячейкам сумки, и
-- один предмет лежит в двух ячейках. Для игрока это один предмет и одно число.
--
-- list - имена или записи { name, qty }, limit - сколько РАЗНЫХ имён назвать.
-- Возвращает текст и число неназванных имён.
function U.enumerate(list, limit)
    limit = tonumber(limit) or 3
    local order, qty = {}, {}
    for _, raw in ipairs(list or {}) do
        local name = (type(raw) == "table") and tostring(raw.name) or tostring(raw)
        local n = (type(raw) == "table") and (tonumber(raw.qty) or 1) or 1
        if qty[name] == nil then
            qty[name] = 0
            order[#order + 1] = name
        end
        qty[name] = qty[name] + n
    end
    local shown = {}
    for i = 1, math.min(limit, #order) do
        local name = order[i]
        shown[#shown + 1] = name .. ((qty[name] > 1) and (" x" .. qty[name]) or "")
    end
    local rest = #order - #shown
    local text = table.concat(shown, ", ")
    if rest > 0 then text = text .. " и ещё " .. rest end
    return text, rest
end

-- Upper-case the first character, Cyrillic included (string.upper would leave
-- "материалы" alone on a Russian client).
local CYR_LOWER_TO_UPPER = {}
do
    for b = 176, 191 do CYR_LOWER_TO_UPPER[char(208, b)] = char(208, b - 32) end  -- а..п
    for b = 128, 143 do CYR_LOWER_TO_UPPER[char(209, b)] = char(208, b + 32) end  -- р..я
    CYR_LOWER_TO_UPPER[char(209, 145)] = char(208, 129)                            -- ё
end

function U.capitalize(s)
    if type(s) ~= "string" or s == "" then return s end
    local b1 = s:byte(1)
    if b1 < 0x80 then return s:sub(1, 1):upper() .. s:sub(2) end
    local two = s:sub(1, 2)
    local up = CYR_LOWER_TO_UPPER[two]
    if up then return up .. s:sub(3) end
    return s
end

-- ЗАКРЫТЬ ПРЕДЛОЖЕНИЕ ТОЧКОЙ - И НЕ ПОСТАВИТЬ ВТОРУЮ.
--
-- Конец фразы собирается из подписей и чисел, а часть подписей кончается
-- сокращением, у которого точка своя: «46 шт.», «13 ур.», «ед.». Приписанная
-- сверху точка давала «46 шт..» - ровно то, что проверка пунктуации называет
-- «две точки подряд», и игрок это видел на карточке «Материал есть у …».
--
-- СМОТРИМ НА ПОСЛЕДНИЙ ЗНАК, А НЕ НА СПИСОК СОКРАЩЕНИЙ. Список пришлось бы
-- держать в двух местах (здесь и в Tests/sense.lua) и дописывать при каждом
-- новом сокращении - то есть он протух бы на первом же «з.». Последний знак
-- работает и для «шт.», и для «з.», и для «ур.», и для того сокращения,
-- которого ещё нет.
local SENTENCE_END = {
    ["."] = true, ["!"] = true, ["?"] = true, [":"] = true, [";"] = true,
}

function U.endSentence(s)
    if type(s) ~= "string" then return s end
    local text = s:gsub("%s+$", "")
    if text == "" then return text end
    if SENTENCE_END[text:sub(-1)] then return text end
    -- Многоточие - один символ UTF-8 из трёх байтов, последним знаком его не
    -- увидеть. «…» тоже конец фразы: «…. » читается как опечатка.
    if text:sub(-3) == "…" then return text end
    return text .. "."
end

-- "Предмет #12345" is the honest fallback when the client has no name yet.
function U.itemFallbackName(itemID)
    return "Предмет #" .. tostring(itemID)
end

-- ИМЯ ПРОФЕССИИ ДЛЯ ЭКРАНА - ОДНОЙ ФУНКЦИЕЙ НА ВЕСЬ АДДОН.
--
-- Имя профессии приходит из трёх мест, и только одно из них русское: клиент
-- (ruRU - «Алхимия»), чужой кеш Mastercraft (английское - «Alchemy») и наш
-- справочник (английское по уговору, см. шапку Data/ForeverSource.lua). Пока
-- каждая карточка подставляла имя как пришло, на экране русского игрока
-- оказывались «Навык на пределе: Enchanting 225/225» и «Откройте окно:
-- Tailoring» - ровно тогда, когда клиент ещё молчал и имя бралось из кеша.
--
-- Перевод живёт в ОДНОМ словаре - RecipeBook.NAME_BRIDGE, через
-- Roster:DisplayName. Здесь только точка входа, чтобы вызывающему не надо было
-- знать, у кого спрашивать, и чтобы Tests/sense.lua мог проверить ВСЕ места
-- одним правилом. Имя, которого словарь не знает, отдаётся как пришло: это
-- единственное, что про эту профессию известно.
function U.profLabel(name)
    if type(name) ~= "string" or name == "" then return name end
    local R = ns.Roster
    if R and R.DisplayName then return R:DisplayName(name) end
    return name
end

-- Russian plural: U.plural(n, "рецепт", "рецепта", "рецептов")
function U.plural(n, one, few, many)
    n = abs(floor(tonumber(n) or 0))
    local m100, m10 = n % 100, n % 10
    if m100 >= 11 and m100 <= 14 then return many end
    if m10 == 1 then return one end
    if m10 >= 2 and m10 <= 4 then return few end
    return many
end

function U.pct(x)
    return format("%d%%", U.round((tonumber(x) or 0) * 100))
end

-- «5 раз», «3 раза», «2,5 раза»: число раз, согласованное с числом.
--
-- Раньше каждое место писало своё «в %d раз» - и на экране стояло «в 3 раз
-- больше», «в 25.3 раз», «в 167 раза». Целое число согласуется обычным образом,
-- дробное всегда требует «раза» и пишется с запятой.
function U.times(n)
    n = tonumber(n)
    if not n then return nil end
    local tenths = U.round(n * 10) / 10
    if tenths == floor(tenths) then
        local whole = floor(tenths)
        return whole .. " " .. U.plural(whole, "раз", "раза", "раз")
    end
    return (format("%.1f", tenths):gsub("%.", ",")) .. " раза"
end

-- Confidence -------------------------------------------------------------

local CONF_RANK = { EXACT = 4, CACHED = 3, ESTIMATE = 2, UNKNOWN = 1 }

-- The confidence of a conclusion is the confidence of its weakest input.
-- Called with nothing valid at all it used to answer EXACT, which is the most
-- confident answer in the set and exactly the wrong default.
function U.worstConf(...)
    local worst, worstRank, any = "EXACT", 5, false
    for i = 1, select("#", ...) do
        local c = select(i, ...)
        local r = CONF_RANK[c]
        if r then
            any = true
            if r < worstRank then worst, worstRank = c, r end
        end
    end
    if not any then return "UNKNOWN" end
    return worst
end

function U.confScore(conf)
    return ns.CONF_SCORE[conf] or ns.CONF_SCORE.UNKNOWN
end

-- Normalisation ----------------------------------------------------------

-- Squash an unbounded positive value into 0..1 with a soft knee at `scale`.
-- x = scale  -> 0.5 ; x = 3*scale -> 0.75 ; never reaches 1.
function U.soft(x, scale)
    x = max(0, tonumber(x) or 0)
    scale = max(1e-9, tonumber(scale) or 1)
    return x / (x + scale)
end

-- Time -------------------------------------------------------------------

-- "ещё 2 часа" style wait text for a cooldown that has not expired yet.
function U.durationText(seconds)
    seconds = tonumber(seconds)
    if not seconds or seconds <= 0 then return nil end
    if seconds < 60 then
        local s = floor(seconds)
        return s .. " " .. U.plural(s, "секунда", "секунды", "секунд")
    end
    if seconds < 3600 then
        local m = max(1, floor(seconds / 60))
        return m .. " " .. U.plural(m, "минута", "минуты", "минут")
    end
    if seconds < 86400 then
        local h = max(1, floor(seconds / 3600))
        return h .. " " .. U.plural(h, "час", "часа", "часов")
    end
    local d = max(1, floor(seconds / 86400))
    return d .. " " .. U.plural(d, "день", "дня", "дней")
end

function U.ageText(seconds)
    seconds = tonumber(seconds)
    if not seconds or seconds < 0 then return nil end
    if seconds < 3600 then
        local m = max(1, floor(seconds / 60))
        return m .. " " .. U.plural(m, "минуту", "минуты", "минут") .. " назад"
    end
    if seconds < 86400 then
        local h = floor(seconds / 3600)
        return h .. " " .. U.plural(h, "час", "часа", "часов") .. " назад"
    end
    local d = floor(seconds / 86400)
    return d .. " " .. U.plural(d, "день", "дня", "дней") .. " назад"
end

-- Item links -------------------------------------------------------------

-- "|cnIQ3:|Hitem:253957::::::::26:1482::...|h[Жемчужный венец]|h|r" -> 253957
function U.itemIDFromLink(link)
    if type(link) ~= "string" then return nil end
    local id = link:match("|?H?item:(%d+)")
    return id and tonumber(id) or nil
end

-- -> "Жемчужный венец"
function U.itemNameFromLink(link)
    if type(link) ~= "string" then return nil end
    return U.trim(link:match("%[(.-)%]"))
end

-- The enchantId field of an item link, or nil when the item is not enchanted.
-- item:ID:ENCHANT:gem1:gem2:gem3:gem4:suffix:unique:level:...
function U.enchantIDFromLink(link)
    if type(link) ~= "string" then return nil end
    local payload = link:match("|?H?item:([%-%d:]*)")
    if not payload then return nil end
    local fields = {}
    for field in (payload .. ":"):gmatch("([^:]*):") do fields[#fields + 1] = field end
    local e = tonumber(fields[2])
    if e and e ~= 0 then return e end
    return nil
end

return U
