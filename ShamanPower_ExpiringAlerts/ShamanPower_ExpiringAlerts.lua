-- ============================================================================
-- ShamanPower [Expiring Alerts] Module
-- Scrolling combat text style alerts for expiring shields, totems, and imbues
-- ============================================================================

local SP = ShamanPower
if not SP then
	print("|cffff0000ShamanPower [Expiring Alerts]:|r Core addon not found!")
	return
end

-- Only load for Shamans
local _, playerClass = UnitClass("player")
if playerClass ~= "SHAMAN" then
	return
end

-- Mark module as loaded
SP.ExpiringAlertsLoaded = true

-- SavedVariables
ShamanPowerExpiringAlertsDB = ShamanPowerExpiringAlertsDB or {}

-- ============================================================================
-- Helper Functions
-- ============================================================================

-- Strip rank from spell/totem names (e.g., "Strength of Earth Totem VII" -> "Strength of Earth Totem")
local function StripRank(name)
	if not name then return name end
	-- Remove Roman numerals at the end (I, II, III, IV, V, VI, VII, VIII, IX, X, XI, XII, etc.)
	name = name:gsub("%s+[IVX]+$", "")
	-- Remove "(Rank X)" format
	name = name:gsub("%s*%([Rr]ank%s*%d+%)%s*$", "")
	return name
end

-- ============================================================================
-- Spell IDs and Names (for Classic compatibility)
-- ============================================================================

local ShieldSpells = {
	lightningShield = {
		id = 324,
		name = GetSpellInfo(324) or "Lightning Shield",
		icon = "Interface\\Icons\\Spell_Nature_LightningShield",
	},
	waterShield = {
		id = 24398,
		name = GetSpellInfo(24398) or "Water Shield",
		icon = "Interface\\Icons\\Ability_Shaman_WaterShield",
	},
	earthShield = {
		id = 974,
		name = GetSpellInfo(974) or "Earth Shield",
		icon = "Interface\\Icons\\Spell_Nature_SkinOfEarth",
	},
}

local WeaponImbues = {
	windfury = {
		id = 8232,
		name = GetSpellInfo(8232) or "Windfury Weapon",
		icon = "Interface\\Icons\\Spell_Nature_Cyclone",
	},
	flametongue = {
		id = 8024,
		name = GetSpellInfo(8024) or "Flametongue Weapon",
		icon = "Interface\\Icons\\Spell_Fire_FlameTounge",
	},
	frostbrand = {
		id = 8033,
		name = GetSpellInfo(8033) or "Frostbrand Weapon",
		icon = "Interface\\Icons\\Spell_Frost_IceShock",
	},
	rockbiter = {
		id = 8017,
		name = GetSpellInfo(8017) or "Rockbiter Weapon",
		icon = "Interface\\Icons\\Spell_Nature_RockBiter",
	},
	earthliving = {
		id = 51730,
		name = GetSpellInfo(51730) or "Earthliving Weapon",
		icon = "Interface\\Icons\\Spell_Shaman_EarthlivingWeapon",
	},
}

local TotemElements = {
	[1] = { name = "Earth", color = {r = 0.6, g = 0.4, b = 0.2} },
	[2] = { name = "Fire", color = {r = 1.0, g = 0.3, b = 0.0} },
	[3] = { name = "Water", color = {r = 0.0, g = 0.6, b = 1.0} },
	[4] = { name = "Air", color = {r = 0.6, g = 0.8, b = 1.0} },
}

-- Element colors for alerts
local ElementColors = {
	lightning = { r = 0.5, g = 0.5, b = 1.0 },
	water = { r = 0.0, g = 0.6, b = 1.0 },
	earth = { r = 0.6, g = 0.4, b = 0.2 },
	fire = { r = 1.0, g = 0.5, b = 0.0 },
	air = { r = 0.6, g = 0.8, b = 1.0 },
}

-- ============================================================================
-- Default Settings
-- ============================================================================

