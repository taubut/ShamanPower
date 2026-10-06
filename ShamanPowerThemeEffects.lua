-- ShamanPowerThemeEffects.lua
-- How the Effects (Settings > Bars > Totem Bar / Cooldown Bar > Effects) are PAINTED per
-- Effects Look, and the twelve new Effects styles. Themes are not effects: a
-- theme pick never changes anything here. The Effects themselves (what
-- triggers them, their on/off switches, their settings) live in
-- ShamanPowerCues.lua and are untouched; its painting functions ask SP.ThemeCue
-- first and carry on with today's drawing whenever it answers false.
--
-- Effects Look (the bars' Effects tabs, per bar: opt.totemCueLook / opt.cdbarCueLook,
-- read through the engine's spots tb.effects / cd.effects):
--   Standard   today's drawing, exactly (SP.ThemeCue answers false: the
--              Standard path in ShamanPowerCues.lua runs as always)
--   Elemental  an element-coloured ring and glow; the red X becomes a cracked
--              totem turned to stone
--   Signal     a thin frame on the button's edge, a bar inside its bottom
--              edge; the red X becomes a red slash and corner flag
--
-- New styles (fx.new-styles): two per effect, in that effect's Style list for
-- any player to pick, in any look. Every existing style and default stays.
--   Totem Destroyed      Crumble, Frame blink
--   Totem Expired        Ring draws in, Underline runs out
--   Totem Expiring Soon  Frame drains, Bar under it
--   Cooldown Ready       Shine, Dot
--   Weapon Imbue Gone    Element flare, Corner flag
--   Shield Gone          Shield burst, Frame blink + flag
--
-- Signature Moves (the bars' Effects tabs, per bar: opt.totemCueSignature /
-- opt.cdbarCueSignature; spots tb.signature / cd.signature): each effect's
-- EXISTING Style setting is registered with SP:ThemeSpotSettings, so turning
-- the switch on writes the look's own move into it (Elemental: the first style
-- of each pair above, Signal: the second) and off (or a Standard look) puts the
-- player's own styles back. The Style dropdowns keep changing them as ever.
--
-- Every part is built once per button, the first time a theme look or a new
-- style plays on it, and reused: a play is Stop, a few setters and Play,
-- nothing allocated. Nothing here runs by itself.
local SP = ShamanPower
if not SP then return end

local max, min = math.max, math.min

local WHITE = "Interface\\Buttons\\WHITE8x8"
local TEX = "Interface\\AddOns\\ShamanPower\\textures\\"
local RING, RADIAL, CRACK = TEX .. "cue_ring", TEX .. "cue_radial", TEX .. "cue_crack"
local SLASH, FLAG, SHEEN, DOT = TEX .. "cue_slash", TEX .. "cue_flag", TEX .. "cue_sheen", TEX .. "dot"
local LOGO_BLUE = (SP.THEME_BRAND and SP.THEME_BRAND.logoBlue) or { 63 / 255, 169 / 255, 245 / 255 }
local STONE = { 0.48, 0.47, 0.45 }

-- ShamanPowerCues.lua's own parts, handed over when it loads (SP.ThemeCue.init)
local cueFrame, TINT, iconMotion, alphaAnim

-- which Themes spot decides the look of each effect
local SPOT_OF = {
	destroyed = "tb.effects", expired = "tb.effects", expiring = "tb.effects",
	ready = "cd.effects", imbue = "cd.effects", shield = "cd.effects",
	running = "cd.effects", almost = "cd.effects",   -- Cooldown Bar > Effects: Running Out, Cooldown Almost Ready
}
-- the new one-shot styles and the new loops (Totem Expiring Soon)
local MOVES = { crumble = true, frameblink = true, ringin = true, underline = true, shine = true,
	dot = true, flare = true, flag = true, burst = true, blinkflag = true }
local LOOP_MOVES = { drain = true, underbar = true }

local function isSecret(v) return issecretvalue and issecretvalue(v) or false end

local function lookOf(kind)
	local lk = SP.ThemeEffectLook and SP:ThemeEffectLook(SPOT_OF[kind] or "tb.effects")
	if lk == "elemental" or lk == "signal" then return lk end
	return "standard"
end

