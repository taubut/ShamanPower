-- ShamanPowerTheme.lua
-- The theme engine. A theme changes how ShamanPower LOOKS and nothing else.
-- Every theme control lives on General > Themes (ShamanPower_Config/Themes.lua);
-- this file is the shared engine every painter and that page code against.
--
-- Two kinds of parts:
--  A. Setting-backed: looks that already have a setting (Element Colors,
--     Cooldown Text Color, the Effects styles, Ready Reminders / Tremor
--     colours...). The file that owns the setting registers it with
--     SP:ThemeSpotSettings. A theme is a PRESET for those: picking one WRITES
--     the theme's value into the existing setting (the player's own value is
--     saved first), the settings page keeps working, and whatever the player
--     changes there afterwards is what shows. Standard puts the saved value back.
--  B. Theme-stored: looks with no setting today (hardcoded colours, flat boxes,
--     effect looks). Read at paint time with SP:ThemeColor / SP:ThemeElement /
--     SP:ThemeBoxed ...; nil / "standard" means: run today's code unchanged.
--
-- A player who never opens the Themes tab: SP.opt.theme stays nil, nothing is
-- written, every read returns nil / today's value, no listener ever runs.
-- Colours are resolved once per change into preallocated tables; paint-time
-- reads allocate nothing.
local SP = ShamanPower
if not SP then return end

local type, pairs, ipairs, next, pcall, tostring, tonumber = type, pairs, ipairs, next, pcall, tostring, tonumber
local abs = math.abs

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------
local IS_MAINLINE = (WOW_PROJECT_ID ~= nil and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE)

local THEMES      = { standard = true, shamanpower = true, minimal = true }
local PALETTE_KEY = { classic = true, blizzard = true, shamanpower = true, custom = true }
local SHIELD_KEY  = { today = true, palette = true, magic = true }
local SHOWAS_KEY  = { both = true, letters = true, tint = true, mini = true }
local LOOK_KEY    = { standard = true, elemental = true, signal = true }
local LOOK_OF     = { standard = "standard", shamanpower = "elemental", minimal = "signal" }
local THEME_OF_LOOK = { standard = "standard", elemental = "shamanpower", signal = "minimal" }
-- what a setting-backed entry follows when its spot is on Standard
local FOLLOWS_OF_KIND = { element = "palette", choice = "choice", shield = "shield" }

local function Hex(h)
	return tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255
end
local function RGB(h)
	local r, g, b = Hex(h)
	return { r, g, b }
end

-- Element palettes, Earth / Fire / Water / Air. classic and blizzard are the
-- exact numbers ShamanPower.lua's Appearance palettes use; shamanpower is the logo.
local PALETTES = {
	classic     = { { 0.60, 0.40, 0.20 }, { 1.00, 0.40, 0.10 }, { 0.20, 0.60, 1.00 }, { 0.80, 0.80, 1.00 } },
	blizzard    = { { 0.36, 0.72, 0.21 }, { 0.92, 0.37, 0.17 }, { 0.28, 0.70, 0.88 }, { 0.60, 0.32, 1.00 } },
	shamanpower = { RGB("AE7E4E"), RGB("F25735"), RGB("668DF2"), RGB("D0D5ED") },
}
SP.THEME_PALETTES = PALETTES

-- brand constants
local LOGO_BLUE   = RGB("3FA9F5")
local NAVY_BG     = "141B26"
local NAVY_EDGE   = "2B374A"
local NAVY_ALPHA  = 0.92
SP.THEME_BRAND = { logoBlue = LOGO_BLUE, navyBg = RGB(NAVY_BG), navyBgAlpha = NAVY_ALPHA, navyEdge = RGB(NAVY_EDGE) }

-- WoW's own colours (GlobalColor.db2), used only when the game global is missing
local WOW_FALLBACK = {
	GREEN_FONT_COLOR        = RGB("19FF19"),
	YELLOW_FONT_COLOR       = RGB("FFFF00"),
	RED_FONT_COLOR          = IS_MAINLINE and RGB("FF2020") or RGB("FF1919"),
	NORMAL_FONT_COLOR       = IS_MAINLINE and RGB("FFD200") or RGB("FFD100"),
	ORANGE_FONT_COLOR       = RGB("FF8040"),
	DEBUFF_TYPE_MAGIC_COLOR = RGB("0081FF"),
}

-- What the Themes tab's dropdowns and cards offer (labels as the player reads them).
SP.THEME_LISTS = {
	theme   = { { key = nil, label = "Use General Theme" }, { key = "standard", label = "Standard" },
	            { key = "shamanpower", label = "ShamanPower" }, { key = "minimal", label = "ShamanPower Minimal" } },
	themes  = { { key = "standard", label = "Standard" }, { key = "shamanpower", label = "ShamanPower" },
	            { key = "minimal", label = "ShamanPower Minimal" } },
	palette = { { key = nil, label = "Use Theme's" }, { key = "classic", label = "Classic" }, { key = "blizzard", label = "Blizzard" },
	            { key = "shamanpower", label = "ShamanPower" }, { key = "custom", label = "Custom" } },
	shield  = { { key = nil, label = "Use Theme's" }, { key = "today", label = "Today" },
	            { key = "palette", label = "Follow Palette" }, { key = "magic", label = "WoW Magic Blue" } },
	showAs  = { { key = nil, label = "Use Theme's" }, { key = "both", label = "Letters + faint icon" }, { key = "letters", label = "Letters" },
	            { key = "tint", label = "One-color icon" }, { key = "mini", label = "Small icon" } },
	effects = { { key = nil, label = "Use Theme's" }, { key = "standard", label = "Standard" },
	            { key = "elemental", label = "Elemental" }, { key = "signal", label = "Signal" } },
}

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------
local function Report(err)
	local h = geterrorhandler and geterrorhandler()
	if h then h(err) end
end

local function Copy(v)
	if type(v) ~= "table" then return v end
	local c = {}
	for k, x in pairs(v) do c[k] = Copy(x) end
	return c
end

local TOL = 1 / 255 + 1e-6
local function IsColor(v)
	return type(v) == "table" and (type(v.r) == "number" or (v.r == nil and type(v[1]) == "number" and type(v[3]) == "number"))
end
local function ColorRGB(v)
	if v.r ~= nil then return v.r, v.g or 0, v.b or 0 end
	return v[1], v[2] or 0, v[3] or 0
end
-- equal, with numbers (and colours, r/g/b only) within 1/255
local function Near(a, b)
	if a == b then return true end
	local ta, tb = type(a), type(b)
	if ta == "number" and tb == "number" then return abs(a - b) <= TOL end
	if ta ~= "table" or tb ~= "table" then return false end
	if IsColor(a) and IsColor(b) then
		local r1, g1, b1 = ColorRGB(a)
		local r2, g2, b2 = ColorRGB(b)
		return abs(r1 - r2) <= TOL and abs(g1 - g2) <= TOL and abs(b1 - b2) <= TOL
	end
	for k, x in pairs(a) do if not Near(x, b[k]) then return false end end
	for k, x in pairs(b) do if a[k] == nil and x ~= nil then return false end end
	return true
end

-- SP.opt.theme, read side: never creates anything
local function T()
	local o = SP.opt
	local t = o and o.theme
	if type(t) == "table" then return t end
	return nil
end
-- write side: creates SP.opt.theme (only ever called on a real change)
local function TW()
	local o = SP.opt
	if not o then return nil end
	local t = o.theme
	if type(t) ~= "table" then t = {}; o.theme = t end
	return t
end
local function Sub(t, k)
	local s = t[k]
	if type(s) ~= "table" then s = {}; t[k] = s end
	return s
end
local function SpotOverride(t, id)
	local s = t and t.spots
	s = type(s) == "table" and s[id]
	if type(s) == "table" then return s end
	return nil
end

