-- ForeverPilot / Tests/test_quiet.lua
--
-- АДДОН НЕ ДЁРГАЕТ ИГРУ, ПОКА НА НЕГО НИКТО НЕ СМОТРИТ.
--
-- Живые цифры (маг 31 ур., 2026-11-21, сеанс 23 минуты, окно и панель закрыты):
-- 83 полных пересчёта, в среднем 84 мс, пик 143 мс. Это рывок кадра раз в 17
-- секунд ради списка, которого никто не видел. Слова игрока: «ни в коем случае
-- не приводить к фризам».
--
-- Набор держит шесть контрактов (UI/MainFrame.lua, Main:ShouldDefer):
--   1. никто не смотрит - сумки, деньги, подгрузка имён, крафт и аукцион
--      пересчёта не стоят;
--   2. важная причина (навык, уровень, спек) считается и при закрытом окне, и
--      раз в ns.HIDDEN_REBUILD_SECONDS пересчёт делается всё равно;
--   3. на бегу не считаем вовсе - кроме случая, когда окно открыли руками;
--   4. пока идёт полоска заклинания или крафта - тоже не считаем;
--   5. окно открыто - мелочи не чаще раза в ns.VISIBLE_SOFT_SECONDS;
--   6. отложенное не теряется: как только можно, оно догоняется.
local H = ...
local S = assert(loadfile((H.ROOT or ".") .. "/Tests/uistub.lua"))()

return function()

local function world()
    -- Мир с интерфейсом: окно - часть того, что проверяется. Само окно не
    -- строится (MainFrame:Build не зовётся), поэтому на экране его нет - ровно
    -- как у игрока с закрытым окном.
    local env = S.load(H)
    local ns = env.ns
    -- Панель шага выключена, как у игрока из жалобы: иначе она на экране, а
    -- значит на советы смотрят, и считать надо (это проверяет отдельный набор
    -- ниже).
    ns.Config:Get().panel.enabled = false
    local count = { n = 0 }
    local realBuild = ns.ActionEngine.Build
    ns.ActionEngine.Build = function(self, ...)
        count.n = count.n + 1
        return realBuild(self, ...)
    end
    env.G.GetUnitSpeed = function() return env.moving and 7 or 0 end
    env.G.UnitCastingInfo = function(unit)
        if env.casting then return "Жемчужный кушак" end
        return nil
    end
    env.G.UnitChannelInfo = function(unit)
        if env.channeling then return "Рыбная ловля" end
        return nil
    end
    return env, ns, count
end

local function shownFrame()
    return { IsShown = function() return true end }
end

H.suite("Тишина: первый пересчёт делается всегда")
do
    local env, ns, count = world()
    local M = ns.MainFrame
    H.eq(M:AnyoneWatching(), false, "окно не построено - никто не смотрит")
    H.eq((M:ShouldDefer({ bags = true })), nil,
        "первый пересчёт не откладывается: списка ещё нет вовсе")
    M:Rebuild(false, { bags = true })
    H.eq(count.n, 1, "и он случился")
    H.eq(M.stale, nil, "долга нет")
end

H.suite("Тишина: окно закрыто - сумки и деньги пересчёта не стоят")
do
    local env, ns, count = world()
    local M = ns.MainFrame
    M:Rebuild(false, { bags = true })
    local before = count.n
    H.clock = H.clock + 20
    for _, reasons in ipairs({ { bags = true }, { money = true }, { items = true },
                               { equipment = true }, { idle = true } }) do
        M:Rebuild(false, reasons)
    end
    H.eq(count.n, before, "пять поводов подряд - ни одного пересчёта")
    H.eq(M.stale, true, "но долг записан")
    H.ok((ns.Diag:Init().counters["recompute.deferred.hidden"] or 0) >= 5,
        "и отложенное посчитано в диагностике")
end

H.suite("Тишина: важная причина считается и при закрытом окне")
do
    local env, ns, count = world()
    local M = ns.MainFrame
    M:Rebuild(false, { bags = true })
    for _, flag in ipairs({ "skillcap", "character", "level", "spec" }) do
        local before = count.n
        H.clock = H.clock + 5
        M:Rebuild(false, { [flag] = true })
        H.eq(count.n, before + 1, "причина «" .. flag .. "» - пересчёт сделан")
    end
