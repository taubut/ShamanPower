-- ============================================================================
-- ShamanPower [SPRange] Module
-- Totem Range Tracker - Shows which totems are affecting you
-- ============================================================================

-- "First Surname" on WoW: Forever (SPCompat.UnitName); other clients unchanged
local UnitName = (SPCompat and SPCompat.UnitName) or UnitName
local GetRaidRosterInfo = (SPCompat and SPCompat.GetRaidRosterInfo) or GetRaidRosterInfo
local SP = ShamanPower
-- Forever returns a LIST of enchants per weapon; the legacy global reports only
-- the first entry, which is empty when the imbue lands in the second.
local GetWeaponEnchantInfo = (SPCompat and SPCompat.GetWeaponEnchantInfo) or GetWeaponEnchantInfo
if not SP then
	print("|cff0070ddShamanPower [SPRange]:|r Core addon not found!")
	return
end

-- Mark module as loaded
SP.SPRangeLoaded = true

ShamanPower_RangeTracker = ShamanPower_RangeTracker or {}

-- Trackable totems with their detection methods
-- detection: "buff" = check for buff, "weapon" = check weapon enchant
-- buffSpellID: the BUFF spell ID (aura on party members), NOT the cast spell ID
-- buffName is resolved at load time via GetSpellInfo (same approach as TotemTimers)
SP.TrackableTotems = {
	-- Earth
	{
		id = "soe",
		name = "Strength of Earth",
		element = 1,
		index = 1,
		spellID = 8075,
		detection = "buff",
		buffSpellID = 8076,
	},
	{
		id = "stoneskin",
		name = "Stoneskin",
		element = 1,
		index = 2,
		spellID = 8071,
		detection = "buff",
		buffSpellID = 8072,
	},
	-- Fire
	{
		id = "tow",
		name = "Totem of Wrath",
		element = 2,
		index = 1,
		spellID = 30706,
		detection = "buff",
		buffSpellID = 30708,
	},
	{
		id = "flametongue",
		name = "Flametongue Totem",
		element = 2,
		index = 5,
		spellID = 8227,
		detection = "buff",
		buffSpellID = 8215,
	},
	{
		id = "frostresist",
		name = "Frost Resistance",
		element = 2,
		index = 6,
		spellID = 8181,
		detection = "buff",
		buffSpellID = 8182,
	},
	-- Water
	{
		id = "manaspring",
		name = "Mana Spring",
		element = 3,
		index = 1,
		spellID = 5675,
		detection = "buff",
		buffSpellID = 5677,
	},
	{
		id = "healingstream",
		name = "Healing Stream",
		element = 3,
		index = 2,
		spellID = 5394,
		detection = "buff",
		buffSpellID = 5672,
	},
	{
		id = "fireresist",
		name = "Fire Resistance",
		element = 3,
		index = 6,
		spellID = 8184,
		detection = "buff",
		buffSpellID = 8185,
	},
	{
		id = "manatide",
		name = "Mana Tide Totem",
		element = 3,
		index = 3,
		spellID = 16190,
		detection = "buff",
		buffSpellID = 16191,
	},
	-- Air
	{
		id = "windfury",
		name = "Windfury Totem",
		element = 4,
		index = 1,
		spellID = 8512,
		detection = "weapon",  -- Special: check weapon enchant
		buffSpellID = 8513,
	},
	{
		id = "graceofair",
		name = "Grace of Air",
		element = 4,
		index = 2,
		spellID = 8835,
		detection = "buff",
		buffSpellID = 8836,
	},
	{
		id = "wrathofair",
		name = "Wrath of Air",
		element = 4,
		index = 3,
		spellID = 3738,
		detection = "buff",
		buffSpellID = 2895,
	},
	{
		id = "tranquilair",
		name = "Tranquil Air",
		element = 4,
		index = 4,
		spellID = 25908,
		detection = "buff",
		buffSpellID = 25909,
		buffSpellIDs = { 25909 },
		-- name AND icon rows are encrypted on WoW: Forever; the client cannot draw it
		icon = "Interface\\Icons\\Spell_Nature_Brilliance",
	},
	{
		id = "natureresist",
		name = "Nature Resistance",
		element = 4,
		index = 6,
		spellID = 10595,
		detection = "buff",
		buffSpellID = 10596,
	},
	{
		id = "windwall",
		name = "Windwall",
		element = 4,
		index = 7,
		spellID = 15107,
		detection = "buff",
		buffSpellID = 15108,
	},
}

