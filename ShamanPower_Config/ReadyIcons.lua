-- ShamanPower_Config :: ReadyIcons
-- Ready Reminders' settings page (D40, 2026-10-02): the Spells row and, for players
-- updating, the "settings moved" notice. The Spells row shows every Ready Reminder
-- spell this game version has, learned or not (not learned: dark), in the list's
-- order, as 36 px spell icons on thin plates. A hidden one is gray and dim; a small
-- accentHi corner marks an icon with settings of its own. Left-click: show or hide
-- it. Right-click: EVERY setting of that spell, in ns.ContextMenu, grouped (Look,
-- When Ready, While On Cooldown, Out of Range, Sound, Ready Flash), with sliders
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
if not (Core and SP) then return end

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
local CAPTION = "Click a spell to show or hide it. Right-click it for its settings. Dark spells aren't learned yet."
local NOT_LEARNED_SHADE = 0.3   -- a spell not learned yet: gray and dark

local Row = { buttons = {}, list = {}, byKey = {} }
ns.CustomRows.readyIcons = Row

-- ---------------------------------------------------------------------------
-- Labels
-- ---------------------------------------------------------------------------
local SHOW_CHOICES = {
	{ "ready", "Only When Ready" }, { "cooldown", "Only While On Cooldown" },
	{ "always_bright", "Always (Sweep + Countdown)" }, { "always", "Always, Dimmed While On Cooldown" },
	{ "flash", "Never (Ready Flash Only)" },
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

local function PaintButton(b)
	local entry = b.entry
	if not entry then return end
	local on = SP.ReadyReminderOn(entry) and true or false
	local learned = SP.ReadyReminderKnown(entry) and true or false
	local n = SP:ReadyReminderIconTextures(entry.key, texOut)
	local shade = 1
	if not learned then shade = NOT_LEARNED_SHADE elseif not on then shade = HIDDEN_SHADE end
	for i = 1, 3 do
		local t = b.icons[i]
		if i <= n then
			t:ClearAllPoints()
			t:SetSize(ICON / n, ICON)
			t:SetPoint("TOPLEFT", b, "TOPLEFT", 2 + (i - 1) * ICON / n, -2)
			t:SetTexture(texOut[i])
			t:SetTexCoord(0.08 + 0.84 * (i - 1) / n, 0.08 + 0.84 * i / n, 0.08, 0.92)
			t:SetDesaturated(not (on and learned))
			t:SetVertexColor(shade, shade, shade)
			t:Show()
		else
			t:Hide()
		end
	end
	b.corner:SetShown(SP:ReadyReminderHasOwn(entry.key) and true or false)
	b.openEdge:SetShown(Row.openKey == entry.key)
	Core:AttachTooltip(b, entry.name, TooltipBody(entry), "Click: show or hide it\nRight-click: its settings")
end

local function ButtonClick(b, button)
	local entry = b.entry
	if not entry then return end
	if button == "RightButton" then
		Row:OpenMenu(entry.key)
		return
	end
	SP:ReadyReminderSetSpell(entry.key, not SP.ReadyReminderOn(entry))
	Row:Changed(false)
end

local function NewButton(parent)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(PLATE, PLATE)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	local plate = SP.Brand and SP.Brand.plate or { 5 / 255, 7 / 255, 10 / 255 }   -- #05070A, the totem boxes' plate
	b.plate = b:CreateTexture(nil, "BACKGROUND")
	b.plate:SetAllPoints(b)
	b.plate:SetColorTexture(plate[1], plate[2], plate[3], 1)
	b.icons = {}
	for i = 1, 3 do   -- one icon, or Combined Shocks' slices
		local t = b:CreateTexture(nil, "ARTWORK")
		t:Hide()
		b.icons[i] = t
	end
	-- hover: the plate's edge turns accent, as a control's border does
	b.hoverEdge = CreateFrame("Frame", nil, b)
	b.hoverEdge:SetAllPoints(b)
	b.hoverEdge:SetFrameLevel(b:GetFrameLevel() + 1)
	Core:MakeBorder(b.hoverEdge, "accent", 1)
	b.hoverEdge:Hide()
	-- its menu is open: a 2 px accentHi outline
	b.openEdge = CreateFrame("Frame", nil, b)
	b.openEdge:SetAllPoints(b)
	b.openEdge:SetFrameLevel(b:GetFrameLevel() + 2)
	Core:MakeBorder(b.openEdge, "accentHi", 2)
	b.openEdge:Hide()
	-- settings of its own: an accentHi square in the plate's top right corner, edged in plate black
	b.corner = CreateFrame("Frame", nil, b)
	b.corner:SetSize(CORNER, CORNER)
	b.corner:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, 0)
	b.corner:SetFrameLevel(b:GetFrameLevel() + 3)
	local edge = b.corner:CreateTexture(nil, "ARTWORK")
	edge:SetAllPoints(b.corner)
	edge:SetColorTexture(plate[1], plate[2], plate[3], 1)
	local fill = b.corner:CreateTexture(nil, "OVERLAY")
	fill:SetPoint("TOPLEFT", b.corner, "TOPLEFT", 1, -1)
	fill:SetPoint("BOTTOMRIGHT", b.corner, "BOTTOMRIGHT", -1, 1)
	fill:SetColorTexture(Core:Color("accentHi"))
	b.corner:Hide()
	b:SetScript("OnClick", ButtonClick)
	b:SetScript("OnEnter", function(self) self.hoverEdge:Show() end)
	b:SetScript("OnLeave", function(self) self.hoverEdge:Hide() end)
	return b
