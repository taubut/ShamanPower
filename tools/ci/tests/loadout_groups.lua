-- client: both
-- Auto Loadout Groups (3.0.9.5, sheet A79): what the flyout shows where, switching to a group's first
-- loadout on entry (once; in a fight when it ends; not with its switch off), a zone's kind put right
-- by a visit, Also Show My Other Loadouts Here, hidden loadouts, Any Raid beside a zone's group, the
-- Loadouts switch, a group moved and deleted, and more than 8 loadouts
local SP = ShamanPower
if not (SP.AddLoadoutGroup and ShamanPower_Assignments and SP.player and ShamanPower_Assignments[SP.player]) then
	skip("no groups or no assignments in the sim")
end
local keepList, keepGroups, keepActive = ShamanPower_TotemLoadouts, ShamanPower_LoadoutGroups, SP.opt.activeLoadout
local keepZone, keepInst, keepOff, keepBar = GetRealZoneText, IsInInstance, SP.opt.loadoutsOff, SP.opt.showLoadoutBar
local zone, kind = "Orgrimmar", nil
GetRealZoneText = function() return zone end
IsInInstance = function() if kind then return true, kind end return false, "none" end
local function go(z, k)
	zone, kind = z, k
	__sim.W.fireEvent("ZONE_CHANGED_NEW_AREA")
	__sim.advance(0.1)
end
local function idx(name)
	for i, lo in ipairs(ShamanPower_TotemLoadouts) do if lo.name == name then return i end end
