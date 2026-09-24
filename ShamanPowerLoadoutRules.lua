-- ============================================================================
-- Loadout auto-switch: pick a saved totem loadout by the kind of content you
-- are in (raid, dungeon, battleground, open world), by zone, by the mob you
-- target (BWL: target Firemaw -> the Fire Resistance loadout, like an
-- equipment manager), or by a boss encounter starting.
--
-- All opt-in (master toggle off by default). A loadout rewrites assignments
-- and secure button attributes, so nothing switches in combat: a switch that
-- comes up in combat waits for PLAYER_REGEN_ENABLED and happens only if it
-- still applies then. Event-driven only: no tickers, nothing runs while idle,
-- and the target event is only listened to while a target rule exists.
--
-- WoW: Forever: a zone or encounter rule may also request a raid resistance
-- totem (ShamanPowerResist.lua). The request ends when the boss dies (a wipe
-- keeps it for the next pull) or when you leave the zone.
--
-- Settings live in the AceDB profile (opt.loadoutRules). Rules point at a
-- loadout by a stable id stored on the loadout itself (lo.uid), because the
-- loadout list is positional and deleting one shifts the rest.
-- ============================================================================

local SP = ShamanPower
if not SP then return end
if select(2, UnitClass("player")) ~= "SHAMAN" then return end

local FOREVER = (WOW_PROJECT_ID == WOW_PROJECT_MAINLINE)
local MAX_RULES = 20

local function DB()
	local o = SP.opt
	if not o then return nil end
	o.loadoutRules = o.loadoutRules or {}
	local d = o.loadoutRules
	d.content = d.content or {}
	d.rules = d.rules or {}
	return d
end

-- ---------------------------------------------------------------------------
-- Loadout identity
-- ---------------------------------------------------------------------------
local function EnsureUID(lo)
	if not lo.uid then
		lo.uid = string.format("%x%04x", time(), math.random(0, 65535))
	end
	return lo.uid
end

local function IndexOfUID(uid)
	if not uid or not ShamanPower_TotemLoadouts then return nil end
	for i, lo in ipairs(ShamanPower_TotemLoadouts) do
		if lo.uid == uid then return i end
	end
	return nil
end

local function LoadoutName(index)
	local lo = ShamanPower_TotemLoadouts and ShamanPower_TotemLoadouts[index]
	return lo and (lo.name or ("Loadout " .. index)) or "?"
end

local function LoadoutValues()
	local v = { __none = "None" }
	for i, lo in ipairs(ShamanPower_TotemLoadouts or {}) do
		v[EnsureUID(lo)] = lo.name or ("Loadout " .. i)
	end
	return v
end

