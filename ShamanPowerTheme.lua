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
	classColors = { { key = nil, label = "Use Theme's" }, { key = "wow", label = "WoW's" }, { key = "subtle", label = "Subtle" },
	            { key = "stronger", label = "Stronger" }, { key = "vibrant", label = "Vibrant" }, { key = "muted", label = "Muted" } },
}

-- Class Colors (General > Themes, the cards under Element Colors; a part's own
-- dropdown on Party Dots / Coverage Dots: Class Colors). The same hue for every
-- class in every set; WoW's = RAID_CLASS_COLORS exactly (what Standard shows).
-- The ShamanPower themes pick Subtle.
SP.CLASS_COLOR_SETS = {
	{ key = "wow", label = "WoW's", sub = "The game's own class colors, exactly. What Standard always shows." },
	{ key = "subtle", label = "Subtle", sub = "The same hues, brightness evened out a little for ShamanPower's navy panels.", colors = {
		WARRIOR = "D2A878", PALADIN = "F28EC0", HUNTER = "A6CF6E", ROGUE = "F2E45F", PRIEST = "E6EAF0",
		SHAMAN = "2F8CF0", MAGE = "6AC6EE", WARLOCK = "A897DD", DRUID = "FF8A26" } },
	{ key = "stronger", label = "Stronger", sub = "The same hues, evened out more: priest white and rogue yellow calmer, shaman and warlock brighter.", colors = {
		WARRIOR = "DBB384", PALADIN = "EE95C6", HUNTER = "9EC66A", ROGUE = "E4D35A", PRIEST = "D3D9E4",
		SHAMAN = "4A9FF6", MAGE = "6CBDE8", WARLOCK = "B7A8E9", DRUID = "FF9640" } },
	{ key = "vibrant", label = "Vibrant", sub = "Richer and punchier: more saturation, every class still its own color.", colors = {
		WARRIOR = "D59958", PALADIN = "FF5FA5", HUNTER = "A7E356", ROGUE = "FFF34F", PRIEST = "FFFFFF",
		SHAMAN = "007BF4", MAGE = "45CDFF", WARLOCK = "8469D2", DRUID = "FF8111" } },
	{ key = "muted", label = "Muted", sub = "Softer and dustier, easy on the eyes on a busy screen.", colors = {
		WARRIOR = "B8A18A", PALADIN = "D894B1", HUNTER = "AAC08C", ROGUE = "DBD583", PRIEST = "C8CDD6",
		SHAMAN = "4889CA", MAGE = "85BCD1", WARLOCK = "9D94BA", DRUID = "CF915A" } },
}
local CLASS_SET_KEY, CLASS_SET_RGB = {}, {}
for _, set in ipairs(SP.CLASS_COLOR_SETS) do
	CLASS_SET_KEY[set.key] = true
	if set.colors then
		local t = {}
		for class, hex in pairs(set.colors) do
			t[class] = { tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255 }
		end
		CLASS_SET_RGB[set.key] = t
	end
end
SP.CLASS_SET_KEY = CLASS_SET_KEY

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
		  note = "The pulse wipe on the icons and the pulse bar: white, the element color or logo blue. Pulse Bar Color on Totem Bar > Duration Bars can still change it." },
		{ id = "tb.dots-missing", label = "Party Dots: Missing Buff", roles = { Role("missing", "Missing Buff", "wow", "RED_FONT_COLOR", "FF0000") },
		  note = "The dot for a party member without your totem's buff." },
		{ id = "tb.dots-class", label = "Party Dots: Class Colors", roles = {}, classColors = true,
		  note = "The party dots in class colors. Class Colors picks the set: Use Theme's follows the Class Colors cards at the top." },
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
		{ id = "mod.coverage-dots-class", label = "Coverage Dots: Class Colors", roles = {}, classColors = true,
		  note = "The coverage dots in class colors. Class Colors picks the set: Use Theme's follows the Class Colors cards at the top." },
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
-- Class Colors: the set a part's class-colored dots use. Its own dropdown, else
-- the cards at the top, else the theme's: Standard = WoW's, the ShamanPower themes = Subtle.
function SP:ThemeClassColorSetGlobal()
	local t = T()
	if t and CLASS_SET_KEY[t.classColors] then return t.classColors end
	return (SP:ThemeGlobal() == "standard") and "wow" or "subtle"
end
function SP:ThemeClassColorSetDefault()   -- the picked theme's own set (the cards store nil for it)
	return (SP:ThemeGlobal() == "standard") and "wow" or "subtle"
end
function SP:ThemeClassColorSet(spot)
	local t = T()
	local o = spot and SpotOverride(t, spot)
	if o and CLASS_SET_KEY[o.classColors] then return o.classColors end
	if t and CLASS_SET_KEY[t.classColors] then return t.classColors end
	return (ResolveSpotTheme(t, spot) == "standard") and "wow" or "subtle"
end
-- a class's r, g, b in a set (nil: WoW's own, RAID_CLASS_COLORS)
function SP:ClassSetRGB(set, class)
	local t = CLASS_SET_RGB[set]
	local c = t and class and t[class]
	if c then return c[1], c[2], c[3] end
	return nil
end
function SP:ThemeClassSetRGB(spot, class)
	return self:ClassSetRGB(self:ThemeClassColorSet(spot), class)
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

-- Theme cards (presets, Your Themes, sharing): the section at the end of this file.
local Cards = {}

