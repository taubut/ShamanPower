-- ShamanPowerCues
-- Visual cues on the bars (Settings > Bars > Totem Bar / Cooldown Bar > Effects), every one
-- off by default:
--   totem bar     a totem destroyed (killed before its time), a totem that ran
--                 out, and a loop over a totem's last seconds
--   cooldown bar  a cooldown ready again, a weapon imbue gone, the shield gone
-- A one-shot cue is a style played on the button: shake or pop (the button's
-- icon texture moves; a secure button's own frame is never animated), flash
-- (the icon lit in the cue's color) or glow (its edges). Every part is built the
-- first time it plays and reused after: a play is Stop, a few setters and Play,
-- nothing allocated. Nothing runs while the cues are off.
--
-- Where each cue comes from:
--   destroyed / expired  the core's totem record says why a totem went, in
--                        combat on WoW: Forever too (ShadowTotemSlotUpdate calls
--                        TotemEndCue); otherwise the readable slots on
--                        PLAYER_TOTEM_UPDATE (CueTotemUpdate), with the core's
--                        half-second wait so a Totemic Recall, your own dismiss,
--                        your death or a re-drop is never "destroyed"
--   expiring             the totems' own start and duration, 5 times a second
--                        while a totem is down (the core's record in combat on
--                        Forever)
--   ready / imbue        the cooldown bar's own update (UpdateCooldownButtons)
--   shield               the shield going, seen out of combat and on Anniversary.
--                        In combat on Forever the game hides that moment, so a
--                        red "missing" loop sits under the game's shield icon and
--                        shows the instant the game takes its icon away.

local SP = ShamanPower
if not SP then return end

local WHITE = "Interface\\Buttons\\WHITE8x8"
local MARK = "Interface\\RaidFrame\\ReadyCheck-NotReady"
local TINT = {
	destroyed = { 1, 0.15, 0.1 },
	expired   = { 0.95, 0.95, 0.95 },
	expiring  = { 1, 0.6, 0.1 },
	ready     = { 1, 0.82, 0.25 },
	imbue     = { 0.35, 0.65, 1 },
	shield    = { 0.35, 0.65, 1 },
	running   = { 1, 0.6, 0.1 },     -- Running Out: the Expiring Soon orange
	almost    = { 1, 0.82, 0.25 },   -- Cooldown Almost Ready: the Cooldown Ready gold
	usual     = { 1, 0.82, 0.25 },   -- Put Your Usual Totem Back: the same gold, in the Totem Bar's Effects Look
}
-- WoW's own red and gold (each client's RED_FONT_COLOR / NORMAL_FONT_COLOR), read
-- once: Turns red, and the time on a button that is running out
local WOW_RED, WOW_GOLD = { 1, 0.125, 0.125 }, { 1, 0.82, 0 }
local wowRead = false
local function wowColors()
	if wowRead then return end
	wowRead = true
	for _, pair in ipairs({ { RED_FONT_COLOR, WOW_RED }, { NORMAL_FONT_COLOR, WOW_GOLD } }) do
		local c, into = pair[1], pair[2]
		if c and c.GetRGB then
			local ok, r, g, b = pcall(c.GetRGB, c)
			if ok and type(r) == "number" then into[1], into[2], into[3] = r, g, b end
		end
	end
end
local VERDICT_WINDOW = 0.5   -- the core's bind window: a recall / dismiss / re-drop can trail the slot update
-- the theme looks and the new styles (ShamanPowerThemeEffects.lua, loaded
-- before this file): each painter below asks it first; on the Standard look
-- with today's styles it answers false and today's drawing runs unchanged
local ThemeCue = SP.ThemeCue

local function secretNow()
	return SPCompat and SPCompat.secretsRegime and SPCompat.AnyRestrictionActive and SPCompat.AnyRestrictionActive() or false
end
local function isSecret(v) return issecretvalue and issecretvalue(v) or false end

-- Anniversary: the core stamps your own right-click dismissals on the Mainline
-- family only (its in-combat record needs them there); the cues need them on
-- every client, or a dismissed totem would read as destroyed.
if not SPCompat.FOREVER and type(DestroyTotem) == "function" and hooksecurefunc then
	hooksecurefunc("DestroyTotem", function(slot)
		slot = tonumber(slot)
		if slot and SP._totemDismissedAt then SP._totemDismissedAt[slot] = GetTime() end
	end)
end

-- ---------------------------------------------------------------------------
-- Parts
-- ---------------------------------------------------------------------------
local function alphaAnim(group, order, from, to, duration)
	local a = group:CreateAnimation("Alpha")
	a:SetOrder(order)
	a:SetFromAlpha(from)
	a:SetToAlpha(to)
	a:SetDuration(duration)
	return a
end

-- The light over a button: a flash, four glowing edges, a dark layer (the
-- expiring pulse) and an X, on a plain frame above the button's text and the
-- game-drawn layers (the cooldown bar shield's are at +6 and +12).
local function cueFrame(host)
	local c = host.spCue
	if c then return c end
	c = CreateFrame("Frame", nil, host)
	c:SetAllPoints(host)
	c:SetFrameLevel(host:GetFrameLevel() + 14)

	local flash = c:CreateTexture(nil, "OVERLAY")
	flash:SetAllPoints(c)
	flash:SetTexture(WHITE)
	flash:SetBlendMode("ADD")
	flash:SetAlpha(0)
	c.flash = flash
	c.flashOnce = flash:CreateAnimationGroup()
	alphaAnim(c.flashOnce, 1, 0, 0.8, 0.08); alphaAnim(c.flashOnce, 2, 0.8, 0, 0.3)
	c.flashTwice = flash:CreateAnimationGroup()
	alphaAnim(c.flashTwice, 1, 0, 0.8, 0.08); alphaAnim(c.flashTwice, 2, 0.8, 0, 0.22)
	alphaAnim(c.flashTwice, 3, 0, 0.8, 0.08); alphaAnim(c.flashTwice, 4, 0.8, 0, 0.3)

	local dim = c:CreateTexture(nil, "ARTWORK")
	dim:SetAllPoints(c)
	dim:SetColorTexture(0, 0, 0)
	dim:SetAlpha(0)
	c.dimLoop = dim:CreateAnimationGroup()
	c.dimLoop:SetLooping("BOUNCE")
	alphaAnim(c.dimLoop, 1, 0, 0.55, 0.45)

	local glow = CreateFrame("Frame", nil, c)
	glow:SetAllPoints(c)
	glow:SetAlpha(0)
	local E = {}
	for i = 1, 4 do
		local e = glow:CreateTexture(nil, "OVERLAY")
		e:SetTexture(WHITE)
		e:SetBlendMode("ADD")
		E[i] = e
	end
	E[1]:SetPoint("TOPLEFT"); E[1]:SetPoint("TOPRIGHT")         -- top
	E[2]:SetPoint("BOTTOMLEFT"); E[2]:SetPoint("BOTTOMRIGHT")   -- bottom
	E[3]:SetPoint("TOPLEFT"); E[3]:SetPoint("BOTTOMLEFT")       -- left
	E[4]:SetPoint("TOPRIGHT"); E[4]:SetPoint("BOTTOMRIGHT")     -- right
	glow.edges = E
	c.glow = glow
	c.glowPulses = glow:CreateAnimationGroup()
	for k = 0, 2 do
		alphaAnim(c.glowPulses, k * 2 + 1, 0, 1, 0.12)
		alphaAnim(c.glowPulses, k * 2 + 2, 1, 0, 0.25)
	end
	c.glowLoop = glow:CreateAnimationGroup()
	c.glowLoop:SetLooping("BOUNCE")
	alphaAnim(c.glowLoop, 1, 0.2, 1, 0.5)

	local mark = c:CreateTexture(nil, "OVERLAY", nil, 7)
	mark:SetTexture(MARK)
	mark:SetPoint("CENTER")
	mark:SetAlpha(0)
	c.mark = mark
	-- in, held, out: 5 seconds at most (a re-drop of the element stops it sooner)
	c.markHold = mark:CreateAnimationGroup()
	alphaAnim(c.markHold, 1, 0, 1, 0.1); alphaAnim(c.markHold, 2, 1, 1, 4.5); alphaAnim(c.markHold, 3, 1, 0, 0.4)

	host.spCue = c
	return c
end

local function paintGlow(c, h, t)
	local w = math.max(2, math.floor(h * 0.1 + 0.5))
	local E = c.glow.edges
	E[1]:SetHeight(w); E[2]:SetHeight(w); E[3]:SetWidth(w); E[4]:SetWidth(w)
	for i = 1, 4 do E[i]:SetVertexColor(t[1], t[2], t[3], 0.9) end
end

-- Shake and pop move the icon texture itself (its own groups, next to the
-- raid-call pop the core plays on the same texture).
local function iconMotion(icon, style, h)
	if SP.ThemeIconMotion then SP:ThemeIconMotion(icon, style, h) end   -- a theme's flat-box skin over the icon moves with it
	if style == "shake" then
		local g = icon.spCueShake
		if not g then
			g = icon:CreateAnimationGroup()
			for k = 1, 4 do
				local a = g:CreateAnimation("Translation")
				a:SetOrder(k)
				g[k] = a
			end
			icon.spCueShake = g
		end
		local d = math.max(2, h * 0.09)
		g[1]:SetOffset(d, 0); g[1]:SetDuration(0.04)
		g[2]:SetOffset(-2 * d, 0); g[2]:SetDuration(0.07)
		g[3]:SetOffset(2 * d, 0); g[3]:SetDuration(0.07)
		g[4]:SetOffset(-d, 0); g[4]:SetDuration(0.05)
		g:Stop(); g:Play()
	elseif style == "pop" then
		local g = icon.spCuePop
		if not g then
			g = icon:CreateAnimationGroup()
			local a1 = g:CreateAnimation("Scale")
			a1:SetOrder(1); a1:SetScaleFrom(1, 1); a1:SetScaleTo(1.3, 1.3); a1:SetDuration(0.12); a1:SetSmoothing("OUT")
			local a2 = g:CreateAnimation("Scale")
			a2:SetOrder(2); a2:SetScaleFrom(1.3, 1.3); a2:SetScaleTo(1, 1); a2:SetDuration(0.25); a2:SetSmoothing("IN_OUT")
			icon.spCuePop = g
		end
		g:Stop(); g:Play()
	end
end

if ThemeCue then ThemeCue.init(cueFrame, TINT, iconMotion, alphaAnim) end

-- One cue: kind picks the color (TINT), style what it does.
-- look: a look to play in (a preview), nil = the effect's own
local function playCue(host, style, kind, icon, look)
	if not host then return end
	if ThemeCue and ThemeCue.play(host, style, kind, icon, look) then return end
	local c = cueFrame(host)
	local t = TINT[kind] or TINT.expired
	local h = host:GetHeight()
	if style == "glow" then
		paintGlow(c, h, t)
		c.glowPulses:Stop(); c.glowPulses:Play()
	elseif style == "flash" then
		c.flash:SetVertexColor(t[1], t[2], t[3])
		c.flashOnce:Stop(); c.flashTwice:Stop(); c.flashTwice:Play()
	else   -- shake / pop: the icon moves and lights once
		icon = icon or host.icon
		if icon then iconMotion(icon, style, h) end
		c.flash:SetVertexColor(t[1], t[2], t[3])
		c.flashTwice:Stop(); c.flashOnce:Stop(); c.flashOnce:Play()
	end
end

local function showMark(host, look)
	if ThemeCue and ThemeCue.mark(host, look) then return end
	local c = cueFrame(host)
	local s = host:GetHeight() * 0.75
	c.mark:SetSize(s, s)
	c.markHold:Stop(); c.markHold:Play()
end

-- the mark on a button goes (it was recast): today's red X and a theme's marks and flags
local function clearHostMark(host)
	local c = host and host.spCue
	if not c then return end
	if c.markHold:IsPlaying() then c.markHold:Stop() end
	if c.spTheme and ThemeCue then ThemeCue.clear(c) end
end

-- Red X Until You Imbue Again / Cast a Shield Again (Cooldown Bar > Effects): the
-- totem bar's mark, in the cooldown bar's own Effects Look
local function cdbarMark(btn, kind)
	showMark(btn, ThemeCue and ThemeCue.lookOf and ThemeCue.lookOf(kind) or nil)
end

-- "Turns red" (Running Out, Turns Red While Missing, the totem bar's Expiring
-- Soon): the icon in WoW's red with its time and charges sharp on top. A tint (MOD)
-- and a wash on the button itself, over its icon and under its text, and a 1 px red
-- edge on the cue frame. Where it goes (host.spRunHigh): nil = that; "top" = the
-- wash over the button's dark "gone" layer too (a missing shield or imbue: no text
-- to keep sharp); true = the game draws the icon above the button's own art (the
-- cooldown bar's shield in a fight on WoW: Forever): the wash goes over it, on the
-- cue frame. The same in every Effects Look. Built the first time, then only shown
-- and hidden.
-- which bar's Icon Shape a button follows, and the icon it shapes (nil: none)
local function shapeKind(host)
	local icon = host.icon
	if not icon and host.GetName and host:GetName() == "ShamanPowerEarthShieldBtn" then
		return "totem", _G.ShamanPowerEarthShieldBtnIcon   -- (its template icon has no .icon key)
	end
	if not icon then return nil end
	if host.spShapeKind then return host.spShapeKind, icon end
	if host.spellType then return "cooldown", icon end
	return "totem", icon   -- (totem buttons, Totem Rows' buttons)
end
-- whether a bar's icons are masked to a shape (Flat is still square)
local function shaped(kind)
	return kind and SP.IconShapeOf and SP.IconShapeMaskFile and SP:IconShapeMaskFile(SP:IconShapeOf(kind)) ~= nil or false
end
local function redParts(host)
	local r = host.spRed
	if r then return r end
	wowColors()
	local R = WOW_RED
	local c = cueFrame(host)
	r = {}
	-- (OVERLAY under 0: over the icon, its sweeps and a theme's flat box; under the button's
	-- own time, counts and dark layer, at 0 and up, and a flat box's letters, at -1)
	r.tint = host:CreateTexture(nil, "OVERLAY", nil, -3)
	r.tint:SetAllPoints(host)
	r.tint:SetColorTexture(1, 0.6, 0.6)
	r.tint:SetBlendMode("MOD")
	r.tint:Hide()
	r.wash = host:CreateTexture(nil, "OVERLAY", nil, -2)
	r.wash:SetAllPoints(host)
	r.wash:SetColorTexture(R[1], R[2], R[3], 0.45)
	r.wash:Hide()
	r.top = host:CreateTexture(nil, "OVERLAY", nil, 1)
	r.top:SetAllPoints(host)
	r.top:SetColorTexture(R[1], R[2], R[3], 0.45)
	r.top:Hide()
	r.high = c:CreateTexture(nil, "BACKGROUND")
	r.high:SetAllPoints(c)
	r.high:SetColorTexture(R[1], R[2], R[3], 0.5)
	r.high:Hide()
	local edge = CreateFrame("Frame", nil, c)
	edge:SetAllPoints(c)
	for i = 1, 4 do
		local e = edge:CreateTexture(nil, "OVERLAY", nil, 6)
		e:SetColorTexture(R[1], R[2], R[3], 1)
		edge[i] = e
	end
	edge[1]:SetPoint("TOPLEFT"); edge[1]:SetPoint("TOPRIGHT"); edge[1]:SetHeight(1)
	edge[2]:SetPoint("BOTTOMLEFT"); edge[2]:SetPoint("BOTTOMRIGHT"); edge[2]:SetHeight(1)
	edge[3]:SetPoint("TOPLEFT"); edge[3]:SetPoint("BOTTOMLEFT"); edge[3]:SetWidth(1)
	edge[4]:SetPoint("TOPRIGHT"); edge[4]:SetPoint("BOTTOMRIGHT"); edge[4]:SetWidth(1)
	edge:Hide()
	r.edge = edge
	-- Icon Shape (Rounded / Circle): the red takes the icon's shape
	local icon
	r.kind, icon = shapeKind(host)
	if r.kind and icon and SP.ShapeIconTexture then
		for _, t in ipairs({ r.tint, r.wash, r.top, r.high }) do SP:ShapeIconTexture(t, icon, r.kind) end
	end
	host.spRed = r
	return r
end
local function redOn(host, where)
	local r = redParts(host)
	where = where or false
	if host.spRedOn and host.spRedHigh == where then return end
	host.spRedOn, host.spRedHigh = true, where
	local high, top = where == true, where == "top"
	r.tint:SetShown(not high)
	r.wash:SetShown(not (high or top))
	r.top:SetShown(top)
	r.high:SetShown(high)
	-- the thin red edge is square: none round a shaped icon
	r.edge:SetShown(not shaped(r.kind))
end
local function redOff(host)
	local r = host.spRed
	if not (r and host.spRedOn) then return end
	host.spRedOn, host.spRedHigh = nil, nil
	r.tint:Hide(); r.wash:Hide(); r.top:Hide(); r.high:Hide(); r.edge:Hide()
end

-- A loop (pulse: the icon darkening and back; glow: the edges breathing; Turns
-- red) that runs until loopOff. Calling it again while it runs changes nothing.
-- kind: whose loop, for its look and colors (nil: Totem Expiring Soon).
local function loopOn(host, style, t, look, kind)
	if style == "red" then
		local c = host.spCue
		if c then
			c.dimLoop:Stop(); c.glowLoop:Stop()
			if c.spTheme and ThemeCue then ThemeCue.stop(c) end
		end
		redOn(host, host.spRunHigh)
		return
	end
	redOff(host)
	if ThemeCue and ThemeCue.loop(host, style, t, look, kind) then return end
	local c = cueFrame(host)
	if style == "glow" then
		if not c.glowLoop:IsPlaying() then
			c.dimLoop:Stop()
			paintGlow(c, host:GetHeight(), t)
			c.glowLoop:Play()
		end
	elseif not c.dimLoop:IsPlaying() then
		c.glowLoop:Stop()
		c.dimLoop:Play()
	end
end
local function loopOff(host)
	redOff(host)
	local c = host.spCue
	if c then c.dimLoop:Stop(); c.glowLoop:Stop() end
	if c and c.spTheme and ThemeCue then ThemeCue.stop(c) end   -- a theme's loop
end

-- The settings preview (Effects tab) plays the same effects on its own mock
-- buttons (any frame with an .icon texture). look (optional): "standard" /
-- "elemental" / "signal" to show that look whatever the Themes tab has.
SP.CueFx = {
	play = function(host, style, kind, look) playCue(host, style, kind, host.icon, look) end,
	mark = showMark,
	loop = function(host, style, kind, look) loopOn(host, style, TINT[kind] or TINT.expiring, look, kind) end,
	stop = loopOff,
}

-- ---------------------------------------------------------------------------
-- Totem bar
-- ---------------------------------------------------------------------------
-- The button a totem's cue plays on: the element's own button. The Compact,
-- Grid and Blizzard's-bar styles draw their totems elsewhere: no cues there.
local function totemHost(element)
	-- Totem Rows with the main bar hidden: the row's totem that is down
	local rowBtn = SP.RowsCarryButton and SP:RowsCarryButton(element)
	if rowBtn then
		if rowBtn.icon and rowBtn:IsVisible() then return rowBtn, rowBtn.icon end
		return nil
	end
	if SP.CompactActive and SP:CompactActive() then return nil end
	if SP.GridActive and SP:GridActive() then return nil end
	if SP.UsingBlizzardTotemBar and SP:UsingBlizzardTotemBar() then return nil end
	local btn = SP.totemButtons and SP.totemButtons[element]
	if btn and btn.icon and btn:IsVisible() then return btn, btn.icon end
	return nil
end

local expiringHost = {}   -- [element] = the button its expiring loop plays on

local function stopExpiring(element)
	local host = expiringHost[element]
	if not host then return end
	expiringHost[element] = nil
	loopOff(host)
end

local function startExpiring(element, style)
	local host = totemHost(element)
	if expiringHost[element] ~= host then stopExpiring(element) end
	if not host then return end
	loopOn(host, style, TINT.expiring)
	expiringHost[element] = host
end

local function clearMark(element)
	local btn = SP.totemButtons and SP.totemButtons[element]
	local c = btn and btn.spCue
	if c and c.markHold:IsPlaying() then c.markHold:Stop() end
	if c and c.spTheme and ThemeCue then ThemeCue.clear(c) end   -- a theme's mark or flag
end

function SP:TotemCuesWanted()
	local o = self.opt
	return o and (o.totemCueDestroyed or o.totemCueExpired) and true or false
end

-- A totem went (why: destroyed / expired / recalled / dismissed / died / unknown).
function SP:TotemEndCue(element, why)
	stopExpiring(element)
	local o = self.opt
	if not o or self:IsOff() then return end
	if why == "destroyed" and o.totemCueDestroyed then
		local host, icon = totemHost(element)
		if not host then return end
		playCue(host, o.totemCueDestroyedStyle or "shake", "destroyed", icon)
		if o.totemCueDestroyedMark ~= false then showMark(host) end
	elseif why == "expired" and o.totemCueExpired then
		local host, icon = totemHost(element)
		if not host then return end
		playCue(host, o.totemCueExpiredStyle or "pop", "expired", icon)
	end
end

-- The readable path (Anniversary always, Forever out of combat): the slots as
-- they were, and the destroyed verdicts waiting out the window (one per
-- element, answered by a callback made once, so nothing is made per totem).
local prevTotem = { {}, {}, {}, {} }
local pendingAt, pendingSlot, verdict = {}, {}, {}
for element = 1, 4 do
	verdict[element] = function()
		local at, slot = pendingAt[element], pendingSlot[element]
		pendingAt[element], pendingSlot[element] = nil, nil
		if not at then return end
		local recall = SP._totemRecallAt
		if recall and at - recall < 2 then return end
		local dismissed = slot and SP._totemDismissedAt and SP._totemDismissedAt[slot]
		if dismissed and at - dismissed < 2 then return end
		if UnitIsDeadOrGhost("player") then return end
		-- a loading screen (hearth, portal, instance) or a flight path takes totems too
		if SP._cueWorldAt and at - SP._cueWorldAt < 3 then return end
		if UnitOnTaxi and UnitOnTaxi("player") then return end
		if SP:GetElementTotemInfo(element) then return end   -- that element is down again
		SP:TotemEndCue(element, "destroyed")
	end
end

-- PLAYER_TOTEM_UPDATE (after the core has taken it in)
function SP:CueTotemUpdate()
	local wanted = self:TotemCuesWanted() and not self:IsOff()
	local secret = wanted and secretNow()   -- the check costs a few protected calls: only when it matters
	local now = GetTime()
	for element = 1, 4 do
		local have, name, start, duration, _, slot = self:GetElementTotemInfo(element)
		local p = prevTotem[element]
		if have then clearMark(element) end
		if wanted and not secret and p.active and not have then
			-- Fire Nova Totem (Anniversary) removes itself when it goes off, ahead of its time
			local selfEnding = SPCompat.TotemNameMatches(p.name, 1535, "Fire Nova Totem")
			if selfEnding or (type(p.duration) == "number" and p.duration > 0 and now - p.start >= p.duration - 0.5) then
				self:TotemEndCue(element, "expired")
			else
				pendingAt[element], pendingSlot[element] = now, p.slot
				C_Timer.After(VERDICT_WINDOW, verdict[element])
			end
		end
		if isSecret(start) or isSecret(duration) then start, duration = nil, nil end
		if isSecret(name) then name = nil end
		p.active, p.name, p.start, p.duration, p.slot = have and true or false, name, start, duration, slot
	end
end

-- Expiring: 5 times a second, only while the option is on and a totem is down.
local expiringState = {}
local function expiringPass()
	local o = SP.opt
	if not o.totemCueExpiring then
		for element = 1, 4 do stopExpiring(element) end
		return
	end
	local secs = o.totemCueExpiringSecs or 5
	local style = o.totemCueExpiringStyle or "pulse"
	local now = GetTime()
	for element = 1, 4 do
		local have, _, start, duration = SP:GetElementTotemInfo(element)
		local left = have and type(start) == "number" and type(duration) == "number" and not isSecret(start)
			and duration > secs + 1 and (start + duration - now) or nil
		if left and left > 0 and left <= secs then startExpiring(element, style) else stopExpiring(element) end
	end
end

-- ---------------------------------------------------------------------------
-- Cooldown bar
-- ---------------------------------------------------------------------------
-- A tracked cooldown (UpdateCooldownButtons, cooldown branch): ready when it
-- stops being on cooldown within a few seconds of when it was due (a bar that
-- was hidden meanwhile does not cue late).
-- real (WoW: Forever): the game's own answer from that pass, true = cooling,
-- false = ready (its flags; the engine's end signal wakes that pass at once).
-- It cues the moment a cooldown seen cooling is ready, a reset or a shortened
-- one included, if it was seen cooling in the last few seconds. nil: the game
-- has no answer, and the estimate times it as before.
function SP:CueCooldownCheck(btn, start, duration, real)
	local t = btn.cooldownType   -- (its own settings: ShamanPowerCdItems.lua)
	if not self:CdItemOpt(t, "cueReady") then btn._cueCdEnd, btn._cueCdSeen = nil, nil return end
	if real ~= nil then
		local now = GetTime()
		btn._cueCdEnd = nil
		if real then
			btn._cueCdSeen = now
		elseif btn._cueCdSeen then
			local seen = btn._cueCdSeen
			btn._cueCdSeen = nil
			if now - seen < 3 then playCue(btn, self:CdItemOpt(t, "cueReadyStyle"), "ready") end
		end
		return
	end
	if type(start) ~= "number" or type(duration) ~= "number" or isSecret(start) or isSecret(duration) then return end
	if start > 0 and duration > 1.5 then
		btn._cueCdEnd = start + duration
	elseif btn._cueCdEnd then
		local late = GetTime() - btn._cueCdEnd
		-- still due later: the global cooldown is showing over the spell's last moment
		if late < -0.1 then return end
		btn._cueCdEnd = nil
		if late < 3 then playCue(btn, self:CdItemOpt(t, "cueReadyStyle"), "ready") end
	end
end

-- The weapon imbue button: either hand's own imbue gone (ran out, or the weapon
-- swapped). A totem's weapon enchant (Windfury Totem on Anniversary) is not the
-- shaman's imbue: it is not in EnchantIDToImbue and never has more than ~10 s
-- left, so an enchant counts as the shaman's when it is known or has longer.
local function ownImbue(has, id, left)
	if not has then return false end
	if isSecret(id) or isSecret(left) then return true end
	if id and SP.EnchantIDToImbue and SP.EnchantIDToImbue[id] then return true end
	return type(left) == "number" and left > 15000
end
function SP:CueImbueCheck(btn, hasMain, hasOff, mainID, offID, mainLeft, offLeft)
	local t = btn.cooldownType
	if not self:CdItemOpt(t, "cueGone") then btn._cueMain, btn._cueOff = nil, nil return end
	if isSecret(hasMain) or isSecret(hasOff) then return end
	hasMain, hasOff = ownImbue(hasMain, mainID, mainLeft), ownImbue(hasOff, offID, offLeft)
	local gone = (btn._cueMain and not hasMain) or (btn._cueOff and not hasOff)
	-- imbued again: the red X and a theme's corner flag go (until recast)
	if (hasMain and btn._cueMain == false) or (hasOff and btn._cueOff == false) then clearHostMark(btn) end
	btn._cueMain, btn._cueOff = hasMain, hasOff
	if gone then
		playCue(btn, self:CdItemOpt(t, "cueGoneStyle"), "imbue")
		if self:CdItemOpt(t, "cueMark") then cdbarMark(btn, "imbue") end   -- Red X Until You Imbue Again
	end
end

-- The shield. Seen going: confirmed a moment later (a shield swapped for the
-- other one can read as gone for one update). In combat on Forever: the red
-- missing loop between the addon's no-shield look and the game's shield icon,
-- only at full opacity (below it, it would show through the game's icon).
local pendingShieldBtn
local function confirmShield()
	local btn = pendingShieldBtn
	pendingShieldBtn = nil
	if not btn or btn._cueShield or not SP:CdItemOpt(btn.cooldownType, "cueGone") then return end
	if UnitIsDeadOrGhost("player") then return end   -- dying strips the shield: not "gone"
	playCue(btn, SP:CdItemOpt(btn.cooldownType, "cueGoneStyle"), "shield")
	if SP:CdItemOpt(btn.cooldownType, "cueMark") then cdbarMark(btn, "shield") end   -- Red X Until You Cast a Shield Again
end

local function missingLayer(btn)
	local m = btn.spCueMissing
	if m then return m end
	m = CreateFrame("Frame", nil, btn)
	m:SetAllPoints(btn)
	m:SetFrameLevel(btn:GetFrameLevel() + 4)   -- under the game's shield button (container at +6)
	local t = m:CreateTexture(nil, "OVERLAY")
	t:SetAllPoints(m)
	t:SetColorTexture(TINT.destroyed[1], TINT.destroyed[2], TINT.destroyed[3])
	t:SetAlpha(0)
	m.loop = t:CreateAnimationGroup()
	m.loop:SetLooping("BOUNCE")
	alphaAnim(m.loop, 1, 0.08, 0.5, 0.5)
	-- Turns Red While Missing, in a fight: a steady red and a red edge, the same way
	wowColors()
	local red = m:CreateTexture(nil, "ARTWORK")
	red:SetAllPoints(m)
	red:SetColorTexture(WOW_RED[1], WOW_RED[2], WOW_RED[3], 0.45)
	red:Hide()
	m.red = red
	local edge = CreateFrame("Frame", nil, m)
	edge:SetAllPoints(m)
	for i = 1, 4 do
		local e = edge:CreateTexture(nil, "OVERLAY", nil, 2)
		e:SetColorTexture(WOW_RED[1], WOW_RED[2], WOW_RED[3], 1)
		edge[i] = e
	end
	edge[1]:SetPoint("TOPLEFT"); edge[1]:SetPoint("TOPRIGHT"); edge[1]:SetHeight(1)
	edge[2]:SetPoint("BOTTOMLEFT"); edge[2]:SetPoint("BOTTOMRIGHT"); edge[2]:SetHeight(1)
	edge[3]:SetPoint("TOPLEFT"); edge[3]:SetPoint("BOTTOMLEFT"); edge[3]:SetWidth(1)
	edge[4]:SetPoint("TOPRIGHT"); edge[4]:SetPoint("BOTTOMRIGHT"); edge[4]:SetWidth(1)
	edge:Hide()
	m.redEdge = edge
	-- Red X Until You Cast a Shield Again, in a fight: the X under the game's shield icon,
	-- seen while no shield is up (the moment it went cannot be seen there)
	local x = m:CreateTexture(nil, "OVERLAY", nil, 1)
	x:SetTexture(MARK)
	x:SetPoint("CENTER")
	x:SetAlpha(0)
	m.x = x
	btn.spCueMissing = m
	return m
end

local function stopMissing(btn)
	local m = btn.spCueMissing
	if m and m.loop:IsPlaying() then m.loop:Stop() end
	if m and m.xOn then m.xOn = nil; m.x:SetAlpha(0) end
end

function SP:CueShieldState(btn, hasShield, engine)
	if not self:CdItemOpt(btn.cooldownType, "cueGone") then
		stopMissing(btn)
		btn._cueShield = nil
		return
	end
	if engine then
		-- the drop itself cannot be seen: the loop the game's icon hides while the shield is up
		btn._cueShield = nil   -- the readable state starts fresh after the fight: no late cue
		if (btn:GetEffectiveAlpha() or 1) >= 0.99 then
			local m = missingLayer(btn)
			if not m.loop:IsPlaying() then m.loop:Play() end
			local xOn = self:CdItemOpt(btn.cooldownType, "cueMark") and true or nil
			if m.xOn ~= xOn then
				m.xOn = xOn
				local size = btn:GetHeight() * 0.75
				m.x:SetSize(size, size)
				m.x:SetAlpha(xOn and 1 or 0)
			end
		else
			stopMissing(btn)
		end
		return
	end
	stopMissing(btn)
	local had = btn._cueShield
	btn._cueShield = hasShield and true or false
	if hasShield and had == false then clearHostMark(btn) end   -- recast: the red X and a theme's flag go
	if had and not hasShield then
		pendingShieldBtn = btn
		C_Timer.After(0.4, confirmShield)
	end
end

-- ---------------------------------------------------------------------------
-- Running out: Show Items Only When Running Out (Cooldown Bar > Display) and
-- the running-out effects (Cooldown Bar > Effects). One moment for both, set by
-- two settings shown on both pages: a shield or weapon imbue runs out in its
-- last cdbarRunOutSecs seconds (a shield also on its last charge); a cooldown
-- is almost ready in its last cdbarAlmostSecs seconds. The cooldown bar's own
-- pass (UpdateCooldownButtons: 5 a second while something counts down in
-- seconds, once a second otherwise) hands each button's state to the three
-- RunOut* methods below, which answer whether that pass should keep its fast
-- pace (a moment due within the next second). Nothing here runs by itself.
--
-- WoW: Forever in a fight: weapon imbue times stay readable; cooldown times come
-- from ShamanPower's own record of your casts (the same numbers the bar shows in
-- fights); the shield is drawn by the game, and the moment it runs out early is
-- hidden from addons, so Show Items Only When Running Out keeps it on the bar
-- for the whole fight.
-- ---------------------------------------------------------------------------
-- Both per item (ShamanPowerCdItems.lua: Running Out At / Almost Ready At); t nil (the totem
-- bar's Earth Shield button): the shared seconds
local function runOutSecs(t) return SP:CdItemOpt(t, "runOutSecs") or 60 end
local function almostSecs(t) return SP:CdItemOpt(t, "almostSecs") or 5 end

-- Show Items Only When Running Out shows everything while Keybind Mode or Unlock UI
-- is open (to bind or place what is out of sight) and while the Test button plays
local function showAll(btn)
	if btn._roTestUntil and GetTime() < btn._roTestUntil then return true end
	if SP.KeybindModeActive and SP:KeybindModeActive() then return true end
	if SP.IsMasterUnlocked and SP:IsMasterUnlocked() then return true end
	return false
end

-- a popped-out item is a tracker of its own: it stays in sight (its key made once)
local function poppedOut(btn)
	local p = SP.opt.poppedOut
	if p == nil or btn.cooldownType == nil then return false end
	local key = btn._roPopKey
	if not key then key = "cd_" .. btn.cooldownType; btn._roPopKey = key end
	return p[key] == true
end

-- Grid lays every shield / imbue choice out beside the button: with nothing single to hide,
-- the shield and imbue stay in sight there
local function gridKeeps(btn)
	return (btn.spellType == "shield" or btn.spellType == "weaponImbue") and SP.CooldownBarGridOn and SP:CooldownBarGridOn(btn.cooldownType) or false
end

-- In or out of sight. Out of sight keeps the button's spot, so nothing on the bar
-- moves: its alpha goes to 0 (UpdateCooldownBarOpacity; alpha may change in a
-- fight), and out of a fight its mouse goes too, so it is really gone: no click,
-- tooltip or flyout. In a fight the game locks the mouse: the fight's start
-- gives every button its mouse back (a click on an empty spot still casts there).
local function setShown(btn, want)
	local hide = (not want) or nil
	if btn._roHidden ~= hide then
		btn._roHidden = hide
		SP:UpdateCooldownBarOpacity()
	end
	if not InCombatLockdown() then
		-- (the tab that opens its flyout, WoW: Forever's arrow layout, goes with it)
		local tab = btn.spFlyoutOpenArrow
		if hide and not btn._roMouseOff then
			btn._roMouseOff = true
			btn:EnableMouse(false)
			if tab then tab:EnableMouse(false) end
		elseif not hide and btn._roMouseOff then
			btn._roMouseOff = nil
			btn:EnableMouse(true)
			if tab then tab:EnableMouse(true) end
		end
	end
end

local function onlyRunningOut(btn)
	return SP.opt and SP:CdItemOpt(btn.cooldownType, "runOutOnly") and not SP:IsOff() or false
end

local function decideShown(btn, want)
	if not want and (not onlyRunningOut(btn) or poppedOut(btn) or showAll(btn) or gridKeeps(btn)) then want = true end
	if want and not btn._roHidden and not btn._roMouseOff then return end   -- shown already: nothing to do
	setShown(btn, want)
end

-- The look on a shield / imbue / Earth Shield button (Cooldown Bar > Effects):
-- Running Out's style while it runs out, Turns red while it is missing (Turns Red
-- While Missing); nil: none. The Test button plays Running Out for 3 seconds
-- whatever the switch, then (with Turns Red While Missing on) the missing red for
-- 3 more. what: "shield" / "imbue" / "es" (its element for Frame drains); frac: the
-- part of the running-out time still left (Frame drains, Bar under it); where: see
-- redOn. Returns true while a look follows the time or a test plays (the pass keeps
-- its pace).
local function runLook(btn, style, what, frac, where)
	local now = GetTime()
	local test = false
	local t = btn._roTestRun
	if t then
		if now < t then
			style, frac, test = SP:CdItemOpt(btn.cooldownType or (what == "es" and 12) or nil, "cueRunningStyle"), (t - now) / 3, true
		else
			btn._roTestRun = nil
		end
	end
	t = btn._roTestMiss
	if t and not test then
		if now >= t then
			btn._roTestMiss = nil
		elseif now >= t - 3 then
			style, frac, test = "red", 1, true
			if where ~= true then where = "top" end   -- (in a fight on WoW: Forever: over the game's icon)
		end
	end
	if style and not SP:IsOff() then
		if where ~= true and where ~= "top" then where = false end
		btn.spRunKind, btn.spRunFrac, btn.spRunHigh = what, frac or 1, where
		local moving = style == "drain" or style == "underbar"
		if btn._roLook ~= style or btn._roHigh ~= where or moving then
			btn._roLook, btn._roHigh = style, where
			loopOn(btn, style, TINT.running, nil, "running")
		end
		return moving or test
	end
	if btn._roLook then
		btn._roLook, btn._roHigh = nil, nil
		btn.spRunFrac, btn.spRunHigh = nil, nil
		loopOff(btn)
	end
	return (btn._roTestMiss ~= nil) and true or false
end

-- the look a readable shield / imbue wants: its Running Out style, or the missing red
local function wantedLook(t, state)
	if state == "out" and SP:CdItemOpt(t, "cueRunning") then return SP:CdItemOpt(t, "cueRunningStyle"), false end
	if state == "gone" and SP:CdItemOpt(t, "cueMissing") then return "red", "top" end
	return nil, false
end

-- Time Turns Red While Running Out: the time on a button that is running out in
-- WoW's red (WoW's gold on a cooldown almost ready); on a button that turns red it
-- stays white, to read it. Painted only when it changes; each text's own color is
-- kept and put back.
local TIME0 = { "timeText" }                                 -- the time in the button's middle (Show Cooldown Text)
local TIME1 = { "insideText", "outsideText", "iconText" }    -- Duration Text Location (the imbue's main hand)
local TIME2 = { "insideText2", "outsideText2", "iconText2" } -- the imbue's off hand
local function paintTimes(btn, fields, color)
	for i = 1, #fields do
		local fs = btn[fields[i]]
		if fs then
			if color then
				if not fs.spRoColored then
					local b = fs.spRoBase
					if not b then b = {}; fs.spRoBase = b end
					b[1], b[2], b[3], b[4] = fs:GetTextColor()
					fs.spRoColored = true
				end
				fs:SetTextColor(color[1], color[2], color[3])
			elseif fs.spRoColored then
				local b = fs.spRoBase
				fs:SetTextColor(b[1] or 1, b[2] or 1, b[3] or 1, b[4] or 1)
				fs.spRoColored = nil
			end
		end
	end
end
local function timeColor(btn, slot, fields, want)
	if btn[slot] == want then return end
	btn[slot] = want
	wowColors()
	paintTimes(btn, fields, (want == "red" and WOW_RED) or (want == "gold" and WOW_GOLD) or nil)
end
local function timeRed(btn, on)
	return (on and SP:CdItemOpt(btn.cooldownType, "cueTimeColor") and btn._roLook ~= "red" and not SP:IsOff()) and "red" or nil
end

-- Turns Red While Missing in a fight on WoW: Forever: the moment a shield goes
-- cannot be seen there, so the red sits under the game's shield icon (the missing
-- layer, see CueShieldState) and shows the moment the game takes the icon away. Only
-- at full opacity: below it the red would show through the game's icon.
local function missingRed(btn, on)
	local m = btn.spCueMissing
	if on then
		m = m or missingLayer(btn)
		if not m.redOn then
			m.redOn = true
			if not m.redShaped and SP.ShapeIconTexture and btn.icon then
				m.redShaped = true
				SP:ShapeIconTexture(m.red, btn.icon, "cooldown")
			end
			m.red:Show()
			m.redEdge:SetShown(not shaped("cooldown"))
		end
	elseif m and m.redOn then
		m.redOn = nil
		m.red:Hide()
		m.redEdge:Hide()
	end
end

-- The shield button. up: the shield the button shows is up; left: its seconds
-- left (nil: unknown); charges: its charges; engine: auras are hidden (WoW:
-- Forever in a fight), the game draws the shield on the button. A shield that is
-- gone stays in sight until you cast one again. In a fight on WoW: Forever the
-- Running Out look follows ShamanPower's own record of your cast (its time, and
-- the charges it can count), over the game's own shield; the game colors its own
-- time text (ShieldTimeTextOptions).
function SP:RunOutShield(btn, up, left, charges, engine)
	local o = self.opt
	if not o or not btn then return false end
	local t = btn.cooldownType
	local N = runOutSecs(t)
	local state, runOn, frac
	if engine then
		state = "fight"
		local sh = self.shadowShield
		local sl = (sh and type(sh.start) == "number" and type(sh.duration) == "number") and (sh.start + sh.duration - GetTime()) or nil
		if sl and sl <= 0 then sl = nil end
		runOn = sl ~= nil and (sl <= N or sh.charges == 1)
		frac, left = sl and sl / N or 1, sl
	elseif not up then
		state = "gone"
	elseif (left and left <= N) or charges == 1 then
		state, runOn = "out", true
		frac = left and left / N or 1
	else
		state = "plenty"
	end
	decideShown(btn, state ~= "plenty")
	local style, where
	if engine then
		-- (missing, in a fight: the red under the game's icon, missingRed below)
		style, where = (runOn and self:CdItemOpt(t, "cueRunning")) and self:CdItemOpt(t, "cueRunningStyle") or nil, true
	else
		style, where = wantedLook(t, state)
		if where == false and btn.darkOverlay and btn.darkOverlay:IsShown() then where = "top" end
	end
	local busy = runLook(btn, style, "shield", frac, where)
	missingRed(btn, engine and self:CdItemOpt(t, "cueMissing") and not self:IsOff() and (btn:GetEffectiveAlpha() or 1) >= 0.99)
	local tc = (not engine) and timeRed(btn, runOn) or nil
	timeColor(btn, "_roTime0", TIME0, tc)
	timeColor(btn, "_roTime1", TIME1, tc)
	if left ~= nil and left > N and left <= N + 1.2 then busy = true end
	return busy
end

-- The weapon imbue button, from the game's read (hasMain / hasOff, the enchants'
-- IDs, their milliseconds left). With an off-hand weapon both hands count: the
-- button comes up when either hand's imbue is in its last seconds or gone; each
-- hand's time turns red on its own.
function SP:RunOutImbue(btn, hasMain, hasOff, mainID, offID, mainLeft, offLeft)
	local o = self.opt
	if not o or not btn then return false end
	if isSecret(hasMain) or isSecret(hasOff) then return false end
	local t = btn.cooldownType
	local N = runOutSecs(t) * 1000
	local upM, upO = ownImbue(hasMain, mainID, mainLeft), ownImbue(hasOff, offID, offLeft)
	local mL = (upM and type(mainLeft) == "number" and not isSecret(mainLeft)) and mainLeft or nil
	local oL = (upO and type(offLeft) == "number" and not isSecret(offLeft)) and offLeft or nil
	local dual = self.HasOffHandWeapon and self:HasOffHandWeapon()
	local outM, outO = mL ~= nil and mL <= N, oL ~= nil and oL <= N
	local state
	if not upM or (dual and not upO) then
		state = "gone"
	elseif outM or outO then
		state = "out"
	else
		state = "plenty"
	end
	decideShown(btn, state ~= "plenty")
	local least = mL
	if oL and (not least or oL < least) then least = oL end
	local style, where = wantedLook(t, state)
	if where == false and btn.darkOverlay and btn.darkOverlay:IsShown() then where = "top" end   -- (a style's view not lit)
	local busy = runLook(btn, style, "imbue", least and least / N or 1, where)
	timeColor(btn, "_roTime0", TIME0, timeRed(btn, state == "out"))
	timeColor(btn, "_roTime1", TIME1, timeRed(btn, outM))
	timeColor(btn, "_roTime2", TIME2, timeRed(btn, outO))
	if (mL and mL > N and mL <= N + 1200) or (oL and oL > N and oL <= N + 1200) then busy = true end
	return busy
end

-- Earth Shield (TBC Anniversary: its button at the end of the totem bar): Running
-- Out in its last seconds or on 2 charges (where its number turns red), from the
-- core's carrier record (twice a second while the button shows: esButton). Its
-- settings are its own slot, 12 (ShamanPowerCdItems.lua: never the shield's).
function SP:RunOutEarthShield(esBtn, target, charges)
	local o = self.opt
	if not (o and esBtn) then return end
	local N = runOutSecs(12)
	local exp = self.esTrackedExpiration
	local left = (target and type(exp) == "number" and exp > 0) and (exp - GetTime()) or nil
	local on = target ~= nil and type(charges) == "number" and charges > 0 and (charges <= 2 or (left ~= nil and left <= N))
	local style = (on and self:CdItemOpt(12, "cueRunning") and esBtn:IsVisible()) and self:CdItemOpt(12, "cueRunningStyle") or nil
	runLook(esBtn, style, "es", left and left / N or 1, false)
end

-- Cooldown Almost Ready (Cooldown Bar > Effects): a cooldown's last seconds play
-- a look in the Cooldown Ready gold, on a frame of its own over the button (its
-- holder). On WoW: Forever the game decides the exact moment, in and out of
-- fights: the holder's alpha is a step on the real cooldown's time left (a curve
-- on the duration object the bar's game-drawn cooldown uses, handed straight to
-- SetAlpha, never read or compared: the same calls as Ready Reminders' Countdown
-- Only Under). The look itself starts by ShamanPower's own estimate, a moment
-- early, so it is not left running unseen for the whole cooldown.
local underCurves = {}   -- [seconds] = curve (false: none), made once
local function underCurve(sec)
	local c = underCurves[sec]
	if c == nil then
		c = false
		if C_CurveUtil and C_CurveUtil.CreateCurve then
			local ok, made = pcall(C_CurveUtil.CreateCurve)
			if ok and made then
				local linear = Enum and Enum.LuaCurveType and Enum.LuaCurveType.Linear
				if made.SetType and linear then pcall(made.SetType, made, linear) end
				-- under the seconds: shown; from there up: hidden
				if pcall(made.AddPoint, made, math.max(0, sec - 0.05), 1) and pcall(made.AddPoint, made, sec, 0) then c = made end
			end
		end
		underCurves[sec] = c
	end
	return c or nil
end

local function almostHolder(btn)
	local h = btn.spAlmost
	if h then return h end
	h = CreateFrame("Frame", nil, btn)
	h:SetAllPoints(btn)
	h:SetFrameLevel(btn:GetFrameLevel() + 1)
	btn.spAlmost = h
	return h
end

-- on: in its last seconds (WoW: Forever with dur: about to be, by the estimate);
-- frac: the part of them still left (Frame drains, Bar under it); dur: the game's
-- duration object for it (WoW: Forever), A: the seconds. Returns true while a look
-- follows the time.
local function almostLook(btn, on, frac, dur, A)
	local t = btn.cooldownType
	local test = btn._roTestAlmost
	if test then
		local now = GetTime()
		if now < test then
			on, frac, dur = true, (test - now) / 3, nil
		else
			btn._roTestAlmost, test = nil, nil
		end
	end
	if on and (SP:CdItemOpt(t, "cueAlmost") or test) and not SP:IsOff() then
		local h = almostHolder(btn)
		h.spRunFrac = frac or 1
		local style = SP:CdItemOpt(t, "cueAlmostStyle")
		if style == "red" then style = "glow" end   -- (red is for what runs out; a cooldown gets gold)
		local moving = style == "drain" or style == "underbar"
		if btn._roAlmost ~= style or moving then
			btn._roAlmost = style
			loopOn(h, style, TINT.almost, nil, "almost")
		end
		local curve = dur and A and A > 0 and dur.EvaluateRemainingDuration and underCurve(A)
		local curved = false
		if curve then
			local ok, a = pcall(dur.EvaluateRemainingDuration, dur, curve)
			if ok then curved = pcall(h.SetAlpha, h, a) end   -- a may be secret: handed over, never looked at
		end
		if not curved then h:SetAlpha(1) end
		return moving or test ~= nil
	end
	if btn._roAlmost then
		btn._roAlmost = nil
		local h = btn.spAlmost
		if h then
			loopOff(h)
			h.spRunFrac = nil
			h:SetAlpha(1)
		end
	end
	return false
end

-- the time of a cooldown the game draws (WoW: Forever): its own countdown text, in
-- WoW's gold while almost ready (the core marks it to be painted again whenever it
-- places that text afresh: FeedEngineBarCooldown)
local function engineTimeGold(btn, want)
	want = want or nil
	if btn._roEngTime == want then return end
	btn._roEngTime = want
	local cd = btn.cooldown
	local ok, fs = false, nil
	if cd and cd.GetCountdownFontString then ok, fs = pcall(cd.GetCountdownFontString, cd) end
	if not (ok and fs) then return end
	wowColors()
	if want then
		if not fs.spRoColored then
			local b = fs.spRoBase
			if not b then b = {}; fs.spRoBase = b end
			b[1], b[2], b[3], b[4] = fs:GetTextColor()
			fs.spRoColored = true
		end
		fs:SetTextColor(WOW_GOLD[1], WOW_GOLD[2], WOW_GOLD[3])
	elseif fs.spRoColored then
		local b = fs.spRoBase
		fs:SetTextColor(b[1] or 1, b[2] or 1, b[3] or 1, b[4] or 1)
		fs.spRoColored = nil
	end
end

-- WoW: Forever: whether ShamanPower's estimate of a cooldown in a fight is only the
-- spell's base length (never seen readable this session): talents can make the real
-- one shorter, so the estimate may end late
function SP:RunOutEstimateSeeded(spellID)
	local shadow = SPCompat and SPCompat.shadowCooldowns
	if not (shadow and spellID) then return false end
	local e = shadow[GetSpellInfo(spellID) or spellID]
	return (e and e.seeded) and true or false
end

-- A cooldown button. cooling: on a real cooldown (WoW: Forever: the game's own
-- flags); left: its seconds left (nil: unknown, e.g. after a reload mid-fight).
-- Totemic Call has nothing to wait for: it comes up while you have totems down.
-- Reincarnation also comes up while your bags have no Ankh.
function SP:RunOutCooldown(btn, cooling, left)
	local o = self.opt
	if not o or not btn then return false end
	local t = btn.cooldownType
	local A = almostSecs(t)
	local now = GetTime()
	if left and left < 0 then left = 0 end
	-- the moment it turned ready: Hide It Again keeps it up while its Cooldown Ready plays
	if btn._roWasCooling and not cooling then btn._roReadyAt = now end
	btn._roWasCooling = cooling and true or nil
	local state
	if cooling then
		if left and left <= A then state = "almost" else state = "cooling" end
	else
		state = "ready"
	end
	-- cooling with no time known (WoW: Forever after a /reload in a fight: no record of the
	-- cast): it can't be told when it is almost ready, so it stays in sight; its Cooldown
	-- Almost Ready look still shows at the game's own moment (the curve below)
	local unknown = cooling and left == nil
	local busy = false
	if onlyRunningOut(btn) then
		local want
		if state == "almost" or unknown then
			want = true
		elseif state == "ready" then
			if self:CdItemOpt(t, "runOutReady") == "keep" then
				want = true
			else
				local at = btn._roReadyAt
				want = at ~= nil and (now - at) < (self:CdItemOpt(t, "cueReady") and 2.2 or 0.5)
				if want then busy = true end
			end
		else
			want = false
		end
		if btn.spellID == 36936 then
			want = (state ~= "cooling" or unknown) and self:AnyTotemDown()
		elseif btn.spellID == 20608 and not want then
			want = (GetItemCount and GetItemCount(17030) or 1) == 0
		end
		decideShown(btn, want)
	elseif btn._roHidden or btn._roMouseOff then
		decideShown(btn, true)
	end
	-- Cooldown Almost Ready, and its time in gold (Time Turns Red While Running Out)
	local dur = cooling and btn._ebSpell and btn._ebDur or nil
	local lookOn
	if A <= 0 or not (self:CdItemOpt(t, "cueAlmost") or btn._roTestAlmost) then
		lookOn = false
	elseif dur then
		-- the game shows it at the exact moment; the look starts by the estimate, or at once when
		-- there is none or it is only the spell's base length (a first use in a fight: talents
		-- can make the real one shorter)
		lookOn = (left == nil) or left <= A + 0.5 or self:RunOutEstimateSeeded(btn.spellID)
	else
		lookOn = state == "almost"
	end
	if almostLook(btn, cooling and lookOn, (left and A > 0) and left / A or 1, dur, A) then busy = true end
	local gold = (state == "almost" and self:CdItemOpt(t, "cueTimeColor") and not self:IsOff()) and "gold" or nil
	if btn._ebSpell then
		engineTimeGold(btn, gold)
		timeColor(btn, "_roTime0", TIME0, nil)
		timeColor(btn, "_roTime1", TIME1, nil)
	else
		engineTimeGold(btn, nil)
		timeColor(btn, "_roTime0", TIME0, gold)
		timeColor(btn, "_roTime1", TIME1, gold)
	end
	if cooling and left and left > A and left <= A + 1.2 then busy = true end
	return busy
end

-- The looks and time colors start afresh (a switch, style, look or number of
-- seconds changed): the cooldown bar's next pass puts back what is wanted.
function SP:RunOutResetLooks()
	local function reset(btn)
		if btn._roLook then
			btn._roLook, btn._roHigh = nil, nil
			btn.spRunFrac, btn.spRunHigh = nil, nil
			loopOff(btn)
		end
		timeColor(btn, "_roTime0", TIME0, nil)
		timeColor(btn, "_roTime1", TIME1, nil)
		timeColor(btn, "_roTime2", TIME2, nil)
		if btn._roAlmost then
			btn._roAlmost = nil
			local h = btn.spAlmost
			if h then loopOff(h); h.spRunFrac = nil; h:SetAlpha(1) end
		end
		if btn._roEngTime then engineTimeGold(btn, nil) end
	end
	for _, btn in ipairs(self.cooldownButtons or {}) do reset(btn) end
	local es = _G["ShamanPowerEarthShieldBtn"]
	if es then reset(es) end
end

-- Whether the game-drawn shield's time is colored: Time Turns Red While Running Out on,
-- and not on a shield button that turns red (its time stays white)
local function shieldTimeColored(o)
	if not (o and SP:CdItemOpt(1, "cueTimeColor")) then return false end
	return not (SP:CdItemOpt(1, "cueRunning") and SP:CdItemOpt(1, "cueRunningStyle") == "red")
end
-- what the game-drawn shield's time is built with: 0 (today's white) or its seconds.
-- EnsureShieldChargeContainer keeps it on the button; a change builds the display again.
function SP:ShieldTimeTextKey()
	local o = self.opt
	return shieldTimeColored(o) and runOutSecs(1) or 0
end

-- The game-drawn shield's time (WoW: Forever, in a fight: EnsureShieldChargeContainer):
-- with Time Turns Red While Running Out the game colors it itself, WoW's red in its
-- last seconds (a step on the time left; nothing for Lua to read or compare). nil:
-- today's white (the switch off, or a shield button that turns red: its time stays white).
function SP:ShieldTimeTextOptions()
	local o = self.opt
	if not shieldTimeColored(o) then return nil end
	local CU, P = C_CurveUtil, Enum and Enum.DurationTextBindingProperty
	if not (CU and CU.CreateColorCurve and P and P.RemainingDuration and CreateColor) then return nil end
	local N = runOutSecs(1)
	local made = self._roTimeOpts
	if made and made.n == N then return made.opts end
	local ok, curve = pcall(CU.CreateColorCurve)
	if not (ok and curve) then return nil end
	wowColors()
	local step = Enum.LuaCurveType and Enum.LuaCurveType.Step or 1
	if not (pcall(curve.SetType, curve, step)
		and pcall(curve.AddPoint, curve, 0, CreateColor(WOW_RED[1], WOW_RED[2], WOW_RED[3], 1))
		and pcall(curve.AddPoint, curve, N, CreateColor(1, 1, 1, 1))) then return nil end
	local opts = { textColor = { curve = curve, property = P.RemainingDuration } }
	self._roTimeOpts = { n = N, opts = opts }
	return opts
end
-- every button back in sight (the switch turned off, ShamanPower switched off)
function SP:RunOutShowAll()
	for _, btn in ipairs(self.cooldownButtons or {}) do
		if btn._roHidden or btn._roMouseOff then setShown(btn, true) end
	end
end

-- The fight's start, the last moment a button's mouse can change: every spot
-- keeps working in the fight. After it, the cooldown bar's next pass takes the
-- mouse off what is out of sight again.
do
	local watch = CreateFrame("Frame")
	watch:RegisterEvent("PLAYER_REGEN_DISABLED")
	watch:SetScript("OnEvent", function()
		if InCombatLockdown() then return end   -- (too late: locked already)
		for _, btn in ipairs(SP.cooldownButtons or {}) do
			if btn._roMouseOff then
				btn._roMouseOff = nil
				btn:EnableMouse(true)
				if btn.spFlyoutOpenArrow then btn.spFlyoutOpenArrow:EnableMouse(true) end
			end
		end
	end)
end

-- Keybind Mode and Unlock UI show every item: at once when they open or close
if hooksecurefunc then
	local function modeChanged()
		if SP.cooldownBar and SP.opt and SP:CdItemAny("runOutOnly") and not SP:IsOff() then
			SP:WakeCooldownBar()
			SP:UpdateCooldownButtons()
		end
	end
	if SP.SetKeybindMode then hooksecurefunc(SP, "SetKeybindMode", modeChanged) end
	if SP.SetMasterUnlock then hooksecurefunc(SP, "SetMasterUnlock", modeChanged) end
end

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------
-- The expiring loop's update runs only while the option is on; everything else
-- is event-driven. Called at login and by every Effects setting.
function SP:ApplyCueSettings()
	local o = self.opt
	if not o then return end
	if not self.updateSystem.subsystems["totemCues"] then
		self:RegisterUpdateSubsystem("totemCues", 0.2, function()
			SP._whileTotemsDown(expiringState, expiringPass)
		end)
	end
	if o.totemCueExpiring and not self:IsOff() then
		self:EnableUpdateSubsystem("totemCues")
	else
		self:DisableUpdateSubsystem("totemCues")
		for element = 1, 4 do stopExpiring(element) end
	end
	if self.shieldButton and not self:CdItemOpt(self.shieldButton.cooldownType, "cueGone") then stopMissing(self.shieldButton) end
	-- the running-out settings: off or switched off, everything back in sight now; on, the
	-- cooldown bar's next pass (at once) decides what shows; the looks start afresh
	if not self:CdItemAny("runOutOnly") or self:IsOff() then self:RunOutShowAll() end
	self:RunOutResetLooks()
	-- WoW: Forever: the game-drawn shield's time colors are set when it is built: a change
	-- builds it again, once the settings stop changing (a slider drag sends many; a profile
	-- switch builds it by itself). RebuildShieldChargeContainer waits for the end of a fight.
	local sb = self.shieldButton
	if SPCompat.secretsRegime and sb and sb.chargeContainer and sb.spTimeKey ~= nil and sb.spTimeKey ~= self:ShieldTimeTextKey() then
		self._roRebuildGen = (self._roRebuildGen or 0) + 1
		local gen = self._roRebuildGen
		C_Timer.After(0.6, function()
			if gen ~= SP._roRebuildGen then return end
			local b = SP.shieldButton
			if b and b.chargeContainer and b.spTimeKey ~= SP:ShieldTimeTextKey() then SP:RebuildShieldChargeContainer() end
		end)
	end
	if self.cooldownBar and self.WakeCooldownBar then
		self:WakeCooldownBar()
		if not self:IsOff() and self.cooldownBar:IsShown() then self:UpdateCooldownButtons() end
	end
end

-- Test buttons: the chosen styles on the real bars, on or off.
function SP:TestTotemCues()
	local o = self.opt
	local host, icon = totemHost(1)
	if host then
		playCue(host, o.totemCueDestroyedStyle or "shake", "destroyed", icon)
		if o.totemCueDestroyedMark ~= false then showMark(host) end
	end
	host, icon = totemHost(2)
	if host then playCue(host, o.totemCueExpiredStyle or "pop", "expired", icon) end
	if totemHost(3) then
		startExpiring(3, o.totemCueExpiringStyle or "pulse")
		C_Timer.After(3, function() stopExpiring(3) end)
	end
end

function SP:TestCooldownCues()
	-- Show Items Only When Running Out: every item comes up while the test plays
	local imbue, shield = self.weaponImbueButton, self.shieldButton
	local miss = (imbue and self:CdItemOpt(imbue.cooldownType, "cueMissing")) or (shield and self:CdItemOpt(shield.cooldownType, "cueMissing")) or false
	local testFor = miss and 6 or 3
	if self:CdItemAny("runOutOnly") and self.cooldownBar then
		local untilAt = GetTime() + testFor + 0.5
		for _, btn in ipairs(self.cooldownButtons or {}) do btn._roTestUntil = untilAt end
		self:UpdateCooldownButtons()
		C_Timer.After(testFor + 0.6, function()
			if SP.cooldownBar and not SP:IsOff() then SP:WakeCooldownBar(); SP:UpdateCooldownButtons() end
		end)
	end
	for _, btn in ipairs(self.cooldownButtons or {}) do
		if btn.spellType == "cooldown" and btn:IsVisible() then
			playCue(btn, self:CdItemOpt(btn.cooldownType, "cueReadyStyle"), "ready")
			break
		end
	end
	if imbue and imbue:IsVisible() then
		playCue(imbue, self:CdItemOpt(imbue.cooldownType, "cueGoneStyle"), "imbue")
		if self:CdItemOpt(imbue.cooldownType, "cueMark") then cdbarMark(imbue, "imbue") end
	end
	if shield and shield:IsVisible() then
		playCue(shield, self:CdItemOpt(shield.cooldownType, "cueGoneStyle"), "shield")
		if self:CdItemOpt(shield.cooldownType, "cueMark") then cdbarMark(shield, "shield") end
	end
	-- Running Out plays for 3 seconds on the shield and the imbue, Cooldown Almost Ready on a
	-- cooldown (the second one shown: the first plays Cooldown Ready); the cooldown bar's pass runs them
	local runUntil = GetTime() + 3
	if imbue and imbue:IsVisible() then imbue._roTestRun = runUntil end
	if shield and shield:IsVisible() then shield._roTestRun = runUntil end
	-- then Turns Red While Missing, for 3 more (when it is on)
	if imbue and imbue:IsVisible() and self:CdItemOpt(imbue.cooldownType, "cueMissing") then imbue._roTestMiss = runUntil + 3 end
	if shield and shield:IsVisible() and self:CdItemOpt(shield.cooldownType, "cueMissing") then shield._roTestMiss = runUntil + 3 end
	local first, second
	for _, btn in ipairs(self.cooldownButtons or {}) do
		if btn.spellType == "cooldown" and btn:IsVisible() then
			if first then second = btn break end
			first = btn
		end
	end
	if second or first then (second or first)._roTestAlmost = runUntil end
	if self.cooldownBar then self:WakeCooldownBar(); self:UpdateCooldownButtons() end
end

-- One item's effects, with its own settings (its menu's Test This Item's Effects; t: its
-- cooldownType). A shield / imbue: its Gone style (and red X), then Running Out for 3
-- seconds, then Turns Red While Missing for 3 more when it is on. A cooldown: Cooldown
-- Ready, then Cooldown Almost Ready for 3 seconds. Shown while it plays even with Show
-- Only When Running Out. Returns false when the item is not on the bar.
function SP:TestCdItemCues(t)
	local btn
	if t == 1 then btn = self.shieldButton elseif t == 7 then btn = self.weaponImbueButton end
	if not btn then
		for _, b in ipairs(self.cooldownButtons or {}) do
			if b.cooldownType == t then btn = b break end
		end
	end
	if not (btn and btn:IsVisible() and btn.cooldownType) then return false end
	local now = GetTime()
	if btn.spellType == "cooldown" then
		btn._roTestUntil = now + 5
		playCue(btn, self:CdItemOpt(t, "cueReadyStyle"), "ready")
		C_Timer.After(1.2, function()
			btn._roTestAlmost = GetTime() + 3
			if SP.cooldownBar then SP:WakeCooldownBar(); SP:UpdateCooldownButtons() end
		end)
	else
		local miss = self:CdItemOpt(t, "cueMissing")
		btn._roTestUntil = now + (miss and 6 or 3) + 0.5
		local kind = (btn.spellType == "shield") and "shield" or "imbue"
		playCue(btn, self:CdItemOpt(t, "cueGoneStyle"), kind)
		if self:CdItemOpt(t, "cueMark") then cdbarMark(btn, kind) end
		btn._roTestRun = now + 3
		if miss then btn._roTestMiss = now + 6 end
	end
	C_Timer.After(6.6, function()
		if SP.cooldownBar and not SP:IsOff() then SP:WakeCooldownBar(); SP:UpdateCooldownButtons() end
	end)
	if self.cooldownBar then self:WakeCooldownBar(); self:UpdateCooldownButtons() end
	return true
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("PLAYER_ENTERING_WORLD")   -- a loading screen: totems it removes are not "destroyed"
loader:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_ENTERING_WORLD" then SP._cueWorldAt = GetTime() return end
	SP:ApplyCueSettings()
end)
if SP.OnOnOff then SP:OnOnOff(function() SP:ApplyCueSettings() end) end
