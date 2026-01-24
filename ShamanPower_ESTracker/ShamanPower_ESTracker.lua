-- ============================================================================
-- ShamanPower ES Tracker Module
-- Track Earth Shields cast by OTHER shamans in your raid/party
-- ============================================================================

local SP = ShamanPower
if not SP then return end

-- Mark module as loaded
SP.ESTrackerLoaded = true

-- ============================================================================
-- Raid Earth Shield Tracker: Shows all Earth Shields in raid/party
-- ============================================================================

SP.earthShields = {}  -- { [targetGUID] = { target, caster, charges, expiration } }

-- Earth Shield spell ID (for icon)
SP.EarthShieldSpellID = 32594  -- Rank 1, we just need the icon

-- Initialize Earth Shield tracker settings
function SP:InitESTracker()
	-- Ensure profile table exists
	self:EnsureProfileTable("esTracker")

	-- Migrate from old global variable if it exists
	if ShamanPower_ESTracker and next(ShamanPower_ESTracker) then
		-- Copy old settings to profile if profile is empty/default
		if SP.opt.esTracker.enabled == false and SP.opt.esTracker.enabled then
			SP.opt.esTracker.enabled = SP.opt.esTracker.enabled
		end
		if SP.opt.esTracker.position then
			self.opt.esTracker.position = SP.opt.esTracker.position
		end
		if SP.opt.esTracker.opacity and SP.opt.esTracker.opacity ~= 1.0 then
			self.opt.esTracker.opacity = SP.opt.esTracker.opacity
		end
		if SP.opt.esTracker.iconSize and SP.opt.esTracker.iconSize ~= 40 then
			self.opt.esTracker.iconSize = SP.opt.esTracker.iconSize
		end
		if SP.opt.esTracker.vertical then
			self.opt.esTracker.vertical = SP.opt.esTracker.vertical
		end
		if SP.opt.esTracker.hideNames then
			self.opt.esTracker.hideNames = SP.opt.esTracker.hideNames
		end
		if SP.opt.esTracker.hideBorder then
			self.opt.esTracker.hideBorder = SP.opt.esTracker.hideBorder
		end
		if SP.opt.esTracker.hideCharges then
			self.opt.esTracker.hideCharges = SP.opt.esTracker.hideCharges
		end
		-- Clear the old global after migration
		ShamanPower_ESTracker = nil
	end
end

-- Create the Earth Shield tracker frame
function SP:CreateESTrackerFrame()
	if self.esTrackerFrame then return self.esTrackerFrame end

	local frame = CreateFrame("Frame", "ShamanPowerESTrackerFrame", UIParent, "BackdropTemplate")
	frame:SetSize(150, 60)
	frame:SetPoint("CENTER", UIParent, "CENTER", 200, 0)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:SetClampedToScreen(true)
	frame:SetFrameStrata("MEDIUM")

	-- Backdrop
	frame:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 }
	})
	frame:SetBackdropColor(0, 0, 0, 0.8)
	frame:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)

	-- Title
	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	title:SetPoint("TOP", frame, "TOP", 0, -6)
	title:SetText("Earth Shields")
	title:SetTextColor(0.4, 0.8, 0.4)  -- Green tint for Earth
	frame.title = title

	-- Container for ES icons
	local iconContainer = CreateFrame("Frame", nil, frame)
	iconContainer:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -20)
	iconContainer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 8)
	frame.iconContainer = iconContainer

	-- Drag to move (ALT+drag when borderless, normal drag when bordered)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self)
		if not self:IsMovable() then return end
		if SP.opt.esTracker.hideBorder and not IsAltKeyDown() then
			return
		end
		self:StartMoving()
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, _, x, y = self:GetPoint()
		SP.opt.esTracker.position = { point = point, x = x, y = y }
	end)

	-- Tooltip
	frame:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine("Earth Shield Tracker", 0.4, 0.8, 0.4)
		GameTooltip:AddLine(" ")
		if SP.opt.esTracker.hideBorder then
			GameTooltip:AddLine("ALT+drag to move", 0.7, 0.7, 0.7)
		else
			GameTooltip:AddLine("Drag to move", 0.7, 0.7, 0.7)
		end
		GameTooltip:Show()
	end)
	frame:SetScript("OnLeave", function(self)
		GameTooltip:Hide()
	end)

	frame.esButtons = {}
	frame:Hide()

	-- Enable/disable ES tracker events based on visibility
	frame:HookScript("OnShow", function()
		SP:EnableESTrackerEvents()
	end)
	frame:HookScript("OnHide", function()
		SP:DisableESTrackerEvents()
	end)

	self.esTrackerFrame = frame
	return frame
end

