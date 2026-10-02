-- "First Surname" on WoW: Forever (SPCompat.UnitName); other clients unchanged
local UnitName = (SPCompat and SPCompat.UnitName) or UnitName
local GetTotemInfo = (SPCompat and SPCompat.GetTotemInfo) or GetTotemInfo  -- guarded on restricted clients
--[[
    ShamanPower_TremorReminder
    Proactive Tremor Totem reminder when targeting fear-casting mobs

    Shows a Tremor Totem icon when you target a mob known to cast fears,
    even before anyone in your party gets feared.
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
local TREMOR_TOTEM_NAME = GetSpellInfo(8143) or "Tremor Totem"
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
    ["Golemagg the Incinerator"] = true,
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
        -- In dungeons and raids the game hides mob names (measured), so those entries wait until names are readable.
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
local lastTargetName = nil

-- Check if a mob name is in the fear-caster list
-- Restricted clients: unit identity (name/GUID) is secret on instanced maps.
-- Ask the client before touching it so nothing here ever branches on a secret.
local function SPIdentitySecret(unit)
	if C_Secrets and C_Secrets.ShouldUnitIdentityBeSecret then
		local ok, v = pcall(C_Secrets.ShouldUnitIdentityBeSecret, unit)
		if ok and v == true then return true end
	end
	if issecretvalue and issecretvalue((UnitGUID(unit))) then return true end
	return false
end

local function IsFearCaster(name)
    if not name then return false end

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

-- Check if Tremor Totem is currently active
local function IsTremorTotemActive()
    -- On Forever the Earth slot may be secret; the core resolver falls back
    -- to the addon's own-cast shadow model instead of treating it as empty.
    if SPCompat.FOREVER then
        local haveTotem, totemName = ShamanPower:GetElementTotemInfo(1)
        if issecretvalue(haveTotem) or issecretvalue(totemName) then return false end
        return haveTotem and type(totemName) == "string" and totemName:find("Tremor", 1, true) ~= nil
    end
    for slot = 1, 4 do
        local haveTotem, totemName = GetTotemInfo(slot)
        if haveTotem and totemName and totemName:find("Tremor") then
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
            local targetName = UnitName("target")
            if targetName then
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
    else
        reminderFrame.glow:Hide()
        reminderFrame.glowAnim:Stop()
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

-- Check if we should show the reminder
local function CheckTarget()
    if SP.TremorDemoActive then return end
    -- instanced map on a restricted client: names are secret, so stand down, and
    -- take down a reminder that was already up (it can no longer be checked)
    if SPIdentitySecret("target") then
        HideReminder()
        return
    end
    local sv = ShamanPowerTremorReminderDB
    if not sv or not sv.enabled or SP:IsOff() then
        HideReminder()
        return
    end

    -- Check if we're targeting an attackable unit
    if not UnitExists("target") or not UnitCanAttack("player", "target") then
        HideReminder()
        lastTargetName = nil
        return
    end

    local targetName = UnitName("target")

    -- Check if target is a known fear-caster
    if not IsFearCaster(targetName) then
        HideReminder()
        lastTargetName = targetName
        return
    end

    -- Check if Tremor Totem is already active
    if sv.hideWhenTremorActive and IsTremorTotemActive() then
        HideReminder()
        lastTargetName = targetName
        return
    end

    -- Only play sound once per target
    local shouldSound = (targetName ~= lastTargetName)
    lastTargetName = targetName

    if not isShowing then
        if shouldSound and sv.playSound then
            ShamanPower:PlaySoundWithVolume(ShamanPower:GetSoundFile(sv.soundName or "Raid Warning"), sv.soundVolume, true)
        end
    end

    ShowReminder()
end

-- Event handler frame
local eventFrame = CreateFrame("Frame")
if SPCompat and SPCompat.StressRegister then SPCompat.StressRegister(eventFrame, "Tremor Reminder") end
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:RegisterEvent("PLAYER_TOTEM_UPDATE")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

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

    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Re-check on zone changes
        C_Timer.After(1, CheckTarget)
    end
end)

-- Enable ShamanPower switched: off hides the reminder, on checks the target again
SP:OnOnOff(function() CheckTarget() end)

-- Slash commands
SLASH_SPTREMOR1 = "/sptremor"
SlashCmdList["SPTREMOR"] = function(msg)
    msg = msg:lower():trim()

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
        local mobName = msg:sub(5):trim()
        if mobName ~= "" then
            ShamanPowerTremorReminderDB.fearCasters[mobName] = true
            print("|cff0070ddShamanPower|r [Tremor Reminder]: Added '" .. mobName .. "' to fear-caster list.")
        end

    elseif msg:find("^remove ") then
        local mobName = msg:sub(8):trim()
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
        local name = not SPIdentitySecret("target") and UnitName("target") or nil
        if name and UnitCanAttack("player", "target") then
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
