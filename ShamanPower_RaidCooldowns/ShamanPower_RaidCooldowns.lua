-- ============================================================================
-- ShamanPower [Raid Cooldowns] Module
-- Raid Cooldown Management - BL/Heroism and Mana Tide calling
-- ============================================================================

local SP = ShamanPower
if not SP then
	print("|cffff0000ShamanPower [Raid Cooldowns]:|r Core addon not found!")
	return
end

-- Mark module as loaded
SP.RaidCooldownsLoaded = true

-- ============================================================================
-- RAID COOLDOWN MANAGEMENT
-- ============================================================================

function SP:InitRaidCooldowns()
	if not ShamanPower_RaidCooldowns then
		ShamanPower_RaidCooldowns = {}
	end
	if not ShamanPower_RaidCooldowns.bloodlust then
		ShamanPower_RaidCooldowns.bloodlust = {
			primary = nil,
			backup1 = nil,
			backup2 = nil,
			caller = nil,
		}
	end
	if not ShamanPower_RaidCooldowns.manatide then
		ShamanPower_RaidCooldowns.manatide = {}
	end
end

-- Check if player can assign raid cooldowns (RL or assist)
function SP:CanAssignRaidCooldowns()
	-- Allow solo players to manage their own settings
	if GetNumGroupMembers() == 0 then
		return true
	end
	return UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
end

-- Check if player can call raid cooldowns
function SP:CanCallRaidCooldowns()
	if self:CanAssignRaidCooldowns() then return true end
	local playerName = self.player
	local bl = ShamanPower_RaidCooldowns.bloodlust
	if bl and bl.caller and bl.caller == playerName then
		return true
	end
	return false
end

-- Get the shaman who should use BL (checks if primary is dead, falls back to backups)
function SP:GetBloodlustTarget()
	local bl = ShamanPower_RaidCooldowns.bloodlust
	if not bl then return nil end

	-- Check primary
	if bl.primary and not UnitIsDeadOrGhost(bl.primary) then
		return bl.primary
	end
	-- Check backup1
	if bl.backup1 and not UnitIsDeadOrGhost(bl.backup1) then
		return bl.backup1
	end
	-- Check backup2
	if bl.backup2 and not UnitIsDeadOrGhost(bl.backup2) then
		return bl.backup2
	end
	return nil
end

-- Toggle the raid cooldown panel
function SP:ToggleRaidCooldownPanel()
	if not self.raidCooldownPanel then
		self:CreateRaidCooldownPanel()
	end

	if self.raidCooldownPanel:IsShown() then
		self.raidCooldownPanel:Hide()
	else
		self:UpdateRaidCooldownPanel()
		self.raidCooldownPanel:Show()
	end
end

-- Create the raid cooldown panel UI
function SP:CreateRaidCooldownPanel()
	if self.raidCooldownPanel then return end

	local panel = CreateFrame("Frame", "ShamanPowerRaidCooldownPanel", UIParent, "BackdropTemplate")
	panel:SetSize(300, 380)
	panel:SetPoint("CENTER")
	panel:SetMovable(true)
	panel:EnableMouse(true)
	panel:RegisterForDrag("LeftButton")
	panel:SetScript("OnDragStart", panel.StartMoving)
	panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
	panel:SetFrameStrata("DIALOG")
	panel:Hide()

	-- Match main ShamanPower frame styling
	panel:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true,
		tileEdge = true,
		tileSize = 16,
		edgeSize = 16,
		insets = {left = 4, right = 4, top = 4, bottom = 4},
	})
	panel:SetBackdropColor(0.02, 0.02, 0.02, 0.95)
	panel:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.9)

	-- Title with gold color like main frame
	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOP", 0, -12)
	title:SetText("|cffffd200Raid Cooldowns|r")

	-- Close button (small X)
	local closeBtn = CreateFrame("Button", nil, panel)
	closeBtn:SetSize(16, 16)
	closeBtn:SetPoint("TOPRIGHT", -6, -6)
	closeBtn:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
	closeBtn:SetHighlightTexture("Interface\\Buttons\\UI-StopButton", "ADD")
	closeBtn:GetHighlightTexture():SetVertexColor(1, 0, 0)
	closeBtn:SetScript("OnClick", function() panel:Hide() end)

	-- Determine if Alliance (Heroism) or Horde (Bloodlust)
	local faction = UnitFactionGroup("player")
	local blName = (faction == "Alliance") and "Heroism" or "Bloodlust"

	-- Horizontal separator under title
	local sep1 = panel:CreateTexture(nil, "ARTWORK")
	sep1:SetHeight(1)
	sep1:SetPoint("TOPLEFT", 10, -32)
	sep1:SetPoint("TOPRIGHT", -10, -32)
	sep1:SetColorTexture(0.5, 0.5, 0.5, 0.5)

	-- BL/Heroism Section Header
	local blHeader = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	blHeader:SetPoint("TOPLEFT", 15, -42)
	blHeader:SetText("|cffff8800" .. blName .. " Assignment|r")

	-- Primary dropdown
	local primaryLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	primaryLabel:SetPoint("TOPLEFT", 25, -65)
	primaryLabel:SetText("|cffffffffPrimary:|r")

	local primaryDropdown = CreateFrame("Frame", "ShamanPowerRCPrimaryDropdown", panel, "UIDropDownMenuTemplate")
	primaryDropdown:SetPoint("TOPLEFT", 85, -60)
	UIDropDownMenu_SetWidth(primaryDropdown, 130)
	panel.primaryDropdown = primaryDropdown

	-- Backup 1 dropdown
	local backup1Label = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	backup1Label:SetPoint("TOPLEFT", 25, -95)
	backup1Label:SetText("|cffffffffBackup 1:|r")

	local backup1Dropdown = CreateFrame("Frame", "ShamanPowerRCBackup1Dropdown", panel, "UIDropDownMenuTemplate")
	backup1Dropdown:SetPoint("TOPLEFT", 85, -90)
	UIDropDownMenu_SetWidth(backup1Dropdown, 130)
	panel.backup1Dropdown = backup1Dropdown

	-- Backup 2 dropdown
	local backup2Label = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	backup2Label:SetPoint("TOPLEFT", 25, -125)
	backup2Label:SetText("|cffffffffBackup 2:|r")

	local backup2Dropdown = CreateFrame("Frame", "ShamanPowerRCBackup2Dropdown", panel, "UIDropDownMenuTemplate")
	backup2Dropdown:SetPoint("TOPLEFT", 85, -120)
	UIDropDownMenu_SetWidth(backup2Dropdown, 130)
	panel.backup2Dropdown = backup2Dropdown

	-- Caller dropdown
	local callerLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	callerLabel:SetPoint("TOPLEFT", 25, -155)
	callerLabel:SetText("|cffffffffCaller:|r")

	local callerDropdown = CreateFrame("Frame", "ShamanPowerRCCallerDropdown", panel, "UIDropDownMenuTemplate")
	callerDropdown:SetPoint("TOPLEFT", 85, -150)
	UIDropDownMenu_SetWidth(callerDropdown, 130)
	panel.callerDropdown = callerDropdown

	-- Separator before Mana Tide section
	local sep2 = panel:CreateTexture(nil, "ARTWORK")
	sep2:SetHeight(1)
	sep2:SetPoint("TOPLEFT", 10, -185)
	sep2:SetPoint("TOPRIGHT", -10, -185)
	sep2:SetColorTexture(0.5, 0.5, 0.5, 0.5)

	-- Mana Tide Section Header
	local mtHeader = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	mtHeader:SetPoint("TOPLEFT", 15, -197)
	mtHeader:SetText("|cff0088ffMana Tide Assignments|r")

	local mtDesc = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	mtDesc:SetPoint("TOPLEFT", 25, -215)
	mtDesc:SetText("|cff888888Assign a caller for each shaman's Mana Tide|r")

	-- Column headers with gold color
	local shamanHeader = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	shamanHeader:SetPoint("TOPLEFT", 25, -235)
	shamanHeader:SetText("|cffffd200Shaman (Group)|r")

	local callerHeader = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	callerHeader:SetPoint("TOPLEFT", 150, -235)
	callerHeader:SetText("|cffffd200Caller|r")

	-- Container for MT assignments (will be populated dynamically)
	local mtContainer = CreateFrame("Frame", "ShamanPowerMTContainer", panel)
	mtContainer:SetPoint("TOPLEFT", 25, -253)
	mtContainer:SetSize(280, 120)
	panel.mtContainer = mtContainer
	panel.mtRows = {}

	self.raidCooldownPanel = panel
