-- client: both
-- (3.0.9.18, denko on Discord, 11-19, in dungeons) "calling '?' on bad self (Attempt to access forbidden object from code
-- tainted by an AddOn)", 903 times in his support code: the module watched the game's shared CompactUnitFrame_SetUnit,
-- which the nameplates go through too (forbidden ones included), and asked each frame its name. Now only the party and
-- raid frames themselves are watched, each for its own "unit" (CompactUnitFrame_SetUnit sets it on the frame), so
-- nothing else reaches the module. Here: a frame handed another player is bound to them through its own watch, and a
-- nameplate's frame is never watched.
local SP = ShamanPower
local H = SP.HealingTrackerState
if not (SP.HealingTrackerLoaded and H and H.watched) then skip("no Frame Buff Indicators here") end
local sv = ShamanPowerHealingTrackerDB
local keepEnabled = sv.enabled

local function cuf(name, unit)
	local f = _G[name] or CreateFrame("Button", name, UIParent)
	f:SetSize(72, 36)
	f:SetPoint("CENTER")
	f.unit = unit
	f:Show()
	return f
end
local p3 = cuf("CompactPartyFrameMember3", "party2")
local r5 = cuf("CompactRaidFrame5", "raid5")
local plate = cuf("NamePlate1UnitFrame", "nameplate1")   -- (a nameplate's frame, as the game names one)

sv.enabled = true
SP:UpdateHealingTracker()
check("a party frame is watched", H.watched[p3] == true)
check("a raid frame is watched", H.watched[r5] == true)
check("a nameplate's frame: never watched", H.watched[plate] == nil)
check("a nameplate's frame: nothing put on it", H.recs[plate] == nil)
local rec = H.recs[p3]
local rip, anc = rec and rec.parts.riptide, rec and rec.parts.ancestral
check("the party frame has its icons", rip ~= nil and anc ~= nil)
checkEq("bound to its player", rip and rip.unit, "party2")

-- the game hands the frame another player: CompactUnitFrame_SetUnit sets frame.unit, then its "unit" attribute
p3.unit = "party4"
p3:SetAttribute("unit", "party4")
__sim.advance(0.3)
checkEq("handed another player: bound to them through its own watch (Riptide)", rip and rip.unit, "party4")
checkEq("(Ancestral Healing too)", anc and anc.unit, "party4")

-- any other attribute: nothing new
local before = rip and rip.unit
p3:SetAttribute("*type1", "target")
__sim.advance(0.3)
checkEq("another attribute: still bound the same", rip and rip.unit, before)

-- put back
p3.unit = "party2"
p3:SetAttribute("unit", "party2")
sv.enabled = keepEnabled
SP:UpdateHealingTracker()
__sim.advance(0.3)
finish()