-- ---------------------------------------------------------------------------
-- Parts (on top of ShamanPowerCues.lua's cue frame, built on first use)
-- ---------------------------------------------------------------------------
local function scaleAnim(group, order, from, to, duration, smoothing)
	local a = group:CreateAnimation("Scale")
	a:SetOrder(order)
	a:SetScaleFrom(from, from)
	a:SetScaleTo(to, to)
	a:SetDuration(duration)
	if smoothing then a:SetSmoothing(smoothing) end
	return a
end
-- in, held, out: 5 seconds at most, like the red X
local function holdGroup(region)
	local g = region:CreateAnimationGroup()
	alphaAnim(g, 1, 0, 1, 0.1); alphaAnim(g, 2, 1, 1, 4.5); alphaAnim(g, 3, 1, 0, 0.4)
	return g
end
local function pulses(group, n, peak)
	for k = 0, n - 1 do
		alphaAnim(group, k * 2 + 1, 0, peak, 0.12)
		alphaAnim(group, k * 2 + 2, peak, 0, 0.25)
	end
end
local function edgeSet(parent)
	local E = {}
	for i = 1, 4 do
		local e = parent:CreateTexture(nil, "OVERLAY")
		e:SetTexture(WHITE)
		E[i] = e
	end
	return E
end
local function tintEdges(E, r, g, b)
	for i = 1, 4 do E[i]:SetVertexColor(r, g, b, 1) end
end

local function parts(c)
	if c.spTheme then return c end
	c.spTheme = true
	local lvl = c:GetFrameLevel()
	-- Elemental: the element ring (burst, three pulses, a tightening or breathing loop, drawing in)
	local ring = c:CreateTexture(nil, "OVERLAY", nil, 2)
	ring:SetTexture(RING)
	ring:SetPoint("CENTER")
	ring:SetAlpha(0)
	c.ring = ring
	c.ringBurst = ring:CreateAnimationGroup()
	alphaAnim(c.ringBurst, 1, 0, 1, 0.05)
	alphaAnim(c.ringBurst, 2, 1, 0, 0.5); scaleAnim(c.ringBurst, 2, 1, 1.45, 0.5, "OUT")
	c.ringPulses = ring:CreateAnimationGroup()
	pulses(c.ringPulses, 3, 1)
	c.ringOnce = ring:CreateAnimationGroup()
	alphaAnim(c.ringOnce, 1, 0, 1, 0.1); alphaAnim(c.ringOnce, 2, 1, 0, 0.45)
	c.ringTighten = ring:CreateAnimationGroup()
	c.ringTighten:SetLooping("BOUNCE")
	alphaAnim(c.ringTighten, 1, 0.6, 1, 0.5); scaleAnim(c.ringTighten, 1, 1, 0.84, 0.5)
	c.ringBreathe = ring:CreateAnimationGroup()
	c.ringBreathe:SetLooping("BOUNCE")
	alphaAnim(c.ringBreathe, 1, 0.2, 1, 0.5)
	c.ringIn = ring:CreateAnimationGroup()
	alphaAnim(c.ringIn, 1, 0, 1, 0.05)
	alphaAnim(c.ringIn, 2, 1, 0, 0.75); scaleAnim(c.ringIn, 2, 1.15, 0.45, 0.75, "IN")

	-- Elemental: a soft element wash from the middle
	local radial = c:CreateTexture(nil, "OVERLAY", nil, 1)
	radial:SetTexture(RADIAL)
	radial:SetBlendMode("ADD")
	radial:SetAllPoints(c)
	radial:SetAlpha(0)
	c.radial = radial
	c.radialTwice = radial:CreateAnimationGroup()
	alphaAnim(c.radialTwice, 1, 0, 0.95, 0.08); alphaAnim(c.radialTwice, 2, 0.95, 0, 0.22)
	alphaAnim(c.radialTwice, 3, 0, 0.95, 0.08); alphaAnim(c.radialTwice, 4, 0.95, 0, 0.3)
	c.radialOnce = radial:CreateAnimationGroup()
	alphaAnim(c.radialOnce, 1, 0, 0.55, 0.08); alphaAnim(c.radialOnce, 2, 0.55, 0, 0.35)
	c.radialFlare = radial:CreateAnimationGroup()
	alphaAnim(c.radialFlare, 1, 0, 1, 0.1); alphaAnim(c.radialFlare, 2, 1, 0.35, 0.25); alphaAnim(c.radialFlare, 3, 0.35, 0, 0.5)

	-- Elemental mark / Crumble: the totem turns to stone, cracked in red
	local stone = CreateFrame("Frame", nil, c)
	stone:SetAllPoints(c)
	stone:SetFrameLevel(lvl + 1)
	stone:SetAlpha(0)
	local grey = stone:CreateTexture(nil, "ARTWORK")
	grey:SetAllPoints(stone)
	grey:SetColorTexture(STONE[1], STONE[2], STONE[3], 0.6)
	local crack = stone:CreateTexture(nil, "OVERLAY")
	crack:SetTexture(CRACK)
	crack:SetAllPoints(stone)
	crack:SetVertexColor(TINT.destroyed[1], TINT.destroyed[2], TINT.destroyed[3])
	c.stone = stone
	c.stoneHold = holdGroup(stone)

	-- Signal: a thin frame on the button's own edge
	local fout = CreateFrame("Frame", nil, c)
	fout:SetAllPoints(c)
	fout:SetFrameLevel(lvl + 2)
	fout:SetAlpha(0)
	local F = edgeSet(fout)
	F[1]:SetPoint("TOPLEFT"); F[1]:SetPoint("TOPRIGHT"); F[1]:SetHeight(2)
	F[2]:SetPoint("BOTTOMLEFT"); F[2]:SetPoint("BOTTOMRIGHT"); F[2]:SetHeight(2)
	F[3]:SetPoint("TOPLEFT"); F[3]:SetPoint("BOTTOMLEFT"); F[3]:SetWidth(2)
	F[4]:SetPoint("TOPRIGHT"); F[4]:SetPoint("BOTTOMRIGHT"); F[4]:SetWidth(2)
	fout.edges = F
	c.fout = fout
	c.foutOnce = fout:CreateAnimationGroup()
	alphaAnim(c.foutOnce, 1, 0, 1, 0.05); alphaAnim(c.foutOnce, 2, 1, 1, 0.2); alphaAnim(c.foutOnce, 3, 1, 0, 0.35)
	c.foutTwice = fout:CreateAnimationGroup()
	alphaAnim(c.foutTwice, 1, 0, 1, 0.05); alphaAnim(c.foutTwice, 2, 1, 1, 0.12); alphaAnim(c.foutTwice, 3, 1, 0, 0.1)
	alphaAnim(c.foutTwice, 4, 0, 1, 0.05); alphaAnim(c.foutTwice, 5, 1, 1, 0.12); alphaAnim(c.foutTwice, 6, 1, 0, 0.2)
	c.foutPulses = fout:CreateAnimationGroup()
	pulses(c.foutPulses, 3, 1)
	c.foutBreathe = fout:CreateAnimationGroup()
	c.foutBreathe:SetLooping("BOUNCE")
	alphaAnim(c.foutBreathe, 1, 0.2, 1, 0.5)

	-- Signal: a bar inside the button's bottom edge (inside: the duration bar sits under the button)
	local ubar = CreateFrame("Frame", nil, c)
	ubar:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", 2, 2)
	ubar:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -2, 2)
	ubar:SetHeight(3)
	ubar:SetFrameLevel(lvl + 2)
	ubar:SetAlpha(0)
	local back = ubar:CreateTexture(nil, "BACKGROUND")
	back:SetAllPoints(ubar)
	back:SetColorTexture(0, 0, 0, 0.7)
	local fill = ubar:CreateTexture(nil, "ARTWORK")
	fill:SetTexture(WHITE)
	fill:SetPoint("TOPLEFT")
	fill:SetPoint("BOTTOMLEFT")
	ubar.fill = fill
	c.ubar = ubar
	c.ubarRun = ubar:CreateAnimationGroup()   -- the underline runs out towards the left
	alphaAnim(c.ubarRun, 1, 0, 1, 0.05)
	local run = c.ubarRun:CreateAnimation("Scale")
	run:SetOrder(2); run:SetScaleFrom(1, 1); run:SetScaleTo(0.02, 1); run:SetOrigin("LEFT", 0, 0); run:SetDuration(0.9)
	alphaAnim(c.ubarRun, 2, 1, 1, 0.9)
	alphaAnim(c.ubarRun, 3, 1, 0, 0.1)
	c.ubarFade = ubar:CreateAnimationGroup()
	c.ubarFade:SetLooping("BOUNCE")
	alphaAnim(c.ubarFade, 1, 1, 0.15, 0.5)

	-- Signal mark: a red slash and a red corner flag
	local slashMark = CreateFrame("Frame", nil, c)
	slashMark:SetAllPoints(c)
	slashMark:SetFrameLevel(lvl + 3)
	slashMark:SetAlpha(0)
	local sl = slashMark:CreateTexture(nil, "OVERLAY")
	sl:SetTexture(SLASH)
	sl:SetAllPoints(slashMark)
	sl:SetVertexColor(TINT.destroyed[1], TINT.destroyed[2], TINT.destroyed[3])
	local sf = slashMark:CreateTexture(nil, "OVERLAY")
	sf:SetTexture(FLAG)
	sf:SetPoint("TOPRIGHT")
	sf:SetVertexColor(TINT.destroyed[1], TINT.destroyed[2], TINT.destroyed[3])
	slashMark.flag = sf
	c.slashMark = slashMark
	c.slashHold = holdGroup(slashMark)

	-- Frame drains: the frame, drained clockwise
	local drain = CreateFrame("Frame", nil, c)
	drain:SetAllPoints(c)
	drain:SetFrameLevel(lvl + 2)
	drain:Hide()
	local D = edgeSet(drain)
	D[1]:SetPoint("TOPLEFT")       -- top, runs right
	D[2]:SetPoint("TOPRIGHT")      -- right, runs down
	D[3]:SetPoint("BOTTOMRIGHT")   -- bottom, runs left
	D[4]:SetPoint("BOTTOMLEFT")    -- left, runs up
	drain.edges = D
	c.drain = drain

	-- a corner flag (Corner flag, Frame blink + flag, the end of Bar under it)
	local flag = c:CreateTexture(nil, "OVERLAY", nil, 6)
	flag:SetTexture(FLAG)
	flag:SetPoint("TOPRIGHT")
	flag:SetAlpha(0)
	c.flag = flag
	c.flagHold = holdGroup(flag)

	-- Shine: a band of light across the icon, kept inside it
	local clip = CreateFrame("Frame", nil, c)
	clip:SetAllPoints(c)
	clip:SetFrameLevel(lvl + 1)
	clip:SetClipsChildren(true)
	local sheen = clip:CreateTexture(nil, "OVERLAY")
	sheen:SetTexture(SHEEN)
	sheen:SetBlendMode("ADD")
	sheen:SetAlpha(0)
	c.sheen = sheen
	c.sheenSweep = sheen:CreateAnimationGroup()
	alphaAnim(c.sheenSweep, 1, 0, 0.9, 0.08)
	c.sheenMove = c.sheenSweep:CreateAnimation("Translation")
	c.sheenMove:SetOrder(1)
	c.sheenMove:SetDuration(0.55)
	c.sheenMove:SetSmoothing("IN_OUT")

	-- Dot: a logo-blue dot pops on the corner, stays a moment, goes
	local dotF = CreateFrame("Frame", nil, c)
	dotF:SetFrameLevel(lvl + 3)
	dotF:SetAlpha(0)
	local dr = dotF:CreateTexture(nil, "ARTWORK")
	dr:SetTexture(DOT)
	dr:SetPoint("CENTER")
	dr:SetVertexColor(0, 0, 0, 0.9)
	local dd = dotF:CreateTexture(nil, "OVERLAY")
	dd:SetTexture(DOT)
	dd:SetPoint("CENTER")
	dd:SetVertexColor(LOGO_BLUE[1], LOGO_BLUE[2], LOGO_BLUE[3])
	dotF.ring, dotF.dot = dr, dd
	c.dotF = dotF
	c.dotPop = dotF:CreateAnimationGroup()
	alphaAnim(c.dotPop, 1, 0, 1, 0.12); scaleAnim(c.dotPop, 1, 1.7, 1, 0.18, "OUT")
	alphaAnim(c.dotPop, 2, 1, 1, 1.6)
	alphaAnim(c.dotPop, 3, 1, 0, 0.35)

	-- a dark layer of its own: the icon greying a moment, and Signal's lighter pulse
	local shade = c:CreateTexture(nil, "ARTWORK", nil, 1)
	shade:SetAllPoints(c)
	shade:SetColorTexture(0, 0, 0)
	shade:SetAlpha(0)
	c.shade = shade
	c.dimOnce = shade:CreateAnimationGroup()
	alphaAnim(c.dimOnce, 1, 0, 0.45, 0.25); alphaAnim(c.dimOnce, 2, 0.45, 0.45, 0.6); alphaAnim(c.dimOnce, 3, 0.45, 0, 0.5)
	c.dimSoft = shade:CreateAnimationGroup()
	c.dimSoft:SetLooping("BOUNCE")
	alphaAnim(c.dimSoft, 1, 0, 0.3, 0.45)
	c.dimDeep = shade:CreateAnimationGroup()   -- Elemental's pulse: the Standard darkening, on this layer
	c.dimDeep:SetLooping("BOUNCE")
	alphaAnim(c.dimDeep, 1, 0, 0.55, 0.45)
	return c