end

-- every spell this game version has, in the list's order (learned or not)
local function Known(out)
	wipe(out)
	for _, entry in ipairs(SP.ReadyReminderSpells) do
		if SP.ReadyReminderUsable(entry) then out[#out + 1] = entry end
	end
	return out
end

local scratch = {}
function Row:ListChanged()
	Known(scratch)
	if #scratch ~= #self.list then return true end
	for i = 1, #scratch do if scratch[i] ~= self.list[i] then return true end end
	return false
end

function Row:Repaint()
	for _, b in ipairs(self.buttons) do
		if b:IsShown() then PaintButton(b) end
	end
end

-- a setting changed here: the icons repainted now, then the page (the preview).
-- keepMenu: the menu stays open, even if the page lays itself out again (it opens
-- again on the same rows)
function Row:Changed(keepMenu)
	self:Repaint()
	local fn = self.onChanged
	if not fn then return end
	self.writing = keepMenu and true or false
	local ok, err = pcall(fn)
	self.writing = false
	if not ok then geterrorhandler()(err) end
end

-- a setting changed anywhere (the page, a theme, an import, the setup tour)
function Row:OnSettingsChanged()
	if not (self.frame and self.frame:IsVisible()) then return end
	if self:ListChanged() then   -- a spell new to the list: the page lays itself out again
		local cfg = _G.ShamanPowerConfig
		if cfg and cfg.RefreshCurrent then cfg:RefreshCurrent() end
		return
	end
	self:Repaint()
	if self.openKey and ns.ContextMenu:IsOpen() then ns.ContextMenu:Refresh() end
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
local READY_KEYS = { "readyEffect", "glowColor" }
local COOL_KEYS = { "dimOpacity", "desaturate", "sweepStyle", "sweepDirection", "barStyle", "barHeight", "barColor", "showCountdown",
	"textPosition", "textSize", "countdownUnder" }
local RANGE_KEYS = { "outOfRange", "rangeLook", "rangeColor" }
local SOUND_KEYS = { "soundOnReady", "soundName", "soundVolume", "soundMinCooldown" }
local FLASH_KEYS = { "flash", "flashAnim", "flashSize", "flashHold", "flashEarly", "flashName", "flashMin" }
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
	local name = SP:ReadyReminderShowOf(key) == "cooldown" and "Effect While Shown" or "Ready Effect"
	local t = { ChoiceRow(key, name, "readyEffect", EFFECT_CHOICES, "glow") }
	if fx == "glow" or fx == "both" then
		t[#t + 1] = ColorRow(key, entry, "Glow Color", "glowColor", 0.3, 0.8, 1.0)
		if SP.GlowShapeValues and SP.SetGlowShape then
			t[#t + 1] = SharedRow("Glow Shape", function() return SP:GlowShapeValues() end,
				function() return SP.opt and SP.opt.glowShape or "default" end, function(v) SP:SetGlowShape(v) end)
		end
	end
	t[#t + 1] = { separator = true }
	t[#t + 1] = CopyGroupRow(key, "When Ready", READY_KEYS)
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

local function SoundRows(key)
	local t = { OnOffRow(key, "Play Sound", "soundOnReady") }
	if Opt(key, "soundOnReady") then
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
		if not Opt(key, "ownSound") then
			t[#t + 1] = SliderRow(key, "Only For Cooldowns Over", "soundMinCooldown", 0, 300, 5, 20, function(v) return Secs(v, "Always") end)
		end
		t[#t + 1] = { text = "Test Sound", onClick = function() SP:ReadyReminderPlaySound(nil, key); return true end }
	end
	t[#t + 1] = { separator = true }
	t[#t + 1] = CopyGroupRow(key, "Sound", SOUND_KEYS)
	return t
end

local function FlashRows(key)
	local t = { OnOffRow(key, "Ready Flash", "flash") }
	if Opt(key, "flash") then
		t[#t + 1] = ChoiceRow(key, "Animation", "flashAnim", ANIM_CHOICES, "grow")
		t[#t + 1] = SliderRow(key, "Flash Size", "flashSize", 48, 200, 4, 96)
		t[#t + 1] = SliderRow(key, "Time On Screen", "flashHold", 0.5, 3, 0.1, 1, function(v) return Secs(v) end)
		t[#t + 1] = SliderRow(key, "Flash Early", "flashEarly", 0, 5, 0.5, 0, function(v) return Secs(v, "Off") end)
		t[#t + 1] = OnOffRow(key, "Show Spell Name", "flashName")
		-- a flash turned on in this menu always plays: the minimum only filters the old default
		if not Opt(key, "ownFlash") then
			t[#t + 1] = SliderRow(key, "Only For Cooldowns Over", "flashMin", 0, 120, 5, 10, function(v) return Secs(v, "Always") end)
		end
		t[#t + 1] = { separator = true }
		t[#t + 1] = { text = "Test Flash", onClick = function() if SP.ReadyFlashTest then SP:ReadyFlashTest(key) end; return true end }
		t[#t + 1] = { text = "Move This Flash", onClick = function() if SP.ReadyFlashMoveSpell then SP:ReadyFlashMoveSpell(key) end; return false end }
		if SP:ReadyFlashHasOwnSpot(key) then
			t[#t + 1] = { text = "Use Shared Spot", onClick = function() SP:ReadyFlashUseShared(key); Row:Changed(true); return true end }
		end
	end
	t[#t + 1] = { separator = true }
	t[#t + 1] = CopyGroupRow(key, "Ready Flash", FLASH_KEYS)
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
	for _, e in ipairs(Row.list) do
		if e.key ~= key then
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
	{ "edge", "As An Edge Around The Icon" } }
local BUFF_LOOK_SHORT = { off = "Off", corner = "Corner", own = "Own Icon", edge = "Edge" }
local BUFF_CORNER_CHOICES = { { "tr", "Top Right" }, { "tl", "Top Left" }, { "br", "Bottom Right" }, { "bl", "Bottom Left" } }
local BUFF_SIDE_CHOICES = { { "above", "Above" }, { "below", "Below" }, { "left", "Left" }, { "right", "Right" },
	{ "spot", "In Its Own Spot" } }
local BUFF_TIPS = {
	show = "Where the buff shows while it's on you. It stays on screen while this icon hides between casts (the edge needs the icon). Off: nothing changes.",
	corner = "Which corner of this icon the buff sits in.",
	cornerSize = "How big the buff is, as a share of this icon.",
	side = "Where the buff's own icon goes: next to this icon, or In Its Own Spot, anywhere on your screen (Move This Buff places it). In its own spot it shows even with this icon hidden.",
	ownSize = "How big the buff's icon is, as a share of this icon.",
	move = "Opens Unlock UI with just this buff's box. Drag it where you want it, then press Done.",
	edge = "The edge's color while the buff is on you. It starts as WoW's mana-bar blue.",
	time = "The seconds the buff has left.",
	gold = "The time turns WoW's gold for the buff's last seconds. Never: it stays white.",
}

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
	t[#t + 1] = {
		text = "Show The Buff", tip = BUFF_TIPS.show,
		value = function()
			local cur = Opt(key, "buffLook") or "off"
			return LabelOf(BUFF_LOOK_CHOICES, cur), cur ~= "off"
		end,
		sub = function()
			local cur = Opt(key, "buffLook") or "off"
			local items = {}
			for _, c in ipairs(BUFF_LOOK_CHOICES) do
				local v = c[1]
				items[#items + 1] = { text = c[2], selected = cur == v, onClick = function() return Set(key, "buffLook", v) end }
			end
			return items
		end,
	}
	local row
	if look == "corner" then
		row = ChoiceRow(key, "Corner", "buffCorner", BUFF_CORNER_CHOICES, "tr"); row.tip = BUFF_TIPS.corner; t[#t + 1] = row
		row = SliderRow(key, "Size", "buffSize", 0.3, 0.7, 0.05, 0.45, nil, true); row.tip = BUFF_TIPS.cornerSize; t[#t + 1] = row
	elseif look == "own" then
		row = ChoiceRow(key, "Side", "buffSide", BUFF_SIDE_CHOICES, "above"); row.tip = BUFF_TIPS.side; t[#t + 1] = row
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
	for _, e in ipairs(Row.list) do if e.key == key then entry = e break end end
	if not entry then return {} end
	local show = SP:ReadyReminderShowOf(key)
	local items = {
		{ text = "Show",
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
	-- right under it: only does something while Only In Combat is on, and the icon is ever on screen
	if Opt(key, "onlyInCombat") and show ~= "flash" then items[#items + 1] = FadeRow(key) end
	if entry.combo then items[#items + 1] = Group("Shocks", function() return ShockRows() end) end
	items[#items + 1] = Group("Look", function() return LookRows(key, entry) end)
	items[#items + 1] = Group("When Ready", function() return ReadyRows(key, entry) end)
	-- D52: the buff this spell puts on you (only a spell that puts one on you, in this game)
	local buffInfo = SP.ReadyReminderBuffInfo and SP:ReadyReminderBuffInfo(key)
	if buffInfo then items[#items + 1] = BuffGroup(key, entry, buffInfo) end
	-- the cooling settings only do something while it shows on cooldown
	if show == "cooldown" or show == "always" or show == "always_bright" then
		items[#items + 1] = Group("While On Cooldown", function() return CoolRows(key, entry) end)
	end
	items[#items + 1] = Group("Out of Range", function() return RangeRows(key, entry) end)
	items[#items + 1] = Group("Sound", function() return SoundRows(key) end)
	items[#items + 1] = Group("Ready Flash", function() return FlashRows(key) end)
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

-- path: the submenus to open again (after the page laid itself out)
function Row:OpenMenu(key, path)
	local b = self.byKey[key]
	if not (b and b.entry and b:IsVisible()) then return end
	local entry = b.entry
	local icons = {}
	local n = SP:ReadyReminderIconTextures(key, texOut)
	for i = 1, n do icons[i] = texOut[i] end
	self.openKey = key
	PaintButton(b)
	ns.ContextMenu:Open(b, {
		header = { text = entry.name, icons = icons },
		items = function() return MenuItems(key) end,
		onClose = function()
			if Row.openKey == key then Row.openKey = nil end
			Row:Repaint()
		end,
	})
	if path and #path > 0 then ns.ContextMenu:ShowPath(path) end
end

-- ---------------------------------------------------------------------------
-- The row (ns.CustomRows: drawn by Window.lua's page packer, released on every redraw)
-- ---------------------------------------------------------------------------
local function OpenQueued()
	local q = Row.queued
	Row.queued = nil
	if q then Row:OpenMenu(q.key, q.path) end
end

function Row:Render(body, x, y, width, onChanged)
	if not (SP.ReadyReminderSpells and SP.ReadyReminderIconTextures and SP.ReadyReminderKnown) then return nil, 0 end
	self.onChanged = onChanged
	if not self.watching and SP.ReadyReminderWatch then
		self.watching = true
		SP:ReadyReminderWatch(function() Row:OnSettingsChanged() end)
	end
	-- the menu closes with the settings window (hooked once: never SetScript on it)
	if not self.hooked and _G.ShamanPowerConfigUIFrame then
		self.hooked = true
		_G.ShamanPowerConfigUIFrame:HookScript("OnHide", function()
			Row.reopen = nil
			if Row.openKey and ns.ContextMenu:IsOpen() then ns.ContextMenu:Close() end
		end)
	end

	local f = self.frame
	if not f then
		f = CreateFrame("Frame", nil, body)
		f.caption = f:CreateFontString(nil, "OVERLAY")
		f.caption:SetFontObject(Core.fonts.rowDim)
		f.caption:SetJustifyH("LEFT")
		f.caption:SetWordWrap(true)
		f.spNoCull = true   -- (redrawn by its own watcher, which skips a hidden row)
		self.frame = f
	end
	f:SetParent(body)
	f:ClearAllPoints()
	f:SetPoint("TOPLEFT", body, "TOPLEFT", x or 0, -(y or 0))
	f:SetWidth(width)
	f:Show()

	local list = Known(self.list)
	wipe(self.byKey)
	local padX = PAD_X + (ns.Widgets and tonumber(ns.Widgets.CARD_INSET) or 0)   -- in line with the rows' labels
	local perRow = max(1, floor((width - padX * 2 + (PITCH - PLATE)) / PITCH))
	for i, entry in ipairs(list) do
		local b = self.buttons[i] or NewButton(f)
		self.buttons[i] = b
		b.entry = entry
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", f, "TOPLEFT", padX + ((i - 1) % perRow) * PITCH, -(PAD_TOP + floor((i - 1) / perRow) * PITCH))
		b:Show()
		self.byKey[entry.key] = b
	end
	for i = #list + 1, #self.buttons do
		local b = self.buttons[i]
		b.entry = nil
		b:Hide()
	end
	local iconsH = max(1, ceil(#list / perRow)) * PITCH - (PITCH - PLATE)
	f.caption:ClearAllPoints()
	f.caption:SetPoint("TOPLEFT", f, "TOPLEFT", padX, -(PAD_TOP + iconsH + CAPTION_GAP))
	f.caption:SetWidth(width - padX * 2)
	f.caption:SetText(CAPTION)
	local h = PAD_TOP + iconsH + CAPTION_GAP + ceil(f.caption:GetStringHeight()) + PAD_BOTTOM
	f:SetHeight(h)
	self:Repaint()

	-- a menu to open: asked for (SP:ReadyReminderOpenIconMenu), or open before the page
	-- laid itself out after one of its own choices. Next frame: the icons are placed.
	local r = self.reopen
	self.reopen = nil
	if r and (not r.at or GetTime() - r.at < 2) and self.byKey[r.key] then
		self.queued = r
		C_Timer.After(0, OpenQueued)
	end
	return f, h + ROW_GAP
end

function Row:Release()
	if self.openKey and ns.ContextMenu:IsOpen() then
		-- a redraw made by one of the menu's own choices: open it again when drawn
		if self.writing then self.reopen = { key = self.openKey, path = ns.ContextMenu:OpenPath() } end
		ns.ContextMenu:Close()
	elseif self.queued then
		self.reopen = self.queued   -- drawn twice in one go (D42's gray page): it still opens after the second
	end
	self.openKey, self.queued = nil, nil
	if self.frame then self.frame:Hide() end
	for _, b in ipairs(self.buttons) do
		Core:HideTooltipFor(b)
		b.hoverEdge:Hide()
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
