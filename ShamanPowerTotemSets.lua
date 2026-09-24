-- ShamanPowerTotemSets.lua
-- WoW: Forever ships the Wrath-era totem sets: Call of the Elements / Ancestors /
-- Spirits each drop the four totems stored in one "page" of the multi-cast bar,
-- and Totemic Recall pulls them back. This file makes the Drop All button cast
-- the sets and keeps the set pages in step with assignments and loadouts.
--
-- Loaded from the Mainline TOC only. Every entry point checks for the multi-cast
-- API at runtime, so the file is inert on clients without totem sets.
local SP = ShamanPower
if not SP then return end

local SUMMON = { 66842, 66843, 66844 }   -- Call of the Elements / Ancestors / Spirits = set pages 1-3
local RECALL = 36936                     -- Totemic Recall
local PAGE_NAMES = { "Call of the Elements", "Call of the Ancestors", "Call of the Spirits" }
local SLOTS_PER_PAGE = 4
local boundPages = {} -- Session-only: owner record, readiness, actual slots and deferred work.
local selfWriteDepth = 0
local boundRefreshPending = false
local boundRefreshQueued = false

local function boundLoadout(page)
	for index, loadout in ipairs(ShamanPower_TotemLoadouts or {}) do
		if loadout.setPage == page then return loadout, index end
	end
end

-- ACTIONBAR_SLOT_CHANGED is synchronous (ActionBar API docs). Ignore those
-- callbacks during our writes, restoring the guard even if the API raises.
local function writeSlot(action, spellID)
	selfWriteDepth = selfWriteDepth + 1
	local ok, err = pcall(SetMultiCastSpell, action, spellID)
	selfWriteDepth = selfWriteDepth - 1
	if not ok then error(err, 0) end
end

local function spellName(id)
	if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
	return GetSpellInfo(id)
end
local function spellIcon(id)
	if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(id) end
	return GetSpellTexture(id)
end
local function known(id)
	if IsPlayerSpell then return IsPlayerSpell(id) end
	return IsSpellKnown and IsSpellKnown(id)
end

-- The client API the sets need. All three are Wrath-era globals.
local function haveAPI()
	return WOW_PROJECT_ID == WOW_PROJECT_MAINLINE
		and type(SetMultiCastSpell) == "function" and type(GetMultiCastTotemSpells) == "function"
		and C_ActionBar and type(C_ActionBar.GetMultiCastBarIndex) == "function"
end

-- Known summon spells by page: { [1] = 66842, [2] = 66843 } ...
function SP:KnownTotemSetPages()
	local t = {}
	for page, id in ipairs(SUMMON) do
		if known(id) then t[page] = id end
	end
	return t
end

-- True when this client has the API and the player knows at least Call of the Elements.
function SP:HasTotemSets()
	return haveAPI() and known(SUMMON[1]) and true or false
end

-- True when the client has Blizzard's totem bar at all. The bar and its first
-- page exist from the first totem on, long before Call of the Elements is
-- trainable, so keeping it in step with assignments must not wait for that spell.
function SP:HasTotemBar()
	return haveAPI()
end

-- Action slot holding page/element. Blizzard: action = buttonID + (multiCastBarIndex - 1) * 12,
-- with buttonID = (page - 1) * 4 + WoW totem slot (Fire 1, Earth 2, Water 3, Air 4).
local function setActionSlot(page, element)
	local wowSlot = SP.ElementToSlot and SP.ElementToSlot[element] or element
	local bar = C_ActionBar.GetMultiCastBarIndex()
	if not bar or bar < 1 then return nil end
	return (page - 1) * SLOTS_PER_PAGE + wowSlot + (bar - 1) * (NUM_ACTIONBAR_BUTTONS or 12)
end

-- Spell IDs currently stored in a page, by element.
function SP:ReadTotemSet(page)
	local t = {}
	if not haveAPI() then return t end
	for element = 1, 4 do
		local action = setActionSlot(page, element)
		if action then
			local kind, id = GetActionInfo(action)
			if kind == "spell" and id and id > 0 then t[element] = id end
		end
	end
	return t
end

