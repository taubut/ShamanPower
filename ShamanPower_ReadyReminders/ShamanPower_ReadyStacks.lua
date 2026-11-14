-- ============================================================================
-- ShamanPower Ready Reminders: Maelstrom Weapon (3.0.9.2, WoW: Forever; sheet A55)
-- A Ready Reminder that shows your stacks of a buff (Maelstrom Weapon: 1 to 5)
-- instead of a cooldown, in the Look picked in its right-click menu:
--   number    Icon + Stack Number: the reminder's icon with the count over it
--   bar       Charge Bar: the icon with a 5-part bar under it, as Shield Charges draws
--   wings     Wings: Blizzard's own Maelstrom pictures, a piece more per stack and the
--             full emblem at 5 (the game's files: textures/spellactivationoverlays)
--   fill      Fill: Blizzard's full emblem, gray, lit from the bottom a fifth per stack
--   iconfill  Fill The Icon: the spell's icon, gray, its color rising a fifth per stack
--   storm     Storm Glow: the icon's glow, brighter with every stack
-- 5 stacks is this reminder's "ready": At 5 Stacks plays its Effect (Glow, Pulse,
-- both; a Wings or Fill emblem glows or pulses itself). Time Left adds the buff's
-- time as a number, or the look going gray from the top as it runs out (Drain).
--
-- The game draws all of it, in a fight and out of one, and nothing hidden is read.
-- Every part hangs on the button of an AuraContainer slot filtered to the buff: the
-- game shows that button only while the buff is on you, writes the count (a number
-- formatter decides the text and its color), fills the stack bars, and counts the
-- time. A part from N stacks up sits on a StatusBar the game shows only at N or more
-- (SetApplicationBar's own switch: shown while the stacks reach its minimum). A part
-- for exactly N stacks hangs on a count text the game writes only at N: anchored to
-- that text's sides, it has a width only then (Shield Charges' Storm look does the
-- same). It is all built out of combat (a setting changed in a fight lands after it);
-- in a fight only a container's own switch changes (Glow Only In Combat).
-- Out of combat the stacks are readable, so the reminder hides while it has nothing
-- to show (no hole in a grid or a row then); in a fight it stays on screen and the
-- game decides what is drawn. The settings previews, the setup tour and Unlock UI
-- draw it with plain frames at a stack count of their own (Paint), from the same
-- description of each look.
-- The sound At 5 Stacks (3.0.9.9): every Ready Reminder's own ready sound (its Sound,
-- Volume, Hide In Town), the moment the stacks reach 5 (S.AtFive).
-- ============================================================================

local SP = ShamanPower
if not SP then return end
local API = SP.ReadyStacksAPI   -- the Ready Reminders file's own helpers (it loads first, shamans only)
if not API then return end

local IconOpt, color = API.IconOpt, API.color
local S = { stages = {} }
SP.ReadyStacks = S

