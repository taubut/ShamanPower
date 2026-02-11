-- ============================================================================
-- ShamanPower Totem Plates Module
-- Replaces totem nameplates with clean, recognizable icons
-- ============================================================================

local SP = ShamanPower
if not SP then return end

-- Mark module as loaded
SP.TotemPlatesLoaded = true

-- ============================================================================
-- Storage
-- ============================================================================

SP.activeTotemPlates = {}      -- unitId -> nameplate
SP.totemPlateCache = {}        -- Recycled frames
SP.detectedNameplateAddon = "Blizzard"

-- ============================================================================
-- Totem Data: NPC IDs to Totem Info Mapping
-- Based on TotemPlates Constants_shared.lua
-- ============================================================================

-- Spell IDs for getting icons dynamically
local TOTEM_SPELL_IDS = {
    -- Fire Totems
    ["Searing Totem"] = 3599,
    ["Magma Totem"] = 8190,
    ["Fire Nova Totem"] = 1535,
    ["Flametongue Totem"] = 8227,
    ["Frost Resistance Totem"] = 8181,
    ["Fire Elemental Totem"] = 2894,
    ["Totem of Wrath"] = 30706,

    -- Water Totems
    ["Healing Stream Totem"] = 5394,
    ["Mana Tide Totem"] = 16190,
    ["Mana Spring Totem"] = 5675,
    ["Poison Cleansing Totem"] = 8166,
    ["Disease Cleansing Totem"] = 8170,
    ["Fire Resistance Totem"] = 8184,

    -- Earth Totems
    ["Tremor Totem"] = 8143,
    ["Earthbind Totem"] = 2484,
    ["Stoneclaw Totem"] = 5730,
    ["Stoneskin Totem"] = 8071,
    ["Strength of Earth Totem"] = 8075,
    ["Earth Elemental Totem"] = 2062,

    -- Air Totems
    ["Grounding Totem"] = 8177,
    ["Windfury Totem"] = 8512,
    ["Grace of Air Totem"] = 8835,
    ["Wrath of Air Totem"] = 3738,
    ["Tranquil Air Totem"] = 25908,
    ["Nature Resistance Totem"] = 10595,
    ["Windwall Totem"] = 15107,
    ["Sentry Totem"] = 6495,
}

-- Get icon texture for a totem
local function GetTotemIcon(totemName)
    local spellID = TOTEM_SPELL_IDS[totemName]
    if spellID then
        local _, _, icon = GetSpellInfo(spellID)
        return icon
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- Totem pulse intervals (in seconds) - how often the totem "ticks"
-- Only totems that pulse have entries here
local TOTEM_PULSE_INTERVALS = {
    -- Earth Totems
    ["Tremor Totem"] = 3,           -- Pulses every 3 sec to remove fear/charm/sleep
    ["Earthbind Totem"] = 3,        -- Pulses every 3 sec to apply slow

    -- Water Totems
    ["Healing Stream Totem"] = 2,   -- Heals every 2 sec
    ["Mana Spring Totem"] = 2,      -- Restores mana every 2 sec
    ["Mana Tide Totem"] = 3,        -- Pulses every 3 sec (12 sec duration, 4 ticks)
    ["Poison Cleansing Totem"] = 5, -- Cleanses every 5 sec
    ["Disease Cleansing Totem"] = 5, -- Cleanses every 5 sec

    -- Fire Totems
    ["Searing Totem"] = 2.2,        -- Attacks every ~2.2 sec
    ["Magma Totem"] = 2,            -- Pulses every 2 sec
    ["Fire Nova Totem"] = 4,        -- Explodes after delay (shows countdown)
}

