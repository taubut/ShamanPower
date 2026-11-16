-- client: both
-- (3.0.9.14) Snugs' ask on Discord (11-13): a reminder only for some specs. Its menu's Show For ticks the specs
-- it is for (nothing ticked: every spec). Played in another spec it hides on screen by itself, and stays on in
-- the settings; a respec into a ticked spec brings it back; while the spec can't be told, it shows.
local SP = ShamanPower
local W = __sim.W
if not (SP.ReadyReminderSetIconOpt and SP.ReadyReminderSpecOK) then skip("no Ready Reminders here") end
SP:SetReadyRemindersEnabled(true)
local entry
for _, e in ipairs(SP.ReadyReminderSpells) do if e.key == "earthshock" then entry = e end end
if not (entry and SP.ReadyReminderUsable(entry) and SP.ReadyReminderKnown(entry)) then skip("Earth Shock not known here") end
local keepIdx = SP.ShareSpecIndex
local spec = 2   -- (SP.ShareSpecIndex: 1 Restoration, 2 Enhancement, 3 Elemental, 0 can't tell)
SP.ShareSpecIndex = function() return spec end
local function respec(n)
	spec = n
	W.fireEvent("PLAYER_TALENT_UPDATE")
	SP:UpdateReadyReminders(); __sim.advance(0.2); SP:UpdateReadyReminders()
end
SP:ReadyReminderSetSpell("earthshock", true)
SP:ReadyReminderSetShow("earthshock", "always_bright")   -- (on screen whatever its cooldown)
respec(2)
local f = SP.readyReminderFrames.earthshock
check("nothing ticked: every spec, on screen", f and f:IsShown())
check("nothing ticked: its spec check passes", SP.ReadyReminderSpecOK(entry))

-- ticked for Elemental only, played as Enhancement: hidden on screen, still on in the settings
SP:ReadyReminderSetIconOpt("earthshock", "specElemental", true)
respec(2)
check("Elemental only, played as Enhancement: hidden", not f:IsShown())
check("still on in the settings", SP.ReadyReminderOn(entry) == true)
-- a respec into Elemental brings it back
respec(3)
check("respec into Elemental: back on screen", f:IsShown())
-- two specs ticked
SP:ReadyReminderSetIconOpt("earthshock", "specEnhancement", true)
respec(2)
check("Elemental + Enhancement, played as Enhancement: on screen", f:IsShown())
respec(1)
check("played as Restoration: hidden", not f:IsShown())
-- the spec can't be told: it shows
respec(0)
check("the spec can't be told: on screen", f:IsShown())
-- nothing ticked again
SP:ReadyReminderSetIconOpt("earthshock", "specElemental", nil)
SP:ReadyReminderSetIconOpt("earthshock", "specEnhancement", nil)
respec(1)
check("nothing ticked: on screen in any spec", f:IsShown())

SP.ShareSpecIndex = keepIdx
SP:ReadyReminderSetShow("earthshock", nil)
SP:ReadyReminderSetSpell("earthshock", false)
W.fireEvent("PLAYER_TALENT_UPDATE")
finish()
