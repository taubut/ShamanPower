-- client: both
-- (3.0.9.10) Shield Charges, dragged by hand: after a drag the game anchors the frame to the screen corner or
-- edge it is nearest, not by its center, and those offsets were saved as center offsets, so the shield jumped
-- on the next load (a support ticket: Lightning Shield saved off the left edge). The spot is now measured from
-- the frame's own center. Unlock UI's drop (a center anchor) saves its offsets as they are. And Reset This
-- Shield Display puts a moved shield back on its starting spot (a shield off the screen could not be reached).
local SP = ShamanPower
if not (SP.CreateShieldChargeDisplays and SP.SetShieldSpot and SP.ShieldIconsRow) then skip("no Shield Charges here") end
if not (SP.shieldChargeFrames and SP.shieldChargeFrames.player) then SP:CreateShieldChargeDisplays() end
local f = SP.shieldChargeFrames.player
check("the Lightning Shield frame", f ~= nil)
SP:EnsureProfileTable("shieldChargeDisplay")
local s = SP.opt.shieldChargeDisplay
local keep = { s.xLS, s.yLS, s.locked }
s.locked = nil
local function near(a, b) return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 1 end

-- a drag by hand that the game leaves anchored to the right edge
f:ClearAllPoints(); f:SetPoint("RIGHT", UIParent, "RIGHT", -300, -50)
__sim.advance(0.05)
local cx, cy = f:GetCenter()
local ux, uy = UIParent:GetCenter()
f:GetScript("OnDragStop")(f)
check("saved where it is: x", near(s.xLS, cx - ux), tostring(s.xLS) .. " vs " .. tostring(cx - ux))
check("saved where it is: y", near(s.yLS, cy - uy), tostring(s.yLS) .. " vs " .. tostring(cy - uy))
check("on the screen", math.abs(s.xLS or 1e9) < UIParent:GetWidth() / 2)
local p, _, rp = f:GetPoint()
check("anchored by its center now", p == "CENTER" and rp == "CENTER")
__sim.advance(0.05)
local cx2, cy2 = f:GetCenter()
check("and it did not move", near(cx2, cx) and near(cy2, cy))

-- Unlock UI's drop: a center anchor, saved as it is
f:ClearAllPoints(); f:SetPoint("CENTER", UIParent, "CENTER", -474, -43)
f:GetScript("OnDragStop")(f)
check("a center anchor: its offsets as they are", s.xLS == -474 and s.yLS == -43)

-- off the screen, then Reset This Shield Display in its menu
SP:SetShieldSpot(1, -1170, -220)
check("moved: it has a spot of its own", SP:ShieldSpotMoved(1))
local reset
for _, it in ipairs(SP.ShieldIconsRow and SP.ShieldIconsRow.def.menu({ key = "LS" }) or {}) do
	if it.text == "Reset This Shield Display" then reset = it end
end
check("its menu has Reset This Shield Display, on", reset ~= nil and not reset.disabled)
if reset then reset.onClick(); __sim.advance(0.2) end
check("back on its starting spot", s.xLS == nil and s.yLS == nil and not SP:ShieldSpotMoved(1))
local _, _, _, fx, fy = f:GetPoint()
check("and the frame with it", near(fx, -50))

-- put back
s.xLS, s.yLS, s.locked = keep[1], keep[2], keep[3]
if SP.ResetShieldSpot and keep[1] == nil then SP:ResetShieldSpot(1) end
finish()
