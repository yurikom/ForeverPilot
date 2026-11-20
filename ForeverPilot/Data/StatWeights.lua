-- ForeverPilot / Data/StatWeights.lua
--
-- Stat weights, expressed relative to 1 point of the class's primary stat.
-- These are judgement calls, not game data, so they are all in one table the
-- player can override, and every number a weight produces is labelled as our
-- own estimate rather than a fact from the client.
--
-- The first version is tuned for an arcane mage in the low-to-mid levels:
-- intellect carries the kit (mana pool and spell power scale off it at this
-- level), stamina keeps you alive while you solo, spirit matters only while
-- drinking, and melee stats are worth nothing at all.
local ADDON, ns = ...

local U = ns.Util
local SW = {}
ns.StatWeights = SW

local S = ns.STAT

-- The client's stat keys (what GetItemStats returns, and what we parse out of
-- tooltips) mapped onto our canonical keys.
SW.CLIENT_KEY_TO_STAT = {
    ITEM_MOD_INTELLECT_SHORT            = S.INT,
    ITEM_MOD_SPIRIT_SHORT               = S.SPI,
    ITEM_MOD_STAMINA_SHORT              = S.STA,
    ITEM_MOD_STRENGTH_SHORT             = S.STR,
    ITEM_MOD_AGILITY_SHORT              = S.AGI,
    -- ITEM_MOD_SPELL_POWER_SHORT is deliberately NOT here. See
    -- SW.COMBINED_SPELL_POWER below: it is one bonus written as one number and
    -- it has to land in TWO stats, which a one-to-one map cannot express.
    ITEM_MOD_SPELL_DAMAGE_DONE_SHORT    = S.SPELLDMG,
    ITEM_MOD_SPELL_HEALING_DONE_SHORT   = S.HEALPOWER,
    ITEM_MOD_CRIT_SPELL_RATING_SHORT    = S.SPELLCRIT,
    ITEM_MOD_HIT_SPELL_RATING_SHORT     = S.SPELLHIT,
    ITEM_MOD_HASTE_SPELL_RATING_SHORT   = S.SPELLHASTE,
    ITEM_MOD_CRIT_RATING_SHORT          = S.CRIT,
    ITEM_MOD_HIT_RATING_SHORT           = S.HIT,
    ITEM_MOD_HASTE_RATING_SHORT         = S.HASTE,
    ITEM_MOD_EXPERTISE_RATING_SHORT     = S.EXPERTISE,
    ITEM_MOD_ATTACK_POWER_SHORT         = S.ATTACKPOWER,
    ITEM_MOD_POWER_REGEN0_SHORT         = S.MP5,
    ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = S.DEFENSE,
    ITEM_MOD_DODGE_RATING_SHORT         = S.DODGE,
    ITEM_MOD_PARRY_RATING_SHORT         = S.PARRY,
    ITEM_MOD_BLOCK_RATING_SHORT         = S.BLOCK,
    ITEM_MOD_HEALTH_SHORT               = S.HEALTH,
    ITEM_MOD_MANA_SHORT                 = S.MANA,
    ITEM_MOD_ARMOR                      = S.ARMOR,
    RESISTANCE0_NAME                    = S.ARMOR,
    RESISTANCE6_NAME                    = S.RESIST_ARCANE,
    RESISTANCE2_NAME                    = S.RESIST_FIRE,
    RESISTANCE4_NAME                    = S.RESIST_FROST,
    RESISTANCE3_NAME                    = S.RESIST_NATURE,
    RESISTANCE5_NAME                    = S.RESIST_SHADOW,
}

-- WHAT A ZERO MEANS HERE, AND WHY THERE ARE SO MANY NOW
--
-- A weight above zero says "a point of this makes the character better at what
-- the profile is for". It is not a tiebreaker and it is not politeness. A small
-- non-zero weight on a stat the character cannot use is strictly worse than a
-- zero, because it lets a pile of useless stats outvote a real one - and that
-- is not hypothetical. Healing carried 0.10 for a DPS caster, an item with
-- "+22 healing" collected 2.2 points for a stat an arcane mage cannot use, and
-- those points went into the gain that persuaded the player to craft a
-- downgrade. The same went for agility (0.05), dodge, defense, and five
-- resistances at 0.05 each: a hypothetical item with +20 of every resistance
-- would have scored 5 points of "power" while doing nothing for his damage.
--
-- So: a combat profile weights ONLY what makes it better at combat. Survival
-- stats keep a weight where survival is the profile's job (TANK), and healing
-- keeps its weight where healing is the job (CASTER_HEAL). Everywhere else the
-- answer is zero, and the gear advice says "equal" rather than inventing a
-- preference it cannot defend.

-- THE SCHOOL WEIGHTS, AND WHERE THEY COME FROM
--
-- Three facts drive them, and none of them is a guess:
--
--   1. A point of school-specific damage is worth about as much as a point of
--      generic spell damage ON THE SPELLS OF THAT SCHOOL. Generic is worth
--      slightly MORE overall, because it also helps the off-school spells the
--      character casts (an arcane mage still throws Fire Blast). So the own
--      school sits just under generic rather than above it.
--
--   2. The school items nevertheless win, and that is itemisation, not weights:
--      a generic item spends part of its budget on healing, which a DPS caster
--      cannot use, so the school version carries a bigger number for the same
--      item level. The player's own family proves it - Pristine gives sp8 plus
--      heal22, Pearly gives spArcane14 for the same stamina, armour and ilvl.
--      Correct weights make that come out right on their own.
--
--   3. An off-spec school of the same class keeps a real but much smaller
--      weight; a school the class cannot cast at all is zero. A mage of any
--      spec casts some fire and some frost, so those are worth something to
--      him; shadow and holy are worth nothing to him at any spec.
--
-- The ORDERING above is not only our judgement: an independent gear-advice
-- addon shipped on this same realm reaches the same ordering from its own
-- simulation data - own school and generic spell power at the top and level
-- with each other, the other two schools of the class at roughly a third to
-- two thirds of that, and the schools the class cannot cast absent from its
-- table entirely. Our numbers are our own, rounded to a scale a human can read
-- against a primary stat of 1.0; the shape is corroborated.
local SP_FULL      = 1.60   -- generic spell damage, the reference point
local SP_OWN       = 1.50   -- the school this spec actually casts
local SP_OFF_CLASS = 0.40   -- another school of the same class, cast sometimes
local SP_NONE      = 0.00   -- a school this class cannot cast

-- WHEN WE DO NOT KNOW THE SCHOOL. The school-neutral set cannot just hand every
-- school the off-school weight: that says "generic spell damage is four times
-- better per point than school damage", which is the exact shape of the bug
-- being fixed - it undervalues the school gear the player is already wearing.
--
-- The honest number is the expectation. A caster casts one school; an item
-- gives one school. With three plausible schools for the class, a random school
-- bonus is worth
--     1/3 * SP_OWN + 2/3 * SP_OFF_CLASS = 1/3*1.50 + 2/3*0.40 = 0.77
-- so 0.80 rounded. It is deliberately a weak answer, which is why the addon
-- works hard not to need it: see SW:InferSchoolFromGear.
local SP_UNKNOWN_SCHOOL = 0.80