local defaultSettings = {
	enabled = true,
	locked = false,
	displayMode = "both",  -- "text", "icon", "both"
	animationStyle = "scrollUp",  -- "scrollUp", "scrollDown", "staticFade", "bounce"
	position = { point = "CENTER", x = 0, y = 150 },
	textSize = 24,
	iconSize = 32,
	duration = 2.5,
	opacity = 100,
	fontOutline = true,
	soundVolume = 100,

	shields = {
		enabled = true,
		lightning = true,
		water = true,
		earthShield = true,
		sound = false,
		soundFile = "Sound\\Interface\\RaidWarning.ogg",
		color = { r = 0.5, g = 0.5, b = 1.0 },
	},
	totems = {
		enabled = true,
		destroyed = true,
		expired = false,  -- off by default (can be spammy)
		earth = true,
		fire = true,
		water = true,
		air = true,
		sound = false,
		soundFile = "Sound\\Interface\\AlarmClockWarning3.ogg",
	},
	weaponImbues = {
		enabled = true,
		mainHand = true,
		offHand = true,
		sound = false,
		soundFile = "Sound\\Interface\\RaidWarning.ogg",
		color = { r = 1.0, g = 0.5, b = 0.0 },
	},
}

-- ============================================================================
-- State Tracking
-- ============================================================================

local previousState = {
	shields = {
		lightning = false,
		water = false,
	},
	totems = {
		[1] = { active = false, name = nil, startTime = 0, duration = 0 },
		[2] = { active = false, name = nil, startTime = 0, duration = 0 },
		[3] = { active = false, name = nil, startTime = 0, duration = 0 },
		[4] = { active = false, name = nil, startTime = 0, duration = 0 },
	},
	weaponEnchants = {
		mainHand = false,
		offHand = false,
	},
	earthShieldTarget = nil,
	earthShieldActive = false,
}

-- ============================================================================
-- Initialization
-- ============================================================================

function SP:InitExpiringAlerts()
	local sv = ShamanPowerExpiringAlertsDB

	-- Apply defaults for missing settings
	for key, value in pairs(defaultSettings) do
		if sv[key] == nil then
			if type(value) == "table" then
				sv[key] = {}
				for k, v in pairs(value) do
					if type(v) == "table" then
						sv[key][k] = {}
						for k2, v2 in pairs(v) do
							sv[key][k][k2] = v2
						end
					else
						sv[key][k] = v
					end
				end
			else
				sv[key] = value
			end
		end
	end

	-- Ensure sub-tables exist
	if not sv.shields then sv.shields = {} end
	if not sv.totems then sv.totems = {} end
	if not sv.weaponImbues then sv.weaponImbues = {} end
	if not sv.position then sv.position = { point = "CENTER", x = 0, y = 150 } end

	-- Apply sub-defaults
	for k, v in pairs(defaultSettings.shields) do
		if sv.shields[k] == nil then sv.shields[k] = v end
	end
	for k, v in pairs(defaultSettings.totems) do
		if sv.totems[k] == nil then sv.totems[k] = v end
	end
	for k, v in pairs(defaultSettings.weaponImbues) do
		if sv.weaponImbues[k] == nil then sv.weaponImbues[k] = v end
	end

	-- Create the alert frame
	self:CreateExpiringAlertsFrame()

	-- Setup events
	self:SetupExpiringAlertsEvents()

	-- Initialize state
	self:UpdateExpiringAlertsState()
end

-- ============================================================================
-- Alert Frame and Pool System
-- ============================================================================

SP.expiringAlertsFrame = nil
SP.alertPool = {}
SP.activeAlerts = {}
SP.alertQueue = {}

