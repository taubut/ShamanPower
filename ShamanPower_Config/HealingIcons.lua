-- ShamanPower_Config :: HealingIcons
-- The Frame Buff Indicators settings page (3.0.9.17, A117; WoW: Forever only): its Buffs row (Riptide, Ancestral Healing)
-- and each buff's right-click menu, on the shared icon row (IconRow.lua), as Shield Charges' page is built. Click: that
-- buff shown on the party and raid frames or not. Right-click: all of its settings (Icon Size, Position, Offset X / Y;
-- Show Sweep, Show Time Left, Time Text Size; Copy Settings To, Reset This Icon). Beside the icons: a line per buff
-- saying how it is set up. Every value goes through the module (SP:HealingOpt / SP:SetHealingOpt,
-- ShamanPower_HealingTracker): this page only reads and writes them. A value changed from its starting value is
-- drawn in blue, and the buff gets the blue corner.

local _, ns = ...
local Core = ns.Core
local SP = ShamanPower
if not (Core and SP and ns.IconRow) then return end
if not (SPCompat and SPCompat.FOREVER) then return end   -- (the page exists only there)

local Menu = ns.IconRow.Menu
local Choice, OnOff, Slider = Menu.Choice, Menu.OnOff, Menu.Slider
local SEP = { separator = true }

