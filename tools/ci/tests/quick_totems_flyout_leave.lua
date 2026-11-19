-- client: both
-- (3.0.9.17) A Discord report: totem bar flyouts stuck out, more often since Quick Totems. The totem button keeps its
-- hover flyout open while a quick totem (a child of it) is under the mouse; leaving the quick totem has to close it,
-- through its own _onleave, which the game's SecureHandlerEnterLeaveTemplate runs from its OnEnter / OnLeave scripts.
-- Quick Totems SET those scripts for its tooltip, wiping the template's, so the close never ran and the flyout stayed
-- out (Quick Totems below, flyouts above: the mouse leaving the bar downward crossed them). Now hooked, as every flyout
-- button's tooltip is.
local SP = ShamanPower
local W = __sim.W
if not (SP.SetQuickTotemSlot and SP.totemButtons and SP.totemButtons[1]) then skip("no totem bar here (not a shaman?)") end
local o = SP.opt
local keep = { on = o.quickTotems, side = o.quickTotemSide, picks = o.quickTotemPicks, tips = o.ShowTooltips }
local E = 1
local k = {}
for idx in pairs(SP.Totems[E] or {}) do if SP:KnowsTotem(E, idx) then k[#k + 1] = idx end end
table.sort(k)
if #k < 2 then skip("fewer than two known Earth totems here") end
check("no quick totem made yet", _G.ShamanPowerQuickTotem1_1 == nil)

-- the game's template runs _onenter / _onleave from its own OnEnter / OnLeave (the sim's template has no scripts):
-- stand in for it on every frame made with it, counting each run
local ran = {}
local CF = CreateFrame
CreateFrame = function(kind, name, parent, template, ...)
	local f = CF(kind, name, parent, template, ...)
	if type(template) == "string" and template:find("SecureHandlerEnterLeaveTemplate", 1, true) then
		f:SetScript("OnEnter", function(self) ran[#ran + 1] = { self, "_onenter" } end)
		f:SetScript("OnLeave", function(self) ran[#ran + 1] = { self, "_onleave" } end)
	end
	return f
end
o.ShowTooltips = true
SP:SetQuickTotemSlot(E, k[1], 1)
SP:SetQuickTotemSlot(E, k[2], 2)
o.quickTotems = true
SP:QuickTotemsChanged()
CreateFrame = CF

local function runs(f, what)
	local n = 0
	for _, r in ipairs(ran) do if r[1] == f and r[2] == what then n = n + 1 end end
	return n
end
for slot = 1, 2 do
	local q = _G["ShamanPowerQuickTotem1_" .. slot]
	check("spot " .. slot .. ": made and shown", q ~= nil and q:IsShown())
	if q then
		W.runScript(q, "OnEnter", true)   -- (its script and hooks, as the game fires them)
		checkEq("spot " .. slot .. ": the template's OnEnter still runs", runs(q, "_onenter"), 1)
		check("spot " .. slot .. ": its tooltip shows", GameTooltip:IsShown())
		W.runScript(q, "OnLeave", true)
		checkEq("spot " .. slot .. ": leaving it runs its _onleave (the flyout's close)", runs(q, "_onleave"), 1)
		check("spot " .. slot .. ": its tooltip goes", not GameTooltip:IsShown())
		if not SP:FlyoutBoxMode() then
			checkEq("spot " .. slot .. ": the close is its leave snippet", q:GetAttribute("_onleave"), SP.SECURE_ONLEAVE_PARENT)
		end
	end
end

-- made again (switched off and on): still one run per leave, no second hook
o.quickTotems = false; SP:QuickTotemsChanged()
o.quickTotems = true; SP:QuickTotemsChanged()
local q = _G.ShamanPowerQuickTotem1_1
if q then
	local before = runs(q, "_onleave")
	W.runScript(q, "OnLeave", true)
	checkEq("switched off and on: one run per leave", runs(q, "_onleave") - before, 1)
end

o.quickTotems, o.quickTotemSide, o.quickTotemPicks, o.ShowTooltips = keep.on, keep.side, keep.picks, keep.tips
SP:QuickTotemsChanged()
finish()
