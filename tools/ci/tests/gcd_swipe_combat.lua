-- client: forever
-- regime: secrets
-- (Rakii, 11-11) The totem bar's GCD swipe in a fight on WoW: Forever. Its totems have a 1.0 s global
-- cooldown (the game's spell data); out of a fight the swipe reads it, in one the game hides the numbers
-- and the swipe fell back to 1.5 s, so it ran slower than the action bars. In a fight it now takes the
-- cast spell's own global cooldown from its spell data (readable in fights): 1.0 s for a totem, 1.5 s
-- for Totemic Call. Out of a fight: the game's numbers, as before.
local SP = ShamanPower
local W = __sim.W
local SEARING, TOTEMIC_CALL = 3599, 36936
SP:SetupGCDSwipes()
local cd = SP.gcdCooldowns and SP.gcdCooldowns[2]
local btn = SP.totemButtons and SP.totemButtons[2]
if not (cd and btn) then skip("no fire button or no GCD swipe here") end
if btn.compactLayoutOn then skip("Compact lines have no GCD swipe") end

local realGet, realBase = C_Spell.GetSpellCooldown, GetSpellBaseCooldown
local fight, gcdStart, gcdLen = false, 0, 1.0
C_Spell.GetSpellCooldown = function()
	local now = GetTime()
	local on = now < gcdStart + gcdLen
	local st, du = on and gcdStart or 0, on and gcdLen or 0
	if fight then st, du = __sim.secret("start"), __sim.secret("duration") end
	return { startTime = st, duration = du, isEnabled = true, isActive = on, isOnGCD = on, modRate = 1 }
end
GetSpellBaseCooldown = function(id) if id == TOTEMIC_CALL then return 0, 1500 end return 0, 1000 end
local function cast(id, len)
	gcdStart, gcdLen = GetTime(), len
	W.fireEvent("SPELL_UPDATE_COOLDOWN")   -- (the cooldown cache emptied, as in game)
	SP:TriggerGCDSwipe(id)
	local _, ms = cd:GetCooldownTimes()
	return ms / 1000
end

checkEq("out of a fight: a totem's swipe is the game's 1.0 s", cast(SEARING, 1.0), 1.0)
fight = true
checkEq("in a fight (numbers hidden): a totem's swipe is still 1.0 s", cast(SEARING, 1.0), 1.0)
checkEq("in a fight: Totemic Call's swipe is its own 1.5 s", cast(TOTEMIC_CALL, 1.5), 1.5)
GetSpellBaseCooldown = function() return 0, 0 end
checkEq("in a fight, no spell data: 1.5 s, as before", cast(SEARING, 1.0), 1.5)
fight = false

C_Spell.GetSpellCooldown, GetSpellBaseCooldown = realGet, realBase
W.fireEvent("SPELL_UPDATE_COOLDOWN")
cd:Clear()
finish()