-- Resolve buff spell IDs to exact names via GetSpellInfo (same approach as TotemTimers)
for _, totem in ipairs(SP.TrackableTotems) do
	if totem.buffSpellID then
		-- Forever reuses 8215 (TBC's Flametongue Totem buff) for "Rapid Cast"; the
		-- aura party members carry there is the effect spell
		if totem.id == "flametongue" and WOW_PROJECT_ID ~= nil and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE then totem.buffSpellID = 8230 end
		totem.buffName = GetSpellInfo(totem.buffSpellID)
	end
	if WOW_PROJECT_ID ~= nil and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE then
		-- Build once, after client-specific ID overrides; nameless auras need
		-- ID matching, while named entries retain the single native lookup.
		totem.buffSpellIDs = totem.buffSpellIDs or { totem.buffSpellID }
		totem.buffSpellIDSet = {}
		for _, spellID in ipairs(totem.buffSpellIDs) do totem.buffSpellIDSet[spellID] = true end
	end
end

-- Only totems this client has. WoW: Forever has no Totem of Wrath and no Wrath
-- of Air; a tracked totem the client lacks would sit at MISSING forever.
if WOW_PROJECT_ID ~= nil and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE and SPCompat and SPCompat.SpellExists then
	local kept = {}
	for _, totem in ipairs(SP.TrackableTotems) do
		if SPCompat.SpellExists(totem.spellID) then kept[#kept + 1] = totem end
	end
	SP.TrackableTotems = kept
end

-- Icon for a trackable totem. Tranquil Air (25908) has no readable icon row on
-- WoW: Forever (encrypted, like its name), so an entry may carry a static one.
function SP:TrackableTotemIcon(totem)
	local tex = GetSpellTexture and GetSpellTexture(totem.spellID)
	if not tex then tex = select(3, GetSpellInfo(totem.spellID)) end
	return tex or totem.icon
end

-- Build lookup by ID
SP.TrackableTotemsByID = {}
for _, totem in ipairs(SP.TrackableTotems) do
	SP.TrackableTotemsByID[totem.id] = totem
end

-- Short names for display
SP.TrackableTotemShortNames = {
	soe = "SoE",
	stoneskin = "Stone",
	tow = "ToW",
	flametongue = "FT",
	frostresist = "FrRes",
	manaspring = "Mana",
	healingstream = "Heal",
	fireresist = "FiRes",
	manatide = "Mana Tide",
	windfury = "WF",
	graceofair = "GoA",
	wrathofair = "WoA",
	tranquilair = "Tranq",
	natureresist = "NaRes",
	windwall = "Wind",
}

-- Initialize SPRange settings
function SP:InitSPRange()
	-- Ensure profile table exists for visual settings
	self:EnsureProfileTable("rangeTracker")

	-- Migrate old global settings to profile if they exist
	if ShamanPower_RangeTracker then
		if ShamanPower_RangeTracker.opacity and ShamanPower_RangeTracker.opacity ~= 1.0 then
			self.opt.rangeTracker.opacity = ShamanPower_RangeTracker.opacity
			ShamanPower_RangeTracker.opacity = nil
		end
		if ShamanPower_RangeTracker.iconSize and ShamanPower_RangeTracker.iconSize ~= 36 then
			self.opt.rangeTracker.iconSize = ShamanPower_RangeTracker.iconSize
			ShamanPower_RangeTracker.iconSize = nil
		end
		if ShamanPower_RangeTracker.vertical then
			self.opt.rangeTracker.vertical = ShamanPower_RangeTracker.vertical
			ShamanPower_RangeTracker.vertical = nil
		end
		if ShamanPower_RangeTracker.hideNames then
			self.opt.rangeTracker.hideNames = ShamanPower_RangeTracker.hideNames
			ShamanPower_RangeTracker.hideNames = nil
		end
		if ShamanPower_RangeTracker.hideBorder then
			self.opt.rangeTracker.hideBorder = ShamanPower_RangeTracker.hideBorder
			ShamanPower_RangeTracker.hideBorder = nil
		end
	end

	-- Runtime state stays in global SavedVariable
	if not ShamanPower_RangeTracker then
		ShamanPower_RangeTracker = {}
	end
	if not ShamanPower_RangeTracker.tracked then
		-- Default: track Windfury and Grace of Air
		ShamanPower_RangeTracker.tracked = {
			windfury = true,
			graceofair = true,
		}
	end
	if not ShamanPower_RangeTracker.position then
		ShamanPower_RangeTracker.position = { point = "CENTER", x = 0, y = 0 }
	end
	if ShamanPower_RangeTracker.shown == nil then
		ShamanPower_RangeTracker.shown = false
	end
end

-- Check if player has a specific buff (same approach as TotemTimers)
local function MainlineHasNamedBuff(unit, buffName, buffSpellIDSet)
	if issecretvalue(buffName) then return false end
	if SPCompat and SPCompat.AurasUnreadable and SPCompat.AurasUnreadable() then return false end
	if buffName then
		if not (C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName) then return false end
		local aura = C_UnitAuras.GetAuraDataBySpellName(unit, buffName, "HELPFUL")
		-- The native lookup already selected the name; do not inspect secret fields.
		return not issecretvalue(aura) and aura ~= nil
	end
	if not (buffSpellIDSet and C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return false end
	-- Tranquil Air's name is encrypted. Only public IDs from readable auras
	-- can match here; this does not bypass combat aura restrictions.
	for index = 1, 40 do
		local aura = C_UnitAuras.GetAuraDataByIndex(unit, index, "HELPFUL")
		if issecretvalue(aura) then return false end
		if not aura then break end
		local spellID = aura.spellId
		if not issecretvalue(spellID) and spellID and buffSpellIDSet[spellID] then return true end
	end
	return false
end

function SP:SPRangeHasBuff(buffName, buffSpellIDSet)
	if WOW_PROJECT_ID ~= nil and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE then
		return MainlineHasNamedBuff("player", buffName, buffSpellIDSet)
	end
	if not buffName then return false end

	for i = 1, 32 do
		local name = UnitBuff("player", i)
		if not name then break end
		if name == buffName then return true end
	end
	return false
end

-- Check if player has Windfury weapon enchant
function SP:SPRangeHasWindfuryWeapon()
	local hasMainHandEnchant, mainHandExpiration, mainHandCharges, mainHandEnchantID,
	      hasOffHandEnchant, offHandExpiration, offHandCharges, offHandEnchantID = GetWeaponEnchantInfo()

	-- Windfury weapon enchant IDs (from Windfury Totem)
	-- The enchant applied by Windfury Totem is different from the shaman's self-buff
	-- We check if either hand has any temporary enchant as an approximation
	-- More accurate: check for specific Windfury buff on weapon
	if hasMainHandEnchant or hasOffHandEnchant then
		-- Check if we also have the Windfury buff indicator
		-- Windfury Totem applies "Windfury Totem" buff in some versions
		-- or we can check for the weapon enchant directly
		return true, mainHandExpiration, offHandExpiration
	end
	return false, nil, nil
end

-- Check if player is in range of a tracked totem
function SP:SPRangeCheckTotem(totemData)
	if totemData.detection == "weapon" then
		-- Special case: Windfury - check weapon enchant
		local hasEnchant = self:SPRangeHasWindfuryWeapon()
		return hasEnchant
	else
		-- Standard buff check
		return self:SPRangeHasBuff(totemData.buffName, totemData.buffSpellIDSet)
	end
end

-- Our own totem of this kind, if it's the one down for its element: in range by
-- distance from where we dropped it (see ShamanPower:TotemDropInRange).
-- nil = not ours, or no position to measure from.
function SP:SPRangeOwnTotemInRange(totemData)
	if not self.TotemDropInRange or not self.GetElementTotemInfo then return nil end
	local have, name = self:GetElementTotemInfo(totemData.element)
	if not have or type(name) ~= "string" or not name:find(totemData.name, 1, true) then return nil end
	return self:TotemDropInRange(totemData.element)
end

-- Create the SPRange frame
function SP:CreateSPRangeFrame()
	if self.spRangeFrame then return self.spRangeFrame end

	local frame = CreateFrame("Frame", "ShamanPowerRangeFrame", UIParent, "BackdropTemplate")
	frame:SetSize(150, 40)
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:SetClampedToScreen(true)

	-- Backdrop
	SP:ApplyPanelBackdrop(frame)

	-- Title
	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	title:SetPoint("TOP", frame, "TOP", 0, -6)
	title:SetText("Totem Range")
	SP:SetSPFont(title, "labels", 11, "", STANDARD_TEXT_FONT)
	title:SetShadowOffset(1, -1)
	title:SetTextColor(0.902, 0.918, 0.941)
	frame.title = title

	-- Settings button (cog icon in top right)
	local settingsBtn = CreateFrame("Button", nil, frame)
	settingsBtn:SetSize(14, 14)
	settingsBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
	SP:StyleSettingsButton(settingsBtn)
	settingsBtn:SetScript("OnClick", function()
		SP:OpenFrameSettings("sprange", frame)
	end)
	settingsBtn:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Configure Totem Range", 1, 1, 1)
		GameTooltip:Show()
	end)
	settingsBtn:HookScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	frame.settingsBtn = settingsBtn

	-- Container for totem icons
	local iconContainer = CreateFrame("Frame", nil, frame)
	iconContainer:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -20)
	iconContainer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 8)
	frame.iconContainer = iconContainer

	-- Drag to move (ALT+drag when borderless, normal drag when bordered)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self)
		if not self:IsMovable() then return end
		-- If border is hidden, require ALT to drag
		if SP.opt.rangeTracker.hideBorder and not IsAltKeyDown() then
			return
		end
		self:StartMoving()
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		-- Save position
		local point, _, _, x, y = self:GetPoint()
		ShamanPower_RangeTracker.position = { point = point, x = x, y = y }
	end)

	-- Right-click to configure (when border is hidden)
	frame:SetScript("OnMouseUp", function(self, button)
		if button == "RightButton" and SP.opt.rangeTracker.hideBorder then
			SP:ShowSPRangeConfig()
		end
	end)

	-- Tooltip
	frame:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine("Totem Range Tracker", 1, 0.82, 0)
		GameTooltip:AddLine(" ")
		if SP.opt.rangeTracker.hideBorder then
			GameTooltip:AddLine("ALT+drag to move", 0.7, 0.7, 0.7)
			GameTooltip:AddLine("Right-click to configure", 0.7, 0.7, 0.7)
		else
			GameTooltip:AddLine("Drag to move", 0.7, 0.7, 0.7)
		end
		GameTooltip:Show()
	end)
	frame:SetScript("OnLeave", function(self)
		GameTooltip:Hide()
	end)

	frame.totemButtons = {}
	frame:Hide()

	-- Enable/disable spRange subsystem based on visibility
	frame:HookScript("OnShow", function()
		SP:SetupSPRangeUpdater()
		SP:EnableUpdateSubsystem("spRange")
	end)
	frame:HookScript("OnHide", function()
		SP:DisableUpdateSubsystem("spRange")
	end)

	self.spRangeFrame = frame
	return frame
