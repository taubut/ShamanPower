-- client: both
-- (3.0.9.17) The owner, 11-17: right-clicking the Maelstrom Weapon reminder out of a fight opened the Ready Reminders
-- settings. "THAT SHOULD NEVER BE A THING outside of the unlock ui screen". A Ready Reminder icon and a Reactive Totems
-- alert open their settings on a right-click only while they are being placed (Move the Icons / Show All (Position),
-- Unlock UI); any other time a right-click does nothing.
local SP = ShamanPower
local W = __sim.W

-- every way the settings could open, counted
local opened = 0
local realMenu, realOpen = SP.ReadyReminderOpenIconMenu, ShamanPowerConfig and ShamanPowerConfig.Open
SP.ReadyReminderOpenIconMenu = function() opened = opened + 1 end
if ShamanPowerConfig then ShamanPowerConfig.Open = function() opened = opened + 1 end end
local function rightClick(f) local fn = f:GetScript("OnClick") if fn then fn(f, "RightButton") end end

-- a Ready Reminder icon (the first on the list)
local entry = SP.ReadyReminderSpells and SP.ReadyReminderSpells[1]
if entry and SP.CreateReadyReminderFrame then
	local f = SP:CreateReadyReminderFrame(entry)
	opened = 0
	rightClick(f)
	checkEq("Ready Reminder: a right-click in play opens nothing", opened, 0)
	SP:ShowAllReadyReminders()
	rightClick(f)
	checkEq("Ready Reminder: while Move the Icons is on it opens its settings", opened, 1)
	SP:HideAllReadyReminders()
	opened = 0
	rightClick(f)
	checkEq("Ready Reminder: Move the Icons off again: nothing", opened, 0)
	if SP.SetMasterUnlock then
		SP:SetMasterUnlock(true)
		rightClick(f)
		check("Ready Reminder: in Unlock UI it opens its settings", opened == 1)
		SP:SetMasterUnlock(false)
	end
end

-- a Reactive Totems alert
if SP.CreateReactiveTotemFrame and SP.ReactiveTotems then
	local id = next(SP.ReactiveTotems)
	local f = SP.reactiveFrames and SP.reactiveFrames[id] or SP:CreateReactiveTotemFrame(id)
	opened = 0
	rightClick(f)
	checkEq("Reactive Totems: a right-click in play opens nothing", opened, 0)
	SP.reactivePositioningMode = true
	rightClick(f)
	checkEq("Reactive Totems: while its alerts are placed it opens its settings", opened, 1)
	SP.reactivePositioningMode = nil
	opened = 0
	rightClick(f)
	checkEq("Reactive Totems: placing over: nothing", opened, 0)
end

SP.ReadyReminderOpenIconMenu = realMenu
if ShamanPowerConfig then ShamanPowerConfig.Open = realOpen end
finish()
