-- ForeverPilot / Logic/ActionEngine.lua
--
-- The single ranked list. Craft, buy, enchant and sell all go into one pile and
-- are scored on the same scale, so the top card really is the next best thing
-- to do rather than the best thing within some category the player has to pick
-- first.
--
-- Scoring. Every card is reduced to five axes, each normalised to 0..1:
--   power  - weighted stat points gained
--   skill  - expected profession skill-ups
--   profit - gold expected to come in
--   spend  - gold that has to go out (always weighted negatively)
--   ready  - how much of what it needs is already in hand
-- The chosen profile supplies the weights, the card's data confidence scales
-- the result, and "setup" cards are pinned above everything because a list
-- built on missing data is worse than a list that says what is missing.
--
-- The normalisation scales are relative to the player's own wallet and kit, so
-- a 2-gold character is not told to go and spend 2 gold, and a 1-gold profit is
-- treated as significant for them even though it would be noise at level 60.
local ADDON, ns = ...

local U = ns.Util
local Api = ns.Api
local CONF = ns.CONF

local Engine = {}
ns.ActionEngine = Engine

-- Past this multiple of the player's gold, a purchase is not advice any more -
-- it is a wish. The gear branch coming alive surfaced a card asking for 167
-- gold of cloth from a character holding one gold, ranked above everything.
-- Three times the wallet is a stretch worth showing; more than that gets
-- demoted below the things they can actually do, and says why.
Engine.OUT_OF_REACH_RATIO = 3

Engine.cards = {}
Engine.meta = {}
-- Сколько пересчётов уже прошло. Нужно затем, что «список пуст» и «пересчёта
-- ещё не было» - разные утверждения, а выглядят одинаково: пустая таблица
-- карточек. Панель на этом и спотыкалась, объявляя «пока нечего советовать»
-- там, где правдой было «ещё считаю».
Engine.buildCount = 0
-- Cards a branch produced and the player's own dismissals swallowed. Kept
-- rather than dropped on the floor: twenty of these is how a working engine
-- ends up reporting "no branch produced anything".
Engine.hidden = {}
-- Per-branch "why nothing here", filled by the branch that came up empty.
Engine.branchNote = {}

local function nameOf(itemID)
    local info = Api:ItemInfo(itemID)
    return (info and info.name) or U.itemFallbackName(itemID)
end
Engine.nameOf = nameOf

-- Scales ----------------------------------------------------------------

function Engine:Scales(snap)
    local money = math.max(0, (snap and snap.money) or 0)
    -- A kit's total weighted score tells us what "a meaningful upgrade" means
    -- for this character: 5% of the current kit, floored so an empty kit still
    -- has a sane scale.
    local _, kitScore = ns.GearAdvisor:Audit(snap)
    local powerScale = math.max(4, (kitScore or 0) * 0.05)
    return {
        power  = powerScale,
        skill  = 1.0,
        profit = math.max(2000, money * 0.10),
        spend  = math.max(2000, money * 0.25),
        money  = money,
        kitScore = kitScore or 0,
    }
end

-- Card construction -----------------------------------------------------

local function blankAxes()
    return { power = 0, skill = 0, profit = 0, spend = 0, ready = 0 }
end

function Engine:Score(card, weights, profile)
    local a = card.axes or blankAxes()
    local w = weights or ns.PROFILE_WEIGHTS.POWER
    local raw = (w.power or 0) * (a.power or 0)
        + (w.skill or 0) * (a.skill or 0)
        + (w.profit or 0) * (a.profit or 0)
        + (w.spend or 0) * (a.spend or 0)
        + (w.ready or 0) * (a.ready or 0)
    -- Confidence scales the score rather than gating it: a well-evidenced
    -- small win should beat a guessed big one.
    local confFactor = 0.55 + 0.45 * U.confScore(card.conf or CONF.UNKNOWN)
    card.scoreRaw = raw
    card.score = raw * confFactor
    -- УСИЛЕНИЕ ПО ПРОФИЛЮ. Весами одного порядка мало: разница в полпункта на
    -- экране не читается как «профиль переключился». Множитель применяется к
    -- уже посчитанному результату и только к тем видам, которые этому профилю
    -- по смыслу ближе всего.
    local boost = profile and ns.PROFILE_BOOST
        and ns.PROFILE_BOOST[profile] and ns.PROFILE_BOOST[profile][card.kind]
    if boost then
        card.profileBoost = boost
        -- Отрицательные очки усиливать нельзя: это сделало бы убыточный совет
        -- ещё ниже в «Заработке», что выглядит как ошибка ранжирования.
        if card.score > 0 then card.score = card.score * boost end
    end
    return card.score
end