end

-- Create a totem button for SPRange
function SP:CreateSPRangeTotemButton(parent, totemData, index)
	local iconSize = SP.opt.rangeTracker.iconSize or 36
	local btn = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	btn:SetSize(iconSize, iconSize)

	-- Background
	SP:ApplyPanelBackdrop(btn)

	-- Icon
	local icon = btn:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("TOPLEFT", 3, -3)
	icon:SetPoint("BOTTOMRIGHT", -3, 3)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	-- Get icon from spell
	icon:SetTexture(self:TrackableTotemIcon(totemData))
	btn.icon = icon

	-- Range indicator overlay (red tint)
	local rangeOverlay = btn:CreateTexture(nil, "OVERLAY")
	rangeOverlay:SetAllPoints(icon)
	rangeOverlay:SetColorTexture(0.3, 0, 0, 0.6)  -- Darker red overlay
	rangeOverlay:Hide()
	btn.rangeOverlay = rangeOverlay

	-- Status text (shows "OUT OF RANGE" or "MISSING")
	local statusText = btn:CreateFontString(nil, "OVERLAY")
	SP:SetSPFont(statusText, "labels", 7, "OUTLINE")
	statusText:SetPoint("CENTER", btn, "CENTER", 0, 0)
	statusText:SetTextColor(1, 0.2, 0.2)  -- Red text
	statusText:SetShadowColor(0, 0, 0, 1)
	statusText:SetShadowOffset(1, -1)
	statusText:Hide()
	btn.statusText = statusText

	-- Short totem name below icon
	local nameText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	SP:SetSPFont(nameText, "labels", 8, "OUTLINE")
	nameText:SetPoint("TOP", btn, "BOTTOM", 0, -1)
	nameText:SetText(self.TrackableTotemShortNames[totemData.id] or totemData.name:sub(1, 6))
	nameText:SetTextColor(0.8, 0.8, 0.8)
	if SP.opt.rangeTracker.hideNames then
		nameText:Hide()
	end
	btn.nameText = nameText

	-- In-range state
	btn.inRange = false
	btn.status = "unknown"  -- "inrange", "outofrange", "missing"

	-- Tooltip
	btn:EnableMouse(true)
	btn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(totemData.name, 1, 1, 1)
		if totemData.detection == "weapon" then
			GameTooltip:AddLine("Detected via: Weapon Enchant", 0.7, 0.7, 0.7)
		else
			GameTooltip:AddLine("Detected via: Buff", 0.7, 0.7, 0.7)
		end
		if self.status == "inrange" then
			GameTooltip:AddLine("Status: IN RANGE", 0, 1, 0)
		elseif self.status == "missing" then
			GameTooltip:AddLine("Status: MISSING (no shaman in group)", 0.7, 0.7, 0.7)
		else
			GameTooltip:AddLine("Status: OUT OF RANGE", 1, 0, 0)
		end
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", function(self)
		GameTooltip:Hide()
	end)

	btn.totemData = totemData
	return btn
end