-- Shared by every caster-DPS profile; the school block is layered on top.
local function casterBase()
    return {
        [S.INT] = 1.00, [S.STA] = 0.55, [S.SPI] = 0.25,
        [S.SPELLDMG] = SP_FULL,
        -- Nothing populates SPELLPOWER any more: the client's combined line is
        -- split into damage and healing by SW:Canonical, and the item database
        -- reports them separately to begin with. The weight stays at zero so
        -- that if some future source ever does fill it, the effect is a stat
        -- quietly ignored rather than the same bonus counted twice - and
        -- SanityChecks' spell-power-double-counted says so out loud.
        [S.SPELLPOWER] = 0.00,
        -- Zero, deliberately, and the reason is at the top of this block.
        [S.HEALPOWER] = 0.00,
        [S.SPELLCRIT] = 1.10, [S.SPELLHIT] = 1.30, [S.SPELLHASTE] = 1.00,
        [S.MP5] = 0.80, [S.MANA] = 0.06, [S.HEALTH] = 0.05,
        -- Cloth armour is a rounding error on a caster's survival, but it is
        -- not nothing: it is the profile's own armour type.
        [S.ARMOR] = 0.02,
        -- A caster's weapon damage matters for one thing: the wand they shoot
        -- between casts to save mana. Small, but it is the ONLY stat a wand
        -- has, so a zero here would make every wand comparison meaningless -
        -- which is exactly what happened.
        [S.DPS] = 0.30,
        -- Melee and defensive stats do nothing for spell damage.
        [S.STR] = 0.00, [S.AGI] = 0.00, [S.ATTACKPOWER] = 0.00,
        [S.CRIT] = 0.00, [S.HIT] = 0.00, [S.HASTE] = 0.00, [S.EXPERTISE] = 0.00,
        [S.DEFENSE] = 0.00, [S.DODGE] = 0.00, [S.PARRY] = 0.00, [S.BLOCK] = 0.00,
        -- Resistance is a situational defence, not damage. A DPS profile that
        -- paid for it let five useless numbers add up to a fake upgrade.
        [S.RESIST_ARCANE] = 0.00, [S.RESIST_FIRE] = 0.00, [S.RESIST_FROST] = 0.00,
        [S.RESIST_NATURE] = 0.00, [S.RESIST_SHADOW] = 0.00,
    }
end

-- `own` is the school key this spec casts; `alsoCasts` are the other schools of
-- the same class. Everything not listed is zero.
local function casterSet(own, alsoCasts)
    local set = casterBase()
    for _, entry in ipairs(ns.SPELL_SCHOOLS) do set[entry.stat] = SP_NONE end
    for _, key in ipairs(alsoCasts or {}) do
        for _, entry in ipairs(ns.SPELL_SCHOOLS) do
            if entry.key == key then set[entry.stat] = SP_OFF_CLASS end
        end
    end
    if own then
        for _, entry in ipairs(ns.SPELL_SCHOOLS) do
            if entry.key == own then set[entry.stat] = SP_OWN end
        end
    end
    return set
end

-- School-neutral caster DPS: the fallback when we cannot read a spec AND
-- cannot work the school out of the gear. Every school gets the expectation
-- weight, so none is favoured and - crucially - none is dismissed.
local CASTER_DPS = casterBase()
do
    for _, entry in ipairs(ns.SPELL_SCHOOLS) do
        CASTER_DPS[entry.stat] = SP_UNKNOWN_SCHOOL
    end
end

local CASTER_ARCANE = casterSet("ARCANE", { "FIRE", "FROST" })
local CASTER_FIRE   = casterSet("FIRE",   { "ARCANE", "FROST" })
local CASTER_FROST  = casterSet("FROST",  { "ARCANE", "FIRE" })
-- Warlock and shadow priest. A warlock's damage is shadow and fire; a shadow
-- priest's is shadow and holy, but holy damage gear is a healer's, so it keeps
-- the off-school weight rather than the own-school one.
local CASTER_SHADOW = casterSet("SHADOW", { "FIRE" })
-- Balance druid and elemental shaman: nature first, with fire alongside.
local CASTER_NATURE = casterSet("NATURE", { "FIRE", "FROST" })

local CASTER_HEAL = {
    [S.INT] = 1.00, [S.STA] = 0.45, [S.SPI] = 0.70,
    [S.HEALPOWER] = 1.50, [S.SPELLDMG] = 0.20,
    [S.SPELLPOWER] = 0.00,   -- see the caster note above
    [S.SPELLCRIT] = 0.70, [S.SPELLHIT] = 0.10, [S.SPELLHASTE] = 0.80,
    [S.MP5] = 1.60, [S.MANA] = 0.07, [S.HEALTH] = 0.05, [S.ARMOR] = 0.02,
    [S.STR] = 0.00, [S.AGI] = 0.00, [S.ATTACKPOWER] = 0.00,
    [S.CRIT] = 0.00, [S.HIT] = 0.00, [S.HASTE] = 0.00,
    -- A healer's wand, same reasoning as the caster above.
    [S.DPS] = 0.20,
    -- A healer's offensive spells are a side job, so school damage is worth
    -- little; holy is the one they actually cast.
    [S.SPELLDMG_HOLY] = 0.20, [S.SPELLDMG_ARCANE] = 0.00,
    [S.SPELLDMG_FIRE] = 0.00, [S.SPELLDMG_FROST] = 0.00,
    [S.SPELLDMG_NATURE] = 0.10, [S.SPELLDMG_SHADOW] = 0.00,
}

local MELEE_DPS = {
    [S.STR] = 1.00, [S.AGI] = 0.90, [S.STA] = 0.55,
    [S.ATTACKPOWER] = 0.50, [S.CRIT] = 1.10, [S.HIT] = 1.40, [S.HASTE] = 1.00,
    [S.EXPERTISE] = 1.10, [S.ARMOR] = 0.05, [S.HEALTH] = 0.05,
    [S.INT] = 0.02, [S.SPI] = 0.02, [S.SPELLPOWER] = 0.00,
    [S.HEALPOWER] = 0.00,
    -- For a melee profile the weapon IS the damage, so this is the heaviest
    -- single number on the sheet.
    [S.DPS] = 2.00,
}

local TANK = {
    [S.STA] = 1.00, [S.STR] = 0.45, [S.AGI] = 0.65,
    [S.DEFENSE] = 1.40, [S.DODGE] = 1.10, [S.PARRY] = 1.00, [S.BLOCK] = 0.70,
    [S.ARMOR] = 0.12, [S.HEALTH] = 0.10, [S.HIT] = 0.40, [S.CRIT] = 0.30,
    [S.ATTACKPOWER] = 0.15, [S.INT] = 0.05, [S.SPI] = 0.05,
    [S.HEALPOWER] = 0.00,
    -- A tank still has to hold aggro, but survival comes first.
    [S.DPS] = 0.60,
    -- Survival IS the job here, so resistance earns a weight - unlike on a
    -- damage profile, where it was buying fake upgrades.
    [S.RESIST_ARCANE] = 0.03, [S.RESIST_FIRE] = 0.03, [S.RESIST_FROST] = 0.03,
    [S.RESIST_NATURE] = 0.03, [S.RESIST_SHADOW] = 0.03,
}

