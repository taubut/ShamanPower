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
-- Page 1 (Call of the Elements) as it was after ShamanPower last wrote or read it (nil until
-- then): a pick on Blizzard's bar is only what CHANGED since. A slot Blizzard's bar couldn't take (Searing not
-- listed yet), a loading screen or a bar not ready yet is never taken as "the player chose Empty".
local page1Actual
local barChangeQueued = false
local changedPages = {}
local editedSlots = {}   -- [element] = true: Blizzard said this one page-1 slot changed (a pick or a clear)
local clearedSlots = {}  -- [element] = true: the player's LAST change to that slot emptied it (a later pick wipes the mark)
-- (3.0.9.9) Call Flyout on Drop All: its frames, its in-fight copy of each Call's totems, its queue
local CALL = { sets = {}, buttons = {}, routers = {} }

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
local function pageName(page)
	return (SUMMON[page] and spellName(SUMMON[page])) or PAGE_NAMES[page] or ("page " .. page)
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
	return SPCompat.FOREVER
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

-- Page 1 as it is now, or nil while the client can't say (no multi-cast bar index yet):
-- an unreadable bar is never taken as every slot emptied
local function readPage1()
	if not haveAPI() then return nil end
	local ok, action = pcall(setActionSlot, 1, 1)
	if not ok or not action then return nil end
	return SP:ReadTotemSet(1)
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
	-- another rank of the same spell, by ID, highest first (a rank's name can
	-- differ from the first rank's in some languages)
	local family = SPCompat.SpellRanks(spellID)
	if family then
		for index = #family, 1, -1 do
			if allowed[family[index]] then return family[index] end
		end
	end
	local want = spellName(spellID)
	if issecretvalue(want) or not want then return nil end
	for id in pairs(allowed) do
		local name = spellName(id)
		if not issecretvalue(name) and (name == want
			or (SPCompat.HasTotemCastAliases(spellID) and SPCompat.TotemNameMatches(name, spellID))) then
			return id
		end
	end
	return nil
end

local function sameSpell(a, b)
	if a == b then return true end
	if not a or not b then return false end
	-- ranks of one spell, by ID
	local family = SPCompat.SpellRanks(a)
	if family then
		for _, rank in ipairs(family) do
			if rank == b then return true end
		end
	end
	local na, nb = spellName(a), spellName(b)
	if issecretvalue(na) or issecretvalue(nb) then return false end
	if na ~= nil and na == nb then return true end
	return (SPCompat.HasTotemCastAliases(a) and SPCompat.TotemNameMatches(nb, a))
		or (SPCompat.HasTotemCastAliases(b) and SPCompat.TotemNameMatches(na, b)) or false
end

-- Write { [element] = spellID | false } into a page: a spell ID sets the slot,
-- false clears it, nil leaves it alone. Out of combat only.
-- Returns written, skipped, reason.
-- a page-1 slot differs from what it held (nil = empty; another rank of the same totem is no change)
local function slotChanged(now, was)
	if now == nil or was == nil then return now ~= was end
	return not sameSpell(now, was)
end

function SP:WriteTotemSet(page, spells)
	if not self:HasTotemBar() then return 0, 0, "totem sets are not available in this version of the game" end
	-- page 1 is the bar itself; pages 2 and 3 only exist once their spell is known
	if page ~= 1 and not self:KnownTotemSetPages()[page] then return 0, 0, pageName(page) .. " is not known yet" end
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
	if page == 1 then page1Actual = readPage1() or page1Actual end   -- what the slots really hold now
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
			-- (a totem our tables can't find right now: its slot is left as it is, never emptied)
			t[element] = self:GetTotemSpell(element, idx)
		else
			t[element] = false
		end
	end
	return t
end

-- Before Sync writes the assignments over page 1:
-- 1. a pick on Blizzard's bar not taken yet (made in a fight, or this very frame, or while
--    switched off) is newer than the assignments: it is taken first, so the write never wipes it;
-- 2. the session's first write: an element Empty here takes the totem on Blizzard's bar instead
--    of wiping it (put there while ShamanPower was off or not loaded, or never set here).
local function adoptBeforeWrite(self)
	if changedPages[1] or self.totemSetsAdoptPending then
		changedPages[1] = nil
		self:AdoptTotemBarAssignments()
	end
	if not self.totemSetsSyncedOnce then self:AdoptIntoEmptyAssignments() end
end

-- Keep Call of the Elements (page 1) equal to the assignments. Silent, cheap,
-- idempotent. No UpdateDropAllButton here: this is called FROM it, and the
-- client fires UPDATE_MULTI_CAST_ACTIONBAR after a real write anyway.
function SP:SyncTotemSetFromAssignments()
	if self:IsOff() then return end
	-- a cold login while the game still calls the player "Unknown": the real assignments aren't
	-- read yet, so nothing is written or adopted (the session's first real look at the bar comes
	-- once the name is known)
	local me = self.player
	if type(me) ~= "string" or me == "" or me == "Unknown" or me == UNKNOWNOBJECT then return end
	-- (3.0.9.9) another Call picked on Drop All's flyout: the assignments are that Call's totems,
	-- and that Call follows them whatever Call of the Elements Follows My Assignments says (it is
	-- about Call of the Elements, which is left alone meanwhile)
	local callPage = self:CallPage()
	if callPage ~= 1 then
		if not self:HasTotemBar() or InCombatLockdown() then
			self.totemSetsSyncPending = self:HasTotemBar() or nil
			return
		end
		if not readPageSafe(callPage) then self.totemSetsSyncPending = true return end
		self.totemSetsSyncPending = nil
		CALL.write(self, callPage)
		return
	end
	-- switched off: Blizzard's bar is left alone (brought in step on switch-on). The other
	-- direction does not depend on it: with My Assignments Follow Blizzard's Totem Bar on, the
	-- session's first look at the bar is taken here, where the first write would have been
	if self.opt.totemSetsSyncAssignments == false then
		if not page1Actual and self:HasTotemBar() then self:AdoptTotemBarAssignments() end
		return
	end
	if not self:HasTotemBar() or InCombatLockdown() then
		self.totemSetsSyncPending = self:HasTotemBar() or nil
		return
	end
	-- Blizzard's bar not readable yet (the first moments of a login): the session's first write
	-- waits for it, so the totems on it are seen before anything is written over them
	if not self.totemSetsSyncedOnce and not readPage1() then
		self.totemSetsSyncPending = true
		return
	end
	-- (an adoption below is assigning: the one write follows when it is done)
	if self.totemSetsAdopting then return end
	self.totemSetsSyncPending = nil
	self.totemSetsAdopting = true
	local ok, err = pcall(adoptBeforeWrite, self)
	self.totemSetsAdopting = nil
	if not ok then geterrorhandler()(err) end
	self:WriteTotemSet(1, self:TotemSetSpellsFromAssignments())
	self.totemSetsSyncedOnce = true   -- from here on Blizzard's bar may lead (AdoptTotemBarAssignments)
end

-- The other direction: a totem picked on Blizzard's bar (its own flyouts)
-- becomes the assignment here. Page 1 is read after the client reports a
-- change; an element whose slot differs from the assignment is re-assigned,
-- an emptied slot un-assigns. Elements kept out of Drop All are skipped
-- (their slot is deliberately empty), so is a spell our tables do not know.
-- Not before the first sync of a session (while Call of the Elements Follows My
-- Assignments is on): at login the saved assignments are
-- the truth and Blizzard's bar is brought to them, not the other way round.
-- Out of combat only (assigning writes secure attributes); a change seen in
-- a fight is adopted at regen.
local function totemIndexForSpell(element, spellID)
	for i = 1, SP:GetTotemIndexLimit(element) do
		if sameSpell(SP:GetTotemSpell(element, i), spellID) then return i end
	end
	return nil
end

-- (SyncTotemSetFromAssignments, out of combat) Empty elements take the totem on Blizzard's
-- bar, when My Assignments Follow Blizzard's Totem Bar is on. Elements kept out of Drop All are
-- skipped (their slot is meant to be empty), so is a spell our tables do not know.
function SP:AdoptIntoEmptyAssignments()
	if self.opt.totemSetsAdoptFromBar == false or InCombatLockdown() then return end
	local assignments = ShamanPower_Assignments and ShamanPower_Assignments[self.player]
	if not assignments then return end
	local exclude = {
		[1] = self.opt.excludeEarthFromDropAll, [2] = self.opt.excludeFireFromDropAll,
		[3] = self.opt.excludeWaterFromDropAll, [4] = self.opt.excludeAirFromDropAll,
	}
	local slots
	for element = 1, 4 do
		if not exclude[element] and (assignments[element] or 0) == 0 then
			slots = slots or self:ReadTotemSet(1)
			local idx = slots[element] and totemIndexForSpell(element, slots[element])
			if idx and idx > 0 then
				if SPCompat and SPCompat.Trace then SPCompat.Trace("TOTEMSETS empty element %d takes Blizzard's %s", element, tostring(slots[element])) end
				self:ApplyAssignment(element, idx)
			end
		end
	end
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
	if not self.opt or not self:HasTotemBar() then return false, "the game's totem bar is not available" end
	local loadout = ShamanPower_TotemLoadouts and ShamanPower_TotemLoadouts[index]
	local page = loadout and loadout.setPage
	if page ~= 2 and page ~= 3 then return false, "this loadout is not linked to a Call spell" end
	if boundLoadout(page) ~= loadout then return false, "another loadout is linked to that Call spell" end
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

-- One hidden button per Call (Elements / Ancestors / Spirits), so each has its
-- own key (SHAMANPOWER_CALL_* in Key Bindings, see SP.KeybindButtons).
-- Made from SetupKeybindings, which only runs out of combat.
local CALL_BUTTONS = { "ShamanPowerCallElementsBtn", "ShamanPowerCallAncestorsBtn", "ShamanPowerCallSpiritsBtn" }
function SP:CreateTotemSetButtons()
	if not haveAPI() or InCombatLockdown() then return end
	for page, name in ipairs(CALL_BUTTONS) do
		if not _G[name] then
			local btn = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
			btn:SetSize(1, 1)
			btn:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
			btn:Hide()   -- only pressed by its key
			btn:RegisterForClicks("AnyUp", "AnyDown")
			btn:SetAttribute("type", "spell")
			btn:SetAttribute("spell", SUMMON[page])
		end
	end
end

function SP:BoundLoadoutSummon(index)
	if not self:HasTotemBar() then return nil end
	local loadout = ShamanPower_TotemLoadouts and ShamanPower_TotemLoadouts[index]
	local page = loadout and loadout.setPage
	if (page == 2 or page == 3) and known(SUMMON[page]) then return SUMMON[page] end
end

function SP:BindLoadoutToTotemSet(index, page)
	if not self.opt or not self:HasTotemBar() then return false, "the game's totem bar is not available" end
	local loadout = ShamanPower_TotemLoadouts and ShamanPower_TotemLoadouts[index]
	if not loadout then return false, "loadout does not exist" end
	if page == 0 then page = nil end
	if page ~= nil and page ~= 2 and page ~= 3 then return false, "only Call of the Ancestors or Call of the Spirits can be linked" end
	if page and not known(SUMMON[page]) then return false, "you have not learned that Call spell yet" end
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

-- Add Call of the Ancestors / Spirits Loadout (Loadouts > Loadouts, 3.0.9.5): a loadout named after
-- the spell, tied to its set, holding the four totems the set holds now, first in Everywhere (the
-- one in use stays in use). Its button shows while you know the spell and no loadout is tied to
-- the set (SP:CallLoadoutButtonShown), so deleting the loadout or untying it brings it back.
function SP:CallLoadoutButtonShown(page)
	if not ((page == 2 or page == 3) and self:HasTotemBar() and known(SUMMON[page])) then return false end
	for _, lo in ipairs(ShamanPower_TotemLoadouts or {}) do
		if lo.setPage == page then return false end
	end
	return true
end

-- fromMenu: a loadout's menu > Blizzard Totem Set made it (SP:HasCallLoadout said there was none yet);
-- the right-clicked loadout goes on the set right after, so another loadout on the set doesn't stop it
function SP:AddCallLoadout(page, fromMenu)
	if InCombatLockdown() then return false, "loadouts can't change in combat" end
	if fromMenu then
		if not ((page == 2 or page == 3) and self:HasTotemBar() and known(SUMMON[page])) then
			return false, "you have not learned that Call spell yet"
		end
	elseif not self:CallLoadoutButtonShown(page) then
		return false, "you have not learned that Call spell yet"
	end
	local spells = self:ReadTotemSet(page)
	local loadout = { name = PAGE_NAMES[page], callPage = page, noDropAll = self:CurrentDropAllExcludes() }
	for element = 1, 4 do
		loadout[element] = (spells[element] and totemIndexForSpell(element, spells[element])) or 0
	end
	local icon = (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(SUMMON[page]))
		or (GetSpellTexture and GetSpellTexture(SUMMON[page]))
	loadout.icon = icon
	self:LoadoutTakeOrder(loadout)
	tinsert(ShamanPower_TotemLoadouts, loadout)
	local n = #ShamanPower_TotemLoadouts
	if n > 1 then self:MoveLoadout(n, 1) end
	self:BindLoadoutToTotemSet(1, page)
	self:UpdateLoadoutBar()
	return true
end

-- The set's own loadout was made already (its Add button or a loadout's menu): marked callPage, or
-- one made before the mark that still has the set's name
function SP:HasCallLoadout(page)
	for _, lo in ipairs(ShamanPower_TotemLoadouts or {}) do
		if lo.callPage == page or lo.name == PAGE_NAMES[page] then return true end
	end
	return false
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
	-- (3.0.9.9) another Call picked on Drop All's flyout: the assignments are that Call's, not page 1's
	if self:CallPage() ~= 1 then return end
	-- The bar is "known" once ShamanPower has written or read it. While Call of the Elements
	-- Follows My Assignments is on, the session's first write (SyncTotemSetFromAssignments) is
	-- that moment: until then the bar may still be loading. With it off nothing ever writes the
	-- bar, so the first readable look at it counts instead.
	local known = page1Actual ~= nil or self.opt.totemSetsSyncAssignments == false
	if self.opt.totemSetsAdoptFromBar == false or not self:HasTotemBar() or not known then
		if SPCompat and SPCompat.Trace then SPCompat.Trace("TOTEMSETS adopt skipped: option=%s bar=%s known=%s", tostring(self.opt.totemSetsAdoptFromBar), tostring(self:HasTotemBar()), tostring(page1Actual ~= nil)) end
		return
	end
	-- (a cold login while the game still calls the player "Unknown": not these assignments)
	local me = self.player
	if type(me) ~= "string" or me == "" or me == "Unknown" or me == UNKNOWNOBJECT then return end
	if InCombatLockdown() then self.totemSetsAdoptPending = true return end
	self.totemSetsAdoptPending = nil
	local assignments = ShamanPower_Assignments and ShamanPower_Assignments[self.player]
	if not assignments then return end
	local exclude = {
		[1] = self.opt.excludeEarthFromDropAll, [2] = self.opt.excludeFireFromDropAll,
		[3] = self.opt.excludeWaterFromDropAll, [4] = self.opt.excludeAirFromDropAll,
	}
	local slots = readPage1()
	if not slots then return end   -- (the client can't say yet: nothing changes)
	-- the first look of a session with Call of the Elements Follows My Assignments off: every
	-- totem on the bar is the player's, and a slot the player emptied before this look counts too
	-- (an empty slot never counts on its own, and a pick made before the look is a pick even
	-- when the bar reads empty for a moment)
	local firstLook = page1Actual == nil
	local before = page1Actual or {}
	page1Actual = slots
	local edited, cleared = editedSlots, clearedSlots
	editedSlots, clearedSlots = {}, {}
	if SPCompat and SPCompat.Trace then
		SPCompat.Trace("TOTEMSETS adopt read: E=%s F=%s W=%s A=%s  assigned %s/%s/%s/%s", tostring(slots[1]), tostring(slots[2]), tostring(slots[3]), tostring(slots[4]),
			tostring(assignments[1]), tostring(assignments[2]), tostring(assignments[3]), tostring(assignments[4]))
	end
	for element = 1, 4 do
		-- only a slot that CHANGED since ShamanPower last wrote or read it is the player's pick
		if not exclude[element] and (slotChanged(slots[element], before[element]) or (firstLook and cleared[element])) then
			local current = assignments[element] or 0
			local want
			if slots[element] then
				want = totemIndexForSpell(element, slots[element])   -- nil: not one of ours, leave it
			elseif edited[element] then
				want = 0   -- the player emptied that slot on Blizzard's bar
			else
				want = nil   -- an empty read with no edit (a reload, a loading screen): not a choice
			end
			if want ~= nil and want ~= current then
				if SPCompat and SPCompat.Trace then SPCompat.Trace("TOTEMSETS adopt element %d: %d -> %d", element, current, want) end
				self:ApplyAssignment(element, want)
			end
		end
	end
end

-- A newer choice made in ShamanPower (a loadout): a pick on Blizzard's bar still waiting
-- to be taken is dropped, so it never undoes that choice
function SP:ForgetPendingBarPicks()
	self.totemSetsAdoptPending = nil
	changedPages[1] = nil
	editedSlots, clearedSlots = {}, {}
end

-- What a flyout pick writes into Blizzard's bar: the page-1 action slot of an
-- element and the spell to put there (0 = leave the slot empty). nil when the
-- bar should be left alone (no API, sync turned off, element kept out of Drop
-- All, or a totem the slot does not take). Used by the flyouts' "multispell"
-- helpers, which are the only way to write the bar during a fight.
function SP:TotemBarSlotSpell(element, totemIndex)
	if not haveAPI() then return nil end
	-- (3.0.9.9) the Call the bar is on (Drop All's flyout); the sync option is Call of the Elements' only
	local page = self:CallPage()
	if page == 1 and self.opt.totemSetsSyncAssignments == false then return nil end
	local exclude = {
		[1] = self.opt.excludeEarthFromDropAll, [2] = self.opt.excludeFireFromDropAll,
		[3] = self.opt.excludeWaterFromDropAll, [4] = self.opt.excludeAirFromDropAll,
	}
	if exclude[element] then return nil end
	local action = setActionSlot(page, element)
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
	if not loadout then print("|cff0070ddShamanPower:|r no loadout " .. tostring(index)) return end
	local spells = {}
	for element = 1, 4 do
		local idx = loadout[element] or 0
		if idx > 0 then spells[element] = self:GetTotemSpell(element, idx) end
	end
	local written, skipped, reason = self:WriteTotemSet(page, spells)
	if reason then print("|cff0070ddShamanPower:|r " .. reason) return end
	local name = loadout.name or ("Loadout " .. index)
	print(string.format("|cff0070ddShamanPower:|r '%s' sent to %s (%d slot%s updated%s)", name, pageName(page),
		written, written == 1 and "" or "s", skipped > 0 and (", " .. skipped .. " not allowed in that slot") or ""))
	self:UpdateDropAllButton()
end

-- ---------------------------------------------------------------------------
-- (3.0.9.9, A90) Call Flyout on Drop All (Totem Bar > Clicks; a Discord ask). Drop All opens a
-- flyout of the Calls that are not on it, the totem flyouts' kind: it leaves out the one on the
-- button, and opens on hover, or on right-click with Flyout Requires Right-Click on (then that
-- right-click casts no Totemic Recall; Recall keeps its own button). Picking a Call puts it on Drop
-- All, and the four assignments follow it: the bar shows and drops that Call's totems, and a totem
-- picked in an element's flyout becomes that Call's totem (a loadout linked to it follows).
-- Call of the Elements is left alone while another Call is picked, and comes back with it.
--
-- The Call the bar is on is the character's own (db.char.callPage, like the assignments), so a
-- profile never pulls it out of step with them; turning the switch off brings Elements back first.
--
-- In a fight: the flyout's buttons are secure, children of a holder frame over Drop All (the totem
-- flyouts' snippets: show, assignment, relayout, leave), and Drop All's own scripts are wrapped while
-- the switch is on (SecureHandlerWrapScript: nothing of today's button changes without it). A pick
-- clicks a secure router (SPCALLR<page>) that keeps the totems the bar casts now as the old Call's,
-- puts the new Call on Drop All and its totems on the four buttons, and points the flyout pick
-- helpers (SPFM) at the new Call's slots. The assignments follow when the fight ends, as a flyout
-- pick's do (pendingAssignments); the icons change at once.
-- ---------------------------------------------------------------------------

-- the Call the bar is on: 1 (Elements) unless another was picked on Drop All's flyout
function SP:CallPage()
	local c = self.db and self.db.char
	local p = c and c.callPage
	return (p == 2 or p == 3) and p or 1
end

-- the switch, and what it needs (Blizzard-Style Flyout Arrows open flyouts their own way: not there)
function SP:CallFlyoutOn()
	local o = self.opt
	if not (o and o.dropAllCallFlyout == true and o.dropAllUsesTotemSets ~= false and o.showTotemFlyouts) then return false end
	if self:IsOff() or self:FlyoutBoxMode() or not self:HasTotemSets() then return false end
	if self.UsingBlizzardTotemBar and self:UsingBlizzardTotemBar() then return false end
	return true
end

local function excludedElement(self, element)
	local keys = self.DropAllExcludeKeys
	return (keys and self.opt[keys[element]]) and true or false
end

-- (3.0.9.12, the owner) Every Call has its own four totems, set on Totem Bar > Bar, and the bar takes all
-- four with the Call. An element Drop All skips has its game slot kept empty (so the Call never drops it),
-- so that Call's totem of it is kept here: db.char.callKept[page][element]. A Call not given one yet takes
-- the bar's totem of that element the first time it is asked (nothing on screen changes; never Empty).
local function keptTotem(self, page, element)
	local c = self.db and self.db.char
	if not c then return nil end
	local k = c.callKept and c.callKept[page]
	if k and k[element] ~= nil then return k[element] end   -- (0: Empty, picked with Show Empty Choice on)
	local loadout = boundLoadout(page)
	if loadout and (loadout[element] or 0) > 0 then return loadout[element] end
	local a = ShamanPower_Assignments and ShamanPower_Assignments[self.player]
	local idx = a and a[element] or 0
	if idx <= 0 then return nil end
	c.callKept = c.callKept or {}
	c.callKept[page] = c.callKept[page] or {}
	c.callKept[page][element] = idx
	return idx
end
local function setKept(self, page, element, idx)
	local c = self.db and self.db.char
	if not c or not idx or idx < 0 then return end
	c.callKept = c.callKept or {}
	c.callKept[page] = c.callKept[page] or {}
	c.callKept[page][element] = idx
end

-- { [element] = totemIndex, 0 = empty } of a page as the game holds it; nil while unreadable. A
-- spell our tables do not know leaves its element out (nil): that assignment stays as it is.
local function pageIndexes(page)
	local slots = readPageSafe(page)
	if not slots then return nil end
	local t = {}
	for element = 1, 4 do
		local id = slots[element]
		if id then t[element] = totemIndexForSpell(element, id) else t[element] = 0 end
	end
	return t
end

-- the name a totem button casts for (element, totem index), as the bar sets it; "" = none
local function castNameFor(element, idx)
	if not idx or idx <= 0 then return "" end
	local id = SP:GetTotemSpell(element, idx)
	if not id then return "" end
	local name = GetSpellInfo(id)
	if SPCompat.HasTotemCastAliases(id) then name = SPCompat.TotemCastName(id) end
	return name or ""
end

-- Sync's page for another Call: the assignments into it. A loadout linked to that Call leads the
-- page (it is written back over it on many refreshes), so it takes the assignments first.
function CALL.write(self, page)
	local loadout, index = boundLoadout(page)
	if not loadout then
		self:WriteTotemSet(page, self:TotemSetSpellsFromAssignments())
		return
	end
	local a = ShamanPower_Assignments and ShamanPower_Assignments[self.player] or {}
	local changed = false
	for element = 1, 4 do
		if not excludedElement(self, element) then
			local idx = a[element] or 0
			if (loadout[element] or 0) ~= idx then loadout[element], changed = idx, true end
		end
	end
	if changed then refreshLoadouts() end
	CALL.writing = true
	local ok, err = pcall(self.SyncBoundLoadout, self, index)
	CALL.writing = nil
	if not ok then geterrorhandler()(err) end
end

-- four assignments at once (an element left out keeps its own), then one refresh: one at a time,
-- each refresh would write a half-switched bar into the Call
local function applyCallAssignments(self, idx, emptyOK)
	ShamanPower_Assignments[self.player] = ShamanPower_Assignments[self.player] or {}
	local a = ShamanPower_Assignments[self.player]
	local changed = {}
	for element = 1, 4 do
		-- (3.0.9.12) an element Drop All skips takes its Call's own totem too (keptTotem), never an Empty
		local skip = excludedElement(self, element) and (idx[element] or 0) == 0 and not (emptyOK and emptyOK[element])
		if idx[element] ~= nil and not skip and (a[element] or 0) ~= idx[element] then
			a[element] = idx[element]
			changed[#changed + 1] = element
		end
	end
	if #changed == 0 then return false end
	self:UpdateMiniTotemBar()
	self:UpdateDropAllButton()   -- (and Sync: the Call the bar is on, which holds these already)
	self:UpdateSPMacros()
	for element = 1, 4 do
		self:UpdateFlyoutVisibility(element)
		if self.ShowEmptySlotArt then self:ShowEmptySlotArt(element, (a[element] or 0) == 0) end
	end
	for _, element in ipairs(changed) do
		self:SendMessage("ASSIGN " .. self.player .. " " .. element .. " " .. (a[element] or 0))
	end
	return true
end

-- Put a Call on Drop All, out of a fight: the bar leaves its Call holding the assignments (a pick
-- not written yet lands now) and takes the new Call's totems as they are in the game.
function SP:SelectCall(page)
	page = (page == 2 or page == 3) and page or 1
	if InCombatLockdown() or not self:HasTotemBar() or not (self.db and self.db.char) then return false end
	if page ~= 1 and not self:KnownTotemSetPages()[page] then return false end
	local cur = self:CallPage()
	if page == cur then CALL.queue() return true end
	local target = pageIndexes(page)
	if not target then return false end   -- (the game can't say yet: nothing changes)
	-- (3.0.9.12) an element Drop All skips: the old Call keeps the bar's, the bar takes the new Call's
	local held = ShamanPower_Assignments and ShamanPower_Assignments[self.player] or {}
	local emptyOK = {}
	for element = 1, 4 do
		if excludedElement(self, element) then
			local newIdx = keptTotem(self, page, element)
			setKept(self, cur, element, held[element])
			target[element] = newIdx
			emptyOK[element] = newIdx == 0   -- (an Empty that Call was given on purpose)
		end
	end
	self:SyncTotemSetFromAssignments()
	if page == 1 then
		self.db.char.callPage = nil
		page1Actual = readPage1() or page1Actual   -- what Elements holds is known: nothing on it is a new pick
	else
		self.db.char.callPage = page
	end
	if not applyCallAssignments(self, target, emptyOK) then self:UpdateDropAllButton() end
	if self.RefreshTotemBarHelpers then self:RefreshTotemBarHelpers() end
	CALL.queue()
	return true
end

-- The switch (Totem Bar > Clicks), out of a fight. Off while another Call is picked: Elements first.
function SP:SetCallFlyout(on)
	if InCombatLockdown() or not self.opt then return false end
	if not on and self:CallPage() ~= 1 then self:SelectCall(1) end
	self.opt.dropAllCallFlyout = on and true or nil
	self:UpdateDropAllButton()
	return true
end

-- (3.0.9.12, A98) Totem Bar > Bar shows the three Calls, a line each, and sets their totems one at a time.
-- The Call the bar is on holds the assignments (it is the bar); another Call holds what its set page holds
-- in the game, or its linked loadout (which leads that page); a Call not learned yet keeps the totems picked
-- for it early (db.char.callEarly[page]) and gets them the moment it is learned (ApplyEarlyCallPicks).
-- { [element] = totem index, 0 = empty }; nil while the game can't say (a page not readable yet).
-- Second return: true for a Call not learned yet (its picks wait).
function SP:CallTotems(page)
	local t = {}
	if page == self:CallPage() then
		local a = ShamanPower_Assignments and ShamanPower_Assignments[self.player] or {}
		for element = 1, 4 do t[element] = a[element] or 0 end
		return t
	end
	local function kept(tt)
		if not tt then return tt end
		for element = 1, 4 do
			if excludedElement(self, element) then tt[element] = keptTotem(self, page, element) or tt[element] end
		end
		return tt
	end
	local loadout = boundLoadout(page)
	if loadout then
		for element = 1, 4 do t[element] = loadout[element] or 0 end
		return kept(t)
	end
	if page ~= 1 and not self:KnownTotemSetPages()[page] then
		local early = self.db and self.db.char and self.db.char.callEarly and self.db.char.callEarly[page]
		for element = 1, 4 do t[element] = early and early[element] or 0 end
		return kept(t), true
	end
	return kept(pageIndexes(page))
end

-- One totem of one Call (0: empty), out of a fight. False when nothing changed: in a fight, or the
-- game's slot can't take it (a totem not learned yet).
function SP:SetCallTotem(page, element, idx)
	if InCombatLockdown() or not self:HasTotemBar() then return false end
	idx = idx or 0
	if page == self:CallPage() then return self:ApplyAssignment(element, idx) end
	if excludedElement(self, element) then
		-- (its game slot stays empty: the Call keeps it here, and the bar takes it with the Call)
		if idx < 0 then return false end
		setKept(self, page, element, idx)
		return true
	end
	local loadout, index = boundLoadout(page)
	if loadout then
		loadout[element] = idx
		refreshLoadouts()
		self:SyncBoundLoadout(index)
		return true
	end
	if page ~= 1 and not self:KnownTotemSetPages()[page] then
		local c = self.db and self.db.char
		if not c then return false end
		c.callEarly = c.callEarly or {}
		c.callEarly[page] = c.callEarly[page] or {}
		c.callEarly[page][element] = idx
		return true
	end
	local spell = idx > 0 and self:GetTotemSpell(element, idx) or false
	local _, skipped, reason = self:WriteTotemSet(page, { [element] = spell })
	return reason == nil and (skipped or 0) == 0
end

-- A Call learned (SPELLS_CHANGED): the totems picked for it early go into it, out of a fight (else the
-- next SPELLS_CHANGED or the fight's end). A linked loadout takes them, as any pick for it does.
function SP:ApplyEarlyCallPicks()
	local c = self.db and self.db.char
	local early = c and c.callEarly
	if not early or InCombatLockdown() or not self:HasTotemBar() then return end
	for page = 2, 3 do
		local picks = early[page]
		if picks and self:KnownTotemSetPages()[page] then
			for element = 1, 4 do
				if picks[element] ~= nil and excludedElement(self, element) then
					setKept(self, page, element, picks[element])
					picks[element] = nil
				end
			end
			local loadout, index = boundLoadout(page)
			if loadout then
				for element = 1, 4 do if picks[element] ~= nil then loadout[element] = picks[element] end end
				refreshLoadouts()
				self:SyncBoundLoadout(index)
			else
				local spells = {}
				for element = 1, 4 do
					local idx = picks[element]
					if idx ~= nil then spells[element] = idx > 0 and self:GetTotemSpell(element, idx) or false end
				end
				self:WriteTotemSet(page, spells)
			end
			early[page] = nil
		end
	end
	if not next(early) then c.callEarly = nil end
end

-- A Call picked in a fight: the secure router did the casting side; here the icons and what
-- waits for the fight's end (the old Call keeps what the bar has now, the new one's go pending)
local function pickedInCombat(self, page)
	local cur = self:CallPage()
	if page == cur then return end
	local now = {}
	for element = 1, 4 do now[element] = self:AssignedIndex(element) end
	CALL.sets[cur] = now
	-- (3.0.9.12) an element Drop All skips: the old Call keeps the bar's; the new Call's goes on the bar when
	-- the fight ends (its button keeps casting the one it has until then)
	for element = 1, 4 do
		if excludedElement(self, element) then
			CALL.keptAfterFight = CALL.keptAfterFight or {}
			setKept(self, cur, element, CALL.keptAfterFight[element] or now[element])
			CALL.keptAfterFight[element] = keptTotem(self, page, element)
		end
	end
	if page == 1 then self.db.char.callPage = nil else self.db.char.callPage = page end
	local target = CALL.sets[page]
	if target then
		self.pendingAssignments = self.pendingAssignments or {}
		for element = 1, 4 do
			local idx = target[element]
			-- (as the router: an element kept out of Drop All, or Air while twisting, keeps its own)
			if idx ~= nil and not excludedElement(self, element) and not (element == 4 and self.opt.enableTotemTwisting) then
				self.pendingAssignments[element] = idx
				local b = self.totemButtons and self.totemButtons[element]
				if b and b.icon then
					local icons = self.TotemIcons and self.TotemIcons[element]
					b.icon:SetTexture((idx > 0 and icons and icons[idx]) or self.ElementIcons[element])
				end
				if self.ShowEmptySlotArt then self:ShowEmptySlotArt(element, idx == 0) end
				self:MarkAssignedInFlyout(element)
			end
		end
	end
	local d = _G.ShamanPowerAutoDropAll
	local icon = d and (d.icon or _G.ShamanPowerAutoDropAllIcon)
	if icon and not (self.DropAllOwnIcon and self:DropAllOwnIcon()) then icon:SetTexture(spellIcon(SUMMON[page]) or 136024) end
	if self.UpdateActiveTotemOverlays then self:UpdateActiveTotemOverlays() end
end

-- a Call button's click (PostClick: after the router)
function SP:CallFlyoutPicked(page)
	if InCombatLockdown() then pickedInCombat(self, page) return end
	if self:SelectCall(page) then return end
	-- the game couldn't say what that Call holds: the router's changes go, the bar casts as before
	self:UpdateMiniTotemBar()
	self:UpdateDropAllButton()
	for element = 1, 4 do self:UpdateFlyoutVisibility(element) end
	if self.RefreshTotemBarHelpers then self:RefreshTotemBarHelpers() end
end

-- The snippets. The flyout's are the totem flyouts' (ShamanPower.lua): show, assignment (the one on
-- Drop All hides), relayout (the rest close the gap), leave (WoW: Forever's form).
CALL.SHOW = [[
	if message then
		if not self:GetAttribute("isCurrentAssignment") and not self:GetAttribute("flyoutHidden") then self:Show() end
	else
		self:Hide()
	end
]]
CALL.ASSIGNMENT = [[
	self:SetAttribute("isCurrentAssignment", message == self:GetAttribute("mySpell"))
]]
CALL.RELAYOUT = [[
	if self:GetAttribute("isCurrentAssignment") or self:GetAttribute("flyoutHidden") then return end
	local parent = self:GetParent()
	local size = parent:GetAttribute("flyoutButtonSize") or 28
	local spacing = parent:GetAttribute("flyoutSpacing") or 0
	local myIndex = self:GetAttribute("myTotemIndex") or 0
	local before = 0
	local children = newtable(parent:GetChildren())
	for i = 1, #children do
		local c = children[i]
		if c:GetAttribute("isFlyoutButton") and (c:GetAttribute("myTotemIndex") or 0) < myIndex
			and not c:GetAttribute("isCurrentAssignment") and not c:GetAttribute("flyoutHidden") then
			before = before + 1
		end
	end
	local along = spacing + before * (size + spacing)
	self:ClearAllPoints()
	if parent:GetAttribute("flyoutIsHorizontal") then
		if parent:GetAttribute("isVerticalLeft") then
			self:SetPoint("RIGHT", parent, "LEFT", -along, 0)
		else
			self:SetPoint("LEFT", parent, "RIGHT", along, 0)
		end
	elseif parent:GetAttribute("flyoutGoesBelow") then
		self:SetPoint("TOP", parent, "BOTTOM", 0, -along)
	else
		self:SetPoint("BOTTOM", parent, "TOP", 0, along)
	end
]]
CALL.LEAVE = [[
	local parent = self:GetParent()
	if parent:IsUnderMouse() then return end
	local children = newtable(parent:GetChildren())
	for i = 1, #children do
		local c = children[i]
		if c ~= self and c:GetAttribute("spFlyoutProtocol") and c:IsShown() and c:IsUnderMouse() then return end
	end
	parent:ChildUpdate("show", false)
]]
-- Drop All's own scripts, wrapped (control = the holder)
CALL.WRAP_ENTER = [[
	if control:GetAttribute("OpenMenu") == "mouseover" then control:ChildUpdate("show", true) end
]]
CALL.WRAP_LEAVE = [[
	if self:IsUnderMouse() then return end
	local children = newtable(control:GetChildren())
	for i = 1, #children do
		local c = children[i]
		if c:GetAttribute("spFlyoutProtocol") and c:IsShown() and c:IsUnderMouse() then return end
	end
	control:ChildUpdate("show", false)
]]
CALL.WRAP_CLICK = [[
	if control:GetAttribute("OpenMenu") == "click" and button == control:GetAttribute("spOpener") then
		control:ChildUpdate("show", true)
		return false
	end
]]
-- The router: one per Call (spPage). hdr = the holder, which keeps the state: spPage (the Call on
-- Drop All), call<p> (each Call's spell), p<p>e<e> (each Call's totem names, "" = none), keep<e>
-- (an element kept out of Drop All), tb<e> / dropall / spfm<i> (the frames).
CALL.ROUTER = [[
	local hdr = self:GetFrameRef("hdr")
	if not hdr then return end
	local page = self:GetAttribute("spPage")
	local cur = hdr:GetAttribute("spPage") or 1
	if page == cur then hdr:ChildUpdate("show", false) return end
	for e = 1, 4 do
		local b = hdr:GetFrameRef("tb" .. e)
		if b then hdr:SetAttribute("p" .. cur .. "e" .. e, b:GetAttribute("spell1") or "") end
	end
	hdr:SetAttribute("spPage", page)
	local d = hdr:GetFrameRef("dropall")
	if d then d:SetAttribute("spell1", hdr:GetAttribute("call" .. page)) end
	for e = 1, 4 do
		local b = hdr:GetFrameRef("tb" .. e)
		if b and not hdr:GetAttribute("keep" .. e) and b:GetAttribute("type1") ~= "macro" then
			local s = hdr:GetAttribute("p" .. page .. "e" .. e)
			if s == "" then s = nil end
			b:SetAttribute("spell1", s)
			if b:GetAttribute("spSecureResort") then
				b:ChildUpdate("assignment", s)
				b:ChildUpdate("relayout", true)
			end
		end
	end
	local n = hdr:GetAttribute("spfmN") or 0
	for i = 1, n do
		local m = hdr:GetFrameRef("spfm" .. i)
		if m and not m:GetAttribute("spNever") then
			local base = m:GetAttribute("spBase")
			if base and not (page == 1 and m:GetAttribute("spPage1Off")) then
				m:SetAttribute("type", "multispell")
				m:SetAttribute("action", base + (page - 1) * 4)
			else
				m:SetAttribute("type", nil)
			end
		end
	end
	hdr:ChildUpdate("assignment", hdr:GetAttribute("call" .. page))
	hdr:ChildUpdate("relayout", true)
	hdr:ChildUpdate("show", false)
]]
SP.CallFlyoutSnippets = CALL   -- (the tests read the snippets)

local function callTooltip(btn)
	if not (SP.opt and SP.opt.ShowTooltips) then return end
	GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
	if btn.spSpell then GameTooltip:SetSpellByID(btn.spSpell) end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("|cff00ff00Click:|r Put it on Drop All. Your totems follow it.", 1, 1, 1, true)
	GameTooltip:Show()
end

-- the holder, its three Call buttons and their routers: made once, out of a fight
local function build(self, d)
	if CALL.header then return CALL.header end
	local h = CreateFrame("Frame", "ShamanPowerCallFlyout", d, "SecureHandlerBaseTemplate")
	h:SetAllPoints(d)
	h:EnableMouse(false)
	for page = 1, 3 do
		local b = CreateFrame("Button", "ShamanPowerCallFlyoutBtn" .. page, h, "SPFlyoutButtonTemplate")
		b:Hide()
		b:SetIgnoreParentAlpha(true)
		self:SetSnippet(b, "_childupdate-show", CALL.SHOW)
		self:SetSnippet(b, "_childupdate-assignment", CALL.ASSIGNMENT)
		self:SetSnippet(b, "_childupdate-relayout", CALL.RELAYOUT)
		self:SetSnippet(b, "_onleave", CALL.LEAVE)
		b:SetAttribute("spFlyoutProtocol", true)
		b:SetAttribute("isFlyoutButton", true)
		b:SetAttribute("myTotemIndex", page)
		b:SetAttribute("mySpell", SUMMON[page])
		b:SetAttribute("type1", "macro")
		b:SetAttribute("macrotext1", "/click SPCALLR" .. page)
		b:SetAttribute("type2", "macro")
		b:SetAttribute("macrotext2", "/click SPCALLR" .. page)
		b.icon = _G[b:GetName() .. "Icon"]
		b.spPage, b.spSpell = page, SUMMON[page]
		b:HookScript("OnEnter", callTooltip)
		b:HookScript("OnLeave", function() GameTooltip:Hide() end)
		b:SetScript("PostClick", function(btn) SP:CallFlyoutPicked(btn.spPage) end)
		CALL.buttons[page] = b

		local r = CreateFrame("Button", "SPCALLR" .. page, h, "SecureHandlerClickTemplate")
		r:SetSize(1, 1)
		r:SetPoint("CENTER", h, "CENTER")
		r:EnableMouse(false)
		r:RegisterForClicks("AnyUp", "AnyDown")
		r:SetAttribute("spPage", page)
		r:SetFrameRef("hdr", h)
		r:SetAttribute("_onclick", CALL.ROUTER)
		CALL.routers[page] = r
	end
	CALL.header = h
	SP.callFlyoutButtons, SP.callFlyoutHeader = CALL.buttons, h   -- (Click Through gathers them)
	return h
end

local WRAPPED = { "OnEnter", "OnLeave", "OnClick" }
local function wrap(d, h)
	if CALL.wrapped then return end
	SecureHandlerWrapScript(d, "OnEnter", h, CALL.WRAP_ENTER)
	SecureHandlerWrapScript(d, "OnLeave", h, CALL.WRAP_LEAVE)
	SecureHandlerWrapScript(d, "OnClick", h, CALL.WRAP_CLICK)
	CALL.wrapped = true
end
local function unwrap(d)
	if not CALL.wrapped then return end
	for _, script in ipairs(WRAPPED) do pcall(SecureHandlerUnwrapScript, d, script) end
	CALL.wrapped = nil
end

-- the Call buttons placed as the relayout snippet places them (out of a fight, and where the
-- snippets cannot run): every Call but the one on Drop All, in order, away from the screen edge
local function layout(h, current)
	local size = h:GetAttribute("flyoutButtonSize") or 28
	local n = 0
	for page = 1, 3 do
		local b = CALL.buttons[page]
		local on = page ~= current and b.spKnown
		b:SetAttribute("isCurrentAssignment", page == current)
		b:SetAttribute("flyoutHidden", not b.spKnown)   -- (a Call not learned yet: never in the flyout)
		if on then
			local along = n * size
			n = n + 1
			b:ClearAllPoints()
			if h:GetAttribute("flyoutIsHorizontal") then
				if h:GetAttribute("isVerticalLeft") then b:SetPoint("RIGHT", h, "LEFT", -along, 0)
				else b:SetPoint("LEFT", h, "RIGHT", along, 0) end
			elseif h:GetAttribute("flyoutGoesBelow") then
				b:SetPoint("TOP", h, "BOTTOM", 0, -along)
			else
				b:SetPoint("BOTTOM", h, "TOP", 0, along)
			end
		end
		b:Hide()
	end
end

-- Out of a fight: builds, wraps or unwraps, and sets every attribute the snippets read from what
-- the game and the assignments hold now. The Lua copy of each Call's totems (for a pick in a fight)
-- comes from the same reads.
function SP:RefreshCallFlyout()
	CALL.queued = nil
	if InCombatLockdown() then CALL.pending = true return end
	CALL.pending = nil
	local d = _G.ShamanPowerAutoDropAll
	if not d or not self.opt then return end
	-- the switch went off, or Drop All stopped casting the Calls: Elements back first
	if self:CallPage() ~= 1 and (self.opt.dropAllCallFlyout ~= true or self.opt.dropAllUsesTotemSets == false)
		and haveAPI() and not CALL.reverting then
		CALL.reverting = true
		local ok, err = pcall(self.SelectCall, self, 1)
		CALL.reverting = nil
		if not ok then geterrorhandler()(err) end
	end
	if not self:CallFlyoutOn() then
		unwrap(d)
		for _, b in pairs(CALL.buttons) do b:Hide() end
		return
	end
	local h = build(self, d)
	if h:GetParent() ~= d then h:SetParent(d) end
	h:ClearAllPoints()
	h:SetAllPoints(d)
	local cur = self:CallPage()
	local pages = self:KnownTotemSetPages()
	-- how it opens: as the totem buttons' flyouts, and the click that would cast Totemic Recall
	h:SetAttribute("OpenMenu", self:FlyoutOpensOnRightClick() and "click" or "mouseover")
	h:SetAttribute("spOpener", d.spClickFlipped and "LeftButton" or "RightButton")
	-- which way: the totem flyouts' way
	h:SetAttribute("flyoutButtonSize", self:TotemFlyoutButtonSize())
	h:SetAttribute("flyoutSpacing", 0)
	h:SetAttribute("flyoutIsHorizontal", not self:IsTotemBarHorizontal())
	h:SetAttribute("isVerticalLeft", (self.opt.layout == "VerticalLeft") and not self:CompactActive())
	h:SetAttribute("flyoutGoesBelow", self:FlyoutGoesBelow(d))
	-- what the router sets
	h:SetAttribute("spPage", cur)
	h:SetFrameRef("dropall", d)
	local a = ShamanPower_Assignments and ShamanPower_Assignments[self.player] or {}
	for page = 1, 3 do
		h:SetAttribute("call" .. page, pages[page] or pages[1])
		local idx
		if page == cur then
			idx = {}
			for element = 1, 4 do idx[element] = a[element] or 0 end
		else
			idx = pageIndexes(page) or CALL.sets[page]
		end
		CALL.sets[page] = idx
		for element = 1, 4 do
			local name = idx and castNameFor(element, idx[element]) or ""
			h:SetAttribute("p" .. page .. "e" .. element, name)
		end
	end
	for element = 1, 4 do
		local tb = self.totemButtons and self.totemButtons[element]
		if tb then h:SetFrameRef("tb" .. element, tb) end
		h:SetAttribute("keep" .. element, excludedElement(self, element) or nil)
	end
	-- the flyout pick helpers (SPFM): each one's Call of the Elements slot; the router adds 4 per Call
	local n = 0
	local syncOff = self.opt.totemSetsSyncAssignments == false
	for element = 1, 4 do
		local flyout = self.totemFlyouts and self.totemFlyouts[element]
		for _, fb in ipairs(flyout and flyout.allButtons or {}) do
			local m = _G["SPFM" .. element .. "_" .. tostring(fb.totemIndex)]
			if m then
				n = n + 1
				local base = setActionSlot(1, element)
				local spell
				if fb.totemIndex == 0 then
					spell = 0
				else
					local id = self:GetTotemSpell(element, fb.totemIndex)
					spell = id and resolveInSlot(allowedInSlot(element), id)
				end
				m:SetAttribute("spBase", base)
				m:SetAttribute("spNever", (excludedElement(self, element) or not base or spell == nil) or nil)
				m:SetAttribute("spPage1Off", syncOff or nil)
				h:SetFrameRef("spfm" .. n, m)
			end
		end
	end
	h:SetAttribute("spfmN", n)
	-- the Call buttons: the known ones, their icons and size, the one on Drop All left out
	local size = self:TotemFlyoutButtonSize()
	for page = 1, 3 do
		local b = CALL.buttons[page]
		b.spKnown = pages[page] and true or false
		b:SetAttribute("mySpell", pages[page] or SUMMON[page])
		b:SetSize(size, size)
		if b.icon then b.icon:SetTexture(spellIcon(SUMMON[page]) or 136024) end
	end
	layout(h, cur)
	wrap(d, h)
end

function CALL.queue()
	if CALL.queued then return end
	CALL.queued = true
	C_Timer.After(0, function() if SP.opt then SP:RefreshCallFlyout() else CALL.queued = nil end end)
end

-- what else moves the flyout: how flyouts open, the click swap, their direction and size
for _, name in ipairs({ "UpdateTotemFlyoutEnabled", "ApplyClickSwap", "SetupTotemFlyouts", "RefreshTotemBarHelpers" }) do
	if type(SP[name]) == "function" then hooksecurefunc(SP, name, function() CALL.queue() end) end
end

-- A loadout linked to the Call the bar is on, changed in Loadouts: the bar takes it (not when the
-- bar wrote it: CALL.write)
hooksecurefunc(SP, "SyncBoundLoadout", function(self, index)
	if CALL.writing or InCombatLockdown() then return end
	local loadout = ShamanPower_TotemLoadouts and ShamanPower_TotemLoadouts[index]
	local page = loadout and loadout.setPage
	if not page or page ~= self:CallPage() or boundLoadout(page) ~= loadout then return end
	local idx = {}
	for element = 1, 4 do idx[element] = loadout[element] or 0 end
	applyCallAssignments(self, idx)
end)

-- A loadout chosen while another Call is picked: loadouts are Call of the Elements' (a linked one
-- owns its Call), so Elements comes back first and the loadout lands there, as always
if type(SP.ApplyLoadout) == "function" then
	local applyLoadout = SP.ApplyLoadout
	SP.ApplyLoadout = function(self, ...)
		if not InCombatLockdown() and self.CallPage and self:CallPage() ~= 1 then self:SelectCall(1) end
		return applyLoadout(self, ...)
	end
end

-- a fight's end: what changed in it (a pick, a Call) is set out again
CALL.ev = CreateFrame("Frame")
CALL.ev:RegisterEvent("PLAYER_REGEN_ENABLED")
CALL.ev:SetScript("OnEvent", function()
	if CALL.pending or (SP.CallFlyoutOn and SP:CallFlyoutOn()) then CALL.queue() end
end)

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
		CALL.queue()   -- (3.0.9.9) no Call flyout either
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
		btn:SetAttribute("spell1", pages[self:CallPage()] or pages[1])   -- (3.0.9.9) the Call picked on its flyout
		btn:SetAttribute("shift-spell1", pages[2] or pages[1])
		btn:SetAttribute("ctrl-spell1", pages[3] or pages[1])
		btn:SetAttribute("alt-spell1", pages[1])
		btn:SetAttribute("spell2", known(RECALL) and RECALL or nil)
		self.dropAllLastMacro = "totemsets"
	end
	local icon = btn.icon or _G["ShamanPowerAutoDropAllIcon"]
	if icon then icon:SetTexture((self.DropAllOwnIcon and self:DropAllOwnIcon()) or spellIcon(pages[self:CallPage()] or pages[1]) or 136024) end
	CALL.queue()   -- (3.0.9.9) the Call flyout follows
	return true
end

function SP:DropAllTotemSetsTooltip(button)
	if not self.opt.ShowTooltips then return end
	local pages = self:KnownTotemSetPages()
	GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
	GameTooltip:AddLine("Drop All Totems", 1, 0.8, 0)
	-- (3.0.9.9) a plain click casts the Call picked on Drop All's flyout; Alt-click is always Elements
	local cp = self:CallPage()
	local mods = { "Click", "Shift-click", "Ctrl-click" }
	if cp ~= 1 then mods = { "Alt-click", cp == 2 and "Click, Shift-click" or "Shift-click", cp == 3 and "Click, Ctrl-click" or "Ctrl-click" } end
	for page = 1, 3 do
		if pages[page] then
			GameTooltip:AddLine(" ", 1, 1, 1)
			GameTooltip:AddLine(string.format("|cff00ccff%s:|r %s", mods[page], pageName(page)), 1, 1, 1)
			local set = self:ReadTotemSet(page)
			for _, element in ipairs({ 1, 2, 3, 4 }) do
				local id = set[element]
				GameTooltip:AddLine(string.format("  %s: %s", self.Elements[element] or element, id and spellName(id) or "|cff888888empty|r"), 0.8, 0.8, 0.8)
			end
		end
	end
	GameTooltip:AddLine(" ", 1, 1, 1)
	local callFlyout = self:CallFlyoutOn()
	local clickOpens = callFlyout and self:FlyoutOpensOnRightClick()
	if clickOpens then
		GameTooltip:AddLine("|cff00ccffRight-click:|r Pick another Call", 1, 1, 1)
	elseif known(RECALL) then
		GameTooltip:AddLine("|cff00ccffRight-click:|r " .. (spellName(RECALL) or "Totemic Recall"), 1, 1, 1)
	end
	if callFlyout and not clickOpens then GameTooltip:AddLine("Hover to pick another Call", 0.5, 0.5, 0.5) end
	if callFlyout then GameTooltip:AddLine("Your totems follow the Call you pick", 0.5, 0.5, 0.5) end
	if self.opt.totemSetsSyncAssignments ~= false then
		GameTooltip:AddLine(pageName(1) .. " follows your assignments", 0.5, 0.5, 0.5)
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
-- (barChangeQueued / changedPages: declared at the top, Sync reads them)
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
	if not SP.opt or not SP:HasTotemBar() or InCombatLockdown() or SP:IsOff() then return end
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
	if boundRefreshQueued or InCombatLockdown() or SP:IsOff() then return end   -- switched off: on switch-on
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
		if changedPage == 1 then
			-- the one slot the player touched: only this one may be adopted as emptied
			local wowSlot = (slot - first) % SLOTS_PER_PAGE + 1
			-- what the slot holds right now: emptied = a clear to remember, filled = a pick (it
			-- wipes an older clear mark); unreadable (a secret value) = not a clear
			local okInfo, kind = pcall(GetActionInfo, slot)
			local emptied = okInfo and kind == nil
			for element = 1, 4 do
				if (SP.ElementToSlot and SP.ElementToSlot[element] or element) == wowSlot then
					editedSlots[element] = true
					clearedSlots[element] = emptied or nil
				end
			end
		end
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
		if not SP.opt or SP:IsOff() then return end   -- switched off: what waits is done on switch-on
		local after = CALL.keptAfterFight
		if after then
			-- (3.0.9.12) a Call picked in the fight: its own totem of an element Drop All skips, now
			CALL.keptAfterFight = nil
			for element, idx in pairs(after) do
				if idx and excludedElement(SP, element) then SP:ApplyAssignment(element, idx) end
			end
		end
		SP:ApplyEarlyCallPicks()   -- (A98) a Call learned in the fight: its early picks now
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
		SP:ApplyEarlyCallPicks()   -- (A98) a Call just learned: the totems picked for it early
		QueueBoundRefresh()
	end
end)

-- Switched back on: Blizzard's bar follows the assignments again and the bound
-- set pages get what waited meanwhile (nothing here writes it while off)
SP:OnOnOff(function(off)
	if off or not SP.opt or not SP:HasTotemBar() then return end
	if SP.totemSetsAdoptPending and SP.AdoptTotemBarAssignments then SP:AdoptTotemBarAssignments() end
	SP:SyncTotemSetFromAssignments()
	QueueBoundRefresh()
end)
