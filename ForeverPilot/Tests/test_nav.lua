-- ForeverPilot / Tests/test_nav.lua
--
-- Navigation: the bearing and distance maths on known coordinate pairs, and
-- every degraded state the arrow has to survive - no facing, target on another
-- map, no coordinates at all, TomTom chosen, routing switched off.
local H = ...

return function()

local pi = math.pi

-- Bearings --------------------------------------------------------------
-- Map space: x grows east, y grows SOUTH. Bearings run clockwise from north.

H.suite("Геометрия: азимут по четырём сторонам")
do
    local env = H.load()
    local Geo = env.ns.Geo
    -- Player in the middle of the map.
    local px, py = 0.5, 0.5
    H.near(Geo.Bearing(px, py, 0.5, 0.3), 0, 1e-9, "север = 0")
    H.near(Geo.Bearing(px, py, 0.7, 0.5), pi / 2, 1e-9, "восток = pi/2")
    H.near(math.abs(Geo.Bearing(px, py, 0.5, 0.7)), pi, 1e-9, "юг = pi")
    H.near(Geo.Bearing(px, py, 0.3, 0.5), -pi / 2, 1e-9, "запад = -pi/2")
end

H.suite("Геометрия: азимут по диагоналям")
do
    local env = H.load()
    local Geo = env.ns.Geo
    local px, py = 0.5, 0.5
    -- North-east: x up, y down by the same amount.
    H.near(Geo.Bearing(px, py, 0.6, 0.4), pi / 4, 1e-9, "северо-восток = pi/4")
    H.near(Geo.Bearing(px, py, 0.6, 0.6), 3 * pi / 4, 1e-9, "юго-восток = 3pi/4")
    H.near(Geo.Bearing(px, py, 0.4, 0.6), -3 * pi / 4, 1e-9, "юго-запад = -3pi/4")
    H.near(Geo.Bearing(px, py, 0.4, 0.4), -pi / 4, 1e-9, "северо-запад = -pi/4")
end

H.suite("Геометрия: азимут на самого себя не определён")
do
    local env = H.load()
    local Geo = env.ns.Geo
    H.eq(Geo.Bearing(0.5, 0.5, 0.5, 0.5), nil, "совпадающие точки - nil")
    H.eq(Geo.Bearing(0.5, 0.5, 0.5 + 1e-12, 0.5), nil, "разница ниже порога - nil")
    H.eq(Geo.Bearing(nil, 0.5, 0.5, 0.5), nil, "nil на входе - nil")
    H.eq(Geo.Bearing(0.5, 0.5, "мусор", 0.5), nil, "мусор на входе - nil")
end

H.suite("Геометрия: нормализация угла")
do
    local env = H.load()
    local Geo = env.ns.Geo
    H.near(Geo.normalize(0), 0, 1e-9, "ноль")
    H.near(Geo.normalize(pi), pi, 1e-9, "pi остаётся pi")
    H.near(Geo.normalize(3 * pi), pi, 1e-9, "3pi -> pi")
    H.near(Geo.normalize(2 * pi + 0.5), 0.5, 1e-9, "оборот отбрасывается")
    H.near(Geo.normalize(-3 * pi / 2), pi / 2, 1e-9, "-3pi/2 -> pi/2")
    H.ok(Geo.normalize(5 * pi) <= pi and Geo.normalize(5 * pi) > -pi,
        "результат в (-pi, pi]")
end

-- Arrow rotation --------------------------------------------------------

H.suite("Геометрия: поворот стрелки учитывает взгляд игрока")
do
    local env = H.load()
    local Geo = env.ns.Geo
    -- Target due north, player facing north: the arrow points straight up,
    -- so the rotation is zero.
    local rot = Geo.ArrowRotation(0, 0)
    H.near(rot, 0, 1e-9, "цель на север, смотрим на север - стрелка вверх")

    -- Target north, player facing west (GetPlayerFacing grows counter-clockwise,
    -- so west = pi/2). North is then to the player's RIGHT, i.e. clockwise by
    -- pi/2, and SetRotation turns counter-clockwise, so the value is -pi/2.
    local rot2, cw2 = Geo.ArrowRotation(0, pi / 2)
    H.near(cw2, pi / 2, 1e-9, "север оказывается справа (по часовой pi/2)")
    H.near(rot2, -pi / 2, 1e-9, "а значение для SetRotation с обратным знаком")

    -- Target east, player facing east. GetPlayerFacing: east is -pi/2
    -- (clockwise from north is negative in that convention).
    local _, cw3 = Geo.ArrowRotation(pi / 2, -pi / 2)
    H.near(cw3, 0, 1e-9, "цель на восток, смотрим на восток - стрелка вверх")

    -- Target behind: player faces north, target is south.
    local _, cw4 = Geo.ArrowRotation(pi, 0)
    H.near(math.abs(cw4), pi, 1e-9, "цель за спиной - стрелка вниз")
