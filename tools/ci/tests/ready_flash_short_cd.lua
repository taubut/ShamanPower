-- client: both
-- (3.0.9.9) Ready Flash: a spell turned on flashes when it is ready, whatever its cooldown.
-- The tab's Minimum Cooldown (10 seconds by default) kept the shocks' 6 seconds from ever
-- flashing (a Discord report); it is gone, and an old saved value of it does nothing.
local SP = ShamanPower
local A, W = __sim.A, __sim.W
if not (SP.ReadyReminderSetIconOpt and A.cooldowns) then skip("no Ready Reminders here") end
SP:SetReadyRemindersEnabled(true)
local ES = 8042
local entry
for _, e in ipairs(SP.ReadyReminderSpells) do if e.key == "earthshock" then entry = e end end
check("Earth Shock in the list", entry ~= nil)

ShamanPower_ReadyReminders.flashMin = 10   -- an old saved Minimum Cooldown
SP:ReadyReminderSetSpell("earthshock", true)
SP:ReadyReminderSetIconOpt("earthshock", "flash", true)
SP:UpdateReadyReminders(); __sim.advance(0.2)

local function flashing()
	local f = _G.ShamanPowerReadyFlash
	return f ~= nil and f.spPlaying == entry
end
local function cast()
	A.cooldowns["Earth Shock"] = { GetTime(), 6 }
	W.fireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-ES", ES)
	W.fireEvent("SPELL_UPDATE_COOLDOWN")
	SP:UpdateReadyReminders()
end
-- the next 8 seconds: did it flash, and when (seconds after the cast)
local function watch()
	local at
	for i = 1, 80 do
		__sim.advance(0.1)
		if i % 10 == 0 then W.fireEvent("SPELL_UPDATE_COOLDOWN") end
		if not at and flashing() then at = i / 10 end
	end
	return at
end

cast()
local at = watch()
check("Earth Shock (6-second cooldown) flashes when it is ready", at ~= nil)
check("not while it cools: at about 6 seconds", at ~= nil and at >= 5.5 and at <= 7.5)

-- off in Ready Flash: no flash
SP:ReadyReminderSetIconOpt("earthshock", "flash", nil)
__sim.advance(2)
cast()
check("turned off in Ready Flash: no flash", watch() == nil)

-- put back
A.cooldowns["Earth Shock"] = nil
ShamanPower_ReadyReminders.flashMin = nil
SP:UpdateReadyReminders(); __sim.advance(0.2)
finish()
