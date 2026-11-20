-- ForeverPilot / Logic/Notifier.lua
--
-- ДВА ПОВОДА СКАЗАТЬ ЧТО-ТО ПЕРВЫМ, И НИ ОДНОГО ТИХОГО ДЕЙСТВИЯ.
--
-- Про сделки на аукционе говорит Logic/AuctionMoment.lua. Здесь - остальное:
--
--   * ПОТОЛОК НАВЫКА ПОДНЯЛСЯ. Для этого персонажа это главная новость, какая
--     вообще может быть: четыре профессии стоят на 225/225, крафт навыка не
--     даёт, и целая ветка советов молчит. Потолок в Forever поднимается сам по
--     ходу игры - и ровно в этот момент ветка оживает. Заметить это самому
--     игроку почти невозможно: число 225 меняется на 226 в окне профессии,
--     которое он не открывает.
--
--   * ЦЕНЫ СТАРШЕ СУТОК. Auctionator знает только то, что игрок отсканировал
--     сам, обойти это нельзя - значит надо честно сказать, что денежная часть
--     советов держится на старых числах, и предложить зайти на аукцион.
--
-- ПРАВИЛА, ЧТОБЫ ЭТО НЕ СТАЛО НАЗОЙЛИВЫМ:
--   * про один и тот же подъём потолка говорится ровно один раз;
--   * про старые цены - не чаще раза в сессию и только когда они действительно
--     старые;
--   * оба выключаются отдельно в настройках;
--   * выключено СООБЩЕНИЕ, а не работа: карточки, пересчёт и слепок цен идут
--     при любом значении. Аддон уже один раз молча съел все советы, и тихое
--     поведение здесь - то, чего быть не должно.
local ADDON, ns = ...

local U = ns.Util
local Api = ns.Api

local N = {}
ns.Notifier = N

N.told = {}          -- ключ новости -> true, чтобы не повторяться
N.lastStaleAt = nil

function N:Bind()
    if N.bound then return end
    N.bound = true
    -- Сообщение клиента о повышении навыка: самый ранний момент, когда можно
    -- проверить потолок.
    ns.Events:On("skill", function() N:CheckSkillCap("сообщение клиента о навыке") end)
    -- И на каждом пересчёте: событие могло не прийти (клиент пишет в чат не
    -- всегда), а снимок персонажа всё равно обновился.
    ns.Events:On("recompute", function(reasons)
        if reasons and (reasons.skillcap or reasons.character or reasons.forced) then
            N:CheckSkillCap("пересчёт")
        end
        N:CheckStalePrices()
    end)
end

function N:Enabled(key)
    local cfg = ns.Config and ns.Config:Get()
    local n = cfg and cfg.notify
    if not n then return true end
    return n[key] ~= false
end

-- Потолок навыка -------------------------------------------------------

-- Что мы помним о потолках, чтобы заметить движение. Поле в SavedVariables, а
-- не в памяти: подъём между сессиями тоже подъём, и именно его игрок пропускает.
--
-- ПО ПЕРСОНАЖУ, А НЕ НА АККАУНТ. Таблица была одна и заведена по имени
-- профессии. У мага кулинария 225, у чернокнижника она качается с единицы - и в
-- живом файле игрока там лежало ровно это: Кулинария = 225 от мага. Поэтому
-- подъём потолка кулинарии у чернокнижника (75 -> 150) сравнивался с чужими
-- 225, попадал в ветку «клиент ответил хуже, чем раньше» и пропадал молча. То
-- есть главная новость, ради которой модуль существует, не доходила до игрока
-- именно на том персонаже, который её производил.
--
-- Это тот же класс ошибки, что был с рецептами по GUID: одно имя, два
-- персонажа, одна ячейка. Хранилище теперь в Logic/Roster.lua, рядом с
-- остальным, что аддон помнит про персонажа.
function N:Remembered()
    local snap = ns.CharacterScanner and ns.CharacterScanner:Get() or nil
    local who = snap and (snap.fullName or snap.name) or nil
    -- Нет снимка или нет имени - писать некуда. Пустая таблица здесь значит
    -- «ничего не помню», то есть каждая профессия будет «первой встречей» и
    -- ничего не объявится; выдумывать общее хранилище на этот случай нельзя -
    -- именно оно и было ошибкой.
    if not (who and ns.Roster) then return {} end
    return ns.Roster:SkillCaps(who)
end

