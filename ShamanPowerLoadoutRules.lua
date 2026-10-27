-- ============================================================================
-- Auto Loadout Groups (3.0.9.5, sheet A79). A group is a zone (The Molten Core: typed, or
-- Use Current Zone) or a kind of place (Any Raid, Any Dungeon, Any Battleground or Arena,
-- Outside). Loadouts are dragged onto a group's row in Settings > Loadouts > Saved Loadouts
-- (lo.group = the group's id); a loadout on no group shows everywhere, as before. Where you
-- are decides which loadouts the loadout flyout and the Loadout List show
-- (SP:LoadoutShownSet), and entering a group's place switches you to the group's first
-- loadout (its Switch to the First Loadout When I Enter), once. Nothing switches per boss:
-- WoW: Forever hides every mob's name in dungeons and raids, bosses too.
--
-- Groups are shared by your characters, like the loadouts (ShamanPower_LoadoutGroups: a list
-- in the page's order; a new group goes first, right under Everywhere). A zone group carries
-- the kind of place the player said it is (zoneType: raid, party, pvp or none); the game's
-- own answer replaces it the first time you are there. A raid group's name is fire red.
-- The Loadouts switch (opt.loadoutsOff, the sidebar) turns the loadout bar, the Loadout List
-- and all switching off; loadouts and groups stay saved.
--
-- A loadout rewrites assignments and secure button attributes, so nothing switches in
-- combat: a switch that comes up in combat waits for PLAYER_REGEN_ENABLED and happens only if
-- you are still in that group's place then. Nothing switches while you are dead: a ghost
-- released outside after a wipe has not left, and one running back has not arrived. Event
-- driven: no tickers, and nothing is listened to while there is no group.
--
-- WoW: Forever: a raid group may ask the raid for a resistance totem when you enter
-- (ShamanPowerResist.lua). The request waits for a raid to form and ends when you leave.
-- An automatic switch keeps a resistance the raid asked you for (the Resist file puts it
-- back on top of the new loadout).
--
-- The beta's Auto-Switch (opt.loadoutRules: By Location, rules with targets and boss
-- encounters) is dropped, not converted.
-- ============================================================================

local SP = ShamanPower
if not SP then return end
if select(2, UnitClass("player")) ~= "SHAMAN" then return end

local FOREVER = (SPCompat.FOREVER)

-- ---------------------------------------------------------------------------
-- The groups
-- ---------------------------------------------------------------------------
local KIND_NAMES = { raid = "Any Raid", party = "Any Dungeon", pvp = "Any Battleground or Arena", none = "Outside" }
local ZONE_TYPES = { raid = true, party = true, pvp = true, none = true }

function SP:LoadoutGroups()
	if type(ShamanPower_LoadoutGroups) ~= "table" then ShamanPower_LoadoutGroups = {} end
	return ShamanPower_LoadoutGroups
end

function SP:LoadoutGroupByID(id)
	if not id then return nil end
	for i, g in ipairs(self:LoadoutGroups()) do
		if g.id == id then return g, i end
	end
	return nil
end

-- the name its row and the Loadout List show
function SP:LoadoutGroupName(g)
	if not g then return "?" end
	if g.kind == "zone" then return g.zone or "?" end
	return KIND_NAMES[g.kind] or "?"
end

-- a raid's group: its name is fire red
function SP:LoadoutGroupIsRaid(g)
	return g ~= nil and (g.kind == "raid" or (g.kind == "zone" and g.zoneType == "raid"))
end

-- the words under a group's name
function SP:LoadoutGroupKindText(g)
	if not g then return "" end
	if g.kind ~= "zone" then
		return ({ raid = "Every raid", party = "Every dungeon", pvp = "Every battleground and arena", none = "The open world" })[g.kind] or ""
	end
	return ({ raid = "Raid", party = "Dungeon", pvp = "Battleground or Arena", none = "Other" })[g.zoneType or "raid"] or ""
end

-- capital letters, extra spaces and a leading "The" never matter in a zone's name: the game itself calls
-- one place Molten Core on its map and The Molten Core inside it
local function Norm(s)
	if type(s) ~= "string" or (issecretvalue and issecretvalue(s)) then return "" end
	return (strlower(strtrim((s:gsub("%s+", " ")))):gsub("^the ", ""))
end
SP.LoadoutZoneKey = Norm

local function NewID()
	local id
	repeat id = string.format("g%x%04x", time(), math.random(0, 65535)) until not SP:LoadoutGroupByID(id)
	return id
end

-- the loadouts of a group, by their place in the saved list (the first: the one you switch to)
function SP:LoadoutGroupMembers(g, out)
	out = out or {}
	if not g then return out end
	for i, lo in ipairs(ShamanPower_TotemLoadouts or {}) do
		if lo.group == g.id then out[#out + 1] = i end
	end
	return out
end

function SP:LoadoutGroupFirst(g)
	if not g then return nil end
	for i, lo in ipairs(ShamanPower_TotemLoadouts or {}) do
		if lo.group == g.id then return i end
	end
	return nil
end

-- the zone group with this name (forgiving), if one exists; except: a group to leave out (the one
-- being changed)
function SP:LoadoutGroupForZone(name, except)
	local want = Norm(name)
	if want == "" then return nil end
	for _, g in ipairs(self:LoadoutGroups()) do
		if g ~= except and g.kind == "zone" and Norm(g.zone) == want then return g end
	end
	return nil
end

-- the group of a kind of place (Any Raid ...), if one exists
function SP:LoadoutGroupOfKind(kind, except)
	for _, g in ipairs(self:LoadoutGroups()) do
		if g ~= except and g.kind == kind then return g end
	end
	return nil
end

-- ---------------------------------------------------------------------------
-- Where are we: the zone's own group, and the group of its kind of place
-- ---------------------------------------------------------------------------
local function Bucket()
	local inInstance, kind = IsInInstance()
	if not inInstance then return "none" end
	if kind == "raid" then return "raid" end
	if kind == "pvp" or kind == "arena" then return "pvp" end
	if kind == "party" or kind == "scenario" then return "party" end
	return "none"
end

local function HereGroups()
	local zone = Norm(GetRealZoneText())
	local bucket = Bucket()
	local zoneG, kindG
	for _, g in ipairs(SP:LoadoutGroups()) do
		if g.kind == "zone" then
			if not zoneG and zone ~= "" and Norm(g.zone) == zone then zoneG = g end
		elseif g.kind == bucket and not kindG then
			kindG = g
		end
	end
	return zoneG, kindG, bucket
end

-- zoneG, kindG, bucket ("raid", "party", "pvp" or "none")
function SP:LoadoutGroupsHere() return HereGroups() end

-- ---------------------------------------------------------------------------
-- The Zone Name box's suggestions: the zones you've stood in, by the exact name the game shows there
-- and their kind (account-wide, db.global.zonesSeen), and every zone and instance on the game's map
-- (C_Map, read once). Close names to what was typed, best first.
-- ---------------------------------------------------------------------------
local function Remember()
	local db = SP.db and SP.db.global
	local name = GetRealZoneText()
	if not db or type(name) ~= "string" or name == "" or (issecretvalue and issecretvalue(name)) then return end
	db.zonesSeen = db.zonesSeen or {}
	local key, kind = Norm(name), Bucket()
	local was = db.zonesSeen[key]
	if not (was and was.name == name and was.kind == kind) then db.zonesSeen[key] = { name = name, kind = kind } end
end
do
	local f = CreateFrame("Frame")   -- (a zone change only: nothing while you stay put)
	f:RegisterEvent("PLAYER_ENTERING_WORLD")
	f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
	f:SetScript("OnEvent", Remember)
end

-- the game's names: its dungeons, raids and battlegrounds with their kind (SP.INSTANCE_NAMES,
-- ShamanPowerZoneNames.lua: the world map has no page for them), then every zone on its map
local mapNames, mapKind
local function MapNames()
	if mapNames then return mapNames, mapKind end
	mapNames, mapKind = {}, {}
	for _, e in ipairs(SP.INSTANCE_NAMES or {}) do
		mapNames[#mapNames + 1] = e[1]
		mapKind[e[1]] = e[2]
	end
	if C_Map and C_Map.GetMapInfo then
		local types = Enum and Enum.UIMapType
		local ZONE, DUNGEON = types and types.Zone or 3, types and types.Dungeon or 4
		for id = 1, 4000 do
			local info = C_Map.GetMapInfo(id)
			if info and type(info.name) == "string" and info.name ~= "" and (info.mapType == ZONE or info.mapType == DUNGEON) then
				mapNames[#mapNames + 1] = info.name
			end
		end
	end
	return mapNames, mapKind
end

-- for comparing loosely: no punctuation either (Zul Gurub is Zul'Gurub)
local function Loose(s) return (Norm(s):gsub("[^%w ]", "")) end

-- edit distance, given up past limit
local function Distance(a, b, limit)
	local la, lb = #a, #b
	if math.abs(la - lb) > limit then return limit + 1 end
	local prev, cur = {}, {}
	for j = 0, lb do prev[j] = j end
	for i = 1, la do
		cur[0] = i
		local best, ca = i, a:byte(i)
		for j = 1, lb do
			local v = math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + ((ca == b:byte(j)) and 0 or 1))
			cur[j] = v
			if v < best then best = v end
		end
		if best > limit then return limit + 1 end
		prev, cur = cur, prev
	end
	return prev[lb]
end

-- The whole name you're typing (the Zone Name box fills in the rest): zones you've stood in first, then the
-- game's map, the shortest first; a leading "The" may be left out ("Molt" fills in Molten Core). nil under two
-- letters, when nothing starts so, or when what you typed is already a whole name.
function SP:LoadoutZoneComplete(text)
	local t = strlower(text or "")
	if #t < 2 then return nil end
	local best, bestSeen
	local function try(name, seen)
		local l, n = strlower(name), name
		if l:sub(1, #t) ~= t then
			if l:sub(1, 4) == "the " and l:sub(5, 4 + #t) == t then n = name:sub(5) else return end
		end
		if #n == #t then best, bestSeen = false, true return end   -- already whole: nothing to fill in
		if best == nil or (best and ((seen and not bestSeen) or (seen == bestSeen and (#n < #best or (#n == #best and n < best))))) then
			best, bestSeen = n, seen
		end
	end
	local db = self.db and self.db.global
	for _, v in pairs(db and db.zonesSeen or {}) do if best ~= false then try(v.name, true) end end
	for _, name in ipairs(MapNames()) do if best ~= false then try(name, false) end end
	return best or nil
end

-- Up to `max` { name, kind, seen } close to what was typed (kind: a dungeon's or raid's, or a zone's you've stood in;
-- seen: you have). Nothing when
-- the name already matches one as typed, or under three letters.
function SP:LoadoutZoneSuggestions(text, max)
	local out = {}
	local key, exact = Loose(text), Norm(text)
	if #key < 3 then return out end
	local cands, order = {}, {}
	local function add(name, kind, seen)
		local lk = Loose(name)
		if lk ~= "" and not cands[lk] then
			cands[lk] = { name = name, kind = kind, seen = seen }
			order[#order + 1] = lk
		end
	end
	local db = self.db and self.db.global
	for _, v in pairs(db and db.zonesSeen or {}) do add(v.name, v.kind, true) end   -- (first: their spelling wins)
	local names, kinds = MapNames()
	for _, name in ipairs(names) do add(name, kinds[name]) end
	local list = {}
	for _, lk in ipairs(order) do
		local c = cands[lk]
		if Norm(c.name) == exact then return {} end   -- matches as typed
		local score
		if lk == key then score = 0
		elseif #key >= 4 and lk:find(key, 1, true) then score = 1 + (#lk - #key) / 100
		else
			local limit = math.max(1, math.floor(#lk / 5))
			local d = Distance(key, lk, limit)
			if d <= limit then score = 1 + d end
		end
		if score then list[#list + 1] = { name = c.name, kind = c.kind, seen = c.seen, score = score - (c.seen and 0.5 or 0) } end
	end
	table.sort(list, function(a, b) if a.score ~= b.score then return a.score < b.score end return a.name < b.name end)
	for i = 1, math.min(max or 3, #list) do out[i] = { name = list[i].name, kind = list[i].kind, seen = list[i].seen } end
	return out
end

function SP:LoadoutsOn()
	return not (self.opt and self.opt.loadoutsOff)
end

-- The loadouts the flyout and the Loadout List show here: not hidden, and on no group (unless
-- this place's group turned Also Show My Other Loadouts Here off) or on one of this place's
-- groups (the zone's own and its kind's: both show, Q3). A loadout on a group that no longer
-- exists counts as on no group. Returns a set [index] = true (the same table each call).
local shownSet = {}
function SP:LoadoutShownSet()
	wipe(shownSet)
	local list = ShamanPower_TotemLoadouts or {}
	local zoneG, kindG = HereGroups()
	local own = zoneG or kindG
	local others = not (own and own.others == false)
	for i, lo in ipairs(list) do
		if not lo.hidden then
			local gid = lo.group
			if gid and not self:LoadoutGroupByID(gid) then gid = nil end
			if (gid == nil and others) or (gid ~= nil and ((zoneG and gid == zoneG.id) or (kindG and gid == kindG.id))) then
				shownSet[i] = true
			end
		end
	end
	return shownSet
end

-- ---------------------------------------------------------------------------
-- Switching
-- ---------------------------------------------------------------------------
local pending   -- { loadout, reason, valid = function() ... end } waiting for combat to end or for you to be alive

local function IndexOf(lo)
	for i, x in ipairs(ShamanPower_TotemLoadouts or {}) do
		if x == lo then return i end
	end
	return nil
end

-- Nothing switches in combat or while you are dead (Request and RunPending ask)
local function MustWait()
	return InCombatLockdown() or UnitIsDeadOrGhost("player")
end

local function Tell(text)
	if SP.opt and SP.opt.loadoutChat ~= false then print("|cff0070ddShamanPower|r: " .. text) end
end

local function Switch(lo, reason)
	if SP:IsOff() or not SP:LoadoutsOn() then return end   -- switched off during the fight it waited for
	local index = IndexOf(lo)
	if not index then return end
	if SP.opt.activeLoadout == index then return end   -- already there: say nothing
	SP:ApplyLoadout(index, true)
	Tell("switched to loadout " .. (lo.name or ("Loadout " .. index)) .. (reason and (" (" .. reason .. ")") or "") .. ".")
end

-- valid: called again once you are out of combat and alive; the switch only
-- happens if it still returns true then.
local function Request(lo, reason, valid)
	if not lo then return end
	if MustWait() then
		pending = { loadout = lo, reason = reason, valid = valid }
		return
	end
	pending = nil
	Switch(lo, reason)
end

-- The waiting switch (combat ended, or you are alive again): kept while you
-- are still dead or in combat; a ghost's whereabouts do not count against it.
local function RunPending()
	local p = pending
	if not p or MustWait() then return end
	pending = nil
	local ok, still = pcall(p.valid)
	if ok and still then Switch(p.loadout, p.reason) end
end

-- ---------------------------------------------------------------------------
-- Raid resistance requests from a raid group (WoW: Forever). Only a request a group made is
-- ended by the groups; one the raid made by hand is left alone.
-- ---------------------------------------------------------------------------
local RESIST_NAMES = {
	fire = SPCompat.SpellLabel(8184, "Fire Resistance"),
	frost = SPCompat.SpellLabel(8181, "Frost Resistance"),
	nature = SPCompat.SpellLabel(10595, "Nature Resistance"),
}
SP.LOADOUT_RESIST_NAMES = RESIST_NAMES
local heldResist = {}     -- key -> true: asked for by a group
local heldInPractice = {} -- key -> true: held as a practice request (/sp resisttest)
local zoneWant            -- the group's resistance, still to be asked for (no raid yet)

-- Returns false when the request was refused (not in a raid, or requests
-- turned off); says so unless quiet.
local function HoldResist(key, quiet)
	if not (FOREVER and key and RESIST_NAMES[key] and SP.SetResistNeeded) then return true end
	if heldResist[key] or SP:IsResistNeeded(key) then return true end
	if SP:SetResistNeeded(key, true) then
		heldResist[key] = true
		heldInPractice[key] = SP:ResistPracticeActive() or nil
		return true
	end
	if not quiet then
		if SP.opt and SP.opt.resistRequests == false then
			Tell(RESIST_NAMES[key] .. " not requested: raid resistance requests are turned off"
				.. " (Settings > Group Tools > Raid Resistance).")
		else
			Tell(RESIST_NAMES[key] .. " will be requested once you are in a raid.")
		end
	end
	return false
end

local function ReleaseResist()
	for key in pairs(heldResist) do
		heldResist[key] = nil
		heldInPractice[key] = nil
		if SP.IsResistNeeded and SP:IsResistNeeded(key) then SP:SetResistNeeded(key, false) end
	end
	zoneWant = nil
end

-- The group's request, refused before the raid formed (or dropped when the group broke up), is
-- made once a raid forms or practice mode starts. Called on roster settles and practice
-- switches; costs nothing without one.
local function RetryResist()
	if not (FOREVER and SP.ResistActive) or SP:IsOff() or not SP:LoadoutsOn() then return end
	local practising = SP:ResistPracticeActive()
	for key in pairs(heldResist) do
		-- gone with the group or with practice mode (not unticked by someone in the raid)
		if not SP:IsResistNeeded(key) and (not SP:ResistActive() or (heldInPractice[key] and not practising)) then
			heldResist[key] = nil
			heldInPractice[key] = nil
			zoneWant = key
		end
	end
	local key = zoneWant
	if key and HoldResist(key, true) then
		zoneWant = nil
		if heldResist[key] then Tell("requested " .. RESIST_NAMES[key] .. ".") end
	end
end

local function ResistFor(g)
	ReleaseResist()
	if FOREVER and g and g.resist and RESIST_NAMES[g.resist] and SP:LoadoutGroupIsRaid(g) then
		if not HoldResist(g.resist) then zoneWant = g.resist end
	end
end

-- ---------------------------------------------------------------------------
-- Arriving
-- ---------------------------------------------------------------------------
-- the group whose place you were in at the last look (false: none); nil: not looked yet (a
-- login, a /reload, a profile change, the Loadouts switch turned on): that look only notes it
local lastGroup
local arriveWhenAlive

local function RefreshShown()
	if SP.UpdateLoadoutBar then SP:UpdateLoadoutBar() end   -- (the Loadout List follows it)
end

local function Check()
	if not SP:LoadoutsOn() or SP:IsOff() then return end
	-- dead: where you are is looked at again once you are alive
	if UnitIsDeadOrGhost("player") then arriveWhenAlive = true return end
	arriveWhenAlive = nil
	local zoneG, kindG, bucket = HereGroups()
	-- the zone's own group learns what kind of place it is (a wrong label puts itself right)
	if zoneG and zoneG.zoneType ~= bucket then
		zoneG.zoneType = bucket
		if SP.LoadoutGroupsChangedUI then SP:LoadoutGroupsChangedUI() end
	end
	local g = zoneG or kindG
	local key = g and g.id or false
	local previous = lastGroup
	lastGroup = key
	RefreshShown()
	if key == previous then return end
	-- Its resistance is asked for even on a login or /reload, on purpose: after a /reload this
	-- client no longer knows the request and nobody resends it to the one who made it, so
	-- without asking again leaving the zone could not end it.
	ResistFor(g)
	if previous == nil then return end   -- a login or /reload is not arriving anywhere
	if g and g.entry ~= false then
		local first = SP:LoadoutGroupFirst(g)
		local lo = first and ShamanPower_TotemLoadouts[first]
		if lo then
			Request(lo, SP:LoadoutGroupName(g), function()
				local z, k = HereGroups()
				return (z or k) == g
			end)
		end
	end
end

-- after a change on the settings page (a group made, changed, deleted or moved; a loadout
-- dragged onto a group): where you are is noted again without switching, and the flyout and
-- the Loadout List follow
function SP:LoadoutGroupsChanged()
	self:UpdateLoadoutGroupEvents()
	if self:LoadoutsOn() and not self:IsOff() and not UnitIsDeadOrGhost("player") then
		local zoneG, kindG = HereGroups()
		local g = zoneG or kindG
		local key = g and g.id or false
		if key ~= lastGroup then
			lastGroup = key
			ResistFor(g)
		end
	end
	RefreshShown()
	if self.LoadoutGroupsChangedUI then self:LoadoutGroupsChangedUI() end
end

-- ---------------------------------------------------------------------------
-- Changing groups (the settings page). Out of a fight only, as a loadout's place is.
-- ---------------------------------------------------------------------------
local FIELDS = { "kind", "zone", "zoneType", "entry", "others", "resist" }

local function Clean(g, fields)
	for _, k in ipairs(FIELDS) do
		if fields[k] ~= nil then g[k] = fields[k] end
	end
	if not KIND_NAMES[g.kind] then g.kind = "zone" end
	if g.kind == "zone" then
		g.zone = strtrim((tostring(g.zone or ""):gsub("%s+", " ")))
		if not ZONE_TYPES[g.zoneType] then g.zoneType = "raid" end
	else
		g.zone, g.zoneType = nil, nil
	end
	if g.entry ~= false then g.entry = nil end      -- (On, the default, is never saved)
	if g.others ~= false then g.others = nil end
	if not (RESIST_NAMES[g.resist] and SP:LoadoutGroupIsRaid(g)) then g.resist = nil end
	return g
end

-- a new group, first in the list (right under Everywhere)
function SP:AddLoadoutGroup(fields)
	local g = Clean({ id = NewID() }, fields or {})
	tinsert(self:LoadoutGroups(), 1, g)
	self:LoadoutGroupsChanged()
	return g
end

function SP:EditLoadoutGroup(id, fields)
	local g = self:LoadoutGroupByID(id)
	if not g then return nil end
	Clean(g, fields or {})
	self:LoadoutGroupsChanged()
	return g
end

-- its loadouts go back to Everywhere: no loadout is deleted
function SP:DeleteLoadoutGroup(id)
	local g, at = self:LoadoutGroupByID(id)
	if not g then return false end
	tremove(self:LoadoutGroups(), at)
	for _, lo in ipairs(ShamanPower_TotemLoadouts or {}) do
		if lo.group == id then lo.group = nil end
	end
	self:LoadoutGroupsChanged()
	return true
end

-- a group's row to another place on the page (only the page's order: the flyout and the Loadout
-- List show one place's groups at a time)
function SP:MoveLoadoutGroup(id, to)
	local list = self:LoadoutGroups()
	local g, from = self:LoadoutGroupByID(id)
	if not g then return false end
	to = math.max(1, math.min(#list, to or from))
	if to == from then return false end
	tinsert(list, to, tremove(list, from))
	self:LoadoutGroupsChanged()
	return true
end

-- A loadout onto a group (id; nil: Everywhere), in front of the loadout `before` (nil: after
-- the group's last one). Its place in the saved list moves with it (the group's order is the
-- list's), the way a drag moves it (SP:MoveLoadout: the one in use stays in use).
function SP:PutLoadoutInGroup(from, id, before)
	local list = ShamanPower_TotemLoadouts
	local lo = list and list[from]
	if not lo or InCombatLockdown() then return false end
	if id and not self:LoadoutGroupByID(id) then return false end
	lo.group = id
	local to = from
	if before and before ~= lo then
		to = IndexOf(before) or from
		if to > from then to = to - 1 end
	else
		local last
		for i, x in ipairs(list) do
			if x ~= lo and x.group == id then last = i end
		end
		if last then to = (last < from) and (last + 1) or last end
	end
	if to ~= from then self:MoveLoadout(from, to) end
	self:LoadoutGroupsChanged()
	return true
end

-- Hidden: out of the flyout and the Loadout List everywhere (still saved; a group's first
-- loadout still switches you on entry, Q4)
function SP:SetLoadoutHidden(index, hidden)
	local lo = ShamanPower_TotemLoadouts and ShamanPower_TotemLoadouts[index]
	if not lo then return end
	lo.hidden = hidden and true or nil
	RefreshShown()
end

-- The Loadouts switch (the sidebar): Off, no loadout bar, no Loadout List, no switching and no
-- resistance request on entry; Switch To This Loadout and /spl still work
function SP:SetLoadoutsOn(on)
	if not self.opt then return end
	self.opt.loadoutsOff = (not on) or nil
	if on then lastGroup = nil end   -- like a login: where you are is noted, not arrived at
	self:UpdateLoadoutGroupEvents()
	if on then Check() else pending = nil; ReleaseResist() end
	RefreshShown()
end

-- ---------------------------------------------------------------------------
-- Events: listened to only while there is a group and loadouts are on, so a player who makes
-- no group pays nothing
-- ---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
if SPCompat and SPCompat.StressRegister then SPCompat.StressRegister(frame, "Auto Loadout Groups") end

function SP:UpdateLoadoutGroupEvents()
	frame:UnregisterAllEvents()
	frame:RegisterEvent("PLAYER_LOGIN")
	if not self:LoadoutsOn() or #self:LoadoutGroups() == 0 then
		pending = nil
		ReleaseResist()
		lastGroup, arriveWhenAlive = nil, nil   -- (back on later: where you are is noted again)
		return
	end
	-- ShamanPower switched off: nothing is listened to
	if self:IsOff() then pending = nil return end
	frame:RegisterEvent("PLAYER_ENTERING_WORLD")
	frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
	frame:RegisterEvent("PLAYER_REGEN_ENABLED")
	-- alive again: a ghost that ran back or took the spirit healer, or a resurrection before releasing
	pcall(frame.RegisterEvent, frame, "PLAYER_UNGHOST")
	pcall(frame.RegisterEvent, frame, "PLAYER_ALIVE")
end

-- A group's members that point at nothing, and the beta's Auto-Switch settings, go
local function Tidy()
	if SP.opt and SP.opt.loadoutRules ~= nil then SP.opt.loadoutRules = nil end
	for _, lo in ipairs(ShamanPower_TotemLoadouts or {}) do
		if lo.group and not SP:LoadoutGroupByID(lo.group) then lo.group = nil end
	end
end

frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		Tidy()
		if SP.db and SP.db.RegisterCallback then
			-- own key: registering with SP itself would replace the core's OnProfileChanged
			local key = {}
			local function reload()
				Tidy()
				lastGroup, pending = nil, nil
				SP:UpdateLoadoutGroupEvents()
				Check()   -- (notes where you are under the new profile: not an arrival)
			end
			SP.db.RegisterCallback(key, "OnProfileChanged", reload)
			SP.db.RegisterCallback(key, "OnProfileCopied", reload)
			SP.db.RegisterCallback(key, "OnProfileReset", reload)
		end
		-- a group's request refused before the raid formed goes out once it does (or once
		-- practice mode starts): ShamanPowerResist.lua loads after this file
		if FOREVER and SP.SetResistPractice then
			hooksecurefunc(SP, "OnRosterSettled", RetryResist)
			hooksecurefunc(SP, "SetResistPractice", RetryResist)
		end
		SP:UpdateLoadoutGroupEvents()
	elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
		Check()
	elseif event == "PLAYER_UNGHOST" or event == "PLAYER_ALIVE" then
		-- PLAYER_ALIVE also fires on releasing (still a ghost): both wait
		if arriveWhenAlive then Check() end
		RunPending()
	elseif event == "PLAYER_REGEN_ENABLED" then
		RunPending()
	end
end)

-- Switched back on: like a login, where you are is noted (not an arrival) and the loadout you
-- have stays; the next place switches as usual.
SP:OnOnOff(function(off)
	if not off then lastGroup, pending = nil, nil end
	SP:UpdateLoadoutGroupEvents()
	if not off then Check() end
end)
