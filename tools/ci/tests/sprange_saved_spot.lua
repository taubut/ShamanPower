-- client: both
-- (3.0.9.17, Moolnir on Discord, 11-19) "Is there a trick to getting the Totem Range element to stay put when you open
-- edit layout mode?" The frame was made at the screen's center and only ShowSPRangeOverlay moved it to its saved spot,
-- so until the tracker had shown once (solo, say), Unlock UI and the settings preview showed it in the middle. It is
-- made on its saved spot now. As at a login: a saved spot, the frame made fresh, then the preview Unlock UI uses.
local SP = ShamanPower
if not (SP.SPRangeLoaded and SP.CreateSPRangeFrame and SP.SPRangeDemo) then skip("no Totem Range Tracker here") end
SP:InitSPRange()
local keepPos = ShamanPower_RangeTracker.position
local keepFrame, keepGlobal = SP.spRangeFrame, _G.ShamanPowerRangeFrame

ShamanPower_RangeTracker.position = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 300, y = -200 }
SP.spRangeFrame = nil
local f = SP:CreateSPRangeFrame()
local function spot()
	local p, rel, rp, x, y = f:GetPoint()
	return p, rel, rp, x, y
end
local p, rel, rp, x, y = spot()
checkEq("made on its saved point", p, "TOPLEFT")
checkEq("against the screen's corner", rp, "TOPLEFT")
check("at its saved offsets", x == 300 and y == -200)
check("anchored to the screen", rel == UIParent)

-- the preview (what Unlock UI and the settings page show), before the tracker ever showed
SP:SPRangeDemo(true)
p, rel, rp, x, y = spot()
check("the preview keeps it on its saved spot", p == "TOPLEFT" and rp == "TOPLEFT" and x == 300 and y == -200)
SP:SPRangeDemo(false)

-- an old saved spot with no relPoint (from before 3.0.9.1): its point both ends, as ShowSPRangeOverlay reads it
ShamanPower_RangeTracker.position = { point = "BOTTOM", x = 0, y = 120 }
SP.spRangeFrame = nil
f = SP:CreateSPRangeFrame()
p, rel, rp, x, y = spot()
check("an old spot: its point both ends", p == "BOTTOM" and rp == "BOTTOM" and x == 0 and y == 120)

-- no saved spot: the middle, as before
ShamanPower_RangeTracker.position = nil
SP.spRangeFrame = nil
f = SP:CreateSPRangeFrame()
p, rel, rp, x, y = spot()
check("no saved spot: the middle", p == "CENTER" and rp == "CENTER" and x == 0 and y == 0)
f:Hide()

-- put back
ShamanPower_RangeTracker.position = keepPos
SP.spRangeFrame, _G.ShamanPowerRangeFrame = keepFrame, keepGlobal
finish()
