-- client: both
-- Expiring Alerts switched off: none of its sounds play (3.0.9.6). Sound When Your Shield Drops on, Lightning
-- Shield dropped: the sound plays with Expiring Alerts on, not with it off (the setting is kept), and again once
-- it is back on. (The sim has no C_UnitAuras.AddAuraSound, so both clients take ShamanPower's own path here;
-- WoW: Forever's game-played sound goes by the same check.)
local SP = ShamanPower
local W = __sim.W
local o = SP.opt
local ea = ShamanPowerExpiringAlertsDB
check("Expiring Alerts is loaded", SP.ExpiringAlertsLoaded == true and type(ea) == "table")

-- the sound as it is set in game: on, one shared sound for every shield
o.shieldDropSound = true
for _, k in ipairs({ "shieldDropSoundLS", "shieldDropSoundWS", "shieldDropSoundES" }) do o[k] = nil end

-- your Lightning Shield, as the game would answer out of combat
local shieldOn, instance = false, 100
local LS = {}
for _, id in ipairs(SP.ShieldAuraSets[1].ids) do LS[id] = true end
local get = C_UnitAuras.GetPlayerAuraBySpellID
C_UnitAuras.GetPlayerAuraBySpellID = function(id)
	if LS[id] then
		if not shieldOn then return nil end
		return { auraInstanceID = instance, spellId = 324, name = "Lightning Shield" }
	end
	return get and get(id)
end

local played = 0
local play = SP.PlaySoundWithVolume
SP.PlaySoundWithVolume = function(self, ...) played = played + 1 end

local function putOn()
	instance = instance + 1
	shieldOn = true
	W.fireEvent("UNIT_AURA", "player", { addedAuras = { { auraInstanceID = instance, spellId = 324, name = "Lightning Shield" } } })
	__sim.advance(0.3)
end
local function drop()
	shieldOn = false
	W.fireEvent("UNIT_AURA", "player", { removedAuraInstanceIDs = { instance } })
	__sim.advance(1.5)   -- (past the one-second throttle too)
end
local function switch(on)
	ea.enabled = on
	SP:UpdateShieldSounds()
	__sim.advance(0.1)
end

W.fireEvent("PLAYER_ENTERING_WORLD")
switch(true)
putOn()
played = 0; drop()
check("Expiring Alerts on: the shield drop plays its sound", played == 1)

switch(false)
putOn()
played = 0; drop()
check("Expiring Alerts off: no sound when the shield drops", played == 0)
check("Expiring Alerts off: the sound setting itself is kept", o.shieldDropSound == true and SP:ShieldSoundOn(1))

switch(true)
putOn()
played = 0; drop()
check("Expiring Alerts back on: the sound plays again", played == 1)

SP.PlaySoundWithVolume = play
C_UnitAuras.GetPlayerAuraBySpellID = get
finish()
