-- ============================================================================
-- ShamanPower [Reactive Totems] Module
-- Shows large totem icons when you have fear, disease, or poison debuffs
-- Each totem type has its own movable frame
-- ============================================================================

-- "First Surname" on WoW: Forever (SPCompat.UnitName); other clients unchanged
local UnitName = (SPCompat and SPCompat.UnitName) or UnitName
local SP = ShamanPower
local UnitDebuff = SPCompat and SPCompat.UnitDebuff or UnitDebuff   -- ShamanPower's own reader on Forever, never another addon's global
if not SP then
	print("|cff0070ddShamanPower [Reactive Totems]:|r ShamanPower is not loaded.")
	return
end

-- Only load for Shamans
local _, playerClass = UnitClass("player")
if playerClass ~= "SHAMAN" then
	return
end

-- Mark module as loaded
SP.ReactiveTotemsLoaded = true

-- SavedVariables
ShamanPower_ReactiveTotems = ShamanPower_ReactiveTotems or {}

-- ============================================================================
-- Reactive Totem Definitions
-- ============================================================================

SP.ReactiveTotems = {
	fear = {
		id = "fear",
		name = "Fear/Charm",
		debuffTypes = {"Fear", "Charm", "Horrify"},
		totemName = "Tremor Totem",
		totemSpellID = 8143,
		totemElement = 1,  -- Earth
		icon = "Interface\\Icons\\Spell_Nature_TremorTotem",
		color = {r = 0.8, g = 0.2, b = 0.8},  -- Purple
		defaultPos = { point = "CENTER", x = -80, y = 150 },
	},
	poison = {
		id = "poison",
		name = "Poison",
		debuffTypes = {"Poison"},
		totemName = "Poison Cleansing Totem",
		totemSpellID = 8166,
		totemElement = 3,  -- Water
		icon = "Interface\\Icons\\Spell_Nature_PoisonCleansingTotem",
		color = {r = 0.2, g = 0.8, b = 0.2},  -- Green
		defaultPos = { point = "CENTER", x = 0, y = 150 },
	},
	disease = {
		id = "disease",
		name = "Disease",
		debuffTypes = {"Disease"},
		totemName = "Disease Cleansing Totem",
		totemSpellID = 8170,
		totemElement = 3,  -- Water
		icon = "Interface\\Icons\\Spell_Nature_DiseaseCleansingTotem",
		color = {r = 0.6, g = 0.4, b = 0.2},  -- Brown
		defaultPos = { point = "CENTER", x = 80, y = 150 },
	},
}
for _, data in pairs(SP.ReactiveTotems) do
	data.totemName = SPCompat.SpellLabel(data.totemSpellID, data.totemName)
end

-- Theme (General > Themes, spot mod.reactive): each alert's colour table above
-- is bound to the element of the totem that answers it (Tremor = Earth, the
-- cleansing totems = Water). The engine rewrites these tables in place and
-- puts today's colours back on Standard, so every paint site below reads them
-- as it always has. Looks only; nothing is written until a theme is picked.
if SP.ThemeBind then
	for _, id in ipairs({ "fear", "poison", "disease" }) do
		local data = SP.ReactiveTotems[id]
		SP:ThemeBind(data.color, "mod.reactive", tostring(data.totemElement))
	end
end

-- Existing fear/charm list, by spell ID. The bundled duration library provides
-- player spell ranks; localized-name matching also covers other NPC variants.
SP.FearSpells = {
	{ 5782, "Fear" }, { 6213, "Fear" }, { 6215, "Fear" },
	{ 5484, "Howl of Terror" }, { 17928, "Howl of Terror" },
	{ 6789, "Death Coil" }, { 17925, "Death Coil" }, { 17926, "Death Coil" },
	{ 6358, "Seduction" },
	{ 5246, "Intimidating Shout" }, { 20511, "Intimidating Shout" },
	{ 8122, "Psychic Scream" }, { 8124, "Psychic Scream" }, { 10888, "Psychic Scream" }, { 10890, "Psychic Scream" },
	-- The Forever spell catalog does not include 18431; retain the old English
	-- match when a client cannot resolve it, and recognize its named variants.
	{ 18431, "Bellowing Roar" }, { 22686, "Bellowing Roar" },
	{ 445498, "Bellowing Roar" }, { 1214028, "Bellowing Roar" },
	{ 6605, "Terrifying Screech" }, { 19372, "Ancient Hysteria" }, { 16508, "Intimidating Roar" },
}
SP.FearSpellNames = {}
SP.FearSpellIDSet = {}
for _, spell in ipairs(SP.FearSpells) do
	local id = spell[1]
	SP.FearSpellIDSet[id] = true
	local name = SPCompat.SpellName(id, spell[2])
	if name then SP.FearSpellNames[name] = true end
end

-- ============================================================================
-- Default Settings
-- ============================================================================

local defaultSettings = {
	enabled = true,
	locked = false,

	-- Global appearance (applies to all frames)
	iconSize = 64,
	scale = 1.0,
	opacity = 1.0,
	hideBorder = false,
	hideBackground = false,

	-- Text options
	showDebuffName = true,
	showTotemName = true,
	showDebuffIcon = false,       -- engine-drawn alerts: the debuff's own icon as a corner badge (opt-in)
	showSpellKeybind = false,     -- the key bound to the alert's own totem, under its name (opt-in)
	noKeyText = "none",           -- that totem has no key: "none" (show nothing) | "show" ("No Key Bound")
	fontSize = 14,
	fontOutline = true,

	-- Effects
	showGlow = true,
	glowIntensity = 0.8,
	colorByDebuffType = true,

	-- Audio
	playSound = false,
	soundName = "Raid Warning",
	soundVolume = 100,

	-- Behavior
	clickToCast = true,
	onlyInInstance = false,       -- Only show alerts inside instances (dungeons/raids/PvP)
	hideWhenTotemActive = true,   -- Hide alert when the relevant totem is already placed

	-- Per-totem tracking toggles
	trackFear = true,
	trackPoison = true,
	trackDisease = true,

	-- Per-totem positions (each totem can be moved independently)
	positions = {
		fear = { point = "CENTER", x = -80, y = 150 },
		poison = { point = "CENTER", x = 0, y = 150 },
		disease = { point = "CENTER", x = 80, y = 150 },
	},
}
-- the support code (/sp support) reports only what differs from these
if SP and SP.SUPPORT_MODULE_DEFAULTS then SP.SUPPORT_MODULE_DEFAULTS.ShamanPower_ReactiveTotems = defaultSettings end

-- ============================================================================
-- Each alert's own settings (3.0.8, the settings page's icon row: A16)
-- ============================================================================
-- Fear, Poison and Disease each have their own look, Spell Keybind, glow, sound (with
-- its own volume) and Hide While Its Totem Is Down: sv.alertOwn[id][name], EMPTY until
-- the player changes one, and until then the shared value it always used (sv[name]),
-- so an untouched profile looks and works exactly as before. Unlock UI's wheel over an
-- alert's box sets that alert's own Icon Size (Ctrl: Opacity).
local RT_OWN_NAMES = { "hideWhenTotemActive", "iconSize", "opacity", "fontSize", "fontOutline", "hideBackground", "hideBorder",
	"showDebuffName", "showDebuffIcon", "showTotemName", "showSpellKeybind", "noKeyText", "showGlow", "glowIntensity",
	"playSound", "soundName", "soundVolume" }
local RT_OWN = {}
for _, name in ipairs(RT_OWN_NAMES) do RT_OWN[name] = true end
SP.ReactiveOwnNames = RT_OWN_NAMES
-- the alert's value as the code reads it: its own, else the shared one (nil = as today)
local function R(id, name)
	local sv = ShamanPower_ReactiveTotems
	local all = sv and sv.alertOwn
	local own = type(all) == "table" and id and all[id]
	if type(own) == "table" then
		local v = own[name]
		if v ~= nil then return v end
	end
	return sv and sv[name]
end
local function SameValue(a, b)
	if type(a) == "number" and type(b) == "number" then return math.abs(a - b) < 1e-4 end
	return a == b
end
-- a value with today's default filled in (what the old rows showed)
local function WithDefault(name, v)
	if v == nil then v = defaultSettings[name] end
	return v
end
-- value, own: own = this alert has a value of its own that differs from the shared one
function SP:ReactiveOpt(id, name)
	if not RT_OWN[name] then return nil, false end
	local sv = ShamanPower_ReactiveTotems
	local shared = WithDefault(name, sv and sv[name])
	local v = WithDefault(name, R(id, name))
	return v, not SameValue(v, shared)
end
local function SetOwn(sv, id, name, v)
	if type(sv.alertOwn) ~= "table" then sv.alertOwn = {} end
	local own = sv.alertOwn[id]
	if type(own) ~= "table" then own = {}; sv.alertOwn[id] = own end
	own[name] = v
	if next(own) == nil then sv.alertOwn[id] = nil end
	if next(sv.alertOwn) == nil then sv.alertOwn = nil end
end
-- v: the alert's own value (nil: back on the shared one); the alert is drawn again
function SP:SetReactiveOpt(id, name, v)
	local sv = ShamanPower_ReactiveTotems
	if not (sv and RT_OWN[name] and self.ReactiveTotems[id]) then return end
	SetOwn(sv, id, name, v)
	self:ReactiveOptChanged(id, name)
end
-- several at once (Paste, Copy To): own[name] = values[name] (nil: the shared one) for
-- each of names, then the alert is drawn again once
function SP:SetReactiveOpts(id, values, names)
	local sv = ShamanPower_ReactiveTotems
	if not (sv and self.ReactiveTotems[id]) then return end
	local keys, look, hide = false, false, false
	for _, name in ipairs(names) do
		if RT_OWN[name] then
			SetOwn(sv, id, name, values[name])
			if name == "showSpellKeybind" or name == "noKeyText" then keys = true
			elseif name == "hideWhenTotemActive" then hide = true
			elseif name ~= "playSound" and name ~= "soundName" and name ~= "soundVolume" then look = true end
		end
	end
	if keys then self:ReactiveOptChanged(id, "showSpellKeybind") elseif look then self:ReactiveOptChanged(id, "iconSize") end
	if hide then self:ReactiveOptChanged(id, "hideWhenTotemActive") end
end
-- an alert's own value as saved (nil: it uses the shared one), for Copy Settings
function SP:ReactiveOwnRaw(id, name)
	local sv = ShamanPower_ReactiveTotems
	local own = sv and type(sv.alertOwn) == "table" and sv.alertOwn[id]
	if type(own) ~= "table" then return nil end
	return own[name]