local HYBRID_PHYS = {
    [S.AGI] = 1.00, [S.STR] = 0.80, [S.STA] = 0.60,
    [S.ATTACKPOWER] = 0.45, [S.CRIT] = 1.00, [S.HIT] = 1.20, [S.HASTE] = 0.90,
    [S.ARMOR] = 0.05, [S.INT] = 0.10, [S.SPI] = 0.10,
    [S.HEALPOWER] = 0.00,
    [S.DPS] = 1.80,
}

SW.SETS = {
    CASTER_DPS = CASTER_DPS,
    CASTER_ARCANE = CASTER_ARCANE,
    CASTER_FIRE = CASTER_FIRE,
    CASTER_FROST = CASTER_FROST,
    CASTER_SHADOW = CASTER_SHADOW,
    CASTER_NATURE = CASTER_NATURE,
    CASTER_HEAL = CASTER_HEAL,
    MELEE_DPS = MELEE_DPS,
    TANK = TANK,
    HYBRID_PHYS = HYBRID_PHYS,
}

-- The stat each profile exists to maximise. Used for one rule and one rule
-- only: an item that LOWERS this is never presented as an upgrade, however the
-- total comes out. That is the rule the Pristine Circlet broke - it traded 11
-- arcane damage for 8 generic and 22 healing and came out "+16".
SW.MAIN_STAT = {
    CASTER_DPS    = S.SPELLDMG,
    CASTER_ARCANE = S.SPELLDMG_ARCANE,
    CASTER_FIRE   = S.SPELLDMG_FIRE,
    CASTER_FROST  = S.SPELLDMG_FROST,
    CASTER_SHADOW = S.SPELLDMG_SHADOW,
    CASTER_NATURE = S.SPELLDMG_NATURE,
    CASTER_HEAL   = S.HEALPOWER,
    MELEE_DPS     = S.STR,
    TANK          = S.STA,
    HYBRID_PHYS   = S.AGI,
}

-- For a caster, the generic spell damage stat counts as the main stat too: it
-- feeds the same spells the school stat does, so losing one and gaining the
-- other is not a drop in the thing the profile is about.
-- SPELLPOWER is NOT listed: it is the same bonus as SPELLDMG written another
-- way, and listing both is what made item 253885's group read 8 instead of 4.
SW.MAIN_STAT_ALSO = {
    CASTER_DPS    = { S.SPELLDMG },
    CASTER_ARCANE = { S.SPELLDMG },
    CASTER_FIRE   = { S.SPELLDMG },
    CASTER_FROST  = { S.SPELLDMG },
    CASTER_SHADOW = { S.SPELLDMG },
    CASTER_NATURE = { S.SPELLDMG },
    CASTER_HEAL   = { S.SPELLDMG },
}

-- The set of stats that count as "the point of this profile", as a set.
function SW:MainStats(setKey)
    local out = {}
    local main = SW.MAIN_STAT[setKey or ""]
    if main then out[main] = true end
    for _, extra in ipairs(SW.MAIN_STAT_ALSO[setKey or ""] or {}) do
        out[extra] = true
    end
    return out
end

-- КАКИЕ ШКОЛЫ КЛАСС ВООБЩЕ УМЕЕТ КАСТОВАТЬ.
--
-- Нужно для двух разных вопросов, и оба до этой таблицы отвечались неверно:
--
--   1. Профиль по умолчанию, когда спек не читается. У чернокнижника все три
--      спека - тень с огнём рядом, это написано в SPEC_HINTS ниже; а
--      CLASS_DEFAULT отдавал ему школо-слепой CASTER_DPS, где все шесть школ
--      стоят 0.80 - включая тайную магию, лёд и силы природы, которых
--      чернокнижник не кастует вообще. На десятом уровне талантов ещё нет,
--      то есть это НОРМАЛЬНОЕ состояние, а не редкий случай.
--
--   2. Вывод школы по надетым вещам. Он был классо-слепым: чернокнижник,
--      надевший кинжал с тайным уроном - а на низких уровнях надевают что
--      дали, - получал профиль CASTER_ARCANE, то есть веса мага. Надетая вещь
--      - улика о вещи, а не о том, какие заклинания персонаж умеет бросать.
--
-- Классы, которых здесь нет, школами не ограничиваются: пустая запись значит
-- «не знаю», и тогда прежнее поведение сохраняется целиком.
SW.CLASS_SCHOOLS = {
    MAGE    = { ARCANE = true, FIRE = true, FROST = true },
    WARLOCK = { SHADOW = true, FIRE = true },
    PRIEST  = { HOLY = true, SHADOW = true },
    DRUID   = { NATURE = true, ARCANE = true },
    SHAMAN  = { NATURE = true, FIRE = true, FROST = true },
    PALADIN = { HOLY = true },
}

-- Школы класса как множество, или nil когда класс нам незнаком.
function SW:SchoolsOfClass(classFile)
    local set = SW.CLASS_SCHOOLS[classFile or ""]
    if not set then return nil end
    local out = {}
    for key in pairs(set) do out[key] = true end
    return out
end

-- Which set each class falls back to when we cannot read a spec.
--
-- WARLOCK ЗДЕСЬ НЕ CASTER_DPS, и это не вкусовщина: школо-слепой набор ценит
-- тайный и ледяной урон наравне с теневым, а чернокнижник ни того, ни другого
-- не кастует. У мага три спека - три разные школы, и для него школо-слепой
-- ответ действительно единственный честный; у чернокнижника все три спека
-- теневые, то есть школа известна и без спека.
SW.CLASS_DEFAULT = {
    MAGE = "CASTER_DPS",
    WARLOCK = "CASTER_SHADOW",
    PRIEST = "CASTER_HEAL",
    DRUID = "CASTER_HEAL",
    SHAMAN = "CASTER_HEAL",
    PALADIN = "TANK",
    WARRIOR = "MELEE_DPS",
    ROGUE = "HYBRID_PHYS",
    HUNTER = "HYBRID_PHYS",
    DEATHKNIGHT = "MELEE_DPS",
    MONK = "MELEE_DPS",
    DEMONHUNTER = "MELEE_DPS",
    EVOKER = "CASTER_DPS",
}

