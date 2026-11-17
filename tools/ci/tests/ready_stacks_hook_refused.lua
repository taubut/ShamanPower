-- client: forever
-- regime: secrets
-- (3.0.9.14) A CurseForge report: "Button:HookScript(): Cannot assign script handler for 'onshow' (blocked by
-- secret aspects)" from ShamanPower_ReadyStacks.lua, Maelstrom Weapon's reminder. The At 5 Stacks sound in a
-- fight hooked OnShow on the game's aura button, and the game refuses that. (3.0.9.16) The game also runs no script
-- of ours on any frame inside its button, so nothing of ShamanPower's listens there any more: the sound in a fight
-- is counted from the game's Cooldown Manager item. With every hook on the button and inside it refused: no error,
-- the reminder still draws, the sound plays in a fight and out of one.
local SP = ShamanPower
local W = __sim.W
local e
for _, x in ipairs(SP.ReadyReminderSpells or {}) do if x.key == "maelstrom" then e = x end end
if not (e and SP.ReadyStacks and SP.ReadyStacksAPI and W.foreverClasses) then skip("no Maelstrom Weapon reminder here") end

-- as ready_stacks_sound.lua: the game's number formatter, the talent known, the buff out of combat
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
local function setStacks(n)
	stacks = n
	__sim.auraApplications(n)
	W.fireEvent("UNIT_AURA", "player", {}); SP:UpdateReadyReminders(); __sim.advance(0.1)
end
local plays = {}
local play = SP.PlaySoundWithVolume
SP.PlaySoundWithVolume = function(_, _, vol) plays[#plays + 1] = vol end
local function heard(fn) local n = #plays; fn(); return #plays - n end

-- every error the addon hands to the error handler (BugGrabber's popup in game)
local errs = {}
local geh = geterrorhandler
geterrorhandler = function() return function(err) errs[#errs + 1] = tostring(err) end end
local REFUSED = "Button:HookScript(): Cannot assign script handler for 'onshow' (blocked by secret aspects)"

-- the game refuses a hook on its own aura button (the report), and on every frame of ours inside it
local AB = W.foreverClasses.AuraButton.methods
local abHook = rawget(AB, "HookScript")
AB.HookScript = function() error(REFUSED, 2) end
local CF = CreateFrame
local hooksInside = 0
CreateFrame = function(kind, name, parent, ...)
	local fr = CF(kind, name, parent, ...)
	if parent and parent.GetObjectType and parent:GetObjectType() == "AuraButton" then
		fr.HookScript = function() hooksInside = hooksInside + 1; error(REFUSED, 2) end
	end
	return fr
end
-- the game's Cooldown Manager item for Maelstrom Weapon (stands in for Blizzard's)
local item = { id = 200560 }
function item:GetCooldownID() return self.id end
function item:TriggerAuraAppliedAlert() end
function item:TriggerAuraRemovedAlert() end
function item:OnUnitAuraUpdatedEvent() end
function item:SetAlpha() end
local viewer = { itemFramePool = { EnumerateActive = function() return pairs({ [item] = true }) end } }
function viewer:RefreshLayout() end
local CV, BV = C_CooldownViewer, _G.BuffIconCooldownViewer
C_CooldownViewer = { GetCooldownViewerCooldownInfo = function(id) if id == 200560 then return { spellID = 408498 } end end }
_G.BuffIconCooldownViewer = viewer

ShamanPower_ReadyReminders.enabled = true
SP:ReadyReminderSetSpell("maelstrom", true)
SP:ReadyReminderSetIconOpt("maelstrom", "soundOnReady", true)
SP:ReadyReminderSetIconOpt("maelstrom", "stackShow", "five")      -- (the player's: Only At 5 Stacks,
SP:ReadyReminderSetIconOpt("maelstrom", "readyEffect", "both")    --  Glow + Pulse)
setStacks(0)
setStacks(3)
local f = SP.readyReminderFrames.maelstrom
checkEq("every hook refused: no error", #errs, 0, errs[1])
checkEq("no hook tried inside the game's button", hooksInside, 0)
check("the reminder's parts built", f and SP.ReadyStacks.Diag(f):find("failed=false", 1, true) ~= nil, f and SP.ReadyStacks.Diag(f))
setStacks(1); __sim.advance(1.2)
checkEq("out of a fight, 5 stacks: the sound", (heard(function() setStacks(5) end)), 1)
setStacks(2); __sim.advance(1.2)
__sim.setCombat(true); __sim.advance(0.2)
checkEq("in a fight, 3 stacks: no sound", (heard(function() setStacks(3); item:OnUnitAuraUpdatedEvent() end)), 0)
checkEq("in a fight, 5 stacks: the sound", (heard(function()
	setStacks(4); item:OnUnitAuraUpdatedEvent(); setStacks(5); item:OnUnitAuraUpdatedEvent()
end)), 1)
__sim.advance(1.2)
checkEq("in a fight, spent: no sound", (heard(function() setStacks(0); item:TriggerAuraRemovedAlert() end)), 0)
checkEq("in a fight, the buff back at 1: no sound", (heard(function() setStacks(1); item:TriggerAuraAppliedAlert() end)), 0)
__sim.setCombat(false); __sim.advance(1.2)
checkEq("still no error after the fight", #errs, 0, errs[1])

-- put back
C_CooldownViewer, _G.BuffIconCooldownViewer = CV, BV
CreateFrame = CF
AB.HookScript = abHook
geterrorhandler = geh
SP.PlaySoundWithVolume = play
setStacks(0)
SP:ReadyReminderResetIcon("maelstrom")
SP:ReadyReminderSetSpell("maelstrom", false)
C_UnitAuras.GetPlayerAuraBySpellID = get
SPCompat.SpellExists, SPCompat.KnowsSpellID = SE, KN
finish()