-- Get class color for a unit
function SP:GetClassColorForUnit(unit)
	if not unit or not UnitExists(unit) then
		return 1, 1, 1
	end
	local _, class = UnitClass(unit)
	if class and RAID_CLASS_COLORS[class] then
		local color = RAID_CLASS_COLORS[class]
		return color.r, color.g, color.b
	end
	return 1, 1, 1
end

-- Get class color by class name
function SP:GetClassColor(class)
	if class and RAID_CLASS_COLORS[class] then
		local color = RAID_CLASS_COLORS[class]
		return color.r, color.g, color.b
	end
	return 1, 1, 1
end

-- Create an Earth Shield button for the tracker
function SP:CreateESTrackerButton(parent, esData, index)
	local iconSize = SP.opt.esTracker.iconSize or 40
	local btn = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	btn:SetSize(iconSize, iconSize)

	-- Background
	btn:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Buttons\\WHITE8X8",
		tile = true, tileSize = 16, edgeSize = 2,
		insets = { left = 2, right = 2, top = 2, bottom = 2 }
	})
	btn:SetBackdropColor(0, 0, 0, 0.7)
	btn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

	-- Icon (Earth Shield icon)
	local icon = btn:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("TOPLEFT", 3, -3)
	icon:SetPoint("BOTTOMRIGHT", -3, 3)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local _, _, spellIcon = GetSpellInfo(self.EarthShieldSpellID)
	icon:SetTexture(spellIcon or "Interface\\Icons\\Spell_Nature_SkinofEarth")
	btn.icon = icon

	-- Target name (inside the icon area, at bottom)
	local targetText = btn:CreateFontString(nil, "OVERLAY")
	targetText:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
	targetText:SetPoint("BOTTOM", btn, "BOTTOM", 0, 5)
	targetText:SetText(esData.targetName or "?")
	targetText:SetTextColor(1, 1, 1)
	btn.targetText = targetText

	-- Charges (top right corner)
	local chargesText = btn:CreateFontString(nil, "OVERLAY")
	chargesText:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
	chargesText:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -2, -2)
	chargesText:SetText(esData.charges or "?")
	chargesText:SetTextColor(0.4, 1, 0.4)
	if SP.opt.esTracker.hideCharges then
		chargesText:Hide()
	end
	btn.chargesText = chargesText

	-- Caster name (below the icon)
	local casterText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	casterText:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
	casterText:SetPoint("TOP", btn, "BOTTOM", 0, -1)
	casterText:SetText(esData.casterName or "?")
	-- Color by caster's class
	local r, g, b = self:GetClassColor(esData.casterClass)
	casterText:SetTextColor(r, g, b)
	if SP.opt.esTracker.hideNames then
		casterText:Hide()
	end
	btn.casterText = casterText

	-- Tooltip
	btn:EnableMouse(true)
	btn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Earth Shield", 0.4, 0.8, 0.4)
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Target: " .. (esData.targetName or "Unknown"), 1, 1, 1)
		GameTooltip:AddLine("Caster: " .. (esData.casterName or "Unknown"), 1, 0.82, 0)
		GameTooltip:AddLine("Charges: " .. (esData.charges or "?"), 0.4, 1, 0.4)
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", function(self)
		GameTooltip:Hide()
	end)

	btn.esData = esData
	return btn
end

-- Update the Earth Shield tracker display
function SP:UpdateESTrackerFrame()
	local frame = self.esTrackerFrame
	if not frame then return end

	-- Clear existing buttons
	for _, btn in pairs(frame.esButtons) do
		btn:Hide()
	end
	frame.esButtons = {}

	-- Get all tracked Earth Shields
	local esList = {}
	for guid, esData in pairs(self.earthShields) do
		table.insert(esList, esData)
	end

	-- Sort by caster name for consistency
	table.sort(esList, function(a, b)
		return (a.casterName or "") < (b.casterName or "")
	end)

	if #esList == 0 then
		frame:SetSize(120, 50)
		frame.title:SetText("Earth Shields (none)")
		return
	end

	-- Calculate frame size
	local buttonSize = SP.opt.esTracker.iconSize or 40
	local padding = 6
	local numButtons = #esList
	local nameSpace = SP.opt.esTracker.hideNames and 0 or 14
	local isVertical = SP.opt.esTracker.vertical

	local width, height
	if isVertical then
		width = buttonSize + 24 + nameSpace
		height = (buttonSize * numButtons) + (padding * (numButtons - 1)) + 28 + nameSpace
	else
		local buttonsWidth = (buttonSize * numButtons) + (padding * (numButtons - 1))
		width = buttonsWidth + 24
		height = buttonSize + 26 + nameSpace
	end

	frame:SetSize(math.max(100, width), height)
	frame.title:SetText("Earth Shields")

	-- Create buttons
	for i, esData in ipairs(esList) do
		local btn = self:CreateESTrackerButton(frame.iconContainer, esData, i)

		if isVertical then
			local startY = -20
			btn:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, startY - (i - 1) * (buttonSize + padding + nameSpace))
		else
			local buttonsWidth = (buttonSize * numButtons) + (padding * (numButtons - 1))
			local startX = (frame:GetWidth() - buttonsWidth) / 2
			btn:SetPoint("TOPLEFT", frame, "TOPLEFT", startX + (i - 1) * (buttonSize + padding), -20)
		end

		btn:Show()
		table.insert(frame.esButtons, btn)
	end

	-- Apply opacity
	frame:SetAlpha(SP.opt.esTracker.opacity or 1.0)
