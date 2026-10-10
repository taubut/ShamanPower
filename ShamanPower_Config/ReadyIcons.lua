-- ShamanPower_Config :: ReadyIcons
-- Ready Reminders' settings page (D40, 2026-10-02): the Spells row and, for players
-- updating, the "settings moved" notice. The Spells row shows every Ready Reminder
-- spell this game version has, learned or not (not learned: dark), in the list's
-- order, as 36 px spell icons on thin plates. A hidden one is gray and dim; a small
-- accentHi corner marks an icon with settings of its own. Left-click: show or hide
-- it. Right-click: EVERY setting of that spell, in ns.ContextMenu, grouped (Look,
-- When Ready, While On Cooldown, Out of Range, Sound), with sliders
-- in the rows (D41 A), Copy / Paste and Copy <Group> To All Icons. An icon that
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

-- ---------------------------------------------------------------------------
-- Labels
-- ---------------------------------------------------------------------------
local SHOW_CHOICES = {
	{ "ready", "Only When Ready" }, { "cooldown", "Only While On Cooldown" },
	{ "always_bright", "Always (Sweep + Countdown)" }, { "always", "Always, Dimmed While On Cooldown" },
}
local EFFECT_CHOICES = { { "glow", "Glow" }, { "pulse", "Pulse" }, { "both", "Glow + Pulse" }, { "none", "None" } }
local SWEEP_CHOICES = { { "radial", "Radial (Clock)" }, { "vertical", "Vertical - Fills Back In" }, { "none", "None" } }
local SWEEP_DIRECTION_CHOICES = { { "top", "From The Top" }, { "bottom", "From The Bottom" } }
local BAR_CHOICES = { { "none", "None" }, { "below", "Below The Icon" }, { "above", "Above The Icon" } }
local TEXTPOS_CHOICES = { { "center", "Center" }, { "top", "Top" }, { "bottom", "Bottom" }, { "below", "Below The Icon" }, { "above", "Above The Icon" } }
local RANGE_CHOICES = { { "red", "Red Tint" }, { "gray", "Gray" }, { "dim", "Dim" } }
local ANIM_CHOICES = { { "grow", "Grow and Fade" }, { "pop", "Pop" }, { "fade", "Fade Only" } }
local SHOCK_CHOICES = { { "cycle", "Cycle" }, { "split", "Split" }, { "one", "One Shock" } }
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

-- ---------------------------------------------------------------------------
-- The icons
-- ---------------------------------------------------------------------------
local texOut = {}   -- reused: the textures of the icon being painted

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

