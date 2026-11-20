-- ForeverPilot / Tests/fixtures/real_items.lua
--
-- GENERATED. Do not hand-edit: rebuild it from the installed data with the
-- generator described at the bottom of this file.
--
-- WHY IT EXISTS. The test harness used to fake the "independent item database"
-- by MIRRORING the fake client's stat table. That mirror is derived from
-- Data/StatWeights.lua's CLIENT_KEY_TO_STAT, which has no school keys at all,
-- so a mirror can never produce spArcane - and the bug that cost the player
-- materials was therefore untestable by construction. These are real rows,
-- copied verbatim out of the installed Polestar_ItemDB and out of the player's
-- own SavedVariables, so a fixture cannot agree with the code by accident.
--
-- Entry format is the data addon's own, documented in its header:
--   "<inv> <ilvl> <req> <quality> <classID> <subclassID> [<stat><n> ...]"
local F = {}

-- Item rows, verbatim from Polestar_ItemDB (Items.lua / Forever.lua).
F.ITEM_ROWS = {
    [25] = "21 2 1 1 2 7 dmin1 dmax3 speed1900",
    [39] = "7 1 1 0 4 1 armor2",
    [720] = "10 28 23 3 4 2 str8 sta7 armor62",
    [744] = "12 44 0 2 4 0 spi8",  -- Thunderbrew's Boot Flask
    [756] = "17 29 24 2 2 1 agi7 sta7 dmin49 dmax74 speed3100",
    [776] = "13 31 26 3 2 15 agi6 dmin17 dmax33 speed1300 uniq1",
    [812] = "17 54 49 4 2 10 sta15 int29 spi9 dmin127 dmax191 speed3100",
    [862] = "11 50 45 3 4 0 sp7 heal7",
    [867] = "10 42 37 4 4 2 armor86 ap20 crit1",
    [868] = "21 43 38 4 2 4 armor100 defense5 dmin48 dmax90 speed2100",
    [942] = "11 52 47 4 4 0 spFrost21",
    [944] = "17 61 56 4 2 10 spFire36 spFrost36 dmin147 dmax221 speed3200",
    [1484] = "17 22 17 3 2 10 int8 spShadow11 dmin55 dmax83 speed3600",
    [1720] = "17 46 41 3 2 10 str9 spi18 spNature14 dmin109 dmax165 speed3400",
    [2039] = "11 29 24 3 4 0 sta8 int3 uniq1",
    [2040] = "14 48 43 3 4 6 sta10 armor1676 block2",
    [2569] = "8 13 8 2 4 1 sta2 armor17",  -- Linen Boots
    [2816] = "21 33 28 3 2 4 spShadow28 heal68 hpr12 dmin28 dmax52 speed2800",  -- Death Speaker Scepter
    [2911] = "6 23 18 3 4 1 sta3 int8 armor23",
    [2919] = "12 30 25 1 4 0 cls16 uniq1",
    [4130] = "12 50 0 2 4 0 dodge1",  -- Smotts' Compass
    [4318] = "10 26 21 2 4 1 spi7 armor25 sp5 heal5",  -- Gloves of Meditation
    [4320] = "8 25 20 3 4 1 sta4 int4 armor29 sp7 heal7",  -- Spidersilk Boots
    [5198] = "26 22 17 3 2 19 dmin20 dmax38 speed1300",  -- Cookie's Stirring Rod
    [5522] = "23 36 31 1 4 0 spellCrit1 uniq1",
    [5542] = "16 19 14 2 4 0 int3 armor16 sp2 heal2",  -- Pearl-clasped Cloak
    [6447] = "14 21 15 3 4 6 armor530 mpr2",  -- Worn Turtle Shell Shield
    [7348] = "10 25 20 2 4 2 armor53 crit1 parry-1",  -- Fletcher's Gloves
    [7757] = "17 37 32 3 2 10 sta7 int15 spArcane14 dmin80 dmax121 speed3100",
    [7950] = "5 42 0 2 4 2 agi7 armor115 hit1 cls8",
    [10021] = "5 45 40 3 4 1 int9 spi14 armor65 sp18 heal18",  -- Dreamweave Vest
    [10510] = "26 44 39 2 2 3 rap14 dmin41 dmax76 speed2900",  -- Mithril Heavy-bore Rifle
    [10751] = "1 54 0 3 4 1 agi5 sta9 int17 spi18 armor63",
    [10782] = "1 55 0 2 4 1 sta16 int15 armor58",
    [11662] = "6 54 49 3 4 1 sta10 int11 armor43 sp12 heal12 spellHit1",
    [12047] = "2 30 25 2 4 0",
    [12752] = "1 62 0 4 4 1 sta17 int20 armor78 spellCrit2 cls1488",
    [12998] = "3 25 20 3 4 1 int9 armor32 sp5 heal5",
    [13062] = "26 27 22 3 2 19 dmin36 dmax67 speed1900",
    [13094] = "11 30 25 3 4 0 sta1 int2 spi8 uniq1",
    [13106] = "9 31 26 3 4 1 str3 int8 armor21",
    [16732] = "7 61 56 3 4 4 str23 agi11 sta15 spi4 armor557 blockValue17",  -- Legplates of Valor
    [17741] = "20 51 46 3 4 1 armor73 spHoly29 mpr8",
    [19972] = "1 40 0 2 4 1 sta15 armor43",  -- Lucky Fishing Hat
    [249392] = "17 30 25 3 2 10 sta11 int11 sp34 heal34 dmin32 dmax49 speed2200",  -- Glimmering Staff
    [253885] = "6 15 10 3 4 1 sta3 int3 armor17 sp4 heal4",  -- Novice Arcanist's Sash
    [253887] = "6 15 10 3 4 1 int3 spi3 armor17 sp2 heal6",  -- Novice Ardent's Sash
    [253889] = "8 17 12 3 4 1 sta4 int3 armor23 sp3 heal9",  -- Pristine Boots
    [253891] = "8 17 12 3 4 1 sta4 int3 armor23 spFrost6",  -- Silky Boots
    [253893] = "8 17 12 3 4 1 sta4 int3 armor23 spFire6",  -- Flame Boots
    [253895] = "8 17 12 3 4 1 sta4 int3 armor23 spShadow6",  -- Shadow Boots
    [253897] = "8 17 12 3 4 1 sta4 int3 armor23 spArcane6",  -- Pearly Boots
    [253899] = "8 17 12 3 4 1 sta4 int3 armor23 spHoly6",  -- Shining Boots
    [253901] = "20 20 15 3 4 1 sta4 int5 spi3 armor37 sp5 heal13",  -- Filigreed Pristine Gown
    [253903] = "5 20 15 3 4 1 sta4 int5 spi3 armor37 spFrost9",  -- Filigreed Silky Gown
    [253905] = "5 20 15 3 4 1 sta4 int5 spi3 armor37 spFire9",  -- Filigreed Flame Gown
    [253907] = "5 20 15 3 4 1 sta4 int5 spi3 armor37 spShadow9",  -- Filigreed Shadow Gown
    [253909] = "5 20 15 3 4 1 sta4 int5 spi3 armor37 spArcane9",  -- Filigreed Pearly Gown
    [253911] = "5 20 15 3 4 1 sta4 int5 spi3 armor37 spHoly9",  -- Filigreed Shining Gown
    [253913] = "10 20 15 3 4 1 sta4 int3 armor23 sp4 heal11",  -- Pristine Gloves
    [253915] = "10 20 15 3 4 1 sta4 int3 armor23 spFrost7",  -- Silky Gloves
    [253917] = "10 20 15 3 4 1 sta4 int3 armor23 spFire7",  -- Flame Gloves
    [253919] = "10 20 15 3 4 1 sta4 int3 armor23 spShadow7",  -- Shadow Gloves
    [253921] = "10 20 15 3 4 1 sta4 int3 armor23 spArcane7",  -- Pearly Gloves
    [253923] = "10 20 15 3 4 1 sta4 int3 armor23 spHoly7",  -- Shining Gloves
    [253925] = "6 22 17 3 4 1 sta5 int4 armor22 sp4 heal11",  -- Pristine Sash
    [253927] = "6 22 17 3 4 1 sta5 int4 armor22 spFrost7",  -- Silky Sash
    [253929] = "6 22 17 3 4 1 sta5 int4 armor22 spFire7",  -- Flame Sash
    [253931] = "6 22 17 3 4 1 sta5 int4 armor22 spShadow7",  -- Shadow Sash
    [253933] = "6 22 17 3 4 1 sta5 int4 armor22 spArcane7",  -- Pearly Sash
    [253935] = "6 22 17 3 4 1 sta5 int4 armor22 spHoly7",  -- Shining Sash
    [253937] = "7 25 20 3 4 1 sta5 int6 spi4 armor37 sp6 heal18",  -- Filigreed Pristine Leggings
    [253939] = "7 25 20 3 4 1 sta5 int6 spi4 armor37 spFrost11",  -- Filigreed Silky Leggings
    [253941] = "7 25 20 3 4 1 sta5 int6 spi4 armor37 spFire11",  -- Filigreed Flame Leggings
    [253943] = "7 25 20 3 4 1 sta5 int6 spi4 armor37 spShadow11",  -- Filigreed Shadow Leggings
    [253945] = "7 25 20 3 4 1 sta5 int6 spi4 armor37 spArcane11",  -- Filigreed Pearly Leggings
    [253947] = "7 25 20 3 4 1 sta5 int6 spi4 armor37 spHoly11",  -- Filigreed Shining Leggings
    [253949] = "1 25 20 3 4 1 sta10 armor35 sp6 heal18",  -- Pristine Circlet
    [253951] = "1 25 20 3 4 1 sta10 armor35 spFrost11",  -- Silky Circlet
    [253953] = "1 25 20 3 4 1 sta10 armor35 spFire11",  -- Flame Circlet
    [253955] = "1 25 20 3 4 1 sta10 armor35 spShadow11",  -- Shadow Circlet
    [253957] = "1 25 20 3 4 1 sta10 armor35 spArcane11",  -- Pearly Circlet
    [253959] = "1 25 20 3 4 1 sta10 armor35 spHoly11",  -- Shining Circlet
    [253961] = "5 27 22 3 4 1 sta6 int7 spi4 armor45 sp7 heal20",  -- Pristine Gown
    [253963] = "5 27 22 3 4 1 sta6 int7 spi4 armor45 spFrost13",  -- Silky Gown
    [253965] = "5 27 22 3 4 1 sta6 int7 spi4 armor45 spFire13",  -- Flame Gown
    [253967] = "5 27 22 3 4 1 sta6 int7 spi4 armor45 spShadow13",  -- Shadow Gown
    [253969] = "5 27 22 3 4 1 sta6 int7 spi4 armor45 spArcane13",  -- Pearly Gown
    [253971] = "5 27 22 3 4 1 sta6 int7 spi4 armor45 spHoly13",  -- Shining Gown
    [253975] = "1 30 25 3 4 1 sta12 armor38 sp8 heal22",  -- Filigreed Pristine Circlet
    [253977] = "1 30 25 3 4 1 sta12 armor38 spFrost14",  -- Filigreed Silky Circlet
    [253979] = "1 30 25 3 4 1 sta12 armor38 spFire14",  -- Filigreed Flame Circlet
    [253981] = "1 30 25 3 4 1 sta12 armor38 spShadow14",  -- Filigreed Shadow Circlet
    [253983] = "1 30 25 3 4 1 sta12 armor38 spArcane14",  -- Filigreed Pearly Circlet
    [253985] = "1 30 25 3 4 1 sta12 armor38 spHoly14",  -- Filigreed Shining Circlet
    [253987] = "7 30 25 3 4 1 sta7 int7 spi5 armor41 sp7 heal22",  -- Pristine Leggings
    [253989] = "7 30 25 3 4 1 sta7 int7 spi5 armor41 spFrost14",  -- Silky Leggings
    [253991] = "7 30 25 3 4 1 sta7 int7 spi5 armor41 spFire14",  -- Flame Leggings
    [253993] = "7 30 25 3 4 1 sta7 int7 spi5 armor41 spShadow14",  -- Shadow Leggings
    [253995] = "7 30 25 3 4 1 sta7 int7 spi5 armor41 spArcane14",  -- Pearly Leggings
    [253997] = "7 30 25 3 4 1 sta7 int7 spi5 armor41 spHoly14",  -- Shining Leggings
    [253999] = "7 35 30 2 4 1 spi11 armor41 sp5 heal15",  -- Earthen Leggings
    [254001] = "8 35 30 3 4 1 sta6 int7 spi4 armor35 sp7 heal20",  -- Gilded Slippers
    [254003] = "8 35 30 3 4 1 sta6 int7 spi4 armor35 spFrost13",  -- Frothing Slippers
    [254005] = "8 35 30 3 4 1 sta6 int7 spi4 armor35 spFire13",  -- Fiery Slippers
    [254007] = "8 35 30 3 4 1 sta6 int7 spi4 armor35 spShadow13",  -- Black Slippers
    [254009] = "8 35 30 3 4 1 sta6 int7 spi4 armor35 spArcane13",  -- Golden Slippers
    [254011] = "8 35 30 3 4 1 sta6 int7 spi4 armor35 spHoly13",  -- Radiant Slippers
    [254013] = "8 36 31 2 4 1 spi7 armor33 sp24 heal18",  -- Earthen Silk Slippers
    [254015] = "1 37 32 2 4 1 spi10 armor40 sp8 heal22",  -- Earthen Silk Hood
    [254017] = "10 39 34 2 4 1 spi8 armor32 sp6 heal18",  -- Earthen Silk Gloves
    [254019] = "9 40 35 2 4 1 spi5 armor23 sp4 heal10",  -- Earthen Silk Cuffs
    [254021] = "10 40 35 3 4 1 sta9 int7 armor36 sp8 heal22",  -- Gilded Handwraps
    [254023] = "10 40 35 3 4 1 sta9 int7 armor36 spFrost14",  -- Frothing Handwraps
    [254025] = "10 40 35 3 4 1 sta9 int7 armor36 spFire14",  -- Fiery Handwraps
    [254027] = "10 40 35 3 4 1 sta9 int7 armor36 spShadow14",  -- Black Handwraps
    [254029] = "10 40 35 3 4 1 sta9 int7 armor36 spArcane14",  -- Golden Handwraps
    [254031] = "10 40 35 3 4 1 sta9 int7 armor36 spHoly14",  -- Radiant Handwraps
    [254033] = "3 41 36 2 4 1 spi8 armor40 sp6 heal18",  -- Earthen Silk Shoulders
    [254037] = "6 45 40 3 4 1 sta8 int8 spi6 armor37 sp8 heal22",  -- Gilded Cord
    [254039] = "6 45 40 3 4 1 sta8 int8 spi6 armor37 spFrost14",  -- Frothing Cord
    [254041] = "6 45 40 3 4 1 sta8 int8 spi6 armor37 spFire14",  -- Fiery Cord
    [254043] = "6 45 40 3 4 1 sta8 int8 spi6 armor37 spShadow14",  -- Black Cord
    [254045] = "6 45 40 3 4 1 sta8 int8 spi6 armor37 spArcane14",  -- Golden Cord
    [254047] = "6 45 40 3 4 1 sta8 int8 spi6 armor37 spHoly14",  -- Radiant Cord
    [254049] = "3 47 42 3 4 1 sta8 int8 spi6 armor51 sp9 heal26",  -- Nethergeld Shoulders
    [254051] = "3 47 42 3 4 1 sta8 int8 spi6 armor51 spFrost17",  -- Netherfroth Shoulders
    [254053] = "3 47 42 3 4 1 sta8 int8 spi6 armor51 spFire17",  -- Netherflame Shoulders
    [254055] = "3 47 42 3 4 1 sta8 int8 spi6 armor51 spShadow17",  -- Netherpearl Shoulders
    [254057] = "3 47 42 3 4 1 sta8 int8 spi6 armor51 spArcane17",  -- Nethershine Shoulders
    [254059] = "3 47 42 3 4 1 sta8 int8 spi6 armor51 spHoly17",  -- Netherlight Shoulders
}

