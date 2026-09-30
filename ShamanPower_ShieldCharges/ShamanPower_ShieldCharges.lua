-- ============================================================================
-- ShamanPower Shield Charge Display Module
-- Large on-screen numbers showing your shield charges and Earth Shield charges
-- ============================================================================

local SP = ShamanPower
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

function SP:CreateShieldChargeDisplays()
	local settings = self.opt.shieldChargeDisplay
	if not settings then
		self:EnsureProfileTable("shieldChargeDisplay")
		settings = self.opt.shieldChargeDisplay
	end

	-- Create player shield frame (Lightning/Water Shield)
	if not self.shieldChargeFrames.player then
		local frame = CreateFrame("Frame", "ShamanPowerPlayerShieldCharge", UIParent)
		frame:SetSize(60, 60)
		frame:SetPoint("CENTER", UIParent, "CENTER", settings.playerShieldX or -50, settings.playerShieldY or -100)
		frame:SetFrameStrata("MEDIUM")

		local text = frame:CreateFontString(nil, "OVERLAY")
		SP:SetSPFont(text, "charges", 48, "OUTLINE")
		text:SetPoint("CENTER", frame, "CENTER", 0, 0)
		text:SetTextColor(0.2, 0.6, 1.0)  -- Blue for Lightning/Water Shield
		frame.text = text

		-- Make movable when unlocked
		frame:SetMovable(true)
		frame:RegisterForDrag("LeftButton")
		frame:SetScript("OnDragStart", function(self)
			if not SP.opt.shieldChargeDisplay.locked then
				self:StartMoving()
			end
		end)
		frame:SetScript("OnDragStop", function(self)
			self:StopMovingOrSizing()
			local _, _, _, x, y = self:GetPoint()
			SP.opt.shieldChargeDisplay.playerShieldX = x
			SP.opt.shieldChargeDisplay.playerShieldY = y
		end)

		frame:Hide()
		self.shieldChargeFrames.player = frame
	end

	-- Create Earth Shield frame
	if not self.shieldChargeFrames.earth then
		local frame = CreateFrame("Frame", "ShamanPowerEarthShieldCharge", UIParent)
		frame:SetSize(60, 60)
		frame:SetPoint("CENTER", UIParent, "CENTER", settings.earthShieldX or 50, settings.earthShieldY or -100)
		frame:SetFrameStrata("MEDIUM")

		local text = frame:CreateFontString(nil, "OVERLAY")
		SP:SetSPFont(text, "charges", 48, "OUTLINE")
		text:SetPoint("CENTER", frame, "CENTER", 0, 0)
		text:SetTextColor(0.2, 0.8, 0.2)  -- Green for Earth Shield
		frame.text = text

		-- Make movable when unlocked
		frame:SetMovable(true)
		frame:RegisterForDrag("LeftButton")
		frame:SetScript("OnDragStart", function(self)
			if not SP.opt.shieldChargeDisplay.locked then
				self:StartMoving()
			end
		end)
		frame:SetScript("OnDragStop", function(self)
			self:StopMovingOrSizing()
			local _, _, _, x, y = self:GetPoint()
			SP.opt.shieldChargeDisplay.earthShieldX = x
			SP.opt.shieldChargeDisplay.earthShieldY = y
		end)

		frame:Hide()
		self.shieldChargeFrames.earth = frame
	end

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
		for _, ev in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "SPELLS_CHANGED" }) do
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
			if ev == "UNIT_AURA" and unit ~= "player" and not ShamanPower.esTrackedTargetGUID then return end
			SP._shieldWake = true
		end)
	end
	-- Only enable if shield charge display is configured to show something (and ShamanPower is on)
	local showAny = ((settings.showPlayerShield ~= false) or earthShieldWanted(settings)) and not self:IsOff()
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
-- everything about the orbs a built display depends on (a change rebuilds it)
local function orbSig(settings)
	local a, b, c = orbLookOf(settings, 1), orbLookOf(settings, 2), orbLookOf(settings, 3)
	local gen = SP.chargeStyleGen or 0   -- Charge Colors / Charge Bar Gradient changed
	if not (a or b or c) then return gen end
	return tostring(a) .. "," .. tostring(b) .. "," .. tostring(c) .. "|" .. tostring(settings.orbColor) .. "|" .. tostring(settings.orbEmpty ~= false) .. "|" .. gen
		.. "|" .. tostring(settings.orbAnim == true) .. tostring(settings.orbAnimWS == true) .. tostring(settings.orbAnimES == true)
