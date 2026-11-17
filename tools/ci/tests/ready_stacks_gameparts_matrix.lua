-- client: forever
-- regime: secrets
-- regime: gameparts
-- (3.0.9.15) Every Maelstrom Weapon setup against the game's refusals on its aura buttons (the sim's game parts
-- regime: a frame moved onto them, a script on them, a script on a bar the game shows). The Proc Glow error of
-- 3.0.9.15 hid in one combination no test had tried (At 5 Stacks Glow + Glow Shape Proc Glow), so this walks
-- them all: every Look with every Effect and Glow Shape, Glow Only In Combat and Sound on and off, then every
-- Show, Time Left and Show Number, each through 0, 3 and 5 stacks in and out of a fight.
local SP = ShamanPower
local W = __sim.W
local e
for _, x in ipairs(SP.ReadyReminderSpells or {}) do if x.key == "maelstrom" then e = x end end
if not (e and SP.ReadyStacks and SP.ReadyStacksAPI and W.foreverClasses and W.onGameButton) then skip("no Maelstrom Weapon reminder or game parts regime here") end

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
SP.ReadyStacksAPI.Buff.engine = nil
local SE, KN = SPCompat.SpellExists, SPCompat.KnowsSpellID
SPCompat.SpellExists = function(id) if id == 408498 then return true end return SE(id) end
SPCompat.KnowsSpellID = function(id) if id == 408498 then return true end return KN(id) end
e.clientID = nil
W.fireEvent("SPELLS_CHANGED")
local stacks = 0
local get = C_UnitAuras.GetPlayerAuraBySpellID
C_UnitAuras.GetPlayerAuraBySpellID = function(id)
	if id == 408505 then
		if stacks <= 0 then return nil end
		return { applications = stacks, expirationTime = GetTime() + 20, duration = 30, spellId = 408505 }
	end
	return get and get(id)
end
local function setStacks(n)
	stacks = n
	__sim.auraApplications(n)
	W.fireEvent("UNIT_AURA", "player", {}); SP:UpdateReadyReminders(); __sim.advance(0.1)
end
local play = SP.PlaySoundWithVolume
SP.PlaySoundWithVolume = function() end

-- every error the addon hands to the error handler, with the setup it came from
local errs, bad, label = {}, {}, ""
local geh = geterrorhandler
geterrorhandler = function() return function(err)
	errs[#errs + 1] = tostring(err)
	if not bad[label] then bad[label] = tostring(err); bad[#bad + 1] = label end
end end
local function walk(l)
	label = l
	setStacks(0); setStacks(3); setStacks(5); setStacks(1)
	__sim.setCombat(true); __sim.advance(0.2)
	setStacks(3); setStacks(5); setStacks(0); setStacks(5)
	__sim.setCombat(false); __sim.advance(0.3)
	setStacks(0)
end
local function opt(k, v)   -- (a refusal while an option changes: named by that change and the setup before it)
	label = ("setting %s = %s (after: %s)"):format(k, tostring(v), label)
	SP:ReadyReminderSetIconOpt("maelstrom", k, v)
end

ShamanPower_ReadyReminders.enabled = true
SP:ReadyReminderSetSpell("maelstrom", true)
local LOOKS = { "number", "bar", "wings", "fill", "iconfill", "storm", "baronly", "numberonly" }
local EFFECTS = { "glow", "pulse", "both", "none" }
local SHAPES = {}
for _, s in ipairs(SP.GLOW_SHAPES or {}) do SHAPES[#SHAPES + 1] = s.key end
local n = 0
for _, look in ipairs(LOOKS) do
	opt("stackLook", look)
	for _, fx in ipairs(EFFECTS) do
		opt("readyEffect", fx)
		for _, shape in ipairs(SHAPES) do
			opt("glowShape", shape)
			for _, gco in ipairs({ false, true }) do
				opt("glowCombatOnly", gco or nil)
				for _, snd in ipairs({ false, true }) do
					opt("soundOnReady", snd or nil)
					walk(("%s / %s / %s / glowCombatOnly=%s / sound=%s"):format(look, fx, shape, tostring(gco), tostring(snd)))
					n = n + 1
				end
			end
			if fx == "pulse" or fx == "none" then break end   -- (no glow: the shape draws nothing)
		end
	end
end
opt("readyEffect", "both"); opt("glowShape", "proc"); opt("glowCombatOnly", nil); opt("soundOnReady", true)
for _, look in ipairs(LOOKS) do
	opt("stackLook", look)
	for _, show in ipairs({ "stacks", "five", "always" }) do
		opt("stackShow", show)
		for _, left in ipairs({ "off", "number", "drain" }) do
			opt("stackLeft", left)
			for _, num in ipairs({ false, true }) do
				opt("stackNumber", num or nil)
				for _, oic in ipairs({ false, true }) do
					opt("onlyInCombat", oic or nil)
					walk(("%s / show=%s / left=%s / number=%s / onlyInCombat=%s"):format(look, show, left, tostring(num), tostring(oic)))
					n = n + 1
				end
			end
		end
	end
end
label = ""
local list = {}
for i = 1, math.min(#bad, 6) do list[#list + 1] = bad[i] .. "  ->  " .. bad[bad[i]] end
check(("%d setups walked: none hands the game something it refuses"):format(n), #bad == 0, #bad .. " refused: " .. table.concat(list, " || "))

geterrorhandler = geh
SP.PlaySoundWithVolume = play
SP:ReadyReminderResetIcon("maelstrom")
SP:ReadyReminderSetSpell("maelstrom", false)
C_UnitAuras.GetPlayerAuraBySpellID = get
SPCompat.SpellExists, SPCompat.KnowsSpellID = SE, KN
finish()
