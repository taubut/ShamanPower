-- client: both
-- Cooldown Bar keys for every spell (3.0.9.7): Shamanistic Rage, Elemental / Lightning Mastery, Rage of the
-- Farseer and WoW: Forever's Totemic Call had no key action, so Keybind Mode passed them over (the owner's
-- report: Totemic Call on WoW: Forever). Each has its own now. Its key presses the button of its spell, and
-- still does after the bar's order is turned around (the buttons are named by position).
local SP = ShamanPower
local o = SP.opt
local NEW = { SHAMANPOWER_CD_SHAMANISTIC_RAGE = 8, SHAMANPOWER_CD_ELEMENTAL_MASTERY = 9,
	SHAMANPOWER_CD_RAGE_OF_THE_FARSEER = 10, SHAMANPOWER_CD_TOTEMIC_PROJECTION = 11 }
local KEY = { [8] = "SHIFT-1", [9] = "SHIFT-2", [10] = "SHIFT-3", [11] = "SHIFT-4" }

for action, t in pairs(NEW) do
	checkEq(action .. ": a key action for type " .. t, SP.CooldownBarKeybinds[action], t)
	check(action .. ": named in the Key Bindings window", type(_G["BINDING_NAME_" .. action]) == "string")
end

local savedOrder = o.cooldownBarOrder and { unpack(o.cooldownBarOrder) }
local savedShow = {}
for _, s in ipairs(SP.TrackedCooldowns) do savedShow[s[4]] = o[s[4]] end
for _, s in ipairs(SP.TrackedCooldowns) do if s[5] >= 8 then o[s[4]] = true end end   -- every one on the bar it can be

local pointed = {}
local realKey, realOverride = GetBindingKey, SetOverrideBindingClick
GetBindingKey = function(action) local t = NEW[action] return t and KEY[t] or nil end
SetOverrideBindingClick = function(_, _, key, name) pointed[key] = name end

local function run(label)
	SP:RecreateCooldownBar()
	wipe(pointed)
	SP:SetupKeybindings()
	local seen = 0
	for t = 8, 11 do
		local btn = SP:GetCooldownButtonByCooldownType(t)
		if btn then
			seen = seen + 1
			checkEq(label .. "type " .. t .. ": its key presses its button", pointed[KEY[t]], btn:GetName())
		end
	end
	return seen
end

local seen = run("")
check("at least one of the four on the bar here", seen > 0)
-- the order turned around: the buttons swap names, each key stays with its spell
local order = SP:GetCooldownBarOrder()
local rev = {}
for i = #order, 1, -1 do rev[#rev + 1] = order[i] end
o.cooldownBarOrder = rev
run("bar reversed: ")

GetBindingKey, SetOverrideBindingClick = realKey, realOverride
o.cooldownBarOrder = savedOrder
for k, v in pairs(savedShow) do o[k] = v end
SP:RecreateCooldownBar()
SP:SetupKeybindings()
finish()