local LOOKS = { number = true, bar = true, wings = true, fill = true, iconfill = true, storm = true, baronly = true }
-- three icons wide: a spot of their own (Charge Bar Only too: the bar alone, no emblem, no icon)
local WIDE = { wings = true, fill = true, baronly = true }
local SHOWS = { stacks = true, five = true, always = true }
local LEFTS = { off = true, number = true, drain = true }
-- Blizzard's own Maelstrom Weapon pictures, 256 x 128 (textures/spellactivationoverlays/
-- maelstrom_weapon_1 .. _4, then the whole maelstrom_weapon); each holds the ones before it
local PIECES = { 1028136, 1028137, 1028138, 1028139, 450927 }
local EMBLEM = 450927
local WIDE_W, WIDE_H = 3.125, 1.5625   -- the emblem's box, in icon sizes (150 x 75 at 48)
local WHITE = "Interface\\Buttons\\WHITE8X8"
local GLOW_FILE = "Interface\\SpellActivationOverlay\\IconAlert"
local DIM = 0.35   -- Show: Always, at 0 stacks (the page's own dimmed look)
local LEVEL = { main = 2, piece = 4, storm = 4, five = 6, fx = 10, shade = 12, text = 14 }   -- (over the stage; Drain's gray over the Effect)

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------
function S.Look(e) local v = IconOpt(e, "stackLook"); if LOOKS[v] then return v end return "number" end
function S.Show(e) local v = IconOpt(e, "stackShow"); if SHOWS[v] then return v end return "stacks" end
function S.Left(e) local v = IconOpt(e, "stackLeft"); if LEFTS[v] then return v end return "off" end
function S.NumberOn(e) return S.Look(e) == "number" or IconOpt(e, "stackNumber") == true end
-- Wings and Fill are three icons wide: a spot of their own, never on a row or in the grid
function S.Wide(e) return e ~= nil and e.stacks ~= nil and WIDE[S.Look(e)] == true end
-- the display's width and height, and the icon size it comes from
function S.Box(e)
	local s = IconOpt(e, "iconSize") or 48
	local look = S.Look(e)
	if look == "baronly" then   -- (Charge Bar Only: as wide as Wings, its Bar Height, else a third of Size)
		local bh = tonumber(IconOpt(e, "stackBarHeight")) or 0
		if bh <= 0 then bh = math.max(6, math.floor(s * 0.3 + 0.5)) end
		return math.floor(s * WIDE_W + 0.5), bh, s
	end
	if WIDE[look] then return math.floor(s * WIDE_W + 0.5), math.floor(s * WIDE_H + 0.5), s end
	return s, s, s
end
local function stackRGB(e) return color(IconOpt(e, "stackColor"), 0.35, 0.65, 1.0) end
local function fiveRGB(e) return color(IconOpt(e, "stackColor5"), 1, 0.82, 0) end
local function glowRGB(e) return color(IconOpt(e, "glowColor"), 0.3, 0.8, 1.0) end
local function glowShape(e) return IconOpt(e, "glowShape") or (SP.opt and SP.opt.glowShape) or "default" end
local function code(r, g, b)
	return string.format("|cff%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end
local texOut = {}
local function iconFile(e)
	local n = SP:ReadyReminderIconTextures(e.key, texOut)
	return (n > 0 and texOut[1]) or 237584   -- (Spell_Shaman_MaelstromWeapon)
end

-- Everything a look's parts are built from: a change means a new build (rare: a menu click)
local function signature(e)
	local w, h, s = S.Box(e)
	local r, g, b = stackRGB(e)
	local r5, g5, b5 = fiveRGB(e)
	local gr, gg, gb = glowRGB(e)
	local bc = IconOpt(e, "borderColor")
	return table.concat({ S.Look(e), S.Show(e), S.Left(e), tostring(S.NumberOn(e)), w, h, s,
		code(r, g, b), code(r5, g5, b5), code(gr, gg, gb), tostring(IconOpt(e, "readyEffect") or "glow"), glowShape(e),
		tostring(IconOpt(e, "glowThick")), tostring(IconOpt(e, "iconShape")), tostring(IconOpt(e, "hideBackground")),
		tostring(IconOpt(e, "hideBorder")), tostring(bc and (bc.r or bc[1])) .. tostring(bc and (bc.g or bc[2])) .. tostring(bc and (bc.b or bc[3])),
		tostring(SP.IconShapeOf and SP:IconShapeOf("ready")), tostring(iconFile(e)), tostring(IconOpt(e, "stackBarHeight")) }, "|")
end

-- ---------------------------------------------------------------------------
-- Number formatters (made once each): the count, and the "exactly N" gate's spacer
-- ---------------------------------------------------------------------------
local formatters = {}
local function newFormatter()
	local U = C_StringUtil
	if not (U and U.CreateNumericRuleFormatter) then return nil end
	local ok, f = pcall(U.CreateNumericRuleFormatter)
	if not (ok and f and f.AddBreakpoint) then return nil end
	return f
end
-- the stack count: white from 1 (a breakpoint at 1 is what draws a single stack at all), in
-- Color At 5 Stacks at 5; only = 5: nothing below 5 (Show: Only At 5 Stacks)
local function countFormatter(onlyFive, r5, g5, b5)
	local key = (onlyFive and "5" or "a") .. code(r5, g5, b5)
	local f = formatters[key]
	if f ~= nil then return f or nil end
	formatters[key] = false
	f = newFormatter()
	if not f then return nil end
	local ok = pcall(f.AddBreakpoint, f, { threshold = 0, format = "" })
	if ok and not onlyFive then ok = pcall(f.AddBreakpoint, f, { threshold = 1, format = "%d" }) end
	if ok then ok = pcall(f.AddBreakpoint, f, { threshold = 5, format = code(r5, g5, b5) .. "%d|r" }) end
	if not ok then return nil end
	formatters[key] = f
	return f
end
-- exactly n stacks: a spacer `w` wide at n, nothing at any other count
local function gateFormatter(n, w)
	local key = "g" .. n .. ":" .. w
	local f = formatters[key]
	if f ~= nil then return f or nil end
	formatters[key] = false
	f = newFormatter()
	if not f then return nil end
	local spacer = ("|T%s:2:%d|t"):format(WHITE, w)
	local ok = pcall(f.AddBreakpoint, f, { threshold = 0, format = "" })
		and pcall(f.AddBreakpoint, f, { threshold = n, format = spacer })
	if ok and n < 5 then ok = pcall(f.AddBreakpoint, f, { threshold = n + 1, format = "" }) end
	if not ok then return nil end
	formatters[key] = f
	return f
end

-- ---------------------------------------------------------------------------
-- The parts (the same for both ways of drawing)
-- ---------------------------------------------------------------------------
-- the Ready Reminder's own look: backing, icon, border (or a ring round a shaped icon)
local function plate(host, e, s, gray, alpha)
	local P = API.Buff.NewParts(host)
	local hideBg = IconOpt(e, "hideBackground") and true or false
	local ed = (s >= 24) and 2 or 1
	P.bg:SetColorTexture(0, 0, 0, 0.6); P.bg:SetShown(not hideBg)
	P.icon:ClearAllPoints()
	P.icon:SetPoint("TOPLEFT", P.art, "TOPLEFT", ed, -ed); P.icon:SetPoint("BOTTOMRIGHT", P.art, "BOTTOMRIGHT", -ed, ed)
	P.icon:SetTexture(iconFile(e)); P.icon:Show()
	if gray then P.icon:SetDesaturated(true); P.icon:SetVertexColor(0.55, 0.55, 0.55) end
	local own = IconOpt(e, "iconShape")
	API.Buff.Shape(P, own)
	local r, g, b = color(IconOpt(e, "borderColor"), 0.2, 0.7, 1.0)
	API.Buff.Edges(P, ed, ed, r, g, b, not hideBg and not IconOpt(e, "hideBorder"), own)
	P.text:Hide()
	SP:SPFontGameOwned(P.time)   -- (on the game's button: a font refresh waits out fights)
	if alpha then P.art:SetAlpha(alpha) end
	P.inset = ed
	return P
end
-- a frame of our own over the stage, `level` above it
local function layer(host, stage, level)
	local fr = CreateFrame("Frame", nil, host)
	fr:SetAllPoints(stage)
	fr:SetFrameLevel(stage:GetFrameLevel() + level)
	fr:EnableMouse(false)
	return fr
end
local function emblemTex(fr, file, dim)
	local t = fr:CreateTexture(nil, "ARTWORK")
	t:SetAllPoints(fr)
	t:SetTexture(file)
	if dim then t:SetDesaturated(true); t:SetVertexColor(dim, dim, dim) end
	return t
end
-- the glow round an icon (its Glow Shape, ADD, breathing as the reminder's glow does)
local function glowTex(fr, anchor, shape, r, g, b, lo, hi, period)
	local t = fr:CreateTexture(nil, "OVERLAY", nil, 1)
	t:SetPoint("TOPLEFT", anchor, "TOPLEFT", -10, 10); t:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 10, -10)
	t:SetTexture(GLOW_FILE)
	t:SetTexCoord(0.00781250, 0.50781250, 0.27734375, 0.52734375)
	if SP.PaintGlowShape then SP:PaintGlowShape(t, shape) end
	t:SetBlendMode("ADD")
	t:SetVertexColor(r, g, b)
	if lo then
		local ag = t:CreateAnimationGroup(); ag:SetLooping("REPEAT")
		local a1 = ag:CreateAnimation("Alpha"); a1:SetFromAlpha(lo); a1:SetToAlpha(hi); a1:SetDuration(period); a1:SetOrder(1)
		local a2 = ag:CreateAnimation("Alpha"); a2:SetFromAlpha(hi); a2:SetToAlpha(lo); a2:SetDuration(period); a2:SetOrder(2)
		ag:Play()
		t.ag = ag
	end
	return t
end
-- a picture breathing in and out (the reminder's Pulse: 1.12 over 0.45 s each way)
local function pulse(t)
	local ag = t:CreateAnimationGroup(); ag:SetLooping("REPEAT")
	local p1 = ag:CreateAnimation("Scale"); p1:SetScale(1.12, 1.12); p1:SetDuration(0.45); p1:SetOrder(1)
	local p2 = ag:CreateAnimation("Scale"); p2:SetScale(1 / 1.12, 1 / 1.12); p2:SetDuration(0.45); p2:SetOrder(2)
	ag:Play()
	t.ag = ag
	return t
end
-- the count over the look (Shield Charges' number font)
local function countText(fr, s, wide, barH)
	local fs = fr:CreateFontString(nil, "OVERLAY")
	local size = barH and math.max(8, math.floor(barH * 1.1 + 0.5)) or math.max(10, math.floor(s * 0.7 + 0.5))   -- (Charge Bar Only: the bar's height)
	SP:SetSPFont(fs, "charges", size, "OUTLINE")
	if barH then fs:SetPoint("CENTER", fr, "CENTER", 1, 0); fs:SetTextColor(1, 1, 1); return fs end
	fs:SetPoint("CENTER", fr, "CENTER", 1, wide and -math.floor(s * 0.1) or 0)
	fs:SetTextColor(1, 1, 1)
	return fs
end
-- the time left: in the icon's corner, or under the emblem's middle
local function timeText(fr, s, wide, barH)
	local fs = fr:CreateFontString(nil, "OVERLAY")
	SP:SetSPFont(fs, "alerts", math.max(10, math.floor(s * 0.30 + 0.5)), "OUTLINE")
	if barH then fs:SetPoint("LEFT", fr, "RIGHT", 4, 0); fs:SetTextColor(1, 1, 1); return fs end   -- (Charge Bar Only: beside it)
	if wide then fs:SetPoint("BOTTOM", fr, "BOTTOM", 0, 2) else fs:SetPoint("BOTTOMRIGHT", fr, "BOTTOMRIGHT", -2, 3) end
	fs:SetTextColor(1, 1, 1)
	return fs
end
-- a fill the stacks drive: from the bottom, cropped to the fill (one filled from its top edge
-- is stretched by the game instead, see TotemEngineSweepBar); the icon's copy oversized in a clip
-- so its untrimmed picture lines up with the trimmed icon
local function fillBar(fr, area, file, isIcon, iconW)
	local holder = area
	if isIcon then
		holder = CreateFrame("Frame", nil, fr)
		holder:SetAllPoints(area)
		holder:SetClipsChildren(true)
	end
	local sb = CreateFrame("StatusBar", nil, holder)
	if isIcon then
		local m = (0.08 / 0.84) * iconW
		sb:SetPoint("TOPLEFT", holder, "TOPLEFT", -m, m); sb:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", m, -m)
	else
		sb:SetAllPoints(area)
	end
	sb:SetOrientation("VERTICAL")
	sb:SetReverseFill(false)
	local style = Enum and Enum.StatusBarFillStyle and Enum.StatusBarFillStyle.Standard
	if sb.SetFillStyle then pcall(sb.SetFillStyle, sb, style or "STANDARD") end   -- (the game's enum where it has one)
	sb:SetStatusBarTexture(file)
	sb:SetMinMaxValues(0, 5); sb:SetValue(0)
	return sb
end
-- Charge Bar: 5 parts under the icon, the stack color, dark between the parts
local function stackBar(fr, stage, s, r, g, b, full)
	local bh = math.max(4, math.floor(s * 0.16 + 0.5))
	local sb = CreateFrame("StatusBar", nil, fr)
	sb:SetSize(s, bh)
	sb:SetPoint("TOP", stage, "BOTTOM", 0, -3)
	SP:SetSPStatusBarTexture(sb, "other", WHITE)
	sb:SetStatusBarColor(r, g, b)
	sb:SetMinMaxValues(0, 5); sb:SetValue(full and 5 or 0)
	local bg = sb:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(sb); bg:SetColorTexture(0, 0, 0, 0.6)
	local top = CreateFrame("Frame", nil, sb)
	top:SetAllPoints(sb); top:SetFrameLevel(sb:GetFrameLevel() + 2)
	for i = 1, 4 do
		local d = top:CreateTexture(nil, "OVERLAY")
		d:SetColorTexture(0, 0, 0, 0.9); d:SetWidth(1)
		d:SetPoint("TOP", sb, "TOPLEFT", s * i / 5, 0); d:SetPoint("BOTTOM", sb, "BOTTOMLEFT", s * i / 5, 0)
	end
	return sb, bh
end
-- Charge Bar Only: five parts side by side, from (index) to (index); a color lights them (a shade lighter
-- at the top), none draws the empty track; a thin dark line round each part and between them
local function segments(fr, w, h, from, to, r, g, b, alpha)
	local gap = 1 + math.floor(h / 24)   -- (the owner: no gap, just the line, as one bar)
	local sw = (w - gap * 4) / 5
	for i = from, to do
		local x = (i - 1) * (sw + gap)
		local edge = fr:CreateTexture(nil, "BORDER")
		edge:SetColorTexture(0, 0, 0, 0.85)
		edge:SetPoint("TOPLEFT", fr, "TOPLEFT", x - 1, 1); edge:SetSize(sw + 2, h + 2)
		local t = fr:CreateTexture(nil, "ARTWORK")
		t:SetPoint("TOPLEFT", fr, "TOPLEFT", x, 0); t:SetSize(sw, h)
		t:SetTexture(WHITE)
		if r then
			t:SetVertexColor(r, g, b)
			if t.SetGradient and CreateColor then
				pcall(t.SetGradient, t, "VERTICAL", CreateColor(r * 0.8, g * 0.8, b * 0.8, 1),
					CreateColor(math.min(1, r + 0.3), math.min(1, g + 0.3), math.min(1, b + 0.3), 1))
			end
		else
			t:SetVertexColor(0.08, 0.08, 0.1, 0.8)
		end
		if alpha then t:SetAlpha(alpha); edge:SetAlpha(alpha) end
	end
end

-- Charge Bar Only's glow: light along all four sides of the bar, brightest at its edge and fading
-- outward, breathing as the reminder's glow does. (The icon glows are square art: stretched over a
-- long bar they lit only its ends.)
local function barGlow(fr, anchor, r, g, b)
	local pad = 8
	local gf = CreateFrame("Frame", nil, fr)
	gf:SetAllPoints(anchor)
	local function strip(p1, a1, p2, a2, vertical, inside)
		local t = gf:CreateTexture(nil, "OVERLAY", nil, 1)
		t:SetTexture(WHITE); t:SetBlendMode("ADD")
		t:SetPoint(p1, anchor, a1); t:SetPoint(p2, anchor, a2)
		if vertical then t:SetHeight(pad) else t:SetWidth(pad) end
		-- from the bar's edge (bright) out (clear): `inside` names which end of the gradient is the edge
		local lo, hi = CreateColor and CreateColor(r, g, b, 0), CreateColor and CreateColor(r, g, b, 0.9)
		if lo and t.SetGradient then
			if inside == "min" then pcall(t.SetGradient, t, vertical and "VERTICAL" or "HORIZONTAL", hi, lo)
			else pcall(t.SetGradient, t, vertical and "VERTICAL" or "HORIZONTAL", lo, hi) end
		else
			t:SetVertexColor(r, g, b, 0.5)
		end
		return t
	end
	strip("BOTTOMLEFT", "TOPLEFT", "BOTTOMRIGHT", "TOPRIGHT", true, "min")        -- above: its bottom is the edge
	strip("TOPLEFT", "BOTTOMLEFT", "TOPRIGHT", "BOTTOMRIGHT", true, "max")        -- below: its top is the edge
	strip("TOPRIGHT", "TOPLEFT", "BOTTOMRIGHT", "BOTTOMLEFT", false, "max")       -- left: its right end is the edge
	strip("TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT", false, "min")       -- right: its left end is the edge
	local ag = gf:CreateAnimationGroup(); ag:SetLooping("REPEAT")
	local a1 = ag:CreateAnimation("Alpha"); a1:SetFromAlpha(0.35); a1:SetToAlpha(1); a1:SetDuration(0.5); a1:SetOrder(1)
	local a2 = ag:CreateAnimation("Alpha"); a2:SetFromAlpha(1); a2:SetToAlpha(0.35); a2:SetDuration(0.5); a2:SetOrder(2)
	ag:Play()
	gf.ag = ag
	return gf
end

-- the gold of 5 stacks: the same bar, full, in Color At 5 Stacks
local function stackBarFull(fr, stage, s, r, g, b) return (stackBar(fr, stage, s, r, g, b, true)) end
-- Drain: a gray copy of the look over its top part, down to where the time left reaches. The
-- sensor is a bar the time fills from the bottom (cropped, never stretched); the clip runs from the
-- top of the area down to the top of that fill, so the gray covers the time already gone.
local function drainShade(fr, area, e, s, wide, stage)
	local sensor = CreateFrame("StatusBar", nil, fr)
	sensor:SetAllPoints(area)
	sensor:SetOrientation("VERTICAL"); sensor:SetReverseFill(false)
	sensor:SetStatusBarTexture(WHITE)
	sensor:SetStatusBarColor(0, 0, 0, 0)
	sensor:SetMinMaxValues(0, 1); sensor:SetValue(1)
	local fill = sensor:GetStatusBarTexture()
	local clip = CreateFrame("Frame", nil, fr)
	clip:SetPoint("TOPLEFT", area, "TOPLEFT", 0, 0)
	clip:SetPoint("TOPRIGHT", area, "TOPRIGHT", 0, 0)
	clip:SetPoint("BOTTOM", fill, "TOP", 0, 0)
	clip:SetClipsChildren(true)
	clip:SetFrameLevel(stage:GetFrameLevel() + LEVEL.shade)
	local inner = CreateFrame("Frame", nil, clip)
	inner:SetAllPoints(area)
	if wide then
		local t = inner:CreateTexture(nil, "ARTWORK")
		t:SetAllPoints(area)
		t:SetTexture(EMBLEM); t:SetDesaturated(true); t:SetVertexColor(0.25, 0.25, 0.25)
	else
		local ed = (s >= 24) and 2 or 1
		local t = inner:CreateTexture(nil, "ARTWORK")
		t:SetPoint("TOPLEFT", area, "TOPLEFT", ed, -ed); t:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", -ed, ed)
		t:SetTexture(iconFile(e)); t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		t:SetDesaturated(true); t:SetVertexColor(0.4, 0.4, 0.4)
		if SP.ShapeIconTexture then SP:ShapeIconTexture(t, t, "ready") end
	end
	return sensor
end

-- ---------------------------------------------------------------------------
-- A look, described once. `A` draws it: the game's way (Engine) or with plain
-- frames (Paint). Each A:Part(rule, fn) gives fn a host frame for that rule and a
-- way to hand things to the game (R): rule.main (while the buff is on you; at 5 with
-- Show: Only At 5 Stacks), rule.from = n (n stacks or more), rule.at = n (exactly n),
-- rule.fx = "glow" / "pulse" (at 5, the Effect), rule.dim (always, Show: Always).
-- ---------------------------------------------------------------------------
local function describe(A, stage, e)
	local look, show, left = S.Look(e), S.Show(e), S.Left(e)
	local w, h, s = S.Box(e)
	local barOnly = look == "baronly"
	local wide = WIDE[look] == true and not barOnly   -- (the emblem's looks)
	if barOnly and left == "drain" then left = "number" end   -- (no picture to gray: the number instead)
	local five = show == "five"
	local sr, sg, sb = stackRGB(e)
	local r5, g5, b5 = fiveRGB(e)
	local fx = IconOpt(e, "readyEffect") or "glow"
	local shape = glowShape(e)
	local gr, gg, gb = glowRGB(e)

	-- Show: Always: the look at 0 stacks, dimmed, under everything
	if show == "always" then
		A:Part({ dim = true }, function(host)
			local fr = layer(host, stage, 1)
			if barOnly then segments(fr, w, h, 1, 5, nil, nil, nil, DIM)
			elseif wide then emblemTex(fr, EMBLEM, 0.3)
			else
				plate(fr, e, s, true, DIM)
				if look == "bar" then local bar = stackBar(fr, stage, s, sr, sg, sb, false); bar:SetAlpha(DIM) end
			end
		end)
	end

	-- the look itself, while the buff is on you (Only At 5 Stacks: at 5)
	A:Part({ main = true, from = five and 5 or nil }, function(host, R)
		local fr = layer(host, stage, LEVEL.main)
		if barOnly then
			-- the empty track; Only At 5 Stacks: all of it in Color At 5 Stacks
			if five then segments(fr, w, h, 1, 5, r5, g5, b5) else segments(fr, w, h, 1, 5) end
		elseif look == "wings" then
			if five then emblemTex(fr, EMBLEM) end
		elseif look == "fill" then
			if five then emblemTex(fr, EMBLEM)
			else
				emblemTex(fr, EMBLEM, 0.3)
				R:Stacks(fillBar(fr, fr, EMBLEM, false))
			end
		elseif look == "iconfill" then
			local P = plate(fr, e, s, not five)
			if not five then
				local bar = fillBar(fr, P.icon, iconFile(e), true, s - 2 * P.inset)
				local fill = bar:GetStatusBarTexture()
				if fill and SP.ShapeIconTexture then SP:ShapeIconTexture(fill, P.icon, "ready") end
				if fill and SP.SetIconShapeOwn then SP:SetIconShapeOwn(fill, IconOpt(e, "iconShape")) end
				R:Stacks(bar)
			end
		else
			plate(fr, e, s)
			if look == "bar" then
				if five then stackBarFull(fr, stage, s, r5, g5, b5)
				else R:Stacks((stackBar(fr, stage, s, sr, sg, sb, false))) end
			end
		end
		-- Time Left
		if left == "drain" then
			R:Time(drainShade(fr, fr, e, s, wide, stage))
		elseif left == "number" then
			local tf = layer(fr, stage, LEVEL.text)
			R:TimeText(timeText(tf, s, wide, barOnly and h or nil))
		end
		-- the count (Icon + Stack Number, or Stack Number on)
		if S.NumberOn(e) then
			local tf = layer(fr, stage, LEVEL.text)
			R:Count(countText(tf, s, wide, barOnly and h or nil), countFormatter(five, r5, g5, b5))
		end
	end)

	if not five then
		-- Wings: Blizzard's piece for each count, exactly at that count
		if look == "wings" then
			for n = 1, 5 do
				A:Part({ at = n, w = w }, function(host, R)
					local fr = layer(host, stage, LEVEL.piece)
					local t = fr:CreateTexture(nil, "ARTWORK")
					t:SetTexture(PIECES[n])
					R:Gate(t, h)
				end)
			end
		end
		-- Storm Glow: one glow more per stack, the glows adding up (the stack color)
		if look == "storm" then
			for n = 1, 4 do
				A:Part({ from = n }, function(host)
					local fr = layer(host, stage, LEVEL.storm)
					glowTex(fr, fr, shape, sr * 0.3, sg * 0.3, sb * 0.3, 0.7, 1, 0.9 - n * 0.1)
				end)
			end
		end
		-- Charge Bar Only: one part more per stack (the stack color), all of them in Color At 5 Stacks at 5
		if barOnly then
			for n = 1, 4 do
				A:Part({ from = n }, function(host)
					segments(layer(host, stage, LEVEL.piece), w, h, n, n, sr, sg, sb)
				end)
			end
			A:Part({ from = 5 }, function(host)
				segments(layer(host, stage, LEVEL.five), w, h, 1, 5, r5, g5, b5)
			end)
		end
		-- Charge Bar at 5: all of it in Color At 5 Stacks
		if look == "bar" then
			A:Part({ from = 5 }, function(host)
				stackBarFull(layer(host, stage, LEVEL.five), stage, s, r5, g5, b5)
			end)
		end
	end

	-- At 5 Stacks: the Effect (Glow, Pulse, both, none)
	if fx == "glow" or fx == "both" then
		A:Part({ fx = "glow" }, function(host)
			local fr = layer(host, stage, LEVEL.fx)
			if wide then
				local t = emblemTex(fr, EMBLEM)
				t:SetBlendMode("ADD"); t:SetVertexColor(gr, gg, gb)
				local ag = t:CreateAnimationGroup(); ag:SetLooping("REPEAT")
				local a1 = ag:CreateAnimation("Alpha"); a1:SetFromAlpha(0.15); a1:SetToAlpha(0.8); a1:SetDuration(0.5); a1:SetOrder(1)
				local a2 = ag:CreateAnimation("Alpha"); a2:SetFromAlpha(0.8); a2:SetToAlpha(0.15); a2:SetDuration(0.5); a2:SetOrder(2)
				ag:Play()
			elseif shape == "proc" and SP.ProcGlow_Start then
				-- Proc Glow: WeakAuras' ring on a frame of ours the size of the icon
				local c = { gr, gg, gb, 1 }
				if gr > 0.98 and gg > 0.98 and gb > 0.98 then c = nil end   -- (white: the game's gold)
				local pf = CreateFrame("Frame", nil, fr)
				pf:SetSize(w, h); pf:SetPoint("CENTER", stage, "CENTER", 0, 0)
				SP.ProcGlow_Start(pf, SP:ProcGlowOptions(pf, c, "rs", true, IconOpt(e, "glowThick") or SP.PROC_GLOW_OUT or 0.2))
			elseif barOnly then
				barGlow(fr, fr, gr, gg, gb)   -- (Charge Bar Only: all the way round the bar)
			else
				glowTex(fr, fr, shape, gr, gg, gb, 0.15, 0.8, 0.5)
			end
		end)
	end
	if fx == "pulse" or fx == "both" then
		A:Part({ fx = "pulse" }, function(host)
			local fr = layer(host, stage, LEVEL.fx - 1)
			if barOnly then   -- (Charge Bar Only: the whole bar, in Color At 5 Stacks, breathes)
				local pf = CreateFrame("Frame", nil, fr)
				pf:SetAllPoints(fr)
				segments(pf, w, h, 1, 5, r5, g5, b5)
				pulse(pf)
				return
			end
			local t = fr:CreateTexture(nil, "ARTWORK")
			if wide then
				t:SetAllPoints(fr); t:SetTexture(EMBLEM)
			else
				local ed = (s >= 24) and 2 or 1
				t:SetPoint("TOPLEFT", fr, "TOPLEFT", ed, -ed); t:SetPoint("BOTTOMRIGHT", fr, "BOTTOMRIGHT", -ed, ed)
				t:SetTexture(iconFile(e)); t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
				if SP.ShapeIconTexture then SP:ShapeIconTexture(t, t, "ready") end
			end
			pulse(t)
		end)
	end
end

-- ---------------------------------------------------------------------------
-- Engine: the game draws (live, in a fight too)
-- ---------------------------------------------------------------------------
local Dir = Enum and Enum.StatusBarTimerDirection or {}
local Engine = {}
Engine.__index = Engine
local Reg = {}
Reg.__index = Reg
function Reg:Count(fs, fmt)
	if not fs then return end
	SP:SPFontGameOwned(fs)
	pcall(self.button.SetApplicationCount, self.button, fs, fmt and { formatter = fmt } or {})
end
function Reg:Stacks(bar)
	if bar then pcall(self.button.SetApplicationBar, self.button, bar, { minApplications = 0, maxApplications = 5 }) end
end
function Reg:TimeText(fs)
	if not fs then return end
	SP:SPFontGameOwned(fs)
	pcall(self.button.SetDurationText, self.button, fs, { textFormatter = API.Buff.Formatter(3) })
end
function Reg:Time(sensor)
	if sensor and Dir.RemainingTime then pcall(self.button.SetDurationBar, self.button, sensor, { direction = Dir.RemainingTime }) end
end
-- exactly n: the part is as wide as the count text the game writes only at n
function Reg:Gate(t, h)
	local fs = self.gateText
	if not fs then t:Hide() return end
	t:ClearAllPoints()
	t:SetPoint("LEFT", fs, "LEFT", 1, 0); t:SetPoint("RIGHT", fs, "RIGHT", -1, 0)
	t:SetHeight(h)
end

local MAP
function Engine:Part(rule, fn)
	local st = self.st
	if rule.dim then fn(self.dimHost) return end
	local ok, c = pcall(CreateFrame, "AuraContainer", nil, self.host, "CustomAuraContainerTemplate")
	if not (ok and c and type(c.AddAuraSlot) == "function") then self.failed = true return end
	c:ClearAllPoints(); c:SetSize(1, 1); c:SetPoint("CENTER", st, "CENTER", 0, 0)
	c:SetFrameLevel(st:GetFrameLevel() + 1)
	if c.SetEditModePreviewEnabled then pcall(c.SetEditModePreviewEnabled, c, false) end
	local made = false
	local okSlot = pcall(c.AddAuraSlot, c, "stacks", "HELPFUL|PLAYER", {
		candidateFilters = { includeSpellIDs = MAP },
		initializeFrame = function(button)
			button:ClearAllPoints()
			button:SetAllPoints(st)
			if button.SetMouseClickEnabled then pcall(button.SetMouseClickEnabled, button, false) end
			if button.SetMouseMotionEnabled then pcall(button.SetMouseMotionEnabled, button, false) end
			local R = setmetatable({ button = button }, Reg)
			local host
			local from = rule.from or (rule.fx and 5) or nil
			if from then
				-- n stacks or more: a bar the game shows only from n (its value never drawn)
				host = CreateFrame("StatusBar", nil, button)
				host:SetAllPoints(st)
				host:SetMinMaxValues(from, from); host:SetValue(from)
				pcall(button.SetApplicationBar, button, host, { minApplications = from, maxApplications = from })
			else
				host = CreateFrame("Frame", nil, button)
				host:SetAllPoints(st)
				if rule.at then
					-- exactly n: the game writes a spacer only at n (hidden: only its width counts)
					local fs = host:CreateFontString(nil, "OVERLAY")
					fs:SetFont(STANDARD_TEXT_FONT, 10, "")
					fs:SetPoint("CENTER", st, "CENTER", 0, 0)
					fs:SetAlpha(0)
					local fmt = gateFormatter(rule.at, (rule.w or 0) + 2)
					if fmt then pcall(button.SetApplicationCount, button, fs, { formatter = fmt }); R.gateText = fs end
				end
			end
			host:EnableMouse(false)
			local okFn, err = pcall(fn, host, R)
			if not okFn then geterrorhandler()(err) end
			made = true
		end,
	})
	if not (okSlot and made) then
		pcall(c.SetEnabled, c, false); c:Hide()
		self.failed = true
		return
	end
	pcall(c.SetUnit, c, "player")
	pcall(c.SetEnabled, c, true)
	if c.UpdateAllAuras then pcall(c.UpdateAllAuras, c) end
	self.list[#self.list + 1] = c
	if rule.fx == "glow" then self.glowC[#self.glowC + 1] = c end
end

local function dropEngine(st)
	local E = st.engine
	if not E then return end
	for _, c in ipairs(E.list) do
		pcall(c.SetEnabled, c, false)
		pcall(c.SetUnit, c, "none")
		c:Hide()
	end
	if E.host then E.host:Hide() end
	if E.dimHost then E.dimHost:Hide() end
	st.engine = nil
end

-- (out of combat, never while the game hides auras: then on a later pass)
local function buildEngine(st, e)
	dropEngine(st)
	MAP = MAP or { [e.stacks.buff] = true }
	local E = setmetatable({ st = st, list = {}, glowC = {} }, Engine)
	E.host = CreateFrame("Frame", nil, st.eng)
	E.host:SetAllPoints(st); E.host:EnableMouse(false)
	E.dimHost = CreateFrame("Frame", nil, st.eng)
	E.dimHost:SetAllPoints(st); E.dimHost:EnableMouse(false)
	describe(E, st, e)
	-- (3.0.9.9) At 5 Stacks' sound in a fight: a part the game shows only from 5 stacks, nothing drawn on
	-- it. The buff back on you puts the game's button on screen before the part is set for the new count,
	-- so a part still shown from the last 5 comes up with it: the next frame says which it was.
	E:Part({ from = 5 }, function(host)
		local button = host:GetParent()
		if button and button.HookScript then button:HookScript("OnShow", function() st.fiveBtnAt = GetTime() end) end
		host:HookScript("OnShow", function()
			if not InCombatLockdown() then return end   -- (out of a fight the count is read: S.Pass)
			local at = GetTime()
			C_Timer.After(0, function()
				if st.fiveBtnAt ~= at then S.AtFive(st) end
			end)
		end)
	end)
	st.engine = E
	st.glowCombat = nil   -- (the switch below sets the glow containers for this fight state)
	return not E.failed
end

-- ---------------------------------------------------------------------------
-- Paint: plain frames, at a stack count of our own (previews, Unlock UI, the sim)
-- ---------------------------------------------------------------------------
local Paint = {}
Paint.__index = Paint
local PReg = {}
PReg.__index = PReg
function PReg:Count(fs, _, five) self.part.count = fs end
function PReg:Stacks(bar) local list = self.part.bars; list[#list + 1] = bar end
function PReg:TimeText(fs) self.part.time = fs end
function PReg:Time(sensor) self.part.sensor = sensor end
function PReg:Gate(t, h) t:ClearAllPoints(); t:SetPoint("CENTER", self.part.host, "CENTER", 0, 0); t:SetSize(self.part.rule.w or 0, h) end
function Paint:Part(rule, fn)
	local host = CreateFrame("Frame", nil, self.host)
	host:SetAllPoints(self.st); host:EnableMouse(false)
	local part = { rule = rule, host = host, bars = {} }
	local okFn, err = pcall(fn, host, setmetatable({ part = part }, PReg))
	if not okFn then geterrorhandler()(err) end
	self.parts[#self.parts + 1] = part
end

local function buildPaint(st, e)
	local old = st.paint
	if old and old.host then old.host:Hide() end
	local Pn = setmetatable({ st = st, parts = {} }, Paint)
	Pn.host = CreateFrame("Frame", nil, st.pnt)
	Pn.host:SetAllPoints(st); Pn.host:EnableMouse(false)
	describe(Pn, st, e)
	st.paint = Pn
end

-- the look at n stacks with `left` of its time (0 to 1) and `secs` seconds left
local function paintAt(st, e, n, left, secs)
	local Pn = st.paint
	if not Pn then return end
	local five = S.Show(e) == "five"
	local r5, g5, b5 = fiveRGB(e)
	local glowOK = not (IconOpt(e, "glowCombatOnly") and not InCombatLockdown())
	for _, p in ipairs(Pn.parts) do
		local r = p.rule
		local on = r.dim == true
		if r.fx then on = n >= 5 and (r.fx ~= "glow" or glowOK)
		elseif r.at then on = n == r.at
		elseif r.from then on = n >= r.from
		elseif not r.dim then on = n > 0 end
		p.host:SetShown(on)
		if on then
			for _, bar in ipairs(p.bars) do bar:SetValue(n) end
			if p.count then
				if n >= 5 then p.count:SetText(code(r5, g5, b5) .. n .. "|r")
				elseif five or n < 1 then p.count:SetText("")
				else p.count:SetText(tostring(n)) end
			end
			if p.time then p.time:SetText(secs and tostring(math.ceil(secs)) or "") end
			if p.sensor then p.sensor:SetValue(left or 1) end
		end
	end
end

-- ---------------------------------------------------------------------------
-- The stage on each Maelstrom Weapon reminder
-- ---------------------------------------------------------------------------
local function stageOf(f)
	local st = f.stack
	if st then return st end
	st = CreateFrame("Frame", nil, f)
	st:SetAllPoints(f)
	st:EnableMouse(false)
	st.eng = CreateFrame("Frame", nil, st); st.eng:SetAllPoints(st)
	st.pnt = CreateFrame("Frame", nil, st); st.pnt:SetAllPoints(st)
	st.pnt:Hide()
	st.f = f
	f.stack = st
	S.stages[#S.stages + 1] = st
	return st
end
-- drawn by the game ("engine") or by us ("paint")
local function setMode(st, mode)
	if st.mode == mode then return end
	st.mode = mode
	st.eng:SetShown(mode == "engine")
	st.pnt:SetShown(mode == "paint")
end

-- The reminder's own parts step aside: the stage draws the stacks. Called by the
-- appearance update (any setting, a theme, an import), in a fight too.
function S.Appearance(f)
	local e = f.entry
	local w, h = S.Box(e)
	f:SetSize(w, h)
	f.bg:Hide(); f.icon:Hide(); f.border:Hide()
	if f.ring then f.ring:Hide() end
	f.cooldown:Hide(); f.overlay:Hide(); f.bar:Hide(); f.glow:Hide()
	f.count:SetText("")
	-- the name under it: under the Charge Bar when the bar is there
	if S.Look(e) == "bar" then
		local s = IconOpt(e, "iconSize") or 48
		f.label:ClearAllPoints()
		f.label:SetPoint("TOP", f, "BOTTOM", 0, -(math.max(4, math.floor(s * 0.16 + 0.5)) + 6))
	end
	f.stackWide = WIDE[S.Look(e)] == true
	local st = stageOf(f)
	st.want = signature(e)
	if st.paint and st.paintSig ~= st.want then buildPaint(st, e); st.paintSig = st.want end
	if st.mode == "paint" and st.paintN then paintAt(st, e, st.paintN, st.paintLeft, st.paintSecs) end
	S.UpdateSound()
end

local function engineOK()
	return API.Buff.Engine() and C_StringUtil ~= nil and C_StringUtil.CreateNumericRuleFormatter ~= nil
end
-- the game's parts as the settings say (out of combat, not while auras are hidden)
local function ensureEngine(st, e)
	if st.engineSig == st.want and st.engine then return true end
	if SP:GameAuraButtonsLocked() then return st.engine ~= nil end
	local ok = buildEngine(st, e)
	st.engineSig = st.want
	return ok
end

-- out of combat: the stacks and the time left, read plainly (nil: not readable now).
-- One read per change: UNIT_AURA (out of combat only) marks it stale.
local read = { n = 0, left = 1, secs = nil, stale = true, exp = nil, dur = nil }
function S.Read(e)
	if read.stale then
		read.stale = false
		read.n, read.exp, read.dur = 0, nil, nil
		local get = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
		local ok, a = false, nil
		if get then ok, a = pcall(get, e.stacks.buff) end
		if not ok or (issecretvalue and issecretvalue(a)) then read.stale = true return nil end
		if type(a) == "table" then
			local n, exp, dur = a.applications, a.expirationTime, a.duration
			if issecretvalue and (issecretvalue(n) or issecretvalue(exp) or issecretvalue(dur)) then read.stale = true return nil end
			read.n = (type(n) == "number" and n > 0) and n or 1
			if type(exp) == "number" and type(dur) == "number" and dur > 0 then read.exp, read.dur = exp, dur end
		end
	end
	if read.exp then
		local secs = math.max(0, read.exp - GetTime())
		return read.n, secs / read.dur, secs
	end
	return read.n, 1, nil
end

local watch   -- UNIT_AURA (player), out of combat only: the next pass reads again
local function watchOn(on)
	if on then
		if not watch then
			watch = CreateFrame("Frame")
			watch:SetScript("OnEvent", function()
				read.stale = true
				SP.readyWake = true
			end)
			if SPCompat and SPCompat.StressRegister then SPCompat.StressRegister(watch, "Ready Reminders (stacks)") end
		end
		if not watch.on then
			if watch.RegisterUnitEvent then watch:RegisterUnitEvent("UNIT_AURA", "player") else watch:RegisterEvent("UNIT_AURA") end
			watch.on = true
			read.stale = true
		end
	elseif watch and watch.on then
		watch:UnregisterEvent("UNIT_AURA")
		watch.on = false
		read.stale = true
	end
end

-- Each pass (the Ready Reminders pass, for a Maelstrom Weapon reminder that is on screen)
function S.Pass(f, inCombat)
	local e = f.entry
	local st = stageOf(f)
	if not st.want then S.Appearance(f) end
	watchOn(not inCombat)
	local show = S.Show(e)
	local visible = true
	if engineOK() then
		setMode(st, "engine")
		ensureEngine(st, e)
		-- Glow Only In Combat: the glow's own containers, switched at the fight's edges
		local E = st.engine
		if E and #E.glowC > 0 then
			local want = inCombat or not IconOpt(e, "glowCombatOnly")
			if st.glowCombat ~= want then
				st.glowCombat = want
				for _, c in ipairs(E.glowC) do pcall(c.SetEnabled, c, want) end
			end
		end
		if not inCombat then
			local n = S.Read(e)
			if n ~= nil then
				if show == "stacks" then visible = n > 0 elseif show == "five" then visible = n >= 5 end
			end
			S.FiveCrossed(st, n)
		else
			st.fiveWas = nil   -- (the count hidden: the game's part says when 5 comes)
		end
	else
		-- (no game parts on this client: our own frames, from what can be read)
		setMode(st, "paint")
		if not st.paint or st.paintSig ~= st.want then buildPaint(st, e); st.paintSig = st.want end
		local n, left, secs = S.Read(e)
		S.FiveCrossed(st, n)
		n = n or 0
		if show == "stacks" then visible = n > 0 elseif show == "five" then visible = n >= 5 end
		st.paintN, st.paintLeft, st.paintSecs = n, left, secs
		paintAt(st, e, n, left, secs)
	end
	-- in a fight it stays on screen: the game shows what there is (the mouse goes through)
	f.gridReady = visible
	if visible then
		if not f:IsShown() then st.reshowing = true; f:Show(); st.reshowing = nil end   -- (its 5 part back with it: no sound)
	elseif f:IsShown() then
		f:Hide()
	end
	if inCombat then API.mouseOff(f) else API.mouseBack(f) end
	local a = IconOpt(e, "opacity") or 1
	f:SetAlpha(a * (f.fade or 1)); f.fadeBase = a
end

-- (3.0.9.13) Only In Combat (or Hide In Town) hides the reminder out of combat, and nothing can be made in a
-- fight: its game parts are made now, inside the hidden reminder, so the first fight has them. Before, Only In
-- Combat left it with nothing to draw in a fight (a player's report: Maelstrom Weapon never showed)
function S.Prepare(f)
	if InCombatLockdown() or not engineOK() then return end
	local st = stageOf(f)
	if not st.want then S.Appearance(f) end
	setMode(st, "engine")
	ensureEngine(st, f.entry)
end

-- Previews (the setup tour, the settings window) and Unlock UI: our own frames,
-- counting up 1 to 5 and holding at 5, the time running down; t = seconds into the
-- demo, nil = still at 5 stacks with all its time (Unlock UI)
local DEMO_STEP, DEMO_STEPS = 0.8, 8
function S.Demo(f, t)
	local e = f.entry
	local st = stageOf(f)
	if not st.want then S.Appearance(f) end
	setMode(st, "paint")
	if not st.paint or st.paintSig ~= st.want then buildPaint(st, e); st.paintSig = st.want end
	local n, left, secs = 5, 1, 30
	if t then
		local step = math.floor(t / DEMO_STEP) % DEMO_STEPS
		n = math.min(5, step + 1)
		left = 1 - (step / DEMO_STEPS) * 0.8
		secs = 30 * left
	end
	if st.paintN ~= n or st.paintLeft ~= left then
		st.paintN, st.paintLeft, st.paintSecs = n, left, secs
		paintAt(st, e, n, left, secs)
	end
	API.mouseBack(f)
	f.gridReady = true
end

-- ---------------------------------------------------------------------------
-- At 5 Stacks: the sound, as every Ready Reminder's (3.0.9.9)
-- ---------------------------------------------------------------------------
-- The reminders' own ready sound (API.readySound: the icon's Sound and Volume), the moment
-- the stacks reach 5. Out of a fight the pass reads the count (S.Pass); in a fight the game
-- hides it, so the moment comes from a part the game shows only from 5 stacks (buildEngine).
-- Until 3.0.9.9 the game played it on "Maelstrom Ready!" (408501), with no volume, and
-- players heard nothing (a Discord report).
local fiveCount = 0
function S.AtFive(st)
	if st.reshowing or not st.f then return end   -- (the reminder back on screen at 5: no new 5)
	fiveCount = fiveCount + 1
	API.readySound(st.f)
end
-- out of a fight, the count read: 5 reached since the last pass
function S.FiveCrossed(st, n)
	if n == nil then return end
	local at5 = n >= 5
	if at5 and st.fiveWas == false then S.AtFive(st) end
	st.fiveWas = at5
end
function S.UpdateSound() end   -- (nothing to register any more; kept for its callers)

-- /spdiag ready: how the stacks are drawn (never what they are)
function S.Diag(f)
	local st = f and f.stack
	local E = st and st.engine
	return string.format("stacks look=%s show=%s left=%s mode=%s containers=%s failed=%s waiting=%s sound=%s",
		f and S.Look(f.entry) or "-", f and S.Show(f.entry) or "-", f and S.Left(f.entry) or "-", tostring(st and st.mode),
		tostring(E and #E.list or 0), tostring(E and E.failed or false), tostring(st ~= nil and st.engineSig ~= st.want),
		"at 5 x" .. fiveCount)
end

-- the reminder is off screen (switched off, Only In Combat out of combat, the module off):
-- nothing to read
function S.Idle() watchOn(false) end
