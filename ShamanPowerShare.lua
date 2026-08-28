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
	"ShamanPower_ESTracker",
	"ShamanPowerExpiringAlertsDB",
	"ShamanPower_RaidCooldowns",
	"ShamanPower_Assignments",
	"ShamanPower_EarthShieldAssignments",
	"ShamanPower_TwistAssignments",
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
}
local PRESET_SVAR_STRIP = {
	-- keep only these keys from a table (drop everything else)
	ShamanPower_RaidCooldowns = { callerButtonPos = true },
}

-- Deep copy that skips functions and metatables (safe to serialize).
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
	end
	return payload
end

function SP:EncodeShare(payload)
	if not (Serializer and Deflate) then
		return nil, "serialization libraries are missing"
	end
	local ok, serialized = pcall(function() return Serializer:Serialize(payload) end)
	if not ok or not serialized then return nil, "could not serialize" end
	local compressed = Deflate:CompressDeflate(serialized, { level = 9 })
	if not compressed then return nil, "could not compress" end
	return PREFIX .. Deflate:EncodeForPrint(compressed)
end

function SP:DecodeShare(str)
	if not (Serializer and Deflate) then return nil, "serialization libraries are missing" end
	if type(str) ~= "string" then return nil, "empty string" end
	str = strtrim(str)
	if str:sub(1, #PREFIX) ~= PREFIX then return nil, "not a ShamanPower string" end
	local body = str:sub(#PREFIX + 1)
	local compressed = Deflate:DecodeForPrint(body)
	if not compressed then return nil, "corrupt string" end
	local serialized = Deflate:DecompressDeflate(compressed)
	if not serialized then return nil, "corrupt string" end
	local ok, payload = Serializer:Deserialize(serialized)
	if not ok or type(payload) ~= "table" then return nil, "could not read string" end
	if payload.addon ~= "ShamanPower" then return nil, "string is for a different addon" end
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
	if type(payload.profile) ~= "table" then return nil, "string has no profile data" end

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

	-- Loose module tables. Most replace the importer's copy (that is the point
	-- of a shared setup); tables flagged in extraMerge only merge their keys, so
	-- e.g. a preset's caller-button position lands without wiping the importer's
	-- own raid-cooldown assignments.
	if payload.extras then
		local merge = payload.extraMerge or {}
		for name, tbl in pairs(payload.extras) do
			if _G[name] ~= nil or name:match("^ShamanPower") then
				if merge[name] then
					if type(_G[name]) ~= "table" then _G[name] = {} end
					for k, v in pairs(tbl) do _G[name][k] = CleanCopy(v) end
				else
					_G[name] = CleanCopy(tbl)
				end
			end
		end
	end

	self.opt = self.db.profile
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
	call("UpdateSPRangeFrame")
	call("UpdateSPRangeBorder")
	call("UpdateLoadoutBar")
	local reg = LibStub and LibStub("AceConfigRegistry-3.0", true)
	if reg then reg:NotifyChange("ShamanPower") end
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
	local str = self:EncodeShare(self:BuildPresetPayload())
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
		print("|cff0070ddShamanPower|r: capture failed (serialization libraries missing).")
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
		print("|cff0070ddShamanPower|r: /sppreset capture — capture your layout as a string")
		print("|cff0070ddShamanPower|r: /sppreset apply [key] — apply a built-in preset (default: " .. (SP.Presets and SP.Presets[1] and SP.Presets[1].key or "none") .. ")")
	end
end
