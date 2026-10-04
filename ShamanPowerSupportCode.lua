-- ============================================================================
-- Support code: one paste for a "why does it do this" question in #help on the
-- ShamanPower Discord, instead of a /run. It holds the player's game, a snapshot
-- of what ShamanPower sees right now, and every setting they changed from the
-- default. Nothing personal: no name, realm, guild, who they group with, chat,
-- profile names, raid assignments or saved positions. Built only when asked
-- (the Support Code buttons, /sp support); nothing here runs otherwise.
--
-- Format: "SPH1:" .. LibDeflate:EncodeForPrint(CompressDeflate(LibSerialize(payload)))
-- payload (short keys; the Discord bot decodes them):
--   v    code version (1)
--   t    time() when it was copied
--   g    the game: p WOW_PROJECT_ID, b build "1.60.1.70058", l GetLocale(),
--        v ShamanPower version, c class file ("SHAMAN"), s spec (SP.SHARE_SPECS
--        index, 0 unknown), lv level range start (0, 10, 20 ...)
--   k    looks in effect: st totem bar style, th theme, cu Custom look (bool),
--        is totem bar icon shape, cs cooldown bar icon shape, sw sweep style
--   n    right now: cb in combat, rs addon restrictions active, au auras
--        hidden, cd cooldowns hidden, gp "solo" / "party" / "raid", in instance
--        type, on ShamanPower switched on, sh ShamanPower sees a shield, se the
--        game draws the shield (engine), ss shadow shield record, ln the game's
--        Lightning Shield name is the English one, sb cooldown bar has a shield
--        button, ly game-drawn layers (only where auras can be hidden):
--        [name] = 0 missing, 1 built (hidden), 2 built and showing
--   s    the SPS1 setup code (feature on/offs, decoded by the same bot)
--   nl   ShamanPower's modules that are not loaded (folder names; none = nil)
--   set  the profile, only what differs from the defaults (decimals to 4 digits)
--   mod  [module SavedVariable] = only what differs from its defaults
--   lo   how many loadouts are saved (not their contents)
--   x    the rest of the picture, each part nil if the game cannot tell:
--        fa faction, gn group size, kn { [spell ID] = known } for the shields
--        and key spells, tk { [element 1-4] = totems known }, td { [slot 1-4] =
--        totem name or false } (tdh = true: hidden, tds = ShamanPower's own
--        tracking instead), er { { m = message, c = count, f = first seen, s =
--        stack lines } } the newest ShamanPower errors (the player's name and
--        realm taken out), ad { loaded addon names } (not ShamanPower's), sc
--        { w, h physical screen, u UI scale, ui uiScale cvar on }, bars { [name]
--        = { v shown, o on screen } }, kb { [binding] = key }, cv { [cvar] =
--        value }, mem ShamanPower KB, cpu { avg, recent, peak ms, all addons recent ms },
--        fps frame rate, lat { home, world } latency ms, up seconds since login,
--        bars[name] also a (alpha), s (scale)
--   h    load and save health (a "my settings reset" or "it vanished" answer
--        without a /run): i the client's interface number, fv / sr ShamanPower
--        thinks it is on WoW: Forever / in the secrets regime, cb SPCompat.BUILD,
--        vc the game's version check is on ("Load out of date AddOns" unticked),
--        m { [folder] = { l loaded, ok loadable, r the game's reason it is not,
--        e enabled for this character (0 none, 1 some, 2 all), v its Version, i its
--        TOC's interface, er it failed while loading, x false when not installed } }
--        for ShamanPower and every module, sv { g / c seconds since the account /
--        this character last saved ShamanPower cleanly (nil: none on record), n
--        clean saves on record, pk profile kind ("default" / "character" /
--        "other", never its name), np profiles, em { SavedVariables that were empty
--        when their module loaded }, big { addons the game would not save: too
--        large } }, bl { { f function, k "blocked" / "forbidden", c count } }
--        actions the game stopped ShamanPower doing, bg { BugSack's ShamanPower
--        errors, as er }, ui { u Unlock UI, k Keybind Mode, w settings window open },
--        rr the six addon restriction states (SPR())
-- ============================================================================

local SP = ShamanPower
if not SP then return end

local PREFIX = "SPH1:"
local CODE_VERSION = 1

-- Each settings module adds [its SavedVariable] = its defaults table here, so
-- only what the player changed goes in (a module without one goes in whole).
-- Settings > Reset This Page reads these defaults too.
SP.SUPPORT_MODULE_DEFAULTS = SP.SUPPORT_MODULE_DEFAULTS or {}
-- Profile tables whose defaults live in their own file, not the database's
-- (announce, readyCheck): those files add [profile key] = their defaults here.
SP.SUPPORT_PROFILE_DEFAULTS = SP.SUPPORT_PROFILE_DEFAULTS or {}
local MODULE_SVARS = { "ShamanPowerExpiringAlertsDB", "ShamanPower_ReadyReminders", "ShamanPower_ReactiveTotems",
	"ShamanPowerTremorReminderDB", "ShamanPower_RangeTracker", "ShamanPower_TargetTracker" }
local MODULES = { "ShamanPower_Config", "ShamanPower_ESTracker", "ShamanPower_ExpiringAlerts", "ShamanPower_PartyRange",
	"ShamanPower_RaidCooldowns", "ShamanPower_ReactiveTotems", "ShamanPower_ReadyReminders", "ShamanPower_ShieldCharges",
	"ShamanPower_SPRange", "ShamanPower_TargetTracker", "ShamanPower_TotemPlates", "ShamanPower_TremorReminder" }
-- each module's own SavedVariables (the core's are checked by its save stamp instead)
-- (not the Earth Shield Tracker's: it moved into the profile and clears its old one)
local MODULE_SV_OF = {
	ShamanPower_ExpiringAlerts = { "ShamanPowerExpiringAlertsDB" },
	ShamanPower_RaidCooldowns = { "ShamanPower_RaidCooldowns" }, ShamanPower_ReactiveTotems = { "ShamanPower_ReactiveTotems" },
	ShamanPower_ReadyReminders = { "ShamanPower_ReadyReminders" }, ShamanPower_SPRange = { "ShamanPower_RangeTracker" },
	ShamanPower_TremorReminder = { "ShamanPowerTremorReminderDB" },
	ShamanPower_TargetTracker = { "ShamanPower_TargetTracker" },
}

-- ---------------------------------------------------------------------------
-- Watched all session (cheap: these events are rare), for the h part of the code:
-- which SavedVariables were empty as their module loaded, addons the game would
-- not save, actions the game blocked, and a clean-save stamp written at logout or
-- /reload (WoW saves only then, so a crash loses what changed since the last one).
local health = { empty = {}, big = {}, blocked = {}, loginAt = nil }
do
	local f = CreateFrame("Frame")
	f:RegisterEvent("ADDON_LOADED")
	f:RegisterEvent("PLAYER_LOGIN")
	f:RegisterEvent("PLAYER_LOGOUT")
	pcall(f.RegisterEvent, f, "SAVED_VARIABLES_TOO_LARGE")
	pcall(f.RegisterEvent, f, "ADDON_ACTION_BLOCKED")
	pcall(f.RegisterEvent, f, "ADDON_ACTION_FORBIDDEN")
	f:SetScript("OnEvent", function(_, event, a, b)
		if event == "ADDON_LOADED" then
			-- this frame is older than the modules' own, so it hears their ADDON_LOADED
			-- first: a SavedVariable still empty here is one the game did not restore
			for _, sv in ipairs(MODULE_SV_OF[a] or {}) do
				if rawget(_G, sv) == nil then health.empty[#health.empty + 1] = sv end
			end
		elseif event == "PLAYER_LOGIN" then
			health.loginAt = GetTime()
		elseif event == "PLAYER_LOGOUT" then
			local db = SP.db
			if db and db.global and db.char then
				local now = time()
				db.global.supportSaved = now
				db.global.supportSaves = (tonumber(db.global.supportSaves) or 0) + 1
				db.char.supportSaved = now
			end
		elseif event == "SAVED_VARIABLES_TOO_LARGE" then
			if type(a) == "string" then health.big[#health.big + 1] = a end
		elseif type(a) == "string" and a:find("^ShamanPower") then   -- ADDON_ACTION_BLOCKED / _FORBIDDEN
			local key = tostring(b) .. "|" .. event
			local e = health.blocked[key]
			if not e then
				e = { f = tostring(b):sub(1, 80), k = event == "ADDON_ACTION_FORBIDDEN" and "forbidden" or "blocked", c = 0 }
				health.blocked[key] = e
			end
			e.c = e.c + 1
		end
	end)
end

-- Left out of the settings: saved positions (screen spots, not behavior), the
-- sound file paths (their names are kept) and the Custom card's saved copy of a look.
local function skipKey(k, parent)
	if type(k) ~= "string" then return false end
	if k:find("[Pp]os$") or k:find("[Pp]osition") or k:find("Shield[XY]$") or k == "offsetX" or k == "offsetY"
		or k == "soundFile" then return true end
	return k == "saved" and parent == "theme"
end

-- Settings the player types text into (a character or guild name can be in them):
-- the code only says they were changed, never what they say. The promise is
-- "nothing personal", and these are the free-text boxes that can break it.
local FREE_TEXT = {
	useText = true, soonText = true, triggers = true, replyReadyText = true, replyCooldownText = true,   -- Cooldown Announce
	target = true,   -- a loadout rule's Target (a mob, but anything can be typed)
}
local CUSTOM_TEXT = "(custom text)"

-- a value as it goes in: decimals cut to 4 digits (a saved 1.3999999761581 is 1.4)
local function plain(v)
	if type(v) == "number" and v ~= math.floor(v) then return tonumber(string.format("%.4g", v)) end
	if type(v) == "function" or type(v) == "userdata" then return nil end
	return v
end

local function copyPlain(v, name)
	if type(v) ~= "table" then return plain(v) end
	local out = {}
	for k, x in pairs(v) do
		if not skipKey(k, name) then
			local c
			if FREE_TEXT[k] and type(x) == "string" then c = CUSTOM_TEXT else c = copyPlain(x, k) end
			if c ~= nil then out[k] = c end
		end
	end
	return next(out) and out or nil
end

-- what differs from the defaults (the database's wildcard defaults included)
local function diff(cur, def, name, depth)
	if depth > 12 then return nil end
	local out
	for k, v in pairs(cur) do
		if not skipKey(k, name) then
			local d = nil
			if type(def) == "table" then
				d = def[k]
				if d == nil then d = def["**"] or def["*"] end
			end
			local x
			if type(v) == "table" then
				if type(d) == "table" then x = diff(v, d, k, depth + 1) else x = copyPlain(v, k) end
			elseif v ~= d then
				if FREE_TEXT[k] and type(v) == "string" then x = CUSTOM_TEXT else x = plain(v) end
			end
			if x ~= nil then
				out = out or {}
				out[k] = x
			end
		end
	end
	return out
end

local function safe(f, ...)
	local ok, v = pcall(f, ...)
	if ok then return v end
	return nil
end

-- a game-drawn layer: nil where it does not apply, 0 missing, 1 built, 2 built and showing
local function layer(frame, field)
	if not frame then return nil end
	local l = frame[field]
	if not l then return 0 end
	return (l.IsShown and l:IsShown()) and 2 or 1
end

-- ---------------------------------------------------------------------------
-- The rest of the picture (every part guarded: a client without an API just leaves it out)
local KEY_SPELLS = { 324, 24398, 974, 36936, 20608, 16188, 16190, 30823, 16166, 17364 }
local CVARS = { "countdownForCooldowns", "ActionButtonUseKeyDown", "useUiScale", "uiScale", "nameplateShowEnemyTotems",
	"nameplateShowFriendlyTotems", "addonProfilerEnabled" }
-- game functions ShamanPower calls by their old names: on Forever the game has none of
-- these and ShamanPower adds its own only when no other addon has (Questie's UnitBuff
-- once hid a shield); on Anniversary they are the game's unless an addon replaced one
local SHARED_GLOBALS = { "GetSpellInfo", "GetSpellTexture", "GetSpellCooldown", "GetSpellBookItemName", "IsPlayerSpell",
	"IsSpellKnown", "FindSpellBookSlotBySpellID", "GetAddOnMetadata", "IsAddOnLoaded", "GetItemInfo", "GetItemCount",
	"GetUnitName" }

local function known(id)
	if IsPlayerSpell and safe(IsPlayerSpell, id) then return true end
	if IsSpellKnown and safe(IsSpellKnown, id) then return true end
	return false
end

local function plainString(v)
	return type(v) == "string" and not (issecretvalue and issecretvalue(v)) and v or nil
end

-- text with the player's name and realm taken out: the name every way it can appear
-- (WoW: Forever's whole "First Surname" by SPCompat's name rule, each half of it, the
-- classic name) and the realm
local function scrubber()
	local ok, name, second = pcall(UnitName, "player")   -- both returns (safe() keeps only the first)
	if not ok then name, second = nil, nil end
	name, second = plainString(name), plainString(second)
	local full = SPCompat and SPCompat.UnitName and plainString(safe(SPCompat.UnitName, "player"))
	local realm = plainString(safe(GetRealmName))
	local parts = {}
	for _, p in ipairs({ full or false, name or false, second or false }) do
		if p and #p > 2 then parts[#parts + 1] = p end
	end
	table.sort(parts, function(a, b) return #a > #b end)   -- the whole name before its halves
	return function(text)
		text = tostring(text or "")
		for _, p in ipairs(parts) do text = text:gsub(p:gsub("%W", "%%%0"), "<you>") end
		if realm and #realm > 2 then text = text:gsub(realm:gsub("%W", "%%%0"), "<realm>") end
		return text
	end
end

-- a stack's ShamanPower lines (the collector in SPCompat.lua, in every stack, left out)
local function stackLines(stack, scrub)
	local lines, mine = {}, false
	for line in tostring(stack or ""):gmatch("[^\n]+") do
		if line:find("AddOns/ShamanPower", 1, true) and not line:find("SPCompat.lua", 1, true) then
			mine = true
			if #lines < 4 then lines[#lines + 1] = scrub(line:gsub("Interface/AddOns/", ""):sub(1, 140)) end
		end
	end
	return lines, mine
end

-- BugSack's ShamanPower errors (BugGrabber holds the error handler when it is
-- installed, so these may never reach ShamanPower's own log)
local function bugSackErrors(scrub)
	local bg = rawget(_G, "BugGrabber")
	if type(bg) ~= "table" or type(bg.GetDB) ~= "function" then return nil end
	local ok, db = pcall(bg.GetDB, bg)
	if not ok or type(db) ~= "table" then return nil end
	local list = {}
	for i = #db, 1, -1 do
		local e = db[i]
		if type(e) == "table" then
			local msg = tostring(e.message or "")
			local lines, mine = stackLines(e.stack, scrub)
			if mine or msg:find("ShamanPower", 1, true) then
				list[#list + 1] = { m = scrub(msg:sub(1, 240)), c = e.counter, f = e.time, s = lines }
				if #list >= 5 then break end
			end
		end
	end
	return list[1] and list or nil
end

-- the newest ShamanPower errors from the error log (/sperrors), the player's name and realm taken out
local function recentErrors()
	local log = rawget(_G, "ShamanPowerErrorLog")
	local errors = type(log) == "table" and log.errors
	if type(errors) ~= "table" then return nil end
	local scrub = scrubber()
	local list = {}
	for msg, e in pairs(errors) do
		if type(e) == "table" then
			-- (an error inside SPCompat.lua itself names the file in its message)
			local lines, mine = stackLines(e.stack, scrub)
			mine = mine or tostring(msg):find("ShamanPower", 1, true)
			if mine then
				list[#list + 1] = { m = scrub(tostring(msg):sub(1, 240)), c = e.count, f = e.first, l = e.last, s = lines }
			end
		end
	end
	table.sort(list, function(a, b) return tostring(a.f) > tostring(b.f) end)
	for i = #list, 6, -1 do list[i] = nil end
	return list[1] and list or nil
end

local function onScreen(f)
	if not (f and f.GetCenter and UIParent) then return nil end
	local x, y = f:GetCenter()
	if not (x and y) then return false end
	local k = (f:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
	x, y = x * k, y * k
	return x >= 0 and y >= 0 and x <= UIParent:GetWidth() and y <= UIParent:GetHeight()
end

local function extras()
	local x = {}
	x.fa = safe(UnitFactionGroup, "player")
	x.gn = GetNumGroupMembers and safe(GetNumGroupMembers) or nil
	-- spells: the shields and the key cooldowns (any rank: every rank stays in the spellbook)
	local kn = {}
	for _, id in ipairs(KEY_SPELLS) do kn[id] = known(id) end
	for _, s in ipairs(SP.ShieldSpells or {}) do if type(s[1]) == "number" then kn[s[1]] = known(s[1]) end end
	x.kn = kn
	if SP.KnowsTotem and SP.GetTotemSpell then
		local tk = {}
		for element = 1, 4 do
			local n = 0
			for i = 1, 20 do
				if not safe(SP.GetTotemSpell, SP, element, i) then break end
				if safe(SP.KnowsTotem, SP, element, i) then n = n + 1 end
			end
			tk[element] = n
		end
		x.tk = tk
	end
	-- totems down: the game's answer; while it is hidden (Forever in combat), ShamanPower's own tracking
	local getTotem = (SPCompat and SPCompat.GetTotemInfo) or GetTotemInfo
	if getTotem then
		local td, hidden = {}, false
		for slot = 1, 4 do
			local ok, have, name = pcall(getTotem, slot)
			if ok and plainString(name) and name ~= "" then td[slot] = name
			else td[slot] = false; if not ok then hidden = true end end
		end
		x.td = td
		if (SP.shieldCache and SP.shieldCache.engineCount) or hidden then
			x.tdh = true
			local tds = {}
			for element, e in pairs(SP.shadowTotems or {}) do
				if type(e) == "table" then tds[element] = plainString(e.name) or true end
			end
			x.tds = tds
		end
	end
	x.er = recentErrors()
	-- which addon defined any of those (the game's own and ShamanPower's own are left out)
	local secure = rawget(_G, "issecurevariable")
	if secure then
		local gw = {}
		for _, name in ipairs(SHARED_GLOBALS) do
			if rawget(_G, name) ~= nil then
				local ok, isSecure, by = pcall(secure, name)
				by = ok and plainString(by) or nil
				if ok and not isSecure and not (by and by:find("^ShamanPower")) then gw[name] = by or "?" end
			end
		end
		if next(gw) then x.gw = gw end
	end
	-- addons: every loaded one by name (not ShamanPower's own), for clashes
	local num = (C_AddOns and C_AddOns.GetNumAddOns) or GetNumAddOns
	local info = (C_AddOns and C_AddOns.GetAddOnInfo) or GetAddOnInfo
	local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
	if num and info and loaded then
		local ad = {}
		for i = 1, safe(num) or 0 do
			local name = plainString(safe(info, i))
			if name and not name:find("^ShamanPower") and safe(loaded, i) then ad[#ad + 1] = name end
		end
		table.sort(ad)
		x.ad = ad
	end
	-- screen and bars
	local sw, sh = nil, nil
	if GetPhysicalScreenSize then sw, sh = GetPhysicalScreenSize() end
	x.sc = { w = sw, h = sh, u = UIParent and UIParent:GetEffectiveScale() or nil }
	local bars = {}
	for key, f in pairs({ totem = SP.autoButton, cooldown = SP.cooldownBar, loadout = SP.loadoutAnchor,
		esTracker = rawget(_G, "ShamanPowerESTrackerFrame") }) do
		if f and f.IsVisible then
			bars[key] = { v = f:IsVisible() and true or false, o = onScreen(f),
				a = f.GetEffectiveAlpha and tonumber(string.format("%.2g", f:GetEffectiveAlpha() or 1)) or nil,
				s = f.GetScale and tonumber(string.format("%.3g", f:GetScale() or 1)) or nil }
		end
	end
	x.bars = bars
	-- frame rate, latency and how long this session has run
	if GetFramerate then x.fps = math.floor((safe(GetFramerate) or 0) + 0.5) end
	if GetNetStats then
		local ok, _, _, home, world = pcall(GetNetStats)
		if ok then x.lat = { home = home, world = world } end
	end
	if health.loginAt then x.up = math.floor(GetTime() - health.loginAt) end
	-- ShamanPower's key bindings
	if GetNumBindings and GetBinding then
		local kb = {}
		for i = 1, safe(GetNumBindings) or 0 do
			local ok, command, _, key1 = pcall(GetBinding, i)
			if ok and type(command) == "string" and command:find("^SHAMANPOWER") and key1 then kb[command] = key1 end
		end
		if next(kb) then x.kb = kb end
	end
	-- game options that change what ShamanPower shows
	if GetCVar then
		local cv = {}
		for _, name in ipairs(CVARS) do cv[name] = safe(GetCVar, name) end
		x.cv = cv
	end
	-- memory and CPU (Blizzard's addon profiler, where the client has it)
	if UpdateAddOnMemoryUsage and GetAddOnMemoryUsage then
		safe(UpdateAddOnMemoryUsage)
		local kb = 0
		for _, name in ipairs({ "ShamanPower", unpack(MODULES) }) do kb = kb + (safe(GetAddOnMemoryUsage, name) or 0) end
		x.mem = math.floor(kb + 0.5)
	end
	local P = rawget(_G, "C_AddOnProfiler")
	local M = Enum and Enum.AddOnProfilerMetric
	if P and P.GetAddOnMetric and M then
		local function ms(metric)
			local sum = 0
			for _, name in ipairs({ "ShamanPower", unpack(MODULES) }) do sum = sum + (safe(P.GetAddOnMetric, name, metric) or 0) end
			return tonumber(string.format("%.4g", sum))
		end
		x.cpu = { avg = ms(M.SessionAverageTime), recent = ms(M.RecentAverageTime), peak = ms(M.PeakTime),
			all = P.GetOverallMetric and tonumber(string.format("%.4g", safe(P.GetOverallMetric, M.RecentAverageTime) or 0)) or nil }
	end
	return x
end

-- Load and save health: why a module is not running, and whether the settings the
-- player sees came from a save (see the header's h)
local function loadHealth()
	local A = C_AddOns or {}
	local h = {}
	h.i = select(4, GetBuildInfo())
	local compat = rawget(_G, "SPCompat")
	if compat then h.fv, h.sr, h.cb = compat.FOREVER, compat.secretsRegime, compat.BUILD end
	if A.IsAddonVersionCheckEnabled then h.vc = safe(A.IsAddonVersionCheckEnabled) end
	local me = plainString(safe(UnitName, "player"))
	local getInfo = A.GetAddOnInfo or GetAddOnInfo
	local getMeta = A.GetAddOnMetadata or GetAddOnMetadata
	local m = {}
	for _, name in ipairs({ "ShamanPower", unpack(MODULES) }) do
		local e = {}
		if A.DoesAddOnExist and safe(A.DoesAddOnExist, name) == false then
			e.x = false
		else
			if A.IsAddOnLoaded then e.l = safe(A.IsAddOnLoaded, name) and true or false end
			if getInfo then
				local ok, _, _, _, loadable, reason = pcall(getInfo, name)
				if ok then e.ok = loadable and true or false; e.r = plainString(reason) end
			end
			if A.GetAddOnEnableState and me then e.e = safe(A.GetAddOnEnableState, name, me) end
			if getMeta then e.v = plainString(safe(getMeta, name, "Version")) end
			if A.GetAddOnInterfaceVersion then e.i = safe(A.GetAddOnInterfaceVersion, name) end
			if A.DoesAddOnHaveLoadError and safe(A.DoesAddOnHaveLoadError, name) then e.er = true end
		end
		m[name] = e
	end
	h.m = m
	-- saves: the stamps written at the last clean logout / reload, and the profile in use
	local sv = {}
	local db, now = SP.db, time()
	if db then
		local g, c = db.global and db.global.supportSaved, db.char and db.char.supportSaved
		if type(g) == "number" then sv.g = now - g end
		if type(c) == "number" then sv.c = now - c end
		sv.n = db.global and tonumber(db.global.supportSaves) or nil
		local cur = db.GetCurrentProfile and safe(db.GetCurrentProfile, db)
		local charKey = db.keys and db.keys.char
		sv.pk = (cur == "Default" and "default") or (cur ~= nil and cur == charKey and "character") or (cur and "other") or nil
		if db.GetProfiles then
			local ok, list = pcall(db.GetProfiles, db)
			if ok and type(list) == "table" then sv.np = #list end
		end
	end
	if health.empty[1] then sv.em = health.empty end
	if health.big[1] then sv.big = health.big end
	h.sv = sv
	local bl = {}
	for _, e in pairs(health.blocked) do bl[#bl + 1] = e end
	if bl[1] then h.bl = bl end
	h.bg = bugSackErrors(scrubber())
	h.ui = { u = SP.IsMasterUnlocked and safe(SP.IsMasterUnlocked, SP) and true or false,
		k = SP.KeybindModeActive and safe(SP.KeybindModeActive, SP) and true or false }
	local win = rawget(_G, "ShamanPowerConfigUIFrame")
	if win and win.IsShown then h.ui.w = win:IsShown() and true or false end
	if rawget(_G, "SPR") then h.rr = plainString(safe(SPR)) end
	return h
end

local function snapshot()
	local n = {}
	n.cb = InCombatLockdown() and true or false
	local compat = rawget(_G, "SPCompat")
	if compat and compat.AnyRestrictionActive then n.rs = safe(compat.AnyRestrictionActive) and true or false end
	local secrets = rawget(_G, "C_Secrets")
	if secrets then
		if secrets.ShouldAurasBeSecret then n.au = safe(secrets.ShouldAurasBeSecret) == true end
		if secrets.ShouldCooldownsBeSecret then n.cd = safe(secrets.ShouldCooldownsBeSecret) == true end
	end
	n.gp = IsInRaid() and "raid" or (IsInGroup() and "party" or "solo")
	n["in"] = select(2, IsInInstance()) or "none"
	n.on = not (SP.IsOff and SP:IsOff())
	local c = SP.shieldCache
	if type(c) == "table" then
		n.sh = c.hasShield and true or false
		n.se = c.engineCount == true
	end
	n.ss = SP.shadowShield ~= nil
	n.ln = safe(GetSpellInfo, 324) == "Lightning Shield"
	n.sb = SP.shieldButton ~= nil
	if compat and compat.secretsRegime then
		local ly = {}
		ly.cdShield = layer(SP.shieldButton, "chargeContainer")          -- cooldown bar shield button
		ly.esButton = layer(rawget(_G, "ShamanPowerEarthShieldBtn"), "chargeContainer")
		local frames = SP.shieldChargeFrames
		ly.chargesShield = layer(frames and frames.player, "engine")    -- Shield Charges: your shield
		ly.chargesES = layer(frames and frames.earth, "engine")         -- Shield Charges: Earth Shield
		n.ly = ly
	end
	return n
end

function SP:BuildSupportCode()
	local LS = LibStub and LibStub("LibSerialize", true)
	local LD = LibStub and LibStub("LibDeflate", true)
	if not (LS and LD) then return nil, "files needed to create a Support Code are missing" end
	local o = self.opt or {}
	local version, build = GetBuildInfo()
	local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
	local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
	local isShaman = select(2, UnitClass("player")) == "SHAMAN"

	local payload = {
		v = CODE_VERSION,
		t = time(),
		g = {
			p = WOW_PROJECT_ID,
			b = tostring(version or "?") .. "." .. tostring(build or "?"),
			l = GetLocale(),
			v = getMeta and getMeta("ShamanPower", "Version") or nil,
			c = select(2, UnitClass("player")),
			s = isShaman and self.ShareSpecIndex and safe(self.ShareSpecIndex) or 0,
			lv = math.floor((UnitLevel("player") or 0) / 10) * 10,
		},
		k = {
			st = self.GetTotemBarStyle and safe(self.GetTotemBarStyle, self) or nil,
			th = self.ThemeGlobal and safe(self.ThemeGlobal, self) or nil,
			cu = self.ThemeIsCustom and safe(self.ThemeIsCustom, self) and true or false,
			is = self.IconShapeOf and safe(self.IconShapeOf, self, "totem") or nil,
			cs = self.IconShapeOf and safe(self.IconShapeOf, self, "cooldown") or nil,
			sw = o.cdbarSweepStyle,
		},
		n = snapshot(),
		s = self.BuildShareCode and safe(self.BuildShareCode, self) or nil,
	}
	for _, name in ipairs(MODULES) do
		if not (isLoaded and safe(isLoaded, name)) then
			payload.nl = payload.nl or {}
			payload.nl[#payload.nl + 1] = name
		end
	end
	local defaults = self.db and self.db.defaults and self.db.defaults.profile   -- the non-shaman (Other) set for a non-shaman
	local extra = self.SUPPORT_PROFILE_DEFAULTS
	local view = setmetatable({}, { __index = function(_, k)
		local d = defaults and defaults[k]
		if d == nil and k ~= "*" and k ~= "**" then d = extra[k] end
		return d
	end })
	payload.set = diff(o, view, nil, 0)
	for _, name in ipairs(MODULE_SVARS) do
		local cur = rawget(_G, name)
		if type(cur) == "table" then
			local d = diff(cur, self.SUPPORT_MODULE_DEFAULTS[name], nil, 0)
			if d then
				payload.mod = payload.mod or {}
				payload.mod[name] = d
			end
		end
	end
	local loadouts = rawget(_G, "ShamanPower_TotemLoadouts")
	payload.lo = type(loadouts) == "table" and #loadouts or 0
	local okX, x = pcall(extras)
	payload.x = okX and x or { fail = tostring(x) }
	local okH, h = pcall(loadHealth)
	payload.h = okH and h or { fail = tostring(h) }

	local ok, serialized = pcall(LS.Serialize, LS, payload)
	if not ok or not serialized then return nil, "could not prepare the Support Code" end
	local compressed = LD:CompressDeflate(serialized, { level = 9 })
	if not compressed then return nil, "could not create the Support Code" end
	return PREFIX .. LD:EncodeForPrint(compressed)
end

-- The copy box (ShamanPower's own dialog: WoW cannot write the clipboard, so
-- the code sits selected and Ctrl+C copies it).
function SP:ShowSupportCode()
	local ok, code, err = pcall(self.BuildSupportCode, self)
	if not ok or not code then
		print("|cff0070ddShamanPower|r: could not build the support code (" .. tostring(ok and err or code) .. ").")
		return
	end
	self:ShowSPDialog({
		key = "supportcode",
		title = "Support Code",
		subtitle = "For the #help channel",
		width = 460,
		editScroll = true,
		text = "Paste this in #help on the ShamanPower Discord (discord.gg/eCtNeBqE8U) with a few words about the problem. "
			.. "Copy it while the problem is on screen so it includes what is happening now.\n\n"
			.. "Press |cffFFD100Ctrl+C|r to copy it.\n\n"
			.. "|cff3FA9F5WHAT'S IN IT|r\n"
			.. "- Your game, language, ShamanPower version, class, spec and level range\n"
			.. "- The settings you changed from the default\n"
			.. "- Whether you are in combat and what ShamanPower can show right now\n"
			.. "- Your recent ShamanPower errors (BugSack's too), the spells you know, your addon list, screen size and key bindings\n"
			.. "- Which ShamanPower features loaded, any problems loading them, and when your settings were last saved\n"
			.. "- Never: your name, realm, guild, who you group with, or chat",
		editText = code,
	})
end

-- General > Main, the Discord section: right under Share My Setup, in gold
do
	local main = SP.options and SP.options.args and SP.options.args.settings
		and SP.options.args.settings.args.settings_show and SP.options.args.settings.args.settings_show.args
	if main then
		main.support_code = {
			order = 92, type = "execute", name = "Get Help: Copy Support Code", width = "full",
			desc = "Copy details about your game, your ShamanPower version, what ShamanPower shows right now and the settings you changed. No name, realm or guild is included. Paste the code in #help on the ShamanPower Discord when something looks wrong. Also: /sp support",
			func = function() SP:ShowSupportCode() end,
		}
		SP.OptionButtonTone = SP.OptionButtonTone or {}
		SP.OptionButtonTone[main.support_code] = "help"
	end
end
