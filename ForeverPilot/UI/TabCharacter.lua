-- ForeverPilot / UI/TabCharacter.lua
--
-- What I know about you, and where each piece came from. This tab exists so the
-- advice on the Now tab is never a black box: if a number here is wrong, the
-- player can see which source produced it.
local ADDON, ns = ...

local U = ns.Util
local W = ns.Widgets

local Tab = {}
ns.TabCharacter = Tab

Tab.PAD = 12

function Tab:Build(parent)
    if self.frame then return self.frame end
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)
    self.frame = frame

    local scroll, content = W.ScrollArea(frame)
    scroll:SetPoint("TOPLEFT", Tab.PAD, -Tab.PAD)
    scroll:SetPoint("BOTTOMRIGHT", -(Tab.PAD + 22), Tab.PAD)
    self.scroll, self.content = scroll, content
    self.widgets = {}
    return frame
end

-- Builders reuse a single pool of rows so switching tabs does not leak frames.
function Tab:Row(kind, index)
    local key = kind .. index
    local w = self.widgets[key]
    if w then w:Show(); return w end
    if kind == "head" then
        w = W.SectionHeader(self.content, "", 400)
    elseif kind == "stat" then
        w = W.StatRow(self.content, "", "", 400)
    elseif kind == "note" then
        w = W.Label(self.content, "", W.FONT_SMALL, 0.60, 0.60, 0.60)
        w.SetTextSafe = function(self2, t) self2:SetText(t) end
    end
    self.widgets[key] = w
    return w
end

