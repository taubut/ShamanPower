-- client: forever
-- (3.0.9.17) A Discord report (11-17, with a picture): Call of the Elements dropped Searing Totem and Windfury Totem at
-- rank 1 (no numeral on the totems) while Strength of Earth III and Mana Spring II came down at their ranks. A Call slot
-- filled while only rank 1 was known was never brought up: the write was skipped as "the same totem already there".
-- The owner: it must ALWAYS drop the highest rank. By spell ID: a slot always gets the highest rank ID the game lists
-- for it, whether the game lists each totem's top rank only or every rank known; on all three Calls; with Call of the
-- Elements Follows My Assignments on or off; nothing in a fight or while switched off.
local SP = ShamanPower
local A, W = __sim.A, __sim.W
if not (SP.SyncTotemSetFromAssignments and SPCompat.SpellRanks) then skip("no totem sets here") end
check("the highest-rank pass is there", SP.TopRankTotemSets ~= nil)
local function topRank() if SP.TopRankTotemSets then SP:TopRankTotemSets() end end

-- ---- Blizzard's totem bar (the sim has none): three pages of four slots
local BAR = 7
local first = (BAR - 1) * 12 + 1
local slots, writes = {}, 0
local was = {
	GetActionInfo = GetActionInfo, SetMultiCastSpell = rawget(_G, "SetMultiCastSpell"),
	GetMultiCastTotemSpells = rawget(_G, "GetMultiCastTotemSpells"), barIndex = C_ActionBar.GetMultiCastBarIndex,
	sync = SP.opt.totemSetsSyncAssignments, once = SP.totemSetsSyncedOnce, page = SP.db.char.callPage, known = {},
	off = SP.IsOff,
}
local function slotOf(page, element) return (page - 1) * 4 + SP.ElementToSlot[element] + first - 1 end
C_ActionBar.GetMultiCastBarIndex = function() return BAR end
GetActionInfo = function(a)
	if type(a) == "number" and a >= first and a < first + 12 then
		if slots[a] then return "spell", slots[a] end
		return nil
	end
	return was.GetActionInfo(a)
end
SetMultiCastSpell = function(a, id) writes = writes + 1; if id and id ~= 0 then slots[a] = id else slots[a] = nil end end
for _, id in ipairs({ 66842, 66843, 66844 }) do was.known[id] = A.known[id]; A.known[id] = true end

-- Searing Totem (Fire, 2) and Windfury Totem (Air, 4), known up to rank 3
local FIRE, AIR = 2, 4
local function indexOf(element, id)
	for i, x in pairs(SP.Totems[element]) do if x == id then return i end end