end

-- Scan for Earth Shields in the raid/party
-- Optimized: uses direct buff lookup and caches unit list
function SP:ScanEarthShields()
	self.earthShields = {}

	-- Build unit list (cached on group changes)
	local units
	if IsInRaid() then
		-- Cache raid unit list - only rebuild if needed
		if not self.cachedRaidUnits or (GetTime() - (self.cachedRaidUnitsTime or 0)) > 5 then
			self.cachedRaidUnits = {}
			for i = 1, 40 do
				if UnitExists("raid" .. i) then
					table.insert(self.cachedRaidUnits, "raid" .. i)
				end
			end
			self.cachedRaidUnitsTime = GetTime()
		end
		units = self.cachedRaidUnits
	elseif IsInGroup() then
		units = {"player", "party1", "party2", "party3", "party4"}
	else
		units = {"player"}
	end

	-- Scan each unit for Earth Shield buff
	for _, unit in ipairs(units) do
		if UnitExists(unit) then
			-- Use optimized direct lookup if available
			local name, icon, count, _, duration, expirationTime, caster
			if AuraUtil and AuraUtil.FindAuraByName then
				name, icon, count, _, duration, expirationTime, _, _, _, _, _, _, _, _, _, _, _, _, _, _, caster = AuraUtil.FindAuraByName("Earth Shield", unit)
			else
				-- Fallback: scan first 20 buffs
				for i = 1, 20 do
					local buffName, buffIcon, buffCount, _, buffDuration, buffExpiration, buffCaster = UnitBuff(unit, i)
					if not buffName then break end
					if buffName == "Earth Shield" then
						name, icon, count, duration, expirationTime, caster = buffName, buffIcon, buffCount, buffDuration, buffExpiration, buffCaster
						break
					end
				end
			end

			if name then
				local targetGUID = UnitGUID(unit)
				local targetName = UnitName(unit)
				local casterName = caster and UnitName(caster) or "Unknown"
				local _, casterClass = caster and UnitClass(caster) or nil, nil

				self.earthShields[targetGUID] = {
					targetGUID = targetGUID,
					targetName = targetName,
					casterName = casterName,
					casterClass = casterClass,
					charges = count or 0,
					expirationTime = expirationTime,
					icon = icon
				}
			end
		end
	end

	self:UpdateESTrackerFrame()
end

-- Update Earth Shield tracker border visibility
function SP:UpdateESTrackerBorder()
	local frame = self.esTrackerFrame
	if not frame then return end

	if SP.opt.esTracker.hideBorder then
		frame:SetBackdrop(nil)
		if frame.title then frame.title:Hide() end
	else
		frame:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 }
		})
		frame:SetBackdropColor(0, 0, 0, 0.8)
		frame:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
		if frame.title then frame.title:Show() end
	end
end

-- Update Earth Shield tracker opacity
function SP:UpdateESTrackerOpacity()
	local frame = self.esTrackerFrame
	if frame then
		frame:SetAlpha(SP.opt.esTracker.opacity or 1.0)
	end
end

-- Toggle Earth Shield tracker visibility
function SP:ToggleESTracker()
	self:InitESTracker()
	if not self.esTrackerFrame then
		self:CreateESTrackerFrame()
	end

	if self.esTrackerFrame:IsShown() then
		self.esTrackerFrame:Hide()
		self:DisableESTrackerEvents()  -- Stop UNIT_AURA tracking
		SP.opt.esTracker.enabled = false
	else
		-- Restore saved position
		local pos = SP.opt.esTracker.position
		if pos then
			self.esTrackerFrame:ClearAllPoints()
			self.esTrackerFrame:SetPoint(pos.point, UIParent, pos.point, pos.x, pos.y)
		end
		self:UpdateESTrackerBorder()
		self:ScanEarthShields()
		self.esTrackerFrame:Show()
		self:EnableESTrackerEvents()  -- Start UNIT_AURA tracking
		SP.opt.esTracker.enabled = true
	end
