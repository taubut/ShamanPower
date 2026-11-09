-- client: both
-- regime: secrets
-- Maelstrom Weapon's Ready Reminder (3.0.9.2, A55): your stacks instead of a cooldown, six looks picked in its
-- menu, drawn by the game (AuraContainer slots on the buff: the count, the stack bars, "from N" and "exactly N"
-- parts) in a fight and out of one; out of combat it hides at 0 stacks; Wings / Fill sit on a spot of their
-- own; the previews draw it with plain frames. Anniversary: not in the list (TBC has no Maelstrom Weapon).
local SP = ShamanPower
local W = __sim.W
local e
for _, x in ipairs(SP.ReadyReminderSpells or {}) do if x.key == "maelstrom" then e = x end end
check("Maelstrom Weapon is in the catalog", e ~= nil and e.stacks ~= nil)
if not SPCompat.FOREVER then
	check("Anniversary: not usable (TBC has no Maelstrom Weapon)", not SP.ReadyReminderUsable(e))
	finish()
end
check("Forever: the stacks file loaded", SP.ReadyStacks ~= nil and SP.ReadyStacksAPI ~= nil)

-- the game's number formatter (the sim has none): breakpoints, the highest one at or under the number
if not C_StringUtil.CreateNumericRuleFormatter then
	C_StringUtil.CreateNumericRuleFormatter = function()
		local f = { rules = {} }
		function f:AddBreakpoint(b) self.rules[#self.rules + 1] = b; table.sort(self.rules, function(x, y) return x.threshold < y.threshold end); return true end
		function f:FormatNumber(n)
			local pick
			for _, b in ipairs(self.rules) do if n >= b.threshold then pick = b end end
			return pick and (pick.format:find("%%d") and pick.format:format(n) or pick.format) or ""
		end
		return f
	end
end
SP.ReadyStacksAPI.Buff.engine = nil   -- (probe the engine again, with the formatter there)

-- the sim's spell data has no talent spell: it exists and is known
local SE, KN = SPCompat.SpellExists, SPCompat.KnowsSpellID
SPCompat.SpellExists = function(id) if id == 408498 then return true end return SE(id) end
SPCompat.KnowsSpellID = function(id) if id == 408498 then return true end return KN(id) end
e.clientID = nil
W.fireEvent("SPELLS_CHANGED")
check("usable on Forever", SP.ReadyReminderUsable(e))
check("learned (the talent)", SP.ReadyReminderKnown(e))

-- the buff, as the game would answer out of combat
local stacks = 0
local get = C_UnitAuras.GetPlayerAuraBySpellID
C_UnitAuras.GetPlayerAuraBySpellID = function(id)
	if id == 408505 then
		if stacks <= 0 then return nil end
		return { applications = stacks, expirationTime = GetTime() + 20, duration = 30, spellId = 408505 }
	end
	return get and get(id)
end
local function setStacks(n) stacks = n; W.fireEvent("UNIT_AURA", "player", {}); SP:UpdateReadyReminders(); __sim.advance(0.1) end

local sv = ShamanPower_ReadyReminders
sv.enabled = true
SP:ReadyReminderSetSpell("maelstrom", true)
setStacks(0)
local f = SP.readyReminderFrames.maelstrom
check("its reminder frame is made", f ~= nil)
check("out of combat, 0 stacks: hidden", f and not f:IsShown())
setStacks(3)
check("out of combat, 3 stacks: shown", f and f:IsShown())
local st = f and f.stack
check("drawn by the game (engine)", st and st.mode == "engine", st and st.mode)
local diag = SP.ReadyStacks.Diag(f)
check("the game's parts built, none refused", diag:find("failed=false") ~= nil and not diag:find("containers=0"), diag)

-- in a fight: it stays on screen, whatever the stacks (the game decides what is drawn)
__sim.setCombat(true)
setStacks(0)
check("in a fight, 0 readable stacks: still on screen", f:IsShown())
__sim.setCombat(false)
setStacks(0)
check("after the fight, 0 stacks: hidden again", not f:IsShown())

-- Show: Only At 5 Stacks
SP:ReadyReminderSetIconOpt("maelstrom", "stackShow", "five")
setStacks(4)
check("Only At 5 Stacks: 4 stacks hidden", not f:IsShown())
setStacks(5)
check("Only At 5 Stacks: 5 stacks shown", f:IsShown())
SP:ReadyReminderSetIconOpt("maelstrom", "stackShow", nil)

-- each look: the game's parts (main; From N; Exactly N; the Effect's glow; 3.0.9.9: + the sound's part At 5 Stacks)
local want = { number = 3, bar = 4, baronly = 8, wings = 8, fill = 3, iconfill = 3, storm = 7 }
for _, look in ipairs({ "number", "bar", "baronly", "wings", "fill", "iconfill", "storm" }) do
	SP:ReadyReminderSetIconOpt("maelstrom", "stackLook", look)
	setStacks(2)
	local d = SP.ReadyStacks.Diag(f)
	local n = tonumber(d:match("containers=(%d+)"))
	checkEq(look .. ": the game's parts", n, want[look])
	check(look .. ": none refused", d:find("failed=false") ~= nil, d)
end
-- Time Left and Stack Number add no parts of their own (they ride on the main one)
SP:ReadyReminderSetIconOpt("maelstrom", "stackLook", "storm")
SP:ReadyReminderSetIconOpt("maelstrom", "stackLeft", "drain")
SP:ReadyReminderSetIconOpt("maelstrom", "stackNumber", true)
setStacks(2)
checkEq("storm + drain + number: the same parts", tonumber(SP.ReadyStacks.Diag(f):match("containers=(%d+)")), 7)
SP:ReadyReminderSetIconOpt("maelstrom", "readyEffect", "both")
setStacks(2)
checkEq("Effect Glow + Pulse: one part more", tonumber(SP.ReadyStacks.Diag(f):match("containers=(%d+)")), 8)

-- Wings / Fill: three icons wide, a spot of its own (never in the grid)
SP:ReadyReminderSetIconOpt("maelstrom", "stackLook", "wings")
SP:UpdateAllReadyReminderAppearance()
setStacks(3)
local w, h = f:GetSize()
check("Wings: 150 x 75 at Size 48", math.abs(w - 150) < 0.5 and math.abs(h - 75) < 0.5, w .. "x" .. h)
-- Charge Bar Only: the bar alone, as wide as Wings, a third of Size tall (or its Bar Height)
SP:ReadyReminderSetIconOpt("maelstrom", "stackLook", "baronly")
SP:UpdateAllReadyReminderAppearance()
setStacks(3)
w, h = f:GetSize()
check("Charge Bar Only: 150 x 14 at Size 48", math.abs(w - 150) < 0.5 and math.abs(h - 14) < 0.5, w .. "x" .. h)
SP:ReadyReminderSetIconOpt("maelstrom", "stackBarHeight", 22)
SP:UpdateAllReadyReminderAppearance()
w, h = f:GetSize()
check("its own Bar Height", math.abs(h - 22) < 0.5, w .. "x" .. h)
SP:ReadyReminderSetIconOpt("maelstrom", "stackBarHeight", nil)
SP:ReadyReminderSetIconOpt("maelstrom", "stackLook", "wings")
SP:UpdateAllReadyReminderAppearance()
setStacks(3)
local prevArrange = sv.arrange
sv.arrange = "grid"
SP:UpdateAllReadyReminderAppearance(); setStacks(3)
local _, rel = f:GetPoint(1)
check("Grid placement: Wings stays on its own spot", rel == UIParent, rel and rel.GetName and rel:GetName())
local movers = SP:ReadyReminderMoverFrames()
local hasOwn = false
for _, m in ipairs(movers) do if m == f then hasOwn = true end end
check("Unlock UI: Wings gets a box of its own beside the grid's", hasOwn)
-- Rows placement: dragged down to Not On A Row it's off your screen; back up: its own spot again
sv.arrange = "rows"
SP:UpdateAllReadyReminderAppearance(); setStacks(3)
check("Rows: Wings on its own spot, shown", f:IsShown() and not SP:ReadyOwnOff("maelstrom"))
SP:ReadySetOwnOff("maelstrom", true)
setStacks(3)
check("Rows: Not On A Row, off your screen", not f:IsShown())
local inMovers = false
for _, m in ipairs(SP:ReadyReminderMoverFrames()) do if m == f then inMovers = true end end
check("Rows: no Unlock UI box while it's off", not inMovers)
SP:ReadySetOwnOff("maelstrom", false)
setStacks(3)
check("Rows: back on its own spot", f:IsShown())
sv.arrange = prevArrange
SP:UpdateAllReadyReminderAppearance()

-- the previews: plain frames, counting up
SP:ReadyRemindersDemo(true)
__sim.advance(2.5)
check("the preview draws it itself (paint)", f.stack.mode == "paint")
check("the preview shows it", f:IsShown())
SP:ReadyRemindersDemo(false)
setStacks(3)
check("after the preview: drawn by the game again", f.stack.mode == "engine")

-- its menu
local Row = SP.ReadyIconsRow
if Row then
	local items = Row.def.menu({ key = "maelstrom" })
	local byText = {}
	for _, it in ipairs(items) do if it.text then byText[it.text] = it end end
	check("menu: Look", byText.Look ~= nil)
	check("menu: Stacks", byText.Stacks ~= nil)
	check("menu: At 5 Stacks", byText["At 5 Stacks"] ~= nil)
	check("menu: no Out of Range", byText["Out of Range"] == nil)
	local lookSub = byText.Look and byText.Look.sub()
	checkEq("Look: seven looks", lookSub and #lookSub, 7)
	local showSub = byText.Show and byText.Show.sub()
	checkEq("Show: three choices", showSub and #showSub, 3)
	if lookSub then lookSub[2].onClick() end
	checkEq("a click on Charge Bar saves it", SP:ReadyReminderIconOpt("maelstrom", "stackLook"), "bar")
	local stackRows = byText.Stacks and byText.Stacks.sub()
	check("Stacks: Stack Number, Time Left and the two colors", stackRows and #stackRows >= 5)
	-- Test Icon: the look counting up 1 to 5 on the icon, then back to the real stacks
	local test = byText["Test Icon"]
	check("menu: Test Icon", test ~= nil and not test.disabled)
	setStacks(0)
	check("0 stacks: hidden before the test", not f:IsShown())
	if test then test.onClick() end
	__sim.advance(0.3)
	check("Test Icon shows the icon", f:IsShown() and f.stack.mode == "paint")
	SP:UpdateReadyReminders()
	check("a pass during the test leaves it up", f:IsShown())
	__sim.advance(7)
	check("the test ends on its own", f.spStacksTest == nil)
	check("then the icon follows the real stacks again (0: hidden)", not f:IsShown())
else
	check("the Spells row is reachable", false)
end

-- copies: the stacks' settings never land on another icon
SP:ReadyReminderCopyIcon("maelstrom", "stormstrike")
check("Copy Settings To Stormstrike: no stack settings on it", SP:ReadyReminderOwnOpt("stormstrike", "stackLook") == nil)
SP:ReadyReminderResetIcon("stormstrike")
SP:ReadyReminderResetIcon("maelstrom")
SP:ReadyReminderSetSpell("maelstrom", false)
C_UnitAuras.GetPlayerAuraBySpellID = get
SPCompat.SpellExists, SPCompat.KnowsSpellID = SE, KN
finish()