-- What this card actually asks the player to DO, as a string.
--
-- Two cards are the same advice when they would send the player to the same
-- recipe, the same item or the same vendor - regardless of the key the branch
-- that produced them happened to choose. That is the difference that mattered:
-- the duplicate "Льняные сапоги" cards did share a key, but a second recipe
-- producing the same item would not have, and it would have been just as much
-- of a repeat on screen.
function Engine:ActionIdentity(card)
    if type(card) ~= "table" then return nil end
    local act = card.action or {}
    local parts = { tostring(card.kind or "?") }
    if card.recipeID then
        parts[#parts + 1] = "r" .. tostring(card.recipeID)
    elseif act.recipeID then
        parts[#parts + 1] = "r" .. tostring(act.recipeID)
    end
    if card.itemID then parts[#parts + 1] = "i" .. tostring(card.itemID) end
    if card.slot then parts[#parts + 1] = "s" .. tostring(card.slot) end
    if card.profession then parts[#parts + 1] = "p" .. tostring(card.profession) end
    -- Nothing identifying at all: fall back to the key, so an informational
    -- card is still compared against itself and not against its neighbours.
    if #parts == 1 then parts[#parts + 1] = "k" .. tostring(card.key) end
    return table.concat(parts, "|")
end

function Engine:Add(card)
    if not card or not card.key then return nil end
    local now = Api:ServerTime()

    -- The same advice twice is never useful, and on the real character four of
    -- twelve rows were repeats. Both guards are here on purpose: the key guard
    -- catches a branch that ran twice over duplicated data, the identity guard
    -- catches two different sources of the same action.
    self.seenKeys = self.seenKeys or {}
    self.seenActions = self.seenActions or {}
    self.dupes = self.dupes or 0
    self.dupeDetail = self.dupeDetail or {}
    if self.seenKeys[card.key] then
        self.dupes = self.dupes + 1
        self.dupeKeyHits = (self.dupeKeyHits or 0) + 1
        if #self.dupeDetail < 5 then
            self.dupeDetail[#self.dupeDetail + 1] = {
                reason = "same-key", key = card.key, title = card.title,
            }
        end
        if ns.Diag then ns.Diag:Count("cards.duplicateKey") end
        return nil
    end
    local identity = self:ActionIdentity(card)
    if identity and self.seenActions[identity] then
        self.dupes = self.dupes + 1
        self.dupeActionHits = (self.dupeActionHits or 0) + 1
        if #self.dupeDetail < 5 then
            self.dupeDetail[#self.dupeDetail + 1] = {
                reason = "same-action", key = card.key, identity = identity,
                firstKey = self.seenActions[identity], title = card.title,
            }
        end
        if ns.Diag then ns.Diag:Count("cards.duplicateAction") end
        return nil
    end
    -- A card the UI refuses to hide cannot be "hidden by the player", so a
    -- stale dismissal left over from an earlier key does not apply to it.
    if not card.blocking then
        local dismissed, until_ = ns.Config:IsDismissed(card.key, now)
        if dismissed then
            -- Remembered, not discarded. Build() needs to know the list is
            -- empty because the player emptied it, not because there is
            -- nothing to say.
            self.hidden[#self.hidden + 1] = {
                key = card.key, kind = card.kind, title = card.title,
                until_ = until_,
            }
            return nil
        end
    end
    card.axes = card.axes or blankAxes()
    card.conf = card.conf or CONF.UNKNOWN

    -- Two honest labels the ranking and the UI both use, so a card that would
    -- leave the player poorer is never dressed up as a recommendation.
    local snap = ns.CharacterScanner and ns.CharacterScanner:Get() or nil
    local money = snap and snap.money or nil
    -- HOW FAR OUT OF REACH, not just whether. "Costs more than you have" is
    -- true of a 2-gold purchase with 1 gold in the bag and of a 167-gold one,
    -- and those are not the same advice. The ranking could not tell them apart
    -- either, because the spend axis saturates: U.soft(2g) and U.soft(167g)
    -- both sit near 1. So the ratio is kept and the tiering below uses it.
    if card.cost and money then
        if card.cost > money then card.unaffordable = true end
        card.affordRatio = U.div(card.cost, math.max(1, money), nil)
        if card.affordRatio and card.affordRatio > Engine.OUT_OF_REACH_RATIO then
            card.outOfReach = true
            -- Карточку сейчас опустят ниже всего, что игрок может сделать
            -- сегодня. Причина должна быть на самой карточке: совет про пояс
            -- из рунной ткани - самый выгодный в списке, а в строке «чего не
            -- хватает» стояло только «не хватает: Рунная ткань x3», и почему
            -- он внизу, было не видно. Покупка свою цифру пишет сама, поэтому
            -- дважды не повторяем.
            if not U.contains(card.need or "", "больше, чем у вас есть")
                and not U.contains(card.need or "", "Денег у вас сейчас нет") then
                card.need = Engine.JoinSentences(card.need,
                    Engine.OutOfReachText(card.cost, money, card.affordRatio))
            end
        end
    end
    if card.benefitValue and card.benefitValue < 0 then card.losesMoney = true end

    -- РИСК И ПРАВДОПОДОБИЕ, ОДИН РАЗ НА КАРТОЧКУ И ДО РАНЖИРОВАНИЯ.
    --
    -- Выгода без риска - половина правды, и ровно эту половину игрок уже
    -- прочитал. Здесь к карточке прикладывается требуемый капитал, риск
    -- отсутствия покупателя, риск цены и максимальный убыток; а если числа
    -- самой карточки друг другу противоречат (выручка 2з 66с при цене торговца
    -- 5м - расхождение в 5320 раз), карточка помечается сомнительной, её
    -- достоверность падает до «неизвестно» и предупреждение попадает в
    -- заголовок. Ничего не прячется: tierOf ниже опускает такую карточку под
    -- всё исполнимое, но с экрана не убирает.
    if ns.Risk then ns.Risk:Attach(card, snap) end

    self.seenKeys[card.key] = true
    if identity then self.seenActions[identity] = card.key end
    card.actionIdentity = identity

    self.cards[#self.cards + 1] = card
    return card
end

-- Branch: setup ---------------------------------------------------------
-- Mandatory, not optional. C_TradeSkillUI hands back nothing at all until the
-- player has opened that profession's window once in this session, so without
-- this card the Now tab would simply be wrong and the player would have no idea
-- why. One card per profession we have no recipes for, pinned to the top.

-- ОБЩЕЕ ОБЪЯСНЕНИЕ - ОДНОЙ СТРОКОЙ НА ВСЕ ТАКИЕ СОВЕТЫ, А НЕ В КАЖДОМ.
--
-- Эти два абзаца про ограничение игры одинаковы для любой профессии, и у игрока
-- профессий две-три. На экране «Сейчас» при входе в игру из-за этого стояли
-- подряд две карточки с ОДНИМ И ТЕМ ЖЕ текстом в 140 символов - второй раз он
-- не сообщал ничего. Теперь он уезжает в `aboveList`: строка над списком, одна
-- на все такие советы (UI/Card.lua, Card.ActionNote сворачивает одинаковые), а
-- в самой карточке остаётся то, что относится к ЕЁ профессии.
--
-- Это тот же приём, которым уже убрана повторявшаяся инструкция про окно
-- профессий из подсказок (см. Tests/test_nonsense.lua).
Engine.SETUP_NOTE_RECIPES = "Игра не отдаёт список рецептов, пока окно профессии"
    .. " не открыли хотя бы раз за сессию — до этого считать мне нечего."
Engine.SETUP_NOTE_SKILL = "Шанс прироста навыка я беру из цвета рецепта — он от"
    .. " сообщённого числа не зависит, поэтому советы «на навык» остаются верными."

function Engine:AddSetupCards(snap)
    local missing = ns.RecipeBook.missingProfessions or {}
    for _, prof in ipairs(missing) do
        if prof.crafting then
            local label = tostring(U.profLabel(prof.name))
            self:Add({
                key = "setup:prof:" .. tostring(prof.name),
                kind = ns.KIND.SETUP,
                pinTop = true,
                icon = ns.KIND_ICON.SETUP,
                title = "Откройте окно: " .. label,
                benefit = "нужно 1 раз",
                benefitKind = "setup",
                why = "Окно «" .. label .. "» в этот заход ни разу не открывали,"
                    .. " поэтому я не знаю, что вы в ней умеете делать.",
                aboveList = Engine.SETUP_NOTE_RECIPES,
                need = "Откройте «" .. label .. "» в книге профессий"
                    .. " — я прочитаю список сам и запомню его до следующего входа.",
                action = { kind = "openProfession", label = "Понятно", profession = prof.name },
                conf = CONF.EXACT,
                axes = blankAxes(),
                blocking = true,
            })
        end
    end

    -- A profession whose skill level came back as zero while we hold recipes
    -- for it: tell the player we are ignoring the zero rather than acting on it.
    for _, prof in ipairs(snap.professions or {}) do
        if prof.skillBroken and ns.RecipeBook:HasProfession(prof.name) then
            self:Add({
                key = "setup:skill:" .. tostring(prof.name),
                kind = ns.KIND.SETUP,
                pinTop = true,
                icon = ns.KIND_ICON.SETUP,
                title = "Уровень навыка неизвестен: " .. tostring(U.profLabel(prof.name)),
                benefit = "не блокирует",
                benefitKind = "setup",
                -- Здесь стояло «…и не считаю прирост навыка для этой профессии»,
                -- а строкой ниже в том же списке стоял совет «На навык» по ней
                -- же. Совет честный: шанс прироста берётся из цвета рецепта и
                -- от этого числа не зависит. Неправдой была эта фраза.
                --
                -- А потом оказалось, что обе строки - и эта, и «чего не
                -- хватает» - НЕ НАЗЫВАЛИ ПРОФЕССИЮ, и при двух профессиях с
                -- нулевым навыком экран показывал два совета с дословно
                -- одинаковыми абзацами. Общая часть ушла в `aboveList`.
                why = "По «" .. tostring(U.profLabel(prof.name)) .. "» клиент"
                    .. " сообщил навык 0, хотя рецепты по ней есть. Нулю я не верю:"
                    .. " сколько осталось до максимума, сказать не могу.",
                aboveList = Engine.SETUP_NOTE_SKILL,
                need = "Откройте окно «" .. tostring(U.profLabel(prof.name))
                    .. "» — там число настоящее,"
                    .. " и советы по прокачке снова станут точными.",
                action = { kind = "openProfession", label = "Понятно", profession = prof.name },
                conf = CONF.ESTIMATE,
                axes = blankAxes(),
            })
        end
    end

    -- No bank data at all.
    if snap.bank == nil and ns.Config:Get().show.includeBank then
        local anyPlanNeedsIt = true
        if anyPlanNeedsIt then
            self:Add({
                key = "setup:bank",
                kind = ns.KIND.SETUP,
                icon = ns.KIND_ICON.SETUP,
                title = "Банк я ещё не видел",
                benefit = "возможно, покупать не нужно",
                benefitKind = "setup",
                why = "Я считаю только сумки. Если материалы лежат в банке,"
                    .. " часть покупок из списка может оказаться лишней.",
                need = "Зайдите к банкиру и откройте банк один раз.",
                action = { kind = "noop" },
                conf = CONF.EXACT,
                axes = { power = 0, skill = 0, profit = 0, spend = 0, ready = 0.2 },
            })
        end
    end

    if not ns.PriceProvider:AuctionatorEnabled() then
        self:Add({
            key = "setup:auctionator",
            kind = ns.KIND.SETUP,
            icon = ns.KIND_ICON.SETUP,
            title = "Цен с аукциона нет",
            benefit = "работаю без них",
            benefitKind = "setup",
            why = "Auctionator не загружен, поэтому рыночных цен я не знаю."
                .. " Советы по силе и навыку работают как обычно, а всё,"
                .. " что про деньги, помечено как «неизвестно».",
            need = "Включите Auctionator, если хотите видеть цены и прибыль.",
            action = { kind = "noop" },
            conf = CONF.EXACT,
            axes = blankAxes(),
        })
    end
end

-- Branch: the player hid everything ------------------------------------
--
-- Dismissing a card hides it for a day. Dismiss enough of them and an engine
-- that is working perfectly has nothing left to show, which is exactly what
-- happened on the real character: every key a branch could produce was sitting
-- in ForeverPilotDB.dismissed, so the Now tab said "0 советов" and the
-- diagnostics said "no branch produced anything". Both were true and neither
-- was the reason.
--
-- So an empty list plus hidden cards is never left empty: one card says what
-- happened, how long it lasts, and offers to undo it. It is marked blocking,
-- because a card whose whole job is to explain the empty list must not be the
-- next thing the player dismisses.

function Engine:HiddenSummary()
    local seen, count, soonest = {}, 0, nil
    for _, h in ipairs(self.hidden or {}) do
        if h.key and not seen[h.key] then
            seen[h.key] = true
            count = count + 1
            if h.until_ and ((not soonest) or h.until_ < soonest) then
                soonest = h.until_
            end
        end
    end
    return count, soonest
end

function Engine:AddHiddenCard()
    local count, soonest = self:HiddenSummary()
    if count == 0 then return 0 end

    local backIn
    if soonest then
        local left = soonest - Api:ServerTime()
        if left > 0 then backIn = U.durationText(left) end
    end

    local kinds = {}
    for _, h in ipairs(self.hidden or {}) do
        local label = ns.KIND_LABEL[h.kind] or h.kind
        if label and not kinds[label] then kinds[label] = true end
    end
    local kindList = {}
    for label in pairs(kinds) do kindList[#kindList + 1] = label end
    table.sort(kindList)

    self:Add({
        key = "hidden:restore",
        kind = ns.KIND.SETUP,
        pinTop = true,
        blocking = true,
        icon = ns.KIND_ICON.SETUP,
        title = "Скрытых советов: " .. count,
        benefit = "список пуст из-за этого",
        benefitKind = "setup",
        -- ТЕКСТ НАЗЫВАЕТ РОВНО ТО, ЧТО ЕСТЬ, И РОВНО ТЕ СРОКИ, КОТОРЫЕ В КОДЕ.
        --
        -- Ошибок в этих двух строках было уже три. Первая: текст называл кнопку
        -- «Понятно», которой на этом экране может не быть вовсе — когда скрыто
        -- всё, в списке стоит одна эта карточка, и единственная кнопка на ней
        -- называется «Вернуть все». Вторая: «прячется на сутки» — это срок
        -- скрытия в списке, а на час прячет панель, то есть один срок назывался
        -- за два разных действия. Третья: «кнопка на самом совете — на час» —
        -- такой кнопки на экране не было никогда; на час прятали «Дальше» и
        -- левый щелчок по информационному совету, и оба больше ничего не прячут.
        --
        -- Теперь назван единственный способ спрятать совет - два правых щелчка -
        -- и оба места, где он работает, каждое со своим сроком. (Панель раньше
        -- прятала с одного щелчка; с тех пор и там нужно два.)
        why = "Советы есть — все " .. count .. " вы скрыли сами."
            .. " Два правых щелчка по совету прячут его: в списке — на "
            .. (U.durationText(ns.DISMISS_SECONDS) or "сутки")
            .. ", на панели — на "
            .. (U.durationText(ns.SNOOZE_SECONDS) or "час") .. "."
            .. ((#kindList > 0) and (" Скрыто: " .. table.concat(kindList, ", ") .. ".") or ""),
        need = "Нажмите «Вернуть все» — или наберите /fp show."
            .. (backIn and (" Первые вернутся сами через " .. backIn .. ".") or ""),
        action = { kind = "undismiss", label = "Вернуть все" },
        conf = CONF.EXACT,
        axes = blankAxes(),
        hiddenCount = count,
    })
    return 1
end

-- Branch: gear upgrades -------------------------------------------------
-- Level and class restrictions apply here in full: this is the list of things
-- the player can actually put on.

-- ПОЧЕМУ ВЕТКИ ПО ВЕЩАМ МОЛЧАТ БЕЗ ПРОФИЛЯ - ОДНИМ ОТВЕТОМ НА ТРИ ВЕТКИ.
--
-- Весов нет только в одном случае: класс персонажа моим данным незнаком (или
-- клиент его ещё не назвал). Раньше в этом случае бралcя кастерский набор, и
-- экипировка оценивалась по чужому классу - а карточка выглядела обычной.
-- Теперь веток три и молчат они все, поэтому и причина одна.
local function noProfileNote(snap)
    if snap and snap.weights then return nil end
    local reason = ns.StatWeights and ns.StatWeights.NoProfileReason
        and ns.StatWeights:NoProfileReason(snap and snap.weightSource,
            snap and snap.classFile) or nil
    return reason
        or "весов характеристик для вашего класса у меня нет, а оценивать вещи"
        .. " чужими весами я не буду"
end

function Engine:AddGearCards(snap, scales)
    if not (snap and snap.weights) then
        self.branchNote.gear = noProfileNote(snap)
        return 0
    end
    local upgrades = ns.GearAdvisor:Upgrades(snap, ns.CraftingPlanner)
    local added = 0
    for _, up in ipairs(upgrades) do
        if added >= ns.MAX_CARDS_PER_KIND then break end
        added = added + 1

        local plan = up.plan
        local axes = blankAxes()
        -- With no readable comparison there is no gain to normalise, so the
        -- power axis carries the item's own worth at a deliberately modest
        -- scale and the confidence factor demotes the card further.
        if up.gain then
            axes.power = U.soft(up.gain, scales.power)
        else
            axes.power = 0.5 * U.soft(up.newScore or 0, scales.power)
        end
        axes.ready = plan and plan.readiness or 0
        axes.spend = plan and plan.cost and U.soft(plan.cost, scales.spend) or 0
        local skillChance = ns.CraftingPlanner:SkillChance(up.recipe)
        axes.skill = U.soft(skillChance, scales.skill)

        local slotLabel = ns.SlotMap:Label(up.targetSlot)
        -- ItemLabel, not the bare name. "Расшитый безупречный венец" is two
        -- different items on this character - 253975 and 253979 - and the one
        -- they are wearing is one of them. A sentence that names only the word
        -- cannot say which.
        -- С ЧЕМ СРАВНИВАЛИ, ТО И НАЗЫВАЕМ. Сравнение идёт с лучшим из того, что
        -- у игрока есть на слот (см. GearAdvisor:OwnedFloor), а имя брали у
        -- надетого - и когда планку задавала вещь из сумки, подпись не
        -- совпадала с числом.
        local currentName, currentWhere
        local slotItem = ns.GearAdvisor:SlotItem(up.targetSlot, snap, snap.weights)
        if up.betterOwned and up.betterOwned.itemID then
            currentName = up.betterOwned.label
                or ns.GearAdvisor:ItemLabel(up.betterOwned.itemID)
            currentWhere = up.betterOwned.where
        elseif slotItem and slotItem.itemID then
            currentName = slotItem.label or ns.GearAdvisor:ItemLabel(slotItem.itemID)
            currentWhere = slotItem.where
        end
        if currentWhere == "bags" then
            currentName = currentName .. " (из сумки)"
        elseif currentWhere == "bank" then
            currentName = currentName .. " (из банка)"
        end
        local candidateName = ns.GearAdvisor:ItemLabel(up.info.itemID)

        -- The unit comes from Core/Const.lua and from nowhere else: it used to
        -- read "ед. силы", which named Strength - the one stat an arcane mage
        -- has no use for - for a number that is actually a weighted sum over
        -- this character's own stat weights. Печатает его U.benefit, потому что
        -- слово склоняется: «1 балл», «2 балла», «5 баллов».
        local why, benefit
        if up.compare == "school-unknown" then
            -- Not "I cannot read the stats" - a different and more specific
            -- answer: the stats are readable, but which school of magic this
            -- character actually casts is not, and that is precisely what
            -- decides whether this is an upgrade.
            benefit = "школа не определена"
            why = "Слот «" .. slotLabel .. "»: тут в деле школьная магия, а какая"
                .. " школа у вас основная, я не понял — ни специализация, ни"
                .. " надетые вещи не сказали однозначно. Поэтому «лучше» или"
                .. " «хуже» я утверждать не буду: у этой вещи "
                .. U.benefit(up.newScore or 0)
                .. ", у надетой " .. U.benefit(up.currentScore or 0)
                .. " при равных шансах по школам."
            if up.compareDetail and up.compareDetail.mainFrom ~= up.compareDetail.mainTo then
                why = why .. string.format(" Сила магии: %d -> %d.",
                    up.compareDetail.mainFrom, up.compareDetail.mainTo)
            end
        elseif up.compare ~= "exact" then
            benefit = "сравнить не могу"
            why = "Слот «" .. slotLabel .. "»: характеристики надетой вещи"
                .. (currentName and (" («" .. currentName .. "»)") or "")
                .. " клиент не отдаёт, поэтому сказать «лучше» я не могу."
                .. " У этой вещи " .. U.benefit(up.newScore or 0)
                .. " по вашим весам — сравните сами."
        elseif currentName then
            benefit = U.benefitDelta(up.gain)
            why = "Слот «" .. slotLabel .. "»: лучше, чем " .. currentName
                .. ", на " .. U.benefit(up.gain) .. "."
            if up.displacedSlots and #up.displacedSlots > 1 then
                why = why .. " Считал обе руки: двуручное снимает и левую."
            end
        else
            benefit = U.benefitDelta(up.gain)
            why = "Слот «" .. slotLabel .. "» пустой — любая вещь лучше, чем ничего."
        end
        -- WHAT GOES DOWN, SAID OUT LOUD. A single total hid the one thing the
        -- player needed to know: the robe the addon recommended traded away 11
        -- points of arcane damage - the whole point of an arcane mage - for
        -- generic spell power and 22 points of healing he cannot use, and the
        -- card printed "+16 ед. пользы" and nothing else. He crafted it.
        local cmp = up.compareDetail
        if cmp then
            -- The main stat group first and always, because that is the thing
            -- the player is actually trading. "13 → 20 силы магии по тайной
            -- школе" is the sentence that was missing.
            if cmp.mainFrom ~= cmp.mainTo then
                why = why .. string.format(" %s: %d -> %d.",
                    U.capitalize(ns.GearAdvisor:MainGroupLabel(
                        snap and snap.weightSetKey)),
                    cmp.mainFrom, cmp.mainTo)
            end
            local other = {}
            for _, l in ipairs(cmp.losses) do
                if not l.main then
                    other[#other + 1] = string.format(ns.GLYPH.MINUS .. "%d %s",
                        math.abs(l.delta), l.label)
                end
            end
            if #other > 0 then
                why = why .. " Но просадки: "
                    .. table.concat(other, ", ", 1, math.min(3, #other))
                    .. ((#other > 3) and (" и ещё " .. (#other - 3)) or "") .. "."
            end
        end
        -- And when several variants of the same item exist, which one this is.
        if up.family and up.family.text then
            why = why .. " " .. up.family.text
        end
        if up.free then
            why = why .. " Материалы ничего не стоят: всё уже в сумках."
        elseif up.gainPerGold and plan and plan.cost and plan.cost >= 10000 then
            -- «За золотой» - только когда вещь стоит золотой и больше. У плаща
            -- за 6с получалось «142.0 ед. пользы за золотой»: число из деления
            -- на шесть сотых золотого, при том что всей пользы там девять.
            -- Согласование числа и слова - у U.benefitRate: дробное число
            -- требует «балла», целое - «балл/балла/баллов».
            why = why .. " Это " .. U.benefitRate(up.gainPerGold) .. " за золотой."
        end

        local card = self:Add({
            key = "gear:" .. up.recipe.id,
            kind = ns.KIND.CRAFT_GEAR,
            icon = up.info.texture or ns.KIND_ICON.CRAFT_GEAR,
            title = "Скрафтить: " .. candidateName,
            benefit = benefit,
            benefitKind = "power",
            benefitValue = up.gain,
            why = why,
            need = ns.CraftingPlanner:MissingText(plan, nameOf),
            action = {
                -- ЭТО НЕ КНОПКА. Вид действия «findRecipe» означает «совет про
                -- рецепт, который игрок открывает САМ»: окно профессий игра
                -- аддонам открывать запрещает (Core/Api.lua). Экран рисует
                -- вместо кнопки строку «откройте такую-то профессию и найдите
                -- такой-то рецепт» - поэтому подписи у действия нет.
                kind = "findRecipe",
                recipeID = up.recipe.id, itemID = up.info.itemID,
            },
            link = up.info.link,
            itemID = up.info.itemID,
            recipeID = up.recipe.id,
            plan = plan,
            cost = plan and plan.cost or nil,
            conf = up.conf,
            axes = axes,
            -- Carried for the diagnostics and the sanity checks: which stats
            -- went down, whether the profile's own stat is one of them, and
            -- which school variant this is.
            compareDetail = up.compareDetail,
            statLosses = up.compareDetail and up.compareDetail.losses or nil,
            mainStatDrop = up.compareDetail and up.compareDetail.mainStatDrop or nil,
            family = up.family,
        })
        -- ПО КАКОМУ РЕЦЕПТУ УЖЕ ЕСТЬ СОВЕТ «СКРАФТИТЬ И НАДЕТЬ».
        --
        -- Нужно ветке «на продажу», которая идёт следом: тот же рецепт она
        -- рассматривает заново и своими числами, и до этой записи обе ветки
        -- выдавали по карточке на один и тот же предмет - «надеть» и
        -- «продать», - причём ни одна про другую не знала. На скриншоте из
        -- игры это «Теневые очки» дважды. Решение - в FoldSellIntoGear.
        --
        -- ЗАПИСЬ ПОЯВЛЯЕТСЯ И ТОГДА, КОГДА КАРТОЧКУ НЕ ВЗЯЛИ (false). Взять её
        -- могли не взять по одной причине - игрок её скрыл; и тогда выдать ту
        -- же вещь карточкой «на продажу» значило бы вернуть скрытый совет в
        -- другой одежде. Этого в аддоне не делают нигде (см. Logic/Dismissal.lua).
        self.gearByRecipe = self.gearByRecipe or {}
        self.gearByRecipe[up.recipe.id] = card or false
    end
    if added == 0 then
        self.branchNote.gear = ns.GearAdvisor:LossReason(ns.GearAdvisor.lastStats)
            or "среди ваших рецептов нет надеваемой вещи лучше текущей"
    end
    return added
end

-- ОДНА ВЕЩЬ - ОДИН СОВЕТ, ДАЖЕ КОГДА С НЕЙ МОЖНО СДЕЛАТЬ ДВА РАЗНЫХ ДЕЛА.
--
-- Надеть и продать - взаимоисключающие действия над одним предметом, и две
-- карточки про них рядом не помогают выбрать, а спорят друг с другом: игрок
-- читает «скрафтить и надеть» и «на продажу» про те же «Теневые очки» и видит
-- аддон, который сам с собой не согласен. Ни одна из двух карточек при этом не
-- была неправдой - неправдой было их молчание друг о друге.
--
-- Поэтому карточка остаётся одна, та, которая уже построена веткой экипировки,
-- и она НАЗЫВАЕТ ОБА ВАРИАНТА с числами: сколько даёт надеть (баллы) и сколько
-- даёт продать (золото). Выбор за игроком - это ровно тот случай, где аддон не
-- имеет права выбирать за него: баллы и золото несравнимы, и что важнее,
-- решает он.
--
-- `sell` - карточка «на продажу», уже собранная, но ещё не добавленная в
-- список; `c` - её расчёт (маржа, выручка, партия).
function Engine:FoldSellIntoGear(gear, sell, c)
    if not (gear and sell) then return end

    -- Число строится заново, а не берётся подписью с карточки продажи: та
    -- подпись самостоятельна («оценка ~4с 26м», «+1з 90с за стопку»), и внутри
    -- фразы она читается как сломанная грамматика. Пометка «оценка» при этом
    -- не теряется - она становится знаком «~» перед суммой, тем же, которым
    -- аддон помечает все свои оценки (ns.ESTIMATE_MARK).
    local margin = tonumber(sell.benefitValue) or 0
    local mark = sell.priceSoft and ns.ESTIMATE_MARK or ""
    local money = mark .. U.money(margin)
        .. (((tonumber(sell.outputQty) or 1) > 1) and " за крафт" or "")

    -- В столбце выгоды - оба варианта. Это единственное место, которое игрок
    -- читает, не наводя мышь, поэтому второй вариант обязан быть здесь.
    gear.benefit = tostring(gear.benefit or "") .. " / продать за " .. money
    gear.why = Engine.JoinSentences(gear.why,
        "С этой вещью можно и иначе: не надевать, а продать — прибыль "
        .. money .. " при выручке "
        .. (c and c.revenue and U.money(c.revenue) or U.void(ns.VOID.NO_PRICE))
        .. " за штуку. Надеть или продать — выбирать вам: надетая вещь даёт"
        .. " баллы, проданная — золото, и одно исключает другое.")
    -- И ОЧКИ ЗА ДЕНЬГИ КАРТОЧКА ЗАБИРАЕТ СЕБЕ ТОЖЕ.
    --
    -- Иначе выгодный крафт, который заодно чуть лучше надетого, провалился бы
    -- вниз списка в профиле «Заработок»: до свёртки по деньгам его ранжировала
    -- отдельная карточка «на продажу», а после - никто. Ось берётся готовой у
    -- свёрнутой карточки: она посчитана тем же масштабом этого же пересчёта,
    -- так что второй раз считать (и разойтись в числах) не нужно.
    gear.axes = gear.axes or {}
    local sellProfit = (sell.axes and sell.axes.profit) or 0
    if sellProfit > (gear.axes.profit or 0) then gear.axes.profit = sellProfit end

    -- ПРЕДУПРЕЖДЕНИЕ ПРО ОБЛИК ПЕРЕЕЗЖАЕТ ВМЕСТЕ СО ВТОРЫМ ВАРИАНТОМ.
    --
    -- Надеть вещь безопасно: надетая привязывается, и облик с неё записывается
    -- сам. Опасен ровно второй вариант - «продать», - и раз он теперь назван
    -- здесь, то и предупреждение обязано стоять здесь же. Иначе оно пропало бы
    -- вместе со свёрнутой карточкой, причём именно у той вещи, которую игрок
    -- уже собрался продать.
    if sell.looks then Engine.ApplyLooks(gear, sell.looks, true) end

    -- Для подсказки, диагностики и проверок: что именно за второй вариант.
    gear.alsoSell = {
        key = sell.key, benefit = money,
        revenue = c and c.revenue or nil,
        margin = margin,
        soft = sell.priceSoft or nil,
        outputQty = sell.outputQty,
        looks = sell.looks,
    }
    if ns.Diag then ns.Diag:Count("cards.sellFoldedIntoGear") end
end

-- Branch: equip what you already own ------------------------------------
--
-- Самый дешёвый совет, который аддон вообще может дать: ничего не покупать,
-- ничего не крафтить, просто надеть то, что уже лежит в сумке. Появился из
-- живой находки - игрок надел удочку порыбачить, и аддон принялся советовать
-- ему оружие, хотя оружие у него было.
function Engine:AddEquipCards(snap, scales)
    if not (snap and snap.weights) then
        self.branchNote.equip = noProfileNote(snap)
        return 0
    end
    local swaps = ns.GearAdvisor:EquipSwaps(snap, snap and snap.weights)
    local added = 0
    for _, sw in ipairs(swaps) do
        if added >= ns.MAX_CARDS_PER_KIND then break end
        added = added + 1

        local axes = blankAxes()
        axes.power = U.soft(sw.gain, scales.power)
        -- Ничего не стоит и делается сразу: это и есть полная готовность.
        axes.ready = 1
        axes.spend = 0

        local slotLabel = ns.SlotMap:Label(sw.slot)
        local whereText = (sw.where == "bank") and "в банке" or "в сумке"
        local why
        if sw.toolReplaced then
            why = "В слоте «" .. slotLabel .. "» у вас инструмент"
                .. (sw.wornLabel and (" («" .. sw.wornLabel .. "»)") or "")
                .. " — для боя он ничего не даёт. А " .. whereText
                .. " лежит «" .. tostring(sw.label) .. "»: это "
                .. U.benefit(sw.gain) .. "."
        elseif sw.wornLabel then
            why = "Слот «" .. slotLabel .. "»: то, что лежит " .. whereText
                .. ", лучше надетого «" .. sw.wornLabel .. "» на "
                .. U.benefit(sw.gain) .. "."
        else
            why = "Слот «" .. slotLabel .. "» пустой, а " .. whereText
                .. " лежит «" .. tostring(sw.label) .. "»: "
                .. U.benefit(sw.gain) .. "."
        end
        if sw.displacedSlots and #sw.displacedSlots > 1 then
            why = why .. " Считал обе руки: двуручное снимает и левую."
        end

        local need
        if sw.where == "bank" then
            need = "Лежит в банке — заберите и наденьте. Я ничего не надеваю сам."
        else
            need = "Всё уже в сумках. Наденьте сами: я экипировкой не управляю."
        end

        local info = ns.Api:ItemInfo(sw.link or sw.itemID)
        self:Add({
            key = "equip:" .. tostring(sw.slot) .. ":" .. tostring(sw.itemID),
            kind = ns.KIND.EQUIP,
            icon = (info and info.texture) or ns.KIND_ICON.EQUIP,
            title = "Надеть: " .. tostring(sw.label),
            benefit = U.benefitDelta(sw.gain),
            benefitKind = "power",
            benefitValue = sw.gain,
            why = why,
            need = need,
            action = { kind = "showItem", label = "Показать предмет",
                       itemID = sw.itemID, link = sw.link },
            link = sw.link,
            itemID = sw.itemID,
            cost = 0,
            conf = sw.conf,
            axes = axes,
            equipSwap = sw,
        })
    end
    if added == 0 then
        self.branchNote.equip =
            "в сумках и банке нет вещи лучше той, что надета"
    end
    return added
end

-- Branch: enchants ------------------------------------------------------

-- Что формула даёт этому персонажу - теми числами, которые у нас есть.
--
-- ЧИСЛА ЗДЕСЬ НЕ ВЫДУМАНЫ И НЕ ПРО «СКОЛЬКО ПРИБАВИТ». Сколько именно даёт
-- чара, не знает ни клиент, ни одна установленная база (почему - написано над
-- Enchant:SkillNeeded). Поэтому на карточке стоят только те числа, которые
-- действительно известны: вес характеристики по профилю игрока, порог навыка
-- формулы, цена реагентов и чего из них не хватает.
local function enchantGainText(s)
    local parts = {}
    if s.statText then
        local line = "Даёт прирост " .. s.statText
        if s.usefulness and s.usefulness > 0 then
            line = line .. " — вес " .. string.format("%.2f", s.usefulness)
                .. " по вашему профилю"
        else
            line = line .. " — по вашему профилю это ноль"
        end
        parts[#parts + 1] = line
    else
        parts[#parts + 1] = "Что именно она даёт, из названия не читается,"
            .. " и выдумывать я не буду"
    end
    if s.skillNeeded then
        parts[#parts + 1] = "Порог формулы — навык " .. s.skillNeeded
            .. (s.skillHave and (", у вас " .. s.skillHave) or "")
    end
    return table.concat(parts, ". ") .. "."
end

-- ОН САМ ЗАЧАРОВАТЕЛЬ, И СОВЕТ ОБЯЗАН ЭТО УЧИТЫВАТЬ. Формулу он знает, значит
-- покупать свиток ему не надо - надо иметь реагенты и наложить самому. Поэтому
-- выгода карточки говорит про реагенты, а не про цену чужой услуги.
local function enchantReagentText(s)
    if s.ready then
        return "Реагенты есть — формула ваша, накладываете сами."
    end
    if s.cost then
        return "Реагенты надо докупить на " .. U.money(s.cost)
            .. " — свиток покупать не нужно, формула ваша."
    end
    return "Цену реагентов я посчитать не смог — часть цен неизвестна."
end

function Engine:AddEnchantCards(snap, scales)
    if not (snap and snap.weights) then
        self.branchNote.enchant = noProfileNote(snap)
        return 0
    end
    local advice = ns.EnchantAdvisor:Advise(snap, ns.CraftingPlanner)
    local added = 0
    -- Keyed by card key so the sanity checks can ask "was there a better
    -- formula for this slot?" without recomputing anything.
    self.enchantByCardKey = {}
    -- Сперва пустые слоты, потом занятые: пустой слот - это дырка, а занятый -
    -- это вопрос «а нельзя ли лучше», и на него у нас нет полного ответа.
    local queue = {}
    for _, s in ipairs(advice.bare) do queue[#queue + 1] = s end
    -- ЗАНЯТЫЕ СЛОТЫ В КАРТОЧКИ НЕ ИДУТ.
    --
    -- Живая жалоба (маг 31 ур., 2026-11-21): «Чары: Чары для двуручного
    -- оружия: малый интеллект» на посох, где у игрока уже стоит «Откровение» -
    -- чары заведомо сильнее. Карточка честно писала «лучше или хуже я не
    -- утверждаю», но стояла в списке СОВЕТОВ, с ценой реагентов и кнопкой, и
    -- читалась как совет перекрыть. От уже наложенных чар игра отдаёт только
    -- номер, сравнить мне нечем - значит и советовать нечего.
    --
    -- Сведения не теряются: какие слоты зачарованы, говорит сводная карточка
    -- ниже («Уже зачарованы: …»), и туда же дописано, что перекрывать их я не
    -- советую. EnchantAdvisor:Replacements по-прежнему отдаёт этот список.
    local replaceSkipped = #(advice.replace or {})
    if replaceSkipped > 0 and ns.Diag then
        ns.Diag:Count("enchant.replaceNotAdvised", replaceSkipped)
    end
    for _, s in ipairs(queue) do
        if added >= ns.MAX_CARDS_PER_KIND then break end
        added = added + 1
        self.enchantByCardKey["ench:" .. s.recipe.id .. ":" .. s.slot] = s

        local axes = blankAxes()
        -- An enchant's actual numbers are not readable from the recipe, so no
        -- number is claimed. An empty enchantable slot is a real, known gap;
        -- how much the card is worth depends on whether the formula gives this
        -- character something it cares about, which we read out of its name.
        if s.usefulness == nil then
            axes.power = 0.30
        elseif s.usefulness <= 0 then
            axes.power = 0.05
        else
            axes.power = U.clamp(0.20 + 0.45 * s.usefulness, 0, 0.75)
        end
        -- Занятый слот стоит ниже пустого: там мы перекрываем неизвестное.
        if s.occupied then axes.power = axes.power * 0.5 end
        axes.ready = s.plan and s.plan.readiness or 0
        axes.spend = s.cost and U.soft(s.cost, scales.spend) or 0

        -- ГДЕ ЛЕЖИТ ВЕЩЬ, А НЕ ТОЛЬКО ЕЁ ИМЯ. Пока ветка чар смотрела только на
        -- тело, карточка писала «Слот «Правая рука» без чар (Большая железная
        -- удочка)» - предлагала зачаровать удочку. Теперь предмет слота может
        -- лежать в сумке, и это обязано быть сказано.
        local where = ""
        if s.inBag then
            where = (s.where == "bank") and " — он в банке" or " — он в сумке"
        end
        local why
        if s.occupied then
            -- ЧТО СТОИТ СЕЙЧАС - ТОЛЬКО НОМЕР, И ЭТО СКАЗАНО ПРЯМО.
            why = "Слот «" .. s.label .. "» (" .. s.equippedName .. where
                .. "): чары на нём уже есть, но игра отдаёт от них только"
                .. " номер (#" .. tostring(s.currentEnchantID) .. "),"
                .. " поэтому «лучше» или «хуже» я не утверждаю."
                .. " Лучшая из ваших формул на этот слот — эта. "
                .. enchantGainText(s)
                .. " Наложение перекроет то, что стоит сейчас."
        else
            why = "Слот «" .. s.label .. "» без чар (" .. s.equippedName
                .. where .. "). " .. enchantGainText(s)
        end
        if s.usefulness and s.usefulness <= 0 then
            why = why .. " Эта формула вашему классу почти ничего не даёт,"
                .. " но других на этот слот вы не знаете."
        end
        -- ГДЕ ЭТО НАСТРАИВАЕТСЯ - НЕ В СОВЕТЕ.
        --
        -- Здесь стояло «Слот определён по категории рецепта — поправьте в
        -- настройках, если мимо». Сам факт нужен: слот не прочитан, а угадан.
        -- А дорога в настройки - это ответ на вопрос, который игрок ещё не
        -- задал, и в строке «почему» он стоит ровно на месте совета. Поэтому
        -- факт остался в строке, дорога уехала под курсор (card.tipNote).
        local tipNote
        if s.slotConf ~= CONF.EXACT then
            why = why .. " Слот я определил по категории рецепта, а не прочитал."
            tipNote = "Слот определён по категории рецепта — если мимо,"
                .. " это поправимо в настройках."
        end
        if s.alternatives > 0 then
            why = why .. " Знаете ещё " .. s.alternatives .. " "
                .. U.plural(s.alternatives, "формулу", "формулы", "формул") .. " на этот слот."
        end

        self:Add({
            key = "ench:" .. s.recipe.id .. ":" .. s.slot,
            kind = ns.KIND.ENCHANT,
            icon = s.recipe.icon or ns.KIND_ICON.ENCHANT,
            title = "Чары: " .. s.recipe.name,
            benefit = (s.ready and "реагенты есть")
                or (s.cost and ("реагенты " .. U.money(s.cost)))
                or "цена реагентов неизвестна",
            benefitKind = "enchant",
            why = why,
            tipNote = tipNote,
            need = ns.CraftingPlanner:MissingText(s.plan, nameOf)
                .. ". " .. enchantReagentText(s),
            action = {
                kind = "findRecipe",
                recipeID = s.recipe.id,
            },
            recipeID = s.recipe.id,
            plan = s.plan,
            cost = s.cost,
            conf = s.conf,
            axes = axes,
            slot = s.slot,
            enchantOccupied = s.occupied or nil,
            currentEnchantID = s.currentEnchantID,
        })
    end

    -- Bare slots we know no formula for.
    --
    -- This card used to read "Слоты без чар, формул нет / нечего предложить"
    -- over a character with seven of eight enchantable slots already done, and
    -- the player read it as the addon failing. The progress is the headline
    -- now, and the one bare slot comes with what is actually known about it:
    -- this realm has five neck formulas, the player knows none of them, and
    -- saying so is advice rather than an apology.
    -- `added` counts the actionable suggestions, which is what decides whether
    -- the branch has a note to write. `produced` counts every card the branch
    -- put on screen, informational ones included - otherwise the summary says
    -- "Чары молчат" while an enchant card is sitting in the list, which is the
    -- sort of contradiction that sends an investigation the wrong way.
    local produced = added
    local status = ns.EnchantAdvisor:SlotStatus(snap)
    local bare = ns.EnchantAdvisor:BareWithoutFormula(snap)
    -- ЧТО УЖЕ СТОИТ - ВТОРАЯ ПОЛОВИНА ВОПРОСА, И ДО ЭТОГО ЕЙ НЕ ОТВЕЧАЛ НИКТО.
    -- Карточка писала «6 из 7», а какие именно шесть и что на них - нигде, ни
    -- на одном экране. Игрок спросил дословно «какие чанты у меня есть».
    local worn = ns.EnchantAdvisor:Worn(snap)
    local wornText
    if #worn > 0 then
        local parts, numbered = {}, 0
        for _, w in ipairs(worn) do
            -- Слова чар - если игра их отдала (Api:InventoryEnchantText);
            -- иначе номер, как раньше.
            if w.enchantText then
                parts[#parts + 1] = w.label .. " (" .. w.itemName
                    .. ", чары «" .. w.enchantText .. "»)"
            else
                numbered = numbered + 1
                parts[#parts + 1] = w.label .. " (" .. w.itemName
                    .. ", чары #" .. tostring(w.enchantID) .. ")"
            end
        end
        wornText = "Уже зачарованы: " .. table.concat(parts, ", ") .. "."
        if numbered > 0 then
            wornText = wornText .. " Номер - это всё, что игра отдаёт от наложенной чары;"
                .. " что именно она даёт, по номеру я сказать не могу"
                .. " и выдумывать не буду."
        end
        -- Формулы на часть этих слотов у игрока есть, но перекрывать то, что
        -- стоит, я не советую: сравнить не с чем (см. replaceSkipped выше).
        if replaceSkipped > 0 then
            wornText = wornText .. " Перекрывать их своими формулами не советую:"
                .. " сравнить с тем, что уже наложено, мне нечем."
        end
    end
    -- СЛОТ, ПРО КОТОРЫЙ СОВЕТА НЕТ, ОБЯЗАН БЫТЬ НАЗВАН НА ЭКРАНЕ, А НЕ ТОЛЬКО В
    -- ДИАГНОСТИКЕ. На настоящем маге это плащ и перчатки: формул на них он
    -- знает пятнадцать, и ни одна не даёт того, что ценит тайная магия
    -- (сопротивления, защита, горное дело, рыбная ловля, ловкость, сила).
    -- Воронка это записывает, но игрок читает карточку, а не воронку.
    local skipped, skippedFormulas = {}, 0
    for _, slotNote in ipairs(advice.slots or {}) do
        if slotNote.dropped == "occupied-nothing-better-known" then
            skipped[#skipped + 1] = slotNote.label
            skippedFormulas = skippedFormulas + (slotNote.formulas or 0)
        end
    end
    table.sort(skipped)
    local skippedText
    if #skipped > 0 then
        -- БЕЗ ВТОРОГО «НИ ОДНА». Строка с перечнем уже может говорить, что
        -- формул на голый слот не выучено, и два отрицания подряд читаются как
        -- повтор - это ловит Tests/sense.lua (Sense.deniesTwice). Поэтому здесь
        -- сказано, ЧТО эти формулы дают, а не чего они не дают.
        skippedText = "На " .. table.concat(skipped, ", ") .. " у вас "
            .. skippedFormulas .. " "
            .. U.plural(skippedFormulas, "формула", "формулы", "формул")
            .. ", и все они дают то, чего ваш класс не ценит — поэтому"
            .. " перекрывать ими то, что там стоит, я не предлагаю."
    end
    if (#bare > 0 or #skipped > 0) and added < ns.MAX_CARDS_PER_KIND then
        local labels, unlearned, example = {}, 0, nil
        for i = 1, math.min(4, #bare) do labels[#labels + 1] = bare[i].label end
        for _, b in ipairs(bare) do
            unlearned = unlearned + (b.unlearnedCount or 0)
            example = example or b.unlearnedExample
        end

        local why = "Зачаровано " .. status.enchanted .. " из "
            .. status.enchantable .. " "
            .. U.plural(status.enchantable, "слота", "слотов", "слотов")
            .. ", которые вообще можно зачаровать."
        if #bare > 0 then
            why = why .. " Без чар: " .. table.concat(labels, ", ")
                .. (#bare > 4 and (" и ещё " .. (#bare - 4)) or "") .. "."
        end
        if wornText then why = why .. " " .. wornText end
        -- РОД И ЧИСЛО. Здесь стояло «Остался без чар: Шея, Левая рука. Формулы
        -- на этот слот…»: «остался» про шею и руку, «этот слот» про два слота.
        -- Перечень теперь идёт после двоеточия без глагола, а слово про слот
        -- согласуется с тем, сколько их.
        local onSlot = (#bare == 1) and "этот слот" or "эти слоты"
        local onIt = (#bare == 1) and "него" or "них"
        local need
        if #bare == 0 then
            need = "Формулы на эти слоты у вас есть, но пользы вашему классу от"
                .. " них нет. Это не ошибка — просто предложить нечего."
        elseif unlearned > 0 then
            why = why .. " Формулы на " .. onSlot .. " в игре есть — " .. unlearned .. " "
                .. U.plural(unlearned, "штука", "штуки", "штук")
                .. (example and (", например «" .. example .. "»") or "")
                .. ", но ни одна у вас не выучена."
            need = "Чтобы тут что-то появилось, формулу надо выучить."
                .. " Где её берут, я не знаю — в моих данных этого нет,"
                .. " и выдумывать не буду."
        else
            why = why .. " Выученных формул на " .. onIt .. " у вас нет,"
                .. " и ни одной такой формулы я вообще не видел."
            need = "Это не ошибка — просто пока нечего накладывать."
        end
        if skippedText then why = why .. " " .. skippedText end

        local title
        if #bare == 0 then
            title = "Чары: " .. status.enchanted .. "/" .. status.enchantable
                .. ", лучше предложить нечего"
        elseif status.enchanted > 0 then
            title = "Чары: " .. status.enchanted .. "/" .. status.enchantable
                .. ", без чар: " .. table.concat(labels, ", ")
        else
            title = "Слоты без чар, формул нет"
        end
        local noFormulaCard = self:Add({
            key = "ench:noformula",
            kind = ns.KIND.ENCHANT,
            icon = ns.KIND_ICON.ENCHANT,
            title = title,
            benefit = (unlearned > 0)
                and ("можно выучить " .. unlearned)
                or (status.enchanted .. "/" .. status.enchantable .. " готово"),
            benefitKind = "info",
            why = why,
            need = need,
            action = { kind = "noop" },
            conf = CONF.EXACT,
            axes = { power = 0, skill = 0, profit = 0, spend = 0, ready = 0.1 },
            informational = true,
            enchantStatus = status,
            enchantWorn = worn,
            enchantSkipped = skipped,
        })
        if noFormulaCard then produced = produced + 1 end
    end
    if added == 0 then
        -- The formula count here used to be taken straight off the book, which
        -- held every recipe twice while the two profession name-spaces were
        -- both alive: the note read "формул 130" for a player with 65. It is
        -- the deduplicated count now, and the note leads with what is done.
        --
        -- И ПРИЧИНА ТЕПЕРЬ ВЕРНА. Здесь стояло «выученных формул 65, но ни одна
        -- сюда не подходит» - про мага, у которого к надетым вещам подходили 60
        -- формул из 65. Не подходила ни одна только к ОДНОМУ слоту без чар
        -- (шея), а про остальные шесть - занятых - примечание молчало вовсе.
        local formulas = #ns.EnchantAdvisor:LearnedFormulas()
        local bareSlots = status.bare
        -- Сколько слотов отсеялось и почему - по той же раскладке, по которой
        -- строились карточки, а не по второму счёту.
        local occupiedNothing, bareNoFormula = 0, 0
        for _, slotNote in ipairs(advice.slots or {}) do
            if slotNote.dropped == "occupied-nothing-better-known" then
                occupiedNothing = occupiedNothing + 1
            elseif slotNote.dropped == "no-formula-known" then
                bareNoFormula = bareNoFormula + 1
            end
        end
        if formulas == 0 then
            self.branchNote.enchant = "выученных формул чар нет"
        elseif bareSlots == 0 then
            self.branchNote.enchant = "все " .. status.enchantable .. " "
                .. U.plural(status.enchantable, "слот", "слота", "слотов")
                .. ", которые можно зачаровать, уже зачарованы"
                .. ((occupiedNothing > 0) and ("; из выученных " .. formulas
                    .. " " .. U.plural(formulas, "формулы", "формул", "формул")
                    .. " ни одна не даёт на эти слоты того, что вы цените")
                    or "")
        else
            self.branchNote.enchant = "зачаровано " .. status.enchanted .. " из "
                .. status.enchantable .. ", без чар: "
                .. table.concat(status.bareLabels, ", ")
                .. " — выученных формул " .. formulas
                .. ", но на " .. U.plural(bareNoFormula, "этот слот", "эти слоты", "эти слоты")
                .. " у вас нет ни одной"
                .. ((occupiedNothing > 0) and ("; на занятые слоты формулы есть,"
                    .. " но того, что вы цените, среди них нет") or "")
        end
    end
    -- ЗАНЯТЫЕ СЛОТЫ С ПОЛЕЗНОЙ ФОРМУЛОЙ: КАРТОЧКИ НЕТ, НО И ТИШИНЫ НЕТ.
    -- Совет перекрыть наложенное я не даю (см. replaceSkipped в начале
    -- ветки), и это сказано там, где игрок читает, почему ветка промолчала.
    if replaceSkipped > 0 and self.branchNote.enchant then
        self.branchNote.enchant = self.branchNote.enchant
            .. "; на " .. replaceSkipped .. " "
            .. U.plural(replaceSkipped, "зачарованный слот", "зачарованных слота",
                "зачарованных слотов")
            .. " у вас есть формулы, но перекрывать наложенное я не советую —"
            .. " сравнить с ним мне нечем"
    end
    return produced
end

-- Branch: craft for profit ---------------------------------------------
--
-- This looks at EVERY learned recipe that produces an item, with no level or
-- class filter whatsoever. On this realm that is the point: professions are not
-- gated by character level, so a level 26 character with 225 tailoring knows a
-- pile of recipes for gear twenty levels above them. Those recipes are not junk
-- to be filtered out, they are the main income.

function Engine:AddProfitCards(snap, scales)
    local planner = ns.CraftingPlanner
    local book = ns.RecipeBook

    -- Which outputs are gear the player cannot wear, so the card can say so.
    local unwearable = {}
    for _, entry in ipairs(ns.GearAdvisor:Unwearable(snap)) do
        unwearable[entry.recipe.id] = entry
    end

    -- Two passes on purpose. Margin is cheap (it reuses the planner's memoised
    -- unit costs); a full Plan is not, because it walks and allocates the whole
    -- material tree. With 263 learned recipes, planning every profitable one
    -- was the single biggest cost in a recompute, so only the best handful get
    -- planned - and the shortlist is wider than the card limit so readiness can
    -- still reorder them.
    local candidates = {}
    local funnel = ns.Diag and ns.Diag:Funnel("craftProfit") or nil
    for _, recipe in ipairs(book:Iterate(function(r) return r.learned and r.output end)) do
        if funnel then funnel:In(recipe) end
        local margin, conf, revenue, cost, craft, revOrigin = planner:Margin(recipe)
        if not margin then
            if funnel then
                funnel:Drop("no-price", recipe,
                    (not revenue) and "цена продажи неизвестна"
                        or "стоимость материалов не посчиталась")
            end
        elseif margin <= 0 then
            if funnel then funnel:Drop("not-profitable", recipe) end
        else
            candidates[#candidates + 1] = {
                recipe = recipe, margin = margin, conf = conf,
                revenue = revenue, cost = cost, craft = craft,
                revOrigin = revOrigin,
                unwearable = unwearable[recipe.id],
            }
        end
    end
    local considered = #candidates

    table.sort(candidates, function(a, b)
        if a.margin ~= b.margin then return a.margin > b.margin end
        return a.recipe.id < b.recipe.id
    end)

    local shortlist = ns.MAX_CARDS_PER_KIND * 3
    if funnel and #candidates > shortlist then
        for i = shortlist + 1, #candidates do
            funnel:Drop("below-shortlist", candidates[i].recipe,
                (i == shortlist + 1)
                    and ("маржа ниже " .. shortlist .. " лучших, план не строился")
                    or nil)
        end
    end
    for i = #candidates, shortlist + 1, -1 do candidates[i] = nil end

    for _, c in ipairs(candidates) do
        c.plan = planner:Plan(c.recipe, 1)
        c.maxNow = planner:MaxCraftableNow(c.recipe)
        -- РАСХОДНИК ОЦЕНИВАЕТСЯ ПАРТИЕЙ, ШМОТКА - ШТУКОЙ.
        --
        -- Зелья, бомбы и патроны продаются постоянно и малыми партиями; мантия
        -- продаётся один раз. Пока в ранжирование шла маржа за один крафт, зелье
        -- с маржой 3 серебра всегда проигрывало мантии с маржой 4 золотых - то
        -- есть вся алхимия и всё инженерное дело стояли в конце списка по
        -- причине, которой нет. Подробнее - у Planner:BatchProfit.
        c.batch = planner:BatchProfit(c.recipe)
    end

    -- Profit per craft, but a recipe you can run right now out of your own bags
    -- is worth more than a slightly richer one that needs a shopping trip.
    --
    -- Для расходника «per craft» заменяется на прибыль партии: это и есть то,
    -- что одно действие игрока у стола приносит, когда товар продаётся во
    -- множестве. Число берётся из BatchProfit и ограничено стопкой, то есть
    -- настоящими границами, а не оценкой спроса.
    local function rankValue(c)
        local base = (c.batch and c.batch.margin) or c.margin
        return base * (1 + 0.5 * ((c.plan and c.plan.readiness) or 0))
    end
    table.sort(candidates, function(a, b)
        local ra, rb = rankValue(a), rankValue(b)
        if ra ~= rb then return ra > rb end
        return a.recipe.id < b.recipe.id
    end)

    if considered == 0 then
        local ps = ns.PriceProvider:SourceSummary()
        self.branchNote.profit = (not ps.auctionatorAvailable)
            and "цен аукциона нет, поэтому прибыль посчитать не из чего"
            or "ни один из ваших рецептов не продаётся дороже материалов"
    end

    if ns.Diag then
        ns.Diag:Module("craftProfit", {
            ["in"] = considered, out = math.min(#candidates, ns.MAX_CARDS_PER_KIND),
            planned = #candidates, shortlist = shortlist,
            reason = (considered == 0)
                and "ни один рецепт не дал положительной маржи (нет цен или всё убыточно)"
                or nil,
        })
    end

    local added = 0
    for ci, c in ipairs(candidates) do
        if added >= ns.MAX_CARDS_PER_KIND then
            if funnel then
                for i = ci, #candidates do
                    funnel:Drop("over-card-limit", candidates[i].recipe,
                        (i == ci) and ("на экран берём только "
                            .. ns.MAX_CARDS_PER_KIND .. " лучших") or nil)
                end
            end
            break
        end
        added = added + 1

        local info = Api:ItemInfo(c.recipe.output)
        local outName = (info and info.name) or U.itemFallbackName(c.recipe.output)

        local axes = blankAxes()
        -- The profit axis uses the per-craft figure: that is what one action by
        -- the player actually yields. The card keeps both numbers so the text
        -- can never pass one off as the other.
        --
        -- У РАСХОДНИКА «одно действие игрока» - это партия, а не штука: за один
        -- подход к столу он делает стопку зелий и выставляет её одним лотом.
        -- Ось обязана считать то же самое, что и сортировка выше: иначе
        -- сортировка расставит карточки по партиям, а итоговое ранжирование по
        -- осям переставит их обратно по штукам, и правка не сделает ничего.
        local perCraft = (c.craft and c.craft.margin) or c.margin
        local shown = (c.batch and c.batch.margin) or perCraft
        axes.profit = U.soft(shown, scales.profit)
        axes.ready = c.plan and c.plan.readiness or 0
        axes.spend = c.plan and c.plan.cost and U.soft(c.plan.cost, scales.spend) or 0
        axes.skill = U.soft(planner:SkillChance(c.recipe), scales.skill)

        local qty = (c.craft and c.craft.outputQty) or 1

        -- WHERE the revenue came from, said out loud. The parenthesis used to
        -- read "(сбор аукциона уже вычтен)" on every card, including the ones
        -- whose revenue is the vendor's offer and had no fee taken off at all.
        local origin = c.revOrigin or {}
        local revNote
        if origin.cutApplied then
            revNote = "сбор аукциона уже вычтен"
        elseif origin.src == "vendor" then
            revNote = "это цена торговца, не аукциона — сбора нет"
        else
            revNote = "источник цены неизвестен, сбор не учтён"
        end
        -- Нет числа - называется ПРИЧИНА, одним словарём на весь аддон
        -- (ns.VOID в Core/Const.lua). Прочерк и «?» здесь значили разное в
        -- разных местах, и на экране это сливалось в «аддон молчит».
        local perUnitText = "материалы "
            .. (c.cost and U.money(c.cost) or U.void(ns.VOID.NO_PRICE))
            .. ", выручка "
            .. (c.revenue and U.money(c.revenue) or U.void(ns.VOID.NO_PRICE))
            .. " за штуку (" .. revNote .. ")"

        local why
        if c.unwearable then
            why = "Вы это надеть не можете (" .. (c.unwearable.blockReason or "не подходит")
                .. "), но на продажу годится: " .. perUnitText .. "."
        else
            why = U.capitalize(perUnitText) .. "."
        end

        -- What the item's own price history says about the figure above. This
        -- sentence is the one that was missing when the top card promised
        -- 4 gold 74 for a pair of boots that had traded at 2 silver all week.
        if origin.historyNote then
            why = why .. " " .. U.capitalize(origin.historyNote) .. "."
        end

        -- ЧАСТЬ МАТЕРИАЛОВ ДЕШЕВЛЕ НА ПОЛКЕ - И ЭТО ТОЖЕ СОВЕТ, А НЕ СНОСКА.
        --
        -- Стоимость материалов выше уже посчитана по потолку (Price:Buy), так
        -- что число верно и так. Но план игрок исполняет руками, и без этой
        -- фразы он пойдёт за всем списком на аукцион - то есть заплатит
        -- разницу, которую карточка уже сэкономила на бумаге.
        local matSave = Engine.VendorSavingInPlan(c.plan)
        if matSave then
            why = why .. " " .. matSave .. "."
        end

        -- ВОЗРАСТ ЦЕНЫ - НА КАРТОЧКЕ, А НЕ ТОЛЬКО В ДИАГНОСТИКЕ.
        --
        -- Auctionator знает ровно то, что игрок отсканировал сам, и обойти это
        -- нельзя. Значит, если весь расчёт стоит на цене позавчерашней давности,
        -- игрок обязан прочитать это там, где читает сумму - а не узнавать из
        -- файла диагностики. (И да, до этого возраст вообще не мог сюда попасть:
        -- Auctionator отдаёт его в ДНЯХ, а адаптер считал днями секунды, так что
        -- «старой» цена не становилась никогда. См. Api:ReadAuctionPrice.)
        local revAge = tonumber(origin.age)
        if revAge and revAge >= (ns.PRICE_AGE_SAY_SECONDS or 86400) then
            why = why .. " Цена не сегодняшняя: последний раз этот предмет"
                .. " видели на аукционе " .. (U.ageText(revAge) or "давно")
                .. ". Зайдите на аукцион — я пересчитаю на свежих."
        end
        if qty > 1 and c.craft then
            why = why .. " Один крафт даёт " .. qty .. " шт.: "
                .. U.money(c.craft.cost) .. " материалов, "
                .. U.moneyDelta(c.craft.margin) .. " прибыли за крафт."
        end

        -- ЧТО ЭТО ЗА ТОВАР, СКАЗАННОЕ СЛОВАМИ.
        --
        -- Прибыль расходника в заголовке - это прибыль ПАРТИИ, и игрок обязан
        -- прочитать это там же, где читает сумму. Иначе «+1з 90с» за стопку
        -- зелий читается как «+1з 90с за зелье», а это в пять раз не так.
        local batch = c.batch
        if batch and batch.shape == planner.SALE_BATCH then
            why = why .. " Это расходник: такое продают партиями и понемногу"
                .. " постоянно, а не один раз, как вещь."
            if batch.runs > 1 then
                why = why .. " В прибыли выше — стопка из " .. batch.runs .. " "
                    .. U.plural(batch.runs, "штуки", "штук", "штук") .. ": "
                    .. (batch.limitedBy == "stack"
                        and ("материала хватает на " .. batch.canMake
                             .. ", но больше стопки одним лотом не выставить")
                        or "столько хватает материала")
                    .. ". Сколько рынок проглотит, я не знаю — цены аукцион"
                    .. " показывает, оборот нет."
            elseif batch.limitedBy == "materials" then
                -- «материала на вторую штуку НЕТ» стояло здесь до того, как
                -- рядом в той же строке оказалась вторая фраза с «нет» (про
                -- отсутствие своей истории цен). Две фразы с «нет» в одной
                -- строке читаются как одно и то же, сказанное дважды, - это
                -- ловит правило «повтор» в Tests/sense.lua. Факт тот же,
                -- сказанный с положительной стороны.
                why = why .. " Партию считать не из чего: материала хватает"
                    .. " на одну штуку, поэтому в прибыли выше — один крафт."
            end
        end

        -- ЦЕНА БЕЗУБЫТОЧНОСТИ, И СКАЗАННАЯ ПРЯМО.
        --
        -- Карточка показывает прибыль при СЕГОДНЯШНЕЙ цене. Но продаёт игрок
        -- не сегодняшней ценой, а той, которую сам выставит, и единственное
        -- число, которое ему для этого нужно, - граница: ниже неё он продаёт в
        -- минус. Считается по своей книге закупок, когда она закрывает
        -- материалы, и тогда это не оценка (см. Logic/Ledger.lua).
        local breakeven = ns.Ledger and ns.Ledger:Breakeven(c.recipe, ns.PriceProvider) or nil
        if breakeven then
            why = why .. " Дешевле " .. U.money(breakeven.listPrice)
                .. " за штуку выставлять нельзя: это продажа в минус"
                .. " (себестоимость " .. U.money(breakeven.unitCost)
                .. (breakeven.source == "ledger" and " по вашим покупкам"
                    or (breakeven.source == "mixed" and " — часть по вашим покупкам"
                        or " — оценка"))
                .. ", аукцион берёт " .. U.pct(breakeven.cut) .. " с продажи)."
        end
        local cdLeft = planner:CooldownLeft(c.recipe)
        if cdLeft then
            why = why .. " Рецепт на перезарядке: ещё "
                .. (U.durationText(cdLeft) or "?") .. "."
        elseif c.maxNow > 0 then
            why = why .. " Сейчас можно сделать " .. c.maxNow .. " шт. из своего."
        end

        -- A figure nobody can stand behind does not get to look like one.
        --
        -- The headline used to be a bare "+4з 74с" whatever the figure rested
        -- on, and that is what the player acted on. When the price was not
        -- confirmed by a listing, or the history says the live listing is an
        -- outlier, the headline carries a "≈" and the word "оценка" so the
        -- number is read as what it is before the card is ever opened.
        local soft = (origin.outlier ~= nil)
            or (origin.observed == false)
            or c.conf == CONF.ESTIMATE or c.conf == CONF.UNKNOWN
        local benefitText
        if soft then
            benefitText = "оценка ~" .. U.money(math.abs(shown))
                .. ((shown < 0) and " убытка" or "")
        else
            benefitText = U.moneyDelta(shown)
        end
        -- ЗА ЧТО ЭТО ЧИСЛО. Три разных ответа, и до этого два из них выглядели
        -- одинаково: «за крафт» (рецепт даёт несколько штук) и «за стопку»
        -- (расходник, крафтов несколько). Без подписи «+1з 90с» у стопки зелий
        -- читается как прибыль с одного зелья - а это в пять раз не так.
        local batchRuns = (c.batch and c.batch.shape == planner.SALE_BATCH
            and c.batch.runs > 1) and c.batch.runs or nil
        if batchRuns then
            benefitText = benefitText .. " за стопку (" .. batchRuns .. " "
                .. U.plural(batchRuns, "шт.", "шт.", "шт.") .. ")"
        elseif qty > 1 then
            benefitText = benefitText .. " за крафт"
        end

        -- ОБЛИК ТОГО, ЧТО СОБИРАЮТСЯ ПРОДАТЬ.
        --
        -- Вещь ещё не сделана, поэтому привязанность берётся из правила привязки
        -- самой вещи: привязка при подборе значит, что скрафченная вещь станет
        -- вашей и облик запишется сам, а привязка при надевании - что проданную
        -- вещь вы отдадите вместе с её обликом. Расходников это не касается
        -- вовсе: облика у них не бывает, и ветка про них молчит.
        local sellLooks = ns.Appearance and ns.Appearance:Check({
            itemID = c.recipe.output,
            link = info and info.link or nil,
            name = info and info.name or nil,
            quality = info and info.quality or nil,
            classID = info and info.classID or nil,
            bindType = info and info.bindType or nil,
        }, "sell", "craft-profit") or nil

        local dupesBefore = self.dupes or 0
        local sellCard = {
            key = "profit:" .. c.recipe.id,
            kind = ns.KIND.CRAFT_PROFIT,
            icon = (info and info.texture) or c.recipe.icon or ns.KIND_ICON.CRAFT_PROFIT,
            title = "На продажу: " .. outName
                .. ((qty > 1) and (" (x" .. qty .. " за крафт)") or ""),
            benefit = benefitText,
            benefitKind = "gold",
            priceOutlier = origin.outlier,
            priceObserved = origin.observed,
            priceSoft = soft or nil,
            benefitValue = shown,
            revenue = c.revenue,
            revOrigin = origin,
            unitMargin = c.margin,
            craftMargin = c.craft and c.craft.margin or nil,
            -- ФОРМА ПРОДАЖИ И ПАРТИЯ ЕДУТ С КАРТОЧКОЙ. Окно крафта и подсказка
            -- не имеют права считать их заново: три числа (штука, крафт,
            -- стопка) слишком похожи, чтобы расходиться молча.
            saleShape = c.batch and c.batch.shape or nil,
            batch = c.batch,
            batchMargin = c.batch and c.batch.margin or nil,
            -- Граница, ниже которой продавать в минус. Карточка носит её с
            -- собой, чтобы окно крафта и подсказка не считали её заново и не
            -- разошлись с тем, что уже написано в `why`.
            breakeven = breakeven,
            outputQty = qty,
            why = why,
            need = planner:MissingText(c.plan, nameOf),
            action = {
                kind = "findRecipe",
                recipeID = c.recipe.id, itemID = c.recipe.output,
            },
            link = info and info.link or nil,
            itemID = c.recipe.output,
            recipeID = c.recipe.id,
            plan = c.plan,
            cost = c.plan and c.plan.cost or nil,
            conf = c.conf,
            axes = axes,
        }

        -- ТОТ ЖЕ РЕЦЕПТ УЖЕ СОВЕТУЮТ НАДЕТЬ?
        --
        -- Тогда второй карточки не будет: оба варианта называет одна, уже
        -- построенная (см. Engine:FoldSellIntoGear). Карточка «на продажу»
        -- здесь всё равно собирается целиком - из неё берутся числа, - просто
        -- не попадает в список, и место в лимите ветки не занимает.
        Engine.ApplyLooks(sellCard, sellLooks)

        local gearCard = self.gearByRecipe and self.gearByRecipe[c.recipe.id]
        if gearCard ~= nil then
            if gearCard then
                self:FoldSellIntoGear(gearCard, sellCard, c)
                if funnel then
                    funnel:Drop("same-item-advised-to-wear", c.recipe,
                        "эту вещь уже советую скрафтить и надеть — продажа названа"
                        .. " в той же карточке вторым вариантом")
                end
            elseif funnel then
                funnel:Drop("same-item-advised-to-wear", c.recipe,
                    "совет про эту вещь игрок скрыл — показать её же как"
                    .. " «на продажу» значило бы вернуть скрытое другой строкой")
            end
            added = added - 1
        else
            local accepted = self:Add(sellCard)
            if funnel and not accepted then
                -- The card was built and then swallowed. Which of the two
                -- reasons it was matters: one is the player's own doing and
                -- reversible, the other is a bug in a branch producing the
                -- same thing twice.
                if (self.dupes or 0) > dupesBefore then
                    funnel:Drop("duplicate", c.recipe, "такой же совет уже в списке")
                else
                    funnel:Drop("hidden-by-player", c.recipe, "скрыто игроком, /fp show")
                end
            end
        end
    end
    -- `added` counts the cards this branch BUILT, which is what the branch note
    -- and the old counters mean; the funnel above says how many of them the
    -- list actually kept and why the rest went.
    if funnel then funnel:Finish(added) end
    return added
end

-- Branch: craft for skill ----------------------------------------------

function Engine:AddSkillCards(snap, scales)
    local planner = ns.CraftingPlanner
    local cfg = ns.Config:Get()
    local added = 0
    local capped, cappedNames = {}, {}

    for _, prof in ipairs(ns.CharacterScanner:CraftingProfessions()) do
        local bucket = ns.RecipeBook:Bucket(prof.name)
        if bucket then
            -- A skill level we do not trust is simply not used as a gate; the
            -- recipe difficulty the client reports is evidence on its own. And
            -- an unknown ceiling is not a ceiling: with no max to compare
            -- against we cannot be at it, so the advice carries on and says the
            -- maximum is unknown rather than guessing one.
            local atCap = false
            if prof.skillTrusted and prof.skill and prof.max and prof.max > 0 then
                atCap = prof.skill >= prof.max
            end

            -- The skill has stopped moving because current == max. WHY the
            -- ceiling sits there we do not know and do not guess: the client
            -- reports it and nothing else on disk explains it, and
            -- a card that sends the player to a trainer on a hunch is worse
            -- than one that admits the limit. Collected and reported as ONE
            -- card at the end, because this character is capped on four
            -- professions and four near-identical cards would push the real
            -- advice off screen.
            if atCap then
                -- Имя - через U.profLabel: в раннем состоянии профессии
                -- приходят из чужого кеша, и там они английские.
                capped[#capped + 1] = U.profLabel(prof.name)
                    .. " " .. prof.skill .. "/" .. prof.max
                cappedNames[#cappedNames + 1] = U.profLabel(prof.name)
            end

            if not atCap then
                local best, bestScore = nil, -1
                for _, recipe in ipairs(bucket.list) do
                    -- A recipe on cooldown cannot give a skill-up now, so it is
                    -- not the answer to "what should I craft next".
                    if recipe.learned and not planner:OnCooldown(recipe) then
                        local chance = planner:SkillChance(recipe)
                        local worthIt = chance > 0
                            or (not cfg.show.hideTrivialSkill and recipe.diff == nil)
                        if worthIt then
                            local plan = planner:Plan(recipe, 1)
                            local cost = plan and plan.cost
                            -- Skill per gold: a free skill-up out of the bags
                            -- beats a marginally better one that costs money.
                            local value = chance
                            if cost and cost > 0 then
                                value = chance / (1 + cost / math.max(1, scales.spend))
                            elseif cost == 0 then
                                value = chance * 2
                            end
                            value = value * (0.5 + 0.5 * ((plan and plan.readiness) or 0))
                            if value > bestScore then
                                best, bestScore = { recipe = recipe, plan = plan, chance = chance, cost = cost }, value
                            end
                        end
                    end
                end

                if best then
                    added = added + 1
                    local info = best.recipe.output and Api:ItemInfo(best.recipe.output) or nil
                    local axes = blankAxes()
                    axes.skill = U.soft(best.chance, scales.skill)
                    axes.ready = best.plan and best.plan.readiness or 0
                    axes.spend = best.cost and U.soft(best.cost, scales.spend) or 0

                    -- The goal comes from the client's max and from nowhere
                    -- else. When the client did not report a ceiling the card
                    -- says the maximum is unknown instead of borrowing one.
                    local goal, remaining = planner:SkillGoal(prof)

                    local skillText
                    if prof.skillTrusted and prof.skill then
                        skillText = prof.skill .. (goal and ("/" .. goal) or "")
                        -- Zero is truthy in Lua, so `not prof.max` would let a
                        -- zero ceiling pass as a known one and print "/0".
                        if not (prof.max and prof.max > 0) then
                            skillText = skillText .. " (максимум неизвестен)"
                        end
                    else
                        skillText = "уровень навыка неизвестен"
                    end

                    self:Add({
                        key = "skill:" .. prof.name .. ":" .. best.recipe.id,
                        kind = ns.KIND.CRAFT_SKILL,
                        icon = best.recipe.icon or (info and info.texture) or ns.KIND_ICON.CRAFT_SKILL,
                        title = "На навык: " .. best.recipe.name,
                        -- ЧИСЛО БЕЗ ЕДИНИЦЫ. Здесь стояло «почти верный +1»:
                        -- плюс один - чего? В столбце выгоды рядом стоят
                        -- «+11 баллов» и «+5с 60м», и «+1» читается как ещё
                        -- одна такая величина. Это пункт навыка, и так теперь
                        -- и написано - тем же словом, которым про навык говорит
                        -- строка «почему» («до потолка 3 пункта»).
                        benefit = (best.chance >= 1 and "+1 пункт навыка почти наверняка")
                            or (best.chance > 0
                                and ("+1 пункт навыка, шанс " .. U.pct(best.chance)))
                            or "прирост навыка: шанс неизвестен",
                        benefitKind = "skill",
                        benefitValue = best.chance,
                        why = U.profLabel(prof.name) .. " — " .. skillText
                            .. (remaining and (", до потолка " .. remaining .. " "
                                .. U.plural(remaining, "пункт", "пункта", "пунктов")) or "")
                            .. ". Это самый дешёвый рецепт, который ещё даёт навык"
                            .. ((best.cost and best.cost > 0)
                                and (" (" .. U.money(best.cost) .. " за крафт)")
                                or ((best.cost == 0) and " (материалы уже есть)" or ""))
                            .. ".",
                        need = planner:MissingText(best.plan, nameOf),
                        action = {
                            kind = "findRecipe",
                            recipeID = best.recipe.id,
                        },
                        recipeID = best.recipe.id,
                        plan = best.plan,
                        cost = best.cost,
                        skillGoal = goal,
                        skillRemaining = remaining,
                        conf = U.worstConf(best.plan and best.plan.conf or CONF.UNKNOWN,
                            best.recipe.conf or CONF.CACHED),
                        axes = axes,
                        profession = prof.name,
                    })
                end
            end
        end
    end

    -- One card for every capped profession at once.
    if #capped > 0 then
        added = added + 1
        local axes = blankAxes()
        -- This card delivers no skill-up: that is the whole point of it. It used
        -- to claim axes.skill = 0.50, half a guaranteed skill-up, and on the
        -- real character it then sat at the top of the list under every profile
        -- while the actual advice was pushed below the fold. It is information,
        -- so it is marked as such and ranks below anything actionable.
        axes.ready = 0.15
        table.sort(capped)
        table.sort(cappedNames)

        -- ЧТО КАРТОЧКА ГОВОРИТ О ПОТОЛКЕ: ТОЛЬКО ТО, ЧТО ИЗВЕСТНО.
        --
        -- Здесь стояло «Раньше он уже поднимался (4 раза): последний раз
        -- 2026-11-15, 224 -> 225». Это была неправда: числа брались из истории
        -- Mastercraft, где записан НАВЫК игрока за день, а не максимум (см.
        -- Api:MastercraftSkillHistory). «Потолок поднялся с 224 до 225» - это
        -- игрок докачал пункт. Истории максимума у аддона нет, поэтому про неё
        -- он молчит; известно ему одно - что навык сейчас равен максимуму.
        local need = "Когда и как максимум поднимется, я не знаю — поэтому не"
               .. " гадаю. Крафт для этих профессий сейчас советую только ради"
               .. " денег и вещей."

        self:Add({
            -- Keyed on the profession names, NOT on the numbers. The numbers
            -- move - that is the whole point of this card - and keying on them
            -- made a "Понятно" dismissal evaporate the moment a skill ticked.
            key = "cap:reached:" .. table.concat(cappedNames, ","),
            kind = ns.KIND.CRAFT_SKILL,
            icon = ns.KIND_ICON.CRAFT_SKILL,
            title = (#capped == 1)
                and ("Навык на пределе: " .. capped[1])
                or ("Навык на пределе: " .. #capped .. " "
                    .. U.plural(#capped, "профессия", "профессии", "профессий")),
            benefit = "прироста сейчас нет",
            benefitKind = "skill",
            benefitValue = 0,
            why = table.concat(capped, ", ")
                .. ". Текущий навык равен максимальному, поэтому крафт навык не"
                .. " даёт — сколько ни делай.",
            need = need,
            action = { kind = "noop" },
            conf = CONF.EXACT,
            axes = axes,
            informational = true,
            cappedProfessions = capped,
        })
    end

    -- The skill branch is the one case where "nothing to advise" is the right
    -- answer rather than a gap: a profession at its ceiling cannot gain skill.
    -- Said plainly, because the player can then stop looking for the missing
    -- advice. Nothing here gates the gear, profit or enchant branches - they
    -- have no skill requirement at all and keep running at the ceiling.
    if #capped > 0 then
        self.branchNote.skill = "навык на пределе: " .. table.concat(capped, ", ")
            .. " — крафт навык пока не даёт"
    elseif added == 0 then
        self.branchNote.skill = "нет рецепта, который ещё даёт прирост навыка"
    end
    return added
end

-- МАТЕРИАЛЫ, КОТОРЫЕ ДЕШЕВЛЕ НА ПОЛКЕ, - ОДНОЙ ФРАЗОЙ НА ВЕСЬ ПЛАН.
--
-- Одна фраза на карточку, а не строка на каждый материал: строка «почему» на
-- экране одна и обрезается шириной окна. Названия - до двух: больше в эту
-- строку всё равно не влезет, а «и ещё N» отвечает на вопрос «а остальные?».
--
-- Решения берутся из плана, то есть из тех же вызовов Price:Buy, которыми
-- посчитана стоимость. Своей арифметики здесь нет: разошлись бы.
function Engine.VendorSavingInPlan(plan)
    if type(plan) ~= "table" then return nil end
    local Price = ns.PriceProvider
    if not (Price and Price.Ceiling) then return nil end
    local saving, names, n = 0, {}, 0
    for _, line in ipairs(plan.shopping or {}) do
        local v = Price:Ceiling(line.itemID)
        if v and v.cheaper == "vendor" and v.saving and v.saving > 0 then
            n = n + 1
            saving = saving + v.saving * (tonumber(line.qty) or 1)
            if #names < 2 then
                local info = Api:ItemInfo(line.itemID)
                names[#names + 1] = (info and info.name)
                    or U.itemFallbackName(line.itemID)
            end
        end
    end
    if n == 0 or saving <= 0 then return nil end
    local what = table.concat(names, ", ")
    if n > #names then
        local rest = n - #names
        what = what .. " и ещё " .. rest .. " "
            .. U.plural(rest, "позиция", "позиции", "позиций")
    end
    -- Не «Дешевле у торговца…»: следом в этой же строке идёт граница
    -- безубыточности, которая начинается со слова «Дешевле», и две фразы подряд
    -- с одного слова читаются как повтор аддона, а не как два разных факта.
    return "У торговца это дешевле, чем на аукционе: " .. what
        .. " — экономия " .. U.money(saving) .. " на весь план"
end

-- Branch: buy ----------------------------------------------------------
-- Materials that several suggested cards need, worth one trip to the auction
-- house. We never buy anything; this is a list and a hint.

Engine.MAX_BUY_CARDS = 4

-- «ЭТО В N РАЗ БОЛЬШЕ, ЧЕМ У ВАС ЕСТЬ» - одной функцией на оба места.
--
-- Мест два (любая карточка не по карману и карточка покупки), и оба писали
-- «в " .. N .. " раз» без согласования: «в 3 раз больше». А при нуле денег
-- отношение считалось от единицы, и выходило «в 600 раз больше, чем у вас есть
-- (0м)» - сравнение с нулём, которое не значит ничего.
function Engine.OutOfReachText(cost, money, ratio)
    if (tonumber(money) or 0) <= 0 then
        return "Денег у вас сейчас нет вовсе — на это не хватает "
            .. U.money(cost or 0) .. "."
    end
    return "Это в " .. (U.times(U.round(ratio or 0)) or "несколько раз")
        .. " больше, чем у вас есть (" .. U.money(money) .. ")."
end

-- Приписать фразу к тексту так, чтобы между ними стояла точка. «…и ещё 2
-- позиции Это в 10 раз больше…» получалось из склейки через пробел.
-- Точка ставится одним правилом на весь аддон (U.endSentence): здесь был
-- свой список из трёх знаков, и он не знал про «46 шт.» - приписывал вторую
-- точку к сокращению.
function Engine.JoinSentences(text, sentence)
    -- ПРИПИСЫВАТЬ НЕЧЕГО - НЕ ПРИПИСЫВАЕМ, А НЕ ПАДАЕМ.
    --
    -- Раньше второй кусок обязан был быть строкой, и все вызывающие это
    -- соблюдали - до ветки лагеря, у которой фраза «готовый на аукционе стоит
    -- столько» существует только при известной цене, а «мест у костра станет
    -- больше» - только когда есть с чем сравнить. В обычном мире оба куска на
    -- месте, и `.. nil` не случался; поймал его откат, в котором у предметов
    -- лагеря пропали имена и цены. Один `..` на nil роняет весь пересчёт, то
    -- есть весь аддон.
    if sentence == nil or sentence == "" then return text end
    if type(text) ~= "string" or text == "" then return sentence end
    return U.endSentence(text) .. " " .. sentence
end

-- ОБЛИК: ОДНА ФРАЗА В СТРОКУ СОВЕТА, ПОДРОБНОСТИ ПОД КУРСОР ----------------
--
-- Пять веток этого файла советуют расстаться с вещью: продать на аукционе,
-- продать торговцу, распылить, перекупить и перепродать, переслать другому
-- персонажу. У всех пяти есть общее свойство: любую ошибку в их числах игрок
-- отменит, а потерянный облик - нет. Поэтому ответ про облик приписывается
-- всем пяти ОДНИМ способом, и ни одна ветка не рассказывает про это своими
-- словами.
--
-- ГДЕ ИМЕННО СТОИТ ТЕКСТ, И ПОЧЕМУ ТАК:
--   * предупреждение - ПЕРВОЙ фразой в строке «почему». Игрок читает первую
--     фразу и часто только её, а всё остальное в этих карточках про деньги;
--   * подробности (почему это необратимо, что посмотреть, что решать ему) -
--     под курсор. В строке совета места на абзац нет: она одна и не
--     переносится, а над списком лишней строке тоже не место - там общая
--     строка про непоказанные советы.
--
-- Сам ответ (card.looks) едет с карточкой, чтобы самопроверка могла спросить
-- каждую такую карточку, был ли вопрос задан вообще.
-- `atEnd` - приписать предупреждение В КОНЕЦ, а не в начало. Нужно одному
-- случаю: карточка «скрафтить и надеть», которая вторым вариантом называет
-- продажу. Надеть вещь безопасно, и начинать такую карточку с «облик
-- потеряете» значило бы предупреждать про поступок, которого она не советует.
function Engine.ApplyLooks(card, looks, atEnd)
    if type(card) ~= "table" then return card end
    if type(looks) ~= "table" then return card end
    card.looks = looks
    if not (ns.Appearance and ns.Appearance:Speaks(looks)) then return card end
    local lead = U.endSentence(looks.short)
    if type(card.why) ~= "string" or card.why == "" then
        card.why = lead
    elseif atEnd then
        card.why = Engine.JoinSentences(card.why, lead)
    else
        card.why = lead .. " " .. card.why
    end
    if type(looks.detail) == "string" and looks.detail ~= "" then
        local tail = card.tipNote
        card.tipNote = (type(tail) == "string" and tail ~= "")
            and (U.endSentence(looks.detail) .. " " .. tail)
            or looks.detail
    end
    return card
end

-- «Нужно для: …» - ОДНОЙ ФУНКЦИЕЙ, ПОТОМУ ЧТО СТРОКУ ПРИХОДИТСЯ ПЕРЕПИСЫВАТЬ.
--
-- Карточка покупки называет советы, которым этот материал нужен. Но часть этих
-- советов до экрана может не дойти: порог мелкой денежной выгоды убирает
-- денежные советы ПОСЛЕ того, как покупки построены. На настоящих данных это
-- выглядело так: порог убрал «На продажу: Лунная винтовка», а карточка «Купить:
-- Предмет #1705 x2» осталась и честно писала «Нужно для: На продажу: Лунная
-- винтовка» - про совет, которого на экране нет. Поэтому строка собирается
-- здесь и пересобирается после порога по тем заказчикам, которые остались.
--
-- Имя заказчика, которое ставит сам список покупок, когда позицию закрепил
-- игрок: за совет оно не считается.
Engine.PINNED_BY_HAND = "закреплено вручную"

function Engine.BuyUseText(uses)
    local n = #uses
    if n > 2 then
        return "Нужно для " .. n .. " "
            .. U.plural(n, "совета", "советов", "советов")
            .. ", например: " .. uses[1] .. "; " .. uses[2]
    elseif n == 2 then
        return "Нужно для 2 советов: " .. uses[1] .. "; " .. uses[2]
    elseif n == 1 then
        return "Нужно для: " .. uses[1]
    end
    -- ЗДЕСЬ СТОЯЛО «Ни одному совету это сейчас не нужно», И ЭТО БЫЛА ПЕРВАЯ
    -- ФРАЗА КАРТОЧКИ, КОТОРАЯ ТУТ ЖЕ ПРЕДЛАГАЛА КУПИТЬ. Пустой список
    -- заказчиков бывает ровно в одном случае - позицию закрепил сам игрок, - и
    -- такая карточка теперь называется своим именем (Engine.AsOwnListCard).
    -- Строка осталась одна, честная: если до неё однажды доберётся путь, о
    -- котором мы не знаем, игрок прочитает, чей это заказ, а не то, что совет
    -- сам себе не нужен. Правило, которое держит отрицание себя вне карточек, -
    -- Tests/sense.lua, Sense.SELF_DENIAL.
    return Engine.OWN_LIST_LEAD
end

-- СОВЕТ, ПЕРВАЯ ФРАЗА КОТОРОГО ОТРИЦАЛА ЕГО ЖЕ СУЩЕСТВОВАНИЕ ---------------
--
-- Живая находка, десятая строка списка:
--
--   «Купить: Небесно-голубая краска x6»
--   «Ни одному совету это сейчас не нужно. Цена: ~1з 31с … В вашем списке
--    покупок это уже закреплено (6 шт.).»
--
-- Совет, который сам сообщает, что он не нужен. Место в списке он занимал
-- только потому, что игрок когда-то закрепил предмет руками, и выглядел при
-- этом как совет аддона - заголовок «Купить: …», кнопка «В список покупок»,
-- ступень ранжирования та же, что у настоящих советов.
--
-- ВЫБРОСИТЬ ЕГО НЕЛЬЗЯ, и это не вкусовщина. Закрепление - решение игрока, и
-- строка с ценой за штуку и количеством есть только здесь; убрать её значило бы
-- тихо спрятать его собственный список (перечень путей исчезновения советов
-- закрыт - Tests/test_vanish.lua). Поэтому карточка остаётся, но называется тем,
-- что она есть:
--
--   * заголовок говорит, что это список игрока, а не совет аддона;
--   * первая фраза говорит, КТО это попросил, а не то, что это не нужно;
--   * кнопка снимает закрепление - то есть делает ровно то, что на ней написано
--     (раньше кнопка «В список покупок» отвечала «уже в вашем списке», то есть
--     не делала ничего);
--   * карточка помечена информационной и за место с настоящими советами больше
--     не спорит (Engine.TierOf, ступень 1).
Engine.OWN_LIST_TITLE = "Ваш список покупок: "
Engine.OWN_LIST_LEAD = "Это ваше закрепление: вы просили держать это в списке"
    .. " покупок, и я держу. Моим советам столько сейчас не нужно, но список ваш"
Engine.OWN_LIST_NEED = "Снять закрепление — кнопкой «Убрать из списка»."
Engine.OWN_LIST_ACTION = "Убрать из списка"

-- Превратить карточку покупки в карточку своего списка. Идемпотентно: строку
-- «чего не хватает» дописываем один раз.
function Engine.AsOwnListCard(card)
    if type(card) ~= "table" or card.ownList then return card end
    card.ownList = true
    card.informational = true
    card.title = Engine.OWN_LIST_TITLE .. tostring(card.buyName or "?")
        .. " x" .. tostring(card.buyQty or 1)
    card.why = Engine.OWN_LIST_LEAD .. (card.buyOwnTail or "")
    card.whyBase = nil
    card.need = Engine.JoinSentences(card.need, Engine.OWN_LIST_NEED)
    card.action = { kind = "unpin", label = Engine.OWN_LIST_ACTION,
                    itemID = card.itemID }
    if ns.Risk then ns.Risk:RenderDoubts(card) end
    return card
end

function Engine:AddBuyCards(snap, scales)
    local afford = ns.ShoppingList:Affordability(snap)
    local added = 0

    -- Filter first, then take the top N. Taking the first four lines by spend
    -- and only then checking whether they could be bought meant four drop-only
    -- materials at the top of the list produced no buy card at all, while a
    -- cheap reagent sitting fifth was ignored.
    local lines = {}
    for _, line in ipairs(ns.ShoppingList:Lines()) do
        if line.buyable and line.subtotal and line.subtotal > 0 then
            lines[#lines + 1] = line
        end
    end

    for i = 1, math.min(Engine.MAX_BUY_CARDS, #lines) do
        local line = lines[i]
        do
            added = added + 1
            local axes = blankAxes()
            axes.spend = U.soft(line.subtotal, scales.spend)
            -- Buying unblocks other cards, which is its whole value.
            local unblocks = #line.uses
            axes.ready = U.clamp(unblocks / 3, 0, 1) * 0.8
            axes.power = 0
            axes.profit = 0

            -- ДЛЯ ЧЕГО ЭТО НУЖНО - ПО ИМЕНАМ, БЕЗ «ВЫШЕ».
            --
            -- Здесь стояло «нужно для N советов выше». Карточка покупки не
            -- знает, что окажется выше неё: ранжирование, профиль и обрезка
            -- списка идут после. На настоящих данных «12 советов выше» стояло
            -- у карточки, над которой было четыре таких совета. И пометка
            -- «закреплено вручную» считалась за совет.
            local uses, pinnedByHand = {}, false
            for _, title in ipairs(line.uses) do
                if title == Engine.PINNED_BY_HAND then pinnedByHand = true
                else uses[#uses + 1] = title end
            end
            local useText = Engine.BuyUseText(uses)
            -- ЗАКРЕПЛЁННОЕ РУКАМИ ТАК И НАЗВАНО. Сколько купить - не меньше
            -- того, что игрок закрепил сам. Без этой фразы карточка «Купить
            -- x3 … всего нужно 1, своего есть 2» противоречит сама себе.
            local pinnedText = ""
            local pin = tonumber(line.pinned) or 0
            if pin > 0 or pinnedByHand then
                local netNeed = math.max(0, (line.gross or 0) - (line.have or 0))
                if pin > netNeed then
                    pinnedText = " Вы сами закрепили в своём списке покупок " .. pin
                        .. " шт. — меньше не предлагаю."
                else
                    pinnedText = " В вашем списке покупок это уже закреплено ("
                        .. ((pin > 0) and pin or line.qty) .. " шт.)."
                end
            end

            -- A vendor we have actually stood in front of. Without one there is
            -- no route to offer and the card simply does not get a button.
            local place = ns.Places:ForItem(line.itemID)
            local need
            -- LEAD WITH THE GAP when there is a big one. A 167-gold purchase
            -- in front of a player holding one gold is not a shopping list, and
            -- burying that under "не хватает X" read as a detail.
            local ratio = U.div(line.subtotal, math.max(1, afford.money or 0), nil)
            if ratio and ratio > Engine.OUT_OF_REACH_RATIO then
                local canBuy = (afford.money and line.unit and line.unit > 0)
                    and math.floor(afford.money / line.unit) or 0
                need = Engine.OutOfReachText(line.subtotal, afford.money, ratio)
                    .. ((canBuy > 0)
                        and (" На свои деньги хватит на " .. canBuy .. " шт. из "
                             .. line.qty .. ".")
                        or " На свои деньги не хватит даже на одну.")
            elseif afford.affordable == true then
                need = "У вас " .. U.money(afford.money) .. " — хватает."
            elseif afford.affordable == false then
                need = "Не хватает " .. U.money(afford.shortfall or 0) .. " на весь список."
            else
                -- Some lines have no price, so the total is an understatement
                -- and "you can afford it" would be a claim we cannot back.
                need = "У вас " .. U.money(afford.money) .. ". Полную сумму списка"
                    .. " не назову: на " .. (afford.unknownLines or 0) .. " "
                    .. U.plural(afford.unknownLines or 0, "позицию", "позиции", "позиций")
                    .. " цены нет."
            end
            -- Хвост «почему» без пометки о закреплении: карточка своего списка
            -- говорит про закрепление первой фразой, и второй раз там не надо.
            local priceTail = ". Цена: "
                .. ns.PriceProvider:Label(line.unit, line.conf, line.src, line.age)
                .. " за штуку."
                .. ((line.have and line.have > 0 and line.gross)
                    and (" Всего нужно " .. line.gross .. ", своего есть "
                         .. line.have .. ".")
                    or "")
            -- ГДЕ КУПИТЬ И СКОЛЬКО СЭКОНОМИШЬ - СЛОВАМИ, А НЕ ТОЛЬКО В ЧИСЛЕ.
            --
            -- Цена выше уже взята по потолку (Price:Buy), то есть сумма верна и
            -- без этой фразы. Но игрок по ней пойдёт НА АУКЦИОН, если не
            -- сказать, что то же самое лежит на полке, и заплатит разницу
            -- второй раз. Фразу выдаёт PriceProvider - одну на все ветки.
            local ceilText = ns.PriceProvider:CeilingText(line.itemID)
            if ceilText then
                priceTail = priceTail .. " " .. U.capitalize(U.endSentence(ceilText))
                if line.vendorSaving and line.vendorSaving > 0 and line.qty > 1 then
                    priceTail = priceTail .. " На все " .. line.qty
                        .. " шт. экономия " .. U.money(line.vendorSaving) .. "."
                end
            end
            local whyTail = priceTail .. pinnedText

            local hint = ns.Places:CardHint(place)
            if hint then
                need = need .. " Торговец: " .. hint .. "."
            elseif line.vendorCheaper then
                -- ДЕШЕВЛЕ У ТОРГОВЦА, А У КАКОГО - НЕ ЗНАЮ, И ТАК И СКАЗАНО.
                --
                -- Кеш цен торговцев Auctionator хранит цену по предмету, а не по
                -- тому, у кого стояли. Подставить сюда торговца из пакета
                -- сообщества значило бы назвать фактом то, чего мы не видели.
                need = need .. " У какого торговца — не знаю: цена есть, а его"
                    .. " имени в записи нет."
            end

            -- Товар нужен ТОЛЬКО под совет, числам которого я не верю. Молча
            -- выкинуть строку нельзя (сумма списка поехала бы из-за суждения,
            -- которого игрок не видит), поэтому предупреждение едет сюда.
            local suspectWarning
            if line.suspectOnly then
                suspectWarning = "Это нужно только под совет, числам которого я"
                    .. " сам не верю (" .. (line.suspectWhy or "числа не сходятся")
                    .. "). Я бы сначала проверил цену на аукционе, а потом покупал."
                need = need .. " " .. suspectWarning
            end

            local card = {
                key = "buy:" .. line.itemID,
                kind = ns.KIND.BUY,
                icon = line.texture or ns.KIND_ICON.BUY,
                title = "Купить: " .. line.name .. " x" .. line.qty,
                benefit = U.money(line.subtotal),
                benefitKind = "spend",
                benefitValue = -line.subtotal,
                why = useText .. whyTail,
                -- Кто попросил этот материал, по ключам советов, и остаток
                -- строки «почему» без первой фразы: порог мелкой денежной
                -- выгоды убирает советы ПОСЛЕ покупок, и тогда первую фразу
                -- надо переписать по тем, кто остался (Engine:ApplyMoneyFloor).
                buyFor = line.forCards,
                buyWhyTail = whyTail,
                -- Тот же хвост без пометки о закреплении и название с
                -- количеством: из них собирается карточка своего списка, когда
                -- заказчиков-советов у строки не остаётся (Engine.AsOwnListCard).
                buyOwnTail = priceTail,
                buyName = line.name,
                buyQty = line.qty,
                need = need,
                action = {
                    kind = "shop", label = "В список покупок",
                    itemID = line.itemID, qty = line.qty,
                },
                itemID = line.itemID,
                link = line.link,
                cost = line.subtotal,
                conf = line.suspectOnly
                    and U.worstConf(line.conf or CONF.UNKNOWN, CONF.ESTIMATE)
                    or line.conf,
                axes = axes,
                place = place,
                suspectOnly = line.suspectOnly,
                -- A buy card has no plan, so the diagnostics had nowhere to
                -- read the price provenance from and recorded nil next to a
                -- price it was showing the player. The line already knows.
                matPrice = { unit = line.unit, src = line.src, conf = line.conf,
                             age = line.age, qty = line.qty },
            }
            -- Ни одного совета-заказчика, только закрепление игрока: это не
            -- совет, и называться советом оно не должно.
            if #uses == 0 and pinnedByHand then Engine.AsOwnListCard(card) end
            self:Add(card)
        end
    end
    if added == 0 then
        local total = ns.ShoppingList:Count()
        self.branchNote.buy = (total == 0)
            and "покупать нечего: ни один совет не требует материалов со стороны"
            or "в списке закупки " .. total .. " "
                .. U.plural(total, "позиция", "позиции", "позиций")
                .. ", но купить их негде — это добыча, не товар"
    end
    return added
end

-- Branch: vendor arbitrage ---------------------------------------------
--
-- Купить у торговца, продать на аукционе. Для персонажа с пятью золотыми это
-- самый подходящий способ заработать: вкладывать надо мало, делать ничего не
-- надо, и одна сторона сделки заведомо известна - торговец не торгуется.
--
-- Карточка идёт в тот же единый список, что и всё остальное, и несёт всё, без
-- чего совет бесполезен: русское название, itemID, торговца с зоной и
-- координатами, цену с валютой, ограничения продажи и прибыль ПОСЛЕ сбора.

function Engine:AddArbitrageCards(snap, scales)
    if not ns.VendorArbitrage then return 0 end
    local opps = ns.VendorArbitrage:Opportunities()
    local added = 0

    for _, opp in ipairs(opps) do
        if added >= ns.MAX_CARDS_PER_KIND then break end
        added = added + 1

        local axes = blankAxes()
        axes.profit = U.soft(opp.profit, scales.profit)
        axes.spend = U.soft(opp.ask, scales.spend)
        -- Готовность: ничего крафтить не надо, но надо дойти до торговца.
        axes.ready = (opp.place and opp.place.routable) and 0.8 or 0.4

        local why = "У торговца "
            .. ns.PriceProvider:Label(opp.ask, opp.askConf, opp.askSrc)
            .. ", на аукционе дают " .. U.money(opp.revenue)
            .. " (сбор аукциона уже вычтен). Разница "
            .. U.moneyDelta(opp.profit) .. " за штуку, это "
            .. U.pct(opp.marginShare) .. " наценки."
        if opp.revInfo and opp.revInfo.historyNote then
            why = why .. " " .. U.capitalize(opp.revInfo.historyNote) .. "."
        end
        -- Возраст цены - на карточке: вся схема держится на одной рыночной цене.
        if opp.revAge and opp.revAge >= (ns.PRICE_AGE_SAY_SECONDS or 86400) then
            why = why .. " Цена на аукционе не сегодняшняя: "
                .. (U.ageText(opp.revAge) or "давно") .. "."
        end
        why = why .. " " .. ns.VendorArbitrage:StockText(opp)
        -- Откуда цена торговца, если за ней стоит один источник.
        local srcText = ns.VendorArbitrage:AskSourceText(opp)
        if srcText then why = why .. " " .. srcText end
        -- КОНЦЕНТРАЦИЯ. Сказано на карточке, а не только посчитано: игрок
        -- читает карточку, а не диагностику.
        if opp.concentration then
            why = why .. " Осторожно: " .. opp.concentration.text .. "."
        end
        -- НЕПРАВДОПОДОБНАЯ НАЦЕНКА. Порядок важен: сначала всё, что объясняет
        -- расчёт, потом предупреждение о том, что расчёту верить нельзя.
        local verdict = opp.markupVerdict
        if verdict and verdict.code == "markup-note" then
            why = why .. " " .. U.capitalize(verdict.text) .. "."
        end

        local need = ns.VendorArbitrage:WhereText(opp)
        if opp.sellable == nil then
            need = need .. " Выставляется ли эта вещь на аукцион, я пока не"
                .. " проверил: клиент ещё не отдал её данные."
        end

        local benefit = U.moneyDelta(opp.profit) .. " за штуку"
        local suspect
        -- В диагностику это пишет самопроверка, а не ветка: странности,
        -- поднятые во время сборки, стираются перед проверками
        -- (Diag:ClearSuspicions), и запись отсюда просто не доживала бы до
        -- файла. Ветка помечает карточку, самопроверка это видит и заносит.
        if verdict and verdict.code == "markup-impossible" then
            -- ПОМЕТКУ ПЕЧАТАЕТ Logic/Risk.lua, А НЕ ЭТА ВЕТКА.
            --
            -- Здесь стояли свои «сомнительно: » в заголовок и своё «Числа этой
            -- карточки не сходятся: …» в КОНЕЦ строки «почему». Формулировки
            -- совпадали с теми, что печатает Risk, случайно - их правили
            -- одновременно, - а место было хуже: строка «почему» на экране одна
            -- и обрезается шириной окна, так что дописанное в конец игрок не
            -- читал. Risk:RenderDoubts ставит ту же мысль первой фразой.
            suspect = { code = "arbitrage-markup-impossible", text = verdict.text,
                        ratio = verdict.markup }
            -- И ВНИЗ СПИСКА. Прибыль, которой я сам не верю, не должна тянуть
            -- карточку наверх: ось прибыли у такой карточки срезается, иначе
            -- «+10з за штуку» с пометкой «сомнительно» всё равно стоит выше
            -- настоящих советов.
            axes.profit = axes.profit * 0.25
        end

        -- ОБЛИК. Схема та же, что у перекупки лота: купить и продать снова, то
        -- есть вещь пройдёт через руки игрока и уйдёт. Товар с полки торговца
        -- привязанным не бывает - поэтому привязка здесь известна точно.
        local looks = ns.Appearance and ns.Appearance:Check({
            itemID = opp.itemID, link = opp.link, name = opp.name,
            bound = false,
        }, "sell", "arbitrage") or nil

        self:Add(Engine.ApplyLooks({
            key = "arb:" .. opp.itemID,
            kind = ns.KIND.ARBITRAGE,
            icon = opp.texture or ns.KIND_ICON.ARBITRAGE,
            title = "Купить и перепродать: " .. opp.name,
            benefit = benefit,
            benefitKind = "gold",
            benefitValue = opp.profit,
            revenue = opp.revenue,
            revOrigin = opp.revInfo,
            why = why,
            need = need,
            suspect = suspect,
            concentration = opp.concentration,
            markupVerdict = verdict,
            action = { kind = "showItem", label = "Показать предмет",
                       itemID = opp.itemID, link = opp.link },
            link = opp.link,
            itemID = opp.itemID,
            cost = opp.ask,
            conf = opp.conf,
            axes = axes,
            place = opp.place,
            arbitrage = opp,
            matPrice = { unit = opp.ask, src = opp.askSrc, conf = opp.askConf },
        }, looks))
    end

    if added == 0 then
        local skipped = ns.VendorArbitrage.lastCurrencySkipped or 0
        self.branchNote.arbitrage = (skipped > 0)
            and ("ни одной перепродажи: у " .. skipped .. " "
                 .. U.plural(skipped, "товара", "товаров", "товаров")
                 .. " цена у торговца не в золоте, остальное дешевле на аукционе,"
                 .. " чем у торговца")
            or "ни одного товара, который у торговца дешевле, чем на аукционе"
    end
    return added
end

-- Branch: disenchant ---------------------------------------------------
--
-- Единственная ветка, где результат РАНДОМНЫЙ, и поэтому единственная, где в
-- заголовке стоит слово «ожидание». На одном распыле посчитанное не сбудется
-- почти никогда - у зелёной вещи 75/20/5 на пыль/эссенцию/осколок - и говорить
-- об этом надо прямым текстом, а не сноской внизу.

function Engine:AddDisenchantCards(snap, scales)
    if not ns.Disenchant then return 0 end
    local opps = ns.Disenchant:Opportunities(snap)
    local added = 0

    for _, opp in ipairs(opps) do
        if added >= ns.MAX_CARDS_PER_KIND then break end
        added = added + 1

        local axes = blankAxes()
        axes.profit = U.soft(opp.profit, scales.profit)
        axes.spend = U.soft(opp.cost, scales.spend)
        axes.ready = 0.6

        -- ОБЛИК. Вопрос задаётся здесь, у карточки: распыл необратим, а
        -- кандидатов на него считается впятеро больше, чем попадает на экран.
        local looks = ns.Appearance and ns.Appearance:Check({
            itemID = opp.itemID, link = opp.link, name = opp.name,
            quality = opp.quality, classID = opp.classID,
            bound = opp.bound, bindType = opp.bindType,
        }, "disenchant", "disenchant") or nil

        local why = "Купить за " .. U.money(opp.cost)
            .. ", распылить — в среднем выйдет " .. U.money(opp.expected)
            .. ". Что может выпасть: " .. ns.Disenchant:ProductsText(opp) .. "."
            .. " " .. ns.Disenchant:CaveatText(opp)

        self:Add(Engine.ApplyLooks({
            key = "de:" .. opp.itemID,
            kind = ns.KIND.DISENCHANT,
            icon = ns.KIND_ICON.DISENCHANT,
            -- «ОЖИДАНИЕ» В ЗАГОЛОВКЕ, А НЕ В СНОСКЕ. Игрок читает заголовок
            -- первым и часто единственным.
            title = "Распылить: " .. opp.name,
            benefit = "ожидание ~" .. U.money(opp.profit),
            benefitKind = "gold",
            benefitValue = opp.profit,
            revenue = opp.expected,
            -- Выручка здесь не наблюдение и не гарантия: это расчёт. Пометка
            -- нужна, чтобы проверка 27 не приняла её за подтверждённую цену.
            revOrigin = { src = "disenchant-expectation", market = false,
                          observed = false, expectation = true },
            why = why,
            need = "Распыляйте сами: я ничего не покупаю и не распыляю."
                .. " И помните, что это средний результат, а не ваш.",
            action = { kind = "showItem", label = "Показать предмет",
                       itemID = opp.itemID },
            itemID = opp.itemID,
            cost = opp.cost,
            conf = opp.conf,
            axes = axes,
            disenchant = opp,
            expectation = true,
            matPrice = { unit = opp.cost, src = opp.costSrc, conf = opp.costConf },
        }, looks))
    end

    if added == 0 then
        self.branchNote.disenchant = ns.Disenchant.lastReason
            or "распылять нечего выгодного"
    end
    return added
end

-- Branch: resale -------------------------------------------------------
--
-- Перекупить лот заметно ниже рынка. Самый опасный совет в аддоне: «дешевле
-- рынка» бывает ошибкой продавца, упавшим рынком и неликвидом, и различить их
-- можно только по своей истории. Поэтому без истории карточки не будет.

function Engine:AddResaleCards(snap, scales)
    if not ns.Resale then return 0 end
    local opps = ns.Resale:Opportunities(snap)
    local added = 0

    for _, opp in ipairs(opps) do
        if added >= ns.MAX_CARDS_PER_KIND then break end
        added = added + 1

        local axes = blankAxes()
        axes.profit = U.soft(opp.profit, scales.profit)
        axes.spend = U.soft(opp.live, scales.spend)
        -- Купить можно сразу, но продаваться будет не моментально.
        axes.ready = 0.5

        -- ОБЛИК. Вопрос у карточки, а не в расчёте: кандидатов на перекупку
        -- перебирается две с половиной сотни, советом становится один.
        local looks = ns.Appearance and ns.Appearance:Check({
            itemID = opp.itemID, link = opp.link, name = opp.name,
            bound = opp.bound,
        }, "sell", "resale") or nil

        self:Add(Engine.ApplyLooks({
            key = "resell:" .. opp.itemID,
            kind = ns.KIND.RESELL,
            icon = opp.texture or ns.KIND_ICON.RESELL,
            title = "Перекупить: " .. opp.name,
            benefit = U.moneyDelta(opp.profit),
            benefitKind = "gold",
            benefitValue = opp.profit,
            revenue = opp.gross,
            revOrigin = { src = "foreign", market = true, observed = true,
                          historyNote = opp.spread and opp.spread.text or nil },
            why = ns.Resale:WhyText(opp),
            need = "Покупать и выставлять — вам: я аукционом не управляю."
                .. " Если лот не продастся, залог не вернётся.",
            action = { kind = "showItem", label = "Показать предмет",
                       itemID = opp.itemID, link = opp.link },
            link = opp.link,
            itemID = opp.itemID,
            cost = opp.live,
            conf = opp.conf,
            axes = axes,
            resale = opp,
            matPrice = { unit = opp.live, src = "auctionator", conf = opp.conf },
        }, looks))
    end

    if added == 0 then
        self.branchNote.resale = ns.Resale.lastReason
            or "лотов заметно ниже рынка нет"
    end
    return added
end

-- Branch: what the price history says ----------------------------------
--
-- Не совет, а знание: по предметам, которые игрок делает и продаёт, своя
-- история уже может сказать «сейчас нетипично дорого» или «нетипично дёшево».
-- Одна информационная карточка на весь список - иначе она вытеснит советы.

function Engine:AddPriceInfoCards(snap, scales)
    local MH = ns.MarketHistory
    if not MH then return 0 end
    local cov = MH:Coverage()
    if (cov.items or 0) == 0 then
        self.branchNote.priceinfo = "суточных слепков цен ещё нет"
        return 0
    end

    -- Самое выраженное отклонение среди того, что игрок умеет сделать: про
    -- чужие предметы говорить незачем.
    local best
    for _, recipe in ipairs(ns.RecipeBook:Iterate(function(r)
        return r.learned and r.output
    end)) do
        local itemID = recipe.output
        local live = Api:AuctionPrice(itemID)
        if live then
            local v = MH:Verdict(itemID, live)
            if v and (v.flag == MH.FLAG.HIGH_OUTLIER or v.flag == MH.FLAG.LOW_OUTLIER
                      or v.outsideRange) then
                local weight = (v.ratio or 1) + (v.outsideRange and 0.5 or 0)
                if (not best) or weight > best.weight then
                    local info = Api:ItemInfo(itemID)
                    best = {
                        weight = weight, itemID = itemID, verdict = v, live = live,
                        name = (info and info.name) or U.itemFallbackName(itemID),
                        trend = MH:Trend(itemID),
                    }
                end
            end
        end
    end

    if not best then
        self.branchNote.priceinfo = "по моим наблюдениям цены сейчас обычные —"
            .. " ни одного заметного отклонения"
        return 0
    end

    local v = best.verdict
    local badge = MH:Badge(v)
    local why = U.capitalize(v.text or "")
    -- Текст вердикта приходит без точки на конце; без неё следующая фраза
    -- приклеивалась: «…истории ещё мало) За 3 дня цена выросла».
    why = U.endSentence(why)
    -- ТРЕНД ПО ЗАПИСЯМ НЕ СПОРИТ С ЗАГОЛОВКОМ. Тренд считается по записанным
    -- дням, а «сейчас дёшево» - по живой цене против них. Когда цена сейчас
    -- ниже всех записей, а записи росли, на карточке стояло «это ниже всего,
    -- что я видел. За 3 дня цена выросла на 16%» - два утверждения, которые
    -- читаются как противоположные. В таком случае тренд не пишется: карточка
    -- про то, что сейчас, а не про то, что было до.
    local trendClashes = best.trend and (
        (v.belowRange and best.trend.direction == "up")
        or (v.aboveRange and best.trend.direction == "down"))
    if best.trend and best.trend.direction ~= "flat" and not trendClashes then
        why = why .. string.format(" За %d %s цена %s на %d%%.",
            best.trend.days, U.plural(best.trend.days, "день", "дня", "дней"),
            (best.trend.direction == "up") and "выросла" or "упала",
            U.round(math.abs(best.trend.changePct)))
    end
    -- КОРОТКАЯ ВЫБОРКА НАЗЫВАЕТСЯ КОРОТКОЙ - ОДИН РАЗ. Вердикт уже говорит это
    -- сам («выборка короткая: сервер молодой…»); второй раз теми же словами -
    -- это не осторожность, а повтор.
    if cov.short then
        if U.contains(U.lower(why), "выборка короткая") then
            why = why .. " Это повод присмотреться, а не вывод."
        else
            why = why .. " Выборка короткая: сервер молодой, у меня всего "
                .. (cov.deepestDays or 0) .. " "
                .. U.plural(cov.deepestDays or 0, "день", "дня", "дней")
                .. " наблюдений — это повод присмотреться, а не вывод."
        end
    end

    self:Add({
        key = "priceinfo:" .. best.itemID,
        kind = ns.KIND.PRICE_INFO,
        icon = ns.KIND_ICON.PRICE_INFO,
        title = (v.flag == MH.FLAG.HIGH_OUTLIER or v.aboveRange)
            and ("Сейчас дорого: " .. best.name)
            or ("Сейчас дешево: " .. best.name),
        benefit = badge or ((v.aboveRange and "выше обычного") or "ниже обычного"),
        benefitKind = "info",
        why = why,
        -- «ЕСЛИ УМЕЕТЕ ЭТО ДЕЛАТЬ» - ОГОВОРКА ПРО ТО, ЧТО Я И ТАК ЗНАЮ.
        --
        -- Отбор выше идёт ровно по ВЫУЧЕННЫМ рецептам этого персонажа
        -- (RecipeBook:Iterate, r.learned), то есть умеет он это наверняка. А
        -- строка «чего не хватает» сомневалась в этом вслух - вежливый оборот,
        -- который не отвечает ни на один вопрос и при этом сеет сомнение там,
        -- где его нет. Теперь сказано то, что известно.
        need = (v.flag == MH.FLAG.HIGH_OUTLIER or v.aboveRange)
            and "Рецепт у вас выучен — сейчас хороший момент продать."
            or "Рецепт у вас выучен. Продавать сейчас хуже обычного,"
               .. " а купить готовое — дешевле обычного.",
        action = { kind = "showItem", label = "Показать предмет", itemID = best.itemID },
        itemID = best.itemID,
        conf = cov.short and CONF.ESTIMATE or CONF.CACHED,
        axes = { power = 0, skill = 0, profit = 0, spend = 0, ready = 0.1 },
        informational = true,
        priceVerdict = v,
    })
    return 1
end

-- Branch: Merchant's Favor ---------------------------------------------
--
-- САМАЯ ПОЛЕЗНАЯ ВЕТКА ДЛЯ ЭТОГО ПЕРСОНАЖА, и причина в одном наблюдении:
-- рецепты за Благосклонность торговца гейтятся НАВЫКОМ, а не уровнем. У него
-- навык 225 при уровне 26 - значит доступно то, за чем остальные приходят на
-- 35+. Сам он этого не узнает: в игре нигде не написано, что порог тут навык.
--
-- Карточек две, и обе в том же едином списке:
--   * одна сводная - сколько Favor нужно, сколько из этого носится сейчас, и
--     как Favor заработать из того, что уже лежит в сумках;
--   * и до трёх конкретных покупок, по пользе на единицу Favor.

function Engine:AddFavorCards(snap, scales)
    if not ns.Favor then return 0 end
    local plan, why, detail = ns.Favor:Plan(snap)
    if not plan then
        if why == "off-school" then
            -- НЕ «ПОДХОДЯЩИХ ПОКУПОК НЕ НАШЛОСЬ». Персонаж и профессия в
            -- порядке: весь справочник, который у меня есть, несёт школьный
            -- урон, который по весам этого персонажа стоит ноль. Сказать надо
            -- именно это - и числами, которые игрок может проверить в
            -- подсказке предмета.
            local labels = {}
            for _, stat in ipairs((detail and detail.stats) or {}) do
                labels[#labels + 1] = tostring(ns.GearAdvisor
                    and ns.GearAdvisor:StatLabel(stat) or stat)
            end
            self.branchNote.favor =
                "покупки за Благосклонность, которые я знаю, несут "
                .. ((#labels > 0) and table.concat(labels, ", ") or "школьный урон")
                .. " — а по вашим весам это стоит ноль, значит вашему классу"
                .. " такой урон не идёт. Отложено "
                .. ((detail and detail.count) or 0) .. " "
                .. U.plural((detail and detail.count) or 0,
                    "позиция", "позиции", "позиций")
                .. " на " .. ((detail and detail.favor) or 0) .. " Favor."
                .. " Под вашу школу данных по этой ветке у меня нет"
                .. ((detail and detail.certainty == "unknown")
                    and ", а школу я и не определил — ни по спеку, ни по надетым вещам"
                    or "")
        elseif why == "no-data" then
            self.branchNote.favor = "данных про Благосклонность торговца нет"
        elseif why == "no-data-for-professions" then
            -- НЕ «НАВЫКА НЕ ХВАТАЕТ». Данные по этой ветке собраны под
            -- портняжку и чары; у персонажа с алхимией и инженерным делом
            -- раньше выходил полный список портняжных паттернов, у каждого из
            -- которых честно написано «навыка пока не хватает» - и игрок читал
            -- это как «надо качать навык» по профессии, которой у него нет.
            local mine = {}
            for _, prof in ipairs(snap.professions or {}) do
                if prof.crafting and prof.name then
                    mine[#mine + 1] = U.profLabel(prof.name)
                end
            end
            self.branchNote.favor =
                "данных про Благосклонность торговца по вашим профессиям у меня"
                .. " нет: собрано по портняжному делу и наложению чар, а у вас "
                .. ((#mine > 0) and table.concat(mine, ", ")
                    or "клиент профессий ещё не назвал")
                .. ". Навык тут не при чём"
        else
            self.branchNote.favor = "подходящих покупок за Благосклонность не нашлось"
        end
        return 0
    end

    -- Только то, что навык УЖЕ позволяет и чего у игрока ЕЩЁ НЕТ.
    --
    -- Второе условие появилось из живой проверки: первая же карточка советовала
    -- потратить 45 Favor на паттерн Мерцающего посоха, который лежал у игрока в
    -- сумке. Такие позиции не выбрасываются молча - они пересчитываются в
    -- сводную карточку, где сказано, сколько Favor экономится.
    local ready, have, haveFavor = {}, {}, 0
    -- НЕ ЛУЧШЕ ТОГО, ЧТО УЖЕ НАДЕТО - ТОЖЕ НЕ ПОКУПКА.
    --
    -- Живая жалоба: «За Благосклонность: Жемчужные сапоги, +15 баллов» при
    -- надетых сапогах лучше; «Сфера мистического прозрения» в левую руку при
    -- двуручном посохе. Такие позиции не выбрасываются молча - они
    -- перечисляются в сводной карточке с причиной (см. Favor:Describe).
    local worse, worseFavor = {}, 0
    -- Сколько позиций мы не смогли СОПОСТАВИТЬ с профессией игрока. Это не то
    -- же самое, что «навыка не хватает», и в живой игре было именно это: клиент
    -- назвал портняжке номер линии 2948 вместо 197, навык не нашёлся, и ветка
    -- объявила нехватку навыка при навыке 225 против порога 60.
    local unresolved = 0
    for _, d in ipairs(plan.items) do
        if d.lineResolved == false then unresolved = unresolved + 1 end
        if d.affordableBySkill then
            if d.alreadyHave then
                have[#have + 1] = d
                haveFavor = haveFavor + (d.favor or 0)
            elseif d.notUpgrade then
                worse[#worse + 1] = d
                worseFavor = worseFavor + (d.favor or 0)
            else
                ready[#ready + 1] = d
            end
        end
    end
    local function worseText()
        local names = {}
        for i = 1, math.min(3, #worse) do
            local d = worse[i]
            local reason
            if d.blockedByTwoHand then
                reason = "в левую руку, а у вас двуручное"
                    .. (d.againstName and (" — " .. d.againstName) or "")
            elseif d.againstName then
                reason = "не лучше, чем " .. d.againstName
            else
                reason = "не лучше надетого"
            end
            names[#names + 1] = tostring(d.name) .. " (" .. reason .. ")"
        end
        return #worse .. " "
            .. U.plural(#worse, "позицию", "позиции", "позиций")
            .. " не советую — "
            .. table.concat(names, ", ")
            .. ((#worse > 3) and (" и ещё " .. (#worse - 3)) or "")
            .. ": это " .. worseFavor .. " Favor, которые тратить незачем"
    end
    if #ready == 0 then
        if #worse > 0 then
            -- Всё, что осталось купить, хуже надетого: это ответ, а не тишина.
            self.branchNote.favor =
                "покупать за Благосклонность сейчас нечего: " .. worseText()
                .. ((#have > 0)
                    and (". Остальное доступное по навыку у вас уже есть ("
                         .. #have .. " "
                         .. U.plural(#have, "позиция", "позиции", "позиций") .. ")")
                    or "")
        elseif #have > 0 then
            self.branchNote.favor =
                "всё, что доступно по навыку за Благосклонность, у вас уже есть"
                .. " (" .. #have .. " "
                .. U.plural(#have, "позиция", "позиции", "позиций")
                .. ", это " .. haveFavor .. " сэкономленных Favor)"
        elseif unresolved >= #plan.items then
            -- НИ ОДНУ позицию не удалось привязать к профессии: виноват не
            -- навык игрока, а то, что я не сопоставил номер линии навыка с
            -- порогом. Так и надо сказать.
            self.branchNote.favor =
                "не смог сопоставить ваши профессии с порогами навыка за"
                .. " Благосклонность: номер линии навыка, который отдал клиент,"
                .. " моим данным незнаком. Это моя слепота, а не нехватка навыка"
        else
            -- НЕ ВАЛИТЬ НА НАВЫК ТО, ЧТО ОТОБРАЛ Я САМ.
            --
            -- Часть покупок могла уйти из плана по школе (их школьный урон
            -- стоит у этого персонажа ноль). Если про это не сказать, игрок
            -- читает «навыка не хватает» и идёт качать навык, которого ему
            -- хватает - ровно та ошибка, из-за которой рядом стоит ветка про
            -- номер линии навыка.
            local off = plan.offSchool or {}
            self.branchNote.favor =
                "навыка пока не хватает ни на одну покупку за Благосклонность торговца"
                .. ((#off > 0)
                    and (". А ещё " .. #off .. " "
                         .. U.plural(#off, "покупку", "покупки", "покупок")
                         .. " я отложил не из-за навыка: их школьный урон по"
                         .. " вашим весам стоит ноль, то есть вашему классу он"
                         .. " не идёт")
                    or "")
        end
        return 0
    end

    local routes = ns.Favor:EarnRoutes(snap)
    local readyFavor, unknownCrates, readyCrates = ns.Favor:ReadyFavor(routes)
    local added = 0

    -- 1. Сводная карточка.
    local nowList = {}
    for _, d in ipairs(ready) do
        if d.wearableNow then nowList[#nowList + 1] = d.name end
    end
    local favorNeeded = 0
    for _, d in ipairs(ready) do favorNeeded = favorNeeded + (d.favor or 0) end

    local why1 = ns.Favor:HeadlineText(plan, snap)
        .. " Доступно по навыку: " .. #ready .. " "
        .. U.plural(#ready, "покупка", "покупки", "покупок")
        .. " за " .. favorNeeded .. " Favor."
    if #nowList > 0 then
        why1 = why1 .. " Из них надевается уже сейчас: " .. #nowList .. " ("
            .. table.concat(nowList, ", ", 1, math.min(3, #nowList))
            .. ((#nowList > 3) and (" и ещё " .. (#nowList - 3)) or "") .. ")."
    end
    if #have > 0 then
        local names = {}
        for i = 1, math.min(3, #have) do
            names[#names + 1] = have[i].name
                .. (have[i].alreadyKnown and " (рецепт выучен)" or " (уже есть)")
        end
        why1 = why1 .. " " .. #have .. " "
            .. U.plural(#have, "позицию", "позиции", "позиций")
            .. " покупать не нужно — "
            .. table.concat(names, ", ")
            .. ((#have > 3) and (" и ещё " .. (#have - 3)) or "")
            .. ": это " .. haveFavor .. " Favor, которые можно не тратить."
    end
    if #worse > 0 then
        why1 = why1 .. " Ещё " .. worseText() .. "."
    end
    if readyCrates > 0 then
        why1 = why1 .. " Прямо сейчас у вас есть материал на " .. readyCrates .. " "
            .. U.plural(readyCrates, "ящик", "ящика", "ящиков")
            .. ": это " .. ((readyFavor > 0) and ("+" .. readyFavor .. " Favor")
                or "неизвестно сколько Favor")
            .. (unknownCrates > 0
                and (", плюс " .. unknownCrates .. " "
                     .. U.plural(unknownCrates, "ящик", "ящика", "ящиков")
                     .. ", награду за которые источник не знает")
                or "") .. "."
    end
    -- ШКОЛА - НА КАРТОЧКЕ, А НЕ В ГОЛОВЕ У АДДОНА. Когда школу определить не
    -- удалось, так и написано; когда часть позиций отложена по школе - сказано,
    -- сколько и почему.
    local schoolText = ns.Favor:SchoolText(plan)
    if schoolText then why1 = why1 .. " " .. schoolText end
    why1 = why1 .. " " .. ns.Favor:CaveatText()

    local needText
    if readyCrates > 0 then
        local bits = {}
        for _, r in ipairs(routes) do
            if r.ready and #bits < 3 then
                bits[#bits + 1] = r.name .. " x" .. r.need
                    .. " -> ящик «" .. r.kind .. "» (" .. r.rank .. ")"
            end
        end
        needText = "Сдать можно: " .. table.concat(bits, "; ")
            .. ". Материал должен лежать одним стаком, и один ящик закрывается"
            .. " одним набором, а не всеми сразу."
    else
        local closest
        for _, r in ipairs(routes) do
            if not r.ready and (not closest or r.short < closest.short) then closest = r end
        end
        needText = closest
            and ("Ближе всего к сдаче: " .. closest.name .. " — есть "
                 .. closest.have .. " из " .. closest.need
                 .. ", не хватает " .. closest.short .. ".")
            or "Материала на ящики в сумках сейчас нет."
    end

    added = added + 1
    self:Add({
        key = "favor:plan",
        kind = ns.KIND.FAVOR,
        icon = ns.KIND_ICON.FAVOR,
        title = "Благосклонность торговца: " .. #ready .. " "
            .. U.plural(#ready, "покупка", "покупки", "покупок")
            .. " доступны по навыку",
        benefit = favorNeeded .. " Favor"
            .. ((#nowList > 0) and (", " .. #nowList .. " можно носить сейчас") or ""),
        benefitKind = "info",
        why = why1,
        -- Адрес источника - в подсказку, а не в строку «почему»: см.
        -- Favor:CaveatText, там написано, почему он оттуда убран.
        sourceNote = ns.Favor:SourceText(),
        need = needText,
        action = { kind = "noop" },
        conf = plan.conf,
        axes = { power = 0.35, skill = 0, profit = 0, spend = 0, ready = 0.4 },
        favorPlan = plan,
        favorRoutes = routes,
    })

    -- 2. Конкретные покупки, по пользе на единицу Favor.
    --
    -- БЕЗ ИМЕНИ ПРЕДМЕТА КАРТОЧКИ НЕТ. «За Благосклонность: Предмет #253897» -
    -- это не совет: игрок не найдёт в игре то, чего не может прочитать. Клиент
    -- отдаст имя через GET_ITEM_INFO_RECEIVED, и карточка появится на следующем
    -- пересчёте - точно так же, как это уже делает ветка экипировки.
    local nameless = 0
    for _, d in ipairs(ready) do
        if added > 3 then break end
        local info = d.outItemID and Api:ItemInfo(d.outItemID) or nil
        -- ЗДЕСЬ СТОЯЛ `goto continue`, И ИЗ-ЗА НЕГО АДДОН НЕ ЗАГРУЖАЛСЯ ВОВСЕ.
        --
        -- `goto` и метки `::continue::` появились в Lua 5.2. Клиент игры - Lua
        -- 5.1, там этого синтаксиса нет: файл не компилировался целиком, вместе
        -- с ним не выполнялось `ns.ActionEngine = Engine` на 28-й строке, и
        -- каждый пересчёт падал на `attempt to index field 'ActionEngine'
        -- (a nil value)`. В диагностике игрока это 72 падения Rebuild, 65
        -- recompute и 3 Render панели за одну сессию - то есть весь аддон.
        --
        -- Тесты этого не видели: они гоняются через texluajit, а LuaJIT
        -- поддерживает расширения 5.2 и `goto` принимает. Проверка диалекта
        -- теперь живёт в Tests/loadcheck.lua и в наборе test_load.
        --
        -- Пропуск шага сделан через `else`, а не через выход из блока: это та же
        -- логика без синтаксиса, которого в игре нет.
        if not (info and info.name) then
            -- БЕЗ ИМЕНИ ПРЕДМЕТА КАРТОЧКИ НЕТ - см. комментарий выше цикла.
            nameless = nameless + 1
        else
            added = added + 1
            local axes = blankAxes()
            -- Польза есть, но получить её нельзя за золото - только за время.
            -- Поэтому spend остаётся нулём, а power несёт настоящую оценку.
            -- ОЦЕНИВАЕТСЯ ПРИРОСТ, а не вся вещь: d.score - это оценка
            -- предмета против пустого слота, и именно она давала «+15» у
            -- сапог хуже надетых. Нет прироста (сравнить было нечем) - нет и
            -- числа: ось остаётся на уровне «польза есть, размер неизвестен».
            if d.gain then
                axes.power = U.soft(d.gain, scales.power)
            elseif d.score then
                axes.power = 0.15
            end
            axes.ready = d.wearableNow and 0.6 or 0.2

            local why = "Порог — навык " .. tostring(d.skillNeeded)
                .. " по «" .. tostring(U.profLabel(d.professionName) or "?") .. "», у вас "
                .. tostring(d.skill) .. ": хватает."
                .. " Цена: " .. tostring(d.favor) .. " Favor."
            -- ТРИ РАЗНЫХ ОТВЕТА ПРО УРОВЕНЬ, и путать их нельзя. На настоящих
            -- данных у жемчужных вещей req = 0 - это «уровень не требуется
            -- вообще», а не «требуется нулевой»; текст «Предмет требует 0
            -- уровень» читался как сбой. А nil - это «не знаю», и это третий,
            -- совсем другой ответ.
            if d.reqLevel == 0 then
                why = why .. " Уровень предмету не нужен вовсе — наденете сразу."
            elseif d.reqLevel then
                why = why .. " Предмет требует уровень " .. d.reqLevel
                    .. (d.wearableNow and " — вы его носите уже сейчас."
                        or (", а у вас " .. tostring(snap and snap.level)
                            .. " — наденете позже, но рецепт можно забрать уже сегодня."))
            else
                why = why .. " Уровень предмета я проверить не смог: клиент его ещё"
                    .. " не кешировал."
            end
            if d.statText then
                why = why .. " Что даёт: " .. d.statText .. "."
            end
            if d.slotLabel then why = why .. " Слот «" .. d.slotLabel .. "»." end
            -- С ЧЕМ СРАВНЕНО - СКАЗАНО ПРЯМО. Число справа на карточке - это
            -- прирост против названной вещи, а не оценка самой покупки.
            if d.gain then
                if d.againstName then
                    why = why .. " Это лучше, чем " .. d.againstName .. ", на "
                        .. U.benefit(d.gain) .. "."
                else
                    why = why .. " Слот сейчас пуст — прирост " .. U.benefit(d.gain) .. "."
                end
            else
                why = why .. " Сравнить с тем, что на вас надето, я не смог —"
                    .. " прирост не называю."
            end

            local matNames = {}
            for _, r in ipairs(d.reagents) do
                local inf = Api:ItemInfo(r.itemID)
                matNames[#matNames + 1] = ((inf and inf.name) or U.itemFallbackName(r.itemID))
                    .. " x" .. r.qty
            end

            self:Add({
                key = "favor:buy:" .. tostring(d.patternItemID or d.outItemID or d.en),
                kind = ns.KIND.FAVOR,
                icon = ns.KIND_ICON.FAVOR,
                title = "За Благосклонность: " .. d.name,
                benefit = tostring(d.favor) .. " Favor"
                    .. (d.gain and (", " .. U.benefitDelta(d.gain)) or ""),
                benefitKind = "power",
                benefitValue = d.gain,
                why = why,
                need = (#matNames > 0)
                    and ("Сделать потом из: " .. table.concat(matNames, ", ") .. ".")
                    or "Реагенты рецепта мне неизвестны.",
                action = { kind = "showItem", label = "Показать предмет",
                           itemID = d.outItemID },
                itemID = d.outItemID,
                conf = plan.conf,
                axes = axes,
                favorBuy = d,
            })
        end
    end
    if nameless > 0 and ns.Diag then
        ns.Diag:Count("favor.namelessSkipped", nameless)
    end
    return added
end

-- Branch: the camp ------------------------------------------------------
--
-- ЛАГЕРЬ. Предмет лагеря даёт КАЖДАЯ профессия, включая добычные, - поэтому
-- отвечать здесь надо по обоим персонажам аккаунта, а не по тому, кем играют
-- сейчас. Разбор и все числа - в Logic/CampAdvisor.lua, данные с провенансом -
-- в Data/Camp.lua.
--
-- ЧЕТЫРЕ КАРТОЧКИ МАКСИМУМ, И КАЖДАЯ ОТВЕЧАЕТ НА СВОЙ ВОПРОС:
--   1. что сделать самому и это лучшее, что у него есть по данным;
--   2. костёр - у него отдельное место, потому что без костра остальное не
--      поставить, а стоит он одно «простое дерево»;
--   3. чертёж - он предмет и он торгуется, значит это совет на ПОКУПКУ, а не
--      «подрасти навыком»;
--   4. что здесь не сделать, а другой персонаж сделает и пришлёт.
--
-- Сводки здесь нет нарочно: «7 из 12 предметов закрыто» - это одна фраза в
-- строке «почему» первой карточки, а не отдельный совет, который нечего делать.
--
-- Реагенты лагеря в список закупок НЕ едут, и это не тихая пропажа: список
-- кормится планами крафта (card.plan), а рецептов лагеря в книге игрока нет -
-- они не рецепты, а предметы. Чего не хватает и сколько это стоит, карточка
-- говорит сама.

function Engine:AddCampCards(snap, scales)
    if not ns.CampAdvisor then return 0 end
    local Camp = ns.CampAdvisor
    local plan, why = Camp:Plan(snap)
    if not plan then
        self.branchNote.camp = (why == "no-data")
            and "данных про лагерь у меня нет"
            or "про лагерь сказать нечего"
        return 0
    end

    local added = 0
    local coverText = Camp:CoverText(plan)
    -- Полное объяснение ограничения - под курсор, вместе с тем, каких профессий
    -- на аккаунте нет вовсе. На карточке стоит короткая форма: строка одна, и
    -- длинное объяснение вытеснило бы с неё сам совет.
    local tipNote = Camp:LimitText()
    if #plan.uncovered > 0 then
        -- ВТОРОГО «НЕТ» В ЭТОЙ СТРОКЕ БЫТЬ НЕ ДОЛЖНО. Первая фраза уже говорит,
        -- чего нет у игры; «чего нет ни у кого на аккаунте» рядом - это второе
        -- отрицание в одной строке, и правило осмысленности ловит его как
        -- повтор (Tests/sense.lua, deniesTwice). Смысл тот же, слова другие.
        tipNote = tipNote .. " Профессии, которых на аккаунте никто не взял: "
            .. table.concat(plan.uncovered, ", ") .. " — их предметы лагеря"
            .. " останутся закрытыми, пока профессию кто-нибудь не выучит."
    end
    local sourceNote = Camp:SourceText(plan)

    -- Цена материалов словами. Ноль - это НЕ «0м»: «Материалы: 0м» читается как
    -- «стоят ноль», а правда здесь - «всё уже есть» (то же правило, что в
    -- подсказке карточки плана, UI/Card.lua).
    local function costText(d)
        if d.haveAll then return "Материалы: всё есть в сумках." end
        local list = {}
        for _, line in ipairs(d.missing) do
            list[#list + 1] = { name = line.name, qty = line.short }
        end
        local names = U.enumerate(list, 3)
        if d.costKnown then
            return "Материалы: " .. U.money(d.cost) .. " — " .. names .. "."
        end
        return "Материалы: " .. names .. ", цену части я не знаю."
    end

    -- Готовый предмет на аукционе. Объекты лагеря торгуются, и иногда готовый
    -- дешевле, чем собрать: это ответ на тот же вопрос, и прятать его нельзя.
    local function readyText(d)
        if not d.buyCopper then return nil end
        if d.costKnown and not d.haveAll and d.buyCopper < d.cost then
            return "Готовый на аукционе дешевле — " .. U.money(d.buyCopper)
                .. " против " .. U.money(d.cost) .. "."
        end
        return "Готовый на аукционе — " .. U.money(d.buyCopper) .. "."
    end

    local function thresholdText(d)
        local text = "Порог — навык " .. tostring(d.need)
        if d.profLabel then text = text .. " по «" .. d.profLabel .. "»" end
        text = text .. ", у вас " .. tostring(d.skill) .. ": хватает."
        if d.disputed then
            text = text .. " Порог спорный: " .. d.low .. " по одной базе и "
                .. d.high .. " по другой — беру бо́льшее."
        end
        return text
    end

    -- Что объект даёт - в столбец выгоды; если данные числа не дают, так и
    -- сказано, а не подставлен ноль.
    local function benefitOf(d)
        return d.gainText or "бонус у костра"
    end

    -- НАСКОЛЬКО КОСТЁР ВМЕСТИТЕЛЬНЕЕ ТОГО, ЧТО УЖЕ МОЖНО ПОСТАВИТЬ. Костёр с
    -- чертежа - не «ещё один предмет», а замена: сравнение «5 мест вместо 3»
    -- и есть весь смысл покупки, и оба числа взяты из данных.
    local function fireGainText(d)
        local gain = d.row.gain
        if not (type(gain) == "table" and gain.kind == "FIRE") then return nil end
        local now = plan.fireNow
        if not (now and now.item ~= d.item) then return nil end
        local have = tonumber(now.row.gain.slots)
        local want = tonumber(gain.slots)
        if not (have and want and want > have) then return nil end
        return "Мест у костра станет " .. want .. " вместо " .. have .. "."
    end

    -- БАФФ ЛАГЕРЯ УЖЕ НА ИГРОКЕ - ЗНАЧИТ, ОБЪЕКТ РАБОТАЕТ, И СТАВИТЬ ЕГО НЕЗАЧЕМ.
    -- Слова игрока: «он должен учитывать то, что у меня поставлено от костра, и
    -- баффы, которые на мне». Спросить у игры, что стоит, нечем; баффы - можно.
    local activeEffects = Camp.ActiveEffects and Camp:ActiveEffects(snap) or {}
    local activeNames = {}
    local hereList = {}
    for _, d in ipairs(plan.here) do
        if activeEffects[d.item] then
            activeNames[#activeNames + 1] = d.name
        else
            hereList[#hereList + 1] = d
        end
    end
    local activeText = nil
    if #activeNames > 0 then
        activeText = "Уже действует на вас: " .. table.concat(activeNames, ", ")
            .. " — этот бафф лагеря я вижу, заново ставить не советую."
        if ns.Diag then ns.Diag:Count("camp.effectAlreadyActive", #activeNames) end
    end

    local first = true
    -- «7 из 12» - один раз, на первой карточке ветки: второй раз та же фраза не
    -- сообщает ничего.
    local function withCover(text)
        if first then
            first = false
            if activeText then text = Engine.JoinSentences(text, activeText) end
            if coverText then text = Engine.JoinSentences(text, coverText) end
        end
        return text
    end

    local function campCard(d, key, title, body, need, action, cost, ready)
        added = added + 1
        local axes = blankAxes()
        axes.power = d.power
        axes.ready = ready or (d.haveAll and 1.0 or 0.4)
        if cost and cost > 0 then axes.spend = U.soft(cost, scales.spend) end
        self:Add({
            key = key,
            kind = ns.KIND.CAMP,
            icon = ns.KIND_ICON.CAMP,
            title = title,
            benefit = benefitOf(d),
            benefitKind = "power",
            why = withCover(body),
            need = need,
            action = action,
            itemID = d.item,
            recipeID = (action and action.kind == "findRecipe") and d.recipeID or nil,
            cost = cost,
            conf = d.conf,
            axes = axes,
            tipNote = tipNote,
            sourceNote = sourceNote,
            camp = d,
        })
    end

    -- КНОПКИ ЗДЕСЬ НЕТ, И ЭТО НЕ НЕДОДЕЛКА. Рецепт лагеря лежит в окне
    -- профессии, а открыть окно профессии аддону игра запрещает (из-за такого
    -- вызова игрок уже один раз не смог играть). Поэтому у совета «сделать»
    -- действие то же, что у остального крафта: сказать, какую профессию
    -- открыть и что в ней найти (Card.ActionNoteShort -> RecipeBook:FindText).
    local function makeAction(d)
        if d.recipeID then
            return { kind = "findRecipe", recipeID = d.recipeID }
        end
        return { kind = "showItem", label = "Показать предмет", itemID = d.item }
    end

    local shown = {}

    -- ГОТОВЫЙ ПРЕДМЕТ УЖЕ В СУМКАХ - ЗНАЧИТ «ПОСТАВЬ», А НЕ «СДЕЛАЙ».
    --
    -- Живая жалоба (маг 31 ур., 2026-11-21): первой карточкой списка стояло
    -- «Сделать для лагеря: Аквариум» с ценой материалов - при 32 аквариумах в
    -- сумках. Рядом «Сделать костёр для лагеря» при шести наборах для костра.
    -- Ветка смотрела в сумки за РЕАГЕНТАМИ и не смотрела за самим предметом.
    -- Что уже стоит у костра, игра по-прежнему не говорит - но что лежит в
    -- сумках, видно точно, и делать второй раз то, что лежит, незачем.
    -- Возвращает true, если карточка «поставить» сделана.
    local function placeInstead(d, isFire)
        local have = (snap and snap.bags and tonumber(snap.bags[d.item])) or 0
        if have <= 0 then return false end
        campCard(d, "camp:place:" .. d.item,
            (isFire and "Разжечь костёр: " or "Поставить у костра: ") .. d.name,
            "В сумках уже лежит " .. have .. " "
                .. U.plural(have, "штука", "штуки", "штук")
                .. " — делать и покупать не нужно."
                .. (isFire and " Без костра предметы лагеря не ставятся." or ""),
            (isFire and "Поставить и разжечь — делаете вы. "
                or "Поставить у костра — ставите вы. ") .. Camp:LimitShort(),
            { kind = "showItem", label = "Показать предмет", itemID = d.item },
            nil, 1.0)
        return true
    end

    -- 1. Лучшее, что он может сделать сам прямо сейчас.
    local best = hereList[1]
    if best and placeInstead(best, false) then
        shown[best.item] = true
    elseif best then
        shown[best.item] = true
        campCard(best, "camp:make:" .. best.item,
            "Сделать для лагеря: " .. best.name,
            Engine.JoinSentences(
                Engine.JoinSentences(
                    Engine.JoinSentences(thresholdText(best), "Рецепт у вас выучен."),
                    costText(best)),
                readyText(best)),
            "Поставить у костра — ставите вы. " .. Camp:LimitShort(),
            makeAction(best),
            (not best.haveAll) and best.costKnown and best.cost or nil)
    end

    -- 2. КОСТЁР - ОТДЕЛЬНОЕ МЕСТО, И ВОТ ПОЧЕМУ. Без костра ни один предмет
    --    лагеря не ставится, то есть совет «сделай аквариум» без костра
    --    невыполним. Стоит костёр одно «простое дерево», а стоит ли он уже у
    --    игрока - узнать нечем (функций про лагерь в клиенте нет). Поэтому он
    --    не вытесняет лучший совет, но и не уходит из списка за то, что его
    --    бонус скромнее.
    local fire = plan.fireNow
    if fire and added < 4 and not shown[fire.item] and placeInstead(fire, true) then
        shown[fire.item] = true
    elseif fire and added < 4 and not shown[fire.item] then
        shown[fire.item] = true
        campCard(fire, "camp:fire:" .. fire.item,
            "Сделать костёр для лагеря: " .. fire.name,
            Engine.JoinSentences(
                Engine.JoinSentences(
                    Engine.JoinSentences(thresholdText(fire), "Рецепт у вас выучен."),
                    costText(fire)),
                "Без костра предметы лагеря не ставятся."),
            "Поставить и разжечь — делаете вы. " .. Camp:LimitShort(),
            makeAction(fire),
            (not fire.haveAll) and fire.costKnown and fire.cost or nil)
    end

    -- 3. ЧЕРТЁЖ - ЭТО ПОКУПКА. Второй тир закрыт не навыком, а рецептом; рецепт
    --    даёт чертёж, чертёж - предмет, и он торгуется. Значит ответ на вопрос
    --    «что делать» - идти на аукцион, а не качать навык. Что рецепт не
    --    выучен, здесь не предположение: это ответ книги рецептов.
    local bp = plan.gated[1]
    if bp and added < 4 and bp.bpName then
        local cost = bp.bpCopper
        if cost and bp.costKnown and not bp.haveAll then cost = cost + bp.cost end
        local text = thresholdText(bp)
        text = Engine.JoinSentences(text, "Рецепт не выучен, его даёт чертёж.")
        if bp.bpCopper then
            text = Engine.JoinSentences(text,
                "Чертёж на аукционе — " .. U.money(bp.bpCopper) .. ".")
        else
            text = Engine.JoinSentences(text, "Цену чертежа я не знаю.")
        end
        text = Engine.JoinSentences(text, fireGainText(bp))
        text = Engine.JoinSentences(text, costText(bp))
        if bp.overName then
            text = Engine.JoinSentences(text,
                "Ставится поверх «" .. bp.overName .. "», и его бонус остаётся.")
        end
        added = added + 1
        local axes = blankAxes()
        axes.power = bp.power
        axes.ready = 0.2
        if cost and cost > 0 then axes.spend = U.soft(cost, scales.spend) end
        self:Add({
            key = "camp:blueprint:" .. tostring(bp.item),
            kind = ns.KIND.CAMP,
            icon = ns.KIND_ICON.CAMP,
            title = "Купить чертёж для лагеря: " .. bp.name,
            benefit = benefitOf(bp),
            benefitKind = "power",
            why = withCover(text),
            need = "Купить чертёж, выучить и сделать — всё это делаете вы. "
                .. Camp:LimitShort(),
            -- КНОПКА КЛАДЁТ ЧЕРТЁЖ В СПИСОК ПОКУПОК, и подпись у неё та же,
            -- что у остальных таких кнопок в аддоне: одно действие - одна
            -- подпись (договор держит Tests/test_sense.lua). Покупает игрок:
            -- аддон ничего не покупает и на аукцион не ходит.
            action = { kind = "shop", label = "В список покупок",
                       itemID = bp.bpItem, qty = 1 },
            itemID = bp.bpItem,
            cost = cost,
            conf = bp.conf,
            axes = axes,
            tipNote = tipNote,
            sourceNote = sourceNote,
            camp = bp,
        })
    end

    -- 4. ЧТО СДЕЛАЕТ ДРУГОЙ ПЕРСОНАЖ. У игрока две профессии лагеря лежат на
    --    втором персонаже, и сам он об этом не думает: в сумки и в окно
    --    профессий он смотрит на том, кем играет.
    local other = plan.elsewhere[1]
    if other and added < 4 then
        local who = Camp:HolderLabel(other.holder)
        local text = "Порог — навык " .. tostring(other.need)
        if other.profLabel then
            text = text .. " по «" .. other.profLabel .. "»"
        end
        if other.skill then
            text = text .. ", у вас " .. other.skill .. ", а у " .. who .. " хватает."
        else
            text = text .. "; у этого персонажа такой профессии нет, а у "
                .. who .. " она есть."
        end
        -- ЧЕГО ПРО НЕГО НЕ ВИДНО - СКАЗАНО. Книга рецептов есть только у того
        -- персонажа, кем играют: выучен ли у второго этот рецепт, мне не видно,
        -- и делать вид, что видно, нельзя.
        text = Engine.JoinSentences(text,
            "Выучен ли у него этот рецепт, мне не видно: книга рецептов другого"
            .. " персонажа мне не отдаётся.")
        text = Engine.JoinSentences(text, readyText(other))
        added = added + 1
        local axes = blankAxes()
        axes.power = other.power
        axes.ready = 0.15
        self:Add({
            key = "camp:other:" .. tostring(other.item),
            kind = ns.KIND.CAMP,
            icon = ns.KIND_ICON.CAMP,
            -- Заголовок короткий НАРОЧНО: в нём полное имя персонажа, а у
            -- игрока два «Гендольфа», и без фамилии совет бессмыслен. Поэтому
            -- слова «для лагеря» сжаты до «Лагерь:» - место в строке уходит на
            -- то, что игроку нужно различать.
            title = "Лагерь: " .. other.name .. " сделает "
                .. tostring(other.holder.fullName),
            benefit = benefitOf(other),
            benefitKind = "power",
            why = withCover(text),
            need = "Сделать тем персонажем и переслать почтой. Я почтой не"
                .. " управляю и персонажей не переключаю.",
            action = { kind = "showItem", label = "Показать предмет",
                       itemID = other.item },
            itemID = other.item,
            conf = other.conf,
            axes = axes,
            tipNote = tipNote,
            sourceNote = sourceNote,
            camp = other,
        })
    end

    -- 5. РЕЦЕПТ У ТРЕНЕРА. Первый тир рецепта с чертежа не имеет: его даёт
    --    тренер профессии. Это тоже «что сделать сейчас», и стоит это копейки.
    local learn = plan.teach[1]
    if learn and added < 4 then
        local text = thresholdText(learn)
        text = Engine.JoinSentences(text,
            "Рецепт не выучен — его даёт тренер этой профессии"
            .. ((tonumber(learn.row.learnCost) or 0) > 0
                and (" за " .. U.money(learn.row.learnCost)) or "") .. ".")
        text = Engine.JoinSentences(text, costText(learn))
        text = Engine.JoinSentences(text, readyText(learn))
        campCard(learn, "camp:teach:" .. learn.item,
            "Выучить для лагеря: " .. learn.name,
            text,
            "Сходить к тренеру и выучить — иду не я, идёте вы. "
                .. Camp:LimitShort(),
            { kind = "showItem", label = "Показать предмет", itemID = learn.item },
            nil, 0.3)
    end

    -- 6. Второй по пользе свой предмет - если после всего осталось место.
    for _, d in ipairs(hereList) do
        if added >= 4 then break end
        if not shown[d.item] and placeInstead(d, false) then
            shown[d.item] = true
        elseif not shown[d.item] then
            shown[d.item] = true
            campCard(d, "camp:make:" .. d.item,
                "Сделать для лагеря: " .. d.name,
                Engine.JoinSentences(
                    Engine.JoinSentences(
                        Engine.JoinSentences(thresholdText(d), "Рецепт у вас выучен."),
                        costText(d)),
                    readyText(d)),
                "Поставить у костра — ставите вы. " .. Camp:LimitShort(),
                makeAction(d),
                (not d.haveAll) and d.costKnown and d.cost or nil)
        end
    end

    if added == 0 then
        -- ПРИЧИНА РАЗНАЯ, И ЭТО РАЗНЫЕ ОТВЕТЫ.
        if activeText then
            self.branchNote.camp = "всё, что вы можете поставить сами, уже"
                .. " действует на вас: " .. table.concat(activeNames, ", ")
        elseif plan.unread > 0 then
            self.branchNote.camp = "выучены ли рецепты лагеря, я не знаю: окно"
                .. " этих профессий в этой сессии не открывали, и список"
                .. " рецептов игра мне не отдала"
        elseif plan.nameless > 0 and #plan.here == 0 and #plan.gated == 0
            and #plan.elsewhere == 0 then
            self.branchNote.camp = "имён предметов лагеря мне пока никто не"
                .. " назвал (" .. plan.nameless .. " "
                .. U.plural(plan.nameless, "предмет", "предмета", "предметов")
                .. "): ни клиент, ни внешняя база. Советовать то, что игрок не"
                .. " сможет прочитать, я не буду"
        elseif plan.covered == 0 then
            self.branchNote.camp = "ни один предмет лагеря не закрывается"
                .. " профессиями этого аккаунта"
        else
            self.branchNote.camp = "профессии лагерь закрывают, но ни одного"
                .. " предмета сейчас не сделать: навыка не хватает или рецепта"
                .. " нет"
        end
    end
    if plan.nameless > 0 and ns.Diag then
        ns.Diag:Count("camp.namelessSkipped", plan.nameless)
    end
    return added
end

-- Branch: upgrade paths -------------------------------------------------
--
-- РАЗВИЛКА ВМЕСТО ОДНОГО ВАРИАНТА. Раньше на слот выдавался один совет -
-- «скрафтить вот это», - и выбор за игрока делал аддон. Теперь на тот слот, где
-- путей действительно несколько, появляется карточка с вариантами рядом: цена,
-- прирост, срок. Что важнее - золото или время - решает игрок.
--
-- Одна карточка на слот, и только там, где путей БОЛЬШЕ ОДНОГО: развилка из
-- одного варианта - это не развилка, а шум.

function Engine:AddPathCards(snap, scales)
    if not ns.UpgradePaths then return 0 end
    local Gear = ns.GearAdvisor
    local added, examined = 0, 0

    -- Кандидаты уже посчитаны веткой экипировки на этом же проходе.
    local wearable = Gear:Candidates(snap)
    local bySlot = {}
    for _, cand in ipairs(wearable or {}) do
        for _, target in ipairs(ns.SlotMap:TargetSlots(cand.slot)) do
            bySlot[target] = bySlot[target] or {}
            bySlot[target][#bySlot[target] + 1] = cand
        end
    end

    for _, slotKey in ipairs(U.sortedKeys(bySlot)) do
        if added >= 2 then break end
        examined = examined + 1
        local fork = ns.UpgradePaths:ForSlot(slotKey, snap, bySlot[slotKey])
        if fork then
            -- Берём лучший по приросту вариант и смотрим, правда ли у него
            -- несколько путей.
            local opt = fork.options[1]
            -- ТОТ ЖЕ ПОРОГ, ЧТО У КРАФТА И У «НАДЕТЬ СВОЁ».
            --
            -- Здесь стояло `opt.gain > 0`, и на настоящих данных игрока это
            -- давало третью карточку про те же «Теневые очки»: «Как получить:
            -- Теневые очки, +0 ед. пользы, 2 пути». Развилка из двух путей к
            -- вещи, которая не лучше надетой, - это не выбор, а предложение
            -- потратить материалы двумя способами.
            if opt and #opt.paths > 1 and U.isGain(opt.gain) then
                added = added + 1
                local lines = {}
                for _, p in ipairs(opt.paths) do
                    lines[#lines + 1] = "• " .. ns.UpgradePaths:PathLine(p)
                end
                local choice = ns.UpgradePaths:ChoiceText(opt)

                local axes = blankAxes()
                axes.power = U.soft(opt.gain, scales.power)
                local cheapest = opt.cheapest
                axes.spend = (cheapest and cheapest.cost)
                    and U.soft(cheapest.cost, scales.spend) or 0
                axes.ready = (opt.fastest and opt.fastest.when == ns.UpgradePaths.WHEN.NOW)
                    and 0.9 or 0.4

                self:Add({
                    key = "paths:" .. slotKey .. ":" .. opt.itemID,
                    kind = ns.KIND.PATHS,
                    icon = ns.KIND_ICON.PATHS,
                    title = "Как получить: " .. opt.name,
                    benefit = U.benefitDelta(opt.gain)
                        .. ", " .. #opt.paths .. " "
                        .. U.plural(#opt.paths, "путь", "пути", "путей"),
                    benefitKind = "power",
                    benefitValue = opt.gain,
                    why = "Слот «" .. tostring(fork.slotLabel) .. "»: прирост "
                        .. U.benefit(opt.gain)
                        .. " против того, что у вас на этот слот есть."
                        .. " Путей сюда несколько:\n" .. table.concat(lines, "\n")
                        .. (choice and ("\n" .. choice) or ""),
                    -- Когда один путь и дешевле, и быстрее, выбора нет - и
                    -- приписка «Выбирать вам» спорила с текстом строкой выше.
                    need = (opt.cheapest and opt.fastest
                            and opt.cheapest.kind == opt.fastest.kind)
                        and "Делаете вы сами — я ничего не делаю за вас."
                        or "Выбирать вам — я не выбираю за вас и ничего не делаю сам.",
                    action = { kind = "showItem", label = "Показать предмет",
                               itemID = opt.itemID },
                    itemID = opt.itemID,
                    cost = cheapest and cheapest.cost or nil,
                    conf = fork.conf,
                    axes = axes,
                    paths = fork,
                })
            end
        end
    end

    if added == 0 then
        self.branchNote.paths = (examined == 0)
            and "сравнивать нечего: кандидатов на слоты нет"
            or "ни на одном слоте нет нескольких путей к одной вещи —"
               .. " развилку показывать не из чего"
    end
    return added
end

-- Branch: the other character -------------------------------------------
--
-- Материал лежит на чернокнижнике, профессия у мага. Игрок об этом не знает:
-- он смотрит в сумки мага и идёт покупать то, что уже купил вчера другим
-- персонажем.

function Engine:AddCrossCharCards(snap, scales)
    if not ns.CrossCharacter then return 0 end
    local added = 0

    -- 1. Материалы, которых здесь не хватает, а у другого персонажа есть.
    --
    -- СПРАШИВАЕМ У ПЛАНОВ, А НЕ У СПИСКА ПОКУПОК, и это принципиально. Список
    -- покупок уже вычитает запасы альтов (ShoppingList:SetInventory складывает
    -- snap.owned[...].alts) - то есть он МОЛЧА не просит купить то, что лежит на
    -- чернокнижнике. Для суммы это правильно, а для игрока это ровно то самое
    -- тихое поведение: цифра тихо уменьшилась, и почему - не сказано. Поэтому
    -- потребность берём из самих планов, сравниваем с сумками ЭТОГО персонажа,
    -- и разницу проговариваем словами.
    local needed = {}
    for _, card in ipairs(self.cards) do
        local gross = card.plan and card.plan.needGross
        for itemID, qty in pairs(gross or {}) do
            local decision = card.plan.decisions and card.plan.decisions[itemID]
            if not (decision and decision.method == "craft") then
                needed[itemID] = math.max(needed[itemID] or 0, tonumber(qty) or 0)
            end
        end
    end
    local elsewhere, why = ns.CrossCharacter:MaterialsElsewhere(needed, snap)
    if elsewhere and #elsewhere > 0 then
        added = added + 1
        local bits, whoSet = {}, {}
        for i = 1, math.min(3, #elsewhere) do
            local e = elsewhere[i]
            local who = {}
            for _, w in ipairs(e.elsewhere) do
                -- ПОДПИСЬ, А НЕ ОДНО ИМЯ: у игрока два персонажа по имени
                -- «Гендольф», и «у Гендольф (9)» не отвечало ни на вопрос «у
                -- которого», ни на вопрос «что такое 9» (это был номер класса).
                who[#who + 1] = (w.label or w.name) .. " — " .. w.qty .. " шт."
                whoSet[w.label or w.name] = true
            end
            bits[#bits + 1] = e.name .. ": нужно " .. e.need
                .. ", здесь " .. e.hereHave .. ", у " .. table.concat(who, ", ")
        end
        local names = {}
        for name in pairs(whoSet) do names[#names + 1] = name end
        table.sort(names)

        -- Пересылка почтой - необратима так же, как продажа: ткань и руда
        -- облика не имеют, а зелёная вещь имеет. Называется самая опасная из
        -- перечисленных позиций - строка у карточки одна.
        local mailLooks = {}
        for _, e in ipairs(elsewhere) do mailLooks[#mailLooks + 1] = e.looks end

        self:Add(Engine.ApplyLooks({
            key = "cross:materials",
            kind = ns.KIND.CROSS_CHAR,
            icon = ns.KIND_ICON.CROSS_CHAR,
            title = "Материал есть у " .. table.concat(names, ", "),
            benefit = "не покупать " .. #elsewhere .. " "
                .. U.plural(#elsewhere, "позицию", "позиции", "позиций"),
            benefitKind = "info",
            -- Точка - через U.endSentence: строка кончается количеством, то
            -- есть сокращением «шт.» со своей точкой, и приписанная сверху
            -- давала «46 шт..».
            why = U.endSentence("Это уже куплено — только другим персонажем: "
                .. table.concat(bits, "; ")),
            need = "Перешлите почтой или положите в общий банк."
                .. " Я почтой и банком не управляю — только показываю, что искать"
                .. " не надо.",
            action = { kind = "noop" },
            conf = CONF.CACHED,
            axes = { power = 0, skill = 0, profit = 0, spend = 0, ready = 0.5 },
            crossMaterials = elsewhere,
        }, ns.Appearance and ns.Appearance:Worst(mailLooks) or nil))
    end

    -- 2. Суммарное золото: «не хватает 5з» при золотом на альте - другой разговор.
    local gold = ns.CrossCharacter:Gold(snap)
    if gold and gold.elsewhere > 0 and #gold.others > 0 then
        local afford = ns.ShoppingList:Affordability(snap)
        -- Говорим только если это что-то меняет: список не по карману здесь,
        -- но по карману вместе.
        if afford.affordable == false and afford.total <= gold.total then
            added = added + 1
            local bits = {}
            for i = 1, math.min(3, #gold.others) do
                bits[#bits + 1] = gold.others[i].name .. " — "
                    .. U.money(gold.others[i].money)
            end
            self:Add({
                key = "cross:gold",
                kind = ns.KIND.CROSS_CHAR,
                icon = ns.KIND_ICON.CROSS_CHAR,
                title = "Денег хватает, но не здесь",
                benefit = U.money(gold.total) .. " на всех",
                benefitKind = "info",
                why = "Список закупки стоит " .. U.money(afford.total)
                    .. ", здесь у вас " .. U.money(gold.here)
                    .. " — не хватает " .. U.money(afford.shortfall or 0)
                    .. ". Но на других персонажах лежит " .. U.money(gold.elsewhere)
                    .. " (" .. table.concat(bits, ", ") .. "), а вместе это "
                    .. U.money(gold.total) .. " — хватает.",
                need = "Деньги надо переслать почтой: в кошельке они не сами"
                    .. " появятся. Я почтой не управляю.",
                action = { kind = "noop" },
                conf = gold.conf,
                axes = { power = 0, skill = 0, profit = 0, spend = 0, ready = 0.3 },
                crossGold = gold,
            })
        end
    end

    -- 3. Что скрафтить для другого персонажа.
    local forOthers = ns.CrossCharacter:CraftablesForOthers(snap)
    if forOthers and #forOthers > 0 and added < ns.MAX_CARDS_PER_KIND then
        added = added + 1
        local top = forOthers[1]
        local bits = {}
        for i = 1, math.min(3, #forOthers) do
            bits[#bits + 1] = forOthers[i].name
                .. " (" .. tostring(forOthers[i].slotLabel) .. ")"
        end
        self:Add(Engine.ApplyLooks({
            key = "cross:craftfor:" .. tostring(top.forName),
            kind = ns.KIND.CROSS_CHAR,
            icon = ns.KIND_ICON.CROSS_CHAR,
            title = "Скрафтить для " .. tostring(top.forLabel or top.forName),
            benefit = #forOthers .. " "
                .. U.plural(#forOthers, "вариант", "варианта", "вариантов"),
            benefitKind = "info",
            -- ПОДПИСЬ ПЕРСОНАЖА ЦЕЛИКОМ: имя с фамилией, уровень и класс
            -- словом. Раньше здесь стоял номер класса из Syndicator, и текст
            -- читался как «у «Гендольф Белыйй» (9) профессий нет» - девятка
            -- выглядела уровнем.
            --
            -- И ПРИЧИНА БОЛЬШЕ НЕ ВЫДУМЫВАЕТСЯ. Здесь стояло «профессий нет» -
            -- утверждение, которое аддону было нечем проверить: чужие аддоны
            -- профессий не хранят. Пока их у чернокнижника и правда не было,
            -- фраза случайно совпадала с правдой; теперь у него алхимия,
            -- инженерное дело и кулинария, и фраза стала бы ложью. Слова берутся
            -- из реестра (CC:ProfessionText) - он отвечает три разных ответа:
            -- «его профессии: …», «профессий у него нет» и «не знаю, этим
            -- персонажем при мне не играли».
            why = "У «" .. tostring(top.forLabel or top.forName)
                .. "» слоты есть, а этого рецепта нет — "
                .. tostring(top.forProfessionText or "про его профессии мне нечего сказать")
                .. ". Из того, что вы умеете, ему подходит по классу: "
                .. table.concat(bits, ", ")
                .. ((#forOthers > 3) and (" и ещё " .. (#forOthers - 3)) or "") .. "."
                -- ПРИРОСТ НЕ СЧИТАЕМ, и это честно сказано: Syndicator отдаёт
                -- сумки альта, а не его характеристики.
                .. " Насколько это лучше того, что на нём надето, я не знаю:"
                .. " характеристики другого персонажа мне не видны, видны только"
                .. " его сумки.",
            need = "Сделать и переслать почтой. Я ничего не делаю и не пересылаю.",
            action = { kind = "findRecipe", recipeID = top.recipeID },
            recipeID = top.recipeID,
            itemID = top.itemID,
            conf = CONF.ESTIMATE,
            axes = { power = 0, skill = 0, profit = 0, spend = 0, ready = 0.2 },
            crossCraftables = forOthers,
        }, top.looks))
    end

    -- 4. ЧЬЯ ПРОФЕССИЯ ЗАКРЫВАЕТ НУЖДУ, КОТОРУЮ ЗДЕСЬ ЗАКРЫТЬ НЕЧЕМ.
    --
    -- Осмысленным этот вопрос стал ровно сейчас. Пока профессии были у одного
    -- персонажа, спрашивать было нечего: всё, что игрок умеет, он умеет здесь.
    -- Теперь у мага портняжка с чарами, у чернокнижника алхимия с инженерным
    -- делом - и «этот материал умеет сделать другой персонаж» стало таким же
    -- настоящим ответом, как «он лежит у другого в сумках». Разница между ними
    -- для игрока существенная: лежащее надо переслать, а умеемое надо сделать.
    --
    -- Берётся из своего реестра, то есть из того, что аддон видел сам.
    -- Профессии персонажа лежат в его собственной сохранёнке, которую игра для
    -- других персонажей не загружает, а чужие аддоны профессий не хранят вовсе.
    if ns.Roster and added < ns.MAX_CARDS_PER_KIND then
        -- Профессии, которых у ЭТОГО персонажа нет, а на аккаунте есть.
        local mine = {}
        for _, prof in ipairs(snap.professions or {}) do
            if prof.name then mine[U.lower(prof.name)] = true end
        end
        -- И английские пары своих имён: чужой кеш пишет «Alchemy» там, где
        -- клиент говорит «Алхимия», и без этого своя же профессия попала бы в
        -- список «есть у другого».
        local bridge = ns.RecipeBook and ns.RecipeBook.NAME_BRIDGE or {}
        for name in pairs(U.copy(mine)) do
            local other = bridge[name]
            if other then mine[other] = true end
        end
        local elsewhereProfs = {}
        for profName, holders in pairs(ns.Roster:ProfessionIndex()) do
            if not mine[U.lower(profName)] then
                local best
                for _, h in ipairs(holders) do
                    if h.fullName ~= (snap.fullName or snap.name) then
                        if (not best) or (tonumber(h.skill) or -1) > (tonumber(best.skill) or -1) then
                            best = h
                        end
                    end
                end
                if best then
                    elsewhereProfs[#elsewhereProfs + 1] = {
                        profession = profName, holder = best,
                    }
                end
            end
        end
        table.sort(elsewhereProfs, function(a, b)
            local sa, sb = tonumber(a.holder.skill) or -1, tonumber(b.holder.skill) or -1
            if sa ~= sb then return sa > sb end
            return a.profession < b.profession
        end)

        if #elsewhereProfs > 0 then
            added = added + 1
            local bits, anyForeign = {}, false
            for i = 1, math.min(4, #elsewhereProfs) do
                local e = elsewhereProfs[i]
                -- Имя по-русски: из чужого кеша оно приходит английским, а
                -- клиент у игрока ruRU. Перевод - через Roster:DisplayName, то
                -- есть через единственный словарь NAME_BRIDGE.
                local line = ns.Roster:DisplayName(e.profession)
                if e.holder.skill then line = line .. " " .. e.holder.skill end
                -- Подпись персонажа: полное имя, уровень и класс. У игрока два
                -- «Гендольфа», и одного имени здесь не хватает.
                local who = tostring(e.holder.fullName)
                local tail = {}
                if e.holder.level then tail[#tail + 1] = e.holder.level .. " ур." end
                if e.holder.className then tail[#tail + 1] = e.holder.className end
                if #tail > 0 then who = who .. ", " .. table.concat(tail, ", ") end
                if e.holder.source == "foreign" then anyForeign = true end
                bits[#bits + 1] = line .. " — " .. who
            end
            self:Add({
                key = "cross:professions",
                kind = ns.KIND.CROSS_CHAR,
                icon = ns.KIND_ICON.CROSS_CHAR,
                title = "Эти профессии есть у другого персонажа",
                benefit = #elsewhereProfs .. " "
                    .. U.plural(#elsewhereProfs, "профессия", "профессии", "профессий"),
                benefitKind = "info",
                -- Точка - через U.endSentence: подпись персонажа кончается
                -- «13 ур.», когда класс неизвестен, и приписанная сверху точка
                -- дала бы «13 ур..».
                why = U.endSentence("Здесь этого не сделать, а на аккаунте есть: "
                    .. table.concat(bits, "; ")
                    .. ((#elsewhereProfs > 4)
                        and (" и ещё " .. (#elsewhereProfs - 4)) or ""))
                    -- ОТКУДА ЭТО ИЗВЕСТНО - СКАЗАНО. Своё и чужое здесь могут
                    -- стоять рядом, и это не одно и то же: своё аддон видел
                    -- сам, чужое прочитал в кеше Mastercraft, где имена
                    -- английские и возраст записи неизвестен.
                    .. (anyForeign
                        and (" Часть этого — из " .. ns.FOREIGN_BOOK.label
                             .. " (кеш Mastercraft): имена там английские, а"
                             .. " когда их записали, мне не сказали. Как только"
                             .. " вы сыграете этим персонажем, я буду знать"
                             .. " сам.")
                        or " Это то, что я видел сам, когда этими персонажами"
                           .. " играли."),
                need = "Переключиться на того персонажа и сделать там. Я ничего"
                    .. " не делаю и персонажей не переключаю.",
                action = { kind = "noop" },
                conf = CONF.CACHED,
                axes = { power = 0, skill = 0, profit = 0, spend = 0, ready = 0.1 },
                crossProfessions = elsewhereProfs,
            })
        end
    end

    if added == 0 then
        self.branchNote.cross = (why == "no-syndicator")
            and "про других персонажей я ничего не знаю: Syndicator не загружен"
            or "у других персонажей нет ничего, что меняло бы советы здесь"
    end
    return added
end

-- Branch: sell junk ----------------------------------------------------

function Engine:AddJunkCards(snap, scales)
    local junk = ns.CharacterScanner:Junk()
    if #junk == 0 then
        self.branchNote.junk = "серого хлама в сумках нет"
        return 0
    end

    -- ОДИН ПРЕДМЕТ - ОДНА ПОЗИЦИЯ, А НЕ ОДНА ЯЧЕЙКА СУМКИ.
    --
    -- Хлам считается по ячейкам, и один и тот же предмет в двух ячейках давал
    -- и два слагаемых в счёте позиций, и два подряд одинаковых имени в
    -- перечислении: «Отрубленный коготь, Отрубленный коготь и ещё 8». Для
    -- игрока это один предмет, одно имя и одно количество.
    local total, seen, kinds = 0, {}, 0
    for _, j in ipairs(junk) do
        total = total + j.total
        -- По имени, а не по номеру: именно имя игрок видит в перечислении, и
        -- счёт позиций обязан совпадать с тем, что в нём перечислено.
        local key = j.name or j.itemID
        if not seen[key] then
            seen[key] = true
            kinds = kinds + 1
        end
    end
    if total <= 0 then
        self.branchNote.junk = "хлам есть, но торговец за него ничего не даёт"
        return 0
    end

    local axes = blankAxes()
    axes.profit = U.soft(total, scales.profit)
    axes.ready = 1.0

    -- ОБЛИК У ХЛАМА: ОТВЕТ ЗДЕСЬ ПОЧТИ ВСЕГДА ПУСТОЙ, И ВОПРОС ВСЁ РАВНО
    -- ЗАДАЁТСЯ.
    --
    -- Хлам - это серое качество (Scanner:Junk), а серое и белое учится по
    -- подбору: продажа такого облика не теряет, и говорить тут не о чем. Но
    -- условие «серое» живёт не здесь, а в сканере, и держится на одном поле
    -- ответа клиента. Поменяйся он - и карточка «продать хлам» стала бы той
    -- самой необратимой ошибкой, причём молча. Поэтому спрашивается каждая
    -- позиция, а не делается вывод из того, что их отобрал сканер.
    local looksList = {}
    for _, j in ipairs(junk) do
        looksList[#looksList + 1] = ns.Appearance and ns.Appearance:Check({
            itemID = j.itemID, link = j.link, name = j.name,
            quality = j.quality, bound = j.bound,
        }, "vendor", "junk") or nil
    end
    local junkLooks = ns.Appearance and ns.Appearance:Worst(looksList) or nil

    self:Add(Engine.ApplyLooks({
        key = "junk:all",
        kind = ns.KIND.SELL_JUNK,
        icon = ns.KIND_ICON.SELL_JUNK,
        title = "Продать хлам: " .. kinds .. " " .. U.plural(kinds, "позиция", "позиции", "позиций"),
        benefit = U.moneyDelta(total),
        benefitKind = "gold",
        benefitValue = total,
        why = "Серый хлам в сумках: " .. U.enumerate(junk, 3)
            .. ". Цены торговца — точные, не оценка.",
        need = "Отнесите любому торговцу. Я ничего не продаю сам.",
        action = { kind = "noop" },
        cost = nil,
        conf = CONF.EXACT,
        axes = axes,
        junk = junk,
    }, junkLooks))
    return 1
end

-- Build ----------------------------------------------------------------

-- Ranking --------------------------------------------------------------
--
-- Ranking is tiered, then scored inside the tier. Scores alone are not enough:
-- an informational card and a loss-making one both produce a perfectly
-- respectable number, and both were ending up above real advice.
--   3  pinned setup cards - the list is wrong without them
--   2  actionable advice that does not cost more than it gives
--   1  information: true, useful, but not a thing to go and do; and advice the
--      addon itself would check before acting on
--   0  advice that loses money, or whose own numbers contradict each other,
--      kept for honesty, never on top
--
-- ФУНКЦИЕЙ, А НЕ ЗАМЫКАНИЕМ ВНУТРИ СБОРКИ: ранжирование нужно дважды. Второй
-- раз - после самопроверок, когда найденное сомнение меняет ступень карточки
-- (Engine:Sweep ниже).
function Engine.TierOf(card)
    if type(card) ~= "table" then return 0 end
    if card.pinTop then return 3 end
    -- КАРТОЧКА, ЧЬИ ЧИСЛА НЕ СХОДЯТСЯ, НИКОГДА НЕ НАВЕРХУ. Жезл с выручкой
    -- 2з 66с против цены торговца 5м стоял восьмым - выше половины списка -
    -- и выглядел как обычный совет. Вниз, к убыточным, и с предупреждением.
    if card.suspect then return 0 end
    if ns.Risk and card.doubtLevel == ns.Risk.DOUBT_DISTRUST then return 0 end
    -- СВОЙ СПИСОК ИГРОКА - НЕ СОВЕТ И НЕ УБЫТОК. Карточка закрепления стоит в
    -- списке потому, что её попросил игрок, а не потому, что аддон что-то
    -- советует; её «отрицательная выгода» - это просто цена, которую он сам
    -- назначил. Поэтому ступень сведений: за место с советами не спорит и в один
    -- ряд с убыточными советами не встаёт.
    if card.ownList then return 1 end
    if (card.score or 0) < 0 then return 0 end
    -- СОМНЕНИЕ ТОЖЕ МЕНЯЕТ МЕСТО, А НЕ ТОЛЬКО ТЕКСТ.
    --
    -- «На продажу: Небесно-голубая краска» с разрывом в 166 раз между выручкой и
    -- ценой торговца стояла ВТОРЫМ советом сверху - то есть ровно там, где игрок
    -- и действует, - при том что аддон писал про это число странность в свой же
    -- файл на каждом пересчёте. Такая карточка с экрана не уходит (разрыв может
    -- быть и настоящим, решать игроку), но и твёрдым советом больше не выглядит:
    -- она стоит ниже всего, что можно сделать сегодня без оговорок.
    if card.doubtLevel then return 1 end
    -- Out of reach by a wide margin: still shown, still explained, but
    -- never above something the player can actually do today.
    if card.outOfReach then return 1 end
    if card.informational then return 1 end
    return 2
end

function Engine.RankValue(card)
    local score = tonumber(card.score) or 0
    if score ~= score then score = 0 end
    -- Scores live in roughly -2..2, so the tier never gets overrun.
    return Engine.TierOf(card) * 1000 + U.clamp(score, -100, 100)
end

-- САМОПРОВЕРКА И ТО, ЧТО ОНА НАШЛА, - ДО ТОГО, КАК СПИСОК ПОКАЖУТ.
--
-- Проход самопроверок всегда шёл последним и писал только в файл. Из-за этого
-- ни одна находка «про эту карточку» не могла попасть ни в её текст, ни в её
-- место: к моменту прохода список был уже отранжирован, обрезан и записан.
-- Теперь проход идёт здесь, найденное прикладывается к карточкам (Diag
-- маршрутизирует по ключу), печатается одной функцией (Risk:RenderDoubts) и
-- список переставляется заново - состав тот же, порядок другой.
function Engine:Sweep(snap, counts, generated)
    if not (ns.Diag and ns.SanityChecks) then return 0 end
    ns.SanityChecks:Run({
        cards = self.cards,
        snap = snap,
        counts = counts,
        generated = generated,
        hidden = self.meta.hiddenByDismissal or 0,
        enchantBySlot = self.enchantByCardKey,
    })
    local doubted = 0
    if ns.Risk then
        for _, card in ipairs(self.cards) do
            if type(card.doubts) == "table" and #card.doubts > 0 then
                ns.Risk:RenderDoubts(card)
                if card.doubtLevel then doubted = doubted + 1 end
            end
        end
    end
    self.meta.doubtedCards = doubted
    if doubted > 0 then
        self.cards = U.stableSortBy(self.cards, Engine.RankValue, true)
        ns.Diag:Count("cards.doubted", doubted)
    end
    return doubted
end

function Engine:Build()
    self.cards = {}
    self.meta = {}
    self.hidden = {}
    self.branchNote = {}
    -- Считается ЗДЕСЬ, а не в конце: пересчёт, упавший на середине, всё равно
    -- был, и «ещё не считали» про него - неправда. Панель по этому числу
    -- отличает «список пуст» от «пересчёта не было».
    self.buildCount = (self.buildCount or 0) + 1
    -- Deduplication state is per build: carrying it over would make the second
    -- recompute report every card as a duplicate of the first.
    self.seenKeys, self.seenActions = {}, {}
    -- Какие рецепты уже стали советом «скрафтить и надеть». Тоже на один
    -- пересчёт: карточки прошлого прохода больше не существуют, и дописывать в
    -- них второй вариант было бы дописыванием в мусор.
    self.gearByRecipe = {}
    self.dupes, self.dupeKeyHits, self.dupeActionHits = 0, 0, 0
    self.dupeDetail = {}
    local timer = ns.Diag and ns.Diag:TimerStart() or nil

    local snap = ns.CharacterScanner:Get()
    if not snap then
        self.meta.error = "нет снимка персонажа"
        if ns.Diag then
            ns.Diag:Module("actionEngine", { ["in"] = 0, out = 0,
                reason = "CharacterScanner не отдал снимок персонажа" })
            ns.Diag:TimerStop(timer, "build (без снимка)")
        end
        return self.cards, self.meta
    end

    -- A fresh costing pass per build: prices and bags may have moved.
    Api:BeginPass()
    ns.PriceProvider:BeginPass()
    ns.CraftingPlanner:Bind(ns.RecipeBook, ns.PriceProvider):BeginPass()
    ns.GearAdvisor:BeginPass()
    ns.ShoppingList:Reset()

    local scales = self:Scales(snap)
    self.meta.scales = scales

    -- Per-branch timings, so "it feels slow" can be answered with a number for
    -- the branch at fault rather than a guess. Six clock reads per rebuild.
    local spent = {}
    local function timed(name, fn)
        -- Имя ветки едет в провайдер цен, чтобы заказ «нет цены по предмету X»
        -- попадал в файл вместе с тем, КОМУ эта цена понадобилась.
        if ns.PriceProvider.AskingFor then ns.PriceProvider:AskingFor(name) end
        -- `self` first, always. The no-diagnostics path used to call
        -- fn(snap, scales), which lands `snap` in `self` and crashes the branch
        -- on its first field access - a fallback that did not fall back.
        if not ns.Diag then
            local r = fn(self, snap, scales)
            if ns.PriceProvider.AskingFor then ns.PriceProvider:AskingFor(nil) end
            return r
        end
        local t0 = ns.Diag.clock()
        local result = fn(self, snap, scales)
        spent[name] = (ns.Diag.clock() - t0)
        if ns.PriceProvider.AskingFor then ns.PriceProvider:AskingFor(nil) end
        return result
    end

    self:AddSetupCards(snap)

    local counts = {}
    -- Сначала «надень своё»: это бесплатно и выполняется сразу, а ветка
    -- экипировки ниже сравнивает крафт уже с лучшим из имеющегося.
    counts.equip = timed("equip", Engine.AddEquipCards)
    counts.gear = timed("gear", Engine.AddGearCards)
    counts.enchant = timed("enchant", Engine.AddEnchantCards)
    counts.profit = timed("profit", Engine.AddProfitCards)
    counts.skill = timed("skill", Engine.AddSkillCards)

    -- The shopping list is fed by everything above, so the buy cards come last.
    -- The inventory is handed over once: each plan allocated the bags on its
    -- own, so the merged list has to subtract them a single time instead of
    -- once per card.
    ns.ShoppingList:SetInventory(snap)
    -- СПИСОК ПОКУПОК НЕ СОБИРАЕТ МАТЕРИАЛЫ ДЛЯ СОВЕТОВ, КОТОРЫХ НЕ БУДЕТ.
    --
    -- Порог мелкой денежной выгоды убирает советы ниже, уже после всех веток, -
    -- но список покупок кормится ЗДЕСЬ, до него. Пока он кормился всем подряд,
    -- на настоящих данных выходило четыре карточки «Купить материалы» под
    -- советы «на продажу», которые порог только что убрал, и сумма в шапке
    -- («материалы по советам») считалась по ним же. Порог спрашивается один раз
    -- и до веток покупок; само удаление карточек - в Engine:ApplyMoneyFloor.
    local floorNow = self:MoneyFloorNow(snap)
    for _, card in ipairs(self.cards) do
        -- Материалы попадают в список даже от сомнительной карточки - НО с
        -- отметкой, от кого они. Выкинуть их молча было бы ровно тем «тихим
        -- действием», от которого игрок уже пострадал: сумма списка менялась
        -- бы из-за суждения, которого он не видит. Вместо этого отметка едет
        -- дальше, и карточка покупки сама говорит, что товар нужен только под
        -- совет, которому я не верю.
        if card.plan then
            local gain = Engine.MoneyGainOf(card)
            if gain and floorNow > 0 and gain < floorNow then
                -- Этот совет порог уберёт. Его материалы в список не идут - и
                -- это не тихое действие: число убранных советов и покупок
                -- пишется строкой над списком (Engine.MoneyFloorText).
                if ns.Diag then ns.Diag:Count("shopping.skippedByMoneyFloor") end
            else
                ns.ShoppingList:AddPlan(card.plan, card.key, card.title,
                    card.suspect and (card.suspect.text or "числа не сходятся") or nil)
            end
        end
    end
    ns.ShoppingList:LoadPinned()
    counts.buy = timed("buy", Engine.AddBuyCards)
    counts.junk = timed("junk", Engine.AddJunkCards)
    -- Перепродажа у торговцев - после покупок: ей нужны цены, которые уже
    -- спрошены выше, и её собственный список покупок не формирует.
    counts.arbitrage = timed("arbitrage", Engine.AddArbitrageCards)
    counts.favor = timed("favor", Engine.AddFavorCards)
    -- Лагерь - после покупок: ему нужны цены, и своего списка закупок он не
    -- формирует (рецептов лагеря в книге нет, это предметы).
    counts.camp = timed("camp", Engine.AddCampCards)
    -- Развилка путей - после ветки экипировки: ей нужны её кандидаты.
    counts.paths = timed("paths", Engine.AddPathCards)
    counts.disenchant = timed("disenchant", Engine.AddDisenchantCards)
    counts.resale = timed("resale", Engine.AddResaleCards)
    counts.priceinfo = timed("priceinfo", Engine.AddPriceInfoCards)
    -- Другие персонажи - после покупок: ветка смотрит на список закупки и
    -- говорит, что из него уже лежит на альте.
    counts.cross = timed("cross", Engine.AddCrossCharCards)
    self.meta.branchMs = spent

    -- The player's own dismissals are counted before the ranking, so the card
    -- that explains an empty list takes part in it like any other.
    local hiddenCount, hiddenSoonest = self:HiddenSummary()
    self.meta.hiddenByDismissal = hiddenCount
    self.meta.hiddenUntil = hiddenSoonest
    if #self.cards == 0 and hiddenCount > 0 then
        counts.hidden = self:AddHiddenCard()
    end

    -- МЕЛКАЯ ДЕНЕЖНАЯ ВЫГОДА УХОДИТ ИЗ СПИСКА - И ЭТО СКАЗАНО СТРОКОЙ.
    --
    -- Порог, полосы по уровню и то, откуда взялись числа, - в Core/Const.lua
    -- (ns.MONEY_FLOOR_BANDS); какой порог действует сейчас, отвечает
    -- Config:MoneyFloor и только он. Здесь - применение и отчёт.
    --
    -- Идёт ДО профиля: порог - правило игрока о том, что вообще стоит
    -- показывать, а профиль - способ смотреть. Так два числа на экране не
    -- пересекаются: «порог убрал 11» и «профиль не показывает 3» говорят про
    -- разные карточки, и их можно сложить.
    self:ApplyMoneyFloor(snap)

    -- СОСТАВ СПИСКА ЗАВИСИТ ОТ ПРОФИЛЯ, А НЕ ТОЛЬКО ПОРЯДОК.
    --
    -- Карточка, которой в этом профиле быть не должно, убирается - но НЕ МОЛЧА:
    -- число убранных и причина пишутся в branchNote, попадают в сводку по
    -- веткам и видны в окне. Аддон уже один раз тихо съел все советы, и
    -- «пропало, потому что профиль» без объяснения - то же самое.
    local profile = ns.Config:Profile()
    local exclude = ns.PROFILE_EXCLUDE and ns.PROFILE_EXCLUDE[profile] or nil
    if exclude and next(exclude) then
        local kept, dropped, byKind = {}, 0, {}
        for _, card in ipairs(self.cards) do
            -- Обязательные карточки профиль не трогает: без них список неверен.
            if exclude[card.kind] and not card.pinTop and not card.blocking then
                dropped = dropped + 1
                byKind[card.kind] = (byKind[card.kind] or 0) + 1
            else
                kept[#kept + 1] = card
            end
        end
        self.cards = kept
        self.meta.profileDropped = dropped
        self.meta.profileDroppedByKind = byKind
        if dropped > 0 then
            local names = {}
            for kind, n in pairs(byKind) do
                names[#names + 1] = (ns.KIND_LABEL[kind] or kind) .. " (" .. n .. ")"
            end
            table.sort(names)
            local note = "профиль «" .. (ns.PROFILE_LABEL[profile] or profile)
                .. "» убрал из списка: " .. table.concat(names, ", ")
                .. " — в другом профиле они вернутся"
            self.meta.profileNote = note
            -- И в примечание тех веток, чьи карточки убраны: в окне видно
            -- именно по веткам. ПРИПИСЫВАЕТСЯ, А НЕ ЗАТИРАЕТ: у ветки уже может
            -- стоять причина от порога мелкой выгоды, и она тоже про пропажу.
            for kind in pairs(byKind) do
                local branch = Engine.BRANCH_BY_KIND[kind]
                if branch then
                    self.branchNote[branch] = self.branchNote[branch]
                        and Engine.JoinSentences(self.branchNote[branch], U.capitalize(note))
                        or note
                end
            end
            if ns.Diag then
                ns.Diag:Count("cards.droppedByProfile", dropped)
                ns.Diag:Log("профиль изменил состав списка", {
                    profile = profile, dropped = dropped, byKind = byKind,
                })
            end
        end
    end

    -- Score and rank.
    local weights = ns.Config:Weights()
    for _, card in ipairs(self.cards) do self:Score(card, weights, profile) end

    self.cards = U.stableSortBy(self.cards, Engine.RankValue, true)

    local generated = #self.cards
    if #self.cards > ns.MAX_CARDS then
        local trimmed = {}
        for i = 1, ns.MAX_CARDS do trimmed[i] = self.cards[i] end
        self.cards = trimmed
    end
    self.meta.generated = generated

    -- СКОЛЬКО КАРТОЧЕК КАЖДОЙ ВЕТКИ ОСТАЛОСЬ НА ЭКРАНЕ.
    --
    -- Это НЕ то же, что вернула ветка, и расходятся они штатно: профиль убирает
    -- карточки после всех веток, дубликаты сворачиваются, скрытое прячется.
    -- Сводка считала построенное, а игрок видит оставшееся - и из-за этого
    -- говорила «ветка молчит» про ветку с тремя карточками на экране. Живой
    -- файл показывал и обратную ошибку: resale=4 и priceinfo=1 при пометке
    -- «профиль убрал из списка», то есть на экране ноль, а молчащими они не
    -- считались.
    --
    -- Считается ОДИН раз по готовому списку, после профиля и ранжирования:
    -- отсюда и дальше «ветка выдала N» означает «N видно на экране».
    local onScreen = {}
    for _, key in ipairs(Engine.BRANCH_ORDER) do onScreen[key] = 0 end
    for _, card in ipairs(self.cards) do
        local branch = Engine.BRANCH_BY_KIND[card.kind]
        if branch then onScreen[branch] = (onScreen[branch] or 0) + 1 end
    end
    self.meta.branchBuilt = counts
    self.meta.branchOnScreen = onScreen

    -- И причина у ветки, которая построила карточки, а на экране их не имеет,
    -- обязана говорить, КТО их убрал. Пометку про профиль выставляет сам
    -- фильтр выше; здесь страхуется случай, когда карточки исчезли по другой
    -- причине (свернулись дубликаты, игрок их скрыл) и объяснения нет вовсе.
    for _, key in ipairs(Engine.BRANCH_ORDER) do
        if (counts[key] or 0) > 0 and (onScreen[key] or 0) == 0
           and not self.branchNote[key] then
            self.branchNote[key] = "ветка выдала " .. (counts[key] or 0) .. " "
                .. U.plural(counts[key] or 0, "совет", "совета", "советов")
                .. ", но до экрана они не дошли — проверьте фильтр, профиль и"
                .. " скрытые советы"
        end
    end

    self.meta.counts = counts
    self.meta.profile = ns.Config:Profile()
    self.meta.priceSources = ns.PriceProvider:SourceSummary()
    self.meta.shoppingTotal, self.meta.shoppingConf = ns.ShoppingList:Total()
    self.meta.shoppingLines = ns.ShoppingList:Count()
    self.meta.builtAt = Api:ServerTime()
    self.meta.recipeSummary = ns.RecipeBook:Summary()
    self.meta.learnedRecipes = ns.RecipeBook:LearnedCount()
    self.meta.missingProfessions = ns.RecipeBook.missingProfessions
    -- One line per branch: how many cards it produced and, when that is none,
    -- the reason in the branch's own words. This is what lets an empty window
    -- say what is actually missing instead of "всё уже сделано".
    --
    -- Число берётся ПО ЭКРАНУ, а не по тому, что ветка построила: отчёт читают,
    -- глядя на тот же список, и расхождение в нём - это расхождение с глазами.
    self.meta.branches = self:Branches(onScreen, counts)

    if ns.Diag then
        self:ReportToDiag(snap, onScreen, generated, scales, counts)
        -- ПЕРВЫЙ ПЕРЕСЧЁТ НАЗВАН ОТДЕЛЬНО, И ЭТО НЕ КОСМЕТИКА.
        --
        -- В живом файле пик (124.7 мс против 33 средних) стоял с подписью
        -- «полный пересчёт» и датой, равной времени входа в игру: это был первый
        -- пересчёт, у которого пусты ВСЕ кеши - предметы, цены, Codex,
        -- характеристики. Такой пересчёт честно дороже остальных, и один раз за
        -- сессию он неизбежен. Пока подпись у него была общая, пик нельзя было
        -- отличить от подорожания обычного пересчёта - то есть самое полезное
        -- число в разделе ни о чём не говорило.
        ns.Diag:TimerStop(timer,
            (self.buildCount == 1) and "первый пересчёт после входа (кеши пусты)"
            or "полный пересчёт")
        ns.Diag:Trim()
    end
    return self.cards, self.meta
end

-- Порог мелкой денежной выгоды ------------------------------------------
--
-- «Если я выигрываю меньше 20 или 30 золотых … то смысла нету это показывать,
-- особенно выше чем в 20-м левеле» - дословная просьба игрока. Полосы по
-- уровню и числа лежат в Core/Const.lua, действующий порог отдаёт
-- Config:MoneyFloor, а здесь он применяется - к денежным ветками и только к
-- ним (ns.MONEY_FLOOR_KINDS): баллы за вещь и пункты навыка золотом не мерят.
--
-- И НИ ОДНОЙ МОЛЧА. Исчезновение совета в этом проекте всегда объявляется:
-- число убранных, самая крупная из убранных выгод, сам порог и чем его снять -
-- всё это уезжает в meta, оттуда в строку над списком (UI/TabNow.lua) и в
-- примечание ветки. Перечень путей исчезновения закрыт - Tests/test_vanish.lua.

-- Сколько карточка «выигрывает» в меди, с точки зрения порога. nil означает
-- «порогом не меряется»: не денежная ветка или число неизвестно.
function Engine.MoneyGainOf(card)
    if type(card) ~= "table" then return nil end
    if not (ns.MONEY_FLOOR_KINDS or {})[card.kind] then return nil end
    -- Обязательные карточки порог не трогает: без них список неверен. Таких
    -- среди денежных веток нет, но правило то же, что у профиля, и держать его
    -- в одном месте дешевле, чем выяснять потом, почему оно разное.
    if card.pinTop or card.blocking then return nil end
    return tonumber(card.benefitValue)
end

-- Название раздела настроек - одной строкой на весь аддон: именно по ней игрок
-- ищет, где снять порог, и расхождение здесь стоило бы ему поиска.
Engine.MONEY_FLOOR_SECTION = "Мелкая денежная выгода"

-- Строка про порог: сколько убрано, какая выгода была самой крупной из
-- убранных, и чем это вернуть. Собирается здесь, чтобы окно, примечание ветки
-- и сводка диагностики брали одни и те же слова.
function Engine.MoneyFloorText(floor, dropped, byKind, biggest, band, orphans)
    local names = {}
    for kind, n in pairs(byKind or {}) do
        names[#names + 1] = (ns.KIND_LABEL[kind] or tostring(kind)) .. " (" .. n .. ")"
    end
    table.sort(names)
    local text = "порог мелкой выгоды (" .. U.money(floor) .. ") убрал "
        .. dropped .. " " .. U.plural(dropped, "денежный совет", "денежных совета",
                                      "денежных советов")
        .. ((#names > 0) and (": " .. table.concat(names, ", ")) or "")
    -- Покупки, которые были нужны только убранным советам, ушли вместе с ними -
    -- и это сказано отдельным числом: игрок видит, что список покупок стал
    -- короче, и должен понимать, из-за чего.
    orphans = tonumber(orphans) or 0
    if orphans > 0 then
        text = text .. ", а с ними " .. orphans .. " "
            .. U.plural(orphans, "покупка", "покупки", "покупок")
            .. ", нужных только им"
    end
    -- САМОЕ КРУПНОЕ ИЗ УБРАННОГО - ЧТОБЫ БЫЛО ВИДНО, ЧЕГО ИГРОК ЛИШИЛСЯ.
    -- Ноль и минус так и названы: «давал 0м» выглядело бы как потеря, которой
    -- не было, а это ровно тот случай, когда порог не отрезал ничего ценного.
    if biggest and biggest > 0 then
        text = text .. ". Самый крупный из убранных давал " .. U.moneyDelta(biggest)
    elseif biggest then
        text = text .. ". Ни один из убранных не был в плюсе"
    end
    if band then
        text = text .. ". Порог взят по уровню персонажа (" .. band.label .. ")"
    end
    return text .. ". Порог меняется и снимается в настройках, раздел «"
        .. Engine.MONEY_FLOOR_SECTION .. "»"
end

-- Порог, действующий на этом пересчёте. Спрашивается у Config:MoneyFloor и
-- запоминается: его читают дважды - когда кормится список покупок (до веток
-- покупок) и когда карточки убираются (после всех веток), - и два разных ответа
-- на один вопрос дали бы покупки под советы, которых на экране нет.
function Engine:MoneyFloorNow(snap)
    local floor, mode, band = ns.Config:MoneyFloor(snap and snap.level)
    floor = tonumber(floor) or 0
    self.meta.moneyFloor = floor
    self.meta.moneyFloorMode = mode
    self.meta.moneyFloorBand = band
    return floor, mode, band
end

function Engine:ApplyMoneyFloor(snap)
    local level = snap and snap.level
    local floor, mode, band = self:MoneyFloorNow(snap)
    self.meta.moneyFloor = floor
    self.meta.moneyFloorMode = mode
    self.meta.moneyFloorBand = band
    self.meta.moneyFloorDropped = 0
    self.meta.moneyFloorByKind = {}
    -- Порог есть всегда, а вот денежных карточек под ним может не быть: тогда
    -- считать нечего, и строки на экране тоже не будет.
    if floor <= 0 then return 0 end

    local kept, dropped, byKind, biggest, gone = {}, 0, {}, nil, {}
    for _, card in ipairs(self.cards) do
        local gain = Engine.MoneyGainOf(card)
        if gain and gain < floor then
            dropped = dropped + 1
            byKind[card.kind] = (byKind[card.kind] or 0) + 1
            gone[card.key] = true
            if (not biggest) or gain > biggest then biggest = gain end
        else
            kept[#kept + 1] = card
        end
    end

    -- ПОКУПКА, КОТОРАЯ БЫЛА НУЖНА ТОЛЬКО УБРАННОМУ СОВЕТУ, УХОДИТ ЗА НИМ.
    --
    -- Ветка покупок работает ДО порога, поэтому на настоящих данных выходило
    -- так: порог убрал «На продажу: Лунная винтовка», а карточка «Купить:
    -- Предмет #1705 x2» осталась со строкой «Нужно для: На продажу: Лунная
    -- винтовка» - то есть обещала материал под совет, которого на экране нет.
    -- Покупка, у которой не осталось ни одного заказчика, уходит; у той, у кого
    -- часть заказчиков осталась, первая фраза переписывается по оставшимся.
    -- Позиция, закреплённая игроком руками, заказчиком считается всегда: её
    -- просил он сам, и порог к ней отношения не имеет.
    local orphans = 0
    if dropped > 0 then
        local after = {}
        for _, card in ipairs(kept) do
            local owners = (card.kind == ns.KIND.BUY) and card.buyFor or nil
            if type(owners) ~= "table" then
                after[#after + 1] = card
            else
                local live, total = {}, 0
                for key, title in pairs(owners) do
                    total = total + 1
                    if not gone[key] then live[#live + 1] = title end
                end
                if total > 0 and #live == 0 then
                    orphans = orphans + 1
                else
                    if #live < total then
                        local titles, pinned = {}, false
                        for _, title in ipairs(live) do
                            if title == Engine.PINNED_BY_HAND then pinned = true
                            else titles[#titles + 1] = title end
                        end
                        table.sort(titles)
                        if #titles > 0 then
                            card.why = Engine.BuyUseText(titles)
                                .. (card.buyWhyTail or "")
                            card.whyBase = nil
                            if ns.Risk then ns.Risk:RenderDoubts(card) end
                        elseif pinned then
                            -- ПОРОГ УБРАЛ ВСЕХ ЗАКАЗЧИКОВ, ОСТАЛОСЬ ЗАКРЕПЛЕНИЕ.
                            --
                            -- Здесь не делалось ничего, и карточка оставалась со
                            -- строкой «Нужно для: На продажу: …» про совет,
                            -- которого на экране уже нет, - то есть ровно та
                            -- ошибка, от которой этот блок и написан. Теперь это
                            -- становится карточкой своего списка: единственный
                            -- заказчик тут - сам игрок.
                            Engine.AsOwnListCard(card)
                        end
                        -- Третьего случая нет: сюда приходят только те, у кого
                        -- хоть один заказчик остался (иначе карточка уже ушла
                        -- как сирота), а заказчик - это либо имя совета, либо
                        -- закрепление игрока.
                    end
                    after[#after + 1] = card
                end
            end
        end
        kept = after
    end

    self.cards = kept
    self.meta.moneyFloorDropped = dropped
    self.meta.moneyFloorByKind = byKind
    self.meta.moneyFloorBiggest = biggest
    self.meta.moneyFloorOrphans = orphans
    if dropped == 0 then return 0 end

    local note = Engine.MoneyFloorText(floor, dropped, byKind, biggest, band, orphans)
    self.meta.moneyFloorNote = note
    for kind in pairs(byKind) do
        local branch = Engine.BRANCH_BY_KIND[kind]
        if branch then
            self.branchNote[branch] = self.branchNote[branch]
                and Engine.JoinSentences(self.branchNote[branch], U.capitalize(note))
                or note
        end
    end
    if ns.Diag then
        ns.Diag:Count("cards.droppedByMoneyFloor", dropped)
        ns.Diag:Log("порог мелкой денежной выгоды убрал советы", {
            floor = floor, mode = mode, level = level,
            band = band and band.label or nil,
            dropped = dropped, byKind = byKind, biggest = biggest,
        })
    end
    return dropped
end

-- Branch report ---------------------------------------------------------
--
-- Six lines, one per branch, each with the count it produced and - when that is
-- zero - the reason the branch itself recorded while it ran. No new computation
-- happens here: every number and every string was already produced by the
-- build, which is why this is safe on every recompute and safe to show in the
-- window. It exists because "Всё уже сделано" on an empty list is not an
-- answer, and the player asked to be able to see what is missing where.

Engine.BRANCH_ORDER = { "equip", "gear", "enchant", "profit", "skill", "buy",
                        "junk", "arbitrage", "favor", "camp", "paths",
                        "disenchant", "resale", "priceinfo", "cross" }
Engine.BRANCH_LABEL = {
    equip      = "Надеть своё",
    gear       = "Экипировка",
    enchant    = "Чары",
    profit     = "Крафт на продажу",
    skill      = "Крафт на навык",
    buy        = "Покупки",
    junk       = "Продажа хлама",
    arbitrage  = "Перепродажа у торговцев",
    favor      = "Благосклонность торговца",
    camp       = "Лагерь у костра",
    paths      = "Развилка путей",
    cross      = "Другие персонажи",
    -- ЭТИ ТРИ ЛЕЖАЛИ В СОСЕДНЕЙ ТАБЛИЦЕ, И ЭТО БЫЛО ВИДНО ИГРОКУ.
    --
    -- Они стояли в BRANCH_BY_KIND - таблице «вид карточки -> ветка», где им
    -- нечего делать: ключи там ВИДЫ (ARBITRAGE, FAVOR), а не названия веток.
    -- Из-за этого BRANCH_LABEL.disenchant был nil, и русская сводка печатала
    -- «Молчат 3 из 14 веток: … disenchant (…)» английским ключом посреди
    -- русского текста.
    disenchant = "Распыление",
    resale     = "Перекупка лотов",
    priceinfo  = "Что говорят цены",
}

-- Вид карточки -> ветка, которая её делает. Нужно, чтобы «профиль убрал эти
-- карточки» попало в примечание именно той ветки, чьи карточки убраны: в окне
-- причины показываются по веткам, а не по видам.
Engine.BRANCH_BY_KIND = {
    EQUIP        = "equip",
    CRAFT_GEAR   = "gear",
    ENCHANT      = "enchant",
    CRAFT_PROFIT = "profit",
    CRAFT_SKILL  = "skill",
    BUY          = "buy",
    SELL_JUNK    = "junk",
    ARBITRAGE    = "arbitrage",
    FAVOR        = "favor",
    CAMP         = "camp",
    PATHS        = "paths",
    DISENCHANT   = "disenchant",
    RESELL       = "resale",
    PRICE_INFO   = "priceinfo",
    CROSS_CHAR   = "cross",
}

-- `onScreen` - сколько карточек ветки видно; `built` - сколько она построила.
-- Числа разные, и показывается первое: отчёт читают, глядя на список.
function Engine:Branches(onScreen, built)
    onScreen = onScreen or {}
    built = built or {}
    local out = {}
    for _, key in ipairs(Engine.BRANCH_ORDER) do
        -- ПРИЧИНА НУЖНА НЕ ТОЛЬКО ПРИ НУЛЕ. Обычно reason объясняет пустую
        -- ветку, но профиль может убрать часть карточек у ветки, которая всё
        -- равно что-то выдала - и об этом надо сказать, иначе «пропало,
        -- потому что профиль» останется необъяснённым.
        local note = self.branchNote[key]
        local zero = ((onScreen[key] or 0) == 0)
        out[#out + 1] = {
            key = key,
            label = Engine.BRANCH_LABEL[key] or key,
            count = onScreen[key] or 0,
            built = built[key] or 0,
            reason = (zero or (note and U.contains(note, "профиль"))) and note or nil,
        }
    end
    return out
end

-- Diagnostics -----------------------------------------------------------
--
-- Everything written here is a number the build already produced. The only new
-- work is a loop over at most forty cards, which is why it is safe to do on
-- every recompute.

-- `counts` здесь - это СКОЛЬКО ВИДНО НА ЭКРАНЕ, а `built` - сколько ветки
-- построили. Сводка читает первое: она описывает то, на что игрок смотрит.
function Engine:ReportToDiag(snap, counts, generated, scales, built)
    local Diag = ns.Diag
    local book = ns.RecipeBook

    -- Per-module input/output, with a reason whenever the output is zero.
    local profs = ns.CharacterScanner:CraftingProfessions()
    local recipeTotal, recipeLearned = 0, 0
    for _, bucket in pairs(book.byProfession or {}) do
        for _, r in ipairs(bucket.list) do
            recipeTotal = recipeTotal + 1
            if r.learned then recipeLearned = recipeLearned + 1 end
        end
    end

    -- How often the client reported the same profession twice. Zero is the
    -- expected answer; the real character answered four, which is what the
    -- de-duplication in the scanner now absorbs.
    local dupProfs = 0
    for _, prof in ipairs(snap.professions or {}) do
        dupProfs = dupProfs + (prof.duplicates or 0)
    end

    Diag:Module("characterScanner", {
        ["in"] = 1, out = snap.level and 1 or 0,
        level = snap.level, class = snap.classFile, spec = snap.spec,
        professions = #(snap.professions or {}),
        craftingProfessions = #profs,
        duplicateProfessionRecords = dupProfs,
        bagsConf = snap.bagsConf, equippedConf = snap.equippedConf,
        reason = (not snap.level) and "клиент не вернул уровень персонажа" or nil,
        reasonCode = (not snap.level) and "API_SILENT" or nil,
    })

    Diag:Module("bags", {
        ["in"] = 1, out = U.count(snap.bags),
        stacks = #(snap.bagSlots or {}),
        conf = snap.bagsConf,
        reason = (U.count(snap.bags) == 0)
            and "в сумках ничего не найдено — либо пусты, либо чтение не сработало" or nil,
        reasonCode = (U.count(snap.bags) == 0)
            and ((snap.bagsConf == CONF.EXACT) and "EMPTY" or "API_SILENT") or nil,
    })

    -- BANK: "never opened" and "opened and empty" are different answers, and
    -- only the first one had a reason. The player's own file read
    -- "bank: out=0 seen=true reason=причина не указана — это дефект самой
    -- диагностики": the diagnostics correctly accused itself of a hole, because
    -- an empty-but-seen bank fell between the two branches of the old test.
    local bankCount = snap.bank and U.count(snap.bank) or 0
    local bankReason, bankCode
    if snap.bank == nil then
        bankReason = "банк ни разу не открывали — считаются только сумки"
        bankCode = "NOT_SEEN"
    elseif bankCount == 0 then
        bankReason = "банк мы видели, и он пуст — брать из него нечего"
        bankCode = "EMPTY"
    end
    Diag:Module("bank", {
        ["in"] = 1, out = bankCount,
        seen = snap.bank ~= nil, conf = snap.bankConf,
        reason = bankReason, reasonCode = bankCode,
    })

    Diag:Module("equipment", {
        ["in"] = 1, out = U.count(snap.equipped),
        conf = snap.equippedConf,
        reason = (U.count(snap.equipped) == 0)
            and "ни один слот не прочитан" or nil,
        reasonCode = (U.count(snap.equipped) == 0) and "API_SILENT" or nil,
    })

    -- БАФФЫ. Список имён пишется в файл целиком (их не больше сорока): по нему
    -- видно, что именно игра отдаёт, и какие баффы даёт лагерь - без этого
    -- научить ветку лагеря говорить «уже действует» нечем.
    do
        local names = {}
        for i, a in ipairs(snap.auras or {}) do
            if i > 40 then break end
            names[#names + 1] = tostring(a.name) .. "#" .. tostring(a.spellID)
        end
        local reason, code = nil, nil
        if snap.auraSource == nil then
            reason, code = "прочитать баффы нечем: ни C_UnitAuras, ни UnitBuff", "NO_API"
        elseif #names == 0 then
            reason, code = "баффов на игроке сейчас нет", "EMPTY"
        end
        Diag:Module("auras", {
            ["in"] = 1, out = #names,
            source = snap.auraSource,
            names = names,
            reason = reason, reasonCode = code,
        })
    end

    Diag:Module("recipeBook", {
        ["in"] = #profs, out = recipeLearned,
        total = recipeTotal, learned = recipeLearned,
        professions = U.count(book.byProfession),
        missingProfessions = #(book.missingProfessions or {}),
        sources = (function()
            local s = {}
            for name, bucket in pairs(book.byProfession or {}) do
                s[name] = bucket.source
            end
            return s
        end)(),
        reason = (recipeLearned == 0)
            and ((#(book.missingProfessions or {}) > 0)
                and "окно профессии ни разу не открывали — игра не отдаёт рецепты"
                or "рецепты есть, но ни один не помечен выученным") or nil,
        reasonCode = (recipeLearned == 0)
            and ((#(book.missingProfessions or {}) > 0)
                and "WINDOW_NEVER_OPEN" or "NOTHING_LEARNED") or nil,
    })

    -- Enchant slots: how many we could place, and how many we could not.
    local bySlot, unresolved = ns.EnchantAdvisor:BySlot()
    local slotCount, formulaCount = 0, 0
    for _, list in pairs(bySlot) do
        slotCount = slotCount + 1
        formulaCount = formulaCount + #list
    end
    local enchStatus = ns.EnchantAdvisor:SlotStatus(snap)
    Diag:Module("enchantSlots", {
        ["in"] = formulaCount + #unresolved, out = slotCount,
        formulasPlaced = formulaCount, formulasUnplaced = #unresolved,
        bareSlots = #ns.EnchantAdvisor:BareSlots(snap),
        -- The good news, recorded as a number: on the real character seven of
        -- eight enchantable slots were already done, and nothing in the file
        -- said so. "out = 8" next to a card reading "формул нет" looked like a
        -- failure when it was the opposite.
        slotsEnchantable = enchStatus.enchantable,
        slotsEnchanted = enchStatus.enchanted,
        slotsBare = enchStatus.bare,
        slotsBareWithFormula = enchStatus.bareWithFormula,
        bareSlotNames = enchStatus.bareLabels,
        reason = (slotCount == 0)
            and ((formulaCount + #unresolved == 0)
                and "выученных формул чар нет"
                or "формулы есть, но ни одну не удалось привязать к слоту") or nil,
        reasonCode = (slotCount == 0)
            and ((formulaCount + #unresolved == 0)
                and "NOTHING_LEARNED" or "FILTERED_OUT") or nil,
    })

    -- Prices: asked versus answered, by source.
    local ps = ns.PriceProvider:SourceSummary()
    local answered = (ps.auctionator or 0) + (ps.foreign or 0) + (ps.vendor or 0)
        + (ps.estimate or 0)
    Diag:Module("prices", {
        ["in"] = ps.total or 0, out = answered,
        auctionator = ps.auctionator, foreign = ps.foreign,
        vendor = ps.vendor, estimate = ps.estimate, unknown = ps.unknown,
        auctionatorAvailable = ps.auctionatorAvailable,
        reason = (answered == 0)
            and ((ps.total or 0) == 0 and "цены ни разу не запрашивались"
                or "ни один источник цен не ответил") or nil,
        reasonCode = (answered == 0)
            and ((ps.total or 0) == 0 and "NOT_SEEN" or "NO_PRICE_SOURCE") or nil,
    })

    -- Places and navigation.
    local places = ns.Places:Summary()
    Diag:Module("places", {
        ["in"] = places.npcs or 0, out = places.routable or 0,
        itemVendors = places.items, trainers = places.trainers,
        provider = places.provider, hasFacing = places.hasFacing,
        tomtom = places.tomtom,
        reason = ((places.routable or 0) == 0)
            and "ни одного места с координатами — торговцев и тренеров ещё не открывали" or nil,
        reasonCode = ((places.routable or 0) == 0) and "NOT_SEEN" or nil,
    })

    -- Cards by kind.
    local byKind = {}
    for _, card in ipairs(self.cards) do
        byKind[card.kind] = (byKind[card.kind] or 0) + 1
    end
    -- The reason an empty list is empty, in the order the causes actually
    -- happen. Dismissals come FIRST: the branches producing candidates that
    -- the player's own dismissals then swallow used to be reported as "no
    -- branch produced anything", which sent the search in the wrong direction
    -- for a whole session.
    local hidden = self.meta.hiddenByDismissal or 0
    local emptyReason, emptyCode
    if #self.cards == 0 then
        if hidden > 0 then
            emptyReason = "все " .. hidden .. " карточек скрыты игроком"
                .. " (ForeverPilotDB.dismissed) — ветки работают"
            emptyCode = "HIDDEN_BY_PLAYER"
        else
            emptyReason = "ни одна ветка советов ничего не выдала"
            emptyCode = "FILTERED_OUT"
        end
    end

    Diag:Module("actionEngine", {
        ["in"] = recipeLearned, out = #self.cards,
        generated = generated, byKind = byKind, branchCounts = counts,
        -- Оба числа в файле: по расхождению видно, что карточки были и
        -- куда-то делись, а не что ветка промолчала.
        branchBuilt = built or counts,
        branchMs = self.meta.branchMs,
        hiddenByDismissal = hidden,
        hiddenUntil = self.meta.hiddenUntil,
        branchNotes = self.branchNote,
        profile = ns.Config:Profile(),
        scales = scales and { power = scales.power, profit = scales.profit,
                              spend = scales.spend, kitScore = scales.kitScore } or nil,
        duplicatesCollapsed = self.dupes or 0,
        -- HOW MANY TIMES WE WENT TO THE CLIENT. These are the numbers that
        -- were missing when a live session reported 69 ms a rebuild and the
        -- file could not say why: the item database count was there, the two
        -- expensive client calls were not. One rebuild used to make about 930
        -- GetItemInfo, 280 GetItemStats and 280 database lookups.
        clientCalls = {
            itemInfoReads = Api.itemInfoReads or 0,
            itemInfoCacheHits = Api.itemInfoHits or 0,
            itemStatsReads = Api.itemStatsReads or 0,
            itemDBReads = Api.itemDBReads or 0,
            foreignCacheHits = Api.foreignCacheHits or 0,
            -- ОБРАЩЕНИЯ К CODEX. Счётчика здесь не было вовсе, и ровно поэтому
            -- 454 обращения за каждый пересчёт прожили незамеченными до живого
            -- прогона: все остальные расходы были под присмотром, а этот нет.
            -- Числа за пересчёт: reads - сколько раз пакет пришлось читать,
            -- hits - сколько раз ответ нашёлся у нас.
            codexReads = Api.codexReads or 0,
            codexCacheHits = Api.codexHits or 0,
            -- Чужой кеш наблюдённых цен: сколько раз таблицу лотов пришлось
            -- перебрать (reads) и сколько раз ответ нашёлся у нас (hits).
            observedPriceReads = Api.observedPriceReads or 0,
            observedPriceCacheHits = Api.observedPriceHits or 0,
            -- ОБЛИК. Три разных числа, и путать их нельзя: asked - сколько раз
            -- вопрос «собран ли облик» вообще возник, reads - сколько раз из
            -- них пришлось спросить клиента, hits - сколько ответов нашлось у
            -- нас. На клиенте, где этих функций нет, asked останется, а reads
            -- будет нулём - и по этой паре видно, что проверять было нечем.
            appearanceAsked = Api.appearanceAsked or 0,
            appearanceReads = Api.appearanceReads or 0,
            appearanceCacheHits = Api.appearanceHits or 0,
        },
        reason = emptyReason,
        reasonCode = emptyCode,
    })

    -- Duplicates, the loss funnels and the plain-Russian report. All three read
    -- numbers the build already produced.
    Diag:Dedupe({
        collapsed = self.dupes or 0,
        byKey = self.dupeKeyHits or 0,
        byAction = self.dupeActionHits or 0,
        examples = self.dupeDetail or {},
        recipeBookMerges = (Diag:Init().counters or {})["recipeBook.sourceMerged"] or 0,
    })

    -- The gear branch gets a breakdown rather than a guess: on the real
    -- character it reported "no item stats" for 263 recipes when most of them
    -- had simply never been candidates in the first place.
    local gearStats = ns.GearAdvisor.lastStats or {}
    Diag:Module("gearAdvisor", {
        ["in"] = recipeLearned, out = counts.gear or 0,
        considered = gearStats.considered,
        pending = gearStats.pending,
        notGear = gearStats.notGear,
        otherSlot = gearStats.otherSlot,
        wearable = gearStats.wearable,
        unwearable = gearStats.unwearable or #ns.GearAdvisor:Unwearable(snap),
        withStats = gearStats.withStats,
        noStats = gearStats.noStats,
        reason = ((counts.gear or 0) == 0)
            and ("улучшений не найдено: " .. (ns.GearAdvisor:LossReason(gearStats)
                 or "нечего сравнивать")) or nil,
        reasonCode = ((counts.gear or 0) == 0)
            and (((gearStats.withStats or 0) == 0) and "NO_STATS" or "NO_UPGRADE") or nil,
    })

    -- And the sanity sweep. Suspicions are cleared first so a fixed problem
    -- stops being reported; the delta and the written summary come after, so
    -- both see the suspicions this build actually raised.
    --
    -- ПРОХОД ИДЁТ ДО ЗАПИСИ КАРТОЧЕК, А НЕ ПОСЛЕ, И ЭТО НЕ ПОРЯДОК РАДИ ПОРЯДКА.
    -- Проход прикладывает найденное к карточкам и переставляет список, поэтому
    -- запись «карточки ровно так, как их видел игрок» обязана идти после него -
    -- иначе в файле лежал бы список, которого на экране не было.
    ns.Diag:ClearSuspicions()
    self:Sweep(snap, counts, generated)

    -- The cards exactly as the player saw them.
    self:RecordCards()

    -- Откуда что взято: сводка по источникам, тем же составом, что и в окне.
    -- Считается из уже готовых чисел, поэтому безопасно на каждом пересчёте.
    if ns.Provenance then ns.Provenance:Report() end

    -- Last, in this order on purpose: the delta needs this build's numbers, and
    -- the summary quotes the delta.
    ns.Diag:ComputeDelta()
    ns.Diag:WriteSummary()
    ns.Diag:Heartbeat("пересчёт советов")
end

-- The first N cards, verbatim: title, payoff, reason, what is missing, and the
-- confidence. This is what makes the file answer "was the advice sensible",
-- not just "did the code run".
function Engine:RecordCards()
    local Diag = ns.Diag
    local s = Diag:Init()
    s.cards = {}
    for i = 1, math.min(Diag.CAP.cards, #self.cards) do
        local card = self.cards[i]
        local plan = card.plan

        -- TWO different prices, recorded under two different names.
        --
        -- This field used to be one `priceSource`, filled from
        -- plan.shopping[1] - the price of the first MATERIAL the player still
        -- has to buy - and then printed next to the card's revenue figure. On
        -- the real character that produced a card reading "выручка 4з 76с,
        -- сбор аукциона уже вычтен" with "priceSource = vendor" beside it: two
        -- claims that cannot both be about the same number, and an afternoon
        -- spent looking for a bug in the revenue that was never there.
        local matConf, matSrc, matAge
        if card.matPrice then
            matConf, matSrc, matAge = card.matPrice.conf, card.matPrice.src, card.matPrice.age
        elseif plan and plan.shopping and plan.shopping[1] then
            local line = plan.shopping[1]
            matConf, matSrc, matAge = line.conf, line.src, line.age
        end
        local origin = card.revOrigin
        s.cards[i] = {
            rank = i,
            kind = card.kind,
            kindLabel = ns.KIND_LABEL[card.kind] or card.kind,
            title = card.title,
            benefit = card.benefit,
            benefitValue = card.benefitValue,
            why = card.why,
            need = card.need,
            conf = card.conf,
            confLabel = ns.CONF_LABEL[card.conf],
            -- what the MATERIALS cost, and where that came from
            matPriceSource = matSrc,
            matPriceConf = matConf,
            matPriceAgeSeconds = matAge,
            -- what the SALE brings in, and where THAT came from
            revenue = card.revenue,
            revenueSource = origin and origin.src or nil,
            revenueConf = origin and origin.conf or nil,
            revenueAgeSeconds = origin and origin.age or nil,
            revenueCutApplied = origin and origin.cutApplied or nil,
            score = card.score,
            scoreRaw = card.scoreRaw,
            axes = card.axes and U.copy(card.axes) or nil,
            cost = card.cost,
            ready = plan and plan.ready or nil,
            readiness = plan and plan.readiness or nil,
            missingCount = plan and plan.missingCount or nil,
            craftSteps = plan and #plan.crafts or nil,
            pinTop = card.pinTop,
            blocking = card.blocking,
            -- СОМНЕНИЕ, КОТОРОЕ ДОЕХАЛО ДО КАРТОЧКИ. Без этих двух полей файл
            -- отвечал только на вопрос «что нашла самопроверка», а вопрос «что
            -- из этого прочитал игрок» оставался без ответа - и ответ был «ничего».
            doubtLevel = card.doubtLevel,
            doubts = (function()
                local list = card.doubts
                if type(list) ~= "table" or #list == 0 then return nil end
                local codes = {}
                for _, d in ipairs(list) do codes[#codes + 1] = d.code end
                return codes
            end)(),
            recipeID = card.recipeID,
            itemID = card.itemID,
            place = card.place and {
                name = card.place.name, zone = card.place.zone,
                routable = card.place.routable,
            } or nil,
            action = card.action and card.action.kind or nil,
        }
    end
    s.cardsTotal = #self.cards
end

-- Filtering ------------------------------------------------------------

function Engine:Filtered(chip)
    chip = chip or ns.CHIP.ALL
    if chip == ns.CHIP.ALL then return self.cards end

    local out = {}
    if chip == ns.CHIP.READY then
        for _, card in ipairs(self.cards) do
            local ready = card.pinTop or (card.plan and card.plan.ready)
                or card.kind == ns.KIND.SELL_JUNK or card.kind == ns.KIND.SETUP
            if ready then out[#out + 1] = card end
        end
        return out
    end

    local allowed = ns.CHIP_KINDS[chip]
    for _, card in ipairs(self.cards) do
        if (not allowed) or allowed[card.kind] then out[#out + 1] = card end
    end
    return out
end

-- The items worth keeping a daily price for: every reagent and every output of
-- everything the player can make, plus whatever is in their bags.
--
-- И МАТЕРИАЛЫ ВПЕРЁД. Историю цен задним числом не собрать: если начать
-- записывать цену на рунную ткань в тот день, когда потолок портняжки
-- поднимется, сравнивать её будет не с чем ещё неделю. Поэтому в слепок идут и
-- реагенты НЕВЫУЧЕННЫХ рецептов - те самые 630 из 900, которые клиент уже
-- показал. Стоит это один лишний запрос цены на предмет в сутки.
function Engine:TrackedItems()
    local set = {}
    for _, recipe in ipairs(ns.RecipeBook:Iterate(function(r) return r.learned end)) do
        if recipe.output then set[recipe.output] = true end
        for _, r in ipairs(recipe.reagents or {}) do set[r.itemID] = true end
    end
    local snap = ns.CharacterScanner:Get()
    for itemID in pairs((snap and snap.bags) or {}) do set[itemID] = true end
    local ahead = 0
    if ns.Foresight then
        for itemID in pairs(ns.Foresight:TrackItems() or {}) do
            if not set[itemID] then ahead = ahead + 1 end
            set[itemID] = true
        end
    end
    if ns.Diag then
        ns.Diag:Module("priceSnapshotScope", {
            ["in"] = U.count(set), out = U.count(set),
            aheadOnly = ahead,
            note = "в слепок включены материалы невыученных рецептов:"
                .. " историю цен задним числом не собрать",
        })
    end
    return set
end

return Engine
