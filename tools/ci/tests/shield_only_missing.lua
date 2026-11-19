-- client: both
-- (3.0.9.17) A Discord ask: Shield Charges shown only when the shield is fully missing ("i dont really care for the
-- charges"). Two new Show choices for Lightning and Water Shield: Only When Missing, and In Combat, Only When Missing.
-- The gray look while no shield is on you, nothing while one is. In a fight on WoW: Forever (auras hidden) only the
-- Cooldown Manager's word says it went, and the game's count is never shown. Not Earth Shield's.
local SP = ShamanPower
local W = __sim.W
if not (SP.CreateShieldChargeDisplays and SP.SetShieldOpt and SP.UpdateShieldChargeDisplays) then skip("no Shield Charges here") end
SP:EnsureProfileTable("shieldChargeDisplay")
if not (SP.shieldChargeFrames and SP.shieldChargeFrames.player) then SP:CreateShieldChargeDisplays() end
local f = SP.shieldChargeFrames.player
check("the Lightning Shield display", f ~= nil)
if not f then finish() end

-- the choices: Lightning and Water Shield, never Earth Shield
SP:SetShieldOpt("ES", "show", "missing")
checkEq("Earth Shield: Only When Missing refused (it stays While Shield Is Active)", SP:ShieldOpt("ES", "show"), "up")
SP:SetShieldOpt("LS", "show", "missing")
checkEq("Lightning Shield: Only When Missing", SP:ShieldOpt("LS", "show"), "missing")

-- Lightning Shield known; the buff as the game would answer out of a fight
local LS = {}
for _, id in ipairs(SP.ShieldAuraSets[1].ids) do LS[id] = true end
local KN = SPCompat.KnowsSpellID
SPCompat.KnowsSpellID = function(id) if LS[id] then return true end return KN(id) end
local up = false
local FAM = SPCompat.AuraFamilyName
SPCompat.AuraFamilyName = function() return nil end   -- (WoW: Forever reads it by spell ID then: answered below)
local A = C_UnitAuras
local byID, byIndex = A.GetPlayerAuraBySpellID, A.GetBuffDataByIndex
local AURA = { name = "Lightning Shield", spellId = 10432, applications = 3, icon = 136051, duration = 600, auraInstanceID = 77,
	sourceUnit = "player", isHelpful = true }
A.GetPlayerAuraBySpellID = function(id) if up and id == 10432 then AURA.expirationTime = GetTime() + 500 return AURA end return nil end
A.GetBuffDataByIndex = function(unit, i) if up and unit == "player" and i == 1 then AURA.expirationTime = GetTime() + 500 return AURA end return nil end
W.fireEvent("SPELLS_CHANGED")
SP:SetShieldOpt("LS", "enabled", true)
local function pass()
	if SPCompat.FOREVER then
		W.fireEvent("UNIT_AURA", "player", { isFullUpdate = true })
	else
		-- Anniversary: Shield Charges takes the core's shield check (its reader is the game's own, kept at load)
		-- (the core's record as its scan leaves it: shieldID is the shield's own button spell, 324 for Lightning Shield)
		SP.shieldCache = { hasShield = up, rawCount = up and 3 or nil, shieldID = up and 324 or nil, shieldCharges = up and 3 or 0,
			shieldDuration = up and 600 or 0, shieldExpiration = up and (GetTime() + 500) or 0, shieldName = up and "Lightning Shield" or nil }
		SP._shieldCheckedGen = SP.auraGen and SP.auraGen.player or 0
	end
	__sim.advance(0.2)
	SP:UpdateShieldChargeDisplays()
end

up = true; pass()
check("Only When Missing, shield on: nothing on screen", not f:IsShown())
up = false; pass()
check("Only When Missing, shield gone: shown", f:IsShown())
up = true; pass()
check("Only When Missing, shield back: hidden again", not f:IsShown())

-- in a fight on WoW: Forever the game hides your buffs: the Cooldown Manager's word decides (Anniversary reads them)
local CV, BV = C_CooldownViewer, _G.BuffIconCooldownViewer
if SPCompat.FOREVER then
local realR = SP.ShieldChargesRestricted
SP.ShieldChargesRestricted = function() return true end
local item = { id = 200311 }
function item:GetCooldownID() return self.id end
function item:TriggerAuraAppliedAlert() end
function item:TriggerAuraRemovedAlert() end
function item:SetAlpha() end
local viewer = { itemFramePool = { EnumerateActive = function() return pairs({ [item] = true }) end } }
function viewer:RefreshLayout() end
C_CooldownViewer = { GetCooldownViewerCooldownInfo = function(id) if id == 200311 then return { spellID = 324 } end end }
_G.BuffIconCooldownViewer = viewer
if SP.BindShieldGoneHooks then SP.BindShieldGoneHooks() end
__sim.setCombat(true)
item:TriggerAuraAppliedAlert(); SP:UpdateShieldChargeDisplays()
check("in a fight, the Cooldown Manager says it's on: hidden", not f:IsShown())
if f.engine then check("in a fight: the game's count not shown", not f.engine:IsShown()) end
item:TriggerAuraRemovedAlert(); SP:UpdateShieldChargeDisplays()
check("in a fight, the Cooldown Manager says it went: shown", f:IsShown())
if f.engine then check("shown: still not the game's count", not f.engine:IsShown()) end
item:TriggerAuraAppliedAlert(); SP:UpdateShieldChargeDisplays()
check("in a fight, cast again: hidden", not f:IsShown())

-- In Combat, Only When Missing: never out of a fight
SP:SetShieldOpt("LS", "show", "fightsMissing")
item:TriggerAuraRemovedAlert(); SP:UpdateShieldChargeDisplays()
check("In Combat, Only When Missing: gone in a fight: shown", f:IsShown())
__sim.setCombat(false)
SP.ShieldChargesRestricted = realR
else
	SP:SetShieldOpt("LS", "show", "fightsMissing")
	up = false; __sim.setCombat(true); pass()
	check("Anniversary, In Combat, Only When Missing: gone in a fight: shown", f:IsShown())
	up = true; pass()
	check("Anniversary, in a fight, shield on: hidden", not f:IsShown())
	__sim.setCombat(false)
end
up = false; pass()
check("In Combat, Only When Missing: out of a fight, even with no shield: hidden", not f:IsShown())

-- the others as they were: While Shield Is Active shows while it is on
SP:SetShieldOpt("LS", "show", nil)
up = true; pass()
check("While Shield Is Active (unchanged): shown while it is on", f:IsShown())

C_CooldownViewer, _G.BuffIconCooldownViewer = CV, BV
A.GetPlayerAuraBySpellID, A.GetBuffDataByIndex = byID, byIndex
SPCompat.AuraFamilyName, SPCompat.KnowsSpellID = FAM, KN
up = false; pass()
finish()
