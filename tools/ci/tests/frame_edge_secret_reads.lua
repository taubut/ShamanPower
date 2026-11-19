-- client: forever
-- (3.0.9.17) The owner's /sperrors after a Profile by Spec switch (11-17): "ShamanPowerTextures.lua:859: attempt to
-- perform boolean test on a secret boolean value", from Totem Coverage's green border copy. That copy sits inside
-- the game's aura buttons, where WoW: Forever answers IsShown with a secret (and its docs list the frame level and
-- colors as aspects that can be secret too); the switch to a profile with no Frame Edges repainted it. Frame Edges
-- never test those as plain values now: the edge is drawn or hidden either way, with no error.
local SP = ShamanPower
local o = SP.opt
if not (SP.PaintFrameEdgeOnce and __sim.secret) then skip("no Frame Edges here") end
local keepEdge, keepGrad = o.frameEdge, o.outlineGradient

-- (the sim's backdrops carry no backdropInfo: a frame that has one, in the copy's green)
local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
f:SetBackdrop(SP.PANEL_BACKDROP); f.backdropInfo = SP.PANEL_BACKDROP; f:SetBackdropBorderColor(0, 1, 0, 1)
o.frameEdge = "thick"
SP:PaintFrameEdgeOnce(f, true)
local e = f.spEdge
check("Thick: the edge is drawn", e ~= nil and e:IsShown())
if not e then finish() return end

-- as inside the game's aura buttons: what is read back is a secret
local asked = 0
local realShown = e.IsShown
e.IsShown = function() asked = asked + 1 return __sim.secret("shown") end
f.GetFrameLevel = function() return __sim.secret("level") end
f.GetBackdropBorderColor = function() local s = __sim.secret("color") return s, s, s, s end

-- the profile switched to has no Frame Edges (Plain), then Drop Shadow (none on the copy)
for _, kind in ipairs({ false, "shadow" }) do
	o.frameEdge = kind or nil
	asked = 0
	local ok, err = pcall(SP.PaintFrameEdgeOnce, SP, f, true)
	local name = kind and "Drop Shadow" or "Plain"
	check(name .. ": no error", ok, tostring(err))
	checkEq(name .. ": its shown state never asked", asked, 0)
	e.IsShown = realShown
	check(name .. ": the edge hidden", not e:IsShown())
	e.IsShown = function() asked = asked + 1 return __sim.secret("shown") end
end

-- a profile with an edge (and Outline Gradient): drawn, with no error
o.outlineGradient = "shade"
for _, kind in ipairs({ "thick", "bevel" }) do
	o.frameEdge = kind
	local ok, err = pcall(SP.PaintFrameEdgeOnce, SP, f, true)
	check(kind .. " with secret reads: no error", ok, tostring(err))
	e.IsShown = realShown
	check(kind .. ": the edge drawn", e:IsShown())
	e.IsShown = function() asked = asked + 1 return __sim.secret("shown") end
end

-- frames outside the game's buttons: as before
local g = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
g:SetBackdrop(SP.PANEL_BACKDROP); g.backdropInfo = SP.PANEL_BACKDROP; g:SetBackdropBorderColor(0.2, 0.4, 0.6, 1)
g:SetFrameLevel(10)
o.outlineGradient = nil
o.frameEdge = "thick"
SP:PaintFrameEdgeOnce(g)
local ge = g.spEdge
check("a plain frame: Thick drawn under it", ge and ge:IsShown() and ge:GetFrameLevel() == 9)
local r, gg, b = ge:GetBackdropBorderColor()
check("a plain frame: Thick in its border color", r and math.abs(r - 0.2) < 0.01 and math.abs(gg - 0.4) < 0.01 and math.abs(b - 0.6) < 0.01)
o.frameEdge = nil
SP:PaintFrameEdgeOnce(g)
check("a plain frame: Plain hides it", not ge:IsShown())

o.frameEdge, o.outlineGradient = keepEdge, keepGrad
finish()