-- What a summon places, for the shadow totem model: one Call of the Elements /
-- Ancestors / Spirits cast drops several totems, and in combat the game hides
-- which ones. The page is read live when its action slots are readable, else the
-- copy taken the last time they were (combat start, a bar change, login).
local setCache = {}
local function readPageSafe(page)
	local okSlot, first = pcall(setActionSlot, page, 1)
	if not okSlot or not first then return nil end
	local t = {}
	for element = 1, 4 do
		local ok, action = pcall(setActionSlot, page, element)
		if ok and action then
			local okInfo, kind, id = pcall(GetActionInfo, action)
			if not okInfo or (issecretvalue and (issecretvalue(kind) or issecretvalue(id))) then return nil end
			if kind == "spell" and type(id) == "number" and id > 0 then t[element] = id end
		end
	end
	return t
end
function SP:CacheTotemSetPages()
	if not haveAPI() then return end
	for page = 1, #SUMMON do
		local t = readPageSafe(page)
		if t then setCache[page] = t end
	end
end
-- { [element] = spellID } for a summon spell ID, or nil when spellID is not one.
function SP:TotemSetForSummon(spellID)
	if not haveAPI() or type(spellID) ~= "number" then return nil end
	for page, id in ipairs(SUMMON) do
		if id == spellID then return readPageSafe(page) or setCache[page] end
	end
	return nil
end

-- Totems the client allows in a slot, as a set of spell IDs. nil when the list
-- is empty, which on this client means the player knows no totem for that slot
-- yet (a level-11 shaman and Air): nothing may be written there.
local function allowedInSlot(element)
	local wowSlot = SP.ElementToSlot and SP.ElementToSlot[element] or element
	local list = { GetMultiCastTotemSpells(wowSlot) }
	if #list == 0 then return nil end
	local set = {}
	for _, id in ipairs(list) do set[id] = true end
	return set
end

-- The slot list holds the rank the player would cast, our tables hold rank-1
-- IDs: match by name and hand back the slot's own ID.
local function resolveInSlot(allowed, spellID)
	-- No allowed list = the slot takes nothing yet. Writing anyway made the
	-- client shout "Only Air totems can go in that slot" on every assignment
	-- change before the first Air totem was learned.
	if not allowed then return nil end
	if allowed[spellID] then return spellID end
	local want = spellName(spellID)
	if not want then return nil end
	for id in pairs(allowed) do
		if spellName(id) == want then return id end
	end
	return nil
end

local function sameSpell(a, b)
	if a == b then return true end
	if not a or not b then return false end
	local na, nb = spellName(a), spellName(b)
	return na ~= nil and na == nb
end

-- Write { [element] = spellID | false } into a page: a spell ID sets the slot,
-- false clears it, nil leaves it alone. Out of combat only.
-- Returns written, skipped, reason.
function SP:WriteTotemSet(page, spells)
	if not self:HasTotemBar() then return 0, 0, "no totem sets on this client" end
	-- page 1 is the bar itself; pages 2 and 3 only exist once their spell is known
	if page ~= 1 and not self:KnownTotemSetPages()[page] then return 0, 0, (PAGE_NAMES[page] or "that set") .. " is not known yet" end
	if InCombatLockdown() then return 0, 0, "in combat" end
	local written, skipped = 0, 0
	for element = 1, 4 do
		local want = spells[element]
		if want ~= nil then
			local action = setActionSlot(page, element)
			if not action then
				skipped = skipped + 1
			elseif want == false then
				local kind = GetActionInfo(action)
				if kind then
					-- clear: the client accepts spell 0 for "nothing in this slot"
					pcall(writeSlot, action, 0)
					if GetActionInfo(action) then skipped = skipped + 1 else written = written + 1 end
				end
			else
				local spellID = resolveInSlot(allowedInSlot(element), want)
				if spellID then
					local kind, cur = GetActionInfo(action)
					if not (kind == "spell" and sameSpell(cur, spellID)) then
						writeSlot(action, spellID)
						written = written + 1
					end
				else
					skipped = skipped + 1
				end
			end
		end
	end
	local state = boundPages[page]
	if state and state.loadout == boundLoadout(page) then
		-- Snapshot actual slots, not requested spells: a skipped unlearned slot
		-- must not erase saved intent when a later action-bar event is delivered.
		state.actual = self:ReadTotemSet(page)
	end
	return written, skipped
