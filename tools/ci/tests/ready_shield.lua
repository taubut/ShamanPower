-- client: both
-- (3.0.9.17) A CurseForge ask: the shields on Ready Reminders, shown only while missing, so a shield sits in the same
-- frame as the cooldown icons as part of a rotation. One "Shield" entry, the way Weapon Imbue works: shown while
-- neither Lightning Shield nor Water Shield is on you, hidden while one is, with the icon of the shield last on.
-- WoW: Forever in a fight (your buffs hidden from addons): a shield cast puts it up, Shield Charges' Cooldown Manager
-- hook (SP:ReadyShieldHook) says when it went; with neither, the last answer holds until the fight ends.
local SP = ShamanPower
local W = __sim.W
local e
for _, x in ipairs(SP.ReadyReminderSpells or {}) do if x.key == "shield" then e = x end end
check("Shield is in the catalog", e ~= nil and e.shield == true)
if not e then finish() end
check("off by default", e.def == false)
checkEq("its name is Shield, never one shield's name", e.name, "Shield")
check("usable on this client", SP.ReadyReminderUsable(e))

-- the shields known (the sim knows no spells), the buffs as the game would answer
local LS, WS = {}, {}
for _, id in ipairs(SP.ShieldAuraSets[1].ids) do LS[id] = true end
for _, id in ipairs(SP.ShieldAuraSets[2].ids) do WS[id] = true end
local knowLS, knowWS = true, true
local KN = SPCompat.KnowsSpellID
SPCompat.KnowsSpellID = function(id)
	if LS[id] then return knowLS end
	if WS[id] then return knowWS end
	return KN(id)
end
local LS_ID, WS_ID = 10432, SP.ShieldAuraSets[2].ids[1]
for _, id in ipairs(SP.ShieldAuraSets[2].ids) do if SPCompat.SpellExists(id) then WS_ID = id break end end
local on = {}   -- [spellID] = expirationTime
local hidden = false   -- WoW: Forever in a fight: the game answers nothing
local get = C_UnitAuras.GetPlayerAuraBySpellID
C_UnitAuras.GetPlayerAuraBySpellID = function(id)
	if hidden then return nil end
	if on[id] then return { spellId = id, duration = 600, expirationTime = on[id] } end
	return nil
end
local plays = 0
local play = SP.PlaySoundWithVolume
SP.PlaySoundWithVolume = function() plays = plays + 1 end
local function pass() __sim.advance(0.5); SP:UpdateReadyReminders() end
local function cast(id) W.fireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-0", id) end

W.fireEvent("SPELLS_CHANGED")
SP:SetReadyRemindersEnabled(true)
SP:ReadyReminderSetSpell("shield", true)
SP:ReadyReminderSetIconOpt("shield", "soundOnReady", true)
check("learned with either shield", SP.ReadyReminderKnown(e))
on[LS_ID] = GetTime() + 600
pass()
local f = SP.readyReminderFrames.shield
check("its reminder frame is made", f ~= nil)
if not f then finish() end
check("Lightning Shield on: hidden", not f:IsShown())
check("Show is Only When Missing", SP:ReadyReminderShowOf("shield") == "ready")
check("while it is used, Shield Charges keeps its shield hook bound", SP:ReadyShieldWanted())
local lsIcon = SP.ReadyShield.icon()

local n = plays
on = {}; pass()
check("no shield on you: shown", f:IsShown())
checkEq("its Sound when the shield goes", plays - n, 1)
pass()
checkEq("still missing: no second sound", plays - n, 1)
checkEq("its icon is Lightning Shield's (the last on)", f.icon:GetTexture(), lsIcon)

on[WS_ID] = GetTime() + 600; pass()
check("Water Shield on: hidden", not f:IsShown())
on = {}; pass()
check("Water Shield gone: shown", f:IsShown())
check("its icon is Water Shield's now (the last on)", f.icon:GetTexture() == SP.ReadyShield.icon() and SP.ReadyShield.icon() ~= lsIcon,
	tostring(f.icon:GetTexture()) .. " / " .. tostring(lsIcon))

-- a shield that runs out by itself
on[LS_ID] = GetTime() + 3; pass()
check("a shield with 3 s left: hidden", not f:IsShown())
__sim.advance(3); on = {}; pass()
check("run out: shown", f:IsShown())

