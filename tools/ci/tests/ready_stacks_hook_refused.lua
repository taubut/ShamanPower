-- client: forever
-- regime: secrets
-- (3.0.9.14) A CurseForge report: "Button:HookScript(): Cannot assign script handler for 'onshow' (blocked by
-- secret aspects)" from ShamanPower_ReadyStacks.lua, Maelstrom Weapon's reminder. The At 5 Stacks sound in a
-- fight hooked OnShow on the game's aura button, and the game now refuses that. The hooks are on frames of our
-- own now: no error, and the sound in a fight still plays (with the "buff back at 1" guard). If the game refused
-- those too: still no error, the reminder still draws, no sound in a fight (and never a wrong one), and out of a
-- fight the sound plays as before.
local SP = ShamanPower
local W = __sim.W
local e
for _, x in ipairs(SP.ReadyReminderSpells or {}) do if x.key == "maelstrom" then e = x end end
if not (e and SP.ReadyStacks and SP.ReadyStacksAPI and W.foreverClasses) then skip("no Maelstrom Weapon reminder here") end

-- as ready_stacks_sound.lua: the game's number formatter, the talent known, the buff out of combat
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
local plays = {}
local play = SP.PlaySoundWithVolume
SP.PlaySoundWithVolume = function(_, _, vol) plays[#plays + 1] = vol end
local function heard(fn) local n = #plays; fn(); return #plays - n end

-- every error the addon hands to the error handler (BugGrabber's popup in game)
local errs = {}
local geh = geterrorhandler
geterrorhandler = function() return function(err) errs[#errs + 1] = tostring(err) end end
local REFUSED = "Button:HookScript(): Cannot assign script handler for 'onshow' (blocked by secret aspects)"

-- 1. the game refuses a hook on its own aura button (the report)
local AB = W.foreverClasses.AuraButton.methods
local abHook = rawget(AB, "HookScript")
AB.HookScript = function() error(REFUSED, 2) end

ShamanPower_ReadyReminders.enabled = true
SP:ReadyReminderSetSpell("maelstrom", true)
SP:ReadyReminderSetIconOpt("maelstrom", "soundOnReady", true)
SP:ReadyReminderSetIconOpt("maelstrom", "stackShow", "five")      -- (the player's: Only At 5 Stacks,
SP:ReadyReminderSetIconOpt("maelstrom", "readyEffect", "both")    --  Glow + Pulse)
setStacks(0)
setStacks(3)
local f = SP.readyReminderFrames.maelstrom
checkEq("the game refusing its button's hook: no error", #errs, 0, errs[1])
check("the reminder's parts built, none refused", f and SP.ReadyStacks.Diag(f):find("failed=false", 1, true) ~= nil, f and SP.ReadyStacks.Diag(f))
check("the hooks went on frames of ours: nothing said refused", not SP.ReadyStacks.Diag(f):find("refused", 1, true))
setStacks(1); __sim.advance(1.2)
checkEq("out of a fight, 5 stacks: the sound", (heard(function() setStacks(5) end)), 1)
setStacks(2); __sim.advance(1.2)
__sim.setCombat(true); __sim.advance(0.2)
checkEq("in a fight, 3 stacks: no sound", (heard(function() setStacks(3) end)), 0)
checkEq("in a fight, 5 stacks: the sound", (heard(function() setStacks(5); __sim.advance(0.1) end)), 1)
__sim.advance(1.2)
checkEq("in a fight, spent: no sound", (heard(function() setStacks(0) end)), 0)
checkEq("in a fight, the buff back at 1: no sound", (heard(function() setStacks(1); __sim.advance(0.1) end)), 0)
__sim.setCombat(false); __sim.advance(1.2)
checkEq("still no error after the fight", #errs, 0, errs[1])

-- 2. the game refusing hooks on our frames on its button too: still no error, no sound in a fight (never a
-- wrong one), out of a fight the sound as before
local CF = CreateFrame
CreateFrame = function(kind, name, parent, ...)
	local fr = CF(kind, name, parent, ...)
	if parent and parent.GetObjectType and parent:GetObjectType() == "AuraButton" then
		fr.HookScript = function() error(REFUSED, 2) end
	end
	return fr
end
SP:ReadyReminderSetIconOpt("maelstrom", "stackLeft", "number")   -- (a new build of its parts)
setStacks(0); setStacks(2)
checkEq("refused on our frames too: no error", #errs, 0, errs[1])
check("the reminder still draws", SP.ReadyStacks.Diag(f):find("failed=false", 1, true) ~= nil, SP.ReadyStacks.Diag(f))
check("its diagnostics say why there is no sound in a fight", SP.ReadyStacks.Diag(f):find("refused", 1, true) ~= nil, SP.ReadyStacks.Diag(f))
__sim.advance(1.2)
checkEq("out of a fight, 5 stacks: the sound as before", (heard(function() setStacks(5) end)), 1)
setStacks(2); __sim.advance(1.2)
__sim.setCombat(true); __sim.advance(0.2)
checkEq("in a fight, 5 stacks: no sound (the game refused)", (heard(function() setStacks(5); __sim.advance(0.1) end)), 0)
checkEq("in a fight, the buff back at 1: no wrong sound", (heard(function() setStacks(0); setStacks(1); __sim.advance(0.1) end)), 0)
__sim.setCombat(false); __sim.advance(1.2)

-- put back
CreateFrame = CF
AB.HookScript = abHook
geterrorhandler = geh
SP.PlaySoundWithVolume = play
setStacks(0)
SP:ReadyReminderResetIcon("maelstrom")
SP:ReadyReminderSetSpell("maelstrom", false)
C_UnitAuras.GetPlayerAuraBySpellID = get
SPCompat.SpellExists, SPCompat.KnowsSpellID = SE, KN
finish()
