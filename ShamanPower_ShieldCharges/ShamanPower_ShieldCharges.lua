-- ============================================================================
-- ShamanPower Shield Charge Display Module
-- Large on-screen numbers showing your shield charges and Earth Shield charges
-- ============================================================================

local SP = ShamanPower
local shieldKnown = {}   -- [1 Lightning, 2 Water] = does the player know it (cleared on SPELLS_CHANGED)
local UnitBuff = SPCompat and SPCompat.UnitBuff or UnitBuff   -- ShamanPower's own reader on Forever, never another addon's global
if not SP then return end
-- Only load for Shamans (the core keeps no-op stubs for everything this module provides)
if select(2, UnitClass("player")) ~= "SHAMAN" then return end

-- Mark module as loaded
SP.ShieldChargesLoaded = true

-- ============================================================================
-- Shield Charge Display (large on-screen numbers)
-- ============================================================================

SP.shieldChargeFrames = {}

-- Create or update the shield charge display frames
-- Earth Shield does not exist on every client (WoW: Forever has none): the
-- second number, its options and its preview stand down there.
local function earthShieldWanted(settings)
	if ShamanPower.ESTrackerUnavailable then return false end
	return settings.showEarthShield ~= false
end

-- The settings preview's Water Shield: a display only the live preview shows, so
-- Lightning and Water Shield are both there (the player's display shows whichever
-- shield is up). Never in the setup tour, never on screen outside the preview.
function SP:ShieldChargeWaterPreviewFrame()
	local f = self.shieldChargeWaterPreview
	if f then return f end
	f = CreateFrame("Frame", "ShamanPowerWaterShieldChargePreview", UIParent)
	f.spWhich, f.spKind = 2, "player"
	f:SetSize(60, 60)
	f:SetPoint("CENTER", UIParent, "CENTER", 0, -100)
	f:SetFrameStrata("MEDIUM")
	local text = f:CreateFontString(nil, "OVERLAY")
	SP:SetSPFont(text, "charges", 48, "OUTLINE")
	text:SetPoint("CENTER", f, "CENTER", 0, 0)
	text:SetTextColor(0.2, 0.6, 1.0)
	f.text = text
	f:EnableMouse(false)
	f.spDemoHidden = true   -- (the preview shows it only while the demo paints it)
	f:Hide()
	self.shieldChargeWaterPreview = f
	return f
end

-- One display per shield (3.0.8: each shield owns all its settings and its own
-- spot): [player] Lightning Shield (the frame name it always had), [water] Water
-- Shield, [earth] Earth Shield. Lightning and Water Shield are never up together:
-- only the one that is up shows (or, with none up, the last one you had).
local FRAME_DEF = {
	{ key = "player", name = "ShamanPowerPlayerShieldCharge", kind = "player", color = { 0.2, 0.6, 1.0 } },   -- Lightning Shield
	{ key = "water", name = "ShamanPowerWaterShieldCharge", kind = "player", color = { 0.2, 0.6, 1.0 } },     -- Water Shield
	{ key = "earth", name = "ShamanPowerEarthShieldCharge", kind = "earth", color = { 0.2, 0.8, 0.2 } },      -- Earth Shield
}
local shieldSpot   -- below: one shield's spot (x, y)
local function makeShieldFrame(which)
	local def = FRAME_DEF[which]
	local frame = CreateFrame("Frame", def.name, UIParent)
	frame.spWhich, frame.spKind = which, def.kind
	frame:SetSize(60, 60)
	local x, y = shieldSpot(which)
	frame:SetPoint("CENTER", UIParent, "CENTER", x, y)
	frame.spSpotX, frame.spSpotY = x, y
	frame:SetFrameStrata("MEDIUM")

	local text = frame:CreateFontString(nil, "OVERLAY")
	SP:SetSPFont(text, "charges", 48, "OUTLINE")
	text:SetPoint("CENTER", frame, "CENTER", 0, 0)
	text:SetTextColor(def.color[1], def.color[2], def.color[3])
	frame.text = text

	-- Make movable when unlocked; the drop saves this shield's own spot
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self)
		if not SP.opt.shieldChargeDisplay.locked then
			self:StartMoving()
		end
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local _, _, _, fx, fy = self:GetPoint()
		if SP.SetShieldSpot then SP:SetShieldSpot(self.spWhich, fx, fy) end
	end)

	frame:Hide()
	SP.shieldChargeFrames[def.key] = frame
	return frame
end