end

H.suite("Тишина: крафт и аукцион закрытый аддон не дёргают")
do
    -- TRADE_SKILL_LIST_UPDATE приходит на каждую сделанную вещь, событие
    -- аукциона - на каждый поиск. Окно закрыто - считать не для кого.
    local env, ns, count = world()
    local M = ns.MainFrame
    M:Rebuild(false, { bags = true })
    local before = count.n
    for i = 1, 20 do
        H.clock = H.clock + 2
        M:Rebuild(false, { recipes = true })
        M:Rebuild(false, { prices = true, auctionScan = true })
    end
    H.eq(count.n, before, "сорок событий крафта и аукциона - ни одного пересчёта")
    H.ok(M.stale == true, "но список помечен устаревшим")
    M:Show()
    H.eq(count.n, before + 1, "и пересчитан сразу, как только окно открыли")
end

H.suite("Тишина: раз в положенный срок пересчёт делается всё равно")
do
    local env, ns, count = world()
    local M = ns.MainFrame
    M:Rebuild(false, { bags = true })
    local before = count.n
    H.clock = H.clock + (ns.HIDDEN_REBUILD_SECONDS - 5)
    M:Rebuild(false, { bags = true })
    H.eq(count.n, before, "срок не вышел - не считаем")
    H.clock = H.clock + 10
    M:Rebuild(false, { bags = true })
    H.eq(count.n, before + 1, "срок вышел - считаем")
end

H.suite("Тишина: окно на экране - считаем как раньше")
do
    local env, ns, count = world()
    local M = ns.MainFrame
    M:Rebuild(false, { bags = true })
    local saved = M.frame
    M.frame = shownFrame()
    H.eq(M:AnyoneWatching(), true, "на окно смотрят")
    local before = count.n
    H.clock = H.clock + 5
    pcall(function() M:Rebuild(false, { bags = true }) end)
    H.eq(count.n, before + 1, "сумки изменились - список пересчитан")
    M.frame = saved
end

H.suite("Тишина: панель шага на экране - это тоже «смотрят»")
do
    local env, ns, count = world()
    local M = ns.MainFrame
    ns.Config:Get().panel.enabled = true
    M:Rebuild(false, { bags = true })
    H.eq(M:AnyoneWatching(), true, "панель построена и показана")
    local before = count.n
    H.clock = H.clock + 5
    M:Rebuild(false, { bags = true })
    H.eq(count.n, before + 1, "сумки изменились - панель получает свежий список")
end

H.suite("Тишина: на бегу не считаем, а встал - догоняем")
do
    local env, ns, count = world()
    local M = ns.MainFrame
    M:Rebuild(false, { bags = true })
    local saved = M.frame
    M.frame = shownFrame()
    env.moving = true
    local before = count.n
    H.clock = H.clock + 5
    pcall(function() M:Rebuild(false, { bags = true, skillcap = true }) end)
    H.eq(count.n, before, "игрок бежит - пересчёта нет даже при открытом окне")
    H.eq(M.stale, true, "долг записан")
    H.eq(M.staleImportant, true, "и помнит, что причина была важной")
    H.clock = H.clock + 5
    M:CatchUp(H.clock)
    H.eq(count.n, before, "всё ещё бежит - всё ещё не считаем")
    env.moving = false
    H.clock = H.clock + 5
    pcall(function() M:CatchUp(H.clock) end)
    H.eq(count.n, before + 1, "встал - пересчёт догнан")
    H.eq(M.stale, nil, "долг погашен")
    M.frame = saved
end

H.suite("Тишина: пока идёт крафт или заклинание, не считаем - даже с открытым окном")
do
    -- Очередь крафта: событие окна профессии на каждую вещь. Пересчёт на
    -- каждое дёргал бы кадр всю очередь - поэтому ждём конца полоски.
    local env, ns, count = world()
    local M = ns.MainFrame
    M.frame = shownFrame()
    M:Rebuild(false, { bags = true })
    local before = count.n
    env.casting = true
    for i = 1, 10 do
        H.clock = H.clock + 3
        M:Rebuild(false, { bags = true, recipes = true })
    end
    H.eq(count.n, before, "десять вещей в очереди - ни одного пересчёта")
    H.ok(M.stale == true, "список помечен устаревшим")
    H.ok((ns.Diag:Init().counters["recompute.deferred.casting"] or 0) >= 10,
        "причина отсрочки посчитана")
    env.casting = false
    H.clock = H.clock + 2
    M:CatchUp(H.clock)
    H.eq(count.n, before + 1, "полоска кончилась - один пересчёт, догнали")
    H.eq(M.stale, nil, "долга нет")

    -- Потоковое заклинание (рыбалка) - то же самое.
    env.channeling = true
    H.clock = H.clock + 3
    M:Rebuild(false, { bags = true })
    H.eq(count.n, before + 1, "на рыбалке не считаем")
    env.channeling = false
    H.clock = H.clock + 2
    M:CatchUp(H.clock)
    H.eq(count.n, before + 2, "поплавок вытащен - догнали")
