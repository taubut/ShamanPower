ShamanPower = LibStub("AceAddon-3.0"):NewAddon("ShamanPower", "AceConsole-3.0", "AceEvent-3.0", "AceBucket-3.0", "AceTimer-3.0")

ShamanPower.isVanilla = (_G.WOW_PROJECT_ID == _G.WOW_PROJECT_CLASSIC)
ShamanPower.isBCC = (_G.WOW_PROJECT_ID == _G.WOW_PROJECT_BURNING_CRUSADE_CLASSIC)
ShamanPower.isWrath = (_G.WOW_PROJECT_ID == _G.WOW_PROJECT_WRATH_CLASSIC)

local L = LibStub("AceLocale-3.0"):GetLocale("ShamanPower", true)
if not L then
	L = setmetatable({}, {__index = function(t, k) return k end})
end
local LSM3 = LibStub("LibSharedMedia-3.0")
local AceGUI = LibStub("AceGUI-3.0")
local LUIDDM = LibStub("LibUIDropDownMenu-4.0")

local LCD = (ShamanPower.isVanilla) and LibStub("LibClassicDurations", true)
local UnitAura = LCD and LCD.UnitAuraWrapper or UnitAura

local tinsert = table.insert
local tremove = table.remove
local twipe = table.wipe
local tsort = table.sort
local strfind = string.find
local strsub = string.sub
local format = string.format

-- Pre-built number strings for 0-20 (avoids tostring() garbage for charges/counts)
local NumberStrings = {}
for i = 0, 20 do
	NumberStrings[i] = tostring(i)
end

-- Pre-built minute strings "0m" to "60m" for weapon imbue timer (avoids concat garbage)
local MinuteStrings = {}
for i = 0, 60 do
	MinuteStrings[i] = i .. "m"
end

-- Shaman tracking tables by element
local EarthShamans, FireShamans, WaterShamans, AirShamans = {}, {}, {}, {}
local classlist, classes = {}, {}

-- Pre-initialize classes subtables to avoid garbage generation
-- (avoids creating new tables every UpdateRoster call)
for i = 1, 4 do
	classes[i] = {}
end

ShamanPower.player = UnitName("player")
ShamanPower_Talents = {}
ShamanPower_Assignments = {}
ShamanPower_WeaponAssignments = {}
ShamanPower_EarthShieldAssignments = {}  -- Maps shamanName -> targetName
ShamanPower_TwistAssignments = {}  -- Maps shamanName -> true/false for totem twisting

AllShamans = {}
SyncList = {}
AC_DebugEnabled = false

local initialized = false
local isShaman = false

AC_Leader = false

-- ============================================================================
-- CONSOLIDATED ONUPDATE SYSTEM
-- Instead of 10+ separate OnUpdate frames each being called every frame,
-- we use ONE master frame that manages all timed updates efficiently.
-- Uses array-based active list for fastest iteration (ipairs > pairs)
-- ============================================================================
ShamanPower.updateSystem = {
	frame = nil,
	subsystems = {},  -- {name = {interval=seconds, elapsed=0, callback=func, enabled=false}}
	activeList = {},  -- Array of enabled subsystem references for fast iteration
}

function ShamanPower:InitUpdateSystem()
	if self.updateSystem.frame then return end

	self.updateSystem.frame = CreateFrame("Frame")
	local activeList = self.updateSystem.activeList  -- Local reference for speed

	self.updateSystem.frame:SetScript("OnUpdate", function(frame, elapsed)
		-- Fast array iteration (no pairs overhead, no garbage)
		for i = 1, #activeList do
			local sys = activeList[i]
			sys.elapsed = sys.elapsed + elapsed
			if sys.elapsed >= sys.interval then
				sys.elapsed = 0
				sys.callback()
			end
		end
	end)
end

function ShamanPower:RegisterUpdateSubsystem(name, interval, callback)
	self.updateSystem.subsystems[name] = {
		name = name,
		interval = interval,
		elapsed = 0,
		callback = callback,
		enabled = false,
	}
end

function ShamanPower:EnableUpdateSubsystem(name)
	local sys = self.updateSystem.subsystems[name]
	if sys and not sys.enabled then
		sys.enabled = true
		sys.elapsed = 0
		-- Add to active list
		self.updateSystem.activeList[#self.updateSystem.activeList + 1] = sys
	end
end

function ShamanPower:DisableUpdateSubsystem(name)
	local sys = self.updateSystem.subsystems[name]
	if sys and sys.enabled then
		sys.enabled = false
		-- Remove from active list
		local activeList = self.updateSystem.activeList
		for i = #activeList, 1, -1 do
			if activeList[i].name == name then
				table.remove(activeList, i)
				break
			end
		end
	end
end

function ShamanPower:IsUpdateSubsystemEnabled(name)
	return self.updateSystem.subsystems[name] and self.updateSystem.subsystems[name].enabled
end
-- ============================================================================

-- Helper function to check if player knows a spell by name (works with any rank in Classic)
local function PlayerKnowsSpellByName(spellName)
	if not spellName then return false end
	-- GetSpellInfo with a name will return info if the player can cast it
	local name = GetSpellInfo(spellName)
	if not name then return false end
	-- Check if it's in the spellbook
	local slot = FindSpellBookSlotBySpellID(select(7, GetSpellInfo(spellName)) or 0, false)
	if slot then return true end
	-- Fallback: try to find by name in spellbook
	for i = 1, 500 do
		local bookName = GetSpellBookItemName(i, BOOKTYPE_SPELL)
		if not bookName then break end
		if bookName == spellName or bookName:find("^" .. spellName) then
			return true
		end
	end
	return false
end

-- unit tables
local party_units = {}
local raid_units = {}
local leaders = {}
local roster = {}
local raidmaintanks = {}

local classmaintanks = {}

-- Pre-allocated unit tables to avoid garbage (60 = 40 raid + pets)
local unitTables = {}
for i = 1, 60 do
	unitTables[i] = {}
end
local unitTableIndex = 0
local raidmainassists = {}

local lastMsg = ""
local prevBuffDuration

do
	table.insert(party_units, "player")
	table.insert(party_units, "pet")

	for i = 1, MAX_PARTY_MEMBERS do
		table.insert(party_units, ("party%d"):format(i))
	end
	for i = 1, MAX_PARTY_MEMBERS do
		table.insert(party_units, ("partypet%d"):format(i))
	end

	for i = 1, MAX_RAID_MEMBERS do
		table.insert(raid_units, ("raid%d"):format(i))
	end
	for i = 1, MAX_RAID_MEMBERS do
		table.insert(raid_units, ("raidpet%d"):format(i))
	end
end

ShamanPower.Credits1 = "ShamanPower - Shaman Totem Coordination"
ShamanPower.Credits2 = "Based on PallyPower by Aznamir, Dyaxler, Es, gallantron. Adapted by taubut."

function ShamanPower:Debug(s)
	if (AC_DebugEnabled) then
		DEFAULT_CHAT_FRAME:AddMessage("[PP] " .. tostring(s), 1, 0, 0)
	end
end

-------------------------------------------------------------------
-- Ace Framework Events
-------------------------------------------------------------------
function ShamanPower:OnInitialize()
	-- Initialize the consolidated update system (single OnUpdate for all timed updates)
	self:InitUpdateSystem()

	-- Migrate old AncestralCouncil settings to ShamanPower
	if AncestralCouncilDB and not ShamanPowerDB then
		ShamanPowerDB = AncestralCouncilDB
		print("|cff00ff00ShamanPower:|r Migrated settings from AncestralCouncil.")
	end

	-- Migrate old assignments table
	if ShamanPower_Assignments == nil and AncestralCouncil_Assignments then
		ShamanPower_Assignments = AncestralCouncil_Assignments
	end

	if select(2, UnitClass("player")) == "SHAMAN" then
		self.db = LibStub("AceDB-3.0"):New("ShamanPowerDB", SHAMANPOWER_DEFAULT_VALUES, "Default")
	else
		self.db = LibStub("AceDB-3.0"):New("ShamanPowerDB", SHAMANPOWER_OTHER_VALUES, "Other")
		self.db:SetProfile("Other")
	end

	self.db.RegisterCallback(self, "OnProfileChanged", "OnProfileChanged")
	self.db.RegisterCallback(self, "OnProfileCopied", "OnProfileChanged")
	self.db.RegisterCallback(self, "OnProfileReset", "OnProfileChanged")

	self.opt = self.db.profile

	-- Sync twist setting from shared assignments table (source of truth for sync)
	if ShamanPower_TwistAssignments and ShamanPower_TwistAssignments[self.player] ~= nil then
		self.opt.enableTotemTwisting = ShamanPower_TwistAssignments[self.player]
	elseif self.opt.enableTotemTwisting then
		-- Initialize assignments table from local opt if it exists
		ShamanPower_TwistAssignments = ShamanPower_TwistAssignments or {}
		ShamanPower_TwistAssignments[self.player] = self.opt.enableTotemTwisting
	end

	self.options.args.profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db)

	LibStub("AceConfig-3.0"):RegisterOptionsTable("ShamanPower", self.options, {"sp", "shamanpower"})
	self.optionsFrame = LibStub("AceConfigDialog-3.0"):AddToBlizOptions("ShamanPower", "ShamanPower")

	LSM3:Register("background", "None", "Interface\\Tooltips\\UI-Tooltip-Background")
	LSM3:Register("background", "Banto", "Interface\\AddOns\\ShamanPower\\Skins\\Banto")
	LSM3:Register("background", "BantoBarReverse", "Interface\\AddOns\\ShamanPower\\Skins\\BantoBarReverse")
	LSM3:Register("background", "Glaze", "Interface\\AddOns\\ShamanPower\\Skins\\Glaze")
	LSM3:Register("background", "Gloss", "Interface\\AddOns\\ShamanPower\\Skins\\Gloss")
	LSM3:Register("background", "Healbot", "Interface\\AddOns\\ShamanPower\\Skins\\Healbot")
	LSM3:Register("background", "oCB", "Interface\\AddOns\\ShamanPower\\Skins\\oCB")
	LSM3:Register("background", "Smooth", "Interface\\AddOns\\ShamanPower\\Skins\\Smooth")

	self.zone = GetRealZoneText()

	self:ScanInventory()
	self:CreateLayout()

	if self.opt.skin then
		self:ApplySkin(self.opt.skin)
	end

	self.AutoBuffedList = {}
	self.PreviousAutoBuffedUnit = nil
	self.menuFrame = LUIDDM:Create_UIDropDownMenu("ShamanPowerMenuFrame", UIParent)

	if not ShamanPowerConfigFrame then
		local ConfigFrame = AceGUI:Create("Frame")
		ConfigFrame:EnableResize(false)
		LibStub("AceConfigDialog-3.0"):SetDefaultSize("ShamanPower", 625, 580)
		LibStub("AceConfigDialog-3.0"):Open("ShamanPower", ConfigFrame)
		ConfigFrame:Hide()
		_G["ShamanPowerConfigFrame"] = ConfigFrame.frame
		table.insert(UISpecialFrames, "ShamanPowerConfigFrame")
	end

	self.MinimapIcon = LibStub("LibDBIcon-1.0")
	self.LDB =
		LibStub("LibDataBroker-1.1"):NewDataObject(
		"ShamanPower",
		{
			["type"] = "data source",
			["text"] = "ShamanPower",
			["icon"] = "Interface\\Icons\\ClassIcon_Shaman",
			["OnTooltipShow"] = function(tooltip)
				if self.opt.ShowTooltips then
					tooltip:SetText(SHAMANPOWER_NAME)
					tooltip:AddLine(L["MINIMAP_ICON_TOOLTIP"])
					tooltip:Show()
				end
			end,
			["OnClick"] = function(_, button)
				local playerIsShaman = select(2, UnitClass("player")) == "SHAMAN"

				if (button == "LeftButton") then
					if playerIsShaman then
						ShamanPowerBlessings_Toggle()
					else
						-- Non-shaman: open SPRange
						ShamanPower:InitSPRange()
						if not ShamanPower.spRangeFrame then
							ShamanPower:CreateSPRangeFrame()
						end
						ShamanPower:ShowSPRangeConfig()
					end
				elseif (button == "MiddleButton") then
					-- Middle click: open /sp totems (for non-shamans, or anyone)
					ShamanPowerBlessings_Toggle()
				else
					self:OpenConfigWindow()
				end
			end
		}
	)
	self.MinimapIcon:Register("ShamanPower", self.LDB, self.opt.minimap)
	C_Timer.After(
		2.0,
		function()
			ShamanPowerMinimapIcon_Toggle()
		end
	)

	if self.isVanilla then
		LCD:Register("ShamanPower")
	end

	-- the transition from TBC Classic to Wrath Classic has caused some errors for players with SavedVariables values intended for the 2.5.4 clients and earlier
	if self.isWrath and not self.opt.WrathTransition then
		ShamanPower:Purge()

		self.opt.WrathTransition = true
	end

	if not ShamanPower_SavedPresets then
		ShamanPower_SavedPresets = {}
		ShamanPower_SavedPresets["ShamanPower_Assignments"] = {[0] = {}}
		ShamanPower_SavedPresets["ShamanPower_NormalAssignments"] = {[0] = {}}
		ShamanPower_SavedPresets["ShamanPower_AuraAssignments"] = {[0] = {}}
	end

	-- Initialize assignment tables if they don't exist
	if not ShamanPower_Assignments then
		ShamanPower_Assignments = {}
	end
	if not ShamanPower_NormalAssignments then
		ShamanPower_NormalAssignments = {}
	end
	if not ShamanPower_AuraAssignments then
		ShamanPower_AuraAssignments = {}
	end
	if not ShamanPower_WeaponAssignments then
		ShamanPower_WeaponAssignments = {}
	end
	if not ShamanPower_EarthShieldAssignments then
		ShamanPower_EarthShieldAssignments = {}
	end
	if not ShamanPower_TwistAssignments then
		ShamanPower_TwistAssignments = {}
	end

	local h = _G["ShamanPowerFrame"]
	h:ClearAllPoints()
	local x = self.opt.display.offsetX
	local y = self.opt.display.offsetY
	if x and y and x ~= 0 and y ~= 0 then
		-- Restore absolute position (CENTER of frame at saved x,y screen coordinates)
		h:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
	else
		-- Default to center of screen if no saved position
		h:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	end

	-- Optimize BlessingsFrame: Only run OnUpdate when frame is visible
	-- The XML defines an OnUpdate that was running every frame even when hidden
	local blessingsFrame = _G["ShamanPowerBlessingsFrame"]
	if blessingsFrame then
		-- Store the original OnUpdate function
		local originalOnUpdate = function(frame, elapsed)
			ShamanPowerBlessingsGrid_Update(frame, elapsed)
		end

		-- Disable OnUpdate by default (frame starts hidden)
		blessingsFrame:SetScript("OnUpdate", nil)

		-- Enable OnUpdate only when frame is shown
		blessingsFrame:HookScript("OnShow", function(frame)
			frame:SetScript("OnUpdate", originalOnUpdate)
		end)

		-- Disable OnUpdate when frame is hidden
		blessingsFrame:HookScript("OnHide", function(frame)
			frame:SetScript("OnUpdate", nil)
		end)
	end

end

-- Helper function to ensure nested tables exist in the profile for proper saving
-- AceDB returns default tables when profile doesn't have the key, but setting
-- values on default tables doesn't persist to the profile
-- Deep copy a table (for nested structures like position tables)
local function DeepCopy(orig)
	if type(orig) ~= "table" then return orig end
	local copy = {}
	for k, v in pairs(orig) do
		copy[k] = DeepCopy(v)
	end
	return copy
end

function ShamanPower:EnsureProfileTable(tableName)
	if not rawget(self.db.profile, tableName) then
		-- Create a deep copy of the defaults in the profile
		local defaults = SHAMANPOWER_DEFAULT_VALUES.profile[tableName]
		if defaults then
			self.db.profile[tableName] = DeepCopy(defaults)
		else
			self.db.profile[tableName] = {}
		end
	end
end

-- Helper to save frame position to profile (ensures display table exists)
-- Saves absolute screen position for exact restore
function ShamanPower:SaveFramePosition(frame)
	self:EnsureProfileTable("display")
	-- Save the frame's center as absolute screen coordinates
	local x, y = frame:GetCenter()
	self.db.profile.display.offsetX = x
	self.db.profile.display.offsetY = y
end

function ShamanPower:OnEnable()
	isShaman = select(2, UnitClass("player")) == "SHAMAN"

	self.opt.enable = true
	self:ScanTalents()
	self:ScanSpells()
	self:ScanCooldowns()
	self:RegisterEvent("CHAT_MSG_ADDON")
	self:RegisterEvent("ZONE_CHANGED")
	self:RegisterEvent("ZONE_CHANGED_NEW_AREA")
	self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
	self:RegisterEvent("UNIT_SPELLCAST_SENT")  -- For ES cast tracking
	self:RegisterEvent("UNIT_AURA")  -- For ES charge updates
	self:RegisterEvent("GROUP_JOINED")
	self:RegisterEvent("GROUP_LEFT")
	self:RegisterEvent("PLAYER_ROLES_ASSIGNED")
	self:RegisterEvent("UPDATE_BINDINGS", "BindKeys")
	self:RegisterEvent("CHANNEL_UI_UPDATE", "ReportChannels")
	self:RegisterEvent("CHARACTER_POINTS_CHANGED", "OnTalentsChanged")  -- Classic talent changes
	self:RegisterEvent("PLAYER_TALENT_UPDATE", "OnTalentsChanged")  -- Talent updates
	self:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED", "OnTalentsChanged")  -- Wrath dual spec switch
	self:RegisterBucketEvent("SPELLS_CHANGED", 1, "SPELLS_CHANGED")
	self:RegisterBucketEvent("PLAYER_ENTERING_WORLD", 2, "PLAYER_ENTERING_WORLD")
	self:RegisterBucketEvent({"GROUP_ROSTER_UPDATE", "PLAYER_REGEN_ENABLED", "UNIT_PET"}, 1, "UpdateRoster")
	self:RegisterBucketEvent({"GROUP_ROSTER_UPDATE"}, 1, "UpdateAllShamans")
	-- Reset Drop All castsequence when combat ends
	self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombatEnd")
	if isShaman then
		self:ScheduleRepeatingTimer(self.ScanInventory, 60, self)
		self.ButtonsUpdate(self)
		-- Create Earth Shield macro button and macro for keybinding
		self:UpdateEarthShieldMacroButton()
		self:CreateEarthShieldMacro()
	end
	self:BindKeys()
	self:UpdateRoster()
end

-- Called when combat ends - reset Drop All castsequence
function ShamanPower:OnCombatEnd()
	-- Force rebuild of the Drop All macro to reset the castsequence
	self.dropAllLastMacro = ""
	self:UpdateDropAllButton()
end

-- Create a macro for Earth Shield that users can keybind
function ShamanPower:CreateEarthShieldMacro()
	local macroName = "AC EarthShield"
	local macroBody = "/click ShamanPowerESMacroBtn"
	-- CreateMacro needs just the icon name, not the full path
	local macroIcon = "Spell_Nature_SkinOfEarth"

	-- Check if macro already exists
	local existingIndex = GetMacroIndexByName(macroName)
	if existingIndex and existingIndex > 0 then
		-- Macro exists, no need to recreate
		return
	end

	-- Check if we have room for a new macro
	local numGlobal, numPerChar = GetNumMacros()
	if numGlobal >= MAX_ACCOUNT_MACROS then
		-- Try character-specific macros
		if numPerChar >= MAX_CHARACTER_MACROS then
			-- No room, silently fail (user can manually create it)
			return
		end
		-- Create as character-specific macro
		CreateMacro(macroName, macroIcon, macroBody, true)
	else
		-- Create as global macro
		CreateMacro(macroName, macroIcon, macroBody, false)
	end
end

function ShamanPower:OnDisable()
	self.opt.enable = false
	for i = 1, SHAMANPOWER_MAXCLASSES do
		classlist[i] = 0
		classes[i] = {}
	end
	self:UpdateRoster()
	self.auraButton:Hide()
	self.rfButton:Hide()
	self.autoButton:Hide()
	ShamanPowerAnchor:Hide()
	self:UnbindKeys()
	self:UnregisterAllEvents()
	self:UnregisterAllBuckets()
end

function ShamanPower:OnProfileChanged()
	-- Clean up all popped-out frames from the old profile first
	if self.poppedOutFrames then
		for key, frame in pairs(self.poppedOutFrames) do
			if frame then
				-- Reparent buttons back before hiding frame
				if frame.totemButton then
					frame.totemButton:SetParent(UIParent)
				end
				if frame.cooldownButton and self.cooldownBar then
					frame.cooldownButton:SetParent(self.cooldownBar)
				end
				if frame.button then
					frame.button:Hide()
					frame.button:SetParent(nil)
				end
				frame:Hide()
				frame:SetParent(nil)
			end
		end
		wipe(self.poppedOutFrames)
	end

	self.opt = self.db.profile

	-- Reset frame positions when profile changes (prevents off-screen issues)
	if not InCombatLockdown() then
		local h = _G["ShamanPowerFrame"]
		if h then
			h:ClearAllPoints()
			local x = self.opt.display and self.opt.display.offsetX
			local y = self.opt.display and self.opt.display.offsetY
			if x and y and x ~= 0 and y ~= 0 then
				-- Restore absolute position (CENTER of frame at saved x,y screen coordinates)
				h:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
			else
				-- Default to center of screen if no saved position
				h:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
			end
		end

		-- Apply cooldown bar position from new profile (force reposition to use profile's saved position)
		if self.cooldownBar then
			self.opt.cooldownBarPosX = self.opt.cooldownBarPosX or 0
			self.opt.cooldownBarPosY = self.opt.cooldownBarPosY or -50
			self.opt.cooldownBarPoint = self.opt.cooldownBarPoint or "CENTER"
			self.opt.cooldownBarRelPoint = self.opt.cooldownBarRelPoint or "CENTER"
			self:UpdateCooldownBarPosition(true)  -- true = force reposition from profile
		end

		-- Reset assignment window position
		local c = _G["ShamanPowerBlessingsFrame"]
		if c then
			c:ClearAllPoints()
			c:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
		end
	end

	self:ApplySkin()
	self:UpdateLayout()
	self:UpdateRoster()
	self:ApplyAllOpacity()

	-- Restore popped-out trackers from the new profile
	C_Timer.After(0.5, function()
		self:RestorePoppedOutTrackers()
	end)
	--self:Debug("Profile changed, positions restored from profile.")
end

function ShamanPower:BindKeys()
	local key1 = GetBindingKey("SHAMANPOWER_AUTOKEY1")
	local key2 = GetBindingKey("SHAMANPOWER_AUTOKEY2")
	if key1 then
		SetOverrideBindingClick(self.autoButton, false, key1, "ShamanPowerAuto", "Hotkey1")
	end
	if key2 then
		SetOverrideBindingClick(self.autoButton, false, key2, "ShamanPowerAuto", "Hotkey2")
	end
end

function ShamanPower:UnbindKeys()
	ClearOverrideBindings(self.autoButton)
end

-------------------------------------------------------------------
-- Config Window Functionality
-------------------------------------------------------------------
function ShamanPower:Purge()
	ShamanPower_Assignments = nil
	ShamanPower_NormalAssignments = nil
	ShamanPower_AuraAssignments = nil
	ShamanPower_Assignments = {}
	ShamanPower_NormalAssignments = {}
	ShamanPower_AuraAssignments = {}

	ShamanPower_SavedPresets = nil
end

function ShamanPower:Reset()
	if InCombatLockdown() then return end

	-- Reset totem bar to center and clear saved position
	local h = _G["ShamanPowerFrame"]
	h:ClearAllPoints()
	h:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	self:EnsureProfileTable("display")
	self.opt.display.offsetX = 0
	self.opt.display.offsetY = 0

	-- Reset visual settings to defaults
	self.opt.buffscale = 0.9
	self.opt.border = "Blizzard Tooltip"
	self.opt.layout = "Vertical"
	self.opt.skin = "Smooth"
	self.opt.configscale = 0.9

	-- Reset assignment window to center
	local c = _G["ShamanPowerBlessingsFrame"]
	c:ClearAllPoints()
	c:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

	self:ApplySkin()
	self:UpdateLayout()
end

function ShamanPower:OpenConfigWindow()
	if ShamanPowerBlessingsFrame:IsVisible() then
		ShamanPowerBlessingsFrame:Hide()
		LUIDDM:CloseDropDownMenus()
	end
	if not ShamanPowerConfigFrame:IsShown() then
		ShamanPowerConfigFrame:Show()
		PlaySound(SOUNDKIT.IG_SPELLBOOK_OPEN)
	else
		ShamanPowerConfigFrame:Hide()
		PlaySound(SOUNDKIT.IG_SPELLBOOK_CLOSE)
	end
end

local function tablecopy(tbl)
	if type(tbl) ~= "table" then return tbl end
	local t = {}
	for i,v in pairs(tbl) do
	  t[i] = tablecopy(v)
	end
	return t
  end

local function safeget(t,k) -- always return nil or t[k] if at least t is a table / Treeston
	return t and t[k]    
end

function ShamanPowerBlessings_Clear()
	if InCombatLockdown() then return end

	if GetNumGroupMembers() > 0 and ShamanPower:CheckLeader(ShamanPower.player) then
		-- Leader clears everyone and broadcasts
		ShamanPower:ClearAssignments(ShamanPower.player)
		ShamanPower:SendMessage("CLEAR")
	else
		-- Non-leader or solo: clear own assignments
		ShamanPower:ClearAssignments(ShamanPower.player)
		if GetNumGroupMembers() > 0 then
			ShamanPower:SendSelf()
		end
	end
	ShamanPower:UpdateLayout()
	ShamanPower:UpdateRoster()
end

function ShamanPowerBlessings_Refresh()
	ShamanPower:Debug("ShamanPowerBlessings_Refresh")
	ShamanPower:ScanSpells()
	ShamanPower:ScanCooldowns()
	ShamanPower:ScanInventory()
	if GetNumGroupMembers() > 0 then
		ShamanPower:SendSelf()
		ShamanPower:SendMessage("REQ")
	end
	ShamanPower:UpdateLayout()
	ShamanPower:UpdateRoster()
end

function ShamanPowerBlessings_Toggle()
	if ShamanPower.configFrame and ShamanPower.configFrame:IsShown() then
		ShamanPower.configFrame:Hide()
	end
	if ShamanPowerBlessingsFrame:IsVisible() then
		ShamanPowerBlessingsFrame:Hide()
		LUIDDM:CloseDropDownMenus()
		PlaySound(SOUNDKIT.IG_SPELLBOOK_CLOSE)
	else
		local c = _G["ShamanPowerBlessingsFrame"]
		c:ClearAllPoints()
		c:SetPoint("CENTER", "UIParent", "CENTER", 0, 0)
		ShamanPower:ScanSpells()
		ShamanPower:ScanCooldowns()
		ShamanPower:ScanInventory()
		if GetNumGroupMembers() > 0 then
			ShamanPower:SendSelf()
			ShamanPower:SendMessage("REQ")
		end
		-- Setup Tools dropdown on first show
		ShamanPower:SetupToolsDropdown()
		ShamanPowerBlessingsFrame:Show()
		PlaySound(SOUNDKIT.IG_SPELLBOOK_OPEN)
		table.insert(UISpecialFrames, "ShamanPowerBlessingsFrame")
	end
end

function ShamanPowerMinimapIcon_Toggle()
	if (ShamanPower.opt.minimap.show == false) then
		ShamanPower.MinimapIcon:Hide("ShamanPower")
	else
		ShamanPower.MinimapIcon:Show("ShamanPower")
	end
end

-- Setup Tools dropdown to replace Totem Range, Raid CDs, Options buttons
function ShamanPower:SetupToolsDropdown()
	if self.toolsDropdownSetup then return end
	self.toolsDropdownSetup = true

	local frame = _G["ShamanPowerBlessingsFrame"]
	if not frame then return end

	-- Hide the old buttons
	local totemRangeBtn = _G["ShamanPowerBlessingsFrameTotemRange"]
	local raidCDsBtn = _G["ShamanPowerBlessingsFrameRaidCDs"]
	local optionsBtn = _G["ShamanPowerBlessingsFrameOptions"]

	if totemRangeBtn then totemRangeBtn:Hide() end
	if raidCDsBtn then raidCDsBtn:Hide() end
	if optionsBtn then optionsBtn:Hide() end

	-- Create Tools dropdown button
	local toolsBtn = CreateFrame("Button", "ShamanPowerBlessingsFrameTools", frame, "UIPanelButtonTemplate")
	toolsBtn:SetSize(60, 22)
	toolsBtn:SetText("Tools")

	-- Position it where Options was (left of Auto-Assign)
	local autoAssignBtn = _G["ShamanPowerBlessingsFrameAutoAssign"]
	if autoAssignBtn then
		toolsBtn:SetPoint("BOTTOMRIGHT", autoAssignBtn, "BOTTOMLEFT", -4, 0)
	end

	-- Create dropdown menu frame
	local dropdownMenu = CreateFrame("Frame", "ShamanPowerToolsDropdownMenu", UIParent, "UIDropDownMenuTemplate")

	toolsBtn:SetScript("OnClick", function()
		LUIDDM:ToggleDropDownMenu(1, nil, dropdownMenu, toolsBtn, 0, 0)
	end)

	toolsBtn:SetScript("OnEnter", function(self)
		if ShamanPower.opt.ShowTooltips then
			GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
			GameTooltip:SetText("Open tools menu")
			GameTooltip:Show()
		end
	end)

	toolsBtn:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	-- Initialize the dropdown
	LUIDDM:UIDropDownMenu_Initialize(dropdownMenu, function(self, level)
		local info = LUIDDM:UIDropDownMenu_CreateInfo()

		-- Totem Range
		info.text = "Totem Range"
		info.notCheckable = true
		info.func = function()
			ShamanPower:InitSPRange()
			if not ShamanPower.spRangeFrame then
				ShamanPower:CreateSPRangeFrame()
			end
			ShamanPower:ShowSPRangeConfig()
		end
		LUIDDM:UIDropDownMenu_AddButton(info, level)

		-- Raid CDs
		info.text = "Raid CDs"
		info.notCheckable = true
		info.func = function()
			ShamanPower:ToggleRaidCooldownPanel()
		end
		LUIDDM:UIDropDownMenu_AddButton(info, level)

		-- ES Tracker
		info.text = "ES Tracker"
		info.notCheckable = true
		info.func = function()
			ShamanPower:ToggleESTracker()
		end
		LUIDDM:UIDropDownMenu_AddButton(info, level)

		-- Separator
		info.text = ""
		info.disabled = true
		info.notCheckable = true
		LUIDDM:UIDropDownMenu_AddButton(info, level)

		-- Options
		info.text = "Options"
		info.disabled = false
		info.notCheckable = true
		info.func = function()
			ShamanPower:OpenConfigWindow()
		end
		LUIDDM:UIDropDownMenu_AddButton(info, level)
	end, "MENU")
end

function ShamanPowerBlessings_ShowCredits(self)
	if ShamanPower.opt.ShowTooltips then
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(ShamanPower.Credits1, 1, 1, 1)
		GameTooltip:AddLine(ShamanPower.Credits2, 1, 1, 1)
		GameTooltip:Show()
	end
end

function GetNormalBlessings(pname, class, tname)
	if ShamanPower_NormalAssignments[pname] and ShamanPower_NormalAssignments[pname][class] then
		local blessing = ShamanPower_NormalAssignments[pname][class][tname]
		if blessing then
			return tostring(blessing)
		else
			return "0"
		end
	end
end

function SetNormalBlessings(pname, class, tname, value)
	if not ShamanPower_NormalAssignments[pname] then
		ShamanPower_NormalAssignments[pname] = {}
	end
	if not ShamanPower_NormalAssignments[pname][class] then
		ShamanPower_NormalAssignments[pname][class] = {}
	end
	if value == 0 then
		value = nil
	end
	ShamanPower_NormalAssignments[pname][class][tname] = value
	local msgQueue
	msgQueue =
		C_Timer.NewTimer(
		2.0,
		function()
			if ShamanPower_NormalAssignments and ShamanPower_NormalAssignments[pname] and ShamanPower_NormalAssignments[pname][class] and ShamanPower_NormalAssignments[pname][class][tname] then
				ShamanPower:SendNormalBlessings(pname, class, tname)
				ShamanPower:UpdateLayout()
				msgQueue:Cancel()
			end
		end
	)
end

-- sends blessing to tname as previously set in ShamanPower_NormalAssignments[pname]...
function ShamanPower:SendNormalBlessings(pname, class, tname)
	local value = safeget(safeget(safeget(ShamanPower_NormalAssignments, pname), class), tname)
	if value == nil then value = 0 end
	self:SendMessage("NASSIGN " .. pname .. " " .. class .. " " .. tname .. " " .. value)
end

function ShamanPowerGrid_NormalBlessingMenu(btn, mouseBtn, pname, class)
	if InCombatLockdown() then return end

	if (mouseBtn == "LeftButton") then

		local menu = {}

		local shortname = strsplit("%-", pname)

		tinsert(menu, {text = "|cffffffff" .. shortname .. "|r " .. L["can be assigned"], isTitle = true, isNotRadio = true, notCheckable = 1})
		tinsert(menu, {text = L["a Normal Blessing from:"], isTitle = true, isNotRadio = true, notCheckable = 1})

		local pre, suf
		for pally in pairs(AllShamans) do
			local pallyMenu = {}
			local control = ShamanPower:CanControl(pally)
			if not control then
				pre = "|cff999999"
				suf = "|r"
			else
				pre = ""
				suf = ""
			end

			tinsert(pallyMenu, {
				text = format("%s%s%s", pre, "(none)", suf),
				checked = function() if GetNormalBlessings(pally, class, pname) == "0" then return true end end,
				func = function() LUIDDM:CloseDropDownMenus(); SetNormalBlessings(pally, class, pname, 0) end
			})

			for index, blessing in ipairs(ShamanPower.Spells) do
				if ShamanPower:CanBuff(pally, index) then
					local unitID = ShamanPower:GetUnitIdByName(pname)
					if ShamanPower:CanBuffBlessing(index, 0, unitID, true) then
						tinsert(pallyMenu, {
							text = format("%s%s%s", pre, blessing, suf),
							checked = function() if GetNormalBlessings(pally, class, pname) == tostring(index) then return true end end,
							func = function() LUIDDM:CloseDropDownMenus(); if control then SetNormalBlessings(pally, class, pname, index + 0) end end
						})
					end
				end
			end

			local shortname = strsplit("%-", pally)

			tinsert(menu, {
				text = format("%s%s%s", pre, shortname, suf),
				hasArrow = true,
				menuList = pallyMenu,
				checked = function()
					if ShamanPower_NormalAssignments[pally] and ShamanPower_NormalAssignments[pally][class] and ShamanPower_NormalAssignments[pally][class][pname] then
						return true
					else
						SetNormalBlessings(pally, class, pname, 0)
					end
				end
			})
		end

		tinsert(menu, {text = _G.CANCEL, func = function() end, isNotRadio = true, notCheckable = 1})

		LUIDDM:EasyMenu(menu, ShamanPower.menuFrame, "cursor", 0 , 0, "MENU")

	elseif (mouseBtn == "RightButton") then
		for pally in pairs(AllShamans) do
			if ShamanPower_NormalAssignments[pally] and ShamanPower_NormalAssignments[pally][class] and ShamanPower_NormalAssignments[pally][class][pname] then
				ShamanPower_NormalAssignments[pally][class][pname] = nil
			end
			ShamanPower:SendNormalBlessings(pally, class, pname)
			ShamanPower:UpdateLayout()
		end
	end
end

function ShamanPowerPlayerButton_OnClick(btn, mouseBtn)
	if InCombatLockdown() then return end

	local _, _, class, pnum = strfind(btn:GetName(), "ShamanPowerBlessingsFrameClassGroup(.+)PlayerButton(.+)")
	class = tonumber(class)
	pnum = tonumber(pnum)
	local pname = classes[class][pnum].name

	ShamanPowerGrid_NormalBlessingMenu(btn, mouseBtn, pname, class)
end

function ShamanPowerPlayerButton_OnMouseWheel(btn, arg1)
	if InCombatLockdown() then return end

	local _, _, class, pnum = strfind(btn:GetName(), "ShamanPowerBlessingsFrameClassGroup(.+)PlayerButton(.+)")
	class = tonumber(class)
	pnum = tonumber(pnum)
	local pname = classes[class][pnum].name
	ShamanPower:PerformPlayerCycle(arg1, pname, class)
end

function ShamanPowerGridButton_OnClick(btn, mouseBtn)
	if InCombatLockdown() then return end

	local _, _, pnum, class = strfind(btn:GetName(), "ShamanPowerBlessingsFramePlayer(.+)Class(.+)")
	class = tonumber(class)
	pnum = tonumber(pnum)
	local pname = _G["ShamanPowerBlessingsFramePlayer" .. pnum .. "Name"]:GetText()
	if not ShamanPower:CanControl(pname) then
		return false
	end
	if (mouseBtn == "RightButton") then
		-- Right-click cycles backward through totems
		ShamanPower:PerformCycleBackwards(pname, class)
	else
		-- Left-click cycles forward through totems
		ShamanPower:PerformCycle(pname, class)
	end
end

function ShamanPowerGridButton_OnMouseWheel(btn, arg1)
	if InCombatLockdown() then return end

	local _, _, pnum, class = strfind(btn:GetName(), "ShamanPowerBlessingsFramePlayer(.+)Class(.+)")
	class = tonumber(class)
	pnum = tonumber(pnum)
	local pname = _G["ShamanPowerBlessingsFramePlayer" .. pnum .. "Name"]:GetText()
	if not ShamanPower:CanControl(pname) then
		return false
	end
	if (arg1 == -1) then --mouse wheel down
		ShamanPower:PerformCycle(pname, class)
	else
		ShamanPower:PerformCycleBackwards(pname, class)
	end
end

function ShamanPowerBlessingsFrame_MouseUp()
	if (ShamanPowerBlessingsFrame.isMoving) then
		ShamanPowerBlessingsFrame:StopMovingOrSizing()
		ShamanPowerBlessingsFrame.isMoving = false
	end
end

function ShamanPowerBlessingsFrame_MouseDown(self, button)
	if (((not ShamanPowerBlessingsFrame.isLocked) or (ShamanPowerBlessingsFrame.isLocked == 0)) and (button == "LeftButton")) then
		ShamanPowerBlessingsFrame:StartMoving()
		ShamanPowerBlessingsFrame:SetClampedToScreen(true)
		ShamanPowerBlessingsFrame.isMoving = true
	end
end

function ShamanPowerBlessingsGrid_Update(self, elapsed)
	-- OnUpdate only runs when frame is visible (controlled by OnShow/OnHide hooks)
	if not initialized then return end

	-- Throttle to 5 updates per second
	self.gridUpdateElapsed = (self.gridUpdateElapsed or 0) + elapsed
	if self.gridUpdateElapsed < 0.2 then return end
	self.gridUpdateElapsed = 0

	-- Ensure assignment tables are initialized
	if not ShamanPower_Assignments then ShamanPower_Assignments = {} end
	if not ShamanPower_NormalAssignments then ShamanPower_NormalAssignments = {} end
	if not ShamanPower_AuraAssignments then ShamanPower_AuraAssignments = {} end

	local numShamans = 0
		local numMaxClass = 0
		-- Hide all ClassGroups and AuraGroups - Shamans don't need these
		-- Totems affect the whole party, not individual players
		for i = 1, 9 do  -- Hide all possible ClassGroups
			local fname = "ShamanPowerBlessingsFrameClassGroup" .. i
			local classGroup = _G[fname]
			if classGroup then
				classGroup:Hide()
			end
		end
		-- Hide AuraGroup (Shamans don't have auras like Paladins)
		local auraGroup = _G["ShamanPowerBlessingsFrameAuraGroup1"]
		if auraGroup then
			auraGroup:Hide()
		end
		ShamanPowerBlessingsFrame:SetScale(ShamanPower.opt.configscale)
		for i, name in pairs(SyncList) do
			local fname = "ShamanPowerBlessingsFramePlayer" .. i
			local playerFrame = _G[fname]
			local SkillInfo = AllShamans[name]
			local BuffInfo = ShamanPower_Assignments[name]
			if not BuffInfo then BuffInfo = {} end
			local NormalBuffInfo = ShamanPower_NormalAssignments[name]

			-- Add alternating row background for readability
			local rowBg = _G[fname .. "RowBG"]
			if not rowBg then
				rowBg = playerFrame:CreateTexture(fname .. "RowBG", "BACKGROUND")
				rowBg:SetPoint("TOPLEFT", playerFrame, "TOPLEFT", 0, 0)
				rowBg:SetPoint("BOTTOMRIGHT", playerFrame, "BOTTOMRIGHT", 0, 5)
			end
			if i % 2 == 0 then
				rowBg:SetColorTexture(1, 1, 1, 0.03)  -- Subtle light for even rows
			else
				rowBg:SetColorTexture(0, 0, 0, 0.1)  -- Subtle dark for odd rows
			end
			rowBg:Show()

			_G[fname .. "Name"]:SetText(name)
			if ShamanPower:CanControl(name) then
				_G[fname .. "Name"]:SetTextColor(1, 1, 1)
			else
				if ShamanPower:CheckLeader(name) then
					_G[fname .. "Name"]:SetTextColor(0, 1, 0)
				else
					_G[fname .. "Name"]:SetTextColor(1, 0, 0)
				end
			end
			-- Hide symbols (not needed for Shamans)
			_G[fname .. "Symbols"]:SetText("")

			-- Hide all the paladin-specific skill icons (Icon1-6, Skill1-6)
			for id = 1, 6 do
				local icon = _G[fname .. "Icon" .. id]
				local skill = _G[fname .. "Skill" .. id]
				if icon then icon:Hide() end
				if skill then skill:Hide() end
			end

			-- Hide aura icons (AIcon1-3, ASkill1-3) - Shamans don't have auras
			for id = 1, 3 do
				local aicon = _G[fname .. "AIcon" .. id]
				local askill = _G[fname .. "ASkill" .. id]
				if aicon then aicon:Hide() end
				if askill then askill:Hide() end
			end

			-- Show Earth Shield button if shaman has the talent
			local aura1Btn = _G[fname .. "Aura1"]
			local aura1Icon = _G[fname .. "Aura1Icon"]
			if aura1Btn and aura1Icon then
				if AllShamans[name] and AllShamans[name].hasEarthShield and ShamanPower.EarthShield then
					-- Reposition Aura1 to be before Class1 (to the left)
					aura1Btn:ClearAllPoints()
					aura1Btn:SetPoint("TOPLEFT", _G[fname], "TOPLEFT", 56, 0)

					-- Show Earth Shield icon
					aura1Icon:SetTexture(ShamanPower.EarthShield.icon)
					aura1Btn:Show()

					-- Show target name below the icon
					local targetName = ShamanPower_EarthShieldAssignments[name]
					local targetText = _G[fname .. "Aura1Text"]
					if not targetText then
						-- Create target text if it doesn't exist
						targetText = aura1Btn:CreateFontString(fname .. "Aura1Text", "OVERLAY", "GameFontHighlightSmall")
						targetText:SetPoint("TOP", aura1Icon, "BOTTOM", 0, -2)
						targetText:SetWidth(60)
					end
					if targetName then
						local shortName = Ambiguate(targetName, "short")
						targetText:SetText(shortName)
						targetText:SetTextColor(0, 1, 0)  -- Green for assigned
					else
						targetText:SetText("Click to assign")
						targetText:SetTextColor(0.5, 0.5, 0.5)  -- Gray for unassigned
					end
					targetText:Show()

					-- Update button color based on ES status
					if ShamanPower.opt then
						local btnColour = ShamanPower.opt.cBuffNeedAll  -- Red = needs assignment
						if targetName then
							btnColour = ShamanPower.opt.cBuffGood  -- Green = has target
						end
						ShamanPower:ApplyBackdrop(aura1Btn, btnColour)
					end
				else
					-- Hide if shaman doesn't have Earth Shield
					aura1Icon:SetTexture(nil)
					aura1Btn:Hide()
					local targetText = _G[fname .. "Aura1Text"]
					if targetText then targetText:Hide() end
				end
			end

			-- Create or update Twist checkbox for this shaman
			local twistCheck = _G[fname .. "TwistCheck"]
			if not twistCheck then
				twistCheck = CreateFrame("CheckButton", fname .. "TwistCheck", playerFrame, "UICheckButtonTemplate")
				twistCheck:SetSize(20, 20)
				twistCheck:SetPoint("TOPLEFT", playerFrame, "TOPLEFT", 0, -32)
				twistCheck.text = twistCheck:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
				twistCheck.text:SetPoint("LEFT", twistCheck, "RIGHT", 2, 0)
				twistCheck.text:SetText("Twist")
			end
			-- Store fname reference for the click handler
			twistCheck.shamanFrame = fname
			-- Always update the click handler (in case code changed)
			twistCheck:SetScript("OnClick", function(self)
				local frameName = self.shamanFrame
				local shamanName = _G[frameName .. "Name"]:GetText()
				local enabled = self:GetChecked()
				ShamanPower_TwistAssignments[shamanName] = enabled
				-- Send the twist assignment to other clients
				ShamanPower:SendMessage("TWIST " .. shamanName .. " " .. (enabled and "1" or "0"))
				-- If this is us, update our local setting
				if shamanName == ShamanPower.player then
					ShamanPower.opt.enableTotemTwisting = enabled
					ShamanPower:UpdateMiniTotemBar()
					ShamanPower:UpdateSPMacros()
					-- Refresh Options panel if it's open
					LibStub("AceConfigRegistry-3.0"):NotifyChange("ShamanPower")
					if enabled then
						ShamanPower:SetupTwistTimer()
					else
						ShamanPower:HideTwistTimer()
					end
				end
			end)
			twistCheck:SetScript("OnEnter", function(self)
				if ShamanPower.opt.ShowTooltips then
					GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
					GameTooltip:SetText("Totem Twisting")
					GameTooltip:AddLine("Enable Air totem twisting (Windfury + Grace of Air)", 1, 1, 1, true)
					GameTooltip:Show()
				end
			end)
			twistCheck:SetScript("OnLeave", function() GameTooltip:Hide() end)
			-- Set checkbox state from saved data
			local twistEnabled = ShamanPower_TwistAssignments[name] or false
			twistCheck:SetChecked(twistEnabled)
			twistCheck:Show()

			-- Hide cooldown icons (CIcon1-2, CSkill1-2)
			for id = 1, 2 do
				local cicon = _G[fname .. "CIcon" .. id]
				local cskill = _G[fname .. "CSkill" .. id]
				if cicon then cicon:Hide() end
				if cskill then cskill:Hide() end
			end
			for id = 1, SHAMANPOWER_MAXCLASSES do
				if BuffInfo and BuffInfo[id] and BuffInfo[id] > 0 then
					-- Use TotemIcons: id is the element, BuffInfo[id] is the totem index
					local totemIcon = ShamanPower.TotemIcons[id] and ShamanPower.TotemIcons[id][BuffInfo[id]]
					_G[fname .. "Class" .. id .. "Icon"]:SetTexture(totemIcon)
				else
					_G[fname .. "Class" .. id .. "Icon"]:SetTexture(nil)
				end
			end
			i = i + 1
			numShamans = numShamans + 1
		end
		-- Simplified height for Shaman addon (no class rows needed)
		-- Compact layout: title(24) + headers(20) + rows(55 each) + checkbox(25) + buttons(35)
		ShamanPowerBlessingsFrame:SetHeight(50 + (numShamans * 55) + 55)
		_G["ShamanPowerBlessingsFramePlayer1"]:SetPoint("TOPLEFT", 8, -48)
		for i = 1, SHAMANPOWER_MAXPERCLASS do
			local fname = "ShamanPowerBlessingsFramePlayer" .. i
			if i <= numShamans then
				_G[fname]:Show()
			else
				_G[fname]:Hide()
			end
		end
		ShamanPowerBlessingsFrameFreeAssign:SetChecked(ShamanPower.opt.freeassign)
end

function ShamanPower_StartScaling(self, button)
	if button == "RightButton" then
		ShamanPower.opt.configscale = 0.9
		local c = _G["ShamanPowerBlessingsFrame"]
		c:ClearAllPoints()
		c:SetPoint("CENTER", "UIParent", "CENTER", 0, 0)
		ShamanPowerBlessingsFrame:Show()
	end
	if button == "LeftButton" then
		self:LockHighlight()
		ShamanPower.FrameToScale = self:GetParent()
		ShamanPower.ScalingWidth = self:GetParent():GetWidth() * ShamanPower.FrameToScale:GetParent():GetEffectiveScale()
		ShamanPower.ScalingHeight = self:GetParent():GetHeight() * ShamanPower.FrameToScale:GetParent():GetEffectiveScale()
		ShamanPowerScalingFrame:Show()
	end
end

function ShamanPower_StopScaling(self, button)
	if button == "LeftButton" then
		ShamanPowerScalingFrame:Hide()
		ShamanPower.FrameToScale = nil
		self:UnlockHighlight()
	end
end

function ShamanPower_ScaleFrame(scale)
	local frame = ShamanPower.FrameToScale
	local oldscale = frame:GetScale() or 1
	local framex = (frame:GetLeft() or ShamanPowerPerOptions.XPos) * oldscale
	local framey = (frame:GetTop() or ShamanPowerPerOptions.YPos) * oldscale
	frame:SetScale(scale)
	if frame:GetName() == "ShamanPowerBlessingsFrame" then
		frame:SetClampedToScreen(true)
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", framex / scale, framey / scale)
		ShamanPower.opt.configscale = scale
	end
end

function ShamanPower_ScalingFrame_Update(self, elapsed)
	if not ShamanPower.ScalingTime then
		ShamanPower.ScalingTime = 0
	end
	ShamanPower.ScalingTime = ShamanPower.ScalingTime + elapsed
	if ShamanPower.ScalingTime > 0.25 then
		ShamanPower.ScalingTime = 0
		local frame = ShamanPower.FrameToScale
		local oldscale = frame:GetEffectiveScale()
		local framex, framey, cursorx, cursory = frame:GetLeft() * oldscale, frame:GetTop() * oldscale, GetCursorPosition()
		if ShamanPower.ScalingWidth > ShamanPower.ScalingHeight then
			if (cursorx - framex) > 32 then
				local newscale = (cursorx - framex) / ShamanPower.ScalingWidth
				if newscale < 0.5 then
					ShamanPower_ScaleFrame(0.5)
				else
					ShamanPower_ScaleFrame(newscale)
				end
			end
		else
			if (framey - cursory) > 32 then
				local newscale = (framey - cursory) / ShamanPower.ScalingHeight
				if newscale < 0.5 then
					ShamanPower_ScaleFrame(0.5)
				else
					ShamanPower_ScaleFrame(newscale)
				end
			end
		end
	end
end

-------------------------------------------------------------------
-- Main Functionality
-------------------------------------------------------------------
function ShamanPower:ReportChannels()
	local channels = {GetChannelList()}
	ShamanPower_ChanNames = {}
	ShamanPower_ChanNames[0] = "None"
	for i = 1, #channels / 3 do
		local chanName = channels[i * 3 - 1]
		if chanName ~= "LookingForGroup" and chanName ~= "General" and chanName ~= "Trade" and chanName ~= "LocalDefense" and chanName ~= "WorldDefense" and chanName ~= "GuildRecruitment" then
			ShamanPower_ChanNames[i] = chanName
		end
	end
	return ShamanPower_ChanNames
end

function ShamanPower:Report(type, chanNum)
	if not type then
		if GetNumGroupMembers() > 0 then
			if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and IsInInstance() then
				type = "INSTANCE_CHAT"
			else
				if IsInRaid() then
					type = "RAID"
				elseif IsInGroup(LE_PARTY_CATEGORY_HOME) then
					type = "PARTY"
				end
			end
			if self:CheckLeader(self.player) and type ~= "INSTANCE_CHAT" then
				if #SyncList > 0 then
					SendChatMessage(L["--- Shaman assignments ---"], type)
					local list = {}
					for name in pairs(AllShamans) do
						local blessings
						for i = 1, self.isWrath and 4 or 6 do
							list[i] = 0
						end
						local assignments = ShamanPower_Assignments[name] or {}
						for id = 1, SHAMANPOWER_MAXCLASSES do
							local bid = assignments[id]
							if bid and bid > 0 then
								list[bid] = list[bid] + 1
							end
						end
						for id = 1, self.isWrath and 4 or 6 do
							if (list[id] > 0) then
								if (blessings) then
									blessings = blessings .. ", "
								else
									blessings = ""
								end
								local spell = self.Spells[id]
								blessings = blessings .. spell
							end
						end
						if not (blessings) then
							blessings = "Nothing"
						end
						SendChatMessage(name .. ": " .. blessings, type)
					end
					SendChatMessage(L["--- End of assignments ---"], type)
				end
			else
				if type == "INSTANCE_CHAT" then
					self:Print("Blessings Report is disabled in Battlegrounds.")
				elseif type == "RAID" then
					self:Print("You are not the raid leader or do not have raid assist.")
				else
					self:Print(ERR_NOT_LEADER)
				end
			end
		else
			if type == "RAID" then
				self:Print(ERR_NOT_IN_RAID)
			else
				self:Print(ERR_NOT_IN_GROUP)
			end
		end
	else
		if ((type and (type ~= "INSTANCE_CHAT" or type ~= "RAID" or type ~= "PARTY")) and chanNum and (IsInRaid() or IsInGroup())) then
			SendChatMessage(L["--- Shaman assignments ---"], type, nil, chanNum)
			local list = {}
			for name in pairs(AllShamans) do
				local blessings
				for i = 1, self.isWrath and 4 or 6 do
					list[i] = 0
				end
				local assignments = ShamanPower_Assignments[name] or {}
				for id = 1, SHAMANPOWER_MAXCLASSES do
					local bid = assignments[id]
					if bid and bid > 0 then
						list[bid] = list[bid] + 1
					end
				end
				for id = 1, self.isWrath and 4 or 6 do
					if (list[id] > 0) then
						if (blessings) then
							blessings = blessings .. ", "
						else
							blessings = ""
						end
						local spell = self.Spells[id]
						blessings = blessings .. spell
					end
				end
				if not (blessings) then
					blessings = "Nothing"
				end
				SendChatMessage(name .. ": " .. blessings, type, nil, chanNum)
			end
			SendChatMessage(L["--- End of assignments ---"], type, nil, chanNum)
		elseif not IsInGroup() then
			self:Print(ERR_NOT_IN_GROUP)
		elseif not IsInRaid() then
			self:Print(ERR_NOT_IN_RAID)
		end
	end
end

-- ============================================================================
-- TotemTimers Integration (Optional)
-- Syncs ShamanPower totem assignments to TotemTimers bar
-- Only enabled when TotemTimers is installed AND the option is enabled
-- ============================================================================

-- Map ShamanPower element IDs to TotemTimers element slots
-- ShamanPower: 1=Earth, 2=Fire, 3=Water, 4=Air
-- TotemTimers: EARTH_TOTEM_SLOT=2, FIRE_TOTEM_SLOT=1, WATER_TOTEM_SLOT=3, AIR_TOTEM_SLOT=4
local ShamanPower_ToTotemTimers_ElementMap = {
	[1] = 2,  -- Earth -> EARTH_TOTEM_SLOT (2)
	[2] = 1,  -- Fire -> FIRE_TOTEM_SLOT (1)
	[3] = 3,  -- Water -> WATER_TOTEM_SLOT (3)
	[4] = 4,  -- Air -> AIR_TOTEM_SLOT (4)
}

-- Check if TotemTimers integration is available and enabled
function ShamanPower:IsTotemTimersSyncEnabled()
	-- Check if TotemTimers addon is loaded
	if not TotemTimers or not XiTimers or not XiTimers.timers then
		return false
	end
	-- Check if the sync option is enabled in settings (default to true if TotemTimers is present)
	if self.db and self.db.profile and self.db.profile.syncToTotemTimers ~= nil then
		return self.db.profile.syncToTotemTimers
	end
	-- Default to true if TotemTimers is available
	return true
end

function ShamanPower:SyncToTotemTimers(element, totemIndex)
	-- Check if sync is enabled
	if not self:IsTotemTimersSyncEnabled() then
		return
	end

	-- Skip if element is invalid (e.g., shift-click mass assign uses element 5)
	if element < 1 or element > 4 then
		return
	end

	-- Get the spell ID for this totem assignment
	local spellID = nil
	if totemIndex and totemIndex > 0 then
		spellID = self:GetTotemSpell(element, totemIndex)
	end

	if not spellID then
		return  -- No totem assigned, don't change TotemTimers
	end

	-- Map to TotemTimers element slot
	local ttSlot = ShamanPower_ToTotemTimers_ElementMap[element]
	if not ttSlot then
		return
	end

	-- Find the timer with matching .nr slot
	local timer = nil
	for i = 1, 4 do
		if XiTimers.timers[i] and XiTimers.timers[i].nr == ttSlot then
			timer = XiTimers.timers[i]
			break
		end
	end

	if not timer or not timer.button then
		return
	end

	-- Update the TotemTimers button with this spell
	-- Only if not in combat (secure action buttons can't be modified in combat)
	if InCombatLockdown() then
		-- Queue the update for after combat
		self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
			self:UnregisterEvent("PLAYER_REGEN_ENABLED")
			if timer.button then
				timer.button:SetAttribute("*spell1", spellID)
			end
		end)
	else
		timer.button:SetAttribute("*spell1", spellID)
	end
end

-- ============================================================================
-- Totem Status Detection
-- ============================================================================

-- Map our element IDs to WoW's totem slots
-- Our addon: 1=Earth, 2=Fire, 3=Water, 4=Air
-- WoW slots: 1=Fire, 2=Earth, 3=Water, 4=Air
ShamanPower.ElementToSlot = {
	[1] = 2,  -- Earth -> slot 2
	[2] = 1,  -- Fire -> slot 1
	[3] = 3,  -- Water -> slot 3
	[4] = 4,  -- Air -> slot 4
}

-- Check if a specific totem element is currently active
function ShamanPower:IsTotemActive(element)
	local slot = self.ElementToSlot[element]
	if not slot then return false end
	local haveTotem, totemName, startTime, duration = GetTotemInfo(slot)
	return haveTotem and (startTime + duration > GetTime())
end

-- Find the totem index for a given element based on the active totem name
-- Used for Dynamic Mode to determine which totem is currently placed
function ShamanPower:GetActiveTotemIndex(element)
	local slot = self.ElementToSlot[element]
	if not slot then return nil end

	local haveTotem, activeTotemName = GetTotemInfo(slot)
	if not haveTotem or not activeTotemName then return nil end

	-- Search through all totems for this element to find a match
	local totemNames = self.TotemNames[element]
	if not totemNames then return nil end

	-- Convert to lowercase once for faster comparison
	local activeLower = activeTotemName:lower()

	for totemIndex, totemName in pairs(totemNames) do
		-- Check if the active totem name contains this totem's name (plain text match)
		if totemName and activeLower:find(totemName:lower(), 1, true) then
			return totemIndex
		end
	end

	return nil
end

-- Get status of all assigned totems: returns active count, total assigned
function ShamanPower:GetTotemStatus()
	local playerName = self.player
	local assignments = ShamanPower_Assignments[playerName]
	if not assignments then return 0, 0 end

	local activeCount = 0
	local assignedCount = 0

	for element = 1, 4 do
		local totemIndex = assignments[element] or 0
		if totemIndex and totemIndex > 0 then
			assignedCount = assignedCount + 1
			if self:IsTotemActive(element) then
				activeCount = activeCount + 1
			end
		end
	end

	return activeCount, assignedCount
end

-- Update totem assignments and icons for Dynamic Mode
-- When a totem is placed, it becomes the new assignment for that element
function ShamanPower:UpdateDynamicTotemIcons()
	if not self.opt.dynamicTotemMode then return end

	local playerName = self.player
	if not ShamanPower_Assignments[playerName] then
		ShamanPower_Assignments[playerName] = {}
	end
	local assignments = ShamanPower_Assignments[playerName]

	local needsFullUpdate = false

	for element = 1, 4 do
		-- Skip Air (element 4) when totem twisting is enabled - twist manages Air specially
		if element == 4 and self.opt.enableTotemTwisting then
			-- Don't update Air assignment or icon in dynamic mode when twisting
		else
			local activeIndex = self:GetActiveTotemIndex(element)

			-- If there's an active totem and it's different from the assignment, update it
			if activeIndex and activeIndex ~= assignments[element] then
				assignments[element] = activeIndex
				needsFullUpdate = true
			end

			-- Update the icon regardless
			local totemIndex = assignments[element] or 0
			local icon = self.ElementIcons[element]  -- Default
			if totemIndex and totemIndex > 0 then
				icon = self:GetTotemIcon(element, totemIndex)
			end

			-- Update the XML button icon
			local iconTexture = _G["ShamanPowerAutoTotem" .. element .. "Icon"]
			if iconTexture then
				iconTexture:SetTexture(icon)
			end

			-- Update the Lua button icon (if exists)
			local btn = self.totemButtons and self.totemButtons[element]
			if btn and btn.icon then
				btn.icon:SetTexture(icon)
			end
		end
	end

	-- If assignments changed and we're not in combat, do a full update
	if needsFullUpdate and not InCombatLockdown() then
		self:UpdateMiniTotemBar()
		self:UpdateTotemButtons()
		self:UpdateDropAllButton()
	end
end

-- ============================================================================
-- Totem Pulse Overlay (visual pulse for totems like Tremor)
-- ============================================================================

ShamanPower.pulseOverlays = {}

function ShamanPower:CreatePulseOverlay(button)
	if not button then return nil end

	local container = { glows = {}, button = button }

	-- Create multiple layered glows for more intensity
	for i = 1, 3 do
		local glow = button:CreateTexture(nil, "OVERLAY", nil, 7)
		local offset = 6 + (i * 4)  -- 10, 14, 18 pixel offsets
		glow:SetPoint("TOPLEFT", button, "TOPLEFT", -offset, offset)
		glow:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", offset, -offset)
		glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
		glow:SetBlendMode("ADD")
		glow:SetVertexColor(0.4, 1, 0.4)  -- Bright green
		glow:SetAlpha(0)
		container.glows[i] = glow
	end

	-- Create wipe frame for pulse countdown
	local wipeFrame = CreateFrame("Frame", nil, button)
	wipeFrame:SetFrameLevel(button:GetFrameLevel() + 1)

	-- White overlay texture
	local wipe = wipeFrame:CreateTexture(nil, "OVERLAY")
	wipe:SetColorTexture(1, 1, 1, 0.7)  -- White for visibility
	wipe:Hide()

	-- Time text inside the bar (top)
	local barTimeTextTop = wipeFrame:CreateFontString(nil, "OVERLAY")
	barTimeTextTop:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
	barTimeTextTop:SetPoint("TOP", wipeFrame, "TOP", 0, -1)
	barTimeTextTop:SetTextColor(1, 1, 1)  -- White text
	barTimeTextTop:Hide()
	container.barTimeTextTop = barTimeTextTop

	-- Time text inside the bar (bottom)
	local barTimeTextBottom = wipeFrame:CreateFontString(nil, "OVERLAY")
	barTimeTextBottom:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
	barTimeTextBottom:SetPoint("BOTTOM", wipeFrame, "BOTTOM", 0, 1)
	barTimeTextBottom:SetTextColor(1, 1, 1)  -- White text
	barTimeTextBottom:Hide()
	container.barTimeTextBottom = barTimeTextBottom

	-- Time text above the bar
	local aboveTimeText = wipeFrame:CreateFontString(nil, "OVERLAY")
	aboveTimeText:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
	aboveTimeText:SetPoint("BOTTOM", wipeFrame, "TOP", 0, 1)
	aboveTimeText:SetTextColor(1, 1, 1)  -- White text
	aboveTimeText:Hide()
	container.aboveTimeText = aboveTimeText

	-- Time text below the bar
	local belowTimeText = wipeFrame:CreateFontString(nil, "OVERLAY")
	belowTimeText:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
	belowTimeText:SetPoint("TOP", wipeFrame, "BOTTOM", 0, -1)
	belowTimeText:SetTextColor(1, 1, 1)  -- White text
	belowTimeText:Hide()
	container.belowTimeText = belowTimeText

	-- Time text on the icon
	local iconTimeText = button:CreateFontString(nil, "OVERLAY")
	iconTimeText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
	iconTimeText:SetPoint("CENTER", button, "CENTER", 0, 0)
	iconTimeText:SetTextColor(1, 1, 1)  -- White text
	iconTimeText:Hide()
	container.iconTimeText = iconTimeText

	container.wipeFrame = wipeFrame
	container.wipe = wipe
	container.buttonWidth = button:GetWidth() - 4
	container.buttonHeight = button:GetHeight() - 4

	-- Position the wipe bar based on current option
	self:PositionPulseWipe(container)

	container.SetAlpha = function(self, alpha)
		for i, glow in ipairs(self.glows) do
			glow:SetAlpha(alpha * (1.1 - i * 0.2))  -- Inner glows brighter
		end
	end

	container.Show = function(self)
		for _, glow in ipairs(self.glows) do glow:Show() end
	end

	container.Hide = function(self)
		for _, glow in ipairs(self.glows) do glow:Hide() end
	end

	container.HideWipe = function(self)
		if self.wipe then
			self.wipe:Hide()
		end
	end

	-- Update the wipe progress (0 = just pulsed/no coverage, 1 = about to pulse/full coverage)
	container.UpdateWipe = function(self, progress)
		if self.wipe then
			-- Don't show if pulse bar is disabled
			if self.isDisabled then
				self.wipe:Hide()
				return
			end
			if progress > 0 and progress < 1 then
				local size = self.maxSize * progress
				if self.isVertical then
					self.wipe:SetHeight(math.max(1, size))
				else
					self.wipe:SetWidth(math.max(1, size))
				end
				self.wipe:Show()
			else
				self.wipe:Hide()
			end
		end
	end

	-- Hide all time text elements
	local function hideAllTimeTexts(self)
		if self.barTimeTextTop then self.barTimeTextTop:Hide() end
		if self.barTimeTextBottom then self.barTimeTextBottom:Hide() end
		if self.aboveTimeText then self.aboveTimeText:Hide() end
		if self.belowTimeText then self.belowTimeText:Hide() end
		if self.iconTimeText then self.iconTimeText:Hide() end
	end

	-- Update the time display
	container.UpdateTime = function(self, timeRemaining, displayOption)
		hideAllTimeTexts(self)

		if not displayOption or displayOption == "none" then
			return
		end

		local timeText = string.format("%.1f", timeRemaining)
		local textSize = ShamanPower.opt.pulseTextSize or 8

		if displayOption == "inside_top" then
			if self.barTimeTextTop then
				self.barTimeTextTop:SetFont("Fonts\\FRIZQT__.TTF", textSize, "OUTLINE")
				self.barTimeTextTop:SetText(timeText)
				self.barTimeTextTop:Show()
			end
		elseif displayOption == "inside_bottom" then
			if self.barTimeTextBottom then
				self.barTimeTextBottom:SetFont("Fonts\\FRIZQT__.TTF", textSize, "OUTLINE")
				self.barTimeTextBottom:SetText(timeText)
				self.barTimeTextBottom:Show()
			end
		elseif displayOption == "above" then
			if self.aboveTimeText then
				self.aboveTimeText:SetFont("Fonts\\FRIZQT__.TTF", textSize, "OUTLINE")
				self.aboveTimeText:SetText(timeText)
				self.aboveTimeText:Show()
			end
		elseif displayOption == "below" then
			if self.belowTimeText then
				self.belowTimeText:SetFont("Fonts\\FRIZQT__.TTF", textSize, "OUTLINE")
				self.belowTimeText:SetText(timeText)
				self.belowTimeText:Show()
			end
		elseif displayOption == "on_icon" then
			if self.iconTimeText then
				self.iconTimeText:SetFont("Fonts\\FRIZQT__.TTF", textSize, "OUTLINE")
				self.iconTimeText:SetText(timeText)
				self.iconTimeText:Show()
			end
		end
	end

	-- Hide time displays
	container.HideTime = function(self)
		if self.barTimeTextTop then self.barTimeTextTop:Hide() end
		if self.barTimeTextBottom then self.barTimeTextBottom:Hide() end
		if self.aboveTimeText then self.aboveTimeText:Hide() end
		if self.belowTimeText then self.belowTimeText:Hide() end
		if self.iconTimeText then self.iconTimeText:Hide() end
	end

	return container
end

-- Position the pulse wipe bar based on the pulseBarPosition option
function ShamanPower:PositionPulseWipe(container)
	if not container or not container.wipe or not container.button then return end

	local button = container.button
	local wipeFrame = container.wipeFrame
	local wipe = container.wipe
	local position = self.opt.pulseBarPosition or "on_icon"
	local barSize = self.opt.pulseBarSize or 4  -- Size of the external bar

	wipe:ClearAllPoints()
	wipeFrame:ClearAllPoints()

	-- Handle "none" position - hide the pulse bar
	if position == "none" then
		wipe:Hide()
		wipeFrame:Hide()
		container.isDisabled = true
		return
	end

	container.isDisabled = false

	if position == "on_icon" then
		-- Original behavior: wipe slides down inside the icon
		wipeFrame:SetAllPoints(button)
		wipe:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
		wipe:SetPoint("TOPRIGHT", button, "TOPRIGHT", -2, -2)
		wipe:SetHeight(1)
		container.isVertical = true
		container.isOnIcon = true
		container.maxSize = container.buttonHeight
	elseif position == "above" then
		-- Horizontal bar above the icon, fills left to right
		wipeFrame:SetPoint("BOTTOMLEFT", button, "TOPLEFT", 0, 1)
		wipeFrame:SetSize(button:GetWidth(), barSize)
		wipe:SetPoint("LEFT", wipeFrame, "LEFT", 0, 0)
		wipe:SetHeight(barSize)
		wipe:SetWidth(1)
		container.isVertical = false
		container.isOnIcon = false
		container.maxSize = button:GetWidth()
	elseif position == "above_vert" then
		-- Vertical bar above the icon, fills bottom to top (same height as icon)
		wipeFrame:SetPoint("BOTTOM", button, "TOP", 0, 1)
		wipeFrame:SetSize(barSize, button:GetHeight())
		wipe:SetPoint("BOTTOMLEFT", wipeFrame, "BOTTOMLEFT", 0, 0)
		wipe:SetWidth(barSize)
		wipe:SetHeight(1)
		container.isVertical = true
		container.isOnIcon = false
		container.maxSize = button:GetHeight()
	elseif position == "below" then
		-- Horizontal bar below the icon, fills left to right
		wipeFrame:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -1)
		wipeFrame:SetSize(button:GetWidth(), barSize)
		wipe:SetPoint("LEFT", wipeFrame, "LEFT", 0, 0)
		wipe:SetHeight(barSize)
		wipe:SetWidth(1)
		container.isVertical = false
		container.isOnIcon = false
		container.maxSize = button:GetWidth()
	elseif position == "below_vert" then
		-- Vertical bar below the icon, fills top to bottom (same height as icon)
		wipeFrame:SetPoint("TOP", button, "BOTTOM", 0, -1)
		wipeFrame:SetSize(barSize, button:GetHeight())
		wipe:SetPoint("TOPLEFT", wipeFrame, "TOPLEFT", 0, 0)
		wipe:SetWidth(barSize)
		wipe:SetHeight(1)
		container.isVertical = true
		container.isOnIcon = false
		container.maxSize = button:GetHeight()
	elseif position == "left" then
		-- Vertical bar to the left, fills bottom to top
		wipeFrame:SetPoint("TOPRIGHT", button, "TOPLEFT", -1, 0)
		wipeFrame:SetSize(barSize, button:GetHeight())
		wipe:SetPoint("BOTTOMLEFT", wipeFrame, "BOTTOMLEFT", 0, 0)
		wipe:SetWidth(barSize)
		wipe:SetHeight(1)
		container.isVertical = true
		container.isOnIcon = false
		container.maxSize = button:GetHeight()
	elseif position == "right" then
		-- Vertical bar to the right, fills bottom to top
		wipeFrame:SetPoint("TOPLEFT", button, "TOPRIGHT", 1, 0)
		wipeFrame:SetSize(barSize, button:GetHeight())
		wipe:SetPoint("BOTTOMLEFT", wipeFrame, "BOTTOMLEFT", 0, 0)
		wipe:SetWidth(barSize)
		wipe:SetHeight(1)
		container.isVertical = true
		container.isOnIcon = false
		container.maxSize = button:GetHeight()
	end
end

-- Update all pulse bar positions when option changes
function ShamanPower:UpdatePulseBarPositions()
	-- Enable/disable pulse subsystem based on whether pulse bar is enabled
	local pulseEnabled = (self.opt.pulseBarPosition ~= "none")
	if pulseEnabled then
		self:EnableUpdateSubsystem("pulse")
	else
		self:DisableUpdateSubsystem("pulse")
	end

	for element, container in pairs(self.pulseOverlays) do
		if container then
			self:PositionPulseWipe(container)
		end
	end
	-- Also update active totem overlay pulse positions
	if self.activeTotemOverlays then
		for element, overlay in pairs(self.activeTotemOverlays) do
			if overlay and overlay.frame then
				self:PositionOverlayPulseWipe(overlay, overlay.frame)
			end
		end
	end
end

-- Position the pulse wipe bar for active totem overlays
function ShamanPower:PositionOverlayPulseWipe(overlay, frame)
	if not overlay or not overlay.wipe or not frame then return end

	local wipeFrame = overlay.wipeFrame
	local wipe = overlay.wipe
	local position = self.opt.pulseBarPosition or "on_icon"
	local barSize = self.opt.pulseBarSize or 4  -- Size of the external bar

	wipe:ClearAllPoints()
	if wipeFrame then wipeFrame:ClearAllPoints() end

	-- Handle "none" position - hide the pulse bar
	if position == "none" then
		wipe:Hide()
		if wipeFrame then wipeFrame:Hide() end
		overlay.isDisabled = true
		return
	end

	overlay.isDisabled = false

	if position == "on_icon" then
		-- Original behavior: wipe slides down inside the icon
		if wipeFrame then wipeFrame:SetAllPoints(frame) end
		wipe:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -2)
		wipe:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
		wipe:SetHeight(1)
		overlay.isVertical = true
		overlay.isOnIcon = true
		overlay.maxSize = overlay.buttonHeight or (frame:GetHeight() - 4)
	elseif position == "above" then
		-- Horizontal bar above the frame, fills left to right
		if wipeFrame then
			wipeFrame:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 1)
			wipeFrame:SetSize(frame:GetWidth(), barSize)
		end
		wipe:SetPoint("LEFT", wipeFrame or frame, "LEFT", 0, 0)
		wipe:SetHeight(barSize)
		wipe:SetWidth(1)
		overlay.isVertical = false
		overlay.isOnIcon = false
		overlay.maxSize = frame:GetWidth()
	elseif position == "above_vert" then
		-- Vertical bar above the frame, fills bottom to top (same height as icon)
		if wipeFrame then
			wipeFrame:SetPoint("BOTTOM", frame, "TOP", 0, 1)
			wipeFrame:SetSize(barSize, frame:GetHeight())
		end
		wipe:SetPoint("BOTTOMLEFT", wipeFrame or frame, "BOTTOMLEFT", 0, 0)
		wipe:SetWidth(barSize)
		wipe:SetHeight(1)
		overlay.isVertical = true
		overlay.isOnIcon = false
		overlay.maxSize = frame:GetHeight()
	elseif position == "below" then
		-- Horizontal bar below the frame, fills left to right
		if wipeFrame then
			wipeFrame:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -1)
			wipeFrame:SetSize(frame:GetWidth(), barSize)
		end
		wipe:SetPoint("LEFT", wipeFrame or frame, "LEFT", 0, 0)
		wipe:SetHeight(barSize)
		wipe:SetWidth(1)
		overlay.isVertical = false
		overlay.isOnIcon = false
		overlay.maxSize = frame:GetWidth()
	elseif position == "below_vert" then
		-- Vertical bar below the frame, fills top to bottom (same height as icon)
		if wipeFrame then
			wipeFrame:SetPoint("TOP", frame, "BOTTOM", 0, -1)
			wipeFrame:SetSize(barSize, frame:GetHeight())
		end
		wipe:SetPoint("TOPLEFT", wipeFrame or frame, "TOPLEFT", 0, 0)
		wipe:SetWidth(barSize)
		wipe:SetHeight(1)
		overlay.isVertical = true
		overlay.isOnIcon = false
		overlay.maxSize = frame:GetHeight()
	elseif position == "left" then
		-- Vertical bar to the left, fills bottom to top
		if wipeFrame then
			wipeFrame:SetPoint("TOPRIGHT", frame, "TOPLEFT", -1, 0)
			wipeFrame:SetSize(barSize, frame:GetHeight())
		end
		wipe:SetPoint("BOTTOMLEFT", wipeFrame or frame, "BOTTOMLEFT", 0, 0)
		wipe:SetWidth(barSize)
		wipe:SetHeight(1)
		overlay.isVertical = true
		overlay.isOnIcon = false
		overlay.maxSize = frame:GetHeight()
	elseif position == "right" then
		-- Vertical bar to the right, fills bottom to top
		if wipeFrame then
			wipeFrame:SetPoint("TOPLEFT", frame, "TOPRIGHT", 1, 0)
			wipeFrame:SetSize(barSize, frame:GetHeight())
		end
		wipe:SetPoint("BOTTOMLEFT", wipeFrame or frame, "BOTTOMLEFT", 0, 0)
		wipe:SetWidth(barSize)
		wipe:SetHeight(1)
		overlay.isVertical = true
		overlay.isOnIcon = false
		overlay.maxSize = frame:GetHeight()
	end
end

-- Pulsing totem data: totemName pattern -> { element, interval }
ShamanPower.PulsingTotems = {
	-- Earth totems (element 1, slot 2)
	["Tremor"] = { element = 1, slot = 2, interval = 3 },
	["Earthbind"] = { element = 1, slot = 2, interval = 3 },
	-- Water totems (element 3, slot 3)
	["Mana Tide"] = { element = 3, slot = 3, interval = 3 },
	["Healing Stream"] = { element = 3, slot = 3, interval = 2 },
	["Poison Cleansing"] = { element = 3, slot = 3, interval = 5 },
	["Disease Cleansing"] = { element = 3, slot = 3, interval = 5 },
}

function ShamanPower:GetActivePulsingTotem(slot)
	local haveTotem, totemName, startTime, duration = GetTotemInfo(slot)
	if haveTotem and totemName then
		for pattern, data in pairs(self.PulsingTotems) do
			if data.slot == slot and totemName:find(pattern) then
				return data, startTime, duration
			end
		end
	end
	return nil, nil, nil
end

function ShamanPower:SetupPulseOverlays()
	-- Create pulse overlays for Earth (1) and Water (3) totem buttons
	local elements = {1, 3}  -- Earth and Water can have pulsing totems
	for _, element in ipairs(elements) do
		local button = self.totemButtons[element]
		if button and not self.pulseOverlays[element] then
			self.pulseOverlays[element] = self:CreatePulseOverlay(button)
		end
	end

	-- Register pulse tracking with consolidated update system (20fps)
	-- Only register once, but only enable if feature is on
	if not self.updateSystem.subsystems["pulse"] then
		self:RegisterUpdateSubsystem("pulse", 0.05, function()
			-- Check Earth totem (slot 2)
			local earthData, earthStart = ShamanPower:GetActivePulsingTotem(2)
			ShamanPower:UpdatePulseGlow(1, earthData, earthStart)
			ShamanPower:UpdatePoppedOutPulse(1, 2, earthData, earthStart)

			-- Check Water totem (slot 3)
			local waterData, waterStart = ShamanPower:GetActivePulsingTotem(3)
			ShamanPower:UpdatePulseGlow(3, waterData, waterStart)
			ShamanPower:UpdatePoppedOutPulse(3, 3, waterData, waterStart)
		end)
	end
	-- Only enable if pulse bar is not disabled (pulseBarPosition != "none")
	local pulseEnabled = (self.opt.pulseBarPosition ~= "none")
	if pulseEnabled then
		self:EnableUpdateSubsystem("pulse")
	else
		self:DisableUpdateSubsystem("pulse")
	end
end

-- Update pulse effects on popped-out single totems
function ShamanPower:UpdatePoppedOutPulse(element, slot, totemData, startTime)
	-- Get the active totem name to match against pop-outs
	local haveTotem, activeTotemName = GetTotemInfo(slot)

	-- Iterate through all popped-out overlays for this element
	for key, overlay in pairs(self.poppedOutOverlays or {}) do
		if overlay.element == element then
			local frame = self.poppedOutFrames[key]
			local matchesTotem = false

			-- Check if this pop-out's totem matches the active totem
			if haveTotem and activeTotemName and overlay.spellName then
				-- Simple case-insensitive substring match
				local activeLower = activeTotemName:lower()
				local spellLower = overlay.spellName:lower()
				if activeLower:find(spellLower, 1, true) or spellLower:find(activeLower, 1, true) then
					matchesTotem = true
				end
			end

			if matchesTotem and totemData and startTime then
				-- This pop-out matches the active pulsing totem - show pulse
				local now = GetTime()
				local totemAge = now - startTime
				local pulseInterval = totemData.interval
				local cyclePos = (totemAge % pulseInterval) / pulseInterval
				local timeRemaining = pulseInterval * (1 - cyclePos)

				-- Update wipe bar
				if overlay.UpdateWipe then
					overlay:UpdateWipe(cyclePos)
				end

				-- Update time display
				local displayOption = self.opt.pulseTimeDisplay or "none"
				if overlay.UpdateTime then
					overlay:UpdateTime(timeRemaining, displayOption)
				end

				-- Update glow flash (pulse at start of cycle)
				local alpha
				if cyclePos < 0.15 then
					alpha = 1 - (cyclePos / 0.15)
				else
					alpha = 0
				end

				if alpha > 0 then
					overlay:SetAlpha(alpha * 0.9)
					overlay:Show()
				else
					overlay:SetAlpha(0)
					overlay:Hide()
				end

				-- Show active border on the frame
				if frame and frame.activeBorder then
					frame.activeBorder:Show()
				end
			else
				-- No match or no active pulsing totem - hide pulse
				overlay:SetAlpha(0)
				overlay:Hide()
				if overlay.HideWipe then
					overlay:HideWipe()
				end
				if overlay.HideTime then
					overlay:HideTime()
				end

				-- Check if this pop-out's totem is active (but not pulsing)
				if matchesTotem and haveTotem then
					-- Totem is active but not pulsing - just show active border
					if frame and frame.activeBorder then
						frame.activeBorder:Show()
					end
				else
					-- Hide active border
					if frame and frame.activeBorder then
						frame.activeBorder:Hide()
					end
				end
			end
		end
	end
end

function ShamanPower:UpdatePulseGlow(element, totemData, startTime)
	local glow = self.pulseOverlays[element]
	if not glow then return end

	-- Check if active overlay is showing for this element
	-- In TotemTimers style mode (activeTotemAsMain), always use main button even when overlay is "active"
	local activeOverlay = self.activeTotemOverlays and self.activeTotemOverlays[element]
	local useOverlay = activeOverlay and activeOverlay.isActive and not self.opt.activeTotemAsMain

	-- Check if the active totem is popped out - if so, don't show pulse on main bar
	local totemIsPoppedOut = false
	if totemData then
		local slot = self.ElementToSlot and self.ElementToSlot[element] or element
		local haveTotem, activeTotemName = GetTotemInfo(slot)
		if haveTotem and activeTotemName then
			-- Check if any popped-out single totem matches
			for key, overlay in pairs(self.poppedOutOverlays or {}) do
				if overlay.element == element and overlay.spellName then
					local ok1, result1 = pcall(string.find, activeTotemName, overlay.spellName, 1, true)
					local ok2, result2 = pcall(string.find, overlay.spellName, activeTotemName, 1, true)
					if (ok1 and result1) or (ok2 and result2) then
						totemIsPoppedOut = true
						break
					end
				end
			end
		end
	end

	-- If totem is popped out, hide main bar pulse and let UpdatePoppedOutPulse handle it
	if totemIsPoppedOut then
		glow:SetAlpha(0)
		glow:Hide()
		glow:HideWipe()
		if glow.HideTime then
			glow:HideTime()
		end
		return
	end

	if totemData and startTime then
		local now = GetTime()
		local totemAge = now - startTime
		local pulseInterval = totemData.interval

		-- Calculate position within current pulse cycle (0 to 1)
		local cyclePos = (totemAge % pulseInterval) / pulseInterval

		-- Calculate time remaining until next pulse
		local timeRemaining = pulseInterval * (1 - cyclePos)

		if useOverlay and activeOverlay.wipe then
			-- Update overlay's wipe using its positioning settings
			-- Check if pulse bar is disabled
			if activeOverlay.isDisabled then
				activeOverlay.wipe:Hide()
			elseif cyclePos > 0 and cyclePos < 1 then
				local maxSize = activeOverlay.maxSize or 22
				local size = maxSize * cyclePos
				if activeOverlay.isVertical then
					activeOverlay.wipe:SetHeight(math.max(1, size))
				else
					activeOverlay.wipe:SetWidth(math.max(1, size))
				end
				activeOverlay.wipe:Show()
			else
				activeOverlay.wipe:Hide()
			end
			-- Hide main button's wipe
			glow:UpdateWipe(-1)  -- Hide by passing invalid value
		else
			-- Update main button's wipe
			glow:UpdateWipe(cyclePos)
		end

		-- Update pulse time display
		local displayOption = self.opt.pulseTimeDisplay or "none"
		if useOverlay and activeOverlay.UpdateTime then
			-- Update time on active overlay
			activeOverlay:UpdateTime(timeRemaining, displayOption)
			-- Hide time on main overlay
			if glow.HideTime then glow:HideTime() end
		elseif glow.UpdateTime then
			-- Update time on main overlay
			glow:UpdateTime(timeRemaining, displayOption)
		end

		-- Pulse brightens at the start of each cycle (the glow flash)
		local alpha
		if cyclePos < 0.15 then
			-- Quick flash at pulse point
			alpha = 1 - (cyclePos / 0.15)
		else
			alpha = 0
		end

		if useOverlay and activeOverlay.glows then
			-- Update overlay's glows
			for i, overlayGlow in ipairs(activeOverlay.glows) do
				overlayGlow:SetAlpha(alpha * 0.9 * (1.1 - i * 0.2))
			end
			-- Hide main glows
			glow:SetAlpha(0)
			glow:Hide()
		else
			-- Update main button's glows
			if alpha > 0 then
				glow:SetAlpha(alpha * 0.9)
				glow:Show()
			else
				glow:SetAlpha(0)
				glow:Hide()
			end
		end
	else
		glow:SetAlpha(0)
		glow:Hide()
		glow:HideWipe()
		if glow.HideTime then
			glow:HideTime()
		end

		-- Also hide overlay's pulse elements
		if activeOverlay then
			if activeOverlay.wipe then activeOverlay.wipe:Hide() end
			if activeOverlay.glows then
				for _, overlayGlow in ipairs(activeOverlay.glows) do
					overlayGlow:SetAlpha(0)
				end
			end
			if activeOverlay.HideTime then activeOverlay:HideTime() end
		end
	end
end

-- ============================================================================
-- Totem Twisting Timer (visual countdown for Air totem twist window)
-- ============================================================================

ShamanPower.twistTimer = nil
ShamanPower.twistCooldown = nil
ShamanPower.TWIST_WINDOW = 10  -- Seconds before Windfury buff expires

function ShamanPower:SetupTwistTimer()
	if not self.opt.enableTotemTwisting then return end

	local airButton = self.totemButtons[4]
	if not airButton then return end

	-- Create twist timer display on top of air totem icon
	if not self.twistTimerFrame then
		self.twistTimerFrame = CreateFrame("Frame", "ShamanPowerTwistTimerFrame", airButton)
		self.twistTimerFrame:SetAllPoints(airButton)
		self.twistTimerFrame:SetFrameStrata("HIGH")

		self.twistTimerText = self.twistTimerFrame:CreateFontString(nil, "OVERLAY")
		self.twistTimerText:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
		self.twistTimerText:SetPoint("CENTER", airButton, "CENTER", 0, 0)
		self.twistTimerText:SetTextColor(1, 1, 1)
		self.twistTimerFrame:Hide()
	end

	-- Register twist tracking with consolidated update system (20fps)
	if not self.updateSystem.subsystems["twist"] then
		self:RegisterUpdateSubsystem("twist", 0.05, function()
			ShamanPower:UpdateTwistTimer()
		end)
	end
	self:EnableUpdateSubsystem("twist")
end

function ShamanPower:HideTwistTimer()
	if self.twistTimerFrame then
		self.twistTimerFrame:Hide()
	end
	self:DisableUpdateSubsystem("twist")
	self.twistStartTime = nil
end

function ShamanPower:UpdateTwistTimer()
	if not self.opt.enableTotemTwisting then
		self:HideTwistTimer()
		return
	end

	-- Check if Air totem is active (slot 4)
	local haveTotem, name, startTime, duration = GetTotemInfo(4)

	-- Update the Air button icon based on what's currently down
	local airButton = self.totemButtons[4]
	local iconTexture = airButton and airButton.icon
	if iconTexture then
		if haveTotem and name then
			if name:find("Windfury") then
				iconTexture:SetTexture("Interface\\Icons\\Spell_Nature_InvisibilityTotem")
			elseif name:find("Grace") then
				iconTexture:SetTexture("Interface\\Icons\\Spell_Nature_Windfury")
			else
				iconTexture:SetTexture("Interface\\Icons\\Spell_Nature_Windfury")
			end
		else
			iconTexture:SetTexture("Interface\\Icons\\Spell_Nature_Windfury")
		end
	end

	if haveTotem and startTime and startTime > 0 then
		-- Restart timer every time WINDFURY is placed
		local isWindfury = name and name:find("Windfury")

		if isWindfury and self.twistStartTime ~= startTime then
			-- New Windfury placed - reset the 10 second timer
			self.twistStartTime = startTime
		end

		-- If no timer running, hide and return
		if not self.twistStartTime then
			if self.twistTimerFrame then
				self.twistTimerFrame:Hide()
			end
			return
		end

		-- Calculate remaining time
		local elapsed = GetTime() - self.twistStartTime
		local remaining = self.TWIST_WINDOW - elapsed

		-- Show center-screen timer
		if remaining > 0 then
			if self.twistTimerFrame and self.twistTimerText then
				self.twistTimerText:SetText(string.format("%.1f", remaining))
				-- Color: white > 3s, yellow > 1s, red <= 1s
				if remaining <= 1 then
					self.twistTimerText:SetTextColor(1, 0.2, 0.2)
				elseif remaining <= 3 then
					self.twistTimerText:SetTextColor(1, 1, 0.2)
				else
					self.twistTimerText:SetTextColor(1, 1, 1)
				end
				self.twistTimerFrame:Show()
			end
		else
			-- Timer expired, reset
			self.twistStartTime = nil
			if self.twistTimerFrame then
				self.twistTimerFrame:Hide()
			end
		end
	else
		-- No Air totem active
		self.twistStartTime = nil
		if self.twistTimerFrame then
			self.twistTimerFrame:Hide()
		end
	end
end


-- ============================================================================
-- Totem Duration Progress Bar (shows time remaining on totems)
-- ============================================================================

ShamanPower.totemProgressBars = {}  -- Progress bar textures for each element

-- Element colors for duration bars
ShamanPower.DurationBarColors = {
	[1] = {0.2, 0.8, 0.2},  -- Earth - green
	[2] = {0.9, 0.3, 0.1},  -- Fire - orange/red
	[3] = {0.2, 0.5, 0.9},  -- Water - blue
	[4] = {0.8, 0.8, 0.8},  -- Air - white/gray
}

-- Create progress bars for totem buttons
function ShamanPower:SetupTotemProgressBars()
	local barSize = self.opt.durationBarHeight or 3

	for element = 1, 4 do
		local totemButton = self.totemButtons[element]
		if totemButton and not self.totemProgressBars[element] then
			-- Background (dark)
			local bgBar = totemButton:CreateTexture(nil, "OVERLAY")
			bgBar:SetColorTexture(0, 0, 0, 0.7)
			bgBar:Hide()

			-- Progress bar (colored)
			local progressBar = totemButton:CreateTexture(nil, "OVERLAY", nil, 1)
			local colors = self.DurationBarColors[element]
			progressBar:SetColorTexture(colors[1], colors[2], colors[3], 1)
			progressBar:Hide()

			-- Duration text INSIDE the bar (top)
			local insideTextTop = totemButton:CreateFontString(nil, "OVERLAY", nil, 7)
			insideTextTop:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
			insideTextTop:SetTextColor(1, 1, 1)
			insideTextTop:Hide()

			-- Duration text INSIDE the bar (bottom)
			local insideTextBottom = totemButton:CreateFontString(nil, "OVERLAY", nil, 7)
			insideTextBottom:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
			insideTextBottom:SetTextColor(1, 1, 1)
			insideTextBottom:Hide()

			-- Duration text ABOVE the bar
			local aboveBarText = totemButton:CreateFontString(nil, "OVERLAY")
			aboveBarText:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
			aboveBarText:SetTextColor(1, 1, 1)
			aboveBarText:Hide()

			-- Duration text BELOW the bar
			local belowBarText = totemButton:CreateFontString(nil, "OVERLAY")
			belowBarText:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
			belowBarText:SetTextColor(1, 1, 1)
			belowBarText:Hide()

			-- Duration text ON the icon
			local iconText = totemButton:CreateFontString(nil, "OVERLAY")
			iconText:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
			iconText:SetPoint("CENTER", totemButton, "CENTER", 0, 0)
			iconText:SetTextColor(1, 1, 1)
			iconText:Hide()

			self.totemProgressBars[element] = {
				bg = bgBar,
				bar = progressBar,
				insideText = insideTextTop,  -- Keep for compatibility
				insideTextTop = insideTextTop,
				insideTextBottom = insideTextBottom,
				aboveBarText = aboveBarText,
				belowBarText = belowBarText,
				belowText = belowBarText,  -- Keep old name for compatibility
				outsideText = belowBarText,  -- Keep old name for compatibility
				iconText = iconText,
				maxWidth = totemButton:GetWidth(),
				maxHeight = totemButton:GetHeight()
			}
		elseif totemButton and self.totemProgressBars[element] then
			-- Bars exist but maybe missing text elements (upgrade from old version)
			local bars = self.totemProgressBars[element]

			if not bars.insideTextTop then
				local insideTextTop = totemButton:CreateFontString(nil, "OVERLAY", nil, 7)
				insideTextTop:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
				insideTextTop:SetTextColor(1, 1, 1)
				insideTextTop:Hide()
				bars.insideTextTop = insideTextTop
				bars.insideText = insideTextTop  -- Compatibility
			end

			if not bars.insideTextBottom then
				local insideTextBottom = totemButton:CreateFontString(nil, "OVERLAY", nil, 7)
				insideTextBottom:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
				insideTextBottom:SetTextColor(1, 1, 1)
				insideTextBottom:Hide()
				bars.insideTextBottom = insideTextBottom
			end

			if not bars.aboveBarText then
				local aboveBarText = totemButton:CreateFontString(nil, "OVERLAY")
				aboveBarText:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
				aboveBarText:SetTextColor(1, 1, 1)
				aboveBarText:Hide()
				bars.aboveBarText = aboveBarText
			end

			if not bars.belowBarText then
				local belowBarText = totemButton:CreateFontString(nil, "OVERLAY")
				belowBarText:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
				belowBarText:SetTextColor(1, 1, 1)
				belowBarText:Hide()
				bars.belowBarText = belowBarText
				bars.belowText = belowBarText  -- Compatibility
				bars.outsideText = belowBarText  -- Compatibility
			end

			if not bars.iconText then
				local iconText = totemButton:CreateFontString(nil, "OVERLAY")
				iconText:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
				iconText:SetPoint("CENTER", totemButton, "CENTER", 0, 0)
				iconText:SetTextColor(1, 1, 1)
				iconText:Hide()
				bars.iconText = iconText
			end

			-- Store dimensions
			bars.maxWidth = totemButton:GetWidth()
			bars.maxHeight = totemButton:GetHeight()
		end
	end

	-- Position bars based on setting
	self:UpdateTotemProgressBarPositions()

	-- Register progress bar updates with consolidated update system (10fps)
	if not self.updateSystem.subsystems["progressBars"] then
		self:RegisterUpdateSubsystem("progressBars", 0.1, function()
			ShamanPower:UpdateTotemProgressBars()

			-- Dynamic Mode: update totem icons to reflect currently placed totems
			if ShamanPower.opt.dynamicTotemMode then
				ShamanPower:UpdateDynamicTotemIcons()
			end

			-- Update totem bar opacity (for "full opacity when active" option)
			if ShamanPower.opt.totemBarFullOpacityWhenActive then
				ShamanPower:UpdateTotemBarOpacity()
			end
		end)
	end
	-- Only enable if any of these features are on
	local needsProgressBars = self.opt.showDurationBars ~= false
		or self.opt.dynamicTotemMode
		or self.opt.totemBarFullOpacityWhenActive
	if needsProgressBars then
		self:EnableUpdateSubsystem("progressBars")
	else
		self:DisableUpdateSubsystem("progressBars")
	end
end

-- Update progress bar positions based on setting
function ShamanPower:UpdateTotemProgressBarPositions()
	local barPosition = self.opt.durationBarPosition or "bottom"
	local barSize = self.opt.durationBarHeight or 3

	-- Enable/disable progressBars subsystem based on whether any features need it
	local barDisabled = (barPosition == "none")
	local textDisabled = (self.opt.durationTextLocation == "none" or self.opt.durationTextLocation == nil)
	local needsProgressBars = (not barDisabled) or (not textDisabled)
		or self.opt.dynamicTotemMode
		or self.opt.totemBarFullOpacityWhenActive
	if needsProgressBars then
		self:EnableUpdateSubsystem("progressBars")
	else
		self:DisableUpdateSubsystem("progressBars")
	end

	for element = 1, 4 do
		local totemButton = self.totemButtons[element]
		local bars = self.totemProgressBars[element]
		if totemButton and bars then
			bars.bg:ClearAllPoints()
			bars.bar:ClearAllPoints()
			if bars.insideTextTop then bars.insideTextTop:ClearAllPoints() end
			if bars.insideTextBottom then bars.insideTextBottom:ClearAllPoints() end
			if bars.aboveBarText then bars.aboveBarText:ClearAllPoints() end
			if bars.belowBarText then bars.belowBarText:ClearAllPoints() end

			if barPosition == "bottom" then
				-- Horizontal bar below the icon
				bars.bg:SetHeight(barSize)
				bars.bg:SetPoint("TOPLEFT", totemButton, "BOTTOMLEFT", 0, -1)
				bars.bg:SetPoint("TOPRIGHT", totemButton, "BOTTOMRIGHT", 0, -1)
				bars.bar:SetHeight(barSize)
				bars.bar:SetPoint("TOPLEFT", totemButton, "BOTTOMLEFT", 0, -1)
				if bars.insideTextTop then bars.insideTextTop:SetPoint("TOP", bars.bg, "TOP", 0, -1) end
				if bars.insideTextBottom then bars.insideTextBottom:SetPoint("BOTTOM", bars.bg, "BOTTOM", 0, 1) end
				if bars.aboveBarText then bars.aboveBarText:SetPoint("BOTTOM", bars.bg, "TOP", 0, 1) end
				if bars.belowBarText then bars.belowBarText:SetPoint("TOP", bars.bg, "BOTTOM", 0, -1) end
			elseif barPosition == "bottom_vert" then
				-- Vertical bar below the icon (centered), shrinks UP toward icon
				bars.bg:SetWidth(barSize)
				bars.bg:SetPoint("TOP", totemButton, "BOTTOM", 0, -1)
				bars.bg:SetHeight(totemButton:GetHeight())
				bars.bar:SetWidth(barSize)
				bars.bar:SetPoint("TOP", bars.bg, "TOP", 0, 0)
				if bars.insideTextTop then bars.insideTextTop:SetPoint("TOP", bars.bg, "TOP", 0, -1) end
				if bars.insideTextBottom then bars.insideTextBottom:SetPoint("BOTTOM", bars.bg, "BOTTOM", 0, 1) end
				if bars.aboveBarText then bars.aboveBarText:SetPoint("BOTTOM", bars.bg, "TOP", 0, 1) end
				if bars.belowBarText then bars.belowBarText:SetPoint("TOP", bars.bg, "BOTTOM", 0, -1) end
			elseif barPosition == "top" then
				-- Horizontal bar above the icon
				bars.bg:SetHeight(barSize)
				bars.bg:SetPoint("BOTTOMLEFT", totemButton, "TOPLEFT", 0, 1)
				bars.bg:SetPoint("BOTTOMRIGHT", totemButton, "TOPRIGHT", 0, 1)
				bars.bar:SetHeight(barSize)
				bars.bar:SetPoint("BOTTOMLEFT", totemButton, "TOPLEFT", 0, 1)
				if bars.insideTextTop then bars.insideTextTop:SetPoint("TOP", bars.bg, "TOP", 0, -1) end
				if bars.insideTextBottom then bars.insideTextBottom:SetPoint("BOTTOM", bars.bg, "BOTTOM", 0, 1) end
				if bars.aboveBarText then bars.aboveBarText:SetPoint("BOTTOM", bars.bg, "TOP", 0, 1) end
				if bars.belowBarText then bars.belowBarText:SetPoint("TOP", bars.bg, "BOTTOM", 0, -1) end
			elseif barPosition == "top_vert" then
				-- Vertical bar above the icon (centered)
				bars.bg:SetWidth(barSize)
				bars.bg:SetPoint("BOTTOM", totemButton, "TOP", 0, 1)
				bars.bg:SetHeight(totemButton:GetHeight())
				bars.bar:SetWidth(barSize)
				bars.bar:SetPoint("BOTTOM", bars.bg, "BOTTOM", 0, 0)
				if bars.insideTextTop then bars.insideTextTop:SetPoint("TOP", bars.bg, "TOP", 0, -1) end
				if bars.insideTextBottom then bars.insideTextBottom:SetPoint("BOTTOM", bars.bg, "BOTTOM", 0, 1) end
				if bars.aboveBarText then bars.aboveBarText:SetPoint("BOTTOM", bars.bg, "TOP", 0, 1) end
				if bars.belowBarText then bars.belowBarText:SetPoint("TOP", bars.bg, "BOTTOM", 0, -1) end
			elseif barPosition == "left" then
				-- Vertical bar to the left of the icon
				bars.bg:SetWidth(barSize)
				bars.bg:SetPoint("TOPRIGHT", totemButton, "TOPLEFT", -1, 0)
				bars.bg:SetPoint("BOTTOMRIGHT", totemButton, "BOTTOMLEFT", -1, 0)
				bars.bar:SetWidth(barSize)
				bars.bar:SetPoint("BOTTOMRIGHT", totemButton, "BOTTOMLEFT", -1, 0)
				if bars.insideTextTop then bars.insideTextTop:SetPoint("TOP", bars.bg, "TOP", 0, -1) end
				if bars.insideTextBottom then bars.insideTextBottom:SetPoint("BOTTOM", bars.bg, "BOTTOM", 0, 1) end
				if bars.aboveBarText then bars.aboveBarText:SetPoint("RIGHT", bars.bg, "LEFT", -1, 0) end
				if bars.belowBarText then bars.belowBarText:SetPoint("LEFT", bars.bg, "RIGHT", 1, 0) end
			elseif barPosition == "right" then
				-- Vertical bar to the right of the icon
				bars.bg:SetWidth(barSize)
				bars.bg:SetPoint("TOPLEFT", totemButton, "TOPRIGHT", 1, 0)
				bars.bg:SetPoint("BOTTOMLEFT", totemButton, "BOTTOMRIGHT", 1, 0)
				bars.bar:SetWidth(barSize)
				bars.bar:SetPoint("BOTTOMLEFT", totemButton, "BOTTOMRIGHT", 1, 0)
				if bars.insideTextTop then bars.insideTextTop:SetPoint("TOP", bars.bg, "TOP", 0, -1) end
				if bars.insideTextBottom then bars.insideTextBottom:SetPoint("BOTTOM", bars.bg, "BOTTOM", 0, 1) end
				if bars.aboveBarText then bars.aboveBarText:SetPoint("LEFT", bars.bg, "RIGHT", 1, 0) end
				if bars.belowBarText then bars.belowBarText:SetPoint("RIGHT", bars.bg, "LEFT", -1, 0) end
			end
		end
	end
end

-- Format duration time as M:SS or just seconds (with caching to avoid string garbage)
local FormatDurationCache = {}
local FormatDurationCacheSize = 0
local DURATION_CACHE_MAX = 500  -- Limit cache size to prevent unbounded growth

local function FormatDuration(seconds)
	local intSec = math.floor(seconds)
	if intSec < 0 then intSec = 0 end

	-- Check cache first
	local cached = FormatDurationCache[intSec]
	if cached then return cached end

	-- Generate formatted string
	local result
	if intSec >= 3600 then
		local hours = math.floor(intSec / 3600)
		result = hours .. "h"
	elseif intSec >= 600 then
		local mins = math.floor(intSec / 60)
		result = mins .. "m"
	elseif intSec >= 60 then
		local mins = math.floor(intSec / 60)
		local secs = intSec % 60
		if secs < 10 then
			result = mins .. ":0" .. secs
		else
			result = mins .. ":" .. secs
		end
	else
		result = tostring(intSec)
	end

	-- Cache the result (with size limit)
	if FormatDurationCacheSize < DURATION_CACHE_MAX then
		FormatDurationCache[intSec] = result
		FormatDurationCacheSize = FormatDurationCacheSize + 1
	end

	return result
end

-- Update progress bars based on totem duration
function ShamanPower:UpdateTotemProgressBars()
	local textLocation = self.opt.durationTextLocation or "none"
	local barPosition = self.opt.durationBarPosition or "bottom"
	local barSize = self.opt.durationBarHeight or 3
	local textSize = self.opt.durationTextSize or 8
	local barDisabled = (barPosition == "none")
	local isVertical = (barPosition == "left" or barPosition == "right" or barPosition == "top_vert" or barPosition == "bottom_vert")

	for element = 1, 4 do
		local bars = self.totemProgressBars[element]
		if bars then
			local slot = self.ElementToSlot[element]
			local haveTotem, totemName, startTime, duration = GetTotemInfo(slot)

			-- Check if the active totem is popped out as a single totem
			local totemIsPoppedOut = false
			if haveTotem and totemName then
				for key, popOutBars in pairs(self.poppedOutProgressBars or {}) do
					if popOutBars.element == element and popOutBars.spellName then
						local ok1, result1 = pcall(string.find, totemName, popOutBars.spellName, 1, true)
						local ok2, result2 = pcall(string.find, popOutBars.spellName, totemName, 1, true)
						if (ok1 and result1) or (ok2 and result2) then
							totemIsPoppedOut = true
							break
						end
					end
				end
			end

			-- If totem is popped out, hide main bar and let pop-out handle it
			if totemIsPoppedOut then
				bars.bg:Hide()
				bars.bar:Hide()
				if bars.insideTextTop then bars.insideTextTop:Hide() end
				if bars.insideTextBottom then bars.insideTextBottom:Hide() end
				if bars.aboveBarText then bars.aboveBarText:Hide() end
				if bars.belowBarText then bars.belowBarText:Hide() end
				if bars.iconText then bars.iconText:Hide() end
			elseif haveTotem and duration and duration > 0 then
				local remaining = (startTime + duration) - GetTime()
				local pct = remaining / duration

				if pct > 0 and pct <= 1 then
					-- Show/hide bars based on whether bar position is "none"
					if barDisabled then
						bars.bg:Hide()
						bars.bar:Hide()
					else
						-- Update bar size based on remaining time and orientation
						if isVertical then
							local height = (bars.maxHeight or 26) * pct
							bars.bar:SetHeight(math.max(1, height))
							bars.bar:SetWidth(barSize)
						else
							local width = (bars.maxWidth or 26) * pct
							bars.bar:SetWidth(math.max(1, width))
							bars.bar:SetHeight(barSize)
						end
						bars.bg:Show()
						bars.bar:Show()
					end

					-- Update duration text based on option
					local durationStr = FormatDuration(remaining)

					-- Hide all text elements first
					if bars.insideTextTop then bars.insideTextTop:Hide() end
					if bars.insideTextBottom then bars.insideTextBottom:Hide() end
					if bars.aboveBarText then bars.aboveBarText:Hide() end
					if bars.belowBarText then bars.belowBarText:Hide() end
					if bars.iconText then bars.iconText:Hide() end

					-- Show the appropriate text element (apply text size)
					if textLocation == "inside_top" then
						if bars.insideTextTop then
							bars.insideTextTop:SetFont("Fonts\\FRIZQT__.TTF", textSize, "OUTLINE")
							bars.insideTextTop:SetText(durationStr)
							bars.insideTextTop:Show()
						end
					elseif textLocation == "inside_bottom" then
						if bars.insideTextBottom then
							bars.insideTextBottom:SetFont("Fonts\\FRIZQT__.TTF", textSize, "OUTLINE")
							bars.insideTextBottom:SetText(durationStr)
							bars.insideTextBottom:Show()
						end
					elseif textLocation == "above" then
						if bars.aboveBarText then
							bars.aboveBarText:SetFont("Fonts\\FRIZQT__.TTF", textSize, "OUTLINE")
							bars.aboveBarText:SetText(durationStr)
							bars.aboveBarText:Show()
						end
					elseif textLocation == "below" then
						if bars.belowBarText then
							bars.belowBarText:SetFont("Fonts\\FRIZQT__.TTF", textSize, "OUTLINE")
							bars.belowBarText:SetText(durationStr)
							bars.belowBarText:Show()
						end
					elseif textLocation == "icon" then
						if bars.iconText then
							bars.iconText:SetFont("Fonts\\FRIZQT__.TTF", textSize, "OUTLINE")
							bars.iconText:SetText(durationStr)
							bars.iconText:Show()
						end
					end
				else
					bars.bg:Hide()
					bars.bar:Hide()
					if bars.insideTextTop then bars.insideTextTop:Hide() end
					if bars.insideTextBottom then bars.insideTextBottom:Hide() end
					if bars.aboveBarText then bars.aboveBarText:Hide() end
					if bars.belowBarText then bars.belowBarText:Hide() end
					if bars.iconText then bars.iconText:Hide() end
				end
			else
				bars.bg:Hide()
				bars.bar:Hide()
				if bars.insideTextTop then bars.insideTextTop:Hide() end
				if bars.insideTextBottom then bars.insideTextBottom:Hide() end
				if bars.aboveBarText then bars.aboveBarText:Hide() end
				if bars.belowBarText then bars.belowBarText:Hide() end
				if bars.iconText then bars.iconText:Hide() end
			end
		end
	end

	-- Update popped-out single totem progress bars
	self:UpdatePoppedOutProgressBars()

	-- Update active totem overlays
	self:UpdateActiveTotemOverlays()
end

-- Update progress bars on popped-out single totems
function ShamanPower:UpdatePoppedOutProgressBars()
	if not self.poppedOutProgressBars then return end

	local textLocation = self.opt.durationTextLocation or "none"
	local barSize = self.opt.durationBarHeight or 3

	for key, bars in pairs(self.poppedOutProgressBars) do
		local frame = self.poppedOutFrames[key]
		if frame and bars.element and bars.spellName then
			local slot = self.ElementToSlot[bars.element]
			local haveTotem, activeTotemName, startTime, duration = GetTotemInfo(slot)

			-- Check if this pop-out's totem is the active one
			local isActive = false
			if haveTotem and activeTotemName and bars.spellName then
				local ok1, result1 = pcall(string.find, activeTotemName, bars.spellName, 1, true)
				local ok2, result2 = pcall(string.find, bars.spellName, activeTotemName, 1, true)
				if (ok1 and result1) or (ok2 and result2) then
					isActive = true
				end
			end

			if isActive and duration and duration > 0 then
				local remaining = (startTime + duration) - GetTime()
				local pct = remaining / duration

				if pct > 0 and pct <= 1 then
					-- Update bar size
					local width = (bars.maxWidth or 32) * pct
					bars.bar:SetWidth(math.max(1, width))
					bars.bar:SetHeight(barSize)
					bars.bg:SetHeight(barSize)
					bars.bg:Show()
					bars.bar:Show()

					-- Update duration text if option is set to show on icon
					if textLocation == "icon" then
						local durationStr = FormatDuration(remaining)
						bars.text:SetText(durationStr)
						bars.text:Show()
					else
						bars.text:Hide()
					end
				else
					bars.bg:Hide()
					bars.bar:Hide()
					bars.text:Hide()
				end
			else
				bars.bg:Hide()
				bars.bar:Hide()
				bars.text:Hide()
			end
		end
	end
end

-- Update progress bar size when option changes
function ShamanPower:UpdateTotemProgressBarHeight()
	local barSize = self.opt.durationBarHeight or 3
	local barPosition = self.opt.durationBarPosition or "bottom"
	local isVertical = (barPosition == "left" or barPosition == "right" or barPosition == "top_vert" or barPosition == "bottom_vert")

	for element = 1, 4 do
		local bars = self.totemProgressBars[element]
		if bars then
			if isVertical then
				bars.bg:SetWidth(barSize)
				bars.bar:SetWidth(barSize)
			else
				bars.bg:SetHeight(barSize)
				bars.bar:SetHeight(barSize)
			end

			-- Update inside text font size based on bar size
			if bars.insideText then
				local fontSize = math.max(7, barSize - 2)
				bars.insideText:SetFont("Fonts\\FRIZQT__.TTF", fontSize, "OUTLINE")
			end
		end
	end

	-- Re-position bars to update anchors
	self:UpdateTotemProgressBarPositions()
end

-- ============================================================================
-- Active Totem Overlay (shows actual totem when different from assigned)
-- ============================================================================

ShamanPower.activeTotemOverlays = {}

function ShamanPower:CreateActiveTotemOverlay(element)
	local totemButton = self.totemButtons[element]
	if not totemButton then return nil end

	local overlay = {}

	-- Create a frame to hold the active totem icon (appears above the button)
	local frame = CreateFrame("Frame", "ShamanPowerActiveOverlay" .. element, totemButton)
	frame:SetSize(26, 26)
	frame:SetPoint("BOTTOM", totemButton, "TOP", 0, 2)
	frame:SetFrameLevel(totemButton:GetFrameLevel() + 5)
	frame:Hide()

	-- Background
	local bg = frame:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.7)
	overlay.bg = bg

	-- Icon for the active totem
	local icon = frame:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("TOPLEFT", 2, -2)
	icon:SetPoint("BOTTOMRIGHT", -2, 2)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	overlay.icon = icon

	-- Border with element color
	local colors = self.ElementColors[element]
	local borderSize = 2
	local r, g, b = colors.r, colors.g, colors.b

	local borderTop = frame:CreateTexture(nil, "BORDER")
	borderTop:SetPoint("TOPLEFT", 0, 0)
	borderTop:SetPoint("TOPRIGHT", 0, 0)
	borderTop:SetHeight(borderSize)
	borderTop:SetColorTexture(r, g, b, 1)

	local borderBottom = frame:CreateTexture(nil, "BORDER")
	borderBottom:SetPoint("BOTTOMLEFT", 0, 0)
	borderBottom:SetPoint("BOTTOMRIGHT", 0, 0)
	borderBottom:SetHeight(borderSize)
	borderBottom:SetColorTexture(r, g, b, 1)

	local borderLeft = frame:CreateTexture(nil, "BORDER")
	borderLeft:SetPoint("TOPLEFT", 0, 0)
	borderLeft:SetPoint("BOTTOMLEFT", 0, 0)
	borderLeft:SetWidth(borderSize)
	borderLeft:SetColorTexture(r, g, b, 1)

	local borderRight = frame:CreateTexture(nil, "BORDER")
	borderRight:SetPoint("TOPRIGHT", 0, 0)
	borderRight:SetPoint("BOTTOMRIGHT", 0, 0)
	borderRight:SetWidth(borderSize)
	borderRight:SetColorTexture(r, g, b, 1)

	-- Create pulse wipe frame on this frame
	local wipeFrame = CreateFrame("Frame", nil, frame)
	wipeFrame:SetFrameLevel(frame:GetFrameLevel() + 1)
	overlay.wipeFrame = wipeFrame

	local wipe = wipeFrame:CreateTexture(nil, "OVERLAY")
	wipe:SetColorTexture(1, 1, 1, 0.7)  -- White for visibility
	wipe:Hide()
	overlay.wipe = wipe
	overlay.buttonWidth = frame:GetWidth() - 4
	overlay.buttonHeight = frame:GetHeight() - 4

	-- Position the wipe based on option (will be called after creation)
	self:PositionOverlayPulseWipe(overlay, frame)

	-- Create pulse glow textures on this frame
	overlay.glows = {}
	for i = 1, 3 do
		local glow = frame:CreateTexture(nil, "OVERLAY", nil, 7)
		local offset = 6 + (i * 4)
		glow:SetPoint("TOPLEFT", frame, "TOPLEFT", -offset, offset)
		glow:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", offset, -offset)
		glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
		glow:SetBlendMode("ADD")
		glow:SetVertexColor(0.4, 1, 0.4)
		glow:SetAlpha(0)
		overlay.glows[i] = glow
	end

	-- Create range dots on this frame
	overlay.dots = {}
	for i = 1, 4 do
		local dot = frame:CreateTexture(nil, "OVERLAY")
		dot:SetTexture("Interface\\AddOns\\ShamanPower\\textures\\dot")
		dot:SetSize(5, 5)
		if i == 1 then
			dot:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
		elseif i == 2 then
			dot:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
		elseif i == 3 then
			dot:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, 1)
		else
			dot:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
		end
		dot:SetVertexColor(1, 1, 1)
		dot:Hide()
		overlay.dots[i] = dot
	end

	-- Create pulse time text elements (same as main pulse overlay)
	-- Time text inside the bar (top)
	local barTimeTextTop = wipeFrame:CreateFontString(nil, "OVERLAY")
	barTimeTextTop:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
	barTimeTextTop:SetPoint("TOP", wipeFrame, "TOP", 0, -1)
	barTimeTextTop:SetTextColor(1, 1, 1)
	barTimeTextTop:Hide()
	overlay.barTimeTextTop = barTimeTextTop

	-- Time text inside the bar (bottom)
	local barTimeTextBottom = wipeFrame:CreateFontString(nil, "OVERLAY")
	barTimeTextBottom:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
	barTimeTextBottom:SetPoint("BOTTOM", wipeFrame, "BOTTOM", 0, 1)
	barTimeTextBottom:SetTextColor(1, 1, 1)
	barTimeTextBottom:Hide()
	overlay.barTimeTextBottom = barTimeTextBottom

	-- Time text above the bar
	local aboveTimeText = wipeFrame:CreateFontString(nil, "OVERLAY")
	aboveTimeText:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
	aboveTimeText:SetPoint("BOTTOM", wipeFrame, "TOP", 0, 1)
	aboveTimeText:SetTextColor(1, 1, 1)
	aboveTimeText:Hide()
	overlay.aboveTimeText = aboveTimeText

	-- Time text below the bar
	local belowTimeText = wipeFrame:CreateFontString(nil, "OVERLAY")
	belowTimeText:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
	belowTimeText:SetPoint("TOP", wipeFrame, "BOTTOM", 0, -1)
	belowTimeText:SetTextColor(1, 1, 1)
	belowTimeText:Hide()
	overlay.belowTimeText = belowTimeText

	-- Time text on the icon
	local iconTimeText = frame:CreateFontString(nil, "OVERLAY")
	iconTimeText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
	iconTimeText:SetPoint("CENTER", frame, "CENTER", 0, 0)
	iconTimeText:SetTextColor(1, 1, 1)
	iconTimeText:Hide()
	overlay.iconTimeText = iconTimeText

	-- Helper to hide all time texts
	local function hideAllTimeTexts(ov)
		if ov.barTimeTextTop then ov.barTimeTextTop:Hide() end
		if ov.barTimeTextBottom then ov.barTimeTextBottom:Hide() end
		if ov.aboveTimeText then ov.aboveTimeText:Hide() end
		if ov.belowTimeText then ov.belowTimeText:Hide() end
		if ov.iconTimeText then ov.iconTimeText:Hide() end
	end

	-- UpdateTime method for active overlay
	overlay.UpdateTime = function(self, timeRemaining, displayOption)
		hideAllTimeTexts(self)
		if not displayOption or displayOption == "none" then return end

		local timeText = string.format("%.1f", timeRemaining)
		local textSize = ShamanPower.opt.pulseTextSize or 8

		if displayOption == "inside_top" then
			if self.barTimeTextTop then
				self.barTimeTextTop:SetFont("Fonts\\FRIZQT__.TTF", textSize, "OUTLINE")
				self.barTimeTextTop:SetText(timeText)
				self.barTimeTextTop:Show()
			end
		elseif displayOption == "inside_bottom" then
			if self.barTimeTextBottom then
				self.barTimeTextBottom:SetFont("Fonts\\FRIZQT__.TTF", textSize, "OUTLINE")
				self.barTimeTextBottom:SetText(timeText)
				self.barTimeTextBottom:Show()
			end
		elseif displayOption == "above" then
			if self.aboveTimeText then
				self.aboveTimeText:SetFont("Fonts\\FRIZQT__.TTF", textSize, "OUTLINE")
				self.aboveTimeText:SetText(timeText)
				self.aboveTimeText:Show()
			end
		elseif displayOption == "below" then
			if self.belowTimeText then
				self.belowTimeText:SetFont("Fonts\\FRIZQT__.TTF", textSize, "OUTLINE")
				self.belowTimeText:SetText(timeText)
				self.belowTimeText:Show()
			end
		elseif displayOption == "on_icon" then
			if self.iconTimeText then
				self.iconTimeText:SetFont("Fonts\\FRIZQT__.TTF", textSize, "OUTLINE")
				self.iconTimeText:SetText(timeText)
				self.iconTimeText:Show()
			end
		end
	end

	-- HideTime method for active overlay
	overlay.HideTime = function(self)
		hideAllTimeTexts(self)
	end

	overlay.frame = frame
	overlay.buttonHeight = frame:GetHeight() - 4
	return overlay
end

function ShamanPower:UpdateActiveTotemOverlays()
	-- Safety checks for early calls before addon is fully initialized
	if not self.player then return end
	if not self.ElementToSlot then return end
	if not self.Totems then return end
	if not ShamanPower_Assignments then return end

	local playerName = self.player
	local assignments = ShamanPower_Assignments[playerName]
	if not assignments then return end

	for element = 1, 4 do
		-- Create overlay if needed
		if not self.activeTotemOverlays[element] then
			self.activeTotemOverlays[element] = self:CreateActiveTotemOverlay(element)
		end

		local overlay = self.activeTotemOverlays[element]
		local slot = self.ElementToSlot[element]

		-- Only process if we have both overlay and slot
		if overlay and slot then
			local haveTotem, totemName, startTime, duration = GetTotemInfo(slot)

			-- Get assigned totem info
			local assignedIndex = assignments[element] or 0
			local assignedSpellID = nil
			local assignedName = nil
			if assignedIndex > 0 then
				assignedSpellID = self:GetTotemSpell(element, assignedIndex)
				if assignedSpellID then
					assignedName = GetSpellInfo(assignedSpellID)
				end
			end

			-- Get the main icon texture
			local totemBtn = self.totemButtons[element]
			local iconTexture = totemBtn and totemBtn.icon

			-- Check if active totem differs from assigned
			local showOverlay = false
			local activeIcon = nil

			if haveTotem and totemName and totemName ~= "" then
				-- Check if active totem matches assigned
				local matches = false

				-- Use pcall for string.find in case of pattern issues
				if assignedName then
					local ok1, result1 = pcall(string.find, totemName, assignedName, 1, true)
					local ok2, result2 = pcall(string.find, assignedName, totemName, 1, true)
					if (ok1 and result1) or (ok2 and result2) then
						matches = true
					end
				end

				-- Special case: totem twisting on Air
				if element == 4 and self.opt and self.opt.enableTotemTwisting then
					-- Twisting can have either Windfury or Grace of Air active
					if totemName:find("Windfury") or totemName:find("Grace of Air") then
						matches = true
					end
				end

				if not matches then
					-- Different totem is active - find its icon
					showOverlay = true
					-- Try to find the icon for the active totem
					local totems = self.Totems[element]
					if totems then
						for idx, totemSpellID in pairs(totems) do
							-- totemSpellID is directly the spell ID number
							if totemSpellID and type(totemSpellID) == "number" then
								local totemSpellName = GetSpellInfo(totemSpellID)
								if totemSpellName then
									local ok, found = pcall(string.find, totemName, totemSpellName, 1, true)
									if ok and found then
										activeIcon = self:GetTotemIcon(element, idx)
										break
									end
								end
							end
						end
					end
					-- Fallback: try to get icon from spell name directly
					if not activeIcon then
						local _, _, icon = GetSpellInfo(totemName)
						activeIcon = icon
					end
				end
			end

			local totemButton = self.totemButtons[element]
			local useActiveAsMain = self.opt.activeTotemAsMain

			if showOverlay and activeIcon then
				overlay.isActive = true

				if useActiveAsMain and totemButton then
					-- TotemTimers style: main icon shows active totem, corner shows assigned
					-- Hide the overlay frame (not needed in this mode)
					if overlay.frame then
						overlay.frame:Hide()
					end

					-- Change main button icon to active totem
					if iconTexture then
						iconTexture:SetTexture(activeIcon)
						iconTexture:SetDesaturated(false)
						iconTexture:SetAlpha(1)
					end

					-- Show assigned indicator in corner
					if totemButton.assignedIndicator and totemButton.assignedIndicatorIcon then
						local assignedIcon = self:GetTotemIcon(element, assignedIndex)
						if assignedIcon then
							totemButton.assignedIndicatorIcon:SetTexture(assignedIcon)
							totemButton.assignedIndicator:Show()
						end
					end

					-- Use main button's pulse overlay (not the overlay's)
					-- The pulse will show on the active totem icon
				else
					-- Classic style: overlay shows active totem above the button
					if overlay.frame then
						overlay.icon:SetTexture(activeIcon)
						overlay.frame:Show()
					end

					-- Grey out the assigned totem icon
					if iconTexture then
						iconTexture:SetDesaturated(true)
						iconTexture:SetAlpha(0.5)
					end

					-- Hide assigned indicator (not used in this mode)
					if totemButton and totemButton.assignedIndicator then
						totemButton.assignedIndicator:Hide()
					end

					-- Hide main button's pulse overlay (we'll use overlay's)
					if self.pulseOverlays and self.pulseOverlays[element] then
						local pulse = self.pulseOverlays[element]
						if pulse.wipe then pulse.wipe:Hide() end
						for _, glow in ipairs(pulse.glows or {}) do
							glow:SetAlpha(0)
						end
					end
				end

				-- Note: Range dots are handled by UpdatePartyRangeDots()
				-- which checks overlay.isActive and updates the correct dots
			else
				-- No active totem or same as assigned - restore normal state
				if overlay.frame then
					overlay.frame:Hide()
				end
				overlay.isActive = false

				-- Hide assigned indicator
				if totemButton and totemButton.assignedIndicator then
					totemButton.assignedIndicator:Hide()
				end

				-- Restore main button icon to assigned totem
				if useActiveAsMain and totemButton and iconTexture then
					local assignedIcon = self:GetTotemIcon(element, assignedIndex)
					if assignedIcon then
						iconTexture:SetTexture(assignedIcon)
					end
				end

				-- Hide overlay's dots and pulse
				if overlay.dots then
					for i = 1, 4 do
						if overlay.dots[i] then overlay.dots[i]:Hide() end
					end
				end
				if overlay.wipe then overlay.wipe:Hide() end
				if overlay.glows then
					for _, glow in ipairs(overlay.glows) do
						glow:SetAlpha(0)
					end
				end

				-- Don't reset desaturation here - let UpdatePlayerTotemRange handle it
				-- based on whether the player is in range of the totem buff
				if iconTexture then
					iconTexture:SetAlpha(1)  -- Only restore alpha, not desaturation
				end
			end
		end
	end

	-- Update active borders on popped-out single totems
	self:UpdatePoppedOutActiveBorders()
end

-- Update active borders on popped-out single totems
function ShamanPower:UpdatePoppedOutActiveBorders()
	if not self.poppedOutFrames then return end

	for key, frame in pairs(self.poppedOutFrames) do
		if key:match("^single_") and frame.element and frame.spellName then
			local element = frame.element
			local slot = self.ElementToSlot and self.ElementToSlot[element] or element
			local haveTotem, activeTotemName = GetTotemInfo(slot)

			local isActive = false
			if haveTotem and activeTotemName and frame.spellName then
				-- Check if active totem matches this pop-out's totem
				local ok1, result1 = pcall(string.find, activeTotemName, frame.spellName, 1, true)
				local ok2, result2 = pcall(string.find, frame.spellName, activeTotemName, 1, true)
				if (ok1 and result1) or (ok2 and result2) then
					isActive = true
				end
			end

			-- Show/hide active border
			if frame.activeBorder then
				if isActive then
					frame.activeBorder:Show()
				else
					frame.activeBorder:Hide()
				end
			end

			-- Desaturate/restore icon based on active state
			if frame.button and frame.button.icon then
				if isActive then
					frame.button.icon:SetDesaturated(false)
					frame.button.icon:SetAlpha(1)
				else
					-- Optionally desaturate when not active (matching main bar behavior)
					-- For now, keep it normal since it's a standalone tracker
					frame.button.icon:SetDesaturated(false)
					frame.button.icon:SetAlpha(1)
				end
			end
		end
	end
end

-- ============================================================================
-- Totem Flyout Menus (TotemTimers-style popup for selecting totems)
-- ============================================================================

ShamanPower.totemFlyouts = {}  -- Flyout frames for each element

-- Helper function to check if player knows a totem spell
-- Uses spellbook search since IsSpellKnown doesn't work reliably in Classic
local function PlayerKnowsTotem(spellID, totemName)
	if not spellID then return false end

	-- First try GetSpellInfo - if it returns nil, the spell doesn't exist
	local spellName = GetSpellInfo(spellID)

	-- Build a list of names to search for
	local searchNames = {}
	if spellName then
		table.insert(searchNames, spellName)
	end
	if totemName then
		table.insert(searchNames, totemName)
		-- Also try with " Totem" suffix removed/added
		if totemName:find(" Totem$") then
			table.insert(searchNames, totemName:gsub(" Totem$", ""))
		else
			table.insert(searchNames, totemName .. " Totem")
		end
	end

	if #searchNames == 0 then return false end

	-- Search the spellbook for this spell
	local i = 1
	while true do
		local bookName, bookSubName = GetSpellBookItemName(i, BOOKTYPE_SPELL)
		if not bookName then break end

		for _, searchName in ipairs(searchNames) do
			-- Check for exact match
			if bookName == searchName then
				return true
			end
			-- Check if spellbook entry starts with our search name (handles ranks)
			if bookName:find("^" .. searchName:gsub("([%(%)%.%%%+%-%*%?%[%^%$])", "%%%1")) then
				return true
			end
		end

		i = i + 1
	end

	return false
end

-- Track if we've already hooked the totem buttons
ShamanPower.flyoutHooksInstalled = {}

-- ============================================================================
-- POP-OUT TRACKERS
-- Allow any button to be "popped out" into a standalone, movable tracker
-- ============================================================================

-- Storage for popped-out frames by key
ShamanPower.poppedOutFrames = {}

-- Storage for pop-out pulse/active overlays (for single totem pop-outs)
ShamanPower.poppedOutOverlays = {}

-- Storage for pop-out duration bars (for single totem pop-outs)
ShamanPower.poppedOutProgressBars = {}

-- Create a pop-out frame container with cog wheel (top-right) and title below icon
function ShamanPower:CreatePopOutFrame(key, buttonSize, title)
	-- key: "totem_earth", "single_1_3", "cd_1", etc.
	if self.poppedOutFrames[key] then
		return self.poppedOutFrames[key]
	end

	local frameWidth = buttonSize + 20
	local titleHeight = 14
	local cogSize = 12
	local frameHeight = buttonSize + titleHeight + cogSize + 12

	local frame = CreateFrame("Frame", "ShamanPowerPopOut_" .. key, UIParent, "BackdropTemplate")
	frame:SetSize(frameWidth, frameHeight)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:SetClampedToScreen(true)
	frame:RegisterForDrag("LeftButton")
	frame.key = key
	frame.buttonSize = buttonSize
	frame.title = title

	-- Background frame
	frame:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 12,
		insets = { left = 2, right = 2, top = 2, bottom = 2 }
	})
	frame:SetBackdropColor(0, 0, 0, 0.8)
	frame:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

	-- Cog wheel settings button (top-right corner)
	local cogBtn = CreateFrame("Button", frame:GetName() .. "Cog", frame)
	cogBtn:SetSize(cogSize, cogSize)
	cogBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
	cogBtn:SetNormalTexture("Interface\\WorldMap\\Gear_64")
	cogBtn:GetNormalTexture():SetTexCoord(0, 0.5, 0, 0.5)
	cogBtn:SetHighlightTexture("Interface\\WorldMap\\Gear_64")
	cogBtn:GetHighlightTexture():SetTexCoord(0, 0.5, 0, 0.5)
	cogBtn:SetScript("OnClick", function()
		ShamanPower:ShowPopOutSettingsPanel(key, frame)
	end)
	cogBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Settings")
		GameTooltip:Show()
	end)
	cogBtn:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	frame.cogBtn = cogBtn

	-- Title text (below where the icon will be placed)
	local titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	titleText:SetPoint("BOTTOM", frame, "BOTTOM", 0, 4)
	titleText:SetText(title or "Pop-Out")
	titleText:SetTextColor(1, 0.82, 0)  -- Gold color
	frame.titleText = titleText

	-- Restore position or default to center
	local pos = self.opt.poppedOutPositions and self.opt.poppedOutPositions[key]
	if pos then
		frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
	else
		frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	end

	-- Apply scale/opacity from settings
	local settings = self.opt.poppedOutSettings and self.opt.poppedOutSettings[key] or {}
	local scale = settings.scale or self.opt.poppedOutDefaultScale or 1.0
	local opacity = settings.opacity or self.opt.poppedOutDefaultOpacity or 1.0
	frame:SetScale(scale)
	frame:SetAlpha(opacity)

	-- Check if frame should be hidden (show only icon)
	local hideFrame = settings.hideFrame
	if hideFrame then
		frame:SetBackdrop(nil)
		titleText:Hide()
		cogBtn:Hide()
	end

	-- Drag to move (no ALT needed - drag from title area or frame edge)
	frame:SetScript("OnDragStart", function(self)
		if self:IsMovable() then self:StartMoving() end
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		ShamanPower.opt.poppedOutPositions = ShamanPower.opt.poppedOutPositions or {}
		ShamanPower.opt.poppedOutPositions[key] = {point=point, relPoint=relPoint, x=x, y=y}
	end)

	-- Middle-click on frame to return to bar
	frame:SetScript("OnMouseUp", function(self, button)
		if button == "MiddleButton" then
			if InCombatLockdown() then
				print("|cffff0000ShamanPower:|r Cannot modify pop-outs during combat")
				return
			end
			ShamanPower:ReturnPopOutToBar(key)
		end
	end)

	self.poppedOutFrames[key] = frame
	return frame
end

-- Settings panel for pop-out frames (with sliders)
ShamanPower.popOutSettingsPanel = nil

function ShamanPower:ShowPopOutSettingsPanel(key, popOutFrame)
	-- Close existing panel if open for different key
	if self.popOutSettingsPanel and self.popOutSettingsPanel:IsShown() then
		if self.popOutSettingsPanel.currentKey == key then
			-- Don't close if we just opened it (debounce for double-click events)
			local openTime = self.popOutSettingsPanel.openTime or 0
			if GetTime() - openTime < 0.3 then
				return  -- Too soon, ignore this toggle
			end
			self.popOutSettingsPanel:Hide()
			return
		end
		self.popOutSettingsPanel:Hide()
	end

	-- Create panel if it doesn't exist
	if not self.popOutSettingsPanel then
		local panel = CreateFrame("Frame", "ShamanPowerPopOutSettingsPanel", UIParent, "BackdropTemplate")
		panel:SetSize(180, 200)  -- Taller to fit flyout direction option
		panel:SetFrameStrata("DIALOG")
		panel:SetMovable(true)
		panel:EnableMouse(true)
		panel:SetClampedToScreen(true)
		panel:RegisterForDrag("LeftButton")
		panel:SetScript("OnDragStart", panel.StartMoving)
		panel:SetScript("OnDragStop", panel.StopMovingOrSizing)

		panel:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 }
		})
		panel:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
		panel:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

		-- Title
		local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		title:SetPoint("TOP", panel, "TOP", 0, -8)
		title:SetText("Pop-Out Settings")
		title:SetTextColor(1, 0.82, 0)
		panel.title = title

		-- Close button
		local closeBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
		closeBtn:SetSize(20, 20)
		closeBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -2, -2)

		-- Scale slider
		local scaleLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		scaleLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -28)
		scaleLabel:SetText("Scale:")

		local scaleValue = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		scaleValue:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, -28)
		panel.scaleValue = scaleValue

		local scaleSlider = CreateFrame("Slider", "ShamanPowerPopOutScaleSlider", panel, "OptionsSliderTemplate")
		scaleSlider:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -42)
		scaleSlider:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, -42)
		scaleSlider:SetHeight(17)
		scaleSlider:SetMinMaxValues(0.5, 3.0)
		scaleSlider:SetValueStep(0.05)
		scaleSlider:SetObeyStepOnDrag(true)
		scaleSlider.Low:SetText("50%")
		scaleSlider.High:SetText("300%")
		scaleSlider.Text:SetText("")
		-- Add visible track background
		local scaleBg = scaleSlider:CreateTexture(nil, "BACKGROUND")
		scaleBg:SetPoint("TOPLEFT", scaleSlider, "TOPLEFT", 0, -5)
		scaleBg:SetPoint("BOTTOMRIGHT", scaleSlider, "BOTTOMRIGHT", 0, 5)
		scaleBg:SetColorTexture(0.3, 0.3, 0.3, 0.8)
		local scaleBorder = scaleSlider:CreateTexture(nil, "BORDER")
		scaleBorder:SetPoint("TOPLEFT", scaleBg, "TOPLEFT", -1, 1)
		scaleBorder:SetPoint("BOTTOMRIGHT", scaleBg, "BOTTOMRIGHT", 1, -1)
		scaleBorder:SetColorTexture(0.5, 0.5, 0.5, 1)
		scaleSlider:SetScript("OnValueChanged", function(self, value)
			value = math.floor(value * 20 + 0.5) / 20  -- Round to nearest 0.05
			panel.scaleValue:SetText(math.floor(value * 100) .. "%")
			if panel.currentKey then
				ShamanPower:SetPopOutScale(panel.currentKey, value)
			end
		end)
		panel.scaleSlider = scaleSlider

		-- Opacity slider
		local opacityLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		opacityLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -70)
		opacityLabel:SetText("Opacity:")

		local opacityValue = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		opacityValue:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, -70)
		panel.opacityValue = opacityValue

		local opacitySlider = CreateFrame("Slider", "ShamanPowerPopOutOpacitySlider", panel, "OptionsSliderTemplate")
		opacitySlider:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -84)
		opacitySlider:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, -84)
		opacitySlider:SetHeight(17)
		opacitySlider:SetMinMaxValues(0.1, 1.0)
		opacitySlider:SetValueStep(0.05)
		opacitySlider:SetObeyStepOnDrag(true)
		opacitySlider.Low:SetText("10%")
		opacitySlider.High:SetText("100%")
		opacitySlider.Text:SetText("")
		-- Add visible track background
		local opacityBg = opacitySlider:CreateTexture(nil, "BACKGROUND")
		opacityBg:SetPoint("TOPLEFT", opacitySlider, "TOPLEFT", 0, -5)
		opacityBg:SetPoint("BOTTOMRIGHT", opacitySlider, "BOTTOMRIGHT", 0, 5)
		opacityBg:SetColorTexture(0.3, 0.3, 0.3, 0.8)
		local opacityBorder = opacitySlider:CreateTexture(nil, "BORDER")
		opacityBorder:SetPoint("TOPLEFT", opacityBg, "TOPLEFT", -1, 1)
		opacityBorder:SetPoint("BOTTOMRIGHT", opacityBg, "BOTTOMRIGHT", 1, -1)
		opacityBorder:SetColorTexture(0.5, 0.5, 0.5, 1)
		opacitySlider:SetScript("OnValueChanged", function(self, value)
			value = math.floor(value * 20 + 0.5) / 20  -- Round to nearest 0.05
			panel.opacityValue:SetText(math.floor(value * 100) .. "%")
			if panel.currentKey then
				ShamanPower:SetPopOutOpacity(panel.currentKey, value)
			end
		end)
		panel.opacitySlider = opacitySlider

		-- Hide Frame checkbox
		local hideFrameCheck = CreateFrame("CheckButton", "ShamanPowerPopOutHideFrameCheck", panel, "UICheckButtonTemplate")
		hideFrameCheck:SetSize(22, 22)
		hideFrameCheck:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -108)
		hideFrameCheck.text = hideFrameCheck:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		hideFrameCheck.text:SetPoint("LEFT", hideFrameCheck, "RIGHT", 2, 0)
		hideFrameCheck.text:SetText("Hide Frame (icon only)")
		hideFrameCheck:SetScript("OnClick", function(self)
			if panel.currentKey then
				ShamanPower:TogglePopOutFrame(panel.currentKey)
			end
		end)
		panel.hideFrameCheck = hideFrameCheck

		-- Flyout Direction section (only for element pop-outs)
		local flyoutLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		flyoutLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -132)
		flyoutLabel:SetText("Flyout Direction:")
		panel.flyoutLabel = flyoutLabel

		-- Create direction buttons
		local directions = {"Top", "Bottom", "Left", "Right"}
		local dirButtons = {}
		local btnWidth = 38
		local btnSpacing = 2
		local startX = 12

		for i, dir in ipairs(directions) do
			local btn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
			btn:SetSize(btnWidth, 18)
			btn:SetPoint("TOPLEFT", panel, "TOPLEFT", startX + (i-1) * (btnWidth + btnSpacing), -145)
			btn:SetText(dir)
			btn:GetFontString():SetFont("Fonts\\FRIZQT__.TTF", 9)
			btn.direction = dir:lower()
			btn:SetScript("OnClick", function(self)
				if panel.currentKey then
					ShamanPower:SetPopOutFlyoutDirection(panel.currentKey, self.direction)
					-- Update button highlights
					for _, b in ipairs(dirButtons) do
						if b.direction == self.direction then
							b:SetNormalFontObject("GameFontHighlight")
						else
							b:SetNormalFontObject("GameFontNormalSmall")
						end
					end
				end
			end)
			dirButtons[i] = btn
		end
		panel.flyoutDirButtons = dirButtons

		-- Return to Bar button
		local returnBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
		returnBtn:SetSize(120, 22)
		returnBtn:SetPoint("BOTTOM", panel, "BOTTOM", 0, 8)
		returnBtn:SetText("Return to Bar")
		returnBtn:SetScript("OnClick", function()
			if panel.currentKey then
				panel:Hide()
				ShamanPower:ReturnPopOutToBar(panel.currentKey)
			end
		end)
		panel.returnBtn = returnBtn

		self.popOutSettingsPanel = panel
	end

	local panel = self.popOutSettingsPanel
	panel.currentKey = key

	-- Get current settings
	local settings = self.opt.poppedOutSettings and self.opt.poppedOutSettings[key] or {}
	local currentScale = settings.scale or self.opt.poppedOutDefaultScale or 1.0
	local currentOpacity = settings.opacity or self.opt.poppedOutDefaultOpacity or 1.0
	local currentHideFrame = settings.hideFrame or false
	local currentFlyoutDir = settings.flyoutDirection or "bottom"

	-- Update controls
	panel.scaleSlider:SetValue(currentScale)
	panel.scaleValue:SetText(math.floor(currentScale * 100) .. "%")
	panel.opacitySlider:SetValue(currentOpacity)
	panel.opacityValue:SetText(math.floor(currentOpacity * 100) .. "%")
	panel.hideFrameCheck:SetChecked(currentHideFrame)

	-- Show/hide flyout direction option (only for element pop-outs)
	local isElementPopOut = key:match("^totem_") ~= nil
	if panel.flyoutLabel then
		if isElementPopOut then
			panel.flyoutLabel:Show()
			for _, btn in ipairs(panel.flyoutDirButtons) do
				btn:Show()
				-- Highlight current direction
				if btn.direction == currentFlyoutDir then
					btn:SetNormalFontObject("GameFontHighlight")
				else
					btn:SetNormalFontObject("GameFontNormalSmall")
				end
			end
			panel:SetHeight(200)
		else
			panel.flyoutLabel:Hide()
			for _, btn in ipairs(panel.flyoutDirButtons) do
				btn:Hide()
			end
			panel:SetHeight(160)
		end
	end

	-- Position near the pop-out frame
	panel:ClearAllPoints()
	panel:SetPoint("TOPLEFT", popOutFrame, "TOPRIGHT", 5, 0)

	panel.openTime = GetTime()  -- Track when opened for debounce
	panel:Show()
end

-- Set scale for a pop-out frame
function ShamanPower:SetPopOutScale(key, scale)
	local frame = self.poppedOutFrames[key]
	if frame then
		-- Get current center position before scaling
		local oldScale = frame:GetScale()
		local centerX, centerY = frame:GetCenter()
		if centerX and centerY then
			-- Convert to screen coordinates
			centerX = centerX * oldScale
			centerY = centerY * oldScale

			-- Apply new scale
			frame:SetScale(scale)

			-- Reposition so center stays in same place
			frame:ClearAllPoints()
			frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", centerX / scale, centerY / scale)

			-- Save new position
			local point, _, relPoint, x, y = frame:GetPoint()
			self.opt.poppedOutPositions = self.opt.poppedOutPositions or {}
			self.opt.poppedOutPositions[key] = {point=point, relPoint=relPoint, x=x, y=y}
		else
			frame:SetScale(scale)
		end
	end
	self.opt.poppedOutSettings = self.opt.poppedOutSettings or {}
	self.opt.poppedOutSettings[key] = self.opt.poppedOutSettings[key] or {}
	self.opt.poppedOutSettings[key].scale = scale
end

-- Set opacity for a pop-out frame
function ShamanPower:SetPopOutOpacity(key, opacity)
	local frame = self.poppedOutFrames[key]
	if frame then
		frame:SetAlpha(opacity)
	end
	self.opt.poppedOutSettings = self.opt.poppedOutSettings or {}
	self.opt.poppedOutSettings[key] = self.opt.poppedOutSettings[key] or {}
	self.opt.poppedOutSettings[key].opacity = opacity
end

-- Set flyout direction for a popped-out element
function ShamanPower:SetPopOutFlyoutDirection(key, direction)
	self.opt.poppedOutSettings = self.opt.poppedOutSettings or {}
	self.opt.poppedOutSettings[key] = self.opt.poppedOutSettings[key] or {}
	self.opt.poppedOutSettings[key].flyoutDirection = direction

	-- Get element from key and re-layout flyout
	local elementName = key:match("^totem_(.+)$")
	if elementName then
		local element = self.ElementToID[elementName:upper()]
		if element and self.totemFlyouts[element] then
			self:LayoutFlyoutButtons(self.totemFlyouts[element])
		end
	end
end

-- Toggle frame visibility (show only icon or full frame)
function ShamanPower:TogglePopOutFrame(key)
	self.opt.poppedOutSettings = self.opt.poppedOutSettings or {}
	self.opt.poppedOutSettings[key] = self.opt.poppedOutSettings[key] or {}

	local settings = self.opt.poppedOutSettings[key]
	settings.hideFrame = not settings.hideFrame

	local frame = self.poppedOutFrames[key]
	if frame then
		if settings.hideFrame then
			-- Hide frame decorations, show only icon
			frame:SetBackdrop(nil)
			if frame.titleText then frame.titleText:Hide() end
			if frame.cogBtn then frame.cogBtn:Hide() end
			-- Resize to just fit the button
			frame:SetSize(frame.buttonSize + 4, frame.buttonSize + 4)
			-- Reposition button
			if frame.button then
				frame.button:ClearAllPoints()
				frame.button:SetPoint("CENTER", frame, "CENTER", 0, 0)
			end
		else
			-- Show full frame with decorations
			frame:SetBackdrop({
				bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
				edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
				tile = true, tileSize = 16, edgeSize = 12,
				insets = { left = 2, right = 2, top = 2, bottom = 2 }
			})
			frame:SetBackdropColor(0, 0, 0, 0.8)
			frame:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
			if frame.titleText then frame.titleText:Show() end
			if frame.cogBtn then frame.cogBtn:Show() end
			-- Resize to full size (cog at top, icon in middle, title at bottom)
			local titleHeight = 14
			local cogSize = 12
			frame:SetSize(frame.buttonSize + 20, frame.buttonSize + titleHeight + cogSize + 12)
			-- Reposition button (center, slightly above bottom to make room for title)
			if frame.button then
				frame.button:ClearAllPoints()
				frame.button:SetPoint("CENTER", frame, "CENTER", 0, 2)
			end
		end
	end

	-- Update the settings panel checkbox if it's open for this key
	if self.popOutSettingsPanel and self.popOutSettingsPanel:IsShown() and self.popOutSettingsPanel.currentKey == key then
		self.popOutSettingsPanel.hideFrameCheck:SetChecked(settings.hideFrame)
	end
end

-- Pop out a single totem from a flyout
function ShamanPower:PopOutSingleTotem(element, totemIndex)
	local key = "single_" .. element .. "_" .. totemIndex
	if self.opt.poppedOut and self.opt.poppedOut[key] then return end  -- Already popped

	self.opt.poppedOut = self.opt.poppedOut or {}
	self.opt.poppedOut[key] = true

	-- Get totem spell info
	local spellID = self:GetTotemSpell(element, totemIndex)
	local spellName = spellID and GetSpellInfo(spellID)
	local icon = self:GetTotemIcon(element, totemIndex)
	local totemName = self:GetTotemName(element, totemIndex) or "Totem"

	-- Create frame with title
	local frame = self:CreatePopOutFrame(key, 32, totemName)

	-- Create a visible icon holder frame for the icon and all visual effects
	local iconHolder = CreateFrame("Frame", frame:GetName() .. "IconHolder", frame)
	iconHolder:SetSize(32, 32)
	iconHolder:SetPoint("CENTER", frame, "CENTER", 0, 2)
	frame.iconHolder = iconHolder

	-- Create the icon texture on the holder
	local iconTex = iconHolder:CreateTexture(nil, "ARTWORK")
	iconTex:SetAllPoints()
	iconTex:SetTexture(icon)
	iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	frame.iconTex = iconTex
	iconHolder.icon = iconTex

	-- Create invisible secure button on top for click handling only
	local btn = CreateFrame("Button", frame:GetName() .. "Btn", frame,
		"SecureActionButtonTemplate, SecureHandlerEnterLeaveTemplate")
	btn:SetSize(32, 32)
	btn:SetPoint("CENTER", frame, "CENTER", 0, 2)
	btn:SetFrameLevel(iconHolder:GetFrameLevel() + 10)  -- Make sure it's on top
	btn:RegisterForClicks("AnyUp", "AnyDown")
	btn:SetAlpha(0)  -- Invisible - just handles clicks
	btn.icon = iconTex  -- Reference the separate texture

	-- Set up spell casting
	if spellName then
		btn:SetAttribute("type1", "spell")
		btn:SetAttribute("spell1", spellName)
	end

	-- Right-click to cast Totemic Call (destroys all totems)
	btn:SetAttribute("type2", "spell")
	btn:SetAttribute("spell2", GetSpellInfo(36936))  -- Totemic Call

	-- Tooltip
	btn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if spellID then
			GameTooltip:SetSpellByID(spellID)
		end
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("|cff00ff00Middle-click:|r Return to bar", 1, 1, 1)
		GameTooltip:AddLine("|cff00ff00SHIFT+Middle-click:|r Settings", 1, 1, 1)
		GameTooltip:AddLine("|cff00ff00ALT+drag:|r Move (when frame hidden)", 1, 1, 1)
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	-- Middle-click handler on button (SHIFT = settings, plain = return to bar)
	btn:HookScript("OnClick", function(self, button)
		if button == "MiddleButton" then
			if IsShiftKeyDown() then
				-- SHIFT+Middle-click opens settings
				ShamanPower:ShowPopOutSettingsPanel(key, frame)
			else
				-- Plain middle-click returns to bar
				if InCombatLockdown() then
					print("|cffff0000ShamanPower:|r Cannot modify pop-outs during combat")
					return
				end
				ShamanPower:ReturnPopOutToBar(key)
			end
		end
	end)

	-- ALT+drag on button to move frame (works when frame is hidden)
	btn:RegisterForDrag("LeftButton")
	btn:SetScript("OnDragStart", function(self)
		if IsAltKeyDown() and frame:IsMovable() then
			frame:StartMoving()
		end
	end)
	btn:SetScript("OnDragStop", function(self)
		frame:StopMovingOrSizing()
		local point, _, relPoint, x, y = frame:GetPoint()
		ShamanPower.opt.poppedOutPositions = ShamanPower.opt.poppedOutPositions or {}
		ShamanPower.opt.poppedOutPositions[key] = {point=point, relPoint=relPoint, x=x, y=y}
	end)

	-- Store references
	frame.button = btn
	frame.element = element
	frame.totemIndex = totemIndex
	frame.spellID = spellID
	frame.spellName = spellName

	-- Create pulse overlay on the visible iconHolder (Earth and Water totems can pulse)
	if element == 1 or element == 3 then
		local pulseOverlay = self:CreatePulseOverlay(iconHolder)
		if pulseOverlay then
			self.poppedOutOverlays[key] = pulseOverlay
			pulseOverlay.element = element
			pulseOverlay.totemIndex = totemIndex
			pulseOverlay.spellID = spellID
			pulseOverlay.spellName = spellName
			-- Position the wipe properly for this button
			self:PositionPulseWipe(pulseOverlay)
		end
	end

	-- DISABLED: Active border causes a visual box artifact inside the icon
	-- The UI-ActionButton-Border texture has inner content that shows through
	--[[
	-- Create active totem border on iconHolder (shows when this totem is placed)
	local activeBorder = iconHolder:CreateTexture(nil, "OVERLAY")
	activeBorder:SetPoint("TOPLEFT", iconHolder, "TOPLEFT", -2, 2)
	activeBorder:SetPoint("BOTTOMRIGHT", iconHolder, "BOTTOMRIGHT", 2, -2)
	activeBorder:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
	activeBorder:SetBlendMode("ADD")
	local colors = self.ElementColors[element]
	activeBorder:SetVertexColor(colors.r, colors.g, colors.b, 0.8)
	activeBorder:Hide()
	frame.activeBorder = activeBorder
	--]]
	frame.activeBorder = nil

	-- Create duration bar on iconHolder (same style as main totem bars)
	local barColors = self.DurationBarColors[element]
	local barSize = self.opt.durationBarHeight or 3

	-- Background bar
	local bgBar = iconHolder:CreateTexture(nil, "OVERLAY")
	bgBar:SetColorTexture(0, 0, 0, 0.7)
	bgBar:SetPoint("BOTTOMLEFT", iconHolder, "BOTTOMLEFT", 0, 0)
	bgBar:SetPoint("BOTTOMRIGHT", iconHolder, "BOTTOMRIGHT", 0, 0)
	bgBar:SetHeight(barSize)
	bgBar:Hide()

	-- Progress bar
	local progressBar = iconHolder:CreateTexture(nil, "OVERLAY", nil, 1)
	progressBar:SetColorTexture(barColors[1], barColors[2], barColors[3], 1)
	progressBar:SetPoint("BOTTOMLEFT", iconHolder, "BOTTOMLEFT", 0, 0)
	progressBar:SetHeight(barSize)
	progressBar:SetWidth(1)
	progressBar:Hide()

	-- Duration text on icon
	local durationText = iconHolder:CreateFontString(nil, "OVERLAY")
	durationText:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
	durationText:SetPoint("CENTER", iconHolder, "CENTER", 0, 0)
	durationText:SetTextColor(1, 1, 1)
	durationText:Hide()

	self.poppedOutProgressBars[key] = {
		bg = bgBar,
		bar = progressBar,
		text = durationText,
		maxWidth = iconHolder:GetWidth(),
		element = element,
		spellName = spellName
	}

	-- Check if frame should be hidden based on saved settings
	local settings = self.opt.poppedOutSettings and self.opt.poppedOutSettings[key] or {}
	if settings.hideFrame then
		self:TogglePopOutFrame(key)  -- Apply hide
		self:TogglePopOutFrame(key)  -- Toggle back since it was already set
		-- Actually just apply the hidden state directly
		frame:SetBackdrop(nil)
		if frame.titleText then frame.titleText:Hide() end
		if frame.cogBtn then frame.cogBtn:Hide() end
		frame:SetSize(frame.buttonSize + 4, frame.buttonSize + 4)
		iconHolder:ClearAllPoints()
		iconHolder:SetPoint("CENTER", frame, "CENTER", 0, 0)
		btn:ClearAllPoints()
		btn:SetPoint("CENTER", frame, "CENTER", 0, 0)
	end

	-- Update main bar to hide this from flyout
	self:UpdateFlyoutVisibility(element)

	frame:Show()
end

-- Pop out an entire element with its flyout
function ShamanPower:PopOutElementWithFlyout(element)
	local elementName = self.Elements[element]:lower()  -- "earth", "fire", "water", "air"
	local key = "totem_" .. elementName
	if self.opt.poppedOut and self.opt.poppedOut[key] then return end

	self.opt.poppedOut = self.opt.poppedOut or {}
	self.opt.poppedOut[key] = true

	-- Get element display name
	local displayName = self.Elements[element]  -- "EARTH", "FIRE", etc.
	displayName = displayName:sub(1,1) .. displayName:sub(2):lower()  -- "Earth", "Fire", etc.

	-- Create frame with title
	local frame = self:CreatePopOutFrame(key, 28, displayName)

	-- Get the existing totem button
	local totemBtn = self.totemButtons[element]
	if not totemBtn then return end

	-- Store original parent and points for restoration
	frame.originalParent = totemBtn:GetParent()
	frame.originalPoints = {}
	for i = 1, totemBtn:GetNumPoints() do
		frame.originalPoints[i] = {totemBtn:GetPoint(i)}
	end

	-- Reparent the totem button to this frame
	totemBtn:SetParent(frame)
	totemBtn:ClearAllPoints()
	totemBtn:SetPoint("CENTER", frame, "CENTER", 0, 2)  -- Slightly above center to leave room for title below
	totemBtn:SetScale(1)  -- Reset scale since frame handles it

	-- Flyout buttons are children of totemBtn, so they move with it

	frame.totemButton = totemBtn
	frame.button = totemBtn  -- For TogglePopOutFrame compatibility
	frame.element = element

	-- ALT+drag on totem button to move frame (works when frame is hidden)
	totemBtn:RegisterForDrag("LeftButton")
	totemBtn:HookScript("OnDragStart", function(self)
		if IsAltKeyDown() then
			frame:StartMoving()
		end
	end)
	totemBtn:HookScript("OnDragStop", function(self)
		frame:StopMovingOrSizing()
		local point, _, relPoint, x, y = frame:GetPoint()
		ShamanPower.opt.poppedOutPositions = ShamanPower.opt.poppedOutPositions or {}
		ShamanPower.opt.poppedOutPositions[key] = {point=point, relPoint=relPoint, x=x, y=y}
	end)

	-- Note: SHIFT+Middle-click for settings is handled by the main totem button OnClick handler

	-- Check if frame should be hidden based on saved settings
	local settings = self.opt.poppedOutSettings and self.opt.poppedOutSettings[key] or {}
	if settings.hideFrame then
		frame:SetBackdrop(nil)
		if frame.titleText then frame.titleText:Hide() end
		if frame.cogBtn then frame.cogBtn:Hide() end
		frame:SetSize(frame.buttonSize + 4, frame.buttonSize + 4)
		totemBtn:ClearAllPoints()
		totemBtn:SetPoint("CENTER", frame, "CENTER", 0, 0)
	end

	-- Update main bar layout (skip this element)
	self:UpdateMiniTotemBar()
	self:UpdateTotemButtons()

	frame:Show()
end

-- Cooldown type names for display
local CooldownTypeNames = {
	[1] = "Shield",
	[2] = "Recall",
	[3] = "Ankh",
	[4] = "NS",
	[5] = "Mana Tide",
	[6] = "Bloodlust",
	[7] = "Imbue",
}

-- Pop out a cooldown bar item
function ShamanPower:PopOutCooldownItem(cooldownType)
	local key = "cd_" .. cooldownType
	if self.opt.poppedOut and self.opt.poppedOut[key] then return end

	self.opt.poppedOut = self.opt.poppedOut or {}
	self.opt.poppedOut[key] = true

	-- Find the button
	local btn = nil
	for _, b in ipairs(self.cooldownButtons) do
		if b.cooldownType == cooldownType then
			btn = b
			break
		end
	end
	if not btn then return end

	-- Get display name
	local displayName = CooldownTypeNames[cooldownType] or "Cooldown"

	-- Create frame with title
	local buttonSize = btn:GetWidth() or 22
	local frame = self:CreatePopOutFrame(key, buttonSize, displayName)

	-- Store original parent and points for restoration
	frame.originalParent = btn:GetParent()
	frame.originalPoints = {}
	for i = 1, btn:GetNumPoints() do
		frame.originalPoints[i] = {btn:GetPoint(i)}
	end

	-- Reparent button
	btn:SetParent(frame)
	btn:ClearAllPoints()
	btn:SetPoint("CENTER", frame, "CENTER", 0, 2)  -- Slightly above center to leave room for title below

	frame.cooldownButton = btn
	frame.button = btn  -- For TogglePopOutFrame compatibility
	frame.cooldownType = cooldownType

	-- ALT+drag on button to move frame (only add once)
	if not btn.popOutDragHooked then
		btn.popOutDragHooked = true
		btn:RegisterForDrag("LeftButton")
		btn:HookScript("OnDragStart", function(self)
			if IsAltKeyDown() then
				local popOutFrame = ShamanPower.poppedOutFrames["cd_" .. self.cooldownType]
				if popOutFrame then
					popOutFrame:StartMoving()
				end
			end
		end)
		btn:HookScript("OnDragStop", function(self)
			local cdKey = "cd_" .. self.cooldownType
			local popOutFrame = ShamanPower.poppedOutFrames[cdKey]
			if popOutFrame then
				popOutFrame:StopMovingOrSizing()
				local point, _, relPoint, x, y = popOutFrame:GetPoint()
				ShamanPower.opt.poppedOutPositions = ShamanPower.opt.poppedOutPositions or {}
				ShamanPower.opt.poppedOutPositions[cdKey] = {point=point, relPoint=relPoint, x=x, y=y}
			end
		end)
	end

	-- Middle-click is handled by the initial handler in CreateCooldownBar
	-- (no duplicate hook needed here)

	-- Check if frame should be hidden based on saved settings
	local settings = self.opt.poppedOutSettings and self.opt.poppedOutSettings[key] or {}
	if settings.hideFrame then
		frame:SetBackdrop(nil)
		if frame.titleText then frame.titleText:Hide() end
		if frame.cogBtn then frame.cogBtn:Hide() end
		frame:SetSize(frame.buttonSize + 4, frame.buttonSize + 4)
		btn:ClearAllPoints()
		btn:SetPoint("CENTER", frame, "CENTER", 0, 0)
	end

	-- Update cooldown bar layout
	self:UpdateCooldownBarLayout()

	frame:Show()
end

-- Pop out Earth Shield button as standalone tracker
function ShamanPower:PopOutEarthShield()
	local key = "earthshield"
	if self.opt.poppedOut and self.opt.poppedOut[key] then return end

	local esBtn = _G["ShamanPowerEarthShieldBtn"]
	if not esBtn then return end

	self.opt.poppedOut = self.opt.poppedOut or {}
	self.opt.poppedOut[key] = true

	-- Create frame with title
	local buttonSize = esBtn:GetWidth() or 26
	local frame = self:CreatePopOutFrame(key, buttonSize, "Earth Shield")

	-- Store original parent for restoration
	frame.originalParent = esBtn:GetParent()

	-- Reparent button
	esBtn:SetParent(frame)
	esBtn:ClearAllPoints()
	esBtn:SetPoint("CENTER", frame, "CENTER", 0, 2)

	frame.earthShieldButton = esBtn
	frame.button = esBtn

	-- ALT+drag on button to move frame (only add hook once)
	if not esBtn.popOutDragHooked then
		esBtn.popOutDragHooked = true
		esBtn:RegisterForDrag("LeftButton")
		esBtn:HookScript("OnDragStart", function(self)
			if IsAltKeyDown() then
				local popOutFrame = ShamanPower.poppedOutFrames["earthshield"]
				if popOutFrame then
					popOutFrame:StartMoving()
				end
			end
		end)
		esBtn:HookScript("OnDragStop", function(self)
			local popOutFrame = ShamanPower.poppedOutFrames["earthshield"]
			if popOutFrame then
				popOutFrame:StopMovingOrSizing()
				local point, _, relPoint, x, y = popOutFrame:GetPoint()
				ShamanPower.opt.poppedOutPositions = ShamanPower.opt.poppedOutPositions or {}
				ShamanPower.opt.poppedOutPositions["earthshield"] = {point=point, relPoint=relPoint, x=x, y=y}
			end
		end)
	end

	-- Middle-click is handled by the handler in CreateEarthShieldButton
	-- (no duplicate hook needed here to avoid accumulation)

	-- Check if frame should be hidden based on saved settings
	local settings = self.opt.poppedOutSettings and self.opt.poppedOutSettings[key] or {}
	if settings.hideFrame then
		frame:SetBackdrop(nil)
		if frame.titleText then frame.titleText:Hide() end
		if frame.cogBtn then frame.cogBtn:Hide() end
		frame:SetSize(frame.buttonSize + 4, frame.buttonSize + 4)
		esBtn:ClearAllPoints()
		esBtn:SetPoint("CENTER", frame, "CENTER", 0, 0)
	end

	-- Update totem bar layout
	self:RepositionEarthShieldButton()

	frame:Show()
end

-- Pop out Drop All button as standalone tracker
function ShamanPower:PopOutDropAll()
	local key = "dropall"
	if self.opt.poppedOut and self.opt.poppedOut[key] then return end

	local dropAllBtn = _G["ShamanPowerAutoDropAll"]
	if not dropAllBtn then return end

	self.opt.poppedOut = self.opt.poppedOut or {}
	self.opt.poppedOut[key] = true

	-- Create frame with title
	local buttonSize = dropAllBtn:GetWidth() or 26
	local frame = self:CreatePopOutFrame(key, buttonSize, "Drop All")

	-- Store original parent for restoration
	frame.originalParent = dropAllBtn:GetParent()

	-- Reparent button
	dropAllBtn:SetParent(frame)
	dropAllBtn:ClearAllPoints()
	dropAllBtn:SetPoint("CENTER", frame, "CENTER", 0, 2)

	frame.dropAllButton = dropAllBtn
	frame.button = dropAllBtn

	-- ALT+drag on button to move frame (only add hook once)
	if not dropAllBtn.popOutDragHooked then
		dropAllBtn.popOutDragHooked = true
		dropAllBtn:RegisterForDrag("LeftButton")
		dropAllBtn:HookScript("OnDragStart", function(self)
			if IsAltKeyDown() then
				local popOutFrame = ShamanPower.poppedOutFrames["dropall"]
				if popOutFrame then
					popOutFrame:StartMoving()
				end
			end
		end)
		dropAllBtn:HookScript("OnDragStop", function(self)
			local popOutFrame = ShamanPower.poppedOutFrames["dropall"]
			if popOutFrame then
				popOutFrame:StopMovingOrSizing()
				local point, _, relPoint, x, y = popOutFrame:GetPoint()
				ShamanPower.opt.poppedOutPositions = ShamanPower.opt.poppedOutPositions or {}
				ShamanPower.opt.poppedOutPositions["dropall"] = {point=point, relPoint=relPoint, x=x, y=y}
			end
		end)
	end

	-- Middle-click is handled by the handler in UpdateDropAllButton
	-- (no duplicate hook needed here to avoid accumulation)

	-- Check if frame should be hidden based on saved settings
	local settings = self.opt.poppedOutSettings and self.opt.poppedOutSettings[key] or {}
	if settings.hideFrame then
		frame:SetBackdrop(nil)
		if frame.titleText then frame.titleText:Hide() end
		if frame.cogBtn then frame.cogBtn:Hide() end
		frame:SetSize(frame.buttonSize + 4, frame.buttonSize + 4)
		dropAllBtn:ClearAllPoints()
		dropAllBtn:SetPoint("CENTER", frame, "CENTER", 0, 0)
	end

	-- Update totem bar layout
	self:UpdateMiniTotemBar()

	frame:Show()
end

-- Check if Earth Shield is popped out
function ShamanPower:IsEarthShieldPoppedOut()
	if not self.opt.poppedOut then return false end
	return self.opt.poppedOut["earthshield"] == true
end

-- Check if Drop All is popped out
function ShamanPower:IsDropAllPoppedOut()
	if not self.opt.poppedOut then return false end
	return self.opt.poppedOut["dropall"] == true
end

-- Return a popped-out item to its original bar
function ShamanPower:ReturnPopOutToBar(key)
	if not self.opt.poppedOut then return end
	self.opt.poppedOut[key] = nil

	local frame = self.poppedOutFrames[key]
	if not frame then return end

	if key:match("^totem_") then
		-- Element with flyout - reparent button back
		local totemBtn = frame.totemButton
		if totemBtn then
			totemBtn:SetParent(UIParent)  -- Back to UIParent (original parent for secure buttons)
			-- Position will be restored by UpdateTotemButtons
		end
		self:UpdateMiniTotemBar()
		self:UpdateTotemButtons()

	elseif key:match("^single_") then
		-- Single totem - destroy the pop-out frame and button
		if frame.button then
			frame.button:Hide()
			frame.button:SetParent(nil)
		end
		-- Clean up pulse overlay for this pop-out
		if self.poppedOutOverlays[key] then
			self.poppedOutOverlays[key] = nil
		end
		-- Clean up progress bars for this pop-out
		if self.poppedOutProgressBars[key] then
			self.poppedOutProgressBars[key] = nil
		end
		local element = frame.element
		self:UpdateFlyoutVisibility(element)

	elseif key:match("^cd_") then
		-- Cooldown item - reparent back to cooldown bar
		local btn = frame.cooldownButton
		if btn and self.cooldownBar then
			btn:SetParent(self.cooldownBar)
			-- Position will be restored by UpdateCooldownBarLayout
		end
		self:UpdateCooldownBarLayout()

	elseif key == "earthshield" then
		-- Earth Shield - reparent back to UIParent
		local esBtn = frame.earthShieldButton
		if esBtn then
			esBtn:SetParent(UIParent)
			-- Position will be restored by RepositionEarthShieldButton
		end
		self:RepositionEarthShieldButton()

	elseif key == "dropall" then
		-- Drop All - reparent back to original parent
		local dropAllBtn = frame.dropAllButton
		if dropAllBtn and frame.originalParent then
			dropAllBtn:SetParent(frame.originalParent)
			-- Position will be restored by UpdateMiniTotemBar
		end
		self:UpdateMiniTotemBar()
		-- Ensure Earth Shield is properly repositioned after Drop All returns
		C_Timer.After(0.05, function()
			self:RepositionEarthShieldButton()
		end)
	end

	frame:Hide()
	frame:SetParent(nil)
	self.poppedOutFrames[key] = nil
end

-- Restore all popped-out trackers on load
function ShamanPower:RestorePoppedOutTrackers()
	if not self.opt.poppedOut then return end

	for key, isPopped in pairs(self.opt.poppedOut) do
		if isPopped then
			if key:match("^totem_") then
				local elementName = key:match("^totem_(.+)$")
				if elementName then
					local element = self.ElementToID[elementName:upper()]
					if element then
						-- Delay slightly to ensure buttons exist
						C_Timer.After(0.1, function()
							self.opt.poppedOut[key] = nil  -- Clear so PopOutElementWithFlyout can proceed
							self:PopOutElementWithFlyout(element)
						end)
					end
				end

			elseif key:match("^single_") then
				local elem, idx = key:match("^single_(%d+)_(%d+)$")
				if elem and idx then
					C_Timer.After(0.1, function()
						self.opt.poppedOut[key] = nil  -- Clear so PopOutSingleTotem can proceed
						self:PopOutSingleTotem(tonumber(elem), tonumber(idx))
					end)
				end

			elseif key:match("^cd_") then
				local cdType = key:match("^cd_(%d+)$")
				if cdType then
					C_Timer.After(0.2, function()
						self.opt.poppedOut[key] = nil  -- Clear so PopOutCooldownItem can proceed
						self:PopOutCooldownItem(tonumber(cdType))
					end)
				end

			elseif key == "earthshield" then
				C_Timer.After(0.2, function()
					self.opt.poppedOut[key] = nil  -- Clear so PopOutEarthShield can proceed
					self:PopOutEarthShield()
				end)

			elseif key == "dropall" then
				C_Timer.After(0.2, function()
					self.opt.poppedOut[key] = nil  -- Clear so PopOutDropAll can proceed
					self:PopOutDropAll()
				end)
			end
		end
	end
end

-- Return all popped-out items to bars
function ShamanPower:ReturnAllPopOutsToBar()
	if not self.opt.poppedOut then return end

	-- Make a copy of keys since we're modifying the table
	local keys = {}
	for key in pairs(self.opt.poppedOut) do
		table.insert(keys, key)
	end

	for _, key in ipairs(keys) do
		self:ReturnPopOutToBar(key)
	end
end

-- Check if an element is popped out
function ShamanPower:IsElementPoppedOut(element)
	if not self.opt.poppedOut then return false end
	local elementName = self.Elements[element]:lower()
	local key = "totem_" .. elementName
	return self.opt.poppedOut[key] == true
end

-- Check if a single totem is popped out
function ShamanPower:IsSingleTotemPoppedOut(element, totemIndex)
	if not self.opt.poppedOut then return false end
	local key = "single_" .. element .. "_" .. totemIndex
	return self.opt.poppedOut[key] == true
end

-- Check if a cooldown item is popped out
function ShamanPower:IsCooldownPoppedOut(cooldownType)
	if not self.opt.poppedOut then return false end
	local key = "cd_" .. cooldownType
	return self.opt.poppedOut[key] == true
end

-- Combat-functional totem buttons parented to UIParent (TotemTimers architecture)
-- These buttons handle all totem interactions and support combat flyouts
ShamanPower.totemButtons = {}

-- Create totem buttons parented to UIParent using SPTotemButtonTemplate
-- This architecture enables combat-functional flyout menus
function ShamanPower:CreateTotemButtons()
	if self.totemButtons[1] then return end  -- Already created

	local elementIcons = {
		[1] = "Interface\\Icons\\Spell_Nature_EarthElemental_Totem",  -- Earth
		[2] = "Interface\\Icons\\Spell_Fire_SealOfFire",              -- Fire
		[3] = "Interface\\Icons\\Spell_Frost_SummonWaterElemental",   -- Water
		[4] = "Interface\\Icons\\Spell_Nature_InvisibilityTotem",     -- Air
	}

	for element = 1, 4 do
		-- Create button parented to UIParent using the new template
		local btn = CreateFrame("Button", "ShamanPowerTotemBtn" .. element, UIParent,
			"SPTotemButtonTemplate")

		btn:SetSize(26, 26)
		btn.element = element
		btn.icon = _G[btn:GetName() .. "Icon"]

		-- Set default icon
		if btn.icon then
			btn.icon:SetTexture(elementIcons[element])
		end

		-- Create small corner indicator for "assigned totem" (used in TotemTimers style mode)
		local assignedIndicator = CreateFrame("Frame", nil, btn)
		assignedIndicator:SetSize(12, 12)
		assignedIndicator:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
		assignedIndicator:SetFrameLevel(btn:GetFrameLevel() + 10)
		assignedIndicator:Hide()

		local indicatorBg = assignedIndicator:CreateTexture(nil, "BACKGROUND")
		indicatorBg:SetAllPoints()
		indicatorBg:SetColorTexture(0, 0, 0, 0.8)

		local indicatorIcon = assignedIndicator:CreateTexture(nil, "ARTWORK")
		indicatorIcon:SetPoint("TOPLEFT", 1, -1)
		indicatorIcon:SetPoint("BOTTOMRIGHT", -1, 1)
		indicatorIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

		btn.assignedIndicator = assignedIndicator
		btn.assignedIndicatorIcon = indicatorIcon

		-- SECURE HANDLER: Show flyout on enter (WORKS IN COMBAT)
		btn:SetAttribute("OpenMenu", "mouseover")
		btn:SetAttribute("_onenter", [[
			if self:GetAttribute("OpenMenu") == "mouseover" then
				self:ChildUpdate("show", true)
			end
		]])

		-- SECURE HANDLER: Hide flyout on leave (WORKS IN COMBAT)
		btn:SetAttribute("_onleave", [[
			if not self:IsUnderMouse(true) then
				self:ChildUpdate("show", false)
			end
		]])

		-- SECURE HANDLER: Show flyout on right-click when in click mode (WORKS IN COMBAT)
		btn:SetAttribute("_onmouseup", [[
			local button = button
			if button == "RightButton" and self:GetAttribute("OpenMenu") == "click" then
				self:ChildUpdate("show", true)
			end
		]])

		-- Store layout info as attributes for secure relayout
		btn:SetAttribute("flyoutButtonSize", 28)
		btn:SetAttribute("flyoutSpacing", 0)


		-- Spell casting (type1 = left click)
		btn:SetAttribute("type1", "spell")

		-- Right-click to cast Totemic Call (destroys all totems)
		btn:SetAttribute("type2", "spell")
		btn:SetAttribute("spell2", GetSpellInfo(36936))  -- Totemic Call

		-- Register for clicks
		btn:RegisterForClicks("AnyUp", "AnyDown")
		btn:EnableMouse(true)

		-- Lua hooks for tooltips (work alongside secure handlers)
		btn:HookScript("OnEnter", function(self)
			ShamanPower:TotemBarTooltip(self, element)
		end)
		btn:HookScript("OnLeave", function(self)
			GameTooltip:Hide()
		end)

		-- Middle-click to pop out element with flyout (or SHIFT+Middle-click for settings when popped out)
		btn:HookScript("OnClick", function(self, button)
			if button == "MiddleButton" then
				-- Check if pop-out is enabled
				if ShamanPower.opt.enableMiddleClickPopOut == false then return end

				-- Debounce to prevent double-firing on down+up (same button is reparented)
				local now = GetTime()
				if ShamanPower.lastElementPopOutTime and (now - ShamanPower.lastElementPopOutTime) < 0.3 then
					return
				end
				ShamanPower.lastElementPopOutTime = now

				local elem = self.element
				local elementName = ShamanPower.Elements[elem]:lower()
				local key = "totem_" .. elementName

				-- If popped out and SHIFT is held, open settings instead of returning
				if ShamanPower.opt.poppedOut and ShamanPower.opt.poppedOut[key] then
					if IsShiftKeyDown() then
						local frame = ShamanPower.poppedOutFrames[key]
						if frame then
							ShamanPower:ShowPopOutSettingsPanel(key, frame)
						end
					else
						if InCombatLockdown() then
							print("|cffff0000ShamanPower:|r Cannot modify pop-outs during combat")
							return
						end
						ShamanPower:ReturnPopOutToBar(key)
					end
				else
					if InCombatLockdown() then
						print("|cffff0000ShamanPower:|r Cannot pop out during combat")
						return
					end
					ShamanPower:PopOutElementWithFlyout(elem)
				end
			end
		end)

		btn:Show()
		self.totemButtons[element] = btn
	end
end

-- Position totem buttons over the visual container
function ShamanPower:PositionTotemButtons()
	if not self.autoButton then return end

	local padding = 4
	local spacing = self.opt.totemBarPadding or 2
	local buttonSize = 26
	local isHorizontal = (self.opt.layout == "Horizontal")
	local totemOrder = self.opt.totemBarOrder or {1, 2, 3, 4}

	-- Check which totem buttons should be visible (not hidden and not popped out)
	local elementVisible = {
		[1] = self.opt.totemBarShowEarth ~= false and not self:IsElementPoppedOut(1),
		[2] = self.opt.totemBarShowFire ~= false and not self:IsElementPoppedOut(2),
		[3] = self.opt.totemBarShowWater ~= false and not self:IsElementPoppedOut(3),
		[4] = self.opt.totemBarShowAir ~= false and not self:IsElementPoppedOut(4),
	}

	local visiblePosition = 0
	for position = 1, 4 do
		local element = totemOrder[position]
		local btn = self.totemButtons[element]
		if btn then
			-- Skip popped out elements entirely (they're reparented elsewhere)
			if self:IsElementPoppedOut(element) then
				-- Don't touch popped out buttons
			elseif not elementVisible[element] then
				btn:Hide()
			else
				visiblePosition = visiblePosition + 1
				btn:ClearAllPoints()
				btn:SetSize(buttonSize, buttonSize)

				if isHorizontal then
					btn:SetPoint("TOPLEFT", self.autoButton, "TOPLEFT", padding + (visiblePosition - 1) * (buttonSize + spacing), -padding)
				else
					btn:SetPoint("TOPLEFT", self.autoButton, "TOPLEFT", padding, -padding - (visiblePosition - 1) * (buttonSize + spacing))
				end

				-- Match the scale of the visual container
				btn:SetScale(self.opt.buffscale or 0.9)
				btn:Show()
			end
		end
	end
end

-- Update totem buttons with spell info and position (called from UpdateMiniTotemBar)
function ShamanPower:UpdateTotemButtons()
	if InCombatLockdown() then return end

	-- Make sure totem buttons exist
	self:CreateTotemButtons()

	local playerName = self.player
	local assignments = ShamanPower_Assignments[playerName]
	if not assignments then return end

	local padding = 4
	local spacing = self.opt.totemBarPadding or 2
	local buttonSize = 26
	local isHorizontal = (self.opt.layout == "Horizontal")
	local totemOrder = self.opt.totemBarOrder or {1, 2, 3, 4}

	-- Check which totem buttons should be visible (not hidden in options and not popped out)
	local elementVisible = {
		[1] = self.opt.totemBarShowEarth ~= false and not self:IsElementPoppedOut(1),
		[2] = self.opt.totemBarShowFire ~= false and not self:IsElementPoppedOut(2),
		[3] = self.opt.totemBarShowWater ~= false and not self:IsElementPoppedOut(3),
		[4] = self.opt.totemBarShowAir ~= false and not self:IsElementPoppedOut(4),
	}

	local visiblePosition = 0
	for position = 1, 4 do
		local element = totemOrder[position]
		local btn = self.totemButtons[element]

		if btn then
			local isPoppedOut = self:IsElementPoppedOut(element)

			-- Get totem spell - Dynamic Mode uses active totem, Normal Mode uses assignment
			local totemIndex
			if self.opt.dynamicTotemMode then
				local activeIndex = self:GetActiveTotemIndex(element)
				if activeIndex then
					totemIndex = activeIndex
				else
					totemIndex = assignments[element] or 0
				end
			else
				totemIndex = assignments[element] or 0
			end

			local spellID = nil
			local spellName = nil
			local icon = self.ElementIcons[element]

			if totemIndex and totemIndex > 0 then
				spellID = self:GetTotemSpell(element, totemIndex)
				icon = self:GetTotemIcon(element, totemIndex)
				if spellID then
					spellName = GetSpellInfo(spellID)
				end
			end

			-- Always update icon (even for popped out elements)
			if btn.icon then
				btn.icon:SetTexture(icon)
			end

			-- Always update spell attributes (even for popped out elements)
			-- Clear old attributes
			btn:SetAttribute("type", nil)
			btn:SetAttribute("type1", nil)
			btn:SetAttribute("spell", nil)
			btn:SetAttribute("spell1", nil)
			btn:SetAttribute("macrotext1", nil)

			-- Set up spell casting (same logic as XML buttons)
			if element == 4 and self.opt.enableTotemTwisting then
				local wfName = GetSpellInfo(25587) or "Windfury Totem"
				local goaName = GetSpellInfo(25359) or "Grace of Air Totem"
				btn:SetAttribute("type1", "macro")
				btn:SetAttribute("macrotext1", "/castsequence reset=10 " .. wfName .. ", " .. goaName)
			elseif spellName then
				btn:SetAttribute("type1", "spell")
				btn:SetAttribute("spell1", spellName)
			end

			-- Right-click behavior: Totemic Call by default, or flyout trigger if option enabled
			if self.opt.showTotemFlyouts and self.opt.flyoutRequiresClick then
				-- Right-click shows flyout instead of Totemic Call
				btn:SetAttribute("type2", nil)
				btn:SetAttribute("spell2", nil)
			else
				-- Right-click to cast Totemic Call (destroys all totems)
				btn:SetAttribute("type2", "spell")
				btn:SetAttribute("spell2", GetSpellInfo(36936))  -- Totemic Call
			end

			-- Handle visibility and positioning (only for non-popped-out elements)
			if not elementVisible[element] then
				-- Hide only if not popped out (popped out buttons are reparented)
				if not isPoppedOut then
					btn:Hide()
				end
			else
				visiblePosition = visiblePosition + 1
				btn:Show()

				-- Position button relative to visual container
				btn:ClearAllPoints()
				if isHorizontal then
					btn:SetPoint("TOPLEFT", self.autoButton, "TOPLEFT", padding + (visiblePosition - 1) * (buttonSize + spacing), -padding)
				else
					btn:SetPoint("TOPLEFT", self.autoButton, "TOPLEFT", padding, -padding - (visiblePosition - 1) * (buttonSize + spacing))
				end

				-- Match the scale of the visual container
				btn:SetScale(self.opt.buffscale or 0.9)
			end
		end
	end

	-- Hide the XML totem buttons since we're using the new totem buttons
	for element = 1, 4 do
		local xmlButton = _G["ShamanPowerAutoTotem" .. element]
		if xmlButton then
			xmlButton:Hide()
		end
	end
end

-- Create flyout menu for an element
function ShamanPower:CreateTotemFlyout(element)
	if self.totemFlyouts[element] then return self.totemFlyouts[element] end

	-- Make sure totem buttons exist
	self:CreateTotemButtons()

	-- Use the totem button as parent (parented to UIParent for combat flyout support)
	local parentButton = self.totemButtons[element]
	if not parentButton then return nil end

	-- Get totems for this element
	local totems = self.Totems[element]
	local totemNames = self.TotemNames[element]
	local icons = self.TotemIcons[element]

	-- Flyout is just a table to track buttons (buttons are children of parentButton)
	local flyout = {
		buttons = {},
		buttonSize = 28,
		padding = 4,
		spacing = 0,  -- No gap between buttons to prevent menu closing when moving mouse
		element = element,
		totemButton = parentButton
	}

	for totemIndex, spellID in pairs(totems) do
		-- Check if player knows this totem using improved spellbook search
		local spellName = GetSpellInfo(spellID)
		local totemName = totemNames and totemNames[totemIndex]
		local isKnown = PlayerKnowsTotem(spellID, totemName)

		if isKnown then
			-- Create button as CHILD of totem button using SPFlyoutButtonTemplate
			-- Parent is totemButton (parented to UIParent) for combat flyout support
			local btn = CreateFrame("Button",
				"ShamanPowerFlyout" .. element .. "Btn" .. totemIndex,
				parentButton,  -- CRITICAL: Parent is the totem button!
				"SPFlyoutButtonTemplate")

			-- IMPORTANT: CreateFrame returns existing frame if name exists, but doesn't re-parent it
			-- Must explicitly set parent when reusing frames after RecreateTotemFlyouts()
			btn:SetParent(parentButton)
			btn:SetSize(flyout.buttonSize, flyout.buttonSize)
			btn:Hide()  -- Start hidden (template handles this too)
			btn:SetIgnoreParentAlpha(true)  -- Independent opacity from parent button

			-- SECURE HANDLER: Respond to parent's ChildUpdate (WORKS IN COMBAT)
			btn:SetAttribute("_childupdate-show", [[
				if message then
					if not self:GetAttribute("isCurrentAssignment") then
						self:Show()
					end
				else
					self:Hide()
				end
			]])

			-- SECURE HANDLER: Respond to assignment changes (WORKS IN COMBAT)
			-- Updates isCurrentAssignment based on whether this button's spell matches the new assignment
			btn:SetAttribute("_childupdate-assignment", [[
				local newSpell = message
				local mySpell = self:GetAttribute("mySpell")
				if newSpell == mySpell then
					self:SetAttribute("isCurrentAssignment", true)
				else
					self:SetAttribute("isCurrentAssignment", false)
				end
			]])

			-- SECURE HANDLER: Relayout this button after assignment change (WORKS IN COMBAT)
			-- Each button counts visible siblings before it and positions itself accordingly
			btn:SetAttribute("_childupdate-relayout", [[
				-- If I'm the current assignment, I don't need to position myself (I'll be hidden)
				if self:GetAttribute("isCurrentAssignment") then
					return
				end

				local parent = self:GetParent()
				local buttonSize = parent:GetAttribute("flyoutButtonSize") or 28
				local spacing = parent:GetAttribute("flyoutSpacing") or 0
				local isVerticalLeft = parent:GetAttribute("isVerticalLeft")
				local flyoutIsHorizontal = parent:GetAttribute("flyoutIsHorizontal")
				local flyoutGoesBelow = parent:GetAttribute("flyoutGoesBelow")
				local myIndex = self:GetAttribute("myTotemIndex") or 0

				-- Count visible siblings with lower totemIndex
				local visibleBefore = 0
				local children = newtable(parent:GetChildren())
				for i = 1, #children do
					local sibling = children[i]
					if sibling:GetAttribute("isFlyoutButton") then
						local sibIndex = sibling:GetAttribute("myTotemIndex") or 0
						if sibIndex < myIndex and not sibling:GetAttribute("isCurrentAssignment") then
							visibleBefore = visibleBefore + 1
						end
					end
				end

				-- Position myself based on how many visible buttons are before me
				self:ClearAllPoints()
				if flyoutIsHorizontal then
					if isVerticalLeft then
						self:SetPoint("RIGHT", parent, "LEFT", -spacing - visibleBefore * (buttonSize + spacing), 0)
					else
						self:SetPoint("LEFT", parent, "RIGHT", spacing + visibleBefore * (buttonSize + spacing), 0)
					end
				else
					if flyoutGoesBelow then
						self:SetPoint("TOP", parent, "BOTTOM", 0, -spacing - visibleBefore * (buttonSize + spacing))
					else
						self:SetPoint("BOTTOM", parent, "TOP", 0, spacing + visibleBefore * (buttonSize + spacing))
					end
				end
			]])

			-- SECURE HANDLER: Check parent on leave (WORKS IN COMBAT)
			btn:SetAttribute("_onleave", [[
				if not self:GetParent():IsUnderMouse(true) then
					self:GetParent():ChildUpdate("show", false)
				end
			]])

			-- Store spell info as attributes for secure snippets
			btn:SetAttribute("mySpell", spellName)
			btn:SetAttribute("myElement", element)
			btn:SetAttribute("myTotemIndex", totemIndex)
			btn:SetAttribute("isFlyoutButton", true)  -- Mark as flyout button for relayout handler

			-- Check if buttons are swapped
			local swapped = self.opt.swapFlyoutClickButtons

			-- Set up casting (opposite of assignment button)
			-- Clear BOTH sets of attributes first (frame may be reused with old attributes)
			btn:SetAttribute("type1", nil)
			btn:SetAttribute("spell1", nil)
			btn:SetAttribute("type2", nil)
			btn:SetAttribute("spell2", nil)

			if swapped then
				-- Swapped: right-click casts, left-click assigns
				btn:SetAttribute("type2", "spell")
				btn:SetAttribute("spell2", spellName)
				btn:SetAttribute("assignButton", "LeftButton")
			else
				-- Normal: left-click casts, right-click assigns
				btn:SetAttribute("type1", "spell")
				btn:SetAttribute("spell1", spellName)
				btn:SetAttribute("assignButton", "RightButton")
			end

			-- SECURE HANDLER: Handle assignment via right-click (WORKS IN COMBAT)
			-- Use _onmouseup to change parent's spell and update flyout
			-- This runs after the click action, so it won't interfere with left-click casting
			btn:SetAttribute("_onmouseup", [[
				local button = button
				local assignBtn = self:GetAttribute("assignButton")
				if button == assignBtn then
					local mySpell = self:GetAttribute("mySpell")
					local parent = self:GetParent()
					-- Change parent button's spell to this totem
					parent:SetAttribute("spell1", mySpell)
					-- Notify all flyout buttons of the new assignment (updates isCurrentAssignment)
					parent:ChildUpdate("assignment", mySpell)
					-- Relayout flyout buttons to close the gap
					parent:ChildUpdate("relayout", true)
					-- Close the flyout
					parent:ChildUpdate("show", false)
				end
			]])

			-- Set up icon (use template's icon child or create one)
			btn.icon = _G[btn:GetName() .. "Icon"]
			if not btn.icon then
				btn.icon = btn:CreateTexture(nil, "ARTWORK")
			end
			-- Always reset icon state (button may be reused after SetParent(nil))
			btn.icon:ClearAllPoints()
			btn.icon:SetAllPoints()
			btn.icon:SetTexture(icons[totemIndex] or "Interface\\Icons\\INV_Misc_QuestionMark")
			btn.icon:Show()

			-- Tooltip (Lua hook, works alongside secure handlers)
			btn:HookScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:SetSpellByID(spellID)
				GameTooltip:AddLine(" ")
				if ShamanPower.opt.swapFlyoutClickButtons then
					GameTooltip:AddLine("|cff00ff00Left-click:|r Set as assigned totem", 1, 1, 1)
					GameTooltip:AddLine("|cffffcc00Right-click:|r Cast totem", 1, 1, 1)
				else
					GameTooltip:AddLine("|cff00ff00Left-click:|r Cast totem", 1, 1, 1)
					GameTooltip:AddLine("|cffffcc00Right-click:|r Set as assigned totem", 1, 1, 1)
				end
				if ShamanPower.opt.enableMiddleClickPopOut ~= false then
					GameTooltip:AddLine("|cff00ccffMiddle-click:|r Pop out element", 1, 1, 1)
				end
				GameTooltip:Show()
			end)
			btn:HookScript("OnLeave", function(self)
				GameTooltip:Hide()
			end)

			-- Handle assignment click (button depends on swap setting)
			-- The secure _onclick handler has already changed the spell in combat
			-- This Lua handler does the non-secure parts (SavedVariables, UI updates)
			btn:SetScript("PostClick", function(self, button)
				local assignButton = ShamanPower.opt.swapFlyoutClickButtons and "LeftButton" or "RightButton"
				if button == assignButton then
					local totemIdx = self.totemIndex
					local elem = element

					if InCombatLockdown() then
						-- In combat: secure handler already changed the spell
						-- Update icon immediately (texture changes are allowed in combat)
						local totemBtn = ShamanPower.totemButtons[elem]
						if totemBtn and totemBtn.icon then
							local icons = ShamanPower.TotemIcons[elem]
							if icons and icons[totemIdx] then
								totemBtn.icon:SetTexture(icons[totemIdx])
							end
						end
						-- Queue the Lua-side updates for when combat ends (silently, like TotemTimers)
						if not ShamanPower.pendingAssignments then
							ShamanPower.pendingAssignments = {}
						end
						ShamanPower.pendingAssignments[elem] = totemIdx
					else
						-- Out of combat: do all updates immediately
						if not ShamanPower_Assignments[ShamanPower.player] then
							ShamanPower_Assignments[ShamanPower.player] = {}
						end
						ShamanPower_Assignments[ShamanPower.player][elem] = totemIdx
						ShamanPower:UpdateMiniTotemBar()
						ShamanPower:UpdateDropAllButton()
						ShamanPower:UpdateSPMacros()
						ShamanPower:SyncToTotemTimers(elem, totemIdx)
						ShamanPower:SendMessage("ASSIGN " .. ShamanPower.player .. " " .. elem .. " " .. totemIdx)
						-- Update flyout visibility to mark the new assignment correctly
						ShamanPower:UpdateFlyoutVisibility(elem)
						-- Hide flyout buttons
						local flyoutData = ShamanPower.totemFlyouts[elem]
						if flyoutData and flyoutData.buttons then
							for _, flyoutBtn in ipairs(flyoutData.buttons) do
								flyoutBtn:Hide()
							end
						end
					end
				end
			end)

			-- Middle-click to pop out single totem
			btn:HookScript("OnClick", function(self, button)
				if button == "MiddleButton" then
					if InCombatLockdown() then
						print("|cffff0000ShamanPower:|r Cannot pop out during combat")
						return
					end
					local elem = element
					local totemIdx = self.totemIndex
					local key = "single_" .. elem .. "_" .. totemIdx

					if ShamanPower.opt.poppedOut and ShamanPower.opt.poppedOut[key] then
						ShamanPower:ReturnPopOutToBar(key)
					else
						ShamanPower:PopOutSingleTotem(elem, totemIdx)
					end
				end
			end)

			btn.totemIndex = totemIndex
			btn.spellID = spellID
			table.insert(flyout.buttons, btn)
		end
	end

	-- Sort buttons by totemIndex for consistent ordering
	table.sort(flyout.buttons, function(a, b) return a.totemIndex < b.totemIndex end)

	-- Initial layout
	self:LayoutFlyoutButtons(flyout)

	self.totemFlyouts[element] = flyout

	return flyout
end

-- Layout flyout buttons based on current bar orientation
-- For horizontal bar: flyout is VERTICAL (buttons stacked)
-- For vertical bar: flyout is HORIZONTAL (buttons in a row)
function ShamanPower:LayoutFlyoutButtons(flyout, flyoutIsHorizontal)
	if not flyout or not flyout.buttons then return end

	local totemButton = flyout.totemButton
	if not totemButton then return end

	local buttons = flyout.buttons
	local numButtons = #buttons
	local buttonSize = flyout.buttonSize or 28
	local spacing = flyout.spacing or 0

	-- Check if this element is popped out and has a custom flyout direction
	local element = flyout.element or (totemButton and totemButton.element)
	local poppedOutDirection = nil
	if element then
		local elementName = self.Elements[element]:lower()
		local key = "totem_" .. elementName
		if self:IsElementPoppedOut(element) then
			local settings = self.opt.poppedOutSettings and self.opt.poppedOutSettings[key]
			if settings and settings.flyoutDirection then
				poppedOutDirection = settings.flyoutDirection
			end
		end
	end

	-- If popped out with custom direction, use that instead of bar-based logic
	if poppedOutDirection then
		flyout.isHorizontal = (poppedOutDirection == "left" or poppedOutDirection == "right")

		if numButtons == 0 then return end

		-- Position based on custom direction
		if poppedOutDirection == "top" then
			for i, btn in ipairs(buttons) do
				btn:ClearAllPoints()
				btn:SetPoint("BOTTOM", totemButton, "TOP", 0, spacing + (i - 1) * (buttonSize + spacing))
			end
		elseif poppedOutDirection == "bottom" then
			for i, btn in ipairs(buttons) do
				btn:ClearAllPoints()
				btn:SetPoint("TOP", totemButton, "BOTTOM", 0, -spacing - (i - 1) * (buttonSize + spacing))
			end
		elseif poppedOutDirection == "left" then
			for i, btn in ipairs(buttons) do
				btn:ClearAllPoints()
				btn:SetPoint("RIGHT", totemButton, "LEFT", -spacing - (i - 1) * (buttonSize + spacing), 0)
			end
		elseif poppedOutDirection == "right" then
			for i, btn in ipairs(buttons) do
				btn:ClearAllPoints()
				btn:SetPoint("LEFT", totemButton, "RIGHT", spacing + (i - 1) * (buttonSize + spacing), 0)
			end
		end
		return
	end

	-- Default: if bar is horizontal, flyout is vertical (and vice versa)
	if flyoutIsHorizontal == nil then
		local isHorizontalBar = (self.opt.layout == "Horizontal")
		-- Both "Vertical" and "VerticalLeft" result in horizontal flyouts
		flyoutIsHorizontal = not isHorizontalBar
	end

	local isVerticalLeft = (self.opt.layout == "VerticalLeft")

	-- Determine flyout direction for vertical flyouts (when horizontal bar)
	local flyoutDir = self.opt.totemFlyoutDirection or "auto"
	local flyoutGoesBelow = (flyoutDir == "below")

	flyout.isHorizontal = flyoutIsHorizontal

	-- Store layout info on parent button for secure relayout handler
	totemButton:SetAttribute("isVerticalLeft", isVerticalLeft)
	totemButton:SetAttribute("flyoutIsHorizontal", flyoutIsHorizontal)
	totemButton:SetAttribute("flyoutGoesBelow", flyoutGoesBelow)

	if numButtons == 0 then return end

	-- Position buttons relative to the totem button (parent)
	-- Buttons are children of totemButton, so we anchor to the parent
	if flyoutIsHorizontal then
		if isVerticalLeft then
			-- VerticalLeft: horizontal flyout extends to the LEFT
			for i, btn in ipairs(buttons) do
				btn:ClearAllPoints()
				btn:SetPoint("RIGHT", totemButton, "LEFT", -spacing - (i - 1) * (buttonSize + spacing), 0)
			end
		else
			-- Vertical (Right): horizontal flyout extends to the RIGHT
			for i, btn in ipairs(buttons) do
				btn:ClearAllPoints()
				btn:SetPoint("LEFT", totemButton, "RIGHT", spacing + (i - 1) * (buttonSize + spacing), 0)
			end
		end
	else
		-- Vertical flyout: buttons extend upward or downward based on option
		if flyoutGoesBelow then
			-- Extend downward
			for i, btn in ipairs(buttons) do
				btn:ClearAllPoints()
				btn:SetPoint("TOP", totemButton, "BOTTOM", 0, -spacing - (i - 1) * (buttonSize + spacing))
			end
		else
			-- Extend upward (default/auto)
			for i, btn in ipairs(buttons) do
				btn:ClearAllPoints()
				btn:SetPoint("BOTTOM", totemButton, "TOP", 0, spacing + (i - 1) * (buttonSize + spacing))
			end
		end
	end
end

-- Position flyout relative to totem button, reversing direction if needed
-- For horizontal bar layout: flyout extends vertically (above/below)
-- For vertical bar layout: flyout extends horizontally (left/right)
-- "Vertical" (Right) prefers flyouts to the right, "VerticalLeft" prefers flyouts to the left
function ShamanPower:PositionFlyout(flyout, totemButton)
	if not flyout or not totemButton then return end

	local isHorizontalBar = (self.opt.layout == "Horizontal")
	local isVerticalLeft = (self.opt.layout == "VerticalLeft")

	-- Match the scale of the parent button's frame
	local parentScale = totemButton:GetEffectiveScale() / UIParent:GetEffectiveScale()
	flyout:SetScale(parentScale)

	-- Get screen dimensions
	local screenWidth = GetScreenWidth()
	local screenHeight = GetScreenHeight()

	-- Get totem button position
	local buttonLeft = totemButton:GetLeft() or 0
	local buttonRight = totemButton:GetRight() or 0
	local buttonTop = totemButton:GetTop() or 0
	local buttonBottom = totemButton:GetBottom() or 0

	-- Get flyout dimensions (adjusted for scale)
	local flyoutWidth = flyout:GetWidth() * parentScale
	local flyoutHeight = flyout:GetHeight() * parentScale

	flyout:ClearAllPoints()

	if isHorizontalBar then
		-- Horizontal bar: flyout is VERTICAL and goes above or below
		local flyoutDir = self.opt.totemFlyoutDirection or "auto"
		local spaceAbove = screenHeight - buttonTop
		local spaceBelow = buttonBottom

		if flyoutDir == "above" then
			flyout:SetPoint("BOTTOM", totemButton, "TOP", 0, 2)
		elseif flyoutDir == "below" then
			flyout:SetPoint("TOP", totemButton, "BOTTOM", 0, -2)
		elseif spaceAbove >= flyoutHeight + 2 then
			flyout:SetPoint("BOTTOM", totemButton, "TOP", 0, 2)
		elseif spaceBelow >= flyoutHeight + 2 then
			flyout:SetPoint("TOP", totemButton, "BOTTOM", 0, -2)
		elseif spaceAbove >= spaceBelow then
			flyout:SetPoint("BOTTOM", totemButton, "TOP", 0, 2)
		else
			flyout:SetPoint("TOP", totemButton, "BOTTOM", 0, -2)
		end
	else
		-- Vertical bar: flyout is HORIZONTAL and goes left or right
		-- "VerticalLeft" prefers left, "Vertical" (Right) prefers right
		local spaceRight = screenWidth - buttonRight
		local spaceLeft = buttonLeft

		if isVerticalLeft then
			-- Prefer left side
			if spaceLeft >= flyoutWidth + 2 then
				flyout:SetPoint("RIGHT", totemButton, "LEFT", -2, 0)
			elseif spaceRight >= flyoutWidth + 2 then
				flyout:SetPoint("LEFT", totemButton, "RIGHT", 2, 0)
			elseif spaceLeft >= spaceRight then
				flyout:SetPoint("RIGHT", totemButton, "LEFT", -2, 0)
			else
				flyout:SetPoint("LEFT", totemButton, "RIGHT", 2, 0)
			end
		else
			-- Prefer right side (default "Vertical")
			if spaceRight >= flyoutWidth + 2 then
				flyout:SetPoint("LEFT", totemButton, "RIGHT", 2, 0)
			elseif spaceLeft >= flyoutWidth + 2 then
				flyout:SetPoint("RIGHT", totemButton, "LEFT", -2, 0)
			elseif spaceRight >= spaceLeft then
				flyout:SetPoint("LEFT", totemButton, "RIGHT", 2, 0)
			else
				flyout:SetPoint("RIGHT", totemButton, "LEFT", -2, 0)
			end
		end
	end
end

-- Update flyout to hide currently assigned totem and reposition
-- For horizontal bar: flyout is VERTICAL (buttons stacked top to bottom)
-- For vertical bar: flyout is HORIZONTAL (buttons in a row left to right)
function ShamanPower:UpdateFlyoutVisibility(element)
	local flyout = self.totemFlyouts[element]
	if not flyout or not flyout.buttons then return end

	-- Don't modify secure buttons during combat
	if InCombatLockdown() then
		return
	end

	local totemButton = flyout.totemButton
	if not totemButton then return end

	-- Get current assignment
	local assignments = ShamanPower_Assignments[self.player]
	local currentTotemIndex = assignments and assignments[element] or 0

	-- For horizontal bar, flyout is vertical. For vertical bar (both "Vertical" and "VerticalLeft"), flyout is horizontal.
	local isHorizontalBar = (self.opt.layout == "Horizontal")
	local isVerticalLeft = (self.opt.layout == "VerticalLeft")
	local flyoutIsHorizontal = not isHorizontalBar

	-- Determine flyout direction for vertical flyouts (when horizontal bar)
	local flyoutDir = self.opt.totemFlyoutDirection or "auto"
	local flyoutGoesBelow = (flyoutDir == "below")

	-- Store layout info on parent button for secure relayout handler
	totemButton:SetAttribute("isVerticalLeft", isVerticalLeft)
	totemButton:SetAttribute("flyoutIsHorizontal", flyoutIsHorizontal)
	totemButton:SetAttribute("flyoutGoesBelow", flyoutGoesBelow)

	local buttonSize = flyout.buttonSize or 28
	local spacing = flyout.spacing or 0
	local visibleIndex = 0
	local visibleButtons = {}

	-- First pass: determine which buttons should be visible (hide current assignment and popped-out totems)
	for _, btn in ipairs(flyout.buttons) do
		local totemIdx = btn.totemIndex
		local isPoppedOut = self:IsSingleTotemPoppedOut(element, totemIdx)

		if totemIdx == currentTotemIndex or isPoppedOut then
			-- Mark this button to be hidden (via attribute so secure handler knows)
			btn:SetAttribute("isCurrentAssignment", true)
			if isPoppedOut then
				btn:Hide()  -- Explicitly hide popped-out totems
			end
		else
			btn:SetAttribute("isCurrentAssignment", false)
			visibleIndex = visibleIndex + 1
			table.insert(visibleButtons, btn)
		end
	end

	-- No visible buttons, nothing to layout
	if visibleIndex == 0 then
		return
	end

	-- Check if this element is popped out and has a custom flyout direction
	local poppedOutDirection = nil
	local elementName = self.Elements[element]:lower()
	local key = "totem_" .. elementName
	if self:IsElementPoppedOut(element) then
		local settings = self.opt.poppedOutSettings and self.opt.poppedOutSettings[key]
		if settings and settings.flyoutDirection then
			poppedOutDirection = settings.flyoutDirection
		end
	end

	-- Layout visible buttons relative to the totem button (parent)
	if poppedOutDirection then
		-- Use custom direction for popped-out element
		if poppedOutDirection == "top" then
			for i, btn in ipairs(visibleButtons) do
				btn:ClearAllPoints()
				btn:SetPoint("BOTTOM", totemButton, "TOP", 0, spacing + (i - 1) * (buttonSize + spacing))
			end
		elseif poppedOutDirection == "bottom" then
			for i, btn in ipairs(visibleButtons) do
				btn:ClearAllPoints()
				btn:SetPoint("TOP", totemButton, "BOTTOM", 0, -spacing - (i - 1) * (buttonSize + spacing))
			end
		elseif poppedOutDirection == "left" then
			for i, btn in ipairs(visibleButtons) do
				btn:ClearAllPoints()
				btn:SetPoint("RIGHT", totemButton, "LEFT", -spacing - (i - 1) * (buttonSize + spacing), 0)
			end
		elseif poppedOutDirection == "right" then
			for i, btn in ipairs(visibleButtons) do
				btn:ClearAllPoints()
				btn:SetPoint("LEFT", totemButton, "RIGHT", spacing + (i - 1) * (buttonSize + spacing), 0)
			end
		end
	elseif flyoutIsHorizontal then
		if isVerticalLeft then
			-- VerticalLeft: horizontal flyout extends to the LEFT
			for i, btn in ipairs(visibleButtons) do
				btn:ClearAllPoints()
				btn:SetPoint("RIGHT", totemButton, "LEFT", -spacing - (i - 1) * (buttonSize + spacing), 0)
			end
		else
			-- Vertical (Right): horizontal flyout extends to the RIGHT
			for i, btn in ipairs(visibleButtons) do
				btn:ClearAllPoints()
				btn:SetPoint("LEFT", totemButton, "RIGHT", spacing + (i - 1) * (buttonSize + spacing), 0)
			end
		end
	else
		-- Vertical flyout: buttons extend upward or downward based on option
		if flyoutGoesBelow then
			-- Extend downward
			for i, btn in ipairs(visibleButtons) do
				btn:ClearAllPoints()
				btn:SetPoint("TOP", totemButton, "BOTTOM", 0, -spacing - (i - 1) * (buttonSize + spacing))
			end
		else
			-- Extend upward (default/auto)
			for i, btn in ipairs(visibleButtons) do
				btn:ClearAllPoints()
				btn:SetPoint("BOTTOM", totemButton, "TOP", 0, spacing + (i - 1) * (buttonSize + spacing))
			end
		end
	end

	-- Apply flyout opacity
	local opacity = self.opt.totemFlyoutOpacity or 1.0
	for _, btn in ipairs(flyout.buttons) do
		btn:SetAlpha(opacity)
	end
end

-- Setup all flyout menus
function ShamanPower:SetupTotemFlyouts()
	if not self.opt.showTotemFlyouts then return end

	-- Ensure totem buttons exist and are positioned
	self:CreateTotemButtons()
	self:PositionTotemButtons()

	for element = 1, 4 do
		local totemButton = self.totemButtons[element]

		if totemButton then
			-- Create the flyout (will parent to totemButton)
			local flyout = self:CreateTotemFlyout(element)
			if not flyout then return end

			-- Only install Lua hooks once per totem button
			-- (Secure handlers are set up in CreateTotemButtons)
			if not self.flyoutHooksInstalled[element] then
				self.flyoutHooksInstalled[element] = true

				-- Lua hook for positioning updates (out of combat only)
				totemButton:HookScript("OnEnter", function(btn)
					if ShamanPower.opt.showTotemFlyouts and not InCombatLockdown() then
						ShamanPower:UpdateFlyoutVisibility(element)
					end
				end)
			end
		end
	end
end

-- Refresh flyout buttons (call when spells change or out of combat)
function ShamanPower:RefreshTotemFlyouts()
	if InCombatLockdown() then return end

	for element = 1, 4 do
		local flyout = self.totemFlyouts[element]
		if flyout then
			-- Update spell bindings for any new spells learned
			local totems = self.Totems[element]
			for _, btn in ipairs(flyout.buttons) do
				local spellName = GetSpellInfo(btn.spellID)
				if spellName then
					btn:SetAttribute("spell", spellName)
				end
			end
		end
	end
end

-- Update click behavior on existing flyout buttons (no recreation needed)
function ShamanPower:UpdateFlyoutClickBehavior()
	if InCombatLockdown() then
		print("|cffff0000ShamanPower:|r Cannot change flyout settings in combat")
		return
	end

	local swapped = self.opt.swapFlyoutClickButtons

	for element = 1, 4 do
		local flyout = self.totemFlyouts[element]
		if flyout and flyout.buttons then
			for _, btn in ipairs(flyout.buttons) do
				local spellName = btn:GetAttribute("mySpell")

				-- Clear old attributes
				btn:SetAttribute("type1", nil)
				btn:SetAttribute("spell1", nil)
				btn:SetAttribute("type2", nil)
				btn:SetAttribute("spell2", nil)

				-- Set new attributes based on swap setting
				if swapped then
					btn:SetAttribute("type2", "spell")
					btn:SetAttribute("spell2", spellName)
					btn:SetAttribute("assignButton", "LeftButton")
				else
					btn:SetAttribute("type1", "spell")
					btn:SetAttribute("spell1", spellName)
					btn:SetAttribute("assignButton", "RightButton")
				end
			end
		end
	end

	-- Also update Earth Shield flyout
	self:UpdateESFlyoutClickBehavior()
end

-- Toggle totem flyouts on/off based on showTotemFlyouts option
function ShamanPower:UpdateTotemFlyoutEnabled()
	if InCombatLockdown() then
		print("|cffff0000ShamanPower:|r Cannot change flyout settings in combat")
		return
	end

	local enabled = self.opt.showTotemFlyouts
	local requiresClick = self.opt.flyoutRequiresClick
	local totemicCallName = GetSpellInfo(36936)  -- Totemic Call

	for element = 1, 4 do
		local btn = self.totemButtons[element]
		if btn then
			if not enabled then
				-- Flyouts disabled
				btn:SetAttribute("OpenMenu", nil)
				btn:SetAttribute("type2", "spell")
				btn:SetAttribute("spell2", totemicCallName)
				-- Hide any visible flyout buttons directly
				local flyout = self.totemFlyouts[element]
				if flyout and flyout.buttons then
					for _, flyoutBtn in ipairs(flyout.buttons) do
						flyoutBtn:Hide()
					end
				end
			elseif requiresClick then
				-- Flyouts enabled, right-click to show
				btn:SetAttribute("OpenMenu", "click")
				btn:SetAttribute("type2", nil)  -- Disable Totemic Call on right-click
				btn:SetAttribute("spell2", nil)
			else
				-- Flyouts enabled, mouseover to show (default)
				btn:SetAttribute("OpenMenu", "mouseover")
				btn:SetAttribute("type2", "spell")
				btn:SetAttribute("spell2", totemicCallName)
			end
		end
	end
end

-- Recreate all totem flyouts (used when major changes require full rebuild)
function ShamanPower:RecreateTotemFlyouts()
	if InCombatLockdown() then
		print("|cffff0000ShamanPower:|r Cannot change flyout settings in combat")
		return
	end

	-- Destroy existing flyout buttons (buttons are children of totemButton)
	for element = 1, 4 do
		local flyout = self.totemFlyouts[element]
		if flyout and flyout.buttons then
			for _, btn in ipairs(flyout.buttons) do
				btn:Hide()
				btn:SetParent(nil)
			end
		end
		self.totemFlyouts[element] = nil
		-- Note: We don't reset flyoutHooksInstalled since the secure handlers on totemButton persist
	end

	-- Recreate flyouts with new settings
	self:SetupTotemFlyouts()
end

-- ============================================================================
-- Player Totem Range Indicator (greys out icon if out of range of own totem)
-- ============================================================================

-- Update player's own totem range (desaturate icons when out of range)
-- Reusable arrays for totem range check (avoids creating garbage)
ShamanPower.totemRangeBuffNames = {nil, nil, nil, nil}  -- Buff names to check (indexed by element)
ShamanPower.totemRangeResults = {false, false, false, false}  -- Results (indexed by element)

function ShamanPower:UpdatePlayerTotemRange()
	-- Collect buff names we need to check for each element
	local buffNames = self.totemRangeBuffNames
	local results = self.totemRangeResults
	local buffLowerCache = self.buffNameLowerCache or {}
	self.buffNameLowerCache = buffLowerCache

	-- Track weapon enchant totems (need special weapon enchant check instead of buff check)
	local isWindfuryAir = false      -- Air (4) with Windfury Totem
	local isFlametongueFire = false  -- Fire (2) with Flametongue Totem

	-- Reset results and collect buff names
	for element = 1, 4 do
		results[element] = false
		local slot = self.ElementToSlot[element]
		local haveTotem, totemName = GetTotemInfo(slot)
		if haveTotem then
			buffNames[element] = self:GetActiveTotemBuffName(element)
			-- Special case: Totems that apply weapon enchants instead of buffs
			-- These need weapon enchant detection, not buff detection
			if totemName then
				if element == 4 and totemName:find("Windfury") then
					-- Windfury Totem (Air) - applies weapon enchant
					isWindfuryAir = true
					buffNames[element] = nil  -- Clear buff name so we use weapon check
				elseif element == 2 and totemName:find("Flametongue") then
					-- Flametongue Totem (Fire) - applies weapon enchant
					isFlametongueFire = true
					buffNames[element] = nil  -- Clear buff name so we use weapon check
				end
			end
		else
			buffNames[element] = nil
		end
	end

	-- Single scan through player buffs, checking all 4 elements at once
	local scannedCache = self.scannedBuffLowerCache or {}
	self.scannedBuffLowerCache = scannedCache

	for i = 1, 20 do
		local name = UnitBuff("player", i)
		if not name then break end

		local nameLower = scannedCache[name]
		if not nameLower then
			nameLower = name:lower()
			scannedCache[name] = nameLower
		end

		-- Check this buff against all 4 element buff names
		for element = 1, 4 do
			if not results[element] and buffNames[element] then
				local searchLower = buffLowerCache[buffNames[element]]
				if not searchLower then
					searchLower = buffNames[element]:lower()
					buffLowerCache[buffNames[element]] = searchLower
				end
				if nameLower:find(searchLower, 1, true) then
					results[element] = true
				end
			end
		end
	end

	-- Special case: Check weapon enchant totems via GetWeaponEnchantInfo()
	-- This uses the same detection as SPRange module
	if isWindfuryAir or isFlametongueFire then
		local hasWeaponEnchant = self:SPRangeHasWindfuryWeapon()
		if isWindfuryAir then
			results[4] = hasWeaponEnchant
		end
		if isFlametongueFire then
			results[2] = hasWeaponEnchant
		end
	end

	-- Now apply the results to icons
	for element = 1, 4 do
		local slot = self.ElementToSlot[element]
		local haveTotem = slot and GetTotemInfo(slot)
		local hasBuff = results[element]

		-- Check if active overlay is showing
		local activeOverlay = self.activeTotemOverlays and self.activeTotemOverlays[element]
		local overlayActive = activeOverlay and activeOverlay.isActive

		-- Determine if this element has trackable range (buff or weapon enchant check)
		local hasTrackableRange = buffNames[element] or (element == 4 and isWindfuryAir) or (element == 2 and isFlametongueFire)

		if overlayActive then
			if haveTotem and activeOverlay.icon then
				if hasTrackableRange then
					activeOverlay.icon:SetDesaturated(not hasBuff)
					if not hasBuff then
						activeOverlay.icon:SetVertexColor(0.6, 0.6, 0.6)
					else
						activeOverlay.icon:SetVertexColor(1, 1, 1)
					end
				else
					activeOverlay.icon:SetDesaturated(false)
					activeOverlay.icon:SetVertexColor(1, 1, 1)
				end
			end
		else
			local totemBtn = self.totemButtons[element]
			local iconTexture = totemBtn and totemBtn.icon
			if iconTexture then
				if haveTotem then
					if hasTrackableRange then
						iconTexture:SetDesaturated(not hasBuff)
					else
						iconTexture:SetDesaturated(false)
					end
				else
					iconTexture:SetDesaturated(false)
				end
			end
		end
	end
end

-- ============================================================================
-- Cooldown Tracker Bar (tracks shields, ankh, nature's swiftness, etc.)
-- ============================================================================

ShamanPower.cooldownBar = nil
ShamanPower.cooldownButtons = {}

-- Spells to track on the cooldown bar
-- Format: {spellID, name, type} where type is "buff", "cooldown", or "shield"
ShamanPower.TrackedCooldowns = {
	{324, "Lightning Shield", "shield", "cdbarShowShields"},   -- Lightning/Water Shield (combined)
	{36936, "Totemic Call", "cooldown", "cdbarShowRecall"},  -- Totemic Call (recall totems)
	{20608, "Reincarnation", "cooldown", "cdbarShowReincarnation"},  -- Ankh cooldown
	{16188, "Nature's Swiftness", "cooldown", "cdbarShowNS"},  -- NS cooldown (Resto talent)
	{16190, "Mana Tide Totem", "cooldown", "cdbarShowManaTide"},  -- Mana Tide cooldown (Resto talent)
	{30823, "Shamanistic Rage", "cooldown", "cdbarShowShamanisticRage"},  -- Shamanistic Rage cooldown (Enhancement talent)
	{2825, "Bloodlust", "cooldown", "cdbarShowBloodlust"},  -- Bloodlust (Horde)
	{32182, "Heroism", "cooldown", "cdbarShowBloodlust"},  -- Heroism (Alliance)
}

-- Shield spell IDs for the combined shield button
ShamanPower.ShieldSpells = {
	{324, "Lightning Shield"},   -- Lightning Shield
	{24398, "Water Shield"},     -- Water Shield (TBC)
}

function ShamanPower:CreateCooldownBar()
	if self.cooldownBar then return end
	if not self.autoButton then return end

	-- Create the cooldown bar frame
	local bar = CreateFrame("Frame", "ShamanPowerCooldownBar", self.autoButton, "BackdropTemplate")
	-- Only apply backdrop if not hidden
	if not self.opt.hideCooldownBarFrame then
		bar:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 12,
			insets = { left = 2, right = 2, top = 2, bottom = 2 }
		})
		bar:SetBackdropColor(0, 0, 0, 0.7)
		bar:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
	end

	self.cooldownBar = bar
	self.cooldownButtons = {}

	-- Add drag handlers for independent positioning (ALT+drag on bar itself)
	bar:SetScript("OnDragStart", function(self)
		-- ALT+drag always works when bar is unlocked (ignores frame position lock)
		if not ShamanPower.opt.cooldownBarLocked and IsAltKeyDown() then
			ShamanPower.cooldownBarDragging = true
			self:StartMoving()
		end
	end)

	bar:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		-- Only save position if we were actually dragging
		if ShamanPower.cooldownBarDragging then
			-- Save full anchor info so restore uses exact same positioning
			local point, _, relPoint, x, y = self:GetPoint()
			ShamanPower.opt.cooldownBarPoint = point
			ShamanPower.opt.cooldownBarRelPoint = relPoint
			ShamanPower.opt.cooldownBarPosX = x
			ShamanPower.opt.cooldownBarPosY = y
			ShamanPower.cooldownBarDragging = false
		end
	end)

	-- Create drag handle CheckButton for cooldown bar (like main frame drag handle)
	-- Only visible when CD bar is unlocked from totem bar
	-- Green = position movable, Red = position locked
	local dragHandle = CreateFrame("CheckButton", "ShamanPowerCDBarDragHandle", bar)
	dragHandle:SetSize(16, 16)
	dragHandle:SetPoint("LEFT", bar, "LEFT", -18, 0)
	dragHandle:RegisterForDrag("LeftButton")
	dragHandle:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	dragHandle:SetMovable(false)
	dragHandle:EnableMouse(true)

	-- Normal texture (green - position movable)
	dragHandle:SetNormalTexture("Interface\\AddOns\\ShamanPower\\Icons\\draghandle")
	-- Checked texture (red - position locked)
	dragHandle:SetCheckedTexture("Interface\\AddOns\\ShamanPower\\Icons\\draghandle-checked")

	-- Click to toggle position lock (not bar attachment)
	dragHandle:SetScript("OnClick", function(self, mousebutton)
		if InCombatLockdown() then return end
		if mousebutton == "LeftButton" then
			-- Toggle frame lock (whether position can be changed)
			ShamanPower.opt.cooldownBarFrameLocked = not ShamanPower.opt.cooldownBarFrameLocked
			self:SetChecked(ShamanPower.opt.cooldownBarFrameLocked)
		end
	end)

	dragHandle:SetScript("OnDragStart", function(self)
		-- Only allow dragging when position is not locked
		if not ShamanPower.opt.cooldownBarFrameLocked then
			ShamanPower.cooldownBarDragging = true
			ShamanPower.cooldownBar:StartMoving()
		end
	end)

	dragHandle:SetScript("OnDragStop", function(self)
		ShamanPower.cooldownBar:StopMovingOrSizing()
		-- Only save position if we were actually dragging
		if ShamanPower.cooldownBarDragging then
			-- Save full anchor info so restore uses exact same positioning
			local point, _, relPoint, x, y = ShamanPower.cooldownBar:GetPoint()
			ShamanPower.opt.cooldownBarPoint = point
			ShamanPower.opt.cooldownBarRelPoint = relPoint
			ShamanPower.opt.cooldownBarPosX = x
			ShamanPower.opt.cooldownBarPosY = y
			ShamanPower.cooldownBarDragging = false
		end
	end)

	dragHandle:SetScript("OnEnter", function(self)
		if ShamanPower.opt.ShowTooltips then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText("|cffffffffLeft-Click|r Lock/Unlock Position\n|cffffffffDrag|r Move Cooldown Bar")
			GameTooltip:Show()
		end
	end)

	dragHandle:SetScript("OnLeave", function(self)
		GameTooltip:Hide()
	end)

	-- Set initial checked state (checked = position locked = red)
	dragHandle:SetChecked(self.opt.cooldownBarFrameLocked)
	dragHandle:Hide()  -- Hidden by default, only shown when CD bar unlocked from totem bar
	self.cooldownBarDragHandle = dragHandle

	-- Create buttons for each tracked spell
	local buttonSize = 22
	local spacing = self.opt.cooldownBarPadding or 2
	local padding = 4
	local numButtons = 0

	for i, spellData in ipairs(self.TrackedCooldowns) do
		local spellID, spellName, spellType, optionKey = spellData[1], spellData[2], spellData[3], spellData[4]
		local name, _, icon = GetSpellInfo(spellID)

		-- Check if this item is enabled in options (default to true if not set)
		local isEnabled = (optionKey == nil) or (self.opt[optionKey] ~= false)

		-- Skip Totemic Call on cooldown bar if it should be on totem bar instead
		if spellID == 36936 and self.opt.totemicCallOnTotemBar then
			isEnabled = false
		end

		-- For shield type, check if player knows any shield spell
		-- (check regardless of isEnabled - hidden buttons still need to be functional)
		local knowsSpell = false
		local defaultShieldSpell = nil
		if spellType == "shield" then
			-- Check preferred shield first (use spell name for Classic compatibility)
			local preferredShield = self.opt.preferredShield or 1
			local preferredData = self.ShieldSpells[preferredShield]
			if preferredData and PlayerKnowsSpellByName(preferredData[2]) then
				knowsSpell = true
				defaultShieldSpell = preferredData[2]  -- Use spell name for casting
				local sName, _, sIcon = GetSpellInfo(preferredData[2])
				if sIcon then icon = sIcon end
			else
				-- Fall back to any known shield
				for _, shieldData in ipairs(self.ShieldSpells) do
					if PlayerKnowsSpellByName(shieldData[2]) then
						knowsSpell = true
						defaultShieldSpell = shieldData[2]  -- Use spell name for casting
						local sName, _, sIcon = GetSpellInfo(shieldData[2])
						if sIcon then icon = sIcon end
						break
					end
				end
			end
		else
			-- Try IsSpellKnown first, fall back to name check for Classic compatibility
			knowsSpell = name and (IsSpellKnown(spellID) or PlayerKnowsSpellByName(spellName))
		end

		-- Only create button if player knows this spell and it's enabled
		if knowsSpell and isEnabled then
			numButtons = numButtons + 1

			-- Use different templates for shield (needs combat flyout) vs other buttons
			local templateString
			if spellType == "shield" then
				-- Shield button needs secure handler templates for combat-functional flyout
				templateString = "SecureActionButtonTemplate, SecureHandlerEnterLeaveTemplate, SecureHandlerBaseTemplate"
			else
				templateString = "SecureActionButtonTemplate"
			end
			local btn = CreateFrame("Button", "ShamanPowerCD" .. i, bar, templateString)
			btn:SetSize(buttonSize, buttonSize)
			btn:RegisterForClicks("AnyUp", "AnyDown")

			local iconTex = btn:CreateTexture(nil, "ARTWORK")
			iconTex:SetAllPoints()
			iconTex:SetTexture(icon)
			iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			btn.icon = iconTex

			-- Cooldown overlay
			local cd = CreateFrame("Cooldown", "ShamanPowerCD" .. i .. "Cooldown", btn, "CooldownFrameTemplate")
			cd:SetAllPoints()
			cd:SetDrawEdge(false)
			cd:SetDrawBling(false)
			btn.cooldown = cd

			-- Dark overlay for when buff is missing
			local dark = btn:CreateTexture(nil, "OVERLAY")
			dark:SetAllPoints()
			dark:SetColorTexture(0, 0, 0, 0.6)
			dark:Hide()
			btn.darkOverlay = dark

			-- Progress bar elements (position set dynamically in UpdateCooldownBarProgressBars)
			local barSize = self.opt.cdbarProgressBarHeight or 3

			-- Background bar
			local bgBar = btn:CreateTexture(nil, "OVERLAY")
			bgBar:SetColorTexture(0, 0, 0, 0.7)
			bgBar:Hide()
			btn.bgBar = bgBar

			-- Progress bar (colored)
			local progressBar = btn:CreateTexture(nil, "OVERLAY", nil, 1)
			progressBar:SetColorTexture(0.2, 0.8, 0.2, 0.9)
			progressBar:Hide()
			btn.progressBar = progressBar

			-- Grey sweep overlay for visual timer
			local greyOverlay = btn:CreateTexture(nil, "ARTWORK", nil, 1)
			greyOverlay:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
			greyOverlay:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, 0)
			greyOverlay:SetHeight(0)
			greyOverlay:SetTexture(icon)
			greyOverlay:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			greyOverlay:SetDesaturated(true)
			greyOverlay:SetVertexColor(0.5, 0.5, 0.5)
			greyOverlay:Hide()
			btn.greyOverlay = greyOverlay

			-- Time text for showing remaining duration (center of button - legacy)
			local timeText = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
			timeText:SetPoint("CENTER", btn, "CENTER", 0, 0)
			timeText:SetText("")
			btn.timeText = timeText

			-- Duration text INSIDE the bar
			local insideText = btn:CreateFontString(nil, "OVERLAY", nil, 7)
			insideText:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
			insideText:SetTextColor(1, 1, 1)
			insideText:Hide()
			btn.insideText = insideText

			-- Duration text OUTSIDE the bar
			local outsideText = btn:CreateFontString(nil, "OVERLAY")
			outsideText:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
			outsideText:SetTextColor(1, 1, 1)
			outsideText:Hide()
			btn.outsideText = outsideText
			btn.belowText = outsideText  -- Compatibility

			-- Duration text ON the icon
			local iconText = btn:CreateFontString(nil, "OVERLAY")
			iconText:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
			iconText:SetPoint("CENTER", btn, "CENTER", 0, 0)
			iconText:SetTextColor(1, 1, 1)
			iconText:Hide()
			btn.iconText = iconText

			-- Keybind text (top right corner, like standard action buttons)
			local keybindText = btn:CreateFontString(nil, "OVERLAY")
			keybindText:SetFont("Fonts\\ARIALN.TTF", 9, "OUTLINE")
			keybindText:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 1, 0)
			keybindText:SetTextColor(0.9, 0.9, 0.9, 1)
			keybindText:SetText("")
			keybindText:Hide()  -- Hidden by default, shown if option enabled
			btn.keybindText = keybindText

			-- Charge count text for shield buttons (bottom right corner)
			if spellType == "shield" then
				local chargeText = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
				chargeText:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
				chargeText:SetText("")
				btn.chargeText = chargeText
			end

			-- Store spell info
			btn.spellID = spellID
			btn.spellName = spellName
			btn.spellType = spellType
			btn.defaultShieldSpell = defaultShieldSpell

			-- Assign cooldownType for ordering (1=Shield, 2=Recall, 3=Ankh, 4=NS, 5=MTT, 6=BL/Hero, 7=Imbue)
			-- TrackedCooldowns indices: 1=Shield, 2=Recall, 3=Ankh, 4=NS, 5=MTT, 6=BL, 7=Hero
			-- BL and Heroism both map to type 6
			if i <= 5 then
				btn.cooldownType = i
			else
				btn.cooldownType = 6  -- Both BL (index 6) and Heroism (index 7) are type 6
			end

			-- Store reference to shield button for flyout
			if spellType == "shield" then
				self.shieldButton = btn
			end

			-- Set up click action
			if spellType == "shield" then
				-- Shield button casts the preferred shield
				local shieldSpellName = GetSpellInfo(defaultShieldSpell)
				if shieldSpellName then
					btn:SetAttribute("type1", "spell")
					btn:SetAttribute("spell1", shieldSpellName)
				end

				-- SECURE HANDLER: Show flyout on enter (WORKS IN COMBAT)
				btn:SetAttribute("OpenMenu", "mouseover")
				btn:SetAttribute("_onenter", [[
					if self:GetAttribute("OpenMenu") == "mouseover" then
						self:ChildUpdate("show", true)
					end
				]])

				-- SECURE HANDLER: Hide flyout on leave (WORKS IN COMBAT)
				btn:SetAttribute("_onleave", [[
					if not self:IsUnderMouse(true) then
						self:ChildUpdate("show", false)
					end
				]])
			else
				-- Regular cooldown buttons cast their spell
				local castSpellName = GetSpellInfo(spellID)
				if castSpellName then
					btn:SetAttribute("type1", "spell")
					btn:SetAttribute("spell1", castSpellName)
				end
			end

			-- Tooltip and flyout
			if spellType == "shield" then
				-- Use HookScript for tooltip (works alongside secure handlers)
				btn:HookScript("OnEnter", function(self)
					GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
					GameTooltip:SetText("Shield Spells")
					if self.activeShieldID then
						local activeName = GetSpellInfo(self.activeShieldID)
						GameTooltip:AddLine("Active: " .. (activeName or "Unknown"), 0, 1, 0)
					else
						GameTooltip:AddLine("No shield active", 1, 0.5, 0.5)
					end
					if ShamanPower.opt.enableMiddleClickPopOut ~= false then
						GameTooltip:AddLine("|cff00ccffMiddle-click:|r Pop out", 1, 1, 1)
					end
					GameTooltip:Show()
				end)

				btn:HookScript("OnLeave", function()
					GameTooltip:Hide()
				end)
			else
				btn:SetScript("OnEnter", function(self)
					GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
					GameTooltip:SetSpellByID(self.spellID)
					if ShamanPower.opt.enableMiddleClickPopOut ~= false then
						GameTooltip:AddLine("|cff00ccffMiddle-click:|r Pop out", 1, 1, 1)
					end
					GameTooltip:Show()
				end)
				btn:SetScript("OnLeave", function()
					GameTooltip:Hide()
				end)
			end

			-- Middle-click to pop out cooldown item (or return/settings if already popped)
			btn:HookScript("OnClick", function(self, button)
				if button == "MiddleButton" then
					-- Check if pop-out is enabled
					if ShamanPower.opt.enableMiddleClickPopOut == false then return end

					local cdType = self.cooldownType
					local key = "cd_" .. cdType

					if ShamanPower.opt.poppedOut and ShamanPower.opt.poppedOut[key] then
						-- Already popped out
						if IsShiftKeyDown() then
							-- SHIFT+middle-click opens settings
							local frame = ShamanPower.poppedOutFrames[key]
							if frame then
								ShamanPower:ShowPopOutSettingsPanel(key, frame)
							end
						else
							-- Plain middle-click returns to bar
							if InCombatLockdown() then
								print("|cffff0000ShamanPower:|r Cannot modify pop-outs during combat")
								return
							end
							ShamanPower:ReturnPopOutToBar(key)
						end
					else
						-- Not popped out, pop it out
						if InCombatLockdown() then
							print("|cffff0000ShamanPower:|r Cannot pop out during combat")
							return
						end
						ShamanPower:PopOutCooldownItem(cdType)
					end
				end
			end)

			-- Track if button is hidden in options (still functional but not shown)
			btn.isHiddenInOptions = not isEnabled
			if not isEnabled then
				btn:Hide()
			end

			self.cooldownButtons[numButtons] = btn
		end
	end

	-- Store layout parameters for later use
	bar.buttonSize = buttonSize
	bar.spacing = spacing
	bar.padding = padding
	bar.numButtons = numButtons

	-- Initial sizing will be done in UpdateCooldownBarLayout
	if numButtons == 0 then
		bar:SetSize(1, 1)
	end

	-- Register cooldown updates with consolidated update system (5fps)
	if not self.updateSystem.subsystems["cooldownBar"] then
		self:RegisterUpdateSubsystem("cooldownBar", 0.2, function()
			ShamanPower:UpdateCooldownButtons()
			ShamanPower:UpdateWeaponImbueButton()
			if ShamanPower.opt.cooldownBarFullOpacityWhenActive then
				ShamanPower:UpdateCooldownBarOpacity()
			end
			-- Update Totemic Call on totem bar opacity if shown there
			if ShamanPower.opt.totemicCallOnTotemBar then
				ShamanPower:UpdateTotemicCallOpacity()
			end
		end)
	end
	-- Note: Enabled/disabled in UpdateCooldownBarVisibility
end

-- Find a cooldown button by spell ID
function ShamanPower:GetCooldownButtonBySpellID(spellID)
	for _, btn in ipairs(self.cooldownButtons) do
		if btn.spellID == spellID then
			return btn
		end
	end
	return nil
end

-- Add alert effect to a cooldown button (glow, shake, scale up)
function ShamanPower:AddCooldownButtonAlert(spellID)
	-- Check if button animation is enabled
	if self.opt.raidCDShowButtonAnimation == false then return end

	local btn = self:GetCooldownButtonBySpellID(spellID)
	if not btn then return end

	-- Don't add duplicate alerts
	if btn.alertActive then return end
	btn.alertActive = true

	-- Store original size
	btn.originalWidth = btn:GetWidth()
	btn.originalHeight = btn:GetHeight()

	-- Create glow texture if it doesn't exist
	if not btn.glowTexture then
		local glow = btn:CreateTexture(nil, "OVERLAY")
		glow:SetPoint("TOPLEFT", -8, 8)
		glow:SetPoint("BOTTOMRIGHT", 8, -8)
		glow:SetTexture("Interface\\SpellActivationOverlay\\IconAlert")
		glow:SetTexCoord(0.00781250, 0.50781250, 0.27734375, 0.52734375)
		glow:SetBlendMode("ADD")
		glow:Hide()
		btn.glowTexture = glow
	end

	btn.glowTexture:Show()

	-- Start animation (throttled to ~30fps to reduce CPU usage)
	btn.alertElapsed = 0
	btn.alertUpdateElapsed = 0
	btn:SetScript("OnUpdate", function(self, elapsed)
		self.alertElapsed = (self.alertElapsed or 0) + elapsed
		self.alertUpdateElapsed = (self.alertUpdateElapsed or 0) + elapsed
		if self.alertUpdateElapsed < 0.033 then return end  -- ~30fps
		self.alertUpdateElapsed = 0

		-- Glow pulse
		local glowAlpha = 0.5 + 0.5 * math.sin(self.alertElapsed * 6)
		if self.glowTexture then
			self.glowTexture:SetAlpha(glowAlpha)
		end

		-- Scale pulse (grow to 1.15x then back) - removed shake for performance
		local scale = 1.0 + 0.15 * math.sin(self.alertElapsed * 4)
		local newWidth = (self.originalWidth or 22) * scale
		local newHeight = (self.originalHeight or 22) * scale
		self:SetSize(newWidth, newHeight)
	end)

	-- Auto-clear after 10 seconds
	C_Timer.After(10, function()
		ShamanPower:RemoveCooldownButtonAlert(spellID)
	end)
end

-- Remove alert effect from a cooldown button
function ShamanPower:RemoveCooldownButtonAlert(spellID)
	local btn = self:GetCooldownButtonBySpellID(spellID)
	if not btn then return end

	btn.alertActive = false

	-- Hide glow
	if btn.glowTexture then
		btn.glowTexture:Hide()
	end

	-- Stop animation
	btn:SetScript("OnUpdate", nil)

	-- Restore original size
	if btn.originalWidth and btn.originalHeight then
		btn:SetSize(btn.originalWidth, btn.originalHeight)
	end
end

-- Helper to get progress bar color based on time remaining (milliseconds)
local function GetTimerBarColor(expiration)
	local mins = expiration / 60000
	if mins < 5 then
		return 0.9, 0.2, 0.2  -- Red when critical
	elseif mins < 10 then
		return 0.9, 0.7, 0.2  -- Yellow/orange when low
	else
		return 0.2, 0.8, 0.2  -- Green when healthy
	end
end

-- Update cooldown bar layout (horizontal or vertical)
function ShamanPower:UpdateCooldownBarLayout()
	if not self.cooldownBar then return end
	if #self.cooldownButtons == 0 then return end

	-- Sort cooldownButtons by cooldownBarOrder
	local cooldownBarOrder = self.opt.cooldownBarOrder or {1, 2, 3, 4, 5, 6, 7}

	-- Create a lookup table for order position (cooldownType -> position)
	local orderLookup = {}
	for position, cooldownType in ipairs(cooldownBarOrder) do
		orderLookup[cooldownType] = position
	end

	-- Sort by order position
	table.sort(self.cooldownButtons, function(a, b)
		local orderA = orderLookup[a.cooldownType] or 99
		local orderB = orderLookup[b.cooldownType] or 99
		return orderA < orderB
	end)

	local bar = self.cooldownBar
	local buttonSize = bar.buttonSize or 22
	local spacing = self.opt.cooldownBarPadding or 2
	local padding = bar.padding or 4
	local cdLayout = self.opt.cdbarLayout or self.opt.layout
	local isVertical = (cdLayout == "Vertical" or cdLayout == "VerticalLeft")

	-- Count only visible buttons (not hidden in options and not popped out)
	local visibleButtons = {}
	for _, btn in ipairs(self.cooldownButtons) do
		local isPoppedOut = self:IsCooldownPoppedOut(btn.cooldownType)
		if not btn.isHiddenInOptions and not isPoppedOut then
			table.insert(visibleButtons, btn)
		end
	end
	local numButtons = #visibleButtons

	-- Extra padding for progress bars based on position
	local showBars = self.opt.cdbarShowProgressBars ~= false
	local barPosition = self.opt.cdbarProgressPosition or "left"
	local progressBarSize = self.opt.cdbarProgressBarHeight or 3

	-- Calculate padding based on bar position
	local leftPadding = (showBars and barPosition == "left") and (progressBarSize + 2) or 0
	local rightPadding = (showBars and barPosition == "right") and (progressBarSize + 2) or 0
	local topPadding = (showBars and (barPosition == "top" or barPosition == "top_vert")) and (progressBarSize + 2) or 0
	local bottomPadding = (showBars and (barPosition == "bottom" or barPosition == "bottom_vert")) and (progressBarSize + 2) or 0
	-- Vertical bars on top/bottom need extra height for the bar length
	if showBars and barPosition == "top_vert" then topPadding = buttonSize + 2 end
	if showBars and barPosition == "bottom_vert" then bottomPadding = buttonSize + 2 end

	if isVertical then
		-- Vertical: stack buttons top to bottom
		local barHeight = (buttonSize * numButtons) + (spacing * math.max(numButtons - 1, 0)) + (padding * 2) + topPadding + bottomPadding
		local barWidth = buttonSize + (padding * 2) + leftPadding + rightPadding
		bar:SetSize(barWidth, barHeight)

		for i, btn in ipairs(visibleButtons) do
			btn:ClearAllPoints()
			local xOffset = (leftPadding - rightPadding) / 2
			local yOffset = (topPadding - bottomPadding) / 2
			btn:SetPoint("TOP", bar, "TOP", xOffset, -padding - topPadding - (i - 1) * (buttonSize + spacing) + yOffset)
			btn:Show()
		end

		-- Position drag handle at top of bar for vertical layout
		if self.cooldownBarDragHandle then
			self.cooldownBarDragHandle:ClearAllPoints()
			self.cooldownBarDragHandle:SetPoint("BOTTOM", bar, "TOP", 0, 2)
		end
	else
		-- Horizontal: buttons left to right
		local barWidth = (buttonSize * numButtons) + (spacing * math.max(numButtons - 1, 0)) + (padding * 2) + leftPadding + rightPadding
		local barHeight = buttonSize + (padding * 2) + topPadding + bottomPadding
		bar:SetSize(barWidth, barHeight)

		for i, btn in ipairs(visibleButtons) do
			btn:ClearAllPoints()
			local xOffset = (leftPadding - rightPadding) / 2
			local yOffset = (topPadding - bottomPadding) / 2
			btn:SetPoint("LEFT", bar, "LEFT", padding + leftPadding + (i - 1) * (buttonSize + spacing) - xOffset, yOffset)
			btn:Show()
		end

		-- Position drag handle at left of bar for horizontal layout
		if self.cooldownBarDragHandle then
			self.cooldownBarDragHandle:ClearAllPoints()
			self.cooldownBarDragHandle:SetPoint("RIGHT", bar, "LEFT", -2, 0)
		end
	end

	-- Update progress bar positions for all buttons
	self:UpdateCooldownBarProgressBars()
end

function ShamanPower:UpdateCooldownButtons()
	-- Get display options
	local showBars = self.opt.cdbarShowProgressBars ~= false
	local showSweep = self.opt.cdbarShowColorSweep ~= false
	local showText = self.opt.cdbarShowCDText ~= false
	local barPosition = self.opt.cdbarProgressPosition or "left"
	local barHeight = self.opt.cdbarProgressBarHeight or 3
	local textLocation = self.opt.cdbarDurationTextLocation or "none"

	-- Use numeric for loop instead of ipairs to avoid iterator garbage
	for i = 1, #self.cooldownButtons do
		local btn = self.cooldownButtons[i]
		local buttonHeight = btn:GetHeight()
		local buttonWidth = btn:GetWidth()

		if btn.spellType == "shield" then
			-- Use cached shield state from UNIT_AURA event (no UnitBuff calls here!)
			local cache = self.shieldCache
			local hasShield = false
			local activeShieldID = nil
			local activeShieldIcon = nil
			local shieldDuration = 0
			local shieldExpiration = 0
			local shieldCharges = 0

			if not cache then
				-- No cache yet, do initial scan
				self:ScanPlayerShield()
				cache = self.shieldCache
			end

			if cache and cache.hasShield then
				-- Use fully cached values - no UnitBuff calls needed!
				-- Duration/charges are updated by UNIT_AURA event when shield procs
				hasShield = true
				activeShieldID = cache.shieldID
				activeShieldIcon = cache.shieldIcon
				shieldCharges = cache.shieldCharges
				shieldDuration = cache.shieldDuration
				shieldExpiration = cache.shieldExpiration
			end
			-- If cache exists and hasShield is false, we know there's no shield - no scanning needed!

			if hasShield then
				btn.darkOverlay:Hide()
				btn.icon:SetDesaturated(false)
				if activeShieldIcon then
					btn.icon:SetTexture(activeShieldIcon)
					if btn.greyOverlay then
						btn.greyOverlay:SetTexture(activeShieldIcon)
					end
				end
				btn.activeShieldID = activeShieldID

				-- Calculate remaining time
				local remaining = shieldExpiration - GetTime()
				local maxDuration = shieldDuration > 0 and shieldDuration or 600  -- Default 10 min

				-- Show charge count with optional coloring
				if btn.chargeText then
					if shieldCharges > 0 then
						btn.chargeText:SetText(NumberStrings[shieldCharges] or tostring(shieldCharges))
						-- Color based on charges if enabled
						if self.opt.shieldChargeColors then
							if shieldCharges >= 3 then
								btn.chargeText:SetTextColor(0, 1, 0)  -- Green (full/high)
							elseif shieldCharges == 2 then
								btn.chargeText:SetTextColor(1, 1, 0)  -- Yellow (half)
							else
								btn.chargeText:SetTextColor(1, 0, 0)  -- Red (low - 1 charge)
							end
						else
							btn.chargeText:SetTextColor(1, 1, 1)  -- White (default)
						end
					else
						btn.chargeText:SetText("")
					end
				end

				-- Progress bar (for shields, show based on time remaining)
				local isVerticalBar = (barPosition == "left" or barPosition == "right" or barPosition == "top_vert" or barPosition == "bottom_vert")
				if showBars and btn.progressBar and shieldDuration > 0 then
					local percent = math.min(remaining / maxDuration, 1)
					local r, g, b = GetTimerBarColor(remaining * 1000)

					if btn.bgBar then btn.bgBar:Show() end
					btn.progressBar:ClearAllPoints()

					if isVerticalBar then
						-- Vertical bar
						local progressHeight = math.max(buttonHeight * percent, 1)
						btn.progressBar:SetSize(barHeight, progressHeight)
						if barPosition == "left" then
							btn.progressBar:SetPoint("BOTTOMRIGHT", btn, "BOTTOMLEFT", -1, 0)
						elseif barPosition == "right" then
							btn.progressBar:SetPoint("BOTTOMLEFT", btn, "BOTTOMRIGHT", 1, 0)
						elseif barPosition == "top_vert" then
							btn.progressBar:SetPoint("BOTTOM", btn.bgBar, "BOTTOM", 0, 0)
						elseif barPosition == "bottom_vert" then
							btn.progressBar:SetPoint("BOTTOM", btn.bgBar, "BOTTOM", 0, 0)
						end
					else
						-- Horizontal bar (top/bottom)
						local progressWidth = math.max(buttonWidth * percent, 1)
						btn.progressBar:SetSize(progressWidth, barHeight)
						if barPosition == "bottom" then
							btn.progressBar:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -1)
						else
							btn.progressBar:SetPoint("BOTTOMLEFT", btn, "TOPLEFT", 0, 1)
						end
					end
					btn.progressBar:SetColorTexture(r, g, b, 0.9)
					btn.progressBar:Show()
				else
					if btn.progressBar then btn.progressBar:Hide() end
					if btn.bgBar then btn.bgBar:Hide() end
				end

				-- Grey sweep overlay
				if showSweep and btn.greyOverlay and shieldDuration > 0 then
					local percent = math.min(remaining / maxDuration, 1)
					local depletedPercent = 1 - percent
					local greyHeight = buttonHeight * depletedPercent
					if greyHeight > 1 then
						btn.greyOverlay:ClearAllPoints()
						btn.greyOverlay:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
						btn.greyOverlay:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, 0)
						btn.greyOverlay:SetHeight(greyHeight)
						local texBottom = 0.08 + (depletedPercent * 0.84)
						btn.greyOverlay:SetTexCoord(0.08, 0.92, 0.08, texBottom)
						btn.greyOverlay:Show()
					else
						btn.greyOverlay:Hide()
					end
				elseif btn.greyOverlay then
					btn.greyOverlay:Hide()
				end

				-- Duration text handling for shields
				local durationStr = nil
				if shieldDuration > 0 then
					durationStr = FormatDuration(remaining)
				end

				-- Hide all duration texts first
				if btn.timeText then btn.timeText:SetText("") end
				if btn.insideText then btn.insideText:Hide() end
				if btn.outsideText then btn.outsideText:Hide() end
				if btn.belowText and btn.belowText ~= btn.outsideText then btn.belowText:Hide() end
				if btn.iconText then btn.iconText:Hide() end

				-- Show duration text at chosen location
				if durationStr then
					if textLocation == "inside" then
						if btn.insideText then
							btn.insideText:SetText(durationStr)
							btn.insideText:Show()
						end
					elseif textLocation == "outside" then
						if btn.outsideText then
							btn.outsideText:SetText(durationStr)
							btn.outsideText:Show()
						end
					elseif textLocation == "icon" then
						if btn.iconText then
							btn.iconText:SetText(durationStr)
							btn.iconText:Show()
						end
					end
				end
			else
				btn.darkOverlay:Show()
				btn.icon:SetDesaturated(true)
				btn.activeShieldID = nil
				if btn.chargeText then btn.chargeText:SetText("") end
				if btn.progressBar then btn.progressBar:Hide() end
				if btn.bgBar then btn.bgBar:Hide() end
				if btn.greyOverlay then btn.greyOverlay:Hide() end
				if btn.timeText then btn.timeText:SetText("") end
				if btn.insideText then btn.insideText:Hide() end
				if btn.outsideText then btn.outsideText:Hide() end
				if btn.belowText and btn.belowText ~= btn.outsideText then btn.belowText:Hide() end
				if btn.iconText then btn.iconText:Hide() end
			end
			btn.cooldown:Clear()

		elseif btn.spellType == "cooldown" then
			-- Check cooldown
			local start, duration, enabled = GetSpellCooldown(btn.spellID)
			if start and start > 0 and duration > 1.5 then
				-- Clear radial swipe - use vertical grey sweep instead (like shields/imbues)
				btn.cooldown:Clear()
				btn.darkOverlay:Hide()
				btn.icon:SetDesaturated(false)

				-- Calculate remaining time
				local remaining = (start + duration) - GetTime()
				local percent = math.min(remaining / duration, 1)

				-- Progress bar
				local isVerticalBar = (barPosition == "left" or barPosition == "right" or barPosition == "top_vert" or barPosition == "bottom_vert")
				if showBars and btn.progressBar then
					local r, g, b = GetTimerBarColor(remaining * 1000)

					if btn.bgBar then btn.bgBar:Show() end
					btn.progressBar:ClearAllPoints()

					if isVerticalBar then
						-- Vertical bar
						local progressHeight = math.max(buttonHeight * percent, 1)
						btn.progressBar:SetSize(barHeight, progressHeight)
						if barPosition == "left" then
							btn.progressBar:SetPoint("BOTTOMRIGHT", btn, "BOTTOMLEFT", -1, 0)
						elseif barPosition == "right" then
							btn.progressBar:SetPoint("BOTTOMLEFT", btn, "BOTTOMRIGHT", 1, 0)
						elseif barPosition == "top_vert" then
							btn.progressBar:SetPoint("BOTTOM", btn.bgBar, "BOTTOM", 0, 0)
						elseif barPosition == "bottom_vert" then
							btn.progressBar:SetPoint("BOTTOM", btn.bgBar, "BOTTOM", 0, 0)
						end
					else
						-- Horizontal bar (top/bottom)
						local progressWidth = math.max(buttonWidth * percent, 1)
						btn.progressBar:SetSize(progressWidth, barHeight)
						if barPosition == "bottom" then
							btn.progressBar:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -1)
						else
							btn.progressBar:SetPoint("BOTTOMLEFT", btn, "TOPLEFT", 0, 1)
						end
					end
					btn.progressBar:SetColorTexture(r, g, b, 0.9)
					btn.progressBar:Show()
				else
					if btn.progressBar then btn.progressBar:Hide() end
					if btn.bgBar then btn.bgBar:Hide() end
				end

				-- Grey sweep overlay (vertical, from top)
				if showSweep and btn.greyOverlay then
					local depletedPercent = 1 - percent
					local greyHeight = buttonHeight * depletedPercent
					if greyHeight > 1 then
						btn.greyOverlay:ClearAllPoints()
						btn.greyOverlay:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
						btn.greyOverlay:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, 0)
						btn.greyOverlay:SetHeight(greyHeight)
						local texBottom = 0.08 + (depletedPercent * 0.84)
						btn.greyOverlay:SetTexCoord(0.08, 0.92, 0.08, texBottom)
						btn.greyOverlay:Show()
					else
						btn.greyOverlay:Hide()
					end
				elseif btn.greyOverlay then
					btn.greyOverlay:Hide()
				end

				-- Duration text handling
				local durationStr = FormatDuration(remaining)

				-- Hide all duration texts first
				if btn.timeText then btn.timeText:SetText("") end
				if btn.insideText then btn.insideText:Hide() end
				if btn.outsideText then btn.outsideText:Hide() end
				if btn.belowText and btn.belowText ~= btn.outsideText then btn.belowText:Hide() end
				if btn.iconText then btn.iconText:Hide() end

				-- Show duration text at chosen location
				if textLocation == "inside" then
					if btn.insideText then
						btn.insideText:SetText(durationStr)
						btn.insideText:Show()
					end
				elseif textLocation == "outside" then
					if btn.outsideText then
						btn.outsideText:SetText(durationStr)
						btn.outsideText:Show()
					end
				elseif textLocation == "icon" then
					if btn.iconText then
						btn.iconText:SetText(durationStr)
						btn.iconText:Show()
					end
				elseif textLocation == "none" and showText then
					-- Legacy: show text on icon if CD Text toggle is enabled
					if btn.timeText then
						btn.timeText:SetText(durationStr)
					end
				end
			else
				btn.cooldown:Clear()
				btn.darkOverlay:Hide()
				btn.icon:SetDesaturated(false)
				if btn.progressBar then btn.progressBar:Hide() end
				if btn.bgBar then btn.bgBar:Hide() end
				if btn.greyOverlay then btn.greyOverlay:Hide() end
				if btn.timeText then btn.timeText:SetText("") end
				if btn.insideText then btn.insideText:Hide() end
				if btn.outsideText then btn.outsideText:Hide() end
				if btn.belowText and btn.belowText ~= btn.outsideText then btn.belowText:Hide() end
				if btn.iconText then btn.iconText:Hide() end
			end
		end
	end
end

function ShamanPower:UpdateCooldownBar()
	if not isShaman then return end
	-- Don't update while dragging
	if self.cooldownBarDragging then return end

	if not self.cooldownBar then
		self:CreateCooldownBar()
	end

	-- Create weapon imbue button if not exists
	if not self.weaponImbueButton then
		self:CreateWeaponImbueButton()
	end

	-- Create shield flyout if shield button exists but flyout doesn't
	if self.shieldButton and not self.shieldFlyout then
		self:CreateShieldFlyout()
	end

	if not self.cooldownBar then return end

	if self.opt.showCooldownBar and #self.cooldownButtons > 0 then
		-- Update the button layout first
		self:UpdateCooldownBarLayout()

		-- Position based on lock state
		if self.opt.cooldownBarLocked then
			-- Locked: anchor to totem bar based on layout orientation
			local isVertical = (self.opt.layout == "Vertical" or self.opt.layout == "VerticalLeft")
			local isVerticalLeft = (self.opt.layout == "VerticalLeft")
			self.cooldownBar:ClearAllPoints()
			if isVertical then
				if isVerticalLeft then
					-- Vertical (Left): bar on left side of screen, CDs go to the RIGHT of totems
					self.cooldownBar:SetPoint("LEFT", self.autoButton, "RIGHT", 2, 0)
				else
					-- Vertical (Right): bar on right side of screen, CDs go to the LEFT of totems
					self.cooldownBar:SetPoint("RIGHT", self.autoButton, "LEFT", -2, 0)
				end
			else
				-- Horizontal: position below the main totem bar
				self.cooldownBar:SetPoint("TOP", self.autoButton, "BOTTOM", 0, -2)
			end
			-- Hide drag handle when CD bar is locked to totem bar
			if self.cooldownBarDragHandle then
				self.cooldownBarDragHandle:Hide()
			end
		else
			-- Unlocked: set up independent positioning
			self:UpdateCooldownBarPosition()
		end
		self.cooldownBar:Show()
		self:EnableUpdateSubsystem("cooldownBar")

		-- Apply scale
		self:UpdateCooldownBarScale()
	else
		self.cooldownBar:Hide()
		self:DisableUpdateSubsystem("cooldownBar")
	end
end

function ShamanPower:RecreateCooldownBar()
	if InCombatLockdown() then return end

	-- Destroy existing cooldown bar and drag handle
	if self.cooldownBarDragHandle then
		self.cooldownBarDragHandle:Hide()
		self.cooldownBarDragHandle = nil
	end
	if self.cooldownBar then
		self.cooldownBar:Hide()
		self.cooldownBar:SetParent(nil)
		self.cooldownBar = nil
	end
	self.cooldownButtons = {}

	-- Destroy existing weapon imbue button and flyout
	if self.weaponImbueButton then
		self.weaponImbueButton:Hide()
		self.weaponImbueButton:SetParent(nil)
		self.weaponImbueButton = nil
	end
	if self.weaponImbueFlyout then
		-- Weapon imbue flyout buttons are children of imbue button, clean them up
		if self.weaponImbueFlyout.buttons then
			for _, btn in ipairs(self.weaponImbueFlyout.buttons) do
				btn:Hide()
				btn:SetParent(nil)
			end
		end
		self.weaponImbueFlyout = nil
	end

	-- Destroy existing shield button and flyout
	if self.shieldButton then
		self.shieldButton = nil  -- Reference only, actual button is in cooldownButtons
	end
	if self.shieldFlyout then
		-- Shield flyout buttons are children of shield button, clean them up
		if self.shieldFlyout.buttons then
			for _, btn in ipairs(self.shieldFlyout.buttons) do
				btn:Hide()
				btn:SetParent(nil)
			end
		end
		self.shieldFlyout = nil
	end

	-- Recreate it
	self:CreateCooldownBar()
	self:UpdateCooldownBar()

	-- Create shield flyout after cooldown bar is created
	if self.shieldButton then
		self:CreateShieldFlyout()
	end

	-- Apply lock/unlock state, position, and drag handle visibility
	self:UpdateCooldownBarPosition()
end

-- Update cooldown bar position based on lock state
-- forceReposition: set to true when switching profiles to apply new profile's position
function ShamanPower:UpdateCooldownBarPosition(forceReposition)
	if not self.cooldownBar then return end
	if InCombatLockdown() then return end
	if self.cooldownBarDragging then return end

	if self.opt.cooldownBarLocked then
		-- CD bar is attached to totem bar - hide drag handle
		if self.cooldownBarDragHandle then
			self.cooldownBarDragHandle:Hide()
		end
		self.cooldownBar:SetParent(self.autoButton)
		self.cooldownBar:EnableMouse(false)
		self.cooldownBar:SetMovable(false)
		self:UpdateCooldownBar()
	else
		-- CD bar is independent
		if self.cooldownBarDragHandle then
			self.cooldownBarDragHandle:SetChecked(self.opt.cooldownBarFrameLocked)
			if self.opt.display.enableDragHandle then
				self.cooldownBarDragHandle:Show()
			else
				self.cooldownBarDragHandle:Hide()
			end
		end

		-- Position the bar when first unlocking OR when forcing reposition (profile change)
		if self.cooldownBar:GetParent() ~= UIParent or forceReposition then
			self.cooldownBar:SetParent(UIParent)
			self.cooldownBar:SetFrameStrata("MEDIUM")
			self.cooldownBar:SetFrameLevel(100)
			self.cooldownBar:ClearAllPoints()
			-- Use saved anchor point if available, otherwise default to CENTER
			local point = self.opt.cooldownBarPoint or "CENTER"
			local relPoint = self.opt.cooldownBarRelPoint or "CENTER"
			self.cooldownBar:SetPoint(point, UIParent, relPoint, self.opt.cooldownBarPosX, self.opt.cooldownBarPosY)
		end

		self.cooldownBar:EnableMouse(true)
		self.cooldownBar:SetMovable(true)
		self.cooldownBar:RegisterForDrag("LeftButton")
		self.cooldownBar:Show()
	end

	self:UpdateCooldownBarScale()
end

-- Update cooldown bar scale
function ShamanPower:UpdateCooldownBarScale()
	if not self.cooldownBar then return end

	local cdScale = self.opt.cooldownBarScale or 0.9

	if self.opt.cooldownBarLocked then
		-- When locked, counteract parent scale and apply CD scale
		local parentScale = self.opt.buffscale or 0.9
		self.cooldownBar:SetScale(cdScale / parentScale)
	else
		-- When unlocked (parented to UIParent), apply directly
		self.cooldownBar:SetScale(cdScale)
	end
end

-- Update cooldown bar progress bar positions and sizes
function ShamanPower:UpdateCooldownBarProgressBars()
	local barPosition = self.opt.cdbarProgressPosition or "left"
	local barSize = self.opt.cdbarProgressBarHeight or 3

	for _, btn in ipairs(self.cooldownButtons) do
		local buttonSize = btn:GetWidth()
		local buttonHeight = btn:GetHeight()

		if btn.bgBar then
			btn.bgBar:ClearAllPoints()
			if barPosition == "bottom" then
				-- Horizontal bar below
				btn.bgBar:SetSize(buttonSize, barSize)
				btn.bgBar:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -1)
				btn.bgBar:SetPoint("TOPRIGHT", btn, "BOTTOMRIGHT", 0, -1)
			elseif barPosition == "bottom_vert" then
				-- Vertical bar below (centered)
				btn.bgBar:SetSize(barSize, buttonHeight)
				btn.bgBar:SetPoint("TOP", btn, "BOTTOM", 0, -1)
			elseif barPosition == "top" then
				-- Horizontal bar above
				btn.bgBar:SetSize(buttonSize, barSize)
				btn.bgBar:SetPoint("BOTTOMLEFT", btn, "TOPLEFT", 0, 1)
				btn.bgBar:SetPoint("BOTTOMRIGHT", btn, "TOPRIGHT", 0, 1)
			elseif barPosition == "top_vert" then
				-- Vertical bar above (centered)
				btn.bgBar:SetSize(barSize, buttonHeight)
				btn.bgBar:SetPoint("BOTTOM", btn, "TOP", 0, 1)
			elseif barPosition == "left" then
				-- Vertical bar on left
				btn.bgBar:SetSize(barSize, buttonSize)
				btn.bgBar:SetPoint("TOPRIGHT", btn, "TOPLEFT", -1, 0)
				btn.bgBar:SetPoint("BOTTOMRIGHT", btn, "BOTTOMLEFT", -1, 0)
			elseif barPosition == "right" then
				-- Vertical bar on right
				btn.bgBar:SetSize(barSize, buttonSize)
				btn.bgBar:SetPoint("TOPLEFT", btn, "TOPRIGHT", 1, 0)
				btn.bgBar:SetPoint("BOTTOMLEFT", btn, "BOTTOMRIGHT", 1, 0)
			end
		end

		-- Update inside text position to stay centered in the bar
		if btn.insideText and btn.bgBar then
			btn.insideText:ClearAllPoints()
			btn.insideText:SetPoint("CENTER", btn.bgBar, "CENTER", 0, 0)
			local fontSize = math.max(7, barSize - 2)
			btn.insideText:SetFont("Fonts\\FRIZQT__.TTF", fontSize, "OUTLINE")
		end

		-- Update outside text position based on bar position
		if btn.outsideText and btn.bgBar then
			btn.outsideText:ClearAllPoints()
			if barPosition == "bottom" or barPosition == "bottom_vert" then
				btn.outsideText:SetPoint("TOP", btn.bgBar, "BOTTOM", 0, -1)
			elseif barPosition == "top" or barPosition == "top_vert" then
				btn.outsideText:SetPoint("BOTTOM", btn.bgBar, "TOP", 0, 1)
			elseif barPosition == "left" then
				btn.outsideText:SetPoint("RIGHT", btn.bgBar, "LEFT", -1, 0)
			elseif barPosition == "right" then
				btn.outsideText:SetPoint("LEFT", btn.bgBar, "RIGHT", 1, 0)
			end
		end
	end
end

-- ============================================================================
-- Opacity Functions
-- ============================================================================

function ShamanPower:UpdateTotemBarOpacity()
	local opacity = self.opt.totemBarOpacity or 1.0
	local fullWhenActive = self.opt.totemBarFullOpacityWhenActive

	if self.autoButton then
		self.autoButton:SetAlpha(opacity)
	end

	-- Set alpha on totem buttons - full opacity if totem is placed and option enabled
	if self.totemButtons then
		for element = 1, 4 do
			local btn = self.totemButtons[element]
			if btn then
				if fullWhenActive then
					local slot = self.ElementToSlot and self.ElementToSlot[element]
					local haveTotem = slot and GetTotemInfo(slot)
					btn:SetAlpha(haveTotem and 1.0 or opacity)
				else
					btn:SetAlpha(opacity)
				end
			end
		end
	end

	-- Also set alpha on Earth Shield button
	local esBtn = _G["ShamanPowerEarthShieldBtn"]
	if esBtn then
		if fullWhenActive then
			-- Check if someone has our Earth Shield active
			local hasActiveES = self.esTrackedTarget and self.esTrackedCharges and self.esTrackedCharges > 0
			esBtn:SetAlpha(hasActiveES and 1.0 or opacity)
		else
			esBtn:SetAlpha(opacity)
		end
	end
end

function ShamanPower:UpdateCooldownBarOpacity()
	local opacity = self.opt.cooldownBarOpacity or 1.0
	local fullWhenActive = self.opt.cooldownBarFullOpacityWhenActive

	if self.cooldownBar then
		if fullWhenActive and self.cooldownButtons then
			-- Set bar to full opacity, but we'll control individual button opacity
			self.cooldownBar:SetAlpha(1.0)

			-- Check each button for active state
			for i = 1, #self.cooldownButtons do
				local btn = self.cooldownButtons[i]
				local isActive = false

				if btn.spellType == "shield" then
					-- Shield is active if player has the buff
					isActive = btn.activeShieldID ~= nil
				elseif btn.spellType == "cooldown" then
					-- Check if the buff is active on the player (for spells with buffs)
					local spellID = btn.spellID
					local spellName = btn.spellName

					-- Check for specific buff-based abilities
					if spellID == 16188 then
						-- Nature's Swiftness - check if NS buff is active
						isActive = AuraUtil.FindAuraByName("Nature's Swiftness", "player", "HELPFUL") ~= nil
					elseif spellID == 30823 then
						-- Shamanistic Rage - check if SR buff is active
						isActive = AuraUtil.FindAuraByName("Shamanistic Rage", "player", "HELPFUL") ~= nil
					elseif spellID == 2825 or spellID == 32182 then
						-- Bloodlust/Heroism - check if buff is active
						local hasBL = AuraUtil.FindAuraByName("Bloodlust", "player", "HELPFUL")
						local hasHero = AuraUtil.FindAuraByName("Heroism", "player", "HELPFUL")
						isActive = hasBL ~= nil or hasHero ~= nil
					elseif spellID == 16190 then
						-- Mana Tide Totem - check if MTT is active (water totem slot 3)
						local haveTotem, totemName = GetTotemInfo(3)
						if haveTotem and totemName and totemName:find("Mana Tide") then
							isActive = true
						end
					elseif spellID == 36936 then
						-- Totemic Call - active if any totems are placed
						for slot = 1, 4 do
							local haveTotem = GetTotemInfo(slot)
							if haveTotem then
								isActive = true
								break
							end
						end
					elseif spellID == 20608 then
						-- Reincarnation - active if off cooldown and available
						local start, duration = GetSpellCooldown(spellID)
						isActive = (not start or start == 0 or duration <= 1.5)
					end
				elseif btn.spellType == "imbue" then
					-- Imbue is active if weapon is enchanted
					local hasMain = GetWeaponEnchantInfo()
					isActive = hasMain
				end

				btn:SetAlpha(isActive and 1.0 or opacity)
			end
		else
			self.cooldownBar:SetAlpha(opacity)
			-- Reset all buttons to inherit bar opacity
			if self.cooldownButtons then
				for i = 1, #self.cooldownButtons do
					self.cooldownButtons[i]:SetAlpha(1.0)  -- Full relative to parent
				end
			end
		end
	end
end

function ShamanPower:UpdateTotemFlyoutOpacity()
	local opacity = self.opt.totemFlyoutOpacity or 1.0
	-- Update all totem flyout buttons (flyout is now a table with buttons array)
	if self.totemFlyouts then
		for element = 1, 4 do
			local flyout = self.totemFlyouts[element]
			if flyout and flyout.buttons then
				for _, btn in ipairs(flyout.buttons) do
					btn:SetAlpha(opacity)
				end
			end
		end
	end
end

function ShamanPower:UpdateCooldownFlyoutOpacity()
	local opacity = self.opt.cooldownFlyoutOpacity or 1.0
	-- Update cooldown bar flyouts (shield selector, imbue selector)
	-- Flyouts are now tables with buttons as children of the parent button
	if self.shieldFlyout and self.shieldFlyout.buttons then
		for _, btn in ipairs(self.shieldFlyout.buttons) do
			btn:SetAlpha(opacity)
		end
	end
	if self.weaponImbueFlyout and self.weaponImbueFlyout.buttons then
		for _, btn in ipairs(self.weaponImbueFlyout.buttons) do
			btn:SetAlpha(opacity)
		end
	end
end

-- Apply all opacity settings (called on load/profile change)
function ShamanPower:ApplyAllOpacity()
	self:UpdateTotemBarOpacity()
	self:UpdateCooldownBarOpacity()
	self:UpdateTotemFlyoutOpacity()
	self:UpdateCooldownFlyoutOpacity()
end

-- ============================================================================
-- Weapon Imbue Bar (for applying weapon enchants)
-- ============================================================================

ShamanPower.weaponImbueButton = nil
ShamanPower.weaponImbueFlyout = nil
ShamanPower.lastMainHandImbue = nil  -- Last imbue applied to main hand
ShamanPower.lastOffHandImbue = nil   -- Last imbue applied to off hand

-- Check if player can dual wield (Enhancement talent)
function ShamanPower:CanDualWield()
	-- Check if player has an off-hand weapon equipped
	local offHandLink = GetInventoryItemLink("player", 17)  -- SecondaryHandSlot
	if offHandLink then
		-- Check if it's a weapon (not a shield)
		local _, _, _, _, _, itemType = GetItemInfo(offHandLink)
		if itemType == "Weapon" then
			return true
		end
	end
	return false
end

-- Get the highest rank of a weapon imbue spell that the player knows
function ShamanPower:GetHighestRankImbue(imbueIndex)
	local baseSpellID = self.WeaponImbueSpells[imbueIndex]
	if not baseSpellID then return nil end

	local baseName = GetSpellInfo(baseSpellID)
	if not baseName then return nil end

	-- Try to find the spell in the spellbook (gets highest rank)
	local spellName = baseName
	if GetSpellInfo(spellName) and PlayerKnowsSpellByName(spellName) then
		return spellName
	end

	return nil
end

-- Create the weapon imbue button on the cooldown bar
function ShamanPower:CreateWeaponImbueButton()
	if self.weaponImbueButton then return end
	if not self.cooldownBar then return end
	if InCombatLockdown() then return end

	-- Check if imbues are enabled in options
	if self.opt.cdbarShowImbues == false then return end

	-- Check if player knows any weapon imbue
	local knowsAnyImbue = false
	for i = 1, 4 do
		if self:GetHighestRankImbue(i) then
			knowsAnyImbue = true
			break
		end
	end

	if not knowsAnyImbue then return end

	local buttonSize = self.cooldownBar.buttonSize or 22

	-- Create the button with secure templates for combat-functional flyout
	local btn = CreateFrame("Button", "ShamanPowerWeaponImbue", self.cooldownBar,
		"SecureActionButtonTemplate, SecureHandlerEnterLeaveTemplate, SecureHandlerBaseTemplate")
	btn:SetSize(buttonSize, buttonSize)
	btn:RegisterForClicks("LeftButtonUp", "LeftButtonDown", "RightButtonUp", "RightButtonDown")

	-- Icon texture (will be updated based on current enchants)
	local iconTex = btn:CreateTexture(nil, "ARTWORK")
	iconTex:SetAllPoints()
	iconTex:SetTexture(self.WeaponIcons[1])  -- Default to Windfury icon
	iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	btn.icon = iconTex

	-- Second icon for split display (off-hand)
	local icon2 = btn:CreateTexture(nil, "ARTWORK")
	icon2:SetPoint("TOPLEFT", btn, "CENTER", 0, 0)
	icon2:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
	icon2:SetTexture(self.WeaponIcons[2])  -- Default to Flametongue
	icon2:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	icon2:Hide()
	btn.icon2 = icon2

	-- Dark overlay for when no enchant is active
	local dark = btn:CreateTexture(nil, "OVERLAY")
	dark:SetAllPoints()
	dark:SetColorTexture(0, 0, 0, 0.6)
	dark:Hide()
	btn.darkOverlay = dark

	-- Progress bar for main hand (outside left edge)
	local barWidth = 3
	local mainBar = btn:CreateTexture(nil, "OVERLAY")
	mainBar:SetPoint("TOPRIGHT", btn, "TOPLEFT", -1, 0)  -- Outside left edge
	mainBar:SetSize(barWidth, buttonSize)
	mainBar:SetColorTexture(0.2, 0.8, 0.2, 0.9)  -- Green
	mainBar:Hide()
	btn.mainHandBar = mainBar

	-- Progress bar for off hand (outside right edge)
	local offBar = btn:CreateTexture(nil, "OVERLAY")
	offBar:SetPoint("TOPLEFT", btn, "TOPRIGHT", 1, 0)  -- Outside right edge
	offBar:SetSize(barWidth, buttonSize)
	offBar:SetColorTexture(0.2, 0.8, 0.2, 0.9)  -- Green
	offBar:Hide()
	btn.offHandBar = offBar

	-- Grey sweep overlay for single weapon (shows depleted portion from bottom)
	local greyOverlay = btn:CreateTexture(nil, "ARTWORK", nil, 1)  -- Sublevel 1 to be above icon
	greyOverlay:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
	greyOverlay:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
	greyOverlay:SetHeight(0)
	greyOverlay:SetTexture(self.WeaponIcons[1])
	greyOverlay:SetDesaturated(true)
	greyOverlay:SetVertexColor(0.5, 0.5, 0.5)  -- Darken it a bit
	greyOverlay:Hide()
	btn.greyOverlay = greyOverlay

	-- Grey sweep overlay for main hand (left half) in split display
	local greyOverlay1 = btn:CreateTexture(nil, "ARTWORK", nil, 1)
	greyOverlay1:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
	greyOverlay1:SetSize(buttonSize / 2, 0)
	greyOverlay1:SetTexture(self.WeaponIcons[1])
	greyOverlay1:SetDesaturated(true)
	greyOverlay1:SetVertexColor(0.5, 0.5, 0.5)
	greyOverlay1:Hide()
	btn.greyOverlay1 = greyOverlay1

	-- Grey sweep overlay for off hand (right half) in split display
	local greyOverlay2 = btn:CreateTexture(nil, "ARTWORK", nil, 1)
	greyOverlay2:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
	greyOverlay2:SetSize(buttonSize / 2, 0)
	greyOverlay2:SetTexture(self.WeaponIcons[2])
	greyOverlay2:SetDesaturated(true)
	greyOverlay2:SetVertexColor(0.5, 0.5, 0.5)
	greyOverlay2:Hide()
	btn.greyOverlay2 = greyOverlay2

	-- Time text for showing remaining duration
	local timeText = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	timeText:SetPoint("CENTER", btn, "CENTER", 0, 0)
	timeText:SetText("")
	btn.timeText = timeText

	-- Keybind text (top right corner, like standard action buttons)
	local keybindText = btn:CreateFontString(nil, "OVERLAY")
	keybindText:SetFont("Fonts\\ARIALN.TTF", 9, "OUTLINE")
	keybindText:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 1, 0)
	keybindText:SetTextColor(0.9, 0.9, 0.9, 1)
	keybindText:SetText("")
	keybindText:Hide()  -- Hidden by default, shown if option enabled
	btn.keybindText = keybindText
	btn.cooldownType = 7  -- Imbue type for keybind lookup

	-- SECURE HANDLER: Show flyout on enter (WORKS IN COMBAT)
	btn:SetAttribute("OpenMenu", "mouseover")
	btn:SetAttribute("_onenter", [[
		if self:GetAttribute("OpenMenu") == "mouseover" then
			self:ChildUpdate("show", true)
		end
	]])

	-- SECURE HANDLER: Hide flyout on leave (WORKS IN COMBAT)
	btn:SetAttribute("_onleave", [[
		if not self:IsUnderMouse(true) then
			self:ChildUpdate("show", false)
		end
	]])

	-- Tooltip (Lua hooks work alongside secure handlers)
	btn:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Weapon Imbues")

		-- Show current enchant status
		local hasMain, mainExp, _, mainID, hasOff, offExp, _, offID = GetWeaponEnchantInfo()
		if hasMain then
			local imbueType = ShamanPower.EnchantIDToImbue[mainID]
			local imbueName = imbueType and ShamanPower.WeaponEnchantNames[imbueType] or "Unknown"
			GameTooltip:AddLine("Main Hand: " .. imbueName .. " (" .. math.floor(mainExp/60000) .. "m)", 0, 1, 0)
		else
			GameTooltip:AddLine("Main Hand: None", 1, 0.5, 0.5)
		end

		if ShamanPower:CanDualWield() then
			if hasOff then
				local imbueType = ShamanPower.EnchantIDToImbue[offID]
				local imbueName = imbueType and ShamanPower.WeaponEnchantNames[imbueType] or "Unknown"
				GameTooltip:AddLine("Off Hand: " .. imbueName .. " (" .. math.floor(offExp/60000) .. "m)", 0, 1, 0)
			else
				GameTooltip:AddLine("Off Hand: None", 1, 0.5, 0.5)
			end
		end

		GameTooltip:Show()
	end)

	btn:HookScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	-- Set default spell for quick cast (last used imbue or first known)
	local defaultImbue = self:GetHighestRankImbue(1) or self:GetHighestRankImbue(2) or
	                     self:GetHighestRankImbue(3) or self:GetHighestRankImbue(4)
	if defaultImbue then
		btn:SetAttribute("type1", "spell")
		btn:SetAttribute("spell1", defaultImbue)
		btn:SetAttribute("type2", "spell")
		btn:SetAttribute("spell2", defaultImbue)
	end

	self.weaponImbueButton = btn

	-- Add to cooldown buttons array for positioning
	table.insert(self.cooldownButtons, btn)
	btn.spellType = "weaponImbue"
	btn.cooldownType = 7  -- Imbue is type 7 for ordering

	-- Create the flyout
	self:CreateWeaponImbueFlyout()
end

-- ============================================================================
-- Shield Flyout (for selecting between Lightning Shield and Water Shield)
-- ============================================================================

-- Create the flyout menu for shields (combat-functional architecture)
-- Flyout buttons are parented directly to shieldButton for ChildUpdate to work
function ShamanPower:CreateShieldFlyout()
	if self.shieldFlyout then return end
	if InCombatLockdown() then return end
	if not self.shieldButton then return end

	local parentButton = self.shieldButton
	local buttonSize = 22
	local spacing = 0  -- No gap between buttons for smooth mouse movement

	local flyout = {
		buttons = {},
		buttonSize = buttonSize,
		spacing = spacing,
		shieldButton = parentButton
	}

	-- Create buttons for each known shield as children of the shield button
	for i, shieldData in ipairs(self.ShieldSpells) do
		local spellID, spellName = shieldData[1], shieldData[2]

		-- Check if player knows this shield
		if PlayerKnowsSpellByName(spellName) then
			local name, _, icon = GetSpellInfo(spellName)

			-- Create as CHILD of shield button for ChildUpdate to work
			local btn = CreateFrame("Button", "ShamanPowerShieldFlyout" .. i, parentButton,
				"SecureActionButtonTemplate, SecureHandlerEnterLeaveTemplate, SecureHandlerShowHideTemplate")
			btn:SetSize(buttonSize, buttonSize)
			btn:SetFrameStrata("DIALOG")
			btn:RegisterForClicks("LeftButtonUp", "LeftButtonDown")
			btn:Hide()
			btn:SetIgnoreParentAlpha(true)  -- Independent opacity from parent button

			local iconTex = btn:CreateTexture(nil, "ARTWORK")
			iconTex:SetAllPoints()
			iconTex:SetTexture(icon)
			iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			btn.icon = iconTex

			-- Highlight texture
			local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
			highlight:SetAllPoints()
			highlight:SetColorTexture(1, 1, 1, 0.3)

			-- SECURE HANDLER: Respond to parent's ChildUpdate (WORKS IN COMBAT)
			btn:SetAttribute("_childupdate-show", [[
				if message then
					self:Show()
				else
					self:Hide()
				end
			]])

			-- SECURE HANDLER: Check parent on leave (WORKS IN COMBAT)
			btn:SetAttribute("_onleave", [[
				if not self:GetParent():IsUnderMouse(true) then
					self:GetParent():ChildUpdate("show", false)
				end
			]])

			-- Click to cast shield
			btn:SetAttribute("type1", "spell")
			btn:SetAttribute("spell", spellName)

			-- Update the main shield button's spell when clicked (out of combat only)
			btn:HookScript("PostClick", function(self, button)
				-- Hide flyout buttons only if NOT in combat (in combat, secure handler handles it)
				if not InCombatLockdown() then
					local flyoutData = ShamanPower.shieldFlyout
					if flyoutData and flyoutData.buttons then
						for _, flyoutBtn in ipairs(flyoutData.buttons) do
							flyoutBtn:Hide()
						end
					end

					-- Update default shield assignment
					local shieldBtn = ShamanPower.shieldButton
					if shieldBtn then
						shieldBtn:SetAttribute("spell1", spellName)
						shieldBtn.defaultShieldSpell = spellName
						-- Update the icon
						local _, _, newIcon = GetSpellInfo(spellName)
						if newIcon and shieldBtn.icon then
							shieldBtn.icon:SetTexture(newIcon)
						end
					end
				end
				-- In combat: flyout will close when mouse leaves (via secure _onleave handler)
			end)

			-- Tooltip (Lua hooks work alongside secure handlers)
			btn:HookScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:SetSpellByID(spellID)
				GameTooltip:Show()
			end)
			btn:HookScript("OnLeave", function()
				GameTooltip:Hide()
			end)

			btn.spellID = spellID
			btn.spellName = spellName
			table.insert(flyout.buttons, btn)
		end
	end

	self.shieldFlyout = flyout

	-- Layout the flyout buttons
	self:LayoutShieldFlyout()
end

-- Layout shield flyout buttons (called after creation and when layout changes)
-- Buttons are children of shieldButton, positioned relative to parent
function ShamanPower:LayoutShieldFlyout()
	local flyout = self.shieldFlyout
	if not flyout then return end

	local buttons = flyout.buttons
	if not buttons or #buttons == 0 then return end

	local shieldButton = flyout.shieldButton
	if not shieldButton then return end

	local buttonSize = flyout.buttonSize
	local spacing = flyout.spacing

	-- Determine flyout direction based on CD bar layout
	local cdLayout = self.opt.cdbarLayout or self.opt.layout
	local isHorizontalBar = (cdLayout == "Horizontal")
	local isVerticalLeft = (cdLayout == "VerticalLeft")
	local isLocked = (self.opt.cooldownBarLocked ~= false)

	-- For horizontal bar: flyout goes vertical
	-- For vertical bar: flyout goes horizontal
	local flyoutIsHorizontal = not isHorizontalBar

	if flyoutIsHorizontal then
		-- When locked to totem bar, go OPPOSITE direction to avoid clipping
		-- When unlocked, go same direction as layout
		local goRight
		if isLocked then
			-- Locked: opposite direction
			goRight = isVerticalLeft  -- VerticalLeft -> go right, VerticalRight -> go left
		else
			-- Unlocked: same direction as layout
			goRight = not isVerticalLeft  -- VerticalLeft -> go left, VerticalRight -> go right
		end

		if goRight then
			-- Extend to the RIGHT
			for i, btn in ipairs(buttons) do
				btn:ClearAllPoints()
				btn:SetPoint("LEFT", shieldButton, "RIGHT", spacing + (i - 1) * (buttonSize + spacing), 0)
			end
		else
			-- Extend to the LEFT
			for i, btn in ipairs(buttons) do
				btn:ClearAllPoints()
				btn:SetPoint("RIGHT", shieldButton, "LEFT", -spacing - (i - 1) * (buttonSize + spacing), 0)
			end
		end
	else
		-- Vertical flyout: buttons extend upward or downward based on option
		local flyoutDir = self.opt.cdbarFlyoutDirection or "auto"

		-- When "auto" and locked to totem bar, go below (to avoid clipping into totem icons)
		-- When "auto" and unlocked, go above
		local goBelow = (flyoutDir == "below") or (flyoutDir == "auto" and isLocked)

		if goBelow then
			-- Extend downward
			for i, btn in ipairs(buttons) do
				btn:ClearAllPoints()
				btn:SetPoint("TOP", shieldButton, "BOTTOM", 0, -spacing - (i - 1) * (buttonSize + spacing))
			end
		else
			-- Extend upward
			for i, btn in ipairs(buttons) do
				btn:ClearAllPoints()
				btn:SetPoint("BOTTOM", shieldButton, "TOP", 0, spacing + (i - 1) * (buttonSize + spacing))
			end
		end
	end
end

-- Show shield flyout (for backward compatibility, mostly handled by secure handlers now)
function ShamanPower:ShowShieldFlyout()
	if not self.shieldFlyout then
		self:CreateShieldFlyout()
	end
	-- Layout is handled in CreateShieldFlyout and LayoutShieldFlyout
	-- Show/hide is handled by secure handlers (_onenter/_onleave/_childupdate-show)
end

-- Create the flyout menu for weapon imbues (combat-functional architecture)
-- Flyout buttons are parented directly to weaponImbueButton for ChildUpdate to work
function ShamanPower:CreateWeaponImbueFlyout()
	if self.weaponImbueFlyout then return end
	if InCombatLockdown() then return end
	if not self.weaponImbueButton then return end

	local parentButton = self.weaponImbueButton
	local buttonSize = 22
	local spacing = 0  -- No gap between buttons for smooth mouse movement

	local flyout = {
		buttons = {},
		buttonSize = buttonSize,
		spacing = spacing,
		imbueButton = parentButton
	}

	-- Create buttons for each known imbue as children of the imbue button
	for imbueIndex = 1, 4 do
		local spellName = self:GetHighestRankImbue(imbueIndex)
		if spellName then
			-- Create as CHILD of imbue button for ChildUpdate to work
			local btn = CreateFrame("Button", "ShamanPowerImbueFlyout" .. imbueIndex, parentButton,
				"SecureActionButtonTemplate, SecureHandlerEnterLeaveTemplate, SecureHandlerShowHideTemplate")
			btn:SetSize(buttonSize, buttonSize)
			btn:SetFrameStrata("DIALOG")
			btn:RegisterForClicks("LeftButtonUp", "LeftButtonDown", "RightButtonUp", "RightButtonDown")
			btn:Hide()
			btn:SetIgnoreParentAlpha(true)  -- Independent opacity from parent button

			-- SECURE HANDLER: Respond to parent's ChildUpdate (WORKS IN COMBAT)
			btn:SetAttribute("_childupdate-show", [[
				if message then
					self:Show()
				else
					self:Hide()
				end
			]])

			-- SECURE HANDLER: Check parent on leave (WORKS IN COMBAT)
			btn:SetAttribute("_onleave", [[
				if not self:GetParent():IsUnderMouse(true) then
					self:GetParent():ChildUpdate("show", false)
				end
			]])

			-- Click to cast imbue spell
			btn:SetAttribute("type1", "spell")
			btn:SetAttribute("spell", spellName)

			-- Icon
			local iconTex = btn:CreateTexture(nil, "ARTWORK")
			iconTex:SetAllPoints()
			iconTex:SetTexture(self.WeaponIcons[imbueIndex])
			iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			btn.icon = iconTex

			-- Highlight
			local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
			highlight:SetAllPoints()
			highlight:SetColorTexture(1, 1, 1, 0.3)

			-- Hide flyout after click
			btn:HookScript("PostClick", function(self, button)
				-- Hide flyout buttons only if NOT in combat (in combat, secure handler handles it)
				if not InCombatLockdown() then
					local flyoutData = ShamanPower.weaponImbueFlyout
					if flyoutData and flyoutData.buttons then
						for _, flyoutBtn in ipairs(flyoutData.buttons) do
							flyoutBtn:Hide()
						end
					end
				end
				-- In combat: flyout will close when mouse leaves (via secure _onleave handler)

				-- Remember last used imbue
				if button == "LeftButton" then
					ShamanPower.lastMainHandImbue = imbueIndex
				else
					ShamanPower.lastOffHandImbue = imbueIndex
				end
			end)

			-- Tooltip (Lua hooks work alongside secure handlers)
			btn:HookScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:SetSpellByID(ShamanPower.WeaponImbueSpells[imbueIndex])
				GameTooltip:Show()
			end)
			btn:HookScript("OnLeave", function()
				GameTooltip:Hide()
			end)

			btn.imbueIndex = imbueIndex
			btn.spellName = spellName
			table.insert(flyout.buttons, btn)
		end
	end

	self.weaponImbueFlyout = flyout

	-- Layout the flyout buttons
	self:LayoutWeaponImbueFlyout()
end

-- Layout weapon imbue flyout buttons (called after creation and when layout changes)
-- Buttons are children of weaponImbueButton, positioned relative to parent
function ShamanPower:LayoutWeaponImbueFlyout()
	local flyout = self.weaponImbueFlyout
	if not flyout then return end

	local buttons = flyout.buttons
	if not buttons or #buttons == 0 then return end

	local imbueButton = flyout.imbueButton
	if not imbueButton then return end

	local buttonSize = flyout.buttonSize
	local spacing = flyout.spacing

	-- Determine flyout direction based on CD bar layout
	local cdLayout = self.opt.cdbarLayout or self.opt.layout
	local isHorizontalBar = (cdLayout == "Horizontal")
	local isVerticalLeft = (cdLayout == "VerticalLeft")
	local isLocked = (self.opt.cooldownBarLocked ~= false)

	-- For horizontal bar: flyout goes vertical
	-- For vertical bar: flyout goes horizontal
	local flyoutIsHorizontal = not isHorizontalBar

	if flyoutIsHorizontal then
		-- When locked to totem bar, go OPPOSITE direction to avoid clipping
		-- When unlocked, go same direction as layout
		local goRight
		if isLocked then
			-- Locked: opposite direction
			goRight = isVerticalLeft  -- VerticalLeft -> go right, VerticalRight -> go left
		else
			-- Unlocked: same direction as layout
			goRight = not isVerticalLeft  -- VerticalLeft -> go left, VerticalRight -> go right
		end

		if goRight then
			-- Extend to the RIGHT
			for i, btn in ipairs(buttons) do
				btn:ClearAllPoints()
				btn:SetPoint("LEFT", imbueButton, "RIGHT", spacing + (i - 1) * (buttonSize + spacing), 0)
			end
		else
			-- Extend to the LEFT
			for i, btn in ipairs(buttons) do
				btn:ClearAllPoints()
				btn:SetPoint("RIGHT", imbueButton, "LEFT", -spacing - (i - 1) * (buttonSize + spacing), 0)
			end
		end
	else
		-- Vertical flyout: buttons extend upward or downward based on option
		local flyoutDir = self.opt.cdbarFlyoutDirection or "auto"

		-- When "auto" and locked to totem bar, go below (to avoid clipping into totem icons)
		-- When "auto" and unlocked, go above
		local goBelow = (flyoutDir == "below") or (flyoutDir == "auto" and isLocked)

		if goBelow then
			-- Extend downward
			for i, btn in ipairs(buttons) do
				btn:ClearAllPoints()
				btn:SetPoint("TOP", imbueButton, "BOTTOM", 0, -spacing - (i - 1) * (buttonSize + spacing))
			end
		else
			-- Extend upward
			for i, btn in ipairs(buttons) do
				btn:ClearAllPoints()
				btn:SetPoint("BOTTOM", imbueButton, "TOP", 0, spacing + (i - 1) * (buttonSize + spacing))
			end
		end
	end
end

-- Show weapon imbue flyout (for backward compatibility, mostly handled by secure handlers now)
function ShamanPower:ShowWeaponImbueFlyout()
	if not self.weaponImbueFlyout then
		self:CreateWeaponImbueFlyout()
	end
	-- Layout is handled in CreateWeaponImbueFlyout and LayoutWeaponImbueFlyout
	-- Show/hide is handled by secure handlers (_onenter/_onleave/_childupdate-show)
end

-- Update the weapon imbue button appearance based on current enchants
function ShamanPower:UpdateWeaponImbueButton()
	local btn = self.weaponImbueButton
	if not btn then return end

	local hasMain, mainExp, _, mainID, hasOff, offExp, _, offID = GetWeaponEnchantInfo()
	local maxDuration = 1800000  -- 30 minutes in milliseconds
	local buttonHeight = btn:GetHeight()

	-- Get display options
	local showBars = self.opt.cdbarShowProgressBars ~= false
	local showSweep = self.opt.cdbarShowColorSweep ~= false
	local showText = self.opt.cdbarShowCDText ~= false

	if hasMain then
		local imbueType = self.EnchantIDToImbue[mainID] or 1
		btn.icon:SetTexture(self.WeaponIcons[imbueType])
		btn.icon:SetDesaturated(false)
		btn.darkOverlay:Hide()

		local mainPercent = math.min(mainExp / maxDuration, 1)

		-- Update main hand progress bar (outside left edge)
		if showBars then
			local mainBarHeight = math.max(buttonHeight * mainPercent, 1)
			btn.mainHandBar:SetHeight(mainBarHeight)
			btn.mainHandBar:ClearAllPoints()
			btn.mainHandBar:SetPoint("BOTTOMRIGHT", btn, "BOTTOMLEFT", -1, 0)
			local r, g, b = GetTimerBarColor(mainExp)
			btn.mainHandBar:SetColorTexture(r, g, b, 0.9)
			btn.mainHandBar:Show()
		else
			btn.mainHandBar:Hide()
		end

		-- Update time text (show main hand time)
		if showText then
			local mins = math.floor(mainExp / 60000)
			btn.timeText:SetText(MinuteStrings[mins] or (mins .. "m"))
			btn.timeText:Show()
		else
			btn.timeText:SetText("")
			btn.timeText:Hide()
		end

		-- If dual wielding, show split display (left half = main hand, right half = off hand)
		if self:CanDualWield() and hasOff then
			local offImbueType = self.EnchantIDToImbue[offID] or 2
			local offPercent = math.min(offExp / maxDuration, 1)

			-- Main hand icon - left half of button (full height), showing left half of texture
			btn.icon:ClearAllPoints()
			btn.icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
			btn.icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOM", 0, 0)
			btn.icon:SetTexCoord(0.08, 0.5, 0.08, 0.92)

			-- Off hand icon - right half of button (full height), showing right half of texture
			btn.icon2:ClearAllPoints()
			btn.icon2:SetPoint("TOPLEFT", btn, "TOP", 0, 0)
			btn.icon2:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
			btn.icon2:SetTexture(self.WeaponIcons[offImbueType])
			btn.icon2:SetTexCoord(0.5, 0.92, 0.08, 0.92)
			btn.icon2:Show()

			-- Update off hand progress bar (outside right edge)
			if showBars then
				local offBarHeight = math.max(buttonHeight * offPercent, 1)
				btn.offHandBar:SetHeight(offBarHeight)
				btn.offHandBar:ClearAllPoints()
				btn.offHandBar:SetPoint("BOTTOMLEFT", btn, "BOTTOMRIGHT", 1, 0)
				local r2, g2, b2 = GetTimerBarColor(offExp)
				btn.offHandBar:SetColorTexture(r2, g2, b2, 0.9)
				btn.offHandBar:Show()
			else
				btn.offHandBar:Hide()
			end

			-- Grey sweep overlays for split display (depleted portion from top)
			if showSweep then
				local mainDepletedPercent = 1 - mainPercent
				local mainGreyHeight = buttonHeight * mainDepletedPercent
				if mainGreyHeight > 1 then
					btn.greyOverlay1:SetTexture(self.WeaponIcons[imbueType])
					btn.greyOverlay1:ClearAllPoints()
					btn.greyOverlay1:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
					btn.greyOverlay1:SetSize(buttonHeight / 2, mainGreyHeight)
					local texBottom = 0.08 + (mainDepletedPercent * 0.84)
					btn.greyOverlay1:SetTexCoord(0.08, 0.5, 0.08, texBottom)
					btn.greyOverlay1:Show()
				else
					btn.greyOverlay1:Hide()
				end

				local offDepletedPercent = 1 - offPercent
				local offGreyHeight = buttonHeight * offDepletedPercent
				if offGreyHeight > 1 then
					btn.greyOverlay2:SetTexture(self.WeaponIcons[offImbueType])
					btn.greyOverlay2:ClearAllPoints()
					btn.greyOverlay2:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, 0)
					btn.greyOverlay2:SetSize(buttonHeight / 2, offGreyHeight)
					local texBottom = 0.08 + (offDepletedPercent * 0.84)
					btn.greyOverlay2:SetTexCoord(0.5, 0.92, 0.08, texBottom)
					btn.greyOverlay2:Show()
				else
					btn.greyOverlay2:Hide()
				end
			else
				btn.greyOverlay1:Hide()
				btn.greyOverlay2:Hide()
			end

			btn.greyOverlay:Hide()
		else
			-- Single weapon display
			btn.icon:ClearAllPoints()
			btn.icon:SetAllPoints()
			btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			btn.icon2:Hide()
			btn.offHandBar:Hide()

			-- Grey sweep overlay for single display (depleted portion from top)
			if showSweep then
				local depletedPercent = 1 - mainPercent
				local greyHeight = buttonHeight * depletedPercent
				if greyHeight > 1 then
					btn.greyOverlay:SetTexture(self.WeaponIcons[imbueType])
					btn.greyOverlay:ClearAllPoints()
					btn.greyOverlay:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
					btn.greyOverlay:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, 0)
					btn.greyOverlay:SetHeight(greyHeight)
					local texBottom = 0.08 + (depletedPercent * 0.84)
					btn.greyOverlay:SetTexCoord(0.08, 0.92, 0.08, texBottom)
					btn.greyOverlay:Show()
				else
					btn.greyOverlay:Hide()
				end
			else
				btn.greyOverlay:Hide()
			end

			btn.greyOverlay1:Hide()
			btn.greyOverlay2:Hide()
		end
	else
		-- No enchant - show default icon desaturated
		btn.icon:ClearAllPoints()
		btn.icon:SetAllPoints()
		btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		btn.icon:SetDesaturated(true)
		btn.icon2:Hide()
		btn.mainHandBar:Hide()
		btn.offHandBar:Hide()
		btn.darkOverlay:Show()
		btn.greyOverlay:Hide()
		btn.greyOverlay1:Hide()
		btn.greyOverlay2:Hide()
		btn.timeText:SetText("")
	end
end

-- ============================================================================
-- Mini Totem Bar (built-in totem buttons when TotemTimers is not used)
-- ============================================================================

-- Check if any totems are currently placed
function ShamanPower:HasAnyTotemsPlaced()
	for element = 1, 4 do
		local slot = self.ElementToSlot[element]
		if slot then
			local haveTotem = GetTotemInfo(slot)
			if haveTotem then
				return true
			end
		end
	end
	return false
end

-- Update totem bar visibility based on combat and totem state
function ShamanPower:UpdateTotemBarVisibility()
	-- Enable/disable totemVisibility subsystem based on whether auto-hide features are on
	if self.opt.hideOutOfCombat or self.opt.hideWhenNoTotems then
		self:EnableUpdateSubsystem("totemVisibility")
	else
		self:DisableUpdateSubsystem("totemVisibility")
	end

	if not self.autoButton then return end

	local shouldHide = false

	-- Check hide out of combat option
	if self.opt.hideOutOfCombat then
		local inCombat = InCombatLockdown() or UnitAffectingCombat("player")
		if not inCombat then
			shouldHide = true
		end
	end

	-- Check hide when no totems option (only hide if not already hidden by combat check)
	if not shouldHide and self.opt.hideWhenNoTotems then
		if not self:HasAnyTotemsPlaced() then
			shouldHide = true
		end
	end

	-- Skip update if state hasn't changed (prevents blinking)
	if self.totemBarHidden == shouldHide then return end
	self.totemBarHidden = shouldHide

	-- Apply visibility (can't change in combat lockdown for secure frames)
	if not InCombatLockdown() then
		if shouldHide then
			-- Hide everything
			self.autoButton:Hide()

			if self.totemButtons then
				for element = 1, 4 do
					local btn = self.totemButtons[element]
					if btn then btn:Hide() end
				end
			end

			-- Hide Drop All button
			local dropAllBtn = _G["ShamanPowerAutoDropAll"]
			if dropAllBtn then dropAllBtn:Hide() end

			-- Hide Earth Shield button
			local esBtn = _G["ShamanPowerEarthShieldBtn"]
			if esBtn then esBtn:Hide() end
		else
			-- Show everything with proper opacity
			local alpha = self.opt.totemBarOpacity or 1.0

			self.autoButton:Show()
			self.autoButton:SetAlpha(alpha)

			if self.totemButtons then
				for element = 1, 4 do
					local btn = self.totemButtons[element]
					if btn then
						btn:Show()
						btn:SetAlpha(alpha)
					end
				end
			end

			-- Show Drop All button (if enabled)
			local dropAllBtn = _G["ShamanPowerAutoDropAll"]
			if dropAllBtn and self.opt.showDropAllButton ~= false then
				dropAllBtn:Show()
				dropAllBtn:SetAlpha(alpha)
			end

			-- Show Earth Shield button (if it should be visible)
			local esBtn = _G["ShamanPowerEarthShieldBtn"]
			if esBtn and self:HasEarthShield() then
				esBtn:Show()
				esBtn:SetAlpha(alpha)
			end
		end
	end
end

-- Set up visibility update timer
function ShamanPower:SetupTotemBarVisibilityUpdater()
	-- Register visibility updates with consolidated update system (5fps)
	if not self.updateSystem.subsystems["totemVisibility"] then
		self:RegisterUpdateSubsystem("totemVisibility", 0.2, function()
			ShamanPower:UpdateTotemBarVisibility()
		end)
	end
	-- Only enable if auto-hide features are on
	if self.opt.hideOutOfCombat or self.opt.hideWhenNoTotems then
		self:EnableUpdateSubsystem("totemVisibility")
	else
		self:DisableUpdateSubsystem("totemVisibility")
	end
end

-- Update the mini totem bar icons and spells based on current assignments
function ShamanPower:UpdateMiniTotemBar()
	if not self.autoButton then return end
	if InCombatLockdown() then return end

	-- Don't show buttons if totem bar should be hidden
	if self.totemBarHidden then return end

	local playerName = self.player
	local assignments = ShamanPower_Assignments[playerName]
	if not assignments then return end

	-- Determine layout orientation
	local isHorizontal = (self.opt.layout == "Horizontal")
	local buttonSize = 26
	local spacing = self.opt.totemBarPadding or 2
	local padding = 4
	local separatorSize = 12  -- Extra gap for separator
	local showDropAll = self.opt.showDropAllButton ~= false  -- Default to true if not set
	local dropAllPoppedOut = self:IsDropAllPoppedOut()
	-- Show Totemic Call on totem bar if option is enabled (spell knowledge is validated by CD bar settings)
	local showTotemicCall = self.opt.totemicCallOnTotemBar and self.opt.cdbarShowRecall ~= false

	-- Check which totem buttons should be visible (not hidden in options and not popped out)
	local elementVisible = {
		[1] = self.opt.totemBarShowEarth ~= false and not self:IsElementPoppedOut(1),  -- Earth
		[2] = self.opt.totemBarShowFire ~= false and not self:IsElementPoppedOut(2),   -- Fire
		[3] = self.opt.totemBarShowWater ~= false and not self:IsElementPoppedOut(3),  -- Water
		[4] = self.opt.totemBarShowAir ~= false and not self:IsElementPoppedOut(4),    -- Air
	}

	-- Count visible buttons
	local visibleCount = 0
	for i = 1, 4 do
		if elementVisible[i] then
			visibleCount = visibleCount + 1
		end
	end

	-- Resize the parent frame based on layout and visible button count
	-- Don't include Drop All in size calculations if it's popped out
	local includeDropAll = showDropAll and not dropAllPoppedOut
	-- Count extra buttons (Drop All and/or Totemic Call)
	local extraButtonCount = 0
	if includeDropAll then extraButtonCount = extraButtonCount + 1 end
	if showTotemicCall then extraButtonCount = extraButtonCount + 1 end

	if isHorizontal then
		-- Horizontal: wide and short
		local totalWidth = (buttonSize * visibleCount) + (spacing * math.max(0, visibleCount - 1)) + (padding * 2)
		if extraButtonCount > 0 and visibleCount > 0 then
			totalWidth = totalWidth + separatorSize + (buttonSize * extraButtonCount) + (spacing * math.max(0, extraButtonCount - 1))
		elseif extraButtonCount > 0 then
			totalWidth = (buttonSize * extraButtonCount) + (spacing * math.max(0, extraButtonCount - 1)) + (padding * 2)
		end
		self.autoButton:SetSize(math.max(totalWidth, buttonSize + (padding * 2)), buttonSize + (padding * 2))
	else
		-- Vertical: narrow and tall
		local totalHeight = (buttonSize * visibleCount) + (spacing * math.max(0, visibleCount - 1)) + (padding * 2)
		if extraButtonCount > 0 and visibleCount > 0 then
			totalHeight = totalHeight + separatorSize + (buttonSize * extraButtonCount) + (spacing * math.max(0, extraButtonCount - 1))
		elseif extraButtonCount > 0 then
			totalHeight = (buttonSize * extraButtonCount) + (spacing * math.max(0, extraButtonCount - 1)) + (padding * 2)
		end
		self.autoButton:SetSize(buttonSize + (padding * 2), math.max(totalHeight, buttonSize + (padding * 2)))
	end

	-- Get the order to display totem buttons
	local totemOrder = self.opt.totemBarOrder or {1, 2, 3, 4}

	local visiblePosition = 0  -- Track position of visible buttons
	for position = 1, 4 do
		local element = totemOrder[position]
		local totemButton = _G["ShamanPowerAutoTotem" .. element]
		if totemButton then
			-- Check if this element should be visible
			if not elementVisible[element] then
				totemButton:Hide()
			else
				visiblePosition = visiblePosition + 1
				totemButton:Show()

				-- Dynamic Mode: use currently active totem instead of assignment
				local totemIndex
				if self.opt.dynamicTotemMode then
					-- First try to get the active totem
					local activeIndex = self:GetActiveTotemIndex(element)
					if activeIndex then
						totemIndex = activeIndex
					else
						-- No active totem - fall back to assignment
						totemIndex = assignments[element] or 0
					end
				else
					-- Normal mode: use assignment
					totemIndex = assignments[element] or 0
				end

				local spellID = nil
				local spellName = nil
				local icon = self.ElementIcons[element]  -- Default to element icon

				if totemIndex and totemIndex > 0 then
					spellID = self:GetTotemSpell(element, totemIndex)
					icon = self:GetTotemIcon(element, totemIndex)
					-- TBC needs spell names, not IDs
					if spellID then
						spellName = GetSpellInfo(spellID)
					end
				end

				-- Update the icon
				local iconTexture = _G["ShamanPowerAutoTotem" .. element .. "Icon"]
				if iconTexture then
					iconTexture:SetTexture(icon)
				end

				-- Reposition buttons based on layout (use visiblePosition for layout, element for data)
				totemButton:ClearAllPoints()
				if isHorizontal then
					-- Horizontal: buttons go left to right
					totemButton:SetPoint("TOPLEFT", self.autoButton, "TOPLEFT", padding + (visiblePosition - 1) * (buttonSize + spacing), -padding)
				else
					-- Vertical: buttons go top to bottom
					totemButton:SetPoint("TOPLEFT", self.autoButton, "TOPLEFT", padding, -padding - (visiblePosition - 1) * (buttonSize + spacing))
				end

				-- Set up the button: left-click casts totem, right-click casts Totemic Call
				totemButton:RegisterForClicks("AnyUp", "AnyDown")

				-- Clear old attributes first
				totemButton:SetAttribute("type", nil)
				totemButton:SetAttribute("type1", nil)
				totemButton:SetAttribute("spell", nil)
				totemButton:SetAttribute("spell1", nil)
				totemButton:SetAttribute("macrotext1", nil)

				-- Left-click: cast totem (or castsequence for Air totem twisting)
				if element == 4 and self.opt.enableTotemTwisting then
					-- Air totem with twisting: use castsequence macro
					local wfName = GetSpellInfo(25587) or "Windfury Totem"
					local goaName = GetSpellInfo(25359) or "Grace of Air Totem"
					totemButton:SetAttribute("type1", "macro")
					totemButton:SetAttribute("macrotext1", "/castsequence reset=10 " .. wfName .. ", " .. goaName)
					-- Update icon to Windfury
					local twistIcon = _G["ShamanPowerAutoTotem" .. element .. "Icon"]
					if twistIcon then
						twistIcon:SetTexture("Interface\\Icons\\Spell_Nature_Windfury")
					end
				elseif spellName then
					totemButton:SetAttribute("type1", "spell")
					totemButton:SetAttribute("spell1", spellName)
				end

				-- Right-click behavior: Totemic Call by default, or flyout trigger if option enabled
				if self.opt.showTotemFlyouts and self.opt.flyoutRequiresClick then
					-- Right-click shows flyout instead of Totemic Call
					totemButton:SetAttribute("type2", nil)
					totemButton:SetAttribute("spell2", nil)
				else
					-- Right-click to cast Totemic Call (destroys all totems)
					totemButton:SetAttribute("type2", "spell")
					totemButton:SetAttribute("spell2", GetSpellInfo(36936))  -- Totemic Call
				end
			end  -- end of else (visible)
		end  -- end of if totemButton
	end  -- end of for loop

	-- Create or update separator line
	local separator = _G["ShamanPowerAutoSeparator"]
	if not separator then
		separator = self.autoButton:CreateTexture("ShamanPowerAutoSeparator", "ARTWORK")
		separator:SetColorTexture(0.5, 0.5, 0.5, 0.8)  -- Gray line
	end

	-- Reposition the Drop All button and Totemic Call button (after the separator)
	local dropAllButton = _G["ShamanPowerAutoDropAll"]
	local totemicCallButton = _G["ShamanPowerAutoTotemicCall"]

	-- Set up Totemic Call button spell if needed (only needs to be done once)
	if totemicCallButton and showTotemicCall then
		self:SetupTotemicCallButton()
	end

	-- Calculate how many extra buttons will be shown (after separator)
	local showDropAllHere = showDropAll and not dropAllPoppedOut
	local extraButtonsShown = 0
	if showDropAllHere then extraButtonsShown = extraButtonsShown + 1 end
	if showTotemicCall then extraButtonsShown = extraButtonsShown + 1 end

	-- Position extra buttons (Drop All and Totemic Call)
	if extraButtonsShown > 0 and visibleCount > 0 then
		separator:ClearAllPoints()
		if isHorizontal then
			-- Vertical separator line
			separator:SetSize(2, buttonSize)
			local separatorX = padding + (buttonSize * visibleCount) + (spacing * math.max(0, visibleCount - 1)) + (separatorSize / 2) - 1
			separator:SetPoint("TOPLEFT", self.autoButton, "TOPLEFT", separatorX, -padding)
		else
			-- Horizontal separator line
			separator:SetSize(buttonSize, 2)
			local separatorY = -padding - (buttonSize * visibleCount) - (spacing * math.max(0, visibleCount - 1)) - (separatorSize / 2) + 1
			separator:SetPoint("TOPLEFT", self.autoButton, "TOPLEFT", padding, separatorY)
		end
		separator:Show()

		-- Base position after separator
		local extraPos = 0

		-- Position Drop All button first (if shown)
		if showDropAllHere and dropAllButton then
			dropAllButton:ClearAllPoints()
			if isHorizontal then
				local dropAllX = padding + (buttonSize * visibleCount) + (spacing * math.max(0, visibleCount - 1)) + separatorSize + (extraPos * (buttonSize + spacing))
				dropAllButton:SetPoint("TOPLEFT", self.autoButton, "TOPLEFT", dropAllX, -padding)
			else
				local dropAllY = -padding - (buttonSize * visibleCount) - (spacing * math.max(0, visibleCount - 1)) - separatorSize - (extraPos * (buttonSize + spacing))
				dropAllButton:SetPoint("TOPLEFT", self.autoButton, "TOPLEFT", padding, dropAllY)
			end
			dropAllButton:Show()
			extraPos = extraPos + 1
		elseif dropAllButton then
			dropAllButton:Hide()
		end

		-- Position Totemic Call button (if shown)
		if showTotemicCall and totemicCallButton then
			totemicCallButton:ClearAllPoints()
			if isHorizontal then
				local tcX = padding + (buttonSize * visibleCount) + (spacing * math.max(0, visibleCount - 1)) + separatorSize + (extraPos * (buttonSize + spacing))
				totemicCallButton:SetPoint("TOPLEFT", self.autoButton, "TOPLEFT", tcX, -padding)
			else
				local tcY = -padding - (buttonSize * visibleCount) - (spacing * math.max(0, visibleCount - 1)) - separatorSize - (extraPos * (buttonSize + spacing))
				totemicCallButton:SetPoint("TOPLEFT", self.autoButton, "TOPLEFT", padding, tcY)
			end
			totemicCallButton:Show()
		elseif totemicCallButton then
			totemicCallButton:Hide()
		end

	elseif extraButtonsShown > 0 and visibleCount == 0 then
		-- Show only extra buttons when all totems are hidden
		separator:Hide()
		local extraPos = 0

		if showDropAllHere and dropAllButton then
			dropAllButton:ClearAllPoints()
			if isHorizontal then
				dropAllButton:SetPoint("TOPLEFT", self.autoButton, "TOPLEFT", padding + (extraPos * (buttonSize + spacing)), -padding)
			else
				dropAllButton:SetPoint("TOPLEFT", self.autoButton, "TOPLEFT", padding, -padding - (extraPos * (buttonSize + spacing)))
			end
			dropAllButton:Show()
			extraPos = extraPos + 1
		elseif dropAllButton then
			dropAllButton:Hide()
		end

		if showTotemicCall and totemicCallButton then
			totemicCallButton:ClearAllPoints()
			if isHorizontal then
				totemicCallButton:SetPoint("TOPLEFT", self.autoButton, "TOPLEFT", padding + (extraPos * (buttonSize + spacing)), -padding)
			else
				totemicCallButton:SetPoint("TOPLEFT", self.autoButton, "TOPLEFT", padding, -padding - (extraPos * (buttonSize + spacing)))
			end
			totemicCallButton:Show()
		elseif totemicCallButton then
			totemicCallButton:Hide()
		end
	else
		-- Hide separator and extra buttons
		separator:Hide()
		if dropAllButton then
			dropAllButton:Hide()
		end
		if totemicCallButton then
			totemicCallButton:Hide()
		end
	end

	-- Update totem buttons (parented to UIParent for combat flyouts)
	self:UpdateTotemButtons()

	-- Update Earth Shield button (if shaman has ES and a target assigned)
	self:UpdateEarthShieldButton()

	-- Setup pulse overlays for totems like Tremor
	self:SetupPulseOverlays()

	-- Setup party range dots
	self:SetupPartyRangeDots()

	-- Setup range counters (shows number of players in range)
	self:SetupRangeCounters()

	-- Setup totem duration progress bars
	self:SetupTotemProgressBars()

	-- Setup totem flyout menus
	self:SetupTotemFlyouts()

	-- Setup cooldown tracker bar
	self:UpdateCooldownBar()

	-- Setup keybindings for the buttons
	self:SetupKeybindings()

	-- Setup twist timer visual if twisting is enabled
	if self.opt.enableTotemTwisting then
		self:SetupTwistTimer()
	else
		self:HideTwistTimer()
	end

	-- Setup GCD swipe overlays on totem buttons
	self:SetupGCDSwipes()

	-- Note: Macros are created manually via Options -> Buttons -> "Create/Update Macros" button
	-- or /spmacros command. No automatic macro updates to avoid interfering with macro UI.
end

-- ============================================================================
-- GCD Swipe (shows global cooldown animation on totem buttons)
-- ============================================================================

ShamanPower.gcdCooldowns = {}  -- Cooldown frames for each totem button

function ShamanPower:SetupGCDSwipes()
	for element = 1, 4 do
		local totemButton = self.totemButtons[element]
		if totemButton then
			local cdFrame = self.gcdCooldowns[element]
			if not cdFrame then
				cdFrame = CreateFrame("Cooldown", "ShamanPowerGCD" .. element, totemButton, "CooldownFrameTemplate")
				cdFrame:SetAllPoints(totemButton)
				cdFrame:SetDrawEdge(true)
				cdFrame:SetDrawSwipe(true)
				cdFrame:SetSwipeColor(0, 0, 0, 0.6)
				cdFrame:SetHideCountdownNumbers(true)
				self.gcdCooldowns[element] = cdFrame
			end
		end
	end

	-- Also add to Drop All button
	local dropAllButton = _G["ShamanPowerAutoDropAll"]
	if dropAllButton then
		local cdFrame = self.gcdCooldowns[5]
		if not cdFrame then
			cdFrame = CreateFrame("Cooldown", "ShamanPowerGCD5", dropAllButton, "CooldownFrameTemplate")
			cdFrame:SetAllPoints(dropAllButton)
			cdFrame:SetDrawEdge(true)
			cdFrame:SetDrawSwipe(true)
			cdFrame:SetSwipeColor(0, 0, 0, 0.6)
			cdFrame:SetHideCountdownNumbers(true)
			self.gcdCooldowns[5] = cdFrame
		end
	end
end

function ShamanPower:TriggerGCDSwipe()
	-- Get the current GCD from spell cooldown
	local start, duration = GetSpellCooldown(2484)  -- Earthbind Totem as reference
	if not start or start == 0 then
		-- Fallback: standard 1.5 second GCD
		start = GetTime()
		duration = 1.5
	end

	-- Only trigger if this is a fresh GCD (not a longer cooldown)
	if duration > 2 then return end

	for i = 1, 5 do
		local cdFrame = self.gcdCooldowns[i]
		if cdFrame then
			cdFrame:SetCooldown(start, duration)
		end
	end
end

-- Tooltip for mini totem bar buttons
function ShamanPower:TotemBarTooltip(button, element)
	if not self.opt.ShowTooltips then return end

	local playerName = self.player
	local assignments = ShamanPower_Assignments[playerName]
	local totemIndex = assignments and assignments[element] or 0

	local elementName = self.Elements[element] or "Unknown"
	local totemName = "None"
	local spellID = nil

	if totemIndex and totemIndex > 0 then
		totemName = self:GetTotemName(element, totemIndex)
		spellID = self:GetTotemSpell(element, totemIndex)
	end

	GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
	GameTooltip:AddLine(elementName .. " Totem", 1, 1, 1)
	if spellID then
		GameTooltip:AddLine(totemName, 0, 1, 0)
		GameTooltip:AddLine("|cff00ff00Left-click:|r Cast totem", 0.7, 0.7, 0.7)
		GameTooltip:AddLine("|cffffcc00Right-click:|r Totemic Call", 0.7, 0.7, 0.7)
	else
		GameTooltip:AddLine("No totem assigned", 1, 0, 0)
	end
	if self.opt.enableMiddleClickPopOut ~= false then
		GameTooltip:AddLine("|cff00ccffMiddle-click:|r Pop out", 1, 1, 1)
	end
	GameTooltip:Show()
end

-- ============================================================================
-- Earth Shield Macro Button (invisible, always available for /click)
-- ============================================================================

function ShamanPower:CreateEarthShieldMacroButton()
	if _G["ShamanPowerESMacroBtn"] then return end

	-- Create an invisible button that's always "shown" so /click works
	local macroBtn = CreateFrame("Button", "ShamanPowerESMacroBtn", UIParent, "SecureActionButtonTemplate")
	macroBtn:SetSize(1, 1)
	macroBtn:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -100, 100)  -- Off-screen
	macroBtn:SetAlpha(0)
	macroBtn:EnableMouse(false)  -- Don't intercept mouse clicks on screen
	macroBtn:RegisterForClicks("AnyUp", "AnyDown")
	macroBtn:Show()  -- Must be shown for /click to work
end

function ShamanPower:UpdateEarthShieldMacroButton()
	if InCombatLockdown() then return end

	-- Create if needed
	self:CreateEarthShieldMacroButton()

	local macroBtn = _G["ShamanPowerESMacroBtn"]
	if not macroBtn then return end

	local hasES = self:HasEarthShield()
	local targetName = ShamanPower_EarthShieldAssignments[self.player]

	if hasES and targetName then
		local spellName = self:GetEarthShieldSpell()
		if spellName then
			macroBtn:SetAttribute("type", "macro")
			macroBtn:SetAttribute("macrotext", "/target " .. targetName .. "\n/cast " .. spellName .. "\n/targetlasttarget")
		else
			macroBtn:SetAttribute("type", nil)
			macroBtn:SetAttribute("macrotext", nil)
		end
	else
		macroBtn:SetAttribute("type", nil)
		macroBtn:SetAttribute("macrotext", nil)
	end
end

-- ============================================================================
-- Earth Shield Button (for resto shamans with ES target assigned)
-- ============================================================================

function ShamanPower:CreateEarthShieldButton()
	if _G["ShamanPowerEarthShieldBtn"] then return end

	-- Parent to UIParent and use SPTotemButtonTemplate (same as totem buttons) for combat flyout support
	local esBtn = CreateFrame("Button", "ShamanPowerEarthShieldBtn", UIParent, "SPTotemButtonTemplate")
	esBtn:SetSize(26, 26)
	esBtn:Hide()

	-- SECURE HANDLER: Show flyout on enter (WORKS IN COMBAT)
	esBtn:SetAttribute("OpenMenu", "mouseover")
	esBtn:SetAttribute("_onenter", [[
		if self:GetAttribute("OpenMenu") == "mouseover" then
			self:ChildUpdate("show", true)
		end
	]])
	esBtn:SetAttribute("_onleave", [[
		if not self:IsUnderMouse(true) then
			self:ChildUpdate("show", false)
		end
	]])

	-- Icon (use the template's icon - $parentIcon becomes ShamanPowerEarthShieldBtnIcon)
	local icon = _G[esBtn:GetName() .. "Icon"]
	if icon then
		icon:SetTexture(self.EarthShield.icon)
	end

	-- Charge count text (bottom right corner)
	local chargeText = esBtn:CreateFontString("ShamanPowerEarthShieldBtnCharges", "OVERLAY", "NumberFontNormal")
	chargeText:SetPoint("BOTTOMRIGHT", esBtn, "BOTTOMRIGHT", -1, 1)
	chargeText:SetJustifyH("RIGHT")
	chargeText:SetTextColor(1, 1, 1)  -- White
	chargeText:SetText("")

	-- Target name text (optional, shows below button)
	local nameText = esBtn:CreateFontString("ShamanPowerEarthShieldBtnName", "OVERLAY", "GameFontHighlightSmall")
	nameText:SetPoint("TOP", esBtn, "BOTTOM", 0, -1)
	nameText:SetWidth(40)
	nameText:SetHeight(10)
	nameText:SetJustifyH("CENTER")

	-- Tooltip (use HookScript to work alongside secure handlers)
	esBtn:HookScript("OnEnter", function(self)
		if not ShamanPower.opt.ShowTooltips then return end
		local assignedTarget = ShamanPower_EarthShieldAssignments[ShamanPower.player]
		local currentTarget, charges = ShamanPower:FindEarthShieldTarget()
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Earth Shield", 0.2, 0.8, 0.2)

		if currentTarget then
			GameTooltip:AddLine("Active on: " .. currentTarget, 0, 1, 0)
			if charges and charges > 0 then
				GameTooltip:AddLine("Charges: " .. charges, 1, 1, 1)
			end
		else
			GameTooltip:AddLine("Not active on anyone", 1, 0.3, 0.3)
		end

		-- Show assigned target if different from current
		if assignedTarget and currentTarget ~= assignedTarget then
			local assignedDead = ShamanPower:IsPlayerDead(assignedTarget)
			if assignedDead then
				GameTooltip:AddLine("Assigned: " .. assignedTarget .. " (dead)", 0.5, 0.5, 0.5)
			else
				GameTooltip:AddLine("Assigned: " .. assignedTarget, 1, 0.8, 0)
			end
		end

		-- Determine who click will cast on (same logic as button)
		local castTarget = nil
		if assignedTarget and not ShamanPower:IsPlayerDead(assignedTarget) then
			castTarget = assignedTarget
		elseif currentTarget and not ShamanPower:IsPlayerDead(currentTarget) then
			castTarget = currentTarget
		end

		if castTarget then
			GameTooltip:AddLine("Click to cast on " .. castTarget, 0.7, 0.7, 0.7)
		else
			GameTooltip:AddLine("Click to cast on current target", 0.7, 0.7, 0.7)
		end
		if ShamanPower.opt.enableMiddleClickPopOut ~= false then
			GameTooltip:AddLine("|cff00ccffMiddle-click:|r Pop out", 1, 1, 1)
		end
		GameTooltip:Show()
	end)
	esBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)

	-- Register ES button updates with consolidated update system (2fps)
	if not self.updateSystem.subsystems["esButton"] then
		self:RegisterUpdateSubsystem("esButton", 0.5, function()
			ShamanPower:UpdateEarthShieldCharges()
			ShamanPower:UpdateESActiveOverlay()

			-- Update button display (name color) based on current target
			local overlay = ShamanPower.esActiveOverlay
			local overlayShowing = overlay and overlay.frame and overlay.frame:IsShown()

			if not overlayShowing then
				local esName = _G["ShamanPowerEarthShieldBtnName"]
				local esIcon = _G["ShamanPowerEarthShieldBtnIcon"]
				if esName and not ShamanPower.opt.hideEarthShieldText then
					local currentTarget = ShamanPower.currentEarthShieldTarget
					local assignedTarget = ShamanPower_EarthShieldAssignments[ShamanPower.player]
					if currentTarget then
						local shortName = Ambiguate(currentTarget, "short")
						esName:SetText(shortName)
						if assignedTarget and currentTarget == assignedTarget then
							esName:SetTextColor(0.2, 1, 0.2)  -- Green - on assigned target
						else
							esName:SetTextColor(1, 0.8, 0)  -- Yellow/Gold - on someone else
						end
						if esIcon then
							esIcon:SetDesaturated(false)
							esIcon:SetVertexColor(1, 1, 1)
						end
					else
						if assignedTarget then
							local shortName = Ambiguate(assignedTarget, "short")
							esName:SetText(shortName)
							esName:SetTextColor(1, 0.3, 0.3)  -- Red - not active
						else
							esName:SetText("None")
							esName:SetTextColor(0.5, 0.5, 0.5)  -- Grey
						end
						if esIcon then
							esIcon:SetDesaturated(true)
							esIcon:SetVertexColor(0.6, 0.6, 0.6)
						end
					end
				end
			end
		end)
	end
	-- Only enable if ES button is visible
	if self.opt.totemBarShowEarthShield ~= false and self:HasEarthShield() then
		self:EnableUpdateSubsystem("esButton")
	else
		self:DisableUpdateSubsystem("esButton")
	end

	esBtn:RegisterForClicks("AnyUp", "AnyDown")

	-- Middle-click to pop out (or return/settings if already popped)
	esBtn:HookScript("OnClick", function(self, button)
		if button == "MiddleButton" then
			-- Check if pop-out is enabled
			if ShamanPower.opt.enableMiddleClickPopOut == false then return end

			-- Debounce
			local now = GetTime()
			if ShamanPower.lastESPopOutTime and (now - ShamanPower.lastESPopOutTime) < 0.3 then
				return
			end
			ShamanPower.lastESPopOutTime = now

			local key = "earthshield"
			if ShamanPower.opt.poppedOut and ShamanPower.opt.poppedOut[key] then
				-- Already popped out
				if IsShiftKeyDown() then
					-- SHIFT+middle-click opens settings
					local frame = ShamanPower.poppedOutFrames[key]
					if frame then
						ShamanPower:ShowPopOutSettingsPanel(key, frame)
					end
				else
					-- Plain middle-click returns to bar
					if InCombatLockdown() then
						print("|cffff0000ShamanPower:|r Cannot modify pop-outs during combat")
						return
					end
					ShamanPower:ReturnPopOutToBar(key)
				end
			else
				-- Not popped out, so pop it out
				if InCombatLockdown() then
					print("|cffff0000ShamanPower:|r Cannot pop out during combat")
					return
				end
				ShamanPower:PopOutEarthShield()
			end
		end
	end)
end

-- ============================================================================
-- Earth Shield Active Overlay (shows current ES target above assigned)
-- ============================================================================

ShamanPower.esActiveOverlay = nil

function ShamanPower:CreateESActiveOverlay()
	local esBtn = _G["ShamanPowerEarthShieldBtn"]
	if not esBtn then return nil end
	if self.esActiveOverlay then return self.esActiveOverlay end

	local overlay = {}

	-- Create frame above the ES button
	local frame = CreateFrame("Frame", "ShamanPowerESActiveOverlay", esBtn)
	frame:SetSize(26, 26)
	frame:SetPoint("BOTTOM", esBtn, "TOP", 0, 2)
	frame:SetFrameLevel(esBtn:GetFrameLevel() + 5)
	frame:Hide()

	-- Background
	local bg = frame:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.7)
	overlay.bg = bg

	-- ES Icon
	local icon = frame:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("TOPLEFT", 2, -2)
	icon:SetPoint("BOTTOMRIGHT", -2, 2)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	icon:SetTexture(self.EarthShield and self.EarthShield.icon or "Interface\\Icons\\Spell_Nature_SkinofEarth")
	overlay.icon = icon

	-- Green border (Earth Shield color)
	local borderSize = 2
	local r, g, b = 0.2, 0.8, 0.2

	local borderTop = frame:CreateTexture(nil, "BORDER")
	borderTop:SetPoint("TOPLEFT", 0, 0)
	borderTop:SetPoint("TOPRIGHT", 0, 0)
	borderTop:SetHeight(borderSize)
	borderTop:SetColorTexture(r, g, b, 1)

	local borderBottom = frame:CreateTexture(nil, "BORDER")
	borderBottom:SetPoint("BOTTOMLEFT", 0, 0)
	borderBottom:SetPoint("BOTTOMRIGHT", 0, 0)
	borderBottom:SetHeight(borderSize)
	borderBottom:SetColorTexture(r, g, b, 1)

	local borderLeft = frame:CreateTexture(nil, "BORDER")
	borderLeft:SetPoint("TOPLEFT", 0, 0)
	borderLeft:SetPoint("BOTTOMLEFT", 0, 0)
	borderLeft:SetWidth(borderSize)
	borderLeft:SetColorTexture(r, g, b, 1)

	local borderRight = frame:CreateTexture(nil, "BORDER")
	borderRight:SetPoint("TOPRIGHT", 0, 0)
	borderRight:SetPoint("BOTTOMRIGHT", 0, 0)
	borderRight:SetWidth(borderSize)
	borderRight:SetColorTexture(r, g, b, 1)

	-- Target name text (inside icon)
	local nameText = frame:CreateFontString(nil, "OVERLAY")
	nameText:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
	nameText:SetPoint("CENTER", frame, "CENTER", 0, 0)
	nameText:SetTextColor(1, 1, 1)
	overlay.nameText = nameText

	-- Charge count (top right)
	local chargeText = frame:CreateFontString(nil, "OVERLAY")
	chargeText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
	chargeText:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
	chargeText:SetTextColor(1, 1, 1)
	overlay.chargeText = chargeText

	overlay.frame = frame
	self.esActiveOverlay = overlay
	return overlay
end

function ShamanPower:UpdateESActiveOverlay()
	if not self:HasEarthShield() then return end

	local esBtn = _G["ShamanPowerEarthShieldBtn"]
	if not esBtn then return end

	-- Create overlay if needed
	if not self.esActiveOverlay then
		self:CreateESActiveOverlay()
	end

	local overlay = self.esActiveOverlay
	if not overlay then return end

	local assignedTarget = ShamanPower_EarthShieldAssignments and ShamanPower_EarthShieldAssignments[self.player]
	local currentTarget, charges = self:FindEarthShieldTarget()

	local esIcon = _G["ShamanPowerEarthShieldBtnIcon"]
	local esName = _G["ShamanPowerEarthShieldBtnName"]

	-- Check if current target differs from assigned
	local showOverlay = false
	if currentTarget and assignedTarget then
		-- Normalize names for comparison
		local currentShort = Ambiguate(currentTarget, "short")
		local assignedShort = Ambiguate(assignedTarget, "short")
		if currentShort ~= assignedShort then
			showOverlay = true
		end
	elseif currentTarget and not assignedTarget then
		-- ES is active but no one is assigned - show overlay
		showOverlay = true
	end

	if showOverlay and currentTarget then
		-- Show overlay with current target info
		overlay.frame:Show()

		-- Set target name (truncate if needed)
		local shortName = Ambiguate(currentTarget, "short")
		if #shortName > 5 then
			shortName = shortName:sub(1, 5)
		end
		overlay.nameText:SetText(shortName)

		-- Set charges
		if charges and charges > 0 then
			overlay.chargeText:SetText(charges)
		else
			overlay.chargeText:SetText("")
		end

		-- Grey out the main ES button icon (assigned target)
		if esIcon then
			esIcon:SetDesaturated(true)
			esIcon:SetVertexColor(0.5, 0.5, 0.5)
		end

		-- Update main button name to show assigned (greyed)
		if esName and assignedTarget and not self.opt.hideEarthShieldText then
			local assignedShort = Ambiguate(assignedTarget, "short")
			esName:SetText(assignedShort)
			esName:SetTextColor(0.5, 0.5, 0.5) -- Grey
		end
	else
		-- Hide overlay - ES is on assigned target or not active
		overlay.frame:Hide()

		-- Restore main ES button appearance (handled by UpdateEarthShieldButton)
	end
end

-- ============================================================================
-- Earth Shield Flyout (for quickly casting ES on party/raid members)
-- ============================================================================
-- ES Flyout - OPTIMIZED: Reuses frames, no garbage creation
-- ============================================================================

ShamanPower.esFlyoutButtons = {}  -- Pool of reusable buttons
ShamanPower.esFlyoutButtonCount = 0  -- How many buttons currently in use
ShamanPower.lastESFlyoutSize = 0  -- Track group size to avoid unnecessary rebuilds

-- Pre-computed unit strings for ES flyout (avoids "raid" .. i garbage)
local esFlyoutUnits_raid = {}
local esFlyoutUnits_party = {"player", "party1", "party2", "party3", "party4"}
for i = 1, 40 do
	esFlyoutUnits_raid[i] = "raid" .. i
end

function ShamanPower:CreateEarthShieldFlyout(forceRebuild)
	-- CHECK DISABLED FIRST - before any work
	if self.opt.enableESFlyout == false then
		local esBtn = _G["ShamanPowerEarthShieldBtn"]
		if esBtn then
			esBtn:SetAttribute("OpenMenu", nil)
		end
		-- Hide all existing buttons
		for i = 1, self.esFlyoutButtonCount do
			if self.esFlyoutButtons[i] then
				self.esFlyoutButtons[i]:Hide()
			end
		end
		self.esFlyoutButtonCount = 0
		return
	end

	if not self:HasEarthShield() then return end

	-- Skip rebuild if group size hasn't changed
	local currentSize = GetNumGroupMembers()
	if not forceRebuild and currentSize == self.lastESFlyoutSize then
		return
	end
	self.lastESFlyoutSize = currentSize

	local esBtn = _G["ShamanPowerEarthShieldBtn"]
	if not esBtn then return end

	-- Enable the flyout
	esBtn:SetAttribute("OpenMenu", "mouseover")

	local buttonSize = 28
	local spacing = 0
	local spellName = self:GetEarthShieldSpell()
	local swapped = self.opt.swapFlyoutClickButtons
	local layout = self.opt.layout or "Horizontal"
	local flyoutDir = self.opt.totemFlyoutDirection or "auto"

	-- Count and update buttons directly - NO intermediate members table
	local buttonIndex = 0

	if IsInRaid() then
		for i = 1, 40 do
			local name, _, _, _, _, classFilename = GetRaidRosterInfo(i)
			if name then
				buttonIndex = buttonIndex + 1
				self:UpdateOrCreateESFlyoutButton(buttonIndex, name, classFilename, esFlyoutUnits_raid[i], esBtn, spellName, swapped, buttonSize, spacing, layout, flyoutDir)
			end
		end
	elseif IsInGroup() then
		-- Player first
		local _, classFilename = UnitClass("player")
		buttonIndex = buttonIndex + 1
		self:UpdateOrCreateESFlyoutButton(buttonIndex, UnitName("player"), classFilename, "player", esBtn, spellName, swapped, buttonSize, spacing, layout, flyoutDir)
		-- Party members
		for i = 1, 4 do
			local unit = esFlyoutUnits_party[i + 1]  -- party1-4
			if UnitExists(unit) then
				local name = UnitName(unit)
				local _, classFilename = UnitClass(unit)
				if name then
					buttonIndex = buttonIndex + 1
					self:UpdateOrCreateESFlyoutButton(buttonIndex, name, classFilename, unit, esBtn, spellName, swapped, buttonSize, spacing, layout, flyoutDir)
				end
			end
		end
	else
		-- Solo
		local _, classFilename = UnitClass("player")
		buttonIndex = buttonIndex + 1
		self:UpdateOrCreateESFlyoutButton(buttonIndex, UnitName("player"), classFilename, "player", esBtn, spellName, swapped, buttonSize, spacing, layout, flyoutDir)
	end

	-- Hide any extra buttons from previous larger group
	for i = buttonIndex + 1, self.esFlyoutButtonCount do
		if self.esFlyoutButtons[i] then
			self.esFlyoutButtons[i]:Hide()
		end
	end
	self.esFlyoutButtonCount = buttonIndex
end

-- Update an existing button or create a new one if needed
function ShamanPower:UpdateOrCreateESFlyoutButton(index, name, class, unit, esBtn, spellName, swapped, buttonSize, spacing, layout, flyoutDir)
	local btn = self.esFlyoutButtons[index]

	-- Create button only if we don't have one at this index
	if not btn then
		btn = CreateFrame("Button", "ShamanPowerESFlyoutBtn" .. index, esBtn, "SecureActionButtonTemplate, SecureHandlerShowHideTemplate, SecureHandlerEnterLeaveTemplate")
		btn:SetSize(buttonSize, buttonSize)
		btn:SetFrameStrata("DIALOG")

		-- Class icon (created once, updated each time)
		local icon = btn:CreateTexture(nil, "ARTWORK")
		icon:SetAllPoints()
		btn.icon = icon

		-- Player name text
		local nameText = btn:CreateFontString(nil, "OVERLAY")
		nameText:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
		nameText:SetPoint("CENTER", btn, "CENTER", 0, 0)
		nameText:SetTextColor(1, 1, 1)
		btn.nameText = nameText

		-- Highlight texture
		local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
		highlight:SetAllPoints()
		highlight:SetColorTexture(1, 1, 1, 0.3)

		-- SECURE HANDLER: Respond to parent's ChildUpdate
		btn:SetAttribute("_childupdate-show", [[
			if message then
				self:Show()
			else
				self:Hide()
			end
		]])

		-- SECURE HANDLER: Check parent on leave
		btn:SetAttribute("_onleave", [[
			if not self:GetParent():IsUnderMouse(true) then
				self:GetParent():ChildUpdate("show", false)
			end
		]])

		btn:RegisterForClicks("AnyUp", "AnyDown")

		-- Tooltip (uses stored attributes)
		btn:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			local memberName = self:GetAttribute("memberName")
			local memberClass = self:GetAttribute("memberClass")
			GameTooltip:AddLine(memberName or "Unknown", 1, 1, 1)
			if memberClass and RAID_CLASS_COLORS[memberClass] then
				local classColor = RAID_CLASS_COLORS[memberClass]
				GameTooltip:AddLine(memberClass, classColor.r, classColor.g, classColor.b)
			end
			GameTooltip:AddLine(" ")
			if ShamanPower.opt.swapFlyoutClickButtons then
				GameTooltip:AddLine("|cff00ff00Left-click:|r Assign as ES target", 1, 1, 1)
				GameTooltip:AddLine("|cffffcc00Right-click:|r Cast Earth Shield", 1, 1, 1)
			else
				GameTooltip:AddLine("|cff00ff00Left-click:|r Cast Earth Shield", 1, 1, 1)
				GameTooltip:AddLine("|cffffcc00Right-click:|r Assign as ES target", 1, 1, 1)
			end
			GameTooltip:Show()
		end)
		btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

		-- Handle assignment
		btn:SetScript("PostClick", function(self, button)
			local assignButton = ShamanPower.opt.swapFlyoutClickButtons and "LeftButton" or "RightButton"
			if button == assignButton then
				local memberName = self:GetAttribute("memberName")
				if memberName then
					ShamanPower_EarthShieldAssignments[ShamanPower.player] = memberName
					ShamanPower:UpdateEarthShieldButton()
					ShamanPower:SendMessage("ES_ASSIGN " .. ShamanPower.player .. " " .. memberName)
				end
			end
		end)

		self.esFlyoutButtons[index] = btn
	end

	-- UPDATE existing button with new data (no frame creation, just attribute updates)
	btn:SetParent(esBtn)

	-- Update icon
	local coords = CLASS_ICON_TCOORDS[class]
	if coords then
		btn.icon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
		btn.icon:SetTexCoord(unpack(coords))
	else
		btn.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
		btn.icon:SetTexCoord(0, 1, 0, 1)
	end

	-- Update name text
	local shortName = Ambiguate(name, "short")
	if #shortName > 5 then
		shortName = shortName:sub(1, 5)
	end
	btn.nameText:SetText(shortName)

	-- Store member info as attributes
	btn:SetAttribute("memberName", name)
	btn:SetAttribute("memberUnit", unit)
	btn:SetAttribute("memberClass", class)

	-- Set up casting macro
	local castMacro = "/target " .. name .. "\n/cast " .. spellName .. "\n/targetlasttarget"

	btn:SetAttribute("type1", nil)
	btn:SetAttribute("macrotext1", nil)
	btn:SetAttribute("type2", nil)
	btn:SetAttribute("macrotext2", nil)

	if swapped then
		btn:SetAttribute("type2", "macro")
		btn:SetAttribute("macrotext2", castMacro)
	else
		btn:SetAttribute("type1", "macro")
		btn:SetAttribute("macrotext1", castMacro)
	end

	-- Position button
	btn:ClearAllPoints()
	if layout == "Horizontal" then
		if flyoutDir == "below" then
			btn:SetPoint("TOP", esBtn, "BOTTOM", 0, -spacing - (index - 1) * (buttonSize + spacing))
		else
			btn:SetPoint("BOTTOM", esBtn, "TOP", 0, spacing + (index - 1) * (buttonSize + spacing))
		end
	elseif layout == "VerticalLeft" then
		btn:SetPoint("LEFT", esBtn, "RIGHT", spacing + (index - 1) * (buttonSize + spacing), 0)
	else
		btn:SetPoint("RIGHT", esBtn, "LEFT", -spacing - (index - 1) * (buttonSize + spacing), 0)
	end

	btn:Hide()  -- Hidden by default, shown on hover via secure handler
end

function ShamanPower:UpdateEarthShieldFlyout()
	if InCombatLockdown() then return end
	self:CreateEarthShieldFlyout()
end

function ShamanPower:UpdateESFlyoutClickBehavior()
	if InCombatLockdown() then
		print("|cffff0000ShamanPower:|r Cannot change flyout settings in combat")
		return
	end

	local swapped = self.opt.swapFlyoutClickButtons
	local spellName = self:GetEarthShieldSpell()
	if not spellName then return end

	for _, btn in ipairs(self.esFlyoutButtons) do
		local memberName = btn:GetAttribute("memberName")
		if memberName then
			local castMacro = "/target " .. memberName .. "\n/cast " .. spellName .. "\n/targetlasttarget"

			btn:SetAttribute("type1", nil)
			btn:SetAttribute("macrotext1", nil)
			btn:SetAttribute("type2", nil)
			btn:SetAttribute("macrotext2", nil)

			if swapped then
				btn:SetAttribute("type2", "macro")
				btn:SetAttribute("macrotext2", castMacro)
				btn:SetAttribute("assignButton", "LeftButton")
			else
				btn:SetAttribute("type1", "macro")
				btn:SetAttribute("macrotext1", castMacro)
				btn:SetAttribute("assignButton", "RightButton")
			end
		end
	end
end

-- Get unit ID from player name
function ShamanPower:GetUnitFromName(name)
	if not name then return nil end

	-- Normalize the input name (remove server suffix for comparison)
	local shortName = Ambiguate(name, "short")

	-- Check player
	local playerName = UnitName("player")
	if playerName and (playerName == name or playerName == shortName) then return "player" end

	-- Check target
	local targetName = UnitName("target")
	if targetName and (targetName == name or targetName == shortName) then return "target" end

	-- Check party
	for i = 1, 4 do
		local unitName = UnitName("party" .. i)
		if unitName and (unitName == name or unitName == shortName) then return "party" .. i end
	end

	-- Check raid
	for i = 1, 40 do
		local unitName = UnitName("raid" .. i)
		if unitName and (unitName == name or unitName == shortName) then return "raid" .. i end
	end

	return nil
end

-- Get Earth Shield charges on a target
function ShamanPower:GetEarthShieldCharges(targetName)
	local unit = self:GetUnitFromName(targetName)
	if not unit then return 0 end

	-- Get the localized spell name for Earth Shield
	local esSpellName = nil
	if self.EarthShield then
		esSpellName = GetSpellInfo(self.EarthShield.rank3) or GetSpellInfo(self.EarthShield.rank2) or GetSpellInfo(self.EarthShield.rank1)
	end

	-- Search for Earth Shield buff
	for i = 1, 40 do
		local name, icon, count, debuffType, duration, expirationTime, source = UnitBuff(unit, i)
		if not name then break end
		-- Check if it's Earth Shield (by localized name)
		if esSpellName and name == esSpellName then
			return count or 0
		end
	end

	return 0
end

-- ============================================================================
-- Earth Shield Tracking (Event-based, like TotemTimers)
-- Tracks who has ES by watching your casts, NOT by scanning all raid members
-- ============================================================================

-- Tracked ES target info (set when you cast ES)
ShamanPower.esTrackedTarget = nil      -- Name of player with your ES
ShamanPower.esTrackedTargetGUID = nil  -- GUID of player with your ES
ShamanPower.esTrackedCharges = 0       -- Current charges
ShamanPower.esLastCastTarget = nil     -- Pending cast target (from SENT)
ShamanPower.esLastCastGUID = nil       -- Pending cast GUID
ShamanPower.cachedESSpellName = nil    -- Cached spell name

-- Get the ES spell name (cached)
function ShamanPower:GetESSpellName()
	if self.cachedESSpellName then return self.cachedESSpellName end
	if not self.EarthShield then return nil end
	self.cachedESSpellName = GetSpellInfo(self.EarthShield.rank3) or GetSpellInfo(self.EarthShield.rank2) or GetSpellInfo(self.EarthShield.rank1)
	return self.cachedESSpellName
end

-- Handle ES spell cast events
function ShamanPower:OnEarthShieldCastSent(target, castGUID, spellID)
	local esSpellName = self:GetESSpellName()
	if not esSpellName then return end

	local spellName = GetSpellInfo(spellID)
	if spellName == esSpellName then
		-- Store pending cast info
		self.esLastCastTarget = target
		self.esLastCastGUID = UnitGUID(target)
		-- If we can't get GUID from target name, try current target/focus
		if not self.esLastCastGUID then
			if target == UnitName("target") then
				self.esLastCastGUID = UnitGUID("target")
			elseif target == UnitName("focus") then
				self.esLastCastGUID = UnitGUID("focus")
			end
		end
	end
end

function ShamanPower:OnEarthShieldCastSucceeded(unit, castGUID, spellID)
	if unit ~= "player" then return end

	local esSpellName = self:GetESSpellName()
	if not esSpellName then return end

	local spellName = GetSpellInfo(spellID)
	if spellName == esSpellName and self.esLastCastTarget then
		-- Cast succeeded! Update tracked target
		self.esTrackedTarget = self.esLastCastTarget
		self.esTrackedTargetGUID = self.esLastCastGUID
		self.esTrackedCharges = 6  -- Full charges on fresh cast (will be updated by UNIT_AURA)

		-- Clear pending
		self.esLastCastTarget = nil
		self.esLastCastGUID = nil

		-- Update display
		self:UpdateEarthShieldButton()
	end
end

-- Handle aura changes on tracked target
function ShamanPower:OnEarthShieldAuraChange(unit)
	if not self.esTrackedTargetGUID then return end

	-- Only process if this is our ES target
	if UnitGUID(unit) ~= self.esTrackedTargetGUID then return end

	local esSpellName = self:GetESSpellName()
	if not esSpellName then return end

	-- Check this ONE unit for ES buff
	local found = false
	for i = 1, 40 do
		local name, _, count, _, _, _, source = UnitBuff(unit, i)
		if not name then break end
		if name == esSpellName and source == "player" then
			self.esTrackedCharges = count or 0
			found = true
			break
		end
	end

	if not found then
		-- ES fell off
		self.esTrackedTarget = nil
		self.esTrackedTargetGUID = nil
		self.esTrackedCharges = 0
	end

	-- Update display (but not full rebuild)
	self:UpdateEarthShieldCharges()
end

-- Find who currently has YOUR Earth Shield (uses tracked data, NO scanning!)
function ShamanPower:FindEarthShieldTarget()
	if not self.EarthShield then return nil, 0 end

	-- Just return the tracked target (set by cast events)
	if self.esTrackedTarget and self.esTrackedTargetGUID then
		-- Verify they still exist and have ES (quick single-unit check)
		local unit = nil
		-- Try to find a valid unit ID for the tracked GUID
		if UnitGUID("target") == self.esTrackedTargetGUID then
			unit = "target"
		elseif UnitGUID("focus") == self.esTrackedTargetGUID then
			unit = "focus"
		elseif UnitGUID("player") == self.esTrackedTargetGUID then
			unit = "player"
		else
			-- Check party/raid
			if IsInRaid() then
				for i = 1, 40 do
					if UnitGUID("raid" .. i) == self.esTrackedTargetGUID then
						unit = "raid" .. i
						break
					end
				end
			else
				for i = 1, 4 do
					if UnitGUID("party" .. i) == self.esTrackedTargetGUID then
						unit = "party" .. i
						break
					end
				end
			end
		end

		if unit and UnitExists(unit) then
			return self.esTrackedTarget, self.esTrackedCharges
		else
			-- Target left group or doesn't exist
			self.esTrackedTarget = nil
			self.esTrackedTargetGUID = nil
			self.esTrackedCharges = 0
		end
	end

	return nil, 0
end

-- Update the charge display on the button
function ShamanPower:UpdateEarthShieldCharges()
	local chargeText = _G["ShamanPowerEarthShieldBtnCharges"]
	if not chargeText then return end

	-- Find who currently has our Earth Shield
	local currentTarget, charges = self:FindEarthShieldTarget()

	if currentTarget and charges and charges > 0 then
		chargeText:SetText(NumberStrings[charges] or tostring(charges))
		-- Color based on charges if enabled (Earth Shield has more charges: 6-10)
		if self.opt.shieldChargeColors then
			if charges >= 5 then
				chargeText:SetTextColor(0, 1, 0)  -- Green (healthy)
			elseif charges >= 3 then
				chargeText:SetTextColor(1, 1, 0)  -- Yellow (getting low)
			else
				chargeText:SetTextColor(1, 0, 0)  -- Red (critical - 1-2 charges)
			end
		else
			chargeText:SetTextColor(1, 1, 1)  -- White (default)
		end
	else
		chargeText:SetText("")
	end

	-- Store current target for display purposes
	self.currentEarthShieldTarget = currentTarget
end

-- Check if a player is dead (by name)
function ShamanPower:IsPlayerDead(playerName)
	if not playerName then return true end
	local unit = self:GetUnitFromName(playerName)
	if not unit then return true end  -- Can't find them, treat as unavailable
	return UnitIsDeadOrGhost(unit)
end

function ShamanPower:UpdateEarthShieldButton()
	if InCombatLockdown() then return end
	if not self.autoButton then return end

	-- Create button if it doesn't exist
	self:CreateEarthShieldButton()

	local esBtn = _G["ShamanPowerEarthShieldBtn"]
	if not esBtn then return end

	-- Enable/disable esButton subsystem based on visibility
	local shouldShow = (self.opt.totemBarShowEarthShield ~= false) and self:HasEarthShield() and not self.totemBarHidden
	if shouldShow then
		self:EnableUpdateSubsystem("esButton")
	else
		self:DisableUpdateSubsystem("esButton")
	end

	-- Check if totem bar is hidden (hide out of combat / hide when no totems)
	if self.totemBarHidden then
		esBtn:Hide()
		return
	end

	-- Check if Earth Shield button should be hidden
	if self.opt.totemBarShowEarthShield == false then
		esBtn:Hide()
		return
	end

	local esIcon = _G["ShamanPowerEarthShieldBtnIcon"]
	local esName = _G["ShamanPowerEarthShieldBtnName"]

	-- Check if we have Earth Shield talent
	local hasES = self:HasEarthShield()
	local assignedTarget = ShamanPower_EarthShieldAssignments[self.player]

	-- Find who currently has our Earth Shield (fetch fresh, don't rely on cached value)
	local currentTarget, currentCharges = self:FindEarthShieldTarget()
	self.currentEarthShieldTarget = currentTarget  -- Update cache

	if hasES then
		-- Get the spell name
		local spellName = self:GetEarthShieldSpell()
		if spellName then
			-- Determine who to cast on:
			-- Dynamic mode: prioritize current target (refresh existing shield)
			-- Normal mode: prioritize assigned target
			local castTarget = nil
			if self.opt.dynamicTotemMode then
				-- Dynamic mode: prefer whoever currently has ES, fall back to assigned
				if currentTarget and not self:IsPlayerDead(currentTarget) then
					castTarget = currentTarget
					-- Update assignment to match current target
					if currentTarget ~= assignedTarget then
						ShamanPower_EarthShieldAssignments[self.player] = currentTarget
					end
				elseif assignedTarget and not self:IsPlayerDead(assignedTarget) then
					castTarget = assignedTarget
				end
			else
				-- Normal mode: prefer assigned target, fall back to current
				if assignedTarget and not self:IsPlayerDead(assignedTarget) then
					castTarget = assignedTarget
				elseif currentTarget and not self:IsPlayerDead(currentTarget) then
					castTarget = currentTarget
				end
			end

			if castTarget then
				esBtn:SetAttribute("type1", "macro")
				esBtn:SetAttribute("macrotext1", "/target " .. castTarget .. "\n/cast " .. spellName .. "\n/targetlasttarget")
			else
				-- No valid target - just cast on current target
				esBtn:SetAttribute("type1", "spell")
				esBtn:SetAttribute("spell1", spellName)
			end

			-- Update icon
			if esIcon then
				esIcon:SetTexture(self.EarthShield.icon)
				-- Desaturate icon if no one has ES
				if not currentTarget then
					esIcon:SetDesaturated(true)
					esIcon:SetVertexColor(0.6, 0.6, 0.6)
				else
					esIcon:SetDesaturated(false)
					esIcon:SetVertexColor(1, 1, 1)
				end
			end

			-- Show who currently has Earth Shield (unless hidden by option)
			if esName then
				if self.opt.hideEarthShieldText then
					esName:Hide()
				else
					if currentTarget then
						-- Someone has ES - show their name
						local shortName = Ambiguate(currentTarget, "short")
						esName:SetText(shortName)
						-- Color based on whether it's the assigned target
						if assignedTarget and currentTarget == assignedTarget then
							esName:SetTextColor(0.2, 1, 0.2)  -- Green - on assigned target
						else
							esName:SetTextColor(1, 0.8, 0)  -- Yellow/Gold - on someone else
						end
					else
						-- No one has ES
						if assignedTarget then
							local shortName = Ambiguate(assignedTarget, "short")
							esName:SetText(shortName)
							esName:SetTextColor(1, 0.3, 0.3)  -- Red - not active
						else
							esName:SetText("None")
							esName:SetTextColor(0.5, 0.5, 0.5)  -- Grey
						end
					end
					esName:Show()
				end
			end

			esBtn:Show()

			-- Reposition in the mini bar
			self:RepositionEarthShieldButton()

			-- Create/update ES flyout for party/raid members
			self:CreateEarthShieldFlyout()
		else
			esBtn:Hide()
		end
	else
		esBtn:Hide()
		if esName then esName:Hide() end
	end
end

function ShamanPower:RepositionEarthShieldButton()
	local esBtn = _G["ShamanPowerEarthShieldBtn"]
	if not esBtn or not esBtn:IsShown() then return end
	if not self.autoButton then return end

	-- Skip repositioning if Earth Shield is popped out
	if self:IsEarthShieldPoppedOut() then return end

	-- Match scale of other totem buttons
	esBtn:SetScale(self.opt.buffscale or 0.9)

	local isHorizontal = (self.opt.layout == "Horizontal")
	local buttonSize = 26
	local spacing = self.opt.totemBarPadding or 2
	local showDropAll = self.opt.showDropAllButton ~= false
	local dropAllPoppedOut = self:IsDropAllPoppedOut()
	local showTotemicCall = self.opt.totemicCallOnTotemBar and self.opt.cdbarShowRecall ~= false

	-- Find the anchor point - Totemic Call > Drop All > last visible totem button
	local anchorFrame = nil
	local totemicCallBtn = _G["ShamanPowerAutoTotemicCall"]
	local dropAllBtn = _G["ShamanPowerAutoDropAll"]

	-- First check Totemic Call (it's positioned after Drop All)
	if showTotemicCall and totemicCallBtn and totemicCallBtn:IsShown() then
		anchorFrame = totemicCallBtn
	elseif showDropAll and dropAllBtn and dropAllBtn:IsShown() and not dropAllPoppedOut then
		-- Anchor to Drop All button (only if not popped out)
		anchorFrame = dropAllBtn
	else
		-- Find the last visible totem button based on totemBarOrder
		-- Exclude popped-out elements (they're reparented elsewhere)
		local totemOrder = self.opt.totemBarOrder or {1, 2, 3, 4}
		local elementVisible = {
			[1] = self.opt.totemBarShowEarth ~= false and not self:IsElementPoppedOut(1),
			[2] = self.opt.totemBarShowFire ~= false and not self:IsElementPoppedOut(2),
			[3] = self.opt.totemBarShowWater ~= false and not self:IsElementPoppedOut(3),
			[4] = self.opt.totemBarShowAir ~= false and not self:IsElementPoppedOut(4),
		}

		-- Find the last visible element in order
		for i = 4, 1, -1 do
			local element = totemOrder[i]
			if elementVisible[element] and self.totemButtons[element] then
				anchorFrame = self.totemButtons[element]
				break
			end
		end
	end

	esBtn:ClearAllPoints()

	if anchorFrame then
		if isHorizontal then
			-- Position to the right of anchor with padding
			esBtn:SetPoint("LEFT", anchorFrame, "RIGHT", spacing, 0)
		else
			-- Position below anchor with padding
			esBtn:SetPoint("TOP", anchorFrame, "BOTTOM", 0, -spacing)
		end
	else
		-- No anchor - position at start of autoButton
		local padding = 4
		if isHorizontal then
			esBtn:SetPoint("TOPLEFT", self.autoButton, "TOPLEFT", padding, -padding)
		else
			esBtn:SetPoint("TOPLEFT", self.autoButton, "TOPLEFT", padding, -padding)
		end
	end

	-- Update autoButton size to include ES button
	self:UpdateAutoButtonSize()
end

function ShamanPower:UpdateAutoButtonSize()
	if not self.autoButton then return end

	local padding = 4
	local buttonSize = 26
	local spacing = self.opt.totemBarPadding or 2
	local isHorizontal = (self.opt.layout == "Horizontal")
	local showDropAll = self.opt.showDropAllButton ~= false and not self:IsDropAllPoppedOut()
	local showES = self.opt.totemBarShowEarthShield ~= false and self:HasEarthShield() and not self:IsEarthShieldPoppedOut()

	-- Count visible totem buttons (not hidden in options and not popped out)
	local visibleCount = 0
	if self.opt.totemBarShowEarth ~= false and not self:IsElementPoppedOut(1) then visibleCount = visibleCount + 1 end
	if self.opt.totemBarShowFire ~= false and not self:IsElementPoppedOut(2) then visibleCount = visibleCount + 1 end
	if self.opt.totemBarShowWater ~= false and not self:IsElementPoppedOut(3) then visibleCount = visibleCount + 1 end
	if self.opt.totemBarShowAir ~= false and not self:IsElementPoppedOut(4) then visibleCount = visibleCount + 1 end

	local baseSize = (buttonSize * visibleCount) + (spacing * math.max(0, visibleCount - 1))

	if isHorizontal then
		local totalWidth = padding * 2
		if visibleCount > 0 then
			totalWidth = totalWidth + baseSize
		end
		if showDropAll and visibleCount > 0 then
			totalWidth = totalWidth + spacing + buttonSize
		elseif showDropAll then
			totalWidth = totalWidth + buttonSize
		end
		if showES then
			totalWidth = totalWidth + spacing + buttonSize
		end
		self.autoButton:SetWidth(math.max(totalWidth, buttonSize + padding * 2))
	else
		local totalHeight = padding * 2
		if visibleCount > 0 then
			totalHeight = totalHeight + baseSize
		end
		if showDropAll and visibleCount > 0 then
			totalHeight = totalHeight + spacing + buttonSize
		elseif showDropAll then
			totalHeight = totalHeight + buttonSize
		end
		if showES then
			totalHeight = totalHeight + spacing + buttonSize
		end
		self.autoButton:SetHeight(math.max(totalHeight, buttonSize + padding * 2))
	end
end


-- ============================================================================
-- Drop All Button - cycles through all 4 totems
-- ============================================================================

ShamanPower.dropAllCurrentElement = 1  -- Start with Earth
ShamanPower.dropAllSequence = {}  -- Ordered list of {element, spellName, icon}
ShamanPower.dropAllInCombat = false  -- Track if we were in combat
ShamanPower.dropAllLastMacro = ""  -- Track last macro to avoid unnecessary rebuilds
ShamanPower.dropAllMiddleClickHooked = false  -- Track if we've hooked middle-click

-- Build the totem sequence and update the Drop All button
function ShamanPower:UpdateDropAllButton()
	-- Reset sequence when leaving combat (mimics castsequence reset=combat)
	local inCombat = InCombatLockdown()
	if self.dropAllInCombat and not inCombat then
		self.dropAllCurrentElement = 1
		self.dropAllLastMacro = ""  -- Force macro rebuild after combat
	end
	self.dropAllInCombat = inCombat
	local dropAllBtn = _G["ShamanPowerAutoDropAll"]
	if not dropAllBtn then return end

	-- One-time setup: Add middle-click handler for pop-out (or return/settings if already popped)
	if not self.dropAllMiddleClickHooked then
		self.dropAllMiddleClickHooked = true
		dropAllBtn:HookScript("OnClick", function(self, button)
			if button == "MiddleButton" then
				-- Check if pop-out is enabled
				if ShamanPower.opt.enableMiddleClickPopOut == false then return end

				-- Debounce
				local now = GetTime()
				if ShamanPower.lastDropAllPopOutTime and (now - ShamanPower.lastDropAllPopOutTime) < 0.3 then
					return
				end
				ShamanPower.lastDropAllPopOutTime = now

				local key = "dropall"
				if ShamanPower.opt.poppedOut and ShamanPower.opt.poppedOut[key] then
					-- Already popped out
					if IsShiftKeyDown() then
						-- SHIFT+middle-click opens settings
						local frame = ShamanPower.poppedOutFrames[key]
						if frame then
							ShamanPower:ShowPopOutSettingsPanel(key, frame)
						end
					else
						-- Plain middle-click returns to bar
						if InCombatLockdown() then
							print("|cffff0000ShamanPower:|r Cannot modify pop-outs during combat")
							return
						end
						ShamanPower:ReturnPopOutToBar(key)
					end
				else
					-- Not popped out, so pop it out
					if InCombatLockdown() then
						print("|cffff0000ShamanPower:|r Cannot pop out during combat")
						return
					end
					ShamanPower:PopOutDropAll()
				end
			end
		end)
	end

	local playerName = self.player
	local assignments = ShamanPower_Assignments[playerName]
	if not assignments then return end

	-- Build ordered list of assigned totems using custom drop order
	local newSequence = {}
	local totemSpells = {}
	local dropOrder = self.opt.dropOrder or {1, 2, 3, 4}
	-- Build exclude table for easy lookup
	local excludeTotem = {
		[1] = self.opt.excludeEarthFromDropAll,
		[2] = self.opt.excludeFireFromDropAll,
		[3] = self.opt.excludeWaterFromDropAll,
		[4] = self.opt.excludeAirFromDropAll,
	}
	for _, element in ipairs(dropOrder) do
		-- Skip if this totem type is excluded
		if not excludeTotem[element] then
			local totemIndex = assignments[element] or 0
			if totemIndex and totemIndex > 0 then
				local spellID = self:GetTotemSpell(element, totemIndex)
				if spellID then
					local spellName = GetSpellInfo(spellID)
					-- Fallback to our stored name if GetSpellInfo fails
					if not spellName then
						spellName = self:GetTotemName(element, totemIndex)
						-- Add "Totem" suffix if not present (for castsequence compatibility)
						if spellName and not spellName:find("Totem") and not spellName:find("Elemental") then
							spellName = spellName .. " Totem"
						end
					end
					if spellName then
						local icon = self:GetTotemIcon(element, totemIndex)
						table.insert(newSequence, {element = element, spellName = spellName, icon = icon})
						table.insert(totemSpells, spellName)
					end
				end
			end
		end
	end

	-- Build the macro text to check if it changed
	local macroText = ""
	if #totemSpells > 0 then
		macroText = "/castsequence reset=combat " .. table.concat(totemSpells, ", ")
	end

	-- Only update sequence and macro if the spell list actually changed
	if macroText ~= self.dropAllLastMacro then
		-- Update the cached sequence
		self.dropAllSequence = newSequence

		-- Reset to first element when sequence changes
		self.dropAllCurrentElement = 1

		-- Set up as a castsequence macro (only outside combat)
		if not InCombatLockdown() then
			dropAllBtn:RegisterForClicks("AnyUp", "AnyDown")
			if #totemSpells > 0 then
				dropAllBtn:SetAttribute("type", "macro")
				dropAllBtn:SetAttribute("macrotext", macroText)
			else
				dropAllBtn:SetAttribute("type", nil)
				dropAllBtn:SetAttribute("macrotext", nil)
			end
			self.dropAllLastMacro = macroText
		end
	end

	-- Reset to first element if current is out of bounds
	if self.dropAllCurrentElement > #self.dropAllSequence then
		self.dropAllCurrentElement = 1
	end
	if self.dropAllCurrentElement < 1 then
		self.dropAllCurrentElement = 1
	end

	-- Update icon to show next totem
	self:UpdateDropAllIcon()
end

-- Update just the icon (can be called in combat)
function ShamanPower:UpdateDropAllIcon()
	local dropAllBtn = _G["ShamanPowerAutoDropAll"]
	if not dropAllBtn then return end

	local iconTexture = dropAllBtn.icon or _G["ShamanPowerAutoDropAllIcon"]
	if not iconTexture then return end

	-- Show the icon of the current totem in the sequence (rotating)
	if #self.dropAllSequence > 0 and self.dropAllCurrentElement <= #self.dropAllSequence then
		local current = self.dropAllSequence[self.dropAllCurrentElement]
		if current and current.icon then
			iconTexture:SetTexture(current.icon)
		end
	else
		-- Default to generic totem icon if no sequence
		iconTexture:SetTexture(136024)
	end
end

-- Called after clicking to advance to the next totem
function ShamanPower:AdvanceDropAllTotem(button, mouseButton, down)
	-- Only advance on mouse-up, not mouse-down (button fires both events)
	if down then return end

	if #self.dropAllSequence == 0 then return end

	-- Advance to next totem in sequence
	self.dropAllCurrentElement = self.dropAllCurrentElement + 1
	if self.dropAllCurrentElement > #self.dropAllSequence then
		self.dropAllCurrentElement = 1  -- Wrap around
	end

	-- Update icon immediately (works in combat)
	self:UpdateDropAllIcon()
end

-- Tooltip for drop all button
function ShamanPower:DropAllTooltip(button)
	if not self.opt.ShowTooltips then return end

	GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
	GameTooltip:AddLine("Drop All Totems", 1, 0.8, 0)

	-- Show current/next totem
	if #self.dropAllSequence > 0 and self.dropAllCurrentElement <= #self.dropAllSequence then
		local current = self.dropAllSequence[self.dropAllCurrentElement]
		if current then
			local elementName = self.Elements[current.element] or "Unknown"
			GameTooltip:AddLine("Next: " .. elementName .. " - " .. current.spellName, 0, 1, 0)
		end
	end

	GameTooltip:AddLine(" ", 1, 1, 1)
	GameTooltip:AddLine("Sequence:", 0.7, 0.7, 0.7)

	-- Show all totems in sequence, highlighting current
	for i, totem in ipairs(self.dropAllSequence) do
		local elementName = self.Elements[totem.element] or "Unknown"
		if i == self.dropAllCurrentElement then
			GameTooltip:AddLine("  > " .. elementName .. ": " .. totem.spellName, 0, 1, 0)
		else
			GameTooltip:AddLine("    " .. elementName .. ": " .. totem.spellName, 0.7, 0.7, 0.7)
		end
	end

	GameTooltip:AddLine(" ", 1, 1, 1)
	GameTooltip:AddLine("Resets when combat ends", 0.5, 0.5, 0.5)
	if self.opt.enableMiddleClickPopOut ~= false then
		GameTooltip:AddLine("|cff00ccffMiddle-click:|r Pop out", 1, 1, 1)
	end
	GameTooltip:Show()
end

-- Tooltip for Totemic Call button
function ShamanPower:TotemicCallTooltip(button)
	if not self.opt.ShowTooltips then return end
	GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
	GameTooltip:SetSpellByID(36936)  -- Totemic Call
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("|cff888888Recalls all active totems|r", 1, 1, 1)
	GameTooltip:Show()
end

-- Set up Totemic Call button (from XML: ShamanPowerAutoTotemicCall)
function ShamanPower:SetupTotemicCallButton()
	local btn = _G["ShamanPowerAutoTotemicCall"]
	if not btn then return end

	-- Set up spell casting (Totemic Call)
	local spellName = GetSpellInfo(36936)
	if spellName and not InCombatLockdown() then
		btn:RegisterForClicks("AnyUp", "AnyDown")
		btn:SetAttribute("type1", "spell")
		btn:SetAttribute("spell1", spellName)
	end

	-- Update icon texture
	local iconTexture = btn.icon or _G["ShamanPowerAutoTotemicCallIcon"]
	if iconTexture then
		local _, _, icon = GetSpellInfo(36936)
		if icon then
			iconTexture:SetTexture(icon)
		end
	end
end

-- Update Totemic Call button opacity based on whether totems are active
function ShamanPower:UpdateTotemicCallOpacity()
	local btn = _G["ShamanPowerAutoTotemicCall"]
	if not btn or not btn:IsShown() then return end

	local fullWhenActive = self.opt.cooldownBarFullOpacityWhenActive

	if fullWhenActive then
		-- Check if any totems are placed
		local hasTotem = false
		for slot = 1, 4 do
			local haveTotem = GetTotemInfo(slot)
			if haveTotem then
				hasTotem = true
				break
			end
		end
		-- When active, ignore parent alpha so button is fully visible
		if hasTotem then
			btn:SetIgnoreParentAlpha(true)
			btn:SetAlpha(1.0)
		else
			btn:SetIgnoreParentAlpha(false)
			btn:SetAlpha(1.0)  -- Inherit parent opacity
		end
	else
		btn:SetIgnoreParentAlpha(false)
		btn:SetAlpha(1.0)  -- Inherit parent opacity
	end
end

-- ============================================================================
-- TOTEMIC CALL BUTTON (on totem bar, optional) - Legacy dynamic version
-- ============================================================================

function ShamanPower:CreateTotemicCallButton()
	if self.totemicCallButton then return self.totemicCallButton end
	if not self.autoButton then return nil end

	-- Create secure button for Totemic Call
	local btn = CreateFrame("Button", "ShamanPowerTotemicCall", self.autoButton, "SecureActionButtonTemplate")
	btn:SetSize(26, 26)
	btn:SetFrameLevel(self.autoButton:GetFrameLevel() + 10)
	btn:RegisterForClicks("AnyUp", "AnyDown")
	btn:Hide()

	-- Icon
	local icon = btn:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	icon:SetTexture(GetSpellTexture(36936))  -- Totemic Call icon
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	btn.icon = icon

	-- Border
	local border = btn:CreateTexture(nil, "OVERLAY")
	border:SetPoint("TOPLEFT", -1, 1)
	border:SetPoint("BOTTOMRIGHT", 1, -1)
	border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
	border:SetBlendMode("ADD")
	border:SetVertexColor(0.6, 0.6, 0.6, 0.5)
	btn.border = border

	-- Highlight
	local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetColorTexture(1, 1, 1, 0.2)

	-- Set up spell casting
	local spellName = GetSpellInfo(36936)
	if spellName then
		btn:SetAttribute("type1", "spell")
		btn:SetAttribute("spell1", spellName)
	end

	-- Cooldown frame
	local cooldown = CreateFrame("Cooldown", "ShamanPowerTotemicCallCD", btn, "CooldownFrameTemplate")
	cooldown:SetAllPoints()
	btn.cooldown = cooldown

	-- Tooltip
	btn:SetScript("OnEnter", function(self)
		if not ShamanPower.opt.ShowTooltips then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetSpellByID(36936)
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("|cff888888Recalls all active totems|r", 1, 1, 1)
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", function(self)
		GameTooltip:Hide()
	end)

	self.totemicCallButton = btn
	return btn
end

function ShamanPower:UpdateTotemicCallButton()
	local showOnTotemBar = self.opt.totemicCallOnTotemBar and self.opt.cdbarShowRecall ~= false

	if showOnTotemBar then
		if not self.totemicCallButton then
			self:CreateTotemicCallButton()
		end

		if self.totemicCallButton then
			-- Update cooldown display
			local start, duration = GetSpellCooldown(36936)
			if start and start > 0 and duration > 1.5 then
				self.totemicCallButton.cooldown:SetCooldown(start, duration)
			else
				self.totemicCallButton.cooldown:Clear()
			end
		end
	else
		if self.totemicCallButton then
			self.totemicCallButton:Hide()
		end
	end
end

function ShamanPower:PerformCycle(name, class, skipzero)
	local shift = (IsShiftKeyDown() and ShamanPowerBlessingsFrame:IsMouseOver())
	local control = (IsControlKeyDown() and ShamanPowerBlessingsFrame:IsMouseOver())
	local cur
	if shift then
		class = 5
	end
	if not ShamanPower_Assignments[name] then
		ShamanPower_Assignments[name] = {}
	end
	if not ShamanPower_Assignments[name][class] then
		cur = 0
	else
		cur = ShamanPower_Assignments[name][class]
	end
	ShamanPower_Assignments[name][class] = 0
	-- Get the max number of totems for this element
	local maxTotems = self.TotemNames[class] and #self.TotemNames[class] or 8
	for testB = cur + 1, maxTotems do
		cur = testB
		-- For shamans, all totems are available - just cycle through them
		break
	end
	if cur > maxTotems then
		-- Wrap around to 0 (no totem) or 1 (first totem)
		if skipzero then
			cur = 1
		else
			cur = 0
		end
	end
	if shift then
		for testC = 1, SHAMANPOWER_MAXCLASSES do
			ShamanPower_Assignments[name][testC] = cur
		end
		-- Sync all elements to TotemTimers if this is the current player
		if name == self.player then
			for testC = 1, 4 do
				self:SyncToTotemTimers(testC, cur)
			end
		end
		local msgQueue
		msgQueue =
			C_Timer.NewTimer(
			2.0,
			function()
				self:SendMessage("MASSIGN " .. name .. " " .. ShamanPower_Assignments[name][class])
				self:UpdateLayout()
				msgQueue:Cancel()
			end
		)
	else
		ShamanPower_Assignments[name][class] = cur
		-- Sync to TotemTimers if this is the current player's assignment
		if name == self.player and class >= 1 and class <= 4 then
			self:SyncToTotemTimers(class, cur)
			-- Also update the mini totem bar
			self:UpdateMiniTotemBar()
			self:UpdateDropAllButton()
			-- Update macros when assignment changes
			self:UpdateSPMacros()
		end
		local msgQueue
		msgQueue =
			C_Timer.NewTimer(
			2.0,
			function()
				self:SendMessage("ASSIGN " .. name .. " " .. class .. " " .. ShamanPower_Assignments[name][class])
				self:UpdateLayout()
				msgQueue:Cancel()
			end
		)
	end
end

function ShamanPower:PerformCycleBackwards(name, class, skipzero)
	local shift = (IsShiftKeyDown() and ShamanPowerBlessingsFrame:IsMouseOver())
	local control = (IsControlKeyDown() and ShamanPowerBlessingsFrame:IsMouseOver())
	local cur
	if shift then
		class = 5
	end
	if name and not ShamanPower_Assignments[name] then
		ShamanPower_Assignments[name] = {}
	end
	-- Get max totems for this element
	local maxTotems = self.TotemNames[class] and #self.TotemNames[class] or 8
	if not ShamanPower_Assignments[name][class] then
		cur = maxTotems
	else
		cur = ShamanPower_Assignments[name][class]
		local testB = 1
		if cur == 0 or (skipzero and cur == testB) then
			cur = maxTotems
		end
	end
	ShamanPower_Assignments[name][class] = 0
	-- Simple backwards cycle - go to previous totem
	cur = cur - 1
	if cur < 0 then
		-- Wrap around to max totem or 0
		if skipzero then
			cur = maxTotems
		else
			cur = maxTotems
		end
	end
	if shift then
		for testC = 1, SHAMANPOWER_MAXCLASSES do
			ShamanPower_Assignments[name][testC] = cur
		end
		-- Sync all elements to TotemTimers if this is the current player
		if name == self.player then
			for testC = 1, 4 do
				self:SyncToTotemTimers(testC, cur)
			end
		end
		local msgQueue
		msgQueue =
			C_Timer.NewTimer(
			2.0,
			function()
				self:SendMessage("MASSIGN " .. name .. " " .. ShamanPower_Assignments[name][class])
				self:UpdateLayout()
				msgQueue:Cancel()
			end
		)
	else
		ShamanPower_Assignments[name][class] = cur
		-- Sync to TotemTimers if this is the current player's assignment
		if name == self.player and class >= 1 and class <= 4 then
			self:SyncToTotemTimers(class, cur)
			-- Also update the mini totem bar
			self:UpdateMiniTotemBar()
			self:UpdateDropAllButton()
			-- Update macros when assignment changes
			self:UpdateSPMacros()
		end
		local msgQueue
		msgQueue =
			C_Timer.NewTimer(
			2.0,
			function()
				self:SendMessage("ASSIGN " .. name .. " " .. class .. " " .. ShamanPower_Assignments[name][class])
				self:UpdateLayout()
				msgQueue:Cancel()
			end
		)
	end
end

function ShamanPower:PerformPlayerCycle(delta, pname, class)
	local control = (IsControlKeyDown() and ShamanPowerBlessingsFrame:IsMouseOver())
	local blessing = 0
	if not isShaman then
		return
	end
	if ShamanPower_NormalAssignments[self.player] and ShamanPower_NormalAssignments[self.player][class] and ShamanPower_NormalAssignments[self.player][class][pname] then
		blessing = ShamanPower_NormalAssignments[self.player][class][pname]
	end
	local count
	-- Can't give Blessing of Sacrifice to yourself
	if self.isWrath then
		count = 5
	else
		if pname == self.player then
			count = 7
		else
			count = 8
		end
	end
	local test = (blessing - delta) % count
	while not (ShamanPower:CanBuff(self.player, test) and ShamanPower:NeedsBuff(class, test, pname) or control) and test > 0 do
		test = (test - delta) % count
		if test == blessing then
			test = 0
			break
		end
	end
	SetNormalBlessings(self.player, class, pname, test)
end

function ShamanPower:AssignPlayerAsClass(pname, pclass, tclass)
	local greater, target, targetsorted, freepallies = {}, {}, {}, {}
	for pally, classes in pairs(ShamanPower_Assignments) do
		if AllShamans[pally] and classes[tclass] and classes[tclass] > 0 then
			target[classes[tclass]] = pally
			tinsert(targetsorted, classes[tclass])
		end
	end
	tsort(
		targetsorted,
		function(a, b)
			return a == 2 or a == 1 and b ~= 2
		end
	)
	for pally, info in pairs(AllShamans) do
		if ShamanPower_Assignments[pally] and ShamanPower_Assignments[pally][pclass] then
			local blessing = ShamanPower_Assignments[pally][pclass]
			greater[blessing] = pally
			if not target[blessing] then
				freepallies[pally] = info
			end
		else
			freepallies[pally] = info
		end
	end
	for _, blessing in pairs(targetsorted) do
		if greater[blessing] then
			local pally = greater[blessing]
			if ShamanPower_NormalAssignments[pally] and ShamanPower_NormalAssignments[pally][pclass] and ShamanPower_NormalAssignments[pally][pclass][pname] then
				SetNormalBlessings(pally, pclass, pname, 0)
			end
		else
			local maxname, maxrank, maxtalent = nil, 0, 0
			local targetpally = target[blessing]
			for pally, blessinginfo in pairs(freepallies) do
				local blessinginfo = blessinginfo[blessing]
				local rank, talent = 0, 0
				if blessinginfo then
					rank, talent = blessinginfo.rank, blessinginfo.talent
				end
				if rank > maxrank or (rank == maxrank and talent > maxtalent) or pally == targetpally then
					maxname = pally
					maxrank = rank
					maxtalent = talent
				end
			end
			if maxname then
				freepallies[maxname] = nil
				SetNormalBlessings(maxname, pclass, pname, blessing)
			end
		end
	end
end

function ShamanPower:CanBuff(name, totemIndex, element)
	-- For shamans, all totems are considered available
	-- The element parameter is optional - if not provided, assume the totem is available
	if not AllShamans[name] then
		return false
	end
	-- If we have element info, check the specific totem
	if element and AllShamans[name][element] then
		local totemData = AllShamans[name][element][totemIndex]
		if totemData and totemData.known then
			return true
		end
	end
	-- For simplified mode, just return true for all valid totem indexes
	return totemIndex and totemIndex > 0
end

function ShamanPower:CanBuffBlessing(spellId, gspellId, unitId, config)
	if unitId and spellId or gspellId then
		local normSpell, greatSpell
		if UnitLevel(unitId) >= 60 then
			if spellId > 0 then
				if not self.isWrath and spellId == 7 and GetUnitName(unitId, false) == self.player then
					normSpell = nil
				else
					normSpell = self.Spells[spellId]
				end
			else
				normSpell = nil
			end
			if gspellId > 0 then
				greatSpell = self.GSpells[gspellId]
			else
				greatSpell = nil
			end
			return normSpell, greatSpell
		end
		if spellId > 0 then
			for _, v in pairs(self.NormalBuffs[spellId]) do
				if IsSpellKnown(v[2]) or config then
					if UnitLevel(unitId) >= v[1] then
						local spellName = GetSpellInfo(v[2])
						local spellRank = GetSpellSubtext(v[2])
						if spellName and spellRank then
							if spellId == 3 or spellId == 4 then
								normSpell = spellName
							else
								normSpell = spellName .. "(" .. spellRank .. ")"
							end
						end
						if not self.isWrath and spellId == 7 and GetUnitName(unitId, false) == self.player then
							normSpell = nil
						end
						break
					else
						normSpell = nil
					end
				end
			end
		else
			normSpell = nil
		end
		if gspellId > 0 and UnitLevel(unitId) > 49 then
			for _, v in pairs(self.GreaterBuffs[gspellId]) do
				if IsSpellKnown(v[2]) then
					if UnitLevel(unitId) >= v[1] then
						local gspellName = GetSpellInfo(v[2])
						local gspellRank = GetSpellSubtext(v[2])
						if gspellName and gspellRank then
							if gspellId == 3 or gspellId == 4 then
								greatSpell = gspellName
							else
								greatSpell = gspellName .. "(" .. gspellRank .. ")"
							end
						end
						break
					else
						greatSpell = nil
					end
				end
			end
		else
			greatSpell = nil
		end
		return normSpell, greatSpell
	end
end

function ShamanPower:NeedsBuff(class, test, playerName)
	-- For Shamans, all totems are always valid options
	-- No filtering needed like Paladins have with blessings
	return true
end

function ShamanPower:NeedsBuff_OLD(class, test, playerName)
	-- OLD PALADIN LOGIC - kept for reference
	if (self.isWrath and test == 10) or (not self.isWrath and test == 9) or test == 0 then
		return true
	end
	if self.opt.SmartBuffs then
		-- no wisdom for warriors, rogues, and death knights
		if (class == 1 or class == 2 or (self.isWrath and class == 10)) and test == 1 then
			return false
		end
		-- no might for casters (and hunters in Classic)
		if (class == 3 or class == 7 or class == 8) and test == 2 then -- removed (self.isVanilla and class == 6) or
			return false
		end
	end
	if playerName then
		for pname, classes in pairs(ShamanPower_NormalAssignments) do
			if AllShamans[pname] and not pname == self.player then
				for _, tnames in pairs(classes) do
					for _, blessing_id in pairs(tnames) do
						if blessing_id == test then
							return false
						end
					end
				end
			end
		end
	end
	for name, skills in pairs(ShamanPower_Assignments) do
		if (AllShamans[name]) and ((skills[class]) and (skills[class] == test)) then
			return false
		end
	end
	return true
end

function ShamanPower:ScanTalents()
	local numTabs = GetNumTalentTabs()
	for t = 1, numTabs do
		for i = 1, GetNumTalents(t) do
			local _, textureID = GetTalentInfo(t, i)
			ShamanPower_Talents[textureID] = {t, i}
		end
	end
end

-- Safe default totems for each element (used when talent-required totems become unavailable)
-- These are totems that all shamans can use regardless of spec
ShamanPower.DefaultTotems = {
	[1] = 1,  -- Earth: Strength of Earth (index 1)
	[2] = 2,  -- Fire: Searing Totem (index 2) - index 1 is Totem of Wrath (Elemental talent)
	[3] = 1,  -- Water: Mana Spring (index 1) - index 3 is Mana Tide (Resto talent)
	[4] = 1,  -- Air: Windfury (index 1)
}

-- Validate totem assignments after respec - reset talent-gated totems if player no longer has them
function ShamanPower:ValidateAssignmentsForSpec()
	if not self.player then return end

	local assignments = ShamanPower_Assignments[self.player]
	if not assignments then return end

	local changed = false

	-- Check each element's assigned totem
	for element = 1, SHAMANPOWER_MAXELEMENTS do
		local totemIndex = assignments[element]
		if totemIndex and totemIndex > 0 then
			-- Get the spell ID for this totem
			local spellID = self.Totems[element] and self.Totems[element][totemIndex]
			if spellID then
				-- Check if this is a talent-required totem
				local talentInfo = self.TalentTotems[spellID]
				if talentInfo then
					-- This totem requires a talent - check if player knows it
					local spellName = GetSpellInfo(spellID)
					if not spellName or not IsSpellKnown(spellID) then
						-- Player doesn't have this spell anymore - reset to default
						local defaultTotem = self.DefaultTotems[element] or 1
						assignments[element] = defaultTotem
						changed = true

						local elementName = self.Elements[element] or "Unknown"
						local oldTotemName = self.TotemNames[element] and self.TotemNames[element][totemIndex] or "Unknown"
						local newTotemName = self.TotemNames[element] and self.TotemNames[element][defaultTotem] or "Unknown"
						self:Print("|cffff9900Respec detected:|r " .. elementName .. " totem reset from " .. oldTotemName .. " to " .. newTotemName)
					end
				end
			end
		end
	end

	return changed
end

-- Called when talents change (respec, dual spec switch, etc.)
function ShamanPower:OnTalentsChanged()
	if not isShaman then return end
	if InCombatLockdown() then
		-- Queue for after combat
		self.talentChangePending = true
		return
	end

	-- Rescan talents and spells
	self:ScanTalents()
	self:ScanSpells()

	-- Validate assignments - reset any talent-gated totems the player no longer has
	local assignmentsChanged = self:ValidateAssignmentsForSpec()

	-- Recreate cooldown bar to pick up new talent-based abilities (NS, Mana Tide, etc.)
	self:RecreateCooldownBar()

	-- Update keybindings for the new buttons
	self:SetupKeybindings()

	-- If assignments changed, update UI and macros
	if assignmentsChanged then
		self:UpdateLayout()
		self:UpdateSPMacros()
	end
end

function ShamanPower:ScanSpells()
	--self:Debug("[ScanSpells]")
	if isShaman then
		self:SyncAdd(self.player)
		AllShamans[self.player] = {}

		-- Mark all totems as available for each element (Earth=1, Fire=2, Water=3, Air=4)
		-- We don't check spell ranks - just show all totem types and let the shaman pick
		for element = 1, SHAMANPOWER_MAXELEMENTS do
			AllShamans[self.player][element] = {}
			local totemNames = self.TotemNames[element]
			if totemNames then
				for totemIndex, totemName in pairs(totemNames) do
					AllShamans[self.player][element][totemIndex] = {
						known = true,
						name = totemName
					}
				end
			end
		end

		-- Mark all weapon enchants as available
		AllShamans[self.player].WeaponEnchants = {}
		local enchantNames = {"Windfury Weapon", "Flametongue Weapon", "Frostbrand Weapon", "Rockbiter Weapon"}
		for enchantIndex, enchantName in ipairs(enchantNames) do
			AllShamans[self.player].WeaponEnchants[enchantIndex] = {
				known = true,
				name = enchantName
			}
		end

		-- Check if player has Earth Shield (Restoration talent)
		AllShamans[self.player].hasEarthShield = self:HasEarthShield()

		-- Compatibility placeholders (for code still expecting Paladin structures)
		AllShamans[self.player].AuraInfo = {}
		AllShamans[self.player].CooldownInfo = {}

		isShaman = true
		if not AllShamans[self.player].subgroup then
			AllShamans[self.player].subgroup = 1
		end
	end
	initialized = true
end

function ShamanPower:ScanCooldowns()
	--self:Debug("[ScanCooldowns]")
	-- Shamans don't have the same cooldown tracking as Paladins
	-- This function is a placeholder for future elemental totem cooldowns
	if not initialized or not isShaman then
		return
	end
end

function ShamanPower:ScanInventory()
	-- Shamans don't use symbols like Paladins
	-- This function is a placeholder
	if not initialized or not isShaman then
		return
	end
end

function ShamanPower:SendSelf(sender)
	if not initialized or GetNumGroupMembers() == 0 then
		return
	end
	if ShamanPower:CheckLeader(self.player) then
		self:SendMessage("ACLEADER " .. self.player)
	end
	if not isShaman then
		return
	end

	-- Simplified sync for totems - send available totems by element
	local s = ""
	local TotemInfo = AllShamans[self.player]
	if TotemInfo then
		-- Send which totems are available for each element
		for element = 1, SHAMANPOWER_MAXELEMENTS do
			local elementTotems = TotemInfo[element] or {}
			local available = ""
			for totemIndex = 1, SHAMANPOWER_MAXPERELEMENT do
				if elementTotems[totemIndex] and elementTotems[totemIndex].known then
					available = available .. totemIndex
				end
			end
			s = s .. (available ~= "" and available or "n") .. "|"
		end
	end
	s = s .. "@"

	-- Send current assignments
	if not ShamanPower_Assignments[self.player] then
		ShamanPower_Assignments[self.player] = {}
		for i = 1, SHAMANPOWER_MAXELEMENTS do
			ShamanPower_Assignments[self.player][i] = 0
		end
	end
	local BuffInfo = ShamanPower_Assignments[self.player]
	for i = 1, SHAMANPOWER_MAXELEMENTS do
		if not BuffInfo[i] or BuffInfo[i] == 0 then
			s = s .. "n"
		else
			s = s .. BuffInfo[i]
		end
	end

	-- Add Earth Shield info: #<hasES>:<target>
	local hasES = self:HasEarthShield() and "1" or "0"
	local esTarget = ShamanPower_EarthShieldAssignments[self.player] or ""
	s = s .. "#" .. hasES .. ":" .. esTarget

	-- Add freeassign flag: $<freeassign>
	local freeassign = (self.opt and self.opt.freeassign) and "1" or "0"
	s = s .. "$" .. freeassign

	local leader = self:CheckLeader(sender)
	if sender and not leader then
		self:SendMessage("SELF " .. s, "WHISPER", sender)
	else
		self:SendMessage("SELF " .. s)
	end

	-- Set freeassign option locally
	if AllShamans[self.player] then
		AllShamans[self.player].freeassign = self.opt and self.opt.freeassign or false
	end

end

function ShamanPower:SendMessage(msg, type, target)
	if GetNumGroupMembers() > 0 then
		if lastMsg ~= msg then
			lastMsg = msg
			local type
			if type == nil then
				if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and IsInInstance() then
					type = "INSTANCE_CHAT"
				else
					if IsInRaid() then
						type = "RAID"
					--elseif IsInGroup(LE_PARTY_CATEGORY_HOME) then
					else
						type = "PARTY"
					end
				end
			end
			if target then
				ChatThrottleLib:SendAddonMessage("NORMAL", self.commPrefix, msg, "WHISPER", target)
				--self:Debug("[Sent Message] prefix: " .. self.commPrefix .. " | msg: " .. msg .. " | type: WHISPER | target name: " .. target)
			else
				ChatThrottleLib:SendAddonMessage("NORMAL", self.commPrefix, msg, type)
				--self:Debug("[Sent Message] prefix: " .. self.commPrefix .. " | msg: " .. msg .. " | type: " .. type)
			end
		end
	end
end

function ShamanPower:SPELLS_CHANGED()
	--self:Debug("EVENT: SPELLS_CHANGED")
	if not initialized then
		ShamanPower:ScanSpells()
		return
	end
	ShamanPower:ScanSpells()
	ShamanPower:ScanCooldowns()
	ShamanPower:SendSelf()
	ShamanPower:UpdateLayout()
end

function ShamanPower:PLAYER_ENTERING_WORLD()
	--self:Debug("EVENT: PLAYER_ENTERING_WORLD")
	ShamanPower.realm = GetNormalizedRealmName() --GetRealmName()

	-- Validate assignments in case player respecced while logged out
	local assignmentsChanged = self:ValidateAssignmentsForSpec()
	if assignmentsChanged then
		self:UpdateSPMacros()
	end

	self:UpdateLayout()
	self:UpdateRoster()
	self:ReportChannels()

	-- Apply flyout click mode setting after layout is set up
	C_Timer.After(0.5, function()
		self:UpdateTotemFlyoutEnabled()
	end)

	-- Initialize raid cooldowns and show caller buttons if assigned
	C_Timer.After(1.0, function()
		self:InitRaidCooldowns()
		self:UpdateCallerButtons()
		self:RestoreCallerCooldowns()
	end)

	-- Initialize SPRange (totem range tracker for all classes)
	C_Timer.After(1.5, function()
		self:InitializeSPRange()
	end)

	-- Initialize Earth Shield Tracker (for tracking all ES in raid/party)
	C_Timer.After(2, function()
		self:InitializeESTracker()
	end)

	-- Restore popped-out trackers after bars are fully initialized
	C_Timer.After(2.5, function()
		self:RestorePoppedOutTrackers()
	end)

	-- Initialize Shield Charge Display (large on-screen numbers)
	C_Timer.After(3, function()
		self:CreateShieldChargeDisplays()
	end)

	-- Initialize Totem Plates (replace totem nameplates with icons)
	C_Timer.After(3.5, function()
		self:InitializeTotemPlates()
	end)

	-- Set up totem bar visibility updater (hide out of combat / hide when no totems)
	C_Timer.After(1, function()
		self:SetupTotemBarVisibilityUpdater()
	end)
end

function ShamanPower:ZONE_CHANGED()
	if IsInRaid() then
		self.zone = GetRealZoneText()
		self:UpdateLayout()
		self:UpdateRoster()
	end
end

function ShamanPower:ZONE_CHANGED_NEW_AREA()
	if IsInRaid() then
		self.zone = GetRealZoneText()
		self:UpdateLayout()
		self:UpdateRoster()
	end
end

function ShamanPower:CHAT_MSG_ADDON(event, prefix, message, distribution, source)
	local sender = Ambiguate(source, "none")
	if prefix == self.commPrefix then
	--self:Debug("[EVENT: CHAT_MSG_ADDON] prefix: "..prefix.." | message: "..message.." | distribution: "..distribution.." | sender: "..sender)
	end
	if prefix == self.commPrefix and (distribution == "PARTY" or distribution == "RAID" or distribution == "INSTANCE_CHAT" or distribution == "WHISPER") and sender then
		self:ParseMessage(sender, message)
	end
end

function ShamanPower:GROUP_JOINED(event)
	--self:Debug("[Event] GROUP_JOINED")
	AllShamans = {}
	SyncList = {}
	ShamanPower_NormalAssignments = {}
	self:ScanSpells()
	self:ScanCooldowns()
	self:ScanInventory()
	C_Timer.After(
		2.0,
		function()
			self:SendSelf()
			self:SendMessage("REQ")
			self:UpdateLayout()
			self:UpdateRoster()
		end
	)
	self.zone = GetRealZoneText()
end

function ShamanPower:GROUP_LEFT(event)
	--self:Debug("[Event] GROUP_LEFT")
	AllShamans = {}
	SyncList = {}
	ShamanPower_NormalAssignments = {}
	for pname in pairs(ShamanPower_Assignments) do
		local match = false
		if pname == self.player then
			match = true
		end
		for i = 1, GetNumGuildMembers() do
			local name = Ambiguate(GetGuildRosterInfo(i), "short")
			if pname == name then
				match = true
				break
			end
		end
		if match == false then
			ShamanPower_Assignments[pname] = nil
		end
	end

	-- Clear Earth Shield assignments when leaving group
	ShamanPower_EarthShieldAssignments = {}
	self.currentEarthShieldTarget = nil

	-- Clear Raid Cooldown assignments when leaving group
	ShamanPower_RaidCooldowns = {
		bloodlust = {
			primary = nil,
			backup1 = nil,
			backup2 = nil,
			caller = nil,
		},
		manatide = {},
	}

	self:ScanSpells()
	self:ScanCooldowns()
	self:ScanInventory()
	self:UpdateLayout()
	self:UpdateRoster()
	self:UpdateEarthShieldButton()
	self:UpdateCallerButtons()
end

function ShamanPower:UpdateAllShamans()
	if not initialized then
		return
	end

	local units
	if IsInRaid() then
		units = raid_units
	else
		units = party_units
	end

	local countAllShamans = 0
	for _ in pairs(AllShamans) do countAllShamans = countAllShamans + 1 end

	local found = 0
	for _, unitid in pairs(units) do
		if unitid and (not unitid:find("pet")) and UnitExists(unitid) then
			if AllShamans[GetUnitName(unitid, true)] then found = found + 1 end
		end
	end

	if found < countAllShamans then -- Zid: if AllShamans count is reduced do a fresh setup
		C_Timer.After(
			0.5,
			function()
				AllShamans = {}
				SyncList = {}
				self:ScanSpells()
				self:ScanCooldowns()
				self:ScanInventory()
				self:SendSelf()
				self:SendMessage("REQ")
				self:UpdateLayout()
				self:UpdateRoster()
			end
		)
	end
end

function ShamanPower:UNIT_SPELLCAST_SUCCEEDED(event, unitTarget, castGUID, spellID)
	-- Track Earth Shield casts (event-based tracking, no scanning!)
	self:OnEarthShieldCastSucceeded(unitTarget, castGUID, spellID)

	-- Trigger GCD swipe when player casts a totem
	if unitTarget == "player" then
		local spellName = GetSpellInfo(spellID)
		if spellName and spellName:find("Totem") then
			self:TriggerGCDSwipe()
			-- Dynamic Mode: immediately update assignment when totem is cast
			if self.opt.dynamicTotemMode then
				-- Small delay to let GetTotemInfo update
				C_Timer.After(0.01, function()
					self:UpdateDynamicTotemIcons()
				end)
			end
		end
	end

	if select(2, UnitClass(unitTarget)) == "SHAMAN" then
		for _, spells in pairs(self.Cooldowns) do
			for _, spell in pairs(spells) do
				if spellID == spell then
					C_Timer.After(
						2.0,
						function()
							ShamanPower:ScanCooldowns()
							if GetNumGroupMembers() > 0 then
								ShamanPower:SendSelf()
							end
						end
					)
				end
			end
		end
	end
end

function ShamanPower:PLAYER_ROLES_ASSIGNED(event)
	--self:Debug("[Event] PLAYER_ROLES_ASSIGNED")
	C_Timer.After(
		2.0,
		function()
			for name in pairs(leaders) do
				AC_Leader = false
				if name == self.player then
					self:SendSelf()
				end
			end
		end
	)
end

-- Earth Shield cast tracking (tracks who you cast ES on)
function ShamanPower:UNIT_SPELLCAST_SENT(event, unit, target, castGUID, spellID)
	if unit == "player" then
		self:OnEarthShieldCastSent(target, castGUID, spellID)
	end
end

-- Earth Shield aura tracking (updates charges when aura changes on tracked target)
function ShamanPower:UNIT_AURA(event, unit)
	-- Only process if we have a tracked ES target
	if self.esTrackedTargetGUID then
		self:OnEarthShieldAuraChange(unit)
	end

	-- Scan for shield buffs when player auras change (avoids polling)
	if unit == "player" then
		self:ScanPlayerShield()
	end
end

-- Scan player buffs for shield (called on UNIT_AURA, not every update tick)
function ShamanPower:ScanPlayerShield()
	local hasShield = false
	local shieldID = nil
	local shieldIcon = nil
	local shieldCharges = 0
	local shieldDuration = 0
	local shieldExpiration = 0
	local shieldBuffIndex = nil

	for i = 1, 40 do
		local name, icon, count, _, duration, expirationTime = UnitBuff("player", i)
		if not name then break end
		for j = 1, #self.ShieldSpells do
			local shieldData = self.ShieldSpells[j]
			if name == shieldData[2] then
				hasShield = true
				shieldID = shieldData[1]
				shieldIcon = icon
				shieldCharges = count or 0
				shieldDuration = duration or 0
				shieldExpiration = expirationTime or 0
				shieldBuffIndex = i
				break
			end
		end
		if hasShield then break end
	end

	-- Cache the result
	self.shieldCache = {
		hasShield = hasShield,
		shieldID = shieldID,
		shieldIcon = shieldIcon,
		shieldCharges = shieldCharges,
		shieldDuration = shieldDuration,
		shieldExpiration = shieldExpiration,
		buffIndex = shieldBuffIndex,
	}
end

function ShamanPower:ParseMessage(sender, msg)
	sender = self:RemoveRealmName(sender)

	if strfind(msg, "^PPLEADER") then
		local _, _, name = strfind(msg, "^PPLEADER (.*)")
		name = self:RemoveRealmName(name)
		if self:CheckLeader(name) then
			AC_Leader = true
		end
	end

	if (sender == self.player or sender == nil) or not initialized then return end

	--self:Debug("[Parse Message] sender: " .. sender .. " | msg: " .. msg)

	local leader = self:CheckLeader(sender)

	if msg == "REQ" then
		if IsInRaid() and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and IsInInstance() then
			self:SendSelf()
		else
			self:SendSelf(sender)
		end
	end

	if strfind(msg, "^SELF") then
		ShamanPower_NormalAssignments[sender] = {}
		ShamanPower_Assignments[sender] = {}
		AllShamans[sender] = {}
		self:SyncAdd(sender)

		-- Parse the shaman totem format: SELF <earth>|<fire>|<water>|<air>|@<assignments>#<hasES>:<esTarget>
		-- Example: "SELF 123456|1234567|123456|12345678|@2512#1:Tankname"
		local _, _, totemData, assignAndES = strfind(msg, "SELF ([^@]*)@(.*)")

		-- Split assignments from Earth Shield info
		local assign, esInfo
		if assignAndES then
			local hashPos = strfind(assignAndES, "#")
			if hashPos then
				assign = strsub(assignAndES, 1, hashPos - 1)
				esInfo = strsub(assignAndES, hashPos + 1)
			else
				assign = assignAndES
			end
		end

		if totemData then
			-- Split totemData by pipes to get each element's known totems
			local element = 0
			for elementTotems in string.gmatch(totemData .. "|", "([^|]*)|") do
				element = element + 1
				if element > SHAMANPOWER_MAXELEMENTS then break end

				if elementTotems and elementTotems ~= "" and elementTotems ~= "n" then
					AllShamans[sender][element] = {}
					-- Each character in elementTotems is a known totem index
					for i = 1, #elementTotems do
						local totemIndex = tonumber(strsub(elementTotems, i, i))
						if totemIndex then
							AllShamans[sender][element][totemIndex] = { known = true }
						end
					end
				end
			end
		end

		if assign then
			for i = 1, SHAMANPOWER_MAXELEMENTS do
				local tmp = strsub(assign, i, i)
				if tmp == "n" or tmp == "" then
					tmp = 0
				end
				ShamanPower_Assignments[sender][i] = tmp + 0
			end
		end

		-- Parse Earth Shield info and freeassign: <hasES>:<target>$<freeassign>
		if esInfo then
			-- Split off freeassign flag if present
			local esData, freeassignFlag
			local dollarPos = strfind(esInfo, "%$")
			if dollarPos then
				esData = strsub(esInfo, 1, dollarPos - 1)
				freeassignFlag = strsub(esInfo, dollarPos + 1)
			else
				esData = esInfo
			end

			-- Parse Earth Shield
			local _, _, hasES, esTarget = strfind(esData, "([01]):?(.*)")
			if hasES == "1" then
				AllShamans[sender].hasEarthShield = true
				if esTarget and esTarget ~= "" then
					ShamanPower_EarthShieldAssignments[sender] = esTarget
				end
			else
				AllShamans[sender].hasEarthShield = false
			end

			-- Parse freeassign flag
			if freeassignFlag == "1" then
				AllShamans[sender].freeassign = true
			else
				AllShamans[sender].freeassign = false
			end
		end
	end

	if strfind(msg, "^ASSIGN") then
		local _, _, name, class, skill = strfind(msg, "^ASSIGN (.*) (.*) (.*)")
		name = self:RemoveRealmName(name)
		if name ~= sender and not (leader or self.opt.freeassign) then
			return false
		end
		if not ShamanPower_Assignments[name] then
			ShamanPower_Assignments[name] = {}
		end
		class = class + 0
		skill = skill + 0
		ShamanPower_Assignments[name][class] = skill
	end

	-- Handle TWIST message for totem twisting assignment
	if strfind(msg, "^TWIST") then
		local _, _, name, enabled = strfind(msg, "^TWIST (.*) (.*)")
		name = self:RemoveRealmName(name)
		if name ~= sender and not (leader or self.opt.freeassign) then
			return false
		end
		local twistEnabled = (enabled == "1")
		ShamanPower_TwistAssignments[name] = twistEnabled

		-- If this is for us, update our local setting
		if name == self.player then
			self.opt.enableTotemTwisting = twistEnabled
			self:UpdateMiniTotemBar()
			self:UpdateSPMacros()
			-- Refresh Options panel if it's open
			LibStub("AceConfigRegistry-3.0"):NotifyChange("ShamanPower")
			if twistEnabled then
				self:SetupTwistTimer()
			else
				self:HideTwistTimer()
			end
		end

		-- Update the UI
		self:UpdateRoster()
	end

	if strfind(msg, "^PASSIGN") then
		local _, _, name, assign = strfind(msg, "^PASSIGN (.*)@([0-9n]*)")
		name = self:RemoveRealmName(name)
		if name ~= sender and not (leader or self.opt.freeassign) then
			return false
		end
		if not ShamanPower_Assignments[name] then
			ShamanPower_Assignments[name] = {}
		end
		if assign then
			for i = 1, SHAMANPOWER_MAXCLASSES do
				local tmp = strsub(assign, i, i)
				if tmp == "n" or tmp == "" then
					tmp = 0
				end
				ShamanPower_Assignments[name][i] = tmp + 0
			end
		end
	end

	if strfind(msg, "^NASSIGN") then
		for pname, class, tname, skill in string.gmatch(strsub(msg, 9), "([^@]*) ([^@]*) ([^@]*) ([^@]*)") do
			local name = self:RemoveRealmName(pname)
			if name ~= sender and not (leader or self.opt.freeassign) then
				return
			end
			if not ShamanPower_NormalAssignments[name] then
				ShamanPower_NormalAssignments[name] = {}
			end
			class = class + 0
			if not ShamanPower_NormalAssignments[name][class] then
				ShamanPower_NormalAssignments[name][class] = {}
			end
			skill = skill + 0
			if skill == 0 then
				skill = nil
			end
			ShamanPower_NormalAssignments[name][class][tname] = skill
		end
	end

	if strfind(msg, "^MASSIGN") then
		local _, _, name, skill = strfind(msg, "^MASSIGN (.*) (.*)")
		name = self:RemoveRealmName(name)
		if name ~= sender and not (leader or self.opt.freeassign) then
			return false
		end
		if not ShamanPower_Assignments[name] then
			ShamanPower_Assignments[name] = {}
		end
		skill = skill + 0
		for i = 1, SHAMANPOWER_MAXCLASSES do
			ShamanPower_Assignments[name][i] = skill
		end
	end

	if strfind(msg, "SYMCOUNT") then
		local _, _, symcount = strfind(msg, "SYMCOUNT ([0-9]*)")
		if AllShamans[sender] then
			if symcount == nil or symcount == "0" then
				AllShamans[sender].symbols = 0
			else
				AllShamans[sender].symbols = symcount
			end
		end
	end

	if strfind(msg, "COOLDOWNS") then
		local _, duration1, remaining1, duration2, remaining2 = strsplit(":", msg)
		if AllShamans[sender] then
			if not AllShamans[sender].CooldownInfo then
				AllShamans[sender].CooldownInfo = {}
			end
			if not AllShamans[sender].CooldownInfo[1] and remaining1 ~= "n" then
				AllShamans[sender].CooldownInfo[1] = {}
				duration1 = tonumber(duration1)
				remaining1 = tonumber(remaining1)
				AllShamans[sender].CooldownInfo[1].start = GetTime() - (duration1 - remaining1)
				AllShamans[sender].CooldownInfo[1].duration = duration1
			end
			if not AllShamans[sender].CooldownInfo[2] and remaining2 ~= "n" then
				AllShamans[sender].CooldownInfo[2] = {}
				duration2 = tonumber(duration2)
				remaining2 = tonumber(remaining2)
				AllShamans[sender].CooldownInfo[2].start = GetTime() - (duration2 - remaining2)
				AllShamans[sender].CooldownInfo[2].duration = duration2
			end
		end
	end

	if strfind(msg, "^CLEAR") then
		if leader then
			self:ClearAssignments(sender, strfind(msg, "SKIP"))
		elseif self.opt.freeassign then
			self:ClearAssignments(self.player, strfind(msg, "SKIP"))
		end
	end

	if strfind(msg, "FREEASSIGN YES") and AllShamans[sender] then
		AllShamans[sender].freeassign = true
	end

	if strfind(msg, "FREEASSIGN NO") and AllShamans[sender] then
		AllShamans[sender].freeassign = false
	end

	if strfind(msg, "^ASELF") then
		ShamanPower_AuraAssignments[sender] = 0
		if AllShamans[sender] then
			if not AllShamans[sender].AuraInfo then
				AllShamans[sender].AuraInfo = {}
			end
			local _, _, numbers, assign = strfind(msg, "ASELF ([0-9a-fn]*)@([0-9n]*)")
			for i = 1, SHAMANPOWER_MAXAURAS do
				local rank = strsub(numbers, (i - 1) * 2 + 1, (i - 1) * 2 + 1)
				local talent = strsub(numbers, (i - 1) * 2 + 2, (i - 1) * 2 + 2)
				if rank ~= "n" then
					AllShamans[sender].AuraInfo[i] = {}
					AllShamans[sender].AuraInfo[i].rank = tonumber(rank, 16)
					AllShamans[sender].AuraInfo[i].talent = tonumber(talent)
				end
			end
			if assign then
				if assign == "n" or assign == "" then
					assign = 0
				end
				ShamanPower_AuraAssignments[sender] = assign + 0
			end
		end
	end

	if strfind(msg, "^AASSIGN") then
		local _, _, name, aura = strfind(msg, "^AASSIGN (.*) (.*)")
		name = self:RemoveRealmName(name)
		if name ~= sender and not (leader or self.opt.freeassign) then
			return false
		end
		if not ShamanPower_AuraAssignments[name] then
			ShamanPower_AuraAssignments[name] = {}
		end
		aura = aura + 0
		ShamanPower_AuraAssignments[name] = aura
	end

	-- Earth Shield assignment sync
	if strfind(msg, "^ESASSIGN") then
		local _, _, name, target = strfind(msg, "^ESASSIGN (.*) (.*)")
		name = self:RemoveRealmName(name)
		if name ~= sender and not (leader or self.opt.freeassign) then
			return false
		end
		if target == "NONE" then
			ShamanPower_EarthShieldAssignments[name] = nil
		else
			target = self:RemoveRealmName(target)
			ShamanPower_EarthShieldAssignments[name] = target
		end
		-- Update UI if it's our own assignment
		if name == self.player then
			self:UpdateMiniTotemBar()
			self:UpdateEarthShieldMacroButton()
		end
	end

	-- Raid cooldown coordination messages
	if strfind(msg, "^RCSYNC") or strfind(msg, "^BLCALL") or strfind(msg, "^MTCALL") or strfind(msg, "^MTSYNC") then
		self:HandleRaidCooldownMessage(nil, msg, sender)
	end

	-- Windfury buff status from other players (for SPRange)
	if strfind(msg, "^WFBUFF") then
		local _, _, status = strfind(msg, "^WFBUFF ([01])")
		if status then
			if not self.WindfuryRangeData then
				self.WindfuryRangeData = {}
			end
			self.WindfuryRangeData[sender] = {
				hasWindfury = (status == "1"),
				timestamp = GetTime()
			}
		end
	end

	self:UpdateLayout()
end

function ShamanPower:CanControl(name)
	if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and IsInInstance() then
		return (name == self.player) or (AllShamans[name] and (AllShamans[name].freeassign == true))
	else
		if UnitIsGroupLeader(self.player) or UnitIsGroupAssistant(self.player) then
			return true
		else
			return (name == self.player) or (AllShamans[name] and (AllShamans[name].freeassign == true))
		end
	end
end

function ShamanPower:CheckLeader(nick)
	if leaders[nick] == true then
		return true
	else
		return false
	end
end

function ShamanPower:CheckMainTanks(nick)
	return raidmaintanks[nick]
end

function ShamanPower:CheckMainAssists(nick)
	return raidmainassists[nick]
end

function ShamanPower:ClearAssignments(sender, skipAuras)
	local leader = self:CheckLeader(sender)
	for name in pairs(ShamanPower_Assignments) do
		if leader or name == self.player then
			for i = 1, SHAMANPOWER_MAXCLASSES do
				ShamanPower_Assignments[name][i] = 0
			end
		end
	end
	for pname, classes in pairs(ShamanPower_NormalAssignments) do
		if leader or pname == self.player then
			for _, tnames in pairs(classes) do
				for tname in pairs(tnames) do
					tnames[tname] = nil
				end
			end
		end
	end
	if skipAuras then return end
	for name in pairs(ShamanPower_AuraAssignments) do
		if leader or name == self.player then
			ShamanPower_AuraAssignments[name] = 0
		end
	end
end

function ShamanPower:SyncClear()
	SyncList = {}
end

function ShamanPower:SyncAdd(name)
	local chk = 0
	for _, v in ipairs(SyncList) do
		if v == name then
			chk = 1
		end
	end
	if chk == 0 then
		tinsert(SyncList, name)
		tsort(
			SyncList,
			function(a, b)
				return a < b
			end
		)
	end
	-- Ensure assignment tables have entries for this player
	if not ShamanPower_Assignments then ShamanPower_Assignments = {} end
	if not ShamanPower_NormalAssignments then ShamanPower_NormalAssignments = {} end
	if not ShamanPower_AuraAssignments then ShamanPower_AuraAssignments = {} end
	if not ShamanPower_Assignments[name] then
		ShamanPower_Assignments[name] = {}
	end
	if not ShamanPower_NormalAssignments[name] then
		ShamanPower_NormalAssignments[name] = {}
	end
	if not ShamanPower_AuraAssignments[name] then
		ShamanPower_AuraAssignments[name] = 0
	end
end

function ShamanPower:FormatTime(time)
	if not time or time < 0 or time == 9999 then
		return ""
	end
	local mins = floor(time / 60)
	local secs = time - (mins * 60)
	return format("%d:%02d", mins, secs)
end

function ShamanPower:AddRealmName(unitID)
	local name, realm = strsplit("%-", unitID)
	realm = realm or self.realm

	return name .. "-" .. realm
end

function ShamanPower:RemoveRealmName(unitID)
	local name, realm = strsplit("%-", unitID)
	if realm and realm ~= self.realm then
		return unitID
	else
		return name
	end
end

function ShamanPower:GetClassID(class)
	for id, name in pairs(self.ClassID) do
		if (name == class) then
			return id
		end
	end
	return -1
end

function ShamanPower:UpdateRoster()
	--self:Debug("UpdateRoster()")
	-- Skip if not in a group (no roster to update)
	if GetNumGroupMembers() == 0 then
		return
	end
	local units
	for i = 1, SHAMANPOWER_MAXCLASSES do
		classlist[i] = 0
		twipe(classes[i])  -- Reuse existing tables instead of creating new ones
		classmaintanks[i] = false
	end
	if IsInRaid() then
		units = raid_units
	else
		units = party_units
	end
	twipe(roster)
	twipe(leaders)
	unitTableIndex = 0  -- Reset for this pass
	for _, unitid in pairs(units) do
		if unitid and UnitExists(unitid) then
			unitTableIndex = unitTableIndex + 1
			local tmp = unitTables[unitTableIndex]
			if not tmp then
				tmp = {}
				unitTables[unitTableIndex] = tmp
			else
				twipe(tmp)  -- Clear old data
			end
			tmp.unitid = unitid
			tmp.name = GetUnitName(unitid, true)
			local isPet = tmp.unitid:find("pet")
			local ShowPets = self.opt.ShowPets
			local pclass = (UnitClassBase(unitid))
			if ShowPets or (not isPet) then
				tmp.class = pclass
				if isPet then
					if not ShamanPower.petsShareBaseClass then
						tmp.class = "PET"
					end
					local unitType, _, _, _, _, npcId = strsplit("-", UnitGUID(unitid))
					-- 510: Water Elemental, 19668: Shadowfiend, 1863: Succubus, 26125: Risen Ghoul, 185317: Incubus
					if  (unitType ~= "Pet") and (npcId == "510" or npcId == "19668" or npcId == "1863" or npcId == "26125" or npcId == "185317") then
						tmp.class = false
					else
						local i = 1
						local isPhased = false
						local buffSpellId = select(10, UnitBuff(unitid, i))
						while buffSpellId do
							if (buffSpellId == 4511) then -- 4511: Phase Shift (Imp)
								tmp.class = false
								break
							end
							i = i + 1
							buffSpellId = select(10, UnitBuff(unitid, i))
						end
					end
				end
			end
			if IsInRaid() and (not isPet) then
				local n = select(3, unitid:find("(%d+)"))
				tmp.name, tmp.rank, tmp.subgroup = GetRaidRosterInfo(n)
				tmp.zone = select(7, GetRaidRosterInfo(n))
				
				if self.opt.hideHighGroups then
					local maxPlayerCount = (select(5, GetInstanceInfo()))
					if maxPlayerCount and (maxPlayerCount > 5) then
						local numVisibleSubgroups = math.ceil(maxPlayerCount/5)
						if not (tmp.subgroup <= numVisibleSubgroups) then
							tmp.class = nil
						end
					end
				end
				
				local raidtank = select(10, GetRaidRosterInfo(n))
				tmp.tank = ((raidtank == "MAINTANK") or (self.opt.mainAssist and (raidtank == "MAINASSIST")))
				
				local class = self:GetClassID(pclass)
				-- Warriors and Death Knights
				if (class == 1 or (self.isWrath and class == 10)) then
					if (raidmaintanks[tmp.name] == true) then
						if ShamanPower_NormalAssignments[self.player] and ShamanPower_NormalAssignments[self.player][class] and ShamanPower_NormalAssignments[self.player][class][tmp.name] == self.opt.mainTankSpellsW then
							if ShamanPower_Assignments[self.player] and ShamanPower_Assignments[self.player][class] == self.opt.mainTankGSpellsW and (raidtank == "MAINTANK" and self.opt.mainTank) then
							else
								SetNormalBlessings(self.player, class, tmp.name, 0)
								raidmaintanks[tmp.name] = false
							end
						end
					end
					if (raidmainassists[tmp.name] == true) then
						if ShamanPower_NormalAssignments[self.player] and ShamanPower_NormalAssignments[self.player][class] and ShamanPower_NormalAssignments[self.player][class][tmp.name] == self.opt.mainAssistSpellsW then
							if ShamanPower_Assignments[self.player] and ShamanPower_Assignments[self.player][class] == self.opt.mainAssistGSpellsW and (raidtank == "MAINASSIST" and self.opt.mainAssist) then
							else
								SetNormalBlessings(self.player, class, tmp.name, 0)
								raidmainassists[tmp.name] = false
							end
						end
					end
					if (raidtank == "MAINTANK" and self.opt.mainTank) then
						if (ShamanPower_Assignments[self.player] and ShamanPower_Assignments[self.player][class] == self.opt.mainTankGSpellsW and (raidmaintanks[tmp.name] == false or raidmaintanks[tmp.name] == nil)) or (ShamanPower_NormalAssignments[self.player] and ShamanPower_NormalAssignments[self.player][class] and ShamanPower_NormalAssignments[self.player][class][tmp.name] ~= self.opt.mainTankSpellsW and raidmaintanks[tmp.name] == true) then
							SetNormalBlessings(self.player, class, tmp.name, self.opt.mainTankSpellsW)
							raidmaintanks[tmp.name] = true
						end
					end
					if (raidtank == "MAINASSIST" and self.opt.mainAssist) then
						if (ShamanPower_Assignments[self.player] and ShamanPower_Assignments[self.player][class] == self.opt.mainAssistGSpellsW and (raidmainassists[tmp.name] == false or raidmainassists[tmp.name] == nil)) or (ShamanPower_NormalAssignments[self.player] and ShamanPower_NormalAssignments[self.player][class] and ShamanPower_NormalAssignments[self.player][class][tmp.name] ~= self.opt.mainAssistSpellsW and raidmainassists[tmp.name] == true) then
							SetNormalBlessings(self.player, class, tmp.name, self.opt.mainAssistSpellsW)
							raidmainassists[tmp.name] = true
						end
					end
				end
				-- Druids and Paladins
				if (class == 4 or class == 5) then
					if (raidmaintanks[tmp.name] == true) then
						if ShamanPower_NormalAssignments[self.player] and ShamanPower_NormalAssignments[self.player][class] and ShamanPower_NormalAssignments[self.player][class][tmp.name] == self.opt.mainTankSpellsDP then
							if ShamanPower_Assignments[self.player] and ShamanPower_Assignments[self.player][class] == self.opt.mainTankGSpellsDP and (raidtank == "MAINTANK" and self.opt.mainTank) then
							else
								SetNormalBlessings(self.player, class, tmp.name, 0)
								raidmaintanks[tmp.name] = false
							end
						end
					end
					if (raidmainassists[tmp.name] == true) then
						if ShamanPower_NormalAssignments[self.player] and ShamanPower_NormalAssignments[self.player][class] and ShamanPower_NormalAssignments[self.player][class][tmp.name] == self.opt.mainAssistSpellsDP then
							if ShamanPower_Assignments[self.player] and ShamanPower_Assignments[self.player][class] == self.opt.mainAssistGSpellsDP and (raidtank == "MAINASSIST" and self.opt.mainAssist) then
							else
								SetNormalBlessings(self.player, class, tmp.name, 0)
								raidmainassists[tmp.name] = false
							end
						end
					end
					if (raidtank == "MAINTANK" and self.opt.mainTank) then
						if (ShamanPower_Assignments[self.player] and ShamanPower_Assignments[self.player][class] == self.opt.mainTankGSpellsDP and (raidmaintanks[tmp.name] == false or raidmaintanks[tmp.name] == nil)) or (ShamanPower_NormalAssignments[self.player] and ShamanPower_NormalAssignments[self.player][class] and ShamanPower_NormalAssignments[self.player][class][tmp.name] ~= self.opt.mainTankSpellsDP and raidmaintanks[tmp.name] == true) then
							if (self.player == tmp.name and self.opt.mainTankSpellsDP == 7) then
								SetNormalBlessings(self.player, class, tmp.name, 0)
							else
								SetNormalBlessings(self.player, class, tmp.name, self.opt.mainTankSpellsDP)
							end
							raidmaintanks[tmp.name] = true
						end
					end
					if (raidtank == "MAINASSIST" and self.opt.mainAssist) then
						if (ShamanPower_Assignments[self.player] and ShamanPower_Assignments[self.player][class] == self.opt.mainAssistGSpellsDP and (raidmainassists[tmp.name] == false or raidmainassists[tmp.name] == nil)) or (ShamanPower_NormalAssignments[self.player] and ShamanPower_NormalAssignments[self.player][class] and ShamanPower_NormalAssignments[self.player][class][tmp.name] ~= self.opt.mainAssistSpellsDP and raidmainassists[tmp.name] == true) then
							if (self.player == tmp.name and self.opt.mainTankSpellsDP == 7) then
								SetNormalBlessings(self.player, class, tmp.name, 0)
							else
								SetNormalBlessings(self.player, class, tmp.name, self.opt.mainAssistSpellsDP)
							end
							raidmainassists[tmp.name] = true
						end
					end
				end

				if raidtank == "MAINTANK" then
					classmaintanks[class] = true
				end
			else
				tmp.rank = UnitIsGroupLeader(unitid) and 2 or 0
				tmp.subgroup = 1
			end
			if tmp.class == "SHAMAN" and (not isPet) then
				if AllShamans[tmp.name] then
					AllShamans[tmp.name].subgroup = tmp.subgroup
				end
			end
			if tmp.name and (tmp.rank > 0) then
				if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and IsInInstance() then
				else
					leaders[tmp.name] = true
					if tmp.name == self.player and AC_Leader == false then
						AC_Leader = true
					end
				end
			end
			if tmp.class and tmp.subgroup then
				tinsert(roster, tmp)
				for i = 1, SHAMANPOWER_MAXCLASSES do
					if tmp.class == self.ClassID[i] then
						tmp.visible = false
						tmp.hasbuff = false
						tmp.specialbuff = false
						tmp.dead = false
						classlist[i] = classlist[i] + 1
						tinsert(classes[i], tmp)
					end
				end
			end
		end
	end
	self:UpdateLayout()

	-- Update SPRange visibility based on group composition
	self:UpdateSPRangeVisibility()

	-- Update Earth Shield flyout when group composition changes
	if not InCombatLockdown() then
		self:CreateEarthShieldFlyout()
	end
end

function ShamanPower:ScanClass(classID)
	for _, unit in pairs(classes[classID]) do
		if unit.unitid then
			local spellID, gspellID = self:GetSpellID(classID, unit.name)
			local spell = self.Spells[spellID]
			local spell2 = self.GSpells[spellID]
			local gspell = self.GSpells[gspellID]
			local isMainTank = false
			if IsInRaid() then
				local n = select(3, unit.unitid:find("(%d+)"))
				if unit.zone then
					unit.zone = select(7, GetRaidRosterInfo(n))
				end
			end
			unit.inrange = IsSpellInRange(spell, unit.unitid) == 1
			unit.visible = UnitIsVisible(unit.unitid) and UnitIsConnected(unit.unitid)
			unit.dead = UnitIsDeadOrGhost(unit.unitid)
			unit.hasbuff = self:IsBuffActive(spell, spell2, unit.unitid)
			unit.specialbuff = (spellID ~= gspellID)
		end
	end
end

function ShamanPower:CreateLayout()
	--self:Debug("CreateLayout()")
	self.Header = _G["ShamanPowerFrame"]
	self.autoButton = CreateFrame("Button", "ShamanPowerAuto", self.Header, "SecureHandlerShowHideTemplate, SecureHandlerEnterLeaveTemplate, SecureHandlerStateTemplate, SecureActionButtonTemplate, ShamanPowerAutoButtonTemplate")
	self.autoButton:RegisterForClicks("LeftButtonDown", "RightButtonDown")

	-- ALT+drag to move the frame
	self.autoButton:RegisterForDrag("LeftButton")
	self.autoButton:HookScript("OnDragStart", function(btn)
		if IsAltKeyDown() and not InCombatLockdown() then
			local frame = ShamanPowerFrame
			frame:SetMovable(true)
			frame:StartMoving()
			ShamanPower.isDragging = true
		end
	end)
	self.autoButton:HookScript("OnDragStop", function(btn)
		if ShamanPower.isDragging then
			local frame = ShamanPowerFrame
			frame:StopMovingOrSizing()
			-- Save position to profile (ensures display table exists for proper persistence)
			ShamanPower:SaveFramePosition(frame)
			ShamanPower.isDragging = false
		end
	end)
	self.rfButton = CreateFrame("Button", "ShamanPowerRF", self.Header, "ShamanPowerRFButtonTemplate")
	self.rfButton:RegisterForClicks("LeftButtonDown", "RightButtonDown")
	self.auraButton = CreateFrame("Button", "ShamanPowerAura", self.Header, "ShamanPowerAuraButtonTemplate")
	self.auraButton:RegisterForClicks("LeftButtonDown")
	self.classButtons = {}
	self.playerButtons = {}
	self.autoButton:Execute([[childs = table.new()]])
	for cbNum = 1, SHAMANPOWER_MAXCLASSES do
		-- create class buttons
		local cButton = CreateFrame("Button", "ShamanPowerC" .. cbNum, self.Header, "SecureHandlerShowHideTemplate, SecureHandlerEnterLeaveTemplate, SecureHandlerStateTemplate, SecureActionButtonTemplate, ShamanPowerButtonTemplate")
		SecureHandlerSetFrameRef(self.autoButton, "child", cButton)
		SecureHandlerExecute(self.autoButton, [[
			local child = self:GetFrameRef("child")
			childs[#childs+1] = child;
		]])
		cButton:Execute([[others = table.new()]])
		cButton:Execute([[childs = table.new()]])
		cButton:SetAttribute("_onenter", [[
			for _, other in ipairs(others) do
					other:SetAttribute("state-inactive", self)
			end
			local leadChild;
			for _, child in ipairs(childs) do
					if child:GetAttribute("Display") == 1 then
							child:Show()
							if (leadChild) then
									leadChild:AddToAutoHide(child)
							else
									leadChild = child
									leadChild:RegisterAutoHide(2)
							end
					end
			end
			if (leadChild) then
					leadChild:AddToAutoHide(self)
			end
		]])
		cButton:SetAttribute("_onstate-inactive", [[
			childs[1]:Hide()
		]])
		cButton:RegisterForClicks("LeftButtonDown", "RightButtonDown")
		cButton:EnableMouseWheel(1)
		self.classButtons[cbNum] = cButton
		self.playerButtons[cbNum] = {}
		local pButtons = self.playerButtons[cbNum]
		local leadChild
		for pbNum = 1, SHAMANPOWER_MAXPERCLASS do
			local pButton = CreateFrame("Button", "ShamanPowerC" .. cbNum .. "P" .. pbNum, UIParent, "SecureHandlerShowHideTemplate, SecureHandlerEnterLeaveTemplate, SecureActionButtonTemplate, ShamanPowerPopupTemplate")
			pButton:SetParent(cButton)
			pButton:SetFrameStrata("DIALOG")
			SecureHandlerSetFrameRef(cButton, "child", pButton)
			SecureHandlerExecute(cButton, [[
				local child = self:GetFrameRef("child")
				childs[#childs+1] = child;
			]])
			if pbNum == 1 then
				pButton:Execute([[siblings = table.new()]])
				pButton:SetAttribute("_onhide", [[
					for _, sibling in ipairs(siblings) do
						sibling:Hide()
					end
				]])
				leadChild = pButton
			else
				SecureHandlerSetFrameRef(leadChild, "sibling", pButton)
				SecureHandlerExecute(leadChild, [[
					local sibling = self:GetFrameRef("sibling")
					siblings[#siblings+1] = sibling;
				]])
			end
			pButton:RegisterForClicks("LeftButtonDown", "RightButtonDown")
			pButton:EnableMouseWheel(1)
			pButton:Hide()
			pButtons[pbNum] = pButton
		end -- by pbNum
	end -- by classIndex
	for cbNum = 1, SHAMANPOWER_MAXCLASSES do
		local cButton = self.classButtons[cbNum]
		for cbOther = 1, SHAMANPOWER_MAXCLASSES do
			if (cbOther ~= cbNum) then
				local oButton = self.classButtons[cbOther]
				SecureHandlerSetFrameRef(cButton, "other", oButton)
				SecureHandlerExecute(cButton, [[
					local other = self:GetFrameRef("other")
					others[#others+1] = other;
				]])
			end
		end
	end
	self:UpdateLayout()
end

function ShamanPower:CountClasses()
	local val = 0
	if not classes then
		return 0
	end
	for i = 1, SHAMANPOWER_MAXCLASSES do
		if classlist[i] and classlist[i] > 0 then
			val = val + 1
		end
	end
	return val
end

function ShamanPower:UpdateLayout()
	--self:Debug("UpdateLayout()")
	if InCombatLockdown() then return end

	ShamanPowerFrame:SetScale(self.opt.buffscale)
	-- Update cooldown bar scale to compensate for parent scale change
	self:UpdateCooldownBarScale()
	local x = self.opt.display.buttonWidth
	local y = self.opt.display.buttonHeight
	local point = "TOPLEFT"
	local pointOpposite = "BOTTOMLEFT"
	local layout = self.Layouts[self.opt.layout]
	if not layout then
		-- Fallback to Vertical (Right) if the configured layout doesn't exist
		self.opt.layout = "Vertical"
		layout = self.Layouts["Vertical"]
	end
	for cbNum = 1, SHAMANPOWER_MAXCLASSES do
		local cx = layout.c[cbNum].x
		local cy = layout.c[cbNum].y
		local cButton = self.classButtons[cbNum]
		self:SetButton("ShamanPowerC" .. cbNum)
		cButton.x = cx * x
		cButton.y = cy * y
		cButton:ClearAllPoints()
		cButton:SetPoint(point, self.Header, "CENTER", cButton.x, cButton.y)
		local pButtons = self.playerButtons[cbNum]
		for pbNum = 1, SHAMANPOWER_MAXPERCLASS do
			local px = layout.c[cbNum].p[pbNum].x
			local py = layout.c[cbNum].p[pbNum].y
			local pButton = pButtons[pbNum]
			self:SetPButton("ShamanPowerC" .. cbNum .. "P" .. pbNum)
			pButton:ClearAllPoints()
			pButton:SetPoint(point, self.Header, "CENTER", cButton.x + px * x, cButton.y + py * y)
		end
	end
	local ox = layout.ab.x * x
	local oy = layout.ab.y * y
	local autob = self.autoButton
	autob:ClearAllPoints()
	autob:SetPoint(point, self.Header, "CENTER", ox, oy)
	autob:SetAttribute("type", "spell")
	-- Show mini totem bar only if:
	-- 1. Is a shaman, addon enabled, autobutton option on
	-- 2. In party/raid or solo (based on settings)
	-- 3. TotemTimers sync is NOT enabled (if TT sync is on, user uses TT bar instead)
	local showMiniBar = isShaman and self.opt.enabled and self.opt.autobuff.autobutton
		and ((GetNumGroupMembers() == 0 and self.opt.ShowWhenSolo) or (GetNumGroupMembers() > 0 and self.opt.ShowInParty))
		and not self:IsTotemTimersSyncEnabled()
	if showMiniBar then
		autob:Show()
		-- Update the mini totem bar icons and spells
		self:UpdateMiniTotemBar()
		self:UpdateDropAllButton()
		-- Note: UpdateSPMacros() is called only when assignments change, not on every layout update
	else
		autob:Hide()
	end
	local rfb = self.rfButton
	if self.opt.autobuff.autobutton then
		ox = layout.rf.x * x
		oy = layout.rf.y * y
		rfb:ClearAllPoints()
		rfb:SetPoint(point, self.Header, "CENTER", ox, oy)
	else
		ox = layout.rfd.x * x
		oy = layout.rfd.y * y
		rfb:ClearAllPoints()
		rfb:SetPoint(point, self.Header, "CENTER", ox, oy)
	end
	rfb:SetAttribute("type1", "spell")
	rfb:SetAttribute("unit1", "player")
	self:RFAssign(self.opt.rf)
	rfb:SetAttribute("type2", "spell")
	rfb:SetAttribute("unit2", "player")
	self:SealAssign(self.opt.seal)
	if isShaman and self.opt.enabled and self.opt.rfbuff and ((GetNumGroupMembers() == 0 and self.opt.ShowWhenSolo) or (GetNumGroupMembers() > 0 and self.opt.ShowInParty)) then
		rfb:Show()
	else
		rfb:Hide()
	end
	local auraBtn = self.auraButton
	if (not self.opt.autobuff.autobutton and self.opt.rfbuff) or (self.opt.autobuff.autobutton and not self.opt.rfbuff) then
		ox = layout.aud1.x * x
		oy = layout.aud1.y * y
		auraBtn:ClearAllPoints()
		auraBtn:SetPoint(point, self.Header, "CENTER", ox, oy)
	elseif not self.opt.autobuff.autobutton and not self.opt.rfbuff then
		ox = layout.aud2.x * x
		oy = layout.aud2.y * y
		auraBtn:ClearAllPoints()
		auraBtn:SetPoint(point, self.Header, "CENTER", ox, oy)
	else
		ox = layout.au.x * x
		oy = layout.au.y * y
		auraBtn:ClearAllPoints()
		auraBtn:SetPoint(point, self.Header, "CENTER", ox, oy)
	end
	auraBtn:SetAttribute("type1", "spell")
	auraBtn:SetAttribute("unit1", "player")
	if self.opt.auras then
		self:UpdateAuraButton(ShamanPower_AuraAssignments[self.player])
	end
	if isShaman and self.opt.enabled and self.opt.auras and AllShamans[self.player].AuraInfo[1] and ((GetNumGroupMembers() == 0 and self.opt.ShowWhenSolo) or (GetNumGroupMembers() > 0 and self.opt.ShowInParty)) then
		auraBtn:Show()
	else
		auraBtn:Hide()
	end
	local cbNum = 0
	for classIndex = 1, SHAMANPOWER_MAXCLASSES do
		local _, gspellID = self:GetSpellID(classIndex)
		if (classlist[classIndex] and classlist[classIndex] ~= 0 and (gspellID ~= 0 or self:NormalBlessingCount(classIndex) > 0)) then
			cbNum = cbNum + 1
			local cButton = self.classButtons[cbNum]
			if cbNum == 1 then
				if self.opt.display.showClassButtons then
					self.autoButton:SetAttribute("_onenter", [[
						for _, child in ipairs(childs) do
							if child:GetAttribute("Display") == 1 then
								child:Show()
							end
						end
					]])
					cButton:SetAttribute("_onhide", nil)
				else
					self.autoButton:SetAttribute("_onenter", [[
						local leadChild
						for _, child in ipairs(childs) do
							if child:GetAttribute("Display") == 1 then
								child:Show()
								if (leadChild) then
									leadChild:AddToAutoHide(child)
								else
									leadChild = child
									leadChild:RegisterAutoHide(5)
								end
							end
						end
						if (leadChild) then
							leadChild:AddToAutoHide(self)
						end
					]])
					cButton:SetAttribute("_onhide", [[
						for _, other in ipairs(others) do
							other:Hide()
						end
					]])
				end
			end
			if isShaman and self.opt.enabled and self.opt.display.showClassButtons and ((GetNumGroupMembers() == 0 and self.opt.ShowWhenSolo) or (GetNumGroupMembers() > 0 and self.opt.ShowInParty)) then
				cButton:Show()
			else
				cButton:Hide()
			end
			cButton:SetAttribute("Display", 1)
			cButton:SetAttribute("classID", classIndex)
			cButton:SetAttribute("type1", "macro")
			cButton:SetAttribute("type2", "macro")
			if (cButton:GetAttribute("macrotext1") == nil) then
				if IsInRaid() then
					ShamanPower:ButtonPostClick(cButton, "LeftButton")
				else
					ShamanPower:ButtonPreClick(cButton, "LeftButton")
				end
			end
			local pButtons = self.playerButtons[cbNum]
			for pbNum = 1, math.min(classlist[classIndex], SHAMANPOWER_MAXPERCLASS) do
				local pButton = pButtons[pbNum]
				if self.opt.display.showPlayerButtons then
					pButton:SetAttribute("Display", 1)
				else
					pButton:SetAttribute("Display", 0)
				end
				pButton:SetAttribute("classID", classIndex)
				pButton:SetAttribute("playerID", pbNum)
				local unit = self:GetUnit(classIndex, pbNum)
				local spellID, gspellID = self:GetSpellID(classIndex, unit.name)
				local nSpell, gSpell = self:CanBuffBlessing(spellID, gspellID, unit.unitid)
				-- Greater Blessings (Left Mouse Button [1]) - disable Greater Blessing of Salvation globally. Enabled in PButtonPreClick().
				pButton:SetAttribute("type1", "spell")
				pButton:SetAttribute("unit1", unit.unitid)
				if not self.isWrath and IsInRaid() and gspellID == 4 and (classIndex == 1 or classIndex == 4 or classIndex == 5) and not self.opt.SalvInCombat then
					pButton:SetAttribute("spell1", nil)
				else
					pButton:SetAttribute("spell1", gSpell)
				end
				-- Set Maintank role in a raid
				if IsInRaid() then
					pButton:SetAttribute("ctrl-type1", "maintank")
					pButton:SetAttribute("ctrl-action1", "toggle")
					pButton:SetAttribute("ctrl-unit1", unit.unitid)
				end
				-- Normal Blessings (Right Mouse Button [2]) - disable Normal Blessing of Salvation globally. Enabled in PButtonPreClick().
				pButton:SetAttribute("type2", "spell")
				pButton:SetAttribute("unit2", unit.unitid)
				if not self.isWrath and IsInRaid() and spellID == 4 and (classIndex == 1 or classIndex == 4 or classIndex == 5) and not self.opt.SalvInCombat then
					pButton:SetAttribute("spell2", nil)
				else
					pButton:SetAttribute("spell2", nSpell)
				end
				-- Reset Alternate Blessings
				if unit and unit.name and classIndex then
					pButton:SetAttribute("ctrl-type2", "macro")
					pButton:SetAttribute("ctrl-macrotext2", "/run ShamanPower_NormalAssignments['" .. self.player .. "'][" .. classIndex .. "]['" .. unit.name .. "'] = nil")
				end
			end
			for pbNum = classlist[classIndex] + 1, SHAMANPOWER_MAXPERCLASS do
				local pButton = pButtons[pbNum]
				pButton:SetAttribute("Display", 0)
				pButton:SetAttribute("classID", 0)
				pButton:SetAttribute("playerID", 0)
			end
		end
	end
	cbNum = cbNum + 1
	for i = cbNum, SHAMANPOWER_MAXCLASSES do
		local cButton = self.classButtons[i]
		cButton:SetAttribute("Display", 0)
		cButton:SetAttribute("classID", 0)
		cButton:Hide()
		local pButtons = self.playerButtons[cbNum]
		for pbNum = 1, SHAMANPOWER_MAXPERCLASS do
			local pButton = pButtons[pbNum]
			pButton:SetAttribute("Display", 0)
			pButton:SetAttribute("classID", 0)
			pButton:SetAttribute("playerID", 0)
			pButton:Hide()
		end
	end

	-- Preset and Report buttons are disabled - hide them always
	local presetButton = _G["ShamanPowerBlessingsFramePreset"]
	local reportButton = _G["ShamanPowerBlessingsFrameReport"]
	if presetButton then presetButton:Hide() end
	if reportButton then reportButton:Hide() end

	-- Apply opacity settings
	self:ApplyAllOpacity()

	self:ButtonsUpdate()
	self:UpdateAnchor(displayedButtons)
end

function ShamanPower:SetButton(baseName)
	local time = _G[baseName .. "Time"]
	local text = _G[baseName .. "Text"]
	if (self.opt.display.HideCountText) then
		text:Hide()
	else
		text:Show()
	end
	if (self.opt.display.HideTimerText) then
		time:Hide()
	else
		time:Show()
	end
end

function ShamanPower:SetPButton(baseName)
	local rng = _G[baseName .. "Rng"]
	local dead = _G[baseName .. "Dead"]
	local name = _G[baseName .. "Name"]
	if (self.opt.display.HideRngText) then
		rng:Hide()
	else
		rng:Show()
	end
	if (self.opt.display.HideDeadText) then
		dead:Hide()
	else
		dead:Show()
	end
	if (self.opt.display.HideNameText) then
		name:Hide()
	else
		name:Show()
	end
end

function ShamanPower:UpdateButtonOnPostClick(button, mousebutton)
	local classID = button:GetAttribute("classID")
	if classID and classID > 0 then
		local _, _, cbNum = strfind(button:GetName(), "ShamanPowerC(.+)")
		self:UpdateButton(button, "ShamanPowerC" .. cbNum, classID)
		self:ButtonsUpdate()
		C_Timer.After(
		1.0,
		function()
			self:UpdateButton(button, "ShamanPowerC" .. cbNum, classID)
			self:ButtonsUpdate()
		end
		)
	end
end

-- returns:
-- "need_big" for missing greater blessing
-- "need_small" for missing single blessing
-- "have" for no missing buff
local function ClassifyUnitBuffStateForButton(unit)
	-- do not highlight dead players in combat
	if unit.dead and InCombatLockdown() then
		return "have"
	end
	if not unit.hasbuff then
		if unit.specialbuff then
			return "need_small"
		else
			return "need_big"
		end
	else
		return "have"
	end
end

function ShamanPower:UpdateButton(button, baseName, classID)
	local button = _G[baseName]
	local classIcon = _G[baseName .. "ClassIcon"]
	local buffIcon = _G[baseName .. "BuffIcon"]
	local time = _G[baseName .. "Time"]
	local time2 = _G[baseName .. "Time2"]
	local text = _G[baseName .. "Text"]
	local nneed = 0
	local nspecial = 0
	local nhave = 0
	for _, unit in pairs(classes[classID]) do
		local state = ClassifyUnitBuffStateForButton(unit)
		-- do not show tanks clicking off salvation on the class button
		if not self.isWrath and unit.tank and (state == "need_big") and (self:GetSpellID(classID, unit.name) == 4) then
			state = "have"
		end
		-- do not show unreachable units on the class button
		if (not unit.visible) and InCombatLockdown() then
			state = "have"
		end
		
		if state == "need_big" then
			nneed = nneed + 1
		elseif state == "need_small" then
			nspecial = nspecial + 1
		else
			nhave = nhave + 1
		end
	end
	classIcon:SetTexture(self.ClassIcons[classID])
	classIcon:SetVertexColor(1, 1, 1)
	local _, gspellID = self:GetSpellID(classID)
	-- Use TotemIcons: classID is element, gspellID is totem index
	local totemIcon = self.TotemIcons[classID] and self.TotemIcons[classID][gspellID]
	buffIcon:SetTexture(totemIcon)
	local classExpire, classDuration, specialExpire, specialDuration = self:GetBuffExpiration(classID)
	time:SetText(self:FormatTime(classExpire))
	time:SetTextColor(self:GetSeverityColor(classExpire and classDuration and classDuration > 0 and (classExpire / classDuration) or 0))
	time2:SetText(self:FormatTime(specialExpire))
	time2:SetTextColor(self:GetSeverityColor(specialExpire and specialDuration and specialDuration > 0 and (specialExpire / specialDuration) or 0))
	if (nneed + nspecial > 0) then
		text:SetText(nneed + nspecial)
	else
		text:SetText("")
	end
	-- Use totem status detection for shamans: classID is the element ID
	local totemAssigned = gspellID and gspellID > 0
	local totemActive = self:IsTotemActive(classID)
	if not totemAssigned then
		-- No totem assigned for this element
		self:ApplyBackdrop(button, self.opt.cBuffGood)
	elseif totemActive then
		-- Totem is active
		self:ApplyBackdrop(button, self.opt.cBuffGood)
	else
		-- Totem assigned but not active
		self:ApplyBackdrop(button, self.opt.cBuffNeedAll)
	end
	return classExpire, classDuration, specialExpire, specialDuration, nhave, nneed, nspecial
end

function ShamanPower:GetSeverityColor(percent)
	if (percent >= 0.5) then
		return (1.0 - percent) * 2, 1.0, 0.0
	else
		return 1.0, percent * 2, 0.0
	end
end

function ShamanPower:GetBuffExpiration(classID)
	local class = classes[classID]
	local classExpire, classDuration, specialExpire, specialDuration = 9999, 9999, 9999, 9999
	for _, unit in pairs(class) do
		if unit.unitid then
			local j = 1
			local spellID, gspellID = self:GetSpellID(classID, unit.name)
			local isMight = (spellID == 2) or (gspellID == 2)
			local spell = self.Spells[spellID]
			local gspell = self.GSpells[gspellID]
			local buffName = UnitBuff(unit.unitid, j)
			while buffName do
				if (buffName == gspell) or (not isWrath and isMight and buffName == ShamanPower.Spells[8]) then
					local _, _, _, _, buffDuration, buffExpire = UnitAura(unit.unitid, j, "HELPFUL")
					if buffExpire then
						if buffExpire == 0 then
							buffExpire = 0
						else
							buffExpire = buffExpire - GetTime()
						end
						classExpire = min(classExpire, buffExpire)
						classDuration = min(classDuration, buffDuration)
						--self:Debug("[GetBuffExpiration] buffName: "..buffName.." | classExpire: "..classExpire.." | classDuration: "..classDuration)
						break
					end
				elseif (buffName == spell) or (not isWrath and isMight and buffName == ShamanPower.Spells[8]) then
					local _, _, _, _, buffDuration, buffExpire = UnitAura(unit.unitid, j, "HELPFUL")
					if buffExpire then
						if buffExpire == 0 then
							buffExpire = 0
						else
							buffExpire = buffExpire - GetTime()
						end
						specialExpire = min(specialExpire, buffExpire)
						specialDuration = min(specialDuration, buffDuration)
						--self:Debug("[GetBuffExpiration] buffName: "..buffName.." | specialExpire: "..classExpire.." | specialDuration: "..classDuration)
						break
					end
				end
				j = j + 1
				buffName = UnitBuff(unit.unitid, j)
			end
		end
	end
	return classExpire, classDuration, specialExpire, specialDuration
end

function ShamanPower:GetRFExpiration()
	-- Shamans don't have Righteous Fury, return safe defaults
	-- This could be repurposed for weapon enchant tracking later
	return 9999, 1
end

function ShamanPower:GetSealExpiration()
	-- Shamans don't have Seals, return safe defaults
	-- This could be repurposed for weapon enchant tracking later
	return 9999, 1
end

function ShamanPower:UpdatePButtonOnPostClick(button, mousebutton)
	local classID = button:GetAttribute("classID")
	local playerID = button:GetAttribute("playerID")
	if classID and playerID then
		local _, _, cbNum, pbNum = strfind(button:GetName(), "ShamanPowerC(.+)P(.+)")
		self:UpdatePButton(button, "ShamanPowerC" .. cbNum .. "P" .. pbNum, classID, playerID, mousebutton)
		self:ButtonsUpdate()
		C_Timer.After(
			1.0,
			function()
				self:UpdatePButton(button, "ShamanPowerC" .. cbNum .. "P" .. pbNum, classID, playerID, mousebutton)
				self:ButtonsUpdate()
			end
		)
	end
end

function ShamanPower:PButtonPreClick(button, mousebutton)
	if InCombatLockdown() then return end

	local classID = button:GetAttribute("classID")
	local playerID = button:GetAttribute("playerID")
	if not self.isWrath and classID and playerID then
		local unit = classes[classID][playerID]
		local spellID, gspellID = self:GetSpellID(classID, unit.name)
		local nSpell, gSpell = self:CanBuffBlessing(spellID, gspellID, unit.unitid)
		-- Enable Greater Blessing of Salvation on everyone but do not allow Blessing of Salvation on tanks if SalvInCombat is disabled
		if IsInRaid() and (spellID == 4 or gspellID == 4) and not self.opt.SalvInCombat then
			for k, v in pairs(classmaintanks) do
				-- If for some reason the targeted unit is in combat and there is a tank present
				-- in the Class Group then disable Greater Blessing of Salvation for this unit.
				if UnitAffectingCombat(unit.unitid) and gspellID == 4 and (k == classID and v == true) then
					gSpell = nil
				end
				if k == unit.unitid and v == true then
					-- Do not allow Salvation on tanks - Blessings [disabled]
					if (spellID == 4) then
						nSpell = nil
					end
					if (gspellID == 4) then
						gSpell = nil
					end
				end
			end
			-- Greater Blessing of Salvation [enabled for non-tanks]
			button:SetAttribute("spell1", gSpell)
			-- Normal Blessing of Salvation [enabled for non-tanks]
			button:SetAttribute("spell2", nSpell)
		end
	end
end

function ShamanPower:UpdatePButton(button, baseName, classID, playerID, mousebutton)
	--self:Debug("UpdatePButton()")
	local button = _G[baseName]
	local buffIcon = _G[baseName .. "BuffIcon"]
	local tankIcon = _G[baseName .. "TankIcon"]
	local rng = _G[baseName .. "Rng"]
	local dead = _G[baseName .. "Dead"]
	local name = _G[baseName .. "Name"]
	local time = _G[baseName .. "Time"]
	local unit = classes[classID][playerID]
	local raidtank
	if unit then
		local spellID, gspellID = self:GetSpellID(classID, unit.name)
		tankIcon[unit.tank and "Show" or "Hide"](tankIcon)
		-- Use TotemIcons: classID is element, spellID is totem index
		local totemIcon = self.TotemIcons[classID] and self.TotemIcons[classID][spellID]
		buffIcon:SetTexture(totemIcon)
		buffIcon:SetVertexColor(1, 1, 1)
		time:SetText(self:FormatTime(unit.hasbuff))
		
		-- The following logic keeps Blessing of Salvation from being assigned to Warrior, Druid and Paladin tanks while in a RAID
		-- and SalvInCombat isn't enabled. Allows Normal Blessing of Salvation on everyone else and all other blessings.
		if not InCombatLockdown() then
			local nSpell, gSpell = self:CanBuffBlessing(spellID, gspellID, unit.unitid)
			-- Normal Blessing of Salvation [enabled] and Greater Blessing of Salvation [disabled] in a raid and SalvInCombat isn't allowed
			if not self.isWrath and IsInRaid() and (spellID == 4 or gspellID == 4) and not self.opt.SalvInCombat then
				for k, v in pairs(classmaintanks) do
					-- If for some reason the targeted unit is in combat and there is a tank present
					-- in the Class Group then disable Greater Blessing of Salvation for this unit.
					if gspellID == 4 and (k == classID and v == true) then
						-- This assignment is enabled by the PButtonPreClick() function for non-tanks on a per-click basis while not in combat
						gSpell = nil
					end
					if k == unit.unitid and v == true then
						-- Do not allow Salvation on tanks - Blessings [disabled]
						if (spellID == 4) then
							nSpell = nil
						end
						if (gspellID == 4) then
							gSpell = nil
						end
					end
				end
				-- Greater Blessing of Salvation [enabled for non-tanks]
				button:SetAttribute("spell1", gSpell)
				-- Normal Blessing of Salvation [enabled for non-tanks]
				button:SetAttribute("spell2", nSpell)
			else
				-- Greater Blessings [enabled]
				button:SetAttribute("spell1", gSpell)
				-- Normal Blessings [enabled]
				button:SetAttribute("spell2", nSpell)
			end
		end
		
		local state = ClassifyUnitBuffStateForButton(unit)
		if state == "need_big" then
			self:ApplyBackdrop(button, self.opt.cBuffNeedAll)
		elseif state == "need_small" then
			self:ApplyBackdrop(button, self.opt.cBuffNeedSpecial)
		else
			self:ApplyBackdrop(button, self.opt.cBuffGood)
		end
		
		if unit.hasbuff then
			buffIcon:SetAlpha(1)
			if not unit.visible and not unit.inrange then
				rng:SetVertexColor(1, 0, 0)
				rng:SetAlpha(1)
			elseif unit.visible and not unit.inrange then
				rng:SetVertexColor(1, 1, 0)
				rng:SetAlpha(1)
			else
				rng:SetVertexColor(0, 1, 0)
				rng:SetAlpha(1)
			end
			dead:SetAlpha(0)
		else
			buffIcon:SetAlpha(0.4)
			if not unit.visible and not unit.inrange then
				rng:SetVertexColor(1, 0, 0)
				rng:SetAlpha(1)
			elseif unit.visible and not unit.inrange then
				rng:SetVertexColor(1, 1, 0)
				rng:SetAlpha(1)
			else
				rng:SetVertexColor(0, 1, 0)
				rng:SetAlpha(1)
			end
			if unit.dead then
				dead:SetVertexColor(1, 0, 0)
				dead:SetAlpha(1)
			else
				dead:SetVertexColor(0, 1, 0)
				dead:SetAlpha(0)
			end
		end
		if unit.name then
			local shortname = Ambiguate(unit.name, "short")
			if unit.unitid:find("pet") then
				name:SetText("|T132242:0|t "..shortname)
			else
				name:SetText(shortname)
			end
		end
	else
		self:ApplyBackdrop(button, self.opt.cBuffGood)
		buffIcon:SetAlpha(0)
		rng:SetAlpha(0)
		dead:SetAlpha(0)
	end
end

function ShamanPower:ButtonsUpdate()
	--self:Debug("ButtonsUpdate()")
	local minClassExpire, minClassDuration, minSpecialExpire, minSpecialDuration, sumnhave, sumnneed, sumnspecial = 9999, 9999, 9999, 9999, 0, 0, 0
	for cbNum = 1, SHAMANPOWER_MAXCLASSES do -- scan classes and if populated then assign textures, etc
		local cButton = self.classButtons[cbNum]
		local classIndex = cButton:GetAttribute("classID")
		if classIndex > 0 then
			self:ScanClass(classIndex) -- scanning for in-range and buffs
			local classExpire, classDuration, specialExpire, specialDuration, nhave, nneed, nspecial = self:UpdateButton(cButton, "ShamanPowerC" .. cbNum, classIndex)
			minClassExpire = min(minClassExpire, classExpire)
			minSpecialExpire = min(minSpecialExpire, specialExpire)
			minClassDuration = min(minClassDuration, classDuration)
			minSpecialDuration = min(minSpecialDuration, specialDuration)
			sumnhave = sumnhave + nhave
			sumnneed = sumnneed + nneed
			sumnspecial = sumnspecial + nspecial
			local pButtons = self.playerButtons[cbNum]
			for pbNum = 1, SHAMANPOWER_MAXPERCLASS do
				local pButton = pButtons[pbNum]
				local playerIndex = pButton:GetAttribute("playerID")
				if playerIndex > 0 then
					self:UpdatePButton(pButton, "ShamanPowerC" .. cbNum .. "P" .. pbNum, classIndex, playerIndex)
				end
			end -- by pbnum
		end -- class has players
	end -- by cnum
	local autobutton = _G["ShamanPowerAuto"]
	local time = _G["ShamanPowerAutoTime"]
	local time2 = _G["ShamanPowerAutoTime2"]
	local text = _G["ShamanPowerAutoText"]
	-- Use totem status detection for shamans instead of paladin buff logic
	local activeCount, assignedCount = self:GetTotemStatus()
	if assignedCount == 0 then
		-- No totems assigned
		self:ApplyBackdrop(autobutton, self.opt.cBuffGood)
	elseif activeCount == 0 then
		-- No totems active (all need to be dropped)
		self:ApplyBackdrop(autobutton, self.opt.cBuffNeedAll)
	elseif activeCount < assignedCount then
		-- Some totems active
		self:ApplyBackdrop(autobutton, self.opt.cBuffNeedSome)
	else
		-- All assigned totems are active
		self:ApplyBackdrop(autobutton, self.opt.cBuffGood)
	end
	time:SetText(self:FormatTime(minClassExpire))
	time:SetTextColor(self:GetSeverityColor(minClassExpire and minClassDuration and minClassDuration > 0 and (minClassExpire / minClassDuration) or 0))
	time2:SetText(self:FormatTime(minSpecialExpire))
	time2:SetTextColor(self:GetSeverityColor(minSpecialExpire and minSpecialDuration and minSpecialDuration > 0 and (minSpecialExpire / minSpecialDuration) or 0))
	if (sumnneed + sumnspecial > 0) then
		text:SetText(sumnneed + sumnspecial)
	else
		text:SetText("")
	end
	local rfbutton = _G["ShamanPowerRF"]
	local time1 = _G["ShamanPowerRFTime1"] -- rf timer
	local time2 = _G["ShamanPowerRFTime2"] -- seal timer
	local expire1, duration1 = self:GetRFExpiration()
	local expire2, duration2 = self:GetSealExpiration()
	if self.opt.rf then
		time1:SetText(self:FormatTime(expire1))
		time1:SetTextColor(self:GetSeverityColor(expire1 / duration1))
		if self.opt.display.buffDuration == true and expire1 < 1800 then
			prevBuffDuration = true
			self.opt.display.buffDuration = false
		elseif self.opt.display.buffDuration == false and prevBuffDuration == true then
			prevBuffDuration = nil
			self.opt.display.buffDuration = true
		end
	else
		time1:SetText("")
	end
	time2:SetText(self:FormatTime(expire2))
	time2:SetTextColor(self:GetSeverityColor(expire2 / duration2))
	if (expire1 == 9999 and self.opt.rf) and (expire2 == 9999 and self.opt.seal == 0) then
		self:ApplyBackdrop(rfbutton, self.opt.cBuffNeedAll)
	elseif (expire1 == 9999 and self.opt.rf) or (expire2 == 9999 and self.opt.seal > 0) then
		self:ApplyBackdrop(rfbutton, self.opt.cBuffNeedSome)
	else
		self:ApplyBackdrop(rfbutton, self.opt.cBuffGood)
	end
	if self.opt.auras then
		self:UpdateAuraButton(ShamanPower_AuraAssignments[self.player])
	end
	if minClassExpire ~= 9999 or minSpecialExpire ~= 9999 or expire1 ~= 9999 or expire2 ~= 9999 then
		if isShaman and not self.buttonUpdate then
			self.buttonUpdate = self:ScheduleRepeatingTimer(self.ButtonsUpdate, 1, self)
		end
	else
		self:CancelTimer(self.buttonUpdate)
		self.buttonUpdate = nil
	end
end

function ShamanPower:UpdateAnchor(displayedButtons)
	ShamanPowerAnchor:SetChecked(self.opt.display.frameLocked)
	if self.opt.display.enableDragHandle and ((GetNumGroupMembers() == 0 and self.opt.ShowWhenSolo) or (GetNumGroupMembers() > 0 and self.opt.ShowInParty)) then
		ShamanPowerAnchor:ClearAllPoints()
		-- Position the anchor relative to the mini totem bar (autoButton) if it's visible
		if self.autoButton and self.autoButton:IsShown() then
			ShamanPowerAnchor:SetPoint("BOTTOM", self.autoButton, "TOP", 0, 4)
		elseif self.Header then
			-- Fallback: position relative to the Header when mini totem bar is hidden (e.g., TotemTimers sync enabled)
			ShamanPowerAnchor:SetPoint("TOP", self.Header, "BOTTOM", 0, -4)
		end
		ShamanPowerAnchor:Show()
	else
		ShamanPowerAnchor:Hide()
	end
end

function ShamanPower:NormalBlessingCount(classID)
	local nbcount = 0
	if classlist[classID] then
		for pbNum = 1, math.min(classlist[classID], SHAMANPOWER_MAXPERCLASS) do
			local unit = self:GetUnit(classID, pbNum)
			if unit and unit.name and ShamanPower_NormalAssignments[self.player] and ShamanPower_NormalAssignments[self.player][classID] and ShamanPower_NormalAssignments[self.player][classID][unit.name] then
				nbcount = nbcount + 1
			end
		end -- by pbnum
	end
	return nbcount
end

function ShamanPower:GetSpellID(classID, playerName)
	local normal = 0
	local greater = 0
	if playerName and ShamanPower_NormalAssignments[self.player] and ShamanPower_NormalAssignments[self.player][classID] and ShamanPower_NormalAssignments[self.player][classID][playerName] then
		normal = ShamanPower_NormalAssignments[self.player][classID][playerName]
	end
	if ShamanPower_Assignments[self.player] and ShamanPower_Assignments[self.player][classID] then
		greater = ShamanPower_Assignments[self.player][classID]
	end
	if normal == 0 then
		normal = greater
	end
	return normal, greater
end

function ShamanPower:GetUnit(classID, playerID)
	return classes[classID][playerID]
end

function ShamanPower:GetUnitIdByName(name)
	for _, unit in ipairs(roster) do
		if unit.name == name then
			return unit.unitid
		end
	end
end

function ShamanPower:GetUnitAndSpellSmart(classid, mousebutton)
	local class = classes[classid]
	local now = time()
	-- Greater Blessings
	if (mousebutton == "LeftButton") then
		local minExpire, classMinExpire, classNeedsBuff, classMinUnitPenalty, classMinUnit, classMinSpell, classMaxSpell = 600, 600, true, 600, nil, nil, nil
		for _, unit in pairs(class) do
			local spellID, gspellID = self:GetSpellID(classid, unit.name)
			local spell = self.Spells[spellID]
			local gspell = self.GSpells[gspellID]
			if (not unit.specialbuff) and (IsSpellInRange(gspell, unit.unitid) == 1) and (not UnitIsDeadOrGhost(unit.unitid)) then
				local penalty = 0
				local buffExpire, buffDuration, buffName = self:IsBuffActive(spell, gspell, unit.unitid)
				local nSpell, gSpell = self:CanBuffBlessing(spellID, gspellID, unit.unitid)
				local recipients = #classes[classid]

				if (self.AutoBuffedList[unit.name] and now - self.AutoBuffedList[unit.name] < recipients*1.65) then
					penalty = SHAMANPOWER_GREATERBLESSINGDURATION
				end
				if (self.PreviousAutoBuffedUnit and (unit.hasbuff and unit.hasbuff > minExpire) and unit.name == self.PreviousAutoBuffedUnit.name and GetNumGroupMembers() > 0) then
					penalty = SHAMANPOWER_GREATERBLESSINGDURATION
				else
					penalty = 0
				end
				-- Buff Duration option disabled - allow spamming buffs
				if not self.opt.display.buffDuration then
					for i = 1, recipients do
						local unitID = classes[classid][i]
						if IsSpellInRange(gspell, unitID.unitid) ~= 1 or UnitIsDeadOrGhost(unitID.unitid) or UnitIsAFK(unitID.unitid) or not UnitIsConnected(unitID.unitid) then
							recipients = recipients - 1
						end
					end
					if not self.AutoBuffedList[unit.name] or now - self.AutoBuffedList[unit.name] > (1.65 * recipients) then
						buffExpire = 0
						penalty = 0
					end
				else
					-- If normal blessing - set duration to zero and buff it - but only if an alternate blessing isn't assigned
					if (buffName and buffName == spell and spellID == gspellID) then
						buffExpire = 0
						penalty = 0
					end
				end

				if not self.isWrath and gspellID == 4 then
					-- Skip tanks if Salv is assigned. This allows autobuff to work since some tanks
					-- have addons and/or scripts to auto cancel Salvation. Prevents getting stuck
					-- buffing a tank when auto buff rotates among players in the class group.
					if unit.tank then
						buffExpire = 9999
						penalty = 9999
					end
				end

				if (not ShamanPower.petsShareBaseClass) and unit.unitid:find("pet") then
					-- in builds where pets do not share greater blessings, we don't autobuff them with such
					buffExpire = 9999
					penalty = 9999
				end
				-- Refresh any greater blessing under a 10 min duration
				if ((not buffExpire or (buffExpire < classMinExpire) and buffExpire < SHAMANPOWER_GREATERBLESSINGDURATION) and classMinExpire > 0) then
					if (penalty < classMinUnitPenalty) then
						classMinUnit = unit
						classMinUnitPenalty = penalty
					end
					classMinSpell = nSpell
					classMaxSpell = gSpell
					classMinExpire = (buffExpire or 0)
				end
			elseif (UnitIsVisible(unit.unitid) == false and not UnitIsAFK(unit.unitid) and UnitIsConnected(unit.unitid)) and (IsInRaid() == false or #classes[classid] > 3) then
				classNeedsBuff = false
			end
		end
		-- Refresh any greater blessing under a 10 min duration
		if (classMinUnit and classMinUnit.name and (classNeedsBuff or not self.opt.autobuff.waitforpeople) and classMinExpire + classMinUnitPenalty < minExpire and minExpire > 0) then
			self.AutoBuffedList[classMinUnit.name] = now
			self.PreviousAutoBuffedUnit = classMinUnit
			return classMinUnit.unitid, classMinSpell, classMaxSpell
		end
	-- Normal Blessings
	elseif (mousebutton == "RightButton") then
		local minExpire = 240
		for _, unit in pairs(class) do
			local spellID, gspellID = self:GetSpellID(classid, unit.name)
			local spell = self.Spells[spellID]
			local spell2 = self.GSpells[spellID]
			local gspell = self.GSpells[gspellID]
			if (IsSpellInRange(spell, unit.unitid) == 1) and (not UnitIsDeadOrGhost(unit.unitid)) then
				local penalty = 0
				local greaterBlessing = false
				local buffExpire, buffDuration, buffName = self:IsBuffActive(spell, spell2, unit.unitid)
				local nSpell, gSpell = self:CanBuffBlessing(spellID, gspellID, unit.unitid)
				local recipients = #classes[classid]

				if (self.AutoBuffedList[unit.name] and now - self.AutoBuffedList[unit.name] < recipients*1.65) then
					penalty = SHAMANPOWER_NORMALBLESSINGDURATION
				end
				if (self.PreviousAutoBuffedUnit and (unit.hasbuff and unit.hasbuff > minExpire) and unit.name == self.PreviousAutoBuffedUnit.name and GetNumGroupMembers() > 0) then
					penalty = SHAMANPOWER_NORMALBLESSINGDURATION
				else
					penalty = 0
				end
				-- Flag valid Greater Blessings | If it falls below 4 min refresh it with a Normal Blessing
				if buffName and buffName == gspell and buffExpire > minExpire then
					greaterBlessing = true
					penalty = SHAMANPOWER_NORMALBLESSINGDURATION
				elseif buffName and buffName == gspell and buffExpire < minExpire then
					greaterBlessing = false
					penalty = 0
				end
				if (buffName and buffName == gspell) then
					-- If we're using Blessing of Sacrifice then set the expiration to match Normal Blessings so Auto Buff works.
					if not self.isWrath and (spell == self.Spells[7]) then
						greaterBlessing = false
						buffExpire = 270
						penalty = 0
					-- Alternate Blessing assigned then always allow buffing over a Greater Blessing: Set duration to zero and buff it.
					elseif (self.isWrath and spellID ~= gspellID) or (spell ~= self.Spells[7] and spellID ~= gspellID) then
						greaterBlessing = false
						buffExpire = 0
						penalty = 0
					end
				end
				-- Buff Duration option disabled - allow spamming buffs
				-- This logic counts the number of players in a class and subtracts the ratio from the
				-- buffs overall duration resulting in a "round robin" approach for spamming buffs so
				-- auto buff doesn't get stuck on one person. The ratio is reduced when a player has
				-- a Greater Blessing, is out of range, dead, afk, or not connected.
				if not self.opt.display.buffDuration then
					for i = 1, recipients do
						local unitID = classes[classid][i]
						if (unitID.hasbuff and unitID.hasbuff > 300) or IsSpellInRange(nSpell, unitID.unitid) ~= 1 or UnitIsDeadOrGhost(unitID.unitid) or UnitIsAFK(unitID.unitid) or not UnitIsConnected(unitID.unitid) then
							recipients = recipients - 1
						end
					end
					-- Blessing of Sacrifice
					if not self.isWrath and (spell == self.Spells[7]) then
						if not buffExpire or buffExpire < (30 - ((1.65 * recipients) - 1.65)) then
							buffExpire = 0
							penalty = 0
						end
					-- Normal Blessings
					elseif self.isWrath or (spell ~= self.Spells[7]) then
						if not buffExpire or buffExpire < (300 - ((1.65 * recipients) - 1.65)) then
							buffExpire = 0
							penalty = 0
						end
					end
				end
				if not self.isWrath and IsInRaid() then
					-- Skip tanks if Salv is assigned. This allows autobuff to work since some tanks
					-- have addons and/or scripts to auto cancel Salvation. Tanks shouldn't have a
					-- Normal Blessing of Salvation but sometimes there are way more Paladins in a
					-- Raid than there are buffs to assign so an Alternate Blessing might not be in
					-- use to wipe Salvation from a tank. Prevents getting stuck buffing a tank when
					-- auto buff rotates among players in the class group.
					for k, v in pairs(classmaintanks) do
						if k == unit.unitid and v == true then
							if (spellID == 4 and not self.opt.SalvInCombat) then
								buffExpire = 9999
								penalty = 9999
							end
						end
					end
				end
				-- Refresh any normal blessing under a 4 min duration
				if ((not buffExpire or buffExpire + penalty < minExpire and buffExpire < SHAMANPOWER_NORMALBLESSINGDURATION) and minExpire > 0 and not greaterBlessing) then
					self.AutoBuffedList[unit.name] = now
					self.PreviousAutoBuffedUnit = unit
					return unit.unitid, nSpell, gSpell
				end
			end
		end
	end
	return nil, "", ""
end

function ShamanPower:IsBuffActive(spellName, gspellName, unitID)
	local isMight = (spellName == ShamanPower.Spells[2]) or (gSpellName == ShamanPower.GSpells[2])
	local j = 1
	local buffName = UnitBuff(unitID, j)
	while buffName do
		if (buffName == spellName) or (buffName == gspellName) or (not isWrath and isMight and buffName == ShamanPower.Spells[8] )then
			local _, _, _, _, buffDuration, buffExpire = UnitAura(unitID, j, "HELPFUL")
			if buffExpire then
				if buffExpire == 0 then
					buffExpire = 0
				else
					buffExpire = buffExpire - GetTime()
				end
			end
			--self:Debug("[IsBuffActive] buffName: "..buffName.." | buffExpire: "..buffExpire.." | buffDuration: "..buffDuration)
			return buffExpire, buffDuration, buffName
		end
		j = j + 1
		buffName = UnitBuff(unitID, j)
	end
	return nil
end

function ShamanPower:ButtonPreClick(button, mousebutton)
	if InCombatLockdown() then return end

	-- Greater Blessing: Clear
	button:SetAttribute("macrotext1", nil)
	button:SetAttribute("spellName1", nil)
	button:SetAttribute("step1", nil)
	button:UnwrapScript(button, "OnClick")
	-- Normal Blessing: Clear
	button:SetAttribute("macrotext2", nil)
	local classid = button:GetAttribute("classID")
	local spell, gspell, unitName, unitid
	if classid and classid > 0 then
		if IsInRaid() and (mousebutton == "LeftButton") and ((self.isWrath and classid ~= 11) or (not self.isWrath and classid ~= 10)) then
			unitid, spell, gspell = self:GetUnitAndSpellSmart(classid, mousebutton)
			if unitid and classid then
				unitName = GetUnitName(unitid, true)
			end
			spell = false
		elseif not IsInRaid() or ((IsInRaid() and mousebutton == "RightButton")) then
			unitid, spell, gspell = self:GetUnitAndSpellSmart(classid, mousebutton)
			if unitid then
				if (self.isWrath and classid == 11) or (not self.isWrath and classid == 10) then
					local unitPrefix = "party"
					local offSet = 9
					if (unitid:find("raid")) then
						unitPrefix = "raid"
						offSet = 8
					end
					unitName = GetUnitName(unitPrefix .. unitid:sub(offSet), true) .. "-pet"
				else
					unitName = GetUnitName(unitid, true)
				end
			end
			if mousebutton == "LeftButton" then
				spell = false
			end
			if mousebutton == "RightButton" then
				gspell = false
			end
		end
		if unitName then
			local spellID, gspellID = self:GetSpellID(classid, unitName)
			-- Enable Greater Blessing of Salvation on everyone but do not allow Normal Blessing of Salvation on tanks if SalvInCombat is disabled
			if not self.isWrath then
				if IsInRaid() and (spellID == 4 or gspellID == 4) and (not self.opt.SalvInCombat) then
					for k, v in pairs(classmaintanks) do
						-- If the buff recipient unit(s) is in combat and there is a tank present in
						-- the Class Group then disable Greater Blessing of Salvation for this unit(s).
						if UnitAffectingCombat(unitid) and (gspellID == 4) and (k == classid and v == true) then
							gspell = false
						end
						if k == unitid and v == true then
							-- Do not allow Salvation on tanks - Blessings [disabled]
							if (spellID == 4) then
								spell = false
							end
							if (gspellID == 4) then
								gspell = false
							end
						end
					end
				end
			end
			-- Set Greater Blessing: left click
			if gspell then
				local gspellMacro = "/cast [@" .. unitName .. ",help,nodead] " .. gspell
				button:SetAttribute("macrotext1", gspellMacro)
				--self:Debug("Single Unit Macro Executed: "..gspellMacro)
			end
			-- Set Normal Blessing: right click (Only works while not in combat. Cleared in PostClick.)
			if spell then
				local spellMacro = "/cast [@" .. unitName .. ",help,nodead] " .. spell
				button:SetAttribute("macrotext2", spellMacro)
				--self:Debug("Single Unit Macro Executed: "..spellMacro)
			end
		end
	end
end

function ShamanPower:ButtonPostClick(button, mousebutton)
	if InCombatLockdown() then return end

	if IsInRaid() then
		-- Greater Blessing: Clear current macro
		button:SetAttribute("macrotext1", nil)
		button:SetAttribute("spellName1", nil)
		button:SetAttribute("step1", nil)
		button:UnwrapScript(button, "OnClick")
		-- Create a list of viable players for in-combat script
		local targetNames = {}
		local gSpell = false
		local numPlayers = 0
		local classid = button:GetAttribute("classID")
		if (mousebutton == "LeftButton") and (classid ~= 10) then
			for i = 1, SHAMANPOWER_MAXPERCLASS do
				if numPlayers < 9 and classid and classes[classid] and classes[classid][i] then
					local unit = classes[classid][i]
					local spellID, gspellID = self:GetSpellID(classid, unit.name)
					local _, gspell = self:CanBuffBlessing(spellID, gspellID, unit.unitid)
					if gspell and (IsSpellInRange(gspell, unit.unitid) == 1) and (not UnitIsDeadOrGhost(unit.unitid)) and (not UnitIsAFK(unit.unitid)) and UnitIsConnected(unit.unitid) then
						local unitName = GetUnitName(classes[classid][i].unitid, true)
						table.insert(targetNames, unitName)
						numPlayers = numPlayers + 1
						gSpell = gspell
					end
				else
					break
				end
			end
		end
		-- If there is a tank present for this "classid" then disable Greater Blessing of Salvation.
		if not self.isWrath then
			if gSpell and strfind(gSpell, self.GSpells[4]) and not self.opt.SalvInCombat then
				for k, v in pairs(classmaintanks) do
					if (k == classid and v == true) then
						gSpell = false
					end
				end
			end
		end
		if gSpell and numPlayers > 0 then
			button:SetAttribute("spellName1", gSpell)
			button:SetAttribute("step1", 1)

			button:Execute("unitNames = newtable([=[" .. strjoin("]=],[=[", unpack(targetNames)) .. "]=])\n")

			button:WrapScript(button, "OnClick", [=[
				local spellName = self:GetAttribute("spellName1")
				local step = self:GetAttribute("step1")

				if step > table.maxn(unitNames) then
					step = 1
				end

				if unitNames[step] and SecureCmdOptionParse("[@" .. unitNames[step] .. ",help,nodead]") then
					local gspellMacro = "/cast %s %s"
					local targetName = "[@" .. unitNames[step] .. ",help,nodead]"
					gspellMacro = format(gspellMacro, targetName, spellName)
					self:SetAttribute("macrotext1", gspellMacro)
					print("Secure Macro: "..gspellMacro)
				end
				self:SetAttribute("step1", step + 1)

			]=])
		end
	end
	-- Normal Blessing: Clear current macro
	button:SetAttribute("macrotext2", nil)
end

function ShamanPower:ClickHandle(button, mousebutton)
	-- Lock & Unlock the frame on left click, and toggle config dialog with right click
	local function RelockActionBars()
		ShamanPower:EnsureProfileTable("display")
		self.opt.display.frameLocked = true
		if (self.opt.display.LockBuffBars) then
			LOCK_ACTIONBAR = "1"
		end
		_G["ShamanPowerAnchor"]:SetChecked(true)
	end
	if (mousebutton == "RightButton") then
		if IsShiftKeyDown() then
			self:OpenConfigWindow()
			button:SetChecked(self.opt.display.frameLocked)
		else
			ShamanPowerBlessings_Toggle()
			button:SetChecked(self.opt.display.frameLocked)
		end
	elseif (mousebutton == "LeftButton") then
		self:EnsureProfileTable("display")
		self.opt.display.frameLocked = not self.opt.display.frameLocked
		if (self.opt.display.frameLocked) then
			if (self.opt.display.LockBuffBars) then
				LOCK_ACTIONBAR = "1"
			end
			local h = _G["ShamanPowerFrame"]
			self:SaveFramePosition(h)
		else
			if (self.opt.display.LockBuffBars) then
				LOCK_ACTIONBAR = "0"
			end
			self:ScheduleTimer(RelockActionBars, 30)
		end
		button:SetChecked(self.opt.display.frameLocked)
	end
end

function ShamanPower:DragStart()
	-- Start dragging if not locked
	if (not self.opt.display.frameLocked) then
		local h = _G["ShamanPowerFrame"]
		h:SetClampedToScreen(false)  -- Allow free movement
		h:StartMoving()
	end
end

function ShamanPower:DragStop()
	-- End dragging and save position
	local h = _G["ShamanPowerFrame"]
	h:StopMovingOrSizing()
	-- Save position to profile (ensures display table exists for proper persistence)
	self:SaveFramePosition(h)
end

function ShamanPower:AutoBuff(button, mousebutton)
	if InCombatLockdown() then return end

	local now = time()
	local greater = (mousebutton == "LeftButton" or mousebutton == "Hotkey2")
	if greater then
		-- Greater Blessings
		local minExpire, minUnit, minSpell, maxSpell = 600, nil, nil, nil
		for i = 1, SHAMANPOWER_MAXCLASSES do
			local classMinExpire, classNeedsBuff, classMinUnitPenalty, classMinUnit, classMinSpell, classMaxSpell = 600, true, 600, nil, nil, nil
			for j = 1, SHAMANPOWER_MAXPERCLASS do
				if (classes[i] and classes[i][j]) then
					local unit = classes[i][j]
					local spellID, gspellID = self:GetSpellID(i, unit.name)
					local spell = self.Spells[spellID]
					local gspell = self.GSpells[gspellID]
					if (not unit.specialbuff) and (IsSpellInRange(gspell, unit.unitid) == 1) and not UnitIsDeadOrGhost(unit.unitid) then
						local penalty = 0
						local buffExpire, buffDuration, buffName = self:IsBuffActive(spell, gspell, unit.unitid)
						local nSpell, gSpell = self:CanBuffBlessing(spellID, gspellID, unit.unitid)
						local recipients = #classes[i]

						if (self.AutoBuffedList[unit.name] and now - self.AutoBuffedList[unit.name] < recipients*1.65) then
							penalty = SHAMANPOWER_GREATERBLESSINGDURATION
						end

						if (self.PreviousAutoBuffedUnit and (unit.hasbuff and unit.hasbuff > minExpire) and unit.name == self.PreviousAutoBuffedUnit.name and GetNumGroupMembers() > 0) then
							penalty = SHAMANPOWER_GREATERBLESSINGDURATION
						else
							penalty = 0
						end
						-- If normal blessing - set duration to zero and buff it - but only if an alternate blessing isn't assigned
						if buffName and buffName == spell and spellID == gspellID then
							buffExpire = 0
							penalty = 0
						end
						
						if not self.isWrath and gspellID == 4 then
							-- If for some reason the targeted unit is in combat and there is a tank present
							-- in the Class Group then disable Greater Blessing of Salvation for this unit.
							if (not self.opt.SalvInCombat) and UnitAffectingCombat(unit.unitid) and classmaintanks[classID] then
								buffExpire = 9999
								penalty = 9999
							end
							-- Skip tanks if Salv is assigned. This allows autobuff to work since some tanks
							-- have addons and/or scripts to auto cancel Salvation. Prevents getting stuck
							-- buffing a tank when auto buff rotates among players in the class group.
							if unit.tank then
								buffExpire = 9999
								penalty = 9999
							end
						end
						
						if (not ShamanPower.petsShareBaseClass) and unit.unitid:find("pet") then
							buffExpire = 9999
							penalty = 9999
						end

						-- Refresh any greater blessing under a 10 min duration
						if ((not buffExpire or buffExpire < classMinExpire and buffExpire < SHAMANPOWER_GREATERBLESSINGDURATION) and classMinExpire > 0) then
							if (penalty < classMinUnitPenalty) then
								classMinUnit = unit
								classMinUnitPenalty = penalty
							end

							classMaxSpell = gSpell
							classMinExpire = (buffExpire or 0)
						end
					elseif (UnitIsVisible(unit.unitid) == false and not UnitIsAFK(unit.unitid) and UnitIsConnected(unit.unitid)) and (IsInRaid() == false or #classes[i] > 3) then
						classNeedsBuff = false
					end
				end
			end
			if ((classNeedsBuff or not self.opt.autobuff.waitforpeople) and classMinExpire + classMinUnitPenalty < minExpire and minExpire > 0) then
				minExpire = classMinExpire + classMinUnitPenalty
				minUnit = classMinUnit
				maxSpell = classMaxSpell
			end
		end
		if (minExpire < 600) then
			local button = self.autoButton
			button:SetAttribute("unit", minUnit.unitid)
			button:SetAttribute("spell", maxSpell)
			self.AutoBuffedList[minUnit.name] = now
			self.PreviousAutoBuffedUnit = minUnit
			C_Timer.After(
				1.0,
				function()
					local _, unitClass = UnitClass(minUnit.unitid)
					local cID = self.ClassToID[unitClass]
					self:UpdateButton(nil, "ShamanPowerC" .. cID, cID)
					self:ButtonsUpdate()
				end
			)
		end
	else
		-- Normal Blessings
		local minExpire, minUnit, minSpell = 240, nil, nil
		for _, unit in ipairs(roster) do
			local spellID, gspellID = self:GetSpellID(self:GetClassID(unit.class), unit.name)
			local spell = self.Spells[spellID]
			local spell2 = self.GSpells[spellID]
			local gspell = self.GSpells[gspellID]
			if (IsSpellInRange(spell, unit.unitid) == 1) and not UnitIsDeadOrGhost(unit.unitid) then
				local penalty = 0
				local buffExpire, buffDuration, buffName = self:IsBuffActive(spell, spell2, unit.unitid)
				local nSpell, gSpell = self:CanBuffBlessing(spellID, gspellID, unit.unitid)
				local recipients = #roster

				if (self.AutoBuffedList[unit.name] and now - self.AutoBuffedList[unit.name] < recipients*1.65) then
					penalty = SHAMANPOWER_NORMALBLESSINGDURATION
				end
				if (self.PreviousAutoBuffedUnit and (unit.hasbuff and unit.hasbuff > minExpire) and unit.name == self.PreviousAutoBuffedUnit.name and GetNumGroupMembers() > 0) then
					penalty = SHAMANPOWER_NORMALBLESSINGDURATION
				else
					penalty = 0
				end
				-- If a Greater Blessing falls below 4 min, refresh it with a Normal Blessing
				if buffName and buffName == gspell and buffExpire > minExpire then
					penalty = SHAMANPOWER_NORMALBLESSINGDURATION
				elseif buffName and buffName == gspell and buffExpire < minExpire then
					penalty = 0
				end
				if (buffName and buffName == gspell) then
					-- If we're using Blessing of Sacrifice then set the expiration to match Normal Blessings so Auto Buff works.
					if not self.isWrath and (spell == self.Spells[7]) then
						buffExpire = 270
						penalty = 0
					-- Alternate Blessing assigned then always allow buffing over a Greater Blessing: Set duration to zero and buff it.
					elseif (self.isWrath and spellID ~= gspellID) or (spell ~= self.Spells[7] and spellID ~= gspellID) then
						buffExpire = 0
						penalty = 0
					end
				end
				if IsInRaid() then
					-- Skip tanks if Salv is assigned. This allows autobuff to work since some tanks
					-- have addons and/or scripts to auto cancel Salvation. Tanks shouldn't have a
					-- Normal Blessing of Salvation but sometimes there are way more Paladins in a
					-- Raid than there are buffs to assign so an Alternate Blessing might not be in
					-- use to wipe Salvation from a tank. Prevents getting stuck buffing a tank when
					-- auto buff rotates among players in the class group.
					
					if unit.tank then
						if not self.isWrath and (spellID == 4 and not self.opt.SalvInCombat) then
							buffExpire = 9999
							penalty = 9999
						end
					end
				end
				-- Refresh any blessing under a 4 min duration
				if ((not buffExpire or buffExpire + penalty < minExpire and buffExpire < SHAMANPOWER_NORMALBLESSINGDURATION) and minExpire > 0) then
					minExpire = (buffExpire or 0) + penalty
					minUnit = unit
					minSpell = nSpell
				end
			end
		end
		if (minExpire < 240) then
			local button = self.autoButton
			button:SetAttribute("unit", minUnit.unitid)
			button:SetAttribute("spell", minSpell)
			self.AutoBuffedList[minUnit.name] = now
			self.PreviousAutoBuffedUnit = minUnit
			C_Timer.After(
				1.0,
				function()
					local _, unitClass = UnitClass(minUnit.unitid)
					local cID = self.ClassToID[unitClass]
					if cID then
						self:UpdateButton(nil, "ShamanPowerC" .. cID, cID)
					end
					self:ButtonsUpdate()
				end
			)
		end
	end
end

function ShamanPower:AutoBuffClear(button, mousebutton)
	if InCombatLockdown() then return end

	local button = self.autoButton
	if not button:GetAttribute("unit") == nil then
		local abUnit = button:GetAttribute("unit")
		local abName = UnitName(abUnit)
		for _, unit in ipairs(roster) do
			if unit.unitid == abUnit and unit.name == abName then
				local classIndex = self.ClassToID[unit.class]
				self:UpdateButton(button, "ShamanPowerC" .. classIndex, classIndex)
			end
		end
	end
	button:SetAttribute("unit", nil)
	button:SetAttribute("spell", nil)
end

function ShamanPower:ApplySkin()
	local border = LSM3:Fetch("border", self.opt.border)
	local background = LSM3:Fetch("background", self.opt.skin)
	local tmp = {bgFile = background, edgeFile = border, tile = false, tileSize = 8, edgeSize = 8, insets = {left = 0, right = 0, top = 0, bottom = 0}}
	if BackdropTemplateMixin then
		Mixin(ShamanPowerAura, BackdropTemplateMixin)
		Mixin(ShamanPowerRF, BackdropTemplateMixin)
		Mixin(ShamanPowerAuto, BackdropTemplateMixin)
	end
	ShamanPowerAura:SetBackdrop(tmp)
	ShamanPowerRF:SetBackdrop(tmp)
	-- Only apply backdrop to totem bar if not hidden
	if self.opt.hideTotemBarFrame then
		ShamanPowerAuto:SetBackdrop(nil)
	else
		ShamanPowerAuto:SetBackdrop(tmp)
	end
	for cbNum = 1, SHAMANPOWER_MAXCLASSES do
		local cButton = self.classButtons[cbNum]
		if BackdropTemplateMixin then
			Mixin(cButton, BackdropTemplateMixin)
		end
		cButton:SetBackdrop(tmp)
		local pButtons = self.playerButtons[cbNum]
		for pbNum = 1, SHAMANPOWER_MAXPERCLASS do
			local pButton = pButtons[pbNum]
			if BackdropTemplateMixin then
				Mixin(pButton, BackdropTemplateMixin)
			end
			pButton:SetBackdrop(tmp)
		end
	end
end

function ShamanPower:ApplyBackdrop(button, preset)
	-- button coloring: preset
	if BackdropTemplateMixin then
		Mixin(button, BackdropTemplateMixin)
	end
	button:SetBackdropColor(preset["r"], preset["g"], preset["b"], preset["t"])
end

function ShamanPower:UpdateTotemBarFrame()
	-- Show or hide the totem bar frame (background/border)
	if not ShamanPowerAuto then return end

	if self.opt.hideTotemBarFrame then
		-- Hide the frame - set backdrop to nil
		ShamanPowerAuto:SetBackdrop(nil)
	else
		-- Show the frame - reapply skin
		self:ApplySkin()
	end
end

function ShamanPower:UpdateCooldownBarFrame()
	-- Show or hide the cooldown bar frame (background/border)
	if not self.cooldownBar then return end

	if self.opt.hideCooldownBarFrame then
		-- Hide the frame
		self.cooldownBar:SetBackdrop(nil)
	else
		-- Show the frame
		self.cooldownBar:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 12,
			insets = { left = 2, right = 2, top = 2, bottom = 2 }
		})
		self.cooldownBar:SetBackdropColor(0, 0, 0, 0.7)
		self.cooldownBar:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
	end
end

function ShamanPower:SetSeal(seal)
	-- Shamans don't have seals, no-op
	self.opt.seal = seal or 0
end

function ShamanPower:SealCycle()
	-- Shamans don't have seals, no-op
	-- Could be repurposed for weapon enchant cycling later
end

function ShamanPower:SealCycleBackward()
	-- Shamans don't have seals, no-op
	-- Could be repurposed for weapon enchant cycling later
end

function ShamanPower:RFAssign()
	-- Shamans don't have Righteous Fury, no-op
	-- Could be repurposed for Lightning Shield or similar later
end

function ShamanPower:SealAssign(seal)
	-- Shamans don't have seals, no-op
	self.opt.seal = seal or 0
end

function ShamanPower:AutoAssign()
	if InCombatLockdown() then return end

	local shift = (IsShiftKeyDown() and ShamanPowerBlessingsFrame:IsMouseOver())
	local precedence
	if IsInRaid() and not (IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and IsInInstance() or shift) then
		if self.isWrath then
			precedence = {6, 1, 3, 2, 4, 5, 7} -- fire, devotion, concentration, retribution, shadow, frost, crusader
		else
			precedence = {6, 1, 3, 2, 4, 5, 7, 8} -- fire, devotion, concentration, retribution, shadow, frost, sanctity, crusader
		end
	else
		if self.isWrath then
			precedence = {1, 3, 2, 4, 5, 6, 7} -- devotion, concentration, retribution, shadow, frost, fire, crusader
		else
			precedence = {1, 3, 2, 4, 5, 6, 7, 8} -- devotion, concentration, retribution, shadow, frost, fire, sanctity, crusader
		end
	end
	if self:CheckLeader(self.player) or AC_Leader == false then
		WisdomPallys, MightPallys, KingsPallys, SalvPallys, LightPallys, SancPallys = {}, {}, {}, {}, {}, {}
		self:ClearAssignments(self.player)
		self:SendMessage("CLEAR")
		self:AutoAssignBlessings(shift)
		self:UpdateRoster()
		C_Timer.After(
			0.25,
			function()
				for name in pairs(AllShamans) do
					local s = ""
					local BuffInfo = ShamanPower_Assignments[name]
					if not BuffInfo then BuffInfo = {} end
					for i = 1, SHAMANPOWER_MAXCLASSES do
						if not BuffInfo[i] or BuffInfo[i] == 0 then
							s = s .. "n"
						else
							s = s .. BuffInfo[i]
						end
					end
					self:SendMessage("PASSIGN " .. name .. "@" .. s)
				end
				C_Timer.After(
					0.25,
					function()
						self:AutoAssignAuras(precedence)
						self:UpdateLayout()
					end
				)
			end
		)
	end
end

function ShamanPower:StorePreset()
	ShamanPower_SavedPresets = {}
	ShamanPower_SavedPresets["ShamanPower_Assignments"] = {[0] = {}}
	ShamanPower_SavedPresets["ShamanPower_NormalAssignments"] = {[0] = {}}
	ShamanPower_SavedPresets["ShamanPower_AuraAssignments"] = {[0] = {}}
	--save current Assignments to preset
	ShamanPower_SavedPresets["ShamanPower_Assignments"][0] = tablecopy(ShamanPower_Assignments)
	ShamanPower_SavedPresets["ShamanPower_NormalAssignments"][0] = tablecopy(ShamanPower_NormalAssignments)
	ShamanPower_SavedPresets["ShamanPower_AuraAssignments"][0] = tablecopy(ShamanPower_AuraAssignments)
end

function ShamanPower:LoadPreset()
	-- if leader, load preset and publish to other pallys if possible
	if not ShamanPower:CheckLeader(ShamanPower.player) then return end

	ShamanPower:ClearAssignments(ShamanPower.player, true)
	ShamanPower:SendMessage("CLEAR SKIP")
	ShamanPower_Assignments = tablecopy(ShamanPower_SavedPresets["ShamanPower_Assignments"][0])
	ShamanPower_NormalAssignments = tablecopy(ShamanPower_SavedPresets["ShamanPower_NormalAssignments"][0])
	ShamanPower_AuraAssignments = tablecopy(ShamanPower_SavedPresets["ShamanPower_AuraAssignments"][0])
	C_Timer.After(
		0.25,
		function() -- send Class-Assignments
			for name in pairs(AllShamans) do
				local s = ""
				local BuffInfo = ShamanPower_Assignments[name]
				if not BuffInfo then BuffInfo = {} end
				for i = 1, SHAMANPOWER_MAXCLASSES do
					if not BuffInfo[i] or BuffInfo[i] == 0 then
						s = s .. "n"
					else
						s = s .. BuffInfo[i]
					end
				end
				ShamanPower:SendMessage("PASSIGN " .. name .. "@" .. s)
			end
			C_Timer.After(
				0.25,
				function() -- send Single-Assignments
					for pname, passignments in pairs(ShamanPower_NormalAssignments) do
						if (AllShamans[pname] and ShamanPower:GetUnitIdByName(pname) and passignments) then
							for class, cassignments in pairs(passignments) do
								if cassignments then 
									for tname, value in pairs(cassignments) do
										ShamanPower:SendNormalBlessings(pname, class, tname)
									end
								end
							end
						end
					end
					C_Timer.After(
						0.25,
						function()
							ShamanPower:UpdateLayout()
							ShamanPower:UpdateRoster()
						end
					)
				end
			)
		end
	)
end

function ShamanPower:CalcSkillRanks(name)
	-- For Shamans, return what totems they have available per element
	-- Returns: earth, fire, water, air (boolean flags)
	local earth, fire, water, air = false, false, false, false
	if AllShamans[name] then
		if AllShamans[name][1] and next(AllShamans[name][1]) then earth = true end
		if AllShamans[name][2] and next(AllShamans[name][2]) then fire = true end
		if AllShamans[name][3] and next(AllShamans[name][3]) then water = true end
		if AllShamans[name][4] and next(AllShamans[name][4]) then air = true end
	end
	return earth, fire, water, air
end

function ShamanPower:AutoAssignBlessings(shift)
	-- Smart Shaman Auto-Assign: Assign totems based on party composition and shaman spec
	-- Totem indices:
	-- Earth: 1=Strength of Earth, 2=Stoneskin
	-- Fire: 1=Totem of Wrath, 2=Searing, 5=Flametongue
	-- Water: 1=Mana Spring, 2=Healing Stream, 3=Mana Tide
	-- Air: 1=Windfury, 2=Grace of Air, 3=Wrath of Air

	-- First, analyze party composition for each group
	local groupComposition = self:AnalyzeGroupComposition()

	-- Get shamans organized by their party group
	local shamansByGroup = {}
	for name in pairs(AllShamans) do
		local subgroup = AllShamans[name].subgroup or 1
		if not shamansByGroup[subgroup] then
			shamansByGroup[subgroup] = {}
		end
		table.insert(shamansByGroup[subgroup], name)
	end

	-- Track which totems are already assigned in each group (to avoid duplicates)
	local assignedInGroup = {}
	for i = 1, 8 do
		assignedInGroup[i] = {
			[1] = {},  -- Earth totems assigned
			[2] = {},  -- Fire totems assigned
			[3] = {},  -- Water totems assigned
			[4] = {},  -- Air totems assigned
		}
	end

	-- Assign totems to each shaman
	for name in pairs(AllShamans) do
		local canAssign = (name == self.player) or self:CanControl(name)
		if canAssign then
			local subgroup = AllShamans[name].subgroup or 1
			local comp = groupComposition[subgroup] or {melee = 0, caster = 0, agiUsers = 0, total = 0}

			if not ShamanPower_Assignments[name] then
				ShamanPower_Assignments[name] = {}
			end

			-- Determine shaman spec
			local isElemental = self:ShamanHasTotemOfWrath(name)
			local isResto = self:ShamanHasManaTide(name)

			-- === EARTH TOTEM ===
			local earthTotem = 1  -- Default: Strength of Earth
			if not assignedInGroup[subgroup][1][1] then
				earthTotem = 1  -- Strength of Earth
				assignedInGroup[subgroup][1][1] = true
			elseif not assignedInGroup[subgroup][1][2] then
				earthTotem = 2  -- Stoneskin (if SoE already assigned)
				assignedInGroup[subgroup][1][2] = true
			end
			ShamanPower_Assignments[name][1] = earthTotem

			-- === FIRE TOTEM ===
			local fireTotem = 2  -- Default: Searing
			if isElemental and not assignedInGroup[subgroup][2][1] then
				fireTotem = 1  -- Totem of Wrath for Elemental shamans
				assignedInGroup[subgroup][2][1] = true
			elseif comp.caster > comp.melee and not assignedInGroup[subgroup][2][5] then
				fireTotem = 5  -- Flametongue for caster groups
				assignedInGroup[subgroup][2][5] = true
			else
				if not assignedInGroup[subgroup][2][2] then
					fireTotem = 2  -- Searing
					assignedInGroup[subgroup][2][2] = true
				end
			end
			ShamanPower_Assignments[name][2] = fireTotem

			-- === WATER TOTEM ===
			-- Mana Spring preferred, Healing Stream as fallback (Mana Tide is a cooldown, not auto-assigned)
			local waterTotem = 1  -- Default: Mana Spring
			if not assignedInGroup[subgroup][3][1] then
				waterTotem = 1  -- Mana Spring
				assignedInGroup[subgroup][3][1] = true
			elseif not assignedInGroup[subgroup][3][2] then
				waterTotem = 2  -- Healing Stream (if Mana Spring already assigned)
				assignedInGroup[subgroup][3][2] = true
			end
			ShamanPower_Assignments[name][3] = waterTotem

			-- === AIR TOTEM ===
			-- Windfury for warriors/enh shamans, Grace of Air for hunters/rogues/ferals, Wrath of Air for casters
			local airTotem = 1  -- Default: Windfury
			if comp.caster > comp.melee and comp.caster > comp.agiUsers then
				-- Caster-heavy group
				if not assignedInGroup[subgroup][4][3] then
					airTotem = 3  -- Wrath of Air
					assignedInGroup[subgroup][4][3] = true
				end
			elseif comp.agiUsers > 0 and comp.agiUsers >= comp.melee then
				-- AGI users (hunters, rogues, feral druids) prefer Grace of Air
				if not assignedInGroup[subgroup][4][2] then
					airTotem = 2  -- Grace of Air
					assignedInGroup[subgroup][4][2] = true
				elseif not assignedInGroup[subgroup][4][1] then
					airTotem = 1  -- Windfury as backup
					assignedInGroup[subgroup][4][1] = true
				end
			else
				-- Melee group (warriors, paladins, etc.) want Windfury
				if not assignedInGroup[subgroup][4][1] then
					airTotem = 1  -- Windfury
					assignedInGroup[subgroup][4][1] = true
				elseif not assignedInGroup[subgroup][4][2] then
					airTotem = 2  -- Grace of Air as backup
					assignedInGroup[subgroup][4][2] = true
				end
			end
			ShamanPower_Assignments[name][4] = airTotem
		end
	end

	self:SendMessage("SHPWR_ASSIGNMENTSUPDATED")
	self:UpdateRoster()
	self:Print("Totems have been smart-assigned based on party composition.")
end

-- Analyze the composition of each party group
function ShamanPower:AnalyzeGroupComposition()
	local composition = {}
	for i = 1, 8 do
		composition[i] = {melee = 0, caster = 0, agiUsers = 0, total = 0}
	end

	local numMembers = GetNumGroupMembers()
	local isRaid = IsInRaid()

	if numMembers == 0 then
		-- Solo
		composition[1].total = 1
		return composition
	end

	for i = 1, numMembers do
		local unit = isRaid and ("raid" .. i) or (i == numMembers and "player" or ("party" .. i))
		if UnitExists(unit) then
			local _, class = UnitClass(unit)
			local subgroup = 1
			if isRaid then
				local name, _, sg = GetRaidRosterInfo(i)
				subgroup = sg or 1
			end

			composition[subgroup].total = composition[subgroup].total + 1

			-- Classify by class
			if class == "WARRIOR" or class == "PALADIN" then
				-- Warriors and Paladins benefit from Windfury
				composition[subgroup].melee = composition[subgroup].melee + 1
			elseif class == "ROGUE" then
				-- Rogues want Grace of Air (AGI)
				composition[subgroup].agiUsers = composition[subgroup].agiUsers + 1
			elseif class == "HUNTER" then
				-- Hunters want Grace of Air (AGI)
				composition[subgroup].agiUsers = composition[subgroup].agiUsers + 1
			elseif class == "DRUID" then
				-- Druids: check if they're feral (melee/AGI) or caster
				if self:IsDruidFeral(unit) then
					composition[subgroup].agiUsers = composition[subgroup].agiUsers + 1
				else
					composition[subgroup].caster = composition[subgroup].caster + 1
				end
			elseif class == "SHAMAN" then
				-- Shamans: Enhancement = melee, Elemental/Resto = caster
				if self:IsShamanEnhancement(unit) then
					composition[subgroup].melee = composition[subgroup].melee + 1
				else
					composition[subgroup].caster = composition[subgroup].caster + 1
				end
			elseif class == "MAGE" or class == "WARLOCK" or class == "PRIEST" then
				-- Pure casters
				composition[subgroup].caster = composition[subgroup].caster + 1
			end
		end
	end

	return composition
end

-- Check if a druid is feral (cat/bear) vs caster (balance/resto)
function ShamanPower:IsDruidFeral(unit)
	if not UnitExists(unit) then return false end

	-- Check power type: Ferals in form use rage (bear) or energy (cat)
	local powerType = UnitPowerType(unit)
	if powerType == 1 or powerType == 3 then  -- Rage or Energy
		return true
	end

	-- Check if they have Mangle or other feral abilities (by checking buffs/debuffs)
	-- Ferals often have Leader of the Pack buff
	for i = 1, 40 do
		local name = UnitBuff(unit, i)
		if not name then break end
		if name == "Leader of the Pack" then
			return true
		end
	end

	-- Default: assume caster if we can't tell
	return false
end

-- Check if a shaman is Enhancement spec
function ShamanPower:IsShamanEnhancement(unit)
	if not UnitExists(unit) then return false end

	-- Enhancement shamans dual wield or use 2H with Stormstrike
	-- Check if they have Stormstrike buff/ability
	for i = 1, 40 do
		local name = UnitBuff(unit, i)
		if not name then break end
		if name == "Unleashed Rage" or name == "Shamanistic Rage" then
			return true
		end
	end

	-- Check power type isn't mana-heavy casting (enhancement still uses mana but differently)
	-- This is a rough heuristic
	return false
end

-- Check if a shaman has Totem of Wrath (Elemental talent)
function ShamanPower:ShamanHasTotemOfWrath(shamanName)
	if AllShamans[shamanName] and AllShamans[shamanName].Fire then
		-- Check if they have ToW in their available fire totems
		for totemID, _ in pairs(AllShamans[shamanName].Fire or {}) do
			if totemID == 1 then  -- ToW is index 1 in fire totems
				return true
			end
		end
	end
	-- For self, check if we know the spell
	if shamanName == self.player then
		return IsSpellKnown(30706)  -- Totem of Wrath spell ID
	end
	return false
end

-- Check if a shaman has Mana Tide (Resto talent)
function ShamanPower:ShamanHasManaTide(shamanName)
	if AllShamans[shamanName] and AllShamans[shamanName].Water then
		-- Check if they have Mana Tide in their available water totems
		for totemID, _ in pairs(AllShamans[shamanName].Water or {}) do
			if totemID == 3 then  -- Mana Tide is index 3 in water totems
				return true
			end
		end
	end
	-- For self, check if we know the spell
	if shamanName == self.player then
		return IsSpellKnown(16190)  -- Mana Tide Totem spell ID
	end
	return false
end

function ShamanPower:AssignNewBuffRatings(BuffPallys)
	-- No-op for Shamans (Paladin blessing rating system not used)
end

function ShamanPower:DownRateDefaultBuffs(name, rating)
	-- No-op for Shamans (Paladin blessing rating system not used)
end

function ShamanPower:SelectBuffsByClass(pallycount, class, prioritylist)
	-- No-op for Shamans (Paladin class-based blessing system not used)
end

function ShamanPower:BuffSelections(buff, class, pallys)
	-- No-op for Shamans (Paladin blessing selection not used)
	return ""
end

function ShamanPower:PallyAvailable(pally, pallys)
	-- No-op for Shamans - kept for compatibility
	return false
end

-- Earth Shield target selection dropdown
function ShamanPowerAuraButton_OnClick(btn, mouseBtn)
	if InCombatLockdown() then return end

	local _, _, pnum = strfind(btn:GetName(), "ShamanPowerBlessingsFramePlayer(.+)Aura1")
	pnum = pnum + 0
	local pname = _G["ShamanPowerBlessingsFramePlayer" .. pnum .. "Name"]:GetText()
	if not ShamanPower:CanControl(pname) then
		return false
	end

	-- Check if this shaman has Earth Shield
	if not AllShamans[pname] or not AllShamans[pname].hasEarthShield then
		return false
	end

	if (mouseBtn == "RightButton") then
		-- Right click clears the assignment
		ShamanPower_EarthShieldAssignments[pname] = nil
		ShamanPower:SendMessage("ESASSIGN " .. pname .. " NONE")
		ShamanPower:UpdateLayout()
		if pname == ShamanPower.player then
			ShamanPower:UpdateEarthShieldMacroButton()
		end
	else
		-- Left click opens dropdown
		ShamanPower:ShowEarthShieldDropdown(btn, pname)
	end
end

function ShamanPowerAuraButton_OnMouseWheel(btn, arg1)
	-- Not used for Earth Shield - use dropdown instead
end

-- Store current shaman for dropdown callback
ShamanPower.currentEarthShieldShaman = nil

-- Show dropdown menu for Earth Shield target selection
function ShamanPower:ShowEarthShieldDropdown(anchor, shamanName)
	-- Store the shaman name for the initialization function
	self.currentEarthShieldShaman = shamanName

	-- Create dropdown frame if it doesn't exist
	if not self.earthShieldDropdown then
		self.earthShieldDropdown = CreateFrame("Frame", "ShamanPowerESDropdown", UIParent, "UIDropDownMenuTemplate")
	end

	-- Initialize and show
	UIDropDownMenu_Initialize(self.earthShieldDropdown, ShamanPower_EarthShieldDropdown_Initialize, "MENU")
	ToggleDropDownMenu(1, nil, self.earthShieldDropdown, anchor, 0, 0)
end

-- Dropdown initialization function
function ShamanPower_EarthShieldDropdown_Initialize(self, level)
	local shamanName = ShamanPower.currentEarthShieldShaman
	if not shamanName then return end

	level = level or 1

	local info = UIDropDownMenu_CreateInfo()

	-- Add "None" option at top
	info.text = "None"
	info.notCheckable = true
	info.func = function()
		ShamanPower_EarthShieldAssignments[shamanName] = nil
		ShamanPower:SendMessage("ESASSIGN " .. shamanName .. " NONE")
		ShamanPower:UpdateLayout()
		if shamanName == ShamanPower.player then
			ShamanPower:UpdateEarthShieldMacroButton()
		end
		CloseDropDownMenus()
	end
	UIDropDownMenu_AddButton(info, level)

	-- Add separator
	info = UIDropDownMenu_CreateInfo()
	info.text = ""
	info.disabled = true
	info.notCheckable = true
	UIDropDownMenu_AddButton(info, level)

	-- Get raid/party members
	local members = {}
	local numMembers = GetNumGroupMembers()
	local inRaid = IsInRaid()

	if numMembers > 0 then
		if inRaid then
			for i = 1, numMembers do
				local name, _, subgroup, _, _, class = GetRaidRosterInfo(i)
				if name then
					table.insert(members, {name = name, class = class, subgroup = subgroup})
				end
			end
		else
			-- Party
			table.insert(members, {name = UnitName("player"), class = select(2, UnitClass("player")), subgroup = 1})
			for i = 1, 4 do
				local unit = "party" .. i
				if UnitExists(unit) then
					local name = UnitName(unit)
					local class = select(2, UnitClass(unit))
					table.insert(members, {name = name, class = class, subgroup = 1})
				end
			end
		end
	else
		-- Solo
		table.insert(members, {name = UnitName("player"), class = select(2, UnitClass("player")), subgroup = 1})
	end

	-- Sort by subgroup then name
	table.sort(members, function(a, b)
		if a.subgroup ~= b.subgroup then
			return a.subgroup < b.subgroup
		end
		return a.name < b.name
	end)

	-- Add members to menu
	local currentGroup = 0
	for _, member in ipairs(members) do
		-- Add group header if new group (in raid)
		if inRaid and member.subgroup ~= currentGroup then
			currentGroup = member.subgroup
			info = UIDropDownMenu_CreateInfo()
			info.text = "Group " .. currentGroup
			info.isTitle = true
			info.notCheckable = true
			UIDropDownMenu_AddButton(info, level)
		end

		-- Add player entry
		local classColor = RAID_CLASS_COLORS[member.class] or {r = 1, g = 1, b = 1}
		local isAssigned = (ShamanPower_EarthShieldAssignments[shamanName] == member.name)

		info = UIDropDownMenu_CreateInfo()
		info.text = member.name
		info.colorCode = ("|cff%02x%02x%02x"):format(classColor.r * 255, classColor.g * 255, classColor.b * 255)
		info.checked = isAssigned
		info.func = function()
			ShamanPower_EarthShieldAssignments[shamanName] = member.name
			ShamanPower:SendMessage("ESASSIGN " .. shamanName .. " " .. member.name)
			ShamanPower:UpdateLayout()
			ShamanPower:UpdateMiniTotemBar()
			ShamanPower:UpdateEarthShieldButton()
			if shamanName == ShamanPower.player then
				ShamanPower:UpdateEarthShieldMacroButton()
			end
			CloseDropDownMenus()
		end
		UIDropDownMenu_AddButton(info, level)
	end
end

function ShamanPower:HasAura(name, test)
	-- Shamans don't have auras like Paladins - this is kept for compatibility
	if not AllShamans[name] or not AllShamans[name].AuraInfo then
		return false
	end
	if (not AllShamans[name].AuraInfo[test]) or (AllShamans[name].AuraInfo[test].rank == 0) then
		return false
	end
	return true
end

function ShamanPower:PerformAuraCycle(name, skipzero)
	if not ShamanPower_AuraAssignments[name] then
		ShamanPower_AuraAssignments[name] = 0
	end
	local cur = ShamanPower_AuraAssignments[name]
	for test = cur + 1, SHAMANPOWER_MAXAURAS do
		if self:HasAura(name, test) then
			cur = test
			do
				break
			end
		end
	end
	if (cur == ShamanPower_AuraAssignments[name]) then
		if skipzero and self:HasAura(name, 1) then
			cur = 1
		else
			cur = 0
		end
	end
	ShamanPower_AuraAssignments[name] = cur
	local msgQueue
	msgQueue =
		C_Timer.NewTimer(
		2.0,
		function()
			self:SendMessage("AASSIGN " .. name .. " " .. ShamanPower_AuraAssignments[name])
			self:UpdateLayout()
			msgQueue:Cancel()
		end
	)
end

function ShamanPower:PerformAuraCycleBackwards(name, skipzero)
	if not ShamanPower_AuraAssignments[name] then
		ShamanPower_AuraAssignments[name] = 0
	end
	local cur = ShamanPower_AuraAssignments[name] - 1
	if (cur < 0) or (skipzero and (cur < 1)) then
		cur = SHAMANPOWER_MAXAURAS
	end
	for test = cur, 0, -1 do
		if self:HasAura(name, test) or (test == 0 and not skipzero) then
			ShamanPower_AuraAssignments[name] = test
			local msgQueue
			msgQueue =
				C_Timer.NewTimer(
				2.0,
				function()
					self:SendMessage("AASSIGN " .. name .. " " .. ShamanPower_AuraAssignments[name])
					self:UpdateLayout()
					msgQueue:Cancel()
				end
			)
			do
				break
			end
		end
	end
end

function ShamanPower:IsAuraActive(aura)
	local bFound = false
	local bSelfCast = false
	if (aura and aura > 0) then
		local spell = self.Auras[aura]
		local j = 1
		local buffName, _, _, _, _, buffExpire, castBy = UnitBuff("player", j)
		while buffExpire do
			if buffName == spell then
				bFound = true
				bSelfCast = (castBy == "player")
				do
					break
				end
			end
			j = j + 1
			buffName, _, _, _, _, buffExpire, castBy = UnitBuff("player", j)
		end
	end
	return bFound, bSelfCast
end

function ShamanPower:UpdateAuraButton(aura)
	local pallys = {}
	local auraBtn = _G["ShamanPowerAura"]
	local auraIcon = _G["ShamanPowerAuraIcon"]
	if (aura and aura > 0) then
		for name in pairs(AllShamans) do
			if (name ~= self.player) and (AllShamans[name].subgroup == AllShamans[self.player].subgroup) and (aura == ShamanPower_AuraAssignments[name]) then
				tinsert(pallys, name)
			end
		end
		local name, _, icon = GetSpellInfo(self.Auras[aura])
		if (not InCombatLockdown()) then
			auraIcon:SetTexture(icon)
			auraBtn:SetAttribute("spell", name)
		end
	else
		if (not InCombatLockdown()) then
			auraIcon:SetTexture(nil)
			auraBtn:SetAttribute("spell", "")
		end
	end
	-- only support two lines of text, so only deal with the first two players in the list...
	local player1 = _G["ShamanPowerAuraPlayer1"]
	if pallys[1] then
		local shortpally1 = Ambiguate(pallys[1], "short")
		player1:SetText(shortpally1)
		player1:SetTextColor(1.0, 1.0, 1.0)
	else
		player1:SetText("")
	end
	local player2 = _G["ShamanPowerAuraPlayer2"]
	if pallys[2] then
		local shortpally2 = Ambiguate(pallys[2], "short")
		player2:SetText(shortpally2)
		player2:SetTextColor(1.0, 1.0, 1.0)
	else
		player2:SetText("")
	end
	local btnColour = self.opt.cBuffGood
	local active, selfCast = self:IsAuraActive(aura)
	if (active == false) then
		btnColour = self.opt.cBuffNeedAll
	elseif (selfCast == false) then
		btnColour = self.opt.cBuffNeedSome
	end
	self:ApplyBackdrop(auraBtn, btnColour)
end

function ShamanPower:AutoAssignAuras(precedence)
	local pallys = {}
	for i = 1, 8 do
		pallys[("subgroup%d"):format(i)] = {}
	end
	for name in pairs(AllShamans) do
		if AllShamans[name].subgroup then
			local subgroup = "subgroup" .. AllShamans[name].subgroup
			if self:CanControl(name) then
				tinsert(pallys[subgroup], name)
			end
		end
	end
	for _, subgroup in pairs(pallys) do
		for _, aura in pairs(precedence) do
			local assignee = ""
			local testRank = 0
			local testTalent = 0
			for _, pally in pairs(subgroup) do
				if self:HasAura(pally, aura) and (AllShamans[pally].AuraInfo[aura].rank >= testRank) then
					testRank = AllShamans[pally].AuraInfo[aura].rank
					if AllShamans[pally].AuraInfo[aura].talent >= testTalent then
						testTalent = AllShamans[pally].AuraInfo[aura].talent
						assignee = pally
					end
				end
			end
			if assignee ~= "" then
				for i, name in pairs(subgroup) do
					if assignee == name then
						tremove(subgroup, i)
						ShamanPower_AuraAssignments[assignee] = aura
						self:SendMessage("AASSIGN " .. assignee .. " " .. aura)
					end
				end
			end
		end
	end
end

-- ============================================================================
-- Keybinding Setup (using SetOverrideBindingClick for secure button clicks)
-- ============================================================================

-- Map binding names to button names
ShamanPower.KeybindButtons = {
	["SHAMANPOWER_DROPALL"] = "ShamanPowerAutoDropAll",
	["SHAMANPOWER_EARTH_TOTEM"] = "ShamanPowerTotemBtn1",
	["SHAMANPOWER_FIRE_TOTEM"] = "ShamanPowerTotemBtn2",
	["SHAMANPOWER_WATER_TOTEM"] = "ShamanPowerTotemBtn3",
	["SHAMANPOWER_AIR_TOTEM"] = "ShamanPowerTotemBtn4",
	["SHAMANPOWER_EARTH_SHIELD"] = "ShamanPowerEarthShieldBtn",
	["SHAMANPOWER_TOTEMIC_CALL"] = "ShamanPowerTotemicCallBtn",
}

-- Map cooldown bar binding names to cooldownType values
-- cooldownType: 1=Shield, 2=Recall, 3=Ankh, 4=NS, 5=MTT, 6=BL/Hero, 7=Imbue
ShamanPower.CooldownBarKeybinds = {
	["SHAMANPOWER_CD_SHIELD"] = 1,
	["SHAMANPOWER_CD_RECALL"] = 2,
	["SHAMANPOWER_CD_ANKH"] = 3,
	["SHAMANPOWER_CD_NS"] = 4,
	["SHAMANPOWER_CD_MANATIDE"] = 5,
	["SHAMANPOWER_CD_BLOODLUST"] = 6,
	["SHAMANPOWER_CD_IMBUE"] = 7,
}

-- Find a cooldown button by its cooldownType
function ShamanPower:GetCooldownButtonByCooldownType(cooldownType)
	if cooldownType == 7 then
		-- Weapon imbue button
		return self.weaponImbueButton
	end
	-- Totemic Call (cooldownType 2) - check if it's on the totem bar instead
	if cooldownType == 2 and self.opt.totemicCallOnTotemBar then
		return _G["ShamanPowerAutoTotemicCall"]
	end
	if not self.cooldownButtons then return nil end
	for _, btn in ipairs(self.cooldownButtons) do
		if btn.cooldownType == cooldownType then
			return btn
		end
	end
	return nil
end

-- Create a hidden button for Totemic Call keybind
function ShamanPower:CreateTotemicCallButton()
	if _G["ShamanPowerTotemicCallBtn"] then return end

	local spellName = GetSpellInfo(36936)  -- Totemic Call
	if not spellName or not IsSpellKnown(36936) then return end

	local btn = CreateFrame("Button", "ShamanPowerTotemicCallBtn", UIParent, "SecureActionButtonTemplate")
	btn:SetSize(1, 1)
	btn:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	btn:Hide()  -- Hidden, only used for keybind
	btn:RegisterForClicks("AnyUp", "AnyDown")
	btn:SetAttribute("type1", "spell")
	btn:SetAttribute("spell1", spellName)
end

-- ============================================================================
-- Auto-updating WoW Macros
-- Creates actual WoW macros that users can drag to their action bars.
-- The addon automatically updates the macro text when assignments change.
-- ============================================================================

ShamanPower.MacroNames = {
	Earth = "SP_Earth",
	Fire = "SP_Fire",
	Water = "SP_Water",
	Air = "SP_Air",
	DropAll = "SP_DropAll",
	TotemicCall = "SP_Recall",
}

-- Create or update a WoW macro
function ShamanPower:CreateOrUpdateMacro(name, icon, body)
	if InCombatLockdown() then return end

	local index = GetMacroIndexByName(name)
	if index > 0 then
		-- Macro exists, update it
		EditMacro(index, name, icon, body)
	else
		-- Create new macro (character-specific)
		local numGlobal, numChar = GetNumMacros()
		if numChar < MAX_CHARACTER_MACROS then
			CreateMacro(name, icon, body, true)  -- true = per-character
		else
			-- Try global macros if character slots full
			if numGlobal < MAX_ACCOUNT_MACROS then
				CreateMacro(name, icon, body, false)
			end
		end
	end
end

-- Update all ShamanPower macros based on current assignments
function ShamanPower:UpdateSPMacros()
	if InCombatLockdown() then
		self.macroUpdatePending = true
		return
	end

	local playerName = self.player
	local assignments = ShamanPower_Assignments[playerName]
	if not assignments then return end

	local elementNames = {"Earth", "Fire", "Water", "Air"}
	local defaultIcons = {
		"INV_Stone_10",           -- Earth
		"Spell_Fire_Fire",        -- Fire
		"Spell_Frost_SummonWaterElemental", -- Water
		"Spell_Nature_InvisibilityTotem",   -- Air
	}

	-- Create/update individual totem macros
	for element = 1, 4 do
		local macroName = self.MacroNames[elementNames[element]]
		local totemIndex = assignments[element] or 0
		local body = "#showtooltip\n/cast "
		local icon = defaultIcons[element]

		-- Special handling for Air totem when twisting is enabled
		if element == 4 and self.opt.enableTotemTwisting then
			local wfName = GetSpellInfo(25587) or "Windfury Totem"  -- Windfury Totem
			local goaName = GetSpellInfo(25359) or "Grace of Air Totem"  -- Grace of Air Totem
			body = "#showtooltip\n/castsequence reset=10 " .. wfName .. ", " .. goaName
			icon = "Spell_Nature_Windfury"  -- Windfury icon
		elseif totemIndex > 0 then
			local spellID = self:GetTotemSpell(element, totemIndex)
			if spellID then
				local spellName = GetSpellInfo(spellID)
				if spellName then
					body = body .. spellName
					-- Use totem icon
					local totemIcon = self:GetTotemIcon(element, totemIndex)
					if totemIcon then
						icon = totemIcon:gsub("Interface\\Icons\\", "")
					end
				else
					body = body .. "-- No totem assigned"
				end
			else
				body = body .. "-- No totem assigned"
			end
		else
			body = body .. "-- No totem assigned"
		end

		self:CreateOrUpdateMacro(macroName, icon, body)
	end

	-- Create/update Drop All macro
	local totemSpells = {}
	local dropOrder = self.opt.dropOrder or {1, 2, 3, 4}
	-- Build exclude table for easy lookup
	local excludeTotem = {
		[1] = self.opt.excludeEarthFromDropAll,
		[2] = self.opt.excludeFireFromDropAll,
		[3] = self.opt.excludeWaterFromDropAll,
		[4] = self.opt.excludeAirFromDropAll,
	}
	for _, element in ipairs(dropOrder) do
		-- Skip if this totem type is excluded
		if not excludeTotem[element] then
			local totemIndex = assignments[element] or 0
			if totemIndex > 0 then
				local spellID = self:GetTotemSpell(element, totemIndex)
				if spellID then
					local spellName = GetSpellInfo(spellID)
					if spellName then
						table.insert(totemSpells, spellName)
					end
				end
			end
		end
	end

	local dropAllBody = "#showtooltip\n"
	if #totemSpells > 0 then
		dropAllBody = dropAllBody .. "/castsequence reset=combat " .. table.concat(totemSpells, ", ")
	else
		dropAllBody = dropAllBody .. "/cast -- No totems assigned"
	end
	self:CreateOrUpdateMacro(self.MacroNames.DropAll, "inv_hammer_02", dropAllBody)

	-- Create Totemic Call macro
	local tcSpellName, _, tcIcon = GetSpellInfo(36936)
	if tcSpellName then
		local tcBody = "#showtooltip\n/cast " .. tcSpellName
		local tcIconName
		if type(tcIcon) == "string" then
			tcIconName = tcIcon:match("Interface\\Icons\\(.+)") or tcIcon
		elseif type(tcIcon) == "number" then
			tcIconName = tcIcon  -- Use texture ID directly
		else
			tcIconName = "INV_Misc_QuestionMark"
		end
		self:CreateOrUpdateMacro(self.MacroNames.TotemicCall, tcIconName, tcBody)
	end

	self.macroUpdatePending = false
end

-- Slash command to create/refresh macros
SLASH_SPMACROS1 = "/spmacros"
SlashCmdList["SPMACROS"] = function()
	if InCombatLockdown() then
		print("ShamanPower: Cannot update macros in combat")
		return
	end
	ShamanPower:UpdateSPMacros()
	print("ShamanPower: Macros updated! Look for these in your macro list:")
	print("  SP_Earth, SP_Fire, SP_Water, SP_Air - Cast assigned totem")
	print("  SP_DropAll - Cast all totems in sequence")
	print("  SP_Recall - Totemic Call")
	print("Drag them to your action bar - they auto-update when you change assignments!")
end

-- ============================================================================
-- ACTION BAR KEYBIND DETECTION SYSTEM
-- Scans action bars from various addons (Bartender4, Dominos, ElvUI) to find
-- keybinds for spells, allowing ShamanPower to display keybinds on buttons
-- even when users bind spells through their action bar addon.
-- ============================================================================

-- Table to store detected action bar keybinds (keyed by spell name)
ShamanPower.actionBarKeybinds = {}

-- Detect which action bar addon is active
function ShamanPower:GetActiveActionBarAddon()
	if _G["Bartender4"] then
		return "Bartender4"
	elseif _G["Dominos"] then
		return "Dominos"
	elseif _G["ElvUI"] and _G["ElvUI"][1] and _G["ElvUI"][1].ActionBars then
		return "ElvUI"
	end
	return "Default"
end

-- Get spell name from an action slot
local function GetSpellNameFromActionSlot(slot)
	local actionType, id, subType = GetActionInfo(slot)
	if actionType == "spell" and id then
		local spellName = GetSpellInfo(id)
		return spellName, id
	elseif actionType == "macro" then
		-- Check if macro casts a spell we care about
		local macroSpell = GetMacroSpell(id)
		if macroSpell then
			local spellName = GetSpellInfo(macroSpell)
			return spellName, macroSpell
		end
	end
	return nil, nil
end

-- Scan Bartender4 action bars
function ShamanPower:ScanBartender4Keybinds()
	local keybinds = {}

	-- Bartender4 uses buttons named BT4Button1 through BT4Button120
	for i = 1, 120 do
		local btn = _G["BT4Button" .. i]
		if btn then
			local slot = btn:GetAttribute("action") or btn.action or i
			if slot and type(slot) == "number" and slot >= 1 and slot <= 120 then
				local spellName, spellID = GetSpellNameFromActionSlot(slot)
				if spellName and not keybinds[spellName] then
					-- Try to get keybind for this button
					local bindingString = "CLICK BT4Button" .. i .. ":LeftButton"
					local key1 = GetBindingKey(bindingString)
					if not key1 then
						-- Try alternate binding format
						bindingString = "CLICK BT4Button" .. i .. ":Keybind"
						key1 = GetBindingKey(bindingString)
					end
					if key1 then
						keybinds[spellName] = key1
					end
				end
			end
		end
	end

	return keybinds
end

-- Scan Dominos action bars
function ShamanPower:ScanDominosKeybinds()
	local keybinds = {}

	-- Dominos uses different button naming based on bar type
	-- Main action bar: ActionButton1-12
	-- Bonus bars: MultiBarBottomLeftButton, MultiBarBottomRightButton, etc.
	-- Dominos custom: DominosActionButton1-120

	-- Scan standard action buttons (slots 1-12)
	for i = 1, 12 do
		local slot = i
		local spellName, spellID = GetSpellNameFromActionSlot(slot)
		if spellName and not keybinds[spellName] then
			local key1 = GetBindingKey("ACTIONBUTTON" .. i)
			if key1 then
				keybinds[spellName] = key1
			end
		end
	end

	-- Scan MultiBar buttons (slots 13-72)
	local multiBarMappings = {
		{prefix = "MULTIACTIONBAR1BUTTON", slotOffset = 72, count = 12},  -- Right bar 1
		{prefix = "MULTIACTIONBAR2BUTTON", slotOffset = 60, count = 12},  -- Right bar 2
		{prefix = "MULTIACTIONBAR3BUTTON", slotOffset = 48, count = 12},  -- Bottom left
		{prefix = "MULTIACTIONBAR4BUTTON", slotOffset = 36, count = 12},  -- Bottom right
	}

	for _, barInfo in ipairs(multiBarMappings) do
		for i = 1, barInfo.count do
			local slot = barInfo.slotOffset + i
			local spellName, spellID = GetSpellNameFromActionSlot(slot)
			if spellName and not keybinds[spellName] then
				local key1 = GetBindingKey(barInfo.prefix .. i)
				if key1 then
					keybinds[spellName] = key1
				end
			end
		end
	end

	-- Scan Dominos-specific buttons
	for i = 1, 120 do
		local btn = _G["DominosActionButton" .. i]
		if btn then
			local slot = btn:GetAttribute("action") or i
			if slot and type(slot) == "number" and slot >= 1 and slot <= 120 then
				local spellName, spellID = GetSpellNameFromActionSlot(slot)
				if spellName and not keybinds[spellName] then
					local bindingString = "CLICK DominosActionButton" .. i .. ":LeftButton"
					local key1 = GetBindingKey(bindingString)
					if key1 then
						keybinds[spellName] = key1
					end
				end
			end
		end
	end

	return keybinds
end

-- Scan ElvUI action bars
function ShamanPower:ScanElvUIKeybinds()
	local keybinds = {}

	-- ElvUI action buttons are named ElvUI_Bar1Button1, ElvUI_Bar2Button1, etc.
	for bar = 1, 10 do
		for i = 1, 12 do
			local btnName = "ElvUI_Bar" .. bar .. "Button" .. i
			local btn = _G[btnName]
			if btn then
				local slot = btn:GetAttribute("action") or btn.action
				if slot and type(slot) == "number" and slot >= 1 and slot <= 120 then
					local spellName, spellID = GetSpellNameFromActionSlot(slot)
					if spellName and not keybinds[spellName] then
						-- ElvUI stores bindstring on buttons
						local bindstring = btn.bindstring
						if bindstring then
							local key1 = GetBindingKey(bindstring)
							if key1 then
								keybinds[spellName] = key1
							end
						end
						-- Try click binding format as fallback
						if not keybinds[spellName] then
							local bindingString = "CLICK " .. btnName .. ":LeftButton"
							local key1 = GetBindingKey(bindingString)
							if key1 then
								keybinds[spellName] = key1
							end
						end
					end
				end
			end
		end
	end

	return keybinds
end

-- Scan default WoW action bars
function ShamanPower:ScanDefaultActionBarKeybinds()
	local keybinds = {}

	-- Main action bar (slots 1-12)
	for i = 1, 12 do
		local slot = i
		local spellName, spellID = GetSpellNameFromActionSlot(slot)
		if spellName and not keybinds[spellName] then
			local key1 = GetBindingKey("ACTIONBUTTON" .. i)
			if key1 then
				keybinds[spellName] = key1
			end
		end
	end

	-- Bonus action bar / stance bar (slots 73-84 for first page, etc.)
	for i = 1, 12 do
		local slot = 72 + i
		local spellName, spellID = GetSpellNameFromActionSlot(slot)
		if spellName and not keybinds[spellName] then
			local key1 = GetBindingKey("ACTIONBUTTON" .. i)
			if key1 then
				keybinds[spellName] = key1
			end
		end
	end

	-- Bottom Left MultiBar (MultiBarBottomLeft, slots 61-72)
	for i = 1, 12 do
		local slot = 60 + i
		local spellName, spellID = GetSpellNameFromActionSlot(slot)
		if spellName and not keybinds[spellName] then
			local key1 = GetBindingKey("MULTIACTIONBAR1BUTTON" .. i)
			if key1 then
				keybinds[spellName] = key1
			end
		end
	end

	-- Bottom Right MultiBar (MultiBarBottomRight, slots 49-60)
	for i = 1, 12 do
		local slot = 48 + i
		local spellName, spellID = GetSpellNameFromActionSlot(slot)
		if spellName and not keybinds[spellName] then
			local key1 = GetBindingKey("MULTIACTIONBAR2BUTTON" .. i)
			if key1 then
				keybinds[spellName] = key1
			end
		end
	end

	-- Right MultiBar (MultiBarRight, slots 25-36)
	for i = 1, 12 do
		local slot = 24 + i
		local spellName, spellID = GetSpellNameFromActionSlot(slot)
		if spellName and not keybinds[spellName] then
			local key1 = GetBindingKey("MULTIACTIONBAR3BUTTON" .. i)
			if key1 then
				keybinds[spellName] = key1
			end
		end
	end

	-- Right MultiBar 2 (MultiBarLeft, slots 37-48)
	for i = 1, 12 do
		local slot = 36 + i
		local spellName, spellID = GetSpellNameFromActionSlot(slot)
		if spellName and not keybinds[spellName] then
			local key1 = GetBindingKey("MULTIACTIONBAR4BUTTON" .. i)
			if key1 then
				keybinds[spellName] = key1
			end
		end
	end

	return keybinds
end

-- Main function to scan all action bars and populate the keybind lookup table
function ShamanPower:ScanActionBarKeybinds()
	local addon = self:GetActiveActionBarAddon()
	local keybinds = {}

	-- Always scan default bars first (provides fallback)
	local defaultKeybinds = self:ScanDefaultActionBarKeybinds()
	for spell, key in pairs(defaultKeybinds) do
		keybinds[spell] = key
	end

	-- Then scan addon-specific bars (overwrites default if found)
	if addon == "Bartender4" then
		local addonKeybinds = self:ScanBartender4Keybinds()
		for spell, key in pairs(addonKeybinds) do
			keybinds[spell] = key
		end
	elseif addon == "Dominos" then
		local addonKeybinds = self:ScanDominosKeybinds()
		for spell, key in pairs(addonKeybinds) do
			keybinds[spell] = key
		end
	elseif addon == "ElvUI" then
		local addonKeybinds = self:ScanElvUIKeybinds()
		for spell, key in pairs(addonKeybinds) do
			keybinds[spell] = key
		end
	end

	self.actionBarKeybinds = keybinds
end

-- Get keybind for a spell by name (checks action bar keybinds first)
function ShamanPower:GetKeybindForSpell(spellName)
	if not spellName then return nil end
	return self.actionBarKeybinds[spellName]
end

-- Map ShamanPower button types to their associated spell names
-- Returns the spell name that should be looked up for action bar keybinds
function ShamanPower:GetSpellNameForButton(buttonType, element)
	-- Cooldown bar buttons (cooldownType values)
	if buttonType == "shield" then
		-- Check which shield is preferred/active
		local btn = self.shieldButton
		if btn and btn.activeShieldID then
			return GetSpellInfo(btn.activeShieldID)
		end
		-- Default to Lightning Shield
		return GetSpellInfo(324)
	elseif buttonType == "recall" then
		return GetSpellInfo(36936)  -- Totemic Call
	elseif buttonType == "ankh" then
		return GetSpellInfo(20608)  -- Reincarnation
	elseif buttonType == "ns" then
		return GetSpellInfo(16188)  -- Nature's Swiftness
	elseif buttonType == "manatide" then
		return GetSpellInfo(16190)  -- Mana Tide Totem
	elseif buttonType == "bloodlust" then
		-- Check faction for Bloodlust vs Heroism
		local faction = UnitFactionGroup("player")
		if faction == "Alliance" then
			return GetSpellInfo(32182)  -- Heroism
		else
			return GetSpellInfo(2825)  -- Bloodlust
		end
	elseif buttonType == "imbue" then
		-- Get current main hand imbue spell
		local hasMain, _, _, mainID = GetWeaponEnchantInfo()
		if hasMain and self.EnchantIDToImbue and self.EnchantIDToImbue[mainID] then
			local imbueType = self.EnchantIDToImbue[mainID]
			if self.WeaponImbueSpells and self.WeaponImbueSpells[imbueType] then
				return GetSpellInfo(self.WeaponImbueSpells[imbueType])
			end
		end
		-- Fallback to last used or Windfury
		if self.lastMainHandImbue and self.WeaponImbueSpells then
			return GetSpellInfo(self.WeaponImbueSpells[self.lastMainHandImbue])
		end
		return GetSpellInfo(8232)  -- Windfury Weapon default
	elseif buttonType == "totem" and element then
		-- Get assigned totem spell for this element
		local assignments = ShamanPower_Assignments[self.player]
		if assignments then
			local totemIndex = assignments[element] or 0
			if totemIndex > 0 then
				local spellID = self:GetTotemSpell(element, totemIndex)
				if spellID then
					return GetSpellInfo(spellID)
				end
			end
		end
	elseif buttonType == "dropall" then
		-- Drop All uses a macro, but we can check for Call of the Elements or similar
		-- or just return nil since it's not a single spell
		return nil
	end

	return nil
end

-- Convert a key binding to a short display string
local function GetShortKeybindText(key)
	if not key then return nil end
	-- Make common modifiers shorter
	key = key:gsub("CTRL%-", "C-")
	key = key:gsub("ALT%-", "A-")
	key = key:gsub("SHIFT%-", "S-")
	key = key:gsub("NUMPAD", "N")
	key = key:gsub("BUTTON", "M")
	key = key:gsub("MOUSEWHEELUP", "MWU")
	key = key:gsub("MOUSEWHEELDOWN", "MWD")
	return key
end

-- Map totem bar binding names to button names
ShamanPower.TotemBarKeybinds = {
	["SHAMANPOWER_EARTH_TOTEM"] = "ShamanPowerTotemBtn1",
	["SHAMANPOWER_FIRE_TOTEM"] = "ShamanPowerTotemBtn2",
	["SHAMANPOWER_WATER_TOTEM"] = "ShamanPowerTotemBtn3",
	["SHAMANPOWER_AIR_TOTEM"] = "ShamanPowerTotemBtn4",
	["SHAMANPOWER_DROPALL"] = "ShamanPowerAutoDropAll",
}

-- Set up keybind text FontStrings on totem bar buttons (they're created in XML without keybind text)
function ShamanPower:SetupTotemBarKeybindText()
	for bindingName, buttonName in pairs(self.TotemBarKeybinds) do
		local btn = _G[buttonName]
		if btn and not btn.keybindText then
			local keybindText = btn:CreateFontString(nil, "OVERLAY")
			keybindText:SetFont("Fonts\\ARIALN.TTF", 9, "OUTLINE")
			keybindText:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 1, 0)
			keybindText:SetTextColor(0.9, 0.9, 0.9, 1)
			keybindText:SetText("")
			keybindText:Hide()
			btn.keybindText = keybindText
		end
	end
end

-- Map totem bar binding names to element index for action bar keybind lookup
ShamanPower.TotemBarElementMap = {
	["SHAMANPOWER_EARTH_TOTEM"] = 1,
	["SHAMANPOWER_FIRE_TOTEM"] = 2,
	["SHAMANPOWER_WATER_TOTEM"] = 3,
	["SHAMANPOWER_AIR_TOTEM"] = 4,
	["SHAMANPOWER_DROPALL"] = nil,  -- Drop All is not a single spell
}

-- Map cooldownType to button type string for action bar keybind lookup
ShamanPower.CooldownTypeToButtonType = {
	[1] = "shield",
	[2] = "recall",
	[3] = "ankh",
	[4] = "ns",
	[5] = "manatide",
	[6] = "bloodlust",
	[7] = "imbue",
}

-- Update keybind text on all buttons (totem bar + cooldown bar)
-- Priority: 1) Action bar addon keybind, 2) Default WoW action bar keybind, 3) ShamanPower binding
function ShamanPower:UpdateButtonKeybindText()
	-- Set up totem bar keybind text if not already done
	self:SetupTotemBarKeybindText()

	-- Scan action bars for keybinds (refreshes actionBarKeybinds table)
	self:ScanActionBarKeybinds()

	if not self.opt.showButtonKeybinds then
		-- Hide all keybind text if option disabled
		-- Hide totem bar keybind text
		for _, buttonName in pairs(self.TotemBarKeybinds) do
			local btn = _G[buttonName]
			if btn and btn.keybindText then
				btn.keybindText:Hide()
			end
		end
		-- Hide cooldown bar keybind text
		if self.cooldownButtons then
			for _, btn in ipairs(self.cooldownButtons) do
				if btn.keybindText then
					btn.keybindText:Hide()
				end
			end
		end
		if self.weaponImbueButton and self.weaponImbueButton.keybindText then
			self.weaponImbueButton.keybindText:Hide()
		end
		return
	end

	-- Update keybind text for totem bar buttons
	for bindingName, buttonName in pairs(self.TotemBarKeybinds) do
		local btn = _G[buttonName]
		if btn and btn.keybindText then
			local keyText = nil

			-- First, try to get keybind from action bar addon
			local element = self.TotemBarElementMap[bindingName]
			if element then
				local spellName = self:GetSpellNameForButton("totem", element)
				if spellName then
					local actionBarKey = self:GetKeybindForSpell(spellName)
					if actionBarKey then
						keyText = GetShortKeybindText(actionBarKey)
					end
				end
			elseif bindingName == "SHAMANPOWER_DROPALL" then
				-- Drop All could be bound via macro - skip action bar lookup
				-- (user would need to bind the SP_DropAll macro on their bar)
			end

			-- Fallback to ShamanPower-specific binding
			if not keyText then
				local key1, key2 = GetBindingKey(bindingName)
				keyText = GetShortKeybindText(key1)
			end

			if keyText then
				btn.keybindText:SetText(keyText)
				btn.keybindText:Show()
			else
				btn.keybindText:SetText("")
				btn.keybindText:Hide()
			end
		end
	end

	-- Update keybind text for each cooldown bar button
	for bindingName, cooldownType in pairs(self.CooldownBarKeybinds) do
		local btn = self:GetCooldownButtonByCooldownType(cooldownType)
		if btn and btn.keybindText then
			local keyText = nil

			-- First, try to get keybind from action bar addon
			local buttonType = self.CooldownTypeToButtonType[cooldownType]
			if buttonType then
				local spellName = self:GetSpellNameForButton(buttonType)
				if spellName then
					local actionBarKey = self:GetKeybindForSpell(spellName)
					if actionBarKey then
						keyText = GetShortKeybindText(actionBarKey)
					end
				end
			end

			-- Fallback to ShamanPower-specific binding
			if not keyText then
				local key1, key2 = GetBindingKey(bindingName)
				keyText = GetShortKeybindText(key1)
			end

			if keyText then
				btn.keybindText:SetText(keyText)
				btn.keybindText:Show()
			else
				btn.keybindText:SetText("")
				btn.keybindText:Hide()
			end
		end
	end

	-- Update keybind text for weapon imbue button
	if self.weaponImbueButton and self.weaponImbueButton.keybindText then
		local keyText = nil

		-- Try to get keybind from action bar addon for current imbue spell
		local spellName = self:GetSpellNameForButton("imbue")
		if spellName then
			local actionBarKey = self:GetKeybindForSpell(spellName)
			if actionBarKey then
				keyText = GetShortKeybindText(actionBarKey)
			end
		end

		-- Fallback to ShamanPower-specific binding
		if not keyText then
			local key1, key2 = GetBindingKey("SHAMANPOWER_CD_IMBUE")
			keyText = GetShortKeybindText(key1)
		end

		if keyText then
			self.weaponImbueButton.keybindText:SetText(keyText)
			self.weaponImbueButton.keybindText:Show()
		else
			self.weaponImbueButton.keybindText:SetText("")
			self.weaponImbueButton.keybindText:Hide()
		end
	end
end

function ShamanPower:SetupKeybindings()
	-- Can't modify bindings during combat
	if InCombatLockdown() then
		self.keybindsPending = true
		return
	end

	-- Need a frame to own the bindings
	if not self.keybindFrame then
		self.keybindFrame = CreateFrame("Frame", "ShamanPowerKeybindFrame", UIParent)
	end

	-- Create the Totemic Call button if it doesn't exist
	self:CreateTotemicCallButton()

	-- Clear any existing override bindings
	ClearOverrideBindings(self.keybindFrame)

	-- Set up override bindings for totem bar buttons (static button names)
	for bindingName, buttonName in pairs(self.KeybindButtons) do
		local key1, key2 = GetBindingKey(bindingName)
		if key1 then
			SetOverrideBindingClick(self.keybindFrame, false, key1, buttonName, "LeftButton")
		end
		if key2 then
			SetOverrideBindingClick(self.keybindFrame, false, key2, buttonName, "LeftButton")
		end
	end

	-- Set up override bindings for cooldown bar buttons (dynamic button lookup)
	for bindingName, cooldownType in pairs(self.CooldownBarKeybinds) do
		local btn = self:GetCooldownButtonByCooldownType(cooldownType)
		if btn then
			local buttonName = btn:GetName()
			if buttonName then
				local key1, key2 = GetBindingKey(bindingName)
				if key1 then
					SetOverrideBindingClick(self.keybindFrame, false, key1, buttonName, "LeftButton")
				end
				if key2 then
					SetOverrideBindingClick(self.keybindFrame, false, key2, buttonName, "LeftButton")
				end
			end
		end
	end

	self.keybindsPending = false

	-- Update keybind text on buttons if enabled
	self:UpdateButtonKeybindText()
end

-- Register for binding updates
local keybindEventFrame = CreateFrame("Frame")
keybindEventFrame:RegisterEvent("UPDATE_BINDINGS")
keybindEventFrame:RegisterEvent("PLAYER_LOGIN")
keybindEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
keybindEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
keybindEventFrame:RegisterEvent("ADDON_LOADED")

-- Action bar addons that we want to detect for keybind scanning
local actionBarAddons = {
	["Bartender4"] = true,
	["Dominos"] = true,
	["ElvUI"] = true,
}

keybindEventFrame:SetScript("OnEvent", function(self, event, arg1)
	-- If leaving combat, check if we have pending keybind or macro setup
	if event == "PLAYER_REGEN_ENABLED" then
		if ShamanPower.keybindsPending then
			ShamanPower:SetupKeybindings()
		end
		-- Handle pending talent change from combat
		if ShamanPower.talentChangePending then
			ShamanPower.talentChangePending = false
			ShamanPower:OnTalentsChanged()
		end
		-- Handle pending totem assignment changes from combat
		if ShamanPower.pendingAssignments then
			for elem, totemIdx in pairs(ShamanPower.pendingAssignments) do
				if not ShamanPower_Assignments[ShamanPower.player] then
					ShamanPower_Assignments[ShamanPower.player] = {}
				end
				ShamanPower_Assignments[ShamanPower.player][elem] = totemIdx
				ShamanPower:UpdateMiniTotemBar()
				ShamanPower:UpdateDropAllButton()
				ShamanPower:UpdateSPMacros()
				ShamanPower:SyncToTotemTimers(elem, totemIdx)
				ShamanPower:SendMessage("ASSIGN " .. ShamanPower.player .. " " .. elem .. " " .. totemIdx)
				ShamanPower:UpdateFlyoutVisibility(elem)
			end
			ShamanPower.pendingAssignments = nil
			-- Silent save, like TotemTimers
		end
		-- Dynamic Mode: update button attributes now that we're out of combat
		if ShamanPower.opt.dynamicTotemMode then
			ShamanPower:UpdateMiniTotemBar()
			ShamanPower:UpdateTotemButtons()
		end
		return
	end

	-- When an action bar addon loads, rescan keybinds after a delay
	if event == "ADDON_LOADED" and actionBarAddons[arg1] then
		-- Delay to allow addon to fully initialize
		C_Timer.After(1.0, function()
			if ShamanPower.UpdateButtonKeybindText then
				ShamanPower:UpdateButtonKeybindText()
			end
		end)
		return
	end

	-- When entering world, refresh action bar keybind scan
	if event == "PLAYER_ENTERING_WORLD" then
		-- Delay to allow action bars to be set up
		C_Timer.After(2.0, function()
			if ShamanPower.UpdateButtonKeybindText then
				ShamanPower:UpdateButtonKeybindText()
			end
		end)
	end

	-- Delay slightly to ensure buttons exist
	C_Timer.After(0.5, function()
		if ShamanPower.SetupKeybindings then
			ShamanPower:SetupKeybindings()
		end
	end)
end)

-- ============================================================================
-- MODULE CHECK STUBS
-- These functions provide fallbacks when optional modules are not loaded
-- Modules: ShamanPower [SPRange], ShamanPower [Raid Cooldowns],
--          ShamanPower [Raid ES Tracker], ShamanPower [Party Range],
--          ShamanPower [Shield Charge Display]
-- ============================================================================

-- Raid Cooldowns module stubs (loaded by ShamanPower_RaidCooldowns addon)
if not ShamanPower.RaidCooldownsLoaded then
	-- Provide stub functions when module not loaded
	function ShamanPower:InitRaidCooldowns() end
	function ShamanPower:ToggleRaidCooldownPanel()
		print("|cffff8800ShamanPower:|r Raid Cooldowns module not loaded. Enable 'ShamanPower [Raid Cooldowns]' in your addon list.")
	end
	function ShamanPower:UpdateCallerButtons() end
	function ShamanPower:HandleRaidCooldownMessage() end
	function ShamanPower:CallBloodlust() end
	function ShamanPower:CallManaTide() end
	function ShamanPower:RestoreCallerCooldowns() end
	function ShamanPower:AddCooldownButtonAlert() end
	function ShamanPower:RemoveCooldownButtonAlert() end
	function ShamanPower:EnableCallerCooldownTracking() end
	function ShamanPower:DisableCallerCooldownTracking() end
	function ShamanPower:UpdateCallerButtonOpacity() end
	function ShamanPower:UpdateCallerButtonScale() end

	-- Register /spraid slash command (shows module not loaded message)
	SLASH_SPRAID1 = "/spraid"
	SlashCmdList["SPRAID"] = function(msg)
		ShamanPower:ToggleRaidCooldownPanel()
	end
end

-- SPRange module stubs (loaded by ShamanPower_SPRange addon)
if not ShamanPower.SPRangeLoaded then
	-- Provide stub functions when module not loaded
	function ShamanPower:InitSPRange() end
	function ShamanPower:CreateSPRangeFrame() end
	function ShamanPower:ToggleSPRange()
		print("|cffff8800ShamanPower:|r SPRange module not loaded. Enable 'ShamanPower [SPRange]' in your addon list.")
	end
	function ShamanPower:ShowSPRangeConfig()
		print("|cffff8800ShamanPower:|r SPRange module not loaded. Enable 'ShamanPower [SPRange]' in your addon list.")
	end
	function ShamanPower:InitializeSPRange() end
	function ShamanPower:UpdateSPRangeVisibility() end
	function ShamanPower:UpdateSPRangeFrame() end
	function ShamanPower:UpdateSPRangeBorder() end
	function ShamanPower:UpdateSPRangeOpacity() end
	function ShamanPower:SPRangeHasWindfuryWeapon() return false end
	function ShamanPower:IsPlayerInWindfuryRange() return false end

	-- Register /sprange slash command (shows module not loaded message)
	SLASH_SPRANGE1 = "/sprange"
	SlashCmdList["SPRANGE"] = function(msg)
		ShamanPower:ToggleSPRange()
	end
end

-- ES Tracker module stubs (loaded by ShamanPower_ESTracker addon)
-- This module tracks Earth Shields cast by OTHER shamans in your raid/party
if not ShamanPower.ESTrackerLoaded then
	-- Provide stub functions when module not loaded
	function ShamanPower:InitESTracker() end
	function ShamanPower:CreateESTrackerFrame() end
	function ShamanPower:ToggleESTracker()
		print("|cffff8800ShamanPower:|r ES Tracker module not loaded. Enable 'ShamanPower [Raid ES Tracker]' in your addon list.")
	end
	function ShamanPower:InitializeESTracker() end
	function ShamanPower:UpdateESTrackerFrame() end
	function ShamanPower:UpdateESTrackerBorder() end
	function ShamanPower:UpdateESTrackerOpacity() end
	function ShamanPower:ScanEarthShields() end
	function ShamanPower:SetupESTrackerUpdater() end
	function ShamanPower:EnableESTrackerEvents() end
	function ShamanPower:DisableESTrackerEvents() end
	function ShamanPower:ClearESTracker() end
	function ShamanPower:GetClassColorForUnit() return 1, 1, 1 end
	function ShamanPower:GetClassColor() return 1, 1, 1 end

	-- Register /spestrack slash command (shows module not loaded message)
	SLASH_SPESTRACK1 = "/spestrack"
	SLASH_SPESTRACK2 = "/spearthshield"
	SlashCmdList["SPESTRACK"] = function(msg)
		ShamanPower:ToggleESTracker()
	end
end

-- Party Range module stubs (loaded by ShamanPower_PartyRange addon)
-- This module shows party members in/out of totem range via dots and counters
if not ShamanPower.PartyRangeLoaded then
	-- Provide stub functions when module not loaded
	function ShamanPower:CreatePartyRangeDots() end
	function ShamanPower:SetupPartyRangeDots() end
	function ShamanPower:UpdatePartyRangeDots() end
	function ShamanPower:GetActiveTotemBuffName() return nil end
	function ShamanPower:UnitHasBuff() return false end
	function ShamanPower:GetCachedPartyUnits() return {}, 0 end
	function ShamanPower:CreateRangeCounterText() end
	function ShamanPower:CreateRangeCounterFrame() end
	function ShamanPower:SetupRangeCounters() end
	function ShamanPower:UpdateRangeCounterLock() end
	function ShamanPower:UpdateRangeCounterFrameStyle() end
	function ShamanPower:UpdateRangeCounters() end

	-- Initialize empty tables
	ShamanPower.partyRangeDots = {}
	ShamanPower.partyUnitsCache = {}
	ShamanPower.emptyTable = {}
	ShamanPower.rangeCounterTexts = {}
	ShamanPower.rangeCounterFrames = {}
	ShamanPower.RangeCounterColors = {
		[1] = {0.2, 0.9, 0.2},
		[2] = {0.9, 0.2, 0.2},
		[3] = {0.2, 0.6, 1.0},
		[4] = {1.0, 1.0, 1.0},
	}
	ShamanPower.TotemBuffNames = {}
end

-- Shield Charges module stubs (loaded by ShamanPower_ShieldCharges addon)
-- Large on-screen numbers showing your shield charges and Earth Shield charges
if not ShamanPower.ShieldChargesLoaded then
	-- Provide stub functions when module not loaded
	function ShamanPower:CreateShieldChargeDisplays() end
	function ShamanPower:UpdateShieldChargeDisplays() end
	function ShamanPower:GetShieldChargeColor() return 1, 1, 1 end

	-- Initialize empty table
	ShamanPower.shieldChargeFrames = {}
end

-- Totem Plates module stubs (loaded by ShamanPower_TotemPlates addon)
-- Replaces totem nameplates with clean, recognizable icons
if not ShamanPower.TotemPlatesLoaded then
	-- Provide stub functions when module not loaded
	function ShamanPower:InitializeTotemPlates() end
	function ShamanPower:ToggleTotemPlates()
		print("|cffff8800ShamanPower:|r Totem Plates module not loaded. Enable 'ShamanPower [Totem Plates]' in your AddOns.")
	end
	function ShamanPower:UpdateTotemPlatesSize() end
	function ShamanPower:UpdateTotemPlatesPulseSettings() end
	function ShamanPower:DetectNameplateAddon() end

	-- Initialize empty tables
	ShamanPower.activeTotemPlates = {}
	ShamanPower.totemPlateCache = {}
	ShamanPower.detectedNameplateAddon = "Blizzard"
end

-- NOTE: The actual implementations of these functions are in:
-- - ShamanPower_RaidCooldowns/ShamanPower_RaidCooldowns.lua
-- - ShamanPower_SPRange/ShamanPower_SPRange.lua
-- - ShamanPower_ESTracker/ShamanPower_ESTracker.lua
-- - ShamanPower_PartyRange/ShamanPower_PartyRange.lua
-- - ShamanPower_ShieldCharges/ShamanPower_ShieldCharges.lua
-- - ShamanPower_TotemPlates/ShamanPower_TotemPlates.lua
-- When those modules are loaded, they override these stub functions.


-- ============================================================================
-- SPThanks: Special feature for Srumar to thank ShamanPower users
-- ============================================================================

ShamanPower.spThanksEnabled = false
ShamanPower.spThankedPlayers = {}  -- Track who we've already thanked this session

function ShamanPower:SPThanksCheckAndWhisper(playerName)
	-- Only works for Srumar
	if self.player ~= "Srumar" then return end
	if not self.spThanksEnabled then return end
	if not playerName or playerName == self.player then return end

	-- Don't thank the same person twice in a session
	if self.spThankedPlayers[playerName] then return end

	-- Mark as thanked and send whisper
	self.spThankedPlayers[playerName] = true
	SendChatMessage("Thanks for installing ShamanPower!", "WHISPER", nil, playerName)
	self:Print("Thanked " .. playerName .. " for using ShamanPower!")
end

-- Hook into existing addon sync to detect users
local originalParseMessage = ShamanPower.ParseMessage
function ShamanPower:ParseMessage(sender, msg, ...)
	-- Check for SPThanks before calling original (sender is first param!)
	if sender and sender ~= self.player then
		-- Strip realm name if present
		local shortName = strsplit("-", sender)
		self:SPThanksCheckAndWhisper(shortName)
	end

	-- Call original function
	if originalParseMessage then
		return originalParseMessage(self, sender, msg, ...)
	end
end

SLASH_SPTHANKS1 = "/spthanks"
SlashCmdList["SPTHANKS"] = function(msg)
	-- Only Srumar can use this
	if ShamanPower.player ~= "Srumar" then
		print("|cffff0000ShamanPower:|r This feature is only available for Srumar.")
		return
	end

	msg = msg:lower():trim()

	if msg == "on" then
		ShamanPower.spThanksEnabled = true
		ShamanPower.spThankedPlayers = {}  -- Reset thanked list
		print("|cff00ff00ShamanPower:|r SPThanks enabled! Will whisper thanks to ShamanPower users.")
	elseif msg == "off" then
		ShamanPower.spThanksEnabled = false
		print("|cff00ff00ShamanPower:|r SPThanks disabled.")
	else
		local status = ShamanPower.spThanksEnabled and "|cff00ff00ON|r" or "|cffff0000OFF|r"
		print("|cff00ff00ShamanPower:|r SPThanks is currently " .. status)
		print("Usage: /spthanks on | /spthanks off")
	end
end

-- ============================================================================
-- SPCenter: Reset totem bar and cooldown bar to center of screen
-- ============================================================================

SLASH_SPCENTER1 = "/spcenter"
SlashCmdList["SPCENTER"] = function(msg)
	if InCombatLockdown() then
		print("|cffff0000ShamanPower:|r Cannot reposition frames during combat.")
		return
	end

	-- Reset main ShamanPower frame to center and save position
	local mainFrame = _G["ShamanPowerFrame"]
	if mainFrame then
		mainFrame:ClearAllPoints()
		mainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
		-- Clear saved position so it stays centered after reload
		ShamanPower:EnsureProfileTable("display")
		ShamanPower.opt.display.offsetX = 0
		ShamanPower.opt.display.offsetY = 0
		print("|cff00ff00ShamanPower:|r Totem bar moved to center.")
	end

	-- Reset cooldown bar position (force reposition even if already unlocked)
	if ShamanPower.cooldownBar then
		ShamanPower.opt.cooldownBarPosX = 0
		ShamanPower.opt.cooldownBarPosY = -50
		ShamanPower.opt.cooldownBarPoint = "CENTER"
		ShamanPower.opt.cooldownBarRelPoint = "CENTER"
		ShamanPower:UpdateCooldownBarPosition(true)  -- true = force reposition
		print("|cff00ff00ShamanPower:|r Cooldown bar moved to center.")
	end

	-- Make sure bars are visible
	if ShamanPower.autoButton then
		ShamanPower.autoButton:Show()
	end

	-- Force a layout update
	ShamanPower:UpdateLayout()
	ShamanPower:UpdateRoster()

	print("|cff00ff00ShamanPower:|r Frames reset to center. Use ALT+drag to reposition.")
end