-- English names, for reading this file only. The addon asks the client.
F.EN_NAMES = {
    [744] = "Thunderbrew's Boot Flask",
    [2569] = "Linen Boots",
    [2816] = "Death Speaker Scepter",
    [4130] = "Smotts' Compass",
    [4318] = "Gloves of Meditation",
    [4320] = "Spidersilk Boots",
    [5198] = "Cookie's Stirring Rod",
    [5542] = "Pearl-clasped Cloak",
    [6447] = "Worn Turtle Shell Shield",
    [7348] = "Fletcher's Gloves",
    [10021] = "Dreamweave Vest",
    [10510] = "Mithril Heavy-bore Rifle",
    [16732] = "Legplates of Valor",
    [19972] = "Lucky Fishing Hat",
    [249392] = "Glimmering Staff",
    [253885] = "Novice Arcanist's Sash",
    [253887] = "Novice Ardent's Sash",
    [253889] = "Pristine Boots",
    [253891] = "Silky Boots",
    [253893] = "Flame Boots",
    [253895] = "Shadow Boots",
    [253897] = "Pearly Boots",
    [253899] = "Shining Boots",
    [253901] = "Filigreed Pristine Gown",
    [253903] = "Filigreed Silky Gown",
    [253905] = "Filigreed Flame Gown",
    [253907] = "Filigreed Shadow Gown",
    [253909] = "Filigreed Pearly Gown",
    [253911] = "Filigreed Shining Gown",
    [253913] = "Pristine Gloves",
    [253915] = "Silky Gloves",
    [253917] = "Flame Gloves",
    [253919] = "Shadow Gloves",
    [253921] = "Pearly Gloves",
    [253923] = "Shining Gloves",
    [253925] = "Pristine Sash",
    [253927] = "Silky Sash",
    [253929] = "Flame Sash",
    [253931] = "Shadow Sash",
    [253933] = "Pearly Sash",
    [253935] = "Shining Sash",
    [253937] = "Filigreed Pristine Leggings",
    [253939] = "Filigreed Silky Leggings",
    [253941] = "Filigreed Flame Leggings",
    [253943] = "Filigreed Shadow Leggings",
    [253945] = "Filigreed Pearly Leggings",
    [253947] = "Filigreed Shining Leggings",
    [253949] = "Pristine Circlet",
    [253951] = "Silky Circlet",
    [253953] = "Flame Circlet",
    [253955] = "Shadow Circlet",
    [253957] = "Pearly Circlet",
    [253959] = "Shining Circlet",
    [253961] = "Pristine Gown",
    [253963] = "Silky Gown",
    [253965] = "Flame Gown",
    [253967] = "Shadow Gown",
    [253969] = "Pearly Gown",
    [253971] = "Shining Gown",
    [253975] = "Filigreed Pristine Circlet",
    [253977] = "Filigreed Silky Circlet",
    [253979] = "Filigreed Flame Circlet",
    [253981] = "Filigreed Shadow Circlet",
    [253983] = "Filigreed Pearly Circlet",
    [253985] = "Filigreed Shining Circlet",
    [253987] = "Pristine Leggings",
    [253989] = "Silky Leggings",
    [253991] = "Flame Leggings",
    [253993] = "Shadow Leggings",
    [253995] = "Pearly Leggings",
    [253997] = "Shining Leggings",
    [253999] = "Earthen Leggings",
    [254001] = "Gilded Slippers",
    [254003] = "Frothing Slippers",
    [254005] = "Fiery Slippers",
    [254007] = "Black Slippers",
    [254009] = "Golden Slippers",
    [254011] = "Radiant Slippers",
    [254013] = "Earthen Silk Slippers",
    [254015] = "Earthen Silk Hood",
    [254017] = "Earthen Silk Gloves",
    [254019] = "Earthen Silk Cuffs",
    [254021] = "Gilded Handwraps",
    [254023] = "Frothing Handwraps",
    [254025] = "Fiery Handwraps",
    [254027] = "Black Handwraps",
    [254029] = "Golden Handwraps",
    [254031] = "Radiant Handwraps",
    [254033] = "Earthen Silk Shoulders",
    [254037] = "Gilded Cord",
    [254039] = "Frothing Cord",
    [254041] = "Fiery Cord",
    [254043] = "Black Cord",
    [254045] = "Golden Cord",
    [254047] = "Radiant Cord",
    [254049] = "Nethergeld Shoulders",
    [254051] = "Netherfroth Shoulders",
    [254053] = "Netherflame Shoulders",
    [254055] = "Netherpearl Shoulders",
    [254057] = "Nethershine Shoulders",
    [254059] = "Netherlight Shoulders",
}

