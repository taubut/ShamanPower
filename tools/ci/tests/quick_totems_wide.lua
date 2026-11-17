-- client: both
-- (3.0.9.16) Rakii's report (Discord, a picture): Quick Totems at Size 60% overlapped each other under every totem.
-- Each is a share of the button and they sat at its two corners, so over 50% the pair was wider than the button.
-- Now up to 50% nothing changes (the corners); over it the pair sits in the middle, 1 px apart, and spreads past
-- the button's edges by at most half the Button Spacing (never into the next button's pair), as big as fits with
-- less room. Below and Left, at the bar's 100% and 200% scale, and the bar laid out again at a new Button Spacing.
local SP = ShamanPower
if not (SP.SetQuickTotemSlot and SP.totemButtons and SP.totemButtons[1]) then skip("no totem bar here (not a shaman?)") end
local o = SP.opt
local keep = { on = o.quickTotems, side = o.quickTotemSide, picks = o.quickTotemPicks, size = o.quickTotemSize,
	pad = o.totemBarPadding, scale = o.buffscale }

local function known(e)
	local out = {}
	for idx in pairs(SP.Totems[e] or {}) do
		if SP:KnowsTotem(e, idx) then out[#out + 1] = idx end
	end
	table.sort(out)
	return out
end
local E = 1
local k = known(E)
if #k < 2 then skip("fewer than two known Earth totems here") end
o.quickTotems, o.quickTotemPicks = true, nil
SP:SetQuickTotemSlot(E, k[1], 1)
SP:SetQuickTotemSlot(E, k[2], 2)
local k2 = known(2)
if #k2 >= 2 then SP:SetQuickTotemSlot(2, k2[1], 1); SP:SetQuickTotemSlot(2, k2[2], 2) end
local btn = SP.totemButtons[E]
local q1, q2 = _G.ShamanPowerQuickTotem1_1, _G.ShamanPowerQuickTotem1_2

local function set(side, size, pad)
	o.quickTotemSide, o.quickTotemSize, o.totemBarPadding = side, size, pad
	SP:UpdateMiniTotemBar()      -- (the bar laid out again at the new Button Spacing)
	SP:QuickTotemsChanged()
	__sim.advance(0.1)
	q1, q2 = _G.ShamanPowerQuickTotem1_1, _G.ShamanPowerQuickTotem1_2
end
local function near(a, b) return a and b and math.abs(a - b) < 0.51 end
local function f1(x) return x and ("%.1f"):format(x) or "nil" end

for _, scale in ipairs({ 1, 2 }) do
	o.buffscale = scale
	local at = (" (bar %d%%)"):format(scale * 100)

	-- up to half: the corners, as before
	set("below", 0.5, 10)
	check("50%: at the corners" .. at, near(q1:GetLeft(), btn:GetLeft()) and near(q2:GetRight(), btn:GetRight()),
		f1(q1:GetLeft()) .. "/" .. f1(btn:GetLeft()) .. " " .. f1(q2:GetRight()) .. "/" .. f1(btn:GetRight()))

	-- 60%, Button Spacing 10 (Rakii): full size, apart, in the middle, past the edges by at most 5
	set("below", 0.6, 10)
	local edge = btn:GetWidth()
	check("60%: its full size" .. at, near(q1:GetWidth(), math.floor(edge * 0.6 + 0.5) - 1), f1(q1:GetWidth()) .. " of " .. f1(edge))
	check("60%: the two never overlap" .. at, q1:GetRight() < q2:GetLeft(), f1(q1:GetRight()) .. " vs " .. f1(q2:GetLeft()))
	check("60%: 1 px apart" .. at, near(q2:GetLeft() - q1:GetRight(), 1), f1(q2:GetLeft() - q1:GetRight()))
	local mid = (btn:GetLeft() + btn:GetRight()) / 2
	check("60%: in the middle of the button" .. at, near((q1:GetLeft() + q2:GetRight()) / 2, mid), f1(mid))
	local out = math.max(btn:GetLeft() - q1:GetLeft(), q2:GetRight() - btn:GetRight())
	check("60%: past the edges, at most half the spacing" .. at, out > 0 and out <= 5, f1(out))
	local n1 = _G.ShamanPowerQuickTotem2_1
	if n1 and n1:IsShown() and SP.IsTotemBarHorizontal and SP:IsTotemBarHorizontal() then
		check("60%: never into the next button's pair" .. at, q2:GetRight() < n1:GetLeft(), f1(q2:GetRight()) .. " vs " .. f1(n1:GetLeft()))
	end

	-- Button Spacing 0: as big as fits, inside the button
	set("below", 0.6, 0)
	check("spacing 0: never overlap" .. at, q1:GetRight() < q2:GetLeft(), f1(q1:GetRight()) .. " vs " .. f1(q2:GetLeft()))
	check("spacing 0: inside the button" .. at, q1:GetLeft() >= btn:GetLeft() - 0.01 and q2:GetRight() <= btn:GetRight() + 0.01)
	check("spacing 0: smaller than 60%" .. at, q1:GetWidth() < math.floor(edge * 0.6 + 0.5) - 1, f1(q1:GetWidth()))

	-- the default spacing (2): at most 1 past each edge
	set("below", 0.6, 2)
	out = math.max(btn:GetLeft() - q1:GetLeft(), q2:GetRight() - btn:GetRight())
	check("spacing 2: never overlap, at most 1 past" .. at, q1:GetRight() < q2:GetLeft() and out <= 1, f1(out))

	-- Left: the same up and down
	set("left", 0.6, 10)
	check("Left 60%: never overlap" .. at, q1:GetBottom() > q2:GetTop(), f1(q1:GetBottom()) .. " vs " .. f1(q2:GetTop()))
	local outV = math.max(q1:GetTop() - btn:GetTop(), btn:GetBottom() - q2:GetBottom())
	check("Left 60%: past the edges, at most half the spacing" .. at, outV > 0 and outV <= 5, f1(outV))
	check("Left 60%: on the left of the button" .. at, q1:GetRight() < btn:GetLeft())
end

o.quickTotems, o.quickTotemSide, o.quickTotemPicks, o.quickTotemSize = keep.on, keep.side, keep.picks, keep.size
o.totemBarPadding, o.buffscale = keep.pad, keep.scale
SP:UpdateMiniTotemBar()
SP:QuickTotemsChanged()
finish()