function SP:CreateExpiringAlertsFrame()
	if self.expiringAlertsFrame then return end

	local sv = ShamanPowerExpiringAlertsDB
	local pos = sv.position or defaultSettings.position

	-- Main container frame
	local frame = CreateFrame("Frame", "ShamanPowerExpiringAlertsFrame", UIParent)
	frame:SetSize(300, 100)
	frame:SetPoint(pos.point or "CENTER", UIParent, pos.point or "CENTER", pos.x or 0, pos.y or 150)
	frame:SetMovable(true)
	frame:EnableMouse(false)  -- Normally not interactive
	frame:SetClampedToScreen(true)
	frame:SetFrameStrata("HIGH")

	self.expiringAlertsFrame = frame

	-- Positioning frame (shown when unlocked)
	local posFrame = CreateFrame("Frame", "ShamanPowerExpiringAlertsPosFrame", UIParent, "BackdropTemplate")
	posFrame:SetSize(200, 60)
	posFrame:SetPoint("CENTER", frame, "CENTER", 0, 0)
	posFrame:SetMovable(true)
	posFrame:EnableMouse(true)
	posFrame:SetClampedToScreen(true)
	posFrame:SetFrameStrata("DIALOG")
	posFrame:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 }
	})
	posFrame:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
	posFrame:SetBackdropBorderColor(0.4, 0.6, 1.0, 1)

	local posText = posFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	posText:SetPoint("CENTER", posFrame, "CENTER", 0, 8)
	posText:SetText("Expiring Alerts")
	posText:SetTextColor(1, 0.82, 0)

	local posHint = posFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	posHint:SetPoint("CENTER", posFrame, "CENTER", 0, -10)
	posHint:SetText("Drag to position")
	posHint:SetTextColor(0.7, 0.7, 0.7)

	posFrame:RegisterForDrag("LeftButton")
	posFrame:SetScript("OnDragStart", function(self)
		self:StartMoving()
	end)
	posFrame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, _, x, y = self:GetPoint()
		ShamanPowerExpiringAlertsDB.position = { point = point, x = x, y = y }
		-- Update main frame position
		SP.expiringAlertsFrame:ClearAllPoints()
		SP.expiringAlertsFrame:SetPoint(point, UIParent, point, x, y)
	end)

	posFrame:Hide()
	self.expiringAlertsPosFrame = posFrame
end

function SP:GetAlertFrame()
	-- Return a frame from the pool or create a new one
	local frame = tremove(self.alertPool)
	if not frame then
		frame = self:CreateAlertSubFrame()
	end
	return frame
end

function SP:ReleaseAlertFrame(frame)
	frame:Hide()
	frame:ClearAllPoints()
	if frame.animGroup then
		frame.animGroup:Stop()
	end
	tinsert(self.alertPool, frame)
end

function SP:CreateAlertSubFrame()
	local sv = ShamanPowerExpiringAlertsDB

	local frame = CreateFrame("Frame", nil, self.expiringAlertsFrame)
	frame:SetSize(400, 50)
	frame:SetPoint("CENTER", self.expiringAlertsFrame, "CENTER", 0, 0)

	-- Icon (position set dynamically in ProcessAlertQueue for centering)
	local icon = frame:CreateTexture(nil, "ARTWORK")
	icon:SetSize(sv.iconSize or 32, sv.iconSize or 32)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	frame.icon = icon

	-- Text (position set dynamically in ProcessAlertQueue for centering)
	local text = frame:CreateFontString(nil, "OVERLAY")
	local outline = sv.fontOutline and "OUTLINE" or ""
	text:SetFont("Fonts\\FRIZQT__.TTF", sv.textSize or 24, outline)
	text:SetShadowColor(0, 0, 0, 1)
	text:SetShadowOffset(2, -2)
	frame.text = text

	-- Animation group for scroll/fade
	local ag = frame:CreateAnimationGroup()
	frame.animGroup = ag

	-- These will be configured per-animation style
	frame.moveAnim = ag:CreateAnimation("Translation")
	frame.fadeAnim = ag:CreateAnimation("Alpha")
	frame.scaleAnim = ag:CreateAnimation("Scale")

	ag:SetScript("OnFinished", function()
		SP:ReleaseAlertFrame(frame)
		-- Remove from active alerts
		for i, f in ipairs(SP.activeAlerts) do
			if f == frame then
				tremove(SP.activeAlerts, i)
				break
			end
		end
		-- Process queue
		SP:ProcessAlertQueue()
	end)

	frame:Hide()
	return frame
