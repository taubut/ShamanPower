-- ============================================================================
-- Bar textures: one place that decides what the bar fills ShamanPower draws
-- look like (totem duration bars, cooldown bar progress, pulse sweeps, other
-- small bars). The companion of ShamanPowerFonts.lua.
--
-- A bar fill is set through SP:SetSPBarColor(tex, area, r, g, b, a) instead of
-- tex:SetColorTexture(r, g, b, a). With no texture chosen that is exactly the
-- old flat colour call; with one chosen, the LibSharedMedia statusbar texture is
-- tinted with the same colour. A StatusBar goes through
-- SP:SetSPStatusBarTexture(bar, area, defaultPath). Every call is remembered
-- (weak keys), so changing the texture restyles everything without a reload.
--
-- Compact's lines keep their own setting (Mode & Twisting > Compact > Line
-- Texture); "Apply This Look Everywhere" writes that one too.
-- ============================================================================

local SP = ShamanPower
if not SP then return end

local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

SP.TEXTURE_AREAS = {
	{ key = "duration", label = "Totem Duration Bars", desc = "The bars that run down under your totems, on pop-outs, Grid and Blizzard's bar." },
	{ key = "cooldown", label = "Cooldown Bar",        desc = "The progress bars on the cooldown bar and the weapon imbue bars." },
	{ key = "pulse",    label = "Pulse Sweeps",        desc = "The sweep that shows a totem's next pulse (Tremor, Poison Cleansing ...) and Totem Plates' pulse bar." },
	{ key = "other",    label = "Other Bars",          desc = "Ready Reminders' cooldown bar." },
	{ key = "shieldcharges", label = "Shield Charge Bars", desc = "Shield Charges' charge bar and the cooldown bar's Shield Charge Bar. Their own texture: they never follow Bar Texture." },
}

-- Settings (AceDB profile):
--   opt.barTexture             LibSharedMedia statusbar name, or nil = as designed
--   opt.barTextureAreas[key]   a name for one area
local function texturePath(name)
	if not name or not LSM then return nil end
	return LSM:Fetch("statusbar", name, true)
end

-- The texture path for an area, or nil = the call site's own design.
function SP:TextureFor(area)
	local o = self.opt
	if not o then return nil end
	local per = area and o.barTextureAreas and o.barTextureAreas[area]
	-- Shield Charges are their own thing: their bars never follow Bar Texture
	local own = (area == "shieldcharges")
	local name = per
	if not own then name = per or o.barTexture end
	-- a texture being hovered in the settings list, shown without saving it
	-- ("__default" previews the design for the main row, the main texture for an area)
	local pv = SP._texPreview
	if pv then
		if pv.area == area then
			if pv.name ~= "__default" then name = pv.name elseif own then name = nil else name = o.barTexture end
		elseif pv.area == "all" and not per and not own then
			if pv.name == "__default" then name = nil else name = pv.name end
		end
	end
	return texturePath(name)
end