-- Update SPRange frame with tracked totems
function SP:UpdateSPRangeFrame()
	local frame = self.spRangeFrame
	if not frame then return end

	-- Clear existing buttons
	for _, btn in pairs(frame.totemButtons) do
		btn:Hide()
	end
	frame.totemButtons = {}

	-- Get tracked totems
	local tracked = ShamanPower_RangeTracker.tracked or {}
	local trackedList = {}

	for _, totemData in ipairs(self.TrackableTotems) do
		if tracked[totemData.id] then
			table.insert(trackedList, totemData)
		end
	end

	if #trackedList == 0 then
		frame:SetSize(120, 50)
		frame.title:SetText("Totem Range (none)")
		return
	end

	-- Calculate frame size based on icon size setting
	local buttonSize = SP.opt.rangeTracker.iconSize or 36
	local padding = 6
	local numButtons = #trackedList
	local nameSpace = SP.opt.rangeTracker.hideNames and 0 or 14
	local isVertical = SP.opt.rangeTracker.vertical

	local width, height
	if isVertical then
		-- Vertical layout
		width = buttonSize + 24 + nameSpace
		height = (buttonSize * numButtons) + (padding * (numButtons - 1)) + 28  -- Title + padding
	else
		-- Horizontal layout
		local buttonsWidth = (buttonSize * numButtons) + (padding * (numButtons - 1))
		width = buttonsWidth + 24
		height = buttonSize + 26 + nameSpace
	end

	frame:SetSize(math.max(80, width), height)
	frame.title:SetText("Totem Range")

	-- Create buttons
	for i, totemData in ipairs(trackedList) do
		local btn = self:CreateSPRangeTotemButton(frame.iconContainer, totemData, i)

		if isVertical then
			-- Vertical: stack top to bottom
			local startY = -20
			btn:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, startY - (i - 1) * (buttonSize + padding))
		else
			-- Horizontal: left to right, centered
			local buttonsWidth = (buttonSize * numButtons) + (padding * (numButtons - 1))
			local startX = (frame:GetWidth() - buttonsWidth) / 2
			btn:SetPoint("TOPLEFT", frame, "TOPLEFT", startX + (i - 1) * (buttonSize + padding), -20)
		end

		btn:Show()
		frame.totemButtons[totemData.id] = btn
	end
end

-- Check if ANYONE in the group has a specific buff (indicates totem is down somewhere)
-- Optimized: party1-4 works in both party AND raid (refers to subgroup in raids)
-- Same approach as TotemTimers: exact name match with names resolved from buff spell IDs
local rangePartyUnits = { "party1", "party2", "party3", "party4" }
function SP:SPRangeAnyoneHasBuff(buffName, buffSpellIDSet)
	if WOW_PROJECT_ID ~= nil and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE then
		if MainlineHasNamedBuff("player", buffName, buffSpellIDSet) then return true end
		if IsInGroup() then
			for _, unit in ipairs(rangePartyUnits) do
				local exists = UnitExists(unit)
				if not issecretvalue(exists) and exists
					and MainlineHasNamedBuff(unit, buffName, buffSpellIDSet) then return true end
			end
		end
		return false
	end
	if not buffName then return false end

	-- Check player first
	for i = 1, 32 do
		local name = UnitBuff("player", i)
		if not name then break end
		if name == buffName then return true end
	end

	-- Check party/subgroup members (party1-4 works in both party and raid)
	if IsInGroup() then
		for i = 1, 4 do
			local unit = "party" .. i
			if UnitExists(unit) then
				for j = 1, 32 do
					local name = UnitBuff(unit, j)
					if not name then break end
					if name == buffName then return true end
				end
			end
		end
	end

	return false
end

-- Check if anyone has Windfury weapon enchant (special case)
function SP:SPRangeAnyoneHasWindfury()
	-- For Windfury, we can only reliably check our own weapon
	-- But if we have the enchant, the totem is definitely up
	local hasEnchant = self:SPRangeHasWindfuryWeapon()
	if hasEnchant then
		return true
	end

	-- We can't check other players' weapon enchants directly
	-- So we'll have to rely on seeing if melee in the group are proccing it
	-- For now, return false if we don't have it ourselves
	-- This means for Windfury specifically, we can only know if WE are in range
	return false
end

-- Update range status for all tracked totems
function SP:UpdateSPRangeStatus()
	if self.sprangeDemoActive then return end
	local frame = self.spRangeFrame
	if not frame or not frame:IsShown() then return end

	for id, btn in pairs(frame.totemButtons) do
		local totemData = btn.totemData
		local playerHasBuff = self:SPRangeCheckTotem(totemData)

		-- Check if anyone in the group has the buff (totem is down)
		local totemIsDown
		if totemData.detection == "weapon" then
			-- Windfury special case - can only check ourselves
			totemIsDown = playerHasBuff  -- If we have it, it's down. Otherwise unknown.
		else
			totemIsDown = self:SPRangeAnyoneHasBuff(totemData.buffName, totemData.buffSpellIDSet)
		end

		-- In combat on the Mainline family the buff reads above come back empty
		-- because they're blocked, which flipped every totem to MISSING. Our own
		-- totems are measured by distance instead; anything else keeps what this
		-- button showed before the reads went dark.
		if totemData.detection ~= "weapon" and SPCompat and SPCompat.AurasUnreadable and SPCompat.AurasUnreadable() then
			local near = self:SPRangeOwnTotemInRange(totemData)
			if near ~= nil then
				playerHasBuff, totemIsDown = near, true
			elseif btn.status then
				playerHasBuff = (btn.status == "inrange")
				totemIsDown = (btn.status ~= "missing")
			end
		end

		btn.inRange = playerHasBuff

		if playerHasBuff then
			-- IN RANGE - we have the buff
			btn:SetBackdropBorderColor(0, 1, 0, 1)
			btn.rangeOverlay:Hide()
			btn.icon:SetDesaturated(false)
			btn.icon:SetAlpha(1)
			btn.statusText:Hide()
			btn.nameText:SetTextColor(0, 1, 0.4)  -- Green name
			btn.status = "inrange"
		elseif totemIsDown then
			-- OUT OF RANGE - totem is down (someone has buff) but we don't
			btn:SetBackdropBorderColor(0.8, 0, 0, 1)
			btn.rangeOverlay:Show()
			btn.icon:SetDesaturated(true)
			btn.icon:SetAlpha(0.6)
			btn.statusText:SetText("OUT OF\nRANGE")
			btn.statusText:SetTextColor(1, 0.2, 0.2)  -- Red text
			btn.statusText:Show()
			btn.nameText:SetTextColor(0.8, 0.3, 0.3)  -- Red name
			btn.status = "outofrange"
		else
			-- MISSING - no one has the buff, totem not down
			btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)  -- Grey border
			btn.rangeOverlay:Hide()
			btn.icon:SetDesaturated(true)
			btn.icon:SetAlpha(0.4)
			btn.statusText:SetText("MISSING")
			btn.statusText:SetTextColor(0.7, 0.7, 0.7)  -- Grey text
			btn.statusText:Show()
			btn.nameText:SetTextColor(0.5, 0.5, 0.5)  -- Grey name
			btn.status = "missing"
		end
	end
