-- ShamanPower_Config :: ContextMenu
-- A right-click menu in the shared dropdown popup's look (D33 "Lit menu",
-- menus_glowup_mock.py panel_rr): sidebarBg, the settings window's soft 1.5 px
-- edge with a thin stripe of the four elements on top, 22 px rows in the row font,
-- hover (and the row whose submenu is open) the plain row hover. A level of
-- choices (its items carry `selected`) has its text 28 in and its current choice
-- lit like the settings sidebar's open page: the element's light fading right, a
-- 3 px element bar, the tiny totem box. The element is the page's or window's it
-- opens from (spec.element, else Widgets:MenuElement(anchor); logo blue outside
-- any). Optional header line (icon + name) on a strip tinted toward the element,
-- and separators; a value column in textDim (accentHi for a value of its own);
-- ">" for a submenu. A submenu opens on hover beside its row
-- (to the right; to the left at the screen's edge) and the mouse can cross into
-- it: another row takes over only after a short hover. The whole chain closes on
-- Escape, a click or the wheel outside it, or :Close() (a page change, the window
-- closing). FULLSCREEN_DIALOG, over the settings window. Silent. Built on first
-- use from our own textures and Core.fonts; nothing runs while it is closed.
--
-- ns.ContextMenu:Open(anchor, spec)   :Close()   :Refresh()   :IsOpen()
--   :OpenPath() -> { row index per open submenu }   :ShowPath(path)
-- spec = {
--   header = { text = "Earth Shock", icons = { texture, ... } },   up to three icons: shown as slices
--   items = function() return { item, ... } end,                   read again by :Refresh()
--   onClose = function() end,
--   x, y = the root's offset from the anchor's bottom left (default -4, -6)
--   element = "fire",   optional: the menu's element (default: the anchor's page or window)
-- }
-- item = { separator = true }  or  {
--   text = "Show",
--   value = function() return text, own end,   the value column (own: accentHi)
--   swatch = { r, g, b },                      a small color square in the value column
--   sub = function() return { item, ... } end, subMaxHeight = px (a long list scrolls)
--   selected = true / false,                   a choice (true: the current one)
--   disabled = true,
--   icon = texture,                            a small spell icon before the text
--   preview = function() end,                  a speaker button on the right (plays; picks nothing)
--   onClick = function() return keepOpen end,  nil / false: the chain closes; true: it repaints
--   slider = { min, max, step, get = function() return v end, set = function(v) end,
--              format = function(v) return text end, isPercent = true / false },
--                                              a slider and its number box in the value column (D41 A):
--                                              drag it (set ~10 a second, and once on release), the wheel
--                                              over the row (a step a notch), or type in the box (Enter)
-- }

local _, ns = ...
local Core = ns.Core

local CM = {}
ns.ContextMenu = CM

-- Layout (px); the D29 mock's measures, in the shared popup's row height
local ITEM_H        = 22
local SEP_H         = 8     -- a separator: a 1 px line, inset 8
local HEADER_H      = 38    -- the header line, its rule at 32, 4 below it
local PAD_V         = 4     -- above the first row (no header) and under the last
local PAD_X         = 12    -- the label's left
local ICON_W        = 16    -- a row's small icon (6 px before its text)
local VALUE_GAP     = 24    -- the least room between a label and its value
local RIGHT_ARROW   = 26    -- the value's right edge in a level with submenus (">" centered 12 in)
local RIGHT_PLAIN   = 12
local RIGHT_SPEAKER = 34    -- a level with speaker buttons
local MIN_W_ROOT, MIN_W_SUB = 290, 250   -- the mock's menu and submenu (wider when a text needs it)
local MAX_H         = 420   -- taller: the level scrolls
local WHEEL         = 28    -- the shared popup's wheel step
local SWITCH_DELAY  = 0.15  -- hovering another row this long moves the submenu to it
local BASE_LEVEL    = 40    -- catcher 40, Escape catcher 45, levels 50 / 60 / 70
-- the D33 look: the edge, the stripe, the header's strip, a choice's tiny totem box
-- (11 in) and text (28 in), all from the menu's outer edge
local EDGE, STRIPE_H, HEADER_STRIP_H = 1.5, 2, 32
local BOX, BOX_X, TEXT_X = 10, 11, 28
-- a slider row (D41 A, slider_menu_mock.py): the settings window's slider (Widgets CreateSlider)
-- in the value column: its 120 px track, a 10 px gap, the 48 px number box
local SLIDER_W, SLIDER_GAP, SLIDER_BOX_W = 120, 10, 48
local SLIDER_RESERVE = SLIDER_W + SLIDER_GAP + SLIDER_BOX_W
local SLIDER_SET_EVERY = 0.1   -- a drag hands its value on at most ten times a second

local levels = {}           -- [depth] = the level's frame, made on first use
local catcher, keys, measure
local spec, anchor          -- the menu that is open
local element = "spirit"    -- its element (SP.Brand key)
local sliderDrag            -- the row whose slider thumb is held (no submenu moves meanwhile)

local function Report(err) geterrorhandler()(err) end

local function Width(fs)
	return (fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth()) or fs:GetStringWidth()
end

-- an element's color; accent when the brand file is missing (an update before a full restart)
local function ElementRGB(key)
	local sp = ShamanPower
	if sp and sp.BrandElementRGB then return sp:BrandElementRGB(key) end
	return Core:Color("accent")
end

