-- ============================================================================
-- Raid resistance requests (WoW: Forever only).
--
-- On Forever the Fire, Frost and Nature Resistance totems reach the whole raid
-- within 30 yards (every other totem is party-only), so one shaman per
-- resistance is enough. Any shaman running ShamanPower, or the raid leader or
-- an assistant, can say "we need Fire Resistance". That is a REQUEST: every
-- client works out the same proposal (the shaman whose party loses least), and
-- only the chosen shaman's own client changes their totems - directly with
-- Free Assign or auto-accept on, otherwise after an Accept / Pass prompt.
-- Nobody else ever writes a shaman's totems.
--
-- Messages (SHPWR channel; names always last so "First Last" stays whole):
--   RESREQ <mask>[ P]    the full request state, one 0/1 per resistance in the
--                        order fire, frost, nature; " P" marks a practice request
--   RESPASS <key> <name> <name> passes on <key> (only accepted from <name>)
--   RESPICK <key>[ <name>] practice only: the practising player's pick (no name =
--                        a pretend shaman, or nobody)
-- Old clients ignore unknown keywords. Nothing is sent while idle: a request
-- goes out when it changes, and again (throttled) when the roster changes so
-- players who join learn it.
--
-- Practice mode (/sp resisttest) adds two pretend shamans that live only in
-- this file (never in the roster, the sync list or any message) so the whole
-- flow can be tried alone or in a party. Never in a raid: nothing about a
-- practice is sent to one or accepted from one.
--
-- Nothing secure changes in combat: an accepted request waits for the fight
-- to end, like loadout switches.
-- ============================================================================

local SP = ShamanPower
if not SP then return end
if WOW_PROJECT_ID ~= WOW_PROJECT_MAINLINE then return end

local RESIST_INDEX = 6   -- the resistance totem's index in its element's table
local ELEMENT_NAMES = { "Earth", "Fire", "Water", "Air" }
local RESIST = {
	{ key = "fire",   element = 3, label = "Fire Resistance" },
	{ key = "frost",  element = 2, label = "Frost Resistance" },
	{ key = "nature", element = 4, label = "Nature Resistance" },
}
local BY_KEY = {}
for i, r in ipairs(RESIST) do r.bit = i; BY_KEY[r.key] = r end
SP.RESIST_REQUESTS = RESIST

local ASK_TIMEOUT = 60      -- the prompt's own timeout (counts as Pass)
local WAIT_TIMEOUT = 75     -- everyone else stops waiting on a silent shaman
local REBROADCAST_GAP = 5   -- seconds between roster-driven resends

local MELEE_WEIGHT = { WARRIOR = 2, ROGUE = 2, PALADIN = 1, DRUID = 1 }
local MANA_USER = { PALADIN = true, PRIEST = true, MAGE = true, WARLOCK = true, DRUID = true, SHAMAN = true, HUNTER = true }

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------
local need = {}            -- key -> true while requested
local passed = {}          -- key -> { [name] = true }
local waitTimer = {}       -- key -> { name, timer } everyone's patience with a proposal
local proposal = {}        -- key -> name (last computed)
local queued = {}          -- key -> "apply" | "restore" waiting for combat to end
local lastSetter           -- who last changed the request (resends it to joiners)
local lastResend = 0
local practiceOwner        -- sender of the practice request we follow (not us)
local practicePick = {}    -- key -> name or "" from the practice owner
local sentPick = {}        -- key -> the pick we last sent (practice owner)
local prompt               -- { key, name, fake } the one open prompt
local restoreAfter = 0     -- GetTime() before which a leftover change is kept (login)
local keepOnLogin = {}     -- key -> true: changed before this login, kept while the group can confirm it
local optOutPassed = {}    -- key -> true: passed on while our requests are turned off
local claims = {}          -- key -> { [name] = true } shamans whose own ASSIGN says they drop it
for _, r in ipairs(RESIST) do passed[r.key] = {}; claims[r.key] = {} end

local function Opt() return SP.opt end

local function Player() return SP.player or UnitName("player") end

local function Enabled()
	local o = Opt()
	return o ~= nil and o.enabled ~= false and o.resistRequests ~= false
end

local function Applied()
	local o = Opt()
	if not o then return {} end
	o.resistApplied = o.resistApplied or {}
	return o.resistApplied
end

local function Say(text)
	print("|cff0070ddShamanPower|r: " .. text)
end

local function TotemName(r)
	return (SP.TotemNames[r.element] and SP.TotemNames[r.element][RESIST_INDEX]) or r.label
end

-- ---------------------------------------------------------------------------
-- Practice mode: pretend shamans, local to this file
-- ---------------------------------------------------------------------------
local practice = false
local FAKES = {
	-- a caster group: Frost or Nature Resistance costs it one ordinary totem;
	-- Fire Resistance would take Mana Spring from four casters
	{ name = "Kaldra (practice)", group = "a caster group", freeassign = true,
		classes = { "MAGE", "MAGE", "WARLOCK", "PRIEST" }, assign = { 1, 2, 1, 3 } },
	-- a melee group with no mana users: Fire Resistance costs it one ordinary
	-- totem; Frost or Nature Resistance would take Flametongue or Windfury
	{ name = "Morvak (practice)", group = "a melee group", freeassign = false,
		classes = { "WARRIOR", "WARRIOR", "ROGUE", "ROGUE" }, assign = { 1, 5, 2, 1 } },
}
local FAKE = {}
for _, f in ipairs(FAKES) do FAKE[f.name] = f end
local fakeAssign = {}      -- name -> { element -> index }
local fakePrev = {}        -- name -> { key -> previous index }
local fakeQueued = {}      -- key -> the pretend shaman who accepted it in combat

