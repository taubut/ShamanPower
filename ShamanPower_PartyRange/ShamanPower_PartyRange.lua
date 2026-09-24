-- ============================================================================
-- ShamanPower Party Range Module
-- Shows party members in/out of totem range via dots and counters
-- ============================================================================

local SP = ShamanPower
if not SP then return end

-- Mark module as loaded
SP.PartyRangeLoaded = true

-- ============================================================================
-- Party Range Dots (shows which party members are in totem range)
-- ============================================================================

SP.partyRangeDots = {}  -- [element][partyIndex] = dot texture
-- Declared here, ABOVE SetupPartyRangeDots: that function sets it, and a local
-- declared further down would leave its write going to a global while the
-- engine-dot rebuild read the local (always false). Found by the round-2 review;
-- the engine dots had never been built.
local engineDotsReady = false -- SetupPartyRangeDots has run (buttons exist)

-- Buff spell IDs for totem buffs (same approach as TotemTimers)
-- These are the BUFF spell IDs (auras on party members), NOT the cast spell IDs
SP.TotemBuffSpellIDs = {
	[1] = {  -- Earth
		[1] = 8076,   -- Strength of Earth
		[2] = 8072,   -- Stoneskin
	},
	[2] = {  -- Fire
		[1] = 30708,  -- Totem of Wrath
		[5] = 8215,   -- Flametongue
		[6] = 8182,   -- Frost Resistance
	},
	[3] = {  -- Water
		[1] = 5677,   -- Mana Spring
		[2] = 5672,   -- Healing Stream
		[3] = 16191,  -- Mana Tide
		[6] = 8185,   -- Fire Resistance
	},
	[4] = {  -- Air
		[2] = 8836,   -- Grace of Air
		[3] = 2895,   -- Wrath of Air
		[4] = 25909,  -- Tranquil Air
		[6] = 10596,  -- Nature Resistance
		[7] = 15108,  -- Windwall
	},
}
-- Windfury Totem on WoW: Forever: SpellEffect.db2 1.60.1 shows vanilla's layout
-- (8515 passive party-area dummy aura, 8516/10608/10610 the on-hit proc), i.e.
-- a weapon enchant, not a readable party buff. UNVERIFIED in game (the beta's
-- level cap is below Windfury Totem). So the TBC path (weapon enchant + WFBUFF
-- comms) stays, and the aura IDs are only added to the engine-drawn dots as
-- extras: a dot lights if the client ever reports them, nothing is lost if not.
if WOW_PROJECT_ID ~= nil and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE then
	-- Forever reuses 8215 (TBC's Flametongue Totem buff) for a spell called
	-- "Rapid Cast", which broke the name match. There the entry is the totem
	-- spell itself (its name matches) and its buffs are the effect auras.
	SP.TotemBuffSpellIDs[2][5] = 8227
end

-- Every rank of each buff above (Forever 1.60.1 Spell.db2; the TBC IDs are the
-- same spells). The engine matches auras by exact spell ID, so a rank the list
-- lacks is a dot that never shows.
SP.TotemBuffRanks = {
	[8076]  = { 8076, 8162, 8163, 10441, 25362 },          -- Strength of Earth
	[8072]  = { 8072, 8156, 8157, 10403, 10404, 10405 },   -- Stoneskin
	[30708] = { 30708 },                                    -- Totem of Wrath
	[8215]  = { 8215, 8230, 8250, 10521, 15036 },          -- Flametongue Totem (effect auras)
	[8182]  = { 8182, 10476, 10477 },                       -- Frost Resistance
	[5677]  = { 5677, 10491, 10493, 10494 },                -- Mana Spring
	[5672]  = { 5672, 6371, 6372, 10460, 10461 },           -- Healing Stream
	[16191] = { 16191, 17355, 17360 },                      -- Mana Tide
	[8185]  = { 8185, 10534, 10535 },                       -- Fire Resistance
	[8836]  = { 8836, 10626, 25360 },                       -- Grace of Air
	[2895]  = { 2895 },                                     -- Wrath of Air
	[25909] = { 25909 },                                    -- Tranquil Air
	[10596] = { 10596, 10598, 10599 },                      -- Nature Resistance
	[15108] = { 15108, 15109, 15110 },                      -- Windwall
	[8516]  = { 8516, 10608, 10610 },                       -- Windfury Totem (Forever)
	[8227]  = { 8230, 8250, 10521, 15036 },                 -- Flametongue Totem on Forever: the effect auras party members carry
}

-- Extra aura IDs for the engine-drawn dots only (see the Windfury note above).
SP.ExtraEngineAuraIDs = {}
if WOW_PROJECT_ID ~= nil and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE then
	SP.ExtraEngineAuraIDs[4] = { 8515, 10609, 10612, 8516, 10608, 10610 } -- Windfury Totem passive + proc
end

-- Resolve buff spell IDs to exact names via GetSpellInfo (same approach as TotemTimers)
-- This guarantees exact name matching with UnitBuff results
SP.TotemBuffNames = {}
for element, buffs in pairs(SP.TotemBuffSpellIDs) do
	SP.TotemBuffNames[element] = {}
	for idx, spellId in pairs(buffs) do
		local name = GetSpellInfo(spellId)
		if name then
			SP.TotemBuffNames[element][idx] = name
		end
	end
end

-- On Forever a totem's name may differ from its effect aura's name. Cache all
-- rank/effect IDs once; leave Anniversary's existing name-only scan unchanged.
SP.TotemBuffIDSets = {}
if WOW_PROJECT_ID ~= nil and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE then
	for _, list in pairs(SP.TotemBuffSpellIDs) do
		for _, base in pairs(list) do
			local name = GetSpellInfo(base)
			if not issecretvalue(name) and name then
				local set = SP.TotemBuffIDSets[name] or {}
				for _, id in ipairs(SP.TotemBuffRanks[base] or { base }) do set[id] = true end
				SP.TotemBuffIDSets[name] = set
			end
		end
	end
end

-- Pre-computed lowercase versions for totem name matching in GetActiveTotemBuffName
SP.TotemBuffNamesLower = {}
for element, buffs in pairs(SP.TotemBuffNames) do
	SP.TotemBuffNamesLower[element] = {}
	for idx, name in pairs(buffs) do
		SP.TotemBuffNamesLower[element][idx] = name:lower()
	end
end

-- Cache for totem name lookups (avoids repeated string operations)
SP.totemBuffCache = {}

local function PartyRangeHost(element)
	return (SP.GetTotemOverlayHost and SP:GetTotemOverlayHost(element))
		or (SP.totemButtons and SP.totemButtons[element])
end

-- Create party range dots for a totem button
function SP:CreatePartyRangeDots(button, element)
	if not button then return end
	if self.partyRangeDots[element] then return end  -- Already created

	self.partyRangeDots[element] = {}

	for i = 1, 4 do
		local dot = button:CreateTexture(nil, "OVERLAY")
		dot:SetTexture("Interface\\AddOns\\ShamanPower\\textures\\dot")
		dot:SetSize(5, 5)  -- Smaller dots for inside corners
		dot:SetVertexColor(1, 1, 1)  -- Default white, will be colored by class
		dot:Hide()
		self.partyRangeDots[element][i] = dot
	end
	-- Placement (corners / above / below / left / right) from opt.partyDotPosition
	if self.PositionPartyDots then self:PositionPartyDots(self.partyRangeDots[element], button) end
end

-- The native manager defers host changes until combat ends. Only ordinary
-- addon regions move here; unlocked counters retain their screen positions.
function SP:RefreshPartyRangeHosts()
	if InCombatLockdown() then return end
	local native = self.UsingBlizzardTotemBar and self:UsingBlizzardTotemBar()
	for element = 1, 4 do
		local button = PartyRangeHost(element)
		local dots = self.partyRangeDots[element]
		if button and dots then
			for i = 1, 4 do
				local dot = dots[i]
				if dot:GetParent() ~= button then dot:SetParent(button) end
				local outline = dot.spOutline
				if outline and outline:GetParent() ~= button then outline:SetParent(button) end
			end
			if self.PositionPartyDots then self:PositionPartyDots(dots, button) end
		end
		local text = self.rangeCounterTexts and self.rangeCounterTexts[element]
		if button and text then
			if text:GetParent() ~= button then text:SetParent(button) end
			local _, relativeTo = text:GetPoint(1)
			-- Preserve a compact anchor already restored by the custom layout.
			if native or relativeTo ~= button then
				text:ClearAllPoints()
				text:SetPoint("CENTER", button, "CENTER", 0, 0)
			end
		end
	end
	self:RebuildEnginePartyDots()
end

-- Setup all party range dots for the mini totem bar
function SP:SetupPartyRangeDots()
	for element = 1, 4 do
		local button = PartyRangeHost(element)
		if button then
			self:CreatePartyRangeDots(button, element)
		end
	end

	-- Register range tracking with consolidated update system (2fps)
	if not self.updateSystem.subsystems["partyRange"] then
		local rangeState = {}
		local function rangePass()
			-- Always update player's own totem range (greying out when out of range)
			SP:UpdatePlayerTotemRange()
			-- Only update party range dots/counters if those features are enabled
			if SP.opt.showPartyRangeDots or (SP.opt.rangeCounter and SP.opt.rangeCounter.enabled) then   -- was a key nothing ever wrote: "Numbers Only" never refreshed
				SP:UpdatePartyRangeDots()
			end
			if SP.opt.coverage and SP.opt.coverage.enabled and SP.UpdateCoverage then SP:UpdateCoverage() end
		end
		self:RegisterUpdateSubsystem("partyRange", 0.5, function()
			-- range to a totem only means something while one is down (two more passes after the last
			-- one goes, so the dots and the greying are cleared)
			if SP._whileTotemsDown then SP._whileTotemsDown(rangeState, rangePass) else rangePass() end
		end)
	end
	-- Always enable this subsystem - player's own range tracking should always work
	-- The party dots are conditionally updated inside the callback
	self:EnableUpdateSubsystem("partyRange")
	engineDotsReady = true
	self:RebuildEnginePartyDots()
end

-- Get the buff name for the currently active totem of an element
function SP:GetActiveTotemBuffName(element)
	local haveTotem, totemName = self:GetElementTotemInfo(element)
	if not haveTotem or not totemName then
		self.totemBuffCache[element] = nil
		return nil
	end

	-- Check cache first (avoids string operations every update)
	local cached = self.totemBuffCache[element]
	if cached and cached.totemName == totemName then
		return cached.buffName, cached.totemIndex
	end

	local buffNames = self.TotemBuffNames[element]
	local buffNamesLower = self.TotemBuffNamesLower[element]
	if not buffNames then
		self.totemBuffCache[element] = {totemName = totemName, buffName = nil}
		return nil
	end

	-- Match based on actual totem name from GetTotemInfo (not assignments!)
	-- This ensures we check the buff for the ACTIVE totem, not the assigned one
	-- Strip rank number from totem name for matching (e.g., "Windfury Totem VII" -> "Windfury Totem")
	local totemBaseName = totemName:gsub("%s+[IVXLCDM]+$", ""):gsub("%s+%d+$", "")
	local totemLower = totemBaseName:lower()
	local fullNameLower = totemName:lower()

	for totemIndex, buffName in pairs(buffNames) do
		if type(buffName) == "string" then
			local buffLower = buffNamesLower[totemIndex]
			-- Check if totem name contains the buff search term
			if totemLower:find(buffLower, 1, true) or fullNameLower:find(buffLower, 1, true) then
				-- Cache the result
				self.totemBuffCache[element] = {totemName = totemName, buffName = buffName, totemIndex = totemIndex}
				return buffName, totemIndex
			end
		end
	end

	-- No matching buff found - this totem doesn't have a trackable buff
	-- (e.g., Tremor, Disease Cleansing, Searing, etc.)
	self.totemBuffCache[element] = {totemName = totemName, buffName = nil}
	return nil
end

-- Check if a unit has a specific buff (same approach as TotemTimers).
--
-- On the Mainline family, combat hides other players' buffs, and an empty read
-- looks exactly like "no buff", which turned every dot red the moment a fight
-- started. When reads are blocked and the caller says which element it is
-- asking about, coverage is answered by distance from where that totem was
-- dropped instead (the same model the totem bar's own range check uses). With
-- no position to measure (instances), the last readable answer is kept.
SP.partyRangeLast = {}   -- [unit .. element] = last answer while buffs were readable

-- Instances give out no positions, so distance from the totem cannot be
-- measured there. What the client does still answer in combat is whether a unit
-- is within range of a spell (measured: C_Spell.IsSpellInRange("Healing Wave",
-- "party1") is true next to the shaman and false far away, mid-fight). It is an
-- approximation on two counts, and only used where nothing better exists: it
-- measures from the SHAMAN rather than from the totem, and Healing Wave reaches
-- 40 yd against a totem's 30. It is right whenever the shaman stands by their
-- totems, and unlike a frozen dot it keeps updating during the fight.
local RANGE_SPELL_ID = 331   -- Healing Wave (Rank 1): every shaman knows it
function SP:UnitNearShaman(unit)
	if not (C_Spell and C_Spell.IsSpellInRange) then return nil end
	local name = GetSpellInfo(RANGE_SPELL_ID)   -- localized, matches any rank
	local ok, inRange = pcall(C_Spell.IsSpellInRange, name or RANGE_SPELL_ID, unit)
	if not ok then return nil end
	if issecretvalue and issecretvalue(inRange) then return nil end   -- before any comparison: a secret must not be compared, even to nil
	if inRange == nil then return nil end
	return inRange and true or false
end

function SP:UnitHasBuff(unit, buffName, element)
	if WOW_PROJECT_ID ~= nil and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE and issecretvalue(buffName) then return false end
	if not buffName then return false end

	if element and SPCompat and SPCompat.AurasUnreadable and SPCompat.AurasUnreadable() then
		local near = ShamanPower.TotemDropInRange and ShamanPower:TotemDropInRange(element, unit)
		if near == nil then near = self:UnitNearShaman(unit) end          -- no positions (instances)
		if near == nil then near = self.partyRangeLast[unit .. element] end
		if near == nil then near = true end   -- never call someone uncovered on a guess
		return near
	end

	-- Same unit, same buff, no aura event since the last look: same answer.
	local cache = self._unitBuffCache
	if not cache then cache = {}; self._unitBuffCache = cache end
	local uc = cache[unit]
	if not uc then uc = { gen = {}, at = {}, has = {} }; cache[unit] = uc end
	if self:AuraCacheValid(unit, uc.gen[buffName], uc.at[buffName]) then
		local has = uc.has[buffName]
		if element then self.partyRangeLast[unit .. element] = has end
		return has
	end

	local has = false
	if WOW_PROJECT_ID ~= nil and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE then
		local ids = SP.TotemBuffIDSets[buffName]
		if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
			for i = 1, 40 do
				local aura = C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")
				if issecretvalue(aura) or not aura then break end
				local name, spellId = aura.name, aura.spellId
				if (not issecretvalue(name) and name == buffName)
					or (not issecretvalue(spellId) and spellId and ids and ids[spellId]) then
					has = true
					break
				end
			end
		end
	else
		for i = 1, 32 do
			local name = UnitBuff(unit, i)
			if not name then break end
			if name == buffName then has = true break end
		end
	end
	uc.gen[buffName], uc.at[buffName], uc.has[buffName] = self.auraGen[unit] or 0, GetTime(), has
	if element then self.partyRangeLast[unit .. element] = has end
	return has
end

-- Reusable table for party units (avoids creating garbage every call)
SP.partyUnitsCache = {}
SP.emptyTable = {}  -- Shared empty table for early returns
SP.partyUnitStrings = {"party1", "party2", "party3", "party4"}  -- Pre-built strings to avoid concatenation

-- Get party/subgroup units efficiently
-- In WoW, "party1-party4" works in both party AND raid (refers to your subgroup members)
-- No need to loop through all 40 raid members!
function SP:GetCachedPartyUnits()
	-- Early out: check if there are any subgroup members first
	if not IsInGroup() then
		return self.emptyTable, 0
	end

	-- GetNumSubgroupMembers returns count excluding self (0-4)
	local numMembers = GetNumSubgroupMembers and GetNumSubgroupMembers() or 4
	if numMembers == 0 then
		return self.emptyTable, 0
	end

	-- Reuse cached table to avoid garbage collection pressure
	local partyUnits = self.partyUnitsCache
	wipe(partyUnits)
	local count = 0

	-- party1-party4 works in both party and raid (refers to subgroup in raids)
	-- Use pre-built strings to avoid string concatenation garbage
	for i = 1, numMembers do
		local unitStr = self.partyUnitStrings[i]
		if UnitExists(unitStr) then
			count = count + 1
			partyUnits[count] = unitStr
		end
	end

	return partyUnits, count
end

-- ============================================================================
-- Engine-drawn party dots (secrets regime: Forever / retail)
-- ============================================================================
-- In combat other players' buffs cannot be read, so the dot logic below was
-- guessing there (distance from the drop point, or a spell range check). An
-- AuraContainer bound to the party token draws a child texture whenever that
-- unit carries a totem buff and hides it the instant the buff is gone - in
-- combat, in instances, with no reads and nothing ticking (measured
-- 2026-09-22 on party1 with Stoneskin: shows, and goes blank out of range).
-- One container per totem button and party slot; the slot's filter is every
-- buff any totem of that element can give, all ranks (only one totem per
-- element is ever down, so whichever buff is present is the right one). The
-- class-coloured dot is a static child of the engine's aura button; the red
-- "no buff" dot stays the addon's own texture underneath, covered whenever the
-- engine's dot shows. Built out of combat only (the button subtree may only be
-- written in initializeFrame, and a container is registered out of combat);
-- a rebuild asked for in combat waits for PLAYER_REGEN_ENABLED.
SP.engineDots = {}            -- [element][partyIndex] = { main = record, overlay = record }
local engineDotsPending, engineDotsBuilding = false, false

local function EngineDotsAvailable()
	return SPCompat ~= nil and SPCompat.secretsRegime == true and C_AddOns ~= nil and C_AddOns.LoadAddOn ~= nil
end

-- true while the engine is drawing the coloured dots (so the addon draws only the red ones)
function SP:EngineDotsOn()
	return self.engineDotsBuilt == true and self.opt.showPartyRangeDots and true or false
end

local function ElementBuffMap(element)
	local map = {}
	for _, base in pairs(SP.TotemBuffSpellIDs[element] or {}) do
		for _, id in ipairs(SP.TotemBuffRanks[base] or { base }) do map[id] = true end
	end
	for _, id in ipairs(SP.ExtraEngineAuraIDs[element] or {}) do map[id] = true end
	return map
end

local DOT_TEXTURE = "Interface\\AddOns\\ShamanPower\\textures\\dot"

local function BuildEngineDot(element, partyIndex, btn, r, g, b)
	local unit = SP.partyUnitStrings[partyIndex]
	local size = SP.opt.partyDotSize or 5
	local outline = SP.opt.partyDotOutline ~= false
	local point, relPoint, x, y = ShamanPower:PartyDotAnchor(partyIndex, btn)
	local ok, container = pcall(CreateFrame, "AuraContainer", nil, btn, "CustomAuraContainerTemplate")
	if not ok or not container then
		if SPCompat.Trace then SPCompat.Trace("DOTS container %d/%d create failed: %s", element, partyIndex, tostring(container)) end
		return nil
	end
	container:SetAllPoints(btn)
	container:SetFrameLevel(btn:GetFrameLevel() + 10)   -- above the button art and the active-totem overlay
	local okAdd, err = pcall(container.AddAuraSlot, container, "dot", "HELPFUL", {
		candidateFilters = { includeSpellIDs = ElementBuffMap(element) },
		initializeFrame = function(button)
			button:ClearAllPoints()
			button:SetSize(size, size)
			button:SetPoint(point, btn, relPoint, x, y)
			if button.SetMouseClickEnabled then pcall(button.SetMouseClickEnabled, button, false) end
			if button.SetMouseMotionEnabled then pcall(button.SetMouseMotionEnabled, button, false) end
			if outline then
				local o = button:CreateTexture(nil, "OVERLAY", nil, -1)
				o:SetTexture(DOT_TEXTURE)
				o:SetVertexColor(0, 0, 0, 0.9)
				o:SetPoint("CENTER", button, "CENTER", 0, 0)
				o:SetSize(size + 2, size + 2)
			end
			local dot = button:CreateTexture(nil, "OVERLAY")
			dot:SetTexture(DOT_TEXTURE)
			dot:SetVertexColor(r, g, b)
			dot:SetAllPoints(button)
		end,
	})
	if not okAdd then
		if SPCompat.Trace then SPCompat.Trace("DOTS AddAuraSlot %d/%d failed: %s", element, partyIndex, tostring(err)) end
		container:Hide()
		return nil
	end
	pcall(container.SetUnit, container, unit)
	pcall(container.SetEnabled, container, true)
	pcall(container.UpdateAllAuras, container)
	return container
end

local function UseEngineOverlay(element)
	if SP.GridActive and SP:GridActive() then return false end
	if SP.UsingBlizzardTotemBar and SP:UsingBlizzardTotemBar() then return false end
	if SP.opt.activeTotemAsMain or (SP.CompactActive and SP:CompactActive()) then return false end
	local overlay = SP.activeTotemOverlays and SP.activeTotemOverlays[element]
	return overlay and overlay.isActive and overlay.dots and true or false
end

-- This is our own visibility intent, never a read from the aura subtree.
local function ShowEngineRecord(record, shown)
	if record and record.container and record.shown ~= shown then
		record.container:SetShown(shown)
		record.shown = shown
	end
end

local function RetireEngineRecord(record)
	if record and record.container then
		pcall(record.container.SetEnabled, record.container, false)
		ShowEngineRecord(record, false)
	end
end

local function RebuildEngineRecord(record, element, i, host, exists, class, r, g, b)
	if not host then RetireEngineRecord(record); return nil end
	local point, relPoint, x, y = SP:PartyDotAnchor(i, host)
	local key = (exists and (class or "?") or "-") .. "|" .. tostring(SP.opt.partyDotSize or 5) .. "|"
		.. tostring(SP.opt.partyDotOutline ~= false) .. "|" .. point .. relPoint .. x .. "," .. y
	if record and record.key == key and record.host == host and (record.container or not exists) then return record end
	RetireEngineRecord(record)
	local container = exists and BuildEngineDot(element, i, host, r, g, b) or nil
	if container then container:Hide() end
	return { container = container, key = key, host = host, shown = false }
end

function SP:SetEnginePartyDotsShown(on)
	on = on and true or false
	self.engineDotsShown = on
	for element = 1, 4 do
		local slots = self.engineDots[element]
		local overlay = UseEngineOverlay(element)
		if slots then
			for i = 1, 4 do
				local slot = slots[i]
				if slot then
					-- Hide the old destination first, including when both are disabled.
					if overlay then
						ShowEngineRecord(slot.main, false); ShowEngineRecord(slot.overlay, on)
					else
						ShowEngineRecord(slot.overlay, false); ShowEngineRecord(slot.main, on)
					end
				end
			end
		end
	end
end

local function RebuildEngineDots(self)
	pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
	local native = SP.UsingBlizzardTotemBar and SP:UsingBlizzardTotemBar()
	local built, created = false, false
	for element = 1, 4 do
		local btn = PartyRangeHost(element)
		local overlay = SP.activeTotemOverlays and SP.activeTotemOverlays[element]
		-- Prebuild while safe: the first differing cast may arrive in combat.
		-- Its factory calls PositionPartyDots, so the outer rebuild is reentry guarded.
		if btn and not native and not overlay and SP.activeTotemOverlays and SP.CreateActiveTotemOverlay then
			overlay = SP:CreateActiveTotemOverlay(element)
			SP.activeTotemOverlays[element] = overlay
			created = created or overlay ~= nil
		end
		local overlayHost = not native and overlay and overlay.frame or nil
		SP.engineDots[element] = SP.engineDots[element] or {}
		for i = 1, 4 do
			local unit = SP.partyUnitStrings[i]
			local exists = UnitExists(unit)
			if issecretvalue(exists) then exists = false end
			local _, class = UnitClass(unit)
			if issecretvalue(class) then class = nil end
			local color = class and RAID_CLASS_COLORS[class]
			local r, g, b = 0, 1, 0
			if color then r, g, b = color.r, color.g, color.b end
			local slot = SP.engineDots[element][i] or {}
			slot.main = RebuildEngineRecord(slot.main, element, i, btn, exists, class, r, g, b)
			slot.overlay = RebuildEngineRecord(slot.overlay, element, i, btn and overlayHost, exists, class, r, g, b)
			SP.engineDots[element][i] = slot
			if (slot.main and slot.main.container) or (slot.overlay and slot.overlay.container) then built = true end
		end
	end
	if created and SP.PositionActiveOverlays then SP:PositionActiveOverlays() end
	self.engineDotsBuilt = built or nil
	self:SetEnginePartyDotsShown(self.opt.showPartyRangeDots)
end

-- Build only out of combat. A failed factory may be retried on the next rebuild.
function SP:RebuildEnginePartyDots()
	if engineDotsBuilding or not (engineDotsReady and EngineDotsAvailable()) then return end
	if InCombatLockdown() then engineDotsPending = true return end
	engineDotsPending = false
	engineDotsBuilding = true
	local ok, err = pcall(RebuildEngineDots, self)
	engineDotsBuilding = false
	if not ok then
		engineDotsPending = true
		if SPCompat.Trace then SPCompat.Trace("DOTS rebuild failed: %s", tostring(err)) end
	end
end

-- Roster changes recolour (or add / drop) a slot; a fight defers it.
local engineDotEvents = CreateFrame("Frame")
if SPCompat and SPCompat.StressRegister then SPCompat.StressRegister(engineDotEvents, "Party Range") end
engineDotEvents:RegisterEvent("GROUP_ROSTER_UPDATE")
engineDotEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
engineDotEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
engineDotEvents:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_REGEN_ENABLED" then
		if engineDotsPending then SP:RebuildEnginePartyDots() end
		if SP._coveragePending and SP.RebuildCoverage then SP:RebuildCoverage() end   -- was a local read before it existed
	else
		SP:RebuildEnginePartyDots()
		if SP.RebuildCoverage then SP:RebuildCoverage() end
	end
end)

