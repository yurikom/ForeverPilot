#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Мутационная проверка набора тестов ForeverPilot.

Зачем это нужно. Зелёный набор тестов сам по себе ничего не доказывает: он может
быть зелёным и на сломанном коде. Проверяется это так — в рабочий код вносится
ОДНА заведомая порча (мутация), набор прогоняется, и если он остаётся зелёным,
значит этот класс ошибок тесты структурно не ловят. Ровно такой провал и нашёл
независимый аудит 2026-11-17.

Как запускать (из папки аддона):
    python3 Tests/mutate.py            # все мутации
    python3 Tests/mutate.py 12 13      # только названные номера

Скрипт правит файлы на диске и ВСЕГДА возвращает их обратно, в том числе при
ошибке и при Ctrl-C. Прогоняется набор с реальными данными: он включает в себя
офлайновый (2027 = 1917 + проверки на живом WTF), поэтому одного прогона хватает.

Интерпретатор тестов: texluajit (LuajitTeX, Lua 5.1).
"""

import io
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SUITE = ["texluajit", "Tests/run.lua", "real"]

# (номер, что портим, файл, что ищем, на что меняем)
#
# Каждая мутация ломает ровно один содержательный контракт - тот, из-за которого
# пользователь уже терял деньги или материалы. Если мутация НЕ ПОЙМАНА, значит
# тест на этот контракт либо отсутствует, либо проверяет не то.
MUTATIONS = [
    (1, "цена партии выдаётся за цену штуки",
     "Core/Api.lua",
     "local unit = c / math.max(1, q or 1)",
     "local unit = c -- MUTANT"),

    (2, "свои же крафты считаются покупками",
     "Core/Api.lua",
     "        if e.m then",
     "        if false then -- MUTANT"),

    (3, "выброс в истории цен принимается за рынок",
     "Logic/MarketHistory.lua",
     "MH.OUTLIER_FACTOR_LONG = 3.0",
     "MH.OUTLIER_FACTOR_LONG = math.huge -- MUTANT"),

    (4, "семейство вещей различается по школе магии",
     "Logic/GearAdvisor.lua",
     "local function isSpellPowerStat(stat)\n    if ns.SCHOOL_BY_STAT[stat] then return true end",
     "local function isSpellPowerStat(stat)\n    if true then return false end -- MUTANT\n    if ns.SCHOOL_BY_STAT[stat] then return true end"),

    (5, "просадка главной характеристики не ветируется",
     "Logic/GearAdvisor.lua",
     "                if cmp and cmp.mainStatDrop then",
     "                if false and cmp and cmp.mainStatDrop then -- MUTANT"),

    (6, "лечение снова весит как польза для боевого профиля",
     "Data/StatWeights.lua",
     "        [S.HEALPOWER] = 0.00,",
     "        [S.HEALPOWER] = 0.10, -- MUTANT"),

    (7, "совет не по карману не понижается в ранге",
     "Logic/ActionEngine.lua",
     "Engine.OUT_OF_REACH_RATIO = 3",
     "Engine.OUT_OF_REACH_RATIO = math.huge -- MUTANT"),

    (8, "поток «пришли данные предмета» гонит пересчёты",
     "Core/Events.lua",
     "Events.ITEM_INFO_QUIET_SECONDS = 10",
     "Events.ITEM_INFO_QUIET_SECONDS = 0 -- MUTANT"),

    (9, "неполный ответ клиента больше не перепрашивается",
     "Logic/GearAdvisor.lua",
     "function Gear:RetryPending()\n    local n = 0",
     "function Gear:RetryPending()\n    if true then return 0 end -- MUTANT\n    local n = 0"),

    (11, "инструмент профессии считается боевой экипировкой",
     "Logic/GearAdvisor.lua",
     "    return self:ToolSubclasses()[sub] and true or false",
     "    return false -- MUTANT"),

    (12, "слот оценивается только по надетому",
     "Logic/GearAdvisor.lua",
     "    for _, e in ipairs(self:OwnedBySlot(snap)[slotKey] or {}) do",
     "    for _, e in ipairs({}) do -- MUTANT"),

    (13, "крафт сравнивается с надетым, а не с лучшим из имеющегося",
     "Logic/GearAdvisor.lua",
     "            if curScore ~= nil and floorScore and floorScore > curScore then\n                compareAgainst = floorScore\n            end",
     "            -- MUTANT"),

    (14, "рамка кнопки миникарты съезжает",
     "UI/MinimapButton.lua",
     "MB.BORDER_SIZE   = 53",
     "MB.BORDER_SIZE   = 52 -- MUTANT"),

    (15, "кнопка миникарты не ездит по кромке",
     "UI/MinimapButton.lua",
     "    return w * cos, h * sin",
     "    return 52, -4 -- MUTANT"),

    (16, "книга рецептов снова сбрасывает данные предметов",
     "Logic/RecipeBook.lua",
     "        ns.GearAdvisor:InvalidateRecipeSet(\"пересобрана книга рецептов\")",
     "        ns.GearAdvisor:InvalidateItemData(\"MUTANT\")"),

    (17, "цены аукциона спрашиваются по каждому поводу заново",
     "Core/Api.lua",
     "    local key = itemLink or itemID",
     "    local key = nil -- MUTANT"),

    (18, "отказ внешней базы не запоминается",
     "Core/Api.lua",
     "    local missed = Api.foreignMissCache[itemID]",
     "    local missed = nil -- MUTANT"),

    (19, "чары снова читают только надетое",
     "Logic/EnchantAdvisor.lua",
     "    for _, slotKey in ipairs(Gear:SlotsToCheck()) do",
     "    for _, slotKey in ipairs({}) do -- MUTANT"),

    (20, "возраст цены не называется",
     "Logic/CraftingPlanner.lua",
     "    if age and age > (ns.PRICE_AGE_SAY_SECONDS or 86400) then",
     "    if false then -- MUTANT"),

    (10, "данные предмета читаются заново каждый пересчёт",
     "Logic/GearAdvisor.lua",
     "    if self.statsCache then\n        local c = self.statsCache[cacheKey]",
     "    if false then -- MUTANT\n        local c = self.statsCache[cacheKey]"),

    # --- Второй и третий этапы -------------------------------------------
    #
    # Те же правила: одна порча = один содержательный контракт, и каждый из
    # них либо уже стоил игроку денег, либо стоил бы.

    (21, "карточка с противоречивыми числами не помечается",
     "Logic/Risk.lua",
     "if ratio < Risk.VENDOR_RATIO_LIMIT then return nil end",
     "if true then return nil end -- MUTANT"),

    (22, "максимальный убыток считается без пола торговца",
     "Logic/Risk.lua",
     "maxLoss = math.max(0, capital - vendorFloor)",
     "maxLoss = capital -- MUTANT"),

    (23, "полярность чужой цены торговца не проверяется",
     "Logic/VendorArbitrage.lua",
     "local ok, why = VA:AskPolarityOK(itemID, foreign)",
     "local ok, why = true, nil -- MUTANT"),

    (24, "спецвалюта у торговца считается нулём",
     "Logic/VendorArbitrage.lua",
     "                noPrice = true",
     "                best, bestNpc = 0, src.npc -- MUTANT"),

    (25, "перекупка советуется без своей истории цен",
     "Logic/Resale.lua",
     'if st.days < RS.MIN_HISTORY_DAYS then return nil, "history-too-short" end',
     "-- MUTANT"),

    (26, "перекупка не смотрит на ликвидность",
     "Logic/Resale.lua",
     'if not liq.liquid then return nil, "illiquid" end',
     "-- MUTANT"),

    (27, "ожидание от распыла выдаётся за измеренную цену",
     "Logic/Disenchant.lua",
     "local conf = U.worstConf(worstConf, CONF.ESTIMATE)",
     "local conf = worstConf -- MUTANT"),

    (28, "материалы впереди не попадают в слепки цен",
     "Logic/Foresight.lua",
     "for _, itemID in ipairs(ns.Horizon:WatchList()) do set[itemID] = true end",
     "-- MUTANT"),

    (29, "холостой пересчёт отключён — список замерзает",
     "Core/Events.lua",
     "if (now - base) >= Events.IDLE_SECONDS then",
     "if false then -- MUTANT"),

    (30, "возраст цены снова считается секундами вместо дней",
     "Core/Api.lua",
     "            age = a * 86400",
     "            age = a -- MUTANT"),

    (31, "профиль перестаёт менять состав списка",
     "Logic/ActionEngine.lua",
     "if exclude and next(exclude) then",
     "if false then -- MUTANT"),

    (32, "за Благосклонность советуется то, что уже есть",
     "Logic/ActionEngine.lua",
     "            if d.alreadyHave then",
     "            if false then -- MUTANT"),

    (33, "Благосклонность гейтится уровнем вместо навыка",
     "Logic/Favor.lua",
     "and (skill >= entry.skill) or nil",
     "and (skill >= entry.skill and (tonumber(snap and snap.level) or 0) >= 35) or nil -- MUTANT"),

    # Первая версия этой мутации была написана неверно - «elsewhere + 0» ничего
    # не меняло, и она «не ловилась» по собственной вине, а не из-за дырки в
    # тестах. Теперь она ломает именно тот контракт, который нужен: деньги альта
    # нельзя выдавать за деньги в кошельке, их надо переслать.
    (34, "золото альта выдаётся за деньги в кошельке",
     "Logic/CrossCharacter.lua",
     "                elsewhere = elsewhere + c.money",
     "                here = here + c.money -- MUTANT"),

    # --- 35-45: контракты, из-за которых игрок 17 ноября видел сломанный аддон.
    #
    # Каждый из них уже был нарушен в настоящем коде: аддон не загружался,
    # вкладки накладывались, советы пропадали от кнопки «Дальше», текст обещал
    # кнопку, которой нет. Мутация возвращает ровно ту порчу, что была.

    (35, "«Дальше» снова прячет совет",
     "UI/StepPanel.lua",
     "    local nextIndex = (index % #list) + 1",
     "    local nextIndex = (index % #list) + 1; "
     "ns.Config:Dismiss(list[index].key, ns.Api:ServerTime(), ns.SNOOZE_SECONDS) -- MUTANT"),

    # Card.Dismiss - скрытие в один шаг - из интерфейса убрана, поэтому мутант
    # зовёт то, что осталось: Dismissal:Hide. Его ловят сразу два набора - щелчки
    # по всему (test_vanish, test_text) и перечень мест, которым разрешено
    # звать скрытие (test_vanish).
    (36, "левый щелчок по информационному совету снова его прячет",
     "UI/Card.lua",
     "    -- Правило проверяется тестом на всех советах списка сразу.\nend",
     "    ns.Dismissal:Hide(card, ns.SNOOZE_SECONDS) -- MUTANT\nend"),

    # Эту мутацию loadfile под texluajit НЕ видит - в том и состоял провал:
    # LuaJIT принимает goto, клиент игры (Lua 5.1) нет. Ловить её обязана
    # проверка диалекта в Tests/test_load.lua.
    (37, "в код вернулся синтаксис, которого нет в Lua 5.1 (goto)",
     "Logic/ActionEngine.lua",
     "            nameless = nameless + 1\n        else",
     "            nameless = nameless + 1 goto fp_mutant ::fp_mutant:: -- MUTANT\n        else"),

    (38, "при переключении вкладки прежняя не прячется",
     "UI/MainFrame.lua",
     "        if mod and mod.frame then mod.frame:Hide() end",
     "        if false and mod then mod.frame:Hide() end -- MUTANT"),

    # Кнопка теперь настоящая, но есть она только при открытом аукционе. Мутант
    # возвращает прежнее обещание в состояние, где кнопки на экране нет.
    (39, "текст снова обещает кнопку, которой нет («Искать на аукционе»)",
     "Logic/ShoppingList.lua",
     '        info.note = "Когда откроете аукцион, здесь появится кнопка: она передаст"',
     '        info.note = "Открой аукцион и нажми «Искать на аукционе»: она передаст" -- MUTANT'),

    (40, "в подпись кнопки вернулся значок, которого нет в шрифте клиента",
     "Core/Const.lua",
     '    CLOSE      = "X",',
     '    CLOSE      = "\\226\\156\\149", -- MUTANT'),

    (41, "о непрочитанном файле аддон молчит и запускается как ни в чём не бывало",
     "Main.lua",
     "    if #missing > 0 then\n        Main.halted = true",
     "    if false then -- MUTANT\n        Main.halted = true"),

    (42, "расхождение с чужим кешем понижает доверие к данным клиента",
     "Logic/SourceCheck.lua",
     "                row.cache = {",
     "                row.conf = ns.CONF.ESTIMATE -- MUTANT\n                row.cache = {"),

    (43, "расхождение клиента с кешем Mastercraft не записывается",
     "Logic/SourceCheck.lua",
     "            if differs then\n                cacheDisagreements = cacheDisagreements + 1",
     "            if false then -- MUTANT\n                cacheDisagreements = cacheDisagreements + 1"),

    (44, "история навыка Mastercraft снова читается как пара «навык, максимум»",
     "Core/Api.lua",
     "            out[#out + 1] = row(name, pair.last or pair.first, nil)",
     "            out[#out + 1] = row(name, pair.first, pair.last) -- MUTANT"),

    (45, "«Дальше» пропала у советов со своим действием",
     "UI/StepPanel.lua",
     "    if index and #list > 1 then",
     "    if index and #list > 1 and not Panel.HasOwnAction(card) then -- MUTANT"),

    # --- 46-56: пути, которыми совет пропадает с глаз, и кнопка передачи списка.

    (46, "правый щелчок по панели снова прячет совет с одного раза",
     "UI/StepPanel.lua",
     "    local _, outcome = ns.Card.RequestDismiss(card, ns.SNOOZE_SECONDS)",
     "    local outcome = ns.Dismissal:Hide(card, ns.SNOOZE_SECONDS) -- MUTANT"),

    # Самый первый из всех случаев: один правый щелчок по совету в списке.
    (47, "правый щелчок по совету в списке прячет его с первого раза",
     "Logic/Dismissal.lua",
     "    if not D:IsArmed(card.key) then",
     "    if false then -- MUTANT"),

    (48, "вопрос «скрыть?» не снимается другим действием на панели",
     "UI/StepPanel.lua",
     "            ns.Card.Disarm()\n            -- Clicking the panel opens the full window",
     "            -- MUTANT\n            -- Clicking the panel opens the full window"),

    (49, "фильтр над списком прячет советы молча",
     "UI/TabNow.lua",
     "    if chip and chip ~= ns.CHIP.ALL and shown > 0 and shown < total then",
     "    if false then -- MUTANT"),

    (50, "профиль убирает советы молча",
     "UI/TabNow.lua",
     "    if dropped > 0 then\n        local names = {}",
     "    if false then -- MUTANT\n        local names = {}"),

    (51, "список обрезан по длине молча",
     "UI/TabNow.lua",
     "    if generated > total and total > 0 then",
     "    if false then -- MUTANT"),

    (52, "кнопка «Искать на аукционе» рисуется и без Auctionator",
     "UI/TabCraft.lua",
     '    if handoff.state == "ready" and button then',
     "    if button then -- MUTANT"),

    (53, "кнопка «Искать на аукционе» есть при закрытом аукционе",
     "Logic/ShoppingList.lua",
     "    if not Api:AuctionHouseOpen() then\n        -- ИГРА ГОВОРИТ",
     "    if false then -- MUTANT\n        -- ИГРА ГОВОРИТ"),

    (54, "после отказа Auctionator кнопка остаётся на месте",
     "Logic/ShoppingList.lua",
     "    Shopping.handoffBroken = { reason = route, error = detail }",
     "    Shopping.handoffBroken = nil -- MUTANT"),

    (55, "ошибка Auctionator выходит наружу, а не ловится",
     "Core/Api.lua",
     "    local ok, err = pcall(fn, AUCTIONATOR_CALLER, terms)",
     "    local ok, err = true, fn(AUCTIONATOR_CALLER, terms) -- MUTANT"),

    (56, "вкладка «Крафт» не перерисовывается по пересчёту",
     "UI/TabCraft.lua",
     "function Tab:OnShow()\n    Tab:Render()\nend",
     "function Tab:OnShow()\n    Tab:RenderList(); Tab:RenderPlan()\nend\nTab.Render = nil -- MUTANT"),

    # Показ рецепта: клиент нельзя звать, пока игра сама не загрузила окно
    # профессий. Защита стоит в трёх местах, и каждое портится отдельно.
    (57, "щелчок по совету зовёт клиент при незагруженном окне профессий",
     "Logic/RecipeBook.lua",
     "    if info.state ~= \"ready\" then return false, info.note, info.state end\n\n    local ok, reason, detail = Api:ShowRecipe(recipeID)",
     "    -- MUTANT: проверка состояния убрана\n\n    local ok, reason, detail = Api:ShowRecipe(recipeID)"),

    (58, "кнопка «Показать рецепт» рисуется при незагруженном окне профессий",
     "UI/Card.lua",
     "    if act.kind == \"openRecipe\" then return ns.RecipeBook:CanShow() end\n    return true",
     "    -- MUTANT: показ рецепта считается доступным всегда\n    return true"),

    (59, "адаптер зовёт клиент, не спросив, загружено ли окно профессий",
     "Core/Api.lua",
     "    if not loaded then return false, \"not-loaded\" end\n    local ok, err = pcall(F.openRecipe, recipeID)",
     "    -- MUTANT: «не загружено» больше не отказ\n    local ok, err = pcall(F.openRecipe, recipeID)"),

    (60, "«не знаю, загружено ли окно» принимается за «загружено»",
     "Core/Api.lua",
     "    if type(ask) ~= \"function\" then return nil end\n    -- Новый клиент отвечает двумя значениями",
     "    if type(ask) ~= \"function\" then return true end -- MUTANT\n    -- Новый клиент отвечает двумя значениями"),

    (61, "после отказа клиента кнопка показа рецепта остаётся на месте",
     "Logic/RecipeBook.lua",
     "        RecipeBook.showBroken = { recipeID = recipeID, error = detail }",
     "        RecipeBook.showBroken = nil -- MUTANT"),

    (62, "кнопка рецепта не появляется, когда игра догрузила окно профессий",
     "Main.lua",
     "    if event == \"ADDON_LOADED\" and arg1 == \"Blizzard_Professions\" then\n        Main:OnProfessionsUI()\n        return\n    end",
     "    if event == \"ADDON_LOADED\" and arg1 == \"Blizzard_Professions\" then\n        return -- MUTANT\n    end"),

    (63, "панель предлагает показать рецепт, когда показать его нельзя",
     "UI/StepPanel.lua",
     "    return ns.Card.ActionReady(card) and true or false",
     "    return true -- MUTANT"),

    (64, "у совета без кнопки нет объяснения над списком",
     "UI/TabNow.lua",
     "        local note = ns.Card.ActionNote(card)\n        if note and not said[note] then",
     "        local note = nil -- MUTANT\n        if note and not said[note] then"),

    (65, "текст обещает кнопку рецепта там, где она не появится никогда",
     "Logic/RecipeBook.lua",
     "        info.note = \"Я не могу узнать, открывалось ли уже окно профессий, а\"\n            .. \" открывать его первым не берусь — найдите рецепт там по названию.\"",
     "        info.note = \"Откройте окно профессий — и кнопка показа рецепта появится.\" -- MUTANT"),

    # Необратимое - не одним нажатием: свой список покупок стирается в два шага.
    (66, "список покупок стирается с первого нажатия",
     "Logic/ShoppingList.lua",
     "    if not self:ClearArmed() then\n        Shopping.clearArmedAt = Api:Now()",
     "    if false then -- MUTANT\n        Shopping.clearArmedAt = Api:Now()"),

    (67, "вопрос «очистить список?» не истекает никогда",
     "Logic/ShoppingList.lua",
     "    return (Api:Now() - at) <= Shopping.CLEAR_CONFIRM_SECONDS",
     "    return true -- MUTANT"),

    (68, "кнопка в настройках стирает список сама, в обход вопроса",
     "UI/TabSettings.lua",
     "        local outcome, message = ns.ShoppingList:RequestClear()",
     "        ns.Config:ClearShopping() -- MUTANT\n        local outcome, message = \"cleared\", nil"),

    (69, "кнопка очистки не меняет подпись на время вопроса",
     "UI/TabSettings.lua",
     "    button(clearArmed and \"Точно очистить — нажмите ещё раз\"\n        or \"Очистить мой список покупок\", function()",
     "    button(\"Очистить мой список покупок\", function() -- MUTANT"),

    # --- Проверка на чушь (Tests/test_sense.lua, Tests/test_nonsense.lua) ---
    (70, "число раз не согласовано со словом: «в 3 раз», «в 22 раз»",
     "Core/Util.lua",
     "        return whole .. \" \" .. U.plural(whole, \"раз\", \"раза\", \"раз\")",
     "        return whole .. \" раз\" -- MUTANT"),
    (71, "при нуле денег снова «в 600 раз больше, чем у вас есть (0м)»",
     "Logic/ActionEngine.lua",
     "    if (tonumber(money) or 0) <= 0 then\n        return \"Денег у вас сейчас нет вовсе",
     "    if false then -- MUTANT\n        return \"Денег у вас сейчас нет вовсе"),
    (72, "покупка закреплённого руками не названа закреплённой",
     "Logic/ActionEngine.lua",
     "            if pin > 0 or pinnedByHand then\n",
     "            if false then -- MUTANT\n"),
    (73, "«В список покупок» отвечает «добавил», ничего не добавив",
     "UI/Card.lua",
     "        if had >= qty then\n",
     "        if false then -- MUTANT\n"),
    (74, "команда «/fp сила» из справки не узнаётся и отвечает справкой",
     "Main.lua",
     "            if msg == key:lower() or msg == U.lower(ns.PROFILE_LABEL[key] or \"\") then",
     "            if msg == key:lower() or msg == (ns.PROFILE_LABEL[key] or \"\"):lower() then -- MUTANT"),
    (75, "на карточке «Скрытых советов: 8», а в ответе на кнопку — 9",
     "Logic/Dismissal.lua",
     "            return n, \"вернул скрытые советы: \" .. active",
     "            return n, \"вернул скрытые советы: \" .. n -- MUTANT"),
    (76, "игрок скрыл все советы — диагностика пишет «никто ничего не выдал»",
     "Logic/SanityChecks.lua",
     "    if total == 0 and (tonumber(ctx.hidden) or 0) == 0 then",
     "    if total == 0 then -- MUTANT"),
    (77, "повтор сообщения не печатается никогда — кнопка становится мёртвой",
     "Core/Api.lua",
     "        if since >= 0 and since < Api.REPEAT_QUIET_SECONDS then",
     "        if true then -- MUTANT"),
    (78, "одно и то же сообщение печатается подряд сколько угодно раз",
     "Core/Api.lua",
     "        if since >= 0 and since < Api.REPEAT_QUIET_SECONDS then",
     "        if false then -- MUTANT"),
    (79, "в тексте о цене снова крик заглавными",
     "Logic/MarketHistory.lua",
     "                or \"сейчас %s — это ниже всего, что я видел (%s). %s\",",
     "                or \"сейчас %s — это НИЖЕ всего, что я видел (%s). %s\", -- MUTANT"),
    (80, "ответ на /fp diag снова перечисляет имена функций игры",
     "Core/Diag.lua",
     "                lacking[#lacking + 1] = group.group .. \" — частично\"",
     "                lacking[#lacking + 1] = group.group .. \" — нет: \" .. table.concat(group.missing, \", \") -- MUTANT"),
    (81, "настройки снова показывают внутренние имена вместо слов",
     "UI/TabSettings.lua",
     "            text = \"|cffffcc40частично|r — не хватает \" .. #group.missing .. \" из \"\n                .. (#group.missing + #group.ok)",
     "            text = \"|cffffcc40частично|r — нет: \" .. table.concat(group.missing, \", \") -- MUTANT"),
    (82, "«сейчас ниже всего, что я видел» и следом «цена выросла»",
     "Logic/ActionEngine.lua",
     "    if best.trend and best.trend.direction ~= \"flat\" and not trendClashes then",
     "    if best.trend and best.trend.direction ~= \"flat\" then -- MUTANT"),
    (83, "«ни одного лота среди 0 предметов»",
     "Logic/Resale.lua",
     "        and ((#ids == 0)\n",
     "        and ((false) -- MUTANT\n"),
    (84, "совет «навык неизвестен» снова обещает не считать прирост рядом с советом «На навык»",
     "Logic/ActionEngine.lua",
     "                    .. \" сколько осталось до максимума, сказать не могу.\",",
     "                    .. \" и не считаю прирост навыка для этой профессии.\", -- MUTANT"),
    (85, "«N ед. пользы за золотой» у вещи дешевле золотого",
     "Logic/ActionEngine.lua",
     "        elseif up.gainPerGold and plan and plan.cost and plan.cost >= 10000 then",
     "        elseif up.gainPerGold and plan and plan.cost and plan.cost > 0 then -- MUTANT"),
    (86, "один путь и дешевле, и быстрее — а приписано «Выбирать вам»",
     "Logic/ActionEngine.lua",
     "                        and \"Делаете вы сами — я ничего не делаю за вас.\"",
     "                        and \"Выбирать вам — я не выбираю за вас и ничего не делаю сам.\" -- MUTANT"),
    (87, "«В список не поместилось 1 совет»",
     "UI/TabNow.lua",
     "            .. U.plural(over, \"не поместился\", \"не поместились\", \"не поместилось\")",
     "            .. \"не поместилось\" -- MUTANT"),
    (88, "в совете про Благосклонность снова слово «гейтятся»",
     "Logic/Favor.lua",
     "    return \"Рецепты за Благосклонность торговца открываются по навыку\"",
     "    return \"Рецепты за Благосклонность торговца гейтятся по навыку\" -- MUTANT"),
    (89, "в подсказке совета снова «Материалы: 0м»",
     "UI/Card.lua",
     "        if plan.cost == 0 then\n",
     "        if false then -- MUTANT\n"),
    (90, "у совета «На навык» снова «(0м за крафт)»",
     "Logic/ActionEngine.lua",
     "                            .. ((best.cost and best.cost > 0)",
     "                            .. ((best.cost and best.cost >= 0) -- MUTANT"),
    (91, "крик заглавными в строке, которой в тестовых мирах никто не говорит",
     "Core/Diag.lua",
     "        add(\"Ошибка в %s: %s\", tostring(s.errors[i].where),",
     "        add(\"ОШИБКА в %s: %s\", tostring(s.errors[i].where), -- MUTANT"),
    (92, "аддон говорит о себе в женском роде",
     "UI/TabSettings.lua",
     "    note(\"Пустой выбор = определяю сам по классу и специализации.\"",
     "    note(\"Пустой выбор = определяю сама по классу и специализации.\" -- MUTANT\n"),
    (93, "вторая фраза приписывается к первой без точки",
     "Logic/ActionEngine.lua",
     "    if last ~= \".\" and last ~= \"!\" and last ~= \"?\" then text = text .. \".\" end",
     "    -- MUTANT: точка не ставится"),
    (94, "оговорка о выборке снова с маленькой буквы после точки",
     "Logic/MarketHistory.lua",
     "    local sample = U.capitalize(sampleText(st.days))",
     "    local sample = sampleText(st.days) -- MUTANT"),
    (95, "в подсказке совета его место в списке названо неверно",
     "UI/Card.lua",
     "        table.insert(extra, \"Место в общем списке: \" .. position .. \" из \" .. total",
     "        table.insert(extra, \"Место в общем списке: \" .. (position + 1) .. \" из \" .. total -- MUTANT\n"),

    # --- Порог мелкой денежной выгоды и вода (эта сессия) ---
    (96, "порог мелкой выгоды ничего не отсеивает",
     "Logic/ActionEngine.lua",
     "        local gain = Engine.MoneyGainOf(card)\n        if gain and gain < floor then",
     "        local gain = Engine.MoneyGainOf(card)\n        if false then -- MUTANT"),
    (97, "порог отсеивает молча, без строки над списком",
     "Logic/ActionEngine.lua",
     "    local note = Engine.MoneyFloorText(floor, dropped, byKind, biggest, band, orphans)",
     "    local note = nil -- MUTANT"),
    (98, "порог по уровню больше не растёт с уровнем",
     "Core/Const.lua",
     "    { upTo = 15,    copper = 1000, label = \"1-15 ур.\" },",
     "    { upTo = 15,    copper = 3000, label = \"1-15 ур.\" }, -- MUTANT"),
    (99, "покупка остаётся под совет, который убрал порог",
     "Logic/ActionEngine.lua",
     "                if total > 0 and #live == 0 then",
     "                if false then -- MUTANT"),
    (100, "список покупок снова собирает материалы под убранные советы",
     "Logic/ActionEngine.lua",
     "            if gain and floorNow > 0 and gain < floorNow then",
     "            if false then -- MUTANT"),
    (101, "общее объяснение снова печатается в каждой карточке настройки",
     "Logic/ActionEngine.lua",
     "                aboveList = Engine.SETUP_NOTE_RECIPES,",
     "                why = Engine.SETUP_NOTE_RECIPES, -- MUTANT"),
    (102, "адрес источника снова на карточке, а не в подсказке",
     "Logic/Favor.lua",
     "        .. \" сообщества, в игре я этого не проверял.\"",
     "        .. \" сообщества (\" .. tostring((ns.Horizon or {}).PROVENANCE and ns.Horizon.PROVENANCE.mfCrates or \"?\") .. \"), в игре я этого не проверял.\" -- MUTANT"),
    (103, "прирост навыка снова числом без единицы",
     "Logic/ActionEngine.lua",
     "                        benefit = (best.chance >= 1 and \"+1 пункт навыка почти наверняка\")",
     "                        benefit = (best.chance >= 1 and \"почти верный +1\") -- MUTANT"),
    (104, "про пустые записи снова сказано, что они не устаревают",
     "Logic/Provenance.lua",
     "        fresh = (((tonumber(places.npcs) or 0) > 0)",
     "        fresh = ((true) -- MUTANT"),
]


# Прерванный прогон (таймаут, Ctrl-C, падение) не должен оставить порчу в
# рабочем коде: пользователь перезагружает интерфейс в любой момент. Поэтому
# перед каждой мутацией оригинал кладётся рядом, а при следующем запуске
# восстанавливается, если остался.
STASH = os.path.join(ROOT, "Tests", ".mutate_stash.txt")
STASH_SEP = "\n--[[ ===== ORIGINAL ===== ]]\n"


def restore_stash():
    if not os.path.exists(STASH):
        return
    with io.open(STASH, encoding="utf-8") as f:
        blob = f.read()
    if STASH_SEP not in blob:
        return
    rel, text = blob.split(STASH_SEP, 1)
    rel = rel.strip()
    if rel:
        with io.open(os.path.join(ROOT, rel), "w", encoding="utf-8") as f:
            f.write(text)
        print("Восстановлено после прерванного прогона: " + rel)
    clear_stash()


def stash(path, text):
    # Удалять файлы в этой папке не разрешено, поэтому «пусто» - это пустой
    # файл, а не отсутствующий.
    with io.open(STASH, "w", encoding="utf-8") as f:
        f.write(path + STASH_SEP + text)


def clear_stash():
    with io.open(STASH, "w", encoding="utf-8") as f:
        f.write("")


def read(path):
    with io.open(os.path.join(ROOT, path), encoding="utf-8") as f:
        return f.read()


def write(path, text):
    with io.open(os.path.join(ROOT, path), "w", encoding="utf-8") as f:
        f.write(text)


def suite_is_green(line):
    """Зелёный ли набор, судя по строке итога.

    ЧИСЛО ПРОВАЛОВ РАЗБИРАЕТСЯ, А НЕ ИЩЕТСЯ ПОДСТРОКОЙ. Раньше здесь стояло
    «"0 провалено" in line», и строка «4625 пройдено, 10 провалено» считалась
    зелёной: в «10 провалено» есть «0 провалено». Любое число провалов,
    кончающееся на ноль - 10, 20, 100, - читалось как ноль. Мутация, пойманная
    десятью проверками, объявлялась «не пойманной», а что хуже - набор с десятью
    провалами ДО мутаций сошёл бы за исправный, и весь прогон шёл бы по
    сломанному коду. Найдено на мутации 40: её ловят ровно десять проверок.
    """
    m = re.search(r"(\d+)\s+провалено", line)
    return bool(m) and int(m.group(1)) == 0


def run_suite():
    """Возвращает (ok, строка итога)."""
    p = subprocess.run(SUITE, cwd=ROOT, stdout=subprocess.PIPE,
                       stderr=subprocess.STDOUT)
    out = p.stdout.decode("utf-8", "replace")
    line = ""
    for l in out.splitlines():
        if l.startswith("Итого"):
            line = l.strip()
    if not line:
        line = "набор не доработал до итога (" + out.strip().splitlines()[-1][:80] + ")"
        return False, line
    return suite_is_green(line), line


def main():
    restore_stash()
    want = set(int(a) for a in sys.argv[1:] if a.isdigit())
    todo = [m for m in MUTATIONS if not want or m[0] in want]

    ok, line = run_suite()
    print("Исходный код: " + line)
    if not ok:
        print("!! набор не зелёный ДО мутаций - мутационная проверка "
              "бессмысленна, сначала починить")
        return 2

    caught, missed = [], []
    for num, what, path, old, new in todo:
        src = read(path)
        if old not in src:
            print("M%-2d %-52s ОПОРА СЪЕХАЛА (%s)" % (num, what, path))
            missed.append((num, what, "мутацию не удалось применить"))
            continue
        stash(path, src)
        write(path, src.replace(old, new, 1))
        try:
            good, line = run_suite()
        finally:
            write(path, src)
            clear_stash()
        if good:
            print("M%-2d %-52s НЕ ПОЙМАНА   %s" % (num, what, line))
            missed.append((num, what, line))
        else:
            print("M%-2d %-52s поймана      %s" % (num, what, line))
            caught.append(num)

    print("")
    print("Поймано %d из %d." % (len(caught), len(todo)))
    for num, what, line in missed:
        print("  НЕ ПОЙМАНА M%d: %s - %s" % (num, what, line))

    ok, line = run_suite()
    print("Код после прогона: " + line)
    return 0 if (not missed and ok) else 1


if __name__ == "__main__":
    sys.exit(main())