-- the default spot: just before the spells' row, so no other icon's spot moved
local es = SP.readyReminderFrames.earthshock or SP:CreateReadyReminderFrame((function()
	for _, x in ipairs(SP.ReadyReminderSpells) do if x.key == "earthshock" then return x end end
end)())
local _, _, _, sx = f:GetPoint()
local _, _, _, ex = es:GetPoint()
check("its default spot is just left of the row's first icon", type(sx) == "number" and type(ex) == "number" and ex - sx > 40 and ex - sx < 80,
	tostring(sx) .. " vs " .. tostring(ex))

if SPCompat.FOREVER then
	-- in a fight: the game hides your buffs; no answer is never "missing"
	on[LS_ID] = GetTime() + 600; pass()
	check("before the fight, shield on: hidden", not f:IsShown())
	__sim.setCombat(true); hidden = true; pass()
	check("in a fight, the game silent: still hidden (no answer is not missing)", not f:IsShown())
	n = plays
	SP:ReadyShieldHook(1, false); pass()
	check("the Cooldown Manager says it went: shown, mid-fight", f:IsShown())
	checkEq("its Sound mid-fight", plays - n, 1)
	cast(LS_ID); pass()
	check("you cast Lightning Shield in the fight: hidden", not f:IsShown())
	__sim.advance(30); pass()
	check("no word since: it holds", not f:IsShown())
	cast(WS_ID); SP:ReadyShieldHook(1, false); SP:ReadyShieldHook(2, true); pass()
	check("a swap to Water Shield in a fight: still hidden (a swap is not a loss)", not f:IsShown())
	SP:ReadyShieldHook(2, false); pass()
	check("Water Shield went: shown", f:IsShown())
	cast(WS_ID); pass()
	check("cast again: hidden", not f:IsShown())
	-- its charges spent with no word (no Cooldown Manager): the answer comes when the fight ends
	on = {}
	__sim.setCombat(false); hidden = false; pass()
	check("the fight over, no shield: shown", f:IsShown())
	-- end to end: the game's Cooldown Manager item for Lightning Shield (it and its viewer stand in for Blizzard's),
	-- through Shield Charges' own hook
	check("Shield Charges' hook is here", SP.BindShieldGoneHooks ~= nil)
	if SP.BindShieldGoneHooks then
		local item = { id = 200311 }
		function item:GetCooldownID() return self.id end
		function item:TriggerAuraAppliedAlert() end
		function item:TriggerAuraRemovedAlert() end
		function item:SetAlpha() end
		local viewer = { itemFramePool = { EnumerateActive = function() return pairs({ [item] = true }) end } }
		function viewer:RefreshLayout() end
		local CV, BV = C_CooldownViewer, _G.BuffIconCooldownViewer
		C_CooldownViewer = { GetCooldownViewerCooldownInfo = function(id) if id == 200311 then return { spellID = 324 } end end }
		_G.BuffIconCooldownViewer = viewer
		SP.BindShieldGoneHooks()
		on[LS_ID] = GetTime() + 600; pass()
		__sim.setCombat(true); hidden = true; pass()
		check("Cooldown Manager: in a fight, shield on: hidden", not f:IsShown())
		item:TriggerAuraRemovedAlert(); pass()
		check("Cooldown Manager: its Lightning Shield item says it went: shown", f:IsShown())
		item:TriggerAuraAppliedAlert(); pass()
		check("Cooldown Manager: it says it came back: hidden", not f:IsShown())
		__sim.setCombat(false); hidden = false; pass()
		C_CooldownViewer, _G.BuffIconCooldownViewer = CV, BV
	end
else
	-- Anniversary: your buffs can be read in a fight
	on[LS_ID] = GetTime() + 600; pass()
	__sim.setCombat(true); pass()
	check("in a fight, shield on: hidden", not f:IsShown())
	on = {}; pass()
	check("in a fight, shield gone: shown", f:IsShown())
	__sim.setCombat(false); pass()
end

-- (A116) Show: Always: the icon stays while a shield is on, with the cooldown bar's charge count and charge bar on it
check("Show starts as Only When Missing", SP:ReadyReminderIconOpt("shield", "shieldShow") == "missing")
check("Only When Missing: no charge parts", not (f.shieldSt and f.shieldSt.bar and f.shieldSt.bar:IsShown()))
local charges = 3
local function aura(id, k) on = { [id] = GetTime() + 600 }; charges = k end
local get2 = C_UnitAuras.GetPlayerAuraBySpellID
C_UnitAuras.GetPlayerAuraBySpellID = function(id)
	local a = get2(id)
	if a then a.applications = charges end
	return a