end

local function sizeRing(c, h, scale)
	local s = h * scale
	c.ring:SetSize(s, s)
end

-- The drained frame: what is left of the edge, from the top-left, clockwise.
local function setDrain(c, frac, w, h)
	local D = c.drain.edges
	if frac > 1 then frac = 1 elseif frac < 0 then frac = 0 end
	local left = frac * 2 * (w + h)
	local top = min(w, left); left = left - top
	local right = min(h, left); left = left - right
	local bottom = min(w, left); left = left - bottom
	local side = min(h, left)
	D[1]:SetSize(max(top, 0.01), 3); D[1]:SetShown(top > 0)
	D[2]:SetSize(3, max(right, 0.01)); D[2]:SetShown(right > 0)
	D[3]:SetSize(max(bottom, 0.01), 3); D[3]:SetShown(bottom > 0)
	D[4]:SetSize(3, max(side, 0.01)); D[4]:SetShown(side > 0)
end

-- ---------------------------------------------------------------------------
-- Colours. Standard and Signal keep each effect's own colour (red destroyed,
-- white expired, orange expiring, gold ready, blue imbue and shield); Elemental
-- paints in the button's element colour (Element Colors). A totem button knows
-- its element; an imbue takes its imbue's element, a shield Water's; a
-- cooldown has none and keeps its own gold. The settings and tour previews'
-- mock buttons carry no element: their Effects spots are laid out Earth
-- destroyed, Fire expired, Water expiring.
-- ---------------------------------------------------------------------------
local IMBUE_ELEMENT = { 4, 2, 3, 1 }   -- WeaponImbueSpells: Windfury, Flametongue, Frostbrand, Rockbiter
local imbueElementOf = {}               -- [imbue name] = element or false, worked out once per name
local function imbueElement(btn)
	local name = btn and btn.currentImbueName
	if type(name) ~= "string" or isSecret(name) then return nil end
	local el = imbueElementOf[name]
	if el == nil then
		el = false
		local spells = SP.WeaponImbueSpells
		if spells then
			for i = 1, 4 do
				local base = spells[i] and GetSpellInfo and GetSpellInfo(spells[i])
				if type(base) == "string" and not isSecret(base) and name:find(base, 1, true) then el = IMBUE_ELEMENT[i] break end
			end
		end
		imbueElementOf[name] = el
	end
	return el or nil