local function LoadoutSorting()
	local order = { "__none" }
	for _, lo in ipairs(ShamanPower_TotemLoadouts or {}) do order[#order + 1] = EnsureUID(lo) end
	return order
end

-- ---------------------------------------------------------------------------
-- Where are we
-- ---------------------------------------------------------------------------
local function ContentBucket()
	local inInstance, kind = IsInInstance()
	if not inInstance then return "none" end
	if kind == "raid" then return "raid" end
	if kind == "pvp" or kind == "arena" then return "pvp" end
	if kind == "party" or kind == "scenario" then return "party" end
	return "none"
end

local function Lower(s)
	if type(s) ~= "string" then return "" end
	return strtrim(s):lower()
end

-- A rule's zone matches the real zone or the subzone (case-insensitive); an
-- empty rule zone matches everywhere.
local function ZoneMatches(ruleZone)
	local want = Lower(ruleZone)
	if want == "" then return true end
	return Lower(GetRealZoneText()) == want or Lower(GetSubZoneText()) == want
end

-- ---------------------------------------------------------------------------
-- Switching
-- ---------------------------------------------------------------------------
local pending   -- { uid, reason, valid = function() ... end } waiting for combat to end

local function Switch(uid, reason)
	local index = IndexOfUID(uid)
	if not index then return end
	if SP.opt.activeLoadout == index then return end   -- already there: say nothing
	SP:ApplyLoadout(index, true)
	local d = DB()
	if d and d.announce ~= false then
		print("|cff0070ddShamanPower|r: switched to loadout " .. LoadoutName(index) .. (reason and (" (" .. reason .. ")") or "") .. ".")
	end
end

-- valid: called again after combat; the switch only happens if it still returns true.
local function Request(uid, reason, valid)
	if not uid or uid == "__none" then return end
	if InCombatLockdown() then
		pending = { uid = uid, reason = reason, valid = valid }
		return
	end
	pending = nil
	Switch(uid, reason)
end

-- ---------------------------------------------------------------------------
-- Raid resistance requests from rules (Forever). Only a request a rule made is
-- ended by the rules; one the raid made by hand is left alone.
-- ---------------------------------------------------------------------------
local RESIST_NAMES = { fire = "Fire Resistance", frost = "Frost Resistance", nature = "Nature Resistance" }
local heldResist = {}     -- key -> "zone" | "encounter"
local encounterZone       -- where the encounter request was made

local function HoldResist(key, why)
	if not (FOREVER and key and RESIST_NAMES[key] and SP.SetResistNeeded) then return end
	if heldResist[key] or SP:IsResistNeeded(key) then return end
	if SP:SetResistNeeded(key, true) then heldResist[key] = why end
end

local function ReleaseResist(why)
	for key, w in pairs(heldResist) do
		if w == why then
			heldResist[key] = nil
			if SP.IsResistNeeded and SP:IsResistNeeded(key) then SP:SetResistNeeded(key, false) end
		end
	end
	if why == "encounter" then encounterZone = nil end
end

-- ---------------------------------------------------------------------------
-- Triggers
-- ---------------------------------------------------------------------------
local lastBucket
local returnTo   -- loadout uid active before entering an instance (restorePrevious)

local function ActiveUID()
	local i = SP.opt and SP.opt.activeLoadout
	local lo = i and ShamanPower_TotemLoadouts and ShamanPower_TotemLoadouts[i]
	return lo and EnsureUID(lo) or nil
end

-- Zone rules: a rule with a zone and no target or encounter applies on ARRIVAL
-- (the matching rule changes), never again while you stay: a subzone change
-- inside the same place must not undo a target rule's switch.
local lastZoneRule
local function CheckZoneRules()
	local d = DB()
	local match
	for i, r in ipairs(d.rules) do
		if Lower(r.zone) ~= "" and Lower(r.target) == "" and Lower(r.encounter) == "" and (r.loadout or r.resist) and ZoneMatches(r.zone) then
			match = i
			break
		end
	end
	if match ~= lastZoneRule then
		lastZoneRule = match
		ReleaseResist("zone")
		if match then
			local r = d.rules[match]
			local zone = r.zone
			if r.loadout then Request(r.loadout, zone, function() return ZoneMatches(zone) end) end
			HoldResist(r.resist, "zone")
		end
	end
	return match ~= nil
end

local function CheckContent()
	local d = DB()
	if not (d and d.enabled) then return end
	-- an encounter's resistance request ends when you leave its zone
	if encounterZone and GetRealZoneText() ~= encounterZone then ReleaseResist("encounter") end
	local bucket = ContentBucket()
	local changed = bucket ~= lastBucket
	local previous = lastBucket
	lastBucket = bucket
	if CheckZoneRules() then return end   -- a zone rule is more specific than the content type
	-- a login or /reload in the open world is not "arriving" anywhere: keep the loadout you had
	if previous == nil and bucket == "none" then return end
	if not changed then return end
	local labels = { raid = "raid", party = "dungeon", pvp = "battleground", none = "open world" }
	local stillThere = function() return ContentBucket() == bucket end
	if bucket ~= "none" then
		if previous == "none" or previous == nil then returnTo = ActiveUID() end
		Request(d.content[bucket], labels[bucket], stillThere)
	else
		if d.restorePrevious and returnTo then
			Request(returnTo, "left the instance", stillThere)
		else
			Request(d.content.none, labels.none, stillThere)
		end
		returnTo = nil
	end
end

-- Forever: NPC identity is secret on instanced maps; never read or compare it there.
local function IdentitySecret(unit)
	if C_Secrets and C_Secrets.ShouldUnitIdentityBeSecret then
		local ok, v = pcall(C_Secrets.ShouldUnitIdentityBeSecret, unit)
		if ok and v == true then return true end
	end
	if issecretvalue then
		local name = UnitName(unit)
		if issecretvalue(name) then return true end
	end
	return false
end

local function CheckTarget()
	local d = DB()
	if not (d and d.enabled) or not UnitExists("target") then return end
	if IdentitySecret("target") then return end
	local name = Lower(UnitName("target"))
	if name == "" then return end
	for _, r in ipairs(d.rules) do
		local want = Lower(r.target)
		if want ~= "" and want == name and r.loadout and ZoneMatches(r.zone) then
			local display = r.target
			Request(r.loadout, display, function()
				return UnitExists("target") and not IdentitySecret("target") and Lower(UnitName("target")) == want
			end)
			return
		end
	end
end

local function CheckEncounter(encounterName)
	local d = DB()
	if not (d and d.enabled) then return end
	if type(encounterName) ~= "string" or (issecretvalue and issecretvalue(encounterName)) then return end
	local name = Lower(encounterName)
	for _, r in ipairs(d.rules) do
		if Lower(r.encounter) ~= "" and Lower(r.encounter) == name and (r.loadout or r.resist) and ZoneMatches(r.zone) then
			-- ENCOUNTER_START comes with the pull (combat): this lands when the
			-- fight ends, ready for the next attempt, as long as you are still there.
			local zone = GetRealZoneText()
			if r.loadout then Request(r.loadout, r.encounter, function() return GetRealZoneText() == zone end) end
			if r.resist then
				HoldResist(r.resist, "encounter")
				if heldResist[r.resist] == "encounter" then encounterZone = zone end
			end
			return
		end
	end
end

-- ---------------------------------------------------------------------------
-- Events: registered only while the feature is on (the target event only while a
-- target rule exists), so a player who never turns this on pays nothing.
-- ---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
if SPCompat and SPCompat.StressRegister then SPCompat.StressRegister(frame, "Loadout Auto-Switch") end

local function HasRule(field)
	local d = DB()
	for _, r in ipairs(d and d.rules or {}) do
		-- target rules only switch loadouts (a resistance request needs encounter or zone)
		if Lower(r[field]) ~= "" and (r.loadout or (r.resist and field ~= "target")) then return true end
	end
	return false
end

function SP:UpdateLoadoutRuleEvents()
	frame:UnregisterAllEvents()
	frame:RegisterEvent("PLAYER_LOGIN")
	local d = DB()
	if not (d and d.enabled) then
		pending = nil
		ReleaseResist("zone")
		ReleaseResist("encounter")
		return
	end
	frame:RegisterEvent("PLAYER_ENTERING_WORLD")
	frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
	frame:RegisterEvent("ZONE_CHANGED")
	frame:RegisterEvent("ZONE_CHANGED_INDOORS")
	frame:RegisterEvent("PLAYER_REGEN_ENABLED")
	if HasRule("target") then frame:RegisterEvent("PLAYER_TARGET_CHANGED") end
	if HasRule("encounter") then
		pcall(frame.RegisterEvent, frame, "ENCOUNTER_START")
		if FOREVER then pcall(frame.RegisterEvent, frame, "ENCOUNTER_END") end
	end
end

frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, event, ...)
	if event == "PLAYER_LOGIN" then
		if SP.db and SP.db.RegisterCallback then
			-- own key: registering with SP itself would replace the core's OnProfileChanged
			local key = {}
			local function reload()
				lastBucket, returnTo, pending, lastZoneRule = nil, nil, nil, nil
				SP:UpdateLoadoutRuleEvents()
				if SP.RebuildLoadoutRuleArgs then SP.RebuildLoadoutRuleArgs() end
			end
			SP.db.RegisterCallback(key, "OnProfileChanged", reload)
			SP.db.RegisterCallback(key, "OnProfileCopied", reload)
			SP.db.RegisterCallback(key, "OnProfileReset", reload)
		end
		SP:UpdateLoadoutRuleEvents()
	elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
		CheckContent()
	elseif event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" then
		local d = DB()
		if d and d.enabled then CheckZoneRules() end
	elseif event == "PLAYER_TARGET_CHANGED" then
		CheckTarget()
	elseif event == "ENCOUNTER_START" then
		local _, encounterName = ...
		CheckEncounter(encounterName)
	elseif event == "ENCOUNTER_END" then
		-- a kill ends the rule's resistance request; a wipe keeps it for the next pull
		local success = select(5, ...)
		if not (issecretvalue and issecretvalue(success)) and success == 1 then ReleaseResist("encounter") end
	elseif event == "PLAYER_REGEN_ENABLED" then
		local p = pending
		pending = nil
		if p then
			local ok, still = pcall(p.valid)
			if ok and still then Switch(p.uid, p.reason) end
		end
	end
