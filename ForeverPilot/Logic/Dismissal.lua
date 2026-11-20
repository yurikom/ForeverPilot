-- ForeverPilot / Logic/Dismissal.lua
--
-- Hiding a card, and above all NOT hiding one by accident.
--
-- WHY THIS IS ITS OWN FILE. The logic used to live in UI/Card.lua, where the
-- test harness cannot reach it - the harness loads no frame code on purpose -
-- so the most destructive action in the addon was the one part with no tests on
-- it. It is not presentation: it decides what the player loses and how they get
-- it back, and it belongs with the rest of the decisions.
--
-- WHAT WENT WRONG, TWICE. A single right-click anywhere on a card hid it for a
-- day. The player did that unintentionally, ended up with an empty window, and
-- had no way to guess why. It was explained, the message was improved - and
-- then it happened again, and this time it hid the corrected gear advice that a
-- whole day of work existed to produce. They never saw it.
--
-- SO: two deliberate clicks and a named one-step undo. Every one of those is
-- testable from here. (Acknowledging an informational card used to put it aside
-- for an hour; it no longer hides anything - see UI/Card.lua.)
local ADDON, ns = ...

local U = ns.Util
local D = {}
ns.Dismissal = D

-- How long the first click stays "armed" waiting for the second.
D.CONFIRM_SECONDS = 5

D.armedKey = nil
D.armedAt = 0

function D:IsArmed(cardKey)
    if not cardKey or D.armedKey ~= cardKey then return false end
    local now = ns.Api:Now()
    return (now - (D.armedAt or 0)) <= D.CONFIRM_SECONDS
end

function D:Arm(cardKey)
    if not cardKey then return false end
    D.armedKey, D.armedAt = cardKey, ns.Api:Now()
    return true
end

function D:Disarm()
    local had = D.armedKey ~= nil
    D.armedKey, D.armedAt = nil, 0
    return had
end

-- The two-step request. Returns outcome, message where outcome is one of
--   "blocked" - this card may never be hidden; nothing changed
--   "armed"   - first click; the card is now waiting for a second
--   "hidden"  - second click within the window; the card is hidden
--   "failed"  - we could not record the dismissal (no usable clock)
function D:Request(card, seconds)
    if type(card) ~= "table" or not card.key then return "failed", nil end
    if card.blocking then
        return "blocked",
            "эту карточку не скрываю: без неё советы будут неполными"
    end
    if not D:IsArmed(card.key) then
        D:Arm(card.key)
        return "armed",
            "|cffffcc40скрыть «" .. U.truncate(card.title or card.key, 40)
            .. "»?|r Ещё один правый щелчок по ней — скрою."
            .. " Любое другое действие — оставлю как есть."
    end
    D:Disarm()
    return D:Hide(card, seconds)
end

-- Hide without the confirmation step. НИ ОДИН ЩЕЛЧОК ИГРОКА СЮДА БОЛЬШЕ НЕ
-- ВЕДЁТ НАПРЯМУЮ: всё, что прячет совет, идёт через D:Request выше, то есть
-- через два щелчка. Раньше одним движением прятали правый щелчок по панели,
-- «Дальше» и левый щелчок по информационному совету; все три убраны, и это
-- проверяется перечнем путей в Tests/test_text.lua. Функция остаётся вторым
-- шагом D:Request и точкой, через которую проходит любое скрытие.
function D:Hide(card, seconds)
    if type(card) ~= "table" or not card.key then return "failed", nil end
    if card.blocking then
        return "blocked",
            "эту карточку не скрываю: без неё советы будут неполными"
    end
    seconds = tonumber(seconds) or ns.DISMISS_SECONDS
    local now = ns.Api:ServerTime()
    if not ns.Config:Dismiss(card.key, now, seconds) then
        -- Only happens with no usable clock, and then the card is still there,
        -- so saying it was hidden would be a lie the player can see.
        return "failed", "не смог скрыть: игра не сказала мне текущее время"
    end
    ns.Config:RememberLastDismiss(card.key, card.title, now, seconds)
    if ns.Diag then ns.Diag:Count("cards.hiddenByPlayer") end
    return "hidden",
        "скрыл на " .. (U.durationText(seconds) or "время")
        .. ": «" .. tostring(card.title or card.key)
        .. "». |cff60c060Вернуть именно это — /fp undo|r,"
        .. " вернуть всё скрытое — /fp show"
end

-- Undo exactly the last hide. Returns entry, message.
function D:UndoLast()
    local entry = ns.Config:UndoLastDismiss()
    if not entry then
        return nil, "нечего возвращать: ничего не скрывалось в этот сеанс"
    end
    return entry, "вернул: «" .. tostring(entry.title or entry.key) .. "»"
end

-- Bring everything back. Returns count, message.
--
-- ОТВЕТ НАЗЫВАЕТ ТО ЖЕ ЧИСЛО, ЧТО И КАРТОЧКА. На карточке стоит «Скрытых
-- советов: 8» - это советы, которые скрытие прячет прямо сейчас. А в ответе на
-- её кнопку стояло число ЗАПИСЕЙ о скрытии, и оно бывает больше: запись о
-- совете, которого движок сейчас не строит, тоже запись. Игрок видел «8» и
-- тут же «вернул: 9». Теперь называется то, что он видел; а когда прятать было
-- нечего и стёрты только устаревшие записи - так и сказано.
function D:RestoreAll()
    local active = 0
    if ns.ActionEngine and ns.ActionEngine.HiddenSummary then
        active = tonumber((ns.ActionEngine:HiddenSummary())) or 0
    end
    local n = ns.Config:ClearDismissed()
    if n > 0 then
        if active > 0 then
            return n, "вернул скрытые советы: " .. active
        end
        return n, "скрытых советов на экране не было; стёр "
            .. n .. " " .. U.plural(n, "устаревшую запись", "устаревшие записи",
                "устаревших записей") .. " о скрытии"
    end
    return 0, "скрытых советов нет"
end

return D