-- Totem priority colors (how important to kill in PvP)
-- High priority = brighter/more visible colors
local TOTEM_COLORS = {
    -- High Priority (PvP important)
    ["Tremor Totem"] = {r = 1.0, g = 0.9, b = 0.1},       -- Yellow (breaks fear!)
    ["Grounding Totem"] = {r = 0.0, g = 0.5, b = 0.9},    -- Blue (absorbs spells!)
    ["Mana Tide Totem"] = {r = 0.1, g = 0.9, b = 0.2},    -- Bright green (huge mana!)
    ["Windfury Totem"] = {r = 0.96, g = 0.0, b = 0.07},   -- Red (melee damage!)
    ["Earthbind Totem"] = {r = 0.6, g = 0.4, b = 0.2},    -- Brown (slows!)
    ["Poison Cleansing Totem"] = {r = 0.4, g = 0.9, b = 0.4}, -- Light green
    ["Disease Cleansing Totem"] = {r = 0.4, g = 0.9, b = 0.4}, -- Light green

    -- Medium Priority
    ["Healing Stream Totem"] = {r = 0.2, g = 0.6, b = 1.0}, -- Water blue
    ["Mana Spring Totem"] = {r = 0.2, g = 0.6, b = 1.0},    -- Water blue
    ["Totem of Wrath"] = {r = 1.0, g = 0.4, b = 0.1},       -- Orange
    ["Wrath of Air Totem"] = {r = 0.8, g = 0.8, b = 1.0},   -- Light purple

    -- Lower Priority
    ["Searing Totem"] = {r = 1.0, g = 0.4, b = 0.1},        -- Orange-red
    ["Magma Totem"] = {r = 1.0, g = 0.3, b = 0.0},          -- Deep orange
    ["Fire Nova Totem"] = {r = 1.0, g = 0.2, b = 0.0},      -- Red-orange
    ["Flametongue Totem"] = {r = 1.0, g = 0.5, b = 0.2},    -- Light orange
    ["Frost Resistance Totem"] = {r = 0.5, g = 0.7, b = 1.0}, -- Ice blue
    ["Fire Resistance Totem"] = {r = 1.0, g = 0.6, b = 0.4}, -- Salmon
    ["Nature Resistance Totem"] = {r = 0.4, g = 0.8, b = 0.4}, -- Nature green
    ["Stoneclaw Totem"] = {r = 0.5, g = 0.4, b = 0.3},       -- Brown
    ["Stoneskin Totem"] = {r = 0.6, g = 0.5, b = 0.4},       -- Light brown
    ["Strength of Earth Totem"] = {r = 0.5, g = 0.3, b = 0.1}, -- Dark brown
    ["Grace of Air Totem"] = {r = 0.7, g = 0.7, b = 0.9},    -- Light blue
    ["Tranquil Air Totem"] = {r = 0.6, g = 0.6, b = 0.8},    -- Pale blue
    ["Windwall Totem"] = {r = 0.7, g = 0.8, b = 0.9},        -- Wind blue
    ["Sentry Totem"] = {r = 0.5, g = 0.5, b = 0.5},          -- Gray
    ["Fire Elemental Totem"] = {r = 1.0, g = 0.3, b = 0.0},  -- Fire
    ["Earth Elemental Totem"] = {r = 0.4, g = 0.3, b = 0.2}, -- Earth
}

