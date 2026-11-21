-- ForeverPilot / Tests/test_aware.lua
--
-- ЧТО АДДОН ВИДИТ НА САМОМ ИГРОКЕ: БАФФЫ И СЛОВА НАЛОЖЕННЫХ ЧАР.
--
-- Слова игрока (маг 31 ур., 2026-11-21): «он должен учитывать всё: что у меня
-- в сумках, то, что поставлено от костра, баффы, которые на мне, одежду».
-- До этого дня аддон не читал баффы вовсе, а от наложенных чар знал только
-- номер - и из-за номера советовал перекрыть чары, которые лучше его формул.
--
-- Что здесь закреплено:
--   1. Баффы читаются обоими путями клиента (C_UnitAuras и старый UnitBuff),
--      и «прочитать нечем» - не то же самое, что «баффов нет».
--   2. Баффы попадают в снимок персонажа и в файл диагностики - с номерами
--      заклинаний, чтобы по файлу было видно, что игра отдаёт на самом деле.
--   3. Слова чар берутся из подсказки предмета ТОЛЬКО по типу строки; нет типа
--      или функции - остаётся номер, и ничего не выдумывается.
--   4. «Не нашёл» не запоминается навсегда и не спрашивается каждый проход.
--   5. Бафф с номером объекта лагеря значит, что объект уже работает: совет
--      поставить его пропадает, и об этом сказано словами.
local H = ...

return function()

-- Баффы -------------------------------------------------------------------

local function modernAuras(env, list)
    env.G.C_UnitAuras = {
        GetAuraDataByIndex = function(unit, index, filter)
            if unit ~= "player" or filter ~= "HELPFUL" then return nil end
            local a = list[index]
            if not a then return nil end
            return { name = a.name, spellId = a.spellID,
                     expirationTime = a.expires, applications = a.stacks }
        end,
    }
end

