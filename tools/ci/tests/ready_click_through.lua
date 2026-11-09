-- client: both
-- (3.0.9.9) Ready Reminders: Click Through (Off / In Combat / Always), as the Totem Bar's and the
-- Cooldown Bar's (a Discord ask). Off: the icons take the mouse as before. Always: never. In Combat:
-- not during a fight, back after it. Moving the icons: they take it, whatever the setting. It is a
-- third holder of the mouse: the Only When Ready curve's hold still works with it on and off.
local SP = ShamanPower
if not (SP.ReadyReminderSetClickThrough and SP.CreateReadyReminderFrame) then skip("no Ready Reminders here") end
SP:SetReadyRemindersEnabled(true)
local entry = SP.ReadyReminderSpells[1]
local f = SP:CreateReadyReminderFrame(entry)
f.mouseByCurve, f.mouseByFade, f.mouseByThrough = nil, nil, nil
f:EnableMouse(true)

check("Off to start", (ShamanPower_ReadyReminders.clickThrough or "off") == "off")
check("Off: the icon takes the mouse", f:IsMouseEnabled())

SP:ReadyReminderSetClickThrough("always")
check("Always: the icon ignores the mouse", not f:IsMouseEnabled())
local g = SP:CreateReadyReminderFrame(SP.ReadyReminderSpells[2])
check("Always: an icon made after it too", not g:IsMouseEnabled())

SP:ShowAllReadyReminders(); __sim.advance(0.1)
check("moving the icons: they take the mouse", f:IsMouseEnabled())
SP:HideAllReadyReminders(); __sim.advance(0.1)
check("done moving: Always again", not f:IsMouseEnabled())

SP:ReadyReminderSetClickThrough("combat")
check("In Combat, out of a fight: the mouse", f:IsMouseEnabled())
__sim.setCombat(true); __sim.advance(0.1)
check("In Combat, in a fight: no mouse", not f:IsMouseEnabled())
__sim.setCombat(false); __sim.advance(0.1)
check("In Combat, the fight over: the mouse back", f:IsMouseEnabled())

-- with the curve holding it (a cooling icon kept at alpha 0): Click Through on and off leaves it off
f.mouseByCurve = true; f:EnableMouse(false)
SP:ReadyReminderSetClickThrough("always")
SP:ReadyReminderSetClickThrough("off")
check("the curve's hold outlasts Click Through", not f:IsMouseEnabled())
f.mouseByCurve = nil; f:EnableMouse(true)

SP:ReadyReminderSetClickThrough("off")
check("Off again: the mouse", f:IsMouseEnabled())
check("Off is not saved as a value", ShamanPower_ReadyReminders.clickThrough == nil)
SP:UpdateReadyReminders(); __sim.advance(0.2)
finish()
