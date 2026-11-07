-- client: forever
-- regime: secrets
-- Totem Coverage in a fight in a dungeon (3.0.9.6): no positions and no buff reads there, so the cell's
-- border went neutral gray. Now the game draws "everyone has it": one game-drawn slot per member, each
-- inside the one before, the cell's green border in the last, over a red border. The names and dots
-- are untouched; out of a fight and outdoors nothing changes; a party changed in the fight keeps the gray.
local SP = ShamanPower
local o = SP.opt
if not (SP.CoverageAvailable and SP:CoverageAvailable()) then skip("no game-drawn slots here") end

-- a party of two, both near
local names = { party1 = "Grak", party2 = "Mosh" }
local far = {}
local real = { UnitExists = UnitExists, UnitName = UnitName, UnitClass = UnitClass, UnitIsVisible = UnitIsVisible,
	IsInGroup = IsInGroup, GetNumSubgroupMembers = GetNumSubgroupMembers, UnitPosition = UnitPosition,
	info = SP.GetElementTotemInfo, buff = SP.GetActiveTotemBuffName, unread = SPCompat.AurasUnreadable,
	has = SP.UnitHasBuff }
UnitExists = function(u) if names[u] then return true end return real.UnitExists(u) end
UnitName = function(u) if names[u] then return names[u] end return real.UnitName(u) end
UnitClass = function(u) if names[u] then return "Warrior", "WARRIOR", 1 end return real.UnitClass(u) end
UnitIsVisible = function(u) if names[u] then return not far[u] end return real.UnitIsVisible(u) end
IsInGroup = function() return true end
GetNumSubgroupMembers = function() return 2 end
UnitPosition = function() return nil end

-- Strength of Earth (or the first earth totem with a buff) down
local idx = next(SP.TotemBuffSpellIDs[1])
local buffName = GetSpellInfo(SP.TotemBuffSpellIDs[1][idx])
SP.GetElementTotemInfo = function(self, e) if e == 1 then return true, "Earth Totem", GetTime() - 5, 120, 136098 end return false end
SP.GetActiveTotemBuffName = function(self, e) if e == 1 then return buffName, idx end return nil end
local fight, everyone = false, true
SPCompat.AurasUnreadable = function() return fight end
SP.UnitHasBuff = function(self, unit, name, element) return everyone end

