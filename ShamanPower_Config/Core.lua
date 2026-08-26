-- ShamanPower_Config :: Core
-- Design tokens, font objects, and drawing primitives.
-- Everything here is built from CreateFrame/CreateTexture only -- no Blizzard
-- templates are used anywhere in this module, which is what keeps the look
-- identical across every flavor from Vanilla through Retail.

local ADDON, ns = ...

local Core = {}
ns.Core = Core

-- ---------------------------------------------------------------------------
-- Palette
-- Accent is ShamanPower blue (|cff0070dd), already the brand color used
-- throughout the existing option text.
-- ---------------------------------------------------------------------------
local C = {
	windowBg   = { 0.055, 0.063, 0.078 },
	sidebarBg  = { 0.071, 0.082, 0.102 },
	contentBg  = { 0.086, 0.098, 0.122 },
	rowBg      = { 0.110, 0.125, 0.153 },
	rowHover   = { 0.145, 0.165, 0.200 },
	border     = { 0.180, 0.204, 0.243 },
	borderSoft = { 0.130, 0.148, 0.180 },

	accent     = { 0.000, 0.439, 0.867 },
	accentHi   = { 0.247, 0.663, 1.000 },
	accentDim  = { 0.000, 0.439, 0.867, 0.25 },

	text       = { 0.902, 0.918, 0.941 },
	textDim    = { 0.541, 0.580, 0.651 },
	textMute   = { 0.353, 0.392, 0.455 },

	on         = { 0.180, 0.800, 0.443 },
	off        = { 0.320, 0.350, 0.400 },
	warn       = { 0.900, 0.290, 0.290 },
}
Core.colors = C

-- Conditional colour. Core:Color returns four values, and Lua truncates a
-- multi-return call to one value when it sits inside an and/or chain -- so
-- `cond and Core:Color("a") or Core:Color("b")` silently passes a single
-- number to SetColorTexture. Branch on the key instead of the call.
function Core:ColorIf(cond, keyTrue, keyFalse, alphaOverride)
	return self:Color(cond and keyTrue or keyFalse, alphaOverride)
end

function Core:Color(key, alphaOverride)
	local c = C[key]
	if not c then return 1, 1, 1, 1 end
	return c[1], c[2], c[3], alphaOverride or c[4] or 1
end

-- ---------------------------------------------------------------------------
-- Compat shims
-- SetGradient took (orientation, r,g,b,a, r,g,b,a) before 10.0 and
-- (orientation, colorObj, colorObj) after. 2.5.6 predates the change, so probe
-- once at load and route accordingly.
-- ---------------------------------------------------------------------------
local probe = UIParent:CreateTexture(nil, "BACKGROUND")
local hasColorObjectGradient = false
if probe.SetGradient and CreateColor then
	hasColorObjectGradient = pcall(function()
		probe:SetGradient("HORIZONTAL", CreateColor(1, 1, 1, 1), CreateColor(0, 0, 0, 0))
	end)
end
probe:Hide()

function Core:Gradient(tex, orientation, r1, g1, b1, a1, r2, g2, b2, a2)
	if hasColorObjectGradient then
		tex:SetGradient(orientation, CreateColor(r1, g1, b1, a1), CreateColor(r2, g2, b2, a2))
	elseif tex.SetGradientAlpha then
		tex:SetGradientAlpha(orientation, r1, g1, b1, a1, r2, g2, b2, a2)
	end
end

-- ---------------------------------------------------------------------------
-- Fonts
-- ---------------------------------------------------------------------------
local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local FONT_NARROW = "Fonts\\ARIALN.TTF"

local function MakeFont(suffix, path, size, flags, colorKey)
	local f = CreateFont("ShamanPowerConfigFont" .. suffix)
	f:SetFont(path, size, flags)
	f:SetShadowOffset(1, -1)
	f:SetShadowColor(0, 0, 0, 0.8)
	if colorKey then
		f:SetTextColor(Core:Color(colorKey))
	end
	return f
end