end)

-- ---------------------------------------------------------------------------
-- Settings: Totem Bar > Auto-Switch (group buttons.loadoutrules_section)
-- ---------------------------------------------------------------------------
local ruleArgs = {}

local function Notify()
	local reg = LibStub and LibStub("AceConfigRegistry-3.0", true)
	if reg then reg:NotifyChange("ShamanPower") end
end

local function Disabled()
	local d = DB()
	return not (d and d.enabled) or SP.opt.enabled == false
end

local RebuildRuleArgs

local function ContentSelect(order, key, name, desc)
	return {
		order = order, type = "select", name = name, desc = desc, width = 1.5,
		disabled = Disabled,
		values = LoadoutValues, sorting = LoadoutSorting,
		get = function() local d = DB(); return (d and IndexOfUID(d.content[key]) and d.content[key]) or "__none" end,
		set = function(_, v) local d = DB(); d.content[key] = (v ~= "__none") and v or nil end,
	}
end

local STATIC = {
	desc = {
		order = 0, type = "description", width = "full",
		name = "Switch totem loadouts for you: by the kind of content you are in, by zone, by the mob you target, or by a boss encounter starting."
			.. " Nothing switches in combat; a switch that comes up in a fight happens as soon as it ends, if it still applies."
			.. " Loadouts are made on the Loadouts tab.",
	},
	enabled = {
		order = 1, type = "toggle", width = "full", name = "Switch Loadouts Automatically",
		desc = "Turn on the content, zone, target and encounter switching below. Off by default.",
		disabled = function() return SP.opt.enabled == false end,
		get = function() local d = DB(); return d and d.enabled == true or false end,
		set = function(_, v) local d = DB(); d.enabled = v and true or nil; SP:UpdateLoadoutRuleEvents(); if v then CheckContent() end end,
	},
	announce = {
		order = 2, type = "toggle", width = "full", name = "Say in Chat When It Switches",
		desc = "A line in your own chat window, e.g. \"switched to loadout Fire Resist (Firemaw)\". Only you see it.",
		disabled = Disabled,
		get = function() local d = DB(); return not d or d.announce ~= false end,
		set = function(_, v)
			local d = DB()
			if v then d.announce = nil else d.announce = false end
		end,
	},
	content_header = { order = 10, type = "header", name = "By Content" },
	content_raid = ContentSelect(11, "raid", "Raid", "The loadout to switch to when you enter a raid."),
	content_party = ContentSelect(12, "party", "Dungeon", "The loadout to switch to when you enter a dungeon."),
	content_pvp = ContentSelect(13, "pvp", "Battleground / Arena", "The loadout to switch to when you enter a battleground or arena."),
	content_none = ContentSelect(14, "none", "Open World", "The loadout to switch to when you leave an instance (unless the option below takes you back to the one you had)."),
	restore = {
		order = 15, type = "toggle", width = "full", name = "On Leaving an Instance, Go Back to the Loadout I Had Before",
		desc = "Instead of the Open World choice, return to whatever loadout was active when you went in.",
		disabled = Disabled,
		get = function() local d = DB(); return d and d.restorePrevious == true or false end,
		set = function(_, v) local d = DB(); d.restorePrevious = v and true or nil end,
	},
	rules_header = { order = 20, type = "header", name = "Rules" },
	rules_desc = {
		order = 21, type = "description", width = "full",
		name = "Each rule switches to its loadout when it matches. Zone matches the zone or subzone name (e.g. Blackwing Lair); leave it empty for anywhere."
			.. " With a Target, the rule fires when you target a mob of exactly that name (e.g. Firemaw), so target the boss before the pull."
			.. " With a Boss Encounter, it fires when that encounter starts; the switch lands when the fight ends, ready for the next attempt."
			.. " A rule with only a Zone fires when you arrive there.",
	},
	resist_desc = {
		order = 21.5, type = "description", width = "full",
		hidden = function() return not (FOREVER and SP.RESIST_REQUESTS) end,
		name = "A zone or encounter rule can also ask the raid for a resistance totem (it needs no loadout for that). The request ends when the boss dies (a wipe keeps it for the next pull) or when you leave the zone.",
	},
	forever_note = {
		order = 22, type = "description", width = "full",
		hidden = function() return not FOREVER end,
		name = "|cffffa040Inside dungeons and raids the game hides mob names, so target rules only work in the open world there; zone and content rules still work.|r",
	},
	add_rule = {
		order = 999, type = "execute", width = "full", name = "Add Rule",
		disabled = function() local d = DB(); return Disabled() or (d and #d.rules >= MAX_RULES) end,
		func = function()
			local d = DB()
			if #d.rules >= MAX_RULES then return end
			d.rules[#d.rules + 1] = {}
			RebuildRuleArgs()
			Notify()
		end,
	},
}

RebuildRuleArgs = function()
	wipe(ruleArgs)
	for k, v in pairs(STATIC) do ruleArgs[k] = v end
	local d = DB()
	for i = 1, (d and #d.rules or 0) do
		local idx = i
		local base = 100 + i * 10
		local function rule() local dd = DB(); return dd and dd.rules[idx] end
		ruleArgs["rule_head_" .. i] = {
			order = base, type = "description", width = "full", fontSize = "medium",
			name = function()
				local r = rule()
				local lo = r and IndexOfUID(r.loadout)
				local text = "|cffffd200Rule " .. idx .. "|r"
				if lo then
					text = text .. ": " .. LoadoutName(lo)
				elseif not (r and r.resist) then
					text = text .. " (no loadout picked yet)"
				end
				if r and r.resist and RESIST_NAMES[r.resist] then
					text = text .. (lo and " + " or ": ") .. "request " .. RESIST_NAMES[r.resist]
				end
				return text
			end,
		}
		ruleArgs["rule_loadout_" .. i] = {
			order = base + 1, type = "select", name = "Loadout", width = 1.5,
			disabled = Disabled, values = LoadoutValues, sorting = LoadoutSorting,
			get = function() local r = rule(); return (r and IndexOfUID(r.loadout) and r.loadout) or "__none" end,
			set = function(_, v) local r = rule(); if r then r.loadout = (v ~= "__none") and v or nil end; SP:UpdateLoadoutRuleEvents() end,
		}
		ruleArgs["rule_zone_" .. i] = {
			order = base + 2, type = "input", name = "Zone (optional)", width = 1.5,
			desc = "Zone or subzone name, exactly as the game shows it (not case sensitive). Empty = anywhere.",
			disabled = Disabled,
			get = function() local r = rule(); return r and r.zone or "" end,
			set = function(_, v) local r = rule(); if r then r.zone = (strtrim(v or "") ~= "") and strtrim(v) or nil end end,
		}
		ruleArgs["rule_target_" .. i] = {
			order = base + 3, type = "input", name = "Target (mob name)", width = 1.5,
			desc = "Switch when you target a mob with exactly this name (not case sensitive).",
			disabled = Disabled,
			get = function() local r = rule(); return r and r.target or "" end,
			set = function(_, v) local r = rule(); if r then r.target = (strtrim(v or "") ~= "") and strtrim(v) or nil end; SP:UpdateLoadoutRuleEvents() end,
		}
		ruleArgs["rule_encounter_" .. i] = {
			order = base + 4, type = "input", name = "Boss Encounter (optional)", width = 1.5,
			desc = "Switch when this boss encounter starts (the name the game uses for the fight). The switch lands when the fight ends, ready for the next pull.",
			disabled = Disabled,
			get = function() local r = rule(); return r and r.encounter or "" end,
			set = function(_, v) local r = rule(); if r then r.encounter = (strtrim(v or "") ~= "") and strtrim(v) or nil end; SP:UpdateLoadoutRuleEvents() end,
		}
		ruleArgs["rule_resist_" .. i] = {
			order = base + 4.5, type = "select", name = "Also Request Resistance", width = 1.5,
			desc = "Ask the raid for this resistance totem when the rule fires (zone or encounter rules; target rules do not request it)."
				.. " One shaman is picked and asked; it ends when the boss dies (a wipe keeps it) or when you leave the zone.",
			hidden = function() return not (FOREVER and SP.RESIST_REQUESTS) end,
			disabled = Disabled,
			values = { none = "None", fire = "Fire Resistance", frost = "Frost Resistance", nature = "Nature Resistance" },
			sorting = { "none", "fire", "frost", "nature" },
			get = function() local r = rule(); return (r and r.resist) or "none" end,
			set = function(_, v)
				local r = rule()
				if r then
					if v == "none" then r.resist = nil else r.resist = v end
				end
				SP:UpdateLoadoutRuleEvents()
			end,
		}
		ruleArgs["rule_remove_" .. i] = {
			order = base + 5, type = "execute", name = "Remove Rule " .. i, width = 1.5,
			disabled = Disabled,
			func = function()
				local dd = DB()
				if dd and dd.rules[idx] then tremove(dd.rules, idx) end
				RebuildRuleArgs()
				SP:UpdateLoadoutRuleEvents()
				Notify()
			end,
		}
	end
end

if SP.options and SP.options.args and SP.options.args.buttons and SP.options.args.buttons.args then
	SP.options.args.buttons.args.loadoutrules_section = {
		order = 3.71, type = "group", name = "Loadout Auto-Switch",
		disabled = function() return SP.opt and SP.opt.enabled == false end,
		args = ruleArgs,
	}
	for k, v in pairs(STATIC) do ruleArgs[k] = v end
	-- the rule rows come from the profile, which exists after login
	local f = CreateFrame("Frame")
	f:RegisterEvent("PLAYER_LOGIN")
	f:SetScript("OnEvent", function() RebuildRuleArgs() end)
	SP.RebuildLoadoutRuleArgs = function() RebuildRuleArgs(); Notify() end
end