end
-- The game-drawn alerts (WoW: Forever) are built again once a change settles: a slider
-- dragged or the wheel turned in Unlock UI makes one rebuild, not one per step.
local rebuildAt, rebuildWaiting = 0, false
local function RebuildWhenSettled()
	local wait = rebuildAt - GetTime()
	if wait > 0.02 then C_Timer.After(wait, RebuildWhenSettled) return end
	rebuildWaiting = false
	if SP.reactiveEngineBuilt then SP:RebuildReactiveEngine() end
end
function SP:QueueReactiveRebuild()
	if not self.reactiveEngineBuilt then return end
	rebuildAt = GetTime() + 0.4
	if not rebuildWaiting then
		rebuildWaiting = true
		C_Timer.After(0.4, RebuildWhenSettled)
	end
end
-- a setting of one alert (or, id nil, of all) changed: what it touches is drawn again
function SP:ReactiveOptChanged(id, name)
	if name == "showSpellKeybind" then
		-- a fresh key scan: its hook works the keys out and updates the alerts
		if self.UpdateButtonKeybindText then self:UpdateButtonKeybindText() end
		self:RefreshReactiveKeys()
		self:UpdateReactiveFrameAppearance(id, true)
		self:QueueReactiveRebuild()
	elseif name == "noKeyText" then
		-- only the key captions: never the general appearance update, which in a fight on
		-- WoW: Forever showed the alerts' empty boxes
		self:RefreshReactiveKeyCaptions()
	elseif name == "hideWhenTotemActive" then
		self:UpdateReactiveTotems()
		self:ApplyReactiveEngineVisibility()
	elseif name == "playSound" or name == "soundName" or name == "soundVolume" then
		return
	else
		self:UpdateReactiveFrameAppearance(id, true)
		self:QueueReactiveRebuild()
	end
end
-- the blue corner: any value of its own that differs from the shared one
function SP:ReactiveOwnChanged(id)
	for _, name in ipairs(RT_OWN_NAMES) do
		local _, own = self:ReactiveOpt(id, name)
		if own then return true end
	end
	return false
end
-- Reset This Alert: back on the shared values
function SP:ResetReactiveAlert(id)
	local sv = ShamanPower_ReactiveTotems
	if not (sv and type(sv.alertOwn) == "table") then return end
	local had = sv.alertOwn[id]
	sv.alertOwn[id] = nil
	if next(sv.alertOwn) == nil then sv.alertOwn = nil end
	if type(had) == "table" then
		if had.showSpellKeybind ~= nil then self:ReactiveOptChanged(id, "showSpellKeybind") end
		self:ReactiveOptChanged(id, "iconSize")
		self:ReactiveOptChanged(id, "hideWhenTotemActive")
	end
end
-- the alert on / off: today's Track Fear/Charm, Track Poison, Track Disease
local RT_TRACK = { fear = "trackFear", poison = "trackPoison", disease = "trackDisease" }
function SP:ReactiveAlertOn(id)
	local sv = ShamanPower_ReactiveTotems
	return not (sv and sv[RT_TRACK[id]] == false)
end
function SP:SetReactiveAlertOn(id, on)
	local sv = ShamanPower_ReactiveTotems
	if not (sv and RT_TRACK[id]) then return end
	sv[RT_TRACK[id]] = on and true or false
	self:UpdateReactiveTotems()
	self:ApplyReactiveEngineVisibility()
end
-- any alert with this on (Show Spell Keybind, Play Sound)
function SP:ReactiveAnyOpt(name)
	for id in pairs(self.ReactiveTotems) do
		if R(id, name) then return true end
	end
	return false
end
-- the core's key scan does its second pass while any alert shows its key (ShamanPower.lua)
function SP:ReactiveAnyKeybind() return self:ReactiveAnyOpt("showSpellKeybind") end
-- an alert's own sound, at its own volume (Test Sound, Test All Frames)
function SP:PlayReactiveSound(id)
	self:PlaySoundWithVolume(self:GetSoundFile(R(id, "soundName") or "Raid Warning"), R(id, "soundVolume"), true)
end
-- Unlock UI: the wheel over an alert's box is that alert's own Icon Size, Ctrl + wheel its Opacity
function SP:ReactiveBoxAccess(name, frame)
	local id = frame and frame.totemId
	if not (id and self.ReactiveTotems[id] and ShamanPower_ReactiveTotems) then return nil end
	if name == "opacity" then
		return function() return (SP:ReactiveOpt(id, "opacity")) end,
			function(v) SP:SetReactiveOpt(id, "opacity", v) end, 0.2, 1.0, 0.1, true
	end
	return function() return (SP:ReactiveOpt(id, "iconSize")) end,
		function(v) SP:SetReactiveOpt(id, "iconSize", v) end, 32, 256, 4, false
end
-- the defaults (Reset This Page)
function SP:ReactiveTotemsDefaults() return defaultSettings end

-- ============================================================================
-- Initialization
-- ============================================================================

function SP:InitReactiveTotems()
	-- One-time merge of the old separate Scale into Size (iconSize).
	local db = ShamanPower_ReactiveTotems
	if db and db.scale and math.abs(db.scale - 1) > 0.001 then
		db.iconSize = math.floor((db.iconSize or 64) * db.scale + 0.5)
		db.scale = 1.0
	end
	local sv = ShamanPower_ReactiveTotems

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

	-- Ensure positions table exists for each totem
	if not sv.positions then sv.positions = {} end
	for totemId, totemData in pairs(self.ReactiveTotems) do
		if not sv.positions[totemId] then
			sv.positions[totemId] = {
				point = totemData.defaultPos.point,
				x = totemData.defaultPos.x,
				y = totemData.defaultPos.y
			}
		end
	end
end

-- ============================================================================
-- Frame Creation (one frame per totem type)
-- ============================================================================

SP.reactiveFrames = {}  -- [totemId] = frame

function SP:CreateReactiveTotemFrame(totemId)
	if self.reactiveFrames[totemId] then return self.reactiveFrames[totemId] end

	local sv = ShamanPower_ReactiveTotems
	local totemData = self.ReactiveTotems[totemId]
	if not totemData then return nil end

	local size = R(totemId, "iconSize") or 64
	local pos = sv.positions[totemId] or totemData.defaultPos

	-- Main frame - regular button (no click-to-cast due to combat restrictions)
	local frame = CreateFrame("Button", "ShamanPowerReactive_" .. totemId, UIParent, "BackdropTemplate")
	frame:SetSize(size, size)
	frame:SetPoint(pos.point or "CENTER", UIParent, pos.point or "CENTER", pos.x or 0, pos.y or 150)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:SetClampedToScreen(true)
	frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	frame.totemId = totemId
	frame.totemData = totemData

	-- Background
	local bg = frame:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.6)
	frame.bg = bg

	-- Icon
	local icon = frame:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("TOPLEFT", 3, -3)
	icon:SetPoint("BOTTOMRIGHT", -3, 3)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	icon:SetTexture(totemData.icon)
	frame.icon = icon

	-- Border
	local borderFrame = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	borderFrame:SetPoint("TOPLEFT", -2, 2)
	borderFrame:SetPoint("BOTTOMRIGHT", 2, -2)
	borderFrame:SetBackdrop({
		edgeFile = "Interface\\Buttons\\WHITE8X8",
		edgeSize = 2,
	})
	local c = totemData.color
	borderFrame:SetBackdropBorderColor(c.r, c.g, c.b, 1)
	frame.borderFrame = borderFrame

	-- Glow
	local glow = frame:CreateTexture(nil, "OVERLAY", nil, 1)
	glow:SetPoint("TOPLEFT", -12, 12)
	glow:SetPoint("BOTTOMRIGHT", 12, -12)
	glow:SetTexture("Interface\\SpellActivationOverlay\\IconAlert")
	glow:SetTexCoord(0.00781250, 0.50781250, 0.27734375, 0.52734375)
	if SP.ShapeGlow then SP:ShapeGlow(glow, "alert") end   -- Glow Shape
	glow:SetAlpha(0)
	glow:SetBlendMode("ADD")
	glow:SetVertexColor(c.r, c.g, c.b)
	frame.glow = glow

	-- Animation
	local ag = glow:CreateAnimationGroup()
	ag:SetLooping("REPEAT")

	local fadeIn = ag:CreateAnimation("Alpha")
	fadeIn:SetFromAlpha(0.2)
	fadeIn:SetToAlpha(R(totemId, "glowIntensity") or 0.8)
	fadeIn:SetDuration(0.4)
	fadeIn:SetOrder(1)

	local fadeOut = ag:CreateAnimation("Alpha")
	fadeOut:SetFromAlpha(R(totemId, "glowIntensity") or 0.8)
	fadeOut:SetToAlpha(0.2)
	fadeOut:SetDuration(0.4)
	fadeOut:SetOrder(2)

	frame.glowAnim = ag

	-- Debuff name text
	local debuffText = frame:CreateFontString(nil, "OVERLAY")
	SP:SetSPFont(debuffText, "alerts", R(totemId, "fontSize") or 14, R(totemId, "fontOutline") and "OUTLINE" or "")
	debuffText:SetPoint("TOP", frame, "BOTTOM", 0, -4)
	debuffText:SetTextColor(c.r, c.g, c.b)
	debuffText:SetShadowColor(0, 0, 0, 1)
	debuffText:SetShadowOffset(1, -1)
	frame.debuffText = debuffText

	-- Totem name text
	local totemText = frame:CreateFontString(nil, "OVERLAY")
	SP:SetSPFont(totemText, "alerts", (R(totemId, "fontSize") or 14) - 2, R(totemId, "fontOutline") and "OUTLINE" or "")
	totemText:SetPoint("TOP", debuffText, "BOTTOM", 0, -2)
	totemText:SetText(totemData.totemName)
	totemText:SetTextColor(1, 0.82, 0)
	totemText:SetShadowColor(0, 0, 0, 1)
	totemText:SetShadowOffset(1, -1)
	frame.totemText = totemText

	-- Drag handling - use ALT+drag to move (so left-click can cast)
	frame:SetScript("OnMouseDown", function(self, button)
		if button == "LeftButton" and IsAltKeyDown() and not ShamanPower_ReactiveTotems.locked then
			self:StartMoving()
			self.isMoving = true
		end
	end)

	frame:SetScript("OnMouseUp", function(self, button)
		if self.isMoving then
			self:StopMovingOrSizing()
			self.isMoving = false
			local point, _, _, x, y = self:GetPoint()
			ShamanPower_ReactiveTotems.positions[self.totemId] = { point = point, x = x, y = y }
		end
	end)

	-- Tooltip
	frame:SetScript("OnEnter", function(self)
		if SP.opt and SP.opt.ShowTooltips then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(self.totemData.name .. " Alert", 1, 0.82, 0)
			GameTooltip:AddLine(" ")
			if self.currentDebuffName then
				GameTooltip:AddLine("Debuff: " .. self.currentDebuffName, c.r, c.g, c.b)
			end
			if not ShamanPower_ReactiveTotems.locked then
				GameTooltip:AddLine(" ")
				GameTooltip:AddLine("ALT+drag to move | Right-click for options", 0.5, 0.5, 0.5)
			end
			GameTooltip:Show()
		end
	end)

	frame:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	-- Click handlers
	frame:SetScript("OnClick", function(self, button)
		if button == "RightButton" then
			-- Open Look & Feel settings
			if ShamanPowerConfig then
				ShamanPowerConfig:Open({ "fluffy", "reactivetotems_section" })
			end
		end
	end)

	frame:SetAlpha(R(totemId, "opacity") or 1.0)
	frame:Hide()

	self.reactiveFrames[totemId] = frame
	self:UpdateReactiveFrameAppearance(totemId)
	return frame
