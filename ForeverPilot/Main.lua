-- ForeverPilot / Main.lua
-- Bootstrap: bind SavedVariables, wire the events, open the window.
local ADDON, ns = ...

local U = ns.Util
local Api = ns.Api

local Main = {}
ns.Bootstrap = Main

local driver = CreateFrame("Frame", "ForeverPilotDriver")
driver:RegisterEvent("ADDON_LOADED")
driver:RegisterEvent("PLAYER_LOGIN")
driver:RegisterEvent("PLAYER_LOGOUT")

local loaded, loggedIn = false, false

-- ЧТО ОБЯЗАНО БЫТЬ ЗАГРУЖЕНО, ПРЕЖДЕ ЧЕМ ХОТЬ ЧТО-ТО ЗАПУСКАТЬ.
--
-- Один файл с синтаксической ошибкой клиент пропускает молча: остальные 45
-- грузятся, аддон делает вид, что работает, и падает на первом обращении к
-- пропавшему модулю. Так и вышло: Logic\ActionEngine.lua не компилировался под
-- Lua 5.1, и за одну сессию игрок получил 140 одинаковых красных строк
-- «attempt to index field 'ActionEngine' (a nil value)» — каждые несколько
-- секунд, по таймеру пересчёта. Из них нельзя понять ни что случилось, ни что
-- делать.
--
-- Поэтому инициализация начинается с переписи: если хоть один модуль не
-- приехал, аддон НЕ подписывается на события и НЕ считает советы, а говорит
-- один раз и по делу, какой файл игра не прочитала.
--
-- Таблица ведётся руками, и именно поэтому её держит тест: набор test_load
-- сверяет её с .toc в обе стороны, так что новый файл нельзя добавить в .toc и
-- забыть здесь.
Main.MODULES = {
    -- Core\Const.lua кладёт в ns константы, а не таблицу модуля: сторожем
    -- служит ns.KIND — без него не построить ни одной карточки.
    { file = "Core\\Const.lua",              name = "KIND" },
    { file = "Core\\Util.lua",                name = "Util" },
    { file = "Core\\Diag.lua",                name = "Diag" },
    { file = "Core\\Geo.lua",                 name = "Geo" },
    { file = "Core\\Api.lua",                 name = "Api" },
    { file = "Core\\Config.lua",              name = "Config" },
    { file = "Core\\Events.lua",              name = "Events" },
    { file = "Data\\SlotMap.lua",             name = "SlotMap" },
    { file = "Data\\StatWeights.lua",         name = "StatWeights" },
    { file = "Data\\ForeverSource.lua",       name = "ForeverSource" },
    { file = "Data\\Horizon.lua",             name = "Horizon" },
    { file = "Data\\Camp.lua",                name = "CampData" },
    { file = "Logic\\RecipeBook.lua",         name = "RecipeBook" },
    { file = "Logic\\Roster.lua",             name = "Roster" },
    { file = "Logic\\CharacterScanner.lua",   name = "CharacterScanner" },
    { file = "Logic\\MarketHistory.lua",      name = "MarketHistory" },
    { file = "Logic\\Ledger.lua",             name = "Ledger" },
    { file = "Logic\\PriceProvider.lua",      name = "PriceProvider" },
    { file = "Logic\\Risk.lua",               name = "Risk" },
    { file = "Logic\\CraftingPlanner.lua",    name = "CraftingPlanner" },
    { file = "Logic\\GearAdvisor.lua",        name = "GearAdvisor" },
    { file = "Logic\\EnchantAdvisor.lua",     name = "EnchantAdvisor" },
    { file = "Logic\\Places.lua",             name = "Places" },
    { file = "Logic\\ShoppingList.lua",       name = "ShoppingList" },
    { file = "Logic\\Dismissal.lua",          name = "Dismissal" },
    { file = "Logic\\SanityChecks.lua",       name = "SanityChecks" },
    { file = "Logic\\SourceCheck.lua",        name = "SourceCheck" },
    { file = "Logic\\Appearance.lua",         name = "Appearance" },
    { file = "Logic\\Foresight.lua",          name = "Foresight" },
    { file = "Logic\\ActionEngine.lua",       name = "ActionEngine" },
    { file = "Logic\\VendorArbitrage.lua",    name = "VendorArbitrage" },
    { file = "Logic\\Favor.lua",              name = "Favor" },
    { file = "Logic\\CampAdvisor.lua",        name = "CampAdvisor" },
    { file = "Logic\\UpgradePaths.lua",       name = "UpgradePaths" },
    { file = "Logic\\CrossCharacter.lua",     name = "CrossCharacter" },
    { file = "Logic\\Disenchant.lua",         name = "Disenchant" },
    { file = "Logic\\Resale.lua",             name = "Resale" },
    { file = "Logic\\AuctionMoment.lua",      name = "AuctionMoment" },
    { file = "Logic\\Notifier.lua",           name = "Notifier" },
    { file = "Logic\\Provenance.lua",         name = "Provenance" },
    { file = "UI\\Widgets.lua",               name = "Widgets" },
    { file = "UI\\Arrow.lua",                 name = "Arrow" },
    { file = "UI\\Card.lua",                  name = "Card" },
    { file = "UI\\StepPanel.lua",             name = "StepPanel" },
    { file = "UI\\TabNow.lua",                name = "TabNow" },
    { file = "UI\\TabCharacter.lua",          name = "TabCharacter" },
    { file = "UI\\TabCraft.lua",              name = "TabCraft" },
    { file = "UI\\TabSettings.lua",           name = "TabSettings" },
    { file = "UI\\MinimapButton.lua",         name = "MinimapButton" },
    { file = "UI\\MainFrame.lua",             name = "MainFrame" },
    { file = "Main.lua",                      name = "Bootstrap" },
}