-- NPC ID to Totem Name mapping
-- Comprehensive list from TotemPlates Constants
local npcIdToTotemName = {
    -- ========================================
    -- FIRE TOTEMS
    -- ========================================

    -- Searing Totem (all ranks)
    [2523] = "Searing Totem",
    [3902] = "Searing Totem",
    [3903] = "Searing Totem",
    [3904] = "Searing Totem",
    [7400] = "Searing Totem",
    [7402] = "Searing Totem",
    [15480] = "Searing Totem",

    -- Magma Totem (all ranks)
    [5929] = "Magma Totem",
    [7464] = "Magma Totem",
    [7465] = "Magma Totem",
    [7466] = "Magma Totem",
    [15484] = "Magma Totem",

    -- Fire Nova Totem (all ranks)
    [5879] = "Fire Nova Totem",
    [6110] = "Fire Nova Totem",
    [6111] = "Fire Nova Totem",
    [7844] = "Fire Nova Totem",
    [7845] = "Fire Nova Totem",
    [15482] = "Fire Nova Totem",
    [15483] = "Fire Nova Totem",

    -- Flametongue Totem (all ranks)
    [5950] = "Flametongue Totem",
    [6012] = "Flametongue Totem",
    [7423] = "Flametongue Totem",
    [10557] = "Flametongue Totem",
    [15485] = "Flametongue Totem",

    -- Frost Resistance Totem (all ranks)
    [5926] = "Frost Resistance Totem",  -- Rank 1
    [7412] = "Frost Resistance Totem",  -- Rank 2
    [7413] = "Frost Resistance Totem",  -- Rank 3
    [15486] = "Frost Resistance Totem", -- Rank 4 (TBC)

    -- Fire Elemental Totem
    [15439] = "Fire Elemental Totem",

    -- Totem of Wrath
    [17539] = "Totem of Wrath",

    -- ========================================
    -- WATER TOTEMS
    -- ========================================

    -- Healing Stream Totem (all ranks)
    [3527] = "Healing Stream Totem",
    [3906] = "Healing Stream Totem",
    [3907] = "Healing Stream Totem",
    [3908] = "Healing Stream Totem",
    [3909] = "Healing Stream Totem",
    [15488] = "Healing Stream Totem",

    -- Mana Tide Totem
    [10467] = "Mana Tide Totem",
    [11100] = "Mana Tide Totem",
    [11101] = "Mana Tide Totem",
    [17061] = "Mana Tide Totem",

    -- Mana Spring Totem (all ranks)
    [3573] = "Mana Spring Totem",
    [7414] = "Mana Spring Totem",
    [7415] = "Mana Spring Totem",
    [7416] = "Mana Spring Totem",
    [15489] = "Mana Spring Totem",

    -- Poison Cleansing Totem
    [5923] = "Poison Cleansing Totem",

    -- Disease Cleansing Totem
    [5924] = "Disease Cleansing Totem",

    -- Fire Resistance Totem (all ranks)
    [5927] = "Fire Resistance Totem",
    [7424] = "Fire Resistance Totem",
    [7425] = "Fire Resistance Totem",
    [15487] = "Fire Resistance Totem",

    -- ========================================
    -- EARTH TOTEMS
    -- ========================================

    -- Tremor Totem
    [5913] = "Tremor Totem",

    -- Earthbind Totem
    [2630] = "Earthbind Totem",

    -- Stoneclaw Totem (all ranks)
    [3579] = "Stoneclaw Totem",
    [3911] = "Stoneclaw Totem",
    [3912] = "Stoneclaw Totem",
    [3913] = "Stoneclaw Totem",
    [7398] = "Stoneclaw Totem",
    [7399] = "Stoneclaw Totem",
    [15478] = "Stoneclaw Totem",

    -- Stoneskin Totem (all ranks)
    [5873] = "Stoneskin Totem",
    [5919] = "Stoneskin Totem",
    [5920] = "Stoneskin Totem",
    [7366] = "Stoneskin Totem",
    [7367] = "Stoneskin Totem",
    [7368] = "Stoneskin Totem",
    [15470] = "Stoneskin Totem",
    [15474] = "Stoneskin Totem",

    -- Strength of Earth Totem (all ranks)
    [5874] = "Strength of Earth Totem",
    [5921] = "Strength of Earth Totem",
    [5922] = "Strength of Earth Totem",
    [7403] = "Strength of Earth Totem",
    [15464] = "Strength of Earth Totem",
    [15479] = "Strength of Earth Totem",

    -- Earth Elemental Totem
    [15430] = "Earth Elemental Totem",

    -- ========================================
    -- AIR TOTEMS
    -- ========================================

    -- Grounding Totem
    [5925] = "Grounding Totem",

    -- Windfury Totem (all ranks)
    [6112] = "Windfury Totem",   -- Rank 1
    [7483] = "Windfury Totem",   -- Rank 2
    [7484] = "Windfury Totem",   -- Rank 3
    [15496] = "Windfury Totem",  -- Rank 4 (TBC)
    [15497] = "Windfury Totem",  -- Rank 5 (TBC)

    -- Grace of Air Totem (all ranks)
    [7486] = "Grace of Air Totem",
    [7487] = "Grace of Air Totem",
    [15463] = "Grace of Air Totem",

    -- Wrath of Air Totem
    [15447] = "Wrath of Air Totem",

    -- Tranquil Air Totem
    [15803] = "Tranquil Air Totem",

    -- Nature Resistance Totem (all ranks)
    [7467] = "Nature Resistance Totem",
    [7468] = "Nature Resistance Totem",
    [7469] = "Nature Resistance Totem",
    [15490] = "Nature Resistance Totem",

    -- Windwall Totem (all ranks)
    [9687] = "Windwall Totem",
    [9688] = "Windwall Totem",
    [9689] = "Windwall Totem",
    [15492] = "Windwall Totem",

    -- Sentry Totem
    [3968] = "Sentry Totem",
}

