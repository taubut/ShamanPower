-- client: both
-- (3.0.9.14) A CurseForge report from battlegrounds: "ShamanPowerTextures.lua:1014: calling 'GetTexCoord' on bad
-- self (Attempt to access forbidden object from code tainted by an AddOn)", from ApplyIconShapes when a bar was
-- built again. A shaped icon drawn on the game's own aura buttons (Maelstrom Weapon, Clearcasting) had been made
-- forbidden by the game. A forbidden part is left as it is now: every other icon still takes its shape.
local SP = ShamanPower
local o = SP.opt
local was = { o.iconShape, o.iconShapeReady }
local errs = {}
local geh = geterrorhandler
geterrorhandler = function() return function(err) errs[#errs + 1] = tostring(err) end end

-- a part like Maelstrom Weapon's icon: shaped, then made forbidden by the game
local host = CreateFrame("Frame", nil, UIParent); host:SetSize(40, 40)
local t = host:CreateTexture(nil, "ARTWORK"); t:SetAllPoints(host); t:SetTexture(136048)
o.iconShapeReady = "circle"
SP:ShapeIconTexture(t, t, "ready")
local cd = CreateFrame("Cooldown", nil, host)
SP:ShapeCooldown(cd, "ready")
local function forbid(x)
	x.IsForbidden = function() return true end
	for _, m in ipairs({ "GetTexCoord", "SetTexCoord", "AddMaskTexture", "RemoveMaskTexture", "GetParent", "SetSwipeTexture", "SetUseCircularEdge" }) do
		x[m] = function() error("Attempt to access forbidden object from code tainted by an AddOn", 2) end
	end
end
forbid(t); forbid(cd)

o.iconShape = "rounded"
local ok, err = pcall(SP.ApplyIconShapes, SP)
check("ApplyIconShapes with a forbidden icon: no error", ok, tostring(err))
ok, err = pcall(SP.SetIconShapeOwn, SP, t, "flat", cd)
check("its own shape changed while forbidden: no error", ok, tostring(err))
checkEq("nothing handed to the error handler", #errs, 0, errs[1])
local b = SP.totemButtons and SP.totemButtons[1]
local icon = b and rawget(b, "icon")
if icon then check("the totem bar's icons still take the shape", icon.spShapeMask ~= nil or (icon.GetNumMaskTextures and icon:GetNumMaskTextures() > 0)) end

-- (3.0.9.16) Mononders, on 3.0.9.14 in Alterac Valley: the same error, over and over, past that fix. The game's
-- IsForbidden answers false for a part that only sits on a forbidden one (it says "explicitly marked"), yet every
-- call on the part is refused. Such a part is left as it is too.
local function refuse(x)
	x.IsForbidden = function() return false end
	for _, m in ipairs({ "GetTexCoord", "SetTexCoord", "AddMaskTexture", "RemoveMaskTexture", "GetParent", "SetSwipeTexture", "SetUseCircularEdge" }) do
		x[m] = function() error("calling '" .. m .. "' on bad self (Attempt to access forbidden object from code tainted by an AddOn)", 2) end
	end
end
local t2 = host:CreateTexture(nil, "ARTWORK"); t2:SetAllPoints(host); t2:SetTexture(136048)
SP:ShapeIconTexture(t2, t2, "ready")
local cd2 = CreateFrame("Cooldown", nil, host)
SP:ShapeCooldown(cd2, "ready")
refuse(t2); refuse(cd2)
o.iconShape = "circle"
errs = {}
ok, err = pcall(SP.ApplyIconShapes, SP)
check("IsForbidden false, every call refused: ApplyIconShapes, no error", ok, tostring(err))
ok, err = pcall(SP.SetIconShapeOwn, SP, t2, "rounded", cd2)
check("IsForbidden false, every call refused: its own shape changed, no error", ok, tostring(err))
checkEq("IsForbidden false, every call refused: nothing handed to the error handler", #errs, 0, errs[1])
if icon then check("and the totem bar's icons still take the shape", icon.spShapeMask ~= nil or (icon.GetNumMaskTextures and icon:GetNumMaskTextures() > 0)) end

-- a mistake of ShamanPower's own while shaping an icon is still reported (only the game's refusals are quiet)
local t3 = host:CreateTexture(nil, "ARTWORK"); t3:SetAllPoints(host)
SP:ShapeIconTexture(t3, t3, "ready")
t3.AddMaskTexture = function() error("a mistake of our own", 2) end
errs = {}
o.iconShapeReady = "rounded"
ok = pcall(SP.ApplyIconShapes, SP)
check("our own mistake: still reported", ok and #errs >= 1 and errs[1]:find("a mistake of our own", 1, true) ~= nil, errs[1])
t3.AddMaskTexture = nil
o.iconShapeReady = "circle"

o.iconShape, o.iconShapeReady = was[1], was[2]
SP:ApplyIconShapes()
geterrorhandler = geh
finish()
