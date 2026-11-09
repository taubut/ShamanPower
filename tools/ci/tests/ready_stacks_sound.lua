-- client: forever
-- regime: secrets
-- (3.0.9.9) Maelstrom Weapon's sound At 5 Stacks: every Ready Reminder's own ready sound (its Sound and Volume),
-- once each time the stacks reach 5. Out of a fight from the count; in a fight from the part the game shows only
-- from 5 stacks. Until 3.0.9.9 the game played it on "Maelstrom Ready!" (408501) with no volume (a Discord report:
-- no sound at 5 stacks).
local SP = ShamanPower
local W = __sim.W
local e
for _, x in ipairs(SP.ReadyReminderSpells or {}) do if x.key == "maelstrom" then e = x end end
if not (e and SP.ReadyStacks and SP.ReadyStacksAPI) then skip("no Maelstrom Weapon reminder here") end
check("the reminders' own ready sound is handed over", type(SP.ReadyStacksAPI.readySound) == "function")

-- as ready_stacks.lua: the game's number formatter, the talent known, the buff out of combat
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
-- the count as the game has it: read out of a fight, and its parts drawn (in a fight too)
local function setStacks(n)
	stacks = n
	__sim.auraApplications(n)
	W.fireEvent("UNIT_AURA", "player", {}); SP:UpdateReadyReminders(); __sim.advance(0.1)
end

local plays = {}
local play = SP.PlaySoundWithVolume
SP.PlaySoundWithVolume = function(_, _, vol) plays[#plays + 1] = vol end
local function heard(fn) local n = #plays; fn(); return #plays - n, plays[#plays] end

ShamanPower_ReadyReminders.enabled = true
SP:ReadyReminderSetSpell("maelstrom", true)
SP:ReadyReminderSetIconOpt("maelstrom", "soundOnReady", true)
SP:ReadyReminderSetIconOpt("maelstrom", "soundVolume", 35)
setStacks(0)

checkEq("3 stacks: no sound", (heard(function() setStacks(3) end)), 0)
checkEq("4 stacks: no sound", (heard(function() setStacks(4) end)), 0)
local n, vol = heard(function() setStacks(5) end)
checkEq("5 stacks: one sound", n, 1)
checkEq("at the icon's Volume", vol, 35)
__sim.advance(1.2)
checkEq("still 5: no second sound", (heard(function() setStacks(5) end)), 0)
setStacks(2); __sim.advance(1.2)
checkEq("spent, back to 5: the sound again", (heard(function() setStacks(5) end)), 1)

-- the sound off in its menu: nothing
SP:ReadyReminderSetIconOpt("maelstrom", "soundOnReady", false)
setStacks(1); __sim.advance(1.2)
checkEq("sound off: none", (heard(function() setStacks(5) end)), 0)
SP:ReadyReminderSetIconOpt("maelstrom", "soundOnReady", true)

-- in a fight: the count is hidden; the part the game shows from 5 stacks says when
setStacks(2); __sim.advance(1.2)
__sim.setCombat(true); __sim.advance(0.2)
checkEq("in a fight, 3 stacks: no sound", (heard(function() setStacks(3) end)), 0)
n, vol = heard(function() setStacks(5) end)
checkEq("in a fight, 5 stacks: one sound", n, 1)
checkEq("in a fight: at the icon's Volume", vol, 35)
__sim.advance(1.2)
-- spent at 5, the buff back at 1: the game's part comes up with it for a moment (still set from the last 5)
checkEq("in a fight, spent: no sound", (heard(function() setStacks(0) end)), 0)
checkEq("in a fight, the buff back at 1: no sound", (heard(function() setStacks(1); __sim.advance(0.1) end)), 0)
__sim.advance(1.2)
checkEq("in a fight, 5 again: the sound again", (heard(function() setStacks(4); setStacks(5); __sim.advance(0.1) end)), 1)
__sim.setCombat(false); __sim.advance(1.2)
checkEq("the fight over at 5: no second sound for the same 5", (heard(function() setStacks(5) end)), 0)

-- put back
SP.PlaySoundWithVolume = play
setStacks(0)
SP:ReadyReminderResetIcon("maelstrom")
SP:ReadyReminderSetSpell("maelstrom", false)
C_UnitAuras.GetPlayerAuraBySpellID = get
SPCompat.SpellExists, SPCompat.KnowsSpellID = SE, KN
finish()
