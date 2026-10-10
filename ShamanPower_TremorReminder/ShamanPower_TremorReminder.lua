-- "First Surname" on WoW: Forever (SPCompat.UnitName); other clients unchanged
local UnitName = (SPCompat and SPCompat.UnitName) or UnitName
local GetTotemInfo = (SPCompat and SPCompat.GetTotemInfo) or GetTotemInfo  -- guarded on restricted clients
--[[
    ShamanPower_TremorReminder
    Proactive Tremor Totem reminder when targeting fear-casting mobs

    Shows a Tremor Totem icon when you target a mob known to cast fears,
    even before anyone in your party gets feared. Boss fights that fear
    bring it up at the pull too, targeted or not (inside dungeons and raids
    on WoW: Forever the only way: mob names are hidden there).
]]

local SP = ShamanPower
if not SP then return end

-- Only load for Shamans: nobody else can drop Tremor Totem
if select(2, UnitClass("player")) ~= "SHAMAN" then return end

-- Mark module as loaded
SP.TremorReminderLoaded = true

-- Localization
local L = LibStub("AceLocale-3.0"):GetLocale("ShamanPower")

-- Tremor Totem spell info
local TREMOR_TOTEM_NAME = SPCompat.SpellName(8143, "Tremor Totem")
local TREMOR_TOTEM_ICON = select(3, GetSpellInfo(8143)) or 136108

