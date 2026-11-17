-- client: both
-- (3.0.9.16) The owner, 11-16: a profile switch or an import must never leave anything off the screen because a
-- spot was saved on someone else's screen. The totem bar (the game does not keep it on the screen: it may go past
-- an edge by hand) saved far past the right edge: switching to that profile, or importing a code with it, brings
-- the bar fully onto the screen and saves the new spot; a bar put a little past an edge by hand stays there.
local SP = ShamanPower
local db = SP.db
local root = _G.ShamanPowerFrame
if not (db and root and SP.totemButtons and SP.totemButtons[1] and SP.SaveFramePosition) then skip("no totem bar here") end
local start = db:GetCurrentProfile()

-- the bar's box on the screen (the frame round it and its buttons), in the screen's units
local function box()
	local l, b, r, t
	for _, f in ipairs({ _G.ShamanPowerAuto, SP.totemButtons[1], SP.totemButtons[2], SP.totemButtons[3], SP.totemButtons[4] }) do
		if f and f:IsShown() then
			local fl, fb, w, h = f:GetRect()
			if fl and w and w > 1 then
				local k = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
				fl, fb, w, h = fl * k, fb * k, w * k, h * k
				l, b = math.min(l or fl, fl), math.min(b or fb, fb)
				r, t = math.max(r or fl + w, fl + w), math.max(t or fb + h, fb + h)
			end
		end
	end
	return l, b, r, t
end
local function onScreen()
	local l, b, r, t = box()
	return l and l >= -0.5 and b >= -0.5 and r <= UIParent:GetWidth() + 0.5 and t <= UIParent:GetHeight() + 0.5
end
local function f1(x) return x and ("%.0f"):format(x) or "nil" end
-- the bar moved by dx (screen units) from where it is, saved as a drag saves it
local function shove(dx)
	local p, rel, rp, x, y = root:GetPoint(1)
	local k = root:GetEffectiveScale() / UIParent:GetEffectiveScale()
	root:ClearAllPoints()
	root:SetPoint(p, rel, rp, (x or 0) + dx / k, y or 0)
	SP:SaveFramePosition(root)
	__sim.advance(0.1)
end

__sim.advance(0.2)
check("the bar starts on the screen", onScreen())
local W = UIParent:GetWidth()

-- a profile with the bar saved far past the right edge (another, wider screen)
db:SetProfile("Wide Screen Test")
__sim.advance(1.0)
local l = box()
shove(W + 400 - l)
local l2, _, r2 = box()
check("set up: the bar is off the screen", l2 and l2 > W, f1(l2) .. ".." .. f1(r2) .. " of " .. f1(W))
db:SetProfile(start)
__sim.advance(1.0)
db:SetProfile("Wide Screen Test")
__sim.advance(1.0)
local l3, _, r3 = box()
check("switching to it: the bar is fully on the screen", onScreen(), f1(l3) .. ".." .. f1(r3) .. " of " .. f1(W))
db:SetProfile(start)
__sim.advance(1.0)
db:SetProfile("Wide Screen Test")
__sim.advance(1.0)
check("and its new spot was saved (still on the screen next time)", onScreen())

-- a code made with the bar off the screen, imported
shove(W + 400 - (box()))
local code = SP:ExportCurrentProfile()
db:SetProfile(start)
__sim.advance(1.0)
local ok, name = SP:ImportShare(code, "newProfile", "Off Screen Import Test")
__sim.advance(1.0)
local l4, _, r4 = box()
check("an import with the bar off the screen: fully on it", ok and onScreen(), f1(l4) .. ".." .. f1(r4) .. " of " .. f1(W))

-- a little past the right edge, by hand: left where it was put
local before = select(3, box())
local width = before - (box())
shove(W - (box()) - width * 0.8)   -- (80% of it still on the screen)
local la = box()
db:SetProfile(start)
__sim.advance(1.0)
db:SetProfile(name)
__sim.advance(1.0)
local lb = box()
check("a little past an edge by hand: left there", la and lb and math.abs(la - lb) < 1, f1(la) .. " -> " .. f1(lb))

db:SetProfile(start)
__sim.advance(1.0)
for _, n in ipairs({ "Wide Screen Test", name }) do pcall(db.DeleteProfile, db, n, true) end
check("back on the first profile, on the screen", onScreen())
finish()
