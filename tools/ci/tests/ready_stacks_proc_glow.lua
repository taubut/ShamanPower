-- client: forever
-- regime: secrets
-- (3.0.9.15) A player's /sperrors (Discord, "Lua Error non stop"): "Frame:SetParent(): Reparenting disallowed as
-- child object would inherit forbidden aspects" from ShamanPower_ReadyStacks.lua, 62 times. Maelstrom Weapon's
-- At 5 Stacks Glow with Glow Shape Proc Glow took a frame from the shared Proc Glow pool and moved it onto a part
-- on the game's aura button; the game refuses any frame moved in there. The ring is now made on that part itself
-- (never pooled, no script): no error, and the ring is there, looping, in the Glow Color.
local SP = ShamanPower
local W = __sim.W
local e
for _, x in ipairs(SP.ReadyReminderSpells or {}) do if x.key == "maelstrom" then e = x end end
if not (e and SP.ReadyStacks and SP.ReadyStacksAPI and W.foreverClasses) then skip("no Maelstrom Weapon reminder here") end

-- as ready_stacks_hook_refused.lua: the game's number formatter, the talent known, the buff out of combat
if not C_StringUtil.CreateNumericRuleFormatter then
	C_StringUtil.CreateNumericRuleFormatter = function()
		local f = { rules = {} }
		function f:AddBreakpoint(b) self.rules[#self.rules + 1] = b; table.sort(self.rules, function(x, y) return x.threshold < y.threshold end); return true end
		function f:FormatNumber(n)
			local pick
			for _, b in ipairs(self.rules) do if n >= b.threshold then pick = b end end
			return pick and (pick.format:find("%%d") and pick.format:format(n) or pick.format) or ""
		end
		return f
	end
end
SP.ReadyStacksAPI.Buff.engine = nil
local SE, KN = SPCompat.SpellExists, SPCompat.KnowsSpellID
SPCompat.SpellExists = function(id) if id == 408498 then return true end return SE(id) end
SPCompat.KnowsSpellID = function(id) if id == 408498 then return true end return KN(id) end
e.clientID = nil
W.fireEvent("SPELLS_CHANGED")
local stacks = 0
local get = C_UnitAuras.GetPlayerAuraBySpellID
C_UnitAuras.GetPlayerAuraBySpellID = function(id)
	if id == 408505 then
		if stacks <= 0 then return nil end
		return { applications = stacks, expirationTime = GetTime() + 20, duration = 30, spellId = 408505 }
	end
	return get and get(id)
end
local function setStacks(n)
	stacks = n
	__sim.auraApplications(n)
	W.fireEvent("UNIT_AURA", "player", {}); SP:UpdateReadyReminders(); __sim.advance(0.1)
end

-- every error the addon hands to the error handler (BugGrabber's popup in game)
local errs = {}
local geh = geterrorhandler
geterrorhandler = function() return function(err) errs[#errs + 1] = tostring(err) end end

-- the game: a frame moved (SetParent) onto anything on its aura button is refused; one made there is fine
local REFUSED = "Frame:SetParent(): Reparenting disallowed as child object would inherit forbidden aspects: "
	.. "UntrustedScriptExecution, UntrustedLayoutScriptExecution, AlwaysPropagateInput, ScriptedInput, QueryFocus"
local function onGameButton(p)
	local n = 0
	while p and n < 50 do
		if p.GetObjectType and p:GetObjectType() == "AuraButton" then return true end
		p = p.GetParent and p:GetParent() or nil
		n = n + 1
	end
	return false
end
local FM = W.classes.Frame.methods
local realSetParent = FM.SetParent
local hadOwn = rawget(FM, "SetParent")
FM.SetParent = function(self, p, ...)
	if onGameButton(p) then error(REFUSED, 2) end
	return realSetParent(self, p, ...)
end
local pooled = 0
local acquire = SP.ProcGlowPool.Acquire
SP.ProcGlowPool.Acquire = function(...) pooled = pooled + 1; return acquire(...) end

-- the ring's loop texture under the reminder (any depth; the newest one last)
local LOOP = "UI-HUD-ActionBar-Proc-Loop-Flipbook"
local function allLoops(fr, out, depth)
	depth = depth or 0
	if depth > 12 then return out end
	for _, r in ipairs({ fr:GetRegions() }) do
		if r.GetAtlas and r:GetAtlas() == LOOP then out[#out + 1] = { r, fr } end
	end
	for _, c in ipairs({ fr:GetChildren() }) do allLoops(c, out, depth + 1) end
	return out
end
local function findLoop(fr)
	local all = allLoops(fr, {})
	local last = all[#all]
	if last then return last[1], last[2], #all end
	return nil, nil, 0
end

ShamanPower_ReadyReminders.enabled = true
SP:ReadyReminderSetSpell("maelstrom", true)
SP:ReadyReminderSetIconOpt("maelstrom", "readyEffect", "glow")   -- (the player's: At 5 Stacks Glow,
SP:ReadyReminderSetIconOpt("maelstrom", "glowShape", "proc")     --  Glow Shape Proc Glow)
setStacks(0)
setStacks(3)
local f = SP.readyReminderFrames.maelstrom
checkEq("Proc Glow on the game's aura button: no error", #errs, 0, errs[1])
check("the reminder's parts built", f and SP.ReadyStacks.Diag(f):find("failed=false", 1, true) ~= nil, f and SP.ReadyStacks.Diag(f))
checkEq("no frame taken from the Proc Glow pool", pooled, 0)
local loop, ring = findLoop(f)
check("the ring is there", loop ~= nil)
check("made on the part itself, on the game's button", ring and onGameButton(ring:GetParent()))
check("looping", ring and ring.ProcLoopAnim and ring.ProcLoopAnim:IsPlaying())
check("no start burst and no script on it (nothing the game refuses)", ring and not (ring.ProcStart and ring.ProcStart:IsShown())
	and ring.ProcStartAnim == nil and ring:GetScript("OnShow") == nil and ring:GetScript("OnHide") == nil)
setStacks(5); setStacks(2); setStacks(5)
checkEq("up and down through 5 stacks: still no error", #errs, 0, errs[1])

-- its Glow Color: the ring in that color (white: the game's own gold, as before)
SP:ReadyReminderSetIconOpt("maelstrom", "glowColor", { r = 0.2, g = 0.6, b = 1 })
setStacks(0); setStacks(3)
loop = findLoop(f)   -- (the newest: the parts were made again for the new color)
local r, g, b = 1, 1, 1
if loop and loop.GetVertexColor then r, g, b = loop:GetVertexColor() end
check("a Glow Color reaches the ring", loop and math.abs(r - 0.2) < 0.02 and math.abs(g - 0.6) < 0.02 and math.abs(b - 1) < 0.02,
	("%.2f %.2f %.2f"):format(r or -1, g or -1, b or -1))
__sim.setCombat(true); setStacks(5); __sim.advance(0.5)
__sim.setCombat(false); __sim.advance(1.2)
checkEq("in and out of a fight: still no error", #errs, 0, errs[1])

-- the other Proc Glows (own frames, never the game's) still use the pool as before
local probe = CreateFrame("Frame", nil, UIParent); probe:SetSize(36, 36)
SP.ProcGlow_Start(probe, SP:ProcGlowOptions(probe, nil, "citest"))
check("Proc Glow elsewhere: from the pool as before", pooled == 1 and probe._ProcGlowcitest ~= nil)
SP.ProcGlow_Stop(probe, "citest")

-- put back
FM.SetParent = hadOwn
SP.ProcGlowPool.Acquire = acquire
geterrorhandler = geh
setStacks(0)
SP:ReadyReminderResetIcon("maelstrom")
SP:ReadyReminderSetSpell("maelstrom", false)
C_UnitAuras.GetPlayerAuraBySpellID = get
SPCompat.SpellExists, SPCompat.KnowsSpellID = SE, KN
finish()