-- Проверить и, если потолок вырос, сказать. Возвращает число сказанного.
--
-- СРАВНИВАЕТСЯ С ЗАПОМНЕННЫМ, А НЕ С ИСТОРИЕЙ MastercraftDB: история пишется
-- раз в сутки и про сегодняшний подъём ещё не знает - именно поэтому в живом
-- файле chars показывал рыбалку 225, а свежая запись истории 155.
function N:CheckSkillCap(why)
    local snap = ns.CharacterScanner and ns.CharacterScanner:Get() or nil
    if not snap then return 0 end
    local remembered = N:Remembered()
    local said = 0
    -- КТО ИМЕННО. Входит в ключ «уже сказано»: в игре за сессию персонаж один,
    -- но хранилище теперь по персонажу, и ключ без имени склеил бы подъём
    -- кулинарии у мага с подъёмом кулинарии у чернокнижника - ту же ошибку, что
    -- исправлена в N:Remembered, только в памяти вместо файла.
    local who = snap.fullName or snap.name or "?"

    for _, prof in ipairs(snap.professions or {}) do
        local name = prof.name
        local max = tonumber(prof.max)
        -- Ноль и nil - это «клиент не сказал», а не «потолка нет». Принимать их
        -- за потолок значило бы объявлять падение потолка на каждом входе.
        if name and max and max > 0 then
            local prev = tonumber(remembered[name])
            if prev and max > prev then
                -- ПОДНЯЛСЯ. Записываем до сообщения: если сообщение выключено,
                -- повторять его при включении уже не нужно - новость устарела.
                local key = tostring(who) .. "/" .. tostring(name)
                    .. ":" .. prev .. "->" .. max
                remembered[name] = max
                if not N.told[key] then
                    N.told[key] = true
                    if N:Enabled("skillCap") then
                        local room = max - (tonumber(prof.skill) or max)
                        -- Имя - для игрока (U.profLabel): в раннем состоянии
                        -- профессии приходят из чужого кеша по-английски, а это
                        -- строка в чат.
                        Api:Print("потолок «" .. tostring(U.profLabel(name)) .. "» поднялся: "
                            .. prev .. " -> " .. max
                            .. ((room > 0)
                                and (". Снова можно качать — есть " .. room .. " "
                                     .. U.plural(room, "пункт", "пункта", "пунктов") .. ".")
                                or ". Советы по навыку снова работают."))
                        said = said + 1
                    end
                    if ns.Diag then
                        ns.Diag:Log("потолок навыка поднялся", {
                            profession = name, from = prev, to = max,
                            why = why, told = N:Enabled("skillCap"),
                        })
                        ns.Diag:Count("notify.skillCapUp")
                    end
                    -- Горизонт пересобрать: впереди появился целый ранг.
                    if ns.Foresight then ns.Foresight.lastSkillKey = nil end
                end
            elseif prev == nil then
                -- Первая встреча: запомнить, но ничего не объявлять. Иначе
                -- первый вход в игру выдал бы «потолок поднялся» на все
                -- профессии сразу.
                remembered[name] = max
            elseif max < prev then
                -- Потолок не падает. Если число упало, то это клиент ответил
                -- хуже, чем раньше, а не игра забрала навык: запомненное не
                -- трогаем и в чат не лезем.
                if ns.Diag then ns.Diag:Count("notify.skillCapWentDown") end
            end
        end
    end
    return said
end

-- Старые цены ----------------------------------------------------------

-- Раз в сессию и только по делу. Возвращает число сказанного.
function N:CheckStalePrices()
    if not N:Enabled("stalePrices") then return 0 end
    if N.lastStaleAt then return 0 end
    if not ns.PriceProvider then return 0 end
    local fresh = ns.PriceProvider.Freshness and ns.PriceProvider:Freshness() or nil
    if not (fresh and fresh.stale) then return 0 end
    -- Говорить про старые цены, когда их вообще нет, бессмысленно: про
    -- отсутствие Auctionator есть своя карточка.
    if (fresh.priced or 0) == 0 then return 0 end

    N.lastStaleAt = Api:ServerTime()
    Api:Print(fresh.text .. " Зайдите на аукцион — я пересчитаю всё денежное"
        .. " на свежих ценах сам.")
    if ns.Diag then ns.Diag:Count("notify.stalePrices") end
    return 1
end

-- Для настроек и тестов: что модуль уже сказал за эту сессию.
function N:Summary()
    local n = 0
    for _ in pairs(N.told) do n = n + 1 end
    return {
        skillCapNews = n,
        staleToldAt = N.lastStaleAt,
        skillCapEnabled = N:Enabled("skillCap"),
        stalePricesEnabled = N:Enabled("stalePrices"),
        auctionDealsEnabled = N:Enabled("auctionDeals"),
    }
end

return N