end
-- the Animated setting for a shield (Lightning / Water / Earth)
local ANIM_KEY = { "orbAnim", "orbAnimWS", "orbAnimES" }
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
	local settings = self.opt.shieldChargeDisplay or NO_SETTINGS
	local s = settings.scale or 1
	local icon, number, _, bar, barSide = displayParts(settings)
	local halfW, above, below = 0, 0, 0
	local BAR_WIDTH, BAR_HEIGHT = BAR_WIDTH, BAR_HEIGHT   -- the orb strip's size with Orbs on
	local cb = frame and frame.chargeBar
	local look = orbLookOf(settings, cb and cb.spWhich or 1)
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
	local settings = SP.opt and SP.opt.shieldChargeDisplay or NO_SETTINGS
	local kind = bar.spKind
	which = which or bar.spWhich or ((kind == "earth") and 3 or 1)
	bar.spWhich = which
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
				SP:PaintBarGradient(fill, r, g, b, 1, bar:GetOrientation() == "VERTICAL", nil, "shieldcharges")
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
		SP:SetSPStatusBarTexture(bar, "shieldcharges", "Interface\\Buttons\\WHITE8x8")   -- Shield Charge Bars (Fonts & Textures)
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
	local wantLS = kind == "player" and animOn(settings, 1)
	local wantWS = kind == "player" and animOn(settings, 2)
	local sig = (wantLS or wantWS) and (tostring(wantLS) .. tostring(wantWS) .. "|" .. tostring(s) .. "|" .. tostring(settings.chargeBarDirection)
		.. "|" .. tostring(settings.showIcon) .. "|" .. tostring(settings.showNumber) .. "|" .. tostring(settings.numberPosition)) or false
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
	if wantLS then frame.stormGates[1] = buildGates(frame, settings, s, 1) end
	if wantWS then frame.stormGates[2] = buildGates(frame, settings, s, 2) end
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
local function paintDisplay(frame, kind, settings, s, charges, present, restricted, iconWhich)
	local icon, number, corner, bar, barSide = displayParts(settings)
	local orbs = orbSig(settings)
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

	local own = not restricted or not settings.hideNoShields
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
			and (SP.shieldChargesDemoActive or not (SPCompat and SPCompat.secretsRegime))   -- Forever: the gates draw them
		stormModels(cb, anim and v or 0, s)
	end
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
						count:SetTextColor(c[1], c[2], c[3])   -- fallback if the formatter is unavailable
					end
					placeParts(button, scale, icon, number, corner, iconTex, count, chargeBar, barSide)
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
function SP:EnsureShieldChargeEngine(frame, kind, scale)
	if not (SPCompat and SPCompat.secretsRegime) then return end
	local icon, number, corner, bar, barSide = displayParts(self.opt.shieldChargeDisplay or NO_SETTINGS)
	if frame.engine and (frame.engineScale ~= scale or frame.engineIcon ~= icon or frame.engineNumber ~= number
		or frame.engineCorner ~= corner or frame.engineBar ~= bar or frame.engineTheme ~= themeStamp
		or frame.engineBarSide ~= barSide or frame.engineOrbs ~= orbSig(self.opt.shieldChargeDisplay or NO_SETTINGS)) then
		frame.engine:Hide()
		pcall(frame.engine.SetUnit, frame.engine, "none")   -- the old one stops following auras
		frame.engine = nil
	end
	if not frame.engine then
		-- player: blue, like the module at full charges; Earth Shield: green
		local sets = (kind == "player") and (ShamanPower.ShieldAuraSets or {}) or { { name = "Earth Shield", ids = ES_SPELL_IDS } }
		frame.engine = buildChargeContainer(frame, kind, scale, sets, icon, number, corner, bar, barSide)
		frame.engineScale = scale
		frame.engineIcon, frame.engineNumber, frame.engineCorner, frame.engineBar = icon, number, corner, bar
		frame.engineBarSide = barSide
		frame.engineOrbs = orbSig(self.opt.shieldChargeDisplay or NO_SETTINGS)
		frame.engineTheme = themeStamp
		frame.engineUnit = nil
	end
	if not self.shieldChargesDemoActive then ensureGates(frame, kind, self.opt.shieldChargeDisplay or NO_SETTINGS, scale) end
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
local GetAuraByName = (WOW_PROJECT_ID == WOW_PROJECT_MAINLINE) and C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName or nil

