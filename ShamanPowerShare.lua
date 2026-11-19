-- ShamanPowerShare
-- Export/import of a ShamanPower configuration as a copyable string, and the
-- capture side of setup presets. String format: "SP1:" .. base64(deflate(
-- serialize(payload))). LibSerialize + LibDeflate do the heavy lifting.

local SP = ShamanPower
local Serializer = LibStub and LibStub("LibSerialize", true)
local Deflate    = LibStub and LibStub("LibDeflate", true)

local PREFIX = "SP1:"

-- Every module SavedVariable that lives outside the AceDB profile. Used by a
-- full profile export (your own backup). A setup preset (shared with others)
-- uses PRESET_SVARS below, which drops the transient per-raid assignment data.
local EXTRA_SVARS = {
	"ShamanPower_RangeTracker",
	"ShamanPower_ReactiveTotems",
	"ShamanPowerTremorReminderDB",
	"ShamanPower_TotemLoadouts",
	"ShamanPower_LoadoutGroups",      -- Auto Loadout Groups (3.0.9.5): your own, like the loadouts (never in a preset)
	"ShamanPower_ESTracker",
	"ShamanPowerExpiringAlertsDB",
	"ShamanPower_ReadyReminders",
	"ShamanPower_TargetTracker",
	"ShamanPower_RaidCooldowns",
	"ShamanPower_Assignments",
	"ShamanPower_EarthShieldAssignments",
	"ShamanPower_TwistAssignments",
	"ShamanPowerWindfuryProcDB",      -- Windfury Proc (3.0.9.17, WoW: Forever)
	"ShamanPowerHealingTrackerDB",    -- Frame Buff Indicators (3.0.9.17, WoW: Forever)
}

