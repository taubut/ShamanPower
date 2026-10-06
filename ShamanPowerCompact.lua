-- ============================================================================
-- ShamanPowerCompact.lua
-- "Compact" totem bar display style: each totem slot is an element-colored
-- LINE instead of an icon. Duration drains as an outline (both long edges
-- shrink together from the far end toward the start - top to bottom on a
-- vertical line) or as the line itself draining ("fill" mode), the pulse
-- countdown refills inside the line, and a tiny optional icon square sits
-- above or below it. The Earth Shield button becomes a segmented line, one
-- segment per charge.
--
-- The secure buttons are reused unchanged (click / flyout behavior is
-- identical); this file only draws on them. Everything is driven by
-- SP:CompactOpts(), which the setup wizard also feeds with its preview options
-- so the mock and the real bar are painted by the same code.
-- ============================================================================

local SP = ShamanPower

local FONT  = "Fonts\\FRIZQT__.TTF"
local EMPTY = { r = 0.32, g = 0.32, b = 0.32 }   -- "nothing down" line color
local ES_MAX_CHARGES = 6
-- General > Themes (st.compact): a themed line colour per element, filled in place
-- when a theme is in play (nothing is allocated while painting)
local THEMED_LINE = { { r = 1, g = 1, b = 1 }, { r = 1, g = 1, b = 1 },
	{ r = 1, g = 1, b = 1 }, { r = 1, g = 1, b = 1 } }

-- ---------------------------------------------------------------------------
-- Line textures
-- ---------------------------------------------------------------------------
-- The lines were plain colour fills. opt.compactLineTexture names a statusbar
-- texture from LibSharedMedia instead ("Flat" = the plain fill, the default), so
-- the list holds whatever the player's other addons registered plus the four
-- small greyscale bars shipped in Media/. A texture is tinted with the line's
-- colour, and turned a quarter for vertical lines so its grain runs along them.
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
local FLAT = "Flat"
if LSM then
	local dir = "Interface\\AddOns\\ShamanPower\\Media\\"
	LSM:Register("statusbar", "ShamanPower Smooth", dir .. "bar-smooth.tga")
	LSM:Register("statusbar", "ShamanPower Gloss",  dir .. "bar-gloss.tga")
	LSM:Register("statusbar", "ShamanPower Round",  dir .. "bar-round.tga")
	LSM:Register("statusbar", "ShamanPower Bevel",  dir .. "bar-bevel.tga")
end

function SP:CompactLineTextureList()
	local t = { [FLAT] = "Minimal (flat color)" }
	if LSM then
		for _, name in ipairs(LSM:List("statusbar")) do t[name] = name end
	end
	return t
end

local function LineTexturePath(name)
	if not name or name == FLAT or not LSM then return nil end
	return LSM:Fetch("statusbar", name, true)
end

-- Colour one bar piece, textured or flat. Only touches the texture when it changes.
local function PaintBar(t, tex, vertical, r, g, b, a)
	if tex then
		if t.spTex ~= tex then t:SetTexture(tex); t.spTex = tex; t.spTexVert = nil end
		if t.spTexVert ~= vertical then
			if vertical then t:SetTexCoord(1, 0, 0, 0, 1, 1, 0, 1) else t:SetTexCoord(0, 1, 0, 1) end
			t.spTexVert = vertical
		end
		t:SetVertexColor(r, g, b, a)
	else
		if t.spTex then
			t:SetVertexColor(1, 1, 1, 1); t:SetTexCoord(0, 1, 0, 1)
			t.spTex, t.spTexVert = nil, nil
		end
		t:SetColorTexture(r, g, b, a)
	end
end

-- ---------------------------------------------------------------------------
-- Look defaults
-- ---------------------------------------------------------------------------
-- What an unset look setting means. Version 2 (textured lines, element-coloured
-- outlines at rest, icon squares on, thicker horizontal lines so the pulse
-- countdown fits, 15 px icons). These keys deliberately have NO AceDB default:
-- "nil in the profile" has to mean "never chosen", which is what lets
-- PreserveCompactLook tell an existing Compact user from a new one.
local LOOK = {
	compactLineTexture = "ShamanPower Smooth",
	compactIdleOutline = "element",
	compactIconSquares = "before",
	compactIconSize = 15,
	compactFlyoutButtonSize = 15,
}
-- What the same unset settings meant up to 2.1.x.
local LEGACY_LOOK = {
	compactLineTexture = "Flat",
	compactIdleOutline = "none",
	compactIconSquares = "off",
	compactIconSize = 12,
	compactFlyoutButtonSize = 28,
}
SP.CompactLookDefaults = LOOK

function SP:CompactDefaultThickness(vertical, legacy)
	if vertical then return 16 end
	return legacy and 10 or 14   -- 14: the pulse countdown text needs at least that to be drawn
end

-- Runs once per profile. Someone already using Compact keeps exactly what is on
-- their screen: every look setting they never touched is written down at its OLD
-- meaning before the new defaults take over. Everyone else (and anyone pressing
-- "Reset Compact Style to Defaults") gets the new look.
function SP:PreserveCompactLook()
	local o = self.opt
	if not o or o.compactLookVersion then return end
	if o.compactStyle then
		for key, value in pairs(LEGACY_LOOK) do
			if o[key] == nil then o[key] = value end
		end
		if o.compactThickness == nil then
			o.compactThickness = self:CompactDefaultThickness((o.compactOrientation or "horizontal") == "vertical", true)
		end
	end
	o.compactLookVersion = 2
end

-- ---------------------------------------------------------------------------
-- Option access
-- ---------------------------------------------------------------------------
function SP:CompactActive()
	if self.UsingBlizzardTotemBar and self:UsingBlizzardTotemBar() then return false end
	return self.opt and self.opt.compactStyle and true or false
end

-- Normalized compact options. `o` defaults to the live profile; the wizard
-- passes its own table when previewing a layout.
function SP:CompactOpts(o)
	o = o or self.opt
	local vertical = (o.compactOrientation or "horizontal") == "vertical"
	local T = o.compactThickness
	if T == nil then T = self:CompactDefaultThickness(vertical) end
	local mode = o.compactDurationMode
	if mode == nil or mode == "auto" then mode = vertical and "fill" or "outline" end
	local sq = o.compactIconSquares or LOOK.compactIconSquares
	if sq == "above" then sq = "before" elseif sq == "below" then sq = "after" end   -- old values
	return {
		vertical  = vertical,
		L         = o.compactLength or 120,
		T         = T,
		ow        = o.compactOutlineWidth or 2,
		olColor   = (o.compactOutlineColorMode == "custom") and o.compactOutlineColor or nil,
		fill      = (mode == "fill"),
		sq        = sq,
		iq        = o.compactIconSize or LOOK.compactIconSize,
		pulseText = o.compactPulseText ~= false,
		pulseBar  = o.compactPulseBar ~= false,
		tex       = LineTexturePath(o.compactLineTexture or LOOK.compactLineTexture),
	}
end

function SP:CompactVerticalLines()
	return self:CompactOpts().vertical
end

-- Direction the totem slots are laid out along. Compact horizontal lines stack
-- top-to-bottom (a vertical bar); vertical lines sit side by side.
function SP:IsTotemBarHorizontal()
	if self:CompactActive() then return self:CompactVerticalLines() end
	return self.opt.layout == "Horizontal"
end