-- Default known fear-casting mobs (from Sweb's WeakAura + additions)
local DEFAULT_FEAR_CASTERS = {
    -- Classic Dungeons
    ["Scarlet Monk"] = true,
    ["Scarlet Champion"] = true,
    ["Atal'ai Witch Doctor"] = true,
    ["Thuzadin Shadowcaster"] = true,

    -- Classic Raids
    ["Onyxia"] = true,
    ["Magmadar"] = true,
}

if not SPCompat.FOREVER then
    local tbcFearCasters = {
        -- TBC Dungeons
        ["Nexus Terror"] = true,
        ["Sethekk Prophet"] = true,
        ["Nazan"] = true,
        ["Coilfang Ray"] = true,
        ["Coilfang Siren"] = true,
        ["Durnholde Warden"] = true,
        ["Ambassador Hellmaw"] = true,
        ["Fel Overseer"] = true,
        ["Shadowmoon Darkcaster"] = true,
        ["Warbringer O'mrogg"] = true,
        ["Rift Keeper"] = true,
        ["Mutate Fear-Shrieker"] = true,
        ["Bloodwarder Physician"] = true,
        ["Harbinger Skyriss"] = true,
        ["Bleeding Hollow Scryer"] = true,

        -- Karazhan
        ["Nightbane"] = true,
        ["The Big Bad Wolf"] = true,
        ["Spectral Charger"] = true,
        ["Dorothee"] = true,
        ["Roar"] = true,
        ["Concubine"] = true,

        -- Magtheridon's Lair
        ["Hellfire Warder"] = true,
        ["Hellfire Channeler"] = true,

        -- Serpentshrine Cavern
        ["Coilfang Priestess"] = true,
        ["Greyheart Tidecaller"] = true,

        -- Tempest Keep
        ["Tempest-Smith"] = true,
        ["Astromancer"] = true,

        -- Black Temple
        ["Illidari Heartseeker"] = true,
        ["Bonechewer Taskmaster"] = true,
        ["Dragonmaw Wind Reaver"] = true,
        ["Ashtongue Mystic"] = true,

        -- Hyjal Summit
        ["Banshee"] = true,
        ["Crypt Fiend"] = true,
        ["Anetheron"] = true, -- Sleep (sleep)
        ["Archimonde"] = true, -- Fear (fear)

        -- Sunwell Plateau
        ["Sunblade Vindicator"] = true,

    }
    for name, enabled in pairs(tbcFearCasters) do DEFAULT_FEAR_CASTERS[name] = enabled end
end

-- Vanilla fear/charm/sleep casters; keep these defaults off the Anniversary path.
if SPCompat.FOREVER then -- luacheck: globals WOW_PROJECT_ID WOW_PROJECT_MAINLINE
    local foreverFearCasters = {
        -- 185 fear / charm / sleep casters (what Tremor breaks), researched 2026-10-02 from the Forever client's
        -- own spell data, vmangos, cmangos and Wowhead Forever (each name checked against them).
        -- Horror (Death Coil) is left out: Tremor does not break it.
        -- In dungeons and raids the game hides mob names (measured): there only the bosses in FEAR_BOSS_ENCOUNTERS
        -- (below) count, at the pull.
        -- Wailing Caverns
        ["Deviate Dreadfang"] = true, -- Terrify (fear)
        ["Druid of the Fang"] = true, -- Druid's Slumber (sleep)
        ["Lady Anacondra"] = true, -- Sleep (sleep)
        ["Lord Cobrahn"] = true, -- Druid's Slumber (sleep)
        ["Lord Pythas"] = true, -- Sleep (sleep)
        ["Lord Serpentis"] = true, -- Sleep (sleep)
        ["Mutanus the Devourer"] = true, -- Terrify (fear); Naralex's Nightmare (sleep)

        -- Wailing Caverns (outer cave, outside the instance portal)
        ["Boahn"] = true, -- Druid's Slumber (sleep)

        -- The Deadmines
        ["Sneed's Shredder"] = true, -- Terrify (fear)

        -- Shadowfang Keep
        ["Sever"] = true, -- Intimidating Roar (fear)

        -- Blackfathom Deeps
        ["Blindlight Oracle"] = true, -- Fear (fear)
        ["Twilight Lord Kelris"] = true, -- Sleep (sleep)
        ["Twilight Shadowmage"] = true, -- Dominate Mind (charm)

        -- The Stockade
        ["Dextren Ward"] = true, -- Intimidating Shout (fear)

        -- Razorfen Kraul
        ["Death Speaker Jargba"] = true, -- Dominate Mind (charm)

        -- Scarlet Monastery - Graveyard
        ["Azshir the Sleepless"] = true, -- Terrify (fear)
        ["Scarlet Scryer"] = true, -- Sleep (sleep)

        -- Scarlet Monastery - Cathedral
        ["High Inquisitor Fairbanks"] = true, -- Sleep (sleep); Fear (fear)
        ["High Inquisitor Whitemane"] = true, -- Dominate Mind (charm)

        -- Razorfen Downs
        ["Lady Falther'ess"] = true, -- Dominate Mind (charm)
        ["Ragglesnout"] = true, -- Dominate Mind (charm)

        -- Uldaman
        ["Jadespine Basilisk"] = true, -- Crystalline Slumber (sleep)

        -- Zul'Farrak
        ["Shadowpriest Sezz'ziz"] = true, -- Psychic Scream (fear)

        -- Maraudon
        ["Princess Theradras"] = true, -- Repulsive Gaze (fear)

        -- The Temple of Atal'Hakkar
        ["Atal'ai Deathwalker"] = true, -- Fear (fear)
        ["Hukku's Succubus"] = true, -- Seduction (charm)
        ["Nightmare Wyrmkin"] = true, -- Sleep (sleep)

        -- Blackrock Depths
        ["High Interrogator Gerstahn"] = true, -- Psychic Scream (fear)
        ["Theldren"] = true, -- Intimidating Shout (fear)
        ["Va'jashni"] = true, -- Psychic Scream (fear)

        -- Lower Blackrock Spire
        ["Urok Doomhowl"] = true, -- Intimidating Roar (fear)

        -- Upper Blackrock Spire
        ["Mor Grayhoof"] = true, -- Sleep (sleep)
        ["The Beast"] = true, -- Terrifying Roar (fear)

        -- Dire Maul - East
        ["Wildspawn Felsworn"] = true, -- Fear (fear)

        -- Dire Maul - North
        ["Captain Kromcrush"] = true, -- Intimidating Shout (fear)
        ["Cho'Rush the Observer"] = true, -- Psychic Scream (fear)
        ["Gordok Captain"] = true, -- Fear (fear)

        -- Dire Maul - West
        ["Lord Hel'nurath"] = true, -- Sleep (sleep)
        ["Magister Kalendris"] = true, -- Dominate Mind (charm)

        -- Stratholme
        ["Balnazzar"] = true, -- Sleep (sleep); Psychic Scream (fear); Domination (charm)
        ["Balzaphon"] = true, -- Fear (fear)
        ["Grand Crusader Dathrohan"] = true, -- Sleep (sleep); Psychic Scream (fear); Domination (charm)
        ["Hearthsinger Forresten"] = true, -- Enchanting Lullaby (sleep)
        ["Postmaster Malown"] = true, -- Fear (fear)
        ["Rockwing Screecher"] = true, -- Terrifying Howl (fear)
        ["Sothos"] = true, -- Fear (fear)

        -- Scholomance
        ["Death Knight Darkreaver"] = true, -- Dominate Mind (charm)
        ["Kirtonos the Herald"] = true, -- Dominate Mind (charm)
        ["Lady Illucia Barov"] = true, -- Fear (fear); Dominate Mind (charm)
        ["Ras Frostwhisper"] = true, -- Fear (fear)
        ["Scholomance Neophyte"] = true, -- Fear (fear)

        -- The Hall of Thanes (Forever-new dungeon)
        ["Durgen Dirgehammer"] = true, -- Intimidating Shout (fear)

        -- Molten Core
        ["Flamewaker Protector"] = true, -- Dominate Mind (charm)
        ["Lucifron"] = true, -- Dominate Mind (charm)
        ["Magmadar"] = true, -- Panic (fear)

        -- Onyxia's Lair
        ["Onyxia"] = true, -- Bellowing Roar (fear)

        -- Zul'Gurub
        ["Bloodlord Mandokir"] = true, -- Intimidating Shout (fear)
        ["Gurubashi Berserker"] = true, -- Intimidating Roar (fear)
        ["Hakkar"] = true, -- Cause Insanity (charm)
        ["Hakkari Priest"] = true, -- Psychic Scream (fear)
        ["Hakkari Shadow Hunter"] = true, -- Wyvern Sting (sleep)
        ["Hazza'rah"] = true, -- Sleep (sleep)
        ["High Priestess Jeklik"] = true, -- Terrifying Screech (fear); Psychic Scream (fear)
        ["Soulflayer"] = true, -- Fear (fear)

        -- Blackwing Lair
        ["Grethok the Controller"] = true, -- Dominate Mind (charm)
        ["Lord Victor Nefarius"] = true, -- Fear (fear)
        ["Nefarian"] = true, -- Bellowing Roar (fear)

        -- Ruins of Ahn'Qiraj
        ["Captain Qeez"] = true, -- Intimidating Shout (fear)

        -- Temple of Ahn'Qiraj
        ["Anubisath Warder"] = true, -- Fear (fear)
        ["Princess Huhuran"] = true, -- Wyvern Sting (sleep)
        ["Princess Yauj"] = true, -- Panic (fear); Fear (fear)
        ["Qiraji Brainwasher"] = true, -- Mind Flay (fear)
        ["Qiraji Champion"] = true, -- Intimidating Shout (fear)
        ["Qiraji Mindslayer"] = true, -- Mind Flay (fear)

        -- Naxxramas
        ["Deathknight"] = true, -- Intimidating Shout (fear)
        ["Gluth"] = true, -- Terrifying Roar (fear)
        ["Living Monstrosity"] = true, -- Fear (fear)

        -- World raid bosses
        ["Taerar"] = true, -- Bellowing Roar (fear)

        -- World event - Scourge Invasion
        ["Lumbering Horror"] = true, -- Aura of Fear (fear)
        ["Pallid Horror"] = true, -- Aura of Fear (fear)
        ["Patchwork Terror"] = true, -- Aura of Fear (fear)
        ["Shadow of Doom"] = true, -- Fear (fear)
        ["Spirit of the Damned"] = true, -- Psychic Scream (fear)

        -- Open world - Alterac Mountains
        ["Crushridge Enforcer"] = true, -- Intimidation (fear)
        ["Lord Aliden Perenolde"] = true, -- Sleep (sleep)
        ["Skhowl"] = true, -- Intimidating Roar (fear)

        -- Open world - Arathi Highlands
        ["Singer"] = true, -- Dominate Mind (charm)
        ["Sleeby"] = true, -- Sleep (sleep)
        ["Stromgarde Troll Hunter"] = true, -- Sleep (sleep)
        ["Syndicate Conjuror"] = true, -- Sleep (sleep)

        -- Open world - Ashenvale
        ["Diathorus the Seeker"] = true, -- Fear (fear)
        ["Dreamstalker"] = true, -- Sleep (sleep)
        ["Emeraldon Oracle"] = true, -- Sleep (sleep)
        ["Mist Howler"] = true, -- Terrifying Howl (fear)
        ["Severed Sleeper"] = true, -- Sleep (sleep)
        ["Wrathtail Priestess"] = true, -- Sleep (sleep)

        -- Open world - Azshara
        ["Highborne Apparition"] = true, -- Fear (fear)

        -- Open world - Badlands
        ["Shadowforge Chanter"] = true, -- Sleep (sleep)

        -- Open world - Blasted Lands
        ["Dreadlord"] = true, -- Sleep (sleep); Psychic Scream (fear)

        -- Open world - Desolace
        ["Gritjaw Basilisk"] = true, -- Crystalline Slumber (sleep)
        ["Hulking Gritjaw Basilisk"] = true, -- Crystalline Slumber (sleep)

        -- Open world - Duskwood
        ["Morbent Fel"] = true, -- Presence of Death (fear)
        ["Nefaru"] = true, -- Terrifying Howl (fear)
        ["Skeletal Horror"] = true, -- Terrify (fear)

        -- Open world - Dustwallow Marsh
        ["Strashaz Siren"] = true, -- Dominate Mind (charm)

        -- Open world - Eastern Plaguelands
        ["Blighted Horror"] = true, -- Fear (fear)
        ["Death Singer"] = true, -- Terrifying Screech (fear)
        ["Demetria"] = true, -- Psychic Scream (fear); Dominate Mind (charm)
        ["Dread Weaver"] = true, -- Fear (fear)
        ["Nathanos Blightcaller"] = true, -- Psychic Scream (fear)
        ["Plaguebat"] = true, -- Terrifying Screech (fear)
        ["Redpath the Corrupted"] = true, -- Fear (fear)
        ["Scarlet Enchanter"] = true, -- Sleep (sleep)

        -- Open world - Felwood
        ["Overlord Ror"] = true, -- Terrifying Roar (fear)

        -- Open world - Feralas
        ["Hatecrest Siren"] = true, -- Dominate Mind (charm)
        ["Jademir Oracle"] = true, -- Sleep (sleep)

        -- Open world - Hillsbrad Foothills
        ["High Executor Darthalia"] = true, -- Intimidating Shout (fear)

        -- Open world - Moonglade
        ["Nightmare Phantasm"] = true, -- Aura of Fear (fear)

        -- Open world - Searing Gorge
        ["Shleipnarr"] = true, -- Terrify (fear)

        -- Open world - Silithus
        ["Greater Silithid Flayer"] = true, -- Terrifying Screech (fear)
        ["Hive'Regal Hunter-Killer"] = true, -- Frightening Shriek (fear)
        ["Hive'Regal Slavemaker"] = true, -- Poison Mind (charm)
        ["Hive'Zora Abomination"] = true, -- Wings of Despair (fear)
        ["Imperial Qiraji Destroyer"] = true, -- Panic (fear)
        ["Mistress Natalia Mar'alith"] = true, -- Psychic Scream (fear); Domination (charm); Dominate Mind (charm)
        ["Nelson the Nice"] = true, -- Dreadful Fright (fear)
        ["Solenor the Slayer"] = true, -- Dreadful Fright (fear)
        ["Supreme Silithid Flayer"] = true, -- Terrifying Screech (fear)
        ["Twilight Keeper Mayna"] = true, -- Psychic Scream (fear)
        ["Twilight Prophet"] = true, -- Psychic Scream (fear)

        -- Open world - Silverpine Forest
        ["Ravenclaw Regent"] = true, -- Dominate Mind (charm)

        -- Open world - Stonetalon Mountains
        ["Blackened Basilisk"] = true, -- Crystalline Slumber (sleep)
        ["Scorched Basilisk"] = true, -- Crystalline Slumber (sleep)
        ["Singed Basilisk"] = true, -- Crystalline Slumber (sleep)
        ["Taskmaster Whipfang"] = true, -- Intimidating Roar (fear)

        -- Open world - Stranglethorn Vale
        ["Cold Eye Basilisk"] = true, -- Crystalline Slumber (sleep)
        ["Commander Aggro'gosh"] = true, -- Intimidating Shout (fear)
        ["King Mukla"] = true, -- Intimidation (fear)
        ["Lieutenant Doren"] = true, -- Intimidating Shout (fear)
        ["Mosh'Ogg Lord"] = true, -- Intimidation (fear)

        -- Open world - Swamp of Sorrows
        ["Dreaming Whelp"] = true, -- Sleep (sleep)
        ["Kazkaz the Unholy"] = true, -- Dominate Mind (charm)
        ["Somnus"] = true, -- Sleep (sleep)
        ["Wyrmkin Dreamwalker"] = true, -- Sleep (sleep)

        -- Open world - The Barrens
        ["Captain Fairmount"] = true, -- Intimidating Shout (fear)
        ["Captain Shatterskull"] = true, -- Intimidating Shout (fear)
        ["Faltering Silithid Flayer"] = true, -- Terrifying Screech (fear)
        ["Lok Orcbane"] = true, -- Intimidating Shout (fear)
        ["Minor Silithid Flayer"] = true, -- Terrifying Screech (fear)
        ["Sergra Darkthorn"] = true, -- Intimidating Shout (fear)
        ["Swinegart Spearhide"] = true, -- Intimidating Shout (fear)

        -- Open world - The Hinterlands
        ["Dreamtracker"] = true, -- Terrifying Screech (fear)
        ["Verdantine Oracle"] = true, -- Sleep (sleep)

        -- Open world - Thousand Needles
        ["Lesser Silithid Flayer"] = true, -- Terrifying Screech (fear)
        ["Saltstone Basilisk"] = true, -- Crystalline Slumber (sleep)
        ["Scorpid Terror"] = true, -- Terrify (fear)
        ["Silithid Flayer"] = true, -- Terrifying Screech (fear)

        -- Open world - Un'Goro Crater
        ["Frenzied Pterrordax"] = true, -- Terrify (fear)
        ["King Mosh"] = true, -- Terrifying Roar (fear)
        ["Pterrordax"] = true, -- Terrifying Screech (fear)
        ["Tyrant Devilsaur"] = true, -- Terrifying Roar (fear)

        -- Open world - Western Plaguelands
        ["Grand Inquisitor Isillien"] = true, -- Dominate Mind (charm)
        ["Skeletal Terror"] = true, -- Fear (fear)

        -- Open world - Westfall (Moonbrook, outside the Deadmines instance)
        ["Marisa du'Paige"] = true, -- Sleep (sleep)

        -- Open world - Winterspring
        ["Hederine Initiate"] = true, -- Dominate Mind (charm)
        ["Lady Hederine"] = true, -- Dominate Mind (charm); Fear (fear)
        ["Mezzir the Howler"] = true, -- Terrifying Roar (fear)
        ["Rak'shiri"] = true, -- Terrify (fear)
        ["Shy-Rotam"] = true, -- Terrifying Roar (fear)
        ["Sian-Rotam"] = true, -- Terrifying Roar (fear)

        -- Alterac Valley (battleground)
        ["Captain Galvangar"] = true, -- Intimidating Shout (fear)

        -- Capital cities - battlemasters and faction leaders (attackable by the opposite faction only)
        ["Brakgul Deathbringer"] = true, -- Intimidating Shout (fear)
        ["Deze Snowbane"] = true, -- Intimidating Shout (fear)
        ["Elfarran"] = true, -- Intimidating Shout (fear)
        ["Grizzle Halfmane"] = true, -- Intimidating Shout (fear)
        ["High Overlord Saurfang"] = true, -- Terrifying Roar (fear); Intimidating Roar (fear)
        ["Kartra Bloodsnarl"] = true, -- Intimidating Shout (fear)
        ["Kurden Bloodclaw"] = true, -- Intimidating Shout (fear)
        ["Lady Hoteshem"] = true, -- Intimidating Shout (fear)
        ["Overlord Runthak"] = true, -- Intimidating Roar (fear)
        ["Sir Malory Wheeler"] = true, -- Intimidating Shout (fear)
        ["Thelman Slatefist"] = true, -- Intimidating Shout (fear)
        ["Varimathras"] = true, -- Sleep (sleep); Dominate Mind (charm)

        -- Warlock demons (NPC succubi/incubi, e.g. warlock class-quest summons)
        ["Incubus"] = true, -- Seduction (charm)
        ["Succubus"] = true, -- Seduction (charm)
    }
    for name, enabled in pairs(foreverFearCasters) do DEFAULT_FEAR_CASTERS[name] = enabled end
end

-- Boss fights that fear, charm or sleep, by encounter ID: the start of a boss fight
-- says which fight it is, the same number in every client language. Inside dungeons
-- and raids WoW: Forever hides every mob's name, in and out of combat, so the target
-- check cannot work there; these bring the reminder up at the pull instead, targeted
-- or not, on both clients. Each ID points at the boss's name in the lists above, so
-- Use Default Mob List and a boss taken off the list still apply.
-- IDs from each client's own DungeonEncounter table (2026-10-03). Left out on purpose:
-- fights where the fear depends on which boss shows up (Opera Hall, Edge of Madness),
-- fights that fear in one wave or on heroic only (General Rajaxx, Vazruden), and the
-- Season of Discovery copies the Forever client still lists.
local FEAR_BOSS_ENCOUNTERS = {
    [664] = "Magmadar",         -- Molten Core
    [1084] = "Onyxia",          -- Onyxia's Lair
}
if SPCompat.FOREVER then
    local foreverFearBosses = {
        -- Wailing Caverns
        [585] = "Lady Anacondra",
        [586] = "Lord Cobrahn",
        [588] = "Lord Pythas",
        [590] = "Lord Serpentis",
        [592] = "Mutanus the Devourer",
        -- The Deadmines (the fight is called Sneed; his Shredder fears)
        [2742] = "Sneed's Shredder",
        -- Blackfathom Deeps (one ID per difficulty)
        [2766] = "Twilight Lord Kelris",
        [2825] = "Twilight Lord Kelris",
        [2911] = "Twilight Lord Kelris",
        -- The Stockade
        [2759] = "Dextren Ward",
        -- Razorfen Kraul
        [2775] = "Death Speaker Jargba",
        -- Scarlet Monastery
        [449] = "High Inquisitor Fairbanks",
        [450] = "High Inquisitor Whitemane",
        -- Razorfen Downs
        [2783] = "Ragglesnout",
        -- Zul'Farrak
        [599] = "Shadowpriest Sezz'ziz",
        -- Maraudon
        [429] = "Princess Theradras",
        -- Blackrock Depths
        [227] = "High Interrogator Gerstahn",
        -- Blackrock Spire
        [271] = "Urok Doomhowl",
        [3068] = "The Beast",
        -- Dire Maul
        [348] = "Magister Kalendris",
        [366] = "Captain Kromcrush",
        [367] = "Cho'Rush the Observer",
        [2793] = "Lord Hel'nurath",
        -- Stratholme
        [473] = "Hearthsinger Forresten",
        [478] = "Balnazzar",
        [2798] = "Postmaster Malown",
        -- Scholomance (two fights are called Kirtonos and Ras Frostwhisperer)
        [2805] = "Kirtonos the Herald",
        [2806] = "Lady Illucia Barov",
        [2810] = "Ras Frostwhisper",
        -- The Hall of Thanes
        [3496] = "Durgen Dirgehammer",
        -- Molten Core (Dominate Mind in Lucifron's fight)
        [663] = "Lucifron",
        -- Zul'Gurub
        [785] = "High Priestess Jeklik",
        [787] = "Bloodlord Mandokir",
        [793] = "Hakkar",
        -- Blackwing Lair
        [617] = "Nefarian",
        -- Temple of Ahn'Qiraj (the fight is called Silithid Royalty; Princess Yauj fears)
        [710] = "Princess Yauj",
        [714] = "Princess Huhuran",
        -- Naxxramas
        [1108] = "Gluth",
    }
    for id, name in pairs(foreverFearBosses) do FEAR_BOSS_ENCOUNTERS[id] = name end
else
    local tbcFearBosses = {
        [1908] = "Ambassador Hellmaw",  -- Shadow Labyrinth
        [1937] = "Warbringer O'mrogg",  -- The Shattered Halls
        [1914] = "Harbinger Skyriss",   -- The Arcatraz
        [662] = "Nightbane",            -- Karazhan
        [651] = "Hellfire Channeler",   -- Magtheridon's Lair (the channelers fear)
        [619] = "Anetheron",            -- Hyjal Summit
        [622] = "Archimonde",           -- Hyjal Summit
    }
    for id, name in pairs(tbcFearBosses) do FEAR_BOSS_ENCOUNTERS[id] = name end
end

-- NPC identity is only read where the client permits it. IDs avoid assuming
-- the target has an English name; the English values remain the existing
-- saved-list keys, so an override still disables the same default everywhere.
-- Sources: cmangos classic-db ClassicDB_1_12_1_z2815 and tbc-db
-- TBCDB_1.11.0_Vengeance_One_A_Cmangos_Story creature_template (Entry, Name).
-- Forever-only 185317 and 261319: wowhead.com/forever/npc=185317 and npc=261319.
local DEFAULT_FEAR_NPCS
if SPCompat.FOREVER then
    DEFAULT_FEAR_NPCS = {
        [202] = "Skeletal Horror",
        [347] = "Grizzle Halfmane",
        [469] = "Lieutenant Doren",
        [534] = "Nefaru",
        [599] = "Marisa du'Paige",
        [642] = "Sneed's Shredder",
        [680] = "Mosh'Ogg Lord",
        [690] = "Cold Eye Basilisk",
        [741] = "Dreaming Whelp",
        [743] = "Wyrmkin Dreamwalker",
        [1200] = "Morbent Fel",
        [1559] = "King Mukla",
        [1663] = "Dextren Ward",
        [1785] = "Skeletal Terror",
        [1840] = "Grand Inquisitor Isillien",
        [1863] = "Succubus",
        [2215] = "High Executor Darthalia",
        [2256] = "Crushridge Enforcer",
        [2283] = "Ravenclaw Regent",
        [2423] = "Lord Aliden Perenolde",
        [2425] = "Varimathras",
        [2452] = "Skhowl",
        [2464] = "Commander Aggro'gosh",
        [2583] = "Stromgarde Troll Hunter",
        [2590] = "Syndicate Conjuror",
        [2600] = "Singer",
        [2742] = "Shadowforge Chanter",
        [2764] = "Sleeby",
        [2804] = "Kurden Bloodclaw",
        [3338] = "Sergra Darkthorn",
        [3393] = "Captain Fairmount",
        [3435] = "Lok Orcbane",
        [3654] = "Mutanus the Devourer",
        [3669] = "Lord Cobrahn",
        [3670] = "Lord Pythas",
        [3671] = "Lady Anacondra",
        [3672] = "Boahn",
        [3673] = "Lord Serpentis",
        [3801] = "Severed Sleeper",
        [3840] = "Druid of the Fang",
        [3890] = "Brakgul Deathbringer",
        [3944] = "Wrathtail Priestess",
        [3977] = "High Inquisitor Whitemane",
        [4041] = "Scorched Basilisk",
        [4042] = "Singed Basilisk",
        [4044] = "Blackened Basilisk",
        [4139] = "Scorpid Terror",
        [4147] = "Saltstone Basilisk",
        [4293] = "Scarlet Scryer",
        [4302] = "Scarlet Champion",
        [4371] = "Strashaz Siren",
        [4428] = "Death Speaker Jargba",
        [4540] = "Scarlet Monk",
        [4542] = "High Inquisitor Fairbanks",
        [4728] = "Gritjaw Basilisk",
        [4729] = "Hulking Gritjaw Basilisk",
        [4813] = "Twilight Shadowmage",
        [4820] = "Blindlight Oracle",
        [4832] = "Twilight Lord Kelris",
        [4863] = "Jadespine Basilisk",
        [5056] = "Deviate Dreadfang",
        [5259] = "Atal'ai Witch Doctor",
        [5271] = "Atal'ai Deathwalker",
        [5280] = "Nightmare Wyrmkin",
        [5317] = "Jademir Oracle",
        [5337] = "Hatecrest Siren",
        [5401] = "Kazkaz the Unholy",
        [5864] = "Swinegart Spearhide",
        [5932] = "Taskmaster Whipfang",
        [6072] = "Diathorus the Seeker",
        [6116] = "Highborne Apparition",
        [6490] = "Azshir the Sleepless",
        [6500] = "Tyrant Devilsaur",
        [6584] = "King Mosh",
        [7275] = "Shadowpriest Sezz'ziz",
        [7354] = "Ragglesnout",
        [7410] = "Thelman Slatefist",
        [7461] = "Hederine Initiate",
        [8280] = "Shleipnarr",
        [8521] = "Blighted Horror",
        [8528] = "Dread Weaver",
        [8542] = "Death Singer",
        [8600] = "Plaguebat",
        [8657] = "Hukku's Succubus",
        [8716] = "Dreadlord",
        [9018] = "High Interrogator Gerstahn",
        [9166] = "Pterrordax",
        [9167] = "Frenzied Pterrordax",
        [9452] = "Scarlet Enchanter",
        [9464] = "Overlord Ror",
        [10162] = "Lord Victor Nefarius",
        [10184] = "Onyxia",
        [10197] = "Mezzir the Howler",
        [10200] = "Rak'shiri",
        [10201] = "Lady Hederine",
        [10398] = "Thuzadin Shadowcaster",
        [10409] = "Rockwing Screecher",
        [10430] = "The Beast",
        [10470] = "Scholomance Neophyte",
        [10502] = "Lady Illucia Barov",
        [10506] = "Kirtonos the Herald",
        [10508] = "Ras Frostwhisper",
        [10558] = "Hearthsinger Forresten",
        [10584] = "Urok Doomhowl",
        [10644] = "Mist Howler",
        [10737] = "Shy-Rotam",
        [10741] = "Sian-Rotam",
        [10812] = "Grand Crusader Dathrohan",
        [10813] = "Balnazzar",
        [10938] = "Redpath the Corrupted",
        [11143] = "Postmaster Malown",
        [11339] = "Hakkari Shadow Hunter",
        [11352] = "Gurubashi Berserker",
        [11359] = "Soulflayer",
        [11382] = "Bloodlord Mandokir",
        [11445] = "Gordok Captain",
        [11455] = "Wildspawn Felsworn",
        [11487] = "Magister Kalendris",
        [11583] = "Nefarian",
        [11733] = "Hive'Regal Slavemaker",
        [11830] = "Hakkari Priest",
        [11878] = "Nathanos Blightcaller",
        [11947] = "Captain Galvangar",
        [11982] = "Magmadar",
        [12118] = "Lucifron",
        [12119] = "Flamewaker Protector",
        [12201] = "Princess Theradras",
        [12339] = "Demetria",
        [12476] = "Emeraldon Oracle",
        [12478] = "Verdantine Oracle",
        [12496] = "Dreamtracker",
        [12498] = "Dreamstalker",
        [12557] = "Grethok the Controller",
        [12900] = "Somnus",
        [14324] = "Cho'Rush the Observer",
        [14325] = "Captain Kromcrush",
        [14392] = "Overlord Runthak",
        [14506] = "Lord Hel'nurath",
        [14516] = "Death Knight Darkreaver",
        [14517] = "High Priestess Jeklik",
        [14530] = "Solenor the Slayer",
        [14536] = "Nelson the Nice",
        [14682] = "Sever",
        [14684] = "Balzaphon",
        [14686] = "Lady Falther'ess",
        [14697] = "Lumbering Horror",
        [14720] = "High Overlord Saurfang",
        [14781] = "Captain Shatterskull",
        [14834] = "Hakkar",
        [14890] = "Taerar",
        [14942] = "Kartra Bloodsnarl",
        [14981] = "Elfarran",
        [15006] = "Deze Snowbane",
        [15007] = "Sir Malory Wheeler",
        [15008] = "Lady Hoteshem",
        [15083] = "Hazza'rah",
        [15200] = "Twilight Keeper Mayna",
        [15215] = "Mistress Natalia Mar'alith",
        [15246] = "Qiraji Mindslayer",
        [15247] = "Qiraji Brainwasher",
        [15252] = "Qiraji Champion",
        [15308] = "Twilight Prophet",
        [15311] = "Anubisath Warder",
        [15391] = "Captain Qeez",
        [15449] = "Hive'Zora Abomination",
        [15509] = "Princess Huhuran",
        [15543] = "Princess Yauj",
        [15620] = "Hive'Regal Hunter-Killer",
        [15629] = "Nightmare Phantasm",
        [15744] = "Imperial Qiraji Destroyer",
        [15749] = "Lesser Silithid Flayer",
        [15752] = "Silithid Flayer",
        [15756] = "Greater Silithid Flayer",
        [15759] = "Supreme Silithid Flayer",
        [15808] = "Minor Silithid Flayer",
        [15811] = "Faltering Silithid Flayer",
        [15932] = "Gluth",
        [16021] = "Living Monstrosity",
        [16055] = "Va'jashni",
        [16059] = "Theldren",
        [16080] = "Mor Grayhoof",
        [16102] = "Sothos",
        [16143] = "Shadow of Doom",
        [16146] = "Deathknight",
        [16379] = "Spirit of the Damned",
        [16382] = "Patchwork Terror",
        [16394] = "Pallid Horror",
        [185317] = "Incubus",
        [261319] = "Durgen Dirgehammer",
    }
else
    DEFAULT_FEAR_NPCS = {
        [4302] = "Scarlet Champion",
        [4540] = "Scarlet Monk",
        [5259] = "Atal'ai Witch Doctor",
        [10184] = "Onyxia",
        [10398] = "Thuzadin Shadowcaster",
        [11982] = "Magmadar",
        [15547] = "Spectral Charger",
        [16461] = "Concubine",
        [16809] = "Warbringer O'mrogg",
        [17225] = "Nightbane",
        [17256] = "Hellfire Channeler",
        [17478] = "Bleeding Hollow Scryer",
        [17521] = "The Big Bad Wolf",
        [17535] = "Dorothee",
        [17536] = "Nazan",
        [17546] = "Roar",
        [17694] = "Shadowmoon Darkcaster",
        [17801] = "Coilfang Siren",
        [17808] = "Anetheron",
        [17833] = "Durnholde Warden",
        [17897] = "Crypt Fiend",
        [17905] = "Banshee",
        [17968] = "Archimonde",
        [18325] = "Sethekk Prophet",
        [18731] = "Ambassador Hellmaw",
        [18796] = "Fel Overseer",
        [18829] = "Hellfire Warder",
        [19307] = "Nexus Terror",
        [19513] = "Mutate Fear-Shrieker",
        [20033] = "Astromancer",
        [20042] = "Tempest-Smith",
        [20912] = "Harbinger Skyriss",
        [20990] = "Bloodwarder Physician",
        [21104] = "Rift Keeper",
        [21128] = "Coilfang Ray",
        [21148] = "Rift Keeper",
        [21220] = "Coilfang Priestess",
        [21229] = "Greyheart Tidecaller",
        [21466] = "Harbinger Skyriss",
        [21467] = "Harbinger Skyriss",
        [22845] = "Ashtongue Mystic",
        [23028] = "Bonechewer Taskmaster",
        [23330] = "Dragonmaw Wind Reaver",
        [23339] = "Illidari Heartseeker",
        [25369] = "Sunblade Vindicator",
    }
end

-- Default settings
local defaults = {
    enabled = true,
    displayMode = "icon",  -- "icon", "text", "both"
    iconSize = 64,
    textSize = 24,
    scale = 1.0,
    opacity = 100,
    showGlow = true,
    glowColor = { r = 1, g = 0.8, b = 0 },
    playSound = false,
    soundName = "Raid Warning",
    soundVolume = 100,
    position = { point = "CENTER", x = 0, y = 150 },
    locked = true,
    hideWhenTremorActive = true,
    fearCasters = {},  -- User additions/removals
    useDefaultList = true,
}
-- the support code (/sp support) reports only what differs from these
if SP and SP.SUPPORT_MODULE_DEFAULTS then SP.SUPPORT_MODULE_DEFAULTS.ShamanPowerTremorReminderDB = defaults end

-- Local state
local reminderFrame = nil
local isShowing = false
local fearBossName = nil   -- the list name of the boss whose fight is on, while that fight fears

-- Check if a mob name is in the fear-caster list
-- Restricted clients: unit identity (name/GUID) is secret on instanced maps.
-- Ask the client before touching it so nothing here ever branches on a secret.
local function SPIdentitySecret(unit)
	if C_Secrets and C_Secrets.ShouldUnitIdentityBeSecret then
		local ok, v = pcall(C_Secrets.ShouldUnitIdentityBeSecret, unit)
		if not ok or issecretvalue(v) or v == true then return true end
	end
	local ok, guid = pcall(UnitGUID, unit)
	if not ok or issecretvalue(guid) then return true end
	return false, guid
end

-- The settings buttons and tooltip must ask the same policy before reading a
-- name. The second answer distinguishes a hidden identity from no target.
function SP:TremorReminderTargetName()
    if SPIdentitySecret("target") then return nil, true end
    local name = UnitName("target")
    if issecretvalue(name) then return nil, true end
    if type(name) == "string" then return name, false end
    return nil, false
end

local function IsFearCaster(name)
    if issecretvalue(name) or not name then return false end

    local sv = ShamanPowerTremorReminderDB
    if not sv then return false end

    -- Check user's custom list first (can override defaults)
    if sv.fearCasters and sv.fearCasters[name] ~= nil then
        return sv.fearCasters[name]
    end

    -- Check default list if enabled
    if sv.useDefaultList and DEFAULT_FEAR_CASTERS[name] then
        return true
    end

    return false
end

local function IsTargetFearCaster(guid)
    local name = UnitName("target")
    if issecretvalue(name) then return false end
    local sv = ShamanPowerTremorReminderDB
    if not sv then return false end
    -- A typed name keeps its exact spelling and takes precedence, including a
    -- translated custom entry set to false. Never rewrite saved name keys.
    if name and sv.fearCasters and sv.fearCasters[name] ~= nil then return sv.fearCasters[name] end
    if not sv.useDefaultList then return false end
    if name and DEFAULT_FEAR_CASTERS[name] then return true end
    if issecretvalue(guid) or type(guid) ~= "string" then return false end
    local kind, npc = guid:match("^(%a+)%-[^-]*%-[^-]*%-[^-]*%-[^-]*%-(%d+)%-")
    if kind ~= "Creature" and kind ~= "Vehicle" then return false end
    local defaultName = DEFAULT_FEAR_NPCS[tonumber(npc)]
    return defaultName and IsFearCaster(defaultName) or false
end

-- Check if Tremor Totem is currently active
local function IsTremorTotemActive()
    -- On Forever the Earth slot may be secret; the core resolver falls back
    -- to the addon's own-cast shadow model instead of treating it as empty.
    if SPCompat.FOREVER then
        local haveTotem, totemName = ShamanPower:GetElementTotemInfo(1)
        if issecretvalue(haveTotem) or issecretvalue(totemName) then return false end
        return haveTotem and SPCompat.TotemNameMatches(totemName, 8143, "Tremor Totem")
    end
    for slot = 1, 4 do
        local haveTotem, totemName, _, _, _, _, totemSpellID = GetTotemInfo(slot)
        -- named after its spell (the game's own totem name differs in some languages)
        if ShamanPower.CanonicalTotemName and not issecretvalue(totemName) then
            totemName = ShamanPower:CanonicalTotemName(totemName, totemSpellID)
        end
        if not issecretvalue(haveTotem) and not issecretvalue(totemName)
            and haveTotem and SPCompat.TotemNameMatches(totemName, 8143, "Tremor Totem") then
            return true
        end
    end
    return false
end

-- Create the reminder frame
local function CreateReminderFrame()
    if reminderFrame then return reminderFrame end

    local sv = ShamanPowerTremorReminderDB

    local frame = CreateFrame("Frame", "ShamanPowerTremorReminderFrame", UIParent)
    frame:SetSize(sv.iconSize or 64, sv.iconSize or 64)
    frame:SetPoint(sv.position.point or "CENTER", UIParent, sv.position.point or "CENTER", sv.position.x or 0, sv.position.y or 150)
    frame:SetFrameStrata("HIGH")
    frame:Hide()

    -- Icon texture
    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetAllPoints()
    frame.icon:SetTexture(TREMOR_TOTEM_ICON)
    frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Text label
    frame.text = frame:CreateFontString(nil, "OVERLAY")
    SP:SetSPFont(frame.text, "alerts", sv.textSize or 24, "OUTLINE")
    frame.text:SetPoint("TOP", frame, "BOTTOM", 0, -5)
    frame.text:SetText("TREMOR!")
    frame.text:SetTextColor(1, 0.8, 0)
    frame.text:Hide()

    -- Glow (using ActionButton glow)
    frame.glow = frame:CreateTexture(nil, "OVERLAY", nil, 1)
    frame.glow:SetPoint("TOPLEFT", -12, 12)
    frame.glow:SetPoint("BOTTOMRIGHT", 12, -12)
    frame.glow:SetTexture("Interface\\SpellActivationOverlay\\IconAlert")
    frame.glow:SetTexCoord(0.00781250, 0.50781250, 0.27734375, 0.52734375)
    if SP.ShapeGlow then SP:ShapeGlow(frame.glow, "alert") end   -- Glow Shape
    frame.glow:SetVertexColor(sv.glowColor.r or 1, sv.glowColor.g or 0.8, sv.glowColor.b or 0)

    -- Glow animation - pulsing alpha and scale
    frame.glowAnim = frame.glow:CreateAnimationGroup()
    frame.glowAnim:SetLooping("REPEAT")

    -- Pulse in
    local pulseIn = frame.glowAnim:CreateAnimation("Alpha")
    pulseIn:SetFromAlpha(0.3)
    pulseIn:SetToAlpha(1.0)
    pulseIn:SetDuration(0.4)
    pulseIn:SetOrder(1)
    pulseIn:SetSmoothing("IN_OUT")

    local scaleIn = frame.glowAnim:CreateAnimation("Scale")
    scaleIn:SetScaleFrom(0.9, 0.9)
    scaleIn:SetScaleTo(1.1, 1.1)
    scaleIn:SetDuration(0.4)
    scaleIn:SetOrder(1)
    scaleIn:SetSmoothing("IN_OUT")

    -- Pulse out
    local pulseOut = frame.glowAnim:CreateAnimation("Alpha")
    pulseOut:SetFromAlpha(1.0)
    pulseOut:SetToAlpha(0.3)
    pulseOut:SetDuration(0.4)
    pulseOut:SetOrder(2)
    pulseOut:SetSmoothing("IN_OUT")

    local scaleOut = frame.glowAnim:CreateAnimation("Scale")
    scaleOut:SetScaleFrom(1.1, 1.1)
    scaleOut:SetScaleTo(0.9, 0.9)
    scaleOut:SetDuration(0.4)
    scaleOut:SetOrder(2)
    scaleOut:SetSmoothing("IN_OUT")

    -- Enable mouse for tooltip and dragging
    frame:EnableMouse(true)

    -- Tooltip
    frame:SetScript("OnEnter", function(self)
        if SP.opt and SP.opt.ShowTooltips then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Tremor Totem Reminder", 1, 0.82, 0)
            local targetName = SP:TremorReminderTargetName()
            if not issecretvalue(targetName) and targetName then
                GameTooltip:AddLine("Target: " .. targetName .. " (fear-caster)", 1, 0.5, 0.5)
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("ALT+drag to move", 0.5, 0.5, 0.5)
            GameTooltip:Show()
        end
    end)
    frame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Dragging
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        local sv = ShamanPowerTremorReminderDB
        if IsAltKeyDown() and sv and not sv.locked then
            self:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        sv.position.point = point
        sv.position.x = x
        sv.position.y = y
    end)

    reminderFrame = frame
    return frame
end

-- Update frame appearance
local function UpdateAppearance()
    if not reminderFrame then return end

    local sv = ShamanPowerTremorReminderDB
    if not sv then return end

    local size = sv.iconSize or 64
    reminderFrame:SetSize(size, size)

    -- One-time merge of the old separate Scale into Size (iconSize).
    if sv.scale and math.abs(sv.scale - 1) > 0.001 then
        sv.iconSize = math.floor((sv.iconSize or 64) * sv.scale + 0.5)
        sv.scale = 1.0
        reminderFrame:SetSize(sv.iconSize, sv.iconSize)
    end

    local alpha = (sv.opacity or 100) / 100
    reminderFrame:SetAlpha(alpha)

    -- Display mode: icon, text, or both
    local mode = sv.displayMode or "icon"
    if mode == "icon" then
        reminderFrame.icon:Show()
        reminderFrame.text:Hide()
        reminderFrame.glow:ClearAllPoints()
        reminderFrame.glow:SetPoint("TOPLEFT", -12, 12)
        reminderFrame.glow:SetPoint("BOTTOMRIGHT", 12, -12)
    elseif mode == "text" then
        reminderFrame.icon:Hide()
        reminderFrame.text:Show()
        reminderFrame.text:ClearAllPoints()
        reminderFrame.text:SetPoint("CENTER", reminderFrame, "CENTER", 0, 0)
        reminderFrame.glow:Hide()
        SP:ProcGlowStop(reminderFrame, "tremor")
    elseif mode == "both" then
        reminderFrame.icon:Show()
        reminderFrame.text:Show()
        reminderFrame.text:ClearAllPoints()
        reminderFrame.text:SetPoint("TOP", reminderFrame, "BOTTOM", 0, -5)
        reminderFrame.glow:ClearAllPoints()
        reminderFrame.glow:SetPoint("TOPLEFT", -12, 12)
        reminderFrame.glow:SetPoint("BOTTOMRIGHT", 12, -12)
    end

    -- Update text size
    SP:SetSPFont(reminderFrame.text, "alerts", sv.textSize or 24, "OUTLINE")

    -- Glow (only show if not text-only mode)
    if sv.showGlow and mode ~= "text" then
        reminderFrame.glow:Show()
        reminderFrame.glow:SetVertexColor(sv.glowColor.r or 1, sv.glowColor.g or 0.8, sv.glowColor.b or 0)
        reminderFrame.glowAnim:Play()
        SP:ProcGlowStart(reminderFrame, sv.glowColor.r or 1, sv.glowColor.g or 0.8, sv.glowColor.b or 0, "tremor")
    else
        reminderFrame.glow:Hide()
        reminderFrame.glowAnim:Stop()
        SP:ProcGlowStop(reminderFrame, "tremor")
    end
end

-- Show the reminder
local function ShowReminder()
    if isShowing then return end

    local sv = ShamanPowerTremorReminderDB
    if not sv or not sv.enabled then return end

    if not reminderFrame then
        CreateReminderFrame()
    end

    UpdateAppearance()
    reminderFrame:Show()
    isShowing = true

    if sv.showGlow then
        reminderFrame.glowAnim:Play()
    end

    -- Play sound
    if sv.playSound then
        ShamanPower:PlaySoundWithVolume(ShamanPower:GetSoundFile(sv.soundName or "Raid Warning"), sv.soundVolume, true)
    end
end

-- Hide the reminder
local function HideReminder()
    if not isShowing then return end

    if reminderFrame then
        reminderFrame:Hide()
        reminderFrame.glowAnim:Stop()
    end
    isShowing = false
end

-- Check if we should show the reminder: a known fear-caster targeted, or a boss
-- fight that fears going on. The boss half needs no names, so it also works where
-- the target half cannot: inside dungeons and raids on WoW: Forever.
local function CheckTarget()
    if SP.TremorDemoActive then return end
    local sv = ShamanPowerTremorReminderDB
    -- no reminder while you are dead: your totems die with you
    if not sv or not sv.enabled or SP:IsOff() then
        HideReminder()
        return
    end
    local dead = UnitIsDeadOrGhost("player")
    if issecretvalue(dead) or dead then
        HideReminder()
        return
    end

    local wanted = fearBossName ~= nil and IsFearCaster(fearBossName)

    -- instanced map on a restricted client: the target's name is secret, so it is
    -- never read there and only a boss fight can bring the reminder up
    if not wanted then
        local exists, hostile = UnitExists("target"), UnitCanAttack("player", "target")
        if not issecretvalue(exists) and not issecretvalue(hostile) and exists and hostile then
            local hidden, guid = SPIdentitySecret("target")
            if not hidden then wanted = IsTargetFearCaster(guid) end
        end
    end

    -- Tremor Totem already down: nothing to remind
    if not wanted or (sv.hideWhenTremorActive and IsTremorTotemActive()) then
        HideReminder()
        return
    end

    ShowReminder()   -- plays the sound when it comes up
end

-- Event handler frame
local eventFrame = CreateFrame("Frame")
if SPCompat and SPCompat.StressRegister then SPCompat.StressRegister(eventFrame, "Tremor Reminder") end
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:RegisterEvent("PLAYER_TOTEM_UPDATE")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("ENCOUNTER_START")
eventFrame:RegisterEvent("ENCOUNTER_END")
eventFrame:RegisterEvent("PLAYER_DEAD")
eventFrame:RegisterEvent("PLAYER_ALIVE")
eventFrame:RegisterEvent("PLAYER_UNGHOST")

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "ShamanPower_TremorReminder" then
        -- Initialize saved variables
        if not ShamanPowerTremorReminderDB then
            ShamanPowerTremorReminderDB = {}
        end

        -- Apply defaults
        for k, v in pairs(defaults) do
            if ShamanPowerTremorReminderDB[k] == nil then
                if type(v) == "table" then
                    ShamanPowerTremorReminderDB[k] = {}
                    for k2, v2 in pairs(v) do
                        ShamanPowerTremorReminderDB[k][k2] = v2
                    end
                else
                    ShamanPowerTremorReminderDB[k] = v
                end
            end
        end

        -- Create frame (hidden)
        CreateReminderFrame()

    elseif event == "PLAYER_TARGET_CHANGED" then
        CheckTarget()

    elseif event == "PLAYER_TOTEM_UPDATE" then
        -- Re-check when totems change (might need to hide if Tremor placed)
        CheckTarget()

    elseif event == "ENCOUNTER_START" then
        -- arg1 is the encounter ID, a plain number on every client; test it before
        -- using it as a key anyway (a secret can never index a table)
        if issecretvalue and issecretvalue(arg1) then
            fearBossName = nil
        elseif type(arg1) == "number" then
            fearBossName = FEAR_BOSS_ENCOUNTERS[arg1]
        else
            fearBossName = nil
        end
        CheckTarget()

    elseif event == "ENCOUNTER_END" then
        fearBossName = nil
        CheckTarget()

    elseif event == "PLAYER_DEAD" or event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
        CheckTarget()

    elseif event == "PLAYER_ENTERING_WORLD" then
        -- a loading screen ends any boss fight that was on; re-check on zone changes
        fearBossName = nil
        C_Timer.After(1, CheckTarget)
    end
end)

-- Enable ShamanPower switched: off hides the reminder, on checks the target again
SP:OnOnOff(function() CheckTarget() end)

-- Slash commands
SLASH_SPTREMOR1 = "/sptremor"
SlashCmdList["SPTREMOR"] = function(msg)
    local typed = msg:trim()
    msg = typed:lower()

    if msg == "show" then
        -- Show positioning frame
        if not reminderFrame then CreateReminderFrame() end
        reminderFrame:Show()
        reminderFrame.icon:SetDesaturated(true)
        print("|cff0070ddShamanPower|r [Tremor Reminder]: Reminder shown. ALT+drag to move.")

    elseif msg == "hide" then
        if reminderFrame then
            reminderFrame:Hide()
            reminderFrame.icon:SetDesaturated(false)
        end
        isShowing = false
        print("|cff0070ddShamanPower|r [Tremor Reminder]: Reminder hidden.")

    elseif msg == "test" then
        -- Force show for testing
        if not reminderFrame then CreateReminderFrame() end
        UpdateAppearance()
        reminderFrame:Show()
        reminderFrame.icon:SetDesaturated(false)
        if ShamanPowerTremorReminderDB.showGlow then
            reminderFrame.glowAnim:Play()
        end
        print("|cff0070ddShamanPower|r [Tremor Reminder]: Test alert shown.")

    elseif msg == "reset" then
        ShamanPowerTremorReminderDB.position = { point = "CENTER", x = 0, y = 150 }
        if reminderFrame then
            reminderFrame:ClearAllPoints()
            reminderFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 150)
        end
        print("|cff0070ddShamanPower|r [Tremor Reminder]: Position reset to just above the middle of your screen.")

    elseif msg == "toggle" then
        ShamanPowerTremorReminderDB.enabled = not ShamanPowerTremorReminderDB.enabled
        local status = ShamanPowerTremorReminderDB.enabled and "on" or "off"
        print("|cff0070ddShamanPower|r [Tremor Reminder]: " .. status)
        if not ShamanPowerTremorReminderDB.enabled then
            HideReminder()
        end

    elseif msg:find("^add ") then
        local mobName = typed:sub(5):trim()
        if mobName ~= "" then
            ShamanPowerTremorReminderDB.fearCasters[mobName] = true
            print("|cff0070ddShamanPower|r [Tremor Reminder]: Added '" .. mobName .. "' to fear-caster list.")
        end

    elseif msg:find("^remove ") then
        local mobName = typed:sub(8):trim()
        if mobName ~= "" then
            ShamanPowerTremorReminderDB.fearCasters[mobName] = false
            print("|cff0070ddShamanPower|r [Tremor Reminder]: Removed '" .. mobName .. "' from fear-caster list.")
        end

    elseif msg == "list" then
        print("|cff0070ddShamanPower|r [Tremor Reminder]: Known fear-casters:")
        local count = 0
        if ShamanPowerTremorReminderDB.useDefaultList then
            for name in pairs(DEFAULT_FEAR_CASTERS) do
                if ShamanPowerTremorReminderDB.fearCasters[name] ~= false then
                    print("  - " .. name)
                    count = count + 1
                end
            end
        end
        for name, enabled in pairs(ShamanPowerTremorReminderDB.fearCasters) do
            if enabled and not DEFAULT_FEAR_CASTERS[name] then
                print("  - " .. name .. " (custom)")
                count = count + 1
            end
        end
        print("Total: " .. count .. " mobs")

    else
        -- Open options or show help
        print("|cff0070ddShamanPower|r [Tremor Reminder] Commands:")
        print("  /sptremor show - Show the reminder so you can move it")
        print("  /sptremor hide - Hide the reminder")
        print("  /sptremor test - Show test alert")
        print("  /sptremor reset - Put it back just above the middle of your screen")
        print("  /sptremor toggle - Turn Tremor Reminder on or off")
        print("  /sptremor add <mob name> - Add mob to fear-caster list")
        print("  /sptremor remove <mob name> - Remove mob from list")
        print("  /sptremor list - Show all known fear-casters")
    end