end

H.suite("Геометрия: без направления взгляда поворота нет")
do
    local env = H.load()
    local Geo = env.ns.Geo
    H.eq(Geo.ArrowRotation(0, nil), nil,
        "нет GetPlayerFacing - нет поворота, а не нулевой поворот")
    H.eq(Geo.ArrowRotation(nil, 0), nil, "нет азимута - нет поворота")
end

-- Distance --------------------------------------------------------------

H.suite("Геометрия: расстояние в ярдах по размеру карты")
do
    local env = H.load()
    local Geo = env.ns.Geo
    -- A 1000 x 500 yard map. Half the width east = 500 yards.
    H.near(Geo.Distance(0.0, 0.5, 0.5, 0.5, 1000, 500), 500, 1e-6,
        "полкарты по ширине = 500 ярдов")
    H.near(Geo.Distance(0.5, 0.0, 0.5, 1.0, 1000, 500), 500, 1e-6,
        "вся карта по высоте = 500 ярдов")
    -- 3-4-5 triangle: 0.3 * 1000 = 300 east, 0.8 * 500 = 400 south -> 500.
    H.near(Geo.Distance(0.0, 0.0, 0.3, 0.8, 1000, 500), 500, 1e-6,
        "катеты 300 и 400 дают гипотенузу 500")
    H.near(Geo.Distance(0.5, 0.5, 0.5, 0.5, 1000, 500), 0, 1e-9, "та же точка - ноль")
end

H.suite("Геометрия: без размера карты ярды не выдумываются")
do
    local env = H.load()
    local Geo = env.ns.Geo
    H.eq(Geo.Distance(0, 0, 0.5, 0.5, nil, nil), nil,
        "нет размера карты - нет ярдов")
    H.eq(Geo.Distance(0, 0, 0.5, 0.5, 0, 0), nil, "нулевой размер - nil")
    H.eq(Geo.Distance(0, 0, 0.5, 0.5, -100, 100), nil, "отрицательный размер - nil")
    -- The map-fraction distance is always available instead.
    H.near(Geo.MapDistance(0, 0, 0.3, 0.4), 0.5, 1e-9, "доля карты считается всегда")
end

H.suite("Геометрия: компас")
do
    local env = H.load()
    local Geo = env.ns.Geo
    H.eq(Geo.CompassName(0), "на север", "0")
    H.eq(Geo.CompassName(pi / 4), "на северо-восток", "pi/4")
    H.eq(Geo.CompassName(pi / 2), "на восток", "pi/2")
    H.eq(Geo.CompassName(3 * pi / 4), "на юго-восток", "3pi/4")
    H.eq(Geo.CompassName(pi), "на юг", "pi")
    H.eq(Geo.CompassName(-3 * pi / 4), "на юго-запад", "-3pi/4")
    H.eq(Geo.CompassName(-pi / 2), "на запад", "-pi/2")
    H.eq(Geo.CompassName(-pi / 4), "на северо-запад", "-pi/4")
    -- Sector edges round to the nearest point, not off the end of the table.
    H.eq(Geo.CompassName(0.3), "на север", "чуть восточнее севера - всё ещё север")
    H.eq(Geo.CompassName(-0.3), "на север", "чуть западнее севера - всё ещё север")
    H.eq(Geo.CompassName(nil), nil, "nil - nil")
end

-- Geo.Solve: the four states -------------------------------------------