end

function SP:ConfigureAlertAnimation(frame, style, duration)
	local ag = frame.animGroup
	local move = frame.moveAnim
	local fade = frame.fadeAnim
	local scale = frame.scaleAnim

	-- Reset animations
	ag:Stop()
	move:SetOffset(0, 0)
	move:SetDuration(0)
	fade:SetFromAlpha(1)
	fade:SetToAlpha(1)
	fade:SetDuration(0)
	scale:SetScale(1, 1)
	scale:SetDuration(0)

	if style == "scrollUp" then
		move:SetOffset(0, 100)
		move:SetDuration(duration)
		move:SetSmoothing("OUT")
		fade:SetFromAlpha(1)
		fade:SetToAlpha(0)
		fade:SetDuration(duration)
		fade:SetStartDelay(duration * 0.4)
	elseif style == "scrollDown" then
		move:SetOffset(0, -100)
		move:SetDuration(duration)
		move:SetSmoothing("OUT")
		fade:SetFromAlpha(1)
		fade:SetToAlpha(0)
		fade:SetDuration(duration)
		fade:SetStartDelay(duration * 0.4)
	elseif style == "staticFade" then
		-- Pulse then fade
		fade:SetFromAlpha(1)
		fade:SetToAlpha(0)
		fade:SetDuration(duration)
		fade:SetStartDelay(duration * 0.3)
		-- Add a scale pulse effect
		scale:SetScale(1.1, 1.1)
		scale:SetDuration(0.2)
		scale:SetSmoothing("OUT")
	elseif style == "bounce" then
		-- Move up slightly, then down
		move:SetOffset(0, 20)
		move:SetDuration(0.3)
		move:SetSmoothing("OUT")
		fade:SetFromAlpha(1)
		fade:SetToAlpha(0)
		fade:SetDuration(duration)
		fade:SetStartDelay(duration * 0.5)
	end
end

-- ============================================================================
-- Alert Display Functions
-- ============================================================================

function SP:ShowExpiringAlert(alertType, spellName, spellIcon, color)
	local sv = ShamanPowerExpiringAlertsDB
	if not sv.enabled then return end

	-- Queue the alert
	tinsert(self.alertQueue, {
		alertType = alertType,
		spellName = spellName,
		spellIcon = spellIcon,
		color = color,
	})

	self:ProcessAlertQueue()
end