-- Spec name fragments -> set. Matched case-insensitively against whatever the
-- client calls the spec (or the talent tree with the most points), so both the
-- Russian names this client uses and the English ones are listed.
-- Stems are lowercase and matched through Util.lower, which handles Cyrillic;
-- Lua's own string.lower leaves "Защита" capitalised and the match would miss.
-- Stems are also kept long enough not to collide: a two-letter stem like "бо"
-- would match half the words in the language.
-- ONE SPEC, ONE SCHOOL. The mage line used to map arcane, fire and frost all to
-- the same school-blind CASTER_DPS, which is how an arcane mage was offered the
-- fire and frost versions of the same robe as if they were interchangeable. The
-- three mage specs now point at three different weight sets.
SW.SPEC_HINTS = {
    { set = "TANK",        words = { "защит", "страж", "protect", "guardian" },
      classes = { WARRIOR = true, PALADIN = true, DRUID = true, DEATHKNIGHT = true,
                  MONK = true, DEMONHUNTER = true } },
    -- Mage, by school. "тайн"/"аркан" before the others; "лед"/"льд" covers
    -- "Лед" and "Льда" alike.
    { set = "CASTER_ARCANE", words = { "аркан", "тайн", "arcane" },
      classes = { MAGE = true } },
    { set = "CASTER_FIRE",   words = { "огн", "огон", "пламен", "fire" },
      classes = { MAGE = true } },
    { set = "CASTER_FROST",  words = { "лед", "льд", "холод", "frost" },
      classes = { MAGE = true } },
    -- Warlock: all three specs are shadow-first with fire alongside.
    { set = "CASTER_SHADOW", words = { "демонолог", "колдовств", "разрушен",
                                       "demonolog", "afflict", "destruct" },
      classes = { WARLOCK = true } },
    { set = "CASTER_SHADOW", words = { "темн", "shadow" }, classes = { PRIEST = true } },
    { set = "CASTER_HEAL", words = { "послушан", "свят", "disciplin", "holy" },
      classes = { PRIEST = true, PALADIN = true } },
    { set = "CASTER_HEAL", words = { "исцелен", "восстановлен", "restorat" },
      classes = { DRUID = true, SHAMAN = true } },
    { set = "CASTER_NATURE", words = { "баланс", "сил прир", "balance", "element" },
      classes = { DRUID = true, SHAMAN = true } },
    { set = "MELEE_DPS",   words = { "оруж", "неистов", "боев", "усилен", "возмезд",
                                     "arms", "fury", "enhance", "retrib", "feral" } },
}

-- НЕЗНАКОМЫЙ КЛАСС НЕ ПОЛУЧАЕТ ЧУЖОЙ ПРОФИЛЬ.
--
-- Последним ответом здесь стоял CASTER_DPS, помеченный CONF.UNKNOWN. Пометка
-- честная, а смысл всё равно был «если не знаю, считай магом»: класс,
-- которого нет в CLASS_DEFAULT, получал кастерские веса, и по ним считался
-- прирост экипировки - то есть выдавался СОВЕТ, собранный из чужих чисел.
-- Сравнить его с правдой игроку нечем, а выглядит он так же, как настоящий.
--
-- Поэтому профиля нет вовсе: setKey = nil. Ветки обязаны сказать, почему его
-- нет (how = "unknown-class" / "no-class"), а не оценивать вещи наугад. Это
-- то же правило, по которому реестр отвечает «не знаю» про персонажа, которым
-- не играли, вместо «профессий нет».
--
-- Returns setKey, confidence, how. setKey = nil значит «профиля нет».
-- classFile is the stable English class token (MAGE, WARLOCK...), specName is
-- whatever the client gave us or nil.
function SW:Resolve(classFile, specName)
    if type(specName) == "string" and specName ~= "" then
        local lower = U.lower(specName)
        for _, hint in ipairs(SW.SPEC_HINTS) do
            if (not hint.classes) or (classFile and hint.classes[classFile]) then
                for _, word in ipairs(hint.words) do
                    if lower:find(word) then return hint.set, ns.CONF.ESTIMATE, "spec" end
                end
            end
        end
    end
    if classFile and SW.CLASS_DEFAULT[classFile] then
        return SW.CLASS_DEFAULT[classFile], ns.CONF.ESTIMATE, "class"
    end
    -- Два разных «не знаю», и путать их нельзя: класса ещё не назвали (рано,
    -- клиент не ответил) и класс назвали, но он нам незнаком (чужая сборка,
    -- новый класс). Первое пройдёт само на следующем пересчёте, второе - нет.
    if classFile and classFile ~= "" then
        return nil, ns.CONF.UNKNOWN, "unknown-class"
    end
    return nil, ns.CONF.UNKNOWN, "no-class"
end

-- ПОЧЕМУ ПРОФИЛЯ НЕТ - СЛОВАМИ, ОДНИМ ОТВЕТОМ НА ВЕСЬ АДДОН.
--
-- Нужно всем ветках, которые без весов молчат: иначе каждая придумает свою
-- формулировку, и они разойдутся. nil, когда профиль есть и объяснять нечего.
function SW:NoProfileReason(how, classFile)
    if how == "unknown-class" then
        return "класс «" .. tostring(classFile) .. "» моим данным незнаком, и"
            .. " весов характеристик для него у меня нет: оценивать вещи чужими"
            .. " весами я не буду"
    elseif how == "no-class" then
        return "класс персонажа мне ещё не назвали, поэтому весов"
            .. " характеристик пока нет"
    end
    return nil
end

-- WHICH SCHOOL IS THIS CHARACTER'S, JUDGED BY WHAT THEY ARE WEARING.
--
-- The client does not always say what spec a character is - at low level there
-- may be no talents to read at all - and a school-blind answer is the state in
-- which this addon recommended a downgrade. But the character's own gear is
-- evidence: someone wearing four pieces of arcane-damage armour is an arcane
-- caster, and that is a fact about their kit rather than a guess about their
-- intentions.
--
-- ТОЛЬКО ШКОЛЫ СВОЕГО КЛАССА. `classFile` необязателен и по умолчанию берётся
-- из самого снимка; когда класс известен, школы, которых этот класс не кастует,
-- в подсчёт не идут вовсе - иначе тайный урон на случайном кинжале делал
-- чернокнижника магом. Числа при этом не выдумываются: отброшенные школы
-- остаются видны в detail.ignored, чтобы диагностика могла сказать, что именно
-- не учтено и почему.
--
-- Returns schoolKey, confidence, detail where detail = { counts, total, top }.
-- nil when the gear says nothing, which is an honest answer too.
function SW:InferSchoolFromGear(snap, classFile)
    if not (snap and snap.equipped) then return nil, ns.CONF.UNKNOWN end
    classFile = classFile or snap.classFile
    local allowed = SW:SchoolsOfClass(classFile)
    local counts, total, ignored = {}, 0, nil
    for _, equipped in pairs(snap.equipped) do
        local stats = ns.GearAdvisor and ns.GearAdvisor.ItemStats
            and ns.GearAdvisor:ItemStats(equipped.link or equipped.itemID) or nil
        for stat, value in pairs(stats or {}) do
            local entry = ns.SCHOOL_BY_STAT[stat]
            if entry and value > 0 then
                if allowed and not allowed[entry.key] then
                    ignored = ignored or {}
                    ignored[entry.key] = (ignored[entry.key] or 0) + value
                else
                    counts[entry.key] = (counts[entry.key] or 0) + value
                    total = total + value
                end
            end
        end
    end
    if total <= 0 then
        return nil, ns.CONF.UNKNOWN,
            { counts = counts, total = 0, ignored = ignored, classFile = classFile }
    end

    local top, topKey, second = 0, nil, 0
    for key, value in pairs(counts) do
        if value > top then top, second, topKey = value, top, key
        elseif value > second then second = value end
    end
    -- One school has to be clearly ahead. Two schools neck and neck is not
    -- evidence of either, and saying so is better than picking one.
    if topKey and top >= second * 2 and top >= 5 then
        return topKey, ns.CONF.ESTIMATE,
            { counts = counts, total = total, top = top, second = second,
              ignored = ignored, classFile = classFile }
    end
    return nil, ns.CONF.UNKNOWN,
        { counts = counts, total = total, top = top, second = second,
          ignored = ignored, classFile = classFile }