end
local PREVIEW_ELEMENT = { destroyed = 1, expired = 2, expiring = 3 }
local function elementOf(host, kind)
	if kind == "shield" then return 3 end
	if kind == "imbue" then return imbueElement(host) end
	if kind == "ready" or kind == "almost" then return nil end
	-- Running Out: the item's own element (the shield Water's, an imbue its own, Earth Shield Earth's)
	if kind == "running" then
		local what = host.spRunKind
		if what == "imbue" then return imbueElement(host) end
		if what == "es" then return 1 end
		return 3
	end
	local e = host.element
	if type(e) == "number" and e >= 1 and e <= 4 then return e end
	return PREVIEW_ELEMENT[kind]
end
local function lookTint(host, kind)
	local element = elementOf(host, kind)
	if element and SP.ThemeElement then
		-- the element colour of this bar's effects spot (its own palette, or the player's own under Standard)
		local spot = (kind == "ready" or kind == "imbue" or kind == "shield" or kind == "running" or kind == "almost") and "cd.effects" or "tb.effects"
		return SP:ThemeElement(spot, element)
	end
	local t = TINT[kind] or TINT.expired
	return t[1], t[2], t[3]
end

-- Crumble's drop: the totem sinks a little and settles.
local function thud(icon, h)
	if SP.ThemeIconMotion then SP:ThemeIconMotion(icon, "thud", h) end   -- a flat-box skin over the icon moves with it
	local g = icon.spCueThud
	if not g then
		g = icon:CreateAnimationGroup()
		for k = 1, 2 do
			local a = g:CreateAnimation("Translation")
			a:SetOrder(k)
			g[k] = a
		end
		icon.spCueThud = g
	end
	local d = max(2, h * 0.08)
	g[1]:SetOffset(0, -d); g[1]:SetDuration(0.06)
	g[2]:SetOffset(0, d); g[2]:SetDuration(0.16)
	g:Stop(); g:Play()
