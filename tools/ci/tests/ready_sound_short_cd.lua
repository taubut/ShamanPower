-- client: both
-- (3.0.9.9) Ready Reminders' Sound When Ready, turned on for the whole page: a spell plays its sound when it is
-- ready, whatever its cooldown. The page's Minimum Cooldown (20 seconds) kept the shocks' 6 seconds quiet; it
-- is gone, as Ready Flash's is, and an old saved value of it does nothing.
local SP = ShamanPower
local A, W = __sim.A, __sim.W
if not (SP.ReadyReminderSetPageOpt and A.cooldowns) then skip("no Ready Reminders here") end
SP:SetReadyRemindersEnabled(true)
local ES = 8042

ShamanPower_ReadyReminders.soundMinCooldown = 20   -- an old saved Minimum Cooldown
SP:ReadyReminderSetSpell("earthshock", true)
SP:ReadyReminderSetIconOpt("earthshock", "soundOnReady", nil)   -- (the page's, not its own)
SP:ReadyReminderSetPageOpt("soundOnReady", true)
check("the page's sound reaches Earth Shock", SP:ReadyReminderIconOpt("earthshock", "soundOnReady") == true)
check("Earth Shock has no sound of its own", SP:ReadyReminderOwnOpt("earthshock", "soundOnReady") == nil)
SP:UpdateReadyReminders(); __sim.advance(0.2)

local plays = 0
local play = SP.PlaySoundWithVolume
SP.PlaySoundWithVolume = function() plays = plays + 1 end
local function cast()
	A.cooldowns["Earth Shock"] = { GetTime(), 6 }
	W.fireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-ES", ES)
	W.fireEvent("SPELL_UPDATE_COOLDOWN")
	SP:UpdateReadyReminders()
end
-- the next 8 seconds: when the sound played (seconds after the cast)
local function watch()
	local at, n0 = nil, plays
	for i = 1, 80 do
		__sim.advance(0.1)
		if i % 10 == 0 then W.fireEvent("SPELL_UPDATE_COOLDOWN") end
		if not at and plays > n0 then at = i / 10 end
	end
	return at
end

cast()
local at = watch()
check("Earth Shock (6-second cooldown) sounds when it is ready", at ~= nil)
check("not while it cools: at about 6 seconds", at ~= nil and at >= 5.5 and at <= 7.5)

SP:ReadyReminderSetPageOpt("soundOnReady", false)
__sim.advance(2)
cast()
check("the page's sound off: none", watch() == nil)

-- put back
SP.PlaySoundWithVolume = play
A.cooldowns["Earth Shock"] = nil
ShamanPower_ReadyReminders.soundMinCooldown = nil
SP:ReadyReminderSetPageOpt("soundOnReady", nil)
SP:UpdateReadyReminders(); __sim.advance(0.2)
finish()