-- ============================================================================
-- Totem Coverage: who is OUT of range of each totem, by name
-- ============================================================================
-- The shaman's own Totem Range overlay: the same panel, title and cog, one
-- icon cell per totem down that gives a buff, and under each icon the party
-- members' names. Each name is RED (no buff) drawn by the addon; on top of it
-- sits an engine aura display bound to that member, filtered on the
-- element's totem buffs, whose child is a strip in the cell's own colour
-- carrying the name in class colour. Buffed = the engine shows the strip and
-- the red name is covered; out of range = the engine hides it and the red
-- name shows. No reads, so it holds in combat and in instances. Out of
-- combat, where reads work, the cell's border says green (everyone) or red
-- (someone missing) and a totem everyone has can be left out; in combat the
-- border is neutral and the names carry the answer (the engine never says
-- "all covered"). Rows are built out of combat (names, classes); a roster
-- change in a fight rebuilds at regen.
SP.coverageRows = {}   -- [element][partyIndex] = { container = frame|nil, key = string }

function SP:CoverageAvailable() return EngineDotsAvailable() end

local function CoverageOpts()
	SP.opt.coverage = SP.opt.coverage or {}
	return SP.opt.coverage
end
local function CoverageFont() return (CoverageOpts().fontSize or 9) end
local function CoverageRowH() return CoverageFont() + 3 end
local function CoverageIconSize() return CoverageOpts().iconSize or 36 end
-- "Place each totem freely": every watched TOTEM gets a cell of its own
-- with its own spot and size (keyed element * 100 + totem index); the panel
-- layouts use one cell per element (keyed by element).
local function CellOpts(key)
	local co = CoverageOpts()
	co.cells = co.cells or {}
	co.cells[key] = co.cells[key] or {}
	return co.cells[key]