Core.fonts = {
	title    = MakeFont("Title",   FONT,        22, "",       "text"),
	subtitle = MakeFont("Sub",     FONT,        11, "",       "textDim"),
	brand    = MakeFont("Brand",   FONT,        16, "",       "text"),
	row      = MakeFont("Row",     FONT,        12, "",       "text"),
	rowDim   = MakeFont("RowDim",  FONT,        12, "",       "textDim"),
	section  = MakeFont("Section", FONT_NARROW, 12, "",       "textDim"),
	nav      = MakeFont("Nav",     FONT,        12, "",       "textDim"),
	navOn    = MakeFont("NavOn",   FONT,        12, "",       "text"),
	group    = MakeFont("Group",   FONT_NARROW, 11, "",       "accentHi"),
	tiny     = MakeFont("Tiny",    FONT_NARROW, 10, "",       "textMute"),
	button   = MakeFont("Button",  FONT,        12, "",       "text"),
}

-- ---------------------------------------------------------------------------
-- Drawing primitives
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Background opacity
-- Panel backgrounds and row cards register here so one profile setting can
-- fade them together. Borders, inputs, popups, icons and text never register,
-- which keeps edges and labels crisp at low opacity.
-- ---------------------------------------------------------------------------
Core.opacity = 1
local fadeRegistry = setmetatable({}, { __mode = "k" })

function Core:RegisterFade(tex, colorKey, baseAlpha)
	fadeRegistry[tex] = { key = colorKey, alpha = baseAlpha or 1 }
	local r, g, b = self:Color(colorKey)
	tex:SetColorTexture(r, g, b, (baseAlpha or 1) * self.opacity)
end

function Core:ApplyOpacity(o)
	o = tonumber(o) or 1
	if o < 0.1 then o = 0.1 elseif o > 1 then o = 1 end
	self.opacity = o
	for tex, info in pairs(fadeRegistry) do
		local r, g, b = self:Color(info.key)
		tex:SetColorTexture(r, g, b, info.alpha * o)
	end
end

-- Pull the profile value and repaint only if it differs from what is drawn.
function Core:SyncOpacity()
	local opt = ShamanPower and ShamanPower.opt
	local o = opt and opt.uiOpacity or 1
	if math.abs(o - self.opacity) > 0.001 then
		self:ApplyOpacity(o)
	end
end

-- Flat filled texture pinned to a region. Pass fade=true for panel
-- backgrounds that should follow the opacity setting.
function Core:SolidTex(parent, colorKey, layer, alpha, fade)
	local t = parent:CreateTexture(nil, layer or "BACKGROUND")
	t:SetAllPoints(parent)
	if fade then
		self:RegisterFade(t, colorKey, alpha or 1)
	else
		t:SetColorTexture(self:Color(colorKey, alpha))
	end
	return t
end

-- 1px border drawn as four edge textures. Cheaper and sharper than a backdrop,
-- and sidesteps BackdropTemplate differences between flavors entirely.
function Core:MakeBorder(frame, colorKey, thickness, inset)
	thickness = thickness or 1
	inset = inset or 0
	local r, g, b, a = self:Color(colorKey or "border")
	local edges = {}
	local sides = {
		top    = { "TOPLEFT",    inset, -inset, "TOPRIGHT",     -inset, -inset, nil, thickness },
		bottom = { "BOTTOMLEFT", inset,  inset, "BOTTOMRIGHT",  -inset,  inset, nil, thickness },
		left   = { "TOPLEFT",    inset, -inset, "BOTTOMLEFT",    inset,  inset, thickness, nil },
		right  = { "TOPRIGHT",  -inset, -inset, "BOTTOMRIGHT",  -inset,  inset, thickness, nil },
	}
	for name, s in pairs(sides) do
		local t = frame:CreateTexture(nil, "BORDER")
		t:SetColorTexture(r, g, b, a)
		t:SetPoint(s[1], frame, s[1], s[2], s[3])
		t:SetPoint(s[4], frame, s[4], s[5], s[6])
		if s[7] then t:SetWidth(s[7]) end
		if s[8] then t:SetHeight(s[8]) end
		edges[name] = t
	end
	frame.spBorder = edges
	return edges
end

function Core:SetBorderColor(frame, colorKey, alpha)
	if not frame.spBorder then return end
	local r, g, b, a = self:Color(colorKey, alpha)
	for _, t in pairs(frame.spBorder) do
		t:SetColorTexture(r, g, b, a)
	end
end

-- Card background used by every settings row.
function Core:RowBg(frame)
	local bg = frame:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(frame)
	self:RegisterFade(bg, "rowBg", 1)
	frame.spBg = bg
	self:MakeBorder(frame, "borderSoft")
	return bg
end

