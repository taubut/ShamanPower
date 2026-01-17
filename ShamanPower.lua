ShamanPower = LibStub("AceAddon-3.0"):NewAddon("ShamanPower", "AceConsole-3.0", "AceEvent-3.0", "AceBucket-3.0", "AceTimer-3.0")

ShamanPower.isVanilla = (_G.WOW_PROJECT_ID == _G.WOW_PROJECT_CLASSIC)
ShamanPower.isBCC = (_G.WOW_PROJECT_ID == _G.WOW_PROJECT_BURNING_CRUSADE_CLASSIC)
ShamanPower.isWrath = (_G.WOW_PROJECT_ID == _G.WOW_PROJECT_WRATH_CLASSIC)

local L = LibStub("AceLocale-3.0"):GetLocale("ShamanPower")
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

-- Shaman tracking tables by element
local EarthShamans, FireShamans, WaterShamans, AirShamans = {}, {}, {}, {}
local classlist, classes = {}, {}

ShamanPower.player = UnitName("player")
ShamanPower_Talents = {}
ShamanPower_Assignments = {}
ShamanPower_WeaponAssignments = {}
ShamanPower_EarthShieldAssignments = {}  -- Maps shamanName -> targetName

AllShamans = {}
SyncList = {}
AC_DebugEnabled = false

local initialized = false
local isShaman = false

AC_Leader = false

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
			["icon"] = "Interface\\AddOns\\ShamanPower\\Icons\\SummonChampion",
			["OnTooltipShow"] = function(tooltip)
				if self.opt.ShowTooltips then
					tooltip:SetText(SHAMANPOWER_NAME)
					tooltip:AddLine(L["MINIMAP_ICON_TOOLTIP"])
					tooltip:Show()
				end
			end,
			["OnClick"] = function(_, button)
				if (button == "LeftButton") then
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

	local h = _G["ShamanPowerFrame"]
	h:ClearAllPoints()
	h:SetPoint("CENTER", "UIParent", "CENTER", self.opt.display.offsetX, self.opt.display.offsetY)

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
	self:RegisterEvent("GROUP_JOINED")
	self:RegisterEvent("GROUP_LEFT")
	self:RegisterEvent("PLAYER_ROLES_ASSIGNED")
	self:RegisterEvent("UPDATE_BINDINGS", "BindKeys")
	self:RegisterEvent("CHANNEL_UI_UPDATE", "ReportChannels")
	self:RegisterBucketEvent("SPELLS_CHANGED", 1, "SPELLS_CHANGED")
	self:RegisterBucketEvent("PLAYER_ENTERING_WORLD", 2, "PLAYER_ENTERING_WORLD")
	self:RegisterBucketEvent({"GROUP_ROSTER_UPDATE", "PLAYER_REGEN_ENABLED", "UNIT_PET", "UNIT_AURA"}, 1, "UpdateRoster")
	self:RegisterBucketEvent({"GROUP_ROSTER_UPDATE"}, 1, "UpdateAllShamans")
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
	self.opt = self.db.profile
	self:UpdateLayout()
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

	local h = _G["ShamanPowerFrame"]
	h:ClearAllPoints()
	h:SetPoint("CENTER", "UIParent", "CENTER", self.opt.display.offsetX, self.opt.display.offsetY)
	self.opt.buffscale = 0.9
	self.opt.border = "Blizzard Tooltip"
	self.opt.layout = "Layout 2"
	self.opt.skin = "Smooth"
	local c = _G["ShamanPowerBlessingsFrame"]
	c:ClearAllPoints()
	c:SetPoint("CENTER", "UIParent", "CENTER", 0, 0)
	self.opt.configscale = 0.9
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
	if not initialized then
		return
	end
	-- Ensure assignment tables are initialized
	if not ShamanPower_Assignments then ShamanPower_Assignments = {} end
	if not ShamanPower_NormalAssignments then ShamanPower_NormalAssignments = {} end
	if not ShamanPower_AuraAssignments then ShamanPower_AuraAssignments = {} end
	if ShamanPowerBlessingsFrame:IsVisible() then
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

-- ============================================================================
-- Totem Pulse Overlay (visual pulse for totems like Tremor)
-- ============================================================================

ShamanPower.pulseOverlays = {}

function ShamanPower:CreatePulseOverlay(button)
	if not button then return nil end

	local container = { glows = {} }

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

	return container
end

