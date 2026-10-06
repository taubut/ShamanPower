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

-- "Turns red" (Running Out, and the totem bar's Expiring Soon): the icon in WoW's
-- red with its time and charges sharp on top. A tint (MOD) and a wash on the button
-- itself, over its icon and under its text, and a 1 px red edge on the cue frame.
-- high: the game draws the icon above the button's own art (the cooldown bar's
-- shield in a fight on WoW: Forever): the wash goes over it, on the cue frame. The
-- same in every Effects Look. Built the first time, then only shown and hidden.
local function redParts(host)
	local r = host.spRed
	if r then return r end
	wowColors()
	local R = WOW_RED
	local c = cueFrame(host)
	r = {}
	r.tint = host:CreateTexture(nil, "ARTWORK", nil, 6)
	r.tint:SetAllPoints(host)
	r.tint:SetColorTexture(1, 0.6, 0.6)
	r.tint:SetBlendMode("MOD")
	r.tint:Hide()
	r.wash = host:CreateTexture(nil, "ARTWORK", nil, 7)
	r.wash:SetAllPoints(host)
	r.wash:SetColorTexture(R[1], R[2], R[3], 0.45)
	r.wash:Hide()
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
	host.spRed = r
	return r
end
local function redOn(host, high)
	local r = redParts(host)
	high = high and true or false
	if host.spRedOn and host.spRedHigh == high then return end
	host.spRedOn, host.spRedHigh = true, high
	r.tint:SetShown(not high)
	r.wash:SetShown(not high)
	r.high:SetShown(high)
	r.edge:Show()
end
local function redOff(host)
	local r = host.spRed
	if not (r and host.spRedOn) then return end
	host.spRedOn, host.spRedHigh = nil, nil
	r.tint:Hide(); r.wash:Hide(); r.high:Hide(); r.edge:Hide()
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
	if not self.opt.cdbarCueReady then btn._cueCdEnd, btn._cueCdSeen = nil, nil return end
	if real ~= nil then
		local now = GetTime()
		btn._cueCdEnd = nil
		if real then
			btn._cueCdSeen = now
		elseif btn._cueCdSeen then
			local seen = btn._cueCdSeen
			btn._cueCdSeen = nil
			if now - seen < 3 then playCue(btn, self.opt.cdbarCueReadyStyle or "pop", "ready") end
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
		if late < 3 then playCue(btn, self.opt.cdbarCueReadyStyle or "pop", "ready") end
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
	if not self.opt.cdbarCueImbue then btn._cueMain, btn._cueOff = nil, nil return end
	if isSecret(hasMain) or isSecret(hasOff) then return end
	hasMain, hasOff = ownImbue(hasMain, mainID, mainLeft), ownImbue(hasOff, offID, offLeft)
	local gone = (btn._cueMain and not hasMain) or (btn._cueOff and not hasOff)
	-- imbued again: a theme's corner flag goes (until recast, like the red X)
	if ThemeCue and ((hasMain and btn._cueMain == false) or (hasOff and btn._cueOff == false)) then ThemeCue.clear(btn.spCue) end
	btn._cueMain, btn._cueOff = hasMain, hasOff
	if gone then playCue(btn, self.opt.cdbarCueImbueStyle or "shake", "imbue") end
end