end

-- Show SPRange configuration
-- The window lives in ShamanPower_Config (SPRange.lua), which replaces this.
function SP:ShowSPRangeConfig()
	print("|cff0070ddShamanPower|r: the ShamanPower_Config module is required for the Totem Range window")
end

-- Update SPRange frame border visibility
function SP:UpdateSPRangeBorder()
	if not self.spRangeFrame then return end

	local hideBorder = SP.opt.rangeTracker.hideBorder

	if hideBorder then
		-- Hide border and background
		self.spRangeFrame:SetBackdrop(nil)
		if self.spRangeFrame.title then
			self.spRangeFrame.title:Hide()
		end
		self:SetSettingsButtonHoverOnly(self.spRangeFrame, self.spRangeFrame.settingsBtn, true)
	else
		-- Show border and background
		SP:ApplyPanelBackdrop(self.spRangeFrame)
		if self.spRangeFrame.title then
			self.spRangeFrame.title:Show()
		end
		self:SetSettingsButtonHoverOnly(self.spRangeFrame, self.spRangeFrame.settingsBtn, false)
	end
end

-- Update SPRange frame opacity
function SP:UpdateSPRangeOpacity()
	if not self.spRangeFrame then return end
	local opacity = SP.opt.rangeTracker.opacity or 1.0
	self.spRangeFrame:SetAlpha(opacity)
end

-- Update config button visual states
function SP:UpdateSPRangeConfigButtons()
	if not self.spRangeConfigFrame or not self.spRangeConfigFrame.totemButtons then return end

	for id, btn in pairs(self.spRangeConfigFrame.totemButtons) do
		local isTracked = ShamanPower_RangeTracker.tracked[id]
		local c = btn.elementColors

		if isTracked then
			-- Tracked - full color
			btn.icon:SetDesaturated(false)
			btn.icon:SetAlpha(1)
			btn.nameText:SetTextColor(1, 1, 1)
		else
			-- Not tracked - grey
			btn.icon:SetDesaturated(true)
			btn.icon:SetAlpha(0.4)
			btn.nameText:SetTextColor(0.5, 0.5, 0.5)
		end
	end
end

-- Toggle SPRange visibility
function SP:ToggleSPRange()
	self:InitSPRange()

	if not self.spRangeFrame then
		self:CreateSPRangeFrame()
	end

	if self.spRangeFrame:IsShown() then
		self.spRangeFrame:Hide()
		self.spRangeManuallyOpened = false  -- User closed it manually
		ShamanPower_RangeTracker.shown = false
		self:Print("SPRange hidden. Use /sprange to show.")
	else
		-- Restore position
		local pos = ShamanPower_RangeTracker.position
		if pos then
			self.spRangeFrame:ClearAllPoints()
			self.spRangeFrame:SetPoint(pos.point, UIParent, pos.point, pos.x, pos.y)
		end

		self:UpdateSPRangeFrame()
		self:UpdateSPRangeBorder()
		self:UpdateSPRangeOpacity()
		self.spRangeFrame:Show()
		self.spRangeManuallyOpened = true  -- User opened it manually
		ShamanPower_RangeTracker.shown = true
		self:Print("SPRange shown. Click settings cog to configure.")
	end
end

