-- client: both
-- What's New for 3.0.9.4: versions read with all four parts (3.0.9.3 -> 3.0.9.4 was "3.0.9" both, so a
-- player updating within 3.0.9.x got no card), the card on WoW: Forever only (the owner: not on
-- Anniversary), and the Patreon strip under the Discord strip. Opened on request it always leads
-- with the newest version, on both games (3.0.9.3 had no card items and the card opened as 3.0.9.2).
SlashCmdList["SPWHATSNEW"]("3.0.9.3")
__sim.advance(0.3)
local strip = __sim.frameWithText("Every totem counts: support ShamanPower on Patreon")
if SPCompat.FOREVER then
	check("the 3.0.9.4 card opens for a player from 3.0.9.3", __sim.frameWithText("Out of Range in Every Fight") ~= nil)
	check("Supporters is on it", __sim.frameWithText("Supporters") ~= nil)
	check("the Patreon strip is on it", strip ~= nil)
else
	check("no 3.0.9.4 card on Anniversary", __sim.frameWithText("Supporters") == nil and strip == nil)
	ShamanPowerConfig:Open({ "settings", "settings_patchnotes" })
	__sim.advance(0.3)
	check("Anniversary's Patch Notes still list Supporters", __sim.frameWithText("Supporters") ~= nil)
end
local dlg = __sim.frameWithText("What's new")
if dlg and dlg.Hide then dlg:Hide() end
SlashCmdList["SPWHATSNEW"]("")
__sim.advance(0.3)
local newest = ShamanPower.PATCH_NOTES and ShamanPower.PATCH_NOTES[1] and ShamanPower.PATCH_NOTES[1].v   -- (3.0.9.5 since then)
check("opened on request, the card leads with the newest version", newest ~= nil and __sim.frameWithText("ShamanPower " .. newest) ~= nil)
finish()