-- Pulsing totem data: totemName pattern -> { element, interval }
ShamanPower.PulsingTotems = {
	-- Earth totems (element 1, slot 2)
	["Tremor"] = { element = 1, slot = 2, interval = 3 },
	["Earthbind"] = { element = 1, slot = 2, interval = 3 },
	-- Water totems (element 3, slot 3)
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
		local button = _G["ShamanPowerAutoTotem" .. element]
		if button and not self.pulseOverlays[element] then
			self.pulseOverlays[element] = self:CreatePulseOverlay(button)
		end
	end

	-- Start continuous pulse tracking
	if not self.pulseFrame then
		self.pulseFrame = CreateFrame("Frame")

		self.pulseFrame:SetScript("OnUpdate", function(frame, elapsed)
			-- Check Earth totem (slot 2)
			local earthData, earthStart = ShamanPower:GetActivePulsingTotem(2)
			ShamanPower:UpdatePulseGlow(1, earthData, earthStart)

			-- Check Water totem (slot 3)
			local waterData, waterStart = ShamanPower:GetActivePulsingTotem(3)
			ShamanPower:UpdatePulseGlow(3, waterData, waterStart)
		end)
		self.pulseFrame:Show()
	end
end

function ShamanPower:UpdatePulseGlow(element, totemData, startTime)
	local glow = self.pulseOverlays[element]
	if not glow then return end

	if totemData and startTime then
		local now = GetTime()
		local totemAge = now - startTime
		local pulseInterval = totemData.interval

		-- Calculate position within current pulse cycle (0 to 1)
		local cyclePos = (totemAge % pulseInterval) / pulseInterval

		-- Pulse brightens at the start of each cycle
		local alpha
		if cyclePos < 0.15 then
			-- Quick flash at pulse point
			alpha = 1 - (cyclePos / 0.15)
		else
			alpha = 0
		end

		if alpha > 0 then
			glow:SetAlpha(alpha * 0.9)
			glow:Show()
		else
			glow:SetAlpha(0)
			glow:Hide()
		end
	else
		glow:SetAlpha(0)
		glow:Hide()
	end
end

-- ============================================================================
-- Party Range Dots (shows which party members are in totem range)
-- ============================================================================

ShamanPower.partyRangeDots = {}  -- [element][partyIndex] = dot texture

-- Buff names that totems apply to party members (used for range detection)
ShamanPower.TotemBuffNames = {
	[1] = {  -- Earth
		[1] = "Strength of Earth",
		[2] = "Stoneskin",
		-- Tremor, Earthbind, Stoneclaw, Earth Elemental don't have party buffs
	},
	[2] = {  -- Fire
		[1] = "Totem of Wrath",
		[5] = "Flametongue Totem",
		[6] = "Frost Resistance",
		-- Searing, Magma, Fire Nova are damage totems with no party buff
	},
	[3] = {  -- Water
		[1] = "Mana Spring",
		[2] = "Healing Stream",  -- This heals, doesn't buff
		[3] = "Mana Tide",
		[6] = "Fire Resistance",
		-- Poison/Disease cleansing don't have visible buffs
	},
	[4] = {  -- Air
		[1] = "Windfury Totem",
		[2] = "Grace of Air",
		[3] = "Wrath of Air",
		[4] = "Tranquil Air",
		[6] = "Nature Resistance",
		[7] = "Windwall",
	},
}

-- Create party range dots for a totem button
function ShamanPower:CreatePartyRangeDots(button, element)
	if not button then return end
	if self.partyRangeDots[element] then return end  -- Already created

	self.partyRangeDots[element] = {}

	for i = 1, 4 do
		local dot = button:CreateTexture(nil, "OVERLAY")
		dot:SetTexture("Interface\\AddOns\\ShamanPower\\textures\\dot")
		dot:SetSize(5, 5)  -- Smaller dots for inside corners

		-- Position dots inside the button corners (2x2 grid)
		-- 1=top-left, 2=top-right, 3=bottom-left, 4=bottom-right
		if i == 1 then
			dot:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
		elseif i == 2 then
			dot:SetPoint("TOPRIGHT", button, "TOPRIGHT", -1, -1)
		elseif i == 3 then
			dot:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 1, 1)
		else
			dot:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
		end

		dot:SetVertexColor(1, 1, 1)  -- Default white, will be colored by class
		dot:Hide()
		self.partyRangeDots[element][i] = dot
	end
end

-- Setup all party range dots for the mini totem bar
function ShamanPower:SetupPartyRangeDots()
	for element = 1, 4 do
		local button = _G["ShamanPowerAutoTotem" .. element]
		if button then
			self:CreatePartyRangeDots(button, element)
		end
	end

	-- Start the range tracking update if not already running
	if not self.partyRangeFrame then
		self.partyRangeFrame = CreateFrame("Frame")
		self.partyRangeFrame.elapsed = 0

		self.partyRangeFrame:SetScript("OnUpdate", function(frame, elapsed)
			frame.elapsed = frame.elapsed + elapsed
			if frame.elapsed < 0.5 then return end  -- Update every 0.5 seconds
			frame.elapsed = 0

			ShamanPower:UpdatePartyRangeDots()
		end)
		self.partyRangeFrame:Show()
	end
end