-- Button size (bw, bh), slot size including the icon square (sw, sh), and the
-- button's offset inside its slot (ox, oy; oy negative = down). Icon-style
-- bars are the classic 26x26.
-- Icon squares sit BEFORE / AFTER the line along its own axis: left / right of a
-- horizontal line (the row stays one line tall), above / below a vertical one.
function SP:GetTotemSlotDims(o)
	if not self:CompactActive() and not o then return 26, 26, 26, 26, 0, 0 end
	local co = self:CompactOpts(o)
	local extra = (co.sq ~= "off") and (co.iq + 2) or 0
	if co.vertical then
		local sw = math.max(co.T, (co.sq ~= "off") and co.iq or 0)
		return co.T, co.L, sw, co.L + extra, math.floor((sw - co.T) / 2), (co.sq == "before") and -extra or 0
	else
		local sh = math.max(co.T, (co.sq ~= "off") and co.iq or 0)
		return co.L, co.T, co.L + extra, sh, (co.sq == "before") and extra or 0, -math.floor((sh - co.T) / 2)
	end
end

-- ---------------------------------------------------------------------------
-- Visuals: create / layout / paint (shared by the real bar and the wizard mock)
-- ---------------------------------------------------------------------------
local function Tex(frame, layer, sub)
	local t = frame:CreateTexture(nil, layer, nil, sub)
	t:SetColorTexture(1, 1, 1, 1)
	t:Hide()
	return t
end

function SP:CreateCompactVisuals(frame)
	local c = {}
	c.bg    = Tex(frame, "BACKGROUND", 0); c.bg:SetAllPoints(frame); c.bg:SetColorTexture(0, 0, 0, 0.55)
	c.line  = Tex(frame, "ARTWORK", 0)
	c.pulse = Tex(frame, "ARTWORK", 2); c.pulse:SetColorTexture(1, 1, 1, 0.35)
	-- outline: [1] start cap, [2] far cap, [3] and [4] the two long edges
	c.ol    = { Tex(frame, "OVERLAY", 0), Tex(frame, "OVERLAY", 0), Tex(frame, "OVERLAY", 0), Tex(frame, "OVERLAY", 0) }
	c.text  = frame:CreateFontString(nil, "OVERLAY", nil, 7)
	SP:SetSPFont(c.text, "timers", 10, "OUTLINE"); c.text:SetTextColor(1, 1, 1); c.text:Hide()
	c.sqBd  = Tex(frame, "ARTWORK", 0); c.sqBd:SetColorTexture(0, 0, 0, 0.9)
	c.sq    = Tex(frame, "ARTWORK", 1); c.sq:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	return c
end

function SP:HideCompactVisuals(c)
	if not c then return end
	c.bg:Hide(); c.line:Hide(); c.pulse:Hide(); c.text:Hide(); c.sq:Hide(); c.sqBd:Hide()
	for i = 1, 4 do c.ol[i]:Hide() end
end

-- Anchor every piece for the given size/options. `frame` must already be
-- sized bw x bh (the line, outline included).
function SP:LayoutCompactVisuals(c, frame, co, bw, bh)
	local ow = co.ow
	c.vertical, c.fill, c.ow, c.bw, c.bh = co.vertical, co.fill, ow, bw, bh
	c.lineLen = (co.vertical and bh or bw) - 2 * ow
	c.pulseBar = co.pulseBar
	c.olColor = co.olColor
	c.tex = co.tex

	-- the line: inset by the outline; in fill mode only the start edge is anchored
	c.line:ClearAllPoints()
	if co.fill then
		if co.vertical then
			c.line:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", ow, ow)
			c.line:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -ow, ow)
			c.line:SetHeight(c.lineLen)
		else
			c.line:SetPoint("TOPLEFT", frame, "TOPLEFT", ow, -ow)
			c.line:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", ow, ow)
			c.line:SetWidth(c.lineLen)
		end
	else
		c.line:SetPoint("TOPLEFT", frame, "TOPLEFT", ow, -ow)
		c.line:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -ow, ow)
	end

	-- outline pieces. Start cap = bottom (vertical) / left (horizontal); far
	-- cap = top / right; the two long edges are anchored at the start so they
	-- can shrink toward it.
	local startCap, farCap, edgeA, edgeB = c.ol[1], c.ol[2], c.ol[3], c.ol[4]
	startCap:ClearAllPoints(); farCap:ClearAllPoints(); edgeA:ClearAllPoints(); edgeB:ClearAllPoints()
	if co.vertical then
		startCap:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0); startCap:SetSize(bw, ow)
		farCap:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0);         farCap:SetSize(bw, ow)
		edgeA:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0);    edgeA:SetSize(ow, bh)
		edgeB:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0);  edgeB:SetSize(ow, bh)
	else
		startCap:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0);       startCap:SetSize(ow, bh)
		farCap:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0);       farCap:SetSize(ow, bh)
		edgeA:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0);          edgeA:SetSize(bw, ow)
		edgeB:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0);    edgeB:SetSize(bw, ow)
	end

	-- pulse refill from the start of the line
	c.pulse:ClearAllPoints()
	if co.vertical then
		c.pulse:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", ow, ow)
		c.pulse:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -ow, ow)
		c.pulse:SetHeight(1)
	else
		c.pulse:SetPoint("TOPLEFT", frame, "TOPLEFT", ow, -ow)
		c.pulse:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", ow, ow)
		c.pulse:SetWidth(1)
	end

	-- pulse text: start of a horizontal line, top of a vertical one; hidden on
	-- lines too thin to read it
	-- (never give the text a fixed width: WoW would truncate "1.4" to "..." on a
	-- narrow vertical line - let it overhang instead)
	local fs = math.max(7, math.min(14, co.T - (co.vertical and 5 or 3)))
	SP:SetSPFont(c.text, "timers", fs, "OUTLINE")
	c.text:SetWordWrap(false)
	c.text:ClearAllPoints()
	c.text:SetWidth(0)
	if co.vertical then
		c.text:SetPoint("TOP", frame, "TOP", 0, -(ow + 2)); c.text:SetJustifyH("CENTER")
	else
		c.text:SetPoint("LEFT", frame, "LEFT", ow + 3, 0); c.text:SetJustifyH("LEFT")
	end
	c.textOk = co.pulseText and co.T >= 14

	-- icon square above / below
	c.sqBd:ClearAllPoints()
	if co.sq == "off" then
		c.sqOn = false
		c.sq:ClearAllPoints()
	else
		c.sqOn = true
		c.sq:SetSize(co.iq, co.iq); c.sqBd:SetSize(co.iq + 2, co.iq + 2)
		c.sqSize = co.iq
		c.sqSide = co.vertical and (co.sq == "before" and "top" or "bottom") or (co.sq == "before" and "left" or "right")
		SP:AnchorCompactSquare(c, frame)
		c.sqBd:SetPoint("CENTER", c.sq, "CENTER", 0, 0)
	end
	c.bg:Show()
end

-- The square sits just off one end of the line. A flyout arrow tab can sit on
-- that same end (in a fight, or always with the arrow options); then the
-- square moves out past the tab instead of being cut off by it.
function SP:AnchorCompactSquare(c, frame)
	if not (c and c.sqOn and c.sqSide and frame) then return end
	local across = (self.FlyoutArrowGapOn and self:FlyoutArrowGapOn(frame, c.sqSide)) or 0
	local gap = self.CompactSquareOffset and self:CompactSquareOffset(across) or 2
	c.sq:ClearAllPoints()
	if c.sqSide == "top" then c.sq:SetPoint("BOTTOM", frame, "TOP", 0, gap)
	elseif c.sqSide == "bottom" then c.sq:SetPoint("TOP", frame, "BOTTOM", 0, -gap)
	elseif c.sqSide == "left" then c.sq:SetPoint("RIGHT", frame, "LEFT", -gap, 0)
	else c.sq:SetPoint("LEFT", frame, "RIGHT", gap, 0) end
end

-- Room the icon square takes on one end of a line (0 when there is none there).
-- The flyout on that end starts past it: the active totem stays in view under
-- an open flyout, exactly as the totem button does on the icon bar.
function SP:CompactSquareExtent(btn, side)
	local c = btn and btn.compact
	if not (c and btn.compactLayoutOn and c.sqOn and c.sqSide == side) then return 0 end
	return (c.sqSize or 12) + 2   -- the square plus its 1 px border either side
