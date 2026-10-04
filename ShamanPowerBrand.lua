-- ============================================================================
-- ShamanPowerBrand.lua: the brand primitives every ShamanPower window shares.
-- The totem graphic and the logo build are ports of the brand kit
-- (~/Storage/ShamanPower/brand/sp_logo.py, `sp-logo spec`): the same numbers,
-- order and easing, checked number for number against it. Everything is drawn
-- from our own textures (SetColorTexture and our Media files): no Blizzard
-- templates, fonts or art. Nothing here runs while idle.
--
-- TOKENS: SP.Brand (read-only: never write into it or its color tables)
--   .elements[key]   {r, g, b} 0-1: earth #AE7E4E, fire #F25735, water #668DF2,
--                    air #D0D5ED (the logo's duration bars), spirit #3FA9F5 (logo
--                    blue, for the "Other" group)
--   .plate           {r, g, b} #05070A, the black plate under every totem box
--   .logoBlue        {r, g, b} #3FA9F5
--   .off             {r, g, b} 0.32, 0.35, 0.40: an off switch (Config's `off`)
--   .groupElement    the settings window's NAV group label -> element key:
--                    General = air, Bars = earth, Group Tools = water,
--                    Alerts & Reminders = fire, Other = spirit. A label that is
--                    not listed ("More") gives nil: SP:BrandElementRGB(nil) = spirit.
--   .fonts           .regular / .medium / .semibold: the Fira Sans files. Set fonts
--                    through SP:BrandFontPath / SP:BrandFont (they handle CJK).
--   .radialLight     the path of Media\Textures\SP_RadialLight.tga
--   .BUILD_START, .BUILD_END   the logo build in intro time: 2.12 -> 3.78 s
--
-- FONTS
--   SP:BrandFontPath(weight) -> path   weight "regular" / "medium" / "semibold"
--       (case does not matter; anything else = regular). zhCN / zhTW / koKR
--       clients get STANDARD_TEXT_FONT (Fira Sans has no Chinese or Korean).
--   SP:BrandFont(fs, weight, size, flags)   fs:SetFont(SP:BrandFontPath(weight),
--       size, flags) on a FontString or Font object; size or flags nil = keep fs's
--       own (flags default ""). Returns what SetFont returns.
--
-- COLORS
--   SP:BrandElementRGB(key) -> r, g, b   0-1; an unknown or nil key = spirit
--
-- THE TOTEM GRAPHIC (static: the logo's element boxes, no SP)
--   SP:CreateTotemGraphic(parent, opts) -> Frame
--       The kit's static geometry (sp_logo.py STATIC_*) cropped to the boxes' own
--       bounds: 650 x 682 logo units (width : height). Plain textures, built once.
--       :SetGraphicHeight(px)   size by height; width = px * 650 / 682 (for a
--                               width W: :SetGraphicHeight(W * 682 / 650)).
--                               Starts at 170.5 px (800 units -> 200 px).
--       Place it with SetPoint; Show / Hide as usual. By default each face sits on
--       a full plate (the Esc page's rectangles): right at full opacity, but WoW
--       blends every texture on its own, so at a partial alpha the plate (and
--       the raised Earth's rim) shows through the face: at 12% the raised Earth
--       comes out ~16 / 255 brighter than the kit's image. To fade it (the
--       settings window's huge faint graphic) pass opts = { noOverlap = true }:
--       the plates are then drawn as rings around their faces, the same picture
--       at full opacity, and SetAlpha fades it exactly like a flat image.
--
-- THE LOGO BUILD (animated: the four boxes rise in, the bars grow in after them
-- and run down, the second Earth pops up, the Fire flyout opens)
--   SP:CreateTotemBuild(parent) -> Frame
--       Exactly sp_logo.frame(t, LOGO_ONLY): its pieces never overlap, so what WoW
--       blends is what the kit paints, at any frame alpha. The frame's box is the
--       logo's extent in the intro (614 x 646 units); boxes rising in may draw
--       outside it while they move (nothing is clipped, unless an ancestor clips
--       its children). Starts showing the finished logo (the BUILD_END state), so
--       it doubles as the static "finished logo".
--       :SetGraphicHeight(px)   size by height; width = px * 614 / 646
--       :SetBuildTime(t)        draw the exact state at intro time t (clamped to
--                               BUILD_START .. BUILD_END; nil = the end). Stops a
--                               playback without calling its onDone.
--       :PlayBuild(onDone, speed)  play BUILD_START -> BUILD_END in real time (1.66 s;
--                               speed 2 plays it twice as fast: Unlock UI's opening),
--                               then hold the end state (the bars stop there) and
--                               call onDone(frame) once. One OnUpdate while it
--                               plays, removed when it ends. Calling it again
--                               restarts (the earlier onDone is dropped). While the
--                               frame is hidden it pauses (hidden frames get no
--                               OnUpdate) and it goes on when shown.
--       :FinishBuild()          jump to the end state now (Escape, a click, combat);
--                               if it was playing, onDone is called once
--       :IsPlaying() -> bool
--   SP.BrandLogoStateAt(t, out) -> out   the pure state at intro time t (not
--       clamped): every rectangle the kit draws, in its draw order, as numbers in
--       the table `out` (created when nil; reuse it: no allocation after the first
--       call). Entry i of out.n: out.kind[i] ("plate" / "face" / "rim" / "bar" /
--       "fill"), out.who[i] ("fly0".."fly2", "box0".."box3", "bar0".."bar3",
--       "pop"), out.slot[i] (1-12, the same pieces in draw order), out.x0[i],
--       .y0, .x1, .y1 (corners in the kit's 1920 x 1080 canvas units), .r, .g, .b
--       (0-255), .alpha (0-1), .a8 (the 8-bit alpha the kit paints), .width
--       (a rim's outline width, else 0).
--
-- SMALL PIECES
--   SP:CreateElementBox(parent, size, key) -> Frame   a tiny totem box, the logo's
--       shape: the black plate as a thin edge (the face inset 1 unit). size
--       default 10, key default spirit.
--       :SetElement(key) or :SetElement(r, g, b)
--       :SetDim(bool)       dim face = 35% of the color over (40, 44, 52)
--       :SetBoxSize(size)   resize (the inset follows)
--       :SetShade(k)        multiply plate and face by k (0.5 = the disabled look)
--   SP:CreateTotemSwitch(parent, opts) -> Button   THE on / off switch (design C2):
--       a tiny totem box sliding on its own duration bar. 38 x 18 times opts.scale
--       (default 1); opts.element = its element key (default spirit);
--       opts.checked = the starting state.
--       :SetChecked(on) / :GetChecked()   on: the bar fills with the element, the
--                           box sits at the right; off: no fill, the box at the
--                           left with a dim gray face. Instant (no animation).
--       :SetElement(key) or :SetElement(r, g, b)
--       :SetEnabled(bool)   disabled: knob and fill at vertex 0.5, no clicks.
--                           A plain :Enable() / :Disable() repaints too.
--       It changes nothing by itself: the caller wires OnClick (and OnEnter /
--       OnLeave); use HookScript for OnEnable / OnDisable (it hooks them).
--   SP:CreateElementStripe(parent) -> Frame   Earth / Fire / Water / Air, left to
--       right, in four equal parts of its width; 3 px tall. Anchor its left and
--       right edges (e.g. along a window's top edge).
--       :SetStripeHeight(px)
--   SP:BrandRadialLight(parent, layer, sublevel) -> Texture   the white radial
--       light (SP_RadialLight.tga), BLEND; layer default "BACKGROUND", sublevel 0.
--       Size, place and tint it yourself (SetVertexColor with the element color
--       and a low alpha): the "lit by the element" look.
--
-- MOTION (the logo's own easing, for anything that moves with the logo)
--   SP.BrandEaseBack(x, s) -> 1 + (s + 1)(x - 1)^3 + s(x - 1)^2, s default 1.6
--                             (rising things; overshoots a hair, then settles)
--   SP.BrandEaseOut(x)     -> 1 - (1 - x)^3
--   SP:UIAnimationsOn()    -> false when General > Main > UI Animations is off: every
--                             piece of window motion then shows / hides at once
-- ============================================================================

local SP = ShamanPower
if not SP then return end

local floor, max, min = math.floor, math.max, math.min

local function Hex(h)
	return tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255
end
local function HexRGB(h)
	local r, g, b = Hex(h)
	return { r, g, b }
end

-- ---------------------------------------------------------------------------
-- Tokens
-- ---------------------------------------------------------------------------
local FONTS = "Interface\\AddOns\\ShamanPower\\Media\\Fonts\\"
SP.Brand = {
	elements = {
		earth = HexRGB("AE7E4E"), fire = HexRGB("F25735"), water = HexRGB("668DF2"), air = HexRGB("D0D5ED"),
		spirit = HexRGB("3FA9F5"),
	},
	plate = HexRGB("05070A"),
	logoBlue = HexRGB("3FA9F5"),
	off = { 0.32, 0.35, 0.40 },
	groupElement = {
		["General"] = "air", ["Bars"] = "earth", ["Group Tools"] = "water",
		["Alerts & Reminders"] = "fire", ["Other"] = "spirit",
	},
	fonts = {
		regular = FONTS .. "FiraSans-Regular.ttf",
		medium = FONTS .. "FiraSans-Medium.ttf",
		semibold = FONTS .. "FiraSans-SemiBold.ttf",
	},
	radialLight = "Interface\\AddOns\\ShamanPower\\Media\\Textures\\SP_RadialLight.tga",
}

-- ---------------------------------------------------------------------------
-- Fonts
-- ---------------------------------------------------------------------------
function SP:BrandFontPath(weight)
	local fonts = self.Brand.fonts
	local path = fonts.regular
	if type(weight) == "string" then path = fonts[weight:lower()] or path end
	return self:ResolveLocaleFontPath(path)
end

function SP:BrandFont(fs, weight, size, flags)
	if not fs then return end
	if not size or not flags then
		local _, curSize, curFlags = fs:GetFont()
		size = size or curSize or 12
		flags = flags or curFlags or ""
	end
	return fs:SetFont(self:BrandFontPath(weight), size, flags)
end

function SP:BrandElementRGB(key)
	local elements = self.Brand.elements
	local c = elements[key] or elements.spirit
	return c[1], c[2], c[3]
end

-- ---------------------------------------------------------------------------
-- The totem graphic: sp_logo.py static_logo(letters=False), in its 800 units
-- ---------------------------------------------------------------------------
-- STATIC_BOXES (x, y, face, the raised Earth's rim) and STATIC_BARS (color, fill)
local STATIC_BOXES = {
	{ 241, 59, "9E3923" }, { 241, 225, "BD442A" }, { 241, 391, "DB4F30" },
	{ 75, 391, "A57749", "CE955B" },
	{ 75, 557, "493521" }, { 241, 557, "D94E30" }, { 407, 557, "5B7ED9" }, { 573, 557, "BABFD4" },
}
local STATIC_BARS = { { "AE7E4E", 0.62 }, { "F25735", 0.55 }, { "668DF2", 0.80 }, { "D0D5ED", 0.86 } }
local STATIC_X, STATIC_Y, STATIC_W, STATIC_H = 75, 59, 650, 682   -- STATIC_BOXES_ONLY: 75..725 x 59..741

local function GraphicSetHeight(f, px)
	local k = px / STATIC_H
	f:SetSize(STATIC_W * k, STATIC_H * k)
	local rects = f.spRects
	for i = 1, #rects do
		local r = rects[i]
		local t = r[1]
		t:ClearAllPoints()
		t:SetPoint("TOPLEFT", f, "TOPLEFT", (r[2] - STATIC_X) * k, -(r[3] - STATIC_Y) * k)
		t:SetSize(r[4] * k, r[5] * k)
	end
end

function SP:CreateTotemGraphic(parent, opts)
	local f = CreateFrame("Frame", nil, parent)
	local rects = {}
	local plate = self.Brand.plate
	local noOverlap = opts and opts.noOverlap
	-- sub: the draw order inside the layer (0 the plate, 1 the raised Earth's rim, 2 the
	-- color). Two textures on the same layer and sublevel draw in no fixed order, so
	-- without it a plate can land on top of its face.
	local function Rect(ux, uy, uw, uh, sub, r, g, b)
		local t = f:CreateTexture(nil, "ARTWORK", nil, sub)
		t:SetColorTexture(r, g, b, 1)
		t.spMonoNote = { r, g, b, 1 }   -- (D42) a settings page in gray knows its color
		rects[#rects + 1] = { t, ux, uy, uw, uh }
	end
	-- noOverlap: a plate (or rim) is only the ring around what sits on it, as four sides
	local function Under(ux, uy, uw, uh, ix, iy, iw, ih, sub, r, g, b)
		if not noOverlap then
			Rect(ux, uy, uw, uh, sub, r, g, b)
			return
		end
		Rect(ux, uy, uw, iy - uy, sub, r, g, b)
		Rect(ux, iy + ih, uw, uy + uh - (iy + ih), sub, r, g, b)
		Rect(ux, iy, ix - ux, ih, sub, r, g, b)
		Rect(ix + iw, iy, ux + uw - (ix + iw), ih, sub, r, g, b)
	end
	-- a box: a 152 plate, the 140 face inset 6 (the raised Earth: a 148 rim inset 2 under it)
	for i = 1, #STATIC_BOXES do
		local box = STATIC_BOXES[i]
		local ux, uy = box[1], box[2]
		if box[4] then
			Under(ux, uy, 152, 152, ux + 2, uy + 2, 148, 148, 0, plate[1], plate[2], plate[3])
			Under(ux + 2, uy + 2, 148, 148, ux + 6, uy + 6, 140, 140, 1, Hex(box[4]))
		else
			Under(ux, uy, 152, 152, ux + 6, uy + 6, 140, 140, 0, plate[1], plate[2], plate[3])
		end
		Rect(ux + 6, uy + 6, 140, 140, 2, Hex(box[3]))
	end
	-- bars: a 152 x 18 plate, the fill inset 4 (144 x 10 at full, to the whole unit as the logo has it)
	for i = 1, #STATIC_BARS do
		local bx = 75 + (i - 1) * 166
		local fw = floor(144 * STATIC_BARS[i][2]) + 1
		Under(bx, 723, 152, 18, bx + 4, 727, fw, 10, 0, plate[1], plate[2], plate[3])
		Rect(bx + 4, 727, fw, 10, 2, Hex(STATIC_BARS[i][1]))
	end
	f.spRects = rects
	f.SetGraphicHeight = GraphicSetHeight
	f:SetGraphicHeight(STATIC_H * 0.25)
	return f
end

-- ---------------------------------------------------------------------------
-- The logo build: sp_logo.py logo_state(t, LOGO_ONLY), the kit's frame() without
-- the wordmark, cursor, pick and stamp. Same numbers, same order, same math.
-- ---------------------------------------------------------------------------
local KW, KH = 1920, 1080                      -- the kit's canvas (1x units)
local KS, KG = 140, 18                         -- box size, gap
local BAR_H, BAR_GAP = 16, 16
local ROW_Y = floor(KH / 2 - ((KS + KG) + KS + BAR_GAP + BAR_H) / 2 + (KS + KG))   -- 533
local X0 = floor((KW - (4 * KS + 3 * KG)) / 2)                                      -- 653
local function ColX(i) return X0 + i * (KS + KG) end        -- i = 0..3: Earth, Fire, Water, Air
local function LvlY(n) return ROW_Y - n * (KS + KG) end

local ROW_IN, ROW_STAGGER, ROW_DUR = 2.12, 0.07, 0.5
local ROW_RISE, ROW_SIZE0, ROW_ALPHA_K = 90, 0.85, 1.6
local BAR_IN, BAR_STAGGER, BAR_DUR = 2.35, 0.05, 0.4
local DRAIN_FROM = 2.75
local EARTH_POP, EARTH_POP_DUR, EARTH_POP_BACK = 2.95, 0.4, 1.3
local EARTH_DIM_DUR = 0.3
local FLY_OPEN, FLY_STAGGER, FLY_DUR, FLY_BACK = 3.38, 0.06, 0.28, 1.4
local FLY_SHADE = { 0.86, 0.74, 0.62 }          -- FLY reversed: nearest the bar first
local BAR_START = { 0.98, 0.9, 0.95, 0.99 }
local BAR_RATE = { 0.10, 0.16, 0.07, 0.05 }
local ELE = { { 0.72, 0.52, 0.32 }, { 1.00, 0.36, 0.22 }, { 0.42, 0.58, 1.00 }, { 0.86, 0.88, 0.98 } }
local BUILD_START = ROW_IN
local BUILD_END = FLY_OPEN + 2 * FLY_STAGGER + FLY_DUR   -- the flyout's last box is open
SP.Brand.BUILD_START, SP.Brand.BUILD_END = BUILD_START, BUILD_END

-- the frame's box: the logo's extent in the intro (flyout top .. bars), 614 x 646
local BOX_X, BOX_Y = X0, LvlY(3)
local BOX_W, BOX_H = 4 * KS + 3 * KG, ROW_Y + KS + BAR_GAP + BAR_H - LvlY(3)

local function Clamp(x)
	if x < 0 then return 0 end
	if x > 1 then return 1 end
	return x
end
local function Prog(t, t0, d) return Clamp((t - t0) / d) end
local function EaseOut(x) return 1 - (1 - x) ^ 3 end
local function EaseBack(x, s)
	x = x - 1
	return 1 + (s + 1) * x ^ 3 + s * x ^ 2
end
local function Lerp(a, b, x) return a + (b - a) * x end

-- Python's round(): halves go to the even neighbor
local function Round(x)
	local f = floor(x)
	local d = x - f
	if d > 0.5 or (d == 0.5 and f % 2 == 1) then return f + 1 end
	return f
end
-- sp_logo.rgb(c, k): 0-255
local function RGB(c, k)
	return max(0, min(255, Round(c[1] * k * 255))), max(0, min(255, Round(c[2] * k * 255))),
		max(0, min(255, Round(c[3] * k * 255)))
end

SP.BrandEaseBack = function(x, s) return EaseBack(x, s or 1.6) end
SP.BrandEaseOut = EaseOut

-- General > Main > UI Animations: the window motion (the settings window, Unlock UI,
-- Tuck Away, Keybind Mode) plays only while this is true; off = everything instant.
-- Off to start (the owner, 2026-10-04: lovely, but it must never overwhelm anyone).
function SP:UIAnimationsOn()
	local o = self.opt
	return (o and o.uiAnimations == true) or false
end

local WHO_FLY = { "fly0", "fly1", "fly2" }
local WHO_BOX = { "box0", "box1", "box2", "box3" }
local WHO_BAR = { "bar0", "bar1", "bar2", "bar3" }

local function Put(out, slot, kind, who, x0, y0, x1, y1, r, g, b, alpha, a8, width)
	local n = out.n + 1
	out.n = n
	out.slot[n], out.kind[n], out.who[n] = slot, kind, who
	out.x0[n], out.y0[n], out.x1[n], out.y1[n] = x0, y0, x1, y1
	out.r[n], out.g[n], out.b[n] = r, g, b
	out.alpha[n], out.a8[n], out.width[n] = alpha, a8, width
end

-- sp_logo.box_prims: the plate, the face inset max(2, 5%), the rim (the popped Earth)
local function BoxPrims(out, slot, who, x, y, size, c, shade, alpha, rimK)
	if alpha <= 0.01 or size <= 1 then return end
	local a8 = floor(255 * alpha)
	local pad = max(2, size * 0.05)
	Put(out, slot, "plate", who, x, y, x + size, y + size, 5, 7, 10, alpha, a8, 0)
	local r, g, b = RGB(c, shade)
	Put(out, slot, "face", who, x + pad, y + pad, x + size - pad, y + size - pad, r, g, b, alpha, a8, 0)
	if rimK then
		local bw = max(1, size * 0.025)
		r, g, b = RGB(c, rimK)
		Put(out, slot, "rim", who, x + pad - bw, y + pad - bw, x + size - pad + bw, y + size - pad + bw,
			r, g, b, alpha, a8, bw)
	end
end

-- sp_logo.bar_prims: the plate, the fill inset 3 (only when longer than half a unit)
local function BarPrims(out, slot, who, x, y, w, h, frac, c, alpha)
	if alpha <= 0.01 then return end
	local a8 = floor(255 * alpha)
	Put(out, slot, "bar", who, x, y, x + w, y + h, 5, 7, 10, alpha, a8, 0)
	local fw = (w - 6) * Clamp(frac)
	if fw > 0.5 then
		local r, g, b = RGB(c, 0.95)
		Put(out, slot, "fill", who, x + 3, y + 3, x + 3 + fw, y + h - 3, r, g, b, alpha, a8, 0)
	end
end

function SP.BrandLogoStateAt(t, out)
	out = out or {}
	if not out.x0 then
		out.slot, out.kind, out.who = {}, {}, {}
		out.x0, out.y0, out.x1, out.y1 = {}, {}, {}, {}
		out.r, out.g, out.b = {}, {}, {}
		out.alpha, out.a8, out.width = {}, {}, {}
	end
	out.n = 0
	-- the Fire flyout opens upward, nearest the bar first
	for j = 0, 2 do
		local op = Prog(t, FLY_OPEN + j * FLY_STAGGER, FLY_DUR)
		if op > 0 then
			local e = EaseBack(op, FLY_BACK)
			BoxPrims(out, j + 1, WHO_FLY[j + 1], ColX(1), Lerp(ROW_Y, LvlY(j + 1), e), KS, ELE[2], FLY_SHADE[j + 1],
				Clamp(e * 1.4))
		end
	end
	-- the four boxes rise in, each with its duration bar (grows in after it, then runs down)
	local earthDim = EaseOut(Prog(t, EARTH_POP, EARTH_DIM_DUR))
	for i = 0, 3 do
		local p = Prog(t, ROW_IN + i * ROW_STAGGER, ROW_DUR)
		if p > 0 then
			local e = EaseBack(p, 1.6)
			local off = (1 - e) * ROW_RISE
			local size = KS * Lerp(ROW_SIZE0, 1.0, Clamp(e))
			local x = ColX(i) + (KS - size) / 2
			local y = ROW_Y + off + (KS - size) / 2
			local shade = 0.85                  -- Fire keeps it (it changes only with the intro's pick)
			if i == 0 then shade = Lerp(0.85, 0.40, earthDim) end
			BoxPrims(out, 4 + 2 * i, WHO_BOX[i + 1], x, y, size, ELE[i + 1], shade, Clamp(p * ROW_ALPHA_K))
			local bp = EaseOut(Prog(t, BAR_IN + i * BAR_STAGGER, BAR_DUR))
			local drain = max(0, t - DRAIN_FROM) * BAR_RATE[i + 1]
			local frac = BAR_START[i + 1] * bp - drain * bp
			BarPrims(out, 5 + 2 * i, WHO_BAR[i + 1], ColX(i), ROW_Y + KS + BAR_GAP, KS, BAR_H, frac, ELE[i + 1], bp)
		end
	end
	-- the second Earth pops up one level over its dimmed slot, with its rim
	local pe = Prog(t, EARTH_POP, EARTH_POP_DUR)
	if pe > 0 then
		local e = EaseBack(pe, EARTH_POP_BACK)
		BoxPrims(out, 12, "pop", ColX(0), Lerp(ROW_Y, LvlY(1), e), KS, ELE[1], 0.92, Clamp(pe * 2), 1.15)
	end
	return out
end

-- Drawing the state. The kit paints each rectangle OVER what is under it (a box
-- that is still fading in hides what it covers), while WoW blends textures. So
-- every piece is cut so that no two overlap: a box's plate is the ring around its
-- face (and the rim's ring), a bar's plate the ring around its fill, and a box is
-- cut where a later box covers it. What WoW blends is then exactly what the kit
-- shows. Slots 1-12 are the pieces in the kit's draw order (flyout 1-3, then each
-- column's box and bar, the popped Earth last); ARTWORK sublevels -8..3 keep it.
local SLOTS = 12
local IS_BOX = { true, true, true, true, false, true, false, true, false, true, false, true }

local function Place(f, tex, x0, y0, x1, y1, cy0, cy1, r, g, b, a8)
	if y0 < cy0 then y0 = cy0 end
	if y1 > cy1 then y1 = cy1 end
	if x1 <= x0 or y1 <= y0 then
		tex:Hide()
		return
	end
	local k = f.spK
	tex:SetPoint("TOPLEFT", f, "TOPLEFT", (x0 - BOX_X) * k, (BOX_Y - y0) * k)
	tex:SetPoint("BOTTOMRIGHT", f, "TOPLEFT", (x1 - BOX_X) * k, (BOX_Y - y1) * k)
	tex:SetVertexColor(r / 255, g / 255, b / 255, a8 / 255)
	tex:Show()
end

local function HideFrom(group, first)
	for i = first, #group do group[i]:Hide() end
end

local function RenderBuild(f)
	local st, tex = f.spState, f.spTex
	local iPlate, iInner, iRim = f.spIPlate, f.spIInner, f.spIRim
	for s = 1, SLOTS do iPlate[s], iInner[s], iRim[s] = 0, 0, 0 end
	for i = 1, st.n do
		local s, kind = st.slot[i], st.kind[i]
		if kind == "plate" or kind == "bar" then
			iPlate[s] = i
		elseif kind == "rim" then
			iRim[s] = i
		else
			iInner[s] = i
		end
	end
	local X0s, Y0s, X1s, Y1s = st.x0, st.y0, st.x1, st.y1
	for s = 1, SLOTS do
		local group, p = tex[s], iPlate[s]
		if p == 0 then
			HideFrom(group, 1)
		else
			local ox0, oy0, ox1, oy1 = X0s[p], Y0s[p], X1s[p], Y1s[p]
			-- what is left of a box once the later boxes over it are drawn: they cover
			-- its whole width, so a top or bottom part goes (never a middle one)
			local cy0, cy1 = oy0, oy1
			if IS_BOX[s] then
				for s2 = s + 1, SLOTS do
					local q = iPlate[s2]
					if q > 0 and IS_BOX[s2] and X0s[q] <= ox0 and X1s[q] >= ox1 then
						local b0, b1 = Y0s[q], Y1s[q]
						if b0 < cy1 and b1 > cy0 then
							if b0 <= cy0 and b1 >= cy1 then
								cy1 = cy0
							elseif b0 <= cy0 then
								cy0 = b1
							elseif b1 >= cy1 then
								cy1 = b0
							end
						end
					end
				end
			end
			local a8 = st.a8[p]
			local fi, ri = iInner[s], iRim[s]
			-- the plate: the ring around what sits on it (the rim, else the face or fill)
			local ii = fi
			if ri > 0 then ii = ri end
			if ii > 0 then
				local ix0, iy0, ix1, iy1 = X0s[ii], Y0s[ii], X1s[ii], Y1s[ii]
				Place(f, group[1], ox0, oy0, ox1, iy0, cy0, cy1, 5, 7, 10, a8)
				Place(f, group[2], ox0, iy1, ox1, oy1, cy0, cy1, 5, 7, 10, a8)
				Place(f, group[3], ox0, iy0, ix0, iy1, cy0, cy1, 5, 7, 10, a8)
				Place(f, group[4], ix1, iy0, ox1, iy1, cy0, cy1, 5, 7, 10, a8)
			else   -- a bar with no fill yet: all plate
				Place(f, group[1], ox0, oy0, ox1, oy1, cy0, cy1, 5, 7, 10, a8)
				HideFrom(group, 2)
			end
			if fi > 0 then
				Place(f, group[5], X0s[fi], Y0s[fi], X1s[fi], Y1s[fi], cy0, cy1, st.r[fi], st.g[fi], st.b[fi], a8)
			else
				group[5]:Hide()
			end
			if group[6] then   -- the popped Earth's rim: the ring between its plate and its face
				if ri > 0 and fi > 0 then
					local rx0, ry0, rx1, ry1 = X0s[ri], Y0s[ri], X1s[ri], Y1s[ri]
					local fx0, fy0, fx1, fy1 = X0s[fi], Y0s[fi], X1s[fi], Y1s[fi]
					local r, g, b = st.r[ri], st.g[ri], st.b[ri]
					Place(f, group[6], rx0, ry0, rx1, fy0, cy0, cy1, r, g, b, a8)
					Place(f, group[7], rx0, fy1, rx1, ry1, cy0, cy1, r, g, b, a8)
					Place(f, group[8], rx0, fy0, fx0, fy1, cy0, cy1, r, g, b, a8)
					Place(f, group[9], fx1, fy0, rx1, fy1, cy0, cy1, r, g, b, a8)
				else
					HideFrom(group, 6)
				end
			end
		end
	end
end

local function DrawBuild(f, t)
	SP.BrandLogoStateAt(t, f.spState)
	RenderBuild(f)
end

local function StopPlaying(f)
	if f.spPlaying then
		f.spPlaying = false
		f:SetScript("OnUpdate", nil)
	end
end

local function BuildFinish(f)
	local wasPlaying = f.spPlaying
	StopPlaying(f)
	DrawBuild(f, BUILD_END)
	if wasPlaying then
		local onDone = f.spOnDone
		f.spOnDone = nil
		if onDone then onDone(f) end
	end
end

local function BuildOnUpdate(f, elapsed)
	local t = f.spPlayT + elapsed * (f.spSpeed or 1)
	if t >= BUILD_END then
		BuildFinish(f)
		return
	end
	f.spPlayT = t
	DrawBuild(f, t)
end

local function BuildPlay(f, onDone, speed)
	StopPlaying(f)
	f.spOnDone = onDone
	f.spSpeed = (type(speed) == "number" and speed > 0) and speed or 1
	f.spPlayT = BUILD_START
	f.spPlaying = true
	DrawBuild(f, BUILD_START)
	f:SetScript("OnUpdate", BuildOnUpdate)
end

local function BuildSetTime(f, t)
	StopPlaying(f)
	f.spOnDone = nil
	t = t or BUILD_END
	if t < BUILD_START then t = BUILD_START elseif t > BUILD_END then t = BUILD_END end
	DrawBuild(f, t)
end

local function BuildIsPlaying(f)
	return f.spPlaying == true
end

local function BuildSetGraphicHeight(f, px)
	local k = px / BOX_H
	f.spK = k
	f:SetSize(BOX_W * k, BOX_H * k)
	RenderBuild(f)
end

function SP:CreateTotemBuild(parent)
	local f = CreateFrame("Frame", nil, parent)
	local tex = {}
	for s = 1, SLOTS do
		local group = {}
		local count = 5                  -- the plate's four sides and the face / fill
		if s == SLOTS then count = 9 end  -- the popped Earth: plus its rim's four sides
		for i = 1, count do
			local t = f:CreateTexture(nil, "ARTWORK", nil, s - 9)
			t:SetColorTexture(1, 1, 1, 1)
			t:Hide()
			group[i] = t
		end
		tex[s] = group
	end
	f.spTex, f.spState = tex, {}
	f.spIPlate, f.spIInner, f.spIRim = {}, {}, {}
	f.spK = 0.25
	f.SetGraphicHeight = BuildSetGraphicHeight
	f.SetBuildTime = BuildSetTime
	f.PlayBuild = BuildPlay
	f.FinishBuild = BuildFinish
	f.IsPlaying = BuildIsPlaying
	SP.BrandLogoStateAt(self.Brand.BUILD_END, f.spState)
	f:SetGraphicHeight(BOX_H * 0.25)
	return f
end

-- ---------------------------------------------------------------------------
-- The element box: a tiny totem box, the logo's shape
-- ---------------------------------------------------------------------------
local DIM_T = 0.35                                  -- dim face: 35% of the color over (40, 44, 52)
local DIM_R, DIM_G, DIM_B = 40 / 255, 44 / 255, 52 / 255

local function BoxPaint(f)
	local r, g, b = f.spR, f.spG, f.spB
	if f.spDim then
		r = r * DIM_T + DIM_R * (1 - DIM_T)
		g = g * DIM_T + DIM_G * (1 - DIM_T)
		b = b * DIM_T + DIM_B * (1 - DIM_T)
	end
	local k = f.spShade
	f.spFace:SetVertexColor(r * k, g * k, b * k, 1)
	f.spPlate:SetVertexColor(k, k, k, 1)
end

local function BoxSetElement(f, key, g, b)
	if type(key) == "number" then
		f.spR, f.spG, f.spB = key, g, b
	else
		f.spR, f.spG, f.spB = SP:BrandElementRGB(key)
	end
	BoxPaint(f)
end

local function BoxSetDim(f, dim)
	if dim then f.spDim = true else f.spDim = false end
	BoxPaint(f)
end

local function BoxSetShade(f, k)
	f.spShade = k or 1
	BoxPaint(f)
end

local function BoxSetSize(f, size)
	f:SetSize(size, size)
	local pad = 1   -- a thin black edge, like the window's own 1 unit lines (16% read as a thick frame)
	f.spFace:ClearAllPoints()
	f.spFace:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -pad)
	f.spFace:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -pad, pad)
end

function SP:CreateElementBox(parent, size, key)
	local f = CreateFrame("Frame", nil, parent)
	local plate = self.Brand.plate
	f.spPlate = f:CreateTexture(nil, "ARTWORK", nil, 0)
	f.spPlate:SetColorTexture(plate[1], plate[2], plate[3], 1)
	f.spPlate:SetAllPoints(f)
	f.spFace = f:CreateTexture(nil, "ARTWORK", nil, 1)
	f.spFace:SetColorTexture(1, 1, 1, 1)
	f.spDim, f.spShade = false, 1
	f.SetElement, f.SetDim, f.SetShade, f.SetBoxSize = BoxSetElement, BoxSetDim, BoxSetShade, BoxSetSize
	f:SetBoxSize(size or 10)
	f:SetElement(key)
	return f
end

-- ---------------------------------------------------------------------------
-- The switch (design C2): a tiny totem box sliding on its own duration bar
-- (settings_glowup_mock.py toggle(kind="totem"))
-- ---------------------------------------------------------------------------
-- b.spEnabled mirrors Enable / Disable (IsEnabled may return a secret on Forever)
local function SwitchPaint(b)
	local k = 1
	if not b.spEnabled then k = 0.5 end
	local knob = b.spKnob
	knob:ClearAllPoints()
	if b.spChecked then
		b.spFill:SetVertexColor(b.spR * k, b.spG * k, b.spB * k, 1)
		b.spFill:Show()
		knob:SetPoint("TOPLEFT", b, "TOPLEFT", b.spW - b.spH, 0)
		knob.spR, knob.spG, knob.spB, knob.spDim = b.spR, b.spG, b.spB, false
	else
		b.spFill:Hide()
		knob:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
		local off = SP.Brand.off
		knob.spR, knob.spG, knob.spB, knob.spDim = off[1], off[2], off[3], true
	end
	knob.spShade = k
	BoxPaint(knob)
end

local function SwitchSetChecked(b, on)
	if on then b.spChecked = true else b.spChecked = false end
	SwitchPaint(b)
end

local function SwitchGetChecked(b)
	return b.spChecked
end

local function SwitchSetElement(b, key, g, bl)
	if type(key) == "number" then
		b.spR, b.spG, b.spB = key, g, bl
	else
		b.spR, b.spG, b.spB = SP:BrandElementRGB(key)
	end
	SwitchPaint(b)
end

local function SwitchSetEnabled(b, on)
	if on then
		b.spEnabled = true
		b:Enable()
	else
		b.spEnabled = false
		b:Disable()
	end
	SwitchPaint(b)
end

-- a plain :Enable() / :Disable() repaints too
local function SwitchOnEnable(b)
	b.spEnabled = true
	SwitchPaint(b)
end
local function SwitchOnDisable(b)
	b.spEnabled = false
	SwitchPaint(b)
end

function SP:CreateTotemSwitch(parent, opts)
	opts = opts or {}
	local sc = opts.scale or 1
	local w, h = 38 * sc, 18 * sc
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(w, h)
	b.spW, b.spH = w, h
	-- the track: a plate bar 36% down, 30% tall, the full width
	local plate = self.Brand.plate
	local track = b:CreateTexture(nil, "ARTWORK", nil, 0)
	track:SetColorTexture(plate[1], plate[2], plate[3], 1)
	track:SetPoint("TOPLEFT", b, "TOPLEFT", 0, -h * 0.36)
	track:SetSize(w, h * 0.3)
	-- on: the track fills with the element (inset 1.5 x 1.2)
	local fill = b:CreateTexture(nil, "ARTWORK", nil, 1)
	fill:SetColorTexture(1, 1, 1, 1)
	fill:SetPoint("TOPLEFT", b, "TOPLEFT", 1.5 * sc, -(h * 0.36 + 1.2 * sc))
	fill:SetSize(w - 3 * sc, h * 0.3 - 2.4 * sc)
	b.spTrack, b.spFill = track, fill
	-- the knob: an element box, h x h (a child frame, so it draws over the track)
	b.spKnob = self:CreateElementBox(b, h)
	b.spChecked, b.spEnabled = false, true
	b.spR, b.spG, b.spB = self:BrandElementRGB(opts.element)
	b.SetChecked, b.GetChecked = SwitchSetChecked, SwitchGetChecked
	b.SetElement, b.SetEnabled = SwitchSetElement, SwitchSetEnabled
	b:HookScript("OnEnable", SwitchOnEnable)
	b:HookScript("OnDisable", SwitchOnDisable)
	b:SetChecked(opts.checked)
	return b
end

-- ---------------------------------------------------------------------------
-- The element stripe: Earth / Fire / Water / Air in four equal parts
-- ---------------------------------------------------------------------------
local function StripeSetHeight(f, px)
	f:SetHeight(px)
end

function SP:CreateElementStripe(parent)
	local f = CreateFrame("Frame", nil, parent)
	f:SetHeight(3)
	-- two halves meeting at the center, each split at its own center: four exact
	-- quarters from anchors alone (no size script), and neighbors share an edge
	local left = CreateFrame("Frame", nil, f)
	left:SetPoint("TOPLEFT", f, "TOPLEFT")
	left:SetPoint("BOTTOMRIGHT", f, "BOTTOM")
	local right = CreateFrame("Frame", nil, f)
	right:SetPoint("TOPLEFT", f, "TOP")
	right:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT")
	local elements = self.Brand.elements
	local function Segment(key, half, first)
		local c = elements[key]
		local t = f:CreateTexture(nil, "ARTWORK")
		t:SetColorTexture(c[1], c[2], c[3], 1)
		if first then
			t:SetPoint("TOPLEFT", half, "TOPLEFT")
			t:SetPoint("BOTTOMRIGHT", half, "BOTTOM")
		else
			t:SetPoint("TOPLEFT", half, "TOP")
			t:SetPoint("BOTTOMRIGHT", half, "BOTTOMRIGHT")
		end
	end
	Segment("earth", left, true)
	Segment("fire", left, false)
	Segment("water", right, true)
	Segment("air", right, false)
	f.SetStripeHeight = StripeSetHeight
	return f
end

-- ---------------------------------------------------------------------------
-- The radial light ("lit by the element"): the caller sizes, places and tints it
-- ---------------------------------------------------------------------------
function SP:BrandRadialLight(parent, layer, sublevel)
	local t = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sublevel or 0)
	t:SetTexture(self.Brand.radialLight)
	t:SetBlendMode("BLEND")
	return t
end
