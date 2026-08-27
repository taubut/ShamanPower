-- ============================================================================
-- ShamanPower [SPRange] Module
-- Totem Range Tracker - Shows which totems are affecting you
-- ============================================================================

local SP = ShamanPower
if not SP then
	print("|cffff0000ShamanPower [SPRange]:|r Core addon not found!")
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
		totem.buffName = GetSpellInfo(totem.buffSpellID)
	end
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
function SP:SPRangeHasBuff(buffName)
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
		return self:SPRangeHasBuff(totemData.buffName)
	end
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
	title:SetFont(STANDARD_TEXT_FONT, 11, "")
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
	settingsBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Configure Totem Range", 1, 1, 1)
		GameTooltip:Show()
	end)
	settingsBtn:SetScript("OnLeave", function()
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
	local _, _, spellIcon = GetSpellInfo(totemData.spellID)
	icon:SetTexture(spellIcon)
	btn.icon = icon

	-- Range indicator overlay (red tint)
	local rangeOverlay = btn:CreateTexture(nil, "OVERLAY")
	rangeOverlay:SetAllPoints(icon)
	rangeOverlay:SetColorTexture(0.3, 0, 0, 0.6)  -- Darker red overlay
	rangeOverlay:Hide()
	btn.rangeOverlay = rangeOverlay

	-- Status text (shows "OUT OF RANGE" or "MISSING")
	local statusText = btn:CreateFontString(nil, "OVERLAY")
	statusText:SetFont("Fonts\\FRIZQT__.TTF", 7, "OUTLINE")
	statusText:SetPoint("CENTER", btn, "CENTER", 0, 0)
	statusText:SetTextColor(1, 0.2, 0.2)  -- Red text
	statusText:SetShadowColor(0, 0, 0, 1)
	statusText:SetShadowOffset(1, -1)
	statusText:Hide()
	btn.statusText = statusText

	-- Short totem name below icon
	local nameText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	nameText:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
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
function SP:SPRangeAnyoneHasBuff(buffName)
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
			totemIsDown = self:SPRangeAnyoneHasBuff(totemData.buffName)
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

-- Broadcast Windfury Totem status to group (same detection as SPRange)
-- NOTE: This sends directly via ChatThrottleLib to bypass the lastMsg check in SendMessage
-- which would block repeated "WFBUFF 1" messages. We need periodic broadcasts so the shaman
-- knows party members are still in range.
function SP:BroadcastWindfuryStatus()
	if not IsInGroup() then return end

	-- Use SAME detection as SPRange - check weapon enchant from GetWeaponEnchantInfo()
	local hasWindfury = self:SPRangeHasWindfuryWeapon()
	local status = hasWindfury and "1" or "0"

	-- Send every 2 seconds or when status changes
	if self.lastWFStatus ~= status or not self.lastWFBroadcast or (GetTime() - self.lastWFBroadcast) > 2 then
		self.lastWFStatus = status
		self.lastWFBroadcast = GetTime()

		-- Determine channel
		local channel
		if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and IsInInstance() then
			channel = "INSTANCE_CHAT"
		elseif IsInRaid() then
			channel = "RAID"
		else
			channel = "PARTY"
		end

		-- Send directly via ChatThrottleLib (bypass lastMsg check in SendMessage)
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

			-- Broadcast Windfury status every 2 seconds (every 2nd update)
			SP.spRangeBroadcastCounter = (SP.spRangeBroadcastCounter or 0) + 1
			if SP.spRangeBroadcastCounter >= 2 then
				SP.spRangeBroadcastCounter = 0
				SP:BroadcastWindfuryStatus()
			end
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

-- Auto-show/hide SPRange based on group composition
function SP:UpdateSPRangeVisibility()
	if not self.spRangeFrame then return end

	-- Don't auto-hide if user manually opened it (shamans may want to track their own totems)
	if self.spRangeManuallyOpened then
		return
	end

	local shouldShow = self:SPRangeHasAnyShamanInGroup()

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

	if msg == "toggle" or msg == "show" or msg == "hide" then
		-- Toggle the overlay visibility
		SP:ToggleSPRange()
	else
		-- Default: show the config menu
		SP:InitSPRange()
		if not SP.spRangeFrame then
			SP:CreateSPRangeFrame()
		end
		SP:ShowSPRangeConfig()
	end
end