end

-- { [element] = spellID } from the player's current assignments (Drop All excludes respected).
function SP:TotemSetSpellsFromAssignments()
	local assignments = ShamanPower_Assignments and ShamanPower_Assignments[self.player]
	if not assignments then return {} end
	local exclude = {
		[1] = self.opt.excludeEarthFromDropAll, [2] = self.opt.excludeFireFromDropAll,
		[3] = self.opt.excludeWaterFromDropAll, [4] = self.opt.excludeAirFromDropAll,
	}
	-- unassigned or excluded elements clear their slot (false), so the set
	-- never drops something the assignments no longer say
	local t = {}
	for element = 1, 4 do
		local idx = assignments[element] or 0
		if idx > 0 and not exclude[element] then
			t[element] = self:GetTotemSpell(element, idx) or false
		else
			t[element] = false
		end
	end
	return t
end

-- Keep Call of the Elements (page 1) equal to the assignments. Silent, cheap,
-- idempotent. No UpdateDropAllButton here: this is called FROM it, and the
-- client fires UPDATE_MULTI_CAST_ACTIONBAR after a real write anyway.
function SP:SyncTotemSetFromAssignments()
	if self.opt.totemSetsSyncAssignments == false then return end
	if not self:HasTotemBar() or InCombatLockdown() then
		self.totemSetsSyncPending = self:HasTotemBar() or nil
		return
	end
	self.totemSetsSyncPending = nil
	self:WriteTotemSet(1, self:TotemSetSpellsFromAssignments())
	self.totemSetsSyncedOnce = true   -- from here on Blizzard's bar may lead (AdoptTotemBarAssignments)
end

-- The other direction: a totem picked on Blizzard's bar (its own flyouts)
-- becomes the assignment here. Page 1 is read after the client reports a
-- change; an element whose slot differs from the assignment is re-assigned,
-- an emptied slot un-assigns. Elements kept out of Drop All are skipped
-- (their slot is deliberately empty), so is a spell our tables do not know.
-- Not before the first sync of a session: at login the saved assignments are
-- the truth and Blizzard's bar is brought to them, not the other way round.
-- Out of combat only (assigning writes secure attributes); a change seen in
-- a fight is adopted at regen.
local function totemIndexForSpell(element, spellID)
	for i = 1, SP:GetTotemIndexLimit(element) do
		if sameSpell(SP:GetTotemSpell(element, i), spellID) then return i end
	end
	return nil
end

local function refreshLoadouts()
	if SP.UpdateLoadoutBar then SP:UpdateLoadoutBar() end
	if SP.RefreshLoadoutArgs then SP:RefreshLoadoutArgs() end
	local registry = LibStub and LibStub("AceConfigRegistry-3.0", true)
	if registry then registry:NotifyChange("ShamanPower") end
end

local function stateFor(page, loadout)
	local state = boundPages[page]
	if not state or state.loadout ~= loadout then
		state = { loadout = loadout, pendingWrite = true }
		boundPages[page] = state
	end
	return state
end

-- Only pages 2/3 are loadout-owned; assignments retain page 1. At login the
-- first valid saved owner wins, so malformed/duplicate bindings cannot race.
local function normalizeBindings()
	if not SP.opt or not ShamanPower_TotemLoadouts or not SP:HasTotemBar() then return false end
	local owners, changed = {}, false
	for _, loadout in ipairs(ShamanPower_TotemLoadouts) do
		local page = loadout.setPage
		if page ~= nil then
			if (page ~= 2 and page ~= 3) or owners[page] then
				loadout.setPage, changed = nil, true
			else
				owners[page] = loadout
			end
		end
	end
	for page = 2, 3 do
		if boundPages[page] and boundPages[page].loadout ~= owners[page] then boundPages[page] = nil end
	end
	if changed then refreshLoadouts() end
	return true
end