-- Build totem data with icons and colors
local totemData = {}
for npcId, totemName in pairs(npcIdToTotemName) do
    if not totemData[totemName] then
        totemData[totemName] = {
            name = totemName,
            texture = GetTotemIcon(totemName),
            color = TOTEM_COLORS[totemName] or {r = 0.5, g = 0.5, b = 0.5},
            npcIds = {}
        }
    end
    table.insert(totemData[totemName].npcIds, npcId)
end

-- Rebuild reverse lookup with full data
local npcIdToTotem = {}
for name, data in pairs(totemData) do
    for _, npcId in ipairs(data.npcIds) do
        npcIdToTotem[npcId] = data
    end
end

-- ============================================================================
-- Nameplate Addon Detection
-- ============================================================================

function SP:DetectNameplateAddon()
    local IsAddOnLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded

    if IsAddOnLoaded("Plater") then
        self.detectedNameplateAddon = "Plater"
    elseif IsAddOnLoaded("Kui_Nameplates") then
        self.detectedNameplateAddon = "Kui_Nameplates"
    elseif IsAddOnLoaded("ElvUI") then
        local E = _G.ElvUI and unpack(_G.ElvUI) or nil
        if E and E.private and E.private.nameplates and E.private.nameplates.enable then
            self.detectedNameplateAddon = "ElvUI"
        else
            self.detectedNameplateAddon = "Blizzard"
        end
    elseif IsAddOnLoaded("TidyPlates_ThreatPlates") then
        self.detectedNameplateAddon = "TidyPlates_ThreatPlates"
    elseif IsAddOnLoaded("TidyPlates") then
        self.detectedNameplateAddon = "TidyPlates"
    elseif IsAddOnLoaded("NeatPlates") then
        self.detectedNameplateAddon = "NeatPlates"
    else
        self.detectedNameplateAddon = "Blizzard"
    end
end

-- ============================================================================
-- Get Addon Frame for Nameplate
-- ============================================================================

function SP:GetNameplateAddonFrame(nameplate)
    local addon = self.detectedNameplateAddon

    if addon == "Blizzard" then
        return nameplate.UnitFrame
    elseif addon == "Plater" then
        return nameplate.unitFrame
    elseif addon == "ElvUI" then
        return nameplate.unitFrame
    elseif addon == "Kui_Nameplates" then
        return nameplate.kui
    elseif addon == "TidyPlates_ThreatPlates" then
        return nameplate.TPFrame
    elseif addon == "TidyPlates" then
        return nameplate.extended
    elseif addon == "NeatPlates" then
        return nameplate.extended
    end

    return nameplate.UnitFrame
end

-- ============================================================================
-- Toggle Addon Nameplate Visibility
-- ============================================================================

function SP:ToggleNameplateAddon(nameplate, show)
    local frame = self:GetNameplateAddonFrame(nameplate)
    if not frame then return end

    if show then
        if frame.UpdateAllElements then
            frame:Show()
            pcall(function()
                frame:UpdateAllElements("NAME_PLATE_UNIT_ADDED")
            end)
        else
            frame:Show()
        end
    else
        if frame.UpdateAllElements then
            pcall(function()
                frame:UpdateAllElements("NAME_PLATE_UNIT_REMOVED")
            end)
        end
        frame:Hide()
    end