end

-- ЧТО ШКОЛЬНЫЙ УРОН ПРЕДМЕТА СТОИТ ЭТОМУ ПЕРСОНАЖУ - ЦИФРАМИ.
--
-- Отдельный вопрос и отдельная функция, потому что ответ нужен не только
-- сравнению вещей: ветка Благосклонности отбирает по нему СЕМЕЙСТВО покупок
-- (жемчужный набор против всего остального). Школа при этом нигде не
-- называется и списком не записана - берутся веса ЭТОГО персонажа, а вес ноль
-- здесь утверждение, а не вкус: «точка этой характеристики ему ничего не
-- даёт» (см. блок «WHAT A ZERO MEANS HERE» выше).
--
-- Возвращает amount (сколько школьного урона на предмете), value (сколько он
-- стоит по этим весам) и rows = { { stat, school, points, weight, value } },
-- самые крупные первыми - чтобы вызывающий мог сказать словами, что именно он
-- не учёл.
function SW:SchoolValue(stats, weights)
    if type(stats) ~= "table" then return 0, 0, {} end
    local amount, value, rows = 0, 0, {}
    for stat, points in pairs(stats) do
        local entry = ns.SCHOOL_BY_STAT[stat]
        local n = tonumber(points)
        if entry and n and n > 0 then
            local w = tonumber(weights and weights[stat]) or 0
            amount = amount + n
            value = value + n * w
            rows[#rows + 1] = { stat = stat, school = entry.key, points = n,
                                weight = w, value = n * w }
        end
    end
    table.sort(rows, function(a, b)
        if a.points ~= b.points then return a.points > b.points end
        return tostring(a.stat) < tostring(b.stat)
    end)
    return amount, value, rows
end

-- ЗНАЕТ ЛИ ЭТОТ НАБОР ВЕСОВ, КАКУЮ ШКОЛУ ПЕРСОНАЖ КАСТУЕТ - ПО САМИМ ВЕСАМ.
--
-- Не по имени набора: имя можно переименовать или добавить новое, и всякий, кто
-- сверяется со строкой «CASTER_DPS», разойдётся с числами при первой же правке.
-- Числа говорят сами, и ответов три:
--
--   "known"   - школы весят по-разному: набор знает, какая у персонажа своя;
--   "unknown" - все школы весят одинаково и не ноль (SP_UNKNOWN_SCHOOL): это
--               школо-слепой ответ, то есть «школу я не определил»;
--   "none"    - все школы весят ноль: профиль не про магию вовсе (воин, танк),
--               и школьный урон ему не нужен ни в какой школе.
--
-- Весов нет вовсе - "no-weights": это четвёртый ответ, и он не то же самое, что
-- «школа неизвестна»: профиля нет целиком.
function SW:SchoolCertainty(weights)
    if type(weights) ~= "table" then return "no-weights" end
    local first, same, anyPositive = nil, true, false
    for _, entry in ipairs(ns.SPELL_SCHOOLS) do
        local w = tonumber(weights[entry.stat]) or 0
        if w > 0 then anyPositive = true end
        if first == nil then first = w elseif w ~= first then same = false end
    end
    if not same then return "known" end
    return anyPositive and "unknown" or "none"
end

-- The caster weight set for a school key, when one exists.
SW.SET_FOR_SCHOOL = {
    ARCANE = "CASTER_ARCANE", FIRE = "CASTER_FIRE", FROST = "CASTER_FROST",
    SHADOW = "CASTER_SHADOW", NATURE = "CASTER_NATURE",
}

function SW:Set(setKey)
    return SW.SETS[setKey] or CASTER_DPS
end

-- Which stats the client is known to report for an item on this realm.
--
-- This list is not a guess and it is the whole reason the school fix was
-- needed. The client hands back the BASE stats and nothing else: equip bonuses
-- - spell damage, healing, school damage, ratings, mana regeneration - are not
-- in its item table at all. An independent gear addon running on this same
-- client reaches the same conclusion in its own code and reads bonuses out of
-- its own database for exactly this reason.
--
-- So a stat table built only from the client is INCOMPLETE by construction, and
-- a comparison made from one must not be called exact. That is what `complete`
-- is for below.
SW.CLIENT_REPORTS = {
    [S.STR] = true, [S.AGI] = true, [S.STA] = true, [S.INT] = true, [S.SPI] = true,
    [S.ARMOR] = true, [S.HEALTH] = true, [S.MANA] = true,
}

-- Polestar's item database speaks its own short vocabulary. This maps it onto
-- ours. Nothing is copied from that addon: the keys are the public shape of
-- ItemDB.Get(id).stats, documented in its own header, and we call it at
-- runtime.
--
--   sp   = spell DAMAGE ("+8 damage"), heal = spell HEALING ("+22 healing").
--          A generic "+N spell power" item lists N in both.
--   mpr / hpr are stored as mp5 / hp5 by its parser before we see them.
SW.FOREIGN_KEY_TO_STAT = {
    str = S.STR, agi = S.AGI, sta = S.STA, int = S.INT, spi = S.SPI,
    armor = S.ARMOR, health = S.HEALTH, mana = S.MANA,
    sp = S.SPELLDMG, heal = S.HEALPOWER,
    spArcane = S.SPELLDMG_ARCANE, spFire = S.SPELLDMG_FIRE,
    spFrost = S.SPELLDMG_FROST, spNature = S.SPELLDMG_NATURE,
    spShadow = S.SPELLDMG_SHADOW, spHoly = S.SPELLDMG_HOLY,
    spellCrit = S.SPELLCRIT, spellHit = S.SPELLHIT,
    crit = S.CRIT, hit = S.HIT, haste = S.HASTE,
    ap = S.ATTACKPOWER, rap = S.ATTACKPOWER,
    mp5 = S.MP5,
    defense = S.DEFENSE, dodge = S.DODGE, parry = S.PARRY,
    block = S.BLOCK, blockValue = S.BLOCK,
    resArcane = S.RESIST_ARCANE, resFire = S.RESIST_FIRE,
    resFrost = S.RESIST_FROST, resNature = S.RESIST_NATURE,
    resShadow = S.RESIST_SHADOW,
    -- Weapon damage per second, which the database derives from the damage
    -- range and the swing speed. It used to be dropped on the floor, so a wand
    -- - whose ONLY stat is its damage - compared as if it had no stats at all.
    dps = S.DPS,
    -- Still not mapped: hp5 (health per five seconds). There is no canonical
    -- key for it and its weight would be zero on every profile here, so the
    -- mapping would buy nothing. Named so the completeness test can allow it.
}