end

-- Get list of shamans in the raid/party
function SP:GetRaidShamans()
	local shamans = {}
	local prefix, maxMembers

	if IsInRaid() then
		prefix = "raid"
		maxMembers = 40
	elseif IsInGroup() then
		prefix = "party"
		maxMembers = 4
		-- Include self
		local _, class = UnitClass("player")
		if class == "SHAMAN" then
			local name = UnitName("player")
			table.insert(shamans, name)
		end
	else
		-- Solo
		local _, class = UnitClass("player")
		if class == "SHAMAN" then
			local name = UnitName("player")
			table.insert(shamans, name)
		end
		return shamans
	end

	for i = 1, maxMembers do
		local unit = prefix .. i
		if UnitExists(unit) then
			local _, class = UnitClass(unit)
			if class == "SHAMAN" then
				local name = UnitName(unit)
				table.insert(shamans, name)
			end
		end
	end

	return shamans
end

-- Get list of all raid/party members
function SP:GetRaidMembers()
	local members = {}
	local prefix, maxMembers

	if IsInRaid() then
		prefix = "raid"
		maxMembers = 40
	elseif IsInGroup() then
		prefix = "party"
		maxMembers = 4
		local name = UnitName("player")
		table.insert(members, name)
	else
		local name = UnitName("player")
		table.insert(members, name)
		return members
	end

	for i = 1, maxMembers do
		local unit = prefix .. i
		if UnitExists(unit) then
			local name = UnitName(unit)
			table.insert(members, name)
		end
	end

	return members
end

-- Update the raid cooldown panel dropdowns
function SP:UpdateRaidCooldownPanel()
	if not self.raidCooldownPanel then return end

	self:InitRaidCooldowns()

	local shamans = self:GetRaidShamans()
	local members = self:GetRaidMembers()
	local bl = ShamanPower_RaidCooldowns.bloodlust

	-- Helper to create dropdown menu
	local function InitShamanDropdown(dropdown, field)
		UIDropDownMenu_Initialize(dropdown, function(self, level)
			-- Read current value each time dropdown opens
			local currentValue = bl[field]
			local info = UIDropDownMenu_CreateInfo()

			-- None option
			info.text = "-- None --"
			info.value = nil
			info.checked = (currentValue == nil)
			info.func = function()
				bl[field] = nil
				UIDropDownMenu_SetText(dropdown, "-- None --")
				SP:SendRaidCooldownSync()
			end
			UIDropDownMenu_AddButton(info)

			-- Shaman options
			for _, name in ipairs(shamans) do
				info.text = name
				info.value = name
				info.checked = (currentValue == name)
				info.func = function()
					bl[field] = name
					UIDropDownMenu_SetText(dropdown, name)
					SP:SendRaidCooldownSync()
				end
				UIDropDownMenu_AddButton(info)
			end
		end)
		UIDropDownMenu_SetText(dropdown, bl[field] or "-- None --")
	end

	-- Helper for caller dropdown (all members)
	local function InitCallerDropdown(dropdown)
		UIDropDownMenu_Initialize(dropdown, function(self, level)
			-- Read current value each time dropdown opens
			local currentValue = bl.caller
			local info = UIDropDownMenu_CreateInfo()

			info.text = "-- None --"
			info.value = nil
			info.checked = (currentValue == nil)
			info.func = function()
				bl.caller = nil
				UIDropDownMenu_SetText(dropdown, "-- None --")
				SP:SendRaidCooldownSync()
				SP:UpdateCallerButtons()
			end
			UIDropDownMenu_AddButton(info)

			for _, name in ipairs(members) do
				info.text = name
				info.value = name
				info.checked = (currentValue == name)
				info.func = function()
					bl.caller = name
					UIDropDownMenu_SetText(dropdown, name)
					SP:SendRaidCooldownSync()
					SP:UpdateCallerButtons()
				end
				UIDropDownMenu_AddButton(info)
			end
		end)
		UIDropDownMenu_SetText(dropdown, bl.caller or "-- None --")
	end

	-- Initialize dropdowns
	InitShamanDropdown(self.raidCooldownPanel.primaryDropdown, "primary")
	InitShamanDropdown(self.raidCooldownPanel.backup1Dropdown, "backup1")
	InitShamanDropdown(self.raidCooldownPanel.backup2Dropdown, "backup2")
	InitCallerDropdown(self.raidCooldownPanel.callerDropdown)

	-- Update Mana Tide rows
	self:UpdateManaTideRows(members)

	-- Update floating caller buttons
	self:UpdateCallerButtons()
