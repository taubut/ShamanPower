-- ShamanPower_Config :: CdbarIcons
-- The Cooldown Bar's settings page (A13, 2026-10-07): its Items row and every item's
-- right-click menu, on the shared icon row (IconRow.lua). The row shows every item
-- this game has, in the bar's order (the shield as Lightning | Water, the weapon imbue
-- as Flametongue | Frostbrand | Windfury). Click: on or off the bar. Right-click: the
-- item's settings, grouped (Show and its seconds on the first level; Look, Charges,
-- Effects, Clicks, Flyout, Keybind; only the groups that item has). Drag: its place on
-- the bar (the bar's own order, opt.cooldownBarOrder). The rest of the page (Bar,
-- Progress Bars and Time, Effects, Position) is ShamanPowerOptions.lua's.
--
-- Every value goes through Data.Get / Data.Set by the item's setting names (runOutOnly,
-- sweep, cueGone ...: ShamanPowerCdItems.lua): SP:CdItemOpt reads the item's own value,
-- else today's shared one; SP:SetCdItemOpt saves it as the item's own (the bar follows).
-- A value of the item's own is drawn in blue in the menu, and the item gets the blue corner.
local _, ns = ...
local Core = ns.Core
local SP = ShamanPower
if not (Core and SP and ns.IconRow) then return end

local Menu = ns.IconRow.Menu
local Choice, OnOff, Slider, Group = Menu.Choice, Menu.OnOff, Menu.Slider, Menu.Group
local SEP = { separator = true }

-- 3.0.9: a row's `pic` / `words` are picture hints for the icon's own screen (IconScreen.lua); the
-- menus ignore them. The colors are plain numbers, the ones the bar draws with: the cues' gold, blue
-- and Running Out orange and WoW's red (ShamanPowerCues.lua), the progress bar's green and the charge
-- strip's blue (ShamanPower.lua); a picture never reads a widget.
local PIC = {
	plain = { kind = "plain" }, none = { kind = "none" }, redx = { kind = "redx" },
	GOLD = { 1, 0.82, 0.25 }, BLUE = { 0.35, 0.65, 1 }, ORANGE = { 1, 0.6, 0.1 }, RED = { 1, 0.125, 0.125 },
	GREEN = { 0.2, 0.8, 0.2 }, STRIP = { 0.2, 0.6, 1 },
	-- the Dot pops in the logo's blue (ShamanPowerThemeEffects.lua)
	LOGO = (SP.THEME_BRAND and SP.THEME_BRAND.logoBlue) or { 63 / 255, 169 / 255, 245 / 255 },
}
-- what an effect's styles draw, in that effect's color: Flash washes the icon, Glow glows, Shine / Shield
-- burst / Element flare ring it, Frame drains / Frame blink edge it, Bar under it bars it, Pulse darkens
-- it, Dot / Corner flag sit in its corner, Turns red is WoW's red. Shake and Pop are motion: no picture
local function EffectPics(color)
	local tex = "Interface\\AddOns\\ShamanPower\\textures\\"
	return {
		off = PIC.plain, shake = PIC.none, pop = PIC.none,
		flash = { kind = "tint", color = color },
		glow = { kind = "glow", color = color },
		shine = { kind = "glow", shape = "round", color = color },
		burst = { kind = "glow", shape = "round", color = color },
		flare = { kind = "glow", shape = "round", color = color },
		drain = { kind = "edge", color = color },
		blinkflag = { kind = "edge", color = color },
		underbar = { kind = "bar", frac = 0.4, color = color },
		pulse = { kind = "dark" },
		dot = { kind = "corner", icon = tex .. "dot", color = PIC.LOGO },
		flag = { kind = "corner", icon = tex .. "cue_flag", color = color },
		red = { kind = "tint", color = PIC.RED },
	}
end
PIC.ready, PIC.gone, PIC.running = EffectPics(PIC.GOLD), EffectPics(PIC.BLUE), EffectPics(PIC.ORANGE)

-- (the words that say what to do in the settings' blue, so a player sees them first)
local CAPTION = "|cff3FA9F5CLICK|r an item to show or hide it on the bar. |cff3FA9F5RIGHT-CLICK|r it for its settings."
	.. " |cff3FA9F5DRAG|r it to move it. |cff3FA9F5Dark|r: not learned yet."

-- ---------------------------------------------------------------------------
-- The items
-- ---------------------------------------------------------------------------
local SHIELD, RECALL, ANKH, IMBUE = 1, 2, 3, 7
-- each item's on / off (Cooldown Bar's options, ShamanPowerOptions.lua)
local SHOW_OPTION = {
	[1] = "cdbar_show_shields", [2] = "cdbar_show_recall", [3] = "cdbar_show_reincarnation", [4] = "cdbar_show_ns",
	[5] = "cdbar_show_manatide", [6] = "cdbar_show_bloodlust", [7] = "cdbar_show_imbues", [8] = "cdbar_show_shamanistic_rage",
	[9] = "cdbar_show_elemental_mastery", [10] = "cdbar_show_rage_of_the_farseer", [11] = "cdbar_show_totemic_projection",
}
-- the keys an item can have (Bindings.xml): its button, and the shield's and imbue's flyout
local BINDINGS = {
	[1] = { "SHAMANPOWER_CD_SHIELD", "SHAMANPOWER_FLYOUT_SHIELD" }, [2] = { "SHAMANPOWER_CD_RECALL" },
	[3] = { "SHAMANPOWER_CD_ANKH" }, [4] = { "SHAMANPOWER_CD_NS" }, [5] = { "SHAMANPOWER_CD_MANATIDE" },
	[6] = { "SHAMANPOWER_CD_BLOODLUST" }, [7] = { "SHAMANPOWER_CD_IMBUE", "SHAMANPOWER_FLYOUT_IMBUE" },
	[8] = { "SHAMANPOWER_CD_SHAMANISTIC_RAGE" }, [9] = { "SHAMANPOWER_CD_ELEMENTAL_MASTERY" },
	[10] = { "SHAMANPOWER_CD_RAGE_OF_THE_FARSEER" }, [11] = { "SHAMANPOWER_CD_TOTEMIC_PROJECTION" },
}

local function Option(group, key)
	local f = SP.options and SP.options.args and SP.options.args.fluffy and SP.options.args.fluffy.args
	local g = f and f[group]
	return g and g.args and g.args[key]
end
local function OptGet(group, key)
	local o = Option(group, key)
	if not (o and o.get) then return nil end
	return o.get({})
end
local function OptSet(group, key, v)
	local o = Option(group, key)
	if o and o.set then o.set({}, v) end
end