end

-- Bridge functions for main addon
-- A setting changed (on / off, Hide When Tremor Active, Use Default Mob List): check again now
function SP:TremorReminderRecheck()
    CheckTarget()
end

function SP:TremorReminderShow()
    if not reminderFrame then CreateReminderFrame() end
    reminderFrame:Show()
    reminderFrame.icon:SetDesaturated(true)
end

function SP:TremorReminderHide()
    if reminderFrame then
        reminderFrame:Hide()
        reminderFrame.icon:SetDesaturated(false)
    end
    isShowing = false
end

function SP:TremorReminderTest()
    if not reminderFrame then CreateReminderFrame() end
    UpdateAppearance()
    reminderFrame:Show()
    reminderFrame.icon:SetDesaturated(false)
    if ShamanPowerTremorReminderDB.showGlow then
        reminderFrame.glowAnim:Play()
    end
end

-- Setup-wizard preview: show a believable sample alert without a live target
function SP:TremorDemo(on)
    if not reminderFrame then CreateReminderFrame() end
    local sv = ShamanPowerTremorReminderDB
    if on then
        if self.TremorDemoActive then
            UpdateAppearance()                  -- re-entrant: options changed
            return
        end
        self.TremorDemoActive = true
        -- A short targeting scene, looped. Rendered through the real
        -- appearance path so Display Mode / size / glow all show correctly.
        local SCENE = {
            { show = true, secs = 4.0, story = "You target |cffff8080"
                .. (SPCompat.FOREVER and "Scarlet Monk" or "Coilfang Siren")
                .. "|r - a known fear-caster. Get Tremor down." },
            { show = false, secs = 2.0, story = "Tremor Totem is down - reminder hidden.", tremor = true },
            { show = true, secs = 3.5, story = "New target: |cffff8080"
                .. (SPCompat.FOREVER and "Thuzadin Shadowcaster" or "Sethekk Prophet")
                .. "|r. Tremor has expired - reminder is back." },
            { show = false, secs = 2.0, story = "You target a harmless mob - nothing to remind you about." },
        }
        local beat, left = 0, 0
        local function apply(b)
            self.tremorDemoStatus = b.story
            local show = b.show and sv.enabled ~= false
            if b.tremor and sv.hideWhenTremorActive == false then
                show = true
                self.tremorDemoStatus = "Tremor Totem is down, but the reminder stays (Hide When Tremor Active is off)."
            end
            if show then
                UpdateAppearance()
                reminderFrame.icon:SetDesaturated(false)
                reminderFrame:Show()
                if sv.showGlow and (sv.displayMode or "icon") ~= "text" then reminderFrame.glowAnim:Play() end
                if sv.playSound and b.show then
                    ShamanPower:PlaySoundWithVolume(ShamanPower:GetSoundFile(sv.soundName or "Raid Warning"), sv.soundVolume, true)
                end
            else
                reminderFrame.glowAnim:Stop()
                reminderFrame:Hide()
            end
        end
        if self.tremorDemoTicker then self.tremorDemoTicker:Cancel() end
        self.tremorDemoTicker = C_Timer.NewTicker(0.25, function()
            if not self.TremorDemoActive then return end
            left = left - 0.25
            if left <= 0 then
                beat = (beat % #SCENE) + 1
                left = SCENE[beat].secs
                apply(SCENE[beat])
            end
        end)
    else
        self.TremorDemoActive = false
        if self.tremorDemoTicker then self.tremorDemoTicker:Cancel(); self.tremorDemoTicker = nil end
        self.tremorDemoStatus = nil
        if reminderFrame then
            reminderFrame.glowAnim:Stop()
            reminderFrame.icon:SetDesaturated(false)
            reminderFrame:Hide()
        end
        isShowing = false
        -- Restore real state (hidden unless a live fear-caster is targeted).
        CheckTarget()
    end
end

function SP:TremorReminderReset()
    ShamanPowerTremorReminderDB.position = { point = "CENTER", x = 0, y = 150 }
    if reminderFrame then
        reminderFrame:ClearAllPoints()
        reminderFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 150)
    end