end

-- Get shamans who have Mana Tide with their group number
function SP:GetManaTideShamans()
	local mtShamans = {}
	local prefix, maxMembers

	if IsInRaid() then
		prefix = "raid"
		maxMembers = 40
	elseif IsInGroup() then
		prefix = "party"
		maxMembers = 4
		-- Check self
		local _, class = UnitClass("player")
		if class == "SHAMAN" then
			-- Check if we have Mana Tide (spell ID 16190)
			if IsSpellKnown(16190) then
				local name = UnitName("player")
				table.insert(mtShamans, {name = name, group = 1})
			end
		end
	else
		-- Solo
		local _, class = UnitClass("player")
		if class == "SHAMAN" and IsSpellKnown(16190) then
			local name = UnitName("player")
			table.insert(mtShamans, {name = name, group = 1})
		end
		return mtShamans
	end

	for i = 1, maxMembers do
		local unit = prefix .. i
		if UnitExists(unit) then
			local _, class = UnitClass(unit)
			if class == "SHAMAN" then
				local name = UnitName(unit)
				-- Check if this shaman has Mana Tide via AllShamans data
				-- For now, add all shamans and let them self-report MT capability
				local group = 1
				if IsInRaid() then
					local _, _, subgroup = GetRaidRosterInfo(i)
					group = subgroup or 1
				end
				-- Add all shamans - if they don't have MT, assignment just won't work for them
				table.insert(mtShamans, {name = name, group = group})
			end
		end
	end

	return mtShamans
end

-- Update Mana Tide assignment rows
function SP:UpdateManaTideRows(members)
	local panel = self.raidCooldownPanel
	if not panel or not panel.mtContainer then return end

	-- Hide existing rows
	for _, row in ipairs(panel.mtRows or {}) do
		if row.label then row.label:Hide() end
		if row.dropdown then row.dropdown:Hide() end
	end
	panel.mtRows = {}

	-- Get shamans with Mana Tide
	local mtShamans = self:GetManaTideShamans()
	local mt = ShamanPower_RaidCooldowns.manatide

	local yOffset = 0
	for i, shamanInfo in ipairs(mtShamans) do
		local shamanName = shamanInfo.name
		local group = shamanInfo.group

		-- Create row elements
		local row = {}

		-- Shaman name label
		row.label = panel.mtContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		row.label:SetPoint("TOPLEFT", 0, yOffset)
		row.label:SetText(shamanName .. " (G" .. group .. ")")
		row.label:SetTextColor(1, 1, 1)

		-- Caller dropdown
		row.dropdown = CreateFrame("Frame", "ShamanPowerMTCaller" .. i, panel.mtContainer, "UIDropDownMenuTemplate")
		row.dropdown:SetPoint("TOPLEFT", 100, yOffset + 5)
		UIDropDownMenu_SetWidth(row.dropdown, 90)

		UIDropDownMenu_Initialize(row.dropdown, function(self, level)
			-- Read current value each time dropdown opens
			local currentCaller = mt[shamanName] and mt[shamanName].caller or nil
			local info = UIDropDownMenu_CreateInfo()

			info.text = "-- None --"
			info.value = nil
			info.checked = (currentCaller == nil)
			info.func = function()
				if not mt[shamanName] then mt[shamanName] = {} end
				mt[shamanName].caller = nil
				UIDropDownMenu_SetText(row.dropdown, "-- None --")
				SP:SendRaidCooldownSync()
				SP:UpdateCallerButtons()
			end
			UIDropDownMenu_AddButton(info)

			for _, memberName in ipairs(members) do
				info.text = memberName
				info.value = memberName
				info.checked = (currentCaller == memberName)
				info.func = function()
					if not mt[shamanName] then mt[shamanName] = {} end
					mt[shamanName].caller = memberName
					UIDropDownMenu_SetText(row.dropdown, memberName)
					SP:SendRaidCooldownSync()
					SP:UpdateCallerButtons()
				end
				UIDropDownMenu_AddButton(info)
			end
		end)
		local initialCaller = mt[shamanName] and mt[shamanName].caller or nil
		UIDropDownMenu_SetText(row.dropdown, initialCaller or "-- None --")

		table.insert(panel.mtRows, row)
		yOffset = yOffset - 30
	end

	-- Resize panel based on content
	local baseHeight = 280
	local mtHeight = #mtShamans * 30
	panel:SetHeight(baseHeight + mtHeight)
end

-- Call Mana Tide for a specific shaman
function SP:CallManaTideForShaman(shamanName)
	local mt = ShamanPower_RaidCooldowns.manatide
	local canCall = self:CanAssignRaidCooldowns() or (mt[shamanName] and mt[shamanName].caller == self.player)

	if not canCall then
		print("|cffff0000ShamanPower:|r You don't have permission to call Mana Tide for " .. shamanName)
		return
	end

	self:SendMessage("MTCALL|" .. shamanName)

	if shamanName == self.player then
		self:ShowManaTideAlert()
	end

	print("|cff00ff00ShamanPower:|r Called Mana Tide from " .. shamanName)