-- ONE BONUS, TWO STATS, AND THE BUG THAT CAME OF GETTING IT WRONG.
--
-- In this era "+N spell power" is not a third stat alongside damage and
-- healing: it IS "+N damage and +N healing", written once. The client reports
-- it as the single line ITEM_MOD_SPELL_POWER_SHORT, while the item database
-- reports the same bonus split into `sp` and `heal`.
--
-- Mapping the client's line to its own canonical key put the SAME pribavka in
-- the table twice under two names, and the main stat group summed both. Item
-- 253885 (sta3 int3 armor17 sp4 heal4) came out with a spell power group of 8
-- instead of 4, scored 17.79 instead of 11.39, and beat the Pearly Sash's
-- 17.69 by a tenth of a point - so the addon put the weaker belt on the card
-- and the player's own reading of the database is what caught it.
--
-- An item can carry BOTH the combined line and a damage-only one; the client
-- lists them separately and they add. So this is additive, not a replacement.
SW.COMBINED_SPELL_POWER = "ITEM_MOD_SPELL_POWER_SHORT"

-- TWO JOBS, TWO TABLES, and they only looked like one.
--
-- CLIENT_KEY_TO_STAT answers "what number did the client give me". The table
-- below answers a different question: "what stat does this WORD mean", used to
-- read a stat out of an enchant's name, because an enchant produces no item
-- and there is nothing to call GetItemStats on. Taking the combined spell
-- power key out of the first table to stop the double count also took the
-- phrase "сила магии" out of the second, and an arcane mage was immediately
-- back to being told a spell power enchant was worth nothing - the exact bug a
-- comment further down this file describes at length.
--
-- For naming purposes the combined phrase means spell damage: that is what a
-- caster gets out of it, and the healing half is weighted at zero anyway.
SW.TEXT_KEY_TO_STAT = {}
do
    for key, stat in pairs(SW.CLIENT_KEY_TO_STAT) do
        SW.TEXT_KEY_TO_STAT[key] = stat
    end
    SW.TEXT_KEY_TO_STAT[SW.COMBINED_SPELL_POWER] = S.SPELLDMG
end

-- Convert the client's raw stat table into our canonical keys.
function SW:Canonical(rawStats)
    if type(rawStats) ~= "table" then return nil end
    local out = {}
    for clientKey, value in pairs(rawStats) do
        local n = tonumber(value)
        if n and n ~= 0 then
            if clientKey == SW.COMBINED_SPELL_POWER then
                -- The one key that means two stats.
                out[S.SPELLDMG] = (out[S.SPELLDMG] or 0) + n
                out[S.HEALPOWER] = (out[S.HEALPOWER] or 0) + n
            else
                local stat = SW.CLIENT_KEY_TO_STAT[clientKey]
                if stat then out[stat] = (out[stat] or 0) + n end
            end
        end
    end
    return next(out) and out or nil
end