end

function SP:RefreshCompactSquares()
	if not (self:CompactActive() and self.totemButtons) then return end
	for element = 1, 4 do
		local btn = self.totemButtons[element]
		if btn and btn.compact and btn.compactLayoutOn then self:AnchorCompactSquare(btn.compact, btn) end
	end
end

-- Outline for the remaining fraction: the far cap goes first, then both long
-- edges shrink together toward the start cap, which goes last.
local function SetOutline(c, frac, r, g, b)
	local startCap, farCap, edgeA, edgeB = c.ol[1], c.ol[2], c.ol[3], c.ol[4]
	if frac <= 0 then
		startCap:Hide(); farCap:Hide(); edgeA:Hide(); edgeB:Hide()
		return
	end
	local full = c.vertical and c.bh or c.bw
	local len = math.max(1, full * frac)
	if c.vertical then edgeA:SetHeight(len); edgeB:SetHeight(len) else edgeA:SetWidth(len); edgeB:SetWidth(len) end
	for i = 1, 4 do c.ol[i]:SetColorTexture(r, g, b, 1) end
	startCap:Show(); edgeA:Show(); edgeB:Show()
	farCap:SetShown(frac >= 0.995)
end

-- "1.4" strings without per-frame garbage
local tenths = {}
local function FormatTenths(t)
	local k = math.floor(t * 10 + 0.5)
	if k < 0 then k = 0 end
	local s = tenths[k]
	if not s then s = string.format("%.1f", k / 10); tenths[k] = s end
	return s
end

-- col = element color or nil for an empty slot. frac = remaining duration 0..1.
-- dim = true when the player is out of range of the totem. pulsePos 0..1 and
-- pulseRemain (seconds) are nil for totems that do not pulse.
function SP:PaintCompactVisuals(c, col, frac, dim, pulsePos, pulseRemain, icon, iconAlpha)
	local active = col ~= nil
	local r, g, b, a = EMPTY.r, EMPTY.g, EMPTY.b, 0.6
	if not active and c.idleCol then
		-- opt.compactIdleColor = "element": an idle line keeps its element's colour,
		-- dimmed and without an outline, so the bar reads earth/fire/water/air at rest
		r, g, b, a = c.idleCol.r * 0.45, c.idleCol.g * 0.45, c.idleCol.b * 0.45, 0.8
	end
	if active then
		local k = dim and 0.5 or 1
		r, g, b, a = col.r * k, col.g * k, col.b * k, 0.95
	end
	PaintBar(c.line, c.tex, c.vertical, r, g, b, a)
	if c.fill then
		local len = active and math.max(1, c.lineLen * frac) or c.lineLen
		if c.vertical then c.line:SetHeight(len) else c.line:SetWidth(len) end
	end
	c.line:Show()

	local oFrac = active and (c.fill and 1 or frac) or 0
	if not active and c.idleOl then
		-- opt.compactIdleOutline = "element": an idle line keeps a full outline in its
		-- element's colour (or the custom outline colour), dimmed so a live totem's
		-- brighter outline still stands apart
		local o = c.olColor or c.idleOl
		SetOutline(c, 1, (o.r or 1) * 0.7, (o.g or 1) * 0.7, (o.b or 1) * 0.7)
	elseif c.olColor then
		SetOutline(c, oFrac, c.olColor.r or 1, c.olColor.g or 1, c.olColor.b or 1)
	else
		SetOutline(c, oFrac, r * 0.55 + 0.45, g * 0.55 + 0.45, b * 0.55 + 0.45)
	end

	if active and pulsePos and c.pulseBar then
		local sz = math.max(1, c.lineLen * pulsePos)
		if c.vertical then c.pulse:SetHeight(sz) else c.pulse:SetWidth(sz) end
		c.pulse:Show()
	else
		c.pulse:Hide()
	end
	if active and pulseRemain and c.textOk then
		c.text:SetText(FormatTenths(pulseRemain)); c.text:Show()
	else
		c.text:Hide()
	end

	if c.sqOn and icon then
		c.sq:SetTexture(icon); c.sq:SetAlpha(iconAlpha or 1); c.sq:Show(); c.sqBd:Show()
	else
		c.sq:Hide(); c.sqBd:Hide()
	end
	c.bg:Show()
end

-- ---------------------------------------------------------------------------
-- Charge segments (Earth Shield line) - shared with the wizard mock
-- ---------------------------------------------------------------------------
-- Lays `n` segments along the inside of the line described by visuals `c`.
function SP:LayoutCompactSegments(frame, c, n, gap)
	gap = gap or 2
	frame.compactSeg = frame.compactSeg or {}
	local seg = frame.compactSeg
	local ow = c.ow
	local segLen = (c.lineLen - (n - 1) * gap) / n
	for i = 1, n do
		local t = seg[i]
		if not t then t = Tex(frame, "ARTWORK", 1); seg[i] = t end
		local off = ow + (i - 1) * (segLen + gap)
		t:ClearAllPoints()
		if c.vertical then
			t:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", ow, off)
			t:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -ow, off)
			t:SetHeight(segLen)
		else
			t:SetPoint("TOPLEFT", frame, "TOPLEFT", off, -ow)
			t:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", off, ow)
			t:SetWidth(segLen)
		end
	end
	for i = n + 1, #seg do seg[i]:Hide() end
	seg.n = n
	seg.tex, seg.vertical = c.tex, c.vertical
	return seg
end

-- The filled segments' colour for `charges` of `n`. useColors mirrors the Shield
-- Charges option: green / yellow / red as they run low (thresholds scale with the
-- segment count). base = the healthy color. Shared by the painting below and the
-- game-drawn shield layer (a fight on WoW: Forever), so both always agree.
local function SegmentColor(self, charges, n, useColors, base)
	local r, g, b = 0.25, 0.85, 0.3
	if base then r, g, b = base.r, base.g, base.b end
	-- General > Themes (st.compact-shield): the full colour (Earth Shield line: "es",
	-- your shield: its SHIELD_COLORS role) and low / last; nil = the colours here
	local themed = self:ThemeActive("st.compact-shield")
	if themed then
		local tr, tg, tb = self:ThemeColor("st.compact-shield", base and (base.spRole or "full") or "es")
		if tr then r, g, b = tr, tg, tb end
	end
	if useColors then
		if charges <= n / 3 then r, g, b = 1, 0.25, 0.25 elseif charges <= 2 * n / 3 then r, g, b = 1, 0.85, 0.2 end
		if themed and charges <= 2 * n / 3 then
			local tr, tg, tb = self:ThemeColor("st.compact-shield", (charges <= n / 3) and "last" or "low")
			if tr then r, g, b = tr, tg, tb end
		end
	end
	return r, g, b
end

