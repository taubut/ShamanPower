-- ShamanPower_Config :: ShieldIcons
-- The Shield Charges settings page (A17 part A, 3.0.8): its Shields row and every
-- shield's right-click menu, on the shared icon row (IconRow.lua). Lightning Shield and
-- Water Shield (WoW: Forever), and Earth Shield on TBC Anniversary (a talent: dark until
-- learned). Click: that shield's charges shown or hidden. Right-click: all of its
-- settings (Show, Scale and Opacity on the first level; Icon & Number, Charge Bar,
-- Color, Sound; Copy / Paste / Copy To, Hide, Reset). No drag: each shield has its own
-- spot on screen, so there is no order. The rest of the page (Lock Position, Move) is
-- ShamanPowerOptions.lua's. Beside the icons: a line per shield saying how it is set up
-- (A17c). Under the row, What You See: each shield's real display, drawn by the Shield
-- Charges module with that shield's own settings; a click plays its charges being used.
--
-- The owner's rule: Lightning, Water and Earth Shield are three separate shields. Each
-- owns every one of its settings; a copy copies values once and never links them. Every
-- value goes through the Shield Charges module (SP:ShieldOpt / SP:SetShieldOpt ...,
-- ShamanPower_ShieldCharges): this page only reads and writes them. A value the shield
-- changed from its starting value is drawn in blue, and the shield gets the blue corner.
local _, ns = ...
local Core = ns.Core
local SP = ShamanPower
if not (Core and SP and ns.IconRow) then return end

local Menu = ns.IconRow.Menu
local Choice, OnOff, Slider, Group = Menu.Choice, Menu.OnOff, Menu.Slider, Menu.Group
local SEP = { separator = true }