end

function SP:UpdateTremorReminderAppearance()
    UpdateAppearance()
end

-- Get the list of default fear casters (for options UI)
function SP:GetDefaultFearCasters()
    return DEFAULT_FEAR_CASTERS
end

-- Get custom fear casters from saved vars
function SP:GetCustomFearCasters()
    if ShamanPowerTremorReminderDB then
        return ShamanPowerTremorReminderDB.fearCasters or {}
    end
    return {}
end

-- ============================================================================
-- Mob List Management Frame
-- ============================================================================

local MobListFrame = nil

local function BuildMobList()
    local sv = ShamanPowerTremorReminderDB
    if not sv then return {} end

    local mobs = {}

    -- Add defaults (if enabled and not removed)
    if sv.useDefaultList then
        for name in pairs(DEFAULT_FEAR_CASTERS) do
            if sv.fearCasters[name] ~= false then
                table.insert(mobs, { name = name, isCustom = false })
            end
        end
    end

    -- Add custom mobs
    for name, enabled in pairs(sv.fearCasters) do
        if enabled and not DEFAULT_FEAR_CASTERS[name] then
            table.insert(mobs, { name = name, isCustom = true })
        end
    end

    table.sort(mobs, function(a, b) return a.name < b.name end)
    return mobs
end

function SP:ShowMobList()
    if MobListFrame then
        MobListFrame:Show()
        SP:RefreshMobList()
        return
    end

    -- Create main window
    local f = CreateFrame("Frame", "SPTremorMobListFrame", UIParent, "BackdropTemplate")
    f:SetSize(320, 400)
    f:SetPoint("CENTER")
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 }
    })
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetFrameStrata("DIALOG")

    -- Title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("Fear Caster Mob List")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)

    -- Add mob section
    local addLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    addLabel:SetPoint("TOPLEFT", 20, -45)
    addLabel:SetText("Add Mob:")

    local editBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    editBox:SetSize(150, 20)
    editBox:SetPoint("LEFT", addLabel, "RIGHT", 10, 0)
    editBox:SetAutoFocus(false)
    f.editBox = editBox

    local addBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    addBtn:SetSize(50, 22)
    addBtn:SetPoint("LEFT", editBox, "RIGHT", 5, 0)
    addBtn:SetText("Add")
    addBtn:SetScript("OnClick", function()
        local name = editBox:GetText():trim()
        if name ~= "" then
            ShamanPowerTremorReminderDB.fearCasters[name] = true
            editBox:SetText("")
            SP:RefreshMobList()
        end
    end)

    editBox:SetScript("OnEnterPressed", function() addBtn:Click() end)

    -- Add target button
    local targetBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    targetBtn:SetSize(90, 22)
    targetBtn:SetPoint("TOPLEFT", addLabel, "BOTTOMLEFT", 0, -8)
    targetBtn:SetText("Add Target")
    targetBtn:SetScript("OnClick", function()
        local name = SP:TremorReminderTargetName()
        local hostile = UnitCanAttack("player", "target")
        if name and not issecretvalue(hostile) and hostile then
            ShamanPowerTremorReminderDB.fearCasters[name] = true
            SP:RefreshMobList()
        end
    end)

    -- List container with scroll
    local listBg = CreateFrame("Frame", nil, f, "BackdropTemplate")
    listBg:SetPoint("TOPLEFT", 15, -95)
    listBg:SetPoint("BOTTOMRIGHT", -15, 35)
    listBg:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    listBg:SetBackdropColor(0, 0, 0, 0.5)
    listBg:SetClipsChildren(true)

    -- Scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", "SPTremorMobListScroll", listBg, "FauxScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 5, -5)
    scrollFrame:SetPoint("BOTTOMRIGHT", -26, 5)

    -- Create row frames
    local ROW_HEIGHT = 20
    local rows = {}
    local numVisibleRows = math.floor(scrollFrame:GetHeight() / ROW_HEIGHT)

    for i = 1, 15 do
        local row = CreateFrame("Button", nil, listBg)
        row:SetSize(scrollFrame:GetWidth(), ROW_HEIGHT)
        row:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, -((i - 1) * ROW_HEIGHT))

        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(1, 1, 1, 0.1)
        bg:Hide()
        row.bg = bg

        local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetPoint("LEFT", 5, 0)
        text:SetJustifyH("LEFT")
        row.text = text

        local customTag = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        customTag:SetPoint("RIGHT", -25, 0)
        customTag:SetTextColor(0.3, 1, 0.3)
        row.customTag = customTag

        local delBtn = CreateFrame("Button", nil, row)
        delBtn:SetSize(16, 16)
        delBtn:SetPoint("RIGHT", -3, 0)
        delBtn:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
        delBtn:SetHighlightTexture("Interface\\Buttons\\UI-StopButton")
        row.delBtn = delBtn

        row:SetScript("OnEnter", function() bg:Show() end)
        row:SetScript("OnLeave", function() bg:Hide() end)

        rows[i] = row
    end

    f.scrollFrame = scrollFrame
    f.rows = rows

    -- Count label
    local countLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    countLabel:SetPoint("BOTTOMLEFT", 20, 12)
    countLabel:SetTextColor(0.7, 0.7, 0.7)
    f.countLabel = countLabel

    MobListFrame = f
    SP:RefreshMobList()