function SP:ProcessAlertQueue()
	local sv = ShamanPowerExpiringAlertsDB

	-- Limit active alerts to prevent overlap
	if #self.activeAlerts >= 3 then return end
	if #self.alertQueue == 0 then return end

	local alertData = tremove(self.alertQueue, 1)
	local frame = self:GetAlertFrame()

	local showIcon = sv.displayMode == "icon" or sv.displayMode == "both"
	local showText = sv.displayMode == "text" or sv.displayMode == "both"

	-- Clear previous anchor points
	frame.icon:ClearAllPoints()
	frame.text:ClearAllPoints()

	-- Configure icon
	local iconSize = sv.iconSize or 32
	if showIcon and alertData.spellIcon then
		frame.icon:SetTexture(alertData.spellIcon)
		frame.icon:SetSize(iconSize, iconSize)
		frame.icon:Show()
	else
		frame.icon:Hide()
	end

	-- Configure text
	local textWidth = 0
	if showText then
		local displayText = alertData.spellName .. " FADED!"
		frame.text:SetText(displayText)
		local outline = sv.fontOutline and "OUTLINE" or ""
		frame.text:SetFont("Fonts\\FRIZQT__.TTF", sv.textSize or 24, outline)
		if alertData.color then
			frame.text:SetTextColor(alertData.color.r, alertData.color.g, alertData.color.b)
		else
			frame.text:SetTextColor(1, 1, 1)
		end
		frame.text:Show()
		textWidth = frame.text:GetStringWidth()
	else
		frame.text:Hide()
	end

	-- Calculate total content width and center it
	local spacing = 8
	local totalWidth = 0
	if showIcon and showText then
		totalWidth = iconSize + spacing + textWidth
	elseif showIcon then
		totalWidth = iconSize
	elseif showText then
		totalWidth = textWidth
	end

	-- Position content centered in frame
	local startX = -totalWidth / 2
	if showIcon and showText then
		-- Icon + Text: position icon at left of centered content, text to its right
		frame.icon:SetPoint("LEFT", frame, "CENTER", startX, 0)
		frame.text:SetPoint("LEFT", frame.icon, "RIGHT", spacing, 0)
	elseif showIcon then
		-- Icon only: center it
		frame.icon:SetPoint("CENTER", frame, "CENTER", 0, 0)
	elseif showText then
		-- Text only: center it
		frame.text:SetPoint("CENTER", frame, "CENTER", 0, 0)
	end

	-- Position based on active alerts (stagger vertically)
	local yOffset = #self.activeAlerts * -40
	frame:ClearAllPoints()
	frame:SetPoint("CENTER", self.expiringAlertsFrame, "CENTER", 0, yOffset)

	-- Configure and play animation
	self:ConfigureAlertAnimation(frame, sv.animationStyle or "scrollUp", sv.duration or 2.5)
	local alpha = (sv.opacity or 100) / 100
	frame:SetAlpha(alpha)
	frame.icon:SetAlpha(alpha)
	frame.text:SetAlpha(alpha)
	frame:Show()
	frame.animGroup:Play()

	tinsert(self.activeAlerts, frame)

	-- Play sound
	self:PlayAlertSound(alertData.alertType)
end

function SP:PlayAlertSound(alertType)
	local sv = ShamanPowerExpiringAlertsDB

	local soundFile = nil
	local playSound = false

	if alertType == "shield" and sv.shields and sv.shields.sound then
		soundFile = sv.shields.soundFile
		playSound = true
	elseif alertType == "totem" and sv.totems and sv.totems.sound then
		soundFile = sv.totems.soundFile
		playSound = true
	elseif alertType == "imbue" and sv.weaponImbues and sv.weaponImbues.sound then
		soundFile = sv.weaponImbues.soundFile
		playSound = true
	end

	if playSound and soundFile then
		ShamanPower:PlaySoundWithVolume(soundFile, sv.soundVolume, true)
	end
end

-- ============================================================================
-- State Detection and Updates
-- ============================================================================

function SP:UpdateExpiringAlertsState()
	-- Initialize current state without triggering alerts
	self:CheckShieldState(true)
	self:CheckTotemState(true)
	self:CheckWeaponEnchantState(true)
end

function SP:CheckShieldState(initializing)
	local sv = ShamanPowerExpiringAlertsDB
	if not sv.enabled or not sv.shields or not sv.shields.enabled then return end

	-- Check Lightning Shield
	local hasLightningShield = false
	local hasWaterShield = false

	for i = 1, 40 do
		local name, icon, _, _, _, _, _, _, _, spellId = UnitBuff("player", i)
		if not name then break end

		-- Check by spell ID or name
		if spellId == 324 or name == ShieldSpells.lightningShield.name or name == "Lightning Shield" then
			hasLightningShield = true
		elseif spellId == 24398 or name == ShieldSpells.waterShield.name or name == "Water Shield" then
			hasWaterShield = true
		end
	end

	-- Detect fade
	if not initializing then
		if previousState.shields.lightning and not hasLightningShield and sv.shields.lightning then
			self:ShowExpiringAlert("shield", "Lightning Shield", ShieldSpells.lightningShield.icon, ElementColors.lightning)
		end
		if previousState.shields.water and not hasWaterShield and sv.shields.water then
			self:ShowExpiringAlert("shield", "Water Shield", ShieldSpells.waterShield.icon, ElementColors.water)
		end
	end

	previousState.shields.lightning = hasLightningShield
	previousState.shields.water = hasWaterShield
