-- ShamanPower_Config :: ReadyIcons
-- Ready Reminders' settings page (D40, 2026-10-02): the Spells row and, for players
-- updating, the "settings moved" notice. The Spells row shows every Ready Reminder
-- spell this game version has, learned or not (not learned: dark), in the list's
-- order, as 36 px spell icons on thin plates. A hidden one is gray and dim; a small
-- accentHi corner marks an icon with settings of its own. Left-click: show or hide
-- it. Right-click: EVERY setting of that spell, in ns.ContextMenu, in the order every
-- icon menu shares (3.0.9, G's menu review): the icon itself (Hide / Show), when it
-- shows, how it looks (Appearance, While On Cooldown, its buff), what it does at its
-- moments (When Ready, When The Cooldown Resets, Out of Range, Sound), where it sits
-- (On Row), Copy / Paste / Reset, then its tests; sliders in the rows (D41 A), each
-- group ending in Copy <Group> To All Icons. An icon that
-- never set a value uses the saved default (the old page's value), so nothing on
-- screen changed on the update; Reset This Icon goes back to those.
--
-- SP:ReadyReminderOpenIconMenu(key): the settings window on the Ready Reminders
-- page, with that icon's menu open once the row is drawn (right-click an icon on
-- screen, or a Ready Reminder box in Unlock UI). The menu hangs from the icon, so
-- it moves with the window.
local _, ns = ...
local Core = ns.Core
local SP = ShamanPower
if not (Core and SP and ns.IconRow) then return end

local floor, max, ceil = math.floor, math.max, math.ceil

local ICON         = 36    -- the spell icon
local PLATE        = 40    -- its plate, 2 px round it
local PITCH        = 44    -- plate to plate: 4 px apart
local PAD_X        = 12    -- the settings rows' inner padding (plus a card's inset: Widgets.CARD_INSET)
local PAD_TOP      = 10
local CAPTION_GAP  = 10
local PAD_BOTTOM   = 12
local ROW_GAP      = 6     -- the settings rows' gap (Widgets.ROW_GAP)
local CORNER       = 11
local HIDDEN_SHADE = 0.5   -- a hidden icon: gray and half as bright
-- (the words that say what to do in the settings' blue, so a player sees them first)
local CAPTION = "|cff3FA9F5CLICK|r a spell to show or hide it. |cff3FA9F5RIGHT-CLICK|r it for its settings. |cff3FA9F5Dark|r spells aren't learned yet."
local NOT_LEARNED_SHADE = 0.3   -- a spell not learned yet: gray and dark

local Row        -- the Spells row: the shared icon row (ns.IconRow), made at the end of this file
local Unplaced   -- Rows placement: the spells on no row, a row of their own under it

-- 3.0.9 picture hints (IconScreen.lua, sheet A30): `pic` on a menu row or a choice says what the
-- icon looks like with it, `words` is a card's one line; the right-click menu ignores both. The
-- kinds that never change are these shared tables; one with the icon's own color or picture is
-- built with the menu (Pic.Color, Pic.Glow, Pic.Icon, Pic.Spell, Pic.With: below Opt).
local Pic = {
	NONE = { kind = "none" }, PLAIN = { kind = "plain" }, HIDDEN = { kind = "hidden" }, GRAY = { kind = "gray" },
	FADED = { kind = "faded" }, SOUND = { kind = "sound" }, FLASH = { kind = "flash" }, PULSE = { kind = "pulse" },
	SIZE = { kind = "size" }, OPACITY = { kind = "opacity" }, EDGE = { kind = "edge" }, BAR = { kind = "bar" },
	TINT = { kind = "tint" },
	SWEEP = { kind = "sweep", frac = 0.6, text = "4" },         -- the cooldown sweep with its countdown
	SWEEP_ONLY = { kind = "sweep", frac = 0.75, text = "9" },   -- (another moment of it, beside SWEEP)
	NUMBER = { kind = "number", text = "4" },                    -- the countdown text
	RESET_WORD = { kind = "word", text = "RESET" },
}

-- ---------------------------------------------------------------------------
-- Labels
-- ---------------------------------------------------------------------------
local SHOW_CHOICES = {
	{ "ready", "Only When Ready" }, { "cooldown", "Only While On Cooldown" },
	{ "always_bright", "Always" }, { "always", "Always (Dim on Cooldown)" },
}
local EFFECT_CHOICES = { { "glow", "Glow" }, { "pulse", "Pulse" }, { "both", "Glow + Pulse" }, { "none", "None" } }
-- (3.0.9.2, A55) Maelstrom Weapon: its stacks' look, when it shows, its time left
local STACK_LOOKS = { { "number", "Icon + Stack Number" }, { "bar", "Charge Bar" }, { "baronly", "Charge Bar Only" },
	{ "wings", "Wings" }, { "fill", "Fill" }, { "iconfill", "Fill The Icon" }, { "storm", "Storm Glow" } }
local STACK_SHOWS = { { "stacks", "While You Have Stacks" }, { "five", "Only At 5 Stacks" }, { "always", "Always (0 Too, Dimmed)" } }
local STACK_LEFTS = { { "off", "Off" }, { "number", "Number" }, { "drain", "Drain" } }
local SWEEP_CHOICES = {
	{ "radial", "Clock Sweep", nil, Pic.SWEEP },
	{ "vertical", "Color Fills In", nil, Pic.NONE },   -- (the sweep picture is the radial one)
	{ "none", "None", nil, Pic.PLAIN },
}
local SWEEP_DIRECTION_CHOICES = { { "top", "From The Top" }, { "bottom", "From The Bottom" } }
local BAR_CHOICES = { { "none", "None" }, { "below", "Below The Icon" }, { "above", "Above The Icon" } }
local TEXTPOS_CHOICES = { { "center", "Center" }, { "top", "Top" }, { "bottom", "Bottom" }, { "below", "Below The Icon" }, { "above", "Above The Icon" } }
local RANGE_CHOICES = { { "red", "Red Tint" }, { "gray", "Gray" }, { "dim", "Dim" } }
local ANIM_CHOICES = { { "grow", "Grow and Fade" }, { "pop", "Pop" }, { "fade", "Fade Only" } }
local SHOCK_CHOICES = { { "cycle", "Switch Between Shocks" }, { "split", "All Three in One Icon" }, { "one", "One Shock" } }
local PICK_CHOICES = {
	{ "earthshock", SPCompat.SpellLabel(8042, "Earth Shock") },
	{ "flameshock", SPCompat.SpellLabel(8050, "Flame Shock") },
	{ "frostshock", SPCompat.SpellLabel(8056, "Frost Shock") },
}

local function OnOff(v) if v then return "On" end return "Off" end
local function LabelOf(list, v)
	for _, c in ipairs(list) do if c[1] == v then return c[2] end end
	return list[1][2]
end
local function Color3(c, dr, dg, db)
	if type(c) == "table" then return c.r or c[1] or dr, c.g or c[2] or dg, c.b or c[3] or db end
	return dr, dg, db
end
local function Secs(v, zero)
	v = tonumber(v) or 0
	if v <= 0 and zero then return zero end
	if v == math.floor(v) then return string.format("%d sec", v) end
	return string.format("%.1f sec", v)
end

-- what the icon uses now (its own value, else the saved default)
local function Opt(key, opt) return SP:ReadyReminderIconOpt(key, opt) end
-- (3.0.9.2) Maelstrom Weapon in Wings or Fill: three icons wide, on a spot of its own
local function Wide(entry) return entry ~= nil and entry.stacks ~= nil and SP.ReadyStacks ~= nil and SP.ReadyStacks.Wide(entry) end

-- ---------------------------------------------------------------------------
-- The icons
-- ---------------------------------------------------------------------------
local texOut = {}   -- reused: the textures of the icon being painted

-- (3.0.9) the picture hints that carry the icon's own values
-- a color as the swatch reads it: plain numbers from the icon's setting, nothing allocated
function Pic.Color(key, opt, dr, dg, db)
	return function() return Color3(Opt(key, opt), dr, dg, db) end
end
-- the icon's own glow shape (an icon that never picked one shows Appearance > Themes' Glow Shape)
function Pic.Shape(key) return Opt(key, "glowShape") or (SP.opt and SP.opt.glowShape) or "default" end
-- the icon's glow: its own shape (or the one given) in its Glow Color; pulse: with its pulse (Glow + Pulse)
function Pic.Glow(key, shape, pulse)
	local p = { kind = "glow", shape = shape or Pic.Shape(key), color = Pic.Color(key, "glowColor", 0.3, 0.8, 1.0) }
	if pulse then p.pulse = true end
	return p
end
-- the icon when ready, as its Ready Effect draws it (a glow, a pulse, both, or nothing)
function Pic.Ready(key)
	local fx = Opt(key, "readyEffect") or "glow"
	if fx == "none" then return Pic.PLAIN end
	if fx == "pulse" then return Pic.PULSE end
	return Pic.Glow(key, nil, fx == "both")
end
-- a spell's icon by its Ready Reminder key (this client's spell ID, as the Spells row draws it)
function Pic.Icon(key)
	local n = SP:ReadyReminderIconTextures(key, texOut)
	if n > 0 then return texOut[1] end
	return nil
end
-- a spell's own icon by ID (the buff's picture, the one the engine puts on its button; SPCompat
-- gives WoW: Forever this global)
function Pic.Spell(id)
	if not id then return nil end
	return GetSpellTexture(id)
end
-- the list with each value's picture in its 4th field (ChoiceRow copies it to the choice)
function Pic.With(list, pics)
	local out = {}
	for i, c in ipairs(list) do out[i] = { c[1], c[2], c[3], pics[c[1]] } end
	return out
end

local function TooltipBody(entry)
	if not SP.ReadyReminderKnown(entry) then return "You haven't learned this yet. You can still set it up." end
	if SP:ReadyReminderHasOwn(entry.key) then return "It has settings of its own (right-click to see them)." end
	return "It uses the default settings (right-click to change them)."
end

