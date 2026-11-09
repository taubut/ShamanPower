-- client: both
-- (3.0.9.9) Loadouts Remember the Totem Bar Order: changing the bar's order while a loadout is in use saves it
-- into that loadout (before, only saving a loadout took the order, so it could never be changed: a Discord
-- report). Through the real 1st to 4th Position dropdowns. Another loadout keeps its own; switch off: none.
local SP = ShamanPower
if not (ShamanPower_Assignments and SP.player and ShamanPower_Assignments[SP.player]) then skip("no assignments in the sim") end
local n0 = #ShamanPower_TotemLoadouts
if n0 >= 7 then skip("too many loadouts already") end
local keepOrder = SP.opt.totemBarOrder and { unpack(SP.opt.totemBarOrder) } or nil
local keepSwitch, keepActive = SP.opt.loadoutsRememberOrder, SP.opt.activeLoadout

-- the real dropdown: the options' "1st Position"
local function find(t, key, depth)
	if type(t) ~= "table" or (depth or 0) > 12 then return nil end
	if t.args then
		if t.args[key] then return t.args[key] end
		for _, v in pairs(t.args) do local r = find(v, key, (depth or 0) + 1) if r then return r end end
	end
	return nil
end
local first = find(SP.options, "totem_bar_order_1")
check("the 1st Position dropdown is there", first ~= nil and type(first.set) == "function")
local function order(t) return table.concat(t or {}, ",") end

SP.opt.loadoutsRememberOrder = true
SP.opt.totemBarOrder = { 1, 2, 3, 4 }
SP:SaveLoadout("ci live A")
local a = #ShamanPower_TotemLoadouts
SP:SaveLoadout("ci live B")
local b = #ShamanPower_TotemLoadouts
local A, B = ShamanPower_TotemLoadouts[a], ShamanPower_TotemLoadouts[b]
checkEq("A saved with the bar's order", order(A.order), "1,2,3,4")

SP:ApplyLoadout(a, true)
first.set({}, 3)   -- Water first
checkEq("the bar: Water first", order(SP.opt.totemBarOrder), "3,2,1,4")
checkEq("A, in use, keeps the new order", order(A.order), "3,2,1,4")
checkEq("B, not in use, keeps its own", order(B.order), "1,2,3,4")
SP:ApplyLoadout(b, true)
checkEq("switching to B puts B's order on the bar", order(SP.opt.totemBarOrder), "1,2,3,4")
SP:ApplyLoadout(a, true)
checkEq("and back to A: A's new order", order(SP.opt.totemBarOrder), "3,2,1,4")

-- a loadout saved before the switch was on (no order): it gets one this way
B.order = nil
SP:ApplyLoadout(b, true)
first.set({}, 4)
check("a loadout with no order gets the one set while it is in use", B.order ~= nil and B.order[1] == 4)

-- the switch off: the bar's order changes, no loadout's does
SP.opt.loadoutsRememberOrder = nil
local before = order(B.order)
first.set({}, 2)
checkEq("switch off: the loadout's order stays", order(B.order), before)

-- put back
SP:DeleteLoadout(b)
SP:DeleteLoadout(a)
check("deleted again", #ShamanPower_TotemLoadouts == n0)
SP.opt.loadoutsRememberOrder = keepSwitch
SP.opt.activeLoadout = keepActive
SP.opt.totemBarOrder = keepOrder
SP:UpdateMiniTotemBar()
finish()