-- Get the buff name for the currently active totem of an element
function ShamanPower:GetActiveTotemBuffName(element)
	local slot = self.ElementToSlot[element]
	if not slot then return nil end

	local haveTotem, totemName = GetTotemInfo(slot)
	if not haveTotem or not totemName then return nil end

	-- Match totem name to buff name
	local assignments = ShamanPower_Assignments[self.player]
	if not assignments then return nil end

	local totemIndex = assignments[element]
	if not totemIndex or totemIndex == 0 then return nil end

	-- Return the buff name for this totem type
	local buffNames = self.TotemBuffNames[element]
	if buffNames and buffNames[totemIndex] then
		return buffNames[totemIndex]
	end

	-- Fallback: try to match based on totem name
	for pattern, buffName in pairs(buffNames or {}) do
		if type(buffName) == "string" and totemName:find(buffName) then
			return buffName
		end
	end

	return nil
end

-- Check if a unit has a specific buff
function ShamanPower:UnitHasBuff(unit, buffName)
	if not buffName then return false end

	for i = 1, 40 do
		local name = UnitBuff(unit, i)
		if not name then break end
		if name:find(buffName) then
			return true
		end
	end
	return false
end

-- Update all party range dots
function ShamanPower:UpdatePartyRangeDots()
	-- Check if feature is enabled
	if not self.opt.showPartyRangeDots then
		-- Hide all dots when disabled
		for element = 1, 4 do
			if self.partyRangeDots[element] then
				for i = 1, 4 do
					if self.partyRangeDots[element][i] then
						self.partyRangeDots[element][i]:Hide()
					end
				end
			end
		end
		return
	end

	-- Build list of units to check (party/raid members only, not player)
	local partyUnits = {}
	if IsInRaid() then
		-- Find our subgroup number
		local mySubgroup = 1
		for i = 1, 40 do
			local name, _, subgroup = GetRaidRosterInfo(i)
			if name == UnitName("player") then
				mySubgroup = subgroup
				break
			end
		end
		-- Find other members in our subgroup
		local count = 0
		for i = 1, 40 do
			local name, _, subgroup = GetRaidRosterInfo(i)
			if name and subgroup == mySubgroup and name ~= UnitName("player") then
				count = count + 1
				partyUnits[count] = "raid" .. i
				if count >= 4 then break end
			end
		end
	elseif IsInGroup() then
		-- In a party, use party1-4
		for i = 1, 4 do
			if UnitExists("party" .. i) then
				partyUnits[#partyUnits + 1] = "party" .. i
			end
		end
	end
	-- If solo, partyUnits is empty (no dots shown)

	-- Update dots for each party member
	for partyIndex = 1, 4 do
		local unit = partyUnits[partyIndex]
		local exists = unit and UnitExists(unit)

		-- Get class color for this party member
		local classColor = nil
		if exists then
			local _, class = UnitClass(unit)
			if class and RAID_CLASS_COLORS[class] then
				classColor = RAID_CLASS_COLORS[class]
			end
		end

		-- Check each element
		for element = 1, 4 do
			local dot = self.partyRangeDots[element] and self.partyRangeDots[element][partyIndex]
			if dot then
				if not exists then
					dot:Hide()
				else
					local slot = self.ElementToSlot[element]
					local haveTotem = slot and GetTotemInfo(slot)

					if haveTotem then
						-- Totem is active - check if party member has the buff
						local buffName = self:GetActiveTotemBuffName(element)
						local hasBuff = buffName and self:UnitHasBuff(unit, buffName)

						if hasBuff then
							-- In range - show class-colored dot
							if classColor then
								dot:SetVertexColor(classColor.r, classColor.g, classColor.b)
							else
								dot:SetVertexColor(0, 1, 0)  -- Green
							end
						elseif buffName then
							-- Has a buff to check but doesn't have it - out of range (red)
							dot:SetVertexColor(1, 0, 0)
						else
							-- No buff to check (damage totem, etc.) - show class color
							if classColor then
								dot:SetVertexColor(classColor.r, classColor.g, classColor.b)
							else
								dot:SetVertexColor(0.5, 0.5, 0.5)  -- Gray
							end
						end
						dot:Show()
					else
						-- No totem active for this element
						dot:Hide()
					end
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
	{324, "Lightning Shield", "shield"},   -- Lightning/Water Shield (combined)
	{36936, "Totemic Call", "cooldown"},  -- Totemic Call (recall totems)
	{20608, "Reincarnation", "cooldown"},  -- Ankh cooldown
	{16188, "Nature's Swiftness", "cooldown"},  -- NS cooldown (Resto talent)
	{16190, "Mana Tide Totem", "cooldown"},  -- Mana Tide cooldown (Resto talent)
	{2825, "Bloodlust", "cooldown"},  -- Bloodlust (Horde)
	{32182, "Heroism", "cooldown"},  -- Heroism (Alliance)
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
	bar:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 12,
		insets = { left = 2, right = 2, top = 2, bottom = 2 }
	})
	bar:SetBackdropColor(0, 0, 0, 0.7)
	bar:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)

	self.cooldownBar = bar
	self.cooldownButtons = {}

	-- Create buttons for each tracked spell
	local buttonSize = 22
	local spacing = 8  -- Increased spacing to prevent cooldown text overlap
	local padding = 4
	local numButtons = 0

	for i, spellData in ipairs(self.TrackedCooldowns) do
		local spellID, spellName, spellType = spellData[1], spellData[2], spellData[3]
		local name, _, icon = GetSpellInfo(spellID)

		-- For shield type, check if player knows any shield spell
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

		-- Only create button if player knows this spell
		if knowsSpell then
			numButtons = numButtons + 1

			-- Use SecureActionButtonTemplate for clickable buttons
			local btn = CreateFrame("Button", "ShamanPowerCD" .. i, bar, "SecureActionButtonTemplate")
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

			-- Set up click action
			if spellType == "shield" then
				-- Shield button casts the preferred shield
				local shieldSpellName = GetSpellInfo(defaultShieldSpell)
				if shieldSpellName then
					btn:SetAttribute("type1", "spell")
					btn:SetAttribute("spell1", shieldSpellName)
				end
			else
				-- Regular cooldown buttons cast their spell
				local castSpellName = GetSpellInfo(spellID)
				if castSpellName then
					btn:SetAttribute("type1", "spell")
					btn:SetAttribute("spell1", castSpellName)
				end
			end

			-- Tooltip
			btn:SetScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				if self.activeShieldID then
					GameTooltip:SetSpellByID(self.activeShieldID)
				elseif self.spellType == "shield" and self.defaultShieldSpell then
					-- defaultShieldSpell is a spell name, use it directly
					local spellName = self.defaultShieldSpell
					local name, _, icon, _, _, _, spellID = GetSpellInfo(spellName)
					if spellID then
						GameTooltip:SetSpellByID(spellID)
					else
						GameTooltip:SetText(spellName)
					end
				else
					GameTooltip:SetSpellByID(self.spellID)
				end
				GameTooltip:Show()
			end)
			btn:SetScript("OnLeave", function()
				GameTooltip:Hide()
			end)

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

	-- Start the update timer
	if not self.cooldownUpdateFrame then
		self.cooldownUpdateFrame = CreateFrame("Frame")
		self.cooldownUpdateFrame.elapsed = 0
		self.cooldownUpdateFrame:SetScript("OnUpdate", function(frame, elapsed)
			frame.elapsed = frame.elapsed + elapsed
			if frame.elapsed < 0.2 then return end
			frame.elapsed = 0
			ShamanPower:UpdateCooldownButtons()
		end)
	end
