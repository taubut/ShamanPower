-- client: both
-- What's New for 3.0.9.6 (changes and fixes only, nothing marked for the card): opened on request, the
-- card's 3.0.9.6 part was an empty heading. A version with no new items now shows its changes and fixes
-- there, a row each ("(WoW: Forever)" lines on WoW: Forever's card only). A player updating from the
-- version before still gets no card at login.
local SP = ShamanPower
local notes = SP.PATCH_NOTES

-- at login, from the version before: quiet while the newest version has nothing marked for the card
local newest, before = notes[1], notes[2]
local marked = false
for _, it in ipairs(newest.new or {}) do if it.card then marked = true end end
if not marked then
	SP.opt.setupDone = true
	SP.db.global.lastSeenVersion = before.v
	SP:ShowWhatsNew()
	__sim.advance(0.3)
	check("from " .. before.v .. " at login: no card", __sim.frameWithText("What's new") == nil)
	checkEq("and the new version stamped", SP.db.global.lastSeenVersion, GetAddOnMetadata("ShamanPower", "Version"))
end

-- on request: a newest version with changes and fixes only
table.insert(notes, 1, { v = "9.9.9.9", date = "test", headline = "test",
	changes = { "Totem Coverage (WoW: Forever): in a fight, green." },
	fixes = { "Expiring Alerts: turned off, quiet now.", "No title here" } })
SlashCmdList["SPWHATSNEW"]("")
__sim.advance(0.3)
check("it leads the card", __sim.frameWithText("ShamanPower 9.9.9.9") ~= nil)
check("a fix is a row: its title", __sim.frameWithText("Expiring Alerts") ~= nil)
check("and the rest, capitalized", __sim.frameWithText("Turned off, quiet now.") ~= nil)
check("a line with no title is a row too", __sim.frameWithText("No title here") ~= nil)
if SPCompat.FOREVER then
	check("a WoW: Forever line: titled past its brackets", __sim.frameWithText("Totem Coverage (WoW: Forever)") ~= nil and __sim.frameWithText("In a fight, green.") ~= nil)
else
	check("a WoW: Forever line stays off Anniversary's card", __sim.frameWithText("Totem Coverage (WoW: Forever)") == nil and __sim.frameWithText("In a fight, green.") == nil)
end
local dlg = __sim.frameWithText("What's new")
if dlg and dlg.Hide then dlg:Hide() end
table.remove(notes, 1)
finish()