-- Gradients (General > Themes > Shapes & Textures, and each part's page; Miska's
-- request). Bars: opt.barGradient; outlines: opt.outlineGradient. Each is nil
-- (flat, today's), "shade", "glass", "two" (Two-Tone) or "fade" (Fade Out), with
-- <prefix>Color1 (nil = the part's own color), <prefix>Color2 (Two-Tone's second,
-- WoW gold by default) and <prefix>Fade (Fade Out's end opacity, 15% by default).
-- SetGradient takes color objects: two are reused, so painting makes no tables.
SP.GRADIENTS = {
	{ key = "default", label = "Flat (default)" },
	{ key = "shade",   label = "Shade" },
	{ key = "glass",   label = "Glass" },
	{ key = "two",     label = "Two-Tone" },
	{ key = "fade",    label = "Fade Out" },
}
local GOLD = { r = 1, g = 0.82, b = 0 }
local gradA, gradB
local function gradColors()
	if not gradA and CreateColor then gradA, gradB = CreateColor(1, 1, 1, 1), CreateColor(1, 1, 1, 1) end
	return gradA, gradB
end
local function mixc(v, to, t) return v + (to - v) * t end
-- the start / end colors of a gradient on a part colored r, g, b, a:
-- "along" runs the length of a bar (or top to bottom of an outline), "across" its width
local function gradientEnds(kind, prefix, r, g, b, a)
	local o = SP.opt
	if kind == "shade" then
		return "along", r * 0.45, g * 0.45, b * 0.45, a, r, g, b, a
	elseif kind == "glass" then
		return "across", r * 0.4, g * 0.4, b * 0.4, a, mixc(r, 1, 0.55), mixc(g, 1, 0.55), mixc(b, 1, 0.55), a
	elseif kind == "two" then
		local c1, c2 = o[prefix .. "Color1"], o[prefix .. "Color2"] or GOLD
		local r1, g1, b1 = r, g, b
		if type(c1) == "table" then r1, g1, b1 = c1.r or r, c1.g or g, c1.b or b end
		return "along", r1, g1, b1, a, c2.r or 1, c2.g or 0.82, c2.b or 0, a
	elseif kind == "fade" then
		local f = o[prefix .. "Fade"]
		if f == nil then f = 0.15 end
		return "along", r, g, b, a, r, g, b, a * f
	end
	return nil
end
-- Gradient Direction (opt.barGradientDirection / opt.outlineGradientDirection):
-- where the gradient starts on screen. nil = the style's own way (bars: along the
-- bar; outlines: top to bottom). [2] = the start sits at SetGradient's max end
-- (the right, or the top), so the two colors swap.
local GRAD_DIRS = { ttb = { "VERTICAL", true }, btt = { "VERTICAL", false }, ltr = { "HORIZONTAL", false }, rtl = { "HORIZONTAL", true } }
function SP:GradientDirectionValues(field)
	local v = { default = (field == "outlineGradient") and "Top to Bottom (default)" or "Along the Bar (default)" }
	local order = { "default" }
	for _, d in ipairs({ { "ttb", "Top to Bottom" }, { "btt", "Bottom to Top" }, { "ltr", "Left to Right" }, { "rtl", "Right to Left" } }) do
		if not (field == "outlineGradient" and d[1] == "ttb") then v[d[1]] = d[2]; order[#order + 1] = d[1] end
	end
	return v, order
end
-- Each kind of bar (a TEXTURE_AREAS key) has its own direction:
-- opt.barGradientDirections[area]; nil = Along the Bar. The first build had one
-- direction for every bar (opt.barGradientDirection): it still counts until a
-- bar gets its own, then it is copied onto each.
function SP:BarGradientDirection(area)
	local o = self.opt
	local d = o and o.barGradientDirections
	return (d and d[area]) or (o and o.barGradientDirection) or "default"
end
function SP:SetBarGradientDirection(area, v)
	local o = self.opt
	if not o then return end
	if o.barGradientDirection then
		o.barGradientDirections = o.barGradientDirections or {}
		for _, a in ipairs(SP.TEXTURE_AREAS) do
			if o.barGradientDirections[a.key] == nil then o.barGradientDirections[a.key] = o.barGradientDirection end
		end
		o.barGradientDirection = nil
	end
	if v == "default" then v = nil end
	if v then
		o.barGradientDirections = o.barGradientDirections or {}
		o.barGradientDirections[area] = v
	elseif o.barGradientDirections then
		o.barGradientDirections[area] = nil
	end
	self:RefreshGradients()
end
-- The gradient style for a kind of bar. Shield Charges are their own thing:
-- their bars (Shield Charges' and the cooldown bar's Shield Charge Bar) take
-- Charge Bar Gradient (opt.chargeGradient*), never Bar Gradient.
local function barKind(area)
	if area == "shieldcharges" then return SP.opt and SP.opt.chargeGradient end
	return SP.opt and SP.opt.barGradient
end
-- a bar fill: t colored r, g, b, a, the bar running left-right (vertical: bottom-top)
local function paintBarGradient(t, r, g, b, a, vertical, kindOverride, area)
	local o = SP.opt
	local kind = kindOverride or barKind(area)
	local charge = (area == "shieldcharges")
	local way, r1, g1, b1, a1, r2, g2, b2, a2 = gradientEnds(kind, charge and "chargeGradient" or "barGradient", r, g, b, a or 1)
	local A, B = gradColors()
	if not way or not (A and t.SetGradient) then
		if t.spGrad then t.spGrad = nil; t:SetVertexColor(r, g, b, a or 1) end
		return false
	end
	local dir
	if o and charge then
		dir = GRAD_DIRS[o.chargeGradientDirection]
	elseif o then
		local dirs = o.barGradientDirections
		dir = GRAD_DIRS[(dirs and dirs[area or "other"]) or o.barGradientDirection]
	end
	local orient
	if dir then
		-- a picked direction: the start color on that side. Glass starts with its shine.
		if way == "across" then r1, g1, b1, a1, r2, g2, b2, a2 = r2, g2, b2, a2, r1, g1, b1, a1 end
		if dir[2] then r1, g1, b1, a1, r2, g2, b2, a2 = r2, g2, b2, a2, r1, g1, b1, a1 end
		orient = dir[1]
	elseif way == "along" then
		orient = vertical and "VERTICAL" or "HORIZONTAL"
	else
		orient = vertical and "HORIZONTAL" or "VERTICAL"
	end
	A:SetRGBA(r1, g1, b1, a1); B:SetRGBA(r2, g2, b2, a2)
	t:SetGradient(orient, A, B)
	t.spGrad = true
	return true
end
SP.PaintBarGradient = function(_, t, r, g, b, a, vertical, kindOverride, area) return paintBarGradient(t, r, g, b, a, vertical, kindOverride, area) end
-- the settings' preview cards: a gradient kind's two ends on a color (see gradientEnds)
function SP:GradientEnds(kind, prefix, r, g, b, a) return gradientEnds(kind, prefix, r, g, b, a or 1) end

-- an outline's four edges (top, bottom, left, right), colored r, g, b: top to bottom
-- ("along") or its lighter top ("glass"). Each edge a solid white texture tinted.
function SP:PaintOutlineEdges(top, bottom, left, right, r, g, b, a, kindOverride)
	local kind = kindOverride or (self.opt and self.opt.outlineGradient)
	a = a or 1
	local way, r1, g1, b1, a1, r2, g2, b2, a2 = gradientEnds(kind, "outlineGradient", r, g, b, a)
	local A, B = gradColors()
	if not way or not A then return false end
	-- top edge: the start color; bottom: the end; sides run between them (VERTICAL: min = bottom)
	if way == "across" then
		-- glass on an outline: its shine first (light at the top, dark at the bottom)
		r1, g1, b1, r2, g2, b2 = r2, g2, b2, r1, g1, b1
	end
	-- Gradient Direction: bottom to top / right to left start on the far side
	local dir = self.opt and self.opt.outlineGradientDirection
	if dir == "btt" or dir == "rtl" then r1, g1, b1, a1, r2, g2, b2, a2 = r2, g2, b2, a2, r1, g1, b1, a1 end
	if dir == "ltr" or dir == "rtl" then
		-- left edge: the start color; right: the end; top and bottom run between them (HORIZONTAL: min = left)
		if left then left:SetVertexColor(r1, g1, b1, a1); left.spGrad = true end
		if right then right:SetVertexColor(r2, g2, b2, a2); right.spGrad = true end
		A:SetRGBA(r1, g1, b1, a1); B:SetRGBA(r2, g2, b2, a2)
		if top and top.SetGradient then top:SetGradient("HORIZONTAL", A, B); top.spGrad = true end
		if bottom and bottom.SetGradient then bottom:SetGradient("HORIZONTAL", A, B); bottom.spGrad = true end
		return true
	end
	if top then top:SetVertexColor(r1, g1, b1, a1); top.spGrad = true end
	if bottom then bottom:SetVertexColor(r2, g2, b2, a2); bottom.spGrad = true end
	A:SetRGBA(r2, g2, b2, a2); B:SetRGBA(r1, g1, b1, a1)
	if left and left.SetGradient then left:SetGradient("VERTICAL", A, B); left.spGrad = true end
	if right and right.SetGradient then right:SetGradient("VERTICAL", A, B); right.spGrad = true end
	return true
end
function SP:GradientValues()
	local v, order = {}, {}
	for _, s in ipairs(SP.GRADIENTS) do v[s.key] = s.label; order[#order + 1] = s.key end
	return v, order
end
-- a change of either gradient (or its colors / fade): every bar and outline repaints
function SP:RefreshGradients()
	self:RefreshTextures()
	if self.ShieldChargeStyleChanged then self:ShieldChargeStyleChanged() end   -- orbs draw their own fill
	if self.RepaintFrameEdges then self:RepaintFrameEdges() end
	if self.ThemePaintTotemBorders then self:ThemePaintTotemBorders() end
end
function SP:SetGradientField(field, value)
	if not self.opt then return end
	if value == "default" then value = nil end
	self.opt[field] = value
	self:RefreshGradients()
end

local registry = setmetatable({}, { __mode = "k" })
-- Bumped whenever TextureFor's answers can change; the per-area answer is cached
-- for the generation, so per-tick callers do one table read.
local gen = 0
local areaPath, areaGen = {}, {}
local function pathFor(area)
	local key = area or "other"
	if areaGen[key] ~= gen then areaPath[key] = SP:TextureFor(area) or false; areaGen[key] = gen end
	return areaPath[key] or nil
end

local function paintFill(t, path, r, g, b, a, area)
	local vertical = t:GetHeight() > t:GetWidth()
	if path then
		if t.spBarTex ~= path then t:SetTexture(path); t.spBarTex = path end
		if not paintBarGradient(t, r, g, b, a, vertical, nil, area) then t:SetVertexColor(r, g, b, a or 1) end
	elseif barKind(area) then
		-- a gradient on a flat bar: white, shaded by the gradient's own colors
		if t.spBarTex ~= "grad" then t:SetColorTexture(1, 1, 1, 1); t.spBarTex = "grad" end
		paintBarGradient(t, r, g, b, a, vertical, nil, area)
	else
		if t.spBarTex or t.spGrad then t:SetVertexColor(1, 1, 1, 1); t.spBarTex = nil; t.spGrad = nil end
		t:SetColorTexture(r, g, b, a)
	end
end

-- Drop-in for tex:SetColorTexture(r, g, b, a) on a bar fill.
function SP:SetSPBarColor(t, area, r, g, b, a)
	if not t then return end
	local rec = registry[t]
	if rec and rec.gen == gen and rec.area == area and rec.r == r and rec.g == g and rec.b == b and rec.a == a then
		return   -- nothing changed since the last paint
	end
	if not rec then rec = { kind = "fill" }; registry[t] = rec end
	rec.area, rec.r, rec.g, rec.b, rec.a, rec.gen = area, r, g, b, a, gen
	paintFill(t, pathFor(area), r, g, b, a, area)
end

-- Drop-in for bar:SetStatusBarTexture(defaultPath) on a StatusBar.
function SP:SetSPStatusBarTexture(bar, area, defaultPath)
	if not bar then return end
	local rec = registry[bar]
	if bar.spOwnTexture then
		-- another look draws this bar's fill (Shield Orbs): remember the area, paint nothing
		if not rec then rec = { kind = "bar" }; registry[bar] = rec end
		rec.area, rec.path, rec.gen = area, defaultPath, nil
		return
	end
	if rec and rec.gen == gen and rec.area == area and rec.path == defaultPath and bar.spBarTex ~= nil then return end
	if not rec then
		rec = { kind = "bar" }; registry[bar] = rec
		-- Bar Gradient: the bar's color, however it is set, shades its fill
		hooksecurefunc(bar, "SetStatusBarColor", function(self, r, g, b, a)
			local own = registry[self]
			-- the caller's color, kept: a texture swap puts it back (reading a
			-- gradient-painted fill back gives white)
			if own then own.cr, own.cg, own.cb, own.ca = r, g, b, a end
			if self.spOwnTexture then return end   -- a look that draws its own fill (Shield Orbs)
			local fill = self.GetStatusBarTexture and self:GetStatusBarTexture()
			if fill then paintBarGradient(fill, r, g, b, a, self:GetOrientation() == "VERTICAL", nil, own and own.area) end
		end)
	end
	rec.area, rec.path, rec.gen = area, defaultPath, gen
	local want = pathFor(area) or defaultPath
	if bar.spBarTex == want then return end
	-- keep the tint the caller gave the fill texture across the swap
	local old = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
	local r, g, b, a
	if rec.cr then
		r, g, b, a = rec.cr, rec.cg, rec.cb, rec.ca or 1
	elseif old and old.GetVertexColor then
		r, g, b, a = old:GetVertexColor()
	end
	bar:SetStatusBarTexture(want)
	bar.spBarTex = want
	local new = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
	if new and r and new.SetVertexColor then
		new:SetVertexColor(r, g, b, a)
		if not bar.spOwnTexture then paintBarGradient(new, r, g, b, a, bar:GetOrientation() == "VERTICAL", nil, area) end
	end
end

-- A frame still in use hangs off UIParent (or WorldFrame: nameplates); settings
-- previews are rebuilt and their old frames detached, so a refresh skips those
-- (they re-paint the next time their own code sets them).
local function live(obj)
	local p = obj:GetParent()
	while p do
		if p == UIParent or p == WorldFrame then return true end
		p = p:GetParent()
	end
	return false
end

-- Re-apply every remembered bar: called when a texture setting changes.
function SP:RefreshTextures()
	if SP.RepaintGlows then SP:RepaintGlows() end   -- Glow Shape (a profile change can switch it)
	if SP.RepaintFrameEdges then SP:RepaintFrameEdges() end   -- Frame Edges, the same
	if SP.ApplyIconShapes then SP:ApplyIconShapes() end        -- and Icon Shape
	gen = gen + 1
	for obj, rec in pairs(registry) do
		if live(obj) then
			rec.gen = gen
			if rec.kind == "fill" then
				paintFill(obj, pathFor(rec.area), rec.r, rec.g, rec.b, rec.a, rec.area)
			else
				local path = rec.path
				rec.path = nil          -- force the swap check below
				rec.gen = nil
				obj.spBarTex = nil      -- (a gradient change repaints too)
				self:SetSPStatusBarTexture(obj, rec.area, path)
			end
		end
	end
end

-- Settings hover: show `name` for `area` ("all" = the main texture) until cleared.
function SP:PreviewTexture(area, name)
	if area and name then SP._texPreview = { area = area, name = name } else SP._texPreview = nil end
	self:RefreshTextures()
end

-- A saved texture another addon registers only after our bars were painted
-- fell back to the design: apply it the moment it arrives.
if LSM and LSM.RegisterCallback then
	local function saved(o, key)
		if o.barTexture == key then return true end
		if type(o.barTextureAreas) == "table" then
			for _, name in pairs(o.barTextureAreas) do
				if name == key then return true end
			end
		end
		return false
	end
	LSM.RegisterCallback(SP.TEXTURE_AREAS, "LibSharedMedia_Registered", function(_, mediatype, key)
		if mediatype == "statusbar" and SP.opt and saved(SP.opt, key) then SP:RefreshTextures() end
	end)
end

-- Dot Shape (General > Themes and Party Buff Tracker, one setting): the party
-- dots and Totem Coverage's dots. opt.dotShape nil = the round dot ShamanPower
-- always drew.
local SHAPES = "Interface\\AddOns\\ShamanPower\\Media\\Textures\\"
SP.DOT_SHAPES = {
	{ key = "default", label = "Round (default)", file = "Interface\\AddOns\\ShamanPower\\textures\\dot" },
	{ key = "orb",     label = "Soft Orb",        file = SHAPES .. "Circle_Smooth" },
	{ key = "ring",    label = "Ring",            file = SHAPES .. "Ring_40px" },
	{ key = "square",  label = "Square",          file = "Interface\\Buttons\\WHITE8x8" },
	{ key = "diamond", label = "Diamond",         file = SHAPES .. "Diamond" },
}
local dotFile = {}
for _, s in ipairs(SP.DOT_SHAPES) do dotFile[s.key] = s.file end
function SP:DotTexture()
	local k = self.opt and self.opt.dotShape
	return (k and dotFile[k]) or dotFile.default
end
function SP:DotShapeValues()
	local v, order = {}, {}
	for _, s in ipairs(SP.DOT_SHAPES) do v[s.key] = s.label; order[#order + 1] = s.key end
	return v, order
end
function SP:SetDotShape(key)
	if not self.opt then return end
	if key == "default" then key = nil end
	self.opt.dotShape = key
	if self.UpdatePartyDotPositions then self:UpdatePartyDotPositions() end
	if self.UpdateCoverageLayout then self:UpdateCoverageLayout() end
end

-- Glow Shape (General > Themes, Totem Bar > Duration Bars, Ready Reminders; one
-- setting): the pulse flash round the totem buttons and the ready / alert glows
-- round Ready Reminders, Reactive Totems, Tremor Reminder and the cooldown bar.
-- opt.glowShape nil = today's square glows. A glow keeps its size, color and
-- animation; only its texture changes.
SP.GLOW_SHAPES = {
	{ key = "default", label = "Square (default)", file = "Interface\\Buttons\\UI-ActionButton-Border" },
	{ key = "round",   label = "Round",            file = SHAPES .. "ring_glow3" },
}
local glowKind = setmetatable({}, { __mode = "k" })   -- [texture] = "border" (pulse flash) | "alert"
local function paintGlow(t, kind)
	if SP.opt and SP.opt.glowShape == "round" then
		t:SetTexture(SHAPES .. "ring_glow3"); t:SetTexCoord(0, 1, 0, 1)
	elseif kind == "alert" then
		t:SetTexture("Interface\\SpellActivationOverlay\\IconAlert"); t:SetTexCoord(0.00781250, 0.50781250, 0.27734375, 0.52734375)
	else
		t:SetTexture("Interface\\Buttons\\UI-ActionButton-Border"); t:SetTexCoord(0, 1, 0, 1)
	end
end
-- a glow texture joins the setting (call after creating it)
function SP:ShapeGlow(t, kind)
	if not t then return end
	glowKind[t] = kind or "border"
	paintGlow(t, glowKind[t])
end
function SP:GlowShapeValues()
	local v, order = {}, {}
	for _, s in ipairs(SP.GLOW_SHAPES) do v[s.key] = s.label; order[#order + 1] = s.key end
	return v, order
end
function SP:RepaintGlows()
	for t, kind in pairs(glowKind) do paintGlow(t, kind) end
end
function SP:SetGlowShape(key)
	if not self.opt then return end
	if key == "default" then key = nil end
	self.opt.glowShape = key
	self:RepaintGlows()
end

-- Frame Edges (General > Themes, Appearance > Totem Bar / Cooldown Bar; one
-- setting): an edge round the frames ShamanPower draws a backdrop for (the
-- totem bar, the cooldown bar, pop-outs, module panels). opt.frameEdge nil =
-- today's plain border only. The edge is its own frame just under the frame,
-- anchored to the backdrop's outer corners (so it follows a backdrop stretched
-- past flyout tabs); the backdrop, its colors and size never change. It follows
-- the frame's own SetBackdrop (none = no edge) and border color (a theme's).
SP.FRAME_EDGES = {
	{ key = "default", label = "Plain (default)" },
	{ key = "shadow",  label = "Drop Shadow" },
	{ key = "bevel",   label = "Bevel" },
	{ key = "thick",   label = "Thick" },
}
local edged = setmetatable({}, { __mode = "k" })
local paintFrameOutline   -- below: Outline Gradient on a backdrop's own border
local SHADOW_EDGE = { edgeFile = SHAPES .. "Border_DropShadow", edgeSize = 8 }
local THICK_EDGE = { edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 3 }
local function lift(v) v = v * 1.6 + 0.15; if v > 1 then return 1 end return v end
local function drawEdge(frame, kind)
	local e = frame.spEdge
	if not kind or not frame.backdropInfo then
		if e and e:IsShown() then e:Hide() end
		return
	end
	if not e then
		e = CreateFrame("Frame", nil, frame, "BackdropTemplate")
		e:EnableMouse(false)
		e.bevel = {}
		for i = 1, 4 do e.bevel[i] = e:CreateTexture(nil, "BORDER") end
		frame.spEdge = e
	end
	e:SetFrameLevel(math.max(0, frame:GetFrameLevel() - 1))   -- under the frame's own backdrop
	local tl, br = frame.TopLeftCorner or frame, frame.BottomRightCorner or frame
	local o, dx, dy = 2, 0, 0
	if kind == "shadow" then o, dx, dy = 5, 2, -2 elseif kind == "thick" then o = 3 end
	e:ClearAllPoints()
	e:SetPoint("TOPLEFT", tl, "TOPLEFT", -o + dx, o + dy)
	e:SetPoint("BOTTOMRIGHT", br, "BOTTOMRIGHT", o + dx, -o + dy)
	local r, g, b, a = frame:GetBackdropBorderColor()
	r, g, b, a = r or 0.3, g or 0.3, b or 0.3, a or 1
	local B = e.bevel
	if kind == "bevel" then
		e:SetBackdrop(nil)
		-- light from the top left: a lighter top and left edge, a dark bottom and right
		B[1]:ClearAllPoints(); B[1]:SetPoint("TOPLEFT", e, "TOPLEFT"); B[1]:SetPoint("TOPRIGHT", e, "TOPRIGHT"); B[1]:SetHeight(2)
		B[2]:ClearAllPoints(); B[2]:SetPoint("TOPLEFT", e, "TOPLEFT"); B[2]:SetPoint("BOTTOMLEFT", e, "BOTTOMLEFT"); B[2]:SetWidth(2)
		B[3]:ClearAllPoints(); B[3]:SetPoint("BOTTOMLEFT", e, "BOTTOMLEFT"); B[3]:SetPoint("BOTTOMRIGHT", e, "BOTTOMRIGHT"); B[3]:SetHeight(2)
		B[4]:ClearAllPoints(); B[4]:SetPoint("TOPRIGHT", e, "TOPRIGHT"); B[4]:SetPoint("BOTTOMRIGHT", e, "BOTTOMRIGHT"); B[4]:SetWidth(2)
		for i = 1, 2 do B[i]:SetColorTexture(lift(r), lift(g), lift(b), a); B[i]:Show() end
		for i = 3, 4 do B[i]:SetColorTexture(r * 0.3, g * 0.3, b * 0.3, a); B[i]:Show() end
	else
		for i = 1, 4 do B[i]:Hide() end
		if kind == "shadow" then
			e:SetBackdrop(SHADOW_EDGE)
			e:SetBackdropBorderColor(0, 0, 0, 0.85)
		else
			e:SetBackdrop(THICK_EDGE)
			e:SetBackdropBorderColor(r, g, b, a)
			paintFrameOutline(e)   -- Outline Gradient on the thick edge too
		end
	end
	e:Show()
end
-- Outline Gradient on a backdrop's own border (the frame's, or a Thick edge):
-- the top edge and corners the start color, the bottom the end, the sides shaded
paintFrameOutline = function(frame)
	if not frame.backdropInfo or not frame.TopEdge then return end
	local kind = SP.opt and SP.opt.outlineGradient
	local r, g, b, a = frame:GetBackdropBorderColor()
	r, g, b, a = r or 1, g or 1, b or 1, a or 1
	if kind then
		SP:PaintOutlineEdges(frame.TopEdge, frame.BottomEdge, frame.LeftEdge, frame.RightEdge, r, g, b, a)
		local tr, tg, tb, ta = frame.TopEdge:GetVertexColor()
		local br, bg, bb, ba = frame.BottomEdge:GetVertexColor()
		if frame.TopLeftCorner then frame.TopLeftCorner:SetVertexColor(tr, tg, tb, ta) end
		if frame.TopRightCorner then frame.TopRightCorner:SetVertexColor(tr, tg, tb, ta) end
		if frame.BottomLeftCorner then frame.BottomLeftCorner:SetVertexColor(br, bg, bb, ba) end
		if frame.BottomRightCorner then frame.BottomRightCorner:SetVertexColor(br, bg, bb, ba) end
		frame.spOutlineGrad = true
	elseif frame.spOutlineGrad then
		frame.spOutlineGrad = nil
		for _, k in ipairs({ "TopEdge", "BottomEdge", "LeftEdge", "RightEdge", "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner" }) do
			local t = frame[k]
			if t then t:SetVertexColor(r, g, b, a); t.spGrad = nil end
		end
	end
end
local function paintEdge(frame)
	drawEdge(frame, SP.opt and SP.opt.frameEdge)
	paintFrameOutline(frame)
end
-- the Themes tab's cards: one edge kind on a sample frame
function SP:PaintFrameEdgePreview(frame, kind)
	if kind == "default" then kind = nil end
	drawEdge(frame, kind)
end
local themeHooked = false
-- a frame joins the setting (call once its backdrop is set up)
function SP:EdgeFrame(frame)
	if not frame or not frame.SetBackdrop then return end
	if not edged[frame] then
		edged[frame] = true
		hooksecurefunc(frame, "SetBackdrop", paintEdge)
		hooksecurefunc(frame, "SetBackdropBorderColor", paintEdge)
		if not themeHooked and SP.OnThemeChanged then
			themeHooked = true
			SP:OnThemeChanged(function() SP:RepaintFrameEdges() end)
		end
	end
	paintEdge(frame)
end
function SP:RepaintFrameEdges()
	for f in pairs(edged) do paintEdge(f) end
end
function SP:FrameEdgeValues()
	local v, order = {}, {}
	for _, s in ipairs(SP.FRAME_EDGES) do v[s.key] = s.label; order[#order + 1] = s.key end
	return v, order
end
function SP:SetFrameEdge(key)
	if not self.opt then return end
	if key == "default" then key = nil end
	self.opt.frameEdge = key
	self:RepaintFrameEdges()
end

-- Icon Shape (General > Themes, Appearance > Totem Bar / Cooldown Bar; one
-- setting): the icons on the totem bar, its flyouts, the dropped-totem
-- overlays, pop-outs, Drop All and the cooldown bar. opt.iconShape nil = the
-- square icons. A shape is a mask over the icon and the things drawn on it
-- (highlight, sweeps, dark layer, the split imbue half), and the cooldown swipe
-- takes the same shape. With Square nothing is ever masked (today's code path).
SP.ICON_SHAPES = {
	{ key = "default", label = "Square (default)" },
	{ key = "rounded", label = "Rounded", file = SHAPES .. "Mask_Rounded" },
	{ key = "circle",  label = "Circle",  file = SHAPES .. "Mask_Circle" },
}
local MASK_FILE = { rounded = SHAPES .. "Mask_Rounded", circle = SHAPES .. "Mask_Circle" }
local shapedTex = setmetatable({}, { __mode = "k" })   -- [texture] = the icon whose rectangle the shape covers
local shapedCd = setmetatable({}, { __mode = "k" })
local function shapeTexture(t, icon)
	local file = MASK_FILE[SP.opt and SP.opt.iconShape]
	if t.spShapeMask then t:RemoveMaskTexture(t.spShapeMask); t.spShapeMask = nil end
	if not file then return end
	-- one mask per (frame, icon): a mask masks textures of its own frame
	local host = t:GetParent()
	host.spShapeMasks = host.spShapeMasks or {}
	local m = host.spShapeMasks[icon]
	if not m then
		m = host:CreateMaskTexture()
		m:SetAllPoints(icon)
		host.spShapeMasks[icon] = m
	end
	if m.spFile ~= file then m:SetTexture(file, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE"); m.spFile = file end
	t:AddMaskTexture(m)
	t.spShapeMask = m
end
local function shapeCooldown(cd)
	local k = SP.opt and SP.opt.iconShape
	if k and MASK_FILE[k] then
		cd:SetSwipeTexture(MASK_FILE[k])
		if cd.SetUseCircularEdge then cd:SetUseCircularEdge(k == "circle") end
		cd.spShaped = true
	elseif cd.spShaped then
		cd:SetSwipeTexture("Interface\\Buttons\\WHITE8X8")
		if cd.SetUseCircularEdge then cd:SetUseCircularEdge(false) end
		cd.spShaped = nil
	end
end
-- a texture drawn on an icon joins the setting (icon: the icon it sits on)
function SP:ShapeIconTexture(t, icon)
	if not (t and t.AddMaskTexture and icon) then return end
	if shapedTex[t] == nil and not (SP.opt and SP.opt.iconShape) then shapedTex[t] = icon return end   -- Square: nothing to do
	shapedTex[t] = icon
	shapeTexture(t, icon)
end
function SP:ShapeCooldown(cd)
	if not (cd and cd.SetSwipeTexture) then return end
	shapedCd[cd] = true
	shapeCooldown(cd)
end
local ICON_PARTS = { "icon2", "darkOverlay", "greyOverlay", "cdSweep", "bg" }
local function shapeButton(btn)
	if type(btn) ~= "table" then return end
	local icon = rawget(btn, "icon")
	if not (icon and icon.AddMaskTexture) then return end
	SP:ShapeIconTexture(icon, icon)
	local hl = btn.GetHighlightTexture and btn:GetHighlightTexture()
	if hl then SP:ShapeIconTexture(hl, icon) end
	for _, k in ipairs(ICON_PARTS) do
		local t = rawget(btn, k)
		if type(t) == "table" and t.AddMaskTexture then SP:ShapeIconTexture(t, icon) end
	end
	local bar = rawget(btn, "cdBar")
	local fill = bar and bar.GetStatusBarTexture and bar:GetStatusBarTexture()
	if fill then SP:ShapeIconTexture(fill, icon) end
	local cd = rawget(btn, "cooldown")
	if type(cd) == "table" then SP:ShapeCooldown(cd) end
end
-- every button ShamanPower has made so far (built again after a bar or flyout is rebuilt)
function SP:ApplyIconShapes()
	if not (self.opt and (self.opt.iconShape or self._iconShaped)) then return end   -- never shaped: today's code path
	self._iconShaped = true
	for e = 1, 4 do
		shapeButton(self.totemButtons and self.totemButtons[e])
		local fl = self.totemFlyouts and self.totemFlyouts[e]
		for _, b in ipairs(fl and (fl.allButtons or fl.buttons) or {}) do shapeButton(b) end
		shapeButton(self.activeTotemOverlays and self.activeTotemOverlays[e])
		local gcd = _G["ShamanPowerGCD" .. e]
		if gcd then SP:ShapeCooldown(gcd) end
	end
	for _, b in ipairs(self.cooldownButtons or {}) do shapeButton(b) end
	for _, f in pairs(self.poppedOutFrames or {}) do shapeButton(type(f) == "table" and rawget(f, "button")) end
	shapeButton(_G.ShamanPowerAutoDropAll)
	if _G.ShamanPowerGCD5 then SP:ShapeCooldown(_G.ShamanPowerGCD5) end
	for t, icon in pairs(shapedTex) do shapeTexture(t, icon) end
	for cd in pairs(shapedCd) do shapeCooldown(cd) end
end
function SP:IconShapeValues()
	local v, order = {}, {}
	for _, s in ipairs(SP.ICON_SHAPES) do v[s.key] = s.label; order[#order + 1] = s.key end
	return v, order
end
function SP:SetIconShape(key)
	if not self.opt then return end
	if key == "default" then key = nil end
	self.opt.iconShape = key
	self:ApplyIconShapes()
end
-- a rebuilt bar or flyout gets the shape again
for _, name in ipairs({ "CreateTotemButtons", "CreateTotemFlyout", "CreateCooldownBar", "CreateWeaponImbueButton",
	"CreateActiveTotemOverlay", "SetupGCDSwipes", "UpdateCooldownBar" }) do
	if type(SP[name]) == "function" then hooksecurefunc(SP, name, function() SP:ApplyIconShapes() end) end
end

-- Statusbar names for a picker (LibSharedMedia's list: Blizzard's, ShamanPower's
-- four shipped bars, and every texture other installed addons register).
function SP:TextureList()
	local out = {}
	if LSM then for _, name in ipairs(LSM:List("statusbar")) do out[#out + 1] = name end end
	return out
end

-- One look everywhere: the main font, outline and texture for every area (the
-- per-area choices are cleared), and Compact's lines take the texture too.
function SP:ApplyLookEverywhere()
	local o = self.opt
	if not o then return end
	o.fontAreas, o.barTextureAreas = nil, nil
	if o.barTexture then o.compactLineTexture = o.barTexture end
	if self.RefreshFonts then self:RefreshFonts() end
	self:RefreshTextures()
	if self.ApplyCompactStyle and not InCombatLockdown() then pcall(self.ApplyCompactStyle, self) end
end

-- Back to the designed look: fonts, outline, bar textures and Compact's lines.
function SP:ResetLook()
	local o = self.opt
	if not o then return end
	o.fontName, o.fontOutline, o.fontAreas = nil, nil, nil
	o.barTexture, o.barTextureAreas = nil, nil
	o.compactLineTexture = nil
	if self.RefreshFonts then self:RefreshFonts() end
	self:RefreshTextures()
	if self.ApplyCompactStyle and not InCombatLockdown() then pcall(self.ApplyCompactStyle, self) end
end
