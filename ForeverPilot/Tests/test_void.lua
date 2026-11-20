-- ForeverPilot / Tests/test_void.lua
--
-- СЛОВАРЬ ПУСТОТЫ. Четыре причины, по которым числа на экране нет, и правило
-- про возраст цены. См. ns.VOID в Core/Const.lua: там написано, почему эти
-- четыре случая обязаны выглядеть по-разному.
--
-- Главная проверка здесь одна и она простая до скуки: НИ ОДНО из состояний не
-- отображается так же, как другое. До словаря все четыре сливались в прочерк,
-- и человек не мог отличить «делать нечего» от «сходи на аукцион».
--
-- Run with:  FP_SUITE=test_void texluajit Tests/one.lua

local H = ...

return function()

local env = H.load()
local ns = env.ns
local U = ns.Util
local CONF = ns.CONF
local VOID = ns.VOID

H.suite("Пустота: словарь заведён и у каждого состояния своё лицо")
do
    H.ok(type(ns.VOID) == "table", "ns.VOID есть")
    H.ok(type(ns.VOID_TEXT) == "table", "ns.VOID_TEXT есть")
    H.ok(type(ns.VOID_WHY) == "table", "ns.VOID_WHY есть")

    for _, key in ipairs({ "IMPOSSIBLE", "UNKNOWN", "NO_PRICE" }) do
        H.ok(ns.VOID[key] == key, "состояние " .. key .. " названо")
        H.ok(type(ns.VOID_TEXT[key]) == "string" and ns.VOID_TEXT[key] ~= "",
            "у " .. key .. " есть обозначение: «" .. tostring(ns.VOID_TEXT[key]) .. "»")
        H.ok(type(ns.VOID_WHY[key]) == "string" and ns.VOID_WHY[key] ~= "",
            "и объяснение словами: «" .. tostring(ns.VOID_WHY[key]) .. "»")
    end

    -- «так нельзя» - ОДНИМ ЗНАКОМ, «не знаю» - ДРУГИМ.
    H.eq(U.charLen(ns.VOID_TEXT.IMPOSSIBLE), 1, "«так нельзя» - это один знак")
    H.eq(U.charLen(ns.VOID_TEXT.UNKNOWN), 1, "«не знаю» - тоже один знак")
    H.ok(ns.VOID_TEXT.IMPOSSIBLE ~= ns.VOID_TEXT.UNKNOWN,
        "и это РАЗНЫЕ знаки")
    -- «нет цены» - СЛОВАМИ, а не прочерком.
    H.ok(U.charLen(ns.VOID_TEXT.NO_PRICE) > 3,
        "«нет цены» сказано словами, а не знаком: «" .. ns.VOID_TEXT.NO_PRICE .. "»")
    H.ok(ns.VOID_TEXT.NO_PRICE:find("%a") ~= nil or ns.VOID_TEXT.NO_PRICE:find("[\208\209]") ~= nil,
        "и в нём есть буквы")
end