-- 3.0.4's Custom test: a theme-level change, or a setting a theme wrote changed on its
-- own page. Now only the way in for a player who has no card yet (Cards.Migrate).
function Cards.OldIsCustom()
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
-- The whole look beyond the theme's colors, kept on the Custom card with them: the
-- Themes tab's own fields (borders, Border Size, Class Colors, Show Icons As) and
-- every look (bar textures, shapes, gradients, Gem Dot Finish, Duration Bar
-- Background, each shield's charge look and color). A reset button also keeps
-- the colors every page has (LOOK.CaptureColors, after RESET_COLOR_KEYS).
local LOOK = {
	theme = { "borders", "bordersFlyouts", "bordersCooldown", "bordersCooldownFlyouts", "borderSize", "borderSizeFlyouts",
		"borderSizeCooldown", "borderSizeCooldownFlyouts", "classColors", "showAs" },
	opt = { "barTexture", "dotShape", "dotGem", "glowShape", "frameEdge", "iconShape", "iconShapeCooldown",
		"iconShapeReady", "iconShapeSplit", "iconBordersSquare", "durationBarBackground",
		"barGradientDirection", "barGradientDirections" },
	shield = { "lookLS", "lookWS", "lookES", "barLook", "orbLook", "chargeColorLS", "chargeColorWS", "chargeColorES" },
}
for _, field in ipairs({ "barGradient", "outlineGradient", "chargeGradient" }) do
	for _, part in ipairs({ "", "Direction", "Color1", "Color2", "Fade" }) do LOOK.opt[#LOOK.opt + 1] = field .. part end
end
function LOOK.Capture(t)
	local o = SP.opt
	local look = { theme = {}, opt = {}, shield = {} }
	for _, k in ipairs(LOOK.theme) do look.theme[k] = t and t[k] end
	if type(o) ~= "table" then return look end
	for _, k in ipairs(LOOK.opt) do look.opt[k] = Copy(o[k]) end
	local areas = o.barTextureAreas
	look.shieldTexture = type(areas) == "table" and areas.shieldcharges or nil
	local sc = o.shieldChargeDisplay
	if type(sc) == "table" then
		for _, k in ipairs(LOOK.shield) do look.shield[k] = Copy(sc[k]) end
	end
	return look
end

local function CaptureCustom(t)
	local saved = { base = t.global, spots = Copy(t.spots), palette = t.palette, shield = t.shield, look = LOOK.Capture(t) }
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

-- a Custom look kept by 3.0.4 (t.saved), before the theme cards: the Custom card
-- brings it back once, then it is an unsaved Custom look like any other
function Cards.LegacyLoad()
	local t = T()
	local sv = t and t.saved
	if type(sv) ~= "table" then return end
	if type(sv.colors) == "table" then
		-- a reset kept the colors every page has: they go back under Standard first,
		-- so the theme below keeps them as the player's own (the caller reloads)
		t.global, t.spots, t.palette, t.shield = nil, nil, nil, nil
		Changed(true)
		LOOK.RestoreColors(sv.colors)
	end
	if type(sv.look) == "table" then LOOK.Restore(t, sv.look) end   -- (a Custom kept before 3.0.4 has none)
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
	if type(sv.look) == "table" then LOOK.Repaint() end
	t.saved = nil
end
-- the Custom card holds colors a reset put back to default: loading it reloads
function SP:ThemeCustomNeedsReload()
	local t = T()
	local sv = t and t.saved
	return type(sv) == "table" and type(sv.colors) == "table" and not self:ThemeIsCustom() and LOOK.ColorsDiffer(sv.colors)
end


-- (no effects fields: effects are not part of the themes, see ResolveLook)
-- borders / bordersFlyouts: General > Themes, Element-Colored Borders on the totem bar
-- and its flyouts (ShamanPower.lua ThemePaintTotemBorders)
-- Border Size (px) under each of the three toggles; 2 = nil (the default)
local BORDER_SIZE = { [1] = true, [3] = true, [4] = true, [5] = true, [6] = true }
local THEME_FIELDS = { palette = PALETTE_KEY, shield = SHIELD_KEY, showAs = SHOWAS_KEY, classColors = CLASS_SET_KEY,
	borders = { [true] = true }, bordersFlyouts = { [true] = true }, bordersCooldown = { [true] = true },
	borderSize = BORDER_SIZE, borderSizeFlyouts = BORDER_SIZE, borderSizeCooldown = BORDER_SIZE,
	bordersCooldownFlyouts = { [true] = true }, borderSizeCooldownFlyouts = BORDER_SIZE }

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

-- the colors picked on the Themes tab outside the theme engine: each shield's
-- Charge Color and the gradients' Two-Tone colors (nil = their default)
local GRADIENT_COLOR_KEYS = { "barGradientColor1", "barGradientColor2", "outlineGradientColor1",
	"outlineGradientColor2", "chargeGradientColor1", "chargeGradientColor2" }
local function ClearPickedColors(o)
	if type(o) ~= "table" then return end
	for _, k in ipairs(GRADIENT_COLOR_KEYS) do o[k] = nil end
	local s = o.shieldChargeDisplay
	if type(s) == "table" then s.chargeColorLS, s.chargeColorWS, s.chargeColorES = nil, nil, nil end
end

-- "Reset Colors for Current Theme": colour edits, Colors and Shield Colors choices go,
-- and the Charge Colors and Two-Tone colors picked on the same page
function SP:ResetThemeColors()
	local t = T()
	if t then
		t.palette, t.shield, t.classColors = nil, nil, nil
		if type(t.spots) == "table" then
			for _, o in pairs(t.spots) do
				if type(o) == "table" then o.colors, o.palette, o.shield, o.classColors = nil, nil, nil, nil end
			end
		end
	end
	ClearPickedColors(SP.opt)
	Changed("colors")
	if SP.RefreshGradients then SP:RefreshGradients() end   -- the bars, outlines and charges repaint
end

-- Reset All Colors and Theme (General > Themes, the emergency button): the Themes tab back
-- to Standard with nothing overridden (a Custom look is kept on the Custom card
-- first, as a theme card does), then every colour setting in ShamanPower back to
-- how it comes, the modules' own included. The caller reloads the interface.
local RESET_COLOR_KEYS = { "elementColorPalette", "elementColorsCustom", "cBuffGood", "cBuffNeedSome",
	"cBuffNeedAll", "compactOutlineColorMode", "compactOutlineColor", "compactIdleColor",
	"totemCooldownTextColor", "pulseBarColor", "pulseFlashColor", "manaTintColor",
	"shieldChargeColors", "cdbarSpellColors" }
-- the colors every page has, kept by a reset (read after the theme has put the
-- player's own back) and put back by the Custom card
function LOOK.CaptureColors(o)
	local c = { opt = {} }
	for _, k in ipairs(RESET_COLOR_KEYS) do c.opt[k] = Copy(o[k]) end
	for _, k in ipairs(GRADIENT_COLOR_KEYS) do c.opt[k] = Copy(o[k]) end
	if type(o.rangeCounter) == "table" then c.rangeElem = o.rangeCounter.useElementColors end
	local rr = ShamanPower_ReadyReminders
	if type(rr) == "table" then c.rr = { borderColor = Copy(rr.borderColor), glowColor = Copy(rr.glowColor), barColor = Copy(rr.barColor) } end
	local tr = ShamanPowerTremorReminderDB
	if type(tr) == "table" then c.tremor = Copy(tr.glowColor) end
	return c
end
function LOOK.RestoreColors(c)
	local o = SP.opt
	if type(o) ~= "table" then return end
	for k, v in pairs(type(c.opt) == "table" and c.opt or {}) do o[k] = Copy(v) end
	if type(o.rangeCounter) == "table" then o.rangeCounter.useElementColors = c.rangeElem end
	local rr = ShamanPower_ReadyReminders
	if type(rr) == "table" and type(c.rr) == "table" then
		rr.borderColor, rr.glowColor, rr.barColor = Copy(c.rr.borderColor), Copy(c.rr.glowColor), Copy(c.rr.barColor)
	end
	local tr = ShamanPowerTremorReminderDB
	if type(tr) == "table" and c.tremor ~= nil then tr.glowColor = Copy(c.tremor) end
end
function LOOK.ColorsDiffer(c)
	local o = SP.opt
	if type(o) ~= "table" then return false end
	for k, v in pairs(type(c.opt) == "table" and c.opt or {}) do
		if not Near(o[k], v) then return true end
	end
	if type(o.rangeCounter) == "table" and o.rangeCounter.useElementColors ~= c.rangeElem then return true end
	local rr = ShamanPower_ReadyReminders
	if type(rr) == "table" and type(c.rr) == "table" then
		for _, k in ipairs({ "borderColor", "glowColor", "barColor" }) do
			if not Near(rr[k], c.rr[k]) then return true end
		end
	end
	local tr = ShamanPowerTremorReminderDB
	if type(tr) == "table" and c.tremor ~= nil and not Near(tr.glowColor, c.tremor) then return true end
	return false
end
-- the look back, as kept (the theme's own fields only where they are still valid)
function LOOK.Restore(t, look)
	local lt = type(look.theme) == "table" and look.theme or {}
	for _, k in ipairs(LOOK.theme) do
		local v = lt[k]
		if v ~= nil and not (THEME_FIELDS[k] and THEME_FIELDS[k][v]) then v = nil end
		t[k] = v
	end
	local o = SP.opt
	if type(o) ~= "table" then return end
	local lo = type(look.opt) == "table" and look.opt or {}   -- (a value can be false: Duration Bar Background off)
	for _, k in ipairs(LOOK.opt) do o[k] = Copy(lo[k]) end
	if look.shieldTexture ~= nil or type(o.barTextureAreas) == "table" then
		o.barTextureAreas = o.barTextureAreas or {}
		o.barTextureAreas.shieldcharges = look.shieldTexture
	end
	o.shieldChargeDisplay = o.shieldChargeDisplay or {}
	local sc = o.shieldChargeDisplay
	local ls = type(look.shield) == "table" and look.shield or {}
	for _, k in ipairs(LOOK.shield) do sc[k] = Copy(ls[k]) end
end
-- every part that draws a look, drawn again
function LOOK.Repaint()
	if SP.RefreshTextures then SP:RefreshTextures() end   -- the textures, Glow Shape, Frame Edge, Icon Shape
	if SP.RefreshIconShapes then SP:RefreshIconShapes() end
	if SP.RefreshGradients then SP:RefreshGradients() end
	if SP.UpdatePartyDotPositions then SP:UpdatePartyDotPositions() end   -- Dot Shape, Gem Dot Finish
	if SP.UpdateCoverageLayout then SP:UpdateCoverageLayout() end
	if SP.ApplyDurationBarOpacity then SP:ApplyDurationBarOpacity() end   -- Duration Bar Background
	if SP.ShieldLookChanged then SP:ShieldLookChanged() end
	if SP.ShieldChargeStyleChanged then SP:ShieldChargeStyleChanged() end
end
-- anything a reset clears that is worth keeping on the Custom card: a theme,
-- the Themes tab's fields, any color, and (Reset Everything) any look
function LOOK.Worth(t, look, everything, defaults)
	if t and THEMES[t.global] and t.global ~= "standard" then return true end
	for _, k in ipairs(LOOK.theme) do if look.theme[k] ~= nil then return true end end
	local o = SP.opt
	for _, k in ipairs(RESET_COLOR_KEYS) do if not Near(o[k], defaults[k]) then return true end end
	for _, k in ipairs(GRADIENT_COLOR_KEYS) do if o[k] ~= nil then return true end end
	-- each shield's Charge Color (cleared by ClearPickedColors, kept in the look)
	local sc = o.shieldChargeDisplay
	if type(sc) == "table" and (sc.chargeColorLS or sc.chargeColorWS or sc.chargeColorES) then return true end
	local rc, drc = o.rangeCounter, defaults.rangeCounter
	if type(rc) == "table" and rc.useElementColors ~= (type(drc) == "table" and drc.useElementColors or nil) then return true end
	-- the modules' colors: against their own defaults (Ready Reminders saves its
	-- defaults, so "is there a color" was always yes and every reset overwrote the
	-- saved Custom look); the defaults tables are the ones the support code reads
	local md = SP.SUPPORT_MODULE_DEFAULTS or {}
	local rr, rrd = ShamanPower_ReadyReminders, md.ShamanPower_ReadyReminders
	if type(rr) == "table" then
		for _, k in ipairs({ "borderColor", "glowColor", "barColor" }) do
			if rr[k] ~= nil and not Near(rr[k], type(rrd) == "table" and rrd[k] or nil) then return true end
		end
	end
	local tr, trd = ShamanPowerTremorReminderDB, md.ShamanPowerTremorReminderDB
	local trGlow = type(trd) == "table" and trd.glowColor or { r = 1, g = 0.8, b = 0 }
	if type(tr) == "table" and tr.glowColor ~= nil and not Near(tr.glowColor, trGlow) then return true end
	if not everything then return false end
	for _, k in ipairs(LOOK.opt) do if not Near(look.opt[k], defaults[k]) then return true end end
	if look.shieldTexture ~= nil then return true end
	local ds = type(defaults.shieldChargeDisplay) == "table" and defaults.shieldChargeDisplay or {}
	for _, k in ipairs(LOOK.shield) do if not Near(look.shield[k], ds[k]) then return true end end
	return false
end

function SP:ResetAllColorsToDefault(everything)
	local o = SP.opt
	if type(o) ~= "table" then return end
	local defaults = SP.db and SP.db.defaults and SP.db.defaults.profile or {}
	-- what this clears goes onto the Custom card first, so the Custom card brings it all back
	local t = T()
	local keep = SP:ThemeIsCustom() or LOOK.Worth(t, LOOK.Capture(t), everything, defaults)
	if keep then
		t = TW()
		Cards.Keep()   -- the look before the reset waits on the Custom card
	end
	if t then
		t.global, t.spots, t.palette, t.shield, t.classColors = nil, nil, nil, nil, nil
		t.borders, t.bordersFlyouts, t.bordersCooldown, t.showAs = nil, nil, nil, nil
		t.borderSize, t.borderSizeFlyouts, t.borderSizeCooldown = nil, nil, nil
		t.bordersCooldownFlyouts, t.borderSizeCooldownFlyouts = nil, nil
		t.custom, t.snapshot, t.written, t.applied = nil, nil, nil, nil
		-- Standard is every default: so are the settings a theme writes (the texture ...)
		Cards.Entries(function(_, e)
			local v = Cards.DefaultOf(e)
			if v ~= nil and not Near(SafeGet(e), v) then SafeSet(e, v) end
		end)
		Changed(true)
		-- the card is Standard; what Standard looks like is worked out after the reload,
		-- once every module has registered (anything the reset left is then Custom)
		t.card, t.baseline, t.forceCustom, t.needBaseline = "standard", nil, nil, true
	end
	for _, k in ipairs(RESET_COLOR_KEYS) do o[k] = Copy(defaults[k]) end
	ClearPickedColors(o)   -- each shield's Charge Color, the gradients' Two-Tone colors
	if type(o.rangeCounter) == "table" then
		local d, v = defaults.rangeCounter, nil
		if type(d) == "table" then v = d.useElementColors end
		o.rangeCounter.useElementColors = v
	end
	-- the modules keep theirs in their own saved tables (nil = their default)
	if type(ShamanPower_ReadyReminders) == "table" then
		ShamanPower_ReadyReminders.borderColor = nil
		ShamanPower_ReadyReminders.glowColor = nil
		ShamanPower_ReadyReminders.barColor = nil
	end
	if type(ShamanPowerTremorReminderDB) == "table" then
		ShamanPowerTremorReminderDB.glowColor = { r = 1, g = 0.8, b = 0 }
	end
end

-- Reset Everything (General > Themes): every setting on the Themes tab back to how
-- it comes. All of Reset All Colors and Theme (a Custom look stays on the Custom
-- card), then every look: the bar textures, shapes, gradients, Duration Bar
-- Background, Gem Dot Finish and each shield's charge look. The caller reloads.
function SP:ResetEverythingToDefault()
	self:ResetAllColorsToDefault(true)
	local o = SP.opt
	if type(o) ~= "table" then return end
	local defaults = SP.db and SP.db.defaults and SP.db.defaults.profile or {}
	for _, k in ipairs({ "barTexture", "dotShape", "dotGem", "glowShape", "frameEdge",
		"iconShape", "iconShapeCooldown", "iconShapeReady", "iconShapeSplit", "iconBordersSquare",
		"durationBarBackground", "barGradientDirections" }) do
		o[k] = Copy(defaults[k])
	end
	for _, field in ipairs({ "barGradient", "outlineGradient", "chargeGradient" }) do
		for _, part in ipairs({ "", "Direction", "Color1", "Color2", "Fade" }) do
			o[field .. part] = Copy(defaults[field .. part])
		end
	end
	if type(o.barTextureAreas) == "table" then o.barTextureAreas.shieldcharges = nil end
	local sc = o.shieldChargeDisplay
	if type(sc) == "table" then
		sc.lookLS, sc.lookWS, sc.lookES, sc.barLook, sc.orbLook = nil, nil, nil, nil, nil
	end
end


-- ===========================================================================
-- Theme cards (user, 2026-09-30). Standard, ShamanPower and ShamanPower Minimal are
-- fixed PRESETS: picking one sets everything the Themes tab holds to that preset,
-- every time (Standard = every default). Any change, on the tab or on a page that
-- edits the same setting, makes the look Custom. A Custom look can be saved under a
-- name (Your Themes, account-wide: every character can pick it) and shared as a
-- code (SPT1:). Unsaved changes wait on the Custom card until saved or discarded.
--
-- One form for all of it, a "flat" map path -> value of everything a theme holds:
--   t.<field>   theme fields (global, spots, palette, shield, custom, borders ...)
--   o.<key>     the looks and colors in the profile (LOOK.opt, RESET/GRADIENT colors)
--   sc.<key>    each shield's look and Charge Color;  o.shieldTexture, o.rangeElementColors
--   rr.<key>, tr.glowColor   the Ready Reminders / Tremor Reminder colors
--   e.<spot>.<entry>         the settings a theme writes (ThemeSpotSettings)
-- It is what Your Themes store, the Custom card holds (t.pending), a share code
-- carries, and t.baseline is: the card as applied. The look is Custom whenever it no
-- longer matches its baseline, whatever changed it. t.card = "standard" /
-- "shamanpower" / "minimal" / "mine:<id>". Effects are not part of a theme.
-- Only on clicks: nothing here runs while playing.
-- ===========================================================================
Cards.THEME_KEYS = { "palette", "shield", "custom" }       -- (plus global, spots and LOOK.theme)
Cards.MODULES = { "ShamanPower_ReadyReminders", "ShamanPowerTremorReminderDB" }
Cards.RR = { "borderColor", "glowColor", "barColor" }
Cards.TREMOR_GLOW = { r = 1, g = 0.8, b = 0 }
Cards.PREFIX = "SPT1:"

function Cards.Defaults()
	return SP.db and SP.db.defaults and SP.db.defaults.profile or {}
end
function Cards.ModuleDefault(name)
	local md = SP.SUPPORT_MODULE_DEFAULTS
	return type(md) == "table" and type(md[name]) == "table" and md[name] or {}
end

-- every setting a theme writes (not the effects' signature spots)
function Cards.Entries(fn)
	for id, reg in pairs(settingSpots) do
		local spot = SPOTS[id]
		if spot and not spot.signature then
			for i = 1, #reg.entries do fn(id, reg.entries[i]) end
		end
	end
end

-- what an entry reads with every setting at its default: its getter run against a
-- copy of the defaults (and empty module tables, which read as their defaults)
function Cards.DefaultOf(entry)
	if not Cards.view then Cards.view = Copy(Cards.Defaults()) end
	local real, keep = SP.opt, {}
	for i, name in ipairs(Cards.MODULES) do keep[i] = rawget(_G, name); _G[name] = {} end
	SP.opt = Cards.view
	local ok, v = pcall(entry.get)
	SP.opt = real
	for i, name in ipairs(Cards.MODULES) do _G[name] = keep[i] end
	if not ok then Report(v) return nil end
	return Copy(v)
end

-- a profile value, as the database hands it back after a reload (nil = its default)
function Cards.Opt(o, d, k)
	local v = o[k]
	if v == nil then v = d[k] end
	return Copy(v)
end

function Cards.Flat()
	local o, t, d = SP.opt, T() or {}, Cards.Defaults()
	local f = {}
	if type(o) ~= "table" then return f end
	f["t.global"] = (THEMES[t.global] and t.global ~= "standard") and t.global or nil
	if type(t.spots) == "table" and next(t.spots) then f["t.spots"] = Copy(t.spots) end
	for _, k in ipairs(Cards.THEME_KEYS) do f["t." .. k] = Copy(t[k]) end
	for _, k in ipairs(LOOK.theme) do f["t." .. k] = t[k] end
	for _, k in ipairs(LOOK.opt) do f["o." .. k] = Cards.Opt(o, d, k) end
	for _, k in ipairs(RESET_COLOR_KEYS) do f["o." .. k] = Cards.Opt(o, d, k) end
	for _, k in ipairs(GRADIENT_COLOR_KEYS) do f["o." .. k] = Cards.Opt(o, d, k) end
	local areas = o.barTextureAreas
	f["o.shieldTexture"] = type(areas) == "table" and areas.shieldcharges or nil
	local sc = type(o.shieldChargeDisplay) == "table" and o.shieldChargeDisplay or {}
	local dsc = type(d.shieldChargeDisplay) == "table" and d.shieldChargeDisplay or {}
	for _, k in ipairs(LOOK.shield) do f["sc." .. k] = Cards.Opt(sc, dsc, k) end
	local rc, drc = o.rangeCounter, d.rangeCounter
	local re = type(rc) == "table" and rc.useElementColors
	if re == nil and type(drc) == "table" then re = drc.useElementColors end
	f["o.rangeElementColors"] = re
	local rr = rawget(_G, "ShamanPower_ReadyReminders")
	if type(rr) == "table" then
		local rd = Cards.ModuleDefault("ShamanPower_ReadyReminders")
		for _, k in ipairs(Cards.RR) do f["rr." .. k] = Cards.Opt(rr, rd, k) end
	end
	local tr = rawget(_G, "ShamanPowerTremorReminderDB")
	if type(tr) == "table" then f["tr.glowColor"] = Copy(tr.glowColor or Cards.ModuleDefault("ShamanPowerTremorReminderDB").glowColor or Cards.TREMOR_GLOW) end
	Cards.Entries(function(id, e) f["e." .. id .. "." .. e._id] = Copy(SafeGet(e)) end)
	return f
end

-- Standard, worked out: every value at its default
function Cards.StandardFlat()
	local d = Cards.Defaults()
	local f = {}
	for _, k in ipairs(LOOK.opt) do f["o." .. k] = Copy(d[k]) end
	for _, k in ipairs(RESET_COLOR_KEYS) do f["o." .. k] = Copy(d[k]) end
	for _, k in ipairs(GRADIENT_COLOR_KEYS) do f["o." .. k] = Copy(d[k]) end
	local dsc = type(d.shieldChargeDisplay) == "table" and d.shieldChargeDisplay or {}
	for _, k in ipairs(LOOK.shield) do f["sc." .. k] = Copy(dsc[k]) end
	if type(d.rangeCounter) == "table" then f["o.rangeElementColors"] = d.rangeCounter.useElementColors end
	if type(rawget(_G, "ShamanPower_ReadyReminders")) == "table" then
		local rd = Cards.ModuleDefault("ShamanPower_ReadyReminders")
		for _, k in ipairs(Cards.RR) do f["rr." .. k] = Copy(rd[k]) end
	end
	if type(rawget(_G, "ShamanPowerTremorReminderDB")) == "table" then
		f["tr.glowColor"] = Copy(Cards.ModuleDefault("ShamanPowerTremorReminderDB").glowColor or Cards.TREMOR_GLOW)
	end
	Cards.Entries(function(id, e) f["e." .. id .. "." .. e._id] = Cards.DefaultOf(e) end)
	return f
end

function Cards.Diff(a, b)
	local out = {}
	for k, v in pairs(a) do if not Near(v, b[k]) then out[#out + 1] = k end end
	for k, v in pairs(b) do if a[k] == nil and v ~= nil then out[#out + 1] = k end end
	return out
end
function Cards.Same(a, b)
	for k, v in pairs(a) do if not Near(v, b[k]) then return false end end
	for k, v in pairs(b) do if a[k] == nil and v ~= nil then return false end end
	return true
end

-- a flat map onto the profile, whole. pre: the settings to put in BEFORE the theme is
-- resolved (a preset's defaults, which ShamanPower / Minimal then write over)
function Cards.Apply(f, card, baseline, pre)
	local t, o = TW(), SP.opt
	if not (t and type(o) == "table") then return end
	local d = Cards.Defaults()
	local g = f["t.global"]
	t.global = (THEMES[g] and g ~= "standard") and g or nil
	t.spots = type(f["t.spots"]) == "table" and Copy(f["t.spots"]) or nil
	t.palette = PALETTE_KEY[f["t.palette"]] and f["t.palette"] or nil
	t.shield = SHIELD_KEY[f["t.shield"]] and f["t.shield"] or nil
	t.custom = type(f["t.custom"]) == "table" and CleanCustom(f["t.custom"]) or nil
	for _, k in ipairs(LOOK.theme) do
		local v = f["t." .. k]
		if v ~= nil and not (THEME_FIELDS[k] and THEME_FIELDS[k][v]) then v = nil end
		t[k] = v
	end
	t.snapshot, t.written, t.applied, t.saved = nil, nil, nil, nil
	local function put(k)
		local v = f["o." .. k]
		if v == nil then v = d[k] end
		o[k] = Copy(v)
	end
	for _, k in ipairs(LOOK.opt) do put(k) end
	for _, k in ipairs(RESET_COLOR_KEYS) do put(k) end
	for _, k in ipairs(GRADIENT_COLOR_KEYS) do put(k) end
	local tex = f["o.shieldTexture"]
	if tex ~= nil or type(o.barTextureAreas) == "table" then
		o.barTextureAreas = o.barTextureAreas or {}
		o.barTextureAreas.shieldcharges = type(tex) == "string" and tex or nil
	end
	o.shieldChargeDisplay = o.shieldChargeDisplay or {}
	local sc, dsc = o.shieldChargeDisplay, type(d.shieldChargeDisplay) == "table" and d.shieldChargeDisplay or {}
	for _, k in ipairs(LOOK.shield) do
		local v = f["sc." .. k]
		if v == nil then v = dsc[k] end
		sc[k] = Copy(v)
	end
	o.rangeCounter = o.rangeCounter or {}
	local re = f["o.rangeElementColors"]
	if re == nil and type(d.rangeCounter) == "table" then re = d.rangeCounter.useElementColors end
	o.rangeCounter.useElementColors = re
	local rr = rawget(_G, "ShamanPower_ReadyReminders")
	if type(rr) == "table" then for _, k in ipairs(Cards.RR) do rr[k] = Copy(f["rr." .. k]) end end
	local tr = rawget(_G, "ShamanPowerTremorReminderDB")
	if type(tr) == "table" then tr.glowColor = Copy(f["tr.glowColor"] or Cards.ModuleDefault("ShamanPowerTremorReminderDB").glowColor or Cards.TREMOR_GLOW) end
	local function setAll(src)
		Cards.Entries(function(id, e)
			local v = src["e." .. id .. "." .. e._id]
			if v ~= nil and not Near(SafeGet(e), v) then SafeSet(e, Copy(v)) end
		end)
	end
	if pre then setAll(pre) end
	Changed(true)   -- the theme fields resolved; ShamanPower / Minimal write their values
	setAll(f)       -- then the look's own values of the settings a theme writes
	-- everything that reads these colors and looks, drawn again (the rest on the reload
	-- the settings window offers when it closes)
	for _, fn in ipairs({ "ApplyElementColors", "ApplyTotemCooldownTextColor", "RepaintPulseBarColors",
		"UpdateRangeCounters", "RebuildShieldChargeContainer", "UpdateAllReadyReminderAppearance" }) do
		if SP[fn] then
			local ok, err = pcall(SP[fn], SP)
			if not ok then Report(err) end
		end
	end
	LOOK.Repaint()
	Notify()
	t.card, t.forceCustom, t.needBaseline = card, nil, nil
	t.baseline = baseline or Cards.Flat()
end

function Cards.ApplyPreset(key)
	local f = Cards.StandardFlat()
	f["t.global"] = (key ~= "standard") and key or nil
	if key == "standard" then
		Cards.Apply(f, "standard")
		return
	end
	-- ShamanPower / Minimal: every setting from its default, then the theme's values
	local pre = {}
	for k, v in pairs(f) do
		if k:sub(1, 2) == "e." then pre[k] = v; f[k] = nil end
	end
	Cards.Apply(f, key, nil, pre)
end

-- unsaved changes wait on the Custom card
function Cards.Keep()
	local t = TW()
	if not t then return end
	t.pending = { flat = Cards.Flat(), card = t.card, baseline = Copy(t.baseline), at = time() }
	t.saved = nil
end

-- ---- Your Themes (account-wide) ---------------------------------------------------
function Cards.List()
	local g = SP.db and SP.db.global
	if type(g) ~= "table" then return {} end
	if type(g.themes) ~= "table" then g.themes = {} end
	return g.themes
end
function Cards.Find(id)
	for i, th in ipairs(Cards.List()) do
		if th.id == id then return th, i end
	end
end
function Cards.ByName(name)
	local low = strlower(name or "")
	for _, th in ipairs(Cards.List()) do
		if strlower(th.name or "") == low then return th end
	end
end
function Cards.Unique(name)
	if not Cards.ByName(name) then return name end
	for n = 2, 999 do
		local try = name .. " " .. n
		if not Cards.ByName(try) then return try end
	end
	return name
end
function Cards.CleanName(name)
	name = strtrim(tostring(name or "")):gsub("[%c|]", "")
	if #name > 32 then name = name:sub(1, 32) end
	return name
end
-- the preset a look started from
function Cards.BaseOf(card)
	if type(card) == "string" and card:sub(1, 5) == "mine:" then
		local th = Cards.Find(tonumber(card:sub(6)))
		return th and th.base or "standard"
	end
	return THEMES[card] and card or "standard"
end
-- The highest theme number any profile still points at (its card or its unsaved
-- look's): a deleted theme's number may live on in another profile.
function Cards.HighestRef()
	local top = 0
	local profiles = SP.db and SP.db.sv and SP.db.sv.profiles
	if type(profiles) ~= "table" then return top end
	for _, prof in pairs(profiles) do
		local th = type(prof) == "table" and prof.theme
		if type(th) == "table" then
			local pend = type(th.pending) == "table" and th.pending.card
			for _, c in ipairs({ th.card or false, pend or false }) do
				local n = type(c) == "string" and tonumber(c:match("^mine:(%d+)$"))
				if n and n > top then top = n end
			end
		end
	end
	return top
end
-- Theme numbers only go up, never reused: a profile still pointing at a deleted
-- theme (mine:<id>) must not get the next new one in its place.
function Cards.Add(name, base, flat)
	local list = Cards.List()
	local g = SP.db.global
	local id = math.max(tonumber(g.themeNextId) or 1, Cards.HighestRef() + 1)
	for _, th in ipairs(list) do if (tonumber(th.id) or 0) >= id then id = th.id + 1 end end
	g.themeNextId = id + 1
	list[#list + 1] = { id = id, name = name, base = THEMES[base] and base or "standard", flat = Copy(flat),
		created = time(), updated = time() }
	return id
end

-- ---- migration: a player's first load with theme cards ------------------------------
-- A player whose look differs from their theme keeps it: it becomes a theme called
-- "My Look", in use. Nobody's screen changes. After a reset: Standard, worked out.
function Cards.LooksChanged()
	local o, t, d = SP.opt or {}, T() or {}, Cards.Defaults()
	for _, k in ipairs(LOOK.theme) do if t[k] ~= nil then return true end end
	if type(t.custom) == "table" then return true end
	for _, k in ipairs(LOOK.opt) do if not Near(Cards.Opt(o, d, k), d[k]) then return true end end
	for _, k in ipairs(GRADIENT_COLOR_KEYS) do if not Near(Cards.Opt(o, d, k), d[k]) then return true end end
	local areas = o.barTextureAreas
	if type(areas) == "table" and areas.shieldcharges ~= nil then return true end
	local sc, dsc = type(o.shieldChargeDisplay) == "table" and o.shieldChargeDisplay or {}, type(d.shieldChargeDisplay) == "table" and d.shieldChargeDisplay or {}
	for _, k in ipairs(LOOK.shield) do if not Near(Cards.Opt(sc, dsc, k), dsc[k]) then return true end end
	-- the colors no theme writes
	for _, k in ipairs({ "cBuffNeedSome", "cBuffNeedAll", "compactOutlineColor", "compactIdleColor", "pulseFlashColor", "manaTintColor" }) do
		if not Near(Cards.Opt(o, d, k), d[k]) then return true end
	end
	return false
end
function Cards.Migrate()
	if not ready then return end
	local t = TW()
	if not t then return end
	-- a theme deleted while another profile was loaded: this profile keeps its look, as
	-- an unsaved Custom look on the preset that theme started from (as a delete does
	-- for the profile it happens on)
	local gone = SP.db and SP.db.global and SP.db.global.themesGone
	local function lost(card)
		local n = type(card) == "string" and tonumber(card:match("^mine:(%d+)$"))
		if not n or Cards.Find(n) then return nil end
		return (type(gone) == "table" and THEMES[gone[n]] and gone[n]) or "standard"
	end
	local base = lost(t.card)
	if base then t.card, t.forceCustom = base, true end
	if type(t.pending) == "table" then
		base = lost(t.pending.card)
		if base then t.pending.card = base end
	end
	if t.needBaseline then
		t.card, t.baseline, t.needBaseline = "standard", Cards.StandardFlat(), nil
		return
	end
	if t.card and type(t.baseline) == "table" then return end
	local key = (THEMES[t.global] and t.global) or "standard"
	local f = Cards.Flat()
	local changed
	if key == "standard" then
		changed = not Cards.Same(f, Cards.StandardFlat())
	else
		changed = Cards.OldIsCustom() or Cards.LooksChanged()
	end
	if changed then
		local id
		for _, th in ipairs(Cards.List()) do
			if type(th.flat) == "table" and Cards.Same(th.flat, f) then id = th.id break end
		end
		id = id or Cards.Add(Cards.Unique("My Look"), key, f)
		t.card = "mine:" .. id
	else
		t.card = key
	end
	t.baseline = f
end

-- ---- sharing -----------------------------------------------------------------------
-- only what a theme holds, as plain values: a code from someone else never writes
-- anything else
function Cards.Plain(v, depth)
	local tv = type(v)
	if tv == "number" or tv == "boolean" then return v end
	if tv == "string" then return #v <= 64 and v or nil end
	if tv ~= "table" or depth > 4 then return nil end
	local out, n = {}, 0
	for k, x in pairs(v) do
		n = n + 1
		if n > 200 then break end
		if type(k) == "string" or type(k) == "number" then
			local c = Cards.Plain(x, depth + 1)
			if c ~= nil then out[k] = c end
		end
	end
	return out
end
function Cards.Allowed()
	local a = { ["t.global"] = true, ["t.spots"] = true, ["o.shieldTexture"] = true, ["o.rangeElementColors"] = true,
		["tr.glowColor"] = true }
	for _, k in ipairs(Cards.THEME_KEYS) do a["t." .. k] = true end
	for _, k in ipairs(LOOK.theme) do a["t." .. k] = true end
	for _, k in ipairs(LOOK.opt) do a["o." .. k] = true end
	for _, k in ipairs(RESET_COLOR_KEYS) do a["o." .. k] = true end
	for _, k in ipairs(GRADIENT_COLOR_KEYS) do a["o." .. k] = true end
	for _, k in ipairs(LOOK.shield) do a["sc." .. k] = true end
	for _, k in ipairs(Cards.RR) do a["rr." .. k] = true end
	Cards.Entries(function(id, e) a["e." .. id .. "." .. e._id] = true end)
	return a
end
-- each field's shape, checked before a theme is saved or used: a damaged or
-- hand-made code never puts a value in a setting that the setting cannot read.
-- "s" text, "b" on/off, "f" a 0-1 number, "c" a color, "cs" four element colors,
-- "d" a direction per bar; [2] = the choices a text field may hold
function Cards.GoodNumber(v, lo, hi)
	return type(v) == "number" and v == v and v >= (lo or -1e6) and v <= (hi or 1e6)
end
function Cards.GoodColor(v)
	if not IsColor(v) then return false end
	for _, k in ipairs({ "r", "g", "b", "a", "t", 1, 2, 3, 4 }) do
		if v[k] ~= nil and not Cards.GoodNumber(v[k], -0.01, 1.01) then return false end
	end
	if v.r ~= nil then return Cards.GoodNumber(v.g) and Cards.GoodNumber(v.b) end
	return Cards.GoodNumber(v[2])
end
function Cards.GoodColors(v)
	if type(v) ~= "table" then return false end
	for _, x in pairs(v) do if not Cards.GoodColor(x) then return false end end
	return true
end
function Cards.KeysOf(list)
	local s = {}
	for _, x in ipairs(list or {}) do s[x.key] = true end
	return s
end
function Cards.Kinds()
	if Cards.kinds then return Cards.kinds end
	local K = {}
	local s = function(set) return { "s", set } end
	for _, k in ipairs({ "barTexture", "shieldTexture", "elementColorPalette" }) do K["o." .. k] = s() end
	K["o.dotShape"], K["o.glowShape"], K["o.frameEdge"] = s(Cards.KeysOf(SP.DOT_SHAPES)), s(Cards.KeysOf(SP.GLOW_SHAPES)), s(Cards.KeysOf(SP.FRAME_EDGES))
	for _, k in ipairs({ "iconShape", "iconShapeCooldown", "iconShapeReady" }) do K["o." .. k] = s(Cards.KeysOf(SP.ICON_SHAPES)) end
	K["o.compactIdleColor"] = s({ grey = true, element = true })
	K["o.compactOutlineColorMode"] = s({ element = true, custom = true })
	for _, k in ipairs({ "dotGem", "iconShapeSplit", "iconBordersSquare", "durationBarBackground", "shieldChargeColors",
		"cdbarSpellColors", "rangeElementColors" }) do K["o." .. k] = { "b" } end
	for _, k in ipairs({ "cBuffGood", "cBuffNeedSome", "cBuffNeedAll", "compactOutlineColor", "totemCooldownTextColor",
		"pulseBarColor", "pulseFlashColor", "manaTintColor" }) do K["o." .. k] = { "c" } end
	K["o.elementColorsCustom"], K["t.custom"] = { "cs" }, { "cs" }
	for _, field in ipairs({ "barGradient", "outlineGradient", "chargeGradient" }) do
		local dirs = SP.GradientDirectionValues and (SP:GradientDirectionValues(field)) or nil
		K["o." .. field], K["o." .. field .. "Direction"] = s(Cards.KeysOf(SP.GRADIENTS)), s(dirs)
		K["o." .. field .. "Color1"], K["o." .. field .. "Color2"], K["o." .. field .. "Fade"] = { "c" }, { "c" }, { "f" }
		if field == "barGradient" then K["o.barGradientDirections"] = { "d", dirs } end
	end
	for _, k in ipairs({ "lookLS", "lookWS", "lookES", "barLook", "orbLook" }) do K["sc." .. k] = s() end
	for _, k in ipairs({ "chargeColorLS", "chargeColorWS", "chargeColorES" }) do K["sc." .. k] = { "c" } end
	for _, k in ipairs(Cards.RR) do K["rr." .. k] = { "c" } end
	K["tr.glowColor"] = { "c" }
	K["t.global"], K["t.palette"], K["t.shield"] = s(THEMES), s(PALETTE_KEY), s(SHIELD_KEY)
	Cards.kinds = K
	return K
end
function Cards.FitsKind(v, kind)
	local want, set = kind[1], kind[2]
	if want == "s" then return type(v) == "string" and (set == nil or set[v] == true) end
	if want == "b" then return type(v) == "boolean" end
	if want == "f" then return Cards.GoodNumber(v, 0, 1) end
	if want == "c" then return Cards.GoodColor(v) end
	if want == "cs" then return Cards.GoodColors(v) end
	if want == "d" then
		if type(v) ~= "table" then return false end
		for area, x in pairs(v) do
			if type(area) ~= "string" or type(x) ~= "string" or (set and not set[x]) then return false end
		end
		return true
	end
	return false
end
-- a value's shape as a theme setting's own value is compared: its Lua type,
-- "color", or "colors" (a table of colors)
function Cards.Shape(v)
	if v == nil or v == false then return "boolean" end
	if IsColor(v) then return "color" end
	if type(v) ~= "table" then return type(v) end
	return Cards.GoodColors(v) and "colors" or "table"
end
-- a setting a module registered (e.<spot>.<id>): the value must have a shape the
-- setting itself has had (its default, each theme's value, what it is now)
function Cards.FitsEntry(v, id, e)
	local shape = Cards.Shape(v)
	if shape == "table" then return false end
	if shape == "color" and not Cards.GoodColor(v) then return false end
	if shape == "number" and not Cards.GoodNumber(v) then return false end
	local refs = { Cards.DefaultOf(e), SafeGet(e) }
	for i, key in ipairs({ "standard", "shamanpower", "minimal" }) do
		local x = e[key]
		if type(x) == "function" then
			local ok, res = pcall(x, id, key)
			if ok then x = res else x = nil end
		end
		refs[2 + i] = x
	end
	local any = false
	for i = 1, 5 do
		local x = refs[i]
		if x ~= nil then
			any = true
			-- "off, or a color" (Pulse Bar Color): off reads as false
			if Cards.Shape(x) == shape or (x == false and shape == "color") then return true end
		end
	end
	return not any   -- nothing to compare with: any plain value or color
end
-- a per-spot override: the fields a spot can hold, each a value it accepts
function Cards.CleanSpot(id, x)
	local spot = SPOTS[id]
	if not spot then return nil, 0 end   -- a part of a module this player has off: left out, as its settings are
	if type(x) ~= "table" then return nil, 1 end
	local out, bad = {}, 0
	for field, v in pairs(x) do
		local ok
		if field == "theme" then ok = THEMES[v] == true
		elseif field == "choice" then ok = spot.choiceByKey ~= nil and spot.choiceByKey[v] ~= nil
		elseif field == "colors" and type(v) == "table" then
			local colors = {}
			for rk, c in pairs(v) do
				if type(rk) == "string" and Cards.GoodColor(c) then colors[rk] = c else bad = bad + 1 end
			end
			v = colors
			if next(colors) then ok = true else ok = "none" end   -- (each bad color already counted)
		elseif THEME_FIELDS[field] then ok = THEME_FIELDS[field][v] == true
		end
		if ok == true then out[field] = v elseif not ok then bad = bad + 1 end
	end
	return next(out) and out or nil, bad
end
-- a theme's fields, kept only where each holds a value its setting can read.
-- Returns the clean fields and how many were left out.
function Cards.Clean(f)
	local a, K, out, bad = Cards.Allowed(), Cards.Kinds(), {}, 0
	local entries = {}
	Cards.Entries(function(id, e) entries["e." .. id .. "." .. e._id] = { id, e } end)
	for k, v in pairs(type(f) == "table" and f or {}) do
		if a[k] then
			local c = Cards.Plain(v, 1)
			local ok = c ~= nil
			if ok then
				local field = type(k) == "string" and k:sub(3)
				if k == "t.spots" then
					ok = type(c) == "table"
					if ok then
						local spots = {}
						for id, x in pairs(c) do
							local s, n = Cards.CleanSpot(id, x)
							spots[id], bad = s, bad + n
						end
						c = next(spots) and spots or nil
						ok = c ~= nil
					end
				elseif K[k] then ok = Cards.FitsKind(c, K[k])
				elseif k:sub(1, 2) == "t." and THEME_FIELDS[field] then ok = THEME_FIELDS[field][c] == true
				elseif entries[k] then ok = Cards.FitsEntry(c, entries[k][1], entries[k][2])
				else ok = type(c) ~= "table"
				end
				if not ok and k ~= "t.spots" then bad = bad + 1 end
			else
				bad = bad + 1
			end
			if ok then out[k] = c end
		end
	end
	return out, bad
end
function Cards.Encode(th)
	local LS = LibStub and LibStub("LibSerialize", true)
	local LD = LibStub and LibStub("LibDeflate", true)
	if not (LS and LD) then return nil end
	local ok, ser = pcall(LS.Serialize, LS, { v = 1, name = th.name, base = th.base, flat = th.flat })
	if not ok or not ser then return nil end
	local z = LD:CompressDeflate(ser, { level = 9 })
	return z and (Cards.PREFIX .. LD:EncodeForPrint(z)) or nil
end
function Cards.Decode(text)
	local LS = LibStub and LibStub("LibSerialize", true)
	local LD = LibStub and LibStub("LibDeflate", true)
	if not (LS and LD) then return nil, "the serialization libraries are missing" end
	text = strtrim(tostring(text or ""))
	local at = text:find(Cards.PREFIX, 1, true)
	if not at then return nil, "that is not a ShamanPower theme code (it starts with SPT1:)" end
	local body = text:sub(at + #Cards.PREFIX):match("^[%w%(%)]+")
	local raw = body and LD:DecodeForPrint(body)
	local ser = raw and LD:DecompressDeflate(raw)
	if not ser then return nil, "the code is damaged or cut off" end
	local ok, p = LS:Deserialize(ser)
	if not ok or type(p) ~= "table" or p.v ~= 1 or type(p.flat) ~= "table" then return nil, "the code is damaged or from a newer ShamanPower" end
	return p
end

-- ---- the public side (General > Themes) --------------------------------------------
function SP:ThemeIsCustom()
	local t = T()
	if not t then return false end
	if t.forceCustom then return true end
	if type(t.baseline) == "table" then return not Cards.Same(Cards.Flat(), t.baseline) end
	return Cards.OldIsCustom()
end
-- the card picked (nil before the cards exist for this profile)
function SP:ThemeCard()
	local t = T()
	local c = t and t.card
	if c == nil then return (t and THEMES[t.global] and t.global) or "standard" end
	return c
end
function SP:ThemeCardBase(card) return Cards.BaseOf(card or SP:ThemeCard()) end
function SP:ThemeMine() return Cards.List() end
function SP:ThemeMineById(id) return (Cards.Find(id)) end
function SP:ThemeHasSavedCustom()
	local t = T()
	return t ~= nil and (type(t.pending) == "table" or type(t.saved) == "table")
end
-- what the Custom card draws: the live look when it is in use, else the one waiting
function SP:ThemeCustomLook()
	local t = T()
	if SP:ThemeIsCustom() or not t then return SP:ThemeGlobal(), t and PALETTE_KEY[t.palette] and t.palette or nil end
	local p = t.pending
	if type(p) == "table" and type(p.flat) == "table" then
		local g = p.flat["t.global"]
		return (THEMES[g] and g) or "standard", PALETTE_KEY[p.flat["t.palette"]] and p.flat["t.palette"] or nil
	end
	local sv = t.saved
	if type(sv) == "table" then
		return (THEMES[sv.base] and sv.base) or "standard", PALETTE_KEY[sv.palette] and sv.palette or nil
	end
	return SP:ThemeGlobal(), nil
end
-- the card the Custom look started from, and the list of what changed (labels, first few)
Cards.LABEL = {
	["t.global"] = "Theme", ["t.spots"] = "Part Colors", ["t.palette"] = "Element Colors", ["t.shield"] = "Shield Colors",
	["t.custom"] = "Custom Element Colors", ["t.classColors"] = "Class Colors", ["t.showAs"] = "Show Icons As",
	["t.borders"] = "Element-Colored Borders", ["t.bordersFlyouts"] = "Element-Colored Borders",
	["t.bordersCooldown"] = "Element-Colored Borders", ["t.bordersCooldownFlyouts"] = "Element-Colored Borders",
	["t.borderSize"] = "Border Size", ["t.borderSizeFlyouts"] = "Border Size", ["t.borderSizeCooldown"] = "Border Size",
	["t.borderSizeCooldownFlyouts"] = "Border Size",
	["o.barTexture"] = "Bar Texture", ["o.dotShape"] = "Dot Shape", ["o.dotGem"] = "Gem Dot Finish", ["o.glowShape"] = "Glow Shape",
	["o.frameEdge"] = "Frame Edge", ["o.iconShape"] = "Icon Shape", ["o.iconShapeCooldown"] = "Icon Shape (Cooldown Bar)",
	["o.iconShapeReady"] = "Icon Shape (Ready Reminders)", ["o.iconBordersSquare"] = "Keep Borders Square",
	["o.durationBarBackground"] = "Duration Bar Background", ["o.shieldTexture"] = "Shield Charges Texture",
	["o.rangeElementColors"] = "Range Counter Colors", ["o.elementColorPalette"] = "Element Colors",
	["o.elementColorsCustom"] = "Custom Element Colors", ["o.cBuffGood"] = "Status Colors", ["o.cBuffNeedSome"] = "Status Colors",
	["o.cBuffNeedAll"] = "Status Colors", ["o.totemCooldownTextColor"] = "Cooldown Text Color", ["o.pulseBarColor"] = "Pulse Bar Color",
	["o.pulseFlashColor"] = "Pulse Flash Color", ["o.manaTintColor"] = "Mana Tint Color", ["o.shieldChargeColors"] = "Color Shield Charges by Count",
	["o.cdbarSpellColors"] = "Spell-Colored Progress Bars", ["sc.lookLS"] = "Lightning Shield Look", ["sc.lookWS"] = "Water Shield Look",
	["sc.lookES"] = "Earth Shield Look", ["sc.barLook"] = "Shield Charges Look", ["sc.orbLook"] = "Shield Charges Look",
	["sc.chargeColorLS"] = "Lightning Shield Charge Color", ["sc.chargeColorWS"] = "Water Shield Charge Color",
	["sc.chargeColorES"] = "Earth Shield Charge Color", ["tr.glowColor"] = "Tremor Reminder Glow",
}
function Cards.Label(k)
	if Cards.LABEL[k] then return Cards.LABEL[k] end
	local p = k:match("^o%.(%a+)Gradient") or k:match("^o%.(%a+)Gradient.+")
	if p == "bar" then return "Bar Gradient" elseif p == "outline" then return "Outline Gradient" elseif p == "charge" then return "Charge Bar Gradient" end
	if k:match("^o%.compact") then return "Compact Colors" end
	if k:match("^rr%.") then return "Ready Reminders Colors" end
	local id, eid = k:match("^e%.([^.]+%.?[^.]*)%.(.+)$")
	local reg = id and settingSpots[id]
	if reg then
		for _, e in ipairs(reg.entries) do if e._id == eid and e.label then return e.label end end
	end
	return nil
end
function SP:ThemeChanges()
	local t = T()
	if not t then return {}, "standard" end
	local a, b, card
	if SP:ThemeIsCustom() and type(t.baseline) == "table" then
		a, b, card = Cards.Flat(), t.baseline, t.card
	elseif type(t.pending) == "table" and type(t.pending.flat) == "table" and type(t.pending.baseline) == "table" then
		a, b, card = t.pending.flat, t.pending.baseline, t.pending.card
	else
		return {}, SP:ThemeCard()
	end
	local seen, out = {}, {}
	for _, k in ipairs(Cards.Diff(a, b)) do
		local l = Cards.Label(k)
		if l and not seen[l] then seen[l] = true; out[#out + 1] = l end
	end
	table.sort(out)
	return out, card
end
-- the Custom card belongs to one of Your Themes: that theme, changed
function SP:ThemeCustomOf()
	local t = T()
	if not t then return nil end
	local card = (SP:ThemeIsCustom() and t.card) or (type(t.pending) == "table" and t.pending.card) or nil
	if type(card) == "string" and card:sub(1, 5) == "mine:" then return Cards.Find(tonumber(card:sub(6))) end
	return nil
end

-- /sp themecheck (the developer's tripwire, account-wide switch): every change on
-- General > Themes must change what a theme holds; one that does not is a look not
-- hooked into Cards.Flat (presets, Your Themes and share codes would miss it)
function SP:ThemeCheckOn()
	local g = SP.db and SP.db.global
	return type(g) == "table" and g.themeCheck == true
end
function SP:ThemeCheckSnapshot()
	if SP:ThemeCheckOn() then Cards.lastFlat = Cards.Flat() end
end
function SP:ThemeCheckChange()
	if not SP:ThemeCheckOn() then return end
	local f = Cards.Flat()
	if Cards.lastFlat and Cards.Same(f, Cards.lastFlat) then
		print("|cffff8040ShamanPower theme check|r: that change on General > Themes is NOT part of a theme:"
			.. " presets, Your Themes and share codes would not carry it. Hook it into Cards.Flat"
			.. " (LOOK / RESET_COLOR_KEYS lists or ThemeSpotSettings).")
	end
	Cards.lastFlat = f
end

-- a preset card
function SP:SetThemeGlobal(key)
	if not THEMES[key] or not ready then return end
	local t = TW()
	if not t then return end
	local custom = SP:ThemeIsCustom()
	if not custom and SP:ThemeCard() == key then return end   -- in use already: nothing to do (and no reload prompt)
	if custom then Cards.Keep() end
	Cards.ApplyPreset(key)
end
-- one of Your Themes
function SP:ThemePickMine(id)
	local th = Cards.Find(id)
	if not (th and ready) then return end
	local custom = SP:ThemeIsCustom()
	if not custom and SP:ThemeCard() == "mine:" .. id then return end
	if custom then Cards.Keep() end
	Cards.Apply(Cards.Clean(th.flat), "mine:" .. id)
end
-- the Custom card: the look waiting on it comes back (a 3.0.4 Custom look too)
function SP:ThemeLoadCustom()
	local t = T()
	if not (t and ready) or SP:ThemeIsCustom() then return end
	local p = t.pending
	if type(p) == "table" and type(p.flat) == "table" then
		t.pending = nil
		Cards.Apply(p.flat, p.card or "standard", type(p.baseline) == "table" and p.baseline or nil)
		if type(p.baseline) ~= "table" then t.forceCustom = true end
		return
	end
	if type(t.saved) == "table" then
		Cards.LegacyLoad()
		t.forceCustom = true   -- compared with its card, it is Custom until saved or discarded
	end
end
-- Discard: in use, the card goes back to how it was saved (Undo); waiting on the
-- Custom card, the changes go
function SP:ThemeDiscard()
	local t = T()
	if not t then return end
	if SP:ThemeIsCustom() then
		SP:ThemeUndo()
		return
	end
	t.pending, t.saved = nil, nil
end
-- Undo Changes: the card in use, exactly as it is saved
function SP:ThemeUndo()
	local t = T()
	if not (t and ready) then return end
	local card = SP:ThemeCard()
	if type(card) == "string" and card:sub(1, 5) == "mine:" then
		local th = Cards.Find(tonumber(card:sub(6)))
		if th then Cards.Apply(Cards.Clean(th.flat), card) return end
		card = "standard"
	end
	Cards.ApplyPreset(THEMES[card] and card or "standard")
end
-- Save as Theme / Save as New: the Custom look (in use, else the one waiting) under a
-- name. A name already used is replaced (the page asked first). Returns the id.
function SP:ThemeSaveAs(name)
	local t = TW()
	name = Cards.CleanName(name)
	if not t or name == "" then return nil end
	local inUse = SP:ThemeIsCustom() or not (type(t.pending) == "table")
	local flat, card
	if inUse then flat, card = Cards.Flat(), t.card
	else flat, card = Copy(t.pending.flat), t.pending.card end
	local base = Cards.BaseOf(card)
	local old = Cards.ByName(name)
	local id
	if old then
		old.flat, old.base, old.updated = Copy(flat), base, time()
		id = old.id
	else
		id = Cards.Add(name, base, flat)
	end
	if inUse then
		t.card, t.baseline, t.forceCustom = "mine:" .. id, Cards.Flat(), nil
	else
		t.pending = nil
	end
	return id
end
-- Update <theme>: the theme the Custom look belongs to takes the changes
function SP:ThemeUpdate()
	local t = T()
	local th = SP:ThemeCustomOf()
	if not (t and th) then return end
	local inUse = SP:ThemeIsCustom()
	th.flat = inUse and Cards.Flat() or Copy(t.pending.flat)
	th.updated = time()
	if inUse then t.baseline, t.forceCustom = Cards.Flat(), nil else t.pending = nil end
end
function SP:ThemeRename(id, name)
	local th = Cards.Find(id)
	name = Cards.CleanName(name)
	if not th or name == "" then return false end
	local other = Cards.ByName(name)
	if other and other ~= th then return false end
	th.name = name
	return true
end
function SP:ThemeDelete(id)
	local th, i = Cards.Find(id)
	if not th then return end
	table.remove(Cards.List(), i)
	-- its preset, for the profiles still pointing at it (Cards.Migrate)
	local g = SP.db and SP.db.global
	if g then
		if type(g.themesGone) ~= "table" then g.themesGone = {} end
		g.themesGone[id] = th.base or "standard"
	end
	local t = T()
	if not t then return end
	local key = "mine:" .. id
	-- the look in use stays on screen, now as an unsaved Custom look on its preset
	if t.card == key then t.card, t.forceCustom = th.base or "standard", true end
	if type(t.pending) == "table" and t.pending.card == key then t.pending.card = th.base or "standard" end
end
function SP:ThemeShareCode(id)
	local th = Cards.Find(id)
	return th and Cards.Encode(th) or nil
end
-- a code from Share: added to Your Themes (not picked). Returns the theme, or nil and why.
function SP:ThemeImport(text)
	local p, err = Cards.Decode(text)
	if not p then return nil, err end
	local flat, skipped = Cards.Clean(p.flat)
	if not next(flat) then return nil, "there is nothing in that code this ShamanPower can use" end
	local name = Cards.CleanName(p.name)
	if name == "" then name = "Shared Theme" end
	local id = Cards.Add(Cards.Unique(name), p.base, flat)
	return Cards.Find(id), nil, skipped
end

-- profile change (and anyone who needs a full re-resolve): reconcile every
-- registered spot with the profile's theme, repaint; a profile without a card gets one
function SP:ApplyTheme()
	if not ready then return end
	local was = anyActive
	local wrote = ApplyAll(false)
	if wrote or was or anyActive then Notify() end
	if loggedIn then Cards.Migrate() end
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
	if wrote or changed or anyActive then Notify() end	-- the theme cards: every module has registered its settings by now
	if C_Timer and C_Timer.After then C_Timer.After(0, Cards.Migrate) else Cards.Migrate() end
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