end
local searing, windfury = SPCompat.SpellRanks(3599), SPCompat.SpellRanks(8512)
if not (searing and windfury and indexOf(FIRE, 3599) and indexOf(AIR, 8512)) then skip("no Searing / Windfury ranks here") end
local topS, topW = searing[math.min(3, #searing)], windfury[math.min(3, #windfury)]
check("the ranks differ", topS ~= 3599 and topW ~= 8512)

-- what the game lists for a slot: "top" = each totem's highest rank known, "all" = every rank known
local listing = "top"
local function upTo(family, top)
	local out = {}
	for _, id in ipairs(family) do out[#out + 1] = id; if id == top then break end end
	return out
end
GetMultiCastTotemSpells = function(wowSlot)
	local list = {}
	for e = 1, 4 do
		if SP.ElementToSlot[e] == wowSlot then
			for _, id in pairs(SP.Totems[e]) do
				local family = id == 3599 and upTo(searing, topS) or id == 8512 and upTo(windfury, topW) or nil
				if family and listing == "top" then list[#list + 1] = family[#family]
				elseif family then for _, r in ipairs(family) do list[#list + 1] = r end
				else list[#list + 1] = id end
			end
		end
	end
	return unpack(list)
end

local mine = ShamanPower_Assignments[SP.player]
local savedAssign = {}
for e = 1, 4 do savedAssign[e] = mine[e] end
mine[1], mine[FIRE], mine[3], mine[AIR] = 0, indexOf(FIRE, 3599), 0, indexOf(AIR, 8512)
SP.opt.totemSetsSyncAssignments = nil
SP.db.char.callPage = nil
SP.totemSetsSyncedOnce = true

-- ---- Call of the Elements following the assignments
for _, how in ipairs({ "top", "all" }) do
	listing = how
	slots = { [slotOf(1, FIRE)] = 3599, [slotOf(1, AIR)] = 8512 }   -- (set up while only rank 1 was known)
	SP:SyncTotemSetFromAssignments()
	checkEq(how .. ": Searing brought up to its highest rank", slots[slotOf(1, FIRE)], topS)
	checkEq(how .. ": Windfury brought up to its highest rank", slots[slotOf(1, AIR)], topW)
	writes = 0
	SP:SyncTotemSetFromAssignments()
	checkEq(how .. ": at the highest rank already: nothing written", writes, 0)
	slots = {}
	SP:SyncTotemSetFromAssignments()
	check(how .. ": an empty slot takes the highest rank", slots[slotOf(1, FIRE)] == topS and slots[slotOf(1, AIR)] == topW)
end

-- ---- every Call, whatever Follows My Assignments says: only the rank changes, never the totem
listing = "top"
SP.opt.totemSetsSyncAssignments = false
local GROUNDING = SP.Totems[AIR][1] ~= 8512 and SP.Totems[AIR][1] or nil
slots = { [slotOf(1, FIRE)] = 3599, [slotOf(2, AIR)] = 8512, [slotOf(3, FIRE)] = 3599 }
if GROUNDING and not SPCompat.SpellRanks(GROUNDING) then slots[slotOf(3, AIR)] = GROUNDING end
topRank()
checkEq("Follows off: Call of the Elements' Searing at its highest rank", slots[slotOf(1, FIRE)], topS)
checkEq("Call of the Ancestors' Windfury at its highest rank", slots[slotOf(2, AIR)], topW)
checkEq("Call of the Spirits' Searing at its highest rank", slots[slotOf(3, FIRE)], topS)
if GROUNDING and not SPCompat.SpellRanks(GROUNDING) then
	checkEq("a one-rank totem left as it is", slots[slotOf(3, AIR)], GROUNDING)
end
check("an empty slot stays empty", slots[slotOf(1, AIR)] == nil and slots[slotOf(2, FIRE)] == nil)

-- in a fight: Blizzard's bar left alone
slots = { [slotOf(1, FIRE)] = 3599 }
__sim.setCombat(true)
topRank()
__sim.setCombat(false)
checkEq("in a fight: nothing written", slots[slotOf(1, FIRE)], 3599)

-- switched off: Blizzard's bar left alone
slots = { [slotOf(1, FIRE)] = 3599 }
SP.IsOff = function() return true end
topRank()
SP.IsOff = was.off
checkEq("switched off: nothing written", slots[slotOf(1, FIRE)], 3599)

-- learning a rank (SPELLS_CHANGED) brings it up
W.fireEvent("SPELLS_CHANGED"); __sim.advance(0.5)
checkEq("a spell learned: its highest rank", slots[slotOf(1, FIRE)], topS)

-- ---- put back
for e = 1, 4 do mine[e] = savedAssign[e] end
SP.opt.totemSetsSyncAssignments, SP.totemSetsSyncedOnce, SP.db.char.callPage = was.sync, was.once, was.page
for id, v in pairs(was.known) do A.known[id] = v end
GetActionInfo, SetMultiCastSpell, GetMultiCastTotemSpells = was.GetActionInfo, was.SetMultiCastSpell, was.GetMultiCastTotemSpells
C_ActionBar.GetMultiCastBarIndex = was.barIndex
W.fireEvent("SPELLS_CHANGED"); __sim.advance(0.3)
finish()