end

-- Create all frames
function SP:CreateAllReactiveFrames()
	for totemId, _ in pairs(self.ReactiveTotems) do
		self:CreateReactiveTotemFrame(totemId)
	end
end

-- Update appearance for one or all frames (noEngine: the game-drawn copies are rebuilt
-- by the caller, once its change settles)
function SP:UpdateReactiveFrameAppearance(totemId, noEngine)

	local function updateFrame(id)
		local frame = self.reactiveFrames[id]
		if not frame then return end

		local size = R(id, "iconSize") or 64
		frame:SetSize(size, size)
		frame:SetAlpha(R(id, "opacity") or 1.0)

		-- Background
		if R(id, "hideBackground") then
			frame.bg:Hide()
		else
			frame.bg:Show()
		end

		-- Border
		if R(id, "hideBorder") then
			frame.borderFrame:Hide()
		else
			frame.borderFrame:Show()
		end

		-- Font
		local fontSize = R(id, "fontSize") or 14
		local outline = R(id, "fontOutline") and "OUTLINE" or ""
		SP:SetSPFont(frame.debuffText, "alerts", fontSize, outline)
		SP:SetSPFont(frame.totemText, "alerts", fontSize - 2, outline)

		-- Text visibility
		if R(id, "showDebuffName") then
			frame.debuffText:Show()
		else
			frame.debuffText:Hide()
		end

		if R(id, "showTotemName") then
			frame.totemText:Show()
		else
			frame.totemText:Hide()
		end

		self:ReactiveHostKeyCaption(frame, id)
	end

	if totemId then
		updateFrame(totemId)
	else
		for id, _ in pairs(self.ReactiveTotems) do
			updateFrame(id)
		end
	end
	if self.reactiveEngineBuilt and not noEngine then self:RebuildReactiveEngine() end   -- engine copies of the art (no-op unless it changed)
end