end

function SP:CheckTotemState(initializing)
	local sv = ShamanPowerExpiringAlertsDB
	if not sv.enabled or not sv.totems or not sv.totems.enabled then return end

	for slot = 1, 4 do
		local haveTotem, totemName, startTime, duration = GetTotemInfo(slot)

		local prev = previousState.totems[slot]
		local wasActive = prev.active
		local prevName = prev.name
		local prevStart = prev.startTime
		local prevDuration = prev.duration

		if not initializing and wasActive and not haveTotem then
			-- Totem is gone - determine if destroyed or expired
			local elementName = TotemElements[slot] and TotemElements[slot].name or "Totem"
			local elementColor = TotemElements[slot] and TotemElements[slot].color or {r=1, g=1, b=1}

			-- Check element-specific toggle
			local elementKey = elementName:lower()
			if sv.totems[elementKey] ~= false then
				local elapsed = GetTime() - prevStart
				local isExpired = prevDuration > 0 and elapsed >= (prevDuration - 0.5)

				if isExpired then
					-- Totem expired naturally
					if sv.totems.expired then
						local icon = GetTotemInfo(slot) and select(2, GetTotemInfo(slot)) or "Interface\\Icons\\Spell_Shaman_TotemRecall"
						self:ShowExpiringAlert("totem", StripRank(prevName) .. " Expired", icon, elementColor)
					end
				else
					-- Totem was destroyed
					if sv.totems.destroyed then
						local icon = "Interface\\Icons\\Spell_Shaman_TotemRecall"
						self:ShowExpiringAlert("totem", StripRank(prevName) .. " Destroyed!", icon, elementColor)
					end
				end
			end
		end

		-- Update state
		prev.active = haveTotem
		prev.name = totemName
		prev.startTime = startTime
		prev.duration = duration
	end
end

function SP:CheckWeaponEnchantState(initializing)
	local sv = ShamanPowerExpiringAlertsDB
	if not sv.enabled or not sv.weaponImbues or not sv.weaponImbues.enabled then return end

	-- Check if weapons are equipped (nil if no weapon in slot)
	-- Slot 16 = MainHandSlot, Slot 17 = SecondaryHandSlot (off-hand)
	local hasMainHandWeapon = GetInventoryItemLink("player", 16) ~= nil
	local hasOffHandWeapon = GetInventoryItemLink("player", 17) ~= nil

	-- GetWeaponEnchantInfo returns: hasMain, mainExp, mainCharges, mainID, hasOff, offExp, offCharges, offID
	local hasMainHandEnchant, _, _, _, hasOffHandEnchant = GetWeaponEnchantInfo()

	-- Convert to explicit booleans (API may return 1/nil instead of true/false)
	local mainHandEnchanted = hasMainHandWeapon and hasMainHandEnchant and true or false
	local offHandEnchanted = hasOffHandWeapon and hasOffHandEnchant and true or false

	-- Get previous states (default to false if nil)
	local prevMainHand = previousState.weaponEnchants.mainHand and true or false
	local prevOffHand = previousState.weaponEnchants.offHand and true or false

	if not initializing then
		-- Main hand: was enchanted, now not enchanted, and still has weapon
		if prevMainHand and not mainHandEnchanted and hasMainHandWeapon and sv.weaponImbues.mainHand then
			self:ShowExpiringAlert("imbue", "Weapon Imbue (MH)", WeaponImbues.windfury.icon, sv.weaponImbues.color)
		end

		-- Off hand: was enchanted, now not enchanted, and still has weapon
		if prevOffHand and not offHandEnchanted and hasOffHandWeapon and sv.weaponImbues.offHand then
			self:ShowExpiringAlert("imbue", "Weapon Imbue (OH)", WeaponImbues.flametongue.icon, sv.weaponImbues.color)
		end
	end

	-- Store as explicit booleans
	previousState.weaponEnchants.mainHand = mainHandEnchanted
	previousState.weaponEnchants.offHand = offHandEnchanted
end

