-- client: forever
-- regime: secrets
-- (3.0.9.9) Maelstrom Weapon's sound At 5 Stacks: every Ready Reminder's own ready sound (its Sound and Volume),
-- once each time the stacks reach 5. Out of a fight from the count; in a fight (3.0.9.16) counted from the game's
-- Cooldown Manager item. Until 3.0.9.9 the game played it on "Maelstrom Ready!" (408501) with no volume (a Discord
-- report: no sound at 5 stacks); until 3.0.9.16 a part the game shows from 5 stacks was to say when, and in game it
-- never could (a CurseForge report, 11-16: no sound at 5 stacks).
local SP = ShamanPower
local W = __sim.W
local e
for _, x in ipairs(SP.ReadyReminderSpells or {}) do if x.key == "maelstrom" then e = x end end
if not (e and SP.ReadyStacks and SP.ReadyStacksAPI) then skip("no Maelstrom Weapon reminder here") end
check("the reminders' own ready sound is handed over", type(SP.ReadyStacksAPI.readySound) == "function")

-- as ready_stacks.lua: the game's number formatter, the talent known, the buff out of combat
if not C_StringUtil.CreateNumericRuleFormatter then
	C_StringUtil.CreateNumericRuleFormatter = function()
		local f = { rules = {} }
		function f:AddBreakpoint(b) self.rules[#self.rules + 1] = b; table.sort(self.rules, function(x, y) return x.threshold < y.threshold end); return true end
		function f:FormatNumber(n)
			local pick
			for _, b in ipairs(self.rules) do if n >= b.threshold then pick = b end end
			return pick and (pick.format:find("%%d") and pick.format:format(n) or pick.format) or ""
		end
		return f
	end
end
SP.ReadyStacksAPI.Buff.engine = nil
local SE, KN = SPCompat.SpellExists, SPCompat.KnowsSpellID
SPCompat.SpellExists = function(id) if id == 408498 then return true end return SE(id) end
SPCompat.KnowsSpellID = function(id) if id == 408498 then return true end return KN(id) end
e.clientID = nil
W.fireEvent("SPELLS_CHANGED")
local stacks = 0
local get = C_UnitAuras.GetPlayerAuraBySpellID
C_UnitAuras.GetPlayerAuraBySpellID = function(id)
	if id == 408505 then
		if stacks <= 0 then return nil end
		return { applications = stacks, expirationTime = GetTime() + 20, duration = 30, spellId = 408505 }
	end
	return get and get(id)
end
-- the count as the game has it: read out of a fight, and its parts drawn (in a fight too)
local function setStacks(n)
	stacks = n
	__sim.auraApplications(n)
	W.fireEvent("UNIT_AURA", "player", {}); SP:UpdateReadyReminders(); __sim.advance(0.1)
end

local plays = {}
local play = SP.PlaySoundWithVolume
SP.PlaySoundWithVolume = function(_, _, vol) plays[#plays + 1] = vol end
local function heard(fn) local n = #plays; fn(); return #plays - n, plays[#plays] end

ShamanPower_ReadyReminders.enabled = true
SP:ReadyReminderSetSpell("maelstrom", true)
SP:ReadyReminderSetIconOpt("maelstrom", "soundOnReady", true)
SP:ReadyReminderSetIconOpt("maelstrom", "soundVolume", 35)
setStacks(0)

checkEq("3 stacks: no sound", (heard(function() setStacks(3) end)), 0)
checkEq("4 stacks: no sound", (heard(function() setStacks(4) end)), 0)
local n, vol = heard(function() setStacks(5) end)
checkEq("5 stacks: one sound", n, 1)
checkEq("at the icon's Volume", vol, 35)
__sim.advance(1.2)
checkEq("still 5: no second sound", (heard(function() setStacks(5) end)), 0)
setStacks(2); __sim.advance(1.2)
checkEq("spent, back to 5: the sound again", (heard(function() setStacks(5) end)), 1)

-- the sound off in its menu: nothing
SP:ReadyReminderSetIconOpt("maelstrom", "soundOnReady", false)
setStacks(1); __sim.advance(1.2)
checkEq("sound off: none", (heard(function() setStacks(5) end)), 0)
SP:ReadyReminderSetIconOpt("maelstrom", "soundOnReady", true)

-- in a fight: the count is hidden from addons, and the game runs no script of ours inside its aura buttons
-- (3.0.9.16, measured: the old part that listened never played). The game's Cooldown Manager calls its Maelstrom
-- Weapon item when the buff comes on, at each change and when it goes; ShamanPower counts those calls (the owner's
-- idea, as Shield Charges does with the shields). The item and its viewer stand in for Blizzard's here.
local CDM_ID, SHIELD_ID = 200560, 200311
local item = { id = CDM_ID }
function item:GetCooldownID() return self.id end
function item:TriggerAuraAppliedAlert() end
function item:TriggerAuraRemovedAlert() end
function item:OnUnitAuraUpdatedEvent() end
function item:SetAlpha() end
local shield = { id = SHIELD_ID }
for k, v in pairs(item) do if type(v) == "function" then shield[k] = v end end
local viewer = { itemFramePool = { EnumerateActive = function() return pairs({ [item] = true, [shield] = true }) end } }
function viewer:RefreshLayout() end
local CV, BV = C_CooldownViewer, _G.BuffIconCooldownViewer
C_CooldownViewer = { GetCooldownViewerCooldownInfo = function(id)
	if id == CDM_ID then return { spellID = 408498, linkedSpellIDs = { 408505 } } end
	if id == SHIELD_ID then return { spellID = 324 } end
end }
_G.BuffIconCooldownViewer = viewer
local function cdm(what, it)
	it = it or item
	if what == "on" then it:TriggerAuraAppliedAlert() elseif what == "off" then it:TriggerAuraRemovedAlert() else it:OnUnitAuraUpdatedEvent() end
end
setStacks(2); __sim.advance(1.2)   -- (out of a fight the count is read: 2, and a fight counts on from there)
__sim.setCombat(true); __sim.advance(0.2)
checkEq("in a fight, 3 stacks: no sound", (heard(function() setStacks(3); cdm("up") end)), 0)
checkEq("in a fight, 4 stacks: no sound", (heard(function() setStacks(4); cdm("up") end)), 0)
n, vol = heard(function() setStacks(5); cdm("up") end)
checkEq("in a fight, 5 stacks: one sound", n, 1)
checkEq("in a fight: at the icon's Volume", vol, 35)
__sim.advance(1.2)
checkEq("in a fight, a proc at 5: no second sound", (heard(function() cdm("up"); cdm("up") end)), 0)
checkEq("another item's calls (a shield): nothing", (heard(function() for _ = 1, 6 do cdm("up", shield) end end)), 0)
checkEq("in a fight, spent: no sound", (heard(function() setStacks(0); cdm("off") end)), 0)
checkEq("in a fight, the buff back at 1: no sound", (heard(function() setStacks(1); cdm("on") end)), 0)
__sim.advance(1.2)
checkEq("in a fight, 5 again: the sound again", (heard(function() for s = 2, 5 do setStacks(s); cdm("up") end end)), 1)
__sim.setCombat(false); __sim.advance(1.2)
checkEq("the fight over at 5: no second sound for the same 5", (heard(function() setStacks(5) end)), 0)
C_CooldownViewer, _G.BuffIconCooldownViewer = CV, BV

-- put back
SP.PlaySoundWithVolume = play
setStacks(0)
SP:ReadyReminderResetIcon("maelstrom")
SP:ReadyReminderSetSpell("maelstrom", false)
C_UnitAuras.GetPlayerAuraBySpellID = get
SPCompat.SpellExists, SPCompat.KnowsSpellID = SE, KN
finish()