end

-- Send raid cooldown sync to group
function SP:SendRaidCooldownSync()
	local bl = ShamanPower_RaidCooldowns.bloodlust
	local data = string.format("RCSYNC|%s|%s|%s|%s",
		bl.primary or "",
		bl.backup1 or "",
		bl.backup2 or "",
		bl.caller or ""
	)
	self:SendMessage(data)

	-- Also send MT assignments (always send, even if empty, so receivers can clear)
	local mt = ShamanPower_RaidCooldowns.manatide
	local mtParts = {}
	for shamanName, mtData in pairs(mt) do
		if mtData.caller then
			table.insert(mtParts, shamanName .. ":" .. mtData.caller)
		end
	end
	self:SendMessage("MTSYNC|" .. table.concat(mtParts, ","))
end

-- Call for Bloodlust/Heroism
function SP:CallBloodlust()
	if not self:CanCallRaidCooldowns() then
		print("|cffff0000ShamanPower:|r You don't have permission to call for Bloodlust.")
		return
	end

	local target = self:GetBloodlustTarget()
	if not target then
		print("|cffff0000ShamanPower:|r No shaman assigned for Bloodlust!")
		return
	end

	-- Send call message
	self:SendMessage("BLCALL|" .. target)

	-- Show alert if we're the target
	if target == self.player then
		self:ShowBloodlustAlert()
	end

	local faction = UnitFactionGroup("player")
	local blName = (faction == "Alliance") and "Heroism" or "Bloodlust"
	print("|cff00ff00ShamanPower:|r Called " .. blName .. " from " .. target)
end

-- Call for Mana Tide
function SP:CallManaTide()
	if not self:CanCallRaidCooldowns() then
		print("|cffff0000ShamanPower:|r You don't have permission to call for Mana Tide.")
		return
	end

	-- Send call to all shamans with Mana Tide
	self:SendMessage("MTCALL")
	print("|cff00ff00ShamanPower:|r Called for Mana Tide!")
end

-- Show alert when called for Bloodlust
function SP:ShowBloodlustAlert()
	local faction = UnitFactionGroup("player")
	local blName = (faction == "Alliance") and "HEROISM" or "BLOODLUST"
	local icon = (faction == "Alliance") and "Interface\\Icons\\Ability_Shaman_Heroism" or "Interface\\Icons\\Spell_Nature_Bloodlust"

	-- Show center screen alert
	self:ShowCenterScreenAlert(icon, "USE " .. blName .. " NOW!")

	-- Also add glow/shake to cooldown bar button
	local blSpellID = (faction == "Alliance") and 32182 or 2825
	self:AddCooldownButtonAlert(blSpellID)
end

-- Show alert when called for Mana Tide
function SP:ShowManaTideAlert()
	-- Show center screen alert
	self:ShowCenterScreenAlert("Interface\\Icons\\Spell_Frost_SummonWaterElemental", "USE MANA TIDE NOW!")

	-- Also add glow/shake to cooldown bar button
	self:AddCooldownButtonAlert(16190)  -- Mana Tide Totem spell ID
end

-- Show a center screen alert with icon and text
function SP:ShowCenterScreenAlert(iconPath, text)
	-- Check if any alerts are enabled
	local showIcon = self.opt.raidCDShowWarningIcon ~= false
	local showText = self.opt.raidCDShowWarningText ~= false
	local playSound = self.opt.raidCDPlaySound ~= false

	-- If nothing to show, just play sound if enabled
	if not showIcon and not showText then
		if playSound then
			ShamanPower:PlaySoundWithVolume(8959, self.opt.raidCDSoundVolume, false)
		end
		return
	end

	if not self.centerAlert then
		local frame = CreateFrame("Frame", "ShamanPowerCenterAlert", UIParent)
		frame:SetSize(150, 150)
		frame:SetPoint("CENTER", 0, 100)
		frame:SetFrameStrata("FULLSCREEN_DIALOG")

		local iconTex = frame:CreateTexture(nil, "ARTWORK")
		iconTex:SetSize(128, 128)
		iconTex:SetPoint("CENTER")
		iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		frame.icon = iconTex

		local alertText = frame:CreateFontString(nil, "OVERLAY")
		alertText:SetFont("Fonts\\FRIZQT__.TTF", 24, "OUTLINE")
		alertText:SetPoint("TOP", frame, "BOTTOM", 0, -10)
		alertText:SetTextColor(1, 0.3, 0)
		frame.text = alertText

		frame:Hide()
		self.centerAlert = frame
	end

	-- Show/hide icon based on option
	if showIcon then
		self.centerAlert.icon:SetTexture(iconPath)
		self.centerAlert.icon:Show()
	else
		self.centerAlert.icon:Hide()
	end

	-- Show/hide text based on option
	if showText then
		self.centerAlert.text:SetText(text)
		self.centerAlert.text:Show()
	else
		self.centerAlert.text:Hide()
	end

	self.centerAlert:Show()

	-- Pulse animation (throttled to ~30fps)
	self.centerAlert.elapsed = 0
	self.centerAlert.updateElapsed = 0
	self.centerAlert:SetScript("OnUpdate", function(self, elapsed)
		self.elapsed = self.elapsed + elapsed  -- Always accumulate for animation timing
		self.updateElapsed = (self.updateElapsed or 0) + elapsed
		if self.updateElapsed < 0.033 then return end  -- ~30fps visual updates
		self.updateElapsed = 0

		local alpha = 0.6 + 0.4 * math.sin(self.elapsed * 4)
		self:SetAlpha(alpha)
		if showIcon then
			local scale = 1 + 0.05 * math.sin(self.elapsed * 5)
			self.icon:SetSize(128 * scale, 128 * scale)
		end
	end)

	-- Hide after 5 seconds
	C_Timer.After(5, function()
		if SP.centerAlert then
			SP.centerAlert:Hide()
			SP.centerAlert:SetScript("OnUpdate", nil)
		end
	end)

	-- Play sound if enabled
	if playSound then
		ShamanPower:PlaySoundWithVolume(8959, self.opt.raidCDSoundVolume, false)
	end
