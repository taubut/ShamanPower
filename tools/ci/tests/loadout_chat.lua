-- client: both
-- (3.0.9.9) Show Loadout Changes in My Chat covers a switch you make yourself (the loadout bar, the minimap
-- menu, /spl): off, no "Activated" line (a Discord report: it printed with the setting off). On: the line, as before.
local SP = ShamanPower
if not (ShamanPower_Assignments and SP.player and ShamanPower_Assignments[SP.player]) then skip("no assignments in the sim") end
local n0 = #ShamanPower_TotemLoadouts
if n0 >= 8 then skip("8 loadouts already") end
local keepChat, keepActive = SP.opt.loadoutChat, SP.opt.activeLoadout
SP:SaveLoadout("ci chat")
local idx = #ShamanPower_TotemLoadouts
check("saved", idx == n0 + 1)

local lines = {}
local realPrint = print
print = function(...) lines[#lines + 1] = table.concat({ tostringall and tostringall(...) or ... }, " ") end
local function activated()
	for _, l in ipairs(lines) do if l:find("Activated 'ci chat'", 1, true) then return true end end
	return false
end

SP.opt.loadoutChat = nil   -- (on: the default)
wipe(lines); SP:ApplyLoadout(idx)
check("on: the Activated line", activated())
SP.opt.loadoutChat = false
wipe(lines); SP:ApplyLoadout(idx)
check("off: no Activated line", not activated())
wipe(lines); SP:ApplyLoadout(idx, true)
check("a group's own switch (quiet): never this line", not activated())

-- put back
print = realPrint
SP.opt.loadoutChat = keepChat
SP:DeleteLoadout(idx)
SP.opt.activeLoadout = keepActive
check("deleted again", #ShamanPower_TotemLoadouts == n0)
finish()