function Core:HoverHighlight(frame)
	frame:SetScript("OnEnter", function(self)
		if self.spBg then self.spBg:SetColorTexture(Core:Color("rowHover", Core.opacity)) end
		if self.spOnEnter then self:spOnEnter() end
	end)
	frame:SetScript("OnLeave", function(self)
		if self.spBg then self.spBg:SetColorTexture(Core:Color("rowBg", Core.opacity)) end
		if self.spOnLeave then self:spOnLeave() end
	end)
end

-- Horizontal accent glow used under the page header.
function Core:AccentGlow(parent, height)
	local t = parent:CreateTexture(nil, "ARTWORK")
	t:SetHeight(height or 2)
	t:SetColorTexture(1, 1, 1, 1)
	local r, g, b = self:Color("accentHi")
	self:Gradient(t, "HORIZONTAL", r, g, b, 0, r, g, b, 0.9)
	return t
end

-- ---------------------------------------------------------------------------
-- Tooltip helper
-- ---------------------------------------------------------------------------
-- Safe to call repeatedly on the same frame: the hooks are installed exactly
-- once and read spTipTitle/spTipBody at hover time, so a pooled frame that is
-- reconfigured for a different option just gets its fields overwritten.
-- (HookScript accumulates handlers, so hooking on every call would stack one
-- tooltip per reuse.) Passing nil for both clears the tooltip.
local function TipOnEnter(self)
	local title = self.spTipTitle
	local body  = self.spTipBody
	if title == "" then title = nil end
	if body == "" then body = nil end
	if not title and not body then return end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	-- Rows run the full width of the page, so an ANCHOR_RIGHT tooltip on one
	-- would otherwise open past the screen edge and get clipped.
	GameTooltip:SetClampedToScreen(true)
	if title then GameTooltip:AddLine(title, 1, 1, 1) end
	if body then GameTooltip:AddLine(body, 0.8, 0.8, 0.8, true) end
	GameTooltip:Show()
end

local function TipOnLeave(self)
	if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
end

function Core:AttachTooltip(frame, titleText, bodyText)
	frame.spTipTitle = titleText
	frame.spTipBody = bodyText
	if frame.spTipHooked then return end
	if not titleText and not bodyText then return end
	frame.spTipHooked = true
	frame:HookScript("OnEnter", TipOnEnter)
	frame:HookScript("OnLeave", TipOnLeave)
end

-- Drop the tooltip if it is currently showing for this frame (a hovered row
-- that gets released back to its pool never receives OnLeave).
function Core:HideTooltipFor(frame)
	if GameTooltip:IsOwned(frame) then GameTooltip:Hide() end
end

-- ---------------------------------------------------------------------------
-- Label clamping
-- Long localized labels must not run under the control cluster on the right.
-- Truncate with an ellipsis and expose the full string on hover.
-- ---------------------------------------------------------------------------
function Core:ClampLabel(fontString, maxWidth, fullText)
	if not fontString or not maxWidth or maxWidth <= 0 then return end
	fontString:SetText(fullText)
	if fontString:GetStringWidth() <= maxWidth then
		fontString.spTruncated = false
		return
	end
	local lo, hi = 1, #fullText
	while lo < hi do
		local mid = math.floor((lo + hi) / 2) + 1
		fontString:SetText(string.sub(fullText, 1, mid) .. "...")
		if fontString:GetStringWidth() <= maxWidth then lo = mid else hi = mid - 1 end
	end
	fontString:SetText(string.sub(fullText, 1, lo) .. "...")
	fontString.spTruncated = true
end