local function ChoiceRow(key, text, opt, list, fallback)
	return {
		text = text,
		value = function() return LabelOf(list, Opt(key, opt) or fallback), false end,
		sub = function()
			local cur = Opt(key, opt) or fallback
			local items = {}
			for _, c in ipairs(list) do
				local v = c[1]
				items[#items + 1] = { text = c[2], selected = cur == v, onClick = function() return Set(key, opt, v) end }
			end
			return items
		end,
	}
end
-- on / off: onByDefault = what an unset value means (Countdown Text and Gray Out are on)
local function OnOffRow(key, text, opt, onByDefault)
	local function cur()
		local v = Opt(key, opt)
		if onByDefault then return v ~= false end
		return v == true
	end
	return {
		text = text,
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
local function SliderRow(key, text, opt, lo, hi, step, fallback, format, isPercent)
	return {
		text = text,
		slider = {
			min = lo, max = hi, step = step, isPercent = isPercent,
			get = function() return tonumber(Opt(key, opt)) or fallback end,
			set = function(v) SliderSet(key, opt, v) end,
			format = format,
		},
	}
end
local function ColorRow(key, entry, text, opt, dr, dg, db)
	return {
		text = text,
		swatch = { Color3(Opt(key, opt), dr, dg, db) },
		sub = function()
			return { { text = "Pick Color...", onClick = function()
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
			end } }
		end,
	}
end
-- a setting every spell shares (it is also on General > Themes)
local function SharedRow(text, values, getter, setter)
	return {
		text = text .. " (All Spells)",
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
local function CopyGroupRow(key, group, opts)
	return { text = "Copy " .. group .. " To All Icons", onClick = function()
		SP:ReadyReminderCopyGroup(key, opts)
		Row:Changed(true)
		return true
	end }
end
local function Group(text, rows)
	return { text = text, sub = function() return rows() end }
end

local LOOK_KEYS = { "iconSize", "opacity", "hideBackground", "hideBorder", "borderColor", "showNames" }
local READY_KEYS = { "readyEffect", "glowColor", "glowShape", "glowThick", "glowCombatOnly" }
local COOL_KEYS = { "dimOpacity", "desaturate", "sweepStyle", "sweepDirection", "barStyle", "barHeight", "barColor", "showCountdown",
	"textPosition", "textSize", "countdownUnder" }
local RANGE_KEYS = { "outOfRange", "rangeLook", "rangeColor" }
local SOUND_KEYS = { "soundOnReady", "soundName", "soundVolume", "soundMinCooldown" }
local FADE_KEYS = { "fadeInsteadOfHide", "fadeOpacity" }

local function LookRows(key, entry)
	local t = {
		SliderRow(key, "Icon Size", "iconSize", 24, 96, 2, 48),
		SliderRow(key, "Opacity", "opacity", 0.2, 1, 0.05, 1, nil, true),
	}
	if SP.IconShapeValues and SP.IconShapeOf and SP.SetIconShape then
		t[#t + 1] = SharedRow("Icon Shape", function() return SP:IconShapeValues() end,
			function() return SP:IconShapeOf("ready") or "default" end, function(v) SP:SetIconShape(v, "ready") end)
	end
	t[#t + 1] = {
		text = "Background",
		value = function() if Opt(key, "hideBackground") then return "Hide", false end return "Show", false end,
		sub = function()
			local hidden = Opt(key, "hideBackground") and true or false
			return {
				{ text = "Show", selected = not hidden, onClick = function() return Set(key, "hideBackground", false) end },
				{ text = "Hide (Background And Border)", selected = hidden, onClick = function() return Set(key, "hideBackground", true) end },
			}
		end,
	}
	local bg = not Opt(key, "hideBackground")
	if bg then
		t[#t + 1] = {
			text = "Border",
			value = function() if Opt(key, "hideBorder") then return "Hide", false end return "Show", false end,
			sub = function()
				local hidden = Opt(key, "hideBorder") and true or false
				return {
					{ text = "Show", selected = not hidden, onClick = function() return Set(key, "hideBorder", false) end },
					{ text = "Hide", selected = hidden, onClick = function() return Set(key, "hideBorder", true) end },
				}
			end,
		}
	end
	if bg and not Opt(key, "hideBorder") then
		local shape = SP.IconShapeOf and SP:IconShapeOf("ready")
		if (shape == "rounded" or shape == "circle") and SP.SetIconBordersSquare then
			t[#t + 1] = SharedRow("Keep Borders Square", function() return { [true] = "On", [false] = "Off" }, { true, false } end,
				function() return SP.opt and SP.opt.iconBordersSquare == true end, function(v) SP:SetIconBordersSquare(v) end)
		end
		t[#t + 1] = ColorRow(key, entry, "Border Color", "borderColor", 0.2, 0.7, 1.0)
	end
	t[#t + 1] = OnOffRow(key, "Show Spell Name", "showNames")
	t[#t + 1] = { separator = true }
	t[#t + 1] = CopyGroupRow(key, "Look", LOOK_KEYS)
	return t
end

local function ReadyRows(key, entry)
	local fx = Opt(key, "readyEffect") or "glow"
	local name = entry.weaponSet and "Effect While Holding" or (SP:ReadyReminderShowOf(key) == "cooldown" and "Effect While Shown" or "Ready Effect")
	local t = { ChoiceRow(key, name, "readyEffect", EFFECT_CHOICES, "glow") }
	if fx == "glow" or fx == "both" then
		t[#t + 1] = ColorRow(key, entry, "Glow Color", "glowColor", 0.3, 0.8, 1.0)
		if SP.GlowShapeValues then
			-- this icon's own shape and thickness (an icon that never picked one shows General > Themes' Glow Shape)
			local map, order = SP:GlowShapeValues()
			local choices = {}
			for _, k in ipairs(order or {}) do choices[#choices + 1] = { k, map[k] } end
			local shared = SP.opt and SP.opt.glowShape or "default"
			t[#t + 1] = ChoiceRow(key, "Glow Shape", "glowShape", choices, shared)
			if (Opt(key, "glowShape") or shared) == "proc" and SP.ProcGlowOut then
				local row = SliderRow(key, "Proc Glow Thickness", "glowThick", 0, 0.6, 0.01, SP.PROC_GLOW_OUT or 0.2, nil, true)
				row.tip = "How thick the ring is. It grows outward from the icon's edge."
				t[#t + 1] = row
			end
		end
		local co = OnOffRow(key, "Glow Only In Combat", "glowCombatOnly")
		co.tip = "Out of a fight the icon shows with no glow; the glow comes in a fight."
		t[#t + 1] = co
	end
	t[#t + 1] = { separator = true }
	t[#t + 1] = CopyGroupRow(key, "When Ready", READY_KEYS)
	return t
end

-- A25: When The Cooldown Resets (Stormstrike on WoW: Forever, where a tank's dodge or parry resets
-- it): the icon's burst / word, the Ready Flash saying so, its own sound; each its own switch
local RESET_VISUALS = { { "none", "None" }, { "burst", "Glow Burst" }, { "word", "\"Reset\" Word" }, { "both", "Glow Burst + Word" } }
local function ResetRows(key, entry)
	local vis = Opt(key, "resetVisual") or "none"
	local t = {}
	local v = ChoiceRow(key, "Visual On The Icon", "resetVisual", RESET_VISUALS, "none")
	v.tip = "What the icon does the moment its cooldown is reset (a dodge or parry as a tank). The burst is the Proc Glow ring, the word is RESET over the icon."
	t[#t + 1] = v
	if vis == "burst" or vis == "both" then t[#t + 1] = ColorRow(key, entry, "Burst Color", "resetColor", 1, 0.82, 0) end
	if vis ~= "none" then
		local l = SliderRow(key, "Length", "resetLength", 0.5, 3, 0.1, 1.5, function(x) return Secs(x) end)
		l.tip = "How long the burst or the word stays before the ready look takes over."
		t[#t + 1] = l
	end
	local fl = OnOffRow(key, "Ready Flash", "resetFlash")
	fl.tip = "Your Ready Flash, in place of the plain ready one."
	t[#t + 1] = fl
	if Opt(key, "resetFlash") then
		local fw = OnOffRow(key, "Word Under The Flash", "resetFlashWord", true)
		fw.tip = "The flash says " .. entry.name .. " reset! under the icon. Off: just the icon."
		t[#t + 1] = fw
	end
	local so = OnOffRow(key, "Play Sound", "resetSound")
	so.tip = "Its own sound; the Ready sound stays quiet for a reset, so you never hear two."
	t[#t + 1] = so
	if Opt(key, "resetSound") then
		t[#t + 1] = {
			text = "Sound", subMaxHeight = 300,
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
	if vis ~= "none" or Opt(key, "resetFlash") or Opt(key, "resetSound") then
		t[#t + 1] = { separator = true }
		t[#t + 1] = { text = "Test", onClick = function() if SP.ReadyReminderResetTest then SP:ReadyReminderResetTest(key) end; return true end }
	end
	return t
end

-- A28: Weapon Set: the word under the icon, the set whose hold plays the effect, the swap switches
local HOLD_CHOICES = { { "never", "Never" }, { "shield", "A Shield" }, { "2h", "A Two-Hander" }, { "dual", "Two Weapons" }, { "one", "A One-Hander Alone" } }
local function WeaponSetRows(key, entry)
	local t = {}
	local w = OnOffRow(key, "Word Under The Icon", "wsWord", true)
	w.tip = "Shield, Two-Hander, Two Weapons or One-Hander under the icon."
	t[#t + 1] = w
	local g = ChoiceRow(key, "Glow While Holding", "wsGlow", HOLD_CHOICES, "never")
	g.tip = "The icon's effect (Effect While Holding: glow, pulse, your Glow Shape and Glow Color) plays only while you hold this set, so the wrong set stands out."
	t[#t + 1] = g
	t[#t + 1] = { separator = true }
	local so = OnOffRow(key, "Sound On A Swap", "wsSound")
	so.tip = "The icon's Sound (its group below) plays the moment the set changes."
	t[#t + 1] = so
	local fl = OnOffRow(key, "Ready Flash On A Swap", "wsFlash")
	fl.tip = "Your Ready Flash shows the new set the moment it changes."
	t[#t + 1] = fl
	return t
end

local function CoolRows(key, entry)
	local t = {
		SliderRow(key, "Opacity", "dimOpacity", 0.1, 1, 0.05, 0.35, nil, true),
		OnOffRow(key, "Gray Out The Icon", "desaturate", true),
		ChoiceRow(key, "Sweep", "sweepStyle", SWEEP_CHOICES, "radial"),
	}
	if Opt(key, "sweepStyle") == "vertical" then
		t[#t + 1] = ChoiceRow(key, "Sweep Direction", "sweepDirection", SWEEP_DIRECTION_CHOICES, "bottom")
	end
	t[#t + 1] = ChoiceRow(key, "Progress Bar", "barStyle", BAR_CHOICES, "none")
	if (Opt(key, "barStyle") or "none") ~= "none" then
		t[#t + 1] = SliderRow(key, "Bar Height", "barHeight", 2, 12, 1, 4)
		t[#t + 1] = ColorRow(key, entry, "Bar Color", "barColor", 0.3, 0.8, 1.0)
		if SP.opt and SP.opt.barGradient and SP.GradientDirectionValues and SP.BarGradientDirection and SP.SetBarGradientDirection then
			t[#t + 1] = SharedRow("Bar Gradient", function() return SP:GradientDirectionValues("barGradient") end,
				function() return SP:BarGradientDirection("other") end, function(v) SP:SetBarGradientDirection("other", v) end)
		end
	end
	t[#t + 1] = OnOffRow(key, "Countdown Text", "showCountdown", true)
	if Opt(key, "showCountdown") ~= false then
		t[#t + 1] = ChoiceRow(key, "Countdown Position", "textPosition", TEXTPOS_CHOICES, "center")
		t[#t + 1] = SliderRow(key, "Countdown Size", "textSize", 0, 40, 1, 0, function(v) if (v or 0) <= 0 then return "Auto" end return tostring(v) end)
		t[#t + 1] = SliderRow(key, "Countdown Only Under", "countdownUnder", 0, 60, 1, 0, function(v) return Secs(v, "Always") end)
	end
	t[#t + 1] = { separator = true }
	t[#t + 1] = CopyGroupRow(key, "While On Cooldown", COOL_KEYS)
	return t
end

local function RangeRows(key, entry)
	local t = { OnOffRow(key, "Show Out of Range", "outOfRange") }
	if Opt(key, "outOfRange") then
		t[#t + 1] = ChoiceRow(key, "Look", "rangeLook", RANGE_CHOICES, "red")
		if (Opt(key, "rangeLook") or "red") == "red" then t[#t + 1] = ColorRow(key, entry, "Color", "rangeColor", 0.64, 0.15, 0.15) end
	end
	t[#t + 1] = { separator = true }
	t[#t + 1] = CopyGroupRow(key, "Out of Range", RANGE_KEYS)
	return t
end

local function SoundRows(key, entry)
	-- Weapon Set (A28): no ready moment, so no Play Sound switch; the sound is what Sound On A Swap plays
	local ws = entry and entry.weaponSet
	local t = {}
	if not ws then t[1] = OnOffRow(key, "Play Sound", "soundOnReady") end
	if ws or Opt(key, "soundOnReady") then
		t[#t + 1] = {
			text = "Sound", subMaxHeight = 300,
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
		-- a sound turned on in this menu always plays: the minimum only filters the old default
		if not Opt(key, "ownSound") and not ws then
			t[#t + 1] = SliderRow(key, "Only For Cooldowns Over", "soundMinCooldown", 0, 300, 5, 20, function(v) return Secs(v, "Always") end)
		end
		t[#t + 1] = { text = "Test Sound", onClick = function() SP:ReadyReminderPlaySound(nil, key); return true end }
	end
	t[#t + 1] = { separator = true }
	t[#t + 1] = CopyGroupRow(key, "Sound", SOUND_KEYS)
	return t
end

-- Combined Shocks: how its icon shows the three shocks (one setting for the icon)
local function ShockRows()
	local function choice(text, field, list)
		return {
			text = text,
			value = function() return LabelOf(list, SP:ReadyReminderShockOpt(field)), false end,
			sub = function()
				local cur = SP:ReadyReminderShockOpt(field)
				local items = {}
				for _, c in ipairs(list) do
					local v = c[1]
					items[#items + 1] = { text = c[2], selected = cur == v, onClick = function()
						SP:ReadyReminderSetShockOpt(field, v); Row:Changed(true); return true
					end }
				end
				return items
			end,
		}
	end
	local style = SP:ReadyReminderShockOpt("shockIcon")
	local t = { choice("Shock Icon", "shockIcon", SHOCK_CHOICES) }
	if style == "one" then t[#t + 1] = choice("Shock", "shockPick", PICK_CHOICES) end
	if style ~= "split" then
		t[#t + 1] = {
			text = "Keep Showing The Last Shock",
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
		text = "Fade Instead of Hide", tip = FADE_TIP,
		value = function() return OnOff(on()), false end,
		sub = function()
			local isOn = on()
			local t = {
				{ text = "On", selected = isOn, onClick = function() return Set(key, "fadeInsteadOfHide", true) end },
				{ text = "Off", selected = not isOn, onClick = function() return Set(key, "fadeInsteadOfHide", false) end },
			}
			if isOn then
				local opacity = SliderRow(key, "Faded Opacity", "fadeOpacity", 0.05, 0.9, 0.05, 0.4, nil, true)
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
local BUFF_LOOK_CHOICES = { { "off", "Off" }, { "corner", "In The Icon's Corner" }, { "own", "As Its Own Icon" },
	{ "edge", "As An Edge Around The Icon" }, { "swap", "Replaces The Icon" } }
local BUFF_LOOK_SHORT = { off = "Off", corner = "Corner", own = "Own Icon", edge = "Edge", swap = "Replaces" }
local BUFF_CORNER_CHOICES = { { "tr", "Top Right" }, { "tl", "Top Left" }, { "br", "Bottom Right" }, { "bl", "Bottom Left" } }
local BUFF_SIDE_CHOICES = { { "above", "Above" }, { "below", "Below" }, { "left", "Left" }, { "right", "Right" },
	{ "spot", "In Its Own Spot" } }
local BUFF_TIPS = {
	show = "Where the buff shows while it's on you. Replaces The Icon: the buff's own picture takes this icon's place while it's on. It stays on screen while this icon hides between casts, except as an edge or a replacement (they need the icon) and in a grid (there a hidden icon's place goes to the next icon; In Its Own Spot still stays). In a grid its own icon goes In Its Own Spot, since next to this icon is the next icon. Off: nothing changes.",
	corner = "Which corner of this icon the buff sits in.",
	cornerSize = "How big the buff is, as a share of this icon.",
	side = "Where the buff's own icon goes: next to this icon, or In Its Own Spot, anywhere on your screen (Move This Buff places it). In its own spot it shows even with this icon hidden.",
	ownSize = "How big the buff's icon is, as a share of this icon.",
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
	local never = SP:ReadyReminderShowOf(key) == "flash"
	local side = Opt(key, "buffSide") or "above"
	local grid = ShamanPower_ReadyReminders and ShamanPower_ReadyReminders.arrange == "grid"
	if never and (look == "corner" or look == "edge" or look == "swap" or (look == "own" and side ~= "spot")) then
		t[#t + 1] = { text = "Show: Never keeps this icon off your screen:", disabled = true }
		t[#t + 1] = { text = "the buff shows only In Its Own Spot.", disabled = true }
		t[#t + 1] = { separator = true }
	elseif grid and look == "own" and side ~= "spot" then
		t[#t + 1] = { text = "In a grid the icons sit side by side:", disabled = true }
		t[#t + 1] = { text = "the buff's own icon shows only In Its Own Spot.", disabled = true }
		t[#t + 1] = { separator = true }
	end
	t[#t + 1] = {
		text = "Show The Buff", tip = BUFF_TIPS.show,
		value = function()
			local cur = Opt(key, "buffLook") or "off"
			return LabelOf(BUFF_LOOK_CHOICES, cur), cur ~= "off"
		end,
		sub = function()
			local cur = Opt(key, "buffLook") or "off"
			local items = {}
			for _, c in ipairs(never and NeverChoices(BUFF_LOOK_CHOICES, cur) or BUFF_LOOK_CHOICES) do
				local v = c[1]
				items[#items + 1] = { text = c[2], selected = cur == v, onClick = function()
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
		row = ChoiceRow(key, "Corner", "buffCorner", BUFF_CORNER_CHOICES, "tr"); row.tip = BUFF_TIPS.corner; t[#t + 1] = row
		row = SliderRow(key, "Size", "buffSize", 0.3, 0.7, 0.05, 0.45, nil, true); row.tip = BUFF_TIPS.cornerSize; t[#t + 1] = row
	elseif look == "own" then
		row = ChoiceRow(key, "Side", "buffSide", never and NeverChoices(BUFF_SIDE_CHOICES, side)
			or grid and GridSides(BUFF_SIDE_CHOICES, side) or BUFF_SIDE_CHOICES, "above")
		row.tip = BUFF_TIPS.side; t[#t + 1] = row
		row = SliderRow(key, "Size", "buffOwnSize", 0.3, 1, 0.05, 1, nil, true); row.tip = BUFF_TIPS.ownSize; t[#t + 1] = row
		if Opt(key, "buffSide") == "spot" and SP.ReadyReminderBuffMove then
			t[#t + 1] = { text = "Move This Buff", tip = BUFF_TIPS.move,
				onClick = function() SP:ReadyReminderBuffMove(key); return false end }
		end
	elseif look == "edge" then
		row = ColorRow(key, entry, "Edge Color", "buffEdgeColor", 0, 0, 1); row.tip = BUFF_TIPS.edge; t[#t + 1] = row
	end
	if look ~= "off" and info.timed then
		row = OnOffRow(key, "Time Left", "buffTime", true); row.tip = BUFF_TIPS.time; t[#t + 1] = row
		if Opt(key, "buffTime") ~= false then
			row = SliderRow(key, "Time Turns Gold Under", "buffGoldUnder", 0, 10, 1, 3, function(v) return Secs(v, "Never") end)
			row.tip = BUFF_TIPS.gold
			t[#t + 1] = row
		end
	end
	return t
end

-- the group's row: the buff's name, and the look it shows in (Off to start)
local function BuffGroup(key, entry, info)
	return {
		text = info.name .. " Buff",
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
	local items = {
		entry.weaponSet and { text = "Show", value = function() return "Always", false end,
		  tip = "Weapon Set is always on screen: it shows what you hold. Only In Combat below hides it out of a fight." }
		or entry.imbue and { text = "Show", value = function() return "Only When Missing", false end,
		  tip = "Weapon Imbue shows while an imbue is missing (the main hand; with two weapons, either hand) and hides while your imbues are on. That is all it does." }
		or { text = "Show",
		  value = function() return LabelOf(SHOW_CHOICES, SP:ReadyReminderShowOf(key)), false end,
		  sub = function()
			local cur = SP:ReadyReminderShowOf(key)
			local list = {}
			for _, c in ipairs(SHOW_CHOICES) do
				local v = c[1]
				list[#list + 1] = { text = c[2], selected = cur == v, onClick = function()
					SP:ReadyReminderSetShow(key, v); Row:Changed(true); return true
				end }
			end
			return list
		  end },
		OnOffRow(key, "Only In Combat", "onlyInCombat"),
	}
	-- Rows placement: the row it sits on (Not On A Row: off your screen)
	if SP.ReadyRowsOn and SP:ReadyRowsOn() then
		items[#items + 1] = { text = "On Row",
			value = function()
				local i = SP:ReadyRowOf(key)
				local r = i and SP:ReadyRows()[i]
				return r and (r.name or ("Row " .. i)) or "Not On A Row", i ~= nil
			end,
			tip = "The row this icon sits on. Not On A Row: off your screen until you put it on one (drag it onto a row in the Spells row, or pick one here).",
			sub = function()
				local cur = SP:ReadyRowOf(key)
				local list = {}
				for i, r in ipairs(SP:ReadyRows()) do
					list[#list + 1] = { text = r.name or ("Row " .. i), selected = cur == i, onClick = function()
						SP:ReadyRowPlace(key, i, nil); Row:Changed(false); return false
					end }
				end
				list[#list + 1] = { text = "Remove From Row", selected = cur == nil, onClick = function()
					SP:ReadyRowRemove(key); Row:Changed(false); return false
				end }
				return list
			end }
	end
	-- right under it: only does something while Only In Combat is on, and the icon is ever on screen
	if Opt(key, "onlyInCombat") and show ~= "flash" then items[#items + 1] = FadeRow(key) end
	if entry.combo then items[#items + 1] = Group("Shocks", function() return ShockRows() end) end
	items[#items + 1] = Group("Look", function() return LookRows(key, entry) end)
	if entry.weaponSet then items[#items + 1] = Group("Weapon Set", function() return WeaponSetRows(key, entry) end) end   -- (A28)
	items[#items + 1] = Group(entry.weaponSet and "Effect While Holding" or entry.imbue and "When Missing" or "When Ready", function() return ReadyRows(key, entry) end)
	-- A25: a spell whose cooldown resets (Stormstrike on WoW: Forever: a tank's dodge or parry)
	if entry.reset and SPCompat and SPCompat.FOREVER then
		items[#items + 1] = Group("When The Cooldown Resets", function() return ResetRows(key, entry) end)
	end
	-- D52: the buff this spell puts on you (only a spell that puts one on you, in this game)
	local buffInfo = SP.ReadyReminderBuffInfo and SP:ReadyReminderBuffInfo(key)
	if buffInfo then items[#items + 1] = BuffGroup(key, entry, buffInfo) end
	-- the cooling settings only do something while it shows on cooldown
	if not entry.weaponSet and (show == "cooldown" or show == "always" or show == "always_bright") then
		items[#items + 1] = Group("While On Cooldown", function() return CoolRows(key, entry) end)
	end
	if not entry.imbue and not entry.weaponSet then items[#items + 1] = Group("Out of Range", function() return RangeRows(key, entry) end) end
	items[#items + 1] = Group("Sound", function() return SoundRows(key, entry) end)
	items[#items + 1] = { separator = true }
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
		sub = function() return CopyItems(key) end }
	items[#items + 1] = { separator = true }
	local on = SP.ReadyReminderOn(entry) and true or false
	items[#items + 1] = { text = on and "Hide This Icon" or "Show This Icon",
		onClick = function() SP:ReadyReminderSetSpell(key, not on); Row:Changed(false) end }
	items[#items + 1] = { text = "Reset This Icon", disabled = not SP:ReadyReminderHasOwn(key),
		onClick = function() SP:ReadyReminderResetIcon(key); Row:Changed(false) end }
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
--   out in it), or onto a row and between rows (Rows).
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
		return "|cff3FA9F5DRAG|r a spell onto a row, or between rows. |cff3FA9F5CLICK|r a spell to show or hide it."
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
	t[#t + 1] = Menu.Slider("Spacing", 0, 40, 1, function() return tonumber(r.spacing) or 8 end,
		function(v) SP:ReadyRowSet(i, "spacing", v); Row:Changed(true) end,
		function(v) return string.format("%d px", v) end, false,
		"The gap between this row's icons. 0 puts them side by side, touching.")
	t[#t + 1] = Menu.Choice("Direction", { { "row", "Row" }, { "column", "Column" } },
		function() return r.direction or "row", false end,
		function(v) SP:ReadyRowSet(i, "direction", v); Row:Changed(true); return true end,
		"A row runs right; a column runs down.")
	t[#t + 1] = { text = "Move This Row", tip = "Opens Unlock UI with just this row's box. Drag it where you want it, then press Done.",
		onClick = function() SP:ReadyRowMove(i); return false end }
	t[#t + 1] = SEP_ROW
	t[#t + 1] = { text = "Rename...", tip = "A box to type its new name in.", onClick = function() NameBox(i); return false end }
	t[#t + 1] = { text = "Delete This Row", tip = "Its spells go to Not On A Row (off your screen until you place them again).",
		onClick = function() SP:ReadyRowDelete(i); Row:Changed(false); return false end }
	return t
end
local function RowMenu(i, holder)
	if not SP:ReadyRows()[i] then return end
	ns.ContextMenu:Open(holder, { header = { text = RowName(i) }, items = function() return RowMenuItems(i) end })
end

local LABELS = { off = "NOT SHOWN", none = "NOT ON A ROW" }
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
			if SP.ReadyReminderOn(e) then
				i = i + 1
				out[#out + 1] = e
				meta[e.key] = { group = "g" .. ceil(i / per), gap = ((i - 1) % per ~= 0) and gap or 0 }
			end
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
			if e then
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
end

-- a drop. Free and Grid: the order. Rows: onto the row of the line under the cursor,
-- before the first icon on it whose middle is right of the cursor
local function Move(e, to)
	if e.empty then return end
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
	local cx, cy = Row:CursorInFrame()
	local sx, sy, list = Row.slotX, Row.slotY, Row.list
	if not (sx and sy) then return end
	local lineY, best
	for i = 1, #list do
		local d = math.abs(cy - (sy[i] + PLATE / 2))
		if not best or d < best then best, lineY = d, sy[i] end
	end
	if lineY == nil then return end
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
	if not rowIndex then return end
	SP:ReadyRowPlace(e.key, rowIndex, at)
end

Row = ns.IconRow.New({
	caption = Caption,
	hint = "Click: show or hide it\nRight-click: its settings\nDrag: its order, or onto a row",
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
	movable = function(e) return not e.empty end,
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
	t[#t + 1] = { text = "Ready Flash", value = function() return OnOff(on), on end,
		sub = function() return {
			{ text = "On", selected = on, onClick = function() return FSet(key, "flash", true) end },
			{ text = "Off", selected = not on, onClick = function() return FSet(key, "flash", false) end },
		} end }
	t[#t + 1] = { text = "Flash Early", tip = "Seconds before this spell is ready, once per cooldown. Off: the tab's Flash Early.",
		slider = { min = 0, max = 5, step = 0.5,
			get = function() return tonumber(SP:ReadyReminderOwnOpt(key, "flashEarly")) or 0 end,
			set = function(v) SP:ReadyReminderSetIconOpt(key, "flashEarly", v > 0 and v or nil); FlashRow:Repaint() end,
			format = function(v) return Secs(v, "Off") end } }
	t[#t + 1] = { separator = true }
	t[#t + 1] = { text = "Spot", value = function() return own and "Its Own" or "Shared", own end,
		tip = "Where this spell's flash plays: the shared spot, or a spot of its own (Unlock UI opens with its box; drop it where you want it).",
		sub = function() return {
			{ text = "The Shared Spot", selected = not own, onClick = function() SP:ReadyFlashUseShared(key); FlashRow:Changed(true); return true end },
			{ text = "Its Own Spot", selected = own, onClick = function() if SP.ReadyFlashMoveSpell then SP:ReadyFlashMoveSpell(key) end; return false end },
		} end }
	if own then
		t[#t + 1] = { text = "Move This Flash", tip = "Unlock UI with just this spell's flash box.",
			onClick = function() if SP.ReadyFlashMoveSpell then SP:ReadyFlashMoveSpell(key) end; return false end }
		t[#t + 1] = SliderRow(key, "Size", "flashSize", 48, 200, 4, SP.ReadyReminderIconOpt and (tonumber(SP:ReadyReminderIconOpt(key, "flashSize")) or 96) or 96)
	end
	t[#t + 1] = { separator = true }
	t[#t + 1] = { text = "Test This Flash", onClick = function() if SP.ReadyFlashTest then SP:ReadyFlashTest(key) end; return true end }
	return t
end
FlashRow = ns.IconRow.New({
	caption = "|cff3FA9F5CLICK|r a spell to flash it when it is ready. |cff3FA9F5RIGHT-CLICK|r it for its own spot, its size there and Flash Early. |cff3FA9F5Dark|r spells aren't learned yet.",
	hint = "Click: flash it when ready\nRight-click: its own spot and more",
	list = function(out) for _, e in ipairs(Known(flashList)) do out[#out + 1] = e end end,
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
	caption = "These spells are on no row, so they are off your screen. |cff3FA9F5CLICK|r one to put it on the last row. |cff3FA9F5RIGHT-CLICK|r it for its settings.",
	hint = "Click: put it on the last row\nRight-click: its settings",
	list = function(out)
		if Mode() ~= "rows" then return end
		for _, e in ipairs(Known(unplacedList)) do
			if not SP:ReadyRowOf(e.key) then out[#out + 1] = e end
		end
	end,
	textures = function(e, out) return SP:ReadyReminderIconTextures(e.key, out) end,
	shown = function() return false end,
	learned = function(e) return SP.ReadyReminderKnown(e) and true or false end,
	hasOwn = function(e) return SP:ReadyReminderHasOwn(e.key) and true or false end,
	tooltip = function() return "Off your screen: it is on no row. Click to put it on the last row." end,
	toggle = function(e)
		SP:ReadyRowPlace(e.key, nil, nil)
		if not SP.ReadyReminderOn(e) then SP:ReadyReminderSetSpell(e.key, true) end
	end,
	menu = function(e) return MenuItems(e.key) end,
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
local NOTICE_TEXT = "Ready Reminders has moved to a per-spell settings menu."

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
