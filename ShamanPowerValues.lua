local L = LibStub("AceLocale-3.0"):GetLocale("ShamanPower", true) or {}

-- Global constants for XML text references
SHAMANPOWER_NAME = "ShamanPower"
SHAMANPOWER_REFRESH = "Refresh"
SHAMANPOWER_CLEAR = "Clear"
SHAMANPOWER_AUTOASSIGN = "Auto-Assign"
SHAMANPOWER_OPTIONS = "Options"
SHAMANPOWER_PRESET = "Preset"
SHAMANPOWER_REPORT = "Report"
SHAMANPOWER_FREEASSIGN = "Free Assignment"

-- Keybinding names (displayed in WoW's keybinding menu)
BINDING_HEADER_SHAMANPOWER = "ShamanPower"
BINDING_NAME_SHAMANPOWER_DROPALL = "Drop All Totems"
BINDING_NAME_SHAMANPOWER_EARTH_TOTEM = "Cast Assigned Earth Totem"
BINDING_NAME_SHAMANPOWER_FIRE_TOTEM = "Cast Assigned Fire Totem"
BINDING_NAME_SHAMANPOWER_WATER_TOTEM = "Cast Assigned Water Totem"
BINDING_NAME_SHAMANPOWER_AIR_TOTEM = "Cast Assigned Air Totem"
BINDING_NAME_SHAMANPOWER_EARTH_SHIELD = "Cast Earth Shield on Assigned Target"
BINDING_NAME_SHAMANPOWER_TOTEMIC_CALL = "Totemic Call (Recall Totems)"

-- Cooldown Bar keybindings
BINDING_HEADER_SHAMANPOWER_CD = "ShamanPower Cooldown Bar"
BINDING_NAME_SHAMANPOWER_CD_SHIELD = "Cast Shield (Lightning/Water)"
BINDING_NAME_SHAMANPOWER_CD_RECALL = "Totemic Call (Recall)"
BINDING_NAME_SHAMANPOWER_CD_ANKH = "Reincarnation (Ankh)"
BINDING_NAME_SHAMANPOWER_CD_NS = "Nature's Swiftness"
BINDING_NAME_SHAMANPOWER_CD_MANATIDE = "Mana Tide Totem"
BINDING_NAME_SHAMANPOWER_CD_BLOODLUST = "Bloodlust / Heroism"
BINDING_NAME_SHAMANPOWER_CD_IMBUE = "Cast Weapon Imbue"

-- Tooltip descriptions
SHAMANPOWER_REFRESH_DESC = "Refresh the shaman list"
SHAMANPOWER_CLEAR_DESC = "Clear all totem assignments"
SHAMANPOWER_AUTOASSIGN_DESC = "Auto-assign totems based on available shamans"
SHAMANPOWER_OPTIONS_DESC = "Open ShamanPower options"
SHAMANPOWER_PRESET_DESC = "Save or load totem assignment presets"
SHAMANPOWER_REPORT_DESC = "Report totem assignments to raid/party chat"
SHAMANPOWER_FREEASSIGN_DESC = "Allow others to change your assignments without leader/assist"

-- Tooltip strings for UI elements
ShamanPower.CONFIG_DRAGHANDLE = L["DRAGHANDLE_TOOLTIP"] or "|cffffffffLeft-Click|r Lock/Unlock ShamanPower\n|cffffffffLeft-Click-Hold|r Move ShamanPower\n|cffffffffRight-Click|r Open Totem Assignments\n|cffffffffShift-Right-Click|r Open Options"
ShamanPower.CONFIG_RESIZEGRIP = "Drag to resize"

ShamanPower.commPrefix = "SHPWR"
C_ChatInfo.RegisterAddonMessagePrefix(ShamanPower.commPrefix)

-- Constants
SHAMANPOWER_MAXGROUPS = 8          -- Max party groups in a raid
SHAMANPOWER_MAXELEMENTS = 4        -- Earth, Fire, Water, Air
SHAMANPOWER_MAXPERELEMENT = 8      -- Max totems per element
SHAMANPOWER_TOTEMDURATION = 2 * 60 -- 2 minutes base duration (some vary)

-- Compatibility constants (for code still referencing old PallyPower structure)
SHAMANPOWER_MAXCLASSES = 4         -- Using elements instead of classes
SHAMANPOWER_MAXAURAS = 0           -- Shamans don't have auras like Paladins
SHAMANPOWER_MAXPERCLASS = 8        -- Max shamans to display

-- Default configuration values
SHAMANPOWER_DEFAULT_VALUES = {
    profile = {
        autobuff = {
            autobutton = true,
            waitforpeople = true
        },
        border = "Blizzard Tooltip",
        buffscale = 0.90,
        cBuffNeedAll = {r = 1.0, g = 0.0, b = 0.0, t = 0.5},
        cBuffNeedSome = {r = 1.0, g = 1.0, b = 0.5, t = 0.5},
        cBuffNeedSpecial = {r = 0.0, g = 0.0, b = 1.0, t = 0.5},
        cBuffGood = {r = 0.0, g = 0.7, b = 0.0, t = 0.5},
        configscale = 0.90,
        display = {
            buffDuration = true,
            buttonWidth = 100,
            buttonHeight = 34,
            enableDragHandle = true,
            frameLocked = false,
            HideKeyText = false,
            HideCount = false,
            HideCountText = false,
            HideTimerText = false,
            LockBuffBars = false,
            showShamanButtons = true,
            showElementButtons = true,
            offsetX = 0,
            offsetY = 0
        },
        enabled = true,
        layout = "Vertical",
        minimap = {
            ["minimapPos"] = 190,
            ["show"] = true,
        },
        ReportChannel = 0,
        ShowInParty = true,
        ShowTooltips = true,
        ShowWhenSolo = true,
        showDropAllButton = true,  -- Show the Drop All Totems button on mini bar
        showPartyRangeDots = true,  -- Show party range indicator dots on mini totem bar
        showCooldownBar = true,  -- Show the cooldown tracker bar below totem bar
        showButtonKeybinds = false,  -- Show keybind text on buttons (top-right corner)
        hideTotemBarFrame = false,  -- Hide the background/border around totem bar (icons only)
        hideCooldownBarFrame = false,  -- Hide the background/border around cooldown bar (icons only)
        cooldownBarLocked = true,  -- When false, CD bar can be moved independently from totem bar
        cooldownBarFrameLocked = false,  -- When CD bar is independent, this locks its position (red=locked, green=movable)
        cooldownBarScale = 0.90,  -- Separate scale for CD bar
        cooldownBarPoint = "CENTER",  -- Saved anchor point
        cooldownBarRelPoint = "CENTER",  -- Saved relative anchor point
        cooldownBarPosX = 0,  -- Saved X position offset
        cooldownBarPosY = -50,  -- Saved Y position offset
        showTotemFlyouts = true,  -- Show flyout menus on mouseover for quick totem selection
        hideEarthShieldText = false,  -- Hide the Earth Shield target name text on totem bar
        preferredShield = 1,  -- Preferred shield: 1=Lightning Shield, 2=Water Shield
        dropOrder = {1, 2, 3, 4},  -- Order to drop totems: 1=Earth, 2=Fire, 3=Water, 4=Air
        excludeEarthFromDropAll = false,  -- Exclude Earth totem from Drop All button
        excludeFireFromDropAll = false,   -- Exclude Fire totem from Drop All button
        excludeWaterFromDropAll = false,  -- Exclude Water totem from Drop All button
        excludeAirFromDropAll = false,    -- Exclude Air totem from Drop All button
        totemBarOrder = {1, 2, 3, 4},  -- Order of totem buttons on mini bar: 1=Earth, 2=Fire, 3=Water, 4=Air
        cooldownBarOrder = {1, 2, 3, 4, 5, 6, 7},  -- Order of cooldown bar items: 1=Shield, 2=Recall, 3=Ankh, 4=NS, 5=ManaTide, 6=BL/Hero, 7=Imbues
        skin = "Smooth",
        SmartBuffs = true,
        syncToTotemTimers = false,  -- Sync assignments to TotemTimers addon (if installed)
        weaponEnchant = 1,  -- Default weapon enchant (Windfury)
    }
}

-- Non-shaman profile (minimal display)
SHAMANPOWER_OTHER_VALUES = {
    profile = {
        autobuff = {
            autobutton = false,
            waitforpeople = false
        },
        border = "Blizzard Tooltip",
        buffscale = 0.90,
        cBuffNeedAll = {r = 1.0, g = 0.0, b = 0.0, t = 0.5},
        cBuffNeedSome = {r = 1.0, g = 1.0, b = 0.5, t = 0.5},
        cBuffNeedSpecial = {r = 0.0, g = 0.0, b = 1.0, t = 0.5},
        cBuffGood = {r = 0.0, g = 0.7, b = 0.0, t = 0.5},
        configscale = 0.90,
        display = {
            buffDuration = false,
            buttonWidth = 100,
            buttonHeight = 34,
            enableDragHandle = false,
            frameLocked = false,
            HideKeyText = false,
            HideCount = false,
            HideCountText = false,
            HideTimerText = false,
            LockBuffBars = false,
            showShamanButtons = false,
            showElementButtons = false
        },
        enabled = true,
        layout = "Vertical",
        minimap = {
            ["minimapPos"] = 190,
            ["show"] = true,
        },
        ReportChannel = 0,
        ShowInParty = true,
        ShowTooltips = true,
        ShowWhenSolo = true,
        showDropAllButton = true,
        skin = "Smooth",
        SmartBuffs = false,
        weaponEnchant = 0,
    }
}

ShamanPower.BuffBarTitle = "Totem Buffs (%d)"

-- Element IDs
ShamanPower.Elements = {
    [1] = "EARTH",
    [2] = "FIRE",
    [3] = "WATER",
    [4] = "AIR"
}

ShamanPower.ElementToID = {
    ["EARTH"] = 1,
    ["FIRE"] = 2,
    ["WATER"] = 3,
    ["AIR"] = 4
}

-- Element colors for UI
ShamanPower.ElementColors = {
    [1] = {r = 0.6, g = 0.4, b = 0.2},  -- Earth - brown
    [2] = {r = 1.0, g = 0.4, b = 0.1},  -- Fire - orange
    [3] = {r = 0.2, g = 0.6, b = 1.0},  -- Water - blue
    [4] = {r = 0.8, g = 0.8, b = 1.0},  -- Air - light blue/white
}

-- Group names for display
ShamanPower.GroupNames = {
    [1] = "Group 1",
    [2] = "Group 2",
    [3] = "Group 3",
    [4] = "Group 4",
    [5] = "Group 5",
    [6] = "Group 6",
    [7] = "Group 7",
    [8] = "Group 8",
}

-- ============================================================================
-- TOTEM SPELL DATA
-- Format: [totemIndex] = spellID (highest rank in TBC)
-- ============================================================================

-- Earth Totems (using Rank 1 spell IDs so all characters can use)
ShamanPower.EarthTotems = {
    [1] = 8075,     -- Strength of Earth Totem (Rank 1)
    [2] = 8071,     -- Stoneskin Totem (Rank 1)
    [3] = 8143,     -- Tremor Totem
    [4] = 2484,     -- Earthbind Totem
    [5] = 5730,     -- Stoneclaw Totem (Rank 1)
    [6] = 2062,     -- Earth Elemental Totem
}

-- Fire Totems (using Rank 1 spell IDs)
ShamanPower.FireTotems = {
    [1] = 30706,    -- Totem of Wrath (Elemental talent)
    [2] = 3599,     -- Searing Totem (Rank 1)
    [3] = 8190,     -- Magma Totem (Rank 1)
    [4] = 1535,     -- Fire Nova Totem (Rank 1)
    [5] = 8227,     -- Flametongue Totem (Rank 1)
    [6] = 8181,     -- Frost Resistance Totem (Rank 1)
    [7] = 2894,     -- Fire Elemental Totem
}

-- Water Totems (using Rank 1 spell IDs)
ShamanPower.WaterTotems = {
    [1] = 5675,     -- Mana Spring Totem (Rank 1)
    [2] = 5394,     -- Healing Stream Totem (Rank 1)
    [3] = 16190,    -- Mana Tide Totem (Resto talent)
    [4] = 8166,     -- Poison Cleansing Totem
    [5] = 8170,     -- Disease Cleansing Totem
    [6] = 8184,     -- Fire Resistance Totem (Rank 1)
}

-- Air Totems (using Rank 1 spell IDs)
ShamanPower.AirTotems = {
    [1] = 8512,     -- Windfury Totem (Rank 1)
    [2] = 8835,     -- Grace of Air Totem (Rank 1)
    [3] = 3738,     -- Wrath of Air Totem
    [4] = 25908,    -- Tranquil Air Totem
    [5] = 8177,     -- Grounding Totem
    [6] = 10595,    -- Nature Resistance Totem (Rank 1)
    [7] = 15107,    -- Windwall Totem (Rank 1)
    [8] = 6495,     -- Sentry Totem
}

-- Combined totems by element
ShamanPower.Totems = {
    [1] = ShamanPower.EarthTotems,
    [2] = ShamanPower.FireTotems,
    [3] = ShamanPower.WaterTotems,
    [4] = ShamanPower.AirTotems,
}

-- Totem names by element (for display)
ShamanPower.TotemNames = {
    [1] = {  -- Earth
        [1] = "Strength of Earth",
        [2] = "Stoneskin",
        [3] = "Tremor",
        [4] = "Earthbind",
        [5] = "Stoneclaw",
        [6] = "Earth Elemental",
    },
    [2] = {  -- Fire
        [1] = "Totem of Wrath",
        [2] = "Searing",
        [3] = "Magma",
        [4] = "Fire Nova",
        [5] = "Flametongue",
        [6] = "Frost Resistance",
        [7] = "Fire Elemental",
    },
    [3] = {  -- Water
        [1] = "Mana Spring",
        [2] = "Healing Stream",
        [3] = "Mana Tide",
        [4] = "Poison Cleansing",
        [5] = "Disease Cleansing",
        [6] = "Fire Resistance",
    },
    [4] = {  -- Air
        [1] = "Windfury",
        [2] = "Grace of Air",
        [3] = "Wrath of Air",
        [4] = "Tranquil Air",
        [5] = "Grounding",
        [6] = "Nature Resistance",
        [7] = "Windwall",
        [8] = "Sentry",
    },
}

-- Short names for buttons
ShamanPower.TotemShortNames = {
    [1] = {  -- Earth
        [1] = "SoE",
        [2] = "Stone",
        [3] = "Trem",
        [4] = "Bind",
        [5] = "Claw",
        [6] = "E.Ele",
    },
    [2] = {  -- Fire
        [1] = "ToW",
        [2] = "Sear",
        [3] = "Mag",
        [4] = "Nova",
        [5] = "FT",
        [6] = "FrRes",
        [7] = "F.Ele",
    },
    [3] = {  -- Water
        [1] = "MST",
        [2] = "HST",
        [3] = "MTT",
        [4] = "Pois",
        [5] = "Dis",
        [6] = "FiRes",
    },
    [4] = {  -- Air
        [1] = "WF",
        [2] = "GoA",
        [3] = "WoA",
        [4] = "Tranq",
        [5] = "Grnd",
        [6] = "NaRes",
        [7] = "Wall",
        [8] = "Sent",
    },
}

-- Talent-required totems (talent tree, required points)
ShamanPower.TalentTotems = {
    [30706] = {1, 41},   -- Totem of Wrath (Elemental 41 points)
    [17359] = {3, 31},   -- Mana Tide Totem (Restoration 31 points)
}

-- ============================================================================
-- EARTH SHIELD (Restoration talent - 41 points)
-- ============================================================================

ShamanPower.EarthShield = {
    spellID = 32594,    -- Earth Shield Rank 3 (TBC)
    rank1 = 974,        -- Earth Shield Rank 1
    rank2 = 32593,      -- Earth Shield Rank 2
    rank3 = 32594,      -- Earth Shield Rank 3
    buffID = 32594,     -- Buff that appears on target
    talentTree = 3,     -- Restoration
    talentPoints = 41,  -- Required talent points
    icon = "Interface\\Icons\\Spell_Nature_SkinOfEarth",
}

-- Check if player has Earth Shield talent
function ShamanPower:HasEarthShield()
    -- Check if the player knows any rank of Earth Shield
    local name = GetSpellInfo(self.EarthShield.rank1)
    if name and IsSpellKnown(self.EarthShield.rank1) then return true end
    name = GetSpellInfo(self.EarthShield.rank2)
    if name and IsSpellKnown(self.EarthShield.rank2) then return true end
    name = GetSpellInfo(self.EarthShield.rank3)
    if name and IsSpellKnown(self.EarthShield.rank3) then return true end
    return false
end

-- Get the highest rank of Earth Shield the player knows
function ShamanPower:GetEarthShieldSpell()
    local spellName = GetSpellInfo(self.EarthShield.rank3)
    if spellName and IsSpellKnown(self.EarthShield.rank3) then
        return spellName, self.EarthShield.rank3
    end
    spellName = GetSpellInfo(self.EarthShield.rank2)
    if spellName and IsSpellKnown(self.EarthShield.rank2) then
        return spellName, self.EarthShield.rank2
    end
    spellName = GetSpellInfo(self.EarthShield.rank1)
    if spellName and IsSpellKnown(self.EarthShield.rank1) then
        return spellName, self.EarthShield.rank1
    end
    return nil, nil
end

-- ============================================================================
-- TOTEM BUFFS (what buffs the totems apply)
-- Used for checking if party members have the buff
-- ============================================================================

ShamanPower.TotemBuffs = {
    -- Earth totems
    [25528] = 25528,    -- Strength of Earth
    [25509] = 25509,    -- Stoneskin
    [8143] = 8143,      -- Tremor
    [2484] = 2484,      -- Earthbind
    [25525] = 25525,    -- Stoneclaw

    -- Fire totems
    [30706] = 30708,    -- Totem of Wrath buff
    [25557] = 25557,    -- Flametongue buff
    [25560] = 25560,    -- Frost Resistance

    -- Water totems
    [25570] = 25570,    -- Mana Spring
    [25567] = 25567,    -- Healing Stream
    [17359] = 17359,    -- Mana Tide
    [25563] = 25563,    -- Fire Resistance

    -- Air totems
    [25587] = 25587,    -- Windfury
    [25359] = 25359,    -- Grace of Air
    [3738] = 2895,      -- Wrath of Air buff
    [25908] = 25908,    -- Tranquil Air
    [25574] = 25574,    -- Nature Resistance
    [25577] = 25577,    -- Windwall
}

-- ============================================================================
-- WEAPON ENCHANTS
-- ============================================================================

-- Base spell IDs for weapon imbues (use rank 1 for IsSpellKnown checks)
ShamanPower.WeaponImbueSpells = {
    [1] = 8232,     -- Windfury Weapon
    [2] = 8024,     -- Flametongue Weapon
    [3] = 8033,     -- Frostbrand Weapon
    [4] = 8017,     -- Rockbiter Weapon
}

ShamanPower.WeaponEnchants = {
    [1] = 25505,    -- Windfury Weapon (Rank 4)
    [2] = 25489,    -- Flametongue Weapon (Rank 6)
    [3] = 25500,    -- Frostbrand Weapon (Rank 6)
    [4] = 25508,    -- Rockbiter Weapon (Rank 9)
}

ShamanPower.WeaponEnchantNames = {
    [1] = "Windfury",
    [2] = "Flametongue",
    [3] = "Frostbrand",
    [4] = "Rockbiter",
}

ShamanPower.WeaponEnchantShortNames = {
    [1] = "WF",
    [2] = "FT",
    [3] = "FB",
    [4] = "RB",
}

-- Map enchant IDs (from GetWeaponEnchantInfo) to imbue type index
-- This allows us to identify what imbue is currently active on a weapon
ShamanPower.EnchantIDToImbue = {
    -- Windfury Weapon (all ranks)
    [283] = 1, [284] = 1, [525] = 1, [1669] = 1, [2636] = 1,
    [3785] = 1, [3786] = 1, [3787] = 1, [7569] = 1,
    -- Flametongue Weapon (all ranks)
    [3] = 2, [4] = 2, [5] = 2, [523] = 2, [1665] = 2, [1666] = 2,
    [2634] = 2, [3779] = 2, [3780] = 2, [3781] = 2, [7567] = 2,
    -- Frostbrand Weapon (all ranks)
    [2] = 3, [12] = 3, [524] = 3, [1667] = 3, [1668] = 3, [2635] = 3,
    [3782] = 3, [3783] = 3, [3784] = 3, [7566] = 3,
    -- Rockbiter Weapon (all ranks)
    [1] = 4, [6] = 4, [29] = 4, [503] = 4, [504] = 4, [683] = 4,
    [1663] = 4, [1664] = 4, [2632] = 4, [2633] = 4, [3018] = 4, [7568] = 4,
}

-- Combined imbue definitions for dual wield
-- These are virtual "spells" that cast one imbue on main hand, another on off hand
ShamanPower.CombinedImbues = {
    [1] = {main = 1, off = 2, name = "WF / FT", shortName = "WF+FT"},  -- Windfury MH, Flametongue OH
    [2] = {main = 1, off = 3, name = "WF / FB", shortName = "WF+FB"},  -- Windfury MH, Frostbrand OH
    [3] = {main = 2, off = 2, name = "FT / FT", shortName = "FT+FT"},  -- Flametongue both hands
}

-- ============================================================================
-- ICONS
-- ============================================================================

-- Element icons (for column headers)
ShamanPower.ElementIcons = {
    [1] = "Interface\\Icons\\Spell_Nature_EarthElemental_Totem",     -- Earth
    [2] = "Interface\\Icons\\Spell_Fire_SealOfFire",                 -- Fire
    [3] = "Interface\\Icons\\Spell_Frost_SummonWaterElemental",      -- Water
    [4] = "Interface\\Icons\\Spell_Nature_InvisibilityTotem",        -- Air
}

-- Totem icons by element
ShamanPower.TotemIcons = {
    [1] = {  -- Earth
        [1] = "Interface\\Icons\\Spell_Nature_EarthBindTotem",       -- Strength of Earth
        [2] = "Interface\\Icons\\Spell_Nature_StoneSkinTotem",       -- Stoneskin
        [3] = "Interface\\Icons\\Spell_Nature_TremorTotem",          -- Tremor
        [4] = "Interface\\Icons\\Spell_Nature_StrengthOfEarthTotem02", -- Earthbind
        [5] = "Interface\\Icons\\Spell_Nature_StoneClawTotem",       -- Stoneclaw
        [6] = "Interface\\Icons\\Spell_Nature_EarthElemental_Totem", -- Earth Elemental
    },
    [2] = {  -- Fire
        [1] = "Interface\\Icons\\Spell_Fire_TotemOfWrath",           -- Totem of Wrath
        [2] = "Interface\\Icons\\Spell_Fire_SearingTotem",           -- Searing
        [3] = "Interface\\Icons\\Spell_Fire_SelfDestruct",           -- Magma
        [4] = "Interface\\Icons\\Spell_Fire_SealOfFire",             -- Fire Nova
        [5] = "Interface\\Icons\\Spell_Nature_GuardianWard",         -- Flametongue
        [6] = "Interface\\Icons\\Spell_FrostResistanceTotem_01",     -- Frost Resistance
        [7] = "Interface\\Icons\\Spell_Fire_Elemental_Totem",        -- Fire Elemental
    },
    [3] = {  -- Water
        [1] = "Interface\\Icons\\Spell_Nature_ManaRegenTotem",       -- Mana Spring
        [2] = "Interface\\Icons\\INV_Spear_04",                      -- Healing Stream
        [3] = "Interface\\Icons\\Spell_Frost_SummonWaterElemental",  -- Mana Tide
        [4] = "Interface\\Icons\\Spell_Nature_PoisonCleansingTotem", -- Poison Cleansing
        [5] = "Interface\\Icons\\Spell_Nature_DiseaseCleansingTotem",-- Disease Cleansing
        [6] = "Interface\\Icons\\Spell_FireResistanceTotem_01",      -- Fire Resistance
    },
    [4] = {  -- Air
        [1] = "Interface\\Icons\\Spell_Nature_Windfury",             -- Windfury
        [2] = "Interface\\Icons\\Spell_Nature_InvisibilityTotem",    -- Grace of Air
        [3] = "Interface\\Icons\\Spell_Nature_SlowingTotem",         -- Wrath of Air
        [4] = "Interface\\Icons\\Spell_Nature_Brilliance",           -- Tranquil Air
        [5] = "Interface\\Icons\\Spell_Nature_GroundingTotem",       -- Grounding
        [6] = "Interface\\Icons\\Spell_Nature_NatureResistanceTotem",-- Nature Resistance
        [7] = "Interface\\Icons\\Spell_Nature_EarthBind",            -- Windwall
        [8] = "Interface\\Icons\\Spell_Nature_RemoveCurse",          -- Sentry
    },
}

-- Weapon enchant icons
ShamanPower.WeaponIcons = {
    [1] = "Interface\\Icons\\Spell_Nature_Cyclone",                  -- Windfury
    [2] = "Interface\\Icons\\Spell_Fire_FlameTounge",                -- Flametongue
    [3] = "Interface\\Icons\\Spell_Frost_FrostBrand",                -- Frostbrand
    [4] = "Interface\\Icons\\Spell_Nature_RockBiter",                -- Rockbiter
}

-- ============================================================================
-- UI LAYOUTS (compatible with PallyPower layout format)
-- c = class/element buttons, p = player buttons, ab = auto button, rf = seal/weapon button
-- ============================================================================

-- Helper to create player button positions
local function createPlayerPositions(startX, startY, spacing, count)
    local positions = {}
    for i = 1, count do
        positions[i] = {x = startX, y = startY + (i-1) * spacing}
    end
    return positions
end

ShamanPower.Layouts = {
    ["Vertical"] = {
        -- Vertical layout - buttons stack down, players expand right
        c = {
            [1] = {x = 0, y = 0, p = createPlayerPositions(1, 0, 0, 8)},   -- Earth
            [2] = {x = 0, y = -1, p = createPlayerPositions(1, 0, 0, 8)},  -- Fire
            [3] = {x = 0, y = -2, p = createPlayerPositions(1, 0, 0, 8)},  -- Water
            [4] = {x = 0, y = -3, p = createPlayerPositions(1, 0, 0, 8)},  -- Air
        },
        ab = {x = 0, y = -4},
        rf = {x = 0, y = -5},
        rfd = {x = 0, y = -4},  -- rf disabled position
        aura = {x = 0, y = 1},
        au = {x = 0, y = 1},
        aud1 = {x = 0, y = 1},
        aud2 = {x = 0, y = 1},
        dh = {x = 0, y = -6},
    },
    ["Horizontal"] = {
        -- Horizontal layout - buttons go right, players expand down
        c = {
            [1] = {x = 0, y = 0, p = createPlayerPositions(0, -1, -1, 8)},   -- Earth
            [2] = {x = 1, y = 0, p = createPlayerPositions(0, -1, -1, 8)},   -- Fire
            [3] = {x = 2, y = 0, p = createPlayerPositions(0, -1, -1, 8)},   -- Water
            [4] = {x = 3, y = 0, p = createPlayerPositions(0, -1, -1, 8)},   -- Air
        },
        ab = {x = 4, y = 0},
        rf = {x = 5, y = 0},
        rfd = {x = 4, y = 0},  -- rf disabled position
        aura = {x = -1, y = 0},
        au = {x = -1, y = 0},
        aud1 = {x = -1, y = 0},
        aud2 = {x = -1, y = 0},
        dh = {x = 6, y = 0},
    },
    ["VerticalLeft"] = {
        -- Vertical Left layout - same as Vertical but flyouts expand to the left
        c = {
            [1] = {x = 0, y = 0, p = createPlayerPositions(1, 0, 0, 8)},   -- Earth
            [2] = {x = 0, y = -1, p = createPlayerPositions(1, 0, 0, 8)},  -- Fire
            [3] = {x = 0, y = -2, p = createPlayerPositions(1, 0, 0, 8)},  -- Water
            [4] = {x = 0, y = -3, p = createPlayerPositions(1, 0, 0, 8)},  -- Air
        },
        ab = {x = 0, y = -4},
        rf = {x = 0, y = -5},
        rfd = {x = 0, y = -4},  -- rf disabled position
        aura = {x = 0, y = 1},
        au = {x = 0, y = 1},
        aud1 = {x = 0, y = 1},
        aud2 = {x = 0, y = 1},
        dh = {x = 0, y = -6},
    },
}

-- ============================================================================
-- RECOMMENDED ASSIGNMENTS (auto-assign presets)
-- ============================================================================

-- Default totem recommendations by group composition
ShamanPower.DefaultAssignments = {
    -- For melee groups (warriors, rogues, etc.)
    melee = {
        [1] = 1,  -- Strength of Earth
        [2] = 2,  -- Searing Totem (or ToW if Elemental)
        [3] = 1,  -- Mana Spring
        [4] = 1,  -- Windfury
    },
    -- For caster groups (mages, warlocks, etc.)
    caster = {
        [1] = 1,  -- Strength of Earth (or Stoneskin)
        [2] = 1,  -- Totem of Wrath (if available)
        [3] = 1,  -- Mana Spring
        [4] = 3,  -- Wrath of Air
    },
    -- For healer groups
    healer = {
        [1] = 2,  -- Stoneskin
        [2] = 5,  -- Flametongue
        [3] = 1,  -- Mana Spring
        [4] = 3,  -- Wrath of Air
    },
}

-- ============================================================================
-- SKINS (UI appearance)
-- ============================================================================

ShamanPower.Skins = {
    ["None"] = "",
    ["Banto"] = "Interface\\AddOns\\ShamanPower\\Skins\\Banto",
    ["Glaze"] = "Interface\\AddOns\\ShamanPower\\Skins\\Glaze",
    ["Gloss"] = "Interface\\AddOns\\ShamanPower\\Skins\\Gloss",
    ["Healbot"] = "Interface\\AddOns\\ShamanPower\\Skins\\HealBot",
    ["oCB"] = "Interface\\AddOns\\ShamanPower\\Skins\\oCB",
    ["Smooth"] = "Interface\\AddOns\\ShamanPower\\Skins\\smooth",
}

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

-- Get totem spell ID by element and index
function ShamanPower:GetTotemSpell(element, totemIndex)
    local elementTotems = self.Totems[element]
    if elementTotems and elementTotems[totemIndex] then
        return elementTotems[totemIndex]
    end
    return nil
end

-- Get totem name by element and index
function ShamanPower:GetTotemName(element, totemIndex)
    local names = self.TotemNames[element]
    if names and names[totemIndex] then
        return names[totemIndex]
    end
    return "Unknown"
end

-- Get totem icon by element and index
function ShamanPower:GetTotemIcon(element, totemIndex)
    local icons = self.TotemIcons[element]
    if icons and icons[totemIndex] then
        return icons[totemIndex]
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- Check if a totem requires a talent
function ShamanPower:TotemRequiresTalent(spellID)
    return self.TalentTotems[spellID] ~= nil
end

-- Get talent requirement for a totem
function ShamanPower:GetTotemTalentRequirement(spellID)
    return self.TalentTotems[spellID]
end

-- ============================================================================
-- COMPATIBILITY STRUCTURES
-- These are placeholders for code still referencing old PallyPower structures
-- ============================================================================

-- Spell arrays for compatibility - maps to element/totem names
-- Used for reporting assignments to chat
ShamanPower.Spells = {
    [1] = "Earth Totem",
    [2] = "Fire Totem",
    [3] = "Water Totem",
    [4] = "Air Totem",
}
ShamanPower.GSpells = {
    [1] = "Earth Totem",
    [2] = "Fire Totem",
    [3] = "Water Totem",
    [4] = "Air Totem",
}
ShamanPower.Auras = {}
-- Seals maps to weapon enchant names for Options compatibility
ShamanPower.Seals = {
    [1] = GetSpellInfo(25505) or "Windfury Weapon",    -- Windfury Weapon
    [2] = GetSpellInfo(25489) or "Flametongue Weapon", -- Flametongue Weapon
    [3] = GetSpellInfo(25500) or "Frostbrand Weapon",  -- Frostbrand Weapon
    [4] = GetSpellInfo(25508) or "Rockbiter Weapon",   -- Rockbiter Weapon
}
ShamanPower.Cooldowns = {}
ShamanPower.NormalBuffs = {}
ShamanPower.GreaterBuffs = {}

-- Class ID mapping (for compatibility - will be replaced with group-based)
ShamanPower.ClassID = {
    [1] = "EARTH",
    [2] = "FIRE",
    [3] = "WATER",
    [4] = "AIR",
}

ShamanPower.ClassToID = {
    ["EARTH"] = 1,
    ["FIRE"] = 2,
    ["WATER"] = 3,
    ["AIR"] = 4,
}

-- Empty icon arrays for compatibility
ShamanPower.BlessingIcons = {}
ShamanPower.NormalBlessingIcons = {}
ShamanPower.AuraIcons = {}
ShamanPower.SealIcons = {}
ShamanPower.ClassIcons = {
    [1] = ShamanPower.ElementIcons[1],  -- Earth
    [2] = ShamanPower.ElementIcons[2],  -- Fire
    [3] = ShamanPower.ElementIcons[3],  -- Water
    [4] = ShamanPower.ElementIcons[4],  -- Air
}
