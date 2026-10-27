-- client: both
-- Reactive Totems (Miska, PR #28): an alert only for a debuff something you have learned can answer: Tremor
-- Totem for fear, Poison Cleansing Totem or Cure Poison for poison, Disease Cleansing Totem or Cure Disease for
-- disease. By spell ID only, never by name, and read again when the spellbook changes. The scan part runs on
-- Forever only: there the sim's debuffs can be faked (C_UnitAuras); Anniversary's UnitDebuff is fixed at load.
local SP = ShamanPower
local W = __sim.W
local sv = ShamanPower_ReactiveTotems
check("Reactive Totems loaded", SP.ReactiveCanAnswer ~= nil and sv ~= nil)
if not (SP.ReactiveCanAnswer and sv) then finish() end

local ANSWER_IDS = { [8143] = true, [8166] = true, [526] = true, [8170] = true, [2870] = true }
local KN, realInfo = SPCompat.KnowsSpellID, GetSpellInfo
local known = {}
SPCompat.KnowsSpellID = function(id) if ANSWER_IDS[id] then return known[id] or false end return KN(id) end
local function learn(...)
	wipe(known)
	for _, id in ipairs({ ... }) do known[id] = true end
	W.fireEvent("SPELLS_CHANGED")
end
local function answers()
	return (SP:ReactiveCanAnswer("fear") and "F" or "-") .. (SP:ReactiveCanAnswer("poison") and "P" or "-")
		.. (SP:ReactiveCanAnswer("disease") and "D" or "-")
end

learn()
checkEq("nothing learned: no alert", answers(), "---")
learn(8143)
checkEq("Tremor Totem: the fear alert only", answers(), "F--")
learn(8166)
checkEq("Poison Cleansing Totem: the poison alert only", answers(), "-P-")
learn(526)
checkEq("Cure Poison: the poison alert only", answers(), "-P-")
learn(8170)
checkEq("Disease Cleansing Totem: the disease alert only", answers(), "--D")
learn(2870)
checkEq("Cure Disease: the disease alert only", answers(), "--D")
learn(8143, 8166, 8170)
checkEq("all three totems: every alert", answers(), "FPD")

-- the spellbook changing: read again (the answer is kept until then)
learn(8143)
known[526] = true
checkEq("a spell learned: still the old answer before the spellbook event", answers(), "F--")
W.fireEvent("SPELLS_CHANGED")
checkEq("then the spellbook event: the poison alert too", answers(), "FP-")

-- by spell ID only: a name the game would find is not enough
GetSpellInfo = function(name) if type(name) == "string" then return name, nil, 136240 end return realInfo and realInfo(name) end
learn()
checkEq("no name lookup: nothing learned by ID is no alert", answers(), "---")
GetSpellInfo = realInfo

-- the scan looks only for what you can answer (Forever: fake debuffs on you)
if SPCompat.FOREVER and C_UnitAuras and C_UnitAuras.GetDebuffDataByIndex then
	local A = C_UnitAuras
	local realGet = A.GetDebuffDataByIndex
	local mine = {
		{ name = "Deadly Poison", icon = 136140, applications = 1, dispelName = "Poison", spellId = 2818 },
		{ name = "Plague", icon = 136182, applications = 1, dispelName = "Disease", spellId = 3439 },
	}
	A.GetDebuffDataByIndex = function(unit, i) if unit == "player" then return mine[i] end end
	local saved = { sv.enabled, sv.onlyInInstance, sv.trackPoison, sv.trackDisease }
	sv.enabled, sv.onlyInInstance, sv.trackPoison, sv.trackDisease = true, false, true, true
	local function scan()
		local f = SP:ScanForReactiveDebuffs()
		return (f.poison and "P" or "-") .. (f.disease and "D" or "-")
	end
	learn()
	checkEq("poisoned and diseased, nothing learned: nothing found", scan(), "--")
	learn(526)
	checkEq("Cure Poison learned: the poison found, not the disease", scan(), "P-")
	learn(526, 2870)
	checkEq("Cure Poison and Cure Disease: both found", scan(), "PD")
	A.GetDebuffDataByIndex = realGet
	sv.enabled, sv.onlyInInstance, sv.trackPoison, sv.trackDisease = saved[1], saved[2], saved[3], saved[4]
end

SPCompat.KnowsSpellID = KN
W.fireEvent("SPELLS_CHANGED")
finish()