end

-- ---------------------------------------------------------------------------
-- One-shots
-- ---------------------------------------------------------------------------
-- a new style: the same move in every look
local function playMove(c, host, move, kind, icon, h, t)
	local r, g, b = lookTint(host, kind)
	if move == "crumble" then
		icon = icon or host.icon
		if icon then thud(icon, h) end
		c.radial:SetVertexColor(TINT.destroyed[1], TINT.destroyed[2], TINT.destroyed[3])
		c.radialOnce:Stop(); c.radialOnce:Play()
		c.stoneHold:Stop(); c.stoneHold:Play()
	elseif move == "frameblink" then
		tintEdges(c.fout.edges, t[1], t[2], t[3])
		c.foutPulses:Stop(); c.foutPulses:Play()
	elseif move == "ringin" then
		c.ring:SetVertexColor(r, g, b)
		sizeRing(c, h, 1)
		c.ringIn:Stop(); c.ringIn:Play()
		c.dimOnce:Stop(); c.dimOnce:Play()
	elseif move == "underline" then
		local fill = c.ubar.fill
		fill:SetVertexColor(t[1], t[2], t[3])
		fill:SetWidth(max(1, host:GetWidth() - 4))
		c.ubarRun:Stop(); c.ubarRun:Play()
		c.dimOnce:Stop(); c.dimOnce:Play()
	elseif move == "shine" then
		local sheen = c.sheen
		sheen:SetSize(h, h)
		sheen:ClearAllPoints()
		sheen:SetPoint("CENTER", c, "CENTER", -h, 0)
		c.sheenMove:SetOffset(2 * h, 0)
		c.sheenSweep:Stop(); c.sheenSweep:Play()
		c.ring:SetVertexColor(r, g, b)
		sizeRing(c, h, 1)
		c.ringOnce:Stop(); c.ringOnce:Play()
	elseif move == "dot" then
		local s = max(6, h * 0.3)
		local dotF = c.dotF
		dotF:SetSize(s + 2, s + 2)
		dotF:ClearAllPoints()
		dotF:SetPoint("CENTER", c, "TOPRIGHT", -s * 0.35, -s * 0.35)
		dotF.ring:SetSize(s + 2, s + 2)
		dotF.dot:SetSize(s, s)
		c.dotPop:Stop(); c.dotPop:Play()
	elseif move == "flare" then
		c.radial:SetVertexColor(r, g, b)
		c.radialFlare:Stop(); c.radialFlare:Play()
		c.dimOnce:Stop(); c.dimOnce:Play()
	elseif move == "flag" then
		c.flag:SetVertexColor(r, g, b)
		c.flag:SetSize(h * 0.36, h * 0.36)
		c.flagHold:Stop(); c.flagHold:Play()
		c.dimOnce:Stop(); c.dimOnce:Play()
	elseif move == "burst" then
		c.ring:SetVertexColor(r, g, b)
		sizeRing(c, h, 0.95)
		c.ringBurst:Stop(); c.ringBurst:Play()
		c.radial:SetVertexColor(r, g, b)
		c.radialOnce:Stop(); c.radialOnce:Play()
		c.dimOnce:Stop(); c.dimOnce:Play()
	elseif move == "blinkflag" then
		tintEdges(c.fout.edges, t[1], t[2], t[3])
		c.foutOnce:Stop(); c.foutOnce:Play()
		c.flag:SetVertexColor(t[1], t[2], t[3])
		c.flag:SetSize(h * 0.36, h * 0.36)
		c.flagHold:Stop(); c.flagHold:Play()
		c.dimOnce:Stop(); c.dimOnce:Play()
	end
