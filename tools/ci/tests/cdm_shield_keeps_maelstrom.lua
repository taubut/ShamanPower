-- client: forever
-- (3.0.9.17, a Discord ticket 11-17) Maelstrom Weapon's 5-stack sound worked, then the player learned Water Shield,
-- took the shield setup's reload, and the sound was gone: the setup rebuilds ShamanPower's Cooldown Manager layout
-- whole and put Maelstrom Weapon in Not Displayed. Now it stays in Tracked Buffs when it is there, or when its sound
-- wants it; a layout with it there reads as whole (the shield switch no longer rebuilds it away). Never otherwise
-- (the owner's rule, 3.0.9.16: only for the sound).
local SP = ShamanPower
local W = __sim.W
if not (SP.ShieldGoneSetup and SP.CdmMaelstromSet and SP.CdmKeepMaelstrom) then skip("no Shield Charges / Cooldown Manager layout here") end
local e
for _, x in ipairs(SP.ReadyReminderSpells or {}) do if x.key == "maelstrom" then e = x end end
if not e then skip("no Maelstrom Weapon reminder here") end

local LS_CID, WS_CID, MW_CID = 200311, 200312, 200560
local LS_ID, WS_ID, MW_ID = 324, 52127, 408498
for _, set in ipairs(SP.ShieldAuraSets or {}) do
	if set.name == "Lightning Shield" and set.ids[1] then LS_ID = set.ids[1] end
	if set.name == "Water Shield" and set.ids[1] then WS_ID = set.ids[1] end
end
-- a stand-in Cooldown Manager (cdm_layout.lua's): the store kept as a table behind a key string; Maelstrom
-- Weapon in its catalog's buffs
local store, saved, n = {}, nil, 0
local realC, realE, realCat = C_CooldownViewer, C_EncodingUtil, Enum.CooldownViewerCategory
local KN, SE = SPCompat.KnowsSpellID, SPCompat.SpellExists
C_EncodingUtil = {
	SerializeCBOR = function(t) n = n + 1; store["k" .. n] = t; return "k" .. n end,
	CompressString = function(s) return s end, DecompressString = function(s) return s end,
	EncodeBase64 = function(s) return s end, DecodeBase64 = function(s) return s end,
	DeserializeCBOR = function(s) return store[s] end,
}
local catalog = { [0] = { 11 }, [1] = { 21 }, [2] = { LS_CID, WS_CID, MW_CID, 31 }, [3] = { 41 } }
C_CooldownViewer = {
	IsCooldownViewerAvailable = function() return true end,
	GetLayoutData = function() return saved end,
	SetLayoutData = function(s) saved = s end,
	GetCooldownViewerCategorySet = function(cat)
		local out = {}
		for _, id in ipairs(catalog[cat] or {}) do out[#out + 1] = id end
		return out
	end,
	GetCooldownViewerCooldownInfo = function(id)
		if id == LS_CID then return { spellID = LS_ID } elseif id == WS_CID then return { spellID = WS_ID }
		elseif id == MW_CID then return { spellID = MW_ID, linkedSpellIDs = { 408505 } } end
		return { spellID = 1000 + id }
	end,
}
Enum.CooldownViewerCategory = { Essential = 0, Utility = 1, TrackedBuff = 2, TrackedBar = 3, HiddenActive = -1, HiddenPassive = -2 }
-- (every Water Shield ID the module looks at: the sim knows every spell)
local WATER = { [WS_ID] = true, [24398] = true, [33736] = true, [408510] = true, [408511] = true, [409941] = true, [52127] = true }
for _, set in ipairs(SP.ShieldAuraSets or {}) do
	if set.name == "Water Shield" then for _, id in ipairs(set.ids) do WATER[id] = true end end
end
local waterKnown = false
SPCompat.KnowsSpellID = function(id)
	if id == LS_ID or id == MW_ID then return true end
	if WATER[id] then return waterKnown end
	return KN and KN(id)
end
SPCompat.SpellExists = function(id) if id == MW_ID then return true end return SE(id) end
-- (the displays as the game makes them at login: their event frame forgets the known shields when spells change)
if SP.CreateShieldChargeDisplays and not (SP.shieldChargeFrames and SP.shieldChargeFrames.player) then
	SP:EnsureProfileTable("shieldChargeDisplay")
	SP:CreateShieldChargeDisplays()
end
e.clientID = nil
W.fireEvent("SPELLS_CHANGED")
-- (the Maelstrom popup is not this test's: kept quiet)
local dlg = SP.ShowSPDialog
SP.ShowSPDialog = function(self, d) if type(d) == "table" and d.key == "cdmMaelstrom" then return end return dlg(self, d) end

local function active()
	local data = store[(saved or ""):gsub("^1|", "")]
	local tag
	for t in pairs(data[2]) do tag = t end
	return data[3][tag][data[2][tag]]
end
local function where(cid)
	for cat, ids in pairs(active()[2] or {}) do for _, x in ipairs(ids) do if x == cid then return cat end end end
end

-- the shield setup, Maelstrom's sound off: Lightning Shield tracked, Maelstrom out of sight (as before)
ShamanPower_ReadyReminders.enabled = true
SP:ReadyReminderSetSpell("maelstrom", true)
SP:ReadyReminderSetIconOpt("maelstrom", "soundOnReady", false)
local ok, why = SP:ShieldGoneSetup()
check("the shield setup works: " .. tostring(why), ok)
if not ok then finish() return end
checkEq("Lightning Shield tracked", where(LS_CID), 2)
checkEq("Maelstrom's sound off: Maelstrom out of sight, as before", where(MW_CID), -2)

-- Maelstrom's sound set up (its popup's button): tracked
SP:ReadyReminderSetIconOpt("maelstrom", "soundOnReady", true)
check("Maelstrom put in Tracked Buffs", SP:CdmMaelstromSet(true))
checkEq("Maelstrom tracked", where(MW_CID), 2)
check("with Maelstrom tracked the layout still reads as whole", SP:ShieldGoneLayoutComplete())

-- the ticket: Water Shield learned, the shield setup again (its ask and reload)
waterKnown = true
W.fireEvent("SPELLS_CHANGED")
check("Water Shield learned: the layout isn't whole", not SP:ShieldGoneLayoutComplete())
ok = SP:ShieldGoneSetup()
check("the shield setup again", ok)
checkEq("Water Shield tracked", where(WS_CID), 2)
checkEq("Lightning Shield still tracked", where(LS_CID), 2)
checkEq("Maelstrom STILL tracked (the ticket)", where(MW_CID), 2)
check("whole", SP:ShieldGoneLayoutComplete())

-- a layout that lost it before this fix: the shield setup brings it back while its sound wants it
check("Maelstrom put out of sight", SP:CdmMaelstromSet(false))
SP:ShieldGoneSetup()
checkEq("its sound on: the shield setup tracks Maelstrom again", where(MW_CID), 2)

-- its sound off and Maelstrom out of sight: the setup leaves it there (only for the sound)
SP:ReadyReminderSetIconOpt("maelstrom", "soundOnReady", false)
SP:CdmMaelstromSet(false)
SP:ShieldGoneSetup()
checkEq("its sound off: Maelstrom stays out of sight", where(MW_CID), -2)
-- the game's other icons stay out of sight
checkEq("another buff out of sight", where(31), -2)
checkEq("a cooldown out of sight", where(11), -1)

-- put back
SP.ShowSPDialog = dlg
C_CooldownViewer, C_EncodingUtil, Enum.CooldownViewerCategory = realC, realE, realCat
SPCompat.KnowsSpellID, SPCompat.SpellExists = KN, SE
SP:ReadyReminderResetIcon("maelstrom")
SP:ReadyReminderSetSpell("maelstrom", false)
SP.opt.cdmLayoutBackup = nil
W.fireEvent("SPELLS_CHANGED")
finish()
