-- ============================================================================
-- ShamanPower [Expiring Alerts] Module
-- Scrolling combat text style alerts for expiring shields, totems, and imbues
-- ============================================================================

local SP = ShamanPower
-- Forever returns a LIST of enchants per weapon; the legacy global reports only
-- the first entry, which is empty when the imbue lands in the second.
local GetWeaponEnchantInfo = (SPCompat and SPCompat.GetWeaponEnchantInfo) or GetWeaponEnchantInfo
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
		-- 24398 on TBC, 408510 on WoW: Forever (Restoration talent), 52127 on retail
		id = (GetSpellInfo(24398) and 24398) or (GetSpellInfo(408510) and 408510) or (GetSpellInfo(52127) and 52127) or 24398,
		name = GetSpellInfo(24398) or GetSpellInfo(408510) or GetSpellInfo(52127) or "Water Shield",
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
		soundName = "Raid Warning",
		color = { r = 0.5, g = 0.5, b = 1.0 },
	},
	totems = {
		enabled = true,
		destroyed = true,
		-- a line in your own chat window (nobody else sees it): on for Forever, where it is how
		-- you notice a totem killed mid-fight; opt-in on Anniversary, where the alert always worked
		destroyedChat = (WOW_PROJECT_ID == WOW_PROJECT_MAINLINE),
		destroyedCenter = false,  -- big raid-warning-style text, drawn only on your screen
		destroyedParty = false,   -- tell the party / raid in chat (opt-in)
		expired = false,  -- off by default (can be spammy)
		earth = true,
		fire = true,
		water = true,
		air = true,
		sound = false,
		soundName = "Alarm Clock Warning 3",
	},
	weaponImbues = {
		enabled = true,
		mainHand = true,
		offHand = true,
		sound = false,
		soundName = "Raid Warning",
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
	SP:SetSPFont(text, "alerts", sv.textSize or 24, outline)
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
	if self.expiringAlertsDemoActive then return end

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
		-- shields and imbues name the buff that faded; totem alerts carry their
		-- own ending ("Destroyed!", "Expired")
		local displayText = alertData.alertType == "totem" and alertData.spellName or (alertData.spellName .. " FADED!")
		frame.text:SetText(displayText)
		local outline = sv.fontOutline and "OUTLINE" or ""
		SP:SetSPFont(frame.text, "alerts", sv.textSize or 24, outline)
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

local shieldSoundDebug = false      -- /spalerts sound turns this on for a session

function SP:PlayAlertSound(alertType)
	local sv = ShamanPowerExpiringAlertsDB

	local soundName = nil
	local playSound = false

	if alertType == "shield" and sv.shields and sv.shields.sound then
		soundName = sv.shields.soundName or "Raid Warning"
		playSound = true
	elseif alertType == "totem" and sv.totems and sv.totems.sound then
		soundName = sv.totems.soundName or "Alarm Clock Warning 3"
		playSound = true
	elseif alertType == "imbue" and sv.weaponImbues and sv.weaponImbues.sound then
		soundName = sv.weaponImbues.soundName or "Raid Warning"
		playSound = true
	end

	if playSound then
		-- With the engine playing the shield sound (below), it also fires for the
		-- out-of-combat fade this alert is announcing; one sound per drop, not two.
		if alertType == "shield" and SP.shieldSoundEngineActive then
			if shieldSoundDebug then SP:Print("shield alert: engine owns the sound, Lua sound skipped") end
			return
		end
		if alertType == "shield" and shieldSoundDebug then SP:Print("shield alert: Lua sound played") end
		ShamanPower:PlaySoundWithVolume(ShamanPower:GetSoundFile(soundName), sv.soundVolume, true)
	end
end

-- ============================================================================
-- Shield-dropped sound in combat (Mainline family)
-- ============================================================================
-- In combat the addon cannot see the shield fall off (measured: aura reads
-- return nothing, orb discharges fire no cast event), so the visual alert
-- only fires once reads come back. C_UnitAuras.AddAuraSound hands the ENGINE
-- a sound to play when a given aura leaves the player, and the engine does
-- that in combat (measured 2026-09-22: registered out of combat on Lightning
-- Shield, played the moment the last orb was consumed). Audio only: nothing
-- is learned, and no count can be read from it.
-- Registered out of combat only (a registration in combat inside instanced
-- PvE is a blocked action), one per shield rank the client knows, and torn
-- down when the option goes off. Uses the player's chosen shield alert sound.
local shieldSoundIDs = {}
local shieldSoundKey = nil          -- what the current registrations were made with
local shieldSoundPending = false
local shieldSoundLog = {}          -- one entry per rank tried, read by /spalerts sound

local function shieldSoundWanted()
	local sv = ShamanPowerExpiringAlertsDB
	if not (WOW_PROJECT_ID ~= nil and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE) then return false end
	if not (C_UnitAuras and C_UnitAuras.AddAuraSound and Enum and Enum.UnitAuraSoundTrigger) then return false end
	if not (sv and sv.enabled ~= false and sv.shields and sv.shields.enabled ~= false and sv.shields.sound) then return false end
	return true
end

function SP:RemoveShieldSounds()
	if C_UnitAuras and C_UnitAuras.RemoveAuraSound then
		for _, id in ipairs(shieldSoundIDs) do pcall(C_UnitAuras.RemoveAuraSound, id) end
	end
	wipe(shieldSoundIDs)
	shieldSoundKey = nil
	self.shieldSoundEngineActive = nil
end

function SP:UpdateShieldSounds()
	if not shieldSoundWanted() then
		if #shieldSoundIDs > 0 then self:RemoveShieldSounds() end
		return
	end
	local sv = ShamanPowerExpiringAlertsDB
	local sound = ShamanPower:GetSoundFile(sv.shields.soundName or "Raid Warning")
	local key = tostring(sound) .. "|" .. tostring(sv.shields.lightning ~= false) .. "|" .. tostring(sv.shields.water ~= false)
	if key == shieldSoundKey and #shieldSoundIDs > 0 then return end
	if InCombatLockdown() then shieldSoundPending = true return end
	shieldSoundPending = false
	self:RemoveShieldSounds()
	wipe(shieldSoundLog)
	local info = { unitToken = "player", outputChannel = "Master", throttleSeconds = 1 }
	if type(sound) == "number" then info.soundFileID = sound else info.soundFileName = sound end
	for _, set in ipairs(ShamanPower.ShieldAuraSets or {}) do
		local on = (set.name == "Lightning Shield" and sv.shields.lightning ~= false)
			or (set.name == "Water Shield" and sv.shields.water ~= false)
		if on then
			for _, spellID in ipairs(set.ids) do
				if self.shieldSoundSolo and spellID ~= self.shieldSoundSolo then
					shieldSoundLog[#shieldSoundLog + 1] = spellID .. " solo-off"
				elseif not (SPCompat and SPCompat.SpellExists) or SPCompat.SpellExists(spellID) then
					info.spellID = spellID
					local ok, id = pcall(C_UnitAuras.AddAuraSound, Enum.UnitAuraSoundTrigger.Removed, info)
					if ok and type(id) == "number" then
						shieldSoundIDs[#shieldSoundIDs + 1] = id
						shieldSoundLog[#shieldSoundLog + 1] = spellID .. "=" .. id
					else
						shieldSoundLog[#shieldSoundLog + 1] = spellID .. (ok and "=nil" or (":" .. tostring(id)))
					end
				else
					shieldSoundLog[#shieldSoundLog + 1] = spellID .. " skipped"
				end
			end
		end
	end
	shieldSoundKey = key
	self.shieldSoundEngineActive = (#shieldSoundIDs > 0) or nil
end

-- /spalerts sound: what the engine registration did, for testing on the beta.
function SP:ShieldSoundReport()
	local sv = ShamanPowerExpiringAlertsDB
	self:Print(("Shield sound: wanted=%s engine=%s pending=%s combat=%s"):format(
		tostring(shieldSoundWanted()), tostring(self.shieldSoundEngineActive), tostring(shieldSoundPending),
		tostring(InCombatLockdown())))
	local sound = ShamanPower:GetSoundFile(sv and sv.shields and sv.shields.soundName or "Raid Warning")
	self:Print(("  sound=%s (%s) name=%s key=%s"):format(tostring(sound), type(sound),
		tostring(sv and sv.shields and sv.shields.soundName), tostring(shieldSoundKey):gsub("|", "/")))
	self:Print("  registered " .. #shieldSoundIDs .. ": " .. table.concat(shieldSoundLog, ", "))
end

-- ============================================================================
-- State Detection and Updates
-- ============================================================================

function SP:UpdateExpiringAlertsState()
	-- Initialize current state without triggering alerts
	self:CheckShieldState(true)
	self:CheckTotemState(true)
	self:CheckWeaponEnchantState(true)
	self:CheckEarthShieldState(nil, true)
end

function SP:CheckShieldState(initializing)
	-- Restricted client (retail rules): state reads return nothing in combat; don't alert on that
	if SPCompat and SPCompat.combatDataSecret then return end
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

	-- A blocked read in combat returns nothing, same as "no shield". The flag at
	-- the top is only raised BY a blocked read, so the first one of a fight gets
	-- this far: keep the old state instead of calling a shield that's still on faded.
	if SPCompat and SPCompat.AurasUnreadable and SPCompat.AurasUnreadable() then return end

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

-- Totem state by addon element (1 Earth, 2 Fire, 3 Water, 4 Air). The core's
-- resolver handles clients that fill slots in cast order; otherwise the fixed
-- slot map applies (WoW slot 1 is Fire, slot 2 is Earth).
local function ElementTotemInfo(element)
	if ShamanPower.GetElementTotemInfo then return ShamanPower:GetElementTotemInfo(element) end
	return GetTotemInfo(ShamanPower.ElementToSlot[element])
end

-- Every way of saying "a totem was destroyed": the alert (and its sound), a line
-- in your own chat window, the big centre text, and (opt-in) the group chat.
function SP:TotemDestroyedAlert(totemName, elementColor)
	local t = ShamanPowerExpiringAlertsDB.totems
	if not t.destroyed then return end
	local label = StripRank(totemName or "") ~= "" and StripRank(totemName) or "Totem"
	self:ShowExpiringAlert("totem", label .. " Destroyed!", "Interface\\Icons\\Spell_Shaman_TotemRecall", elementColor)
	if t.destroyedChat ~= false and DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage("|cff0070ddShamanPower|r: |cffff5050" .. label .. " destroyed.|r")
	end
	if t.destroyedCenter and RaidNotice_AddMessage and RaidWarningFrame then
		RaidNotice_AddMessage(RaidWarningFrame, label .. " destroyed!", { r = 1, g = 0.3, b = 0.3 })
	end
	if t.destroyedParty and IsInGroup() then
		local channel = (IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and "INSTANCE_CHAT") or (IsInRaid() and "RAID") or "PARTY"
		pcall(SendChatMessage, label .. " destroyed!", channel)
	end
end

-- While the game hides totem data (combat on WoW: Forever), CheckTotemState stands
-- down; the core's own totem record still sees a slot empty with no cast, recall or
-- death behind it, and says why (ShamanPower.lua ShadowTotemSlotUpdate).
function SP:OnShadowTotemGone(element, entry, why)
	local sv = ShamanPowerExpiringAlertsDB
	if not (sv and sv.enabled and sv.totems and sv.totems.enabled) then return end
	local info = TotemElements[element]
	local elementKey = info and info.name and info.name:lower()
	if elementKey and sv.totems[elementKey] == false then return end
	local color = info and info.color or { r = 1, g = 1, b = 1 }
	if why == "destroyed" then
		self:TotemDestroyedAlert(entry.name, color)
	elseif why == "expired" and sv.totems.expired then
		self:ShowExpiringAlert("totem", StripRank(entry.name or "Totem") .. " Expired", "Interface\\Icons\\Spell_Shaman_TotemRecall", color)
	end
	if previousState.totems[element] then previousState.totems[element].active = false end
end

function SP:CheckTotemState(initializing)
	-- Restricted client (retail rules): state reads return nothing in combat; don't alert on that
	if SPCompat and SPCompat.combatDataSecret then return end
	local sv = ShamanPowerExpiringAlertsDB
	if not sv.enabled or not sv.totems or not sv.totems.enabled then return end

	for element = 1, 4 do
		local haveTotem, totemName, startTime, duration = ElementTotemInfo(element)

		local prev = previousState.totems[element]
		local wasActive = prev.active
		local prevName = prev.name
		local prevStart = prev.startTime
		local prevDuration = prev.duration

		if not initializing and wasActive and not haveTotem then
			-- Totem is gone - determine if destroyed or expired
			local elementName = TotemElements[element] and TotemElements[element].name or "Totem"
			local elementColor = TotemElements[element] and TotemElements[element].color or {r=1, g=1, b=1}

			-- Check element-specific toggle
			local elementKey = elementName:lower()
			if sv.totems[elementKey] ~= false then
				local elapsed = GetTime() - prevStart
				local isExpired = prevDuration > 0 and elapsed >= (prevDuration - 0.5)

				if isExpired then
					-- Totem expired naturally
					if sv.totems.expired then
						local icon = "Interface\\Icons\\Spell_Shaman_TotemRecall"
						self:ShowExpiringAlert("totem", StripRank(prevName) .. " Expired", icon, elementColor)
					end
				else
					-- Totem was destroyed
					self:TotemDestroyedAlert(prevName, elementColor)
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

local mainlineWeaponChecks = _G.WOW_PROJECT_ID ~= nil and _G.WOW_PROJECT_ID == _G.WOW_PROJECT_MAINLINE
local isSecretValue = _G.issecretvalue or function() return false end
local weaponExpiryTimer

local function CancelWeaponExpiry()
	if weaponExpiryTimer then weaponExpiryTimer:Cancel() weaponExpiryTimer = nil end
end

local function WeaponExpiryReached()
	weaponExpiryTimer = nil
	SP:CheckWeaponEnchantState(false)
end

-- Read the native list: the compatibility tuple turns failed reads into false.
-- Unknown/secret data must preserve the previous state, not announce a fade.
local function ReadMainlineWeaponEnchant(inventorySlot, weaponSlot)
	local link = _G.GetInventoryItemLink("player", inventorySlot)
	if isSecretValue(link) then return end
	local enchants = _G.C_Item.GetWeaponEnchantInfo(weaponSlot)
	if isSecretValue(enchants) or type(enchants) ~= "table" then return end
	local active, timeLeft = false, nil
	for _, enchant in pairs(enchants) do
		if isSecretValue(enchant) or type(enchant) ~= "table" then return end
		local hasEnchant = enchant.hasEnchant
		if isSecretValue(hasEnchant) or type(hasEnchant) ~= "boolean" then return end
		if hasEnchant then
			active = true
			local remaining = enchant.timeLeft
			if not isSecretValue(remaining) and type(remaining) == "number" and remaining > 0 then
				if not timeLeft or remaining < timeLeft then timeLeft = remaining end
			end
		end
	end
	return link ~= nil, active, timeLeft
end

function SP:CheckWeaponEnchantState(initializing)
	-- Weapon enchants are not hidden in combat the way buffs are (the cooldown
	-- bar reads them every update mid-fight), so imbue alerts keep working there.
	local sv = ShamanPowerExpiringAlertsDB
	if not sv.enabled or not sv.weaponImbues or not sv.weaponImbues.enabled then
		if not mainlineWeaponChecks then return end
		-- Settings can flip without an update callback. Keep the event-driven
		-- baseline/deadline while disabled, but never emit an expiration alert.
		initializing = true
	end

	-- Check if weapons are equipped (nil if no weapon in slot)
	-- Slot 16 = MainHandSlot, Slot 17 = SecondaryHandSlot (off-hand)
	local hasMainHandWeapon, hasOffHandWeapon, hasMainHandEnchant, hasOffHandEnchant
	local mainTimeLeft, offTimeLeft
	if mainlineWeaponChecks then
		local slots = _G.Enum and _G.Enum.WeaponSlot
		if not (slots and _G.C_Item and _G.C_Item.GetWeaponEnchantInfo) then return end
		local mainOK, offOK
		mainOK, hasMainHandWeapon, hasMainHandEnchant, mainTimeLeft =
			pcall(ReadMainlineWeaponEnchant, 16, slots.MainHand)
		offOK, hasOffHandWeapon, hasOffHandEnchant, offTimeLeft =
			pcall(ReadMainlineWeaponEnchant, 17, slots.OffHand)
		if not mainOK or not offOK or hasMainHandWeapon == nil or hasOffHandWeapon == nil then return end
		CancelWeaponExpiry()
	else
		hasMainHandWeapon = GetInventoryItemLink("player", 16) ~= nil
		hasOffHandWeapon = GetInventoryItemLink("player", 17) ~= nil
		-- Classic tuple: hasMain, mainExp, mainCharges, mainID, hasOff, offExp, offCharges, offID.
		local main, _, _, _, off = GetWeaponEnchantInfo()
		hasMainHandEnchant, hasOffHandEnchant = main, off
	end

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
	if mainlineWeaponChecks then
		local delay = mainHandEnchanted and mainTimeLeft or nil
		if offHandEnchanted and offTimeLeft and (not delay or offTimeLeft < delay) then delay = offTimeLeft end
		-- One cancellable deadline, no idle polling. The callback confirms actual
		-- absence; an elapsed prediction by itself never triggers an alert.
		if delay then weaponExpiryTimer = _G.C_Timer.NewTimer(delay / 1000, WeaponExpiryReached) end
	end
end

function SP:CheckEarthShieldState(unit, initializing)
	if SPCompat and SPCompat.combatDataSecret then return end
	local sv = ShamanPowerExpiringAlertsDB
	if not sv.enabled or not sv.shields or not sv.shields.enabled or not sv.shields.earthShield then return end

	-- The player your Earth Shield is actually on (cast tracking), else the assigned
	-- target, else the last name we saw: the core clears its tracking on the same
	-- UNIT_AURA that tells us the shield fell off, so the name must survive that moment
	local esTarget = ShamanPower.esTrackedTarget
		or (ShamanPower_EarthShieldAssignments and ShamanPower_EarthShieldAssignments[SP.player])
		or previousState.earthShieldTarget
	if not esTarget then return end
	esTarget = esTarget:match("^[^%-]+") or esTarget

	-- Check if ES is still on the target
	local hasES = false
	local targetUnit = nil

	-- The event handler passes the unit that changed; otherwise find them in the group
	if unit and UnitExists(unit) and UnitName(unit) == esTarget then
		targetUnit = unit
	else
		local units = {"player", "target", "focus", "party1", "party2", "party3", "party4"}
		for _, u in ipairs(units) do
			if UnitExists(u) and UnitName(u) == esTarget then
				targetUnit = u
				break
			end
		end
		if not targetUnit and IsInRaid() then
			for i = 1, 40 do
				local u = "raid" .. i
				if UnitExists(u) and UnitName(u) == esTarget then
					targetUnit = u
					break
				end
			end
		end
	end
	-- Nobody we can see carries that name: keep the last known state rather than
	-- reporting a shield we simply cannot observe as expired
	if not targetUnit then return end

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
	if SPCompat and SPCompat.StressRegister then SPCompat.StressRegister(eventFrame, "Expiring Alerts") end
	-- Your own buffs only (shields): the game filters, so the other 39 raid members'
	-- aura changes never reach this handler. Earth Shield's carrier has its own frame below.
	if eventFrame.RegisterUnitEvent then
		eventFrame:RegisterUnitEvent("UNIT_AURA", "player")
	else
		eventFrame:RegisterEvent("UNIT_AURA")
	end
	eventFrame:RegisterEvent("SPELLS_CHANGED")
	eventFrame:RegisterEvent("PLAYER_TOTEM_UPDATE")
	eventFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")
	if mainlineWeaponChecks then
		eventFrame:RegisterEvent("WEAPON_ENCHANT_CHANGED")
		eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
	end
	eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
	eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")   -- shield-sound registration deferred out of a fight
	eventFrame:RegisterEvent("PLAYER_LOGOUT")          -- engine sound IDs kept counting across /reload (41.. after a reload): drop ours before the UI goes

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

	-- the carrier's name without a realm, cached until the source name changes
	-- (this runs on group members' aura changes; no string built per call)
	local cachedESSource, cachedESName
	local function IsEarthShieldUnit(unit)
		local esTarget = ShamanPower.esTrackedTarget
			or (ShamanPower_EarthShieldAssignments and ShamanPower_EarthShieldAssignments[SP.player])
			or previousState.earthShieldTarget
		if not esTarget or not unit or not UnitExists(unit) then return false end
		if esTarget ~= cachedESSource then
			cachedESSource, cachedESName = esTarget, esTarget:match("^[^%-]+") or esTarget
		end
		return UnitName(unit) == cachedESName
	end

	-- Earth Shield's carrier is another player. Only a shaman who knows Earth Shield
	-- listens to other units' aura changes at all, and then only for the tokens the
	-- check below can match (group, target, focus; never nameplates or pets).
	local ES_TOKENS = { player = true, target = true, focus = true }
	for i = 1, 4 do ES_TOKENS["party" .. i] = true end
	for i = 1, 40 do ES_TOKENS["raid" .. i] = true end
	local esFrame = CreateFrame("Frame")
	esFrame:SetScript("OnEvent", function(_, _, unit)
		if type(unit) ~= "string" or isSecretValue(unit) or not ES_TOKENS[unit] then return end
		if IsEarthShieldUnit(unit) then
			SP:CheckEarthShieldState(unit, false)
		end
	end)
	local function knowsEarthShield()
		if SP.ESTrackerUnavailable then return false end
		-- the same check the rest of the addon uses (ES button, options)
		if SP.HasEarthShield then return SP:HasEarthShield() and true or false end
		return IsSpellKnown and (IsSpellKnown(974) or IsSpellKnown(32593) or IsSpellKnown(32594)) or false
	end
	local esWatching = false
	local function refreshESWatch()
		local want = knowsEarthShield()
		if want and not esWatching then esFrame:RegisterEvent("UNIT_AURA")
		elseif not want and esWatching then esFrame:UnregisterEvent("UNIT_AURA") end
		esWatching = want
	end
	refreshESWatch()

	local weaponCheckPending = false
	local function CheckWeaponsAfterCast()
		if not weaponCheckPending then return end
		weaponCheckPending = false
		SP:CheckWeaponEnchantState(false)
	end

	eventFrame:SetScript("OnEvent", function(_, event, unit, _castGUID, spellID)
		if event == "UNIT_AURA" then
			if unit == "player" then
				RequestAuraUpdate()
			end
			if IsEarthShieldUnit(unit) then
				SP:CheckEarthShieldState(unit, false)
			end
		elseif event == "PLAYER_TOTEM_UPDATE" then
			SP:CheckTotemState(false)
		elseif event == "UNIT_INVENTORY_CHANGED" then
			if (not mainlineWeaponChecks or not isSecretValue(unit)) and unit == "player" then
				SP:CheckWeaponEnchantState(false)
			end
		elseif mainlineWeaponChecks and event == "WEAPON_ENCHANT_CHANGED" then
			SP:CheckWeaponEnchantState(false)
		elseif mainlineWeaponChecks and event == "UNIT_SPELLCAST_SUCCEEDED" then
			if not isSecretValue(unit) and unit == "player" and not isSecretValue(spellID)
				and type(spellID) == "number" and not weaponCheckPending
				and _G.C_Spell and _G.C_Spell.GetSpellName then
				local ok, name = pcall(_G.C_Spell.GetSpellName, spellID)
				if ok and not isSecretValue(name) and type(name) == "string" then
					for _, imbue in pairs(WeaponImbues) do
						if name == imbue.name then
							-- Cast success can arrive before the enchant list changes.
							weaponCheckPending = true
							_G.C_Timer.After(0, CheckWeaponsAfterCast)
							break
						end
					end
				end
			end
		elseif event == "SPELLS_CHANGED" then
			refreshESWatch()
		elseif event == "PLAYER_ENTERING_WORLD" then
			refreshESWatch()
			SP:UpdateExpiringAlertsState()
			SP:UpdateShieldSounds()
		elseif event == "PLAYER_REGEN_ENABLED" then
			if shieldSoundPending then SP:UpdateShieldSounds() end
		elseif event == "PLAYER_LOGOUT" then
			SP:RemoveShieldSounds()
			if mainlineWeaponChecks then CancelWeaponExpiry() weaponCheckPending = false end
		end
	end)

	self.expiringAlertsEventFrame = eventFrame

	-- Classic keeps the periodic check; Mainline uses events and one expiry timer.
	-- (a ticker: the same twice-a-second check without a Lua call every frame)
	if not mainlineWeaponChecks then
		self.weaponCheckTicker = C_Timer.NewTicker(0.5, function() SP:CheckWeaponEnchantState(false) end)
	end

	-- Combat hides aura reads, so a shield that fell off during a fight goes
	-- unnoticed until the next buff change, which may be minutes away. Re-check
	-- the moment restrictions lift and report it then.
	if SPCompat and SPCompat.OnUnrestricted then
		SPCompat.OnUnrestricted(function()
			SP:CheckShieldState(false)
			-- Re-baseline silently after secret totem slots become readable, so a
			-- later totem event cannot announce a stale in-combat expiration.
			SP:CheckTotemState(true)
			if mainlineWeaponChecks then SP:CheckWeaponEnchantState(false) end
		end)
	end
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

function SP:ExpiringAlertsDemo(on)
	-- Setup-wizard preview: feed sample alerts through the REAL queue and
	-- animation pipeline, so style / duration / sizes / sounds all show.
	self:CreateExpiringAlertsFrame()
	local frame = self.expiringAlertsFrame
	if not frame then return end

	if on then
		if self.expiringAlertsDemoActive then return end   -- re-entrant: nothing to reset
		self.expiringAlertsDemoActive = true
		frame:Show()
		local sv = ShamanPowerExpiringAlertsDB
		local SCENE = {
			{ type = "shield", cond = function() return sv.shields.enabled and sv.shields.lightning end,
			  name = "Lightning Shield", icon = ShieldSpells.lightningShield.icon, color = ElementColors.lightning,
			  story = "Your Lightning Shield just ran out" },
			{ type = "totem", cond = function() return sv.totems.enabled and sv.totems.destroyed end,
			  name = "Tremor Totem Destroyed!", icon = "Interface\\Icons\\Spell_Nature_TremorTotem", color = TotemElements[1].color,
			  story = "A mob killed your Tremor Totem" },
			{ type = "imbue", cond = function() return sv.weaponImbues.enabled and sv.weaponImbues.mainHand end,
			  name = "Weapon Imbue (MH)", icon = WeaponImbues.windfury.icon, color = sv.weaponImbues.color,
			  story = "Windfury Weapon faded from your main hand" },
			{ type = "shield", cond = function() return sv.shields.enabled and sv.shields.water end,
			  name = "Water Shield", icon = ShieldSpells.waterShield.icon, color = ElementColors.water,
			  story = "Your Water Shield just ran out" },
			{ type = "totem", cond = function() return sv.totems.enabled and sv.totems.expired end,
			  name = "Mana Spring Totem Expired", icon = "Interface\\Icons\\Spell_Nature_ManaRegenTotem", color = TotemElements[3].color,
			  story = "Your Mana Spring Totem timed out" },
			{ type = "shield", cond = function() return sv.shields.enabled and sv.shields.earthShield and not (SPCompat and SPCompat.earthShieldExists == false) end,
			  name = "Earth Shield (Tank)", icon = ShieldSpells.earthShield.icon, color = ElementColors.earth,
			  story = "Earth Shield dropped off your tank" },
		}
		local idx = 0
		local function fire()
			if not self.expiringAlertsDemoActive then return end
			for _ = 1, #SCENE do
				idx = (idx % #SCENE) + 1
				local a = SCENE[idx]
				if a.cond() then
					self.expiringDemoStatus = a.story
					tinsert(self.alertQueue, { alertType = a.type, spellName = a.name, spellIcon = a.icon, color = a.color })
					self:ProcessAlertQueue()
					return
				end
			end
			self.expiringDemoStatus = "Nothing is switched on to alert about"
		end
		if self.expiringDemoTicker then self.expiringDemoTicker:Cancel() end
		self.expiringDemoTicker = C_Timer.NewTicker(3.0, fire)
		fire()
	else
		self.expiringAlertsDemoActive = false
		if self.expiringDemoTicker then self.expiringDemoTicker:Cancel(); self.expiringDemoTicker = nil end
		self.expiringDemoStatus = nil
		wipe(self.alertQueue)
		for i = #self.activeAlerts, 1, -1 do
			local f = self.activeAlerts[i]
			f.animGroup:Stop()
			self:ReleaseAlertFrame(f)
			self.activeAlerts[i] = nil
		end
	end
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
		SP:SetSPFont(frame.text, "alerts", sv.textSize or 24, outline)
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
	elseif msg == "sound" or msg == "sound solo" or msg == "sound all" then
		shieldSoundDebug = true
		if msg == "sound solo" then SP.shieldSoundSolo = 324 elseif msg == "sound all" then SP.shieldSoundSolo = nil end
		if msg ~= "sound" then SP:RemoveShieldSounds() end
		SP:UpdateShieldSounds()
		SP:ShieldSoundReport()
	else
		-- Open options
		if ShamanPowerConfig then
			ShamanPowerConfig:Open({ "fluffy", "expiringalerts_section" })
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

-- ============================================================================
-- Setup Wizard Preview
-- ============================================================================

if ShamanPower.RegisterPreview then
	ShamanPower:RegisterPreview("expiring", { frame = "ShamanPowerExpiringAlertsFrame", demo = "SP:ExpiringAlertsDemo", pad = 24,
		pane = { maxScale = 1.0 } })   -- settings-window pane only: life-size, the text is wider than the frame
end
