-- client: both
-- What's New for 3.0.9.9: a player updating from 3.0.9.8 gets the card at login, led by 3.0.9.9 and its card
-- items: Racials, Click Through, Shield Sound Volume and the loadouts' Drop Order on both games; the Call flyout and
-- the Minimap Totems page on WoW: Forever's card only (Anniversary has neither).
local SP = ShamanPower
local notes = SP.PATCH_NOTES
checkEq("3.0.9.9 is the newest", notes[1].v, "3.0.9.9")
checkEq("the TOC says 3.0.9.9", GetAddOnMetadata("ShamanPower", "Version"), "3.0.9.9")
SP.opt.setupDone = true
SP.db.global.lastSeenVersion = "3.0.9.8"
SP:ShowWhatsNew()
__sim.advance(0.3)
check("from 3.0.9.8 at login: the card", __sim.frameWithText("What's new") ~= nil)
check("led by 3.0.9.9", __sim.frameWithText("ShamanPower 3.0.9.9") ~= nil)
for _, h in ipairs({ "Racials in Ready Reminders", "Click Through for Ready Reminders and Totem Coverage",
	"Shield Sound Volume", "Loadouts Keep Their Drop Order" }) do
	check(h, __sim.frameWithText(h) ~= nil)
end
local call, mm = __sim.frameWithText("Pick a Call from Drop All") ~= nil, __sim.frameWithText("Minimap Totems Page") ~= nil
if SPCompat.FOREVER then
	check("WoW: Forever: the Call flyout and the Minimap Totems page too", call and mm)
else
	check("Anniversary: neither the Call flyout nor the Minimap Totems page", not call and not mm)
end
checkEq("and 3.0.9.9 stamped as seen", SP.db.global.lastSeenVersion, "3.0.9.9")
local dlg = __sim.frameWithText("What's new")
if dlg and dlg.Hide then dlg:Hide() end
finish()