-- every spell this game version has, in the page's order (learned or not)
local ordered = {}
local function Ordered()
	if SP.ReadyOrderedSpells then return SP:ReadyOrderedSpells(ordered) end
	wipe(ordered)
	for _, entry in ipairs(SP.ReadyReminderSpells) do ordered[#ordered + 1] = entry end
	return ordered
end
local function Known(out)
	wipe(out)
	for _, entry in ipairs(Ordered()) do
		if SP.ReadyReminderUsable(entry) then out[#out + 1] = entry end
	end
	return out
end

-- ---------------------------------------------------------------------------
-- The menu (D40): every setting of the spell, grouped
-- ---------------------------------------------------------------------------
-- a choice: saved as the icon's own, the menu stays open and is drawn again
local function Set(key, opt, value)
	SP:ReadyReminderSetIconOpt(key, opt, value)
	Row:Changed(true)
	return true
end
-- a slider's value: only saved (the icons and the open menu are drawn again by the
-- settings watcher, the preview follows); never a redraw of the page under a drag
local function SliderSet(key, opt, value)
	SP:ReadyReminderSetIconOpt(key, opt, value)
	Row:Repaint()
	local cfg = _G.ShamanPowerConfig
	if cfg and cfg.PreviewChanged then cfg:PreviewChanged() end
end

local function FirstTexture(entry)
	local n = SP:ReadyReminderIconTextures(entry.key, texOut)
	return n > 0 and texOut[1] or nil
end

-- 3.0.9: `pic` is a row's picture hint for the icon's own screen (IconScreen.lua), as on
-- ns.IconRow.Menu: a choice's is its list entry's 4th field, the row's the fallback; on an
-- On / Off row it is the ON picture, on a slider or a color row the live one; a group's
-- `words` is its card's line. The menus ignore them.
local function ChoiceRow(key, text, opt, list, fallback, pic)
	return {
		text = text, pic = pic,
		value = function() return LabelOf(list, Opt(key, opt) or fallback), false end,
		sub = function()
			local cur = Opt(key, opt) or fallback
			local items = {}
			for _, c in ipairs(list) do
				local v = c[1]
				items[#items + 1] = { text = c[2], selected = cur == v, pic = c[4],
					onClick = function() return Set(key, opt, v) end }
			end
			return items
		end,
	}
end
-- on / off: onByDefault = what an unset value means (Countdown Text and Gray Out are on)
local function OnOffRow(key, text, opt, onByDefault, pic)
	local function cur()
		local v = Opt(key, opt)
		if onByDefault then return v ~= false end
		return v == true
	end
	return {
		text = text, pic = pic,
		value = function() return OnOff(cur()), false end,
		sub = function()
			local on = cur()
			return {
				{ text = "On", selected = on, onClick = function() return Set(key, opt, true) end },
				{ text = "Off", selected = not on, onClick = function() return Set(key, opt, false) end },
			}
		end,
	}
end
local function SliderRow(key, text, opt, lo, hi, step, fallback, format, isPercent, pic)
	return {
		text = text, pic = pic,
		slider = {
			min = lo, max = hi, step = step, isPercent = isPercent,
			get = function() return tonumber(Opt(key, opt)) or fallback end,
			set = function(v) SliderSet(key, opt, v) end,
			format = format,
		},
	}
end
-- (a click on the row opens the picker: no "Pick Color..." level in between)
local function ColorRow(key, entry, text, opt, dr, dg, db, pic)
	return {
		text = text, pic = pic,
		swatch = { Color3(Opt(key, opt), dr, dg, db) },
		onClick = function()
			if not SP.OpenColorPicker then return false end
			local before = SP:ReadyReminderOwnOpt(key, opt)
			local r, g, b = Color3(Opt(key, opt), dr, dg, db)
			SP:OpenColorPicker({
				r = r, g = g, b = b, hasAlpha = false, title = entry.name .. " " .. text,
				onChange = function(nr, ng, nb)
					SP:ReadyReminderSetIconOpt(key, opt, { r = nr, g = ng, b = nb })
					Row:Changed(false)
				end,
				-- Cancel: exactly as it was
				onCancel = function()
					SP:ReadyReminderSetIconOpt(key, opt, before)
					Row:Changed(false)
				end,
			})
			return false   -- the menu closes; the color picker is open
		end,
	}
end
-- a setting shared beyond this icon (it is also on Appearance > Themes): `scope` says how far it
-- reaches, in the label
local function SharedRow(text, values, getter, setter, scope)
	return {
		text = text .. " (" .. (scope or "All Icons") .. ")",
		value = function()
			local map = values()
			return (map and map[getter()]) or tostring(getter() or ""), false
		end,
		sub = function()
			local map, order = values()
			local cur = getter()
			local items = {}
			for _, k in ipairs(order or {}) do
				items[#items + 1] = { text = map[k], selected = cur == k, onClick = function()
					setter(k)
					if SP.UpdateAllReadyReminderAppearance then SP:UpdateAllReadyReminderAppearance() end
					Row:Changed(true)
					return true
				end }
			end
			return items
		end,
	}
end
-- the last line of a group: these settings of this spell on every other spell
local COPY_NAMES = { ["When Ready"] = "Ready Effects", ["At 5 Stacks"] = "Ready Effects", ["While Holding"] = "Weapon Effects", ["When It's Gone"] = "Missing Imbue Effects",
	["While On Cooldown"] = "Cooldown Appearance", ["When Out of Mana"] = "Out of Mana Effects" }
local function CopyGroupRow(key, group, opts)
	return { text = "Copy " .. (COPY_NAMES[group] or group) .. " To All Icons", onClick = function()
		SP:ReadyReminderCopyGroup(key, opts)
		Row:Changed(true)
		return true
	end }
end
local function Group(text, rows, words)
	return { text = text, words = words, sub = function() return rows() end }
end
-- (3.0.9.2) a group's settings onto one icon you pick (Copy <Group> To...), and onto the other
-- icons on this icon's row (Rows placement: Copy <Group> To This Row), as Copy Settings To... and
-- Copy Settings To This Row do with all of an icon's settings
local function CopyGroupPickRows(key, group, opts)
	local name = COPY_NAMES[group] or group
	local items, rows = {}, {}
	for _, e in ipairs(Ordered()) do
		if e.key ~= key and SP.ReadyReminderUsable(e) then
			items[#items + 1] = { text = e.name, icon = FirstTexture(e),
				onClick = function() SP:ReadyReminderCopyGroup(key, opts, { e.key }); Row:Changed(true) end }
		end
	end
	rows[#rows + 1] = { text = "Copy " .. name .. " To...", disabled = #items == 0, subMaxHeight = 420,
		words = "this icon's " .. name:lower() .. " on an icon you pick", sub = function() return items end }
	if SP.ReadyRowsOn and SP:ReadyRowsOn() then
		local ri = SP:ReadyRowOf(key)
		local r = ri and SP:ReadyRows()[ri]
		local rowName = r and (r.name or ("Row " .. ri)) or nil
		local mates = {}
		if r then
			local usable = {}
			for _, e in ipairs(Ordered()) do if SP.ReadyReminderUsable(e) then usable[e.key] = true end end
			for _, k in ipairs(r.spells) do if k ~= key and usable[k] then mates[#mates + 1] = k end end
		end
		rows[#rows + 1] = { text = "Copy " .. name .. " To This Row", disabled = #mates == 0,
			value = function() return rowName or "Not On A Row", false end,
			tip = rowName and ("Puts this icon's " .. name:lower() .. " on every other icon on " .. rowName .. ".")
				or "This icon is on no row. Put it on one (On Row, in this icon's menu) and this copies to that row.",
			onClick = function() SP:ReadyReminderCopyGroup(key, opts, mates); Row:Changed(true); return true end }
	end
	return rows
end

local LOOK_KEYS = { "iconSize", "opacity", "iconShape", "hideBackground", "hideBorder", "borderColor", "showNames",
	"glowColor", "glowShape", "glowThick" }
local READY_KEYS = { "readyEffect", "glowCombatOnly", "wsGlow" }
local COOL_KEYS = { "dimOpacity", "desaturate", "sweepStyle", "sweepDirection", "barStyle", "barHeight", "barColor", "showCountdown",
	"textPosition", "textSize", "countdownUnder" }
local RANGE_KEYS = { "outOfRange", "rangeLook", "rangeColor" }
local SOUND_KEYS = { "soundOnReady", "soundName", "soundVolume" }
local FADE_KEYS = { "fadeInsteadOfHide", "fadeOpacity" }

local function AppearanceRows(key, entry)
	local t = {
		SliderRow(key, "Size", "iconSize", 24, 96, 2, 48, nil, nil, Pic.SIZE),
		SliderRow(key, "Opacity", "opacity", 0.2, 1, 0.05, 1, nil, true, Pic.OPACITY),
	}
	-- (3.0.9.2) Wings and Fill: Blizzard's picture alone, no icon, backing or border to set
	local wide = Wide(entry)
	if wide then
		local barOnly = Opt(key, "stackLook") == "baronly"
		t[#t + 1] = { text = barOnly and "Charge Bar Only has no icon, background or border" or "Wings and Fill have no icon, background or border", disabled = true,
			tip = barOnly and "This look is the five-part bar alone. Size sets its width; its height is under Stacks > Bar Height."
				or "These looks are Blizzard's own Maelstrom picture alone. Size and Opacity still apply; pick another Look for the icon's settings." }
	end
	-- Icon Shape (3.0.9): this icon's own (a circle Earth Shock beside a square Stormstrike), else
	-- the shape every icon shares (Appearance > Themes); the first choice puts it back on the shared one
	if SP.IconShapeValues and SP.IconShapeOf and not wide then
		local function plain(label) return (label or ""):gsub(" %(default%)$", "") end
		t[#t + 1] = {
			text = "Icon Shape", pic = Pic.NONE,
			value = function()
				local map = SP:IconShapeValues()
				local own = SP:ReadyReminderOwnOpt(key, "iconShape")
				if own then return plain(map[own]) or tostring(own), true end
				return plain(map[SP:IconShapeOf("ready") or "default"]) .. " (all icons)", false
			end,
			tip = "This icon's shape: Square, Flat (the picture's own border removed), Rounded or Circle. Use Shared Shape: the shape every icon shares, set on Appearance > Themes.",
			sub = function()
				local map, order = SP:IconShapeValues()
				local own = SP:ReadyReminderOwnOpt(key, "iconShape")
				local shared = SP:IconShapeOf("ready") or "default"
				local list = {
					{ text = "Use Shared Shape  (" .. plain(map[shared]) .. ")", selected = own == nil,
					  onClick = function() return Set(key, "iconShape", nil) end },
					{ separator = true },
				}
				for _, k in ipairs(order or {}) do
					list[#list + 1] = { text = plain(map[k]), selected = own == k, onClick = function() return Set(key, "iconShape", k) end }
				end
				return list
			end,
		}
	end
	if not wide then t[#t + 1] = {
		text = "Background",
		value = function() if Opt(key, "hideBackground") then return "Hide", false end return "Show", false end,
		sub = function()
			local hidden = Opt(key, "hideBackground") and true or false
			return {
				{ text = "Show", selected = not hidden, pic = Pic.PLAIN,
				  onClick = function() return Set(key, "hideBackground", false) end },
				{ text = "Hide Both", selected = hidden, pic = Pic.NONE,
				  onClick = function() return Set(key, "hideBackground", true) end },
			}
		end,
	} end
	local bg = not Opt(key, "hideBackground") and not wide
	if bg then
		t[#t + 1] = {
			text = "Border",
			value = function() if Opt(key, "hideBorder") then return "Hide", false end return "Show", false end,
			sub = function()
				local hidden = Opt(key, "hideBorder") and true or false
				return {
					{ text = "Show", selected = not hidden,
					  pic = { kind = "edge", color = Pic.Color(key, "borderColor", 0.2, 0.7, 1.0) },
					  onClick = function() return Set(key, "hideBorder", false) end },
					{ text = "Hide", selected = hidden, pic = Pic.NONE, onClick = function() return Set(key, "hideBorder", true) end },
				}
			end,
		}
	end
	if bg and not Opt(key, "hideBorder") then
		local shape = SP.IconShapeOf and SP:IconShapeOf("ready")
		if (shape == "rounded" or shape == "circle") and SP.SetIconBordersSquare then
			t[#t + 1] = SharedRow("Keep Borders Square", function() return { [true] = "On", [false] = "Off" }, { true, false } end,
				function() return SP.opt and SP.opt.iconBordersSquare == true end, function(v) SP:SetIconBordersSquare(v) end, "Every Bar")
			t[#t].pic = Pic.NONE   -- (square or round corners: no picture kind draws them)
			t[#t].tip = "Keep borders square around rounded or circular icons. This changes all bars and Ready Reminders. The same setting is on General → Themes."
		end
		t[#t + 1] = ColorRow(key, entry, "Border Color", "borderColor", 0.2, 0.7, 1.0, Pic.EDGE)
	end
	-- (the name under the icon, which no picture kind draws; a Weapon Set's is its set's word)
	if entry.weaponSet then
		local w = OnOffRow(key, "Show Weapon Set Name", "wsWord", true, { kind = "word", text = "SHIELD" })
		w.tip = "Shield, Two-Hander, Two Weapons or One-Hander under the icon."
		t[#t + 1] = w
	else
		t[#t + 1] = OnOffRow(key, "Show Name", "showNames", nil, Pic.NONE)
	end
	-- the glow's look (its moment is under When Ready): shape, color, thickness; an icon that
	-- never picked a shape shows Appearance > Themes' Glow Shape
	t[#t + 1] = { separator = true }
	local fx = Opt(key, "readyEffect") or "glow"
	if fx == "glow" or fx == "both" then
		if SP.GlowShapeValues and not wide then   -- (Wings / Fill: the emblem itself glows)
			local map, order = SP:GlowShapeValues()
			local choices = {}
			for _, k in ipairs(order or {}) do choices[#choices + 1] = { k, map[k], nil, Pic.Glow(key, k) } end
			local shared = SP.opt and SP.opt.glowShape or "default"
			t[#t + 1] = ChoiceRow(key, "Glow Shape", "glowShape", choices, shared)
		end
		t[#t + 1] = ColorRow(key, entry, "Glow Color", "glowColor", 0.3, 0.8, 1.0, { kind = "glow", shape = Pic.Shape(key) })
		if SP.GlowShapeValues and not wide and (Opt(key, "glowShape") or (SP.opt and SP.opt.glowShape) or "default") == "proc" and SP.ProcGlowOut then
			local row = SliderRow(key, "Glow Thickness", "glowThick", 0, 0.6, 0.01, SP.PROC_GLOW_OUT or 0.2, nil, true,
				{ kind = "thick", shape = "proc", color = Pic.Color(key, "glowColor", 0.3, 0.8, 1.0) })
			row.tip = "How thick the Proc Glow ring is. It grows outward from the icon's edge."
			t[#t + 1] = row
		end
	else
		local moment = entry.weaponSet and "While Holding" or entry.imbue and "When It's Gone" or entry.stacks and "At 5 Stacks" or "When Ready"
		t[#t + 1] = { text = "No glow yet: pick one under " .. moment .. " > Effect", disabled = true,
			tip = "This icon's effect has no glow, so there is no glow look to set. Pick Glow or Glow + Pulse under " .. moment .. " > Effect." }
	end
	t[#t + 1] = { separator = true }
	t[#t + 1] = CopyGroupRow(key, "Appearance", LOOK_KEYS)
	for _, r in ipairs(CopyGroupPickRows(key, "Appearance", LOOK_KEYS)) do t[#t + 1] = r end
	return t
end

local HOLD_CHOICES = {
	{ "never", "No Glow", nil, Pic.PLAIN },
	{ "shield", "A Shield", nil, { kind = "word", text = "SHIELD" } },
	{ "2h", "Two-Handed Weapon", nil, { kind = "word", text = "2-HAND" } },
	{ "dual", "Two Weapons", nil, { kind = "word", text = "DUAL" } },
	{ "one", "One-Handed Weapon Only", nil, { kind = "word", text = "1-HAND" } },
}
local function ReadyRows(key, entry, groupName)
	local fx = Opt(key, "readyEffect") or "glow"
	-- (Pulse: the icon's own grow-and-shrink, caught mid-grow)
	local t = { ChoiceRow(key, "Effect", "readyEffect", Pic.With(EFFECT_CHOICES,
		{ glow = Pic.Glow(key), pulse = Pic.PULSE, both = Pic.Glow(key, nil, true), none = Pic.PLAIN }), "glow") }
	t[1].tip = "What the icon does at that moment: a glow (its shape and color are under Appearance), a pulse, both, or nothing."
	if entry.stacks then
		t[1].tip = "What it does at 5 stacks, while they last: a glow, a pulse, both, or nothing. On Wings and Fill the emblem itself glows or pulses."
	end
	if entry.weaponSet then   -- (A28) the set whose hold plays the effect
		local g = ChoiceRow(key, "Glow While Holding", "wsGlow", HOLD_CHOICES, "never")
		g.tip = "Use this effect while these weapons are equipped."
		t[#t + 1] = g
	end
	if fx == "glow" or fx == "both" then
		local co = OnOffRow(key, "Glow Only In Combat", "glowCombatOnly", nil, Pic.Glow(key))
		co.tip = "Out of a fight the icon shows with no glow; the glow comes in a fight."
		t[#t + 1] = co
	end
	t[#t + 1] = { separator = true }
	t[#t + 1] = CopyGroupRow(key, groupName or "When Ready", READY_KEYS)
	return t
end

-- A25: When The Cooldown Resets (Stormstrike on WoW: Forever, where a tank's dodge or parry resets
-- it): the icon's burst / word, the Ready Flash saying so, its own sound; each its own switch
local RESET_VISUALS = { { "none", "None" }, { "burst", "Glow Burst" }, { "word", "\"RESET\" Text" }, { "both", "Glow Burst and \"RESET\" Text" } }
local function ResetRows(key, entry)
	local vis = Opt(key, "resetVisual") or "none"
	local t = {}
	-- (Glow Burst + Word: one kind per picture, and the word alone is "RESET" Text's)
	local v = ChoiceRow(key, "Icon Effect", "resetVisual", Pic.With(RESET_VISUALS, {
		none = Pic.PLAIN, burst = { kind = "glow", shape = "proc", color = Pic.Color(key, "resetColor", 1, 0.82, 0) },
		word = Pic.RESET_WORD, both = Pic.NONE }), "none")
	v.tip = "What the icon does the moment its cooldown is reset (a dodge or parry as a tank). The burst is the Proc Glow ring, the word is RESET over the icon."
	t[#t + 1] = v
	if vis == "burst" or vis == "both" then
		t[#t + 1] = ColorRow(key, entry, "Burst Color", "resetColor", 1, 0.82, 0, { kind = "glow", shape = "proc" })
	end
	if vis ~= "none" then
		local l = SliderRow(key, "Show for (Seconds)", "resetLength", 0.5, 3, 0.1, 1.5, function(x) return Secs(x) end)
		l.tip = "How long the burst or the word stays before the ready look takes over."
		t[#t + 1] = l
	end
	local fl = OnOffRow(key, "Ready Flash", "resetFlash", nil, Pic.FLASH)
	fl.tip = "Your Ready Flash, in place of the plain ready one."
	t[#t + 1] = fl
	if Opt(key, "resetFlash") then
		local fw = OnOffRow(key, "Show Reset Message", "resetFlashWord", true, Pic.FLASH)
		fw.tip = "The flash says " .. entry.name .. " reset! under the icon. Off: just the icon."
		t[#t + 1] = fw
	end
	local so = OnOffRow(key, "Play Sound", "resetSound", nil, Pic.SOUND)
	so.tip = "Its own sound; the Ready sound stays quiet for a reset, so you never hear two."
	t[#t + 1] = so
	if Opt(key, "resetSound") then
		t[#t + 1] = {
			text = "Sound", subMaxHeight = 300, pic = Pic.SOUND,
			value = function() return tostring(Opt(key, "resetSoundName") or "ShamanPower: Ready Ping"), false end,
			sub = function()
				local lsm = LibStub and LibStub("LibSharedMedia-3.0", true)
				local names = lsm and lsm:List("sound")
				local cur = Opt(key, "resetSoundName") or "ShamanPower: Ready Ping"
				local items = {}
				for _, name in ipairs(type(names) == "table" and names or {}) do
					items[#items + 1] = { text = name, selected = name == cur,
						preview = function() SP:ReadyReminderPlaySound(name, key) end,
						onClick = function() return Set(key, "resetSoundName", name) end }
				end
				return items
			end,
		}
		t[#t + 1] = SliderRow(key, "Volume", "resetVolume", 0, 100, 1, 100, function(x) return string.format("%d%%", x or 0) end)
	end
	return t
end
-- (its Test sits in the menu's test section, at the bottom)
local function ResetConfigured(key)
	return (Opt(key, "resetVisual") or "none") ~= "none" or Opt(key, "resetFlash") or Opt(key, "resetSound")
end

-- A28: Weapon Set: the set whose hold plays the effect (HOLD_CHOICES, under While Holding), and
-- the swap switches, a group of their own (the word under the icon is Appearance's)
-- (the pictures: the word the icon shows for that set; four glows alike would not say which)
local function SwapRows(key, entry)
	local t = {}
	local so = OnOffRow(key, "Play Sound", "wsSound", nil, Pic.SOUND)
	so.tip = "The icon's Sound (its group below) plays the moment the set changes."
	t[#t + 1] = so
	local fl = OnOffRow(key, "Ready Flash", "wsFlash", nil, Pic.FLASH)
	fl.tip = "Your Ready Flash shows the new set the moment it changes."
	t[#t + 1] = fl
	return t
end

local function CoolRows(key, entry)
	local t = {
		SliderRow(key, "Opacity", "dimOpacity", 0.1, 1, 0.05, 0.35, nil, true, Pic.OPACITY),
		OnOffRow(key, "Gray Out The Icon", "desaturate", true, Pic.GRAY),
		ChoiceRow(key, "Sweep", "sweepStyle", SWEEP_CHOICES, "radial"),
	}
	if Opt(key, "sweepStyle") == "vertical" then
		t[#t + 1] = ChoiceRow(key, "Sweep Direction", "sweepDirection", SWEEP_DIRECTION_CHOICES, "bottom", Pic.NONE)
	end
	-- (Above The Icon: the bar picture only draws under the icon)
	t[#t + 1] = ChoiceRow(key, "Progress Bar", "barStyle", Pic.With(BAR_CHOICES, { none = Pic.PLAIN,
		below = { kind = "bar", frac = 0.6, color = Pic.Color(key, "barColor", 0.3, 0.8, 1.0) }, above = Pic.NONE }), "none")
	if (Opt(key, "barStyle") or "none") ~= "none" then
		t[#t + 1] = SliderRow(key, "Bar Height", "barHeight", 2, 12, 1, 4)
		t[#t + 1] = ColorRow(key, entry, "Bar Color", "barColor", 0.3, 0.8, 1.0, Pic.BAR)
		if SP.opt and SP.opt.barGradient and SP.GradientDirectionValues and SP.BarGradientDirection and SP.SetBarGradientDirection then
			t[#t + 1] = SharedRow("Bar Gradient", function() return SP:GradientDirectionValues("barGradient") end,
				function() return SP:BarGradientDirection("other") end, function(v) SP:SetBarGradientDirection("other", v) end, "Shared")
			t[#t].pic = Pic.NONE
			t[#t].tip = "One setting for these bars and every bar but the totem bar's, with Appearance > Themes."
		end
	end
	t[#t + 1] = OnOffRow(key, "Show Countdown", "showCountdown", true, Pic.NUMBER)
	if Opt(key, "showCountdown") ~= false then
		t[#t + 1] = ChoiceRow(key, "Countdown Position", "textPosition", TEXTPOS_CHOICES, "center", Pic.NONE)
		t[#t + 1] = SliderRow(key, "Countdown Text Size", "textSize", 0, 40, 1, 0, function(v) if (v or 0) <= 0 then return "Auto" end return tostring(v) end)
		t[#t + 1] = SliderRow(key, "Show Countdown Below", "countdownUnder", 0, 60, 1, 0, function(v) return Secs(v, "Always") end)
	end
	t[#t + 1] = { separator = true }
	t[#t + 1] = CopyGroupRow(key, "While On Cooldown", COOL_KEYS)
	return t
end

-- (3.0.9.2) When Out of Mana: while you can't afford the spell, the icon's tint (ShamanPower's
-- out-of-mana blue to start) and an effect of its own (a glow in its own shape and color, a pulse)
local OOM_KEYS = { "oomTint", "oomColor", "oomEffect", "oomGlowShape", "oomGlowColor" }
local function OomRows(key, entry)
	local tintPic = { kind = "tint", color = Pic.Color(key, "oomColor", 0.45, 0.45, 1.0) }
	local t = {}
	local tint = OnOffRow(key, "Tint The Icon", "oomTint", nil, tintPic)
	tint.tip = "While you don't have the mana for it, the icon takes the color below. While your target is out of range, the Out of Range look shows instead."
	t[#t + 1] = tint
	if Opt(key, "oomTint") then
		t[#t + 1] = ColorRow(key, entry, "Out of Mana Color", "oomColor", 0.45, 0.45, 1.0, Pic.TINT)
	end
	local glowPic = { kind = "glow", shape = Opt(key, "oomGlowShape") or Pic.Shape(key), color = Pic.Color(key, "oomGlowColor", 0.45, 0.45, 1.0) }
	local fx = Opt(key, "oomEffect") or "none"
	local e = ChoiceRow(key, "Effect", "oomEffect", Pic.With(EFFECT_CHOICES, { glow = glowPic, pulse = Pic.PULSE,
		both = { kind = "glow", shape = glowPic.shape, color = glowPic.color, pulse = true }, none = Pic.PLAIN }), "none")
	e.tip = "What the icon does while you don't have the mana for it: a glow, a pulse, both, or nothing."
	t[#t + 1] = e
	if fx == "glow" or fx == "both" then
		if SP.GlowShapeValues then
			local map, order = SP:GlowShapeValues()
			local choices = {}
			for _, k in ipairs(order or {}) do
				choices[#choices + 1] = { k, map[k], nil, { kind = "glow", shape = k, color = glowPic.color } }
			end
			local shape = ChoiceRow(key, "Glow Shape", "oomGlowShape", choices, Pic.Shape(key))
			shape.tip = "The out-of-mana glow's own shape. Until you pick one it uses this icon's Glow Shape."
			t[#t + 1] = shape
		end
		t[#t + 1] = ColorRow(key, entry, "Glow Color", "oomGlowColor", 0.45, 0.45, 1.0, glowPic)
	end
	t[#t + 1] = { separator = true }
	t[#t + 1] = CopyGroupRow(key, "When Out of Mana", OOM_KEYS)
	return t
end

local function RangeRows(key, entry)
	-- the pictures: each look; the switch shows the look the icon has
	local looks = { red = { kind = "tint", color = Pic.Color(key, "rangeColor", 0.64, 0.15, 0.15) },
		gray = Pic.GRAY, dim = Pic.FADED }
	local t = { OnOffRow(key, "Warn When Out of Range", "outOfRange", nil, looks[Opt(key, "rangeLook") or "red"] or looks.red) }
	if Opt(key, "outOfRange") then
		t[#t + 1] = ChoiceRow(key, "Warning Style", "rangeLook", Pic.With(RANGE_CHOICES, looks), "red")
		if (Opt(key, "rangeLook") or "red") == "red" then
			t[#t + 1] = ColorRow(key, entry, "Out of Range Color", "rangeColor", 0.64, 0.15, 0.15, Pic.TINT)
		end
	end
	t[#t + 1] = { separator = true }
	t[#t + 1] = CopyGroupRow(key, "Out of Range", RANGE_KEYS)
	return t
end

local function SoundRows(key, entry)
	-- Weapon Set (A28): no ready moment, so no Play Sound switch; the sound is what Sound On A Swap plays
	local ws = entry and entry.weaponSet
	local t = {}
	if not ws then t[1] = OnOffRow(key, "Play Sound", "soundOnReady", nil, Pic.SOUND) end
	if ws or Opt(key, "soundOnReady") then
		t[#t + 1] = {
			text = "Sound", subMaxHeight = 300, pic = Pic.SOUND,
			value = function() return tostring(Opt(key, "soundName") or "Raid Warning"), false end,
			sub = function()
				local lsm = LibStub and LibStub("LibSharedMedia-3.0", true)
				local names = lsm and lsm:List("sound")
				local cur = Opt(key, "soundName") or "Raid Warning"
				local items = {}
				for _, name in ipairs(type(names) == "table" and names or {}) do
					-- only the speaker button plays one; choosing or moving through the list is silent
					items[#items + 1] = { text = name, selected = name == cur,
						preview = function() SP:ReadyReminderPlaySound(name, key) end,
						onClick = function() return Set(key, "soundName", name) end }
				end
				return items
			end,
		}
		t[#t + 1] = SliderRow(key, "Volume", "soundVolume", 0, 100, 1, 100, function(v) return string.format("%d%%", v or 0) end)
	end
	t[#t + 1] = { separator = true }
	t[#t + 1] = CopyGroupRow(key, "Sound", SOUND_KEYS)
	return t
end

-- (3.0.9.2, A55) Maelstrom Weapon: the count on any look, the time left, the two colors. A row that
-- does nothing in this look stays, grayed, and says which looks it is for.
local function StackRows(key, entry)
	local look = Opt(key, "stackLook") or "number"
	local t = {}
	if look == "number" then
		t[#t + 1] = { text = "Stack Number: always on in this look", disabled = true,
			tip = "Icon + Stack Number always shows the count. Turn Stack Number on here for the other looks." }
	else
		local n = OnOffRow(key, "Stack Number", "stackNumber")
		n.tip = "The count over the look, as Icon + Stack Number shows it: white, in Color At 5 Stacks at 5."
		t[#t + 1] = n
	end
	local left = ChoiceRow(key, "Time Left", "stackLeft", look == "baronly" and { STACK_LEFTS[1], STACK_LEFTS[2] } or STACK_LEFTS, "off")
	left.tip = (look == "baronly") and "The buff's time left, as a number beside the bar."
		or "The buff's time left: a number, or Drain: the look goes gray from the top as the time runs out."
	t[#t + 1] = left
	if look == "baronly" then   -- (Charge Bar Only: its height; Size sets its width)
		local bh = SliderRow(key, "Bar Height", "stackBarHeight", 0, 40, 1, 0, function(v) if (v or 0) <= 0 then return "Auto" end return tostring(v) end)
		bh.tip = "How tall the bar is. Auto: a third of Size. Size (Appearance) sets how wide it is."
		t[#t + 1] = bh
	end
	t[#t + 1] = { separator = true }
	if look == "bar" or look == "baronly" or look == "storm" then
		local c = ColorRow(key, entry, "Stack Color", "stackColor", 0.35, 0.65, 1.0)
		c.tip = (look == "storm") and "The Storm Glow's color below 5 stacks." or "The Charge Bar's color below 5 stacks."
		t[#t + 1] = c
	else
		t[#t + 1] = { text = "Stack Color: Charge Bar and Storm Glow only", disabled = true,
			tip = "Only the Charge Bar and the Storm Glow color the stacks below 5. The other looks show the spell's own picture." }
	end
	if look == "number" or look == "bar" or look == "baronly" or Opt(key, "stackNumber") then
		local c5 = ColorRow(key, entry, "Color At 5 Stacks", "stackColor5", 1, 0.82, 0)
		c5.tip = "At 5 stacks the number turns this color" .. ((look == "bar" or look == "baronly") and ", and so does the Charge Bar." or ".")
		t[#t + 1] = c5
	else
		t[#t + 1] = { text = "Color At 5 Stacks: the number and the Charge Bar", disabled = true,
			tip = "It colors the number at 5 stacks (Icon + Stack Number, or Stack Number on) and the Charge Bar." }
	end
	return t
end

-- Combined Shocks: how its icon shows the three shocks (one setting for the icon)
local function ShockRows()
	local function choice(text, field, list, pic)
		return {
			text = text, pic = pic,
			value = function() return LabelOf(list, SP:ReadyReminderShockOpt(field)), false end,
			sub = function()
				local cur = SP:ReadyReminderShockOpt(field)
				local items = {}
				for _, c in ipairs(list) do
					local v = c[1]
					items[#items + 1] = { text = c[2], selected = cur == v, pic = c[4], onClick = function()
						SP:ReadyReminderSetShockOpt(field, v); Row:Changed(true); return true
					end }
				end
				return items
			end,
		}
	end
	local style = SP:ReadyReminderShockOpt("shockIcon")
	-- the pictures: one shock's icon in the plate (Cycle takes them in turn, One Shock the one picked);
	-- Split is the slices the Spells row draws
	local function shock(k) return { kind = "swap", icon = Pic.Icon(k) } end
	local picked = SP:ReadyReminderShockOpt("shockPick") or "earthshock"
	local t = { choice("Shock Icon", "shockIcon", Pic.With(SHOCK_CHOICES,
		{ cycle = shock("flameshock"), split = Pic.PLAIN, one = shock(picked) })) }
	if style == "one" then t[#t + 1] = choice("Shock", "shockPick", Pic.With(PICK_CHOICES,
		{ earthshock = shock("earthshock"), flameshock = shock("flameshock"), frostshock = shock("frostshock") })) end
	if style ~= "split" then
		t[#t + 1] = {
			text = "Keep Showing The Last Shock", pic = Pic.PLAIN,
			value = function() return OnOff(SP:ReadyReminderShockOpt("shockKeepLast")), false end,
			sub = function()
				local on = SP:ReadyReminderShockOpt("shockKeepLast") and true or false
				return {
					{ text = "On", selected = on, onClick = function() SP:ReadyReminderSetShockOpt("shockKeepLast", true); Row:Changed(true); return true end },
					{ text = "Off", selected = not on, onClick = function() SP:ReadyReminderSetShockOpt("shockKeepLast", false); Row:Changed(true); return true end },
				}
			end,
		}
	end
	return t
end

local function CopyItems(key)
	local items, others = {}, {}
	for _, e in ipairs(Ordered()) do   -- (every spell, on a row or not; never an empty row's plate)
		if e.key ~= key and SP.ReadyReminderUsable(e) then
			others[#others + 1] = e.key
			items[#items + 1] = { text = e.name, icon = FirstTexture(e),
				onClick = function() SP:ReadyReminderCopyIcon(key, e.key); Row:Changed(false) end }
		end
	end
	if #others > 0 then
		items[#items + 1] = { separator = true }
		items[#items + 1] = { text = "All Icons",
			onClick = function() SP:ReadyReminderCopyIcon(key, others); Row:Changed(false) end }
	end
	return items
end

-- D51 Fade Instead of Hide: under Only In Combat (only while that is on, and not with
-- Show: Never), On / Off; while On its Faded Opacity slider; then Copy Fade To All Icons
local FADE_TIP = "Out of combat, this icon fades to the opacity below instead of hiding, so you can still see which spells are ready. In a fight it's back to full."
local FADED_OPACITY_TIP = "How visible the icon stays out of combat. 100% is how it looks in a fight."
local function FadeRow(key)
	local function on() return Opt(key, "fadeInsteadOfHide") == true end
	return {
		text = "Fade Instead of Hide", tip = FADE_TIP, words = "out of a fight it fades instead of hiding",
		pic = { kind = "faded", alpha = tonumber(Opt(key, "fadeOpacity")) or 0.4 },
		value = function() return OnOff(on()), false end,
		sub = function()
			local isOn = on()
			local t = {
				{ text = "On", selected = isOn, onClick = function() return Set(key, "fadeInsteadOfHide", true) end },
				{ text = "Off", selected = not isOn, onClick = function() return Set(key, "fadeInsteadOfHide", false) end },
			}
			if isOn then
				local opacity = SliderRow(key, "Faded Opacity", "fadeOpacity", 0.05, 0.9, 0.05, 0.4, nil, true, Pic.OPACITY)
				opacity.tip = FADED_OPACITY_TIP
				t[#t + 1] = opacity
			end
			t[#t + 1] = { separator = true }
			t[#t + 1] = CopyGroupRow(key, "Fade", FADE_KEYS)
			return t
		end,
	}
end

-- D52 Your buff on its icon: a group for a spell that puts a buff on you (in this game),
-- named after the buff, right under When Ready. Off to start. Show The Buff picks the
-- look; only the rows that do something in that look are there. Before the buff can come
-- up (the talent, the set bonus or the spell itself missing), a plain line says why first.
local BUFF_LOOK_CHOICES = { { "off", "Off" }, { "corner", "In the Corner" }, { "own", "Separate Icon" },
	{ "edge", "Border Around Icon" }, { "swap", "Replace Spell Icon" } }
local BUFF_LOOK_SHORT = { off = "Off", corner = "Corner", own = "Own Icon", edge = "Edge", swap = "Replaces" }
local BUFF_CORNER_CHOICES = { { "tr", "Top Right" }, { "tl", "Top Left" }, { "br", "Bottom Right" }, { "bl", "Bottom Left" } }
local BUFF_SIDE_CHOICES = { { "above", "Above" }, { "below", "Below" }, { "left", "Left" }, { "right", "Right" },
	{ "spot", "Separate Position" } }
local BUFF_TIPS = {
	show = "Where the buff shows while it's on you. Replace Spell Icon: the buff's own picture takes this icon's place while it's on. It stays on screen while this icon hides between casts, except as an edge or a replacement (they need the icon) and in a grid (there a hidden icon's place goes to the next icon; Separate Position still stays). In a grid its own icon goes Separate Position, since next to this icon is the next icon. Off: nothing changes.",
	corner = "Which corner of this icon the buff sits in.",
	cornerSize = "How big the buff is, as a percentage of this icon's size.",
	side = "Where the buff's own icon goes: next to this icon, or Separate Position, anywhere on your screen (Move This Buff places it). In a separate position it shows even with this icon hidden.",
	ownSize = "How big the buff's icon is, as a percentage of this icon's size.",
	move = "Opens Unlock UI with just this buff's box. Drag it where you want it, then press Done.",
	edge = "The edge's color while the buff is on you. It starts as WoW's mana-bar blue.",
	time = "The seconds the buff has left.",
	gold = "The time turns WoW's gold for the buff's last seconds. Never: it stays white.",
}

-- Show: Never (Ready Flash only): the icon is never on screen, so the buff can only show In
-- Its Own Spot: the corner, the edge (it needs the icon) and the sides next to the icon are
-- left out of the choices, as Fade Instead of Hide is. A look saved before that cannot show
-- then gets a plain line saying why nothing shows.
local BUFF_NEVER_HIDES = { corner = true, edge = true, swap = true, above = true, below = true, left = true, right = true }
local function NeverChoices(list, cur)
	local out = {}
	for _, c in ipairs(list) do
		if not BUFF_NEVER_HIDES[c[1]] or c[1] == cur then out[#out + 1] = c end
	end
	return out
end
-- Grid: the icons sit side by side, so a buff beside its icon would land on the next icon:
-- its own icon goes only In Its Own Spot there (the corner and the edge stay).
local BUFF_GRID_HIDES = { above = true, below = true, left = true, right = true }
local function GridSides(list, cur)
	local out = {}
	for _, c in ipairs(list) do
		if not BUFF_GRID_HIDES[c[1]] or c[1] == cur then out[#out + 1] = c end
	end
	return out
end

local function BuffRows(key, entry)
	local info = SP.ReadyReminderBuffInfo and SP:ReadyReminderBuffInfo(key)
	if not info then return {} end
	local t = {}
	if not info.known then
		t[#t + 1] = { text = info.line1, disabled = true }
		t[#t + 1] = { text = info.line2, disabled = true }
		t[#t + 1] = { separator = true }
	end
	local look = Opt(key, "buffLook") or "off"
	-- the pictures: the buff's own icon in the corner or in this icon's place, the edge in its color
	-- (As Its Own Icon sits beside this icon: no picture kind draws that)
	local buffIcon = Pic.Spell(entry.buff and entry.buff.ids and entry.buff.ids[1]) or 136243
	local looks = { off = Pic.PLAIN, corner = { kind = "corner", icon = buffIcon }, own = Pic.NONE,
		edge = { kind = "edge", color = Pic.Color(key, "buffEdgeColor", 0, 0, 1) },
		swap = { kind = "swap", icon = buffIcon } }
	local never = SP:ReadyReminderShowOf(key) == "flash"
	local side = Opt(key, "buffSide") or "above"
	local grid = ShamanPower_ReadyReminders and ShamanPower_ReadyReminders.arrange == "grid"
	if never and (look == "corner" or look == "edge" or look == "swap" or (look == "own" and side ~= "spot")) then
		t[#t + 1] = { text = "Show: Never keeps this icon off your screen:", disabled = true }
		t[#t + 1] = { text = "the buff shows only in a Separate Position.", disabled = true }
		t[#t + 1] = { separator = true }
	elseif grid and look == "own" and side ~= "spot" then
		t[#t + 1] = { text = "There is no room beside icons in Grid.", disabled = true }
		t[#t + 1] = { text = "Use a separate position for the buff icon.", disabled = true }
		t[#t + 1] = { separator = true }
	end
	t[#t + 1] = {
		text = "Buff Display", tip = BUFF_TIPS.show,
		value = function()
			local cur = Opt(key, "buffLook") or "off"
			return LabelOf(BUFF_LOOK_CHOICES, cur), cur ~= "off"
		end,
		sub = function()
			local cur = Opt(key, "buffLook") or "off"
			local items = {}
			for _, c in ipairs(never and NeverChoices(BUFF_LOOK_CHOICES, cur) or BUFF_LOOK_CHOICES) do
				local v = c[1]
				items[#items + 1] = { text = c[2], selected = cur == v, pic = looks[v], onClick = function()
					-- Show: Never: its own icon goes In Its Own Spot (the one place it can show)
					if (never or grid) and v == "own" and Opt(key, "buffSide") ~= "spot" then SP:ReadyReminderSetIconOpt(key, "buffSide", "spot") end
					return Set(key, "buffLook", v)
				end }
			end
			return items
		end,
	}
	local row
	if look == "corner" then
		-- (the corner picture draws top right only: the other corners say it in words)
		row = ChoiceRow(key, "Corner", "buffCorner", Pic.With(BUFF_CORNER_CHOICES, { tr = looks.corner }), "tr", Pic.NONE)
		row.tip = BUFF_TIPS.corner; t[#t + 1] = row
		row = SliderRow(key, "Size", "buffSize", 0.3, 0.7, 0.05, 0.45, nil, true); row.tip = BUFF_TIPS.cornerSize; t[#t + 1] = row
	elseif look == "own" then
		row = ChoiceRow(key, "Position", "buffSide", never and NeverChoices(BUFF_SIDE_CHOICES, side)
			or grid and GridSides(BUFF_SIDE_CHOICES, side) or BUFF_SIDE_CHOICES, "above", Pic.NONE)
		row.tip = BUFF_TIPS.side; t[#t + 1] = row
		row = SliderRow(key, "Size", "buffOwnSize", 0.3, 1, 0.05, 1, nil, true); row.tip = BUFF_TIPS.ownSize; t[#t + 1] = row
		if Opt(key, "buffSide") == "spot" and SP.ReadyReminderBuffMove then
			t[#t + 1] = { text = "Move This Buff", tip = BUFF_TIPS.move,
				onClick = function() SP:ReadyReminderBuffMove(key); return false end }
		end
	elseif look == "edge" then
		row = ColorRow(key, entry, "Border Color", "buffEdgeColor", 0, 0, 1, Pic.EDGE)
		row.tip = BUFF_TIPS.edge; t[#t + 1] = row
	end
	if look ~= "off" and info.timed then
		row = OnOffRow(key, "Time Left", "buffTime", true, { kind = "number", text = "12" })
		row.tip = BUFF_TIPS.time; t[#t + 1] = row
		if Opt(key, "buffTime") ~= false then
			row = SliderRow(key, "Time Left Size", "buffTimeSize", 0, 40, 1, 0, function(v) if (v or 0) <= 0 then return "Auto" end return tostring(v) end)
			row.tip = "How big the buff's time left is. Auto sizes it to the buff's look."
			t[#t + 1] = row
			row = SliderRow(key, "Turn Time Gold Below (Seconds)", "buffGoldUnder", 0, 10, 1, 3, function(v) return Secs(v, "Never") end)
			row.tip = BUFF_TIPS.gold
			t[#t + 1] = row
		end
	end
	return t
end

-- the group's row: the buff's name, and the look it shows in (Off to start)
local function BuffGroup(key, entry, info)
	return {
		text = info.name .. " Buff", words = "the buff it puts on you, while it's on you",
		tip = "Shows when the " .. info.name .. " buff is on you" .. (info.timed and ", with the time it has left" or "")
			.. ". Pick how under Show The Buff.",
		value = function()
			local look = Opt(key, "buffLook") or "off"
			local v = BUFF_LOOK_SHORT[look] or "Off"
			if look == "own" and Opt(key, "buffSide") == "spot" then v = "Own Spot" end
			return v, look ~= "off"
		end,
		sub = function() return BuffRows(key, entry) end,
	}
end

local function MenuItems(key)
	local entry
	for _, e in ipairs(Ordered()) do if e.key == key then entry = e break end end
	if not entry then return {} end
	local show = SP:ReadyReminderShowOf(key)
	local rowsOn = SP.ReadyRowsOn and SP:ReadyRowsOn()
	local items = {}
	-- the icon itself
	local on = SP.ReadyReminderOn(entry) and true or false
	items[#items + 1] = { text = "Show", label = true }
	items[#items + 1] = { text = on and "Hide This Icon" or "Show This Icon",
		onClick = function() SP:ReadyReminderSetSpell(key, not on); Row:Changed(false) end }
	-- when it shows
	local stackShow
	if entry.stacks then   -- (3.0.9.2) Maelstrom Weapon: by its stacks
		stackShow = ChoiceRow(key, "Show", "stackShow", STACK_SHOWS, "stacks")
		stackShow.words = "when its stacks are on screen"
		stackShow.tip = "While You Have Stacks: from the first stack until you spend them. Only At 5 Stacks: only when your next spell is instant. Always: 0 stacks too, dimmed."
	end
	items[#items + 1] = stackShow or entry.weaponSet and { text = "Show", words = "always on screen: it shows what you hold",
		  value = function() return "Always", false end,
		  tip = "Weapon Set is always on screen: it shows what you hold. Only In Combat below hides it out of a fight." }
		or entry.imbue and { text = "Show", words = "only while an imbue is missing",
		  value = function() return "Only When Missing", false end,
		  tip = "Weapon Imbue shows while an imbue is missing (the main hand; with two weapons, either hand) and hides while your imbues are on." }
		or { text = "Show", words = "when the icon is on screen",
		  value = function() return LabelOf(SHOW_CHOICES, SP:ReadyReminderShowOf(key)), false end,
		  tip = "Only When Ready: the icon comes up when the spell is ready and goes while it cools. Only While On Cooldown: the other way round. While Ready And On Cooldown: always there, with the cooldown sweep and countdown over it; Dimmed: faded while it cools (While On Cooldown sets how).",
		  sub = function()
			local cur = SP:ReadyReminderShowOf(key)
			-- the pictures: the moment each shows (its Ready Effect, the cooldown sweep), dimmed as Opacity has it
			local dim = tonumber(Opt(key, "dimOpacity")) or 0.35
			local dimmed = Pic.PLAIN   -- (Opacity at 100%: nothing dims)
			if dim < 1 then dimmed = { kind = "faded", alpha = dim } end
			local pics = { ready = Pic.Ready(key), cooldown = Pic.SWEEP_ONLY, always_bright = Pic.SWEEP, always = dimmed }
			local list = {}
			for _, c in ipairs(SHOW_CHOICES) do
				local v = c[1]
				list[#list + 1] = { text = c[2], selected = cur == v, pic = pics[v], onClick = function()
					SP:ReadyReminderSetShow(key, v); Row:Changed(true); return true
				end }
			end
			return list
		  end }
	local combat = OnOffRow(key, "Only In Combat", "onlyInCombat", nil, Pic.PLAIN)   -- (on: the icon as a fight shows it)
	combat.words = "only in fights; out of one it hides, or fades"
	items[#items + 1] = combat
	-- right under Only In Combat: only does something while it is on, and the icon is ever on screen
	if Opt(key, "onlyInCombat") and show ~= "flash" then items[#items + 1] = FadeRow(key) end
	if entry.combo then
		items[#items + 1] = { separator = true }
		items[#items + 1] = Group("Shocks", function() return ShockRows() end, "how its one icon shows the three shocks")
	end
	items[#items + 1] = { separator = true }
	-- how it looks
	items[#items + 1] = { text = "Appearance", label = true }
	if entry.stacks then   -- (3.0.9.2) Maelstrom Weapon: its stacks' look
		local look = ChoiceRow(key, "Look", "stackLook", STACK_LOOKS, "number")
		look.words = "how the stacks show"
		look.tip = "How your stacks show: a number on the icon, a Charge Bar like Shield Charges, Blizzard's wings building up, the emblem or the icon filling a fifth per stack, or the icon's glow growing."
		items[#items + 1] = look
		items[#items + 1] = Group("Stacks", function() return StackRows(key, entry) end, "the number, the time left, the colors")
	end
	items[#items + 1] = Group("Appearance", function() return AppearanceRows(key, entry) end,
		"size, opacity, shape, background, border, name, the glow's look")
	-- the cooling settings only do something while it shows on cooldown
	if not entry.weaponSet and (show == "cooldown" or show == "always" or show == "always_bright") then
		items[#items + 1] = Group("While On Cooldown", function() return CoolRows(key, entry) end,
			"how it looks while it's on cooldown")
	end
	-- D52: the buff this spell puts on you (only a spell that puts one on you, in this game)
	local buffInfo = SP.ReadyReminderBuffInfo and SP:ReadyReminderBuffInfo(key)
	if buffInfo then items[#items + 1] = BuffGroup(key, entry, buffInfo) end
	items[#items + 1] = { separator = true }
	-- what it does at its moments
	items[#items + 1] = { text = "Effects & Sound", label = true }
	local readyName = entry.weaponSet and "While Holding" or entry.imbue and "While Imbue Is Missing" or entry.stacks and "At 5 Stacks" or "When Ready"
	items[#items + 1] = Group(readyName, function() return ReadyRows(key, entry, readyName) end,
		entry.weaponSet and "the effect while you hold a set" or entry.imbue and "the effect while an imbue is missing"
		or entry.stacks and "the effect at 5 stacks" or "the effect the moment it's ready")
	if entry.weaponSet then   -- (A28)
		items[#items + 1] = Group("On A Weapon Swap", function() return SwapRows(key, entry) end, "a sound, the Ready Flash")
	end
	-- A25: a spell whose cooldown resets (Stormstrike on WoW: Forever: a tank's dodge or parry)
	if entry.reset and SPCompat and SPCompat.FOREVER then
		items[#items + 1] = Group("When The Cooldown Resets", function() return ResetRows(key, entry) end,
			"a tank's dodge or parry resets it: burst, word, flash, sound")
	end
	if not entry.imbue and not entry.weaponSet and not entry.stacks then
		items[#items + 1] = Group("Out of Range", function() return RangeRows(key, entry) end,
			"how it looks when your target is out of range")
	end
	if not entry.weaponSet and not entry.stacks then   -- (3.0.9.2)
		items[#items + 1] = Group("When Out of Mana", function() return OomRows(key, entry) end,
			"how it looks while you can't afford it")
	end
	items[#items + 1] = Group("Sound", function() return SoundRows(key, entry) end,
		entry.weaponSet and "the sound a swap plays" or entry.imbue and "the sound when an imbue goes missing"
		or entry.stacks and "the sound at 5 stacks" or "the sound the moment it's ready")
	items[#items + 1] = { separator = true }
	-- where it sits (Rows placement: the row it is on; Not On A Row: off your screen)
	if rowsOn and Wide(entry) then   -- (3.0.9.2) Wings / Fill / Charge Bar Only: never on a row; its own spot or off
		items[#items + 1] = { text = "On Row", pic = Pic.NONE, words = "its own spot, or off your screen",
			value = function() return SP:ReadyOwnOff(key) and "Not On A Row" or "Its Own Spot", true end,
			tip = "Wings, Fill and Charge Bar Only are three icons wide, so they sit on a spot of their own, never on a row. Not On A Row: off your screen (drag it down to Not On A Row, or back up, on the Spells row too).",
			sub = function()
				local off = SP:ReadyOwnOff(key)
				return {
					{ text = "Its Own Spot", selected = not off, onClick = function() SP:ReadySetOwnOff(key, false); Row:Changed(false); return false end },
					{ text = "Remove From Row", selected = off, pic = Pic.HIDDEN, onClick = function() SP:ReadySetOwnOff(key, true); Row:Changed(false); return false end },
				}
			end }
		items[#items + 1] = { separator = true }
	elseif rowsOn then
		items[#items + 1] = { text = "On Row", pic = Pic.NONE, words = "the row this icon sits on",
			value = function()
				local i = SP:ReadyRowOf(key)
				local r = i and SP:ReadyRows()[i]
				return r and (r.name or ("Row " .. i)) or "Not On A Row", i ~= nil
			end,
			tip = "The row this icon sits on. Not On A Row: off your screen until you put it on one (pick one here, or drag the icon onto a row under Spells).",
			sub = function()
				local cur = SP:ReadyRowOf(key)
				local list = {}
				for i, r in ipairs(SP:ReadyRows()) do
					list[#list + 1] = { text = r.name or ("Row " .. i), selected = cur == i, onClick = function()
						SP:ReadyRowPlace(key, i, nil); Row:Changed(false); return false
					end }
				end
				list[#list + 1] = { text = "Remove From Row", selected = cur == nil, pic = Pic.HIDDEN, onClick = function()
					SP:ReadyRowRemove(key); Row:Changed(false); return false
				end }
				return list
			end }
		items[#items + 1] = { separator = true }
	end
	-- copy and reset
	items[#items + 1] = { text = "Copy & Reset", label = true }
	items[#items + 1] = { text = "Copy Settings", onClick = function()
		Row.clip = { from = key, name = entry.name, snap = SP:ReadyReminderOwnSnapshot(key) }
		return true
	end }
	local clip = Row.clip
	items[#items + 1] = { text = clip and ("Paste Settings  (from " .. clip.name .. ")") or "Paste Settings",
		disabled = not clip or clip.from == key,
		onClick = function()
			if not Row.clip then return true end
			SP:ReadyReminderPasteSnapshot(key, Row.clip.snap)
			Row:Changed(true)
			return true
		end }
	items[#items + 1] = { text = "Copy Settings To...", disabled = #Row.list < 2, subMaxHeight = 420,
		words = "put this icon's settings on another icon",
		sub = function() return CopyItems(key) end }
	-- Rows placement: this icon's settings onto the other icons on its row, one click (the owner,
	-- 3.0.9: a different look per row without copying icon by icon). Its own item, never inside
	-- Copy Settings To...; the row's name on the right, as On Row shows it
	if rowsOn then
		local ri = SP:ReadyRowOf(key)
		local r = ri and SP:ReadyRows()[ri]
		local rowName = r and (r.name or ("Row " .. ri)) or nil
		local mates = {}
		if r then
			local usable = {}
			for _, e in ipairs(Ordered()) do if SP.ReadyReminderUsable(e) then usable[e.key] = true end end
			for _, k in ipairs(r.spells) do
				if k ~= key and usable[k] then mates[#mates + 1] = k end
			end
		end
		items[#items + 1] = { text = "Copy Settings To This Row", disabled = #mates == 0,
			words = "this icon's settings on the rest of its row",
			value = function() return rowName or "Not On A Row", false end,
			tip = rowName and ("Puts this icon's settings on every other icon on " .. rowName .. ", so the whole row looks like this one.")
				or "This icon is on no row. Put it on one (On Row, above) and this copies its settings to that row.",
			onClick = function() SP:ReadyReminderCopyIcon(key, mates); Row:Changed(false) end }
	end
	items[#items + 1] = { text = "Reset This Icon", disabled = not SP:ReadyReminderHasOwn(key),
		onClick = function() SP:ReadyReminderResetIcon(key); Row:Changed(false) end }
	-- its tests
	local tests = {}
	if entry.weaponSet or Opt(key, "soundOnReady") then
		tests[#tests + 1] = { text = "Test Sound", onClick = function() SP:ReadyReminderPlaySound(nil, key); return true end }
	end
	if entry.stacks and SP.ReadyReminderStacksTest then   -- (3.0.9.2) its look, before your first stack
		tests[#tests + 1] = { text = "Test Icon", disabled = not on,
			tip = on and "Plays your look on the icon: the stacks count up from 1 to 5, then the icon goes back to your real stacks. Out of a fight."
				or "Show this icon first (Show This Icon, at the top of this menu).",
			onClick = function()
				if not SP:ReadyReminderStacksTest(key) then SP:Print("Test Icon works out of a fight.") end
				return true
			end }
	end
	if entry.reset and SPCompat and SPCompat.FOREVER and ResetConfigured(key) then
		tests[#tests + 1] = { text = "Test Cooldown Reset", tip = "Plays what you set under When The Cooldown Resets, once.",
			onClick = function() if SP.ReadyReminderResetTest then SP:ReadyReminderResetTest(key) end; return true end }
	end
	if #tests > 0 then
		items[#items + 1] = { separator = true }
		if #tests > 1 then items[#items + 1] = { text = "Test", label = true } end
		for _, t in ipairs(tests) do items[#items + 1] = t end
	end
	return items
end

-- ---------------------------------------------------------------------------
-- The Spells row (3.0.8): the shared icon row (IconRow.lua), laid out by Placement.
--   Free: the spells in the page's order. Grid: the shown spells in the grid's own
--   shape (Icons Per Row, Spacing), the hidden ones on a NOT SHOWN line. Rows: one
--   line per row with its name (right-click it for the row's menu: Spacing,
--   Direction, Move This Row, Rename, Delete This Row; an empty row shows an empty
--   plate with that menu too), the + tile adds a row; the spells on no row sit in a
--   row of their own under it (Unplaced: a click puts one on the last row).
--   Drag: the order (Free and Grid: the grid fills in it, Reset Position lays Free
--   out in it), or onto a row and between rows (Rows). Rows, 3.0.9: a spell drags
--   from the Not On A Row row up onto a row, and from a row down to Not On A Row
--   (off your screen), the same as On Row in its menu.
-- ---------------------------------------------------------------------------
local GUTTER = 98   -- the row names' room (Grid and Rows)
local Menu = ns.IconRow.Menu
local SEP_ROW = { separator = true }
local function Mode()
	if SP.ReadyRowsOn and SP:ReadyRowsOn() then return "rows" end
	if SP.ReadyReminderPageOpt and SP:ReadyReminderPageOpt("arrange") == "grid" then return "grid" end
	return "free"
end
local function RowName(i)
	local r = SP:ReadyRows()[i]
	return (r and r.name) or ("Row " .. i)
end
local meta = {}         -- [key] = { group, gap }: each item's line and the room before it, set as the list is built
local known = {}
local placeholders = {} -- [row index] = the empty plate an empty row shows
local function Group(e) local m = meta[e.key]; return m and m.group or nil end
local function GapBefore(e) local m = meta[e.key]; return m and m.gap or 0 end

local function Caption()
	local mode = Mode()
	if mode == "grid" then
		local per = tonumber(SP:ReadyReminderPageOpt("gridColumns")) or 6
		local gap = tonumber(SP:ReadyReminderPageOpt("spacing")) or 8
		return "Your grid as it fills: " .. per .. " icons per row, " .. gap .. " px apart. |cff3FA9F5CLICK|r a spell to show or hide it."
			.. " |cff3FA9F5RIGHT-CLICK|r it for its settings. |cff3FA9F5DRAG|r a spell to change the order. |cff3FA9F5Dark|r spells aren't learned yet."
	elseif mode == "rows" then
		return "|cff3FA9F5DRAG|r a spell onto a row, between rows, or down to Not On A Row to take it off your screen. |cff3FA9F5CLICK|r a spell to show or hide it."
			.. " |cff3FA9F5RIGHT-CLICK|r a spell for its settings, a row's name for the row's. |cff3FA9F5Dark|r spells aren't learned yet."
	end
	return "|cff3FA9F5CLICK|r a spell to show or hide it. |cff3FA9F5RIGHT-CLICK|r it for its settings. |cff3FA9F5DRAG|r a spell to change the order."
		.. " |cff3FA9F5Dark|r spells aren't learned yet."
end

-- a row's name (the addon's own dialog)
local function NameBox(i)
	local name = RowName(i)
	return SP:ShowSPDialog({
		key = "readyRowName",
		title = "Rename row",
		text = "A new name for " .. name .. ". It shows beside the row here and on its box in Unlock UI.",
		input = { text = name, maxLetters = 24 },
		buttons = {
			{ text = "Rename", onClick = function(dialog)
				local v = dialog and dialog.GetInput and dialog:GetInput() or ""
				v = tostring(v or ""):match("^%s*(.-)%s*$") or ""
				SP:ReadyRowSet(i, "name", v ~= "" and v or nil)
				Row:Changed(false)
			end },
			{ text = "Cancel" },
		},
	})
end

-- the row's menu: right-click its name (or its empty plate)
local function RowMenuItems(i)
	local r = SP:ReadyRows()[i]
	if not r then return {} end
	local t = {}
	t[#t + 1] = { text = "Rename...", tip = "Rename this row.", onClick = function() NameBox(i); return false end }
	t[#t + 1] = SEP_ROW
	t[#t + 1] = { text = "Position & Keys", label = true }
	t[#t + 1] = Menu.Slider("Spacing", 0, 40, 1, function() return tonumber(r.spacing) or 8 end,
		function(v) SP:ReadyRowSet(i, "spacing", v); Row:Changed(true) end,
		function(v) return string.format("%d px", v) end, false,
		"The gap between this row's icons. 0 puts them side by side, touching.")
	t[#t + 1] = Menu.Choice("Direction", { { "row", "Row" }, { "column", "Column" } },
		function() return r.direction or "row", false end,
		function(v) SP:ReadyRowSet(i, "direction", v); Row:Changed(true); return true end,
		"A row runs right; a column runs down.", Pic.NONE)
	t[#t + 1] = { text = "Move " .. (r.name or ("Row " .. i)), tip = "Unlocks only this row's box: drag it where you want it, then press Done.",
		onClick = function() SP:ReadyRowMove(i); return false end }
	t[#t + 1] = SEP_ROW
	t[#t + 1] = { text = "Delete Row and Hide Its Icons", tip = "Its spells go to Not On A Row (off your screen until you place them again).",
		onClick = function() SP:ReadyRowDelete(i); Row:Changed(false); return false end }
	return t
end
local function RowMenu(i, holder)
	if not SP:ReadyRows()[i] then return end
	ns.ContextMenu:Open(holder, { header = { text = RowName(i) }, items = function() return RowMenuItems(i) end })
end

local LABELS = { off = "NOT SHOWN", none = "NOT ON A ROW", own = "OWN SPOT" }
local ROW_TIP = "This row's own settings: its spacing, direction, spot and name."
local function GroupLabel(holder, key)
	if not holder.text then
		holder.text = holder:CreateFontString(nil, "OVERLAY")
		holder.text:SetFontObject(Core.fonts.section)
		holder.text:SetPoint("LEFT", holder, "LEFT", 0, 0)
		holder.text:SetJustifyH("LEFT")
		holder:EnableMouse(true)
		holder:SetScript("OnMouseUp", function(h) if h.spRowIndex then RowMenu(h.spRowIndex, h) end end)
	end
	local n = key and key:match("^row(%d+)$")
	n = n and tonumber(n) or nil
	holder.spRowIndex = n
	local text = n and RowName(n) or (key and LABELS[key]) or ""
	holder.text:SetText(text:upper())
	holder.text:SetTextColor(Core:Color(n and "text" or "textDim"))
	if n then
		Core:AttachTooltip(holder, RowName(n), ROW_TIP, "Click: this row's settings")
	else
		Core:HideTooltipFor(holder)
		holder:SetScript("OnEnter", nil); holder:SetScript("OnLeave", nil)
	end
end

local function ListItems(out)
	wipe(meta)
	local mode = Mode()
	Known(known)
	Row.def.groupLabelWidth = (mode == "free") and 0 or GUTTER
	if mode == "free" then
		for _, e in ipairs(known) do out[#out + 1] = e end
		return
	end
	if mode == "grid" then
		local per = tonumber(SP:ReadyReminderPageOpt("gridColumns")) or 6
		if per < 1 then per = 1 end
		local gap = max(0, (tonumber(SP:ReadyReminderPageOpt("spacing")) or 8) - (PITCH - PLATE))
		local i = 0
		for _, e in ipairs(known) do
			if SP.ReadyReminderOn(e) and not Wide(e) then
				i = i + 1
				out[#out + 1] = e
				meta[e.key] = { group = "g" .. ceil(i / per), gap = ((i - 1) % per ~= 0) and gap or 0 }
			end
		end
		for _, e in ipairs(known) do   -- (3.0.9.2) Wings / Fill: its own spot, never in the grid
			if SP.ReadyReminderOn(e) and Wide(e) then out[#out + 1] = e; meta[e.key] = { group = "own" } end
		end
		for _, e in ipairs(known) do
			if not SP.ReadyReminderOn(e) then out[#out + 1] = e; meta[e.key] = { group = "off" } end
		end
		return
	end
	local byKey = {}
	for _, e in ipairs(known) do byKey[e.key] = e end
	for i, r in ipairs(SP:ReadyRows()) do
		local gap = max(0, (tonumber(r.spacing) or 8) - (PITCH - PLATE))
		local j = 0
		for _, key in ipairs(r.spells) do
			local e = byKey[key]
			if e and not Wide(e) then
				j = j + 1
				out[#out + 1] = e
				meta[key] = { group = "row" .. i, gap = (j > 1) and gap or 0 }
			end
		end
		if j == 0 then   -- an empty row: an empty plate, so the row has a line to drag onto
			local ph = placeholders[i]
			if not ph then ph = { key = "__row" .. i, empty = true, row = i }; placeholders[i] = ph end
			ph.name = RowName(i)
			out[#out + 1] = ph
			meta[ph.key] = { group = "row" .. i }
		end
	end
	for _, e in ipairs(known) do   -- (3.0.9.2) Wings / Fill: its own spot, on no row (dragged down: off your screen)
		if Wide(e) and not SP:ReadyOwnOff(e.key) then out[#out + 1] = e; meta[e.key] = { group = "own" } end
	end
end

-- Rows: a spell dropped at a spot in the Spells row (cx, cy in its frame) goes onto the row of
-- the line under the cursor, before the first icon on it whose middle is right of the cursor.
-- true when it landed on a row (a drop from this row, or from the Not On A Row row)
local function PlaceAt(e, cx, cy)
	local sx, sy, list = Row.slotX, Row.slotY, Row.list
	if not (sx and sy) then return false end
	local lineY, best
	for i = 1, #list do
		local d = math.abs(cy - (sy[i] + PLATE / 2))
		if not best or d < best then best, lineY = d, sy[i] end
	end
	if lineY == nil then return false end
	local rowIndex, at = nil, 1
	for i = 1, #list do
		if sy[i] == lineY then
			local x = list[i]
			local m = meta[x.key]
			local n = m and m.group and m.group:match("^row(%d+)$")
			if n then rowIndex = rowIndex or tonumber(n) end
			if x ~= e and not x.empty and cx >= sx[i] + PLATE / 2 then at = at + 1 end
		end
	end
	if not rowIndex then return false end
	SP:ReadyRowPlace(e.key, rowIndex, at)
	return true
end

-- a drop. Free and Grid: the order. Rows: onto the row under the cursor (PlaceAt)
local function Move(e, to)
	if e.empty then return end
	if Mode() == "rows" and Wide(e) then return end   -- (its own spot: it never goes onto a row)
	if Mode() ~= "rows" then
		local before, n = nil, 0
		for _, x in ipairs(Row.list) do
			if x ~= e then
				n = n + 1
				if n == to then before = x.key break end
			end
		end
		SP:ReadyOrderMove(e.key, before)
		return
	end
	PlaceAt(e, Row:CursorInFrame())
end

Row = ns.IconRow.New({
	caption = Caption,
	hint = "Click: show or hide it\nRight-click: its settings\nDrag: its order, onto a row, or off the rows",
	list = ListItems,
	moveAlways = function() return Mode() == "rows" end,   -- (a drop onto an empty row lands where the list order would call "no move")
	textures = function(e, out) if e.empty then return 0 end return SP:ReadyReminderIconTextures(e.key, out) end,
	shown = function(e) if e.empty then return false end return SP.ReadyReminderOn(e) and true or false end,
	learned = function(e) if e.empty then return true end return SP.ReadyReminderKnown(e) and true or false end,
	hasOwn = function(e) if e.empty then return false end return SP:ReadyReminderHasOwn(e.key) and true or false end,
	tooltip = function(e)
		if e.empty then return "An empty row. Drag a spell onto it, or pick this row in a spell's On Row. Right-click: the row's settings." end
		return TooltipBody(e)
	end,
	toggle = function(e) if e.empty then return end SP:ReadyReminderSetSpell(e.key, not SP.ReadyReminderOn(e)) end,
	menu = function(e) if e.empty then return RowMenuItems(e.row) end return MenuItems(e.key) end,
	move = Move,
	movable = function(e) return not e.empty and not (Wide(e) and Mode() == "grid") end,   -- (Wings / Fill: its own spot; in Rows, down to Not On A Row)
	crossGroups = true,   -- (a spell drags from one row to another; the line follows the cursor's row)
	-- Rows: a spell dragged down onto the Not On A Row row comes off its row (off your screen)
	dropTargets = function() if Mode() == "rows" and Unplaced then return { Unplaced } end end,
	dropOut = function(e, target)
		if target ~= Unplaced or e.empty then return end
		if Wide(e) then SP:ReadySetOwnOff(e.key, true) else SP:ReadyRowRemove(e.key) end   -- (Wings / Fill: off its own spot)
	end,
	gapBefore = GapBefore,
	group = Group,
	groupLabel = GroupLabel,
	groupLabelWidth = GUTTER,
	groupGap = 6,
	add = {
		name = "Add a Row",
		tip = "A new empty row under the others. Put spells on it: drag them onto it, or pick it in a spell's On Row.",
		hint = "Click: add a row",
		shown = function() return Mode() == "rows" end,
		click = function() SP:ReadyRowAdd() end,
	},
})
ns.CustomRows.readyIcons = Row
SP.ReadyIconsRow = Row   -- (the sp-ci tests open an icon's menu through it)

-- ===========================================================================
-- The Ready Flash tab's Spells row (A26): click a spell to flash it when ready (whether or
-- not it shows an icon), right-click it for what is truly per spell: on / off, Flash Early,
-- a spot of its own with its own Size, and a Test
-- ===========================================================================
local FlashRow
local flashList = {}
local function FSet(key, opt, value)
	SP:ReadyReminderSetIconOpt(key, opt, value)
	FlashRow:Changed(true)
	return true
end
local function FlashMenuItems(key)
	local on = Opt(key, "flash") == true
	local own = SP:ReadyFlashHasOwnSpot(key)
	local t = {}
	t[#t + 1] = { text = "Show", label = true }
	t[#t + 1] = { text = "Ready Flash", pic = Pic.FLASH, words = "a big flash of the icon the moment it's ready",
		value = function() return OnOff(on), on end,
		sub = function() return {
			{ text = "On", selected = on, onClick = function() return FSet(key, "flash", true) end },
			{ text = "Off", selected = not on, onClick = function() return FSet(key, "flash", false) end },
		} end }
	-- when
	t[#t + 1] = { text = "Flash Early", tip = "Flash this many seconds before the spell is ready. Use Page Setting follows Flash Early on this tab.",
		slider = { min = 0, max = 5, step = 0.5,
			get = function() return tonumber(SP:ReadyReminderOwnOpt(key, "flashEarly")) or 0 end,
			set = function(v) SP:ReadyReminderSetIconOpt(key, "flashEarly", v > 0 and v or nil); FlashRow:Repaint() end,
			format = function(v) return Secs(v, "Use Page Setting") end } }
	t[#t + 1] = { separator = true }
	-- how it looks (its own spot has its own size; the shared spot's size is the tab's)
	if own then
		t[#t + 1] = SliderRow(key, "Size", "flashSize", 48, 200, 4,
			SP.ReadyReminderIconOpt and (tonumber(SP:ReadyReminderIconOpt(key, "flashSize")) or 96) or 96, nil, nil, Pic.SIZE)
		t[#t + 1] = { separator = true }
	end
	-- where
	if own then t[#t + 1] = { text = "Position & Keys", label = true } end
	t[#t + 1] = { text = "Position", pic = Pic.NONE, words = "where this spell's flash plays",
		value = function() return own and "Separate Position" or "Shared Position", own end,
		tip = "Where this spell's flash plays: the shared spot, or a spot of its own (Unlock UI opens with its box; drop it where you want it).",
		sub = function() return {
			{ text = "Shared Position", selected = not own, onClick = function() SP:ReadyFlashUseShared(key); FlashRow:Changed(true); return true end },
			{ text = "Separate Position", selected = own, onClick = function() if SP.ReadyFlashMoveSpell then SP:ReadyFlashMoveSpell(key) end; return false end },
		} end }
	if own then
		t[#t + 1] = { text = "Move This Flash", tip = "Open Unlock UI to move this spell's Ready Flash.",
			onClick = function() if SP.ReadyFlashMoveSpell then SP:ReadyFlashMoveSpell(key) end; return false end }
	end
	t[#t + 1] = { separator = true }
	t[#t + 1] = { text = "Test This Flash", onClick = function() if SP.ReadyFlashTest then SP:ReadyFlashTest(key) end; return true end }
	return t
end

FlashRow = ns.IconRow.New({
	caption = "|cff3FA9F5CLICK|r a spell to flash it when it is ready. |cff3FA9F5RIGHT-CLICK|r it for its own spot, its size there and Flash Early. |cff3FA9F5Dark|r spells aren't learned yet.",
	hint = "Click: flash it when ready\nRight-click: its own spot and more",
	list = function(out) for _, e in ipairs(Known(flashList)) do if not e.stacks then out[#out + 1] = e end end end,
	textures = function(e, out) return SP:ReadyReminderIconTextures(e.key, out) end,
	shown = function(e) return Opt(e.key, "flash") == true end,
	learned = function(e) return SP.ReadyReminderKnown(e) and true or false end,
	hasOwn = function(e) return SP:ReadyFlashHasOwnSpot(e.key) and true or false end,
	tooltip = function(e)
		if not SP.ReadyReminderKnown(e) then return "You haven't learned this yet. You can still set it up." end
		if SP:ReadyFlashHasOwnSpot(e.key) then return "It flashes on a spot of its own (right-click to move it)." end
		return "It flashes on the shared spot (right-click for its own)."
	end,
	toggle = function(e) SP:ReadyReminderSetIconOpt(e.key, "flash", not (Opt(e.key, "flash") == true)) end,
	menu = function(e) return FlashMenuItems(e.key) end,
})
ns.CustomRows.readyFlashIcons = FlashRow

-- Rows placement: the spells on no row, off your screen, a row of their own under the Spells row
local unplacedList = {}
Unplaced = ns.IconRow.New({
	caption = "These spells are on no row, so they are off your screen. |cff3FA9F5DRAG|r one onto a row, or |cff3FA9F5CLICK|r it to put it on the last row. |cff3FA9F5RIGHT-CLICK|r it for its settings.",
	hint = "Click: put it on the last row\nDrag: onto a row\nRight-click: its settings",
	list = function(out)
		if Mode() ~= "rows" then return end
		for _, e in ipairs(Known(unplacedList)) do
			if Wide(e) then
				if SP:ReadyOwnOff(e.key) then out[#out + 1] = e end   -- (3.0.9.2: dragged off its own spot)
			elseif not SP:ReadyRowOf(e.key) then out[#out + 1] = e end
		end
	end,
	textures = function(e, out) return SP:ReadyReminderIconTextures(e.key, out) end,
	shown = function() return false end,
	learned = function(e) return SP.ReadyReminderKnown(e) and true or false end,
	hasOwn = function(e) return SP:ReadyReminderHasOwn(e.key) and true or false end,
	tooltip = function() return "Off your screen: it is on no row. Click to put it on the last row, or drag it onto one." end,
	toggle = function(e)
		if Wide(e) then SP:ReadySetOwnOff(e.key, false) else SP:ReadyRowPlace(e.key, nil, nil) end   -- (Wings / Fill: back on its own spot)
		if not SP.ReadyReminderOn(e) then SP:ReadyReminderSetSpell(e.key, true) end
	end,
	menu = function(e) return MenuItems(e.key) end,
	-- a drag up onto a row of the Spells row puts it there, and on screen, as a click does; the
	-- order within this row is the page's, so a drag never lands here
	move = function() end,
	dragOutOnly = true,
	dropTargets = function() return { Row } end,
	dropOut = function(e, target, cx, cy)
		if target ~= Row then return end
		if Wide(e) then SP:ReadySetOwnOff(e.key, false)   -- (Wings / Fill: back on its own spot, never a row)
		elseif not PlaceAt(e, cx, cy) then SP:ReadyRowPlace(e.key, nil, nil) end
		if not SP.ReadyReminderOn(e) then SP:ReadyReminderSetSpell(e.key, true) end
	end,
	group = function() return "none" end,
	groupLabel = GroupLabel,
	groupLabelWidth = GUTTER,
	empty = "Every spell is on a row.",
})
ns.CustomRows.readyUnplaced = Unplaced
do
	local proto = getmetatable(Unplaced).__index
	-- not in Rows placement: the row draws nothing
	Unplaced.Render = function(self, ...)
		if Mode() ~= "rows" then
			if self.frame then self.frame:Hide() end
			return nil, 0
		end
		return proto.Render(self, ...)
	end
	-- the Spells row: the module's settings watcher repaints both rows (set up on the first draw)
	Row.Render = function(self, ...)
		if not (SP.ReadyReminderSpells and SP.ReadyReminderIconTextures and SP.ReadyReminderKnown) then return nil, 0 end
		if not self.watching and SP.ReadyReminderWatch then
			self.watching = true
			SP:ReadyReminderWatch(function() Row:OnSettingsChanged(); Unplaced:OnSettingsChanged() end)
		end
		return proto.Render(self, ...)
	end
end

-- ---------------------------------------------------------------------------
-- Entry point: an icon's own settings from anywhere
-- ---------------------------------------------------------------------------
-- path (optional): the submenus to open in it, by row (the separators not counted)
function SP.ReadyReminderOpenIconMenu(_, key, path)
	local cfg = _G.ShamanPowerConfig
	if not (cfg and cfg.Open) then return end
	Row.reopen = { key = key, at = GetTime(), path = path }
	cfg:Open({ "fluffy", "readyreminders_section" })
end

-- ---------------------------------------------------------------------------
-- The "settings moved" notice at the top of the page (3.0.6 and 3.0.7, for players
-- who had Ready Reminders before): one line and Got it, which hides it for good
-- ---------------------------------------------------------------------------
local Notice = {}
ns.CustomRows.readyNotice = Notice
local NOTICE_TEXT = "Right-click a spell to change its Ready Reminders settings."

function Notice:Render(body, x, y, width)
	if not (SP.ReadyReminderNoticeShown and SP.ReadyReminderNoticeShown()) then return nil, 0 end
	local f = self.frame
	if not f then
		f = CreateFrame("Frame", nil, body)
		f.text = f:CreateFontString(nil, "OVERLAY")
		f.text:SetFontObject(Core.fonts.row)
		f.text:SetJustifyH("LEFT")
		f.text:SetWordWrap(true)
		f.btn = Core:MakeButton(f, "Got it", 90, true)
		f.btn:SetScript("OnClick", function()
			if SP.ReadyReminderNoticeDone then SP.ReadyReminderNoticeDone() end
			local cfg = _G.ShamanPowerConfig
			if cfg and cfg.RefreshCurrent then cfg:RefreshCurrent() end
		end)
		f.spNoCull = true   -- (redrawn by its own watcher, which skips a hidden row)
		self.frame = f
	end
	f:SetParent(body)
	f:ClearAllPoints()
	f:SetPoint("TOPLEFT", body, "TOPLEFT", x or 0, -(y or 0))
	f:SetWidth(width)
	f:Show()
	local padX = PAD_X + (ns.Widgets and tonumber(ns.Widgets.CARD_INSET) or 0)
	local mid = PAD_TOP + 13
	f.btn:ClearAllPoints()
	f.btn:SetPoint("RIGHT", f, "TOPRIGHT", -padX, -mid)
	f.text:ClearAllPoints()
	f.text:SetPoint("LEFT", f, "TOPLEFT", padX, -mid)
	f.text:SetPoint("RIGHT", f.btn, "LEFT", -12, 0)
	f.text:SetText(NOTICE_TEXT)
	local h = PAD_TOP + max(26, ceil(f.text:GetStringHeight())) + PAD_BOTTOM
	f:SetHeight(h)
	return f, h + ROW_GAP
end

function Notice:Release()
	if self.frame then self.frame:Hide() end
end