-- charges = filled segments; active = false paints everything gray.
function SP:PaintCompactSegments(seg, charges, active, useColors, base)
	if not seg then return end
	local r, g, b = SegmentColor(self, charges, seg.n or #seg, useColors, base)
	for i = 1, seg.n or #seg do
		if active and i <= charges then
			PaintBar(seg[i], seg.tex, seg.vertical, r, g, b, 0.95)
		else
			PaintBar(seg[i], seg.tex, seg.vertical, EMPTY.r, EMPTY.g, EMPTY.b, active and 0.45 or 0.6)
		end
		seg[i]:Show()
	end
end

function SP:HideCompactSegments(seg)
	if not seg then return end
	for i = 1, #seg do seg[i]:Hide() end
end

-- ---------------------------------------------------------------------------
-- Real totem bar
-- ---------------------------------------------------------------------------
function SP:EnsureCompactVisuals(btn)
	if not btn.compact then btn.compact = self:CreateCompactVisuals(btn) end
	return btn.compact
end

-- Room taken at the far end of a line by the keybind label and the
-- range-counter number, so the party dots sit after them.
function SP:CompactCounterShift(btn)
	local shift = 0
	if btn.keybindText and btn.keybindText:IsShown() and (btn.keybindText:GetText() or "") ~= "" then
		shift = shift + math.ceil(btn.keybindText:GetStringWidth()) + 3
	end
	local rc = self.opt.rangeCounter
	if rc and rc.enabled and (rc.location or "icon") == "icon" and self.rangeCounterTexts and self.rangeCounterTexts[btn.element] then
		shift = shift + 18
	end
	return shift
end

-- The key on Compact's own two lines (Show Keybinds on Buttons): Your Shield Line's binding
-- (SHAMANPOWER_SHIELD_LINE) and the Earth Shield line's (SHAMANPOWER_EARTH_SHIELD: the Earth Shield
-- button in its Compact look). Which key: the bar buttons' rule (ButtonKeybindText, Keybind Shown).
-- Where and how: the totem lines' (the far end of the line, the same font and color), on a frame of
-- its own over the line, so the game-drawn charges (WoW: Forever, in a fight) never cover it. Made
-- out of a fight; after that only its text changes, which is fine in one. The icon-style Earth
-- Shield button keeps its look (no key), as before.
function SP:PaintCompactLineKey(btn, on, spellName, bindingName)
	if not btn then return end
	local fs = btn.spLineKey
	local text = on and self.opt and self.opt.showButtonKeybinds and self:ButtonKeybindText(spellName, bindingName) or nil
	if text and not fs and not InCombatLockdown() then
		local holder = CreateFrame("Frame", nil, btn)
		holder:SetAllPoints(btn)
		holder:SetFrameLevel(btn:GetFrameLevel() + 10)   -- (the game-drawn layer is 2 above the line, its bars a few more)
		fs = holder:CreateFontString(nil, "OVERLAY")
		self:SetSPFont(fs, "labels", 9, "OUTLINE", "Fonts\\ARIALN.TTF")
		fs:SetTextColor(0.9, 0.9, 0.9, 1)
		btn.spLineKey = fs
	end
	if not fs then return end
	if not text then
		fs:SetText("")
		fs:Hide()
		return
	end
	local c = btn.compact
	if c and not InCombatLockdown() then   -- (laid out only out of a fight, like the line)
		local ow = c.ow or 2
		fs:ClearAllPoints()
		if c.vertical then fs:SetPoint("BOTTOM", btn, "BOTTOM", 0, ow + 1)
		else fs:SetPoint("RIGHT", btn, "RIGHT", -(ow + 2), 0) end
	end
	fs:SetText(text)
	fs:Show()
end

function SP:UpdateCompactLineKeys()
	local sh = _G["ShamanPowerCompactShieldBtn"]
	if sh then
		self:PaintCompactLineKey(sh, sh.compact ~= nil and self:CompactShieldLineActive(),
			sh.spShieldName or self:CompactKnownShield(), "SHAMANPOWER_SHIELD_LINE")
	end
	local es = _G["ShamanPowerEarthShieldBtn"]
	if es then
		local spell = self.GetEarthShieldSpell and self:GetEarthShieldSpell() or nil
		self:PaintCompactLineKey(es, (es.compactLayoutOn and spell) and true or false, spell, "SHAMANPOWER_EARTH_SHIELD")
	end
end

-- every refresh of the bar buttons' keys (bindings, action bars, Keybind Shown, Keybind Mode's Done)
-- refreshes the lines' too
if SP.UpdateButtonKeybindText then
	hooksecurefunc(SP, "UpdateButtonKeybindText", function(self) self:UpdateCompactLineKeys() end)
end

-- Switch one totem button between icon and compact rendering. `forceOff` is
-- used for popped-out buttons, which always keep their icon.
function SP:ApplyCompactButtonLayout(btn, forceOff)
	if not btn then return end
	local on = self:CompactActive() and not forceOff
	local rc = self.rangeCounterTexts and self.rangeCounterTexts[btn.element]
	local gcd = self.gcdCooldowns and self.gcdCooldowns[btn.element]
	if not on then
		if btn.compactLayoutOn then
			self:HideCompactVisuals(btn.compact)
			if btn.icon then btn.icon:Show() end
			if self.ShowEmptySlotArt and btn.element then
				btn.compactLayoutOn = nil
				self:ShowEmptySlotArt(btn.element, self:AssignedIndex(btn.element) == 0)
			end
			if rc then rc:ClearAllPoints(); rc:SetPoint("CENTER", btn, "CENTER", 0, 0) end
			if btn.keybindText then btn.keybindText:ClearAllPoints(); btn.keybindText:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 1, 0) end
			if gcd then gcd:Show() end
			btn.compactLayoutOn = nil
			local dots = self.partyRangeDots and self.partyRangeDots[btn.element]
			if dots and self.PositionPartyDots then self:PositionPartyDots(dots, btn) end
		end
		return
	end

	local c = self:EnsureCompactVisuals(btn)
	btn.compactLayoutOn = true
	if btn.icon then btn.icon:Hide() end
	if btn.emptyArt then btn.emptyArt:Hide() end
	if btn.assignedIndicator then btn.assignedIndicator:Hide() end
	if btn.cooldownText then btn.cooldownText:Hide() end
	if btn.cooldown then btn.cooldown:Clear() end
	if btn.cdSweep then btn.cdSweep:Hide() end
	if gcd then gcd:Clear(); gcd:Hide() end      -- the GCD swipe is an icon thing

	local co = self:CompactOpts()
	local bw, bh = self:GetTotemSlotDims()
	self:LayoutCompactVisuals(c, btn, co, bw, bh)

	-- far end of the line: keybind label, then the range counter, then the dots
	local shift = 0
	if btn.keybindText then
		btn.keybindText:ClearAllPoints()
		if co.vertical then btn.keybindText:SetPoint("BOTTOM", btn, "BOTTOM", 0, co.ow + 1)
		else btn.keybindText:SetPoint("RIGHT", btn, "RIGHT", -(co.ow + 2), 0) end
		if btn.keybindText:IsShown() and (btn.keybindText:GetText() or "") ~= "" then
			shift = math.ceil(btn.keybindText:GetStringWidth()) + 3
		end
	end
	if rc then
		rc:ClearAllPoints()
		if co.vertical then rc:SetPoint("BOTTOM", btn, "BOTTOM", 0, co.ow + 2 + shift)
		else rc:SetPoint("RIGHT", btn, "RIGHT", -(co.ow + 3 + shift), 0) end
	end
	local dots = self.partyRangeDots and self.partyRangeDots[btn.element]
	if dots and self.PositionPartyDots then self:PositionPartyDots(dots, btn) end
	self:UpdateCompactTotems()
end

