-- client: both
-- (3.0.9.9) Loadouts Remember the Totem Bar and Drop Order: a loadout keeps the order Drop All drops its totems
-- in (a Discord ask: a drop order per loadout), as it keeps the bar's order. Saved with the loadout, changed while
-- it is in use (the real Drop Order dropdown), put back on a switch; Drop All and SP_DropAll read it. A loadout
-- saved before (no Drop Order of its own) leaves the Drop Order alone; the switch off: none of this.
local SP = ShamanPower
if not (ShamanPower_Assignments and SP.player and ShamanPower_Assignments[SP.player]) then skip("no assignments in the sim") end
local n0 = #ShamanPower_TotemLoadouts
if n0 >= 6 then skip("too many loadouts already") end
local function copy(t) return t and { t[1], t[2], t[3], t[4] } or nil end
local keepDrop, keepBar = copy(SP.opt.dropOrder), copy(SP.opt.totemBarOrder)
local keepSwitch, keepActive = SP.opt.loadoutsRememberOrder, SP.opt.activeLoadout

local function find(t, key, depth)
	if type(t) ~= "table" or (depth or 0) > 12 then return nil end
	if t.args then
		if t.args[key] then return t.args[key] end
		for _, v in pairs(t.args) do local r = find(v, key, (depth or 0) + 1) if r then return r end end
	end
	return nil
end
local first = find(SP.options, "drop_order_1")
check("the Drop Order's first dropdown is there", first ~= nil and type(first.set) == "function")
local function order(t) return table.concat(t or {}, ",") end

SP.opt.loadoutsRememberOrder = true
SP.opt.dropOrder = { 1, 2, 3, 4 }
SP.opt.totemBarOrder = { 1, 2, 3, 4 }
SP:SaveLoadout("ci drop A")
local a = #ShamanPower_TotemLoadouts
SP:SaveLoadout("ci drop B")
local b = #ShamanPower_TotemLoadouts
local A, B = ShamanPower_TotemLoadouts[a], ShamanPower_TotemLoadouts[b]
checkEq("A saved with the Drop Order", order(A.dropOrder), "1,2,3,4")

SP:ApplyLoadout(a, true)
first.set({}, 4)   -- Air dropped first
checkEq("Drop Order: Air first", order(SP.opt.dropOrder), "4,2,3,1")
checkEq("A, in use, keeps it", order(A.dropOrder), "4,2,3,1")
checkEq("B keeps its own", order(B.dropOrder), "1,2,3,4")
checkEq("the bar's order untouched", order(SP.opt.totemBarOrder), "1,2,3,4")
SP:ApplyLoadout(b, true)
checkEq("switching to B: B's Drop Order", order(SP.opt.dropOrder), "1,2,3,4")
SP:ApplyLoadout(a, true)
checkEq("back to A: A's Drop Order", order(SP.opt.dropOrder), "4,2,3,1")
check("A's tooltip names it", (SP:GetLoadoutDescription(a) or ""):find("Drop order: Air, Fire, Water, Earth", 1, true) ~= nil)

-- a loadout saved before (no Drop Order of its own): the Drop Order stays as it is
B.dropOrder = nil
SP:ApplyLoadout(b, true)
checkEq("an old loadout: the Drop Order as it was", order(SP.opt.dropOrder), "4,2,3,1")

-- the switch off: a switch puts no Drop Order back, a change saves none
SP.opt.loadoutsRememberOrder = nil
SP:ApplyLoadout(a, true)
first.set({}, 2)
checkEq("switch off: A's Drop Order stays", order(A.dropOrder), "4,2,3,1")
SP:ApplyLoadout(b, true)
checkEq("switch off: the Drop Order stays with a switch", order(SP.opt.dropOrder), order({ 2, 4, 3, 1 }))

-- put back
SP:DeleteLoadout(b)
SP:DeleteLoadout(a)
check("deleted again", #ShamanPower_TotemLoadouts == n0)
SP.opt.loadoutsRememberOrder = keepSwitch
SP.opt.activeLoadout = keepActive
SP.opt.dropOrder, SP.opt.totemBarOrder = keepDrop, keepBar
SP:UpdateMiniTotemBar(); SP:UpdateDropAllButton()
finish()