end

function SP:RefreshMobList()
    if not MobListFrame then return end

    local mobs = BuildMobList()
    local rows = MobListFrame.rows
    local scrollFrame = MobListFrame.scrollFrame
    local ROW_HEIGHT = 20

    FauxScrollFrame_Update(scrollFrame, #mobs, #rows, ROW_HEIGHT)
    local offset = FauxScrollFrame_GetOffset(scrollFrame)

    for i, row in ipairs(rows) do
        local idx = i + offset
        if idx <= #mobs then
            local mob = mobs[idx]
            row.text:SetText(mob.name)
            row.customTag:SetText(mob.isCustom and "(custom)" or "")
            row.delBtn:SetScript("OnClick", function()
                if mob.isCustom then
                    ShamanPowerTremorReminderDB.fearCasters[mob.name] = nil
                else
                    ShamanPowerTremorReminderDB.fearCasters[mob.name] = false
                end
                SP:RefreshMobList()
            end)
            row:Show()
        else
            row:Hide()
        end
    end

    MobListFrame.countLabel:SetText(#mobs .. " mobs")

    scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, function() SP:RefreshMobList() end)
    end)
end

function SP:HideMobList()
    if MobListFrame then MobListFrame:Hide() end
end

function SP:ToggleMobList()
    if MobListFrame and MobListFrame:IsShown() then
        SP:HideMobList()
    else
        SP:ShowMobList()
    end
