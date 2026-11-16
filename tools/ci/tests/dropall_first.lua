-- client: both
-- (3.0.9.14) Dibul's ask on Discord (11-14): the Call button (Drop All) on the left of the bar. Totem Bar > Bar's
-- Buttons row: Drop All drags like the elements, to the start or the end of the bar (a drop between two elements
-- lands on the nearer end). At the start it goes first on the bar, then the separator, then the totems; Totemic
-- Call, when it is on the totem bar, stays at the end (the owner: "recal stays where it was") with a separator
-- before it; Earth Shield stays at the end. On WoW: Forever's Call lines the row shows it there too.
-- The elements still drag among themselves. Reset Page Settings puts it back at the end.
local SP = ShamanPower
local ns = __sim.A.addons["shamanpower_config"] and __sim.A.addons["shamanpower_config"].ns
if not (ns and SP.TotemBarExtrasLead and SP.autoButton) then skip("no totem bar here (not a shaman?)") end
local o = SP.opt
local keep = { first = o.dropAllFirst, order = o.totemBarOrder, compact = o.compactStyle }
local da = _G.ShamanPowerAutoDropAll
if not (da and SP:ShowsDropAllButton()) then skip("Drop All not on the bar here") end

local function x(f) return f and f:GetLeft() end
local function firstTotem()
	local best
	for e = 1, 4 do
		local b = SP.totemButtons[e]
		if b and b:IsShown() and (not best or b:GetLeft() < best:GetLeft()) then best = b end
	end
	return best
end
local function lastTotem()
	local best
	for e = 1, 4 do
		local b = SP.totemButtons[e]
		if b and b:IsShown() and (not best or b:GetLeft() > best:GetLeft()) then best = b end
	end
	return best
end
if not SP:IsTotemBarHorizontal() then skip("this test reads a bar that runs across") end

-- 1. as always: at the end
o.dropAllFirst = nil
SP:UpdateMiniTotemBar()
__sim.advance(0.1)
local w0 = SP.autoButton:GetWidth()
local scaleK = SP.totemButtons[1]:GetEffectiveScale() / da:GetEffectiveScale()
check("by default Drop All is after the totems", x(da) > x(lastTotem()) * scaleK - 0.5,
	tostring(x(da)) .. " vs " .. tostring(x(lastTotem()) * scaleK))
checkEq("no room before the totems", SP:TotemBarExtrasLead(), 0)

-- 2. dragged to the start in the Buttons row
ShamanPowerConfig:Open({ "buttons", "auto_button" })
__sim.advance(0.3)
local row = ns.CustomRows.tbButtons
-- (after a drag the row reads its list again and the page is laid out again, as IconRow's StopDrag does)
local function refresh()
	if row:ListChanged() and ShamanPowerConfig.RefreshCurrent then ShamanPowerConfig:RefreshCurrent() end
	__sim.advance(0.2)
	row = ns.CustomRows.tbButtons
end
local function item(key) for _, it in ipairs(row.list or {}) do if it.key == key then return it end end end
local d = item("dropall")
check("Drop All can be dragged", d and row.def.movable(d))
local n = #row.list
-- where it may land: the start, or after the elements (between two elements: the nearer end)
local firstE, lastE
for i, it in ipairs(row.list) do if type(it.key) == "number" then firstE = firstE or i; lastE = i end end
checkEq("dropped before the first two elements: the start", row.def.snapGap(d, firstE + 1), firstE)
checkEq("dropped near the end: after the elements", row.def.snapGap(d, lastE), lastE + 1)
check("an element stays among the elements", row.def.snapGap(item(1), n + 1) <= lastE + 1)
row.def.move(d, 1)
__sim.advance(0.2)
check("dragged to the start: saved", o.dropAllFirst == true)
check("Drop All is first on the bar", x(da) < x(firstTotem()) * scaleK, tostring(x(da)) .. " vs " .. tostring(x(firstTotem()) * scaleK))
check("the room before the totems", SP:TotemBarExtrasLead() > 0)
local tc = _G.ShamanPowerAutoTotemicCall
local tcOn = tc and tc:IsShown()
local grow = tcOn and (12 - SP:TotemBarSpacing()) or 0   -- (a second separator before Totemic Call at the end)
check("the bar keeps its size (and a separator more with Totemic Call)", math.abs(SP.autoButton:GetWidth() - (w0 + grow)) < 0.01,
	tostring(w0) .. " -> " .. tostring(SP.autoButton:GetWidth()))
local sep = _G.ShamanPowerAutoSeparator
check("the separator between Drop All and the totems", sep and sep:IsShown() and x(sep) > x(da) and x(sep) < x(firstTotem()) * scaleK)
if tcOn then
	check("Totemic Call stays at the end", x(tc) > x(lastTotem()) * scaleK)
	local sep2 = _G.ShamanPowerAutoSeparator2
	check("with a separator before it", sep2 and sep2:IsShown() and x(sep2) < x(tc) and x(sep2) > x(lastTotem()) * scaleK)
end
local es = _G.ShamanPowerEarthShieldBtn
if es and es:IsShown() and es:GetNumPoints() > 0 then
	local _, rel = es:GetPoint(1)
	checkEq("Earth Shield stays at the end (after the last totem)", rel, lastTotem())
end

-- 3. the row lists it first, and the elements still drag among themselves
refresh()
local daAt, e1At
for i, it in ipairs(row.list) do
	if it.key == "dropall" then daAt = i end
	if type(it.key) == "number" and not e1At then e1At = i end
end
check("the row lists Drop All before the elements", daAt and e1At and daAt < e1At, tostring(daAt) .. " / " .. tostring(e1At))
local before = o.totemBarOrder and o.totemBarOrder[1] or 1
local e1 = item(before)
local from
for i, it in ipairs(row.list) do if it == e1 then from = i end end
row.def.move(e1, #row.list)   -- (as the drop after the last element sends it)
__sim.advance(0.2)
checkEq("an element dragged to the end: last on the bar", o.totemBarOrder and o.totemBarOrder[4], before)

-- 4. not on Compact (its lines keep their own layout)
if SP.TotemBarStyle and SP:TotemBarStyle("compact") and SP.SetTotemBarStyle then
	local style = SP:GetTotemBarStyle()
	SP:SetTotemBarStyle("compact")
	__sim.advance(0.2)
	checkEq("Compact: no room before the lines", SP:TotemBarExtrasLead(), 0)
	SP:SetTotemBarStyle(style)
	__sim.advance(0.2)
end

-- 5. back to the end by a drag, and by Reset Page Settings
refresh()
d = item("dropall")
row.def.move(d, #row.list)
__sim.advance(0.2)
check("dragged back to the end", not o.dropAllFirst)
o.dropAllFirst = true
SP:TotemBarResetPage()
__sim.advance(0.2)
check("Reset Page Settings: back at the end", not o.dropAllFirst)

if ShamanPowerConfig.Hide then ShamanPowerConfig:Hide() end
o.dropAllFirst, o.totemBarOrder = keep.first, keep.order
SP:UpdateMiniTotemBar()
finish()