end

-- Handle incoming raid cooldown messages
function SP:HandleRaidCooldownMessage(prefix, message, sender)
	local cmd, rest = strsplit("|", message, 2)

	if cmd == "RCSYNC" then
		-- Sync from raid leader
		local primary, backup1, backup2, caller = strsplit("|", rest)
		self:InitRaidCooldowns()
		local bl = ShamanPower_RaidCooldowns.bloodlust
		bl.primary = (primary ~= "") and primary or nil
		bl.backup1 = (backup1 ~= "") and backup1 or nil
		bl.backup2 = (backup2 ~= "") and backup2 or nil
		bl.caller = (caller ~= "") and caller or nil

		if self.raidCooldownPanel and self.raidCooldownPanel:IsShown() then
			self:UpdateRaidCooldownPanel()
		end

	elseif cmd == "BLCALL" then
		-- Called for Bloodlust
		local target = rest
		if target == self.player then
			self:ShowBloodlustAlert()
		end

	elseif cmd == "MTCALL" then
		-- Called for Mana Tide - check if it's for us specifically or broadcast
		local targetShaman = rest
		if targetShaman and targetShaman ~= "" then
			-- Specific shaman called
			if targetShaman == self.player and IsSpellKnown(16190) then
				self:ShowManaTideAlert()
			end
		else
			-- Broadcast to all MT shamans
			if IsSpellKnown(16190) then
				self:ShowManaTideAlert()
			end
		end

	elseif cmd == "MTSYNC" then
		-- Sync MT assignments from raid leader
		self:InitRaidCooldowns()
		local mt = ShamanPower_RaidCooldowns.manatide
		-- Clear existing
		for k in pairs(mt) do mt[k] = nil end
		-- Parse new assignments
		if rest and rest ~= "" then
			for pair in string.gmatch(rest, "[^,]+") do
				local shamanName, callerName = strsplit(":", pair)
				if shamanName and callerName then
					mt[shamanName] = {caller = callerName}
				end
			end
		end

		if self.raidCooldownPanel and self.raidCooldownPanel:IsShown() then
			self:UpdateRaidCooldownPanel()
		end
		self:UpdateCallerButtons()
	end
end

-- Register slash command
SLASH_SPRAID1 = "/spraid"
SlashCmdList["SPRAID"] = function(msg)
	SP:ToggleRaidCooldownPanel()
end

-- ============================================================================
-- FLOATING CALLER BUTTONS
-- Shows buttons on screen for assigned callers to quickly call BL/MT
-- ============================================================================

function SP:CreateCallerButtonFrame()
	if self.callerButtonFrame then return self.callerButtonFrame end

	local frame = CreateFrame("Frame", "ShamanPowerCallerButtons", UIParent, "BackdropTemplate")
	frame:SetSize(100, 60)
	frame:SetPoint("CENTER", UIParent, "CENTER", 200, 200)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self) if self:IsMovable() then self:StartMoving() end end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		-- Save position
		local point, _, relPoint, x, y = self:GetPoint()
		if not ShamanPower_RaidCooldowns.callerButtonPos then
			ShamanPower_RaidCooldowns.callerButtonPos = {}
		end
		ShamanPower_RaidCooldowns.callerButtonPos.point = point
		ShamanPower_RaidCooldowns.callerButtonPos.relPoint = relPoint
		ShamanPower_RaidCooldowns.callerButtonPos.x = x
		ShamanPower_RaidCooldowns.callerButtonPos.y = y
	end)
	frame:SetFrameStrata("HIGH")
	frame:Hide()

	frame:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 14,
		insets = {left = 3, right = 3, top = 3, bottom = 3},
	})
	frame:SetBackdropColor(0.1, 0.1, 0.1, 0.85)
	frame:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

	-- Heroism/Bloodlust button
	local faction = UnitFactionGroup("player")
	local blIcon = (faction == "Alliance") and "Interface\\Icons\\Ability_Shaman_Heroism" or "Interface\\Icons\\Spell_Nature_Bloodlust"

	local blBtn = CreateFrame("Button", "ShamanPowerCallerBLBtn", frame)
	blBtn:SetSize(40, 40)
	blBtn:SetPoint("TOPLEFT", 8, -8)

	-- Icon texture (inset from border)
	local blIconTex = blBtn:CreateTexture(nil, "ARTWORK")
	blIconTex:SetPoint("TOPLEFT", 3, -3)
	blIconTex:SetPoint("BOTTOMRIGHT", -3, 3)
	blIconTex:SetTexture(blIcon)
	blIconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	blBtn.icon = blIconTex

	-- Orange border for BL button (4 edge textures)
	local borderSize = 3
	local borderColor = {1, 0.5, 0, 1}  -- Orange

	local blBorderTop = blBtn:CreateTexture(nil, "BORDER")
	blBorderTop:SetPoint("TOPLEFT", 0, 0)
	blBorderTop:SetPoint("TOPRIGHT", 0, 0)
	blBorderTop:SetHeight(borderSize)
	blBorderTop:SetColorTexture(unpack(borderColor))

	local blBorderBottom = blBtn:CreateTexture(nil, "BORDER")
	blBorderBottom:SetPoint("BOTTOMLEFT", 0, 0)
	blBorderBottom:SetPoint("BOTTOMRIGHT", 0, 0)
	blBorderBottom:SetHeight(borderSize)
	blBorderBottom:SetColorTexture(unpack(borderColor))

	local blBorderLeft = blBtn:CreateTexture(nil, "BORDER")
	blBorderLeft:SetPoint("TOPLEFT", 0, 0)
	blBorderLeft:SetPoint("BOTTOMLEFT", 0, 0)
	blBorderLeft:SetWidth(borderSize)
	blBorderLeft:SetColorTexture(unpack(borderColor))

	local blBorderRight = blBtn:CreateTexture(nil, "BORDER")
	blBorderRight:SetPoint("TOPRIGHT", 0, 0)
	blBorderRight:SetPoint("BOTTOMRIGHT", 0, 0)
	blBorderRight:SetWidth(borderSize)
	blBorderRight:SetColorTexture(unpack(borderColor))

	local blHighlight = blBtn:CreateTexture(nil, "HIGHLIGHT")
	blHighlight:SetAllPoints(blIconTex)
	blHighlight:SetColorTexture(1, 1, 1, 0.3)

	blBtn:SetScript("OnClick", function()
		SP:CallBloodlust()
	end)
	blBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		local name = (UnitFactionGroup("player") == "Alliance") and "Heroism" or "Bloodlust"
		GameTooltip:SetText("Call " .. name)
		local target = SP:GetBloodlustTarget()
		if target then
			GameTooltip:AddLine("Will call: " .. target, 0, 1, 0)
		end
		GameTooltip:Show()
	end)
	blBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

	-- Name label under BL button (shows who will use BL)
	local blNameLabel = blBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	blNameLabel:SetPoint("TOP", blBtn, "BOTTOM", 0, -2)
	blNameLabel:SetText("")
	blBtn.nameLabel = blNameLabel

	frame.blBtn = blBtn

	-- Container for MT buttons (can have multiple)
	frame.mtButtons = {}

	-- Enable/disable caller button systems based on visibility
	frame:HookScript("OnShow", function()
		SP:EnableCallerCooldownTracking()
		SP:EnableUpdateSubsystem("callerButtons")
	end)
	frame:HookScript("OnHide", function()
		SP:DisableCallerCooldownTracking()
		SP:DisableUpdateSubsystem("callerButtons")
	end)

	self.callerButtonFrame = frame

	-- Restore saved position
	if ShamanPower_RaidCooldowns and ShamanPower_RaidCooldowns.callerButtonPos then
		local pos = ShamanPower_RaidCooldowns.callerButtonPos
		frame:ClearAllPoints()
		frame:SetPoint(pos.point or "CENTER", UIParent, pos.relPoint or "CENTER", pos.x or 200, pos.y or 200)
	end

	return frame
