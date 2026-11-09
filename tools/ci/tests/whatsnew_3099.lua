-- client: both
-- What's New for 3.0.9.9: a player updating from 3.0.9.8 gets the card at login, with 3.0.9.9's card
-- items: Racials, Click Through, Shield Sound Volume and the loadouts' Drop Order on both games; the Call flyout and
-- the Minimap Totems page on WoW: Forever's card only (Anniversary has neither).
local SP = ShamanPower
local notes = SP.PATCH_NOTES
local v99
for _, v in ipairs(notes) do if v.v == "3.0.9.9" then v99 = v end end
check("3.0.9.9 is in the Patch Notes", v99 ~= nil)
local function num(v)
	local a, b, c, d = (v or ""):match("^(%d+)%.(%d+)%.?(%d*)%.?(%d*)")
	if not a then return 0 end
	return ((tonumber(a) * 1000 + tonumber(b)) * 1000 + (tonumber(c) or 0)) * 1000 + (tonumber(d) or 0)
end
check("the TOC is 3.0.9.9 or newer", num(GetAddOnMetadata("ShamanPower", "Version")) >= num("3.0.9.9"))
SP.opt.setupDone = true
SP.db.global.lastSeenVersion = "3.0.9.8"
SP:ShowWhatsNew()
__sim.advance(0.3)
check("from 3.0.9.8 at login: the card", __sim.frameWithText("What's new") ~= nil)
-- (headed by the running version: 3.0.9.9 itself, or a newer one with 3.0.9.9's items under Also New In 3.0)
check("headed by the running version", __sim.frameWithText("ShamanPower " .. GetAddOnMetadata("ShamanPower", "Version")) ~= nil)
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
checkEq("and the running version stamped as seen", SP.db.global.lastSeenVersion, GetAddOnMetadata("ShamanPower", "Version"))
local dlg = __sim.frameWithText("What's new")
if dlg and dlg.Hide then dlg:Hide() end
finish()