-- ============================================================================
-- Spell keybind under the alert (Show Spell Keybind, off to start)
-- ============================================================================
-- Each alert can show the key that casts ITS totem ("Tremor Totem" / "Shift-2"),
-- under the totem's name. Only a key bound to that exact spell counts: the spell
-- on the action bars (the core's key scan, the same one the bar buttons show) or
-- the flyout button that casts it in Keybind Mode, in Keybind Shown's order
-- (General > Keybinds). Never an element button's key: the Earth button casts
-- whichever Earth totem is assigned (Stoneskin, Strength of Earth...).
-- The text is worked out out of combat, from the scan, and handed to the alert
-- as a plain string: on WoW: Forever the game draws the alert in fights and the
-- caption with it, so a key that changes in a fight shows after the fight (the
-- engine displays are rebuilt then, as for any other change to their art).

local KEY_MODS = { CTRL = "Ctrl", ALT = "Alt", SHIFT = "Shift", META = "Cmd" }
local KEY_NAMES = {
	SPACE = "Space", TAB = "Tab", ENTER = "Enter", ESCAPE = "Esc", BACKSPACE = "Backspace",
	CAPSLOCK = "Caps Lock", INSERT = "Insert", DELETE = "Delete", HOME = "Home", END = "End",
	PAGEUP = "Page Up", PAGEDOWN = "Page Down", UP = "Up", DOWN = "Down", LEFT = "Left", RIGHT = "Right",
	MOUSEWHEELUP = "Wheel Up", MOUSEWHEELDOWN = "Wheel Down", PRINTSCREEN = "Print Screen",
	NUMLOCK = "Num Lock", SCROLLLOCK = "Scroll Lock", PAUSE = "Pause",
	NUMPADPLUS = "Numpad+", NUMPADMINUS = "Numpad-", NUMPADMULTIPLY = "Numpad*", NUMPADDIVIDE = "Numpad/",
	NUMPADDECIMAL = "Numpad.", NUMPADENTER = "Numpad Enter", NUMPADEQUALS = "Numpad=",
}

-- A binding ("CTRL-SHIFT-BUTTON4") in words ("Ctrl-Shift-Mouse4"); other languages
-- get the game's own key names.
local function KeyWords(key)
	if type(key) ~= "string" or key == "" then return nil end
	local locale = GetLocale and GetLocale()
	if locale and locale ~= "enUS" and locale ~= "enGB" and GetBindingText then
		local text = GetBindingText(key)
		if type(text) == "string" and text ~= "" then return text end
	end
	local parts, rest = {}, key
	while true do
		local mod, after = rest:match("^(%u+)%-(.+)$")
		if not (mod and KEY_MODS[mod]) then break end
		parts[#parts + 1] = KEY_MODS[mod]
		rest = after
	end
	local word = KEY_NAMES[rest]
	if not word then
		local n = rest:match("^BUTTON(%d+)$")
		if n then
			word = "Mouse" .. n
		else
			n = rest:match("^NUMPAD(%d)$")
			if n then
				word = "Numpad" .. n
			elseif #rest > 1 and rest:match("^%u+$") then
				word = rest:sub(1, 1) .. rest:sub(2):lower()
			else
				word = rest
			end
		end
	end
	parts[#parts + 1] = word
	return table.concat(parts, "-")
end

-- The raw key bound to this alert's own totem, or nil. The action bar key comes
-- from the core's exact-key pass (actionBarExactKeybinds, scanned while Show Spell
-- Keybind is on), which passes over ShamanPower's own SP_ macros: SP_Earth or
-- SP_DropAll cast whichever totem comes next, never this totem for sure.
local function ReactiveSpellKey(data)
	local name = SPCompat.TotemCastName and SPCompat.TotemCastName(data.totemSpellID) or SPCompat.SpellName(data.totemSpellID)
	if not name then return nil end
	local mode = SP.opt and SP.opt.keybindSource
	local exact = SP.actionBarExactKeybinds
	local barKey = (mode ~= "sponly") and exact and exact[name] or nil
	local spKey = SP.FlyoutSpellClickKey and SP:FlyoutSpellClickKey(name, data.totemElement) or nil
	if mode == "sp" or mode == "sponly" then return spKey or barKey end
	return barKey or spKey
end

-- [totemId] = the key in words, false (learned, no key) or nil (not learned / not worked out)
local reactiveKeyWords = {}

local measureFS
local function TextWidth(text, size, outline)
	if not measureFS then
		measureFS = UIParent:CreateFontString(nil, "OVERLAY")
		measureFS:Hide()
	end
	SP:SetSPFont(measureFS, "alerts", size, outline)
	measureFS:SetText(text)
	return (measureFS.GetUnboundedStringWidth and measureFS:GetUnboundedStringWidth()) or measureFS:GetStringWidth() or 0
end

-- Lines no wider than one and a half icons or the totem's name (whichever is
-- wider), broken only after a "-", so a long key wraps between its parts
-- ("Ctrl-Shift-" / "Mouse4", "Alt-Ctrl-Shift-" / "Wheel Down") instead of running
-- wide. A part is never split ("Wheel Down" stays one line, as does "No Key
-- Bound"), and nothing is ever cut short.
local function WrapCaption(text, data)
	local id = data.id
	local size, outline = (R(id, "fontSize") or 14) - 2, R(id, "fontOutline") and "OUTLINE" or ""
	local limit = math.max((R(id, "iconSize") or 64) * 1.5, TextWidth(data.totemName or "", size, outline))
	if TextWidth(text, size, outline) <= limit + 0.5 then return text end
	local tokens, cur = {}, ""
	for ch in text:gmatch(".") do
		cur = cur .. ch
		if ch == "-" and cur:find("[^%-%s]") then
			tokens[#tokens + 1] = cur
			cur = ""
		end
	end
	if cur ~= "" then
		if cur:find("[^%-%s]") or #tokens == 0 then tokens[#tokens + 1] = cur else tokens[#tokens] = tokens[#tokens] .. cur end
	end
	local lines, line = {}, ""
	for _, t in ipairs(tokens) do
		local try = line .. t
		if line ~= "" and TextWidth((try:gsub("%s+$", "")), size, outline) > limit + 0.5 then
			lines[#lines + 1] = (line:gsub("%s+$", ""))
			line = t
		else
			line = try
		end
	end
	if line ~= "" then lines[#lines + 1] = (line:gsub("%s+$", "")) end
	return table.concat(lines, "\n")
end

-- What the alert shows under the totem's name: text ("" = nothing), and true for
-- a key (white, like the time left) or false for "No Key Bound" (WoW's gray).
function SP:ReactiveKeyCaption(totemId)
	local sv = ShamanPower_ReactiveTotems
	local data = self.ReactiveTotems[totemId]
	if not (sv and data and R(totemId, "showSpellKeybind")) then return "", false end
	local words = reactiveKeyWords[totemId]
	if words then return WrapCaption(words, data), true end
	if words == false and R(totemId, "noKeyText") == "show" then return WrapCaption("No Key Bound", data), false end
	return "", false
end

local function KeyCaptionColor(isKey)
	if isKey then return 1, 1, 1 end
	local c = GRAY_FONT_COLOR
	if c and c.GetRGB then return c:GetRGB() end
	return 0.5, 0.5, 0.5
end

-- The host frame's copy (TBC Anniversary's alerts; the test, Show All and preview
-- on both clients): directly under the totem's name, or under what is shown.
function SP:ReactiveHostKeyCaption(frame, totemId)
	local text, isKey = self:ReactiveKeyCaption(totemId)
	local fs = frame.keyText
	if text == "" then
		if fs then fs:SetText(""); fs:Hide() end
		return
	end
	if not fs then
		fs = frame:CreateFontString(nil, "OVERLAY")
		fs:SetShadowColor(0, 0, 0, 1)
		fs:SetShadowOffset(1, -1)
		fs:SetJustifyH("CENTER")
		frame.keyText = fs
	end
	SP:SetSPFont(fs, "alerts", (R(totemId, "fontSize") or 14) - 2, R(totemId, "fontOutline") and "OUTLINE" or "")
	fs:ClearAllPoints()
	if R(totemId, "showTotemName") then
		fs:SetPoint("TOP", frame.totemText, "BOTTOM", 0, -2)
	elseif R(totemId, "showDebuffName") then
		fs:SetPoint("TOP", frame.debuffText, "BOTTOM", 0, -2)
	else
		fs:SetPoint("TOP", frame, "BOTTOM", 0, -4)
	end
	fs:SetTextColor(KeyCaptionColor(isKey))
	fs:SetText(text)
	fs:SetShown(not self:ReactiveEngineLive())
end

-- Work the keys out again (after the core's key scan, or a setting changed): the
-- host frames take the new text at once, the engine displays are rebuilt where
-- their caption changed (RebuildReactiveEngine waits for the end of a fight).
-- Nothing at all while Show Spell Keybind is off.
function SP:RefreshReactiveKeys()
	local sv = ShamanPower_ReactiveTotems
	if not (sv and self.ReactiveTotems) then return end
	local on = self:ReactiveAnyKeybind()   -- (any alert that shows its key: 3.0.8, each alert its own)
	if not on and not self.reactiveKeysShown then return end
	self.reactiveKeysShown = on or nil
	local changed = false
	for totemId, data in pairs(self.ReactiveTotems) do
		local words
		if on and R(totemId, "showSpellKeybind") and SPCompat.KnowsSpellID(data.totemSpellID) then
			words = KeyWords(ReactiveSpellKey(data)) or false
		end
		if reactiveKeyWords[totemId] ~= words then
			reactiveKeyWords[totemId] = words
			changed = true
		end
	end
	self:ReactiveKeyEventsOn(on)
	if not changed then return end
	self:RefreshReactiveKeyCaptions()
	-- the settings page lists the keys found (Reactive Totems > Spell Keybind)
	local reg = on and LibStub and LibStub("AceConfigRegistry-3.0", true)
	if reg then reg:NotifyChange("ShamanPower") end
end

-- The captions again (the keys changed, or When No Key Is Bound did): each host's
-- copy at once (hidden while the game draws the alerts), and the game-drawn alerts
-- rebuilt, which waits for the end of a fight. Only the captions: the general
-- appearance update would show the hosts' own art (background, border, names)
-- with nothing in it, in a fight on WoW: Forever, until the rebuild.
function SP:RefreshReactiveKeyCaptions()
	for totemId, frame in pairs(self.reactiveFrames) do self:ReactiveHostKeyCaption(frame, totemId) end
	if self.reactiveEngineBuilt then self:RebuildReactiveEngine() end
end

-- One alert's key now, in words (its menu's Key Now)
function SP:ReactiveKeyNow(totemId)
	local words = reactiveKeyWords[totemId]
	if words then return words end
	if words == false then return "No Key Bound" end
	local data = self.ReactiveTotems[totemId]
	if data and not SPCompat.KnowsSpellID(data.totemSpellID) then return "Not Learned Yet" end
	return "No Key Bound"
end

-- For the settings page and /spreactive status: what each alert's totem has now.
function SP:ReactiveKeyStatus(sep)
	local parts = {}
	for _, totemId in ipairs({ "fear", "poison", "disease" }) do
		local data = self.ReactiveTotems[totemId]
		local words = reactiveKeyWords[totemId]
		local shown
		if words then
			shown = words
		elseif words == false then
			shown = "no key bound"
		else
			shown = "not learned yet"
		end
		parts[#parts + 1] = (data and data.totemName or totemId) .. ": " .. shown
	end
	return table.concat(parts, sep or "   ")
end

-- The bar and binding events that can move a key, heard only while the feature
-- is on (the core hears them itself only while the bar buttons show keys).
-- Each one queues the core's coalesced key scan; the scan's hook below does the rest.
function SP:ReactiveKeyEventsOn(on)
	local f = self.reactiveKeyEvents
	if not f then
		if not on then return end
		f = CreateFrame("Frame")
		f:SetScript("OnEvent", function()
			if SP:IsOff() then return end
			if SP.QueueKeybindTextRefresh then SP:QueueKeybindTextRefresh() end
		end)
		self.reactiveKeyEvents = f
	end
	if on == (f.spOn or false) then return end
	f.spOn = on
	for _, event in ipairs({ "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "SPELLS_CHANGED" }) do
		if on then f:RegisterEvent(event) else f:UnregisterEvent(event) end
	end
end

-- Every key scan the core runs (logins, bindings, bars, Keybind Mode, Keybind Shown)
-- ends in UpdateButtonKeybindText: the keys are worked out again from its fresh scan.
if type(SP.UpdateButtonKeybindText) == "function" then
	hooksecurefunc(SP, "UpdateButtonKeybindText", function() SP:RefreshReactiveKeys() end)
end

-- ============================================================================
-- Debuff Detection
-- ============================================================================

function SP:IsKnownFearDebuff(debuffName, spellID)
	if not issecretvalue(spellID) and spellID and self.FearSpellIDSet[spellID] then return true end
	if issecretvalue(debuffName) or not debuffName then return false end
	return self.FearSpellNames[debuffName] or false
end

-- The scan's answer lives in tables made once and refilled (a scan used to make
-- two to five new tables). Callers read it straight away and keep only strings.
local SCAN_UNITS = { "player", "party1", "party2", "party3", "party4" }
local SCAN_NONE = {}   -- (read-only)
local scanFound = {}
local scanHit = { fear = {}, poison = {}, disease = {} }
local function Hit(kind, name, icon, unit)
	local h = scanHit[kind]
	h.debuffName, h.debuffIcon, h.unit = name, icon, unit
	return h
end

function SP:ScanForReactiveDebuffs()
	local sv = ShamanPower_ReactiveTotems
	if not sv or not sv.enabled then SP.reactiveAnyFound = false return SCAN_NONE end

	if sv.onlyInInstance then
		local inInstance, instanceType = IsInInstance()
		if not inInstance then SP.reactiveAnyFound = false return SCAN_NONE end
	end

	local found = scanFound
	found.fear, found.poison, found.disease = nil, nil, nil

	-- Scan player and party members only (totems are party-wide, not raid-wide)
	for _, unit in ipairs(SCAN_UNITS) do
		if UnitExists(unit) and not UnitIsDeadOrGhost(unit) then
			for i = 1, 40 do
				local name, icon, count, debuffType, _, _, _, _, _, spellID = UnitDebuff(unit, i)
				if issecretvalue(name) or issecretvalue(spellID) or issecretvalue(debuffType) then break end
				if not name then break end

				-- Fear/Charm
				if sv.trackFear and not found.fear then
					if debuffType == "Fear" or debuffType == "Charm" or debuffType == "Horrify"
						or self:IsKnownFearDebuff(name, spellID) then
						found.fear = Hit("fear", name, icon, unit)
					end
				end

				-- Poison
				if sv.trackPoison and not found.poison and debuffType == "Poison" then
					found.poison = Hit("poison", name, icon, unit)
				end

				-- Disease
				if sv.trackDisease and not found.disease and debuffType == "Disease" then
					found.disease = Hit("disease", name, icon, unit)
				end

				-- Early exit if we found all types
				if found.fear and found.poison and found.disease then
					SP.reactiveAnyFound = true
					return found
				end
			end
		end
	end

	SP.reactiveAnyFound = (found.fear or found.poison or found.disease) and true or false
	return found
end

-- ============================================================================
-- Display Updates
-- ============================================================================

-- Totem state by addon element (1 Earth, 2 Fire, 3 Water, 4 Air). The core's
-- resolver handles clients that fill slots in cast order; otherwise the fixed
-- slot map applies (WoW slot 1 is Fire, slot 2 is Earth).
local function ElementTotemInfo(element)
	if ShamanPower.GetElementTotemInfo then return ShamanPower:GetElementTotemInfo(element) end
	return GetTotemInfo(ShamanPower.ElementToSlot[element])
end

function SP:UpdateReactiveTotemDisplay()
	-- Skip updates during positioning mode
	if self.reactivePositioningMode then return end

	-- Setup-wizard preview: don't let live scans overwrite the sample data.
	if self.reactiveDemoActive then return end

	local sv = ShamanPower_ReactiveTotems
	if self:ReactiveEngineLive() then
		-- The engine draws the alerts (below). The host frames are anchors only,
		-- and the sound is the one thing left to the scan, while it can read.
		self:SetReactiveHostMode()
		self:ApplyReactiveEngineVisibility()
		if sv and sv.enabled and self:ReactiveAnyOpt("playSound") and not self:IsOff() and not (SPCompat and SPCompat.AurasUnreadable and SPCompat.AurasUnreadable()) then
			local found = self:ScanForReactiveDebuffs()
			for totemId, frame in pairs(self.reactiveFrames) do
				local hit = found[totemId]
				if hit and totemId == "fear" and hit.unit ~= "player" then hit = nil end   -- Tremor: you only, as drawn
				if hit then
					if not frame.soundPlayed and R(totemId, "playSound") then
						self:PlayReactiveSound(totemId)
						frame.soundPlayed = true
					end
				else
					frame.soundPlayed = nil
				end
			end
		end
		return
	end
	if not sv or not sv.enabled or self:IsOff() then
		-- Hide all frames
		for id, frame in pairs(self.reactiveFrames) do
			frame:Hide()
		end
		return
	end

	local found = self:ScanForReactiveDebuffs()

	-- Update each totem frame based on whether that debuff type is present
	for totemId, totemData in pairs(self.ReactiveTotems) do
		local frame = self.reactiveFrames[totemId]
		if not frame then
			frame = self:CreateReactiveTotemFrame(totemId)
		end

		local debuffData = found[totemId]

		-- Check if relevant totem is already active
		if debuffData and R(totemId, "hideWhenTotemActive") then
			local element = totemData.totemElement
			if element then
				local haveTotem, totemName = ElementTotemInfo(element)
				if not issecretvalue(haveTotem) and not issecretvalue(totemName) and haveTotem
					and SPCompat.TotemNameMatches(totemName, totemData.totemSpellID, totemData.totemName) then
					debuffData = nil
				end
			end
		end

		if debuffData then
			-- Show unit name and debuff name (the text only rewritten when it changes)
			local unitName = UnitName(debuffData.unit) or debuffData.unit
			if frame.currentDebuffName ~= debuffData.debuffName or frame.currentUnit ~= debuffData.unit
				or frame.currentUnitName ~= unitName then
				if debuffData.unit == "player" then
					frame.debuffText:SetText(debuffData.debuffName)
				else
					frame.debuffText:SetText(unitName .. ": " .. debuffData.debuffName)
				end
			end
			frame.currentDebuffName = debuffData.debuffName
			frame.currentUnit = debuffData.unit
			frame.currentUnitName = unitName

			-- Glow
			if R(totemId, "showGlow") then
				frame.glow:Show()
				frame.glowAnim:Play()
			else
				frame.glow:Hide()
				frame.glowAnim:Stop()
			end

			-- Sound (only once per debuff application)
			if R(totemId, "playSound") and not frame.soundPlayed then
				self:PlayReactiveSound(totemId)
				frame.soundPlayed = true
			end

			frame:Show()
		else
			-- Hide this totem's frame
			frame.glowAnim:Stop()
			frame.glow:Hide()
			frame.currentDebuffName = nil
			frame.soundPlayed = nil
			frame:Hide()
		end
	end
end

-- ============================================================================
-- Engine-drawn alerts (secrets regime: Forever / retail)
-- ============================================================================
-- In combat the scan above reads nothing (party debuffs are blocked), which is
-- the only time a cleansing call matters. An AuraContainer bound to each unit
-- (player, party1-4) shows its own copy of the alert art whenever that unit
-- carries a matching debuff and hides it the moment the debuff is gone, in
-- combat, with no reads: poison and disease by dispel type (a filter the
-- client does not tie to spell identity), fear by the client's CROWD_CONTROL
-- class. That class covers every crowd-control effect and the client offers
-- no fear-only filter, so the Tremor alert is built for you only and shown only
-- while your loss-of-control list says fear, charm or sleep (another player's is
-- secret, so their roots and stuns would read as fears). The debuff's own icon and time left are painted by the engine;
-- the unit's name is static text set when the display is built (party names
-- are public out of combat). The sound cannot come from the engine (a sound
-- registration is per spell ID), so it plays only while the scan can read.
-- Built out of combat only; a rebuild asked for in a fight waits for regen.
SP.reactiveEngine = {}     -- [totemId][unitIndex] = { container = frame, key = string }
local reactivePending = false
local REACTIVE_UNITS = { "player", "party1", "party2", "party3", "party4" }
local REACTIVE_TRACK = { fear = "trackFear", poison = "trackPoison", disease = "trackDisease" }

local function ReactiveEngineAvailable()
	return SPCompat ~= nil and SPCompat.secretsRegime == true and C_AddOns ~= nil and C_AddOns.LoadAddOn ~= nil
end

-- true while the engine's displays are the live alerts
function SP:ReactiveEngineLive()
	return self.reactiveEngineBuilt == true and not self.reactivePositioningMode and not self.reactiveDemoActive
		and not self.reactiveTestActive
end

-- Everything about the art the display was built with; a change rebuilds it.
-- (each alert its own, 3.0.8)
local function ReactiveAppearanceKey(id)
	return table.concat({ tostring(R(id, "iconSize") or 64), tostring(R(id, "hideBackground") and 1 or 0), tostring(R(id, "hideBorder") and 1 or 0),
		tostring(R(id, "showGlow") ~= false and 1 or 0), tostring(R(id, "glowIntensity") or 0.8), tostring(R(id, "fontSize") or 14),
		tostring(R(id, "fontOutline") and 1 or 0), tostring(R(id, "showDebuffName") ~= false and 1 or 0), tostring(R(id, "showTotemName") ~= false and 1 or 0),
		tostring(R(id, "showDebuffIcon") and 1 or 0) }, "|")
end

local function ReactiveShouldShow(totemId)
	local sv = ShamanPower_ReactiveTotems
	if not sv or not sv.enabled or SP:IsOff() then return false end
	if SP.reactivePositioningMode or SP.reactiveDemoActive then return false end
	if sv[REACTIVE_TRACK[totemId]] == false then return false end
	if sv.onlyInInstance and not IsInInstance() then return false end
	if R(totemId, "hideWhenTotemActive") then
		local data = SP.ReactiveTotems[totemId]
		local haveTotem, totemName = ElementTotemInfo(data.totemElement)
		if not issecretvalue(haveTotem) and not issecretvalue(totemName) and haveTotem
			and SPCompat.TotemNameMatches(totemName, data.totemSpellID, data.totemName) then
			return false
		end
	end
	return true
end

-- Your Tremor alert: CROWD_CONTROL also covers roots, stuns and more, but for you the
-- game says what kind of control it is, in combat too (the player's loss-of-control
-- list is secret only for other units). It shows for fear, charm or sleep (and
-- horror, as the scan counts it); anything unreadable shows it, as before.
local TREMOR_LOC_TYPES = { FEAR = true, FEAR_MECHANIC = true, CHARM = true, POSSESS = true }
local function PlayerTremorBreakable()
	local L = C_LossOfControl
	if not (L and L.GetActiveLossOfControlDataCount and L.GetActiveLossOfControlData) then return true end
	local n = L.GetActiveLossOfControlDataCount()
	if issecretvalue(n) or type(n) ~= "number" then return true end
	local sleep, horror = _G.LOSS_OF_CONTROL_DISPLAY_SLEEP, _G.LOSS_OF_CONTROL_DISPLAY_HORROR
	for i = 1, n do
		local d = L.GetActiveLossOfControlData(i)
		if d then
			local t, text = d.locType, d.displayText
			if issecretvalue(t) or issecretvalue(text) then return true end
			if TREMOR_LOC_TYPES[t] or (text ~= nil and (text == sleep or text == horror)) then return true end
		end
	end
	return false
end

function SP:ApplyReactiveEngineVisibility()
	if not self.reactiveEngineBuilt then return end
	for totemId, list in pairs(self.reactiveEngine) do
		local show = ReactiveShouldShow(totemId)
		for i, slot in pairs(list) do
			local c = slot.container
			local on = show
			if on and i == 1 and totemId == "fear" then on = PlayerTremorBreakable() end   -- slot 1 is you
			if c and c:IsShown() ~= on then c:SetShown(on) end
		end
	end
end

-- In engine mode the host frame is an anchor: its own art shows only for
-- positioning and the wizard demo; the engine's copies are the live alerts.
function SP:SetReactiveHostMode()
	if not self.reactiveEngineBuilt then return end
	local live = self:ReactiveEngineLive()
	for id, frame in pairs(self.reactiveFrames) do
		if live then
			frame.bg:Hide(); frame.icon:Hide(); frame.borderFrame:Hide()
			frame.glow:Hide(); frame.glowAnim:Stop()
			frame.debuffText:Hide(); frame.totemText:Hide()
			if frame.keyText then frame.keyText:Hide() end
			frame:EnableMouse(false)
			frame:SetAlpha(R(id, "opacity") or 1.0)
			frame:Show()
		elseif not frame.icon:IsShown() then
			frame.icon:Show()
			frame.bg:SetShown(not R(id, "hideBackground"))
			frame.borderFrame:SetShown(not R(id, "hideBorder"))
			frame.debuffText:SetShown(R(id, "showDebuffName") and true or false)
			frame.totemText:SetShown(R(id, "showTotemName") and true or false)
			if frame.keyText then frame.keyText:SetShown((frame.keyText:GetText() or "") ~= "") end
			frame:EnableMouse(true)
		end
	end
end

local reactiveLog = {}   -- one line per display built or refused, for /spreactive status

local function BuildReactiveContainer(totemId, unitIndex, host)
	local data = SP.ReactiveTotems[totemId]
	local unit = REACTIVE_UNITS[unitIndex]
	local ok, container = pcall(CreateFrame, "AuraContainer", nil, host, "CustomAuraContainerTemplate")
	if not ok or not container then
		reactiveLog[#reactiveLog + 1] = totemId .. "/" .. unit .. " create: " .. tostring(container)
		if SPCompat.Trace then SPCompat.Trace("REACTIVE container %s/%s create failed: %s", totemId, unit, tostring(container)) end
		return nil
	end
	container:SetAllPoints(host)
	container:SetFrameLevel(host:GetFrameLevel() + 5)
	local filter, options = "HARMFUL", {}
	if totemId == "fear" then
		filter = "HARMFUL|CROWD_CONTROL"
	elseif totemId == "poison" then
		options.candidateFilters = { includeDispelTypes = { Poison = true } }
	else
		options.candidateFilters = { includeDispelTypes = { Disease = true } }
	end
	-- decided now, drawn by the engine later
	local size = R(totemId, "iconSize") or 64
	local c = data.color
	local fontSize = R(totemId, "fontSize") or 14
	local outline = R(totemId, "fontOutline") and "OUTLINE" or ""
	local hideBackground, hideBorder, showGlow = R(totemId, "hideBackground"), R(totemId, "hideBorder"), R(totemId, "showGlow")
	local glowIntensity, showDebuffIcon = R(totemId, "glowIntensity"), R(totemId, "showDebuffIcon")
	local showDebuffName, showTotemName = R(totemId, "showDebuffName"), R(totemId, "showTotemName")
	local label = (unit == "player") and "You" or (UnitName(unit) or unit)
	local lr, lg, lb = c.r, c.g, c.b
	local _, class = UnitClass(unit)
	if class and RAID_CLASS_COLORS[class] then
		lr, lg, lb = RAID_CLASS_COLORS[class].r, RAID_CLASS_COLORS[class].g, RAID_CLASS_COLORS[class].b
	end
	local caption, captionIsKey = SP:ReactiveKeyCaption(totemId)   -- Show Spell Keybind ("" = none)
	local kr, kg, kb = KeyCaptionColor(captionIsKey)
	options.initializeFrame = function(button)
		button:ClearAllPoints()
		button:SetAllPoints(host)
		if button.SetMouseClickEnabled then pcall(button.SetMouseClickEnabled, button, false) end
		if button.SetMouseMotionEnabled then pcall(button.SetMouseMotionEnabled, button, false) end
		if not hideBackground then
			local bg = button:CreateTexture(nil, "BACKGROUND")
			bg:SetAllPoints(button)
			bg:SetColorTexture(0, 0, 0, 0.6)
		end
		local icon = button:CreateTexture(nil, "ARTWORK")
		icon:SetPoint("TOPLEFT", 3, -3)
		icon:SetPoint("BOTTOMRIGHT", -3, 3)
		icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		icon:SetTexture(data.icon)
		if not hideBorder then
			local border = CreateFrame("Frame", nil, button, "BackdropTemplate")
			border:SetPoint("TOPLEFT", -2, 2)
			border:SetPoint("BOTTOMRIGHT", 2, -2)
			border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
			border:SetBackdropBorderColor(c.r, c.g, c.b, 1)
		end
		if showGlow ~= false then
			local glow = button:CreateTexture(nil, "OVERLAY", nil, 1)
			glow:SetPoint("TOPLEFT", -12, 12)
			glow:SetPoint("BOTTOMRIGHT", 12, -12)
			glow:SetTexture("Interface\\SpellActivationOverlay\\IconAlert")
			glow:SetTexCoord(0.00781250, 0.50781250, 0.27734375, 0.52734375)
			if SP.ShapeGlow then SP:ShapeGlow(glow, "alert") end   -- Glow Shape
			glow:SetBlendMode("ADD")
			glow:SetVertexColor(c.r, c.g, c.b)
			glow:SetAlpha(0.2)
			local ag = glow:CreateAnimationGroup()
			ag:SetLooping("REPEAT")
			local a1 = ag:CreateAnimation("Alpha"); a1:SetFromAlpha(0.2); a1:SetToAlpha(glowIntensity or 0.8); a1:SetDuration(0.4); a1:SetOrder(1)
			local a2 = ag:CreateAnimation("Alpha"); a2:SetFromAlpha(glowIntensity or 0.8); a2:SetToAlpha(0.2); a2:SetDuration(0.4); a2:SetOrder(2)
			ag:Play()
		end
		-- the debuff itself: its icon as a badge hanging off the corner, painted
		-- by the engine; a dark edge keeps it from reading as a copy of the totem.
		-- Opt-in: off, the badge is still registered (the engine wants an icon
		-- region) but stays invisible.
		local badge = CreateFrame("Frame", nil, button)
		if not showDebuffIcon then badge:SetAlpha(0) end
		local dsize = math.floor(size * 0.4)
		badge:SetSize(dsize, dsize)
		badge:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 6, -6)
		badge:SetFrameLevel(button:GetFrameLevel() + 3)
		local edge = badge:CreateTexture(nil, "BACKGROUND")
		edge:SetPoint("TOPLEFT", -2, 2)
		edge:SetPoint("BOTTOMRIGHT", 2, -2)
		edge:SetColorTexture(0, 0, 0, 1)
		local debuff = badge:CreateTexture(nil, "ARTWORK")
		debuff:SetAllPoints(badge)
		debuff:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		pcall(button.SetIcon, button, debuff)
		-- who and how long: one row per unit, so several alerts read as a list
		local carrier = CreateFrame("Frame", nil, button)
		carrier:SetAllPoints(button)
		if showDebuffName ~= false then
			local who = carrier:CreateFontString(nil, "OVERLAY")
			SP:SetSPFont(who, "alerts", fontSize, outline)
			SP:SPFontGameOwned(who)   -- (on the game's button: a font change waits out fights and hidden auras)
			who:SetPoint("TOP", button, "BOTTOM", 0, -4 - (unitIndex - 1) * (fontSize + 2))
			who:SetTextColor(lr, lg, lb)
			who:SetShadowColor(0, 0, 0, 1)
			who:SetShadowOffset(1, -1)
			who:SetText(label)
			local left = carrier:CreateFontString(nil, "OVERLAY")
			SP:SetSPFont(left, "alerts", fontSize, outline)
			SP:SPFontGameOwned(left)
			left:SetPoint("LEFT", who, "RIGHT", 4, 0)
			left:SetTextColor(1, 1, 1)
			left:SetShadowColor(0, 0, 0, 1)
			left:SetShadowOffset(1, -1)
			pcall(button.SetDurationText, button, left, {})
		end
		-- the key that casts this totem (Show Spell Keybind), directly under its
		-- name: the name moves up to make room. Plain text, set now.
		local keyLine
		if caption ~= "" then
			keyLine = carrier:CreateFontString(nil, "OVERLAY")
			SP:SetSPFont(keyLine, "alerts", fontSize - 2, outline)
			SP:SPFontGameOwned(keyLine)
			keyLine:SetPoint("BOTTOM", button, "TOP", 0, 3)
			keyLine:SetJustifyH("CENTER")
			keyLine:SetTextColor(kr, kg, kb)
			keyLine:SetShadowColor(0, 0, 0, 1)
			keyLine:SetShadowOffset(1, -1)
			keyLine:SetText(caption)
		end
		if showTotemName ~= false then
			local totem = carrier:CreateFontString(nil, "OVERLAY")
			SP:SetSPFont(totem, "alerts", fontSize - 2, outline)
			SP:SPFontGameOwned(totem)
			if keyLine then
				totem:SetPoint("BOTTOM", keyLine, "TOP", 0, 2)
			else
				totem:SetPoint("BOTTOM", button, "TOP", 0, 3)
			end
			totem:SetText(data.totemName)
			totem:SetTextColor(1, 0.82, 0)
			totem:SetShadowColor(0, 0, 0, 1)
			totem:SetShadowOffset(1, -1)
		end
	end
	local okAdd, err = pcall(container.AddAuraSlot, container, "alert", filter, options)
	if not okAdd then
		reactiveLog[#reactiveLog + 1] = totemId .. "/" .. unit .. " slot: " .. tostring(err)
		if SPCompat.Trace then SPCompat.Trace("REACTIVE AddAuraSlot %s/%s failed: %s", totemId, unit, tostring(err)) end
		container:Hide()
		return nil
	end
	local okU, errU = pcall(container.SetUnit, container, unit)
	local okE, errE = pcall(container.SetEnabled, container, true)
	local okA, errA = pcall(container.UpdateAllAuras, container)
	reactiveLog[#reactiveLog + 1] = ("%s/%s ok (unit %s, enable %s, update %s)"):format(totemId, unit,
		okU and "ok" or tostring(errU), okE and "ok" or tostring(errE), okA and "ok" or tostring(errA))
	container:Hide()   -- ApplyReactiveEngineVisibility decides
	return container
end

-- /spreactive status: what the engine displays are doing, for testing on the beta.
function SP:ReactiveEngineReport()
	local sv = ShamanPower_ReactiveTotems
	self:Print(("Reactive engine: available=%s built=%s live=%s combat=%s enabled=%s instanceOnly=%s hideWhenTotem=%s"):format(
		tostring(ReactiveEngineAvailable()), tostring(self.reactiveEngineBuilt), tostring(self:ReactiveEngineLive()),
		tostring(InCombatLockdown()), tostring(sv and sv.enabled), tostring(sv and sv.onlyInInstance), tostring(sv and sv.hideWhenTotemActive)))
	self:Print(("  look: size=%s glow=%s debuffName=%s totemName=%s font=%s border=%s background=%s"):format(
		tostring(sv and sv.iconSize), tostring(sv and sv.showGlow), tostring(sv and sv.showDebuffName), tostring(sv and sv.showTotemName),
		tostring(sv and sv.fontSize), tostring(not (sv and sv.hideBorder)), tostring(not (sv and sv.hideBackground))))
	if sv and sv.showSpellKeybind then
		self:Print(("  keys (%s): %s"):format(sv.noKeyText == "show" and "No Key Bound shown" or "nothing when unbound", self:ReactiveKeyStatus()))
	end
	for totemId in pairs(self.ReactiveTotems) do
		local host = self.reactiveFrames[totemId]
		local parts = {}
		for i, unit in ipairs(REACTIVE_UNITS) do
			local slot = self.reactiveEngine[totemId] and self.reactiveEngine[totemId][i]
			local c = slot and slot.container
			parts[#parts + 1] = unit .. "=" .. (c and (c:IsShown() and "shown" or "hidden") or "-")
		end
		self:Print(("  %s: shouldShow=%s host=%s track=%s  %s"):format(totemId, tostring(ReactiveShouldShow(totemId)),
			host and (host:IsShown() and "shown" or "hidden") or "none", tostring(sv and sv[REACTIVE_TRACK[totemId]]), table.concat(parts, " ")))
	end
	self:Print("  built: " .. (#reactiveLog > 0 and table.concat(reactiveLog, "; ") or "(nothing built yet)"))
end

-- Build, or rebuild where a unit's name / class or the art changed. Cheap when
-- nothing changed (one key per display), so options and roster code call it freely.
function SP:RebuildReactiveEngine()
	if not ReactiveEngineAvailable() then return end
	if self:IsOff() then return end   -- ShamanPower switched off: built when it comes back on
	if InCombatLockdown() then reactivePending = true return end
	reactivePending = false
	pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
	local built = false
	for totemId in pairs(self.ReactiveTotems) do
		local host = self.reactiveFrames[totemId] or self:CreateReactiveTotemFrame(totemId)
		local look = ReactiveAppearanceKey(totemId)
		if host then
			self.reactiveEngine[totemId] = self.reactiveEngine[totemId] or {}
			local list = self.reactiveEngine[totemId]
			local caption = self:ReactiveKeyCaption(totemId)   -- its key changed: this totem's displays are built again
			for i, unit in ipairs(REACTIVE_UNITS) do
				local exists = UnitExists(unit)
				local _, class = UnitClass(unit)
				local key = (exists and ((UnitName(unit) or "?") .. "/" .. tostring(class)) or "-") .. "|" .. look
				if caption ~= "" then key = key .. "|" .. caption end
				local slot = list[i]
				if not slot or slot.key ~= key then
					if slot and slot.container then
						pcall(slot.container.SetEnabled, slot.container, false)
						slot.container:Hide()
					end
					local wanted = totemId ~= "fear" or i == 1   -- Tremor: you only (see above)
					list[i] = { container = exists and wanted and BuildReactiveContainer(totemId, i, host) or nil, key = key }
				end
				if list[i].container then built = true end
			end
		end
	end
	self.reactiveEngineBuilt = built or nil
	self:SetReactiveHostMode()
	self:ApplyReactiveEngineVisibility()
end

function SP:ReactiveEngineRegen()
	if reactivePending then self:RebuildReactiveEngine() end
end

-- ============================================================================
-- Event Handling
-- ============================================================================

function SP:SetupReactiveTotemsEvents()
	if self.reactiveEventsSetup then return end
	self.reactiveEventsSetup = true

	local eventFrame = CreateFrame("Frame", "ShamanPowerReactiveEventFrame", UIParent)
	if SPCompat and SPCompat.StressRegister then SPCompat.StressRegister(eventFrame, "Reactive Totems") end
	-- UNIT_AURA for player + party1-4 only (totems are party-wide): the game filters,
	-- so a raid's other members and nameplates never reach the handler. Two units
	-- per frame, the count every client accepts. Old clients: all units, filtered below.
	local auraFrames = {}
	if eventFrame.RegisterUnitEvent then
		for _, units in ipairs({ { "player", "party1" }, { "party2", "party3" }, { "party4" } }) do
			local f = CreateFrame("Frame")
			-- same row as eventFrame: the stress baseline counted UNIT_AURA there
			if SPCompat and SPCompat.StressRegister then SPCompat.StressRegister(f, "Reactive Totems") end
			f:RegisterUnitEvent("UNIT_AURA", units[1], units[2])
			auraFrames[#auraFrames + 1] = f
		end
	else
		eventFrame:RegisterEvent("UNIT_AURA")
	end
	eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
	eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
	eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
	eventFrame:RegisterEvent("PLAYER_TOTEM_UPDATE")
	eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")   -- engine displays rebuilt after a fight if asked for in one
	-- your Tremor alert follows your loss-of-control list (PlayerTremorBreakable)
	if SPCompat and SPCompat.secretsRegime and C_LossOfControl and eventFrame.RegisterUnitEvent then
		local loc = CreateFrame("Frame")
		loc:RegisterUnitEvent("LOSS_OF_CONTROL_ADDED", "player")
		loc:RegisterUnitEvent("LOSS_OF_CONTROL_UPDATE", "player")
		loc:RegisterEvent("PLAYER_CONTROL_GAINED")
		loc:SetScript("OnEvent", function() if SP.reactiveEngineBuilt then SP:ApplyReactiveEngineVisibility() end end)
	end

	-- Throttle updates to max 20 per second (0.05s between updates)
	local lastUpdate = 0
	local pendingUpdate = false

	local function DoUpdate()
		pendingUpdate = false
		SP:UpdateReactiveTotemDisplay()
	end

	local function RequestUpdate()
		local now = GetTime()
		if now - lastUpdate >= 0.05 then
			lastUpdate = now
			DoUpdate()
		elseif not pendingUpdate then
			pendingUpdate = true
			C_Timer.After(0.05, DoUpdate)
		end
	end

	-- An aura change can change an answer only if it ADDS a harmful aura (a new
	-- fear, poison or disease), or REMOVES something while an alert is up (maybe
	-- that debuff ending). Buffs coming, going and refreshing - most of a party's
	-- aura traffic - and any aura's time or stacks changing skip the scan. A full
	-- update, a client with no update info, or contents the game hides: scan as
	-- always. Nothing hidden is ever tested.
	local secret = issecretvalue or function() return false end
	local function AuraChangeMatters(info)
		if not info or secret(info) or secret(info.isFullUpdate) or info.isFullUpdate then return true end
		local added = info.addedAuras
		if secret(added) then return true end
		if added then
			for i = 1, #added do
				local a = added[i]
				if secret(a) then return true end
				local harmful = a.isHarmful
				if secret(harmful) or harmful ~= false then return true end   -- (unknown counts as harmful)
			end
		end
		local removed = info.removedAuraInstanceIDs
		if secret(removed) then return true end
		if removed and SP.reactiveAnyFound ~= false then
			if #removed > 0 then return true end
		end
		return false
	end

	local function OnPartyAura(_, _, _, info)
		if SP:IsOff() then return end   -- ShamanPower switched off
		local sv = ShamanPower_ReactiveTotems
		if not sv or not sv.enabled then return end   -- switching it on updates at once
		-- engine mode: aura changes are the engine's business; the scan only serves the sound
		if SP:ReactiveEngineLive() and not SP:ReactiveAnyOpt("playSound") then return end
		if not AuraChangeMatters(info) then return end
		RequestUpdate()
	end
	-- the filtered frames only ever hear player and party1-4 (whatever token the
	-- game names them by), so they need no token check
	for _, f in ipairs(auraFrames) do f:SetScript("OnEvent", OnPartyAura) end

	-- A raid or battleground forming fires dozens of GROUP_ROSTER_UPDATEs, and
	-- every slot that changed builds new engine displays: rebuild once, 0.3 s
	-- after the last one. One timer at a time: when it fires with newer events
	-- behind it, it waits again for the rest of their 0.3 s (a storm that never
	-- pauses still rebuilds every 5 s).
	local rebuildQueued, rebuildFirst, rebuildLast = false, 0, 0
	local function RebuildSettled()
		local now = GetTime()
		local wait = rebuildLast + 0.3 - now
		if wait > 0.01 and now - rebuildFirst < 5 then C_Timer.After(wait, RebuildSettled) return end
		rebuildQueued = false
		SP:RebuildReactiveEngine()
		RequestUpdate()
	end

	local function OnReactiveEvent(self, event, unit)
		-- ShamanPower switched off: nothing to scan or build (the switch-on handler catches up)
		if SP:IsOff() then return end
		if event == "UNIT_AURA" then
			-- Unfiltered fallback: only player and party units (totems are party-wide only)
			if unit == "player" or unit == "party1" or unit == "party2" or unit == "party3" or unit == "party4" then
				OnPartyAura()
			end
		elseif event == "PLAYER_REGEN_ENABLED" then
			SP:ReactiveEngineRegen()
		elseif event == "PLAYER_ENTERING_WORLD" or event == "GROUP_ROSTER_UPDATE"
			or event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_TOTEM_UPDATE" then
			if event ~= "PLAYER_TOTEM_UPDATE" and ReactiveEngineAvailable() then   -- names / classes may have changed
				rebuildLast = GetTime()
				if not rebuildQueued then
					rebuildQueued, rebuildFirst = true, rebuildLast
					C_Timer.After(0.3, RebuildSettled)
				end
			end
			RequestUpdate()
		end
	end
	eventFrame:SetScript("OnEvent", OnReactiveEvent)

	self.reactiveEventFrame = eventFrame
end

-- ============================================================================
-- Configuration UI
-- ============================================================================

-- The module's old Blizzard-template configuration window is retired: every
-- setting it held is on the Reactive Totems page of the settings window, with
-- the Test / Show All / Reset actions. /spreactive and the old entry points land
-- on that page.
function SP:ShowReactiveTotemsConfig()
	self:OpenConfigWindow({ "fluffy", "reactivetotems_section" })
end

-- Test all alerts
function SP:TestReactiveAlerts()
	self.reactiveTestActive = true
	self:SetReactiveHostMode()
	self:ApplyReactiveEngineVisibility()

	for totemId, totemData in pairs(self.ReactiveTotems) do
		local frame = self.reactiveFrames[totemId]
		if not frame then
			frame = self:CreateReactiveTotemFrame(totemId)
		end

		frame.debuffText:SetText("Test " .. totemData.name)
		frame.currentDebuffName = "Test " .. totemData.name

		if R(totemId, "showGlow") then
			frame.glow:Show()
			frame.glowAnim:Play()
		end

		frame:Show()
	end

	-- each alert's own sound (3.0.8), one after another; the same sound only once (as before:
	-- one sound while they all share it)
	local played, n = {}, 0
	for _, id in ipairs({ "fear", "poison", "disease" }) do
		if R(id, "playSound") then
			local key = tostring(R(id, "soundName") or "Raid Warning") .. "|" .. tostring(R(id, "soundVolume"))
			if not played[key] then
				played[key] = true
				if n == 0 then
					self:PlayReactiveSound(id)
				else
					C_Timer.After(n * 0.7, function() SP:PlayReactiveSound(id) end)
				end
				n = n + 1
			end
		end
	end

	-- Hide after 3 seconds
	C_Timer.After(3, function()
		for totemId, frame in pairs(SP.reactiveFrames) do
			frame.glowAnim:Stop()
			frame.glow:Hide()
			frame:Hide()
		end
		SP.reactiveTestActive = nil
		SP:SetReactiveHostMode()
		SP:ApplyReactiveEngineVisibility()
	end)
end

-- Show all frames for positioning (disables click-to-cast so user can drag freely)
function SP:ShowAllReactiveFrames()
	self.reactivePositioningMode = true
	self:SetReactiveHostMode()
	self:ApplyReactiveEngineVisibility()

	for totemId, totemData in pairs(self.ReactiveTotems) do
		local frame = self.reactiveFrames[totemId]
		if not frame then
			frame = self:CreateReactiveTotemFrame(totemId)
		end

		-- Disable click-to-cast during positioning
		frame:SetAttribute("type1", nil)
		frame:SetAttribute("spell1", nil)

		frame.debuffText:SetText(totemData.name)
		frame.glow:Hide()
		frame.glowAnim:Stop()
		frame:Show()
	end

	SP:Print("Positioning mode: ALT+drag the alerts, then press Hide All on the Reactive Totems settings page (or /spreactive hide).")
end

-- Hide all frames and restore click-to-cast
function SP:HideAllReactiveFrames()
	local sv = ShamanPower_ReactiveTotems
	self.reactivePositioningMode = false
	if self.SettingsTestDone then self:SettingsTestDone() end   -- back to the settings page that started positioning

	for totemId, frame in pairs(self.reactiveFrames) do
		frame:Hide()

		-- Restore click-to-cast if enabled
		if sv.clickToCast then
			frame:SetAttribute("type1", "spell")
			frame:SetAttribute("spell1", SPCompat.SpellName(frame.totemData.totemSpellID) or frame.totemData.totemSpellID)
		end
	end

	self:SetReactiveHostMode()
	self:ApplyReactiveEngineVisibility()
	SP:Print("Finished moving Reactive Totems.")
end

-- Reset positions
function SP:ResetReactivePositions()
	local sv = ShamanPower_ReactiveTotems

	for totemId, totemData in pairs(self.ReactiveTotems) do
		sv.positions[totemId] = {
			point = totemData.defaultPos.point,
			x = totemData.defaultPos.x,
			y = totemData.defaultPos.y
		}

		local frame = self.reactiveFrames[totemId]
		if frame then
			frame:ClearAllPoints()
			frame:SetPoint(totemData.defaultPos.point, UIParent, totemData.defaultPos.point,
				totemData.defaultPos.x, totemData.defaultPos.y)
		end
	end

	SP:Print("Reactive Totems positions reset to defaults")
end

-- ============================================================================
-- Slash Commands
-- ============================================================================

SLASH_SPREACTIVE1 = "/spreactive"
SLASH_SPREACTIVE2 = "/reactivetotem"
SlashCmdList["SPREACTIVE"] = function(msg)
	msg = msg and msg:lower():trim() or ""

	if msg == "toggle" then
		ShamanPower_ReactiveTotems.enabled = not ShamanPower_ReactiveTotems.enabled
		SP:UpdateReactiveTotemDisplay()
		SP:Print("Reactive Totems " .. (ShamanPower_ReactiveTotems.enabled and "on" or "off"))
	elseif msg == "test" then
		SP:TestReactiveAlerts()
	elseif msg == "reset" then
		SP:ResetReactivePositions()
	elseif msg == "status" then
		SP:ReactiveEngineReport()
	elseif msg == "rebuild" then
		wipe(reactiveLog)
		for _, list in pairs(SP.reactiveEngine) do
			for _, slot in pairs(list) do slot.key = "" end   -- force every display to be built again
		end
		SP:RebuildReactiveEngine()
		SP:ReactiveEngineReport()
	elseif msg == "show" then
		SP:ShowAllReactiveFrames()
	elseif msg == "hide" then
		SP:HideAllReactiveFrames()
	else
		-- Open ShamanPower options to Look & Feel > Reactive Totems using AceConfigDialog
		if ShamanPowerConfig then
			ShamanPowerConfig:Open({ "fluffy", "reactivetotems_section" })
		else
			SP:Print("Type /sp to open ShamanPower settings, then go to Look & Feel > Reactive Totems")
		end
	end
end

-- ============================================================================
-- Bridge Functions (called by ShamanPowerOptions.lua)
-- ============================================================================

-- Called when enabled or tracking settings change
function SP:UpdateReactiveTotems()
	self:UpdateReactiveTotemDisplay()
end

-- Called when appearance settings change
function SP:UpdateReactiveTotemAppearance()
	self:UpdateReactiveFrameAppearance()
end

-- Called by Test All button in options
function SP:TestReactiveTotems()
	self:TestReactiveAlerts()
end

-- Called by Reset Positions button in options
function SP:ResetReactiveTotemPositions()
	self:ResetReactivePositions()
end

-- One alert back on its default spot (Unlock UI: that box's Reset)
function SP:ResetReactiveTotemPosition(frame)
	local sv = ShamanPower_ReactiveTotems
	for totemId, totemData in pairs(self.ReactiveTotems) do
		if self.reactiveFrames[totemId] == frame then
			local d = totemData.defaultPos
			sv.positions[totemId] = { point = d.point, x = d.x, y = d.y }
			frame:ClearAllPoints()
			frame:SetPoint(d.point, UIParent, d.point, d.x, d.y)
			return
		end
	end
	self:ResetReactivePositions()   -- (not one of its alerts: all of them, as before)
end

-- Called by Show All button in options (bridge function)
-- Note: ShowAllReactiveFrames is defined above, this just ensures consistent naming

-- Called by Hide All button in options (bridge function)
-- Note: HideAllReactiveFrames is defined above, this just ensures consistent naming

-- ============================================================================
-- Setup Wizard Preview (frame borrowed by ShamanPowerPreview.lua)
-- ============================================================================

-- Which reactive totem to showcase in the wizard preview (Tremor Totem).
local PREVIEW_TOTEM = "fear"

-- Fill the reactive totem frame with believable sample data for the wizard.
-- Reuses the same render the test/live paths use (debuffText + glow); only the
-- data is faked. Unlike TestReactiveAlerts this plays no sound and never
-- auto-expires, and it does NOT call frame:Show() itself -- the preview harness
-- shows the frame, so the frame's real (hidden) state is preserved for a clean
-- restore. reactiveDemoActive guards UpdateReactiveTotemDisplay meanwhile.
function SP:ReactiveDemo(on)
	local sv = ShamanPower_ReactiveTotems
	self.reactiveFrames = self.reactiveFrames or {}
	for id in pairs(self.ReactiveTotems) do
		if not self.reactiveFrames[id] then self:CreateReactiveTotemFrame(id) end
	end

	-- The live alert's debuff badge is drawn by the game; the preview draws its own
	-- copy (same corner, same size, same dark edge) with a sample debuff icon.
	local DEMO_DEBUFF_ICON = {
		fear = "Interface\\Icons\\Ability_GolemThunderClap",    -- Intimidating Shout
		poison = "Interface\\Icons\\Ability_Rogue_DualWeild",   -- Deadly Poison
		disease = "Interface\\Icons\\Spell_Shadow_CallofBone",  -- Plague
	}
	local function demoBadge(frame, id)
		local b = frame.spDemoBadge
		if not b then
			b = CreateFrame("Frame", nil, frame)
			local edge = b:CreateTexture(nil, "BACKGROUND")
			edge:SetPoint("TOPLEFT", -2, 2); edge:SetPoint("BOTTOMRIGHT", 2, -2)
			edge:SetColorTexture(0, 0, 0, 1)
			b.icon = b:CreateTexture(nil, "ARTWORK")
			b.icon:SetAllPoints(b); b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			frame.spDemoBadge = b
		end
		local dsize = math.floor(frame:GetWidth() * 0.4)
		b:SetSize(dsize, dsize)
		b:ClearAllPoints(); b:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 6, -6)
		b:SetFrameLevel(frame:GetFrameLevel() + 6)
		b.icon:SetTexture(DEMO_DEBUFF_ICON[id])
		b:Show()
	end

	local function clearAll()
		for id, frame in pairs(self.reactiveFrames) do
			if frame.spDemoBadge then frame.spDemoBadge:Hide() end
			frame.glowAnim:Stop(); frame.glow:Hide()
			frame.debuffText:SetText(""); frame.currentDebuffName = nil; frame.soundPlayed = nil
			frame:Hide()
		end
	end

	if on then
		if self.reactiveDemoActive then
			self:UpdateReactiveFrameAppearance()   -- re-entrant: options changed
			return
		end
		self.reactiveDemoActive = true
		self:SetReactiveHostMode()
		self:ApplyReactiveEngineVisibility()
		self:UpdateReactiveFrameAppearance()

		-- A short raid scene, looped: each beat is { totem, "who: debuff", seconds }.
		local SCENE = {
			SPCompat and SPCompat.FOREVER   -- on WoW: Forever the Fear alert is yours only
				and { "fear", "You: Intimidating Shout", 4.0, story = "You got feared - drop Tremor Totem" }
				or { "fear", "Tank: Intimidating Shout", 4.0, story = "The tank got feared - drop Tremor Totem" },
			{ nil,       nil,                        1.5, story = "Tremor is down, fear broken" },
			{ "poison",  "Rogue: Deadly Poison",     4.0, story = "Rogue is poisoned - drop Poison Cleansing Totem" },
			{ nil,       nil,                        1.5, story = "Cleansed" },
			{ "disease", "Priest: Plague",           4.0, story = "Priest is diseased - drop Disease Cleansing Totem" },
			{ nil,       nil,                        2.0, story = "All clear" },
		}
		local track = { fear = "trackFear", poison = "trackPoison", disease = "trackDisease" }
		local beat, left = 0, 0
		local function apply(b)
			clearAll()
			local id, text = b[1], b[2]
			self.reactiveDemoStatus = b.story
			if id and sv[track[id]] ~= false then
				local frame = self.reactiveFrames[id]
				frame.debuffText:SetText(text); frame.currentDebuffName = text
				if R(id, "showGlow") ~= false then frame.glow:Show(); frame.glowAnim:Play() end
				if R(id, "showDebuffIcon") then demoBadge(frame, id) end
				if R(id, "playSound") then self:PlayReactiveSound(id) end
				frame:Show()
			elseif id then
				self.reactiveDemoStatus = b.story .. "  (tracking for this debuff is off)"
			end
		end
		if self.reactiveDemoTicker then self.reactiveDemoTicker:Cancel() end
		self.reactiveDemoTicker = C_Timer.NewTicker(0.25, function()
			if not self.reactiveDemoActive then return end
			left = left - 0.25
			if left <= 0 then
				beat = (beat % #SCENE) + 1
				left = SCENE[beat][3]
				apply(SCENE[beat])
			end
		end)
	else
		self.reactiveDemoActive = false
		if self.reactiveDemoTicker then self.reactiveDemoTicker:Cancel(); self.reactiveDemoTicker = nil end
		self.reactiveDemoStatus = nil
		clearAll()
		-- Hand control back to the real scan (frames hide when no debuff).
		self:UpdateReactiveTotemDisplay()
	end
end

-- ============================================================================
-- Module Initialization
-- ============================================================================

function SP:InitializeReactiveTotems()
	self:InitReactiveTotems()
	self:CreateAllReactiveFrames()
	self:SetupReactiveTotemsEvents()
	-- Show Spell Keybind: the keys before the first build (the core's own scan
	-- after login comes later and updates them through its hook)
	if self:ReactiveAnyKeybind() and self.ScanActionBarKeybinds then self:ScanActionBarKeybinds() end
	self:RefreshReactiveKeys()
	self:RebuildReactiveEngine()
	self:UpdateReactiveTotemDisplay()
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self, event)
	if event == "PLAYER_LOGIN" then
		C_Timer.After(0.5, function()
			SP:InitializeReactiveTotems()
		end)
	end
end)

-- Enable ShamanPower switched (out of combat): off hides every alert; on builds
-- the engine displays (the group may have changed meanwhile) and scans again.
SP:OnOnOff(function(off)
	if not SP.reactiveEventsSetup then return end   -- not set up yet: login does it
	if not off then SP:RebuildReactiveEngine() end
	SP:UpdateReactiveTotemDisplay()
end)

-- ============================================================================
-- Theme changed (General > Themes): the colour tables are already rewritten;
-- repaint what was drawn with the old colours. Nothing runs unless an alert
-- colour actually moved.
-- ============================================================================

if SP.OnThemeChanged then
	local seen = {}   -- totemId -> the colour last painted
	for id, data in pairs(SP.ReactiveTotems) do
		local c = data.color
		seen[id] = { c.r, c.g, c.b }
	end
	-- WoW: Forever: the game-drawn alerts took their colours when they were
	-- built; rebuild them (RebuildReactiveEngine waits for the end of combat)
	local function rebuildEngine()
		local engine = SP.reactiveEngine
		if not (SP.reactiveEngineBuilt and engine) then return end
		for _, list in pairs(engine) do
			for _, slot in pairs(list) do slot.key = nil end
		end
		SP:RebuildReactiveEngine()
	end
	SP:OnThemeChanged(function()
		local moved = false
		for id, data in pairs(SP.ReactiveTotems) do
			local c, s = data.color, seen[id]
			if s and (s[1] ~= c.r or s[2] ~= c.g or s[3] ~= c.b) then
				s[1], s[2], s[3] = c.r, c.g, c.b
				moved = true
			end
		end
		if not moved then return end
		for _, frame in pairs(SP.reactiveFrames) do
			local c = frame.totemData and frame.totemData.color
			if c then
				frame.borderFrame:SetBackdropBorderColor(c.r, c.g, c.b, 1)
				frame.glow:SetVertexColor(c.r, c.g, c.b)
				frame.debuffText:SetTextColor(c.r, c.g, c.b)
			end
		end
		if SPCompat.FOREVER and SP.reactiveEngineBuilt and SP.ThemeRepaintSoon then
			SP:ThemeRepaintSoon("reactiveEngine", rebuildEngine)
		end
	end)
end

-- ============================================================================
-- Setup Wizard Preview Registration
-- ============================================================================

if ShamanPower.RegisterPreview then
	ShamanPower:RegisterPreview("reactive", {
		frames = {
			function() SP.reactiveFrames = SP.reactiveFrames or {}; return SP.reactiveFrames.fear or SP:CreateReactiveTotemFrame("fear") end,
			function() return SP.reactiveFrames.poison or SP:CreateReactiveTotemFrame("poison") end,
			function() return SP.reactiveFrames.disease or SP:CreateReactiveTotemFrame("disease") end,
		},
		demo = "SP:ReactiveDemo",
		pad = 24,
		pane = { overlap = true },   -- settings-window pane only: the scene lights one alert at a time, so one centred spot
	})
end
