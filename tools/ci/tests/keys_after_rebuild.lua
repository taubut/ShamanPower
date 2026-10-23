-- client: both
-- The cooldown bar made again (a setting, a profile, a talent): its keys press the NEW buttons. A key's
-- CLICK binding presses the first frame ever made under its name, so the new buttons get names nothing
-- has had (FreshFrameName) and the keys are pointed at them after every rebuild, with Keybinds Still Work
-- Even If Icon Is Turned Off on or off. (The owner's report, 3.0.9.4: the shield key kept casting the
-- shield the button had at login, the imbue key the old imbue.)
local SP = ShamanPower
local o = SP.opt
local savedWhenOff = o.keybindsWorkWhenOff

local keys = { SHAMANPOWER_CD_SHIELD = "SHIFT-8", SHAMANPOWER_CD_IMBUE = "SHIFT-F" }
local pointed = {}
local realKey, realOverride = GetBindingKey, SetOverrideBindingClick
GetBindingKey = function(action) return keys[action] end
SetOverrideBindingClick = function(_, _, key, name) pointed[key] = name end

for _, whenOff in ipairs({ false, true }) do
	local label = whenOff and "keys-when-off on: " or "keys-when-off off: "
	o.keybindsWorkWhenOff = whenOff or nil
	SP:RecreateCooldownBar()
	local oldShield, oldImbue = SP.shieldButton, SP.weaponImbueButton
	wipe(pointed)
	SP:RecreateCooldownBar()   -- no SetupKeybindings call of our own: the rebuild points the keys
	local shield, imbue = SP.shieldButton, SP.weaponImbueButton
	if shield and oldShield then
		check(label .. "the shield button is a new frame", shield ~= oldShield)
		check(label .. "under a name the old one never had", shield:GetName() ~= oldShield:GetName())
		checkEq(label .. "the shield key presses the new button", pointed["SHIFT-8"], shield:GetName())
		check(label .. "that name finds the new button", _G[shield:GetName()] == shield)
	else
		check(label .. "a shield button to test", false)
	end
	if imbue and oldImbue then
		check(label .. "the imbue button is a new frame under a new name", imbue ~= oldImbue and imbue:GetName() ~= oldImbue:GetName())
		checkEq(label .. "the imbue key presses the new button", pointed["SHIFT-F"], imbue:GetName())
	end
end

-- the first bar keeps the plain names
check("a name never used comes back as it is", SP.FreshFrameName and SP:FreshFrameName("ShamanPowerNeverMadeXYZ") == "ShamanPowerNeverMadeXYZ")

GetBindingKey, SetOverrideBindingClick = realKey, realOverride
o.keybindsWorkWhenOff = savedWhenOff
SP:RecreateCooldownBar()
finish()
