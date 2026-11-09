-- client: forever
-- (3.0.9.9) Call of the Elements Follows My Assignments on the Loadouts page too, with the other Call settings (a
-- Discord report: it was only in Drop All's right-click menu on the Totem Bar screen). The same setting: switched
-- here, the menu's switch reads it; switched on, Call of the Elements is brought in step at once.
local SP = ShamanPower
local function find(t, key, depth)
	if type(t) ~= "table" or (depth or 0) > 12 then return nil end
	if t.args then
		if t.args[key] then return t.args[key] end
		for _, v in pairs(t.args) do local r = find(v, key, (depth or 0) + 1) if r then return r end end
	end
	return nil
end
local opt = find(SP.options, "cote_sync")
check("on the Loadouts page", opt ~= nil and opt.type == "toggle")
if not opt then finish() end
checkEq("its name", opt.name, "Call of the Elements Follows My Assignments")

local keep = SP.opt.totemSetsSyncAssignments
local synced = 0
local sync = SP.SyncTotemSetFromAssignments
SP.SyncTotemSetFromAssignments = function() synced = synced + 1 end

check("on by default", (function() SP.opt.totemSetsSyncAssignments = nil return opt.get({}) end)() == true)
opt.set({}, false)
check("off here: the setting is off (the menu reads the same one)", SP.opt.totemSetsSyncAssignments == false)
check("and reads off", opt.get({}) == false)
opt.set({}, true)
check("on again: on", SP.opt.totemSetsSyncAssignments ~= false and opt.get({}) == true)
checkEq("switched on: Call of the Elements brought in step", synced, 1)

-- put back
SP.SyncTotemSetFromAssignments = sync
SP.opt.totemSetsSyncAssignments = keep
finish()