end
local function CellIconSize(key)
	if CoverageOpts().freeCells then return CellOpts(key).iconSize or CoverageIconSize() end
	return CoverageIconSize()
end
local function TotemCellKey(element, totemIndex) return element * 100 + totemIndex end
local ELEMENT_LABELS = { "Earth", "Fire", "Water", "Air" }

-- Which totems the overlay watches (by the buff's base spell ID; all on
-- unless switched off). A cell only appears for a watched totem, and the
-- engine rows are filtered to watched buffs only.
function SP:CoverageWatches(element, totemIndex)
	local base = self.TotemBuffSpellIDs[element] and self.TotemBuffSpellIDs[element][totemIndex]
	if not base then return false end
	local tracked = CoverageOpts().tracked
	return not (tracked and tracked[base] == false)
end
function SP:SetCoverageWatch(base, on)
	local co = CoverageOpts()
	co.tracked = co.tracked or {}
	-- watched = no entry (the default), unwatched = false. Not "on and nil or false":
	-- "and nil" is always nil, so that form wrote false for both.
	if on then co.tracked[base] = nil else co.tracked[base] = false end
	self:UpdateCoverageLayout()
end
local function CoverageBuffMap(element)
	local map = {}
	for idx, base in pairs(SP.TotemBuffSpellIDs[element] or {}) do
		if SP:CoverageWatches(element, idx) then
			for _, id in ipairs(SP.TotemBuffRanks[base] or { base }) do map[id] = true end
		end
	end
	return map