end

-- Update cooldown bar layout (horizontal or vertical)
function ShamanPower:UpdateCooldownBarLayout()
	if not self.cooldownBar then return end
	if #self.cooldownButtons == 0 then return end

	local bar = self.cooldownBar
	local buttonSize = bar.buttonSize or 22
	local spacing = bar.spacing or 8
	local padding = bar.padding or 4
	local numButtons = #self.cooldownButtons
	local isVertical = (self.opt.layout == "Vertical")

	if isVertical then
		-- Vertical: stack buttons top to bottom
		local barHeight = (buttonSize * numButtons) + (spacing * (numButtons - 1)) + (padding * 2)
		bar:SetSize(buttonSize + (padding * 2), barHeight)

		for i, btn in ipairs(self.cooldownButtons) do
			btn:ClearAllPoints()
			btn:SetPoint("TOP", bar, "TOP", 0, -padding - (i - 1) * (buttonSize + spacing))
		end
	else
		-- Horizontal: buttons left to right
		local barWidth = (buttonSize * numButtons) + (spacing * (numButtons - 1)) + (padding * 2)
		bar:SetSize(barWidth, buttonSize + (padding * 2))

		for i, btn in ipairs(self.cooldownButtons) do
			btn:ClearAllPoints()
			btn:SetPoint("LEFT", bar, "LEFT", padding + (i - 1) * (buttonSize + spacing), 0)
		end
	end
end

