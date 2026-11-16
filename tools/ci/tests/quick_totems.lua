-- client: both
-- (3.0.9.14) Quick Totems (mockups A109 + A110): off by default and nothing made; on, the totems picked in each
-- element's two spots show at its corners and cast them; Auto puts them on the side away from the flyouts; what is
-- drawn outside the button on that side (the duration bar here) steps out past them; picked on the flyout's side
-- the flyout starts past them; a fight freezes them (a change waits for its end); lit with the time left while their
-- totem is down; hidden on Grid and Compact.
local SP = ShamanPower
if not (SP.SetQuickTotemSlot and SP.totemButtons and SP.totemButtons[1]) then skip("no totem bar here (not a shaman?)") end
local W = __sim.W
local o = SP.opt
local keep = { on = o.quickTotems, side = o.quickTotemSide, picks = o.quickTotemPicks, pos = o.durationBarPosition }

-- two known totems of an element (by their index in its list)
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
if #k < 3 then skip("fewer than three known Earth totems here") end

-- 1. off by default: nothing made, no room taken
o.quickTotems, o.quickTotemPicks, o.quickTotemSide = nil, nil, nil
SP:QuickTotemsChanged()
check("off by default: no button made", _G.ShamanPowerQuickTotem1_1 == nil)
check("off: no room taken", SP.totemButtons[E].spQuickPadT == nil)
checkEq("the default side is Auto", SHAMANPOWER_DEFAULT_VALUES and SHAMANPOWER_DEFAULT_VALUES.quickTotemSide or "auto", "auto")

-- 2. picks: one totem per spot, a new pick takes the spot over
SP:SetQuickTotemSlot(E, k[1], 1)
SP:SetQuickTotemSlot(E, k[2], 2)
checkEq("spot 1 holds the first pick", SP:QuickTotemPick(E, 1), k[1])
checkEq("spot 2 holds the second", SP:QuickTotemPick(E, 2), k[2])
SP:SetQuickTotemSlot(E, k[1], 2)
checkEq("the same totem moved to spot 2 leaves spot 1", SP:QuickTotemPick(E, 1), nil)
checkEq("and takes spot 2 over", SP:QuickTotemPick(E, 2), k[1])
SP:SetQuickTotemSlot(E, k[2], 1)
checkEq("its spot reads back", SP:QuickTotemSlotOf(E, k[2]), 1)
checkEq("not a quick totem reads 0", SP:QuickTotemSlotOf(E, k[3]), 0)

-- 3. on: they show and cast their totem
o.quickTotems = true
o.durationBarPosition = "bottom"
SP:QuickTotemsChanged()
local q1, q2 = _G.ShamanPowerQuickTotem1_1, _G.ShamanPowerQuickTotem1_2
local btn = SP.totemButtons[E]
check("on: both spots show", q1 and q1:IsShown() and q2 and q2:IsShown())
local name1 = GetSpellInfo(SP:GetTotemSpell(E, k[2]))
if SPCompat.HasTotemCastAliases(SP:GetTotemSpell(E, k[2])) then name1 = SPCompat.TotemCastName(SP:GetTotemSpell(E, k[2])) end
checkEq("spot 1 casts its totem", q1 and q1:GetAttribute("spell"), name1)
checkEq("by a spell click", q1 and q1:GetAttribute("type"), "spell")
check("half the button", q1 and math.abs(q1:GetWidth() - (math.floor(btn:GetWidth() * 0.5 + 0.5) - 1)) < 0.01,
	tostring(q1 and q1:GetWidth()) .. " of " .. tostring(btn:GetWidth()))
check("other elements made nothing", _G.ShamanPowerQuickTotem2_1 == nil)

-- 4. Auto: the side away from the flyouts, and the duration bar steps out past them
local fly = SP:FlyoutDirection({ element = E, totemButton = btn })
local side = SP:QuickTotemSide(E)
local AWAY = { top = "below", bottom = "above", left = "right", right = "left" }
checkEq("Auto: away from the flyouts (" .. tostring(fly) .. ")", side, AWAY[fly])
local t, b, l, r = SP:FlyoutArrowPads(btn)
local room = (side == "below" and b) or (side == "above" and t) or (side == "left" and l) or r
check("their side has their room", room and room >= q1:GetHeight(), tostring(room))
if side == "below" then
	local bars = SP.totemProgressBars and SP.totemProgressBars[E]
	if bars and bars.bg then
		local _, _, _, _, y = bars.bg:GetPoint(1)
		check("the duration bar steps down past them", y and y <= -(1 + room), tostring(y))
	end