end
SP:ReadyReminderSetIconOpt("shield", "shieldShow", "always")
aura(LS_ID, 3); pass()
check("Always, shield on: shown", f:IsShown())
check("Always, shield on: no glow (it isn't missing)", not f.glowShown)
local st = f.shieldSt
check("its charge parts are made", st ~= nil and st.bar ~= nil)
if st then
	check("Show Charge Bar on to start: the bar inside the icon", st.bar:IsShown())
	local _, rel, _, bx, by = st.bar:GetPoint(1)
	check("the bar sits inside the icon along its bottom", rel == f and by == 2 and bx == 2, tostring(bx) .. "," .. tostring(by))
	if SPCompat.FOREVER then
		check("WoW: Forever: the game draws the count and the fill", SP.ReadyShieldCharges.Diag(f):find("built=true", 1, true) ~= nil,
			SP.ReadyShieldCharges.Diag(f))
		checkEq("WoW: Forever: our own fill stays empty under the game's", st.bar:GetValue(), 0)
		checkEq("WoW: Forever: our own count stays blank", st.corner:GetText(), "")
	else
		checkEq("the bar: 3 charges", st.bar:GetValue(), 3)
		checkEq("Show Charge Count on to start: 3, bottom right", st.corner:GetText(), "3")
		local r, g, b = st.corner:GetTextColor()
		check("3 in green", r < 0.1 and g > 0.9 and b < 0.1)
		aura(LS_ID, 1); pass()
		checkEq("1 charge: the bar", st.bar:GetValue(), 1)
		checkEq("1 charge: the count", st.corner:GetText(), "1")
		r, g, b = st.corner:GetTextColor()
		check("1 in red", r > 0.9 and g < 0.1 and b < 0.1)
		SP:ReadyReminderSetIconOpt("shield", "shieldCountPos", "center"); pass()
		checkEq("Count Position Center: the count in the middle", st.center:GetText(), "1")
		checkEq("Center: none at the bottom right", st.corner:GetText(), "")
		local p = st.center:GetPoint(1)
		checkEq("Center: anchored to the icon's middle", p, "CENTER")
		SP:ReadyReminderSetIconOpt("shield", "shieldCountPos", nil)
		SP:ReadyReminderSetIconOpt("shield", "shieldCount", false); pass()
		checkEq("Show Charge Count off: no count", st.corner:GetText(), "")
		SP:ReadyReminderSetIconOpt("shield", "shieldCount", nil)
	end
	SP:ReadyReminderSetIconOpt("shield", "shieldBar", false); pass()
	check("Show Charge Bar off: no bar", not st.bar:IsShown())
	SP:ReadyReminderSetIconOpt("shield", "shieldBar", nil)
	n = plays
	on = {}; pass()
	check("Always, shield gone: still shown", f:IsShown())
	check("Always, shield gone: its glow", f.glowShown == true)
	checkEq("Always, shield gone: its Sound", plays - n, 1)
	checkEq("Always, shield gone: the bar empty", st.bar:GetValue(), 0)
	checkEq("Always, shield gone: no count", st.corner:GetText(), "")
	aura(LS_ID, 3); pass()
	check("Always, shield back: the glow goes", not f.glowShown)
	SP:ReadyReminderSetIconOpt("shield", "shieldShow", nil); pass()
	check("back to Only When Missing: hidden while the shield is on, as built", not f:IsShown())
	check("back to Only When Missing: the charge parts put away", not st.bar:IsShown())
end
C_UnitAuras.GetPlayerAuraBySpellID = get2
on = {}; pass()

-- neither shield learned: never on screen
knowLS, knowWS = false, false
W.fireEvent("SPELLS_CHANGED"); pass()
check("neither shield learned: not on screen", not f:IsShown())
knowLS, knowWS = true, true
W.fireEvent("SPELLS_CHANGED"); pass()

-- switched off: the hook is no longer wanted
SP:ReadyReminderSetSpell("shield", false); pass()
check("switched off: hidden", not f:IsShown())
check("switched off: the hook no longer wanted", not SP:ReadyShieldWanted())
SP:ReadyReminderSetSpell("shield", true); pass()
check("on again: wanted", SP:ReadyShieldWanted())
SP:SetReadyRemindersEnabled(false); pass()
check("Ready Reminders off: the hook no longer wanted", not SP:ReadyShieldWanted())

SPCompat.KnowsSpellID = KN
C_UnitAuras.GetPlayerAuraBySpellID = get
SP.PlaySoundWithVolume = play
finish()