-- Convert a foreign item database's stat table into our canonical keys.
-- Returns the table plus the keys it used that we do not understand, so a
-- vocabulary change shows up in the diagnostics instead of silently dropping a
-- stat the way the schools were dropped.
function SW:CanonicalForeign(foreignStats)
    if type(foreignStats) ~= "table" then return nil, nil end
    local out, unknown = {}, nil
    for key, value in pairs(foreignStats) do
        local stat = SW.FOREIGN_KEY_TO_STAT[key]
        local n = tonumber(value)
        if stat and n and n ~= 0 then
            out[stat] = (out[stat] or 0) + n
        elseif not stat and key ~= "dps" and key ~= "hp5" then
            unknown = unknown or {}
            unknown[#unknown + 1] = key
        end
    end
    if unknown then table.sort(unknown) end
    return (next(out) and out or nil), unknown
end

-- Merge what the client said with what a foreign database knows.
--
--   client wins for the stats it actually reports (CLIENT_REPORTS): it is the
--     live game, and the external data was generated weeks ago.
--   the foreign table fills everything the client does not report, which on
--     this realm is every equip bonus including school damage.
--
-- Returns stats, confidence, info where info = {
--   complete  - true when every stat the comparison needs is accounted for
--   fromClient / fromForeign - how many stats each side supplied
--   missingBonuses - true when NOBODY could tell us the equip bonuses, which is
--     the state in which a comparison must not be called exact
--   unknownKeys - foreign keys we did not recognise
-- }
function SW:Merge(clientRaw, foreignStats)
    local fromClient = SW:Canonical(clientRaw)
    local fromForeign, unknown = SW:CanonicalForeign(foreignStats)

    if not (fromClient or fromForeign) then
        return nil, ns.CONF.UNKNOWN, {
            complete = false, missingBonuses = true,
            fromClient = 0, fromForeign = 0, unknownKeys = unknown,
        }
    end

    local out, nClient, nForeign = {}, 0, 0
    for stat, value in pairs(fromForeign or {}) do
        out[stat] = value
        nForeign = nForeign + 1
    end
    for stat, value in pairs(fromClient or {}) do
        -- A base stat read from the live client overrides the cached copy.
        if SW.CLIENT_REPORTS[stat] or out[stat] == nil then
            out[stat] = value
        end
        nClient = nClient + 1
    end

    local conf
    if fromForeign and fromClient then conf = ns.CONF.CACHED
    elseif fromForeign then conf = ns.CONF.CACHED
    else conf = ns.CONF.EXACT end

    return out, conf, {
        complete = (fromForeign ~= nil),
        missingBonuses = (fromForeign == nil),
        fromClient = nClient, fromForeign = nForeign,
        unknownKeys = unknown,
    }
end

-- Score a canonical stat table against a weight set. Returns a single number in
-- "primary stat points" - the unit every power comparison in the addon uses.
--
-- SCHOOL BONUSES DO NOT ADD UP, and that is the one piece of real arithmetic in
-- here. The damage a character deals splits over the schools they cast, and
-- they do not cast two spells at once: an item giving +14 Fire AND +14 Frost is
-- worth about one +14, not two. Summed naively, a six-school item would score
-- as the best object in the game. So the school contribution is capped at the
-- largest single school bonus, valued at the best weight that applies - which
-- is the generic spell damage weight when that is higher, because a
-- multi-school bonus can never beat plain spell damage of the same size.
-- БЕЗ ВЕСОВ БАЛЛА НЕТ, И ЭТО НЕ НОЛЬ.
--
-- Здесь стояло `weightSet or CASTER_DPS`: профиля нет - считаем кастерскими
-- весами. Это и есть «если не знаю, считай магом», только на самом дне, где
-- его никто не видит: наверху карточка выходила с честной пометкой «оценка», а
-- числа в ней были посчитаны по чужому классу.
--
-- nil значит «балла нет» - ровно так же, как U.money без числа отвечает «не
-- знаю», а не «0м». Ноль был бы утверждением «эта вещь ничего не даёт».
function SW:Score(canonicalStats, weightSet)
    if type(canonicalStats) ~= "table" then return 0 end
    if type(weightSet) ~= "table" then return nil end
    local w = weightSet
    local total, schoolSum, schoolTop = 0, 0, 0
    for stat, value in pairs(canonicalStats) do
        if ns.SCHOOL_BY_STAT[stat] then
            schoolSum = schoolSum + value * (w[stat] or 0)
            if value > schoolTop then schoolTop = value end
        else
            total = total + (value * (w[stat] or 0))
        end
    end
    if schoolSum > 0 then
        local best = w[S.SPELLDMG] or 0
        for _, entry in ipairs(ns.SPELL_SCHOOLS) do
            local x = w[entry.stat] or 0
            if x > best then best = x end
        end
        local cap = best * schoolTop
        if schoolSum > cap then schoolSum = cap end
        total = total + schoolSum
    end
    return total
end

-- The weight set in force right now, honouring a player override.
--
-- `snap` is optional and is the character snapshot. When it is supplied and the
-- spec could not be read, the school is inferred from the equipped gear rather
-- than falling back to the school-blind set - which is what let a downgrade
-- through in the first place.
--
-- Returns weights, setKey, confidence, how ("override"|"spec"|"gear"|"class"|"none").
function SW:Active(classFile, specName, snap)
    local override = ns.Config and ns.Config:Char() and ns.Config:Char().statWeightOverride
    if override and SW.SETS[override] then
        return SW.SETS[override], override, ns.CONF.EXACT, "override"
    end
    local key, conf, how = SW:Resolve(classFile, specName)
    -- Профиля нет - значит нет, и наружу уходит nil, а не школо-слепой набор.
    -- Все, кто берёт snap.weights, обязаны это пережить и сказать почему
    -- (SW:NoProfileReason).
    if not key then
        if ns.Diag then
            ns.Diag:Log("профиля весов нет", {
                classFile = classFile, spec = specName, how = how,
                why = SW:NoProfileReason(how, classFile),
            })
        end
        return nil, nil, conf, how
    end

    -- A school-blind caster answer is the weakest one there is. Before settling
    -- for it, look at the gear.
    if key == "CASTER_DPS" and how ~= "spec" and snap then
        local school, schoolConf, detail = SW:InferSchoolFromGear(snap, classFile)
        local inferred = school and SW.SET_FOR_SCHOOL[school] or nil
        if inferred and SW.SETS[inferred] then
            if ns.Diag then
                ns.Diag:Log("школа определена по надетым вещам", {
                    school = school, set = inferred,
                    counts = detail and detail.counts or nil,
                    -- Школы, которые этот класс не кастует, в подсчёт не пошли.
                    -- Видно, что именно отброшено: иначе «почему не аркан» было
                    -- бы не на что ответить.
                    ignored = detail and detail.ignored or nil,
                    classFile = classFile,
                })
            end
            return SW.SETS[inferred], inferred, schoolConf, "gear"
        end
    end
    return SW:Set(key), key, conf, how
end

-- ПОРЯДОК НАБОРОВ ДЛЯ РУЧНОГО ВЫБОРА.
--
-- В настройках стоял список из пяти «ролей», а школьных наборов в нём не было -
-- при том что главная характеристика кастера считается именно по школе. Если
-- автоопределение промахнулось (оно выводит школу по надетым вещам, то есть по
-- улике, а не по факту), исправить его было нечем.
--
-- Порядок именно список, а не обход SW.SETS: обход таблицы в Lua не
-- упорядочен, и кнопки на экране прыгали бы между открытиями окна.
SW.OVERRIDE_ORDER = {
    "CASTER_DPS",
    "CASTER_ARCANE", "CASTER_FIRE", "CASTER_FROST",
    "CASTER_SHADOW", "CASTER_NATURE",
    "CASTER_HEAL", "MELEE_DPS", "TANK", "HYBRID_PHYS",
}

-- ЧТО ИДЁТ В БАЛЛ, А ЧТО НЕ ИДЁТ - СЛОВАМИ И ИЗ САМОГО НАБОРА.
--
-- Нужно одному месту - строке в настройках, где раньше было вписано
-- «интеллект, сила магии и дух, а сила не идёт вовсе». Это кастерский перечень,
-- выданный за характеристики «вашего класса»: воин с набором MELEE_DPS читал,
-- что сила не идёт вовсе, тогда как у него она главная.
--
-- Возвращает два списка названий: самые весомые характеристики и те, чей вес
-- ровно ноль (а ноль здесь - утверждение, см. блок «WHAT A ZERO MEANS HERE»
-- выше). Названия берутся у GearAdvisor - там они уже есть для всех статов, и
-- второй словарь разошёлся бы с первым.
SW.WEIGHT_SUMMARY_TOP = 3
SW.WEIGHT_SUMMARY_ZERO = 3

function SW:WeightSummary(setKey)
    local set = SW.SETS[setKey or ""]
    if not set then return nil, nil end
    local label = ns.GearAdvisor and ns.GearAdvisor.StatLabel
        and function(s) return ns.GearAdvisor:StatLabel(s) end
        or function(s) return tostring(s) end

    local rows, zeros = {}, {}
    for stat, weight in pairs(set) do
        if (tonumber(weight) or 0) > 0 then
            rows[#rows + 1] = { stat = stat, weight = weight }
        elseif weight == 0 then
            zeros[#zeros + 1] = stat
        end
    end
    -- Вес, потом имя стата: порядок обхода таблицы в Lua не определён, и без
    -- второго ключа строка менялась бы от запуска к запуску.
    table.sort(rows, function(a, b)
        if a.weight ~= b.weight then return a.weight > b.weight end
        return a.stat < b.stat
    end)
    table.sort(zeros)

    local counted = {}
    for i = 1, math.min(SW.WEIGHT_SUMMARY_TOP, #rows) do
        counted[#counted + 1] = label(rows[i].stat)
    end
    -- Из нулевых показываем те, которые игрок скорее всего и спутает с
    -- полезными: первые по алфавиту годятся не хуже любого другого правила, но
    -- школьные нули в этот список не идут - «урон тенью не идёт вовсе» у мага
    -- правда, а читается как поломка.
    local ignored = {}
    for _, stat in ipairs(zeros) do
        if #ignored >= SW.WEIGHT_SUMMARY_ZERO then break end
        if not ns.SCHOOL_BY_STAT[stat] then ignored[#ignored + 1] = label(stat) end
    end
    return counted, ignored
end

SW.SET_LABEL = {
    CASTER_DPS = "Магический урон (школа не определена)",
    CASTER_ARCANE = "Магический урон: тайная магия",
    CASTER_FIRE = "Магический урон: огонь",
    CASTER_FROST = "Магический урон: лёд",
    CASTER_SHADOW = "Магический урон: тень",
    CASTER_NATURE = "Магический урон: силы природы",
    CASTER_HEAL = "Лечение",
    MELEE_DPS = "Ближний бой",
    TANK = "Защита",
    HYBRID_PHYS = "Ловкость / физ. урон",
}

-- Reading a stat out of a name -----------------------------------------
--
-- An enchant produces no item, so there is nothing to call GetItemStats on and
-- no way to learn what it actually does. Without this, the addon happily
-- recommends an agility enchant to an arcane mage, which is useless advice.
--
-- What we can do: the recipe's name contains the stat, and the client already
-- told us what every stat is called in the player's language via the
-- ITEM_MOD_* globals. So we take the stat word out of the client's own string
-- and look for it in the recipe name. Nothing is translated by hand, and the
-- result is reported as an ESTIMATE because it is pattern matching on a name.
--
-- Russian declines nouns, so the global ("+%d к интеллекту", dative) and the
-- recipe name ("интеллект III", nominative) do not match exactly. Trimming two
-- characters off the end of the stat word bridges the cases.

local statWordCache

local function utf8Chars(s)
    local chars, i, n = {}, 1, #s
    while i <= n do
        local b = s:byte(i)
        local len = (b >= 240 and 4) or (b >= 224 and 3) or (b >= 192 and 2) or 1
        chars[#chars + 1] = s:sub(i, i + len - 1)
        i = i + len
    end
    return chars
end

local function stem(word)
    local chars = utf8Chars(word)
    local keep = #chars - 2
    if keep < 4 then keep = math.min(#chars, math.max(3, #chars - 1)) end
    return table.concat(chars, "", 1, keep)
end

-- Stem EVERY word of a stat name, not just chop two characters off the end of
-- the whole phrase.
--
-- This is what made "сила магии" unreadable. The client's string is dative
-- ("+%d к силе магии"), so the old code produced the single stem "силе маг",
-- which never matches the nominative "сила магии" in a recipe name. The short
-- stem "сил" (from "+%d к силе") then matched instead, and an arcane mage was
-- told that the best spell power enchant in the game was worth nothing because
-- it had been read as strength.
--
-- Per-word stems ("сил" + "маг") match either case, and because every word has
-- to be present, plain "сила" no longer collides with "сила магии".
local STOP_WORDS = { ["к"] = true, ["to"] = true, ["от"] = true, ["of"] = true,
                     ["и"] = true, ["and"] = true, ["в"] = true }

local function stemWords(phrase)
    local parts = {}
    for word in phrase:gmatch("[^%s%-%,%.]+") do
        if not STOP_WORDS[word] then
            local st = stem(word)
            if st and #st >= 3 then parts[#parts + 1] = st end
        end
    end
    return parts
end

-- { { stems = {"сил","маг"}, stat = "SPELLPOWER" }, ... }, most specific first.
function SW:StatWords()
    if statWordCache then return statWordCache end
    statWordCache = {}

    local seen = {}
    for clientKey, stat in pairs(SW.TEXT_KEY_TO_STAT) do
        local text = _G and _G[clientKey]
        if type(text) == "string" and text ~= "" then
            -- "+%d к интеллекту" -> "интеллекту" ; "+%d Intellect" -> "Intellect"
            local bare = text:gsub("%%%d?%$?[sd]", ""):gsub("[%+%-%d%%]", "")
            bare = U.trim(bare)
            if bare then
                local low = U.lower(bare)
                local parts = stemWords(low)
                if #parts > 0 then
                    local key = table.concat(parts, "|")
                    if not seen[key] then
                        seen[key] = true
                        statWordCache[#statWordCache + 1] = {
                            stems = parts, stat = stat, word = low,
                            weight = #table.concat(parts) + #parts,
                        }
                    end
                end
            end
        end
    end
    -- Most words first, then longest, so "сила магии" is considered before "сила".
    table.sort(statWordCache, function(a, b)
        if #a.stems ~= #b.stems then return #a.stems > #b.stems end
        if a.weight ~= b.weight then return a.weight > b.weight end
        return a.word < b.word
    end)
    return statWordCache
end

function SW:ResetStatWords()
    statWordCache = nil
end

-- КОРЕНЬ ИЩЕТСЯ С НАЧАЛА СЛОВА, И СЛОВО НЕ ДОЛЖНО БЫТЬ ДЛИННЕЕ КОРНЯ НА МНОГО.
--
-- Простой поиск подстроки читал «сильный интеллект» как силу: корень силы -
-- «сил» (из клиентского «+%d к силе»), и он честно находится внутри слова
-- «сильный». На экране это выглядело так: «Чары для нагрудника: сильный
-- интеллект» - «Даёт прирост интеллекта И СИЛЫ», то есть совет обещал магу
-- характеристику, которой в чаре нет вовсе. А «без размена» в этом проекте -
-- правило, не пожелание.
--
-- Падеж русское слово меняет с конца и не больше чем на три буквы от корня
-- (корень - это и есть слово минус два знака, см. stem): «сил» -> сила, силы,
-- силе, силу, силой - самое длинное шесть букв. «сильный» - семь, и он мимо.
-- Считаются ЗНАКИ, а не байты: в utf-8 русская буква занимает два.
local MAX_ENDING = 3

local function wordMatchesStem(word, stem)
    if word:sub(1, #stem) ~= stem then return false end
    local extra = #utf8Chars(word) - #utf8Chars(stem)
    return extra >= 0 and extra <= MAX_ENDING
end

-- Which stats a piece of text seems to mention. Returns a set, or nil.
--
-- СЛОВО ТЕКСТА ОТДАЁТСЯ САМОМУ ПОДРОБНОМУ НАЗВАНИЮ И БОЛЬШЕ НИКОМУ.
--
-- Образцы и так перебираются от самого подробного к самому общему (см.
-- сортировку в SW:StatWords, «сила магии» раньше «силы»), но занятые слова не
-- отмечались, и поэтому «малая сила магии» давала ДВЕ характеристики: силу
-- магии и заодно физическую силу. Для оценки это сходило с рук - там берётся
-- наибольший вес, - а на карточке чар выезжало прямо в текст: «даёт прирост
-- силы магии и силы». Теперь слово, которое забрало подробное название,
-- общему уже не достаётся.
function SW:StatsInText(text)
    if type(text) ~= "string" then return nil end
    local low = U.lower(text)
    -- Слова текста - по тем же разделителям, по которым разбирается само
    -- название характеристики (см. stemWords).
    local words, taken = {}, {}
    for word in low:gmatch("[^%s%-%,%.%:%;%(%)]+") do words[#words + 1] = word end
    local found, any = {}, false
    for _, entry in ipairs(SW:StatWords()) do
        -- Every word of the stat name has to be there, which is what keeps
        -- "сила" and "сила магии" apart.
        local all, used = true, {}
        for _, st in ipairs(entry.stems) do
            local hit = nil
            for i, word in ipairs(words) do
                if not taken[i] and not used[i] and wordMatchesStem(word, st) then
                    hit = i
                    break
                end
            end
            if not hit then all = false; break end
            used[hit] = true
        end
        if all then
            for i in pairs(used) do taken[i] = true end
            found[entry.stat] = true
            any = true
        end
    end
    return any and found or nil
end

-- How much this character would value whatever the text names.
-- Returns score (nil when nothing recognised), confidence, the stat set.
function SW:TextUsefulness(text, weightSet)
    local stats = SW:StatsInText(text)
    if not stats then return nil, ns.CONF.UNKNOWN, nil end
    local w = weightSet or CASTER_DPS
    local best = 0
    for stat in pairs(stats) do
        local weight = w[stat] or 0
        if weight > best then best = weight end
    end
    return best, ns.CONF.ESTIMATE, stats
end

return SW