-- The shield. Seen going: confirmed a moment later (a shield swapped for the
-- other one can read as gone for one update). In combat on Forever: the red
-- missing loop between the addon's no-shield look and the game's shield icon,
-- only at full opacity (below it, it would show through the game's icon).
local pendingShieldBtn
local function confirmShield()
	local btn = pendingShieldBtn
	pendingShieldBtn = nil
	if not btn or btn._cueShield or not SP.opt.cdbarCueShield then return end
	if UnitIsDeadOrGhost("player") then return end   -- dying strips the shield: not "gone"
	playCue(btn, SP.opt.cdbarCueShieldStyle or "shake", "shield")
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
	btn.spCueMissing = m
	return m
end

local function stopMissing(btn)
	local m = btn.spCueMissing
	if m and m.loop:IsPlaying() then m.loop:Stop() end
end

function SP:CueShieldState(btn, hasShield, engine)
	if not self.opt.cdbarCueShield then
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
		else
			stopMissing(btn)
		end
		return
	end
	stopMissing(btn)
	local had = btn._cueShield
	btn._cueShield = hasShield and true or false
	if hasShield and had == false and ThemeCue then ThemeCue.clear(btn.spCue) end   -- recast: a theme's flag goes
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
local function runOutSecs(o) return o.cdbarRunOutSecs or 60 end
local function almostSecs(o)
	local s = o.cdbarAlmostSecs
	if s == nil then return 5 end
	return s
end

-- Show Items Only When Running Out shows everything while Keybind Mode or Unlock UI
-- is open (to bind or place what is out of sight) and while the Test button plays
local function showAll(btn)
	if btn._roTestUntil and GetTime() < btn._roTestUntil then return true end
	if SP.KeybindModeActive and SP:KeybindModeActive() then return true end
	if SP.IsMasterUnlocked and SP:IsMasterUnlocked() then return true end
	return false
end

-- a popped-out item is a tracker of its own: it stays in sight
local function poppedOut(btn)
	return SP.opt.poppedOut ~= nil and btn.cooldownType ~= nil and SP:IsCooldownPoppedOut(btn.cooldownType)
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
		if hide and not btn._roMouseOff then
			btn._roMouseOff = true
			btn:EnableMouse(false)
		elseif not hide and btn._roMouseOff then
			btn._roMouseOff = nil
			btn:EnableMouse(true)
		end
	end
end

local function onlyRunningOut()
	local o = SP.opt
	return o and o.cdbarRunOutOnly and not SP:IsOff() or false
end

local function decideShown(btn, want)
	if not want and (not onlyRunningOut() or poppedOut(btn) or showAll(btn)) then want = true end
	if want and not btn._roHidden and not btn._roMouseOff then return end   -- shown already: nothing to do
	setShown(btn, want)
end

-- The Running Out look (Cooldown Bar > Effects) on a button: on while it runs
-- out, in the chosen style; the Test button plays it for 3 seconds whatever the
-- switch. what: "shield" / "imbue" / "es" (its element for Frame drains); frac:
-- the part of the running-out time still left (Frame drains, Bar under it); high:
-- see redOn. Returns true while a look follows the time (the pass keeps its pace).
local function runLook(btn, on, what, frac, high)
	local o = SP.opt
	local test = btn._roTestRun
	if test then
		local now = GetTime()
		if now < test then
			on, frac = true, (test - now) / 3
		else
			btn._roTestRun, test = nil, nil
		end
	end
	if on and (o.cdbarCueRunning or test) and not SP:IsOff() then
		local style = o.cdbarCueRunningStyle or "red"
		high = high and true or false
		btn.spRunKind, btn.spRunFrac, btn.spRunHigh = what, frac or 1, high
		local moving = style == "drain" or style == "underbar"
		if btn._roLook ~= style or btn._roHigh ~= high or moving then
			btn._roLook, btn._roHigh = style, high
			loopOn(btn, style, TINT.running, nil, "running")
		end
		return moving or test ~= nil
	end
	if btn._roLook then
		btn._roLook, btn._roHigh = nil, nil
		btn.spRunFrac, btn.spRunHigh = nil, nil
		loopOff(btn)
	end
	return false
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
local function timeRed(o, btn, on)
	return (on and o.cdbarCueTimeColor and btn._roLook ~= "red" and not SP:IsOff()) and "red" or nil
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
	local N = runOutSecs(o)
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
	local busy = runLook(btn, runOn, "shield", frac, engine)
	local tc = (not engine) and timeRed(o, btn, runOn) or nil
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
	local N = runOutSecs(o) * 1000
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
	local busy = runLook(btn, state == "out", "imbue", least and least / N or 1, false)
	timeColor(btn, "_roTime0", TIME0, timeRed(o, btn, state == "out"))
	timeColor(btn, "_roTime1", TIME1, timeRed(o, btn, outM))
	timeColor(btn, "_roTime2", TIME2, timeRed(o, btn, outO))
	if (mL and mL > N and mL <= N + 1200) or (oL and oL > N and oL <= N + 1200) then busy = true end
	return busy
end

-- Earth Shield (TBC Anniversary: its button at the end of the totem bar): Running
-- Out in its last seconds or on 2 charges (where its number turns red), from the
-- core's carrier record (twice a second while the button shows: esButton).
function SP:RunOutEarthShield(esBtn, target, charges)
	local o = self.opt
	if not (o and esBtn) then return end
	local N = runOutSecs(o)
	local exp = self.esTrackedExpiration
	local left = (target and type(exp) == "number" and exp > 0) and (exp - GetTime()) or nil
	local on = target ~= nil and type(charges) == "number" and charges > 0 and (charges <= 2 or (left ~= nil and left <= N))
	runLook(esBtn, on and esBtn:IsVisible(), "es", left and left / N or 1, false)
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
	local o = SP.opt
	local test = btn._roTestAlmost
	if test then
		local now = GetTime()
		if now < test then
			on, frac, dur = true, (test - now) / 3, nil
		else
			btn._roTestAlmost, test = nil, nil
		end
	end
	if on and (o.cdbarCueAlmost or test) and not SP:IsOff() then
		local h = almostHolder(btn)
		h.spRunFrac = frac or 1
		local style = o.cdbarCueAlmostStyle or "glow"
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
	local A = almostSecs(o)
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
	local busy = false
	if onlyRunningOut() then
		local want
		if state == "almost" then
			want = true
		elseif state == "ready" then
			if o.cdbarRunOutReady == "keep" then
				want = true
			else
				local at = btn._roReadyAt
				want = at ~= nil and (now - at) < (o.cdbarCueReady and 2.2 or 0.5)
				if want then busy = true end
			end
		else
			want = false
		end
		if btn.spellID == 36936 then
			want = state ~= "cooling" and self:AnyTotemDown()
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
	if A <= 0 then
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
	local gold = (state == "almost" and o.cdbarCueTimeColor and not self:IsOff()) and "gold" or nil
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

-- The game-drawn shield's time (WoW: Forever, in a fight: EnsureShieldChargeContainer):
-- with Time Turns Red While Running Out the game colors it itself, WoW's red in its
-- last seconds (a step on the time left; nothing for Lua to read or compare). nil:
-- today's white (the switch off, or a shield button that turns red: its time stays white).
function SP:ShieldTimeTextOptions()
	local o = self.opt
	if not (o and o.cdbarCueTimeColor) then return nil end
	if o.cdbarCueRunning and (o.cdbarCueRunningStyle or "red") == "red" then return nil end
	local CU, P = C_CurveUtil, Enum and Enum.DurationTextBindingProperty
	if not (CU and CU.CreateColorCurve and P and P.RemainingDuration and CreateColor) then return nil end
	local N = runOutSecs(o)
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
local function shieldTimeKey(o)
	local red = o.cdbarCueRunning and (o.cdbarCueRunningStyle or "red") == "red"
	return (o.cdbarCueTimeColor and 1 or 0) + (red and 2 or 0) + runOutSecs(o) * 4
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
		for _, btn in ipairs(SP.cooldownButtons or {}) do
			if btn._roMouseOff then
				btn._roMouseOff = nil
				btn:EnableMouse(true)
			end
		end
	end)
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
	if not o.cdbarCueShield and self.shieldButton then stopMissing(self.shieldButton) end
	-- the running-out settings: off or switched off, everything back in sight now; on, the
	-- cooldown bar's next pass (at once) decides what shows; the looks start afresh
	if not o.cdbarRunOutOnly or self:IsOff() then self:RunOutShowAll() end
	self:RunOutResetLooks()
	-- WoW: Forever: the game-drawn shield's time colors are set when it is built: build it
	-- again (RebuildShieldChargeContainer waits for the end of a fight by itself)
	if SPCompat.secretsRegime and self.shieldButton and self.RebuildShieldChargeContainer then
		local key = shieldTimeKey(o)
		if self._roShieldTimeKey ~= nil and self._roShieldTimeKey ~= key then self:RebuildShieldChargeContainer() end
		self._roShieldTimeKey = key
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
	local o = self.opt
	-- Show Items Only When Running Out: every item comes up while the test plays
	if o.cdbarRunOutOnly and self.cooldownBar then
		local untilAt = GetTime() + 3.5
		for _, btn in ipairs(self.cooldownButtons or {}) do btn._roTestUntil = untilAt end
		self:UpdateCooldownButtons()
		C_Timer.After(3.6, function()
			if SP.cooldownBar and not SP:IsOff() then SP:WakeCooldownBar(); SP:UpdateCooldownButtons() end
		end)
	end
	for _, btn in ipairs(self.cooldownButtons or {}) do
		if btn.spellType == "cooldown" and btn:IsVisible() then
			playCue(btn, o.cdbarCueReadyStyle or "pop", "ready")
			break
		end
	end
	local imbue = self.weaponImbueButton
	if imbue and imbue:IsVisible() then playCue(imbue, o.cdbarCueImbueStyle or "shake", "imbue") end
	local shield = self.shieldButton
	if shield and shield:IsVisible() then playCue(shield, o.cdbarCueShieldStyle or "shake", "shield") end
	-- Running Out plays for 3 seconds on the shield and the imbue, Cooldown Almost Ready on a
	-- cooldown (the second one shown: the first plays Cooldown Ready); the cooldown bar's pass runs them
	local runUntil = GetTime() + 3
	if imbue and imbue:IsVisible() then imbue._roTestRun = runUntil end
	if shield and shield:IsVisible() then shield._roTestRun = runUntil end
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

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("PLAYER_ENTERING_WORLD")   -- a loading screen: totems it removes are not "destroyed"
loader:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_ENTERING_WORLD" then SP._cueWorldAt = GetTime() return end
	SP:ApplyCueSettings()
end)
if SP.OnOnOff then SP:OnOnOff(function() SP:ApplyCueSettings() end) end