function SP:CheckEarthShieldState(unit, initializing)
	local sv = ShamanPowerExpiringAlertsDB
	if not sv.enabled or not sv.shields or not sv.shields.enabled or not sv.shields.earthShield then return end

	-- Only check if we have a tracked Earth Shield target
	local esTarget = ShamanPower_EarthShieldAssignments and ShamanPower_EarthShieldAssignments[SP.player]
	if not esTarget then return end

	-- Check if ES is still on the target
	local hasES = false
	local targetUnit = nil

	-- Find the unit for the target name
	local units = {"target", "focus", "party1", "party2", "party3", "party4", "player"}
	for _, u in ipairs(units) do
		if UnitExists(u) and UnitName(u) == esTarget then
			targetUnit = u
			break
		end
	end

	if targetUnit then
		for i = 1, 40 do
			local name, _, _, _, _, _, _, _, _, spellId = UnitBuff(targetUnit, i)
			if not name then break end
			if spellId == 974 or name == ShieldSpells.earthShield.name or name == "Earth Shield" then
				hasES = true
				break
			end
		end
	end

	if not initializing then
		if previousState.earthShieldActive and not hasES then
			self:ShowExpiringAlert("shield", "Earth Shield (" .. esTarget .. ")", ShieldSpells.earthShield.icon, ElementColors.earth)
		end
	end

	previousState.earthShieldActive = hasES
	previousState.earthShieldTarget = esTarget
end

-- ============================================================================
-- Event Handling
-- ============================================================================

function SP:SetupExpiringAlertsEvents()
	if self.expiringAlertsEventsSetup then return end
	self.expiringAlertsEventsSetup = true

	local eventFrame = CreateFrame("Frame", "ShamanPowerExpiringAlertsEventFrame", UIParent)
	eventFrame:RegisterEvent("UNIT_AURA")
	eventFrame:RegisterEvent("PLAYER_TOTEM_UPDATE")
	eventFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")
	eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

	-- Throttle updates
	local lastAuraUpdate = 0
	local pendingAuraUpdate = false

	local function DoAuraUpdate()
		pendingAuraUpdate = false
		SP:CheckShieldState(false)
	end

	local function RequestAuraUpdate()
		local now = GetTime()
		if now - lastAuraUpdate >= 0.1 then
			lastAuraUpdate = now
			DoAuraUpdate()
		elseif not pendingAuraUpdate then
			pendingAuraUpdate = true
			C_Timer.After(0.1, DoAuraUpdate)
		end
	end

	eventFrame:SetScript("OnEvent", function(self, event, unit)
		if event == "UNIT_AURA" then
			if unit == "player" then
				RequestAuraUpdate()
			elseif previousState.earthShieldTarget and UnitExists(unit) and UnitName(unit) == previousState.earthShieldTarget then
				SP:CheckEarthShieldState(unit, false)
			end
		elseif event == "PLAYER_TOTEM_UPDATE" then
			SP:CheckTotemState(false)
		elseif event == "UNIT_INVENTORY_CHANGED" then
			if unit == "player" then
				SP:CheckWeaponEnchantState(false)
			end
		elseif event == "PLAYER_ENTERING_WORLD" then
			SP:UpdateExpiringAlertsState()
		end
	end)

	self.expiringAlertsEventFrame = eventFrame

	-- Weapon enchants don't have a reliable event when they expire
	-- Use a periodic check (every 0.5 seconds) to detect enchant changes
	local lastWeaponCheck = 0
	local weaponCheckFrame = CreateFrame("Frame")
	weaponCheckFrame:SetScript("OnUpdate", function(self, elapsed)
		lastWeaponCheck = lastWeaponCheck + elapsed
		if lastWeaponCheck >= 0.5 then
			lastWeaponCheck = 0
			SP:CheckWeaponEnchantState(false)
		end
	end)
	self.weaponCheckFrame = weaponCheckFrame
end

-- ============================================================================
-- Public API Functions
-- ============================================================================