-- The Earth Shield button on the totem bar becomes a segmented line: one
-- segment per charge, the target's name over it (below it when vertical).
function SP:ApplyCompactESLayout()
	local esBtn = _G["ShamanPowerEarthShieldBtn"]
	if not esBtn then return end
	local icon    = _G["ShamanPowerEarthShieldBtnIcon"]
	local name    = _G["ShamanPowerEarthShieldBtnName"]
	local charges = _G["ShamanPowerEarthShieldBtnCharges"]
	local on = self:CompactActive() and not (self.IsEarthShieldPoppedOut and self:IsEarthShieldPoppedOut())
	if not on then
		-- (its game-drawn layer, WoW: Forever, off with the line: no aura work for it)
		local layer = esBtn.spShieldLayer
		if layer and esBtn.spLayerOn ~= false then
			pcall(layer.SetEnabled, layer, false)
			layer:SetAlpha(0)
			esBtn.spLayerOn = false
		end
		if esBtn.compactLayoutOn then
			self:HideCompactVisuals(esBtn.compact)
			self:HideCompactSegments(esBtn.compactSeg)
			esBtn:SetSize(26, 26)
			if icon then icon:Show() end
			if charges then charges:Show() end
			if name then
				name:ClearAllPoints(); name:SetPoint("TOP", esBtn, "BOTTOM", 0, -1)
				name:SetWidth(40); name:SetHeight(10); name:SetFontObject("GameFontHighlightSmall"); self:AdoptSPFont(name, "labels")
				name:Show()
			end
			esBtn.compactLayoutOn = nil
		end
		self:PaintCompactLineKey(esBtn, false)   -- (the icon button shows no key, as before)
		return
	end

	local c = self:EnsureCompactVisuals(esBtn)
	esBtn.compactLayoutOn = true
	local co = self:CompactOpts()
	local bw, bh = self:GetTotemSlotDims()
	esBtn:SetSize(bw, bh)
	if icon then icon:Hide() end
	if charges then charges:Hide() end
	self:LayoutCompactVisuals(c, esBtn, co, bw, bh)
	c.line:Hide()
	self:LayoutCompactSegments(esBtn, c, ES_MAX_CHARGES)
	self:EnsureCompactESLayer(esBtn)   -- (WoW: Forever: the charges in a fight)
	-- No target name on the compact line: at line size it only adds clutter
	if name then name:Hide() end
	-- its key at the far end, like the totem lines' (Show Keybinds on Buttons; none without Earth Shield)
	local esSpell = self.GetEarthShieldSpell and self:GetEarthShieldSpell() or nil
	self:PaintCompactLineKey(esBtn, esSpell ~= nil, esSpell, "SHAMANPOWER_EARTH_SHIELD")
	self:UpdateCompactES()
end

-- ---------------------------------------------------------------------------
-- Your own shield (Lightning / Water) as a 3-segment line at the START of the
-- bar - the Earth Shield line sits at the end. Optional (compactShieldLine).
-- ---------------------------------------------------------------------------
local SHIELD_MAX_CHARGES = 3
local SHIELD_COLORS = { [324] = { r = 1.0, g = 0.85, b = 0.25 }, [24398] = { r = 0.35, g = 0.65, b = 1.0 },
	[408510] = { r = 0.35, g = 0.65, b = 1.0 } }   -- Water Shield on WoW: Forever (talent, Season of Discovery spell ID)
-- which st.compact-shield role (General > Themes) each one's full colour is
SHIELD_COLORS[324].spRole, SHIELD_COLORS[24398].spRole, SHIELD_COLORS[408510].spRole = "full", "water", "water"

-- Validate shield names on spellbook changes for both clients, never in the
-- 10 Hz painter. ScanPlayerShield replaces shieldCache on
-- aura events, so keep these spellbook answers separately from its aura state.
local compactShieldNames = {}
local compactShieldGeneration = 0
do
	local function RefreshCompactShieldNames()
		for id in pairs(compactShieldNames) do compactShieldNames[id] = nil end
		for _, data in ipairs(SP.ShieldSpells) do
			if SPCompat.KnowsSpellID(data[1]) then compactShieldNames[data[1]] = SPCompat.SpellName(data[1]) end
		end
		compactShieldGeneration = compactShieldGeneration + 1
	end
	RefreshCompactShieldNames()
	SPCompat.OnSpellDataChanged(RefreshCompactShieldNames)
end

-- Spell name to cast: the shield that is up, else the preferred one, else any known.
function SP:CompactKnownShield()
	local cache = self.shieldCache
	if compactShieldNames then
		local shieldID = cache and cache.hasShield and cache.shieldID or nil
		local preferred = self.opt.preferredShield or 1
		if cache and cache.compactGeneration == compactShieldGeneration
			and cache.compactActiveID == shieldID and cache.compactPreferred == preferred then
			return cache.compactName, cache.compactID
		end
		local id = shieldID
		local name = id and compactShieldNames[id]
		if not name then
			local pref = self.ShieldSpells[preferred]
			id = pref and pref[1]
			name = id and compactShieldNames[id]
		end
		if not name then
			for _, data in ipairs(self.ShieldSpells) do
				if compactShieldNames[data[1]] then
					id, name = data[1], compactShieldNames[data[1]]
					break
				end
			end
		end
		if not name then id = nil end
		if cache then
			cache.compactGeneration, cache.compactActiveID = compactShieldGeneration, shieldID
			cache.compactPreferred, cache.compactName, cache.compactID = preferred, name, id
		end
		return name, id
	end
	if cache and cache.hasShield and cache.shieldID then
		for _, d in ipairs(self.ShieldSpells or {}) do
			if d[1] == cache.shieldID and SPCompat.KnowsSpellID(d[1]) then return SPCompat.SpellName(d[1]), d[1] end
		end
	end
	local pref = self.ShieldSpells and self.ShieldSpells[self.opt.preferredShield or 1]
	if pref and SPCompat.KnowsSpellID(pref[1]) then return SPCompat.SpellName(pref[1]), pref[1] end
	for _, d in ipairs(self.ShieldSpells or {}) do
		if SPCompat.KnowsSpellID(d[1]) then return SPCompat.SpellName(d[1]), d[1] end
	end
	return nil
end