-- Localised names as the player's own client reported them, out of
-- ForeverPilotCharDB.recipes. This is where the 253975 / 253979 name
-- collision is visible: two different items, one name.
F.RU_NAMES = {
    [2569] = "Льняные сапоги",
    [4318] = "Перчатки Медитации",
    [4320] = "Сапоги из паучьего шелка",
    [5542] = "Плащ с перламутровыми застежками",
    [10021] = "Жилет из ткани Грез",
    [249392] = "Мерцающий посох",
    [253885] = "Кушак начинающего чародея",
    [253887] = "Кушак начинающего ревнителя",
    [253889] = "Безупречные сапоги",
    [253891] = "Шелковые сапоги",
    [253893] = "Пламенные сапоги",
    [253895] = "Теневые сапоги",
    [253897] = "Жемчужные сапоги",
    [253899] = "Сияющие сапоги",
    [253901] = "Расшитое безупречное одеяние",
    [253903] = "Расшитое шелковое одеяние",
    [253905] = "Расшитое пламенное одеяние",
    [253907] = "Расшитое теневое одеяние",
    [253909] = "Расшитое жемчужное одеяние",
    [253911] = "Расшитое сияющее одеяние",
    [253913] = "Безупречные перчатки",
    [253915] = "Шелковые перчатки",
    [253917] = "Пламенные перчатки",
    [253919] = "Теневые перчатки",
    [253921] = "Жемчужные перчатки",
    [253923] = "Сияющие перчатки",
    [253925] = "Безупречный кушак",
    [253927] = "Шелковый кушак",
    [253929] = "Пламенный кушак",
    [253931] = "Теневой кушак",
    [253933] = "Жемчужный кушак",
    [253935] = "Сияющий кушак",
    [253937] = "Расшитые безупречные поножи",
    [253939] = "Расшитые шелковые поножи",
    [253941] = "Расшитые пламенные поножи",
    [253943] = "Расшитые теневые поножи",
    [253945] = "Расшитые жемчужные поножи",
    [253947] = "Расшитые сияющие поножи",
    [253949] = "Безупречный венец",
    [253951] = "Шелковый венец",
    [253953] = "Пламенный венец",
    [253955] = "Теневой венец",
    [253957] = "Жемчужный венец",
    [253959] = "Сияющий венец",
    [253961] = "Безупречное одеяние",
    [253963] = "Шелковое одеяние",
    [253965] = "Пламенное одеяние",
    [253967] = "Теневое одеяние",
    [253969] = "Жемчужное одеяние",
    [253971] = "Сияющее одеяние",
    [253975] = "Расшитый безупречный венец",
    [253977] = "Расшитый шелковый венец",
    [253979] = "Расшитый безупречный венец",
    [253981] = "Расшитый теневой венец",
    [253983] = "Расшитый жемчужный венец",
    [253985] = "Расшитый сияющий венец",
    [253987] = "Безупречные поножи",
    [253989] = "Шелковые поножи",
    [253991] = "Пламенные поножи",
    [253993] = "Теневые поножи",
    [253995] = "Жемчужные поножи",
    [253997] = "Сияющие поножи",
    [253999] = "Поножи земельника",
    [254001] = "Золоченые туфли",
    [254003] = "Пенящиеся туфли",
    [254005] = "Огненные туфли",
    [254007] = "Черные туфли",
    [254009] = "Золотые туфли",
    [254011] = "Светозарные туфли",
    [254013] = "Шелковые туфли земельника",
    [254015] = "Шелковый капюшон земельника",
    [254017] = "Шелковые перчатки земельника",
    [254019] = "Шелковые манжеты земельника",
    [254021] = "Золоченые повязки",
    [254023] = "Пенящиеся повязки",
    [254025] = "Огненные повязки",
    [254027] = "Черные повязки",
    [254029] = "Золотые повязки",
    [254031] = "Светозарные повязки",
    [254033] = "Шелковые наплечники земельника",
    [254037] = "Золоченый шнурованный ремень",
    [254039] = "Пенящийся шнурованный ремень",
    [254041] = "Огненный шнурованный ремень",
    [254043] = "Черный шнурованный ремень",
    [254045] = "Золотой шнурованный ремень",
    [254047] = "Светозарный шнурованный ремень",
    [254049] = "Наплечники позолоты Пустоты",
    [254051] = "Наплечники пены Пустоты",
    [254053] = "Наплечники пламени Пустоты",
    [254055] = "Наплечники жемчуга Пустоты",
    [254057] = "Наплечники сияния Пустоты",
    [254059] = "Наплечники света Пустоты",
}

