-- client: both
-- (3.0.9.17, a Discord ask 11-19: Windfury and Searing Totem at rank 1 to save mana) Rank in a totem's right-click
-- menu on Totem Bar > Bar. Every place ShamanPower casts the totem follows it: the bar's button, its flyout (cast,
-- assign and mySpell alike), Drop All, the SP_ macros, Quick Totems, the twist (Anniversary), the tooltip. A rank not
-- learned yet casts the closest lower one learned; picked at or above the highest known, nothing changes. Highest,
-- Reset This Totem and Reset Page take it back; a fight holds it until it ends; a profile has its own.
local SP = ShamanPower
local A = __sim.A
local W = __sim.W
if not (SP.SetTotemRank and SPCompat.TotemCastSpell and SP.TotemBarRows and SP.TotemBarRows.totems) then skip("no totem ranks here") end
local FIRE, SEARING = 2, 3599
local ranks = SPCompat.SpellRanks(SEARING)
if not (ranks and #ranks > 2) then skip("Searing Totem has fewer than three ranks here") end
local idx
for i, id in pairs(SP.Totems[FIRE] or {}) do if id == SEARING then idx = i end end
if not idx then skip("no Searing Totem in the Fire list") end
local o = SP.opt
local keep = { rank = o.totemRank, qt = o.quickTotems, picks = o.quickTotemPicks, fire = ShamanPower_Assignments[SP.player][FIRE] }
local knownKeep = {}
for _, id in ipairs(ranks) do knownKeep[id] = A.known[id] end
local function know(top, gaps)
	for n, id in ipairs(ranks) do A.known[id] = (n <= top and not (gaps and gaps[n])) or nil end
	SPCompat.InvalidateSpellData()
end
know(#ranks)

local name = SPCompat.SpellName(SEARING)
local getSub = rawget(_G, "GetSpellSubtext") or (C_Spell and C_Spell.GetSpellSubtext)
local function rankText(n)
	local sub = getSub and getSub(ranks[n])
	if type(sub) ~= "string" or sub == "" then sub = "Rank " .. n end
	return SPCompat.SpellName(ranks[n]) .. "(" .. sub .. ")"
end
check("Searing Totem has a name", name ~= nil)

-- the macros as UpdateSPMacros writes them (the sim keeps none)
local bodies = {}
local realMacro = SP.CreateOrUpdateMacro
SP.CreateOrUpdateMacro = function(_, mname, _, body) bodies[mname] = body return "updated" end

SP:ApplyAssignment(FIRE, idx)
o.quickTotems = true
SP:SetQuickTotemSlot(FIRE, idx, 1)
local function bar() return _G["ShamanPowerAutoTotem" .. FIRE] end
local function flyBtn()
	local f = SP.totemFlyouts and SP.totemFlyouts[FIRE]
	for _, b in ipairs(f and f.allButtons or {}) do if b.totemIndex == idx then return b end end
end
local function flyCast(b) return b and (b:GetAttribute("spell1") or b:GetAttribute("spell2") or b:GetAttribute("spell")) end
local function quick() local q = _G["ShamanPowerQuickTotem" .. FIRE .. "_1"] return q and q:GetAttribute("spell") end
local function everywhere(label, want)
	if bar() then checkEq(label .. ": the bar's button", bar():GetAttribute("spell1"), want) end
	local b = flyBtn()
	check(label .. ": its flyout button is there", b ~= nil)
	checkEq(label .. ": the flyout casts it", flyCast(b), want)
	checkEq(label .. ": the flyout assigns it (mySpell)", b and b:GetAttribute("mySpell"), want)
	check(label .. ": Drop All casts it", (SP.dropAllLastMacro or ""):find(want, 1, true) ~= nil)
	wipe(bodies)
	SP:UpdateSPMacros()
	checkEq(label .. ": SP_Fire", bodies.SP_Fire, "#showtooltip\n/cast " .. want)
	check(label .. ": SP_DropAll", (bodies.SP_DropAll or ""):find(want, 1, true) ~= nil)
	checkEq(label .. ": Quick Totem", quick(), want)
end

-- as always: the plain name (the highest rank)
SP:RefreshTotemCasts()
everywhere("Highest", name)
checkEq("Highest: the tooltip shows the top rank", SPCompat.TotemTooltipID(SEARING), ranks[#ranks])

-- Rank 1 picked
SP:SetTotemRank(SEARING, 1)
checkEq("saved in the profile", o.totemRank and o.totemRank[SEARING], 1)
everywhere("Rank 1", rankText(1))
checkEq("Rank 1: the tooltip shows rank 1", SPCompat.TotemTooltipID(SEARING), ranks[1])
check("Rank 1: the name on screen stays plain", SP:GetTotemName(FIRE, idx) == name or not tostring(SP:GetTotemName(FIRE, idx)):find("(", 1, true))
-- any rank of the totem asks the same (a flyout button carries rank 1's ID, others the top one's)
checkEq("asked by another rank's ID: the same", SPCompat.TotemCastSpell(ranks[#ranks]), rankText(1))

-- a rank not learned yet
SP:SetTotemRank(SEARING, 3)
know(2)
checkEq("Rank 3, only 2 learned: the highest (nothing changes)", SPCompat.TotemCastSpell(SEARING), name)
know(#ranks)
checkEq("Rank 3, all learned", SPCompat.TotemCastSpell(SEARING), rankText(3))
know(#ranks, { [2] = true, [3] = true })
checkEq("Rank 3, ranks 2-3 not learned: the closest lower one (1)", SPCompat.TotemCastSpell(SEARING), rankText(1))
know(#ranks, { [1] = true, [2] = true, [3] = true })
checkEq("Rank 3, no lower rank reported (Classic reports the highest only): rank 3", SPCompat.TotemCastSpell(SEARING), rankText(3))
know(#ranks)

-- the menu: Rank, its value, a pick, Highest
local row = SP.TotemBarRows.totems
local item = { key = SEARING, e = FIRE, idx = idx, name = name }
local function menuItem(it, text)
	for _, x in ipairs(row.def.menu(it)) do if x.text == text then return x end end
end
local rk = menuItem(item, "Rank")
check("the menu has Rank", rk ~= nil)
if rk then
	local v, own = rk.value()
	checkEq("its value", v, "Rank 3")
	check("marked as changed", own == true)
	local sub = rk.sub()
	checkEq("Highest first", sub[1].text, "Highest")
	local n = 0
	for _, x in ipairs(sub) do if type(x.text) == "string" and x.text:match("^Rank %d+$") then n = n + 1 end end
	checkEq("one row per rank", n, #ranks)
	for _, x in ipairs(sub) do if x.text == "Rank 2" then x.onClick() end end
	checkEq("Rank 2 picked from the menu", SP:TotemRankChoice(SEARING), 2)
	sub = rk.sub()
	sub[1].onClick()
	checkEq("Highest from the menu: nothing saved", o.totemRank, nil)
	everywhere("Highest again", name)
end
local tremorIdx, tremor
for i, id in pairs(SP.Totems[1] or {}) do
	if not (SPCompat.SpellRanks(id) and #SPCompat.SpellRanks(id) > 1) then tremorIdx, tremor = i, id break end
end
if tremor then
	check("a totem with one rank has no Rank", menuItem({ key = tremor, e = 1, idx = tremorIdx, name = "x" }, "Rank") == nil)
end

-- Reset This Totem
SP:SetTotemRank(SEARING, 1)
local reset = menuItem(item, "Reset This Totem")
check("Reset This Totem is on", reset and not reset.disabled)
if reset then reset.onClick() end
checkEq("Reset This Totem: its highest rank", SP:TotemRankChoice(SEARING), nil)
checkEq("Reset This Totem: the bar casts the highest", flyCast(flyBtn()), name)

-- a fight: written when it ends
__sim.setCombat(true)
SP:SetTotemRank(SEARING, 1)
check("in a fight: waiting", SP.totemCastsPending == true)
checkEq("in a fight: the flyout keeps the old cast", flyCast(flyBtn()), name)
__sim.setCombat(false)
check("after the fight: done", not SP.totemCastsPending)
checkEq("after the fight: the flyout casts rank 1", flyCast(flyBtn()), rankText(1))

-- a profile of its own
local db = SP.db
local start = db:GetCurrentProfile()
db:SetProfile("Totem Rank Test")
SP:ApplyAssignment(FIRE, idx)
checkEq("another profile: the highest", flyCast(flyBtn()), name)
db:SetProfile(start)
o = SP.opt
checkEq("back: rank 1 again", flyCast(flyBtn()), rankText(1))
db:DeleteProfile("Totem Rank Test", true)

-- the twist (Anniversary: Forever has no twisting)
if not SPCompat.FOREVER and SPCompat.SpellRanks(8512) and #SPCompat.SpellRanks(8512) > 1 then
	SP:SetTotemRank(8512, 1)
	o.enableTotemTwisting = true
	SP:RefreshTotemCasts()
	local air = _G["ShamanPowerAutoTotem4"]
	local wfRanks = SPCompat.SpellRanks(8512)
	local wfSub = getSub and getSub(wfRanks[1])
	if type(wfSub) ~= "string" or wfSub == "" then wfSub = "Rank 1" end
	check("the twist casts Windfury rank 1", air and (air:GetAttribute("macrotext1") or ""):find(SPCompat.SpellName(8512) .. "(" .. wfSub .. ")", 1, true) ~= nil)
	o.enableTotemTwisting = nil
	SP:SetTotemRank(8512, nil)
end

-- Reset Page
SP:SetTotemRank(SEARING, 1)
SP.TotemBarResetPage(SP)
checkEq("Reset Page: no ranks saved", o.totemRank, nil)
checkEq("Reset Page: the flyout casts the highest", flyCast(flyBtn()), name)

-- put back
o.totemRank, o.quickTotems, o.quickTotemPicks = keep.rank, keep.qt, keep.picks
for id, v in pairs(knownKeep) do A.known[id] = v end
SPCompat.InvalidateSpellData()
SP:ApplyAssignment(FIRE, keep.fire or 0)
SP:RefreshTotemCasts()
SP.CreateOrUpdateMacro = realMacro
finish()
