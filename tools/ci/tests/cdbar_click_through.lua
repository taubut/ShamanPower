-- client: both
-- (3.0.9.9) Click Through The Cooldown Bar, the bar standing on its own (a Discord report: the
-- icons ignored clicks but the cursor still stuck on the bar). Its own frame takes the mouse to be
-- dragged; under In Combat or Always it lets go with its buttons. Off: it takes the mouse as
-- before. Attached to the totem bar it never has the mouse, whatever the setting.
local SP = ShamanPower
if not (SP.ApplyClickThrough and SP.UpdateCooldownBarPosition) then skip("no Click Through here") end
local was = { show = SP.opt.showCooldownBar, locked = SP.opt.cooldownBarLocked, mode = SP.opt.cdbarClickThrough }

SP.opt.showCooldownBar = true
SP.opt.cdbarClickThrough = "off"
SP.opt.cooldownBarLocked = nil
SP:UpdateCooldownBarPosition(true); SP:RecreateCooldownBar(); __sim.advance(0.3)
local bar = SP.cooldownBar
check("the bar stands on its own", bar and bar:GetParent() == UIParent)
check("Off: the bar takes the mouse (it can be dragged)", bar:IsMouseEnabled())

local function anyButtonMouse()
	for _, b in ipairs(SP.cooldownButtons or {}) do if b:IsMouseEnabled() then return true end end
	return false
end

SP.opt.cdbarClickThrough = "always"; SP:ApplyClickThrough()
check("Always: the bar's frame lets go of the mouse", not bar:IsMouseEnabled())
check("Always: its buttons too", not anyButtonMouse())
SP:UpdateCooldownBarPosition(); __sim.advance(0.2)   -- (a profile change or a reset places it again)
check("Always: placed again, still no mouse", not bar:IsMouseEnabled())

SP.opt.cdbarClickThrough = "combat"; SP:ApplyClickThrough()
check("In Combat, out of a fight: the bar takes the mouse", bar:IsMouseEnabled())
__sim.setCombat(true); __sim.advance(0.1)
check("In Combat, in a fight: the bar lets go", not bar:IsMouseEnabled())
__sim.setCombat(false); __sim.advance(0.1)
check("In Combat, the fight over: the mouse back", bar:IsMouseEnabled())

SP.opt.cdbarClickThrough = "off"; SP:ApplyClickThrough()
check("Off again: the bar takes the mouse", bar:IsMouseEnabled())

-- attached to the totem bar: no mouse, as before, whatever the setting
SP.opt.cooldownBarLocked = true
SP:UpdateCooldownBarPosition(true); __sim.advance(0.2)
check("attached: no mouse", not bar:IsMouseEnabled())
SP.opt.cdbarClickThrough = "always"; SP:ApplyClickThrough()
SP.opt.cdbarClickThrough = "off"; SP:ApplyClickThrough(); __sim.advance(0.2)
check("attached, Off after Always: still no mouse", not bar:IsMouseEnabled())

-- put back
SP.opt.cdbarClickThrough = was.mode
SP.opt.cooldownBarLocked = was.locked
SP.opt.showCooldownBar = was.show
SP:UpdateCooldownBarPosition(true); SP:ApplyClickThrough(); __sim.advance(0.2)
finish()