end

-- One cue (ShamanPowerCues.lua playCue). Returns false for today's styles on
-- the Standard look: the caller then draws it exactly as always.
-- lk: a look to play in (a preview), nil = the effect's spot's look.
local function play(host, style, kind, icon, lk)
	if not cueFrame or not host then return false end
	local move = MOVES[style]
	if not move then
		if lk ~= "elemental" and lk ~= "signal" then lk = (lk == nil) and lookOf(kind) or "standard" end
		if lk == "standard" then return false end
	end
	local c = parts(cueFrame(host))
	local t = TINT[kind] or TINT.expired
	local h = host:GetHeight()
	if move then
		playMove(c, host, style, kind, icon, h, t)
	elseif lk == "elemental" then
		local r, g, b = lookTint(host, kind)
		c.ring:SetVertexColor(r, g, b)
		if style == "glow" then
			sizeRing(c, h, 1)
			c.ringPulses:Stop(); c.ringPulses:Play()
		elseif style == "flash" then
			c.radial:SetVertexColor(r, g, b)
			c.radialTwice:Stop(); c.radialTwice:Play()
		else   -- shake / pop: the icon moves and the ring spreads from it
			icon = icon or host.icon
			if icon then iconMotion(icon, style, h) end
			sizeRing(c, h, 0.95)
			c.ringBurst:Stop(); c.ringBurst:Play()
		end
	else   -- signal
		tintEdges(c.fout.edges, t[1], t[2], t[3])
		if style == "glow" then
			c.foutPulses:Stop(); c.foutPulses:Play()
		elseif style == "flash" then
			c.foutTwice:Stop(); c.foutTwice:Play()
		else   -- shake / pop: the icon moves and the frame lights once
			icon = icon or host.icon
			if icon then iconMotion(icon, style, h) end
			c.foutOnce:Stop(); c.foutOnce:Play()
		end
	end
	return true
