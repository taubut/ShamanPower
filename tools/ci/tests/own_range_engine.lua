-- client: forever
-- regime: secrets
-- Your own range in a fight on WoW: Forever, drawn by the game (10-21): over the icon showing each
-- totem sits an engine aura slot per totem that puts an aura on you. In a fight the icon takes its
-- gray underneath and the game covers it in full color while the aura is on you, in dungeons too.
-- Nothing the bar had is gone: out of a fight the buff read decides, and the glow keeps the bar's
-- own answer (the drop spot, else the last one). The Totem Range Tracker gets the same.
local SP = ShamanPower
local W = __sim.W
local o = SP.opt
SP:RebuildOwnRangeEngine()
local btn = SP.totemButtons[3]
local e3 = SP.ownRangeEngine[3]
if not (btn and e3 and e3.main) then skip("no water button or no game-drawn slots here") end
check("water: the slots sit over the bar button", e3.main.host == btn)
local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
checkEq("water: one slot per totem with an aura on you", count(e3.main.slots), count(SP.TotemBuffSpellIDs[3]))
check("Healing Stream has its slot", e3.main.slots[2] ~= nil)
check("Mana Spring has its slot", e3.main.slots[1] ~= nil)
local e4 = SP.ownRangeEngine[4]
check("Grounding has its slot", e4 and e4.main and e4.main.slots[5] ~= nil)
local e1 = SP.ownRangeEngine[1]
check("Strength of Earth has its slot", e1 and e1.main and e1.main.slots[1] ~= nil)

-- right above the icon, under the bar's swipes and texts
local L = btn:GetFrameLevel()
checkEq("the slot is right above the icon", e3.main.slots[2]:GetFrameLevel(), L + 1)
check("the cooldown swipe stays above it", btn.cooldown and btn.cooldown:GetFrameLevel() > L + 1)
check("the GCD swipe stays above it", SP.gcdCooldowns and SP.gcdCooldowns[3] and SP.gcdCooldowns[3]:GetFrameLevel() > L + 1)
local low = 0
for _, ch in ipairs({ btn:GetChildren() }) do
	if not e3.main.mine[ch] and not ch:IsProtected() and ch:GetFrameLevel() <= L + 1 then low = low + 1 end
end
checkEq("nothing of the bar's own left at the slot's level", low, 0)
-- the bar's own party dots draw over the game's picture (the owner's report, 3.0.9.4: the red dots sat
-- under it on the Mana Tide overlay, only their rims showing)
local dots = SP.partyRangeDots and SP.partyRangeDots[3]
if dots and dots[1] then
	check("the party dots draw over the game's picture", dots[1]:GetParent():GetFrameLevel() > e3.main.slots[2]:GetFrameLevel())
end
local ovr = SP.activeTotemOverlays and SP.activeTotemOverlays[3]
local oslot = e3.overlay and e3.overlay.slots and select(2, next(e3.overlay.slots))
if ovr and ovr.dots and oslot then
	check("on the active-totem overlay too", ovr.dots[1]:GetParent():GetFrameLevel() > oslot:GetFrameLevel())
else
	check("an active-totem overlay with its slots to test", false)
end
check("all dark before any fight", e3.main.slots[2]:GetAlpha() == 0)

-- Healing Stream down; a dungeon fight (no positions)
local keep = { o.totemOwn }
local realInfo, realUB, realUnread, realPos = SP.GetElementTotemInfo, SPCompat.UnitBuff, SPCompat.AurasUnreadable, UnitPosition
local down, onMe, fight = 5394, true, false
SP.GetElementTotemInfo = function(self, e) if e == 3 then return true, GetSpellInfo(down), GetTime() - 5, 300, nil, 3 end return false end
SPCompat.UnitBuff = function(unit, i)
	if not fight and onMe and i == 1 then return SPCompat.SpellName(down == 5394 and 5672 or 5677) end
	return nil
end
SPCompat.AurasUnreadable = function() return fight end
UnitPosition = function() return nil end
local function pass() SP.totemBuffCache[3] = nil; SP:InvalidateTotemInfo(); W.fireEvent("UNIT_AURA", "player", { isFullUpdate = true }); SP:UpdatePlayerTotemRange() end
local function lit(i) local c = e3.main.slots[i] return c and c:GetAlpha() == 1 end
local overlay = SP.activeTotemOverlays and SP.activeTotemOverlays[3]
if overlay then overlay.isActive = false end
o.activeTotemAsMain = o.activeTotemAsMain

pass()
check("out of a fight, in range: the read decides (no gray, the game's slot dark)", not btn.icon:IsDesaturated() and not lit(2))
fight = true
pass()
check("in a fight: the icon grays underneath", btn.icon:IsDesaturated())
check("in a fight: Healing Stream's slot lit (the game covers the gray while its aura is on you)", lit(2))
check("in a fight: the other water slots dark", not lit(1) and not lit(3))
local g = SP.totemRangeGlows and SP.totemRangeGlows[3]
check("the glow keeps the bar's own answer (in range before the pull: none)", not (g and g.on))
down = 5675
pass()
check("Mana Spring dropped in the fight: its slot lit, Healing Stream's dark", lit(1) and not lit(2))
o.totemOwn = { [5675] = { totemRangeLook = "glow" } }
pass()
check("its look is Glow only: no gray, so nothing to cover (slot dark)", not lit(1) and not btn.icon:IsDesaturated())
o.totemOwn = keep[1]
fight = false
pass()
check("the fight over: the read decides again, every slot dark", not btn.icon:IsDesaturated() and not lit(1) and not lit(2))

-- the active-totem overlay above the button: the slots over it light instead
if overlay and e3.overlay and not o.activeTotemAsMain then
	overlay.isActive = true
	fight = true
	pass()
	local oc = e3.overlay.slots[1]
	check("on the overlay: its own slot lit, the button's dark", oc and oc:GetAlpha() == 1 and not lit(1))
	fight = false
	overlay.isActive = false
	pass()
	check("on the overlay: dark after the fight", oc and oc:GetAlpha() == 0)
end

SP.GetElementTotemInfo, SPCompat.UnitBuff, SPCompat.AurasUnreadable, UnitPosition = realInfo, realUB, realUnread, realPos
o.totemOwn = keep[1]
SP.totemBuffCache[3] = nil
SP:InvalidateTotemInfo()
SP:UpdatePlayerTotemRange()

-- the Totem Range Tracker: the same over each icon (any shaman's totem: it is about you having the buff)
local hs = SP.TrackableTotemsByID and SP.TrackableTotemsByID.healingstream
if hs and SP.CreateSPRangeTotemButton then
	local tb = SP:CreateSPRangeTotemButton(UIParent, hs, 1)
	check("tracker: a game-drawn slot over the icon", tb.spEngine ~= nil)
	checkEq("tracker: right above the icon", tb.spEngine:GetFrameLevel(), tb:GetFrameLevel() + 1)
	tb.status = "inrange"
	SP:SPRangePaint(tb, "inrange")
	SP:SPRangeEngineApply(tb, true)
	check("tracker in a fight: the icon takes its Out of Range look, the slot lit", tb.icon:IsDesaturated() and tb.spEngine:GetAlpha() == 1)
	SP:SPRangePaint(tb, "inrange")
	SP:SPRangeEngineApply(tb, false)
	check("tracker out of a fight: the slot dark, the read's look", not tb.icon:IsDesaturated() and tb.spEngine:GetAlpha() == 0)
	tb:Hide()
end
finish()