-- ---------------------------------------------------------------------------
-- The registry: SP.THEME_MODULES (order = the Themes tab's section order)
-- ---------------------------------------------------------------------------
local EL = { "Earth", "Fire", "Water", "Air" }

-- the four element roles "1".."4"; std = today's colours (hex), nil = the
-- Appearance palette (SP.ElementColors) or a ThemeBind copy
local function E4(std, kind, labels)
	local t = {}
	for e = 1, 4 do
		t[e] = { key = tostring(e), label = (labels and labels[e]) or EL[e], kind = kind or "element", e = e, std = std and std[e] }
	end
	return t
end
local function Role(key, label, kind, v, std, extra)
	local r = { key = key, label = label, kind = kind, std = std }
	if kind == "wow" then r.name = v
	elseif kind == "shield" then r.which = v
	elseif kind == "fixed" then r.hex = v
	elseif kind == "element" then r.e = v end
	if extra then for k, x in pairs(extra) do r[k] = x end end
	return r
end
local function Plus(a, ...)
	local t = {}
	for _, r in ipairs(a) do t[#t + 1] = r end
	for i = 1, select("#", ...) do t[#t + 1] = (select(i, ...)) end
	return t
end
local function Panel(stdBg, stdEdge)
	return {
		Role("bg", "Background", "fixed", NAVY_BG, stdBg, { alpha = NAVY_ALPHA }),
		Role("border", "Border", "fixed", NAVY_EDGE, stdEdge),
	}
end
local function Shields(std)
	return {
		Role("lightning", "Lightning Shield", "shield", "lightning", std and std[1]),
		Role("water", "Water Shield", "shield", "water", std and std[2]),
		Role("earth", "Earth Shield", "shield", "earth", std and std[3]),
	}
end
local SPELL = function() return Role("spell", "Spells", "fixed", "3FA9F5") end
local IMBUE_LABELS = { "Earth (Rockbiter)", "Fire (Flametongue)", "Water (Frostbrand)", "Air (Windfury)" }
local PANEL_STD_BG, PANEL_STD_EDGE = "16191F", "2E343E"   -- SP.PANEL_BG / SP.PANEL_BORDER

local CHOICES_TEXT = {
	{ key = "white",   label = "White",         hex = "FFFFFF" },
	{ key = "element", label = "Element Color", element = true },
	{ key = "gold",    label = "WoW Gold",      wow = "NORMAL_FONT_COLOR" },
}
local CHOICES_PULSE = {
	{ key = "white",   label = "White",         hex = "FFFFFF" },
	{ key = "element", label = "Element Color", element = true },
	{ key = "blue",    label = "Logo Blue",     hex = "3FA9F5" },
}
local CHOICE_DEFAULT = { standard = "white", shamanpower = "element", minimal = "element" }

SP.THEME_MODULES = {
	-- Theme-level: the Element Colors cards ARE the Appearance palette setting.
	-- Drawn by the palette cards under the picker, never as a module section.
	{ key = "theme", label = "Theme", themeLevel = true, spots = {
		{ id = "pal.element", label = "Element Colors", palette = true, followsPalette = true, settingBacked = true, roles = {},
		  note = "The Element Colors setting on Appearance. The ShamanPower themes switch it to the ShamanPower palette; Standard puts yours back." },
	} },
	{ key = "totembar", label = "Totem Bar", spots = {
		{ id = "tb.boxes", label = "Totem Icons", box = true, palette = true, roles = E4(),
		  note = "The totem buttons. ShamanPower Minimal draws them as flat element boxes." },
		{ id = "tb.flyout-boxes", label = "Totem Flyout Entries", box = true, palette = true, roles = E4(),
		  note = "The totems in each flyout. ShamanPower Minimal draws them as flat element boxes." },
		{ id = "tb.flyout-empty", label = "Flyout Empty Choice", roles = {},
		  note = "The Empty choice in a flyout. ShamanPower Minimal shows a dark box with a dash." },
		{ id = "tb.flyout-art", label = "Flyout Arrow Tabs and Panel", palette = true, roles = E4(),
		  note = "The flyout arrow tabs and panel. The ShamanPower themes draw flat tabs in the element colors." },
		{ id = "tb.overlay-boxes", label = "Dropped-Totem Overlay", box = true, palette = true, roles = E4(),
		  note = "The icon of the totem you have down. ShamanPower Minimal draws it as a flat box." },
		{ id = "tb.overlay-border", label = "Dropped-Totem Overlay Border", palette = true, roles = E4(),
		  note = "The element-colored border around a dropped totem." },
		{ id = "tb.dropall", label = "Drop All Button", box = true, roles = E4(),
		  note = "The Drop All button. ShamanPower Minimal draws it as a box in the color of the totem it shows." },
		{ id = "tb.recall", label = "Totemic Call Button", box = true, roles = { Role("box", "Box", "fixed", "3FA9F5") },
		  note = "Totemic Call on the totem bar. ShamanPower Minimal draws it as a flat box." },
		{ id = "tb.empty-slot", label = "Unassigned Slot", roles = {},
		  note = "A slot with no totem picked (WoW: Forever). ShamanPower Minimal shows a dark box with a dash." },
		{ id = "tb.sweep", label = "Cooldown Sweep", roles = {},
		  note = "The cooldown sweep over a totem. ShamanPower Minimal draws a dark band on the box." },
		{ id = "tb.duration", label = "Duration Bar Colors", palette = true, roles = E4({ "33CC33", "E64D1A", "3380E6", "CCCCCC" }),
		  note = "The bars that count down each totem. The ShamanPower themes use the element palette." },
		{ id = "tb.duration-text", label = "Duration Text Color", choices = CHOICES_TEXT, choiceDefault = CHOICE_DEFAULT,
		  roles = E4({ "FFFFFF", "FFFFFF", "FFFFFF", "FFFFFF" }, "choice"),
		  note = "The time left on the duration bars: white, the element color or WoW gold." },
		{ id = "tb.cooldown-text", label = "Cooldown Text Color", settingBacked = true,
		  roles = { Role("text", "Cooldown Text Color", "fixed", "FFFFFF", nil, { placeholder = true }) },
		  note = "The Cooldown Text Color setting on Totem Bar > Duration Bars. The ShamanPower themes set it to white; you can still change it there." },
		{ id = "tb.pulse", label = "Pulse Wipe and Pulse Bar", choices = CHOICES_PULSE, choiceDefault = CHOICE_DEFAULT,
		  roles = E4({ "FFFFFF", "FFFFFF", "FFFFFF", "FFFFFF" }, "choice"),
		  note = "The pulse wipe on the icons and the pulse bar: white, the element color or logo blue." },
		{ id = "tb.dots-missing", label = "Party Dots: Missing Buff", roles = { Role("missing", "Missing Buff", "wow", "RED_FONT_COLOR", "FF0000") },
		  note = "The dot for a party member without your totem's buff." },
		{ id = "tb.dots-class", label = "Party Dots: Class Colors", roles = {},
		  note = "The party dots in class colors. Every theme keeps WoW's class colors for now." },
		{ id = "tb.range", label = "Range Counter Numbers", palette = true, roles = E4({ "33E633", "E63333", "3399FF", "FFFFFF" }),
		  note = "The numbers that count who is in range of each totem." },
		{ id = "tb.frame", label = "Frame Background and Border", roles = Panel("000000", "4D4D4D"),
		  note = "The totem bar's background and border. The ShamanPower themes use navy." },
		{ id = "tb.effects", label = "Effects Look", effects = true, hidden = true, lookOpt = "totemCueLook", signatureSpot = "tb.signature", roles = {},
		  note = "How Totem Destroyed, Totem Expired and Totem Expiring Soon look: Standard, Elemental or Signal." },
		{ id = "tb.signature", label = "Signature Moves", signature = true, hidden = true, sigOpt = "totemCueSignature", effectsSpot = "tb.effects", settingBacked = true, roles = {},
		  note = "Each totem effect uses the look's own move. Turning it off puts your Effects styles back." },
	} },
	{ key = "styles", label = "Totem Bar Styles", spots = {
		{ id = "st.compact", label = "Compact Line Colors", palette = true, roles = E4(),
		  note = "The element lines of the Compact style." },
		{ id = "st.compact-shield", label = "Compact Shield Line", shield = true, roles = {
			Role("full", "Full", "shield", "lightning", "FFD940"),
			Role("water", "Water Shield", "shield", "water", "59A6FF"),
			Role("es", "Earth Shield", "shield", "earth", "40D94D"),
			Role("low", "Low", "wow", "YELLOW_FONT_COLOR", "FFD933"),
			Role("last", "Last Charge", "wow", "RED_FONT_COLOR", "FF4040") },
		  note = "The shield line on the Compact style: full, low and last charge." },
		{ id = "st.boxes-compact", label = "Compact Line Boxes", box = true, palette = true, roles = E4(),
		  note = "A flat element box at the start of each Compact line (ShamanPower Minimal)." },
		{ id = "st.grid", label = "Grid Rings and Split Borders", palette = true, roles = E4(),
		  note = "The element rings and split borders of the Grid style." },
		{ id = "st.boxes-grid", label = "Grid Icons", box = true, palette = true, roles = E4(),
		  note = "The Grid style's icons. ShamanPower Minimal draws them as flat element boxes." },
		{ id = "st.blizzard", label = "Blizzard's Totem Bar Squares", palette = true, roles = E4({ "5CB836", "EB5E2B", "47B3E0", "9952FF" }),
		  note = "The element squares ShamanPower draws on Blizzard's Totem Bar." },
	} },
	{ key = "cooldownbar", label = "Cooldown Bar", spots = {
		{ id = "cd.boxes", label = "Cooldown Icons", box = true, palette = true, roles = Plus(E4(), SPELL()),
		  note = "The cooldown buttons. ShamanPower Minimal draws them as flat boxes." },
		{ id = "cd.shield-box", label = "Shield Button", box = true, shield = true, roles = Shields(),
		  note = "The shield button. ShamanPower Minimal draws it as a flat box in the shield's color." },
		{ id = "cd.imbue-boxes", label = "Weapon Imbue Buttons", box = true, palette = true, roles = E4(nil, nil, IMBUE_LABELS),
		  note = "The main-hand and off-hand imbue buttons. ShamanPower Minimal draws them as flat boxes." },
		{ id = "cd.flyout-boxes", label = "Shield and Imbue Flyouts", box = true, palette = true, shield = true,
		  roles = Plus(E4(nil, nil, IMBUE_LABELS), SPELL(), unpack(Shields())),
		  note = "The entries in the shield and imbue flyouts. ShamanPower Minimal draws them as flat boxes." },
		{ id = "cd.class-icons", label = "Earth Shield Class Icons", box = true, roles = {},
		  note = "The class icons in the Earth Shield flyout. ShamanPower Minimal shows a class-color box with letters." },
		{ id = "cd.recall", label = "Totemic Call", box = true, roles = { Role("box", "Box", "fixed", "3FA9F5") },
		  note = "Totemic Call on the cooldown bar. ShamanPower Minimal draws it as a flat box." },
		{ id = "cd.count", label = "Shield Charge Count", roles = {
			Role("high", "Healthy", "wow", "GREEN_FONT_COLOR", "00FF00"),
			Role("mid", "Low", "wow", "YELLOW_FONT_COLOR", "FFFF00"),
			Role("low", "Critical", "wow", "RED_FONT_COLOR", "FF0000") },
		  note = "The charge count on the shield button. The ShamanPower themes use WoW's green, yellow and red." },
		{ id = "cd.strip", label = "Shield Charge Strip", shield = true, roles = { Role("strip", "Strip", "shield", "lightning", "3399FF") },
		  note = "The strip of charges under the shield button." },
		{ id = "cd.shieldbar", label = "Shield Bar", shield = true, roles = {
			Role("lightning", "Lightning Shield", "shield", "lightning"),
			Role("water", "Water Shield", "shield", "water") },
		  note = "The time-left bar of your shield and Earth Shield." },
		{ id = "cd.imbuebar", label = "Imbue Time-Left Bar", palette = true, roles = E4(nil, nil, IMBUE_LABELS),
		  note = "The time-left bar of each weapon imbue. The ShamanPower themes use the element palette." },
		{ id = "cd.timers", label = "Cooldown and Imbue Timer Bars", roles = {
			Role("good", "Healthy", "wow", "GREEN_FONT_COLOR", "33CC33"),
			Role("low", "Low", "wow", "YELLOW_FONT_COLOR", "E6B333"),
			Role("bad", "Critical", "wow", "RED_FONT_COLOR", "E63333") },
		  note = "The timer bars as they run low. The ShamanPower themes use WoW's green, yellow and red." },
		{ id = "cd.frame", label = "Frame Background and Border", roles = Panel("000000", "4D4D4D"),
		  note = "The cooldown bar's background and border. The ShamanPower themes use navy." },
		{ id = "cd.sweep", label = "Cooldown Sweep", roles = {},
		  note = "The cooldown sweep and gray overlay. ShamanPower Minimal draws a dark band on the box." },
		{ id = "cd.engine", label = "Game-Drawn Shield Display", roles = { Role("bar", "Bar", "wow", "GREEN_FONT_COLOR", "33CC33") },
		  note = "The shield count and bar the game draws in combat (WoW: Forever). The color is set when it is built." },
		{ id = "cd.effects", label = "Effects Look", effects = true, hidden = true, lookOpt = "cdbarCueLook", signatureSpot = "cd.signature", roles = {},
		  note = "How Cooldown Ready, Weapon Imbue Gone and Shield Gone look: Standard, Elemental or Signal." },
		{ id = "cd.signature", label = "Signature Moves", signature = true, hidden = true, sigOpt = "cdbarCueSignature", effectsSpot = "cd.effects", settingBacked = true, roles = {},
		  note = "Each cooldown effect uses the look's own move. Turning it off puts your Effects styles back." },
	} },
	{ key = "loadouts", label = "Totem Loadouts", spots = {
		{ id = "lo.bar", label = "Loadout Bar Buttons", box = true, palette = true, roles = Plus(E4(), Role("box", "Loadout Number Box", "fixed", "3FA9F5")),
		  note = "The loadout bar's buttons. ShamanPower Minimal draws them as flat boxes." },
		{ id = "lo.tooltip", label = "Tooltip Element Names", palette = true, roles = E4({ "B3804D", "FF1A1A", "6666FF", "FFFFFF" }),
		  note = "The element names in a loadout's tooltip." },
	} },
	{ key = "shieldcharges", label = "Shield Charge Display", spots = {
		{ id = "mod.shieldcharges-colors", label = "Big Number and Charge Bar", shield = true, roles = {
			Role("full", "Full", "shield", "lightning", "3399FF"),
			Role("esfull", "Earth Shield Full", "shield", "earth", "33CC33"),
			Role("low", "Low", "wow", "YELLOW_FONT_COLOR", "FFCC00"),
			Role("last", "Last Charge", "wow", "RED_FONT_COLOR", "FF3333") },
		  note = "The big charge number and bar: full, low and last charge." },
		{ id = "mod.shieldcharges-icon", label = "Shield Icon", box = true, shield = true, roles = Shields(),
		  note = "The shield icon. ShamanPower Minimal draws it as a flat box." },
	} },
	{ key = "alerts", label = "Expiring Alerts", spots = {
		{ id = "mod.alerts", label = "Alert Text Colors", palette = true, roles = Plus(E4({ "996633", "FF4D00", "0099FF", "99CCFF" }),
			Role("shield", "Lightning Shield", "shield", "lightning", "8080FF"),
			Role("destroyed", "Totem Destroyed", "wow", "RED_FONT_COLOR", "FF4D4D"),
			Role("imbue", "Imbue Faded", "wow", "ORANGE_FONT_COLOR", "FF8000")),
		  note = "The color of each alert's text." },
		{ id = "mod.alerts-box", label = "Alert Icon", box = true, palette = true, roles = Plus(E4(), Role("spell", "Other Spells", "fixed", "3FA9F5")),
		  note = "The icon beside the alert text. ShamanPower Minimal draws it as a flat box." },
	} },
	{ key = "partybuff", label = "Party Buff Tracker", spots = {
		{ id = "mod.partybuff-frame", label = "Counter Frames", roles = Panel(PANEL_STD_BG, PANEL_STD_EDGE),
		  note = "The party buff counters' background and border. The ShamanPower themes use navy." },
		{ id = "mod.coverage-colors", label = "Coverage Panel", roles = Panel(PANEL_STD_BG, PANEL_STD_EDGE),
		  note = "The coverage panel's background and border." },
		{ id = "mod.coverage-boxes", label = "Coverage Cell Icons", box = true, palette = true, roles = E4(),
		  note = "The icons in the coverage cells. ShamanPower Minimal draws them as flat boxes." },
		{ id = "mod.coverage-dots-missing", label = "Coverage Dots: Missing Buff", roles = { Role("missing", "Missing Buff", "wow", "RED_FONT_COLOR", "FF0000") },
		  note = "The dot for a party member without the buff." },
		{ id = "mod.coverage-dots-class", label = "Coverage Dots: Class Colors", roles = {},
		  note = "The coverage dots in class colors. Every theme keeps WoW's class colors for now." },
	} },
	{ key = "range", label = "Totem Range Tracker", spots = {
		{ id = "mod.range-colors", label = "Panel", roles = Panel(PANEL_STD_BG, PANEL_STD_EDGE),
		  note = "The range tracker's background and border. The ShamanPower themes use navy." },
		{ id = "mod.range-boxes", label = "Totem Icons", box = true, palette = true, roles = E4(),
		  note = "The tracked totems. ShamanPower Minimal draws them as flat boxes." },
		{ id = "win.rangecfg", label = "Config Window Element Tints", palette = true, roles = E4({ "B88552", "FF5C38", "6B94FF", "DBE0FA" }),
		  note = "The element tints in the range tracker's totem picker." },
	} },
	{ key = "raidcd", label = "Raid Cooldowns", spots = {
		{ id = "mod.raidcd-boxes", label = "Mana Tide and Bloodlust Buttons", box = true, palette = true,
		  roles = Plus(E4(), Role("spell", "Bloodlust / Heroism", "fixed", "C41E3A")),
		  note = "The caller buttons. ShamanPower Minimal draws them as flat boxes (Mana Tide in Water)." },
		{ id = "mod.raidcd-colors", label = "Panels and Center Alert", roles = Plus(Panel(PANEL_STD_BG, PANEL_STD_EDGE),
			Role("alert", "Center Alert", "wow", "NORMAL_FONT_COLOR", "FF4D00")),
		  note = "The Raid Cooldowns panels and the alert in the middle of the screen." },
	} },
	{ key = "popouts", label = "Pop-Out Trackers", spots = {
		{ id = "mod.popouts-colors", label = "Pop-Out Panels", roles = Panel(PANEL_STD_BG, PANEL_STD_EDGE),
		  note = "The Pop-Out Trackers' background and border." },
		{ id = "mod.popouts-boxes", label = "Pop-Out Icons", box = true, palette = true, roles = E4(),
		  note = "The popped-out icons. ShamanPower Minimal draws them as flat boxes." },
	} },
	{ key = "estracker", label = "Earth Shield Tracker", spots = {
		{ id = "mod.estracker-colors", label = "Panel and Count", roles = Plus(Panel("000000", "999999"),
			Role("count", "Charge Count", "wow", "GREEN_FONT_COLOR", "66FF66")),
		  note = "The tracker's background, border and charge count." },
		{ id = "mod.estracker-box", label = "Earth Shield Icon", box = true, shield = true,
		  roles = { Role("earth", "Earth Shield", "shield", "earth") },
		  note = "The Earth Shield icon. ShamanPower Minimal draws it as a flat box." },
	} },
	{ key = "reactive", label = "Reactive Totems", spots = {
		{ id = "mod.reactive", label = "Alert Colors", palette = true, roles = {
			Role("1", "Earth (Fear, Charm)", "element", 1),
			Role("3", "Water (Poison, Disease)", "element", 3) },
		  note = "The reactive alerts. The ShamanPower themes color each one by the element of the totem that answers it." },
		{ id = "mod.reactive-boxes", label = "Alert Icons", box = true, palette = true, roles = {
			Role("1", "Earth (Tremor)", "element", 1),
			Role("3", "Water (Cleansing)", "element", 3) },
		  note = "The totem icon on each alert. ShamanPower Minimal draws it as a flat element box." },
	} },
	{ key = "readyreminders", label = "Ready Reminders", spots = {
		{ id = "mod.readyreminders", label = "Border", settingBacked = true, roles = {
			Role("border", "Border", "fixed", "3FA9F5", "33B3FF") },
		  note = "The reminder's border. Standard keeps the color you picked on Ready Reminders." },
		{ id = "mod.readyreminders-boxes", label = "Reminder Icons", box = true, palette = true, roles = Plus(E4(), Role("spell", "Other Spells", "fixed", "3FA9F5")),
		  note = "The spell icons. ShamanPower Minimal draws them as flat boxes: element spells in their element, others in the logo blue." },
	} },
	{ key = "tremor", label = "Tremor Reminder", spots = {
		{ id = "mod.tremor", label = "Tremor Glow", settingBacked = true, roles = { Role("glow", "Glow", "wow", "NORMAL_FONT_COLOR", "FFCC00") },
		  note = "The Tremor Totem glow. Standard keeps the color you picked on Tremor Reminder." },
		{ id = "mod.tremor-box", label = "Tremor Icon", box = true, palette = true, roles = { Role("1", "Earth", "element", 1) },
		  note = "The Tremor Totem icon. ShamanPower Minimal draws it as a flat Earth box." },
	} },
	{ key = "readycheck", label = "Ready Check", spots = {
		{ id = "mod.readycheck", label = "Ready Check Sweep Panel", roles = Panel(PANEL_STD_BG, PANEL_STD_EDGE),
		  note = "The ready check panel's background and border." },
	} },
	{ key = "plates", label = "Totem Plates", spots = {
		{ id = "mod.plates-colors", label = "Plate Borders", roles = {
			Role("enemy", "Enemy", "wow", "RED_FONT_COLOR", "D12614"),
			Role("friendly", "Friendly", "wow", "GREEN_FONT_COLOR", "14D117") },
		  note = "The border around enemy and friendly totem plates." },
		{ id = "mod.plates-boxes", label = "Plate Icons", box = true, palette = true, roles = E4(),
		  note = "The totem plate icons. ShamanPower Minimal draws them as flat boxes." },
	} },
	{ key = "minimap", label = "Minimap Totems", spots = {
		{ id = "mod.minimap", label = "Rings and Pins", palette = true, roles = E4(),
		  note = "The totem rings and pins on the minimap." },
		{ id = "mod.minimap-boxes", label = "Minimap Pins", box = true, palette = true, roles = E4(),
		  note = "The totem pins on the minimap. ShamanPower Minimal draws them as flat boxes (too small for letters: the one-color icon)." },
	} },
	{ key = "assign", label = "Totem Assignments", spots = {
		{ id = "win.assign", label = "Window Element Tints", palette = true, roles = E4({ "B88552", "FF5C38", "6B94FF", "DBE0FA" }),
		  note = "The element tints in the Totem Assignments window." },
	} },
}

-- ---------------------------------------------------------------------------
-- Indices and the preallocated caches
-- ---------------------------------------------------------------------------
local SPOTS = {}          -- id -> spot def
local cache = {}          -- id -> { [roleKey] = { r, g, b, on = bool } } (element roles also under their number)
local st = {}             -- id -> resolved state, rewritten in place on every change
SP.THEME_SPOTS = SPOTS
SP.THEME_MODULE_BY_KEY = {}

local function NewState()
	return { theme = "standard", palette = nil, shield = "today", choice = nil, look = "standard",
		sig = false, boxed = false, showAs = "both", active = false }
end

local function AddRole(spot, role)
	role.key = tostring(role.key)
	if role.hex then role.rgb = RGB(role.hex) end
	if type(role.std) == "string" then role.stdRGB = RGB(role.std) end
	spot.roleByKey[role.key] = role
	local cc = cache[spot.id]
	local c = cc[role.key]
	if not c then
		c = { 0, 0, 0, on = false }
		cc[role.key] = c
		local n = tonumber(role.key)
		if n then cc[n] = c end   -- ThemeColor(spot, 1) works as well as ThemeColor(spot, "1")
	end
end

local function IndexSpot(spot, moduleKey)
	SPOTS[spot.id] = spot
	spot.module = moduleKey
	spot.roleByKey = {}
	spot.roles = spot.roles or {}
	cache[spot.id] = cache[spot.id] or {}
	st[spot.id] = st[spot.id] or NewState()
	for _, role in ipairs(spot.roles) do AddRole(spot, role) end
	if spot.choices then
		spot.choiceByKey = {}
		for _, c in ipairs(spot.choices) do
			spot.choiceByKey[c.key] = c
			if c.hex and not c.rgb then c.rgb = RGB(c.hex) end
		end
	end
end

for _, mod in ipairs(SP.THEME_MODULES) do
	SP.THEME_MODULE_BY_KEY[mod.key] = mod
	for _, spot in ipairs(mod.spots) do IndexSpot(spot, mod.key) end
end

-- a spot a file registers settings for that the registry does not list
local function DynamicSpot(id)
	local spot = { id = id, label = id, dynamic = true, roles = {} }
	IndexSpot(spot, nil)
	return spot
end

-- ---------------------------------------------------------------------------
-- Resolution
-- ---------------------------------------------------------------------------
local function ResolveSpotTheme(t, id)
	local o = SpotOverride(t, id)
	if o and THEMES[o.theme] then return o.theme end
	if t and THEMES[t.global] then return t.global end
	return "standard"
end

local function ResolvePalette(t, id, theme)
	local o = SpotOverride(t, id)
	if o and PALETTE_KEY[o.palette] then return o.palette end
	if t and PALETTE_KEY[t.palette] then return t.palette end
	if theme == "standard" then
		-- today's Appearance palette. While a theme has rewritten that shared setting
		-- (pal.element has a snapshot), the player's own palette is the snapshot's.
		if id ~= "pal.element" then
			local snap = t and type(t.snapshot) == "table" and t.snapshot["pal.element"]
			if type(snap) == "table" and next(snap) then return "own" end
		end
		return nil
	end
	return "shamanpower"
end

local function ResolveShield(t, id, theme)
	local o = SpotOverride(t, id)
	if o and SHIELD_KEY[o.shield] then return o.shield end
	if t and SHIELD_KEY[t.shield] then return t.shield end
	return theme == "standard" and "today" or "palette"
end

local function ResolveChoice(t, spot, theme)
	if not spot.choices then return nil end
	local o = SpotOverride(t, spot.id)
	local c = o and o.choice
	if c ~= nil and spot.choiceByKey[c] then return c end
	return spot.choiceDefault[theme] or spot.choiceDefault.standard
end

-- Effects are not part of the themes: each bar's Effects Look and Signature
-- Moves are the player's own settings on the bars' Effects tabs (opt.totemCueLook /
-- opt.cdbarCueLook, opt.totemCueSignature / opt.cdbarCueSignature). A theme pick
-- never changes them.
local function ResolveLook(t, spot)
	local linked = spot.effectsSpot and SPOTS[spot.effectsSpot]
	if linked then return ResolveLook(t, linked) end
	local o = SP.opt
	local v = spot.lookOpt and o and o[spot.lookOpt]
	if LOOK_KEY[v] then return v end
	return "standard"
end

local function ResolveSignature(t, spot)
	local sig = spot
	if spot.signatureSpot then sig = SPOTS[spot.signatureSpot] or spot end
	if not sig.signature then return false end
	local o = SP.opt
	if not (o and sig.sigOpt and o[sig.sigOpt] == true) then return false end
	return ResolveLook(t, sig) ~= "standard"
end

local function ResolveShowAs(t, id)
	local o = SpotOverride(t, id)
	if o and SHOWAS_KEY[o.showAs] then return o.showAs end
	if t and SHOWAS_KEY[t.showAs] then return t.showAs end
	return "both"
end

-- palette colour; key nil = today's Appearance palette, read live
local function PaletteRGB(key, e)
	if key == "own" then
		-- the player's own Appearance palette, from pal.element's snapshot
		local t = T()
		local snap = t and type(t.snapshot) == "table" and t.snapshot["pal.element"]
		if type(snap) ~= "table" then key = nil
		else
			local mode = snap.palette and snap.palette.v
			if mode == nil and not snap.palette then mode = SP.opt and SP.opt.elementColorPalette end
			mode = mode or (SP.DefaultElementPalette and SP:DefaultElementPalette()) or "classic"
			if mode == "custom" then
				local cu = snap.custom and snap.custom.v
				if cu == nil and not snap.custom then cu = SP.opt and SP.opt.elementColorsCustom end
				local c = type(cu) == "table" and cu[e]
				if type(c) == "table" then return c.r or 1, c.g or 1, c.b or 1 end
				mode = "classic"
			end
			local p = PALETTES[mode] and PALETTES[mode][e]
			if p then return p[1], p[2], p[3] end
			key = nil
		end
	end
	if key == "custom" then
		local t = T()
		local c = t and type(t.custom) == "table" and t.custom[e]
		if type(c) == "table" and type(c.r) == "number" then return c.r, c.g or 0, c.b or 0 end
		key = "shamanpower"
	end
	local p = key and PALETTES[key]
	if p then
		local v = p[e]
		if v then return v[1], v[2], v[3] end
	end
	local ec = SP.ElementColors and SP.ElementColors[e]
	if ec then return ec.r, ec.g, ec.b end
	return 1, 1, 1
end

function SP:WoWColor(name)
	local c = name and _G[name]
	if type(c) == "table" then
		local r, g, b = c.r, c.g, c.b
		if type(r) == "number" and type(g) == "number" and type(b) == "number" then return r, g, b end
	end
	local f = WOW_FALLBACK[name]
	if f then return f[1], f[2], f[3] end
	return 1, 1, 1
end

local function ShieldRGB(mode, which, palette)
	if mode == "magic" then return SP:WoWColor("DEBUFF_TYPE_MAGIC_COLOR") end
	if which == "water" then return PaletteRGB(palette, 3) end
	if which == "earth" then return PaletteRGB(palette, 1) end
	return LOGO_BLUE[1], LOGO_BLUE[2], LOGO_BLUE[3]
end

-- the themed value of one role (not counting a swatch edit): on, r, g, b
local function RoleValue(spot, role, s)
	local kind, theme = role.kind, s.theme
	if kind == "element" then
		if theme == "standard" and not s.palette then return false end
		return true, PaletteRGB(s.palette, role.e)
	elseif kind == "shield" then
		if s.shield == "today" or not s.shield then return false end
		return true, ShieldRGB(s.shield, role.which, s.palette)
	elseif kind == "choice" then
		local ch = spot.choiceByKey and spot.choiceByKey[s.choice]
		if not ch then return false end
		if theme == "standard" and s.choice == spot.choiceDefault.standard then return false end
		if ch.element then return true, PaletteRGB(s.palette, role.e) end
		if ch.wow then return true, SP:WoWColor(ch.wow) end
		if ch.rgb then return true, ch.rgb[1], ch.rgb[2], ch.rgb[3] end
		return false
	elseif kind == "wow" then
		if theme == "standard" then return false end
		return true, SP:WoWColor(role.name)
	elseif kind == "fixed" then
		if theme == "standard" then return false end
		local c = role.rgb
		if c then return true, c[1], c[2], c[3] end
	end
	return false
end

-- ---------------------------------------------------------------------------
-- Bindings: live colour tables the engine rewrites in place
-- ---------------------------------------------------------------------------
local bindings = {}       -- { t =, keyed =, std = {r,g,b}, spot =, role =, painted = bool }
local firstBinding = {}   -- spot -> roleKey -> binding (its Standard copy is the swatch's "today")

local function PaintBinding(b)
	local cc = cache[b.spot]
	local c = cc and cc[b.role]
	local t = b.t
	if c and c.on then
		if b.keyed then t.r, t.g, t.b = c[1], c[2], c[3] else t[1], t[2], t[3] = c[1], c[2], c[3] end
		b.painted = true
	elseif b.painted then
		local s = b.std
		if b.keyed then t.r, t.g, t.b = s[1], s[2], s[3] else t[1], t[2], t[3] = s[1], s[2], s[3] end
		b.painted = false
	end
end

-- ---------------------------------------------------------------------------
-- Rebuild: resolve every spot once into the caches, then repaint bindings.
-- Returns true when any cached colour or state changed.
-- ---------------------------------------------------------------------------
local anyActive = false

local function Rebuild()
	local t = T()
	local changed, any = false, false
	for id, spot in pairs(SPOTS) do
		local s = st[id]
		local theme = ResolveSpotTheme(t, id)
		local palette = ResolvePalette(t, id, theme)
		local shield = ResolveShield(t, id, theme)
		local choice = ResolveChoice(t, spot, theme)
		local fx = spot.effects or spot.signature
		local look = ResolveLook(t, spot)
		local sig = fx and ResolveSignature(t, spot) or false
		local boxed = (spot.box and theme == "minimal") and true or false
		local showAs = ResolveShowAs(t, id)
		if s.theme ~= theme or s.palette ~= palette or s.shield ~= shield or s.choice ~= choice
			or s.look ~= look or s.sig ~= sig or s.boxed ~= boxed or s.showAs ~= showAs then
			changed = true
		end
		s.theme, s.palette, s.shield, s.choice, s.look, s.sig, s.boxed, s.showAs = theme, palette, shield, choice, look, sig, boxed, showAs
		local active = theme ~= "standard" or boxed or sig or (fx and look ~= "standard")
			or (spot.choices ~= nil and choice ~= spot.choiceDefault.standard)
		local o = SpotOverride(t, id)
		local edits = o and type(o.colors) == "table" and o.colors
		local cc = cache[id]
		for _, role in ipairs(spot.roles) do
			local c = cc[role.key]
			local on, r, g, b = false, nil, nil, nil
			if not role.setting then
				local e = edits and edits[role.key]
				if type(e) == "table" and type(e.r) == "number" then
					on, r, g, b = true, e.r, e.g or 0, e.b or 0
				else
					on, r, g, b = RoleValue(spot, role, s)
				end
			end
			if on then
				if not c.on or c[1] ~= r or c[2] ~= g or c[3] ~= b then
					changed = true
					c[1], c[2], c[3], c.on = r, g, b, true
				end
				active = true
			elseif c.on then
				changed = true
				c.on = false
			end
		end
		s.active = active
		if active then any = true end
	end
	anyActive = any
	for i = 1, #bindings do PaintBinding(bindings[i]) end
	return changed
end

-- ---------------------------------------------------------------------------
-- Listeners, debounced repaints (combat deferred)
-- ---------------------------------------------------------------------------
local listeners = {}
function SP:OnThemeChanged(fn)
	if type(fn) == "function" then listeners[#listeners + 1] = fn end
end
local function Notify()
	for i = 1, #listeners do
		local ok, err = pcall(listeners[i])
		if not ok then Report(err) end
	end
end

local watcher = CreateFrame("Frame")
local soon, soonSpare, soonScheduled = {}, {}, false
local deferred, deferredSpare = {}, {}

local function RunList(list)
	for k, fn in pairs(list) do
		list[k] = nil
		local ok, err = pcall(fn)
		if not ok then Report(err) end
	end
end

local function RunSoon()
	soonScheduled = false
	local run = soon
	soon, soonSpare = soonSpare, run
	if InCombatLockdown and InCombatLockdown() then
		for k, fn in pairs(run) do deferred[k] = fn; run[k] = nil end
		watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end
	RunList(run)
end

function SP:ThemeRepaintSoon(key, fn)
	if type(fn) ~= "function" then return end
	soon[key or fn] = fn
	if not soonScheduled then
		soonScheduled = true
		C_Timer.After(0.15, RunSoon)
	end
end

-- ---------------------------------------------------------------------------
-- Setting-backed parts (SP:ThemeSpotSettings)
-- ---------------------------------------------------------------------------
local settingSpots = {}   -- id -> { entries = { ... } }
local pending = {}        -- spot ids waiting for their reconcile
local ready, loggedIn, inApply = false, false, false
local reconcileScheduled = false

-- get(): one value; an AceConfig-style getter returning r, g, b(, a) is packed
local function SafeGet(entry)
	local ok, a, b, c, d = pcall(entry.get)
	if not ok then Report(a); return nil end
	if type(a) == "number" and type(b) == "number" and type(c) == "number" then
		entry._rgbGetter = true
		return { r = a, g = b, b = c, a = d }
	end
	return a
end

-- a theme colour written onto a colour setting keeps that setting's own alpha
local function WithAlpha(v, cur)
	local c = Copy(v)
	if IsColor(c) and IsColor(cur) then
		if c.r ~= nil then
			if c.a == nil then c.a = cur.a or cur[4] end
		elseif c[4] == nil then
			c[4] = cur.a or cur[4]
		end
	end
	return c
end

local function SafeSet(entry, v)
	local ok, err
	if entry._rgbGetter and type(v) == "table" then
		local r, g, b = ColorRGB(v)
		ok, err = pcall(entry.set, r, g, b, v.a or v[4])
	else
		ok, err = pcall(entry.set, v)
	end
	if not ok then Report(err) end
end

local function EntryActive(spot, s, entry)
	if spot.signature then return s.sig end
	if s.theme ~= "standard" then return true end
	local f = entry._follows
	if f == "palette" then return s.palette ~= nil end
	if f == "shield" then return s.shield ~= nil and s.shield ~= "today" end
	if f == "choice" then return spot.choices ~= nil and s.choice ~= spot.choiceDefault.standard end
	return false
end

-- which column of the entry to write: the spot's theme; a signature spot's
-- look (Elemental = shamanpower, Signal = minimal); "shamanpower" for a
-- Standard spot made active by a Colors / Shield Colors / choice override
local function EntryWriteKey(spot, s)
	if spot.signature then return THEME_OF_LOOK[s.look] or "standard" end
	if s.theme ~= "standard" then return s.theme end
	return "shamanpower"
end

local function EntryValue(spot, s, entry)
	local key = EntryWriteKey(spot, s)
	local v = entry[key]
	if v == nil and key == "minimal" then v = entry.shamanpower end
	if type(v) == "function" then
		local ok, res = pcall(v, spot.id, key)
		if not ok then Report(res); return nil end
		v = res
	end
	return v
end

-- Write (or restore) one spot's settings. force = true writes every active
-- entry (a theme was picked: preset); force = "colors" only the colour
-- entries (Reset Colors); otherwise an entry is written only when the theme's
-- value differs from what the engine last wrote, so a change the player made
-- on the setting's own page stays until the theme's value itself changes.
local function ApplySpotSettings(id, force)
	local reg, spot, s = settingSpots[id], SPOTS[id], st[id]
	if not (reg and spot and s) then return false end
	local wrote = false
	for i = 1, #reg.entries do
		local entry = reg.entries[i]
		local eid = entry._id
		if EntryActive(spot, s, entry) then
			local v = EntryValue(spot, s, entry)
			if v ~= nil then
				local t = TW()
				if not t then return wrote end
				local snap = Sub(Sub(t, "snapshot"), id)
				local wr = Sub(Sub(t, "written"), id)
				local w = wr[eid]
				local f = force == true or (force == "colors" and entry.role ~= nil)
				if f or not w or not Near(w.v, v) then
					local cur = SafeGet(entry)
					if snap[eid] == nil then snap[eid] = { v = Copy(cur) } end   -- the player's own value, once
					if not Near(cur, v) then SafeSet(entry, WithAlpha(v, cur)); wrote = true end
					wr[eid] = { v = Copy(v) }
				end
			end
		else
			local t = T()
			local snap = t and type(t.snapshot) == "table" and t.snapshot[id]
			local saved = type(snap) == "table" and snap[eid]
			if type(saved) == "table" then
				if not Near(SafeGet(entry), saved.v) then SafeSet(entry, Copy(saved.v)); wrote = true end
				snap[eid] = nil
				local wr = type(t.written) == "table" and t.written[id]
				if type(wr) == "table" then wr[eid] = nil end
			end
		end
	end
	-- bookkeeping: which theme was last written to this spot's settings
	local t = T()
	if t then
		local snap = type(t.snapshot) == "table" and t.snapshot[id]
		if type(snap) == "table" and next(snap) then
			Sub(t, "applied")[id] = EntryWriteKey(spot, s)
		else
			if type(t.snapshot) == "table" then t.snapshot[id] = nil end
			if type(t.written) == "table" then t.written[id] = nil end
			if type(t.applied) == "table" then t.applied[id] = nil end
		end
	end
	return wrote
end

-- drop empty tables; SP.opt.theme goes away when nothing is left in it
local SUBS = { "spots", "snapshot", "applied", "written" }
local function Prune()
	local o = SP.opt
	local t = o and o.theme
	if type(t) ~= "table" then return end
	t.effects, t.signature = nil, nil   -- effects are not part of the themes (left by earlier test builds)
	if type(t.spots) == "table" then
		for id, x in pairs(t.spots) do
			if type(x) ~= "table" then t.spots[id] = nil
			else
				x.effects, x.signature = nil, nil
				if type(x.colors) == "table" and not next(x.colors) then x.colors = nil end
				if not next(x) then t.spots[id] = nil end
			end
		end
	end
	for _, k in ipairs(SUBS) do
		local x = t[k]
		if type(x) == "table" then
			if k ~= "spots" and k ~= "applied" then
				for id, v in pairs(x) do if type(v) ~= "table" or not next(v) then x[id] = nil end end
			end
			if not next(x) then t[k] = nil end
		elseif x ~= nil then
			t[k] = nil
		end
	end
	if t.global == "standard" then t.global = nil end
	if not next(t) then o.theme = nil end
end

-- the one path every change takes: resolve, write the settings, resolve again
-- (a written palette changes SP.ElementColors), repaint
local function ApplyAll(force)
	inApply = true
	Rebuild()
	local wrote = false
	for id in pairs(settingSpots) do
		local f = force
		if type(force) == "string" and force ~= "colors" then f = (force == id) end
		if ApplySpotSettings(id, f) then wrote = true end
	end
	inApply = false
	Prune()
	Rebuild()
	return wrote
end

local function Changed(force)
	SP.ThemeChangedThisSession = true
	if not ready then return end
	ApplyAll(force)
	Notify()
end

-- reconcile the spots registered since the last pass: returns wrote, changed
local function ReconcilePending()
	inApply = true
	local changed = Rebuild()
	local wrote = false
	for id in pairs(pending) do
		pending[id] = nil
		if ApplySpotSettings(id, false) then wrote = true end
	end
	inApply = false
	Prune()
	if Rebuild() then changed = true end
	return wrote, changed
end

local function FlushReconcile()
	reconcileScheduled = false
	if not ready or not next(pending) then return end
	local wrote, changed = ReconcilePending()
	if wrote or changed then Notify() end
end

local function ScheduleReconcile()
	if not ready or not loggedIn then return end   -- flushed at ready / at PLAYER_LOGIN
	if reconcileScheduled then return end
	reconcileScheduled = true
	C_Timer.After(0, FlushReconcile)
end

function SP:ThemeSpotSettings(spotId, entries)
	if type(spotId) ~= "string" or type(entries) ~= "table" then return end
	local spot = SPOTS[spotId] or DynamicSpot(spotId)
	local reg = settingSpots[spotId]
	if not reg then reg = { entries = {} }; settingSpots[spotId] = reg end
	for _, e in ipairs(entries) do
		if type(e) == "table" and type(e.get) == "function" and type(e.set) == "function" then
			local eid = tostring(e.key or e.role or ("#" .. (#reg.entries + 1)))
			e._id = eid
			local replaced = false
			for i, old in ipairs(reg.entries) do
				if old._id == eid then reg.entries[i] = e; replaced = true; break end
			end
			if not replaced then reg.entries[#reg.entries + 1] = e end
			local follows = e.follows
			if e.role ~= nil then
				local rk = tostring(e.role)
				local role = spot.roleByKey[rk]
				if not role then
					role = { key = rk, label = e.label or rk, kind = "setting" }
					spot.roles[#spot.roles + 1] = role
					AddRole(spot, role)
				end
				role.setting = e
				role.placeholder = nil
				if e.label and role.kind == "setting" then role.label = e.label end
				follows = follows or FOLLOWS_OF_KIND[role.kind]
			end
			if not follows and spot.followsPalette then follows = "palette" end
			e._follows = follows
		end
	end
	-- a placeholder role nobody registered a setting for goes away
	for i = #spot.roles, 1, -1 do
		local r = spot.roles[i]
		if r.placeholder and not r.setting then
			table.remove(spot.roles, i)
			spot.roleByKey[r.key] = nil
		end
	end
	pending[spotId] = true
	ScheduleReconcile()
end

-- ---------------------------------------------------------------------------
-- Read side (paint code). Nothing here allocates.
-- ---------------------------------------------------------------------------
function SP:ThemeColor(spot, role)
	local cc = cache[spot]
	local c = cc and cc[role]
	if c and c.on then return c[1], c[2], c[3] end
	return nil
end

function SP:ThemeElement(spot, e)
	local cc = cache[spot]
	local c = cc and cc[e]
	if c and c.on then return c[1], c[2], c[3] end
	local ec = SP.ElementColors and SP.ElementColors[e]
	if ec then return ec.r, ec.g, ec.b end
	return 1, 1, 1
end

-- the themed alpha of a role (the navy panels' 92%), or nil = keep today's
function SP:ThemeAlpha(spot, role)
	local cc = cache[spot]
	local c = cc and cc[role]
	if not (c and c.on) then return nil end
	local def = SPOTS[spot]
	local r = def and def.roleByKey[tostring(role)]
	return r and r.alpha or nil
end

function SP:ThemeBind(tbl, spot, role)
	if type(tbl) ~= "table" or spot == nil or role == nil then return end
	local keyed = tbl.r ~= nil
	local b = { t = tbl, keyed = keyed, spot = spot, role = role, painted = false,
		std = keyed and { tbl.r, tbl.g, tbl.b } or { tbl[1], tbl[2], tbl[3] } }
	bindings[#bindings + 1] = b
	local fb = firstBinding[spot]
	if not fb then fb = {}; firstBinding[spot] = fb end
	local rk = tostring(role)
	if not fb[rk] then fb[rk] = b end
	if ready then PaintBinding(b) end
end

function SP:ThemeActive(spot)
	local s = st[spot]
	return s and s.active or false
end
function SP:ThemeSpotTheme(spot)
	local s = st[spot]
	if s then return s.theme end
	return ResolveSpotTheme(T(), spot)
end
function SP:ThemeMinimal(spot)
	local s = st[spot]
	return s ~= nil and s.theme == "minimal"
end
function SP:ThemeBoxed(spot)
	local s = st[spot]
	return s and s.boxed or false
end
function SP:ThemeShowAs(spot)
	local s = st[spot]
	return s and s.showAs or "both"
end
function SP:ThemeChoice(spot)
	local s = st[spot]
	return s and s.choice or nil
end
function SP:ThemeEffectLook(spot)
	local s = st[spot]
	return s and s.look or "standard"
end
function SP:ThemeSignature(spot)
	local s = st[spot]
	return s and s.sig or false
end
function SP:ThemeSpotPalette(spot)   -- "classic" / "blizzard" / "shamanpower" / "custom", nil = today's Appearance palette
	local s = st[spot]
	local p = s and s.palette
	if p == "own" then return nil end
	return p
end
function SP:ThemeShieldMode(spot)    -- "today" / "palette" / "magic"
	local s = st[spot]
	return s and s.shield or "today"
end
function SP:ThemePaletteRGB(key, e)
	return PaletteRGB(key, e)
end

-- ---------------------------------------------------------------------------
-- The Themes page's side
-- ---------------------------------------------------------------------------
function SP:ThemeSpot(id) return SPOTS[id] end
function SP:ThemeGlobal()
	local t = T()
	return (t and THEMES[t.global] and t.global) or "standard"
end
function SP:ThemeField(field)            -- a raw theme-level field (nil = the theme's default)
	local t = T()
	return t and t[field]
end
function SP:ThemeSpotField(spot, field)  -- a raw per-spot override (nil = Use General Theme / Use Theme's)
	local o = SpotOverride(T(), spot)
	return o and o[field]
end
function SP:ThemeRoleIsSetting(spot, role)
	local def = SPOTS[spot]
	local r = def and def.roleByKey[tostring(role)]
	return (r and r.setting) and true or false
end
function SP:ThemeSetRoleStd(spot, role, std)   -- a painter declares today's colour for the swatch
	local def = SPOTS[spot]
	local r = def and def.roleByKey[tostring(role)]
	if not r then return end
	r.std = std
	r.stdRGB = type(std) == "string" and RGB(std) or nil
end

local function EntryRGB(entry)
	if entry.getRGB then
		local ok, r, g, b = pcall(entry.getRGB)
		if ok and type(r) == "number" then return r, g, b end
		return nil
	end
	local v = SafeGet(entry)
	if IsColor(v) then return ColorRGB(v) end
	return nil
end

local function StdRGB(def, rd)
	local fb = firstBinding[def.id]
	local b = fb and fb[rd.key]
	if b then return b.std[1], b.std[2], b.std[3] end
	if type(rd.std) == "function" then
		local ok, r, g, bb = pcall(rd.std)
		if ok and type(r) == "number" then return r, g, bb end
	end
	if rd.stdRGB then return rd.stdRGB[1], rd.stdRGB[2], rd.stdRGB[3] end
	if rd.kind == "element" and rd.e then
		local ec = SP.ElementColors and SP.ElementColors[rd.e]
		if ec then return ec.r, ec.g, ec.b end
	end
	return 1, 1, 1
end

local function RoleSource(def, rd, s)
	if rd.kind == "wow" then return "wow" end
	if rd.kind == "shield" and s.shield == "magic" then return "wow" end
	if rd.kind == "choice" then
		local ch = def.choiceByKey and def.choiceByKey[s.choice]
		if ch and ch.wow then return "wow" end
	end
	return "theme"
end

-- r, g, b, source ("setting" / "custom" / "wow" / "theme" / "standard")
function SP:ThemeDisplayColor(spot, role)
	local def = SPOTS[spot]
	local rk = role ~= nil and tostring(role)
	local rd = def and rk and def.roleByKey[rk]
	if not rd then return 1, 1, 1, "standard" end
	if rd.setting then
		local r, g, b = EntryRGB(rd.setting)
		if r then return r, g, b, "setting" end
	end
	local o = SpotOverride(T(), spot)
	local e = o and type(o.colors) == "table" and o.colors[rk]
	if type(e) == "table" and type(e.r) == "number" then return e.r, e.g or 0, e.b or 0, "custom" end
	local c = cache[spot] and cache[spot][rk]
	if c and c.on then return c[1], c[2], c[3], RoleSource(def, rd, st[spot]) end
	local r, g, b = StdRGB(def, rd)
	return r, g, b, "standard"
end

function SP:ThemeIsCustom()
	local t = T()
	if not t then return false end
	if PALETTE_KEY[t.palette] or SHIELD_KEY[t.shield] then return true end
	if type(t.spots) == "table" then
		for _, o in pairs(t.spots) do
			if type(o) == "table" and next(o) then return true end
		end
	end
	-- a setting-backed look changed away from the theme's value on its own page
	for id, reg in pairs(settingSpots) do
		local spot, s = SPOTS[id], st[id]
		if spot and s and s.theme ~= "standard" and not spot.signature then
			for i = 1, #reg.entries do
				local entry = reg.entries[i]
				if EntryActive(spot, s, entry) then
					local v = EntryValue(spot, s, entry)
					if v ~= nil and not Near(SafeGet(entry), v) then return true end
				end
			end
		end
	end
	return false
end

-- ---------------------------------------------------------------------------
-- Change side. Each one applies, repaints and marks the session dirty.
-- ---------------------------------------------------------------------------
SP.ThemeChangedThisSession = false

-- a theme card: every spot back to "Use General Theme", the theme written everywhere
-- ---------------------------------------------------------------------------
-- The saved Custom theme (SP.opt.theme.saved): the moment the player leaves a
-- Custom look for a theme card, it is kept, so the Custom card can bring it back:
-- the theme it started from, every per-part choice, the Colors / Shield Colors
-- cards, and each setting the player changed on its own settings page.
-- One per profile; a newer Custom replaces it.
-- ---------------------------------------------------------------------------
local function CaptureCustom(t)
	local saved = { base = t.global, spots = Copy(t.spots), palette = t.palette, shield = t.shield }
	for id, reg in pairs(settingSpots) do
		local spot, s = SPOTS[id], st[id]
		if spot and s and s.theme ~= "standard" and not spot.signature then
			for i = 1, #reg.entries do
				local entry = reg.entries[i]
				if EntryActive(spot, s, entry) then
					local v = EntryValue(spot, s, entry)
					local cur = SafeGet(entry)
					if v ~= nil and not Near(cur, v) then
						saved.settings = saved.settings or {}
						local byId = saved.settings[id] or {}
						saved.settings[id] = byId
						byId[entry._id] = { v = Copy(cur) }
					end
				end
			end
		end
	end
	t.saved = saved
end

function SP:ThemeHasSavedCustom()
	local t = T()
	return t ~= nil and type(t.saved) == "table"
end
function SP:ThemeSavedCustomBase()   -- the theme the saved Custom started from
	local t = T()
	local sv = t and t.saved
	return type(sv) == "table" and THEMES[sv.base] and sv.base or "standard"
end
function SP:ThemeSavedCustomPalette()   -- its Colors card, or nil (the theme's own)
	local t = T()
	local sv = t and t.saved
	return type(sv) == "table" and PALETTE_KEY[sv.palette] and sv.palette or nil
end

-- the Custom card: the saved Custom back, exactly
function SP:ThemeLoadCustom()
	local t = T()
	local sv = t and t.saved
	if type(sv) ~= "table" then return end
	if self:ThemeIsCustom() then return end   -- a Custom look is already in use
	t.global = (THEMES[sv.base] and sv.base ~= "standard") and sv.base or nil
	t.spots = Copy(sv.spots)
	t.palette = PALETTE_KEY[sv.palette] and sv.palette or nil
	t.shield = SHIELD_KEY[sv.shield] and sv.shield or nil
	Changed(true)   -- the theme and every part's choice, as a preset
	-- then the player's own changes made on the settings pages
	local wrote = false
	for id, byId in pairs(type(sv.settings) == "table" and sv.settings or {}) do
		local reg = settingSpots[id]
		if reg and type(byId) == "table" then
			for i = 1, #reg.entries do
				local entry = reg.entries[i]
				local x = byId[entry._id]
				if type(x) == "table" then SafeSet(entry, Copy(x.v)); wrote = true end
			end
		end
	end
	if wrote then Notify() end
end

function SP:SetThemeGlobal(key)
	if not THEMES[key] then return end
	-- the card already picked, with nothing changed since: nothing to do (and no reload prompt)
	local cur = T()
	if ((cur and THEMES[cur.global] and cur.global) or "standard") == key and not SP:ThemeIsCustom() then return end
	local t = TW()
	if not t then return end
	if SP:ThemeIsCustom() then CaptureCustom(t) end   -- the Custom look is kept for the Custom card
	t.global = (key ~= "standard") and key or nil
	t.spots, t.palette, t.shield, t.effects, t.signature = nil, nil, nil, nil, nil
	Changed(true)
end

-- (no effects fields: effects are not part of the themes, see ResolveLook)
-- borders / bordersFlyouts: General > Themes, Element-Colored Borders on the totem bar
-- and its flyouts (ShamanPower.lua ThemePaintTotemBorders)
local THEME_FIELDS = { palette = PALETTE_KEY, shield = SHIELD_KEY, showAs = SHOWAS_KEY,
	borders = { [true] = true }, bordersFlyouts = { [true] = true }, bordersCooldown = { [true] = true } }

local function CleanCustom(v)
	if type(v) ~= "table" then return nil end
	local c = {}
	for e = 1, 4 do
		local x = v[e]
		local r, g, b
		if IsColor(x) then r, g, b = ColorRGB(x) else r, g, b = PaletteRGB("shamanpower", e) end
		c[e] = { r = r, g = g, b = b }
	end
	return c
end

function SP:SetThemeField(field, value)
	if field ~= "custom" and not THEME_FIELDS[field] then return end   -- (never creates the theme table for nothing)
	local t = TW()
	if not t then return end
	if field == "custom" then
		t.custom = CleanCustom(value)
	elseif THEME_FIELDS[field] then
		if value ~= nil and not THEME_FIELDS[field][value] then return end
		t[field] = value
	else
		return
	end
	Changed(nil)
end

-- one swatch of the Themes tab's Custom palette
function SP:SetThemeCustomColor(e, r, g, b)
	if type(e) ~= "number" or e < 1 or e > 4 then return end
	local t = TW()
	if not t then return end
	local c = CleanCustom(t.custom or {})
	if r ~= nil then
		c[e] = { r = r, g = g, b = b }
	else
		local pr, pg, pb = PaletteRGB("shamanpower", e)
		c[e] = { r = pr, g = pg, b = pb }
	end
	t.custom = c
	Changed(nil)
end

function SP:SetSpotField(spot, field, value)
	local def = SPOTS[spot]
	if not def then return end
	if field == "choice" then
		if value ~= nil and not (def.choiceByKey and def.choiceByKey[value]) then return end
	elseif field == "theme" then
		if value ~= nil and not THEMES[value] then return end
	elseif THEME_FIELDS[field] then
		if value ~= nil and not THEME_FIELDS[field][value] then return end
	else
		return
	end
	local t = TW()
	if not t then return end
	Sub(Sub(t, "spots"), spot)[field] = value
	Changed(field == "theme" and spot or nil)   -- a spot's Theme dropdown is a preset for that spot
end

local function ShapeColor(cur, r, g, b)
	if type(cur) == "table" and cur.r == nil and type(cur[1]) == "number" then
		return { r, g, b, cur[4] }
	end
	return { r = r, g = g, b = b, a = type(cur) == "table" and cur.a or nil }
end

function SP:SetSpotColor(spot, role, r, g, b)
	local def = SPOTS[spot]
	if not def or role == nil then return end
	local rk = tostring(role)
	local rd = def.roleByKey[rk]
	local entry = rd and rd.setting
	if entry then
		-- the same setting the module page edits
		if r ~= nil then
			if entry.setRGB then
				local ok, err = pcall(entry.setRGB, r, g, b)
				if not ok then Report(err) end
			else
				SafeSet(entry, ShapeColor(SafeGet(entry), r, g, b))
			end
		elseif ready then
			local s = st[spot]
			if EntryActive(def, s, entry) then
				local v = EntryValue(def, s, entry)
				if v ~= nil then SafeSet(entry, WithAlpha(v, SafeGet(entry))) end
			end
		end
		Changed(nil)
		return
	end
	local t = TW()
	if not t then return end
	local o = Sub(Sub(t, "spots"), spot)
	if r == nil then
		if type(o.colors) == "table" then o.colors[rk] = nil end
	else
		Sub(o, "colors")[rk] = { r = r, g = g, b = b }
	end
	Changed(nil)
end

-- "Reset Colors to the Theme": colour edits, Colors and Shield Colors choices go
function SP:ResetThemeColors()
	local t = T()
	if t then
		t.palette, t.shield = nil, nil
		if type(t.spots) == "table" then
			for _, o in pairs(t.spots) do
				if type(o) == "table" then o.colors, o.palette, o.shield = nil, nil, nil end
			end
		end
	end
	Changed("colors")
end

-- profile change (and anyone who needs a full re-resolve): reconcile every
-- registered spot with the profile's theme, repaint
function SP:ApplyTheme()
	if not ready then return end
	local was = anyActive
	local wrote = ApplyAll(false)
	if wrote or was or anyActive then Notify() end
end

-- ---------------------------------------------------------------------------
-- Start-up: SP.opt exists after the addon's OnInitialize; module addons load
-- after it and their saved variables are only there at PLAYER_LOGIN.
-- ---------------------------------------------------------------------------
local function OnReady()
	if ready or not SP.opt then return end
	ready = true
	-- the core's own settings (SP.opt is loaded); nothing is drawn yet, so no repaint
	ReconcilePending()
	if loggedIn and next(pending) then ScheduleReconcile() end
end

local function OnLogin()
	loggedIn = true
	if not ready then OnReady() end
	if not ready then return end
	local wrote, changed = ReconcilePending()   -- the modules' settings (their saved variables are in)
	-- anything drawn before the colours were resolved repaints once (never on Standard)
	if wrote or changed or anyActive then Notify() end
end

watcher:SetScript("OnEvent", function(self, event)
	if event == "PLAYER_LOGIN" then
		self:UnregisterEvent("PLAYER_LOGIN")
		OnLogin()
	elseif event == "PLAYER_REGEN_ENABLED" then
		self:UnregisterEvent("PLAYER_REGEN_ENABLED")
		local run = deferred
		deferred, deferredSpare = deferredSpare, run
		RunList(run)
	elseif event == "ADDON_LOADED" then
		if SP.opt then
			self:UnregisterEvent("ADDON_LOADED")
			OnReady()
		end
	end
end)
if IsLoggedIn and IsLoggedIn() then
	loggedIn = true
else
	watcher:RegisterEvent("PLAYER_LOGIN")
end

if SP.opt then
	OnReady()
elseif type(SP.OnInitialize) == "function" then
	hooksecurefunc(SP, "OnInitialize", OnReady)
else
	watcher:RegisterEvent("ADDON_LOADED")
end

if type(SP.OnProfileChanged) == "function" then
	hooksecurefunc(SP, "OnProfileChanged", function() SP:ApplyTheme() end)
end

-- the Appearance palette feeds every "today's palette" colour: re-resolve when
-- it changes (only repaints when a themed colour actually moved)
if type(SP.ApplyElementColors) == "function" then
	hooksecurefunc(SP, "ApplyElementColors", function()
		if not ready or inApply then return end
		if Rebuild() then Notify() end
	end)
end

-- the core registers its own setting-backed parts (ShamanPower.lua loaded first)
if type(SP.ThemeRegisterCore) == "function" then
	local ok, err = pcall(SP.ThemeRegisterCore, SP)
	if not ok then Report(err) end
end