function Tab:Render()
    if not self.frame then return end
    for _, w in pairs(self.widgets) do w:Hide() end

    local snap = ns.CharacterScanner:Get()
    local width = (self.scroll:GetWidth() or 620) - 8
    local y, heads, stats, notes = 0, 0, 0, 0

    local function head(text)
        heads = heads + 1
        local w = self:Row("head", heads)
        w:SetWidth(width)
        w.text:SetText(text)
        w:ClearAllPoints()
        w:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -y)
        y = y + 26
    end
    local function stat(label, value, conf)
        stats = stats + 1
        local w = self:Row("stat", stats)
        w:SetWidth(width)
        w.label:SetText(label)
        -- Нет значения - это «не знаю», а не прочерк: прочерк в словаре
        -- пустоты означает «такого не бывает» (см. ns.VOID), а здесь просто
        -- клиент промолчал.
        local text = value or U.void(ns.VOID.UNKNOWN)
        if conf and conf ~= ns.CONF.EXACT then
            text = text .. "  |cff808080(" .. (ns.CONF_LABEL[conf] or "?") .. ")|r"
        end
        w.value:SetText(text)
        w:ClearAllPoints()
        w:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -y)
        y = y + 18
    end
    local function note(text)
        notes = notes + 1
        local w = self:Row("note", notes)
        w:SetWidth(width)
        w:SetText(text)
        w:SetJustifyH("LEFT")
        w:SetWordWrap(true)
        w:ClearAllPoints()
        w:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -y)
        y = y + math.max(14, (w:GetStringHeight() or 12) + 4)
    end

    if not snap then
        head("Снимок персонажа ещё не сделан")
        note("Подождите секунду после входа в игру или нажмите «Обновить».")
        self.content:SetSize(width, math.max(1, y))
        return
    end

    -- Who ---------------------------------------------------------------
    head("Персонаж")
    stat("Имя", snap.name or U.void(ns.VOID.UNKNOWN))
    stat("Уровень", snap.level and tostring(snap.level) or "неизвестен",
        snap.level and ns.CONF.EXACT or ns.CONF.UNKNOWN)
    stat("Класс", snap.className or U.void(ns.VOID.UNKNOWN))
    -- Фракцию клиент отдаёт английским кодом («Horde»); на экране - по-русски.
    local FACTION = { Horde = "Орда", Alliance = "Альянс" }
    stat("Раса / фракция", (snap.raceName or U.void(ns.VOID.UNKNOWN)) .. " / "
        .. (FACTION[snap.factionFile or ""] or snap.factionFile or U.void(ns.VOID.UNKNOWN)))
    stat("Специализация", snap.spec or "не определена", snap.specConf)
    stat("Веса характеристик",
        (ns.StatWeights.SET_LABEL[snap.weightSetKey] or snap.weightSetKey or U.void(ns.VOID.UNKNOWN)),
        snap.weightConf)
    stat("Золото", U.money(snap.money, true), snap.moneyConf)

    if snap.weightConf ~= ns.CONF.EXACT then
        note("Веса характеристик — моя собственная оценка, не данные клиента."
            .. " Их можно переключить вручную в настройках.")
    end

    -- Professions ------------------------------------------------------
    head("Профессии")
    if #(snap.professions or {}) == 0 then
        note("Клиент не вернул ни одной профессии. Советы по крафту работать не будут.")
    end
    for _, prof in ipairs(snap.professions or {}) do
        local value
        if prof.skillBroken or not prof.skill then
            value = "|cffff8040уровень неизвестен|r"
        else
            -- The ceiling is whatever the client said, or nothing. An unknown
            -- maximum is spelled out rather than hidden behind a bare number:
            -- "225" and "225 из неизвестного максимума" lead to different
            -- decisions, and the player is the one making them.
            value = tostring(prof.skill)
            if prof.max and prof.max > 0 then
                value = value .. "/" .. prof.max
                if prof.skill >= prof.max then
                    value = value .. "  |cffffd100(на пределе)|r"
                end
            else
                value = value .. "  |cffff8040(максимум неизвестен)|r"
            end
        end
        if prof.gathering then value = value .. "  |cff808080(добыча)|r" end
        local bucket = ns.RecipeBook:Bucket(prof.name)
        if bucket then
            local learned = 0
            for _, r in ipairs(bucket.list) do if r.learned then learned = learned + 1 end end
            -- ФОРМЫ СДВИНУТЫ НАРОЧНО, И ЭТО НЕ ОПЕЧАТКА. Слово стоит после «из
            -- N», то есть в родительном падеже, а не в именительном: «из 1
            -- рецепта», «из 2 рецептов», «из 82 рецептов». Обычный набор
            -- («рецепт», «рецепта», «рецептов») дал бы «из 1 рецепт» - и
            -- Tests/test_sense.lua это ловит.
            value = value .. "  •  " .. learned .. " из " .. #bucket.list .. " "
                .. U.plural(#bucket.list, "рецепта", "рецептов", "рецептов")
        elseif prof.crafting then
            value = value .. "  •  |cffff8040рецепты не прочитаны|r"
        end
        -- Имя профессии - через U.profLabel: пока клиент молчит, оно приходит
        -- из чужого кеша по-английски.
        local profLabel = U.profLabel(prof.name) or "?"
        stat(profLabel, value, prof.conf)
        if prof.skillNote then note("   " .. profLabel .. ": " .. prof.skillNote) end

        -- Здесь была строка «потолок поднимался N раз, последний раз …». Её
        -- нет: числа в ней были ростом навыка, а не потолка (см.
        -- Api:MastercraftSkillHistory). Истории максимума у аддона нет.
    end
    -- ОТКУДА НАВЫК - СЛОВАМИ, А НЕ ИМЕНЕМ ФУНКЦИИ. Здесь печаталось
    -- «Источник данных о профессиях: C_SkillInfo.GetSkillLineInfoByID»: игроку
    -- это не говорит ничего, а важное в этой строке одно - из игры число или
    -- из чужой сохранёнки. Точное имя маршрута остаётся в диагностике.
    if snap.professions and snap.professions[1] and snap.professions[1].route then
        local route = tostring(snap.professions[1].route)
        if route:find("Mastercraft", 1, true) then
            note("Навык профессий взят из сохранённых данных Mastercraft: игра"
                .. " сейчас его не сообщила, так что число могло устареть.")
        else
            note("Навык профессий сообщила игра.")
        end
    end

    -- Recipes ----------------------------------------------------------
    head("Рецепты")
    local summary = ns.RecipeBook:Summary()
    if #summary == 0 then
        note("Ни одного рецепта не прочитано. Откройте окно любой профессии —"
            .. " игра отдаёт список только после этого.")
    end
    local SRC = { own = "прочитал сам", stored = "мой кеш", foreign = "кеш другого аддона" }
    for _, s in ipairs(summary) do
        local age = s.scanned and s.scanned > 0
            and U.ageText(ns.Api:ServerTime() - s.scanned) or nil
        stat(U.profLabel(s.name), s.learned .. " выучено из " .. s.total
            .. "  •  " .. (SRC[s.source] or s.source)
            .. (age and ("  •  " .. age) or ""), s.conf)
    end
    for _, prof in ipairs(ns.RecipeBook.missingProfessions or {}) do
        note("|cffff8040Нет данных по «" .. tostring(U.profLabel(prof.name))
            .. "» — откройте это окно профессии один раз.|r")
    end

    -- Equipment --------------------------------------------------------
    head("Экипировка и чары")
    local rows, total, conf = ns.GearAdvisor:Audit(snap)
    stat("Всё надетое вместе", U.benefit(total or 0), conf)
    local bare, empty = 0, 0
    for _, row in ipairs(rows) do
        local value
        if row.empty then
            value = "|cffff6060пусто|r"
            empty = empty + 1
        else
            value = row.name or "?"
            if row.score then
                value = value .. "  |cff808080(" .. U.benefit(row.score) .. ")|r"
            else
                value = value .. "  |cffff8040(характеристики не прочитаны)|r"
            end
            if row.enchantable then
                if row.enchantID then
                    -- НОМЕР ЧАРЫ ВИДЕН. «Чары есть» - это не ответ на вопрос
                    -- «какие чанты у меня есть»: по номеру игрок хотя бы
                    -- сопоставит строку с подсказкой предмета в игре. Что
                    -- именно даёт чара, по номеру не знает ни один
                    -- установленный аддон, поэтому ничего и не обещаем.
                    value = value .. "  |cff60c060чары есть (#"
                        .. tostring(row.enchantID) .. ")|r"
                else
                    value = value .. "  |cffffcc40без чар|r"
                    bare = bare + 1
                end
            end
        end
        stat(row.label, value, row.conf)
    end
    if bare > 0 then
        note(bare .. " " .. U.plural(bare, "слот", "слота", "слотов")
            .. " без чар — смотрите раздел «Советы».")
    end
    if empty > 0 then
        note(empty .. " " .. U.plural(empty, "слот пуст", "слота пусты", "слотов пусты") .. ".")
    end

    -- Materials --------------------------------------------------------
    head("Материалы")
    local bagCount = U.count(snap.bags)
    stat("В сумках", bagCount .. " " .. U.plural(bagCount, "вид", "вида", "видов")
        .. " предметов", snap.bagsConf)
    if snap.bank == nil then
        stat("В банке", "|cffff8040не видел — банк не открывали|r", ns.CONF.UNKNOWN)
        note("Пока я не видел банк, я считаю только сумки. Часть покупок"
            .. " из списка может быть лишней.")
    else
        local bankCount = U.count(snap.bank)
        stat("В банке", bankCount .. " " .. U.plural(bankCount, "вид", "вида", "видов"),
            snap.bankConf)
    end
    if snap.alts then
        for _, alt in ipairs(snap.alts) do
            if not alt.isSelf then
                stat("У " .. (alt.name or "?"),
                    U.count(alt.counts) .. " "
                        .. U.plural(U.count(alt.counts), "вид", "вида", "видов")
                        .. "  •  " .. U.money(alt.money),
                    snap.altsConf)
            end
        end
    else
        stat("Другие персонажи", "нет данных (Syndicator не загружен)", ns.CONF.UNKNOWN)
    end

    -- ПРОФЕССИИ ДРУГИХ ПЕРСОНАЖЕЙ -------------------------------------
    --
    -- Нужны тут по той же причине, по которой существует весь этот раздел: совет
    -- «эти профессии есть у другого персонажа» не должен быть чёрным ящиком.
    -- Syndicator профессий не хранит, поэтому это НЕ его данные - это своя
    -- запись (Logic/Roster.lua) о том, что аддон видел, пока этим персонажем
    -- играли, плюс чужой кеш запасным путём и с пометкой.
    -- Строки собирает Logic/Roster.lua: это утверждения о мире, и они обязаны
    -- быть проверяемы тестом, а нарисованное проверить нечем.
    local roster = ns.Roster and ns.Roster:OtherCharacterLines() or {}
    if #roster > 0 then
        head("Профессии других персонажей")
        for _, line in ipairs(roster) do
            stat(line.label, line.value, line.conf)
        end
        note("Это не данные Syndicator: профессий он не хранит. Я помню то, что"
            .. " видел сам, пока вы играли этим персонажем. Про того, кем при мне"
            .. " ещё не играли, я так и говорю — не знаю, а не «профессий нет».")
    end

    -- ОТКУДА ЧТО ВЗЯТО, ВСЁ В ОДНОМ МЕСТЕ -------------------------------
    --
    -- Аддон сшит из пяти источников с совершенно разной надёжностью, и до сих
    -- пор это было видно только по пометкам на отдельных карточках. Игрок не
    -- технический: если у него возникло сомнение, ответ должен лежать целиком и
    -- в одном месте - что знаю точно, что из вторых рук, чего не знаю вовсе и
    -- что с этим делать.
    head("Откуда я всё это знаю")
    if ns.Provenance then
        note(ns.Provenance:Headline())
        for _, row in ipairs(ns.Provenance:Rows()) do
            stat(row.label, row.source, row.conf)
            note("   " .. ns.Provenance:RowText(row))
        end
    end

    -- Цены подробнее: сколько ответов дал каждый источник за пересчёт.
    head("Откуда берутся цены")
    local ps = ns.ActionEngine.meta and ns.ActionEngine.meta.priceSources
    if ps then
        stat("Auctionator", ps.auctionatorAvailable and "загружен" or "|cffff8040нет|r")
        stat("Цен с аукциона", tostring(ps.auctionator or 0))
        stat("Из наблюдений", tostring(ps.foreign or 0))
        stat("Цены торговцев", tostring(ps.vendor or 0))
        stat("Грубые оценки", tostring(ps.estimate or 0))
        stat("Без цены", tostring(ps.unknown or 0))
    else
        note("Список ещё не строился.")
    end

    local meta = ns.Config:PriceHistoryMeta()
    stat("Своя история цен",
        (meta.items or 0) .. " " .. U.plural(meta.items or 0, "предмет", "предмета", "предметов")
        .. ", " .. (meta.days or 0) .. " " .. U.plural(meta.days or 0, "день", "дня", "дней"))
    note("Сервер открылся 4 ноября 2026 — истории цен нет ни у кого, и задним"
        .. " числом её не собрать. Я складываю по одной цене на предмет в день"
        .. " с первого запуска; в этой версии только копится, без анализа.")

    self.content:SetSize(width, math.max(1, y))
end

function Tab:OnShow() Tab:Render() end

return Tab
