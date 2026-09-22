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
-- Forever's Windfury Totem is a party BUFF ("Attack Power increased by $s1.
-- Granted $s2 Extra Attack.", Spell.db2 1.60.1: 8516 / 10608 / 10610), not the
-- weapon enchant the classic family applies, so there it is tracked like any
-- other totem buff and the Windfury comms special case never runs.
if WOW_PROJECT_ID ~= nil and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE then
	SP.TotemBuffSpellIDs[4][1] = 8516
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
}

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

-- Setup all party range dots for the mini totem bar
function SP:SetupPartyRangeDots()
	for element = 1, 4 do
		local button = self.totemButtons[element]
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
		return cached.buffName
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
				self.totemBuffCache[element] = {totemName = totemName, buffName = buffName}
				return buffName
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
	if not buffName then return false end

	if element and SPCompat and SPCompat.AurasUnreadable and SPCompat.AurasUnreadable() then
		local near = ShamanPower.TotemDropInRange and ShamanPower:TotemDropInRange(element, unit)
		if near == nil then near = self:UnitNearShaman(unit) end          -- no positions (instances)
		if near == nil then near = self.partyRangeLast[unit .. element] end
		if near == nil then near = true end   -- never call someone uncovered on a guess
		return near
	end

	local has = false
	for i = 1, 32 do
		local name = UnitBuff(unit, i)
		if not name then break end
		if name == buffName then has = true break end
	end
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
SP.engineDots = {}            -- [element][partyIndex] = { container = frame|nil, key = string }
local engineDotsPending = false
local engineDotsReady = false -- SetupPartyRangeDots has run (buttons exist)

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

-- Build, or rebuild where the class colour or the placement changed. Cheap
-- when nothing changed (one key per slot), so layout code calls it freely.
function SP:RebuildEnginePartyDots()
	if not (engineDotsReady and EngineDotsAvailable()) then return end
	if InCombatLockdown() then engineDotsPending = true return end
	engineDotsPending = false
	pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
	local built = false
	for element = 1, 4 do
		local btn = self.totemButtons and self.totemButtons[element]
		if btn then
			self.engineDots[element] = self.engineDots[element] or {}
			for i = 1, 4 do
				local unit = self.partyUnitStrings[i]
				local exists = UnitExists(unit)
				local _, class = UnitClass(unit)
				local color = class and RAID_CLASS_COLORS[class]
				local r, g, b = 0, 1, 0
				if color then r, g, b = color.r, color.g, color.b end
				local point, relPoint, x, y = ShamanPower:PartyDotAnchor(i, btn)
				local key = (exists and (class or "?") or "-") .. "|" .. tostring(self.opt.partyDotSize or 5) .. "|"
					.. tostring(self.opt.partyDotOutline ~= false) .. "|" .. point .. relPoint .. x .. "," .. y
				local slot = self.engineDots[element][i]
				if not slot or slot.key ~= key then
					if slot and slot.container then
						pcall(slot.container.SetEnabled, slot.container, false)
						slot.container:Hide()
					end
					local container = exists and BuildEngineDot(element, i, btn, r, g, b) or nil
					if container then container:SetShown(self.opt.showPartyRangeDots and true or false) end
					self.engineDots[element][i] = { container = container, key = key }
				end
				if self.engineDots[element][i].container then built = true end
			end
		end
	end
	self.engineDotsBuilt = built or nil
	self.engineDotsShown = nil   -- re-applied by the next dots pass
end

function SP:SetEnginePartyDotsShown(on)
	on = on and true or false
	if self.engineDotsShown == on then return end
	self.engineDotsShown = on
	for element = 1, 4 do
		local slots = self.engineDots[element]
		if slots then
			for i = 1, 4 do
				local c = slots[i] and slots[i].container
				if c then c:SetShown(on) end
			end
		end
	end
end

-- Roster changes recolour (or add / drop) a slot; a fight defers it.
local engineDotEvents = CreateFrame("Frame")
engineDotEvents:RegisterEvent("GROUP_ROSTER_UPDATE")
engineDotEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
engineDotEvents:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_REGEN_ENABLED" then
		if engineDotsPending then SP:RebuildEnginePartyDots() end
	else
		SP:RebuildEnginePartyDots()
	end
end)

-- Update all party range dots
function SP:UpdatePartyRangeDots()
	-- Always update range counters (even if dots are disabled)
	self:UpdateRangeCounters()

	-- Enable/disable partyRange subsystem based on whether any features are enabled
	local rangeCounterEnabled = self.opt.rangeCounter and self.opt.rangeCounter.enabled
	local dotsEnabled = self.opt.showPartyRangeDots
	if dotsEnabled or rangeCounterEnabled then
		self:EnableUpdateSubsystem("partyRange")
	else
		self:DisableUpdateSubsystem("partyRange")
	end

	if self.engineDotsBuilt then self:SetEnginePartyDotsShown(dotsEnabled) end
	local engine = self:EngineDotsOn()

	-- Check if dots feature is enabled
	if not dotsEnabled then
		-- Hide all dots when disabled
		for element = 1, 4 do
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
		local unit = partyUnits[partyIndex]
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
			local useOverlay = activeOverlay and activeOverlay.isActive and activeOverlay.dots
			local overlayDot = useOverlay and activeOverlay.dots[partyIndex]

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
	text:SetFont("Fonts\\FRIZQT__.TTF", fontSize, "OUTLINE")
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
	text:SetFont("Fonts\\FRIZQT__.TTF", fontSize, "OUTLINE")
	text:SetPoint("CENTER", frame, "CENTER", 0, 0)
	text:SetTextColor(1, 1, 1)
	frame.text = text

	-- Element label below the number
	local label = frame:CreateFontString(nil, "OVERLAY")
	label:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
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
		local button = self.totemButtons[element]
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
				counterText:SetFont("Fonts\\FRIZQT__.TTF", fontSize, "OUTLINE")

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
				counterText:SetFont("Fonts\\FRIZQT__.TTF", fontSize, "OUTLINE")

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
			frame.text:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
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
