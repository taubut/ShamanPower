-- client: forever
-- Auto-Assign on WoW: Forever (3.0.9.5): the raid-wide totems (Strength of Earth, Windfury, Grace of Air,
-- Flametongue) go to one shaman each across the raid, an Enhancement shaman first, so the raid has them all
-- before anyone doubles up; Windfury and Flametongue never both; a shaman with Guardian Totems drops
-- Stoneskin; a raid-wide totem someone else already drops is never doubled.
local SP = ShamanPower
if not (SP.AutoAssignTotems and SP.HasGuardianTotems) then skip("no Auto-Assign") end
local me = SP.player
local keep = {
	all = SP.AllShamans, assign = ShamanPower_Assignments, comp = SP.AnalyzeGroupComposition, ctl = SP.CanControl,
	spec = SP.SpecGuess, gt = SP.HasGuardianTotems, knows = SP.KnowsTotem, roster = SP.UpdateRoster,
	print = SP.Print, raid = IsInRaid,
}
-- every party: melee, no tank, mana users
SP.AnalyzeGroupComposition = function()
	local c = {}
	for g = 1, 8 do
		c[g] = { tank = 0, healer = 1, meleeDPS = 3, rangedCaster = 0, agilityDPS = 0, manaUsers = 2, melee = 3,
			caster = 1, agiUsers = 0, total = 5 }
	end
	return c
end
SP.CanControl = function() return true end
SP.KnowsTotem = function() return true end
SP.UpdateRoster = function() end
SP.Print = function() end
IsInRaid = function() return true end
local mySpec, myGuardian = "resto", false
SP.SpecGuess = function() return mySpec end
SP.HasGuardianTotems = function() return myGuardian end

local function Raid(shamans)
	SP.AllShamans, ShamanPower_Assignments = {}, {}
	for name, info in pairs(shamans) do
		SP.AllShamans[name] = { subgroup = info.group, spec = info.spec, guardian = info.guardian }
		ShamanPower_Assignments[name] = info.has or { 0, 0, 0, 0 }
	end
	SP:AutoAssignTotems()
	return ShamanPower_Assignments
end
local function count(a, element, index)
	local n = 0
	for _, t in pairs(a) do if t[element] == index then n = n + 1 end end
	return n
end

-- one Enhancement shaman and you (Restoration), in different parties
local a = Raid({ [me] = { group = 1 }, Aenhance = { group = 2, spec = "enh" } })
checkEq("Windfury: the Enhancement shaman", a.Aenhance[4], 1)
checkEq("Grace of Air: you (the second shaman)", a[me][4], 2)
checkEq("Strength of Earth: the Enhancement shaman", a.Aenhance[1], 1)
checkEq("you: Stoneskin (Strength of Earth is covered)", a[me][1], 2)
checkEq("no Flametongue with Windfury down", count(a, 2, 5), 0)

-- the Enhancement shaman has Guardian Totems: Stoneskin, so Strength of Earth goes to you
a = Raid({ [me] = { group = 1 }, Aenhance = { group = 2, spec = "enh", guardian = true } })
checkEq("Guardian Totems: Stoneskin", a.Aenhance[1], 2)
checkEq("Strength of Earth: you", a[me][1], 1)
checkEq("Windfury still the Enhancement shaman", a.Aenhance[4], 1)
checkEq("Grace of Air: you", a[me][4], 2)

-- you have Guardian Totems
myGuardian = true
a = Raid({ [me] = { group = 1 }, Aenhance = { group = 2, spec = "enh" } })
checkEq("your Guardian Totems: Stoneskin", a[me][1], 2)
myGuardian = false

-- three shamans, two Enhancement: one Windfury, one Grace of Air, the third neither
a = Raid({ [me] = { group = 1 }, Aenhance = { group = 2, spec = "enh" }, Benhance = { group = 3, spec = "enh" } })
checkEq("one Windfury in the raid", count(a, 4, 1), 1)
checkEq("one Grace of Air in the raid", count(a, 4, 2), 1)
check("both from the Enhancement shamans", a.Aenhance[4] == 1 and a.Benhance[4] == 2)
check("you: neither (Grounding or Tranquil Air)", a[me][4] ~= 1 and a[me][4] ~= 2 and a[me][4] ~= 0)
checkEq("one Strength of Earth in the raid", count(a, 1, 1), 1)

-- someone you can't change already drops Windfury: nobody else does, and nobody drops Flametongue
SP.CanControl = function(_, name) return name ~= "Zother" end
a = Raid({ [me] = { group = 1 }, Aenhance = { group = 2, spec = "enh" }, Zother = { group = 3, has = { 0, 0, 0, 1 } } })
checkEq("Windfury stays theirs alone", count(a, 4, 1), 1)
checkEq("the Enhancement shaman: Grace of Air", a.Aenhance[4], 2)
check("you: neither", a[me][4] ~= 1 and a[me][4] ~= 2)
checkEq("no Flametongue", count(a, 2, 5), 0)
SP.CanControl = function() return true end

-- back as it was
SP.AllShamans, ShamanPower_Assignments, SP.AnalyzeGroupComposition, SP.CanControl = keep.all, keep.assign, keep.comp, keep.ctl
SP.SpecGuess, SP.HasGuardianTotems, SP.KnowsTotem, SP.UpdateRoster = keep.spec, keep.gt, keep.knows, keep.roster
SP.Print, IsInRaid = keep.print, keep.raid
finish()
