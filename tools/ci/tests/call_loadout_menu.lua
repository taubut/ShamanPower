-- client: forever
-- A loadout's menu > Blizzard Totem Set (3.0.9.5): when that set's Call of the Ancestors / Spirits loadout was
-- never made, it's made first (as its Add button does), then the right-clicked loadout goes on the set. Made
-- once: picking the set again never makes a second one. The sim has no totem bar: its parts are stubbed.
local SP = ShamanPower
if not (SP.AddCallLoadout and SP.HasCallLoadout and SP.BindLoadoutToTotemSet) then skip("no totem sets") end
local keepList, keepBar, keepRead, keepSync, keepKnown = ShamanPower_TotemLoadouts, SP.HasTotemBar, SP.ReadTotemSet,
	SP.SyncBoundLoadout, IsPlayerSpell
SP.HasTotemBar = function() return true end
SP.ReadTotemSet = function() return {} end
SP.SyncBoundLoadout = function() return true end
IsPlayerSpell = function(id) return id == 66842 or id == 66843 or id == 66844 or keepKnown(id) end

-- what the menu does with a pick (LoadoutIcons.lua, SetRows)
local function Pick(lo, page)
	if page ~= 0 and not SP:HasCallLoadout(page) then SP:AddCallLoadout(page, true) end
	for i, l in ipairs(ShamanPower_TotemLoadouts) do
		if l == lo then SP:BindLoadoutToTotemSet(i, page) end
	end
end
local function Named(name)
	local n, found = 0, nil
	for _, l in ipairs(ShamanPower_TotemLoadouts) do if l.name == name then n = n + 1; found = l end end
	return found, n
end

local pvp = { name = "PVP", 1, 2, 1, 1 }
ShamanPower_TotemLoadouts = { pvp, { name = "Raid", 2, 5, 1, 2 } }
check("no Call of the Spirits loadout yet", not SP:HasCallLoadout(3))
Pick(pvp, 3)
local call, n = Named("Call of the Spirits")
checkEq("the Call of the Spirits loadout is made", n, 1)
check("made first in Everywhere", ShamanPower_TotemLoadouts[1] == call)
checkEq("PVP is on the set", pvp.setPage, 3)
check("the made one isn't (one loadout per set)", call.setPage == nil)
check("its Add button stays away", not SP:CallLoadoutButtonShown(3))
Pick(pvp, 0)
check("PVP off the set: the Add button is back", SP:CallLoadoutButtonShown(3))
Pick(pvp, 3)
local _, n2 = Named("Call of the Spirits")
checkEq("picked again: still one Call of the Spirits loadout", n2, 1)
-- one made by the Add button before callPage existed: its name counts
ShamanPower_TotemLoadouts = { pvp, { name = "Call of the Ancestors", 3, 6, 6, 1 } }
pvp.setPage = nil
Pick(pvp, 2)
local _, n3 = Named("Call of the Ancestors")
checkEq("an older Call of the Ancestors loadout counts: none made", n3, 1)
checkEq("PVP is on the Ancestors set", pvp.setPage, 2)

ShamanPower_TotemLoadouts, SP.HasTotemBar, SP.ReadTotemSet, SP.SyncBoundLoadout, IsPlayerSpell = keepList, keepBar,
	keepRead, keepSync, keepKnown
finish()