-- ---------------------------------------------------------------------------
-- Scrollbar
-- A thin track + thumb for a ScrollFrame, drawn from primitives. Shows only
-- when the scroll child is taller than the viewport; the thumb is draggable
-- and clicking the track pages toward the click. Follows wheel scrolling
-- through the ScrollFrame's own OnVerticalScroll / OnScrollRangeChanged.
-- ---------------------------------------------------------------------------
function Core:AttachScrollbar(scroll, child, opts)
	opts = opts or {}
	local width  = opts.width or 4
	local offset = opts.offset or 6      -- gap between viewport edge and track
	local minThumb = 24

	local track = CreateFrame("Button", nil, scroll:GetParent())
	track:SetWidth(width)
	track:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", offset + width, -2)
	track:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", offset + width, 2)
	track:SetFrameLevel(scroll:GetFrameLevel() + 5)
	track.bg = track:CreateTexture(nil, "BACKGROUND")
	track.bg:SetAllPoints(track)
	track.bg:SetColorTexture(self:Color("border", 0.5))
	track:Hide()

	local thumb = CreateFrame("Button", nil, track)
	thumb:SetWidth(width)
	thumb:SetPoint("TOP", track, "TOP", 0, 0)
	thumb.tex = thumb:CreateTexture(nil, "ARTWORK")
	thumb.tex:SetAllPoints(thumb)
	thumb.tex:SetColorTexture(self:Color("textMute"))
	-- Wider hit area than the 4px visual so it is easy to grab.
	thumb:SetHitRectInsets(-6, -6, 0, 0)
	track:SetHitRectInsets(-6, -6, 0, 0)

	local function Range()
		local viewH = scroll:GetHeight()
		local contentH = child:GetHeight()
		return viewH, contentH, math.max(0, contentH - viewH)
	end

	local function Update()
		local viewH, contentH, maxScroll = Range()
		if maxScroll <= 1 or viewH <= 0 then track:Hide() return end
		track:Show()
		local trackH = track:GetHeight()
		local thumbH = math.max(minThumb, math.floor(trackH * (viewH / contentH)))
		if thumbH > trackH then thumbH = trackH end
		thumb:SetHeight(thumbH)
		local frac = scroll:GetVerticalScroll() / maxScroll
		if frac > 1 then frac = 1 elseif frac < 0 then frac = 0 end
		thumb:ClearAllPoints()
		thumb:SetPoint("TOP", track, "TOP", 0, -math.floor((trackH - thumbH) * frac))
	end

	local function ScrollToFraction(frac)
		local _, _, maxScroll = Range()
		if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
		scroll:SetVerticalScroll(maxScroll * frac)
	end

	-- Follow the scroll frame itself, whatever moved it (wheel, code, drag).
	scroll:HookScript("OnVerticalScroll", Update)
	scroll:HookScript("OnScrollRangeChanged", Update)
	scroll:HookScript("OnSizeChanged", Update)
	scroll:HookScript("OnShow", Update)

	-- Thumb drag: keep the grab point under the cursor.
	local dragging, grabOffset = false, 0
	local function CursorY()
		local _, y = GetCursorPosition()
		return y / track:GetEffectiveScale()
	end
	thumb:SetScript("OnMouseDown", function(self)
		dragging = true
		grabOffset = self:GetTop() - CursorY()
		self.tex:SetColorTexture(Core:Color("accentHi"))
	end)
	thumb:SetScript("OnMouseUp", function(self)
		dragging = false
		self.tex:SetColorTexture(Core:Color(self:IsMouseOver() and "accent" or "textMute"))
	end)
	thumb:SetScript("OnEnter", function(self) if not dragging then self.tex:SetColorTexture(Core:Color("accent")) end end)
	thumb:SetScript("OnLeave", function(self) if not dragging then self.tex:SetColorTexture(Core:Color("textMute")) end end)
	thumb:SetScript("OnUpdate", function(self)
		if not dragging then return end
		if not IsMouseButtonDown("LeftButton") then
			dragging = false
			self.tex:SetColorTexture(Core:Color("textMute"))
			return
		end
		local trackH, thumbH = track:GetHeight(), self:GetHeight()
		local travel = trackH - thumbH
		if travel <= 0 then return end
		local topWanted = CursorY() + grabOffset
		local frac = (track:GetTop() - topWanted) / travel
		ScrollToFraction(frac)
	end)

	-- Click on the track (outside the thumb): page toward the click.
	track:SetScript("OnClick", function(self)
		local y = CursorY()
		local viewH, _, maxScroll = Range()
		if maxScroll <= 0 then return end
		local cur = scroll:GetVerticalScroll()
		if y > thumb:GetTop() then
			scroll:SetVerticalScroll(math.max(0, cur - viewH))
		elseif y < thumb:GetBottom() then
			scroll:SetVerticalScroll(math.min(maxScroll, cur + viewH))
		end
	end)
	-- Wheel over the bar behaves like wheel over the content.
	track:EnableMouseWheel(true)
	track:SetScript("OnMouseWheel", function(_, delta)
		local h = scroll:GetScript("OnMouseWheel")
		if h then h(scroll, delta) end
	end)

	scroll.spScrollbar = track
	scroll.spScrollbarUpdate = Update
	return track
end

return Core
