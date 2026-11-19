-- client: both
-- (3.0.9.18, denko on Discord, 11-19, in dungeons) "calling '?' on bad self (Attempt to access forbidden object from code tainted
-- by an AddOn)", 17 times, from the hook on CompactUnitFrame_SetUnit: the game's nameplates go through it too, forbidden
-- ones included, and the hook asked each frame its name. A forbidden frame refuses every call, so the hook never asks a
-- frame anything now: a frame is ours if it IS one of the game's party or raid frames. (The sim has no
-- CompactUnitFrame_SetUnit, so the hook's check is called here as the hook calls it.)
local SP = ShamanPower
if not (SP.HealingTrackerLoaded and SP.HealingTrackerState and SP.HealingTrackerState.kindOf) then
	skip("no Frame Buff Indicators here")
end
local kindOf = SP.HealingTrackerState.kindOf

-- a forbidden nameplate: any use of it besides being compared fails, as in the game
local touched = 0
local plate = setmetatable({}, { __index = function()
	touched = touched + 1
	error("Attempt to access forbidden object from code tainted by an AddOn")
end })
local ok, kind = pcall(kindOf, plate)
check("a forbidden nameplate: no error", ok, tostring(kind))
check("not one of ours", ok and kind == nil)
checkEq("never asked anything", touched, 0)

-- the game's own frames still count, by what they are
local function frame(name)
	return _G[name] or CreateFrame("Button", name, UIParent)
end
checkEq("a party frame", kindOf(frame("CompactPartyFrameMember2")), "party")
checkEq("a raid frame", kindOf(frame("CompactRaidFrame7")), "raid")
checkEq("a raid group's frame", kindOf(frame("CompactRaidGroup3Member4")), "raid")
checkEq("a pet's frame: never", kindOf(frame("CompactPartyFramePet1")), nil)
checkEq("a frame of another addon's: not ours", kindOf(CreateFrame("Button", nil, UIParent)), nil)
finish()
