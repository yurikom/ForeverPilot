-- ForeverPilot / Tests/uistub.lua
--
-- A frame stub plus a loader, shared by the UI suites that are not test_ui.lua.
--
-- WHY IT EXISTS. test_ui.lua grew its own stub inline, and it is the right one -
-- it has the allow-list that catches a game method we invented by mistake.
-- But a second UI suite needs the same scaffolding, and copying 200 lines into
-- it would mean two stubs drifting apart. This file is the shared half: the
-- parts that only MODEL the client. The allow-list check stays in test_ui.lua,
-- which is where it belongs - it is an assertion, not scaffolding.
--
-- The stub answers every method on the list and records what it was told, so a
-- test can ask what a button's label actually says and whether it is on screen.
-- That is the whole point: the texts invariant cannot be checked against source
-- code, only against the frames the addon really built.
--
-- Nothing here is loaded in game: Tests/ is not referenced from the .toc.

local S = {}

-- Methods the stub answers. Deliberately the same list as test_ui.lua's: a
-- method missing here would make a suite fail for the wrong reason.
S.KNOWN_METHODS = {}
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
    -- Ширина текста без переноса (по ней считается, сколько строк он займёт) и
    -- то, что сейчас лежит в текстуре (так узнаётся, нашёл ли клиент файл).
    "GetUnboundedStringWidth", "GetTexture",
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
    -- Окно на свой лад (2026-11-21): своя полоса прокрутки (колесо мыши и
    -- положение списка), свой шрифт (объект шрифта: файл, тень), переход цвета
    -- в шапке, скруглённые плашки из трёх кусков без щели между ними и предел
    -- размера окна на старых клиентах.
    "EnableMouseWheel", "GetVerticalScroll", "SetFont", "GetFont",
    "SetShadowOffset", "SetShadowColor", "SetGradient", "SetSnapToPixelGrid",
    "SetTexelSnappingBias", "SetMaxResize",
}) do S.KNOWN_METHODS[name] = true end

S.KNOWN_FIELDS = { ScrollBar = true, ScrollFrame = true }