-- What the mage is wearing, from SYNDICATOR_DATA.
F.EQUIPPED = {
    BACK = 5542,  -- Pearl-clasped Cloak
    CHEST = 253969,  -- Pearly Gown
    FEET = 4320,  -- Spidersilk Boots
    FINGER1 = 2039,
    FINGER2 = 13094,
    HANDS = 4318,  -- Gloves of Meditation
    HEAD = 253975,  -- Filigreed Pristine Circlet
    LEGS = 253995,  -- Pearly Leggings
    MAINHAND = 249392,  -- Glimmering Staff
    NECK = 12047,
    RANGED = 13062,
    SHIRT = 16060,
    SHOULDER = 12998,
    WAIST = 2911,
    WRIST = 13106,
}

-- Recipes from the player's own cache that produce fixture items.
F.RECIPES = {
    { id = 2386, output = 2569, outputQty = 1, profession = "Портняжное дело", name = "Льняные сапоги",
      diff = "trivial", category = "Обувь", reagents = { { itemID = 2996, qty = 3 }, { itemID = 2320, qty = 1 }, { itemID = 2318, qty = 1 } } },
    { id = 3852, output = 4318, outputQty = 1, profession = "Портняжное дело", name = "Перчатки Медитации",
      diff = "trivial", category = "Перчатки", reagents = { { itemID = 2997, qty = 4 }, { itemID = 2321, qty = 3 }, { itemID = 3383, qty = 1 } } },
    { id = 3855, output = 4320, outputQty = 1, profession = "Портняжное дело", name = "Сапоги из паучьего шелка",
      diff = "trivial", category = "Обувь", reagents = { { itemID = 4305, qty = 2 }, { itemID = 2319, qty = 4 }, { itemID = 3182, qty = 4 }, { itemID = 5500, qty = 1 } } },
    { id = 6521, output = 5542, outputQty = 1, profession = "Портняжное дело", name = "Плащ с перламутровыми застежками",
      diff = "trivial", category = "Плащи", reagents = { { itemID = 2997, qty = 3 }, { itemID = 2321, qty = 2 }, { itemID = 5498, qty = 1 } } },
    { id = 12070, output = 10021, outputQty = 1, profession = "Портняжное дело", name = "Жилет из ткани Грез",
      diff = "easy", category = "Одеяния и жилеты", reagents = { { itemID = 4339, qty = 6 }, { itemID = 8153, qty = 6 }, { itemID = 10286, qty = 2 }, { itemID = 8343, qty = 2 } } },
    { id = 1248703, output = 249392, outputQty = 1, profession = "Наложение чар", name = "Мерцающий посох",
      diff = "trivial", category = "Посохи", reagents = { { itemID = 11084, qty = 4 }, { itemID = 10978, qty = 2 }, { itemID = 11291, qty = 4 }, { itemID = 11082, qty = 1 }, { itemID = 10940, qty = 5 }, { itemID = 249391, qty = 3 } } },
    { id = 1257368, output = 253885, outputQty = 1, profession = "Портняжное дело", name = "Кушак начинающего чародея",
      diff = "trivial", category = "Пояса", reagents = { { itemID = 2996, qty = 8 }, { itemID = 2321, qty = 2 }, { itemID = 2455, qty = 2 } } },
    { id = 1257369, output = 253887, outputQty = 1, profession = "Портняжное дело", name = "Кушак начинающего ревнителя",
      diff = "trivial", category = "Пояса", reagents = { { itemID = 2996, qty = 12 }, { itemID = 2321, qty = 2 }, { itemID = 118, qty = 2 } } },
    { id = 1257371, output = 253891, outputQty = 1, profession = "Портняжное дело", name = "Шелковые сапоги",
      diff = "trivial", category = "Обувь", reagents = { { itemID = 2997, qty = 8 }, { itemID = 2321, qty = 2 }, { itemID = 249409, qty = 2 }, { itemID = 3182, qty = 1 } } },
    { id = 1257376, output = 253901, outputQty = 1, profession = "Портняжное дело", name = "Расшитое безупречное одеяние",
      diff = "trivial", category = "Одеяния и жилеты", reagents = { { itemID = 2997, qty = 8 }, { itemID = 2321, qty = 4 }, { itemID = 249409, qty = 2 }, { itemID = 249427, qty = 2 } } },
    { id = 1257377, output = 253903, outputQty = 1, profession = "Портняжное дело", name = "Расшитое шелковое одеяние",
      diff = "trivial", category = "Одеяния и жилеты", reagents = { { itemID = 2997, qty = 8 }, { itemID = 2321, qty = 4 }, { itemID = 249409, qty = 2 }, { itemID = 3182, qty = 2 } } },
    { id = 1257378, output = 253905, outputQty = 1, profession = "Портняжное дело", name = "Расшитое пламенное одеяние",
      diff = "trivial", category = "Одеяния и жилеты", reagents = { { itemID = 2997, qty = 8 }, { itemID = 2321, qty = 4 }, { itemID = 249409, qty = 2 }, { itemID = 6371, qty = 2 } } },
    { id = 1257379, output = 253907, outputQty = 1, profession = "Портняжное дело", name = "Расшитое теневое одеяние",
      diff = "trivial", category = "Одеяния и жилеты", reagents = { { itemID = 2997, qty = 8 }, { itemID = 2321, qty = 4 }, { itemID = 249409, qty = 2 }, { itemID = 1210, qty = 2 } } },
    { id = 1257380, output = 253909, outputQty = 1, profession = "Портняжное дело", name = "Расшитое жемчужное одеяние",
      diff = "trivial", category = "Одеяния и жилеты", reagents = { { itemID = 2997, qty = 8 }, { itemID = 2321, qty = 4 }, { itemID = 249409, qty = 2 }, { itemID = 5498, qty = 2 } } },
    { id = 1257381, output = 253911, outputQty = 1, profession = "Портняжное дело", name = "Расшитое сияющее одеяние",
      diff = "trivial", category = "Одеяния и жилеты", reagents = { { itemID = 2997, qty = 8 }, { itemID = 2321, qty = 4 }, { itemID = 249409, qty = 2 }, { itemID = 249391, qty = 2 } } },
    { id = 1257383, output = 253915, outputQty = 1, profession = "Портняжное дело", name = "Шелковые перчатки",
      diff = "trivial", category = "Перчатки", reagents = { { itemID = 2997, qty = 6 }, { itemID = 2321, qty = 4 }, { itemID = 249409, qty = 3 }, { itemID = 3182, qty = 2 } } },
    { id = 1257392, output = 253933, outputQty = 1, profession = "Портняжное дело", name = "Жемчужный кушак",
      diff = "trivial", category = "Пояса", reagents = { { itemID = 4305, qty = 8 }, { itemID = 2321, qty = 4 }, { itemID = 249409, qty = 3 }, { itemID = 5498, qty = 3 } } },
    { id = 1257394, output = 253937, outputQty = 1, profession = "Портняжное дело", name = "Расшитые безупречные поножи",
      diff = "trivial", category = "Поножи", reagents = { { itemID = 4305, qty = 8 }, { itemID = 2321, qty = 4 }, { itemID = 249409, qty = 2 }, { itemID = 249427, qty = 4 } } },
    { id = 1257395, output = 253939, outputQty = 1, profession = "Портняжное дело", name = "Расшитые шелковые поножи",
      diff = "trivial", category = "Поножи", reagents = { { itemID = 4305, qty = 8 }, { itemID = 2321, qty = 4 }, { itemID = 249409, qty = 2 }, { itemID = 3182, qty = 4 } } },
    { id = 1257396, output = 253941, outputQty = 1, profession = "Портняжное дело", name = "Расшитые пламенные поножи",
      diff = "trivial", category = "Поножи", reagents = { { itemID = 4305, qty = 8 }, { itemID = 2321, qty = 4 }, { itemID = 249409, qty = 2 }, { itemID = 6371, qty = 4 } } },
    { id = 1257397, output = 253943, outputQty = 1, profession = "Портняжное дело", name = "Расшитые теневые поножи",
      diff = "trivial", category = "Поножи", reagents = { { itemID = 4305, qty = 8 }, { itemID = 2321, qty = 4 }, { itemID = 249409, qty = 2 }, { itemID = 1210, qty = 4 } } },
    { id = 1257398, output = 253945, outputQty = 1, profession = "Портняжное дело", name = "Расшитые жемчужные поножи",
      diff = "trivial", category = "Поножи", reagents = { { itemID = 4305, qty = 8 }, { itemID = 2321, qty = 4 }, { itemID = 249409, qty = 2 }, { itemID = 5498, qty = 4 } } },
    { id = 1257399, output = 253947, outputQty = 1, profession = "Портняжное дело", name = "Расшитые сияющие поножи",
      diff = "trivial", category = "Поножи", reagents = { { itemID = 4305, qty = 8 }, { itemID = 2321, qty = 4 }, { itemID = 249409, qty = 2 }, { itemID = 249391, qty = 4 } } },
    { id = 1257401, output = 253951, outputQty = 1, profession = "Портняжное дело", name = "Шелковый венец",
      diff = "trivial", category = "Капюшоны", reagents = { { itemID = 4305, qty = 10 }, { itemID = 4291, qty = 2 }, { itemID = 249409, qty = 4 }, { itemID = 3182, qty = 4 }, { itemID = 2842, qty = 1 }, { itemID = 11082, qty = 2 } } },
    { id = 1257404, output = 253957, outputQty = 1, profession = "Портняжное дело", name = "Жемчужный венец",
      diff = "trivial", category = "Капюшоны", reagents = { { itemID = 4305, qty = 10 }, { itemID = 4291, qty = 2 }, { itemID = 249409, qty = 4 }, { itemID = 5498, qty = 4 }, { itemID = 2842, qty = 1 }, { itemID = 11082, qty = 2 } } },
    { id = 1257410, output = 253969, outputQty = 1, profession = "Портняжное дело", name = "Жемчужное одеяние",
      diff = "trivial", category = "Одеяния и жилеты", reagents = { { itemID = 4305, qty = 12 }, { itemID = 4291, qty = 2 }, { itemID = 249409, qty = 6 }, { itemID = 5498, qty = 6 }, { itemID = 2842, qty = 2 }, { itemID = 11082, qty = 2 } } },
    { id = 1257413, output = 253975, outputQty = 1, profession = "Портняжное дело", name = "Расшитый безупречный венец",
      diff = "trivial", category = "Капюшоны", reagents = { { itemID = 4305, qty = 8 }, { itemID = 2321, qty = 4 }, { itemID = 249409, qty = 2 }, { itemID = 249427, qty = 6 } } },
    { id = 1257414, output = 253977, outputQty = 1, profession = "Портняжное дело", name = "Расшитый шелковый венец",
      diff = "trivial", category = "Капюшоны", reagents = { { itemID = 4305, qty = 8 }, { itemID = 2321, qty = 4 }, { itemID = 249409, qty = 2 }, { itemID = 3182, qty = 6 } } },
    { id = 1257415, output = 253979, outputQty = 1, profession = "Портняжное дело", name = "Расшитый безупречный венец",
      diff = "trivial", category = "Капюшоны", reagents = { { itemID = 4305, qty = 8 }, { itemID = 2321, qty = 4 }, { itemID = 249409, qty = 2 }, { itemID = 6371, qty = 6 } } },
    { id = 1257416, output = 253981, outputQty = 1, profession = "Портняжное дело", name = "Расшитый теневой венец",
      diff = "trivial", category = "Капюшоны", reagents = { { itemID = 4305, qty = 8 }, { itemID = 2321, qty = 4 }, { itemID = 249409, qty = 2 }, { itemID = 1210, qty = 6 } } },
    { id = 1257417, output = 253983, outputQty = 1, profession = "Портняжное дело", name = "Расшитый жемчужный венец",
      diff = "trivial", category = "Капюшоны", reagents = { { itemID = 4305, qty = 8 }, { itemID = 2321, qty = 4 }, { itemID = 249409, qty = 2 }, { itemID = 5498, qty = 6 } } },
    { id = 1257418, output = 253985, outputQty = 1, profession = "Портняжное дело", name = "Расшитый сияющий венец",
      diff = "trivial", category = "Капюшоны", reagents = { { itemID = 4305, qty = 8 }, { itemID = 2321, qty = 4 }, { itemID = 249409, qty = 2 }, { itemID = 249391, qty = 6 } } },
    { id = 1257423, output = 253995, outputQty = 1, profession = "Портняжное дело", name = "Жемчужные поножи",
      diff = "trivial", category = "Поножи", reagents = { { itemID = 4305, qty = 14 }, { itemID = 2321, qty = 3 }, { itemID = 249409, qty = 8 }, { itemID = 5498, qty = 8 }, { itemID = 2842, qty = 2 }, { itemID = 11082, qty = 3 } } },
    { id = 1257426, output = 254001, outputQty = 1, profession = "Портняжное дело", name = "Золоченые туфли",
      diff = "trivial", category = "Обувь", reagents = { { itemID = 4339, qty = 8 }, { itemID = 8343, qty = 4 }, { itemID = 249430, qty = 2 }, { itemID = 249409, qty = 2 }, { itemID = 3577, qty = 2 } } },
    { id = 1257427, output = 254003, outputQty = 1, profession = "Портняжное дело", name = "Пенящиеся туфли",
      diff = "trivial", category = "Обувь", reagents = { { itemID = 4339, qty = 8 }, { itemID = 8343, qty = 4 }, { itemID = 249430, qty = 2 }, { itemID = 249409, qty = 2 }, { itemID = 7079, qty = 2 } } },
    { id = 1257428, output = 254005, outputQty = 1, profession = "Портняжное дело", name = "Огненные туфли",
      diff = "trivial", category = "Обувь", reagents = { { itemID = 4339, qty = 8 }, { itemID = 8343, qty = 4 }, { itemID = 249430, qty = 2 }, { itemID = 249409, qty = 2 }, { itemID = 7077, qty = 2 } } },
    { id = 1257429, output = 254007, outputQty = 1, profession = "Портняжное дело", name = "Черные туфли",
      diff = "trivial", category = "Обувь", reagents = { { itemID = 4339, qty = 8 }, { itemID = 8343, qty = 4 }, { itemID = 249430, qty = 2 }, { itemID = 249409, qty = 2 }, { itemID = 7971, qty = 2 } } },
    { id = 1257430, output = 254009, outputQty = 1, profession = "Портняжное дело", name = "Золотые туфли",
      diff = "trivial", category = "Обувь", reagents = { { itemID = 4339, qty = 8 }, { itemID = 8343, qty = 4 }, { itemID = 249430, qty = 2 }, { itemID = 249409, qty = 2 }, { itemID = 13926, qty = 2 } } },
    { id = 1257431, output = 254011, outputQty = 1, profession = "Портняжное дело", name = "Светозарные туфли",
      diff = "trivial", category = "Обувь", reagents = { { itemID = 4339, qty = 8 }, { itemID = 8343, qty = 4 }, { itemID = 249430, qty = 2 }, { itemID = 249409, qty = 2 }, { itemID = 11178, qty = 2 } } },
    { id = 1257444, output = 254037, outputQty = 1, profession = "Портняжное дело", name = "Золоченый шнурованный ремень",
      diff = "trivial", category = "Пояса", reagents = { { itemID = 4339, qty = 28 }, { itemID = 8343, qty = 4 }, { itemID = 249430, qty = 6 }, { itemID = 249409, qty = 4 }, { itemID = 3577, qty = 12 } } },
    { id = 1257445, output = 254039, outputQty = 1, profession = "Портняжное дело", name = "Пенящийся шнурованный ремень",
      diff = "trivial", category = "Пояса", reagents = { { itemID = 4339, qty = 28 }, { itemID = 8343, qty = 4 }, { itemID = 249430, qty = 6 }, { itemID = 249409, qty = 4 }, { itemID = 7079, qty = 12 } } },
    { id = 1257446, output = 254041, outputQty = 1, profession = "Портняжное дело", name = "Огненный шнурованный ремень",
      diff = "trivial", category = "Пояса", reagents = { { itemID = 4339, qty = 28 }, { itemID = 8343, qty = 4 }, { itemID = 249430, qty = 6 }, { itemID = 249409, qty = 4 }, { itemID = 7077, qty = 12 } } },
    { id = 1257447, output = 254043, outputQty = 1, profession = "Портняжное дело", name = "Черный шнурованный ремень",
      diff = "trivial", category = "Пояса", reagents = { { itemID = 4339, qty = 28 }, { itemID = 8343, qty = 4 }, { itemID = 249430, qty = 6 }, { itemID = 249409, qty = 4 }, { itemID = 7971, qty = 12 } } },
    { id = 1257448, output = 254045, outputQty = 1, profession = "Портняжное дело", name = "Золотой шнурованный ремень",
      diff = "trivial", category = "Пояса", reagents = { { itemID = 4339, qty = 28 }, { itemID = 8343, qty = 4 }, { itemID = 249430, qty = 6 }, { itemID = 249409, qty = 4 }, { itemID = 13926, qty = 12 } } },
    { id = 1257449, output = 254047, outputQty = 1, profession = "Портняжное дело", name = "Светозарный шнурованный ремень",
      diff = "trivial", category = "Пояса", reagents = { { itemID = 4339, qty = 28 }, { itemID = 8343, qty = 4 }, { itemID = 249430, qty = 6 }, { itemID = 249409, qty = 4 }, { itemID = 11178, qty = 12 } } },
}