-- Returns success, reason, written, skipped. Combat queues record identity,
-- never an array index: deleting an earlier loadout cannot redirect the write.
function SP:SyncBoundLoadout(index)
	if not self.opt or not self:HasTotemBar() then return false, "no totem bar on this client" end
	local loadout = ShamanPower_TotemLoadouts and ShamanPower_TotemLoadouts[index]
	local page = loadout and loadout.setPage
	if page ~= 2 and page ~= 3 then return false, "loadout is not bound to a set page" end
	if boundLoadout(page) ~= loadout then return false, "another loadout owns that set page" end
	local state = stateFor(page, loadout)
	state.pendingWrite = true
	if InCombatLockdown() then return false, "queued until combat ends" end
	local spells = {}
	for element = 1, 4 do
		local totem = loadout[element] or 0
		spells[element] = totem > 0 and self:GetTotemSpell(element, totem) or false
	end
	local written, skipped, reason = self:WriteTotemSet(page, spells)
	if reason then return false, reason, written, skipped end
	state.ready, state.pendingWrite, state.pendingAdopt = true, nil, nil
	return true, nil, written, skipped
end

function SP:BoundLoadoutSummon(index)
	if not self:HasTotemBar() then return nil end
	local loadout = ShamanPower_TotemLoadouts and ShamanPower_TotemLoadouts[index]
	local page = loadout and loadout.setPage
	if (page == 2 or page == 3) and known(SUMMON[page]) then return SUMMON[page] end
end

function SP:BindLoadoutToTotemSet(index, page)
	if not self.opt or not self:HasTotemBar() then return false, "no totem bar on this client" end
	local loadout = ShamanPower_TotemLoadouts and ShamanPower_TotemLoadouts[index]
	if not loadout then return false, "loadout does not exist" end
	if page == 0 then page = nil end
	if page ~= nil and page ~= 2 and page ~= 3 then return false, "only Ancestors or Spirits can be bound" end
	if page and not known(SUMMON[page]) then return false, "that set page is not known yet" end
	local oldPage = loadout.setPage
	if oldPage then boundPages[oldPage] = nil end
	if page then
		for _, other in ipairs(ShamanPower_TotemLoadouts) do
			if other ~= loadout and other.setPage == page then other.setPage = nil end
		end
		boundPages[page] = nil
	end
	loadout.setPage = page
	local reason
	if page then
		local synced
		synced, reason = self:SyncBoundLoadout(index)
		if synced then reason = nil end
	end
	refreshLoadouts()
	return true, reason
end

local function adoptBoundPage(page)
	local loadout = boundLoadout(page)
	local state = boundPages[page]
	if not loadout or not state or state.loadout ~= loadout then boundPages[page] = nil; return end
	if not state.ready or state.pendingWrite then return end
	if InCombatLockdown() then state.pendingAdopt = true; return end
	state.pendingAdopt = nil
	local slots = SP:ReadTotemSet(page)
	local changed = false
	if SP.opt.totemSetsAdoptFromBar ~= false then
		for element = 1, 4 do
			if slots[element] ~= state.actual[element] then
				local index
				if slots[element] then index = totemIndexForSpell(element, slots[element]) else index = 0 end
				-- Unknown spells are not loadout entries; unchanged skipped slots
				-- stay at their saved selection instead of becoming zero.
				if index ~= nil and index ~= (loadout[element] or 0) then
					loadout[element], changed = index, true
				end
			end
		end
	end
	state.actual = slots
	if changed then refreshLoadouts() end
end

local function syncAllBoundLoadouts()
	if not normalizeBindings() then return end
	for page = 2, 3 do
		local loadout, index = boundLoadout(page)
		if loadout then SP:SyncBoundLoadout(index) end
	end
	if SP.UpdateLoadoutBar then SP:UpdateLoadoutBar() end
end