end
local function CoverageWatchSig(element)
	local parts = {}
	for idx in pairs(SP.TotemBuffSpellIDs[element] or {}) do
		if SP:CoverageWatches(element, idx) then parts[#parts + 1] = idx end
	end
	table.sort(parts)
	return table.concat(parts, ",")
end

function SP:CreateCoverageFrame()
	if self.coverageFrame then return self.coverageFrame end
	local co = CoverageOpts()
	local frame = CreateFrame("Frame", "ShamanPowerCoverage", UIParent, "BackdropTemplate")
	frame:SetSize(150, 60)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:SetClampedToScreen(true)
	SP:ApplyPanelBackdrop(frame)

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	title:SetPoint("TOP", frame, "TOP", 0, -6)
	title:SetText("Totem Coverage")
	SP:SetSPFont(title, "labels", 11, "", STANDARD_TEXT_FONT)
	title:SetShadowOffset(1, -1)
	title:SetTextColor(0.902, 0.918, 0.941)
	frame.title = title

	local settingsBtn = CreateFrame("Button", nil, frame)
	settingsBtn:SetSize(14, 14)
	settingsBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
	SP:StyleSettingsButton(settingsBtn)
	settingsBtn:SetScript("OnClick", function() SP:OpenFrameSettings("coverage", frame) end)
	settingsBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Configure Totem Coverage", 1, 1, 1)
		GameTooltip:Show()
	end)
	settingsBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
	frame.settingsBtn = settingsBtn

	-- Drag to move (ALT+drag when borderless, like the Totem Range overlay)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self)
		if not self:IsMovable() then return end
		if CoverageOpts().hideBorder and not IsAltKeyDown() then return end
		self:StartMoving()
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		CoverageOpts().position = SP:SavePositionRecord(self)
	end)
	frame:SetScript("OnMouseUp", function(self, button)
		if button == "RightButton" and CoverageOpts().hideBorder then SP:OpenFrameSettings("coverage", self) end
	end)
	frame:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine("Totem Coverage", 1, 0.82, 0)
		GameTooltip:AddLine(" ")
		if CoverageOpts().hideBorder then
			GameTooltip:AddLine("ALT+drag to move", 0.7, 0.7, 0.7)
			GameTooltip:AddLine("Right-click to configure", 0.7, 0.7, 0.7)
		else
			GameTooltip:AddLine("Drag to move", 0.7, 0.7, 0.7)
		end
		GameTooltip:Show()
	end)
	frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
	if not self:ApplyPositionRecord(frame, co.position) then frame:SetPoint("CENTER", UIParent, "CENTER", 0, 120) end

	-- a cell: icon, status, and the name rows under the icon. The panel
	-- layouts use one per element; free placement one per watched totem.
	local function NewCell(key, element, label)
		local btn = CreateFrame("Frame", nil, frame, "BackdropTemplate")
		SP:ApplyPanelBackdrop(btn)
		local icon = btn:CreateTexture(nil, "ARTWORK")
		icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 3, -3)
		icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		btn.icon = icon
		local overlay = btn:CreateTexture(nil, "OVERLAY")
		overlay:SetAllPoints(icon)
		overlay:SetColorTexture(0.3, 0, 0, 0.6)
		overlay:Hide()
		btn.rangeOverlay = overlay
		local statusText = btn:CreateFontString(nil, "OVERLAY")
		SP:SetSPFont(statusText, "labels", 7, "OUTLINE")
		statusText:SetPoint("CENTER", icon, "CENTER", 0, 0)
		statusText:SetTextColor(1, 0.2, 0.2)
		statusText:SetShadowColor(0, 0, 0, 1)
		statusText:SetShadowOffset(1, -1)
		statusText:Hide()
		btn.statusText = statusText
		btn.rows = {}
		for i = 1, 4 do
			-- a name-tag pill under the icon: the dark tag is what the engine's
			-- strip can match to cover the red name
			local row = CreateFrame("Frame", nil, btn)
			local t = row:CreateFontString(nil, "OVERLAY")
			SP:SetSPFont(t, "labels", 9, "OUTLINE")
			t:SetPoint("LEFT", row, "LEFT", 2, 0)
			t:SetPoint("RIGHT", row, "RIGHT", -2, 0)
			t:SetJustifyH("CENTER")
			t:SetWordWrap(false)
			t:SetTextColor(1, 0.25, 0.25)
			row.text = t
			row:Hide()
			btn.rows[i] = row
		end
		btn.element, btn.cellKey, btn.cellLabel = element, key, label
		btn.spMoverLabel = "Coverage: " .. label
		btn:SetMovable(true)
		btn:SetClampedToScreen(true)
		btn:RegisterForDrag("LeftButton")
		btn:SetScript("OnDragStart", function(self)
			if CoverageOpts().freeCells and IsAltKeyDown() then self:StartMoving() end
		end)
		btn:SetScript("OnDragStop", function(self)
			self:StopMovingOrSizing()
			if CoverageOpts().freeCells then CellOpts(self.cellKey).position = SP:SavePositionRecord(self) end
		end)
		btn:SetScript("OnEnter", function(self)
			if not CoverageOpts().freeCells then return end
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:AddLine("Totem Coverage: " .. self.cellLabel, 1, 0.82, 0)
			GameTooltip:AddLine("ALT+drag to move", 0.7, 0.7, 0.7)
			GameTooltip:Show()
		end)
		btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
		btn:Hide()
		return btn
	end
	frame.NewCell = NewCell
	frame.buttons = {}
	for element = 1, 4 do frame.buttons[element] = NewCell(element, element, ELEMENT_LABELS[element]) end
	frame.totemCells = {}   -- [element * 100 + totemIndex] = cell, made when first needed
	frame:Hide()
	self.coverageFrame = frame
	self:UpdateCoverageBorder()
	self:UpdateCoverageOpacity()
	return frame
end

local SizeCell, HideAllCells   -- defined with the layout helpers below

local function BuildCoverageRow(element, partyIndex, btn, row, name, r, g, b)
	local unit = SP.partyUnitStrings[partyIndex]
	local ok, container = pcall(CreateFrame, "AuraContainer", nil, row, "CustomAuraContainerTemplate")
	if not ok or not container then return nil end
	container:SetAllPoints(row)
	container:SetFrameLevel(row:GetFrameLevel() + 5)
	local sr, sg, sb = btn:GetBackdropColor()
	local fontSize = CoverageFont()
	local okAdd = pcall(container.AddAuraSlot, container, "cover", "HELPFUL", {
		candidateFilters = { includeSpellIDs = CoverageBuffMap(element) },
		initializeFrame = function(button)
			button:ClearAllPoints()
			button:SetAllPoints(row)
			if button.SetMouseClickEnabled then pcall(button.SetMouseClickEnabled, button, false) end
			if button.SetMouseMotionEnabled then pcall(button.SetMouseMotionEnabled, button, false) end
			-- the covered look: the same name, same font and place, in class
			-- colour - identical glyphs, so the red one underneath disappears
			-- under it. No tag, no strip: names float, frame or no frame.
			local t = button:CreateFontString(nil, "OVERLAY")
			SP:SetSPFont(t, "labels", fontSize, "OUTLINE")
			t:SetPoint("LEFT", button, "LEFT", 2, 0)
			t:SetPoint("RIGHT", button, "RIGHT", -2, 0)
			t:SetJustifyH("CENTER")
			t:SetWordWrap(false)
			t:SetTextColor(r, g, b)
			t:SetText(name)
		end,
	})
	if not okAdd then container:Hide() return nil end
	pcall(container.SetUnit, container, unit)
	pcall(container.SetEnabled, container, true)
	pcall(container.UpdateAllAuras, container)
	return container
end

-- The cell of one watched totem (free placement), made on first use.
function SP:CoverageTotemCell(element, totemIndex)
	local frame = self:CreateCoverageFrame()
	local key = TotemCellKey(element, totemIndex)
	local btn = frame.totemCells[key]
	if not btn then
		local base = self.TotemBuffSpellIDs[element] and self.TotemBuffSpellIDs[element][totemIndex]
		local label = (base and GetSpellInfo(base)) or (ELEMENT_LABELS[element] .. " " .. totemIndex)
		btn = frame.NewCell(key, element, label)
		btn.totemIndex = totemIndex
		local totem = self.GetTotemSpell and self:GetTotemSpell(element, totemIndex)
		local _, _, tex = totem and GetSpellInfo(totem)
		if tex then btn.icon:SetTexture(tex); btn.iconTex = tex end
		frame.totemCells[key] = btn
	end
	return btn
end