H.suite("Навигация: цель на той же карте, взгляд известен")
do
    local env = H.load()
    local Geo = env.ns.Geo
    local s = Geo.Solve(
        { mapID = 1434, x = 0.5, y = 0.5, facing = 0 },
        { mapID = 1434, x = 0.5, y = 0.2 },
        { width = 1000, height = 1000 })
    H.eq(s.ok, true, "решение получено")
    H.eq(s.reason, nil, "без оговорок")
    H.eq(s.sameMap, true, "та же карта")
    H.near(s.bearing, 0, 1e-9, "азимут на север")
    H.near(s.rotation, 0, 1e-9, "поворот стрелки есть")
    H.near(s.yards, 300, 1e-6, "300 ярдов")
    H.eq(s.compass, "на север", "компас заполнен")
    H.eq(s.arrived, nil, "ещё не на месте")
end

H.suite("Навигация: взгляд недоступен - стрелки нет, направление есть")
do
    local env = H.load()
    local Geo = env.ns.Geo
    local s = Geo.Solve(
        { mapID = 1434, x = 0.5, y = 0.5, facing = nil },
        { mapID = 1434, x = 0.8, y = 0.5 },
        { width = 1000, height = 1000 })
    H.eq(s.ok, true, "решение всё равно получено")
    H.eq(s.reason, "no-facing", "причина названа")
    H.eq(s.rotation, nil, "поворота нет")
    H.near(s.bearing, pi / 2, 1e-9, "но азимут посчитан")
    H.eq(s.compass, "на восток", "и компас заполнен")
    H.near(s.yards, 300, 1e-6, "и расстояние посчитано")
end

H.suite("Навигация: цель в другой зоне")
do
    local env = H.load()
    local Geo = env.ns.Geo
    local s = Geo.Solve(
        { mapID = 1434, x = 0.5, y = 0.5, facing = 0 },
        { mapID = 1411, x = 0.2, y = 0.9 },
        { width = 1000, height = 1000 })
    H.eq(s.ok, false, "решения нет")
    H.eq(s.reason, "other-map", "причина - другая карта")
    H.eq(s.sameMap, false, "карты разные")
    H.eq(s.bearing, nil, "азимут не считаем - между картами он бессмыслен")
    H.eq(s.rotation, nil, "и стрелку не крутим")
    H.eq(s.yards, nil, "и расстояние не придумываем")
end

H.suite("Навигация: нет координат у цели")
do
    local env = H.load()
    local Geo = env.ns.Geo
    local s = Geo.Solve(
        { mapID = 1434, x = 0.5, y = 0.5, facing = 0 },
        { mapID = 1434, x = nil, y = nil },
        { width = 1000, height = 1000 })
    H.eq(s.ok, false, "решения нет")
    H.eq(s.reason, "no-target", "причина - нет цели")

    local s2 = Geo.Solve(nil, { mapID = 1, x = 0.5, y = 0.5 })
    H.eq(s2.reason, "no-player", "не знаем, где игрок")

    local s3 = Geo.Solve({ mapID = 1, x = 0.5, y = 0.5 }, nil)
    H.eq(s3.reason, "no-target", "цели нет вообще")

    local s4 = Geo.Solve({}, {})
    H.eq(s4.reason, "no-player", "пустые таблицы не ломают")
end

H.suite("Навигация: прибытие")
do
    local env = H.load()
    local Geo = env.ns.Geo
    local s = Geo.Solve(
        { mapID = 1, x = 0.5, y = 0.5, facing = 0 },
        { mapID = 1, x = 0.5005, y = 0.5 },
        { width = 1000, height = 1000 })  -- 0.5 yards away
    H.eq(s.arrived, true, "на месте")
    H.eq(s.reason, "arrived", "причина - прибыли")
    H.eq(s.ok, true, "это нормальное состояние, не ошибка")

    -- Without a world size the arrival test falls back to map fractions.
    local s2 = Geo.Solve(
        { mapID = 1, x = 0.5, y = 0.5, facing = 0 },
        { mapID = 1, x = 0.5005, y = 0.5 }, nil)
    H.eq(s2.arrived, true, "без размера карты прибытие тоже определяется")
end