function SP:ExpiringAlertsUpdate()
	self:UpdateExpiringAlertsState()
end

function SP:ExpiringAlertsTest()
	-- Show test alerts for each type
	self:ShowExpiringAlert("shield", "Lightning Shield", ShieldSpells.lightningShield.icon, ElementColors.lightning)
	C_Timer.After(0.5, function()
		SP:ShowExpiringAlert("totem", "Tremor Totem Destroyed!", "Interface\\Icons\\Spell_Nature_TremorTotem", TotemElements[1].color)
	end)
	C_Timer.After(1.0, function()
		SP:ShowExpiringAlert("imbue", "Windfury Weapon", WeaponImbues.windfury.icon, ElementColors.air)
	end)
end

function SP:ExpiringAlertsReset()
	local sv = ShamanPowerExpiringAlertsDB
	sv.position = { point = "CENTER", x = 0, y = 150 }

	if self.expiringAlertsFrame then
		self.expiringAlertsFrame:ClearAllPoints()
		self.expiringAlertsFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 150)
	end
	if self.expiringAlertsPosFrame then
		self.expiringAlertsPosFrame:ClearAllPoints()
		self.expiringAlertsPosFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 150)
	end

	SP:Print("Expiring Alerts position reset to default")
end

function SP:ExpiringAlertsShow()
	if self.expiringAlertsPosFrame then
		self.expiringAlertsPosFrame:Show()
	end
end

function SP:ExpiringAlertsHide()
	if self.expiringAlertsPosFrame then
		self.expiringAlertsPosFrame:Hide()
	end
end

function SP:UpdateExpiringAlertsAppearance()
	-- Update any active alert frames with new settings
	local sv = ShamanPowerExpiringAlertsDB

	for _, frame in ipairs(self.alertPool) do
		local outline = sv.fontOutline and "OUTLINE" or ""
		frame.text:SetFont("Fonts\\FRIZQT__.TTF", sv.textSize or 24, outline)
		frame.icon:SetSize(sv.iconSize or 32, sv.iconSize or 32)
	end
end

-- ============================================================================
-- Slash Commands
-- ============================================================================

SLASH_SPALERTS1 = "/spalerts"
SLASH_SPALERTS2 = "/expiringalerts"
SlashCmdList["SPALERTS"] = function(msg)
	msg = msg and msg:lower():trim() or ""

	if msg == "show" then
		SP:ExpiringAlertsShow()
		SP:Print("Expiring Alerts: Positioning frame shown. Drag to move, type /spalerts hide when done.")
	elseif msg == "hide" then
		SP:ExpiringAlertsHide()
		SP:Print("Expiring Alerts: Positioning frame hidden.")
	elseif msg == "test" then
		SP:ExpiringAlertsTest()
	elseif msg == "reset" then
		SP:ExpiringAlertsReset()
	elseif msg == "toggle" then
		ShamanPowerExpiringAlertsDB.enabled = not ShamanPowerExpiringAlertsDB.enabled
		SP:Print("Expiring Alerts " .. (ShamanPowerExpiringAlertsDB.enabled and "enabled" or "disabled"))
	else
		-- Open options
		if LibStub and LibStub("AceConfigDialog-3.0", true) then
			LibStub("AceConfigDialog-3.0"):Open("ShamanPower")
			LibStub("AceConfigDialog-3.0"):SelectGroup("ShamanPower", "fluffy", "expiringalerts_section")
		else
			SP:Print("Expiring Alerts Commands:")
			SP:Print("  /spalerts - Open options")
			SP:Print("  /spalerts show - Show positioning frame")
			SP:Print("  /spalerts hide - Hide positioning frame")
			SP:Print("  /spalerts test - Show test alerts")
			SP:Print("  /spalerts reset - Reset position to default")
			SP:Print("  /spalerts toggle - Enable/disable alerts")
		end
	end
end

-- ============================================================================
-- Module Load
-- ============================================================================

-- Initialize on load
C_Timer.After(0.5, function()
	SP:InitExpiringAlerts()
end)