-- ...and only when the SHIELD changed: the game says which auras each update
-- added, changed or removed, so any other buff coming or going costs nothing.
-- known = false means "read it again on the next update" (at login, after a
-- full update, and whenever auras were secret: in combat the game draws the
-- count itself and nothing here is read).
local shield = { known = false, id = nil, has = false, charges = 0, water = false }
-- in combat the game hides auras' contents (secret values): nothing hidden is
-- ever tested, only "read again once it can be read"
local secret = issecretvalue or function() return false end
if GetAuraByName then
	local function has(list, id)   -- true when the list holds id, or can't be read
		if secret(list) then return true end
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
			local list = info.removedAuraInstanceIDs
			if list and has(list, id) then shield.known = false return end
			list = info.updatedAuraInstanceIDs   -- a charge used
			if list and has(list, id) then shield.known = false return end
		end
		local added = info.addedAuras
		if added then
			if secret(added) then shield.known = false return end
			for i = 1, #added do
				local a = added[i]
				local name = not secret(a) and a.name
				if secret(a) or secret(name) or name == "Lightning Shield" or name == "Water Shield" then shield.known = false return end
			end
		end
	end)
end

function SP:UpdateShieldChargeDisplays()
	if self.shieldChargesDemoActive then return end
	local settings = self.opt.shieldChargeDisplay
	if not settings then return end

	-- ShamanPower switched off: no numbers, and the update stops
	if self:IsOff() then
		self:DisableUpdateSubsystem("shieldCharge")
		if self.shieldChargeFrames.player then self.shieldChargeFrames.player:Hide() end
		if self.shieldChargeFrames.earth then self.shieldChargeFrames.earth:Hide() end
		return
	end

	-- Enable/disable the shieldCharge subsystem based on settings
	local showAny = (settings.showPlayerShield ~= false) or earthShieldWanted(settings)
	if showAny then
		self:EnableUpdateSubsystem("shieldCharge")
	else
		self:DisableUpdateSubsystem("shieldCharge")
	end

	local playerFrame = self.shieldChargeFrames.player
	local earthFrame = self.shieldChargeFrames.earth
	if not playerFrame or not earthFrame then return end

	local scale = settings.scale or 1.0
	local opacity = settings.opacity or 1.0
	local locked = settings.locked
	local hideOOC = settings.hideOutOfCombat
	local hideNoShields = settings.hideNoShields

	-- Check combat state
	local inCombat = InCombatLockdown() or UnitAffectingCombat("player")

	-- Update player shield (Lightning/Water Shield)
	if settings.showPlayerShield ~= false then
		local charges = 0
		local hasShield = false
		local water = false   -- Water Shield (not Lightning Shield): which icon to draw

		local restricted = self:ShieldChargesRestricted()
		-- Animated Lightning on WoW: Forever: the per-orb gates are built out of combat
		-- (they track the shield themselves, in and out of combat, once built)
		if SPCompat and SPCompat.secretsRegime and not self.shieldChargesDemoActive then
			ensureGates(playerFrame, "player", settings, scale)
		end
		if restricted then
			-- auras are secret: the engine draws the count (nothing while no shield)
			hasShield = true
			self:EnsureShieldChargeEngine(playerFrame, "player", scale)
		else
			-- Check for Lightning Shield or Water Shield; the answer holds until the next aura event
			if GetAuraByName then
				-- WoW: Forever: the shield by name, only when it changed (see above)
				if not shield.known then
					-- the two shields never stand together: whichever is up
					local a = GetAuraByName("player", "Lightning Shield", "HELPFUL")
					local w = false
					if not a then
						a = GetAuraByName("player", "Water Shield", "HELPFUL")
						w = a ~= nil
					end
					if a and (secret(a.applications) or secret(a.auraInstanceID)) then
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
			if WOW_PROJECT_ID ~= WOW_PROJECT_MAINLINE and core and not core.engineCount and ShamanPower._shieldCheckedGen ~= nil
				and ShamanPower._shieldCheckedGen == (ShamanPower.auraGen and ShamanPower.auraGen["player"] or 0) then
				-- TBC Anniversary: the core's shield check is current (it read the shield, or the
				-- game said nothing about it changed): its answer, not a second read of every
				-- buff (each read builds a ~1.9 KB record there). Same rules as the loop below.
				if core.hasShield then
					local n = core.rawCount
					if n == nil then n = 3 end
					charges, hasShield, water = n, true, core.shieldName == "Water Shield"
				end
			elseif self.AuraCacheValid and self:AuraCacheValid("player", sc.gen, sc.at) then
				charges, hasShield, water = sc.charges, sc.hasShield, sc.water
			else
			for i = 1, 40 do
				local name, _, count, _, _, _, _, _, _, spellId = UnitBuff("player", i)
				if not name then break end
				if name:find("Lightning Shield") or name:find("Water Shield") then
					charges = count or 0
					-- If charges is 0 but we have the buff, it might be stored differently
					if charges == 0 then
						-- Try getting it from the 3rd return value directly
						local _, _, c = UnitBuff("player", i)
						charges = c or 3  -- Default to 3 if we can't get count
					end
					hasShield = true
					water = name:find("Water Shield") and true or false
					break
				end
			end
			sc.gen, sc.at, sc.charges, sc.hasShield = ShamanPower.auraGen and ShamanPower.auraGen["player"] or 0, GetTime(), charges, hasShield
			sc.water = water
			end
			end
			-- the icon shown with no shield up (and under the engine's in combat) is the last one seen
			if hasShield then self._shieldLastWater = water end
			-- WoW: Forever: the game's layer is built out of combat, before the first fight,
			-- instead of in it (and again here if a build ever came back empty). Only while
			-- there is none: a built one is kept up to date by the settings (see below)
			if SPCompat and SPCompat.secretsRegime and not playerFrame.engine and not InCombatLockdown()
				and not self.shieldChargesDemoActive then
				self:EnsureShieldChargeEngine(playerFrame, "player", scale)
			end
		end
		if playerFrame.engine then playerFrame.engine:SetShown(restricted) end

		-- Determine visibility
		local shouldShow = hasShield or not hideNoShields
		if hideOOC and not inCombat then
			shouldShow = false
		end

		if shouldShow then
			if not (hasShield and not restricted) then
				-- no shield to read: the last one seen, else the preferred shield
				water = self._shieldLastWater
				if water == nil then water = (self.opt.preferredShield == 2) end
			end
			paintDisplay(playerFrame, "player", settings, scale, charges, hasShield, restricted, water and 2 or 1)
			playerFrame:SetAlpha(opacity)
			playerFrame:EnableMouse(not locked)
			playerFrame:Show()
		else
			playerFrame:Hide()
		end
	else
		playerFrame:Hide()
	end

	-- Update Earth Shield
	if earthShieldWanted(settings) then
		local charges = 0
		local hasShield = false

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
		local shouldShow = hasShield or not hideNoShields
		if hideOOC and not inCombat then
			shouldShow = false
		end

		if shouldShow then
			paintDisplay(earthFrame, "earth", settings, scale, charges, hasShield, restricted, 3)
			earthFrame:SetAlpha(opacity)
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
	if not playerFrame or not earthFrame then return end
	local settings = self.opt.shieldChargeDisplay or {}
	local scale, opacity = settings.scale or 1.0, settings.opacity or 1.0
	local d = self.shieldChargesDemoState or { player = 3, earth = 6 }
	-- the demo draws the whole display itself: the game-drawn copy (restricted,
	-- WoW: Forever) keeps the look it was built with, so a changed setting would
	-- show twice; it is put back as the settings say when the demo ends
	if playerFrame.engine then playerFrame.engine:Hide() end
	if earthFrame.engine then earthFrame.engine:Hide() end
	for _, set in pairs(playerFrame.stormGates or {}) do   -- the demo draws its own effects
		for _, g in ipairs(set) do g:Hide() end
	end

	if settings.showPlayerShield ~= false then
		-- Lightning Shield, like the character on stage; at 0 it shows the no-shield look
		paintDisplay(playerFrame, "player", settings, scale, d.player, d.player > 0, false, 1)
		playerFrame:SetAlpha(opacity)
		playerFrame:EnableMouse(false)
		playerFrame:Show()
	else
		playerFrame:Hide()
	end
	-- the settings preview also shows Water Shield, its own display and bar
	local waterFrame = self.shieldChargeWaterPreview
	if waterFrame then
		if self.shieldChargesDemoPane and settings.showPlayerShield ~= false then
			waterFrame.spDemoHidden = nil
			paintDisplay(waterFrame, "player", settings, scale, d.player, d.player > 0, false, 2)
			waterFrame:SetAlpha(opacity)
			waterFrame:Show()
		else
			waterFrame.spDemoHidden = true
			waterFrame:Hide()
		end
	end
	if earthShieldWanted(settings) then
		paintDisplay(earthFrame, "earth", settings, scale, d.earth, d.earth > 0, false, 3)
		earthFrame:SetAlpha(opacity)
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
		if self.shieldChargeFrames.player then self.shieldChargeFrames.player:EnableMouse(not locked) end
		if self.shieldChargeFrames.earth then self.shieldChargeFrames.earth:EnableMouse(not locked) end
		self:UpdateShieldChargeDisplays()
	end
end

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
			local st = SP.opt and SP.opt.shieldChargeDisplay
			return st and st.showChargeBar and (st.chargeBarDirection == "right" or st.chargeBarDirection == "left") or false
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
	local s = SP.opt and SP.opt.shieldChargeDisplay
	for kind, f in pairs(SP.shieldChargeFrames) do
		if f.engine then SP:EnsureShieldChargeEngine(f, kind, (s and s.scale) or 1.0) end
	end
	SP._shieldWake = true
end
if SP.OnThemeChanged then
	SP:OnThemeChanged(function()
		if not ThemeColorsMoved() then return end
		for kind, f in pairs(SP.shieldChargeFrames) do
			for w, cb in pairs(f.chargeBars or {}) do styleChargeBar(cb, w) end   -- each shield's own bar
		end
		SP._shieldWake = true
		if SP.shieldChargesDemoActive then SP:ShieldChargesDemoRefresh() end
		if WOW_PROJECT_ID == WOW_PROJECT_MAINLINE and SP.ThemeRepaintSoon then
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
	SP._shieldWake = true
	if SP.shieldChargesDemoActive and SP.ShieldChargesDemoRefresh then SP:ShieldChargesDemoRefresh() end
	if WOW_PROJECT_ID == WOW_PROJECT_MAINLINE and SP.ThemeRepaintSoon then
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

-- Enable ShamanPower switched: hide the numbers (off), or show them as the settings say (on)
SP:OnOnOff(function() SP:UpdateShieldChargeDisplays() end)
