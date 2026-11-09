-- client: forever
-- (3.0.9.9, A90) Call Flyout on Drop All. Picking a Call puts it on Drop All and the assignments follow
-- it; a pick on the bar then lands in that Call (a linked loadout follows), Call of the Elements is left
-- alone and comes back with it. Out of a fight and in one (the Lua side; the secure snippets are checked
-- against stand-in frames at the end). The sim has no Blizzard totem bar: its three pages are made here.
local SP = ShamanPower
local A, W = __sim.A, __sim.W
if not (SP.SelectCall and SP.RefreshCallFlyout and SP.CallFlyoutSnippets) then skip("no Call flyout here") end

-- ---- Blizzard's totem bar, three pages of four slots, as the game has it
local BAR = 7
local first = (BAR - 1) * 12 + 1
local slots = {}
local was = {
	GetActionInfo = GetActionInfo, SetMultiCastSpell = rawget(_G, "SetMultiCastSpell"),
	GetMultiCastTotemSpells = rawget(_G, "GetMultiCastTotemSpells"), barIndex = C_ActionBar.GetMultiCastBarIndex,
	wrap = rawget(_G, "SecureHandlerWrapScript"), unwrap = rawget(_G, "SecureHandlerUnwrapScript"),
	known = {}, opt = {}, page = SP.db.char.callPage, snippets = SPCompat.snippetOverride,
}
-- the sim cannot run secure snippets, so its flyouts are the arrow ("box") kind; the game's are not
-- (WoW: Forever runs them): this test goes the game's way (/spflyout secure)
SPCompat.snippetOverride = "on"
local function slotOf(page, element) return (page - 1) * 4 + SP.ElementToSlot[element] + first - 1 end
C_ActionBar.GetMultiCastBarIndex = function() return BAR end
GetActionInfo = function(a)
	if type(a) == "number" and a >= first and a < first + 12 then
		if slots[a] then return "spell", slots[a] end
		return nil
	end
	return was.GetActionInfo(a)