function SP:AdoptTotemBarAssignments()
	if self.opt.totemSetsAdoptFromBar == false or not self:HasTotemBar() or not self.totemSetsSyncedOnce then
		if SPCompat and SPCompat.Trace then SPCompat.Trace("TOTEMSETS adopt skipped: option=%s bar=%s syncedOnce=%s", tostring(self.opt.totemSetsAdoptFromBar), tostring(self:HasTotemBar()), tostring(self.totemSetsSyncedOnce)) end
		return
	end
	if InCombatLockdown() then self.totemSetsAdoptPending = true return end
	self.totemSetsAdoptPending = nil
	local assignments = ShamanPower_Assignments and ShamanPower_Assignments[self.player]
	if not assignments then return end
	local exclude = {
		[1] = self.opt.excludeEarthFromDropAll, [2] = self.opt.excludeFireFromDropAll,
		[3] = self.opt.excludeWaterFromDropAll, [4] = self.opt.excludeAirFromDropAll,
	}
	local slots = self:ReadTotemSet(1)
	if SPCompat and SPCompat.Trace then
		SPCompat.Trace("TOTEMSETS adopt read: E=%s F=%s W=%s A=%s  assigned %s/%s/%s/%s", tostring(slots[1]), tostring(slots[2]), tostring(slots[3]), tostring(slots[4]),
			tostring(assignments[1]), tostring(assignments[2]), tostring(assignments[3]), tostring(assignments[4]))
	end
	for element = 1, 4 do
		if not exclude[element] then
			local current = assignments[element] or 0
			local want
			if slots[element] then
				want = totemIndexForSpell(element, slots[element])   -- nil: not one of ours, leave it
			else
				want = 0
			end
			if want ~= nil and want ~= current then
				if SPCompat and SPCompat.Trace then SPCompat.Trace("TOTEMSETS adopt element %d: %d -> %d", element, current, want) end
				self:ApplyAssignment(element, want)
			end
		end
	end
end

-- What a flyout pick writes into Blizzard's bar: the page-1 action slot of an
-- element and the spell to put there (0 = leave the slot empty). nil when the
-- bar should be left alone (no API, sync turned off, element kept out of Drop
-- All, or a totem the slot does not take). Used by the flyouts' "multispell"
-- helpers, which are the only way to write the bar during a fight.
function SP:TotemBarSlotSpell(element, totemIndex)
	if not haveAPI() or self.opt.totemSetsSyncAssignments == false then return nil end
	local exclude = {
		[1] = self.opt.excludeEarthFromDropAll, [2] = self.opt.excludeFireFromDropAll,
		[3] = self.opt.excludeWaterFromDropAll, [4] = self.opt.excludeAirFromDropAll,
	}
	if exclude[element] then return nil end
	local action = setActionSlot(1, element)
	if not action then return nil end
	if not totemIndex or totemIndex == 0 then return action, 0 end
	local id = self:GetTotemSpell(element, totemIndex)
	id = id and resolveInSlot(allowedInSlot(element), id)
	if not id then return nil end
	return action, id
end

-- Send a saved loadout to a set page (2 = Ancestors, 3 = Spirits, 1 = Elements).
function SP:PushLoadoutToTotemSet(index, page)
	local loadout = ShamanPower_TotemLoadouts and ShamanPower_TotemLoadouts[index]
	if not loadout then print("|cffff0000ShamanPower:|r no loadout " .. tostring(index)) return end
	local spells = {}
	for element = 1, 4 do
		local idx = loadout[element] or 0
		if idx > 0 then spells[element] = self:GetTotemSpell(element, idx) end
	end
	local written, skipped, reason = self:WriteTotemSet(page, spells)
	if reason then print("|cffff0000ShamanPower:|r " .. reason) return end
	local name = loadout.name or ("Loadout " .. index)
	print(string.format("|cff00ff00ShamanPower:|r '%s' sent to %s (%d slot%s written%s)", name, PAGE_NAMES[page] or ("page " .. page),
		written, written == 1 and "" or "s", skipped > 0 and (", " .. skipped .. " not allowed in that slot") or ""))
	self:UpdateDropAllButton()
end

-- ---------------------------------------------------------------------------
-- Drop All button: cast the sets instead of the castsequence
-- ---------------------------------------------------------------------------