function ShamanPower:UpdateCooldownButtons()
	for _, btn in ipairs(self.cooldownButtons) do
		if btn.spellType == "shield" then
			-- Check if any shield is active
			local hasShield = false
			local activeShieldID = nil
			local activeShieldIcon = nil

			local shieldCharges = 0
			for _, shieldData in ipairs(self.ShieldSpells) do
				local shieldID, shieldName = shieldData[1], shieldData[2]
				-- Use UnitBuff to get charges (count)
				for i = 1, 40 do
					local name, icon, count = UnitBuff("player", i)
					if not name then break end
					if name == shieldName then
						hasShield = true
						activeShieldID = shieldID
						activeShieldIcon = icon
						shieldCharges = count or 0
						break
					end
				end
				if hasShield then break end
			end

			if hasShield then
				btn.darkOverlay:Hide()
				btn.icon:SetDesaturated(false)
				if activeShieldIcon then
					btn.icon:SetTexture(activeShieldIcon)
				end
				btn.activeShieldID = activeShieldID
				-- Show charge count
				if btn.chargeText then
					if shieldCharges > 0 then
						btn.chargeText:SetText(tostring(shieldCharges))
					else
						btn.chargeText:SetText("")
					end
				end
			else
				btn.darkOverlay:Show()
				btn.icon:SetDesaturated(true)
				btn.activeShieldID = nil
				-- Clear charge count when no shield
				if btn.chargeText then
					btn.chargeText:SetText("")
				end
			end
			btn.cooldown:Clear()

		elseif btn.spellType == "cooldown" then
			-- Check cooldown
			local start, duration, enabled = GetSpellCooldown(btn.spellID)
			if start and start > 0 and duration > 1.5 then
				btn.cooldown:SetCooldown(start, duration)
				btn.darkOverlay:Hide()
				btn.icon:SetDesaturated(false)
			else
				btn.cooldown:Clear()
				btn.darkOverlay:Hide()
				btn.icon:SetDesaturated(false)
			end
		end
	end
end

function ShamanPower:UpdateCooldownBar()
	if not self.cooldownBar then
		self:CreateCooldownBar()
	end

	if not self.cooldownBar then return end

	if self.opt.showCooldownBar and #self.cooldownButtons > 0 then
		-- Update the button layout first
		self:UpdateCooldownBarLayout()

		-- Position based on layout orientation
		local isVertical = (self.opt.layout == "Vertical")
		self.cooldownBar:ClearAllPoints()
		if isVertical then
			-- Vertical: position to the left of the main totem bar
			self.cooldownBar:SetPoint("RIGHT", self.autoButton, "LEFT", -2, 0)
		else
			-- Horizontal: position below the main totem bar
			self.cooldownBar:SetPoint("TOP", self.autoButton, "BOTTOM", 0, -2)
		end
		self.cooldownBar:Show()
		self.cooldownUpdateFrame:Show()
	else
		self.cooldownBar:Hide()
		if self.cooldownUpdateFrame then
			self.cooldownUpdateFrame:Hide()
		end
	end
end

function ShamanPower:RecreateCooldownBar()
	if InCombatLockdown() then return end

	-- Destroy existing cooldown bar
	if self.cooldownBar then
		self.cooldownBar:Hide()
		self.cooldownBar:SetParent(nil)
		self.cooldownBar = nil
	end
	self.cooldownButtons = {}

	-- Recreate it
	self:CreateCooldownBar()
	self:UpdateCooldownBar()
end

-- ============================================================================
-- Mini Totem Bar (built-in totem buttons when TotemTimers is not used)
-- ============================================================================