-- (the words that say what to do in the settings' blue, so a player sees them first)
local CAPTION = "|cff3FA9F5Click|r a shield to show or hide its charges. |cff3FA9F5Right-click|r it for all of its"
	.. " settings: each shield has its own, and nothing is shared. |cff3FA9F5Dark|r: not learned yet (you can still set it up)."

local function Red(text) print("|cff0070ddShamanPower|r: |cffe64a4a" .. text .. "|r") end
local LOCKED_TEXT = "Shield Charges' settings can't change in combat - try again after the fight."

-- ---------------------------------------------------------------------------
-- The shields
-- ---------------------------------------------------------------------------
local LS, WS, ES = "LS", "WS", "ES"
local NAMES, ICONS, SPELLS = {}, {}, {}

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

local function Setup()
	if NAMES[LS] then return end
	local label = SPCompat and SPCompat.SpellLabel or function(_, fb) return fb end
	local water = (SP.ShieldSpells and SP.ShieldSpells[2] and SP.ShieldSpells[2][1]) or 24398
	SPELLS[LS], SPELLS[WS], SPELLS[ES] = 324, water, 974
	NAMES[LS] = label(324, "Lightning Shield")
	NAMES[WS] = label(water, "Water Shield")
	NAMES[ES] = label(974, "Earth Shield")
	ICONS[LS] = SpellTexture(324) or 136051
	ICONS[WS] = SpellTexture(water) or 132315
	ICONS[ES] = SpellTexture(974) or 136089
end

-- Earth Shield: TBC Anniversary only (WoW: Forever has none)
local function EarthHere()
	if SPCompat and SPCompat.FOREVER then return false end
	if SP.ESTrackerUnavailable then return false end
	if SPCompat and SPCompat.earthShieldExists == false then return false end
	return true
end
local function List()
	if EarthHere() then return { LS, WS, ES } end
	return { LS, WS }
end
local function Others(s)
	local o = {}
	for _, x in ipairs(List()) do if x ~= s then o[#o + 1] = x end end
	return o
end

local function Known(id) return id and SPCompat and SPCompat.KnowsSpellID and SPCompat.KnowsSpellID(id) or false end

-- ---------------------------------------------------------------------------
-- The values: the module's (SP:ShieldOpt -> value, changed). This page never stores one.
-- ---------------------------------------------------------------------------
local function HasAPI() return type(SP.ShieldOpt) == "function" and type(SP.SetShieldOpt) == "function" end

-- each value's starting value (CONTRACT-shields.final.md): a value that differs is the shield's
-- own, drawn in blue. The sound starts from today's one shared Sound When Your Shield Drops.
local START = {
	show = "up", scale = 1, opacity = 1, icon = false, number = true, numberPosition = "center", bar = false,
	look = "bar", direction = "below", orbColor = "bar", orbEmpty = true, anim = false, texture = "default",
	gradient = "default", gradientDirection = "default", gradientFade = 0.15,
}
local WHICH_OF = { LS = 1, WS = 2, ES = 3 }
local function StartOf(name, s)
	-- (Earth Shield's starts from the shared sound only while Expiring Alerts' Earth Shield alert is on)
	if (name == "sound" or name == "soundName") and SP.ShieldSoundShared and WHICH_OF[s] then
		local on, sound = SP:ShieldSoundShared(WHICH_OF[s])
		if name == "sound" then return on end
		return sound
	end
	if name == "sound" then return (SP.opt and SP.opt.shieldDropSound == true) or false end
	if name == "soundName" then return (SP.opt and SP.opt.shieldDropSoundName) or "Raid Warning" end
	if name == "gradientColor2" then return { r = 1, g = 0.82, b = 0 } end
	return START[name]
end
local function Same(a, b)
	if type(a) == "number" and type(b) == "number" then return math.abs(a - b) < 0.0001 end
	if type(a) == "table" and type(b) == "table" then
		return Same(a.r or a[1], b.r or b[1]) and Same(a.g or a[2], b.g or b[2]) and Same(a.b or a[3], b.b or b[3])
	end
	return a == b
end

local Row   -- (below)
local function Get(s, name)
	if not HasAPI() then return nil, false end
	local v = SP:ShieldOpt(s, name)
	return v, not Same(v, StartOf(name, s))
end
local function Val(s, name) return (Get(s, name)) end
-- (SetShieldOpt refreshes the shield itself; a copy or a reset is refreshed here)
local function Changed(s)
	if SP.ShieldChanged then SP:ShieldChanged(s) end
end
-- a choice: saved, the menu stays open and is drawn again
local function Set(s, name, v)
	if not HasAPI() then return true end
	SP:SetShieldOpt(s, name, v)
	Row:Changed(true)
	return true
end
-- a slider's value: only saved, the icons and the preview follow; never a redraw of the
-- page under a drag
local function SliderSet(s, name, v)
	if not HasAPI() then return end
	SP:SetShieldOpt(s, name, v)
	Row:Repaint()
	local cfg = _G.ShamanPowerConfig
	if cfg and cfg.PreviewChanged then cfg:PreviewChanged() end
end

local function OnOffName(s, text, name, tip)
	return OnOff(text, function() return Get(s, name) end, function(v) return Set(s, name, v) end, tip)
end
local function ChoiceName(s, text, name, list, tip, fallback)
	return Choice(text, list, function()
		local v, own = Get(s, name)
		if v == nil then v = fallback end
		return v, own
	end, function(v) return Set(s, name, v) end, tip)
end
local function Pct(v) return string.format("%d%%", math.floor((tonumber(v) or 0) * 100 + 0.5)) end

-- ---------------------------------------------------------------------------
-- The choices (the module's values; the words a new player reads)
-- ---------------------------------------------------------------------------
local SHOW_CHOICES = {
	{ "up", "While It's Up" },
	{ "always", "Always (Gray While It's Not Up)" },
	{ "fightsUp", "In Fights, While It's Up" },
	{ "fights", "In Fights (Gray While It's Not Up)" },
}
local NUMPOS_CHOICES = { { "center", "Center" }, { "corner", "Bottom-Right Corner" } }
local LOOKS = { { "bar", "Bar" }, { "glow", "Glowing Orbs" }, { "icon", "Shield Icon Orbs" }, { "flat", "Flat Orbs" },
	{ "storm", "Storm Orbs" } }
local LOOK_EXTRA = {
	[WS] = { { "tide", "Tide Orbs" }, { "bubble", "Bubble Orbs" }, { "foam", "Foam Orbs" } },
	[ES] = { { "stone", "Stone Ring Orbs" }, { "leaf", "Leaf Wreath Orbs" }, { "spike", "Spiked Stone Orbs" } },
}
local STORM = { storm = true, tide = true, bubble = true, foam = true, stone = true, leaf = true, spike = true }
local DIR_CHOICES = { { "below", "Below" }, { "above", "Above" }, { "right", "Vertical, Right" }, { "left", "Vertical, Left" } }
local DIR_ALONE = { { "below", "Horizontal" }, { "right", "Vertical" } }
local ORBCOL_CHOICES = { { "bar", "Same As Charge Color" }, { "shield", "The Shield's Own Color" } }
local ANIM_TEXT = { [LS] = "Animated Lightning", [WS] = "Animated Water", [ES] = "Animated Earth" }
local ANIM_TIP = {
	[LS] = "Blizzard's lightning spell effect crackling over each orb.",
	[WS] = "Blizzard's icy blue spell effect glowing over each orb.",
	[ES] = "Blizzard's green nature spell effect glowing over each orb.",
}
local DEFAULT_TEX = "default"
local GRADIENT_DIRS = { { "default", "Along the Bar (default)" }, { "ttb", "Top to Bottom" }, { "btt", "Bottom to Top" },
	{ "ltr", "Left to Right" }, { "rtl", "Right to Left" } }
local DEFAULT_SOUND = "Raid Warning"

local function LookList(s)
	local o = {}
	for _, l in ipairs(LOOKS) do o[#o + 1] = l end
	for _, l in ipairs(LOOK_EXTRA[s] or {}) do o[#o + 1] = l end
	if SP.ShieldLookAvailable then
		local keep = {}
		for _, l in ipairs(o) do if SP:ShieldLookAvailable(s, l[1]) then keep[#keep + 1] = l end end
		return keep
	end
	return o
end
local function GradientList()
	local o = {}
	for _, g in ipairs(SP.GRADIENTS or { { key = "default", label = "Flat (default)" } }) do o[#o + 1] = { g.key, g.label } end
	return o
end
local function TextureList()
	local o = { { DEFAULT_TEX, "Default (as designed)" } }
	for _, name in ipairs(SP.TextureList and SP:TextureList() or {}) do o[#o + 1] = { name, name } end
	return o
end

-- ---------------------------------------------------------------------------
-- Copy, Paste, Copy To, and each group's own copy line: values once, never links
-- ---------------------------------------------------------------------------
local function CopyTo(from, to, group)
	if not SP.CopyShield then return end
	if to == "all" then
		for _, x in ipairs(Others(from)) do SP:CopyShield(from, x, group); Changed(x) end
	else
		SP:CopyShield(from, to, group)
		Changed(to)
	end
end
local function ToAll(s, what, group)
	return { text = "Copy " .. what .. " To All Shields",
		tip = "Copies this shield's " .. what .. " settings onto the other shields once. They stay separate: changing one later never changes another.",
		onClick = function() CopyTo(s, "all", group); Row:Changed(true); return true end }
end

-- every value of a shield, as it is at Copy (Paste puts these, even if the shield changes after)
local function CopyValue(v)
	if type(v) ~= "table" then return v end
	local o = {}
	for k, x in pairs(v) do o[k] = x end
	return o
end
local function Snapshot(s)
	local snap = {}
	if not (HasAPI() and SP.ShieldNames) then return snap end
	for _, name in ipairs(SP:ShieldNames() or {}) do
		local v = Get(s, name)
		snap[name] = { v = CopyValue(v) }
	end
	return snap
end
local function Paste(snap, to)
	if not (HasAPI() and snap) then return end
	local own = {}
	for _, l in ipairs(LookList(to)) do own[l[1]] = true end
	for name, e in pairs(snap) do
		local v = CopyValue(e.v)
		-- a look this shield doesn't have (Tide Orbs onto Lightning Shield): its Storm Orbs
		if name == "look" and v ~= nil and not own[v] then v = "storm" end
		SP:SetShieldOpt(to, name, v)
	end
end

-- ---------------------------------------------------------------------------
-- The menu
-- ---------------------------------------------------------------------------
local function ShowTip(s)
	if s == ES then
		return "When your Earth Shield's charges are on screen. It's up while it is on someone (the player you put it on)."
			.. " Gray: its icon or number grayed out while it's not up."
	end
	return "When this shield's charges are on screen. Gray: its icon or number grayed out while it's not up."
		.. " With no shield up, only the last one you had shows its gray look."
end

local function IconRows(s)
	local icon, bar = Val(s, "icon"), Val(s, "bar")
	local r = { OnOffName(s, "Shield Icon", "icon", "The shield's icon, with the number on it.") }
	local number = OnOffName(s, "Number", "number",
		"The charges left, as a number. It can only be off while the icon or the charge bar is on, so the display never goes blank.")
	if not (icon or bar) then
		-- nothing else would be left on screen: the number stays (and says why)
		number.disabled = true
		number.sub = nil
		number.value = function() return "On", false end
		number.tip = "The number stays on while the icon and the charge bar are both off, so the display never goes blank."
			.. " Turn on the Shield Icon or the Charge Bar to turn it off."
	end
	r[#r + 1] = number
	if icon and Val(s, "number") ~= false then
		r[#r + 1] = ChoiceName(s, "Number Position", "numberPosition", NUMPOS_CHOICES,
			"Large in the center of the icon, or smaller in its bottom-right corner.", "center")
	end
	r[#r + 1] = SEP
	r[#r + 1] = ToAll(s, "Icon & Number", "icon")
	return r
end

local function BarRows(s)
	local n = (s == ES) and "6" or "3"
	local r = { OnOffName(s, "Charge Bar", "bar", "A bar with one piece per charge (" .. n .. "), or one orb per charge.") }
	if Val(s, "bar") then
		local look = Val(s, "look") or "bar"
		r[#r + 1] = ChoiceName(s, "Look", "look", LookList(s), "The bar, or one orb per charge. Works in fights.", "bar")
		-- with the icon and the number both off there is nothing to sit beside: only flat or upright
		local alone = not Val(s, "icon") and Val(s, "number") == false
		r[#r + 1] = Choice("Direction", alone and DIR_ALONE or DIR_CHOICES, function()
			local v, own = Get(s, "direction")
			v = v or "below"
			if alone then
				if v == "above" then v = "below" elseif v == "left" then v = "right" end
			end
			return v, own
		end, function(v)
			local d = Val(s, "direction") or "below"
			-- alone: picking the shape it already has keeps its side
			if alone and ((v == "below" and d == "above") or (v == "right" and d == "left")) then return true end
			return Set(s, "direction", v)
		end, alone and "The bar lies flat or stands upright (the icon and the number are off, so there is nothing to sit beside)."
			or "Where the bar sits: under, over or beside the icon or number. Vertical bars fill from the bottom.")
		if look == "bar" then
			r[#r + 1] = Choice("Texture", TextureList(), function()
				local v, own = Get(s, "texture")
				return v or DEFAULT_TEX, own
			end, function(v) return Set(s, "texture", v) end, "This shield's own bar texture: it never follows Bar Texture.")
			r[#r].subMaxHeight = 300
		end
		if look == "glow" or look == "flat" then
			r[#r + 1] = ChoiceName(s, "Orb Color", "orbColor", ORBCOL_CHOICES,
				"Same As Charge Color: the orbs in this shield's Charge Color (Color). The Shield's Own Color: the shield's usual color.", "bar")
		end
		if look ~= "bar" then
			r[#r + 1] = OnOff("Empty Orbs", function()
				local v, own = Get(s, "orbEmpty")
				return v ~= false, own
			end, function(v) return Set(s, "orbEmpty", v) end,
				"A faint ring where a used charge was, so you always see how many the shield had.")
		end
		if STORM[look] then
			r[#r + 1] = OnOffName(s, ANIM_TEXT[s], "anim", ANIM_TIP[s] .. " Off to start. It may slightly lower your frame rate.")
		end
	end
	r[#r + 1] = SEP
	r[#r + 1] = ToAll(s, "Charge Bar", "bar")
	return r
end

-- a color row: its swatch, a click opens ShamanPower's color picker (Cancel puts it back)
local function ColorRow(s, text, name, fallback, tip)
	local function rgb()
		local c = Val(s, name)
		if type(c) == "table" then return c.r or c[1] or 1, c.g or c[2] or 1, c.b or c[3] or 1 end
		if type(fallback) == "function" then return fallback() end
		return fallback[1], fallback[2], fallback[3]
	end
	local r, g, b = rgb()
	return { text = text, tip = tip, swatch = { r, g, b }, onClick = function()
		if not SP.OpenColorPicker then return false end
		local before = CopyValue(Val(s, name))
		local cr, cg, cb = rgb()
		SP:OpenColorPicker({
			r = cr, g = cg, b = cb, hasAlpha = false, title = (NAMES[s] or "") .. " " .. text,
			onChange = function(nr, ng, nb)
				if InCombatLockdown() then return end
				SP:SetShieldOpt(s, name, { r = nr, g = ng, b = nb })
				Row:Changed(false)
			end,
			-- Cancel: exactly as it was
			onCancel = function()
				SP:SetShieldOpt(s, name, before)
				Row:Changed(false)
			end,
		})
		return false   -- the menu closes; the color picker is open
	end }
end

local WHICH = { [LS] = 1, [WS] = 2, [ES] = 3 }
local GOLD = { 1, 0.82, 0 }
local function ColorRows(s)
	-- today's color for this shield (a theme's Shield Colors included)
	local own = function()
		if SP.ShieldChargeColorOf then return SP:ShieldChargeColorOf(WHICH[s]) end
		return 0.2, 0.6, 1
	end
	local r = { ColorRow(s, "Charge Color", "chargeColor", own,
		"This shield's charge bar and orbs (Shield Icon Orbs keep their icons). Any color you like.") }
	local look = Val(s, "look") or "bar"
	if Val(s, "bar") and (look == "bar" or look == "glow" or look == "flat") then
		local grad = Val(s, "gradient") or "default"
		r[#r + 1] = ChoiceName(s, "Gradient", "gradient", GradientList(),
			"Shades this shield's charge bar (and its Glowing and Flat orbs). Its own: never Bar Gradient's.", "default")
		if grad ~= "default" then
			r[#r + 1] = ChoiceName(s, "Gradient Direction", "gradientDirection", GRADIENT_DIRS,
				"Where the gradient starts on screen.", "default")
		end
		if grad == "two" then
			-- (no First Color of its own: it starts from the Charge Color)
			r[#r + 1] = OnOff("Start From Its Own Color", function()
				local c1 = Val(s, "gradientColor1")
				return c1 == nil, c1 ~= nil
			end, function(v)
				if v then return Set(s, "gradientColor1", nil) end
				local cr, cg, cb = own()
				return Set(s, "gradientColor1", { r = cr, g = cg, b = cb })
			end, "On: it starts in the Charge Color and shades into the second color. Off: it starts in a first color you pick.")
			if Val(s, "gradientColor1") ~= nil then
				r[#r + 1] = ColorRow(s, "First Color", "gradientColor1", own, "The color the gradient starts in.")
			end
			r[#r + 1] = ColorRow(s, "Second Color", "gradientColor2", GOLD, "The color the gradient shades into. WoW gold to start.")
		elseif grad == "fade" then
			r[#r + 1] = Slider("Fade To", 0, 1, 0.01, function()
				local f = Val(s, "gradientFade")
				if f == nil then f = 0.15 end
				return f
			end, function(v) SliderSet(s, "gradientFade", v) end, Pct, true,
				"How much of the color is left at the faded end: 0% fades right into the game world.")
		end
	end
	r[#r + 1] = SEP
	local colorOwn = select(2, Get(s, "chargeColor"))
	r[#r + 1] = { text = "Default Color", tip = colorOwn and "This shield's charges back to their usual color."
			or "This shield's charges already have their usual color.",
		disabled = (not colorOwn) or nil,
		onClick = function() return Set(s, "chargeColor", nil) end }
	r[#r + 1] = ToAll(s, "Color", "color")
	return r
end

local function PlayName(name)
	if not (SP.PlaySoundWithVolume and SP.GetSoundFile) then return end
	SP:PlaySoundWithVolume(SP:GetSoundFile(name), 100, true)
end
local function SoundRows(s)
	local r = { OnOffName(s, "Sound When It Drops", "sound", s == ES
		and "When your Earth Shield is gone from the player you put it on. The same setting as Earth Shield's sound in Expiring Alerts."
		or ("The moment your " .. (NAMES[s] or "shield") .. " leaves you (its last charge used, run out, canceled or replaced),"
			.. " in fights too. The same setting as this shield's sound in Expiring Alerts.")) }
	if Val(s, "sound") then
		r[#r + 1] = {
			text = "Sound", subMaxHeight = 300,
			value = function()
				local v, own = Get(s, "soundName")
				return tostring(v or DEFAULT_SOUND), own
			end,
			sub = function()
				local lsm = LibStub and LibStub("LibSharedMedia-3.0", true)
				local names = lsm and lsm:List("sound")
				local cur = Val(s, "soundName") or DEFAULT_SOUND
				local items = {}
				for _, name in ipairs(type(names) == "table" and names or {}) do
					-- only the speaker button plays one; choosing or moving through the list is silent
					items[#items + 1] = { text = name, selected = name == cur,
						preview = function() PlayName(name) end,
						onClick = function() return Set(s, "soundName", name) end }
				end
				return items
			end,
		}
		r[#r + 1] = { text = "Test Sound", onClick = function()
			if SP.TestShieldSound then SP:TestShieldSound(s) end
			return true
		end }
	end
	r[#r + 1] = SEP
	r[#r + 1] = ToAll(s, "Sound", "sound")
	return r
end

local function Shown(s) return Val(s, "enabled") and true or false end

-- the line beside the icons (A17c): how each shield is set up, in its menu's words
local function LookName(s)
	local look = Val(s, "look") or "bar"
	if look == "bar" then return "Charge Bar" end
	for _, l in ipairs(LookList(s)) do if l[1] == look then return l[2] end end
	return "Charge Bar"
end
local NAME_COLOR = "|cffE6EAF0"   -- Core's text (the rest is the row's dim text)
local function Summary()
	Setup()
	local lines = {}
	for _, s in ipairs(List()) do
		local what
		if not Shown(s) then
			what = "hidden"
		else
			local icon, bar = Val(s, "icon"), Val(s, "bar")
			local number = Val(s, "number") ~= false or not (icon or bar)
			local parts = {}
			if bar then parts[#parts + 1] = LookName(s) end
			if icon then
				parts[#parts + 1] = number and "icon + number" or "icon"
			elseif number then
				parts[#parts + 1] = "number"
			end
			parts[#parts + 1] = "size " .. Pct(Val(s, "scale") or 1)
			local op = Val(s, "opacity") or 1
			if op < 0.995 then parts[#parts + 1] = "opacity " .. Pct(op) end
			what = table.concat(parts, ", ")
		end
		if not Known(SPELLS[s]) then what = what .. "  (not learned yet)" end
		lines[#lines + 1] = NAME_COLOR .. (NAMES[s] or s) .. ":|r  " .. what
	end
	return table.concat(lines, "\n")
end

local function MenuItems(item)
	local s = item.key
	local r = {}
	r[#r + 1] = ChoiceName(s, "Show", "show", SHOW_CHOICES, ShowTip(s), "up")
	r[#r + 1] = Slider("Scale", 0.5, 3, 0.05, function() return Val(s, "scale") or 1 end,
		function(v) SliderSet(s, "scale", v) end, Pct, true,
		"The size of this shield's charges: number, icon and charge bar. In Unlock UI, the mouse wheel over its box does the same.")
	r[#r + 1] = Slider("Opacity", 0.1, 1, 0.05, function() return Val(s, "opacity") or 1 end,
		function(v) SliderSet(s, "opacity", v) end, Pct, true, "How see-through this shield's charges are.")
	r[#r + 1] = Group("Icon & Number", function() return IconRows(s) end)
	r[#r + 1] = Group("Charge Bar", function() return BarRows(s) end)
	r[#r + 1] = Group("Color", function() return ColorRows(s) end)
	r[#r + 1] = Group("Sound", function() return SoundRows(s) end,
		"The same setting as this shield's sound in Expiring Alerts: each shield has its own.")
	r[#r + 1] = SEP
	r[#r + 1] = { text = "Copy Settings", disabled = (not HasAPI()) or nil,
		tip = "Remembers every setting of this shield as it is now, for Paste Settings on another shield.",
		onClick = function()
			Row.clip = { from = s, name = NAMES[s], snap = Snapshot(s) }
			return true
		end }
	local clip = Row.clip
	r[#r + 1] = { text = clip and ("Paste Settings  (from " .. clip.name .. ")") or "Paste Settings",
		disabled = (not clip or clip.from == s) or nil,
		tip = (not clip) and "Copy Settings on another shield first, then paste them here."
			or (clip.from == s) and "These are this shield's own settings: paste them on another shield."
			or "Puts the settings you copied onto this shield, once. The two never stay linked.",
		onClick = function()
			if Row.clip then Paste(Row.clip.snap, s) end
			Row:Changed(true)
			return true
		end }
	r[#r + 1] = { text = "Copy Settings To...", disabled = (not SP.CopyShield) or nil, sub = function()
		local o = {}
		for _, x in ipairs(Others(s)) do
			o[#o + 1] = { text = NAMES[x], icon = ICONS[x], onClick = function() CopyTo(s, x); Row:Changed(false) end }
		end
		o[#o + 1] = SEP
		o[#o + 1] = { text = "All Shields", onClick = function() CopyTo(s, "all"); Row:Changed(false) end }
		return o
	end }
	r[#r + 1] = SEP
	local on = Shown(s)
	r[#r + 1] = { text = on and "Hide This Shield" or "Show This Shield",
		tip = "The same as a click on its icon. Its settings stay as they are.",
		onClick = function()
			if HasAPI() then SP:SetShieldOpt(s, "enabled", not on) end
			Row:Changed(false)
		end }
	local hasOwn = SP.ShieldOwnChanged and SP:ShieldOwnChanged(s)
	r[#r + 1] = { text = "Reset This Shield", disabled = (not hasOwn) or nil,
		tip = hasOwn and "Every setting of this shield back to its starting value. The other shields keep theirs."
			or "Nothing to reset: every setting of this shield is at its starting value.",
		onClick = function()
			if SP.ResetShield then SP:ResetShield(s); Changed(s) end
			Row:Changed(false)
		end }
	return r
end

-- ---------------------------------------------------------------------------
-- The row
-- ---------------------------------------------------------------------------
Row = ns.IconRow.New({
	caption = CAPTION,
	hint = "Click: show or hide its charges\nRight-click: its settings",
	list = function(out)
		Setup()
		for _, s in ipairs(List()) do out[#out + 1] = { key = s, name = NAMES[s] } end
	end,
	textures = function(item, out)
		Setup()
		out[1] = ICONS[item.key]
		return 1
	end,
	shown = function(item) return Shown(item.key) end,
	learned = function(item)
		Setup()
		return Known(SPELLS[item.key])
	end,
	hasOwn = function(item) return SP.ShieldOwnChanged and SP:ShieldOwnChanged(item.key) and true or false end,
	tooltip = function(item)
		local s = item.key
		local lines = {}
		if not Known(SPELLS[s]) then
			lines[#lines + 1] = (s == ES) and "You haven't learned Earth Shield yet (a talent). You can still set it up: it shows once you learn it."
				or "You haven't learned this shield yet. You can still set it up: it shows once you learn it."
		end
		lines[#lines + 1] = Shown(s) and "Its charges show on your screen." or "Hidden: a click brings it back, with all its settings."
		if SP.ShieldOwnChanged and SP:ShieldOwnChanged(s) then
			lines[#lines + 1] = "It has settings changed from its starting values (Reset This Shield in its menu clears them)."
		end
		return table.concat(lines, "\n\n")
	end,
	toggle = function(item)
		if not HasAPI() then return end
		SP:SetShieldOpt(item.key, "enabled", not Shown(item.key))
	end,
	menu = MenuItems,
	beside = Summary,
	locked = function() return InCombatLockdown() end,
	onLocked = function() Red(LOCKED_TEXT) end,
})
ns.CustomRows.shieldIcons = Row
ns.ShieldRow = Row

-- ---------------------------------------------------------------------------
-- What You See (A17c): each shield's real display in a box of its own, drawn by the
-- module (SP:ShieldChargeSample) with that shield's own settings, shrunk to fit only
-- when it is bigger than its box. It follows every change (the row's Repaint). A click
-- plays its charges being used one by one, then puts it back to full. Hidden or not
-- learned yet: shown dim, with a word why.
-- ---------------------------------------------------------------------------
local PV_H, PV_GAP, PV_MAXW = 132, 12, 260
local PV_NAME_H = 24        -- the name under the display
local PV_PAD = 10           -- the display's margin inside its box
local PV_STEP = 0.6         -- a charge used every this many seconds while it plays
local PV_DIM = 0.4          -- hidden / not learned yet
local PV_CAPTION = "Each shield as it looks on your screen, with its own settings: it changes as you change them."
	.. " |cff3FA9F5Click|r one to watch it use its charges."
local WHICH_NUM = { [LS] = 1, [WS] = 2, [ES] = 3 }
local Preview = { boxes = {} }

local function PvTip(s)
	if not Known(SPELLS[s]) then
		return "You haven't learned it yet: this is how it will look once you do."
	end
	if not Shown(s) then return "Hidden: a click on its icon above brings it back." end
	return "How it looks on your screen with its settings now. A click plays its charges being used, then fills it again."
end

function Preview:Paint()
	local f = self.frame
	if not (f and f:IsShown() and SP.ShieldChargeSample and SP.PaintShieldChargeSample) then return end
	for _, b in ipairs(self.boxes) do
		local s = b.shield
		if s and b:IsShown() then
			local which = WHICH_NUM[s]
			local sample = SP:ShieldChargeSample(which, b.area)
			local full = SP.ShieldChargeMax and SP:ShieldChargeMax(which) or 3
			sample:SetScale(1)
			SP:PaintShieldChargeSample(sample, b.charges or full)
			-- shrink to fit the box (never grow): the display's reach at its own size
			local halfW, above, below = 30, 30, 30
			if SP.ShieldChargeDisplayExtent then halfW, above, below = SP:ShieldChargeDisplayExtent(sample) end
			local aw, ah = b.area:GetWidth() - PV_PAD * 2, b.area:GetHeight() - PV_PAD * 2
			local fit = 1
			if halfW > 0 and halfW * 2 > aw then fit = math.min(fit, aw / (halfW * 2)) end
			if above + below > ah then fit = math.min(fit, ah / (above + below)) end
			sample:SetScale(math.max(0.2, fit))
			sample:ClearAllPoints()
			sample:SetPoint("CENTER", b.area, "CENTER", 0, (below - above) / 2)
			sample:Show()
			local dim = not (Shown(s) and Known(SPELLS[s]))
			b.area:SetAlpha(dim and PV_DIM or 1)
			local note = (not Known(SPELLS[s])) and "not learned yet" or ((not Shown(s)) and "hidden")
				or (fit < 0.98 and "shown smaller to fit") or nil
			b.name:SetText(note and ((NAMES[s] or s) .. "  |cff8A94A6(" .. note .. ")|r") or (NAMES[s] or s))
			local r, g, bl = 0.2, 0.6, 1
			local own = Val(s, "chargeColor")
			if type(own) == "table" then
				r, g, bl = own.r or own[1], own.g or own[2], own.b or own[3]
			elseif SP.ShieldChargeColorOf then
				r, g, bl = SP:ShieldChargeColorOf(which)
			end
			b.stripe:SetColorTexture(r or 0.2, g or 0.6, bl or 1, 1)
			Core:AttachTooltip(b, NAMES[s], PvTip(s), "Click: watch it use its charges")
		end
	end
end

-- a click: its charges used one by one, a short wait at none, then full again
local function PvStop(b)
	if b.ticker then b.ticker:Cancel() end
	b.ticker, b.charges = nil, nil
end
local function PvPlay(b)
	local s = b.shield
	if not s then return end
	PvStop(b)
	local full = SP.ShieldChargeMax and SP:ShieldChargeMax(WHICH_NUM[s]) or 3
	b.charges = full
	local waited = false
	b.ticker = C_Timer.NewTicker(PV_STEP, function()
		if not (Preview.frame and Preview.frame:IsVisible()) then PvStop(b) return end
		if b.charges > 0 then
			b.charges = b.charges - 1
		elseif not waited then
			waited = true
			return
		else
			PvStop(b)
		end
		Preview:Paint()
	end)
	Preview:Paint()
end

local function PvBox(parent)
	local b = CreateFrame("Button", nil, parent)
	b:RegisterForClicks("LeftButtonUp")
	local plate = SP.Brand and SP.Brand.plate or { 5 / 255, 7 / 255, 10 / 255 }   -- the icons' plate (#05070A)
	b.bg = b:CreateTexture(nil, "BACKGROUND")
	b.bg:SetAllPoints(b)
	b.bg:SetColorTexture(plate[1], plate[2], plate[3], 1)
	b.edge = CreateFrame("Frame", nil, b)
	b.edge:SetAllPoints(b)
	Core:MakeBorder(b.edge, "border", 1)
	b.hover = CreateFrame("Frame", nil, b)
	b.hover:SetAllPoints(b)
	b.hover:SetFrameLevel(b:GetFrameLevel() + 4)
	Core:MakeBorder(b.hover, "accent", 1)
	b.hover:Hide()
	-- the shield's own charge color along the top, 2 px
	b.stripe = b:CreateTexture(nil, "ARTWORK")
	b.stripe:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
	b.stripe:SetPoint("TOPRIGHT", b, "TOPRIGHT", -1, -1)
	b.stripe:SetHeight(2)
	b.area = CreateFrame("Frame", nil, b)
	b.area:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -3)
	b.area:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, PV_NAME_H)
	if b.area.SetClipsChildren then b.area:SetClipsChildren(true) end
	b.name = b:CreateFontString(nil, "OVERLAY")
	b.name:SetFontObject(Core.fonts.row)
	b.name:SetJustifyH("CENTER")
	b.name:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 6, 7)
	b.name:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -6, 7)
	b:SetScript("OnEnter", function(self) self.hover:Show() end)
	b:SetScript("OnLeave", function(self) self.hover:Hide() end)
	b:SetScript("OnClick", PvPlay)
	return b
end

function Preview:Render(body, x, y, width, onChanged)
	local f = self.frame
	if not f then
		f = CreateFrame("Frame", nil, body)
		f.caption = f:CreateFontString(nil, "OVERLAY")
		f.caption:SetFontObject(Core.fonts.rowDim)
		f.caption:SetJustifyH("LEFT")
		f.caption:SetWordWrap(true)
		f.spNoCull = true
		self.frame = f
	end
	f:SetParent(body)
	f:ClearAllPoints()
	f:SetPoint("TOPLEFT", body, "TOPLEFT", x or 0, -(y or 0))
	f:SetWidth(width)
	f:Show()
	Setup()
	local list = List()
	local padX = 12 + (ns.Widgets and tonumber(ns.Widgets.CARD_INSET) or 0)   -- in line with the rows (IconRow's PAD_X)
	local n = #list
	local bw = math.min(PV_MAXW, math.floor((width - padX * 2 - PV_GAP * (n - 1)) / math.max(1, n)))
	for i, s in ipairs(list) do
		local b = self.boxes[i] or PvBox(f)
		self.boxes[i] = b
		if b.shield ~= s then PvStop(b) end
		b.shield = s
		b:SetSize(bw, PV_H)
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", f, "TOPLEFT", padX + (i - 1) * (bw + PV_GAP), -10)
		b:Show()
	end
	for i = n + 1, #self.boxes do
		PvStop(self.boxes[i])
		self.boxes[i].shield = nil
		self.boxes[i]:Hide()
	end
	f.caption:ClearAllPoints()
	f.caption:SetPoint("TOPLEFT", f, "TOPLEFT", padX, -(10 + PV_H + 10))
	f.caption:SetWidth(width - padX * 2)
	f.caption:SetText(PV_CAPTION)
	local h = 10 + PV_H + 10 + math.ceil(f.caption:GetStringHeight()) + 12
	f:SetHeight(h)
	self:Paint()
	return f, h + 6
end

function Preview:Release()
	for _, b in ipairs(self.boxes) do
		PvStop(b)
		Core:HideTooltipFor(b)
		b.hover:Hide()
	end
	if self.frame then self.frame:Hide() end
end
ns.CustomRows.shieldPreview = Preview

-- the previews follow every change the row makes or hears (a slider, a theme, a profile)
do
	local repaint = Row.Repaint
	function Row:Repaint(...)
		repaint(self, ...)
		Preview:Paint()
	end
end

-- SP:ShieldChargesOpenMenu(shield, path): the settings window on the Shield Charges page with
-- that shield's menu open once the row is drawn
function SP.ShieldChargesOpenMenu(_, s, path)
	local cfg = _G.ShamanPowerConfig
	if not (cfg and cfg.Open) then return end
	Row:QueueMenu(s, path)
	cfg:Open({ "fluffy", "shieldcharges_page" })
end

-- the page's own refusal in a fight (Move, Lock Position): the same red line
function SP.ShieldChargesRefuseInCombat()
	if not InCombatLockdown() then return false end
	Red(LOCKED_TEXT)
	return true
end

-- ---------------------------------------------------------------------------
-- Reset This Page (Window.lua calls it after the page's own rows): every shield's menu
-- settings back to their starting values, and every shield shown again. Left alone, as on
-- every page: where they sit, and what a theme holds (each shield's Look, Charge Color,
-- texture and gradient: the shield's entries in the theme cards, General > Themes).
-- ---------------------------------------------------------------------------
local THEME_HELD = { "look", "chargeColor", "texture", "gradient", "gradientDirection", "gradientColor1", "gradientColor2",
	"gradientFade" }
function SP.ShieldChargesResetPage(sp)
	if InCombatLockdown() or not (sp.ResetShield and HasAPI()) then return end
	for _, s in ipairs({ LS, WS, ES }) do
		local keep
		for _, name in ipairs(THEME_HELD) do
			local v, own = Get(s, name)
			if own then keep = keep or {}; keep[name] = CopyValue(v) end
		end
		if sp:ShieldOwnChanged(s) then sp:ResetShield(s) end
		for name, v in pairs(keep or {}) do sp:SetShieldOpt(s, name, v) end
		if not Shown(s) then sp:SetShieldOpt(s, "enabled", true) end
		Changed(s)
	end
end