local function SpellTexture(id)
	if not id then return nil end
	if C_Spell and C_Spell.GetSpellTexture then
		local t = C_Spell.GetSpellTexture(id)
		if t then return t end
	end
	if GetSpellTexture then
		local t = GetSpellTexture(id)
		if t then return t end
	end
	return (select(3, GetSpellInfo(id)))
end

-- the spells of a cooldown item on this client (TrackedCooldowns' 5th field)
local function SpellsOf(t)
	local out = {}
	for _, e in ipairs(SP.TrackedCooldowns or {}) do
		if e[5] == t then out[#out + 1] = e[1] end
	end
	return out
end

local NAMES, ICONS, SPELLS = {}, {}, {}
local function Setup()
	if NAMES[1] then return end
	local label = SPCompat and SPCompat.SpellLabel or function(_, fb) return fb end
	local water = (SP.ShieldSpells and SP.ShieldSpells[2] and SP.ShieldSpells[2][1]) or 24398
	NAMES[1] = "Lightning / Water Shield"
	ICONS[1] = { SpellTexture(324), SpellTexture(water) }
	-- the weapon imbue: Flametongue | Frostbrand | Windfury (ShamanPowerValues.lua WeaponIcons)
	local wi = SP.WeaponIcons or {}
	NAMES[7] = "Weapon Imbue"
	ICONS[7] = { wi[2], wi[3], wi[1] }
	-- Bloodlust (Horde) or Heroism (Alliance): the one the bar shows for your side
	local faction = UnitFactionGroup and UnitFactionGroup("player")
	NAMES[6] = label(2825, "Bloodlust") .. " / " .. label(32182, "Heroism")
	SPELLS[6] = (faction == "Alliance") and 32182 or 2825
	ICONS[6] = { SpellTexture(SPELLS[6]) }
	for t = 2, 11 do
		if t ~= 6 and t ~= 7 then
			local ids = SpellsOf(t)
			SPELLS[t] = ids[1]
			NAMES[t] = (SP.CooldownTypeLabels and SP.CooldownTypeLabels[t]) or ("Item " .. t)
			ICONS[t] = { SpellTexture(ids[1]) or 134400 }
		end
	end
	if GetSpellInfo(36936) then NAMES[2] = GetSpellInfo(36936) end   -- "Totemic Recall" on some clients
end

local function Known(id) return id and SPCompat and SPCompat.KnowsSpellID and SPCompat.KnowsSpellID(id) or false end

local function Learned(t)
	if t == SHIELD then
		for _, s in ipairs(SP.ShieldSpells or {}) do if Known(s[1]) then return true end end
		return false
	end
	if t == IMBUE then return SP.DefaultImbueIndex and SP:DefaultImbueIndex() ~= nil or false end
	for _, id in ipairs(SpellsOf(t)) do if Known(id) then return true end end
	return false
end

local function ShownOnBar(t)
	local key = SHOW_OPTION[t]
	if not key then return false end
	local v = OptGet("cdbar_items_section", key)
	return v ~= false
end

-- ---------------------------------------------------------------------------
-- The item values: each item's own (SP:CdItemOpt / SetCdItemOpt, ShamanPowerCdItems.lua);
-- with a core that has no per-item settings yet (an update not restarted), the shared
-- settings through their own options, as the page was before
-- ---------------------------------------------------------------------------
local Data = {}
local function PerItem() return type(SP.CdItemOpt) == "function" and type(SP.SetCdItemOpt) == "function" end
ns.CdbarData = Data
local D, E, I = "cooldown_display_section", "cdbar_effects_section", "cdbar_items_section"
local GONE = { [SHIELD] = { "cdbarCueShield", "cdbarCueShieldStyle", "cdbarCueShieldMark" },
	[IMBUE] = { "cdbarCueImbue", "cdbarCueImbueStyle", "cdbarCueImbueMark" } }
local SHARED = {
	runOutOnly      = { D, "cdbarRunOutOnly" },
	runOutReady     = { D, "cdbarRunOutReady" },
	runOutSecs      = { D, "cdbarRunOutSecs" },
	almostSecs      = { D, "cdbarAlmostSecs" },
	sweepDirection  = { D, "cdbar_sweep_direction" },
	progressBar     = { D, "cdbar_show_progress_bars" },
	progressColor   = { D, "cdbar_spell_colors" },
	timeOnIcon      = { D, "cdbar_show_cd_text" },
	ankhCount       = { D, "show_ankh_count" },
	chargeCount     = { D, "shield_charge_count" },
	colorCount      = { D, "shield_charge_colors" },
	chargeBar       = { D, "shield_charge_bar" },
	cueReady        = { E, "cdbarCueReady" },
	cueReadyStyle   = { E, "cdbarCueReadyStyle" },
	cueAlmost       = { E, "cdbarCueAlmost" },
	cueAlmostStyle  = { E, "cdbarCueAlmostStyle" },
	cueMissing      = { E, "cdbarCueMissing" },
	cueMissingGlow  = { E, "cdbarCueMissingGlow" },
	cueMarkStays    = { E, "cdbarCueMarkStays" },
	cueRunning      = { E, "cdbarCueRunning" },
	cueRunningStyle = { E, "cdbarCueRunningStyle" },
	cueTimeColor    = { E, "cdbarCueTimeColor" },
	cueTimeOnly     = { E, "cdbarCueTimeOnly" },
	flyoutDirection = { I, "cdbar_flyout_direction" },
	flyoutIconSize  = { I, "cooldownFlyoutButtonSize" },
	flyoutOpacity   = { I, "cooldownFlyoutOpacity" },
	rightClickOther = { I, "cdbar_shield_right_click_other" },
	onTotemBar      = { I, "cdbar_recall_on_totembar" },
}

-- value, own (own: the item's own value, drawn in blue)
function Data.Get(t, name)
	if PerItem() then
		local own = SP.CdItemOwnOpt and SP:CdItemOwnOpt(t, name)
		return SP:CdItemOpt(t, name), own ~= nil
	end
	if name == "buttonStyle" then
		if not OptGet(D, "cdbar_own_style") then return "mirror", false end
		return OptGet(D, "cdbar_style") or "normal", false
	elseif name == "sweep" then
		if OptGet(D, "cdbar_show_color_sweep") == false then return "none", false end
		return OptGet(D, "cdbar_sweep_style") or "greys", false
	elseif name == "cueGone" or name == "cueGoneStyle" or name == "cueMark" then
		local g = GONE[t]
		if not g then return nil, false end
		local i = (name == "cueGone" and 1) or (name == "cueGoneStyle" and 2) or 3
		return OptGet(E, g[i]), false
	end
	local s = SHARED[name]
	if not s then return nil, false end
	return OptGet(s[1], s[2]), false
end

function Data.Set(t, name, v)
	if PerItem() then
		SP:SetCdItemOpt(t, name, v)
		return
	end
	if name == "buttonStyle" then
		if v == "mirror" then
			OptSet(D, "cdbar_own_style", false)
		else
			OptSet(D, "cdbar_style", v)
			OptSet(D, "cdbar_own_style", true)
		end
		return
	elseif name == "sweep" then
		if v == "none" then
			OptSet(D, "cdbar_show_color_sweep", false)
		else
			OptSet(D, "cdbar_sweep_style", v)
			OptSet(D, "cdbar_show_color_sweep", true)
		end
		return
	elseif name == "cueGone" or name == "cueGoneStyle" or name == "cueMark" then
		local g = GONE[t]
		if not g then return end
		local i = (name == "cueGone" and 1) or (name == "cueGoneStyle" and 2) or 3
		OptSet(E, g[i], v)
		return
	end
	local s = SHARED[name]
	if s then OptSet(s[1], s[2], v) end
end

-- ---------------------------------------------------------------------------
-- The menu
-- ---------------------------------------------------------------------------
local Row   -- (below)
-- the row whose menu is open: this page's, or Totem Bar > Bar's Buttons row while Totemic Recall sits on
-- the totem bar (TotemBarIcons.lua shows it there, with this same menu)
local function MenuRow() return ns.CdbarMenuRow or Row end
local function Get(t, name) return Data.Get(t, name) end
-- a choice: saved, the menu stays open and is drawn again
local function Set(t, name, v)
	Data.Set(t, name, v)
	MenuRow():Changed(true)
	return true
end
-- a slider's value: only saved, the icons and the preview follow; never a redraw of the
-- page under a drag
local function SliderSet(t, name, v)
	Data.Set(t, name, v)
	MenuRow():Repaint()
	local cfg = _G.ShamanPowerConfig
	if cfg and cfg.PreviewChanged then cfg:PreviewChanged() end
end

-- pic: the row's picture hint (an On / Off row's ON picture; a choice's fallback)
local function OnOffName(t, text, name, tip, pic)
	return OnOff(text, function() return Get(t, name) end, function(v) return Set(t, name, v) end, tip, pic)
end
local function ChoiceName(t, text, name, list, tip, fallback, pic)
	return Choice(text, list, function()
		local v, own = Get(t, name)
		if v == nil then v = fallback end
		return v, own
	end, function(v) return Set(t, name, v) end, tip, pic)
end
local function Secs(v) return string.format("%d sec", tonumber(v) or 0) end
local function IsShieldOrImbue(t) return t == SHIELD or t == IMBUE end

-- an effect's switch and style as one row: Off, or the style it plays (Q7); pics: each style's picture
-- Signature Moves (the page's Effects): every effect plays the Effects Look's own move
local function SignatureOn()
	local o = SP.opt
	return (o and o.cdbarCueSignature and (o.cdbarCueLook or "standard") ~= "standard") and true or false
end

local function EffectRow(t, text, onName, styleName, list, fallback, tip, pics)
	local function cur()
		local on, own1 = Get(t, onName)
		local st, own2 = Get(t, styleName)
		if not on then return "off", own1 end
		return st or fallback, own1 or own2
	end
	return {
		text = text, tip = tip,
		value = function()
			local v, own = cur()
			return Menu.LabelOf(list, v), own and true or false
		end,
		sub = function()
			local now = cur()
			-- Signature Moves on: the move it plays (Off still turns it off)
			local sig = SignatureOn() and (Get(t, styleName) or fallback) or nil
			local items = {}
			for _, c in ipairs(list) do
				local v = c[1]
				items[#items + 1] = { text = c[2], selected = now == v, pic = pics and pics[v],
					disabled = (sig and v ~= "off" and v ~= sig) or nil, onClick = function()
					if v == "off" then
						Data.Set(t, onName, false)
					elseif SignatureOn() then
						Data.Set(t, onName, true)   -- (Signature Moves plays its move: the item's own style stays for after)
					else
						Data.Set(t, styleName, v)
						Data.Set(t, onName, true)
					end
					MenuRow():Changed(true)
					return true
				end }
			end
			return items
		end,
	}
end

local STYLE_CHOICES = { { "mirror", "Same As The Totem Bar" }, { "normal", "Normal" }, { "totemtimers", "TotemTimers Style" },
	{ "single", "Single Totem" }, { "dynamic", "Dynamic (PvP)" }, { "grid", "Grid (every choice)" } }
-- (the sweeps' pictures: Clock Sweep as it is, Grays Out as the gray; Fills Back In has no picture of its own)
local SWEEP_CHOICES = { { "none", "None", nil, PIC.plain }, { "greys", "Gray Fills In", nil, { kind = "gray" } },
	{ "fills", "Color Fills In", nil, PIC.none },
	{ "radial", "Clock Sweep", nil, { kind = "sweep", frac = 0.6, text = "6m" } } }
local SWEEP_CHOICES_IMBUE = { SWEEP_CHOICES[1], SWEEP_CHOICES[2], SWEEP_CHOICES[3] }
local DIRECTION_CHOICES = { { "top", "From The Top" }, { "bottom", "From The Bottom" } }
local BARCOLOR_CHOICES = { { false, "By Time Left" }, { true, "Spell Color" } }
local FLYDIR_CHOICES = { { "below", "Below" }, { "auto", "Auto" }, { "above", "Above" } }
local READY_STYLES = { { "off", "Off" }, { "shake", "Shake" }, { "pop", "Pop" }, { "flash", "Flash" }, { "glow", "Glow" },
	{ "shine", "Shine" }, { "dot", "Dot" } }
local ALMOST_STYLES = { { "off", "Off" }, { "pulse", "Pulse" }, { "glow", "Glow" }, { "drain", "Shrinking Border" },
	{ "underbar", "Bar Below Icon" } }
local RUNNING_STYLES = { { "off", "Off" }, { "red", "Turns red" }, { "pulse", "Pulse" }, { "glow", "Glow" },
	{ "drain", "Shrinking Border" }, { "underbar", "Bar Below Icon" } }
local GONE_STYLES = {
	[SHIELD] = { { "off", "Off" }, { "shake", "Shake" }, { "pop", "Pop" }, { "flash", "Flash" }, { "glow", "Glow" },
		{ "burst", "Shield burst" }, { "blinkflag", "Blinking Border and Corner Mark" } },
	[IMBUE] = { { "off", "Off" }, { "shake", "Shake" }, { "pop", "Pop" }, { "flash", "Flash" }, { "glow", "Glow" },
		{ "flare", "Element Flash" }, { "flag", "Corner Mark" } },
}

-- a choice list with its pictures (value -> pic), for the lists whose pictures are the item's own
local function WithPics(list, pics)
	local out = {}
	for i, c in ipairs(list) do out[i] = { c[1], c[2], c[3], pics[c[1]] } end
	return out
end
-- the progress bar's color with plenty of time left: the spell's own (Spell Color: ShamanPower.lua's
-- SpellBarColors / ImbueBarColors; the shield's Lightning, the imbue's Flametongue) or green (By Time Left)
local function SpellColor(t)
	local c
	if t == SHIELD then c = SP.SpellBarColors and SP.SpellBarColors[324]
	elseif t == IMBUE then c = SP.ImbueBarColors and SP.ImbueBarColors[2]
	else c = SP.SpellBarColors and SPELLS[t] and SP.SpellBarColors[SPELLS[t]] end
	return c or PIC.GREEN
end

-- ---------------------------------------------------------------------------
-- Copy, Paste, Copy To, and each group's own copy line (the item's values, or "follow the
-- bar" where it has none: SP:CopyCdItem copies only what both items have)
-- ---------------------------------------------------------------------------
local function HasAPI(fn) return type(SP[fn]) == "function" end
-- the shield's and the imbue's Gone styles differ in their last two: a copy between them takes
-- the other one's own (Shield burst <-> Element flare, Frame blink + flag <-> Corner flag)
local GONE_TWIN = { [SHIELD] = { flare = "burst", flag = "blinkflag" }, [IMBUE] = { burst = "flare", blinkflag = "flag" } }
local function FixGoneStyles()
	if not HasAPI("CdItemOwnOpt") then return end
	for t, map in pairs(GONE_TWIN) do
		local v = SP:CdItemOwnOpt(t, "cueGoneStyle")
		if v and map[v] then SP:SetCdItemOpt(t, "cueGoneStyle", map[v]) end
	end
end
local function Copy(from, to, group)
	if not HasAPI("CopyCdItem") then return end
	SP:CopyCdItem(from, to, group)
	FixGoneStyles()
end
local function CopyGroup(t, to, group)
	Copy(t, to, group)
	MenuRow():Changed(true)
	return true
end
-- Cooldown Ready, Cooldown Almost Ready and the time's gold onto every other cooldown this game
-- has (never the shield or the imbue: theirs are other effects)
local function CopyEffectsToCooldowns(t)
	if not (HasAPI("CdItemNames") and HasAPI("CdItemApplies") and HasAPI("CdItemOwnOpt")) then return true end
	local names = SP:CdItemNames("effects") or {}
	for _, x in ipairs(SP:GetCooldownBarOrder()) do
		if x ~= t and x ~= SHIELD and x ~= IMBUE then
			for _, name in ipairs(names) do
				if SP:CdItemApplies(t, name) and SP:CdItemApplies(x, name) then
					local v = SP:CdItemOwnOpt(t, name)
					if SP:CdItemOwnOpt(x, name) ~= v then SP:SetCdItemOpt(x, name, v) end
				end
			end
		end
	end
	MenuRow():Changed(true)
	return true
end
local function CopyLine(text, fn) return { text = text, onClick = fn } end

local function AppearanceRows(t)
	local r = {}
	if IsShieldOrImbue(t) then
		-- (TotemTimers Style: the other shield / imbue in the corner; Single Totem: in place of the icon; Dynamic
		-- draws as Single; Same As The Totem Bar and Grid have no picture of their own)
		local other = ICONS[t] and ICONS[t][2]
		local pics = { mirror = PIC.none, normal = PIC.plain, totemtimers = { kind = "corner", icon = other },
			single = { kind = "swap", icon = other }, dynamic = PIC.none, grid = PIC.none }
		r[#r + 1] = ChoiceName(t, "Button Style", "buttonStyle", WithPics(STYLE_CHOICES, pics),
			"How the button picks what it shows. Same As The Totem Bar: the way your Totem Bar Style works (General > Main).\n\n"
			.. "Normal: the one you assigned, lit only while it is up. TotemTimers Style: the one that is up, with your assigned"
			.. " one in its corner. Single Totem: the one that is up, without the corner. Dynamic (PvP): the one that is up, and"
			.. " casting another one makes it your assigned one. Grid: every choice laid out beside it (no flyout).", "mirror")
	end
	-- (the imbue draws a Clock Sweep as Vertical - Grays Out: one copied from another item reads that way)
	r[#r + 1] = Choice("Sweep", t == IMBUE and SWEEP_CHOICES_IMBUE or SWEEP_CHOICES, function()
		local v, own = Get(t, "sweep")
		if v == nil or (t == IMBUE and v == "radial") then v = "greys" end
		return v, own
	end, function(v) return Set(t, "sweep", v) end,
		"Grays Out: the icon starts in color and gray covers it as time runs out. Fills Back In: the icon starts gray and"
		.. " its color comes back." .. (t == IMBUE and "" or " Clock Sweep: the classic clock sweep.") .. " None: no sweep.")
	local sweep = Get(t, "sweep")
	if t == IMBUE and sweep == "radial" then sweep = "greys" end
	if sweep == "greys" or sweep == "fills" then
		r[#r + 1] = ChoiceName(t, "Sweep Direction", "sweepDirection", DIRECTION_CHOICES,
			"Where the gray (Grays Out) or the color (Fills Back In) starts.", "top", PIC.none)
	end
	r[#r + 1] = OnOffName(t, "Progress Bar", "progressBar", "A colored bar beside the button that runs down with the time left."
		.. " Where it sits and how big it is: Progress Bars and Time on this page.",
			{ kind = "bar", color = function()   -- (follows Progress Bar Color)
				local c = PIC.GREEN
				if Get(t, "progressColor") then c = SpellColor(t) end
				return c[1], c[2], c[3]
			end })
	if SP.opt and SP.opt.cdbarShowProgressBars == false then
		r[#r + 1] = { text = "Show Progress Bars is off on the Cooldown Bar page: no item shows one.", disabled = true }
	end
	if Get(t, "progressBar") ~= false then
		r[#r + 1] = Choice("Progress Bar Color", WithPics(BARCOLOR_CHOICES, { [false] = { kind = "bar", color = PIC.GREEN },
			[true] = { kind = "bar", color = SpellColor(t) } }), function()
			local v, own = Get(t, "progressColor")
			return v and true or false, own
		end, function(v) return Set(t, "progressColor", v) end,
			"By Time Left: green, then yellow, then red. Spell Color: the spell's own color while there is plenty of time"
			.. " (with less than 10 minutes left it still turns yellow, then red).")
	end
	if t ~= SHIELD then
		local where = OptGet(D, "cdbar_duration_text") or "none"
		if where == "none" then
			r[#r + 1] = OnOffName(t, "Show Time Left", "timeOnIcon", "The time left, in the middle of the icon.",
				{ kind = "word", text = "45" })
		end
	end
	if t == ANKH then
		r[#r + 1] = OnOffName(t, "Ankh Count", "ankhCount", "How many Ankhs are in your bags, on the icon.",
			{ kind = "number", text = "5" })
	end
	r[#r + 1] = SEP
	r[#r + 1] = CopyLine("Copy Appearance To All Items", function() return CopyGroup(t, "all", "look") end)
	return r
end

local function ChargeRows(t)
	local r = { OnOffName(t, "Charge Count", "chargeCount", "The charges left, in the button's corner.",
		{ kind = "number", text = "3" }) }
	if Get(t, "chargeCount") ~= false then
		-- (no picture says a colored count: the count is the row above's)
		r[#r + 1] = OnOffName(t, "Color by Charges Left", "colorCount", "Green when full, yellow at half, red when low. Off: white.",
			PIC.none)
	end
	r[#r + 1] = OnOffName(t, "Charge Bar", "chargeBar",
		"A bar along the bottom of the button, one piece per charge.", { kind = "bar", frac = 1, color = PIC.STRIP })
	return r
end

local FOREVER = SPCompat and SPCompat.FOREVER
-- this item's effects on the bar (the page's Test button plays every item's)
local function TestItem(t)
	if SP.TestCdItemCues then SP:TestCdItemCues(t) elseif SP.TestCooldownCues then SP:TestCooldownCues() end
	return true
end
local function EffectRows(t)
	local r = {}
	if SignatureOn() then
		r[#r + 1] = { text = "Signature Moves is on under Effects.", disabled = true }
		r[#r + 1] = { text = "Effects use the selected look's animations.", disabled = true }
		r[#r + 1] = SEP
	end
	if IsShieldOrImbue(t) then
		local shield = t == SHIELD
		r[#r + 1] = EffectRow(t, shield and "Shield Gone" or "Weapon Imbue Gone", "cueGone", "cueGoneStyle", GONE_STYLES[t], "shake",
			shield and ("When your shield is gone, the button plays this in blue."
				.. (FOREVER and " In a fight it pulses red while no shield is up (at 100% Cooldown Bar opacity)." or ""))
			or "When the imbue drops off (it ran out, or you swapped weapons), the button plays this in blue.", PIC.gone)
		-- its own switch (3.0.9.1): works with the Gone animation off too; off clears an X on the button
		r[#r + 1] = OnOffName(t, "Red X When It's Gone", "cueMark",
			shield and ("A red X on the button until you cast a shield again (5 seconds at most). Its own switch: with Shield Gone off,"
				.. " the X alone." .. (FOREVER and " In a fight it shows while no shield is up instead (at 100% Cooldown Bar opacity)." or ""))
			or "A red X on the button until you put an imbue on again (5 seconds at most). Its own switch: with Weapon Imbue Gone off,"
				.. " the X alone.", PIC.redx)
		if Get(t, "cueMark") then
			r[#r + 1] = OnOffName(t, "Keep the Red X Until You Recast", "cueMarkStays",
				"The X stays on the button until you cast again, instead of fading after 5 seconds. Off: an X held now fades.", PIC.redx)
		end
		r[#r + 1] = OnOffName(t, "Turns Red While Missing", "cueMissing",
			shield and "While your shield is gone, the button turns red until you cast it again."
			or "While a weapon imbue is gone, the button turns red until you imbue again (with two weapons: either hand).",
			{ kind = "tint", color = PIC.RED })
		r[#r + 1] = OnOffName(t, "Glow While Missing", "cueMissingGlow",
			(shield and "While your shield is gone, the button's edges glow red until you cast it again."
			or "While a weapon imbue is gone, the button's edges glow red until you imbue again (with two weapons: either hand).")
			.. " With Proc Glow as your Glow Shape, that plays round the button too.", { kind = "glow", color = PIC.RED })
		r[#r + 1] = EffectRow(t, "Running Out", "cueRunning", "cueRunningStyle", RUNNING_STYLES, "red",
			"Over its last moments (Running Out At), the button plays this until you cast it again."
			.. (shield and " A shield also counts as running out on its last charge." or ""), PIC.running)
		r[#r + 1] = OnOffName(t, "Time Turns Red While Running Out", "cueTimeColor",
			"The time on the button turns red while it is running out. On a button that turns red, the time stays white so you can read it.",
			PIC.none)   -- (no picture says a red time: the time is the sweep's)
		if shield then
			r[#r + 1] = OnOffName(t, "Show Time Only When Running Out", "cueTimeOnly",
				"The shield's time stays out of sight while there is plenty left, and shows the moment it is running out (Running Out At)."
				.. (FOREVER and " In a fight the game draws it, so it is exact to the second." or ""),
				{ kind = "word", text = "45" })   -- (the time alone: the sweep is its own setting)
		end
		r[#r + 1] = SEP
		if shield then
			r[#r + 1] = CopyLine("Copy Effects To Weapon Imbue", function() return CopyGroup(t, IMBUE, "effects") end)
		else
			r[#r + 1] = CopyLine("Copy Effects To Shield", function() return CopyGroup(t, SHIELD, "effects") end)
		end
	else
		r[#r + 1] = EffectRow(t, "Cooldown Ready", "cueReady", "cueReadyStyle", READY_STYLES, "pop",
			"When the cooldown is ready again, the button plays this in gold.", PIC.ready)
		r[#r + 1] = EffectRow(t, "Cooldown Almost Ready", "cueAlmost", "cueAlmostStyle", ALMOST_STYLES, "glow",
			"Over the cooldown's last seconds (Almost Ready At), the button plays this in gold.", PIC.ready)
		r[#r + 1] = OnOffName(t, "Time Turns Gold When Almost Ready", "cueTimeColor",
			"The time on the button turns gold over its last seconds (Almost Ready At).", PIC.none)   -- (as Time Turns Red)
		r[#r + 1] = SEP
		r[#r + 1] = CopyLine("Copy Effects To All Cooldowns", function() return CopyEffectsToCooldowns(t) end)
	end
	return r
end

local function ClickRows(t)
	local swapped = SP.ClicksSwapped and SP:ClicksSwapped()
	local click = swapped and "Left-click" or "Right-click"
	local desc = click .. " the shield button to cast your other shield: Water Shield while the button is on Lightning"
		.. " Shield, Lightning Shield while it's on Water Shield. That shield then stays on the button, so your next"
		.. " click or key casts it again. Works in fights. If the cast doesn't go off (for example during the global"
		.. " cooldown), the button still switches to the other shield. (The totem bar's clicks are on Totem Bar > Clicks.)"
	if swapped then
		desc = desc .. "\n\nSwap Left and Right Click is on, so this is the left-click. The right-click and your key cast the shield on the button."
	end
	if SP.FlyoutOpensOnRightClick and SP:FlyoutOpensOnRightClick() then
		desc = desc .. "\n\n\"Flyout Requires Right-Click\" is on and takes the right-click first, so this does nothing right now."
	end
	if SP.KnownShieldCount and SP:KnownShieldCount() < 2 then
		desc = desc .. "\n\nYou know only one of the two shields right now, so there is nothing to switch to yet."
	end
	return { OnOffName(t, (swapped and "Left" or "Right") .. "-Click Casts Your Other Shield", "rightClickOther", desc,
		PIC.none) }
end

local function FlyoutRows(t)
	local r = {}
	local layout = SP.opt and (SP.opt.cdbarLayout or SP.opt.layout)
	if layout == "Horizontal" then
		r[#r + 1] = ChoiceName(t, "Direction", "flyoutDirection", FLYDIR_CHOICES,
			"Where the flyout opens while the bar is horizontal.", "auto", PIC.none)
	end
	r[#r + 1] = Slider("Icon Size", 12, 56, 1, function() return Get(t, "flyoutIconSize") or 22 end,
		function(v) SliderSet(t, "flyoutIconSize", v) end, nil, false,
		"How big the icons in the flyout are. 22 is the classic size. The Cooldown Bar's scale still applies on top.")
	r[#r + 1] = Slider("Opacity", 0.1, 1, 0.05, function() return Get(t, "flyoutOpacity") or 1 end,
		function(v) SliderSet(t, "flyoutVisibility", v) end, nil, true, "How see-through the flyout is.")
	r[#r + 1] = SEP
	if t == SHIELD then
		r[#r + 1] = CopyLine("Copy Flyout Settings To Weapon Imbue", function() return CopyGroup(t, IMBUE, "flyout") end)
	else
		r[#r + 1] = CopyLine("Copy Flyout Settings To Shield", function() return CopyGroup(t, SHIELD, "flyout") end)
	end
	return r
end

local function KeyText(binding)
	local key = binding and GetBindingKey and GetBindingKey(binding)
	if not key then return "Not Set" end
	return (GetBindingText and GetBindingText(key, "KEY_")) or key
end
local function KeybindRows(t)
	local b = BINDINGS[t]
	local r = { { text = "Button Key", value = function() return KeyText(b[1]), false end } }
	if b[2] then r[#r + 1] = { text = "Flyout Key", value = function() return KeyText(b[2]), false end } end
	r[#r + 1] = SEP
	r[#r + 1] = { text = "Open Keybind Mode...", tip = "Opens Keybind Mode: press the key you want on the button, or on its flyout.", onClick = function()
		if SP.SetKeybindMode then SP:SetKeybindMode(true) end
	end }
	return r
end

local function MenuItems(item)
	local t = item.key
	local r = {}
	-- the icon itself
	local on = ShownOnBar(t)
	r[#r + 1] = { text = "Show", label = true }
	r[#r + 1] = { text = on and "Hide This Icon" or "Show This Icon", onClick = function()
		OptSet(I, SHOW_OPTION[t], not on)
		MenuRow():Changed(false)
	end }
	-- when it shows
	if IsShieldOrImbue(t) then
		r[#r + 1] = Choice("Show", { { "always", "Always", nil, { kind = "sweep", frac = 0.8, text = "8m" } },
			{ "runout", "Only When Running Out", nil, { kind = "sweep", frac = 0.15, text = "45" } } }, function()
			local v, own = Get(t, "runOutOnly")
			return v and "runout" or "always", own
		end, function(v) return Set(t, "runOutOnly", v == "runout") end,
			"Only When Running Out: out of sight until it is running out, then up with its time left. Gone: up until you cast"
			.. " it again. It keeps its place on the bar."
			.. ((FOREVER and t == SHIELD) and " On WoW: Forever your shield stays on the bar during a fight: the game doesn't tell addons when it runs out there." or ""))
		r[#r].words = "when the button is on the bar"
		r[#r + 1] = Slider("Running Out (Seconds Left)", 10, 300, 5, function() return Get(t, "runOutSecs") or 60 end,
			function(v) SliderSet(t, "runOutSecs", v) end, Secs, false,
			"When it counts as running out, for Show and for the Running Out effect."
			.. (t == SHIELD and " A shield also counts as running out on its last charge." or ""))
		r[#r].words = "the seconds that count as running out"
	else
		r[#r + 1] = Choice("Show", { { "always", "Always", nil, { kind = "sweep", frac = 0.7, text = "2m" } },
			{ "hide", "When Almost Ready, Then Hide Once Ready", nil, { kind = "sweep", frac = 0.1, text = "3" } },
			{ "keep", "When Almost Ready, Keep Until Used", nil, PIC.plain } }, function()
			local on, own1 = Get(t, "runOutOnly")
			if not on then return "always", own1 end
			local ready, own2 = Get(t, "runOutReady")
			return (ready == "keep") and "keep" or "hide", own1 or own2
		end, function(v)
			if v == "always" then
				Data.Set(t, "runOutOnly", false)
			else
				Data.Set(t, "runOutReady", v)
				Data.Set(t, "runOutOnly", true)
			end
			MenuRow():Changed(true)
			return true
		end, "Out of sight until its last seconds (Almost Ready At). Then Hide Again: gone again once it is ready."
			.. " Until Used: up until you use it.")
		r[#r].words = "when the button is on the bar"
		r[#r + 1] = Slider("Almost Ready (Seconds Left)", 0, 30, 1, function()
			local s = Get(t, "almostSecs")
			if s == nil then s = 5 end
			return s
		end, function(v) SliderSet(t, "almostSecs", v) end, Secs, false,
			"When it counts as almost ready, for Show and for the Cooldown Almost Ready effect. At 0 seconds the Cooldown"
			.. " Almost Ready effect never plays.")
		r[#r].words = "the seconds that count as almost ready"
	end
	r[#r + 1] = SEP
	-- how it looks
	r[#r + 1] = { text = "Appearance", label = true }
	r[#r + 1] = Group("Appearance", function() return AppearanceRows(t) end, nil, nil,
		IsShieldOrImbue(t) and "button style, sweep and progress bar" or "sweep and progress bar")
	if t == SHIELD then
		r[#r + 1] = Group("Charges", function() return ChargeRows(t) end, nil, nil, "the count and the bar for its charges")
	end
	if IsShieldOrImbue(t) then
		r[#r + 1] = Group("Flyout", function() return FlyoutRows(t) end, nil, nil,
			"where the flyout opens, its size and opacity")
	end
	r[#r + 1] = SEP
	-- what it plays at its moments
	r[#r + 1] = Group("Effects", function() return EffectRows(t) end, nil, nil,
		IsShieldOrImbue(t) and "what the button plays when it is gone or running out"
		or "what the button plays when it is ready or almost ready")
	r[#r + 1] = SEP
	-- where it sits (Totemic Recall: which bar; the rest sit on the cooldown bar), its clicks and keys
	local pk = {}
	if t == RECALL then
		pk[#pk + 1] = Choice("Bar", { { false, "Cooldown Bar" }, { true, "Totem Bar" } }, function()
			local v, own = Get(t, "onTotemBar")
			return v and true or false, own
		end, function(v)
			local was = SP.RecallOnTotemBarPage and SP:RecallOnTotemBarPage()
			Data.Set(t, "onTotemBar", v)
			local now = SP.RecallOnTotemBarPage and SP:RecallOnTotemBarPage()
			if was == now then
				MenuRow():Changed(true)
				return true
			end
			-- its icon moves to the other bar's page (Totem Bar > Bar, or here): that page, with this menu open
			C_Timer.After(0, function()
				if now and SP.TotemBarOpenItemMenu then SP:TotemBarOpenItemMenu("button", "recall")
				elseif SP.CooldownBarOpenItemMenu then SP:CooldownBarOpenItemMenu(t) end
			end)
		end, "Totem Bar: the button sits at the end of your totem bar instead, and its icon and these settings move to"
			.. " Totem Bar > Bar.", PIC.none)
		pk[#pk].words = "which bar the button sits on"
	end
	if t == SHIELD then
		pk[#pk + 1] = Group("Clicks", function() return ClickRows(t) end, nil, nil, "what a click on the button casts")
	end
	if BINDINGS[t] then
		pk[#pk + 1] = Group("Keys", function() return KeybindRows(t) end, nil, nil,
			BINDINGS[t][2] and "the keys for the button and its flyout" or "the key for the button")
	end
	if #pk > 0 then
		if #pk > 1 then r[#r + 1] = { text = "Position & Keys", label = true } end
		for _, x in ipairs(pk) do r[#r + 1] = x end
		r[#r + 1] = SEP
	end
	-- copy and reset
	r[#r + 1] = { text = "Copy & Reset", label = true }
	r[#r + 1] = { text = "Copy Settings", disabled = not HasAPI("CdItemSnapshot"), onClick = function()
		Row.clip = { from = t, name = NAMES[t] or ("Item " .. t), snap = SP:CdItemSnapshot(t) }
		return true
	end }
	local clip = Row.clip
	r[#r + 1] = { text = clip and ("Paste Settings  (from " .. clip.name .. ")") or "Paste Settings",
		disabled = not clip or clip.from == t,
		onClick = function()
			if Row.clip and HasAPI("PasteCdItem") then
				SP:PasteCdItem(Row.clip.snap, t)
				FixGoneStyles()
			end
			MenuRow():Changed(true)
			return true
		end }
	r[#r + 1] = { text = "Copy Settings To...", subMaxHeight = 420, disabled = not HasAPI("CopyCdItem"),
		words = "this item's settings onto another item, or all of them", sub = function()
		local o = {}
		for _, x in ipairs(SP:GetCooldownBarOrder()) do
			if x ~= t then
				o[#o + 1] = { text = NAMES[x] or ("Item " .. x), icon = ICONS[x] and ICONS[x][1],
					onClick = function() Copy(t, x); MenuRow():Changed(false) end }
			end
		end
		o[#o + 1] = SEP
		o[#o + 1] = { text = "All Items", onClick = function() Copy(t, "all"); MenuRow():Changed(false) end }
		return o
	end }
	r[#r + 1] = { text = "Reset This Button", disabled = not (SP.CdItemHasOwn and SP:CdItemHasOwn(t)),
		tip = "Clear this icon's changes and use the bar's settings again.",
		onClick = function()
			if SP.ResetCdItem then SP:ResetCdItem(t) end
			MenuRow():Changed(false)
		end }
	r[#r + 1] = SEP
	-- its test
	r[#r + 1] = { text = "Test This Button's Effects", onClick = function() return TestItem(t) end }
	return r
end

-- ---------------------------------------------------------------------------
-- Order: the item to its new place (the bar's saved order; the items this game
-- doesn't have keep their saved places after the rest, as the old Order tab's swap did)
-- ---------------------------------------------------------------------------
local function MoveItem(item, index)
	if InCombatLockdown() or not SP.GetCooldownBarOrder then return end
	local order = SP:GetCooldownBarOrder()
	-- (Totemic Recall on the totem bar is not in this row: the row's places are counted without it,
	-- and it keeps its own place in the saved order)
	local recallAt
	if SP.RecallOnTotemBarPage and SP:RecallOnTotemBarPage() then
		for i, x in ipairs(order) do if x == RECALL then recallAt = i break end end
		if recallAt then table.remove(order, recallAt) end
	end
	local from
	for i, x in ipairs(order) do if x == item.key then from = i break end end
	if not from then return end
	table.remove(order, from)
	table.insert(order, math.max(1, math.min(#order + 1, index)), item.key)
	if recallAt then table.insert(order, math.min(recallAt, #order + 1), RECALL) end
	local seen = {}
	for _, x in ipairs(order) do seen[x] = true end
	for _, x in ipairs(SP.opt.cooldownBarOrder or {}) do
		if not seen[x] then order[#order + 1] = x; seen[x] = true end
	end
	SP.opt.cooldownBarOrder = order
	SP:RecreateCooldownBar()   -- waits for the end of combat by itself
end

-- ---------------------------------------------------------------------------
-- The row
-- ---------------------------------------------------------------------------
Row = ns.IconRow.New({
	caption = CAPTION,
	hint = "Click: show or hide it\nRight-click: its settings\nDrag: move it",
	list = function(out)
		Setup()
		local away = SP.RecallOnTotemBarPage and SP:RecallOnTotemBarPage()   -- (Totemic Recall: on Totem Bar > Bar)
		for _, t in ipairs(SP.GetCooldownBarOrder and SP:GetCooldownBarOrder() or {}) do
			if not (away and t == RECALL) then out[#out + 1] = { key = t, name = NAMES[t] or ("Item " .. t) } end
		end
	end,
	textures = function(item, out)
		Setup()
		local ic = ICONS[item.key] or {}
		local n = 0
		for i = 1, 3 do
			out[i] = ic[i]
			if ic[i] then n = i end
		end
		return n
	end,
	shown = function(item) return ShownOnBar(item.key) end,
	learned = function(item) return Learned(item.key) end,
	hasOwn = function(item) return SP.CdItemHasOwn and SP:CdItemHasOwn(item.key) or false end,
	toggle = function(item)
		local key = SHOW_OPTION[item.key]
		if key then OptSet(I, key, not ShownOnBar(item.key)) end
	end,
	menu = function(item)
		ns.CdbarMenuRow = nil   -- (this page's menu: this row redraws)
		return MenuItems(item)
	end,
	move = MoveItem,
	locked = function() return InCombatLockdown() end,
	onLocked = function()
		print("|cff0070ddShamanPower|r: |cffe64a4aThe Cooldown Bar's settings can't change in combat - try again after the fight.|r")
	end,
})
ns.CustomRows.cdbarIcons = Row
ns.CdbarRow = Row
SP.CooldownBarRow = Row   -- (the test round and the renderer reach the row here)

-- Totemic Recall on the totem bar: Totem Bar > Bar's Buttons row shows its icon with these (row: that row,
-- which the menu then redraws)
ns.CdbarRecall = {
	name = function() Setup() return NAMES[RECALL] or "Totemic Recall" end,
	icon = function() Setup() return ICONS[RECALL] and ICONS[RECALL][1] end,
	shown = function() return ShownOnBar(RECALL) end,
	learned = function() return Learned(RECALL) end,
	hasOwn = function() return SP.CdItemHasOwn and SP:CdItemHasOwn(RECALL) or false end,
	toggle = function() OptSet(I, SHOW_OPTION[RECALL], not ShownOnBar(RECALL)) end,
	menu = function(row, item)
		ns.CdbarMenuRow = row
		return MenuItems({ key = RECALL, name = item and item.name })
	end,
}

-- SP:CooldownBarOpenItemMenu(type, path): the settings window on the Cooldown Bar page with
-- that item's menu open once the row is drawn
function SP.CooldownBarOpenItemMenu(_, t, path)
	local cfg = _G.ShamanPowerConfig
	if not (cfg and cfg.Open) then return end
	Row:QueueMenu(t, path)
	cfg:Open({ "fluffy", "cdbar_page" })
end

-- ---------------------------------------------------------------------------
-- Reset This Page (Window.lua calls it after the page's own rows): every item's own values,
-- the settings the items' menus show for an item with none of its own, each item's on / off
-- and the bar's order, back to how they came. Left alone, as on every page: where the bar sits
-- and what a theme holds (each item's own looks, Sweep Direction, Spell-Colored Progress Bars,
-- Color Shield Charges by Count). Earth Shield (TBC Anniversary) shares the Running Out settings today but is not on
-- this page: it keeps the values it has (as its own).
-- ---------------------------------------------------------------------------
local RESET_SHARED = { "cdbarRunOutOnly", "cdbarRunOutReady", "cdbarRunOutSecs", "cdbarAlmostSecs", "cdbarOwnStyle",
	"cdbarStyle", "cdbarShowColorSweep", "cdbarSweepStyle", "cdbarShowProgressBars", "cdbarShowCDText", "showAnkhCount",
	"cdbarShowShieldCount", "cdbarShieldChargeBar", "cdbarCueReady", "cdbarCueReadyStyle", "cdbarCueAlmost",
	"cdbarCueAlmostStyle", "cdbarCueShield", "cdbarCueShieldStyle", "cdbarCueShieldMark", "cdbarCueImbue",
	"cdbarCueImbueStyle", "cdbarCueImbueMark", "cdbarCueMarkStays", "cdbarCueMissing", "cdbarCueMissingGlow", "cdbarCueRunning", "cdbarCueRunningStyle",
	"cdbarCueTimeColor", "cdbarCueTimeOnly", "cdbarFlyoutDirection", "cooldownFlyoutButtonSize", "cooldownFlyoutOpacity",
	"cdbarShieldRightClickOther", "totemicCallOnTotemBar", "cooldownBarOrder" }
local RESET_SHOWN = { "cdbarShowShields", "cdbarShowRecall", "cdbarShowReincarnation", "cdbarShowNS", "cdbarShowManaTide",
	"cdbarShowBloodlust", "cdbarShowImbues", "cdbarShowShamanisticRage", "cdbarShowElementalMastery",
	"cdbarShowRageOfTheFarseer", "cdbarShowTotemicProjection" }
local EARTH_SHIELD, EARTH_NAMES = 12, { "runOutSecs", "cueRunning", "cueRunningStyle" }
function SP.CooldownBarResetPage(sp)
	if InCombatLockdown() or not sp.opt then return end
	local o = sp.opt
	-- Earth Shield keeps what it has
	if sp.CdItemOwnOpt and sp.SetCdItemOpt and sp.CdItemOpt then
		for _, name in ipairs(EARTH_NAMES) do
			if sp:CdItemOwnOpt(EARTH_SHIELD, name) == nil then sp:SetCdItemOpt(EARTH_SHIELD, name, sp:CdItemOpt(EARTH_SHIELD, name)) end
		end
	end
	-- each item's own looks a theme holds (Appearance > Themes) stay: the theme stays as it is
	local looks = sp.CdItemThemeLooks or {}
	if sp.CdItemHasOwn and sp.ResetCdItem then
		for t = 1, 11 do
			if sp:CdItemHasOwn(t) then
				local keep
				for _, look in ipairs(looks) do
					local v = sp:CdItemOwnOpt(t, look[1])
					if v ~= nil then keep = keep or {}; keep[look[1]] = v end
				end
				sp:ResetCdItem(t)
				for name, v in pairs(keep or {}) do sp:SetCdItemOpt(t, name, v) end
			end
		end
	end
	for _, k in ipairs(RESET_SHARED) do o[k] = nil end
	for _, k in ipairs(RESET_SHOWN) do o[k] = nil end   -- (every item on the bar)
	sp:RecreateCooldownBar()
	for _, fn in ipairs({ "UpdateMiniTotemBar", "ApplyShieldButtonClicks", "ApplyCooldownFlyoutButtonSize",
		"UpdateCooldownFlyoutOpacity", "ApplyCueSettings" }) do
		if sp[fn] then
			local ok, err = pcall(sp[fn], sp)
			if not ok then geterrorhandler()(err) end
		end
	end
end