-- Update the mini totem bar icons and spells based on current assignments
function ShamanPower:UpdateMiniTotemBar()
	if not self.autoButton then return end
	if InCombatLockdown() then return end

	local playerName = self.player
	local assignments = ShamanPower_Assignments[playerName]
	if not assignments then return end

	-- Determine layout orientation
	local isHorizontal = (self.opt.layout == "Horizontal")
	local buttonSize = 26
	local spacing = 4
	local padding = 4
	local separatorSize = 12  -- Extra gap for separator
	local showDropAll = self.opt.showDropAllButton ~= false  -- Default to true if not set

	-- Resize the parent frame based on layout
	if isHorizontal then
		-- Horizontal: wide and short
		local totalWidth = (buttonSize * 4) + (spacing * 3) + (padding * 2)
		if showDropAll then
			totalWidth = totalWidth + separatorSize + buttonSize
		end
		self.autoButton:SetSize(totalWidth, buttonSize + (padding * 2))
	else
		-- Vertical: narrow and tall
		local totalHeight = (buttonSize * 4) + (spacing * 3) + (padding * 2)
		if showDropAll then
			totalHeight = totalHeight + separatorSize + buttonSize
		end
		self.autoButton:SetSize(buttonSize + (padding * 2), totalHeight)
	end

	for element = 1, 4 do
		local totemButton = _G["ShamanPowerAutoTotem" .. element]
		if totemButton then
			local totemIndex = assignments[element] or 0
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

			-- Reposition buttons based on layout
			totemButton:ClearAllPoints()
			if isHorizontal then
				-- Horizontal: buttons go left to right
				totemButton:SetPoint("TOPLEFT", self.autoButton, "TOPLEFT", padding + (element - 1) * (buttonSize + spacing), -padding)
			else
				-- Vertical: buttons go top to bottom
				totemButton:SetPoint("TOPLEFT", self.autoButton, "TOPLEFT", padding, -padding - (element - 1) * (buttonSize + spacing))
			end

			-- Set up the button: left-click casts totem, right-click destroys it
			totemButton:RegisterForClicks("AnyUp", "AnyDown")

			-- Clear old attributes first
			totemButton:SetAttribute("type", nil)
			totemButton:SetAttribute("spell", nil)

			-- Left-click: cast totem
			if spellName then
				totemButton:SetAttribute("type1", "spell")
				totemButton:SetAttribute("spell1", spellName)
			else
				totemButton:SetAttribute("type1", nil)
				totemButton:SetAttribute("spell1", nil)
			end

			-- Right-click: destroy totem (using macro to call DestroyTotem)
			local slot = self.ElementToSlot[element]
			totemButton:SetAttribute("type2", "macro")
			totemButton:SetAttribute("macrotext2", "/run DestroyTotem(" .. slot .. ")")
		end
	end

	-- Create or update separator line
	local separator = _G["ShamanPowerAutoSeparator"]
	if not separator then
		separator = self.autoButton:CreateTexture("ShamanPowerAutoSeparator", "ARTWORK")
		separator:SetColorTexture(0.5, 0.5, 0.5, 0.8)  -- Gray line
	end

	-- Reposition the Drop All button (after the separator)
	local dropAllButton = _G["ShamanPowerAutoDropAll"]

	if showDropAll then
		separator:ClearAllPoints()
		if isHorizontal then
			-- Vertical separator line
			separator:SetSize(2, buttonSize)
			local separatorX = padding + (buttonSize * 4) + (spacing * 3) + (separatorSize / 2) - 1
			separator:SetPoint("TOPLEFT", self.autoButton, "TOPLEFT", separatorX, -padding)
		else
			-- Horizontal separator line
			separator:SetSize(buttonSize, 2)
			local separatorY = -padding - (buttonSize * 4) - (spacing * 3) - (separatorSize / 2) + 1
			separator:SetPoint("TOPLEFT", self.autoButton, "TOPLEFT", padding, separatorY)
		end
		separator:Show()

		if dropAllButton then
			dropAllButton:ClearAllPoints()
			if isHorizontal then
				-- Horizontal: Drop All is after the separator
				local dropAllX = padding + (buttonSize * 4) + (spacing * 3) + separatorSize
				dropAllButton:SetPoint("TOPLEFT", self.autoButton, "TOPLEFT", dropAllX, -padding)
			else
				-- Vertical: Drop All is below the separator
				local dropAllY = -padding - (buttonSize * 4) - (spacing * 3) - separatorSize
				dropAllButton:SetPoint("TOPLEFT", self.autoButton, "TOPLEFT", padding, dropAllY)
			end
			dropAllButton:Show()
		end
	else
		-- Hide separator and Drop All button
		separator:Hide()
		if dropAllButton then
			dropAllButton:Hide()
		end
	end

	-- Update Earth Shield button (if shaman has ES and a target assigned)
	self:UpdateEarthShieldButton()

	-- Setup pulse overlays for totems like Tremor
	self:SetupPulseOverlays()

	-- Setup party range dots
	self:SetupPartyRangeDots()

	-- Setup cooldown tracker bar
	self:UpdateCooldownBar()

	-- Setup keybindings for the buttons
	self:SetupKeybindings()
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
		GameTooltip:AddLine("Click to cast", 0.7, 0.7, 0.7)
	else
		GameTooltip:AddLine("No totem assigned", 1, 0, 0)
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

	local esBtn = CreateFrame("Button", "ShamanPowerEarthShieldBtn", self.autoButton, "SecureActionButtonTemplate")
	esBtn:SetSize(26, 26)
	esBtn:Hide()

	-- Icon (simple, matching other totem buttons)
	local icon = esBtn:CreateTexture("ShamanPowerEarthShieldBtnIcon", "ARTWORK")
	icon:SetAllPoints()
	icon:SetTexture(self.EarthShield.icon)

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

	-- Tooltip
	esBtn:SetScript("OnEnter", function(self)
		if not ShamanPower.opt.ShowTooltips then return end
		local target = ShamanPower_EarthShieldAssignments[ShamanPower.player]
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Earth Shield", 0.2, 0.8, 0.2)
		if target then
			local charges = ShamanPower:GetEarthShieldCharges(target)
			GameTooltip:AddLine("Target: " .. target, 1, 1, 1)
			if charges and charges > 0 then
				GameTooltip:AddLine("Charges: " .. charges, 0, 1, 0)
			else
				GameTooltip:AddLine("Not active", 1, 0.5, 0)
			end
			GameTooltip:AddLine("Click to cast on " .. target, 0.7, 0.7, 0.7)
		else
			GameTooltip:AddLine("No target assigned", 1, 0, 0)
		end
		GameTooltip:Show()
	end)
	esBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

	-- Update charges periodically
	esBtn:SetScript("OnUpdate", function(self, elapsed)
		self.timeSinceLastUpdate = (self.timeSinceLastUpdate or 0) + elapsed
		if self.timeSinceLastUpdate > 0.5 then  -- Update every 0.5 seconds
			self.timeSinceLastUpdate = 0
			ShamanPower:UpdateEarthShieldCharges()
		end
	end)

	esBtn:RegisterForClicks("AnyUp", "AnyDown")
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