end

-- ============================================================================
-- Create Totem Plate Frame
-- ============================================================================

function SP:CreateTotemPlateFrame(nameplate)
    local settings = self.opt.totemPlates or {}
    local size = settings.iconSize or 40

    -- Reuse cached frame or create new
    local frame
    if #self.totemPlateCache > 0 then
        frame = table.remove(self.totemPlateCache)
    else
        frame = CreateFrame("Frame", nil, nil, "BackdropTemplate")
        frame:SetFrameLevel(1)
        frame:SetIgnoreParentAlpha(true)

        -- Background for border effect
        frame:SetBackdrop({
            bgFile = nil,
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8,
            insets = { left = 2, right = 2, top = 2, bottom = 2 }
        })

        -- Icon texture
        frame.icon = frame:CreateTexture(nil, "ARTWORK")
        frame.icon:SetPoint("TOPLEFT", 2, -2)
        frame.icon:SetPoint("BOTTOMRIGHT", -2, 2)
        frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)  -- Remove icon borders

        -- Cooldown overlay (for pulse timer)
        frame.cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
        frame.cooldown:SetAllPoints(frame.icon)
        frame.cooldown:SetDrawEdge(false)
        frame.cooldown:SetDrawSwipe(true)
        frame.cooldown:SetHideCountdownNumbers(true)
        frame.cooldown:Hide()

        -- Pulse timer text (shows countdown to next pulse)
        frame.pulseText = frame:CreateFontString(nil, "OVERLAY")
        frame.pulseText:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
        frame.pulseText:SetPoint("CENTER", frame, "CENTER", 0, 0)
        frame.pulseText:SetTextColor(1, 1, 1, 1)
        frame.pulseText:Hide()

        -- Pulse bar (visual indicator)
        frame.pulseBar = CreateFrame("StatusBar", nil, frame)
        frame.pulseBar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 2, 2)
        frame.pulseBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
        frame.pulseBar:SetHeight(4)
        frame.pulseBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        frame.pulseBar:SetStatusBarColor(1, 1, 1, 0.9)
        frame.pulseBar:SetMinMaxValues(0, 1)
        frame.pulseBar:SetValue(1)
        frame.pulseBar:Hide()

        -- Pulse bar background
        frame.pulseBarBg = frame.pulseBar:CreateTexture(nil, "BACKGROUND")
        frame.pulseBarBg:SetAllPoints()
        frame.pulseBarBg:SetColorTexture(0, 0, 0, 0.5)

        -- Optional name text
        frame.name = frame:CreateFontString(nil, "OVERLAY")
        frame.name:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
        frame.name:SetPoint("TOP", frame, "BOTTOM", 0, -2)

        -- Selection highlight
        frame.highlight = frame:CreateTexture(nil, "OVERLAY")
        frame.highlight:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-BarFill")
        frame.highlight:SetBlendMode("ADD")
        frame.highlight:SetAlpha(0)
        frame.highlight:SetPoint("TOPLEFT", 4, -4)
        frame.highlight:SetPoint("BOTTOMRIGHT", -4, 4)

        -- Enable mouse for tooltip hover
        frame:EnableMouse(true)

        -- Tooltip on hover
        frame:SetScript("OnEnter", function(self)
            if self.totemInfo then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(self.totemInfo.name, 1, 1, 1)
                if self.isEnemy then
                    GameTooltip:AddLine("Enemy Totem", 1, 0.2, 0.2)
                else
                    GameTooltip:AddLine("Friendly Totem", 0.2, 1, 0.2)
                end
                GameTooltip:Show()
                self.highlight:SetAlpha(0.3)
            end
        end)

        frame:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
            self.highlight:SetAlpha(0)
        end)
    end

    frame:SetSize(size, size)
    frame:SetParent(nameplate)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", nameplate, "CENTER", 0, 0)

    return frame
end

-- ============================================================================
-- Update Totem Plate Highlights (for target selection)
-- ============================================================================

