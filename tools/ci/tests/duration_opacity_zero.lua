-- client: both
-- (3.0.9.14) nano's ask on Discord (11-15): Duration Bar Opacity down to 0%, so the duration bars go and their time
-- text stays (Duration Bar Position: None takes the text away too). The slider now starts at 0%. Pulse Bar Opacity
-- too (the owner: "yes please"): its bar goes, its countdown text (on the bar's frame, not the bar) stays.
local SP = ShamanPower
local W = __sim.W
local o = SP.opt
local keep = { a = o.durationBarOpacity, loc = o.durationTextLocation, pos = o.durationBarPosition }

-- the slider reaches 0%
local row
local function find(t)
	if type(t) ~= "table" then return end
	if t.name == "Duration Bar Opacity" and t.type == "range" then row = t return end
	for _, v in pairs(t.args or {}) do if not row then find(v) end end
end
find(SP.options)
check("the slider is there", row ~= nil)
checkEq("it starts at 0%", row and row.min, 0)

-- a totem down, its time below the bar, the bar at 0%
o.durationBarPosition, o.durationTextLocation = "bottom", "below"
local e = 1
local idx
for i in pairs(SP.Totems[e]) do if SP:KnowsTotem(e, i) then idx = i break end end
if not idx then skip("no known Earth totem here") end
local id = SP:GetTotemSpell(e, idx)
local slot = SP.ElementToSlot[e]
__sim.A.totems[slot] = { GetSpellInfo(id), GetTime() - 10, 120, nil, id }
SP:InvalidateTotemInfo()
row.set(nil, 0)
SP:UpdateTotemProgressBarPositions()
W.fireEvent("PLAYER_TOTEM_UPDATE", slot)
__sim.advance(0.5)
local bars = SP.totemProgressBars and SP.totemProgressBars[e]
check("its bars are there", bars and bars.bar and bars.bg)
checkEq("0% saved as 0", o.durationBarOpacity, 0)
checkEq("the bar is gone (alpha 0)", bars.bar:GetAlpha(), 0)
checkEq("and its dark track", bars.bg:GetAlpha(), 0)
local text = bars.belowBarText
check("the time text still shows", text and text:IsShown() and (text:GetText() or "") ~= "", tostring(text and text:GetText()))
check("at full opacity", text and text:GetEffectiveAlpha() > 0.99, tostring(text and text:GetEffectiveAlpha()))

-- back to full
row.set(nil, 1)
checkEq("100%: saved as nothing (the default)", o.durationBarOpacity, nil)
checkEq("the bar back", bars.bar:GetAlpha(), 1)

-- Pulse Bar Opacity reaches 0% too
local prow
local function findP(t)
	if type(t) ~= "table" then return end
	if t.name == "Pulse Bar Opacity" and t.type == "range" then prow = t return end
	for _, v in pairs(t.args or {}) do if not prow then findP(v) end end
end
findP(SP.options)
check("the Pulse Bar Opacity slider is there", prow ~= nil)
checkEq("it starts at 0%", prow and prow.min, 0)
local keepP = o.pulseBarOpacity
prow.set(nil, 0)
checkEq("0% saved as 0", o.pulseBarOpacity, 0)
prow.set(nil, 1)
checkEq("100%: saved as nothing", o.pulseBarOpacity, nil)
o.pulseBarOpacity = keepP

__sim.A.totems[slot] = nil
SP:InvalidateTotemInfo()
W.fireEvent("PLAYER_TOTEM_UPDATE", slot)
o.durationBarOpacity, o.durationTextLocation, o.durationBarPosition = keep.a, keep.loc, keep.pos
SP:ApplyDurationBarOpacity()
SP:UpdateTotemProgressBarPositions()
finish()