-- Mastercraft cost lots, verbatim. `c` is copper FOR THE WHOLE LOT -
-- its own Cost.lua says so: "c = copper for them all". `m` means the
-- player made it themselves, so it is their cost, not a market price.
F.COST_LOTS = {
    [2039] = { { c = 30000, q = 1, t = 1794749653, m = false } },
    [2320] = { { c = 48, q = 2, t = 1794885666, m = false } },
    [2569] = { { c = 425, q = 2, t = 1794885708, m = true }, { c = 154, q = 2, t = 1794163132, m = true } },
    [2911] = { { c = 1900, q = 1, t = 1794750104, m = false } },
    [4306] = { { c = 15718, q = 80, t = 1794641443, m = false }, { c = 9550, q = 50, t = 1794636182, m = false }, { c = 8322, q = 42, t = 1794563660, m = false }, { c = 31739, q = 160, t = 1794556367, m = false }, { c = 15920, q = 80, t = 1794555957, m = false } },
    [4318] = { { c = 1000, q = 1, t = 1794568273, m = false } },
    [4320] = { { c = 6635, q = 1, t = 1794557784, m = true } },
    [4338] = { { c = 124920, q = 250, t = 1794655454, m = false }, { c = 416725, q = 900, t = 1794643346, m = false } },
    [8343] = { { c = 16038, q = 6, t = 1794893832, m = false }, { c = 8019, q = 3, t = 1794892833, m = false }, { c = 56000, q = 20, t = 1794801101, m = false }, { c = 7198, q = 4, t = 1794741534, m = false } },
    [11137] = { { c = 13188, q = 12, t = 1794893829, m = false }, { c = 995, q = 1, t = 1794750509, m = false }, { c = 1894, q = 2, t = 1794679452, m = false }, { c = 45080, q = 40, t = 1794583380, m = false } },
    [12047] = { { c = 22899, q = 1, t = 1794749583, m = false } },
    [12998] = { { c = 14000, q = 1, t = 1794749759, m = false } },
    [13062] = { { c = 30000, q = 1, t = 1794749996, m = false } },
    [13094] = { { c = 6400, q = 1, t = 1794749631, m = false } },
    [13106] = { { c = 7048, q = 1, t = 1794750277, m = false } },
    [249392] = { { c = 41848, q = 1, t = 1794575139, m = true } },
    [253901] = { { c = 31761, q = 1, t = 1794893491, m = true } },
    [253937] = { { c = 35103, q = 1, t = 1794893474, m = true } },
    [253957] = { { c = 36689, q = 1, t = 1794565597, m = true } },
    [253969] = { { c = 50454, q = 1, t = 1794568225, m = true } },
    [253975] = { { c = 36101, q = 1, t = 1794893463, m = true } },
    [253995] = { { c = 65024, q = 1, t = 1794568871, m = true } },
}