-- Called first thing from UpdateDropAllButton. Returns true when the sets own the button.
function SP:UpdateDropAllButtonForTotemSets(btn)
	self:SyncTotemSetFromAssignments()   -- the bar follows assignments even before the sets are trainable
	local on = self:HasTotemSets() and self.opt.dropAllUsesTotemSets ~= false
	if not on then
		if self.dropAllTotemSetsActive then
			-- hand the button back to the castsequence
			self.dropAllTotemSetsActive = nil
			self.dropAllLastMacro = ""
			if not InCombatLockdown() then
				for _, a in ipairs({ "type", "spell1", "shift-spell1", "ctrl-spell1", "alt-spell1", "spell2" }) do btn:SetAttribute(a, nil) end
			end
		end
		return false
	end
	local pages = self:KnownTotemSetPages()
	self.dropAllTotemSetsActive = true
	self.dropAllSequence = {}
	if not InCombatLockdown() then
		btn:RegisterForClicks("AnyUp", "AnyDown")
		-- one unsuffixed "type": the secure lookup falls back to it for every
		-- modifier and both mouse buttons (shift-type1 etc. are never set)
		btn:SetAttribute("macrotext", nil)
		btn:SetAttribute("type", "spell")
		btn:SetAttribute("spell1", pages[1])
		btn:SetAttribute("shift-spell1", pages[2] or pages[1])
		btn:SetAttribute("ctrl-spell1", pages[3] or pages[1])
		btn:SetAttribute("alt-spell1", pages[1])
		btn:SetAttribute("spell2", known(RECALL) and RECALL or nil)
		self.dropAllLastMacro = "totemsets"
	end
	local icon = btn.icon or _G["ShamanPowerAutoDropAllIcon"]
	if icon then icon:SetTexture(spellIcon(pages[1]) or 136024) end
	return true
end

function SP:DropAllTotemSetsTooltip(button)
	if not self.opt.ShowTooltips then return end
	local pages = self:KnownTotemSetPages()
	GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
	GameTooltip:AddLine("Drop All Totems", 1, 0.8, 0)
	local mods = { "Click", "Shift-click", "Ctrl-click" }
	for page = 1, 3 do
		if pages[page] then
			GameTooltip:AddLine(" ", 1, 1, 1)
			GameTooltip:AddLine(string.format("|cff00ccff%s:|r %s", mods[page], PAGE_NAMES[page]), 1, 1, 1)
			local set = self:ReadTotemSet(page)
			for _, element in ipairs({ 1, 2, 3, 4 }) do
				local id = set[element]
				GameTooltip:AddLine(string.format("  %s: %s", self.Elements[element] or element, id and spellName(id) or "|cff888888empty|r"), 0.8, 0.8, 0.8)
			end
		end
	end
	GameTooltip:AddLine(" ", 1, 1, 1)
	if known(RECALL) then GameTooltip:AddLine("|cff00ccffRight-click:|r Totemic Recall", 1, 1, 1) end
	if self.opt.totemSetsSyncAssignments ~= false then
		GameTooltip:AddLine("Call of the Elements follows your assignments", 0.5, 0.5, 0.5)
	end
	GameTooltip:AddLine("/spl set <2|3> <loadout> sends a loadout to a set", 0.5, 0.5, 0.5)
	if self.opt.enableMiddleClickPopOut ~= false then
		GameTooltip:AddLine("|cff00ccffMiddle-click:|r Pop out", 1, 1, 1)
	end
	GameTooltip:Show()
end