local function ResetFakes()
	for _, f in ipairs(FAKES) do
		fakeAssign[f.name] = { f.assign[1], f.assign[2], f.assign[3], f.assign[4] }
		fakePrev[f.name] = {}
	end
end

local function AssignedIndex(name, element)
	if FAKE[name] then
		local a = practice and fakeAssign[name]
		return a and a[element] or 0
	end
	local a = ShamanPower_Assignments and ShamanPower_Assignments[name]
	return (a and a[element]) or 0
end

-- ---------------------------------------------------------------------------
-- Who is in the group, and what each party would lose
-- ---------------------------------------------------------------------------
local roster = {}          -- name -> subgroup
local groups = {}          -- subgroup -> { melee = n, mana = n }

local function ScanRoster()
	wipe(roster)
	for _, g in pairs(groups) do g.melee, g.mana = 0, 0 end
	local function add(name, subgroup, class)
		if not name then return end
		name = SP:RemoveRealmName(name)
		roster[name] = subgroup
		local g = groups[subgroup]
		if not g then g = { melee = 0, mana = 0 }; groups[subgroup] = g end
		g.melee = g.melee + (MELEE_WEIGHT[class] or 0)
		if MANA_USER[class] then g.mana = g.mana + 1 end
	end
	if IsInRaid() then
		for i = 1, GetNumGroupMembers() do
			local name, _, subgroup, _, _, class = GetRaidRosterInfo(i)
			add(name, subgroup or 1, class)
		end
	else
		add(Player(), 1, select(2, UnitClass("player")))
		for i = 1, GetNumSubgroupMembers() do
			local unit = "party" .. i
			if UnitExists(unit) then add(GetUnitName(unit, true), 1, select(2, UnitClass(unit))) end
		end
	end
	if practice then
		for _, f in ipairs(FAKES) do
			local g = { melee = 0, mana = 0 }
			for _, class in ipairs(f.classes) do
				g.melee = g.melee + (MELEE_WEIGHT[class] or 0)
				if MANA_USER[class] then g.mana = g.mana + 1 end
			end
			groups[f.name] = g   -- keyed by name: never collides with a real raid group
		end
	end
end

-- What the shaman's party gives up when that element's totem becomes the
-- resistance. An empty slot costs nothing.
local function Loss(name, r)
	local current = AssignedIndex(name, r.element)
	if current == 0 then return 0 end
	local g
	if FAKE[name] then g = groups[name] else g = roster[name] and groups[roster[name]] end
	if not g then return 5 end
	-- the party-wide totem each slot usually holds costs the party; anything
	-- else there (Searing, Healing Stream, Grounding...) costs about one
	if r.key == "nature" and current == 1 then return g.melee end   -- Windfury
	if r.key == "fire" and current == 1 then return g.mana end      -- Mana Spring
	if r.key == "frost" and current == 5 then return g.melee end    -- Flametongue
	return 1
end

local function KnowsResist(name, r)
	if FAKE[name] then return true end
	-- practice: the pick may land on any other real shaman (an alt that has not
	-- learned it yet), but on you only if you know it (it lands on your real bar)
	if name ~= Player() and (practice or practiceOwner) then return true end
	if name == Player() then
		local id = SP:GetTotemSpell(r.element, RESIST_INDEX)
		if not id then return false end
		if IsPlayerSpell(id) or IsSpellKnown(id) then return true end
		return SP.PlayerKnowsTotem ~= nil and SP.PlayerKnowsTotem(id, TotemName(r)) or false
	end
	local info = SP.AllShamans and SP.AllShamans[name]
	local el = info and info[r.element]
	return (el and el[RESIST_INDEX] and el[RESIST_INDEX].known) and true or false
end