-- Update the charge display on the button
function ShamanPower:UpdateEarthShieldCharges()
	local chargeText = _G["ShamanPowerEarthShieldBtnCharges"]
	if not chargeText then return end

	local targetName = ShamanPower_EarthShieldAssignments[self.player]
	if not targetName then
		chargeText:SetText("")
		return
	end

	local charges = self:GetEarthShieldCharges(targetName)
	if charges and charges > 0 then
		chargeText:SetText(tostring(charges))
		chargeText:SetTextColor(1, 1, 1)  -- White
	else
		chargeText:SetText("")
	end
end

function ShamanPower:UpdateEarthShieldButton()
	if InCombatLockdown() then return end
	if not self.autoButton then return end

	-- Create button if it doesn't exist
	self:CreateEarthShieldButton()

	local esBtn = _G["ShamanPowerEarthShieldBtn"]
	if not esBtn then return end

	local esIcon = _G["ShamanPowerEarthShieldBtnIcon"]
	local esName = _G["ShamanPowerEarthShieldBtnName"]

	-- Check if we have Earth Shield and a target assigned
	local hasES = self:HasEarthShield()
	local targetName = ShamanPower_EarthShieldAssignments[self.player]

	if hasES and targetName then
		-- Get the spell name
		local spellName = self:GetEarthShieldSpell()
		if spellName then
			-- Set up the button to target and cast Earth Shield
			-- Using a macro to target the player and cast
			-- Use type1/macrotext1 for left-click (needed for /click macro to work)
			esBtn:SetAttribute("type1", "macro")
			esBtn:SetAttribute("macrotext1", "/target " .. targetName .. "\n/cast " .. spellName .. "\n/targetlasttarget")

			-- Update icon
			if esIcon then
				esIcon:SetTexture(self.EarthShield.icon)
			end

			-- Show target name
			if esName then
				local shortName = Ambiguate(targetName, "short")
				esName:SetText(shortName)
				esName:Show()
			end

			esBtn:Show()

			-- Reposition in the mini bar
			self:RepositionEarthShieldButton()
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

	local isHorizontal = (self.opt.layout == "Horizontal")
	local buttonSize = 26
	local spacing = 4
	local padding = 4
	local separatorSize = 12
	local showDropAll = self.opt.showDropAllButton ~= false

	-- Position Earth Shield button after Drop All button (or where it would be)
	esBtn:ClearAllPoints()

	if isHorizontal then
		local esX
		local totalWidth
		if showDropAll then
			-- After Drop All horizontally
			esX = padding + (buttonSize * 4) + (spacing * 3) + separatorSize + buttonSize + spacing
			totalWidth = (buttonSize * 4) + (spacing * 3) + separatorSize + buttonSize + spacing + buttonSize + (padding * 2)
		else
			-- Where Drop All would be (after totems with separator)
			esX = padding + (buttonSize * 4) + (spacing * 3) + separatorSize
			totalWidth = (buttonSize * 4) + (spacing * 3) + separatorSize + buttonSize + (padding * 2)
		end
		esBtn:SetPoint("TOPLEFT", self.autoButton, "TOPLEFT", esX, -padding)
		self.autoButton:SetWidth(totalWidth)
	else
		local esY
		local totalHeight
		if showDropAll then
			-- Below Drop All vertically
			esY = -padding - (buttonSize * 4) - (spacing * 3) - separatorSize - buttonSize - spacing
			totalHeight = (buttonSize * 4) + (spacing * 3) + separatorSize + buttonSize + spacing + buttonSize + (padding * 2)
		else
			-- Where Drop All would be
			esY = -padding - (buttonSize * 4) - (spacing * 3) - separatorSize
			totalHeight = (buttonSize * 4) + (spacing * 3) + separatorSize + buttonSize + (padding * 2)
		end
		esBtn:SetPoint("TOPLEFT", self.autoButton, "TOPLEFT", padding, esY)
		self.autoButton:SetHeight(totalHeight)
	end
end

-- ============================================================================
-- Drop All Button - cycles through all 4 totems
-- ============================================================================