end

-- The mark until recast (Red X Until Recast). Standard: false, today's red X.
-- Elemental: the crack and stone. Signal: the red slash and corner flag.
-- Crumble brings its own stone: while it is up, that is the mark.
local function mark(host, lk)
	if not cueFrame or not host then return false end
	local c = host.spCue
	if c and c.spTheme and c.stoneHold:IsPlaying() then return true end
	if lk ~= "elemental" and lk ~= "signal" then lk = (lk == nil) and lookOf("destroyed") or "standard" end
	if lk == "standard" then return false end
	c = parts(cueFrame(host))
	if lk == "elemental" then
		c.stoneHold:Stop(); c.stoneHold:Play()
	else
		local f = host:GetHeight() * 0.36
		c.slashMark.flag:SetSize(f, f)
		tintEdges(c.fout.edges, TINT.destroyed[1], TINT.destroyed[2], TINT.destroyed[3])
		c.foutOnce:Stop(); c.foutOnce:Play()
		c.slashHold:Stop(); c.slashHold:Play()
	end
	return true
end

-- The element (or shield / imbue) is back: the theme's marks and flags go.
local function clear(c)
	if not (c and c.spTheme) then return end
	if c.stoneHold:IsPlaying() then c.stoneHold:Stop() end
	if c.slashHold:IsPlaying() then c.slashHold:Stop() end
	if c.flagHold:IsPlaying() then c.flagHold:Stop() end
end

-- ---------------------------------------------------------------------------
-- Loops (Totem Expiring Soon)
-- ---------------------------------------------------------------------------
local function stop(c)
	if not (c and c.spTheme) then return end
	c.dimLoop:Stop(); c.glowLoop:Stop()
	c.ringTighten:Stop(); c.ringBreathe:Stop(); c.foutBreathe:Stop(); c.ubarFade:Stop()
	c.dimSoft:Stop(); c.dimDeep:Stop()
	if c.drain:IsShown() then c.drain:Hide() end
	if c.loopBar then c.ubar:SetAlpha(0); c.flag:SetAlpha(0); c.loopBar = nil end
	c.loopMove, c.loopLook, c.loopT0 = nil, nil, nil
end

-- The part of the last seconds still left, for Frame drains / Bar under it:
-- the totem's own time on a real button; the cooldown bar's running-out part (its
-- pass sets spRunFrac); on a preview's mock button a 5-second countdown, round and round.
local function loopFrac(host, c)
	local f0 = host.spRunFrac
	if f0 then
		if f0 < 0 then f0 = 0 elseif f0 > 1 then f0 = 1 end
		return f0
	end
	local element = host.element
	local buttons = SP.totemButtons
	if element and buttons and buttons[element] == host then
		local have, _, start, duration = SP:GetElementTotemInfo(element)
		if have and type(start) == "number" and type(duration) == "number" and not isSecret(start) and not isSecret(duration) then
			local secs = (SP.opt and SP.opt.totemCueExpiringSecs) or 5
			local f = (start + duration - GetTime()) / secs
			if f < 0 then f = 0 elseif f > 1 then f = 1 end
			return f
		end
	end
	local now = GetTime()
	if not c.loopT0 then c.loopT0 = now end
	return 1 - ((now - c.loopT0) % 5) / 5
end