end

-- Setup Earth Shield tracker update timer
function SP:SetupESTrackerUpdater()
	if self.esTrackerUpdateFrame then return end

	-- Register ES tracker updates with consolidated update system (1fps)
	if not self.updateSystem.subsystems["esTracker"] then
		self:RegisterUpdateSubsystem("esTracker", 1.0, function()
			if SP.esTrackerFrame and SP.esTrackerFrame:IsShown() then
				SP:ScanEarthShields()
			end
		end)
	end

	-- Create event frame for immediate updates (no OnUpdate, just events)
	-- Don't register UNIT_AURA here - EnableESTrackerEvents will do it
	local eventFrame = CreateFrame("Frame")
	eventFrame:RegisterEvent("GROUP_LEFT")
	eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
	eventFrame:SetScript("OnEvent", function(self, event, unit)
		if event == "GROUP_LEFT" then
			SP:ClearESTracker()
		elseif event == "GROUP_ROSTER_UPDATE" then
			if not IsInGroup() then
				SP:ClearESTracker()
			end
		end
		-- UNIT_AURA events trigger immediate scan if tracker is visible
		if event == "UNIT_AURA" and SP.esTrackerFrame and SP.esTrackerFrame:IsShown() then
			SP:ScanEarthShields()
		end
	end)

	self.esTrackerUpdateFrame = eventFrame
end

-- Enable ES tracker events (called when tracker is shown)
function SP:EnableESTrackerEvents()
	if self.esTrackerUpdateFrame and not self.esTrackerEventsEnabled then
		self.esTrackerUpdateFrame:RegisterEvent("UNIT_AURA")
		self.esTrackerEventsEnabled = true
	end
	self:EnableUpdateSubsystem("esTracker")
end

-- Disable ES tracker events (called when tracker is hidden)
function SP:DisableESTrackerEvents()
	if self.esTrackerUpdateFrame and self.esTrackerEventsEnabled then
		self.esTrackerUpdateFrame:UnregisterEvent("UNIT_AURA")
		self.esTrackerEventsEnabled = false
	end
	self:DisableUpdateSubsystem("esTracker")
end

function SP:ClearESTracker()
	if self.trackedEarthShields then
		wipe(self.trackedEarthShields)
	end
	if self.esTrackerButtons then
		for _, btn in pairs(self.esTrackerButtons) do
			btn:Hide()
		end
	end
	self:UpdateESTrackerFrame()
end

-- Initialize Earth Shield tracker
function SP:InitializeESTracker()
	self:InitESTracker()
	self:CreateESTrackerFrame()
	self:SetupESTrackerUpdater()

	-- Show if it was enabled
	if SP.opt.esTracker.enabled then
		local pos = SP.opt.esTracker.position
		if pos then
			self.esTrackerFrame:ClearAllPoints()
			self.esTrackerFrame:SetPoint(pos.point, UIParent, pos.point, pos.x, pos.y)
		end
		self:UpdateESTrackerBorder()
		self:ScanEarthShields()
		self.esTrackerFrame:Show()
		self:EnableESTrackerEvents()  -- Start UNIT_AURA tracking
	end
end

-- Register /spestrack slash command
SLASH_SPESTRACK1 = "/spestrack"
SLASH_SPESTRACK2 = "/spearthshield"
SlashCmdList["SPESTRACK"] = function(msg)
	msg = (msg or ""):lower():trim()

	if msg == "toggle" or msg == "" then
		SP:ToggleESTracker()
	elseif msg == "show" then
		SP:InitESTracker()
		if not SP.esTrackerFrame then
			SP:CreateESTrackerFrame()
		end
		local pos = SP.opt.esTracker.position
		if pos then
			SP.esTrackerFrame:ClearAllPoints()
			SP.esTrackerFrame:SetPoint(pos.point, UIParent, pos.point, pos.x, pos.y)
		end
		SP:UpdateESTrackerBorder()
		SP:ScanEarthShields()
		SP.esTrackerFrame:Show()
		SP:EnableESTrackerEvents()  -- Start UNIT_AURA tracking
		SP.opt.esTracker.enabled = true
	elseif msg == "hide" then
		if SP.esTrackerFrame then
			SP.esTrackerFrame:Hide()
		end
		SP:DisableESTrackerEvents()  -- Stop UNIT_AURA tracking
		SP.opt.esTracker.enabled = false
	else
		print("|cff00ff00ShamanPower:|r Earth Shield Tracker commands:")
		print("  /spestrack - Toggle the tracker")
		print("  /spestrack show - Show the tracker")
		print("  /spestrack hide - Hide the tracker")
	end
end
