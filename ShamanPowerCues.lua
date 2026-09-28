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
}
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
if WOW_PROJECT_ID ~= WOW_PROJECT_MAINLINE and type(DestroyTotem) == "function" and hooksecurefunc then
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

-- A loop (pulse: the icon darkening and back; glow: the edges breathing) that
-- runs until loopOff. Calling it again while it runs changes nothing.
local function loopOn(host, style, t, look)
	if ThemeCue and ThemeCue.loop(host, style, t, look) then return end
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
	loop = function(host, style, kind, look) loopOn(host, style, TINT[kind] or TINT.expiring, look) end,
	stop = loopOff,
}

-- ---------------------------------------------------------------------------
-- Totem bar
-- ---------------------------------------------------------------------------
-- The button a totem's cue plays on: the element's own button. The Compact,
-- Grid and Blizzard's-bar styles draw their totems elsewhere: no cues there.
local function totemHost(element)
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
			local selfEnding = type(p.name) == "string" and p.name:find("Fire Nova", 1, true)
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
function SP:CueCooldownCheck(btn, start, duration)
	if not self.opt.cdbarCueReady then btn._cueCdEnd = nil return end
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
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("PLAYER_ENTERING_WORLD")   -- a loading screen: totems it removes are not "destroyed"
loader:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_ENTERING_WORLD" then SP._cueWorldAt = GetTime() return end
	SP:ApplyCueSettings()
end)
if SP.OnOnOff then SP:OnOnOff(function() SP:ApplyCueSettings() end) end