-- Real shamans running ShamanPower who are in the group, plus the pretend ones.
local candidates = {}
local function Candidates()
	wipe(candidates)
	for _, name in ipairs(SP.SyncList or {}) do
		if roster[name] or name == Player() then candidates[#candidates + 1] = name end
	end
	if practice then
		for _, f in ipairs(FAKES) do candidates[#candidates + 1] = f.name end
	end
	return candidates
end

-- ---------------------------------------------------------------------------
-- Activity
-- ---------------------------------------------------------------------------
local function Active()
	if not Enabled() then return false end
	return IsInRaid() or practice or practiceOwner ~= nil
end

local function AnyNeed()
	for _, r in ipairs(RESIST) do if need[r.key] then return true end end
	return false
end

local function AnyApplied()
	return next(Applied()) ~= nil
end

function SP:CanRequestResist()
	if practice then return true end
	if not Active() then return false end
	if UnitIsGroupLeader("player") or UnitIsGroupAssistant("player") then return true end
	return select(2, UnitClass("player")) == "SHAMAN"
end

local function SenderMayRequest(sender)
	if SP:CheckLeader(sender) then return true end
	if not (SP.AllShamans and SP.AllShamans[sender]) then return false end
	for _, name in ipairs(SP.SyncList or {}) do
		if name == sender then return true end
	end
	return false
end

-- ---------------------------------------------------------------------------
-- Sending (coalesced: one flush a moment after the last change)
-- ---------------------------------------------------------------------------
local sendQueued = false
local sendMask = false
local sendAssign = {}      -- element -> true: our own ASSIGN still to go out
local sendPass = {}        -- key -> true: our RESPASS still to go out
local events = CreateFrame("Frame")

local function MaskString()
	local s = ""
	for _, r in ipairs(RESIST) do s = s .. (need[r.key] and "1" or "0") end
	return s
end

local Flush
local function QueueSend(mask)
	if mask then sendMask = true end
	if sendQueued then return end
	sendQueued = true
	C_Timer.After(0.3, Flush)
end

Flush = function()
	sendQueued = false
	if GetNumGroupMembers() == 0 then sendMask = false; wipe(sendAssign); wipe(sendPass); return end
	local blocked = false
	-- practice never reaches a real raid (a party that just became one ends it)
	local practiceHere = practice and not IsInRaid()
	if practice and not practiceHere then sendMask = false end
	if sendMask then
		local msg = "RESREQ " .. MaskString()
		if practice then msg = msg .. " P" end
		if SP:SendMessage(msg, nil, nil, true) == false then blocked = true else sendMask = false end
	end
	if practiceHere and not blocked then
		for _, r in ipairs(RESIST) do
			local pick = practicePick[r.key] or ""
			if need[r.key] and sentPick[r.key] ~= pick then
				local msg = "RESPICK " .. r.key
				if pick ~= "" then msg = msg .. " " .. pick end
				if SP:SendMessage(msg, nil, nil, true) == false then blocked = true break end
				sentPick[r.key] = pick
			end
		end
	end
	if not blocked then
		local me = Player()
		local a = ShamanPower_Assignments and ShamanPower_Assignments[me]
		for element in pairs(sendAssign) do
			if SP:SendMessage("ASSIGN " .. me .. " " .. element .. " " .. ((a and a[element]) or 0)) == false then blocked = true break end
			sendAssign[element] = nil
		end
	end
	if not blocked then
		for key in pairs(sendPass) do
			if SP:SendMessage("RESPASS " .. key .. " " .. Player(), nil, nil, true) == false then blocked = true break end
			sendPass[key] = nil
		end
	end
	-- the client's chat lock (boss fights on Forever): try again when it lifts
	if blocked then
		events:RegisterEvent("PLAYER_REGEN_ENABLED")
		C_Timer.After(5, function() QueueSend(false) end)
	end
end

-- ---------------------------------------------------------------------------
-- Applying to your own totems (and the pretend shamans')
-- ---------------------------------------------------------------------------
local function RefreshOwnAssignment(element)
	SP:UpdateMiniTotemBar()
	SP:UpdateDropAllButton()
	SP:UpdateSPMacros()
	-- sent from the queue: under the chat lock it goes out once the lock lifts
	sendAssign[element] = true
	QueueSend(false)
	SP:UpdateLayout()
	if SP.SyncTotemSetFromAssignments then SP:SyncTotemSetFromAssignments() end
end

local Recompute

local function ApplyNow(r)
	local me = Player()
	ShamanPower_Assignments[me] = ShamanPower_Assignments[me] or {}
	local current = ShamanPower_Assignments[me][r.element] or 0
	if current == RESIST_INDEX then return end
	Applied()[r.key] = current
	ShamanPower_Assignments[me][r.element] = RESIST_INDEX
	RefreshOwnAssignment(r.element)
	local was = current > 0 and SP.TotemNames[r.element][current]
	Say("your " .. ELEMENT_NAMES[r.element] .. " totem is now " .. TotemName(r) .. " for the raid" .. (was and (" (was " .. was .. ")") or "") .. ".")
end

local function RestoreNow(r, quiet)
	local applied = Applied()
	local prev = applied[r.key]
	if prev == nil then return end
	applied[r.key] = nil
	local me = Player()
	local a = ShamanPower_Assignments[me]
	-- only undo our own change: a totem picked since then stays
	if not a or a[r.element] ~= RESIST_INDEX then return end
	a[r.element] = prev
	RefreshOwnAssignment(r.element)
	if quiet then return end
	local back = prev > 0 and SP.TotemNames[r.element][prev]
	Say(TotemName(r) .. " is no longer requested; your " .. ELEMENT_NAMES[r.element] .. " totem is back to " .. (back or "none") .. ".")
end

local function Apply(r)
	if InCombatLockdown() then
		queued[r.key] = "apply"
		events:RegisterEvent("PLAYER_REGEN_ENABLED")
		Say("you will drop " .. TotemName(r) .. " when combat ends.")
		return
	end
	queued[r.key] = nil
	ApplyNow(r)
end

local function Restore(r)
	if queued[r.key] == "apply" then queued[r.key] = nil end
	if Applied()[r.key] == nil then return end
	if InCombatLockdown() then
		queued[r.key] = "restore"
		events:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end
	queued[r.key] = nil
	RestoreNow(r)
end

-- Returns true when the pretend shaman switched now.
local function FakeApply(name, r)
	local a = fakeAssign[name]
	if not a or a[r.element] == RESIST_INDEX then return false end
	-- like a real shaman: a switch that comes up in combat waits for it to end
	if InCombatLockdown() then
		if fakeQueued[r.key] ~= name then
			fakeQueued[r.key] = name
			events:RegisterEvent("PLAYER_REGEN_ENABLED")
			Say("practice: " .. name .. " will drop " .. TotemName(r) .. " when combat ends.")
		end
		return false
	end
	fakeQueued[r.key] = nil
	fakePrev[name][r.key] = a[r.element]
	a[r.element] = RESIST_INDEX
	Say("practice: " .. name .. " drops " .. TotemName(r) .. ".")
	return true
end

local function FakeRestore(r)
	fakeQueued[r.key] = nil
	for _, f in ipairs(FAKES) do
		local prev = fakePrev[f.name] and fakePrev[f.name][r.key]
		if prev ~= nil then
			fakePrev[f.name][r.key] = nil
			if fakeAssign[f.name][r.element] == RESIST_INDEX then fakeAssign[f.name][r.element] = prev end
		end
	end
end

-- Two clients can disagree on the proposal (their sync lists differ for a
-- moment, or an ASSIGN is held up in the chat queue or the chat lock) and both
-- take the same resistance. Settled the same way on both sides with no extra
-- messages, however late the other claim arrives: when another shaman's ASSIGN
-- or practice pick claims a resistance we took for a request, whichever name
-- sorts later stands down. Standing down sends our own ASSIGN back, which the
-- other side ignores (it sorts earlier), and from then on their ASSIGN counts
-- as cover here even before they are in our sync list (claims).

-- we drop this resistance for a request, or will once combat ends
local function Holding(r)
	if queued[r.key] == "apply" then return true end
	if queued[r.key] == "standdown" or Applied()[r.key] == nil then return false end
	local a = ShamanPower_Assignments[Player()]
	return a ~= nil and a[r.element] == RESIST_INDEX
end

local function StandDown(r, other)
	if queued[r.key] == "apply" then
		queued[r.key] = nil
		Say(other .. " is already dropping " .. TotemName(r) .. " for the raid; you will not drop it after combat.")
		return
	end
	local prev = Applied()[r.key]
	if prev == nil then return end
	local back = prev > 0 and SP.TotemNames[r.element][prev]
	Say(other .. " also took " .. TotemName(r) .. " for the raid, so you stand down: your " .. ELEMENT_NAMES[r.element] .. " totem goes back to " .. (back or "none") .. ".")
	if InCombatLockdown() then
		queued[r.key] = "standdown"
		events:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end
	RestoreNow(r, true)
end

local function ClaimSeen(r, name)
	if not name or name == "" then return end
	local me = Player()
	if name ~= me and me > name and Holding(r) then StandDown(r, name) end
end

-- ShamanPower.lua's ASSIGN handler, after it stored the assignment
function SP:ResistClaimSeen(name, element, index)
	if index ~= RESIST_INDEX or not Enabled() then return end
	for _, r in ipairs(RESIST) do
		if r.element == element then
			claims[r.key][name] = true
			ClaimSeen(r, name)
			return
		end
	end
end

-- ---------------------------------------------------------------------------
-- Passing
-- ---------------------------------------------------------------------------
local function MarkPassed(key, name)
	passed[key][name] = true
	local w = waitTimer[key]
	if w and w.name == name then w.timer:Cancel(); waitTimer[key] = nil end
end

-- sent from the queue: under the chat lock it goes out once the lock lifts
local function SendPass(key)
	sendPass[key] = true
	QueueSend(false)
end

local function PassOwn(r)
	MarkPassed(r.key, Player())
	SendPass(r.key)
	Recompute()
end

-- ---------------------------------------------------------------------------
-- The prompt (one at a time; the next opens when it closes). ShamanPower's own
-- dialog (ShamanPowerDialog.lua), drawn above the settings and the setup tour.
-- ---------------------------------------------------------------------------
local PROMPT_KEY = "ShamanPowerResistRequest"

local function ClosePrompt()
	if not prompt then return end
	prompt.dead = true
	prompt = nil
	SP:HideSPDialog(PROMPT_KEY)
end

local function Resolve(data, accepted)
	if not data or data.dead then return end
	data.dead = true
	if prompt == data then prompt = nil end
	local r = BY_KEY[data.key]
	if not (r and need[r.key]) then Recompute() return end
	if data.fake then
		if accepted then FakeApply(data.name, r) else MarkPassed(r.key, data.name) end
		Recompute()
		return
	end
	if proposal[r.key] ~= Player() then Recompute() return end
	if accepted then Apply(r); Recompute() else PassOwn(r) end
end

local function ShowPrompt(r, name, fake)
	local data = { key = r.key, name = name, fake = fake }
	prompt = data
	local current = AssignedIndex(name, r.element)
	local slot = ELEMENT_NAMES[r.element]
	local was = current > 0 and SP.TotemNames[r.element][current]
	local body = "The raid needs " .. r.label .. ". Drop it for this fight?\n\n"
		.. "Your " .. slot .. " totem" .. (was and (" (" .. was .. ")") or "") .. " becomes " .. TotemName(r) .. " Totem"
		.. " until the request ends; then it goes back. It reaches the whole raid within 30 yards."
	if fake then
		body = "|cffffd200PRACTICE|r - " .. name .. " would see:\n\n" .. body
	elseif practiceOwner then
		body = "|cffffd200PRACTICE|r request from " .. practiceOwner .. ".\n\n" .. body
	elseif practice then
		body = "|cffffd200PRACTICE|r\n\n" .. body
	end
	local dialog = SP:ShowSPDialog({
		key = PROMPT_KEY,
		title = "Raid Resistance Request",
		text = body,
		buttons = {
			{ text = ACCEPT or "Accept", onClick = function() Resolve(data, true) end },
			{ text = PASS or "Pass", onClick = function() Resolve(data, false) end },
		},
		-- Escape, the close button and the timeout all pass it on to the next shaman
		onEscape = function() Resolve(data, false) end,
		timeout = ASK_TIMEOUT,
		countdown = true,
	})
	if not dialog and prompt == data then prompt = nil end
end

-- ---------------------------------------------------------------------------
-- The proposal
-- ---------------------------------------------------------------------------
local coverers = {}        -- key -> { names assigned the resistance }
for _, r in ipairs(RESIST) do coverers[r.key] = {} end

-- One shaman per requested resistance, lowest loss first, nobody twice while
-- another shaman is free. The same on every client: roster, synced assignments
-- and passes are shared; ties go by name.
local pairsList = {}
local function Choose()
	wipe(pairsList)
	local list = Candidates()
	for _, r in ipairs(RESIST) do
		proposal[r.key] = nil
		if need[r.key] and #coverers[r.key] == 0 then
			for _, name in ipairs(list) do
				if not passed[r.key][name] and KnowsResist(name, r) then
					pairsList[#pairsList + 1] = { r = r, name = name, loss = Loss(name, r), fake = FAKE[name] ~= nil }
				end
			end
		end
	end
	table.sort(pairsList, function(a, b)
		if a.loss ~= b.loss then return a.loss < b.loss end
		-- practice: a real shaman before a pretend one
		if a.fake ~= b.fake then return b.fake end
		if a.r.bit ~= b.r.bit then return a.r.bit < b.r.bit end
		return a.name < b.name
	end)
	local busy = {}
	for _, r in ipairs(RESIST) do
		for _, name in ipairs(coverers[r.key]) do busy[name] = true end
	end
	-- first pass: a different shaman for each; second: doubling up if we must
	for pass = 1, 2 do
		for _, p in ipairs(pairsList) do
			if not proposal[p.r.key] and (pass == 2 or not busy[p.name]) then
				proposal[p.r.key] = p.name
				busy[p.name] = true
			end
		end
	end
end

local function StartWaiting(r, name)
	local w = waitTimer[r.key]
	if w and w.name == name then return end
	if w then w.timer:Cancel() end
	waitTimer[r.key] = {
		name = name,
		timer = C_Timer.NewTimer(WAIT_TIMEOUT, function()
			local cur = waitTimer[r.key]
			if not cur or cur.name ~= name then return end
			waitTimer[r.key] = nil
			if need[r.key] and proposal[r.key] == name and #coverers[r.key] == 0 then
				passed[r.key][name] = true
				Recompute()
			end
		end),
	}
end

local recomputeQueued = false
local function RecomputeNow()
	recomputeQueued = false
	ScanRoster()
	-- requests that ended: give our totems back (after a /reload, only once
	-- the group had a chance to tell us the request still stands)
	local grace = GetTime() < restoreAfter and Active()
	for _, r in ipairs(RESIST) do
		if need[r.key] then
			-- confirmed by the group: from now on it ends like any other request
			keepOnLogin[r.key] = nil
		else
			if not (grace and keepOnLogin[r.key]) then Restore(r) end
			if practice then FakeRestore(r) end
			wipe(passed[r.key])
			proposal[r.key] = nil
			if waitTimer[r.key] then waitTimer[r.key].timer:Cancel(); waitTimer[r.key] = nil end
		end
	end

	-- who drops each resistance now (after any restore above)
	local list = Candidates()
	for _, r in ipairs(RESIST) do
		local c = coverers[r.key]
		wipe(c)
		for _, name in ipairs(list) do
			if AssignedIndex(name, r.element) == RESIST_INDEX then c[#c + 1] = name end
		end
		-- a group member not in our sync list yet whose own ASSIGN says they drop
		-- it (the shaman we stood down for) covers it too; a stale claim goes
		local seen = claims[r.key]
		for name in pairs(seen) do
			if not roster[name] or AssignedIndex(name, r.element) ~= RESIST_INDEX then
				seen[name] = nil
			elseif not tContains(c, name) then
				c[#c + 1] = name
			end
		end
	end

	-- the others read every shaman as knowing every totem: when we cannot
	-- cast one that is requested, say so once, so nobody waits on us
	local me = Player()
	if not practice and not practiceOwner and SP.AllShamans and SP.AllShamans[me] then
		for _, r in ipairs(RESIST) do
			if need[r.key] and #coverers[r.key] == 0 and not passed[r.key][me] and not KnowsResist(me, r) then
				MarkPassed(r.key, me)
				SendPass(r.key)
			end
		end
	end

	if practiceOwner then
		-- following someone's practice: their pick, not ours
		for _, r in ipairs(RESIST) do
			local pick = practicePick[r.key]
			if need[r.key] and #coverers[r.key] == 0 and pick and pick ~= "" and not passed[r.key][pick] then
				proposal[r.key] = pick
			else
				proposal[r.key] = nil
			end
		end
	else
		Choose()
	end

	local o = Opt() or {}
	local changed = false
	for _, r in ipairs(RESIST) do
		local name = proposal[r.key]
		if practice then
			if name and not FAKE[name] then practicePick[r.key] = name else practicePick[r.key] = "" end
		end
		if name then StartWaiting(r, name) end
		if name == me and queued[r.key] ~= "apply" then
			-- someone else's practice always asks: it never switches your totems unasked
			if (o.freeassign or o.resistAutoAccept) and not practiceOwner then
				Apply(r)
				changed = true
			elseif not prompt then
				ShowPrompt(r, me, false)
			end
		elseif name and FAKE[name] and fakeQueued[r.key] ~= name then
			if FAKE[name].freeassign then
				if FakeApply(name, r) then changed = true end
			elseif not prompt then
				ShowPrompt(r, name, true)
			end
		end
	end
	-- a prompt whose question is over closes
	if prompt and not (need[prompt.key] and proposal[prompt.key] == prompt.name) then ClosePrompt() end
	if practice then QueueSend(false) end
	if SP.ResistChanged then SP.ResistChanged() end
	-- our own change is not echoed back to us: look again with it in place
	if changed then Recompute() end
end

Recompute = function()
	if recomputeQueued then return end
	recomputeQueued = true
	C_Timer.After(0, RecomputeNow)
end
SP.RecomputeResist = Recompute

-- ---------------------------------------------------------------------------
-- Changing the request
-- ---------------------------------------------------------------------------
local function SetNeed(key, on)
	on = on and true or nil
	if need[key] == on then return false end
	need[key] = on
	return true
end

-- Local change (the strip's ticks, loadout rules). Returns false if not allowed.
function SP:SetResistNeeded(key, on)
	if not BY_KEY[key] or not self:CanRequestResist() then return false end
	if practiceOwner then practiceOwner = nil; wipe(practicePick) end
	if SetNeed(key, on) then
		lastSetter = Player()
		wipe(sentPick)
		QueueSend(true)
		Recompute()
	end
	return true
end

function SP:IsResistNeeded(key)
	return need[key] and true or false
end

function SP:ClearResistRequests(silent)
	local changed = false
	for _, r in ipairs(RESIST) do changed = SetNeed(r.key, false) or changed end
	practiceOwner = nil
	wipe(practicePick)
	if changed and not silent then QueueSend(true) end
	Recompute()
end

-- ---------------------------------------------------------------------------
-- Receiving
-- ---------------------------------------------------------------------------
-- Requests turned off: whatever the raid asks for is passed on at once (once per
-- request), so nobody waits WAIT_TIMEOUT on us.
local function PassWhileOff(msg, sender)
	local mask, flag = strmatch(msg, "^RESREQ ([01][01][01])( ?P?)")
	if not mask or not SenderMayRequest(sender) then return end
	if (flag == " P") == IsInRaid() then return end
	for i, r in ipairs(RESIST) do
		if strsub(mask, i, i) == "1" then
			if not optOutPassed[r.key] then optOutPassed[r.key] = true; SendPass(r.key) end
		else
			optOutPassed[r.key] = nil
		end
	end
end

function SP:HandleResistMessage(kw, msg, sender)
	if not Enabled() then
		if kw == "RESREQ" then PassWhileOff(msg, sender) end
		return
	end
	if kw == "RESPASS" then
		local key, name = strmatch(msg, "^RESPASS (%a+) (.+)$")
		if not (key and BY_KEY[key]) or self:RemoveRealmName(name) ~= sender then return end
		MarkPassed(key, sender)
		Recompute()
		return
	end
	if practice then return end   -- practising: only our own requests count
	if kw == "RESREQ" then
		local mask, flag = strmatch(msg, "^RESREQ ([01][01][01])( ?P?)")
		if not mask or not SenderMayRequest(sender) then return end
		local isPractice = flag == " P"
		-- a real request needs a raid; practice never counts in one
		if isPractice == IsInRaid() then return end
		if isPractice then
			if practiceOwner ~= sender then wipe(practicePick) end
			practiceOwner = sender
		else
			practiceOwner = nil
			wipe(practicePick)
		end
		for i, r in ipairs(RESIST) do SetNeed(r.key, strsub(mask, i, i) == "1") end
		lastSetter = sender
		if not AnyNeed() then practiceOwner = nil; wipe(practicePick) end
		Recompute()
	elseif kw == "RESPICK" then
		if sender ~= practiceOwner then return end
		local key, name = strmatch(msg, "^RESPICK (%a+) ?(.*)$")
		if not (key and BY_KEY[key]) then return end
		practicePick[key] = self:RemoveRealmName(name or "") or ""
		ClaimSeen(BY_KEY[key], practicePick[key])
		Recompute()
	end
end

-- ---------------------------------------------------------------------------
-- What the assignments window shows
-- ---------------------------------------------------------------------------
local function JoinNames(list)
	if #list == 1 then return list[1] end
	return table.concat(list, ", ", 1, #list - 1) .. " and " .. list[#list]
end

-- text, tone ("ok", "warn", "busy", "dim")
function SP:GetResistStatus(key)
	local r = BY_KEY[key]
	if not r then return "", "dim" end
	local c = coverers[key]
	if #c > 1 then
		return JoinNames(c) .. ((#c == 2) and " both" or " all") .. " drop it: one is enough for the whole raid.", "warn"
	elseif #c == 1 then
		-- a pretend shaman's name already ends in "(practice)"
		if FAKE[c[1]] then return c[1] .. " covers the raid", "ok" end
		return c[1] .. " (covers the raid)", "ok"
	end
	if not need[key] then return "not requested", "dim" end
	local name = proposal[key]
	if name then
		if name == Player() and queued[key] == "apply" then return "you (switching when combat ends)", "busy" end
		if fakeQueued[key] == name then return name .. ": switching when combat ends", "busy" end
		return "asking " .. name .. "...", "busy"
	end
	if practiceOwner and practicePick[key] == "" then return "asking a practice shaman...", "busy" end
	if next(passed[key]) then return "nobody yet (everyone asked has passed)", "warn" end
	return "nobody yet", "warn"
end

function SP:ResistActive() return Active() end
function SP:ResistPracticeActive() return practice end
function SP:ResistPracticeOwner() return practiceOwner end

function SP:GetResistPracticeLine()
	if not practice then return nil end
	local parts = {}
	for _, f in ipairs(FAKES) do
		parts[#parts + 1] = f.name .. " (" .. f.group .. ", Free Assign " .. (f.freeassign and "on" or "off") .. ")"
	end
	return "Practice mode: pretend shamans " .. JoinNames(parts) .. ". Nothing about them is sent. /sp resisttest off to stop."
end

-- ---------------------------------------------------------------------------
-- Practice mode switch
-- ---------------------------------------------------------------------------
function SP:SetResistPractice(on)
	on = on and true or false
	if on == practice then
		Say("resistance practice mode is already " .. (on and "on" or "off") .. ".")
		return
	end
	if not Enabled() then
		Say("raid resistance requests are turned off in the options.")
		return
	end
	if on and IsInRaid() then
		Say("practice mode is for solo or a party. In a raid the Raid Resistance ticks make real requests.")
		return
	end
	if on then
		-- leave any real request first; practice never mixes with one
		self:ClearResistRequests(true)
		practice = true
		ResetFakes()
		wipe(sentPick)
		Say("resistance practice mode ON: two pretend shamans (" .. FAKES[1].name .. ", Free Assign on; "
			.. FAKES[2].name .. ", Free Assign off) join the Raid Resistance strip in the assignments window (/sp totems). Nothing is sent about them. /sp resisttest off to stop.")
	else
		local owned = AnyNeed()
		for _, r in ipairs(RESIST) do SetNeed(r.key, false) end
		practice = false
		-- tell a partner following this practice to stand down
		if owned and GetNumGroupMembers() > 0 and not IsInRaid() then SP:SendMessage("RESREQ 000 P", nil, nil, true) end
		sendMask = false
		wipe(practicePick)
		wipe(sentPick)
		wipe(fakeAssign)
		wipe(fakePrev)
		wipe(fakeQueued)
		Say("resistance practice mode OFF: pretend shamans removed and your totems put back.")
	end
	RecomputeNow()
end

-- /sp resisttest [on|off]
local slash = SlashCmdList["SHAMANPOWER"]
if slash then
	SlashCmdList["SHAMANPOWER"] = function(msg)
		local cmd, arg = strmatch(strtrim(strlower(msg or "")), "^(%S+)%s*(%S*)$")
		if cmd == "resisttest" then
			if arg == "on" then SP:SetResistPractice(true)
			elseif arg == "off" then SP:SetResistPractice(false)
			else SP:SetResistPractice(not practice) end
			return
		end
		return slash(msg)
	end
end

-- ---------------------------------------------------------------------------
-- Events: nothing runs while idle. Roster settles and comm bursts only wake
-- this up while a request, a practice or one of our changes exists.
-- ---------------------------------------------------------------------------
local function Busy()
	return practice or AnyNeed() or AnyApplied() or practiceOwner ~= nil
end

-- ...or the assignments window shows the coverage lines in a raid
local function Watching()
	if Busy() then return true end
	local win = rawget(_G, "ShamanPowerAssign")
	return Active() and win ~= nil and win:IsShown() and true or false
end

hooksecurefunc(SP, "QueueCommRefresh", function()
	if Watching() then Recompute() end
end)

-- Your own hand edit (assignments window, a flyout, Blizzard's totem bar): the
-- coverage lines follow it (your own ASSIGN is never echoed back), and taking
-- back the slot that holds a requested resistance is a Pass, so it is not
-- put straight back on you.
local function OwnEdit(name, element)
	if not Watching() then return end
	local me = Player()
	if name == me then
		for _, r in ipairs(RESIST) do
			if r.element == element and need[r.key] and Applied()[r.key] ~= nil and queued[r.key] == nil
				and AssignedIndex(me, element) ~= RESIST_INDEX and not passed[r.key][me] then
				Say("you changed your " .. ELEMENT_NAMES[element] .. " totem, so " .. TotemName(r) .. " passes to the next shaman.")
				PassOwn(r)
			end
		end
	end
	Recompute()
end
hooksecurefunc(SP, "PerformCycle", function(_, name, element) OwnEdit(name, element) end)
hooksecurefunc(SP, "PerformCycleBackwards", function(_, name, element) OwnEdit(name, element) end)
hooksecurefunc(SP, "ApplyAssignment", function(_, element) OwnEdit(Player(), element) end)

hooksecurefunc(SP, "OnRosterSettled", function()
	if not Busy() then
		if Watching() then Recompute() end
		return
	end
	-- practice never runs in a real raid: a party that becomes one ends it
	if IsInRaid() and (practice or practiceOwner) then
		if practice then
			Say("you are in a raid now, so resistance practice mode ends.")
			SP:SetResistPractice(false)
		else
			SP:ClearResistRequests(true)
		end
		return
	end
	-- disbanded (or out of the raid): the request is over
	if not Active() then
		SP:ClearResistRequests(true)
		return
	end
	-- resend for players who just joined (only the last one to change it)
	if lastSetter == Player() and AnyNeed() and GetTime() - lastResend > REBROADCAST_GAP then
		lastResend = GetTime()
		wipe(sentPick)
		QueueSend(true)
	end
	Recompute()
end)

-- someone (re)joined and asked for shaman data: they need the request too
hooksecurefunc(SP, "QueueSelfBroadcast", function()
	if lastSetter == Player() and AnyNeed() and GetTime() - lastResend > REBROADCAST_GAP then
		lastResend = GetTime()
		wipe(sentPick)
		QueueSend(true)
	end
end)

events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self, event)
	if event == "PLAYER_LOGIN" then
		-- a /reload while dropping a resistance: keep it while the group can
		-- still tell us the request stands, then put it back if nobody did
		-- (only what was changed before this login: a request made and ended
		-- since then gives the totem back at once)
		restoreAfter = GetTime() + 20
		for key in pairs(Applied()) do keepOnLogin[key] = true end
		C_Timer.After(21, function()
			wipe(keepOnLogin)
			if AnyApplied() then Recompute() end
		end)
	elseif event == "PLAYER_REGEN_ENABLED" then
		self:UnregisterEvent("PLAYER_REGEN_ENABLED")
		for _, r in ipairs(RESIST) do
			local q = queued[r.key]
			queued[r.key] = nil
			if q == "apply" and need[r.key] then ApplyNow(r)
			elseif q == "restore" then RestoreNow(r)
			elseif q == "standdown" then RestoreNow(r, true) end
			local fake = fakeQueued[r.key]
			fakeQueued[r.key] = nil
			if fake and practice and need[r.key] and proposal[r.key] == fake then FakeApply(fake, r) end
		end
		if sendMask or practice or next(sendAssign) or next(sendPass) then QueueSend(false) end
		Recompute()
	end
end)

-- ---------------------------------------------------------------------------
-- Settings: Totem Bar > Raid Resistance (group buttons.resist_section)
-- ---------------------------------------------------------------------------
if SP.options and SP.options.args and SP.options.args.buttons and SP.options.args.buttons.args then
	SP.options.args.buttons.args.resist_section = {
		order = 3.72, type = "group", name = "Raid Resistance",
		disabled = function() return SP.opt and SP.opt.enabled == false end,
		args = {
			desc = {
				order = 0, type = "description", width = "full",
				name = "On WoW: Forever the Fire, Frost and Nature Resistance totems reach every raid member within 30 yards, so one shaman per resistance covers the raid."
					.. " Any shaman running ShamanPower, or the raid leader or an assistant, can ask for one with the Raid Resistance ticks in the assignments window (/sp totems)."
					.. " ShamanPower picks the shaman whose party loses least, and only that shaman's own ShamanPower changes their totems.",
			},
			enabled = {
				order = 1, type = "toggle", width = "full", name = "Raid Resistance Requests",
				desc = "Show the Raid Resistance ticks and answer requests from the raid. Off: you do not see the ticks, and a request that picks you passes straight to the next shaman.",
				get = function() return SP.opt.resistRequests ~= false end,
				set = function(_, v)
					if v then
						SP.opt.resistRequests = nil
						wipe(optOutPassed)
						Recompute()   -- the strip comes back with current coverage lines
						return
					end
					if practice then SP:SetResistPractice(false) end
					-- a request we made ends for everyone; one we were asked for
					-- passes to the next shaman at once
					local mine = lastSetter == Player()
					wipe(optOutPassed)
					if not mine then
						for _, r in ipairs(RESIST) do
							if need[r.key] then
								optOutPassed[r.key] = true
								if not passed[r.key][Player()] then SendPass(r.key) end
							end
						end
					end
					SP:ClearResistRequests(not mine)   -- gives our totems back
					SP.opt.resistRequests = false
				end,
			},
			autoaccept = {
				order = 2, type = "toggle", width = "full", name = "Auto-Accept Resistance Requests",
				desc = "When the raid asks you for a resistance totem, switch to it without the Accept / Pass prompt. With Free Assign on you are switched without a prompt anyway."
					.. " Your previous totem comes back when the request ends. Never in combat: a switch that comes up in a fight waits for it to end.",
				disabled = function() return SP.opt.resistRequests == false end,
				get = function() return SP.opt.resistAutoAccept == true end,
				set = function(_, v) SP.opt.resistAutoAccept = v and true or nil end,
			},
			practice = {
				order = 3, type = "toggle", width = "full", name = "Practice Mode (this session only)",
				desc = "Adds two pretend shamans so you can try requests alone or in a party: one with Free Assign on (switches straight away), one with it off (you see the Accept / Pass prompt they would get)."
					.. " Nothing about them is sent to anyone. Not in a raid: there the ticks make real requests, and joining one ends practice. Same as /sp resisttest. Always off after a /reload.",
				disabled = function() return SP.opt.resistRequests == false end,
				get = function() return practice end,
				set = function(_, v) SP:SetResistPractice(v) end,
			},
		},
	}
end