-- ---------------------------------------------------------------------------
-- Painting
-- ---------------------------------------------------------------------------
-- the current choice's light: 28% of the element over rowHover, fading out to the
-- right, its 3 px bar and tiny totem box (painted when the row's element changes)
local function PaintLit(b)
	if b.litKey == element then return end
	b.litKey = element
	local er, eg, eb = ElementRGB(element)
	local hr, hg, hb = Core:Color("rowHover")
	local lr, lg, lb = er * 0.28 + hr * 0.72, eg * 0.28 + hg * 0.72, eb * 0.28 + hb * 0.72
	Core:Gradient(b.lit, "HORIZONTAL", lr, lg, lb, 1, hr, hg, hb, 1)
	b.bar:SetColorTexture(er, eg, eb, 1)
	if b.box then b.box:SetElement(element) end
end

local function PaintRow(b)
	local item, lv = b.item, b.lv
	if not item then return end
	local open = lv.openRow == b   -- its submenu is open: it keeps the hover look
	local lit = item.selected and true or false
	if lit then PaintLit(b) end
	b.lit:SetShown(lit)
	b.bar:SetShown(lit)
	if b.box then
		b.box:SetShown(lit)
		if item.disabled then b.box:SetShade(0.5) else b.box:SetShade(1) end
	end
	-- the lit current choice stays as it is under the mouse (the settings sidebar's open page)
	if (b.hover or open) and not item.disabled and not lit then
		b.bg:SetColorTexture(Core:Color("rowHover"))
	else
		b.bg:SetColorTexture(0, 0, 0, 0)
	end
	b.text:SetTextColor(Core:ColorIf(item.disabled, "textMute", "text"))
	if b.icon:IsShown() then b.icon:SetDesaturated(item.disabled and true or false) end
end

local function PaintSpeaker(s, key)
	local r, g, bl = Core:Color(key)
	for i = 1, #s.parts do s.parts[i]:SetVertexColor(r, g, bl) end
end

-- ---------------------------------------------------------------------------
-- Levels
-- ---------------------------------------------------------------------------
local OpenLevel, CloseFrom   -- forward

local function SetChild(lv, b)
	if lv.openRow == b then return end
	CloseFrom(lv.depth + 1)
	local old = lv.openRow
	lv.openRow = nil
	if old then PaintRow(old) end
	local item = b and b.item
	if item and item.sub and not item.disabled then
		lv.openRow = b
		PaintRow(b)
		local ok, items = pcall(item.sub)
		if ok and type(items) == "table" then OpenLevel(lv.depth + 1, items, b, item.subMaxHeight)
		elseif not ok then Report(items) end
	end
end

local function RowEnter(b)
	local lv = b.lv
	b.hover = true
	PaintRow(b)
	if sliderDrag then return end   -- a thumb is held: the submenus stay as they are
	-- the mouse reached this level: its parent keeps the submenu it is in
	local parent = levels[lv.depth - 1]
	if parent then parent.pending = nil end
	if lv.openRow == b then lv.pending = nil return end
	local child = levels[lv.depth + 1]
	if child and child:IsShown() then
		-- another row's submenu is open: move it only if the mouse stays here a moment,
		-- so passing over a row on the way into the submenu changes nothing
		lv.pending, lv.pendingAt = b, GetTime()
		C_Timer.After(SWITCH_DELAY, lv.switch)
	else
		lv.pending = nil
		SetChild(lv, b)
	end
end

local function RowLeave(b)
	b.hover = false
	PaintRow(b)
	if b.lv.pending == b then b.lv.pending = nil end
end

local function RowClick(b)
	local item = b.item
	if not item or item.disabled then return end
	if item.sub then b.lv.pending = nil; SetChild(b.lv, b) return end
	if not item.onClick then return end
	local ok, keep = xpcall(item.onClick, geterrorhandler())
	if ok and keep then CM:Refresh() else CM:Close() end
end

-- the speaker: a small box, its widening cone and two sound waves, drawn in textDim
local function NewSpeaker(row)
	local s = CreateFrame("Button", nil, row)
	s:SetSize(18, 18)
	s:SetPoint("RIGHT", row, "RIGHT", -10, 0)
	s.row = row
	s.parts = {}
	local function rect(x, w, h)
		local t = s:CreateTexture(nil, "ARTWORK")
		t:SetColorTexture(1, 1, 1, 1)
		t:SetSize(w, h)
		t:SetPoint("CENTER", s, "CENTER", x, 0)
		s.parts[#s.parts + 1] = t
	end
	rect(-5.5, 3, 4)
	rect(-3.5, 1, 6)
	rect(-2.5, 1, 8)
	rect(-1.5, 1, 10)
	local function line(x1, y1, x2, y2)
		local l = s:CreateLine(nil, "ARTWORK")
		l:SetThickness(1.2)
		l:SetColorTexture(1, 1, 1, 1)
		l:SetStartPoint("CENTER", s, x1, y1)
		l:SetEndPoint("CENTER", s, x2, y2)
		s.parts[#s.parts + 1] = l
	end
	line(1.5, 2.5, 2.5, 0); line(2.5, 0, 1.5, -2.5)
	line(3.5, 4.5, 5.2, 0); line(5.2, 0, 3.5, -4.5)
	PaintSpeaker(s, "textDim")
	s:SetScript("OnEnter", function(self) PaintSpeaker(self, "accentHi"); RowEnter(self.row) end)
	s:SetScript("OnLeave", function(self) PaintSpeaker(self, "textDim"); RowLeave(self.row) end)
	s:SetScript("OnClick", function(self)
		local item = self.row.item
		if item and item.preview then xpcall(item.preview, geterrorhandler()) end
	end)
	Core:AttachTooltip(s, "Play this sound", nil)
	return s
end

-- ---------------------------------------------------------------------------
-- Slider rows (D41 A)
-- ---------------------------------------------------------------------------
-- a value on the slider's steps, inside its range
local function SliderStep(sl, v)
	local lo, hi = sl.min or 0, sl.max or 100
	local step = sl.step or 1
	if step > 0 then v = lo + math.floor((v - lo) / step + 0.5) * step end
	if v < lo then v = lo elseif v > hi then v = hi end
	return tonumber(string.format("%.4f", v))
end

-- the box's text: the item's own format, else the settings slider's (Widgets SliderFormat)
local function SliderText(sl, v)
	if sl.format then
		local ok, t = xpcall(sl.format, geterrorhandler(), v)
		if ok and t ~= nil then return tostring(t) end
	end
	if sl.isPercent then return string.format("%d%%", math.floor(v * 100 + 0.5)) end
	local step = sl.step or 1
	if step < 1 then return string.format(step >= 0.1 and "%.1f" or "%.2f", v) end
	return tostring(math.floor(v + 0.5))
end

local function SliderGet(sl)
	if not sl.get then return sl.min or 0 end
	local ok, v = xpcall(sl.get, geterrorhandler())
	v = ok and tonumber(v) or nil
	return v or sl.min or 0
end

-- the item's set (the row's current item: a refresh hands the row a new one)
local function SliderSet(b, v)
	local sl = b.item and b.item.slider
	if not (sl and sl.set) or b.item.disabled then return end
	xpcall(sl.set, geterrorhandler(), v)
end

local function SliderFill(b, v)
	local sl = b.item and b.item.slider
	if not sl then return end
	local lo, hi = sl.min or 0, sl.max or 100
	local pct = (hi > lo) and ((v - lo) / (hi - lo)) or 0
	b.sl.fill:SetWidth(math.max(1, SLIDER_W * pct))
end

local function SliderRelease(b)
	if sliderDrag ~= b then return end
	sliderDrag = nil
	if ns.Widgets then ns.Widgets.sliderDragging = false end   -- (the live preview waits for this)
	local pv = b.slPending
	b.slPending = nil
	if pv ~= nil then SliderSet(b, pv) end   -- the release: the last value at once
end

-- the wheel over a slider row (its label, track or box): a step a notch
local function SliderWheel(b, delta)
	local sl = b.item and b.item.slider
	if not sl or b.item.disabled then return end
	local v = SliderStep(sl, b.sl:GetValue() + (delta > 0 and 1 or -1) * (sl.step or 1))
	if v ~= b.sl:GetValue() then b.sl:SetValue(v) end   -- OnValueChanged hands it on
end

local function NewSliderParts(b)
	local s = CreateFrame("Slider", nil, b)
	s:SetSize(SLIDER_W, 14)
	s:SetOrientation("HORIZONTAL")
	s:SetMinMaxValues(0, 100)
	s:SetValueStep(1)
	if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
	s.groove = s:CreateTexture(nil, "BACKGROUND")
	s.groove:SetHeight(3)
	s.groove:SetPoint("LEFT", s, "LEFT", 0, 0)
	s.groove:SetPoint("RIGHT", s, "RIGHT", 0, 0)
	s.groove:SetColorTexture(Core:Color("off"))
	s.fill = s:CreateTexture(nil, "ARTWORK")
	s.fill:SetHeight(3)
	s.fill:SetPoint("LEFT", s.groove, "LEFT", 0, 0)
	s.thumb = s:CreateTexture(nil, "OVERLAY")
	s.thumb:SetSize(12, 12)
	s.thumb:SetColorTexture(0.95, 0.96, 0.98, 1)
	s:SetThumbTexture(s.thumb)

	local box = CreateFrame("EditBox", nil, b)
	box:SetSize(SLIDER_BOX_W, 18)
	box:SetAutoFocus(false)
	box:SetFontObject(Core.fonts.row)
	box:SetJustifyH("CENTER")
	box:SetTextInsets(2, 2, 0, 0)
	Core:SolidTex(box, "windowBg", "BACKGROUND")
	Core:MakeBorder(box, "border")
	box.spMenuBox = true   -- (the Escape catcher lets its keys through)
	s.box = box

	-- a drag: the box follows every step, the item hears it ten times a second and on release
	b.slFlush = function()
		b.slQueued = false
		local pv = b.slPending
		if pv ~= nil and sliderDrag == b then b.slPending = nil; SliderSet(b, pv) end
	end
	s:SetScript("OnValueChanged", function(self, v)
		if b.slApplying then return end
		local sl = b.item and b.item.slider
		if not sl then return end
		v = SliderStep(sl, v)
		box:SetText(SliderText(sl, v))
		SliderFill(b, v)
		if b.item.disabled then return end
		if sliderDrag == b then
			b.slPending = v
			if not b.slQueued then
				b.slQueued = true
				C_Timer.After(SLIDER_SET_EVERY, b.slFlush)
			end
			return
		end
		SliderSet(b, v)   -- the wheel, the box, a click on the track
	end)
	s:SetScript("OnMouseDown", function()
		if b.item and b.item.disabled then return end
		sliderDrag = b
		if ns.Widgets then ns.Widgets.sliderDragging = true end
	end)
	s:SetScript("OnMouseUp", function() SliderRelease(b) end)
	s:SetScript("OnHide", function() SliderRelease(b) end)
	-- the hover look of its row (the row's own OnLeave fires as the mouse moves onto them)
	s:SetScript("OnEnter", function() RowEnter(b) end)
	s:SetScript("OnLeave", function() RowLeave(b) end)
	box:SetScript("OnEnter", function() RowEnter(b) end)
	box:SetScript("OnLeave", function() RowLeave(b) end)
	s:EnableMouseWheel(true)
	s:SetScript("OnMouseWheel", function(_, delta) SliderWheel(b, delta) end)
	box:EnableMouseWheel(true)
	box:SetScript("OnMouseWheel", function(_, delta) SliderWheel(b, delta) end)

	-- typing: Enter takes the value (clamped; "50" and "50%" are 50% on a percent slider,
	-- a typed fraction like "0.5" stays one), Escape or leaving puts the current one back
	box:SetScript("OnEditFocusGained", function(self)
		b.slEditing = true
		self:HighlightText()
	end)
	box:SetScript("OnEditFocusLost", function(self)
		b.slEditing = false
		self:HighlightText(0, 0)
		local sl = b.item and b.item.slider
		if sl then self:SetText(SliderText(sl, b.sl:GetValue())) end
	end)
	box:SetScript("OnEnterPressed", function(self)
		local sl = b.item and b.item.slider
		local text = self:GetText() or ""
		local v = tonumber((text:gsub("%%", "")))
		if sl and v and not b.item.disabled then
			if sl.isPercent and not (v <= 1 and text:find(".", 1, true)) then v = v / 100 end
			v = SliderStep(sl, v)
			if v ~= b.sl:GetValue() then b.sl:SetValue(v) else SliderSet(b, v) end
		end
		self:ClearFocus()
	end)
	box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	box:SetScript("OnHide", function(self) if self:HasFocus() then self:ClearFocus() end end)
	b.sl = s
	return s
end

-- a slider row's parts, placed and set from its item (not while its thumb is held or
-- its box is being typed in: a refresh mid-drag leaves the drag alone)
local function FillSlider(b, valueRight)
	local sl = b.item.slider
	local s = b.sl or NewSliderParts(b)
	local box = s.box
	box:ClearAllPoints()
	box:SetPoint("RIGHT", b, "RIGHT", -valueRight, 0)
	s:ClearAllPoints()
	s:SetPoint("RIGHT", box, "LEFT", -SLIDER_GAP, 0)
	local off = b.item.disabled and true or false
	if off then
		s.fill:SetColorTexture(Core:Color("off"))
	else
		local r, g, bl = ElementRGB(element)
		s.fill:SetColorTexture(r, g, bl, 1)
	end
	box:SetTextColor(Core:ColorIf(off, "textMute", "text"))
	s:EnableMouse(not off)
	box:EnableMouse(not off)
	if sliderDrag ~= b and not b.slEditing then
		local v = SliderStep(sl, SliderGet(sl))
		b.slApplying = true
		s:SetMinMaxValues(sl.min or 0, sl.max or 100)
		s:SetValueStep(sl.step or 1)
		s:SetValue(v)
		b.slApplying = false
		box:SetText(SliderText(sl, v))
		SliderFill(b, v)
	end
	s:Show()
	box:Show()
end

local function NewRow(lv)
	local b = CreateFrame("Button", nil, lv.content)
	b:SetHeight(ITEM_H)
	b:RegisterForClicks("LeftButtonUp")
	b.lv = lv
	b.bg = b:CreateTexture(nil, "BACKGROUND")
	b.bg:SetAllPoints(b)
	b.bg:SetColorTexture(0, 0, 0, 0)
	b.lit = b:CreateTexture(nil, "BACKGROUND", nil, 1)
	b.lit:SetAllPoints(b)
	b.lit:SetColorTexture(1, 1, 1, 1)
	b.lit:Hide()
	b.bar = b:CreateTexture(nil, "ARTWORK")
	b.bar:SetWidth(3)
	b.bar:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
	b.bar:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
	b.bar:Hide()
	local sp = ShamanPower
	if sp and sp.CreateElementBox then   -- (no brand file before a full restart: no box)
		b.box = sp:CreateElementBox(b, BOX)
		b.box:SetPoint("LEFT", b, "LEFT", BOX_X - EDGE, 0)
		b.box:Hide()
	end
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetSize(ICON_W, ICON_W)
	b.icon:SetPoint("LEFT", b, "LEFT", PAD_X, 0)
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	b.icon:Hide()
	b.text = b:CreateFontString(nil, "OVERLAY")
	b.text:SetFontObject(Core.fonts.row)
	b.text:SetJustifyH("LEFT")
	b.value = b:CreateFontString(nil, "OVERLAY")
	b.value:SetFontObject(Core.fonts.rowDim)
	b.value:SetJustifyH("RIGHT")
	b.arrow = b:CreateFontString(nil, "OVERLAY")
	b.arrow:SetFontObject(Core.fonts.tiny)
	b.arrow:SetPoint("CENTER", b, "RIGHT", -12, 0)
	b.arrow:SetText(">")
	b.arrow:SetTextColor(Core:Color("textDim"))
	-- a color in the value column: the swatch look of the settings rows, smaller
	b.swatch = CreateFrame("Frame", nil, b)
	b.swatch:SetSize(18, 12)
	Core:MakeBorder(b.swatch, "border")
	b.swatch.fill = b.swatch:CreateTexture(nil, "ARTWORK")
	b.swatch.fill:SetPoint("TOPLEFT", 1, -1)
	b.swatch.fill:SetPoint("BOTTOMRIGHT", -1, 1)
	b.swatch:Hide()
	b.speaker = NewSpeaker(b)
	b:SetScript("OnEnter", RowEnter)
	b:SetScript("OnLeave", RowLeave)
	b:SetScript("OnClick", RowClick)
	b:SetScript("OnMouseWheel", SliderWheel)   -- only a slider row takes the wheel (see FillLevel)
	return b
end

local function NewSep(lv)
	local t = lv.content:CreateTexture(nil, "ARTWORK")
	t:SetHeight(1)
	t:SetColorTexture(Core:Color("border"))
	return t
end

local function NewLevel(depth)
	local lv = CreateFrame("Frame", depth == 1 and "ShamanPowerContextMenu" or nil, UIParent)
	lv:SetFrameStrata("FULLSCREEN_DIALOG")
	lv:SetFrameLevel(BASE_LEVEL + depth * 10)
	lv:EnableMouse(true)   -- its edges and padding are not "outside"
	lv:Hide()
	lv.depth = depth
	Core:SolidTex(lv, "sidebarBg", "BACKGROUND")   -- solid: popups never fade
	-- the soft edge and the four elements along the top, over the rows (under the next level)
	local edge = CreateFrame("Frame", nil, lv)
	edge:SetAllPoints(lv)
	edge:SetFrameLevel(lv:GetFrameLevel() + 8)
	Core:MakeBorder(edge, "border", EDGE)
	local sp = ShamanPower
	if sp and sp.CreateElementStripe then   -- (no brand file before a full restart: no stripe)
		local stripe = sp:CreateElementStripe(lv)
		stripe:SetStripeHeight(STRIPE_H)
		stripe:SetPoint("TOPLEFT", lv, "TOPLEFT", 0, 0)
		stripe:SetPoint("TOPRIGHT", lv, "TOPRIGHT", 0, 0)
		stripe:SetFrameLevel(lv:GetFrameLevel() + 9)
	end

	local hd = CreateFrame("Frame", nil, lv)
	hd:SetPoint("TOPLEFT", lv, "TOPLEFT", 1, -1)
	hd:SetPoint("TOPRIGHT", lv, "TOPRIGHT", -1, -1)
	hd:SetHeight(HEADER_H - 2)
	-- the header's strip in the menu's element (a settings card's strip; no rule under it)
	hd.strip = hd:CreateTexture(nil, "BACKGROUND")
	hd.strip:SetPoint("TOPLEFT", lv, "TOPLEFT", 0, 0)
	hd.strip:SetPoint("TOPRIGHT", lv, "TOPRIGHT", 0, 0)
	hd.strip:SetHeight(HEADER_STRIP_H)
	hd.icons = {}
	for i = 1, 3 do
		local t = hd:CreateTexture(nil, "ARTWORK")
		t:Hide()
		hd.icons[i] = t
	end
	hd.text = hd:CreateFontString(nil, "OVERLAY")
	hd.text:SetFontObject(Core.fonts.row)
	hd.text:SetJustifyH("LEFT")
	hd.text:SetPoint("LEFT", hd, "TOPLEFT", 35, -16)
	hd:Hide()
	lv.header = hd

	local sc = CreateFrame("ScrollFrame", nil, lv)
	local ct = CreateFrame("Frame", nil, sc)
	ct:SetSize(10, 10)
	sc:SetScrollChild(ct)
	sc:EnableMouseWheel(true)   -- the wheel over the menu never closes it
	sc:SetScript("OnMouseWheel", function(self, delta)
		local maxS = math.max(0, ct:GetHeight() - self:GetHeight())
		self:SetVerticalScroll(math.max(0, math.min(maxS, self:GetVerticalScroll() - delta * WHEEL)))
	end)
	Core:AttachScrollbar(sc, ct, { offset = 2, width = 4 })
	lv.scroll, lv.content = sc, ct
	lv.rows, lv.seps = {}, {}
	-- the pending switch (see RowEnter): made once per level, no closure per hover
	lv.switch = function()
		local b = lv.pending
		if not b then return end
		local wait = SWITCH_DELAY - (GetTime() - (lv.pendingAt or 0))
		if wait > 0.01 then C_Timer.After(wait, lv.switch) return end
		lv.pending = nil
		if b.hover and lv:IsShown() then SetChild(lv, b) end
	end
	lv:SetScript("OnEnter", function()
		local parent = levels[depth - 1]
		if parent then parent.pending = nil end
	end)
	-- the wheel over its header or edge scrolls it too (it never reaches the catcher under it)
	lv:EnableMouseWheel(true)
	lv:SetScript("OnMouseWheel", function(_, delta) sc:GetScript("OnMouseWheel")(sc, delta) end)
	if depth == 1 then
		-- Escape in combat reaches it through UISpecialFrames: all of it closes
		tinsert(UISpecialFrames, "ShamanPowerContextMenu")
		lv:SetScript("OnHide", function() if spec then CM:Close() end end)
	end
	levels[depth] = lv
	return lv
end

-- the header: a spell icon (or slices of up to three) and the name
local function FillHeader(lv, header)
	local hd = lv.header
	local icons = header.icons or {}
	local n = math.min(#icons, 3)
	for i = 1, 3 do
		local t = hd.icons[i]
		if i <= n then
			t:ClearAllPoints()
			t:SetSize(18 / n, 18)
			t:SetPoint("TOPLEFT", hd, "TOPLEFT", 9 + (i - 1) * 18 / n, -7)
			t:SetTexture(icons[i])
			t:SetTexCoord(0.08 + 0.84 * (i - 1) / n, 0.08 + 0.84 * i / n, 0.08, 0.92)
			t:Show()
		else
			t:Hide()
		end
	end
	hd.text:ClearAllPoints()
	hd.text:SetPoint("LEFT", hd, "TOPLEFT", n > 0 and 35 or PAD_X, -16)
	hd.text:SetText(header.text or "")
	-- 16% of the element over the strip navy
	local er, eg, eb = ElementRGB(element)
	local sr, sg, sb = Core:Color("stripBg")
	hd.strip:SetColorTexture(er * 0.16 + sr * 0.84, eg * 0.16 + sg * 0.84, eb * 0.16 + sb * 0.84, 1)
	hd:Show()
end

-- the level's rows, measured to their longest text (never cut short)
local function FillLevel(lv, items, keepScroll)
	lv.items = items
	local root = lv.depth == 1
	local top = PAD_V
	if root and spec and spec.header then
		FillHeader(lv, spec.header)
		top = HEADER_H
	else
		lv.header:Hide()
	end
	if not measure then
		measure = lv:CreateFontString(nil, "OVERLAY")   -- only measures: never shown
		measure:Hide()
	end

	-- a level of choices keeps room for the tiny totem box: its text starts 28 in
	local choices = false
	for _, item in ipairs(items) do
		if item.selected ~= nil then choices = true break end
	end
	local textLeft = PAD_X                       -- in the row (the rows start EDGE in)
	if choices then textLeft = TEXT_X - EDGE end

	-- widths
	local hasSub, hasSpeaker = false, false
	local maxText, maxValue = 0, 0
	if root and spec and spec.header then
		measure:SetFontObject(Core.fonts.row)
		measure:SetText(spec.header.text or "")
		maxText = Width(measure) + 35 - textLeft   -- the header's text starts 35 in
	end
	local ri, si, contentH = 0, 0, 0
	for _, item in ipairs(items) do
		if item.separator then
			si = si + 1
			contentH = contentH + SEP_H
		else
			ri = ri + 1
			local b = lv.rows[ri] or NewRow(lv)
			lv.rows[ri] = b
			b.item = item
			b.vText, b.vOwn = nil, nil
			if item.value then
				local ok, vt, own = pcall(item.value)
				if ok then b.vText, b.vOwn = vt, own else Report(vt) end
			end
			measure:SetFontObject(Core.fonts.row)
			measure:SetText(item.text or "")
			local w = Width(measure) + (item.icon and (ICON_W + 6) or 0)
			if w > maxText then maxText = w end
			if item.slider then
				if maxValue < SLIDER_RESERVE then maxValue = SLIDER_RESERVE end
			elseif b.vText then
				measure:SetFontObject(Core.fonts.rowDim)
				measure:SetText(b.vText)
				if Width(measure) > maxValue then maxValue = Width(measure) end
			elseif item.swatch and maxValue < 18 then
				maxValue = 18
			end
			if item.sub then hasSub = true end
			if item.preview then hasSpeaker = true end
			contentH = contentH + ITEM_H
		end
	end
	local right = (hasSub and RIGHT_ARROW) or (hasSpeaker and RIGHT_SPEAKER) or RIGHT_PLAIN
	local w = math.ceil(EDGE + textLeft + maxText + (maxValue > 0 and (VALUE_GAP + maxValue) or 0) + right)
	w = math.max(w, root and MIN_W_ROOT or MIN_W_SUB)

	-- height: past the most it may be, the rows scroll (a thin bar on the right)
	local maxH = math.min(lv.maxH or MAX_H, (UIParent:GetHeight() or 768) - 32)
	local h = top + contentH + PAD_V
	local scrolls = h > maxH
	if scrolls then
		h = maxH
		w = w + 8
	end
	lv:SetSize(w, h)
	lv.scroll:ClearAllPoints()
	lv.scroll:SetPoint("TOPLEFT", lv, "TOPLEFT", EDGE, -top)
	lv.scroll:SetPoint("BOTTOMRIGHT", lv, "BOTTOMRIGHT", scrolls and -(EDGE + 8) or -EDGE, PAD_V)
	local cw = w - 2 * EDGE - (scrolls and 8 or 0)
	lv.content:SetSize(cw, math.max(contentH, 1))
	if not keepScroll then lv.scroll:SetVerticalScroll(0) end

	-- place and paint the rows
	local y = 0
	ri, si = 0, 0
	for _, item in ipairs(items) do
		if item.separator then
			si = si + 1
			local sep = lv.seps[si] or NewSep(lv)
			lv.seps[si] = sep
			sep:ClearAllPoints()
			sep:SetPoint("TOPLEFT", lv.content, "TOPLEFT", 8, -(y + 3))
			sep:SetPoint("TOPRIGHT", lv.content, "TOPRIGHT", -8, -(y + 3))
			sep:Show()
			y = y + SEP_H
		else
			ri = ri + 1
			local b = lv.rows[ri]
			b.index = ri
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", lv.content, "TOPLEFT", 0, -y)
			b:SetWidth(cw)
			if item.icon then
				b.icon:SetTexture(item.icon)
				b.icon:ClearAllPoints()
				b.icon:SetPoint("LEFT", b, "LEFT", textLeft, 0)
				b.icon:Show()
				b.text:SetPoint("LEFT", b, "LEFT", textLeft + ICON_W + 6, 0)
			else
				b.icon:Hide()
				b.text:SetPoint("LEFT", b, "LEFT", textLeft, 0)
			end
			b.text:SetText(item.text or "")
			local valueRight = hasSub and RIGHT_ARROW or RIGHT_PLAIN
			b.value:ClearAllPoints()
			b.value:SetPoint("RIGHT", b, "RIGHT", -valueRight, 0)
			if item.slider then
				FillSlider(b, valueRight)
				b:EnableMouseWheel(true)
			else
				if b.sl then b.sl:Hide(); b.sl.box:Hide() end
				b:EnableMouseWheel(false)   -- the wheel scrolls the level
			end
			if b.vText and not item.slider then
				b.value:SetText(b.vText)
				b.value:SetTextColor(Core:ColorIf(b.vOwn, "accentHi", "textDim"))
				b.value:Show()
			else
				b.value:Hide()
			end
			if item.swatch and not b.vText and not item.slider then
				b.swatch:ClearAllPoints()
				b.swatch:SetPoint("RIGHT", b, "RIGHT", -valueRight, 0)
				b.swatch.fill:SetColorTexture(item.swatch[1] or 1, item.swatch[2] or 1, item.swatch[3] or 1, 1)
				b.swatch:Show()
			else
				b.swatch:Hide()
			end
			b.arrow:SetShown(item.sub ~= nil)
			b.speaker:SetShown(item.preview ~= nil)
			b.hover = b:IsMouseOver() and true or false
			b:Show()
			PaintRow(b)
			y = y + ITEM_H
		end
	end
	for i = ri + 1, #lv.rows do
		local b = lv.rows[i]
		b.item, b.hover = nil, false
		b:Hide()
	end
	for i = si + 1, #lv.seps do lv.seps[i]:Hide() end
	if lv.openRow and not lv.openRow:IsShown() then lv.openRow = nil end
end

-- the root, under its anchor: kept on the screen when the anchor is on it (a
-- window still moving in is not measured; the root simply follows its anchor)
local function PlaceRoot(lv)
	local x, y = spec.x or -4, spec.y or -6
	lv:ClearAllPoints()
	lv:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", x, y)
	local s = anchor:GetEffectiveScale() / UIParent:GetEffectiveScale()
	local left, bottom, top = anchor:GetLeft(), anchor:GetBottom(), anchor:GetTop()
	if not (left and bottom and top) then return end
	left, bottom, top = left * s, bottom * s, top * s
	local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
	if top > sh or bottom < 0 then return end
	local w, h = lv:GetWidth(), lv:GetHeight()
	if left + x + w > sw - 4 then x = sw - 4 - w - left end
	if left + x < 4 then x = 4 - left end
	if bottom + y - h < 4 and top + h + 6 <= sh - 4 then
		lv:ClearAllPoints()
		lv:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", x, -y)   -- no room below: above it
	else
		lv:ClearAllPoints()
		lv:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", x, y)
	end
end

-- a submenu beside its row: to the right, or to the left at the screen's edge;
-- its first row level with the row, lifted when it would run off the bottom
local function PlaceSub(lv, row)
	local parent = row.lv
	lv:ClearAllPoints()
	local pr, pl = parent:GetRight(), parent:GetLeft()
	local rr, rl, rt = row:GetRight(), row:GetLeft(), row:GetTop()
	if not (pr and pl and rr and rl and rt) then
		lv:SetPoint("TOPLEFT", row, "TOPRIGHT", 2, PAD_V)
		return
	end
	local w, h = lv:GetWidth(), lv:GetHeight()
	local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
	local y = PAD_V
	if rt + y - h < 4 then y = h + 4 - rt end
	if rt + y > sh - 4 then y = sh - 4 - rt end
	if pr + 2 + w <= sw - 4 or pl - 2 - w < 4 then
		lv:SetPoint("TOPLEFT", row, "TOPRIGHT", (pr - rr) + 2, y)
	else
		lv:SetPoint("TOPRIGHT", row, "TOPLEFT", -(rl - pl) - 2, y)
	end
end

OpenLevel = function(depth, items, row, maxH)
	local lv = levels[depth] or NewLevel(depth)
	lv.spElement = element   -- its tooltips are lit in the menu's element (they walk up to here)
	lv.maxH = maxH
	lv.openRow, lv.pending = nil, nil
	lv.parentRow = row
	FillLevel(lv, items)
	if depth == 1 then PlaceRoot(lv) else PlaceSub(lv, row) end
	lv:Show()
end

CloseFrom = function(depth)
	for d = #levels, depth, -1 do
		local lv = levels[d]
		if lv:IsShown() then
			lv.pending, lv.parentRow = nil, nil
			local open = lv.openRow
			lv.openRow = nil
			if open then PaintRow(open) end
			lv:Hide()
		end
	end
end

-- ---------------------------------------------------------------------------
-- Outside clicks and Escape
-- ---------------------------------------------------------------------------
local function GetCatcher()
	if catcher then return catcher end
	-- one full-screen click under the menu, like the dropdown popup's: it closes the
	-- menu and is used up (nothing under it is clicked)
	catcher = CreateFrame("Button", nil, UIParent)
	catcher:SetFrameStrata("FULLSCREEN_DIALOG")
	catcher:SetFrameLevel(BASE_LEVEL)
	catcher:SetAllPoints(UIParent)
	catcher:EnableMouse(true)
	catcher:RegisterForClicks("AnyUp", "AnyDown")
	catcher:EnableMouseWheel(true)
	catcher:SetScript("OnClick", function() CM:Close() end)
	catcher:SetScript("OnMouseWheel", function() CM:Close() end)
	catcher:Hide()
	return catcher
end

-- Escape reaches a keyboard frame before the game's own Escape handling, which
-- would close the settings window too. Out of combat a frame above them takes
-- Escape for the menu and lets every other key through. SetPropagateKeyboardInput
-- may not be called in combat, so it is hidden when the fight starts (Escape then
-- reaches the menu through UISpecialFrames) and comes back after. A menu opened in
-- combat (EnableKeyboard may not be called then either) gets it when the fight ends.
local regen   -- that wait: made at load, registered only while it waits
local function KeysOn()
	if InCombatLockdown() then
		regen:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end
	if not keys then
		keys = CreateFrame("Frame", nil, UIParent)
		keys:SetFrameStrata("FULLSCREEN_DIALOG")
		keys:SetFrameLevel(BASE_LEVEL + 5)
		keys:SetAllPoints(UIParent)
		keys:EnableMouse(false)   -- keys only: clicks pass to the catcher under it
		keys:Hide()
		keys:EnableKeyboard(true)
		keys:SetScript("OnKeyDown", function(self, key)
			if InCombatLockdown() then return end
			local focus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
			if focus and focus.spMenuBox then   -- typing in a slider's box: Escape is the box's
				self:SetPropagateKeyboardInput(true)
				return
			end
			if key == "ESCAPE" then
				self:SetPropagateKeyboardInput(false)
				CM:Close()
			else
				self:SetPropagateKeyboardInput(true)
			end
		end)
		keys:SetScript("OnEvent", function(self, event)
			if event == "PLAYER_REGEN_DISABLED" then self:Hide()
			elseif spec then
				self:SetPropagateKeyboardInput(true)
				self:Show()
			end
		end)
	end
	keys:RegisterEvent("PLAYER_REGEN_DISABLED")
	keys:RegisterEvent("PLAYER_REGEN_ENABLED")
	keys:SetPropagateKeyboardInput(true)   -- a key held from before passes through
	keys:Show()
end

regen = CreateFrame("Frame")
regen:SetScript("OnEvent", function(self)
	self:UnregisterEvent("PLAYER_REGEN_ENABLED")
	if spec then KeysOn() end   -- still open when the fight ended
end)

local function KeysOff()
	regen:UnregisterEvent("PLAYER_REGEN_ENABLED")
	if not keys then return end
	keys:UnregisterAllEvents()
	keys:Hide()
end

-- ---------------------------------------------------------------------------
-- Public
-- ---------------------------------------------------------------------------
function CM.IsOpen(_) return spec ~= nil end

function CM:Open(a, sp)
	if spec then self:Close() end
	if not (a and type(sp) == "table") then return end
	local ok, items = pcall(sp.items)
	if not ok or type(items) ~= "table" then
		if not ok then Report(items) end
		return
	end
	spec, anchor = sp, a
	-- the element of the page or window it opens from (Ready Reminders: Fire)
	element = sp.element
	if not element and ns.Widgets and ns.Widgets.MenuElement then element = ns.Widgets:MenuElement(a) end
	element = element or "spirit"
	GetCatcher():Show()
	OpenLevel(1, items, nil, sp.maxHeight)
	KeysOn()
end

-- everything read again in place (a choice made, a value changed): the open
-- submenus stay open on the same rows
function CM:Refresh()
	if not spec then return end
	local ok, items = pcall(spec.items)
	if not ok or type(items) ~= "table" then
		if not ok then Report(items) end
		self:Close()
		return
	end
	FillLevel(levels[1], items, true)
	for d = 2, #levels do
		local lv = levels[d]
		if not lv:IsShown() then break end
		local row = levels[d - 1].openRow
		local item = row and row:IsShown() and row.item
		if not (item and item.sub) then CloseFrom(d) break end
		local okSub, sub = pcall(item.sub)
		if not okSub or type(sub) ~= "table" then
			if not okSub then Report(sub) end
			CloseFrom(d)
			break
		end
		FillLevel(lv, sub, true)
		PlaceSub(lv, row)
	end
end

-- the rows whose submenus are open, top down (to open the same ones again)
function CM.OpenPath(_)
	local path = {}
	for d = 1, #levels do
		local lv = levels[d]
		if not (lv:IsShown() and lv.openRow) then break end
		path[#path + 1] = lv.openRow.index
	end
	return path
end

function CM.ShowPath(_, path)
	if not spec or type(path) ~= "table" then return end
	for d, index in ipairs(path) do
		local lv = levels[d]
		local b = lv and lv:IsShown() and lv.rows[index]
		if not (b and b:IsShown() and b.item and b.item.sub) then break end
		SetChild(lv, b)
	end
end

function CM.Close(_)
	if not spec then return end
	local closing = spec
	spec, anchor = nil, nil
	CloseFrom(1)
	if catcher then catcher:Hide() end
	KeysOff()
	if closing.onClose then xpcall(closing.onClose, geterrorhandler()) end
end
