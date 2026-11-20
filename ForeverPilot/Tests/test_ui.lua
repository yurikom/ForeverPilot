-- ForeverPilot / Tests/test_ui.lua
--
-- Smoke test for the UI. It cannot prove the window LOOKS right - only running
-- the game can do that - but it does prove every UI file loads, every tab
-- builds, every tab renders against real-shaped data, and every card action
-- runs without touching a nil. In practice that is where almost all addon
-- load errors come from: a global that does not exist on this client, or a
-- method called on something that came back nil.
--
-- The frame stub answers any method call and records it, so a method the addon
-- invents by mistake is caught by the allow-list check at the end rather than
-- silently passing.
local H = ...

return function()

-- Frame stub ------------------------------------------------------------

-- Every method the addon is allowed to call on a frame or font string. If the
-- addon calls something not on this list, it is either a typo or an API we
-- have not thought about - either way we want to know.
local KNOWN_METHODS = {}
for _, name in ipairs({
    "SetPoint", "SetAllPoints", "ClearAllPoints", "GetPoint", "SetSize",
    "SetWidth", "SetHeight", "GetWidth", "GetHeight", "Show", "Hide",
    "GetLeft", "GetRight", "GetTop", "GetBottom", "GetCenter", "GetRect",
    "GetEffectiveScale", "SetRotation", "GetRotation", "IsMouseOver",
    "IsShown", "IsVisible", "SetParent", "GetParent", "SetScript", "GetScript",
    "HookScript", "RegisterEvent", "UnregisterEvent", "RegisterForDrag",
    "RegisterForClicks", "EnableMouse", "EnableKeyboard", "SetMovable",
    "SetResizable", "SetResizeBounds", "SetMinResize", "StartMoving",
    "StartSizing", "StopMovingOrSizing", "SetFrameStrata", "SetToplevel",
    "SetScale", "GetScale", "SetPropagateKeyboardInput", "SetClampedToScreen",
    "CreateTexture", "CreateFontString", "SetTexture", "SetColorTexture",
    "SetTexCoord", "SetVertexColor", "SetDesaturated", "SetNormalTexture",
    "SetHighlightTexture", "SetPushedTexture", "SetDisabledTexture",
    "SetText", "GetText", "SetFontObject", "SetJustifyH", "SetJustifyV",
    "SetTextColor", "SetWordWrap", "GetStringWidth", "GetStringHeight",
    "SetMaxLines", "SetSpacing", "SetAlpha", "GetAlpha",
    "SetMinMaxValues", "GetMinMaxValues", "SetValue", "GetValue",
    "SetValueStep", "SetObeyStepOnDrag", "SetOrientation", "SetThumbTexture",
    "SetScrollChild", "GetScrollChild", "SetVerticalScroll", "UpdateScrollChildRect",
    "SetAutoFocus", "SetTextInsets", "ClearFocus", "SetFocus", "SetNumeric",
    "SetMultiLine", "Insert", "SetCursorPosition", "HighlightText",
    "SetOwner", "ClearLines", "AddLine", "AddDoubleLine", "SetHyperlink",
    "Raise", "Lower", "SetID", "GetID", "SetChecked", "GetChecked",
    "SetLabel", "SetEnabledState", "SetSelected", "Set", "SetBackdrop",
    "SetBackdropColor", "SetBackdropBorderColor", "GetObjectType", "GetName",
    "Click", "Disable", "Enable", "IsEnabled", "SetHitRectInsets",
    "SetMask", "SetMaskTexture", "SetFrameLevel", "GetFrameLevel",
    "SetDrawLayer", "SetBlendMode", "SetIgnoreParentScale", "SetClipsChildren",
}) do KNOWN_METHODS[name] = true end

local unknownCalls, callLog = {}, {}

local frameMT
local function newFrame(frameType, name, parent)
    local f = {
        __type = frameType or "Frame",
        __name = name,
        __parent = parent,
        __scripts = {},
        __shown = false,
        __width = 600,
        __height = 400,
        __text = "",
    }
    return setmetatable(f, frameMT)
end

-- Game fields (not methods) the addon is allowed to read off a frame. Anything
-- else that is not a known method comes back nil, exactly like a real field the
-- addon has not assigned yet - which is what makes `if frame.fpBG then` work.
local KNOWN_FIELDS = { ScrollBar = true, ScrollFrame = true }