end

-- 5. on the flyout's side: the flyout starts past them (and they keep the tab's room)
o.quickTotemSide = ({ top = "above", bottom = "below", left = "left", right = "right" })[fly]
SP:QuickTotemsChanged()
local fl = SP.totemFlyouts and SP.totemFlyouts[E]
if fl and fl.buttons and fl.buttons[1] then
	checkEq("the flyout knows their room", SP:QuickTotemFlyoutLead(fl), btn.spQuickRoom)
	if fl.box and SP.UpdateFlyoutVisibility then SP:UpdateFlyoutVisibility(E) else SP:LayoutFlyoutButtons(fl, fl.isHorizontal) end
	local first
	for _, fb in ipairs(fl.buttons) do if fb:GetNumPoints() > 0 then first = fb break end end
	if first then
		local _, _, _, x, y = first:GetPoint(1)
		local off = math.abs((fly == "top" or fly == "bottom") and y or x)
		check("the flyout starts past them", off >= btn.spQuickRoom, tostring(off) .. " < " .. tostring(btn.spQuickRoom))
	end
	check("the in-combat relayout reads the same lead", btn:GetAttribute("flyoutLead") ~= nil)
end
o.quickTotemSide = nil
SP:QuickTotemsChanged()
check("back on Auto: the flyout has no lead from them", not fl or SP:QuickTotemFlyoutLead(fl) == 0)
check("and its in-combat relayout neither", btn:GetAttribute("flyoutLead") == nil)

-- 6. a fight freezes them: a change waits for its end
__sim.setCombat(true)
o.quickTotemSize = 0.4
SP:QuickTotemsChanged()
local w = q1:GetWidth()
check("in a fight nothing moves", math.abs(w - (math.floor(btn:GetWidth() * 0.5 + 0.5) - 1)) < 0.01, tostring(w))
__sim.setCombat(false)
__sim.advance(0.2)
check("after it, the change is made", math.abs(q1:GetWidth() - (math.floor(btn:GetWidth() * 0.4 + 0.5) - 1)) < 0.01, tostring(q1:GetWidth()))
o.quickTotemSize = nil
SP:QuickTotemsChanged()

-- 7. its totem down: lit with its time left; gone: not
local id = SP:GetTotemSpell(E, k[2])
local slot = SP.ElementToSlot and SP.ElementToSlot[E] or 2
__sim.A.totems[slot] = { GetSpellInfo(id), GetTime() - 20, 120, nil, id }
SP:InvalidateTotemInfo()
W.fireEvent("PLAYER_TOTEM_UPDATE", slot)
__sim.advance(0.3)
check("its totem down: lit", q1.lit:IsShown())
local tx = q1.time:GetText()
check("with its time left", tx == SP.FormatDuration(99) or tx == SP.FormatDuration(100), tostring(tx))
check("the other spot not lit", not q2.lit:IsShown())
__sim.A.totems[slot] = nil
SP:InvalidateTotemInfo()
W.fireEvent("PLAYER_TOTEM_UPDATE", slot)
__sim.advance(0.3)
check("gone: not lit", not q1.lit:IsShown())

-- 8. not on Grid or Compact: hidden, the room given back
local style = SP.GetTotemBarStyle and SP:GetTotemBarStyle() or "normal"
if SP.SetTotemBarStyle and SP:TotemBarStyle("compact") then
	SP:SetTotemBarStyle("compact")
	__sim.advance(0.2)
	check("Compact: hidden", not q1:IsShown())
	check("Compact: no room taken", btn.spQuickPadT == nil)
	SP:SetTotemBarStyle(style)
	__sim.advance(0.2)
	check("back on its style: shown again", q1:IsShown())
end

-- 9. off again: hidden, the room given back
o.quickTotems = false
SP:QuickTotemsChanged()
check("off: hidden", not q1:IsShown() and not q2:IsShown())
check("off: the room given back", btn.spQuickPadT == nil)

o.quickTotems, o.quickTotemSide, o.quickTotemPicks, o.durationBarPosition = keep.on, keep.side, keep.picks, keep.pos
SP:QuickTotemsChanged()
finish()