-- Какие модули не приехали. Пустой список - всё на месте.
function Main:MissingModules()
    local out = {}
    for _, m in ipairs(Main.MODULES) do
        if ns[m.name] == nil then out[#out + 1] = m end
    end
    return out
end

-- Сказать это ОДИН раз, словами, и назвать файл.
--
-- Печатаем через `print`, а не через Api:Print: сломаться мог как раз Core\Api.
-- По той же причине здесь нет ни Diag, ни Config - только то, что есть в игре
-- всегда.
function Main:ReportBrokenLoad(missing)
    local files = {}
    for _, m in ipairs(missing) do files[#files + 1] = m.file end
    local one = (#files == 1)
    -- Сломаться мог и сам Core\Api, поэтому говорим через print клиента. Если и
    -- его нет, молчим: падать в сообщении о падении - худшее из возможного.
    local say = (type(_G.print) == "function") and _G.print or function() end
    local lines = {
        "|cffff6060ForeverPilot загрузился не полностью и поэтому выключен.|r",
        (one and "Игра не смогла прочитать файл: " or "Игра не смогла прочитать файлы: ")
            .. table.concat(files, ", ") .. ".",
        "Это ошибка внутри " .. (one and "самого файла" or "этих файлов")
            .. ", а не в ваших настройках. Советов я не считаю — иначе чат"
            .. " завалит одинаковыми ошибками.",
        "Что делать: сообщите автору, какой файл назван выше. Текст ошибки игра"
            .. " печатает при входе — его видно в окне ошибок интерфейса.",
    }
    for _, line in ipairs(lines) do say("ForeverPilot: " .. line) end

    -- Чтобы /fp не молчал: та же самая фраза по команде, если игрок попробует.
    if _G.SlashCmdList and _G.SLASH_FOREVERPILOT1 == nil then
        _G.SLASH_FOREVERPILOT1 = "/foreverpilot"
        _G.SLASH_FOREVERPILOT2 = "/fp"
        _G.SlashCmdList["FOREVERPILOT"] = function()
            for _, line in ipairs(lines) do say("ForeverPilot: " .. line) end
        end
    end
    -- И в диагностику, если она сама жива: иначе файл сессии не объяснит,
    -- почему в нём ничего нет.
    if ns.Diag and ns.Diag.Log then
        pcall(function()
            ns.Diag:Log("аддон не загрузился целиком", { missing = files })
        end)
    end
end

local function initialize()
    if not (loaded and loggedIn) then return end
    if Main.ready or Main.halted then return end

    -- ПЕРЕПИСЬ МОДУЛЕЙ ПЕРЕД ВСЕМ ОСТАЛЬНЫМ. См. Main.MODULES выше: без неё
    -- один непрочитанный файл превращается в поток одинаковых ошибок.
    local missing = Main:MissingModules()
    if #missing > 0 then
        Main.halted = true
        Main:ReportBrokenLoad(missing)
        return
    end

    Main.ready = true

    -- Detection first: it is what fills the feature-detect section of the
    -- diagnostics, and everything after it depends on the result.
    Api:Detect()
    ns.Diag:CaptureEnvironment()
    -- Версии внешних баз и свежесть наших собственных данных: отдельным
    -- разделом, чтобы по файлу было видно не только «чего не хватило», но и
    -- «чем мы это пытались закрыть и насколько это старое».
    ns.Diag:CaptureDataVersions()
    ns.Diag:Log("инициализация начата", {
        sanityChecks = ns.SanityChecks:Count(),
    })

    -- Events takes over the frame's OnEvent, so the bootstrap events have to be
    -- handed to it explicitly or they stop arriving (PLAYER_LOGOUT in
    -- particular, which is when the diagnostics session gets closed).
    ns.Events:Init(driver, Main.OnBootstrapEvent)
    ns.Events:On("recompute", function(reasons)
        -- Item data arrived: drop exactly the entries that were waiting on it.
        if reasons.items and ns.GearAdvisor.RetryPending then
            ns.GearAdvisor:RetryPending()
        end
        -- NOT A FULL INVALIDATION, and that is deliberate.
        -- The caches hold only complete answers, so an item that was missing
        -- something is simply re-read on the next pass. Clearing everything
        -- here - which an earlier version did - turned the client's 4268
        -- GET_ITEM_INFO_RECEIVED events in one session into 4268 full cache
        -- rebuilds and cost more than the caching saved.
        --
        -- A recipe-window event is the one case where we also rescan the
        -- window itself, because that is the only moment the game will tell us
        -- what the player knows.
        -- Игрок открывал или закрывал аукцион: Auctionator мог пересканировать
        -- базу, и помнить прежние ответы больше нельзя.
        if reasons.prices and Api.ClearAuctionCache then
            -- С ограничителем: сигналов «цены могли измениться» десятки на одно
            -- сканирование аукциона. См. ns.AUCTION_RESCAN_GUARD.
            Api:ClearAuctionCache("игрок был у аукциона", true)
        end
        -- ЧУЖАЯ КНИГА ЗАКУПОК МОГЛА ПОЛУЧИТЬ НОВЫЙ ЛОТ - И ТОЛЬКО ТУТ.
        --
        -- Ответ «по этому предмету рыночной записи нет» помнится всю сессию
        -- (Api:MastercraftObservedPrice): сам он измениться не может. Новый лот
        -- в чужой книге появляется ровно тогда, когда игрок что-то купил или
        -- продал, а это видно по деньгам, сумкам и окнам торговца и аукциона.
        if (reasons.money or reasons.bags or reasons.vendor or reasons.prices)
            and Api.ClearObservedPriceMemory then
            Api:ClearObservedPriceMemory("деньги или сумки изменились")
        end
        if reasons.recipes then
            local prof, count = ns.RecipeBook:ScanOpenWindow()
            if prof and count > 0 then
                Api:Print("прочитал " .. count .. " "
                    .. U.plural(count, "рецепт", "рецепта", "рецептов")
                    -- Имя - для игрока (U.profLabel): окно профессии отдаёт
                    -- его на языке клиента, но путь к этой строке один, и он
                    -- обязан быть тем же, что у всех остальных.
                    .. " по «" .. tostring(U.profLabel(prof)) .. "»")
            end
        end
        ns.MainFrame:Rebuild(false, reasons)
        -- ГОРИЗОНТ - ДО СЛЕПКА, И ЭТО ВАЖНО ИМЕННО В ЭТОМ ПОРЯДКЕ. Слепок цен
        -- берёт список предметов у движка, а движок спрашивает у горизонта, что
        -- понадобится позже. Собери горизонт после слепка - и материалы на
        -- будущий ранг профессии начнут записываться только со следующего дня,
        -- а день истории цен не восстановить ничем.
        --
        -- Сам Refresh дешёвый: он почти всегда отвечает «не пора» (раз в 15
        -- минут, плюс смена уровня и подъём потолка навыка).
        if ns.Foresight then ns.Foresight:Refresh(ns.CharacterScanner:Get()) end
        Main:MaybeSnapshotPrices()
    end)
    ns.Events:On("combat", function(inCombat)
        ns.MainFrame:OnCombat(inCombat)
    end)
    -- Окно профессии открыли, обновили или закрыли: книга рецептов ставит
    -- обещанный поиск, а кнопки на советах меняют подпись.
    ns.Events:On("tradeskill", function(phase)
        local message, changed = ns.RecipeBook:OnTradeSkill(phase)
        if message then Api:Print(message) end
        if changed and ns.MainFrame.RefreshIfShown then ns.MainFrame:RefreshIfShown() end
    end)
    -- Аукцион открыли или закрыли: на советах появляется или пропадает кнопка
    -- «Искать на аукционе». Пересчёт для этого не нужен - только перерисовка.
    ns.Events:On("auction", function(what)
        if (what == "open" or what == "close") and ns.MainFrame.RefreshIfShown then
            ns.MainFrame:RefreshIfShown()
        end
    end)
    ns.Events:On("merchant", function(phase)
        -- Закрытое окно читать нечего: фаза «close» нужна книге закупок, а не
        -- чтению цен. Без этой проверки каждое закрытие торговца запускало бы
        -- пустой проход по окну, которого уже нет.
        if phase == "close" then return end
        Main:ReadMerchant()
    end)
    ns.Events:On("trainer", function()
        Main:ReadTrainer()
    end)
    ns.Events:On("zone", function()
        ns.MainFrame:OnZoneChanged()
    end)
    -- МОМЕНТ АУКЦИОНА. Единственный раз за сессию, когда у аддона есть свежий
    -- срез рынка: тут сбрасывается память цен, обновляется суточный слепок (его
    -- нельзя отложить - историю задним числом не собрать) и говорится одна
    -- фраза, если появилось что-то заметно выгодное.
    if ns.AuctionMoment then ns.AuctionMoment:Bind() end
    -- СВОЯ КНИГА ЗАКУПОК. Подписывается на те же сигналы (торговец, аукцион,
    -- пересчёт) - своих подписок на события не делает, чтобы отчёт
    -- Events:Report() остался полным ответом на «на что аддон подписан».
    if ns.Ledger then ns.Ledger:Bind() end
    -- ПОДЪЁМ ПОТОЛКА НАВЫКА. Клиент пишет про повышение в чат, и это
    -- единственный надёжный признак; сам потолок читается из данных, а не
    -- угадывается по сообщению.
    if ns.Notifier then ns.Notifier:Bind() end

    ns.MainFrame:Build()
    ns.MainFrame:ApplyMinimapButton()
    ns.MainFrame:OnZoneChanged()
    ns.MainFrame:Rebuild(true)
    -- The compact panel builds itself only if it is enabled; off costs nothing.
    ns.StepPanel:ApplyVisibility()
    ns.StepPanel:Render()

    Main:RegisterSlash()

    -- Окно возвращается в том же виде, в каком игрок его оставил. Пишет это
    -- поле только явное действие игрока, так что на свежей установке и после
    -- закрытия крестиком окно не выскакивает. Порядок важен: кнопка у
    -- миникарты уже создана, поэтому «как вернуть» назовёт и её.
    ns.MainFrame:RestoreShown()

    ns.Diag:Log("инициализация завершена", {
        cards = #(ns.ActionEngine.cards or {}),
        errors = #(ns.Diag:Init().errors or {}),
    })
    ns.Diag:Trim()

    if not ns.Config:Get().welcomed then
        ns.Config:Get().welcomed = true
        Api:Print("готов. /fp — открыть окно. Я только советую, ничего не делаю сам.")
        Api:Print("/fp diag — короткая сводка самопроверки.")
    end

    -- If anything already went wrong before the player touched anything, say so
    -- now rather than waiting to be asked.
    local s = ns.Diag:Init()
    if #s.errors > 0 then
        Api:Print("|cffff6060при запуске были ошибки (" .. #s.errors
            .. ") — наберите /fp diag|r")
    elseif #s.suspicious > 0 then
        Api:Print("|cffffcc40самопроверка нашла странности (" .. #s.suspicious
            .. ") — наберите /fp diag|r")
    end
end

-- The bootstrap events. This function is both the frame's own handler before
-- initialisation and the passthrough Events calls afterwards, so ADDON_LOADED,
-- PLAYER_LOGIN and PLAYER_LOGOUT are handled exactly once either way.
-- Игра догрузила своё окно профессий - оно грузится по требованию, когда
-- игрок открывает его сам. С этого момента рецепт можно показывать, и у
-- советов должна появиться кнопка. Пересчёт не нужен: советы те же, изменилось
-- только то, можно ли нажать.
function Main:OnProfessionsUI()
    if not Main.ready then return end
    ns.Diag:Guard("Main:OnProfessionsUI", function()
        if ns.MainFrame and ns.MainFrame.Refresh then ns.MainFrame:Refresh() end
    end)
end

function Main.OnBootstrapEvent(event, arg1)
    if event == "ADDON_LOADED" and arg1 == "Blizzard_Professions" then
        Main:OnProfessionsUI()
        return
    end
    if event == "ADDON_LOADED" and arg1 == ADDON then
        ForeverPilotDB = ForeverPilotDB or {}
        ForeverPilotCharDB = ForeverPilotCharDB or {}
        -- The diagnostics live in their own SavedVariables so they can be
        -- deleted or sent to someone without touching the player's settings.
        FOREVERPILOT_DIAG = FOREVERPILOT_DIAG or {}
        ns.Diag:Bind(FOREVERPILOT_DIAG)
        ns.Config:Bind(ForeverPilotDB, ForeverPilotCharDB)
        loaded = true
        initialize()
        return
    end
    if event == "PLAYER_LOGOUT" then
        -- Stamp the session so a truncated file is recognisable as truncated.
        ns.Diag:Finish()
        return
    end
    if event == "PLAYER_LOGIN" then
        loggedIn = true
        initialize()
        return
    end
end

driver:SetScript("OnEvent", function(self, event, arg1)
    if ns.Events.PASSTHROUGH[event] then
        Main.OnBootstrapEvent(event, arg1)
        return
    end
    -- Once initialised, the scheduler owns the event stream.
    if Main.ready then ns.Events:OnEvent(event, arg1) end
end)

-- Merchant and trainer ---------------------------------------------------
-- Reading a window the player opened is not automation: nothing is bought and
-- nothing is trained. What we take from it is the asking prices, the vendor's
-- stock list, and where this NPC stands - which is how the "show the way"
-- button gets anything to point at.

function Main:ReadMerchant()
    local learned, npcID, name = ns.Places:RecordMerchant()
    if (learned or 0) > 0 then
        ns.Events:MarkDirty("prices")
        if npcID then
            local _, _, _, zone = Api:PlayerPosition()
            Api:Print("записал торговца «" .. (name or ("#" .. npcID)) .. "»"
                .. (zone and (" (" .. zone .. ")") or "")
                .. ": " .. learned .. " "
                .. U.plural(learned, "позиция", "позиции", "позиций"))
        end
    end
end

function Main:ReadTrainer()
    -- No API says which profession a trainer teaches. With one crafting
    -- profession the attribution is obvious; with several it is a guess, and a
    -- guess here sends the arrow to the wrong NPC. So the ambiguous case is
    -- recorded as "a trainer, profession unknown" and the card says that.
    local profs = {}
    for _, prof in ipairs(ns.CharacterScanner:CraftingProfessions()) do
        profs[#profs + 1] = prof.name
    end
    local npcID, name, attributed = ns.Places:RecordTrainer(profs)
    if npcID then
        ns.Events:MarkDirty("places")
        if attributed then
            Api:Print("записал тренера «" .. (name or ("#" .. npcID)) .. "» — теперь"
                .. " смогу показать к нему путь")
        else
            Api:Print("записал тренера «" .. (name or ("#" .. npcID)) .. "». Какой"
                .. " он профессии, игра не говорит, так что путь покажу,"
                .. " а профессию утверждать не буду")
        end
    end
end

-- Daily price snapshot ---------------------------------------------------
-- Spread over frames so a login never stutters. One pass per day, and it only
-- uses Auctionator's documented-stable price call.

local snapshotTicker

function Main:MaybeSnapshotPrices()
    if snapshotTicker then return end
    if Api:InCombat() then return end
    local ok = ns.PriceProvider:QueueDailySnapshot(ns.ActionEngine:TrackedItems())
    if not ok then return end

    snapshotTicker = ns.Widgets.Ticker(0.25, function()
        if Api:InCombat() then return end
        local more = ns.PriceProvider:StepDailySnapshot(120)
        if not more then
            if snapshotTicker then snapshotTicker:Cancel(); snapshotTicker = nil end
            local meta = ns.Config:PriceHistoryMeta()
            if (meta.lastWritten or 0) > 0 then
                Api:Print("слепок цен за сегодня: " .. meta.lastWritten .. " "
                    .. U.plural(meta.lastWritten, "запись", "записи", "записей"))
            end
        end
    end)
end

-- Slash commands ---------------------------------------------------------

function Main:RegisterSlash()
    _G.SLASH_FOREVERPILOT1 = "/foreverpilot"
    _G.SLASH_FOREVERPILOT2 = "/fp"
    _G.SlashCmdList = _G.SlashCmdList or {}
    _G.SlashCmdList.FOREVERPILOT = function(msg)
        -- U.lower, А НЕ string.lower: вторая не знает кириллицы. Имя профиля
        -- для сравнения приводилось к нижнему регистру ею же и оставалось
        -- «Сила», поэтому «/fp сила» не совпадала ни с чем - и четыре команды
        -- из справки (сила, прокачка, экономия, заработок) отвечали справкой.
        -- Заодно «/fp Сейчас» с большой буквы перестала быть неизвестной.
        msg = U.trim(U.lower(msg or "")) or ""

        if msg == "" then
            ns.MainFrame:Toggle()
            return
        end
        if msg == "now" or msg == "сейчас" then
            ns.MainFrame:Show(); ns.MainFrame:Select("NOW"); return
        end
        -- «char» осталась от раздела «Персонаж», которого больше нет: команда
        -- открывает окно на «Советах», а не отвечает справкой.
        if msg == "char" or msg == "персонаж" then
            ns.MainFrame:Show(); ns.MainFrame:Select("NOW"); return
        end
        if msg == "craft" or msg == "крафт" or msg == "buy" or msg == "покупки" then
            ns.MainFrame:Show(); ns.MainFrame:Select("CRAFT"); return
        end
        if msg == "config" or msg == "настройки" then
            ns.MainFrame:Show(); ns.MainFrame:Select("CONFIG"); return
        end
        if msg == "scan" or msg == "обновить" then
            ns.MainFrame:Rebuild(true)
            Api:Print("пересчитал")
            return
        end
        -- ПУТЬ НАЗАД ДЛЯ ПАНЕЛИ ШАГА.
        --
        -- У панели теперь есть крестик, и закрыть её стало легко — значит,
        -- вернуть её тоже должно быть легко. Эта команда называется в том самом
        -- сообщении, которое печатается при закрытии, так что искать её не надо.
        -- Сообщения печатают Toggle/TurnOn/TurnOff: одна формулировка на все
        -- пути, и она сверяется с тем, что реально оказалось на экране.
        if msg == "panel" or msg == "панель" then
            ns.StepPanel:Toggle()
            return
        end
        if msg == "panel on" or msg == "панель вкл" then
            ns.StepPanel:TurnOn()
            return
        end
        if msg == "panel off" or msg == "панель выкл" then
            ns.StepPanel:TurnOff()
            return
        end
        -- The way back from "I hid everything and now the window is empty".
        if msg == "show" or msg == "вернуть" or msg == "показать" then
            ns.Card.RestoreHidden()
            return
        end
        -- One step back from a mis-click, named in the message every hide
        -- prints. The player has twice hidden advice by accident, and the
        -- second time it hid the very cards this was all fixed for.
        if msg == "undo" or msg == "отмена" or msg == "назад" then
            ns.Card.UndoLastHidden()
            return
        end
        if msg == "hidden" or msg == "скрытые" then
            -- Two different numbers, and they are different on purpose, so both
            -- get said. `stored` is every live dismissal in SavedVariables;
            -- `active` is how many of them actually swallowed a card in the
            -- last build. A dismissal for a card the engine no longer produces
            -- is stored but not active, and reporting only one of the two made
            -- the window and the command contradict each other.
            local stored = ns.Config:DismissedCount(Api:ServerTime())
            local active = (ns.ActionEngine.meta or {}).hiddenByDismissal or 0
            if stored == 0 then
                Api:Print("скрытых советов нет")
            else
                Api:Print("скрыто записей: " .. stored
                    .. ", из них прячут совет прямо сейчас: " .. active
                    .. ". Вернуть все — /fp show")
            end
            return
        end
        if msg == "reset" then
            ns.Config:SaveFrame("CENTER", "CENTER", 0, 0, 720, 560)
            ns.Config:SetScale(1.0)
            ns.MainFrame:ApplyPosition()
            ns.MainFrame:ApplyScale()
            -- И панель, и стрелка: «сбросить» для игрока означает «поставь всё
            -- на место», а не «поставь на место ровно то окно, про которое я
            -- сейчас думаю». Раньше панель и стрелка оставались там, куда
            -- уехали, и команда выглядела наполовину сработавшей.
            ns.StepPanel:ResetPosition()
            if ns.Arrow then ns.Arrow:ResetPosition() end
            Api:Print("окно, панель и стрелка поставлены на место,"
                .. " масштаб окна — обычный")
            return
        end
        if msg == "api" then
            -- Словами: состояние приходило кодом («ok», «partial»), а нехватки -
            -- внутренними ключами. Имена функций остаются в файле диагностики.
            local STATE = { ok = "всё на месте", none = "игра этого не сообщает" }
            for _, group in ipairs(Api:Report()) do
                Api:Print(group.group .. ": " .. (STATE[group.state]
                    or ("частично — не хватает " .. #group.missing .. " из "
                        .. (#group.missing + #group.ok))))
            end
            return
        end
        if msg == "diag" or msg == "диаг" or msg == "диагностика" then
            ns.Diag:Trim()
            ns.Diag:Print()
            return
        end
        if msg == "diag full" or msg == "diag all" then
            ns.Diag:Trim()
            ns.Diag:PrintFull()
            return
        end
        if msg == "diag reset" then
            local store = _G.FOREVERPILOT_DIAG
            if type(store) == "table" then
                store.sessions = {}
                ns.Diag.session = nil
                ns.Diag:Bind(store)
                ns.Diag:CaptureEnvironment()
                Api:Print("диагностика очищена, собираю заново")
            end
            return
        end
        for _, key in ipairs(ns.PROFILE_ORDER) do
            if msg == key:lower() or msg == U.lower(ns.PROFILE_LABEL[key] or "") then
                ns.Config:SetProfile(key)
                ns.MainFrame:Rebuild(true)
                Api:Print("профиль: " .. ns.PROFILE_LABEL[key])
                return
            end
        end

        Api:Print("команды: /fp • now • buy (покупки) • config • scan • reset • api"
            .. " • panel (убрать/вернуть панель шага)"
            .. " • undo (вернуть последнее скрытое) • show (вернуть все)"
            .. " • hidden • diag • diag full • diag reset"
            .. " • сила / прокачка / экономия / заработок")
    end
end

-- Addon compartment, when the client has one.
_G.ForeverPilot_OnAddonCompartmentClick = function()
    if ns.MainFrame then ns.MainFrame:Toggle() end
end

return Main