end

function SP:UpdateCallerButtons()
	self:InitRaidCooldowns()

	-- Don't show caller buttons when not in a group
	if GetNumGroupMembers() == 0 then
		if self.callerButtonFrame then
			self.callerButtonFrame:Hide()
		end
		self:DisableCallerCooldownTracking()
		self:DisableUpdateSubsystem("callerButtons")
		return
	end

	local playerName = self.player
	local bl = ShamanPower_RaidCooldowns.bloodlust
	local mt = ShamanPower_RaidCooldowns.manatide

	-- Check if player is a BL caller or MT caller for any shaman
	-- Only consider BL callable if there's a caller assigned AND (player is RL/assist or is the caller)
	local isBLCaller = bl.caller and (self:CanAssignRaidCooldowns() or bl.caller == playerName)
	local mtCallsFor = {}

	-- Check if player is caller for any shaman's MT
	for shamanName, data in pairs(mt) do
		if data.caller == playerName then
			table.insert(mtCallsFor, shamanName)
		end
	end

	-- Also show if RL/assist (they can call anything that has a caller assigned)
	if self:CanAssignRaidCooldowns() then
		-- Get all MT shamans for RL/assist, but only if they have a caller assigned
		local mtShamans = self:GetManaTideShamans()
		for _, info in ipairs(mtShamans) do
			-- Only add if this shaman has a caller assigned
			if mt[info.name] and mt[info.name].caller then
				local found = false
				for _, name in ipairs(mtCallsFor) do
					if name == info.name then found = true break end
				end
				if not found then
					table.insert(mtCallsFor, info.name)
				end
			end
		end
	end

	-- Determine if buttons will actually be shown
	local showBLButton = isBLCaller and (bl.primary or bl.backup1 or bl.backup2)
	local showFrame = showBLButton or #mtCallsFor > 0

	if not showFrame then
		if self.callerButtonFrame then
			self.callerButtonFrame:Hide()
		end
		self:DisableCallerCooldownTracking()
		self:DisableUpdateSubsystem("callerButtons")
		return
	end

	local frame = self:CreateCallerButtonFrame()

	-- Show/hide BL button
	if showBLButton then
		frame.blBtn:Show()
	else
		frame.blBtn:Hide()
	end

	-- Clear old MT buttons
	for _, btn in ipairs(frame.mtButtons) do
		btn:Hide()
	end
	frame.mtButtons = {}

	-- Create MT buttons
	local xOffset = isBLCaller and (bl.primary or bl.backup1 or bl.backup2) and 52 or 8
	local borderSize = 3
	local mtBorderColor = {0.2, 0.6, 1, 1}  -- Blue

	for i, shamanName in ipairs(mtCallsFor) do
		local mtBtn = CreateFrame("Button", "ShamanPowerCallerMTBtn" .. i, frame)
		mtBtn:SetSize(40, 40)
		mtBtn:SetPoint("TOPLEFT", xOffset, -8)

		-- Icon texture (inset from border)
		local mtIconTex = mtBtn:CreateTexture(nil, "ARTWORK")
		mtIconTex:SetPoint("TOPLEFT", 3, -3)
		mtIconTex:SetPoint("BOTTOMRIGHT", -3, 3)
		mtIconTex:SetTexture("Interface\\Icons\\Spell_Frost_SummonWaterElemental")
		mtIconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		mtBtn.icon = mtIconTex

		-- Blue border for MT button (4 edge textures)
		local mtBorderTop = mtBtn:CreateTexture(nil, "BORDER")
		mtBorderTop:SetPoint("TOPLEFT", 0, 0)
		mtBorderTop:SetPoint("TOPRIGHT", 0, 0)
		mtBorderTop:SetHeight(borderSize)
		mtBorderTop:SetColorTexture(unpack(mtBorderColor))

		local mtBorderBottom = mtBtn:CreateTexture(nil, "BORDER")
		mtBorderBottom:SetPoint("BOTTOMLEFT", 0, 0)
		mtBorderBottom:SetPoint("BOTTOMRIGHT", 0, 0)
		mtBorderBottom:SetHeight(borderSize)
		mtBorderBottom:SetColorTexture(unpack(mtBorderColor))

		local mtBorderLeft = mtBtn:CreateTexture(nil, "BORDER")
		mtBorderLeft:SetPoint("TOPLEFT", 0, 0)
		mtBorderLeft:SetPoint("BOTTOMLEFT", 0, 0)
		mtBorderLeft:SetWidth(borderSize)
		mtBorderLeft:SetColorTexture(unpack(mtBorderColor))

		local mtBorderRight = mtBtn:CreateTexture(nil, "BORDER")
		mtBorderRight:SetPoint("TOPRIGHT", 0, 0)
		mtBorderRight:SetPoint("BOTTOMRIGHT", 0, 0)
		mtBorderRight:SetWidth(borderSize)
		mtBorderRight:SetColorTexture(unpack(mtBorderColor))

		local mtHighlight = mtBtn:CreateTexture(nil, "HIGHLIGHT")
		mtHighlight:SetAllPoints(mtIconTex)
		mtHighlight:SetColorTexture(1, 1, 1, 0.3)

		mtBtn.shamanName = shamanName
		mtBtn:SetScript("OnClick", function(self)
			SP:CallManaTideForShaman(self.shamanName)
		end)
		mtBtn:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText("Call Mana Tide")
			GameTooltip:AddLine("From: " .. self.shamanName, 0, 0.7, 1)
			GameTooltip:Show()
		end)
		mtBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

		-- Name label under MT button (shows shaman name)
		local mtNameLabel = mtBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		mtNameLabel:SetPoint("TOP", mtBtn, "BOTTOM", 0, -2)
		mtNameLabel:SetText(shamanName)
		mtBtn.nameLabel = mtNameLabel

		table.insert(frame.mtButtons, mtBtn)
		xOffset = xOffset + 44
	end

	-- Update BL button's name label with the active target
	if frame.blBtn and frame.blBtn.nameLabel then
		local activeTarget = self:GetBloodlustTarget()
		if activeTarget then
			frame.blBtn.nameLabel:SetText(activeTarget)
		else
			frame.blBtn.nameLabel:SetText("")
		end
	end

	-- Resize frame based on buttons (taller to fit name labels)
	local numButtons = (isBLCaller and (bl.primary or bl.backup1 or bl.backup2) and 1 or 0) + #mtCallsFor
	local width = math.max(60, numButtons * 44 + 16)
	frame:SetSize(width, 62)  -- 40 button + 2 gap + 12 text + 8 padding

	frame:Show()

	-- Apply scale and opacity settings
	self:UpdateCallerButtonScale()
	self:UpdateCallerButtonOpacity()

	-- Start cooldown tracking update
	self:StartCallerCooldownTracking()
