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
-- Every value goes through Data.Get / Data.Set by the item's setting names
-- (CONTRACT-cdbar-items: runOutOnly, sweep, cueGone ...).
local _, ns = ...
local Core = ns.Core
local SP = ShamanPower
if not (Core and SP and ns.IconRow) then return end

local Menu = ns.IconRow.Menu
local Choice, OnOff, Slider, Group = Menu.Choice, Menu.OnOff, Menu.Slider, Menu.Group
local SEP = { separator = true }

-- (the words that say what to do in the settings' blue, so a player sees them first)
local CAPTION = "|cff3FA9F5Click|r an item to show or hide it on the bar. |cff3FA9F5Right-click|r it for its settings."
	.. " |cff3FA9F5Drag|r it to move it. |cff3FA9F5Dark|r: not learned yet."

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
-- The item values (stage 1: the shared settings, through their own options)
-- ---------------------------------------------------------------------------
local Data = {}
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
	cueRunning      = { E, "cdbarCueRunning" },
	cueRunningStyle = { E, "cdbarCueRunningStyle" },
	cueTimeColor    = { E, "cdbarCueTimeColor" },
	flyoutDirection = { I, "cdbar_flyout_direction" },
	flyoutIconSize  = { I, "cooldownFlyoutButtonSize" },
	flyoutOpacity   = { I, "cooldownFlyoutOpacity" },
	rightClickOther = { I, "cdbar_shield_right_click_other" },
	onTotemBar      = { I, "cdbar_recall_on_totembar" },
}

-- value, own (own: the item's own value, drawn in blue; stage 1 has none)
function Data.Get(t, name)
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
local function Get(t, name) return Data.Get(t, name) end
-- a choice: saved, the menu stays open and is drawn again
local function Set(t, name, v)
	Data.Set(t, name, v)
	Row:Changed(true)
	return true
end
-- a slider's value: only saved, the icons and the preview follow; never a redraw of the
-- page under a drag
local function SliderSet(t, name, v)
	Data.Set(t, name, v)
	Row:Repaint()
	local cfg = _G.ShamanPowerConfig
	if cfg and cfg.PreviewChanged then cfg:PreviewChanged() end
end

local function OnOffName(t, text, name, tip)
	return OnOff(text, function() return Get(t, name) end, function(v) return Set(t, name, v) end, tip)
end
local function ChoiceName(t, text, name, list, tip, fallback)
	return Choice(text, list, function()
		local v, own = Get(t, name)
		if v == nil then v = fallback end
		return v, own
	end, function(v) return Set(t, name, v) end, tip)
end
local function Secs(v) return string.format("%d sec", tonumber(v) or 0) end
local function IsShieldOrImbue(t) return t == SHIELD or t == IMBUE end

-- an effect's switch and style as one row: Off, or the style it plays (Q7)
local function EffectRow(t, text, onName, styleName, list, fallback, tip)
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
			local items = {}
			for _, c in ipairs(list) do
				local v = c[1]
				items[#items + 1] = { text = c[2], selected = now == v, onClick = function()
					if v == "off" then
						Data.Set(t, onName, false)
					else
						Data.Set(t, styleName, v)
						Data.Set(t, onName, true)
					end
					Row:Changed(true)
					return true
				end }
			end
			return items
		end,
	}
end

local STYLE_CHOICES = { { "mirror", "Same As The Totem Bar" }, { "normal", "Normal" }, { "totemtimers", "TotemTimers Style" },
	{ "single", "Single Totem" }, { "dynamic", "Dynamic (PvP)" }, { "grid", "Grid (every choice)" } }
local SWEEP_CHOICES = { { "none", "None" }, { "greys", "Vertical - Grays Out" }, { "fills", "Vertical - Fills Back In" },
	{ "radial", "Radial Swipe" } }
local SWEEP_CHOICES_IMBUE = { SWEEP_CHOICES[1], SWEEP_CHOICES[2], SWEEP_CHOICES[3] }
local DIRECTION_CHOICES = { { "top", "From The Top" }, { "bottom", "From The Bottom" } }
local BARCOLOR_CHOICES = { { false, "By Time Left" }, { true, "Spell Color" } }
local FLYDIR_CHOICES = { { "below", "Below" }, { "auto", "Auto" }, { "above", "Above" } }
local READY_STYLES = { { "off", "Off" }, { "shake", "Shake" }, { "pop", "Pop" }, { "flash", "Flash" }, { "glow", "Glow" },
	{ "shine", "Shine" }, { "dot", "Dot" } }
