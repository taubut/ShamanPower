-- client: both
-- regime: aurasounds
-- (3.0.9.9) Shield Charges > Sound > Shield Sound Volume (a Discord ask: "Lightning Shield is super loud").
-- Until it is moved, as before: WoW: Forever, the game plays the drop (full volume); Anniversary, Expiring
-- Alerts' Alert Volume. Below 100 on WoW: Forever: ShamanPower plays it at that volume when the Cooldown
-- Manager's hook says the shield went (in a fight too) and the game's sound is not registered for that
-- shield; a shield the Cooldown Manager has no item for keeps the game's sound. A refresh is no drop.
-- Earth Shield's sound stays on Expiring Alerts' Alert Volume.
local SP = ShamanPower
local A = __sim.A
local FOREVER = SPCompat.FOREVER
local o = SP.opt
local ea = ShamanPowerExpiringAlertsDB
check("Expiring Alerts is loaded", SP.ExpiringAlertsLoaded == true and type(ea) == "table")

local eaVol = ea.soundVolume
o.shieldDropSound = true
for _, k in ipairs({ "shieldDropSoundLS", "shieldDropSoundWS", "shieldDropSoundES" }) do o[k] = nil end
o.shieldSoundVolume = nil
ea.soundVolume = 70

-- what ShamanPower plays, and how loud
local plays = {}
local play = SP.PlaySoundWithVolume
SP.PlaySoundWithVolume = function(_, _, vol) plays[#plays + 1] = vol end
-- the Cooldown Manager's shield items (Shield Charges' hook), as a stand-in
local has = { true, true }
local hookHas = SP.ShieldHookHas
SP.ShieldHookHas = function(_, w) return has[w] == true end
SP:UpdateShieldSounds()
if FOREVER then check("the game's aura sounds are here (the regime)", next(A.auraSounds) ~= nil) end

local LS = {}
for _, id in ipairs(SP.ShieldAuraSets[1].ids) do LS[id] = true end
local function gameSoundLS()
	for _, r in pairs(A.auraSounds or {}) do if LS[r.spellID] then return true end end
	return false
end
-- the hook's word that Lightning Shield went; then a moment, and the sounds since
local function drop(back)
	local n = #plays
	SP:ShieldSoundHook(1, false)
	if back then SP:ShieldSoundHook(1, true) end
	__sim.advance(0.3)
	local v = plays[n + 1]
	__sim.advance(1.2)   -- (past the one-sound-per-drop throttle)
	return v
end

checkEq("until moved: the volume as before", SP:ShieldSoundVolume(), FOREVER and 100 or 70)
SP:TestShieldSound("LS")
checkEq("Test Sound at it", plays[#plays], FOREVER and 100 or 70)

SP:SetShieldSoundVolume(40)
checkEq("moved to 40", SP:ShieldSoundVolume(), 40)
SP:TestShieldSound("LS")
checkEq("Lightning Shield's Test Sound at 40", plays[#plays], 40)
SP:TestShieldSound("ES")
checkEq("Earth Shield's at Expiring Alerts' Alert Volume", plays[#plays], 70)

if FOREVER then
	SP:SetShieldSoundVolume(nil)
	check("until moved: the game plays Lightning Shield's drop", gameSoundLS())
	check("and ShamanPower plays none", drop() == nil)

	SP:SetShieldSoundVolume(40)
	check("40: the game's sound is gone for it", not gameSoundLS())
	checkEq("40: ShamanPower plays the drop at 40", drop(), 40)
	check("a refresh (gone, back at once): no sound", drop(true) == nil)
	__sim.setCombat(true); __sim.advance(0.1)
	checkEq("in a fight too", drop(), 40)
	__sim.setCombat(false); __sim.advance(0.1)

	-- no Cooldown Manager item for it: the game's sound, never silence
	has[1] = false; SP:UpdateShieldSounds()
	check("no item: the game's sound again", gameSoundLS())
	check("no item: ShamanPower plays none (never two)", drop() == nil)
	has[1] = true; SP:UpdateShieldSounds()

	SP:SetShieldSoundVolume(100)
	check("100: the game's sound, as before", gameSoundLS())
	check("100: ShamanPower plays none", drop() == nil)

	-- the sound switched off: nothing from either
	SP:SetShieldSoundVolume(40)
	o.shieldDropSound = false; SP:UpdateShieldSounds()
	check("sound off: no game sound", not gameSoundLS())
	check("sound off: ShamanPower plays none", drop() == nil)
	o.shieldDropSound = true
end

-- the page's Reset: back to as before
if SP.ShieldChargesResetPage then
	SP:SetShieldSoundVolume(40)
	SP:ShieldChargesResetPage()
	check("Reset Page Settings: back to as before", o.shieldSoundVolume == nil)
end

-- put back
SP.PlaySoundWithVolume = play
SP.ShieldHookHas = hookHas
ea.soundVolume = eaVol
o.shieldSoundVolume = nil
o.shieldDropSound = nil
SP:UpdateShieldSounds()
finish()
