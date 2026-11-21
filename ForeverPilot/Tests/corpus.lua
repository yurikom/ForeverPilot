-- ForeverPilot / Tests/corpus.lua
--
-- ВСЁ, ЧТО АДДОН ГОВОРИТ ИГРОКУ, - ОДНИМ СОБРАНИЕМ И С АДРЕСОМ КАЖДОЙ СТРОКИ.
--
-- Не набор тестов, а то, по чему наборы ходят: Tests/test_sense.lua проверяет
-- собрание на осмысленность. Собрание строится из МНОГИХ СОСТОЯНИЙ мира, потому
-- что одного мало: строка, которая рисуется только при открытом аукционе или
-- только у пустого списка, в «обычном» состоянии не существует вовсе, и
-- проверка по нему её не видит никогда. Так уже было - трижды.
--
-- Каждая строка несёт адрес: канал (заголовок совета, «почему», «нужно»,
-- подпись кнопки, экран, подсказка, чат, сводка диагностики) и место
-- (состояние / вкладка / совет). Проверке, которая нашла чушь, есть что
-- напечатать, кроме самой чуши.
--
-- Отдельно собираются НАЖАТИЯ: каждая кнопка каждого совета нажимается, и
-- записывается, что аддон на это ответил и что изменилось. По ним проверяется
-- главное правило: кнопка отвечает на тот вопрос, который на ней написан.
local C = {}

