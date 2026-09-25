-- "First Surname" on WoW: Forever (SPCompat.UnitName); other clients unchanged
local UnitName = (SPCompat and SPCompat.UnitName) or UnitName
local L = LibStub("AceLocale-3.0"):GetLocale("ShamanPower")

local isShaman = select(2, UnitClass("player")) == "SHAMAN"

-- Presentation only: keep each option object and its callbacks while arranging
-- a page in bands. A heading disappears when every row in its band is hidden.
function ShamanPower.OrderSettingsBands(group, bands)
	local args, used = group.args, {}
	for index, band in ipairs(bands) do
		local base, members = index * 1000, {}
		for offset, key in ipairs(band.keys) do
			local option = args[key]
			if option then
				option.order = base + offset
				if band.names and band.names[key] then option.name = band.names[key] end
				used[key], members[#members + 1] = true, key
			end
		end
		if band.header then
			local header = args[band.header] or { type = "header" }
			local previous = header.hidden
			header.name, header.order = band.name or header.name, base
			header.hidden = function(info)
				local hidden = previous
				if type(hidden) == "function" then hidden = hidden(info) end
				if hidden then return true end
				for _, key in ipairs(members) do
					local option = args[key]
					if option then
						local value = option.hidden
						if type(value) == "function" then
							local childInfo = {}
							for k, v in pairs(info or {}) do childInfo[k] = v end
							childInfo[math.max(1, #childInfo)] = key
							childInfo.option, childInfo.type, childInfo.arg = option, option.type, option.arg
							value = value(childInfo)
						end
						if not value then return false end
					end
				end
				return true
			end
			args[band.header], used[band.header] = header, true
		end
	end
	-- Replaced headings are presentation, not settings. Keep unlisted controls
	-- at the end so a later contributor is never silently lost.
	for key, option in pairs(args) do
		if not used[key] then
			if option.type == "header" then
				args[key] = nil
			else
				local previous = type(option.order) == "number" and option.order or 0
				option.order = (#bands + 1) * 1000 + previous
			end
		end
	end
end

-- Shared args table for loadouts section (rebuilt in-place by RefreshLoadoutArgs)
local loadoutArgs = {}

-- Element names and color codes for totem dropdowns (matches TotemTimers ElementColors)
local loadoutElementNames = {
	[1] = "|cffb3804dEarth|r",  -- 0.7, 0.5, 0.3
	[2] = "|cffff1a1aFire|r",   -- 1.0, 0.1, 0.1
	[3] = "|cff6666ffWater|r",  -- 0.4, 0.4, 1.0
	[4] = "|cffffffffAir|r",    -- 1.0, 1.0, 1.0
}

-- Build totem dropdown values for a given element
-- Loadout totem pickers: a totem this character has not learned yet is marked, since the
-- game will not drop it (and Blizzard's totem bar will not hold it) until it is
local function GetTotemValues(element)
	local mainline = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE
	return function()
		local values = { [0] = "None" }
		for idx, name in pairs(ShamanPower.TotemNames[element] or {}) do
			if not mainline or ShamanPower:TotemExistsOnClient(element, idx) then
				local learned = not ShamanPower.KnowsTotem or ShamanPower:KnowsTotem(element, idx)
				values[idx] = learned and name or (name .. " |cff888888(not learned)|r")
			end
		end
		return values
	end
end

-- Build sorted key list for totem dropdown
local function GetTotemSorting(element)
	if WOW_PROJECT_ID == WOW_PROJECT_MAINLINE then
		return function()
			local sorting = { 0 }
			for idx in pairs(ShamanPower.TotemNames[element] or {}) do
				if ShamanPower:TotemExistsOnClient(element, idx) then tinsert(sorting, idx) end
			end
			table.sort(sorting)
			return sorting
		end
	end
	local sorting = {0}
	local names = ShamanPower.TotemNames[element]
	if names then
		for idx in pairs(names) do
			tinsert(sorting, idx)
		end
	end
	table.sort(sorting)
	return sorting
end

-- Icon choices for custom loadout icons (element icons + common totems + "None" to reset)
-- ============================================================================
-- ICON PICKER POPUP (same as TotemTimers IconPicker.lua)
-- Scrollable grid of icons for choosing a loadout icon
-- ============================================================================
local ICONS_PER_ROW = 6
local ICON_SIZE = 36
local ICON_SPACING = 4
local VISIBLE_ROWS = 12
local ROW_HEIGHT = ICON_SIZE + ICON_SPACING

local allIcons = {}
local filteredIcons = {}
local iconPickerFrame = nil
local currentCallback = nil
local selectedIconIndex = nil

local function BuildIconList()
	if #allIcons > 0 then return end

	-- Try WoW API first (returns hundreds of spell/item icons)
	local macroIcons = GetMacroIcons and GetMacroIcons()
	if macroIcons then
		for i = 1, #macroIcons do
			tinsert(allIcons, macroIcons[i])
		end
	end
	local itemIcons = GetMacroItemIcons and GetMacroItemIcons()
	if itemIcons then
		for i = 1, #itemIcons do
			tinsert(allIcons, itemIcons[i])
		end
	end

	-- Fallback: hardcoded shaman-relevant icons (same as TotemTimers)
	if #allIcons == 0 then
		local commonIcons = {
			"Interface\\Icons\\Spell_Nature_Lightning",
			"Interface\\Icons\\Spell_Nature_ChainLightning",
			"Interface\\Icons\\Spell_Fire_FlameShock",
			"Interface\\Icons\\Spell_Nature_EarthShock",
			"Interface\\Icons\\Spell_Frost_FrostShock2",
			"Interface\\Icons\\Spell_Nature_MagicImmunity",
			"Interface\\Icons\\Ability_Shaman_Stormstrike",
			"Interface\\Icons\\Spell_Nature_LightningShield",
			"Interface\\Icons\\Spell_Fire_Volcano",
			"Interface\\Icons\\Spell_Nature_HealingWaveGreater",
			"Interface\\Icons\\Spell_Nature_StoneSkinTotem",
			"Interface\\Icons\\Spell_Fire_SearingTotem",
			"Interface\\Icons\\Spell_Nature_ManaRegenTotem",
			"Interface\\Icons\\Spell_Nature_InvisibilityTotem",
			"Interface\\Icons\\Spell_Nature_Cyclone",
			"Interface\\Icons\\Spell_Nature_EarthBindTotem",
			"Interface\\Icons\\Spell_Nature_TremorTotem",
			"Interface\\Icons\\Spell_Fire_SelfDestruct",
			"Interface\\Icons\\Spell_Nature_GroundingTotem",
			"Interface\\Icons\\Spell_Nature_Purge",
			"Interface\\Icons\\Spell_Nature_SkinofEarth",
			"Interface\\Icons\\Spell_Nature_Bloodlust",
			"Interface\\Icons\\Spell_Nature_UnyeildingStamina",
			"Interface\\Icons\\Spell_FireResistanceTotem_01",
			"Interface\\Icons\\Spell_FrostResistanceTotem_01",
			"Interface\\Icons\\Spell_Nature_NatureResistanceTotem",
			"Interface\\Icons\\Spell_Nature_WispSplode",
			"Interface\\Icons\\Spell_Fire_TotemOfWrath",
			"Interface\\Icons\\Spell_Nature_ManaTide",
			"Interface\\Icons\\Spell_Shaman_TotemRecall",
			"Interface\\Icons\\Spell_Nature_EarthElemental_Totem",
			"Interface\\Icons\\Spell_Fire_SealOfFire",
			"Interface\\Icons\\Spell_Frost_SummonWaterElemental",
			"Interface\\Icons\\Spell_Nature_Windfury",
			"Interface\\Icons\\Spell_Nature_SlowingTotem",
			"Interface\\Icons\\Spell_Nature_Brilliance",
			"Interface\\Icons\\Spell_Fire_FlameTounge",
			"Interface\\Icons\\ClassIcon_Shaman",
			"Interface\\Icons\\ClassIcon_Warrior",
			"Interface\\Icons\\ClassIcon_Paladin",
			"Interface\\Icons\\ClassIcon_Hunter",
			"Interface\\Icons\\ClassIcon_Rogue",
			"Interface\\Icons\\ClassIcon_Priest",
			"Interface\\Icons\\ClassIcon_Mage",
			"Interface\\Icons\\ClassIcon_Warlock",
			"Interface\\Icons\\ClassIcon_Druid",
			"Interface\\Icons\\Ability_ThunderBolt",
			"Interface\\Icons\\Ability_DualWield",
			"Interface\\Icons\\Ability_Warrior_BattleShout",
			"Interface\\Icons\\Achievement_PVP_A_A",
			"Interface\\Icons\\Achievement_PVP_H_H",
			"Interface\\Icons\\INV_BannerPVP_01",
			"Interface\\Icons\\INV_BannerPVP_02",
			"Interface\\Icons\\Spell_Holy_PrayerOfHealing",
			"Interface\\Icons\\INV_Misc_Head_Dragon_01",
			"Interface\\Icons\\INV_Misc_QuestionMark",
			"Interface\\Icons\\INV_Shield_06",
			"Interface\\Icons\\INV_Hammer_04",
			"Interface\\Icons\\INV_Spear_04",
			"Interface\\Icons\\Spell_Holy_MindSooth",
			"Interface\\Icons\\Ability_Parry",
			"Interface\\Icons\\Achievement_Zone_Durotar",
			"Interface\\Icons\\Achievement_Zone_ElwynnForest",
		}
		for _, icon in ipairs(commonIcons) do
			tinsert(allIcons, icon)
		end
	end

	filteredIcons = allIcons
end

-- The Config dialog and the fallback use the same lazily built catalogue.
function ShamanPower.GetLoadoutIconChoices()
	BuildIconList()
	return allIcons
end

local function UpdateVisibleButtons()
	if not iconPickerFrame then return end

	local scrollFrame = iconPickerFrame.scrollFrame
	local offset = scrollFrame:GetVerticalScroll()
	local firstVisibleRow = math.floor(offset / ROW_HEIGHT)
	local firstIconIndex = firstVisibleRow * ICONS_PER_ROW + 1

	for i, btn in ipairs(iconPickerFrame.iconButtons) do
		local iconIndex = firstIconIndex + i - 1
		if iconIndex <= #filteredIcons then
			local iconPath = filteredIcons[iconIndex]
			btn.iconIndex = iconIndex
			btn.iconPath = iconPath
			btn.icon:SetTexture(iconPath)
			if iconIndex == selectedIconIndex then
				btn.border:Show()
			else
				btn.border:Hide()
			end
			btn:Show()
		else
			btn:Hide()
		end
	end
end

local function InitializeScrollFrame()
	if not iconPickerFrame then return end
	local scrollFrame = iconPickerFrame.scrollFrame
	local numRows = math.ceil(#filteredIcons / ICONS_PER_ROW)
	local totalHeight = numRows * ROW_HEIGHT
	FauxScrollFrame_Update(scrollFrame, numRows, VISIBLE_ROWS, ROW_HEIGHT)
	UpdateVisibleButtons()
end

local function CreateIconPickerFrame()
	if iconPickerFrame then return end

	local frameWidth = ICONS_PER_ROW * (ICON_SIZE + ICON_SPACING) + 50
	local frameHeight = VISIBLE_ROWS * ROW_HEIGHT + 110

	local frame = CreateFrame("Frame", "ShamanPower_IconPicker", UIParent, "BasicFrameTemplateWithInset")
	frame:SetSize(frameWidth, frameHeight)
	frame:SetFrameStrata("FULLSCREEN_DIALOG")
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:Hide()

	frame.TitleText:SetText("Choose an Icon")

	-- Currently selected icon display
	local selectedBG = frame:CreateTexture(nil, "BACKGROUND")
	selectedBG:SetSize(ICON_SIZE + 8, ICON_SIZE + 8)
	selectedBG:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, -35)
	selectedBG:SetColorTexture(0.2, 0.2, 0.2, 1)

	local selectedIcon = frame:CreateTexture(nil, "ARTWORK")
	selectedIcon:SetSize(ICON_SIZE, ICON_SIZE)
	selectedIcon:SetPoint("CENTER", selectedBG, "CENTER")
	frame.selectedIcon = selectedIcon

	local selectedLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	selectedLabel:SetPoint("LEFT", selectedBG, "RIGHT", 10, 0)
	selectedLabel:SetText("Selected")

	-- Container for icons (clips content)
	local iconContainer = CreateFrame("Frame", nil, frame)
	iconContainer:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, -80)
	iconContainer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -35, 45)
	iconContainer:SetClipsChildren(true)
	frame.iconContainer = iconContainer

	-- Scroll frame
	local scrollFrame = CreateFrame("ScrollFrame", "ShamanPower_IconPickerScroll", frame, "FauxScrollFrameTemplate")
	scrollFrame:SetPoint("TOPLEFT", iconContainer, "TOPLEFT", 0, 0)
	scrollFrame:SetPoint("BOTTOMRIGHT", iconContainer, "BOTTOMRIGHT", -18, 0)
	frame.scrollFrame = scrollFrame

	-- Create visible icon buttons (enough for visible area + 1 row buffer)
	local numVisibleButtons = ICONS_PER_ROW * (VISIBLE_ROWS + 1)
	frame.iconButtons = {}

	for i = 1, numVisibleButtons do
		local btn = CreateFrame("Button", nil, iconContainer)
		btn:SetSize(ICON_SIZE, ICON_SIZE)

		local row = math.floor((i - 1) / ICONS_PER_ROW)
		local col = (i - 1) % ICONS_PER_ROW
		btn:SetPoint("TOPLEFT", iconContainer, "TOPLEFT", col * (ICON_SIZE + ICON_SPACING), -row * ROW_HEIGHT)

		local icon = btn:CreateTexture(nil, "ARTWORK")
		icon:SetAllPoints()
		btn.icon = icon

		local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
		highlight:SetAllPoints()
		highlight:SetColorTexture(1, 1, 1, 0.3)

		local border = btn:CreateTexture(nil, "OVERLAY")
		border:SetSize(ICON_SIZE * 1.8, ICON_SIZE * 1.8)
		border:SetPoint("CENTER")
		border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
		border:SetBlendMode("ADD")
		border:Hide()
		btn.border = border

		btn:SetScript("OnClick", function(self)
			selectedIconIndex = self.iconIndex
			frame.selectedIconPath = self.iconPath
			frame.selectedIcon:SetTexture(self.iconPath)
			for _, b in ipairs(frame.iconButtons) do
				if b.iconIndex == selectedIconIndex then
					b.border:Show()
				else
					b.border:Hide()
				end
			end
			-- Apply immediately so the selection is stored even if user doesn't click Okay
			if currentCallback and frame.selectedIconPath then
				currentCallback(frame.selectedIconPath)
			end
		end)

		btn:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			local path = self.iconPath
			local name
			if type(path) == "number" then
				name = tostring(path)
			elseif type(path) == "string" then
				name = path:match("Interface\\Icons\\(.+)") or path
			else
				name = "Unknown"
			end
			GameTooltip:SetText(name)
			GameTooltip:Show()
		end)

		btn:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)

		frame.iconButtons[i] = btn
	end

	-- Scroll handler
	scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
		FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, function()
			UpdateVisibleButtons()
		end)
	end)

	-- Okay button
	local okayButton = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
	okayButton:SetSize(80, 22)
	okayButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOM", -5, 12)
	okayButton:SetText("Okay")
	okayButton:SetScript("OnClick", function()
		if currentCallback and frame.selectedIconPath then
			currentCallback(frame.selectedIconPath)
		end
		frame:Hide()
		ShamanPower:RefreshConfig()
	end)

	-- Cancel button
	local cancelButton = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
	cancelButton:SetSize(80, 22)
	cancelButton:SetPoint("BOTTOMLEFT", frame, "BOTTOM", 5, 12)
	cancelButton:SetText("Cancel")
	cancelButton:SetScript("OnClick", function()
		frame:Hide()
	end)

	iconPickerFrame = frame
end

function ShamanPower:OpenIconPicker(loadoutIndex, callback)
	if self.OpenConfigIconPicker then
		if iconPickerFrame then iconPickerFrame:Hide() end
		return self:OpenConfigIconPicker(loadoutIndex, callback)
	end
	BuildIconList()
	CreateIconPickerFrame()

	currentCallback = callback
	selectedIconIndex = nil

	-- Set current icon if loadout has one
	local currentIcon
	if loadoutIndex then
		local set = ShamanPower_TotemLoadouts[loadoutIndex]
		currentIcon = set and set.icon
	else
		currentIcon = ShamanPower._newLoadoutIcon
	end
	if currentIcon then
		iconPickerFrame.selectedIconPath = currentIcon
		iconPickerFrame.selectedIcon:SetTexture(currentIcon)
		-- Find the index of the current icon
		for i, icon in ipairs(filteredIcons) do
			if icon == currentIcon then
				selectedIconIndex = i
				break
			end
		end
	else
		iconPickerFrame.selectedIconPath = nil
		iconPickerFrame.selectedIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
	end

	InitializeScrollFrame()
	-- Anchor to right side of config frame as a pop-out panel
	iconPickerFrame:ClearAllPoints()
	local configFrame = _G["ShamanPowerConfigUIFrame"]
	if configFrame and configFrame:IsShown() then
		iconPickerFrame:SetPoint("TOPLEFT", configFrame, "TOPRIGHT", -2, 0)
	else
		iconPickerFrame:SetPoint("CENTER")
	end
	iconPickerFrame:Show()
	iconPickerFrame:Raise()
end

local function HasLoadoutSetControls()
	return WOW_PROJECT_ID == WOW_PROJECT_MAINLINE and ShamanPower.HasTotemBar and ShamanPower:HasTotemBar()
end

-- the Set Page picker and Send to Set Now only show once Call of the Ancestors or
-- Call of the Spirits is known; before that the Loadouts page's note says when they come
local function KnowsSetPage()
	if not (HasLoadoutSetControls() and ShamanPower.KnownTotemSetPages) then return false end
	local known = ShamanPower:KnownTotemSetPages()
	return (known[2] or known[3]) and true or false
end

local function LoadoutSetPageValues()
	local values = { [0] = "None" }
	if HasLoadoutSetControls() and ShamanPower.KnownTotemSetPages then
		local known = ShamanPower:KnownTotemSetPages()
		if known[2] then values[2] = "Call of the Ancestors" end
		if known[3] then values[3] = "Call of the Spirits" end
	end
	return values
end

local function RefreshLoadoutArgs()
	-- Guard: ShamanPower_TotemLoadouts may not exist yet at file load time (SavedVariable)
	if not ShamanPower_TotemLoadouts then return end
	-- Wipe and rebuild - preserves the table reference
	wipe(loadoutArgs)

	loadoutArgs.loadouts_desc = {
		order = 0,
		type = "description",
		name = "Save and switch between personal totem loadouts (up to 8). Each loadout remembers your 4 assigned totems.\n\nUse |cffffd200/spl save <name>|r to save, |cffffd200/spl <name>|r to switch, or manage below.\n",
	}
	loadoutArgs.loadouts_sets_note = {
		order = 0.5,
		type = "description",
		width = "full",
		-- The Set Page picker below only lists set pages the character knows; say why it is empty.
		name = function()
			local known = ShamanPower.KnownTotemSetPages and ShamanPower:KnownTotemSetPages() or {}
			if known[2] or known[3] then
				return "Blizzard's totem sets: pick a loadout's |cffffd200Set Page|r below to put it on Call of the Ancestors or Call of the Spirits; its bar button then casts the whole set. Call of the Elements always follows your assignments.\n"
			end
			return "|cffffa040Blizzard's totem sets: each loadout can be put on Call of the Ancestors (learned at level 30) or Call of the Spirits (level 40) with a Set Page picker, which appears on each loadout below once your character knows one of them. Call of the Elements always follows your assignments.|r\n"
		end,
		hidden = function() return not HasLoadoutSetControls() end,
	}
	loadoutArgs.show_bar = {
		order = 1,
		type = "toggle",
		name = "Show Loadout Bar",
		desc = "Show the on-screen loadout flyout bar for quick switching between totem loadouts",
		width = "full",
		get = function(info)
			return ShamanPower.opt.showLoadoutBar
		end,
		set = function(info, val)
			ShamanPower.opt.showLoadoutBar = val
			ShamanPower:UpdateLoadoutBar()
		end
	}
	loadoutArgs.move_bar = {
		order = 1.5, type = "execute", width = "full",
		name = "Move the Loadout Bar",
		desc = "Hides this window and draws a box around the loadout bar on your screen. Drag it where you want it, then press Done to come back here.",
		disabled = function()
			return ShamanPower.opt.enabled == false or not ShamanPower.opt.showLoadoutBar
				or not ShamanPower.UnlockModuleFrames or InCombatLockdown()
		end,
		func = function() ShamanPower:UnlockModuleFrames("loadoutbar") end,
	}
	loadoutArgs.move_hint = {
		order = 1.6, type = "description", width = "full",
		name = "The bar can also be moved by holding ALT and dragging its anchor "
			.. "while ALT+drag is unlocked (Loadout Bar tab).",
	}
	loadoutArgs.new_header = {
		order = 2,
		type = "header",
		name = "Create New Loadout",
	}
	loadoutArgs.new_name = {
		order = 3,
		type = "input",
		name = "Loadout Name",
		desc = "Enter a name for the new loadout (e.g. 'Enhance', 'Resto')",
		width = 1.2,
		get = function(info)
			return ShamanPower._newLoadoutName or ""
		end,
		set = function(info, val)
			ShamanPower._newLoadoutName = val
		end,
	}
	loadoutArgs.new_icon = {
		order = 3.5,
		type = "execute",
		name = function()
			local icon = ShamanPower._newLoadoutIcon or "Interface\\Icons\\INV_Misc_QuestionMark"
			return "|T" .. icon .. ":16|t Icon"
		end,
		desc = "Click to choose an icon for the new loadout",
		width = 0.5,
		func = function()
			ShamanPower:OpenIconPicker(nil, function(selectedIcon)
				ShamanPower._newLoadoutIcon = selectedIcon
				ShamanPower:RefreshConfig()
			end)
		end,
	}
	-- Pre-fill new loadout totems from current assignments
	if not ShamanPower._newLoadoutTotems then
		ShamanPower._newLoadoutTotems = {}
		local assignments = ShamanPower_Assignments and ShamanPower_Assignments[ShamanPower.player]
		for element = 1, 4 do
			ShamanPower._newLoadoutTotems[element] = (assignments and assignments[element]) or 0
		end
	end
	for element = 1, 4 do
		local elem = element
		loadoutArgs["new_totem_" .. elem] = {
			order = 4 + elem * 0.1,
			type = "select",
			name = loadoutElementNames[elem],
			width = 0.75,
			values = GetTotemValues(elem),
			sorting = GetTotemSorting(elem),
			get = function(info)
				return ShamanPower._newLoadoutTotems and ShamanPower._newLoadoutTotems[elem] or 0
			end,
			set = function(info, val)
				if not ShamanPower._newLoadoutTotems then ShamanPower._newLoadoutTotems = {} end
				ShamanPower._newLoadoutTotems[elem] = val
			end,
		}
	end
	loadoutArgs.create_loadout = {
		order = 4.9,
		type = "execute",
		name = "Create Loadout",
		desc = "Create a new loadout with the name, icon, and totems chosen above",
		width = 1.0,
		disabled = function()
			return not ShamanPower_TotemLoadouts or #ShamanPower_TotemLoadouts >= 8
		end,
		func = function()
			local name = ShamanPower._newLoadoutName
			if name and name:trim() == "" then name = nil end
			local icon = ShamanPower._newLoadoutIcon
			local totems = ShamanPower._newLoadoutTotems or {}
			ShamanPower:CreateLoadout(name, icon, totems)
			-- Clear temp fields and re-fill from current assignments
			ShamanPower._newLoadoutName = nil
			ShamanPower._newLoadoutIcon = nil
			ShamanPower._newLoadoutTotems = nil
			RefreshLoadoutArgs()
			ShamanPower:RefreshConfig()
		end,
	}
	loadoutArgs.loadouts_header = {
		order = 5,
		type = "header",
		name = "Saved Loadouts",
		hidden = function() return not ShamanPower_TotemLoadouts or #ShamanPower_TotemLoadouts == 0 end,
	}

	-- Dynamically add per-loadout management controls
	if ShamanPower_TotemLoadouts then
		for i = 1, #ShamanPower_TotemLoadouts do
			local idx = i
			local baseOrder = 10 + (i - 1) * 20 -- More spacing for extra controls

			local loadout = ShamanPower_TotemLoadouts[idx]
			local lname = loadout and (loadout.name or ("Loadout " .. idx)) or ("Loadout " .. idx)

			-- Header with name and active indicator
			loadoutArgs["lo_header_" .. idx] = {
				order = baseOrder,
				type = "description",
				name = function()
					local lo = ShamanPower_TotemLoadouts[idx]
					if not lo then return "" end
					local n = lo.name or ("Loadout " .. idx)
					local active = (ShamanPower.opt.activeLoadout == idx) and "  |cff00ff00[Active]|r" or ""
					return "\n|cffffd200" .. idx .. ". " .. n .. "|r" .. active
				end,
				fontSize = "medium",
			}

			-- Color-coded description
			loadoutArgs["lo_desc_" .. idx] = {
				order = baseOrder + 1,
				type = "description",
				name = function()
					return ShamanPower:GetLoadoutDescription(idx) .. "\n"
				end,
			}

			-- Rename input (same layout as TotemTimers: Rename | Icon | Update | Delete)
			loadoutArgs["lo_rename_" .. idx] = {
				order = baseOrder + 2,
				type = "input",
				name = "Rename",
				width = 0.9,
				get = function(info)
					local lo = ShamanPower_TotemLoadouts[idx]
					return lo and lo.name or ""
				end,
				set = function(info, val)
					if val and val:trim() == "" then val = nil end
					ShamanPower:RenameLoadout(idx, val)
					RefreshLoadoutArgs()
					ShamanPower:RefreshConfig()
				end,
			}

			-- Icon picker button (same as TotemTimers GUI/Sets.lua setIcon)
			loadoutArgs["lo_icon_" .. idx] = {
				order = baseOrder + 2.5,
				type = "execute",
				name = function()
					local lo = ShamanPower_TotemLoadouts[idx]
					if not lo then return "Icon" end
					local icon = lo.icon or ShamanPower:GetLoadoutIcon(idx)
					return "|T" .. icon .. ":16|t Icon"
				end,
				desc = "Click to choose an icon for this loadout",
				width = 0.5,
				func = function()
					if not ShamanPower_TotemLoadouts[idx] then return end
					local loadoutIndex = idx
					ShamanPower:OpenIconPicker(loadoutIndex, function(selectedIcon)
						if not ShamanPower_TotemLoadouts[loadoutIndex] then return end
						ShamanPower_TotemLoadouts[loadoutIndex].icon = selectedIcon
						ShamanPower:UpdateLoadoutBar()
						RefreshLoadoutArgs()
						ShamanPower:RefreshConfig()
					end)
				end,
			}

			loadoutArgs["lo_delete_" .. idx] = {
				order = baseOrder + 3,
				type = "execute",
				name = "Delete",
				width = 0.5,
				func = function()
					if not ShamanPower_TotemLoadouts[idx] then return end
					ShamanPower:ConfirmDeleteLoadout(idx, lname)
				end,
			}

			-- Per-element totem dropdowns (pick totems individually)
			loadoutArgs["lo_totems_header_" .. idx] = {
				order = baseOrder + 4,
				type = "description",
				name = "    |cff888888Edit totems:|r",
			}

			for element = 1, 4 do
				local elem = element
				loadoutArgs["lo_totem_" .. idx .. "_" .. elem] = {
					order = baseOrder + 4 + elem,
					type = "select",
					name = loadoutElementNames[elem],
					width = 0.75,
					values = GetTotemValues(elem),
					sorting = GetTotemSorting(elem),
					get = function(info)
						local lo = ShamanPower_TotemLoadouts[idx]
						return lo and lo[elem] or 0
					end,
					set = function(info, val)
						ShamanPower:SetLoadoutTotem(idx, elem, val)
						ShamanPower:RefreshConfig()
					end,
				}
			end
			loadoutArgs["lo_dropall_header_" .. idx] = {
				order = baseOrder + 8.5,
				type = "description",
				name = "    |cff888888Leave out of Drop All and Call of the Elements (switches with this loadout):|r",
			}
			for element = 1, 4 do
				local elem = element
				loadoutArgs["lo_dropall_" .. idx .. "_" .. elem] = {
					order = baseOrder + 8.5 + elem * 0.1,
					type = "toggle",
					name = "Exclude " .. loadoutElementNames[elem],
					width = 0.75,
					get = function() return ShamanPower:LoadoutExcluded(idx, elem) end,
					set = function(_, val)
						ShamanPower:SetDropAllExclude(elem, val, idx)
						ShamanPower:RefreshConfig()
					end,
				}
			end
			loadoutArgs["lo_set_page_" .. idx] = {
				order = baseOrder + 9, type = "select", name = "Set Page", width = 1.5,
				desc = "Bind this loadout to one known Blizzard totem set. Each page holds one loadout; "
					.. "rebinding a page unbinds its previous loadout. Call of the Elements stays with assignments. "
					.. "None keeps normal loadout selection. Unknown saved bindings are retained until available again.",
				hidden = function() return not KnowsSetPage() end,
				disabled = function() return not ShamanPower.BindLoadoutToTotemSet end,
				values = LoadoutSetPageValues,
				get = function()
					local lo = ShamanPower_TotemLoadouts and ShamanPower_TotemLoadouts[idx]
					if lo and HasLoadoutSetControls() and ShamanPower.BoundLoadoutSummon
						and ShamanPower:BoundLoadoutSummon(idx) then return lo.setPage end
					return 0
				end,
				set = function(_, page)
					if not HasLoadoutSetControls() or not ShamanPower.BindLoadoutToTotemSet then return end
					local ok, reason = ShamanPower:BindLoadoutToTotemSet(idx, page)
					if not ok and reason then ShamanPower:Print(reason) end
					RefreshLoadoutArgs()
					ShamanPower:RefreshConfig()
					LibStub("AceConfigRegistry-3.0"):NotifyChange("ShamanPower")
				end,
			}
			loadoutArgs["lo_send_set_" .. idx] = {
				order = baseOrder + 10, type = "execute", name = "Send to Set Now", width = 1.5,
				desc = "Write all four saved totems to the bound set; None clears a slot. Combat changes wait until combat ends.",
				hidden = function() return not KnowsSetPage() end,
				disabled = function()
					return not (HasLoadoutSetControls() and ShamanPower.SyncBoundLoadout
						and ShamanPower.BoundLoadoutSummon and ShamanPower:BoundLoadoutSummon(idx))
				end,
				func = function()
					if not HasLoadoutSetControls() or not ShamanPower.SyncBoundLoadout
						or not ShamanPower.BoundLoadoutSummon or not ShamanPower:BoundLoadoutSummon(idx) then return end
					local ok, reason = ShamanPower:SyncBoundLoadout(idx)
					if not ok and reason then ShamanPower:Print(reason) end
					ShamanPower:RefreshConfig()
					LibStub("AceConfigRegistry-3.0"):NotifyChange("ShamanPower")
				end,
			}
		end
	end
end

-- Initialize once (ShamanPower_TotemLoadouts won't exist yet at file load, so just build static part)
RefreshLoadoutArgs()

-- Expose so ShamanPower.lua can call it after SavedVariables are loaded
function ShamanPower:RefreshLoadoutArgs()
	RefreshLoadoutArgs()
end

-------------------------------------------------------------------
-- AceConfig
-------------------------------------------------------------------
-- Flyout icon size sliders. Each style has its own saved size and its slider
-- sits with that style's settings: the icon bar's in Appearance, the Compact
-- bar's with the Compact Style options, the cooldown bar's next to its scale.
-- "Why does this setting do nothing?" - append a note to a description while
-- some other setting or state is overriding it. WithNotes("base", cond1, "note1",
-- cond2, "note2", ...) returns a desc function; a cond is a function (or a value).
local function WithNotes(base, ...)
	local rules = { ... }
	return function()
		local text = type(base) == "function" and base() or base
		for i = 1, #rules, 2 do
			local cond = rules[i]
			if type(cond) == "function" then cond = cond() end
			if cond then text = text .. "\n\n|cffffa040" .. rules[i + 1] .. "|r" end
		end
		return text
	end
end
local function NativeTotemBarSelected()
	return HasLoadoutSetControls() and ShamanPower.opt and ShamanPower.opt.useBlizzardTotemBar == true
end
local function CompactOn()
	if NativeTotemBarSelected() then return false end
	return ShamanPower.CompactActive and ShamanPower:CompactActive() or false
end
local function AvailableShieldNotes(describe)
	return function()
		local text = describe()
		if not ShamanPower.ESTrackerUnavailable then return text end
		return (text:gsub(" %(and the Earth Shield one%)", "")
			:gsub("so only the Earth Shield indicator uses this%.", "so no separate indicator is shown."))
	end
end
local function SetsOwnDropAll()
	return (ShamanPower.HasTotemSets and ShamanPower:HasTotemSets() and ShamanPower.opt.dropAllUsesTotemSets ~= false) and true or false
end

-- The Textures and Status Colors sections only style the panel behind the totem
-- buttons. With "Hide Totem Bar Frame" on there is no panel, and the settings
-- looked broken (they did nothing, with no hint why). Say so, and grey them out.
local PANEL_HIDDEN_NOTE = "\n\n|cffffa040The totem bar's panel is hidden right now, so nothing here is visible. Turn off \"Hide Totem Bar Frame\" (Appearance > Visibility) to see it.|r"
local function PanelHidden()
	return ShamanPower.opt and ShamanPower.opt.hideTotemBarFrame and true or false
end
-- Status Colors: the three colours tint the panel and grey out with it. Rows other
-- files add to that section (Mana Tint, ShamanPowerManaTint.lua) colour the buttons,
-- so the section itself is not greyed by a hidden panel (a group's disabled is
-- inherited by every row without its own).
local function StatusColorDisabled()
	return ShamanPower.opt.enabled == false or not isShaman or PanelHidden()
end

local function FlyoutSizeOption(order, width, key, default, name, desc, apply, extraDisabled)
	return {
		order = order,
		type = "range",
		name = name,
		desc = desc,
		width = width,
		min = 12,
		max = 56,
		step = 1,
		disabled = function(info)
			return ShamanPower.opt.enabled == false or not isShaman or (extraDisabled and extraDisabled()) or false
		end,
		get = function(info)
			return ShamanPower.opt[key] or default
		end,
		set = function(info, val)
			if InCombatLockdown() then
				print("|cff0070ddShamanPower:|r the flyout size cannot change in combat")
				return
			end
			ShamanPower.opt[key] = val
			ShamanPower[apply](ShamanPower)
		end
	}
end

ShamanPower.options = {
	name = "  " .. L["ShamanPower Classic"],
	type = "group",
	childGroups = "tab",
	args = {
		settings = {
			order = 1,
			name = _G.SETTINGS,
			desc = L["Change global settings"],
			type = "group",
			cmdHidden = true,
			args = {
				settings_show = {
					order = 1,
					name = L["Main ShamanPower Settings"],
					type = "group",
					inline = true,
					args = {
						globally = {
							order = 1,
							name = L["Enable ShamanPower"],
							desc = L["[Enable/Disable] ShamanPower"],
							type = "toggle",
							width = 1.0,
							get = function(info)
								return ShamanPower.opt.enabled
							end,
							set = function(info, val)
								ShamanPower.opt.enabled = val
								if ShamanPower.opt.enabled then
									ShamanPower:OnEnable()
								else
									ShamanPower:OnDisable()
								end
							end
						},
						showparty = {
							order = 2,
							name = L["Use in Party"],
							desc = "Show the totem bar while you are in a party or raid. This is about the totem bar only; the cooldown bar has its own settings.",
							type = "toggle",
							width = 1.0,
							disabled = function(info)
								return ShamanPower.opt.enabled == false or not isShaman   -- bar visibility: shaman only
							end,
							get = function(info)
								return ShamanPower.opt.ShowInParty
							end,
							set = function(info, val)
								ShamanPower.opt.ShowInParty = val
								ShamanPower:UpdateRoster()
							end
						},
						showminimapicon = {
							order = 3,
							name = L["Show Minimap Icon"],
							desc = L["[Show/Hide] Minimap Icon"],
							type = "toggle",
							width = 1.0,
							get = function(info)
								return ShamanPower.opt.minimap.show
							end,
							set = function(info, val)
								ShamanPower:EnsureProfileTable("minimap")
								ShamanPower.opt.minimap.show = val
								ShamanPowerMinimapIcon_Toggle()
							end
						},
						showsingle = {
							order = 4,
							name = L["Use when Solo"],
							desc = "Show the totem bar while you are solo. This is about the totem bar only; the cooldown bar has its own settings.",
							type = "toggle",
							width = 1.0,
							disabled = function(info)
								return ShamanPower.opt.enabled == false or not isShaman   -- bar visibility: shaman only
							end,
							get = function(info)
								return ShamanPower.opt.ShowWhenSolo
							end,
							set = function(info, val)
								ShamanPower.opt.ShowWhenSolo = val
								ShamanPower:UpdateRoster()
							end
						},
						showtooltips = {
							order = 5,
							name = L["Show Tooltips"],
							desc = L["[Show/Hide] The ShamanPower Tooltips"],
							type = "toggle",
							width = 1.0,
							disabled = function(info)
								return ShamanPower.opt.enabled == false
							end,
							get = function(info)
								return ShamanPower.opt.ShowTooltips
							end,
							set = function(info, val)
								ShamanPower.opt.ShowTooltips = val
								ShamanPower:UpdateRoster()
							end
						},
					}
				},
				-- settings_buffs removed (legacy)
				settings_totemMode = {
					order = 2,
					name = "Totem Bar Mode",
					type = "group",
					inline = true,
					args = {
						dynamicMode = {
							order = 1,
							name = "Dynamic Mode (PVP)",
							desc = "When enabled, the totem bar automatically shows whatever totem is currently placed for each element. No need to right-click to assign totems first - just drop a totem and it becomes the active one on the bar. Great for PVP where you need quick, reactive totem management. Cannot be combined with Compact Style: turning this on turns Compact off. While Totem Twisting is on, the Air button is left alone.",
							type = "toggle",
							width = "full",
							disabled = function(info)
								return ShamanPower.opt.enabled == false
							end,
							get = function(info)
								return ShamanPower.opt.dynamicTotemMode
							end,
							set = function(info, val)
								if val and ShamanPower.opt.compactStyle and InCombatLockdown() then
									print("|cff0070ddShamanPower:|r Cannot change the totem bar style during combat")
									return
								end
								ShamanPower.opt.dynamicTotemMode = val
								if val and ShamanPower.opt.compactStyle then
									ShamanPower.opt.compactStyle = false
									ShamanPower:ApplyCompactStyle()
								end
								ShamanPower:UpdateMiniTotemBar()
								ShamanPower:FollowStyleSpot()   -- each style keeps its own spot
							end
						},
						dynamicModeDesc = {
							order = 2,
							name = "|cff888888Normal Mode: Right-click a totem in the flyout to assign it, then left-click to cast.\nDynamic Mode: Any totem you drop becomes the active button for that element.|r",
							type = "description",
							width = "full",
						},
						activeAsMainSpacer = {
							order = 3,
							type = "description",
							name = " ",
							width = "full",
						},
						activeTotemAsMain = {
							order = 4,
							name = "TotemTimers Style Display",
							desc = WithNotes("When you drop a different totem than assigned, show the ACTIVE totem as the main icon with the ASSIGNED totem as a small indicator in the corner. (Default shows active totem in a separate frame above the button) Cannot be combined with Compact Style: turning this on turns Compact off.",
								function() return ShamanPower.opt.dynamicTotemMode end, "Dynamic Mode is on: whatever you drop becomes the assigned totem, so the dropped and assigned totems are never different and this display never appears."),
							type = "toggle",
							width = "full",
							disabled = function(info)
								return ShamanPower.opt.enabled == false
							end,
							get = function(info)
								return ShamanPower.opt.activeTotemAsMain
							end,
							set = function(info, val)
								if val and ShamanPower.opt.compactStyle and InCombatLockdown() then
									print("|cff0070ddShamanPower:|r Cannot change the totem bar style during combat")
									return
								end
								ShamanPower.opt.activeTotemAsMain = val
								if val and ShamanPower.opt.compactStyle then
									ShamanPower.opt.compactStyle = false
									ShamanPower:ApplyCompactStyle()
								end
								ShamanPower:UpdateActiveTotemOverlays()
								ShamanPower:FollowStyleSpot()   -- each style keeps its own spot
							end
						},
						rightClickCastsAssigned = {
							order = 4.5,
							name = "Right-Click Drops Corner Totem",
							desc = WithNotes("When enabled, right-clicking a totem button will drop the totem shown in the corner indicator instead of casting Totemic Call. Useful for quickly switching between your active and assigned totems.",
								function() return ShamanPower.RightClickDestroysTotems and ShamanPower:RightClickDestroysTotems() end, "\"Right-Click Pulls That Totem Back\" is on and takes the right-click first, so this does nothing right now.",
								function() return ShamanPower.opt.showTotemFlyouts and ShamanPower.FlyoutOpensOnRightClick and ShamanPower:FlyoutOpensOnRightClick() end, "\"Flyout Requires Right-Click\" is on and takes the right-click first, so this does nothing right now.",
								function() return ShamanPower.opt.dynamicTotemMode end, "Dynamic Mode is on: the corner totem is always the one that is already down."),
							type = "toggle",
							width = "full",
							hidden = function(info)
								return not ShamanPower.opt.activeTotemAsMain
							end,
							disabled = function(info)
								return ShamanPower.opt.enabled == false
							end,
							get = function(info)
								return ShamanPower.opt.rightClickCastsAssigned
							end,
							set = function(info, val)
								ShamanPower.opt.rightClickCastsAssigned = val
								ShamanPower:UpdateMiniTotemBar()
							end
						},
						rightClickDestroysTotem = {
							order = 4.6,
							name = "Right-Click Pulls That Totem Back",
							desc = "Right-clicking a totem button destroys just that element's totem instead of casting Totemic Call. Shift+right-click still casts Totemic Call. If the flyout is set to open on right-click, the flyout keeps priority.",
							type = "toggle",
							width = "full",
							hidden = function(info)
								return not (ShamanPower.TotemDestroySupported and ShamanPower:TotemDestroySupported())
							end,
							disabled = function(info)
								return ShamanPower.opt.enabled == false
							end,
							get = function(info)
								return ShamanPower.opt.rightClickDestroysTotem == true
							end,
							set = function(info, val)
								ShamanPower.opt.rightClickDestroysTotem = val
								if not InCombatLockdown() then
									ShamanPower:UpdateMiniTotemBar()
									ShamanPower:UpdateTotemFlyoutEnabled()
								end
							end
						},
						compactSpacer = {
							order = 4.6,
							type = "description",
							name = " ",
							width = "full",
						},
						compactStyle = {
							order = 4.7,
							name = "Compact Style (lines instead of icons)",
							desc = "Each totem slot becomes an element-colored line. The totem's duration drains as an outline around the line (or the line itself drains), the pulse countdown refills inside it, and a tiny icon square can sit above or below. Clicks, keybinds and flyouts work exactly as before. Cannot be combined with Dynamic Mode or TotemTimers Style: turning Compact on turns both of those off.",
							type = "toggle",
							width = "full",
							disabled = function(info)
								return ShamanPower.opt.enabled == false
							end,
							get = function(info)
								return ShamanPower.opt.compactStyle
							end,
							set = function(info, val)
								if InCombatLockdown() then
									-- ApplyCompactStyle refuses in combat; do not leave the saved value and the bar disagreeing
									print("|cff0070ddShamanPower:|r Cannot change the totem bar style during combat")
									return
								end
								ShamanPower.opt.compactStyle = val
								ShamanPower:ApplyCompactStyle()
								ShamanPower:FollowStyleSpot()
							end
						},
						compactOptions = {
							order = 4.8,
							type = "group",
							inline = true,
							name = "Compact Style",
							hidden = function(info)
								return not ShamanPower.opt.compactStyle
							end,
							args = {
								compactReset = {
									order = 99,
									type = "execute",
									name = "Reset Compact Style to Defaults",
									desc = "Puts every setting in this section back to its default. Asks first. Positions are not changed.",
									func = function() ShamanPower:ConfirmResetSection("compact") end,
								},
								compactOrientation = {
									order = 1,
									type = "select",
									name = "Lines",
									desc = "Horizontal lines stack top to bottom; vertical lines sit side by side.",
									width = 1.2,
									values = { horizontal = "Horizontal (stacked)", vertical = "Vertical (side by side)" },
									get = function(info) return ShamanPower.opt.compactOrientation or "horizontal" end,
									set = function(info, val) ShamanPower.opt.compactOrientation = val; ShamanPower:ApplyCompactStyle() end,
								},
								compactDurationMode = {
									order = 2,
									type = "select",
									name = "Duration Shown As",
									desc = "Auto uses the outline for horizontal lines and a draining line for vertical ones.",
									width = 1.2,
									values = { auto = "Auto", outline = "Outline draining around the line", fill = "Line draining" },
									get = function(info) return ShamanPower.opt.compactDurationMode or "auto" end,
									set = function(info, val) ShamanPower.opt.compactDurationMode = val; ShamanPower:ApplyCompactStyle() end,
								},
								compactLineTexture = {
									order = 2.5,
									type = "select",
									name = "Line Texture",
									desc = "The texture the lines are drawn with, tinted in each element's colour. Flat is a plain colour fill. The ShamanPower ones ship with the addon; the rest come from your other addons (anything that registers bar textures).",
									width = 1.2,
									values = function() return ShamanPower:CompactLineTextureList() end,
									get = function(info) return ShamanPower.opt.compactLineTexture or ShamanPower.CompactLookDefaults.compactLineTexture end,
									set = function(info, val) ShamanPower.opt.compactLineTexture = val; ShamanPower:ApplyCompactStyle() end,
								},
								compactIdleColor = {
									order = 2.6,
									type = "select",
									name = "Idle Line Colour",
									desc = "The inside of a line while no totem of that element is down. Grey: the line only takes its colour when a totem is out. Element colour: the line always shows its element, dimmed, and brightens when a totem is out.",
									width = 1.2,
									values = { grey = "Grey", element = "Element colour (dimmed)" },
									get = function(info) return ShamanPower.opt.compactIdleColor or "grey" end,
									set = function(info, val) ShamanPower.opt.compactIdleColor = val; ShamanPower:ApplyCompactStyle() end,
								},
								compactIdleOutline = {
									order = 2.7,
									type = "select",
									name = "Idle Outline",
									desc = "The outline of a line while no totem of that element is down. None: the outline only appears with a totem out (and drains with its duration). Element colour: every line always wears an outline in its element's colour (or your custom outline colour), a little dimmer than a live totem's.",
									width = 1.2,
									values = { none = "None", element = "Element colour" },
									get = function(info) return ShamanPower.opt.compactIdleOutline or ShamanPower.CompactLookDefaults.compactIdleOutline end,
									set = function(info, val) ShamanPower.opt.compactIdleOutline = val; ShamanPower:ApplyCompactStyle() end,
								},
								compactLength = {
									order = 3,
									type = "range",
									name = "Line Length",
									min = 40, max = 300, step = 2,
									width = 1.2,
									get = function(info) return ShamanPower.opt.compactLength or 120 end,
									set = function(info, val) ShamanPower.opt.compactLength = val; ShamanPower:ApplyCompactStyle() end,
								},
								compactThickness = {
									order = 4,
									type = "range",
									name = "Line Thickness",
									desc = "The pulse countdown text needs at least 14.",
									min = 4, max = 30, step = 1,
									width = 1.2,
									get = function(info) return ShamanPower:CompactOpts().T end,
									set = function(info, val) ShamanPower.opt.compactThickness = val; ShamanPower:ApplyCompactStyle() end,
								},
								compactOutlineWidth = {
									order = 5,
									type = "range",
									name = "Outline Width",
									min = 1, max = 4, step = 1,
									width = 1.2,
									get = function(info) return ShamanPower.opt.compactOutlineWidth or 2 end,
									set = function(info, val) ShamanPower.opt.compactOutlineWidth = val; ShamanPower:ApplyCompactStyle() end,
								},
								compactOutlineColorMode = {
									order = 5.5,
									type = "select",
									name = "Outline Color",
									width = 1.2,
									values = { element = "Element color", custom = "Custom" },
									get = function(info) return ShamanPower.opt.compactOutlineColorMode or "element" end,
									set = function(info, val) ShamanPower.opt.compactOutlineColorMode = val; ShamanPower:ApplyCompactStyle() end,
								},
								compactOutlineColor = {
									order = 5.6,
									type = "color",
									name = "Custom Outline Color",
									width = 1.2,
									hidden = function(info) return (ShamanPower.opt.compactOutlineColorMode or "element") ~= "custom" end,
									get = function(info)
										local c = ShamanPower.opt.compactOutlineColor or {}
										return c.r or 1, c.g or 1, c.b or 1
									end,
									set = function(info, r, g, b)
										ShamanPower:EnsureProfileTable("compactOutlineColor")
										local c = ShamanPower.opt.compactOutlineColor
										c.r, c.g, c.b = r, g, b
										ShamanPower:ApplyCompactStyle()
									end,
								},
								compactIconSquares = {
									order = 6,
									type = "select",
									name = "Icon Squares",
									desc = "A tiny icon of the totem that is down (ghosted: the assigned totem when nothing is down). Left/right of a horizontal line, above/below a vertical one.",
									width = 1.2,
									values = function(info)
										if ShamanPower:CompactOpts().vertical then
											return { off = "Off", before = "Above the line", after = "Below the line" }
										end
										return { off = "Off", before = "Left of the line", after = "Right of the line" }
									end,
									sorting = { "off", "before", "after" },
									get = function(info)
										local v = ShamanPower.opt.compactIconSquares or ShamanPower.CompactLookDefaults.compactIconSquares
										if v == "above" then v = "before" elseif v == "below" then v = "after" end
										return v
									end,
									set = function(info, val) ShamanPower.opt.compactIconSquares = val; ShamanPower:ApplyCompactStyle() end,
								},
								compactIconSize = {
									order = 7,
									type = "range",
									name = "Icon Square Size",
									min = 8, max = 24, step = 1,
									width = 1.2,
									hidden = function(info) return (ShamanPower.opt.compactIconSquares or ShamanPower.CompactLookDefaults.compactIconSquares) == "off" end,
									get = function(info) return ShamanPower.opt.compactIconSize or ShamanPower.CompactLookDefaults.compactIconSize end,
									set = function(info, val) ShamanPower.opt.compactIconSize = val; ShamanPower:ApplyCompactStyle() end,
								},
								compactFlyoutSize = FlyoutSizeOption(7.5, 1.2, "compactFlyoutButtonSize", 15,
									"Flyout Icon Size",
									"How big the icons in the totem flyouts are while Compact style is on. The default is 15, the same as the icon squares, so a flyout sits neatly beside the lines instead of spilling over its neighbours (the icon bar uses 28, and keeps its own size in Appearance). The totem bar's scale still applies on top.",
									"ApplyTotemFlyoutButtonSize", function() return not ShamanPower.opt.showTotemFlyouts end),
								compactPulseBar = {
									order = 8,
									type = "toggle",
									name = "Pulse Refill In The Line",
									width = 1.2,
									get = function(info) return ShamanPower.opt.compactPulseBar ~= false end,
									set = function(info, val) ShamanPower.opt.compactPulseBar = val; ShamanPower:ApplyCompactStyle() end,
								},
								compactPulseText = {
									order = 9,
									type = "toggle",
									name = "Pulse Countdown Text",
									desc = "Shown when the line is at least 14 px thick.",
									width = 1.2,
									get = function(info) return ShamanPower.opt.compactPulseText ~= false end,
									set = function(info, val) ShamanPower.opt.compactPulseText = val; ShamanPower:ApplyCompactStyle() end,
								},
								compactShieldLine = {
									order = 9.5,
									type = "toggle",
									name = "Your Shield Line (Lightning / Water)",
									desc = "A 3-segment line at the start of the bar showing your Lightning or Water Shield charges. Click it to recast.",
									width = "full",
									get = function(info) return ShamanPower.opt.compactShieldLine and true or false end,
									set = function(info, val) ShamanPower.opt.compactShieldLine = val; ShamanPower:ApplyCompactStyle() end,
								},
								compactESLine = {
									hidden = function(info) return not ShamanPower:HasEarthShield() end,
									order = 9.6,
									type = "toggle",
									name = "Earth Shield Line",
									desc = "A segmented line at the end of the bar showing your Earth Shield charges (one segment per charge). Click it to recast. This is the Earth Shield button in Compact style, so it is the same setting as Totem Bar > Items > Show Earth Shield.",
									width = "full",
									get = function(info) return ShamanPower.opt.totemBarShowEarthShield ~= false end,
									set = function(info, val)
										ShamanPower.opt.totemBarShowEarthShield = val
										ShamanPower:UpdateEarthShieldButton()
										ShamanPower:ApplyCompactStyle()
									end,
								},
								compactNote = {
									order = 10,
									type = "description",
									width = "full",
									name = "|cff888888Compact style draws duration and pulse itself, so the Duration Bars page and the totem cooldown sweep do not apply while it is on. Button Spacing sets the gap between lines. Party dots and the range counter sit at the far end of each line.|r",
								},
							}
						},
						twistSpacer = {
							order = 5,
							type = "description",
							name = " ",
							width = "full",
						},
						enableTwisting = {
							order = 6,
							name = "Enable Totem Twisting",
							desc = function(info) return "Enable Air totem twisting (alternates between Windfury and " .. ShamanPower:GetTwistTotemName() .. "). This is the same option as the checkbox in /sp totems." end,
							type = "toggle",
							width = "full",
							disabled = function(info)
								return ShamanPower.opt.enabled == false
							end,
							get = function(info)
								return ShamanPower.opt.enableTotemTwisting
							end,
							set = function(info, val)
								ShamanPower.opt.enableTotemTwisting = val
								-- Sync to assignments table
								ShamanPower_TwistAssignments = ShamanPower_TwistAssignments or {}
								ShamanPower_TwistAssignments[ShamanPower.player] = val
								-- Send to other clients
								ShamanPower:SendMessage("TWIST " .. ShamanPower.player .. " " .. (val and "1" or "0"))
								-- Update UI
								ShamanPower:UpdateMiniTotemBar()
								ShamanPower:UpdateSPMacros()
								if val then
									ShamanPower:SetupTwistTimer()
								else
									ShamanPower:HideTwistTimer()
								end
							end
						},
						twistTotemSelect = {
							order = 6.5,
							name = "Twist Totem",
							desc = "Select which Air totem to alternate with Windfury when twisting",
							type = "select",
							width = 1.0,
							hidden = function(info)
								return not ShamanPower.opt.enableTotemTwisting
							end,
							disabled = function(info)
								return ShamanPower.opt.enabled == false
							end,
							values = function()
								local vals = {}
								-- 2=Grace of Air, 3=Wrath of Air, 4=Tranquil Air, 6=Nature Resistance
								for _, i in ipairs({2, 3, 4, 6}) do
									local id = ShamanPower.AirTotems[i]   -- nil where this client lacks the totem (pruned tables)
									local name = id and GetSpellInfo(id)
									if WOW_PROJECT_ID == WOW_PROJECT_MAINLINE then
										if not (SPCompat and SPCompat.SpellExists) or SPCompat.SpellExists(id) then
											vals[i] = name or ShamanPower.TotemNames[4][i]
										end
									elseif name then
										vals[i] = name
									end
								end
								return vals
							end,
							get = function(info)
								return ShamanPower.opt.twistTotem or 2
							end,
							set = function(info, val)
								ShamanPower.opt.twistTotem = val
								ShamanPower:UpdateMiniTotemBar()
								ShamanPower:UpdateSPMacros()
							end
						},
						twistTimerNoDecimals = {
							order = 7,
							name = "Twist Timer: Hide Decimals",
							desc = "Show whole seconds only on the twist countdown timer instead of decimal values (e.g., '8' instead of '8.3')",
							type = "toggle",
							width = "full",
							hidden = function(info)
								return not ShamanPower.opt.enableTotemTwisting
							end,
							disabled = function(info)
								return ShamanPower.opt.enabled == false
							end,
							get = function(info)
								return ShamanPower.opt.twistTimerNoDecimals
							end,
							set = function(info, val)
								ShamanPower.opt.twistTimerNoDecimals = val
							end
						},
						twistSoundEnabled = {
							order = 7.5,
							name = "Play Twist Sound",
							desc = "Play a sound when the twist timer reaches the threshold",
							type = "toggle",
							width = "full",
							hidden = function(info)
								return not ShamanPower.opt.enableTotemTwisting
							end,
							disabled = function(info)
								return ShamanPower.opt.enabled == false
							end,
							get = function(info)
								return ShamanPower.opt.twistSoundEnabled
							end,
							set = function(info, val)
								ShamanPower.opt.twistSoundEnabled = val
							end
						},
						twistSoundThreshold = {
							order = 7.6,
							name = "Sound Threshold (seconds)",
							desc = "Play the twist sound when this many seconds remain",
							type = "range",
							min = 0,
							max = 10,
							step = 1,
							width = "double",
							hidden = function(info)
								return not ShamanPower.opt.enableTotemTwisting or not ShamanPower.opt.twistSoundEnabled
							end,
							disabled = function(info)
								return ShamanPower.opt.enabled == false
							end,
							get = function(info)
								return ShamanPower.opt.twistSoundThreshold or 3
							end,
							set = function(info, val)
								ShamanPower.opt.twistSoundThreshold = val
							end
						},
						twistSoundPicker = {
							order = 7.7,
							name = "Twist Sound",
							desc = "Choose which sound to play",
							type = "select",
							dialogControl = "LSM30_Sound",
							values = AceGUIWidgetLSMlists.sound,
							width = "double",
							hidden = function(info)
								return not ShamanPower.opt.enableTotemTwisting or not ShamanPower.opt.twistSoundEnabled
							end,
							disabled = function(info)
								return ShamanPower.opt.enabled == false
							end,
							get = function(info)
								return ShamanPower.opt.twistSoundName or "Raid Warning"
							end,
							set = function(info, val)
								ShamanPower.opt.twistSoundName = val
							end
						},
						twistSoundPicker_testsound = {
							hidden = function(info)
								return not ShamanPower.opt.enableTotemTwisting or not ShamanPower.opt.twistSoundEnabled
							end,
							order = 7.7 + 0.05,
							type = "execute",
							name = "Test Sound",
							desc = "Play the selected sound at the selected volume.",
							width = 0.7,
							disabled = function(info)
								return ShamanPower.opt.enabled == false
							end,
							func = function()
								ShamanPower:PlaySoundWithVolume(ShamanPower:GetSoundFile(ShamanPower.opt.twistSoundName or "Raid Warning"), ShamanPower.opt.twistSoundVolume or 100, true)
							end,
						},
						twistSoundVolume = {
							order = 7.8,
							name = "Twist Sound Volume",
							type = "range",
							min = 0,
							max = 100,
							step = 1,
							width = "double",
							hidden = function(info)
								return not ShamanPower.opt.enableTotemTwisting or not ShamanPower.opt.twistSoundEnabled
							end,
							disabled = function(info)
								return ShamanPower.opt.enabled == false
							end,
							get = function(info)
								return ShamanPower.opt.twistSoundVolume or 100
							end,
							set = function(info, val)
								ShamanPower.opt.twistSoundVolume = val
							end
						},
					}
				},
				settings_visibility = {
					order = 2.3,
					name = "Totem Bar Visibility",
					type = "group",
					inline = true,
					args = {
						hideOutOfCombat = {
							order = 1,
							name = "Hide Out of Combat",
							desc = "Hide the totem bar when not in combat",
							type = "toggle",
							width = 1.0,
							disabled = function(info)
								return ShamanPower.opt.enabled == false
							end,
							get = function(info)
								return ShamanPower.opt.hideOutOfCombat == true
							end,
							set = function(info, val)
								ShamanPower.opt.hideOutOfCombat = val
								ShamanPower:UpdateTotemBarVisibility()
							end
						},
						hideWhenNoTotems = {
							order = 2,
							name = "Hide When No Totems",
							desc = "Hide the totem bar when no totems are currently placed",
							type = "toggle",
							width = 1.0,
							disabled = function(info)
								return ShamanPower.opt.enabled == false
							end,
							get = function(info)
								return ShamanPower.opt.hideWhenNoTotems == true
							end,
							set = function(info, val)
								ShamanPower.opt.hideWhenNoTotems = val
								ShamanPower:UpdateTotemBarVisibility()
							end
						},
						-- Fade rules: soften the two hide options above (alpha only, so
						-- nothing here is ever blocked in combat).
						fadeInsteadOfHide = {
							order = 3,
							name = "Fade Instead of Hide",
							desc = "When one of the hide options above applies, fade the totem bar to the opacity below instead of hiding it, so you can still see and click it.",
							type = "toggle",
							width = 1.0,
							disabled = function(info)
								return ShamanPower.opt.enabled == false or not (ShamanPower.opt.hideOutOfCombat or ShamanPower.opt.hideWhenNoTotems)
							end,
							get = function(info) return ShamanPower.opt.fadeInsteadOfHide == true end,
							set = function(info, val)
								ShamanPower.opt.fadeInsteadOfHide = val or nil
								ShamanPower:UpdateTotemBarVisibility(true)
							end
						},
						fadeOpacity = {
							order = 4,
							name = "Faded Opacity",
							desc = "How visible the totem bar stays while faded.",
							type = "range",
							min = 0.05, max = 0.9, step = 0.05, isPercent = true,
							width = 1.0,
							disabled = function(info)
								return ShamanPower.opt.enabled == false or ShamanPower.opt.fadeInsteadOfHide ~= true
									or not (ShamanPower.opt.hideOutOfCombat or ShamanPower.opt.hideWhenNoTotems)
							end,
							get = function(info) return ShamanPower.opt.fadeOpacity or 0.25 end,
							set = function(info, val)
								ShamanPower.opt.fadeOpacity = val
								ShamanPower:UpdateTotemBarVisibility(true)
							end
						},
						fadeSmooth = {
							order = 4.5,
							name = "Smooth Fade",
							desc = "Glide between faded and full over a fifth of a second instead of switching at once. Out of combat only: the bar is always at full the moment a fight starts.",
							type = "toggle",
							width = 1.0,
							disabled = function(info)
								return ShamanPower.opt.enabled == false or ShamanPower.opt.fadeInsteadOfHide ~= true
									or not (ShamanPower.opt.hideOutOfCombat or ShamanPower.opt.hideWhenNoTotems)
							end,
							get = function(info) return ShamanPower.opt.fadeSmooth ~= false end,
							set = function(info, val)
								if val then ShamanPower.opt.fadeSmooth = nil else ShamanPower.opt.fadeSmooth = false end
							end
						},
						showWithTarget = {
							order = 5,
							name = "Show When I Have a Target",
							desc = "Out of combat, bring the totem bar back while you target something you can attack, even when a hide option above applies.",
							type = "toggle",
							width = "full",
							disabled = function(info)
								return ShamanPower.opt.enabled == false or not (ShamanPower.opt.hideOutOfCombat or ShamanPower.opt.hideWhenNoTotems)
							end,
							get = function(info) return ShamanPower.opt.showWithTarget == true end,
							set = function(info, val)
								ShamanPower.opt.showWithTarget = val or nil
								ShamanPower:UpdateTotemBarVisibility(true)
							end
						},
					}
				},
				settings_popout = {
					order = 2.5,
					name = "Pop-Out Trackers",
					type = "group",
					inline = true,
					args = {
						enablePopOut = {
							order = 1,
							name = "Enable Middle-Click Pop-Out",
							desc = "Allow middle-clicking buttons to pop them out as standalone, movable trackers. Disable this if you accidentally trigger pop-outs.",
							type = "toggle",
							width = "full",
							disabled = function(info)
								return ShamanPower.opt.enabled == false
							end,
							get = function(info)
								return ShamanPower.opt.enableMiddleClickPopOut ~= false
							end,
							set = function(info, val)
								ShamanPower.opt.enableMiddleClickPopOut = val
							end
						},
						lockPopOuts = {
							order = 1.5,
							name = "Lock All Pop-Out Trackers",
							desc = "Pop-out trackers can no longer be dragged, including ALT-drag on the icon. Turn this off to rearrange them.",
							type = "toggle",
							width = "full",
							disabled = function(info)
								return ShamanPower.opt.enabled == false
							end,
							get = function(info)
								return ShamanPower.opt.poppedOutLocked and true or false
							end,
							set = function(info, val)
								ShamanPower:SetPopOutsLocked(val)
							end
						},
						popOutDesc = {
							order = 2,
							name = function()
								local shield = ShamanPower.ESTrackerUnavailable and "" or ", Earth Shield"
								return "|cff888888When enabled: Middle-click any totem button, cooldown bar item"
									.. shield .. ", or Drop All to pop it out.\nSHIFT+Middle-click on popped-out frame"
									.. " for settings. ALT+drag to move.|r"
							end,
							type = "description",
							width = "full",
						}
					}
				},
				settings_frames = {
					order = 3,
					name = "Reset",
					type = "group",
					inline = true,
					args = {
						runSetup = {
							order = 0.5,
							type = "execute",
							name = "Run First-Time Setup",
							desc = "Open the guided setup again.",
							func = function() if ShamanPower.Wizard then ShamanPower.Wizard:Open() end end,
						},
						reset_center = {
							order = 1,
							name = "Reset Frames to Center",
							desc = "Put the totem bar in the middle of the screen and the cooldown bar straight under it: a rescue for bars lost off screen (same as /spcenter).",
							type = "execute",
							disabled = function(info)
								return ShamanPower.opt.enabled == false
							end,
							func = function()
								SlashCmdList["SPCENTER"]("")
							end
						},
						reset_defaults = {
							order = 2,
							name = "Reset to Defaults",
							desc = "Reset all visual settings (scale, skin, border, layout) back to defaults",
							type = "execute",
							disabled = function(info)
								return ShamanPower.opt.enabled == false
							end,
							func = function()
								ShamanPower:Reset()
								ShamanPower:UpdateRoster()
							end
						}
					}
				}
			}
		},
		buttons = {
			order = 2,
			name = L["Buttons"],
			desc = L["Change the button settings"],
			type = "group",
			childGroups = "tree",
			cmdHidden = true,
			disabled = function(info)
				return ShamanPower.opt.enabled == false
			end,
			args = {
				auto_button = {
					order = 3,
					name = "Mini Totem Bar",
					type = "group",
					disabled = function(info)
						return ShamanPower.opt.enabled == false or not isShaman
					end,
					args = {
						unlock_totem_bar = {
							order = 0.5,
							name = "Unlock Bar (move)",
							desc = "Show a movable overlay so you can drag the totem bar anywhere. Turn it off when done.",
							type = "toggle",
							width = "full",
							get = function(info)
								return ShamanPower.opt.display and ShamanPower.opt.display.moverUnlocked or false
							end,
							set = function(info, val)
								ShamanPower:SetTotemBarUnlocked(val)
							end
						},
						auto_desc = {
							order = 0,
							type = "description",
							name = "Configure the Mini Totem Bar - a compact bar of clickable totem buttons.",
						},
						auto_enable = {
							order = 1,
							type = "toggle",
							name = "Enable Mini Totem Bar",
							desc = "Turn the totem bar off entirely - for shamans who keybind their totems and only want the cooldown bar. The cooldown bar keeps working on its own.",
							width = "full",
							get = function(info)
								return ShamanPower.opt.miniBar.autobutton
							end,
							set = function(info, val)
								ShamanPower:EnsureProfileTable("miniBar")
								ShamanPower.opt.miniBar.autobutton = val
								-- a cooldown bar attached to the totem bar would vanish with it
								if not val and ShamanPower.opt.cooldownBarLocked then
									ShamanPower.opt.cooldownBarLocked = nil
									ShamanPower:UpdateCooldownBarPosition(true)
								end
								ShamanPower:UpdateLayout()
								ShamanPower:UpdateRoster()
							end
						},
						show_dropall = {
							order = 2,
							type = "toggle",
							name = "Show Drop All Button",
							desc = "[Enable/Disable] The Drop All Totems button on the Mini Totem Bar",
							width = "full",
							get = function(info)
								return ShamanPower.opt.showDropAllButton
							end,
							set = function(info, val)
								ShamanPower.opt.showDropAllButton = val
								if not InCombatLockdown() then
									ShamanPower:UpdateMiniTotemBar()
								end
							end
						},
						-- Totem sets (WoW: Forever only; hidden elsewhere)
						dropall_totem_sets = {
							order = 2.1,
							type = "toggle",
							name = "Drop All Casts Call of the Elements",
							desc = WithNotes("On clients with totem sets, the Drop All button casts Call of the Elements (Shift: Call of the Ancestors, Ctrl: Call of the Spirits, right-click: Totemic Recall) instead of dropping one totem per click.",
								function() return ShamanPower.opt.showDropAllButton == false end, "\"Show Drop All Button\" is off, so there is no button for this to change. It still decides what the SP_DropAll macro and Blizzard's totem bar do."),
							width = "full",
							hidden = function() return not (ShamanPower.HasTotemSets and ShamanPower:HasTotemSets()) end,
							get = function(info) return ShamanPower.opt.dropAllUsesTotemSets ~= false end,
							set = function(info, val)
								ShamanPower.opt.dropAllUsesTotemSets = val
								if not InCombatLockdown() then ShamanPower:UpdateDropAllButton() end
							end
						},
						dropall_totem_sets_sync = {
							order = 2.2,
							type = "toggle",
							name = "Call of the Elements Follows My Assignments",
							desc = "Whenever your totem assignments change, the four totems in Call of the Elements are updated to match (out of combat). Use /spl set 2 <loadout> and /spl set 3 <loadout> to fill Call of the Ancestors and Call of the Spirits from saved loadouts.",
							width = "full",
							hidden = function() return not (ShamanPower.HasTotemSets and ShamanPower:HasTotemSets()) end,
							get = function(info) return ShamanPower.opt.totemSetsSyncAssignments ~= false end,
							set = function(info, val)
								ShamanPower.opt.totemSetsSyncAssignments = val
								if val and not InCombatLockdown() and ShamanPower.SyncTotemSetFromAssignments then ShamanPower:SyncTotemSetFromAssignments() end
							end
						},
						dropall_totem_sets_adopt = {
							order = 2.25,
							type = "toggle",
							name = "My Assignments Follow Blizzard's Totem Bar",
							desc = "Pick a totem on Blizzard's own totem bar and the matching ShamanPower button takes it (clearing a slot there un-assigns it here). Elements kept out of Drop All are left alone. Out of combat; a change made during a fight is picked up when it ends.",
							width = "full",
							hidden = function() return not (ShamanPower.HasTotemBar and ShamanPower:HasTotemBar()) end,
							get = function(info)
								return ShamanPower.opt.totemSetsAdoptFromBar ~= false
							end,
							set = function(info, val)
								ShamanPower.opt.totemSetsAdoptFromBar = val
								if val and ShamanPower.AdoptTotemBarAssignments then ShamanPower:AdoptTotemBarAssignments() end
							end
						},
						show_cooldown_bar = {
							order = 2.05,
							type = "toggle",
							name = "Show Cooldown Bar",
							desc = "[Enable/Disable] Show the cooldown tracker bar (Shields, Ankh, NS, etc.)",
							width = "full",
							get = function(info)
								return ShamanPower.opt.showCooldownBar
							end,
							set = function(info, val)
								ShamanPower.opt.showCooldownBar = val
								ShamanPower:UpdateCooldownBar()
							end
						},
						show_totem_flyouts = {
							order = 2.25,
							type = "toggle",
							name = "Show Totem Flyouts",
							desc = "[Enable/Disable] Show flyout menus on mouseover for quick totem selection (TotemTimers style)",
							width = "full",
							get = function(info)
								return ShamanPower.opt.showTotemFlyouts
							end,
							set = function(info, val)
								ShamanPower.opt.showTotemFlyouts = val
								ShamanPower:UpdateTotemFlyoutEnabled()
							end
						},
						show_es_flyout = {
							order = 2.26,
							type = "toggle",
							name = "Show Earth Shield Flyout",
							desc = "[Enable/Disable] Show flyout menu on Earth Shield button for quick target selection",
							width = "full",
							hidden = function(info)
								return not ShamanPower:HasEarthShield()
							end,
							get = function(info)
								return ShamanPower.opt.enableESFlyout ~= false
							end,
							set = function(info, val)
								ShamanPower.opt.enableESFlyout = val
								if not InCombatLockdown() then
									ShamanPower:UpdateEarthShieldButton()
								end
							end
						},
						es_flyout_filter = {
							order = 2.27,
							type = "group",
							inline = true,
							name = "Earth Shield Flyout Filter",
							hidden = function(info)
								return not ShamanPower:HasEarthShield() or ShamanPower.opt.enableESFlyout == false
							end,
							args = {
								esf_desc = {
									order = 1,
									type = "description",
									width = "full",
									name = "|cff888888Only show these players in the Earth Shield flyout. Roles use the built-in group roles (raid Main Tanks count as Tanks). Selections combine: a player shows if their role OR class is picked. Nothing selected = everyone. Your assigned target is always shown.|r",
								},
								esf_role_TANK = {
									order = 2,
									type = "toggle",
									name = "Tanks",
									width = 0.7,
									get = function(info) return ShamanPower.opt.esFlyoutRoles and ShamanPower.opt.esFlyoutRoles.TANK or false end,
									set = function(info, val)
										ShamanPower:EnsureProfileTable("esFlyoutRoles")
										ShamanPower.opt.esFlyoutRoles.TANK = val or nil
										ShamanPower:CreateEarthShieldFlyout(true)
									end,
								},
								esf_role_HEALER = {
									order = 3,
									type = "toggle",
									name = "Healers",
									width = 0.7,
									get = function(info) return ShamanPower.opt.esFlyoutRoles and ShamanPower.opt.esFlyoutRoles.HEALER or false end,
									set = function(info, val)
										ShamanPower:EnsureProfileTable("esFlyoutRoles")
										ShamanPower.opt.esFlyoutRoles.HEALER = val or nil
										ShamanPower:CreateEarthShieldFlyout(true)
									end,
								},
								esf_role_DAMAGER = {
									order = 4,
									type = "toggle",
									name = "Damage",
									width = 0.7,
									get = function(info) return ShamanPower.opt.esFlyoutRoles and ShamanPower.opt.esFlyoutRoles.DAMAGER or false end,
									set = function(info, val)
										ShamanPower:EnsureProfileTable("esFlyoutRoles")
										ShamanPower.opt.esFlyoutRoles.DAMAGER = val or nil
										ShamanPower:CreateEarthShieldFlyout(true)
									end,
								},
								esf_class_spacer = { order = 9, type = "description", name = " ", width = "full" },
								esf_class_WARRIOR = {
									order = 10,
									type = "toggle",
									name = "|cffC79C6EWarriors|r",
									width = 0.7,
									get = function(info) return ShamanPower.opt.esFlyoutClasses and ShamanPower.opt.esFlyoutClasses.WARRIOR or false end,
									set = function(info, val)
										ShamanPower:EnsureProfileTable("esFlyoutClasses")
										ShamanPower.opt.esFlyoutClasses.WARRIOR = val or nil
										ShamanPower:CreateEarthShieldFlyout(true)
									end,
								},
								esf_class_PALADIN = {
									order = 11,
									type = "toggle",
									name = "|cffF58CBAPaladins|r",
									width = 0.7,
									get = function(info) return ShamanPower.opt.esFlyoutClasses and ShamanPower.opt.esFlyoutClasses.PALADIN or false end,
									set = function(info, val)
										ShamanPower:EnsureProfileTable("esFlyoutClasses")
										ShamanPower.opt.esFlyoutClasses.PALADIN = val or nil
										ShamanPower:CreateEarthShieldFlyout(true)
									end,
								},
								esf_class_HUNTER = {
									order = 12,
									type = "toggle",
									name = "|cffABD473Hunters|r",
									width = 0.7,
									get = function(info) return ShamanPower.opt.esFlyoutClasses and ShamanPower.opt.esFlyoutClasses.HUNTER or false end,
									set = function(info, val)
										ShamanPower:EnsureProfileTable("esFlyoutClasses")
										ShamanPower.opt.esFlyoutClasses.HUNTER = val or nil
										ShamanPower:CreateEarthShieldFlyout(true)
									end,
								},
								esf_class_ROGUE = {
									order = 13,
									type = "toggle",
									name = "|cffFFF569Rogues|r",
									width = 0.7,
									get = function(info) return ShamanPower.opt.esFlyoutClasses and ShamanPower.opt.esFlyoutClasses.ROGUE or false end,
									set = function(info, val)
										ShamanPower:EnsureProfileTable("esFlyoutClasses")
										ShamanPower.opt.esFlyoutClasses.ROGUE = val or nil
										ShamanPower:CreateEarthShieldFlyout(true)
									end,
								},
								esf_class_PRIEST = {
									order = 14,
									type = "toggle",
									name = "|cffFFFFFFPriests|r",
									width = 0.7,
									get = function(info) return ShamanPower.opt.esFlyoutClasses and ShamanPower.opt.esFlyoutClasses.PRIEST or false end,
									set = function(info, val)
										ShamanPower:EnsureProfileTable("esFlyoutClasses")
										ShamanPower.opt.esFlyoutClasses.PRIEST = val or nil
										ShamanPower:CreateEarthShieldFlyout(true)
									end,
								},
								esf_class_SHAMAN = {
									order = 15,
									type = "toggle",
									name = "|cff0070DEShamans|r",
									width = 0.7,
									get = function(info) return ShamanPower.opt.esFlyoutClasses and ShamanPower.opt.esFlyoutClasses.SHAMAN or false end,
									set = function(info, val)
										ShamanPower:EnsureProfileTable("esFlyoutClasses")
										ShamanPower.opt.esFlyoutClasses.SHAMAN = val or nil
										ShamanPower:CreateEarthShieldFlyout(true)
									end,
								},
								esf_class_MAGE = {
									order = 16,
									type = "toggle",
									name = "|cff69CCF0Mages|r",
									width = 0.7,
									get = function(info) return ShamanPower.opt.esFlyoutClasses and ShamanPower.opt.esFlyoutClasses.MAGE or false end,
									set = function(info, val)
										ShamanPower:EnsureProfileTable("esFlyoutClasses")
										ShamanPower.opt.esFlyoutClasses.MAGE = val or nil
										ShamanPower:CreateEarthShieldFlyout(true)
									end,
								},
								esf_class_WARLOCK = {
									order = 17,
									type = "toggle",
									name = "|cff9482C9Warlocks|r",
									width = 0.7,
									get = function(info) return ShamanPower.opt.esFlyoutClasses and ShamanPower.opt.esFlyoutClasses.WARLOCK or false end,
									set = function(info, val)
										ShamanPower:EnsureProfileTable("esFlyoutClasses")
										ShamanPower.opt.esFlyoutClasses.WARLOCK = val or nil
										ShamanPower:CreateEarthShieldFlyout(true)
									end,
								},
								esf_class_DRUID = {
									order = 18,
									type = "toggle",
									name = "|cffFF7D0ADruids|r",
									width = 0.7,
									get = function(info) return ShamanPower.opt.esFlyoutClasses and ShamanPower.opt.esFlyoutClasses.DRUID or false end,
									set = function(info, val)
										ShamanPower:EnsureProfileTable("esFlyoutClasses")
										ShamanPower.opt.esFlyoutClasses.DRUID = val or nil
										ShamanPower:CreateEarthShieldFlyout(true)
									end,
								},
							}
						},
						drop_order_header = {
							order = 2.5,
							type = "header",
							name = "Drop Order",
						},
						drop_order_1 = {
							order = 2.6,
							type = "select",
							name = "1st Position",
							desc = WithNotes("First totem to drop",
								SetsOwnDropAll, "\"Drop All Casts Call of the Elements\" is on, and that spell drops all four totems at once, so the order is not used by the button. It still orders the SP_DropAll macro."),
							width = 1.2,
							values = {
								[1] = "Earth",
								[2] = "Fire",
								[3] = "Water",
								[4] = "Air",
							},
							get = function(info)
								return ShamanPower.opt.dropOrder and ShamanPower.opt.dropOrder[1] or 1
							end,
							set = function(info, val)
								if not ShamanPower.opt.dropOrder then ShamanPower.opt.dropOrder = {1, 2, 3, 4} end
								-- Swap if duplicate
								for i = 2, 4 do
									if ShamanPower.opt.dropOrder[i] == val then
										ShamanPower.opt.dropOrder[i] = ShamanPower.opt.dropOrder[1]
										break
									end
								end
								ShamanPower.opt.dropOrder[1] = val
								ShamanPower:UpdateDropAllButton()
							end
						},
						drop_order_2 = {
							order = 2.7,
							type = "select",
							name = "2nd Position",
							desc = WithNotes("Second totem to drop",
								SetsOwnDropAll, "\"Drop All Casts Call of the Elements\" is on, and that spell drops all four totems at once, so the order is not used by the button. It still orders the SP_DropAll macro."),
							width = 1.2,
							values = {
								[1] = "Earth",
								[2] = "Fire",
								[3] = "Water",
								[4] = "Air",
							},
							get = function(info)
								return ShamanPower.opt.dropOrder and ShamanPower.opt.dropOrder[2] or 2
							end,
							set = function(info, val)
								if not ShamanPower.opt.dropOrder then ShamanPower.opt.dropOrder = {1, 2, 3, 4} end
								-- Swap if duplicate
								for i = 1, 4 do
									if i ~= 2 and ShamanPower.opt.dropOrder[i] == val then
										ShamanPower.opt.dropOrder[i] = ShamanPower.opt.dropOrder[2]
										break
									end
								end
								ShamanPower.opt.dropOrder[2] = val
								ShamanPower:UpdateDropAllButton()
							end
						},
						drop_order_3 = {
							order = 2.8,
							type = "select",
							name = "3rd Position",
							desc = WithNotes("Third totem to drop",
								SetsOwnDropAll, "\"Drop All Casts Call of the Elements\" is on, and that spell drops all four totems at once, so the order is not used by the button. It still orders the SP_DropAll macro."),
							width = 1.2,
							values = {
								[1] = "Earth",
								[2] = "Fire",
								[3] = "Water",
								[4] = "Air",
							},
							get = function(info)
								return ShamanPower.opt.dropOrder and ShamanPower.opt.dropOrder[3] or 3
							end,
							set = function(info, val)
								if not ShamanPower.opt.dropOrder then ShamanPower.opt.dropOrder = {1, 2, 3, 4} end
								-- Swap if duplicate
								for i = 1, 4 do
									if i ~= 3 and ShamanPower.opt.dropOrder[i] == val then
										ShamanPower.opt.dropOrder[i] = ShamanPower.opt.dropOrder[3]
										break
									end
								end
								ShamanPower.opt.dropOrder[3] = val
								ShamanPower:UpdateDropAllButton()
							end
						},
						drop_order_4 = {
							order = 2.9,
							type = "select",
							name = "4th Position",
							desc = WithNotes("Fourth totem to drop",
								SetsOwnDropAll, "\"Drop All Casts Call of the Elements\" is on, and that spell drops all four totems at once, so the order is not used by the button. It still orders the SP_DropAll macro."),
							width = 1.2,
							values = {
								[1] = "Earth",
								[2] = "Fire",
								[3] = "Water",
								[4] = "Air",
							},
							get = function(info)
								return ShamanPower.opt.dropOrder and ShamanPower.opt.dropOrder[4] or 4
							end,
							set = function(info, val)
								if not ShamanPower.opt.dropOrder then ShamanPower.opt.dropOrder = {1, 2, 3, 4} end
								-- Swap if duplicate
								for i = 1, 3 do
									if ShamanPower.opt.dropOrder[i] == val then
										ShamanPower.opt.dropOrder[i] = ShamanPower.opt.dropOrder[4]
										break
									end
								end
								ShamanPower.opt.dropOrder[4] = val
								ShamanPower:UpdateDropAllButton()
							end
						},
						exclude_from_drop_all_header = {
							order = 2.901,
							type = "header",
							name = "Exclude from Drop All",
						},
						exclude_earth = {
							order = 2.902,
							type = "toggle",
							name = "Exclude Earth",
							desc = function()
								local d = "Exclude Earth totem from the Drop All button"
								if ShamanPower.HasTotemBar and ShamanPower:HasTotemBar() then
									if ShamanPower.opt.totemSetsSyncAssignments == false then
										d = d .. ".\n\n\"Call of the Elements Follows My Assignments\" is off, so Blizzard's totem bar is left alone: whatever sits in its Earth slot is still dropped by Call of the Elements. Turn that option on for this exclude to reach it."
									else
										d = d .. ".\n\nCall of the Elements drops whatever Blizzard's totem bar holds, so while this is on the Earth slot of that bar is kept empty. Your own Earth button still casts and assigns as usual."
									end
								end
								return d
							end,
							width = "full",
							get = function(info)
								return ShamanPower.opt.excludeEarthFromDropAll
							end,
							set = function(info, val)
								ShamanPower:SetDropAllExclude(1, val)   -- the active loadout keeps it too
							end
						},
						exclude_fire = {
							order = 2.903,
							type = "toggle",
							name = "Exclude Fire",
							desc = function()
								local d = "Exclude Fire totem from the Drop All button"
								if ShamanPower.HasTotemBar and ShamanPower:HasTotemBar() then
									if ShamanPower.opt.totemSetsSyncAssignments == false then
										d = d .. ".\n\n\"Call of the Elements Follows My Assignments\" is off, so Blizzard's totem bar is left alone: whatever sits in its Fire slot is still dropped by Call of the Elements. Turn that option on for this exclude to reach it."
									else
										d = d .. ".\n\nCall of the Elements drops whatever Blizzard's totem bar holds, so while this is on the Fire slot of that bar is kept empty. Your own Fire button still casts and assigns as usual."
									end
								end
								return d
							end,
							width = "full",
							get = function(info)
								return ShamanPower.opt.excludeFireFromDropAll
							end,
							set = function(info, val)
								ShamanPower:SetDropAllExclude(2, val)   -- the active loadout keeps it too
							end
						},
						exclude_water = {
							order = 2.904,
							type = "toggle",
							name = "Exclude Water",
							desc = function()
								local d = "Exclude Water totem from the Drop All button"
								if ShamanPower.HasTotemBar and ShamanPower:HasTotemBar() then
									if ShamanPower.opt.totemSetsSyncAssignments == false then
										d = d .. ".\n\n\"Call of the Elements Follows My Assignments\" is off, so Blizzard's totem bar is left alone: whatever sits in its Water slot is still dropped by Call of the Elements. Turn that option on for this exclude to reach it."
									else
										d = d .. ".\n\nCall of the Elements drops whatever Blizzard's totem bar holds, so while this is on the Water slot of that bar is kept empty. Your own Water button still casts and assigns as usual."
									end
								end
								return d
							end,
							width = "full",
							get = function(info)
								return ShamanPower.opt.excludeWaterFromDropAll
							end,
							set = function(info, val)
								ShamanPower:SetDropAllExclude(3, val)   -- the active loadout keeps it too
							end
						},
						exclude_air = {
							order = 2.905,
							type = "toggle",
							name = "Exclude Air",
							desc = function()
								local d = "Exclude Air totem from the Drop All button"
								if ShamanPower.HasTotemBar and ShamanPower:HasTotemBar() then
									if ShamanPower.opt.totemSetsSyncAssignments == false then
										d = d .. ".\n\n\"Call of the Elements Follows My Assignments\" is off, so Blizzard's totem bar is left alone: whatever sits in its Air slot is still dropped by Call of the Elements. Turn that option on for this exclude to reach it."
									else
										d = d .. ".\n\nCall of the Elements drops whatever Blizzard's totem bar holds, so while this is on the Air slot of that bar is kept empty. Your own Air button still casts and assigns as usual."
									end
								end
								return d
							end,
							width = "full",
							get = function(info)
								return ShamanPower.opt.excludeAirFromDropAll
							end,
							set = function(info, val)
								ShamanPower:SetDropAllExclude(4, val)   -- the active loadout keeps it too
							end
						},
						exclude_earth_empty_note = {
							order = 2.9025,
							type = "description",
							name = "|cffffa040Earth is set to Empty on the totem bar, so Drop All skips it already; this toggle only matters once a totem is assigned there.|r",
							hidden = function()
								local a = ShamanPower_Assignments and ShamanPower.player and ShamanPower_Assignments[ShamanPower.player]
								return not (a and (a[1] or 0) == 0)
							end,
						},
						exclude_fire_empty_note = {
							order = 2.9035,
							type = "description",
							name = "|cffffa040Fire is set to Empty on the totem bar, so Drop All skips it already; this toggle only matters once a totem is assigned there.|r",
							hidden = function()
								local a = ShamanPower_Assignments and ShamanPower.player and ShamanPower_Assignments[ShamanPower.player]
								return not (a and (a[2] or 0) == 0)
							end,
						},
						exclude_water_empty_note = {
							order = 2.9045,
							type = "description",
							name = "|cffffa040Water is set to Empty on the totem bar, so Drop All skips it already; this toggle only matters once a totem is assigned there.|r",
							hidden = function()
								local a = ShamanPower_Assignments and ShamanPower.player and ShamanPower_Assignments[ShamanPower.player]
								return not (a and (a[3] or 0) == 0)
							end,
						},
						exclude_air_empty_note = {
							order = 2.9055,
							type = "description",
							name = "|cffffa040Air is set to Empty on the totem bar, so Drop All skips it already; this toggle only matters once a totem is assigned there.|r",
							hidden = function()
								local a = ShamanPower_Assignments and ShamanPower.player and ShamanPower_Assignments[ShamanPower.player]
								return not (a and (a[4] or 0) == 0)
							end,
						},
					}
				},
				macros_section = {
					order = 3.5,
					name = "Macros",
					type = "group",
					disabled = function(info)
						return ShamanPower.opt.enabled == false or not isShaman
					end,
					args = {
						macros_desc = {
							order = 0,
							type = "description",
							name = "Create macros for your assigned totems. Drag them to your action bar - they auto-update when you change assignments."
						},
						create_macros = {
							order = 1,
							type = "execute",
							name = "Create/Update Macros",
							desc = "Creates or updates the following macros:\nSP_Earth, SP_Fire, SP_Water, SP_Air - Cast assigned totem\nSP_DropAll - Cast all totems in sequence\nSP_Recall - Totemic Call",
							width = 1.3,
							func = function()
								if InCombatLockdown() then
									print("ShamanPower: Cannot update macros in combat")
									return
								end
								ShamanPower:UpdateSPMacros()
								print("ShamanPower: Macros created! Check your macro panel (Esc -> Macros)")
							end
						}
					}
				},
				loadouts_section = {
					order = 3.7,
					name = "Totem Loadouts",
					type = "group",
					disabled = function(info)
						return ShamanPower.opt.enabled == false or not isShaman
					end,
					args = loadoutArgs,
				},
			}
		},
		fluffy = {
			order = 3,
			name = "Look & Feel",
			desc = "UI customization options (requested by FluffyKable)",
			type = "group",
			childGroups = "tree",
			cmdHidden = true,
			disabled = function(info)
				return ShamanPower.opt.enabled == false
			end,
			args = {
				fluffy_header = {
					order = 0,
					type = "description",
					name = "    |cffffd200Fluffy Settings|r\n    UI customization options - dedicated to |cff0070deFluffyKable|r from the Shaman Discord.",
					fontSize = "medium",
				},
				layout_section = {
					order = 1,
					name = "Layout",
					type = "group",
					args = {
						layout_desc = {
							order = 0,
							type = "description",
							name = "Control the orientation of your bars and how flyout menus appear.",
						},
						element_color_palette = {
							order = 0.5,
							type = "select",
							name = "Element Colours",
							desc = "The colour each element is drawn in: Compact lines, alerts, party counters and anything else coloured by element. ShamanPower classic has brown Earth and pale Air. Blizzard matches the game's own totem bar (and our flyout arrows): green Earth, orange Fire, blue Water, purple Air. Custom lets you pick all four.",
							width = 1.4,
							values = { classic = "ShamanPower classic (brown Earth)", blizzard = "Blizzard totem bar (green Earth)", custom = "Custom" },
							sorting = { "classic", "blizzard", "custom" },
							get = function(info) return ShamanPower.opt.elementColorPalette or ShamanPower:DefaultElementPalette() end,
							set = function(info, val)
								if val == "custom" and not ShamanPower.opt.elementColorsCustom then
									-- start from whatever is showing now
									local t = {}
									for e = 1, 4 do local r, g, b = ShamanPower:ElementPaletteColor(e); t[e] = { r = r, g = g, b = b } end
									ShamanPower.opt.elementColorsCustom = t
								end
								ShamanPower.opt.elementColorPalette = val
								ShamanPower:ApplyElementColors()
							end,
						},
						element_color_1 = {
							order = 0.51,
							type = "color",
							name = "Earth",
							width = 0.6,
							hidden = function(info) return (ShamanPower.opt.elementColorPalette or ShamanPower:DefaultElementPalette()) ~= "custom" end,
							get = function(info) return ShamanPower:ElementPaletteColor(1) end,
							set = function(info, r, g, b)
								ShamanPower:EnsureProfileTable("elementColorsCustom")
								ShamanPower.opt.elementColorsCustom[1] = { r = r, g = g, b = b }
								ShamanPower:ApplyElementColors()
							end,
						},
						element_color_2 = {
							order = 0.52,
							type = "color",
							name = "Fire",
							width = 0.6,
							hidden = function(info) return (ShamanPower.opt.elementColorPalette or ShamanPower:DefaultElementPalette()) ~= "custom" end,
							get = function(info) return ShamanPower:ElementPaletteColor(2) end,
							set = function(info, r, g, b)
								ShamanPower:EnsureProfileTable("elementColorsCustom")
								ShamanPower.opt.elementColorsCustom[2] = { r = r, g = g, b = b }
								ShamanPower:ApplyElementColors()
							end,
						},
						element_color_3 = {
							order = 0.53,
							type = "color",
							name = "Water",
							width = 0.6,
							hidden = function(info) return (ShamanPower.opt.elementColorPalette or ShamanPower:DefaultElementPalette()) ~= "custom" end,
							get = function(info) return ShamanPower:ElementPaletteColor(3) end,
							set = function(info, r, g, b)
								ShamanPower:EnsureProfileTable("elementColorsCustom")
								ShamanPower.opt.elementColorsCustom[3] = { r = r, g = g, b = b }
								ShamanPower:ApplyElementColors()
							end,
						},
						element_color_4 = {
							order = 0.54,
							type = "color",
							name = "Air",
							width = 0.6,
							hidden = function(info) return (ShamanPower.opt.elementColorPalette or ShamanPower:DefaultElementPalette()) ~= "custom" end,
							get = function(info) return ShamanPower:ElementPaletteColor(4) end,
							set = function(info, r, g, b)
								ShamanPower:EnsureProfileTable("elementColorsCustom")
								ShamanPower.opt.elementColorsCustom[4] = { r = r, g = g, b = b }
								ShamanPower:ApplyElementColors()
							end,
						},
						element_color_reset = {
							order = 0.59,
							type = "execute",
							name = "Reset Element Colours",
							desc = "Puts every setting in this section back to its default. Asks first. Positions are not changed.",
							width = 1.0,
							hidden = function(info) return ShamanPower.opt.elementColorPalette == nil or ShamanPower.opt.elementColorPalette == ShamanPower:DefaultElementPalette() end,
							func = function() ShamanPower:ConfirmResetSection("colors") end,
						},
						layout = {
							order = 1,
							type = "select",
							width = 1.4,
							name = "Totem Bar Layout",
							desc = WithNotes("Change the layout orientation of the totem bar",
								CompactOn, "Compact style is on: the bar's direction comes from Compact Style > Lines, and totem flyouts open from the end of the lines. This setting is not used for that."),
							disabled = function(info)
								return ShamanPower.opt.enabled == false or not isShaman
							end,
							get = function(info)
								return ShamanPower.opt.layout
							end,
							set = function(info, val)
								-- Don't change layout in combat
								if InCombatLockdown() then print("|cff0070ddShamanPower:|r the bar layout cannot change during combat - try again after the fight."); return end

								-- Initialize cdbarLayout if not set, so changing totem bar doesn't affect CD bar
								if ShamanPower.opt.cdbarLayout == nil then
									ShamanPower.opt.cdbarLayout = ShamanPower.opt.layout
								end

								-- Save current autoButton screen position before layout change
								local oldLayout = ShamanPower.opt.layout
								local autoBtn = ShamanPower.autoButton
								local header = ShamanPower.Header
								local oldCenterX, oldCenterY
								if autoBtn and autoBtn:IsShown() then
									oldCenterX, oldCenterY = autoBtn:GetCenter()
								end

								-- Change the layout
								ShamanPower.opt.layout = val
								ShamanPower:UpdateLayout()
								ShamanPower:UpdateRoster()

								-- Restore position so autoButton stays in same screen location
								-- (one with no saved spot was just put back on its default one)
								if oldCenterX and oldCenterY and autoBtn and header and ShamanPower:TotemBarRecord() then
									local newCenterX, newCenterY = autoBtn:GetCenter()
									if newCenterX and newCenterY then
										-- Calculate the offset needed
										local deltaX = oldCenterX - newCenterX
										local deltaY = oldCenterY - newCenterY

										-- Move the main frame to compensate
										local frame = _G["ShamanPowerFrame"]
										if frame and not InCombatLockdown() then
											local point, relativeTo, relativePoint, xOfs, yOfs = frame:GetPoint()
											if point and xOfs and yOfs then
												frame:ClearAllPoints()
												frame:SetPoint(point, relativeTo, relativePoint, xOfs + deltaX, yOfs + deltaY)
												ShamanPower:SaveFramePosition(frame)
											end
										end
									end
								end

								-- Update cooldown bar position for new layout
								ShamanPower:UpdateCooldownBar()
							end,
							values = {
								["Horizontal"] = "Horizontal",
								["Vertical"] = "Vertical (Right)",
								["VerticalLeft"] = "Vertical (Left)",
							}
						},
						totem_flyout_direction = {
							order = 1.2,
							type = "select",
							name = "Totem Flyout Direction",
							desc = "Direction totem flyouts appear when totem bar is horizontal",
							width = 1.0,
							hidden = function(info)
								-- Compact decides the bar's direction itself, so ask the bar, not opt.layout
								return not ShamanPower.opt.showTotemFlyouts or not ShamanPower:IsTotemBarHorizontal()
							end,
							values = {
								["auto"] = "Auto",
								["above"] = "Above",
								["below"] = "Below",
							},
							get = function(info)
								return ShamanPower.opt.totemFlyoutDirection or "auto"
							end,
							set = function(info, val)
								ShamanPower.opt.totemFlyoutDirection = val
								-- Update all totem flyouts (UpdateFlyoutVisibility handles positioning)
								for element = 1, 4 do
									if ShamanPower.totemFlyouts[element] then
										ShamanPower:UpdateFlyoutVisibility(element)
									end
								end
								-- Update ES flyout if it exists
								if ShamanPower.CreateEarthShieldFlyout then
									ShamanPower:CreateEarthShieldFlyout()
								end
							end,
						},
						activeOverlayDirection = {
							order = 1.3,
							type = "select",
							name = "Dropped Totem Indicator Position",
							desc = AvailableShieldNotes(WithNotes("Where the indicator for a dropped, non-assigned totem"
								.. " (and the Earth Shield one) pops out from its button. Auto puts it above a horizontal bar"
								.. " and on the flyout side of a vertical one.",
								CompactOn, "Compact style is on: it has no pop-out indicator (the line is whatever is down), so this does nothing right now.",
								function() return not CompactOn() and ShamanPower.opt.activeTotemAsMain end, "TotemTimers Style is on: the dropped totem is shown on the button itself with the assigned one in the corner, so only the Earth Shield indicator uses this.",
								function() return not CompactOn() and ShamanPower.opt.dynamicTotemMode end,
								"Dynamic Mode is on: whatever you drop becomes the assigned totem,"
									.. " so there is never a separate dropped-totem indicator to place.")),
							width = 1.4,
							values = { auto = "Auto", above = "Above", below = "Below", left = "Left", right = "Right" },
							sorting = { "auto", "above", "below", "left", "right" },
							disabled = function(info)
								return (ShamanPower.opt.enabled == false) or (CompactOn())
							end,
							get = function(info)
								return ShamanPower.opt.activeOverlayDirection or "auto"
							end,
							set = function(info, val)
								ShamanPower.opt.activeOverlayDirection = val
								ShamanPower:PositionActiveOverlays()
							end
						},
						cdbarLayout = {
							order = 1.5,
							type = "select",
							width = 1.4,
							name = "Cooldown Bar Layout",
							desc = "Change the layout orientation of the cooldown bar independently from the totem bar",
							disabled = function(info)
								return ShamanPower.opt.enabled == false or not isShaman or not ShamanPower.opt.showCooldownBar
							end,
							get = function(info)
								return ShamanPower.opt.cdbarLayout or ShamanPower.opt.layout
							end,
							set = function(info, val)
								-- Don't change layout in combat
								if InCombatLockdown() then print("|cff0070ddShamanPower:|r the bar layout cannot change during combat - try again after the fight."); return end
								ShamanPower.opt.cdbarLayout = val
								ShamanPower:UpdateCooldownBarLayout()
								ShamanPower:UpdateCooldownBar()
								-- Re-layout the shield and weapon imbue flyouts for new direction
								if ShamanPower.LayoutShieldFlyout then
									ShamanPower:LayoutShieldFlyout()
								end
								if ShamanPower.LayoutWeaponImbueFlyout then
									ShamanPower:LayoutWeaponImbueFlyout()
								end
							end,
							values = {
								["Horizontal"] = "Horizontal",
								["Vertical"] = "Vertical (Right)",
								["VerticalLeft"] = "Vertical (Left)",
							}
						},
						cdbar_flyout_direction = {
							disabled = function(info) return ShamanPower.opt.enabled == false or not isShaman or not ShamanPower.opt.showCooldownBar end,
							order = 1.7,
							type = "select",
							name = "Cooldown Flyout Direction",
							desc = "Direction cooldown bar flyouts appear when cooldown bar is horizontal",
							width = 1.0,
							hidden = function(info)
								local cdLayout = ShamanPower.opt.cdbarLayout or ShamanPower.opt.layout
								return cdLayout ~= "Horizontal"
							end,
							values = {
								["auto"] = "Auto",
								["above"] = "Above",
								["below"] = "Below",
							},
							get = function(info)
								return ShamanPower.opt.cdbarFlyoutDirection or "auto"
							end,
							set = function(info, val)
								ShamanPower.opt.cdbarFlyoutDirection = val
								-- Re-layout the shield and weapon imbue flyouts for new direction
								if ShamanPower.LayoutShieldFlyout then
									ShamanPower:LayoutShieldFlyout()
								end
								if ShamanPower.LayoutWeaponImbueFlyout then
									ShamanPower:LayoutWeaponImbueFlyout()
								end
							end,
						},
						swap_flyout_clicks = {
							order = 2,
							type = "toggle",
							name = "Swap Flyout Click Buttons",
							desc = "Swap mouse buttons on totem flyout menus: Left-click assigns totem, Right-click casts (default is Left=cast, Right=assign)",
							-- Mainline clients get the full swap in Appearance instead (same saved setting)
							hidden = function(info)
								return (ShamanPower.ApplyClickSwap and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE) and true or false
							end,
							width = "full",
							disabled = function(info)
								return ShamanPower.opt.enabled == false or not isShaman
							end,
							get = function(info)
								return ShamanPower.opt.swapFlyoutClickButtons
							end,
							set = function(info, val)
								ShamanPower.opt.swapFlyoutClickButtons = val
								-- Just update click attributes on existing buttons
								ShamanPower:UpdateFlyoutClickBehavior()
							end
						},
						flyout_requires_click = {
							order = 3,
							type = "toggle",
							name = "Flyout Requires Right-Click",
							desc = "Flyouts only appear when you right-click the button instead of on mouseover. Applies to both totem bar and cooldown bar (shield/imbue) flyouts. Right-click the flyout totem to assign it. Note: Disables right-click to destroy totems.",
							width = "full",
							-- retired where flyouts open from arrows ("Open Flyouts Only From the Arrow" replaces it)
							hidden = function(info)
								return (SPCompat and SPCompat.SecureSnippetsWork and not SPCompat.SecureSnippetsWork()) and true or false
							end,
							disabled = function(info)
								return ShamanPower.opt.enabled == false or not isShaman or not ShamanPower.opt.showTotemFlyouts
							end,
							get = function(info)
								return ShamanPower.opt.flyoutRequiresClick
							end,
							set = function(info, val)
								ShamanPower.opt.flyoutRequiresClick = val
								ShamanPower:UpdateTotemFlyoutEnabled()
							end
						},
						totem_flyout_button_size = FlyoutSizeOption(3.4, "full", "totemFlyoutButtonSize", 28,
							"Totem Flyout Icon Size (icon bar)",
							"How big the icons in the totem flyouts are while the totem bar shows icons. 28 is the classic size. The Compact style has its own size, with the Compact Style settings. The totem bar's scale still applies on top.",
							"ApplyTotemFlyoutButtonSize", function() return not ShamanPower.opt.showTotemFlyouts end),
						flyout_combat_header = {
							order = 3.5,
							type = "header",
							name = "Flyouts (totem bar and cooldown bar)",
							hidden = function(info)
								return not (SPCompat and SPCompat.SecureSnippetsWork and not SPCompat.SecureSnippetsWork())
							end,
						},
						flyout_style = {
							order = 5,
							type = "select",
							name = "Flyout Style",
							desc = "|cffffd100Icons only|r: the flyout is just the totem icons.\n|cffffd100Blizzard frame|r: the icons sit in Blizzard's totem bar flyout frame, tinted per element, with the close tab at the far end.",
							width = "full",
							values = { icons = "Icons only", frame = "Blizzard frame" },
							sorting = { "icons", "frame" },
							hidden = function(info)
								return not (SPCompat and SPCompat.SecureSnippetsWork and not SPCompat.SecureSnippetsWork())
							end,
							disabled = function(info)
								-- also governs the shield / imbue flyouts, so it stays usable with totem flyouts off
								return ShamanPower.opt.enabled == false or not isShaman
							end,
							get = function(info)
								return ShamanPower.opt.flyoutStyle or "icons"
							end,
							set = function(info, val)
								ShamanPower.opt.flyoutStyle = val
								if InCombatLockdown() then
									print("|cff0070ddShamanPower|r: takes effect after combat.")
									return
								end
								for _, entry in pairs(ShamanPower.boxFlyouts or {}) do pcall(entry.relayout) end
							end
						},
						flyout_frame_opacity = {
							order = 6,
							type = "range",
							name = "Frame Opacity",
							desc = "How solid the Blizzard frame's border and background are. Lower is lighter and more see-through.",
							min = 0.1, max = 1.0, step = 0.05,
							isPercent = true,
							width = "full",
							hidden = function(info)
								return not (SPCompat and SPCompat.SecureSnippetsWork and not SPCompat.SecureSnippetsWork())
									or (ShamanPower.opt.flyoutStyle or "icons") ~= "frame"
							end,
							get = function(info)
								return ShamanPower.opt.flyoutFrameOpacity or 1.0
							end,
							set = function(info, val)
								ShamanPower.opt.flyoutFrameOpacity = val
								-- artwork only, so this is safe to apply at any time, even in combat
								for _, entry in pairs(ShamanPower.boxFlyouts or {}) do
									ShamanPower:DressFlyoutFrame(entry.flyout)
								end
							end
						},
						flyout_close_on_cast = {
							order = 4.5,
							type = "toggle",
							name = "Close Flyout After Casting From It",
							desc = "Clicking a totem, shield or imbue in a flyout casts it and closes the flyout in the same click. Turn it off to keep the flyout open until you close it yourself (handy for dropping several totems in a row).",
							width = "full",
							hidden = function(info)
								return not (SPCompat and SPCompat.SecureSnippetsWork and not SPCompat.SecureSnippetsWork())
							end,
							disabled = function(info)
								-- also governs the shield / imbue flyouts, so it stays usable with totem flyouts off
								return ShamanPower.opt.enabled == false or not isShaman
							end,
							get = function(info)
								return ShamanPower.opt.flyoutCloseOnCast ~= false
							end,
							set = function(info, val)
								ShamanPower.opt.flyoutCloseOnCast = val
								if InCombatLockdown() then
									print("|cff0070ddShamanPower|r: takes effect after combat.")
								end
								ShamanPower:ApplyFlyoutPickMacros()
							end
						},
						flyout_route_bar_keys = {
							order = 4.6,
							type = "toggle",
							name = "Action Bar Keys Also Close the Flyout",
							desc = "If a totem, shield or imbue from a flyout is also on your action bars with a keybind, that key is sent through ShamanPower's own button: it casts the same spell and closes the flyout, even in combat.\n\nOnly for bar slots holding the plain spell, never a macro. Blizzard's action button will not show the press animation for those keys. Turn this off to leave your action bar keys completely alone.",
							width = "full",
							hidden = function(info)
								return not (SPCompat and SPCompat.SecureSnippetsWork and not SPCompat.SecureSnippetsWork())
							end,
							disabled = function(info)
								return ShamanPower.opt.enabled == false or not isShaman or not ShamanPower.opt.showTotemFlyouts
									or ShamanPower.opt.flyoutCloseOnCast == false
							end,
							get = function(info)
								return ShamanPower.opt.flyoutRouteBarKeys ~= false
							end,
							set = function(info, val)
								ShamanPower.opt.flyoutRouteBarKeys = val
								if InCombatLockdown() then
									print("|cff0070ddShamanPower|r: takes effect after combat.")
								end
								ShamanPower:SetupKeybindings()
							end
						},
						swap_all_clicks = {
							order = 3.6,
							type = "toggle",
							name = "Swap Left and Right Click",
							desc = "Flips the mouse on ShamanPower's buttons, so right-click is the main action everywhere.\n\nTotem buttons: right-click drops the totem, left-click does the other action (pull it back or Totemic Call, shift for the shifted one).\nTotem flyouts: right-click casts, left-click assigns.\nShield flyout: right-click casts and sets the default, left-click only sets it.\nWeapon imbues: right-click is the main hand, left-click the off hand.\nDrop All: right-click drops, left-click recalls.\n\nCooldown buttons with a single action work with either click. Your keybinds keep doing what they did.",
							width = "full",
							hidden = function(info)
								return not (ShamanPower.ApplyClickSwap and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE)
							end,
							disabled = function(info)
								return ShamanPower.opt.enabled == false or not isShaman
							end,
							get = function(info)
								return ShamanPower.opt.swapFlyoutClickButtons == true
							end,
							set = function(info, val)
								if InCombatLockdown() then
									print("|cff0070ddShamanPower:|r the mouse buttons cannot be swapped in combat")
									return
								end
								ShamanPower.opt.swapFlyoutClickButtons = val
								ShamanPower:UpdateFlyoutClickBehavior()   -- totem flyouts (rebuilt in box mode)
								ShamanPower:ApplyClickSwap()
								ShamanPower:SetupKeybindings()
								if ShamanPower.RouteFlyoutBarKeys then ShamanPower:RouteFlyoutBarKeys() end
							end
						},
						flyout_reset = {
							order = 6.9,
							type = "execute",
							name = "Reset Flyout Settings to Defaults",
							desc = "Puts every setting in this section back to its default. Asks first. Positions are not changed.",
							hidden = function(info)
								return not (SPCompat and SPCompat.SecureSnippetsWork and not SPCompat.SecureSnippetsWork())
							end,
							func = function() ShamanPower:ConfirmResetSection("flyouts") end,
						},
						flyout_arrows_always = {
							order = 4.2,
							type = "toggle",
							name = "Always Show the Flyout Arrows",
							desc = "Keeps the small arrow tab on every button that has a flyout, out of combat as well. Off: the arrows only appear when a fight starts, and out of combat flyouts simply open when you hover.",
							width = "full",
							hidden = function(info)
								return not (SPCompat and SPCompat.SecureSnippetsWork and not SPCompat.SecureSnippetsWork())
							end,
							disabled = function(info)
								return ShamanPower.opt.enabled == false or not isShaman or ShamanPower.opt.flyoutArrowOnly == true
							end,
							get = function(info)
								return (ShamanPower.opt.flyoutArrowsAlways or ShamanPower.opt.flyoutArrowOnly) and true or false
							end,
							set = function(info, val)
								ShamanPower.opt.flyoutArrowsAlways = val
								if InCombatLockdown() then
									print("|cff0070ddShamanPower|r: takes effect when the fight ends.")
									return
								end
								ShamanPower:RefreshFlyoutLayout()
							end
						},
						flyout_arrow_only = {
							order = 4.3,
							type = "toggle",
							name = "Open Flyouts Only From the Arrow or a Keybind",
							desc = "Hovering a button never opens its flyout, in or out of combat. A flyout opens from its arrow or its toggle keybind, and stays open until you pick from it, press the arrow again, or press the key again. The arrows are always shown in this mode.",
							width = "full",
							hidden = function(info)
								return not (SPCompat and SPCompat.SecureSnippetsWork and not SPCompat.SecureSnippetsWork())
							end,
							disabled = function(info)
								return ShamanPower.opt.enabled == false or not isShaman
							end,
							get = function(info)
								return ShamanPower.opt.flyoutArrowOnly == true
							end,
							set = function(info, val)
								ShamanPower.opt.flyoutArrowOnly = val
								if InCombatLockdown() then
									print("|cff0070ddShamanPower|r: takes effect when the fight ends.")
									return
								end
								ShamanPower:UpdateTotemFlyoutEnabled()
								ShamanPower:RefreshFlyoutLayout()
							end
						},
						flyout_show_empty = {
							order = 4.7,
							type = "toggle",
							name = "Offer an \"Empty\" Choice in Totem Flyouts",
							desc = "Adds a faded totem to each totem flyout, as on Blizzard's totem bar. Picking it leaves that element with no totem assigned, so the button casts nothing until you pick a totem again. (While Totem Twisting is on, the Air button always casts the twist sequence, whatever is assigned.)",
							width = "full",
							hidden = function(info)
								return not (SPCompat and SPCompat.SecureSnippetsWork and not SPCompat.SecureSnippetsWork())
							end,
							disabled = function(info)
								return ShamanPower.opt.enabled == false or not isShaman or not ShamanPower.opt.showTotemFlyouts
							end,
							get = function(info)
								return ShamanPower.opt.flyoutShowEmpty ~= false
							end,
							set = function(info, val)
								ShamanPower.opt.flyoutShowEmpty = val
								if InCombatLockdown() then
									print("|cff0070ddShamanPower|r: takes effect after a /reload or your next login.")
									return
								end
								for element = 1, 4 do ShamanPower:RebuildTotemFlyout(element) end
							end
						},
						flyout_single_open = {
							order = 4,
							type = "toggle",
							name = "In Combat: Opening One Flyout Closes the Others",
							desc = "In combat, flyouts open from the arrow tab on each totem button. With this on, clicking an arrow closes any other open flyout, so only one is ever open. Turn it off to let several stay open until you pick a totem or close them.",
							width = "full",
							-- only meaningful where the arrow flyouts exist (clients whose secure snippets are broken)
							hidden = function(info)
								return not (SPCompat and SPCompat.SecureSnippetsWork and not SPCompat.SecureSnippetsWork())
							end,
							disabled = function(info)
								-- also governs the shield / imbue flyouts, so it stays usable with totem flyouts off
								return ShamanPower.opt.enabled == false or not isShaman
							end,
							get = function(info)
								return ShamanPower.opt.flyoutSingleOpen ~= false
							end,
							set = function(info, val)
								ShamanPower.opt.flyoutSingleOpen = val
								if InCombatLockdown() then
									print("|cff0070ddShamanPower|r: takes effect after combat.")
								end
								ShamanPower:ApplyFlyoutArrowMode()
							end
						},
					}
				},
				scale_section = {
					order = 2,
					name = "Scale",
					type = "group",
					args = {
						scale_reset = {
							order = 99,
							type = "execute",
							name = "Reset Scale Settings to Defaults",
							desc = "Puts every setting in this section back to its default. Asks first. Positions are not changed.",
							func = function() ShamanPower:ConfirmResetSection("scale") end,
						},
						scale_desc = {
							order = 0,
							type = "description",
							name = "Adjust the overall size of your bars and buttons.",
						},
						buffscale = {
							order = 1,
							name = "Totem Bar Scale",
							desc = "Adjust the size of the totem bar and main ShamanPower buttons",
							type = "range",
							isPercent = true,
							width = 1.5,
							min = 0.4,
							max = 3.0,
							step = 0.05,
							disabled = function(info)
								return ShamanPower.opt.enabled == false or not isShaman
							end,
							get = function(info)
								return ShamanPower.opt.buffscale
							end,
							set = function(info, val)
								ShamanPower.opt.buffscale = val
								ShamanPower:UpdateLayout()
								ShamanPower:UpdateCooldownBarScale()
								ShamanPower:UpdateRoster()
							end
						},
						cooldownFlyoutButtonSize = FlyoutSizeOption(2.1, 1.5, "cooldownFlyoutButtonSize", 22,
							"Cooldown Bar Flyout Icon Size",
							"How big the icons in the shield and weapon imbue flyouts are. 22 is the classic size. The cooldown bar's scale still applies on top.",
							"ApplyCooldownFlyoutButtonSize", function() return not ShamanPower.opt.showCooldownBar end),
						cooldownBarScale = {
							order = 2,
							name = "Cooldown Bar Scale",
							desc = "Adjust the size of the cooldown tracker bar independently",
							type = "range",
							isPercent = true,
							width = 1.5,
							min = 0.4,
							max = 3.0,
							step = 0.05,
							disabled = function(info)
								return ShamanPower.opt.enabled == false or not isShaman or not ShamanPower.opt.showCooldownBar
							end,
							get = function(info)
								return ShamanPower.opt.cooldownBarScale or 0.9
							end,
							set = function(info, val)
								ShamanPower.opt.cooldownBarScale = val
								ShamanPower:UpdateCooldownBarScale()
							end
						},
						assignmentsscale = {
							order = 3,
							name = L["Totem Assignments Scale"],
							desc = L["This allows you to adjust the overall size of the Totem Assignments Panel"],
							type = "range",
							isPercent = true,
							width = 1.5,
							min = 0.4,
							max = 3.0,
							step = 0.05,
							disabled = function(info)
								return ShamanPower.opt.enabled == false or not isShaman
							end,
							get = function(info)
								return ShamanPower.opt.configscale
							end,
							set = function(info, val)
								ShamanPower.opt.configscale = val
								ShamanPower:UpdateLayout()
								ShamanPower:UpdateRoster()
							end
						},
					}
				},
				opacity_section = {
					order = 3,
					name = "Opacity",
					type = "group",
					args = {
						opacity_reset = {
							order = 99,
							type = "execute",
							name = "Reset Opacity Settings to Defaults",
							desc = "Puts every setting in this section back to its default. Asks first. Positions are not changed.",
							func = function() ShamanPower:ConfirmResetSection("opacity") end,
						},
						opacity_desc = {
							order = 0,
							type = "description",
							name = "Control transparency of your bars. Use 'Full Opacity When Active' to highlight active totems/cooldowns.",
						},
						totemBarOpacity = {
							order = 1,
							name = "Totem Bar",
							desc = "Adjust the opacity/transparency of the totem bar",
							type = "range",
							width = 1.2,
							min = 0,
							max = 1.0,
							step = 0.05,
							isPercent = true,
							disabled = function(info)
								return ShamanPower.opt.enabled == false or not isShaman
							end,
							get = function(info)
								return ShamanPower.opt.totemBarOpacity or 1.0
							end,
							set = function(info, val)
								ShamanPower.opt.totemBarOpacity = val
								ShamanPower:UpdateTotemBarOpacity()
							end
						},
						totemBarFullOpacityWhenActive = {
							order = 1.5,
							name = "Full Opacity When Totem Placed",
							desc = "Show totem buttons at full opacity when that element's totem is active (overrides the opacity setting above)",
							type = "toggle",
							width = "full",
							disabled = function(info)
								return ShamanPower.opt.enabled == false or not isShaman
							end,
							get = function(info)
								return ShamanPower.opt.totemBarFullOpacityWhenActive
							end,
							set = function(info, val)
								ShamanPower.opt.totemBarFullOpacityWhenActive = val
								ShamanPower:UpdateTotemBarOpacity()
							end
						},
						cooldownBarOpacity = {
							order = 2,
							name = "Cooldown Bar",
							desc = "Adjust the opacity/transparency of the cooldown bar",
							type = "range",
							width = 1.2,
							min = 0,
							max = 1.0,
							step = 0.05,
							isPercent = true,
							disabled = function(info)
								return ShamanPower.opt.enabled == false or not isShaman or not ShamanPower.opt.showCooldownBar
							end,
							get = function(info)
								return ShamanPower.opt.cooldownBarOpacity or 1.0
							end,
							set = function(info, val)
								ShamanPower.opt.cooldownBarOpacity = val
								ShamanPower:UpdateCooldownBarOpacity()
							end
						},
						cooldownBarFullOpacityWhenActive = {
							order = 2.5,
							name = "Full Opacity When Active",
							desc = "Show cooldown buttons at full opacity when the buff is active or the ability is on cooldown",
							type = "toggle",
							width = "full",
							disabled = function(info)
								return ShamanPower.opt.enabled == false or not isShaman or not ShamanPower.opt.showCooldownBar
							end,
							get = function(info)
								return ShamanPower.opt.cooldownBarFullOpacityWhenActive
							end,
							set = function(info, val)
								ShamanPower.opt.cooldownBarFullOpacityWhenActive = val
								ShamanPower:UpdateCooldownBarOpacity()
							end
						},
						totemFlyoutOpacity = {
							order = 3,
							name = "Totem Flyouts",
							desc = "Adjust the opacity/transparency of the totem bar flyout menus",
							type = "range",
							width = 1.2,
							min = 0.1,
							max = 1.0,
							step = 0.05,
							isPercent = true,
							disabled = function(info)
								return ShamanPower.opt.enabled == false or not isShaman or not ShamanPower.opt.showTotemFlyouts
							end,
							get = function(info)
								return ShamanPower.opt.totemFlyoutOpacity or 1.0
							end,
							set = function(info, val)
								ShamanPower.opt.totemFlyoutOpacity = val
								ShamanPower:UpdateTotemFlyoutOpacity()
							end
						},
						cooldownFlyoutOpacity = {
							order = 4,
							name = "CD Flyouts",
							desc = "Adjust the opacity/transparency of the cooldown bar flyout menus",
							type = "range",
							width = 1.2,
							min = 0.1,
							max = 1.0,
							step = 0.05,
							isPercent = true,
							disabled = function(info)
								return ShamanPower.opt.enabled == false or not isShaman or not ShamanPower.opt.showCooldownBar
							end,
							get = function(info)
								return ShamanPower.opt.cooldownFlyoutOpacity or 1.0
							end,
							set = function(info, val)
								ShamanPower.opt.cooldownFlyoutOpacity = val
								ShamanPower:UpdateCooldownFlyoutOpacity()
							end
						},
					}
				},
				padding_section = {
					order = 4,
					name = "Button Padding",
					type = "group",
					args = {
						padding_reset = {
							order = 99,
							type = "execute",
							name = "Reset Button Padding to Defaults",
							desc = "Puts every setting in this section back to its default. Asks first. Positions are not changed.",
							func = function() ShamanPower:ConfirmResetSection("padding") end,
						},
						padding_desc = {
							order = 0,
							type = "description",
							name = "Adjust the spacing between buttons on your bars.",
						},
						totemBarPadding = {
							order = 1,
							name = "Totem Bar Padding",
							desc = "Adjust the spacing between totem bar buttons (in pixels)",
							type = "range",
							width = 1.5,
							min = 0,
							max = 20,
							step = 1,
							disabled = function(info)
								return ShamanPower.opt.enabled == false or not isShaman
							end,
							get = function(info)
								return ShamanPower.opt.totemBarPadding or 2
							end,
							set = function(info, val)
								ShamanPower.opt.totemBarPadding = val
								ShamanPower:UpdateRoster()
							end
						},
						cooldownBarPadding = {
							order = 2,
							name = "Cooldown Bar Padding",
							desc = "Adjust the spacing between cooldown bar buttons (in pixels)",
							type = "range",
							width = 1.5,
							min = 0,
							max = 20,
							step = 1,
							disabled = function(info)
								return ShamanPower.opt.enabled == false or not isShaman or not ShamanPower.opt.showCooldownBar
							end,
							get = function(info)
								return ShamanPower.opt.cooldownBarPadding or 2
							end,
							set = function(info, val)
								ShamanPower.opt.cooldownBarPadding = val
								ShamanPower:UpdateCooldownBar()
							end
						},
					}
				},
				visibility_section = {
					order = 5,
					name = "Frame Visibility",
					type = "group",
					args = {
						visibility_desc = {
							order = 0,
							type = "description",
							name = "Show or hide various UI elements like frames, text, keybinds, and drag handles.",
						},
						hide_totem_bar_frame = {
							order = 1,
							type = "toggle",
							name = "Hide Totem Bar Frame",
							desc = "Hide the background and border around the totem bar (show icons only)",
							width = 1.5,
							get = function(info)
								return ShamanPower.opt.hideTotemBarFrame
							end,
							set = function(info, val)
								ShamanPower.opt.hideTotemBarFrame = val
								ShamanPower:UpdateTotemBarFrame()
							end
						},
						hide_cooldown_bar_frame = {
							order = 2,
							type = "toggle",
							name = "Hide Cooldown Bar Frame",
							desc = "Hide the background and border around the cooldown bar (show icons only)",
							width = 1.5,
							disabled = function(info)
								return not ShamanPower.opt.showCooldownBar
							end,
							get = function(info)
								return ShamanPower.opt.hideCooldownBarFrame
							end,
							set = function(info, val)
								ShamanPower.opt.hideCooldownBarFrame = val
								ShamanPower:UpdateCooldownBarFrame()
							end
						},
						hide_earth_shield_text = {
							order = 3,
							type = "toggle",
							name = "Hide Earth Shield Text",
							desc = WithNotes("Hide the Earth Shield target name text below the button on the totem bar",
								CompactOn, "Compact style never shows the target name on the Earth Shield line, so this only matters on the icon bar."),
							hidden = function(info) return not ShamanPower:HasEarthShield() end,
							width = 1.5,
							get = function(info)
								return ShamanPower.opt.hideEarthShieldText
							end,
							set = function(info, val)
								ShamanPower.opt.hideEarthShieldText = val
								ShamanPower:UpdateEarthShieldButton()
							end
						},
						show_button_keybinds = {
							order = 4,
							type = "toggle",
							name = "Show Keybinds on Buttons",
							desc = "Display keybind text on buttons (top-right corner)",
							width = 1.5,
							get = function(info)
								return ShamanPower.opt.showButtonKeybinds
							end,
							set = function(info, val)
								ShamanPower.opt.showButtonKeybinds = val
								ShamanPower:UpdateButtonKeybindText()
								-- and again shortly after, in case the first pass ran before the
								-- spell names were available
								if val and ShamanPower.QueueKeybindTextRefresh then ShamanPower:QueueKeybindTextRefresh() end
							end
						},
					}
				},
				texture_section = {
					order = 6,
					name = "Textures",
					type = "group",
					args = {
						texture_desc = {
							order = 0,
							type = "description",
							name = function()
								return "The background and border of the totem bar's panel - the box drawn behind the four totem buttons. (The icons, the flyouts, the cooldown bar and the Compact lines are not skinned by this.)"
									.. (PanelHidden() and PANEL_HIDDEN_NOTE or "")
							end,
						},
						skin = {
							order = 1,
							name = L["Background Textures"],
							desc = "The texture that fills the totem bar's panel (the box behind the totem buttons).",
							type = "select",
							width = 1.5,
							dialogControl = "LSM30_Background",
							values = AceGUIWidgetLSMlists.background,
							disabled = function(info)
								return ShamanPower.opt.enabled == false or not isShaman or PanelHidden()
							end,
							get = function(info)
								return ShamanPower.opt.skin
							end,
							set = function(info, val)
								ShamanPower.opt.skin = val
								ShamanPower:ApplySkin()
								ShamanPower:UpdateRoster()
							end
						},
						edges = {
							order = 2,
							name = L["Borders"],
							desc = "The border drawn around the totem bar's panel (the box behind the totem buttons).",
							type = "select",
							width = 1.5,
							dialogControl = "LSM30_Border",
							values = AceGUIWidgetLSMlists.border,
							disabled = function(info)
								return ShamanPower.opt.enabled == false or not isShaman or PanelHidden()
							end,
							get = function(info)
								return ShamanPower.opt.border
							end,
							set = function(info, val)
								ShamanPower.opt.border = val
								ShamanPower:ApplySkin()
								ShamanPower:UpdateRoster()
							end
						},
					}
				},
				cooldown_display_section = {
					order = 11,
					name = "Cooldown Display",
					type = "group",
					hidden = function(info)
						return not ShamanPower.opt.showCooldownBar
					end,
					args = {
						cdbar_display_desc = {
							order = 0,
							type = "description",
							name = "Customize how cooldowns and durations are displayed on the cooldown bar.",
						},
						cdbar_show_progress_bars = {
							order = 1,
							type = "toggle",
							name = "Show Progress Bars",
							desc = "Show colored progress bars on the edges of cooldown buttons",
							width = "full",
							get = function(info)
								return ShamanPower.opt.cdbarShowProgressBars ~= false
							end,
							set = function(info, val)
								ShamanPower.opt.cdbarShowProgressBars = val
								if ShamanPower.RebuildShieldChargeContainer then ShamanPower:RebuildShieldChargeContainer() end   -- the engine-drawn shield display reads these once, when built
							end
						},
						cdbar_show_color_sweep = {
							order = 2,
							type = "toggle",
							name = "Show Color Sweep Overlay",
							desc = "Show greyed-out sweep overlay as time depletes",
							width = "full",
							get = function(info)
								return ShamanPower.opt.cdbarShowColorSweep ~= false
							end,
							set = function(info, val)
								ShamanPower.opt.cdbarShowColorSweep = val
								if ShamanPower.RebuildShieldChargeContainer then ShamanPower:RebuildShieldChargeContainer() end   -- the engine-drawn shield display reads these once, when built
							end
						},
						cdbar_sweep_style = {
							order = 2.5,
							type = "select",
							name = "Sweep Style",
							desc = "Greys out: the grey grows down from the top as time runs out. Fills back in: the icon starts grey and the color returns as time runs down. Radial: the classic clock swipe (shields and cooldowns; weapon imbues keep the vertical sweep).",
							width = 1.2,
							values = {
								["greys"] = "Vertical - greys out",
								["fills"] = "Vertical - fills back in",
								["radial"] = "Radial swipe",
							},
							disabled = function()
								return ShamanPower.opt.cdbarShowColorSweep == false
							end,
							get = function(info)
								return ShamanPower.opt.cdbarSweepStyle or "greys"
							end,
							set = function(info, val)
								ShamanPower.opt.cdbarSweepStyle = val
								ShamanPower:UpdateCooldownBar()
								if ShamanPower.RebuildShieldChargeContainer then ShamanPower:RebuildShieldChargeContainer() end   -- the engine-drawn shield display reads these once, when built
							end
						},
						cdbar_show_cd_text = {
							order = 3,
							type = "toggle",
							name = "Show Cooldown Text",
							desc = WithNotes("Show cooldown time remaining as text. Only used while Duration Text Location is set to None; any other location always shows the time.",
								function() return (ShamanPower.opt.cdbarDurationTextLocation or "none") ~= "none" end, "Duration Text Location is not None right now, so the time is always shown and this toggle does nothing."),
							width = "full",
							get = function(info)
								return ShamanPower.opt.cdbarShowCDText ~= false
							end,
							set = function(info, val)
								ShamanPower.opt.cdbarShowCDText = val
								if val and ShamanPower.EnableCountdownNumbers then ShamanPower:EnableCountdownNumbers() end
							end
						},
						cdbar_numbers_note = {
							order = 3.05,
							type = "description",
							name = "|cffffa040On this client the time is drawn by the game, and WoW's own \"Show Numbers for Cooldowns\" setting is off, so no time can show on the cooldown bar.|r",
							hidden = function()
								return not (ShamanPower.EngineCooldownsOn and ShamanPower:EngineCooldownsOn() and not ShamanPower:CountdownNumbersEnabled()
									and (ShamanPower.opt.cdbarShowCDText ~= false or (ShamanPower.opt.cdbarDurationTextLocation or "none") ~= "none"))
							end,
						},
						cdbar_numbers_button = {
							order = 3.06,
							type = "execute",
							name = "Turn on Show Numbers for Cooldowns",
							desc = "Turns on WoW's own cooldown numbers (Options > Action Bars). They then show on your action bars as well.",
							width = 1.6,
							hidden = function()
								return not (ShamanPower.EngineCooldownsOn and ShamanPower:EngineCooldownsOn() and not ShamanPower:CountdownNumbersEnabled()
									and (ShamanPower.opt.cdbarShowCDText ~= false or (ShamanPower.opt.cdbarDurationTextLocation or "none") ~= "none"))
							end,
							func = function() ShamanPower:EnableCountdownNumbers() end,
						},
						shield_charge_colors = {
							disabled = function(info) return (ShamanPower.opt.cdbarShowShields == false) and true or false end,
							order = 4,
							type = "toggle",
							name = "Color Shield Charges by Count",
							desc = "Color shield charge count based on remaining charges (Green=full, Yellow=half, Red=low). Disable for plain white text.",
							width = "full",
							get = function(info)
								return ShamanPower.opt.shieldChargeColors ~= false
							end,
							set = function(info, val)
								ShamanPower.opt.shieldChargeColors = val
								if ShamanPower.RebuildShieldChargeContainer then ShamanPower:RebuildShieldChargeContainer() end   -- the engine-drawn shield display reads these once, when built
							end
						},
						show_ankh_count = {
							disabled = function(info) return (ShamanPower.opt.cdbarShowReincarnation == false) and true or false end,
							order = 4.5,
							type = "toggle",
							name = "Show Ankh Count on Reincarnation",
							desc = "Display the number of Ankhs in your inventory on the Reincarnation icon",
							width = "full",
							get = function(info)
								return ShamanPower.opt.showAnkhCount
							end,
							set = function(info, val)
								ShamanPower.opt.showAnkhCount = val
							end
						},
						spacer1 = {
							order = 5,
							type = "description",
							name = "\n",
							width = "full",
						},
						cdbar_progress_position = {
							disabled = function(info) return (ShamanPower.opt.cdbarShowProgressBars == false) and true or false end,
							order = 6,
							type = "select",
							name = "Progress Bar Position",
							desc = "Position of the progress bar relative to icons",
							width = "full",
							values = {
								["left"] = "Left",
								["right"] = "Right",
								["top"] = "Top (Horizontal)",
								["top_vert"] = "Top (Vertical)",
								["bottom"] = "Bottom (Horizontal)",
								["bottom_vert"] = "Bottom (Vertical)",
								["on_icon"] = "On Icon (Left & Right)",
							},
							get = function(info)
								return ShamanPower.opt.cdbarProgressPosition or "left"
							end,
							set = function(info, val)
								ShamanPower.opt.cdbarProgressPosition = val
								ShamanPower:RecreateCooldownBar()
							end
						},
						cdbar_progress_height = {
							disabled = function(info) return (ShamanPower.opt.cdbarShowProgressBars == false) and true or false end,
							order = 7,
							type = "range",
							name = "Progress Bar Size",
							desc = "Size of the duration bar (height for horizontal bars, width for vertical bars)",
							width = "full",
							min = 3,
							max = 16,
							step = 1,
							get = function(info)
								return ShamanPower.opt.cdbarProgressBarHeight or 3
							end,
							set = function(info, val)
								ShamanPower.opt.cdbarProgressBarHeight = val
								ShamanPower:UpdateCooldownBarProgressBars()
								ShamanPower:UpdateCooldownBarLayout()
							end
						},
						cdbar_spell_colors = {
							disabled = function(info) return (ShamanPower.opt.cdbarShowProgressBars == false) and true or false end,
							order = 8,
							type = "toggle",
							name = "Spell-Colored Progress Bars",
							desc = WithNotes("Color progress bars based on the spell (e.g. Lightning Shield = blue, Reincarnation = red, Flametongue = orange). The spell colour replaces the green \"plenty of time\" colour only: with less than 10 minutes left a bar still turns yellow, then red.",
								function() return ShamanPower.opt.cdbarShowProgressBars == false end, "\"Show Progress Bars\" is off, so there are no bars to colour."),
							width = "full",
							get = function(info)
								return ShamanPower.opt.cdbarSpellColors or false
							end,
							set = function(info, val)
								ShamanPower.opt.cdbarSpellColors = val
								if ShamanPower.RebuildShieldChargeContainer then ShamanPower:RebuildShieldChargeContainer() end   -- the engine-drawn shield display reads these once, when built
							end
						},
						cdbar_duration_text = {
							order = 9,
							type = "select",
							name = "Duration Text Location",
							desc = "Where to show the remaining duration time",
							width = "full",
							values = {
								["none"] = "None",
								["inside"] = "Inside Bar",
								["outside"] = "Outside Bar",
								["icon"] = "On Icon",
							},
							get = function(info)
								return ShamanPower.opt.cdbarDurationTextLocation or "none"
							end,
							set = function(info, val)
								ShamanPower.opt.cdbarDurationTextLocation = val
								if ShamanPower.RebuildShieldChargeContainer then ShamanPower:RebuildShieldChargeContainer() end   -- the engine-drawn shield display reads these once, when built
								if val ~= "none" and ShamanPower.EnableCountdownNumbers then ShamanPower:EnableCountdownNumbers() end
							end
						},
						cdbar_duration_text_size = {
							order = 10,
							type = "range",
							name = "Duration Text Size",
							desc = "Font size for duration text on the cooldown bar",
							width = "full",
							min = 6, max = 20, step = 1,
							hidden = function()
								return (ShamanPower.opt.cdbarDurationTextLocation or "none") == "none"
							end,
							get = function(info)
								return ShamanPower.opt.cdbarDurationTextSize or 8
							end,
							set = function(info, val)
								ShamanPower.opt.cdbarDurationTextSize = val
								ShamanPower:ApplyCdbarTextSize()
							end
						},
					}
				},
				color_section = {
					order = 19,
					name = "Status Colors",
					type = "group",
					disabled = function(info)
						return ShamanPower.opt.enabled == false or not isShaman
					end,
					args = {
						color_desc = {
							order = 0,
							type = "description",
							name = function()
								return "The totem bar's panel is tinted by how many of your assigned totems are down: all of them, some of them, or none."
									.. (PanelHidden() and "\n\n|cffffa040The totem bar's panel is hidden right now, so these three colours are not visible. Turn off \"Hide Totem Bar Frame\" (Appearance > Visibility) to see them.|r" or "")
							end,
						},
						color_good = {
							order = 1,
							name = L["Fully Buffed"],
							type = "color",
							disabled = StatusColorDisabled,
							get = function()
								return ShamanPower.opt.cBuffGood.r, ShamanPower.opt.cBuffGood.g, ShamanPower.opt.cBuffGood.b, ShamanPower.opt.cBuffGood.t
							end,
							set = function(info, r, g, b, t)
								ShamanPower:EnsureProfileTable("cBuffGood")
								ShamanPower.opt.cBuffGood.r = r
								ShamanPower.opt.cBuffGood.g = g
								ShamanPower.opt.cBuffGood.b = b
								ShamanPower.opt.cBuffGood.t = t
							end,
							hasAlpha = true
						},
						color_partial = {
							order = 2,
							name = L["Partially Buffed"],
							type = "color",
							disabled = StatusColorDisabled,
							width = 1.1,
							get = function()
								return ShamanPower.opt.cBuffNeedSome.r, ShamanPower.opt.cBuffNeedSome.g, ShamanPower.opt.cBuffNeedSome.b, ShamanPower.opt.cBuffNeedSome.t
							end,
							set = function(info, r, g, b, t)
								ShamanPower:EnsureProfileTable("cBuffNeedSome")
								ShamanPower.opt.cBuffNeedSome.r = r
								ShamanPower.opt.cBuffNeedSome.g = g
								ShamanPower.opt.cBuffNeedSome.b = b
								ShamanPower.opt.cBuffNeedSome.t = t
							end,
							hasAlpha = true
						},
						color_missing = {
							order = 3,
							name = L["None Buffed"],
							type = "color",
							disabled = StatusColorDisabled,
							get = function()
								return ShamanPower.opt.cBuffNeedAll.r, ShamanPower.opt.cBuffNeedAll.g, ShamanPower.opt.cBuffNeedAll.b, ShamanPower.opt.cBuffNeedAll.t
							end,
							set = function(info, r, g, b, t)
								ShamanPower:EnsureProfileTable("cBuffNeedAll")
								ShamanPower.opt.cBuffNeedAll.r = r
								ShamanPower.opt.cBuffNeedAll.g = g
								ShamanPower.opt.cBuffNeedAll.b = b
								ShamanPower.opt.cBuffNeedAll.t = t
							end,
							hasAlpha = true
						}
					}
				},
				raid_cd_section = {
					order = 18,
					name = "|cff0070ddRaid Cooldowns|r",
					type = "group",
					args = {
						no_group_note = {
							order = 0.05,
							type = "description",
							name = "|cffffa040Caller buttons only appear in a group, and only when you are an assigned caller (or raid lead / assist). Solo there is nothing on screen for the button settings to change. /spraid opens the assignments.|r",
							hidden = function() return not (ShamanPower.RaidCooldownsLoaded and GetNumGroupMembers() == 0) end,
						},
						module_missing_note = {
							order = 0.01,
							type = "description",
							name = "|cffffa040This module is not loaded, so nothing on this page does anything right now (toggles may even snap back). Enable the ShamanPower [Raid Cooldowns] addon in the AddOns list and /reload.|r",
							hidden = function() return not (not ShamanPower.RaidCooldownsLoaded) end,
						},
						raid_cd_desc = {
							order = 0,
							type = "description",
							name = function()
								local what = (SPCompat and SPCompat.RaidCooldownNames) and SPCompat.RaidCooldownNames("Bloodlust/Heroism") or "Bloodlust/Heroism, Mana Tide and Drums of Battle"
								return "Manage " .. what .. " calling for your raid.\n\n|cffff8800Note:|r Requires the |cff00ff00ShamanPower [Raid Cooldowns]|r module to be enabled in your AddOns list.\n"
							end,
						},
						raidCDButtonScale = {
							order = 1,
							name = "Caller Button Scale",
							desc = "Adjust the size of the raid cooldown caller buttons",
							type = "range",
							isPercent = true,
							width = 1.5,
							min = 0.5,
							max = 2.0,
							step = 0.05,
							get = function(info)
								return ShamanPower.opt.raidCDButtonScale or 1.0
							end,
							set = function(info, val)
								ShamanPower.opt.raidCDButtonScale = val
								ShamanPower:UpdateCallerButtonScale()
							end
						},
						raidCDButtonOpacity = {
							order = 2,
							name = "Caller Button Opacity",
							desc = "Adjust the opacity of the raid cooldown caller buttons",
							type = "range",
							isPercent = true,
							width = 1.5,
							min = 0.1,
							max = 1.0,
							step = 0.05,
							get = function(info)
								return ShamanPower.opt.raidCDButtonOpacity or 1.0
							end,
							set = function(info, val)
								ShamanPower.opt.raidCDButtonOpacity = val
								ShamanPower:UpdateCallerButtonOpacity()
							end
						},
						raidCDButtonShowFrame = {
							order = 2.5,
							name = "Show Caller Button Frame",
							desc = "Show the panel and border behind the caller buttons. Turn this off (or use Hide Frame on the buttons' settings) for icons only.",
							type = "toggle",
							width = 1.5,
							get = function(info)
								return not ShamanPower.opt.raidCDButtonHideFrame
							end,
							set = function(info, val)
								ShamanPower.opt.raidCDButtonHideFrame = (not val) or nil
								if ShamanPower.UpdateCallerButtonFrameStyle then
									ShamanPower:UpdateCallerButtonFrameStyle()
								end
							end
						},
						raidCDShowWarningIcon = {
							order = 3,
							name = "Show Warning Icon",
							desc = "Show raid warning icon when calling cooldowns",
							type = "toggle",
							width = 1.0,
							get = function(info)
								return ShamanPower.opt.raidCDShowWarningIcon ~= false
							end,
							set = function(info, val)
								ShamanPower.opt.raidCDShowWarningIcon = val
							end
						},
						raidCDShowWarningText = {
							order = 4,
							name = "Show Warning Text",
							desc = "Show raid warning text when calling cooldowns",
							type = "toggle",
							width = 1.0,
							get = function(info)
								return ShamanPower.opt.raidCDShowWarningText ~= false
							end,
							set = function(info, val)
								ShamanPower.opt.raidCDShowWarningText = val
							end
						},
						raidCDPlaySound = {
							order = 5,
							name = "Play Sound",
							desc = "Play sound when calling cooldowns",
							type = "toggle",
							width = 1.0,
							get = function(info)
								return ShamanPower.opt.raidCDPlaySound ~= false
							end,
							set = function(info, val)
								ShamanPower.opt.raidCDPlaySound = val
							end
						},
						raidCDSoundVolume = {
							order = 5.5,
							name = "Sound Volume",
							desc = "Volume for raid cooldown sounds",
							type = "range",
							min = 0,
							max = 100,
							step = 5,
							width = "full",
							disabled = function() return not ShamanPower.opt.raidCDPlaySound end,
							get = function(info)
								return ShamanPower.opt.raidCDSoundVolume or 100
							end,
							set = function(info, val)
								ShamanPower.opt.raidCDSoundVolume = val
							end
						},
						raidCDSoundVolume_testsound = {
							order = 5.5 + 0.05,
							type = "execute",
							name = "Test Sound",
							desc = "Play the selected sound at the selected volume.",
							width = 0.7,
							func = function()
								ShamanPower:PlaySoundWithVolume(8959, ShamanPower.opt.raidCDSoundVolume or 100, false)
							end,
						},
						raidCDSoundVolumeNote = {
							order = 5.6,
							type = "description",
							name = "|cff888888Must have Dialog sound at 100% for this slider to work.|r",
							width = "full",
						},
						raidCDShowButtonAnimation = {
							order = 6,
							name = "Show Button Animation",
							desc = "Show cooldown animation on caller buttons",
							type = "toggle",
							width = 1.0,
							get = function(info)
								return ShamanPower.opt.raidCDShowButtonAnimation ~= false
							end,
							set = function(info, val)
								ShamanPower.opt.raidCDShowButtonAnimation = val
							end
						},
					}
				},
				sprange_section = {
					order = 15,
					name = "|cff0070ddTotem Range Tracker|r",
					type = "group",
					args = {
						not_shown_note = {
							order = 0.05,
							type = "description",
							name = "|cffffa040The range overlay is hidden right now. It shows by itself only for a non-shaman grouped with a shaman; click this page's power dot or type /sprange to show it while you adjust these.|r",
							hidden = function() return not (ShamanPower.SPRangeLoaded and not (ShamanPower.spRangeFrame and ShamanPower.spRangeFrame:IsShown())) end,
						},
						module_missing_note = {
							order = 0.01,
							type = "description",
							name = "|cffffa040The range overlay module is not loaded. Enable ShamanPower [Totem Range]"
								.. " in the AddOns list and /reload to use its overlay controls."
								.. " Shaman minimap markers below work without that module.|r",
							hidden = function() return not (not ShamanPower.SPRangeLoaded) end,
						},
						sprange_desc = {
							order = 0,
							type = "description",
							-- a function: the minimap file loads after this one
							name = function() return "The optional range overlay shows non-shamans whether OTHER shamans' party buffs are in range."
								.. " It requires ShamanPower [Totem Range]."
								.. ((not ShamanPower.MinimapTotemsAvailable or not isShaman) and "\n" or "\n\nShamans can also show their own recorded"
								.. " totem drops on the minimap in the open world. Missing map calibration hides markers;"
								.. " instances never show them.\n") end,
						},
						minimapTotemMarkers = {
							hidden = function() return not ShamanPower.MinimapTotemsAvailable or not isShaman end,
							order = 0.1, type = "toggle", name = "Totem markers on the minimap", width = "full",
							get = function() return ShamanPower.opt.minimapTotemMarkers ~= false end,
							set = function(_, value) ShamanPower.opt.minimapTotemMarkers = value; ShamanPower:RefreshMinimapTotems() end,
						},
						minimapTotemRings = {
							hidden = function() return not ShamanPower.MinimapTotemsAvailable or not isShaman end,
							order = 0.2, type = "toggle", name = "Estimated totem radius rings", width = "full",
							desc = "Uses the addon's range model, not guaranteed exact spell or talent-modified reach."
								.. " Unknown radii show only a pin. Relocated totems need a fresh drop.",
							get = function() return ShamanPower.opt.minimapTotemRings ~= false end,
							set = function(_, value) ShamanPower.opt.minimapTotemRings = value; ShamanPower:RefreshMinimapTotems() end,
						},
						minimapTotemPinSize = {
							hidden = function() return not ShamanPower.MinimapTotemsAvailable or not isShaman end,
							order = 0.3, type = "range", name = "Minimap totem pin size", min = 8, max = 28, step = 1,
							get = function() return ShamanPower.opt.minimapTotemPinSize or 14 end,
							set = function(_, value) ShamanPower.opt.minimapTotemPinSize = value; ShamanPower:RefreshMinimapTotems() end,
						},
						sprange_opacity = {
							order = 1,
							name = "Opacity",
							desc = "Adjust the opacity of the totem range overlay",
							type = "range",
							isPercent = true,
							width = 1.5,
							min = 0.2,
							max = 1.0,
							step = 0.1,
							get = function(info)
								return ShamanPower.opt.rangeTracker and ShamanPower.opt.rangeTracker.opacity or 1.0
							end,
							set = function(info, val)
								ShamanPower:EnsureProfileTable("rangeTracker")
								ShamanPower.opt.rangeTracker.opacity = val
								ShamanPower:UpdateSPRangeOpacity()
							end
						},
						sprange_icon_size = {
							order = 2,
							name = "Icon Size",
							desc = "Adjust the size of the totem range overlay icons",
							type = "range",
							width = 1.5,
							min = 20,
							max = 60,
							step = 4,
							get = function(info)
								return ShamanPower.opt.rangeTracker and ShamanPower.opt.rangeTracker.iconSize or 36
							end,
							set = function(info, val)
								ShamanPower:EnsureProfileTable("rangeTracker")
								ShamanPower.opt.rangeTracker.iconSize = val
								ShamanPower:UpdateSPRangeFrame()
							end
						},
						sprange_vertical = {
							order = 3,
							name = "Vertical Layout",
							desc = "Stack totem icons vertically instead of horizontally",
							type = "toggle",
							width = 1.0,
							get = function(info)
								return ShamanPower.opt.rangeTracker and ShamanPower.opt.rangeTracker.vertical or false
							end,
							set = function(info, val)
								ShamanPower:EnsureProfileTable("rangeTracker")
								ShamanPower.opt.rangeTracker.vertical = val
								ShamanPower:UpdateSPRangeFrame()
								ShamanPower:UpdateSPRangeBorder()
							end
						},
						sprange_hide_names = {
							order = 4,
							name = "Hide Names",
							desc = "Hide totem names below the icons",
							type = "toggle",
							width = 1.0,
							get = function(info)
								return ShamanPower.opt.rangeTracker and ShamanPower.opt.rangeTracker.hideNames or false
							end,
							set = function(info, val)
								ShamanPower:EnsureProfileTable("rangeTracker")
								ShamanPower.opt.rangeTracker.hideNames = val
								ShamanPower:UpdateSPRangeFrame()
							end
						},
						sprange_hide_border = {
							order = 5,
							name = "Hide Border",
							desc = "Hide the frame border and title on the totem range overlay",
							type = "toggle",
							width = 1.0,
							get = function(info)
								return ShamanPower.opt.rangeTracker and ShamanPower.opt.rangeTracker.hideBorder or false
							end,
							set = function(info, val)
								ShamanPower:EnsureProfileTable("rangeTracker")
								ShamanPower.opt.rangeTracker.hideBorder = val
								ShamanPower:UpdateSPRangeBorder()
							end
						},
					}
				},
				partybuff_section = {
					order = 14,
					name = "|cff0070ddParty Buff Tracker|r",
					type = "group",
					args = {
						module_missing_note = {
							order = 0.01,
							type = "description",
							name = "|cffffa040This module is not loaded, so nothing on this page does anything right now (toggles may even snap back). Enable the ShamanPower [Party Range] addon in the AddOns list and /reload.|r",
							hidden = function() return not (not ShamanPower.PartyRangeLoaded) end,
						},
						partybuff_engine_note = {
							order = 0.02,
							type = "description",
							name = "|cffffa040On this client the dots are drawn by the game engine from each party member's actual totem buff, so they stay right in combat and in instances. A red dot means that player is not carrying the buff; the numbers-only counter still guesses in combat.|r",
							hidden = function() return not (SPCompat and SPCompat.secretsRegime) end,
						},
						partybuff_desc = {
							order = 0,
							type = "description",
							name = "Shows which party members are in range of YOUR totems. Different from Totem Range Tracker which shows OTHER shamans' totems affecting you.\n\n|cffff8800Note:|r Requires the |cff00ff00ShamanPower [Party Totem Range]|r module to be enabled in your AddOns list.\n",
						},
						partybuff_display_mode = {
							order = 1,
							type = "select",
							name = "Display Mode",
							desc = "Choose how to display party member range information",
							width = 1.5,
							values = {
								["dots"] = "Dots Only",
								["numbers"] = "Numbers Only",
								["both"] = "Both Dots and Numbers",
								["none"] = "Disabled",
							},
							get = function(info)
								local showDots = ShamanPower.opt.showPartyRangeDots
								local showNumbers = ShamanPower.opt.rangeCounter and ShamanPower.opt.rangeCounter.enabled
								if showDots and showNumbers then return "both"
								elseif showDots then return "dots"
								elseif showNumbers then return "numbers"
								else return "none" end
							end,
							set = function(info, val)
								if not ShamanPower.opt.rangeCounter then
									ShamanPower.opt.rangeCounter = {}
								end
								if val == "dots" then
									ShamanPower.opt.showPartyRangeDots = true
									ShamanPower.opt.rangeCounter.enabled = false
								elseif val == "numbers" then
									ShamanPower.opt.showPartyRangeDots = false
									ShamanPower.opt.rangeCounter.enabled = true
								elseif val == "both" then
									ShamanPower.opt.showPartyRangeDots = true
									ShamanPower.opt.rangeCounter.enabled = true
								else
									ShamanPower.opt.showPartyRangeDots = false
									ShamanPower.opt.rangeCounter.enabled = false
								end
								ShamanPower:UpdatePartyRangeDots()
								ShamanPower:UpdateRangeCounters()
								ShamanPower:UpdatePartyDotPositions()   -- bars pad away from dots only while dots show
							end
						},
						partybuff_dot_position = {
							disabled = function(info) return (CompactOn()) and true or false end,
							hidden = function(info) return (not ShamanPower.opt.showPartyRangeDots) and true or false end,
							order = 1.5,
							type = "select",
							name = "Dot Position",
							desc = WithNotes("Where the party dots sit on each totem button. Rows suit a horizontal bar; columns suit a vertical bar.",
								CompactOn, "Compact style is on: party dots always sit at the far end of each line, so this is ignored."),
							width = 1.2,
							values = {
								["corners"] = "Icon Corners",
								["above"] = "Above Icon (row)",
								["below"] = "Below Icon (row)",
								["left"] = "Left of Icon (column)",
								["right"] = "Right of Icon (column)",
							},
							get = function(info)
								return ShamanPower.opt.partyDotPosition or "corners"
							end,
							set = function(info, val)
								ShamanPower.opt.partyDotPosition = val
								ShamanPower:UpdatePartyDotPositions()
							end
						},
						partybuff_dot_outline = {
							hidden = function(info) return (not ShamanPower.opt.showPartyRangeDots) and true or false end,
							order = 1.6,
							type = "toggle",
							name = "Dot Outline",
							desc = "Draw a thin dark ring under each dot so it stays visible on bright totem icons.",
							width = 0.9,
							get = function(info)
								return ShamanPower.opt.partyDotOutline ~= false
							end,
							set = function(info, val)
								ShamanPower.opt.partyDotOutline = val
								ShamanPower:UpdatePartyDotPositions()
							end
						},
						partybuff_dot_size = {
							hidden = function(info) return (not ShamanPower.opt.showPartyRangeDots) and true or false end,
							order = 1.7,
							type = "range",
							name = "Dot Size",
							min = 4, max = 10, step = 1,
							width = 0.9,
							get = function(info)
								return ShamanPower.opt.partyDotSize or 5
							end,
							set = function(info, val)
								ShamanPower.opt.partyDotSize = val
								ShamanPower:UpdatePartyDotPositions()
							end
						},
						partybuff_header_numbers = {
							order = 2,
							type = "header",
							name = "Number Counter Settings",
							hidden = function()
								return not (ShamanPower.opt.rangeCounter and ShamanPower.opt.rangeCounter.enabled)
							end,
						},
						partybuff_location = {
							order = 3,
							type = "select",
							name = "Counter Location",
							desc = "Where to display the range counter numbers",
							width = 1.5,
							hidden = function()
								return not (ShamanPower.opt.rangeCounter and ShamanPower.opt.rangeCounter.enabled)
							end,
							values = {
								["icon"] = "On Totem Icon",
								["unlocked"] = "Separate Movable Frame",
							},
							get = function(info)
								return (ShamanPower.opt.rangeCounter and ShamanPower.opt.rangeCounter.location) or "icon"
							end,
							set = function(info, val)
								if not ShamanPower.opt.rangeCounter then
									ShamanPower.opt.rangeCounter = {}
								end
								ShamanPower.opt.rangeCounter.location = val
								ShamanPower:UpdateRangeCounters()
							end
						},
						partybuff_move_counters = {
							order = 3.05,
							type = "execute",
							name = "Move the Counter Frames",
							desc = "Unlocks just the four counter frames: drag their boxes where you want them (over your totem bar, wherever), then press Done to come back here.",
							width = 1.4,
							hidden = function()
								local rc = ShamanPower.opt.rangeCounter
								return not (rc and rc.enabled and rc.location == "unlocked" and ShamanPower.UnlockModuleFrames)
							end,
							func = function() ShamanPower:UnlockModuleFrames("partyrange") end,
						},
						partybuff_move_counters_note = {
							order = 3.06,
							type = "description",
							name = "|cffffa040Separate frames start wherever they last were; use the button to place them.|r",
							hidden = function()
								local rc = ShamanPower.opt.rangeCounter
								return not (rc and rc.enabled and rc.location == "unlocked")
							end,
						},
						partybuff_colors = {
							order = 4,
							type = "toggle",
							name = "Use Element Colors",
							desc = "Color the numbers by element (Green=Earth, Red=Fire, Blue=Water, White=Air)",
							width = 1.5,
							hidden = function()
								return not (ShamanPower.opt.rangeCounter and ShamanPower.opt.rangeCounter.enabled)
							end,
							get = function(info)
								return ShamanPower.opt.rangeCounter and ShamanPower.opt.rangeCounter.useElementColors ~= false
							end,
							set = function(info, val)
								if not ShamanPower.opt.rangeCounter then
									ShamanPower.opt.rangeCounter = {}
								end
								ShamanPower.opt.rangeCounter.useElementColors = val
								ShamanPower:UpdateRangeCounters()
							end
						},
						partybuff_fontsize = {
							order = 5,
							type = "range",
							name = "Font Size",
							desc = "Size of the counter number",
							min = 8, max = 32, step = 1,
							width = 1.5,
							hidden = function()
								return not (ShamanPower.opt.rangeCounter and ShamanPower.opt.rangeCounter.enabled)
							end,
							get = function(info)
								return (ShamanPower.opt.rangeCounter and ShamanPower.opt.rangeCounter.fontSize) or 14
							end,
							set = function(info, val)
								if not ShamanPower.opt.rangeCounter then
									ShamanPower.opt.rangeCounter = {}
								end
								ShamanPower.opt.rangeCounter.fontSize = val
								ShamanPower:UpdateRangeCounters()
							end
						},
						partybuff_header_frame = {
							order = 6,
							type = "header",
							name = "Unlocked Frame Settings",
							hidden = function()
								return not (ShamanPower.opt.rangeCounter and ShamanPower.opt.rangeCounter.enabled)
									or (ShamanPower.opt.rangeCounter and ShamanPower.opt.rangeCounter.location ~= "unlocked")
							end,
						},
						partybuff_locked = {
							order = 6.5,
							type = "toggle",
							name = "Lock Frames (Click-through)",
							desc = "Lock the frames so they can't be moved and won't block mouse clicks",
							width = 1.5,
							hidden = function()
								return not (ShamanPower.opt.rangeCounter and ShamanPower.opt.rangeCounter.enabled)
									or (ShamanPower.opt.rangeCounter and ShamanPower.opt.rangeCounter.location ~= "unlocked")
							end,
							get = function(info)
								return ShamanPower.opt.rangeCounter and ShamanPower.opt.rangeCounter.locked
							end,
							set = function(info, val)
								if not ShamanPower.opt.rangeCounter then
									ShamanPower.opt.rangeCounter = {}
								end
								ShamanPower.opt.rangeCounter.locked = val
								ShamanPower:UpdateRangeCounterLock()
							end
						},
						partybuff_hide_frame = {
							order = 7,
							type = "toggle",
							name = "Hide Frame Background",
							desc = "Hide the frame border/background, showing only the number",
							width = 1.5,
							hidden = function()
								return not (ShamanPower.opt.rangeCounter and ShamanPower.opt.rangeCounter.enabled)
									or (ShamanPower.opt.rangeCounter and ShamanPower.opt.rangeCounter.location ~= "unlocked")
							end,
							get = function(info)
								return ShamanPower.opt.rangeCounter and ShamanPower.opt.rangeCounter.hideFrame
							end,
							set = function(info, val)
								if not ShamanPower.opt.rangeCounter then
									ShamanPower.opt.rangeCounter = {}
								end
								ShamanPower.opt.rangeCounter.hideFrame = val
								ShamanPower:UpdateRangeCounterFrameStyle()
							end
						},
						partybuff_hide_label = {
							order = 8,
							type = "toggle",
							name = "Hide Element Label",
							desc = "Hide the element name below the counter (Earth, Fire, Water, Air)",
							width = 1.5,
							hidden = function()
								return not (ShamanPower.opt.rangeCounter and ShamanPower.opt.rangeCounter.enabled)
									or (ShamanPower.opt.rangeCounter and ShamanPower.opt.rangeCounter.location ~= "unlocked")
							end,
							get = function(info)
								return ShamanPower.opt.rangeCounter and ShamanPower.opt.rangeCounter.hideLabel
							end,
							set = function(info, val)
								if not ShamanPower.opt.rangeCounter then
									ShamanPower.opt.rangeCounter = {}
								end
								ShamanPower.opt.rangeCounter.hideLabel = val
								ShamanPower:UpdateRangeCounterFrameStyle()
							end
						},
						partybuff_scale = {
							order = 9,
							type = "range",
							isPercent = true,
							name = "Frame Scale",
							desc = "Scale of the unlocked counter frames",
							min = 0.5, max = 3.0, step = 0.1,
							width = 1.5,
							hidden = function()
								return not (ShamanPower.opt.rangeCounter and ShamanPower.opt.rangeCounter.enabled)
									or (ShamanPower.opt.rangeCounter and ShamanPower.opt.rangeCounter.location ~= "unlocked")
							end,
							get = function(info)
								return (ShamanPower.opt.rangeCounter and ShamanPower.opt.rangeCounter.scale) or 1.0
							end,
							set = function(info, val)
								if not ShamanPower.opt.rangeCounter then
									ShamanPower.opt.rangeCounter = {}
								end
								ShamanPower.opt.rangeCounter.scale = val
								for element = 1, 4 do
									local frame = ShamanPower.rangeCounterFrames[element]
									if frame then
										ShamanPower:SetFrameScaleKeepCenter(frame, val)
										ShamanPower:SaveRangeCounterPosition(element)
									end
								end
							end
						},
						partybuff_opacity = {
							order = 10,
							type = "range",
							name = "Frame Opacity",
							desc = "Opacity of the unlocked counter frames",
							min = 0.1, max = 1, step = 0.05, isPercent = true,
							width = 1.5,
							hidden = function()
								return not (ShamanPower.opt.rangeCounter and ShamanPower.opt.rangeCounter.enabled)
									or (ShamanPower.opt.rangeCounter and ShamanPower.opt.rangeCounter.location ~= "unlocked")
							end,
							get = function(info)
								return (ShamanPower.opt.rangeCounter and ShamanPower.opt.rangeCounter.opacity) or 1.0
							end,
							set = function(info, val)
								if not ShamanPower.opt.rangeCounter then
									ShamanPower.opt.rangeCounter = {}
								end
								ShamanPower.opt.rangeCounter.opacity = val
								for element = 1, 4 do
									if ShamanPower.rangeCounterFrames[element] then
										ShamanPower.rangeCounterFrames[element]:SetAlpha(val)
									end
								end
							end
						},
						coverage_header = {
							order = 11.5,
							type = "header",
							name = "Totem Coverage List",
							hidden = function() return not (ShamanPower.CoverageAvailable and ShamanPower:CoverageAvailable()) end,
						},
						coverage_desc = {
							order = 11.51,
							type = "description",
							name = "The reverse of the Totem Range Tracker: for every totem you have down, the names of party members who are NOT getting its buff, in red. The names are drawn by the game engine straight from their buffs, so they hold in combat and in instances; the cell's border and count use the same distance model as the counters.",
							hidden = function() return not (ShamanPower.CoverageAvailable and ShamanPower:CoverageAvailable()) end,
						},
						coverage_enabled = {
							order = 11.52,
							type = "toggle",
							name = "Show the Coverage List",
							width = 1.0,
							hidden = function() return not (ShamanPower.CoverageAvailable and ShamanPower:CoverageAvailable()) end,
							get = function() return ShamanPower.opt.coverage and ShamanPower.opt.coverage.enabled or false end,
							set = function(_, val)
								ShamanPower.opt.coverage = ShamanPower.opt.coverage or {}
								ShamanPower.opt.coverage.enabled = val
								if ShamanPower.RebuildCoverage then ShamanPower:RebuildCoverage() end
								if ShamanPower.UpdatePartyRangeDots then ShamanPower:UpdatePartyRangeDots() end
							end,
						},
						coverage_hide_covered = {
							order = 11.53,
							type = "toggle",
							name = "Hide a Totem Once Everyone Is in Range",
							desc = "When the whole party is getting a totem's buff, its cell disappears; it comes back as soon as someone is out of range. In the open world that is judged from real distances, in and out of combat. In dungeon combat the game gives addons no positions, so every totem stays listed and the names themselves show who is covered.",
							width = 1.0,
							hidden = function() return not (ShamanPower.CoverageAvailable and ShamanPower:CoverageAvailable()) end,
							disabled = function() return not (ShamanPower.opt.coverage and ShamanPower.opt.coverage.enabled) end,
							get = function() return not (ShamanPower.opt.coverage and ShamanPower.opt.coverage.hideWhenCovered == false) end,
							set = function(_, val)
								ShamanPower.opt.coverage = ShamanPower.opt.coverage or {}
								ShamanPower.opt.coverage.hideWhenCovered = val
								if ShamanPower.UpdateCoverage then ShamanPower:UpdateCoverage() end
							end,
						},
						coverage_icon_size = {
							order = 11.535,
							type = "range",
							name = "Icon Size",
							min = 20, max = 60, step = 4,
							width = 1.0,
							hidden = function() return not (ShamanPower.CoverageAvailable and ShamanPower:CoverageAvailable()) end,
							disabled = function() return not (ShamanPower.opt.coverage and ShamanPower.opt.coverage.enabled) end,
							get = function() return (ShamanPower.opt.coverage and ShamanPower.opt.coverage.iconSize) or 36 end,
							set = function(_, val)
								ShamanPower.opt.coverage = ShamanPower.opt.coverage or {}
								ShamanPower.opt.coverage.iconSize = val
								if ShamanPower.UpdateCoverageLayout then ShamanPower:UpdateCoverageLayout() end
							end,
						},
						coverage_font = {
							order = 11.54,
							type = "range",
							name = "Name Size",
							min = 7, max = 14, step = 1,
							width = 1.0,
							hidden = function() return not (ShamanPower.CoverageAvailable and ShamanPower:CoverageAvailable()) end,
							disabled = function() return not (ShamanPower.opt.coverage and ShamanPower.opt.coverage.enabled) end,
							get = function() return (ShamanPower.opt.coverage and ShamanPower.opt.coverage.fontSize) or 9 end,
							set = function(_, val)
								ShamanPower.opt.coverage = ShamanPower.opt.coverage or {}
								ShamanPower.opt.coverage.fontSize = val
								if ShamanPower.UpdateCoverageLayout then ShamanPower:UpdateCoverageLayout() end
							end,
						},
						coverage_free = {
							order = 11.5405,
							type = "toggle",
							name = "Place Each Totem Freely",
							desc = "Every watched totem gets a cell of its own on the screen, with its own spot and size (below). Use Move the Coverage List to drag them, or ALT+drag a cell. Off: one cell per element, together in a row or column.",
							width = "full",
							hidden = function() return not (ShamanPower.CoverageAvailable and ShamanPower:CoverageAvailable()) end,
							disabled = function() return not (ShamanPower.opt.coverage and ShamanPower.opt.coverage.enabled) end,
							get = function() return ShamanPower.opt.coverage and ShamanPower.opt.coverage.freeCells or false end,
							set = function(_, val)
								ShamanPower.opt.coverage = ShamanPower.opt.coverage or {}
								ShamanPower.opt.coverage.freeCells = val
								if ShamanPower.UpdateCoverageLayout then ShamanPower:UpdateCoverageLayout() end
							end,
						},
						coverage_sizes_desc = {
							order = 11.5406,
							type = "description",
							name = "Each watched totem's cell has a size of its own while placed freely:",
							hidden = function() return not (ShamanPower.CoverageAvailable and ShamanPower:CoverageAvailable() and ShamanPower.opt.coverage and ShamanPower.opt.coverage.freeCells) end,
						},
						coverage_size_1_1 = {
							order = 11.5411,
							type = "range",
							name = function()
								local base = ShamanPower.TotemBuffSpellIDs and ShamanPower.TotemBuffSpellIDs[1] and ShamanPower.TotemBuffSpellIDs[1][1]
								return ((base and GetSpellInfo(base)) or "Strength of Earth") .. " Size"
							end,
							min = 20, max = 80, step = 4,
							width = 1.0,
							hidden = function()
								local co = ShamanPower.opt.coverage
								if not (ShamanPower.CoverageAvailable and ShamanPower:CoverageAvailable() and co and co.freeCells) then return true end
								if not (ShamanPower.CoverageWatches and ShamanPower:CoverageWatches(1, 1)) then return true end
								local totem = ShamanPower.GetTotemSpell and ShamanPower:GetTotemSpell(1, 1)
								return not (totem and SPCompat and SPCompat.SpellExists and SPCompat.SpellExists(totem))
							end,
							disabled = function() return not (ShamanPower.opt.coverage and ShamanPower.opt.coverage.enabled) end,
							get = function()
								local co = ShamanPower.opt.coverage or {}
								local c = co.cells and co.cells[101]
								return (c and c.iconSize) or co.iconSize or 36
							end,
							set = function(_, val)
								local co = ShamanPower.opt.coverage; co.cells = co.cells or {}; co.cells[101] = co.cells[101] or {}
								co.cells[101].iconSize = val
								if ShamanPower.UpdateCoverageLayout then ShamanPower:UpdateCoverageLayout() end
							end,
						},
						coverage_size_1_2 = {
							order = 11.5416,
							type = "range",
							name = function()
								local base = ShamanPower.TotemBuffSpellIDs and ShamanPower.TotemBuffSpellIDs[1] and ShamanPower.TotemBuffSpellIDs[1][2]
								return ((base and GetSpellInfo(base)) or "Stoneskin") .. " Size"
							end,
							min = 20, max = 80, step = 4,
							width = 1.0,
							hidden = function()
								local co = ShamanPower.opt.coverage
								if not (ShamanPower.CoverageAvailable and ShamanPower:CoverageAvailable() and co and co.freeCells) then return true end
								if not (ShamanPower.CoverageWatches and ShamanPower:CoverageWatches(1, 2)) then return true end
								local totem = ShamanPower.GetTotemSpell and ShamanPower:GetTotemSpell(1, 2)
								return not (totem and SPCompat and SPCompat.SpellExists and SPCompat.SpellExists(totem))
							end,
							disabled = function() return not (ShamanPower.opt.coverage and ShamanPower.opt.coverage.enabled) end,
							get = function()
								local co = ShamanPower.opt.coverage or {}
								local c = co.cells and co.cells[102]
								return (c and c.iconSize) or co.iconSize or 36
							end,
							set = function(_, val)
								local co = ShamanPower.opt.coverage; co.cells = co.cells or {}; co.cells[102] = co.cells[102] or {}
								co.cells[102].iconSize = val
								if ShamanPower.UpdateCoverageLayout then ShamanPower:UpdateCoverageLayout() end
							end,
						},
						coverage_size_2_1 = {
							order = 11.5421,
							type = "range",
							name = function()
								local base = ShamanPower.TotemBuffSpellIDs and ShamanPower.TotemBuffSpellIDs[2] and ShamanPower.TotemBuffSpellIDs[2][1]
								return ((base and GetSpellInfo(base)) or "Totem of Wrath") .. " Size"
							end,
							min = 20, max = 80, step = 4,
							width = 1.0,
							hidden = function()
								local co = ShamanPower.opt.coverage
								if not (ShamanPower.CoverageAvailable and ShamanPower:CoverageAvailable() and co and co.freeCells) then return true end
								if not (ShamanPower.CoverageWatches and ShamanPower:CoverageWatches(2, 1)) then return true end
								local totem = ShamanPower.GetTotemSpell and ShamanPower:GetTotemSpell(2, 1)
								return not (totem and SPCompat and SPCompat.SpellExists and SPCompat.SpellExists(totem))
							end,
							disabled = function() return not (ShamanPower.opt.coverage and ShamanPower.opt.coverage.enabled) end,
							get = function()
								local co = ShamanPower.opt.coverage or {}
								local c = co.cells and co.cells[201]
								return (c and c.iconSize) or co.iconSize or 36
							end,
							set = function(_, val)
								local co = ShamanPower.opt.coverage; co.cells = co.cells or {}; co.cells[201] = co.cells[201] or {}
								co.cells[201].iconSize = val
								if ShamanPower.UpdateCoverageLayout then ShamanPower:UpdateCoverageLayout() end
							end,
						},
						coverage_size_2_5 = {
							order = 11.5426,
							type = "range",
							name = function()
								local base = ShamanPower.TotemBuffSpellIDs and ShamanPower.TotemBuffSpellIDs[2] and ShamanPower.TotemBuffSpellIDs[2][5]
								return ((base and GetSpellInfo(base)) or "Flametongue Totem") .. " Size"
							end,
							min = 20, max = 80, step = 4,
							width = 1.0,
							hidden = function()
								local co = ShamanPower.opt.coverage
								if not (ShamanPower.CoverageAvailable and ShamanPower:CoverageAvailable() and co and co.freeCells) then return true end
								if not (ShamanPower.CoverageWatches and ShamanPower:CoverageWatches(2, 5)) then return true end
								local totem = ShamanPower.GetTotemSpell and ShamanPower:GetTotemSpell(2, 5)
								return not (totem and SPCompat and SPCompat.SpellExists and SPCompat.SpellExists(totem))
							end,
							disabled = function() return not (ShamanPower.opt.coverage and ShamanPower.opt.coverage.enabled) end,
							get = function()
								local co = ShamanPower.opt.coverage or {}
								local c = co.cells and co.cells[205]
								return (c and c.iconSize) or co.iconSize or 36
							end,
							set = function(_, val)
								local co = ShamanPower.opt.coverage; co.cells = co.cells or {}; co.cells[205] = co.cells[205] or {}
								co.cells[205].iconSize = val
								if ShamanPower.UpdateCoverageLayout then ShamanPower:UpdateCoverageLayout() end
							end,
						},
						coverage_size_2_6 = {
							order = 11.5431,
							type = "range",
							name = function()
								local base = ShamanPower.TotemBuffSpellIDs and ShamanPower.TotemBuffSpellIDs[2] and ShamanPower.TotemBuffSpellIDs[2][6]
								return ((base and GetSpellInfo(base)) or "Frost Resistance") .. " Size"
							end,
							min = 20, max = 80, step = 4,
							width = 1.0,
							hidden = function()
								local co = ShamanPower.opt.coverage
								if not (ShamanPower.CoverageAvailable and ShamanPower:CoverageAvailable() and co and co.freeCells) then return true end
								if not (ShamanPower.CoverageWatches and ShamanPower:CoverageWatches(2, 6)) then return true end
								local totem = ShamanPower.GetTotemSpell and ShamanPower:GetTotemSpell(2, 6)
								return not (totem and SPCompat and SPCompat.SpellExists and SPCompat.SpellExists(totem))
							end,
							disabled = function() return not (ShamanPower.opt.coverage and ShamanPower.opt.coverage.enabled) end,
							get = function()
								local co = ShamanPower.opt.coverage or {}
								local c = co.cells and co.cells[206]
								return (c and c.iconSize) or co.iconSize or 36
							end,
							set = function(_, val)
								local co = ShamanPower.opt.coverage; co.cells = co.cells or {}; co.cells[206] = co.cells[206] or {}
								co.cells[206].iconSize = val
								if ShamanPower.UpdateCoverageLayout then ShamanPower:UpdateCoverageLayout() end
							end,
						},
						coverage_size_3_1 = {
							order = 11.5436,
							type = "range",
							name = function()
								local base = ShamanPower.TotemBuffSpellIDs and ShamanPower.TotemBuffSpellIDs[3] and ShamanPower.TotemBuffSpellIDs[3][1]
								return ((base and GetSpellInfo(base)) or "Mana Spring") .. " Size"
							end,
							min = 20, max = 80, step = 4,
							width = 1.0,
							hidden = function()
								local co = ShamanPower.opt.coverage
								if not (ShamanPower.CoverageAvailable and ShamanPower:CoverageAvailable() and co and co.freeCells) then return true end
								if not (ShamanPower.CoverageWatches and ShamanPower:CoverageWatches(3, 1)) then return true end
								local totem = ShamanPower.GetTotemSpell and ShamanPower:GetTotemSpell(3, 1)
								return not (totem and SPCompat and SPCompat.SpellExists and SPCompat.SpellExists(totem))
							end,
							disabled = function() return not (ShamanPower.opt.coverage and ShamanPower.opt.coverage.enabled) end,
							get = function()
								local co = ShamanPower.opt.coverage or {}
								local c = co.cells and co.cells[301]
								return (c and c.iconSize) or co.iconSize or 36
							end,
							set = function(_, val)
								local co = ShamanPower.opt.coverage; co.cells = co.cells or {}; co.cells[301] = co.cells[301] or {}
								co.cells[301].iconSize = val
								if ShamanPower.UpdateCoverageLayout then ShamanPower:UpdateCoverageLayout() end
							end,
						},
						coverage_size_3_2 = {
							order = 11.5441,
							type = "range",
							name = function()
								local base = ShamanPower.TotemBuffSpellIDs and ShamanPower.TotemBuffSpellIDs[3] and ShamanPower.TotemBuffSpellIDs[3][2]
								return ((base and GetSpellInfo(base)) or "Healing Stream") .. " Size"
							end,
							min = 20, max = 80, step = 4,
							width = 1.0,
							hidden = function()
								local co = ShamanPower.opt.coverage
								if not (ShamanPower.CoverageAvailable and ShamanPower:CoverageAvailable() and co and co.freeCells) then return true end
								if not (ShamanPower.CoverageWatches and ShamanPower:CoverageWatches(3, 2)) then return true end
								local totem = ShamanPower.GetTotemSpell and ShamanPower:GetTotemSpell(3, 2)
								return not (totem and SPCompat and SPCompat.SpellExists and SPCompat.SpellExists(totem))
							end,
							disabled = function() return not (ShamanPower.opt.coverage and ShamanPower.opt.coverage.enabled) end,
							get = function()
								local co = ShamanPower.opt.coverage or {}
								local c = co.cells and co.cells[302]
								return (c and c.iconSize) or co.iconSize or 36
							end,
							set = function(_, val)
								local co = ShamanPower.opt.coverage; co.cells = co.cells or {}; co.cells[302] = co.cells[302] or {}
								co.cells[302].iconSize = val
								if ShamanPower.UpdateCoverageLayout then ShamanPower:UpdateCoverageLayout() end
							end,
						},
						coverage_size_3_3 = {
							order = 11.5446,
							type = "range",
							name = function()
								local base = ShamanPower.TotemBuffSpellIDs and ShamanPower.TotemBuffSpellIDs[3] and ShamanPower.TotemBuffSpellIDs[3][3]
								return ((base and GetSpellInfo(base)) or "Mana Tide") .. " Size"
							end,
							min = 20, max = 80, step = 4,
							width = 1.0,
							hidden = function()
								local co = ShamanPower.opt.coverage
								if not (ShamanPower.CoverageAvailable and ShamanPower:CoverageAvailable() and co and co.freeCells) then return true end
								if not (ShamanPower.CoverageWatches and ShamanPower:CoverageWatches(3, 3)) then return true end
								local totem = ShamanPower.GetTotemSpell and ShamanPower:GetTotemSpell(3, 3)
								return not (totem and SPCompat and SPCompat.SpellExists and SPCompat.SpellExists(totem))
							end,
							disabled = function() return not (ShamanPower.opt.coverage and ShamanPower.opt.coverage.enabled) end,
							get = function()
								local co = ShamanPower.opt.coverage or {}
								local c = co.cells and co.cells[303]
								return (c and c.iconSize) or co.iconSize or 36
							end,
							set = function(_, val)
								local co = ShamanPower.opt.coverage; co.cells = co.cells or {}; co.cells[303] = co.cells[303] or {}
								co.cells[303].iconSize = val
								if ShamanPower.UpdateCoverageLayout then ShamanPower:UpdateCoverageLayout() end
							end,
						},
						coverage_size_3_6 = {
							order = 11.5451,
							type = "range",
							name = function()
								local base = ShamanPower.TotemBuffSpellIDs and ShamanPower.TotemBuffSpellIDs[3] and ShamanPower.TotemBuffSpellIDs[3][6]
								return ((base and GetSpellInfo(base)) or "Fire Resistance") .. " Size"
							end,
							min = 20, max = 80, step = 4,
							width = 1.0,
							hidden = function()
								local co = ShamanPower.opt.coverage
								if not (ShamanPower.CoverageAvailable and ShamanPower:CoverageAvailable() and co and co.freeCells) then return true end
								if not (ShamanPower.CoverageWatches and ShamanPower:CoverageWatches(3, 6)) then return true end
								local totem = ShamanPower.GetTotemSpell and ShamanPower:GetTotemSpell(3, 6)
								return not (totem and SPCompat and SPCompat.SpellExists and SPCompat.SpellExists(totem))
							end,
							disabled = function() return not (ShamanPower.opt.coverage and ShamanPower.opt.coverage.enabled) end,
							get = function()
								local co = ShamanPower.opt.coverage or {}
								local c = co.cells and co.cells[306]
								return (c and c.iconSize) or co.iconSize or 36
							end,
							set = function(_, val)
								local co = ShamanPower.opt.coverage; co.cells = co.cells or {}; co.cells[306] = co.cells[306] or {}
								co.cells[306].iconSize = val
								if ShamanPower.UpdateCoverageLayout then ShamanPower:UpdateCoverageLayout() end
							end,
						},
						coverage_size_4_1 = {
							order = 11.5456,
							type = "range",
							name = function()
								local base = ShamanPower.TotemBuffSpellIDs and ShamanPower.TotemBuffSpellIDs[4] and ShamanPower.TotemBuffSpellIDs[4][1]
								return ((base and GetSpellInfo(base)) or "Windfury Totem") .. " Size"
							end,
							min = 20, max = 80, step = 4,
							width = 1.0,
							hidden = function()
								local co = ShamanPower.opt.coverage
								if not (ShamanPower.CoverageAvailable and ShamanPower:CoverageAvailable() and co and co.freeCells) then return true end
								if not (ShamanPower.CoverageWatches and ShamanPower:CoverageWatches(4, 1)) then return true end
								local totem = ShamanPower.GetTotemSpell and ShamanPower:GetTotemSpell(4, 1)
								return not (totem and SPCompat and SPCompat.SpellExists and SPCompat.SpellExists(totem))
							end,
							disabled = function() return not (ShamanPower.opt.coverage and ShamanPower.opt.coverage.enabled) end,
							get = function()
								local co = ShamanPower.opt.coverage or {}
								local c = co.cells and co.cells[401]
								return (c and c.iconSize) or co.iconSize or 36
							end,
							set = function(_, val)
								local co = ShamanPower.opt.coverage; co.cells = co.cells or {}; co.cells[401] = co.cells[401] or {}
								co.cells[401].iconSize = val
								if ShamanPower.UpdateCoverageLayout then ShamanPower:UpdateCoverageLayout() end
							end,
						},
						coverage_size_4_2 = {
							order = 11.5461,
							type = "range",
							name = function()
								local base = ShamanPower.TotemBuffSpellIDs and ShamanPower.TotemBuffSpellIDs[4] and ShamanPower.TotemBuffSpellIDs[4][2]
								return ((base and GetSpellInfo(base)) or "Grace of Air") .. " Size"
							end,
							min = 20, max = 80, step = 4,
							width = 1.0,
							hidden = function()
								local co = ShamanPower.opt.coverage
								if not (ShamanPower.CoverageAvailable and ShamanPower:CoverageAvailable() and co and co.freeCells) then return true end
								if not (ShamanPower.CoverageWatches and ShamanPower:CoverageWatches(4, 2)) then return true end
								local totem = ShamanPower.GetTotemSpell and ShamanPower:GetTotemSpell(4, 2)
								return not (totem and SPCompat and SPCompat.SpellExists and SPCompat.SpellExists(totem))
							end,
							disabled = function() return not (ShamanPower.opt.coverage and ShamanPower.opt.coverage.enabled) end,
							get = function()
								local co = ShamanPower.opt.coverage or {}
								local c = co.cells and co.cells[402]
								return (c and c.iconSize) or co.iconSize or 36
							end,
							set = function(_, val)
								local co = ShamanPower.opt.coverage; co.cells = co.cells or {}; co.cells[402] = co.cells[402] or {}
								co.cells[402].iconSize = val
								if ShamanPower.UpdateCoverageLayout then ShamanPower:UpdateCoverageLayout() end
							end,
						},
						coverage_size_4_3 = {
							order = 11.5466,
							type = "range",
							name = function()
								local base = ShamanPower.TotemBuffSpellIDs and ShamanPower.TotemBuffSpellIDs[4] and ShamanPower.TotemBuffSpellIDs[4][3]
								return ((base and GetSpellInfo(base)) or "Wrath of Air") .. " Size"
							end,
							min = 20, max = 80, step = 4,
							width = 1.0,
							hidden = function()
								local co = ShamanPower.opt.coverage
								if not (ShamanPower.CoverageAvailable and ShamanPower:CoverageAvailable() and co and co.freeCells) then return true end
								if not (ShamanPower.CoverageWatches and ShamanPower:CoverageWatches(4, 3)) then return true end
								local totem = ShamanPower.GetTotemSpell and ShamanPower:GetTotemSpell(4, 3)
								return not (totem and SPCompat and SPCompat.SpellExists and SPCompat.SpellExists(totem))
							end,
							disabled = function() return not (ShamanPower.opt.coverage and ShamanPower.opt.coverage.enabled) end,
							get = function()
								local co = ShamanPower.opt.coverage or {}
								local c = co.cells and co.cells[403]
								return (c and c.iconSize) or co.iconSize or 36
							end,
							set = function(_, val)
								local co = ShamanPower.opt.coverage; co.cells = co.cells or {}; co.cells[403] = co.cells[403] or {}
								co.cells[403].iconSize = val
								if ShamanPower.UpdateCoverageLayout then ShamanPower:UpdateCoverageLayout() end
							end,
						},
						coverage_size_4_4 = {
							order = 11.5471,
							type = "range",
							name = function()
								local base = ShamanPower.TotemBuffSpellIDs and ShamanPower.TotemBuffSpellIDs[4] and ShamanPower.TotemBuffSpellIDs[4][4]
								return ((base and GetSpellInfo(base)) or "Tranquil Air") .. " Size"
							end,
							min = 20, max = 80, step = 4,
							width = 1.0,
							hidden = function()
								local co = ShamanPower.opt.coverage
								if not (ShamanPower.CoverageAvailable and ShamanPower:CoverageAvailable() and co and co.freeCells) then return true end
								if not (ShamanPower.CoverageWatches and ShamanPower:CoverageWatches(4, 4)) then return true end
								local totem = ShamanPower.GetTotemSpell and ShamanPower:GetTotemSpell(4, 4)
								return not (totem and SPCompat and SPCompat.SpellExists and SPCompat.SpellExists(totem))
							end,
							disabled = function() return not (ShamanPower.opt.coverage and ShamanPower.opt.coverage.enabled) end,
							get = function()
								local co = ShamanPower.opt.coverage or {}
								local c = co.cells and co.cells[404]
								return (c and c.iconSize) or co.iconSize or 36
							end,
							set = function(_, val)
								local co = ShamanPower.opt.coverage; co.cells = co.cells or {}; co.cells[404] = co.cells[404] or {}
								co.cells[404].iconSize = val
								if ShamanPower.UpdateCoverageLayout then ShamanPower:UpdateCoverageLayout() end
							end,
						},
						coverage_size_4_6 = {
							order = 11.5476,
							type = "range",
							name = function()
								local base = ShamanPower.TotemBuffSpellIDs and ShamanPower.TotemBuffSpellIDs[4] and ShamanPower.TotemBuffSpellIDs[4][6]
								return ((base and GetSpellInfo(base)) or "Nature Resistance") .. " Size"
							end,
							min = 20, max = 80, step = 4,
							width = 1.0,
							hidden = function()
								local co = ShamanPower.opt.coverage
								if not (ShamanPower.CoverageAvailable and ShamanPower:CoverageAvailable() and co and co.freeCells) then return true end
								if not (ShamanPower.CoverageWatches and ShamanPower:CoverageWatches(4, 6)) then return true end
								local totem = ShamanPower.GetTotemSpell and ShamanPower:GetTotemSpell(4, 6)
								return not (totem and SPCompat and SPCompat.SpellExists and SPCompat.SpellExists(totem))
							end,
							disabled = function() return not (ShamanPower.opt.coverage and ShamanPower.opt.coverage.enabled) end,
							get = function()
								local co = ShamanPower.opt.coverage or {}
								local c = co.cells and co.cells[406]
								return (c and c.iconSize) or co.iconSize or 36
							end,
							set = function(_, val)
								local co = ShamanPower.opt.coverage; co.cells = co.cells or {}; co.cells[406] = co.cells[406] or {}
								co.cells[406].iconSize = val
								if ShamanPower.UpdateCoverageLayout then ShamanPower:UpdateCoverageLayout() end
							end,
						},
						coverage_size_4_7 = {
							order = 11.5481,
							type = "range",
							name = function()
								local base = ShamanPower.TotemBuffSpellIDs and ShamanPower.TotemBuffSpellIDs[4] and ShamanPower.TotemBuffSpellIDs[4][7]
								return ((base and GetSpellInfo(base)) or "Windwall") .. " Size"
							end,
							min = 20, max = 80, step = 4,
							width = 1.0,
							hidden = function()
								local co = ShamanPower.opt.coverage
								if not (ShamanPower.CoverageAvailable and ShamanPower:CoverageAvailable() and co and co.freeCells) then return true end
								if not (ShamanPower.CoverageWatches and ShamanPower:CoverageWatches(4, 7)) then return true end
								local totem = ShamanPower.GetTotemSpell and ShamanPower:GetTotemSpell(4, 7)
								return not (totem and SPCompat and SPCompat.SpellExists and SPCompat.SpellExists(totem))
							end,
							disabled = function() return not (ShamanPower.opt.coverage and ShamanPower.opt.coverage.enabled) end,
							get = function()
								local co = ShamanPower.opt.coverage or {}
								local c = co.cells and co.cells[407]
								return (c and c.iconSize) or co.iconSize or 36
							end,
							set = function(_, val)
								local co = ShamanPower.opt.coverage; co.cells = co.cells or {}; co.cells[407] = co.cells[407] or {}
								co.cells[407].iconSize = val
								if ShamanPower.UpdateCoverageLayout then ShamanPower:UpdateCoverageLayout() end
							end,
						},
						coverage_vertical = {
							order = 11.541,
							type = "toggle",
							name = "Vertical Layout",
							desc = "Stack the totem cells instead of a row (when they are not placed freely).",
							width = 1.0,
							hidden = function() return not (ShamanPower.CoverageAvailable and ShamanPower:CoverageAvailable()) end,
							disabled = function() return not (ShamanPower.opt.coverage and ShamanPower.opt.coverage.enabled) or (ShamanPower.opt.coverage and ShamanPower.opt.coverage.freeCells) end,
							get = function() return ShamanPower.opt.coverage and ShamanPower.opt.coverage.vertical or false end,
							set = function(_, val)
								ShamanPower.opt.coverage = ShamanPower.opt.coverage or {}
								ShamanPower.opt.coverage.vertical = val
								if ShamanPower.UpdateCoverageLayout then ShamanPower:UpdateCoverageLayout() end
							end,
						},
						coverage_hide_border = {
							order = 11.542,
							type = "toggle",
							name = "Hide Frame",
							desc = "Only the cells, no panel or title. ALT+drag to move, right-click to configure.",
							width = 1.0,
							hidden = function() return not (ShamanPower.CoverageAvailable and ShamanPower:CoverageAvailable()) end,
							disabled = function() return not (ShamanPower.opt.coverage and ShamanPower.opt.coverage.enabled) end,
							get = function() return ShamanPower.opt.coverage and ShamanPower.opt.coverage.hideBorder or false end,
							set = function(_, val)
								ShamanPower.opt.coverage = ShamanPower.opt.coverage or {}
								ShamanPower.opt.coverage.hideBorder = val
								if ShamanPower.UpdateCoverageBorder then ShamanPower:UpdateCoverageBorder() end
							end,
						},
						coverage_opacity = {
							order = 11.543,
							type = "range",
							name = "Opacity",
							min = 0.2, max = 1, step = 0.05, isPercent = true,
							width = 1.0,
							hidden = function() return not (ShamanPower.CoverageAvailable and ShamanPower:CoverageAvailable()) end,
							disabled = function() return not (ShamanPower.opt.coverage and ShamanPower.opt.coverage.enabled) end,
							get = function() return (ShamanPower.opt.coverage and ShamanPower.opt.coverage.opacity) or 1 end,
							set = function(_, val)
								ShamanPower.opt.coverage = ShamanPower.opt.coverage or {}
								ShamanPower.opt.coverage.opacity = val
								if ShamanPower.UpdateCoverageOpacity then ShamanPower:UpdateCoverageOpacity() end
							end,
						},
						coverage_watch_header = {
							order = 11.56,
							type = "header",
							name = "Totems To Watch",
							hidden = function() return not (ShamanPower.CoverageAvailable and ShamanPower:CoverageAvailable()) end,
						},
						coverage_watch_desc = {
							order = 11.561,
							type = "description",
							name = "A totem only gets a cell while it is watched. Turn off the ones you do not care about.",
							hidden = function() return not (ShamanPower.CoverageAvailable and ShamanPower:CoverageAvailable()) end,
						},
						coverage_watch_1_1 = {
							order = 11.5625,
							type = "toggle",
							name = function()
								local base = ShamanPower.TotemBuffSpellIDs and ShamanPower.TotemBuffSpellIDs[1] and ShamanPower.TotemBuffSpellIDs[1][1]
								return (base and GetSpellInfo(base)) or "Strength of Earth"
							end,
							width = 1.0,
							hidden = function()
								if not (ShamanPower.CoverageAvailable and ShamanPower:CoverageAvailable()) then return true end
								local base = ShamanPower.TotemBuffSpellIDs and ShamanPower.TotemBuffSpellIDs[1] and ShamanPower.TotemBuffSpellIDs[1][1]
								if not base then return true end
								local totem = ShamanPower.GetTotemSpell and ShamanPower:GetTotemSpell(1, 1)
								return not (totem and SPCompat and SPCompat.SpellExists and SPCompat.SpellExists(totem))   -- not on this client
							end,
							disabled = function() return not (ShamanPower.opt.coverage and ShamanPower.opt.coverage.enabled) end,
							get = function() return ShamanPower.CoverageWatches and ShamanPower:CoverageWatches(1, 1) end,
							set = function(_, val)
								local base = ShamanPower.TotemBuffSpellIDs[1][1]
								if base and ShamanPower.SetCoverageWatch then ShamanPower:SetCoverageWatch(base, val) end
							end,
						},
						coverage_watch_1_2 = {
							order = 11.563,
							type = "toggle",
							name = function()
								local base = ShamanPower.TotemBuffSpellIDs and ShamanPower.TotemBuffSpellIDs[1] and ShamanPower.TotemBuffSpellIDs[1][2]
								return (base and GetSpellInfo(base)) or "Stoneskin"
							end,
							width = 1.0,
							hidden = function()
								if not (ShamanPower.CoverageAvailable and ShamanPower:CoverageAvailable()) then return true end
								local base = ShamanPower.TotemBuffSpellIDs and ShamanPower.TotemBuffSpellIDs[1] and ShamanPower.TotemBuffSpellIDs[1][2]
								if not base then return true end
								local totem = ShamanPower.GetTotemSpell and ShamanPower:GetTotemSpell(1, 2)
								return not (totem and SPCompat and SPCompat.SpellExists and SPCompat.SpellExists(totem))   -- not on this client
							end,
							disabled = function() return not (ShamanPower.opt.coverage and ShamanPower.opt.coverage.enabled) end,
							get = function() return ShamanPower.CoverageWatches and ShamanPower:CoverageWatches(1, 2) end,
							set = function(_, val)
								local base = ShamanPower.TotemBuffSpellIDs[1][2]
								if base and ShamanPower.SetCoverageWatch then ShamanPower:SetCoverageWatch(base, val) end
							end,
						},
						coverage_watch_2_1 = {
							order = 11.5635,
							type = "toggle",
							name = function()
								local base = ShamanPower.TotemBuffSpellIDs and ShamanPower.TotemBuffSpellIDs[2] and ShamanPower.TotemBuffSpellIDs[2][1]
								return (base and GetSpellInfo(base)) or "Totem of Wrath"
							end,
							width = 1.0,
							hidden = function()
								if not (ShamanPower.CoverageAvailable and ShamanPower:CoverageAvailable()) then return true end
								local base = ShamanPower.TotemBuffSpellIDs and ShamanPower.TotemBuffSpellIDs[2] and ShamanPower.TotemBuffSpellIDs[2][1]
								if not base then return true end
								local totem = ShamanPower.GetTotemSpell and ShamanPower:GetTotemSpell(2, 1)
								return not (totem and SPCompat and SPCompat.SpellExists and SPCompat.SpellExists(totem))   -- not on this client
							end,
							disabled = function() return not (ShamanPower.opt.coverage and ShamanPower.opt.coverage.enabled) end,
							get = function() return ShamanPower.CoverageWatches and ShamanPower:CoverageWatches(2, 1) end,
							set = function(_, val)
								local base = ShamanPower.TotemBuffSpellIDs[2][1]
								if base and ShamanPower.SetCoverageWatch then ShamanPower:SetCoverageWatch(base, val) end
							end,
						},
						coverage_watch_2_5 = {
							order = 11.564,
							type = "toggle",
							name = function()
								local base = ShamanPower.TotemBuffSpellIDs and ShamanPower.TotemBuffSpellIDs[2] and ShamanPower.TotemBuffSpellIDs[2][5]
								return (base and GetSpellInfo(base)) or "Flametongue Totem"
							end,
							width = 1.0,
							hidden = function()
								if not (ShamanPower.CoverageAvailable and ShamanPower:CoverageAvailable()) then return true end
								local base = ShamanPower.TotemBuffSpellIDs and ShamanPower.TotemBuffSpellIDs[2] and ShamanPower.TotemBuffSpellIDs[2][5]
								if not base then return true end
								local totem = ShamanPower.GetTotemSpell and ShamanPower:GetTotemSpell(2, 5)
								return not (totem and SPCompat and SPCompat.SpellExists and SPCompat.SpellExists(totem))   -- not on this client
							end,
							disabled = function() return not (ShamanPower.opt.coverage and ShamanPower.opt.coverage.enabled) end,
							get = function() return ShamanPower.CoverageWatches and ShamanPower:CoverageWatches(2, 5) end,
							set = function(_, val)
								local base = ShamanPower.TotemBuffSpellIDs[2][5]
								if base and ShamanPower.SetCoverageWatch then ShamanPower:SetCoverageWatch(base, val) end
							end,
						},
						coverage_watch_2_6 = {
							order = 11.5645,
							type = "toggle",
							name = function()
								local base = ShamanPower.TotemBuffSpellIDs and ShamanPower.TotemBuffSpellIDs[2] and ShamanPower.TotemBuffSpellIDs[2][6]
								return (base and GetSpellInfo(base)) or "Frost Resistance"
							end,
							width = 1.0,
							hidden = function()
								if not (ShamanPower.CoverageAvailable and ShamanPower:CoverageAvailable()) then return true end
								local base = ShamanPower.TotemBuffSpellIDs and ShamanPower.TotemBuffSpellIDs[2] and ShamanPower.TotemBuffSpellIDs[2][6]
								if not base then return true end
								local totem = ShamanPower.GetTotemSpell and ShamanPower:GetTotemSpell(2, 6)
								return not (totem and SPCompat and SPCompat.SpellExists and SPCompat.SpellExists(totem))   -- not on this client
							end,
							disabled = function() return not (ShamanPower.opt.coverage and ShamanPower.opt.coverage.enabled) end,
							get = function() return ShamanPower.CoverageWatches and ShamanPower:CoverageWatches(2, 6) end,
							set = function(_, val)
								local base = ShamanPower.TotemBuffSpellIDs[2][6]
								if base and ShamanPower.SetCoverageWatch then ShamanPower:SetCoverageWatch(base, val) end
							end,
						},
						coverage_watch_3_1 = {
							order = 11.565,
							type = "toggle",
							name = function()
								local base = ShamanPower.TotemBuffSpellIDs and ShamanPower.TotemBuffSpellIDs[3] and ShamanPower.TotemBuffSpellIDs[3][1]
								return (base and GetSpellInfo(base)) or "Mana Spring"
							end,
							width = 1.0,
							hidden = function()
								if not (ShamanPower.CoverageAvailable and ShamanPower:CoverageAvailable()) then return true end
								local base = ShamanPower.TotemBuffSpellIDs and ShamanPower.TotemBuffSpellIDs[3] and ShamanPower.TotemBuffSpellIDs[3][1]
								if not base then return true end
								local totem = ShamanPower.GetTotemSpell and ShamanPower:GetTotemSpell(3, 1)
								return not (totem and SPCompat and SPCompat.SpellExists and SPCompat.SpellExists(totem))   -- not on this client
							end,
							disabled = function() return not (ShamanPower.opt.coverage and ShamanPower.opt.coverage.enabled) end,
							get = function() return ShamanPower.CoverageWatches and ShamanPower:CoverageWatches(3, 1) end,
							set = function(_, val)
								local base = ShamanPower.TotemBuffSpellIDs[3][1]
								if base and ShamanPower.SetCoverageWatch then ShamanPower:SetCoverageWatch(base, val) end
							end,
						},
						coverage_watch_3_2 = {
							order = 11.5655,
							type = "toggle",
							name = function()
								local base = ShamanPower.TotemBuffSpellIDs and ShamanPower.TotemBuffSpellIDs[3] and ShamanPower.TotemBuffSpellIDs[3][2]
								return (base and GetSpellInfo(base)) or "Healing Stream"
							end,
							width = 1.0,
							hidden = function()
								if not (ShamanPower.CoverageAvailable and ShamanPower:CoverageAvailable()) then return true end
								local base = ShamanPower.TotemBuffSpellIDs and ShamanPower.TotemBuffSpellIDs[3] and ShamanPower.TotemBuffSpellIDs[3][2]
								if not base then return true end
								local totem = ShamanPower.GetTotemSpell and ShamanPower:GetTotemSpell(3, 2)
								return not (totem and SPCompat and SPCompat.SpellExists and SPCompat.SpellExists(totem))   -- not on this client
							end,
							disabled = function() return not (ShamanPower.opt.coverage and ShamanPower.opt.coverage.enabled) end,
							get = function() return ShamanPower.CoverageWatches and ShamanPower:CoverageWatches(3, 2) end,
							set = function(_, val)
								local base = ShamanPower.TotemBuffSpellIDs[3][2]
								if base and ShamanPower.SetCoverageWatch then ShamanPower:SetCoverageWatch(base, val) end
							end,
						},
						coverage_watch_3_3 = {
							order = 11.566,
							type = "toggle",
							name = function()
								local base = ShamanPower.TotemBuffSpellIDs and ShamanPower.TotemBuffSpellIDs[3] and ShamanPower.TotemBuffSpellIDs[3][3]
								return (base and GetSpellInfo(base)) or "Mana Tide"
							end,
							width = 1.0,
							hidden = function()
								if not (ShamanPower.CoverageAvailable and ShamanPower:CoverageAvailable()) then return true end
								local base = ShamanPower.TotemBuffSpellIDs and ShamanPower.TotemBuffSpellIDs[3] and ShamanPower.TotemBuffSpellIDs[3][3]
								if not base then return true end
								local totem = ShamanPower.GetTotemSpell and ShamanPower:GetTotemSpell(3, 3)
								return not (totem and SPCompat and SPCompat.SpellExists and SPCompat.SpellExists(totem))   -- not on this client
							end,
							disabled = function() return not (ShamanPower.opt.coverage and ShamanPower.opt.coverage.enabled) end,
							get = function() return ShamanPower.CoverageWatches and ShamanPower:CoverageWatches(3, 3) end,
							set = function(_, val)
								local base = ShamanPower.TotemBuffSpellIDs[3][3]
								if base and ShamanPower.SetCoverageWatch then ShamanPower:SetCoverageWatch(base, val) end
							end,
						},
						coverage_watch_3_6 = {
							order = 11.5665,
							type = "toggle",
							name = function()
								local base = ShamanPower.TotemBuffSpellIDs and ShamanPower.TotemBuffSpellIDs[3] and ShamanPower.TotemBuffSpellIDs[3][6]
								return (base and GetSpellInfo(base)) or "Fire Resistance"
							end,
							width = 1.0,
							hidden = function()
								if not (ShamanPower.CoverageAvailable and ShamanPower:CoverageAvailable()) then return true end
								local base = ShamanPower.TotemBuffSpellIDs and ShamanPower.TotemBuffSpellIDs[3] and ShamanPower.TotemBuffSpellIDs[3][6]
								if not base then return true end
								local totem = ShamanPower.GetTotemSpell and ShamanPower:GetTotemSpell(3, 6)
								return not (totem and SPCompat and SPCompat.SpellExists and SPCompat.SpellExists(totem))   -- not on this client
							end,
							disabled = function() return not (ShamanPower.opt.coverage and ShamanPower.opt.coverage.enabled) end,
							get = function() return ShamanPower.CoverageWatches and ShamanPower:CoverageWatches(3, 6) end,
							set = function(_, val)
								local base = ShamanPower.TotemBuffSpellIDs[3][6]
								if base and ShamanPower.SetCoverageWatch then ShamanPower:SetCoverageWatch(base, val) end
							end,
						},
						coverage_watch_4_1 = {
							order = 11.567,
							type = "toggle",
							name = function()
								local base = ShamanPower.TotemBuffSpellIDs and ShamanPower.TotemBuffSpellIDs[4] and ShamanPower.TotemBuffSpellIDs[4][1]
								return (base and GetSpellInfo(base)) or "Windfury Totem"
							end,
							width = 1.0,
							hidden = function()
								if not (ShamanPower.CoverageAvailable and ShamanPower:CoverageAvailable()) then return true end
								local base = ShamanPower.TotemBuffSpellIDs and ShamanPower.TotemBuffSpellIDs[4] and ShamanPower.TotemBuffSpellIDs[4][1]
								if not base then return true end
								local totem = ShamanPower.GetTotemSpell and ShamanPower:GetTotemSpell(4, 1)
								return not (totem and SPCompat and SPCompat.SpellExists and SPCompat.SpellExists(totem))   -- not on this client
							end,
							disabled = function() return not (ShamanPower.opt.coverage and ShamanPower.opt.coverage.enabled) end,
							get = function() return ShamanPower.CoverageWatches and ShamanPower:CoverageWatches(4, 1) end,
							set = function(_, val)
								local base = ShamanPower.TotemBuffSpellIDs[4][1]
								if base and ShamanPower.SetCoverageWatch then ShamanPower:SetCoverageWatch(base, val) end
							end,
						},
						coverage_watch_4_2 = {
							order = 11.5675,
							type = "toggle",
							name = function()
								local base = ShamanPower.TotemBuffSpellIDs and ShamanPower.TotemBuffSpellIDs[4] and ShamanPower.TotemBuffSpellIDs[4][2]
								return (base and GetSpellInfo(base)) or "Grace of Air"
							end,
							width = 1.0,
							hidden = function()
								if not (ShamanPower.CoverageAvailable and ShamanPower:CoverageAvailable()) then return true end
								local base = ShamanPower.TotemBuffSpellIDs and ShamanPower.TotemBuffSpellIDs[4] and ShamanPower.TotemBuffSpellIDs[4][2]
								if not base then return true end
								local totem = ShamanPower.GetTotemSpell and ShamanPower:GetTotemSpell(4, 2)
								return not (totem and SPCompat and SPCompat.SpellExists and SPCompat.SpellExists(totem))   -- not on this client
							end,
							disabled = function() return not (ShamanPower.opt.coverage and ShamanPower.opt.coverage.enabled) end,
							get = function() return ShamanPower.CoverageWatches and ShamanPower:CoverageWatches(4, 2) end,
							set = function(_, val)
								local base = ShamanPower.TotemBuffSpellIDs[4][2]
								if base and ShamanPower.SetCoverageWatch then ShamanPower:SetCoverageWatch(base, val) end
							end,
						},
						coverage_watch_4_3 = {
							order = 11.568,
							type = "toggle",
							name = function()
								local base = ShamanPower.TotemBuffSpellIDs and ShamanPower.TotemBuffSpellIDs[4] and ShamanPower.TotemBuffSpellIDs[4][3]
								return (base and GetSpellInfo(base)) or "Wrath of Air"
							end,
							width = 1.0,
							hidden = function()
								if not (ShamanPower.CoverageAvailable and ShamanPower:CoverageAvailable()) then return true end
								local base = ShamanPower.TotemBuffSpellIDs and ShamanPower.TotemBuffSpellIDs[4] and ShamanPower.TotemBuffSpellIDs[4][3]
								if not base then return true end
								local totem = ShamanPower.GetTotemSpell and ShamanPower:GetTotemSpell(4, 3)
								return not (totem and SPCompat and SPCompat.SpellExists and SPCompat.SpellExists(totem))   -- not on this client
							end,
							disabled = function() return not (ShamanPower.opt.coverage and ShamanPower.opt.coverage.enabled) end,
							get = function() return ShamanPower.CoverageWatches and ShamanPower:CoverageWatches(4, 3) end,
							set = function(_, val)
								local base = ShamanPower.TotemBuffSpellIDs[4][3]
								if base and ShamanPower.SetCoverageWatch then ShamanPower:SetCoverageWatch(base, val) end
							end,
						},
						coverage_watch_4_4 = {
							order = 11.5685,
							type = "toggle",
							name = function()
								local base = ShamanPower.TotemBuffSpellIDs and ShamanPower.TotemBuffSpellIDs[4] and ShamanPower.TotemBuffSpellIDs[4][4]
								return (base and GetSpellInfo(base)) or "Tranquil Air"
							end,
							width = 1.0,
							hidden = function()
								if not (ShamanPower.CoverageAvailable and ShamanPower:CoverageAvailable()) then return true end
								local base = ShamanPower.TotemBuffSpellIDs and ShamanPower.TotemBuffSpellIDs[4] and ShamanPower.TotemBuffSpellIDs[4][4]
								if not base then return true end
								local totem = ShamanPower.GetTotemSpell and ShamanPower:GetTotemSpell(4, 4)
								return not (totem and SPCompat and SPCompat.SpellExists and SPCompat.SpellExists(totem))   -- not on this client
							end,
							disabled = function() return not (ShamanPower.opt.coverage and ShamanPower.opt.coverage.enabled) end,
							get = function() return ShamanPower.CoverageWatches and ShamanPower:CoverageWatches(4, 4) end,
							set = function(_, val)
								local base = ShamanPower.TotemBuffSpellIDs[4][4]
								if base and ShamanPower.SetCoverageWatch then ShamanPower:SetCoverageWatch(base, val) end
							end,
						},
						coverage_watch_4_6 = {
							order = 11.569,
							type = "toggle",
							name = function()
								local base = ShamanPower.TotemBuffSpellIDs and ShamanPower.TotemBuffSpellIDs[4] and ShamanPower.TotemBuffSpellIDs[4][6]
								return (base and GetSpellInfo(base)) or "Nature Resistance"
							end,
							width = 1.0,
							hidden = function()
								if not (ShamanPower.CoverageAvailable and ShamanPower:CoverageAvailable()) then return true end
								local base = ShamanPower.TotemBuffSpellIDs and ShamanPower.TotemBuffSpellIDs[4] and ShamanPower.TotemBuffSpellIDs[4][6]
								if not base then return true end
								local totem = ShamanPower.GetTotemSpell and ShamanPower:GetTotemSpell(4, 6)
								return not (totem and SPCompat and SPCompat.SpellExists and SPCompat.SpellExists(totem))   -- not on this client
							end,
							disabled = function() return not (ShamanPower.opt.coverage and ShamanPower.opt.coverage.enabled) end,
							get = function() return ShamanPower.CoverageWatches and ShamanPower:CoverageWatches(4, 6) end,
							set = function(_, val)
								local base = ShamanPower.TotemBuffSpellIDs[4][6]
								if base and ShamanPower.SetCoverageWatch then ShamanPower:SetCoverageWatch(base, val) end
							end,
						},
						coverage_watch_4_7 = {
							order = 11.5695,
							type = "toggle",
							name = function()
								local base = ShamanPower.TotemBuffSpellIDs and ShamanPower.TotemBuffSpellIDs[4] and ShamanPower.TotemBuffSpellIDs[4][7]
								return (base and GetSpellInfo(base)) or "Windwall"
							end,
							width = 1.0,
							hidden = function()
								if not (ShamanPower.CoverageAvailable and ShamanPower:CoverageAvailable()) then return true end
								local base = ShamanPower.TotemBuffSpellIDs and ShamanPower.TotemBuffSpellIDs[4] and ShamanPower.TotemBuffSpellIDs[4][7]
								if not base then return true end
								local totem = ShamanPower.GetTotemSpell and ShamanPower:GetTotemSpell(4, 7)
								return not (totem and SPCompat and SPCompat.SpellExists and SPCompat.SpellExists(totem))   -- not on this client
							end,
							disabled = function() return not (ShamanPower.opt.coverage and ShamanPower.opt.coverage.enabled) end,
							get = function() return ShamanPower.CoverageWatches and ShamanPower:CoverageWatches(4, 7) end,
							set = function(_, val)
								local base = ShamanPower.TotemBuffSpellIDs[4][7]
								if base and ShamanPower.SetCoverageWatch then ShamanPower:SetCoverageWatch(base, val) end
							end,
						},
						coverage_move = {
							order = 11.55,
							type = "execute",
							name = "Move the Coverage List",
							desc = "Unlocks just the list: drag its box where you want it, then press Done to come back here.",
							width = 1.2,
							hidden = function() return not (ShamanPower.CoverageAvailable and ShamanPower:CoverageAvailable() and ShamanPower.opt.coverage and ShamanPower.opt.coverage.enabled and ShamanPower.UnlockModuleFrames) end,
							func = function() ShamanPower:UnlockModuleFrames("coverage") end,
						},
						partybuff_reset = {
							order = 11,
							type = "execute",
							name = "Reset Frame Positions",
							desc = "Reset unlocked counter frames to center of screen",
							hidden = function()
								return not (ShamanPower.opt.rangeCounter and ShamanPower.opt.rangeCounter.enabled)
									or (ShamanPower.opt.rangeCounter and ShamanPower.opt.rangeCounter.location ~= "unlocked")
							end,
							func = function()
								-- Clear saved positions
								if ShamanPower.opt.rangeCounter then
									ShamanPower.opt.rangeCounter.positions = {}
								end
								-- Reposition existing frames to center of screen
								for element = 1, 4 do
									local frame = ShamanPower.rangeCounterFrames[element]
									if frame then
										local xOffset = (element - 2.5) * 55  -- Spread horizontally
										frame:ClearAllPoints()
										frame:SetPoint("CENTER", UIParent, "CENTER", xOffset, 0)
									end
								end
							end
						},
					}
				},
				estrack_section = {
					order = 16,
					name = "|cff0070ddEarth Shield Tracker|r",
					type = "group",
					-- No Earth Shield on this client means nothing to track. The
					-- nav list drops any entry whose page resolves to nothing, so
					-- hiding the group removes the sidebar row with it.
					hidden = function() return ShamanPower.ESTrackerUnavailable == true end,
					args = {
						module_missing_note = {
							order = 0.01,
							type = "description",
							name = "|cffffa040This module is not loaded, so nothing on this page does anything right now (toggles may even snap back). Enable the ShamanPower [Earth Shield Tracker] addon in the AddOns list and /reload.|r",
							hidden = function() return not (not ShamanPower.ESTrackerLoaded) end,
						},
						estrack_desc = {
							order = 0,
							type = "description",
							name = "Track all Earth Shields cast by OTHER shamans in your party/raid. ALT+drag to move the frame.\n\n|cffff8800Note:|r Requires the |cff00ff00ShamanPower [Raid ES Tracker]|r module to be enabled in your AddOns list.\n",
						},
						estrack_enabled = {
							order = 1,
							name = "Enable Earth Shield Tracker",
							desc = "Enable the Earth Shield tracker to show all Earth Shields in your party/raid",
							type = "toggle",
							width = "full",
							get = function(info)
								return ShamanPower.opt.esTracker and ShamanPower.opt.esTracker.enabled or false
							end,
							set = function(info, val)
								ShamanPower:EnsureProfileTable("esTracker")
								ShamanPower.opt.esTracker.enabled = val
								if ShamanPower.SetESTrackerEnabled then ShamanPower:SetESTrackerEnabled(val) end
							end
						},
						estrack_opacity = {
							disabled = function(info) return (not (ShamanPower.opt.esTracker and ShamanPower.opt.esTracker.enabled)) and true or false end,
							order = 2,
							name = "Opacity",
							desc = "Adjust the opacity of the Earth Shield tracker",
							type = "range",
							isPercent = true,
							width = "full",
							min = 0.2,
							max = 1.0,
							step = 0.1,
							get = function(info)
								return ShamanPower.opt.esTracker and ShamanPower.opt.esTracker.opacity or 1.0
							end,
							set = function(info, val)
								ShamanPower:EnsureProfileTable("esTracker")
								ShamanPower.opt.esTracker.opacity = val
								ShamanPower:UpdateESTrackerOpacity()
							end
						},
						estrack_icon_size = {
							disabled = function(info) return (not (ShamanPower.opt.esTracker and ShamanPower.opt.esTracker.enabled)) and true or false end,
							order = 3,
							name = "Icon Size",
							desc = "Adjust the size of the Earth Shield tracker icons",
							type = "range",
							width = "full",
							min = 20,
							max = 60,
							step = 4,
							get = function(info)
								return ShamanPower.opt.esTracker and ShamanPower.opt.esTracker.iconSize or 40
							end,
							set = function(info, val)
								ShamanPower:EnsureProfileTable("esTracker")
								ShamanPower.opt.esTracker.iconSize = val
								ShamanPower:UpdateESTrackerFrame()
							end
						},
						estrack_options_header = {
							order = 4,
							type = "header",
							name = "Display Options",
						},
						estrack_vertical = {
							disabled = function(info) return (not (ShamanPower.opt.esTracker and ShamanPower.opt.esTracker.enabled)) and true or false end,
							order = 5,
							name = "Vertical Layout",
							desc = "Stack Earth Shield icons vertically instead of horizontally",
							type = "toggle",
							width = "full",
							get = function(info)
								return ShamanPower.opt.esTracker and ShamanPower.opt.esTracker.vertical or false
							end,
							set = function(info, val)
								ShamanPower:EnsureProfileTable("esTracker")
								ShamanPower.opt.esTracker.vertical = val
								ShamanPower:UpdateESTrackerFrame()
								ShamanPower:UpdateESTrackerBorder()
							end
						},
						estrack_hide_names = {
							disabled = function(info) return (not (ShamanPower.opt.esTracker and ShamanPower.opt.esTracker.enabled)) and true or false end,
							order = 6,
							name = "Hide Names",
							desc = "Hide player names on the Earth Shield tracker",
							type = "toggle",
							width = "full",
							get = function(info)
								return ShamanPower.opt.esTracker and ShamanPower.opt.esTracker.hideNames or false
							end,
							set = function(info, val)
								ShamanPower:EnsureProfileTable("esTracker")
								ShamanPower.opt.esTracker.hideNames = val
								ShamanPower:UpdateESTrackerFrame()
							end
						},
						estrack_hide_border = {
							disabled = function(info) return (not (ShamanPower.opt.esTracker and ShamanPower.opt.esTracker.enabled)) and true or false end,
							order = 7,
							name = "Hide Border",
							desc = "Hide the frame border and title (use ALT+drag to move when hidden)",
							type = "toggle",
							width = "full",
							get = function(info)
								return ShamanPower.opt.esTracker and ShamanPower.opt.esTracker.hideBorder or false
							end,
							set = function(info, val)
								ShamanPower:EnsureProfileTable("esTracker")
								ShamanPower.opt.esTracker.hideBorder = val
								ShamanPower:UpdateESTrackerBorder()
							end
						},
						estrack_hide_charges = {
							disabled = function(info) return (not (ShamanPower.opt.esTracker and ShamanPower.opt.esTracker.enabled)) and true or false end,
							order = 8,
							name = "Hide Charges",
							desc = "Hide the charge count on Earth Shield icons",
							type = "toggle",
							width = "full",
							get = function(info)
								return ShamanPower.opt.esTracker and ShamanPower.opt.esTracker.hideCharges or false
							end,
							set = function(info, val)
								ShamanPower:EnsureProfileTable("esTracker")
								ShamanPower.opt.esTracker.hideCharges = val
								ShamanPower:UpdateESTrackerFrame()
							end
						},
					}
				},
				shieldcharges_section = {
					order = 17,
					name = "|cff0070ddShield Charge Display|r",
					type = "group",
					args = {
						both_off_note = {
							order = 0.06,
							type = "description",
							name = "|cffffa040Both displays are turned off, so scale, opacity, lock and the hide options have nothing to act on.|r",
							hidden = function() return not (ShamanPower.opt.shieldChargeDisplay and ShamanPower.opt.shieldChargeDisplay.showPlayerShield == false and ShamanPower.opt.shieldChargeDisplay.showEarthShield == false) end,
						},
						hide_ooc_note = {
							order = 0.05,
							type = "description",
							name = "|cffffa040\"Hide Out of Combat\" is on, so the numbers only appear during a fight. Turn it off while you position or preview them.|r",
							hidden = function() return not (ShamanPower.opt.shieldChargeDisplay and ShamanPower.opt.shieldChargeDisplay.hideOutOfCombat and not InCombatLockdown()) end,
						},
						module_missing_note = {
							order = 0.01,
							type = "description",
							name = "|cffffa040This module is not loaded, so nothing on this page does anything right now (toggles may even snap back). Enable the ShamanPower [Shield Charges] addon in the AddOns list and /reload.|r",
							hidden = function() return not (not ShamanPower.ShieldChargesLoaded) end,
						},
						shieldcharges_desc = {
							order = 0,
							type = "description",
							name = function()
								if ShamanPower.ESTrackerUnavailable then
									return "A large on-screen number showing your shield charges (Lightning or Water Shield). ALT+drag to move when unlocked.\n\n|cffff8800Note:|r Requires the |cff00ff00ShamanPower [Shield Charge Display]|r module to be enabled in your AddOns list.\n"
								end
								return "Large on-screen numbers showing your shield charges and Earth Shield charges on your target. ALT+drag to move when unlocked.\n\n|cffff8800Note:|r Requires the |cff00ff00ShamanPower [Shield Charge Display]|r module to be enabled in your AddOns list.\n"
							end,
						},
						shieldcharges_player = {
							order = 1,
							name = "Show Player Shield Charges",
							desc = "Show Lightning Shield or Water Shield charge count",
							type = "toggle",
							width = "full",
							get = function(info)
								return ShamanPower.opt.shieldChargeDisplay and ShamanPower.opt.shieldChargeDisplay.showPlayerShield
							end,
							set = function(info, val)
								if ShamanPower.opt.shieldChargeDisplay then
									ShamanPower.opt.shieldChargeDisplay.showPlayerShield = val
									ShamanPower:UpdateShieldChargeDisplays()
								end
							end
						},
						shieldcharges_earth = {
							-- no Earth Shield on this client (one hidden: a second key silently replaced the first)
							hidden = function(info) return ShamanPower.ESTrackerUnavailable == true or (SPCompat and SPCompat.earthShieldExists == false) and true or false end,
							order = 2,
							name = "Show Earth Shield Charges",
							desc = "Show Earth Shield charge count on your current target",
							type = "toggle",
							width = "full",
							get = function(info)
								return ShamanPower.opt.shieldChargeDisplay and ShamanPower.opt.shieldChargeDisplay.showEarthShield
							end,
							set = function(info, val)
								if ShamanPower.opt.shieldChargeDisplay then
									ShamanPower.opt.shieldChargeDisplay.showEarthShield = val
									ShamanPower:UpdateShieldChargeDisplays()
								end
							end
						},
						shieldcharges_scale = {
							order = 3,
							name = "Scale",
							desc = "Adjust the size of the shield charge numbers",
							type = "range",
							isPercent = true,
							width = "full",
							min = 0.5,
							max = 3.0,
							step = 0.1,
							get = function(info)
								return ShamanPower.opt.shieldChargeDisplay and ShamanPower.opt.shieldChargeDisplay.scale or 1.0
							end,
							set = function(info, val)
								if ShamanPower.opt.shieldChargeDisplay then
									ShamanPower.opt.shieldChargeDisplay.scale = val
									ShamanPower:UpdateShieldChargeDisplays()
								end
							end
						},
						shieldcharges_opacity = {
							order = 4,
							name = "Opacity",
							desc = "Adjust the opacity of the shield charge display",
							type = "range",
							isPercent = true,
							width = "full",
							min = 0.1,
							max = 1.0,
							step = 0.1,
							get = function(info)
								return ShamanPower.opt.shieldChargeDisplay and ShamanPower.opt.shieldChargeDisplay.opacity or 1.0
							end,
							set = function(info, val)
								if ShamanPower.opt.shieldChargeDisplay then
									ShamanPower.opt.shieldChargeDisplay.opacity = val
									ShamanPower:UpdateShieldChargeDisplays()
								end
							end
						},
						shieldcharges_locked = {
							order = 5,
							name = "Lock Position",
							desc = "Lock the shield charge displays in place (click-through)",
							type = "toggle",
							width = "full",
							get = function(info)
								return ShamanPower.opt.shieldChargeDisplay and ShamanPower.opt.shieldChargeDisplay.locked
							end,
							set = function(info, val)
								if ShamanPower.opt.shieldChargeDisplay then
									ShamanPower.opt.shieldChargeDisplay.locked = val
									ShamanPower:UpdateShieldChargeDisplays()
								end
							end
						},
						shieldcharges_hide_ooc = {
							order = 6,
							name = "Hide Out of Combat",
							desc = "Hide the shield charge display when not in combat",
							type = "toggle",
							width = "full",
							get = function(info)
								return ShamanPower.opt.shieldChargeDisplay and ShamanPower.opt.shieldChargeDisplay.hideOutOfCombat
							end,
							set = function(info, val)
								if ShamanPower.opt.shieldChargeDisplay then
									ShamanPower.opt.shieldChargeDisplay.hideOutOfCombat = val
									ShamanPower:UpdateShieldChargeDisplays()
								end
							end
						},
						shieldcharges_hide_none = {
							order = 7,
							name = "Hide When No Shields",
							desc = "Hide the display when no shields are active",
							type = "toggle",
							width = "full",
							get = function(info)
								return ShamanPower.opt.shieldChargeDisplay and ShamanPower.opt.shieldChargeDisplay.hideNoShields
							end,
							set = function(info, val)
								if ShamanPower.opt.shieldChargeDisplay then
									ShamanPower.opt.shieldChargeDisplay.hideNoShields = val
									ShamanPower:UpdateShieldChargeDisplays()
								end
							end
						},
					}
				},
				reactivetotems_section = {
					order = 18,
					name = "|cff0070ddReactive Totems|r",
					type = "group",
					args = {
						master_off_note = {
							order = 0.06,
							type = "description",
							name = "|cffffa040Reactive Totems is disabled, so the settings below have no live effect.|r",
							hidden = function() return not (ShamanPower_ReactiveTotems and ShamanPower_ReactiveTotems.enabled == false) end,
						},
						engine_note = {
							order = 0.04,
							type = "description",
							name = "|cffffa040On this client the alerts are drawn by the game engine straight from the debuffs, so they work in combat. What that changes: the alert shows the affected player's name, the debuff's icon and its time left instead of the debuff's name; the Fear alert fires for any crowd control (the client has no fear-only filter); the sound can only play out of combat.|r",
							hidden = function() return not (SPCompat and SPCompat.secretsRegime) end,
						},
						instance_only_note = {
							order = 0.05,
							type = "description",
							name = "|cffffa040\"Only Alert in Instances\" is on and you are not in one, so nothing will show out here. Use Test / Show All to preview.|r",
							hidden = function() return not (ShamanPower_ReactiveTotems and ShamanPower_ReactiveTotems.onlyInInstance and not IsInInstance()) end,
						},
						module_missing_note = {
							order = 0.01,
							type = "description",
							name = "|cffffa040This module is not loaded, so nothing on this page does anything right now (toggles may even snap back). Enable the ShamanPower [Reactive Totems] addon in the AddOns list and /reload.|r",
							hidden = function() return not (not ShamanPower.ReactiveTotemsLoaded) end,
						},
						reactive_desc = {
							order = 0,
							type = "description",
							name = "Shows large totem icons when party members have fear, disease, or poison debuffs.\n\n|cffff8800Note:|r Requires the |cff00ff00ShamanPower [Reactive Totems]|r module to be enabled in your AddOns list.\n",
						},
						reactive_enabled = {
							order = 1,
							name = "Enable Reactive Totems",
							desc = "Enable the reactive totem display when you have cleansable debuffs",
							type = "toggle",
							width = 1.0,
							get = function(info)
								if ShamanPower_ReactiveTotems then
									return ShamanPower_ReactiveTotems.enabled ~= false
								end
								return true
							end,
							set = function(info, val)
								if ShamanPower_ReactiveTotems then
									ShamanPower_ReactiveTotems.enabled = val
									if ShamanPower.UpdateReactiveTotems then
										ShamanPower:UpdateReactiveTotems()
									end
								end
							end
						},
						reactive_locked = {
							order = 1.5,
							name = "Lock Positions",
							desc = "Lock the frame positions so they can't be dragged",
							type = "toggle",
							width = 1.0,
							get = function(info)
								if ShamanPower_ReactiveTotems then
									return ShamanPower_ReactiveTotems.locked or false
								end
								return false
							end,
							set = function(info, val)
								if ShamanPower_ReactiveTotems then
									ShamanPower_ReactiveTotems.locked = val
								end
							end
						},
						reactive_only_instance = {
							order = 1.6,
							name = "Only Alert in Instances",
							desc = "Only show reactive totem alerts inside dungeons, raids, and battlegrounds",
							type = "toggle",
							width = "full",
							get = function(info)
								if ShamanPower_ReactiveTotems then
									return ShamanPower_ReactiveTotems.onlyInInstance or false
								end
								return false
							end,
							set = function(info, val)
								if ShamanPower_ReactiveTotems then
									ShamanPower_ReactiveTotems.onlyInInstance = val
									if ShamanPower.UpdateReactiveTotems then
										ShamanPower:UpdateReactiveTotems()
									end
								end
							end
						},
						reactive_hide_when_active = {
							order = 1.7,
							name = "Hide When Totem Active",
							desc = "Hide the alert when the relevant cleansing totem is already placed",
							type = "toggle",
							width = "full",
							get = function(info)
								if ShamanPower_ReactiveTotems then
									return ShamanPower_ReactiveTotems.hideWhenTotemActive ~= false
								end
								return true
							end,
							set = function(info, val)
								if ShamanPower_ReactiveTotems then
									ShamanPower_ReactiveTotems.hideWhenTotemActive = val
									if ShamanPower.UpdateReactiveTotems then
										ShamanPower:UpdateReactiveTotems()
									end
								end
							end
						},
						reactive_header_tracking = {
							order = 2,
							type = "header",
							name = "Debuff Tracking",
						},
						reactive_track_fear = {
							order = 3,
							name = "Track Fear/Charm",
							desc = "Show Tremor Totem icon when feared, charmed, or horrified",
							type = "toggle",
							width = 1.0,
							get = function(info)
								if ShamanPower_ReactiveTotems and ShamanPower_ReactiveTotems then
									return ShamanPower_ReactiveTotems.trackFear ~= false
								end
								return true
							end,
							set = function(info, val)
								if ShamanPower_ReactiveTotems and ShamanPower_ReactiveTotems then
									ShamanPower_ReactiveTotems.trackFear = val
									if ShamanPower.UpdateReactiveTotems then
										ShamanPower:UpdateReactiveTotems()
									end
								end
							end
						},
						reactive_track_poison = {
							order = 4,
							name = "Track Poison",
							desc = "Show Poison Cleansing Totem icon when poisoned",
							type = "toggle",
							width = 1.0,
							get = function(info)
								if ShamanPower_ReactiveTotems and ShamanPower_ReactiveTotems then
									return ShamanPower_ReactiveTotems.trackPoison ~= false
								end
								return true
							end,
							set = function(info, val)
								if ShamanPower_ReactiveTotems and ShamanPower_ReactiveTotems then
									ShamanPower_ReactiveTotems.trackPoison = val
									if ShamanPower.UpdateReactiveTotems then
										ShamanPower:UpdateReactiveTotems()
									end
								end
							end
						},
						reactive_track_disease = {
							order = 5,
							name = "Track Disease",
							desc = "Show Disease Cleansing Totem icon when diseased",
							type = "toggle",
							width = 1.0,
							get = function(info)
								if ShamanPower_ReactiveTotems and ShamanPower_ReactiveTotems then
									return ShamanPower_ReactiveTotems.trackDisease ~= false
								end
								return true
							end,
							set = function(info, val)
								if ShamanPower_ReactiveTotems and ShamanPower_ReactiveTotems then
									ShamanPower_ReactiveTotems.trackDisease = val
									if ShamanPower.UpdateReactiveTotems then
										ShamanPower:UpdateReactiveTotems()
									end
								end
							end
						},
						reactive_header_appearance = {
							order = 6,
							type = "header",
							name = "Appearance",
						},
						reactive_icon_size = {
							order = 6.5,
							name = "Icon Size",
							desc = "Base size of the reactive totem icons in pixels",
							type = "range",
							width = 1.5,
							min = 32,
							max = 256,
							step = 4,
							get = function(info)
								if ShamanPower_ReactiveTotems then
									return ShamanPower_ReactiveTotems.iconSize or 64
								end
								return 64
							end,
							set = function(info, val)
								if ShamanPower_ReactiveTotems then
									ShamanPower_ReactiveTotems.iconSize = val
									if ShamanPower.UpdateReactiveTotemAppearance then
										ShamanPower:UpdateReactiveTotemAppearance()
									end
								end
							end
						},
						reactive_opacity = {
							order = 8,
							name = "Opacity",
							desc = "Adjust the opacity of the reactive totem icons",
							type = "range",
							isPercent = true,
							width = 1.5,
							min = 0.2,
							max = 1.0,
							step = 0.1,
							get = function(info)
								if ShamanPower_ReactiveTotems and ShamanPower_ReactiveTotems then
									return ShamanPower_ReactiveTotems.opacity or 1.0
								end
								return 1.0
							end,
							set = function(info, val)
								if ShamanPower_ReactiveTotems and ShamanPower_ReactiveTotems then
									ShamanPower_ReactiveTotems.opacity = val
									if ShamanPower.UpdateReactiveTotemAppearance then
										ShamanPower:UpdateReactiveTotemAppearance()
									end
								end
							end
						},
						reactive_hide_border = {
							order = 9,
							name = "Hide Border",
							desc = "Hide the border around the reactive totem icons",
							type = "toggle",
							width = 1.0,
							get = function(info)
								if ShamanPower_ReactiveTotems and ShamanPower_ReactiveTotems then
									return ShamanPower_ReactiveTotems.hideBorder or false
								end
								return false
							end,
							set = function(info, val)
								if ShamanPower_ReactiveTotems and ShamanPower_ReactiveTotems then
									ShamanPower_ReactiveTotems.hideBorder = val
									if ShamanPower.UpdateReactiveTotemAppearance then
										ShamanPower:UpdateReactiveTotemAppearance()
									end
								end
							end
						},
						reactive_hide_background = {
							order = 10,
							name = "Hide Background",
							desc = "Hide the background behind the reactive totem icons",
							type = "toggle",
							width = 1.0,
							get = function(info)
								if ShamanPower_ReactiveTotems and ShamanPower_ReactiveTotems then
									return ShamanPower_ReactiveTotems.hideBackground or false
								end
								return false
							end,
							set = function(info, val)
								if ShamanPower_ReactiveTotems and ShamanPower_ReactiveTotems then
									ShamanPower_ReactiveTotems.hideBackground = val
									if ShamanPower.UpdateReactiveTotemAppearance then
										ShamanPower:UpdateReactiveTotemAppearance()
									end
								end
							end
						},
						reactive_font_size = {
							order = 11,
							name = "Font Size",
							desc = "Size of the totem name text",
							type = "range",
							width = 1.5,
							min = 8,
							max = 24,
							step = 1,
							get = function(info)
								if ShamanPower_ReactiveTotems and ShamanPower_ReactiveTotems then
									return ShamanPower_ReactiveTotems.fontSize or 12
								end
								return 12
							end,
							set = function(info, val)
								if ShamanPower_ReactiveTotems and ShamanPower_ReactiveTotems then
									ShamanPower_ReactiveTotems.fontSize = val
									if ShamanPower.UpdateReactiveTotemAppearance then
										ShamanPower:UpdateReactiveTotemAppearance()
									end
								end
							end
						},
						reactive_hide_debuff_text = {
							order = 11.1,
							name = "Hide Debuff Text",
							desc = "Hide the debuff name/type text (e.g. 'PlayerName: Fear')",
							type = "toggle",
							width = 1.0,
							get = function(info)
								if ShamanPower_ReactiveTotems then
									return not ShamanPower_ReactiveTotems.showDebuffName
								end
								return false
							end,
							set = function(info, val)
								if ShamanPower_ReactiveTotems then
									ShamanPower_ReactiveTotems.showDebuffName = not val
									if ShamanPower.UpdateReactiveTotemAppearance then
										ShamanPower:UpdateReactiveTotemAppearance()
									end
								end
							end
						},
						reactive_show_debuff_icon = {
							order = 11.15,
							name = "Show Debuff Icon",
							desc = "Add the debuff's own icon as a small badge in the corner of the alert (the engine paints it; the debuff's name cannot be read in combat on this client). Off: just the totem to drop.",
							type = "toggle",
							width = 1.0,
							hidden = function() return not (SPCompat and SPCompat.secretsRegime) end,
							get = function(info)
								if ShamanPower_ReactiveTotems then
									return ShamanPower_ReactiveTotems.showDebuffIcon and true or false
								end
								return false
							end,
							set = function(info, val)
								if ShamanPower_ReactiveTotems then
									ShamanPower_ReactiveTotems.showDebuffIcon = val
									if ShamanPower.UpdateReactiveTotemAppearance then
										ShamanPower:UpdateReactiveTotemAppearance()
									end
								end
							end
						},
						reactive_hide_totem_text = {
							order = 11.2,
							name = "Hide Totem Name",
							desc = "Hide the totem name text (e.g. 'Tremor Totem')",
							type = "toggle",
							width = 1.0,
							get = function(info)
								if ShamanPower_ReactiveTotems then
									return not ShamanPower_ReactiveTotems.showTotemName
								end
								return false
							end,
							set = function(info, val)
								if ShamanPower_ReactiveTotems then
									ShamanPower_ReactiveTotems.showTotemName = not val
									if ShamanPower.UpdateReactiveTotemAppearance then
										ShamanPower:UpdateReactiveTotemAppearance()
									end
								end
							end
						},
						reactive_header_effects = {
							order = 12,
							type = "header",
							name = "Effects",
						},
						reactive_glow = {
							order = 13,
							name = "Show Glow Effect",
							desc = "Show a pulsing glow around the reactive totem icons",
							type = "toggle",
							width = 1.0,
							get = function(info)
								if ShamanPower_ReactiveTotems then
									return ShamanPower_ReactiveTotems.showGlow ~= false
								end
								return true
							end,
							set = function(info, val)
								if ShamanPower_ReactiveTotems then
									ShamanPower_ReactiveTotems.showGlow = val
									if ShamanPower.UpdateReactiveTotemAppearance then
										ShamanPower:UpdateReactiveTotemAppearance()
									end
								end
							end
						},
						reactive_glow_intensity = {
							disabled = function(info) return (ShamanPower_ReactiveTotems and ShamanPower_ReactiveTotems.showGlow == false) and true or false end,
							order = 13.5,
							name = "Glow Intensity",
							desc = WithNotes("Intensity of the pulsing glow effect",
								true, "Takes effect after a /reload (the glow is built once)."),
							type = "range",
							isPercent = true,
							width = 1.5,
							min = 0.2,
							max = 1.0,
							step = 0.1,
							get = function(info)
								if ShamanPower_ReactiveTotems then
									return ShamanPower_ReactiveTotems.glowIntensity or 0.8
								end
								return 0.8
							end,
							set = function(info, val)
								if ShamanPower_ReactiveTotems then
									ShamanPower_ReactiveTotems.glowIntensity = val
								end
							end
						},
						reactive_sound = {
							order = 14,
							name = "Play Alert Sound",
							desc = "Play a sound when a reactive totem icon appears",
							type = "toggle",
							width = 1.0,
							get = function(info)
								if ShamanPower_ReactiveTotems then
									return ShamanPower_ReactiveTotems.playSound or false
								end
								return false
							end,
							set = function(info, val)
								if ShamanPower_ReactiveTotems then
									ShamanPower_ReactiveTotems.playSound = val
								end
							end
						},
						reactive_sound_picker = {
							order = 14.1,
							name = "Alert Sound",
							desc = "Choose which sound to play for reactive totem alerts",
							type = "select",
							dialogControl = "LSM30_Sound",
							values = AceGUIWidgetLSMlists.sound,
							width = "double",
							disabled = function()
								if ShamanPower_ReactiveTotems then
									return not ShamanPower_ReactiveTotems.playSound
								end
								return true
							end,
							get = function()
								if ShamanPower_ReactiveTotems then
									return ShamanPower_ReactiveTotems.soundName or "Raid Warning"
								end
								return "Raid Warning"
							end,
							set = function(_, val)
								if ShamanPower_ReactiveTotems then
									ShamanPower_ReactiveTotems.soundName = val
								end
							end,
						},
						reactive_sound_picker_testsound = {
							order = 14.1 + 0.05,
							type = "execute",
							name = "Test Sound",
							desc = "Play the selected sound at the selected volume.",
							width = 0.7,
							disabled = function()
								if ShamanPower_ReactiveTotems then
									return not ShamanPower_ReactiveTotems.playSound
								end
								return true
							end,
							func = function()
								ShamanPower:PlaySoundWithVolume(ShamanPower:GetSoundFile(ShamanPower_ReactiveTotems and ShamanPower_ReactiveTotems.soundName or "Raid Warning"), ShamanPower_ReactiveTotems and ShamanPower_ReactiveTotems.soundVolume or 100, true)
							end,
						},
						reactive_sound_volume = {
							order = 14.3,
							name = "Sound Volume",
							desc = "Volume for reactive totem alert sounds",
							type = "range",
							min = 0,
							max = 100,
							step = 5,
							width = "full",
							disabled = function()
								if ShamanPower_ReactiveTotems then
									return not ShamanPower_ReactiveTotems.playSound
								end
								return true
							end,
							get = function(info)
								if ShamanPower_ReactiveTotems then
									return ShamanPower_ReactiveTotems.soundVolume or 100
								end
								return 100
							end,
							set = function(info, val)
								if ShamanPower_ReactiveTotems then
									ShamanPower_ReactiveTotems.soundVolume = val
								end
							end
						},
						reactive_sound_volume_note = {
							order = 14.4,
							type = "description",
							name = "|cff888888Must have Dialog sound at 100% for this slider to work.|r",
							width = "full",
						},
						reactive_font_outline = {
							order = 14.6,
							name = "Font Outline",
							desc = "Add outline to the text for better visibility",
							type = "toggle",
							width = 1.0,
							get = function(info)
								if ShamanPower_ReactiveTotems then
									return ShamanPower_ReactiveTotems.fontOutline ~= false
								end
								return true
							end,
							set = function(info, val)
								if ShamanPower_ReactiveTotems then
									ShamanPower_ReactiveTotems.fontOutline = val
									if ShamanPower.UpdateReactiveTotemAppearance then
										ShamanPower:UpdateReactiveTotemAppearance()
									end
								end
							end
						},
						reactive_header_buttons = {
							order = 15,
							type = "header",
							name = "Testing",
						},
						reactive_test = {
							order = 16,
							type = "execute",
							name = "Test All Frames",
							desc = "Show all reactive totem frames for 3 seconds with glow effect",
							func = function()
								if ShamanPower.TestReactiveTotems then
									ShamanPower:RunWithSettingsHidden(3.5, function() ShamanPower:TestReactiveTotems() end)
								end
							end
						},
						reactive_show = {
							order = 17,
							type = "execute",
							name = "Show All (Position)",
							desc = WithNotes("Show all frames for positioning - click-to-cast is disabled so you can drag freely",
								function() return ShamanPower_ReactiveTotems and ShamanPower_ReactiveTotems.locked end,
								"\"Lock Position\" is on, so the frames cannot be dragged. Turn it off, then ALT+drag."),
							func = function()
								if ShamanPower.ShowAllReactiveFrames then
									ShamanPower:RunWithSettingsHidden(nil,
										ShamanPower.ShowAllReactiveFrames, ShamanPower.HideAllReactiveFrames)
								end
							end
						},
						reactive_hide = {
							order = 18,
							type = "execute",
							name = "Hide All",
							desc = "Hide all frames and restore click-to-cast",
							func = function()
								if ShamanPower.HideAllReactiveFrames then
									ShamanPower:HideAllReactiveFrames()
								end
							end
						},
						reactive_reset = {
							order = 19,
							type = "execute",
							name = "Reset Positions",
							desc = "Reset all reactive totem frames to their default positions",
							func = function()
								if ShamanPower.ResetReactiveTotemPositions then
									ShamanPower:ResetReactiveTotemPositions()
								end
							end
						},
					}
				},
				expiringalerts_section = {
					order = 19,
					name = "|cff0070ddExpiring Alerts|r",
					type = "group",
					args = {
						master_off_note = {
							order = 0.05,
							type = "description",
							name = "|cffffa040Expiring Alerts is disabled, so nothing below fires - including Test Alerts.|r",
							hidden = function() return not (ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.enabled == false) end,
						},
						module_missing_note = {
							order = 0.01,
							type = "description",
							name = "|cffffa040This module is not loaded, so nothing on this page does anything right now (toggles may even snap back). Enable the ShamanPower [Expiring Alerts] addon in the AddOns list and /reload.|r",
							hidden = function() return not (not ShamanPower.ExpiringAlertsLoaded) end,
						},
						alerts_desc = {
							order = 0,
							type = "description",
							name = "Scrolling combat text style alerts when shields expire, totems are destroyed/expire, and weapon imbues fade.\n\n|cffff8800Note:|r Requires the |cff00ff00ShamanPower [Expiring Alerts]|r module to be enabled in your AddOns list.\n",
						},
						alerts_enabled = {
							order = 1,
							name = "Enable Expiring Alerts",
							desc = "Enable scrolling text alerts for expiring buffs",
							type = "toggle",
							width = 1.0,
							get = function(info)
								if ShamanPowerExpiringAlertsDB then
									return ShamanPowerExpiringAlertsDB.enabled ~= false
								end
								return true
							end,
							set = function(info, val)
								if ShamanPowerExpiringAlertsDB then
									ShamanPowerExpiringAlertsDB.enabled = val
										if ShamanPower.UpdateShieldSounds then ShamanPower:UpdateShieldSounds() end
								end
							end
						},
						alerts_header_display = {
							order = 2,
							type = "header",
							name = "Display Settings",
						},
						alerts_display_mode = {
							order = 3,
							name = "Display Mode",
							desc = "How to display alerts",
							type = "select",
							width = 1.0,
							values = {
								["text"] = "Text Only",
								["icon"] = "Icon Only",
								["both"] = "Icon + Text",
							},
							get = function(info)
								if ShamanPowerExpiringAlertsDB then
									return ShamanPowerExpiringAlertsDB.displayMode or "both"
								end
								return "both"
							end,
							set = function(info, val)
								if ShamanPowerExpiringAlertsDB then
									ShamanPowerExpiringAlertsDB.displayMode = val
								end
							end
						},
						alerts_animation = {
							order = 4,
							name = "Animation Style",
							desc = "How alerts animate on screen",
							type = "select",
							width = 1.0,
							values = {
								["scrollUp"] = "Scroll Up",
								["scrollDown"] = "Scroll Down",
								["staticFade"] = "Static Fade",
								["bounce"] = "Bounce",
							},
							get = function(info)
								if ShamanPowerExpiringAlertsDB then
									return ShamanPowerExpiringAlertsDB.animationStyle or "scrollUp"
								end
								return "scrollUp"
							end,
							set = function(info, val)
								if ShamanPowerExpiringAlertsDB then
									ShamanPowerExpiringAlertsDB.animationStyle = val
								end
							end
						},
						alerts_text_size = {
							hidden = function(info) return (ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.displayMode == "icon") and true or false end,
							order = 5,
							name = "Text Size",
							desc = "Size of alert text",
							type = "range",
							width = 1.5,
							min = 12,
							max = 36,
							step = 1,
							get = function(info)
								if ShamanPowerExpiringAlertsDB then
									return ShamanPowerExpiringAlertsDB.textSize or 24
								end
								return 24
							end,
							set = function(info, val)
								if ShamanPowerExpiringAlertsDB then
									ShamanPowerExpiringAlertsDB.textSize = val
									if ShamanPower.UpdateExpiringAlertsAppearance then
										ShamanPower:UpdateExpiringAlertsAppearance()
									end
								end
							end
						},
						alerts_icon_size = {
							hidden = function(info) return (ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.displayMode == "text") and true or false end,
							order = 6,
							name = "Icon Size",
							desc = "Size of alert icons",
							type = "range",
							width = 1.5,
							min = 24,
							max = 64,
							step = 2,
							get = function(info)
								if ShamanPowerExpiringAlertsDB then
									return ShamanPowerExpiringAlertsDB.iconSize or 32
								end
								return 32
							end,
							set = function(info, val)
								if ShamanPowerExpiringAlertsDB then
									ShamanPowerExpiringAlertsDB.iconSize = val
									if ShamanPower.UpdateExpiringAlertsAppearance then
										ShamanPower:UpdateExpiringAlertsAppearance()
									end
								end
							end
						},
						alerts_duration = {
							order = 7,
							name = "Duration",
							desc = "How long alerts stay on screen (seconds)",
							type = "range",
							width = 1.5,
							min = 1,
							max = 5,
							step = 0.5,
							get = function(info)
								if ShamanPowerExpiringAlertsDB then
									return ShamanPowerExpiringAlertsDB.duration or 2.5
								end
								return 2.5
							end,
							set = function(info, val)
								if ShamanPowerExpiringAlertsDB then
									ShamanPowerExpiringAlertsDB.duration = val
								end
							end
						},
						alerts_opacity = {
							order = 8,
							name = "Opacity",
							desc = "Opacity of alerts",
							type = "range",
							width = 1.5,
							min = 0.5,
							max = 1,
							step = 0.05,
							isPercent = true,   -- saved as 50-100
							get = function(info)
								if ShamanPowerExpiringAlertsDB then
									return (ShamanPowerExpiringAlertsDB.opacity or 100) / 100
								end
								return 1
							end,
							set = function(info, val)
								if ShamanPowerExpiringAlertsDB then
									ShamanPowerExpiringAlertsDB.opacity = math.floor(val * 100 + 0.5)
								end
							end
						},
						alerts_font_outline = {
							hidden = function(info) return (ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.displayMode == "icon") and true or false end,
							order = 9,
							name = "Font Outline",
							desc = "Add outline to text for better visibility",
							type = "toggle",
							width = 1.0,
							get = function(info)
								if ShamanPowerExpiringAlertsDB then
									return ShamanPowerExpiringAlertsDB.fontOutline ~= false
								end
								return true
							end,
							set = function(info, val)
								if ShamanPowerExpiringAlertsDB then
									ShamanPowerExpiringAlertsDB.fontOutline = val
									if ShamanPower.UpdateExpiringAlertsAppearance then
										ShamanPower:UpdateExpiringAlertsAppearance()
									end
								end
							end
						},
						alerts_header_shields = {
							order = 10,
							type = "header",
							name = "Shield Alerts",
						},
						alerts_shields_enabled = {
							order = 11,
							name = "Enable Shield Alerts",
							desc = "Show alerts when shields fade",
							type = "toggle",
							width = 1.0,
							get = function(info)
								if ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.shields then
									return ShamanPowerExpiringAlertsDB.shields.enabled ~= false
								end
								return true
							end,
							set = function(info, val)
								if ShamanPowerExpiringAlertsDB then
									if not ShamanPowerExpiringAlertsDB.shields then ShamanPowerExpiringAlertsDB.shields = {} end
									ShamanPowerExpiringAlertsDB.shields.enabled = val
										if ShamanPower.UpdateShieldSounds then ShamanPower:UpdateShieldSounds() end
								end
							end
						},
						alerts_shields_lightning = {
							disabled = function(info) return (not (ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.shields and ShamanPowerExpiringAlertsDB.shields.enabled ~= false)) and true or false end,
							order = 12,
							name = "Lightning Shield",
							desc = "Alert when Lightning Shield fades",
							type = "toggle",
							width = 1.0,
							get = function(info)
								if ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.shields then
									return ShamanPowerExpiringAlertsDB.shields.lightning ~= false
								end
								return true
							end,
							set = function(info, val)
								if ShamanPowerExpiringAlertsDB then
									if not ShamanPowerExpiringAlertsDB.shields then ShamanPowerExpiringAlertsDB.shields = {} end
									ShamanPowerExpiringAlertsDB.shields.lightning = val
										if ShamanPower.UpdateShieldSounds then ShamanPower:UpdateShieldSounds() end
								end
							end
						},
						alerts_shields_water = {
							disabled = function(info) return (not (ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.shields and ShamanPowerExpiringAlertsDB.shields.enabled ~= false)) and true or false end,
							order = 13,
							name = "Water Shield",
							desc = "Alert when Water Shield fades",
							type = "toggle",
							width = 1.0,
							get = function(info)
								if ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.shields then
									return ShamanPowerExpiringAlertsDB.shields.water ~= false
								end
								return true
							end,
							set = function(info, val)
								if ShamanPowerExpiringAlertsDB then
									if not ShamanPowerExpiringAlertsDB.shields then ShamanPowerExpiringAlertsDB.shields = {} end
									ShamanPowerExpiringAlertsDB.shields.water = val
										if ShamanPower.UpdateShieldSounds then ShamanPower:UpdateShieldSounds() end
								end
							end
						},
						alerts_shields_earth = {
							disabled = function(info) return (not (ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.shields and ShamanPowerExpiringAlertsDB.shields.enabled ~= false)) and true or false end,
							hidden = function(info) return (SPCompat and SPCompat.earthShieldExists == false) and true or false end,
							order = 14,
							name = "Earth Shield (on target)",
							desc = "Alert when Earth Shield fades on your assigned target",
							type = "toggle",
							width = 1.0,
							get = function(info)
								if ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.shields then
									return ShamanPowerExpiringAlertsDB.shields.earthShield ~= false
								end
								return true
							end,
							set = function(info, val)
								if ShamanPowerExpiringAlertsDB then
									if not ShamanPowerExpiringAlertsDB.shields then ShamanPowerExpiringAlertsDB.shields = {} end
									ShamanPowerExpiringAlertsDB.shields.earthShield = val
								end
							end
						},
						alerts_shields_sound = {
							disabled = function(info) return (not (ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.shields and ShamanPowerExpiringAlertsDB.shields.enabled ~= false)) and true or false end,
							order = 15,
							name = "Play Sound",
							desc = WithNotes("Play a sound when shield alerts appear.",
								function() return WOW_PROJECT_ID ~= nil and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE end, "On this client the game itself plays this sound the moment your shield's last charge is used, in combat too - the one place the addon cannot see the shield fall. Out of combat you get the on-screen alert as well."),
							type = "toggle",
							width = 1.0,
							get = function(info)
								if ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.shields then
									return ShamanPowerExpiringAlertsDB.shields.sound or false
								end
								return false
							end,
							set = function(info, val)
								if ShamanPowerExpiringAlertsDB then
									if not ShamanPowerExpiringAlertsDB.shields then ShamanPowerExpiringAlertsDB.shields = {} end
									ShamanPowerExpiringAlertsDB.shields.sound = val
										if ShamanPower.UpdateShieldSounds then ShamanPower:UpdateShieldSounds() end
								end
							end
						},
						alerts_shields_sound_picker = {
							order = 15.5,
							name = "Shield Alert Sound",
							desc = "Choose which sound to play for shield alerts",
							type = "select",
							dialogControl = "LSM30_Sound",
							values = AceGUIWidgetLSMlists.sound,
							width = "double",
							disabled = function()
								if ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.shields then
									return not ShamanPowerExpiringAlertsDB.shields.sound
								end
								return true
							end,
							get = function()
								if ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.shields then
									return ShamanPowerExpiringAlertsDB.shields.soundName or "Raid Warning"
								end
								return "Raid Warning"
							end,
							set = function(_, val)
								if ShamanPowerExpiringAlertsDB then
									if not ShamanPowerExpiringAlertsDB.shields then ShamanPowerExpiringAlertsDB.shields = {} end
									ShamanPowerExpiringAlertsDB.shields.soundName = val
										if ShamanPower.UpdateShieldSounds then ShamanPower:UpdateShieldSounds() end
								end
							end,
						},
						alerts_shields_sound_picker_testsound = {
							order = 15.5 + 0.05,
							type = "execute",
							name = "Test Sound",
							desc = "Play the selected sound at the selected volume.",
							width = 0.7,
							disabled = function()
								if ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.shields then
									return not ShamanPowerExpiringAlertsDB.shields.sound
								end
								return true
							end,
							func = function()
								ShamanPower:PlaySoundWithVolume(ShamanPower:GetSoundFile(ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.shields and ShamanPowerExpiringAlertsDB.shields.soundName or "Raid Warning"), ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.soundVolume or 100, true)
							end,
						},
						alerts_sound_volume = {
							order = 8.5,
							name = "Sound Volume",
							desc = "Volume for all expiring alert sounds (shields, totems, imbues)",
							type = "range",
							min = 0,
							max = 100,
							step = 5,
							width = 1.5,
							disabled = function()
								if ShamanPowerExpiringAlertsDB then
									local shieldSound = ShamanPowerExpiringAlertsDB.shields and ShamanPowerExpiringAlertsDB.shields.sound
									local totemSound = ShamanPowerExpiringAlertsDB.totems and ShamanPowerExpiringAlertsDB.totems.sound
									local imbueSound = ShamanPowerExpiringAlertsDB.weaponImbues and ShamanPowerExpiringAlertsDB.weaponImbues.sound
									return not (shieldSound or totemSound or imbueSound)
								end
								return true
							end,
							get = function(info)
								if ShamanPowerExpiringAlertsDB then
									return ShamanPowerExpiringAlertsDB.soundVolume or 100
								end
								return 100
							end,
							set = function(info, val)
								if ShamanPowerExpiringAlertsDB then
									ShamanPowerExpiringAlertsDB.soundVolume = val
								end
							end
						},
						alerts_sound_volume_note = {
							order = 8.6,
							type = "description",
							name = "|cff888888Must have Dialog sound at 100% for this slider to work.|r",
							width = "full",
						},
						alerts_header_totems = {
							order = 20,
							type = "header",
							name = "Totem Alerts",
						},
						alerts_totems_enabled = {
							order = 21,
							name = "Enable Totem Alerts",
							desc = "Show alerts when totems are destroyed or expire",
							type = "toggle",
							width = 1.0,
							get = function(info)
								if ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.totems then
									return ShamanPowerExpiringAlertsDB.totems.enabled ~= false
								end
								return true
							end,
							set = function(info, val)
								if ShamanPowerExpiringAlertsDB then
									if not ShamanPowerExpiringAlertsDB.totems then ShamanPowerExpiringAlertsDB.totems = {} end
									ShamanPowerExpiringAlertsDB.totems.enabled = val
								end
							end
						},
						alerts_totems_destroyed = {
							disabled = function(info) return (not (ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.totems and ShamanPowerExpiringAlertsDB.totems.enabled ~= false)) and true or false end,
							order = 22,
							name = "Totem Destroyed",
							desc = "Alert when a totem is destroyed by enemies",
							type = "toggle",
							width = 1.0,
							get = function(info)
								if ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.totems then
									return ShamanPowerExpiringAlertsDB.totems.destroyed ~= false
								end
								return true
							end,
							set = function(info, val)
								if ShamanPowerExpiringAlertsDB then
									if not ShamanPowerExpiringAlertsDB.totems then ShamanPowerExpiringAlertsDB.totems = {} end
									ShamanPowerExpiringAlertsDB.totems.destroyed = val
								end
							end
						},
						alerts_totems_destroyedChat = {
							order = 22.1, type = "toggle", width = "full",
							name = "Destroyed: Line in My Chat Window",
							desc = "When a totem is destroyed, add a line to your own chat window. Only you see it. Works in combat on WoW: Forever too.",
							disabled = function() local t = ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.totems; return not (t and t.enabled ~= false and t.destroyed ~= false) end,
							get = function() local t = ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.totems; return t and t.destroyedChat ~= false end,
							set = function(_, v)
								if not ShamanPowerExpiringAlertsDB then return end
								ShamanPowerExpiringAlertsDB.totems = ShamanPowerExpiringAlertsDB.totems or {}
								ShamanPowerExpiringAlertsDB.totems.destroyedChat = v
							end,
						},
						alerts_totems_destroyedCenter = {
							order = 22.2, type = "toggle", width = "full",
							name = "Destroyed: Big Text on My Screen",
							desc = "When a totem is destroyed, show big raid-warning-style text at the top of your screen. Drawn only on your screen; nothing is sent.",
							disabled = function() local t = ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.totems; return not (t and t.enabled ~= false and t.destroyed ~= false) end,
							get = function() local t = ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.totems; return t and t.destroyedCenter == true or false end,
							set = function(_, v)
								if not ShamanPowerExpiringAlertsDB then return end
								ShamanPowerExpiringAlertsDB.totems = ShamanPowerExpiringAlertsDB.totems or {}
								ShamanPowerExpiringAlertsDB.totems.destroyedCenter = v
							end,
						},
						alerts_totems_destroyedParty = {
							order = 22.3, type = "toggle", width = "full",
							name = "Destroyed: Tell My Group in Chat",
							desc = "When a totem is destroyed, say so in party, raid or instance chat so everyone sees it.",
							disabled = function() local t = ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.totems; return not (t and t.enabled ~= false and t.destroyed ~= false) end,
							get = function() local t = ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.totems; return t and t.destroyedParty == true or false end,
							set = function(_, v)
								if not ShamanPowerExpiringAlertsDB then return end
								ShamanPowerExpiringAlertsDB.totems = ShamanPowerExpiringAlertsDB.totems or {}
								ShamanPowerExpiringAlertsDB.totems.destroyedParty = v
							end,
						},
						alerts_totems_expired = {
							disabled = function(info) return (not (ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.totems and ShamanPowerExpiringAlertsDB.totems.enabled ~= false)) and true or false end,
							order = 23,
							name = "Totem Expired",
							desc = "Alert when a totem expires naturally (can be spammy)",
							type = "toggle",
							width = 1.0,
							get = function(info)
								if ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.totems then
									return ShamanPowerExpiringAlertsDB.totems.expired or false
								end
								return false
							end,
							set = function(info, val)
								if ShamanPowerExpiringAlertsDB then
									if not ShamanPowerExpiringAlertsDB.totems then ShamanPowerExpiringAlertsDB.totems = {} end
									ShamanPowerExpiringAlertsDB.totems.expired = val
								end
							end
						},
						alerts_totems_earth = {
							disabled = function(info) return (not (ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.totems and ShamanPowerExpiringAlertsDB.totems.enabled ~= false)) and true or false end,
							order = 24,
							name = "Earth Totems",
							desc = "Track Earth element totems",
							type = "toggle",
							width = 1.0,
							get = function(info)
								if ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.totems then
									return ShamanPowerExpiringAlertsDB.totems.earth ~= false
								end
								return true
							end,
							set = function(info, val)
								if ShamanPowerExpiringAlertsDB then
									if not ShamanPowerExpiringAlertsDB.totems then ShamanPowerExpiringAlertsDB.totems = {} end
									ShamanPowerExpiringAlertsDB.totems.earth = val
								end
							end
						},
						alerts_totems_fire = {
							disabled = function(info) return (not (ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.totems and ShamanPowerExpiringAlertsDB.totems.enabled ~= false)) and true or false end,
							order = 25,
							name = "Fire Totems",
							desc = "Track Fire element totems",
							type = "toggle",
							width = 1.0,
							get = function(info)
								if ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.totems then
									return ShamanPowerExpiringAlertsDB.totems.fire ~= false
								end
								return true
							end,
							set = function(info, val)
								if ShamanPowerExpiringAlertsDB then
									if not ShamanPowerExpiringAlertsDB.totems then ShamanPowerExpiringAlertsDB.totems = {} end
									ShamanPowerExpiringAlertsDB.totems.fire = val
								end
							end
						},
						alerts_totems_water = {
							disabled = function(info) return (not (ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.totems and ShamanPowerExpiringAlertsDB.totems.enabled ~= false)) and true or false end,
							order = 26,
							name = "Water Totems",
							desc = "Track Water element totems",
							type = "toggle",
							width = 1.0,
							get = function(info)
								if ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.totems then
									return ShamanPowerExpiringAlertsDB.totems.water ~= false
								end
								return true
							end,
							set = function(info, val)
								if ShamanPowerExpiringAlertsDB then
									if not ShamanPowerExpiringAlertsDB.totems then ShamanPowerExpiringAlertsDB.totems = {} end
									ShamanPowerExpiringAlertsDB.totems.water = val
								end
							end
						},
						alerts_totems_air = {
							disabled = function(info) return (not (ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.totems and ShamanPowerExpiringAlertsDB.totems.enabled ~= false)) and true or false end,
							order = 27,
							name = "Air Totems",
							desc = "Track Air element totems",
							type = "toggle",
							width = 1.0,
							get = function(info)
								if ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.totems then
									return ShamanPowerExpiringAlertsDB.totems.air ~= false
								end
								return true
							end,
							set = function(info, val)
								if ShamanPowerExpiringAlertsDB then
									if not ShamanPowerExpiringAlertsDB.totems then ShamanPowerExpiringAlertsDB.totems = {} end
									ShamanPowerExpiringAlertsDB.totems.air = val
								end
							end
						},
						alerts_totems_sound = {
							disabled = function(info) return (not (ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.totems and ShamanPowerExpiringAlertsDB.totems.enabled ~= false)) and true or false end,
							order = 28,
							name = "Play Sound",
							desc = "Play a sound when totem alerts appear",
							type = "toggle",
							width = 1.0,
							get = function(info)
								if ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.totems then
									return ShamanPowerExpiringAlertsDB.totems.sound or false
								end
								return false
							end,
							set = function(info, val)
								if ShamanPowerExpiringAlertsDB then
									if not ShamanPowerExpiringAlertsDB.totems then ShamanPowerExpiringAlertsDB.totems = {} end
									ShamanPowerExpiringAlertsDB.totems.sound = val
								end
							end
						},
						alerts_totems_sound_picker = {
							order = 28.5,
							name = "Totem Alert Sound",
							desc = "Choose which sound to play for totem alerts",
							type = "select",
							dialogControl = "LSM30_Sound",
							values = AceGUIWidgetLSMlists.sound,
							width = "double",
							disabled = function()
								if ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.totems then
									return not ShamanPowerExpiringAlertsDB.totems.sound
								end
								return true
							end,
							get = function()
								if ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.totems then
									return ShamanPowerExpiringAlertsDB.totems.soundName or "Alarm Clock Warning 3"
								end
								return "Alarm Clock Warning 3"
							end,
							set = function(_, val)
								if ShamanPowerExpiringAlertsDB then
									if not ShamanPowerExpiringAlertsDB.totems then ShamanPowerExpiringAlertsDB.totems = {} end
									ShamanPowerExpiringAlertsDB.totems.soundName = val
								end
							end,
						},
						alerts_totems_sound_picker_testsound = {
							order = 28.5 + 0.05,
							type = "execute",
							name = "Test Sound",
							desc = "Play the selected sound at the selected volume.",
							width = 0.7,
							disabled = function()
								if ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.totems then
									return not ShamanPowerExpiringAlertsDB.totems.sound
								end
								return true
							end,
							func = function()
								ShamanPower:PlaySoundWithVolume(ShamanPower:GetSoundFile(ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.totems and ShamanPowerExpiringAlertsDB.totems.soundName or "Alarm Clock Warning 3"), ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.soundVolume or 100, true)
							end,
						},
						alerts_header_imbues = {
							order = 30,
							type = "header",
							name = "Weapon Imbue Alerts",
						},
						alerts_imbues_enabled = {
							order = 31,
							name = "Enable Imbue Alerts",
							desc = "Show alerts when weapon imbues fade",
							type = "toggle",
							width = 1.0,
							get = function(info)
								if ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.weaponImbues then
									return ShamanPowerExpiringAlertsDB.weaponImbues.enabled ~= false
								end
								return true
							end,
							set = function(info, val)
								if ShamanPowerExpiringAlertsDB then
									if not ShamanPowerExpiringAlertsDB.weaponImbues then ShamanPowerExpiringAlertsDB.weaponImbues = {} end
									ShamanPowerExpiringAlertsDB.weaponImbues.enabled = val
								end
							end
						},
						alerts_imbues_mainhand = {
							disabled = function(info) return (not (ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.weaponImbues and ShamanPowerExpiringAlertsDB.weaponImbues.enabled ~= false)) and true or false end,
							order = 32,
							name = "Main Hand",
							desc = "Alert when main hand weapon imbue fades",
							type = "toggle",
							width = 1.0,
							get = function(info)
								if ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.weaponImbues then
									return ShamanPowerExpiringAlertsDB.weaponImbues.mainHand ~= false
								end
								return true
							end,
							set = function(info, val)
								if ShamanPowerExpiringAlertsDB then
									if not ShamanPowerExpiringAlertsDB.weaponImbues then ShamanPowerExpiringAlertsDB.weaponImbues = {} end
									ShamanPowerExpiringAlertsDB.weaponImbues.mainHand = val
								end
							end
						},
						alerts_imbues_offhand = {
							disabled = function(info) return (not (ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.weaponImbues and ShamanPowerExpiringAlertsDB.weaponImbues.enabled ~= false)) and true or false end,
							order = 33,
							name = "Off Hand",
							desc = "Alert when off hand weapon imbue fades",
							type = "toggle",
							width = 1.0,
							get = function(info)
								if ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.weaponImbues then
									return ShamanPowerExpiringAlertsDB.weaponImbues.offHand ~= false
								end
								return true
							end,
							set = function(info, val)
								if ShamanPowerExpiringAlertsDB then
									if not ShamanPowerExpiringAlertsDB.weaponImbues then ShamanPowerExpiringAlertsDB.weaponImbues = {} end
									ShamanPowerExpiringAlertsDB.weaponImbues.offHand = val
								end
							end
						},
						alerts_imbues_sound = {
							disabled = function(info) return (not (ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.weaponImbues and ShamanPowerExpiringAlertsDB.weaponImbues.enabled ~= false)) and true or false end,
							order = 34,
							name = "Play Sound",
							desc = "Play a sound when weapon imbue alerts appear",
							type = "toggle",
							width = 1.0,
							get = function(info)
								if ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.weaponImbues then
									return ShamanPowerExpiringAlertsDB.weaponImbues.sound or false
								end
								return false
							end,
							set = function(info, val)
								if ShamanPowerExpiringAlertsDB then
									if not ShamanPowerExpiringAlertsDB.weaponImbues then ShamanPowerExpiringAlertsDB.weaponImbues = {} end
									ShamanPowerExpiringAlertsDB.weaponImbues.sound = val
								end
							end
						},
						alerts_imbues_sound_picker = {
							order = 34.5,
							name = "Imbue Alert Sound",
							desc = "Choose which sound to play for weapon imbue alerts",
							type = "select",
							dialogControl = "LSM30_Sound",
							values = AceGUIWidgetLSMlists.sound,
							width = "double",
							disabled = function()
								if ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.weaponImbues then
									return not ShamanPowerExpiringAlertsDB.weaponImbues.sound
								end
								return true
							end,
							get = function()
								if ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.weaponImbues then
									return ShamanPowerExpiringAlertsDB.weaponImbues.soundName or "Raid Warning"
								end
								return "Raid Warning"
							end,
							set = function(_, val)
								if ShamanPowerExpiringAlertsDB then
									if not ShamanPowerExpiringAlertsDB.weaponImbues then ShamanPowerExpiringAlertsDB.weaponImbues = {} end
									ShamanPowerExpiringAlertsDB.weaponImbues.soundName = val
								end
							end,
						},
						alerts_imbues_sound_picker_testsound = {
							order = 34.5 + 0.05,
							type = "execute",
							name = "Test Sound",
							desc = "Play the selected sound at the selected volume.",
							width = 0.7,
							disabled = function()
								if ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.weaponImbues then
									return not ShamanPowerExpiringAlertsDB.weaponImbues.sound
								end
								return true
							end,
							func = function()
								ShamanPower:PlaySoundWithVolume(ShamanPower:GetSoundFile(ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.weaponImbues and ShamanPowerExpiringAlertsDB.weaponImbues.soundName or "Raid Warning"), ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.soundVolume or 100, true)
							end,
						},
						alerts_header_testing = {
							order = 40,
							type = "header",
							name = "Testing & Position",
						},
						alerts_test = {
							order = 41,
							type = "execute",
							name = "Test Alerts",
							desc = "Show test alerts for each type",
							func = function()
								if ShamanPower.ExpiringAlertsTest then
									local sv = ShamanPowerExpiringAlertsDB
									local style = sv and sv.animationStyle or "scrollUp"
									local duration = sv and sv.duration or 2.5
									-- Fade duration PLUS its start delay, then the final sample at 1 s.
									local span = duration * (style == "staticFade" and 1.3 or style == "bounce" and 1.5 or 1.4)
									-- Preview release clears demo alerts; real queued alerts finish first.
									local backlog = 0
									if not ShamanPower.expiringAlertsDemoActive then
										backlog = #(ShamanPower.activeAlerts or {}) + #(ShamanPower.alertQueue or {})
									end
									ShamanPower:RunWithSettingsHidden(1 + span * (1 + math.ceil(backlog / 3)),
										ShamanPower.ExpiringAlertsTest)
								end
							end
						},
						alerts_show_pos = {
							order = 42,
							type = "execute",
							name = "Show Position Frame",
							desc = "Show the positioning frame to drag alerts to a new location",
							func = function()
								if ShamanPower.ExpiringAlertsShow then
									ShamanPower:RunWithSettingsHidden(nil,
										ShamanPower.ExpiringAlertsShow, ShamanPower.ExpiringAlertsHide)
								end
							end
						},
						alerts_hide_pos = {
							order = 43,
							type = "execute",
							name = "Hide Position Frame",
							desc = "Hide the positioning frame",
							func = function()
								if ShamanPower.ExpiringAlertsHide then
									ShamanPower:ExpiringAlertsHide()
								end
								ShamanPower:SettingsTestDone()
							end
						},
						alerts_reset_pos = {
							order = 44,
							type = "execute",
							name = "Reset Position",
							desc = "Reset alert position to default (center of screen)",
							func = function()
								if ShamanPower.ExpiringAlertsReset then
									ShamanPower:ExpiringAlertsReset()
								end
							end
						},
					}
				},
				tremorreminder_section = {
					order = 19.5,
					name = "|cff0070ddTremor Reminder|r",
					type = "group",
					args = {
						master_off_note = {
							order = 0.05,
							type = "description",
							name = "|cffffa040Tremor Reminder is disabled, so these settings only show up in Test Alert.|r",
							hidden = function() return not (ShamanPowerTremorReminderDB and ShamanPowerTremorReminderDB.enabled == false) end,
						},
						module_missing_note = {
							order = 0.01,
							type = "description",
							name = "|cffffa040This module is not loaded, so nothing on this page does anything right now (toggles may even snap back). Enable the ShamanPower [Tremor Reminder] addon in the AddOns list and /reload.|r",
							hidden = function() return not (not ShamanPower.TremorReminderLoaded) end,
						},
						tremor_desc = {
							order = 0,
							type = "description",
							name = "Proactive Tremor Totem reminder when targeting fear-casting mobs. Shows a reminder icon before anyone in your party gets feared.\n\n|cffff8800Note:|r Requires the |cff00ff00ShamanPower [Tremor Reminder]|r module to be enabled in your AddOns list.\n",
						},
						tremor_enabled = {
							order = 1,
							name = "Enable Tremor Reminder",
							desc = "Show reminder when targeting known fear-casting mobs",
							type = "toggle",
							width = "full",
							get = function(info)
								if ShamanPowerTremorReminderDB then
									return ShamanPowerTremorReminderDB.enabled ~= false
								end
								return true
							end,
							set = function(info, val)
								if ShamanPowerTremorReminderDB then
									ShamanPowerTremorReminderDB.enabled = val
								end
							end
						},
						tremor_hide_when_active = {
							order = 2,
							name = "Hide When Tremor Active",
							desc = "Hide the reminder when Tremor Totem is already placed",
							type = "toggle",
							width = "full",
							get = function(info)
								if ShamanPowerTremorReminderDB then
									return ShamanPowerTremorReminderDB.hideWhenTremorActive ~= false
								end
								return true
							end,
							set = function(info, val)
								if ShamanPowerTremorReminderDB then
									ShamanPowerTremorReminderDB.hideWhenTremorActive = val
								end
							end
						},
						tremor_use_defaults = {
							order = 3,
							name = "Use Default Mob List",
							desc = function()
								if WOW_PROJECT_ID == WOW_PROJECT_MAINLINE then
									return "Include the built-in list of fear-casting dungeon and raid mobs"
								end
								return "Include the built-in list of TBC fear-casting mobs"
							end,
							type = "toggle",
							width = "full",
							get = function(info)
								if ShamanPowerTremorReminderDB then
									return ShamanPowerTremorReminderDB.useDefaultList ~= false
								end
								return true
							end,
							set = function(info, val)
								if ShamanPowerTremorReminderDB then
									ShamanPowerTremorReminderDB.useDefaultList = val
								end
							end
						},
						tremor_display_mode = {
							order = 4,
							name = "Display Mode",
							desc = "How to display the reminder",
							type = "select",
							width = 1.5,
							values = {
								icon = "Icon Only",
								text = "Text Only",
								both = "Icon + Text",
							},
							get = function(info)
								if ShamanPowerTremorReminderDB then
									return ShamanPowerTremorReminderDB.displayMode or "icon"
								end
								return "icon"
							end,
							set = function(info, val)
								if ShamanPowerTremorReminderDB then
									ShamanPowerTremorReminderDB.displayMode = val
									if ShamanPower.UpdateTremorReminderAppearance then
										ShamanPower:UpdateTremorReminderAppearance()
									end
								end
							end
						},
						tremor_manage_mobs = {
							order = 5,
							type = "execute",
							name = "Manage Mob List",
							desc = "Open the fear-caster mob list manager to add or remove mobs",
							func = function()
								if ShamanPower.ShowMobList then
									ShamanPower:ShowMobList()
								else
									print("|cff0070ddShamanPower:|r Tremor Reminder module not loaded.")
								end
							end
						},
						tremor_header_appearance = {
							order = 10,
							type = "header",
							name = "Appearance",
						},
						tremor_icon_size = {
							order = 11,
							name = "Icon Size",
							desc = WithNotes("Size of the reminder icon",
								function() return ShamanPowerTremorReminderDB and ShamanPowerTremorReminderDB.displayMode == "text" end, "Display Mode is Text only, which has no icon and no glow, so this does nothing right now."),
							type = "range",
							min = 32,
							max = 256,
							step = 1,
							width = 1.5,
							get = function(info)
								if ShamanPowerTremorReminderDB then
									return ShamanPowerTremorReminderDB.iconSize or 64
								end
								return 64
							end,
							set = function(info, val)
								if ShamanPowerTremorReminderDB then
									ShamanPowerTremorReminderDB.iconSize = val
									if ShamanPower.UpdateTremorReminderAppearance then
										ShamanPower:UpdateTremorReminderAppearance()
									end
								end
							end
						},
						tremor_opacity = {
							order = 13,
							name = "Opacity",
							desc = "Opacity of the reminder icon",
							type = "range",
							min = 0.5,
							max = 1,
							step = 0.05,
							isPercent = true,   -- saved as 50-100
							width = 1.5,
							get = function(info)
								if ShamanPowerTremorReminderDB then
									return (ShamanPowerTremorReminderDB.opacity or 100) / 100
								end
								return 1
							end,
							set = function(info, val)
								if ShamanPowerTremorReminderDB then
									ShamanPowerTremorReminderDB.opacity = math.floor(val * 100 + 0.5)
									if ShamanPower.UpdateTremorReminderAppearance then
										ShamanPower:UpdateTremorReminderAppearance()
									end
								end
							end
						},
						tremor_text_size = {
							order = 14,
							name = "Font Size",
							desc = "Size of the reminder text (for Text or Icon+Text modes)",
							type = "range",
							min = 12,
							max = 48,
							step = 1,
							width = 1.5,
							get = function(info)
								if ShamanPowerTremorReminderDB then
									return ShamanPowerTremorReminderDB.textSize or 24
								end
								return 24
							end,
							set = function(info, val)
								if ShamanPowerTremorReminderDB then
									ShamanPowerTremorReminderDB.textSize = val
									if ShamanPower.UpdateTremorReminderAppearance then
										ShamanPower:UpdateTremorReminderAppearance()
									end
								end
							end
						},
						tremor_header_glow = {
							order = 20,
							type = "header",
							name = "Glow Effect",
						},
						tremor_show_glow = {
							order = 21,
							name = "Show Glow",
							desc = WithNotes("Show a pulsing glow effect around the icon",
								function() return ShamanPowerTremorReminderDB and ShamanPowerTremorReminderDB.displayMode == "text" end, "Display Mode is Text only, which has no icon and no glow, so this does nothing right now."),
							type = "toggle",
							width = 1.0,
							get = function(info)
								if ShamanPowerTremorReminderDB then
									return ShamanPowerTremorReminderDB.showGlow ~= false
								end
								return true
							end,
							set = function(info, val)
								if ShamanPowerTremorReminderDB then
									ShamanPowerTremorReminderDB.showGlow = val
									if ShamanPower.UpdateTremorReminderAppearance then
										ShamanPower:UpdateTremorReminderAppearance()
									end
								end
							end
						},
						tremor_glow_color = {
							disabled = function(info) return (ShamanPowerTremorReminderDB and ShamanPowerTremorReminderDB.showGlow == false) and true or false end,
							order = 22,
							name = "Glow Color",
							desc = WithNotes("Color of the glow effect",
								function() return ShamanPowerTremorReminderDB and ShamanPowerTremorReminderDB.displayMode == "text" end, "Display Mode is Text only, which has no icon and no glow, so this does nothing right now."),
							type = "color",
							width = 1.0,
							get = function(info)
								if ShamanPowerTremorReminderDB and ShamanPowerTremorReminderDB.glowColor then
									return ShamanPowerTremorReminderDB.glowColor.r or 1,
									       ShamanPowerTremorReminderDB.glowColor.g or 0.8,
									       ShamanPowerTremorReminderDB.glowColor.b or 0
								end
								return 1, 0.8, 0
							end,
							set = function(info, r, g, b)
								if ShamanPowerTremorReminderDB then
									if not ShamanPowerTremorReminderDB.glowColor then
										ShamanPowerTremorReminderDB.glowColor = {}
									end
									ShamanPowerTremorReminderDB.glowColor.r = r
									ShamanPowerTremorReminderDB.glowColor.g = g
									ShamanPowerTremorReminderDB.glowColor.b = b
									if ShamanPower.UpdateTremorReminderAppearance then
										ShamanPower:UpdateTremorReminderAppearance()
									end
								end
							end
						},
						tremor_header_sound = {
							order = 30,
							type = "header",
							name = "Sound",
						},
						tremor_play_sound = {
							order = 31,
							name = "Play Sound",
							desc = "Play a warning sound when targeting a fear-caster",
							type = "toggle",
							width = "full",
							get = function(info)
								if ShamanPowerTremorReminderDB then
									return ShamanPowerTremorReminderDB.playSound or false
								end
								return false
							end,
							set = function(info, val)
								if ShamanPowerTremorReminderDB then
									ShamanPowerTremorReminderDB.playSound = val
								end
							end
						},
						tremor_sound_picker = {
							order = 31.5,
							name = "Alert Sound",
							desc = "Choose which sound to play for tremor reminders",
							type = "select",
							dialogControl = "LSM30_Sound",
							values = AceGUIWidgetLSMlists.sound,
							width = "double",
							disabled = function()
								if ShamanPowerTremorReminderDB then
									return not ShamanPowerTremorReminderDB.playSound
								end
								return true
							end,
							get = function()
								if ShamanPowerTremorReminderDB then
									return ShamanPowerTremorReminderDB.soundName or "Raid Warning"
								end
								return "Raid Warning"
							end,
							set = function(_, val)
								if ShamanPowerTremorReminderDB then
									ShamanPowerTremorReminderDB.soundName = val
								end
							end,
						},
						tremor_sound_picker_testsound = {
							order = 31.5 + 0.05,
							type = "execute",
							name = "Test Sound",
							desc = "Play the selected sound at the selected volume.",
							width = 0.7,
							disabled = function()
								if ShamanPowerTremorReminderDB then
									return not ShamanPowerTremorReminderDB.playSound
								end
								return true
							end,
							func = function()
								ShamanPower:PlaySoundWithVolume(ShamanPower:GetSoundFile(ShamanPowerTremorReminderDB and ShamanPowerTremorReminderDB.soundName or "Raid Warning"), ShamanPowerTremorReminderDB and ShamanPowerTremorReminderDB.soundVolume or 100, true)
							end,
						},
						tremor_sound_volume = {
							order = 32,
							name = "Sound Volume",
							desc = "Volume for tremor reminder sounds",
							type = "range",
							min = 0,
							max = 100,
							step = 5,
							width = "full",
							disabled = function()
								if ShamanPowerTremorReminderDB then
									return not ShamanPowerTremorReminderDB.playSound
								end
								return true
							end,
							get = function(info)
								if ShamanPowerTremorReminderDB then
									return ShamanPowerTremorReminderDB.soundVolume or 100
								end
								return 100
							end,
							set = function(info, val)
								if ShamanPowerTremorReminderDB then
									ShamanPowerTremorReminderDB.soundVolume = val
								end
							end
						},
						tremor_sound_volume_note = {
							order = 33,
							type = "description",
							name = "|cff888888Must have Dialog sound at 100% for this slider to work.|r",
							width = "full",
						},
						tremor_header_commands = {
							order = 40,
							type = "header",
							name = "Commands",
						},
						tremor_commands_desc = {
							order = 41,
							type = "description",
							name = "|cff888888Slash Commands:|r\n" ..
							       "  /sptremor show - Show frame for positioning\n" ..
							       "  /sptremor test - Show test alert\n" ..
							       "  /sptremor reset - Reset position\n" ..
							       "  /sptremor add <mob> - Add mob to list\n" ..
							       "  /sptremor remove <mob> - Remove mob\n" ..
							       "  /sptremor list - Show all fear-casters\n",
						},
						tremor_test = {
							order = 42,
							type = "execute",
							name = "Test Alert",
							desc = "Show a test alert",
							func = function()
								if ShamanPower.TremorReminderTest then
									ShamanPower:RunWithSettingsHidden(nil,
										ShamanPower.TremorReminderTest, ShamanPower.TremorReminderHide)
								end
							end
						},
						tremor_hide_test = {
							order = 42.5,
							type = "execute",
							name = "Hide Alert",
							desc = "Hide the test alert",
							func = function()
								if ShamanPower.TremorReminderHide then
									ShamanPower:TremorReminderHide()
								end
								ShamanPower:SettingsTestDone()
							end
						},
						tremor_show_pos = {
							order = 43,
							type = "execute",
							name = "Show Position Frame",
							desc = "Show the positioning frame to drag to a new location",
							func = function()
								if ShamanPower.TremorReminderShow then
									ShamanPower:RunWithSettingsHidden(nil,
										ShamanPower.TremorReminderShow, ShamanPower.TremorReminderHide)
								end
							end
						},
						tremor_reset_pos = {
							order = 44,
							type = "execute",
							name = "Reset Position",
							desc = "Reset position to default (center of screen)",
							func = function()
								if ShamanPower.TremorReminderReset then
									ShamanPower:TremorReminderReset()
								end
							end
						},
						tremor_lock_pos = {
							order = 45,
							name = "Lock Position",
							desc = "Prevent moving the frame with ALT+drag",
							type = "toggle",
							width = "full",
							get = function(info)
								if ShamanPowerTremorReminderDB then
									return ShamanPowerTremorReminderDB.locked ~= false
								end
								return true
							end,
							set = function(info, val)
								if ShamanPowerTremorReminderDB then
									ShamanPowerTremorReminderDB.locked = val
								end
							end
						},
						tremor_reset_moblist = {
							order = 46,
							type = "execute",
							width = "full",
							name = "Reset Mob List to Defaults",
							desc = "Remove all custom mobs and restore all removed default mobs",
							confirm = true,
							confirmText = "Are you sure you want to reset the mob list to defaults? This will remove all custom mobs you added and restore any default mobs you removed.",
							func = function()
								if ShamanPowerTremorReminderDB then
									ShamanPowerTremorReminderDB.fearCasters = {}
									if ShamanPower.RefreshMobList then
										ShamanPower:RefreshMobList()
									end
									print("|cff0070ddShamanPower|r [Tremor Reminder]: Mob list reset to defaults.")
								end
							end
						},
					}
				},
				totembar_items_section = {
					order = 7,
					name = "Totem Bar Items",
					type = "group",
					args = {
						totembar_desc = {
							order = 0,
							type = "description",
							name = "Choose which buttons appear on the mini totem bar.",
						},
						totembar_hide_unlearned = {
							order = 0.5,
							name = "Only Show Learned Elements",
							desc = "Hide an element's button until you have learned a totem for it. A new shaman starts with Earth and gains Fire, Water and Air as they level; the bar grows with them. Turn off to always show all four.",
							type = "toggle",
							width = "full",
							disabled = function(info)
								return ShamanPower.opt.enabled == false
							end,
							get = function(info)
								return ShamanPower.opt.hideUnlearnedElements ~= false
							end,
							set = function(info, val)
								ShamanPower.opt.hideUnlearnedElements = val
								ShamanPower:InvalidateElementLearned()
								ShamanPower:UpdateLayout()
							end
						},
						totembar_show_earth = {
							order = 1,
							type = "toggle",
							name = "Show Earth Totem",
							desc = "Show Earth totem button on the mini totem bar",
							width = "full",
							get = function(info)
								return ShamanPower.opt.totemBarShowEarth ~= false
							end,
							set = function(info, val)
								ShamanPower.opt.totemBarShowEarth = val
								ShamanPower:UpdateMiniTotemBar()
							end
						},
						totembar_show_fire = {
							order = 2,
							type = "toggle",
							name = "Show Fire Totem",
							desc = "Show Fire totem button on the mini totem bar",
							width = "full",
							get = function(info)
								return ShamanPower.opt.totemBarShowFire ~= false
							end,
							set = function(info, val)
								ShamanPower.opt.totemBarShowFire = val
								ShamanPower:UpdateMiniTotemBar()
							end
						},
						totembar_show_water = {
							order = 3,
							type = "toggle",
							name = "Show Water Totem",
							desc = "Show Water totem button on the mini totem bar",
							width = "full",
							get = function(info)
								return ShamanPower.opt.totemBarShowWater ~= false
							end,
							set = function(info, val)
								ShamanPower.opt.totemBarShowWater = val
								ShamanPower:UpdateMiniTotemBar()
							end
						},
						totembar_show_air = {
							order = 4,
							type = "toggle",
							name = "Show Air Totem",
							desc = "Show Air totem button on the mini totem bar",
							width = "full",
							get = function(info)
								return ShamanPower.opt.totemBarShowAir ~= false
							end,
							set = function(info, val)
								ShamanPower.opt.totemBarShowAir = val
								ShamanPower:UpdateMiniTotemBar()
							end
						},
						totembar_show_earthshield = {
							hidden = function(info) return (SPCompat and SPCompat.earthShieldExists == false) and true or false end,
							order = 5,
							type = "toggle",
							name = "Show Earth Shield",
							desc = "Show Earth Shield button on the mini totem bar (if you have the talent)",
							width = "full",
							get = function(info)
								return ShamanPower.opt.totemBarShowEarthShield ~= false
							end,
							set = function(info, val)
								ShamanPower.opt.totemBarShowEarthShield = val
								ShamanPower:UpdateEarthShieldButton()
							end
						},
					}
				},
				totembar_order_section = {
					order = 8,
					name = "Totem Bar Order",
					type = "group",
					args = {
						totembar_order_desc = {
							order = 0,
							type = "description",
							name = "Choose the order of totem buttons on the mini totem bar.",
						},
						totem_bar_order_1 = {
							order = 1,
							type = "select",
							name = "1st Position",
							desc = "First totem button position",
							width = 1.2,
							values = {
								[1] = "Earth",
								[2] = "Fire",
								[3] = "Water",
								[4] = "Air",
							},
							get = function(info)
								return ShamanPower.opt.totemBarOrder and ShamanPower.opt.totemBarOrder[1] or 1
							end,
							set = function(info, val)
								if not ShamanPower.opt.totemBarOrder then ShamanPower.opt.totemBarOrder = {1, 2, 3, 4} end
								for i = 2, 4 do
									if ShamanPower.opt.totemBarOrder[i] == val then
										ShamanPower.opt.totemBarOrder[i] = ShamanPower.opt.totemBarOrder[1]
										break
									end
								end
								ShamanPower.opt.totemBarOrder[1] = val
								ShamanPower:UpdateMiniTotemBar()
							end
						},
						totem_bar_order_2 = {
							order = 2,
							type = "select",
							name = "2nd Position",
							desc = "Second totem button position",
							width = 1.2,
							values = {
								[1] = "Earth",
								[2] = "Fire",
								[3] = "Water",
								[4] = "Air",
							},
							get = function(info)
								return ShamanPower.opt.totemBarOrder and ShamanPower.opt.totemBarOrder[2] or 2
							end,
							set = function(info, val)
								if not ShamanPower.opt.totemBarOrder then ShamanPower.opt.totemBarOrder = {1, 2, 3, 4} end
								for i = 1, 4 do
									if i ~= 2 and ShamanPower.opt.totemBarOrder[i] == val then
										ShamanPower.opt.totemBarOrder[i] = ShamanPower.opt.totemBarOrder[2]
										break
									end
								end
								ShamanPower.opt.totemBarOrder[2] = val
								ShamanPower:UpdateMiniTotemBar()
							end
						},
						totem_bar_order_3 = {
							order = 3,
							type = "select",
							name = "3rd Position",
							desc = "Third totem button position",
							width = 1.2,
							values = {
								[1] = "Earth",
								[2] = "Fire",
								[3] = "Water",
								[4] = "Air",
							},
							get = function(info)
								return ShamanPower.opt.totemBarOrder and ShamanPower.opt.totemBarOrder[3] or 3
							end,
							set = function(info, val)
								if not ShamanPower.opt.totemBarOrder then ShamanPower.opt.totemBarOrder = {1, 2, 3, 4} end
								for i = 1, 4 do
									if i ~= 3 and ShamanPower.opt.totemBarOrder[i] == val then
										ShamanPower.opt.totemBarOrder[i] = ShamanPower.opt.totemBarOrder[3]
										break
									end
								end
								ShamanPower.opt.totemBarOrder[3] = val
								ShamanPower:UpdateMiniTotemBar()
							end
						},
						totem_bar_order_4 = {
							order = 4,
							type = "select",
							name = "4th Position",
							desc = "Fourth totem button position",
							width = 1.2,
							values = {
								[1] = "Earth",
								[2] = "Fire",
								[3] = "Water",
								[4] = "Air",
							},
							get = function(info)
								return ShamanPower.opt.totemBarOrder and ShamanPower.opt.totemBarOrder[4] or 4
							end,
							set = function(info, val)
								if not ShamanPower.opt.totemBarOrder then ShamanPower.opt.totemBarOrder = {1, 2, 3, 4} end
								for i = 1, 3 do
									if ShamanPower.opt.totemBarOrder[i] == val then
										ShamanPower.opt.totemBarOrder[i] = ShamanPower.opt.totemBarOrder[4]
										break
									end
								end
								ShamanPower.opt.totemBarOrder[4] = val
								ShamanPower:UpdateMiniTotemBar()
							end
						},
					}
				},
				totembar_duration_section = {
					order = 9,
					name = "Totem Duration Bars",
					type = "group",
					args = {
						compact_override_note = {
							order = 0.05,
							type = "description",
							name = "|cffffa040Compact style is on. It draws duration and pulse itself, so nothing on this page applies to the totem bar right now (only the cooldown sweep on flyout icons still does). Use the Compact Style options in Mode & Twisting instead.|r",
							hidden = function() return not (CompactOn()) end,
						},
						duration_desc = {
							order = 0,
							type = "description",
							name = "Show progress bars on totem buttons indicating remaining duration.",
						},
						duration_bar_position = {
							disabled = function(info) return (CompactOn()) and true or false end,
							order = 1,
							type = "select",
							name = "Bar Position",
							desc = "Position of the duration bar relative to totem icons (or None to disable)",
							width = 1.1,
							values = {
								["none"] = "None (Disabled)",
								["bottom"] = "Bottom (Horizontal)",
								["bottom_vert"] = "Bottom (Vertical)",
								["top"] = "Top (Horizontal)",
								["top_vert"] = "Top (Vertical)",
								["left"] = "Left",
								["right"] = "Right",
							},
							get = function(info)
								return ShamanPower.opt.durationBarPosition or "bottom"
							end,
							set = function(info, val)
								ShamanPower.opt.durationBarPosition = val
								ShamanPower:UpdateTotemProgressBarPositions()
								ShamanPower:UpdateMiniTotemBar()
							end
						},
						duration_bar_height = {
							disabled = function(info) return (CompactOn()) and true or false end,
							order = 2,
							type = "range",
							name = "Bar Size",
							desc = "Size of the duration bar (height for horizontal bars, width for vertical bars)",
							width = 0.8,
							min = 2,
							max = 26,
							step = 1,
							hidden = function()
								return ShamanPower.opt.durationBarPosition == "none"
							end,
							get = function(info)
								return ShamanPower.opt.durationBarHeight or 3
							end,
							set = function(info, val)
								ShamanPower.opt.durationBarHeight = val
								ShamanPower:UpdateTotemProgressBarHeight()
							end
						},
						show_duration_text = {
							disabled = function(info) return (CompactOn()) and true or false end,
							order = 3,
							type = "select",
							name = "Show Duration",
							desc = "Where to show the remaining totem duration time",
							width = 1.1,
							values = {
								["none"] = "None",
								["inside_top"] = "Inside Bar (Top)",
								["inside_bottom"] = "Inside Bar (Bottom)",
								["above"] = "Above Bar",
								["below"] = "Below Bar",
								["icon"] = "On Icon",
							},
							get = function(info)
								return ShamanPower.opt.durationTextLocation or "none"
							end,
							set = function(info, val)
								ShamanPower.opt.durationTextLocation = val
								ShamanPower:UpdateTotemProgressBarPositions()
								ShamanPower:UpdateTotemProgressBars()
							end
						},
						duration_text_size = {
							disabled = function(info) return (CompactOn()) and true or false end,
							order = 3.5,
							type = "range",
							name = "Duration Text Size",
							desc = "Font size for the duration time text",
							width = 1.0,
							min = 6,
							max = 20,
							step = 1,
							hidden = function()
								return ShamanPower.opt.durationTextLocation == "none" or ShamanPower.opt.durationTextLocation == nil
							end,
							get = function(info)
								return ShamanPower.opt.durationTextSize or 8
							end,
							set = function(info, val)
								ShamanPower.opt.durationTextSize = val
								ShamanPower:UpdateTotemProgressBarPositions()
								ShamanPower:UpdateTotemProgressBars()
							end
						},
						show_totem_cooldowns = {
							order = 3.7,
							type = "toggle",
							name = "Show Totem Cooldowns",
							desc = function()
								local elementals = ", Elementals"
								if WOW_PROJECT_ID == WOW_PROJECT_MAINLINE
									and SPCompat and SPCompat.SpellExists and not SPCompat.SpellExists(2894) then
									elementals = ""
								end
								return "Show cooldown swipe and remaining time on totems that have cooldowns"
									.. " (Grounding, Mana Tide" .. elementals
									.. ", etc). Displays on both the main totem button and in the flyout menu."
							end,
							width = "full",
							get = function(info)
								return ShamanPower.opt.showTotemCooldowns ~= false
							end,
							set = function(info, val)
								ShamanPower.opt.showTotemCooldowns = val
								ShamanPower:SetupTotemProgressBars()  -- Re-enable/disable the update subsystem
								if not val and ShamanPower.ClearEngineCooldowns then ShamanPower:ClearEngineCooldowns() end
							end
						},
						totem_cooldown_sweep = {
							order = 3.75,
							type = "select",
							name = "Cooldown Style",
							desc = "How a totem's spell cooldown is drawn on its button: the classic radial swipe, or the vertical grey sweep the cooldown bar uses.",
							width = 1.0,
							values = {
								["radial"] = "Radial Swipe",
								["vertical"] = "Vertical Sweep (greys out)",
								["reverse"] = "Vertical Sweep (fills back in)",
							},
							disabled = function()
								return ShamanPower.opt.showTotemCooldowns == false
							end,
							get = function(info)
								return ShamanPower.opt.totemCooldownSweep or "radial"
							end,
							set = function(info, val)
								ShamanPower.opt.totemCooldownSweep = val
								ShamanPower:UpdateTotemCooldowns()
							end
						},
						totem_cooldown_edge = {
							order = 3.76,
							type = "toggle",
							name = "Radial Edge Line",
							desc = "The bright line that travels around the icon with the radial swipe. Off for a plain dark swipe.",
							width = 1.0,
							disabled = function()
								return ShamanPower.opt.showTotemCooldowns == false or (ShamanPower.opt.totemCooldownSweep or "radial") ~= "radial"
							end,
							get = function(info)
								return ShamanPower.opt.totemCooldownEdge ~= false
							end,
							set = function(info, val)
								ShamanPower.opt.totemCooldownEdge = val
								if ShamanPower.ClearEngineCooldowns then ShamanPower:ClearEngineCooldowns() end   -- re-fed with the new edge setting
								ShamanPower:UpdateTotemCooldowns()
							end
						},
						totem_cooldown_text = {
							order = 3.78,
							type = "toggle",
							name = "Show Cooldown Time",
							desc = "Show the remaining time as a number on the totem. Turn off for just the swipe.",
							width = "full",
							disabled = function()
								return ShamanPower.opt.showTotemCooldowns == false
							end,
							get = function(info)
								return ShamanPower.opt.totemCooldownText ~= false
							end,
							set = function(info, val)
								ShamanPower.opt.totemCooldownText = val
								if val and ShamanPower.EnableCountdownNumbers then ShamanPower:EnableCountdownNumbers() end
								ShamanPower:UpdateTotemCooldowns()
							end
						},
						totem_cooldown_numbers_note = {
							order = 3.785,
							type = "description",
							name = "|cffffa040On this client the time is drawn by the game, and WoW's own \"Show Numbers for Cooldowns\" setting is off, so nothing can show.|r",
							hidden = function()
								return not (ShamanPower.EngineCooldownsOn and ShamanPower:EngineCooldownsOn() and ShamanPower.opt.showTotemCooldowns ~= false
									and ShamanPower.opt.totemCooldownText ~= false and not ShamanPower:CountdownNumbersEnabled())
							end,
						},
						totem_cooldown_numbers_button = {
							order = 3.786,
							type = "execute",
							name = "Turn on Show Numbers for Cooldowns",
							desc = "Turns on WoW's own cooldown numbers (Options > Action Bars). They then show on your action bars as well.",
							width = 1.6,
							hidden = function()
								return not (ShamanPower.EngineCooldownsOn and ShamanPower:EngineCooldownsOn() and ShamanPower.opt.showTotemCooldowns ~= false
									and ShamanPower.opt.totemCooldownText ~= false and not ShamanPower:CountdownNumbersEnabled())
							end,
							func = function() ShamanPower:EnableCountdownNumbers() end,
						},
						totem_cooldown_text_color = {
							order = 3.8,
							type = "color",
							name = "Cooldown Text Color",
							desc = "Color of the cooldown remaining time text on totem buttons",
							width = 1.0,
							disabled = function()
								return ShamanPower.opt.showTotemCooldowns == false or ShamanPower.opt.totemCooldownText == false
							end,
							get = function(info)
								local c = ShamanPower.opt.totemCooldownTextColor
								if c then
									return c.r or 1, c.g or 1, c.b or 1
								end
								return 1, 1, 1
							end,
							set = function(info, r, g, b)
								if not ShamanPower.opt.totemCooldownTextColor then
									ShamanPower.opt.totemCooldownTextColor = {}
								end
								ShamanPower.opt.totemCooldownTextColor.r = r
								ShamanPower.opt.totemCooldownTextColor.g = g
								ShamanPower.opt.totemCooldownTextColor.b = b
								ShamanPower:ApplyTotemCooldownTextColor()
							end
						},
						pulse_bar_position = {
							disabled = function(info) return (CompactOn()) and true or false end,
							order = 4,
							type = "select",
							name = "Pulse Bar Position",
							desc = "Position of the white pulse countdown bar for pulsing totems (Tremor, Healing Stream, etc)",
							width = 1.2,
							values = {
								["none"] = "None (Disabled)",
								["on_icon"] = "On Icon",
								["above"] = "Above (Horizontal)",
								["above_vert"] = "Above (Vertical)",
								["below"] = "Below (Horizontal)",
								["below_vert"] = "Below (Vertical)",
								["left"] = "Left",
								["right"] = "Right",
							},
							get = function(info)
								return ShamanPower.opt.pulseBarPosition or "on_icon"
							end,
							set = function(info, val)
								ShamanPower.opt.pulseBarPosition = val
								ShamanPower:UpdatePulseBarPositions()
							end
						},
						pulse_bar_size = {
							disabled = function(info) return (CompactOn()) and true or false end,
							order = 4.5,
							type = "range",
							name = "Pulse Bar Size",
							desc = "Size of the pulse bar (height for horizontal bars, width for vertical bars)",
							width = 0.8,
							min = 2,
							max = 26,
							step = 1,
							hidden = function()
								return ShamanPower.opt.pulseBarPosition == "none" or ShamanPower.opt.pulseBarPosition == "on_icon"
							end,
							get = function(info)
								return ShamanPower.opt.pulseBarSize or 4
							end,
							set = function(info, val)
								ShamanPower.opt.pulseBarSize = val
								ShamanPower:UpdatePulseBarPositions()
							end
						},
						pulse_time_display = {
							disabled = function(info) return (((ShamanPower.opt.pulseBarPosition or "none") == "none") and true or false) or (CompactOn()) end,
							order = 5,
							type = "select",
							name = "Show Pulse Time",
							desc = WithNotes("Where to show the time until next pulse",
								function() return (ShamanPower.opt.pulseBarPosition or "none") == "none" end, "The pulse time is drawn by the pulse bar. Set Pulse Bar Position to something other than None first."),
							width = 1.1,
							values = {
								["none"] = "None",
								["inside_top"] = "Inside Bar (Top)",
								["inside_bottom"] = "Inside Bar (Bottom)",
								["above"] = "Above Bar",
								["below"] = "Below Bar",
								["on_icon"] = "On Icon",
							},
							get = function(info)
								return ShamanPower.opt.pulseTimeDisplay or "none"
							end,
							set = function(info, val)
								ShamanPower.opt.pulseTimeDisplay = val
								ShamanPower:UpdatePulseBarPositions()
							end
						},
						pulse_text_size = {
							disabled = function(info) return (((ShamanPower.opt.pulseBarPosition or "none") == "none") and true or false) or (CompactOn()) end,
							order = 5.5,
							type = "range",
							name = "Pulse Text Size",
							desc = "Font size for the pulse time text",
							width = 1.0,
							min = 6,
							max = 20,
							step = 1,
							hidden = function()
								return ShamanPower.opt.pulseTimeDisplay == "none" or ShamanPower.opt.pulseTimeDisplay == nil
							end,
							get = function(info)
								return ShamanPower.opt.pulseTextSize or 8
							end,
							set = function(info, val)
								ShamanPower.opt.pulseTextSize = val
								ShamanPower:UpdatePulseBarPositions()
							end
						},
					}
				},
				cdbar_items_section = {
					order = 12,
					name = "Cooldown Bar Items",
					type = "group",
					args = {
						unlock_cd_bar = {
							order = 0.5,
							name = "Unlock Bar (move)",
							desc = "Show a movable overlay so you can drag the cooldown bar anywhere. Turn it off when done.",
							type = "toggle",
							width = "full",
							get = function(info)
							return ShamanPower.cdBarMoverShown or false
							end,
							set = function(info, val)
							ShamanPower:SetCooldownBarUnlocked(val)
							end
						},
						cdbar_items_desc = {
							order = 0,
							type = "description",
							name = "Choose which buttons appear on the cooldown bar.\n",
						},
						show_cooldown_bar = {
							order = 1,
							type = "toggle",
							name = "Enable Cooldown Bar",
							desc = "Show a cooldown tracker bar with shields, ankh, nature's swiftness, etc.",
							width = "full",
							get = function(info)
								return ShamanPower.opt.showCooldownBar
							end,
							set = function(info, val)
								ShamanPower.opt.showCooldownBar = val
								ShamanPower:UpdateCooldownBar()
							end
						},
						cdbar_spacer1 = {
							order = 1.5,
							type = "description",
							name = " ",
							hidden = function() return not ShamanPower.opt.showCooldownBar end,
						},
						cdbar_show_shields = {
							order = 2,
							type = "toggle",
							name = "Shields (Lightning/Water Shield)",
							desc = "Show Lightning/Water Shield button on cooldown bar",
							width = "full",
							hidden = function() return not ShamanPower.opt.showCooldownBar end,
							get = function(info)
								return ShamanPower.opt.cdbarShowShields ~= false
							end,
							set = function(info, val)
								ShamanPower.opt.cdbarShowShields = val
								ShamanPower:RecreateCooldownBar()   -- waits for the end of combat by itself
							end
						},
						cdbar_show_recall = {
							order = 3,
							type = "toggle",
							name = function() return (GetSpellInfo(36936) or "Totemic Call") .. " (Recall Totems)" end,
							desc = function() return "Show " .. (GetSpellInfo(36936) or "Totemic Call") .. " button" end,
							width = "full",
							hidden = function() return (not ShamanPower.opt.showCooldownBar and not ShamanPower.opt.totemicCallOnTotemBar) or not ShamanPower:CooldownTypeExists(2) end,
							get = function(info)
								return ShamanPower.opt.cdbarShowRecall ~= false
							end,
							set = function(info, val)
								ShamanPower.opt.cdbarShowRecall = val
								if not InCombatLockdown() then
									ShamanPower:RecreateCooldownBar()
									ShamanPower:UpdateMiniTotemBar()
								end
							end
						},
						cdbar_recall_on_totembar = {
							order = 3.5,
							type = "toggle",
							name = "    |cff888888-> Show on Totem Bar instead|r",
							desc = "Move Totemic Call button to the totem bar instead of cooldown bar",
							width = "full",
							hidden = function()
								-- shown with the cooldown bar off too: the totem bar's Totemic Call button does not care about it,
								-- and these are the only switches that remove it
								return ShamanPower.opt.cdbarShowRecall == false
							end,
							get = function(info)
								return ShamanPower.opt.totemicCallOnTotemBar
							end,
							set = function(info, val)
								ShamanPower.opt.totemicCallOnTotemBar = val
								if not InCombatLockdown() then
									ShamanPower:RecreateCooldownBar()
									ShamanPower:UpdateMiniTotemBar()
								end
							end
						},
						cdbar_show_reincarnation = {
							order = 4,
							type = "toggle",
							name = "Reincarnation (Ankh)",
							desc = "Show Reincarnation cooldown on cooldown bar",
							width = "full",
							hidden = function() return (not ShamanPower.opt.showCooldownBar) or not ShamanPower:CooldownTypeExists(3) end,
							get = function(info)
								return ShamanPower.opt.cdbarShowReincarnation ~= false
							end,
							set = function(info, val)
								ShamanPower.opt.cdbarShowReincarnation = val
								ShamanPower:RecreateCooldownBar()   -- waits for the end of combat by itself
							end
						},
						cdbar_show_ns = {
							order = 5,
							type = "toggle",
							name = "Nature's Swiftness",
							desc = "Show Nature's Swiftness cooldown on cooldown bar",
							width = "full",
							hidden = function() return (not ShamanPower.opt.showCooldownBar) or not ShamanPower:CooldownTypeExists(4) end,
							get = function(info)
								return ShamanPower.opt.cdbarShowNS ~= false
							end,
							set = function(info, val)
								ShamanPower.opt.cdbarShowNS = val
								ShamanPower:RecreateCooldownBar()   -- waits for the end of combat by itself
							end
						},
						cdbar_show_manatide = {
							order = 6,
							type = "toggle",
							name = "Mana Tide Totem",
							desc = "Show Mana Tide Totem cooldown on cooldown bar",
							width = "full",
							hidden = function() return (not ShamanPower.opt.showCooldownBar) or not ShamanPower:CooldownTypeExists(5) end,
							get = function(info)
								return ShamanPower.opt.cdbarShowManaTide ~= false
							end,
							set = function(info, val)
								ShamanPower.opt.cdbarShowManaTide = val
								ShamanPower:RecreateCooldownBar()   -- waits for the end of combat by itself
							end
						},
						cdbar_show_shamanistic_rage = {
							order = 7,
							type = "toggle",
							name = "Shamanistic Rage",
							desc = "Show Shamanistic Rage cooldown on cooldown bar (Enhancement talent)",
							width = "full",
							hidden = function() return (not ShamanPower.opt.showCooldownBar) or not ShamanPower:CooldownTypeExists(8) end,
							get = function(info)
								return ShamanPower.opt.cdbarShowShamanisticRage ~= false
							end,
							set = function(info, val)
								ShamanPower.opt.cdbarShowShamanisticRage = val
								ShamanPower:RecreateCooldownBar()   -- waits for the end of combat by itself
							end
						},
						cdbar_show_bloodlust = {
							order = 8,
							type = "toggle",
							name = "Bloodlust / Heroism",
							desc = "Show Bloodlust/Heroism cooldown on cooldown bar",
							width = "full",
							hidden = function() return (not ShamanPower.opt.showCooldownBar) or not ShamanPower:CooldownTypeExists(6) end,
							get = function(info)
								return ShamanPower.opt.cdbarShowBloodlust ~= false
							end,
							set = function(info, val)
								ShamanPower.opt.cdbarShowBloodlust = val
								ShamanPower:RecreateCooldownBar()   -- waits for the end of combat by itself
							end
						},
						cdbar_show_imbues = {
							order = 9,
							type = "toggle",
							name = "Weapon Imbues",
							desc = "Show Weapon Imbue button on cooldown bar",
							width = "full",
							hidden = function() return not ShamanPower.opt.showCooldownBar end,
							get = function(info)
								return ShamanPower.opt.cdbarShowImbues ~= false
							end,
							set = function(info, val)
								ShamanPower.opt.cdbarShowImbues = val
								ShamanPower:RecreateCooldownBar()   -- waits for the end of combat by itself
							end
						},
						cdbar_show_elemental_mastery = {
							order = 10,
							type = "toggle",
							name = "Elemental Mastery",
							desc = "Show Elemental Mastery cooldown on cooldown bar (Elemental talent)",
							width = "full",
							hidden = function() return (not ShamanPower.opt.showCooldownBar) or not ShamanPower:CooldownTypeExists(9) end,
							get = function(info)
								return ShamanPower.opt.cdbarShowElementalMastery ~= false
							end,
							set = function(info, val)
								ShamanPower.opt.cdbarShowElementalMastery = val
								ShamanPower:RecreateCooldownBar()   -- waits for the end of combat by itself
							end
						},
						-- WoW: Forever cooldowns; hidden on clients whose data lacks the spell
						cdbar_show_rage_of_the_farseer = {
							order = 10.1,
							type = "toggle",
							name = "Rage of the Farseer",
							desc = "Show the Rage of the Farseer cooldown on the cooldown bar (Enhancement capstone talent, WoW: Forever)",
							width = "full",
							hidden = function() return not ShamanPower.opt.showCooldownBar or not SPCompat.SpellExists(425336) end,
							get = function(info)
								return ShamanPower.opt.cdbarShowRageOfTheFarseer ~= false
							end,
							set = function(info, val)
								ShamanPower.opt.cdbarShowRageOfTheFarseer = val
								ShamanPower:RecreateCooldownBar()   -- waits for the end of combat by itself
							end
						},
						cdbar_show_totemic_projection = {
							order = 10.2,
							type = "toggle",
							name = "Totemic Projection",
							desc = "Show the Totemic Projection cooldown on the cooldown bar (WoW: Forever)",
							width = "full",
							hidden = function() return not ShamanPower.opt.showCooldownBar or not SPCompat.SpellExists(437009) end,
							get = function(info)
								return ShamanPower.opt.cdbarShowTotemicProjection ~= false
							end,
							set = function(info, val)
								ShamanPower.opt.cdbarShowTotemicProjection = val
								ShamanPower:RecreateCooldownBar()   -- waits for the end of combat by itself
							end
						},
					}
				},
				cdbar_order_section = {
					order = 13,
					name = "Cooldown Bar Order",
					type = "group",
					hidden = function(info)
						return not ShamanPower.opt.showCooldownBar
					end,
					args = {
						cdbar_order_desc = {
							order = 0,
							type = "description",
							name = "Choose the order of buttons on the cooldown bar. Only buttons that exist on this game client are listed; ones you have turned off or have not learned yet keep their place and are simply skipped.",
						},
					}
				},
				popout_section = {
					order = 20,
					name = "Pop-Out Trackers",
					type = "group",
					args = {
						popout_desc = {
							order = 0,
							type = "description",
							name = "Middle-click any totem or cooldown button to pop it out into a standalone, movable tracker. Use the cog wheel on each pop-out for individual settings (scale, opacity, hide frame). Middle-click or use the cog menu to return to bar. ALT+drag to move when frame is hidden.",
						},
						popout_return_all = {
							order = 1,
							type = "execute",
							name = "Return All to Bars",
							desc = "Return all popped-out trackers back to their original bars",
							width = 1.2,
							func = function()
								if InCombatLockdown() then
									print("|cff0070ddShamanPower:|r Cannot modify pop-outs during combat")
									return
								end
								ShamanPower:ReturnAllPopOutsToBar()
							end,
						},
						popout_hide_all_frames = {
							order = 2,
							type = "toggle",
							name = "Hide All Frames",
							desc = WithNotes("Hide the frame/border around all popped-out trackers (show only icons). You can still use ALT+drag to move them.",
								true, "Applies to the pop-outs that exist when you click it. Ones you pop out later keep their frame until you click this again."),
							width = 1.2,
							get = function(info)
								return ShamanPower.opt.poppedOutHideAllFrames or false
							end,
							set = function(info, val)
								ShamanPower.opt.poppedOutHideAllFrames = val
								-- Apply to all existing pop-outs
								for key, frame in pairs(ShamanPower.poppedOutFrames) do
									ShamanPower.opt.poppedOutSettings = ShamanPower.opt.poppedOutSettings or {}
									ShamanPower.opt.poppedOutSettings[key] = ShamanPower.opt.poppedOutSettings[key] or {}
									-- never toggled = frame shown (nil counts as false)
									local wasHidden = ShamanPower.opt.poppedOutSettings[key].hideFrame and true or false
									if (val and true or false) ~= wasHidden then
										ShamanPower:TogglePopOutFrame(key)
									end
								end
							end,
						},
					}
				},
				totemflyouts_section = {
					order = 9.5,
					name = "Totem Flyouts",
					type = "group",
					args = {
						flyouts_off_note = {
							order = 0.05,
							type = "description",
							name = "|cffffa040Totem flyouts are turned off (Totem Bar > Items), so this list has no effect until you turn them on.|r",
							hidden = function() return not (not ShamanPower.opt.showTotemFlyouts) end,
						},
						flyouts_desc = {
							order = 0,
							type = "description",
							name = "Choose which totems appear in the flyout menus. Disable totems you never use to keep your flyouts cleaner.\n",
						},
						-- Earth Totems
						earth_header = {
							order = 1,
							type = "header",
							name = "|cff8B4513Earth Totems|r",
						},
						earth_strength = {
							order = 1.1,
							type = "toggle",
							name = "Strength of Earth",
							width = 0.9,
							get = function() return ShamanPower.opt.flyoutTotems == nil or ShamanPower.opt.flyoutTotems.earth_1 ~= false end,
							hidden = function() return not SPCompat.SpellExists(ShamanPower.EarthTotems[1]) end,   -- totem not in this client's data
							set = function(_, val)
								ShamanPower.opt.flyoutTotems = ShamanPower.opt.flyoutTotems or {}
								ShamanPower.opt.flyoutTotems.earth_1 = val
								ShamanPower:RecreateTotemFlyouts()
							end,
						},
						earth_stoneskin = {
							order = 1.2,
							type = "toggle",
							name = "Stoneskin",
							width = 0.9,
							get = function() return ShamanPower.opt.flyoutTotems == nil or ShamanPower.opt.flyoutTotems.earth_2 ~= false end,
							hidden = function() return not SPCompat.SpellExists(ShamanPower.EarthTotems[2]) end,   -- totem not in this client's data
							set = function(_, val)
								ShamanPower.opt.flyoutTotems = ShamanPower.opt.flyoutTotems or {}
								ShamanPower.opt.flyoutTotems.earth_2 = val
								ShamanPower:RecreateTotemFlyouts()
							end,
						},
						earth_tremor = {
							order = 1.3,
							type = "toggle",
							name = "Tremor",
							width = 0.9,
							get = function() return ShamanPower.opt.flyoutTotems == nil or ShamanPower.opt.flyoutTotems.earth_3 ~= false end,
							hidden = function() return not SPCompat.SpellExists(ShamanPower.EarthTotems[3]) end,   -- totem not in this client's data
							set = function(_, val)
								ShamanPower.opt.flyoutTotems = ShamanPower.opt.flyoutTotems or {}
								ShamanPower.opt.flyoutTotems.earth_3 = val
								ShamanPower:RecreateTotemFlyouts()
							end,
						},
						earth_earthbind = {
							order = 1.4,
							type = "toggle",
							name = "Earthbind",
							width = 0.9,
							get = function() return ShamanPower.opt.flyoutTotems == nil or ShamanPower.opt.flyoutTotems.earth_4 ~= false end,
							hidden = function() return not SPCompat.SpellExists(ShamanPower.EarthTotems[4]) end,   -- totem not in this client's data
							set = function(_, val)
								ShamanPower.opt.flyoutTotems = ShamanPower.opt.flyoutTotems or {}
								ShamanPower.opt.flyoutTotems.earth_4 = val
								ShamanPower:RecreateTotemFlyouts()
							end,
						},
						earth_stoneclaw = {
							order = 1.5,
							type = "toggle",
							name = "Stoneclaw",
							width = 0.9,
							get = function() return ShamanPower.opt.flyoutTotems == nil or ShamanPower.opt.flyoutTotems.earth_5 ~= false end,
							hidden = function() return not SPCompat.SpellExists(ShamanPower.EarthTotems[5]) end,   -- totem not in this client's data
							set = function(_, val)
								ShamanPower.opt.flyoutTotems = ShamanPower.opt.flyoutTotems or {}
								ShamanPower.opt.flyoutTotems.earth_5 = val
								ShamanPower:RecreateTotemFlyouts()
							end,
						},
						earth_elemental = {
							order = 1.6,
							type = "toggle",
							name = "Earth Elemental",
							width = 0.9,
							get = function() return ShamanPower.opt.flyoutTotems == nil or ShamanPower.opt.flyoutTotems.earth_6 ~= false end,
							hidden = function() return not SPCompat.SpellExists(ShamanPower.EarthTotems[6]) end,   -- totem not in this client's data
							set = function(_, val)
								ShamanPower.opt.flyoutTotems = ShamanPower.opt.flyoutTotems or {}
								ShamanPower.opt.flyoutTotems.earth_6 = val
								ShamanPower:RecreateTotemFlyouts()
							end,
						},
						-- Fire Totems
						fire_header = {
							order = 2,
							type = "header",
							name = "|cffFF4500Fire Totems|r",
						},
						fire_wrath = {
							order = 2.1,
							type = "toggle",
							name = "Totem of Wrath",
							width = 0.9,
							get = function() return ShamanPower.opt.flyoutTotems == nil or ShamanPower.opt.flyoutTotems.fire_1 ~= false end,
							hidden = function() return not SPCompat.SpellExists(ShamanPower.FireTotems[1]) end,   -- totem not in this client's data
							set = function(_, val)
								ShamanPower.opt.flyoutTotems = ShamanPower.opt.flyoutTotems or {}
								ShamanPower.opt.flyoutTotems.fire_1 = val
								ShamanPower:RecreateTotemFlyouts()
							end,
						},
						fire_searing = {
							order = 2.2,
							type = "toggle",
							name = "Searing",
							width = 0.9,
							get = function() return ShamanPower.opt.flyoutTotems == nil or ShamanPower.opt.flyoutTotems.fire_2 ~= false end,
							hidden = function() return not SPCompat.SpellExists(ShamanPower.FireTotems[2]) end,   -- totem not in this client's data
							set = function(_, val)
								ShamanPower.opt.flyoutTotems = ShamanPower.opt.flyoutTotems or {}
								ShamanPower.opt.flyoutTotems.fire_2 = val
								ShamanPower:RecreateTotemFlyouts()
							end,
						},
						fire_magma = {
							order = 2.3,
							type = "toggle",
							name = "Magma",
							width = 0.9,
							get = function() return ShamanPower.opt.flyoutTotems == nil or ShamanPower.opt.flyoutTotems.fire_3 ~= false end,
							hidden = function() return not SPCompat.SpellExists(ShamanPower.FireTotems[3]) end,   -- totem not in this client's data
							set = function(_, val)
								ShamanPower.opt.flyoutTotems = ShamanPower.opt.flyoutTotems or {}
								ShamanPower.opt.flyoutTotems.fire_3 = val
								ShamanPower:RecreateTotemFlyouts()
							end,
						},
						fire_nova = {
							order = 2.4,
							type = "toggle",
							name = "Fire Nova",
							width = 0.9,
							get = function() return ShamanPower.opt.flyoutTotems == nil or ShamanPower.opt.flyoutTotems.fire_4 ~= false end,
							hidden = function() return not SPCompat.SpellExists(ShamanPower.FireTotems[4]) end,   -- totem not in this client's data
							set = function(_, val)
								ShamanPower.opt.flyoutTotems = ShamanPower.opt.flyoutTotems or {}
								ShamanPower.opt.flyoutTotems.fire_4 = val
								ShamanPower:RecreateTotemFlyouts()
							end,
						},
						fire_flametongue = {
							order = 2.5,
							type = "toggle",
							name = "Flametongue",
							width = 0.9,
							get = function() return ShamanPower.opt.flyoutTotems == nil or ShamanPower.opt.flyoutTotems.fire_5 ~= false end,
							hidden = function() return not SPCompat.SpellExists(ShamanPower.FireTotems[5]) end,   -- totem not in this client's data
							set = function(_, val)
								ShamanPower.opt.flyoutTotems = ShamanPower.opt.flyoutTotems or {}
								ShamanPower.opt.flyoutTotems.fire_5 = val
								ShamanPower:RecreateTotemFlyouts()
							end,
						},
						fire_frostres = {
							order = 2.6,
							type = "toggle",
							name = "Frost Resistance",
							width = 0.9,
							get = function() return ShamanPower.opt.flyoutTotems == nil or ShamanPower.opt.flyoutTotems.fire_6 ~= false end,
							hidden = function() return not SPCompat.SpellExists(ShamanPower.FireTotems[6]) end,   -- totem not in this client's data
							set = function(_, val)
								ShamanPower.opt.flyoutTotems = ShamanPower.opt.flyoutTotems or {}
								ShamanPower.opt.flyoutTotems.fire_6 = val
								ShamanPower:RecreateTotemFlyouts()
							end,
						},
						fire_elemental = {
							order = 2.7,
							type = "toggle",
							name = "Fire Elemental",
							width = 0.9,
							get = function() return ShamanPower.opt.flyoutTotems == nil or ShamanPower.opt.flyoutTotems.fire_7 ~= false end,
							hidden = function() return not SPCompat.SpellExists(ShamanPower.FireTotems[7]) end,   -- totem not in this client's data
							set = function(_, val)
								ShamanPower.opt.flyoutTotems = ShamanPower.opt.flyoutTotems or {}
								ShamanPower.opt.flyoutTotems.fire_7 = val
								ShamanPower:RecreateTotemFlyouts()
							end,
						},
						-- Water Totems
						water_header = {
							order = 3,
							type = "header",
							name = "|cff00CED1Water Totems|r",
						},
						water_manaspring = {
							order = 3.1,
							type = "toggle",
							name = "Mana Spring",
							width = 0.9,
							get = function() return ShamanPower.opt.flyoutTotems == nil or ShamanPower.opt.flyoutTotems.water_1 ~= false end,
							hidden = function() return not SPCompat.SpellExists(ShamanPower.WaterTotems[1]) end,   -- totem not in this client's data
							set = function(_, val)
								ShamanPower.opt.flyoutTotems = ShamanPower.opt.flyoutTotems or {}
								ShamanPower.opt.flyoutTotems.water_1 = val
								ShamanPower:RecreateTotemFlyouts()
							end,
						},
						water_healingstream = {
							order = 3.2,
							type = "toggle",
							name = "Healing Stream",
							width = 0.9,
							get = function() return ShamanPower.opt.flyoutTotems == nil or ShamanPower.opt.flyoutTotems.water_2 ~= false end,
							hidden = function() return not SPCompat.SpellExists(ShamanPower.WaterTotems[2]) end,   -- totem not in this client's data
							set = function(_, val)
								ShamanPower.opt.flyoutTotems = ShamanPower.opt.flyoutTotems or {}
								ShamanPower.opt.flyoutTotems.water_2 = val
								ShamanPower:RecreateTotemFlyouts()
							end,
						},
						water_manatide = {
							order = 3.3,
							type = "toggle",
							name = "Mana Tide",
							width = 0.9,
							get = function() return ShamanPower.opt.flyoutTotems == nil or ShamanPower.opt.flyoutTotems.water_3 ~= false end,
							hidden = function() return not SPCompat.SpellExists(ShamanPower.WaterTotems[3]) end,   -- totem not in this client's data
							set = function(_, val)
								ShamanPower.opt.flyoutTotems = ShamanPower.opt.flyoutTotems or {}
								ShamanPower.opt.flyoutTotems.water_3 = val
								ShamanPower:RecreateTotemFlyouts()
							end,
						},
						water_poison = {
							order = 3.4,
							type = "toggle",
							name = "Poison Cleansing",
							width = 0.9,
							get = function() return ShamanPower.opt.flyoutTotems == nil or ShamanPower.opt.flyoutTotems.water_4 ~= false end,
							hidden = function() return not SPCompat.SpellExists(ShamanPower.WaterTotems[4]) end,   -- totem not in this client's data
							set = function(_, val)
								ShamanPower.opt.flyoutTotems = ShamanPower.opt.flyoutTotems or {}
								ShamanPower.opt.flyoutTotems.water_4 = val
								ShamanPower:RecreateTotemFlyouts()
							end,
						},
						water_disease = {
							order = 3.5,
							type = "toggle",
							name = "Disease Cleansing",
							width = 0.9,
							get = function() return ShamanPower.opt.flyoutTotems == nil or ShamanPower.opt.flyoutTotems.water_5 ~= false end,
							hidden = function() return not SPCompat.SpellExists(ShamanPower.WaterTotems[5]) end,   -- totem not in this client's data
							set = function(_, val)
								ShamanPower.opt.flyoutTotems = ShamanPower.opt.flyoutTotems or {}
								ShamanPower.opt.flyoutTotems.water_5 = val
								ShamanPower:RecreateTotemFlyouts()
							end,
						},
						water_fireres = {
							order = 3.6,
							type = "toggle",
							name = "Fire Resistance",
							width = 0.9,
							get = function() return ShamanPower.opt.flyoutTotems == nil or ShamanPower.opt.flyoutTotems.water_6 ~= false end,
							hidden = function() return not SPCompat.SpellExists(ShamanPower.WaterTotems[6]) end,   -- totem not in this client's data
							set = function(_, val)
								ShamanPower.opt.flyoutTotems = ShamanPower.opt.flyoutTotems or {}
								ShamanPower.opt.flyoutTotems.water_6 = val
								ShamanPower:RecreateTotemFlyouts()
							end,
						},
						-- Air Totems
						air_header = {
							order = 4,
							type = "header",
							name = "|cff87CEEBAir Totems|r",
						},
						air_windfury = {
							order = 4.1,
							type = "toggle",
							name = "Windfury",
							width = 0.9,
							get = function() return ShamanPower.opt.flyoutTotems == nil or ShamanPower.opt.flyoutTotems.air_1 ~= false end,
							hidden = function() return not SPCompat.SpellExists(ShamanPower.AirTotems[1]) end,   -- totem not in this client's data
							set = function(_, val)
								ShamanPower.opt.flyoutTotems = ShamanPower.opt.flyoutTotems or {}
								ShamanPower.opt.flyoutTotems.air_1 = val
								ShamanPower:RecreateTotemFlyouts()
							end,
						},
						air_graceofair = {
							order = 4.2,
							type = "toggle",
							name = "Grace of Air",
							width = 0.9,
							get = function() return ShamanPower.opt.flyoutTotems == nil or ShamanPower.opt.flyoutTotems.air_2 ~= false end,
							hidden = function() return not SPCompat.SpellExists(ShamanPower.AirTotems[2]) end,   -- totem not in this client's data
							set = function(_, val)
								ShamanPower.opt.flyoutTotems = ShamanPower.opt.flyoutTotems or {}
								ShamanPower.opt.flyoutTotems.air_2 = val
								ShamanPower:RecreateTotemFlyouts()
							end,
						},
						air_wrathofair = {
							order = 4.3,
							type = "toggle",
							name = "Wrath of Air",
							width = 0.9,
							get = function() return ShamanPower.opt.flyoutTotems == nil or ShamanPower.opt.flyoutTotems.air_3 ~= false end,
							hidden = function() return not SPCompat.SpellExists(ShamanPower.AirTotems[3]) end,   -- totem not in this client's data
							set = function(_, val)
								ShamanPower.opt.flyoutTotems = ShamanPower.opt.flyoutTotems or {}
								ShamanPower.opt.flyoutTotems.air_3 = val
								ShamanPower:RecreateTotemFlyouts()
							end,
						},
						air_tranquil = {
							order = 4.4,
							type = "toggle",
							name = "Tranquil Air",
							width = 0.9,
							get = function() return ShamanPower.opt.flyoutTotems == nil or ShamanPower.opt.flyoutTotems.air_4 ~= false end,
							hidden = function() return not SPCompat.SpellExists(ShamanPower.AirTotems[4]) end,   -- totem not in this client's data
							set = function(_, val)
								ShamanPower.opt.flyoutTotems = ShamanPower.opt.flyoutTotems or {}
								ShamanPower.opt.flyoutTotems.air_4 = val
								ShamanPower:RecreateTotemFlyouts()
							end,
						},
						air_grounding = {
							order = 4.5,
							type = "toggle",
							name = "Grounding",
							width = 0.9,
							get = function() return ShamanPower.opt.flyoutTotems == nil or ShamanPower.opt.flyoutTotems.air_5 ~= false end,
							hidden = function() return not SPCompat.SpellExists(ShamanPower.AirTotems[5]) end,   -- totem not in this client's data
							set = function(_, val)
								ShamanPower.opt.flyoutTotems = ShamanPower.opt.flyoutTotems or {}
								ShamanPower.opt.flyoutTotems.air_5 = val
								ShamanPower:RecreateTotemFlyouts()
							end,
						},
						air_natureres = {
							order = 4.6,
							type = "toggle",
							name = "Nature Resistance",
							width = 0.9,
							get = function() return ShamanPower.opt.flyoutTotems == nil or ShamanPower.opt.flyoutTotems.air_6 ~= false end,
							hidden = function() return not SPCompat.SpellExists(ShamanPower.AirTotems[6]) end,   -- totem not in this client's data
							set = function(_, val)
								ShamanPower.opt.flyoutTotems = ShamanPower.opt.flyoutTotems or {}
								ShamanPower.opt.flyoutTotems.air_6 = val
								ShamanPower:RecreateTotemFlyouts()
							end,
						},
						air_windwall = {
							order = 4.7,
							type = "toggle",
							name = "Windwall",
							width = 0.9,
							get = function() return ShamanPower.opt.flyoutTotems == nil or ShamanPower.opt.flyoutTotems.air_7 ~= false end,
							hidden = function() return not SPCompat.SpellExists(ShamanPower.AirTotems[7]) end,   -- totem not in this client's data
							set = function(_, val)
								ShamanPower.opt.flyoutTotems = ShamanPower.opt.flyoutTotems or {}
								ShamanPower.opt.flyoutTotems.air_7 = val
								ShamanPower:RecreateTotemFlyouts()
							end,
						},
						air_sentry = {
							order = 4.8,
							type = "toggle",
							name = "Sentry",
							width = 0.9,
							get = function() return ShamanPower.opt.flyoutTotems == nil or ShamanPower.opt.flyoutTotems.air_8 ~= false end,
							hidden = function() return not SPCompat.SpellExists(ShamanPower.AirTotems[8]) end,   -- totem not in this client's data
							set = function(_, val)
								ShamanPower.opt.flyoutTotems = ShamanPower.opt.flyoutTotems or {}
								ShamanPower.opt.flyoutTotems.air_8 = val
								ShamanPower:RecreateTotemFlyouts()
							end,
						},
					}
				},
				totemplates_section = {
					order = 10,
					name = "Totem Plates",
					type = "group",
					args = {
						module_missing_note = {
							order = 0.01,
							type = "description",
							name = "|cffffa040This module is not loaded, so nothing on this page does anything right now (toggles may even snap back). Enable the ShamanPower [Totem Plates] addon in the AddOns list and /reload.|r",
							hidden = function() return not (not ShamanPower.TotemPlatesLoaded) end,
						},
						totemplates_desc = {
							order = 0,
							type = "description",
							name = "Replace totem nameplates with icons for easy identification in PvP and raids.\n\n|cffff8800Note:|r Requires the |cff00ff00ShamanPower [Totem Plates]|r module to be enabled in your AddOns list.\n",
						},
						totemplates_enabled = {
							order = 1,
							name = "Enable Totem Plates",
							desc = "Replace totem nameplates with clean icons",
							type = "toggle",
							width = "full",
							get = function(info)
								return ShamanPower.opt.totemPlates and ShamanPower.opt.totemPlates.enabled or false
							end,
							set = function(info, val)
								ShamanPower:EnsureProfileTable("totemPlates")
								ShamanPower.opt.totemPlates.enabled = val
								ShamanPower:ToggleTotemPlates()
							end
						},
						totemplates_show_enemy = {
							order = 2,
							name = "Show Enemy Totems",
							desc = "Replace enemy totem nameplates with icons",
							type = "toggle",
							width = 1.0,
							disabled = function() return not (ShamanPower.opt.totemPlates and ShamanPower.opt.totemPlates.enabled) end,
							get = function(info)
								return ShamanPower.opt.totemPlates and ShamanPower.opt.totemPlates.showEnemy ~= false
							end,
							set = function(info, val)
								ShamanPower:EnsureProfileTable("totemPlates")
								ShamanPower.opt.totemPlates.showEnemy = val
							end
						},
						totemplates_show_friendly = {
							order = 3,
							name = "Show Friendly Totems",
							desc = "Replace friendly totem nameplates with icons. |cffffa040Not inside dungeons and raids: the game keeps friendly nameplates away from addons there. Enemy totems work everywhere.|r",
							type = "toggle",
							width = 1.0,
							disabled = function() return not (ShamanPower.opt.totemPlates and ShamanPower.opt.totemPlates.enabled) end,
							get = function(info)
								return ShamanPower.opt.totemPlates and ShamanPower.opt.totemPlates.showFriendly ~= false
							end,
							set = function(info, val)
								ShamanPower:EnsureProfileTable("totemPlates")
								ShamanPower.opt.totemPlates.showFriendly = val
							end
						},
						totemplates_size = {
							order = 4,
							name = "Icon Size",
							desc = "Size of the totem plate icons",
							type = "range",
							min = 20, max = 80, step = 2,
							width = 1.5,
							disabled = function() return not (ShamanPower.opt.totemPlates and ShamanPower.opt.totemPlates.enabled) end,
							get = function(info)
								return ShamanPower.opt.totemPlates and ShamanPower.opt.totemPlates.iconSize or 40
							end,
							set = function(info, val)
								ShamanPower:EnsureProfileTable("totemPlates")
								ShamanPower.opt.totemPlates.iconSize = val
								ShamanPower:UpdateTotemPlatesSize()
							end
						},
						totemplates_alpha = {
							order = 5,
							name = "Opacity",
							desc = "Opacity of the totem plate icons",
							type = "range",
							min = 0.3, max = 1.0, step = 0.1,
							isPercent = true,
							width = 1.5,
							disabled = function() return not (ShamanPower.opt.totemPlates and ShamanPower.opt.totemPlates.enabled) end,
							get = function(info)
								return ShamanPower.opt.totemPlates and ShamanPower.opt.totemPlates.alpha or 0.9
							end,
							set = function(info, val)
								ShamanPower:EnsureProfileTable("totemPlates")
								ShamanPower.opt.totemPlates.alpha = val
							end
						},
						totemplates_show_name = {
							order = 6,
							name = "Show Totem Name",
							desc = "Display the totem name below the icon",
							type = "toggle",
							width = "full",
							disabled = function() return not (ShamanPower.opt.totemPlates and ShamanPower.opt.totemPlates.enabled) end,
							get = function(info)
								return ShamanPower.opt.totemPlates and ShamanPower.opt.totemPlates.showName or false
							end,
							set = function(info, val)
								ShamanPower:EnsureProfileTable("totemPlates")
								ShamanPower.opt.totemPlates.showName = val
							end
						},
						totemplates_pulse_header = {
							order = 7,
							type = "header",
							name = "Pulse Timer",
							hidden = function() return not (ShamanPower.opt.totemPlates and ShamanPower.opt.totemPlates.enabled) end,
						},
						totemplates_pulse_enabled = {
							order = 8,
							name = "Show Pulse Timer",
							desc = "Show countdown to next pulse for totems like Tremor, Healing Stream, etc.",
							type = "toggle",
							width = "full",
							disabled = function() return not (ShamanPower.opt.totemPlates and ShamanPower.opt.totemPlates.enabled) end,
							get = function(info)
								return ShamanPower.opt.totemPlates and ShamanPower.opt.totemPlates.showPulseTimer ~= false
							end,
							set = function(info, val)
								ShamanPower:EnsureProfileTable("totemPlates")
								ShamanPower.opt.totemPlates.showPulseTimer = val
								ShamanPower:UpdateTotemPlatesPulseSettings()
							end
						},
						totemplates_pulse_text = {
							order = 9,
							name = "Countdown Text",
							desc = "Display the time until next pulse as text on the icon",
							type = "toggle",
							width = 1.0,
							disabled = function() return not (ShamanPower.opt.totemPlates and ShamanPower.opt.totemPlates.enabled and ShamanPower.opt.totemPlates.showPulseTimer) end,
							get = function(info)
								return ShamanPower.opt.totemPlates and ShamanPower.opt.totemPlates.showPulseText ~= false
							end,
							set = function(info, val)
								ShamanPower:EnsureProfileTable("totemPlates")
								ShamanPower.opt.totemPlates.showPulseText = val
								ShamanPower:UpdateTotemPlatesPulseSettings()
							end
						},
						totemplates_pulse_bar = {
							order = 10,
							name = "Pulse Bar",
							desc = "Display a progress bar showing time until next pulse",
							type = "toggle",
							width = 1.0,
							disabled = function() return not (ShamanPower.opt.totemPlates and ShamanPower.opt.totemPlates.enabled and ShamanPower.opt.totemPlates.showPulseTimer) end,
							get = function(info)
								return ShamanPower.opt.totemPlates and ShamanPower.opt.totemPlates.showPulseBar ~= false
							end,
							set = function(info, val)
								ShamanPower:EnsureProfileTable("totemPlates")
								ShamanPower.opt.totemPlates.showPulseBar = val
								ShamanPower:UpdateTotemPlatesPulseSettings()
							end
						},
						totemplates_pulse_cooldown = {
							order = 11,
							name = "Cooldown Swipe",
							desc = "Display a cooldown swipe animation on the icon",
							type = "toggle",
							width = 1.0,
							disabled = function() return not (ShamanPower.opt.totemPlates and ShamanPower.opt.totemPlates.enabled and ShamanPower.opt.totemPlates.showPulseTimer) end,
							get = function(info)
								return ShamanPower.opt.totemPlates and ShamanPower.opt.totemPlates.showPulseCooldown or false
							end,
							set = function(info, val)
								ShamanPower:EnsureProfileTable("totemPlates")
								ShamanPower.opt.totemPlates.showPulseCooldown = val
								ShamanPower:UpdateTotemPlatesPulseSettings()
							end
						},
						totemplates_pulse_text_size = {
							order = 12,
							name = "Text Size",
							desc = "Font size for the pulse countdown text",
							type = "range",
							min = 8, max = 24, step = 1,
							width = 1.0,
							disabled = function() return not (ShamanPower.opt.totemPlates and ShamanPower.opt.totemPlates.enabled and ShamanPower.opt.totemPlates.showPulseTimer and ShamanPower.opt.totemPlates.showPulseText) end,
							get = function(info)
								return ShamanPower.opt.totemPlates and ShamanPower.opt.totemPlates.pulseTextSize or 14
							end,
							set = function(info, val)
								ShamanPower:EnsureProfileTable("totemPlates")
								ShamanPower.opt.totemPlates.pulseTextSize = val
								ShamanPower:UpdateTotemPlatesPulseSettings()
							end
						},
						totemplates_pulse_bar_height = {
							order = 13,
							name = "Bar Height",
							desc = "Height of the pulse progress bar",
							type = "range",
							min = 2, max = 12, step = 1,
							width = 1.0,
							disabled = function() return not (ShamanPower.opt.totemPlates and ShamanPower.opt.totemPlates.enabled and ShamanPower.opt.totemPlates.showPulseTimer and ShamanPower.opt.totemPlates.showPulseBar) end,
							get = function(info)
								return ShamanPower.opt.totemPlates and ShamanPower.opt.totemPlates.pulseBarHeight or 4
							end,
							set = function(info, val)
								ShamanPower:EnsureProfileTable("totemPlates")
								ShamanPower.opt.totemPlates.pulseBarHeight = val
								ShamanPower:UpdateTotemPlatesPulseSettings()
							end
						},
					}
				},
				loadoutbar_section = {
					order = 11,
					name = "Loadout Bar",
					type = "group",
					disabled = function(info)
						return ShamanPower.opt.enabled == false or not isShaman
					end,
					args = {
						loadoutbar_desc = {
							order = 0,
							type = "description",
							name = "Customize the appearance of the on-screen totem loadout bar.\n",
						},
						loadoutbar_scale = {
							order = 1,
							name = "Scale",
							desc = "Adjust the size of the loadout bar",
							type = "range",
							isPercent = true,
							width = 1.5,
							min = 0.5,
							max = 2.0,
							step = 0.05,
							disabled = function()
								return ShamanPower.opt.enabled == false or not isShaman or not ShamanPower.opt.showLoadoutBar
							end,
							get = function(info)
								return ShamanPower.opt.loadoutBarScale or 1.0
							end,
							set = function(info, val)
								ShamanPower.opt.loadoutBarScale = val
								ShamanPower:UpdateLoadoutBar()
							end,
						},
						loadoutbar_opacity = {
							order = 2,
							name = "Opacity",
							desc = "Adjust the opacity/transparency of the loadout bar",
							type = "range",
							width = 1.5,
							min = 0.1,
							max = 1.0,
							step = 0.05,
							isPercent = true,
							disabled = function()
								return ShamanPower.opt.enabled == false or not isShaman or not ShamanPower.opt.showLoadoutBar
							end,
							get = function(info)
								return ShamanPower.opt.loadoutBarOpacity or 1.0
							end,
							set = function(info, val)
								ShamanPower.opt.loadoutBarOpacity = val
								ShamanPower:UpdateLoadoutBar()
							end,
						},
						loadoutbar_locked = {
							order = 3,
							name = "Lock ALT+Drag",
							desc = "The bar's anchor button can also be moved by holding ALT and dragging it. On, that shortcut is off so the bar cannot be nudged by accident. The Move button above works either way.",
							type = "toggle",
							width = "full",
							disabled = function()
								return ShamanPower.opt.enabled == false or not isShaman or not ShamanPower.opt.showLoadoutBar
							end,
							get = function(info)
								return ShamanPower.opt.loadoutBarLocked
							end,
							set = function(info, val)
								ShamanPower.opt.loadoutBarLocked = val
							end,
						},
						loadoutbar_hidenames = {
							order = 4,
							name = "Hide Loadout Names",
							desc = "Hide the name labels shown next to loadout buttons",
							type = "toggle",
							width = "full",
							disabled = function()
								return ShamanPower.opt.enabled == false or not isShaman or not ShamanPower.opt.showLoadoutBar
							end,
							get = function(info)
								return ShamanPower.opt.loadoutBarHideNames
							end,
							set = function(info, val)
								ShamanPower.opt.loadoutBarHideNames = val
								ShamanPower:UpdateLoadoutBar()
							end,
						},
						loadoutbar_showtotems = {
							order = 5,
							name = "Show Totem Icons on Active Loadout",
							desc = "Show the 4 totem icons on the active loadout button instead of the loadout icon, so you can see at a glance which totems are assigned",
							type = "toggle",
							width = "full",
							disabled = function()
								return ShamanPower.opt.enabled == false or not isShaman or not ShamanPower.opt.showLoadoutBar
							end,
							get = function(info)
								return ShamanPower.opt.loadoutBarShowTotems
							end,
							set = function(info, val)
								ShamanPower.opt.loadoutBarShowTotems = val
								ShamanPower:UpdateLoadoutBar()
							end,
						},
						loadoutbar_clickcycle = {
							order = 6,
							name = "Click the Button to Cycle Loadouts",
							desc = "Left-click the loadout button for your next loadout, right-click for the previous one, as well as picking from the flyout. Out of combat.",
							type = "toggle",
							width = "full",
							disabled = function()
								return ShamanPower.opt.enabled == false or not isShaman or not ShamanPower.opt.showLoadoutBar
							end,
							get = function(info)
								return ShamanPower.opt.loadoutBarClickCycle == true
							end,
							set = function(info, val)
								ShamanPower.opt.loadoutBarClickCycle = val and true or nil
								ShamanPower:UpdateLoadoutBar()   -- the flyout comes back with cycling off
							end,
						},
						loadoutbar_noflyout = {
							order = 6.1,
							name = "Turn Off the Flyout",
							desc = "Hovering the loadout button no longer opens the flyout of your other loadouts: clicking is the only way to switch.",
							type = "toggle",
							width = "full",
							hidden = function() return not ShamanPower.opt.loadoutBarClickCycle end,
							disabled = function()
								return ShamanPower.opt.enabled == false or not isShaman or not ShamanPower.opt.showLoadoutBar
							end,
							get = function(info)
								return ShamanPower.opt.loadoutBarNoFlyout == true
							end,
							set = function(info, val)
								ShamanPower.opt.loadoutBarNoFlyout = val and true or nil
								ShamanPower:UpdateLoadoutBar()
							end,
						},
					}
				},
			}
		},
		totems = {
			order = 4,
			name = "Totem Assignments",
			type = "execute",
			guiHidden = true,
			func = function()
				if not (UnitAffectingCombat("player")) then
					ShamanPower:ToggleAssignmentWindow()
				end
			end
		},
		options = {
			order = 5,
			name = "ShamanPower Options",
			type = "execute",
			guiHidden = true,
			func = function()
				if not (UnitAffectingCombat("player")) then
					ShamanPower:OpenConfigWindow()
				end
			end
		}
	}
}

-- Window and cog controls use the same saved fields as their module pages.
-- Keep this UI-only wiring together; no module is required at options load time.
do
	local SP = ShamanPower
	local pages = SP.options.args.fluffy.args
	local function Notify()
		local registry = LibStub("AceConfigRegistry-3.0", true)
		if registry then registry:NotifyChange("ShamanPower") end
	end
	local function OpenButton(name, method, loaded)
		return {
			order = 0.5, type = "execute", name = "Open " .. name, width = "full",
			disabled = function() return (loaded and not SP[loaded]) or not SP[method] end,
			func = function() if SP[method] then SP[method](SP) end end,
		}
	end
	SP.options.args.settings.args.settings_show.args.open_assignments =
		OpenButton("Totem Assignments", "ToggleAssignmentWindow")
	SP.options.args.settings.args.settings_show.args.open_assignments.disabled = function() return InCombatLockdown() end
	local range = pages.sprange_section.args
	range.open_window = OpenButton("Totem Range Picker", "ShowSPRangeConfig", "SPRangeLoaded")
	range.show_overlay = {
		order = 0.6, type = "toggle", name = "Show Overlay", width = "full",
		disabled = function() return not SP.SPRangeLoaded end,
		get = function() return SP.spRangeFrame and SP.spRangeFrame:IsShown() or false end,
		set = function(_, value)
			if not SP.SPRangeLoaded then return end
			local shown = SP.spRangeFrame and SP.spRangeFrame:IsShown() or false
			if shown ~= value then SP:ToggleSPRange() end
		end,
	}
	range.tracked_header = { order = 6, type = "header", name = "Totems to Track" }
	-- The settings renderer supports individual toggles, not Ace multiselects.
	-- Resolve labels and availability from the module's filtered source table.
	local trackableIds = {
		"soe", "stoneskin", "tow", "flametongue", "frostresist",
		"manaspring", "healingstream", "fireresist", "manatide",
		"windfury", "graceofair", "wrathofair", "tranquilair", "natureresist", "windwall",
	}
	for position, id in ipairs(trackableIds) do
		range["tracked_" .. id] = {
			order = 6 + position / 100, type = "toggle", width = 1.5,
			name = function()
				local totem = SP.TrackableTotemsByID and SP.TrackableTotemsByID[id]
				return totem and totem.name or id
			end,
			hidden = function() return not (SP.TrackableTotemsByID and SP.TrackableTotemsByID[id]) end,
			disabled = function() return not SP.SPRangeLoaded end,
			get = function()
				return ShamanPower_RangeTracker and ShamanPower_RangeTracker.tracked
					and ShamanPower_RangeTracker.tracked[id] or false
			end,
			set = function(_, value)
				if not SP.SPRangeLoaded then return end
				SP:InitSPRange()
				ShamanPower_RangeTracker.tracked[id] = value
				SP:UpdateSPRangeConfigButtons()
				SP:UpdateSPRangeFrame()
			end,
		}
	end
	pages.partybuff_section.args.open_coverage = {
		order = 0.5, type = "execute", name = "Open Totem Coverage Settings", width = "full",
		hidden = function() return not (SP.CoverageAvailable and SP:CoverageAvailable()) end,
		func = function() SP:OpenFrameSettings("coverage", SP.coverageFrame) end,
	}
	local es = pages.estrack_section.args
	es.open_window = OpenButton("Earth Shield Tracker", "ToggleESTracker", "ESTrackerLoaded")
	es.open_window.hidden = function() return SP.ESTrackerUnavailable == true end
	es.open_window.func = function()
		if not SP.ESTrackerUnavailable and SP.ESTrackerLoaded then SP:ToggleESTracker(); Notify() end
	end
	local reactive = pages.reactivetotems_section.args
	reactive.click_to_cast = {
		order = 1.55, type = "toggle", name = "Click to Cast Totem (legacy preference)", width = "full",
		desc = "Mirrors the separate window's saved preference. Current alert frames are not secure cast buttons; "
			.. "enabling this does not make them cast totems.",
		disabled = function() return not SP.ReactiveTotemsLoaded end,
		get = function() return ShamanPower_ReactiveTotems and ShamanPower_ReactiveTotems.clickToCast ~= false end,
		set = function(_, value)
			if not ShamanPower_ReactiveTotems then return end
			ShamanPower_ReactiveTotems.clickToCast = value
			if SP.UpdateReactiveTotemAppearance then SP:UpdateReactiveTotemAppearance() end
		end,
	}

	-- Assignment selectors are UI state only. No new SavedVariables or protocol.
	local selectedShaman, selectedGroup = "", 1
	local function RaidDB()
		if not SP.RaidCooldownsLoaded or not SP.InitRaidCooldowns then return nil end
		SP:InitRaidCooldowns()
		return ShamanPower_RaidCooldowns
	end
	local function RaidLocked()
		return not (SP.RaidCooldownsLoaded and SP.CanAssignRaidCooldowns and SP:CanAssignRaidCooldowns())
	end
	local function NameValues(method)
		local values = { [""] = "None" }
		if SP.RaidCooldownsLoaded and SP[method] then
			for _, name in ipairs(SP[method](SP)) do values[name] = name end
		end
		return values
	end
	local function AssignmentChanged()
		SP:SendRaidCooldownSync()
		SP:UpdateRaidCooldownPanel()
	end
	local function HasBloodlust() return not (SPCompat and SPCompat.HasBloodlust) or SPCompat.HasBloodlust() end
	local function HasDrums() return not (SPCompat and SPCompat.HasDrums) or SPCompat.HasDrums() end
	local raid = pages.raid_cd_section.args
	raid.open_window = OpenButton("Raid Cooldown Assignments", "ToggleRaidCooldownPanel", "RaidCooldownsLoaded")
	raid.assignment_header = { order = 7, type = "header", name = "Cooldown Assignments" }
	for index, field in ipairs({ "primary", "backup1", "backup2", "caller" }) do
		local label = ({ "Primary", "Backup 1", "Backup 2", "Caller" })[index]
		raid["bloodlust_" .. field] = {
			order = 7 + index / 10, type = "select", width = 1.5,
			name = function()
				return (UnitFactionGroup("player") == "Alliance" and "Heroism " or "Bloodlust ") .. label
			end,
			hidden = function() return not HasBloodlust() end,
			disabled = RaidLocked,
			values = function() return NameValues(field == "caller" and "GetRaidMembers" or "GetRaidShamans") end,
			get = function() local db = RaidDB(); return db and db.bloodlust[field] or "" end,
			set = function(_, value)
				if RaidLocked() then return end
				RaidDB().bloodlust[field] = value ~= "" and value or nil
				AssignmentChanged()
			end,
		}
	end
	local function ManaTideValues()
		local values = { [""] = "Select a shaman" }
		if SP.RaidCooldownsLoaded and SP.GetManaTideShamans then
			for _, info in ipairs(SP:GetManaTideShamans()) do
				values[info.name] = info.name .. " (Group " .. info.group .. ")"
			end
		end
		return values
	end
	local function SelectedManaTide()
		if selectedShaman ~= "" and ManaTideValues()[selectedShaman] then return selectedShaman end
		return ""
	end
	raid.manatide_shaman = {
		order = 8, type = "select", name = "Mana Tide Shaman", width = 1.5,
		disabled = function() return not SP.RaidCooldownsLoaded end,
		values = ManaTideValues, get = SelectedManaTide,
		set = function(_, value) selectedShaman = value end,
	}
	raid.manatide_caller = {
		order = 8.1, type = "select", name = "Selected Shaman's Mana Tide Caller", width = 1.5,
		disabled = function() return RaidLocked() or SelectedManaTide() == "" end,
		values = function() return NameValues("GetRaidMembers") end,
		get = function()
			local db = RaidDB()
			local assignment = db and db.manatide[SelectedManaTide()]
			return assignment and assignment.caller or ""
		end,
		set = function(_, value)
			local name = SelectedManaTide()
			if RaidLocked() or name == "" then return end
			local mt = RaidDB().manatide
			mt[name] = mt[name] or {}
			mt[name].caller = value ~= "" and value or nil
			AssignmentChanged()
		end,
	}
	raid.drums_caller = {
		order = 9, type = "select", name = "Drums Caller", width = 1.5,
		hidden = function() return not HasDrums() end, disabled = RaidLocked,
		values = function() return NameValues("GetRaidMembers") end,
		get = function() local db = RaidDB(); return db and db.drums.caller or "" end,
		set = function(_, value)
			if RaidLocked() then return end
			RaidDB().drums.caller = value ~= "" and value or nil
			AssignmentChanged()
		end,
	}
	local function GroupValues()
		local values = {}
		if SP.RaidCooldownsLoaded and SP.GetGroupMembers then
			for group in pairs(SP:GetGroupMembers()) do values[group] = "Group " .. group end
		end
		return values
	end
	local function SelectedGroup()
		if GroupValues()[selectedGroup] then return selectedGroup end
		return nil
	end
	raid.drums_group = {
		order = 9.1, type = "select", name = "Drums Group", width = 1.5,
		hidden = function() return not HasDrums() end,
		disabled = function() return not SP.RaidCooldownsLoaded end,
		values = GroupValues, get = SelectedGroup,
		set = function(_, value) selectedGroup = value end,
	}
	raid.drums_drummer = {
		order = 9.2, type = "select", name = "Selected Group's Drummer", width = 1.5,
		hidden = function() return not HasDrums() end,
		disabled = function() return RaidLocked() or not SelectedGroup() end,
		values = function()
			local values = { [""] = "None" }
			if SP.RaidCooldownsLoaded and SP.GetGroupMembers then
				for _, name in ipairs(SP:GetGroupMembers()[selectedGroup] or {}) do values[name] = name end
			end
			return values
		end,
		get = function() local db = RaidDB(); return db and db.drums.drummers[selectedGroup] or "" end,
		set = function(_, value)
			if RaidLocked() or not SelectedGroup() then return end
			RaidDB().drums.drummers[selectedGroup] = value ~= "" and value or nil
			AssignmentChanged()
		end,
	}

	local tremor = pages.tremorreminder_section.args
	tremor.tremor_manage_mobs.order = 0.5
	tremor.tremor_manage_mobs.name = "Open Fear-Caster Mob List"
	tremor.tremor_manage_mobs.disabled = function() return not SP.TremorReminderLoaded end
	local selectedMob = ""
	local function FearDB()
		if not SP.TremorReminderLoaded or not ShamanPowerTremorReminderDB then return nil end
		ShamanPowerTremorReminderDB.fearCasters = ShamanPowerTremorReminderDB.fearCasters or {}
		return ShamanPowerTremorReminderDB
	end
	local function FearDefaults() return SP.GetDefaultFearCasters and SP:GetDefaultFearCasters() or {} end
	local function FearChanged()
		if SP.RefreshMobList then SP:RefreshMobList() end
	end
	local function AddFearName(name)
		if issecretvalue and issecretvalue(name) then return end
		local db = FearDB()
		if not db or type(name) ~= "string" then return end
		name = strtrim(name)
		if name == "" then return end
		db.fearCasters[name] = true
		FearChanged()
	end
	local function FearValues()
		local values = { [""] = "Select a mob" }
		local db = FearDB()
		if not db then return values end
		local defaults = FearDefaults()
		if db.useDefaultList ~= false then
			for name in pairs(defaults) do if db.fearCasters[name] ~= false then values[name] = name end end
		end
		for name, enabled in pairs(db.fearCasters) do
			if enabled and not defaults[name] then values[name] = name end
		end
		return values
	end
	tremor.fear_add_name = {
		order = 5, type = "input", name = "Add a Mob by Name", width = "full",
		desc = "Enter the exact mob name and press Enter to add it to the fear-caster list.",
		disabled = function() return not SP.TremorReminderLoaded end,
		get = function() return "" end, set = function(_, value) AddFearName(value) end,
	}
	tremor.fear_add_target = {
		order = 5.1, type = "execute", name = "Add Current Target", width = 1.5,
		disabled = function() return not SP.TremorReminderLoaded end,
		func = function()
			local name, hostile = UnitName("target"), UnitCanAttack("player", "target")
			if issecretvalue and (issecretvalue(name) or issecretvalue(hostile)) then
				SP:Print("This target's identity is hidden; add its name manually out of combat.")
			elseif name and hostile then AddFearName(name); Notify()
			else SP:Print("Target an enemy first.") end
		end,
	}
	tremor.fear_remove_select = {
		order = 5.2, type = "select", name = "Fear-Caster Mob", width = 1.5,
		disabled = function() return not SP.TremorReminderLoaded end,
		values = FearValues,
		get = function() return FearValues()[selectedMob] and selectedMob or "" end,
		set = function(_, value) selectedMob = value end,
	}
	tremor.fear_remove = {
		order = 5.3, type = "execute", name = "Remove Selected Mob", width = 1.5,
		disabled = function() return not SP.TremorReminderLoaded or selectedMob == "" or not FearValues()[selectedMob] end,
		func = function()
			local db = FearDB()
			if not db or selectedMob == "" or not FearValues()[selectedMob] then return end
			if FearDefaults()[selectedMob] then db.fearCasters[selectedMob] = false
			else db.fearCasters[selectedMob] = nil end
			selectedMob = ""
			FearChanged(); Notify()
		end,
	}
	tremor.fear_restore_defaults = {
		order = 5.4, type = "execute", name = "Restore Removed Defaults", width = "full",
		desc = "Restore hidden built-in mobs without removing custom additions.",
		disabled = function() return not SP.TremorReminderLoaded end,
		func = function()
			local db = FearDB()
			if not db then return end
			local defaults = FearDefaults()
			for name, enabled in pairs(db.fearCasters) do
				if enabled == false and defaults[name] then db.fearCasters[name] = nil end
			end
			FearChanged(); Notify()
		end,
	}

	local popout = pages.popout_section.args
	local selectedPopout = ""
	local function PopoutKey()
		if SP.poppedOutFrames and SP.poppedOutFrames[selectedPopout] then return selectedPopout end
		return nil
	end
	local function PopoutSettings()
		local key = PopoutKey()
		return key and SP.opt.poppedOutSettings and SP.opt.poppedOutSettings[key] or {}
	end
	local function PopoutLocked() return InCombatLockdown() or not PopoutKey() end
	popout.open_window = {
		order = 0.5, type = "execute", name = "Open Pop-Out Settings", width = "full",
		disabled = function() return not PopoutKey() end,
		func = function()
			local key = PopoutKey()
			if key then SP:ShowPopOutSettingsPanel(key, SP.poppedOutFrames[key]) end
		end,
	}
	popout.selected_tracker = {
		order = 3, type = "select", name = "Popped-Out Tracker", width = "full",
		values = function()
			local values = { [""] = "Select a popped-out tracker" }
			for key, frame in pairs(SP.poppedOutFrames or {}) do
				values[key] = frame.title and frame.title ~= "" and frame.title or key
			end
			return values
		end,
		get = function() return PopoutKey() or "" end,
		set = function(_, value) selectedPopout = value end,
	}
	popout.selected_scale = {
		order = 3.1, type = "range", name = "Selected Tracker Scale", width = 1.5,
		min = 0.5, max = 3, step = 0.05, isPercent = true, disabled = PopoutLocked,
		get = function() return PopoutSettings().scale or SP.opt.poppedOutDefaultScale or 1 end,
		set = function(_, value) if not PopoutLocked() then SP:SetPopOutScale(PopoutKey(), value) end end,
	}
	popout.selected_opacity = {
		order = 3.2, type = "range", name = "Selected Tracker Opacity", width = 1.5,
		min = 0.1, max = 1, step = 0.05, isPercent = true, disabled = PopoutLocked,
		get = function() return PopoutSettings().opacity or SP.opt.poppedOutDefaultOpacity or 1 end,
		set = function(_, value) if not PopoutLocked() then SP:SetPopOutOpacity(PopoutKey(), value) end end,
	}
	popout.selected_hide_frame = {
		order = 3.3, type = "toggle", name = "Hide Selected Tracker Frame", width = "full", disabled = PopoutLocked,
		get = function() return PopoutSettings().hideFrame or false end,
		set = function(_, value)
			if not PopoutLocked() and (PopoutSettings().hideFrame or false) ~= value then SP:TogglePopOutFrame(PopoutKey()) end
		end,
	}
	popout.selected_flyout_direction = {
		order = 3.4, type = "select", name = "Selected Tracker Flyout Direction", width = 1.5,
		values = { top = "Top", bottom = "Bottom", left = "Left", right = "Right" },
		sorting = { "top", "bottom", "left", "right" }, disabled = PopoutLocked,
		hidden = function() local key = PopoutKey(); return not (key and key:match("^totem_")) end,
		get = function() return PopoutSettings().flyoutDirection or "bottom" end,
		set = function(_, value) if not PopoutLocked() then SP:SetPopOutFlyoutDirection(PopoutKey(), value) end end,
	}
	popout.selected_return = {
		order = 3.5, type = "execute", name = "Return Selected Tracker to Bar", width = "full", disabled = PopoutLocked,
		func = function()
			if PopoutLocked() then return end
			SP:ReturnPopOutToBar(PopoutKey())
			selectedPopout = ""
			Notify()
		end,
	}

	-- Existing page setters also publish changes, so a dialog/cog that is already
	-- open refreshes. Wrapping once at definition time preserves their behaviour.
	local function NotifySetters(args, prefix)
		for key, option in pairs(args) do
			if (not prefix or key:sub(1, #prefix) == prefix) and type(option.set) == "function" then
				local setter = option.set
				option.set = function(...) setter(...); Notify() end
			end
		end
	end
	NotifySetters(range)
	NotifySetters(raid)
	NotifySetters(es)
	NotifySetters(reactive)
	NotifySetters(tremor)
	NotifySetters(popout)
	NotifySetters(pages.partybuff_section.args, "coverage_")
	local resetMobs = tremor.tremor_reset_moblist.func
	tremor.tremor_reset_moblist.func = function(...) resetMobs(...); Notify() end
	local returnPopouts = popout.popout_return_all.func
	popout.popout_return_all.func = function(...) returnPopouts(...); Notify() end
end

-- Native hosts share the custom display options; native layout and actions stay
-- Blizzard-owned. Lifetime widgets never touch Blizzard's spell cooldowns.
do
	local SP = ShamanPower
	local root = SP.options.args
	local pages = root.fluffy.args
	local bar = root.buttons.args.auto_button.args
	local mode = root.settings.args.settings_totemMode.args   -- Mode & Twisting: where the display modes live
	local duration = pages.totembar_duration_section.args
	local function NotifyNative()
		if SP.RefreshConfig then SP:RefreshConfig() end
		local registry = LibStub("AceConfigRegistry-3.0", true)
		if registry then registry:NotifyChange("ShamanPower") end
	end
	local function NativeLocked()
		return not HasLoadoutSetControls() or not SP.RefreshBlizzardTotemBar or InCombatLockdown()
	end
	local scaleRefreshQueued = false
	local function RefreshNative()
		if NativeTotemBarSelected() and SP.RefreshBlizzardTotemBar then
			SP:RefreshBlizzardTotemBar()
			NotifyNative()
		end
	end
	mode.use_blizzard_totem_bar = {
		order = 4.85, type = "toggle", name = "Use Blizzard's Totem Bar", width = "full",
		desc = "Use Blizzard's buttons and flyouts with ShamanPower's lifetime, pulse and party overlays. "
			.. "Change out of combat.",
		hidden = function() return not HasLoadoutSetControls() end,
		disabled = NativeLocked,
		get = function() return SP.opt.useBlizzardTotemBar == true end,
		set = function(_, value)
			if NativeLocked() then return end
			SP.opt.useBlizzardTotemBar = value
			-- the bar's move overlay would stay behind with its checkbox hidden
			if value and SP.SetTotemBarUnlocked and SP.opt.display and SP.opt.display.moverUnlocked then SP:SetTotemBarUnlocked(false) end
			SP:RefreshBlizzardTotemBar()
			NotifyNative()
		end,
	}
	mode.hide_blizzard_totem_bar = {
		order = 4.855, type = "toggle", name = "Hide Blizzard's Totem Bar", width = "full",
		desc = "While you use ShamanPower's bar, keep Blizzard's own totem bar hidden so you do not get two. It still shows in Edit Mode. Turn this off to keep both.",
		hidden = function() return not HasLoadoutSetControls() or NativeTotemBarSelected() end,
		get = function() return SP.opt.hideBlizzardTotemBar ~= false end,
		set = function(_, value)
			if value then SP.opt.hideBlizzardTotemBar = nil else SP.opt.hideBlizzardTotemBar = false end
			if SP.ApplyBlizzardTotemBarHiding then SP:ApplyBlizzardTotemBarHiding() end
		end,
	}
	mode.blizzard_totem_bar_note = {
		order = 4.86, type = "description", width = "full",
		hidden = function() return not NativeTotemBarSelected() end,
		name = "|cffffa040Blizzard controls layout, visibility and flyouts. Icons / TotemTimers style, duration bars, text, "
			.. "pulse, party dots and counters apply to ShamanPower's overlays. Lifetime swipes use our totem model; "
			.. "Blizzard's spell cooldowns are unchanged. Compact style needs ShamanPower's bar.|r",
	}
	mode.blizzard_totem_bar_scale_override = {
		order = 4.87, type = "toggle", name = "Override Blizzard Bar Scale", width = "full",
		desc = "Optional: scale relative to Blizzard's original bar size. Off leaves that size alone. Out of combat only.",
		hidden = function() return not NativeTotemBarSelected() end,
		disabled = NativeLocked,
		get = function() return SP.opt.blizzardTotemBarScale ~= nil end,
		set = function(_, value)
			if NativeLocked() or not NativeTotemBarSelected() then return end
			SP.opt.blizzardTotemBarScale = value and 1 or nil
			SP:RefreshBlizzardTotemBar()
			NotifyNative()
		end,
	}
	mode.blizzard_totem_bar_scale = {
		order = 4.88, type = "range", name = "Blizzard Bar Relative Scale", width = 1.5,
		min = 0.5, max = 2, step = 0.05, isPercent = true,
		desc = "100% is Blizzard's original bar scale, not ShamanPower's bar scale. Reapplied after Edit Mode.",
		hidden = function() return not NativeTotemBarSelected() end,
		disabled = function() return NativeLocked() or SP.opt.blizzardTotemBarScale == nil end,
		get = function() return SP.opt.blizzardTotemBarScale or 1 end,
		set = function(_, value)
			if NativeLocked() or not NativeTotemBarSelected() or SP.opt.blizzardTotemBarScale == nil then return end
			if type(value) ~= "number" or value ~= value or value < 0.5 or value > 2 then return end
			SP.opt.blizzardTotemBarScale = value
			-- A drag sets this many times a second; the full bar refresh is heavy.
			-- Apply once, shortly after the last change.
			if not scaleRefreshQueued then
				scaleRefreshQueued = true
				C_Timer.After(0.15, function()
					scaleRefreshQueued = false
					if SP.RefreshBlizzardTotemBar then SP:RefreshBlizzardTotemBar() end
				end)
			end
		end,
	}
	mode.blizzard_totem_bar_scale_reset = {
		order = 4.89, type = "execute", name = "Restore Blizzard Bar Scale", width = 1.5,
		desc = "Remove the override and restore the original native bar scale. Out of combat only.",
		hidden = function() return not NativeTotemBarSelected() end,
		disabled = function() return NativeLocked() or SP.opt.blizzardTotemBarScale == nil end,
		func = function()
			if NativeLocked() or not NativeTotemBarSelected() then return end
			SP.opt.blizzardTotemBarScale = nil
			SP:RefreshBlizzardTotemBar()
			NotifyNative()
		end,
	}

	local function HideForNative(option)
		if not option then return end
		local previous = option.hidden
		option.hidden = function(info)
			if NativeTotemBarSelected() then return true end
			if type(previous) == "function" then return previous(info) end
			return previous
		end
	end
	local function HideFields(args, names)
		for _, name in ipairs(names) do HideForNative(args[name]) end
	end
	HideFields(pages, { "totembar_items_section", "totembar_order_section", "totemflyouts_section",
		"texture_section", "color_section" })
	HideFields(bar, { "unlock_totem_bar", "auto_enable", "show_dropall", "show_totem_flyouts" })
	HideFields(root.settings.args.settings_totemMode.args, { "dynamicMode", "dynamicModeDesc", "activeAsMainSpacer",
		"rightClickCastsAssigned", "rightClickDestroysTotem", "compactOptions" })
	HideFields(root.settings.args.settings_show.args, { "showparty", "showsingle" })
	HideFields(root.settings.args.settings_visibility.args, { "hideOutOfCombat", "hideWhenNoTotems",
		"fadeInsteadOfHide", "fadeOpacity", "fadeSmooth", "showWithTarget" })
	HideFields(pages.layout_section.args, { "layout", "totem_flyout_direction", "totem_flyout_button_size",
		"swap_flyout_clicks", "flyout_show_empty" })
	HideFields(pages.scale_section.args, { "buffscale" })
	HideFields(pages.opacity_section.args, { "totemBarOpacity", "totemBarFullOpacityWhenActive", "totemFlyoutOpacity" })
	HideFields(pages.padding_section.args, { "totemBarPadding" })
	HideFields(pages.visibility_section.args, { "hide_totem_bar_frame" })
	HideFields(duration, { "compact_override_note" })
	local compactDisabled, compactSetter = mode.compactStyle.disabled, mode.compactStyle.set
	mode.compactStyle.disabled = function(info)
		if NativeTotemBarSelected() then return true end
		return compactDisabled(info)
	end
	mode.compactStyle.set = function(...)
		if not NativeTotemBarSelected() then compactSetter(...) end
	end
	mode.blizzard_compact_note = {
		order = 4.75, type = "description", width = "full",
		hidden = function() return not NativeTotemBarSelected() end,
		name = "Compact style is available only on ShamanPower's bar.",
	}
	-- Rebuild geometry only after a settings action, never from the update tick.
	local function RefreshAfter(option)
		local setter = option.set
		option.set = function(...) setter(...); RefreshNative() end
	end
	RefreshAfter(mode.activeTotemAsMain)
	RefreshAfter(pages.layout_section.args.activeOverlayDirection)
	for _, name in ipairs({ "duration_bar_position", "duration_bar_height",
		"show_duration_text", "duration_text_size" }) do
		RefreshAfter(duration[name])
	end
	local durationDescription = duration.duration_desc.name
	duration.duration_desc.name = function()
		if NativeTotemBarSelected() then
			return "Duration bars and text share ShamanPower's bar settings. On Icon uses the engine countdown; "
				.. "other text locations use the plain totem-duration model. Swipe settings below control our lifetime "
				.. "overlay, not Blizzard's spell cooldowns."
		end
		return durationDescription
	end

	local function LifetimeOption(option, name, description, disabled)
		local oldName, oldDescription, oldDisabled, oldSetter = option.name, option.desc, option.disabled, option.set
		option.name = function(info)
			if NativeTotemBarSelected() then return name end
			if type(oldName) == "function" then return oldName(info) end
			return oldName
		end
		option.desc = function(info)
			if NativeTotemBarSelected() then return description end
			if type(oldDescription) == "function" then return oldDescription(info) end
			return oldDescription
		end
		option.disabled = function(info)
			if NativeTotemBarSelected() then return disabled and disabled() or false end
			if type(oldDisabled) == "function" then return oldDisabled(info) end
			return oldDisabled
		end
		option.set = function(...) oldSetter(...); RefreshNative() end
	end
	LifetimeOption(duration.show_totem_cooldowns, "Show Totem Lifetime Swipe",
		"Show ShamanPower's active-totem lifetime swipe. Duration bars and positioned text are independent; "
			.. "Blizzard's spell cooldowns are untouched.")
	LifetimeOption(duration.totem_cooldown_sweep, "Lifetime Swipe Style",
		"Draw the totem lifetime as a radial swipe, a vertical grey sweep, or a reverse vertical sweep.",
		function() return SP.opt.showTotemCooldowns == false end)
	LifetimeOption(duration.totem_cooldown_edge, "Radial Edge Line",
		"Draw the bright edge on ShamanPower's radial lifetime swipe.",
		function() return SP.opt.showTotemCooldowns == false or (SP.opt.totemCooldownSweep or "radial") ~= "radial" end)
	LifetimeOption(duration.totem_cooldown_text, "Show On-Icon Lifetime Number",
		"When Show Duration is On Icon, show the engine-drawn number. Other text locations are independent.",
		function() return SP.opt.durationTextLocation ~= "icon" end)
	LifetimeOption(duration.totem_cooldown_text_color, "Lifetime Text Color",
		"Color of the engine-drawn lifetime numbers on ShamanPower's overlay.",
		function() return SP.opt.totemCooldownText == false or SP.opt.durationTextLocation ~= "icon" end)
	for _, name in ipairs({ "totem_cooldown_numbers_note", "totem_cooldown_numbers_button" }) do
		local option = duration[name]
		local oldHidden = option.hidden
		option.hidden = function(info)
			if not NativeTotemBarSelected() then return oldHidden(info) end
			return not (SP.EngineCooldownsOn and SP:EngineCooldownsOn() and SP.opt.durationTextLocation == "icon"
				and SP.opt.totemCooldownText ~= false
				and not SP:CountdownNumbersEnabled())
		end
	end
	local enableNumbers = duration.totem_cooldown_numbers_button.func
	duration.totem_cooldown_numbers_button.func = function(...) enableNumbers(...); RefreshNative() end
end

-- Cooldown bar order: one dropdown per button that can exist on this client.
-- These were eight hand-written copies of one fixed list (Shield ... Shamanistic
-- Rage), so clients without some of those spells still offered them, and the
-- three newer buttons could not be placed at all.
do
	local section = ShamanPower.options.args.fluffy and ShamanPower.options.args.fluffy.args.cdbar_order_section
	local ordinals = { "1st", "2nd", "3rd", "4th", "5th", "6th", "7th", "8th", "9th", "10th", "11th" }
	if section and section.args then
		for i = 1, 11 do   -- ShamanPower.COOLDOWN_TYPE_COUNT; this file may load before it is defined
			section.args["cooldown_bar_order_" .. i] = {
				order = i,
				type = "select",
				name = ordinals[i] .. " Position",
				desc = "Which button sits in position " .. i .. ". Picking a button that is already placed swaps the two.",
				width = 1.5,
				hidden = function() return i > #ShamanPower:GetCooldownBarOrder() end,
				values = function() return ShamanPower:CooldownBarOrderChoices() end,
				get = function(info) return ShamanPower:GetCooldownBarOrder()[i] end,
				set = function(info, val) ShamanPower:SetCooldownBarOrderSlot(i, val) end,
			}
		end
	end
end

-- Grid is a visual style; Dynamic Mode remains an independent assignment policy.
do
	local SP = ShamanPower
	local mode = SP.options.args.settings.args.settings_totemMode.args
	local function GridLocked()
		return SP.opt.enabled == false or InCombatLockdown() or not SP.SetGridStyle or not SP.RefreshGridStyle
	end
	local function NotifyGrid()
		if SP.RefreshConfig then SP:RefreshConfig() end
		local config = rawget(_G, "ShamanPowerConfig")
		if config and config.PreviewChanged then config:PreviewChanged() end
	end
	mode.gridStyle = {
		order = 4.76, type = "toggle", name = "Grid Style", width = "full",
		desc = "Keep each element's existing totem choices visible in a row. "
			.. "Clicks and assignments keep their flyout controls. "
			.. "Only Show Learned Elements still applies. Change style out of combat.",
		disabled = GridLocked,
		get = function() return SP.opt.gridStyle == true end,
		set = function(_, value)
			if GridLocked() then return end
			SP:SetGridStyle(value)
			SP:FollowStyleSpot()   -- each style keeps its own spot
			NotifyGrid()
		end,
	}
	mode.gridDropAssigns = {
		order = 4.765, type = "toggle", name = "Left-Click Also Assigns", width = "full",
		desc = "Clicking a totem in the Grid drops it AND makes it that element's assigned totem, the way Dynamic Mode "
			.. "treats every drop: the highlight moves to it, and your keybind and Drop All cast it next. "
			.. "Off: left-click only drops, right-click assigns.",
		hidden = function() return not SP.opt.gridStyle end,
		get = function() return SP.opt.gridDropAssigns ~= false end,
		set = function(_, value) SP.opt.gridDropAssigns = value; NotifyGrid() end,
	}
	mode.gridSplit = {
		order = 4.77, type = "toggle", name = "Split by Element", width = "full",
		desc = "Give each row its own pop-out frame. Unlock UI moves the four rows; "
			.. "positions use the existing pop-out settings. Middle-clicking a row splits the Grid; "
			.. "returning one row recombines it. Grid rows always keep their element border.",
		hidden = function() return not SP.opt.gridStyle end,
		disabled = GridLocked,
		get = function() return SP.opt.gridSplit == true end,
		set = function(_, value)
			if GridLocked() or not SP.opt.gridStyle then return end
			SP.opt.gridSplit = value
			SP:RefreshGridStyle()
			NotifyGrid()
		end,
	}
	local elementNames = { "Earth", "Fire", "Water", "Air" }
	for element, name in ipairs(elementNames) do
		local index = element
		mode["gridOrientation" .. element] = {
			order = 4.78 + element * 0.001, type = "select", name = name .. " Row Direction", width = 1.5,
			values = { horizontal = "Horizontal", vertical = "Vertical" },
			sorting = { "horizontal", "vertical" },
			hidden = function() return not (SP.opt.gridStyle and SP.opt.gridSplit) end,
			disabled = GridLocked,
			get = function() return SP.opt.gridOrientation and SP.opt.gridOrientation[index] or "horizontal" end,
			set = function(_, value)
				if GridLocked() or not (SP.opt.gridStyle and SP.opt.gridSplit) then return end
				if value ~= "horizontal" and value ~= "vertical" then return end
				SP.opt.gridOrientation = SP.opt.gridOrientation or {}
				SP.opt.gridOrientation[index] = value
				SP:RefreshGridStyle()
				NotifyGrid()
			end,
		}
	end
	local function ClearGridBefore(option)
		if not option or not option.set then return end
		local setter = option.set
		option.set = function(info, value, ...)
			if value and SP.opt.gridStyle then
				if InCombatLockdown() or not SP.SetGridStyle then return end
				SP:SetGridStyle(false)
				if SP.opt.gridStyle then return end
			end
			setter(info, value, ...)
		end
	end
	ClearGridBefore(mode.compactStyle)
	ClearGridBefore(mode.activeTotemAsMain)
	ClearGridBefore(mode.use_blizzard_totem_bar)
end

-- General > Main: one dropdown for the totem bar's style, so the choice made in
-- the setup tour is one click away afterwards. It reads and writes the same
-- flags as the Mode & Twisting toggles, through ShamanPowerStyles.lua. The
-- settings window previews a style while it is hovered in the list, and the
-- style toggles on Mode & Twisting do the same; OptionHoverStyle tells it
-- which options those are (keyed by the option table: AceConfig allows no
-- extra keys inside one).
do
	local SP = ShamanPower
	local main = SP.options.args.settings.args.settings_show.args
	local mode = SP.options.args.settings.args.settings_totemMode.args
	main.totemBarStyle = {
		order = 1.5, type = "select", name = "Totem Bar Style", width = 1.5,
		desc = function()
			local d = "Which bar you play with: one of the four looks of ShamanPower's bar, every totem laid out in a grid"
			if WOW_PROJECT_ID == WOW_PROJECT_MAINLINE then d = d .. ", or Blizzard's own totem bar with ShamanPower's timers, bars and dots on its slots" end
			return d .. ". Hover a style in the list to see it in the live preview (the arrow tab on the right). Mode & Twisting has each style's own settings. Change out of combat."
		end,
		hidden = function() return not isShaman or not SP.TotemBarStyleList end,
		disabled = function() return SP.opt.enabled == false or InCombatLockdown() end,
		values = function()
			local v = {}
			for _, st in ipairs(SP:TotemBarStyleList()) do v[st.key] = st.label end
			return v
		end,
		sorting = function()
			local order = {}
			for _, st in ipairs(SP:TotemBarStyleList()) do order[#order + 1] = st.key end
			return order
		end,
		get = function() return SP:GetTotemBarStyle() end,
		set = function(_, value) SP:SetTotemBarStyle(value) end,
	}
	-- right under the style picker too (same setting as on Mode & Twisting)
	main.hide_blizzard_totem_bar = {
		order = 1.55, type = "toggle", name = "Hide Blizzard's Totem Bar", width = "full",
		desc = "While you use ShamanPower's bar, keep Blizzard's own totem bar hidden so you do not get two. It still shows in Edit Mode. Turn this off to keep both.",
		hidden = function() return not isShaman or not HasLoadoutSetControls() or NativeTotemBarSelected() end,
		get = function() return SP.opt.hideBlizzardTotemBar ~= false end,
		set = function(_, value)
			if value then SP.opt.hideBlizzardTotemBar = nil else SP.opt.hideBlizzardTotemBar = false end
			if SP.ApplyBlizzardTotemBarHiding then SP:ApplyBlizzardTotemBarHiding() end
		end,
	}
	SP.OptionHoverStyle = {
		[main.totemBarStyle] = "select",
		[mode.dynamicMode] = "dynamic",
		[mode.activeTotemAsMain] = "totemtimers",
		[mode.compactStyle] = "compact",
	}
	if mode.gridStyle then SP.OptionHoverStyle[mode.gridStyle] = "grid" end
	if mode.use_blizzard_totem_bar then SP.OptionHoverStyle[mode.use_blizzard_totem_bar] = "blizzard" end
end

-- General > Main: where to get help. WoW cannot open links, so the invite sits in
-- a box the player can select and copy (Ctrl+A, Ctrl+C); typing in it changes nothing.
do
	local SP = ShamanPower
	local main = SP.options.args.settings.args.settings_show.args
	local INVITE = "https://discord.gg/eCtNeBqE8U"
	-- WoW gives addons no clipboard: "Copy Link" opens ShamanPower's own box with the
	-- link already selected, so one Ctrl+C copies it (the usual way addons do this).
	main.community = {
		order = 90, type = "group", inline = true, name = "ShamanPower Discord",
		args = {
			about = {
				order = 1, type = "description", width = "full",
				name = "|cff5865F2Join the ShamanPower Discord|r - the best way to reach me directly.\n"
					.. "|cffffd200>|r  Get help setting ShamanPower up\n"
					.. "|cffffd200>|r  Report bugs straight to the developer\n"
					.. "|cffffd200>|r  Suggest new features and vote on ideas\n"
					.. "|cffffd200>|r  Try new builds before anyone else",
			},
			link = {
				order = 2, type = "input", name = "Invite link", width = "full",
				desc = "Click Copy Link, or click the box and press Ctrl+A then Ctrl+C, then paste it into your browser.",
				get = function() return INVITE end,
				set = function() end,   -- read-only: the box always shows the invite
			},
			copy = {
				order = 3, type = "execute", name = "Copy Link", width = "full",
				desc = "Opens a small box with the link selected: press Ctrl+C to copy it.",
				func = function()
					SP:ShowSPDialog({ key = "discordLink", title = "ShamanPower Discord",
						text = "The link is selected: press |cffFFD100Ctrl+C|r to copy it, then paste it into your browser.",
						editText = INVITE })
				end,
			},
		},
	}
	-- the Discord section's heading is the big gold featured one (Widgets SectionHeader)
	SP.OptionFeaturedHeader = SP.OptionFeaturedHeader or {}
	SP.OptionFeaturedHeader[main.community] = "Interface\\AddOns\\ShamanPower\\Media\\discord"   -- Discord's logo, transparent
end

-- General > Fonts: the typeface and outline of the text ShamanPower draws on
-- screen (ShamanPowerFonts.lua). "Default" keeps each element's designed font.
-- Hovering a font in a list shows it on the frames and in the live preview.
do
	local SP = ShamanPower
	local settings = SP.options.args.settings.args
	local function refresh() if SP.RefreshFonts then SP:RefreshFonts() end end
	local function fontValues(inheritLabel)
		return function()
			local v = { __default = inheritLabel or "Default (as designed)" }
			for _, name in ipairs(SP:FontList()) do v[name] = name end
			return v
		end
	end
	local function fontSorting(first)
		return function()
			local order = { first }
			for _, name in ipairs(SP:FontList()) do order[#order + 1] = name end
			return order
		end
	end
	local function outlineValues(inheritLabel)
		local v = { __default = inheritLabel or "Default (as designed)" }
		for _, o in ipairs(SP.FONT_OUTLINES) do v[o.value == "" and "__none" or o.value] = o.label end
		return v
	end
	local OUTLINE_ORDER = { "__default", "__none", "OUTLINE", "THICKOUTLINE" }
	local function toOutline(v) if v == "__default" then return nil elseif v == "__none" then return "" else return v end end
	local function fromOutline(o) if o == nil then return "__default" elseif o == "" then return "__none" else return o end end
	local function area(key)
		SP.opt.fontAreas = SP.opt.fontAreas or {}
		SP.opt.fontAreas[key] = SP.opt.fontAreas[key] or {}
		return SP.opt.fontAreas[key]
	end

	local args = {
		fonts_desc = {
			order = 0, type = "description", width = "full",
			name = "The font of the numbers and text ShamanPower draws on screen: totem timers, cooldown numbers, shield charges, alerts, names and labels."
				.. " Default keeps each one's designed font. The list holds WoW's own fonts plus every font your other addons share (ElvUI, SharedMedia and the like)."
				.. " Hover a font to see it before you pick it.",
		},
		fontName = {
			order = 1, type = "select", name = "Font", width = 1.5,
			desc = "The font for everything ShamanPower draws on screen, unless a section below picks its own.",
			values = fontValues(), sorting = fontSorting("__default"),
			get = function() return SP.opt.fontName or "__default" end,
			set = function(_, v) SP.opt.fontName = (v ~= "__default") and v or nil; refresh() end,
		},
		fontOutline = {
			order = 2, type = "select", name = "Outline", width = 1,
			desc = "The text's outline. Default keeps each element's designed outline.",
			values = outlineValues(), sorting = OUTLINE_ORDER,
			get = function() return fromOutline(SP.opt.fontOutline) end,
			set = function(_, v) SP.opt.fontOutline = toOutline(v); refresh() end,
		},
		fonts_areas = { order = 10, type = "header", name = "Per Area" },
		fonts_areas_desc = {
			order = 10.1, type = "description", width = "full",
			name = "Give one part of ShamanPower its own font or outline. \"Same as above\" follows the Font and Outline at the top.",
		},
		fonts_reset = {
			order = 19, type = "execute", name = "Reset All Fonts", width = "full",
			desc = "Back to the designed font and outline everywhere.",
			func = function() SP.opt.fontName, SP.opt.fontOutline, SP.opt.fontAreas = nil, nil, nil; refresh() end,
		},
	}
	for i, a in ipairs(SP.FONT_AREAS) do
		local key = a.key
		args["font_" .. key] = {
			order = 10 + i, type = "select", name = a.label, width = 1.5,
			desc = a.desc,
			values = fontValues("Same as above"), sorting = fontSorting("__default"),
			get = function() local t = SP.opt.fontAreas and SP.opt.fontAreas[key]; return (t and t.name) or "__default" end,
			set = function(_, v) area(key).name = (v ~= "__default") and v or nil; refresh() end,
		}
		args["font_" .. key .. "_outline"] = {
			order = 10 + i + 0.5, type = "select", name = "Outline", width = 1,
			values = outlineValues("Same as above"), sorting = OUTLINE_ORDER,
			get = function() local t = SP.opt.fontAreas and SP.opt.fontAreas[key]; return fromOutline(t and t.outline) end,
			set = function(_, v) area(key).outline = toOutline(v); refresh() end,
		}
	end
	settings.settings_fonts = { order = 1.2, type = "group", name = "Fonts & Textures", args = args }

	-- the settings window previews a hovered font: option table -> area ("all" = the main font)
	SP.OptionHoverFont = { [args.fontName] = "all" }
	for _, a in ipairs(SP.FONT_AREAS) do SP.OptionHoverFont[args["font_" .. a.key]] = a.key end
end

-- General > Fonts & Textures, second half: the bar fills' texture
-- (ShamanPowerTextures.lua), and one button to apply the chosen look everywhere.
do
	local SP = ShamanPower
	local args = SP.options.args.settings.args.settings_fonts.args
	local function refresh() if SP.RefreshTextures then SP:RefreshTextures() end end
	local function texValues(inheritLabel)
		return function()
			local v = { __default = inheritLabel or "Default (as designed)" }
			for _, name in ipairs(SP:TextureList()) do v[name] = name end
			return v
		end
	end
	local function texSorting()
		local order = { "__default" }
		for _, name in ipairs(SP:TextureList()) do order[#order + 1] = name end
		return order
	end
	local function areas()
		SP.opt.barTextureAreas = SP.opt.barTextureAreas or {}
		return SP.opt.barTextureAreas
	end

	args.textures_header = { order = 40, type = "header", name = "Bar Textures" }
	args.textures_desc = {
		order = 40.1, type = "description", width = "full",
		name = "The texture of the bars ShamanPower draws: totem duration bars, cooldown bar progress, pulse sweeps."
			.. " Default keeps each bar's designed flat colour; a texture is tinted with the same colour."
			.. " The list holds WoW's bar, ShamanPower's four and every bar texture your other addons share. Hover one to see it.",
	}
	args.barTexture = {
		order = 41, type = "select", name = "Bar Texture", width = 1.5,
		desc = "The texture for every bar, unless an area below picks its own.",
		values = texValues(), sorting = texSorting,
		get = function() return SP.opt.barTexture or "__default" end,
		set = function(_, v) SP.opt.barTexture = (v ~= "__default") and v or nil; refresh() end,
	}
	for i, a in ipairs(SP.TEXTURE_AREAS) do
		local key = a.key
		args["texture_" .. key] = {
			order = 42 + i, type = "select", name = a.label, width = 1.5,
			desc = a.desc,
			values = texValues("Same as above"), sorting = texSorting,
			get = function() local t = SP.opt.barTextureAreas; return (t and t[key]) or "__default" end,
			set = function(_, v) areas()[key] = (v ~= "__default") and v or nil; refresh() end,
		}
	end
	args.textures_reset = {
		order = 49, type = "execute", name = "Reset All Bar Textures", width = "full",
		desc = "Back to each bar's designed flat colour.",
		func = function() SP.opt.barTexture, SP.opt.barTextureAreas = nil, nil; refresh() end,
	}

	args.look_header = { order = 80, type = "header", name = "One Look Everywhere" }
	args.look_desc = {
		order = 80.1, type = "description", width = "full",
		name = "Apply This Look Everywhere uses the Font, Outline and Bar Texture at the top of this page for every part of ShamanPower:"
			.. " the per-area choices are cleared, and Compact's lines take the bar texture too. Reset Look goes back to the designed look.",
	}
	args.look_apply = {
		order = 81, type = "execute", name = "Apply This Look Everywhere", width = 1.5,
		func = function() SP:ApplyLookEverywhere() end,
	}
	args.look_reset = {
		order = 82, type = "execute", name = "Reset Look", width = 1,
		desc = "Fonts, outline, bar textures and Compact's line texture back to their defaults.",
		func = function() SP:ResetLook() end,
	}

	-- the settings window previews a hovered texture: option table -> area ("all" = the main texture)
	SP.OptionHoverTexture = { [args.barTexture] = "all" }
	for _, a in ipairs(SP.TEXTURE_AREAS) do SP.OptionHoverTexture[args["texture_" .. a.key]] = a.key end
end

-- General > Main (non-shamans): Windfury-only mode, set from the setup tour's
-- welcome or here. Everything else ShamanPower does is switched off while it is on.
do
	local SP = ShamanPower
	local main = SP.options.args.settings.args.settings_show.args
	main.windfuryOnly = {
		order = 0.5, type = "toggle", name = "Windfury-Only Mode", width = "full",
		desc = "Turns off every window, bar, icon and nameplate ShamanPower has on this character. It keeps quietly telling your group's shamans whether your weapon has Windfury, so their ShamanPower can show it.",
		hidden = function() return isShaman end,
		get = function() return SP.opt.windfuryOnly == true end,
		set = function(_, v) SP:SetWindfuryOnly(v) end,
	}
end

-- Move the actual option objects, keeping hover maps and callbacks intact.
-- Old leaf paths are kept for settings links into groups split across tabs.
function ShamanPower.MoveSettingsOptions(sourcePath, destinationPath, keys)
	local function resolve(path)
		local node = ShamanPower.options
		for _, key in ipairs(path) do node = node.args[key] end
		return node
	end
	local source, destination = resolve(sourcePath), resolve(destinationPath)
	local aliases = ShamanPower.SettingsPathAliases or {}
	ShamanPower.SettingsPathAliases = aliases
	for _, key in ipairs(keys) do
		if source.args[key] then
			destination.args[key], source.args[key] = source.args[key], nil
			local path = {}
			for _, part in ipairs(destinationPath) do path[#path + 1] = part end
			path[#path + 1] = key
			aliases[table.concat(sourcePath, "/") .. "/" .. key] = path
		end
	end
end

-- Coverage has its own tab; dots and counters keep their existing entry path.
do
	local SP = ShamanPower
	local pages = SP.options.args.fluffy.args
	local party = pages.partybuff_section
	local coverageKeys, watches, sizes = { "open_coverage" }, { "coverage_watch_desc" }, { "coverage_sizes_desc" }
	for key in pairs(party.args) do
		if key:match("^coverage_") then coverageKeys[#coverageKeys + 1] = key end
		if key:match("^coverage_watch_%d") then watches[#watches + 1] = key end
		if key:match("^coverage_size_%d") then sizes[#sizes + 1] = key end
	end
	local function byOrder(a, b) return party.args[a].order < party.args[b].order end
	table.sort(watches, byOrder)
	table.sort(sizes, byOrder)
	pages.coverage_section = {
		order = 14.1, type = "group", name = "Coverage", args = {},
		hidden = party.args.coverage_header.hidden,
	}
	SP.MoveSettingsOptions({ "fluffy", "partybuff_section" }, { "fluffy", "coverage_section" }, coverageKeys)
	SP.OrderSettingsBands(party, {
		{ keys = { "partybuff_desc", "module_missing_note", "partybuff_engine_note" } },
		{ keys = { "partybuff_display_mode" } },
		{ header = "look_header", name = "Look", keys = {
			"partybuff_scale", "partybuff_opacity", "partybuff_fontsize", "partybuff_dot_size",
			"partybuff_dot_outline", "partybuff_hide_frame", "partybuff_hide_label", "partybuff_colors",
		}, names = { partybuff_scale = "Scale", partybuff_opacity = "Opacity", partybuff_fontsize = "Text Size",
			partybuff_hide_frame = "Hide Background" } },
		{ header = "position_header", name = "Position", keys = {
			"partybuff_dot_position", "partybuff_location", "partybuff_move_counters_note",
			"partybuff_move_counters", "partybuff_locked", "partybuff_reset",
		}, names = { partybuff_move_counters = "Move", partybuff_locked = "Lock Position",
			partybuff_reset = "Reset Position" } },
	})
	SP.OrderSettingsBands(pages.coverage_section, {
		{ keys = { "coverage_desc" } },
		{ keys = { "coverage_enabled", "open_coverage" } },
		{ header = "coverage_watch_header", name = "Totems to Watch", keys = watches },
		{ header = "look_header", name = "Look", keys = {
			"coverage_icon_size", "coverage_opacity", "coverage_font", "coverage_hide_border",
		}, names = { coverage_font = "Text Size", coverage_hide_border = "Hide Background" } },
		{ header = "sizes_header", name = "Per-Totem Icon Size", keys = sizes },
		{ header = "behaviour_header", name = "Behaviour", keys = {
			"coverage_hide_covered", "coverage_free", "coverage_vertical",
		} },
		{ header = "position_header", name = "Position", keys = { "coverage_move" }, names = { coverage_move = "Move" } },
	})
	pages.coverage_section.args.coverage_free.desc = "Every watched totem gets its own spot and size."
		.. " Use Move below to drag the cells, or ALT+drag a cell. Off: one cell per element, together in a row or column."
end

-- Drop All has its own tab, separate from the order of the visible buttons.
do
	local SP = ShamanPower
	local buttons, pages = SP.options.args.buttons.args, SP.options.args.fluffy.args
	local bar = buttons.auto_button
	local keys = { "show_dropall", "dropall_totem_sets", "dropall_totem_sets_sync", "dropall_totem_sets_adopt",
		"drop_order_header", "drop_order_1", "drop_order_2", "drop_order_3", "drop_order_4",
		"exclude_from_drop_all_header", "exclude_earth", "exclude_fire", "exclude_water", "exclude_air" }
	for key in pairs(bar.args) do
		if key:match("^exclude_.*_empty_note$") then keys[#keys + 1] = key end
	end
	buttons.dropall_section = { order = 3.1, type = "group", name = "Drop All", args = {}, disabled = bar.disabled }
	SP.MoveSettingsOptions({ "buttons", "auto_button" }, { "buttons", "dropall_section" }, keys)
	bar.name = "Totem Bar"
	bar.args.auto_desc.name = "Configure the totem bar and its flyout menus."
	bar.args.auto_enable.name = "Enable Totem Bar"
	bar.args.show_cooldown_bar = nil -- the identical toggle stays on Cooldown Bar > Items
	SP.SettingsPathAliases["buttons/auto_button/show_cooldown_bar"] = {
		"fluffy", "cdbar_items_section", "show_cooldown_bar",
	}
	SP.OrderSettingsBands(bar, {
		{ keys = { "auto_desc" } },
		{ keys = { "auto_enable" } },
		{ header = "flyouts_header", name = "Flyouts", keys = {
			"show_totem_flyouts", "show_es_flyout", "es_flyout_filter",
		} },
		{ header = "position_header", name = "Position", keys = { "unlock_totem_bar" },
			names = { unlock_totem_bar = "Move (unlock bar)" } },
	})
	SP.OrderSettingsBands(buttons.dropall_section, {
		{ keys = { "show_dropall" } },
		{ header = "sets_header", name = "Blizzard Totem Sets", keys = {
			"dropall_totem_sets", "dropall_totem_sets_sync", "dropall_totem_sets_adopt",
		} },
		{ header = "drop_order_header", name = "Drop All Order", keys = {
			"drop_order_1", "drop_order_2", "drop_order_3", "drop_order_4",
		} },
		{ header = "exclude_from_drop_all_header", name = "Exclude from Drop All", keys = {
			"exclude_earth", "exclude_earth_empty_note", "exclude_fire", "exclude_fire_empty_note",
			"exclude_water", "exclude_water_empty_note", "exclude_air", "exclude_air_empty_note",
		} },
	})
	pages.totembar_order_section.name = "Button Order"
	for i, ordinal in ipairs({ "1st", "2nd", "3rd", "4th" }) do
		buttons.dropall_section.args["drop_order_" .. i].name = ordinal .. " in Drop All Order"
		pages.totembar_order_section.args["totem_bar_order_" .. i].name = ordinal .. " Button"
	end
end

-- Module pages keep their controls and callbacks; only their reading order changes.
do
	local SP = ShamanPower
	local tracked = {
		"tracked_soe", "tracked_stoneskin", "tracked_tow", "tracked_flametongue", "tracked_frostresist",
		"tracked_manaspring", "tracked_healingstream", "tracked_fireresist", "tracked_manatide",
		"tracked_windfury", "tracked_graceofair", "tracked_wrathofair", "tracked_tranquilair",
		"tracked_natureresist", "tracked_windwall",
	}
	SP.OrderSettingsBands(SP.options.args.fluffy.args.sprange_section, {
		{ keys = { "sprange_desc", "module_missing_note", "not_shown_note" } },
		{ keys = { "show_overlay", "open_window" } },
		{ header = "tracked_header", name = "Totems to Track", keys = tracked },
		{ header = "look_header", name = "Look", keys = {
			"sprange_icon_size", "sprange_opacity", "sprange_vertical", "sprange_hide_names", "sprange_hide_border",
		} },
		{ header = "minimap_header", name = "Minimap Markers", keys = {
			"minimapTotemMarkers", "minimapTotemRings", "minimapTotemPinSize",
		} },
	})
	SP.OrderSettingsBands(SP.options.args.fluffy.args.estrack_section, {
		{ keys = { "estrack_desc", "module_missing_note" } },
		{ keys = { "estrack_enabled", "open_window" } },
		{ header = "estrack_options_header", name = "Look", keys = {
			"estrack_icon_size", "estrack_opacity", "estrack_vertical", "estrack_hide_names",
			"estrack_hide_border", "estrack_hide_charges",
		} },
	})
	SP.OrderSettingsBands(SP.options.args.fluffy.args.raid_cd_section, {
		{ keys = { "raid_cd_desc", "module_missing_note", "no_group_note" } },
		{ keys = { "open_window" } },
		{ header = "assignment_header", name = "Cooldown Assignments", keys = {
			"bloodlust_primary", "bloodlust_backup1", "bloodlust_backup2", "bloodlust_caller",
			"manatide_shaman", "manatide_caller", "drums_caller", "drums_group", "drums_drummer",
		} },
		{ header = "warnings_header", name = "Warnings", keys = {
			"raidCDShowWarningIcon", "raidCDShowWarningText",
		} },
		{ header = "look_header", name = "Look", keys = {
			"raidCDButtonScale", "raidCDButtonOpacity", "raidCDButtonShowFrame", "raidCDShowButtonAnimation",
		}, names = { raidCDButtonScale = "Scale", raidCDButtonOpacity = "Opacity" } },
		{ header = "sound_header", name = "Sound", keys = {
			"raidCDPlaySound", "raidCDSoundVolume_testsound", "raidCDSoundVolume", "raidCDSoundVolumeNote",
		}, names = { raidCDSoundVolume = "Volume" } },
	})
	SP.OrderSettingsBands(SP.options.args.fluffy.args.shieldcharges_section, {
		{ keys = { "shieldcharges_desc", "module_missing_note", "hide_ooc_note", "both_off_note" } },
		{ keys = { "shieldcharges_player", "shieldcharges_earth" } },
		{ header = "look_header", name = "Look", keys = { "shieldcharges_scale", "shieldcharges_opacity" } },
		{ header = "behaviour_header", name = "Behaviour", keys = {
			"shieldcharges_hide_ooc", "shieldcharges_hide_none",
		} },
		{ header = "position_header", name = "Position", keys = { "shieldcharges_locked" } },
	})
	SP.OrderSettingsBands(SP.options.args.fluffy.args.reactivetotems_section, {
		{ keys = { "reactive_desc", "module_missing_note", "engine_note", "instance_only_note", "master_off_note" } },
		{ keys = { "reactive_enabled" } },
		{ header = "reactive_header_tracking", name = "Debuff Tracking", keys = {
			"reactive_track_fear", "reactive_track_poison", "reactive_track_disease",
		} },
		{ header = "reactive_header_appearance", name = "Look", keys = {
			"reactive_icon_size", "reactive_opacity", "reactive_font_size", "reactive_font_outline",
			"reactive_hide_border", "reactive_hide_background", "reactive_hide_debuff_text",
			"reactive_show_debuff_icon", "reactive_hide_totem_text",
		}, names = {
			reactive_font_size = "Text Size", reactive_font_outline = "Outline (unless Fonts & Textures sets one)",
		} },
		{ header = "reactive_header_effects", name = "Behaviour", keys = {
			"reactive_only_instance", "reactive_hide_when_active", "click_to_cast", "reactive_glow", "reactive_glow_intensity",
		} },
		{ header = "sound_header", name = "Sound", keys = {
			"reactive_sound", "reactive_sound_picker", "reactive_sound_picker_testsound",
			"reactive_sound_volume", "reactive_sound_volume_note",
		}, names = { reactive_sound = "Play Sound", reactive_sound_picker = "Sound", reactive_sound_volume = "Volume" } },
		{ header = "position_header", name = "Position", keys = {
			"reactive_show", "reactive_locked", "reactive_reset", "reactive_hide",
		}, names = { reactive_show = "Move", reactive_locked = "Lock Position", reactive_reset = "Reset Position" } },
		{ header = "reactive_header_buttons", name = "Test / Reset", keys = { "reactive_test" } },
	})
	SP.OrderSettingsBands(SP.options.args.fluffy.args.expiringalerts_section, {
		{ keys = { "alerts_desc", "module_missing_note", "master_off_note" } },
		{ keys = { "alerts_enabled", "alerts_display_mode" } },
		{ header = "alerts_header_shields", name = "Shield Alerts", keys = {
			"alerts_shields_enabled", "alerts_shields_lightning", "alerts_shields_water", "alerts_shields_earth",
		} },
		{ header = "alerts_header_totems", name = "Totem Alerts", keys = {
			"alerts_totems_enabled", "alerts_totems_destroyed", "alerts_totems_expired",
			"alerts_totems_earth", "alerts_totems_fire", "alerts_totems_water", "alerts_totems_air",
		} },
		{ header = "destroyed_header", name = "When a Totem Is Destroyed", keys = {
			"alerts_totems_destroyedChat", "alerts_totems_destroyedCenter", "alerts_totems_destroyedParty",
		}, names = {
			alerts_totems_destroyedChat = "Line in My Chat Window", alerts_totems_destroyedCenter = "Big Text on My Screen",
			alerts_totems_destroyedParty = "Tell My Group in Chat",
		} },
		{ header = "alerts_header_imbues", name = "Weapon Imbue Alerts", keys = {
			"alerts_imbues_enabled", "alerts_imbues_mainhand", "alerts_imbues_offhand",
		} },
		{ header = "alerts_header_display", name = "Look", keys = {
			"alerts_icon_size", "alerts_opacity", "alerts_text_size", "alerts_font_outline",
		}, names = { alerts_font_outline = "Outline (unless Fonts & Textures sets one)" } },
		{ header = "behaviour_header", name = "Behaviour", keys = { "alerts_animation", "alerts_duration" } },
		{ header = "shield_sound_header", name = "Sound: Shields", keys = {
			"alerts_shields_sound", "alerts_shields_sound_picker", "alerts_shields_sound_picker_testsound",
		}, names = { alerts_shields_sound_picker = "Sound" } },
		{ header = "totem_sound_header", name = "Sound: Totems", keys = {
			"alerts_totems_sound", "alerts_totems_sound_picker", "alerts_totems_sound_picker_testsound",
		}, names = { alerts_totems_sound_picker = "Sound" } },
		{ header = "imbue_sound_header", name = "Sound: Weapon Imbues", keys = {
			"alerts_imbues_sound", "alerts_imbues_sound_picker", "alerts_imbues_sound_picker_testsound",
		}, names = { alerts_imbues_sound_picker = "Sound" } },
		{ header = "volume_header", name = "Sound: Shared Volume", keys = {
			"alerts_sound_volume", "alerts_sound_volume_note",
		}, names = { alerts_sound_volume = "Volume" } },
		{ header = "position_header", name = "Position", keys = {
			"alerts_show_pos", "alerts_hide_pos", "alerts_reset_pos",
		}, names = { alerts_show_pos = "Move" } },
		{ header = "alerts_header_testing", name = "Test / Reset", keys = { "alerts_test" } },
	})
	SP.OrderSettingsBands(SP.options.args.fluffy.args.tremorreminder_section, {
		{ keys = { "tremor_desc", "module_missing_note", "master_off_note" } },
		{ keys = { "tremor_enabled", "tremor_display_mode", "tremor_manage_mobs" } },
		{ header = "mob_list_header", name = "Mob List", keys = {
			"tremor_use_defaults", "fear_add_name", "fear_add_target", "fear_remove_select", "fear_remove",
			"fear_restore_defaults", "tremor_reset_moblist",
		} },
		{ header = "tremor_header_appearance", name = "Look", keys = {
			"tremor_icon_size", "tremor_opacity", "tremor_text_size", "tremor_glow_color",
		}, names = { tremor_text_size = "Text Size" } },
		{ header = "tremor_header_glow", name = "Behaviour", keys = {
			"tremor_hide_when_active", "tremor_show_glow",
		} },
		{ header = "tremor_header_sound", name = "Sound", keys = {
			"tremor_play_sound", "tremor_sound_picker", "tremor_sound_picker_testsound",
			"tremor_sound_volume", "tremor_sound_volume_note",
		}, names = { tremor_sound_picker = "Sound", tremor_sound_volume = "Volume" } },
		{ header = "position_header", name = "Position", keys = {
			"tremor_show_pos", "tremor_lock_pos", "tremor_reset_pos",
		}, names = { tremor_show_pos = "Move" } },
		{ header = "tremor_header_commands", name = "Test / Reset", keys = {
			"tremor_test", "tremor_hide_test", "tremor_commands_desc",
		} },
	})
end