-- Called again and again while the loop runs (the expiring pass, the cooldown
-- bar's pass, the preview): a running loop changes nothing, except Frame drains and
-- Bar under it, which follow the time left. Returns false for today's loops on the
-- Standard look (after taking down a theme loop left from before): the caller runs
-- them. kind: whose loop (nil: Totem Expiring Soon; "running" / "almost": the
-- cooldown bar's Running Out / Cooldown Almost Ready), for its look and colors.
local function loop(host, style, t, lk, kind)
	if not cueFrame or not host then return false end
	kind = kind or "expiring"
	local move = LOOP_MOVES[style]
	if lk ~= "elemental" and lk ~= "signal" then lk = (lk == nil) and lookOf(kind) or "standard" end
	if not move and lk == "standard" then
		local c = host.spCue
		if c and c.loopMove then stop(c) end   -- back from a theme's loop: today's starts clean
		return false
	end
	t = t or TINT.expiring
	local c = parts(cueFrame(host))
	if c.loopMove ~= style or c.loopLook ~= lk then
		stop(c)
		c.loopMove, c.loopLook = style, lk
	end
	local h = host:GetHeight()
	if style == "drain" then
		if not c.drain:IsShown() then
			local r, g, b = lookTint(host, kind)
			tintEdges(c.drain.edges, r, g, b)
			c.drain:Show()
		end
		setDrain(c, loopFrac(host, c), host:GetWidth(), h)
	elseif style == "underbar" then
		local frac = loopFrac(host, c)
		local fill = c.ubar.fill
		fill:SetVertexColor(t[1], t[2], t[3])
		fill:SetWidth(max(0.01, (host:GetWidth() - 4) * frac))
		c.ubar:SetAlpha(1)
		local late = frac < 0.15
		if late then
			c.flag:SetVertexColor(t[1], t[2], t[3])
			c.flag:SetSize(h * 0.36, h * 0.36)
		end
		c.flag:SetAlpha(late and 1 or 0)
		c.loopBar = true
	elseif lk == "elemental" then
		if style == "glow" then
			if not c.ringBreathe:IsPlaying() then
				local r, g, b = lookTint(host, kind)
				c.ring:SetVertexColor(r, g, b)
				sizeRing(c, h, 1)
				c.ringBreathe:Play()
			end
		elseif not c.ringTighten:IsPlaying() then
			local r, g, b = lookTint(host, kind)
			c.ring:SetVertexColor(r, g, b)
			sizeRing(c, h, 1)
			c.ringTighten:Play()
			c.dimDeep:Play()
		end
	else   -- signal
		if style == "glow" then
			if not c.foutBreathe:IsPlaying() then
				tintEdges(c.fout.edges, t[1], t[2], t[3])
				c.foutBreathe:Play()
			end
		elseif not c.ubarFade:IsPlaying() then
			c.ubar.fill:SetVertexColor(t[1], t[2], t[3])
			c.ubar.fill:SetWidth(max(1, host:GetWidth() - 4))
			c.ubarFade:Play()
			c.dimSoft:Play()
		end
	end
	return true
end

-- ShamanPowerCues.lua hands its parts over as it loads (it loads after this file).
local function init(frameFn, tint, motionFn, alphaFn)
	cueFrame, TINT, iconMotion, alphaAnim = frameFn, tint, motionFn, alphaFn
end

SP.ThemeCue = { init = init, play = play, mark = mark, clear = clear, loop = loop, stop = stop, lookOf = lookOf }

-- ---------------------------------------------------------------------------
-- Signature Effects (setting-backed): each effect's own Style setting. The
-- engine writes the look's move into it when the switch is on (Elemental =
-- the "shamanpower" column, Signal = "minimal") and puts the player's own
-- style back when it goes off or the look goes back to Standard. The setter is
-- the Effects page's own (write, then ApplyCueSettings).
-- ---------------------------------------------------------------------------
if SP.ThemeSpotSettings then
	local function styleSetting(key, label, elemental, signal)
		return {
			key = key, label = label,
			get = function() return SP.opt and SP.opt[key] end,
			set = function(v)
				if not SP.opt then return end
				SP.opt[key] = v
				if SP.ApplyCueSettings and IsLoggedIn and IsLoggedIn() then SP:ApplyCueSettings() end
			end,
			shamanpower = elemental, minimal = signal,
		}
	end
	SP:ThemeSpotSettings("tb.signature", {
		styleSetting("totemCueDestroyedStyle", "Destroyed Style", "crumble", "frameblink"),
		styleSetting("totemCueExpiredStyle", "Expired Style", "ringin", "underline"),
		styleSetting("totemCueExpiringStyle", "Expiring Style", "drain", "underbar"),
	})
	SP:ThemeSpotSettings("cd.signature", {
		styleSetting("cdbarCueReadyStyle", "Ready Style", "shine", "dot"),
		styleSetting("cdbarCueImbueStyle", "Imbue Style", "flare", "flag"),
		styleSetting("cdbarCueShieldStyle", "Shield Style", "burst", "blinkflag"),
		styleSetting("cdbarCueRunningStyle", "Running Out Style", "drain", "underbar"),
	})
end
