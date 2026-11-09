-- client: forever
-- (3.0.9.9, sheet A91) Other > Minimap Totems: the minimap markers' own page (they were at the bottom of Totem Range
-- Tracker, which looks switched off with the tracker off: a Discord report). The same settings, gone from the
-- tracker page; new: Marker Opacity, Ring Opacity (65% = before) and a ring per element. Drawn: a Windfury Totem
-- down beside you, with a stand-in for your place in the world (the sim has none).
local SP = ShamanPower
local ST = __sim.ST
check("the minimap markers are available (WoW: Forever)", SP.MinimapTotemsAvailable == true)
local F = SP.options.args.fluffy.args
local page = F.minimaptotems_section
check("Other > Minimap Totems is there", page ~= nil and page.args ~= nil)
if not page then finish() end
check("it shows for a shaman", not page.hidden())
local KEYS = { "minimapTotemMarkers", "minimapTotemRings", "minimapTotemPinSize", "minimapRingColorMode", "minimapRingColor1",
	"minimapRingColor2", "minimapRingColor3", "minimapRingColor4", "minimapMarkerOpacity", "minimapRingOpacity",
	"minimapRing1", "minimapRing2", "minimapRing3", "minimapRing4" }
local onPage, offTracker = 0, 0
for _, k in ipairs(KEYS) do
	if page.args[k] then onPage = onPage + 1 end
	if not F.sprange_section.args[k] then offTracker = offTracker + 1 end
end
checkEq("every minimap setting on the page", onPage, #KEYS)
checkEq("none left on Totem Range Tracker", offTracker, #KEYS)

-- your place in the world: the middle of map 1, continent 1, 1000 yards a side
local keep = { UnitPosition = UnitPosition, pos = C_Map.GetPlayerMapPosition, world = C_Map.GetWorldPosFromMapPos,
	info = SP.GetElementTotemInfo, index = SP.GetActiveTotemIndex, drop = SP.totemDropPos and SP.totemDropPos[4] }
UnitPosition = function() return 200, 100, 0, 1 end
C_Map.GetPlayerMapPosition = function() return CreateVector2D(0.5, 0.5) end
C_Map.GetWorldPosFromMapPos = function(_, v) return 1, CreateVector2D(200 + (v.x - 0.5) * 1000, 100 + (v.y - 0.5) * 1000) end
-- a Windfury Totem (a totem with a range) dropped where you stand
local windIndex
for _, t in ipairs(SP.TrackableTotems or {}) do if t.element == 4 and not windIndex then windIndex = t.index end end
check("an Air totem with a range", windIndex ~= nil)
SP.GetElementTotemInfo = function(self, element)
	if element == 4 then return true, "Windfury Totem", GetTime() - 1, 120, 136114 end
	return false
end
SP.GetActiveTotemIndex = function(self, element) if element == 4 then return windIndex end return 0 end
SP.totemDropPos = SP.totemDropPos or {}
SP.totemDropPos[4] = { x = 100, y = 200, map = 1 }

local o = SP.opt
local before = { o.minimapMarkerOpacity, o.minimapRingOpacity, o.minimapRing4, o.minimapTotemMarkers, o.minimapTotemRings }
o.minimapMarkerOpacity, o.minimapRingOpacity, o.minimapRing4, o.minimapTotemMarkers, o.minimapTotemRings = nil, nil, nil, nil, nil
SP:RefreshMinimapTotems()
local pin = SP.minimapTotemPins[4]
check("the Air marker is up", pin ~= nil and pin.active == true)
if not (pin and pin.active) then finish() end
local function ringA() local c = ST[pin.lines[1]].color return c and math.floor(c[4] * 100 + 0.5) end
local function markA() return math.floor(pin.mark:GetAlpha() * 100 + 0.5) end
check("with its ring", pin.radius ~= nil)
checkEq("the ring at 65%, as before", ringA(), 65)
checkEq("the marker solid, as before", markA(), 100)

page.args.minimapRingOpacity.set({}, 0.3)
checkEq("Ring Opacity 30%", ringA(), 30)
page.args.minimapMarkerOpacity.set({}, 0.5)
checkEq("Marker Opacity 50%", markA(), 50)
checkEq("the ring keeps its own", ringA(), 30)
page.args.minimapRing4.set({}, false)
check("Air Totems off: no ring, the marker stays", pin.radius == nil and pin.active == true)
page.args.minimapRing1.set({}, false)
page.args.minimapRing4.set({}, true)
check("Air Totems on again (Earth's off): its ring is back", pin.radius ~= nil)
page.args.minimapRing1.set({}, true)

-- the sidebar's switch is Totem markers on the minimap
check("on: the marker is on the minimap", pin:IsShown())
o.minimapTotemMarkers = false; SP:RefreshMinimapTotems()
check("switched off: no marker", not pin:IsShown())

-- put back
UnitPosition, C_Map.GetPlayerMapPosition, C_Map.GetWorldPosFromMapPos = keep.UnitPosition, keep.pos, keep.world
SP.GetElementTotemInfo, SP.GetActiveTotemIndex, SP.totemDropPos[4] = keep.info, keep.index, keep.drop
o.minimapMarkerOpacity, o.minimapRingOpacity, o.minimapRing4, o.minimapTotemMarkers, o.minimapTotemRings =
	before[1], before[2], before[3], before[4], before[5]
SP:RefreshMinimapTotems()
finish()