H.suite("Навигация: тексты расстояния")
do
    local env = H.load()
    local Geo = env.ns.Geo
    H.eq(Geo.DistanceText(0.4), "меньше метра", "совсем близко")
    H.eq(Geo.DistanceText(250), "250 м", "метры")
    H.eq(Geo.DistanceText(250.6), "251 м", "округление")
    H.eq(Geo.DistanceText(2500), "2.5 км", "километры")
    H.eq(Geo.DistanceText(nil), nil, "nil - nil")
    H.eq(Geo.RoughText(0.01), "совсем рядом", "грубая оценка близко")
    H.eq(Geo.RoughText(0.9), "очень далеко", "грубая оценка далеко")
    H.eq(Geo.RoughText(nil), nil, "nil - nil")
end

-- Places and routing ----------------------------------------------------

local function navEnv()
    local env = H.load()
    local ns = env.ns
    env.playerMap = { mapID = 1434, x = 0.50, y = 0.50, zone = "Тернистая долина" }
    env.facing = 0
    env.worldSizes[1434] = { width = 4000, height = 2600, name = "Тернистая долина" }
    env.npcUnit = { id = 1313, name = "Торговец Кварц" }
    env.merchantItems = {
        { itemID = 2589, name = "Льняная ткань", price = 100, stack = 5 },
        { itemID = 2320, name = "Грубая нить", price = 9, stack = 1 },
    }
    H.item(env, 2589, { name = "Льняная ткань", sellPrice = 5 })
    H.item(env, 2320, { name = "Грубая нить", sellPrice = 2 })
    H.rescan(env)
    return env
end

H.suite("Места: торговец запоминается с координатами")
do
    local env = navEnv()
    local ns = env.ns
    local learned, npcID, name = ns.Places:RecordMerchant()
    H.eq(learned, 2, "две позиции прочитаны")
    H.eq(npcID, 1313, "id торговца записан")
    H.eq(name, "Торговец Кварц", "имя записано")

    local place = ns.Places:Lookup(1313)
    H.ok(place ~= nil, "место найдено")
    H.eq(place.mapID, 1434, "карта записана")
    H.near(place.x, 0.50, 1e-9, "x записан")
    H.eq(place.routable, true, "место пригодно для стрелки")
    H.eq(place.zone, "Тернистая долина", "зона записана")

    local byItem = ns.Places:ForItem(2589)
    H.ok(byItem ~= nil, "торговец найден по предмету")
    H.eq(byItem.npcID, 1313, "это тот самый торговец")
    H.eq(ns.Places:ForItem(99999), nil, "по неизвестному предмету - ничего")

    -- Per-unit price, not per-stack.
    H.eq(ns.Config:VendorPrice(2589), 20, "цена за штуку (100 за 5)")
end

H.suite("Места: без координат NPC запоминается, но маршрута не даёт")
do
    local env = navEnv()
    local ns = env.ns
    -- Instances and some spots report no position at all.
    env.playerMap = nil
    local learned, npcID = ns.Places:RecordMerchant()
    H.eq(npcID, 1313, "торговец всё равно записан по имени")
    local place = ns.Places:Lookup(1313)
    H.ok(place ~= nil, "запись есть")
    H.eq(place.routable, false, "но маршрут по ней не построить")
    H.eq(place.mapID, nil, "карты нет")
    local hint = ns.Places:CardHint(place)
    H.ok(hint and hint:find("координат"), "карточка честно пишет, что координат нет")
end