-- The shamans in your own subgroup, by the name a whisper needs (with the realm
-- for other realms): an instance raid's report goes to them (see below). Read
-- again at every send, so a name still "Unknown" at roster time is picked up.
-- Anniversary only: on WoW: Forever the realm label changes and names can have
-- two parts, so a whisper might not find its target (and the failed whisper's
-- system message would repeat every heartbeat); there the report stays on
-- INSTANCE_CHAT.
local WF_WHISPER = not (WOW_PROJECT_ID ~= nil and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE)
local wfWhisperTargets = {}
local function refreshWhisperTargets()
	wipe(wfWhisperTargets)
	for i = 1, 4 do
		local unit = "party" .. i
		if UnitExists(unit) and select(2, UnitClass(unit)) == "SHAMAN" then
			local name = GetUnitName(unit, true)
			if type(name) == "string" and not (issecretvalue and issecretvalue(name)) and name ~= "" and name ~= UNKNOWNOBJECT then
				wfWhisperTargets[#wfWhisperTargets + 1] = name
			end
		end
	end
end

-- Losing Windfury (walking out of the totem's range) is its weapon enchant
-- running out. Whether or not the client fires an event for that, a one-shot
-- timer checks the moment it should have run out. One timer at a time: while
-- the totem keeps renewing the enchant, it waits again for the new end. An
-- enchant that ends sooner than the timer's wake (a long oil replaced by the
-- totem's short enchant) cancels it and wakes at the new end instead.
local wfExpireAt, wfExpireTimer, wfWakeAt = 0, nil, 0
local function wfExpireCheck()
	local wait = wfExpireAt - GetTime()
	if wait > 0.05 then
		wfWakeAt = wfExpireAt
		wfExpireTimer = C_Timer.NewTimer(wait, wfExpireCheck)
		return
	end
	wfExpireTimer = nil
	if not SP:IsUpdateSubsystemEnabled("wfBroadcast") then return end
	SP:SPRangeHasWindfuryWeapon()   -- on Forever this first read drops SPCompat's cache of an enchant that ran out
	SP:BroadcastWindfuryStatus()
end
local function wfWatchExpiry(mainExp, offExp)
	-- milliseconds left on each hand; the report says "0" only once both are gone
	local ms = 0
	if type(mainExp) == "number" and not (issecretvalue and issecretvalue(mainExp)) then ms = mainExp end
	if type(offExp) == "number" and not (issecretvalue and issecretvalue(offExp)) and offExp > ms then ms = offExp end
	if ms <= 0 then return end
	wfExpireAt = GetTime() + ms / 1000 + 0.2
	-- an earlier end rearms the wake (a re-read of the same enchant can differ by a few ms)
	if wfExpireTimer and wfExpireAt < wfWakeAt - 0.1 then
		wfExpireTimer:Cancel()
		wfExpireTimer = nil
	end
	if not wfExpireTimer then
		wfWakeAt = wfExpireAt
		wfExpireTimer = C_Timer.NewTimer(ms / 1000 + 0.2, wfExpireCheck)
	end
end

-- Broadcast Windfury Totem status to group (same detection as SPRange)
-- NOTE: This sends directly via ChatThrottleLib to bypass the lastMsg check in SendMessage
-- which would block repeated "WFBUFF 1" messages. We need periodic broadcasts so the shaman
-- knows party members are still in range.
-- Sent the moment it changes (weapon enchant events), and as a heartbeat every
-- 6 s (receivers drop a report after 10 s): heartbeat = send even if unchanged.
function SP:BroadcastWindfuryStatus(heartbeat)
	if self.sprangeDemoActive or self:IsOff() then return end   -- off: a check queued before the switch sends nothing
	if not IsInGroup() then return end
	-- Chat lockdown: nothing goes out and nothing is recorded as sent; the report
	-- is owed and goes out as soon as the lock lifts (see wfEvents below).
	if SPK and SPK() == true then self.wfReportOwed = true return false end

	-- Use SAME detection as SPRange - check weapon enchant from GetWeaponEnchantInfo()
	local hasWindfury, mainExp, offExp = self:SPRangeHasWindfuryWeapon()
	if hasWindfury then wfWatchExpiry(mainExp, offExp) end
	local status = hasWindfury and "1" or "0"
	if not heartbeat and self.lastWFStatus == status then return end

	-- Totems only reach your own party, so the report only goes there: the
	-- PARTY channel inside a raid is your own subgroup (4 players, not 39).
	-- An instance-only group has no home party. A 5-player one (LFG dungeon) uses
	-- INSTANCE_CHAT, which is those 5; in an instance raid (a battleground, LFR)
	-- INSTANCE_CHAT reaches everyone there, so on Anniversary the report is
	-- whispered to the shamans in your own subgroup instead.
	local channel = "PARTY"
	if not IsInGroup(LE_PARTY_CATEGORY_HOME) and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
		channel = "INSTANCE_CHAT"
		if WF_WHISPER and IsInRaid() then
			refreshWhisperTargets()
			-- no name known yet: nothing goes out and nothing is recorded as sent,
			-- so the next change or heartbeat tries again
			if #wfWhisperTargets == 0 then return end
			channel = "WHISPER"
		end
	end
	self.lastWFStatus = status
	self.lastWFBroadcast = GetTime()
	self.wfReportOwed = nil

	-- Send directly via ChatThrottleLib (bypass lastMsg check in SendMessage)
	if channel == "WHISPER" then
		for _, name in ipairs(wfWhisperTargets) do
			ChatThrottleLib:SendAddonMessage("NORMAL", self.commPrefix, "WFBUFF " .. status, "WHISPER", name)
		end
	else
		ChatThrottleLib:SendAddonMessage("NORMAL", self.commPrefix, "WFBUFF " .. status, channel)
	end
end

-- Get Windfury range data for a specific player
function SP:GetWindfuryRangeStatus(playerName)
	if not self.WindfuryRangeData then return nil end
	local data = self.WindfuryRangeData[playerName]
	if not data then return nil end

	-- Data expires after 10 seconds
	if (GetTime() - data.timestamp) > 10 then
		self.WindfuryRangeData[playerName] = nil
		return nil
	end

	return data.hasWindfury
end

-- Check if a player is in range of Windfury totem (using reported data)
function SP:IsPlayerInWindfuryRange(playerName)
	-- Check self first
	if playerName == self.player then
		return self:SPRangeHasWindfuryWeapon()
	end

	-- Check reported data from other players
	return self:GetWindfuryRangeStatus(playerName)
end

-- Setup SPRange update timer
function SP:SetupSPRangeUpdater()
	if self.spRangeUpdaterSetup then return end
	self.spRangeUpdaterSetup = true
	self.spRangeBroadcastCounter = 0  -- Track broadcasts (every 2 updates = 2 seconds)

	-- Register SPRange updates with consolidated update system (1fps)
	if not self.updateSystem.subsystems["spRange"] then
		self:RegisterUpdateSubsystem("spRange", 1.0, function()
			-- Only run if SPRange frame is actually visible
			if not SP.spRangeFrame or not SP.spRangeFrame:IsShown() then
				return
			end
			SP:UpdateSPRangeStatus()
			-- (the Windfury report has its own timer: UpdateWindfuryBroadcaster)
		end)
	end
	-- Only enable if SPRange frame exists and is shown
	if self.spRangeFrame and self.spRangeFrame:IsShown() then
		self:EnableUpdateSubsystem("spRange")
	end
end

-- Check if there's a shaman anywhere in the group (not just subgroup)
function SP:SPRangeHasAnyShamanInGroup()
	-- If player is a shaman, don't auto-show SPRange (they have the full UI)
	local _, playerClass = UnitClass("player")
	if playerClass == "SHAMAN" then
		return false
	end

	if IsInRaid() then
		for i = 1, 40 do
			local name, _, _, _, _, class = GetRaidRosterInfo(i)
			if name and class == "SHAMAN" then
				return true
			end
		end
	elseif IsInGroup() then
		for i = 1, 4 do
			if UnitExists("party" .. i) then
				local _, class = UnitClass("party" .. i)
				if class == "SHAMAN" then
					return true
				end
			end
		end
	end

	return false
end

-- The Windfury report runs on its own timer whenever a shaman is in the group,
-- whether or not the overlay is on screen (so closing the overlay, or
-- Windfury-only mode, never stops the shaman seeing your Windfury).
-- Switching ShamanPower off does stop it: then nothing is sent.
-- A shaman in YOUR party (party1-4 are your own subgroup inside a raid): the only
-- shamans whose totems can reach you, so the only ones the report is for.
function SP:ShamanInMyParty()
	if select(2, UnitClass("player")) == "SHAMAN" then return false end
	for i = 1, 4 do
		local unit = "party" .. i
		if UnitExists(unit) and select(2, UnitClass(unit)) == "SHAMAN" then return true end
	end
	return false
end

-- Changes are sent when the weapon enchants change, not found by polling: these
-- events are heard only while a shaman is in your party. A burst is checked once,
-- a moment later (after SPCompat's own handler has dropped its enchant cache).
-- The enchant running out is also caught by its own timer (wfWatchExpiry).
local wfCheckQueued, wfCheckForce = false, false
local function wfCheck()
	local force = wfCheckForce
	wfCheckQueued, wfCheckForce = false, false
	SP:BroadcastWindfuryStatus(force)
end
local wfEvents = CreateFrame("Frame")
if SPCompat and SPCompat.StressRegister then SPCompat.StressRegister(wfEvents, "Totem Range (Windfury report)") end
wfEvents:SetScript("OnEvent", function(_, event, _, state)
	local lifted = event == "ADDON_RESTRICTION_STATE_CHANGED"
	if lifted then
		-- a restriction lifting (state 0; chat lockdown is one): send what the lock
		-- held back, heartbeat included (receivers may have dropped the report)
		if state ~= 0 or not SP.wfReportOwed then return end
		wfCheckForce = true
	end
	if wfCheckQueued then return end
	wfCheckQueued = true
	C_Timer.After(lifted and 1 or 0.1, wfCheck)
end)
local function setWFEvents(on)
	if not on then wfEvents:UnregisterAllEvents() return end
	if wfEvents.RegisterUnitEvent then
		wfEvents:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
	else
		wfEvents:RegisterEvent("UNIT_INVENTORY_CHANGED")
	end
	pcall(wfEvents.RegisterEvent, wfEvents, "WEAPON_ENCHANT_CHANGED")
	pcall(wfEvents.RegisterEvent, wfEvents, "ADDON_RESTRICTION_STATE_CHANGED")
end

function SP:UpdateWindfuryBroadcaster()
	if not self.updateSystem then return end
	if not self.updateSystem.subsystems["wfBroadcast"] then
		-- the heartbeat only: changes go out from the events above
		self:RegisterUpdateSubsystem("wfBroadcast", 6.0, function() SP:BroadcastWindfuryStatus(true) end)
	end
	if not self:IsOff() and self:ShamanInMyParty() then
		if not self:IsUpdateSubsystemEnabled("wfBroadcast") then
			self:EnableUpdateSubsystem("wfBroadcast")
			setWFEvents(true)
			self:BroadcastWindfuryStatus(true)   -- the shaman sees you at once, not after the first heartbeat
		end
	else
		self:DisableUpdateSubsystem("wfBroadcast")
		setWFEvents(false)
	end
end
do
	local f = CreateFrame("Frame")
	if SPCompat and SPCompat.StressRegister then SPCompat.StressRegister(f, "Totem Range (Windfury report)") end
	f:RegisterEvent("GROUP_ROSTER_UPDATE")
	f:RegisterEvent("PLAYER_ENTERING_WORLD")
	f:SetScript("OnEvent", function() SP:UpdateWindfuryBroadcaster() end)
end

-- Auto-show/hide SPRange based on group composition
function SP:UpdateSPRangeVisibility()
	if not self.spRangeFrame then return end

	-- Windfury-only mode: no overlay at all (the report keeps running)
	if self.WindfuryOnly and self:WindfuryOnly() then
		if self.spRangeFrame:IsShown() then self.spRangeFrame:Hide() end
		return
	end

	-- Don't auto-hide if user manually opened it (shamans may want to track their own totems)
	if self.spRangeManuallyOpened then
		return
	end

	-- ShamanPower switched off: no auto-show (an overlay opened by hand is the player's call)
	local shouldShow = not self:IsOff() and self:SPRangeHasAnyShamanInGroup()

	if shouldShow then
		if not self.spRangeFrame:IsShown() then
			-- Restore position
			local pos = ShamanPower_RangeTracker.position
			if pos then
				self.spRangeFrame:ClearAllPoints()
				self.spRangeFrame:SetPoint(pos.point, UIParent, pos.point, pos.x, pos.y)
			end
			self:UpdateSPRangeFrame()
			self:UpdateSPRangeBorder()
			self:UpdateSPRangeOpacity()
			self.spRangeFrame:Show()
		end
	else
		if self.spRangeFrame:IsShown() then
			self.spRangeFrame:Hide()
		end
	end
end

-- Initialize SPRange on addon load (for non-shamans primarily, but works for all)
function SP:InitializeSPRange()
	self:InitSPRange()
	self:CreateSPRangeFrame()
	self:SetupSPRangeUpdater()

	-- Check if we should auto-show (in group with a shaman)
	self:UpdateSPRangeVisibility()
end

-- Register /sprange slash command
SLASH_SPRANGE1 = "/sprange"
SlashCmdList["SPRANGE"] = function(msg)
	msg = msg:lower():trim()

	if msg == "toggle" then
		-- Toggle the overlay visibility
		SP:ToggleSPRange()
	elseif msg == "show" or msg == "hide" then
		-- only flip it when it is not already that way (show never hides, hide never shows)
		local shown = SP.spRangeFrame and SP.spRangeFrame:IsShown() and true or false
		if (msg == "show") ~= shown then
			SP:ToggleSPRange()
		else
			SP:Print(shown and "SPRange is already shown." or "SPRange is already hidden.")
		end
	else
		-- Default: show the config menu
		SP:InitSPRange()
		if not SP.spRangeFrame then
			SP:CreateSPRangeFrame()
		end
		SP:ShowSPRangeConfig()
	end
end

-- ============================================================================
-- Setup Wizard preview: fill the range overlay with sample totems (no group)
-- ============================================================================
function SP:SPRangeDemo(on)
	if on then
		local frame = self.spRangeFrame or self:CreateSPRangeFrame()
		if not frame then return end
		if not self.opt or not self.opt.rangeTracker then return end
		if frame.settingsBtn then frame.settingsBtn:Hide() end
		self:InitSPRange()

		-- Style one button from a fake status (same visuals as UpdateSPRangeStatus).
		local function style(btn, status)
			if status == "inrange" then
				btn:SetBackdropBorderColor(0, 1, 0, 1); btn.rangeOverlay:Hide()
				btn.icon:SetDesaturated(false); btn.icon:SetAlpha(1); btn.statusText:Hide()
				btn.nameText:SetTextColor(0, 1, 0.4)
			elseif status == "outofrange" then
				btn:SetBackdropBorderColor(0.8, 0, 0, 1); btn.rangeOverlay:Show()
				btn.icon:SetDesaturated(true); btn.icon:SetAlpha(0.6)
				btn.statusText:SetText("OUT OF\nRANGE"); btn.statusText:SetTextColor(1, 0.2, 0.2); btn.statusText:Show()
				btn.nameText:SetTextColor(0.8, 0.3, 0.3)
			else
				btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1); btn.rangeOverlay:Hide()
				btn.icon:SetDesaturated(true); btn.icon:SetAlpha(0.4)
				btn.statusText:SetText("MISSING"); btn.statusText:SetTextColor(0.7, 0.7, 0.7); btn.statusText:Show()
				btn.nameText:SetTextColor(0.5, 0.5, 0.5)
			end
			btn.status = status; btn.inRange = (status == "inrange")
		end

		-- (Re)build the frame from the user's tracked set. Called on every
		-- option change, so keep the per-totem sim state across rebuilds.
		local d = self.sprangeDemo or { states = {}, tick = 0 }
		self.sprangeDemo = d
		local function build()
			for _, btn in pairs(frame.totemButtons) do btn:Hide() end
			frame.totemButtons = {}
			local list = {}
			local tracked = ShamanPower_RangeTracker and ShamanPower_RangeTracker.tracked or {}
			for _, t in ipairs(self.TrackableTotems) do
				if tracked[t.id] then list[#list + 1] = t end
			end
			d.list = list
			local buttonSize = SP.opt.rangeTracker.iconSize or 36
			local padding, n = 6, #list
			local nameSpace = SP.opt.rangeTracker.hideNames and 0 or 14
			local isVertical = SP.opt.rangeTracker.vertical
			local width, height
			if n == 0 then
				width, height = 150, 50
			elseif isVertical then
				width = buttonSize + 24 + nameSpace
				height = (buttonSize * n) + (padding * (n - 1)) + 28
			else
				width = (buttonSize * n) + (padding * (n - 1)) + 24
				height = buttonSize + 26 + nameSpace
			end
			frame:SetSize(math.max(80, width), height)
			if frame.title then frame.title:SetText(n == 0 and "Totem Range (pick totems)" or "Totem Range") end
			for i, t in ipairs(list) do
				local btn = self:CreateSPRangeTotemButton(frame.iconContainer, t, i)
				if isVertical then
					btn:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -20 - (i - 1) * (buttonSize + padding))
				else
					local bw = (buttonSize * n) + (padding * (n - 1))
					btn:SetPoint("TOPLEFT", frame, "TOPLEFT", (frame:GetWidth() - bw) / 2 + (i - 1) * (buttonSize + padding), -20)
				end
				d.states[t.id] = d.states[t.id] or ((i % 3 == 0) and "outofrange" or "inrange")
				style(btn, d.states[t.id])
				btn:Show()
				frame.totemButtons[t.id] = btn
			end
			self:UpdateSPRangeBorder()
			self:UpdateSPRangeOpacity()
			frame:Show()
		end
		d.build = build
		build()

		if not self.sprangeDemoActive then
			self.sprangeDemoActive = true
			-- Sim: every couple of seconds one totem changes state, as if you
			-- walked around (or its shaman stopped dropping it).
			if self.sprangeDemoTicker then self.sprangeDemoTicker:Cancel() end
			self.sprangeDemoTicker = C_Timer.NewTicker(2.2, function()
				if not self.sprangeDemoActive or not d.list or #d.list == 0 then return end
				d.tick = d.tick + 1
				local t = d.list[(d.tick % #d.list) + 1]
				local cur = d.states[t.id] or "inrange"
				local nxt = (cur == "inrange") and "outofrange" or (cur == "outofrange" and (d.tick % 5 == 0) and "missing") or "inrange"
				d.states[t.id] = nxt
				local btn = frame.totemButtons[t.id]
				if btn then style(btn, nxt) end
				local short = self.TrackableTotemShortNames[t.id] or t.name
				self.sprangeDemoStatus =
					(nxt == "outofrange" and ("You walked out of range of the shaman's " .. t.name))
					or (nxt == "missing" and ("Nobody has " .. t.name .. " down right now"))
					or ("Back in range of " .. t.name)
			end)
		end
	else
		self.sprangeDemoActive = false
		if self.sprangeDemoTicker then self.sprangeDemoTicker:Cancel(); self.sprangeDemoTicker = nil end
		self.sprangeDemo = nil
		self.sprangeDemoStatus = nil
		if self.spRangeFrame and self.spRangeFrame.settingsBtn then self.spRangeFrame.settingsBtn:Show() end
		-- Clear sample data and let real data take over
		self:UpdateSPRangeFrame()
		self:UpdateSPRangeStatus()
		self:UpdateSPRangeVisibility()
	end
end

-- Register the range overlay with the setup wizard preview harness
if ShamanPower.RegisterPreview then
	ShamanPower:RegisterPreview("sprange", { frame = "ShamanPowerRangeFrame", demo = "SP:SPRangeDemo", pad = 24 })
end

-- Enable ShamanPower switched: off hides the overlay (one opened by hand too) and
-- stops the Windfury report; on brings both back as the group and settings say.
SP:OnOnOff(function(off)
	local frame = SP.spRangeFrame
	if frame then
		if off then
			frame:Hide()
		elseif SP.spRangeManuallyOpened then
			frame:Show()   -- opened by hand before the switch
		end
		SP:UpdateSPRangeVisibility()
	end
	SP:UpdateWindfuryBroadcaster()
end)