-- Every watched totem this client has, as cells (free placement).
function SP:CoverageWatchedCells()
	local out = {}
	for element = 1, 4 do
		for idx in pairs(self.TotemBuffSpellIDs[element] or {}) do
			if self:CoverageWatches(element, idx) and self:TotemExistsOnClient(element, idx) then
				local totem = self.GetTotemSpell and self:GetTotemSpell(element, idx)
				if totem and SPCompat and SPCompat.SpellExists and SPCompat.SpellExists(totem) then
					out[#out + 1] = self:CoverageTotemCell(element, idx)
				end
			end
		end
	end
	table.sort(out, function(a, b) return a.cellKey < b.cellKey end)
	return out
end

-- Rows for the current party under one cell (names, classes, font); keyed,
-- so a roster or font change rebuilds only what changed.
local function BuildCellRows(self, btn, rowsKey, element)
	local fontSize, rowH = CoverageFont(), CoverageRowH()
	SizeCell(btn, CellIconSize(btn.cellKey))   -- the tags size themselves against the cell
	self.coverageRows[rowsKey] = self.coverageRows[rowsKey] or {}
	for i = 1, 4 do
		local unit = self.partyUnitStrings[i]
		local exists = UnitExists(unit)
		local name = exists and (UnitName(unit) or "?") or "-"
		local _, class = UnitClass(unit)
		local key = name .. "|" .. tostring(class) .. "|" .. fontSize .. "|" .. CellIconSize(btn.cellKey) .. "|" .. CoverageWatchSig(element)
		local slot = self.coverageRows[rowsKey][i]
		local row = btn.rows[i]
		if not slot or slot.key ~= key then
			if slot and slot.container then
				pcall(slot.container.SetEnabled, slot.container, false)
				slot.container:Hide()
			end
			SP:SetSPFont(row.text, "labels", fontSize, "OUTLINE")
			row.text:SetText(name)
			-- as wide as the cell, wider for a long name (never cut): flush under the icon
			row:SetSize(math.max(btn:GetWidth(), math.ceil(row.text:GetStringWidth()) + 10), rowH)
			row:ClearAllPoints()
			row:SetPoint("TOP", btn, "BOTTOM", 0, -(i - 1) * rowH)
			local cr, cg, cb = 0.4, 1, 0.4
			local color = class and RAID_CLASS_COLORS[class]
			if color then cr, cg, cb = color.r, color.g, color.b end
			local container = exists and BuildCoverageRow(element, i, btn, row, name, cr, cg, cb) or nil
			self.coverageRows[rowsKey][i] = { container = container, key = key }
		end
		row:SetShown(exists)
	end
end

-- Rows for every cell in use. Out of combat only.
function SP:RebuildCoverage()
	local co = self.opt.coverage
	if not (co and co.enabled and EngineDotsAvailable()) then
		if self.coverageFrame then HideAllCells(self.coverageFrame) end
		return
	end
	if InCombatLockdown() then SP._coveragePending = true return end
	SP._coveragePending = false
	local frame = self:CreateCoverageFrame()
	pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
	if co.freeCells then
		for _, btn in ipairs(self:CoverageWatchedCells()) do BuildCellRows(self, btn, "t" .. btn.cellKey, btn.element) end
	else
		for element = 1, 4 do BuildCellRows(self, frame.buttons[element], element, element) end
	end
	frame.layoutKey = nil
	self:UpdateCoverage()
end

SizeCell = function(btn, iconSize)
	btn:SetSize(iconSize + 6, iconSize + 6)
	btn.icon:SetSize(iconSize, iconSize)
end

-- Free placement: each cell lives on its own, parented to the screen, at its
-- saved spot (or spread in a row to start), at its own size.
local freeOrder = 0
local function PlaceFreeCell(btn)
	if btn:GetParent() ~= UIParent then
		btn:SetParent(UIParent)
		btn:SetFrameStrata("MEDIUM")
	end
	btn:EnableMouse(true)
	SizeCell(btn, CellIconSize(btn.cellKey))
	if not btn.freePlaced then
		btn.freePlaced = true
		if not SP:ApplyPositionRecord(btn, CellOpts(btn.cellKey).position) then
			-- never placed: spread in a row above the character, in the order they first appear
			freeOrder = freeOrder + 1
			btn:ClearAllPoints()
			btn:SetPoint("CENTER", UIParent, "CENTER", (freeOrder - 3) * 70, 120)
		end
	end
end

local function ReturnCellToFrame(frame, btn)
	if btn:GetParent() ~= frame then btn:SetParent(frame) end
	btn:EnableMouse(false)
	btn.freePlaced = nil
end

-- Cells laid out like the Totem Range overlay (row or column), sized for
-- the icon plus the name rows.
local function LayoutCoverage(frame, shown, count)
	local co = CoverageOpts()
	local iconSize, rowH = CoverageIconSize(), CoverageRowH()
	local cellW = iconSize + 6
	local cellH = iconSize + 6
	local nameSpace = (count > 0) and (count * rowH + 2) or 0   -- the name tags stack flush under each cell
	local padding, n = 6, #shown
	local width, height
	if co.vertical then
		width = cellW + 24
		height = ((cellH + nameSpace) * n) + (padding * (n - 1)) + 28
	else
		width = (cellW * n) + (padding * (n - 1)) + 24
		height = cellH + nameSpace + 26
	end
	frame:SetSize(math.max(80, width), height)
	for idx, btn in ipairs(shown) do
		SizeCell(btn, iconSize)
		btn:ClearAllPoints()
		if co.vertical then
			btn:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -20 - (idx - 1) * (cellH + nameSpace + padding))
		else
			local cellsW = (cellW * n) + (padding * (n - 1))
			btn:SetPoint("TOPLEFT", frame, "TOPLEFT", (frame:GetWidth() - cellsW) / 2 + (idx - 1) * (cellW + padding), -20)
		end
	end
end

local function PaintCoverageCell(btn, state, missing)
	if btn.state == state and btn.missing == missing then return end
	btn.state, btn.missing = state, missing
	if state == "covered" then
		btn:SetBackdropBorderColor(0, 1, 0, 1)
		btn.rangeOverlay:Hide()
		btn.statusText:Hide()
	elseif state == "missing" then
		btn:SetBackdropBorderColor(0.8, 0, 0, 1)
		btn.rangeOverlay:Show()
		btn.statusText:SetText(missing == 1 and "1 OUT" or (missing .. " OUT"))
		btn.statusText:Show()
	else   -- "combat": the names carry the answer
		btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
		btn.rangeOverlay:Hide()
		btn.statusText:Hide()
	end
end

-- Which cells show and what their borders say. Runs on the range pass while
-- totems are down; lays out again only when the set of cells changes.
HideAllCells = function(frame)
	frame:Hide()
	for element = 1, 4 do frame.buttons[element]:Hide() end
	for _, btn in pairs(frame.totemCells or {}) do btn:Hide() end
end