function SP:UpdateTotemPlateHighlights()
    local targetGUID = UnitGUID("target")

    for unitId, nameplate in pairs(self.activeTotemPlates) do
        local frame = nameplate.totemPlateFrame
        if frame and frame:IsShown() then
            local unitGUID = UnitGUID(unitId)
            if unitGUID and unitGUID == targetGUID then
                frame.highlight:SetAlpha(0.5)
            else
                frame.highlight:SetAlpha(0)
            end
        end
    end
end

-- ============================================================================
-- Main Event Handler - OnUnitAdded
-- ============================================================================

function SP:OnTotemPlateUnitAdded(unitId)
    local settings = self.opt.totemPlates
    if not settings or not settings.enabled then return end

    local nameplate = C_NamePlate.GetNamePlateForUnit(unitId)
    if not nameplate then return end

    -- Parse GUID to get NPC ID
    local guid = UnitGUID(unitId)
    if not guid then return end

    local npcType, _, _, _, _, npcId = strsplit("-", guid)
    if npcType ~= "Creature" then return end

    npcId = tonumber(npcId)
    local totemInfo = npcIdToTotem[npcId]
    if not totemInfo then return end  -- Not a totem

    -- Check if this specific totem is enabled
    local totemKey = "totem_" .. totemInfo.name:gsub(" ", "_"):lower()
    if settings.perTotem and settings.perTotem[totemKey] == false then
        self:ToggleNameplateAddon(nameplate, true)
        return
    end

    -- Check friendly/enemy filter
    local isEnemy = UnitIsEnemy("player", unitId)
    if isEnemy and settings.showEnemy == false then
        self:ToggleNameplateAddon(nameplate, true)
        return
    end
    if not isEnemy and settings.showFriendly == false then
        self:ToggleNameplateAddon(nameplate, true)
        return
    end

    -- Create/reuse totem plate frame
    local frame = self:CreateTotemPlateFrame(nameplate)
    frame.unitId = unitId
    frame.totemInfo = totemInfo
    frame.isEnemy = isEnemy

    -- Set icon
    frame.icon:SetTexture(totemInfo.texture)

    -- Set border color (red for enemy, green for friendly)
    if isEnemy then
        frame:SetBackdropBorderColor(0.82, 0.15, 0.08, 1)
    else
        frame:SetBackdropBorderColor(0.08, 0.82, 0.09, 1)
    end

    -- Set alpha
    frame:SetAlpha(settings.alpha or 0.9)

    -- Optional name
    if settings.showName then
        frame.name:SetText(totemInfo.name)
        frame.name:Show()
    else
        frame.name:Hide()
    end

    -- Start pulse timer if this totem pulses
    local pulseInterval = TOTEM_PULSE_INTERVALS[totemInfo.name]
    if pulseInterval and settings.showPulseTimer then
        self:StartPulseTimer(frame, pulseInterval)
    else
        self:StopPulseTimer(frame)
    end

    -- Hide the underlying nameplate
    self:ToggleNameplateAddon(nameplate, false)

    nameplate.totemPlateFrame = frame
    frame:Show()

    self.activeTotemPlates[unitId] = nameplate

    -- Update highlights if this is our target
    self:UpdateTotemPlateHighlights()
end

-- ============================================================================
-- Main Event Handler - OnUnitRemoved
-- ============================================================================

function SP:OnTotemPlateUnitRemoved(unitId)
    local nameplate = self.activeTotemPlates[unitId]
    if not nameplate then return end

    if nameplate.totemPlateFrame then
        -- Stop pulse timer before recycling
        self:StopPulseTimer(nameplate.totemPlateFrame)

        nameplate.totemPlateFrame:Hide()
        nameplate.totemPlateFrame:SetParent(nil)
        nameplate.totemPlateFrame:ClearAllPoints()
        table.insert(self.totemPlateCache, nameplate.totemPlateFrame)
        nameplate.totemPlateFrame = nil
    end

    self:ToggleNameplateAddon(nameplate, true)
    self.activeTotemPlates[unitId] = nil
end

-- ============================================================================
-- Update All Totem Plate Sizes
-- ============================================================================