-- Build a fresh stub world. Everything it records lives on the returned table,
-- so two loads in one suite never see each other's frames.
function S.newWorld()
    local world = { frames = {}, templates = {}, unknown = {} }
    local frameMT

    -- НОВЫЙ ФРЕЙМ В КЛИЕНТЕ ПОКАЗАН, А НЕ СКРЫТ.
    --
    -- Это не придирка к точности: вся проверка «текст не называет кнопки,
    -- которой нет на экране» стоит на том, что значит «на экране». Со
    -- скрытым-по-умолчанию фреймом ни одна кнопка настроек не считалась
    -- видимой, и инвариант проходил, ничего не проверив, — а это худший сорт
    -- зелёного теста. Код аддона зовёт :Hide() там, где действительно хочет
    -- спрятать, так что показ по умолчанию — это и есть поведение игры.
    local function newFrame(frameType, name, parent)
        local f = setmetatable({
            __type = frameType or "Frame",
            __name = name,
            __parent = parent,
            __scripts = {},
            __shown = true,
            -- И РАЗМЕР НОВОГО ФРЕЙМА — НОЛЬ, А НЕ ВЫДУМАННЫЕ 300x100.
            --
            -- В клиенте у свежего CreateFrame ширина и высота равны нулю, пока
            -- не позвали SetSize или не задали точки привязки с двух сторон.
            -- Выдуманный размер прятал настоящую ошибку: проверка «не за краем
            -- ли экрана» в панели выполнялась ДО SetSize, на нулевом фрейме
            -- считала панель потерянной и стирала сохранённую позицию при
            -- каждом входе в игру — да ещё печатала об этом в чат.
            __width = 0,
            __height = 0,
            __text = "",
        }, frameMT)
        world.frames[#world.frames + 1] = f
        return f
    end
    world.newFrame = newFrame

    frameMT = {
        __index = function(t, key)
            if type(key) ~= "string" then return nil end
            if key:sub(1, 2) == "__" then return nil end
            if not S.KNOWN_METHODS[key] then
                if not S.KNOWN_FIELDS[key] then
                    local looksLikeMethod = key:match("^[SGI][ec]t%u") or key:match("^Is%u")
                        or key:match("^Register%u") or key:match("^Create%u")
                        or key:match("^Start%u") or key:match("^Stop%u")
                    if looksLikeMethod then
                        world.unknown[key] = (world.unknown[key] or 0) + 1
                    end
                end
                return nil
            end

            local fn
            if key == "CreateTexture" then
                fn = function(self, name, layer)
                    local tex = newFrame("Texture", name, self)
                    tex.__layer = layer
                    return tex
                end
            elseif key == "CreateFontString" then
                fn = function(self, name, layer, font)
                    local fs = newFrame("FontString", nil, self)
                    fs.__layer, fs.__font = layer, font
                    return fs
                end
            -- ЦВЕТА И «ВО ВЕСЬ РОДИТЕЛЬ» ЗАПИСЫВАЮТСЯ. Проверкам разметки они не
            -- нужны, а картинке окна, которую по этим же рамкам рисует
            -- Tests/preview.py, - нужны: без них видно прямоугольники, но не
            -- видно, как окно выглядит.
            elseif key == "SetColorTexture" then
                fn = function(self, r, g, b, a) self.__color = { r, g, b, a } end
            elseif key == "SetTextColor" then
                fn = function(self, r, g, b, a) self.__textColor = { r, g, b, a } end
            elseif key == "SetAllPoints" then
                fn = function(self, other) self.__allPoints = other or true end
            elseif key == "SetJustifyH" then
                fn = function(self, v) self.__justifyH = v end
            elseif key == "SetWordWrap" then
                fn = function(self, v) self.__wrap = v and true or false end
            elseif key == "SetScript" then
                fn = function(self, which, handler) self.__scripts[which] = handler end
            elseif key == "GetScript" then
                fn = function(self, which) return self.__scripts[which] end
            elseif key == "HookScript" then
                -- Hooks run after whatever SetScript put there, which is what
                -- the addon relies on for OnHide.
                fn = function(self, which, handler)
                    local prev = self.__scripts[which]
                    self.__scripts[which] = function(...)
                        if prev then prev(...) end
                        return handler(...)
                    end
                end
            elseif key == "Show" then
                fn = function(self) self.__shown = true end
            elseif key == "Hide" then
                fn = function(self)
                    local was = self.__shown
                    self.__shown = false
                    local h = self.__scripts and self.__scripts.OnHide
                    -- Only when it was actually visible, exactly like the client.
                    if was and h then h(self) end
                end
            elseif key == "IsShown" or key == "IsVisible" then
                fn = function(self) return self.__shown end
            elseif key == "SetWidth" then
                fn = function(self, v) self.__width = v end
            elseif key == "SetHeight" then
                fn = function(self, v) self.__height = v end
            elseif key == "SetSize" then
                fn = function(self, w, h) self.__width, self.__height = w, h end
            elseif key == "SetPoint" then
                fn = function(self, ...)
                    self.__points = self.__points or {}
                    self.__points[#self.__points + 1] = { ... }
                end
            elseif key == "ClearAllPoints" then
                fn = function(self) self.__points = {} end
            elseif key == "SetTexture" then
                fn = function(self, v) self.__texture = v end
            elseif key == "GetTexture" then
                fn = function(self) return self.__texture end
            elseif key == "GetUnboundedStringWidth" then
                fn = function(self) return S.textWidth(self.__text, self.__font) end
            elseif key == "SetTexCoord" then
                fn = function(self, ...) self.__texCoord = { ... } end
            elseif key == "SetMask" or key == "SetMaskTexture" then
                fn = function(self, v) self.__mask = v end
            elseif key == "SetHighlightTexture" then
                fn = function(self, v) self.__highlight = v end
            elseif key == "SetFrameLevel" then
                fn = function(self, v) self.__frameLevel = v end
            elseif key == "GetFrameLevel" then
                fn = function(self) return self.__frameLevel or 1 end
            elseif key == "SetFrameStrata" then
                fn = function(self, v) self.__strata = v end
            elseif key == "SetClampedToScreen" then
                fn = function(self, v) self.__clamped = v and true or false end
            elseif key == "Raise" then
                fn = function(self) self.__raised = (self.__raised or 0) + 1 end
            elseif key == "RegisterForDrag" then
                fn = function(self, ...) self.__dragButtons = table.concat({ ... }, ",") end
            elseif key == "GetWidth" then
                fn = function(self) return self.__width or 300 end
            elseif key == "GetHeight" then
                fn = function(self) return self.__height or 100 end
            elseif key == "SetText" then
                fn = function(self, v) self.__text = tostring(v or "") end
            elseif key == "GetText" then
                fn = function(self) return self.__text end
            elseif key == "GetStringWidth" then
                -- Roughly a small game font: enough for the layout arithmetic
                -- to behave like the client's, which is all it is used for.
                fn = function(self) return S.textWidth(self.__text, self.__font) end
            elseif key == "GetStringHeight" then
                -- Текст с заданной шириной переносится, и высота его - столько
                -- строк, сколько вышло. Раньше заглушка отвечала «12» на любой
                -- текст, и разметка, которая ставит блоки один под другим по
                -- этой высоте, на бумаге не налезала никогда.
                fn = function(self)
                    local w = tonumber(self.__width) or 0
                    local text = self.__text or ""
                    local line = S.lineHeight(self.__font)
                    if w <= 0 or self.__wrap == false or text == "" then return line end
                    local lines = 0
                    for para in (text .. "\n"):gmatch("([^\n]*)\n") do
                        lines = lines + S.wrapCount(para, self.__font, w)
                    end
                    return lines * line
                end
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
            elseif key == "GetRotation" then
                fn = function(self) return self.__rotation or 0 end
            elseif key == "SetRotation" then
                fn = function(self, r) self.__rotation = r end
            elseif key == "GetParent" then
                fn = function(self) return self.__parent end
            elseif key == "SetParent" then
                fn = function(self, p) self.__parent = p end
            elseif key == "GetValue" then
                fn = function(self) return self.__value or 1 end
            elseif key == "SetValue" then
                fn = function(self, v) self.__value = v end
            elseif key == "SetVerticalScroll" then
                fn = function(self, v) self.__vscroll = tonumber(v) or 0 end
            elseif key == "GetVerticalScroll" then
                fn = function(self) return self.__vscroll or 0 end
            -- Объект шрифта: файл либо принят, либо нет. Заглушка принимает
            -- всё, что ей дали; «клиент файла не видит» проверки задают сами.
            elseif key == "SetFont" then
                fn = function(self, path, size)
                    if world.rejectFonts then return false end
                    self.__fontFile, self.__fontSize = path, size
                    return true
                end
            elseif key == "GetFont" then
                fn = function(self) return self.__fontFile, self.__fontSize, "" end
            elseif key == "SetVertexColor" then
                fn = function(self, r, g, b, a) self.__vertex = { r, g, b, a } end
            elseif key == "SetGradient" then
                fn = function(self, orientation, from, to)
                    self.__gradient = { orientation, from, to }
                end
            elseif key == "SetScrollChild" then
                fn = function(self, c) self.__scrollChild = c end
            elseif key == "GetScrollChild" then
                fn = function(self) return self.__scrollChild end
            elseif key == "GetName" then
                fn = function(self) return self.__name end
            elseif key == "GetObjectType" then
                fn = function(self) return self.__type end
            elseif key == "SetChecked" then
                fn = function(self, v) self.__checked = v and true or false end
            elseif key == "GetChecked" then
                fn = function(self) return self.__checked end
            else
                fn = function() return nil end
            end
            t[key] = fn
            return fn
        end,
    }
    return world
end

-- Characters are about this wide in GameFontHighlightSmall. The exact number
-- does not matter; what matters is that a long label measures wider than a
-- short one, because that is what the panel's button row decides on.
--
-- S.measure / S.measureLine / S.measureWrap - настоящие мерки шрифта. Их
-- подставляет Tests/preview.py (там шрифт загружен по-настоящему), чтобы
-- картинка окна совпадала с тем, что нарисует клиент: какая строка влезла,
-- какая перенеслась. Проверкам они не нужны и в них не заданы.
function S.textWidth(s, font)
    if S.measure then return S.measure(tostring(s or ""), font) end
    local n = 0
    for _ in tostring(s or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*") do n = n + 1 end
    return n * 6
end

function S.lineHeight(font)
    if S.measureLine then return S.measureLine(font) end
    return 12
end

-- Во сколько строк ляжет абзац при этой ширине.
function S.wrapCount(para, font, width)
    if S.measureWrap then return S.measureWrap(tostring(para or ""), font, width) end
    return math.max(1, math.ceil(S.textWidth(para, font) / width))
end

S.UI_FILES = {
    "UI/Widgets.lua", "UI/Arrow.lua", "UI/Card.lua", "UI/StepPanel.lua",
    "UI/TabNow.lua", "UI/TabCharacter.lua", "UI/TabCraft.lua",
    "UI/TabSettings.lua", "UI/MinimapButton.lua", "UI/MainFrame.lua",
}

-- Load the addon with the UI on top of the stub. Returns the harness env with
-- `world` attached.
function S.load(H, opts)
    opts = opts or {}
    return S.attachUI(H, H.load(opts), opts)
end

-- СВОИ ФАЙЛЫ АДДОНА КЛИЕНТ ВИДИТ (шрифт, значки) - или нет.
--
-- По умолчанию заглушка ведёт себя как игра ДО полного перезапуска: метки
-- X-Media нет, шрифт создать нечем, окно рисуется шрифтами игры и без значков.
-- С opts.media = true она ведёт себя как игра после перезапуска: метка на
-- месте, CreateFont есть, шрифт загружается. Оба вида обязаны проходить одни и
-- те же проверки разметки.
S.MEDIA_STAMP = "2"
function S.grantMedia(env, world)
    local G = env.G
    G.C_AddOns = G.C_AddOns or {}
    local prev = G.C_AddOns.GetAddOnMetadata
    G.C_AddOns.GetAddOnMetadata = function(addon, field)
        if field == "X-Media" then return S.MEDIA_STAMP end
        if prev then return prev(addon, field) end
        return nil
    end
    G.CreateFont = function(name)
        local font = world.newFrame("Font", name)
        if name then G[name] = font end
        return font
    end
    -- Переход цвета в шапке: клиент даёт для него объект цвета.
    G.CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
    if env.ns and env.ns.Api then
        env.ns.Api.mediaReady, env.ns.Api.fontsReady = nil, nil
    end
end

-- ТОТ ЖЕ ИНТЕРФЕЙС, НО НА УЖЕ СОБРАННОМ МИРЕ.
--
-- Мир на настоящих сохранениях игрока собирает Tests/inspect_real.lua, и
-- интерфейса в нём нет: скрипт показывает советы текстом. А проверять
-- разметку - сколько строк над списком, что обрезано по ширине - можно только
-- на нарисованном окне. Поэтому загрузка интерфейса вынута сюда: один и тот же
-- код и для выдуманных миров (S.load выше), и для настоящего.
function S.attachUI(H, env, opts)
    local ns, G, sandbox = env.ns, env.G, env.sandbox
    local world = S.newWorld()
    env.world = world
    opts = opts or {}
    if opts.media or S.FORCE_MEDIA then S.grantMedia(env, world) end

    -- A real screen, not the stub's default: the off-screen rescue compares
    -- against UIParent's size, and 600x400 would call every position broken.
    G.UIParent = world.newFrame("Frame", "UIParent")
    G.UIParent:SetSize(1920, 1080)
    G.UIParent.__left, G.UIParent.__bottom = 0, 0
    G.UIParent:Show()
    G.Minimap = world.newFrame("Frame", "Minimap")
    G.Minimap:SetSize(140, 140)
    G.GameTooltip = world.newFrame("GameTooltip", "GameTooltip")
    G.UISpecialFrames = {}
    G.GetScreenWidth = function() return 1920 end
    G.GetScreenHeight = function() return 1080 end
    -- Modifier keys. The stub starts with none held; a test sets this.
    world.shiftDown = false
    G.IsShiftKeyDown = function() return world.shiftDown and true or false end

    G.CreateFrame = function(frameType, name, parent, template)
        local f = world.newFrame(frameType, name, parent)
        world.templates[#world.templates + 1] =
            (frameType or "?") .. (template and ("/" .. template) or "")
        if name then G[name] = f end
        return f
    end
    G.C_Timer = {
        After = function(_, fn)
            env.pendingTimers = env.pendingTimers or {}
            table.insert(env.pendingTimers, fn)
        end,
        NewTicker = function(_, fn)
            env.pendingTickers = env.pendingTickers or {}
            table.insert(env.pendingTickers, fn)
            return { Cancel = function() end }
        end,
    }
    G.GetTime = function() return H.clock end

    for _, rel in ipairs(S.UI_FILES) do
        local path = H.ROOT .. "/" .. rel
        local chunk, err = loadfile(path)
        if not chunk then error("не загрузился " .. rel .. ": " .. tostring(err)) end
        setfenv(chunk, sandbox)
        local ok, loadErr = pcall(chunk, "ForeverPilot", ns)
        if not ok then error("ошибка загрузки " .. rel .. ": " .. tostring(loadErr)) end
    end
    return env
end

-- A world with something of every card kind, so every surface has data to draw.
-- Kept in step with test_ui.lua's `populate` on purpose: a suite that draws a
-- different world from the one test_ui draws would disagree with it for reasons
-- that have nothing to do with what either is checking.
function S.populate(env, H)
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

-- РАЗМЕРЫ, КОТОРЫХ ЗАГЛУШКА САМА НЕ СЧИТАЕТ ------------------------------
--
-- В клиенте вкладка растянута по окну (SetAllPoints), а список - по вкладке:
-- ширину им считает клиент по привязкам. Заглушка привязок не считает, и
-- ширина остаётся нулевой - а на нулевой ширине любая проверка «что на что
-- налезает» и «что не влезло в строку» зеленеет, ничего не проверив.
--
-- Поэтому размеры задаются явно и в одном месте - так же, как посчитал бы
-- клиент: окно, вкладка по окну, список по вкладке. Числа отступов берутся у
-- самих файлов интерфейса, а не повторяются здесь.
S.WINDOW_WIDTH, S.WINDOW_HEIGHT = 980, 600

function S.layout(env, width, height)
    local ns = env.ns
    width = width or S.WINDOW_WIDTH
    height = height or S.WINDOW_HEIGHT
    local main = ns.MainFrame
    if main and main.frame then main.frame:SetSize(width, height) end
    -- Площадь разделов - справа от полосы и над строкой состояния. Числа
    -- отвечает само окно (Main.HostSize), а не повторяются здесь.
    local innerW, innerH = width, height
    if main and main.HostSize then innerW, innerH = main.HostSize(width, height) end
    if main and main.host then main.host.__width, main.host.__height = innerW, innerH end
    if main and main.band then main.band.__width = innerW end
    if main and main.page then
        main.page.__width, main.page.__height = innerW, innerH - (main.BAND_H or 0)
    end
    if main and main.foot then main.foot.__width = innerW end
    if main and main.rail then main.rail.__height = height - 2 end
    -- «Советы»: три колонки, и ширины их отвечает сама вкладка (Tab.Columns).
    local tab = ns.TabNow
    if tab and tab.frame then
        tab.frame.__width, tab.frame.__height = innerW, innerH
        local cols = tab.Columns(innerW)
        if tab.side then tab.side.__height = innerH end
        if tab.mainCol then tab.mainCol.__width, tab.mainCol.__height = cols.main, innerH end
        if tab.band then tab.band.__width = cols.main end
        if tab.pane then tab.pane.__height = innerH end
        local detail = ns.Detail and ns.Detail.frame
        if detail then detail.__width, detail.__height = cols.detail, innerH end
        if tab.scroll then
            tab.scroll.__width = cols.list
            tab.scroll.__height = innerH - tab.LIST_TOP - tab.LIST_SIDE
        end
    end
    return width, height
end

-- ЧАСТИ КАРТОЧКИ СОВЕТА, КОТОРЫЕ СЕЙЧАС НА ЭКРАНЕ ---------------------------
--
-- Имя части, её прямоугольник по привязкам, нарисованный текст и - где он
-- известен - текст, который должен стоять целиком (название и выгода из
-- совета, остальное из Card.Sheet). Один перечень на все проверки разметки:
-- Tests/test_window.lua, Tests/corpus.lua.
function S.detailParts(ns)
    local d = ns.Detail
    local out = {}
    if not (d and d.frame) then return out end
    local card = d.card
    local sheet = card and ns.Card.Sheet(card) or nil
    local function add(name, el, fs, full)
        if el and el.__shown then
            out[#out + 1] = {
                name = name, el = el, rect = S.rectOf(el, d.frame),
                drawn = fs and S.plain(fs.__text or "") or nil,
                full = (full ~= nil and full ~= "") and S.plain(tostring(full)) or nil,
            }
        end
    end
    add("вид совета", d.kind, d.kind)
    add("иконка", d.iconHit)
    add("название", d.title, d.title, card and card.title)
    add("выгода", d.benefit, d.benefit and d.benefit.text, card and card.benefit)
    add("выгода строкой", d.benefitLine, d.benefitLine, card and card.benefit)
    add("готовность", d.state, d.state and d.state.text)
    add("сомнение", d.warn, d.warn, sheet and sheet.warn)
    add("суть", d.lead, d.lead, sheet and sheet.lead)
    for i, row in ipairs(d.rows or {}) do
        local want = sheet and sheet.rows[i]
        add("подпись строки " .. i, row.label, row.label, want and want.label)
        add("значение строки " .. i, row.value, row.value, want and want.value)
    end
    for i, caption in ipairs(d.captions or {}) do add("заголовок блока " .. i, caption, caption) end
    for i, item in ipairs(d.items or {}) do
        add("позиция " .. i, item.left, item.left)
        add("цена позиции " .. i, item.right, item.right)
    end
    add("ещё позиции", d.more, d.more)
    add("что сделать", d.need, d.need, sheet and sheet.need)
    add("что сделать самому", d.note, d.note)
    add("кнопка действия", d.action)
    add("кнопка пути", d.route)
    return out
end

-- ЩЕЛЧОК ПО СТРОКЕ СПИСКА ------------------------------------------------
--
-- Кнопок в строках списка больше нет: щелчок по строке выбирает совет, и он
-- открывается в карточке справа (ns.Detail) - полный текст и одна кнопка
-- действия. Проверки, которые раньше нажимали кнопку в строке, делают то же,
-- что игрок: щёлкают по строке и нажимают кнопку в карточке.

-- Щёлкнуть по строке. Возвращает карточку совета справа.
function S.pick(ns, row)
    local click = row.__scripts and row.__scripts.OnClick
    if click then click(row, "LeftButton") end
    return ns.Detail
end

-- Кнопка действия выбранного совета - если она нарисована. Иначе nil.
function S.actionOf(ns, row)
    local detail = S.pick(ns, row)
    local btn = detail and detail.action
    if btn and btn.__shown and detail.card == row.card then return btn end
    return nil
end

-- ГЕОМЕТРИЯ ПО ПРИВЯЗКАМ ------------------------------------------------
--
-- Игрок дважды присылал скриншоты с текстом поверх текста: сначала вторая
-- строка карточки поверх третьей, потом кнопка фильтра поверх строки «75
-- рецептов известно • материалы по советам: 4з 34с». Глазами такое видно, по
-- исходнику - нет: в коде каждое число стоит по месту, а налезает то, что из
-- них получается.
--
-- Поэтому прямоугольники считаются ТАК ЖЕ, КАК ИХ СЧИТАЕТ КЛИЕНТ: по привязкам,
-- от выбранной точки отсчёта. Жило это внутри Tests/test_nonsense.lua и умело
-- только вертикаль; теперь здесь и для всех - вертикаль и горизонталь, потому
-- что «не налезает» без горизонтали не проверить.
--
-- Начало координат - левый верхний угол `root`: вправо плюс, вниз минус.

-- Привязка в том виде, в каком её принимает клиент: либо (точка, x, y) с
-- неявным родителем, либо (точка, кто, его точка, x, y).
function S.pointsOf(el)
    local out = {}
    for _, p in ipairs(el.__points or {}) do
        if type(p[2]) == "table" then
            out[#out + 1] = { point = p[1], rel = p[2], relPoint = p[3] or p[1],
                              x = tonumber(p[4]) or 0, y = tonumber(p[5]) or 0 }
        else
            out[#out + 1] = { point = p[1], rel = el.__parent, relPoint = p[1],
                              x = tonumber(p[2]) or 0, y = tonumber(p[3]) or 0 }
        end
    end
    return out
end

-- Размер: заданный, а у текста без заданного - по шрифту (столько же, сколько
-- отвечают про него GetStringWidth и GetStringHeight заглушки).
function S.sizeOf(el)
    local w = tonumber(el.__width) or 0
    local h = tonumber(el.__height) or 0
    if el.__type == "FontString" then
        -- Высота не задана - значит, «сама по тексту»: у строки с заданной
        -- шириной это столько строк, сколько вышло после переноса.
        if h <= 0 then
            h = (w > 0 and el.GetStringHeight) and el:GetStringHeight() or S.lineHeight(el.__font)
        end
        if w <= 0 then w = S.textWidth(S.plain(el.__text or ""), el.__font) end
    end
    return w, h
end

function S.rectOf(el, root, depth)
    if not el then return nil end
    local w, h = S.sizeOf(el)
    if el == root then return { top = 0, bottom = -h, left = 0, right = w } end
    depth = (depth or 0) + 1
    if depth > 12 then return nil end
    for _, p in ipairs(S.pointsOf(el)) do
        local r = S.rectOf(p.rel, root, depth)
        if r then
            local ry
            if p.relPoint:find("TOP") then ry = r.top
            elseif p.relPoint:find("BOTTOM") then ry = r.bottom
            else ry = (r.top + r.bottom) / 2 end
            ry = ry + p.y
            local top, bottom
            if p.point:find("TOP") then top, bottom = ry, ry - h
            elseif p.point:find("BOTTOM") then top, bottom = ry + h, ry
            else top, bottom = ry + h / 2, ry - h / 2 end

            local rx
            if p.relPoint:find("LEFT") then rx = r.left
            elseif p.relPoint:find("RIGHT") then rx = r.right
            else rx = (r.left + r.right) / 2 end
            rx = rx + p.x
            local left, right
            if p.point:find("LEFT") then left, right = rx, rx + w
            elseif p.point:find("RIGHT") then left, right = rx - w, rx
            else left, right = rx - w / 2, rx + w / 2 end

            return { top = top, bottom = bottom, left = left, right = right }
        end
    end
    return nil
end

-- Насколько два прямоугольника налезают друг на друга: по горизонтали и по
-- вертикали. Налезание есть только тогда, когда и то и другое больше нуля -
-- кнопка слева от строки и кнопка над строкой одинаково не мешают.
function S.rectOverlap(a, b)
    if not (a and b) then return 0, 0 end
    local top, bottom = math.min(a.top, b.top), math.max(a.bottom, b.bottom)
    local left, right = math.max(a.left, b.left), math.min(a.right, b.right)
    local oy = (top > bottom) and (top - bottom) or 0
    local ox = (right > left) and (right - left) or 0
    if ox <= 0 or oy <= 0 then return 0, 0 end
    return ox, oy
end

-- Walking the frames a surface actually built ---------------------------

-- Is `frame` a descendant of `root`? The texts invariant is "on the same
-- screen", and the only honest way to answer that is ancestry plus visibility.
function S.descends(frame, root)
    local seen, node = {}, frame
    while node do
        if node == root then return true end
        if seen[node] then return false end   -- a parent cycle; refuse to loop
        seen[node] = true
        node = node.__parent
    end
    return false
end

-- Everything on this surface that a player can see, as two lists:
--   labels - the text of every visible clickable thing (buttons, chips, checks)
--   texts  - the text of every visible font string that is not such a label
--
-- Visibility here is "shown, and every ancestor up to the surface is shown",
-- because a label inside a hidden row is not on screen however much text it has.
function S.harvest(world, root)
    -- On screen means: this thing is shown, and so is every frame between it
    -- and the surface. A label inside a hidden row is not on screen, however
    -- much text it holds.
    --
    -- The surface ITSELF is not part of the question: `root` is what we are
    -- calling "the screen", and asking whether the screen is on screen is not
    -- a useful question. It is also a trap - opening the window for real calls
    -- a full rebuild, which wipes the world the test set up, so a suite that
    -- needed the window shown just to read its labels ended up checking a
    -- different screen than it meant to.
    local function visible(f)
        local node, seen = f, {}
        while node do
            if seen[node] then return false end
            seen[node] = true
            if node == root then return true end
            if not node.__shown then return false end
            node = node.__parent
        end
        return false
    end

    -- A clickable thing is a Button, and its text lives either in `.text`
    -- (our own widgets) or in `.label` (our checkbox rows).
    local labelOf = {}
    for _, f in ipairs(world.frames) do
        if f.__type == "Button" and S.descends(f, root) then
            for _, field in ipairs({ "text", "label" }) do
                local fs = rawget(f, field)
                if type(fs) == "table" and fs.__type == "FontString" then
                    labelOf[fs] = f
                end
            end
        end
    end

    local labels, texts = {}, {}
    for _, f in ipairs(world.frames) do
        if f.__type == "FontString" and S.descends(f, root) then
            local text = f.__text
            if text and text ~= "" and visible(f) then
                local owner = labelOf[f]
                if owner then
                    if owner.__shown then labels[#labels + 1] = text end
                else
                    texts[#texts + 1] = text
                end
            end
        end
    end
    return labels, texts
end

-- Colour codes are not words. Strip them before looking for element names, or
-- "|cffff6060пересчёт" reads as a name nobody wrote.
function S.plain(s)
    s = tostring(s or "")
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    s = s:gsub("|H.-|h", ""):gsub("|h", ""):gsub("|T.-|t", "")
    return s
end

-- Every element name a text claims exists: the words inside guillemets. That is
-- this addon's own convention for naming a control, used consistently, which is
-- what makes the invariant checkable at all.
--
-- `.-` AND NOT `[^»]+`, AND THIS COST A GREEN TEST THAT PROVED NOTHING.
--
-- Lua 5.1 patterns work on BYTES. In UTF-8 «» are \194\171 and \194\187, so
-- `[^»]` is a class excluding the bytes \194 and \187 - and \187 is the second
-- byte of the Cyrillic "л". So the class broke on the first "л" inside the
-- quotes and the pattern never matched anything in Russian text. The whole
-- invariant passed because it found zero names to check. Verified by sabotage:
-- a text renamed to «Волшебная кнопка» went through green, which is how this
-- was found at all. The lazy `.-` has no character class and is byte-safe.
function S.quotedNames(s)
    local out = {}
    for name in S.plain(s):gmatch("«(.-)»") do
        out[#out + 1] = name
    end
    return out
end

-- Every slash command a text tells the player to type. Same byte trap avoided:
-- the exclusion list holds only ASCII punctuation, never a multi-byte char.
function S.slashCommands(s)
    local out = {}
    for cmd in S.plain(s):gmatch("/fp%s+([^%s%.,;:!%?|%)]+)") do
        out[#out + 1] = cmd:lower()
    end
    return out
end

return S