-- Состояния мира. `prepare` получает мир уже с обычным наполнением.
C.STATES = {
    { name = "обычный", prepare = function() end },
    { name = "всё скрыто", prepare = function(env, H)
        for _, card in ipairs(env.ns.ActionEngine.cards or {}) do
            if not card.blocking then
                env.ns.Config:Dismiss(card.key, env.ns.Api:ServerTime(), 86400)
            end
        end
        H.build(env)
    end },
    { name = "рецепты не прочитаны", prepare = function(env, H)
        env.ns.RecipeBook.byProfession = {}
        env.ns.RecipeBook:Reindex()
        H.build(env)
    end },
    { name = "без Auctionator", prepare = function(env, H)
        env.auctionator = false
        H.build(env)
    end },
    { name = "аукцион открыт, список можно передать", prepare = function(env, H)
        env.auctionator = true
        env.G.Auctionator = { API = { v1 = { MultiSearchAdvanced = function() end } } }
        local ah = env.world.newFrame("Frame", "AuctionHouseFrame")
        ah:Show()
        env.G.AuctionHouseFrame = ah
        env.G.AuctionatorTabs_Shopping =
            env.world.newFrame("Button", "AuctionatorTabs_Shopping")
        H.build(env)
    end },
    { name = "банк не виден", prepare = function(env, H)
        env.bank = nil
        H.build(env)
    end },
    { name = "окно профессий ещё не открывалось", prepare = function(env)
        env.professionsUI = false
    end },
    { name = "клиент не говорит, открывалось ли окно профессий", prepare = function(env)
        env.professionsUI = "unknown"
    end },
    { name = "панель свёрнута", prepare = function(env)
        env.ns.Config:Get().panel.collapsed = true
    end },
    { name = "фильтр, под который ничего не подходит", prepare = function(env)
        local nsr = env.ns
        nsr.Config:SetChip(nsr.CHIP.ENCHANT)
        local kept = {}
        for _, card in ipairs(nsr.ActionEngine.cards or {}) do
            if card.kind ~= nsr.KIND.ENCHANT and card.kind ~= nsr.KIND.SETUP then
                kept[#kept + 1] = card
            end
        end
        nsr.ActionEngine.cards = kept
    end },
    -- НАВИГАЦИЯ ВЫКЛЮЧЕНА ИГРОКОМ, А ТОРГОВЕЦ ЗАПИСАН.
    --
    -- Кнопки «Показать путь» в этом состоянии нет, и в строке совета остаются
    -- одни координаты. Раньше к ним приписывалось «(навигация выключена в
    -- настройках)» - и за край окна уходили как раз координаты, а не приписка
    -- (игрок прислал «Торговец: Mister Graphed, Лесоречье, 78.2 5…»). Состояния
    -- с выключенной навигацией в собрании не было вовсе, поэтому этой приписки
    -- не видело ни одно правило.
    { name = "навигация выключена игроком", prepare = function(env, H)
        local nsr = env.ns
        nsr.Places:RecordMerchant()
        nsr.Config:Get().nav.provider = "off"
        H.build(env)
    end },
    { name = "денег нет", prepare = function(env, H)
        env.money = 0
        H.build(env)
    end },
    -- ПОРОГ МЕЛКОЙ ДЕНЕЖНОЙ ВЫГОДЫ В ДЕЙСТВИИ.
    --
    -- В остальных состояниях порог снят: деньги в фикстурах игрушечные, и
    -- рабочий порог срезал бы в них механику, а не воду (см. H.setMoneyFloor в
    -- Tests/harness.lua). Из-за этого строка «порог убрал N советов» на экране
    -- не появлялась вовсе - то есть ни одно правило осмысленности её никогда не
    -- читало. Здесь порог включён на 10 серебра - нижнюю полосу, которую назвал
    -- сам игрок, - и часть денежных советов уходит: в собрание попадают и
    -- строка над списком, и причина ветки.
    { name = "порог мелкой выгоды отсекает часть советов", prepare = function(env, H)
        local nsr = env.ns
        nsr.Config:SetMoneyFloorMode(nsr.MONEY_FLOOR_MODE.FIXED)
        nsr.Config:SetMoneyFloorOwn(1000)
        H.build(env)
    end },
    -- ЧАСТЬ СОВЕТОВ НЕ ПОКАЗАНА СРАЗУ ПО ТРЁМ ПРИЧИНАМ.
    --
    -- Над списком об этом стоит ОДНА строка (UI/TabNow.lua, Tab:NoticeShort), и
    -- самой длинной она бывает ровно здесь: фильтр, порог и профиль разом. В
    -- остальных состояниях её либо нет вовсе, либо причина одна - и правило «над
    -- списком не больше одной короткой строки» проверялось бы на пустоте. А
    -- простыня, из-за которой это правило появилось, выросла именно из трёх
    -- причин, сказанных тремя абзацами.
    { name = "часть советов не показана по трём причинам", prepare = function(env, H)
        local nsr = env.ns
        -- Фильтр, под который часть списка подходит: под «Золото» в этом мире
        -- не подходит ничего, и тогда вместо строки над списком показывается
        -- пустое состояние - то есть опять не то, что проверяем.
        nsr.Config:SetChip(nsr.CHIP.CRAFT)
        nsr.Config:SetMoneyFloorMode(nsr.MONEY_FLOOR_MODE.FIXED)
        nsr.Config:SetMoneyFloorOwn(1000)
        nsr.PROFILE_EXCLUDE[nsr.Config:Profile()] = { BUY = true }
        H.build(env)
    end },
    { name = "цен нет ни на что", prepare = function(env, H)
        env.prices = {}
        env.vendorPrices = {}
        H.build(env)
    end },
    -- ВЕНДОРНЫЙ ПОТОЛОК, ОБЕ ЕГО СТОРОНЫ РАЗОМ.
    --
    -- Ни в одном из остальных миров нет цены торговца и цены аукциона на один
    -- и тот же предмет одновременно, поэтому состояния «материал дешевле на
    -- полке» не существовало вовсе - и ни одно правило осмысленности новых фраз
    -- не читало. А у игрока это 27 реагентов его собственных рецептов.
    --
    -- Числа настоящие, из его кеша Auctionator: Heavy Silken Thread (8343) -
    -- торговец 18с против аукциона 18с 80м. Вторая сторона тут же: готовый
    -- кушак торговец продаёт дешевле, чем за него дают на аукционе, и карточка
    -- «на продажу» обязана про это сказать.
    { name = "материал дешевле у торговца, чем на аукционе", prepare = function(env, H)
        local nsr = env.ns
        H.item(env, 8343, { name = "Крепкая шелковая нить", sellPrice = 450 })
        H.item(env, 8344, { name = "Шелковый кушак", sellPrice = 400 })
        env.prices[8343] = 1880
        env.vendorPrices[8343] = 1800
        env.prices[8344] = 9000
        env.vendorPrices[8344] = 4000
        -- Рецепты кладутся в тот же справочник, а не новой профессией: второй
        -- раз объявить «Tailoring» значило бы дать персонажу две одинаковые
        -- профессии, то есть проверять не тот мир.
        nsr.RecipeBook:Store("Tailoring", {
            H.recipe { id = 1, name = "Новый капюшон", output = 101, outputQty = 1,
                       reagents = { { itemID = 2589, qty = 6 } }, diff = "optimal",
                       category = "Капюшоны", categoryID = 1 },
            H.recipe { id = 3, name = "Шелковый кушак", output = 8344, outputQty = 1,
                       reagents = { { itemID = 8343, qty = 4 } }, diff = "optimal",
                       category = "Пояса", categoryID = 2 },
        }, "own", nsr.CONF.EXACT, H.serverTime)
        nsr.RecipeBook:Reindex()
        H.itemsChanged(env)
        H.rescan(env)
        H.build(env)
    end },
    -- ОДИН И ТОТ ЖЕ ПРЕДМЕТ В ДВУХ ЯЧЕЙКАХ СУМКИ.
    --
    -- Так выглядит хлам у игрока: «Отрубленный коготь» лежал двумя кучками, и
    -- перечисление называло его дважды подряд - «Отрубленный коготь,
    -- Отрубленный коготь и ещё 8». В выдуманных мирах каждый предмет лежал
    -- ровно в одной ячейке (см. H.installFakes, Api:BagCounts), поэтому такого
    -- состояния не существовало вовсе и правило про повтор в перечислении
    -- читать было нечего.
    { name = "один предмет лежит в двух ячейках сумки", prepare = function(env, H)
        env.bagStacks = env.bagStacks or {}
        env.bagStacks[9000] = { 5, 3 }   -- та же «Рваная шкура», двумя кучками
        H.rescan(env)
        H.build(env)
    end },
    { name = "сумки и банк пусты", prepare = function(env, H)
        env.bags = {}
        env.bank = {}
        H.build(env)
    end },
    { name = "навык неизвестен", prepare = function(env, H)
        for _, prof in ipairs(env.professions or {}) do
            prof.skill, prof.max, prof.maxKnown = 0, 0, false
        end
        H.build(env)
    end },
    -- ПРОФЕССИИ, КОТОРЫХ НЕТ В СПРАВОЧНИКЕ, - И ЭТО НЕ ВЫДУМАННЫЙ МИР.
    --
    -- Ровно так выглядит второй персонаж игрока: алхимия, инженерное дело и
    -- кулинария, а справочник (Data/ForeverSource.lua) собран по портняжному
    -- делу и наложению чар. Все остальные состояния здесь - про портняжника,
    -- то есть про того единственного персонажа, на котором аддон смотрели, и
    -- поэтому целый класс находок был невидим: в этом состоянии сверка
    -- справочника с игрой не состоится, и то, что она при этом СКАЖЕТ, попадает
    -- в собрание текстов и проверяется всеми правилами - включая правило про
    -- английские имена профессий, с которого всё и началось.
    --
    -- Имена профессий здесь РУССКИЕ: именно так их отдаёт клиент ruRU, под
    -- которым живёт игрок (Api:Locale() в стенде тоже "ruRU").
    { name = "профессии, которых нет в справочнике", prepare = function(env, H)
        local nsr = env.ns
        env.professions = {}
        nsr.RecipeBook.byProfession = {}
        H.profession(env, "Алхимия", 150, 150, {
            H.recipe { id = 2330, name = "Слабое исцеляющее зелье", output = 118,
                       outputQty = 1, reagents = { { itemID = 2447, qty = 1 } },
                       diff = "optimal", category = "Зелья", categoryID = 20 },
        })
        H.profession(env, "Инженерное дело", 150, 150, {
            H.recipe { id = 3918, name = "Грубый порох", output = 4357,
                       outputQty = 1, reagents = { { itemID = 2835, qty = 1 } },
                       diff = "trivial", category = "Детали", categoryID = 21 },
        })
        H.profession(env, "Кулинария", 150, 150, {})
        nsr.RecipeBook:Reindex()
        H.build(env)
        -- Сверку зовём сами: в стенде подписка на пересчёт снята (см.
        -- Tests/harness.lua), иначе она шла бы в каждом чужом наборе.
        if nsr.SourceCheck then nsr.SourceCheck:RunStatic() end
        H.build(env)
    end },
    -- ОБЛИК ВЕЩИ, ОБА ЕГО СОСТОЯНИЯ -----------------------------------------
    --
    -- Ни в одном из остальных миров нет вещи необычного качества, с которой
    -- советуют расстаться: все фикстуры белые, а белое учится по подбору и
    -- облика не теряет. Значит ни одной фразы про облик собрание не видело
    -- вовсе - то есть ни одно правило осмысленности её не читало, а фраза эта
    -- стоит ПЕРВОЙ в строке самых опасных советов аддона.
    --
    -- Состояний два, потому что ответов тоже два и говорят они разное:
    -- «облик не собран» (утверждение) и «не знаю» (клиент не ответил - ровно
    -- так ведёт себя любой клиент, где этих функций нет).
    --
    -- Предмет и его числа - из мира распыла: зелёный плащ, который персонаж
    -- умеет и сделать, и распылить. Ответ про облик ПОДСТАВЛЕН явно; настоящего
    -- ответа офлайн не существует.
    { name = "облик вещи не собран, а её советуют продать", prepare = function(env, H)
        local nsr = env.ns
        H.item(env, 6001, { name = "Зелёный плащик", equipLoc = "INVTYPE_CLOAK",
            reqLevel = 20, classID = 4, subclassID = 1, quality = 2,
            itemLevel = 25, sellPrice = 500, bindType = 2 })
        env.prices[6001] = 9000
        env.bags[6001] = 1
        env.bagBound[6001] = false
        nsr.RecipeBook:Store("Tailoring", {
            H.recipe { id = 6102, name = "Зелёный плащик", output = 6001,
                       outputQty = 1, reagents = { { itemID = 2589, qty = 4 } },
                       diff = "optimal", category = "Плащи", categoryID = 3 },
        }, "own", nsr.CONF.EXACT, H.serverTime)
        nsr.RecipeBook:Reindex()
        H.setAppearances(env, { rule = true, collected = { [6001] = false } })
        H.itemsChanged(env)
        H.rescan(env)
        H.build(env)
    end },
    { name = "про облик вещи клиент не ответил", prepare = function(env, H)
        local nsr = env.ns
        H.item(env, 6001, { name = "Зелёный плащик", equipLoc = "INVTYPE_CLOAK",
            reqLevel = 20, classID = 4, subclassID = 1, quality = 2,
            itemLevel = 25, sellPrice = 500, bindType = 2 })
        env.prices[6001] = 9000
        env.bags[6001] = 1
        env.bagBound[6001] = false
        nsr.RecipeBook:Store("Tailoring", {
            H.recipe { id = 6102, name = "Зелёный плащик", output = 6001,
                       outputQty = 1, reagents = { { itemID = 2589, qty = 4 } },
                       diff = "optimal", category = "Плащи", categoryID = 3 },
        }, "own", nsr.CONF.EXACT, H.serverTime)
        nsr.RecipeBook:Reindex()
        -- Шва нет - значит нет и ответа. Так выглядит клиент без этих функций.
        H.setAppearances(env, nil)
        H.itemsChanged(env)
        H.rescan(env)
        H.build(env)
    end },
    -- ЛАГЕРЬ У КОСТРА: БЕЗ ЭТОГО СОСТОЯНИЯ ЕГО ТЕКСТОВ НЕ ЧИТАЕТ НИ ОДНО
    -- ПРАВИЛО.
    --
    -- Ветка лагеря молчит в «обычном» мире, и молчит правильно: предметы лагеря
    -- она называет только тогда, когда их имя известно (клиент или Codex), а в
    -- фикстурном мире ни того, ни другого нет. То есть все её фразы - «порог
    -- спорный», «рецепт не выучен, его даёт чертёж», «мест у костра станет 5
    -- вместо 3», «что в лагере уже стоит, игра мне не говорит» - в собрании
    -- текстов не существовали бы вовсе. Так уже было трижды с другими ветками.
    --
    -- Мир собран из НАСТОЯЩИХ чисел игрока: маг с рыбалкой и кулинарией 225,
    -- выученный аквариум, невыученный костёр подмастерья с чертежом на
    -- аукционе, и алхимия на втором персонаже. Поэтому здесь появляются все
    -- четыре вида камповых карточек разом - «сделать», «костёр», «купить
    -- чертёж» и «сделает другой персонаж».
    { name = "лагерь у костра: костёр, чертёж и второй персонаж",
      prepare = function(env, H)
        local nsr = env.ns
        H.item(env, 279967, { name = "Аквариум", sellPrice = 32 })
        H.item(env, 279981, { name = "Обычный костер", sellPrice = 13 })
        H.item(env, 279961, { name = "Костер подмастерья", sellPrice = 90 })
        H.item(env, 273087, { name = "Чертеж: костер подмастерья", sellPrice = 3000 })
        H.item(env, 279956, { name = "Колодец маны", sellPrice = 39 })
        H.item(env, 6291, { name = "Сырая блестящая рыбка", sellPrice = 18 })
        H.item(env, 3371, { name = "Пустая колба", sellPrice = 1 })
        H.item(env, 4470, { name = "Простая древесина", sellPrice = 9 })
        H.item(env, 11291, { name = "Звездная древесина", sellPrice = 100 })
        H.item(env, 2447, { name = "Мироцвет", sellPrice = 40 })
        env.prices[279967] = 160
        env.prices[273087] = 157095
        env.prices[279956] = 197
        env.prices[6291] = 90
        env.prices[3371] = 5
        env.prices[4470] = 39
        env.prices[11291] = 4150
        env.prices[2447] = 179
        env.vendorPrices[3371] = 4
        env.vendorPrices[4470] = 38
        env.bags[4470] = 3
        nsr.RecipeBook:Store("Рыбная ловля", {
            H.recipe { id = 1229745, name = "Аквариум", output = 279967,
                       learned = true, category = "Лагерь", categoryID = 40,
                       reagents = { { itemID = 6291, qty = 1 },
                                    { itemID = 3371, qty = 1 } } },
        }, "own", nsr.CONF.EXACT, H.serverTime)
        nsr.RecipeBook:Store("Кулинария", {
            H.recipe { id = 1229737, name = "Обычный костер", output = 279981,
                       learned = true, category = "Лагерь", categoryID = 40,
                       reagents = { { itemID = 4470, qty = 1 } } },
            H.recipe { id = 1283400, name = "Костер подмастерья", output = 279961,
                       learned = false, category = "Лагерь", categoryID = 40,
                       reagents = { { itemID = 11291, qty = 1 } } },
        }, "own", nsr.CONF.EXACT, H.serverTime)
        nsr.RecipeBook:Reindex()
        env.professions[#env.professions + 1] = {
            name = "Рыбная ловля", skill = 225, max = 225, skillTrusted = true,
        }
        env.professions[#env.professions + 1] = {
            name = "Кулинария", skill = 225, max = 225, skillTrusted = true,
        }
        -- Второй персонаж - из чужого кеша, как его видит аддон, пока играют
        -- этим: имя с фамилией, уровень, класс и профессии.
        env.foreignDB = env.foreignDB or {}
        env.foreignDB.chars = {
            ["Player-6946-01187A42"] = {
                name = "Гендольф", surname = "Белыйй", level = 20,
                class = "Чернокнижник", classFile = "WARLOCK",
                realm = H.realmName, faction = "Horde",
                professions = {
                    { name = "Alchemy", skill = 225, max = 225 },
                    { name = "Engineering", skill = 225, max = 225 },
                },
            },
        }
        H.itemsChanged(env)
        H.rescan(env)
        H.build(env)
    end },
    { name = "в своём списке покупок есть позиции", prepare = function(env, H)
        env.ns.ShoppingList:Pin(2589, 12)
        env.ns.ShoppingList:Pin(11137, 3)
        H.build(env)
    end },
    -- ЗАКРЕПЛЕНИЕ, КОТОРОЕ НИ ОДНОМУ СОВЕТУ НЕ НУЖНО.
    --
    -- В состоянии выше закреплены лён и магическая пыль - и то и другое нужно
    -- рецептам этого мира. Поэтому состояния «игрок закрепил то, что никому не
    -- нужно» в собрании не существовало вовсе, и ни одно правило осмысленности
    -- его не читало. А у игрока оно было, десятой строкой списка: «Купить:
    -- Небесно-голубая краска x6» с первой фразой «Ни одному совету это сейчас не
    -- нужно» - совет, который сам сообщает, что он не нужен.
    --
    -- Номер предмета взят настоящий, тот самый.
    { name = "закреплено то, что ни одному совету не нужно", prepare = function(env, H)
        H.item(env, 249409, { name = "Небесно-голубая краска", sellPrice = 300,
                              stackCount = 10 })
        env.prices[249409] = 7247
        H.rescan(env)
        env.ns.ShoppingList:Pin(249409, 6)
        H.build(env)
    end },
    { name = "вопрос «очистить список?» задан", prepare = function(env, H)
        env.ns.ShoppingList:Pin(2589, 12)
        H.build(env)
        env.ns.ShoppingList:RequestClear()
    end },
    -- Клиент, в котором части функций нет, а часть запросов молчит. Только в
    -- этом состоянии раздел настроек «что игра мне сообщает», команда /fp api и
    -- ответ на /fp diag показывают строки про недостающее - а именно они раньше
    -- состояли из имён функций игры.
    { name = "игра не даёт части сведений", prepare = function(env, H)
        local nsr = env.ns
        -- Настоящий отчёт вместо пустого списка стенда - с подменённой на время
        -- вызова таблицей «что нашлось»: третья тема отсутствует целиком,
        -- в четвёртой нет одной функции, остальные на месте.
        local realReport = env.real and env.real.Report
        if realReport then
            nsr.Api.Report = function(self)
                local saved = self.has
                local fake = {}
                self.has = setmetatable({}, { __index = function() return true end })
                local groups = realReport(self)
                for i, g in ipairs(groups) do
                    for j, key in ipairs(g.ok) do
                        fake[key] = not (i == 3 or (i == 4 and j == 2))
                    end
                end
                self.has = fake
                local out = realReport(self)
                self.has = saved
                return out
            end
        end
        H.build(env)
        local s = nsr.Diag:Init()
        s.detect["C_Item.GetItemStats"] = false
        s.detect["C_TooltipInfo.GetItemByID"] = false
        s.calls["C_Container.GetContainerItemInfo"] =
            { tries = 3, gotData = 0, empty = 3, failed = 0 }
        s.modules["gearUpgrades"] = s.modules["gearUpgrades"] or { ["in"] = 0, out = 0 }
        s.modules["gearUpgrades"].out = 0
    end },
}

-- Вспомогательное -------------------------------------------------------------

local PREFIX = "ForeverPilot: "

-- Строка чата без цвета и без подписи аддона.
function C.chatText(S, line)
    local plain = S.plain(line)
    if plain:sub(1, #PREFIX) == PREFIX then plain = plain:sub(#PREFIX + 1) end
    return plain
end

function C.fresh(H, S, state)
    local env = S.load(H)
    S.populate(env, H)
    local nsr = env.ns
    nsr.Config:Get().panel.enabled = true
    nsr.Config:Get().ui.minimapButton = true
    if state and state.prepare then state.prepare(env, H) end
    env.said = {}
    return env
end

-- Все подсказки, которые появляются при наведении на что-либо видимое.
local function hoverAll(env, S, into, where)
    local tip = env.G.GameTooltip
    local lines
    tip.AddLine = function(_, text) lines[#lines + 1] = tostring(text) end
    tip.AddDoubleLine = function(_, a, b)
        lines[#lines + 1] = tostring(a) .. " " .. tostring(b)
    end
    tip.SetHyperlink = function() end
    local n = 0
    for _, frame in ipairs(env.world.frames) do
        local enter = frame.__scripts and frame.__scripts.OnEnter
        if enter and frame.__shown then
            lines = {}
            pcall(enter, frame)
            n = n + 1
            for _, text in ipairs(lines) do
                into[#into + 1] = { text = text, channel = "tip", where = where }
            end
        end
    end
    return n
end

-- Нажимаемые элементы, которые игрок сейчас видит под `root`.
function C.visibleButtons(env, S, root)
    local out = {}
    for _, frame in ipairs(env.world.frames) do
        if frame.__type == "Button" and frame.__shown
            and frame.__scripts and frame.__scripts.OnClick
            and S.descends(frame, root) then
            local node, ok = frame.__parent, true
            while node and node ~= root do
                if not node.__shown then ok = false; break end
                node = node.__parent
            end
            if ok then out[#out + 1] = frame end
        end
    end
    return out
end

function C.labelOf(S, frame)
    local fs = rawget(frame, "text") or rawget(frame, "label")
    return S.plain((type(fs) == "table" and fs.__text) or "")
end

-- Слепок всего, что игрок мог бы заметить: тексты окна и панели, что показано,
-- что сохранено. По разнице слепков видно, сделало ли нажатие хоть что-нибудь.
local function leaves(t, seen, out, prefix)
    if type(t) ~= "table" then
        out[#out + 1] = prefix .. "=" .. tostring(t)
        return
    end
    if seen[t] then return end
    seen[t] = true
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do leaves(t[k], seen, out, prefix .. "." .. tostring(k)) end
end

function C.signature(env, S)
    local nsr = env.ns
    local parts = {}
    local function surface(tag, frame)
        if not frame then return end
        parts[#parts + 1] = tag .. ":" .. tostring(frame.__shown)
        local labels, texts = S.harvest(env.world, frame)
        for _, l in ipairs(labels) do parts[#parts + 1] = tag .. ".l:" .. l end
        for _, t in ipairs(texts) do parts[#parts + 1] = tag .. ".t:" .. t end
    end
    surface("окно", nsr.MainFrame and nsr.MainFrame.frame)
    surface("панель", nsr.StepPanel and nsr.StepPanel.frame)
    parts[#parts + 1] = "вкладка:" .. tostring(nsr.MainFrame and nsr.MainFrame.activeTab)
    local arrow = nsr.Arrow
    if arrow then
        parts[#parts + 1] = "стрелка:" .. tostring(arrow.target and (tostring(arrow.target.mapID)
            .. ":" .. tostring(arrow.target.x) .. ":" .. tostring(arrow.target.y)))
        parts[#parts + 1] = "стрелка.окно:" .. tostring(arrow.frame and arrow.frame.__shown)
    end
    local mb = nsr.MinimapButton
    if mb and mb.frame then
        parts[#parts + 1] = "миникарта:" .. tostring(mb.frame.__shown)
    end
    parts[#parts + 1] = "рецептов показано:" .. #(env.openRecipeCalls or {})
    parts[#parts + 1] = "tomtom:" .. #(env.tomtomCalls or {})
    parts[#parts + 1] = "вопрос о скрытии:" .. tostring(nsr.Dismissal and nsr.Dismissal.armedKey)
    parts[#parts + 1] = "пересчётов:" .. tostring(nsr.ActionEngine and nsr.ActionEngine.buildCount)
    local cfg = {}
    leaves(nsr.Config:Get(), {}, cfg, "cfg")
    parts[#parts + 1] = table.concat(cfg, ";")
    return table.concat(parts, "\n")
end

-- Команды и все кнопки ----------------------------------------------------------
--
-- Чат - не только ответы кнопок советов. Туда же пишут команды /fp, правый
-- щелчок по совету и по панели (вопрос о скрытии и само скрытие), кнопки
-- настроек, переключатели. Здесь всё это нажимается подряд - ради слов, которые
-- аддон при этом говорит.

-- Все команды /fp. Справка (ответ на неизвестную команду) сверяется с этим
-- списком в Tests/test_sense.lua: команда, названная в справке и не названная
-- здесь, роняет тест.
C.COMMANDS = {
    "now", "char", "craft", "buy", "config", "scan",
    "panel", "panel", "panel off", "panel on",
    "hidden", "undo", "show", "reset", "api",
    "diag", "diag full", "diag reset",
    "сила", "прокачка", "экономия", "заработок",
    "такой команды нет",
}

-- Вывод этих команд - сырой дамп для разработчика, а не ответ игроку.
C.DUMP_COMMANDS = { ["diag full"] = true }

C.CHATTER_STATES = { "обычный", "в своём списке покупок есть позиции", "всё скрыто",
                     "игра не даёт части сведений" }

local function stateByName(name)
    for _, st in ipairs(C.STATES) do
        if st.name == name then return st end
    end
    return nil
end

-- Мир с загруженным Main.lua: команды /fp живут там.
function C.freshWithMain(H, S, state)
    local env = S.load(H)
    S.populate(env, H)
    local nsr, G = env.ns, env.G
    G.SlashCmdList = {}
    G.GetMerchantNumItems = G.GetMerchantNumItems or function() return 0 end
    local chunk = assert(loadfile((H.ROOT or ".") .. "/Main.lua"))
    setfenv(chunk, env.sandbox)
    chunk("ForeverPilot", nsr)
    local driver = G.ForeverPilotDriver
    local onEvent = driver and driver.__scripts and driver.__scripts.OnEvent
    if onEvent then
        pcall(onEvent, driver, "ADDON_LOADED", "ForeverPilot")
        pcall(onEvent, driver, "PLAYER_LOGIN")
    end
    S.populate(env, H)
    nsr.Config:Get().panel.enabled = true
    nsr.Config:Get().ui.minimapButton = true
    if state and state.prepare then state.prepare(env, H) end
    env.said = {}
    nsr.Api.lastSaid = nil
    return env, G.SlashCmdList and G.SlashCmdList.FOREVERPILOT
end

-- Собрать в `corpus` всё, что аддон отвечает на команды и на нажатие всего,
-- что нажимается. `add(text, channel, where)` - как в C.build.
function C.chatter(H, S, corpus, add)
    corpus.commands = corpus.commands or {}
    corpus.crashes = corpus.crashes or {}
    corpus.clicked = corpus.clicked or 0
    for _, name in ipairs(C.CHATTER_STATES) do
        local env, slash = C.freshWithMain(H, S, stateByName(name))
        local nsr = env.ns
        local function listen(where, channel, fn)
            env.said = {}
            nsr.Api.lastSaid = nil
            local ok, err = pcall(fn)
            if not ok then
                corpus.crashes[#corpus.crashes + 1] = where .. ": " .. tostring(err)
            end
            local said = {}
            for _, line in ipairs(env.said) do
                add(line, channel, where)
                said[#said + 1] = C.chatText(S, line)
            end
            return said
        end

        -- 1. Команды.
        if slash then
            for _, cmd in ipairs(C.COMMANDS) do
                local where = name .. " / команда /fp " .. cmd
                local said = listen(where, C.DUMP_COMMANDS[cmd] and "dump" or "chat",
                    function() slash(cmd) end)
                corpus.commands[#corpus.commands + 1] = { state = name, command = cmd, said = said }
            end
        else
            corpus.crashes[#corpus.crashes + 1] = name .. ": команда /fp не зарегистрирована"
        end

        -- 2. Всё, что нажимается: каждая вкладка окна и панель, обеими кнопками
        --    мыши, в два прохода (второй проход - это «второе нажатие» там, где
        --    первое только спрашивает).
        nsr.MainFrame:Build()
        nsr.StepPanel:Build()
        for pass = 1, 2 do
            for _, def in ipairs(nsr.MainFrame.TABS) do
                pcall(function()
                    nsr.MainFrame:Show()
                    nsr.MainFrame:Select(def.key)
                    nsr.MainFrame:RenderActive()
                    nsr.StepPanel:ApplyVisibility()
                end)
                local roots = { { nsr.MainFrame.frame, "окно / " .. def.label },
                                { nsr.StepPanel.frame, "панель" } }
                for _, root in ipairs(roots) do
                    local buttons = root[1] and C.visibleButtons(env, S, root[1]) or {}
                    if root[1] and root[1].__type == "Button" and root[1].__shown
                        and root[1].__scripts and root[1].__scripts.OnClick then
                        buttons[#buttons + 1] = root[1]
                    end
                    for _, btn in ipairs(buttons) do
                        local label = C.labelOf(S, btn)
                        for _, mouse in ipairs({ "LeftButton", "RightButton" }) do
                            corpus.clicked = corpus.clicked + 1
                            listen(name .. " / " .. root[2] .. " / щелчок ("
                                .. ((mouse == "LeftButton") and "левый" or "правый") .. ", проход "
                                .. pass .. ") по «" .. ((label ~= "") and label or "без подписи") .. "»",
                                "chat", function() btn.__scripts.OnClick(btn, mouse) end)
                        end
                    end
                end
            end
        end
    end
end

-- Сборка ----------------------------------------------------------------------

-- ЧТО СТОИТ НАД СПИСКОМ И ЧТО НА ЧТО НАЛЕЗАЕТ - В ТОМ ЖЕ СОБРАНИИ.
--
-- Правилам осмысленности хватает текста, а двум жалобам игрока - нет: «простыня
-- над списком» и «кнопка нарисована поверх строки с числами» видны только
-- РАЗМЕТКОЙ. Поэтому вместе с текстами собираются и измерения: строка над
-- списком (сколько строк, какой ширины, что под курсором), полосы шапки
-- (прямоугольники по привязкам) и то, что реально нарисовано в строках
-- карточек рядом с тем, сколько места у них было.
--
-- Все три собираются в том же проходе по состояниям мира - без второго
-- построения восемнадцати миров.
local function measureNow(C2, env, S, state, into)
    local ns = env.ns
    local tab = ns.TabNow
    if not (tab and tab.frame) then return end

    -- 1. Строка в шапке списка: «N советов · ещё M не показано». Отдельной
    --    строки над списком больше нет; что не показано, сказано здесь числом,
    --    а причины стоят под курсором (tab.summaryTip).
    local summary = tab.summary
    if summary then
        local text = S.plain(summary:GetText() or "")
        local details = {}
        for _, d in ipairs(tab.summaryTip or {}) do details[#details + 1] = S.plain(d) end
        local total = #(ns.ActionEngine.cards or {})
        local hostW = ns.MainFrame:HostNow()
        local hiddenShown = tab.hiddenButton and tab.hiddenButton.__shown
        into.strips[#into.strips + 1] = {
            state = state.name,
            -- «Сказано» - строка называет не показанное.
            shown = text:find("не показано", 1, true) ~= nil,
            -- Сколько советов убрали правила (порог, профиль, длина списка).
            hidden = tab:HiddenByRules(ns.ActionEngine.meta, total),
            text = text,
            lines = (text == "") and 0 or (select(2, text:gsub("\n", "")) + 1),
            width = S.textWidth(text),
            room = math.max(100, tab.Columns(hostW).main - 48 - (hiddenShown and 150 or 0)),
            details = details,
        }
    end

    -- 2. Полосы шапки: прямоугольники по привязкам, от левого верхнего угла
    --    вкладки. Названия - те, которыми их назвал бы игрок.
    local bands = {}
    local function band(name, el)
        local rect = el and S.rectOf(el, tab.frame)
        if rect then bands[#bands + 1] = { name = name, rect = rect } end
    end
    band("подпись профилей", tab.profileLabel)
    for key, chip in pairs(tab.profileChips or {}) do
        band("профиль «" .. (ns.PROFILE_LABEL[key] or key) .. "»", chip)
    end
    for key, chip in pairs(tab.filterChips or {}) do
        band("фильтр «" .. (ns.CHIP_LABEL[key] or key) .. "»", chip)
    end
    band("строка статистики", tab.summary)
    band("список советов", tab.scroll)
    table.sort(bands, function(a, b) return a.name < b.name end)
    into.bands[#into.bands + 1] = {
        state = state.name, bands = bands,
        width = tonumber(tab.frame.__width) or 0,
    }

    -- 3. Строки списка: что нарисовано, что было целиком, сколько места.
    --    В строке заголовок и выгода; «почему» и «чего не хватает» стоят в
    --    карточке совета справа - целиком (см. measureDetail ниже).
    for _, row in ipairs(ns.Card.pool) do
        if row.__shown and row.card then
            local card = row.card
            local room = ns.Card.RoomFor(row, card)
            into.rows[#into.rows + 1] = {
                state = state.name, card = card,
                width = tonumber(row.__width) or 0,
                lines = {
                    -- В строке заголовок стоит без слова, уже сказанного
                    -- заголовком раздела (Card.ListTitle).
                    { name = "заголовок", drawn = S.plain(row.title:GetText() or ""),
                      full = S.plain(ns.Card.ListTitle(card)), room = room.title,
                      cut = (row.cut or {}).title },
                    { name = "выгода", drawn = S.plain(row.benefit:GetText() or ""),
                      full = S.plain(tostring(card.benefit or "")), room = room.benefit,
                      cut = (row.cut or {}).benefit },
                },
            }
        end
    end
end

-- КАРТОЧКА СОВЕТА СПРАВА ОТ СПИСКА - ДЛЯ КАЖДОГО СОВЕТА НА ЭКРАНЕ.
--
-- Щелчок по строке открывает совет в карточке: полный текст и одна кнопка.
-- Здесь это делается для каждой строки по очереди, и собирается всё, что в
-- карточке при этом стоит: текст (он идёт в общее собрание, под правила
-- смысла), прямоугольники частей (под правило «ничто ни на что не налезает») и
-- то, что нарисовано целиком, рядом с тем, что должно было быть.
local function measureDetail(C2, env, S, state, into, add)
    local ns = env.ns
    local detail = ns.Detail
    if not (detail and detail.frame and ns.TabNow and ns.TabNow.frame) then return end
    local rows = {}
    for _, row in ipairs(ns.Card.pool) do
        if row.__shown and row.card then rows[#rows + 1] = row end
    end
    local first = rows[1] and rows[1].card
    for _, row in ipairs(rows) do
        local card = row.card
        S.pick(ns, row)
        local where = state.name .. " / карточка совета «" .. tostring(card.title) .. "»"
        local labels, texts = S.harvest(env.world, detail.frame)
        for _, l in ipairs(labels) do add(l, "label", where, card) end
        for _, t in ipairs(texts) do add(t, "screen", where, card) end
        local parts = S.detailParts(ns)
        into.details[#into.details + 1] = {
            state = state.name, card = card, parts = parts, picked = detail.card == card,
            width = tonumber(detail.frame.__width) or 0,
            height = tonumber(detail.frame.__height) or 0,
            labels = labels, texts = texts,
            action = detail.action.__shown and S.plain(detail.action.text.__text or "") or nil,
        }
    end
    -- Вернуть выбор туда, где он был: дальше экран читают другие сборщики.
    if first then ns.TabNow:SelectCard(first) end
end

-- opts.states - список состояний (по умолчанию C.STATES)
function C.build(H, S, opts)
    opts = opts or {}
    local corpus = {
        lines = {},     -- { text, channel, where, card }
        cards = {},     -- { state, card, env-independent copies of the fields }
        screens = {},   -- { state, where, labels, texts, kinds = {kind=count}, meta }
        presses = {},   -- { state, card, label, kind, said = {...}, changed, opened, ... }
        summaries = {}, -- { state, lines = {...}, kindsOnScreen = {...}, branchCounts }
        strips = {},    -- { state, shown, text, lines, width, room, details }
        bands = {},     -- { state, width, bands = { { name, rect } } }
        rows = {},      -- { state, card, width, lines = { { name, drawn, full, room } } }
        details = {},   -- { state, card, parts = { { name, rect, drawn, full } }, action }
        states = {},
        hovered = 0,
    }
    local function add(text, channel, where, card)
        if type(text) ~= "string" or text == "" then return end
        corpus.lines[#corpus.lines + 1] =
            { text = text, plain = S.plain(text), channel = channel, where = where, card = card }
    end

    for _, state in ipairs(opts.states or C.STATES) do
        local env = C.fresh(H, S, state)
        local nsr = env.ns
        corpus.states[#corpus.states + 1] = state.name
        nsr.MainFrame:Build()
        nsr.MainFrame:ApplyMinimapButton()
        nsr.StepPanel:Build()
        nsr.StepPanel:ApplyVisibility()

        -- 1. Сами советы: поля, из которых экран их рисует.
        for _, card in ipairs(nsr.ActionEngine.cards or {}) do
            local where = state.name .. " / совет «" .. tostring(card.title) .. "»"
            add(card.title, "title", where, card)
            add(card.benefit, "benefit", where, card)
            add(card.why, "why", where, card)
            add(card.need, "need", where, card)
            if card.action and card.action.label then
                add(card.action.label, "label", where, card)
            end
            corpus.cards[#corpus.cards + 1] = {
                state = state.name, card = card,
                -- сколько этого предмета игрок закрепил в своём списке руками
                pinned = card.itemID and nsr.Config:Shopping()[card.itemID] or nil,
            }
        end

        -- 2. Экраны: каждая вкладка окна и панель.
        for _, def in ipairs(nsr.MainFrame.TABS) do
            nsr.MainFrame:Select(def.key)
            -- Размеры - как их посчитал бы клиент, и ПОСЛЕ того, как вкладка
            -- создана: без них ширина нулевая, а на нулевой ширине измерения
            -- разметки ничего не значат (см. S.layout).
            S.layout(env)
            nsr.MainFrame:RenderActive()
            local where = state.name .. " / окно / " .. def.label
            local labels, texts = S.harvest(env.world, nsr.MainFrame.frame)
            for _, l in ipairs(labels) do add(l, "label", where) end
            for _, t in ipairs(texts) do add(t, "screen", where) end
            local kinds = {}
            if def.key == "NOW" then
                for _, row in ipairs(nsr.Card.pool) do
                    if row.__shown and row.card then
                        kinds[row.card.kind] = (kinds[row.card.kind] or 0) + 1
                    end
                end
            end
            corpus.screens[#corpus.screens + 1] = {
                state = state.name, tab = def.key, where = where,
                labels = labels, texts = texts, kinds = kinds,
            }
            if def.key == "NOW" then
                measureNow(C, env, S, state, corpus)
                measureDetail(C, env, S, state, corpus, add)
            end
            local tips = {}
            corpus.hovered = corpus.hovered + hoverAll(env, S, tips, where .. " / подсказка")
            for _, t in ipairs(tips) do add(t.text, t.channel, t.where) end
        end
        nsr.MainFrame:Select("NOW")
        nsr.MainFrame:RenderActive()

        local pf = nsr.StepPanel.frame
        if pf and pf:IsShown() then
            nsr.StepPanel:Render()
            for step = 1, #(nsr.ActionEngine.cards or {}) + 1 do
                local where = state.name .. " / панель, совет " .. step
                local labels, texts = S.harvest(env.world, pf)
                for _, l in ipairs(labels) do add(l, "label", where) end
                for _, t in ipairs(texts) do add(t, "screen", where) end
                corpus.screens[#corpus.screens + 1] = {
                    state = state.name, tab = "PANEL", where = where,
                    labels = labels, texts = texts, kinds = {},
                }
                local tips = {}
                local enter = pf.__scripts and pf.__scripts.OnEnter
                if enter then
                    local lines = {}
                    env.G.GameTooltip.AddLine = function(_, text) lines[#lines + 1] = tostring(text) end
                    pcall(enter, pf)
                    for _, text in ipairs(lines) do add(text, "tip", where .. " / подсказка") end
                end
                if not nsr.StepPanel:Advance() then break end
            end
        end

        -- 3. Сводка диагностики и то, что она говорит о ветках, - рядом с тем,
        --    что в этот момент на экране.
        local kindsOnScreen, total = {}, 0
        for _, card in ipairs(nsr.ActionEngine.cards or {}) do
            kindsOnScreen[card.kind] = (kindsOnScreen[card.kind] or 0) + 1
            total = total + 1
        end
        -- Сводка «простым языком» пишется в файл диагностики на каждом
        -- пересчёте (Diag:WriteSummary); берём её оттуда же, откуда её прочтёт
        -- игрок, а не строим заново.
        local summary = {}
        do
            pcall(function() nsr.Diag:WriteSummary() end)
            local stored = nsr.Diag:Init().summary
            if type(stored) == "table" then
                for _, line in ipairs(stored) do summary[#summary + 1] = tostring(line) end
            end
        end
        local short = {}
        do
            local ok, lines = pcall(function() return nsr.Diag:Summary() end)
            if ok and type(lines) == "table" then short = lines end
        end
        for _, l in ipairs(summary) do add(l, "summary", state.name .. " / сводка в файле") end
        for _, l in ipairs(short) do add(l, "diag", state.name .. " / команда /fp diag") end
        corpus.summaries[#corpus.summaries + 1] = {
            state = state.name, lines = summary, short = short,
            kindsOnScreen = kindsOnScreen, total = total,
            meta = nsr.ActionEngine.meta, cards = nsr.ActionEngine.cards,
            branchLabel = nsr.ActionEngine.BRANCH_LABEL, branchOrder = nsr.ActionEngine.BRANCH_ORDER,
            branchByKind = nsr.ActionEngine.BRANCH_BY_KIND,
            kindLabel = nsr.KIND_LABEL,
            -- Пространство имён этого мира - по той же причине, по которой оно
            -- лежит у нажатий ниже: договору иногда нужно спросить у самого
            -- аддона, как он что-то называет, а не повторять его правило вторым
            -- списком в тесте.
            ns = nsr,
        }

        -- 4. Нажатия: кнопка каждого совета - что она ответила и что изменилось.
        --    Идёт последним: нажатия меняют мир.
        nsr.MainFrame:Select("NOW")
        nsr.MainFrame:RenderActive()
        local targets = {}
        for _, row in ipairs(nsr.Card.pool) do
            if row.__shown and row.card then targets[#targets + 1] = row end
        end
        for _, row in ipairs(targets) do
            local card = row.card
            local act = card.action or {}
            -- ЧТО НА КНОПКЕ НАПИСАНО И ЧТО ОНА ДЕЛАЕТ - СПРАШИВАЕМ ДО НАЖАТИЯ.
            -- Подпись и действие у совета теперь зависят от того, что открыто
            -- (аукцион, окно профессии): Card.LiveAction. Договор проверяется
            -- по тому, что было на кнопке в момент нажатия.
            local live = nsr.Card.LiveAction and nsr.Card.LiveAction(card) or nil
            local liveKind = (live and live.kind) or act.kind
            local liveLabel = (live and live.label) or act.label
            -- ЩЕЛЧОК ПО СТРОКЕ ВЫБИРАЕТ СОВЕТ, КНОПКА - В КАРТОЧКЕ СПРАВА.
            --
            -- Так теперь действует игрок, так же действует и проверка: щелчок
            -- по строке, потом кнопка карточки, если она нарисована. Если
            -- кнопки нет (у советов про рецепт её нет вовсе: открыть окно
            -- профессий игра аддонам запрещает), ответ игроку стоит словами в
            -- самой карточке - и он собран выше, в measureDetail.
            --
            -- Выбор идёт ДО снимка мира: «что изменилось» - это про нажатие
            -- кнопки, а не про то, какой совет открыт справа.
            local ok, err = pcall(S.pick, nsr, row)
            local button = ok and S.actionOf(nsr, row) or nil
            local shown = button ~= nil
            local handler = button and button.__scripts and button.__scripts.OnClick
            env.said = {}
            nsr.Api.lastSaid = nil            -- каждое нажатие слушаем с чистого листа
            local before = C.signature(env, S)
            local callsBefore = #(env.openRecipeCalls or {})
            if handler then
                ok, err = pcall(handler, button)
            end
            local said = {}
            for _, line in ipairs(env.said) do
                said[#said + 1] = C.chatText(S, line)
                add(line, "chat", state.name .. " / ответ на «" .. tostring(act.label or "?")
                    .. "» у совета «" .. tostring(card.title) .. "»", card)
            end
            corpus.presses[#corpus.presses + 1] = {
                state = state.name, card = card, kind = liveKind, label = liveLabel,
                drawn = shown and true or false, pressed = handler ~= nil,
                ok = ok, err = err, said = said, raw = env.said,
                changed = C.signature(env, S) ~= before,
                recipeCalls = #(env.openRecipeCalls or {}) - callsBefore,
                items = env.items,
                -- Пространство имён этого мира: договорам иногда нужно
                -- спросить у самого аддона, как он что-то называет (имя
                -- профессии для игрока - U.profLabel), а не повторять его
                -- правило второй раз в тесте.
                ns = nsr,
            }
        end
    end

    -- 5. Команды /fp и все кнопки окна - в отдельных мирах: они меняют всё.
    if not opts.states then C.chatter(H, S, corpus, add) end
    return corpus
end

-- Слова текста: кириллица и латиница, со счётом байтов UTF-8.
function C.words(text)
    local out = {}
    for word in tostring(text):gmatch("[%a\128-\255][%a%d\128-\255%-]*") do
        out[#out + 1] = word
    end
    return out
end

return C
