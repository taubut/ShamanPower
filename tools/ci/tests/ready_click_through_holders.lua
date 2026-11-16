-- client: both
-- (3.0.9.14) A CurseForge report: Ready Reminders set to Click Through, clicks did nothing, but the camera
-- still would not turn with the mouse over them. Measured in game (GetMouseFoci): ShamanPowerReadyRow1 took
-- clicks and hovering. A row's (and the grid's) invisible holder under its first icon was given an OnMouseUp
-- script (to save its place after a drag), and the game switches a frame's mouse on with that script. The
-- holders never take the mouse now: drags start on the icons, and Unlock UI saves through the script itself.
-- (The sim switches the mouse on for a mouse-button script too, as the game does.)
local SP = ShamanPower
if not (SP.ReadyReminderSetClickThrough and SP.SetReadyRemindersEnabled) then skip("no Ready Reminders here") end
local sv = ShamanPower_ReadyReminders
local was = { rows = sv.rows, arrange = sv.arrange, through = sv.clickThrough }
SP:SetReadyRemindersEnabled(true)
SP:ReadyReminderSetSpell("earthshock", true)
SP:ReadyReminderSetShow("earthshock", "always_bright")

for _, arrange in ipairs({ "rows", "grid" }) do
	sv.arrange = arrange
	if arrange == "rows" then sv.rows = { { spells = { "earthshock" } } } end
	SP:ReadyReminderSetClickThrough("always")
	SP:UpdateAllReadyReminderAppearance(); SP:UpdateReadyReminders(); __sim.advance(0.3)
	local holder = (arrange == "rows") and _G.ShamanPowerReadyRow1 or _G.ShamanPowerReadyGrid
	check(arrange .. ": its holder is made", holder ~= nil)
	if holder then
		check(arrange .. ": Click Through on, the holder takes no mouse", not holder:IsMouseEnabled())
		check(arrange .. ": its save-after-drag script is still there (Unlock UI runs it)", holder:GetScript("OnMouseUp") ~= nil)
	end
	local f = SP.readyReminderFrames.earthshock
	check(arrange .. ": Click Through on, the icon takes no mouse", f and not f:IsMouseEnabled())
	-- Unlock: the icons take the mouse to be dragged; the holder still never does
	SP:ShowAllReadyReminders(); __sim.advance(0.2)
	check(arrange .. ": unlocked, the icon takes the mouse (dragging)", f and f:IsMouseEnabled())
	if holder then check(arrange .. ": unlocked, the holder still takes none", not holder:IsMouseEnabled()) end
	SP:HideAllReadyReminders(); __sim.advance(0.2)
end

SP:ReadyReminderSetClickThrough(was.through)
sv.rows, sv.arrange = was.rows, was.arrange
SP:ReadyReminderSetShow("earthshock", nil)
SP:ReadyReminderSetSpell("earthshock", false)
SP:UpdateAllReadyReminderAppearance()
finish()
