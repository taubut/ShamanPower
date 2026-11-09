-- client: both
-- Totem Coverage: Click Through (Off / In Combat / Always), as the Totem Bar's (the owner kept
-- right-clicking the list in fights, which opened its settings). Off: the list takes the mouse as
-- before. Always: never. In Combat: not during a fight, back after it. Freely placed totems the same.
local SP = ShamanPower
if not (SP.CreateCoverageFrame and SP.ApplyCoverageClickThrough) then skip("no Totem Coverage here") end
SP.opt.coverage = SP.opt.coverage or {}
local co = SP.opt.coverage
co.enabled = true
local frame = SP:CreateCoverageFrame()
check("off to start", SP:CoverageClickThrough() == "off")
check("off: the list takes the mouse", frame:IsMouseEnabled())

co.clickThrough = "always"; SP:ApplyCoverageClickThrough()
check("Always: the list ignores the mouse", not frame:IsMouseEnabled())

co.clickThrough = "combat"; SP:ApplyCoverageClickThrough()
check("In Combat, out of a fight: the list takes the mouse", frame:IsMouseEnabled())
__sim.setCombat(true); __sim.advance(0.1)
check("In Combat, in a fight: the list ignores the mouse", not frame:IsMouseEnabled())
__sim.setCombat(false); __sim.advance(0.1)
check("In Combat, the fight over: the mouse back", frame:IsMouseEnabled())

-- a freely placed totem follows it
local cell
for _, b in pairs(frame.totemCells or {}) do cell = b break end
if cell then
	cell:SetParent(UIParent)
	co.clickThrough = "always"; SP:ApplyCoverageClickThrough()
	check("a freely placed totem ignores the mouse too", not cell:IsMouseEnabled())
	co.clickThrough = nil; SP:ApplyCoverageClickThrough()
	check("Off again: it takes the mouse", cell:IsMouseEnabled())
	cell:SetParent(frame)
end
co.clickThrough = nil; SP:ApplyCoverageClickThrough()
check("Off: the list takes the mouse again", frame:IsMouseEnabled())
finish()