-- ForeverPilotDB.priceHistory, verbatim: day stamp -> copper.
F.PRICE_HISTORY = {
    [2320] = { [20773] = 25, [20774] = 25 },
    [2569] = { [20773] = 300, [20774] = 300 },
    [4306] = { [20773] = 197, [20774] = 190 },
    [4318] = { [20773] = 1400, [20774] = 1400 },
    [4320] = { [20773] = 16600, [20774] = 16099 },
    [4338] = { [20773] = 484, [20774] = 470 },
    [5542] = { [20773] = 4599, [20774] = 4599 },
    [8343] = { [20773] = 2800, [20774] = 2673 },
    [10021] = { [20773] = 48900, [20774] = 39800 },
    [10290] = { [20773] = 4900, [20774] = 4895 },
    [11137] = { [20773] = 1199, [20774] = 1018 },
}

-- Parse one row into the shape Polestar.ItemDB.Get returns. The format is the
-- one its header documents; this is the test side of the same contract.
local UNTOKEN = { mpr = "mp5", hpr = "hp5" }
local HEADER_ONLY = { cls = true, uniq = true }

function F.Record(itemID)
    local s = F.ITEM_ROWS[itemID]
    if type(s) ~= "string" then return nil end
    local inv, ilvl, req, quality, class, sub =
        s:match("^(%d+) (%d+) (%d+) (%d+) (%d+) (%d+)")
    if not inv then return nil end
    local stats, dmin, dmax, speed = {}, nil, nil, nil
    for key, n in s:gmatch("(%a+)(%-?%d+)") do
        n = tonumber(n)
        if key == "dmin" then dmin = n
        elseif key == "dmax" then dmax = n
        elseif key == "speed" then speed = n
        elseif not HEADER_ONLY[key] then stats[UNTOKEN[key] or key] = n end
    end
    if dmin and dmax and speed and speed > 0 then
        stats.dps = math.floor((dmin + dmax) / 2 / (speed / 1000) * 10 + 0.5) / 10
    end
    return {
        id = itemID, inv = tonumber(inv), ilvl = tonumber(ilvl),
        req = tonumber(req), quality = tonumber(quality),
        class = tonumber(class), subclass = tonumber(sub),
        stats = stats, dmin = dmin, dmax = dmax, speed = speed,
    }