end
local function active() local lo = ShamanPower_TotemLoadouts[SP.opt.activeLoadout or 0]; return lo and lo.name end
local function shownNames()
	local t = {}
	for i in pairs(SP:LoadoutShownSet()) do t[#t + 1] = ShamanPower_TotemLoadouts[i].name end
	table.sort(t)
	return table.concat(t, ",")
end

ShamanPower_TotemLoadouts = {
	{ name = "Solo", 1, 2, 1, 1 }, { name = "Raid", 2, 5, 1, 2 }, { name = "MC Trash", 2, 5, 6, 2 },
	{ name = "Lucifron", 3, 6, 6, 1 }, { name = "BWL Trash", 2, 5, 1, 1 }, { name = "Firemaw", 1, 5, 6, 1 },
}
ShamanPower_LoadoutGroups = {}
SP.opt.loadoutsOff = nil
SP.opt.showLoadoutBar = true
SP:ApplyLoadout(2, true)

-- a zone typed loosely is found by its real name; a new group goes first
local mc = SP:AddLoadoutGroup({ kind = "zone", zone = "  the   molten core ", zoneType = "raid", resist = "fire" })
checkEq("the name is tidied", mc.zone, "the molten core")
check("found by the game's name (case and spaces don't matter)", SP:LoadoutGroupForZone("The Molten Core") == mc)
check("a raid group", SP:LoadoutGroupIsRaid(mc))
SP:PutLoadoutInGroup(idx("MC Trash"), mc.id)
SP:PutLoadoutInGroup(idx("Lucifron"), mc.id)
checkEq("its first loadout", ShamanPower_TotemLoadouts[SP:LoadoutGroupFirst(mc)].name, "MC Trash")
local bwl = SP:AddLoadoutGroup({ kind = "zone", zone = "Blackwing Lair", zoneType = "party" })
check("a new group goes first", SP:LoadoutGroups()[1] == bwl and SP:LoadoutGroups()[2] == mc)
SP:PutLoadoutInGroup(idx("BWL Trash"), bwl.id)
SP:PutLoadoutInGroup(idx("Firemaw"), bwl.id)

-- what shows where
checkEq("Orgrimmar: Everywhere only", shownNames(), "Raid,Solo")
go("The Molten Core", "raid")
checkEq("entering MC: its first loadout", active(), "MC Trash")
checkEq("MC: Everywhere + MC's group", shownNames(), "Lucifron,MC Trash,Raid,Solo")
local flyout = 0
for _, b in ipairs(SP.loadoutButtons or {}) do if not b:GetAttribute("inactive") then flyout = flyout + 1 end end
checkEq("the flyout: the three that are not in use", flyout, 3)

-- a manual pick stays; the same zone again is not arriving
SP:ApplyLoadout(idx("Lucifron"), true)
go("The Molten Core", "raid")
checkEq("Lucifron stays", active(), "Lucifron")

-- in a fight: when it ends; the zone's kind put right by the visit
__sim.setCombat(true)
go("Blackwing Lair", "raid")
checkEq("in a fight: no switch yet", active(), "Lucifron")
__sim.setCombat(false)
__sim.advance(0.1)
checkEq("the fight over: BWL's first", active(), "BWL Trash")
checkEq("Dungeon picked for BWL, the visit says raid", bwl.zoneType, "raid")

-- Also Show My Other Loadouts Here off, a hidden loadout
SP:EditLoadoutGroup(bwl.id, { others = false })
checkEq("BWL only", shownNames(), "BWL Trash,Firemaw")
SP:SetLoadoutHidden(idx("Firemaw"), true)
checkEq("Firemaw hidden", shownNames(), "BWL Trash")
SP:SetLoadoutHidden(idx("Firemaw"), false)

-- the switch off: no switch on entry
SP:EditLoadoutGroup(mc.id, { entry = false })
SP:ApplyLoadout(idx("Solo"), true)
go("Orgrimmar")
go("The Molten Core", "raid")
checkEq("Switch to the First Loadout off: Solo stays", active(), "Solo")
SP:EditLoadoutGroup(mc.id, { entry = true })

-- Any Raid: a raid with no group of its own, and beside MC's group in MC (both show)
local anyRaid = SP:AddLoadoutGroup({ kind = "raid" })
SP:PutLoadoutInGroup(idx("Raid"), anyRaid.id)
go("Orgrimmar")
go("Zul'Gurub", "raid")
checkEq("another raid: Any Raid's first", active(), "Raid")
go("The Molten Core", "raid")
checkEq("MC: its own group wins on entry", active(), "MC Trash")
checkEq("MC: both groups show", shownNames(), "Lucifron,MC Trash,Raid,Solo")
check("Any Raid has no zone", anyRaid.zone == nil and SP:LoadoutGroupName(anyRaid) == "Any Raid")

-- the Loadouts switch
SP:SetLoadoutsOn(false)
SP:ApplyLoadout(idx("Solo"), true)
go("Orgrimmar")
go("Zul'Gurub", "raid")
checkEq("Loadouts off: no switch", active(), "Solo")
check("Loadouts off: no loadout bar", not (SP.loadoutAnchor and SP.loadoutAnchor:IsShown()))
SP:SetLoadoutsOn(true)
check("Loadouts on again: the bar", SP.loadoutAnchor and SP.loadoutAnchor:IsShown())

-- a group moved, then deleted (its loadouts go back to Everywhere)
SP:MoveLoadoutGroup(anyRaid.id, 3)
check("moved to the bottom", SP:LoadoutGroups()[3] == anyRaid)
SP:DeleteLoadoutGroup(mc.id)
check("deleted: MC Trash back in Everywhere", ShamanPower_TotemLoadouts[idx("MC Trash")].group == nil)
checkEq("two groups left", #SP:LoadoutGroups(), 2)

-- more than 8 loadouts, and the flyout makes more buttons
for g, _ in pairs(ShamanPower_LoadoutGroups) do ShamanPower_LoadoutGroups[g] = nil end
for _, lo in ipairs(ShamanPower_TotemLoadouts) do lo.group, lo.hidden = nil, nil end
SP:LoadoutGroupsChanged()
for i = 1, 6 do SP:SaveLoadout("Extra " .. i) end
checkEq("12 loadouts saved", #ShamanPower_TotemLoadouts, 12)
SP:UpdateLoadoutBar()
flyout = 0
for _, b in ipairs(SP.loadoutButtons or {}) do if not b:GetAttribute("inactive") then flyout = flyout + 1 end end
checkEq("the flyout: all 11 not in use", flyout, 11)

-- back as it was
GetRealZoneText, IsInInstance = keepZone, keepInst
ShamanPower_TotemLoadouts, ShamanPower_LoadoutGroups = keepList, keepGroups
SP.opt.activeLoadout, SP.opt.loadoutsOff, SP.opt.showLoadoutBar = keepActive, keepOff, keepBar
SP:LoadoutGroupsChanged()
SP:UpdateLoadoutBar()
finish()