end
SetMultiCastSpell = function(a, id) if id and id ~= 0 then slots[a] = id else slots[a] = nil end end
GetMultiCastTotemSpells = function(wowSlot)
	local list = {}
	for e = 1, 4 do
		if SP.ElementToSlot[e] == wowSlot then for _, id in pairs(SP.Totems[e]) do list[#list + 1] = id end end
	end
	return unpack(list)
end
local wraps, unwraps = 0, 0
SecureHandlerWrapScript = function(...) wraps = wraps + 1 end
SecureHandlerUnwrapScript = function(...) unwraps = unwraps + 1 end
for _, id in ipairs({ 66842, 66843, 66844, 36936 }) do was.known[id] = A.known[id]; A.known[id] = true end
for _, k in ipairs({ "dropAllCallFlyout", "dropAllUsesTotemSets", "totemSetsSyncAssignments", "showTotemFlyouts" }) do was.opt[k] = SP.opt[k] end
SP.opt.dropAllUsesTotemSets, SP.opt.totemSetsSyncAssignments, SP.opt.showTotemFlyouts = nil, nil, true
W.fireEvent("SPELLS_CHANGED"); __sim.advance(0.2)

-- two totems per element: i1 (the Elements set) and i2 (the Ancestors set)
local i1, i2 = {}, {}
for e = 1, 4 do
	local keys = {}
	for idx in pairs(SP.Totems[e]) do keys[#keys + 1] = idx end
	table.sort(keys)
	i1[e], i2[e] = keys[1], keys[2]
end
local function spell(e, idx) return SP:GetTotemSpell(e, idx) end
local function page(p) local t = {} for e = 1, 4 do t[e] = slots[slotOf(p, e)] or 0 end return table.concat(t, ",") end
local function want(set) local t = {} for e = 1, 4 do t[e] = set[e] and spell(e, set[e]) or 0 end return table.concat(t, ",") end
local function assigned() local a = ShamanPower_Assignments[SP.player] local t = {} for e = 1, 4 do t[e] = a[e] or 0 end return table.concat(t, ",") end
local function idx(set) return table.concat(set, ",") end

local savedAssign = {}
ShamanPower_Assignments[SP.player] = ShamanPower_Assignments[SP.player] or {}
for e = 1, 4 do savedAssign[e] = ShamanPower_Assignments[SP.player][e] end
for e = 1, 4 do ShamanPower_Assignments[SP.player][e] = i1[e] end
SP:UpdateDropAllButton(); __sim.advance(0.2)
checkEq("Elements follows the assignments", page(1), want(i1))
for e = 1, 4 do slots[slotOf(2, e)] = spell(e, i2[e]) end   -- Ancestors as set on Blizzard's bar

-- ---- the switch
SP:SetCallFlyout(true); __sim.advance(0.2)
local B = SP.callFlyoutButtons
check("on: the flyout is made", SP.callFlyoutHeader and B and B[1] and B[2] and B[3])
check("on: Drop All's scripts wrapped", wraps == 3)
check("Elements is on Drop All: left out", B[1]:GetAttribute("isCurrentAssignment") == true)
check("Ancestors and Spirits in the flyout", not B[2]:GetAttribute("isCurrentAssignment") and not B[2]:GetAttribute("flyoutHidden")
	and not B[3]:GetAttribute("isCurrentAssignment"))
checkEq("the router knows Ancestors' Earth", SP.callFlyoutHeader:GetAttribute("p2e1"), (GetSpellInfo(spell(1, i2[1]))))

-- ---- out of a fight
check("Ancestors picked", SP:SelectCall(2))
__sim.advance(0.1)   -- (the flyout follows on the next frame)
checkEq("the Call is the character's", SP.db.char.callPage, 2)
checkEq("the assignments follow Ancestors", assigned(), idx(i2))
checkEq("Drop All casts Ancestors", _G.ShamanPowerAutoDropAll:GetAttribute("spell1"), 66843)
checkEq("Elements left alone", page(1), want(i1))
check("now Ancestors is left out of the flyout", B[2]:GetAttribute("isCurrentAssignment") == true and not B[1]:GetAttribute("isCurrentAssignment"))
local m = _G["SPFM1_" .. i2[1]]
if m then checkEq("a flyout pick writes into Ancestors", m:GetAttribute("action"), slotOf(2, 1)) end

SP:ApplyAssignment(1, i1[1]); __sim.advance(0.2)   -- (a pick on the bar)
checkEq("a pick lands in Ancestors", slots[slotOf(2, 1)], spell(1, i1[1]))
checkEq("not in Elements", page(1), want(i1))

check("Elements picked", SP:SelectCall(1))
check("back on Elements", SP.db.char.callPage == nil)
checkEq("the assignments are Elements' again", assigned(), idx(i1))
checkEq("Ancestors kept the pick", slots[slotOf(2, 1)], spell(1, i1[1]))
if m then checkEq("flyout picks write into Elements again", m:GetAttribute("action"), slotOf(1, 1)) end

-- ---- a loadout linked to Ancestors follows the bar
ShamanPower_TotemLoadouts = ShamanPower_TotemLoadouts or {}
local L = { name = "Call test", setPage = 2 }
for e = 1, 4 do L[e] = i2[e] end
table.insert(ShamanPower_TotemLoadouts, L)
SP:SelectCall(2); __sim.advance(0.2)
SP:ApplyAssignment(2, i1[2]); __sim.advance(0.2)
checkEq("the linked loadout follows the pick", L[2], i1[2])
checkEq("and Ancestors has it", slots[slotOf(2, 2)], spell(2, i1[2]))
SP:SelectCall(1); __sim.advance(0.2)
for i, lo in ipairs(ShamanPower_TotemLoadouts) do if lo == L then table.remove(ShamanPower_TotemLoadouts, i) break end end

-- ---- in a fight: the assignments follow when it ends
local ancestors = page(2)
__sim.setCombat(true); __sim.advance(0.1)
SP:CallFlyoutPicked(2)
checkEq("in a fight: the Call changes at once", SP.db.char.callPage, 2)
local p = SP.pendingAssignments or {}
local pend = {}
for e = 1, 4 do pend[e] = p[e] and spell(e, p[e]) or 0 end
checkEq("in a fight: Ancestors' totems wait for the fight's end", table.concat(pend, ","), ancestors)
__sim.setCombat(false); __sim.advance(1)
local a = {}
for e = 1, 4 do a[e] = spell(e, ShamanPower_Assignments[SP.player][e]) or 0 end
checkEq("the fight over: the assignments are Ancestors'", table.concat(a, ","), ancestors)
checkEq("Elements untouched by the fight", page(1), want(i1))

-- ---- a loadout chosen while Ancestors is on: Elements comes back and takes it
local L2 = { name = "Call test 2" }
for e = 1, 4 do L2[e] = i2[e] end
table.insert(ShamanPower_TotemLoadouts, L2)
SP:ApplyLoadout(#ShamanPower_TotemLoadouts, true); __sim.advance(0.2)
check("a loadout: back on Elements", SP.db.char.callPage == nil)
checkEq("the loadout lands in Elements", page(1), want(i2))
checkEq("Ancestors keeps its own", page(2), ancestors)
table.remove(ShamanPower_TotemLoadouts)

-- ---- the switch off while Ancestors is on: Elements first
for e = 1, 4 do ShamanPower_Assignments[SP.player][e] = i1[e] end
SP:UpdateDropAllButton(); __sim.advance(0.2)
SP:SelectCall(2); __sim.advance(0.2)
SP:SetCallFlyout(false); __sim.advance(0.2)
check("off: back on Elements", SP.db.char.callPage == nil)
checkEq("off: the assignments are Elements'", assigned(), idx(i1))
check("off: Drop All unwrapped", unwraps >= 3)
check("off: no flyout", not B[2]:IsShown() and not B[3]:IsShown())

-- ---- the snippets, against stand-in frames
local function frame(attrs)
	local f = { attrs = attrs or {}, refs = {}, kids = {}, shown = false }
	function f:GetAttribute(k) return self.attrs[k] end
	function f:SetAttribute(k, v) self.attrs[k] = v end
	function f:GetFrameRef(k) return self.refs[k] end
	function f:ChildUpdate(id, msg) self.updates = (self.updates or "") .. id .. "=" .. tostring(msg) .. ";" end
	function f:GetChildren() return unpack(self.kids) end
	function f:IsUnderMouse() return false end
	function f:IsShown() return self.shown end
	return f
end
local C = SP.callFlyoutSnippets or SP.CallFlyoutSnippets
local hdr = frame({ spPage = 1, call1 = 66842, call2 = 66843, call3 = 66844, p2e1 = "Stoneskin Totem", p2e2 = "", p2e3 = "Mana Spring Totem",
	p2e4 = "Windfury Totem", keep3 = true, spfmN = 2 })
local tb = {}
for e = 1, 4 do tb[e] = frame({ spell1 = "Old " .. e, type1 = "spell", spSecureResort = true }); hdr.refs["tb" .. e] = tb[e] end
tb[4].attrs.type1 = "macro"   -- (Air while twisting: left as it is)
local dropall = frame({ spell1 = 66842 }); hdr.refs.dropall = dropall
local m1 = frame({ spBase = 80, type = "multispell", action = 80 }); hdr.refs.spfm1 = m1
local m2 = frame({ spBase = 81, spPage1Off = true, type = nil }); hdr.refs.spfm2 = m2
local router = frame({ spPage = 2 }); router.refs.hdr = hdr
local function run(body, env)
	local fn = assert(loadstring(body))
	env.newtable = function(...) return { ... } end
	setfenv(fn, env)
	return fn()
end
run(C.ROUTER, { self = router })
checkEq("router: the Call on Drop All", hdr.attrs.spPage, 2)
checkEq("router: Drop All casts it", dropall.attrs.spell1, 66843)
checkEq("router: the old Call keeps what the bar cast", hdr.attrs.p1e1, "Old 1")
checkEq("router: Earth casts Ancestors' totem", tb[1].attrs.spell1, "Stoneskin Totem")
check("router: an empty slot casts nothing", tb[2].attrs.spell1 == nil)
checkEq("router: an element kept out of Drop All keeps its own", tb[3].attrs.spell1, "Old 3")
checkEq("router: Air while twisting keeps its own", tb[4].attrs.spell1, "Old 4")
checkEq("router: flyout picks write into Ancestors", m1.attrs.action, 84)
checkEq("router: one Call of the Elements would not write, now does", m2.attrs.action, 85)
router.attrs.spPage = 1
run(C.ROUTER, { self = router })
checkEq("router back: Earth casts Elements' again", tb[1].attrs.spell1, "Old 1")
check("router back: the sync-off helper writes nothing to Elements", m2.attrs.type == nil)
checkEq("router back: Ancestors remembered", hdr.attrs.p2e1, "Stoneskin Totem")

hdr.attrs.OpenMenu, hdr.attrs.spOpener = "click", "RightButton"
check("right-click opens, casts nothing", run(C.WRAP_CLICK, { self = dropall, button = "RightButton", control = hdr }) == false)
check("left-click casts", run(C.WRAP_CLICK, { self = dropall, button = "LeftButton", control = hdr }) == nil)
hdr.attrs.OpenMenu = "mouseover"
check("hover mode: right-click casts Totemic Recall", run(C.WRAP_CLICK, { self = dropall, button = "RightButton", control = hdr }) == nil)

-- ---- put back
for e = 1, 4 do ShamanPower_Assignments[SP.player][e] = savedAssign[e] end
for k, v in pairs(was.opt) do SP.opt[k] = v end
SP.db.char.callPage = was.page
for id, v in pairs(was.known) do A.known[id] = v end
GetActionInfo, SetMultiCastSpell, GetMultiCastTotemSpells = was.GetActionInfo, was.SetMultiCastSpell, was.GetMultiCastTotemSpells
C_ActionBar.GetMultiCastBarIndex = was.barIndex
SecureHandlerWrapScript, SecureHandlerUnwrapScript = was.wrap, was.unwrap
SPCompat.snippetOverride = was.snippets
W.fireEvent("SPELLS_CHANGED"); SP:UpdateDropAllButton(); SP:UpdateMiniTotemBar(); __sim.advance(0.3)
finish()
