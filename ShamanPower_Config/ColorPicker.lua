-- ShamanPower_Config :: ColorPicker
-- ShamanPower's own color picker, drawn with the settings window's kit
-- (Core.lua): a saturation / brightness square and a hue strip, the color as
-- it is now over the color it opened with, a hex box, rows of swatches (the
-- element palettes and WoW's own colors), an opacity slider when the color has
-- one, and Cancel / Okay. Every color setting in ShamanPower opens this one;
-- Blizzard's ColorPickerFrame is never used.
--
-- SP:OpenColorPicker({ r =, g =, b =, a =, hasAlpha =, title =,
--                      onChange = function(r, g, b, a) end, onCancel = function() end })
--   onChange runs live, on every change: a drag calls it as the color moves.
--   Okay keeps the color. Cancel, the X and Escape put the color it opened with
--   back (onChange with the original values, when anything was changed), then
--   call onCancel. Opening it again while it is up keeps the first color as it
--   is and starts over with the new one.
--
-- Zero idle cost: built the first time it opens, and its only OnUpdate runs
-- while a drag in the square or the hue strip is held.
local _, ns = ...
local Core, Widgets = ns.Core, ns.Widgets
local SP = ShamanPower
if not (SP and Core) then return end

local floor, max, min = math.floor, math.max, math.min

local IS_MAINLINE = (WOW_PROJECT_ID ~= nil and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE)

-- Layout (px)
local DLG_W    = 420   -- grows for a long title, never cuts it
local HEADER_H = 46
local FOOTER_H = 52
local SQ       = 150   -- the square, and the hue strip's height
local STRIP_W  = 16
local SW, SGAP = 18, 6 -- swatches
local LABEL_W  = 96    -- the swatch rows' names
local NOW_W, NOW_H, WAS_H = 120, 40, 12

-- ---------------------------------------------------------------------------
-- The swatch rows: brand-guidelines 4 (element palettes) and 5 (WoW's colors)
-- ---------------------------------------------------------------------------
local ELEMENTS = { "Earth", "Fire", "Water", "Air" }
local PALETTE_ROWS = {
	{ label = "ShamanPower", hex = { "AE7E4E", "F25735", "668DF2", "D0D5ED" } },
	{ label = "Blizzard",    hex = { "5CB836", "EB5E2B", "47B3E0", "9952FF" } },
	{ label = "Classic",     hex = { "996633", "FF661A", "3399FF", "CCCCFF" } },
}
-- read from the game's globals; the hex is only the fallback when one is missing
local WOW_ROW = {
	{ global = "GREEN_FONT_COLOR",        name = "WoW green (healthy)",   hex = "19FF19" },
	{ global = "YELLOW_FONT_COLOR",       name = "WoW yellow (low)",      hex = "FFFF00" },
	{ global = "RED_FONT_COLOR",          name = "WoW red (critical)",    hex = IS_MAINLINE and "FF2020" or "FF1919" },
	{ global = "NORMAL_FONT_COLOR",       name = "WoW gold",              hex = IS_MAINLINE and "FFD200" or "FFD100" },
	{ global = "ORANGE_FONT_COLOR",       name = "WoW orange",            hex = "FF8040" },
	{ global = "DEBUFF_TYPE_MAGIC_COLOR", name = "WoW magic blue",        hex = "0081FF" },
}

local function HexRGB(h)
	return tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255
end

local function WoWRGB(item)
	if SP.WoWColor then return SP:WoWColor(item.global) end
	local c = _G[item.global]
	if type(c) == "table" and type(c.r) == "number" and type(c.g) == "number" and type(c.b) == "number" then
		return c.r, c.g, c.b
	end
	return HexRGB(item.hex)
end

local function HexText(r, g, b)
	return string.format("#%02X%02X%02X", floor(r * 255 + 0.5), floor(g * 255 + 0.5), floor(b * 255 + 0.5))
end

-- "#9952FF", "9952ff" or " #9952FF " -> r, g, b; anything else -> nil
local function ParseHex(text)
	local h = (text or ""):match("^%s*#?(%x%x%x%x%x%x)%s*$")
	if not h then return nil end
	return HexRGB(h)
end

-- ---------------------------------------------------------------------------
-- HSV
-- ---------------------------------------------------------------------------
local function HSVtoRGB(h, s, v)
	if s <= 0 then return v, v, v end
	h = (h % 1) * 6
	local i = floor(h)
	local f = h - i
	local p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
	if i == 0 then return v, t, p
	elseif i == 1 then return q, v, p
	elseif i == 2 then return p, v, t
	elseif i == 3 then return p, q, v
	elseif i == 4 then return t, p, v
	end
	return v, p, q
end

-- keepH: the hue to keep when the color has none (a grey), so dragging down to
-- black or across to white does not throw the hue strip back to red
local function RGBtoHSV(r, g, b, keepH)
	local mx, mn = max(r, g, b), min(r, g, b)
	local d = mx - mn
	local h = keepH or 0
	if d > 0 then
		if mx == r then h = ((g - b) / d) % 6
		elseif mx == g then h = (b - r) / d + 2
		else h = (r - g) / d + 4 end
		h = h / 6
	end
	return h, (mx > 0) and (d / mx) or 0, mx
end

-- ---------------------------------------------------------------------------
-- State: one session at a time, kept in these tables (nothing is made per
-- change or per frame)
-- ---------------------------------------------------------------------------
local dlg
local cur  = { h = 0, s = 0, v = 1, r = 1, g = 1, b = 1, a = 1 }
local orig = { r = 1, g = 1, b = 1, a = 1 }
local sent = { r = -1, g = -1, b = -1, a = -1 }
local session = { onChange = nil, onCancel = nil, hasAlpha = false, changed = false, done = true }
local dragging   -- "sv" / "hue" while a drag is held

local function Call(fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		local handler = geterrorhandler and geterrorhandler()
		if handler then handler(err) end
	end
end

local function Paint()
	local hr, hg, hb = HSVtoRGB(cur.h, 1, 1)
	dlg.svBase:SetColorTexture(hr, hg, hb, 1)
	dlg.svCursor:SetPoint("CENTER", dlg.sv, "TOPLEFT", cur.s * SQ, -(1 - cur.v) * SQ)
	dlg.hueMark:SetPoint("CENTER", dlg.hue, "TOP", 0, -cur.h * SQ)
	dlg.now:SetColorTexture(cur.r, cur.g, cur.b, session.hasAlpha and cur.a or 1)
	if not dlg.hex:HasFocus() then dlg.hex:SetText(HexText(cur.r, cur.g, cur.b)) end
end

-- the color moved: repaint, and tell the caller (once per real change)
local function Changed()
	Paint()
	local a = cur.a
	if cur.r == sent.r and cur.g == sent.g and cur.b == sent.b and a == sent.a then return end
	sent.r, sent.g, sent.b, sent.a = cur.r, cur.g, cur.b, a
	session.changed = true
	if session.onChange then Call(session.onChange, cur.r, cur.g, cur.b, a) end
end

local function SetRGB(r, g, b)
	cur.r, cur.g, cur.b = r, g, b
	cur.h, cur.s, cur.v = RGBtoHSV(r, g, b, cur.h)
	Changed()
end

-- ---------------------------------------------------------------------------
-- Dragging in the square and the hue strip
-- ---------------------------------------------------------------------------
local function StopDrag()
	dragging = nil
	if dlg then dlg.driver:SetScript("OnUpdate", nil) end
end

local function DragUpdate()
	if not dragging then StopDrag() return end
	if not IsMouseButtonDown("LeftButton") then StopDrag() return end
	local target = (dragging == "sv") and dlg.sv or dlg.hue
	local left, top = target:GetLeft(), target:GetTop()
	if not (left and top) then return end
	local scale = target:GetEffectiveScale()
	local x, y = GetCursorPosition()
	x, y = x / scale - left, top - y / scale
	if dragging == "sv" then
		local s = min(1, max(0, x / SQ))
		local v = 1 - min(1, max(0, y / SQ))
		if s == cur.s and v == cur.v then return end
		cur.s, cur.v = s, v
	else
		local h = min(1, max(0, y / SQ))
		if h == cur.h then return end
		cur.h = h
	end
	cur.r, cur.g, cur.b = HSVtoRGB(cur.h, cur.s, cur.v)
	Changed()
end

local function StartDrag(which)
	if dlg.hex:HasFocus() then dlg.hex:ClearFocus() end
	dragging = which
	dlg.driver:SetScript("OnUpdate", DragUpdate)
	DragUpdate()
end

-- ---------------------------------------------------------------------------
-- Closing
-- ---------------------------------------------------------------------------
-- keep = true: the color stays (Okay, or a new color opened over this one)
local function Finish(keep)
	if session.done then return end
	session.done = true
	StopDrag()
	local onChange, onCancel = session.onChange, session.onCancel
	session.onChange, session.onCancel = nil, nil
	if keep then return end
	if session.changed and onChange then Call(onChange, orig.r, orig.g, orig.b, orig.a) end
	if onCancel then Call(onCancel) end
end

-- ---------------------------------------------------------------------------
-- Small drawing helpers (primitives only)
-- ---------------------------------------------------------------------------
-- a 1px ring of four edges in a fixed color
local function Ring(frame, r, g, b, a)
	local function edge(p1, p2, w, h)
		local t = frame:CreateTexture(nil, "OVERLAY")
		t:SetColorTexture(r, g, b, a)
		t:SetPoint(p1); t:SetPoint(p2)
		if w then t:SetWidth(w) end
		if h then t:SetHeight(h) end
	end
	edge("TOPLEFT", "TOPRIGHT", nil, 1)
	edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
	edge("TOPLEFT", "BOTTOMLEFT", 1, nil)
	edge("TOPRIGHT", "BOTTOMRIGHT", 1, nil)
end

-- a clickable color square: 1px border that lights up on hover, a tooltip
local function Swatch(parent, r, g, b, name)
	local s = CreateFrame("Button", nil, parent)
	s:SetSize(SW, SW)
	local fill = s:CreateTexture(nil, "ARTWORK")
	fill:SetPoint("TOPLEFT", s, "TOPLEFT", 1, -1)
	fill:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", -1, 1)
	fill:SetColorTexture(r, g, b, 1)
	Core:MakeBorder(s, "border")
	s:SetScript("OnEnter", function(self) Core:SetBorderColor(self, "accent") end)
	s:SetScript("OnLeave", function(self) Core:SetBorderColor(self, "border") end)
	Core:AttachTooltip(s, name, HexText(r, g, b))
	s:SetScript("OnClick", function() SetRGB(r, g, b) end)
	return s
end

-- ---------------------------------------------------------------------------
-- The window
-- ---------------------------------------------------------------------------
local function Build()
	if dlg then return dlg end
	dlg = Core:CreateDialog({
		name = "ShamanPowerColorPicker", width = DLG_W, height = 380,
		title = "Color", subtitle = "changes show as you pick",
		headerHeight = HEADER_H, footer = FOOTER_H, special = true, strata = "FULLSCREEN_DIALOG",
	})
	-- a color is judged against a solid panel: opaque at any Background Opacity
	local solid = dlg:CreateTexture(nil, "BACKGROUND", nil, 1)
	solid:SetPoint("TOPLEFT", 2, -2); solid:SetPoint("BOTTOMRIGHT", -2, 2)
	solid:SetColorTexture(Core:Color("windowBg", 1))
	local solidH = dlg.header:CreateTexture(nil, "BACKGROUND", nil, 1)
	solidH:SetAllPoints(dlg.header); solidH:SetColorTexture(Core:Color("sidebarBg", 1))

	local body = dlg.body
	dlg.driver = CreateFrame("Frame", nil, dlg)   -- runs the drag; no script while idle

	-- the saturation / brightness square: the pure hue under a white ramp
	-- (left to right) and a black ramp (top to bottom)
	local sv = CreateFrame("Frame", nil, body)
	sv:SetSize(SQ, SQ)
	sv:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
	sv:EnableMouse(true)
	local base = sv:CreateTexture(nil, "ARTWORK", nil, 0); base:SetAllPoints(sv)
	local white = sv:CreateTexture(nil, "ARTWORK", nil, 1); white:SetAllPoints(sv); white:SetColorTexture(1, 1, 1, 1)
	Core:Gradient(white, "HORIZONTAL", 1, 1, 1, 1, 1, 1, 1, 0)
	local black = sv:CreateTexture(nil, "ARTWORK", nil, 2); black:SetAllPoints(sv); black:SetColorTexture(1, 1, 1, 1)
	Core:Gradient(black, "VERTICAL", 0, 0, 0, 1, 0, 0, 0, 0)   -- bottom black, top clear
	local svEdge = CreateFrame("Frame", nil, sv)
	svEdge:SetPoint("TOPLEFT", sv, "TOPLEFT", -1, 1); svEdge:SetPoint("BOTTOMRIGHT", sv, "BOTTOMRIGHT", 1, -1)
	Core:MakeBorder(svEdge, "border")
	sv:SetScript("OnMouseDown", function(_, button) if button == "LeftButton" then StartDrag("sv") end end)
	sv:SetScript("OnMouseUp", StopDrag)
	dlg.sv, dlg.svBase = sv, base
	-- the cursor: a white ring inside a dark one, readable on any color
	local cursor = CreateFrame("Frame", nil, sv)
	cursor:SetSize(11, 11)
	cursor:SetFrameLevel(sv:GetFrameLevel() + 2)
	Ring(cursor, 0, 0, 0, 0.9)
	local inner = CreateFrame("Frame", nil, cursor)
	inner:SetPoint("TOPLEFT", cursor, "TOPLEFT", 1, -1); inner:SetPoint("BOTTOMRIGHT", cursor, "BOTTOMRIGHT", -1, 1)
	Ring(inner, 1, 1, 1, 1)
	dlg.svCursor = cursor

	-- the hue strip: six ramps, red at the top round to red at the bottom
	local hue = CreateFrame("Frame", nil, body)
	hue:SetSize(STRIP_W, SQ)
	hue:SetPoint("TOPLEFT", sv, "TOPRIGHT", 10, 0)
	hue:EnableMouse(true)
	local segH = SQ / 6
	for i = 0, 5 do
		local seg = hue:CreateTexture(nil, "ARTWORK")
		seg:SetColorTexture(1, 1, 1, 1)
		seg:SetPoint("TOPLEFT", hue, "TOPLEFT", 0, -i * segH)
		seg:SetPoint("TOPRIGHT", hue, "TOPRIGHT", 0, -i * segH)
		seg:SetHeight(segH)
		local tr, tg, tb = HSVtoRGB(i / 6, 1, 1)
		local br, bg, bb = HSVtoRGB((i + 1) / 6, 1, 1)
		Core:Gradient(seg, "VERTICAL", br, bg, bb, 1, tr, tg, tb, 1)   -- bottom, top
	end
	local hueEdge = CreateFrame("Frame", nil, hue)
	hueEdge:SetPoint("TOPLEFT", hue, "TOPLEFT", -1, 1); hueEdge:SetPoint("BOTTOMRIGHT", hue, "BOTTOMRIGHT", 1, -1)
	Core:MakeBorder(hueEdge, "border")
	hue:SetScript("OnMouseDown", function(_, button) if button == "LeftButton" then StartDrag("hue") end end)
	hue:SetScript("OnMouseUp", StopDrag)
	dlg.hue = hue
	-- the hue marker: a white bar edged in black, a little wider than the strip
	local mark = CreateFrame("Frame", nil, hue)
	mark:SetSize(STRIP_W + 6, 4)
	mark:SetFrameLevel(hue:GetFrameLevel() + 2)
	local markBg = mark:CreateTexture(nil, "OVERLAY", nil, 0); markBg:SetAllPoints(mark); markBg:SetColorTexture(0, 0, 0, 0.9)
	local markFg = mark:CreateTexture(nil, "OVERLAY", nil, 1)
	markFg:SetPoint("TOPLEFT", mark, "TOPLEFT", 1, -1); markFg:SetPoint("BOTTOMRIGHT", mark, "BOTTOMRIGHT", -1, 1)
	markFg:SetColorTexture(1, 1, 1, 1)
	dlg.hueMark = mark

	-- right column: the color now over the color it opened with, and the hex box
	local colX = SQ + 10 + STRIP_W + 16
	local block = CreateFrame("Frame", nil, body)
	block:SetSize(NOW_W, NOW_H + WAS_H)
	block:SetPoint("TOPLEFT", body, "TOPLEFT", colX, 0)
	-- (the fills sit inside the 1px border, never over it)
	local checker = block:CreateTexture(nil, "BACKGROUND")
	checker:SetPoint("TOPLEFT", block, "TOPLEFT", 1, -1); checker:SetPoint("BOTTOMRIGHT", block, "BOTTOMRIGHT", -1, 1)
	checker:SetColorTexture(0.25, 0.25, 0.25, 1)
	local now = block:CreateTexture(nil, "ARTWORK")
	now:SetPoint("TOPLEFT", block, "TOPLEFT", 1, -1); now:SetPoint("TOPRIGHT", block, "TOPRIGHT", -1, -1)
	now:SetHeight(NOW_H - 1)
	Core:MakeBorder(block, "border")
	dlg.now = now
	-- the "before" strip: click it to go back to the color it opened with
	local was = CreateFrame("Button", nil, block)
	was:SetPoint("BOTTOMLEFT", block, "BOTTOMLEFT", 1, 1); was:SetPoint("BOTTOMRIGHT", block, "BOTTOMRIGHT", -1, 1)
	was:SetHeight(WAS_H - 1)
	local wasTex = was:CreateTexture(nil, "ARTWORK"); wasTex:SetAllPoints(was)
	local wasRule = was:CreateTexture(nil, "OVERLAY"); wasRule:SetHeight(1)
	wasRule:SetPoint("TOPLEFT", was, "TOPLEFT", 0, 0); wasRule:SetPoint("TOPRIGHT", was, "TOPRIGHT", 0, 0)
	wasRule:SetColorTexture(Core:Color("border"))
	Core:AttachTooltip(was, "Before", "The color this opened with. Click it to go back to it.")
	was:SetScript("OnClick", function()
		cur.a = orig.a
		SetRGB(orig.r, orig.g, orig.b)
		if dlg.alphaHost and Widgets then Widgets:RefreshAll(dlg.alphaHost) end
	end)
	dlg.wasTex = wasTex

	-- the hex box: styled like the settings' input boxes (Widgets:Input)
	local hex = CreateFrame("EditBox", nil, body)
	hex:SetSize(NOW_W, 22)
	hex:SetPoint("TOPLEFT", block, "BOTTOMLEFT", 0, -10)
	hex:SetAutoFocus(false)
	hex:SetFontObject(Core.fonts.row)
	hex:SetTextInsets(6, 6, 0, 0)
	hex:SetMaxLetters(12)
	Core:SolidTex(hex, "windowBg", "BACKGROUND")
	Core:MakeBorder(hex, "border")
	-- only a hex that differs from the one shown moves the color (leaving the
	-- box untouched never rounds a dragged color to the hex); a typo goes back
	-- to the color shown
	local function commitHex(self)
		local r, g, b = ParseHex(self:GetText())
		if r and HexText(r, g, b) ~= HexText(cur.r, cur.g, cur.b) then SetRGB(r, g, b) end
		self:SetText(HexText(cur.r, cur.g, cur.b))
	end
	hex:SetScript("OnEnterPressed", function(self) commitHex(self); self:ClearFocus() end)
	hex:SetScript("OnEscapePressed", function(self) self:SetText(HexText(cur.r, cur.g, cur.b)); self:ClearFocus() end)
	hex:SetScript("OnEditFocusGained", function(self) Core:SetBorderColor(self, "accent"); self:HighlightText() end)
	hex:SetScript("OnEditFocusLost", function(self)
		Core:SetBorderColor(self, "border")
		self:HighlightText(0, 0)
		commitHex(self)
	end)
	hex:SetScript("OnEnter", function(self) if not self:HasFocus() then Core:SetBorderColor(self, "accent") end end)
	hex:SetScript("OnLeave", function(self) if not self:HasFocus() then Core:SetBorderColor(self, "border") end end)
	Core:AttachTooltip(hex, "Hex color", "Type a color as #RRGGBB and press Enter.")
	dlg.hex = hex

	local help = body:CreateFontString(nil, "OVERLAY")
	help:SetFontObject(Core.fonts.rowDim)
	help:SetPoint("TOPLEFT", hex, "BOTTOMLEFT", 0, -10)
	help:SetJustifyH("LEFT"); help:SetWordWrap(true)
	help:SetText("Drag in the square and the strip, type a hex color, or click a swatch below.")
	dlg.help, dlg.colX = help, colX

	-- the swatch rows, under the square (placed at open, below the taller of the
	-- square and the right column)
	local rows = CreateFrame("Frame", nil, body)
	local y = 0
	local function rowLabel(text)
		local l = rows:CreateFontString(nil, "OVERLAY")
		l:SetFontObject(Core.fonts.section)
		l:SetPoint("LEFT", rows, "TOPLEFT", 0, -(y + SW / 2))
		l:SetWidth(LABEL_W - 6); l:SetJustifyH("LEFT"); l:SetWordWrap(true)
		l:SetText(strupper(text))
	end
	for _, row in ipairs(PALETTE_ROWS) do
		rowLabel(row.label)
		for e = 1, 4 do
			local r, g, b = HexRGB(row.hex[e])
			local s = Swatch(rows, r, g, b, row.label .. " " .. ELEMENTS[e])
			s:SetPoint("TOPLEFT", rows, "TOPLEFT", LABEL_W + (e - 1) * (SW + SGAP), -y)
		end
		y = y + SW + SGAP
	end
	rowLabel("WoW")
	for i, item in ipairs(WOW_ROW) do
		local r, g, b = WoWRGB(item)
		local s = Swatch(rows, r, g, b, item.name)
		s:SetPoint("TOPLEFT", rows, "TOPLEFT", LABEL_W + (i - 1) * (SW + SGAP), -y)
	end
	rows:SetHeight(y + SW)
	dlg.rows = rows

	-- the opacity slider (only for a color with one): the settings' own slider row
	local alphaHost = CreateFrame("Frame", nil, body)
	alphaHost:SetPoint("TOPLEFT", rows, "BOTTOMLEFT", 0, -12)
	alphaHost:SetPoint("TOPRIGHT", rows, "BOTTOMRIGHT", 0, -12)
	alphaHost:SetHeight(40)
	dlg.alphaHost = alphaHost

	-- buttons: Okay (primary, rightmost), Cancel to its left; the X is Cancel
	local okay = Core:MakeButton(dlg, "Okay", 92, true)
	okay:SetPoint("BOTTOMRIGHT", dlg, "BOTTOMRIGHT", -14, 12)
	okay:SetScript("OnClick", function()
		if dlg.hex:HasFocus() then dlg.hex:ClearFocus() end   -- a typed hex counts without Enter
		Finish(true)
		dlg:Hide()
	end)
	local cancel = Core:MakeButton(dlg, "Cancel", 92, false)
	cancel:SetPoint("RIGHT", okay, "LEFT", -8, 0)
	cancel:SetScript("OnClick", function() Finish(false); dlg:Hide() end)
	dlg.close:SetScript("OnClick", function() cancel:Click() end)

	-- Escape (UISpecialFrames) or anything else that closes it is Cancel. A
	-- hidden parent (Alt+Z) is not a close: the frame is still shown.
	dlg.spOnHide = function(self)
		StopDrag()
		if self.hex:HasFocus() then self.hex:ClearFocus() end
		if self:IsShown() then return end
		Finish(false)
		if Widgets then Widgets:ReleaseAll(self.alphaHost) end
	end
	return dlg
end

-- ---------------------------------------------------------------------------
-- Public
-- ---------------------------------------------------------------------------
function SP:OpenColorPicker(opts)
	if type(opts) ~= "table" then return end
	Build()
	-- a color already being picked keeps what it has
	if not session.done then Finish(true) end
	if Widgets then Widgets:ReleaseAll(dlg.alphaHost) end

	local r, g, b = tonumber(opts.r) or 1, tonumber(opts.g) or 1, tonumber(opts.b) or 1
	local a = tonumber(opts.a) or 1
	orig.r, orig.g, orig.b, orig.a = r, g, b, a
	cur.r, cur.g, cur.b, cur.a = r, g, b, a
	cur.h, cur.s, cur.v = RGBtoHSV(r, g, b, 0)
	sent.r, sent.g, sent.b, sent.a = r, g, b, a
	session.onChange = type(opts.onChange) == "function" and opts.onChange or nil
	session.onCancel = type(opts.onCancel) == "function" and opts.onCancel or nil
	session.hasAlpha = opts.hasAlpha and true or false
	session.changed = false
	session.done = false

	-- the title, whole: the window widens for a long one
	local title = (type(opts.title) == "string" and opts.title ~= "") and opts.title or "Color"
	dlg.title:SetText(title)
	local w = max(DLG_W, math.ceil(dlg.title:GetStringWidth()) + dlg.pad + 60)
	dlg:SetWidth(w)
	local bodyW = w - 2 * dlg.pad
	dlg.help:SetWidth(max(80, bodyW - dlg.colX))

	dlg.wasTex:SetColorTexture(r, g, b, session.hasAlpha and a or 1)

	-- the swatch rows under the taller of the square and the right column, the
	-- opacity row under them, and the height measured from what is shown
	local colH = NOW_H + WAS_H + 10 + 22 + 10 + math.ceil(dlg.help:GetStringHeight())
	local rowsY = max(SQ, colH) + 16
	dlg.rows:ClearAllPoints()
	dlg.rows:SetPoint("TOPLEFT", dlg.body, "TOPLEFT", 0, -rowsY)
	dlg.rows:SetPoint("TOPRIGHT", dlg.body, "TOPRIGHT", 0, -rowsY)
	local bodyH = rowsY + dlg.rows:GetHeight()
	if session.hasAlpha and Widgets then
		local _, h = Widgets:Slider(dlg.alphaHost, {
			label = "Opacity", desc = "How see-through this color is.",
			x = 0, y = 0, width = bodyW, min = 0, max = 1, step = 0.01, isPercent = true,
			get = function() return cur.a end,
			set = function(v) cur.a = v; Changed() end,
		})
		dlg.alphaHost:Show()
		bodyH = bodyH + 12 + (h - Widgets.ROW_GAP)
	else
		dlg.alphaHost:Hide()
	end
	dlg:SetHeight(HEADER_H + 4 + 10 + bodyH + dlg.pad + FOOTER_H)

	Paint()
	dlg:Show()
	dlg:Raise()
end

-- Close the picker. keep = true keeps the color; otherwise it is a Cancel.
function SP:HideColorPicker(keep)
	if not dlg or not dlg:IsShown() then return end
	Finish(keep and true or false)
	dlg:Hide()
end