H.suite("Места: тренер запоминается только при однозначной профессии")
do
    -- This test used to assert that a trainer opened by a player with two
    -- professions was filed under BOTH of them. That is what sent the arrow to
    -- the tailoring trainer when the player needed the enchanter: no API says
    -- which profession a trainer teaches, so with more than one candidate the
    -- NPC is remembered without a profession.
    local env = navEnv()
    local ns = env.ns
    H.profession(env, "Tailoring", 225, 225, {})
    H.rescan(env)
    env.npcUnit = { id = 5566, name = "Тренер портных" }
    local npcID, _, attributed = ns.Places:RecordTrainer({ "Tailoring", "Enchanting" })
    H.eq(npcID, 5566, "тренер записан")
    H.eq(attributed, nil, "но ни к одной профессии не привязан")
    H.eq(ns.Places:ForTrainer("Tailoring"), nil, "по портняжному - ничего")
    H.eq(ns.Places:ForTrainer("Enchanting"), nil, "по чарам тоже ничего")
    local any = ns.Places:AnyTrainer()
    H.ok(any ~= nil, "сам NPC найден как тренер без профессии")
    H.eq(any and any.npcID, 5566, "это он")
    H.eq(any and any.professionKnown, false, "и это честно помечено")

    -- One candidate profession: the attribution is unambiguous and kept.
    local env2 = navEnv()
    local ns2 = env2.ns
    H.profession(env2, "Tailoring", 225, 225, {})
    H.rescan(env2)
    env2.npcUnit = { id = 5567, name = "Тренер портных" }
    local id2, _, attr2 = ns2.Places:RecordTrainer({ "Tailoring" })
    H.eq(id2, 5567, "тренер записан")
    H.eq(attr2, "tailoring", "и привязан к единственной профессии")
    local place = ns2.Places:ForTrainer("Tailoring")
    H.ok(place ~= nil, "найден по названию профессии")
    H.eq(place and place.npcID, 5567, "это он")
    H.ok(ns2.Places:ForTrainer("tailoring") ~= nil, "регистр не важен")
    H.eq(ns2.Places:ForTrainer("Blacksmithing"), nil, "по чужой профессии - ничего")
end

