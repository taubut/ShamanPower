-- client: both
-- Ready Reminders: a Proc Glow started while the icon breathes (Glow + Pulse, mid-scale) grew in the
-- game until it covered the whole screen (a player's ticket, 11-07: Glow Only In Combat, so the glow
-- came at the pull with the pulse already going; reproduced by the owner, gone with Glow alone). The
-- pulse now holds while the glow starts and plays on after it: never a glow attached mid-pulse. The
-- When Out of Mana glow starts on the same icon, so it holds the pulse too.
local SP = ShamanPower
local W = __sim.W
SP:ReadyReminderSetSpell("earthshock", true)
SP:ReadyReminderSetShow("earthshock", "always_bright")
SP:ReadyReminderSetIconOpt("earthshock", "readyEffect", "both")
SP:ReadyReminderSetIconOpt("earthshock", "glowShape", "proc")
SP:ReadyReminderSetIconOpt("earthshock", "glowCombatOnly", true)
SP:UpdateReadyReminders(); __sim.advance(0.2)
local f = SP.readyReminderFrames and SP.readyReminderFrames.earthshock
if not (f and f:IsShown()) then skip("Earth Shock's icon not on screen here") end

-- every Proc Glow start on this icon: was the icon mid-pulse then?
local realStart = SP.ProcGlow_Start
local starts, midPulse = 0, 0
SP.ProcGlow_Start = function(r, options)
	if r == f or r == f.oomFx then
		starts = starts + 1
		if f.pulseAnim:IsPlaying() then midPulse = midPulse + 1 end
	end
	return realStart(r, options)
end

check("out of a fight: the icon breathes", f.pulseAnim:IsPlaying())
check("out of a fight: no glow (Glow Only In Combat)", not f.glowShown)
__sim.advance(0.3)   -- (well into the pulse)
__sim.setCombat(true); __sim.advance(0.2)
check("the pull: the glow starts", f.glowShown and starts >= 1)
checkEq("never on an icon mid-pulse", midPulse, 0)
check("and the icon breathes on", f.pulseAnim:IsPlaying())

-- When Out of Mana's own Proc Glow, in the fight, on the same breathing icon
local realUsable = C_Spell.IsSpellUsable
local noMana = true
C_Spell.IsSpellUsable = function() return not noMana, noMana end
SP:ReadyReminderSetIconOpt("earthshock", "oomEffect", "glow")
SP:ReadyReminderSetIconOpt("earthshock", "oomGlowShape", "proc")
starts, midPulse = 0, 0
SP:UpdateReadyReminders()
W.fireEvent("SPELL_UPDATE_USABLE"); __sim.advance(0.1)
if starts > 0 then
	checkEq("out of mana: its glow never on an icon mid-pulse", midPulse, 0)
	check("and the icon breathes on", f.pulseAnim:IsPlaying())
end

C_Spell.IsSpellUsable = realUsable
SP.ProcGlow_Start = realStart
__sim.setCombat(false)
finish()