H.suite("Пустота: четыре состояния на экране различимы попарно")
do
    -- Вот те самые четыре строки, которые игрок видит в графе с деньгами.
    local shown = {
        ["так нельзя"] = U.void(VOID.IMPOSSIBLE),
        ["не знаю"]    = U.void(VOID.UNKNOWN),
        ["нет цены"]   = U.void(VOID.NO_PRICE),
        -- Оценка - это не пустота: число есть, но оно наше. Берём настоящую
        -- строку из настоящей функции показа цены.
        ["оценка"]     = U.priceText(2500, CONF.ESTIMATE, 60),
    }
    local names = {}
    for name in pairs(shown) do names[#names + 1] = name end
    table.sort(names)

    local clashes = {}
    for i = 1, #names do
        for j = i + 1, #names do
            if shown[names[i]] == shown[names[j]] then
                clashes[#clashes + 1] = "«" .. names[i] .. "» и «" .. names[j]
                    .. "» показываются одинаково: " .. tostring(shown[names[i]])
            end
        end
    end
    H.eq(#clashes, 0, "ни одно из четырёх состояний не выглядит как другое"
        .. ((#clashes > 0) and ("  <- " .. table.concat(clashes, "; ")) or ""))
    for _, name in ipairs(names) do
        print("     «" .. name .. "» -> " .. tostring(shown[name]))
    end

    -- И ни одно из них не читается как ноль: в графе с деньгами «0м» значит
    -- «бесплатно», и спутать это с пустотой - самая дорогая из путаниц.
    for _, name in ipairs(names) do
        H.ok(shown[name] ~= "0м" and shown[name] ~= "0",
            "«" .. name .. "» не показывается нулём")
    end
end

H.suite("Пустота: цена без числа называет ПРИЧИНУ, а не прочерк")
do
    -- Цена, которой нет: по умолчанию это «нет цены» словами.
    H.eq(U.priceText(nil), ns.VOID_TEXT.NO_PRICE,
        "цены нет - так и написано словами")
    -- А если звать явно - то, что попросили.
    H.eq(U.priceText(nil, nil, nil, VOID.IMPOSSIBLE), ns.VOID_TEXT.IMPOSSIBLE,
        "«продавать нечего» - знак «так нельзя»")
    H.eq(U.priceText(nil, nil, nil, VOID.UNKNOWN), ns.VOID_TEXT.UNKNOWN,
        "«не знаю» - свой знак")

    -- U.money без числа - это «не знаю»: функция не в курсе, почему числа нет,
    -- и выдумывать причину она не вправе. Прочерк тут был бы утверждением
    -- «такого не бывает», которого она сделать не может.
    H.eq(U.money(nil), ns.VOID_TEXT.UNKNOWN, "U.money(nil) - «не знаю», не прочерк")
    H.eq(U.moneyDelta(nil), ns.VOID_TEXT.UNKNOWN,
        "U.moneyDelta(nil) - «не знаю», а НЕ «0м»")
    H.eq(U.moneyDelta(0), "0м", "а настоящий ноль остаётся нулём")
end

H.suite("Пустота: возраст цены виден ВСЕГДА")
do
    local fresh = U.priceText(2500, CONF.CACHED, 120)
    local old   = U.priceText(2500, CONF.CACHED, 3 * 86400)
    local noAge = U.priceText(2500, CONF.CACHED, nil)
    local timeless = U.priceText(2500, CONF.EXACT, false)

    H.ok(fresh:find("назад") ~= nil or fresh:find(ns.AGE_JUST_NOW) ~= nil,
        "у свежей цены возраст написан: " .. fresh)
    H.ok(old:find("назад") ~= nil, "у старой тоже: " .. old)
    H.ok(noAge:find(ns.AGE_UNKNOWN) ~= nil,
        "и когда возраст неизвестен - так и сказано: " .. noAge)
    H.ok(timeless:find(ns.AGE_TIMELESS) ~= nil,
        "а цена из данных предмета не стареет, и это тоже сказано: " .. timeless)

    -- Ровно та ошибка, из-за которой правило появилось: свежая и бессрочная
    -- цены печатались одинаково.
    H.ok(fresh ~= noAge, "свежая цена и цена без возраста выглядят по-разному")
    H.ok(fresh ~= timeless, "свежая и нестареющая - тоже")

    -- Возраст не прячется ни при какой достоверности.
    for _, conf in ipairs({ CONF.EXACT, CONF.CACHED, CONF.ESTIMATE, CONF.UNKNOWN }) do
        local t = U.priceText(2500, conf, 600)
        H.ok(t:find("назад") ~= nil,
            "при достоверности «" .. (ns.CONF_LABEL[conf] or conf)
                .. "» возраст на месте: " .. t)
    end
end

H.suite("Пустота: оценка помечена на самом числе")
do
    local exact = U.priceText(2500, CONF.EXACT, 600)
    local est   = U.priceText(2500, CONF.ESTIMATE, 600)
    local unk   = U.priceText(2500, CONF.UNKNOWN, 600)

    H.ok(est:find(ns.ESTIMATE_MARK, 1, true) ~= nil,
        "у оценки есть знак «" .. ns.ESTIMATE_MARK .. "»: " .. est)
    H.ok(est:find(ns.ESTIMATE_WORD, 1, true) ~= nil,
        "и слово «" .. ns.ESTIMATE_WORD .. "»: " .. est)
    H.ok(exact:find(ns.ESTIMATE_MARK, 1, true) == nil,
        "у точного числа пометки оценки нет: " .. exact)
    H.ok(est ~= exact, "оценка и точное число выглядят по-разному")
    H.ok(unk:find(ns.ESTIMATE_WORD, 1, true) ~= nil,
        "число с достоверностью «неизвестно» тоже помечено как оценка: " .. unk)
end

H.suite("Пустота: обходных прочерков в коде больше нет")
do
    -- СЛОВАРЬ НАДО НЕ ТОЛЬКО ЗАВЕСТИ, НО И НЕ ОБОЙТИ.
    --
    -- Прочерк, вписанный по месту (`value or "—"`), - это утверждение «такого
    -- значения не бывает», сделанное кодом, который о причине ничего не знает.
    -- Таких мест было пять, и в каждом прочерк значил своё. Проверка идёт по
    -- всем файлам из .toc: новое такое место нельзя добавить незаметно.
    --
    -- Разрешены ровно два случая, и оба названы: сам словарь (Core/Const.lua)
    -- и подпись кнопки «свернуть» на панели шага - там это не значение, а
    -- рисунок на кнопке.
    local ALLOWED = {
        ["Core/Const.lua"] = true,
        ["UI/StepPanel.lua"] = true,
    }
    local BYPASS = {
        { pat = '"—"', what = "прочерк вписан по месту вместо U.void" },
        { pat = "'—'", what = "прочерк вписан по месту вместо U.void" },
        { pat = '"цена неизвестна"', what = "своя фраза вместо U.void(ns.VOID.NO_PRICE)" },
        { pat = '"цены неизвестны"', what = "своя фраза вместо U.void(ns.VOID.NO_PRICE)" },
        { pat = '"неизвестна"', what = "своя фраза вместо словаря пустоты" },
    }

    local files = {}
    do
        local toc = io.open(H.ROOT .. "/ForeverPilot.toc", "r")
        if toc then
            for line in toc:lines() do
                local rel = line:gsub("\r", ""):gsub("\\", "/")
                    :gsub("^%s+", ""):gsub("%s+$", "")
                if rel:match("%.lua$") then files[#files + 1] = rel end
            end
            toc:close()
        end
    end
    H.ok(#files >= 40, "файлов из .toc под проверкой: " .. #files)

    local hits = {}
    for _, rel in ipairs(files) do
        if not ALLOWED[rel] then
            local fh = io.open(H.ROOT .. "/" .. rel, "r")
            if fh then
                local n = 0
                for line in fh:lines() do
                    n = n + 1
                    -- Комментарии пропускаются: про прочерк можно РАССКАЗЫВАТЬ.
                    local code = line:gsub("%-%-.*$", "")
                    for _, b in ipairs(BYPASS) do
                        if code:find(b.pat, 1, true) then
                            hits[#hits + 1] = rel .. ":" .. n .. " — " .. b.what
                        end
                    end
                end
                fh:close()
            end
        end
    end
    H.eq(#hits, 0, "ни одного обхода словаря пустоты"
        .. ((#hits > 0) and ("  <- " .. table.concat(hits, "; ")) or ""))
end

H.suite("Пустота: словарь применён там, где игрок видит цену")
do
    -- Подпись цены из PriceProvider - то, что стоит на карточках и в развилке
    -- путей. Без цены она обязана говорить словами.
    local label = ns.PriceProvider:Label(nil, CONF.UNKNOWN, "none")
    H.eq(label, ns.VOID_TEXT.NO_PRICE, "подпись цены без числа: " .. tostring(label))

    -- С ценой - и возраст, и источник.
    local withPrice = ns.PriceProvider:Label(2500, CONF.CACHED, "auctionator", 7200)
    H.ok(withPrice:find("аукцион") ~= nil, "источник назван: " .. withPrice)
    H.ok(withPrice:find("назад") ~= nil, "и возраст: " .. withPrice)

    -- Источник без возраста: возраст всё равно назван.
    local noAge = ns.PriceProvider:Label(2500, CONF.CACHED, "auctionator", nil)
    H.ok(noAge:find(ns.AGE_UNKNOWN) ~= nil,
        "когда возраста нет - так и написано: " .. noAge)

    -- Цена торговца из данных предмета не стареет.
    local vendor = ns.PriceProvider:Label(300, CONF.EXACT, "vendor", false)
    H.ok(vendor:find(ns.AGE_TIMELESS) ~= nil, "цена торговца: " .. vendor)
end

end