end

function F.Stats(itemID)
    local rec = F.Record(itemID)
    return rec and rec.stats or nil
end

-- inv slot id -> the client's INVTYPE string, so a fixture item can be handed
-- to the addon exactly as the client would hand it over.
F.INV_TO_EQUIPLOC = {
    [1] = "INVTYPE_HEAD", [2] = "INVTYPE_NECK", [3] = "INVTYPE_SHOULDER",
    [4] = "INVTYPE_BODY", [5] = "INVTYPE_CHEST", [6] = "INVTYPE_WAIST",
    [7] = "INVTYPE_LEGS", [8] = "INVTYPE_FEET", [9] = "INVTYPE_WRIST",
    [10] = "INVTYPE_HAND", [11] = "INVTYPE_FINGER", [12] = "INVTYPE_TRINKET",
    [13] = "INVTYPE_WEAPON", [14] = "INVTYPE_SHIELD", [15] = "INVTYPE_RANGED",
    [16] = "INVTYPE_CLOAK", [17] = "INVTYPE_2HWEAPON", [18] = "INVTYPE_BAG",
    [19] = "INVTYPE_TABARD", [20] = "INVTYPE_ROBE",
    [21] = "INVTYPE_WEAPONMAINHAND", [22] = "INVTYPE_WEAPONOFFHAND",
    [23] = "INVTYPE_HOLDABLE", [25] = "INVTYPE_THROWN",
    [26] = "INVTYPE_RANGEDRIGHT",
}

-- Every stat token that appears in ANY row here. The mapping test asserts the
-- addon understands all of them, so deleting a mapping is caught.
function F.AllStatKeys()
    local seen = {}
    for id in pairs(F.ITEM_ROWS) do
        for key in pairs(F.Stats(id) or {}) do seen[key] = true end
    end
    return seen
end

return F