end

-- ============================================================================
-- CALLER BUTTON COOLDOWN TRACKING
-- Tracks when BL/MT are used and shows cooldown on caller buttons
-- ============================================================================

SP.callerCooldowns = {}  -- {[shamanName] = {bl = {start, duration}, mt = {start, duration}}}

-- Cooldown durations
local BL_COOLDOWN = 600  -- 10 minutes
local MT_COOLDOWN = 300  -- 5 minutes

-- Track spell casts via combat log
function SP:SetupCallerCooldownTracking()
	if self.callerCooldownFrame then return end

	local frame = CreateFrame("Frame")
	-- Don't register event here - EnableCallerCooldownTracking will do it
	frame:SetScript("OnEvent", function(self, event)
		SP:OnCombatLogEvent()
	end)
	self.callerCooldownFrame = frame
end

-- Enable COMBAT_LOG_EVENT_UNFILTERED tracking (called when caller buttons are shown)
function SP:EnableCallerCooldownTracking()
	self:SetupCallerCooldownTracking()
	if self.callerCooldownFrame and not self.callerCooldownTrackingEnabled then
		self.callerCooldownFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
		self.callerCooldownTrackingEnabled = true
	end
end

-- Disable COMBAT_LOG_EVENT_UNFILTERED tracking (called when caller buttons are hidden)
function SP:DisableCallerCooldownTracking()
	if self.callerCooldownFrame and self.callerCooldownTrackingEnabled then
		self.callerCooldownFrame:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
		self.callerCooldownTrackingEnabled = false
	end
end

function SP:OnCombatLogEvent()
	local _, subEvent, _, sourceGUID, sourceName, _, _, _, _, _, _, spellID = CombatLogGetCurrentEventInfo()

	if subEvent ~= "SPELL_CAST_SUCCESS" then return end

	-- Check for Bloodlust/Heroism
	if spellID == 2825 or spellID == 32182 then
		if sourceName then
			sourceName = self:RemoveRealmName(sourceName)
			if not self.callerCooldowns[sourceName] then
				self.callerCooldowns[sourceName] = {}
			end
			self.callerCooldowns[sourceName].bl = {
				start = GetTime(),
				duration = BL_COOLDOWN
			}
			-- Save to SavedVariables (use time() for persistence across reloads)
			self:SaveCallerCooldown(sourceName, "bl", BL_COOLDOWN)
			-- Also clear the alert on this shaman's cooldown bar button
			local blSpellID = (UnitFactionGroup("player") == "Alliance") and 32182 or 2825
			if sourceName == self.player then
				self:RemoveCooldownButtonAlert(blSpellID)
			end
		end
	end

	-- Check for Mana Tide Totem
	if spellID == 16190 then
		if sourceName then
			sourceName = self:RemoveRealmName(sourceName)
			if not self.callerCooldowns[sourceName] then
				self.callerCooldowns[sourceName] = {}
			end
			self.callerCooldowns[sourceName].mt = {
				start = GetTime(),
				duration = MT_COOLDOWN
			}
			-- Save to SavedVariables
			self:SaveCallerCooldown(sourceName, "mt", MT_COOLDOWN)
			-- Also clear the alert
			if sourceName == self.player then
				self:RemoveCooldownButtonAlert(16190)
			end
		end
	end
