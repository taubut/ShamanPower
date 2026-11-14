-- client: forever
-- regime: secrets
-- (3.0.9.13, a player's report: "Maelstrom doesn't appear when set in Ready Reminders") Maelstrom Weapon's
-- reminder with Only In Combat on: out of combat it is hidden, and a fight cannot make the game's parts that
-- draw its stacks, so they were never made and the reminder had nothing to draw in a fight. They are made out
-- of combat now, while it is hidden; in a fight it shows with them, in Grid and in Rows alike.
local SP = ShamanPower
if not (SP.ReadyStacks and SP.ReadyStacksAPI) then skip("no Maelstrom Weapon reminder here") end
local W = __sim.W
local sv = ShamanPower_ReadyReminders
local e
for _, x in ipairs(SP.ReadyReminderSpells or {}) do if x.key == "maelstrom" then e = x end end
if not C_StringUtil.CreateNumericRuleFormatter then
	C_StringUtil.CreateNumericRuleFormatter = function()
		local f = { rules = {} }
		function f:AddBreakpoint(b) self.rules[#self.rules + 1] = b; table.sort(self.rules, function(x, y) return x.threshold < y.threshold end); return true end
		function f:FormatNumber(n) local pick for _, b in ipairs(self.rules) do if n >= b.threshold then pick = b end end return pick and (pick.format:find("%%d") and pick.format:format(n) or pick.format) or "" end
		return f
	end
end
SP.ReadyStacksAPI.Buff.engine = nil
local SE, KN = SPCompat.SpellExists, SPCompat.KnowsSpellID
SPCompat.SpellExists = function(id) if id == 408498 then return true end return SE(id) end
SPCompat.KnowsSpellID = function(id) if id == 408498 then return true end return KN(id) end
e.clientID = nil
W.fireEvent("SPELLS_CHANGED")
local stacks = 3
local get = C_UnitAuras.GetPlayerAuraBySpellID
C_UnitAuras.GetPlayerAuraBySpellID = function(id)
	if id == 408505 then if stacks <= 0 then return nil end return { applications = stacks, expirationTime = GetTime() + 20, duration = 30, spellId = 408505 } end
	return get and get(id)
end
sv.enabled = true
local function containers()
	local d = SP.ReadyStacks.Diag(SP.readyReminderFrames.maelstrom)
	return tonumber(d:match("containers=(%d+)")) or 0, d:find("waiting=true", 1, true) ~= nil
end
local function pass() W.fireEvent("UNIT_AURA", "player", {}); SP:UpdateReadyReminders(); __sim.advance(0.3); SP:UpdateReadyReminders(); __sim.advance(0.3) end
local was = { rows = sv.rows, arrange = sv.arrange, oic = sv.onlyInCombat, own = SP:ReadyReminderIconOpt("maelstrom", "onlyInCombat") }
-- (the player's own: Only In Combat on in the icon's menu, and on the page)
local function oic(on) sv.onlyInCombat = on; SP:ReadyReminderSetIconOpt("maelstrom", "onlyInCombat", on) end
sv.enabled = true
-- as the player has it from the start: Only In Combat on before the reminder is ever on screen
sv.arrange = "grid"
oic(true)
__sim.setCombat(false)
SP:ReadyReminderSetSpell("maelstrom", true)
for _, arrange in ipairs({ "grid", "rows" }) do
	sv.arrange = arrange
	if arrange == "rows" then sv.rows = { { spells = { "maelstrom" } } } end   -- (on a row: Rows shows only what is on one)
	oic(true)
	__sim.setCombat(false); pass()
	local f = SP.readyReminderFrames.maelstrom
	check(arrange .. ", Only In Combat, out of combat: hidden", f and not f:IsShown(),
		string.format("f=%s shown=%s inCombat=%s oic=%s iconOic=%s test=%s", tostring(f ~= nil), tostring(f and f:IsShown()),
			tostring(InCombatLockdown()), tostring(sv.onlyInCombat), tostring(SP.ReadyReminderIconOpt and SP:ReadyReminderIconOpt("maelstrom", "onlyInCombat")),
			tostring(f and f.spStacksTest)))
	local n = containers()
	check(arrange .. ": the game's parts are made already", n > 0, tostring(n))
	__sim.setCombat(true); pass()
	local n2, waiting = containers()
	check(arrange .. ", in a fight: shown", f and f:IsShown() and f:IsVisible())
	check(arrange .. ", in a fight: with its game parts", n2 > 0 and not waiting, tostring(n2))
	__sim.setCombat(false)
	oic(false); pass()
	check(arrange .. ", Only In Combat off: shown out of combat with its stacks, as before", f and f:IsShown())
end
sv.arrange, sv.onlyInCombat, sv.rows = was.arrange, was.oic, was.rows
SP:ReadyReminderSetIconOpt("maelstrom", "onlyInCombat", nil)
stacks = 0; pass()
SPCompat.SpellExists, SPCompat.KnowsSpellID = SE, KN
C_UnitAuras.GetPlayerAuraBySpellID = get
e.clientID = nil
W.fireEvent("SPELLS_CHANGED")
finish()