function SP:UpdateCoverage()
	local co = self.opt.coverage
	local frame = self.coverageFrame
	if not (co and co.enabled and frame) then
		if frame then HideAllCells(frame) end
		return
	end
	if self.coverageDemoActive then return end
	local partyUnits, count = self:GetCachedPartyUnits()
	if count == 0 then HideAllCells(frame) return end
	local shown, mask = {}, 0
	for element = 1, 4 do
		local haveTotem, _, _, _, icon = self:GetElementTotemInfo(element)
		local buffName, totemIndex
		if haveTotem then buffName, totemIndex = self:GetActiveTotemBuffName(element) end
		local show = (haveTotem and buffName and totemIndex and self:CoverageWatches(element, totemIndex)) and true or false
		local state, missing = "combat", 0
		-- In combat inside an instance the game gives out no positions, so the
		-- distance model can only ask "is this player near the SHAMAN", which is
		-- wrong whenever the shaman walks away from the totem. There the border
		-- stays neutral grey and says nothing; the game-drawn names (from the
		-- real buffs) are the answer. Measured in RFC, 2026-09-23.
		local noPositions = show and SPCompat and SPCompat.AurasUnreadable and SPCompat.AurasUnreadable()
			and self.TotemDropInRange and self:TotemDropInRange(element) == nil
		if noPositions then
			state = "combat"
		elseif show then
			-- out of combat these are reads; in combat UnitHasBuff answers from
			-- the distance model, the same one the counters and Totem Range use
			for i = 1, count do
				if not self:UnitHasBuff(partyUnits[i], buffName, element) then missing = missing + 1 end
			end
			state = (missing == 0) and "covered" or "missing"
			-- everyone covered: nothing to say. In combat that is the distance model's
			-- answer (exact outdoors, a range check from the shaman in instances).
			if missing == 0 and co.hideWhenCovered ~= false then show = false end
		end
		if show then
			-- the panel's cell for the element, or the totem's own cell when placed freely
			local btn = co.freeCells and self:CoverageTotemCell(element, totemIndex) or frame.buttons[element]
			if icon ~= nil and not issecretvalue(icon) and btn.iconTex ~= icon then btn.iconTex = icon; btn.icon:SetTexture(icon) end
			PaintCoverageCell(btn, state, missing)
			shown[#shown + 1] = btn
			mask = mask + 2 ^ element
		end
	end
	if co.freeCells then
		-- no panel: every totem's cell shows or hides on its own, where it was put
		frame:Hide()
		for element = 1, 4 do if frame.buttons[element]:IsShown() then frame.buttons[element]:Hide() end end
		for _, btn in pairs(frame.totemCells) do
			local wanted = false
			for _, b in ipairs(shown) do if b == btn then wanted = true break end end
			if wanted then
				PlaceFreeCell(btn)
				if not btn:IsShown() then btn:Show() end
			elseif btn:IsShown() then
				btn:Hide()
			end
		end
		frame.layoutKey = nil
		return
	end
	for _, btn in pairs(frame.totemCells) do if btn:IsShown() then btn:Hide() end end
	for element = 1, 4 do ReturnCellToFrame(frame, frame.buttons[element]) end
	if #shown == 0 then frame:Hide() return end
	local layoutKey = mask * 100 + count * 10 + (co.vertical and 1 or 0)
	if frame.layoutKey ~= layoutKey then
		frame.layoutKey = layoutKey
		for element = 1, 4 do frame.buttons[element]:Hide() end
		LayoutCoverage(frame, shown, count)
		for _, btn in ipairs(shown) do btn:Show() end
	end
	if not frame:IsShown() then frame:Show() end
end

-- Everything back to where it starts (the unlock's Reset).
function SP:ResetCoveragePositions()
	local co = CoverageOpts()
	co.position = nil
	co.cells = nil
	local frame = self.coverageFrame
	if frame then
		frame:ClearAllPoints()
		frame:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
		for element = 1, 4 do frame.buttons[element].freePlaced = nil end
		for _, btn in pairs(frame.totemCells) do btn.freePlaced = nil end
		freeOrder = 0
	end
	self:UpdateCoverageLayout()
end

function SP:UpdateCoverageBorder()
	local frame = self.coverageFrame
	if not frame then return end
	if CoverageOpts().hideBorder then
		frame:SetBackdrop(nil)
		frame.title:Hide()
		self:SetSettingsButtonHoverOnly(frame, frame.settingsBtn, true)
	else
		SP:ApplyPanelBackdrop(frame)
		frame.title:Show()
		self:SetSettingsButtonHoverOnly(frame, frame.settingsBtn, false)
	end
end

function SP:UpdateCoverageOpacity()
	if self.coverageFrame then self.coverageFrame:SetAlpha(CoverageOpts().opacity or 1) end
end

-- Options changed: cells and rows follow.
function SP:UpdateCoverageLayout()
	if not self.coverageFrame then return end
	self.coverageFrame.layoutKey = nil
	if self.coverageDemoActive then self:CoverageDemo(true) else self:RebuildCoverage() end
end

-- Setup-wizard / settings-pane preview and the unlock mover: sample cells
-- acting out a short scene (members stepping out and back), looped.
local COVERAGE_SCENE = {
	-- each beat: per cell, who has the buff; story = the line under the preview
	{ story = "Earth and Water are down. The Warrior wandered out of Earth's reach.",
	  cells = { [1] = { true, false, true, true }, [3] = { true, true, true, true } } },
	{ story = "Now the Priest and Hunter are outside Mana Spring too.",
	  cells = { [1] = { true, false, true, true }, [3] = { true, true, false, false } } },
	{ story = "The Warrior is back in range: Earth's cell has nothing to say and drops out.",
	  cells = { [1] = { true, true, true, true }, [3] = { true, true, false, false } } },
	{ story = "Hunter back too - only the Priest is still missing Mana Spring.",
	  cells = { [1] = { true, true, true, true }, [3] = { true, true, true, false } } },
	{ story = "Everyone covered: nothing to show.",
	  cells = { [1] = { true, true, true, true }, [3] = { true, true, true, true } } },
}
local COVERAGE_DEMO_ICONS = { [1] = "Interface\\Icons\\Spell_Nature_EarthBindTotem", [2] = "Interface\\Icons\\Spell_Fire_SearingTotem",
	[3] = "Interface\\Icons\\Spell_Nature_ManaRegenTotem", [4] = "Interface\\Icons\\Spell_Nature_Windfury" }
local COVERAGE_DEMO_NAMES = { "Rogue", "Warrior", "Priest", "Hunter" }
local COVERAGE_DEMO_COLORS = { { 1.00, 0.96, 0.41 }, { 0.78, 0.61, 0.43 }, { 1, 1, 1 }, { 0.67, 0.83, 0.45 } }

function SP:CoverageDemo(on)
	local frame = self:CreateCoverageFrame()
	if on then
		local wasActive = self.coverageDemoActive
		self.coverageDemoActive = true
		if frame.settingsBtn then frame.settingsBtn:Hide() end
		-- the live engine covers (real party names) would draw over the sample rows:
		-- every cell's, the panel's (keyed 1-4) and the free-placement cells' alike
		for _, rows in pairs(self.coverageRows) do
			for _, slot in pairs(rows) do
				if slot.container then slot.container:Hide() end
			end
		end
		-- the unlock movers show free cells at their own spots; a preview (wizard, pane) shows the panel
		local freeDemo = CoverageOpts().freeCells and self.unlockDemoAll
		local d = self.coverageDemo or { beat = 1 }
		self.coverageDemo = d
		local function paint()
			local co = CoverageOpts()
			local fontSize, rowH = CoverageFont(), CoverageRowH()
			local beat = COVERAGE_SCENE[d.beat]
			self.coverageDemoStatus = beat.story
			for element = 1, 4 do frame.buttons[element]:Hide() end
			for _, btn in pairs(frame.totemCells) do btn:Hide() end
			local shown = {}
			-- free placement: every watched totem's own cell, with sample rows (so each can be placed);
			-- the panel: the scene's cells
			local targets = {}
			if freeDemo then
				for _, btn in ipairs(self:CoverageWatchedCells()) do
					targets[#targets + 1] = { btn = btn, has = beat.cells[btn.element] or { true, true, true, true } }
				end
			else
				for element = 1, 4 do
					if beat.cells[element] then targets[#targets + 1] = { btn = frame.buttons[element], has = beat.cells[element], icon = COVERAGE_DEMO_ICONS[element] } end
				end
			end
			for _, tg in ipairs(targets) do
				local btn, has = tg.btn, tg.has
				do
					if tg.icon then
						btn.icon:SetTexture(tg.icon)
						btn.iconTex = nil   -- the live update must put the real totem's icon back afterwards
					end
					SizeCell(btn, freeDemo and CellIconSize(btn.cellKey) or CoverageIconSize())
					local missing = 0
					for i = 1, 4 do
						local row = btn.rows[i]
						SP:SetSPFont(row.text, "labels", fontSize, "OUTLINE")
						row.text:SetText(COVERAGE_DEMO_NAMES[i])
						if has[i] then
							local c = COVERAGE_DEMO_COLORS[i]
							row.text:SetTextColor(c[1], c[2], c[3])
						else
							row.text:SetTextColor(1, 0.25, 0.25); missing = missing + 1
						end
						row:SetSize(math.max(btn:GetWidth(), math.ceil(row.text:GetStringWidth()) + 10), rowH)
						row:ClearAllPoints()
						row:SetPoint("TOP", btn, "BOTTOM", 0, -(i - 1) * rowH)
						row:Show()
					end
					btn.state = nil
					PaintCoverageCell(btn, missing == 0 and "covered" or "missing", missing)
					-- a fully covered cell drops out, as it does for real (movers keep every cell)
					if missing > 0 or co.hideWhenCovered == false or freeDemo then shown[#shown + 1] = btn end
				end
			end
			if freeDemo then
				frame:Hide()
				for _, btn in ipairs(shown) do PlaceFreeCell(btn); btn:Show() end
			else
				for element = 1, 4 do ReturnCellToFrame(frame, frame.buttons[element]) end
				if #shown > 0 then
					LayoutCoverage(frame, shown, 4)
					for _, btn in ipairs(shown) do btn:Show() end
					frame:Show()
				else
					frame:SetSize(150, 50)   -- keeps its spot in the preview while empty
					frame:Show()
				end
			end
		end
		d.paint = paint
		paint()
		if not wasActive then
			if self.coverageDemoTicker then self.coverageDemoTicker:Cancel() end
			self.coverageDemoTicker = C_Timer.NewTicker(2.2, function()
				if not self.coverageDemoActive then return end
				d.beat = (d.beat % #COVERAGE_SCENE) + 1
				if d.paint then d.paint() end
			end)
		end
	else
		self.coverageDemoActive = nil
		if self.coverageDemoTicker then self.coverageDemoTicker:Cancel(); self.coverageDemoTicker = nil end
		self.coverageDemoStatus = nil
		self.coverageDemo = nil
		if frame.settingsBtn then frame.settingsBtn:Show() end
		-- every cell the demo painted (the panel's four and the free-placement cells)
		local cells = {}
		for element = 1, 4 do cells[#cells + 1] = frame.buttons[element] end
		for _, btn in pairs(frame.totemCells or {}) do cells[#cells + 1] = btn end
		for _, btn in ipairs(cells) do
			btn.iconTex, btn.state = nil, nil
			for i = 1, 4 do
				local row = btn.rows and btn.rows[i]
				if row then row.text:SetText(""); row.text:SetTextColor(1, 0.25, 0.25) end
			end
		end
		HideAllCells(frame)
		-- rows carry demo names: retire every live cover and rebuild them all
		for _, rows in pairs(self.coverageRows) do
			for _, slot in pairs(rows) do
				if slot.container then pcall(slot.container.SetEnabled, slot.container, false); slot.container:Hide() end
			end
		end
		wipe(self.coverageRows)
		self:RebuildCoverage()
	end
end

if ShamanPower.RegisterPreview then
	ShamanPower:RegisterPreview("coverage", {
		frame = function() return ShamanPower:CreateCoverageFrame() end,
		demo = "SP:CoverageDemo",
		pad = 24,
		pane = { maxScale = 1.6 },
	})
end

-- Update all party range dots
function SP:UpdatePartyRangeDots()
	-- Always update range counters (even if dots are disabled)
	self:UpdateRangeCounters()

	-- Enable/disable partyRange subsystem based on whether any features are enabled
	local rangeCounterEnabled = self.opt.rangeCounter and self.opt.rangeCounter.enabled
	local dotsEnabled = self.opt.showPartyRangeDots
	local coverageEnabled = self.opt.coverage and self.opt.coverage.enabled
	if dotsEnabled or rangeCounterEnabled or coverageEnabled then
		self:EnableUpdateSubsystem("partyRange")
	else
		self:DisableUpdateSubsystem("partyRange")
	end

	if self.engineDotsBuilt then self:SetEnginePartyDotsShown(dotsEnabled) end
	local engine = self:EngineDotsOn()
	local native = self.UsingBlizzardTotemBar and self:UsingBlizzardTotemBar()
	local grid = self.GridActive and self:GridActive()

	-- Check if dots feature is enabled
	if not dotsEnabled then
		-- Hide all dots when disabled
		for element = 1, 4 do
			local overlay = self.activeTotemOverlays and self.activeTotemOverlays[element]
			if self.engineDotsBuilt and overlay and overlay.dots then
				for i = 1, 4 do overlay.dots[i]:Hide() end
			end
			if self.partyRangeDots[element] then
				for i = 1, 4 do
					if self.partyRangeDots[element][i] then
						self.partyRangeDots[element][i]:Hide()
					end
				end
			end
		end
		return
	end

	-- Get cached party/subgroup units (avoids looping 40 members every update)
	local partyUnits, partyCount = self:GetCachedPartyUnits()

	-- Update dots for each party member
	for partyIndex = 1, 4 do
		-- Engine slots bind fixed party tokens, even if another slot is empty.
		local unit = engine and self.partyUnitStrings[partyIndex] or partyUnits[partyIndex]
		local exists = unit and UnitExists(unit)

		-- Get class color for this party member
		local classColor = nil
		if exists then
			local _, class = UnitClass(unit)
			if class and RAID_CLASS_COLORS[class] then
				classColor = RAID_CLASS_COLORS[class]
			end
		end

		-- Check each element
		for element = 1, 4 do
			local mainDot = self.partyRangeDots[element] and self.partyRangeDots[element][partyIndex]

			-- Check if active overlay is showing for this element
			local activeOverlay = self.activeTotemOverlays and self.activeTotemOverlays[element]
			local useOverlay = not native and not grid and activeOverlay and activeOverlay.isActive and activeOverlay.dots
			if engine then useOverlay = UseEngineOverlay(element) end
			local overlayDot = useOverlay and activeOverlay.dots[partyIndex]
			if (native or grid or (engine and not useOverlay)) and activeOverlay
				and activeOverlay.dots and activeOverlay.dots[partyIndex] then
				activeOverlay.dots[partyIndex]:Hide()
			end

			-- Determine which dot to update (overlay if active, else main)
			local dot = useOverlay and overlayDot or mainDot

			if dot then
				if not exists then
					dot:Hide()
					if useOverlay and mainDot then mainDot:Hide() end
				else
					local haveTotem, totemName = self:GetElementTotemInfo(element)

					if haveTotem and engine then
						-- Engine mode: the class-coloured dot is the engine's; this one is
						-- the red "no buff" underneath, shown for any totem that gives a
						-- buff at all and covered as soon as the unit carries it.
						if self:GetActiveTotemBuffName(element) then
							dot:SetVertexColor(1, 0, 0)
							dot:Show()
						else
							dot:Hide()
						end
						if useOverlay and mainDot then mainDot:Hide() end
					elseif haveTotem then
						local buffName = self:GetActiveTotemBuffName(element)
						local hasBuff = buffName and self:UnitHasBuff(unit, buffName, element)

						-- Special case: Air element (4) with no buffName = Windfury Totem
						local isWindfury = (element == 4 and not buffName)
						if isWindfury then
							local playerName = UnitName(unit)
							local wfStatus = self:IsPlayerInWindfuryRange(playerName)
							if wfStatus == true then
								if classColor then
									dot:SetVertexColor(classColor.r, classColor.g, classColor.b)
								else
									dot:SetVertexColor(0, 1, 0)
								end
								dot:Show()
								if useOverlay and mainDot then mainDot:Hide() end
							elseif wfStatus == false then
								dot:SetVertexColor(1, 0, 0)
								dot:Show()
								if useOverlay and mainDot then mainDot:Hide() end
							else
								dot:Hide()
								if useOverlay and mainDot then mainDot:Hide() end
							end
						elseif hasBuff then
							if classColor then
								dot:SetVertexColor(classColor.r, classColor.g, classColor.b)
							else
								dot:SetVertexColor(0, 1, 0)
							end
							dot:Show()
							if useOverlay and mainDot then mainDot:Hide() end
						elseif buffName then
							dot:SetVertexColor(1, 0, 0)
							dot:Show()
							if useOverlay and mainDot then mainDot:Hide() end
						else
							dot:Hide()
							if useOverlay and mainDot then mainDot:Hide() end
						end
					else
						dot:Hide()
						if useOverlay and mainDot then mainDot:Hide() end
					end
				end
			end
		end
	end
end

-- ============================================================================
-- Range Counter (shows number of players in range as a number)
-- ============================================================================

SP.rangeCounterTexts = {}     -- Text elements on totem buttons
SP.rangeCounterFrames = {}    -- Unlocked movable frames

-- Element colors for range counters
SP.RangeCounterColors = {
	[1] = {0.2, 0.9, 0.2},  -- Earth - green
	[2] = {0.9, 0.2, 0.2},  -- Fire - red
	[3] = {0.2, 0.6, 1.0},  -- Water - blue
	[4] = {1.0, 1.0, 1.0},  -- Air - white
}

-- Create range counter text on a totem button
function SP:CreateRangeCounterText(button, element)
	if not button then return end
	if self.rangeCounterTexts[element] then return end

	local fontSize = (self.opt.rangeCounter and self.opt.rangeCounter.fontSize) or 14
	local text = button:CreateFontString(nil, "OVERLAY")
	SP:SetSPFont(text, "labels", fontSize, "OUTLINE")
	text:SetPoint("CENTER", button, "CENTER", 0, 0)
	text:SetTextColor(1, 1, 1)
	text:Hide()

	self.rangeCounterTexts[element] = text
end

-- Create unlocked range counter frame for an element
function SP:CreateRangeCounterFrame(element)
	if self.rangeCounterFrames[element] then return self.rangeCounterFrames[element] end

	local elementNames = { "Earth", "Fire", "Water", "Air" }
	local frameName = "ShamanPowerRangeCounter" .. elementNames[element]

	local frame = CreateFrame("Frame", frameName, UIParent, "BackdropTemplate")
	frame:SetSize(40, 40)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:SetClampedToScreen(true)
	frame:RegisterForDrag("LeftButton")
	frame.element = element

	-- Background
	frame:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 8,
		insets = { left = 2, right = 2, top = 2, bottom = 2 }
	})
	frame:SetBackdropColor(0, 0, 0, 0.7)
	frame:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)

	-- Counter text
	local fontSize = (self.opt.rangeCounter and self.opt.rangeCounter.fontSize) or 14
	local text = frame:CreateFontString(nil, "OVERLAY")
	SP:SetSPFont(text, "labels", fontSize, "OUTLINE")
	text:SetPoint("CENTER", frame, "CENTER", 0, 0)
	text:SetTextColor(1, 1, 1)
	frame.text = text

	-- Element label below the number
	local label = frame:CreateFontString(nil, "OVERLAY")
	SP:SetSPFont(label, "labels", 9, "OUTLINE")
	label:SetPoint("BOTTOM", frame, "BOTTOM", 0, 4)
	label:SetText(elementNames[element])
	local colors = self.RangeCounterColors[element]
	label:SetTextColor(colors[1], colors[2], colors[3])
	frame.label = label

	-- Restore position
	local rcOpt = self.opt.rangeCounter
	if rcOpt and rcOpt.positions and rcOpt.positions[element] then
		local pos = rcOpt.positions[element]
		frame:SetPoint(pos.point or "CENTER", UIParent, pos.relPoint or "CENTER", pos.x or 0, pos.y or 0)
	else
		-- Default position: spread horizontally near center of screen
		-- Element 1=Earth, 2=Fire, 3=Water, 4=Air -> spread from left to right
		local xOffset = (element - 2.5) * 55  -- -82.5, -27.5, 27.5, 82.5
		frame:SetPoint("CENTER", UIParent, "CENTER", xOffset, 0)
	end

	-- Apply scale and opacity
	if rcOpt then
		frame:SetScale(rcOpt.scale or 1.0)
		frame:SetAlpha(rcOpt.opacity or 1.0)

		-- Apply hide frame setting
		if rcOpt.hideFrame then
			frame:SetBackdrop(nil)
		end

		-- Apply hide label setting
		if rcOpt.hideLabel then
			label:Hide()
		end

		-- Adjust frame size based on what's visible
		if rcOpt.hideFrame and rcOpt.hideLabel then
			frame:SetSize(30, 25)
		elseif rcOpt.hideLabel then
			frame:SetSize(40, 35)
		end

		-- Apply lock setting (click-through)
		if rcOpt.locked then
			frame:EnableMouse(false)
			frame:SetMovable(false)
		end
	end

	-- Drag to move (ALT+drag)
	frame:SetScript("OnDragStart", function(self)
		if IsAltKeyDown() and self:IsMovable() then
			self:StartMoving()
		end
	end)

	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SP:SaveRangeCounterPosition(element)
	end)

	-- Tooltip
	frame:SetScript("OnEnter", function(self)
		if SP.opt.ShowTooltips then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(elementNames[element] .. " Range Counter")
			GameTooltip:AddLine("Players in range of your " .. elementNames[element] .. " totem", 1, 1, 1)
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine("ALT+Drag to move", 0.7, 0.7, 0.7)
			GameTooltip:Show()
		end
	end)

	frame:SetScript("OnLeave", function(self)
		GameTooltip:Hide()
	end)

	frame:Hide()
	self.rangeCounterFrames[element] = frame
	return frame
end

-- Setup range counters on all totem buttons
function SP:SetupRangeCounters()
	for element = 1, 4 do
		local button = PartyRangeHost(element)
		if button then
			self:CreateRangeCounterText(button, element)
		end
	end
end

-- Update frame lock state (click-through)
function SP:UpdateRangeCounterLock()
	local rcOpt = self.opt.rangeCounter
	if not rcOpt then return end

	local locked = rcOpt.locked
	for element = 1, 4 do
		local frame = self.rangeCounterFrames[element]
		if frame then
			frame:EnableMouse(not locked)
			frame:SetMovable(not locked)
		end
	end
end

-- Update frame style (hide frame background and/or label)
-- Save a range counter's position as a CENTER offset from screen centre, in
-- the frame's own units (what the restore at creation expects), and re-anchor
-- the same way so drag and scale changes agree.
function SP:SaveRangeCounterPosition(element)
	local frame = self.rangeCounterFrames and self.rangeCounterFrames[element]
	if not frame then return end
	local cx, cy = frame:GetCenter()
	if not cx then return end
	local scale = frame:GetScale() or 1
	local x = cx - (UIParent:GetWidth() / 2) / scale
	local y = cy - (UIParent:GetHeight() / 2) / scale
	self.opt.rangeCounter = self.opt.rangeCounter or {}
	self.opt.rangeCounter.positions = self.opt.rangeCounter.positions or {}
	self.opt.rangeCounter.positions[element] = { point = "CENTER", relPoint = "CENTER", x = x, y = y }
	frame:ClearAllPoints()
	frame:SetPoint("CENTER", UIParent, "CENTER", x, y)
end

function SP:UpdateRangeCounterFrameStyle()
	local rcOpt = self.opt.rangeCounter
	if not rcOpt then return end

	for element = 1, 4 do
		local frame = self.rangeCounterFrames[element]
		if frame then
			-- Hide/show frame background
			if rcOpt.hideFrame then
				frame:SetBackdrop(nil)
			else
				frame:SetBackdrop({
					bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
					edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
					tile = true, tileSize = 16, edgeSize = 8,
					insets = { left = 2, right = 2, top = 2, bottom = 2 }
				})
				frame:SetBackdropColor(0, 0, 0, 0.7)
				frame:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
			end

			-- Hide/show element label
			if frame.label then
				if rcOpt.hideLabel then
					frame.label:Hide()
				else
					frame.label:Show()
				end
			end

			-- Adjust frame size based on what's visible
			if rcOpt.hideFrame and rcOpt.hideLabel then
				-- Just the number - make frame smaller
				frame:SetSize(30, 25)
			elseif rcOpt.hideLabel then
				-- Frame but no label
				frame:SetSize(40, 35)
			else
				-- Full frame with label
				frame:SetSize(40, 40)
			end
		end
	end
end

-- Update range counter displays
function SP:UpdateRangeCounters()
	-- Setup-wizard preview: keep sample data while a demo is showing
	if self.partyRangeDemoActive then return end
	local rcOpt = self.opt.rangeCounter
	if not rcOpt or not rcOpt.enabled then
		-- Hide all counters when disabled
		for element = 1, 4 do
			if self.rangeCounterTexts[element] then
				self.rangeCounterTexts[element]:Hide()
			end
			if self.rangeCounterFrames[element] then
				self.rangeCounterFrames[element]:Hide()
			end
		end
		return
	end

	-- Get cached party/subgroup units (avoids looping 40 members every update)
	local partyUnits, totalPartyMembers = self:GetCachedPartyUnits()

	-- Count players in range for each element
	for element = 1, 4 do
		local inRangeCount = 0
		local haveTotem = self:GetElementTotemInfo(element)
		local hasTrackableBuff = false  -- Track if this totem can be tracked

		if haveTotem and totalPartyMembers > 0 then
			local buffName = self:GetActiveTotemBuffName(element)

			for _, unit in ipairs(partyUnits) do
				if UnitExists(unit) then
					-- Special case: Air element with Windfury
					local isWindfury = (element == 4 and not buffName)
					if isWindfury then
						hasTrackableBuff = true  -- Windfury is trackable via broadcast
						local playerName = UnitName(unit)
						local wfStatus = self:IsPlayerInWindfuryRange(playerName)
						if wfStatus == true then
							inRangeCount = inRangeCount + 1
						end
					elseif buffName then
						hasTrackableBuff = true  -- Has a trackable buff
						local hasBuff = self:UnitHasBuff(unit, buffName, element)
						if hasBuff then
							inRangeCount = inRangeCount + 1
						end
					end
					-- If no buffName and not Windfury, hasTrackableBuff stays false
					-- (e.g., Tremor, Searing, Disease Cleansing, Earthbind, etc.)
				end
			end
		end

		-- Determine which display to use
		local useUnlocked = (rcOpt.location == "unlocked")
		local counterText = nil
		local counterFrame = nil

		if useUnlocked then
			-- Use unlocked frame
			counterFrame = self.rangeCounterFrames[element] or self:CreateRangeCounterFrame(element)
			counterText = counterFrame and counterFrame.text
			-- Hide icon text
			if self.rangeCounterTexts[element] then
				self.rangeCounterTexts[element]:Hide()
			end
		else
			-- Use icon text
			counterText = self.rangeCounterTexts[element]
			-- Hide unlocked frame
			if self.rangeCounterFrames[element] then
				self.rangeCounterFrames[element]:Hide()
			end
		end

		-- Update the counter display
		if counterText then
			if useUnlocked and counterFrame and totalPartyMembers > 0 then
				-- Unlocked frames: always show all 4 frames when in a party
				counterFrame:Show()

				if haveTotem and hasTrackableBuff then
					-- Totem is active and has trackable buff - show the count
					counterText:SetText(tostring(inRangeCount))
					counterText:Show()
				else
					-- No totem or totem has no trackable buff - show nothing
					counterText:SetText("")
					counterText:Hide()
				end

				-- Set color
				if rcOpt.useElementColors ~= false then
					local colors = self.RangeCounterColors[element]
					counterText:SetTextColor(colors[1], colors[2], colors[3])
				else
					counterText:SetTextColor(1, 1, 1)
				end

				-- Update font size
				local fontSize = rcOpt.fontSize or 14
				SP:SetSPFont(counterText, "labels", fontSize, "OUTLINE")

			elseif not useUnlocked and haveTotem and hasTrackableBuff and totalPartyMembers > 0 then
				-- On-icon mode: only show when totem is active and has trackable buff
				counterText:SetText(tostring(inRangeCount))

				-- Set color
				if rcOpt.useElementColors ~= false then
					local colors = self.RangeCounterColors[element]
					counterText:SetTextColor(colors[1], colors[2], colors[3])
				else
					counterText:SetTextColor(1, 1, 1)
				end

				-- Update font size
				local fontSize = rcOpt.fontSize or 14
				SP:SetSPFont(counterText, "labels", fontSize, "OUTLINE")

				counterText:Show()
			else
				-- No totem, no trackable buff, or no party - hide
				counterText:Hide()
				if useUnlocked and counterFrame then
					counterFrame:Hide()
				end
			end
		end
	end
end

-- ============================================================================
-- Setup-wizard preview: borrow the Earth range-counter frame and fill it with
-- believable sample data so the user sees what the range counter looks like
-- without needing a live party/totem. No comms, no timers, no SavedVariables.
-- ============================================================================
function SP:PartyRangeDemo(on)
	-- The wizard borrows one frame (Earth). The unlock UI shows all four
	-- movers and asks for sample numbers in each (SP.unlockDemoAll), so
	-- they can be lined up against real content.
	if self.unlockDemoAll then
		local SAMPLE = { 3, 1, 2, 4 }
		for element = 1, 4 do
			local frame = (self.rangeCounterFrames and self.rangeCounterFrames[element]) or self:CreateRangeCounterFrame(element)
			if frame and frame.text then
				if on then
					self.partyRangeDemoActive = true
					local colors = self.RangeCounterColors[element]
					frame.text:SetTextColor(colors[1], colors[2], colors[3])
					frame.text:SetText(tostring(SAMPLE[element]))
					frame.text:Show()
					if frame.label then frame.label:Show() end
					frame:Show()
				else
					frame.text:SetText("")
					frame:Hide()
				end
			end
		end
		if not on then
			self.partyRangeDemoActive = nil
			if self.UpdateRangeCounterFrameStyle then self:UpdateRangeCounterFrameStyle() end
			if self.UpdateRangeCounters then self:UpdateRangeCounters() end
		end
		return
	end
	if on then
		self.partyRangeDemoActive = true
		-- Reuse the module's own counter frame + rendering; only the data is faked.
		local frame = (self.rangeCounterFrames and self.rangeCounterFrames[1]) or self:CreateRangeCounterFrame(1)
		if not frame then return end
		-- Force the default (visible) frame style so the preview reads clearly,
		-- regardless of the user's hideFrame/hideLabel options.
		if frame.SetBackdrop then
			frame:SetBackdrop({
				bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
				edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
				tile = true, tileSize = 16, edgeSize = 8,
				insets = { left = 2, right = 2, top = 2, bottom = 2 }
			})
			frame:SetBackdropColor(0, 0, 0, 0.7)
			frame:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
		end
		frame:SetSize(40, 40)
		if frame.label then frame.label:Show() end
		if frame.text then
			local colors = self.RangeCounterColors[1]
			frame.text:SetTextColor(colors[1], colors[2], colors[3])
			SP:SetSPFont(frame.text, "labels", 14, "OUTLINE")
			-- Sample: 3 of a 5-member subgroup are inside Earth totem range.
			frame.text:SetText("3")
			frame.text:Show()
		end
		frame:Show()
	else
		self.partyRangeDemoActive = nil
		local frame = self.rangeCounterFrames and self.rangeCounterFrames[1]
		if frame then
			if frame.text then frame.text:SetText("") end
			frame:Hide()
		end
		-- Restore the user's real frame style (hideFrame/hideLabel/size) that
		-- Demo(true) forcibly overrode, then repaint real data.
		if self.UpdateRangeCounterFrameStyle then self:UpdateRangeCounterFrameStyle() end
		if self.UpdateRangeCounters then self:UpdateRangeCounters() end
	end
end

-- Register the range-counter frame with the setup-wizard preview harness.
if ShamanPower.RegisterPreview then
	ShamanPower:RegisterPreview("partyrange", {
		frame = function() return ShamanPower:CreateRangeCounterFrame(1) end,
		demo = "SP:PartyRangeDemo",
		pad = 24,
	})
end