ShamanPower.dropAllCurrentElement = 1  -- Start with Earth
ShamanPower.dropAllSequence = {}  -- Ordered list of {element, spellName, icon}
ShamanPower.dropAllInCombat = false  -- Track if we were in combat
ShamanPower.dropAllLastMacro = ""  -- Track last macro to avoid unnecessary rebuilds

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

	local playerName = self.player
	local assignments = ShamanPower_Assignments[playerName]
	if not assignments then return end

	-- Build ordered list of assigned totems using custom drop order
	local newSequence = {}
	local totemSpells = {}
	local dropOrder = self.opt.dropOrder or {1, 2, 3, 4}
	for _, element in ipairs(dropOrder) do
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
	GameTooltip:Show()
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
	self:UpdateLayout()
	self:UpdateRoster()
	self:ReportChannels()

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
	self:ScanSpells()
	self:ScanCooldowns()
	self:ScanInventory()
	self:UpdateLayout()
	self:UpdateRoster()
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
	local units
	for i = 1, SHAMANPOWER_MAXCLASSES do
		classlist[i] = 0
		classes[i] = {}
		classmaintanks[i] = false
	end
	if IsInRaid() then
		units = raid_units
	else
		units = party_units
	end
	twipe(roster)
	twipe(leaders)
	for _, unitid in pairs(units) do
		if unitid and UnitExists(unitid) then
			local tmp = {}
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
	local x = self.opt.display.buttonWidth
	local y = self.opt.display.buttonHeight
	local point = "TOPLEFT"
	local pointOpposite = "BOTTOMLEFT"
	local layout = self.Layouts[self.opt.layout]
	if not layout then
		-- Fallback to Vertical if the configured layout doesn't exist
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

	-- Preset Button handling: show/hide if leader
	local presetButton = _G["ShamanPowerBlessingsFramePreset"]
	local reportButton = _G["ShamanPowerBlessingsFrameReport"]
	local autoassignButton = _G["ShamanPowerBlessingsAutoAssign"]
	if self:CheckLeader(self.player) then
		presetButton:Show()
		reportButton:SetPoint("BOTTOMRIGHT", presetButton, "BOTTOMLEFT", -7, 0)
	else
		presetButton:Hide()
		reportButton:SetPoint("BOTTOMRIGHT", autoassignButton, "BOTTOMLEFT", -7, 0)
	end

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
		-- Position the anchor relative to the mini totem bar (autoButton) if it's visible
		if self.autoButton and self.autoButton:IsShown() then
			ShamanPowerAnchor:ClearAllPoints()
			ShamanPowerAnchor:SetPoint("BOTTOM", self.autoButton, "TOP", 0, 4)
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
		self.opt.display.frameLocked = not self.opt.display.frameLocked
		if (self.opt.display.frameLocked) then
			if (self.opt.display.LockBuffBars) then
				LOCK_ACTIONBAR = "1"
			end
			local h = _G["ShamanPowerFrame"]
			_, _, _, self.opt.display.offsetX, self.opt.display.offsetY = h:GetPoint()
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
	-- Save position immediately so it persists
	_, _, _, self.opt.display.offsetX, self.opt.display.offsetY = h:GetPoint()
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
	ShamanPowerAuto:SetBackdrop(tmp)
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
	["SHAMANPOWER_EARTH_TOTEM"] = "ShamanPowerAutoTotem1",
	["SHAMANPOWER_FIRE_TOTEM"] = "ShamanPowerAutoTotem2",
	["SHAMANPOWER_WATER_TOTEM"] = "ShamanPowerAutoTotem3",
	["SHAMANPOWER_AIR_TOTEM"] = "ShamanPowerAutoTotem4",
	["SHAMANPOWER_EARTH_SHIELD"] = "ShamanPowerEarthShieldBtn",
	["SHAMANPOWER_TOTEMIC_CALL"] = "ShamanPowerTotemicCallBtn",
}

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

	-- Set up override bindings for each keybind
	for bindingName, buttonName in pairs(self.KeybindButtons) do
		local key1, key2 = GetBindingKey(bindingName)
		if key1 then
			SetOverrideBindingClick(self.keybindFrame, false, key1, buttonName, "LeftButton")
		end
		if key2 then
			SetOverrideBindingClick(self.keybindFrame, false, key2, buttonName, "LeftButton")
		end
	end

	self.keybindsPending = false
end

-- Register for binding updates
local keybindEventFrame = CreateFrame("Frame")
keybindEventFrame:RegisterEvent("UPDATE_BINDINGS")
keybindEventFrame:RegisterEvent("PLAYER_LOGIN")
keybindEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
keybindEventFrame:SetScript("OnEvent", function(self, event)
	-- If leaving combat, check if we have pending keybind setup
	if event == "PLAYER_REGEN_ENABLED" then
		if ShamanPower.keybindsPending then
			ShamanPower:SetupKeybindings()
		end
		return
	end

	-- Delay slightly to ensure buttons exist
	C_Timer.After(0.5, function()
		if ShamanPower.SetupKeybindings then
			ShamanPower:SetupKeybindings()
		end
	end)
end)
