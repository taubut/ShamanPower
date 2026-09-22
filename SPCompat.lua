-- ============================================================================
-- SPCompat.lua
-- WoW Forever / modern-client compatibility layer + beta diagnostics.
-- Loads FIRST and depends on nothing (not even the ShamanPower table), so the
-- error collector below catches load-time errors in every later file.
--
-- Three jobs:
--   1. POLYFILLS: define removed classic globals from their modern C_*
--      namespaces - only when the old global is MISSING, so on TBC Anniversary
--      (which still has both) this whole section is a no-op.
--   2. /sperrors: a built-in Lua error collector (no BugSack exists for
--      Forever). Errors persist in the ShamanPowerErrorLog SavedVariable.
--   3. /spdiag: the beta day-one probe battery - prints a copyable report and
--      stores it in the SavedVariable so it can be read from the WTF folder.
-- ============================================================================

-- The table is created here, before the polyfill section, because a couple of
-- the shims below hang functions off it. It is assigned again lower down
-- where the rest of its fields are set; that second line is a harmless no-op.
SPCompat = SPCompat or {}

-- Last-resort stub. If anything below this line throws, the rest of the file
-- never runs, and every caller that does SPCompat.SpellExists(id) would error
-- on a hot path. Defining it up front means a broken compat layer degrades to
-- "trust the name lookup" instead of thousands of errors a second.
if not SPCompat.SpellExists then
	function SPCompat.SpellExists(id) return GetSpellInfo and GetSpellInfo(id) ~= nil end
end

