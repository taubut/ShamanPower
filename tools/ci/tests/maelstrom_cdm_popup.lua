-- client: forever
-- (3.0.9.16) The owner's rule, 11-16: Maelstrom Weapon goes into ShamanPower's Cooldown Manager layout ONLY when the
-- player turns on Sound for its Ready Reminder (the stacks draw without it; its 5-stack sound in a fight counts the
-- Cooldown Manager's item), through a popup like Shield Charges' setup; and once, on the first login after the update,
-- when Sound is already on (the fix for that sound). Nothing else asks: the reminder on or off, dragged, a fight.
local SP = ShamanPower
local W = __sim.W
local e
for _, x in ipairs(SP.ReadyReminderSpells or {}) do if x.key == "maelstrom" then e = x end end
if not (e and SP.CdmMaelstromAsk and SP.CdmMaelstromFirstLogin and SP.db and SP.db.char) then skip("no Maelstrom Weapon reminder or Cooldown Manager popup here") end
local c = SP.db.char
local keepChecked = c.cdmMaelstromChecked
c.cdmMaelstromChecked = true   -- (a first-login check still waiting from the load stays quiet)
local SE, KN = SPCompat.SpellExists, SPCompat.KnowsSpellID
SPCompat.SpellExists = function(id) if id == 408498 then return true end return SE(id) end
SPCompat.KnowsSpellID = function(id) if id == 408498 then return true end return KN(id) end
e.clientID = nil
W.fireEvent("SPELLS_CHANGED")
-- the game's catalog has Maelstrom Weapon (200560); no ShamanPower layout saved yet; a spec
local CV, SI = C_CooldownViewer, C_SpecializationInfo
C_CooldownViewer = {
	GetCooldownViewerCooldownInfo = function(id) if id == 200560 then return { spellID = 408498, linkedSpellIDs = { 408505 } } end end,
	GetLayoutData = function() return "" end,
	SetLayoutData = function() end,
}
C_SpecializationInfo = { GetSpecialization = function() return 2 end }
local asked = 0
local dlg = SP.ShowSPDialog
SP.ShowSPDialog = function(self, d)
	if type(d) == "table" and d.key == "cdmMaelstrom" then asked = asked + 1 return end
	return dlg(self, d)
end
local function asks(fn) local n = asked; fn(); return asked - n end

ShamanPower_ReadyReminders.enabled = true
SP:ReadyReminderSetIconOpt("maelstrom", "soundOnReady", false)
checkEq("the reminder turned on: no popup", asks(function() SP:ReadyReminderSetSpell("maelstrom", true) end), 0)
checkEq("Sound turned on: the popup", asks(function() SP:ReadyReminderSetIconOpt("maelstrom", "soundOnReady", true) end), 1)
checkEq("Sound turned off: none", asks(function() SP:ReadyReminderSetIconOpt("maelstrom", "soundOnReady", false) end), 0)
checkEq("the reminder off, Sound turned on: none", asks(function()
	SP:ReadyReminderSetSpell("maelstrom", false); SP:ReadyReminderSetIconOpt("maelstrom", "soundOnReady", true)
end), 0)
checkEq("the reminder turned back on with Sound on: none", asks(function() SP:ReadyReminderSetSpell("maelstrom", true) end), 0)
__sim.setCombat(true)
checkEq("Sound turned on in a fight: none", asks(function()
	SP:ReadyReminderSetIconOpt("maelstrom", "soundOnReady", false); SP:ReadyReminderSetIconOpt("maelstrom", "soundOnReady", true)
end), 0)
__sim.setCombat(false)

-- the first login after the update: once per character, only with Sound on
c.cdmMaelstromChecked = nil
checkEq("first login, Sound on: the popup", asks(function() SP.CdmMaelstromFirstLogin() end), 1)
check("checked for this character", c.cdmMaelstromChecked == true)
checkEq("a later login: none", asks(function() SP.CdmMaelstromFirstLogin() end), 0)
SP:ReadyReminderSetIconOpt("maelstrom", "soundOnReady", false)
c.cdmMaelstromChecked = nil
checkEq("first login, Sound off: none", asks(function() SP.CdmMaelstromFirstLogin() end), 0)
check("and never asked at a later login", c.cdmMaelstromChecked == true)

-- put back
SP.ShowSPDialog = dlg
C_CooldownViewer, C_SpecializationInfo = CV, SI
c.cdmMaelstromChecked = keepChecked
SP:ReadyReminderResetIcon("maelstrom")
SP:ReadyReminderSetSpell("maelstrom", false)
SPCompat.SpellExists, SPCompat.KnowsSpellID = SE, KN
finish()