H.suite("Баффы: читаются современным путём клиента")
do
    local env = H.load()
    local ns = env.ns
    modernAuras(env, {
        { name = "Чародейский интеллект", spellID = 1459, expires = 900, stacks = 0 },
        { name = "Аквариум", spellID = 1255254 },
    })
    local auras, source = ns.Api:PlayerAuras()
    H.eq(#auras, 2, "два баффа прочитаны")
    H.eq(auras[1].name, "Чародейский интеллект", "имя первого")
    H.eq(auras[1].spellID, 1459, "и его номер")
    H.eq(auras[2].spellID, 1255254, "номер второго")
    H.eq(source, "C_UnitAuras.GetAuraDataByIndex", "путь назван")
end

H.suite("Баффы: старый путь UnitBuff читается так же")
do
    local env = H.load()
    local ns = env.ns
    env.G.C_UnitAuras = nil
    -- Порядок ответов старой функции: имя, значок, стаки, тип, длительность,
    -- конец, источник, можно ли украсть, показывать ли на полоске, номер.
    env.G.UnitBuff = function(unit, index, filter)
        if index == 1 then
            return "Чародейский интеллект", 135932, 0, "Magic", 1800, 900,
                "player", false, false, 1459
        elseif index == 2 then
            return "Аквариум", 134437, 3, nil, 3600, 1200, "player", false, false, 1255254
        end
        return nil
    end
    local auras, source = ns.Api:PlayerAuras()
    H.eq(#auras, 2, "два баффа прочитаны")
    H.eq(auras[2].name, "Аквариум", "имя")
    H.eq(auras[2].spellID, 1255254, "номер стоит на десятом месте - и прочитан оттуда")
    H.eq(auras[2].stacks, 3, "стаки на третьем")
    H.eq(auras[2].expires, 1200, "конец действия на шестом")
    H.eq(source, "UnitBuff", "путь назван")
end

H.suite("Баффы: прочитать нечем — это сказано, а не «баффов нет»")
do
    local env = H.load()
    local ns = env.ns
    env.G.C_UnitAuras = nil
    env.G.UnitBuff = nil
    local auras, source = ns.Api:PlayerAuras()
    H.eq(#auras, 0, "список пуст")
    H.eq(source, nil, "и пути нет: это «не знаю», а не «нет»")
    H.build(env)
    local m = ns.Diag:Init().modules.auras
    H.ok(m ~= nil, "в диагностике есть строка про баффы")
    if m then
        H.eq(m.reasonCode, "NO_API", "причина - функции нет, а не «пусто»")
    end
end

H.suite("Баффы: функция упала — аддон не упал")
do
    local env = H.load()
    local ns = env.ns
    env.G.C_UnitAuras = {
        GetAuraDataByIndex = function() error("заблокировано игрой") end,
    }
    local auras = ns.Api:PlayerAuras()
    H.eq(#auras, 0, "ошибка чужой функции наружу не вышла")
end

H.suite("Баффы: поле, которое игра запретила трогать, не роняет пересчёт")
do
    -- У клиента есть «секретные» значения: держать можно, сравнивать и
    -- склеивать нельзя. Здесь такое значение изображает таблица, у которой
    -- любая операция падает, и функция клиента issecretvalue.
    local env = H.load()
    local ns = env.ns
    local SECRET = setmetatable({}, {
        __concat = function() error("секретное значение") end,
        __len = function() error("секретное значение") end,
        __add = function() error("секретное значение") end,
        __eq = function() error("секретное значение") end,
        __tostring = function() error("секретное значение") end,
    })
    env.G.issecretvalue = function(v) return rawequal(v, SECRET) end
    env.G.C_UnitAuras = {
        GetAuraDataByIndex = function(unit, index)
            if index == 1 then return { name = "Сытость", spellId = SECRET } end
            if index == 2 then return { name = SECRET, spellId = 1255254 } end
            if index == 3 then return { name = SECRET, spellId = SECRET } end
            return nil
        end,
    }
    local auras = ns.Api:PlayerAuras()
    H.eq(#auras, 2, "бафф без имени и без номера пропущен, два остались")
    H.eq(auras[1].name, "Сытость", "имя первого прочитано")
    H.eq(auras[1].spellID, nil, "а секретный номер стал nil, а не ошибкой")
    H.eq(auras[2].name, nil, "секретное имя стало nil")
    H.eq(auras[2].spellID, 1255254, "номер второго прочитан")
    -- И весь пересчёт с такими баффами проходит.
    local ok = pcall(function() H.build(env) end)
    H.ok(ok, "пересчёт не упал")
    H.eq(#ns.CharacterScanner:Get().auras, 2, "в снимке те же два")

    -- Без issecretvalue то же самое ловит защищённый вызов.
    env.G.issecretvalue = nil
    local again = ns.Api:PlayerAuras()
    H.eq(#again, 2, "и без подсказки клиента секретное поле не роняет чтение")

    -- Старый путь: секретное имя - это всё ещё бафф, а не конец списка.
    env.G.C_UnitAuras = nil
    env.G.UnitBuff = function(unit, index)
        if index == 1 then return SECRET, 1, 0, nil, 0, 0, "player", false, false, 1255254 end
        if index == 2 then return "Сытость", 1, 0, nil, 0, 0, "player", false, false, 19705 end
        return nil
    end
    local old = ns.Api:PlayerAuras()
    H.eq(#old, 2, "секретное имя список не оборвало")
    H.eq(old[1].spellID, 1255254, "номер при секретном имени прочитан")
    H.eq(old[2].name, "Сытость", "и следующий бафф тоже")
end

H.suite("Баффы: попадают в снимок персонажа и в диагностику")
do
    local env = H.load()
    local ns = env.ns
    modernAuras(env, {
        { name = "Чародейский интеллект", spellID = 1459 },
        { name = "Сытость", spellID = 19705 },
    })
    H.build(env)
    local snap = ns.CharacterScanner:Get()
    H.eq(#snap.auras, 2, "в снимке два баффа")
    H.ok(snap.auraByName["Сытость"] ~= nil, "и найти бафф по имени можно")
    local m = ns.Diag:Init().modules.auras
    H.ok(m ~= nil, "строка про баффы в диагностике есть")
    if m then
        H.eq(m.out, 2, "их два")
        H.eq(m.names[2], "Сытость#19705", "имя записано вместе с номером")
        H.eq(m.reasonCode, nil, "причины нет: прочитано")
    end

    -- Баффы спали: пустой список - это «прочитано, пусто».
    modernAuras(env, {})
    H.build(env)
    local empty = ns.Diag:Init().modules.auras
    H.eq(empty.out, 0, "баффов не осталось")
    H.eq(empty.reasonCode, "EMPTY", "и это «пусто», а не «читать нечем»")
end

-- Слова чар ---------------------------------------------------------------

local ENCHANT_LINE = 15

local function tooltipWorld(lines)
    local env = H.load()
    local calls = { n = 0 }
    env.G.Enum = env.G.Enum or {}
    env.G.Enum.TooltipDataLineType = { ItemEnchantmentPermanent = ENCHANT_LINE }
    env.G.C_TooltipInfo = {
        GetInventoryItem = function(unit, invID)
            calls.n = calls.n + 1
            return { lines = lines() }
        end,
    }
    return env, env.ns, calls
end

H.suite("Чары: слова берутся из подсказки по типу строки")
do
    local env, ns, calls = tooltipWorld(function()
        return {
            { type = 0, leftText = "Мерцающий посох" },
            { type = 0, leftText = "+11 к интеллекту" },
            { type = ENCHANT_LINE, leftText = "|cff00ff00+22 к интеллекту|r" },
        }
    end)
    local text = ns.Api:InventoryEnchantText(16, 8217, 1904)
    H.eq(text, "+22 к интеллекту", "строка чар прочитана, разметка цвета убрана")
    -- Та же вещь с теми же чарами: второй раз игру не спрашиваем.
    local again = ns.Api:InventoryEnchantText(16, 8217, 1904)
    H.eq(again, "+22 к интеллекту", "ответ тот же")
    H.eq(calls.n, 1, "и подсказка прочитана один раз")
end

H.suite("Чары: обычная зелёная строка за чары не выдаётся")
do
    -- Типа «чары» в подсказке нет: брать строку по цвету или по месту значило
    -- бы показать игроку характеристику вещи под видом чар.
    local env, ns = tooltipWorld(function()
        return {
            { type = 0, leftText = "Мерцающий посох" },
            { type = 0, leftText = "|cff00ff00+11 к интеллекту|r" },
        }
    end)
    H.eq(ns.Api:InventoryEnchantText(16, 8217, 1904), nil,
        "строки с типом чар нет - ответа нет")
end

H.suite("Чары: нет функции — остаётся номер, ничего не выдумано")
do
    local env = H.load()
    local ns = env.ns
    env.G.C_TooltipInfo = nil
    H.eq(ns.Api:InventoryEnchantText(16, 8217, 1904), nil, "нет функции - nil")
    H.eq(ns.Api.enchantTextPath, false, "и это записано как «пути нет»")
end

H.suite("Чары: «не нашёл» не навсегда и не каждый проход")
do
    local ready = false
    local env, ns, calls = tooltipWorld(function()
        if not ready then return { { type = 0, leftText = "Получение сведений" } } end
        return { { type = ENCHANT_LINE, leftText = "+4 ко всем характеристикам" } }
    end)
    H.eq(ns.Api:InventoryEnchantText(5, 301, 843), nil, "подсказка ещё неполная")
    H.eq(calls.n, 1, "спросили один раз")
    for i = 1, 10 do ns.Api:InventoryEnchantText(5, 301, 843) end
    H.eq(calls.n, 1, "десять проходов подряд - игру больше не дёргали")
    ready = true
    H.clock = H.clock + ns.Api.ENCHANT_TEXT_RETRY + 1
    H.eq(ns.Api:InventoryEnchantText(5, 301, 843), "+4 ко всем характеристикам",
        "через минуту спросили снова - и прочитали")
    H.eq(calls.n, 2, "ровно один повторный вопрос")
end

H.suite("Чары: в карточке стоят слова, а не номер")
do
    local env = H.load()
    local ns = env.ns
    env.player.classFile = "MAGE"
    env.player.level = 26
    H.item(env, 300, { name = "Наручи", equipLoc = "INVTYPE_WRIST",
        classID = 4, subclassID = 1 })
    H.item(env, 301, { name = "Нагрудник", equipLoc = "INVTYPE_CHEST",
        classID = 4, subclassID = 1 })
    H.item(env, 400, { name = "Пыль", sellPrice = 100 })
    env.prices[400] = 1000
    env.equipped.WRIST = { itemID = 300 }
    env.equipped.CHEST = { itemID = 301, enchantID = 843,
                           enchantText = "+4 ко всем характеристикам" }
    H.profession(env, "Enchanting", 225, 225, {
        H.recipe { id = 99999, name = "Чары для наручей: невыученные",
                   reagents = { { itemID = 400, qty = 1 } }, learned = false,
                   category = "Чары для наручей", categoryID = 10 },
        -- Без формулы на нагрудник слот «грудь» зачаровываемым не числится:
        -- список слотов выводится из категорий формул, а не вписан руками.
        H.recipe { id = 13858, name = "Чары для нагрудника: выносливость",
                   reagents = { { itemID = 400, qty = 3 } }, learned = true,
                   category = "Чары для нагрудника", categoryID = 11 },
    })
    local cards = H.build(env)
    local found
    for _, c in ipairs(cards) do
        if ns.Util.contains(c.why or "", "Уже зачарованы") then found = c end
    end
    H.ok(found ~= nil, "карточка про чары есть")
    if found then
        H.ok(ns.Util.contains(found.why, "«+4 ко всем характеристикам»"),
            "в ней слова чар: " .. ns.Util.truncate(found.why, 200))
        H.ok(not ns.Util.contains(found.why, "#843"), "а номера нет")
        H.ok(not ns.Util.contains(found.why, "по номеру я сказать не могу"),
            "и оговорки про номер нет: говорить её не о чем")
    end

    -- Игра слов не отдала: остаётся номер и честная оговорка.
    env.equipped.CHEST = { itemID = 301, enchantID = 843 }
    local cards2 = H.build(env)
    local numbered
    for _, c in ipairs(cards2) do
        if ns.Util.contains(c.why or "", "Уже зачарованы") then numbered = c end
    end
    H.ok(numbered ~= nil, "карточка есть и без слов")
    if numbered then
        H.ok(ns.Util.contains(numbered.why, "#843"), "в ней номер")
        H.ok(ns.Util.contains(numbered.why, "выдумывать не буду"),
            "и сказано, что по номеру эффект не назвать")
    end
end

end