function SP:UpdateTotemPlatesSize()
    local settings = self.opt.totemPlates or {}
    local size = settings.iconSize or 40

    for unitId, nameplate in pairs(self.activeTotemPlates) do
        local frame = nameplate.totemPlateFrame
        if frame then
            frame:SetSize(size, size)
        end
    end
end

-- ============================================================================
-- Pulse Timer Functions
-- ============================================================================

-- Start pulse timer for a totem plate frame
function SP:StartPulseTimer(frame, pulseInterval)
    if not pulseInterval or pulseInterval <= 0 then return end

    local settings = self.opt.totemPlates or {}
    if not settings.showPulseTimer then return end

    frame.pulseInterval = pulseInterval
    frame.pulseStartTime = GetTime()
    frame.lastPulseTime = GetTime()

    -- Apply current size settings
    local textSize = settings.pulseTextSize or 14
    local barHeight = settings.pulseBarHeight or 4

    if frame.pulseText then
        frame.pulseText:SetFont("Fonts\\FRIZQT__.TTF", textSize, "OUTLINE")
    end
    if frame.pulseBar then
        frame.pulseBar:SetHeight(barHeight)
    end

    -- Show pulse elements based on settings
    if settings.showPulseText then
        frame.pulseText:Show()
    end
    if settings.showPulseBar then
        frame.pulseBar:Show()
    end

    -- Set up OnUpdate for this frame
    frame:SetScript("OnUpdate", function(self, elapsed)
        SP:UpdatePulseTimer(self)
    end)
end

-- Stop pulse timer for a totem plate frame
function SP:StopPulseTimer(frame)
    frame.pulseInterval = nil
    frame.pulseStartTime = nil
    frame.lastPulseTime = nil

    if frame.pulseText then
        frame.pulseText:Hide()
    end
    if frame.pulseBar then
        frame.pulseBar:Hide()
    end
    if frame.cooldown then
        frame.cooldown:Hide()
    end

    frame:SetScript("OnUpdate", nil)
end

-- Update pulse timer display
function SP:UpdatePulseTimer(frame)
    if not frame.pulseInterval then return end

    local settings = self.opt.totemPlates or {}
    local now = GetTime()
    local elapsed = now - frame.lastPulseTime
    local remaining = frame.pulseInterval - elapsed

    -- Handle pulse cycle reset
    if remaining <= 0 then
        frame.lastPulseTime = now
        remaining = frame.pulseInterval
    end

    -- Update pulse text
    if settings.showPulseText and frame.pulseText then
        frame.pulseText:SetText(string.format("%.1f", remaining))

        -- Color based on urgency (green -> yellow -> red)
        local pct = remaining / frame.pulseInterval
        if pct > 0.5 then
            frame.pulseText:SetTextColor(1, 1, 1, 1)  -- White
        elseif pct > 0.25 then
            frame.pulseText:SetTextColor(1, 1, 0, 1)  -- Yellow
        else
            frame.pulseText:SetTextColor(1, 0.3, 0.3, 1)  -- Red
        end
    end

    -- Update pulse bar
    if settings.showPulseBar and frame.pulseBar then
        local pct = remaining / frame.pulseInterval
        frame.pulseBar:SetValue(pct)

        -- Color the bar based on progress
        if pct > 0.5 then
            frame.pulseBar:SetStatusBarColor(1, 1, 1, 0.9)  -- White
        elseif pct > 0.25 then
            frame.pulseBar:SetStatusBarColor(1, 1, 0, 0.9)  -- Yellow
        else
            frame.pulseBar:SetStatusBarColor(1, 0.3, 0.3, 0.9)  -- Red
        end
    end

    -- Update cooldown swipe (optional visual)
    if settings.showPulseCooldown and frame.cooldown then
        -- Only set cooldown once per cycle
        if elapsed < 0.1 then
            frame.cooldown:SetCooldown(frame.lastPulseTime, frame.pulseInterval)
            frame.cooldown:Show()
        end
    end
end