frameMT = {
    __index = function(t, key)
        if type(key) ~= "string" then return nil end
        if key:sub(1, 2) == "__" then return nil end

        if not KNOWN_METHODS[key] then
            -- Not a method we model. If it looks like a method name the addon
            -- expects from the game, flag it; otherwise treat it as an
            -- unassigned field and return nil.
            if not KNOWN_FIELDS[key] then
                local looksLikeMethod = key:match("^[SGI][ec]t%u") or key:match("^Is%u")
                    or key:match("^Register%u") or key:match("^Create%u")
                    or key:match("^Start%u") or key:match("^Stop%u")
                if looksLikeMethod then
                    unknownCalls[key] = (unknownCalls[key] or 0) + 1
                end
            end
            return nil
        end

        local fn
        if key == "CreateTexture" then
            -- Слой запоминается: «рамка поверх иконки» - это и есть слой, и
            -- проверить это иначе нельзя.
            fn = function(self, name, layer)
                local t = newFrame("Texture", name, self)
                t.__layer = layer
                return t
            end
        elseif key == "CreateFontString" then
            fn = function(self) return newFrame("FontString", nil, self) end
        elseif key == "SetScript" then
            fn = function(self, which, handler) self.__scripts[which] = handler end
        elseif key == "GetScript" then
            fn = function(self, which) return self.__scripts[which] end
        elseif key == "Show" then
            fn = function(self) self.__shown = true end
        elseif key == "Hide" then
            fn = function(self) self.__shown = false end
        elseif key == "IsShown" or key == "IsVisible" then
            fn = function(self) return self.__shown end
        elseif key == "SetWidth" then
            fn = function(self, v) self.__width = v end
        elseif key == "SetHeight" then
            fn = function(self, v) self.__height = v end
        elseif key == "SetSize" then
            fn = function(self, w, h)
                self.__width, self.__height = w, h
                self.__size = { w, h }
            end
        -- Разметка кнопки у миникарты проверяется по этим записям: размеры,
        -- точки привязки, пути текстур, обрезка, слои и уровень фрейма. Без них
        -- съехавшая на четверть размера рамка выглядела для теста нормально.
        elseif key == "SetPoint" then
            fn = function(self, ...)
                self.__points = self.__points or {}
                self.__points[#self.__points + 1] = { ... }
            end
        elseif key == "ClearAllPoints" then
            fn = function(self) self.__points = {} end
        elseif key == "SetTexture" then
            fn = function(self, v) self.__texture = v end
        elseif key == "SetTexCoord" then
            fn = function(self, ...) self.__texCoord = { ... } end
        elseif key == "SetMask" or key == "SetMaskTexture" then
            fn = function(self, v) self.__mask = v end
        elseif key == "SetNormalTexture" then
            fn = function(self, v) self.__normal = v end
        elseif key == "SetHighlightTexture" then
            fn = function(self, v) self.__highlight = v end
        elseif key == "SetFrameLevel" then
            fn = function(self, v) self.__frameLevel = v end
        elseif key == "GetFrameLevel" then
            fn = function(self) return self.__frameLevel or 1 end
        elseif key == "SetFrameStrata" then
            fn = function(self, v) self.__strata = v end
        elseif key == "RegisterForDrag" then
            fn = function(self, ...) self.__dragButtons = table.concat({ ... }, ",") end
        elseif key == "GetWidth" then
            fn = function(self) return self.__width or 600 end
        elseif key == "GetHeight" then
            fn = function(self) return self.__height or 400 end
        elseif key == "SetText" then
            fn = function(self, v) self.__text = tostring(v or "") end
        elseif key == "GetText" then
            fn = function(self) return self.__text end
        elseif key == "GetStringWidth" then
            fn = function(self) return #(self.__text or "") * 6 end
        elseif key == "GetStringHeight" then
            fn = function(self) return 12 end
        elseif key == "GetPoint" then
            fn = function(self) return "CENTER", nil, "CENTER", 0, 0 end
        elseif key == "GetLeft" then
            fn = function(self) return self.__left or 100 end
        elseif key == "GetBottom" then
            fn = function(self) return self.__bottom or 200 end
        elseif key == "GetRight" then
            fn = function(self) return (self.__left or 100) + (self.__width or 0) end
        elseif key == "GetTop" then
            fn = function(self) return (self.__bottom or 200) + (self.__height or 0) end
        elseif key == "GetEffectiveScale" then
            fn = function() return 1 end
        elseif key == "SetRotation" then
            fn = function(self, r) self.__rotation = r end
        elseif key == "GetRotation" then
            fn = function(self) return self.__rotation or 0 end
        elseif key == "GetParent" then
            fn = function(self) return self.__parent end
        elseif key == "SetParent" then
            fn = function(self, p) self.__parent = p end
        elseif key == "GetValue" then
            fn = function(self) return self.__value or 1 end
        elseif key == "SetValue" then
            fn = function(self, v) self.__value = v end
        elseif key == "GetScrollChild" then
            fn = function(self) return self.__scrollChild end
        elseif key == "SetScrollChild" then
            fn = function(self, c) self.__scrollChild = c end
        elseif key == "GetName" then
            fn = function(self) return self.__name end
        elseif key == "GetObjectType" then
            fn = function(self) return self.__type end
        else
            fn = function() return nil end
        end
        -- Cache so repeat calls are cheap and the unknown counter stays honest.
        t[key] = fn
        return fn
    end,
}

-- Load the whole addon, UI included ------------------------------------

local UI_FILES = {
    "UI/Widgets.lua", "UI/Arrow.lua", "UI/Card.lua", "UI/StepPanel.lua",
    "UI/TabNow.lua", "UI/TabCharacter.lua", "UI/TabCraft.lua",
    "UI/TabSettings.lua", "UI/MinimapButton.lua", "UI/MainFrame.lua",
}

local function loadWithUI()
    local env = H.load()
    local ns, G, sandbox = env.ns, env.G, env.sandbox

    G.UIParent = newFrame("Frame", "UIParent")
    G.Minimap = newFrame("Frame", "Minimap")
    G.GameTooltip = newFrame("GameTooltip", "GameTooltip")
    G.UISpecialFrames = {}
    G.CreateFrame = function(frameType, name, parent, template)
        local f = newFrame(frameType, name, parent)
        callLog[#callLog + 1] = (frameType or "?") .. (template and ("/" .. template) or "")
        if name then G[name] = f end
        return f
    end
    G.C_Timer = {
        After = function(_, fn) env.pendingTimers = env.pendingTimers or {}
            table.insert(env.pendingTimers, fn) end,
        NewTicker = function(_, fn)
            env.pendingTickers = env.pendingTickers or {}
            table.insert(env.pendingTickers, fn)
            return { Cancel = function() end }
        end,
    }
    G.GetTime = function() return H.clock end

    for _, rel in ipairs(UI_FILES) do
        local path = H.ROOT .. "/" .. rel
        local chunk, err = loadfile(path)
        if not chunk then error("не загрузился " .. rel .. ": " .. tostring(err)) end
        setfenv(chunk, sandbox)
        local ok, loadErr = pcall(chunk, "ForeverPilot", ns)
        if not ok then error("ошибка загрузки " .. rel .. ": " .. tostring(loadErr)) end
    end
    return env
end

-- A world with something of every card kind, so every tab has data.
local function populate(env)
    local ns = env.ns
    env.player.level = 26
    env.player.classFile = "MAGE"
    env.player.className = "Маг"
    env.player.name = "Гендольф"
    env.spec = "Тайная магия"
    env.money = 25081

    H.item(env, 2589, { name = "Льняная ткань", sellPrice = 5 })
    H.item(env, 11137, { name = "Магическая пыль", sellPrice = 120 })
    H.item(env, 100, { name = "Старый капюшон", equipLoc = "INVTYPE_HEAD",
        reqLevel = 20, classID = 4, subclassID = 1, sellPrice = 50 })
    H.item(env, 101, { name = "Новый капюшон", equipLoc = "INVTYPE_HEAD",
        reqLevel = 24, classID = 4, subclassID = 1, sellPrice = 300 })
    H.item(env, 110, { name = "Наручи", equipLoc = "INVTYPE_WRIST",
        reqLevel = 20, classID = 4, subclassID = 1 })
    H.item(env, 9000, { name = "Рваная шкура", sellPrice = 70, quality = 0 })
    env.stats[100] = { ITEM_MOD_INTELLECT_SHORT = 3 }
    env.stats[101] = { ITEM_MOD_INTELLECT_SHORT = 14 }
    env.prices[2589] = 50
    env.prices[11137] = 900
    env.prices[101] = 2500
    env.equipped.HEAD = { itemID = 100 }
    env.equipped.WRIST = { itemID = 110 }
    env.bags[2589] = 6
    env.bags[9000] = 8
    env.bank = { [11137] = 2 }

    -- A world position and a merchant in front of us, so the navigation and
    -- places paths are exercised rather than skipped.
    env.playerMap = { mapID = 1434, x = 0.34, y = 0.76, zone = "Тернистая долина" }
    env.facing = 0
    env.worldSizes[1434] = { width = 4000, height = 2600, name = "Тернистая долина" }
    env.npcUnit = { id = 1313, name = "Торговец Кварц" }
    env.merchantItems = {
        { itemID = 2589, name = "Льняная ткань", price = 100, stack = 5 },
    }

    H.profession(env, "Tailoring", 180, 225, {
        H.recipe { id = 1, name = "Новый капюшон", output = 101, outputQty = 1,
                   reagents = { { itemID = 2589, qty = 6 } }, diff = "optimal",
                   category = "Капюшоны", categoryID = 1 },
    })
    H.profession(env, "Enchanting", 225, 225, {
        H.recipe { id = 2, name = "Чары для браслетов: интеллект III",
                   reagents = { { itemID = 11137, qty = 1 } }, learned = true,
                   category = "Чары для наручей", categoryID = 10, diff = "medium" },
    })
    H.build(env)
    return env
end

-- Tests ----------------------------------------------------------------

H.suite("UI: все файлы загружаются")
local env
do
    local ok, result = pcall(loadWithUI)
    H.ok(ok, "семь файлов интерфейса загрузились без ошибок", tostring(result))
    if not ok then return end
    env = result
    local ns = env.ns
    for _, name in ipairs({ "Widgets", "Arrow", "Card", "StepPanel", "TabNow",
                            "TabCharacter", "TabCraft", "TabSettings",
                            "MainFrame" }) do
        H.ok(ns[name] ~= nil, "модуль " .. name .. " зарегистрирован")
    end
end

if not env then return end
local ns = env.ns
populate(env)

H.suite("UI: окно собирается")
do
    local ok, err = pcall(function() ns.MainFrame:Build() end)
    H.ok(ok, "MainFrame:Build() прошёл", tostring(err))
    H.ok(ns.MainFrame.frame ~= nil, "фрейм создан")
    H.ok(ns.MainFrame.host ~= nil, "контейнер вкладок создан")
    local tabs = 0
    for _ in pairs(ns.MainFrame.tabButtons or {}) do tabs = tabs + 1 end
    H.eq(tabs, 4, "ровно четыре вкладки, не пять")
end

H.suite("UI: каждая вкладка строится и рисуется")
do
    for _, def in ipairs(ns.MainFrame.TABS) do
        local mod = ns[def.module]
        H.ok(mod ~= nil, def.label .. ": модуль есть")
        if mod then
            local ok, err = pcall(function() return mod:Build(ns.MainFrame.host) end)
            H.ok(ok, def.label .. ": Build()", tostring(err))
            local ok2, err2 = pcall(function() if mod.OnShow then mod:OnShow() end end)
            H.ok(ok2, def.label .. ": OnShow()", tostring(err2))
            local ok3, err3 = pcall(function() if mod.Render then mod:Render() end end)
            H.ok(ok3, def.label .. ": Render()", tostring(err3))
        end
    end
end

H.suite("UI: вкладка «Сейчас» открыта по умолчанию")
do
    H.eq(ns.Config:Get().tab, "NOW", "по умолчанию NOW")
    local ok, err = pcall(function() ns.MainFrame:Select("NOW") end)
    H.ok(ok, "Select(NOW)", tostring(err))
    H.eq(ns.MainFrame.activeTab, "NOW", "активна вкладка «Сейчас»")
    H.ok(ns.TabNow.profileChips ~= nil, "кнопки профилей созданы")
    local profiles = 0
    for _ in pairs(ns.TabNow.profileChips) do profiles = profiles + 1 end
    H.eq(profiles, 4, "четыре профиля приоритетов НАД списком")
    local chips = 0
    for _ in pairs(ns.TabNow.filterChips) do chips = chips + 1 end
    H.eq(chips, #ns.CHIP_ORDER, #ns.CHIP_ORDER .. " чипов-фильтров")
end

H.suite("UI: переключение всех вкладок и профилей не падает")
do
    for _, def in ipairs(ns.MainFrame.TABS) do
        local ok, err = pcall(function() ns.MainFrame:Select(def.key) end)
        H.ok(ok, "переход на «" .. def.label .. "»", tostring(err))
    end
    ns.MainFrame:Select("NOW")
    for _, profile in ipairs(ns.PROFILE_ORDER) do
        local chip = ns.TabNow.profileChips[profile]
        local handler = chip.__scripts and chip.__scripts.OnClick
        H.ok(handler ~= nil, "у кнопки «" .. ns.PROFILE_LABEL[profile] .. "» есть обработчик")
        if handler then
            local ok, err = pcall(handler, chip)
            H.ok(ok, "клик по «" .. ns.PROFILE_LABEL[profile] .. "»", tostring(err))
            H.eq(ns.Config:Profile(), profile, "профиль переключился")
        end
    end
    for _, key in ipairs(ns.CHIP_ORDER) do
        local chip = ns.TabNow.filterChips[key]
        local handler = chip.__scripts and chip.__scripts.OnClick
        if handler then
            local ok, err = pcall(handler, chip)
            H.ok(ok, "клик по чипу «" .. ns.CHIP_LABEL[key] .. "»", tostring(err))
            H.eq(ns.Config:Chip(), key, "фильтр переключился")
        end
    end
    ns.Config:SetChip(ns.CHIP.ALL)
end

H.suite("UI: карточки заполняются")
do
    ns.MainFrame:Select("NOW")
    local cards = ns.ActionEngine.cards
    H.ok(#cards > 0, #cards .. " карточек для отрисовки")
    local filled = 0
    for i, card in ipairs(cards) do
        local frame = ns.Card.Acquire(ns.TabNow.content, i)
        local ok, err = pcall(function() ns.Card.Fill(frame, card) end)
        H.ok(ok, "карточка " .. i .. " («" .. ns.Util.truncate(card.title, 30) .. "»)",
            tostring(err))
        if ok then
            filled = filled + 1
            -- The three lines must actually have reached the font strings.
            H.ok(frame.title:GetText() ~= "", "   строка 1 заполнена")
            H.ok(frame.why:GetText() ~= "", "   строка 2 заполнена")
            H.ok(frame.need:GetText() ~= "", "   строка 3 заполнена")
            H.ok(frame.benefit:GetText() ~= "", "   выгода справа заполнена")
        end
    end
    H.eq(filled, #cards, "все карточки отрисованы")
end

H.suite("UI: «Показать предмет» не прячет совет")
do
    -- Любое действие, которого UI не знает, проваливалось в ветку «понятно» и
    -- убирало карточку на час. Совет «надень своё» нажимают именно чтобы
    -- посмотреть на вещь, и он обязан остаться на экране.
    local card = {
        kind = ns.KIND.EQUIP, key = "equip:MAINHAND:900123", itemID = 900123,
        title = "Надеть: Мерцающий посох",
        action = { kind = "showItem", itemID = 900123 },
    }
    local ok, err = pcall(function() ns.Card.ActivateInner(card) end)
    H.ok(ok, "действие выполняется без ошибки", tostring(err))
    H.eq(ns.Config:IsDismissed(card.key, ns.Api:ServerTime()), false,
        "карточка не скрыта")
end

-- «ПОКАЗАТЬ ПРЕДМЕТ» ДОЛЖНА ПОКАЗЫВАТЬ ПРЕДМЕТ ===========================
--
-- Живая жалоба: игрок жал кнопку на карточках Благосклонности, а в чат падало
-- «Жемчужные перчатки — наденьте сами: экипировкой я не управляю», десяток
-- одинаковых строк подряд. Две ошибки в одной кнопке: ответ не про то, о чём
-- просили (просили ПОКАЗАТЬ), и повтор одного и того же сообщения.
--
-- Текст про «наденьте сами» был написан для совета «надень своё», а действие
-- showItem стоит на семи разных ветках - и всем семи отвечало про экипировку.

H.suite("UI: «Показать предмет» выводит ссылку на предмет, а не совет надеть")
do
    local said = {}
    ns.Api:InjectPrinter(function(line) said[#said + 1] = line end)
    ns.Api.lastSaid = nil
    local link = "|cnIQ2:|Hitem:253921::::::::27:1482:::::::::|h[Жемчужные перчатки]|h|r"
    local card = {
        kind = ns.KIND.FAVOR, key = "favor:buy:253921", itemID = 253921,
        title = "За Благосклонность: Жемчужные перчатки", link = link,
        action = { kind = "showItem", itemID = 253921, link = link },
    }
    ns.Card.ActivateInner(card)
    H.eq(#said, 1, "сказано ровно один раз")
    local msg = said[1] or ""
    H.ok(ns.Util.contains(msg, "Hitem:253921"),
        "и в чат ушла ССЫЛКА на предмет, по которой видно характеристики: " .. msg)
    H.eq(ns.Util.contains(msg, "наденьте сами"), false,
        "и ни слова про «наденьте сами» — кнопка не про это: " .. msg)
    H.eq(ns.Util.contains(msg, "экипировкой я не управляю"), false,
        "и про управление экипировкой тоже")
end

H.suite("UI: показать нечем — сказано именно это, один раз")
do
    local said = {}
    ns.Api:InjectPrinter(function(line) said[#said + 1] = line end)
    ns.Api.lastSaid = nil
    local card = {
        kind = ns.KIND.FAVOR, key = "favor:buy:999999", itemID = 999999,
        title = "За Благосклонность: что-то",
        action = { kind = "showItem", itemID = 999999 },
    }
    ns.Card.ActivateInner(card)
    H.eq(#said, 1, "сказано один раз")
    local msg = said[1] or ""
    H.ok(ns.Util.contains(msg, "не") , "и это отказ, а не выдумка: " .. msg)
    H.eq(ns.Util.contains(msg, "наденьте сами"), false,
        "без текста про экипировку")
end

H.suite("UI: одно и то же сообщение подряд не повторяется")
do
    -- Игрок нажал кнопку десять раз и получил десять одинаковых строк. Второй
    -- раз подряд одно и то же печатать незачем: это не информация, это шум.
    local said = {}
    ns.Api:InjectPrinter(function(line) said[#said + 1] = line end)
    ns.Api.lastSaid = nil
    ns.Api:Print("одно и то же")
    ns.Api:Print("одно и то же")
    ns.Api:Print("одно и то же")
    H.eq(#said, 1, "три одинаковых подряд дали одну строку")
    ns.Api:Print("другое")
    H.eq(#said, 2, "а другое сообщение печатается")
    ns.Api:Print("одно и то же")
    H.eq(#said, 3, "и первое, вернувшись после другого, печатается снова")
end

H.suite("UI: подряд нажатая «Показать предмет» не забивает чат")
do
    local said = {}
    ns.Api:InjectPrinter(function(line) said[#said + 1] = line end)
    ns.Api.lastSaid = nil
    local link = "|cnIQ2:|Hitem:253897::::::::27:1482:::::::::|h[Жемчужные сапоги]|h|r"
    local card = {
        kind = ns.KIND.FAVOR, key = "favor:buy:253897", itemID = 253897,
        title = "За Благосклонность: Жемчужные сапоги", link = link,
        action = { kind = "showItem", itemID = 253897, link = link },
    }
    for _ = 1, 10 do ns.Card.ActivateInner(card) end
    H.eq(#said, 1, "десять нажатий — одна строка в чате, а не десять")
end

H.suite("UI: действия карточек выполняются")
do
    local kinds = {}
    for _, card in ipairs(ns.ActionEngine.cards) do
        if not kinds[card.action.kind] then
            kinds[card.action.kind] = true
            local ok, err = pcall(function() ns.Card.Activate(card) end)
            H.ok(ok, "действие «" .. card.action.kind .. "»", tostring(err))
        end
    end
    -- Right-click dismissal.
    local target
    for _, card in ipairs(ns.ActionEngine.cards) do
        if not card.blocking then target = card; break end
    end
    if target then
        -- Скрытие теперь одно - в два щелчка: первый спрашивает, второй прячет.
        ns.Dismissal:Disarm()
        local ok, err = pcall(function()
            ns.Card.RequestDismiss(target)
            ns.Card.RequestDismiss(target)
        end)
        H.ok(ok, "скрытие карточки", tostring(err))
        H.eq(ns.Config:IsDismissed(target.key, env.Api:ServerTime()), true,
            "после двух правых щелчков карточка скрыта")
    end
    -- A blocking setup card must refuse to be dismissed.
    local blocking
    ns.RecipeBook.byProfession = {}
    ns.RecipeBook:Reindex()
    H.build(env)
    for _, card in ipairs(ns.ActionEngine.cards) do
        if card.blocking then blocking = card end
    end
    if blocking then
        ns.Dismissal:Disarm()
        ns.Card.RequestDismiss(blocking)
        ns.Card.RequestDismiss(blocking)
        H.eq(ns.Config:IsDismissed(blocking.key, env.Api:ServerTime()), false,
            "обязательную карточку скрыть нельзя")
    end
    populate(env)
end

H.suite("UI: пустой экран всё равно что-то говорит")
do
    local saved = ns.RecipeBook.byProfession
    ns.RecipeBook.byProfession = {}
    ns.RecipeBook:Reindex()
    H.build(env)
    ns.MainFrame:Select("NOW")
    local ok, err = pcall(function() ns.TabNow:Render() end)
    H.ok(ok, "отрисовка без рецептов", tostring(err))
    -- With no recipes the engine still emits setup cards, so the list is not
    -- empty; force the empty branch directly to check its text.
    local title, body = ns.TabNow:EmptyReason(ns.ActionEngine.meta, ns.CHIP.ALL)
    H.ok(title and title ~= "", "у пустого состояния есть заголовок: " .. tostring(title))
    H.ok(body and #body > 20, "и внятное объяснение")
    H.ok(body:find("профессии") or body:find("рецепт"),
        "объяснение говорит про рецепты/профессии")
    for _, chip in ipairs(ns.CHIP_ORDER) do
        local t, b = ns.TabNow:EmptyReason(ns.ActionEngine.meta, chip)
        H.ok(t and t ~= "" and b and b ~= "", "для фильтра «"
            .. ns.CHIP_LABEL[chip] .. "» тоже есть текст")
    end
    ns.RecipeBook.byProfession = saved
    ns.RecipeBook:Reindex()
    H.build(env)
end

-- Ноль в счётчике и «советы есть» одновременно - недопустимо -----------
--
-- На экране игрока статус показывал «0 советов», а тело окна при выбранном
-- фильтре «Золото» писало «Советы есть, но не этого типа». Старый EmptyReason
-- выдавал эту фразу по единственному условию chip ~= ALL, вообще не глядя на
-- число карточек (UI/TabNow.lua, ветка `if chip ~= ns.CHIP.ALL then`).
H.suite("UI: пустое состояние не врёт про наличие советов")
do
    -- Случай A: советы есть, фильтр не тот.
    local metaA = { builtAt = 1794800000, learnedRecipes = 265, branches = {} }
    local tA, bA = ns.TabNow:EmptyReason(metaA, ns.CHIP.GOLD, 7)
    H.ok((tA .. " " .. bA):find("7") ~= nil,
        "сказано, сколько советов есть: " .. tostring(bA))
    H.ok(bA:find("Золото") ~= nil, "и назван фильтр, который их не пускает")
    H.ok(bA:find("Всё") ~= nil, "и куда нажать")

    -- Случай B: советов нет вообще - фраза «советы есть» запрещена при любом
    -- фильтре и любом профиле.
    local metaB = {
        builtAt = 1794800000, learnedRecipes = 265,
        branches = {
            { key = "gear", label = "Экипировка", count = 0, reason = "нечего сравнивать" },
            { key = "profit", label = "Крафт на продажу", count = 0,
              reason = "ни один рецепт не продаётся дороже материалов" },
        },
        priceSources = { auctionatorAvailable = true },
    }
    for _, chip in ipairs(ns.CHIP_ORDER) do
        local t, b = ns.TabNow:EmptyReason(metaB, chip, 0)
        local text = t .. " " .. b
        H.ok(text:find("Советы есть") == nil and text:find("Советов у меня") == nil,
            "фильтр «" .. ns.CHIP_LABEL[chip] .. "»: при нуле не обещаем советов",
            text)
        H.ok(text:find("не этого типа") == nil,
            "фильтр «" .. ns.CHIP_LABEL[chip] .. "»: без «не этого типа»")
    end
    -- И перечислено, чего не хватает, по ветке.
    local _, bB = ns.TabNow:EmptyReason(metaB, ns.CHIP.ALL, 0)
    H.ok(bB:find("Экипировка") ~= nil, "названа ветка экипировки")
    H.ok(bB:find("Крафт на продажу") ~= nil, "названа ветка крафта на продажу")
    H.ok(bB:find("нечего сравнивать") ~= nil, "и её причина")
    H.ok(bB:find("дороже материалов") ~= nil, "и причина второй ветки")

    -- Случай B2: нуль из-за скрывашек - это отдельная причина с выходом.
    local metaB2 = { builtAt = 1794800000, learnedRecipes = 265,
                     branches = {}, hiddenByDismissal = 21 }
    local tB2, bB2 = ns.TabNow:EmptyReason(metaB2, ns.CHIP.GOLD, 0)
    H.eq(tB2, "Все советы скрыты вами",
        "заголовок называет причину сразу, до чтения текста")
    H.ok(bB2:find("21") ~= nil, "названо число скрытых: " .. tostring(bB2))
    H.ok(bB2:find("/fp show") ~= nil, "и команда возврата")
    H.ok((tB2 .. " " .. bB2):find("не этого типа") == nil,
        "и никакого «советы есть, но не этого типа»")
    -- Скрывашки важнее перечня ветвей: сначала то, что игрок может отменить.
    H.ok(bB2:find("Экипировка") == nil,
        "и перечень ветвей не мешается — причина одна и она названа")

    -- Случай C: данных ещё нет.
    local tC, bC = ns.TabNow:EmptyReason({}, ns.CHIP.ALL, 0)
    H.ok(tC:find("не собраны") ~= nil, "сказано, что данные ещё не собраны: " .. tostring(tC))
    local tC2 = ns.TabNow:EmptyReason({ error = "нет снимка персонажа" }, ns.CHIP.ALL, 0)
    H.ok(tC2:find("не собраны") ~= nil, "и при сорванном пересчёте тоже")
    local tC3 = ns.TabNow:EmptyReason(
        { builtAt = 1, learnedRecipes = 0, branches = {} }, ns.CHIP.ALL, 0)
    H.ok(tC3:find("не собраны") ~= nil, "и когда рецептов ноль")

    -- Три случая дают три РАЗНЫХ заголовка: иначе различать нечего.
    H.ok(tA ~= tC and tB2 ~= tC and tA ~= tB2,
        "у трёх случаев три разных заголовка: «" .. tA .. "» / «" .. tB2
        .. "» / «" .. tC .. "»")
end

-- Короткий список не оставляет полокна пустым -------------------------
H.suite("UI: под коротким списком написано, почему он короткий")
do
    ns.Config:ClearDismissed()
    H.build(env)
    ns.Config:SetChip(ns.CHIP.ALL)
    ns.MainFrame:Select("NOW")
    -- Высокое окно: места под заметку заведомо хватает. Низкое проверяется
    -- отдельно ниже - там заметка обязана уйти, а не лезть за край.
    --
    -- ВЫСОТА ВЗЯТА С ЗАПАСОМ НА РОСТ СПИСКА. Было 900, и этого хватало, пока
    -- веток было семь; с появлением экономических веток карточек стало больше,
    -- место под заметку кончилось, и проверка начала падать на правильном коде.
    -- Проверяется здесь «заметка показывается, когда есть место», а не «900
    -- пикселей достаточно», поэтому запас большой.
    ns.TabNow.scroll.__height = 4000
    local ok, err = pcall(function() ns.TabNow:Render() end)
    H.ok(ok, "отрисовка прошла", tostring(err))

    local savedBranches = ns.ActionEngine.meta.branches
    local savedPrices = ns.ActionEngine.meta.priceSources
    local savedHidden = ns.ActionEngine.meta.hiddenByDismissal
    ns.ActionEngine.meta.priceSources = { auctionatorAvailable = true }
    ns.ActionEngine.meta.hiddenByDismissal = 0

    -- Одна ветка молчит, другая выдала советы: объясняем только молчащую.
    ns.ActionEngine.meta.branches = {
        { key = "gear", label = "Экипировка", count = 2 },
        { key = "enchant", label = "Чары", count = 0,
          reason = "выученных формул чар нет" },
    }
    local gaps = ns.TabNow:BranchGaps(ns.ActionEngine.meta)
    H.eq(#gaps, 1, "объяснена ровно одна ветка — молчащая")
    H.ok(gaps[1]:find("Чары") ~= nil, "названа она: " .. gaps[1])
    H.ok(gaps[1]:find("формул чар нет") ~= nil, "и её причина, записанная сборкой")
    H.ok(gaps[1]:find("Экипировка") == nil, "про работающую ветку ничего не пишем")

    ns.TabNow:Render()
    H.ok(ns.TabNow.note ~= nil, "панель-заметка создана")
    H.eq(ns.TabNow.note.__shown, true,
        "и показана под карточками, пока в окне есть место")
    H.ok((ns.TabNow.note.body:GetText() or ""):find("формул чар нет") ~= nil,
        "в ней написана причина: " .. tostring(ns.TabNow.note.body:GetText()))

    -- Ветка без записанной причины честно помечается дефектом, а не молчит.
    ns.ActionEngine.meta.branches = {
        { key = "buy", label = "Покупки", count = 0 },
    }
    local gapsNoReason = ns.TabNow:BranchGaps(ns.ActionEngine.meta)
    H.eq(#gapsNoReason, 1, "ветка без причины всё равно в списке")
    H.ok(gapsNoReason[1]:find("дефект") ~= nil,
        "и помечена дефектом диагностики: " .. gapsNoReason[1])

    -- Пустых веток нет - заметка прячется.
    ns.ActionEngine.meta.branches = {
        { key = "gear", label = "Экипировка", count = 2 },
    }
    ns.TabNow:Render()
    H.eq(#ns.TabNow:BranchGaps(ns.ActionEngine.meta), 0, "объяснять нечего")
    H.eq(ns.TabNow.note.__shown, false, "и заметка скрыта")

    -- Скрытые карточки попадают в тот же список.
    ns.ActionEngine.meta.hiddenByDismissal = 4
    local gapsHidden = ns.TabNow:BranchGaps(ns.ActionEngine.meta)
    H.eq(#gapsHidden, 1, "скрытое объяснено отдельной строкой")
    H.ok(gapsHidden[1]:find("/fp show") ~= nil, "с командой возврата: " .. gapsHidden[1])
    ns.ActionEngine.meta.hiddenByDismissal = 0

    ns.ActionEngine.meta.branches = {
        { key = "enchant", label = "Чары", count = 0, reason = "формул нет" },
    }

    -- Низкое окно: карточки занимают всё место, заметка не должна вылезать
    -- за край и отжимать список.
    ns.TabNow.scroll.__height = 120
    ns.TabNow:Render()
    H.eq(ns.TabNow.note.__shown, false, "в тесном окне заметка не показывается")
    ns.TabNow.scroll.__height = nil

    ns.ActionEngine.meta.branches = savedBranches
    ns.ActionEngine.meta.priceSources = savedPrices
    ns.ActionEngine.meta.hiddenByDismissal = savedHidden
end

-- Сквозная проверка на живом движке: счётчик статуса и текст окна -------
H.suite("UI: счётчик и текст окна не противоречат друг другу")
do
    for _, chip in ipairs(ns.CHIP_ORDER) do
        ns.Config:SetChip(chip)
        ns.MainFrame:Select("NOW")
        local total = #(ns.ActionEngine.cards or {})
        local shown = #ns.ActionEngine:Filtered(chip)
        local _, body = ns.TabNow:EmptyReason(ns.ActionEngine.meta, chip, total)
        if shown == 0 and total == 0 then
            H.ok(body:find("Советов у меня") == nil,
                "фильтр «" .. ns.CHIP_LABEL[chip] .. "»: 0 карточек — ничего не обещаем")
        else
            H.ok(true, "фильтр «" .. ns.CHIP_LABEL[chip] .. "»: карточки есть ("
                .. shown .. " из " .. total .. ")")
        end
    end
    ns.Config:SetChip(ns.CHIP.ALL)
end

-- Скрыть всё из интерфейса и вернуть обратно ---------------------------
H.suite("UI: скрыв все карточки, игрок видит причину и может вернуть")
do
    H.build(env)
    local keys = {}
    for _, card in ipairs(ns.ActionEngine.cards or {}) do
        if not card.blocking then keys[#keys + 1] = card.key end
    end
    H.ok(#keys > 0, #keys .. " карточек можно скрыть")
    for _, key in ipairs(keys) do
        ns.Config:Dismiss(key, env.Api:ServerTime(), 86400)
    end
    H.build(env)

    local cards = ns.ActionEngine.cards or {}
    H.ok(#cards > 0, "список не пуст: " .. #cards)
    ns.Config:SetChip(ns.CHIP.GOLD)
    local ok, err = pcall(function() ns.TabNow:Render() end)
    H.ok(ok, "окно рисуется с фильтром «Золото»", tostring(err))
    H.ok(#ns.ActionEngine:Filtered(ns.CHIP.GOLD) > 0,
        "и под фильтром «Золото» что-то видно")
    H.ok((ns.TabNow.summary:GetText() or ""):find("скрыто") ~= nil,
        "в сводке справа названо число скрытых: "
        .. tostring(ns.TabNow.summary:GetText()))

    -- Кнопка на карточке возвращает всё.
    local restore
    for _, card in ipairs(cards) do
        if card.action and card.action.kind == "undismiss" then restore = card end
    end
    H.ok(restore ~= nil, "карточка «вернуть скрытые» на месте")
    if restore then
        local ok2, err2 = pcall(function() ns.Card.ActivateInner(restore) end)
        H.ok(ok2, "нажатие «Вернуть все» не падает", tostring(err2))
        H.eq(ns.Config:DismissedCount(env.Api:ServerTime()), 0,
            "скрывашек не осталось")
        H.ok(#(ns.ActionEngine.cards or {}) > 1,
            "и советы вернулись: " .. #(ns.ActionEngine.cards or {}))
    end
    ns.Config:SetChip(ns.CHIP.ALL)
    H.build(env)
end

-- Скрытие видно сразу, а не после следующего события -------------------
H.suite("UI: скрытая карточка исчезает сразу")
do
    H.build(env)
    local victim
    for _, card in ipairs(ns.ActionEngine.cards or {}) do
        if not card.blocking then victim = card; break end
    end
    H.ok(victim ~= nil, "есть что скрыть")
    if victim then
        local before = #(ns.ActionEngine.cards or {})
        ns.Dismissal:Disarm()
        local ok, err = pcall(function()
            ns.Card.RequestDismiss(victim)
            ns.Card.RequestDismiss(victim)
        end)
        H.ok(ok, "скрытие в два щелчка прошло", tostring(err))
        -- Раньше здесь был Refresh, который только перерисовывает уже
        -- построенный список: карточка оставалась на экране как ни в чём не
        -- бывало, и игрок щёлкал дальше.
        local stillThere = false
        for _, card in ipairs(ns.ActionEngine.cards or {}) do
            if card.key == victim.key then stillThere = true end
        end
        H.eq(stillThere, false, "скрытая карточка ушла из списка немедленно")
        H.ok(#(ns.ActionEngine.cards or {}) < before
            or (ns.ActionEngine.meta.hiddenByDismissal or 0) > 0,
            "и это видно по списку или по счётчику скрытых")
        ns.Config:ClearDismissed()
        H.build(env)
    end
end

H.suite("UI: вкладка «Крафт» работает с выбранным рецептом")
do
    ns.MainFrame:Select("CRAFT")
    local ok, err = pcall(function() ns.TabCraft:RenderList() end)
    H.ok(ok, "список рецептов отрисован", tostring(err))
    ns.TabCraft.selected = 1
    local ok2, err2 = pcall(function() ns.TabCraft:RenderPlan() end)
    H.ok(ok2, "план выбранного рецепта отрисован", tostring(err2))
    ns.TabCraft.selected = 2   -- the enchant: no output item
    local ok3, err3 = pcall(function() ns.TabCraft:RenderPlan() end)
    H.ok(ok3, "план для чар (без предмета на выходе) отрисован", tostring(err3))
    ns.TabCraft.selected = 999999  -- does not exist
    local ok4, err4 = pcall(function() ns.TabCraft:RenderPlan() end)
    H.ok(ok4, "несуществующий рецепт не ломает панель", tostring(err4))
    ns.TabCraft.selected = nil
    local ok5, err5 = pcall(function() ns.TabCraft:RenderPlan() end)
    H.ok(ok5, "пустой выбор не ломает панель", tostring(err5))
end

H.suite("UI: настройки переключаются")
do
    ns.MainFrame:Select("CONFIG")
    local ok, err = pcall(function() ns.TabSettings:Render() end)
    H.ok(ok, "настройки отрисованы", tostring(err))

    -- НАБОР ЩЁЛКАЕТ ВСЁ ПОДРЯД И ОБЯЗАН ВЕРНУТЬ НАСТРОЙКИ КАК БЫЛИ.
    --
    -- Раньше не возвращал. Галочки перебираются через pairs, а порядок pairs
    -- не определён: какой вариант навигации окажется выбран последним, решал
    -- порядок обхода хеша. Под texluajit последним выходил «своя стрелка», и
    -- следующий набор про стрелку проходил; под настоящим Lua 5.1 - тем самым,
    -- что в игре, - последним выходил «выключить навигацию», стрелка честно
    -- отвечала «навигация выключена», и набор падал на пяти проверках. То есть
    -- набор был зелёным по совпадению, и ровно в том интерпретаторе, который
    -- от игрового отличается.
    local function deepCopy(t)
        if type(t) ~= "table" then return t end
        local out = {}
        for k, v in pairs(t) do out[k] = deepCopy(v) end
        return out
    end
    local function restoreInto(dst, src)
        for k in pairs(dst) do
            if src[k] == nil then dst[k] = nil end
        end
        for k, v in pairs(src) do
            if type(v) == "table" and type(dst[k]) == "table" then
                restoreInto(dst[k], v)
            else
                dst[k] = deepCopy(v)
            end
        end
    end
    local cfg = ns.Config:Get()
    local before = deepCopy(cfg)

    -- Toggle every checkbox and re-render.
    local toggled = 0
    for key, w in pairs(ns.TabSettings.pool) do
        if type(key) == "string" and key:sub(1, 5) == "check" then
            local handler = w.__scripts and w.__scripts.OnClick
            if handler then
                local ok2, err2 = pcall(handler, w)
                if ok2 then toggled = toggled + 1 else
                    H.ok(false, "переключатель " .. key, tostring(err2))
                end
            end
        end
    end
    H.ok(toggled > 0, toggled .. " переключателей сработало")
    local ok3, err3 = pcall(function() ns.TabSettings:Render() end)
    H.ok(ok3, "повторная отрисовка после переключений", tostring(err3))

    -- Вернуть настройки и то, что от них зависит на экране.
    restoreInto(cfg, before)
    pcall(function() ns.StepPanel:ApplyVisibility() end)
    pcall(function() ns.MainFrame:ApplyMinimapButton() end)
    local ok4, err4 = pcall(function() ns.TabSettings:Render() end)
    H.ok(ok4, "настройки возвращены в исходное состояние", tostring(err4))
    H.eq(cfg.nav.provider, before.nav.provider,
        "способ навигации тот же, что был до набора: " .. tostring(cfg.nav.provider))
    H.eq(cfg.panel.enabled, before.panel.enabled, "и панель в том же состоянии")
end

H.suite("UI: масштаб и позиция сохраняются")
do
    ns.Config:SetScale(1.25)
    local ok, err = pcall(function() ns.MainFrame:ApplyScale() end)
    H.ok(ok, "ApplyScale()", tostring(err))
    H.near(ns.Config:Scale(), 1.25, 0.001, "масштаб сохранён")
    ns.Config:SetScale(5)
    H.near(ns.Config:Scale(), 1.6, 0.001, "масштаб зажат сверху")
    ns.Config:SetScale(0.1)
    H.near(ns.Config:Scale(), 0.7, 0.001, "масштаб зажат снизу")
    ns.Config:SetScale(1.0)

    ns.Config:SaveFrame("TOPLEFT", "TOPLEFT", 120, -80, 800, 600)
    local f = ns.Config:Frame()
    H.eq(f.point, "TOPLEFT", "точка привязки сохранена")
    H.eq(f.x, 120, "x сохранён")
    H.eq(f.width, 800, "ширина сохранена")
    local ok2, err2 = pcall(function() ns.MainFrame:ApplyPosition() end)
    H.ok(ok2, "ApplyPosition()", tostring(err2))
    local ok3, err3 = pcall(function() ns.MainFrame:SavePosition() end)
    H.ok(ok3, "SavePosition()", tostring(err3))
end

H.suite("UI: показать / скрыть / бой")
do
    local ok, err = pcall(function() ns.MainFrame:Show() end)
    H.ok(ok, "Show()", tostring(err))
    H.ok(ns.MainFrame:IsShown(), "окно показано")
    local ok2, err2 = pcall(function() ns.MainFrame:OnCombat(true) end)
    H.ok(ok2, "вход в бой", tostring(err2))
    H.eq(ns.MainFrame:IsShown(), false, "в бою окно скрыто")
    local ok3, err3 = pcall(function() ns.MainFrame:OnCombat(false) end)
    H.ok(ok3, "выход из боя", tostring(err3))
    H.ok(ns.MainFrame:IsShown(), "после боя окно вернулось")
    local ok4, err4 = pcall(function() ns.MainFrame:Toggle() end)
    H.ok(ok4, "Toggle()", tostring(err4))
    H.eq(ns.MainFrame:IsShown(), false, "переключилось в скрытое")
    ns.MainFrame:Toggle()
end

H.suite("UI: кнопка у миникарты")
do
    ns.Config:Get().ui.minimapButton = true
    local ok, err = pcall(function() ns.MainFrame:ApplyMinimapButton() end)
    H.ok(ok, "кнопка создана", tostring(err))
    H.ok(ns.MainFrame.minimapButton ~= nil, "кнопка существует")
    ns.Config:Get().ui.minimapButton = false
    local ok2 = pcall(function() ns.MainFrame:ApplyMinimapButton() end)
    H.ok(ok2, "кнопка скрывается")
end

-- КНОПКА ДОЛЖНА ВЫГЛЯДЕТЬ КАК У ВСЕХ.
--
-- На скриншоте из игры у всех остальных аддонов кнопка в стандартном золотом
-- кольце, а у нашей рамки не было вовсе: тёмный круг с иконкой. Причина видна в
-- коде - рамка 52x52 вешалась в TOPLEFT кнопки 26x26, то есть съезжала на
-- четверть размера, а иконка ничем не обрезалась.
--
-- Проверить «красиво» тест не может. Проверить разметку - может: размеры,
-- точки привязки, слои и пути текстур. Пути не выдуманы: ровно эти три есть в
-- установленных аддонах этого клиента (MiniMap-TrackingBorder - 15 мест,
-- UI-Minimap-ZoomButton-Highlight - 8, TempPortraitAlphaMask - 29).
H.suite("Миникарта: стандартная рамка, иконка в маске, слои на месте")
do
    ns.Config:Get().ui.minimapButton = true
    ns.MinimapButton.button = nil
    ns.MainFrame.minimapButton = nil
    ns.MainFrame:ApplyMinimapButton()
    local btn = ns.MainFrame.minimapButton
    H.ok(btn ~= nil, "кнопка создана")

    local w, h = btn.__size and btn.__size[1], btn.__size and btn.__size[2]
    H.eq(w, 31, "размер кнопки как у стандартных: 31")
    H.eq(h, 31, "и по высоте 31")

    local border = ns.MinimapButton.border
    H.ok(border ~= nil, "рамка создана")
    H.eq(border and border.__texture, "Interface\\Minimap\\MiniMap-TrackingBorder",
        "рамка - стандартная текстура миникарты")
    H.eq(border and border.__size and border.__size[1], 53,
        "рамка 53 — под кнопку 31, иначе кольцо съезжает")
    H.eq(border and border.__layer, "OVERLAY", "рамка поверх иконки")
    H.eq(border and border.__points and border.__points[1]
        and border.__points[1][1], "TOPLEFT", "и привязана в TOPLEFT кнопки")

    local icon = ns.MinimapButton.icon
    H.ok(icon ~= nil, "иконка создана")
    H.eq(icon and icon.__layer, "ARTWORK", "иконка под рамкой")
    H.ok(icon and icon.__texCoord ~= nil,
        "иконка обрезана по кругу (SetTexCoord)")
    H.eq(icon and icon.__size and icon.__size[1], 17, "иконка 17 — как у всех")
    -- Иконка смещена внутрь кольца, а не поставлена по центру кнопки: центр
    -- кольца в этой текстуре смещён. Числа сверены с OpenMap на этом клиенте.
    local ip = icon and icon.__points and icon.__points[1]
    H.eq(ip and ip[1], "TOPLEFT", "иконка привязана в TOPLEFT")
    H.eq(ip and ip[4], 7, "смещение по X: 7")
    H.eq(ip and ip[5], -6, "смещение по Y: -6")

    local backdrop = ns.MinimapButton.backdrop
    H.ok(backdrop ~= nil, "тёмная подложка есть")
    H.eq(backdrop and backdrop.__layer, "BACKGROUND", "подложка под иконкой")
    H.eq(backdrop and backdrop.__texture, "Interface\\Minimap\\UI-Minimap-Background",
        "и это стандартный фон миникарты")
    H.ok(btn.__highlight ~= nil, "подсветка при наведении есть: "
        .. tostring(btn.__highlight))

    -- Кнопка должна быть выше самой миникарты, иначе кольцо окажется под ней.
    H.ok((btn.__frameLevel or 0) > 0, "уровень выше миникарты: "
        .. tostring(btn.__frameLevel))
    H.ok(btn.__dragButtons ~= nil, "перетаскивание включено: "
        .. tostring(btn.__dragButtons))
end

-- И ОНА ДОЛЖНА ЕЗДИТЬ ПО КРАЮ КАРТЫ.
--
-- Позиция хранится углом, а не координатами: миникарта бывает разного размера
-- и формы (Leatrix_Plus умеет делать её квадратной и подменяет
-- GetMinimapShape), и координаты, посчитанные для круга 140 пикселей, на
-- квадрате 200 оказались бы внутри карты или за экраном.
H.suite("Миникарта: позиция считается углом и переживает смену размера")
do
    local MB = ns.MinimapButton
    local R = MB.RADIUS_PAD

    local x0, y0 = MB.Place(0, 140, 140, "ROUND")
    H.near(x0, 70 + R, 0.01, "угол 0 — справа от центра: " .. string.format("%.1f", x0))
    H.near(y0, 0, 0.01, "и по высоте в центре")

    local x90, y90 = MB.Place(90, 140, 140, "ROUND")
    H.near(x90, 0, 0.01, "угол 90 — ровно сверху")
    H.near(y90, 70 + R, 0.01, "на радиусе: " .. string.format("%.1f", y90))

    local x135, y135 = MB.Place(135, 140, 140, "ROUND")
    H.ok(x135 < 0 and y135 > 0, "угол 135 — слева сверху")

    -- Радиус считается от РАЗМЕРА миникарты, а не от числа 80.
    local xBig = MB.Place(0, 200, 200, "ROUND")
    H.near(xBig, 100 + R, 0.01, "карта шире — кнопка дальше: "
        .. string.format("%.1f", xBig))

    -- Квадратная миникарта: точка обязана лежать на её кромке, а не на
    -- окружности, иначе кнопка повиснет в воздухе.
    local xs, ys = MB.Place(45, 140, 140, "SQUARE")
    local half = 70 + R
    H.ok(math.abs(xs) <= half + 0.01 and math.abs(ys) <= half + 0.01,
        "внутри габарита квадрата")
    H.ok(math.abs(math.abs(xs) - half) < 0.01 or math.abs(math.abs(ys) - half) < 0.01,
        string.format("и на самой кромке (%.1f, %.1f при половине %.1f)", xs, ys, half))

    -- Угол нормализуется: 370 и 10 - это одно и то же место.
    local xa, ya = MB.Place(370, 140, 140, "ROUND")
    local xb, yb = MB.Place(10, 140, 140, "ROUND")
    H.near(xa, xb, 0.01, "370 градусов — это 10 градусов")
    H.near(ya, yb, 0.01, "и по высоте тоже")

    -- Мусор вместо угла не должен ломать кнопку.
    local xn, yn = MB.Place(nil, 140, 140, "ROUND")
    H.ok(type(xn) == "number" and type(yn) == "number",
        "без угла берётся значение по умолчанию")
end

H.suite("Миникарта: угол сохраняется и восстанавливается")
do
    local MB = ns.MinimapButton
    H.ok(type(ns.Config.MinimapAngle) == "function", "угол хранится в настройках")
    local before = ns.Config:MinimapAngle()
    H.ok(type(before) == "number", "угол по умолчанию: " .. tostring(before))

    ns.Config:SetMinimapAngle(217.5)
    H.near(ns.Config:MinimapAngle(), 217.5, 0.01, "новый угол записан")
    H.eq(ns.Config:Get().ui.minimapAngle, 217.5, "и лежит в SavedVariables")

    -- Применение переносит кнопку туда же. Размер миникарты задаём явно:
    -- заглушка по умолчанию отдаёт 600x400, а у настоящей карты 140.
    env.G.Minimap:SetSize(140, 140)
    ns.MinimapButton.button = nil
    ns.MainFrame.minimapButton = nil
    ns.MainFrame:ApplyMinimapButton()
    local btn = ns.MainFrame.minimapButton
    local expectX, expectY = MB.Place(217.5, 140, 140, "ROUND")
    local pt = btn.__points and btn.__points[#btn.__points]
    H.ok(pt ~= nil, "кнопка привязана к миникарте")
    if pt then
        H.eq(pt[1], "CENTER", "от центра миникарты")
        H.near(pt[4], expectX, 0.01, "по углу: x")
        H.near(pt[5], expectY, 0.01, "по углу: y")
    end
    ns.Config:SetMinimapAngle(before)
end

H.suite("Миникарта: перетаскивание мышью меняет угол")
do
    local MB = ns.MinimapButton
    local G = env.G
    ns.Config:Get().ui.minimapButton = true
    ns.MinimapButton.button = nil
    ns.MainFrame.minimapButton = nil
    ns.MainFrame:ApplyMinimapButton()
    local btn = ns.MainFrame.minimapButton
    local start = ns.Config:MinimapAngle()

    -- Клиент отдаёт позицию курсора; подставим её сами, как это сделает игра.
    G.GetCursorPosition = function() return 500, 400 end
    G.Minimap.GetCenter = function() return 400, 400 end
    G.Minimap.GetEffectiveScale = function() return 1 end

    local dragStart = btn.__scripts and btn.__scripts.OnDragStart
    local dragStop = btn.__scripts and btn.__scripts.OnDragStop
    H.ok(dragStart ~= nil and dragStop ~= nil, "обработчики перетаскивания есть")
    if dragStart then
        dragStart(btn)
        H.eq(MB.dragging, true, "перетаскивание началось")
        local upd = btn.__scripts.OnUpdate
        H.ok(upd ~= nil, "движение отслеживается")
        if upd then upd(btn, 0.1) end
        H.near(ns.Config:MinimapAngle(), 0, 0.5,
            "курсор справа от центра — угол 0: "
            .. string.format("%.1f", ns.Config:MinimapAngle()))
        -- Курсор сверху.
        G.GetCursorPosition = function() return 400, 500 end
        if upd then upd(btn, 0.1) end
        H.near(ns.Config:MinimapAngle(), 90, 0.5, "курсор сверху — угол 90")
        dragStop(btn)
        H.eq(MB.dragging, nil, "перетаскивание закончилось")
        H.near(ns.Config:MinimapAngle(), 90, 0.5, "угол остался сохранённым")
    end
    ns.Config:SetMinimapAngle(start)
end

H.suite("UI: полный пересчёт из интерфейса")
do
    for _, def in ipairs(ns.MainFrame.TABS) do
        ns.MainFrame:Select(def.key)
        local ok, err = pcall(function() ns.MainFrame:Rebuild(true) end)
        H.ok(ok, "Rebuild на вкладке «" .. def.label .. "»", tostring(err))
    end
    local ok, err = pcall(function() ns.MainFrame:UpdateStatus() end)
    H.ok(ok, "строка статуса", tostring(err))
    H.ok(ns.MainFrame.status:GetText() ~= "", "в строке статуса есть текст")
end

H.suite("UI: не зовём игровых методов, которых мы не предусмотрели")
do
    local names = {}
    for key, n in pairs(unknownCalls) do names[#names + 1] = key .. "(x" .. n .. ")" end
    table.sort(names)
    if #names > 0 then
        print("     незнакомые методы: " .. table.concat(names, ", "))
    end
    -- Our own helper methods live on the frame table and never reach the
    -- metatable, so anything here is a game API we are assuming exists.
    H.eq(#names, 0, "неизвестных вызовов нет"
        .. (#names > 0 and (": " .. table.concat(names, ", ")) or ""))
end

-- The compact step panel -------------------------------------------------

H.suite("Панель шага: строится и показывает один верхний совет")
do
    local cfg = ns.Config:Get()
    cfg.panel.enabled = true
    cfg.panel.collapsed = false
    local ok, err = pcall(function() ns.StepPanel:Build() end)
    H.ok(ok, "Build()", tostring(err))
    H.ok(ns.StepPanel.frame ~= nil, "фрейм создан")

    H.build(env)
    local ok2, err2 = pcall(function() ns.StepPanel:Render() end)
    H.ok(ok2, "Render()", tostring(err2))
    H.ok(ns.StepPanel.current ~= nil, "совет выбран")
    H.ok(ns.StepPanel.frame.title:GetText() ~= "", "заголовок заполнен")

    -- It must show the same top card the big list shows.
    local cards = ns.ActionEngine.cards
    local firstActionable
    for _, card in ipairs(cards) do
        if card.pinTop then firstActionable = card; break end
    end
    if not firstActionable then
        for _, card in ipairs(cards) do
            if card.action and card.action.kind ~= "noop" then
                firstActionable = card; break
            end
        end
    end
    H.eq(ns.StepPanel.current.key, firstActionable and firstActionable.key,
        "панель показывает ту же карточку, что и верх списка")
end

-- «ПОКА НЕЧЕГО СОВЕТОВАТЬ» ПРИ ПОЛНОМ СПИСКЕ - ЭТО ЛОЖЬ =================
--
-- Живая жалоба: панель постоянно писала, что советовать нечего, при трёх
-- десятках советов в окне. Панель берёт тот же список, что и окно, поэтому
-- такое расхождение означает одно из двух: список при отрисовке был пуст
-- (например, ещё не считали) или выбор карточки вернул ничего при непустом
-- списке. Первое - правда, но сказанная не теми словами; второе - ложь, и его
-- нельзя просто «не допустить»: надо, чтобы оно себя назвало.

H.suite("Панель шага: при непустом списке «нечего советовать» не пишется")
do
    local cfg = ns.Config:Get()
    cfg.panel.enabled = true
    cfg.panel.collapsed = false
    ns.StepPanel:Build()
    H.build(env)
    H.ok(#ns.ActionEngine.cards > 0,
        "в списке есть советы: " .. #ns.ActionEngine.cards)
    ns.StepPanel:Render()
    local title = ns.StepPanel.frame.title:GetText() or ""
    H.eq(ns.Util.contains(title, "нечего советовать"), false,
        "и панель не говорит, что советовать нечего: " .. title)
    H.ok(ns.StepPanel.current ~= nil, "карточка выбрана")
end

H.suite("Панель шага: выбор вернул пусто при непустом списке — это странность")
do
    local cfg = ns.Config:Get()
    cfg.panel.enabled = true
    cfg.panel.collapsed = false
    ns.StepPanel:Build()
    H.build(env)
    ns.Diag:ClearSuspicions()
    -- Ломаем выбор нарочно: так выглядело бы любое будущее расхождение между
    -- «что в списке» и «что панель показывает».
    local realPick = ns.StepPanel.PickCard
    ns.StepPanel.PickCard = function() return nil, 0, 0 end
    ns.StepPanel:Render()
    ns.StepPanel.PickCard = realPick

    local title = ns.StepPanel.frame.title:GetText() or ""
    H.eq(ns.Util.contains(title, "нечего советовать"), false,
        "панель всё равно не врёт про пустой список: " .. title)
    local found
    for _, s in ipairs(ns.Diag:Init().suspicious or {}) do
        if s.code == "panel-empty-while-list-is-not" then found = s end
    end
    H.ok(found ~= nil, "и расхождение записано в диагностику")
    if found then
        H.ok(ns.Util.contains(found.text or "", "панель"),
            "с человеческим текстом: " .. ns.Util.truncate(found.text or "", 160))
    end
end

H.suite("Панель шага: пересчёта ещё не было — так и сказано")
do
    -- «Ещё не считал» и «советовать нечего» - разные утверждения. Первое
    -- правда, второе нет, и игрок по второму идёт искать поломку.
    local fresh = loadWithUI()
    local fns = fresh.ns
    fresh.ns.Config:Get().panel.enabled = true
    fresh.ns.Config:Get().panel.collapsed = false
    fns.StepPanel:Build()
    H.eq(#(fns.ActionEngine.cards or {}), 0, "список пуст: пересчёта не было")
    fns.StepPanel:Render()
    local title = fns.StepPanel.frame.title:GetText() or ""
    H.eq(ns.Util.contains(title, "нечего советовать"), false,
        "и панель не выдаёт это за «нечего советовать»: " .. title)
    H.ok(ns.Util.contains(title, "счит") or ns.Util.contains(title, "ещё"),
        "а говорит, что ещё не считала: " .. title)
end

H.suite("Панель шага: пересчёт был и список правда пуст — говорим прямо")
do
    local fresh = loadWithUI()
    local fns = fresh.ns
    fresh.ns.Config:Get().panel.enabled = true
    fresh.ns.Config:Get().panel.collapsed = false
    fns.StepPanel:Build()
    -- Пересчёт на пустом мире: советов правда нет.
    fns.CharacterScanner:Scan()
    fns.ActionEngine:Build()
    fns.StepPanel:Render()
    local title = fns.StepPanel.frame.title:GetText() or ""
    if #(fns.ActionEngine.cards or {}) == 0 then
        H.ok(ns.Util.contains(title, "нечего советовать"),
            "пустой список после пересчёта называется своим именем: " .. title)
    else
        H.ok(true, "в этом мире советы нашлись — проверка пропущена")
    end
end

H.suite("Панель шага: выключена - фрейм не создаётся вовсе")
do
    local fresh = loadWithUI()
    populate(fresh)
    fresh.ns.Config:Get().panel.enabled = false
    fresh.ns.StepPanel:ApplyVisibility()
    H.eq(fresh.ns.StepPanel.frame, nil,
        "выключенная панель не стоит вообще ничего - фрейма нет")
    fresh.ns.Config:Get().panel.enabled = true
    fresh.ns.StepPanel:ApplyVisibility()
    H.ok(fresh.ns.StepPanel.frame ~= nil, "после включения появляется")
end

H.suite("Панель шага: бой и подземелья не трогают галочку игрока")
do
    local cfg = ns.Config:Get()
    cfg.panel.enabled = true
    cfg.panel.combat = "hide"
    ns.StepPanel:OnCombat(true)
    H.eq(ns.StepPanel.frame:IsShown(), false, "в бою скрыта")
    H.eq(cfg.panel.enabled, true, "но галочка игрока НЕ переписана")
    ns.StepPanel:OnCombat(false)
    H.eq(ns.StepPanel.frame:IsShown(), true, "после боя вернулась сама")

    cfg.panel.combat = "fade"
    ns.StepPanel:OnCombat(true)
    H.eq(ns.StepPanel.frame:IsShown(), true, "в режиме «приглушить» остаётся видна")
    H.near(ns.StepPanel:TargetAlpha(), ns.StepPanel.COMBAT_ALPHA, 0.001,
        "но приглушена")
    ns.StepPanel:OnCombat(false)
    H.near(ns.StepPanel:TargetAlpha(), 1, 0.001, "после боя снова полная")

    cfg.panel.combat = "show"
    ns.StepPanel:OnCombat(true)
    H.eq(ns.StepPanel.frame:IsShown(), true, "в режиме «как обычно» не прячется")
    ns.StepPanel:OnCombat(false)

    cfg.panel.instance = "hide"
    ns.StepPanel:OnZone(true)
    H.eq(ns.StepPanel.frame:IsShown(), false, "в подземелье скрыта")
    H.eq(cfg.panel.enabled, true, "галочка снова не тронута")
    ns.StepPanel:OnZone(false)
    H.eq(ns.StepPanel.frame:IsShown(), true, "на выходе вернулась")
    cfg.panel.instance = "show"
end

H.suite("Панель шага: свёртывание и позиция")
do
    local cfg = ns.Config:Get()
    ns.StepPanel:ToggleCollapsed()
    H.eq(cfg.panel.collapsed, true, "свернулась")
    H.eq(ns.StepPanel.frame.title:IsShown(), false, "содержимое скрыто")
    local ok = pcall(function() ns.StepPanel:Render() end)
    H.ok(ok, "в свёрнутом виде рисуется без ошибок")
    ns.StepPanel:ToggleCollapsed()
    H.eq(cfg.panel.collapsed, false, "развернулась")
    H.eq(ns.StepPanel.frame.title:IsShown(), true, "содержимое вернулось")

    ns.StepPanel:SavePosition()
    H.ok(type(cfg.panel.pos) == "table", "позиция сохранена как пара чисел")
    cfg.panel.pos = { 123, 456 }
    local ok2 = pcall(function() ns.StepPanel:ApplyPosition() end)
    H.ok(ok2, "позиция применяется")
    ns.StepPanel:ResetPosition()
    H.eq(cfg.panel.pos, nil, "сброс позиции")
end

H.suite("Панель шага: «Дальше» листает и ничего не откладывает")
do
    -- ЭТОТ НАБОР РАНЬШЕ ПРОВЕРЯЛ ОБРАТНОЕ: что «Дальше» откладывает совет ровно
    -- на час. Поведение изменено намеренно - игрок трижды остался без советов,
    -- нажимая «Дальше», пока список не опустел, и каждый раз считал аддон
    -- сломанным. Теперь «Дальше» только меняет позицию панели; подробная
    -- проверка (N нажатий, круг, пересчёт) - в Tests/test_text.lua.
    local cfg = ns.Config:Get()
    ns.Config:ClearDismissed()
    H.build(env)
    ns.StepPanel.cursorKey, ns.StepPanel.cursorIndex = nil, 1
    ns.StepPanel:Render()
    local before = ns.StepPanel.current
    H.ok(before ~= nil, "панель показывает совет")
    if before then
        local hiddenBefore = ns.Config:DismissedCount(env.Api:ServerTime())
        local total = #(ns.ActionEngine.cards or {})
        local ok, moved = pcall(function() return ns.StepPanel:Advance() end)
        H.ok(ok, "Advance()", tostring(moved))

        -- Прежняя «Дальше» прятала совет из отложенного вызова (после анимации
        -- «готово»), а в тестах таймеры копятся. Без этого прогона старое
        -- поведение выглядело бы невинным.
        for _, fn in ipairs(env.pendingTimers or {}) do pcall(fn) end
        env.pendingTimers = {}

        H.eq(ns.Config:Get().dismissed[before.key], nil,
            "совет, с которого ушли, НЕ отложен")
        H.eq(ns.Config:DismissedCount(env.Api:ServerTime()), hiddenBefore,
            "число скрытых не изменилось")
        H.eq(#(ns.ActionEngine.cards or {}), total, "и советов в списке столько же")

        local after = ns.StepPanel.current
        if before.pinTop then
            -- Обязательный совет панель держит на виду: листать его нельзя.
            H.eq(moved, false, "с обязательного совета «Дальше» не уводит")
            H.eq(after and after.key, before.key, "он остался на панели")
        else
            H.eq(moved, true, "было куда перейти")
            H.ok(after ~= nil and after.key ~= before.key,
                "на панели следующий совет: " .. tostring(after and after.title))
        end
    end
    ns.StepPanel.cursorKey, ns.StepPanel.cursorIndex = nil, 1
    -- Right-click dismissal.
    ns.Config:ClearDismissed()
    H.build(env)
    ns.StepPanel:Render()
    local target = ns.StepPanel.current
    if target and target.blocking then
        for _, card in ipairs(ns.ActionEngine.cards or {}) do
            if not card.blocking then target = card; break end
        end
        ns.StepPanel.current = target
    end
    H.ok(target ~= nil and not target.blocking,
        "есть необязательный совет, который можно скрыть")
    if target and not target.blocking then
        -- ОДИН ПРАВЫЙ ЩЕЛЧОК БОЛЬШЕ НЕ ПРЯЧЕТ. Раньше этот набор проверял
        -- обратное - что один вызов Dismiss скрывает совет. Это был последний
        -- путь, которым совет исчезал от одного движения; теперь, как и в
        -- списке, первый щелчок спрашивает, второй прячет.
        ns.Dismissal:Disarm()
        local first = ns.StepPanel:Dismiss()
        H.eq(first, "armed", "первый правый щелчок только спрашивает")
        H.eq(ns.Config:IsDismissed(target.key, env.Api:ServerTime()), false,
            "и совет ещё на месте")
        ns.StepPanel.current = target
        local second = ns.StepPanel:Dismiss()
        H.eq(second, "hidden", "второй правый щелчок прячет")
        H.eq(ns.Config:IsDismissed(target.key, env.Api:ServerTime()), true,
            "совет скрыт")
        -- Срок - ЧАС, а не сутки: это «отложить», а не «убрать с глаз
        -- навсегда», и сутки дважды оставили игрока с пустым окном.
        local expiry = ns.Config:Get().dismissed[target.key]
        H.eq(expiry and (expiry - env.Api:ServerTime()), ns.SNOOZE_SECONDS,
            "и ровно на срок, названный в подсказке панели, — на час")
        H.ok(ns.SNOOZE_SECONDS < ns.DISMISS_SECONDS, "а это меньше суток")
    else
        H.ok(true, "верхняя карточка обязательная - скрывать нечего")
    end
    ns.Config:ClearDismissed()
    H.build(env)
end

H.suite("Панель шага: обязательный совет нельзя отложить")
do
    local saved = ns.RecipeBook.byProfession
    ns.RecipeBook.byProfession = {}
    ns.RecipeBook:Reindex()
    H.build(env)
    ns.StepPanel:Render()
    local card = ns.StepPanel.current
    H.ok(card ~= nil and card.blocking, "сверху обязательная карточка")
    if card then
        ns.StepPanel:Dismiss()
        H.eq(ns.Config:IsDismissed(card.key, env.Api:ServerTime()), false,
            "скрыть не удалось, и это правильно")
    end
    ns.RecipeBook.byProfession = saved
    ns.RecipeBook:Reindex()
    H.build(env)
end

H.suite("Панель шага: пустой список не ломает панель")
do
    local saved = ns.ActionEngine.cards
    ns.ActionEngine.cards = {}
    local ok, err = pcall(function() ns.StepPanel:Render() end)
    H.ok(ok, "рисуется без карточек", tostring(err))
    H.ok(ns.StepPanel.frame.title:GetText() ~= "", "и всё равно что-то говорит")
    ns.ActionEngine.cards = saved
end

-- The arrow --------------------------------------------------------------

H.suite("Стрелка: наводится и обновляется")
do
    -- Своё условие набор ставит сам, а не наследует от того, что осталось
    -- после предыдущих: этот набор про СВОЮ стрелку.
    ns.Config:Get().nav.provider = "own"
    ns.Places:RecordMerchant()
    local place = ns.Places:ForItem(2589)
    H.ok(place ~= nil, "есть куда вести")

    -- The merchant was recorded where the player stands, so walk away first,
    -- or the arrow correctly reports "arrived" and stops before we can look.
    env.playerMap = { mapID = 1434, x = 0.10, y = 0.76, zone = "Тернистая долина" }
    env.facing = 0

    local ok, reason, provider = ns.Arrow:SetTarget(place, "Торговец")
    H.eq(ok, true, "цель принята")
    H.eq(provider, "own", "ведём своей стрелкой")
    H.ok(ns.Arrow:HasTarget(), "цель активна")
    H.ok(ns.Arrow.ticker ~= nil, "тикер запущен")
    H.ok(ns.Arrow.frame:IsShown(), "окошко показано")

    ns.Arrow:Update()
    H.eq(ns.Arrow.state.reason, nil, "состояние без оговорок")
    H.ok(ns.Arrow.state.rotation ~= nil, "поворот посчитан")
    H.eq(ns.Arrow.frame.dial:IsShown(), true, "стрелка видна")
    H.ok(ns.Arrow.frame.distance:GetText() ~= "", "расстояние показано")
end

H.suite("Стрелка: без направления взгляда прячется, расстояние остаётся")
do
    env.facing = nil
    ns.Arrow:Update()
    H.eq(ns.Arrow.state.reason, "no-facing", "причина определена")
    H.eq(ns.Arrow.frame.dial:IsShown(), false, "стрелка скрыта")
    H.eq(ns.Arrow.frame.compass:IsShown(), true, "вместо неё направление по карте")
    H.ok(ns.Arrow.frame.compass:GetText():find("на "), "и это текст компаса: "
        .. ns.Arrow.frame.compass:GetText())
    H.ok(ns.Arrow.frame.distance:GetText() ~= "", "расстояние по-прежнему показано")
    env.facing = 0
end

H.suite("Стрелка: цель в другой зоне - зона и координаты текстом")
do
    env.playerMap = { mapID = 1411, x = 0.5, y = 0.5, zone = "Дуротар" }
    ns.Arrow:Update()
    H.eq(ns.Arrow.state.reason, "other-map", "причина - другая карта")
    H.eq(ns.Arrow.frame.dial:IsShown(), false, "стрелки нет")
    H.eq(ns.Arrow.frame.compass:GetText(), "Тернистая долина",
        "написана зона цели")
    H.ok(ns.Arrow.frame.distance:GetText():find("34"),
        "и координаты: " .. ns.Arrow.frame.distance:GetText())
    env.playerMap = { mapID = 1434, x = 0.10, y = 0.76, zone = "Тернистая долина" }
end

H.suite("Стрелка: прибытие останавливает тикер")
do
    ns.Arrow:SetTarget(ns.Places:ForItem(2589), "Торговец")
    env.playerMap = { mapID = 1434, x = 0.3401, y = 0.7601, zone = "Тернистая долина" }
    ns.Arrow:Update()
    H.eq(ns.Arrow.state.arrived, true, "прибыли")
    H.eq(ns.Arrow.ticker, nil, "тикер остановлен - следить больше не за чем")
    H.eq(ns.Arrow.frame.compass:GetText(), "на месте", "так и написано")
    env.playerMap = { mapID = 1434, x = 0.10, y = 0.76, zone = "Тернистая долина" }
end

H.suite("Стрелка: не знаем, где игрок")
do
    ns.Arrow:SetTarget(ns.Places:ForItem(2589), "Торговец")
    env.playerMap = nil
    ns.Arrow:Update()
    H.eq(ns.Arrow.state.reason, "no-player", "причина названа")
    local ok = pcall(function() ns.Arrow:Paint(ns.Arrow.state) end)
    H.ok(ok, "и ничего не падает")
    env.playerMap = { mapID = 1434, x = 0.10, y = 0.76, zone = "Тернистая долина" }
end

H.suite("Стрелка: цель без координат отклоняется")
do
    local ok, reason = ns.Arrow:SetTarget({ name = "Безымянное место" })
    H.eq(ok, false, "цель не принята")
    H.eq(reason, "no-coords", "с внятной причиной")
    local ok2, reason2 = ns.Arrow:SetTarget(nil)
    H.eq(ok2, false, "nil тоже отклонён")
    H.eq(reason2, "no-place", "и это видно")
end

H.suite("Стрелка: сброс, позиция, бой")
do
    ns.Arrow:SetTarget(ns.Places:ForItem(2589), "Торговец")
    ns.Arrow:SavePosition()
    H.ok(type(ns.Config:Get().nav.pos) == "table", "позиция сохранена")
    ns.Arrow:ResetPosition()
    H.eq(ns.Config:Get().nav.pos, nil, "сброс позиции")

    ns.Config:Get().nav.hideInCombat = true
    ns.Arrow:OnCombat(true)
    H.eq(ns.Arrow.frame:IsShown(), false, "в бою убрана")
    H.eq(ns.Arrow.ticker, nil, "и тикер остановлен - в бою не считаем")
    ns.Arrow:OnCombat(false)
    H.eq(ns.Arrow.frame:IsShown(), true, "после боя вернулась")
    H.ok(ns.Arrow.ticker ~= nil, "тикер снова идёт")

    ns.Arrow:Clear()
    H.eq(ns.Arrow:HasTarget(), false, "цель снята")
    H.eq(ns.Arrow.ticker, nil, "тикер остановлен")
    H.eq(ns.Arrow.frame:IsShown(), false, "окошко скрыто")
end

H.suite("Стрелка: выключенная навигация не наводится")
do
    ns.Config:Get().nav.provider = "off"
    local ok, reason = ns.Arrow:SetTarget(ns.Places:ForItem(2589))
    H.eq(ok, false, "цель не принята")
    H.eq(reason, "disabled", "причина - выключено в настройках")
    ns.Config:Get().nav.provider = "own"
end

H.suite("Стрелка: TomTom выбран, но не установлен - рисуем своё")
do
    env.tomtom = false
    ns.Config:Get().nav.provider = "tomtom"
    local ok, reason, provider = ns.Arrow:SetTarget(ns.Places:ForItem(2589))
    H.eq(ok, true, "цель всё равно принята")
    H.eq(provider, "own", "нарисовали свою стрелку вместо отказа")
    ns.Arrow:Clear()
    ns.Config:Get().nav.provider = "own"
end

H.suite("UI: использованные шаблоны фреймов")
do
    local seen = {}
    for _, entry in ipairs(callLog) do seen[entry] = (seen[entry] or 0) + 1 end
    local list = {}
    for entry, n in pairs(seen) do list[#list + 1] = entry .. " x" .. n end
    table.sort(list)
    print("     " .. table.concat(list, ", "))
    H.ok(seen["ScrollFrame/UIPanelScrollFrameTemplate"] ~= nil,
        "используется только штатный шаблон прокрутки")
end

-- Bootstrap -------------------------------------------------------------
-- Main.lua is the one file whose failure means the addon does not load at all,
-- so it gets its own pass: load it, fire the real login event sequence, and
-- run every slash command.

H.suite("Загрузка: Main.lua и последовательность входа в игру")
do
    local G, sandbox = env.G, env.sandbox
    G.SlashCmdList = {}
    G.GetMerchantNumItems = function() return 2 end
    G.GetMerchantItemInfo = function(i)
        return "Товар " .. i, nil, 100 * i, 5
    end
    G.GetMerchantItemLink = function(i)
        return "|Hitem:" .. (2589 + i) .. "::::::::26:1482:::::::::|h[Товар]|h|r"
    end

    local chunk, err = loadfile(H.ROOT .. "/Main.lua")
    H.ok(chunk ~= nil, "Main.lua компилируется", tostring(err))
    if chunk then
        setfenv(chunk, sandbox)
        local ok, loadErr = pcall(chunk, "ForeverPilot", ns)
        H.ok(ok, "Main.lua исполняется", tostring(loadErr))

        local driver = G.ForeverPilotDriver
        H.ok(driver ~= nil, "событийный фрейм создан")
        if driver then
            local handler = driver.__scripts and driver.__scripts.OnEvent
            H.ok(handler ~= nil, "обработчик событий установлен")
            if handler then
                -- The real order: ADDON_LOADED for us, then PLAYER_LOGIN.
                local ok1, e1 = pcall(handler, driver, "ADDON_LOADED", "ForeverPilot")
                H.ok(ok1, "ADDON_LOADED", tostring(e1))
                H.ok(G.ForeverPilotDB ~= nil, "SavedVariables созданы")
                H.ok(G.ForeverPilotCharDB ~= nil, "SavedVariablesPerCharacter созданы")

                local ok2, e2 = pcall(handler, driver, "PLAYER_LOGIN")
                H.ok(ok2, "PLAYER_LOGIN", tostring(e2))
                H.ok(ns.Bootstrap.ready, "инициализация завершена")

                -- ADDON_LOADED for some other addon must be ignored safely.
                local ok3, e3 = pcall(handler, driver, "ADDON_LOADED", "SomeOtherAddon")
                H.ok(ok3, "чужой ADDON_LOADED не ломает", tostring(e3))

                -- Then the live event stream.
                for _, event in ipairs({
                    "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED", "PLAYER_MONEY",
                    "PLAYER_EQUIPMENT_CHANGED", "TRADE_SKILL_SHOW",
                    "TRADE_SKILL_LIST_UPDATE", "MERCHANT_SHOW",
                    "GET_ITEM_INFO_RECEIVED", "SKILL_LINES_CHANGED",
                    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
                    "BANKFRAME_OPENED", "AUCTION_HOUSE_SHOW", "NEW_RECIPE_LEARNED",
                }) do
                    local okE, errE = pcall(handler, driver, event)
                    H.ok(okE, "событие " .. event, tostring(errE))
                end

                -- The scheduler must coalesce, then run.
                H.clock = H.clock + 10
                local okTick, errTick = pcall(function() ns.Events:Tick() end)
                H.ok(okTick, "планировщик сработал", tostring(errTick))
            end
        end

        -- Merchant prices get recorded without buying anything. The handler
        -- already ran on MERCHANT_SHOW above, so the prices are in by now.
        local okM, errM = pcall(function() ns.Bootstrap:ReadMerchant() end)
        H.ok(okM, "чтение витрины торговца", tostring(errM))
        local recorded = ns.Util.count(ns.Config:Get().vendorPrices)
        H.ok(recorded > 0, "цены торговца записаны (" .. recorded .. " позиций)")
        H.eq(ns.Config:VendorPrice(2589), 20, "цена за штуку, а не за стак (100/5)")
        -- And the merchant's position became a routable place.
        local place = ns.Places:ForItem(2589)
        H.ok(place ~= nil, "торговец записан как место")
        H.eq(place and place.routable, true, "с координатами, годными для стрелки")

        -- Every slash command.
        local cmd = G.SlashCmdList and G.SlashCmdList.FOREVERPILOT
        H.ok(cmd ~= nil, "слэш-команда зарегистрирована")
        H.eq(G.SLASH_FOREVERPILOT2, "/fp", "короткая команда /fp")
        if cmd then
            for _, arg in ipairs({ "", "now", "char", "craft", "config", "scan",
                                   "reset", "api", "show", "hidden", "вернуть",
                                   "скрытые", "сила", "прокачка", "экономия",
                                   "заработок", "чепуха" }) do
                local okC, errC = pcall(cmd, arg)
                H.ok(okC, "/fp " .. (arg == "" and "(без аргумента)" or arg), tostring(errC))
            end

            -- /fp show - это выход из состояния «я всё скрыл и окно пустое».
            -- Команда обязана реально снимать скрывашки, а не только печатать.
            ns.Config:Dismiss("profit:9999", env.Api:ServerTime(), 86400)
            ns.Config:Dismiss("gear:9999", env.Api:ServerTime(), 86400)
            H.eq(ns.Config:DismissedCount(env.Api:ServerTime()), 2,
                "две карточки скрыты")
            -- /fp hidden печатает оба числа: сколько записей лежит и сколько
            -- из них реально прячет совет. Раньше окно и команда могли
            -- показывать разные числа и противоречить друг другу.
            local said = {}
            local realPrint = ns.Api.Print
            ns.Api.Print = function(_, msg) said[#said + 1] = tostring(msg) end
            pcall(cmd, "hidden")
            ns.Api.Print = realPrint
            local text = table.concat(said, " | ")
            H.ok(text:find("2") ~= nil, "/fp hidden назвал число записей: " .. text)
            H.ok(text:find("прямо сейчас") ~= nil, "и сколько прячут совет сейчас")

            local okS, errS = pcall(cmd, "show")
            H.ok(okS, "/fp show исполнилась", tostring(errS))
            H.eq(ns.Config:DismissedCount(env.Api:ServerTime()), 0,
                "и скрывашек не осталось")

            -- И когда прятать нечего — так и говорит, без чисел.
            local said2 = {}
            ns.Api.Print = function(_, msg) said2[#said2 + 1] = tostring(msg) end
            pcall(cmd, "hidden")
            ns.Api.Print = realPrint
            H.ok(table.concat(said2, " "):find("скрытых советов нет") ~= nil,
                "/fp hidden на пустой таблице: " .. table.concat(said2, " "))
        end

        -- The addon compartment entry point.
        H.ok(type(G.ForeverPilot_OnAddonCompartmentClick) == "function",
            "точка входа для меню аддонов есть")
        local okA = pcall(G.ForeverPilot_OnAddonCompartmentClick)
        H.ok(okA, "она вызывается без ошибок")
    end
end

-- ЦЕНА ОТРИСОВКИ - В ВЫЗОВАХ, А НЕ В МИЛЛИСЕКУНДАХ ------------------------
--
-- Игрок пожаловался на фризы. В FOREVERPILOT_DIAG видно только пересчёт
-- (средний 40 мс, пик 112), и это неполная картина: таймер
-- Diag:TimerStart/TimerStop обнимает ActionEngine:Build, а ОТРИСОВКА идёт после
-- него и в эти числа не входит вовсе.
--
-- А стоила она дорого. На настоящих данных игрока (26 советов на экране) ОДНА
-- отрисовка списка строила 663 строки-варианта (U.shortenings) и просила
-- клиент померить ширину 330 раз - и делала это ЗАНОВО при каждой отрисовке,
-- включая те, где ни один совет не изменился: прокрутка, наведение мыши,
-- возврат на вкладку, смена фильтра.
--
-- Мерить здесь миллисекунды нельзя, и это правило проекта: на выдуманных
-- данных поддельный GetStringWidth - обращение к таблице, а настоящий стоит на
-- три порядка дороже, и время из теста в игру не переносится. ЧИСЛО ВЫЗОВОВ -
-- переносится один в один. Поэтому контракт такой: повторная отрисовка, в
-- которой ничего не изменилось, не строит ни одного варианта.
H.suite("UI: повторная отрисовка не пересчитывает то же самое")
do
    -- Мир СВОЙ: в общем мире список уже рисовали другие наборы, память
    -- укороченных строк в нём прогрета, и «первая отрисовка» перестала бы
    -- быть первой.
    local fresh = loadWithUI()
    local fns = fresh.ns
    populate(fresh)
    local U, W = fns.Util, fns.Widgets

    local counted = { shortenings = 0, variants = 0 }
    local realShort = U.shortenings
    U.shortenings = function(text)
        counted.shortenings = counted.shortenings + 1
        local out = realShort(text)
        counted.variants = counted.variants + #out
        return out
    end
    W.fitMemoHits, W.fitMemoMisses = 0, 0

    -- Первая отрисовка: строить варианты ПРИХОДИТСЯ, и без этого числа
    -- следующая проверка проверяла бы пустоту - «ноль вариантов» получился бы и
    -- у окна, в котором нечего рисовать. Считаем с самого открытия вкладки:
    -- Select рисует её сам, и если начать считать после него, первая отрисовка
    -- окажется уже не первой.
    fns.MainFrame:Build()
    fns.MainFrame:Select("NOW")
    local firstShort, firstVariants = counted.shortenings, counted.variants
    H.ok(firstShort > 0, "первая отрисовка строит варианты: " .. firstShort
        .. " обращений, " .. firstVariants .. " вариантов")
    H.ok((W.fitMemoMisses or 0) > 0, "и память при этом пуста: промахов "
        .. tostring(W.fitMemoMisses))

    -- А ТЕПЕРЬ ТРИ ОТРИСОВКИ ПОДРЯД, И НИ ОДНА НЕ МЕНЯЕТ НИ СОВЕТОВ, НИ ШИРИНЫ.
    counted.shortenings, counted.variants = 0, 0
    W.fitMemoHits = 0
    local RENDERS = 3
    for _ = 1, RENDERS do fns.MainFrame:RenderActive() end
    U.shortenings = realShort

    H.eq(counted.shortenings, 0, "повторные отрисовки не строят вариантов ни разу"
        .. " (было бы " .. (firstShort * RENDERS) .. " обращений, стало "
        .. counted.shortenings .. ")")
    H.eq(counted.variants, 0, "и ни одной строки-варианта"
        .. " (было бы " .. (firstVariants * RENDERS) .. ", стало "
        .. counted.variants .. ")")
    H.ok((W.fitMemoHits or 0) > 0, "память укороченных строк отвечала: попаданий "
        .. tostring(W.fitMemoHits))

    -- ПАМЯТЬ ОБЯЗАНА ЗАБЫВАТЬ. Изменился текст или место - значит, надо мерить
    -- заново; иначе на экране осталась бы прошлая строка, и это была бы ложь
    -- похуже медленной отрисовки.
    local fs = fns.Card.pool[1] and fns.Card.pool[1].title
    H.ok(fs ~= nil, "строка заголовка первого совета есть")
    if fs then
        local long = string.rep("Очень длинное название рецепта ", 6)
        local a = W.SetFitted(fs, long, 120)
        H.ok(a ~= long, "в узкое место длинный текст не влез целиком")
        local b = W.SetFitted(fs, "Коротко", 120)
        H.eq(b, "Коротко", "другой текст — другой ответ")
        H.eq(fs:GetText(), b, "и на экране стоит новый ответ")
        -- Та же строка, но места сколько угодно: ответ обязан стать другим.
        local wide = W.SetFitted(fs, long, 100000)
        H.eq(wide, long, "на широком месте тот же текст стоит целиком")
        -- И обратно в узкое: прежний ответ, а не запомненный широкий.
        H.eq(W.SetFitted(fs, long, 120), a, "и назад в узкое — снова укороченный")
    end
end

-- СПИСОК ФАЙЛОВ АДДОНА - ОДИН НА ОБА СКАНЕРА, И ИЗ .toc, А НЕ РУКАМИ.
-- Оба перечня ниже (автоматизация и защищённые вызовы) смотрят ровно те файлы,
-- которые грузит игра; разойдись они - и один сканер проверял бы меньше другого.
local function tocFiles()
    local files = {}
    local toc = io.open(H.ROOT .. "/ForeverPilot.toc", "r")
    if toc then
        for line in toc:lines() do
            local rel = line:match("^%s*([%w_]+[\\/][%w_]+%.lua)%s*$")
                or line:match("^%s*([%w_]+%.lua)%s*$")
            if rel then files[#files + 1] = rel:gsub("\\", "/") end
        end
        toc:close()
    end
    return files
end

H.suite("Загрузка: ничего не автоматизируется")
do
    -- A deliberate check against the hard rule: the addon must never call any
    -- of these. Scanning the source is cruder than a runtime check, but it is
    -- the only way to prove a negative about code paths we did not exercise.
    local forbidden = {
        "BuyMerchantItem", "UseContainerItem", "PickupContainerItem",
        "PlaceAuctionBid", "PostAuction", "SellCursorItem",
        "C_AuctionHouse%.PostItem", "C_AuctionHouse%.PlaceBid",
        -- Крафт за игрока на этом клиенте зовётся тремя именами, и все три
        -- запрещены: DoTradeSkill (ремёсла), DoCraft (чары и алхимия в старом
        -- API) и C_TradeSkillUI.CraftRecipe (современное).
        "DoTradeSkill", "DoCraft", "CraftRecipe", "C_TradeSkillUI%.CraftRecipe",
        "UseAction", "CastSpellByName", "RunMacro", "RunMacroText",
        "SetBinding", "ConfirmBindOnUse", "RepairAllItems",
        "ForceQuit", "Logout", "SetCVar",
    }
    -- Every .lua the .toc loads, read from the .toc itself. The hand-written
    -- list this replaces was missing Core/Diag.lua, Logic/SanityChecks.lua,
    -- Logic/SourceCheck.lua and Data/ForeverSource.lua - so a forbidden call
    -- in any of them would have passed unnoticed.
    local files = tocFiles()
    -- ЧТО ОБЯЗАНО БЫТЬ В СПИСКЕ, И ПОЧЕМУ ЭТО ОТДЕЛЬНАЯ ПРОВЕРКА.
    --
    -- Список выше ведётся руками, и из него уже один раз выпало имя: были
    -- DoTradeSkill и CraftRecipe, а DoCraft не было. Это та же самая «сделай
    -- крафт за игрока»: в старом API профессий ремёсла делались через
    -- DoTradeSkill, а чары и алхимия - через DoCraft, и клиент знает оба имени.
    -- Пропуск в списке не виден ни одним «ok»: проверка проходит, потому что
    -- искать нечего. Поэтому состав списка проверяется сам.
    local MUST_HAVE = {
        "BuyMerchantItem", "SellCursorItem", "UseContainerItem",
        "DoTradeSkill", "DoCraft", "CraftRecipe",
        "PlaceAuctionBid", "PostAuction",
    }
    local inList = {}
    for _, name in ipairs(forbidden) do inList[(name:gsub("%%", ""))] = true end
    local absent = {}
    for _, name in ipairs(MUST_HAVE) do
        if not inList[name] then absent[#absent + 1] = name end
    end
    H.eq(#absent, 0, "в списке запрещённых есть все обязательные имена"
        .. ((#absent > 0) and ("  <- не хватает: " .. table.concat(absent, ", ")) or ""))

    H.ok(#files >= 27, #files .. " файлов из .toc под проверкой")
    local hits = {}
    for _, rel in ipairs(files) do
        local fh = io.open(H.ROOT .. "/" .. rel, "r")
        if fh then
            local src = fh:read("*a")
            fh:close()
            -- Strip comment lines so the forbidden names may be DISCUSSED.
            local code = {}
            for line in (src .. "\n"):gmatch("([^\n]*)\n") do
                if not line:match("^%s*%-%-") then code[#code + 1] = line end
            end
            code = table.concat(code, "\n")
            for _, name in ipairs(forbidden) do
                if code:find(name) then
                    hits[#hits + 1] = rel .. " -> " .. name:gsub("%%", "")
                end
            end
        end
    end
    H.eq(#hits, 0, "ни одного вызова автоматизации или покупки/продажи"
        .. (#hits > 0 and (": " .. table.concat(hits, ", ")) or ""))
    print("     проверено " .. #files .. " файлов на " .. #forbidden
        .. " запрещённых вызовов")
end

-- ЗАЩИЩЁННЫЕ ВЫЗОВЫ: ВТОРОЙ ПЕРЕЧЕНЬ, С ДРУГИМ ПРИЗНАКОМ -------------------
--
-- Игрок увидел в игре окно:
--
--   «Модификация "ForeverPilot" заблокирована при попытке выполнения
--    действия, доступного только интерфейсу Blizzard. Вы можете отключить
--    эту модификацию и перезагрузить интерфейс. [Отключить] [Пропустить]»
--
-- Это ADDON_ACTION_BLOCKED, и пришло оно от C_TradeSkillUI.OpenRecipe -
-- вызова, который сам аддон считал безобидным: он ничего не покупает, не
-- продаёт и не крафтит, он всего лишь открывает рецепт в чужом окне. Список
-- запрещённых функций ВЫШЕ собран по признаку «делает за игрока», поэтому
-- OpenRecipe в него не попал - и проверка была зелёной, пока игра не отказала.
--
-- ПРИЗНАК ЗДЕСЬ ДРУГОЙ: «клиент может отказать и обвинить аддон». Сюда входит
-- всё, что на этом клиенте защищено или требует аппаратного события: открытие
-- и закрытие игровых окон, защищённые фреймы и их атрибуты, перетаскивание
-- предметов, камера и движение, цель, макросы и привязки. Проверять это в
-- игре нельзя (блокировка видна только игроку и только после того, как
-- случилась), поэтому перечень ЗАКРЫТЫЙ: имени из него в коде аддона быть не
-- должно вовсе, а обсуждать его в комментариях можно.
--
-- И ДВЕ ЗАЩИТЫ ОТ «ПРОВЕРКА ПРОШЛА, ПОТОМУ ЧТО ИСКАТЬ БЫЛО НЕЧЕГО»:
--   1. состав перечня сверяется с обязательным списком (MUST_HAVE ниже);
--   2. сам искатель проверяется на подложенном тексте - он обязан найти
--      каждое имя из перечня и не обязан находить похожее своё.
-- Без первой пропуск имени не виден; без второй не виден сломанный шаблон.
local PROTECTED = {
    -- Открыть/закрыть чужое окно
    "ShowUIPanel", "HideUIPanel", "ToggleFrame", "SetUIPanel",
    "OpenAllBags", "CloseAllBags", "ToggleAllBags", "ToggleBackpack",
    "OpenBackpack", "OpenBag", "ToggleBag", "ToggleCharacter",
    "ToggleSpellBook", "ToggleTalentFrame", "ToggleWorldMap",
    "ToggleQuestLog", "ToggleGuildFrame", "ToggleFriendsFrame",
    "ToggleDropDownMenu",
    -- Окно профессий: ИМЕННО ЭТО И ЗАБЛОКИРОВАЛИ
    "C_TradeSkillUI%.OpenRecipe", "C_TradeSkillUI%.OpenTradeSkill",
    "C_TradeSkillUI%.CloseTradeSkill", "CloseTradeSkill",
    -- Защищённые фреймы и драйверы состояния
    "SetAttribute", "SetAttributeNoHandler", "RegisterUnitWatch",
    "UnregisterUnitWatch", "RegisterStateDriver", "UnregisterStateDriver",
    "RegisterAttributeDriver", "SecureActionButtonTemplate",
    "SecureHandlerStateTemplate", "SetFrameRef", "WrapScript",
    -- Предметы под курсором и в ячейках
    "PickupItem", "PickupContainerItem", "PickupInventoryItem",
    "PickupMerchantItem", "PickupPlayerMoney", "PickupTradeMoney",
    "SplitContainerItem", "C_Container%.UseContainerItem",
    "C_Container%.PickupContainerItem", "C_Container%.SplitContainerItem",
    "C_Container%.UseHearthstone", "SocketContainerItem", "SocketInventoryItem",
    "EquipCursorItem", "DeleteCursorItem", "ConfirmLootSlot",
    -- Камера и движение: только от аппаратного события
    "CameraOrSelectOrMoveStart", "CameraOrSelectOrMoveStop",
    "TurnOrActionStart", "TurnOrActionStop", "JumpOrAscendStart",
    "MoveForwardStart", "MoveBackwardStart", "StrafeLeftStart",
    "StrafeRightStart", "TurnLeftStart", "TurnRightStart", "PitchUpStart",
    "SitStandOrDescendStart", "ToggleRun", "SetView", "SaveView", "ResetView",
    "CameraZoomIn", "CameraZoomOut",
    -- Цель и взаимодействие
    "TargetUnit", "TargetNearestEnemy", "TargetNearestFriend", "ClearTarget",
    "FollowUnit", "InteractUnit", "AssistUnit", "SpellTargetUnit",
    -- Действия, макросы, привязки
    "UseAction", "PickupAction", "PlaceAction", "StopCasting",
    "SpellStopTargeting", "SetBindingClick", "SetBindingSpell",
    "SetBindingMacro", "SetBindingItem", "LoadBindings", "SaveBindings",
    -- Диалоги и подтверждения, которые вместо игрока нажимать нельзя
    "SelectGossipOption", "SelectGossipAvailableQuest",
    "C_GossipInfo%.SelectOption", "GetQuestReward", "AcceptQuest",
    "CompleteQuest", "AbandonQuest",
    -- Система
    "ConsoleExec", "ReloadUI", "RestartGfx",
}
-- ЧТО ОБЯЗАНО БЫТЬ В ПЕРЕЧНЕ. Отдельно от самого перечня и теми же словами,
-- которыми про это говорит отчёт игроку: без этой сверки выпавшее имя не
-- видно ни одним «ok».
local PROTECTED_MUST_HAVE = {
    "C_TradeSkillUI.OpenRecipe", "ShowUIPanel", "HideUIPanel",
    "SetAttribute", "RegisterUnitWatch", "CameraOrSelectOrMoveStart",
    "PickupItem", "C_Container.UseContainerItem", "UseAction",
    "InteractUnit", "SetView", "ReloadUI",
}

-- ВТОРАЯ ЧАСТЬ ПЕРЕЧНЯ: НЕ ИМЯ ФУНКЦИИ, А ОБРАЩЕНИЕ К ЧУЖОМУ ОБЪЕКТУ.
--
-- Эти три случая именем не выражаются, а запрещены по тому же признаку:
--   * нажать чужую кнопку за игрока (:Click) - у защищённой кнопки игра это
--     блокирует, а у обычной это всё равно действие вместо игрока;
--   * тронуть саму миникарту (её можно только читать и к ней можно прицепить
--     свою кнопку - больше ничего: двигать и прятать чужую миникарту значит
--     ломать другие аддоны);
--   * тронуть UIParent (его тоже только читать: размер экрана).
-- Шаблоны здесь не имена, поэтому и ищутся отдельно, как есть.
local PROTECTED_PATTERNS = {
    { pattern = "[%.:]Click%s*%(", why = "нажатие кнопки за игрока (:Click)" },
    { pattern = "Minimap%s*:%s*Set", why = "миникарту двигают/настраивают" },
    { pattern = "Minimap%s*:%s*Hide", why = "миникарту прячут" },
    { pattern = "Minimap%s*:%s*Show", why = "миникарту показывают" },
    { pattern = "Minimap%s*:%s*ClearAllPoints", why = "миникарту срывают с места" },
    { pattern = "UIParent%s*:%s*Set", why = "UIParent настраивают" },
    { pattern = "UIParent%s*:%s*Hide", why = "UIParent прячут" },
}

-- Искатель. Комментарии снимаются ЦЕЛИКОМ, включая хвост строки: имя должно
-- быть можно обсудить в комментарии рядом с кодом, а не только отдельной
-- строкой. Границы слова - %f, иначе «SetViewport» сошёл бы за «SetView».
local function protectedHits(src, list)
    local hits = {}
    for line in (tostring(src) .. "\n"):gmatch("([^\n]*)\n") do
        local code = line:gsub("%-%-.*$", "")
        for _, name in ipairs(list) do
            if code:find("%f[%w_]" .. name .. "%f[^%w_]") then
                hits[#hits + 1] = (name:gsub("%%", ""))
            end
        end
        for _, rule in ipairs(PROTECTED_PATTERNS) do
            if code:find(rule.pattern) then hits[#hits + 1] = rule.why end
        end
    end
    return hits
end

H.suite("Загрузка: ни одного защищённого вызова игры")
do
    -- 1. СОСТАВ ПЕРЕЧНЯ.
    local inList = {}
    for _, name in ipairs(PROTECTED) do inList[(name:gsub("%%", ""))] = true end
    local absent = {}
    for _, name in ipairs(PROTECTED_MUST_HAVE) do
        if not inList[name] then absent[#absent + 1] = name end
    end
    H.eq(#absent, 0, "в перечне защищённых есть все обязательные имена"
        .. ((#absent > 0) and ("  <- не хватает: " .. table.concat(absent, ", ")) or ""))
    H.ok(#PROTECTED >= 60, "имён в перечне: " .. #PROTECTED)

    -- 2. САМ ИСКАТЕЛЬ. Проверка проходит, когда искать нечего, - поэтому
    --    сначала доказываем, что он вообще умеет находить.
    local missed = {}
    for _, name in ipairs(PROTECTED) do
        local plain = (name:gsub("%%", ""))
        if #protectedHits("local x = " .. plain .. "(1)", PROTECTED) == 0 then
            missed[#missed + 1] = plain
        end
    end
    H.eq(#missed, 0, "искатель находит каждое имя из перечня"
        .. ((#missed > 0) and ("  <- не нашёл: " .. table.concat(missed, ", ")) or ""))
    H.eq(#protectedHits("-- C_TradeSkillUI.OpenRecipe нельзя звать", PROTECTED), 0,
        "и не считает находкой упоминание в комментарии")
    H.eq(#protectedHits("f:SetViewport(1) local v = MySetAttributeHelper", PROTECTED), 0,
        "и не принимает похожее своё имя за защищённое")

    -- Вторая часть перечня - шаблонами, и у неё та же пара проверок.
    local missedPat = {}
    for _, rule in ipairs(PROTECTED_PATTERNS) do
        local sample = ({
            ["[%.:]Click%s*%("] = "AuctionatorTabs_Shopping:Click()",
            ["Minimap%s*:%s*Set"] = "Minimap:SetPoint(1)",
            ["Minimap%s*:%s*Hide"] = "Minimap:Hide()",
            ["Minimap%s*:%s*Show"] = "Minimap:Show()",
            ["Minimap%s*:%s*ClearAllPoints"] = "Minimap:ClearAllPoints()",
            ["UIParent%s*:%s*Set"] = "UIParent:SetScale(2)",
            ["UIParent%s*:%s*Hide"] = "UIParent:Hide()",
        })[rule.pattern]
        if not sample or #protectedHits(sample, PROTECTED) == 0 then
            missedPat[#missedPat + 1] = rule.why
        end
    end
    H.eq(#missedPat, 0, "искатель находит каждый шаблон из перечня"
        .. ((#missedPat > 0) and ("  <- не нашёл: " .. table.concat(missedPat, ", ")) or ""))
    -- И не придирается к тому, что аддону МОЖНО: читать миникарту и экран,
    -- цеплять к миникарте свою кнопку, спрашивать, есть ли у чужой кнопки
    -- метод Click.
    H.eq(#protectedHits(
        "local w = _G.Minimap:GetWidth() btn:SetPoint('CENTER', _G.Minimap)"
        .. " local h = UIParent:GetHeight() local ok = type(tab.Click) == 'function'",
        PROTECTED), 0, "и не придирается к разрешённому чтению миникарты и экрана")

    -- 3. И ТОЛЬКО ТЕПЕРЬ - САМ КОД, все файлы из .toc.
    local files = tocFiles()
    H.ok(#files >= 27, #files .. " файлов из .toc под проверкой на защищённые вызовы")
    local found = {}
    for _, rel in ipairs(files) do
        local fh = io.open(H.ROOT .. "/" .. rel, "r")
        if fh then
            local src = fh:read("*a")
            fh:close()
            for _, name in ipairs(protectedHits(src, PROTECTED)) do
                found[#found + 1] = rel .. " -> " .. name
            end
        end
    end
    H.eq(#found, 0, "ни одного защищённого вызова в коде аддона нет"
        .. ((#found > 0) and ("  <- " .. table.concat(found, ", ")) or ""))
    print("     проверено " .. #files .. " файлов на " .. #PROTECTED
        .. " защищённых вызовов")
end

end