end

-- Register this module's frame with the setup-wizard preview harness.
if ShamanPower.RegisterPreview then
    ShamanPower:RegisterPreview("tremor", { frame = "ShamanPowerTremorReminderFrame", demo = "SP:TremorDemo", pad = 24 })
end

-- Theme (General > Themes, spot mod.tremor): the existing Glow Color setting is
-- the theme's Glow swatch. A theme writes it exactly as the Glow Color option
-- does (the Tremor Reminder page still shows and changes it); Standard puts the
-- player's own colour back.
if SP.ThemeSpotSettings then
    SP:ThemeSpotSettings("mod.tremor", {
        { role = "glow", label = "Glow",
          get = function()
              local c = ShamanPowerTremorReminderDB and ShamanPowerTremorReminderDB.glowColor
              if c then return { r = c.r or 1, g = c.g or 0.8, b = c.b or 0 } end
              return { r = 1, g = 0.8, b = 0 }
          end,
          set = function(v)
              if type(v) ~= "table" or not ShamanPowerTremorReminderDB then return end
              if not ShamanPowerTremorReminderDB.glowColor then
                  ShamanPowerTremorReminderDB.glowColor = {}
              end
              ShamanPowerTremorReminderDB.glowColor.r = v.r or v[1]
              ShamanPowerTremorReminderDB.glowColor.g = v.g or v[2]
              ShamanPowerTremorReminderDB.glowColor.b = v.b or v[3]
              if ShamanPower.UpdateTremorReminderAppearance then
                  ShamanPower:UpdateTremorReminderAppearance()
              end
          end,
          -- ShamanPower and ShamanPower Minimal: WoW gold (NORMAL_FONT_COLOR)
          shamanpower = function()
              local r, g, b = SP:WoWColor("NORMAL_FONT_COLOR")
              return { r = r, g = g, b = b }
          end,
        },
    })
end