-- ---------------------------------------------------------------------------
-- WoW: Forever, in a fight: the game hides shield charges from addons, so the
-- painting above (from the shield cache, or the Earth Shield button's count) can't
-- know them. A layer the GAME draws takes over then, on each line (your shield's,
-- and the Earth Shield line on its carrier): an aura container with one slot per
-- bar (the game binds one application bar per button), each bar over one segment
-- and shown by the game while the shield has at least that bar's count. Bars are
-- stacked by count, so the line shows what the painting shows out of a fight: one
-- segment per charge, coloured by how many are left. A slot's button shows only
-- while the shield is up. Each bar is anchored to its segment (it follows every
-- resize by itself) and drawn exactly like it (PaintBar: the same texture, turned
-- the same way on a vertical line). Made out of combat; in a fight only its alpha,
-- its own on / off and (Earth Shield) the unit it follows change. Its look is
-- painted again in place, out of combat; only a different set of bars (Color by
-- Count, a shield learned) builds a new one.
-- ---------------------------------------------------------------------------
local secret = issecretvalue or function() return false end

-- the game hides auras right now (WoW: Forever only: a fight, a boss, a restricted map)
local function ShieldRestricted()
	if not (SPCompat and SPCompat.secretsRegime) then return false end
	if SPCompat.AnyRestrictionActive and SPCompat.AnyRestrictionActive() then return true end
	return SPCompat.AurasUnreadable and SPCompat.AurasUnreadable() or false
end

-- The bars, one plan per set of bars: i = the segment it sits on, min = the count it lights at (the game shows
-- it while the shield has that many charges or more), band = its stacking (a higher band over a lower one),
-- t = its band's first count (its colour), set = the shield it belongs to (nil: every shield's). Without Color
-- by Count: one band, a bar per segment and shield. With it: three bands at SegmentColor's thresholds, each over
-- its own segments; the two lower ones are the same colour for every shield, so they are shared.
local function LayerPlan(n, useColors, nsets)
	local plan, bands = {}, nil
	if useColors then
		local lo, mid = math.floor(n / 3), math.floor(2 * n / 3)
		bands = { { 1, lo, true }, { lo + 1, mid, true }, { mid + 1, n, false } }
	else
		bands = { { 1, n, false } }
	end
	for band, def in ipairs(bands) do
		local t, top, shared = def[1], def[2], def[3]
		if top >= t then
			for i = 1, top do
				local min = math.max(i, t)
				if shared or nsets == 1 then
					plan[#plan + 1] = { i = i, min = min, band = band, t = t, set = not shared and 1 or nil }
				else
					for set = 1, nsets do plan[#plan + 1] = { i = i, min = min, band = band, t = t, set = set } end
				end
			end
		end
	end
	return plan
end

-- a bar's colour: its band's, for its shield (a shared bar's colour is the same for every shield)
local function PlanColor(self, e, sets, n, useColors)
	local set = sets[e.set or 1]
	return SegmentColor(self, e.t, n, useColors, set and set.base)
end

-- what the bars look like (out of combat only: it allocates)
local function LayerLook(self, c, plan, sets, n, useColors)
	local parts = { c.vertical and "v" or "h", c.tex or "flat" }
	for _, e in ipairs(plan) do
		local r, g, b = PlanColor(self, e, sets, n, useColors)
		parts[#parts + 1] = ("%.3f,%.3f,%.3f"):format(r, g, b)
	end
	return table.concat(parts, "|")
end

local function PaintLayer(self, owner, sets, n, useColors)
	local c = owner.compact
	for _, e in ipairs(owner.spLayerPlan) do
		if e.tex then
			local r, g, b = PlanColor(self, e, sets, n, useColors)
			PaintBar(e.tex, c.tex, c.vertical, r, g, b, 0.95)
		end
	end
end

local function BuildLayer(self, owner, segs, plan, sets, n, useColors, unit)
	if C_AddOns and C_AddOns.LoadAddOn then pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer") end
	local ok, layer = pcall(CreateFrame, "AuraContainer", nil, owner, "CustomAuraContainerTemplate")
	if not (ok and layer and layer.AddAuraSlot) then return nil end
	layer:SetAllPoints(owner)
	layer:SetFrameLevel(owner:GetFrameLevel() + 2)   -- (over the segments: textures of the line's button)
	local c = owner.compact
	local maps, all = {}, {}
	for k, set in ipairs(sets) do
		local m = {}
		for _, id in ipairs(set.ids) do m[id] = true; all[id] = true end
		maps[k] = m
	end
	local any = false
	for pi, e in ipairs(plan) do
		local seg = segs[e.i]
		local added = seg and pcall(layer.AddAuraSlot, layer, "sp" .. pi, "HELPFUL|PLAYER", {
			candidateFilters = { includeSpellIDs = e.set and maps[e.set] or all },
			initializeFrame = function(button)
				button:ClearAllPoints()
				button:SetAllPoints(owner)
				button:SetFrameLevel(layer:GetFrameLevel() + e.band)   -- (a higher count's colour over a lower one's)
				if button.SetMouseClickEnabled then pcall(button.SetMouseClickEnabled, button, false) end
				if button.SetMouseMotionEnabled then pcall(button.SetMouseMotionEnabled, button, false) end
				-- the bar is only the game's switch (it shows it while the shield has e.min charges or more); what
				-- shows is a piece drawn exactly like the segment under it
				local bar = CreateFrame("StatusBar", nil, button)
				bar:SetAllPoints(seg)
				bar:SetMinMaxValues(e.min, e.min + 1)
				bar:SetValue(e.min)
				local t = bar:CreateTexture(nil, "ARTWORK")
				t:SetAllPoints(bar)
				local r, g, b = PlanColor(self, e, sets, n, useColors)
				PaintBar(t, c.tex, c.vertical, r, g, b, 0.95)
				e.tex = t
				pcall(button.SetApplicationBar, button, bar, { minApplications = e.min, maxApplications = e.min + 1 })
			end,
		})
		if added then any = true end
	end
	if not any then
		layer:Hide()
		return nil
	end
	pcall(layer.SetUnit, layer, unit or "none")
	pcall(layer.SetEnabled, layer, false)   -- (on only while it draws: the line's tick)
	layer:SetAlpha(0)
	return layer
end

-- Out of combat: owner's layer for `sets` (its n segments, following `unit`). The same bars stay while only
-- their look changed (painted again in place; never while the game hides auras: then on the next refresh).
local function EnsureLayer(self, owner, n, sets, unit)
	if not (SPCompat and SPCompat.secretsRegime) or InCombatLockdown() then return end
	local c, segs = owner and owner.compact, owner and owner.compactSeg
	if not (c and c.lineLen and segs and segs[n]) then return end
	local useColors = self.opt.shieldChargeColors and true or false
	local names = {}
	for k, set in ipairs(sets) do names[k] = set.name end
	local structure = (#sets > 0) and (n .. "|" .. (useColors and "c" or "-") .. "|" .. table.concat(names, ",")) or nil
	local layer = owner.spShieldLayer
	if layer and owner.spLayerStructure == structure then
		local look = LayerLook(self, c, owner.spLayerPlan, sets, n, useColors)
		if owner.spLayerLook ~= look and not ShieldRestricted() then
			if pcall(PaintLayer, self, owner, sets, n, useColors) then owner.spLayerLook = look end
		end
		return
	end
	if layer then
		pcall(layer.SetEnabled, layer, false)
		pcall(layer.SetUnit, layer, "none")   -- (the old one stops following auras)
		layer:SetAlpha(0)
		layer:Hide()
		owner.spShieldLayer = nil
	end
	owner.spLayerStructure, owner.spLayerPlan, owner.spLayerLook, owner.spLayerOn = structure, nil, nil, nil
	if not structure or (owner.spLayerFails or 0) >= 3 then return end
	local plan = LayerPlan(n, useColors, #sets)
	layer = BuildLayer(self, owner, segs, plan, sets, n, useColors, unit)
	if layer then
		owner.spShieldLayer, owner.spLayerPlan, owner.spLayerUnit = layer, plan, unit or "none"
		owner.spLayerLook = LayerLook(self, c, plan, sets, n, useColors)
	else
		owner.spLayerFails = (owner.spLayerFails or 0) + 1   -- (tried again on the next layout or refresh, three times)
		owner.spLayerStructure = nil
	end
end

-- a line's layer on or off: its alpha and its own on / off, both allowed in a fight
local function SwitchLayer(owner, on)
	local layer = owner.spShieldLayer
	if not layer or owner.spLayerOn == on then return end
	owner.spLayerOn = on
	pcall(layer.SetEnabled, layer, on)
	if on then pcall(layer.UpdateAllAuras, layer) end
	layer:SetAlpha(on and 1 or 0)
end

-- the Earth Shield's carrier as a unit token, for its line's layer (SetUnit is the container's own call, allowed
-- in a fight). Looked up again only when the shield moved, or the token in hand stopped being the carrier (a
-- roster change), and at most twice a second (the lookup builds a list).
local function FollowCarrier(self, owner, layer)
	local guid = self.esTrackedTargetGUID
	local unit = owner.spLayerUnit or "none"
	local stale = guid ~= owner.spLayerGuid
	if not stale and guid then
		if unit == "none" then
			stale = true   -- (not in view when last looked)
		else
			local g = UnitGUID(unit)
			if not secret(g) and g ~= guid then stale = true end
		end
	end
	if not stale then return end
	local now = GetTime()
	if guid == owner.spLayerGuid and (owner.spLayerNext or 0) > now then return end
	owner.spLayerGuid, owner.spLayerNext = guid, now + 0.5
	local u = guid and self.EarthShieldUnitToken and self:EarthShieldUnitToken() or "none"
	if u ~= owner.spLayerUnit then
		owner.spLayerUnit = u
		pcall(layer.SetUnit, layer, u)
		pcall(layer.UpdateAllAuras, layer)
	end
end

-- the shields you know (SP.ShieldAuraSets: every rank), with their line colours
local function ShieldLineSets(self)
	local sets = {}
	for _, set in ipairs(self.ShieldAuraSets or {}) do
		for _, id in ipairs(set.ids) do
			if compactShieldNames[id] then
				sets[#sets + 1] = { name = set.name, ids = set.ids,
					base = (set.name == "Water Shield") and SHIELD_COLORS[24398] or SHIELD_COLORS[324] }
				break
			end
		end
	end
	return sets
end

-- Out of combat (layout, and the refreshes below): each line's layer.
function SP:EnsureCompactShieldLayer(btn)
	if btn then EnsureLayer(self, btn, SHIELD_MAX_CHARGES, ShieldLineSets(self), "player") end
end

function SP:EnsureCompactESLayer(esBtn)
	if not esBtn then return end
	local known = self.HasEarthShield and self:HasEarthShield()
	local sets = known and { { name = "Earth Shield", ids = self.EarthShieldAuraIDs or { 974, 32593, 32594, 383648 } } } or {}
	EnsureLayer(self, esBtn, ES_MAX_CHARGES, sets, esBtn.spLayerUnit or "none")
end

function SP:CompactShieldLineActive()
	return self:CompactActive() and self.opt.compactShieldLine and self:CompactKnownShield() ~= nil and true or false
end

-- Space the shield line takes at the start of the bar (0 when off).
function SP:CompactStartOffset()
	if not self:CompactShieldLineActive() then return 0 end
	local _, _, sw, sh = self:GetTotemSlotDims()
	return (self:IsTotemBarHorizontal() and sw or sh) + (self.opt.totemBarPadding or 2)
end

function SP:EnsureCompactShieldButton()
	local btn = _G["ShamanPowerCompactShieldBtn"]
	if btn then return btn end
	btn = CreateFrame("Button", "ShamanPowerCompactShieldBtn", UIParent, "SecureActionButtonTemplate")
	btn:SetFrameStrata("MEDIUM")
	btn:RegisterForClicks("AnyUp", "AnyDown")
	btn:SetAttribute("type1", "spell")
	btn:Hide()
	btn:HookScript("OnEnter", function(b)
		if not ShamanPower.opt.ShowTooltips then return end
		local cache = ShamanPower.shieldCache
		local name = b.spShieldName or "Shield"
		GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
		GameTooltip:AddLine(name, 0.4, 0.7, 1)
		if b.spLayerOn then
			-- (a fight on WoW: Forever: the line shows the charges; the game keeps the count from addons)
		elseif cache and cache.hasShield then
			GameTooltip:AddLine("Charges: " .. (cache.shieldCharges or 0), 1, 1, 1)
		else
			GameTooltip:AddLine("Not active", 1, 0.3, 0.3)
		end
		GameTooltip:AddLine("Click to recast", 0.7, 0.7, 0.7)
		GameTooltip:Show()
	end)
	btn:HookScript("OnLeave", function() GameTooltip:Hide() end)
	return btn
end

function SP:ApplyCompactShieldLayout()
	-- (switched off, a style change in the settings must not bring it up: a UIParent child)
	local active = self:CompactShieldLineActive() and self.autoButton and not self:IsOff()
	-- a bar the hide rules keep down right now (Hide Out of Combat, Hide When No Totems) still gets its line
	-- laid out, its game-drawn layer included: it comes up with the bar at a pull, too late to make anything
	local on = active and not self.totemBarHidden
	local btn = _G["ShamanPowerCompactShieldBtn"]
	if not active then
		if btn then
			btn:Hide()
			local layer = btn.spShieldLayer
			if layer then
				pcall(layer.SetEnabled, layer, false)   -- (no aura work for a line that is off)
				layer:SetAlpha(0)
				btn.spLayerOn = false
			end
			-- its key (SHAMANPOWER_SHIELD_LINE) does nothing while the line is off: a hidden button
			-- still answers a key, and a line never made this session has nothing to cast either
			if not InCombatLockdown() and btn:GetAttribute("type1") then btn:SetAttribute("type1", nil) end
			self:PaintCompactLineKey(btn, false)
		end
		return
	end
	btn = self:EnsureCompactShieldButton()
	local c = self:EnsureCompactVisuals(btn)
	local co = self:CompactOpts()
	local bw, bh, _, _, ox, oy = self:GetTotemSlotDims()
	btn:SetSize(bw, bh)
	btn:SetScale(self.opt.buffscale or 0.9)
	btn:ClearAllPoints()
	btn:SetPoint("TOPLEFT", self.autoButton, "TOPLEFT", 4 + ox, -4 + oy)
	self:LayoutCompactVisuals(c, btn, co, bw, bh)
	c.line:Hide()
	self:LayoutCompactSegments(btn, c, SHIELD_MAX_CHARGES)
	if not InCombatLockdown() then
		local name = self:CompactKnownShield()
		btn.spShieldName = name
		if btn:GetAttribute("type1") ~= "spell" then btn:SetAttribute("type1", "spell") end   -- (back after the line was off)
		btn:SetAttribute("spell1", name)
	end
	self:EnsureCompactShieldLayer(btn)   -- (WoW: Forever: the charges in a fight)
	btn:SetShown(on)
	-- its key at the far end, like the totem lines' (Show Keybinds on Buttons)
	self:PaintCompactLineKey(btn, true, btn.spShieldName, "SHAMANPOWER_SHIELD_LINE")
	self:UpdateCompactShield()
end

function SP:UpdateCompactShield()
	local btn = _G["ShamanPowerCompactShieldBtn"]
	if not btn or not btn:IsShown() or not btn.compactSeg then return end
	-- WoW: Forever, the game hiding auras (a fight): the game draws the charges (its layer), and goes on
	-- drawing them after the fight until the addon reads your shield again (the shield cache is a stand-in
	-- till then: no blink). Ours stay empty underneath, never a count we can't read.
	local cache = self.shieldCache
	local on = btn.spShieldLayer ~= nil and (ShieldRestricted() or (cache and cache.engineCount) or false)
	SwitchLayer(btn, on)
	if on then
		self:PaintCompactSegments(btn.compactSeg, 0, false, self.opt.shieldChargeColors, nil)
	else
		local active = cache and cache.hasShield and (cache.shieldCharges or 0) > 0
		local base = active and SHIELD_COLORS[cache.shieldID] or nil
		self:PaintCompactSegments(btn.compactSeg, active and cache.shieldCharges or 0, active and true or false, self.opt.shieldChargeColors, base)
	end
	if btn.compact then btn.compact.bg:Show() end
	-- keep the click on the shield that is actually up
	if not InCombatLockdown() then
		local name = self:CompactKnownShield()
		if name and name ~= btn.spShieldName then
			btn.spShieldName = name
			btn:SetAttribute("spell1", name)
			-- the key shown follows the shield it casts (its action bar key, Keybind Shown)
			self:PaintCompactLineKey(btn, true, name, "SHAMANPOWER_SHIELD_LINE")
		end
	end
	-- the rest of the bar's opacity, the fade rules' faded opacity included (this
	-- line has its own parent, so it does not inherit it)
	btn:SetAlpha(self.totemBarFaded and (self.opt.fadeOpacity or 0.25) or (self.opt.totemBarOpacity or 1))
end

-- Charges come from the ES button's own updater (esButton subsystem, 2 Hz),
-- which keeps the charge text and cached target current.
function SP:UpdateCompactES()
	local esBtn = _G["ShamanPowerEarthShieldBtn"]
	if not esBtn or not esBtn.compactLayoutOn or not esBtn:IsShown() then return end
	-- WoW: Forever, the game hiding auras (a fight): the game draws the charges on the carrier (its layer),
	-- and goes on after the fight until the Earth Shield button reads them again (its own game-drawn count is
	-- up till then: no blink). Ours stay empty underneath (the button's count is blank then).
	local layer = esBtn.spShieldLayer
	local core = esBtn.chargeContainer
	local on = layer ~= nil and (ShieldRestricted() or (core ~= nil and core:IsShown()) or false)
	SwitchLayer(esBtn, on)
	if on then
		FollowCarrier(self, esBtn, layer)
		self:PaintCompactSegments(esBtn.compactSeg, 0, false, self.opt.shieldChargeColors)
	else
		local chargeText = _G["ShamanPowerEarthShieldBtnCharges"]
		local charges = chargeText and tonumber(chargeText:GetText() or "") or 0
		local active = self.currentEarthShieldTarget ~= nil and charges > 0
		self:PaintCompactSegments(esBtn.compactSeg, charges, active, self.opt.shieldChargeColors)
	end
	if esBtn.compact then esBtn.compact.bg:Show() end
end

-- The game-drawn layers' look follows the theme, Color Shield Charges by Count, a profile and the shields you
-- know, also while the bar is down (no layout runs then): out of combat, a moment after the change (debounced,
-- after the fight when in one); a no-op when nothing they show changed. Also once the game lets auras be read
-- again (a repaint it refused meanwhile).
if SPCompat and SPCompat.secretsRegime then
	local function RefreshShieldLayers()
		if InCombatLockdown() then return end
		local sb = _G["ShamanPowerCompactShieldBtn"]
		if sb and sb.compact and SP:CompactShieldLineActive() then SP:EnsureCompactShieldLayer(sb) end
		local eb = _G["ShamanPowerEarthShieldBtn"]
		if eb and eb.compactLayoutOn and eb.compact then SP:EnsureCompactESLayer(eb) end
	end
	local function QueueShieldLayers()
		if SP.ThemeRepaintSoon then SP:ThemeRepaintSoon("compactShieldLayers", RefreshShieldLayers) else RefreshShieldLayers() end
	end
	if SP.OnThemeChanged then SP:OnThemeChanged(QueueShieldLayers) end
	for _, name in ipairs({ "RebuildShieldChargeContainer", "OnProfileChanged" }) do
		if SP[name] then hooksecurefunc(SP, name, QueueShieldLayers) end
	end
	if SPCompat.OnSpellDataChanged then SPCompat.OnSpellDataChanged(QueueShieldLayers) end
	if SPCompat.OnUnrestricted then SPCompat.OnUnrestricted(QueueShieldLayers) end
end

-- Per-tick paint of the lines (consolidated update system, 10 Hz).
function SP:UpdateCompactTotems()
	if not self:CompactActive() or not self.totemButtons then return end
	local now = GetTime()
	for element = 1, 4 do
		local btn = self.totemButtons[element]
		local c = btn and btn.compact
		if c and btn.compactLayoutOn and btn:IsShown() then
			local haveTotem, _, startTime, duration, icon = self:GetElementTotemInfo(element)
			c.idleCol = (self.opt.compactIdleColor == "element") and self.ElementColors[element] or nil
			c.idleOl = ((self.opt.compactIdleOutline or LOOK.compactIdleOutline) == "element") and self.ElementColors[element] or nil
			-- General > Themes (st.compact): the theme's line colour; nil = the Appearance palette above
			local col = self.ElementColors[element]
			local tr, tg, tb = self:ThemeColor("st.compact", element)
			if tr then
				col = THEMED_LINE[element]
				col.r, col.g, col.b = tr, tg, tb
				if c.idleCol then c.idleCol = col end
				if c.idleOl then c.idleOl = col end
			end
			if haveTotem and duration and duration > 0 then
				local frac = ((startTime + duration) - now) / duration
				if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
				local pulsePos, pulseRemain
				local pdata = self:GetActivePulsingTotem(element)
				if pdata and self:PulsePartsOff(pdata) then pdata = nil end   -- the refill is the line's pulse bar: its list only
				if pdata then
					pulsePos = ((now - startTime) % pdata.interval) / pdata.interval
					pulseRemain = pdata.interval * (1 - pulsePos)
				end
				local dim = btn.icon and btn.icon:IsDesaturated()
				self:PaintCompactVisuals(c, col, frac, dim, pulsePos, pulseRemain, icon, 1)
			else
				-- empty slot: gray line, the assigned totem ghosted in the square
				-- (a flyout pick made in this fight: the one the button casts)
				local idx = self:AssignedIndex(element)
				local aicon = (idx and idx > 0) and self:GetTotemIcon(element, idx) or nil
				self:PaintCompactVisuals(c, nil, 0, false, nil, nil, aicon, 0.35)
			end
		end
	end
	self:UpdateCompactES()
	self:UpdateCompactShield()
end

-- Compact style has no "dropped totem pops above the assigned one": the line
-- is whatever is down. Called by UpdateActiveTotemOverlays while Compact is on.
function SP:HideActiveTotemOverlaysForCompact()
	for element = 1, 4 do
		local ov = self.activeTotemOverlays and self.activeTotemOverlays[element]
		if ov then
			if ov.frame and ov.frame:IsShown() then ov.frame:Hide() end   -- (only when shown: this runs in fights too)
			ov.isActive = false
		end
		local btn = self.totemButtons and self.totemButtons[element]
		if btn and btn.assignedIndicator then btn.assignedIndicator:Hide() end
	end
end

-- Register the tick and (re)apply the layout to every bar button. Called at
-- the end of UpdateMiniTotemBar so it also runs after the range counters,
-- party dots and the Earth Shield button exist.
function SP:SetupCompactStyle()
	if not self.updateSystem then return end
	if not self.updateSystem.subsystems["compact"] then
		self:RegisterUpdateSubsystem("compact", 0.1, function() SP:UpdateCompactTotems() end)
	end
	local on = self:CompactActive()
	if on then self:EnableUpdateSubsystem("compact") else self:DisableUpdateSubsystem("compact") end
	if self.totemButtons then
		for element = 1, 4 do
			local btn = self.totemButtons[element]
			if btn then self:ApplyCompactButtonLayout(btn, self:IsElementPoppedOut(element)) end
		end
	end
	self:ApplyCompactESLayout()
	self:ApplyCompactShieldLayout()
end

-- Option change entry point (settings window + wizard).
function SP:ApplyCompactStyle()
	if InCombatLockdown() then
		print("|cff0070ddShamanPower:|r Cannot change the totem bar style during combat")
		return
	end
	if self.opt.compactStyle then
		self.opt.activeTotemAsMain = false
		self.opt.dynamicTotemMode = false
	end
	self:SetupCompactStyle()
	-- each style remembers its own screen position
	if self.RestoreTotemBarPosition then self:RestoreTotemBarPosition() end
	if self.UpdateLayout then self:UpdateLayout() end
	if self.UpdateMiniTotemBar then self:UpdateMiniTotemBar() end
	if self.UpdateActiveTotemOverlays then self:UpdateActiveTotemOverlays() end
	if self.UpdateTotemProgressBarPositions then self:UpdateTotemProgressBarPositions() end
	if self.UpdatePulseBarPositions then self:UpdatePulseBarPositions() end
	if self.RecreateTotemFlyouts then pcall(self.RecreateTotemFlyouts, self) end
	-- the icon bar and the Compact bar each keep their own flyout icon size
	if self.ApplyTotemFlyoutButtonSize then self:ApplyTotemFlyoutButtonSize() end
	if self.RefreshFlyoutLayout then self:RefreshFlyoutLayout() end   -- flyouts start past the icon square
	if self.UpdateTotemBarOpacity then self:UpdateTotemBarOpacity() end
	if self.UpdateCooldownBarScale then self:UpdateCooldownBarScale() end
end

-- General > Themes (st.compact): Compact Style > Outline Color is this spot's
-- setting. The ShamanPower themes set it to Element color, so the outline follows
-- the theme's line colours (a custom outline colour would hide them); Standard
-- puts the player's choice back, and the Compact Style page still changes it.
if SP.ThemeSpotSettings then
	SP:ThemeSpotSettings("st.compact", {
		{ key = "compactOutlineColorMode", label = "Outline Color",
		  get = function() return SP.opt and SP.opt.compactOutlineColorMode or "element" end,
		  set = function(v)
			SP.opt.compactOutlineColorMode = v
			-- (another style picks it up when Compact comes on)
			if SP.opt.compactStyle then SP:ApplyCompactStyle() end
		  end,
		  shamanpower = "element",
		},
	})
end