-- (the words that say what to do in the settings' blue, so a player sees them first)
local CAPTION = "|cff3FA9F5CLICK|r a buff to show or hide it on the party and raid frames. |cff3FA9F5RIGHT-CLICK|r it for"
	.. " all of its settings: its size and spot on the frame, the sweep and the time left. |cff3FA9F5Dark|r: not learned yet"
	.. " (you can still set it up)."

-- the buffs: the module's keys, each one's own icon (the one on the frames) and the spells that give it
local BUFFS = {
	{ key = "riptide", name = "Riptide", icon = 252995, spells = { 408521, 1239242, 1239243 } },
	{ key = "ancestral", name = "Ancestral Healing", icon = 136109, spells = { 16176 } },   -- (a talent)
}
local BY_KEY = {}
for _, b in ipairs(BUFFS) do BY_KEY[b.key] = b end

local SPOTS = {
	{ "TOPLEFT", "Top Left" }, { "TOP", "Top" }, { "TOPRIGHT", "Top Right" },
	{ "LEFT", "Left" }, { "CENTER", "Center" }, { "RIGHT", "Right" },
	{ "BOTTOMLEFT", "Bottom Left" }, { "BOTTOM", "Bottom" }, { "BOTTOMRIGHT", "Bottom Right" },
}
local SPOT_NAME = {}
for _, s in ipairs(SPOTS) do SPOT_NAME[s[1]] = s[2] end

-- ---------------------------------------------------------------------------
-- The values: the module's. This page never stores one.
-- ---------------------------------------------------------------------------
local function HasAPI() return type(SP.HealingOpt) == "function" and type(SP.SetHealingOpt) == "function" end

local Row   -- (below)
local function Get(k, name)
	if not HasAPI() then return nil, false end
	return SP:HealingOpt(k, name), SP:HealingOptOwn(k, name) and true or false
end
local function Val(k, name) return (Get(k, name)) end
-- a choice: saved, the menu stays open and is drawn again
local function Set(k, name, v)
	if HasAPI() then SP:SetHealingOpt(k, name, v) end
	Row:Changed(true)
	return true
end
-- a slider's value: only saved, the icons follow; never a redraw of the page under a drag
local function SliderSet(k, name, v)
	if HasAPI() then SP:SetHealingOpt(k, name, v) end
	Row:Repaint()
end
local function Known(b)
	for _, id in ipairs(b.spells) do
		if SPCompat.KnowsSpellID and SPCompat.KnowsSpellID(id) then return true end
	end
	return false
end
local function Shown(k) return Val(k, "on") ~= false end
local function Num(v) return tostring(math.floor((tonumber(v) or 0) + 0.5)) end
local function TextSize(v)
	if (tonumber(v) or 0) <= 0 then return "Auto" end
	return Num(v)
end

-- ---------------------------------------------------------------------------
-- The menu
-- ---------------------------------------------------------------------------
local function MenuItems(item)
	local k = item.key
	local b = BY_KEY[k]
	local r = {}
	-- the buff itself
	local on = Shown(k)
	r[#r + 1] = { text = "Show", label = true }
	r[#r + 1] = { text = on and "Hide This Icon" or "Show This Icon",
		tip = "The same as a click on its icon. Its settings stay as they are.",
		onClick = function()
			if HasAPI() then SP:SetHealingOpt(k, "on", not on) end
			Row:Changed(false)
		end }
	r[#r + 1] = SEP
	-- where it sits on each frame
	r[#r + 1] = { text = "On The Frame", label = true }
	r[#r + 1] = Slider("Icon Size", 8, 30, 1, function() return Val(k, "size") or 14 end,
		function(v) SliderSet(k, "size", v) end, Num, false, "The size of " .. b.name .. "'s icon on each frame.")
	r[#r + 1] = Choice("Position", SPOTS, function()
		local v, own = Get(k, "point")
		return v or "TOPRIGHT", own
	end, function(v) return Set(k, "point", v) end,
		"Where on the frame it sits: a corner, an edge or the middle. WoW's own buffs sit at the bottom right.")
	r[#r + 1] = Slider("Offset X", -40, 40, 1, function() return Val(k, "x") or 0 end,
		function(v) SliderSet(k, "x", v) end, Num, false, "Moves it right (or left, below 0) from its Position.")
	r[#r + 1] = Slider("Offset Y", -40, 40, 1, function() return Val(k, "y") or 0 end,
		function(v) SliderSet(k, "y", v) end, Num, false, "Moves it up (or down, below 0) from its Position.")
	r[#r + 1] = SEP
	-- how long it has left
	r[#r + 1] = { text = "Time Left", label = true }
	r[#r + 1] = OnOff("Show Sweep", function() return Get(k, "sweep") end, function(v) return Set(k, "sweep", v) end,
		"The icon darkens clockwise as it runs out.")
	r[#r + 1] = OnOff("Show Time Left", function() return Get(k, "timeText") end, function(v) return Set(k, "timeText", v) end,
		"The seconds left, on the icon.")
	if Val(k, "timeText") ~= false then
		r[#r + 1] = Slider("Time Text Size", 0, 24, 1, function() return Val(k, "textSize") or 0 end,
			function(v) SliderSet(k, "textSize", v) end, TextSize, false,
			"Auto sizes it to the icon. Its font and outline: Appearance > Fonts & Textures > Frame Buff Indicators.")
	end
	r[#r + 1] = SEP
	-- copy and reset
	r[#r + 1] = { text = "Copy & Reset", label = true }
	r[#r + 1] = { text = "Copy Settings To...", disabled = (not SP.CopyHealingBuff) or nil,
		words = "its size and look onto the other buff, once (never its spot)", sub = function()
		local o = {}
		for _, x in ipairs(BUFFS) do
			if x.key ~= k then
				o[#o + 1] = { text = x.name, icon = x.icon,
					tip = "Its Icon Size, Show Sweep, Show Time Left and Time Text Size, once. Its spot on the frame stays its own.",
					onClick = function() SP:CopyHealingBuff(k, x.key); Row:Changed(false) end }
			end
		end
		return o
	end }
	local own = SP.HealingOwnChanged and SP:HealingOwnChanged(k)
	r[#r + 1] = { text = "Reset This Icon", disabled = (not own) or nil,
		tip = own and "Every setting of this buff back to its starting value. The other buff stays as it is."
			or "Nothing to reset: this buff is at its starting values.",
		onClick = function()
			if SP.ResetHealingBuff then SP:ResetHealingBuff(k) end
			Row:Changed(false)
		end }
	return r
end

-- the line beside the icons: how each buff is set up, in its menu's words
local NAME_COLOR = "|cffE6EAF0"   -- Core's text (the rest is the row's dim text)
local function Summary()
	local lines = {}
	for _, b in ipairs(BUFFS) do
		local k = b.key
		local what
		if not Shown(k) then
			what = "hidden"
		else
			local parts = { (SPOT_NAME[Val(k, "point")] or "Top Right"):lower(), "size " .. Num(Val(k, "size") or 14) }
			local sweep, left = Val(k, "sweep") ~= false, Val(k, "timeText") ~= false
			if sweep and left then parts[#parts + 1] = "sweep + time left"
			elseif sweep then parts[#parts + 1] = "sweep"
			elseif left then parts[#parts + 1] = "time left" end
			what = table.concat(parts, ", ")
		end
		if not Known(b) then what = what .. "  (not learned yet)" end
		lines[#lines + 1] = NAME_COLOR .. b.name .. ":|r  " .. what
	end
	return table.concat(lines, "\n")
end

-- ---------------------------------------------------------------------------
-- The row
-- ---------------------------------------------------------------------------
Row = ns.IconRow.New({
	caption = CAPTION,
	hint = "Click: show or hide it\nRight-click: its settings",
	list = function(out)
		for _, b in ipairs(BUFFS) do out[#out + 1] = { key = b.key, name = b.name } end
	end,
	textures = function(item, out)
		out[1] = BY_KEY[item.key].icon
		return 1
	end,
	shown = function(item) return Shown(item.key) end,
	learned = function(item) return Known(BY_KEY[item.key]) end,
	hasOwn = function(item) return SP.HealingOwnChanged and SP:HealingOwnChanged(item.key) and true or false end,
	tooltip = function(item)
		local b = BY_KEY[item.key]
		local lines = {}
		if not Known(b) then
			lines[#lines + 1] = (b.key == "ancestral") and "You haven't learned Ancestral Healing yet (a talent). You can still set it up: it shows once you learn it."
				or "You haven't learned Riptide yet. You can still set it up: it shows once you learn it."
		end
		lines[#lines + 1] = (b.key == "ancestral")
			and "Ancestral Fortitude, the armor your heals' critical hits give for 15 seconds, on each player who has it."
			or "Your Riptide on each player who has it."
		lines[#lines + 1] = Shown(b.key) and "It shows on the party and raid frames." or "Hidden: a click brings it back, with all its settings."
		if SP.HealingOwnChanged and SP:HealingOwnChanged(b.key) then
			lines[#lines + 1] = "It has settings changed from its starting values (Reset This Icon in its menu clears them)."
		end
		return table.concat(lines, "\n\n")
	end,
	toggle = function(item)
		if HasAPI() then SP:SetHealingOpt(item.key, "on", not Shown(item.key)) end
	end,
	menu = MenuItems,
	beside = Summary,
})
ns.CustomRows.healingIcons = Row
SP.HealingIconsRow = Row   -- (the sp-ci tests open a buff's menu through it)

-- Reset This Page (the window's Reset Page Settings): every buff's settings back to their starting values, and both
-- shown again
function SP.HealingTrackerResetPage(sp)
	if not HasAPI() then return end
	for _, b in ipairs(BUFFS) do
		if sp.ResetHealingBuff then sp:ResetHealingBuff(b.key) end
		if not Shown(b.key) then sp:SetHealingOpt(b.key, "on", true) end
	end
end
