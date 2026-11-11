-- client: both
-- (bug report, 11-10) The Loadout button does not stay where it was put: at login the saved spot is
-- applied while the button is still at 100% scale (CreateLoadoutBar), then UpdateLoadoutBar sets the
-- Loadout Bar Scale for the first time, which moved it unless the scale is 100%. Each login here builds
-- a new button with the same two calls the game's login makes (CreateLoadoutBar, UpdateLoadoutBar).
local SP = ShamanPower
if not (SP.CreateLoadoutBar and SP.RestoreLoadoutBarPosition) then skip("no loadout bar here") end
local keepList, keepActive, keepOff, keepBar = ShamanPower_TotemLoadouts, SP.opt.activeLoadout, SP.opt.loadoutsOff, SP.opt.showLoadoutBar
local keepPos, keepScale = SP.opt.loadoutBarPosition, SP.opt.loadoutBarScale
ShamanPower_TotemLoadouts = { { name = "Solo", 1, 2, 1, 1 }, { name = "Raid", 2, 5, 1, 2 } }
SP.opt.loadoutsOff = nil
SP.opt.showLoadoutBar = true
SP:CreateLoadoutBar()
local a = SP.loadoutAnchor
check("the Loadout button", a ~= nil)
if not a then finish() return end
local function near(x, y) return type(x) == "number" and type(y) == "number" and math.abs(x - y) < 1 end
local function screenCenter()
	local cx, cy = a:GetCenter()
	local s = a:GetScale()
	return cx * s, cy * s
end
local function login()
	a:Hide()
	SP.loadoutBarCreated = nil
	SP:CreateLoadoutBar()
	SP:UpdateLoadoutBar()
	a = SP.loadoutAnchor
	__sim.advance(0.1)
end

for _, scale in ipairs({ 1.0, 0.7, 1.5 }) do
	SP.opt.loadoutBarScale = scale
	-- put by hand near the chat window's corner but well away from it, then saved as a drop saves it
	SP.opt.loadoutBarPosition = { anchor = "BOTTOMLEFT", x = 600, y = 400 }
	login()
	local cx, cy = screenCenter()
	check(("scale %d%%: after a login the button is where it was put (x)"):format(scale * 100), near(cx, 600), tostring(cx))
	check(("scale %d%%: after a login the button is where it was put (y)"):format(scale * 100), near(cy, 400), tostring(cy))
end

ShamanPower_TotemLoadouts, SP.opt.activeLoadout, SP.opt.loadoutsOff, SP.opt.showLoadoutBar = keepList, keepActive, keepOff, keepBar
SP.opt.loadoutBarPosition, SP.opt.loadoutBarScale = keepPos, keepScale
login()
finish()
