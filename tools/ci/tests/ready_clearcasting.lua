-- client: both
-- (3.0.9.14) A Discord ask: Clearcasting (16246, from the Elemental talent Elemental Focus 16164) as a Ready
-- Reminder that shows while the buff is on you. WoW: Forever only. Out of a fight it shows and hides with the
-- buff; in a fight the game draws it (an AuraContainer slot on the buff), so it stays on screen; its Sound plays
-- when it comes; Only In Combat makes its game parts out of combat; Unlock UI shows its look.
local SP = ShamanPower
local W = __sim.W
local e
for _, x in ipairs(SP.ReadyReminderSpells or {}) do if x.key == "clearcasting" then e = x end end
check("Clearcasting is in the catalog", e ~= nil and e.proc ~= nil)
if not SPCompat.FOREVER then
	check("Anniversary: not usable (WoW: Forever only)", not SP.ReadyReminderUsable(e))
	finish()
end
check("Forever: its module loaded", SP.ReadyProcs ~= nil)
check("usable on Forever", SP.ReadyReminderUsable(e))

-- the talent known (the sim has no talents), the buff as the game would answer out of combat
local KN = SPCompat.KnowsSpellID
SPCompat.KnowsSpellID = function(id) if id == 16164 then return true end return KN(id) end
W.fireEvent("SPELLS_CHANGED")
check("learned with Elemental Focus", SP.ReadyReminderKnown(e))
local up = false
local get = C_UnitAuras.GetPlayerAuraBySpellID
C_UnitAuras.GetPlayerAuraBySpellID = function(id)
	if id == 16246 then return up and { spellId = 16246, applications = 0, expirationTime = GetTime() + 15, duration = 15 } or nil end
	return get and get(id)
end
local plays = 0
local play = SP.PlaySoundWithVolume
SP.PlaySoundWithVolume = function() plays = plays + 1 end
local function pass() W.fireEvent("UNIT_AURA", "player", {}); SP:UpdateReadyReminders(); __sim.advance(0.3) end

SP:SetReadyRemindersEnabled(true)
SP:ReadyReminderSetSpell("clearcasting", true)
SP:ReadyReminderSetIconOpt("clearcasting", "soundOnReady", true)
pass()
local f = SP.readyReminderFrames.clearcasting
check("its reminder frame is made", f ~= nil)
check("no buff, out of a fight: hidden", f and not f:IsShown())
check("the game's parts built", SP.ReadyProcs.Diag(f):find("built=true", 1, true) ~= nil, SP.ReadyProcs.Diag(f))
check("its own cooldown icon steps aside (the buff's look draws it)", not f.icon:IsShown() and not f.cooldown:IsShown())

local n = plays
up = true; pass()
check("the buff on you: shown", f:IsShown())
checkEq("its Sound when it comes", plays - n, 1)
pass()
checkEq("still on: no second sound", plays - n, 1)
up = false; pass()
check("gone: hidden", not f:IsShown())

-- in a fight: on screen, the game draws the buff while it is on you
__sim.setCombat(true); pass()
check("in a fight: on screen (the game decides what is drawn)", f:IsShown())
check("in a fight: the mouse goes through it", not f:IsMouseEnabled())
__sim.setCombat(false); pass()
check("after the fight, no buff: hidden again", not f:IsShown())

-- Only In Combat: hidden out of a fight, its game parts made already
SP:ReadyReminderSetIconOpt("clearcasting", "onlyInCombat", true)
up = true; pass()
check("Only In Combat, out of a fight: hidden even with the buff", not f:IsShown())
check("Only In Combat: its game parts are there for the first fight", SP.ReadyProcs.Diag(f):find("built=true", 1, true) ~= nil)
SP:ReadyReminderSetIconOpt("clearcasting", "onlyInCombat", nil)
up = false; pass()

-- Unlock UI: its look, as if the buff were on you
SP:ShowAllReadyReminders(); __sim.advance(0.2)
check("unlocked: shown to be placed", f:IsShown())
SP:HideAllReadyReminders(); __sim.advance(0.2)
pass()
check("locked again, no buff: hidden", not f:IsShown())

SP.PlaySoundWithVolume = play
C_UnitAuras.GetPlayerAuraBySpellID = get
SPCompat.KnowsSpellID = KN
SP:ReadyReminderResetIcon("clearcasting")
SP:ReadyReminderSetSpell("clearcasting", false)
W.fireEvent("SPELLS_CHANGED")
finish()