end

-- Save cooldown to SavedVariables for persistence across reloads
function SP:SaveCallerCooldown(shamanName, cdType, duration)
	if not ShamanPower_RaidCooldowns.cooldownTimes then
		ShamanPower_RaidCooldowns.cooldownTimes = {}
	end
	if not ShamanPower_RaidCooldowns.cooldownTimes[shamanName] then
		ShamanPower_RaidCooldowns.cooldownTimes[shamanName] = {}
	end
	-- Store using time() (Unix epoch) so it persists across reloads
	ShamanPower_RaidCooldowns.cooldownTimes[shamanName][cdType] = {
		timestamp = time(),
		duration = duration
	}
end

-- Restore cooldowns from SavedVariables on login/reload
function SP:RestoreCallerCooldowns()
	if not ShamanPower_RaidCooldowns or not ShamanPower_RaidCooldowns.cooldownTimes then
		return
	end

	local now = time()
	local gameNow = GetTime()

	for shamanName, cds in pairs(ShamanPower_RaidCooldowns.cooldownTimes) do
		if not self.callerCooldowns[shamanName] then
			self.callerCooldowns[shamanName] = {}
		end

		for cdType, cdData in pairs(cds) do
			local elapsed = now - cdData.timestamp
			local remaining = cdData.duration - elapsed

			if remaining > 0 then
				-- Cooldown still active, restore it
				-- Calculate what GetTime() would have been when it started
				local adjustedStart = gameNow - elapsed
				self.callerCooldowns[shamanName][cdType] = {
					start = adjustedStart,
					duration = cdData.duration
				}
			else
				-- Cooldown expired, clear it
				ShamanPower_RaidCooldowns.cooldownTimes[shamanName][cdType] = nil
			end
		end
	end
end

-- Start the cooldown tracking OnUpdate
function SP:StartCallerCooldownTracking()
	local frame = self.callerButtonFrame
	if not frame then return end

	-- Register caller button updates with consolidated update system (5fps)
	if not self.updateSystem.subsystems["callerButtons"] then
		self:RegisterUpdateSubsystem("callerButtons", 0.2, function()
			SP:UpdateCallerButtonCooldowns()
		end)
	end
	-- Only enable if caller buttons frame is shown
	if frame:IsShown() then
		self:EnableCallerCooldownTracking()  -- Also registers COMBAT_LOG_EVENT_UNFILTERED
		self:EnableUpdateSubsystem("callerButtons")
	else
		self:DisableCallerCooldownTracking()
		self:DisableUpdateSubsystem("callerButtons")
	end
end

-- Update cooldown displays on caller buttons
function SP:UpdateCallerButtonCooldowns()
	local frame = self.callerButtonFrame
	if not frame or not frame:IsShown() then return end

	local now = GetTime()

	-- Update BL button cooldown
	if frame.blBtn and frame.blBtn:IsShown() then
		local activeTarget = self:GetBloodlustTarget()
		local cdInfo = activeTarget and self.callerCooldowns[activeTarget] and self.callerCooldowns[activeTarget].bl

		if cdInfo then
			local elapsed = now - cdInfo.start
			local remaining = cdInfo.duration - elapsed

			if remaining > 0 then
				-- Show cooldown
				self:SetCallerButtonCooldown(frame.blBtn, cdInfo.start, cdInfo.duration)
			else
				-- Cooldown done
				self:ClearCallerButtonCooldown(frame.blBtn)
				self.callerCooldowns[activeTarget].bl = nil
			end
		else
			self:ClearCallerButtonCooldown(frame.blBtn)
		end
	end

	-- Update MT button cooldowns
	for _, mtBtn in ipairs(frame.mtButtons or {}) do
		if mtBtn:IsShown() then
			local shamanName = mtBtn.shamanName
			local cdInfo = shamanName and self.callerCooldowns[shamanName] and self.callerCooldowns[shamanName].mt

			if cdInfo then
				local elapsed = now - cdInfo.start
				local remaining = cdInfo.duration - elapsed

				if remaining > 0 then
					self:SetCallerButtonCooldown(mtBtn, cdInfo.start, cdInfo.duration)
				else
					self:ClearCallerButtonCooldown(mtBtn)
					self.callerCooldowns[shamanName].mt = nil
				end
			else
				self:ClearCallerButtonCooldown(mtBtn)
			end
		end
	end
end

-- Set cooldown display on a caller button
function SP:SetCallerButtonCooldown(btn, start, duration)
	-- Check if animation is enabled
	if self.opt.raidCDShowButtonAnimation == false then
		return
	end

	-- Create cooldown frame if needed
	if not btn.cooldownFrame then
		local cd = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
		cd:SetAllPoints(btn.icon or btn)
		cd:SetDrawEdge(false)
		cd:SetDrawBling(false)
		cd:SetDrawSwipe(true)
		cd:SetSwipeColor(0, 0, 0, 0.8)
		btn.cooldownFrame = cd
	end

	btn.cooldownFrame:SetCooldown(start, duration)

	-- Desaturate the icon
	if btn.icon then
		btn.icon:SetDesaturated(true)
	end
end

-- Clear cooldown display on a caller button
function SP:ClearCallerButtonCooldown(btn)
	if btn.cooldownFrame then
		btn.cooldownFrame:Clear()
	end

	-- Restore icon color
	if btn.icon then
		btn.icon:SetDesaturated(false)
	end
end

-- Update opacity of caller button frame
function SP:UpdateCallerButtonOpacity()
	if self.callerButtonFrame then
		local opacity = self.opt.raidCDButtonOpacity or 1.0
		self.callerButtonFrame:SetAlpha(opacity)
	end
end

-- Update scale of caller button frame
function SP:UpdateCallerButtonScale()
	if self.callerButtonFrame then
		local scale = self.opt.raidCDButtonScale or 1.0
		self.callerButtonFrame:SetScale(scale)
	end
end