end

H.suite("Тишина: функций про заклинания нет - считаем как раньше")
do
    local env, ns, count = world()
    env.G.UnitCastingInfo, env.G.UnitChannelInfo = nil, nil
    H.eq(ns.Api:PlayerCasting(), false, "нет функций - ответ «не произносит»")
    -- Чужая функция упала: наружу ошибка не выходит.
    env.G.UnitCastingInfo = function() error("заблокировано") end
    H.eq(ns.Api:PlayerCasting(), false, "ошибка чужой функции - тоже «нет»")
end

H.suite("Тишина: окно открыто - мелочи не чаще раза в несколько секунд")
do
    -- Аукцион и торговец шлют события пачками. Пересчёт на каждую пачку - это
    -- рывок кадра раз в полторы секунды всё время, пока окно открыто.
    local env, ns, count = world()
    local M = ns.MainFrame
    M.frame = shownFrame()
    M:Rebuild(false, { bags = true })
    local before = count.n
    for i = 1, 3 do
        H.clock = H.clock + 1
        M:Rebuild(false, { items = true, prices = true, bags = true, money = true })
    end
    H.eq(count.n, before, "три пачки за три секунды - пересчёта нет")
    H.ok(M.stale == true, "но долг записан")
    H.ok((ns.Diag:Init().counters["recompute.deferred.recent"] or 0) >= 3,
        "причина отсрочки посчитана")
    -- Важное и жест игрока этот срок не ждут.
    H.clock = H.clock + 0.5
    M:Rebuild(false, { level = true })
    H.eq(count.n, before + 1, "новый уровень - считаем сразу")
    H.clock = H.clock + 0.5
    M:Rebuild(false, { opened = true })
    H.eq(count.n, before + 2, "жест игрока в окне - считаем сразу")
    -- Мелочь после этого снова ждёт своего срока и догоняется сама.
    H.clock = H.clock + 1
    M:Rebuild(false, { bags = true })
    H.eq(count.n, before + 2, "сумки через секунду после пересчёта - ждут")
    H.clock = H.clock + ns.VISIBLE_SOFT_SECONDS
    M:CatchUp(H.clock)
    H.eq(count.n, before + 3, "срок вышел - догнали без нового события")
    H.eq(M.stale, nil, "долга нет")
end

H.suite("Тишина: окно открыли руками - считаем сразу, даже на бегу")
do
    local env, ns, count = world()
    local M = ns.MainFrame
    M:Rebuild(false, { bags = true })
    env.moving = true
    local before = count.n
    H.clock = H.clock + 5
    M:Rebuild(false, { opened = true })
    H.eq(count.n, before + 1, "открытие окна - это просьба показать, её не откладывают")
end

H.suite("Тишина: кнопка «Обновить» не откладывается никогда")
do
    local env, ns, count = world()
    local M = ns.MainFrame
    M:Rebuild(false, { bags = true })
    env.moving = true
    local before = count.n
    H.clock = H.clock + 1
    M:Rebuild(true)
    H.eq(count.n, before + 1, "принудительный пересчёт сделан")
end

H.suite("Тишина: бой - не считаем и не забываем")
do
    local env, ns, count = world()
    local M = ns.MainFrame
    M:Rebuild(false, { bags = true })
    env.inCombat = true
    local before = count.n
    H.clock = H.clock + 5
    M:Rebuild(false, { skillcap = true })
    H.eq(count.n, before, "в бою пересчёта нет")
    H.eq(M.stale, true, "но долг записан")
    env.inCombat = false
end

end