H.suite("Навигация: своя стрелка - основной путь")
do
    local env = navEnv()
    local ns = env.ns
    ns.Places:RecordMerchant()
    local place = ns.Places:ForItem(2589)

    H.eq(ns.Config:Get().nav.provider, "own", "по умолчанию своя стрелка")
    H.eq(ns.Places:CanRoute(), true, "маршрут возможен без всяких аддонов")
    H.eq(#env.tomtomCalls, 0, "TomTom не трогаем")
end

H.suite("Навигация: TomTom только по выбору игрока")
do
    local env = navEnv()
    local ns = env.ns
    ns.Places:RecordMerchant()
    local place = ns.Places:ForItem(2589)

    env.tomtom = true
    ns.Config:Get().nav.provider = "tomtom"
    H.eq(ns.Api:NavProvider(), "tomtom", "выбран TomTom")

    local ok, reason = ns.Api:TomTomWaypoint(place.mapID, place.x, place.y, "тест")
    H.eq(ok, true, "точка отдана TomTom")
    H.eq(#env.tomtomCalls, 1, "вызов зафиксирован")
    H.eq(env.tomtomCalls[1].mapID, 1434, "карта передана")
    H.near(env.tomtomCalls[1].x, 0.50, 1e-9, "координата передана как доля, не процент")

    -- Percent input must be converted, not passed through.
    ns.Api:TomTomWaypoint(1434, 34.5, 76.8, "тест")
    H.near(env.tomtomCalls[2].x, 0.345, 1e-9, "проценты переведены в доли")

    -- TomTom chosen but absent: we say so rather than failing silently.
    env.tomtom = false
    local ok2, reason2 = ns.Api:TomTomWaypoint(1434, 0.5, 0.5)
    H.eq(ok2, false, "без TomTom отказ")
    H.eq(reason2, "no-tomtom", "с внятной причиной")
end

H.suite("Навигация: отключена в настройках")
do
    local env = navEnv()
    local ns = env.ns
    ns.Config:Get().nav.provider = "off"
    H.eq(ns.Api:NavProvider(), nil, "провайдера нет")
    H.eq(ns.Places:CanRoute(), false, "маршрут невозможен")
    ns.Places:RecordMerchant()
    local place = ns.Places:ForItem(2589)
    -- В СТРОКЕ СОВЕТА - ТОЛЬКО КООРДИНАТЫ.
    --
    -- Здесь к ним приписывалось «(навигация выключена в настройках)», и именно
    -- эта приписка отжимала координаты за край окна: игрок прислал скриншот с
    -- «Торговец: Mister Graphed, Лесоречье, 78.2 5…». Дорога в настройки уехала
    -- под курсор, координаты остались целыми.
    local hint = ns.Places:CardHint(place)
    H.ok(hint and hint:find("50.0"), "в строке совета координаты: " .. tostring(hint))
    H.eq(hint and hint:find("настройк") ~= nil, false,
        "и ничего про настройки: " .. tostring(hint))
    local tip = ns.Places:CardTip(place)
    H.ok(tip and tip:find("выключена"), "под курсором объяснено, почему кнопки нет: "
        .. tostring(tip))
    -- Навигация включена - объяснять нечего.
    ns.Config:Get().nav.provider = "arrow"
    H.eq(ns.Places:CardTip(place), nil, "с включённой навигацией подсказки нет")
end

H.suite("Навигация: координаты в тексте всегда доступны")
do
    local env = navEnv()
    local ns = env.ns
    ns.Places:RecordMerchant()
    local place = ns.Places:ForItem(2589)
    local text = ns.Places:Describe(place)
    H.ok(text ~= nil, "описание есть: " .. tostring(text))
    H.ok(text:find("Торговец"), "содержит имя")
    H.ok(text:find("Тернистая"), "содержит зону")
    H.ok(text:find("50.0"), "содержит координаты в процентах")
end

H.suite("Навигация: сводка состояния")
do
    local env = navEnv()
    local ns = env.ns
    ns.Places:RecordMerchant()
    local s = ns.Places:Summary()
    H.eq(s.npcs, 1, "один NPC записан")
    H.eq(s.routable, 1, "с координатами")
    H.eq(s.items, 2, "два предмета привязаны к торговцу")
    H.eq(s.hasFacing, true, "взгляд доступен")
    H.eq(s.tomtom, false, "TomTom нет")

    env.facing = nil
    H.eq(ns.Places:Summary().hasFacing, false, "без взгляда это видно в сводке")
end

H.suite("Навигация: карточка покупки получает место")
do
    local env = navEnv()
    local ns = env.ns
    ns.Places:RecordMerchant()

    H.item(env, 101, { name = "Изделие", sellPrice = 300 })
    env.prices[101] = 3000
    env.prices[2589] = 50
    H.profession(env, "Tailoring", 180, 225, {
        H.recipe { id = 1, name = "Изделие", output = 101,
                   reagents = { { itemID = 2589, qty = 10 } }, diff = "optimal",
                   category = "Капюшоны", categoryID = 1 },
    })
    env.money = 25081
    local cards = H.build(env)

    local buyCard
    for _, card in ipairs(cards) do
        if card.kind == ns.KIND.BUY and card.itemID == 2589 then buyCard = card end
    end
    H.ok(buyCard ~= nil, "карточка покупки построена")
    if buyCard then
        H.ok(buyCard.place ~= nil, "к ней привязано место")
        H.eq(buyCard.place.npcID, 1313, "это записанный торговец")
        H.ok(buyCard.need:find("Торговец"), "строка «чего не хватает» называет торговца")
    end
end

H.suite("Навигация: карточка без места не падает и не врёт")
do
    local env = navEnv()
    local ns = env.ns
    -- Никаких записанных торговцев.
    H.item(env, 101, { name = "Изделие", sellPrice = 300 })
    env.prices[101] = 3000
    env.prices[2589] = 50
    H.profession(env, "Tailoring", 180, 225, {
        H.recipe { id = 1, name = "Изделие", output = 101,
                   reagents = { { itemID = 2589, qty = 10 } }, diff = "optimal",
                   category = "Капюшоны", categoryID = 1 },
    })
    env.money = 25081
    local cards = H.build(env)
    for _, card in ipairs(cards) do
        if card.kind == ns.KIND.BUY then
            H.eq(card.place, nil, "места нет - и поле пустое, а не выдуманное")
            H.ok(not card.need:find("Торговец"), "и в тексте торговец не упомянут")
        end
    end
    H.ok(true, "список построен без мест")
end

H.suite("Навигация: CardHint на все случаи")
do
    local env = navEnv()
    local ns = env.ns
    H.eq(ns.Places:CardHint(nil), nil, "nil - nil")
    H.eq(ns.Places:CardHint({}), nil, "пустая таблица - nil")
    local full = { name = "Кварц", zone = "Тернистая долина",
                   x = 0.34, y = 0.76, routable = true }
    local hint = ns.Places:CardHint(full)
    H.ok(hint and hint:find("34.0"), "с координатами: " .. tostring(hint))
    local noCoords = { name = "Кварц", zone = "Тернистая долина", routable = false }
    local hint2 = ns.Places:CardHint(noCoords)
    H.ok(hint2 and hint2:find("Кварц"), "без координат называет NPC")
end

end