local keep = o.coverage
o.coverage = { enabled = true, hideWhenCovered = false }
SP:RebuildCoverage()
local cell = SP.coverageFrame and SP.coverageFrame.buttons[1]
check("the earth cell is there", cell ~= nil)
local chain = cell and cell.coverAll
check("a slot per member, the green border in the last", chain and #chain.containers == 2 and chain.ring ~= nil)
if not (chain and chain.ring) then finish() return end

-- the green border sits inside both members' game-drawn buttons: shown only while both are
local buttons, p = {}, chain.ring:GetParent()
while p and p ~= cell do
	if p:GetObjectType() == "AuraButton" then buttons[#buttons + 1] = p end
	p = p:GetParent()
end
checkEq("inside both members' buttons", #buttons, 2)
check("covers the cell exactly", select(2, chain.ring:GetPoint(1)) == cell)
check("just over the cell's own border", chain.ring:GetFrameLevel() == cell:GetFrameLevel() + 1)
local r, g, b = chain.ring:GetBackdropBorderColor()
check("in the cell's covered green", r == 0 and g == 1 and b == 0)
local cr, cg, cb, ca = chain.ring:GetBackdropColor()
check("no fill: the icon shows through", (ca or 0) == 0)

-- out of a fight: as always (the read decides), the game's green off
SP:UpdateCoverage()
checkEq("out of a fight: covered (the read)", cell.state, "covered")
check("out of a fight: the game's green off", cell.coverAllHolder:GetAlpha() == 0)

-- a dungeon fight
fight = true
SP:UpdateCoverage()
checkEq("dungeon fight: the game's answer", cell.state, "engine")
local br, bg = cell.visual:GetBackdropBorderColor()
check("dungeon fight: red under it", br == 0.8 and bg == 0)
check("dungeon fight: no red tint, no count", not cell.rangeOverlay:IsShown() and not cell.statusText:IsShown())
check("dungeon fight: the game's green on", cell.coverAllHolder:GetAlpha() == 1)
cell:Show()
for _, btn in ipairs(buttons) do btn:Show() end
check("both have it: the green shows", chain.ring:IsVisible())
buttons[2]:Hide()
check("one without it: no green (red)", not chain.ring:IsVisible())
buttons[2]:Show()

far.party2 = true
SP:UpdateCoverage()
check("a member plainly far away: no green", cell.coverAllHolder:GetAlpha() == 0 and cell.state == "engine")
far.party2 = nil
o.coverage.plainIcon = true
SP:UpdateCoverage()
local pr, pg, pb = cell.visual:GetBackdropBorderColor()
local P = SP.PANEL_BORDER
check("Plain Totem Icon: the plain border, no green", cell.coverAllHolder:GetAlpha() == 0 and pr == P[1] and pg == P[2] and pb == P[3])
o.coverage.plainIcon = nil

-- the party changed in the fight: the old way (gray) until the rebuild at regen
SP._coveragePending = true
SP:UpdateCoverage()
checkEq("party changed in the fight: neutral gray as before", cell.state, "combat")
check("party changed in the fight: no green", cell.coverAllHolder:GetAlpha() == 0)
SP._coveragePending = false

-- Frame Edges / Outline Gradient: the copy is painted again with the cell's edge, out of a fight only
-- (it sits inside the game's aura buttons); Drop Shadow stays the cell's own
fight = false
local edgeKeep, paints, locked = o.frameEdge, {}, false
local realPaint, realLocked = SP.PaintFrameEdgeOnce, SP.GameAuraButtonsLocked
SP.PaintFrameEdgeOnce = function(self, f, noShadow) paints[#paints + 1] = { f = f, noShadow = noShadow } return realPaint(self, f, noShadow) end
SP.GameAuraButtonsLocked = function() return locked end
locked = true
SP:SetFrameEdge("thick")
SP:UpdateCoverage()
checkEq("edge changed in a fight: the copy waits", #paints, 0)
locked = false
SP:UpdateCoverage()
local rings, mine = 0, false
for e = 1, 4 do local c = SP.coverageFrame.buttons[e].coverAll if c and c.ring then rings = rings + 1 end end
for _, pt in ipairs(paints) do if pt.f == chain.ring and pt.noShadow == true then mine = true end end
check("out of the fight: every cell's copy painted once, without a shadow of its own", mine and #paints == rings)
SP:UpdateCoverage()
checkEq("then not again every pass", #paints, rings)
SP.PaintFrameEdgeOnce, SP.GameAuraButtonsLocked = realPaint, realLocked
-- (the sim's backdrops carry no backdropInfo, so the edge itself is drawn on a frame that has one)
local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
f:SetBackdrop(SP.PANEL_BACKDROP); f.backdropInfo = SP.PANEL_BACKDROP; f:SetBackdropBorderColor(0, 1, 0, 1)
SP:PaintFrameEdgeOnce(f, true)
check("Thick: the copy gets the edge", f.spEdge ~= nil and f.spEdge:IsShown())
SP:SetFrameEdge("shadow")
SP:PaintFrameEdgeOnce(f, true)
check("Drop Shadow: none on the copy", not f.spEdge:IsShown())
SP:PaintFrameEdgeOnce(f)
check("Drop Shadow: a frame that wants one still gets it", f.spEdge:IsShown())
f:Hide()
SP:SetFrameEdge(edgeKeep)
SP:UpdateCoverage()

-- the settings preview: the live green never draws over the sample cells
fight = true
SP:UpdateCoverage()
SP:CoverageDemo(true)
check("preview: the game's green off", cell.coverAllHolder:GetAlpha() == 0)
SP:CoverageDemo(false)

UnitExists, UnitName, UnitClass, UnitIsVisible = real.UnitExists, real.UnitName, real.UnitClass, real.UnitIsVisible
IsInGroup, GetNumSubgroupMembers, UnitPosition = real.IsInGroup, real.GetNumSubgroupMembers, real.UnitPosition
SP.GetElementTotemInfo, SP.GetActiveTotemBuffName, SPCompat.AurasUnreadable, SP.UnitHasBuff = real.info, real.buff, real.unread, real.has
o.coverage = keep
SP:RebuildCoverage()
finish()
