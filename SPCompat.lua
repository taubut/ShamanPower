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

SLASH_SPDIAG1 = "/spdiag"
SlashCmdList["SPDIAG"] = function()
	local out = {}
	local function say(fmt, ...)
		local line = select("#", ...) > 0 and string.format(fmt, ...) or fmt
		out[#out + 1] = line:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
		print("|cff3fa9f5SPDiag|r " .. line)
	end

	local v, build, bdate, iface = GetBuildInfo()
	say("=== ShamanPower beta diagnostics ===")
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
	local f = CreateFrame("Frame")
	local ok, err = pcall(f.RegisterEvent, f, "COMBAT_LOG_EVENT_UNFILTERED")
	say("CLEU RegisterEvent: %s%s", ok and "|cff4cc776ok|r" or "|cffe5534bBLOCKED|r", ok and "" or (" (" .. tostring(err) .. ")"))

	say("--- Spell data sweep (name = in game data; nil = absent) ---")
	for _, row in ipairs(SPELL_SWEEP) do
		local name = GetSpellInfo and GetSpellInfo(row[1])
		say("%d %s -> %s", row[1], row[2], name and ("|cff4cc776" .. name .. "|r") or "|cffe5534bnil|r")
	end

	say("--- Totems (drop some first for real data) ---")
	if GetTotemInfo then
		for slot = 1, 4 do
			local have, name, start, dur = GetTotemInfo(slot)
			say("slot %d: %s %s %s", slot, tostring(have), tostring(name), dur and ("dur " .. tostring(dur)) or "")
		end
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
