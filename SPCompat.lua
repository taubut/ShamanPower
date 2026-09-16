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

-- ---------------------------------------------------------------------------
-- 1. Polyfills (inert wherever the classic globals still exist)
-- ---------------------------------------------------------------------------
if not GetSpellInfo and C_Spell and C_Spell.GetSpellInfo then
	function GetSpellInfo(spell)
		local s = C_Spell.GetSpellInfo(spell)
		if not s then return nil end
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
	function GetSpellCooldown(spell)
		local c = C_Spell.GetSpellCooldown(spell)
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

-- Retail 12.1 keeps GetWeaponEnchantInfo only as a deprecated shim slated for
-- removal; C_PaperDollInfo.GetTemporaryEnchantmentInfo(16/17) is the backend.
if not GetWeaponEnchantInfo and C_PaperDollInfo and C_PaperDollInfo.GetTemporaryEnchantmentInfo then
	local function slotInfo(slot)
		local ok, t = pcall(C_PaperDollInfo.GetTemporaryEnchantmentInfo, slot)
		if not ok or type(t) ~= "table" or not t.enchantID or t.enchantID == 0 then return false, nil, nil, nil end
		return true, t.remainingTimeMs, t.chargesRemaining, t.enchantID
	end
	function GetWeaponEnchantInfo()
		local hm, me, mc, mid = slotInfo(16)
		local ho, oe, oc, oid = slotInfo(17)
		-- classic order: hasMain, mainExpiration, mainCharges, mainEnchantID, hasOff, offExpiration, offCharges, offEnchantID
		return hm, me, mc, mid, ho, oe, oc, oid
	end
end

if not BOOKTYPE_SPELL then BOOKTYPE_SPELL = "spell" end
if not GetSpellBookItemName and C_SpellBook and C_SpellBook.GetSpellBookItemName then
	function GetSpellBookItemName(index, bookType)
		local bank = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
		return C_SpellBook.GetSpellBookItemName(index, bank)
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
MAX_ACCOUNT_MACROS   = MAX_ACCOUNT_MACROS   or 120
MAX_CHARACTER_MACROS = MAX_CHARACTER_MACROS or 18
MAX_PARTY_MEMBERS    = MAX_PARTY_MEMBERS    or 4
MAX_RAID_MEMBERS     = MAX_RAID_MEMBERS     or 40
LE_PARTY_CATEGORY_HOME     = LE_PARTY_CATEGORY_HOME     or 1
LE_PARTY_CATEGORY_INSTANCE = LE_PARTY_CATEGORY_INSTANCE or 2

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
SPCompat.BUILD = "2026-09-16p"   -- bump when the diag tooling changes so a paste shows whether /reload happened
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
	function SPCompat.ShadowCooldownCast(spellID)
		local key = cdKey(spellID)
		if not key then return end
		local e = shadowCD[key] or {}
		e.start, e.id = GetTime(), spellID
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
					if start and dur and start > 0 and dur > 1.5 then
						local e = shadowCD[key] or {}
						e.start, e.duration = start, dur
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
						local okc, cd = pcall(C_Spell.GetSpellCooldown, id)
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

	local function clearIfUnrestricted()
		if anyRestrictionActive() then return end
		auraBlocked = false
		SPCompat.combatDataSecret = false
	end
	SPCompat.ClearIfUnrestricted = clearIfUnrestricted
	local regen = CreateFrame("Frame")
	regen:RegisterEvent("PLAYER_REGEN_ENABLED")
	pcall(regen.RegisterEvent, regen, "ADDON_RESTRICTION_STATE_CHANGED")   -- fires for the forced-cvar rehearsal too
	regen:SetScript("OnEvent", clearIfUnrestricted)
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
		ShamanPowerErrorLog = ShamanPowerErrorLog or {}
		ShamanPowerErrorLog.errors = ShamanPowerErrorLog.errors or {}
		ShamanPowerErrorLog.session = date and date("%Y-%m-%d %H:%M") or ""
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
	end
	local out = { string.format("=== ShamanPower flyout trace (compat build %s, leave snippet %s) ===", SPCompat.BUILD or "?",
		(ShamanPower and ShamanPower.totemButtons and ShamanPower.totemButtons[1] and ShamanPower.totemFlyouts and ShamanPower.totemFlyouts[1]
			and ShamanPower.totemFlyouts[1].allButtons and ShamanPower.totemFlyouts[1].allButtons[1]
			and tostring(ShamanPower.totemFlyouts[1].allButtons[1]:GetAttribute("_onleave")):find('GetAttribute("_onleave")', 1, true)) and "NEW2" or "old"),
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
local function traceEvent(fmt, ...)
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
					if a == "player" then traceEvent("%s unit=%s spellID=%s", e, SPV(a), SPV(c)) end
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
		print("|cff4cc776ShamanPower:|r event trace on (own casts, totem updates, restriction/encounter changes, SHPWR comms). /sptrace to view, /sptrace off to stop")
	elseif msg == "off" then
		if eventTraceFrame then eventTraceFrame:UnregisterAllEvents() end
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
	-- Registering the combat log is a PROTECTED action while a restriction is
	-- active: the client blocks it and fires ADDON_ACTION_FORBIDDEN (a popup),
	-- not a Lua error, so pcall would report "ok". Only probe when unrestricted.
	if SPCompat.AnyRestrictionActive and SPCompat.AnyRestrictionActive() then
		say("CLEU RegisterEvent: |cffffd100skipped|r (a restriction is active - registering now is a forbidden protected action)")
	else
		local f = CreateFrame("Frame")
		local ok, err = pcall(f.RegisterEvent, f, "COMBAT_LOG_EVENT_UNFILTERED")
		say("CLEU RegisterEvent: %s%s  (out of restriction; forbidden while one is active)", ok and "|cff4cc776ok|r" or "|cffe5534bBLOCKED|r", ok and "" or (" (" .. tostring(err) .. ")"))
	end
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