-- ---------------------------------------------------------------------------
-- Diagnostics: /spdiag sets
-- ---------------------------------------------------------------------------
function SP:TotemSetsDiag()
	local out = { "=== ShamanPower totem sets probe ===" }
	local function add(fmt, ...) out[#out + 1] = string.format(fmt, ...) end
	add("API: SetMultiCastSpell=%s GetMultiCastTotemSpells=%s ChangeMultiCastActionPage=%s C_ActionBar.GetMultiCastBarIndex=%s HasMultiCastActionBar=%s",
		type(SetMultiCastSpell), type(GetMultiCastTotemSpells), type(ChangeMultiCastActionPage),
		tostring(C_ActionBar and C_ActionBar.GetMultiCastBarIndex and C_ActionBar.GetMultiCastBarIndex()),
		tostring(type(HasMultiCastActionBar) == "function" and HasMultiCastActionBar()))
	add("NUM_ACTIONBAR_BUTTONS=%s  HasTotemSets()=%s  options: dropAllUsesTotemSets=%s totemSetsSyncAssignments=%s",
		tostring(NUM_ACTIONBAR_BUTTONS), tostring(self:HasTotemSets()), tostring(self.opt.dropAllUsesTotemSets), tostring(self.opt.totemSetsSyncAssignments))
	for page, id in ipairs(SUMMON) do
		add("page %d: %s (%d) known=%s", page, tostring(spellName(id)), id, tostring(known(id)))
	end
	add("recall: %s (%d) known=%s", tostring(spellName(RECALL)), RECALL, tostring(known(RECALL)))
	if type(GetMultiCastTotemSpells) == "function" then
		for wowSlot = 1, 4 do
			local list = { GetMultiCastTotemSpells(wowSlot) }
			local names = {}
			for i = 1, math.min(#list, 8) do names[#names + 1] = tostring(spellName(list[i])) .. "(" .. tostring(list[i]) .. ")" end
			add("GetMultiCastTotemSpells(%d): %d spells: %s", wowSlot, #list, table.concat(names, ", "))
		end
	end
	if haveAPI() then
		for page = 1, 3 do
			local parts = {}
			for element = 1, 4 do
				local action = setActionSlot(page, element)
				local kind, id
				if action then kind, id = GetActionInfo(action) end
				parts[#parts + 1] = string.format("%s@%s=%s%s", self.Elements[element] or element, tostring(action), tostring(kind), id and (":" .. tostring(id) .. " " .. tostring(spellName(id))) or "")
			end
			add("page %d slots: %s", page, table.concat(parts, " | "))
		end
	end
	local want = self:TotemSetSpellsFromAssignments()
	local parts = {}
	for element = 1, 4 do parts[#parts + 1] = (self.Elements[element] or element) .. "=" .. tostring(want[element] and spellName(want[element]) or "(clear)") end
	add("assignments would write: %s", table.concat(parts, ", "))
	add("dropAllTotemSetsActive=%s dropAllLastMacro=%s", tostring(self.dropAllTotemSetsActive), tostring(self.dropAllLastMacro))
	return out
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------
local ef = CreateFrame("Frame")
ef:RegisterEvent("PLAYER_ENTERING_WORLD")
ef:RegisterEvent("PLAYER_REGEN_ENABLED")
ef:RegisterEvent("SPELLS_CHANGED")
ef:RegisterEvent("PLAYER_REGEN_DISABLED")   -- fires before lockdown: last readable look at the set pages
pcall(ef.RegisterEvent, ef, "UPDATE_MULTI_CAST_ACTIONBAR")
pcall(ef.RegisterEvent, ef, "ACTIONBAR_SLOT_CHANGED")   -- a pick on Blizzard's bar lands in an action slot

-- Read only the affected page on the next frame. A page-2/3 pick must not
-- rewrite page 1, and an unrelated action-slot event must not write anything.
local barChangeQueued = false
local changedPages = {}
local function FlushBarChanges()
	barChangeQueued = false
	if not SP.opt or not SP:HasTotemBar() then return end
	SP:CacheTotemSetPages()   -- the shadow model's copy of what each summon places
	for page = 1, 3 do
		if changedPages[page] then
			changedPages[page] = nil
			if page == 1 then
				if SP.AdoptTotemBarAssignments then SP:AdoptTotemBarAssignments() end
				if SP.UpdateDropAllButton then SP:UpdateDropAllButton() end
			else
				adoptBoundPage(page)
			end
		end
	end
end

-- Spellbook/zoning refreshes are not edits. Existing ready pages adopt queued
-- bar picks first; only a new owner or an explicit pending edit leads the bar.
local function RefreshBoundAfterBarChanges()
	boundRefreshQueued = false
	if not SP.opt or not SP:HasTotemBar() or InCombatLockdown() then return end
	FlushBarChanges()
	for page = 2, 3 do
		local state = boundPages[page]
		if state and state.pendingAdopt then adoptBoundPage(page) end
	end
	boundRefreshPending = false
	syncAllBoundLoadouts()
end

local function QueueBoundRefresh()
	boundRefreshPending = true
	if boundRefreshQueued or InCombatLockdown() then return end
	boundRefreshQueued = true
	C_Timer.After(0, RefreshBoundAfterBarChanges)
end

local function OnTotemBarChanged(event, slot)
	if selfWriteDepth > 0 or not SP.opt or not SP:HasTotemBar() then return end
	local changedPage
	if event == "ACTIONBAR_SLOT_CHANGED" then
		local bar = C_ActionBar and C_ActionBar.GetMultiCastBarIndex and C_ActionBar.GetMultiCastBarIndex()
		if issecretvalue and (issecretvalue(bar) or issecretvalue(slot)) then return end
		if not (bar and bar >= 1 and type(slot) == "number") then return end
		local first = (bar - 1) * (NUM_ACTIONBAR_BUTTONS or 12) + 1
		if slot < first or slot >= first + 3 * SLOTS_PER_PAGE then return end
		changedPage = math.floor((slot - first) / SLOTS_PER_PAGE) + 1
	end
	if SPCompat and SPCompat.Trace then SPCompat.Trace("TOTEMSETS bar change via %s %s", event, tostring(slot)) end
	for page = changedPage or 1, changedPage or 3 do
		if page == 1 or boundLoadout(page) then changedPages[page] = true end
	end
	if barChangeQueued then return end
	barChangeQueued = true
	C_Timer.After(0, FlushBarChanges)
end

ef:SetScript("OnEvent", function(_, event, slot)
	-- the set cache is for the shadow totem model (Call of the Elements in combat),
	-- which runs whether or not ShamanPower draws a totem bar: fill it first
	if event == "PLAYER_REGEN_DISABLED" then SP:CacheTotemSetPages() return end
	if event == "PLAYER_ENTERING_WORLD" then
		C_Timer.After(3, function()
			if not SP.opt then return end
			SP:CacheTotemSetPages()
			if not SP:HasTotemBar() then return end
			if SP.UpdateDropAllButton then SP:UpdateDropAllButton() end
			QueueBoundRefresh()
		end)
		return
	end
	if not SP:HasTotemBar() then return end
	if event == "PLAYER_REGEN_ENABLED" then
		if not SP.opt then return end
		local boundPending = false
		for page = 2, 3 do
			local state = boundPages[page]
			if state and (state.pendingWrite or state.pendingAdopt) then boundPending = true end
		end
		if SP.dropAllTotemSetsActive or SP.totemSetsSyncPending or SP.totemSetsAdoptPending
			or boundPending or boundRefreshPending then
			C_Timer.After(0.5, function()
				-- Blizzard's bar first: a pick made there during the fight is the newest intent
				if SP.totemSetsAdoptPending and SP.AdoptTotemBarAssignments then SP:AdoptTotemBarAssignments() end
				if SP.UpdateDropAllButton then SP:UpdateDropAllButton() end
				for page = 2, 3 do
					local loadout, index = boundLoadout(page)
					local state = boundPages[page]
					if not loadout or not state or state.loadout ~= loadout then
						boundPages[page] = nil
					elseif state.pendingWrite then
						-- A saved edit wins over a queued read; Sync records actual
						-- post-write slots before bar changes may lead again.
						SP:SyncBoundLoadout(index)
					elseif state.pendingAdopt then
						adoptBoundPage(page)
					end
				end
				if boundRefreshPending then QueueBoundRefresh() end
				if boundPending and SP.UpdateLoadoutBar then SP:UpdateLoadoutBar() end
			end)
		end
	elseif event == "UPDATE_MULTI_CAST_ACTIONBAR" or event == "ACTIONBAR_SLOT_CHANGED" then
		OnTotemBarChanged(event, slot)
	elseif event == "SPELLS_CHANGED" then
		if not SP.opt then return end
		if SP.UpdateDropAllButton and (SP.dropAllTotemSetsActive or SP:HasTotemBar()) then SP:UpdateDropAllButton() end
		QueueBoundRefresh()
	end
end)