function SP:CreateShieldChargeDisplays()
	local settings = self.opt.shieldChargeDisplay
	if not settings then
		self:EnsureProfileTable("shieldChargeDisplay")
		settings = self.opt.shieldChargeDisplay
	end
	if self.ShieldMigrate then self:ShieldMigrate() end

	-- Lightning Shield, Water Shield and Earth Shield, each its own frame
	if not self.shieldChargeFrames.player then makeShieldFrame(1) end
	if not self.shieldChargeFrames.water then makeShieldFrame(2) end
	if not self.shieldChargeFrames.earth then makeShieldFrame(3) end

	-- Register shield charge updates with consolidated update system (10fps)
	if not self.updateSystem.subsystems["shieldCharge"] then
		-- What this display shows changes with the player's (or the Earth Shield target's)
		-- auras and with entering / leaving combat - in combat on a restricted client the
		-- engine draws the count by itself and this function only decides visibility. So it
		-- runs when one of those events asks, and once a second as a safety net, instead of
		-- ten times a second (measured with /spperf: the top idle cost, and 3 KB/s in combat).
		local idleTicks = 0
		self:RegisterUpdateSubsystem("shieldCharge", 0.1, function()
			if not SP._shieldWake then
				idleTicks = idleTicks + 1
				if idleTicks < 10 then return end
			end
			idleTicks = 0
			SP._shieldWake = nil
			SP:UpdateShieldChargeDisplays()
		end)
		local wake = CreateFrame("Frame")
		if SPCompat and SPCompat.StressRegister then SPCompat.StressRegister(wake, "Shield Charges") end
		for _, ev in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "SPELLS_CHANGED", "ADDON_LOADED" }) do
			pcall(wake.RegisterEvent, wake, ev)
		end
		-- your own auras through the game's unit filter: a raid's other 39 members
		-- and every nameplate no longer reach this handler
		if wake.RegisterUnitEvent then
			wake:RegisterUnitEvent("UNIT_AURA", "player")
		else
			wake:RegisterEvent("UNIT_AURA")
		end
		-- someone else's auras only matter while an Earth Shield is being tracked on
		-- them. The core already hears exactly those units through the game's unit
		-- filter (player, party1-4 and the Earth Shield carrier's raid token, see
		-- SetupUnitEventFilters) and updates the charges this display reads, so the
		-- display wakes after the core's own handler. A frame of its own here heard
		-- every raid member and nameplate. (Counted in the core's stress rows.)
		hooksecurefunc(ShamanPower, "UNIT_AURA", function(_, _, unit)
			if unit ~= "player" and ShamanPower.esTrackedTargetGUID then SP._shieldWake = true end
		end)
		wake:SetScript("OnEvent", function(_, ev, unit)
			if ev == "SPELLS_CHANGED" then shieldKnown[1], shieldKnown[2] = nil, nil end   -- (a shield learned: its display may come up)
			-- ShieldGoneHooks: the Cooldown Manager's viewers exist (its addon loaded, the world is up): bind
			if ev == "ADDON_LOADED" then
				if unit == "Blizzard_CooldownViewer" and SP.ShieldGoneBindQueue then SP:ShieldGoneBindQueue() end
				return
			end
			if ev == "PLAYER_ENTERING_WORLD" and SP.ShieldGoneBindQueue then C_Timer.After(1, function() SP:ShieldGoneBindQueue() end) end
			if ev == "UNIT_AURA" and unit ~= "player" and not ShamanPower.esTrackedTargetGUID then return end
			SP._shieldWake = true
		end)
	end
	-- Only enable if shield charge display is configured to show something (and ShamanPower is on)
	local showAny = (self:ShieldOpt("LS", "enabled") or self:ShieldOpt("WS", "enabled") or earthShieldWanted(settings)) and not self:IsOff()
	if showAny then
		self:EnableUpdateSubsystem("shieldCharge")
	else
		self:DisableUpdateSubsystem("shieldCharge")
	end

	self:UpdateShieldChargeDisplays()
end

-- Theme looks (General > Themes, ShamanPowerTheme.lua), spot
-- mod.shieldcharges-colors: full (your shield), esfull (Earth Shield), low,
-- last. On Standard every read is nil and today's colours below are used.
local THEME_SPOT = "mod.shieldcharges-colors"
local function ThemeRGB(role)
	if SP.ThemeColor then return SP:ThemeColor(THEME_SPOT, role) end
end

-- Get color based on charges remaining
function SP:GetShieldChargeColor(charges, maxCharges, isEarthShield)
	if isEarthShield then
		-- Earth Shield: 6 charges max, yellow at 3, red at 1-2
		if charges >= 4 then
			local r, g, b = ThemeRGB("esfull"); if r then return r, g, b end
			return 0.2, 0.8, 0.2  -- Green
		elseif charges >= 3 then
			local r, g, b = ThemeRGB("low"); if r then return r, g, b end
			return 1.0, 0.8, 0.0  -- Yellow
		else
			local r, g, b = ThemeRGB("last"); if r then return r, g, b end
			return 1.0, 0.2, 0.2  -- Red
		end
	else
		-- Lightning/Water Shield: 3-4 charges max, yellow at 2, red at 1
		if charges >= 3 then
			local r, g, b = ThemeRGB("full"); if r then return r, g, b end
			return 0.2, 0.6, 1.0  -- Blue (full)
		elseif charges == 2 then
			local r, g, b = ThemeRGB("low"); if r then return r, g, b end
			return 1.0, 0.8, 0.0  -- Yellow (medium)
		else
			local r, g, b = ThemeRGB("last"); if r then return r, g, b end
			return 1.0, 0.2, 0.2  -- Red (low)
		end
	end
end

-- Update the shield charge displays
-- ============================================================================
-- Restricted clients (retail rules): while auras are secret the charge numbers
-- are drawn by the engine. Each display frame gets an AuraContainer whose aura
-- button carries a FontString in the same font/size/position (white); the
-- container is shown only while restricted and the addon's own text is blank.
-- The Earth Shield container is pointed at the group token of the player who
-- carries your shield, and re-pointed whenever that changes.
-- ============================================================================
function SP:ShieldChargesRestricted()
	return SPCompat and SPCompat.secretsRegime and SPCompat.AnyRestrictionActive and SPCompat.AnyRestrictionActive() or false
end

local ES_SPELL_IDS = { 974, 32593, 32594, 383648 }   -- Earth Shield ranks; retail's AURA is 383648 (cast 974)

-- ============================================================================
-- Optional looks, all off by default (the plain number): the shield's icon
-- with the number on it (in the center, or smaller in the bottom-right corner)
-- and a segmented charge bar under it. The same parts are built twice - on the
-- display frame, drawn by the addon (out of combat, and always on clients
-- without secret auras), and on the engine's aura button, drawn by the game
-- while auras are secret - and placed by one function relative to a box that
-- covers the display frame exactly, so both pictures line up.
-- ============================================================================
local ICON_SIZE      = 48   -- the shield icon (square)
local NUMBER_SIZE    = 48   -- the plain number (the default look)
local NUMBER_ON_ICON = 34   -- the number centerd on the icon
local NUMBER_CORNER  = 20   -- the number in the icon's bottom-right corner
local NUMBER_BOTTOM  = 17   -- how far the plain number's digits reach below its center
local BAR_WIDTH, BAR_HEIGHT, BAR_GAP = 48, 7, 3   -- (a vertical bar: the same size, stood up)
local NUMBER_SIDE    = 16   -- how far the plain number's digits reach right of its center
local NUMBER_TOP     = 18   -- how far the plain number's digits reach above its center
local MAX_CHARGES = { player = 3, earth = 6 }
local NO_SETTINGS = {}
-- each shield's charge bar texture / gradient area (ShamanPowerTextures.lua)
local SHIELD_AREA = { "shieldchargesLS", "shieldchargesWS", "shieldchargesES" }
local shieldView   -- below: one shield's own settings (Lightning 1, Water 2, Earth 3)
-- The bar keeps the display's own color at every count: in combat the game
-- fills it and cannot recolor it by count, so out of combat does the same.
local SHIELD_COLOR = { player = { 0.2, 0.6, 1.0 }, earth = { 0.2, 0.8, 0.2 } }
-- Charge Colors (Shield Charges page and General > Themes): each shield's own
-- color for its charge bar and the orbs that take a tint; nil = today's color.
local CHARGE_COLOR_KEY = { "chargeColorLS", "chargeColorWS", "chargeColorES" }
local function customChargeColor(settings, which)
	local c = settings[CHARGE_COLOR_KEY[which or 1]]
	if type(c) == "table" then return c.r or 1, c.g or 1, c.b or 1 end
	return nil
end
-- a theme recolours these in place (the "full" colours) and puts today's back on Standard
if SP.ThemeBind then
	SP:ThemeBind(SHIELD_COLOR.player, THEME_SPOT, "full")
	SP:ThemeBind(SHIELD_COLOR.earth, THEME_SPOT, "esfull")
end
-- Shield Orbs (Charge Bar Look: Orbs): the charge bar's fill is a strip of one
-- orb per charge (Media/Textures/Orbs_*), so a bar filled to 2 of 3 shows two
-- whole orbs. Out of combat the addon sets the value; in combat on WoW: Forever
-- the game fills the same bar (SetApplicationBar): nothing hidden is read either
-- way. A strip is 4 (3 orbs) or 8 (6 orbs) orb-heights long; the empty slots are
-- the bar's backing, a strip of rings. The bar's texture belongs to this look
-- while it is on (spOwnTexture: Fonts & Textures leaves it alone).
local ORB_DIR = "Interface\\AddOns\\ShamanPower\\Media\\Textures\\"
local ORB_H = 14
local ORB_ICON = { "Orbs_Icon_Lightning_3", "Orbs_Icon_Water_3", "Orbs_Icon_Earth_6" }
-- Orb Color: By Shield (Lightning / Water / Earth Shield)
local ORB_SHIELD_COLOR = { { 0.55, 0.55, 1.0 }, { 0.25, 0.66, 0.96 }, { 0.36, 0.72, 0.21 } }
-- Each shield has its own look (Lightning / Water / Earth Shield Look, also on
-- General > Themes): "bar" (today's segmented bar) or an orb look. which: 1
-- Lightning Shield, 2 Water Shield, 3 Earth Shield (Anniversary only).
local LOOK_KEY = { "lookLS", "lookWS", "lookES" }
-- The Storm family: Miska's Shield Orbs aura, its additive PowerAuras layers baked
-- into one strip per shield (drawn with ADD blend, so it adds up the same), and the
-- Water / Earth looks built the same way; the middle orb a little lower (an arc),
-- cells 30 x 45 units. [look] = { Lightning, Water, Earth } strip (nil: not that shield's).
local STORM_LOOK = {
	storm  = { "Orbs_Storm_LS_3", "Orbs_Storm_WS_3", "Orbs_Storm_ES_6" },
	tide   = { nil, "Orbs_Tide_WS_3" },
	bubble = { nil, "Orbs_Bubble_WS_3" },
	foam   = { nil, "Orbs_Foam_WS_3" },
	stone  = { nil, nil, "Orbs_Stone_ES_6" },
	leaf   = { nil, nil, "Orbs_Leaf_ES_6" },
	spike  = { nil, nil, "Orbs_Spike_ES_6" },
}
local STORM_H, STORM_CELL = 45, 30
local function isStorm(look) return look ~= nil and STORM_LOOK[look] ~= nil end
-- the strip's size: the Storm family's big cells, but Bubble Orbs draw at the
-- Glowing Orbs' size, small and close together (the look the user picked)
local function stormSized(look) return isStorm(look) and look ~= "bubble" end
local function orbLength(kind, look)
	if stormSized(look) then return STORM_CELL * MAX_CHARGES[kind] end
	return ORB_H * ((MAX_CHARGES[kind] == 6) and 8 or 4)
end
local function orbThickness(look) return stormSized(look) and STORM_H or ORB_H end
-- The look of one shield's bar: an orb look, or nil for today's bar. The first
-- build had one look for all shields (barLook / orbLook): read until a shield is set.
local function orbLookOf(settings, which)
	which = which or 1
	if not settings.showChargeBar then return nil end
	local v = settings[LOOK_KEY[which]]
	if v == nil and settings.barLook == "orbs" then v = settings.orbLook or "glow" end
	if v == nil or v == "bar" then return nil end
	if STORM_LOOK[v] and not STORM_LOOK[v][which] then return "storm" end   -- a look this shield does not have
	return v
end
-- the Animated setting for a shield (Lightning / Water / Earth)
local ANIM_KEY = { "orbAnim", "orbAnimWS", "orbAnimES" }
-- everything about the orbs a built display depends on (a change rebuilds it)
-- (one shield's: each display draws only its own shield)
local function orbSig(settings, which)
	local a = orbLookOf(settings, which)
	local gen = SP.chargeStyleGen or 0   -- Charge Colors / Charge Bar Gradient changed
	if not a then return gen end
	return tostring(a) .. "|" .. tostring(settings.orbColor) .. "|" .. tostring(settings.orbEmpty ~= false) .. "|" .. gen
		.. "|" .. tostring(settings[ANIM_KEY[which]] == true)
end
local function animOn(settings, which) return settings[ANIM_KEY[which]] == true and isStorm(orbLookOf(settings, which)) end

-- Shared with the options and General > Themes: one shield's look, and setting it
function SP:GetShieldLook(which)
	local s = self.opt and self.opt.shieldChargeDisplay or NO_SETTINGS
	local v = s[LOOK_KEY[which]]
	if v == nil and s.barLook == "orbs" then v = s.orbLook or "glow" end
	if v and STORM_LOOK[v] and not STORM_LOOK[v][which] then v = "storm" end
	return v or "bar"
end
function SP:SetShieldLook(which, look)
	local s = self.opt and self.opt.shieldChargeDisplay
	if not s then return end
	if s.barLook == "orbs" then
		-- the first build's one look for all: each shield keeps what it showed, then it goes
		for w = 1, 3 do if s[LOOK_KEY[w]] == nil then s[LOOK_KEY[w]] = s.orbLook or "glow" end end
		s.barLook, s.orbLook = nil, nil
	end
	if look == "bar" then s[LOOK_KEY[which]] = nil else s[LOOK_KEY[which]] = look end
	if self.ShieldLookChanged then self:ShieldLookChanged() end
end

-- ============================================================================
-- Per-shield settings (3.0.8, the owner's rule: Lightning, Water and Earth Shield
-- are three separate shields, each owns ALL of its settings, nothing shared or
-- linked). The settings pages reach them only through SP:ShieldOpt / SetShieldOpt
-- and the calls below; the drawing reads one shield's values through a view with
-- the field names it always used. shield = "LS" | "WS" | "ES".
-- ============================================================================
local SFX = { "LS", "WS", "ES" }
local WHICH = { LS = 1, WS = 2, ES = 3 }
-- the Show choice and today's two switches { Hide Out of Combat, Hide When No Shields }
local SHOW_HIDE = { up = { false, true }, always = { false, false }, fightsUp = { true, true }, fights = { true, false } }
-- key: one per shield (or suffix .. LS / WS / ES); def: the starting value; nilIs: the
-- value kept as "not set" (nil); color: an { r, g, b } or nil
local OPT = {
	enabled = { key = { "showLS", "showWS", "showEarthShield" }, def = true },
	x = { key = { "xLS", "xWS", "earthShieldX" }, def = { -50, -50, 50 } },
	y = { key = { "yLS", "yWS", "earthShieldY" }, def = { -100, -100, -100 } },
	show = { suffix = "showWhen", def = "up" },
	scale = { suffix = "scale", def = 1.0 },
	opacity = { suffix = "opacity", def = 1.0 },
	icon = { suffix = "showIcon", def = false },
	number = { suffix = "showNumber", def = true },
	numberPosition = { suffix = "numberPosition", def = "center" },
	bar = { suffix = "showChargeBar", def = false },
	look = { key = LOOK_KEY, def = "bar", nilIs = "bar" },
	direction = { suffix = "chargeBarDirection", def = "below", nilIs = "below" },
	orbColor = { suffix = "orbColor", def = "bar", nilIs = "bar" },
	orbEmpty = { suffix = "orbEmpty", def = true, nilIs = true },
	anim = { key = ANIM_KEY, def = false, nilIs = false },
	texture = { suffix = "barTexture", def = "default", nilIs = "default" },
	chargeColor = { key = CHARGE_COLOR_KEY, color = true },
	gradient = { key = { "chargeGradientLS", "chargeGradientWS", "chargeGradientES" }, def = "default", nilIs = "default" },
	gradientDirection = { key = { "chargeGradientLSDirection", "chargeGradientWSDirection", "chargeGradientESDirection" }, def = "default", nilIs = "default" },
	gradientColor1 = { key = { "chargeGradientLSColor1", "chargeGradientWSColor1", "chargeGradientESColor1" }, color = true },
	gradientColor2 = { key = { "chargeGradientLSColor2", "chargeGradientWSColor2", "chargeGradientESColor2" }, color = true, def = { r = 1, g = 0.82, b = 0 } },
	gradientFade = { key = { "chargeGradientLSFade", "chargeGradientWSFade", "chargeGradientESFade" }, def = 0.15 },
	-- When It's Gone (3.0.8, a shaman tank's ask): the icon's effect at 0 charges / no shield
	goneEffect = { suffix = "goneEffect", def = "none", nilIs = "none" },
	goneGlowColor = { suffix = "goneGlowColor", color = true },
	goneGlowShape = { suffix = "goneGlowShape" },   -- (nil: General > Themes' Glow Shape; "default" is a real choice, Square)
	goneGlowThick = { suffix = "goneGlowThick", def = 0.2 },
	sound = { sound = true },        -- (ShamanPowerShieldSound.lua keeps these two: shared with Expiring Alerts)
	soundName = { sound = true },
}
local GROUPS = { "show", "icon", "bar", "color", "sound", "gone" }
local GROUP_NAMES = {
	show = { "show", "scale", "opacity" },
	icon = { "icon", "number", "numberPosition" },
	bar = { "bar", "look", "direction", "orbColor", "orbEmpty", "anim", "texture" },
	color = { "chargeColor", "gradient", "gradientDirection", "gradientColor1", "gradientColor2", "gradientFade" },
	sound = { "sound", "soundName" },
	gone = { "goneEffect", "goneGlowColor", "goneGlowShape", "goneGlowThick" },
}
local ALL_NAMES = {}
for _, g in ipairs(GROUPS) do for _, n in ipairs(GROUP_NAMES[g]) do ALL_NAMES[#ALL_NAMES + 1] = n end end
-- [which][name] = the saved key (made once: the drawing reads them on every update)
local KEY = { {}, {}, {} }
for name, spec in pairs(OPT) do
	if not spec.sound then
		for w = 1, 3 do KEY[w][name] = spec.key and spec.key[w] or (spec.suffix .. SFX[w]) end
	end
end
SP.SHIELD_KEYS = KEY   -- (General > Themes and the tests read the key names)
local function startOf(name, which)
	local d = OPT[name].def
	if type(d) == "table" and not OPT[name].color then return d[which] end
	return d
end

-- One shield's view: its own values under the field names the drawing reads.
local VIEW_FIELD = { showIcon = "icon", showNumber = "number", numberPosition = "numberPosition", showChargeBar = "bar",
	chargeBarDirection = "direction", orbColor = "orbColor", orbEmpty = "orbEmpty", scale = "scale", opacity = "opacity" }
local views = { {}, {}, {} }
shieldView = function(which)
	local s = SP.opt and SP.opt.shieldChargeDisplay or NO_SETTINGS
	local v, k = views[which], KEY[which]
	for field, name in pairs(VIEW_FIELD) do v[field] = s[k[name]] end
	if v.scale == nil then v.scale = 1 end
	if v.opacity == nil then v.opacity = 1 end
	if v.showNumber == nil then v.showNumber = true end
	local hide = SHOW_HIDE[s[k.show]] or SHOW_HIDE.up
	v.hideOutOfCombat, v.hideNoShields = hide[1], hide[2]
	local lk, ak, ck = LOOK_KEY[which], ANIM_KEY[which], CHARGE_COLOR_KEY[which]
	v[lk], v[ak], v[ck] = s[lk], s[ak], s[ck]
	v.barLook, v.orbLook, v.locked = s.barLook, s.orbLook, s.locked
	return v
end

-- COPY ONCE (the update to 3.0.8): every shared Shield Charges value goes into
-- each shield's own new key, so every shield starts with exactly what it showed.
-- New keys only; the old ones are never renamed or deleted. A mark, not "is it
-- nil" (AceDB fills defaults in). Runs at login and on a profile switch / import.
local COPY_SHARED = { scale = "scale", opacity = "opacity", showIcon = "icon", showNumber = "number",
	numberPosition = "numberPosition", showChargeBar = "bar", chargeBarDirection = "direction", orbColor = "orbColor", orbEmpty = "orbEmpty" }
local GRADIENT_PART = { gradient = "", gradientDirection = "Direction", gradientColor1 = "Color1", gradientColor2 = "Color2", gradientFade = "Fade" }
local function copyValue(v)
	if type(v) ~= "table" then return v end
	local c = {}
	for k, x in pairs(v) do c[k] = x end
	return c
end
function SP:ShieldMigrate()
	local o = self.opt
	local s = o and o.shieldChargeDisplay
	if type(s) ~= "table" or rawget(s, "perShieldMigrated") then return end
	s.perShieldMigrated = true
	for w = 1, 3 do
		local k = KEY[w]
		for old, name in pairs(COPY_SHARED) do
			local v = s[old]
			if v ~= nil then s[k[name]] = copyValue(v) end
		end
		local hoc, hns = s.hideOutOfCombat and true or false, s.hideNoShields ~= false
		s[k.show] = (hoc and (hns and "fightsUp" or "fights")) or (hns and "up" or "always")
		local areas = o.barTextureAreas
		local tex = type(areas) == "table" and areas.shieldcharges or nil
		if tex ~= nil then s[k.texture] = tex end
		for name, part in pairs(GRADIENT_PART) do
			local v = o["chargeGradient" .. part]
			if v ~= nil then s[k[name]] = copyValue(v) end
		end
	end
	-- Lightning and Water Shield shared one switch and one spot (Earth Shield had its own)
	local on = s.showPlayerShield
	if on ~= nil then s.showLS, s.showWS = on, on end
	local x, y = s.playerShieldX, s.playerShieldY
	if x ~= nil then s.xLS, s.xWS = x, x end
	if y ~= nil then s.yLS, s.yWS = y, y end
end

local function rawSet(self, which, name, v)
	local spec = OPT[name]
	if spec.sound then
		if self.SetShieldSoundOpt then self:SetShieldSoundOpt(which, name, v) end
		return
	end
	if name == "look" then
		local s = self.opt.shieldChargeDisplay
		if s.barLook == "orbs" then
			-- the first build's one look for all: each shield keeps what it showed, then it goes
			for w = 1, 3 do if s[LOOK_KEY[w]] == nil then s[LOOK_KEY[w]] = s.orbLook or "glow" end end
			s.barLook, s.orbLook = nil, nil
		end
	end
	local s = self.opt.shieldChargeDisplay
	if spec.color then
		if type(v) == "table" then v = { r = v.r or v[1] or 1, g = v.g or v[2] or 1, b = v.b or v[3] or 1 } else v = nil end
	elseif spec.nilIs ~= nil and v == spec.nilIs then
		v = nil
	end
	if name == "show" and not SHOW_HIDE[v] then v = nil end
	s[KEY[which][name]] = v
	-- the number can only be off while the icon or the charge bar is on (as today)
	if (name == "icon" or name == "bar") and not v then
		local other = (name == "icon") and "bar" or "icon"
		if not s[KEY[which][other]] then s[KEY[which].number] = true end
	end
end

function SP:ShieldOpt(shield, name)
	local which, spec = WHICH[shield], OPT[name]
	if not (which and spec) then return nil end
	if spec.sound then
		if name == "sound" then return self.ShieldSoundOn and self:ShieldSoundOn(which) or false end
		return self.ShieldSoundName and self:ShieldSoundName(which) or nil
	end
	if name == "look" then return self:GetShieldLook(which) end
	local s = self.opt and self.opt.shieldChargeDisplay or NO_SETTINGS
	local k = KEY[which]
	local v = s[k[name]]
	if name == "number" and not (s[k.icon] or s[k.bar]) then return true end
	if name == "show" then return SHOW_HIDE[v] and v or "up" end
	if v == nil then v = startOf(name, which) end
	if spec.color then return copyValue(v) end
	if name == "orbEmpty" or name == "anim" or name == "enabled" or name == "icon" or name == "number" or name == "bar" then
		if name == "orbEmpty" or name == "enabled" or name == "number" then return v ~= false end
		return v == true
	end
	return v
end

function SP:SetShieldOpt(shield, name, v)
	local which = WHICH[shield]
	if not (which and OPT[name] and self.opt) then return end
	self:EnsureProfileTable("shieldChargeDisplay")
	rawSet(self, which, name, v)
	self:ShieldChanged(shield, name)
end

-- a value as it starts (for the blue corner): the profile's default, else the table above
local function startValue(self, which, name)
	local d = self.db and self.db.defaults and self.db.defaults.profile
	d = d and d.shieldChargeDisplay
	local v = type(d) == "table" and d[KEY[which][name]] or nil
	if v == nil then v = startOf(name, which) end
	if name == "show" then return "up" end
	return v
end
local function same(a, b)
	if type(a) == "number" and type(b) == "number" then return math.abs(a - b) < 1e-4 end
	if type(a) == "table" and type(b) == "table" then
		return same(a.r, b.r) and same(a.g, b.g) and same(a.b, b.b)
	end
	return a == b
end
-- the blue corner: settings changed from their starting values (not shown / hidden, not its spot)
function SP:ShieldOwnChanged(shield)
	local which = WHICH[shield]
	if not which then return false end
	for _, name in ipairs(ALL_NAMES) do
		if OPT[name].sound then
			if self.ShieldSoundOwnChanged and self:ShieldSoundOwnChanged(which) then return true end
		elseif not same(self:ShieldOpt(shield, name), startValue(self, which, name)) then
			return true
		end
	end
	return false
end

-- Reset This Shield: its settings back to their starting values. all (Reset This
-- Page): it is shown again and back on today's spot too.
function SP:ResetShield(shield, all)
	local which = WHICH[shield]
	if not (which and self.opt) then return end
	self:EnsureProfileTable("shieldChargeDisplay")
	local s = self.opt.shieldChargeDisplay
	for _, name in ipairs(ALL_NAMES) do
		if OPT[name].sound then
			if name == "sound" and self.SetShieldSoundOpt then self:SetShieldSoundOpt(which, "reset") end
		else
			if name == "look" then rawSet(self, which, "look", "bar") end
			s[KEY[which][name]] = nil
		end
	end
	if all then
		local k = KEY[which]
		s[k.enabled], s[k.x], s[k.y] = nil, nil, nil
	end
	self:ShieldChanged(shield, "reset")
end

function SP:ShieldLookAvailable(shield, look)
	local which = WHICH[shield]
	if not which then return false end
	if STORM_LOOK[look] then return STORM_LOOK[look][which] ~= nil end
	return look == "bar" or look == "glow" or look == "flat" or look == "icon"
end

-- Copy Settings: the values, once (never linked). A look the other shield does not
-- have becomes Storm Orbs (as the drawing already does).
function SP:CopyShield(from, to, group)
	local a, b = WHICH[from], WHICH[to]
	if not (a and b and a ~= b and self.opt) then return end
	self:EnsureProfileTable("shieldChargeDisplay")
	local s = self.opt.shieldChargeDisplay
	local list = group and GROUP_NAMES[group] or ALL_NAMES
	for _, name in ipairs(list) do
		local v = self:ShieldOpt(from, name)
		if name == "look" and not self:ShieldLookAvailable(to, v) then v = "storm" end
		if name == "number" then v = s[KEY[a].number] end   -- (as stored: on / off follows icon and bar)
		rawSet(self, b, name, v)
	end
	self:ShieldChanged(to, group or "copy")
end

function SP:ShieldNames(group)
	local list = group and GROUP_NAMES[group] or ALL_NAMES
	local out = {}
	for i = 1, #list do out[i] = list[i] end
	return out
end
function SP:ShieldGroups()
	local out = {}
	for i = 1, #GROUPS do out[i] = GROUPS[i] end
	return out
end

-- a shield's spot (its own; Lightning and Water Shield start on today's one spot)
shieldSpot = function(which)
	local s = SP.opt and SP.opt.shieldChargeDisplay or NO_SETTINGS
	local k = KEY[which]
	local x, y = s[k.x], s[k.y]
	if x == nil then x = startOf("x", which) end
	if y == nil then y = startOf("y", which) end
	return x, y
end
function SP:SetShieldSpot(which, x, y)
	if not self.opt then return end
	self:EnsureProfileTable("shieldChargeDisplay")
	local s, k = self.opt.shieldChargeDisplay, KEY[which]
	s[k.x], s[k.y] = x, y
	local f = self:ShieldChargeFrameOf(which)
	if f then f.spSpotX, f.spSpotY = x, y end   -- (it is there already: dropped on it)
end
-- a box's Reset (Unlock UI): that shield back on its starting spot
function SP:ResetShieldSpot(which)
	if not self.opt then return end
	self:EnsureProfileTable("shieldChargeDisplay")
	local s, k = self.opt.shieldChargeDisplay, KEY[which]
	s[k.x], s[k.y] = nil, nil
	local f = self:ShieldChargeFrameOf(which)
	if f then
		local x, y = shieldSpot(which)
		f:ClearAllPoints(); f:SetPoint("CENTER", UIParent, "CENTER", x, y)
		f.spSpotX, f.spSpotY = x, y
	end
end
function SP:ShieldChargeFrameOf(which)
	local d = FRAME_DEF[which]
	return d and self.shieldChargeFrames[d.key] or nil
end

-- bumped when a theme moves these colours: the game-drawn displays read them
-- once, when built, so a new stamp rebuilds them (out of combat, see the end)
local themeStamp = 0

-- Which parts a display shows. The number can only be off while the icon or
-- the bar is on, so a display is never drawn with nothing in it.
local function displayParts(settings)
	local icon = settings.showIcon and true or false
	local bar = settings.showChargeBar and true or false
	local number = (settings.showNumber ~= false) or not (icon or bar)
	local corner = (icon and number and settings.numberPosition == "corner") and true or false
	-- Charge Bar Direction: nil = below, "above" = over the display (both flat),
	-- "right" / "left" = stood up beside it
	local dir = settings.chargeBarDirection
	local barSide = bar and (dir == "above" or dir == "right" or dir == "left") and dir or false
	return icon, number, corner, bar, barSide
end

-- How far a display's parts reach from its center, in the frame's own units:
-- half its width, above, below. The setup tour lays the preview out by it.
function SP:ShieldChargeDisplayExtent(frame)
	local settings = shieldView(frame and frame.spWhich or 1)
	local s = settings.scale or 1
	local icon, number, _, bar, barSide = displayParts(settings)
	local halfW, above, below = 0, 0, 0
	local BAR_WIDTH, BAR_HEIGHT = BAR_WIDTH, BAR_HEIGHT   -- the orb strip's size with Orbs on
	local cb = frame and frame.chargeBar
	local look = orbLookOf(settings, (cb and cb.spWhich) or (frame and frame.spWhich) or 1)
	if look then
		BAR_WIDTH, BAR_HEIGHT = orbLength(cb and cb.spKind or "player", look), orbThickness(look)
	end
	if number and frame and frame.text then
		halfW = (frame.text:GetStringWidth() or 0) / 2
		above = (frame.text:GetStringHeight() or 0) / 2
		below = above
	end
	if icon then
		local h = ICON_SIZE / 2 * s
		halfW, above, below = math.max(halfW, h), math.max(above, h), math.max(below, h)
	end
	if barSide == "right" or barSide == "left" then
		-- stood up on a side: as tall as the bar is long, reaching past the icon / number
		halfW = math.max(halfW, ((icon and ICON_SIZE / 2) or (number and NUMBER_SIDE) or 0) * s + (BAR_GAP + BAR_HEIGHT) * s)
		above, below = math.max(above, BAR_WIDTH / 2 * s), math.max(below, BAR_WIDTH / 2 * s)
	elseif barSide == "above" then
		halfW = math.max(halfW, BAR_WIDTH / 2 * s)
		above = math.max(above, ((icon and ICON_SIZE / 2) or (number and NUMBER_TOP) or 0) * s + (BAR_GAP + BAR_HEIGHT) * s)
	elseif bar then
		halfW = math.max(halfW, BAR_WIDTH / 2 * s)
		below = math.max(below, ((icon and ICON_SIZE / 2) or (number and NUMBER_BOTTOM) or 0) * s + (BAR_GAP + BAR_HEIGHT) * s)
	end
	return halfW, above, below
end

local function numberSize(icon, corner)
	if corner then return NUMBER_CORNER end
	if icon then return NUMBER_ON_ICON end
	return NUMBER_SIZE
end

-- Icon files, [1] Lightning Shield, [2] Water Shield, [3] Earth Shield: looked
-- up once, the first time an icon is drawn. The fallbacks ship with every client.
local ICON_FALLBACK = {
	"Interface\\Icons\\Spell_Nature_LightningShield",
	"Interface\\Icons\\Ability_Shaman_WaterShield",
	"Interface\\Icons\\Spell_Nature_SkinofEarth",
}
local shieldIcons
local function firstSpellIcon(ids)
	for _, id in ipairs(ids or {}) do
		local ok, tex = pcall(GetSpellTexture, id)
		if ok and tex then return tex end
		if GetSpellInfo then
			local ok2, _, _, tex2 = pcall(GetSpellInfo, id)
			if ok2 and tex2 then return tex2 end
		end
	end
end
local function shieldIcon(which)
	if not shieldIcons then
		shieldIcons = {}
		for _, set in ipairs(ShamanPower.ShieldAuraSets or {}) do
			if set.name == "Lightning Shield" then shieldIcons[1] = firstSpellIcon(set.ids)
			elseif set.name == "Water Shield" then shieldIcons[2] = firstSpellIcon(set.ids) end
		end
		shieldIcons[3] = firstSpellIcon(ES_SPELL_IDS)
		for i = 1, 3 do shieldIcons[i] = shieldIcons[i] or ICON_FALLBACK[i] end
	end
	return shieldIcons[which] or ICON_FALLBACK[1]
end

-- A segmented charge bar: one StatusBar filled to the count over a dark
-- backing, with thin dark dividers between the segments drawn over the fill.
local styleChargeBar   -- below: today's bar or the orbs
local stormModels      -- below: Animated Lightning (Storm Orbs)
local function createChargeBar(parent, kind, which)
	local n, c = MAX_CHARGES[kind], SHIELD_COLOR[kind]
	local bar = CreateFrame("StatusBar", nil, parent)
	bar.spKind, bar.spWhich = kind, which
	local back = bar:CreateTexture(nil, "BACKGROUND")
	bar.back = back
	back:SetPoint("TOPLEFT", bar, "TOPLEFT", -1, 1)
	back:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 1, -1)
	back:SetColorTexture(0, 0, 0, 0.6)
	bar:SetStatusBarColor(c[1], c[2], c[3])
	bar:SetMinMaxValues(0, n)
	bar:SetValue(0)
	bar.dividers = {}
	for i = 1, n - 1 do
		local d = bar:CreateTexture(nil, "OVERLAY")
		d:SetColorTexture(0, 0, 0, 0.9)
		bar.dividers[i] = d
	end
	styleChargeBar(bar, which)
	return bar
end

-- Today's segmented bar, or the orbs (Charge Bar Look). which: 1 Lightning
-- Shield, 2 Water Shield, 3 Earth Shield (the icon orbs and By Shield colors).
styleChargeBar = function(bar, which)
	local kind = bar.spKind
	which = which or bar.spWhich or ((kind == "earth") and 3 or 1)
	bar.spWhich = which
	local settings = shieldView(which)   -- this shield's own settings
	local area = SHIELD_AREA[which]      -- its own Charge Bar Texture and Gradient
	local look = orbLookOf(settings, which)
	local back = bar.back
	local c = SHIELD_COLOR[kind]
	if look then
		local n = MAX_CHARGES[kind]
		local file
		if look == "icon" then file = ORB_DIR .. ORB_ICON[which]
		elseif isStorm(look) then file = ORB_DIR .. (STORM_LOOK[look][which] or STORM_LOOK.storm[which])
		else file = ORB_DIR .. "Orbs_" .. ((look == "flat") and "Flat" or "Glow") .. "_" .. n end
		bar.spOwnTexture = true
		if bar.spOrbFile ~= file then bar:SetStatusBarTexture(file); bar.spOrbFile = file; bar.spBarTex = nil end
		-- the strip is cropped to the fill: whole orbs (Anniversary takes only the enum, not the string)
		local fillStyle = Enum and Enum.StatusBarFillStyle and Enum.StatusBarFillStyle.Standard
		if bar.SetFillStyle then bar:SetFillStyle(fillStyle or "STANDARD") end
		-- Storm Orbs glow additively (Water Shield's are a plain picture)
		local fill = bar:GetStatusBarTexture()
		-- (Miska's Water Shield orb is a plain picture)
		if fill then fill:SetBlendMode((isStorm(look) and not (look == "storm" and which == 2)) and "ADD" or "BLEND") end
		local r, g, b = c[1], c[2], c[3]
		local cr, cg, cbl = customChargeColor(settings, which)
		if look == "icon" then
			r, g, b = 1, 1, 1           -- the shield's own icon, never tinted
		elseif cr then
			r, g, b = cr, cg, cbl       -- Charge Colors: tints the Storm family too
		elseif isStorm(look) then
			r, g, b = 1, 1, 1
		elseif settings.orbColor == "shield" then
			local sc = ORB_SHIELD_COLOR[which] or ORB_SHIELD_COLOR[1]
			r, g, b = sc[1], sc[2], sc[3]
		end
		bar:SetStatusBarColor(r, g, b)
		-- Charge Bar Gradient: the tinted Glowing and Flat orbs shade too; pictures keep their art
		if fill then
			if look == "glow" or look == "flat" then
				SP:PaintBarGradient(fill, r, g, b, 1, bar:GetOrientation() == "VERTICAL", nil, area)
			elseif fill.spGrad then
				fill.spGrad = nil
				fill:SetVertexColor(r, g, b, 1)
			end
		end
		back:ClearAllPoints()
		back:SetAllPoints(bar)
		back:SetTexture(ORB_DIR .. (isStorm(look) and "Orbs_StormEmpty_" or "Orbs_Empty_") .. n)
		if isStorm(look) then
			if which == 3 then back:SetVertexColor(0.25, 0.55, 0.3, 0.8) else back:SetVertexColor(0.3, 0.4, 0.75, 0.8) end
		elseif look == "icon" then back:SetVertexColor(0.55, 0.6, 0.7, 0.9) else back:SetVertexColor(r * 0.55, g * 0.55, b * 0.55, 0.9) end
		back:SetShown(settings.orbEmpty ~= false)
		for _, d in ipairs(bar.dividers) do d:Hide() end
		bar.spOrbs = look
	else
		if bar.spOrbs then
			-- back to today's bar
			bar.spOrbs, bar.spOrbFile, bar.spOwnTexture, bar.spBarTex = nil, nil, nil, nil
			back:ClearAllPoints()
			back:SetPoint("TOPLEFT", bar, "TOPLEFT", -1, 1)
			back:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 1, -1)
			back:SetVertexColor(1, 1, 1, 1)
			back:SetColorTexture(0, 0, 0, 0.6)
			back:Show()
			for _, d in ipairs(bar.dividers) do d:Show() end
			if bar.spPop then bar.spPop:Hide() end
			local fill = bar:GetStatusBarTexture()
			if fill then fill:SetBlendMode("BLEND") end
		end
		SP:SetSPStatusBarTexture(bar, area, "Interface\\Buttons\\WHITE8x8")   -- this shield's Charge Bar Texture
		local r, g, b = c[1], c[2], c[3]
		local cr, cg, cbl = customChargeColor(settings, which)
		if cr then r, g, b = cr, cg, cbl end   -- Charge Colors
		bar:SetStatusBarColor(r, g, b)   -- (Charge Bar Gradient shades it through the texture hook)
	end
end

-- A charge used (out of combat, and on Anniversary): the orb it was pops, grows
-- and fades out over its empty slot. In combat on Forever the game draws the
-- charges, so there the orb simply goes out.
local function orbPop(bar, index)
	local n = MAX_CHARGES[bar.spKind]
	local p = bar.spPop
	if not p then
		p = bar:CreateTexture(nil, "OVERLAY")
		p:SetTexture(ORB_DIR .. "Circle_Smooth")
		p:SetBlendMode("ADD")
		local ag = p:CreateAnimationGroup()
		local sc = ag:CreateAnimation("Scale"); sc:SetScale(1.7, 1.7); sc:SetDuration(0.25)
		local al = ag:CreateAnimation("Alpha"); al:SetFromAlpha(0.9); al:SetToAlpha(0); al:SetDuration(0.25)
		ag:SetScript("OnFinished", function() p:Hide() end)
		p.ag = ag
		bar.spPop = p
	end
	local vertical = bar:GetOrientation() == "VERTICAL"
	local len = vertical and bar:GetHeight() or bar:GetWidth()
	local thk = vertical and bar:GetWidth() or bar:GetHeight()
	local pos = (index - 0.5) / n * len
	p:ClearAllPoints()
	p:SetSize(thk * 0.8, thk * 0.8)
	if vertical then p:SetPoint("CENTER", bar, "BOTTOM", 0, pos) else p:SetPoint("CENTER", bar, "LEFT", pos, 0) end
	p:SetVertexColor(bar:GetStatusBarColor())
	p:Show()
	p.ag:Stop(); p.ag:Play()
end

-- Animated Lightning / Water / Earth (a Storm-family look; off by default): a
-- spell effect over each lit orb, as Miska's aura does with the lightning. Models
-- animate every frame, so they are only there while this is on and an orb is lit.
-- [which] = the model: one family of hand glows, each the same size and centered
-- on its own middle so it sits in an orb: Lightning's crackle (Miska's), the ice
-- glow, the green nature glow (the Water / Earth Shield effects themselves circle
-- the whole character, so an orb only ever showed a slice of them).
local MODEL_ID = { 166492, 166381, 166605 }
local MODEL_UNITS = 77           -- the aura's model size, in this display's units
-- the center of orb i on a strip (the arc: the middle orb sits a little lower)
local function orbCenter(bar, i)
	local n = MAX_CHARGES[bar.spKind]
	local vertical = bar:GetOrientation() == "VERTICAL"
	local len = vertical and bar:GetHeight() or bar:GetWidth()
	local thk = vertical and bar:GetWidth() or bar:GetHeight()
	local along = (i - 0.5) / n * len
	local cross = ((n == 3 and i == 2) and -0.039 or 0.039) * thk   -- the baked arc, as a share of the strip's height
	if vertical then return "BOTTOM", 0, along end
	return "LEFT", along, cross
end
local function newModel(parent, which)
	local m = CreateFrame("PlayerModel", nil, parent)
	if m.SetKeepModelOnHide then m:SetKeepModelOnHide(true) end
	m:SetModel(MODEL_ID[which])
	m.spModelID = MODEL_ID[which]
	m:SetPosition(0, 0, 0)
	m:SetFacing(0)
	m:EnableMouse(false)
	return m
end
-- the addon's own models (Anniversary, and the settings preview): lit = how many orbs
stormModels = function(bar, lit, s)
	local list = bar.spModels
	if lit <= 0 and not list then return end
	list = list or {}
	bar.spModels = list
	local id = MODEL_ID[bar.spWhich or 1]
	for i = 1, MAX_CHARGES[bar.spKind] do
		local m = list[i]
		if i <= lit then
			if not m then m = newModel(bar, bar.spWhich or 1); list[i] = m end
			if m.spModelID ~= id then m:SetModel(id); m.spModelID = id end   -- Lightning <-> Water Shield
			local point, x, y = orbCenter(bar, i)
			local key = point .. x .. "," .. y .. "," .. s
			if m.spKey ~= key then   -- only on a change: sizing a model restarts its animation
				m.spKey = key
				m:ClearAllPoints()
				m:SetSize(MODEL_UNITS * s, MODEL_UNITS * s)
				m:SetPoint("CENTER", bar, point, x, y)
			end
			if not m:IsShown() then m:Show() end
		elseif m and m:IsShown() then
			m:Hide()
		end
	end
end

-- WoW: Forever: charges are hidden from addons, so each orb's model is gated the
-- way Miska's aura does it: an aura container per orb whose hidden text holds a
-- spacer only while the charges are at least n (the game decides, through a
-- formatter), and the model is anchored to that text's corners, so it has a size
-- only then. Nothing hidden is read. Built out of combat, rebuilt on a change.
-- Lightning and Water Shield each get their own set (Earth Shield: Anniversary only).
local SPACER_TEXT = ("\124T%s:0\124t"):format(ORB_DIR .. "Circle_Smooth")
local SHIELD_SET_NAME = { "Lightning Shield", "Water Shield" }
local function shieldIDs(which)
	for _, set in ipairs(ShamanPower.ShieldAuraSets or {}) do
		if set.name == SHIELD_SET_NAME[which] then
			local m = {}
			for _, id in ipairs(set.ids) do m[id] = true end
			return m
		end
	end
	return nil
end
-- Orb n's center on the display frame for a Storm-family strip, from the settings
-- (the same sums placeParts does): the live bar may show the other shield's look.
local function stormOrbOnFrame(settings, kind, s, n, which)
	local icon, number, _, _, barSide = displayParts(settings)
	local count = MAX_CHARGES[kind]
	local look = orbLookOf(settings, which) or "storm"   -- (that shield's strip size: Bubble's is small)
	local blen, bthk = orbLength(kind, look) * s, orbThickness(look) * s
	local arc = ((count == 3 and n == 2) and -0.039 or 0.039) * bthk
	if barSide == "right" or barSide == "left" then
		local side = (icon and ICON_SIZE / 2) or (number and NUMBER_SIDE) or nil
		local cx = 0
		if side then cx = (side + BAR_GAP) * s + bthk / 2 end
		if barSide == "left" then cx = -cx end
		return cx, -blen / 2 + (n - 0.5) / count * blen
	end
	local above = barSide == "above"
	local reach = (icon and ICON_SIZE / 2) or (number and (above and NUMBER_TOP or NUMBER_BOTTOM)) or nil
	local cy = 0
	if reach then cy = (reach + BAR_GAP) * s + bthk / 2 end
	if not above then cy = -cy end
	return -blen / 2 + (n - 0.5) / count * blen, cy + arc
end
local function dropGates(frame)
	if not frame.stormGates then return end
	for _, set in pairs(frame.stormGates) do
		for _, g in ipairs(set) do
			g:Hide()
			pcall(g.SetUnit, g, "none")
		end
	end
	frame.stormGates = nil
end
local function buildGates(frame, settings, s, which)
	local ids = shieldIDs(which)
	if not (ids and C_StringUtil and C_StringUtil.CreateNumericRuleFormatter) then return nil end
	local gates = {}
	for n = 1, MAX_CHARGES.player do
		local okf, fmt = pcall(C_StringUtil.CreateNumericRuleFormatter)
		if not okf or not fmt then break end
		pcall(fmt.AddBreakpoint, fmt, { threshold = 0, format = "" })
		pcall(fmt.AddBreakpoint, fmt, { threshold = n, format = SPACER_TEXT })
		local okc, c = pcall(CreateFrame, "AuraContainer", nil, frame, "CustomAuraContainerTemplate")
		if not okc or not c then break end
		c:SetAllPoints(frame)
		c:SetFrameLevel(frame:GetFrameLevel() + 8)
		local x, y = stormOrbOnFrame(settings, "player", s, n, which)
		local size = math.max(2, math.floor(MODEL_UNITS * s + 0.5))
		pcall(c.AddAuraSlot, c, "stormorb" .. which .. "_" .. n, "HELPFUL|PLAYER", {
			candidateFilters = { includeSpellIDs = ids },
			initializeFrame = function(button)
				button:ClearAllPoints()
				button:SetAllPoints(frame)
				if button.SetMouseClickEnabled then pcall(button.SetMouseClickEnabled, button, false) end
				if button.SetMouseMotionEnabled then pcall(button.SetMouseMotionEnabled, button, false) end
				local carrier = CreateFrame("Frame", nil, button)
				carrier:SetAllPoints(button)
				local fs = carrier:CreateFontString(nil, "OVERLAY")
				fs:SetFont(STANDARD_TEXT_FONT, size, "")
				fs:SetPoint("CENTER", frame, "CENTER", x, y)
				fs:SetAlpha(0)
				local m = newModel(carrier, which)
				-- inset 1px: an empty text is still about 1px wide
				m:SetPoint("TOPLEFT", fs, "TOPLEFT", 1, 0)
				m:SetPoint("BOTTOMRIGHT", fs, "BOTTOMRIGHT", -1, 0)
				pcall(button.SetApplicationCount, button, fs, { formatter = fmt })
			end,
		})
		pcall(c.SetUnit, c, "player")
		if c.SetEnabled then pcall(c.SetEnabled, c, true) end
		pcall(c.UpdateAllAuras, c)
		gates[#gates + 1] = c
	end
	return gates
end
local function ensureGates(frame, kind, settings, s)
	local which = frame.spWhich or 1
	local want = kind == "player" and which ~= 3 and animOn(settings, which)
	local sig = want and (tostring(which) .. "|" .. tostring(s) .. "|" .. tostring(settings.chargeBarDirection)
		.. "|" .. tostring(settings.showIcon) .. "|" .. tostring(settings.showNumber) .. "|" .. tostring(settings.numberPosition)
		.. "|" .. tostring(orbLookOf(settings, which))) or false
	if frame.stormGateSig == sig then
		-- the same gates: shown again after the settings preview hid them (none built:
		-- nothing to do, and no empty table made on every update)
		local sets = frame.stormGates
		if sets then
			for _, set in pairs(sets) do
				for _, g in ipairs(set) do if not g:IsShown() then g:Show() end end
			end
		end
		return
	end
	if InCombatLockdown() then return end   -- built when the fight ends
	dropGates(frame)
	frame.stormGateSig = sig
	if not sig then return end
	frame.stormGates = {}
	frame.stormGates[which] = buildGates(frame, settings, s, which)
end

-- Place a display's parts on `box` (the display frame, or the engine's aura
-- button, which covers it exactly). Every part hangs off the box's center, and
-- the icon (or the plain number) stays where it is when the bar is added.
local function placeParts(box, s, icon, number, corner, iconTex, text, chargeBar, barSide)
	if iconTex then
		iconTex:ClearAllPoints()
		iconTex:SetSize(ICON_SIZE * s, ICON_SIZE * s)
		iconTex:SetPoint("CENTER", box, "CENTER", 0, 0)
	end
	if text then
		text:ClearAllPoints()
		if corner then
			text:SetPoint("BOTTOMRIGHT", box, "CENTER", (ICON_SIZE / 2 - 1) * s, -(ICON_SIZE / 2 - 1) * s)
		else
			text:SetPoint("CENTER", box, "CENTER", 0, 0)
		end
	end
	-- the bar's length and thickness: today's bar, or the orb strip
	local blen, bthk = BAR_WIDTH, BAR_HEIGHT
	if chargeBar and chargeBar.spOrbs then blen, bthk = orbLength(chargeBar.spKind, chargeBar.spOrbs), orbThickness(chargeBar.spOrbs) end
	if chargeBar and (barSide == "right" or barSide == "left") then
		-- Charge Bar Direction: Vertical. Stood up beside the icon / number (never
		-- over it), on the side picked, filling from the bottom; with nothing else
		-- shown it is the whole display.
		local h = blen * s
		chargeBar:SetOrientation("VERTICAL")
		if chargeBar.SetRotatesTexture then chargeBar:SetRotatesTexture(true) end   -- a patterned bar texture stands up with it
		-- the orbs' empty track stands up with them (turned like the fill: its left end
		-- at the bottom), or its row of rings is squeezed into a thin scribble
		if chargeBar.back then chargeBar.back:SetTexCoord(1, 0, 0, 0, 1, 1, 0, 1) end
		chargeBar:ClearAllPoints()
		chargeBar:SetSize(bthk * s, h)
		local side = (icon and ICON_SIZE / 2) or (number and NUMBER_SIDE) or nil
		if side and barSide == "left" then
			chargeBar:SetPoint("RIGHT", box, "CENTER", -(side + BAR_GAP) * s, 0)
		elseif side then
			chargeBar:SetPoint("LEFT", box, "CENTER", (side + BAR_GAP) * s, 0)
		else
			chargeBar:SetPoint("CENTER", box, "CENTER", 0, 0)
		end
		local dividers = chargeBar.dividers
		local n = #dividers + 1
		local dw = math.max(1, math.floor(s + 0.5))
		for i = 1, #dividers do
			local d = dividers[i]
			d:ClearAllPoints()
			d:SetHeight(dw)
			d:SetPoint("LEFT", chargeBar, "BOTTOMLEFT", 0, h * i / n)
			d:SetPoint("RIGHT", chargeBar, "BOTTOMRIGHT", 0, h * i / n)
		end
	elseif chargeBar then
		local w = blen * s
		chargeBar:SetOrientation("HORIZONTAL")
		if chargeBar.SetRotatesTexture then chargeBar:SetRotatesTexture(false) end
		if chargeBar.back then chargeBar.back:SetTexCoord(0, 1, 0, 1) end   -- the empty track lying flat again
		chargeBar:ClearAllPoints()
		chargeBar:SetSize(w, bthk * s)
		-- Charge Bar Direction: Below (today's) or Above, clear of the icon / number
		local above = barSide == "above"
		local reach = (icon and ICON_SIZE / 2) or (number and (above and NUMBER_TOP or NUMBER_BOTTOM)) or nil
		if reach and above then
			chargeBar:SetPoint("BOTTOM", box, "CENTER", 0, (reach + BAR_GAP) * s)
		elseif reach then
			chargeBar:SetPoint("TOP", box, "CENTER", 0, -(reach + BAR_GAP) * s)
		else
			chargeBar:SetPoint("CENTER", box, "CENTER", 0, 0)
		end
		local dividers = chargeBar.dividers
		local n = #dividers + 1
		local dw = math.max(1, math.floor(s + 0.5))
		for i = 1, #dividers do
			local d = dividers[i]
			d:ClearAllPoints()
			d:SetWidth(dw)
			d:SetPoint("TOP", chargeBar, "TOPLEFT", w * i / n, 0)
			d:SetPoint("BOTTOM", chargeBar, "BOTTOMLEFT", w * i / n, 0)
		end
	end
end

-- Draw one display with the addon's own parts. Restricted: the engine draws
-- the live state on top, so the addon's parts show only the empty state
-- (grayed icon, empty bar, and a red 0 when the icon is there to hide it), and
-- only while "Hide When No Shields" is off: the engine's icon covers them
-- while the shield is up. Below 100% opacity the red 0 would show through the
-- engine's live count, so in combat it is only drawn at full opacity (the
-- grayed icon and empty bar stay at any opacity).
-- iconWhich: 1 Lightning Shield, 2 Water Shield, 3 Earth Shield.
-- noGray: in a fight on WoW: Forever the game draws whichever shield is up on its
-- own display; only one of Lightning / Water Shield (the last one you had) keeps
-- the gray layer under it, so two grays never sit on one spot.
-- sample: the Shield Charges page's own copy (SP:PaintShieldChargeSample), which plays its effects on both clients
-- When It's Gone: the icon's effect at 0 charges / no shield (each shield its own): a glow in
-- its Glow Shape (Proc Glow too) round the icon, a pulse of the icon, or both, until a shield
-- is up again. In a fight on WoW: Forever the game hides whether the shield is up: the Cooldown
-- Manager's own shield item tells the moment (ShieldGoneHooks, below); until it has spoken,
-- nothing plays there.
local goneHook = { bound = false, anyUp = nil, up = {}, have = {} }   -- anyUp: a Lightning / Water Shield is up (seeded out of a fight); up: each shield as the hook last saw it; have: the shields with an item
local function goneSettings(which)
	local sv = SP.opt and SP.opt.shieldChargeDisplay or NO_SETTINGS
	local k = KEY[which]
	local fx = sv[k.goneEffect] or "none"
	local c = sv[k.goneGlowColor]
	local r, g, b
	if type(c) == "table" then r, g, b = c.r or c[1] or 1, c.g or c[2] or 1, c.b or c[3] or 1
	else local sc = SHIELD_COLOR[(which == 3) and "earth" or "player"]; r, g, b = sc[1], sc[2], sc[3] end
	return fx, r, g, b, sv[k.goneGlowShape] or (SP.opt and SP.opt.glowShape) or "default", tonumber(sv[k.goneGlowThick]) or 0.2
end
local function goneHost(frame, s)
	local h = frame.goneHost
	if not h then
		h = CreateFrame("Frame", nil, frame)
		h:SetFrameLevel(frame:GetFrameLevel() + 1)
		frame.goneHost = h
		local glow = h:CreateTexture(nil, "OVERLAY", nil, 1)
		glow:SetPoint("TOPLEFT", -10, 10); glow:SetPoint("BOTTOMRIGHT", 10, -10)
		glow:SetTexture("Interface\\SpellActivationOverlay\\IconAlert")
		glow:SetTexCoord(0.00781250, 0.50781250, 0.27734375, 0.52734375)
		glow:SetBlendMode("ADD"); glow:SetAlpha(0)
		h.glow = glow
		local ag = glow:CreateAnimationGroup(); ag:SetLooping("REPEAT")
		local a1 = ag:CreateAnimation("Alpha"); a1:SetFromAlpha(0.15); a1:SetToAlpha(0.8); a1:SetDuration(0.5); a1:SetOrder(1)
		local a2 = ag:CreateAnimation("Alpha"); a2:SetFromAlpha(0.8); a2:SetToAlpha(0.15); a2:SetDuration(0.5); a2:SetOrder(2)
		h.glowAnim = ag
		h:Hide()
	end
	local size = ICON_SIZE * s
	h:SetSize(size, size); h:ClearAllPoints(); h:SetPoint("CENTER", frame, "CENTER", 0, 0)
	return h
end
local function goneEffect(frame, which, s, on)
	local fx, r, g, b, shape, thick = goneSettings(which)
	local wantGlow = on and (fx == "glow" or fx == "both")
	local wantPulse = on and (fx == "pulse" or fx == "both")
	local h = frame.goneHost
	if wantGlow and not h then h = goneHost(frame, s) end
	if h then
		if wantGlow then
			local sig = fx .. "|" .. r .. "," .. g .. "," .. b .. "|" .. shape .. "|" .. thick .. "|" .. s
			if not h.on or h.sig ~= sig then
				local quiet = h.on == true   -- (a re-tune while it plays: no start burst)
				h.sig = sig
				goneHost(frame, s)
				h:Show()
				if shape == "proc" and SP.ProcGlow_Start then
					h.glow:Hide(); h.glowAnim:Stop()
					SP.ProcGlow_Start(h, SP:ProcGlowOptions(h, { r, g, b, 1 }, "shield", quiet, thick))
				else
					if SP.ProcGlow_Stop then SP.ProcGlow_Stop(h, "shield") end
					if SP.PaintGlowShape then SP:PaintGlowShape(h.glow, shape) end
					h.glow:SetVertexColor(r, g, b); h.glow:Show(); h.glowAnim:Play()
				end
				h.on = true
			end
		elseif h.on then
			h.on, h.sig = nil, nil
			h.glow:Hide(); h.glowAnim:Stop()
			if SP.ProcGlow_Stop then SP.ProcGlow_Stop(h, "shield") end
			h:Hide()
		end
	end
	local icon = frame.icon
	if icon then
		if wantPulse then
			if not icon.spPulse then
				local pg = icon:CreateAnimationGroup(); pg:SetLooping("REPEAT")
				local p1 = pg:CreateAnimation("Scale"); p1:SetScale(1.12, 1.12); p1:SetDuration(0.45); p1:SetOrder(1)
				local p2 = pg:CreateAnimation("Scale"); p2:SetScale(1 / 1.12, 1 / 1.12); p2:SetDuration(0.45); p2:SetOrder(2)
				icon.spPulse = pg
			end
			if not icon.spPulse:IsPlaying() then icon.spPulse:Play() end
		elseif icon.spPulse and icon.spPulse:IsPlaying() then icon.spPulse:Stop() end
	end
end
-- every display's effect off (the module off, a profile change)
function SP:ShieldGoneEffectsOff()
	local frames = self.shieldChargeFrames
	if not frames then return end
	for _, f in pairs(frames) do if f.goneHost or (f.icon and f.icon.spPulse) then goneEffect(f, f.spWhich or 1, 1, false) end end
end

local function paintDisplay(frame, kind, settings, s, charges, present, restricted, iconWhich, noGray, sample)
	local icon, number, corner, bar, barSide = displayParts(settings)
	local orbs = orbSig(settings, iconWhich or 1)
	if frame.layScale ~= s or frame.layIcon ~= icon or frame.layNumber ~= number
		or frame.layCorner ~= corner or frame.layBar ~= bar or frame.layBarSide ~= barSide or frame.layOrbs ~= orbs then
		frame.layScale, frame.layIcon, frame.layNumber, frame.layCorner, frame.layBar = s, icon, number, corner, bar
		frame.layBarSide, frame.layOrbs = barSide, orbs
		if icon and not frame.icon then
			local t = frame:CreateTexture(nil, "ARTWORK")
			t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			t:Hide()
			frame.icon = t
		end
		-- one charge bar per shield (Lightning and Water on this display, Earth on its
		-- own): each is built, styled, sized and animated for its own shield only and
		-- never restyled as another; the one for the shield up is shown (below)
		frame.chargeBars = frame.chargeBars or {}
		if bar and iconWhich and not frame.chargeBars[iconWhich] then
			local nb = createChargeBar(frame, kind, iconWhich)
			nb:Hide()
			frame.chargeBars[iconWhich] = nb
		end
		placeParts(frame, s, icon, number, corner, icon and frame.icon, frame.text, nil, barSide)
		for w, b in pairs(frame.chargeBars) do
			styleChargeBar(b, w)   -- today's bar or its shield's orbs, as set now
			if bar then placeParts(frame, s, icon, number, corner, nil, nil, b, barSide) end
		end
	end

	local own = (not restricted or not settings.hideNoShields) and not noGray
	local text = frame.text
	local r, g, b = SP:GetShieldChargeColor(charges, MAX_CHARGES[kind], kind == "earth")
	-- restricted: our 0 sits under the engine's icon, which hides it while the
	-- shield is up at full opacity; without an icon nothing would hide it, and
	-- below 100% it would show through, so no 0 there
	local solid = (settings.opacity or 1) >= 1
	local shown = not number and "" or (not restricted and charges) or ((own and icon and solid) and "0" or "")
	text:SetText(shown)
	text:SetTextColor(r, g, b)
	SP:SetSPFont(text, "charges", numberSize(icon, corner) * s, "OUTLINE")

	local lit = present and not restricted
	local tex = frame.icon
	if tex then
		if icon and own then
			local file = shieldIcon(iconWhich)
			if frame.iconFile ~= file then
				tex:SetTexture(file)
				frame.iconFile = file
			end
			tex:SetDesaturated(not lit)
			tex:SetAlpha(lit and 1 or 0.45)
			tex:Show()
		else
			tex:Hide()
		end
	end
	local bars = frame.chargeBars
	if bars and bar and own and iconWhich and not bars[iconWhich] then
		-- the first time this shield is up: its own bar, laid out like the others
		local nb = createChargeBar(frame, kind, iconWhich)
		nb:Hide()
		bars[iconWhich] = nb
		placeParts(frame, s, icon, number, corner, nil, nil, nb, barSide)
	end
	local cb = bars and bars[iconWhich]
	frame.chargeBar = cb   -- the one shown (the display's extent reads it)
	if bars then
		for _, b in pairs(bars) do
			if (b ~= cb or not (bar and own)) and b:IsShown() then b:Hide() end   -- (its models go with it)
		end
	end
	if cb and bar and own then
		local v = lit and charges or 0
		if not cb:IsShown() then cb.spLast = nil end   -- just switched to this shield: no pop
		if cb.spOrbs then
			if cb.spLast and v < cb.spLast and not restricted and cb:IsVisible() then orbPop(cb, v + 1) end
		end
		cb.spLast = v
		cb:SetValue(v)
		cb:Show()
		local anim = cb.spOrbs and animOn(settings, cb.spWhich or 1)
			and (sample or SP.shieldChargesDemoActive or not (SPCompat and SPCompat.secretsRegime))   -- Forever: the gates draw them
		stormModels(cb, anim and v or 0, s)
	end
	-- When It's Gone: at 0 charges / no shield, on the icon. Out of a fight (and the page's
	-- sample) the display knows; in a fight on WoW: Forever only the Cooldown Manager's word counts
	local gone
	if restricted then
		gone = (iconWhich ~= 3) and goneHook.bound and goneHook.anyUp == false or false
	else
		gone = not present
		if iconWhich ~= 3 and not sample then goneHook.anyUp = present and true or false end
	end
	goneEffect(frame, iconWhich or 1, s, (icon and own and gone) and true or false)
end

-- The engine draws the count and never shows us the number, but it applies a
-- NumericRuleFormatter we hand it first (CustomAuraButtonApplicationCountOptions
-- .formatter, per the client's own API docs). One breakpoint per count decides
-- the text and colour, which is how 1 gets drawn at all: by default the client
-- hides a count of 1, the way stack counts work everywhere else.
local function chargeFormatter(maxCharges, isES)
	if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter) then return nil end
	local ok, fmt = pcall(C_StringUtil.CreateNumericRuleFormatter)
	if not ok or not fmt or not fmt.AddBreakpoint then return nil end
	for n = 0, maxCharges do
		local cr, cg, cb = ShamanPower:GetShieldChargeColor(n, maxCharges, isES)
		pcall(fmt.AddBreakpoint, fmt, {
			threshold = n,
			format = ("|cff%02x%02x%02x%%d|r"):format(
				math.floor(cr * 255 + 0.5), math.floor(cg * 255 + 0.5), math.floor(cb * 255 + 0.5)),
		})
	end
	return fmt
end

-- The engine's button gets the same parts as the display frame (icon, number,
-- bar), laid out by the same placeParts, all before any of them is handed to
-- the game: the game fills in the icon, the count and the bar's value itself.
local function buildChargeContainer(frame, kind, scale, sets, icon, number, corner, bar, barSide)
	if C_AddOns and C_AddOns.LoadAddOn then pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer") end
	local ok, container = pcall(CreateFrame, "AuraContainer", nil, frame, "CustomAuraContainerTemplate")
	if not ok or not container then return nil end
	container:SetAllPoints(frame)
	container:SetFrameLevel(frame:GetFrameLevel() + 2)
	local isES = (kind == "earth")
	local maxCharges, c = MAX_CHARGES[kind], SHIELD_COLOR[kind]
	local interpolation = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate
	for _, set in ipairs(sets) do
		local idMap = {}
		for _, id in ipairs(set.ids) do idMap[id] = true end
		local which = isES and 3 or (set.name == "Water Shield" and 2 or 1)
		pcall(function()
			container:AddAuraSlot("charges_" .. set.name:gsub("%s", ""), "HELPFUL|PLAYER", {
				candidateFilters = { includeSpellIDs = idMap },
				initializeFrame = function(button)
					button:ClearAllPoints()
					button:SetAllPoints(frame)
					if button.SetMouseClickEnabled then pcall(button.SetMouseClickEnabled, button, false) end
					if button.SetMouseMotionEnabled then pcall(button.SetMouseMotionEnabled, button, false) end
					local iconTex, count, chargeBar
					if icon then
						-- this shield's own file, so the icon never depends on the game painting it
						iconTex = button:CreateTexture(nil, "ARTWORK")
						iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
						iconTex:SetTexture(shieldIcon(which))
					end
					if bar then chargeBar = createChargeBar(button, kind, which) end
					if number then
						local carrier = CreateFrame("Frame", nil, button)
						carrier:SetAllPoints(button)
						count = carrier:CreateFontString(nil, "OVERLAY")
						SP:SetSPFont(count, "charges", numberSize(icon, corner) * scale, "OUTLINE")
						SP:SPFontGameOwned(count)   -- (on the game's button: a font change waits out fights and hidden auras)
						count:SetTextColor(c[1], c[2], c[3])   -- fallback if the formatter is unavailable
					end
					-- on the display frame, not the button: the game's container re-anchors the button to
					-- its own corner (its flow layout clears every point), which moved the kit's bar over
					-- the icon in a fight; anchored to the frame, the kit sits exactly on the display
					placeParts(frame, scale, icon, number, corner, iconTex, count, chargeBar, barSide)
					if iconTex then pcall(button.SetIcon, button, iconTex) end
					if chargeBar then
						pcall(button.SetApplicationBar, button, chargeBar,
							{ maxApplications = maxCharges, minApplications = 0, interpolation = interpolation })
					end
					if count then
						pcall(button.SetApplicationCount, button, count,
							{ formatter = chargeFormatter(maxCharges, isES) })
					end
				end,
			})
		end)
	end
	container:Hide()
	return container
end

-- Group token of the player carrying your Earth Shield (nil if not in view)
function SP:EarthShieldTargetToken()
	local guid = ShamanPower.esTrackedTargetGUID
	if not guid then return nil end
	local tokens = { "player" }
	for i = 1, 4 do tokens[#tokens + 1] = "party" .. i end
	if IsInRaid() then for i = 1, 40 do tokens[#tokens + 1] = "raid" .. i end end
	for _, u in ipairs(tokens) do
		if UnitExists(u) and UnitGUID(u) == guid then return u end
	end
	return nil
end

-- Make sure each frame has an engine container for the current look and unit.
-- The engine button's parts are laid out once, when the game builds it: a new
-- scale or a different set of parts (icon, number, corner, bar) needs a new one.
-- Each shield's display has its own layer, built with that shield's own settings,
-- and only OUT OF COMBAT: a setting changed in a fight keeps the layer it has
-- until the fight ends (the end of combat wakes the update, which builds it).
local SET_NAME = { "Lightning Shield", "Water Shield" }
function SP:EnsureShieldChargeEngine(frame, kind, scale)
	if not (SPCompat and SPCompat.secretsRegime) then return end
	local which = frame.spWhich or ((kind == "earth") and 3 or 1)
	local settings = shieldView(which)
	local icon, number, corner, bar, barSide = displayParts(settings)
	local orbs = orbSig(settings, which)
	if frame.engine and (frame.engineScale ~= scale or frame.engineIcon ~= icon or frame.engineNumber ~= number
		or frame.engineCorner ~= corner or frame.engineBar ~= bar or frame.engineTheme ~= themeStamp
		or frame.engineBarSide ~= barSide or frame.engineOrbs ~= orbs) and not InCombatLockdown() then
		frame.engine:Hide()
		pcall(frame.engine.SetUnit, frame.engine, "none")   -- the old one stops following auras
		frame.engine = nil
	end
	if not frame.engine and not InCombatLockdown() then
		-- Lightning / Water Shield: blue, like the module at full charges; Earth Shield: green
		local sets
		if kind == "earth" then
			sets = { { name = "Earth Shield", ids = ES_SPELL_IDS } }
		else
			sets = {}
			for _, set in ipairs(ShamanPower.ShieldAuraSets or {}) do
				if set.name == SET_NAME[which] then sets[#sets + 1] = set end
			end
		end
		frame.engine = buildChargeContainer(frame, kind, scale, sets, icon, number, corner, bar, barSide)
		frame.engineScale = scale
		frame.engineIcon, frame.engineNumber, frame.engineCorner, frame.engineBar = icon, number, corner, bar
		frame.engineBarSide = barSide
		frame.engineOrbs = orbs
		frame.engineTheme = themeStamp
		frame.engineUnit = nil
	end
	if not self.shieldChargesDemoActive then ensureGates(frame, kind, settings, scale) end
	local c = frame.engine
	if not c then return end
	local unit = (kind == "player") and "player" or (self:EarthShieldTargetToken() or "none")
	if frame.engineUnit ~= unit then
		frame.engineUnit = unit
		pcall(c.SetUnit, c, unit)
		pcall(c.UpdateAllAuras, c)
	end
end

-- WoW: Forever reads the player's shield by name: one aura table when it is up,
-- none when it is not. Reading buffs one by one there (UnitBuff, SPCompat) makes a
-- table for EVERY buff the player has, on every aura change. The Classic line
-- keeps its own loop, which makes no tables.
local GetAuraByName = (SPCompat.FOREVER) and C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName or nil

-- ...and only when the SHIELD changed: the game says which auras each update
-- added, changed or removed, so any other buff coming or going costs nothing.
-- known = false means "read it again on the next update" (at login, after a
-- full update, and whenever auras were secret: in combat the game draws the
-- count itself and nothing here is read).
local shield = { known = false, id = nil, has = false, charges = 0, water = false }
-- in combat the game hides auras' contents (secret values): nothing hidden is
-- ever tested, only "read again once it can be read"
local secret = issecretvalue or function() return false end
local LS_IDS, WS_IDS = { 324 }, { 24398, 33736, 408510, 408511, 409941, 52127 }
for _, set in ipairs(SP.ShieldAuraSets or {}) do
	if set.name == "Lightning Shield" then LS_IDS = set.ids elseif set.name == "Water Shield" then WS_IDS = set.ids end
end

-- ShieldGoneHooks (WoW: Forever): in a fight the game hides whether a shield is up, but the
-- game's own Cooldown Manager item for Lightning / Water Shield runs TriggerAuraRemovedAlert
-- the moment the shield goes and TriggerAuraAppliedAlert when one is up, with no secret in
-- hand (read-only review of Blizzard_CooldownViewer, 2026-10-08). Only "the method ran on an
-- item that carries a shield" is used: never a value out of the item. Items are pooled and
-- handed other cooldowns on every layout, so the shield is checked again at each firing and
-- the hooks are bound again after each layout (RefreshLayout). Earth Shield has no item.
local HOOK_VIEWERS = { "EssentialCooldownViewer", "UtilityCooldownViewer", "BuffIconCooldownViewer", "BuffBarCooldownViewer" }
local hookedItems = setmetatable({}, { __mode = "k" })
local function plainNumber(v) return type(v) == "number" and not (issecretvalue and issecretvalue(v)) end
local function inIDs(ids, sid)
	if not plainNumber(sid) then return false end
	for _, x in ipairs(ids) do if x == sid then return true end end
	return false
end
local function itemShield(item)
	if not (item.GetCooldownID and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo) then return nil end
	local ok, id = pcall(item.GetCooldownID, item)
	if not ok or not plainNumber(id) then return nil end
	local ok2, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, id)
	if not ok2 or type(info) ~= "table" then return nil end
	if inIDs(LS_IDS, info.spellID) or inIDs(LS_IDS, info.overrideSpellID) then return 1 end
	if inIDs(WS_IDS, info.spellID) or inIDs(WS_IDS, info.overrideSpellID) then return 2 end
	if type(info.linkedSpellIDs) == "table" then
		for _, x in ipairs(info.linkedSpellIDs) do
			if inIDs(LS_IDS, x) then return 1 end
			if inIDs(WS_IDS, x) then return 2 end
		end
	end
	return nil
end
local function shieldEvent(item, up)
	local w = itemShield(item)
	if SP.shieldHookDebug then print("ShamanPower debug: Cooldown Manager hook", up and "applied" or "removed", "shield", tostring(w)) end
	if not w then return end
	goneHook.bound = true
	goneHook.up[w] = up and true or false
	-- a shield is up when one was seen up; none when every shield seen is down (per shield: a swap is not a loss)
	local any = false
	for _, v in pairs(goneHook.up) do if v then any = true end end
	goneHook.anyUp = any
	if up then SP._shieldLastWater = (w == 2) end   -- (the shield seen last: its look once it is gone)
	if SP.UpdateShieldChargeDisplays then SP:UpdateShieldChargeDisplays() end
	if SP.ExpiringAlertShieldHook then SP:ExpiringAlertShieldHook(w, up) end   -- Expiring Alerts' shield-gone alert, in a fight too
end
-- Is the hook wanted at all: a shield's When It's Gone effect is on, or Expiring Alerts' shield alerts
local function hookWanted()
	local sv = SP.opt and SP.opt.shieldChargeDisplay or NO_SETTINGS
	for w = 1, 2 do
		local fx = sv[KEY[w].goneEffect]
		if fx and fx ~= "none" then return true end
	end
	return SP.ExpiringAlertShieldsOn and SP:ExpiringAlertShieldsOn() or false
end
-- The Cooldown Manager's own shield icon is hidden (alpha 0: the item stays alive, so its hooks
-- still fire), ShamanPower draws the shield; shown again while the Cooldown Settings window is
-- open, so the player can still manage it there. Re-applied after each layout.
local hiddenItems = setmetatable({}, { __mode = "k" })
local hookedViewers = setmetatable({}, { __mode = "k" })
local function settingsOpen() return CooldownViewerSettings and CooldownViewerSettings.IsVisible and CooldownViewerSettings:IsVisible() end
local function editModeOn() return EditModeManagerFrame and EditModeManagerFrame.IsEditModeActive and EditModeManagerFrame:IsEditModeActive() or false end
local function hideShieldItem(item, hide)
	if hide and not settingsOpen() and not editModeOn() then
		hiddenItems[item] = true
		pcall(item.SetAlpha, item, 0)   -- (every pass: a re-laid item comes back at full alpha)
	elseif hiddenItems[item] then
		hiddenItems[item] = nil; pcall(item.SetAlpha, item, 1)
	end
end
-- does the player know this shield (any rank)?
local function knowsShield(w)
	local c = shieldKnown[w]
	if c ~= nil then return c end
	c = false
	for _, id in ipairs(w == 1 and LS_IDS or WS_IDS) do
		if SPCompat and SPCompat.KnowsSpellID and SPCompat.KnowsSpellID(id) then c = true break end
	end
	shieldKnown[w] = c
	return c
end
local queueBind   -- (below) one bind pass next frame, however many layouts asked
local function bindShieldHooks()
	if not (SPCompat and SPCompat.FOREVER and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo) then return end
	-- the hooks are bound whenever the viewers exist (they cost nothing); the hide only while
	-- something uses the signal and ShamanPower is on
	local wanted = hookWanted() and not SP:IsOff()
	local have = goneHook.have
	have[1], have[2] = nil, nil
	for _, name in ipairs(HOOK_VIEWERS) do
		local v = _G[name]
		local pool = v and v.itemFramePool
		if pool and pool.EnumerateActive then
			if not hookedViewers[v] then
				hookedViewers[v] = true
				hooksecurefunc(v, "RefreshLayout", queueBind)
				-- a layout change with the same item count hands items other cooldowns in place (no RefreshLayout)
				if v.OnCooldownDataChanged then hooksecurefunc(v, "OnCooldownDataChanged", queueBind) end
			end
			local ok, iter, st, init = pcall(pool.EnumerateActive, pool)
			if ok and type(iter) == "function" then
				for item in iter, st, init do
					if not hookedItems[item] and item.TriggerAuraRemovedAlert and item.TriggerAuraAppliedAlert then
						hookedItems[item] = true
						hooksecurefunc(item, "TriggerAuraRemovedAlert", function(it) shieldEvent(it, false) end)
						hooksecurefunc(item, "TriggerAuraAppliedAlert", function(it) shieldEvent(it, true) end)
					end
					local w = itemShield(item)
					if w then have[w] = true end
					hideShieldItem(item, wanted and w ~= nil and SP.opt ~= nil and SP.opt.cdmHideShieldIcon == true)   -- (only once the player took ShamanPower's setup, or turned the switch on)
				end
			end
		end
	end
	-- no item carries a shield: the observation is gone, back to unknown (the fight-time
	-- display then says nothing it cannot know); one carries it again: the next firing says more
	if not (have[1] or have[2]) then
		if goneHook.bound then goneHook.bound, goneHook.anyUp = false, nil; goneHook.up[1], goneHook.up[2] = nil, nil end
	elseif not goneHook.bound then
		goneHook.bound = true
	end
	if not goneHook.settingsWatch and EventRegistry and EventRegistry.RegisterCallback then
		goneHook.settingsWatch = true
		-- the Cooldown Settings window and Edit Mode: the shield icon back while they are open, hidden again after
		for _, ev in ipairs({ "CooldownViewerSettings.OnShow", "CooldownViewerSettings.OnHide", "EditMode.Enter", "EditMode.Exit" }) do
			pcall(EventRegistry.RegisterCallback, EventRegistry, ev, queueBind, goneHook)
		end
	end
	-- the one ask, once a session: a shield the player knows, that something needs, with no item of
	-- its own in the player's layout. Never moved by the addon: writing the game's settings tables
	-- from an addon taints the Cooldown Manager for the whole session (measured 2026-10-09)
	if wanted and not goneHook.asked and not (SP.opt and SP.opt.cdmShieldDeclined) and not InCombatLockdown() and not settingsOpen() and SP.ShowSPDialog then
		local missing = (knowsShield(1) and not have[1]) or (knowsShield(2) and not have[2])
		if missing then
			goneHook.asked = true
			SP:ShieldGoneAsk()
		end
	end
end
queueBind = function()
	if goneHook.bindQueued then return end
	goneHook.bindQueued = true
	C_Timer.After(0, function() goneHook.bindQueued = nil; bindShieldHooks() end)
end
function SP:ShieldGoneBindQueue() queueBind() end
-- the one-time ask: the step the player does once in the game's Cooldown Manager
function SP:ShieldGoneAsk()
	local avail = true
	if C_CooldownViewer and C_CooldownViewer.IsCooldownViewerAvailable then
		local ok, a = pcall(C_CooldownViewer.IsCooldownViewerAvailable)
		if ok and a == false then avail = false end
	end
	if not avail then
		self:ShowSPDialog({
			key = "cdmShield",
			title = "The Cooldown Manager is off here",
			text = "To see your shield go in a fight on WoW: Forever, ShamanPower listens to the game's own Cooldown Manager, and the game has it turned off for this character or realm. That part cannot work here; everything else does.",
			buttons = { { text = "Got It" } },
		})
		return
	end
	self:ShowSPDialog({
		key = "cdmShield",
		title = "One reload for your shield in fights",
		text = "To see your shield go in a fight on WoW: Forever, ShamanPower listens to the game's own Cooldown Manager. It can set that up for you now: turn the Cooldown Manager on if it is off, switch it to a layout of ShamanPower's own that tracks only your shield and shows nothing else on screen (ShamanPower draws the shield), and reload the UI once. Your other Cooldown Manager layouts stay as they are.",
		buttons = {
			{ text = "Set It Up And Reload", onClick = function()
				local ok, why = SP:ShieldGoneSetup()
				if ok then
					if C_UI and C_UI.Reload then C_UI.Reload() elseif ReloadUI then ReloadUI() end
				else
					print("|cff0070ddShamanPower|r: could not set the Cooldown Manager up (" .. tostring(why) .. "). By hand: in the Cooldown Manager's settings, drag Lightning Shield and Water Shield from Not Displayed into Tracked Buffs, then close the window.")
				end
			end },
			-- Not Now is kept: never asked again (the Shield Charges page has a button to come back to it)
			{ text = "Not Now", onClick = function() if SP.opt then SP.opt.cdmShieldDeclined = true end end },
		},
	})
end
SP.BindShieldGoneHooks = bindShieldHooks
-- the Cooldown Manager holds a shield of the player's (the Shield Charges page's setup button hides then)
function SP:ShieldGoneCdmReady()
	if not (goneHook.have[1] or goneHook.have[2]) then return false end
	for w = 1, 2 do if knowsShield(w) and not goneHook.have[w] then return false end end   -- (every shield you know is tracked)
	return true
end
-- the page's button: the offer again, whatever was answered before
function SP:ShieldGoneOffer()
	if self.opt then self.opt.cdmShieldDeclined = nil end
	goneHook.asked = true
	self:ShieldGoneAsk()
end

-- ---------------------------------------------------------------------------
-- The Cooldown Manager's saved layout string (an owner experiment, 2026-10-10; G's report
-- section 4): read it, write Lightning Shield into Tracked Buffs through the game's own
-- C_CooldownViewer.SetLayoutData (the encoded save string, never the live tables, which
-- taint), restore it. Only ever run by hand (/run); the addon never calls these itself.
-- Format: "1|" + Base64(Deflate(CBOR(store))); store[1] = save format (5), store[2] =
-- { [classSpecTag] = activeLayoutID }, store[3] = { [tag] = { [layoutID] = { [1] = ordered
-- cooldownIDs, [2] = { [category] = { cooldownIDs } }, [3] = alerts, [4], [5] } } },
-- store[4] = { [layoutID] = name }. Tag = classID * 10 + specialization index.
-- ---------------------------------------------------------------------------
local CDM_LS = 200311   -- Lightning Shield's cooldownID in the shaman set
local function cdmDecode(str)
	if type(str) ~= "string" then return nil, "no layout string" end
	local ver, payload = str:match("^(%d+)|(.*)$")
	if ver ~= "1" then return nil, "encoding version " .. tostring(ver) end
	local E = C_EncodingUtil
	if not (E and E.DecodeBase64 and E.DecompressString and E.DeserializeCBOR) then return nil, "no C_EncodingUtil" end
	local ok, data = pcall(function() return E.DeserializeCBOR(E.DecompressString(E.DecodeBase64(payload), Enum.CompressionMethod.Deflate)) end)
	if not ok or type(data) ~= "table" then return nil, "decode failed: " .. tostring(data) end
	return data
end
local function cdmEncode(data)
	local E = C_EncodingUtil
	local ok, out = pcall(function() return "1|" .. E.EncodeBase64(E.CompressString(E.SerializeCBOR(data), Enum.CompressionMethod.Deflate)) end)
	if not ok then return nil, tostring(out) end
	return out
end
local function cdmTag()
	local classID = select(3, UnitClass("player"))
	local spec = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization and C_SpecializationInfo.GetSpecialization())
		or (GetSpecialization and GetSpecialization()) or 0
	return (classID or 0) * 10 + (tonumber(spec) or 0)
end
function SP:CdmLayoutRead()
	if not (C_CooldownViewer and C_CooldownViewer.GetLayoutData) then print("ShamanPower CDM: no GetLayoutData on this client") return end
	local str = C_CooldownViewer.GetLayoutData()
	local data, err = cdmDecode(str)
	if not data then print("ShamanPower CDM: " .. tostring(err)) return end
	local tag = cdmTag()
	local active = type(data[2]) == "table" and data[2][tag] or nil
	local layouts = type(data[3]) == "table" and data[3][tag] or nil
	local layout = (layouts and active) and layouts[active] or nil
	local n = 0
	if layouts then for _ in pairs(layouts) do n = n + 1 end end
	local name = (type(data[4]) == "table" and active) and data[4][active] or nil
	print(("ShamanPower CDM: format %s, tag %s, active layout %s (%s), layouts for this spec %d, string %d chars"):format(
		tostring(data[1]), tostring(tag), tostring(active), tostring(name or "default"), n, #(str or "")))
	if not layout then
		print("ShamanPower CDM: the active layout is the default one, which the string cannot carry. In the Cooldown Manager settings make a layout of your own (its layout menu), keep it active, close the window, then run this again.")
		return
	end
	local cats = type(layout[2]) == "table" and layout[2] or {}
	local where = {}
	for cat, list in pairs(cats) do
		if type(list) == "table" then
			for _, id in ipairs(list) do if id == CDM_LS then where[#where + 1] = tostring(cat) end end
		end
	end
	local hp = Enum and Enum.CooldownViewerCategory and Enum.CooldownViewerCategory.HiddenPassive
	print("ShamanPower CDM: Lightning Shield (200311) override category: " .. (#where > 0 and table.concat(where, ", ") or "none (its default, Tracked Buffs)")
		.. "  [Tracked Buffs = 2, Not Displayed = " .. tostring(hp) .. "]")
	local alerts = 0
	if type(layout[3]) == "table" then for _ in pairs(layout[3]) do alerts = alerts + 1 end end
	print(("ShamanPower CDM: order list %d ids, alert overrides on %d cooldowns, hidden group buffs %s"):format(
		type(layout[1]) == "table" and #layout[1] or 0, alerts, tostring(layout[4] ~= nil)))
	return data, str, tag, active, layout
end
function SP:CdmLayoutWrite()
	local data, str, tag, active, layout = self:CdmLayoutRead()
	if not (data and layout) then return end
	if not (C_CooldownViewer and C_CooldownViewer.SetLayoutData) then print("ShamanPower CDM: no SetLayoutData") return end
	self.opt.cdmLayoutBackup = str   -- (back: /run ShamanPower:CdmLayoutRestore())
	if type(layout[2]) ~= "table" then layout[2] = {} end
	for cat, list in pairs(layout[2]) do
		if type(list) == "table" then
			for i = #list, 1, -1 do if list[i] == CDM_LS then table.remove(list, i) end end
			if #list == 0 then layout[2][cat] = nil end
		end
	end
	local tb = layout[2][2]
	if type(tb) ~= "table" then tb = {}; layout[2][2] = tb end
	tb[#tb + 1] = CDM_LS
	if type(layout[1]) == "table" then
		local found = false
		for _, id in ipairs(layout[1]) do if id == CDM_LS then found = true break end end
		if not found then table.insert(layout[1], CDM_LS) end
	end
	local out, err = cdmEncode(data)
	if not out then print("ShamanPower CDM: encode failed: " .. tostring(err)) return end
	local ok, e2 = pcall(C_CooldownViewer.SetLayoutData, out)
	if not ok then print("ShamanPower CDM: SetLayoutData refused: " .. tostring(e2)) return end
	local back = C_CooldownViewer.GetLayoutData()
	print("ShamanPower CDM: written, " .. #out .. " chars; readback " .. (back == out and "matches" or "DIFFERS") .. ". Now /reload, then /run ShamanPower:CdmLayoutRead()")
end
function SP:CdmLayoutRestore()
	local b = self.opt.cdmLayoutBackup
	if type(b) ~= "string" then print("ShamanPower CDM: no backup saved") return end
	local ok, e = pcall(C_CooldownViewer.SetLayoutData, b)
	print("ShamanPower CDM: restore " .. (ok and "written; now /reload" or ("refused: " .. tostring(e))))
	if ok then self.opt.cdmLayoutBackup = nil end
end

-- the shields' cooldownIDs in the game's catalog (ordinary values, read out of a fight)
local function cdmShieldIDs()
	local out = {}
	local C = C_CooldownViewer
	if not (C and C.GetCooldownViewerCategorySet and C.GetCooldownViewerCooldownInfo and Enum and Enum.CooldownViewerCategory) then return out end
	local ok, ids = pcall(C.GetCooldownViewerCategorySet, Enum.CooldownViewerCategory.TrackedBuff, false)
	if not ok or type(ids) ~= "table" then return out end
	for _, id in ipairs(ids) do
		if plainNumber(id) then
			local ok2, info = pcall(C.GetCooldownViewerCooldownInfo, id)
			if ok2 and type(info) == "table" then
				local w
				if inIDs(LS_IDS, info.spellID) or inIDs(LS_IDS, info.overrideSpellID) then w = 1
				elseif inIDs(WS_IDS, info.spellID) or inIDs(WS_IDS, info.overrideSpellID) then w = 2 end
				if not w and type(info.linkedSpellIDs) == "table" then
					for _, x in ipairs(info.linkedSpellIDs) do
						if inIDs(LS_IDS, x) then w = 1 break end
						if inIDs(WS_IDS, x) then w = 2 break end
					end
				end
				if w and not out[w] then out[w] = id end
			end
		end
	end
	return out
end

-- The setup the dialog offers (ShieldGoneAsk): the Cooldown Manager on, and a layout of
-- ShamanPower's own made active, through the game's own saved string (SetLayoutData; measured
-- clean 2026-10-10: the live tables taint, the string does not). That layout tracks ONLY the
-- shields the player knows, in Tracked Buffs; every other cooldown and buff of the game's
-- catalog sits in Not Displayed, so the Cooldown Manager draws nothing of its own on screen
-- (the shield item itself is hidden by ShamanPower, which draws the shield). A layout named
-- ShamanPower is reused; else one is made the way the game makes one (the next free ID, a
-- name, active for this class and spec). The player's other layouts stay as they are, and the
-- string before is kept in the profile (CdmLayoutRestore). Answers: done, or why not.
function SP:ShieldGoneSetup()
	if InCombatLockdown() then return false, "in a fight" end
	local C = C_CooldownViewer
	if not (C and C.GetLayoutData and C.SetLayoutData and C.GetCooldownViewerCategorySet) then return false, "this game has no layout string" end
	local getCVar = (C_CVar and C_CVar.GetCVar) or GetCVar
	local setCVar = (C_CVar and C_CVar.SetCVar) or SetCVar
	if getCVar and setCVar then
		local ok, v = pcall(getCVar, "cooldownViewerEnabled")
		if ok and (v == "0" or v == 0) then pcall(setCVar, "cooldownViewerEnabled", "1") end
	end
	local ids = cdmShieldIDs()
	local want = {}
	if ids[1] and knowsShield(1) then want[ids[1]] = true end
	if ids[2] and knowsShield(2) then want[ids[2]] = true end
	if not next(want) then return false, "the game's catalog has no shield you know" end
	local str = C.GetLayoutData()
	local data, err = cdmDecode(str)
	if not data then
		if type(str) ~= "string" or str == "" then data = { [1] = 5, [2] = {}, [3] = {}, [4] = {} }   -- (never saved: a store from nothing)
		else return false, err end
	end
	if data[1] ~= 5 then return false, "save format " .. tostring(data[1]) .. " (ShamanPower knows 5)" end
	for k = 2, 4 do if type(data[k]) ~= "table" then data[k] = {} end end
	local tag = cdmTag()
	if type(data[3][tag]) ~= "table" then data[3][tag] = {} end
	local layouts = data[3][tag]
	-- ShamanPower's layout for this class and spec: the one named so, else a new one
	local id, created
	for lid, name in pairs(data[4]) do
		if name == "ShamanPower" and type(lid) == "number" and layouts[lid] then id = lid break end
	end
	if not id then
		local count, maxID = 0, 0
		for _, perTag in pairs(data[3]) do
			if type(perTag) == "table" then
				for lid in pairs(perTag) do count = count + 1; if type(lid) == "number" and lid > maxID then maxID = lid end end
			end
		end
		for lid in pairs(data[4]) do if type(lid) == "number" and lid > maxID then maxID = lid end end
		if count >= 5 then return false, "the Cooldown Manager already has its 5 layouts" end
		id = maxID + 1
		layouts[id] = {}
		data[4][id] = "ShamanPower"
		created = true
	end
	local layout = layouts[id]
	data[2][tag] = id   -- (active for this class and spec)
	-- its categories, built from the game's catalog: the shields in Tracked Buffs (2), all else
	-- Not Displayed (the game's two hidden pseudo-categories)
	local E = Enum and Enum.CooldownViewerCategory or {}
	local hiddenActive, hiddenPassive = E.HiddenActive or -1, E.HiddenPassive or -2
	local over = {}
	local function list(cat) local t = over[cat]; if not t then t = {}; over[cat] = t end return t end
	for _, cat in ipairs({ E.Essential or 0, E.Utility or 1, E.TrackedBuff or 2, E.TrackedBar or 3 }) do
		local ok, set = pcall(C.GetCooldownViewerCategorySet, cat, false)
		if ok and type(set) == "table" then
			local hidden = (cat == (E.Essential or 0) or cat == (E.Utility or 1)) and hiddenActive or hiddenPassive
			for _, cid in ipairs(set) do
				if plainNumber(cid) then
					if want[cid] then local t = list(E.TrackedBuff or 2); t[#t + 1] = cid
					else local t = list(hidden); t[#t + 1] = cid end
				end
			end
		end
	end
	if created then
		layout[2] = over
	else
		-- the layout exists (made before, maybe added to by the player since): only the shields move,
		-- into Tracked Buffs and out of every other list; the rest of it stays theirs
		if type(layout[2]) ~= "table" then layout[2] = {} end
		for cat, lst in pairs(layout[2]) do
			if type(lst) == "table" then
				for i = #lst, 1, -1 do if want[lst[i]] then table.remove(lst, i) end end
				if #lst == 0 then layout[2][cat] = nil end
			end
		end
		local tb = layout[2][E.TrackedBuff or 2]
		if type(tb) ~= "table" then tb = {}; layout[2][E.TrackedBuff or 2] = tb end
		for cid in pairs(want) do tb[#tb + 1] = cid end
	end
	local out, e = cdmEncode(data)
	if not out then return false, e end
	self.opt.cdmLayoutBackup = str   -- (the string before: /run ShamanPower:CdmLayoutRestore())
	local ok, e2 = pcall(C.SetLayoutData, out)
	if not ok then return false, tostring(e2) end
	if C.GetLayoutData() ~= out then return false, "the game did not keep the string" end
	self.opt.cdmHideShieldIcon = true   -- (the player took ShamanPower's layout: its own shield display takes the icon's place)
	return true
end
-- a trace: what each Cooldown Manager item says it carries (ordinary values only; a secret
-- prints as "secret"), and the shield IDs the hook is looking for
function SP:ShieldGoneHookDump()
	local function show(v) if v == nil then return "-" end if issecretvalue and issecretvalue(v) then return "secret" end return tostring(v) end
	print("ShamanPower debug: shield IDs LS", table.concat(LS_IDS, ","), "WS", table.concat(WS_IDS, ","))
	print("ShamanPower debug: cvar cooldownViewerEnabled=" .. tostring(GetCVar and GetCVar("cooldownViewerEnabled")) .. " available=" .. tostring(C_CooldownViewer and C_CooldownViewer.IsCooldownViewerAvailable and C_CooldownViewer.IsCooldownViewerAvailable()))
	for _, name in ipairs(HOOK_VIEWERS) do
		local v = _G[name]
		local pool = v and v.itemFramePool
		-- the viewer's own ordered list (the game's data, not the item's)
		if v and v.GetCooldownIDs then
			local okl, ids = pcall(v.GetCooldownIDs, v)
			local parts = {}
			if okl and type(ids) == "table" then
				for i, id in ipairs(ids) do
					local sp = "?"
					if plainNumber(id) and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
						local oki, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, id)
						if oki and type(info) == "table" then sp = show(info.spellID) .. "/" .. show(info.overrideSpellID) end
					end
					parts[#parts + 1] = i .. ":" .. show(id) .. "=" .. sp
				end
			end
			print(name:gsub("CooldownViewer", "") .. " list: " .. (okl and table.concat(parts, " ") or ("err " .. tostring(ids))))
		end
		if pool and pool.EnumerateActive then
			local ok, iter, st, init = pcall(pool.EnumerateActive, pool)
			if ok and type(iter) == "function" then
				local i = 0
				for item in iter, st, init do
					i = i + 1
					local okc, cd = pcall(item.GetCooldownID, item)
					local line = name:gsub("CooldownViewer", "") .. "#" .. i .. " cd=" .. (okc and show(cd) or "err") .. " idx=" .. show(rawget(item, "layoutIndex")) .. " raw=" .. show(rawget(item, "cooldownID"))
					if okc and plainNumber(cd) and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
						local oki, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cd)
						if oki and type(info) == "table" then
							local linked = {}
							if type(info.linkedSpellIDs) == "table" then for _, x in ipairs(info.linkedSpellIDs) do linked[#linked + 1] = show(x) end end
							line = line .. " spell=" .. show(info.spellID) .. " over=" .. show(info.overrideSpellID) .. " linked=" .. table.concat(linked, ",") .. " aura=" .. show(info.hasAura) .. " self=" .. show(info.selfAura)
						else
							line = line .. " info=" .. tostring(info)
						end
					end
					print(line)
				end
			end
		end
	end
end
-- the hook's state, for a trace: bound, a shield up, hooked items, each viewer's active items
function SP:ShieldGoneHookState()
	local n = 0
	for _ in pairs(hookedItems) do n = n + 1 end
	local parts = {}
	for _, name in ipairs(HOOK_VIEWERS) do
		local v = _G[name]
		local pool = v and v.itemFramePool
		local count = pool and pool.GetNumActive and pool:GetNumActive() or (pool and "?" or "nopool")
		parts[#parts + 1] = name:gsub("CooldownViewer", "") .. "=" .. tostring(v and count or "nil")
	end
	return goneHook.bound, goneHook.anyUp, n, table.concat(parts, " ")
end
local function FindShieldAura(ids)
	local name = SPCompat.AuraFamilyName(ids)
	if name then return GetAuraByName("player", name, "HELPFUL") end
	-- A client with no readable family name can still answer a known rank ID.
	local byID = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
	if not byID then return nil end
	for _, id in ipairs(ids) do
		local a = byID(id)
		if secret(a) then return a end
		if a then return a end
	end
end
if GetAuraByName then
	local function has(list, id)   -- true when the list holds id, or can't be read
		if secret(list) then return true end
		if not list then return false end
		for i = 1, #list do
			local v = list[i]
			if secret(v) or v == id then return true end
		end
		return false
	end
	local watch = CreateFrame("Frame")
	watch:RegisterUnitEvent("UNIT_AURA", "player")
	watch:SetScript("OnEvent", function(_, _, _, info)
		if not shield.known then return end   -- a read is due anyway
		if not info or secret(info) or secret(info.isFullUpdate) or SP:ShieldChargesRestricted() then shield.known = false return end
		if info.isFullUpdate then shield.known = false return end
		local id = shield.id
		if id then
			if has(info.removedAuraInstanceIDs, id) then shield.known = false return end
			if has(info.updatedAuraInstanceIDs, id) then shield.known = false return end   -- a charge used
		end
		local added = info.addedAuras
		if secret(added) then shield.known = false return end
		if added then
			for i = 1, #added do
				local a = added[i]
				if secret(a) then shield.known = false return end
				local name, spellID = a.name, a.spellId
				if secret(name) or secret(spellID) or SPCompat.AuraMatches(name, spellID, LS_IDS)
					or SPCompat.AuraMatches(name, spellID, WS_IDS) then shield.known = false return end
			end
		end
	end)
end

-- a display's spot, set again when it changed (a profile switch, Reset): out of combat
local PF, ON = {}, {}   -- (reused: the update makes no tables)
local function placeFrame(frame)
	if InCombatLockdown() then return end
	local x, y = shieldSpot(frame.spWhich)
	if frame.spSpotX ~= x or frame.spSpotY ~= y then
		frame.spSpotX, frame.spSpotY = x, y
		frame:ClearAllPoints()
		frame:SetPoint("CENTER", UIParent, "CENTER", x, y)
	end
end

function SP:UpdateShieldChargeDisplays()
	-- (ShieldGoneHooks) the binding runs on events (load, each layout, the settings window, Edit Mode); here only
	-- when what wants the signal changed, so a switch flipped in the settings hides or shows the game's icon at once
	if SPCompat and SPCompat.FOREVER then
		local w = hookWanted() and not self:IsOff()
		if w ~= goneHook.lastWanted then goneHook.lastWanted = w; queueBind() end
	end
	if self.shieldChargesDemoActive then return end
	local settings = self.opt.shieldChargeDisplay
	if not settings then return end

	local frames = self.shieldChargeFrames
	-- ShamanPower switched off: no numbers, and the update stops
	if self:IsOff() then
		self:DisableUpdateSubsystem("shieldCharge")
		for _, f in pairs(frames) do f:Hide() end
		return
	end

	-- a shield the player has not learned never draws, whatever its settings say (they can still be set
	-- up); without this, Water Shield's display came up beside Lightning Shield's in a fight with its own parts
	local onLS = self:ShieldOpt("LS", "enabled") and knowsShield(1)
	local onWS = self:ShieldOpt("WS", "enabled") and knowsShield(2)
	-- Enable/disable the shieldCharge subsystem based on settings
	local showAny = onLS or onWS or earthShieldWanted(settings)
	if showAny then
		self:EnableUpdateSubsystem("shieldCharge")
	else
		self:DisableUpdateSubsystem("shieldCharge")
	end

	local lsFrame, wsFrame, earthFrame = frames.player, frames.water, frames.earth
	if not lsFrame or not wsFrame or not earthFrame then return end
	local locked = settings.locked

	-- Check combat state
	local inCombat = InCombatLockdown() or UnitAffectingCombat("player")

	-- Lightning / Water Shield: read once (whichever is up), each drawn on its own display
	if onLS or onWS then
		local charges = 0
		local hasShield = false
		local water = false   -- Water Shield (not Lightning Shield): which display shows it

		local restricted = self:ShieldChargesRestricted()
		local pf, on = PF, ON
		pf[1], pf[2], on[1], on[2] = lsFrame, wsFrame, onLS, onWS
		-- Animated Lightning / Water on WoW: Forever: the per-orb gates are built out of combat
		-- (they track the shield themselves, in and out of combat, once built)
		if SPCompat and SPCompat.secretsRegime and not self.shieldChargesDemoActive then
			for w = 1, 2 do
				if on[w] then local v = shieldView(w); ensureGates(pf[w], "player", v, v.scale) end
			end
		end
		if restricted then
			-- auras are secret: the game draws the count on each shield's display (nothing while it is not up)
			hasShield = true
			for w = 1, 2 do
				if on[w] then self:EnsureShieldChargeEngine(pf[w], "player", shieldView(w).scale) end
			end
		else
			-- Check for Lightning Shield or Water Shield; the answer holds until the next aura event
			if GetAuraByName then
				-- WoW: Forever: the shield by name, only when it changed (see above)
				if not shield.known then
					-- the two shields never stand together: whichever is up
					local a = FindShieldAura(LS_IDS)
					local w = false
					if not secret(a) and not a then
						a = FindShieldAura(WS_IDS)
						if not secret(a) then w = a ~= nil end
					end
					if secret(a) or (a and (secret(a.applications) or secret(a.auraInstanceID))) then
						-- hidden right now: keep what is shown, read again on the next update
					else
						if a then
							local c = a.applications
							if c == nil then c = 3 end   -- as the loop below: no count read = a full shield
							shield.id, shield.has, shield.charges, shield.water = a.auraInstanceID, true, c, w
						else
							shield.id, shield.has, shield.charges, shield.water = nil, false, 0, false
						end
						shield.known = true
					end
				end
				charges, hasShield, water = shield.charges, shield.has, shield.water
			else
			local sc = self._shieldChargeScan
			if not sc then sc = {}; self._shieldChargeScan = sc end
			local core = ShamanPower.shieldCache
			if not SPCompat.FOREVER and core and not core.engineCount and ShamanPower._shieldCheckedGen ~= nil
				and ShamanPower._shieldCheckedGen == (ShamanPower.auraGen and ShamanPower.auraGen["player"] or 0) then
				-- TBC Anniversary: the core's shield check is current (it read the shield, or the
				-- game said nothing about it changed): its answer, not a second read of every
				-- buff (each read builds a ~1.9 KB record there). Same rules as the loop below.
				if core.hasShield then
					local n = core.rawCount
					if n == nil then n = 3 end
					local id = core.shieldID
					charges, hasShield, water = n, true, not secret(id) and type(id) == "number" and id ~= 324
				end
			elseif self.AuraCacheValid and self:AuraCacheValid("player", sc.gen, sc.at) then
				charges, hasShield, water = sc.charges, sc.hasShield, sc.water
			else
			for i = 1, 40 do
				local name, _, count, _, _, _, _, _, _, spellId = UnitBuff("player", i)
				if secret(name) or secret(spellId) or secret(count) then break end
				if not name then break end
				if SPCompat.AuraMatches(name, spellId, LS_IDS) or SPCompat.AuraMatches(name, spellId, WS_IDS) then
					charges = count or 0
					-- If charges is 0 but we have the buff, it might be stored differently
					if charges == 0 then
						-- Try getting it from the 3rd return value directly
						local _, _, c = UnitBuff("player", i)
						charges = c or 3  -- Default to 3 if we can't get count
					end
					hasShield = true
					water = SPCompat.AuraMatches(name, spellId, WS_IDS)
					break
				end
			end
			sc.gen, sc.at, sc.charges, sc.hasShield = ShamanPower.auraGen and ShamanPower.auraGen["player"] or 0, GetTime(), charges, hasShield
			sc.water = water
			end
			end
			-- the icon shown with no shield up (and under the engine's in combat) is the last one seen
			if hasShield then self._shieldLastWater = water end
			-- WoW: Forever: each shield's game layer is built out of combat, before the first
			-- fight, instead of in it. Only while there is none: a built one is kept up to
			-- date by the settings (see below)
			if SPCompat and SPCompat.secretsRegime and not InCombatLockdown() and not self.shieldChargesDemoActive then
				for w = 1, 2 do
					-- (every pass, not only when missing: a part switched off out of a fight, say the charge bar,
					-- rebuilds the kit now, not in the next fight, where it cannot be rebuilt)
					if on[w] then self:EnsureShieldChargeEngine(pf[w], "player", shieldView(w).scale) end
				end
			end
		end
		-- with no shield to read, the last one seen (else the preferred one) shows its gray
		-- look; if that one is hidden, the other one
		local gray = self._shieldLastWater
		if gray == nil then gray = (self.opt.preferredShield == 2) end
		gray = gray and 2 or 1
		if not on[gray] then gray = 3 - gray end
		local upWhich = (hasShield and not restricted) and (water and 2 or 1) or nil

		for w = 1, 2 do
			local frame = pf[w]
			if frame.engine then frame.engine:SetShown(restricted and on[w] and true or false) end
			if on[w] then
				local v = shieldView(w)
				placeFrame(frame)
				-- Determine visibility
				local shouldShow, present
				if restricted then
					shouldShow, present = true, true
				elseif upWhich then
					shouldShow, present = (upWhich == w), true
				else
					shouldShow, present = (gray == w) and not v.hideNoShields, false
				end
				if v.hideOutOfCombat and not inCombat then
					shouldShow = false
				end
				if shouldShow and SP.TownHides and SP:TownHides("sc") and not SP:TownFades() then shouldShow = false end   -- (A27) Hide In Town
				if shouldShow then
					paintDisplay(frame, "player", v, v.scale, (upWhich == w) and charges or 0, present, restricted, w,
						restricted and gray ~= w)
					frame:SetAlpha((v.opacity or 1) * (SP.TownAlphaMul and SP:TownAlphaMul("sc") or 1))   -- (A27)
					frame:EnableMouse(not locked)
					frame:Show()
				else
					frame:Hide()
				end
			else
				frame:Hide()
			end
		end
	else
		lsFrame:Hide()
		wsFrame:Hide()
		if lsFrame.engine then lsFrame.engine:Hide() end
		if wsFrame.engine then wsFrame.engine:Hide() end
	end

	-- Update Earth Shield
	if earthShieldWanted(settings) then
		local charges = 0
		local hasShield = false
		local v = shieldView(3)
		local scale = v.scale
		placeFrame(earthFrame)

		local restricted = self:ShieldChargesRestricted()
		if restricted then
			-- auras are secret: the engine draws the count on the tracked target
			hasShield = ShamanPower.esTrackedTargetGUID ~= nil
			self:EnsureShieldChargeEngine(earthFrame, "earth", scale)
		else
			-- Get Earth Shield charges from FindEarthShieldTarget
			local esTarget, esCharges = self:FindEarthShieldTarget()
			if esTarget and esCharges and esCharges > 0 then
				charges = esCharges
				hasShield = true
			end
			-- the game's layer, built before the first fight (see Lightning / Water above)
			if SPCompat and SPCompat.secretsRegime and not earthFrame.engine and not InCombatLockdown()
				and not self.shieldChargesDemoActive then
				self:EnsureShieldChargeEngine(earthFrame, "earth", scale)
			end
		end
		if earthFrame.engine then earthFrame.engine:SetShown(restricted) end

		-- Determine visibility
		local shouldShow = hasShield or not v.hideNoShields
		if v.hideOutOfCombat and not inCombat then
			shouldShow = false
		end
		if shouldShow and SP.TownHides and SP:TownHides("sc") and not SP:TownFades() then shouldShow = false end   -- (A27) Hide In Town

		if shouldShow then
			paintDisplay(earthFrame, "earth", v, scale, charges, hasShield, restricted, 3)
			earthFrame:SetAlpha((v.opacity or 1) * (SP.TownAlphaMul and SP:TownAlphaMul("sc") or 1))   -- (A27)
			earthFrame:EnableMouse(not locked)
			earthFrame:Show()
		else
			earthFrame:Hide()
		end
	else
		earthFrame:Hide()
	end
end

-- ============================================================================
-- Setup wizard preview: fill both shield frames with sample charge counts
-- ============================================================================
-- Setup-wizard preview: show BOTH numbers with simulated charges being used
-- up (blue/green -> yellow -> red) and the shields re-applied, rendered with
-- the same font/scale/opacity rules and parts (icon, bar) as the live display.
function SP:ShieldChargesDemoRefresh()
	local playerFrame = self.shieldChargeFrames.player
	local earthFrame = self.shieldChargeFrames.earth
	local waterReal = self.shieldChargeFrames.water
	if not playerFrame or not earthFrame then return end
	local d = self.shieldChargesDemoState or { player = 3, earth = 6 }
	-- the demo draws the whole display itself: the game-drawn copy (restricted,
	-- WoW: Forever) keeps the look it was built with, so a changed setting would
	-- show twice; it is put back as the settings say when the demo ends
	for _, f in pairs(self.shieldChargeFrames) do
		if f.engine then f.engine:Hide() end
		for _, set in pairs(f.stormGates or {}) do   -- the demo draws its own effects
			for _, g in ipairs(set) do g:Hide() end
		end
	end

	-- each shield with its own settings (scale, opacity, look ...)
	local ls, ws, es = shieldView(1), nil, nil
	if self:ShieldOpt("LS", "enabled") then
		-- Lightning Shield, like the character on stage; at 0 it shows the no-shield look
		paintDisplay(playerFrame, "player", ls, ls.scale, d.player, d.player > 0, false, 1)
		playerFrame:SetAlpha(ls.opacity)
		playerFrame:EnableMouse(false)
		playerFrame:Show()
	else
		playerFrame:Hide()
	end
	-- the settings preview also shows Water Shield, its own display and bar
	local waterFrame = self.shieldChargeWaterPreview
	local wsOn = self:ShieldOpt("WS", "enabled")
	if waterFrame then
		if self.shieldChargesDemoPane and wsOn then
			ws = shieldView(2)
			waterFrame.spDemoHidden = nil
			paintDisplay(waterFrame, "player", ws, ws.scale, d.player, d.player > 0, false, 2)
			waterFrame:SetAlpha(ws.opacity)
			waterFrame:Show()
		else
			waterFrame.spDemoHidden = true
			waterFrame:Hide()
		end
	end
	-- Unlock UI: Water Shield's own display on its own spot, so it has a box to drag
	if waterReal then
		if self.unlockDemoAll and not self.shieldChargesDemoPane and wsOn and self.IsMasterUnlocked and self:IsMasterUnlocked() then
			ws = shieldView(2)
			paintDisplay(waterReal, "player", ws, ws.scale, d.player, d.player > 0, false, 2)
			waterReal:SetAlpha(ws.opacity)
			waterReal:EnableMouse(false)
			waterReal:Show()
		else
			waterReal:Hide()
		end
	end
	if earthShieldWanted(self.opt.shieldChargeDisplay or NO_SETTINGS) then
		es = shieldView(3)
		paintDisplay(earthFrame, "earth", es, es.scale, d.earth, d.earth > 0, false, 3)
		earthFrame:SetAlpha(es.opacity)
		earthFrame:EnableMouse(false)
		earthFrame:Show()
	else
		earthFrame:Hide()
	end
end

function SP:ShieldChargesDemo(on)
	if on then
		self.shieldChargesDemoPane = self.previewPaneActive and true or nil   -- the settings pane (Water Shield shown too)
		self:CreateShieldChargeDisplays()
		if not (self.shieldChargeFrames.player and self.shieldChargeFrames.earth) then return end
		if self.shieldChargesDemoActive then
			self:ShieldChargesDemoRefresh()   -- re-entrant: options changed
			return
		end
		self.shieldChargesDemoActive = true
		self.shieldChargesDemoState = { player = 3, earth = 6 }
		if self.shieldChargesDemoTicker then self.shieldChargesDemoTicker:Cancel() end
		local tick = 0
		self.shieldChargesDemoTicker = C_Timer.NewTicker(1.2, function()
			if not self.shieldChargesDemoActive then return end
			tick = tick + 1
			local d = self.shieldChargesDemoState
			-- player shield loses a charge every tick; re-applied after 0
			d.player = d.player - 1
			if d.player < 0 then d.player = 3 end
			-- the staged character (preview) acts it out: shield gone at 0, recast brings it back
			if self.PreviewStageEvent then
				if d.player == 0 then self:PreviewStageEvent("cast") elseif d.player == 3 then self:PreviewStageEvent("aura") end
			end
			-- earth shield loses a charge every other tick (it lasts longer)
			if tick % 2 == 0 then
				d.earth = d.earth - 1
				if d.earth < 0 then d.earth = 6 end
			end
			self:ShieldChargesDemoRefresh()
		end)
		self:ShieldChargesDemoRefresh()
	else
		self.shieldChargesDemoActive = nil
		self.shieldChargesDemoPane = nil
		if self.shieldChargeWaterPreview then
			self.shieldChargeWaterPreview.spDemoHidden = true
			self.shieldChargeWaterPreview:Hide()
		end
		if self.shieldChargesDemoTicker then self.shieldChargesDemoTicker:Cancel(); self.shieldChargesDemoTicker = nil end
		self.shieldChargesDemoState = nil
		local settings = self.opt.shieldChargeDisplay
		local locked = settings and settings.locked
		for _, f in pairs(self.shieldChargeFrames) do f:EnableMouse(not locked) end
		self:UpdateShieldChargeDisplays()
	end
end

-- ============================================================================
-- The Shield Charges page's WHAT YOU SEE (3.0.8): one shield's display drawn by
-- the same painter as the real one, with that shield's own settings, on a plain
-- frame of its own (never the real display, which the live preview may be
-- borrowing). No spot, no mouse, no game-drawn copy, nothing on the screen.
-- ============================================================================
local SAMPLE_KIND = { "player", "player", "earth" }
local sampleGen = 0   -- bumped when the real bars restyle (a theme, Charge Colors, a shield's change)
local function SamplesRestyle() sampleGen = sampleGen + 1 end
SP.ShieldSamplesRestyle = SamplesRestyle
function SP:ShieldChargeSample(which, parent)
	self.shieldChargeSamples = self.shieldChargeSamples or {}
	local f = self.shieldChargeSamples[which]
	if not f then
		f = CreateFrame("Frame", nil, parent)
		f.spWhich, f.spKind = which, SAMPLE_KIND[which]
		f:SetSize(60, 60)
		local text = f:CreateFontString(nil, "OVERLAY")
		SP:SetSPFont(text, "charges", 48, "OUTLINE")
		text:SetPoint("CENTER", f, "CENTER", 0, 0)
		f.text = text
		f:EnableMouse(false)
		self.shieldChargeSamples[which] = f
	end
	if parent and f:GetParent() ~= parent then f:SetParent(parent) end
	return f
end

-- a sample with this many charges (0: the shield's no-shield look); a lower count
-- than last time pops the orb, as on screen
function SP:PaintShieldChargeSample(f, charges)
	local v = shieldView(f.spWhich)
	if f.spSampleGen ~= sampleGen then
		f.spSampleGen = sampleGen
		for w, cb in pairs(f.chargeBars or {}) do styleChargeBar(cb, w) end
	end
	paintDisplay(f, f.spKind, v, v.scale, charges, charges > 0, false, f.spWhich, nil, true)
	f:SetAlpha(v.opacity or 1)
end

-- a full shield's charges (Lightning / Water Shield 3, Earth Shield 6)
function SP:ShieldChargeMax(which) return MAX_CHARGES[SAMPLE_KIND[which] or "player"] end

if ShamanPower.RegisterPreview then
	ShamanPower:RegisterPreview("shieldcharges", {
		frames = {
			function()
				if not SP.shieldChargeFrames.player then SP:CreateShieldChargeDisplays() end
				return SP.shieldChargeFrames.player
			end,
			function() return SP:ShieldChargeWaterPreviewFrame() end,   -- Water Shield (the settings preview only)
			function() if ShamanPower.ESTrackerUnavailable then return nil end; return SP.shieldChargeFrames.earth end,
		},
		demo = "SP:ShieldChargesDemo",
		pad = 24,
		-- vertical bars: Lightning, Water and Earth side by side, spaced by their real reach
		row = function()
			for w = 1, 3 do
				local st = shieldView(w)
				if st.showChargeBar and (st.chargeBarDirection == "right" or st.chargeBarDirection == "left") then return true end
			end
			return false
		end,
		extent = function(frame) return SP:ShieldChargeDisplayExtent(frame) end,
		stage = "player",   -- the player's own character behind the number: it floats near them on screen
		stageKit = 292,     -- Lightning Shield's aura visual (SpellVisualEvent kit for spell visual 37, Forever 1.60.1 data)
		stageCastKit = 237275,   -- its cast visual, played once when the demo recasts
	})
end

-- A theme change (General > Themes): the numbers take the new colours on the
-- next paint (woken now), the charge bars at once; the game-drawn displays
-- (WoW: Forever) are rebuilt with them, never in combat.
local THEME_ROLES = { "full", "esfull", "low", "last" }
local themeSeen = { -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1 }
local function ThemeColorsMoved()
	local moved = false
	for i = 1, 4 do
		local r, g, b = ThemeRGB(THEME_ROLES[i])
		r, g, b = r or -1, g or -1, b or -1
		local k = (i - 1) * 3
		if themeSeen[k + 1] ~= r or themeSeen[k + 2] ~= g or themeSeen[k + 3] ~= b then
			themeSeen[k + 1], themeSeen[k + 2], themeSeen[k + 3] = r, g, b
			moved = true
		end
	end
	return moved
end
ThemeColorsMoved()   -- the colours in use now (today's, or a saved theme's), before anything is built
local function RebuildEngineForTheme()
	themeStamp = themeStamp + 1
	for _, f in pairs(SP.shieldChargeFrames) do
		if f.engine then SP:EnsureShieldChargeEngine(f, f.spKind, shieldView(f.spWhich).scale) end
	end
	SP._shieldWake = true
end
if SP.OnThemeChanged then
	SP:OnThemeChanged(function()
		if not ThemeColorsMoved() then return end
		for _, f in pairs(SP.shieldChargeFrames) do
			for w, cb in pairs(f.chargeBars or {}) do styleChargeBar(cb, w) end   -- each shield's own bar
		end
		if SP.ShieldSamplesRestyle then SP.ShieldSamplesRestyle() end   -- the Shield Charges page's samples
		SP._shieldWake = true
		if SP.shieldChargesDemoActive then SP:ShieldChargesDemoRefresh() end
		if SPCompat.FOREVER and SP.ThemeRepaintSoon then
			SP:ThemeRepaintSoon("shieldChargesEngine", RebuildEngineForTheme)
		end
	end)
end

-- Charge Colors or Charge Bar Gradient changed: every charge bar restyles, the
-- engine's too on WoW: Forever (rebuilt out of combat, as a theme change does).
function SP:ShieldChargeStyleChanged()
	SP.chargeStyleGen = (SP.chargeStyleGen or 0) + 1
	for _, f in pairs(SP.shieldChargeFrames) do
		for w, cb in pairs(f.chargeBars or {}) do styleChargeBar(cb, w) end   -- each shield's own bar
	end
	if SP.ShieldSamplesRestyle then SP.ShieldSamplesRestyle() end
	SP._shieldWake = true
	if SP.shieldChargesDemoActive and SP.ShieldChargesDemoRefresh then SP:ShieldChargesDemoRefresh() end
	if SPCompat.FOREVER and SP.ThemeRepaintSoon then
		SP:ThemeRepaintSoon("shieldChargesEngine", RebuildEngineForTheme)
	end
	SP:UpdateShieldChargeDisplays()
end
-- a shield's charge color as shown: its Charge Color, or today's
function SP:ShieldChargeColorOf(which)
	local r, g, b = customChargeColor(SP.opt and SP.opt.shieldChargeDisplay or NO_SETTINGS, which)
	if r then return r, g, b end
	local c = SHIELD_COLOR[(which == 3) and "earth" or "player"]
	return c[1], c[2], c[3]
end
-- which: 1 Lightning, 2 Water, 3 Earth Shield; no color = back to today's
function SP:SetShieldChargeColor(which, r, g, b)
	if not SP.opt then return end
	SP.opt.shieldChargeDisplay = SP.opt.shieldChargeDisplay or {}
	local s = SP.opt.shieldChargeDisplay
	if r then s[CHARGE_COLOR_KEY[which]] = { r = r, g = g, b = b } else s[CHARGE_COLOR_KEY[which]] = nil end
	self:ShieldChargeStyleChanged()
end

-- One shield's settings changed (the settings pages, Copy, Reset): that shield is
-- drawn again now; its game-drawn layer (WoW: Forever) is rebuilt by the update,
-- out of combat only (a change in a fight shows when it ends, as before).
function SP:ShieldChanged(shield, name)
	if name == "sound" or name == "soundName" then
		if self.UpdateShieldSounds then self:UpdateShieldSounds() end
		return
	end
	if name == "reset" or name == "copy" or name == "color" or name == "texture" or (type(name) == "string" and name:find("^gradient")) then
		if self.RefreshTextures then self:RefreshTextures() end   -- this shield's Charge Bar Texture / Gradient
		if name == "reset" and self.UpdateShieldSounds then self:UpdateShieldSounds() end
	end
	SP.chargeStyleGen = (SP.chargeStyleGen or 0) + 1   -- the built layers carry it: a new one is built
	for _, f in pairs(self.shieldChargeFrames) do
		for w, cb in pairs(f.chargeBars or {}) do styleChargeBar(cb, w) end
	end
	local wf = self.shieldChargeWaterPreview
	if wf then for w, cb in pairs(wf.chargeBars or {}) do styleChargeBar(cb, w) end end
	if self.ShieldSamplesRestyle then self.ShieldSamplesRestyle() end
	SP._shieldWake = true
	if self.shieldChargesDemoActive then self:ShieldChargesDemoRefresh() end
	if self.CreateShieldChargeDisplays and self.opt then self:CreateShieldChargeDisplays() end
end

-- A profile switched, copied, reset or imported: its values copied once (an older
-- profile) and every display put where that profile has it.
if hooksecurefunc and SP.OnProfileChanged then
	hooksecurefunc(SP, "OnProfileChanged", function()
		C_Timer.After(0, function()
			if not SP.opt then return end
			SP:ShieldMigrate()
			if SP.shieldChargeFrames.player then SP:ShieldChanged(nil, "reset") end
		end)
	end)
end

-- Enable ShamanPower switched: hide the numbers (off), or show them as the settings say (on)
SP:OnOnOff(function() SP:UpdateShieldChargeDisplays() end)