-- Update pulse timer settings for all active plates
function SP:UpdateTotemPlatesPulseSettings()
    local settings = self.opt.totemPlates or {}
    local textSize = settings.pulseTextSize or 14
    local barHeight = settings.pulseBarHeight or 4

    for unitId, nameplate in pairs(self.activeTotemPlates) do
        local frame = nameplate.totemPlateFrame
        if frame then
            -- Update font size
            if frame.pulseText then
                frame.pulseText:SetFont("Fonts\\FRIZQT__.TTF", textSize, "OUTLINE")
            end

            -- Update bar height
            if frame.pulseBar then
                frame.pulseBar:SetHeight(barHeight)
            end

            if frame.pulseInterval then
                -- Update visibility based on new settings
                if settings.showPulseText then
                    frame.pulseText:Show()
                else
                    frame.pulseText:Hide()
                end

                if settings.showPulseBar then
                    frame.pulseBar:Show()
                else
                    frame.pulseBar:Hide()
                end

                if not settings.showPulseCooldown and frame.cooldown then
                    frame.cooldown:Hide()
                end

                -- If all pulse options are disabled, stop the timer
                if not settings.showPulseTimer then
                    self:StopPulseTimer(frame)
                end
            end
        end
    end
end

-- ============================================================================
-- Event Frame Setup
-- ============================================================================

function SP:SetupTotemPlatesEvents()
    if self.totemPlatesEventFrame then return end

    local frame = CreateFrame("Frame")
    frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    frame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    frame:RegisterEvent("PLAYER_TARGET_CHANGED")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")

    frame:SetScript("OnEvent", function(_, event, ...)
        if event == "NAME_PLATE_UNIT_ADDED" then
            SP:OnTotemPlateUnitAdded(...)
        elseif event == "NAME_PLATE_UNIT_REMOVED" then
            SP:OnTotemPlateUnitRemoved(...)
        elseif event == "PLAYER_TARGET_CHANGED" then
            SP:UpdateTotemPlateHighlights()
        elseif event == "PLAYER_ENTERING_WORLD" then
            SP.activeTotemPlates = {}
        end
    end)

    self.totemPlatesEventFrame = frame
end

function SP:EnableTotemPlatesEvents()
    if self.totemPlatesEventFrame then
        self.totemPlatesEventFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
        self.totemPlatesEventFrame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    end

    -- Enable CVars for totem nameplates (only out of combat)
    if SetCVar and not InCombatLockdown() then
        pcall(function()
            SetCVar("nameplateShowEnemyTotems", "1")
            SetCVar("nameplateShowFriendlyTotems", "1")
        end)
    end
end

function SP:DisableTotemPlatesEvents()
    if self.totemPlatesEventFrame then
        self.totemPlatesEventFrame:UnregisterEvent("NAME_PLATE_UNIT_ADDED")
        self.totemPlatesEventFrame:UnregisterEvent("NAME_PLATE_UNIT_REMOVED")
    end

    -- Clean up active plates
    for unitId, _ in pairs(self.activeTotemPlates) do
        self:OnTotemPlateUnitRemoved(unitId)
    end
end

-- ============================================================================
-- Toggle Function
-- ============================================================================

function SP:ToggleTotemPlates()
    self:EnsureProfileTable("totemPlates")
    local enabled = self.opt.totemPlates.enabled

    if enabled then
        self:SetupTotemPlatesEvents()
        self:EnableTotemPlatesEvents()

        -- Scan existing nameplates
        local nameplates = C_NamePlate.GetNamePlates()
        if nameplates then
            for _, nameplate in ipairs(nameplates) do
                local unitId = nameplate.namePlateUnitToken
                if unitId then
                    self:OnTotemPlateUnitAdded(unitId)
                end
            end
        end
    else
        self:DisableTotemPlatesEvents()
    end
end

-- ============================================================================
-- Initialize Function
-- ============================================================================

function SP:InitializeTotemPlates()
    self:EnsureProfileTable("totemPlates")
    self:DetectNameplateAddon()

    if self.opt.totemPlates.enabled then
        self:SetupTotemPlatesEvents()
        self:EnableTotemPlatesEvents()
    end
end