-- Setup-preset scope: everything that defines the look/feel/positions, but NOT
-- the current totem choices on the bar or per-player raid assignments (those
-- stay at the importing user's defaults). RaidCooldowns is stripped to just
-- the caller-button position; the bloodlust/manatide/drums assignments drop.
local PRESET_SVARS = {
	"ShamanPower_RangeTracker",       -- which totems the range overlay tracks + its layout
	"ShamanPower_ReactiveTotems",     -- per-totem reactive settings + positions
	"ShamanPowerTremorReminderDB",    -- tremor size/position/custom mob list
	"ShamanPower_TotemLoadouts",      -- the user's saved loadouts
	"ShamanPower_ESTracker",          -- ES tracker settings + position
	"ShamanPowerExpiringAlertsDB",    -- expiring-alerts settings + position
	"ShamanPower_ReadyReminders",     -- which reminders, look + positions
	"ShamanPower_TargetTracker",      -- each spell's look and when, rules, positions
	"ShamanPowerWindfuryProcDB",      -- Windfury Proc's settings + position (3.0.9.17)
	"ShamanPowerHealingTrackerDB",    -- Frame Buff Indicators' looks and spots on the frames (3.0.9.17)
}
-- The tables an import may write (a string names them itself, so it is checked
-- against this list: a tampered string must not replace any other global).
local IMPORTABLE = {}
for _, name in ipairs(EXTRA_SVARS) do IMPORTABLE[name] = true end

local PRESET_SVAR_STRIP = {
	-- keep only these keys from a table (drop everything else)
	ShamanPower_RaidCooldowns = { callerButtonPos = true },
}

-- Deep copy that skips functions and metatables (safe to serialize).
-- every default the profile is missing, as the database lays them in at load
-- (wildcard defaults are the database's own, left to it)
local function FillDefaults(dest, src)
	if type(src) ~= "table" then return end
	for k, v in pairs(src) do
		if k ~= "*" and k ~= "**" then
			if type(v) == "table" then
				if rawget(dest, k) == nil then rawset(dest, k, {}) end
				if type(dest[k]) == "table" then FillDefaults(dest[k], v) end
			elseif rawget(dest, k) == nil then
				rawset(dest, k, v)
			end
		end
	end
end

local function CleanCopy(v, seen)
	if type(v) ~= "table" then
		if type(v) == "function" then return nil end
		return v
	end
	seen = seen or {}
	if seen[v] then return nil end     -- drop cycles
	seen[v] = true
	local out = {}
	for k, val in pairs(v) do
		if type(k) ~= "function" then
			local cv = CleanCopy(val, seen)
			if cv ~= nil then out[k] = cv end
		end
	end
	seen[v] = nil
	return out
end

function SP:BuildSharePayload(opts)
	opts = opts or {}
	local payload = {
		v = 1,
		addon = "ShamanPower",
		profile = CleanCopy(self.db.profile),
	}
	if opts.includeExtras then
		payload.extras = {}
		for _, name in ipairs(EXTRA_SVARS) do
			if _G[name] then payload.extras[name] = CleanCopy(_G[name]) end
		end
		-- Your Themes (account-wide, Appearance > Themes): the full export carries them, so the
		-- profile's own theme comes along to another account or game (ImportShare puts them in)
		local themes = self.db and self.db.global and self.db.global.themes
		if type(themes) == "table" and #themes > 0 then payload.themes = CleanCopy(themes) end
	end
	return payload
end

function SP:EncodeShare(payload)
	if not (Serializer and Deflate) then
		return nil, "files needed to share settings are missing"
	end
	local ok, serialized = pcall(function() return Serializer:Serialize(payload) end)
	if not ok or not serialized then return nil, "could not prepare your settings for sharing" end
	local compressed = Deflate:CompressDeflate(serialized, { level = 9 })
	if not compressed then return nil, "could not create the setup code" end
	return PREFIX .. Deflate:EncodeForPrint(compressed)
end

function SP:DecodeShare(str)
	if not (Serializer and Deflate) then return nil, "files needed to share settings are missing" end
	if type(str) ~= "string" then return nil, "paste a setup code first" end
	str = strtrim(str)
	if str:sub(1, #PREFIX) ~= PREFIX then return nil, "not a ShamanPower setup code" end
	local body = str:sub(#PREFIX + 1)
	local compressed = Deflate:DecodeForPrint(body)
	if not compressed then return nil, "the setup code is damaged or incomplete" end
	local serialized = Deflate:DecompressDeflate(compressed)
	if not serialized then return nil, "the setup code is damaged or incomplete" end
	local ok, payload = Serializer:Deserialize(serialized)
	if not ok or type(payload) ~= "table" then return nil, "could not read the setup code" end
	if payload.addon ~= "ShamanPower" then return nil, "the setup code is for a different addon" end
	return payload
end

-- Safety net: snapshot the whole current setup (profile + module tables)
-- before a preset replaces it. Account-wide, last three kept.
function SP:BackupCurrentSetup(reason)
	local str = self:ExportCurrentProfile()
	if not str then return nil end
	self.db.global.setupBackups = self.db.global.setupBackups or {}
	local list = self.db.global.setupBackups
	table.insert(list, 1, { reason = reason or "backup", profile = self.db:GetCurrentProfile(), date = date("%Y-%m-%d %H:%M"), str = str })
	while #list > 3 do table.remove(list) end
	return list[1]
end

-- Bring a backup back as a NEW profile (the current one is left alone) and
-- put the module tables back the way they were.
function SP:RestoreSetupBackup(index)
	local list = self.db.global.setupBackups
	local b = list and list[index or 1]
	if not b then return nil, "no backup saved" end
	local ok, res = self:ImportShare(b.str, "newProfile", (b.profile or "Profile") .. " (restored " .. b.date .. ")")
	if ok then print("|cff0070ddShamanPower|r: restored your setup from " .. b.date .. " into profile '" .. tostring(res) .. "'.") end
	return ok, res
end

-- Full export of the current profile (+ module tables) as a string.
function SP:ExportCurrentProfile()
	return self:EncodeShare(self:BuildSharePayload({ includeExtras = true }))
end

-- Import a string. mode = "newProfile" (default) creates/switches to
-- `profileName`; "overwrite" writes into the current profile. Returns
-- (true, profileName) or (nil, errorMessage).
function SP:ImportShare(str, mode, profileName)
	local payload, err = self:DecodeShare(str)
	if not payload then return nil, err end
	if type(payload.profile) ~= "table" then return nil, "the setup code has no profile settings" end
	-- (3.0.9.8) a built-in preset hides no totem from the flyouts: Srumar's Layout hid Searing, so a new
	-- shaman who took it at first login had no fire totem to pick (three players' reports, 11-07). A
	-- code a player shares, or your own backup, keeps its list.
	if payload.preset then payload.profile.flyoutTotems = nil end

	self.shareImporting = true   -- (no theme migration of the half-written profile)
	if mode == "overwrite" then
		wipe(self.db.profile)
		for k, v in pairs(payload.profile) do self.db.profile[k] = CleanCopy(v) end
		profileName = self.db:GetCurrentProfile()
	else
		profileName = (profileName and strtrim(profileName) ~= "" and strtrim(profileName)) or "Imported"
		-- Unique-ify the name if it already exists.
		local existing = {}
		for _, n in ipairs(self.db:GetProfiles()) do existing[n] = true end
		local name, i = profileName, 2
		while existing[name] do name = profileName .. " " .. i; i = i + 1 end
		self.db:SetProfile(name)           -- creates and switches (lays out defaults)
		wipe(self.db.profile)
		for k, v in pairs(payload.profile) do self.db.profile[k] = CleanCopy(v) end
		profileName = name
	end
	-- the profile was wiped for the import: any default the string leaves out goes
	-- back in now (the database only fills them at load, and code reads them at once)
	FillDefaults(self.db.profile, self.db.defaults and self.db.defaults.profile)
	-- a string (or backup) made before 3.0 stored a shown caller panel as nothing;
	-- 3.0's default is icons only, so say "shown" or it would flip after a reload
	if payload.profile.raidCDButtonHideFrame == nil then self.db.profile.raidCDButtonHideFrame = false end

	-- Loose module tables. Most replace the importer's copy (that is the point
	-- of a shared setup); tables flagged in extraMerge only merge their keys, so
	-- e.g. a preset's caller-button position lands without wiping the importer's
	-- own raid-cooldown assignments.
	if payload.extras then
		local merge = payload.extraMerge or {}
		for name, tbl in pairs(payload.extras) do
			-- loadouts are the importer's own: a preset (shared by someone else) never
			-- replaces them, only a restore of your own backup does
			if payload.preset and name == "ShamanPower_TotemLoadouts" then
				-- skipped
			elseif IMPORTABLE[name] then   -- only ShamanPower's own tables: never any other global
				if merge[name] then
					if type(_G[name]) ~= "table" then _G[name] = {} end
					for k, v in pairs(tbl) do _G[name][k] = CleanCopy(v) end
				else
					_G[name] = CleanCopy(tbl)
				end
			end
		end
	end

	-- the code's saved themes (a full export carries them): each one becomes a theme here, a
	-- same-named one replaced; the imported profile's card refs follow them to their numbers here
	if type(payload.themes) == "table" and not payload.preset and self.ThemeTakeShared then
		local map = self:ThemeTakeShared(payload.themes)
		local th = self.db.profile.theme
		if type(th) == "table" then
			local function remap(card)
				local n = type(card) == "string" and tonumber(card:match("^mine:(%d+)$"))
				if n and map[n] then return "mine:" .. map[n] end
				return card
			end
			th.card = remap(th.card)
			if type(th.pending) == "table" then th.pending.card = remap(th.pending.card) end
		end
	end

	self.opt = self.db.profile
	self.shareImporting = nil
	-- Re-apply everything to the live UI now that the imported data is in
	-- place. OnProfileChanged rebuilds positions, layout, skin, opacity and
	-- pop-outs from the current profile; SetProfile above already ran it once
	-- against empty data, so run it again with the real data.
	if self.OnProfileChanged then self:OnProfileChanged() end
	-- OnProfileChanged only repositions the cooldown bar; fully rebuild its
	-- contents, scale, frame and progress bars so the imported look is exact.
	local function call(fn) if self[fn] then pcall(self[fn], self) end end
	call("UpdateCooldownBar")
	call("UpdateCooldownBarScale")
	call("UpdateCooldownBarFrame")
	call("UpdateCooldownBarProgressBars")
	call("UpdateCooldownBarOpacity")
	call("UpdateCooldownBarFlyoutEnabled")
	-- Totem bar appearance + mini bar.
	call("UpdateTotemBarFrame")
	call("UpdateMiniTotemBar")
	-- Modules whose settings live in their own SavedVariables.
	call("UpdateReactiveTotemAppearance")
	call("UpdateTremorReminderAppearance")
	call("UpdateAllReadyReminderAppearance")
	call("UpdateReadyReminders")
	call("TargetTrackerRefresh")
	call("UpdateSPRangeFrame")
	call("UpdateSPRangeBorder")
	call("UpdateLoadoutBar")
	local reg = LibStub and LibStub("AceConfigRegistry-3.0", true)
	if reg then reg:NotifyChange("ShamanPower") end
	if self.KeepProfileSetup then self:KeepProfileSetup() end   -- (3.0.9.16) what came in belongs to this profile
	return true, profileName
end

-- ---------------------------------------------------------------------------
-- Setup preset capture
-- Records the layout-relevant slice of the current profile so it can be baked
-- in as a built-in preset. Prints the string; also stashes it for the tools.
-- ---------------------------------------------------------------------------
-- The whole profile is captured (every setting/toggle/scale/colour/position);
-- the profile itself holds no per-player totem assignments (those live in the
-- ShamanPower_Assignments SavedVar, which the preset omits).
function SP:BuildPresetPayload()
	local payload = {
		v = 1,
		addon = "ShamanPower",
		preset = true,
		profile = CleanCopy(self.db.profile),
		extras = {},
	}
	for _, name in ipairs(PRESET_SVARS) do
		if _G[name] then payload.extras[name] = CleanCopy(_G[name]) end
	end
	local strip = PRESET_SVAR_STRIP.ShamanPower_RaidCooldowns
	if strip and _G["ShamanPower_RaidCooldowns"] then
		local keep = {}
		for k in pairs(strip) do
			if _G["ShamanPower_RaidCooldowns"][k] ~= nil then
				keep[k] = CleanCopy(_G["ShamanPower_RaidCooldowns"][k])
			end
		end
		payload.extras.ShamanPower_RaidCooldowns = keep
		payload.extraMerge = { ShamanPower_RaidCooldowns = true }
	end
	return payload
end

function SP:CaptureLayoutPreset()
	local str, err = self:EncodeShare(self:BuildPresetPayload())
	SP.capturedPreset = str
	if str then
		if SP.ShowExportDialog then
			SP:ShowExportDialog(str, "captured layout preset")
		else
			-- No UI available (Config module disabled): fall back to chat.
			print("|cff0070ddShamanPower|r: layout preset captured:")
			print(str)
		end
	else
		print("|cff0070ddShamanPower|r: could not capture the layout (" .. tostring(err or "unknown error") .. ").")
	end
	return str
end

SLASH_SHAMANPOWERPRESET1 = "/sppreset"
SlashCmdList["SHAMANPOWERPRESET"] = function(msg)
	msg = strtrim(msg or "")
	local cmd, rest = msg:match("^(%S+)%s*(.*)$")
	if cmd == "capture" then
		SP:CaptureLayoutPreset()
	elseif cmd == "apply" then
		local key = (rest and rest ~= "" and rest) or (SP.Presets and SP.Presets[1] and SP.Presets[1].key)
		local ok, res = SP:ApplyPreset(key, "newProfile")
		if ok then
			print("|cff0070ddShamanPower|r: applied preset into profile: " .. tostring(res))
		else
			print("|cff0070ddShamanPower|r: " .. tostring(res))
		end
	else
		print("|cff0070ddShamanPower|r: /sppreset capture — copy your layout as a setup code")
		print("|cff0070ddShamanPower|r: /sppreset apply [key] — apply a built-in preset (default: " .. (SP.Presets and SP.Presets[1] and SP.Presets[1].key or "none") .. ")")
	end
end

-- ---------------------------------------------------------------------------
-- (3.0.9.14) Profile by Spec (Profiles page): a profile picked for each spec. A change of spec puts its profile in
-- use, out of combat; picking one for the spec you're in puts it in use at once. Your spec is read as Ready
-- Reminders' Show For reads it (SP.ShareSpecIndex: the spell book on WoW: Forever, the talent points elsewhere),
-- never guessed from the setup's spec. Kept per character (db.char.specProfiles); a profile you pick yourself
-- stays until your spec changes. Woken by spell and talent events only.
-- ---------------------------------------------------------------------------
do
	local BY_INDEX = { "restoration", "enhancement", "elemental" }   -- SP.ShareSpecIndex: 1, 2, 3
	SP.SpecProfileKeys = { "elemental", "enhancement", "restoration" }   -- the page's order
	SP.SpecProfileNames = { elemental = "Elemental", enhancement = "Enhancement", restoration = "Restoration" }
	local ef = CreateFrame("Frame")
	local queued, waitKey = false, nil

	local function exists(name)
		for _, n in ipairs((SP.db:GetProfiles())) do if n == name then return true end end
		return false
	end
	function SP:SpecProfileFor(key)
		local c = SP.db and SP.db.char
		local name = c and type(c.specProfiles) == "table" and c.specProfiles[key] or nil
		if type(name) == "string" and exists(name) then return name end
		return nil
	end

	local function apply(name, key)
		SP.db:SetProfile(name)   -- OnProfileChanged rebuilds positions, layout, skin, opacity and pop-outs
		-- as an import does: the cooldown bar's contents and the totem bar's look, rebuilt whole
		for _, fn in ipairs({ "UpdateCooldownBar", "UpdateCooldownBarScale", "UpdateCooldownBarFrame",
			"UpdateCooldownBarProgressBars", "UpdateCooldownBarOpacity", "UpdateCooldownBarFlyoutEnabled",
			"UpdateTotemBarFrame", "UpdateMiniTotemBar" }) do
			if SP[fn] then pcall(SP[fn], SP) end
		end
		local reg = LibStub and LibStub("AceConfigRegistry-3.0", true)
		if reg then reg:NotifyChange("ShamanPower") end
		print("|cff0070ddShamanPower|r: " .. SP.SpecProfileNames[key] .. ", so profile '" .. name .. "' is in use.")
	end

	-- force: the spec whose profile was just picked (put in use now if it is yours)
	function SP:SpecProfileCheck(force)
		local c = SP.db and SP.db.char
		if not c then return end
		local key = BY_INDEX[SP.ShareSpecIndex and SP.ShareSpecIndex(true) or 0]
		if not key then return end   -- (the talents can't tell yet)
		if key == c.specProfileLast and key ~= force then return end
		local name = SP:SpecProfileFor(key)
		if name and name ~= SP.db:GetCurrentProfile() then
			if InCombatLockdown() then   -- (its bars can't move in a fight: right after it)
				waitKey = force or waitKey or true
				ef:RegisterEvent("PLAYER_REGEN_ENABLED")
				return
			end
			apply(name, key)
		end
		c.specProfileLast = key
	end
	function SP:SetSpecProfile(key, name)
		local c = SP.db and SP.db.char
		if not c then return end
		if type(c.specProfiles) ~= "table" then c.specProfiles = {} end
		c.specProfiles[key] = name
		if name then SP:SpecProfileCheck(key) end
	end

	ef:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_REGEN_ENABLED" then
			ef:UnregisterEvent("PLAYER_REGEN_ENABLED")
			local k = waitKey; waitKey = nil
			if k then SP:SpecProfileCheck(k ~= true and k or nil) end
			return
		end
		if queued then return end
		queued = true   -- (a respec sends several events: one look, a second later)
		C_Timer.After(1, function() queued = false; SP:SpecProfileCheck() end)
	end)
	for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "SPELLS_CHANGED", "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED",
		"ACTIVE_TALENT_GROUP_CHANGED" }) do
		pcall(ef.RegisterEvent, ef, e)
	end
end

-- ---------------------------------------------------------------------------
-- (3.0.9.16) A profile is the whole setup. Every setting ShamanPower saves outside the profile itself (each module's
-- own table: Ready Reminders, Reactive Totems, Range, Tremor, Expiring Alerts, Earth Shield Tracker, Target Tracker,
-- Raid Cooldowns, Loadouts, Auto Loadout Groups and the assignments; your themes; the Call of the Elements page the
-- bar is on and its picks) belongs to the profile it was set on. Switching profile (any way: the Profiles page,
-- Profile by Spec, an import, Copy From) puts the setup you leave away with its profile and brings the new
-- profile's back, so Restoration can have its Ready Reminders one way and Enhancement another. Before, only the
-- profile itself switched: an import's Ready Reminders stayed on every profile (the owner, 11-16). Kept account-wide
-- in db.global.profileSetups, by profile name. Only bookkeeping stays with the character or account: Profile by
-- Spec's own picks, the measured totem durations, what has been seen, backups, support saves, the error log.
-- ---------------------------------------------------------------------------
do
	local GLOBAL_KEYS = { "themes", "themesGone" }              -- db.global: your themes
	local CHAR_KEYS = { "callPage", "callKept", "callEarly" }   -- db.char: the bar's Call and its picks
	local busy = false

	local function store()
		local g = SP.db.global
		if type(g.profileSetups) ~= "table" then g.profileSetups = {} end
		return g.profileSetups
	end
	-- the setup on screen now, copied
	local function capture()
		local t = { sv = {}, global = {}, char = {} }
		for _, name in ipairs(EXTRA_SVARS) do
			if type(_G[name]) == "table" then t.sv[name] = CleanCopy(_G[name]) end
		end
		local g, c = SP.db.global, SP.db.char
		for _, k in ipairs(GLOBAL_KEYS) do t.global[k] = CleanCopy(g[k]) end
		for _, k in ipairs(CHAR_KEYS) do t.char[k] = CleanCopy(c[k]) end
		return t
	end
	-- a kept setup put back in place (each table refilled where it is: whatever holds it sees the new one)
	local function putBack(t)
		for _, name in ipairs(EXTRA_SVARS) do
			local saved = t.sv and t.sv[name]
			if type(saved) == "table" then
				local copy = CleanCopy(saved)
				local live = _G[name]
				if type(live) == "table" then
					wipe(live)
					for k, v in pairs(copy) do live[k] = v end
				else
					_G[name] = copy
				end
			end
		end
		local g, c = SP.db.global, SP.db.char
		for _, k in ipairs(GLOBAL_KEYS) do g[k] = CleanCopy(t.global and t.global[k]) end
		for _, k in ipairs(CHAR_KEYS) do c[k] = CleanCopy(t.char and t.char[k]) end
	end
	-- everything drawn again from the setup now in place: all that answers a profile change (the bars, looks,
	-- themes, loadouts, Calls), then the modules with their own tables (as an import does)
	local function redraw(db)
		busy = true
		pcall(db.callbacks.Fire, db.callbacks, "OnProfileChanged", db, db:GetCurrentProfile())
		busy = false
		for _, fn in ipairs({ "UpdateCooldownBar", "UpdateCooldownBarScale", "UpdateCooldownBarFrame",
			"UpdateCooldownBarProgressBars", "UpdateCooldownBarOpacity", "UpdateCooldownBarFlyoutEnabled",
			"UpdateTotemBarFrame", "UpdateMiniTotemBar", "UpdateReactiveTotemAppearance", "UpdateTremorReminderAppearance",
			"UpdateAllReadyReminderAppearance", "UpdateReadyReminders", "TargetTrackerRefresh", "UpdateSPRangeFrame",
			"UpdateSPRangeBorder", "UpdateLoadoutBar", "UpdateWindfuryProcAppearance", "UpdateHealingTrackerAppearance" }) do
			if SP[fn] then pcall(SP[fn], SP) end
		end
		local reg = LibStub and LibStub("AceConfigRegistry-3.0", true)
		if reg then reg:NotifyChange("ShamanPower") end
	end

	-- the setup on screen now, kept as this profile's (an import calls it; so does logging out), and nothing of it
	-- left off the screen (an import's spots were saved on someone else's screen)
	function SP:KeepProfileSetup()
		if not (SP.db and SP.db.global) then return end
		store()[SP.db:GetCurrentProfile()] = capture()
		if SP.KeepOnScreen then SP:KeepOnScreen() end
	end
	function SP:ProfileSetupOf(name) return SP.db and SP.db.global and type(SP.db.global.profileSetups) == "table"
		and SP.db.global.profileSetups[name] or nil end

	local function install()
		local db = SP.db
		if not db or db.spSetupWrapped then return end
		db.spSetupWrapped = true
		local setProfile, copyProfile = db.SetProfile, db.CopyProfile
		db.SetProfile = function(self, name)
			local from = self:GetCurrentProfile()
			if busy or name == from then return setProfile(self, name) end
			store()[from] = capture()                      -- the setup you leave, kept with its profile
			local r = setProfile(self, name)               -- the profile itself (its OnProfileChanged runs)
			local t = store()[name]
			if t then putBack(t); redraw(self) end         -- and the rest of its setup, as it was left
			if SP.KeepOnScreen then SP:KeepOnScreen() end
			return r                                       -- (a profile never seen with this: keeps what is on screen)
		end
		db.CopyProfile = function(self, name, silent)
			local r = copyProfile(self, name, silent)      -- Copy From: that profile's settings into this one
			local t = store()[name]
			if t then putBack(t); redraw(self) end         -- and the rest of its setup with them
			store()[self:GetCurrentProfile()] = capture()
			if SP.KeepOnScreen then SP:KeepOnScreen() end
			return r
		end
	end
	local ev = CreateFrame("Frame")

	-- (3.0.9.17) Logging in: the profile in use brings its own whole setup back, as switching to it does. Before, each
	-- table loaded as it was last saved: on Anniversary Ready Reminders and most modules' tables are the whole
	-- account's, so another character's last setup came with them (and at logout was kept as this profile's). The
	-- usual login (the same character, or a /reload) finds it just as it was left: nothing is touched then.
	local function same(a, b)
		if a == b then return true end
		if type(a) ~= "table" or type(b) ~= "table" then return false end
		for k, v in pairs(a) do if not same(v, b[k]) then return false end end
		for k in pairs(b) do if a[k] == nil then return false end end
		return true
	end
	local function redrawNow()
		if InCombatLockdown() then ev:RegisterEvent("PLAYER_REGEN_ENABLED") return end   -- (the bars can't move in a fight)
		redraw(SP.db)
	end
	function SP:ProfileSetupLogin()
		if not (SP.db and SP.db.global) then return end
		local t = store()[SP.db:GetCurrentProfile()]
		if type(t) ~= "table" or same(capture(), t) then return end
		putBack(t)                    -- (before the modules build from their tables)
		C_Timer.After(0, redrawNow)   -- and everything drawn from it again once they are all up
	end

	ev:RegisterEvent("PLAYER_LOGIN")
	ev:RegisterEvent("PLAYER_LOGOUT")
	ev:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_LOGIN" then install(); SP:ProfileSetupLogin()
		elseif event == "PLAYER_REGEN_ENABLED" then ev:UnregisterEvent("PLAYER_REGEN_ENABLED"); redrawNow()
		elseif SP.db and SP.db.spSetupWrapped then SP:KeepProfileSetup() end   -- (logging out, or a /reload)
	end)
	install()
end

-- ---------------------------------------------------------------------------
-- (3.0.9.16) Nothing left off the screen after a profile switch or an import: a spot saved on another screen (a
-- code someone made at another resolution or UI scale) can land past its edge. The places the game does not keep
-- on the screen itself (the totem bar, the cooldown bar on its own, Tremor Reminder, each shield, the Raid
-- Cooldowns caller buttons; everything else is clamped to the screen) are looked at once they are drawn. One more
-- than half off the screen is moved fully onto it and its spot saved the way a drag saves it. A spot only a little
-- past an edge (put there by hand) is left alone. Never in a fight (they hold the bar's buttons): after it.
-- ---------------------------------------------------------------------------
do
	local waiting = false
	local function uiRect(f)
		if not (f and f.GetRect and f:IsShown()) then return nil end
		local l, b, w, h = f:GetRect()
		if not (l and b and w and h) or w <= 1 or h <= 1 then return nil end
		local k = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
		return l * k, b * k, (l + w) * k, (b + h) * k
	end
	-- each place: its frame that holds the spot, the frames that show it, and how its spot is saved
	local function places()
		local out = {}
		local root = _G.ShamanPowerFrame
		if root then
			local parts = { _G.ShamanPowerAuto }
			for e = 1, 4 do parts[#parts + 1] = SP.totemButtons and SP.totemButtons[e] end
			out[#out + 1] = { root = root, parts = parts, save = function() SP:SaveFramePosition(root) end }
		end
		local bar = SP.cooldownBar
		local rel = bar and bar:GetNumPoints() > 0 and select(2, bar:GetPoint(1))
		if bar and (rel == nil or rel == UIParent) then   -- (on its own; fixed to the totem bar it moves with it)
			out[#out + 1] = { root = bar, parts = { bar }, save = function()
				SP.opt.cooldownBarPosition = SP:SavePositionRecord(bar)
				SP.opt.cooldownBarPoint, SP.opt.cooldownBarRelPoint = nil, nil
				SP.opt.cooldownBarPosX, SP.opt.cooldownBarPosY = nil, nil
			end }
		end
		local function byDrag(f)   -- its own drop saves its spot from where it is
			if f then out[#out + 1] = { root = f, parts = { f }, save = function()
				local fn = f:GetScript("OnDragStop")
				if fn then pcall(fn, f) end
			end } end
		end
		byDrag(_G.ShamanPowerTremorReminderFrame)
		for _, f in pairs(SP.shieldChargeFrames or {}) do byDrag(f) end
		byDrag(SP.callerButtonFrame)
		return out
	end
	local function pull()
		local W, H = UIParent:GetWidth(), UIParent:GetHeight()
		for _, pl in ipairs(places()) do
			local l, b, r, t
			for _, f in ipairs(pl.parts) do
				local fl, fb, fr, ft = uiRect(f)
				if fl then
					l, b = math.min(l or fl, fl), math.min(b or fb, fb)
					r, t = math.max(r or fr, fr), math.max(t or ft, ft)
				end
			end
			if l and pl.root:GetNumPoints() > 0 then
				local area = (r - l) * (t - b)
				local seen = math.max(0, math.min(r, W) - math.max(l, 0)) * math.max(0, math.min(t, H) - math.max(b, 0))
				if area > 0 and seen < area * 0.5 then
					local dx = (l < 0 and -l) or (r > W and math.max(W - r, -l)) or 0
					local dy = (b < 0 and -b) or (t > H and math.max(H - t, -b)) or 0
					local k = pl.root:GetEffectiveScale() / UIParent:GetEffectiveScale()
					local p, rel, rp, x, y = pl.root:GetPoint(1)
					pl.root:ClearAllPoints()
					pl.root:SetPoint(p, rel, rp, (x or 0) + dx / k, (y or 0) + dy / k)
					pcall(pl.save)
				end
			end
		end
	end
	local ev = CreateFrame("Frame")
	ev:SetScript("OnEvent", function(self)
		self:UnregisterEvent("PLAYER_REGEN_ENABLED")
		C_Timer.After(0.5, function() waiting = false; SP:KeepOnScreen() end)
	end)
	function SP:KeepOnScreen()
		if waiting then return end
		waiting = true
		if InCombatLockdown() then ev:RegisterEvent("PLAYER_REGEN_ENABLED") return end
		C_Timer.After(0.5, function()   -- (once the new setup is drawn and laid out)
			if InCombatLockdown() then ev:RegisterEvent("PLAYER_REGEN_ENABLED") return end
			waiting = false
			pull()
		end)
	end
end
