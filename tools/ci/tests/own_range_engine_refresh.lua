-- client: forever
-- regime: secrets
-- Your own range in a fight (3.0.9.6): a game-drawn slot switched on in a fight heard of no change to
-- your auras after that moment, so out of range at the pull, then the totem dropped again, the icon
-- stayed gray. While a slot is lit, each change to your auras has it read them again; asleep once
-- none is. The Totem Range Tracker's slots the same.
local SP = ShamanPower
local W = __sim.W
SP:RebuildOwnRangeEngine()
local btn = SP.totemButtons[3]
local e3 = SP.ownRangeEngine[3]
if not (btn and e3 and e3.main and e3.main.slots[2]) then skip("no water button or no game-drawn slots here") end

-- Healing Stream down; a dungeon fight (no positions), out of range at the pull
local realInfo, realUB, realUnread, realPos = SP.GetElementTotemInfo, SPCompat.UnitBuff, SPCompat.AurasUnreadable, UnitPosition
local fight = false
SP.GetElementTotemInfo = function(self, e) if e == 3 then return true, GetSpellInfo(5394), GetTime() - 5, 300, nil, 3 end return false end
SPCompat.UnitBuff = function() return nil end
SPCompat.AurasUnreadable = function() return fight end
UnitPosition = function() return nil end
local overlay = SP.activeTotemOverlays and SP.activeTotemOverlays[3]
if overlay then overlay.isActive = false end
local function pass() SP.totemBuffCache[3] = nil; SP:InvalidateTotemInfo(); SP:UpdatePlayerTotemRange() end

-- count the fresh reads each slot is asked for
local reads = {}
local function spy(c) if c and not reads[c] then reads[c] = 0; c.UpdateAllAuras = function(self) reads[self] = reads[self] + 1 end end end
for _, c in pairs(e3.main.slots) do spy(c) end
local hs = e3.main.slots[2]
local function aura() W.fireEvent("UNIT_AURA", "player", { addedAuras = {} }) end

pass()
reads[hs] = 0
aura()
checkEq("out of a fight: no fresh reads (nothing lit)", reads[hs], 0)

fight = true
pass()
check("in a fight: Healing Stream's slot lit", hs:GetAlpha() == 1)
reads[hs] = 0
aura()
checkEq("your auras change in the fight: the lit slot reads them again", reads[hs], 1)
aura()
checkEq("and again on the next change", reads[hs], 2)
local others = 0
for i, c in pairs(e3.main.slots) do if i ~= 2 then others = others + reads[c] end end
checkEq("the dark slots are not asked", others, 0)

fight = false
pass()
check("the fight over: the slot dark", hs:GetAlpha() == 0)
reads[hs] = 0
aura()
aura()
checkEq("after the fight: asleep, no fresh reads", reads[hs], 0)

SP.GetElementTotemInfo, SPCompat.UnitBuff, SPCompat.AurasUnreadable, UnitPosition = realInfo, realUB, realUnread, realPos
SP.totemBuffCache[3] = nil
SP:InvalidateTotemInfo()
SP:UpdatePlayerTotemRange()

-- the Totem Range Tracker
local hsData = SP.TrackableTotemsByID and SP.TrackableTotemsByID.healingstream
if hsData and SP.CreateSPRangeTotemButton then
	local tb = SP:CreateSPRangeTotemButton(UIParent, hsData, 1)
	check("tracker: a game-drawn slot over the icon", tb.spEngine ~= nil)
	if tb.spEngine then
		local keepFrame = SP.spRangeFrame
		SP.spRangeFrame = { totemButtons = { healingstream = tb } }
		spy(tb.spEngine)
		tb.status = "inrange"
		SP:SPRangeEngineApply(tb, true)
		reads[tb.spEngine] = 0
		aura()
		checkEq("tracker in a fight: your auras change, its slot reads them again", reads[tb.spEngine], 1)
		SP:SPRangeEngineApply(tb, false)
		reads[tb.spEngine] = 0
		aura()
		aura()
		checkEq("tracker after the fight: asleep, no fresh reads", reads[tb.spEngine], 0)
		SP.spRangeFrame = keepFrame
	end
	tb:Hide()
end
finish()