local ALMOST_STYLES = { { "off", "Off" }, { "pulse", "Pulse" }, { "glow", "Glow" }, { "drain", "Frame drains" },
	{ "underbar", "Bar under it" } }
local RUNNING_STYLES = { { "off", "Off" }, { "red", "Turns red" }, { "pulse", "Pulse" }, { "glow", "Glow" },
	{ "drain", "Frame drains" }, { "underbar", "Bar under it" } }
local GONE_STYLES = {
	[SHIELD] = { { "off", "Off" }, { "shake", "Shake" }, { "pop", "Pop" }, { "flash", "Flash" }, { "glow", "Glow" },
		{ "burst", "Shield burst" }, { "blinkflag", "Frame blink + flag" } },
	[IMBUE] = { { "off", "Off" }, { "shake", "Shake" }, { "pop", "Pop" }, { "flash", "Flash" }, { "glow", "Glow" },
		{ "flare", "Element flare" }, { "flag", "Corner flag" } },
}

local function LookRows(t)
	local r = {}
	if IsShieldOrImbue(t) then
		r[#r + 1] = ChoiceName(t, "Button Style", "buttonStyle", STYLE_CHOICES,
			"How the button picks what it shows. Same As The Totem Bar: the way your Totem Bar Style works (General > Main).\n\n"
			.. "Normal: the one you assigned, lit only while it is up. TotemTimers Style: the one that is up, with your assigned"
			.. " one in its corner. Single Totem: the one that is up, without the corner. Dynamic (PvP): the one that is up, and"
			.. " casting another one makes it your assigned one. Grid: every choice laid out beside it (no flyout).", "mirror")
	end
	r[#r + 1] = ChoiceName(t, "Sweep", "sweep", t == IMBUE and SWEEP_CHOICES_IMBUE or SWEEP_CHOICES,
		"Grays Out: the icon starts in color and gray covers it as time runs out. Fills Back In: the icon starts gray and"
		.. " its color comes back. Radial Swipe: the classic clock swipe. None: no sweep.", "greys")
	local sweep = Get(t, "sweep")
	if sweep == "greys" or sweep == "fills" then
		r[#r + 1] = ChoiceName(t, "Sweep Direction", "sweepDirection", DIRECTION_CHOICES,
			"Where the gray (Grays Out) or the color (Fills Back In) starts.", "top")
	end
	r[#r + 1] = OnOffName(t, "Progress Bar", "progressBar", "A colored bar beside the button that runs down with the time left."
		.. " Where it sits and how big it is: Progress Bars and Time on this page.")
	if Get(t, "progressBar") ~= false then
		r[#r + 1] = Choice("Progress Bar Color", BARCOLOR_CHOICES, function()
			local v, own = Get(t, "progressColor")
			return v and true or false, own
		end, function(v) return Set(t, "progressColor", v) end,
			"By Time Left: green, then yellow, then red. Spell Color: the spell's own color while there is plenty of time"
			.. " (with less than 10 minutes left it still turns yellow, then red).")
	end
	if t ~= SHIELD then
		local where = OptGet(D, "cdbar_duration_text") or "none"
		if where == "none" then
			r[#r + 1] = OnOffName(t, "Time Left On The Icon", "timeOnIcon", "The time left, in the middle of the icon.")
		end
	end
	if t == ANKH then
		r[#r + 1] = OnOffName(t, "Ankh Count", "ankhCount", "How many Ankhs are in your bags, on the icon.")
	end
	return r
end

local function ChargeRows(t)
	local r = { OnOffName(t, "Charge Count", "chargeCount", "The charges left, in the button's corner.") }
	if Get(t, "chargeCount") ~= false then
		r[#r + 1] = OnOffName(t, "Color The Count", "colorCount", "Green when full, yellow at half, red when low. Off: white.")
	end
	r[#r + 1] = OnOffName(t, "Charge Bar", "chargeBar", "A bar along the bottom of the button, one piece per charge.")
	return r
end

local FOREVER = SPCompat and SPCompat.FOREVER
local function EffectRows(t)
	local r = {}
	if IsShieldOrImbue(t) then
		local shield = t == SHIELD
		r[#r + 1] = EffectRow(t, shield and "Shield Gone" or "Weapon Imbue Gone", "cueGone", "cueGoneStyle", GONE_STYLES[t], "shake",
			shield and ("When your shield is gone, the button plays this in blue."
				.. (FOREVER and " In a fight it pulses red while no shield is up (at 100% Cooldown Bar opacity)." or ""))
			or "When the imbue drops off (it ran out, or you swapped weapons), the button plays this in blue.")
		if Get(t, "cueGone") then
			r[#r + 1] = OnOffName(t, shield and "Red X Until You Cast a Shield Again" or "Red X Until You Imbue Again", "cueMark",
				shield and ("Also a red X on the button until you cast a shield again (5 seconds at most)."
					.. (FOREVER and " In a fight it shows while no shield is up instead (at 100% Cooldown Bar opacity)." or ""))
				or "Also a red X on the button until you put an imbue on again (5 seconds at most).")
		end
		r[#r + 1] = OnOffName(t, "Turns Red While Missing", "cueMissing",
			shield and "While your shield is gone, the button turns red until you cast it again."
			or "While a weapon imbue is gone, the button turns red until you imbue again (with two weapons: either hand).")
		r[#r + 1] = EffectRow(t, "Running Out", "cueRunning", "cueRunningStyle", RUNNING_STYLES, "red",
			"Over its last moments (Running Out At), the button plays this until you cast it again."
			.. (shield and " A shield also counts as running out on its last charge." or ""))
		r[#r + 1] = OnOffName(t, "Time Turns Red While Running Out", "cueTimeColor",
			"The time on the button turns red while it is running out. On a button that turns red, the time stays white so you can read it.")
		r[#r + 1] = SEP
		r[#r + 1] = { text = "Test This Item's Effects", onClick = function()
			if SP.TestCooldownCues then SP:TestCooldownCues() end
			return true
		end }
	else
		r[#r + 1] = EffectRow(t, "Cooldown Ready", "cueReady", "cueReadyStyle", READY_STYLES, "pop",
			"When the cooldown is ready again, the button plays this in gold.")
		r[#r + 1] = EffectRow(t, "Cooldown Almost Ready", "cueAlmost", "cueAlmostStyle", ALMOST_STYLES, "glow",
			"Over the cooldown's last seconds (Almost Ready At), the button plays this in gold.")
		r[#r + 1] = OnOffName(t, "Time Turns Gold When Almost Ready", "cueTimeColor",
			"The time on the button turns gold over its last seconds (Almost Ready At).")
		r[#r + 1] = SEP
		r[#r + 1] = { text = "Test This Item's Effects", onClick = function()
			if SP.TestCooldownCues then SP:TestCooldownCues() end
			return true
		end }
	end
	return r
end

local function ClickRows(t)
	local swapped = SP.ClicksSwapped and SP:ClicksSwapped()
	return { OnOffName(t, (swapped and "Left" or "Right") .. "-Click Casts Your Other Shield", "rightClickOther",
		"Click the shield button with this button to cast your other shield: Water Shield while the button is on Lightning"
		.. " Shield, Lightning Shield while it's on Water Shield. That shield then stays on the button. Works in fights."
		.. " (The totem bar's clicks are on Totem Bar > Clicks.)") }
end

local function FlyoutRows(t)
	local r = {}
	local layout = SP.opt and (SP.opt.cdbarLayout or SP.opt.layout)
	if layout == "Horizontal" then
		r[#r + 1] = ChoiceName(t, "Direction", "flyoutDirection", FLYDIR_CHOICES,
			"Where the flyout opens while the bar is horizontal.", "auto")
	end
	r[#r + 1] = Slider("Icon Size", 12, 56, 1, function() return Get(t, "flyoutIconSize") or 22 end,
		function(v) SliderSet(t, "flyoutIconSize", v) end, nil, false,
		"How big the icons in the flyout are. 22 is the classic size. The Cooldown Bar's scale still applies on top.")
	r[#r + 1] = Slider("Opacity", 0.1, 1, 0.05, function() return Get(t, "flyoutOpacity") or 1 end,
		function(v) SliderSet(t, "flyoutOpacity", v) end, nil, true, "How see-through the flyout is.")
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
	r[#r + 1] = { text = "Set Keys In Keybind Mode", onClick = function()
		if SP.SetKeybindMode then SP:SetKeybindMode(true) end
	end }
	return r
end

local function MenuItems(item)
	local t = item.key
	local r = {}
	if IsShieldOrImbue(t) then
		r[#r + 1] = Choice("Show", { { "always", "Always" }, { "runout", "Only When Running Out" } }, function()
			local v, own = Get(t, "runOutOnly")
			return v and "runout" or "always", own
		end, function(v) return Set(t, "runOutOnly", v == "runout") end,
			"Only When Running Out: out of sight until it is running out, then up with its time left. Gone: up until you cast"
			.. " it again. It keeps its place on the bar."
			.. ((FOREVER and t == SHIELD) and " On WoW: Forever your shield stays on the bar during a fight: the game doesn't tell addons when it runs out there." or ""))
		r[#r + 1] = Slider("Running Out At", 10, 300, 5, function() return Get(t, "runOutSecs") or 60 end,
			function(v) SliderSet(t, "runOutSecs", v) end, Secs, false,
			"When it counts as running out, for Show and for the Running Out effect."
			.. (t == SHIELD and " A shield also counts as running out on its last charge." or ""))
	else
		r[#r + 1] = Choice("Show", { { "always", "Always" }, { "hide", "Only When Almost Ready, Then Hide Again" },
			{ "keep", "Only When Almost Ready, Until Used" } }, function()
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
			Row:Changed(true)
			return true
		end, "Out of sight until its last seconds (Almost Ready At). Then Hide Again: gone again once it is ready."
			.. " Until Used: up until you use it.")
		r[#r + 1] = Slider("Almost Ready At", 0, 30, 1, function()
			local s = Get(t, "almostSecs")
			if s == nil then s = 5 end
			return s
		end, function(v) SliderSet(t, "almostSecs", v) end, Secs, false,
			"When it counts as almost ready, for Show and for the Cooldown Almost Ready effect. At 0 seconds a cooldown has"
			.. " no last seconds, so Cooldown Almost Ready never plays.")
	end
	if t == RECALL then
		r[#r + 1] = Choice("Where", { { false, "Cooldown Bar" }, { true, "Totem Bar" } }, function()
			local v, own = Get(t, "onTotemBar")
			return v and true or false, own
		end, function(v) return Set(t, "onTotemBar", v) end, "Totem Bar: the button sits at the end of your totem bar instead.")
	end
	r[#r + 1] = Group("Look", function() return LookRows(t) end)
	if t == SHIELD then r[#r + 1] = Group("Charges", function() return ChargeRows(t) end) end
	r[#r + 1] = Group("Effects", function() return EffectRows(t) end)
	if t == SHIELD then r[#r + 1] = Group("Clicks", function() return ClickRows(t) end) end
	if IsShieldOrImbue(t) then r[#r + 1] = Group("Flyout", function() return FlyoutRows(t) end) end
	if BINDINGS[t] then r[#r + 1] = Group("Keybind", function() return KeybindRows(t) end) end
	r[#r + 1] = SEP
	local on = ShownOnBar(t)
	r[#r + 1] = { text = on and "Hide This Item" or "Show This Item", onClick = function()
		OptSet(I, SHOW_OPTION[t], not on)
		Row:Changed(false)
	end }
	return r
end

-- ---------------------------------------------------------------------------
-- Order: the item to its new place (the bar's saved order; the items this game
-- doesn't have keep their saved places after the rest, as the old Order tab's swap did)
-- ---------------------------------------------------------------------------
local function MoveItem(item, index)
	if InCombatLockdown() or not SP.GetCooldownBarOrder then return end
	local order = SP:GetCooldownBarOrder()
	local from
	for i, x in ipairs(order) do if x == item.key then from = i break end end
	if not from then return end
	table.remove(order, from)
	table.insert(order, math.max(1, math.min(#order + 1, index)), item.key)
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
		for _, t in ipairs(SP.GetCooldownBarOrder and SP:GetCooldownBarOrder() or {}) do
			out[#out + 1] = { key = t, name = NAMES[t] or ("Item " .. t) }
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
	hasOwn = function() return false end,
	toggle = function(item)
		local key = SHOW_OPTION[item.key]
		if key then OptSet(I, key, not ShownOnBar(item.key)) end
	end,
	menu = MenuItems,
	move = MoveItem,
	locked = function() return InCombatLockdown() end,
})
ns.CustomRows.cdbarIcons = Row
ns.CdbarRow = Row

-- SP:CooldownBarOpenItemMenu(type, path): the settings window on the Cooldown Bar page with
-- that item's menu open once the row is drawn
function SP.CooldownBarOpenItemMenu(_, t, path)
	local cfg = _G.ShamanPowerConfig
	if not (cfg and cfg.Open) then return end
	Row:QueueMenu(t, path)
	cfg:Open({ "fluffy", "cdbar_page" })
end