-- ---------------------------------------------------------------------------
-- 1. Polyfills (inert wherever the classic globals still exist)
-- ---------------------------------------------------------------------------
if not GetSpellInfo and C_Spell and C_Spell.GetSpellInfo then
	-- C_Spell.GetSpellInfo builds a NEW table on every call; the classic global
	-- it stands in for returned plain values and cost nothing. The addon calls
	-- GetSpellInfo(id) from its 10 Hz loops (every totem and flyout button, the
	-- cooldown model's name lookup, Ready Reminders), which on this client came to
	-- about 100 KB of garbage per second (measured with /spperf: progressBars
	-- 8 KB per call). A spell ID's info never changes, so it is kept: one table
	-- per distinct ID for the session instead of one per call.
	-- Only numeric IDs are kept. A NAME lookup answers "is this in my spellbook
	-- right now", which changes with training and respecs, and the addon uses it
	-- as exactly that test. A nil answer is never kept either (spell data can
	-- arrive late while the UI loads).
	local infoByID = {}
	function GetSpellInfo(spell)
		local isID = type(spell) == "number"
		if isID then
			local c = infoByID[spell]
			if c then return c[1], "", c[2], c[3], c[4], c[5], c[6] end
		end
		local s = C_Spell.GetSpellInfo(spell)
		if not s then return nil end
		if isID then infoByID[spell] = { s.name, s.iconID, s.castTime, s.minRange, s.maxRange, s.spellID } end
		-- classic order: name, rank, icon, castTime, minRange, maxRange, spellID
		return s.name, "", s.iconID, s.castTime, s.minRange, s.maxRange, s.spellID
	end
end

if not GetSpellTexture and C_Spell and C_Spell.GetSpellTexture then
	function GetSpellTexture(spell)
		return C_Spell.GetSpellTexture(spell)
	end
end

if not GetSpellCooldown and C_Spell and C_Spell.GetSpellCooldown then
	-- C_Spell.GetSpellCooldown also builds a new table per call, and the loops ask
	-- ten times a second per spell. A cooldown's (start, duration) pair does not
	-- change between the client's own change notices, so the answer is kept until
	-- the next SPELL_UPDATE_COOLDOWN (or charges / spellbook / combat edge), with
	-- two safety nets: nothing is kept longer than five seconds, and a run that has
	-- ended by the clock is read again at once. Measured with /spperf: the two
	-- 10 Hz loops were at 1 KB per call from this alone.
	-- In combat the numbers are secret values: they are kept and handed on like
	-- any other value, never compared or added here.
	local cdCache, cdStamp = {}, {}
	local CD_TTL = 5.0
	local function cooldownTable(spell)
		if spell == nil then return nil end
		local now = GetTime()
		local c = cdCache[spell]
		if c ~= nil and (now - cdStamp[spell]) < CD_TTL then
			if c == false then return nil end
			local st, du = c.startTime, c.duration
			local secret = issecretvalue and (issecretvalue(st) or issecretvalue(du))
			if secret or type(st) ~= "number" or type(du) ~= "number" or st <= 0 or (st + du) > now then
				return c
			end
			-- ran out by the clock: fall through and read the new state
		end
		c = C_Spell.GetSpellCooldown(spell)
		cdCache[spell], cdStamp[spell] = c or false, now
		return c
	end
	SPCompat = SPCompat or {}
	SPCompat.CooldownTable = cooldownTable
	do
		local f = CreateFrame("Frame")
		for _, ev in ipairs({ "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_CHARGES", "SPELLS_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD" }) do
			pcall(f.RegisterEvent, f, ev)
		end
		f:SetScript("OnEvent", function() wipe(cdCache) end)
	end

	function GetSpellCooldown(spell)
		local c = cooldownTable(spell)
		if not c then return 0, 0, 0 end
		-- classic order: start, duration, enabled (number), modRate
		return c.startTime, c.duration, c.isEnabled and 1 or 0, c.modRate
	end
end

do
	local function auraToClassic(a)
		if not a then return nil end
		-- classic order: name, icon, count, debuffType, duration, expirationTime,
		-- source, isStealable, nameplateShowPersonal, spellId, ...
		return a.name, a.icon, a.applications, a.dispelName, a.duration,
			a.expirationTime, a.sourceUnit, a.isStealable, a.nameplateShowPersonal,
			a.spellId, a.canApplyAura, a.isBossAura, a.isFromPlayerOrPlayerPet,
			a.nameplateShowAll, a.timeMod
	end
	if not UnitBuff and C_UnitAuras and C_UnitAuras.GetBuffDataByIndex then
		function UnitBuff(unit, index, filter)
			return auraToClassic(C_UnitAuras.GetBuffDataByIndex(unit, index, filter))
		end
	end
	if not UnitDebuff and C_UnitAuras and C_UnitAuras.GetDebuffDataByIndex then
		function UnitDebuff(unit, index, filter)
			return auraToClassic(C_UnitAuras.GetDebuffDataByIndex(unit, index, filter))
		end
	end
	if not UnitAura and C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
		function UnitAura(unit, index, filter)
			return auraToClassic(C_UnitAuras.GetAuraDataByIndex(unit, index, filter))
		end
	end
end

-- ---------------------------------------------------------------------------
-- Weapon imbues.
--
-- MEASURED on Forever beta 1.60.1.69913 with Rockbiter applied:
--   GetWeaponEnchantInfo()                        -> [1]=false [5]=false [9]=false
--   C_PaperDollInfo.GetTemporaryEnchantmentInfo(16) -> nothing
--   C_Item.GetWeaponEnchantInfo(0)                -> a LIST:
--        [1] = { hasEnchant = false, enchantID = 0, ... }
--        [2] = { hasEnchant = true,  enchantID = 29, timeLeft = 3542889,
--                charges = 0, enchantIconID = 136086, enchantType = 3 }
--
-- This client allows MORE THAN ONE enchant per weapon, so the read returns a
-- list. The legacy global only ever describes the first entry, which was empty,
-- so it reported "no enchant" while the imbue sat in the second. That is why
-- the cooldown bar imbue icon stayed grey with Rockbiter clearly active.
--
-- Blizzard's own buff frame uses the list form
-- (Blizzard_BuffFrame/BuffFrame.lua:749-756, iterating Enum.WeaponSlot and
-- testing enchant.hasEnchant), so that is the supported read.
--
-- Slot ids come from Enum.WeaponSlot (MainHand = 0, OffHand = 1, Ranged = 2),
-- NOT the old INVSLOT numbers 16/17.
--
-- Exposed as SPCompat.GetWeaponEnchantInfo rather than overwriting the global:
-- taking over a Blizzard global is what caused the party-frame taint error
-- earlier today, and there is no reason to repeat it.
-- ---------------------------------------------------------------------------
do
	local function firstEnchant(slotID)
		if slotID == nil then return false end
		local ok, list = pcall(C_Item.GetWeaponEnchantInfo, slotID)
		if not ok or type(list) ~= "table" then return false end
		for _, e in pairs(list) do
			if type(e) == "table" and e.hasEnchant then
				-- timeLeft is milliseconds, same unit the classic tuple used
				return true, e.timeLeft, e.charges, e.enchantID
			end
		end
		return false
	end

	local useList = (WOW_PROJECT_ID == WOW_PROJECT_MAINLINE)
		and C_Item and C_Item.GetWeaponEnchantInfo and Enum and Enum.WeaponSlot

	function SPCompat.GetWeaponEnchantInfo()
		if useList then
			local hm, me, mc, mid = firstEnchant(Enum.WeaponSlot.MainHand)
			local ho, oe, oc, oid = firstEnchant(Enum.WeaponSlot.OffHand)
			return hm, me, mc, mid, ho, oe, oc, oid
		end
		if _G.GetWeaponEnchantInfo then return _G.GetWeaponEnchantInfo() end
		return false
	end
end

if not BOOKTYPE_SPELL then BOOKTYPE_SPELL = "spell" end
if not GetSpellBookItemName and C_SpellBook and C_SpellBook.GetSpellBookItemName then
	function GetSpellBookItemName(index, bookType)
		local bank = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
		return C_SpellBook.GetSpellBookItemName(index, bank)
	end
end

-- IsSpellKnown / IsPlayerSpell / FindSpellBookSlotBySpellID only exist on the
-- Mainline line behind the loadDeprecationFallbacks CVar, so they can be nil.
-- The addon calls all three bare in core paths (learned-element checks, shield
-- detection, raid cooldown setup), where a nil would throw rather than return
-- false. These mirror Blizzard's own deprecated shims so behaviour matches the
-- client when the fallbacks are loaded.
do
	local function spellBank(isPet)
		local E = Enum and Enum.SpellBookSpellBank
		if not E then return isPet and 1 or 0 end
		return isPet and E.Pet or E.Player
	end

	if not IsPlayerSpell and C_SpellBook and C_SpellBook.IsSpellKnown then
		function IsPlayerSpell(spellID)
			return C_SpellBook.IsSpellKnown(spellID, spellBank(false))
		end
	end

	if not IsSpellKnown and C_SpellBook and C_SpellBook.IsSpellInSpellBook then
		function IsSpellKnown(spellID, isPet)
			return C_SpellBook.IsSpellInSpellBook(spellID, spellBank(isPet), false)
		end
	end

	if not IsSpellKnownOrOverridesKnown and C_SpellBook and C_SpellBook.IsSpellInSpellBook then
		function IsSpellKnownOrOverridesKnown(spellID, isPet)
			return C_SpellBook.IsSpellInSpellBook(spellID, spellBank(isPet), true)
		end
	end

	if not FindSpellBookSlotBySpellID and C_SpellBook and C_SpellBook.FindSpellBookSlotForSpell then
		function FindSpellBookSlotBySpellID(spell, includeHidden)
			return (C_SpellBook.FindSpellBookSlotForSpell(spell, includeHidden and true or false))
		end
	end
end

if not GetAddOnMetadata and C_AddOns and C_AddOns.GetAddOnMetadata then
	GetAddOnMetadata = C_AddOns.GetAddOnMetadata
end
if not IsAddOnLoaded and C_AddOns and C_AddOns.IsAddOnLoaded then
	IsAddOnLoaded = C_AddOns.IsAddOnLoaded
end

if not GetItemInfo and C_Item and C_Item.GetItemInfo then
	GetItemInfo = C_Item.GetItemInfo
end
if not GetItemCount and C_Item and C_Item.GetItemCount then
	GetItemCount = C_Item.GetItemCount
end

-- Constants the classic FrameXML defines as globals and modern clients do not
-- (retail 12.1: MAX_*_MACROS gone - the macro code compared numbers against nil)
--
-- These MUST be written only when genuinely absent. `X = X or 4` is not a
-- conditional: Lua emits the SETGLOBAL either way, so it re-stores the same
-- value and the addon becomes the global's last writer. On a client with the
-- secrets regime armed that is a live grenade, because whoever last wrote a
-- global owns its taint and every function that READS it runs tainted.
--
-- MAX_PARTY_MEMBERS is the proven case: Blizzard sets it at
-- Blizzard_UnitFrame/Shared/PartyFrame.lua:1 and reads it back at :55 inside
-- PartyFrameMixin:InitializePartyMemberFrames. Taking it over meant that
-- function ran tainted, so when it reached UnitHealthMax("partypet1") on a
-- solo character and got a secret back, comparing it was blocked. One stray
-- assignment, four party frames that never finished initialising.
local function defaultGlobal(name, value)
	if rawget(_G, name) == nil then _G[name] = value end
end

defaultGlobal("MAX_ACCOUNT_MACROS", 120)
defaultGlobal("MAX_CHARACTER_MACROS", 18)
defaultGlobal("MAX_PARTY_MEMBERS", 4)
defaultGlobal("MAX_RAID_MEMBERS", 40)
defaultGlobal("LE_PARTY_CATEGORY_HOME", 1)
defaultGlobal("LE_PARTY_CATEGORY_INSTANCE", 2)

-- ---------------------------------------------------------------------------
-- 1b. Midnight "secret value" guards (retail 12.x, and Forever if it inherits
-- the combat restrictions). Observed on retail 12.1.0 in combat:
--   * GetTotemInfo returns SECRET booleans/numbers ("attempt to perform
--     boolean test on a secret boolean value")
--   * GetSpellCooldown start/duration are SECRET numbers
--   * C_UnitAuras.GetBuffDataByIndex THROWS "Auras cannot be accessed when
--     secret while tainted"
-- Addon code branches on all three, so the wrappers below turn secret data
-- into "nothing there" and raise SPCompat.combatDataSecret so modules that
-- alert on state changes (ExpiringAlerts) can stand down instead of firing
-- bogus "faded" alerts on the first pull. Every wrapper is a no-op on clients
-- without issecretvalue (the classic family today).
-- ---------------------------------------------------------------------------
SPCompat = SPCompat or {}
SPCompat.BUILD = "2026-09-19a"   -- bump when the diag tooling changes so a paste shows whether /reload happened

-- ---------------------------------------------------------------------------
-- Does a spell exist for this player, on this client?
--
-- GetSpellInfo returning a name is NOT that answer, and it is wrong in both
-- directions on the Forever line:
--
--   * Resolves but is unobtainable. Earth Shield 974 has a SpellName row but
--     no trainer entry and no talent node, so nothing can ever learn it.
--   * Real but does not resolve. That build ships ~540 encrypted SpellName
--     rows; Elemental Mastery 16166 is a live Elemental capstone whose name
--     comes back nil. Treating that as "absent" silently drops the spell.
--
-- So: consult the two hand-checked lists first (derived from the client's own
-- SkillLineAbility/Trait tables, which Lua cannot read), then the name, then
-- the spellbook by ID. The spellbook step needs no name at all, which is the
-- point: it is the only check that survives an encrypted string.
--
-- On the Classic line every real spell resolves by name, both lists are empty
-- there, and the second step always answers, so this returns exactly what a
-- bare GetSpellInfo check returns today.
-- ---------------------------------------------------------------------------
local UNOBTAINABLE = {}   -- has a name, but nothing can learn it
local REAL_UNNAMED = {}   -- no readable name, but genuinely castable

if WOW_PROJECT_ID == WOW_PROJECT_MAINLINE then
	-- Earth Shield: 974 has no SkillLineAbility row at all; 408514 has one but
	-- AcquireMethod 3 with no TraitDefinition and no Talent row, i.e. granted by
	-- nothing. (Water Shield 408510 is also AcquireMethod 3 but DOES have a
	-- TraitDefinition row, which is why it is real and these are not.)
	UNOBTAINABLE[974] = true
	UNOBTAINABLE[32593] = true
	UNOBTAINABLE[32594] = true
	UNOBTAINABLE[408514] = true

	-- Elemental Mastery: NOT on this client. It was allow-listed here on the strength
	-- of Talent.db2 (record 573, "Elemental capstone"), but that table is the
	-- untouched vanilla leftover. The real talents live in the trait tables: tree
	-- 1082 holds all three specs in one 50-node tree (measured in game 2026-09-22); its Elemental branch ends in Lava Burst - the same
	-- list Wowhead's Forever calculator shows. Nothing grants 16166.
	UNOBTAINABLE[16166] = true

	-- Present in SkillLineAbility, name encrypted in SpellName.
	REAL_UNNAMED[25908] = true   -- Tranquil Air Totem, SkillLine 374 (not on the trainer list by level; verify at the trainer)
end

SPCompat.spellDenyList = UNOBTAINABLE
SPCompat.spellAllowList = REAL_UNNAMED

-- Cached because option `hidden` callbacks run on every settings redraw.
-- Wiped on SPELLS_CHANGED: the spellbook is empty while addons load, so any
-- answer worked out at load time would be answering before the data exists.
local spellExistsCache = {}

function SPCompat.SpellExists(id)
	if type(id) ~= "number" then return false end
	local hit = spellExistsCache[id]
	if hit ~= nil then return hit end

	local found
	if UNOBTAINABLE[id] then
		found = false
	elseif REAL_UNNAMED[id] then
		found = true
	elseif GetSpellInfo(id) then
		found = true
	else
		-- No readable name. Ask the spellbook by ID, which ignores strings.
		found = false
		if IsPlayerSpell and IsPlayerSpell(id) then found = true end
		if not found and IsSpellKnown and IsSpellKnown(id) then found = true end
	end

	spellExistsCache[id] = found
	return found
end

function SPCompat.WipeSpellExistsCache()
	spellExistsCache = {}
end

do
	local f = CreateFrame("Frame")
	f:RegisterEvent("SPELLS_CHANGED")
	f:RegisterEvent("PLAYER_ENTERING_WORLD")
	f:SetScript("OnEvent", SPCompat.WipeSpellExistsCache)
end

-- Kept as its own name because it gates a whole module, not one spell.
-- Derived from the deny list so there is a single source of truth.
SPCompat.earthShieldExists = not UNOBTAINABLE[408514]

-- ---------------------------------------------------------------------------
-- Can this client compile secure handler snippets at all?
--
-- On Forever beta 1.60.1.69913 it cannot. Blizzard's RestrictedExecution.lua:22
-- does `local loadstring_untainted = loadstring_untainted`, and on this client
-- that capture yields nil, so every snippet body dies at its line 79 with
-- "attempt to call a nil value" on first use. It surfaces as a Lua error on
-- every mouseover of a button carrying an _onenter / _onleave snippet.
--
-- WHY it is nil is NOT known, and an earlier explanation in this comment was
-- wrong. Measured 2026-09-18: that Blizzard file is BYTE-IDENTICAL to retail's
-- (md5 18034e9c6a08c7d435ce2fafbf5e5bae) and the addon's TOC differs only by
-- adding `camelot` to AllowLoadGameType. The same ShamanPower snippets compile
-- on retail and give working in-combat flyouts there. `loadstring_untainted`
-- reads nil from chat on BOTH clients, so it is withdrawn from _G after load
-- either way and that test cannot tell them apart. The difference is engine
-- side, below anything readable from Lua.
--
-- An addon cannot repair an upvalue captured inside Blizzard's chunk, so the
-- only option is the plain-script fallback. Probe rather than hardcode a client
-- check: the moment it starts working, the secure path returns with no patch.
--
-- SecureHandlerExecute runs the same compile path synchronously, so a pcall
-- around a trivial body is a safe, complete test.
-- ---------------------------------------------------------------------------
local snippetsWork, snippetProbeErr

-- Manual override, persisted per session only: "on" forces the secure snippet
-- path regardless of what the probe thinks, "off" forces the fallback, nil
-- probes. The probe has been wrong before, and this client's snippets compile
-- on retail from a byte-identical Blizzard file, so the probe answering "no"
-- is not proof. /spflyout secure flips it without a code change.
-- PROVEN 2026-09-18, both directions, on build 1.60.1.69913:
--   * Blizzard's RestrictedExecution.lua here is BYTE-IDENTICAL to retail's
--     (md5 18034e9c6a08c7d435ce2fafbf5e5bae, and the addon's TOC differs only
--     by adding `camelot` to AllowLoadGameType), and the same ShamanPower
--     snippets compile and give working in-combat flyouts on retail.
--   * Forcing the secure path on here still throws "attempt to call a nil
--     value" at RestrictedExecution.lua:79 on the first mouseover, in and out
--     of combat. Its line 22 captured `loadstring_untainted` as nil.
-- So the Lua is the same and the engine is not providing that function to this
-- client. An addon cannot repair an upvalue captured inside Blizzard's chunk,
-- which is why the fallback exists at all.
-- /spflyout secure forces it back on for re-testing after a client patch.
SPCompat.snippetOverride = nil   -- probe decides; "on"/"off" via /spflyout

function SPCompat.SecureSnippetsWork()
	if SPCompat.snippetOverride == "on" then return true end
	if SPCompat.snippetOverride == "off" then return false end
	if snippetsWork ~= nil then return snippetsWork end
	-- The probe writes an attribute on a protected frame, which combat blocks
	-- for its own reasons. Answer "no" for now but do NOT cache it, so a reload
	-- mid-fight cannot bake in a false negative for the rest of the session.
	if InCombatLockdown and InCombatLockdown() then return false end
	if type(SecureHandlerExecute) ~= "function" or type(CreateFrame) ~= "function" then
		snippetsWork, snippetProbeErr = false, "SecureHandlerExecute missing"
		return false
	end
	local okF, probe = pcall(CreateFrame, "Frame", nil, UIParent, "SecureHandlerBaseTemplate")
	if not okF or not probe then
		snippetsWork, snippetProbeErr = false, "could not create a probe frame"
		return false
	end
	-- must be EXPLICITLY protected or SecureHandlerExecute refuses regardless
	local okP, _, explicit = pcall(probe.IsProtected, probe)
	if not okP or not explicit then
		snippetsWork, snippetProbeErr = false, "probe frame is not explicitly protected"
		return false
	end
	-- SecureHandlerExecute does NOT run the body inline. It ends with
	--     LOCAL_API_Frame:SetAttribute("_apiframe", frame)
	--     LOCAL_API_Frame:SetAttribute("_execute", body)
	-- so the compile happens inside an OnAttributeChanged handler that C
	-- invokes. An error in a script handler is reported to the error handler
	-- and does NOT propagate back out through the C call, so pcall here returns
	-- TRUE even when the snippet failed to compile. Relying on it made this
	-- probe answer "snippets work" every time.
	--
	-- Detect it the only way that actually observes the failure: install a
	-- recording error handler for the duration of the call. The marker
	-- attribute is corroboration, not the verdict, because a handle method
	-- could be restricted for unrelated reasons.
	local failed, firstErr = false, nil
	local prev = geterrorhandler and geterrorhandler()
	if seterrorhandler then
		pcall(seterrorhandler, function(msg)
			failed = true
			firstErr = firstErr or tostring(msg)
		end)
	end

	pcall(probe.SetAttribute, probe, "spSnippetProbe", nil)
	local ok = pcall(SecureHandlerExecute, probe, "self:SetAttribute('spSnippetProbe', 1)")
	if seterrorhandler and prev then pcall(seterrorhandler, prev) end

	local okMark, marked = pcall(probe.GetAttribute, probe, "spSnippetProbe")
	SPCompat.snippetProbeMarked = okMark and marked or nil

	snippetsWork = (ok and not failed) and true or false
	snippetProbeErr = (not snippetsWork) and (firstErr or "probe call refused") or nil
	return snippetsWork
end

function SPCompat.SecureSnippetError() return snippetProbeErr end
SPCompat.combatDataSecret = false
SPCompat.secretHits = { totem = 0, cooldown = 0, aura = 0 }
SPCompat.rawGetTotemInfo = GetTotemInfo   -- unwrapped, for the in-combat probes
-- Guarded versions of natives Blizzard's own UI calls (GetTotemInfo, GetSpellCooldown)
-- are exposed HERE and aliased by our files; the globals are never replaced,
-- because secure Blizzard code calling into addon code becomes tainted and
-- then cannot read its own secret values (BuffFrame errors in combat).
SPCompat.GetTotemInfo = GetTotemInfo
SPCompat.GetSpellCooldown = GetSpellCooldown
if not issecretvalue then
	function issecretvalue() return false end
end

-- Probe helpers as globals so they survive /reload (the beta checklist and
-- /spdiag combat use them):
--   SPS(v)         true if v is a secret value (false wherever secrets don't exist)
--   SPV(v)         printable form; "<secret>" instead of touching a secret
--   SPC(name, ...) C_Secrets[name](...) or nil when the namespace/function is absent
--   SPR()          restriction state 0..5 (Combat Encounter M+ PvP Map Chat) as one string
--   SPK()          chat/addon-message lockdown flag (nil = API absent)
function SPS(v) return issecretvalue(v) and true or false end
function SPV(v) if SPS(v) then return "<secret>" end return tostring(v) end
function SPC(name, ...)
	local f = C_Secrets and C_Secrets[name]
	if not f then return nil end
	local ok, r = pcall(f, ...)
	if ok then return r end
	return "err"
end
function SPR()
	local R = C_RestrictedActions
	if not (R and R.IsAddOnRestrictionActive) then return "n/a" end
	local t = {}
	for i = 0, 5 do
		local ok, v = pcall(R.IsAddOnRestrictionActive, i)
		t[#t + 1] = i .. ":" .. (ok and SPV(v) or "err")
	end
	return table.concat(t, " ")
end
function SPK()
	local c = C_ChatInfo
	if c and c.InChatMessagingLockdown then
		local ok, v = pcall(c.InChatMessagingLockdown)
		return ok and v or nil
	end
	return nil
end

-- Install the guards only where the secret regime is real. Every current
-- Classic client exports issecretvalue/C_Secrets too (always false there), so
-- presence proves nothing - test BEHAVIOR: UnitHealth("player") is secret on
-- a restricted client even out of combat, and HasSecretRestrictions() is the
-- capability flag where it exists.
local function secretsRegimeActive()
	if type(rawget(_G, "issecretvalue")) ~= "function" then return false end
	local ok, v = pcall(issecretvalue, UnitHealth("player"))
	if ok and v == true then return true end
	if C_Secrets and C_Secrets.HasSecretRestrictions then
		local ok2, v2 = pcall(C_Secrets.HasSecretRestrictions)
		if ok2 and v2 == true then return true end
	end
	return false
end
SPCompat.secretsRegime = secretsRegimeActive()
if SPCompat.secretsRegime then
	local function hit(kind)
		SPCompat.combatDataSecret = true
		SPCompat.secretHits[kind] = SPCompat.secretHits[kind] + 1
	end

	if GetTotemInfo then
		local origGetTotemInfo = GetTotemInfo
		SPCompat.GetTotemInfo = function(slot)
			-- retail adds a 7th return: the spell ID of the totem in the slot
			local have, name, start, dur, icon, modRate, spellID = origGetTotemInfo(slot)
			if issecretvalue(have) or issecretvalue(name) or issecretvalue(start) or issecretvalue(dur) or issecretvalue(spellID) then
				hit("totem")
				return false, "", 0, 0, nil, 1, nil
			end
			return have, name, start, dur, icon, modRate, spellID
		end
	end

	-- Sanctioned pre-checks (no call, no throw) where the client offers them.
	local function aurasSecretNow()
		local f = C_Secrets and C_Secrets.ShouldAurasBeSecret
		if not f then return false end
		local ok, v = pcall(f)
		return ok and v == true
	end
	local function cooldownsSecretNow()
		local f = C_Secrets and C_Secrets.ShouldCooldownsBeSecret
		if not f then return false end
		local ok, v = pcall(f)
		return ok and v == true
	end
	local function anyRestrictionActive()
		local R = C_RestrictedActions
		if not (R and R.IsAddOnRestrictionActive) then return InCombatLockdown() end
		for i = 0, 3 do  -- Combat, Encounter, ChallengeMode, PvPMatch
			local ok, v = pcall(R.IsAddOnRestrictionActive, i)
			if ok and v == true then return true end
		end
		return false
	end
	SPCompat.AnyRestrictionActive = anyRestrictionActive

	-- Shadow cooldown model: cooldown numbers go secret in combat, but the
	-- player's own casts never do. A cast stamps the start time; the cooldown
	-- length is learned the first time it is seen readable (login, out of
	-- combat). While secret, a stamped spell whose never-secret isActive flag
	-- is still true reports (castTime, learnedDuration) - plain numbers, so the
	-- existing display code draws exactly what it draws out of combat.
	-- Keyed by spell NAME so ranks and table IDs meet.
	local shadowCD = {}
	SPCompat.shadowCooldowns = shadowCD
	local function cdKey(spell)
		if type(spell) == "number" then
			local name = GetSpellInfo and GetSpellInfo(spell)
			return name or spell
		end
		return spell
	end
	-- A cooldown's length is normally learned the first time it is seen readable,
	-- which left one hole: a spell whose first use of the session happens IN
	-- combat has no learned length, so the model answered "no cooldown" and the
	-- button looked ready for the whole 30 seconds (Stoneclaw Totem, measured).
	-- GetSpellBaseCooldown is spell data, not state: it returns plain numbers in
	-- and out of combat (measured: 30000, 1000 for 5730 both ways), so it fills
	-- that hole for any spell and rank with no table to maintain. It ignores
	-- talent reductions, so it is only a stand-in: a readable observation
	-- replaces it, and the never-secret isActive flag ends the display early if
	-- the real cooldown is shorter.
	local function baseDuration(id)
		if type(id) ~= "number" or not GetSpellBaseCooldown then return nil end
		local ok, ms = pcall(GetSpellBaseCooldown, id)
		if not ok or type(ms) ~= "number" or issecretvalue(ms) then return nil end
		if ms <= 2500 then return nil end   -- global cooldown only: not a real cooldown
		return ms / 1000
	end

	function SPCompat.ShadowCooldownCast(spellID)
		local key = cdKey(spellID)
		if not key then return end
		local e = shadowCD[key] or {}
		e.start, e.id = GetTime(), spellID
		if not e.duration then
			e.duration = baseDuration(spellID)
			e.seeded = e.duration and true or nil
		end
		shadowCD[key] = e
	end
	if GetSpellCooldown then
		local origGetSpellCooldown = GetSpellCooldown
		SPCompat.GetSpellCooldown = function(spell)
			local start, dur, enabled, modRate = origGetSpellCooldown(spell)
			if not (issecretvalue(start) or issecretvalue(dur)) then
				-- readable: learn/refresh the model from the truth
				local key = cdKey(spell)
				if key then
					if start and dur and start > 0 and dur > 2.5 then   -- > GCD: a real cooldown, not the global one
						local e = shadowCD[key] or {}
						e.start, e.duration = start, dur
						e.seeded = nil   -- the real, talent-adjusted length now
						shadowCD[key] = e
					elseif shadowCD[key] and (not dur or dur == 0) then
						shadowCD[key].start = nil   -- keep the learned length, forget the run
					end
				end
				return start, dur, enabled, modRate
			end
			hit("cooldown")
			local key = cdKey(spell)
			local e = key and shadowCD[key]
			if e and e.start and e.duration then
				local remaining = (e.start + e.duration) - GetTime()
				if remaining > 0 then
					-- confirm with the never-secret flag (a reset cooldown reads inactive)
					local active = true
					local id = e.id or (type(spell) == "number" and spell)
					if id and C_Spell and C_Spell.GetSpellCooldown then
						-- the kept table when there is one: a second fresh read per call is a second table
						local okc, cd = pcall(SPCompat.CooldownTable or C_Spell.GetSpellCooldown, id)
						if okc and type(cd) == "table" and cd.isActive == false then active = false end
					end
					if active then return e.start, e.duration, 1, 1 end
				end
			end
			return 0, 0, 1, 1
		end
	end

	-- Aura reads: the API throws rather than returning secrets. First failure
	-- in a combat marks auras blocked; further reads short-circuit until the
	-- player leaves combat, so the 40-slot scan loops stay cheap.
	local auraBlocked = false
	local function guardAura(name)
		local orig = _G[name]
		if not orig then return end
		_G[name] = function(unit, index, filter)
			if aurasSecretNow() or (auraBlocked and anyRestrictionActive()) then
				if not auraBlocked then hit("aura") end
				auraBlocked = true
				return nil
			end
			local ok, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12 = pcall(orig, unit, index, filter)
			if not ok then
				auraBlocked = true
				hit("aura")
				return nil
			end
			if issecretvalue(a1) then
				hit("aura")
				return nil
			end
			return a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12
		end
	end
	guardAura("UnitBuff")
	guardAura("UnitDebuff")
	guardAura("UnitAura")

	-- True while an empty aura read means "not allowed to look" rather than
	-- "nothing there". Anything that infers from a buff's absence (the totem
	-- range check) must switch to another source while this holds.
	function SPCompat.AurasUnreadable()
		return aurasSecretNow() or (auraBlocked and anyRestrictionActive())
	end

	local unrestrictedCallbacks = {}
	function SPCompat.OnUnrestricted(fn) unrestrictedCallbacks[#unrestrictedCallbacks + 1] = fn end
	local wasRestricted = false
	local function clearIfUnrestricted()
		if anyRestrictionActive() then
			wasRestricted = true
			return
		end
		auraBlocked = false
		SPCompat.combatDataSecret = false
		-- restrictions clear ~2 s after PLAYER_REGEN_ENABLED, and the state may
		-- still read active while the change event is dispatched; callers retry.
		-- State served from shadow models is re-read from the real API once.
		if wasRestricted then
			wasRestricted = false
			if SPCompat.Trace then SPCompat.Trace("UNRESTRICTED -> re-reading shadowed state (%d callbacks)", #unrestrictedCallbacks) end
			for _, fn in ipairs(unrestrictedCallbacks) do pcall(fn) end
		end
	end
	SPCompat.ClearIfUnrestricted = clearIfUnrestricted
	-- the totem/cooldown/aura guards observe restrictions too: remember it
	local origHit = hit
	hit = function(kind) wasRestricted = true; origHit(kind) end
	local regen = CreateFrame("Frame")
	regen:RegisterEvent("PLAYER_REGEN_ENABLED")
	pcall(regen.RegisterEvent, regen, "ADDON_RESTRICTION_STATE_CHANGED")   -- fires for the forced-cvar rehearsal too
	regen:SetScript("OnEvent", function(_, event, rtype, state)
		-- ADDON_RESTRICTION_STATE_CHANGED is dispatched BEFORE a restriction becomes
		-- active (state = Activating) and after one is deactivated (Inactive), and the
		-- client's docs say IsAddOnRestrictionActive always answers false during that
		-- dispatch. So the payload, not a query, decides: a restriction starting is
		-- remembered and nothing is cleared (asking would have said "all clear" at the
		-- very start of a fight and re-read the shadow models from an API about to go
		-- secret). Deactivation and PLAYER_REGEN_ENABLED go on to the check below.
		if event == "ADDON_RESTRICTION_STATE_CHANGED" and state ~= nil and state ~= 0 then
			wasRestricted = true
			return
		end
		clearIfUnrestricted()
		C_Timer.After(0.3, clearIfUnrestricted)
		C_Timer.After(2.5, clearIfUnrestricted)
	end)
end

if not GetUnitName then
	function GetUnitName(unit, showServer)
		local name, realm = UnitName(unit)
		if showServer and realm and realm ~= "" then return name .. "-" .. realm end
		return name
	end
end

-- ---------------------------------------------------------------------------
-- 2. Error collector (/sperrors) - installs immediately so later files'
--    load-time errors are caught too
-- ---------------------------------------------------------------------------
local pending = {}          -- errors seen before the SavedVariable is loaded
local errlog = nil          -- becomes ShamanPowerErrorLog.errors after login

local function record(store, msg, explicitStack)
	local key = tostring(msg):match("^[^\n]*") or "?"
	local e = store[key]
	if e then
		e.count = e.count + 1
		e.last = date and date("%H:%M:%S") or ""
	else
		-- bounded: the log lives in a SavedVariable and only /sperrors clear empties it
		if (store.__n or 0) >= 200 then return end
		store[key] = {
			count = 1,
			first = date and date("%Y-%m-%d %H:%M:%S") or "",
			stack = explicitStack or (debugstack and debugstack(3, 8, 0)) or "",
		}
		store.__n = (store.__n or 0) + 1
	end
end

-- If BugGrabber (BugSack's engine, and anything using it) is present it OWNS
-- the error handler and neutralizes other seterrorhandler calls, so we take
-- its official callback instead and skip our own recorder to avoid double
-- counting. On the beta there is no BugGrabber, so our seterrorhandler is the
-- collector. usingBugGrabber flips true once its callback is wired.
local usingBugGrabber = false
local orig = geterrorhandler and geterrorhandler()
if seterrorhandler then
	seterrorhandler(function(msg)
		if not usingBugGrabber then pcall(record, errlog or pending, msg) end
		if orig then return orig(msg) end
	end)
end

-- A blocked or forbidden action does NOT raise a Lua error, so the handler
-- above never sees it. All the player gets is "Interface action failed because
-- of an AddOn", with no clue which call it was. These two events carry the
-- addon and the exact function name, so record them like errors and let
-- /sperrors answer the question directly.
do
	local blocked = CreateFrame("Frame")
	blocked:RegisterEvent("ADDON_ACTION_BLOCKED")
	blocked:RegisterEvent("ADDON_ACTION_FORBIDDEN")
	blocked:SetScript("OnEvent", function(_, event, addon, func)
		addon = tostring(addon or "?")
		func = tostring(func or "?")
		-- other addons' blocks are noise in our log
		if not addon:find("ShamanPower", 1, true) then return end
		local label = string.format("[%s] %s tried to call %s()",
			event == "ADDON_ACTION_FORBIDDEN" and "FORBIDDEN" or "BLOCKED", addon, func)
		pcall(record, errlog or pending, label, (debugstack and debugstack(2, 12, 0)) or "")
	end)
end

local function hookBugGrabber()
	local bg = _G.BugGrabber
	if not bg or not bg.RegisterCallback then return false end
	local ok = pcall(function()
		bg.RegisterCallback({}, "BugGrabber_BugGrabbed", function(_, err)
			pcall(record, errlog or pending, err and (err.message or err.stack) or "?", err and err.stack)
		end)
	end)
	return ok
end

local ef = CreateFrame("Frame")
ef:RegisterEvent("ADDON_LOADED")
ef:RegisterEvent("PLAYER_LOGIN")
ef:SetScript("OnEvent", function(self, event, addon)
	if event == "ADDON_LOADED" and addon == "ShamanPower" then
		-- Persistence probe. ShamanPowerErrorLog is a RAW SavedVariable, nothing
		-- to do with AceDB, so this separates "the client is not loading saved
		-- variables" from "our database layer is resetting the profile".
		-- bootCount only goes up if the previous session's table came back.
		SPCompat.svBefore = (ShamanPowerErrorLog ~= nil) and "table" or "nil"
		SPCompat.svBootWas = ShamanPowerErrorLog and ShamanPowerErrorLog.bootCount or nil
		SPCompat.svLastSession = ShamanPowerErrorLog and ShamanPowerErrorLog.session or nil

		ShamanPowerErrorLog = ShamanPowerErrorLog or {}
		ShamanPowerErrorLog.errors = ShamanPowerErrorLog.errors or {}
		ShamanPowerErrorLog.bootCount = (ShamanPowerErrorLog.bootCount or 0) + 1
		SPCompat.svBootNow = ShamanPowerErrorLog.bootCount
		-- keep the PREVIOUS session stamp visible next boot
		ShamanPowerErrorLog.prevSession = ShamanPowerErrorLog.session
		ShamanPowerErrorLog.session = date and date("%Y-%m-%d %H:%M:%S") or ""
		errlog = ShamanPowerErrorLog.errors
		for k, v in pairs(pending) do
			if k ~= "__n" then errlog[k] = errlog[k] or v end
		end
		pending = {}
	elseif event == "PLAYER_LOGIN" then
		usingBugGrabber = hookBugGrabber()   -- prefer BugGrabber where it exists
	end
end)

-- ---------------------------------------------------------------------------
-- Copyable output window (chat can't be copied from) - shared by /spdiag and
-- /sperrors. Deliberately template-light so it works on an unknown client.
-- ---------------------------------------------------------------------------
local copyWin
local function ShowCopyWindow(title, text)
	if not copyWin then
		local f = CreateFrame("Frame", "ShamanPowerCopyWindow", UIParent)
		f:SetSize(680, 440)
		f:SetPoint("CENTER")
		f:SetFrameStrata("DIALOG")
		f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
		f:SetScript("OnDragStart", f.StartMoving)
		f:SetScript("OnDragStop", f.StopMovingOrSizing)
		local bg = f:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints(); bg:SetColorTexture(0.055, 0.07, 0.09, 0.97)
		for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT", 0, -1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", 1, 0 } }) do
			local t = f:CreateTexture(nil, "BORDER")
			t:SetPoint(e[1]); t:SetPoint(e[2])
			if e[3] == 0 then t:SetHeight(1) else t:SetWidth(1) end
			t:SetColorTexture(0.25, 0.66, 0.96, 0.9)
		end
		local l = f:CreateTexture(nil, "BORDER"); l:SetPoint("TOPLEFT"); l:SetPoint("BOTTOMLEFT"); l:SetWidth(1); l:SetColorTexture(0.25, 0.66, 0.96, 0.9)
		local r = f:CreateTexture(nil, "BORDER"); r:SetPoint("TOPRIGHT"); r:SetPoint("BOTTOMRIGHT"); r:SetWidth(1); r:SetColorTexture(0.25, 0.66, 0.96, 0.9)
		f.titleText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		f.titleText:SetPoint("TOPLEFT", 14, -12)
		local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		hint:SetPoint("TOPRIGHT", -14, -14)
		hint:SetText("All text is pre-selected - Ctrl+C to copy, Esc to close")
		local eb = CreateFrame("EditBox", nil, f)
		eb:SetMultiLine(true)
		eb:SetFontObject(ChatFontNormal)
		eb:SetAutoFocus(false)
		eb:SetScript("OnEscapePressed", function() f:Hide() end)
		-- read-only: any user edit restores the report and re-selects it
		eb:SetScript("OnTextChanged", function(box, user)
			if user then box:SetText(box.spText or ""); box:HighlightText() end
		end)
		local ok, sf = pcall(CreateFrame, "ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
		if ok and sf then
			sf:SetPoint("TOPLEFT", 14, -36); sf:SetPoint("BOTTOMRIGHT", -34, 14)
			sf:SetScrollChild(eb)
			f.scroll = sf
		else
			eb:SetPoint("TOPLEFT", 14, -36); eb:SetPoint("BOTTOMRIGHT", -14, 14)
		end
		f.eb = eb
		if UISpecialFrames then tinsert(UISpecialFrames, "ShamanPowerCopyWindow") end
		f:Hide()
		copyWin = f
	end
	copyWin.titleText:SetText(title or "ShamanPower")
	if copyWin.scroll then copyWin.eb:SetWidth(copyWin.scroll:GetWidth()) end
	copyWin.eb.spText = text
	copyWin.eb:SetText(text)
	copyWin:Show()
	copyWin.eb:SetFocus()
	copyWin.eb:HighlightText()
end

SLASH_SPERRORS1 = "/sperrors"
SlashCmdList["SPERRORS"] = function(msg)
	local store = errlog or pending
	if msg and strtrim and strtrim(msg) == "clear" then
		if errlog then wipe(errlog) else pending = {} end
		print("|cff3fa9f5ShamanPower|r: error log cleared")
		return
	end
	local n = 0
	for k, e in pairs(store) do
		if k ~= "__n" then
			n = n + 1
			print(string.format("|cffe5534b#%d x%d|r %s", n, e.count, k))
		end
	end
	if n == 0 then
		print("|cff3fa9f5ShamanPower|r: no Lua errors recorded this session. |cff4cc776Clean.|r")
	else
		print(string.format("|cff3fa9f5ShamanPower|r: %d distinct error(s). '/sperrors clear' resets.", n))
		local out = {}
		local i = 0
		for k, e in pairs(store) do
			if k ~= "__n" then
				i = i + 1
				out[#out + 1] = string.format("#%d  x%d  first %s\n%s\n%s", i, e.count, e.first or "?", k, e.stack or "")
			end
		end
		ShowCopyWindow(string.format("ShamanPower - %d Lua error(s)", n), table.concat(out, "\n----------------------------------------\n"))
	end
end

-- ---------------------------------------------------------------------------
-- 3. /spdiag - the day-one probe battery
-- ---------------------------------------------------------------------------
local function exists(v) return v ~= nil and "|cff4cc776yes|r" or "|cffe5534bNO|r" end

local SPELL_SWEEP = {
	{ 8512,  "Windfury Totem R1 (vanilla)" },
	{ 974,   "Earth Shield R1 (TBC)" },
	{ 32594, "Earth Shield R3 (TBC)" },
	{ 24398, "Water Shield (TBC id)" },
	{ 2825,  "Bloodlust" },
	{ 32182, "Heroism" },
	{ 36936, "Totemic Call" },
	{ 30706, "Totem of Wrath" },
	{ 3738,  "Wrath of Air" },
	{ 408510, "Water Shield (Forever talent id)" },
	{ 408490, "Lava Burst R1 (Forever)" },
	{ 408521, "Riptide R1 (Forever)" },
	{ 425336, "Rage of the Farseer (Forever)" },
	{ 437009, "Totemic Projection (Forever)" },
	{ 66842, "Call of the Elements" },
	{ 16190, "Mana Tide R1" },
	{ 8017,  "Rockbiter Weapon R1" },
	{ 51505, "Lava Burst (wrath id)" },
	{ 61295, "Riptide (wrath id)" },
}

-- ---------------------------------------------------------------------------
-- /spflyout: trace enter/leave/show/hide/click on the totem buttons, their
-- flyout buttons and the active-totem overlays. The secure enter/leave
-- templates only run _onleave for a MOTION leave that followed a MOTION
-- enter, so the `motion` flag and the `_entered` attribute are logged with
-- every event, plus what the client thinks is under the cursor.
--   /spflyout on     install the hooks (once per session)
--   /spflyout        open the trace + a snapshot of the current flyout state
--   /spflyout clear  empty the trace
-- ---------------------------------------------------------------------------
local flyoutTrace = {}
local function traceLine(fmt, ...)
	flyoutTrace[#flyoutTrace + 1] = string.format("%.2f  " .. fmt, GetTime(), ...)
	if #flyoutTrace > 500 then table.remove(flyoutTrace, 1) end
end
local function fociNames()
	local list = (GetMouseFoci and GetMouseFoci()) or { GetMouseFocus and GetMouseFocus() }
	local names = {}
	for _, f in ipairs(list) do
		names[#names + 1] = (f.GetName and f:GetName()) or (f.GetDebugName and f:GetDebugName()) or "?"
	end
	return #names > 0 and table.concat(names, ",") or "none"
end
local function frameLabel(f)
	return (f.GetName and f:GetName()) or (f.GetDebugName and f:GetDebugName()) or tostring(f)
end
local function traceHook(f)
	if f.spFlyoutTraced then return end
	f.spFlyoutTraced = true
	local label = frameLabel(f)
	local function entered(self) return tostring(self.GetAttribute and self:GetAttribute("_entered")) end
	f:HookScript("OnEnter", function(self, motion)
		traceLine("%s ENTER motion=%s _entered=%s foci=%s", label, tostring(motion), entered(self), fociNames())
	end)
	f:HookScript("OnLeave", function(self, motion)
		local parent = self:GetParent()
		-- what the secure parent-leave snippet would see: shown siblings (not self) under the cursor
		local blockers = {}
		if parent and parent ~= UIParent and parent.GetChildren then
			for _, c in ipairs({ parent:GetChildren() }) do
				pcall(function()
					if c ~= self and not (c.IsForbidden and c:IsForbidden()) and c:IsShown() and c:IsMouseOver() then
						blockers[#blockers + 1] = string.format("%s(%s lvl%d %dx%d %s)", frameLabel(c), c:GetObjectType(), c:GetFrameLevel(),
							math.floor(c:GetWidth() + 0.5), math.floor(c:GetHeight() + 0.5), c:GetAttribute("_onleave") and "protocol" or "decoration")
					end
				end)
			end
		end
		traceLine("%s LEAVE motion=%s _entered=%s overSelf=%s overParent=%s foci=%s blockers=%s", label, tostring(motion),
			entered(self), tostring(self:IsMouseOver()), tostring(parent and parent:IsMouseOver()), fociNames(),
			#blockers > 0 and table.concat(blockers, ",") or "none")
	end)
	f:HookScript("OnShow", function(self) traceLine("%s SHOW over=%s", label, tostring(self:IsMouseOver())) end)
	f:HookScript("OnHide", function(self) traceLine("%s HIDE over=%s", label, tostring(self:IsMouseOver())) end)
	if f.RegisterForClicks then
		f:HookScript("OnMouseDown", function(self, button) traceLine("%s MOUSEDOWN %s", label, tostring(button)) end)
		f:HookScript("OnMouseUp", function(self, button) traceLine("%s MOUSEUP %s", label, tostring(button)) end)
		f:HookScript("OnClick", function(self, button, down) traceLine("%s CLICK %s down=%s", label, tostring(button), tostring(down)) end)
	end
end
local function installFlyoutTrace()
	local SP = ShamanPower
	if not SP or not SP.totemButtons then return 0 end
	local n = 0
	for element = 1, 4 do
		local btn = SP.totemButtons[element]
		if btn then traceHook(btn); n = n + 1 end
		local flyout = SP.totemFlyouts and SP.totemFlyouts[element]
		for _, fb in ipairs((flyout and (flyout.allButtons or flyout.buttons)) or {}) do traceHook(fb); n = n + 1 end
		local ov = _G["ShamanPowerActiveOverlay" .. element]
		if ov then traceHook(ov); n = n + 1 end
	end
	return n
end
local function flyoutSnapshot(out)
	local SP = ShamanPower
	if not SP or not SP.totemButtons then out[#out + 1] = "ShamanPower not loaded"; return end
	out[#out + 1] = "cursor over: " .. fociNames() .. "   InCombatLockdown=" .. tostring(InCombatLockdown())
	for element = 1, 4 do
		local btn = SP.totemButtons[element]
		if btn then
			out[#out + 1] = string.format("[%d] %s shown=%s over=%s level=%d _entered=%s", element, frameLabel(btn),
				tostring(btn:IsShown()), tostring(btn:IsMouseOver()), btn:GetFrameLevel(), tostring(btn:GetAttribute("_entered")))
			local flyout = SP.totemFlyouts and SP.totemFlyouts[element]
			for _, fb in ipairs((flyout and (flyout.allButtons or flyout.buttons)) or {}) do
				if fb:IsShown() then
					out[#out + 1] = string.format("      flyout %s SHOWN over=%s level=%d _entered=%s isCurrentAssignment=%s flyoutHidden=%s",
						frameLabel(fb), tostring(fb:IsMouseOver()), fb:GetFrameLevel(), tostring(fb:GetAttribute("_entered")),
						tostring(fb:GetAttribute("isCurrentAssignment")), tostring(fb:GetAttribute("flyoutHidden")))
				end
			end
			local ov = _G["ShamanPowerActiveOverlay" .. element]
			if ov then
				out[#out + 1] = string.format("      overlay shown=%s over=%s level=%d mouse=%s", tostring(ov:IsShown()),
					tostring(ov:IsMouseOver()), ov:GetFrameLevel(), tostring(ov:IsMouseEnabled()))
			end
		end
	end
end
SLASH_SPFLYOUT1 = "/spflyout"
SlashCmdList["SPFLYOUT"] = function(msg)
	msg = strtrim(msg or ""):lower()
	if msg == "on" then
		local n = installFlyoutTrace()
		print(string.format("|cff4cc776ShamanPower:|r flyout trace hooked %d frames. Reproduce the problem, then /spflyout", n))
		return
	elseif msg == "clear" then
		flyoutTrace = {}
		print("|cff4cc776ShamanPower:|r flyout trace cleared")
		return
	elseif msg == "secure" or msg == "fallback" or msg == "auto" then
		SPCompat.snippetOverride = (msg == "secure" and "on") or (msg == "fallback" and "off") or nil
		local what = (msg == "secure" and "SECURE snippets (combat flyouts, retail path)")
			or (msg == "fallback" and "plain-script fallback (out of combat only)")
			or "auto (probe decides)"
		print("|cff4cc776ShamanPower:|r flyout mode -> " .. what)
		-- Rebuild immediately rather than asking for a reload: the override is
		-- session-only and SavedVariables are not persisting on this build, so
		-- a reload would throw the setting away before it could be tested.
		if InCombatLockdown() then
			print("|cffe5534bShamanPower:|r leave combat first, then run this again.")
		elseif ShamanPower and ShamanPower.RecreateTotemFlyouts then
			local ok, err = pcall(ShamanPower.RecreateTotemFlyouts, ShamanPower)
			print(ok and "|cff4cc776ShamanPower:|r flyouts rebuilt. Pull something and test."
				or ("|cffe5534bShamanPower:|r rebuild failed: " .. tostring(err)))
		end
		return
	end
	local out = { string.format("=== ShamanPower flyout trace (compat build %s, leave snippet %s) ===", SPCompat.BUILD or "?",
		(ShamanPower and ShamanPower.totemButtons and ShamanPower.totemButtons[1] and ShamanPower.totemFlyouts and ShamanPower.totemFlyouts[1]
			and ShamanPower.totemFlyouts[1].allButtons and ShamanPower.totemFlyouts[1].allButtons[1]
			and tostring(ShamanPower.totemFlyouts[1].allButtons[1]:GetAttribute("_onleave")):find('spFlyoutProtocol', 1, true)) and "MAINLINE" or "CLASSIC"),
		"--- snapshot now ---" }
	flyoutSnapshot(out)
	out[#out + 1] = "--- events (oldest first) ---"
	if #flyoutTrace == 0 then out[#out + 1] = "(empty - run /spflyout on first, then hover/click a flyout)" end
	for _, l in ipairs(flyoutTrace) do out[#out + 1] = l end
	ShowCopyWindow("ShamanPower flyout trace", table.concat(out, "\n"))
end

-- ---------------------------------------------------------------------------
-- /spdiag combat: the in-combat probe set in one command. Every value goes
-- through SPV so nothing secret is printed or saved. Run it while a mob is
-- alive (and again during a boss / in a group) - it tells us which reads are
-- secret on THIS client and whether the engine timer path accepts them.
-- ---------------------------------------------------------------------------
local function SPDiagCombat()
	local out = {}
	local function say(fmt, ...) out[#out + 1] = string.format(fmt, ...) end
	local function try(fn, ...)
		local ok, r = pcall(fn, ...)
		if ok then return r end
		return "err: " .. tostring(r)
	end
	say("=== ShamanPower in-combat probes  %s ===", date and date("%Y-%m-%d %H:%M:%S") or "")
	do
		local okc, forced = pcall(GetCVar, "addonCombatRestrictionsForced")
		say("InCombatLockdown %s   restrictions (0=Combat 1=Encounter 2=M+ 3=PvP 4=Map 5=Chat): %s   chatlock %s   addonCombatRestrictionsForced=%s",
			tostring(InCombatLockdown()), SPR(), tostring(SPK()), okc and tostring(forced) or "n/a")
	end
	say("HasSecretRestrictions %s   ShouldAurasBeSecret %s   ShouldCooldownsBeSecret %s   secretsRegime(load) %s",
		tostring(SPC("HasSecretRestrictions")), tostring(SPC("ShouldAurasBeSecret")), tostring(SPC("ShouldCooldownsBeSecret")), tostring(SPCompat.secretsRegime))

	say("--- own totem slots (raw GetTotemInfo; <secret> = value is secret) ---")
	local raw = SPCompat.rawGetTotemInfo or GetTotemInfo
	for s = 1, 4 do
		local ok, h, n, st, d, i, m, id = pcall(raw, s)
		say("slot %d: ok=%s have=%s name=%s start=%s dur=%s spellID=%s slotSecret=%s", s, tostring(ok), SPV(h), SPV(n), SPV(st), SPV(d), SPV(id), tostring(SPC("ShouldTotemSlotBeSecret", s)))
	end

	say("--- auras ---")
	if C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
		for _, nm in ipairs({ "Lightning Shield", "Water Shield", "Earth Shield" }) do
			local ok, a = pcall(C_UnitAuras.GetAuraDataBySpellName, "player", nm, "HELPFUL")
			local count, exp = "-", "-"
			if ok and type(a) == "table" then count, exp = try(function() return SPV(a.applications) end), try(function() return SPV(a.expirationTime) end) end
			say("by name %s: ok=%s found=%s count=%s exp=%s", nm, tostring(ok), tostring(ok and a ~= nil), count, exp)
		end
	else
		say("by name: C_UnitAuras.GetAuraDataBySpellName absent")
	end
	if C_UnitAuras and C_UnitAuras.GetBuffDataByIndex then
		for _, u in ipairs({ "player", "party1" }) do
			local ok, r = pcall(C_UnitAuras.GetBuffDataByIndex, u, 1)
			say("by index %s slot 1: ok=%s -> %s", u, tostring(ok), ok and type(r) or tostring(r))
		end
	end
	do
		local ok, name = pcall(UnitBuff, "player", 1)
		say("UnitBuff(player,1) via the compat layer: ok=%s name=%s", tostring(ok), SPV(name))
	end

	say("--- cooldowns (2484 Earthbind = GCD reference, 20608 Reincarnation, 8512 Windfury Totem) ---")
	if C_Spell and C_Spell.GetSpellCooldown then
		for _, id in ipairs({ 2484, 20608, 8512 }) do
			local ok, c = pcall(C_Spell.GetSpellCooldown, id)
			if ok and type(c) == "table" then
				say("%d: start=%s dur=%s isActive=%s isOnGCD=%s isEnabled=%s", id, SPV(c.startTime), SPV(c.duration), SPV(c.isActive), SPV(c.isOnGCD), SPV(c.isEnabled))
			else
				say("%d: ok=%s -> %s", id, tostring(ok), tostring(c))
			end
		end
	else
		local ok, st, d = pcall(GetSpellCooldown, 2484)
		say("2484 via GetSpellCooldown: ok=%s start=%s dur=%s", tostring(ok), SPV(st), SPV(d))
	end

	say("--- weapon imbue ---")
	do
		local ok, h, e, ch, id = pcall(GetWeaponEnchantInfo)
		say("GetWeaponEnchantInfo: ok=%s has=%s expMs=%s charges=%s enchantID=%s   C_PaperDollInfo.GetTemporaryEnchantmentInfo %s",
			tostring(ok), SPV(h), SPV(e), SPV(ch), SPV(id), tostring(C_PaperDollInfo and type(C_PaperDollInfo.GetTemporaryEnchantmentInfo)))
	end

	say("--- engine timer path with a live totem (needs a totem in slot 1) ---")
	do
		local gtd = rawget(_G, "GetTotemDuration")
		if gtd then
			local ok, d = pcall(gtd, 1)
			local swipe = "n/a"
			if ok and d then
				SPProbeCD = SPProbeCD or CreateFrame("Cooldown", "SPProbeCD", UIParent, "CooldownFrameTemplate")
				SPProbeCD:SetPoint("CENTER")
				SPProbeCD:SetSize(48, 48)
				SPProbeCD:Show()
				local ok2, err2 = pcall(function() SPProbeCD:SetCooldownFromDurationObject(d) end)
				swipe = ok2 and "48px swipe drawn at screen center (hide with /spdiag hideswipe)" or ("setter error: " .. tostring(err2))
			end
			say("GetTotemDuration(1): ok=%s type=%s   SetCooldownFromDurationObject: %s", tostring(ok), type(d), swipe)
		else
			say("GetTotemDuration absent")
		end
	end

	say("--- identity ---")
	say("target: guidSecret=%s name=%s idSecret=%s | party1: name=%s class=%s idSecret=%s",
		tostring(SPS(UnitGUID("target"))), SPV(UnitName("target")), tostring(SPC("ShouldUnitIdentityBeSecret", "target")),
		SPV(UnitName("party1")), SPV((UnitClass("party1"))), tostring(SPC("ShouldUnitIdentityBeSecret", "party1")))

	say("--- addon comm ---")
	if IsInGroup() and C_ChatInfo and C_ChatInfo.SendAddonMessage then
		pcall(C_ChatInfo.RegisterAddonMessagePrefix, "SHPWRDIAG")
		local ok, r = pcall(C_ChatInfo.SendAddonMessage, "SHPWRDIAG", "ping", IsInRaid() and "RAID" or "PARTY")
		say("SendAddonMessage(grouped): ok=%s result=%s   (0/true = sent, 11 = AddOnMessageLockdown)", tostring(ok), SPV(r))
	else
		say("SendAddonMessage: skipped (not in a group)")
	end
	say("secret-value guard hits this session: totem %d cooldown %d aura %d", SPCompat.secretHits.totem, SPCompat.secretHits.cooldown, SPCompat.secretHits.aura)

	ShamanPowerErrorLog = ShamanPowerErrorLog or {}
	ShamanPowerErrorLog.diagCombat = table.concat(out, "\n")
	ShowCopyWindow("ShamanPower in-combat probes", ShamanPowerErrorLog.diagCombat)
end

-- ---------------------------------------------------------------------------
-- /spdiag frames: can an addon read Blizzard's own buff/raid-frame icons to
-- infer auras in combat? Prints what IsShown / GetTexture / count / spellID
-- look like from tainted code on the player BuffFrame and the first party and
-- raid member frames. Run with /spdiag force on (own buffs up), and again in a
-- group for the party/raid frames.
-- ---------------------------------------------------------------------------
local function SPDiagFrames()
	local out = {}
	local function say(fmt, ...) out[#out + 1] = string.format(fmt, ...) end
	local function field(f, k)
		local ok, v = pcall(function() return f[k] end)
		if not ok then return "err" end
		return SPV(v)
	end
	local function method(f, m, ...)
		local fn = f and f[m]
		if not fn then return "-" end
		local ok, v = pcall(fn, f, ...)
		if not ok then return "err: " .. tostring(v) end
		return SPV(v)
	end
	local function scanButtons(label, list, iconKey, countKey)
		if type(list) ~= "table" then say("%s: no button table", label) return end
		local n = 0
		for i, b in pairs(list) do
			if type(b) == "table" and b.IsShown then
				n = n + 1
				if n <= 6 then
					local icon = b[iconKey] or b.Icon or b.icon
					local count = b[countKey] or b.Count or b.count
					say("  %s[%s]: IsShown=%s  icon.GetTexture=%s  count.GetText=%s  auraInstanceID=%s  spellID=%s  frameType=%s",
						label, tostring(i), method(b, "IsShown"), icon and method(icon, "GetTexture") or "-",
						count and method(count, "GetText") or "-", field(b, "auraInstanceID"), field(b, "spellID"), method(b, "GetObjectType"))
				end
			end
		end
		say("%s: %d button frames%s", label, n, n > 6 and " (first 6 shown)" or "")
	end
	say("=== ShamanPower frame-read probes  %s ===", date and date("%Y-%m-%d %H:%M:%S") or "")
	say("restrictions: %s   addonCombatRestrictionsForced=%s   ShouldAurasBeSecret=%s", SPR(),
		(function() local ok, v = pcall(GetCVar, "addonCombatRestrictionsForced") return ok and tostring(v) or "n/a" end)(), tostring(SPC("ShouldAurasBeSecret")))
	say("--- player BuffFrame ---")
	local bf = rawget(_G, "BuffFrame")
	if bf then
		say("BuffFrame type=%s  IsShown=%s  auraFrames=%s  AuraContainer=%s", method(bf, "GetObjectType"), method(bf, "IsShown"),
			type(bf.auraFrames), type(bf.AuraContainer))
		scanButtons("BuffFrame.auraFrames", bf.auraFrames, "Icon", "Count")
		if bf.AuraContainer then scanButtons("BuffFrame.AuraContainer children", { bf.AuraContainer:GetChildren() }, "Icon", "Count") end
	else
		say("BuffFrame global absent")
	end
	say("--- party / raid member frames (need a group) ---")
	for _, name in ipairs({ "CompactPartyFrameMember1", "CompactRaidFrame1", "PartyFrame" }) do
		local f = rawget(_G, name)
		if f then
			say("%s: type=%s IsShown=%s unit=%s buffFrames=%s auraContainer=%s", name, method(f, "GetObjectType"), method(f, "IsShown"),
				field(f, "unit"), type(f.buffFrames), type(f.AuraContainer or f.auraContainer))
			scanButtons(name .. ".buffFrames", f.buffFrames, "icon", "count")
			local ac = f.AuraContainer or f.auraContainer
			if ac and ac.GetChildren then scanButtons(name .. ".AuraContainer children", { ac:GetChildren() }, "Icon", "Count") end
		else
			say("%s: absent", name)
		end
	end
	say("--- engine AuraContainer made by us (what the sanctioned path exposes) ---")
	do
		local ok, ac = pcall(CreateFrame, "AuraContainer", "SPProbeAuraContainer", UIParent)
		if ok and ac then
			say("created: type=%s  methods: SetUnit=%s AddAuraGroup=%s GetChildren=%s", method(ac, "GetObjectType"),
				type(ac.SetUnit), type(ac.AddAuraGroup), type(ac.GetChildren))
			if ac.SetUnit then pcall(ac.SetUnit, ac, "player") end
			local kids = ac.GetChildren and { ac:GetChildren() } or {}
			say("children after SetUnit(player): %d (engine-managed buttons are expected to be invisible to Lua)", #kids)
			ac:Hide()
		else
			say("AuraContainer: %s", tostring(ac))
		end
	end
	ShamanPowerErrorLog = ShamanPowerErrorLog or {}
	ShamanPowerErrorLog.diagFrames = table.concat(out, "\n")
	ShowCopyWindow("ShamanPower frame-read probes", ShamanPowerErrorLog.diagFrames)
end

-- ---------------------------------------------------------------------------
-- /sptrace: log the non-secret event stream the Forever design would rely on
-- (own casts, PLAYER_TOTEM_UPDATE, restriction/encounter changes, SHPWR
-- comms). Secret fields print as <secret>.
--   /sptrace on | off | clear | (no arg = open the log)
-- ---------------------------------------------------------------------------
local eventTrace = {}
local eventTraceFrame
local eventTraceOn = false   -- nothing is formatted or kept until /sptrace on
local function traceEvent(fmt, ...)
	if not eventTraceOn then return end
	eventTrace[#eventTrace + 1] = string.format("%.3f  " .. fmt, GetTime(), ...)
	if #eventTrace > 500 then table.remove(eventTrace, 1) end
end
SPCompat.Trace = traceEvent   -- other files log into /sptrace through this
SLASH_SPTRACE1 = "/sptrace"
SlashCmdList["SPTRACE"] = function(msg)
	msg = strtrim(msg or ""):lower()
	if msg == "on" then
		if not eventTraceFrame then
			eventTraceFrame = CreateFrame("Frame")
			eventTraceFrame:SetScript("OnEvent", function(_, e, a, b, c, d)
				if e == "UNIT_SPELLCAST_SUCCEEDED" then
					if a == "player" then traceEvent("%s unit=%s spellID=%s name=%s", e, SPV(a), SPV(c), SPV((GetSpellInfo and not SPS(c)) and GetSpellInfo(c) or "?")) end
				elseif e == "UNIT_SPELLCAST_SENT" then
					if a == "player" then traceEvent("%s unit=%s target=%s spellID=%s", e, SPV(a), SPV(b), SPV(d)) end
				elseif e == "CHAT_MSG_ADDON" then
					if not SPS(a) and (a == "SHPWR" or a == "SHPWRDIAG") then
						traceEvent("%s prefix=%s msg=%s chan=%s sender=%s", e, SPV(a), SPV(b), SPV(c), SPV(d))
					end
				else
					traceEvent("%s %s %s %s", e, SPV(a), SPV(b), SPV(c))
				end
			end)
		end
		for _, e in ipairs({ "PLAYER_TOTEM_UPDATE", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_SENT", "ADDON_RESTRICTION_STATE_CHANGED",
			"ENCOUNTER_START", "ENCOUNTER_END", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "CHAT_MSG_ADDON" }) do
			pcall(eventTraceFrame.RegisterEvent, eventTraceFrame, e)
		end
		eventTraceOn = true
		print("|cff4cc776ShamanPower:|r event trace on (own casts, totem updates, restriction/encounter changes, SHPWR comms). /sptrace to view, /sptrace off to stop")
	elseif msg == "off" then
		if eventTraceFrame then eventTraceFrame:UnregisterAllEvents() end
		eventTraceOn = false
		print("|cff4cc776ShamanPower:|r event trace off")
	elseif msg == "clear" then
		eventTrace = {}
		print("|cff4cc776ShamanPower:|r event trace cleared")
	else
		local text = #eventTrace > 0 and table.concat(eventTrace, "\n") or "(empty - /sptrace on first, then drop totems / pull a mob)"
		ShowCopyWindow("ShamanPower event trace", "=== ShamanPower event trace (oldest first) ===\n" .. text)
	end
end

SLASH_SPDIAG1 = "/spdiag"
SlashCmdList["SPDIAG"] = function(msg)
	msg = strtrim(msg or ""):lower()
	if msg == "combat" then return SPDiagCombat() end
	if msg == "frames" then return SPDiagFrames() end
	if msg == "sets" then
		local lines = (ShamanPower and ShamanPower.TotemSetsDiag and ShamanPower:TotemSetsDiag())
			or { "totem sets module not loaded on this client (it ships in the Mainline TOC only)" }
		return ShowCopyWindow("ShamanPower totem sets probe", table.concat(lines, "\n"))
	end
	if msg == "ready" then
		local lines = (ShamanPower and ShamanPower.ReadyRemindersDiag and ShamanPower:ReadyRemindersDiag())
			or { "Ready Reminders module not loaded" }
		return ShowCopyWindow("ShamanPower ready reminders probe", table.concat(lines, "\n"))
	end
	if msg == "auratest" or msg == "auratest off" then
		-- Which slot filter shape matches a SECRET aura? Four engine containers at
		-- screen center, each with a different filter, each showing an icon+count
		-- when it matches. Run out of restriction (all should show something), then
		-- under the restriction: the ones that still show name the working shape.
		if msg == "auratest off" then
			for i = 1, 4 do local c = _G["SPAuraTest" .. i] if c then c:Hide() end end
			return
		end
		if C_AddOns and C_AddOns.LoadAddOn then pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer") end
		local ids = ShamanPower and ShamanPower.ShieldAuraSpellIDs or { 324, 24398, 52127, 192106 }
		local idsMap = {}
		for _, id in ipairs(ids) do idsMap[id] = true end
		local modes = {
			{ label = "ids list", filter = "HELPFUL|PLAYER", cf = { includeSpellIDs = ids } },
			{ label = "ids map",  filter = "HELPFUL|PLAYER", cf = { includeSpellIDs = idsMap } },
			{ label = "no ids",   filter = "HELPFUL|PLAYER" },
			{ label = "HELPFUL",  filter = "HELPFUL" },
		}
		local out = {}
		for i, m in ipairs(modes) do
			local name = "SPAuraTest" .. i
			local c = _G[name]
			if not c then
				local ok, cc = pcall(CreateFrame, "AuraContainer", name, UIParent, "CustomAuraContainerTemplate")
				if not ok then out[#out + 1] = name .. " create failed: " .. tostring(cc) break end
				c = cc
				c:SetSize(48, 48)
				c:SetPoint("CENTER", UIParent, "CENTER", (i - 2.5) * 64, 140)
				local bg = c:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(c); bg:SetColorTexture(0, 0, 0, 0.5)
				local lbl = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); lbl:SetPoint("TOP", c, "BOTTOM", 0, -2); lbl:SetText(m.label)
				local opts = {
					initializeFrame = function(b)
						b:ClearAllPoints(); b:SetAllPoints(c)
						local icon = b:CreateTexture(nil, "ARTWORK"); icon:SetAllPoints(b); icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
						pcall(b.SetIcon, b, icon)
						local carrier = CreateFrame("Frame", nil, b); carrier:SetAllPoints(b)
						local count = carrier:CreateFontString(nil, "OVERLAY", "NumberFontNormal"); count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
						pcall(b.SetApplicationCount, b, count, {})
					end,
				}
				if m.cf then opts.candidateFilters = m.cf end
				local okA, err = pcall(c.AddAuraSlot, c, "t", m.filter, opts)
				out[#out + 1] = string.format("%s (%s): AddAuraSlot=%s%s", name, m.label, tostring(okA), okA and "" or (" " .. tostring(err)))
				pcall(c.SetUnit, c, "player")
				pcall(c.UpdateAllAuras, c)
			end
			c:Show()
		end
		print("|cff4cc776ShamanPower:|r " .. table.concat(out, " | "))
		print("|cff4cc776ShamanPower:|r four aura test squares above screen center (labels under them). /spdiag auratest off hides them.")
		return
	end
	if msg == "sbtest" then
		-- Does a StatusBar CUT its texture at the fill line or SQUEEZE it? Two 64px
		-- bars at screen center wearing the Bloodlust icon at 50%: cut = half an
		-- icon, squeeze = a whole icon flattened into half the bar.
		local tex = "Interface\\Icons\\Spell_Nature_BloodLust"
		for i, orient in ipairs({ "VERTICAL", "HORIZONTAL" }) do
			local name = "SPProbeSB" .. i
			local sb = _G[name] or CreateFrame("StatusBar", name, UIParent)
			sb:SetSize(64, 64)
			sb:SetPoint("CENTER", UIParent, "CENTER", (i - 1) * 90 - 45, 0)
			sb:SetStatusBarTexture(tex)
			sb:SetOrientation(orient)
			sb:SetReverseFill(orient == "VERTICAL")
			sb:SetMinMaxValues(0, 1)
			sb:SetValue(0.5)
			local bg = sb.bg or sb:CreateTexture(nil, "BACKGROUND")
			bg:SetAllPoints(sb); bg:SetColorTexture(0, 0, 0, 0.6); sb.bg = bg
			sb:Show()
		end
		print("|cff4cc776ShamanPower:|r two StatusBars at screen center (vertical from top, horizontal) at 50%. Screenshot them; /spdiag sbtest off hides them.")
		return
	end
	if msg == "sbtest off" then
		for i = 1, 2 do local sb = _G["SPProbeSB" .. i] if sb then sb:Hide() end end
		return
	end
	if msg == "cdbar" then
		local out = {}
		local function say(fmt, ...) out[#out + 1] = string.format(fmt, ...) end
		local SP = ShamanPower
		say("=== ShamanPower cooldown bar under restriction  %s ===", date and date("%H:%M:%S") or "")
		say("restrictions %s   regime=%s   AnyRestrictionActive=%s   GetSpellCooldownDuration=%s   SetCooldownFromDurationObject=%s",
			SPR(), tostring(SPCompat.secretsRegime), tostring(SPCompat.AnyRestrictionActive and SPCompat.AnyRestrictionActive()),
			tostring(C_Spell and type(C_Spell.GetSpellCooldownDuration)), tostring(type(CreateFrame("Cooldown").SetCooldownFromDurationObject)))
		say("cdbarSweepStyle=%s  showSweep opt=%s  showBars opt=%s", tostring(SP.opt.cdbarSweepStyle), tostring(SP.opt.cdbarShowSweep), tostring(SP.opt.cdbarShowProgressBars))
		for key, e in pairs(SPCompat.shadowCooldowns or {}) do
			say("shadow cooldown [%s]: start=%s duration=%s remaining=%s", tostring(key), tostring(e.start), tostring(e.duration),
				(e.start and e.duration) and string.format("%.1f", (e.start + e.duration) - GetTime()) or "-")
		end
		for i, btn in ipairs(SP.cooldownButtons or {}) do
			if btn.spellType == "cooldown" then
				local ok, cd = pcall(C_Spell.GetSpellCooldown, btn.spellID)
				local okd, dur = pcall(C_Spell.GetSpellCooldownDuration, btn.spellID)
				local w = btn.cooldown
				local wStart, wDur = "-", "-"
				if w and w.GetCooldownTimes then local okt, s, d = pcall(w.GetCooldownTimes, w) if okt then wStart, wDur = SPV(s), SPV(d) end end
				say("[%d] %s (%s): shown=%s  isActive=%s isOnGCD=%s isEnabled=%s  durationObj=%s  _engineCDSpell=%s  widget: shown=%s times=%s/%s hideNumbers=%s",
					i, tostring(btn.spellName or (GetSpellInfo and GetSpellInfo(btn.spellID))), tostring(btn.spellID), tostring(btn:IsShown()),
					ok and type(cd) == "table" and SPV(cd.isActive) or ("err " .. tostring(cd)), ok and type(cd) == "table" and SPV(cd.isOnGCD) or "-",
					ok and type(cd) == "table" and SPV(cd.isEnabled) or "-", okd and type(dur) or ("err " .. tostring(dur)), tostring(btn._engineCDSpell),
					tostring(w and w:IsShown()), wStart, wDur, tostring(w and w.GetHideCountdownNumbers and w:GetHideCountdownNumbers()))
			end
		end
		local sb = SP.shieldButton
		if sb then
			local c = sb.chargeContainer
			local s = SP.shadowShield
			say("shield button: container=%s shown=%s unit=%s   cache: has=%s charges=%s engineCount=%s   model: %s", tostring(c ~= nil),
				tostring(c and c:IsShown()), tostring(c and c.GetUnit and c:GetUnit()), tostring(SP.shieldCache and SP.shieldCache.hasShield),
				tostring(SP.shieldCache and SP.shieldCache.shieldCharges), tostring(SP.shieldCache and SP.shieldCache.engineCount),
				s and string.format("%s charges=%s remaining=%.0f", tostring(s.name), tostring(s.charges), (s.start + s.duration) - GetTime()) or "-")
			if c then
				local kids = { c:GetChildren() }
				say("  container children=%d (sizes/positions of engine containers are secret and not printed)", #kids)
				for i, k in ipairs(kids) do
					local okS, shown = pcall(k.IsShown, k)
					local okT, typ = pcall(k.GetObjectType, k)
					local okF, forb = pcall(k.IsForbidden, k)
					say("  child %d: type=%s shown=%s forbidden=%s regions=%s", i, okT and tostring(typ) or "?", okS and SPV(shown) or ("err " .. tostring(shown)),
						okF and tostring(forb) or "?", (function() local okR, n = pcall(function() return select("#", k:GetRegions()) end) return okR and tostring(n) or "?" end)())
				end
			end
		end
		do
			local f = SP.shieldChargeFrames or {}
			local pf, ef = f.player, f.earth
			local tok = SP.EarthShieldTargetToken and SP:EarthShieldTargetToken() or "n/a"
			if C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
				local parts = {}
				for _, nm in ipairs({ "Earth Shield", "Water Shield", "Lightning Shield" }) do
					local ok, a = pcall(C_UnitAuras.GetAuraDataBySpellName, "player", nm, "HELPFUL")
					parts[#parts + 1] = string.format("%s=%s", nm, (ok and type(a) == "table") and (SPV(a.spellId) .. " x" .. SPV(a.applications) .. " src=" .. SPV(a.sourceUnit)) or "none")
				end
				say("own shield auras by name (readable only): %s", table.concat(parts, "  "))
			end
			say("earth shield tracking: target=%s guid=%s charges=%s token=%s  esSpellName=%s", tostring(SP.esTrackedTarget), tostring(SP.esTrackedTargetGUID),
				tostring(SP.esTrackedCharges), tostring(tok), tostring(SP.GetESSpellName and SP:GetESSpellName()))
			say("charge displays: player frame shown=%s engine=%s engineShown=%s unit=%s | earth frame shown=%s engine=%s engineShown=%s unit=%s",
				tostring(pf and pf:IsShown()), tostring(pf and pf.engine ~= nil), tostring(pf and pf.engine and pf.engine:IsShown()), tostring(pf and pf.engineUnit),
				tostring(ef and ef:IsShown()), tostring(ef and ef.engine ~= nil), tostring(ef and ef.engine and ef.engine:IsShown()), tostring(ef and ef.engineUnit))
		end
		ShowCopyWindow("ShamanPower cooldown bar probe", table.concat(out, "\n"))
		return
	end
	if msg == "popout" then
		-- Pop-out frame geometry vs the saved position record (drift diagnosis)
		local out = {}
		local function say(fmt, ...) out[#out + 1] = string.format(fmt, ...) end
		local SP = ShamanPower
		local ok, pw, ph = pcall(GetPhysicalScreenSize)
		say("=== ShamanPower pop-out geometry  %s ===", date and date("%H:%M:%S") or "")
		say("UIParent %.0fx%.0f  effScale %.4f   physical %sx%s   poppedOutDefaultScale=%s",
			UIParent:GetWidth(), UIParent:GetHeight(), UIParent:GetEffectiveScale(), tostring(ok and pw), tostring(ok and ph),
			tostring(SP and SP.opt and SP.opt.poppedOutDefaultScale))
		local frames = SP and SP.poppedOutFrames or {}
		local any = false
		for key, f in pairs(frames) do
			any = true
			local cx, cy = f:GetCenter()
			local s = f:GetScale()
			local pt, rel, rp, x, y = f:GetPoint()
			say("[%s] shown=%s scale=%.3f eff=%.4f size=%.0fx%.0f clamped=%s", key, tostring(f:IsShown()), s, f:GetEffectiveScale(),
				f:GetWidth(), f:GetHeight(), tostring(f:IsClampedToScreen()))
			say("    center raw=(%.1f,%.1f) in UIParent units=(%.1f,%.1f)   point=%s rel=%s %s x=%.1f y=%.1f",
				cx or 0, cy or 0, (cx or 0) * s, (cy or 0) * s, tostring(pt), rel and (rel.GetName and rel:GetName() or "?") or "nil", tostring(rp), x or 0, y or 0)
			local rec = SP.opt and SP.opt.poppedOutPositions and SP.opt.poppedOutPositions[key]
			if rec and rec.anchor then
				say("    saved record: anchor=%s x=%.1f y=%.1f", rec.anchor, rec.x or 0, rec.y or 0)
			elseif rec then
				say("    saved LEGACY: point=%s relPoint=%s x=%.1f y=%.1f", tostring(rec.point), tostring(rec.relPoint), rec.x or 0, rec.y or 0)
			else
				say("    saved: none")
			end
			local st = SP.opt and SP.opt.poppedOutSettings and SP.opt.poppedOutSettings[key]
			say("    settings: scale=%s opacity=%s hideFrame=%s", tostring(st and st.scale), tostring(st and st.opacity), tostring(st and st.hideFrame))
		end
		if not any then say("(no pop-out frames)") end
		ShowCopyWindow("ShamanPower pop-out geometry", table.concat(out, "\n"))
		return
	end
	if msg == "hideswipe" then if SPProbeCD then SPProbeCD:Hide() end return end
	if msg == "force" or msg == "force 1" or msg == "force on" or msg == "force 0" or msg == "force off" then
		-- The forced-restriction cvar must be set from the chat line, not from addon
		-- code: a tainted cvar write taints every Blizzard frame that later reads
		-- the restriction state (BuffFrame errors on secret counts for the rest of
		-- the session). So print the untainted command instead of calling SetCVar.
		local on = not (msg == "force 0" or msg == "force off")
		local okv, v = pcall(GetCVar, "addonCombatRestrictionsForced")
		print(string.format("|cff4cc776ShamanPower:|r addonCombatRestrictionsForced is %s. Type this yourself (untainted):  |cffffd100/console addonCombatRestrictionsForced %s|r   then /spdiag combat%s",
			okv and tostring(v) or "?", on and "1" or "0", on and "" or "   (a /reload afterwards clears any taint left from earlier runs)"))
		if not on and SPCompat.ClearIfUnrestricted then C_Timer.After(0, SPCompat.ClearIfUnrestricted) end
		return
	end
	local out = {}
	local function say(fmt, ...)
		local line = select("#", ...) > 0 and string.format(fmt, ...) or fmt
		out[#out + 1] = line:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
		print("|cff3fa9f5SPDiag|r " .. line)
	end

	local v, build, bdate, iface = GetBuildInfo()
	say("=== ShamanPower beta diagnostics (compat build %s) ===", SPCompat.BUILD or "?")
	say("version %s build %s (%s)  interface |cffffd100%s|r", tostring(v), tostring(build), tostring(bdate), tostring(iface))
	local projects = {}
	for k, val in pairs(_G) do
		if type(k) == "string" and k:find("^WOW_PROJECT") then projects[#projects + 1] = k .. "=" .. tostring(val) end
	end
	table.sort(projects)
	say("projects: %s", table.concat(projects, "  "))
	say("player %s  realm '%s'  locale %s", tostring(UnitName("player")), tostring(GetNormalizedRealmName and GetNormalizedRealmName() or "?"), tostring(GetLocale()))

	say("--- API surface (old globals / modern namespaces) ---")
	say("GetSpellInfo %s  UnitBuff %s  GetSpellCooldown %s  GetSpellBookItemName %s", exists(rawget(_G, "GetSpellInfo")), exists(rawget(_G, "UnitBuff")), exists(rawget(_G, "GetSpellCooldown")), exists(rawget(_G, "GetSpellBookItemName")))
	say("C_Spell %s  C_UnitAuras %s  C_SpellBook %s  C_AddOns %s  C_Item %s  C_NamePlate %s", exists(C_Spell), exists(C_UnitAuras), exists(C_SpellBook), exists(C_AddOns), exists(C_Item), exists(C_NamePlate))
	say("GetTotemInfo %s  GetWeaponEnchantInfo %s  GetNumTalentTabs %s  CastSequence-macros: CreateMacro %s", exists(rawget(_G, "GetTotemInfo")), exists(rawget(_G, "GetWeaponEnchantInfo")), exists(rawget(_G, "GetNumTalentTabs")), exists(rawget(_G, "CreateMacro")))
	say("InterfaceOptions_AddCategory %s  Settings.RegisterAddOnCategory %s  FauxScrollFrame_Update %s", exists(rawget(_G, "InterfaceOptions_AddCategory")), exists(Settings and Settings.RegisterAddOnCategory), exists(rawget(_G, "FauxScrollFrame_Update")))
	local okC, cv = pcall(GetCVar, "ActionButtonUseKeyDown")
	say("ActionButtonUseKeyDown cvar = %s (secure buttons register AnyUp+AnyDown and let the template pick)", okC and tostring(cv) or "absent")

	say("--- day-one unknowns (these decide whether today's fixes were load-bearing) ---")
	local okD, dv = pcall(GetCVarBool, "loadDeprecationFallbacks")
	say("loadDeprecationFallbacks = %s  -> if false, the spellbook globals below are OUR shims, not Blizzard's",
		okD and tostring(dv) or "absent")
	say("IsSpellKnown %s  IsPlayerSpell %s  IsSpellKnownOrOverridesKnown %s  FindSpellBookSlotBySpellID %s",
		exists(rawget(_G, "IsSpellKnown")), exists(rawget(_G, "IsPlayerSpell")),
		exists(rawget(_G, "IsSpellKnownOrOverridesKnown")), exists(rawget(_G, "FindSpellBookSlotBySpellID")))
	say("C_SpellBook.IsSpellKnown %s  .IsSpellInSpellBook %s  .FindSpellBookSlotForSpell %s",
		exists(C_SpellBook and C_SpellBook.IsSpellKnown), exists(C_SpellBook and C_SpellBook.IsSpellInSpellBook),
		exists(C_SpellBook and C_SpellBook.FindSpellBookSlotForSpell))

	-- SpellExists vs a bare name lookup. Any row where they disagree is a spell
	-- the old code got wrong: "name nil / exists yes" was being dropped,
	-- "name ok / exists no" was being offered but is unobtainable.
	say("SpellExists vs GetSpellInfo (disagreement is the whole point of the helper):")
	for _, e in ipairs({
		{ 974,    "Earth Shield r1" },      { 408514, "Earth Shield fvr" },
		{ 408510, "Water Shield fvr" },     { 24398,  "Water Shield tbc" },
		{ 16166,  "Elemental Mastery" },    { 25908,  "Tranquil Air" },
		{ 425336, "Rage of Farseer" },      { 437009, "Totemic Projection" },
		{ 30706,  "Totem of Wrath" },       { 16190,  "Mana Tide" },
	}) do
		local nm = GetSpellInfo(e[1])
		local ex = SPCompat.SpellExists(e[1])
		say("  %-20s %-7d name=%-18s exists=%s%s", e[2], e[1], tostring(nm), tostring(ex),
			((nm ~= nil) ~= (ex == true)) and "   |cffffd100<- differs|r" or "")
	end

	say("earthShieldExists = %s   ESTrackerUnavailable = %s   ESTrackerLoaded = %s",
		tostring(SPCompat.earthShieldExists), tostring(ShamanPower and ShamanPower.ESTrackerUnavailable),
		tostring(ShamanPower and ShamanPower.ESTrackerLoaded))
	local tds = ShamanPower and ShamanPower.TotemDestroySupported and ShamanPower:TotemDestroySupported()
	say("TotemDestroySupported = %s  DestroyTotem %s  (this feature has never run in game - verify it)",
		tostring(tds), exists(rawget(_G, "DestroyTotem")))

	-- Saved-variable persistence. bootCount rising across reloads means saved
	-- variables ARE coming back and any "my settings reset" is our problem;
	-- stuck at 1 means the client is not loading them and no addon can help.
	say("--- saved variables ---")
	say("raw SV at ADDON_LOADED = %s   bootCount %s -> %s   last session %s",
		tostring(SPCompat.svBefore), tostring(SPCompat.svBootWas), tostring(SPCompat.svBootNow),
		tostring(SPCompat.svLastSession))
	local dbOK = ShamanPower and ShamanPower.db and ShamanPower.db.profile
	say("AceDB profile '%s'   setupDone %s   global.lastSeenVersion %s",
		tostring(ShamanPower and ShamanPower.db and ShamanPower.db:GetCurrentProfile()),
		tostring(dbOK and ShamanPower.db.profile.setupDone),
		tostring(ShamanPower and ShamanPower.db and ShamanPower.db.global and ShamanPower.db.global.lastSeenVersion))
	if SPCompat.svBootNow == 1 and SPCompat.svBefore == "nil" then
		say("  |cffe5534bbootCount is 1 and the table was absent: saved variables did NOT load.|r")
		say("  Reload once and run this again - if it is still 1, nothing addon-side can fix it.")
	end

	local snip = SPCompat.SecureSnippetsWork()
	say("secure snippets compile = %s  (probe marker %s)%s", tostring(snip), tostring(SPCompat.snippetProbeMarked),
		snip and "" or ("   |cffe5534bflyout hover/secure show-hide is OFF|r  (" .. tostring(SPCompat.SecureSnippetError()) .. ")"))
	if not snip then
		say("  ^ RestrictedExecution.lua:22 captured loadstring_untainted as nil, so every snippet")
		say("    body dies at its line 79. Cause unknown and engine-side: that Blizzard file is")
		say("    byte-identical to retail's, where the same snippets compile and in-combat flyouts")
		say("    work. Flyouts fall back to plain scripts, out of combat only. /spflyout secure")
		say("    forces the secure path back on to re-test after a client patch.")
	end

	say("--- Midnight restriction probes ---")
	say("namespaces present (shared client exports these EVERYWHERE - presence alone is NOT a restriction):")
	say("  issecretvalue %s  C_Secrets %s  C_RestrictedActions %s  InChatMessagingLockdown %s", exists(rawget(_G, "issecretvalue")), exists(rawget(_G, "C_Secrets")), exists(rawget(_G, "C_RestrictedActions")), exists(C_ChatInfo and C_ChatInfo.InChatMessagingLockdown))
	local secretBehavior = "n/a"
	if rawget(_G, "issecretvalue") then
		local okS, vS = pcall(issecretvalue, UnitHealth("player"))
		secretBehavior = okS and tostring(vS) or ("err: " .. tostring(vS))
	end
	local lockBehavior = "n/a"
	if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
		local okL, vL = pcall(C_ChatInfo.InChatMessagingLockdown)
		lockBehavior = okL and tostring(vL) or ("err: " .. tostring(vL))
	end
	say("BEHAVIOR (this is the real test): issecretvalue(UnitHealth) = |cffffd100%s|r (false = nothing is secret)   InChatMessagingLockdown() = |cffffd100%s|r (false/nil = comms open)", secretBehavior, lockBehavior)
	-- Registering the combat log is a forbidden protected action on this client
	-- in AND out of combat (measured: the ADDON_ACTION_FORBIDDEN popup, not a Lua
	-- error, so pcall reports "ok"). This diagnostic used to try it whenever no
	-- restriction was active, and so popped the dialog itself. Report the
	-- client's own answer instead of provoking it.
	local okR, restricted = pcall(function() return C_CombatLog and C_CombatLog.IsCombatLogRestricted and C_CombatLog.IsCombatLogRestricted() end)
	say("Combat log: C_CombatLog.IsCombatLogRestricted() = |cffffd100%s|r  (true = closed; registering CLEU is a forbidden action here, so it is not attempted)", okR and tostring(restricted) or ("err: " .. tostring(restricted)))
	say("secrets regime detected at load = |cffffd100%s|r   C_Secrets.HasSecretRestrictions() = %s   restrictions now (0=Combat 1=Encounter 2=M+ 3=PvP 4=Map 5=Chat): %s",
		tostring(SPCompat.secretsRegime), tostring(SPC("HasSecretRestrictions")), SPR())
	do
		-- Forever = Mainline game type "Camelot" (Meorawr): find whatever the client exposes to tell game types apart
		local hits = {}
		for k, v in pairs(_G) do
			if type(k) == "string" and (k:find("CAMELOT") or k:find("Camelot") or k:find("GAME_TYPE") or k:find("GameType")) then
				hits[#hits + 1] = k .. "=" .. tostring(type(v) == "table" and "table" or v)
			end
		end
		if Enum then
			for k, v in pairs(Enum) do
				if type(k) == "string" and (k:find("GameType") or k:find("GameMode") or k:find("GameRule") or k:find("Camelot")) then
					local keys = {}
					if type(v) == "table" then for kk in pairs(v) do keys[#keys + 1] = tostring(kk) end end
					table.sort(keys)
					hits[#hits + 1] = "Enum." .. k .. "{" .. table.concat(keys, ",") .. "}"
				end
			end
		end
		local gr = rawget(_G, "C_GameRules")
		local grFns = {}
		if type(gr) == "table" then for k in pairs(gr) do grFns[#grFns + 1] = tostring(k) end table.sort(grFns) end
		say("game-type probes: %s", #hits > 0 and table.concat(hits, "  ") or "no CAMELOT/GameType/GameMode/GameRule globals or enums")
		say("  C_GameRules: %s", #grFns > 0 and table.concat(grFns, ", ") or "absent")
		if type(gr) == "table" then
			local function call(n) local f = gr[n]; if not f then return "n/a" end local ok, v = pcall(f) return ok and tostring(v) or ("err: " .. tostring(v)) end
			local modes = {}
			if Enum and type(Enum.GameMode) == "table" then
				for k, v in pairs(Enum.GameMode) do if type(v) == "number" then modes[#modes + 1] = k .. "=" .. v end end
				table.sort(modes)
			end
			say("  active game mode: GetActiveGameMode()=%s  IsStandard()=%s  IsPlunderstorm()=%s   Enum.GameMode: %s",
				call("GetActiveGameMode"), call("IsStandard"), call("IsPlunderstorm"), table.concat(modes, " "))
		end
	end
	say("totem slot secrecy flags (ShouldTotemSlotBeSecret 1-4): %s %s %s %s", tostring(SPC("ShouldTotemSlotBeSecret", 1)),
		tostring(SPC("ShouldTotemSlotBeSecret", 2)), tostring(SPC("ShouldTotemSlotBeSecret", 3)), tostring(SPC("ShouldTotemSlotBeSecret", 4)))
	do
		local cdf = CreateFrame("Cooldown")
		local sbf = CreateFrame("StatusBar")
		local okAC = pcall(CreateFrame, "AuraContainer")
		say("engine timer pipeline (secret-safe display path): GetTotemDuration %s  Cooldown:SetCooldownFromDurationObject %s  StatusBar:SetTimerDuration %s  C_Spell.GetSpellCooldownDuration %s",
			exists(rawget(_G, "GetTotemDuration")), exists(cdf.SetCooldownFromDurationObject), exists(sbf.SetTimerDuration),
			exists(C_Spell and C_Spell.GetSpellCooldownDuration))
		say("  C_DurationUtil.CreateDurationTextBinding %s  C_CurveUtil %s  SetAlphaFromBoolean %s  AuraContainer frame type %s",
			exists(C_DurationUtil and C_DurationUtil.CreateDurationTextBinding), exists(rawget(_G, "C_CurveUtil")),
			exists(UIParent.SetAlphaFromBoolean), okAC and "|cff4cc776yes|r" or "|cffe5534bNO|r")
		local function cvar(n) local okc, v = pcall(GetCVar, n) return okc and tostring(v) or "err" end
		say("forced-restriction test cvars (nil = absent): addonCombatRestrictionsForced %s  addonEncounterRestrictionsForced %s  addonChatRestrictionsForced %s",
			cvar("addonCombatRestrictionsForced"), cvar("addonEncounterRestrictionsForced"), cvar("addonChatRestrictionsForced"))
	end
	if C_Secrets and C_Secrets.GetSpellAuraSecrecy then
		local ids = { 324, 24398, 974, 8512, 8143, 8166, 2484, 5394, 8075, 20608, 2825, 16190 }
		local parts = {}
		for _, id in ipairs(ids) do
			parts[#parts + 1] = string.format("%d:a%s/c%s", id, tostring(SPC("GetSpellAuraSecrecy", id)), tostring(SPC("GetSpellCooldownSecrecy", id)))
		end
		say("per-spell secrecy flags (0=NeverSecret 1=AlwaysSecret 2=Contextual; a=aura c=cooldown) LS WS ES WF Tremor Searing Earthbind ManaSpring SoE Reinc BL MT: %s", table.concat(parts, "  "))
	end

	say("secret-value guards this session: totem %d  cooldown %d  aura %d  (combatDataSecret=%s; counts only grow in combat on a restricted client)",
		SPCompat.secretHits.totem, SPCompat.secretHits.cooldown, SPCompat.secretHits.aura, tostring(SPCompat.combatDataSecret))

	say("--- Spell data sweep (name = in game data; nil = absent) ---")
	for _, row in ipairs(SPELL_SWEEP) do
		local name = GetSpellInfo and GetSpellInfo(row[1])
		say("%d %s -> %s", row[1], row[2], name and ("|cff4cc776" .. name .. "|r") or "|cffe5534bnil|r")
	end

	say("--- Totems (drop some first for real data) ---")
	if GetTotemInfo then
		for slot = 1, 4 do
			local have, name, start, dur = GetTotemInfo(slot)
			say("slot %d: %s %s dur %s", slot, SPV(have), SPV(name), SPV(dur))
		end
		if ShamanPower and ShamanPower.GetElementTotemInfo then
			local names = { "Earth", "Fire", "Water", "Air" }
			for element = 1, 4 do
				local have, name, _, _, _, slot = ShamanPower:GetElementTotemInfo(element)
				say("resolver %s: %s %s (slot %s)", names[element], tostring(have), tostring(name), tostring(slot))
			end
			say("dynamicTotemSlots (cast-order fill detected) = %s", tostring(ShamanPower.dynamicTotemSlots))
			if ShamanPower.shadowTotems then
				local parts = {}
				for element = 1, 4 do
					local e = ShamanPower.shadowTotems[element]
					parts[#parts + 1] = string.format("%s=%s", names[element], e and string.format("%s slot%s %.0fs/%ds", tostring(e.name), tostring(e.slot), GetTime() - (e.startTime or 0), e.duration or 0) or "-")
				end
				say("shadow totem model (own casts; used while totems are secret): %s", table.concat(parts, "  "))
			end
		end
	end

	-- Totem tooltip: does a "Tools: <Element> Totem" line exist? If yes, totem
	-- discovery can file every totem by element straight from the tooltip.
	do
		local lines, how = {}, "n/a"
		if C_TooltipInfo and C_TooltipInfo.GetSpellByID then
			local okT, data = pcall(C_TooltipInfo.GetSpellByID, 8512)   -- Windfury Totem R1
			if okT and data and data.lines then
				how = "C_TooltipInfo"
				for _, l in ipairs(data.lines) do
					local txt = l.leftText or (l.args and l.args[2] and l.args[2].stringVal)
					if txt then lines[#lines + 1] = txt end
				end
			end
		end
		if #lines == 0 and GameTooltip and GameTooltip.SetSpellByID then
			how = "GameTooltip scan"
			local tt = _G["ShamanPowerDiagTooltip"] or CreateFrame("GameTooltip", "ShamanPowerDiagTooltip", UIParent, "GameTooltipTemplate")
			tt:SetOwner(UIParent, "ANCHOR_NONE")
			pcall(tt.SetSpellByID, tt, 8512)
			for i = 1, tt:NumLines() do
				local fs = _G["ShamanPowerDiagTooltipTextLeft" .. i]
				local txt = fs and fs:GetText()
				if txt and txt ~= "" then lines[#lines + 1] = txt end
			end
			tt:Hide()
		end
		local tools
		for _, txt in ipairs(lines) do
			if txt:find("Totem") and (txt:find("^Tools") or txt:find("^Requires") or txt:find("Reagents")) then tools = txt end
		end
		say("totem tooltip (Windfury Totem, via %s): %d lines; element line -> %s", how, #lines, tools and ("|cff4cc776" .. tools .. "|r") or "|cffe5534bnone|r (no Tools: line - discovery must learn elements from the first cast)")
	end

	if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
		local res = C_ChatInfo.RegisterAddonMessagePrefix("SHPWRDIAG")
		local names = { [0] = "Success", [1] = "DuplicatePrefix (already registered - also fine)", [2] = "InvalidPrefix", [3] = "TooManyPrefixes" }
		local decoded = (res == true and "true (Success, classic bool)") or names[res] or tostring(res)
		say("addon message prefix register -> %s (|cffffd100%s|r)", tostring(res), decoded)
	end

	ShamanPowerErrorLog = ShamanPowerErrorLog or {}
	ShamanPowerErrorLog.diag = table.concat(out, "\n")
	ShowCopyWindow("ShamanPower Diagnostics", ShamanPowerErrorLog.diag)
	print("|cff3fa9f5SPDiag|r report opened in a copy window (also saved to ShamanPowerErrorLog - log out to flush to disk).")
end

-- ---------------------------------------------------------------------------
-- /spperf [seconds]  - where does the time and the garbage go?
-- Wraps every subsystem of the central update loop for a few seconds and reports
-- calls, milliseconds and kilobytes allocated per subsystem, the addon's memory
-- growth over the window, and the client's own profiler numbers when it has them.
-- Costs nothing while it is not running.
-- ---------------------------------------------------------------------------
SLASH_SPPERF1 = "/spperf"
SlashCmdList["SPPERF"] = function(msg)
	local SP = ShamanPower
	local us = SP and SP.updateSystem
	if not (us and us.subsystems) then print("spperf: no update system") return end
	if SP._perfRunning then print("spperf: already running") return end
	local secs = tonumber(msg) or 10
	if secs < 2 then secs = 2 elseif secs > 120 then secs = 120 end
	SP._perfRunning = true

	local stats, originals = {}, {}
	for name, sys in pairs(us.subsystems) do
		local cb = sys.callback
		local st = { calls = 0, ms = 0, kb = 0, enabled = sys.enabled, interval = sys.interval }
		stats[name], originals[name] = st, cb
		sys.callback = function()
			local m0, t0 = collectgarbage("count"), debugprofilestop()
			cb()
			local dt, dm = debugprofilestop() - t0, collectgarbage("count") - m0
			st.ms = st.ms + dt
			if dm > 0 then st.kb = st.kb + dm end   -- a negative delta is a GC step, not an allocation
			st.calls = st.calls + 1
		end
	end

	-- the methods those loops spend their time in (wrapped on the addon table, so only
	-- calls made as SP:Method() are seen; nested time is counted in both caller and callee)
	local FUNCS = { "GetElementTotemInfo", "GetActivePulsingTotem", "UpdatePulseGlow", "UpdatePoppedOutPulse", "UpdateTotemProgressBars",
		"UpdatePoppedOutProgressBars", "UpdateActiveTotemOverlays", "UpdateTotemCooldowns", "UpdateTotemBarOpacity", "UpdateDynamicTotemIcons",
		"UpdateCompactTotems", "UpdateReadyReminders", "UpdateCooldownButtons", "UpdateShieldChargeDisplays", "UpdatePartyRangeDots",
		"UpdatePlayerTotemRange", "UpdateRangeCounters" }
	-- plus every event handler (AceEvent calls SP[EVENT_NAME], looked up at call time)
	for key, value in pairs(SP) do
		if type(key) == "string" and type(value) == "function" and key:find("^[A-Z][A-Z0-9_]+$") then FUNCS[#FUNCS + 1] = key end
	end
	local fstats, forig = {}, {}
	for _, fname in ipairs(FUNCS) do
		local fn = rawget(SP, fname)
		if type(fn) == "function" then
			local st = { calls = 0, ms = 0, kb = 0 }
			fstats[fname], forig[fname] = st, fn
			SP[fname] = function(...)
				local m0, t0 = collectgarbage("count"), debugprofilestop()
				local a, b, c, d, e, f, g, h = fn(...)
				local dt, dm = debugprofilestop() - t0, collectgarbage("count") - m0
				st.ms = st.ms + dt; st.calls = st.calls + 1
				if dm > 0 then st.kb = st.kb + dm end
				return a, b, c, d, e, f, g, h
			end
		end
	end

	local addons = {}
	local n = (C_AddOns and C_AddOns.GetNumAddOns or GetNumAddOns)()
	local getInfo = C_AddOns and C_AddOns.GetAddOnInfo or GetAddOnInfo
	for i = 1, n do
		local name = getInfo(i)
		if type(name) == "string" and name:find("^ShamanPower") then addons[#addons + 1] = name end
	end
	UpdateAddOnMemoryUsage()
	local mem0 = {}
	for _, a in ipairs(addons) do mem0[a] = GetAddOnMemoryUsage(a) end
	local lua0, t0 = collectgarbage("count"), GetTime()
	print(string.format("|cff00ccffspperf|r measuring for %d s ... (combat=%s)", secs, tostring(InCombatLockdown())))

	C_Timer.After(secs, function()
		for name, sys in pairs(us.subsystems) do
			if originals[name] then sys.callback = originals[name] end
		end
		for fname, fn in pairs(forig) do SP[fname] = fn end
		SP._perfRunning = nil
		local window = GetTime() - t0
		UpdateAddOnMemoryUsage()   -- before the report below builds its own strings
		local memNow, luaNow = {}, collectgarbage("count")
		for _, a in ipairs(addons) do memNow[a] = GetAddOnMemoryUsage(a) end
		local rows = {}
		for name, st in pairs(stats) do rows[#rows + 1] = { name = name, st = st } end
		table.sort(rows, function(a, b) return a.st.ms > b.st.ms end)
		print(string.format("|cff00ccffspperf|r %.1f s window. Subsystems (central update loop):", window))
		local totalMs, totalKb = 0, 0
		for _, r in ipairs(rows) do
			local st = r.st
			totalMs, totalKb = totalMs + st.ms, totalKb + st.kb
			print(string.format("  %-16s %s every %.2fs  calls=%d  %.2f ms total (%.3f ms/call)  alloc %.1f KB (%.2f KB/s)",
				r.name, st.enabled and "ON " or "off", st.interval or 0, st.calls, st.ms, st.calls > 0 and st.ms / st.calls or 0, st.kb, st.kb / window))
		end
		print(string.format("  subsystems total: %.2f ms = %.3f%% of the window, alloc %.1f KB (%.2f KB/s)", totalMs, totalMs / (window * 10), totalKb, totalKb / window))
		local frows = {}
		for fname, st in pairs(fstats) do if st.calls > 0 then frows[#frows + 1] = { name = fname, st = st } end end
		table.sort(frows, function(a, b) return a.st.ms > b.st.ms end)
		print("  Methods (time includes whatever they call):")
		for _, r in ipairs(frows) do
			print(string.format("    %-28s calls=%-5d %.2f ms (%.4f ms/call)  alloc %.1f KB", r.name, r.st.calls, r.st.ms, r.st.ms / r.st.calls, r.st.kb))
		end
		for _, a in ipairs(addons) do
			local now = memNow[a]
			local grew = now - (mem0[a] or now)
			if math.abs(grew) > 0.5 or a == "ShamanPower" then
				print(string.format("  memory %-32s %.0f KB  (%+.1f KB over the window, %+.2f KB/s)", a, now, grew, grew / window))
			end
		end
		print(string.format("  whole Lua heap: %+.1f KB over the window", luaNow - lua0))
		if C_AddOnProfiler and C_AddOnProfiler.GetAddOnMetric and Enum and Enum.AddOnProfilerMetric then
			local M = Enum.AddOnProfilerMetric
			for _, a in ipairs(addons) do
				local ok, recent = pcall(C_AddOnProfiler.GetAddOnMetric, a, M.RecentAverageTime)
				local ok2, peak = pcall(C_AddOnProfiler.GetAddOnMetric, a, M.PeakTime)
				local ok3, session = pcall(C_AddOnProfiler.GetAddOnMetric, a, M.SessionAverageTime)
				if ok and type(recent) == "number" and (recent > 0.005 or a == "ShamanPower") then
					print(string.format("  client profiler %-28s recent %.3f ms/frame  session %.3f  peak %.2f", a, recent, ok3 and session or 0, ok2 and peak or 0))
				end
			end
		end
		print("|cff00ccffspperf|r done. Anything NOT in the subsystem list (event handlers, module OnUpdates) shows only in the memory / client profiler lines.")
	end)
end
