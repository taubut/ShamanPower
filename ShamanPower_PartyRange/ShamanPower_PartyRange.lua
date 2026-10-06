-- ============================================================================
-- ShamanPower Party Range Module
-- Shows party members in/out of totem range via dots and counters
-- ============================================================================

-- "First Surname" on WoW: Forever (SPCompat.UnitName); other clients unchanged
local UnitName = (SPCompat and SPCompat.UnitName) or UnitName
local SP = ShamanPower
local UnitBuff = SPCompat and SPCompat.UnitBuff or UnitBuff   -- ShamanPower's own reader on Forever, never another addon's global
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

-- ============================================================================
-- Theme looks (General > Themes, ShamanPowerTheme.lua). Looks only: on Standard
-- every read below is nil and each paint site runs today's code as it was.
-- tb.dots-missing / mod.coverage-dots-missing: the red "no buff" dot.
-- tb.dots-class / mod.coverage-dots-class: the engine is asked, and every theme
-- keeps WoW's class colours for now (brand-guidelines 8.1), so nothing changes.
-- mod.partybuff-frame: the unlocked counter frames. mod.coverage-colors: the
-- Coverage panel. Colours are resolved on a theme change, never while painting.
-- ============================================================================
local themeMissDot, themeMissCov = nil, nil   -- nil: today's red (1, 0, 0)
local THEME_MISS_DOT, THEME_MISS_COV = { 1, 0, 0 }, { 1, 0, 0 }
local function ThemeRGB(spot, role)
	if SP.ThemeColor then return SP:ThemeColor(spot, role) end
end
local function ThemeAlphaOf(spot, role, default)
	return (SP.ThemeAlpha and SP:ThemeAlpha(spot, role)) or default
end
local function ThemeMissing(spot, t)
	local r, g, b = ThemeRGB(spot, "missing")
	if not r then return nil end
	t[1], t[2], t[3] = r, g, b
	return t
end
local function ResolveThemeLooks()
	themeMissDot = ThemeMissing("tb.dots-missing", THEME_MISS_DOT)
	themeMissCov = ThemeMissing("mod.coverage-dots-missing", THEME_MISS_COV)
end
ResolveThemeLooks()
-- the totem bar's red dot, and the Coverage panel's
local function PaintMissingDot(dot)
	local c = themeMissDot
	if c then dot:SetVertexColor(c[1], c[2], c[3]) else dot:SetVertexColor(1, 0, 0) end
end
local function PaintMissingCov(dot)
	local c = themeMissCov
	if c then dot:SetVertexColor(c[1], c[2], c[3]) else dot:SetVertexColor(1, 0, 0) end
end
local classSetsSeen = {}   -- the Class Colors set each dot kind was last built with
-- a class-coloured dot: the theme's colour for that class if it has one, else
-- the Class Colors set it uses (General > Themes; WoW's = `color`, RAID_CLASS_COLORS
-- exactly as today). One table per class, made once.
local themeClassColors = {}
local function ThemeClassColor(spot, class, color)
	if not (color and class and SP.ThemeColor) then return color end
	local r, g, b = SP:ThemeColor(spot, class)
	if not r and SP.ThemeClassSetRGB then r, g, b = SP:ThemeClassSetRGB(spot, class) end
	if not r then return color end
	local bySpot = themeClassColors[spot]
	if not bySpot then bySpot = {}; themeClassColors[spot] = bySpot end
	local t = bySpot[class]
	if not t then t = {}; bySpot[class] = t end
	t.r, t.g, t.b = r, g, b
	return t
end
-- the unlocked counter frames (today black 70%, border grey 80%); `restore`
-- puts today's back (the Themes tab went back to Standard)
local function ThemeCounterFrame(frame, restore)
	local r, g, b = ThemeRGB("mod.partybuff-frame", "bg")
	if r then frame:SetBackdropColor(r, g, b, ThemeAlphaOf("mod.partybuff-frame", "bg", 0.7))
	elseif restore then frame:SetBackdropColor(0, 0, 0, 0.7) end
	r, g, b = ThemeRGB("mod.partybuff-frame", "border")
	if r then frame:SetBackdropBorderColor(r, g, b, 0.8)
	elseif restore then frame:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8) end
end
-- the Coverage panel (today SP:ApplyPanelBackdrop's colours)
local function ThemeCoveragePanel(frame, restore)
	local bg, edge = SP.PANEL_BG, SP.PANEL_BORDER
	local r, g, b = ThemeRGB("mod.coverage-colors", "bg")
	if r then frame:SetBackdropColor(r, g, b, ThemeAlphaOf("mod.coverage-colors", "bg", bg[4]))
	elseif restore then frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4]) end
	r, g, b = ThemeRGB("mod.coverage-colors", "border")
	if r then frame:SetBackdropBorderColor(r, g, b, edge[4])
	elseif restore then frame:SetBackdropBorderColor(edge[1], edge[2], edge[3], edge[4]) end
end
-- the Themes tab's swatches show the counter frames' own colours as today's
if SP.ThemeSetRoleStd then
	SP:ThemeSetRoleStd("mod.partybuff-frame", "bg", "000000")
	SP:ThemeSetRoleStd("mod.partybuff-frame", "border", "4D4D4D")
end

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
if SPCompat.FOREVER then
	-- WoW: Forever (1.60.1.70009) made Windfury Totem a party buff: 8515 / 10609 /
	-- 10612 "Windfury Totem" is an aura on every party member in range (it procs
	-- the extra attack itself), shown like Strength of Earth. TBC's weapon enchant
	-- is gone there, and so are the WFBUFF comms and the companion aura it needed.
	SP.TotemBuffSpellIDs[4][1] = 8515
	-- Forever reuses 8215 (TBC's Flametongue Totem buff) for a spell called
	-- "Rapid Cast", which broke the name match. There the entry is the totem
	-- spell itself (its name matches) and its buffs are the effect auras.
	SP.TotemBuffSpellIDs[2][5] = 8227
else
	-- TBC Anniversary: Flametongue Totem enchants weapons (like Windfury Totem)
	-- and puts no buff on anyone, and no addon can see another player's weapon:
	-- not tracked (8215 is "Rapid Cast" there, so the dots were always red)
	SP.TotemBuffSpellIDs[2][5] = nil
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
	[8515]  = { 8515, 10609, 10612 },                       -- Windfury Totem (Forever: a party buff)
	[8227]  = { 8230, 8250, 10521, 15036 },                 -- Flametongue Totem on Forever: the effect auras party members carry
}

-- TBC Anniversary's level-70 ranks (the buffs of 25528, 25508/25509, 25570, 25567,
-- 25560, 25563, 25574 and 25577 in Anniversary's SpellName.db2): matched by ID too
if not SPCompat.FOREVER then
	for buff, ids in pairs({ [8076] = { 25527 }, [8072] = { 25506, 25507 }, [5677] = { 25569 }, [5672] = { 25566 },
		[8182] = { 25559 }, [8185] = { 25562 }, [10596] = { 25573 }, [15108] = { 25576 } }) do
		for _, id in ipairs(ids) do table.insert(SP.TotemBuffRanks[buff], id) end
	end
end

-- Extra aura IDs for the engine-drawn dots only ([element] = { spell IDs }).
SP.ExtraEngineAuraIDs = {}

-- Resolve buff spell IDs to exact names via GetSpellInfo (same approach as TotemTimers)
-- This guarantees exact name matching with UnitBuff results
SP.TotemBuffNames = {}
for element, buffs in pairs(SP.TotemBuffSpellIDs) do
	SP.TotemBuffNames[element] = {}
	for idx, spellId in pairs(buffs) do
		local name = SPCompat.SpellName(spellId)
		if name then
			SP.TotemBuffNames[element][idx] = name
		end
	end
end

-- A totem's name may differ from its effect aura's name. Cache all rank/effect IDs.
SP.TotemBuffIDSets = {}
do
	for _, list in pairs(SP.TotemBuffSpellIDs) do
		for _, base in pairs(list) do
			local name = SPCompat.SpellName(base)
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
	-- (not while ShamanPower is switched off: then nothing runs)
	if not self:IsOff() then self:EnableUpdateSubsystem("partyRange") end
	engineDotsReady = true
	self:RebuildEnginePartyDots()
end

-- Get the buff name for the currently active totem of an element
function SP:GetActiveTotemBuffName(element)
	local haveTotem, totemName = self:GetElementTotemInfo(element)
	if issecretvalue(haveTotem) or issecretvalue(totemName) then return nil end
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
	if not buffNames then
		self.totemBuffCache[element] = {totemName = totemName, buffName = nil}
		return nil
	end

	-- Match the localized cast name: a translated effect aura can use different
	-- words from the totem that applies it. Keep the active totem, not assignments.
	for totemIndex, buffName in pairs(buffNames) do
		if type(buffName) == "string" then
			local spellID = self:GetTotemSpell(element, totemIndex)
			local fallback = self.TotemNames and self.TotemNames[element] and self.TotemNames[element][totemIndex]
			if spellID and SPCompat.TotemNameMatches(totemName, spellID, fallback) then
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

-- A party member plainly far away: out of sight (the game draws nobody past ~100 yd). They
-- cannot be in range of your totems, and the game can hand over a far-away member's
-- buffs without saying whose they are, so another shaman's own totems lit your dots
-- (reported 2026-10-04: a party member two zones away). Never a range from the SHAMAN: a
-- member standing at your totems while you are 40 yd away is covered (the buff read, or the
-- drop point, answers that). An answer the game keeps to itself (a secret, or none) never
-- counts as far.
function SP:PartyUnitFarAway(unit)
	if not unit or unit == "player" then return false end
	local ok, visible = pcall(UnitIsVisible, unit)
	return ok and not (issecretvalue and issecretvalue(visible)) and not visible or false
end

function SP:UnitHasBuff(unit, buffName, element)
	if SPCompat.FOREVER and issecretvalue(buffName) then return false end
	if not buffName then return false end
	if self:PartyUnitFarAway(unit) then
		if element then self.partyRangeLast[unit .. element] = false end
		return false
	end

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

	-- only YOUR totem's buff counts: another shaman's Stoneskin on a party member never lights
	-- your dot. The game marks a buff from your own totem as yours (measured on Forever: your
	-- Stoneskin reads sourceUnit "player"), so the "PLAYER" filter keeps just those.
	local has = false
	if SPCompat.FOREVER then
		local ids = SP.TotemBuffIDSets[buffName]
		if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
			for i = 1, 40 do
				local aura = C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL|PLAYER")
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
		local ids = SP.TotemBuffIDSets[buffName]
		for i = 1, 32 do
			local name, _, _, _, _, _, _, _, _, spellID = UnitBuff(unit, i, "PLAYER")
			if issecretvalue(name) or issecretvalue(spellID) then break end
			if not name then break end
			if (spellID and ids and ids[spellID]) or name == buffName then has = true break end
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
	return self.engineDotsBuilt == true and self.opt.showPartyRangeDots and not self.opt.partyDotsMissingOnly and true or false
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

-- One game-drawn aura slot on a party token: an AuraContainer over `parent` with
-- a single slot for YOUR buffs among `ids` (spell IDs, every rank), whose look
-- `init` draws once (initializeFrame), then bound to the unit and switched on.
-- The totem bar's dots, Totem Coverage and the Party Strip all build theirs here.
-- Out of combat only. Returns the container, or nil, the error and where it failed.
local function NewPartyAuraSlot(parent, unit, key, ids, init, levelUp)
	local ok, container = pcall(CreateFrame, "AuraContainer", nil, parent, "CustomAuraContainerTemplate")
	if not ok or not container then return nil, container, "create" end
	container:SetAllPoints(parent)
	container:SetFrameLevel(parent:GetFrameLevel() + levelUp)
	local okAdd, err = pcall(container.AddAuraSlot, container, key, "HELPFUL|PLAYER", {   -- your totem's buff only
		candidateFilters = { includeSpellIDs = ids },
		initializeFrame = init,
	})
	if not okAdd then
		container:Hide()
		return nil, err, "add"
	end
	pcall(container.SetUnit, container, unit)
	pcall(container.SetEnabled, container, true)
	pcall(container.UpdateAllAuras, container)
	return container
end

-- The dot look inside a slot's button (from its initializeFrame): no mouse, an
-- optional dark rim and the dot in its color. tex nil = the Dot Shape, with Gem Dot
-- Finish; rimAlpha nil = 0.9 (the dots); noGem: a dot of its own fixed look.
local function PaintDotButton(button, size, outline, r, g, b, tex, rimAlpha, noGem)
	if button.SetMouseClickEnabled then pcall(button.SetMouseClickEnabled, button, false) end
	if button.SetMouseMotionEnabled then pcall(button.SetMouseMotionEnabled, button, false) end
	tex = tex or SP:DotTexture()   -- Dot Shape
	if outline then
		local o = button:CreateTexture(nil, "OVERLAY", nil, -1)
		o:SetTexture(tex)
		o:SetVertexColor(0, 0, 0, rimAlpha or 0.9)
		o:SetPoint("CENTER", button, "CENTER", 0, 0)
		o:SetSize(size + 2, size + 2)
	end
	local dot = button:CreateTexture(nil, "OVERLAY")
	dot:SetTexture(tex)
	dot:SetVertexColor(r, g, b)
	dot:SetAllPoints(button)
	if SP.DotGem and not noGem then SP:DotGem(dot) end   -- Gem Dot Finish
end

local function BuildEngineDot(element, partyIndex, btn, r, g, b)
	local unit = SP.partyUnitStrings[partyIndex]
	local size = SP.opt.partyDotSize or 5
	local outline = SP.opt.partyDotOutline ~= false
	local point, relPoint, x, y = ShamanPower:PartyDotAnchor(partyIndex, btn)
	-- the addon's own dots hang from the same stand-in, which steps out past a
	-- flyout tab on the dots' side: both sets move together, no rebuild
	local dotFrame = ShamanPower.PlacePartyDotFrame and ShamanPower:PlacePartyDotFrame(btn) or btn
	-- (above the button art and the active-totem overlay)
	local container, err, stage = NewPartyAuraSlot(btn, unit, "dot", ElementBuffMap(element), function(button)
		button:ClearAllPoints()
		button:SetSize(size, size)
		button:SetPoint(point, dotFrame, relPoint, x, y)
		PaintDotButton(button, size, outline, r, g, b)
	end, 10)
	if not container then
		if SPCompat.Trace then
			if stage == "create" then
				SPCompat.Trace("DOTS container %d/%d create failed: %s", element, partyIndex, tostring(err))
			else
				SPCompat.Trace("DOTS AddAuraSlot %d/%d failed: %s", element, partyIndex, tostring(err))
			end
		end
		return nil
	end
	return container
end

local function UseEngineOverlay(element)
	if SP.GridActive and SP:GridActive() then return false end
	if SP.UsingBlizzardTotemBar and SP:UsingBlizzardTotemBar() then return false end
	if SP.opt.activeTotemAsMain or (SP.CompactActive and SP:CompactActive()) then return false end
	local overlay = SP.activeTotemOverlays and SP.activeTotemOverlays[element]
	return overlay and overlay.isActive and overlay.dots and true or false
end

-- This is our own visibility intent, never a read from the aura subtree. By ALPHA: the game's
-- containers may not be shown or hidden in a fight (a totem dropped or a member walking off mid-pull
-- changes this), and alpha is never protected. A live container stays shown (made shown, out of combat).
local function ShowEngineRecord(record, shown)
	if record and record.container and record.shown ~= shown then
		local c = record.container
		-- (disabled while unlit: the game registers a container for aura events only while it is shown AND
		-- enabled, so an unlit one costs nothing; enabling is the container's own call, allowed in a fight)
		pcall(c.SetEnabled, c, shown)
		if shown then pcall(c.UpdateAllAuras, c) end
		c:SetAlpha(shown and 1 or 0)
		record.shown = shown
	end
end

local function RetireEngineRecord(record)
	if record and record.container then
		pcall(record.container.SetEnabled, record.container, false)
		record.container:SetAlpha(0)
		record.shown = false
		if not InCombatLockdown() then record.container:Hide() end   -- (retired in a rebuild: out of combat)
	end
end

local function RebuildEngineRecord(record, element, i, host, exists, class, r, g, b)
	if not host then RetireEngineRecord(record); return nil end
	local point, relPoint, x, y = SP:PartyDotAnchor(i, host)
	local key = (exists and (class or "?") or "-") .. "|" .. tostring(SP.opt.partyDotSize or 5) .. "|"
		.. tostring(SP.opt.partyDotOutline ~= false) .. "|" .. tostring(SP.opt.dotShape) .. "|" .. point .. relPoint .. x .. "," .. y
		.. "|" .. tostring(SP.ThemeClassColorSet and SP:ThemeClassColorSet("tb.dots-class")) .. tostring(SP.opt.dotGem)   -- Class Colors / Gem Dot Finish
	if record and record.key == key and record.host == host and (record.container or not exists) then return record end
	RetireEngineRecord(record)
	-- this spot's display for this look, if it had one before (a class coming back): no new one
	local kept = host.spEngineDotsKept
	if not kept then kept = {}; host.spEngineDotsKept = kept end
	local keptKey = element .. ":" .. i .. "|" .. key
	local container = exists and kept[keptKey] or nil
	if container then
		container:Show()   -- (a retired one was hidden; rebuilds run out of combat only)
	else
		container = exists and BuildEngineDot(element, i, host, r, g, b) or nil
		if container then kept[keptKey] = container end
	end
	if container then   -- (kept shown: SetEnginePartyDotsShown lights it, by alpha and its own on / off)
		pcall(container.SetEnabled, container, false)
		container:SetAlpha(0)
	end
	return { container = container, key = key, host = host, shown = false }
end

function SP:SetEnginePartyDotsShown(on)
	on = on and not self.opt.partyDotsMissingOnly and true or false   -- "only missing" draws its own dots
	self.engineDotsShown = on
	-- a member's dot only for an element you have a totem of down, and never for a member
	-- plainly far away (the game draws a dot for any matching buff it is handed)
	local near = self._engineDotNear
	if not near then near = {}; self._engineDotNear = near end
	for i = 1, 4 do
		local unit = self.partyUnitStrings[i]
		near[i] = on and unit ~= nil and UnitExists(unit) and not self:PartyUnitFarAway(unit) or false
	end
	for element = 1, 4 do
		local slots = self.engineDots[element]
		local overlay = UseEngineOverlay(element)
		if slots then
			local down = on and (self:GetElementTotemInfo(element)) and true or false
			for i = 1, 4 do
				local slot = slots[i]
				if slot then
					local shown = down and near[i] and true or false
					-- Hide the old destination first, including when both are disabled.
					if overlay then
						ShowEngineRecord(slot.main, false); ShowEngineRecord(slot.overlay, shown)
					else
						ShowEngineRecord(slot.overlay, false); ShowEngineRecord(slot.main, shown)
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
			if color then color = ThemeClassColor("tb.dots-class", class, color) end
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
	if self:IsOff() then return end   -- switched off: the switch back on rebuilds
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

-- Roster changes recolour (or add / drop) a slot; a fight defers it. A raid or
-- battleground forming fires dozens of GROUP_ROSTER_UPDATEs, and every slot that
-- changed builds new engine displays: rebuild once, 0.3 s after the last one.
-- One timer at a time: when it fires with newer events behind it, it waits
-- again for the rest of their 0.3 s (a storm that never pauses still rebuilds
-- every 5 s).
local rosterQueued, rosterFirst, rosterLast = false, 0, 0
local function rosterSettled()
	local now = GetTime()
	local wait = rosterLast + 0.3 - now
	if wait > 0.01 and now - rosterFirst < 5 then C_Timer.After(wait, rosterSettled) return end
	rosterQueued = false
	SP:RebuildEnginePartyDots()
	if SP.RebuildCoverage then SP:RebuildCoverage() end
	if SP.RebuildPartyStrip then SP:RebuildPartyStrip() end
end
local engineDotEvents = CreateFrame("Frame")
if SPCompat and SPCompat.StressRegister then SPCompat.StressRegister(engineDotEvents, "Party Range") end
engineDotEvents:RegisterEvent("GROUP_ROSTER_UPDATE")
engineDotEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
engineDotEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
engineDotEvents:SetScript("OnEvent", function(_, event)
	if SP:IsOff() then return end   -- switched off: the switch back on rebuilds
	if event == "PLAYER_REGEN_ENABLED" then
		if engineDotsPending then SP:RebuildEnginePartyDots() end
		if SP._coveragePending and SP.RebuildCoverage then SP:RebuildCoverage() end   -- was a local read before it existed
		if SP.PartyStripAfterCombat then SP:PartyStripAfterCombat() end
	else
		rosterLast = GetTime()
		if not rosterQueued then
			rosterQueued, rosterFirst = true, rosterLast
			C_Timer.After(0.3, rosterSettled)
		end
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
-- "Show Dots Instead of Names": a dot per party member, like the totem bar's:
-- class colour with the buff, red without, or ("Only Show Who's Missing") only
-- the ones without it. The range pass colours / shows each from UnitHasBuff.
-- The same options as the totem bar's dots: position, outline, size, placed by
-- the totem bar's own PartyDotAnchor around the cell's icon.
local function CoverageDots() return CoverageOpts().dots and true or false end
local function CoverageDotSize() return CoverageOpts().dotSize or 5 end
local function CoverageDotPos() return CoverageOpts().dotPosition or "corners" end
-- room the panel keeps for dots outside the cell: top, bottom, left, right
-- (they hang outside it, like the names, so the cell stays just the icon)
local function DotPads()
	if not CoverageDots() then return 0, 0, 0, 0 end
	local pos, pad = CoverageDotPos(), CoverageDotSize() + 3
	return (pos == "above") and pad or 0, (pos == "below") and pad or 0,
		(pos == "left") and pad or 0, (pos == "right") and pad or 0
end
local function PlaceDot(btn, row, i)
	local size, pos = CoverageDotSize(), CoverageDotPos()
	-- corners sit on the icon; rows / columns outside the cell's edge
	local host = (pos == "corners") and btn.icon or btn
	local point, relPoint, x, y = SP:PartyDotAnchor(i, host, pos, size)
	row:SetSize(size, size)
	row:ClearAllPoints()
	row:SetPoint(point, host, relPoint, x, y)
	row.dotOutline:SetSize(size + 2, size + 2)
	local tex = SP:DotTexture()   -- Dot Shape
	if row.dot.spDotTex ~= tex then row.dot:SetTexture(tex); row.dotOutline:SetTexture(tex); row.dot.spDotTex = tex end
	if SP.DotGem then SP:DotGem(row.dot) end   -- Gem Dot Finish
end
local function RowMode(row, dots)
	row.text:SetShown(not dots)
	row.dot:SetShown(dots)
	row.dotOutline:SetShown(dots and CoverageOpts().dotOutline ~= false)
end
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
	settingsBtn:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Totem Coverage settings", 1, 1, 1)
		GameTooltip:Show()
	end)
	settingsBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)
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
			GameTooltip:AddLine("Right-click for settings", 0.7, 0.7, 0.7)
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
		-- "Show Totem Time Left": the totem's time left in place of "N OUT"
		local timerText = btn:CreateFontString(nil, "OVERLAY")
		SP:SetSPFont(timerText, "timers", 12, "OUTLINE")
		timerText:SetPoint("CENTER", icon, "CENTER", 0, 0)
		timerText:SetTextColor(1, 1, 1)
		timerText:Hide()
		btn.timerText = timerText
		btn.rows = {}
		for i = 1, 4 do
			-- a name-tag pill under the icon: the dark tag is what the engine's
			-- strip can match to cover the red name
			local row = CreateFrame("Frame", nil, btn)
			row.spNoHoverWalk = true   -- holds the engine's name display: the settings-cog hover walk stays out
			local t = row:CreateFontString(nil, "OVERLAY")
			SP:SetSPFont(t, "labels", 9, "OUTLINE")
			t:SetPoint("LEFT", row, "LEFT", 2, 0)
			t:SetPoint("RIGHT", row, "RIGHT", -2, 0)
			t:SetJustifyH("CENTER")
			t:SetWordWrap(false)
			t:SetTextColor(1, 0.25, 0.25)
			row.text = t
			-- the dot form of the same row (Show Dots Instead of Names)
			local o = row:CreateTexture(nil, "ARTWORK", nil, -1)
			o:SetTexture(DOT_TEXTURE)
			o:SetVertexColor(0, 0, 0, 0.9)
			o:SetPoint("CENTER", row, "CENTER", 0, 0)   -- a ring 1px past the dot, like the totem bar's
			o:SetSize(7, 7)
			o:Hide()
			local d = row:CreateTexture(nil, "ARTWORK")
			d:SetTexture(DOT_TEXTURE)
			d:SetVertexColor(1, 0.25, 0.25)
			d:SetAllPoints(row)
			d:Hide()
			row.dot, row.dotOutline = d, o
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

-- "Show Dots Instead of Names": the class-coloured dot drawn by the game whenever that player carries
-- the totem's buff (in combat and in instances too, where buffs can't be read and the old answer was a
-- range check from the shaman, not the totem), over our red one underneath: as the totem bar's dots
local function BuildCoverageDot(element, partyIndex, btn, row, r, g, b)
	local size, outline = CoverageDotSize(), CoverageOpts().dotOutline ~= false
	return (NewPartyAuraSlot(row, SP.partyUnitStrings[partyIndex], "cover", CoverageBuffMap(element), function(button)
		button:ClearAllPoints()
		button:SetAllPoints(row)
		PaintDotButton(button, size, outline, r, g, b)
	end, 5))
end

local function BuildCoverageRow(element, partyIndex, btn, row, name, r, g, b)
	local fontSize = CoverageFont()
	return (NewPartyAuraSlot(row, SP.partyUnitStrings[partyIndex], "cover", CoverageBuffMap(element), function(button)
		button:ClearAllPoints()
		button:SetAllPoints(row)
		if button.SetMouseClickEnabled then pcall(button.SetMouseClickEnabled, button, false) end
		if button.SetMouseMotionEnabled then pcall(button.SetMouseMotionEnabled, button, false) end
		-- the covered look: the same name, same font and place, in class
		-- colour - identical glyphs, so the red one underneath disappears
		-- under it. No tag, no strip: names float, frame or no frame.
		local t = button:CreateFontString(nil, "OVERLAY")
		SP:SetSPFont(t, "labels", fontSize, "OUTLINE")
		SP:SPFontGameOwned(t)   -- (on the game's button: a font change waits out fights and hidden auras)
		t:SetPoint("LEFT", button, "LEFT", 2, 0)
		t:SetPoint("RIGHT", button, "RIGHT", -2, 0)
		t:SetJustifyH("CENTER")
		t:SetWordWrap(false)
		t:SetTextColor(r, g, b)
		t:SetText(name)
	end, 5))
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
		-- the icon is the 3rd return: "totem and GetSpellInfo(totem)" kept only the first one
		-- (an and-expression is one value), so every new cell started without its icon
		local tex = totem and select(3, GetSpellInfo(totem))
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
		local dots, dotSize = CoverageDots(), CoverageDotSize()
		local key = name .. "|" .. tostring(class) .. "|" .. fontSize .. "|" .. CellIconSize(btn.cellKey) .. "|" .. CoverageWatchSig(element)
			.. "|" .. (dots and ("d" .. dotSize .. CoverageDotPos() .. tostring(CoverageOpts().dotOutline ~= false) .. tostring(self.opt.dotShape)
				.. tostring(self.ThemeClassColorSet and self:ThemeClassColorSet("mod.coverage-dots-class")) .. tostring(self.opt.dotGem)
				.. tostring(CoverageOpts().dotsMissingOnly)) or "n")
		local slot = self.coverageRows[rowsKey][i]
		local row = btn.rows[i]
		if not slot or slot.key ~= key then
			if slot and slot.container then
				pcall(slot.container.SetEnabled, slot.container, false)
				slot.container:Hide()
			end
			SP:SetSPFont(row.text, "labels", fontSize, "OUTLINE")
			row.text:SetText(name)
			RowMode(row, dots)
			if dots then
				PlaceDot(btn, row, i)
				local dc = class and RAID_CLASS_COLORS[class]
				if dc then dc = ThemeClassColor("mod.coverage-dots-class", class, dc) end
				row.cr, row.cg, row.cb = 0, 1, 0   -- no class known: green, as on the totem bar
				if dc then row.cr, row.cg, row.cb = dc.r, dc.g, dc.b end
				row.dot:SetVertexColor(row.cr, row.cg, row.cb)
				row.dotRed = false
			else
				-- as wide as the cell, wider for a long name (never cut): flush under the icon
				row:SetSize(math.max(btn:GetWidth(), math.ceil(row.text:GetStringWidth()) + 10), rowH)
				row:ClearAllPoints()
				row:SetPoint("TOP", btn, "BOTTOM", 0, -(i - 1) * rowH)
			end
			local cr, cg, cb = 0.4, 1, 0.4
			local color = class and RAID_CLASS_COLORS[class]
			if color then cr, cg, cb = color.r, color.g, color.b end
			-- names: the game draws the covered name; dots: the game draws the class-coloured dot over our red
			-- one ("Only Show Who's Missing" keeps the range pass: the game can only add a look, not take ours away)
			local container = nil
			if exists and not dots then
				container = BuildCoverageRow(element, i, btn, row, name, cr, cg, cb)
			elseif exists and not CoverageOpts().dotsMissingOnly then
				container = BuildCoverageDot(element, i, btn, row, row.cr or cr, row.cg or cg, row.cb or cb)
			end
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
	-- switched off: no rows are built (the switch back on rebuilds) and nothing shows
	if self:IsOff() then
		if self.coverageFrame and not self.coverageDemoActive then HideAllCells(self.coverageFrame) end
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
	SP:SetSPFont(btn.timerText, "timers", math.max(9, math.floor(iconSize / 3)), "OUTLINE")
end

-- the time left on a cell's icon (nil: none); text only when the second changes
local function SetCellTimer(btn, left)
	local str = left and SP.FormatDuration and SP.FormatDuration(left) or nil
	if btn.timerStr == str then return end
	btn.timerStr = str
	if str then btn.timerText:SetText(str) end
	btn.timerText:SetShown(str ~= nil)
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
			-- never placed: spread in a row above the character, in the order they first appear.
			-- A cell keeps its place in that row, so its Reset puts it back on the same spot
			if not btn.freeSlot then
				freeOrder = freeOrder + 1
				btn.freeSlot = freeOrder
			end
			btn:ClearAllPoints()
			btn:SetPoint("CENTER", UIParent, "CENTER", (btn.freeSlot - 3) * 70, 120)
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
	local t, b, l, r = DotPads()   -- dots outside the cell hang past it, like the names
	local cellW = iconSize + 6
	local cellH = iconSize + 6
	local nameSpace = 0   -- the name tags stack flush under each cell
	if count > 0 and not CoverageDots() then nameSpace = count * rowH + 2 end
	local padding, n = 6, #shown
	local slotW, slotH = cellW + l + r, cellH + t + b + nameSpace
	local width, height
	if co.vertical then
		width = slotW + 24
		height = (slotH * n) + (padding * (n - 1)) + 28
	else
		width = (slotW * n) + (padding * (n - 1)) + 24
		height = slotH + 26
	end
	frame:SetSize(math.max(80, width), height)
	for idx, btn in ipairs(shown) do
		SizeCell(btn, iconSize)
		btn:ClearAllPoints()
		if co.vertical then
			btn:SetPoint("TOPLEFT", frame, "TOPLEFT", 12 + l, -20 - t - (idx - 1) * (slotH + padding))
		else
			local cellsW = (slotW * n) + (padding * (n - 1))
			btn:SetPoint("TOPLEFT", frame, "TOPLEFT", (frame:GetWidth() - cellsW) / 2 + l + (idx - 1) * (slotW + padding), -20 - t)
		end
	end
end

local function PaintCoverageCell(btn, state, missing)
	local co = CoverageOpts()
	local timer = co.showTimer and true or false   -- the time left takes the "N OUT" spot
	local plain = co.plainIcon and true or false   -- no tint, no coloured outline: the icon as it is
	if btn.state == state and btn.missing == missing and btn.timerMode == timer and btn.plainMode == plain then return end
	btn.state, btn.missing, btn.timerMode, btn.plainMode = state, missing, timer, plain
	if state == "covered" then
		btn:SetBackdropBorderColor(0, 1, 0, 1)
		btn.rangeOverlay:Hide()
		btn.statusText:Hide()
	elseif state == "missing" then
		btn:SetBackdropBorderColor(0.8, 0, 0, 1)
		btn.rangeOverlay:Show()
		btn.statusText:SetText(missing == 1 and "1 OUT" or (missing .. " OUT"))
		btn.statusText:SetShown(not timer)
	else   -- "combat": the names carry the answer
		btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
		btn.rangeOverlay:Hide()
		btn.statusText:Hide()
	end
	if plain then
		local b = SP.PANEL_BORDER
		btn:SetBackdropBorderColor(b[1], b[2], b[3], b[4])
		btn.rangeOverlay:Hide()
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
	if self:IsOff() then HideAllCells(frame) return end   -- ShamanPower switched off
	local partyUnits, count = self:GetCachedPartyUnits()
	if count == 0 then HideAllCells(frame) return end
	local shown, mask = {}, 0
	for element = 1, 4 do
		local haveTotem, _, tStart, tDur, icon = self:GetElementTotemInfo(element)
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
			-- the totem bar's own time left (GetElementTotemInfo, readable in combat too)
			SetCellTimer(btn, co.showTimer and tDur and tDur > 0 and (tStart + tDur - GetTime()) or nil)
			if CoverageDots() then
				-- the totem bar dots' answer (UnitHasBuff; in combat, the distance model):
				-- class colour with the buff, red without, or only the ones without it
				local missingOnly = CoverageOpts().dotsMissingOnly
				local slots = self.coverageRows[co.freeCells and ("t" .. tostring(btn.cellKey)) or element]
				for i = 1, 4 do
					local unit, row = self.partyUnitStrings[i], btn.rows[i]
					local exists = UnitExists(unit)
					local slot = slots and slots[i]
					if slot and slot.container then
						-- the game draws the class-coloured dot over this one while that player has the
						-- buff; never for a member plainly far away (their buffs can come without whose)
						local far = exists and self:PartyUnitFarAway(unit) or false
						-- (by alpha and the container's own on / off: never protected, so the cache can never claim a
						-- change the game refused; a far member's container does no work)
						if slot.far ~= far then
							slot.far = far
							pcall(slot.container.SetEnabled, slot.container, not far)
							if not far then pcall(slot.container.UpdateAllAuras, slot.container) end
							slot.container:SetAlpha(far and 0 or 1)
						end
						if not row.dotRed then row.dotRed = true; PaintMissingCov(row.dot) end
						row:SetShown(exists)
					else
						local has = exists and self:UnitHasBuff(unit, buffName, element)
						local red = not has and not missingOnly
						if row.dotRed ~= red then
							row.dotRed = red
							if red then PaintMissingCov(row.dot) else row.dot:SetVertexColor(row.cr or 0, row.cg or 1, row.cb or 0) end
						end
						row:SetShown(exists and not (missingOnly and has))
					end
				end
			else
				-- names: the game draws a covered member's name; never one plainly far away
				local slots = self.coverageRows[co.freeCells and ("t" .. tostring(btn.cellKey)) or element]
				for i = 1, 4 do
					local slot = slots and slots[i]
					if slot and slot.container then
						local unit = self.partyUnitStrings[i]
						local far = UnitExists(unit) and self:PartyUnitFarAway(unit) or false
						if slot.far ~= far then
							slot.far = far
							pcall(slot.container.SetEnabled, slot.container, not far)
							if not far then pcall(slot.container.UpdateAllAuras, slot.container) end
							slot.container:SetAlpha(far and 0 or 1)
						end
					end
				end
			end
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

-- Every spot back to where it starts (Unlock UI's Reset All): the panel's and each
-- totem's own. Positions only, as its question says: a totem's own size stays.
function SP:ResetCoveragePositions()
	local co = CoverageOpts()
	co.position = nil
	for _, c in pairs(co.cells or {}) do
		if type(c) == "table" then c.position = nil end
	end
	local frame = self.coverageFrame
	if frame then
		frame:ClearAllPoints()
		frame:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
		for element = 1, 4 do frame.buttons[element].freePlaced = nil end
		for _, btn in pairs(frame.totemCells) do btn.freePlaced, btn.freeSlot = nil, nil end
		freeOrder = 0   -- (all of them start the row again)
	end
	self:UpdateCoverageLayout()
end

-- One box back on its default spot (Unlock UI: that box's Reset). A watched totem's own
-- box (free placement): that one only, on its own place in the starting row. The panel:
-- its spot only; the totems' own spots (free placement) and sizes stay.
function SP:ResetCoverageCellPosition(btn)
	local co = CoverageOpts()
	if co.freeCells and btn and btn.cellKey then
		CellOpts(btn.cellKey).position = nil
		btn.freePlaced = nil
	else
		co.position = nil
		local frame = self.coverageFrame
		if frame then
			frame:ClearAllPoints()
			frame:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
		end
	end
	self:UpdateCoverageLayout()
end

-- A profile switch: free cells go to the new profile's spots (they kept the old one's)
if SP.OnProfileChanged then
	hooksecurefunc(SP, "OnProfileChanged", function()
		local frame = SP.coverageFrame
		if not frame then return end
		for _, btn in pairs(frame.totemCells) do btn.freePlaced = nil end
		SP:UpdateCoverageLayout()
	end)
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
		ThemeCoveragePanel(frame)
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
	  storyKept = "The Warrior is back in range: everyone has Earth's buff now.",
	  cells = { [1] = { true, true, true, true }, [3] = { true, true, false, false } } },
	{ story = "The Priest is back too - only the Hunter is still missing Mana Spring.",
	  cells = { [1] = { true, true, true, true }, [3] = { true, true, true, false } } },
	{ story = "Everyone covered: nothing to show.", storyKept = "Everyone is covered.",
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
			-- "Hide a Totem Once Everyone Is in Range" off: covered cells stay, so the line says so
			self.coverageDemoStatus = (co.hideWhenCovered == false and beat.storyKept) or beat.story
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
					local dots = CoverageDots()
					for i = 1, 4 do
						local row = btn.rows[i]
						SP:SetSPFont(row.text, "labels", fontSize, "OUTLINE")
						row.text:SetText(COVERAGE_DEMO_NAMES[i])
						local c = COVERAGE_DEMO_COLORS[i]
						if has[i] then
							row.text:SetTextColor(c[1], c[2], c[3])
						else
							row.text:SetTextColor(1, 0.25, 0.25)
							missing = missing + 1
						end
						-- dots: class colour with the buff, red without, or only the ones without it
						local missingOnly = co.dotsMissingOnly
						if has[i] or missingOnly then row.dot:SetVertexColor(c[1], c[2], c[3]) else PaintMissingCov(row.dot) end
						row.dotRed = nil   -- the live pass paints its own afterwards
						RowMode(row, dots)
						if dots then
							PlaceDot(btn, row, i)
							row:SetShown(not (missingOnly and has[i]))
						else
							row:SetSize(math.max(btn:GetWidth(), math.ceil(row.text:GetStringWidth()) + 10), rowH)
							row:ClearAllPoints()
							row:SetPoint("TOP", btn, "BOTTOM", 0, -(i - 1) * rowH)
							row:Show()
						end
					end
					btn.state = nil
					PaintCoverageCell(btn, missing == 0 and "covered" or "missing", missing)
					SetCellTimer(btn, co.showTimer and (40 + btn.element * 17) or nil)   -- a sample time left
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
				if row then row.text:SetText(""); row.text:SetTextColor(1, 0.25, 0.25); row.dot:SetVertexColor(1, 0.25, 0.25) end
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

-- ============================================================================
-- Party Strip (Party Buff Tracker > Party Strip)
-- ============================================================================
-- One marker per party spot (party1-4, always in that order) for each totem buff
-- the player picks (the tab's Totems row), on screen whether or not that totem is
-- down. A Discord request: "a standalone, draggable party-dots frame, e.g. only for
-- Windfury, that stays useful even when no totem is down"; the owner then asked for
-- several totems in one strip, one line each ("have it all one thing"), the totem's
-- icon always to the LEFT of its line, and Break Up Totem List (each totem a strip
-- of its own). Totem Coverage shows only while your totem is down, so this is a
-- frame of its own, built from Coverage's parts:
--  * WoW: Forever: each spot's "has it" dot is the game's own (NewPartyAuraSlot:
--    your buff only, every rank) over our "missing" mark, one per member and
--    totem. Nothing is read, so it holds in fights and in instances. A member
--    plainly far away gets none (PartyUnitFarAway: the game draws a dot for any
--    matching buff it is handed).
--  * TBC Anniversary: buffs are read (yours only; once per member per aura change, for every line). Windfury Totem is a
--    weapon buff there: each member's own report (WFBUFF, or the Windfury
--    WeakAura) says it, and none (or none for 10 s) is "?", never "missing". A
--    report never says whose Windfury it is: your own totem's spot decides, or
--    being the party's only shaman; else "?" (ReportOwner).
-- The marks differ by shape, not only color: a filled dot in the member's class
-- color (has it), WoW's red circle with a slash (missing), WoW's gray "?" (can't
-- tell), a gray dash (nobody in that spot). Nothing ticks: the roster settle
-- above, the core's UNIT_AURA (one pass per member covers every line), totem
-- changes (InvalidateTotemInfo), reports (SetWindfuryReport, one expiry timer per
-- report) and a newly learned totem (SPELLS_CHANGED) wake it. The strips hold the
-- game's containers, so a fight changes them by alpha and SetEnabled only: their
-- lines, layout, size, place and picks wait for the fight to end. Click-through:
-- Unlock UI (or the tab's Move button) moves them. Settings: SP.opt.partyStrip.
do
	local SPOT_FRAME, SPOT_LINE, SPOT_MARKS = "mod.partystrip-frame", "mod.partystrip-line", "mod.partystrip-marks"
	local SPOT_CLASS = "mod.partystrip-class"
	local RING_TEX = "Interface\\AddOns\\ShamanPower\\Media\\Textures\\Ring_40px"
	local SLASH_TEX = "Interface\\AddOns\\ShamanPower\\textures\\cue_slash"
	-- sizes in the strip's own units at Size 100% (the mockup's numbers, A05)
	local MARK, PAD, GAP, GAP_NAMES, ICON, ICON_GAP, NAME_PX, NAME_GAP, ROW_GAP = 12, 5, 5, 9, 16, 6, 11, 4, 3
	local LINE = 2                       -- the element line over the top border
	-- several totems in one strip: In a Row, the lines' gap; In a Column, the columns' gap
	local LINE_GAP, COL_GAP = 3, 9
	-- Break Up Totem List: a strip with no spot of its own sits this far under the one
	-- before it (UIParent units: room for its Unlock UI box and that box's Reset tab)
	local STACK_GAP = 28
	local DEFAULT_BUFF = "4:1"           -- Windfury Totem (the request)
	local DEFAULT_X, DEFAULT_Y = -380, -60   -- left of the character, clear of both bars' and the reminders' first spots
	local REPORT_TTL = 10                -- a Windfury report counts this long (SPRange's own rule)
	local BACKING = { 0.055, 0.063, 0.078, 0.85 }   -- the dark disc under "missing" and "?" (windowBg)
	local PARTY = SP.partyUnitStrings
	local PARTY_INDEX = { party1 = 1, party2 = 2, party3 = 3, party4 = 4 }
	local EMPTY = {}
	local pending = false                -- a rebuild owed to the end of a fight
	-- the strips: [1] the Party Strip (ShamanPowerPartyStrip); with Break Up Totem List
	-- [2..] the other totems' own strips (made when first needed, kept)
	local frames = {}
	SP.partyStripFrames = frames

	local function Opts()
		local opt = SP.opt
		if not opt then return EMPTY end
		local o = opt.partyStrip
		if type(o) ~= "table" then
			SP:EnsureProfileTable("partyStrip")
			o = opt.partyStrip
		end
		return type(o) == "table" and o or EMPTY
	end
	local function On() return Opts().enabled == true end
	local function Scale()
		local v = tonumber(Opts().scale)
		if not v or v < 0.5 or v > 3 then return 1 end
		return v
	end
	local function BgOpacity()
		local v = tonumber(Opts().bgOpacity)
		if not v then return 0.8 end
		if v < 0 then return 0 elseif v > 1 then return 1 end
		return v
	end
	-- Break Up Totem List: one totem's own strip settings (opt.partyStrip.strips[key]:
	-- its spot and its Size from Unlock UI's wheel); make: create them
	local function StripRec(key, make)
		local o = Opts()
		local t = o.strips
		if type(t) ~= "table" then
			if not make or o == EMPTY then return nil end
			t = {}
			o.strips = t
		end
		local r = t[key]
		if type(r) ~= "table" then
			if not make then return nil end
			r = {}
			t[key] = r
		end
		return r
	end
	-- a strip's Size: its own (a broken-up strip sized in Unlock UI), else the tab's
	local function ScaleOf(f)
		local r = f.stripKey and StripRec(f.stripKey)
		local v = r and tonumber(r.scale)
		if v and v >= 0.5 and v <= 3 then return v end
		return Scale()
	end

	-- -------------------------------------------------------------------------
	-- What it can watch: every totem buff this client has (Totem Coverage's own
	-- list), keyed "element:index" so one profile reads the same on both games.
	-- TBC Anniversary adds Windfury Totem, watched through the party's reports.
	-- -------------------------------------------------------------------------
	local catalog, catalogByKey
	local function Catalog()
		if catalog then return catalog end
		local list, byKey = {}, {}
		for element = 1, 4 do
			local buffs = SP.TotemBuffSpellIDs[element] or EMPTY
			local idxs = {}
			for idx in pairs(buffs) do idxs[#idxs + 1] = idx end
			if element == 4 and not SPCompat.FOREVER and not buffs[1] then idxs[#idxs + 1] = 1 end
			table.sort(idxs)
			for _, idx in ipairs(idxs) do
				local totem = SP.GetTotemSpell and SP:GetTotemSpell(element, idx)
				if totem and SPCompat.SpellExists and SPCompat.SpellExists(totem) then
					local e = { key = element .. ":" .. idx, element = element, index = idx, totem = totem }
					local base = buffs[idx]
					if base then
						local ids = {}
						for _, id in ipairs(SP.TotemBuffRanks[base] or { base }) do ids[id] = true end
						e.ids = ids
						e.buffName = SP.TotemBuffNames[element] and SP.TotemBuffNames[element][idx]
					else
						e.reports = true   -- Windfury Totem on TBC Anniversary
					end
					list[#list + 1] = e
					byKey[e.key] = e
				end
			end
		end
		if #list == 0 then return list end   -- spells not known yet (too early): ask again later
		catalog, catalogByKey = list, byKey
		return catalog
	end
	-- the one buff the strip watched before it could watch several (its old Buff to Watch)
	local function LegacyKey()
		local list = Catalog()
		if not catalogByKey then return nil end
		local e = catalogByKey[Opts().buff or DEFAULT_BUFF] or catalogByKey[DEFAULT_BUFF] or list[1]
		return e and e.key or nil
	end
	-- picked in the Totems row (opt.partyStrip.totems); nothing saved there yet: that one buff
	local function Picked(key)
		local t = Opts().totems
		if type(t) == "table" then return t[key] == true end
		return key ~= nil and key == LegacyKey()
	end
	local function Learned(e)
		return SP.KnowsTotem and SP:KnowsTotem(e.element, e.index) and true or false
	end
	-- the totems the strip shows: picked and learned, in the Totems row's order (the elements')
	local function Picks(out)
		wipe(out)
		for _, e in ipairs(Catalog()) do
			if Picked(e.key) and Learned(e) then out[#out + 1] = e end
		end
		return out
	end
	local function BreakUp() return Opts().breakUp == true end
	local function TotemName(e)
		local name = GetSpellInfo(e.totem)
		if issecretvalue(name) or type(name) ~= "string" or name == "" then
			name = SP.GetTotemName and SP:GetTotemName(e.element, e.index) or nil
		end
		if type(name) ~= "string" or name == "" then name = e.buffName or e.key end
		return name
	end

	-- Totems row (ShamanPower_Config StripTotems): the list, picks, names
	function SP:PartyStripTotems() return Catalog() end
	function SP:PartyStripPicked(key) return Picked(key) end
	function SP:PartyStripTotemName(e) return TotemName(e) end
	function SP:PartyStripTotemLearned(e) return Learned(e) end
	function SP:PartyStripSetPicked(key, on)
		local o = Opts()
		Catalog()
		if o == EMPTY or not (catalogByKey and catalogByKey[key]) then return end
		local t = o.totems
		if type(t) ~= "table" then   -- the first pick: the old Buff to Watch comes along
			t = {}
			local legacy = LegacyKey()
			if legacy then t[legacy] = true end
			o.totems = t
		end
		t[key] = on and true or nil
		self:PartyStripSettingChanged("totems")
	end
	-- how many totems the strip shows (picked and learned), and how many are picked
	function SP:PartyStripCounts()
		local shown, picked = 0, 0
		for _, e in ipairs(Catalog()) do
			if Picked(e.key) then
				picked = picked + 1
				if Learned(e) then shown = shown + 1 end
			end
		end
		return shown, picked
	end
	-- the old Buff to Watch list: key -> the buff's own name (as Coverage's Totems to
	-- Watch list), and their order (Earth, Fire, Water, Air)
	function SP:PartyStripBuffValues()
		local v, order = {}, {}
		for _, e in ipairs(Catalog()) do
			local base = self.TotemBuffSpellIDs[e.element] and self.TotemBuffSpellIDs[e.element][e.index]
			local label = GetSpellInfo(base or e.totem)
			if issecretvalue(label) or type(label) ~= "string" then
				label = self.GetTotemName and self:GetTotemName(e.element, e.index) or e.key
			end
			v[e.key] = label
			order[#order + 1] = e.key
		end
		return v, order
	end
	-- the first totem the strip shows (the one it watched before it could watch several)
	function SP:PartyStripBuff()
		for _, e in ipairs(Catalog()) do
			if Picked(e.key) and Learned(e) then return e.key end
		end
		return LegacyKey() or DEFAULT_BUFF
	end
	-- Windfury through the party's reports (TBC Anniversary) is one of the totems shown
	function SP:PartyStripWatchesReports()
		for _, e in ipairs(Catalog()) do
			if e.reports and Picked(e.key) and Learned(e) then return true end
		end
		return false
	end

	-- -------------------------------------------------------------------------
	-- Colors: WoW's own, or the theme's (General > Themes, Party Buff Tracker)
	-- -------------------------------------------------------------------------
	local RED, GRAY = { 1, 0.125, 0.125 }, { 0.5, 0.5, 0.5 }
	local function WoWColor(name, t, r, g, b)
		local c = _G[name]
		if type(c) == "table" and type(c.r) == "number" then r, g, b = c.r, c.g, c.b end
		t[1], t[2], t[3] = r, g, b
	end
	local function ResolveColors()
		local r, g, b = ThemeRGB(SPOT_MARKS, "missing")
		if r then RED[1], RED[2], RED[3] = r, g, b else WoWColor("RED_FONT_COLOR", RED, 1, 0.125, 0.125) end
		r, g, b = ThemeRGB(SPOT_MARKS, "unknown")
		if r then GRAY[1], GRAY[2], GRAY[3] = r, g, b else WoWColor("GRAY_FONT_COLOR", GRAY, 0.5, 0.5, 0.5) end
	end
	local function UnitClassRGB(unit)
		local _, class = UnitClass(unit)
		if issecretvalue(class) then return 0, 1, 0, nil end   -- (green, as below)
		local color = class and RAID_CLASS_COLORS[class]
		if color then color = ThemeClassColor(SPOT_CLASS, class, color) end
		if color then return color.r, color.g, color.b, class end
		return 0, 1, 0, class   -- no class known: green, as the totem bar's dots
	end
	local function SafeGUID(unit)
		local ok, g = pcall(UnitGUID, unit)
		if not ok or issecretvalue(g) then return nil end
		return g
	end
	local function SafeExists(unit)
		local e = UnitExists(unit)
		if issecretvalue(e) then return false end
		return e and true or false
	end

	-- -------------------------------------------------------------------------
	-- Spots: a strip's place, size and stacking (out of combat only)
	-- -------------------------------------------------------------------------
	local function SavePosition(f)
		local rec = SP:SavePositionRecord(f)
		if f.stripKey then
			StripRec(f.stripKey, true).position = rec   -- (a broken-up strip: its own spot)
		else
			Opts().position = rec
		end
	end
	local function AnchorXY(name, W, H)   -- (ShamanPower.lua's: one of UIParent's nine points)
		local x = (strfind(name, "LEFT") and 0) or (strfind(name, "RIGHT") and W) or W / 2
		local y = (strfind(name, "TOP") and H) or (strfind(name, "BOTTOM") and 0) or H / 2
		return x, y
	end
	-- a strip's middle in UIParent units, worked out from its one point on UIParent
	-- (straight after a SetPoint the game may still report the old spot)
	local function CenterOf(f)
		local s = f:GetScale() or 1
		if f:GetNumPoints() == 1 then
			local point, rel, relPoint, x, y = f:GetPoint(1)
			if point == "CENTER" and rel == UIParent then
				local ax, ay = AnchorXY(relPoint or point, UIParent:GetWidth(), UIParent:GetHeight())
				return ax + (x or 0) * s, ay + (y or 0) * s
			end
		end
		local cx, cy = f:GetCenter()
		if not cx then return nil end
		return cx * s, cy * s
	end
	-- Break Up Totem List: a strip with no spot of its own goes under the one before it,
	-- left edges in line (again at every layout: a strip that grows never covers the next).
	-- The gap leaves room for Unlock UI: each strip's box is at least 24 tall round the
	-- strip's middle, and the lower box's Reset tab stands 23 above that box (UIParent units)
	local function StackUnder(f, prev)
		if prev:GetParent() ~= UIParent then return false end
		local px, py = CenterOf(prev)
		if not px then return false end
		local ps, s = prev:GetScale() or 1, f:GetScale() or 1
		local ph, h = prev:GetHeight() * ps, f:GetHeight() * s
		local left = px - prev:GetWidth() * ps / 2
		local bottom = py - ph / 2
		local gap = math.max(STACK_GAP, 25 + math.max(0, (24 - ph) / 2) + math.max(0, (24 - h) / 2))
		local cx = left + f:GetWidth() * s / 2
		local cy = bottom - gap - h / 2
		f:ClearAllPoints()
		f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx / s, cy / s)
		return true
	end
	-- size, then its spot (out of combat, and never while a preview has borrowed it):
	-- its own spot (a broken-up strip moved in Unlock UI), else under the strip before
	-- it, else the Party Strip's spot
	local function PlaceStrip(f, prev)
		if InCombatLockdown() or f:GetParent() ~= UIParent then return false end
		f:SetScale(ScaleOf(f))
		local own = f.stripKey and StripRec(f.stripKey)
		if own and SP:ApplyPositionRecord(f, own.position) then return true end
		if prev and StackUnder(f, prev) then return true end
		if not SP:ApplyPositionRecord(f, Opts().position) then
			f:ClearAllPoints()
			f:SetPoint("CENTER", UIParent, "CENTER", DEFAULT_X, DEFAULT_Y)
		end
		return true
	end
	-- every strip in use, in order (the first on its spot, the rest under it unless moved)
	local function PlaceAll()
		local prev
		for _, f in ipairs(frames) do
			if f.used then
				PlaceStrip(f, prev)
				prev = f
			end
		end
	end

	-- -------------------------------------------------------------------------
	-- The frames: a HUD panel (SP:ApplyPanelBackdrop: the Frame Edges look too),
	-- the element line, and one line per totem: its icon and four spots
	-- -------------------------------------------------------------------------
	local function NewSpot(f, i)
		local c = CreateFrame("Frame", nil, f)
		c:SetSize(MARK, MARK)
		local m = CreateFrame("Frame", nil, c)   -- the mark's own square: the game's container sits on it
		m:SetSize(MARK, MARK)
		m:SetPoint("LEFT", c, "LEFT", 0, 0)
		local back = m:CreateTexture(nil, "ARTWORK", nil, 0)
		back:SetTexture(DOT_TEXTURE)
		back:SetVertexColor(BACKING[1], BACKING[2], BACKING[3], BACKING[4])
		back:SetAllPoints(m)
		local ring = m:CreateTexture(nil, "ARTWORK", nil, 1)
		ring:SetTexture(RING_TEX)
		ring:SetAllPoints(m)
		local slash = m:CreateTexture(nil, "ARTWORK", nil, 2)
		slash:SetTexture(SLASH_TEX)
		slash:SetTexCoord(1, 0, 0, 1)   -- mirrored: the sign's own slash, top left to bottom right
		local inset = MARK * 0.12
		slash:SetPoint("TOPLEFT", m, "TOPLEFT", inset, -inset)
		slash:SetPoint("BOTTOMRIGHT", m, "BOTTOMRIGHT", -inset, inset)
		local q = m:CreateFontString(nil, "OVERLAY")
		SP:SetSPFont(q, "labels", 11, "OUTLINE")
		q:SetPoint("CENTER", m, "CENTER", 0, 0)
		q:SetText("?")
		local dash = m:CreateTexture(nil, "ARTWORK", nil, 1)
		dash:SetColorTexture(1, 1, 1, 1)
		dash:SetSize(MARK * 0.64, 2)
		dash:SetPoint("CENTER", m, "CENTER", 0, 0)
		-- "has it" drawn by us where the game does not draw it (TBC Anniversary, the
		-- previews): the same look as the game's (an opaque rim, the class-colored dot)
		local rim = m:CreateTexture(nil, "OVERLAY", nil, 0)
		rim:SetTexture(DOT_TEXTURE)
		rim:SetVertexColor(0, 0, 0, 1)
		rim:SetPoint("CENTER", m, "CENTER", 0, 0)
		rim:SetSize(MARK + 2, MARK + 2)
		local lit = m:CreateTexture(nil, "OVERLAY", nil, 1)
		lit:SetTexture(DOT_TEXTURE)
		lit:SetAllPoints(m)
		-- the name (Show Names): never cut short, the strip grows to fit it
		local name = c:CreateFontString(nil, "OVERLAY")
		SP:SetSPFont(name, "labels", NAME_PX, "OUTLINE")
		name:SetJustifyH("LEFT")
		name:SetPoint("LEFT", m, "RIGHT", NAME_GAP, 0)
		c.mark, c.back, c.ring, c.slash, c.q, c.dash, c.rim, c.lit, c.name = m, back, ring, slash, q, dash, rim, lit, name
		c.index = i
		return c
	end

	local function PaintSpotColors(c)
		c.ring:SetVertexColor(RED[1], RED[2], RED[3])
		c.slash:SetVertexColor(RED[1], RED[2], RED[3])
		c.q:SetTextColor(GRAY[1], GRAY[2], GRAY[3])
		c.dash:SetVertexColor(GRAY[1], GRAY[2], GRAY[3], 0.6)
	end

	-- our own layer of a spot: "has" (where the game does not draw it), "missing",
	-- "unknown" or "empty". Textures and text only: fine in a fight.
	local function PaintMark(c, state)
		if c.state == state then return end
		c.state = state
		local miss, unknown = state == "missing", state == "unknown"
		c.back:SetShown(miss or unknown)
		c.ring:SetShown(miss)
		c.slash:SetShown(miss)
		c.q:SetShown(unknown)
		c.dash:SetShown(state == "empty")
		c.rim:SetShown(state == "has")
		c.lit:SetShown(state == "has")
	end

	-- the panel's colors at its Background Opacity, and the element line's parts (colors
	-- only: fine in a fight)
	local function PaintPanel(f)
		local a = BgOpacity()
		local bg, edge = SP.PANEL_BG, SP.PANEL_BORDER
		local r, g, b = ThemeRGB(SPOT_FRAME, "bg")
		if not r then r, g, b = bg[1], bg[2], bg[3] end
		f:SetBackdropColor(r, g, b, a)
		r, g, b = ThemeRGB(SPOT_FRAME, "border")
		if not r then r, g, b = edge[1], edge[2], edge[3] end
		f:SetBackdropBorderColor(r, g, b, a * edge[4])
		if f.spEdge then f.spEdge:SetAlpha(a > 0 and 1 or 0) end   -- Frame Edges (a Drop Shadow keeps its own alpha)
		for j = 1, f.segCount do
			local e = f.segElement[j] or 4
			if SP.ThemeElement then
				r, g, b = SP:ThemeElement(SPOT_LINE, e)
			else
				local ec = SP.ElementColors and SP.ElementColors[e]
				r, g, b = ec and ec.r or 1, ec and ec.g or 1, ec and ec.b or 1
			end
			f.segs[j]:SetVertexColor(r, g, b, a)
		end
	end

	local function NewStrip(k)
		local f = CreateFrame("Frame", k == 1 and "ShamanPowerPartyStrip" or ("ShamanPowerPartyStrip" .. k), UIParent, "BackdropTemplate")
		f:SetSize(PAD * 2 + 4 * MARK + 3 * GAP, PAD * 2 + MARK)
		f:SetFrameStrata("MEDIUM")
		f:SetClampedToScreen(true)
		f:SetMovable(true)
		f:EnableMouse(false)   -- clicks go through to the party frames under it
		f:SetScript("OnDragStop", function(frame)
			frame:StopMovingOrSizing()
			SavePosition(frame)
		end)
		f.spMoverLabel = "Party Strip"
		SP:ApplyPanelBackdrop(f)
		local line = f:CreateTexture(nil, "ARTWORK", nil, -8)   -- over the top border, under everything else
		line:SetColorTexture(1, 1, 1, 1)
		line:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
		line:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
		line:SetHeight(LINE)
		f.line = line
		-- the element line in parts: one per element its lines show (one: the whole line)
		f.segs, f.segElement, f.segCount = { line }, { 4 }, 1
		-- the totems' lines it shows now, in order (what a fight updates)
		f.lines = {}
		f.spots, f.slots = EMPTY, EMPTY   -- (the first line's, once it has one)
		f.index = k
		-- Unlock UI's box for a broken-up strip: as wide as its name on one line, so the box
		-- is no taller than the strip (a narrow strip's box wrapped "Party Strip: <totem>"
		-- to three lines and reached into the Reset tab of the strip under it). The one
		-- Party Strip keeps a box the size of the strip, as before.
		f.spMoverSize = function()
			if not f.stripKey or not _G.ShamanPowerDialogFontText then return f end
			local z = f.moverSizer
			if not z then
				z = CreateFrame("Frame", nil, f)   -- (nothing drawn: it only gives the box its size)
				z.text = z:CreateFontString(nil, "OVERLAY")
				z.text:SetFontObject("ShamanPowerDialogFontText")   -- (the box's own label font)
				z.text:Hide()
				f.moverSizer = z
			end
			z.text:SetText(f.spMoverLabel or "")
			local w0 = z.text.GetUnboundedStringWidth and z.text:GetUnboundedStringWidth() or z.text:GetStringWidth()
			local k = UIParent:GetEffectiveScale() / f:GetEffectiveScale()   -- (the box's units into the strip's)
			z:ClearAllPoints()
			z:SetPoint("CENTER", f, "CENTER", 0, 0)
			z:SetSize(math.max(f:GetWidth(), ((tonumber(w0) or 0) + 16) * k), f:GetHeight())
			return z
		end
		f:Hide()
		frames[k] = f
		return f
	end

	-- one totem's line: its icon and a spot per party member, with the game's displays
	-- (WoW: Forever), all on a host frame of its own. ONE per totem, made once and kept,
	-- whichever strip shows it: Break Up Totem List, a pick or a reorder moves the host to
	-- another strip (out of combat), so a totem's displays never pile up per strip.
	-- (lineList: in the order made, a new one last: the theme's flat boxes find them)
	local lineByKey, lineList = {}, {}
	SP.partyStripLines = lineList
	local function LineFor(f, w)
		local line = lineByKey[w.key]
		if line then return line end
		line = { w = w, key = w.key, element = w.element, spots = {}, slots = {}, slotsBuilt = {} }
		local host = CreateFrame("Frame", nil, f)
		host:SetAllPoints(f)
		line.host = host
		local icon = host:CreateTexture(nil, "ARTWORK", nil, 1)
		icon:SetSize(ICON, ICON)
		icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		local iconEdge = host:CreateTexture(nil, "ARTWORK", nil, 0)
		iconEdge:SetColorTexture(0, 0, 0, 1)
		iconEdge:SetPoint("TOPLEFT", icon, "TOPLEFT", -1, 1)
		iconEdge:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1)
		icon:Hide()
		iconEdge:Hide()
		line.icon, line.iconEdge = icon, iconEdge
		for i = 1, 4 do
			local c = NewSpot(host, i)
			PaintSpotColors(c)
			c:Hide()
			line.spots[i] = c
		end
		lineByKey[w.key] = line
		lineList[#lineList + 1] = line
		return line
	end

	function SP:CreatePartyStrip()
		local f = frames[1]
		if f then return f end
		ResolveColors()
		f = NewStrip(1)
		self.partyStrip = f
		PaintPanel(f)
		PlaceStrip(f)
		return f
	end
	-- the k-th strip (Break Up Totem List's: made the first time it is needed)
	local function Strip(k)
		if k == 1 then return SP:CreatePartyStrip() end
		if frames[k] then return frames[k] end
		if not frames[k - 1] then Strip(k - 1) end   -- (the list never has a hole)
		local f = NewStrip(k)
		PaintPanel(f)
		return f
	end

	-- -------------------------------------------------------------------------
	-- Layout: each line's spots in a row or a column, the names (once, by the first
	-- line), the icons (always to the LEFT of their line), the element line and the
	-- frame's size. Out of combat only (the game's containers ride in the frame).
	-- -------------------------------------------------------------------------
	local function IconOf(w)
		local tex
		if w and w.totem and GetSpellInfo then tex = select(3, GetSpellInfo(w.totem)) end
		if not tex and w and SP.GetTotemIcon then tex = SP:GetTotemIcon(w.element, w.index) end
		return tex
	end

	-- the spots the strip has: one per member of your party (party1-4 are always filled
	-- in order), so it grows and shrinks as people join and leave; a preview has four
	local function Members(f)
		if f.demo then return 4 end
		local n = 0
		for i = 1, 4 do if SafeExists(PARTY[i]) then n = i end end
		return n
	end

	local nameW = {}   -- (reused: the first line's names' widths)
	local function Layout(f)
		local o = Opts()
		local names, column = o.showNames == true, o.layout == "column"
		local lines = f.lines
		local L = #lines
		-- several totems in one strip: each line's icon is its label, always shown
		local showIcon = L > 1 or o.showIcon == true
		f.iconsOn = showIcon and L > 0
		local n = Members(f)
		f.members = n
		local first = lines[1]
		for i = 1, 4 do nameW[i] = 0 end
		for k, line in ipairs(lines) do
			for i = 1, 4 do
				local c = line.spots[i]
				c:SetShown(i <= n)
				c.name:SetShown(names and k == 1)
				if names and k == 1 then
					local t = c.name:GetText()
					if t and t ~= "" then nameW[i] = math.ceil(c.name:GetStringWidth()) end
				end
			end
			line.icon:SetShown(showIcon)
			line.iconEdge:SetShown(showIcon)
			line.icon:ClearAllPoints()
		end
		local rowH = names and math.max(MARK, NAME_PX + 2) or MARK
		local w, h
		if column then
			-- members down; each totem a column with its icon to the LEFT of its first
			-- spot (top-aligned); the names once, beside the first totem's spots
			local x = PAD
			for k, line in ipairs(lines) do
				if showIcon then
					line.icon:SetPoint("TOPLEFT", f, "TOPLEFT", x, -PAD)
					x = x + ICON + ICON_GAP
				end
				local widest = 0
				for i = 1, n do
					local c = line.spots[i]
					local cw = MARK + ((k == 1 and names and nameW[i] > 0) and (NAME_GAP + nameW[i]) or 0)
					widest = math.max(widest, cw)
					c:SetSize(cw, rowH)
					c:ClearAllPoints()
					c:SetPoint("TOPLEFT", f, "TOPLEFT", x, -(PAD + (i - 1) * (rowH + ROW_GAP)))
				end
				x = x + widest
				if k < L then x = x + COL_GAP end
			end
			local colH = n > 0 and (n * rowH + (n - 1) * ROW_GAP) or 0
			w = x + PAD
			h = PAD + math.max(colH, showIcon and ICON or 0) + PAD
		else
			-- members across; each totem a line with its icon at the line's left; the
			-- names once, on the first line (the lines below keep their spots under its spots)
			local inner = math.max(MARK, showIcon and ICON or 0, names and (NAME_PX + 2) or 0)
			local x0 = PAD + (showIcon and (ICON + ICON_GAP) or 0)
			local x = x0
			for k, line in ipairs(lines) do
				local y = -(PAD + inner / 2 + (k - 1) * (inner + LINE_GAP))
				if showIcon then line.icon:SetPoint("LEFT", f, "TOPLEFT", PAD, y) end
				x = x0
				for i = 1, n do
					local c = line.spots[i]
					local nw = (names and nameW[i] > 0) and (NAME_GAP + nameW[i]) or 0
					c:SetSize(MARK + (k == 1 and nw or 0), rowH)
					c:ClearAllPoints()
					c:SetPoint("LEFT", f, "TOPLEFT", x, y)
					x = x + MARK + nw
					if i < n then x = x + (names and GAP_NAMES or GAP) end
				end
			end
			if n == 0 and showIcon then x = x - ICON_GAP end
			w = x + PAD
			local lines1 = math.max(L, 1)
			h = inner * lines1 + LINE_GAP * (lines1 - 1) + PAD * 2
		end
		f:SetSize(w, h)
		for _, line in ipairs(lines) do
			local tex = showIcon and IconOf(line.w) or nil
			if tex then line.icon:SetTexture(tex) end
			line.iconDown = nil   -- (UpdateIcon sets its grayed look again)
		end
		-- the element line along the top: one equal part per element its lines show, in order
		local els, count = f.segElement, 0
		for _, line in ipairs(lines) do
			local e, seen = line.element, false
			for j = 1, count do if els[j] == e then seen = true end end
			if not seen then count = count + 1; els[count] = e end
		end
		if count == 0 then count = 1; els[1] = 4 end
		local segs = f.segs
		for j = 1, count do
			local seg = segs[j]
			if not seg then
				seg = f:CreateTexture(nil, "ARTWORK", nil, -8)
				seg:SetColorTexture(1, 1, 1, 1)
				seg:SetHeight(LINE)
				segs[j] = seg
			end
			seg:ClearAllPoints()
			if count == 1 then
				seg:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
				seg:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
			else
				seg:SetPoint("TOPLEFT", f, "TOPLEFT", math.floor((j - 1) * w / count + 0.5), 0)
				seg:SetPoint("TOPRIGHT", f, "TOPLEFT", math.floor(j * w / count + 0.5), 0)
			end
			seg:Show()
		end
		for j = count + 1, #segs do segs[j]:Hide() end
		f.segCount = count
		-- a totem change has to reach it: its icons gray, or Windfury's report spots
		local wake = f.iconsOn
		for _, line in ipairs(lines) do if line.w.reports then wake = true end end
		f.wakeOnTotems = wake
		f.spots, f.slots = first and first.spots or EMPTY, first and first.slots or EMPTY
	end

	-- -------------------------------------------------------------------------
	-- The game's displays (WoW: Forever): one per spot of each line, member or not
	-- (a spot shows only while someone is in it: one who joins in a fight shows
	-- when it ends, with the layout), keyed so only what changed is rebuilt
	-- -------------------------------------------------------------------------
	local function BuildSlot(c, unit, ids, r, g, b)
		local m = c.mark
		return (NewPartyAuraSlot(m, unit, "strip", ids, function(button)
			button:ClearAllPoints()
			button:SetAllPoints(m)
			-- an opaque rim and the plain round dot (never the Dot Shape or Gem Dot
			-- Finish): it must hide the circle and slash under it completely
			PaintDotButton(button, MARK, true, r, g, b, DOT_TEXTURE, 1, true)
		end, 5))
	end
	-- a spot's display for one look (totem, class, Class Colors set). Each spot of each
	-- totem's line keeps the ones it built: a class that comes back (the next group)
	-- takes its old one again, so a long night of groups never piles up displays. Out
	-- of combat (it may Show).
	local function SlotFor(line, i, key, c, unit, ids, r, g, b)
		local kept = line.slotsBuilt[i]
		if not kept then kept = {}; line.slotsBuilt[i] = kept end
		local container = kept[key]
		if container then
			container:Show()   -- (a retired one was hidden)
		else
			container = BuildSlot(c, unit, ids, r, g, b)
			if container then kept[key] = container end
		end
		if container then   -- (lit by UpdateSpot, by alpha and its own on / off)
			pcall(container.SetEnabled, container, false)
			container:SetAlpha(0)
		end
		return container
	end
	-- a line's displays off and hidden (the line sits out; a rebuild, out of combat)
	local function RetireLine(line)
		for i = 1, 4 do
			RetireEngineRecord(line.slots[i])
			line.slots[i] = nil
		end
	end
	-- names, classes and the game's displays for a strip's lines (out of combat)
	local function BuildLines(f, engine, classSet)
		for k, line in ipairs(f.lines) do
			local w = line.w
			local lineEngine = engine and w.ids and true or false
			for i = 1, 4 do
				local unit, c = PARTY[i], line.spots[i]
				local exists = SafeExists(unit)
				local r, g, b, class = UnitClassRGB(unit)
				local name = exists and UnitName(unit) or nil
				if issecretvalue(name) or type(name) ~= "string" then name = nil end
				c.name:SetText(k == 1 and name or "")   -- (the names: once, by the first line)
				c.name:SetTextColor(r, g, b)
				c.lit:SetVertexColor(r, g, b)
				c.guid = exists and SafeGUID(unit) or nil
				PaintSpotColors(c)
				c.state = nil   -- (repainted below)
				local rec = line.slots[i]
				if lineEngine then
					local key = w.key .. "|" .. tostring(class) .. "|" .. tostring(classSet)
					if not (rec and rec.key == key and rec.container) then
						RetireEngineRecord(rec)
						line.slots[i] = { container = SlotFor(line, i, key, c, unit, w.ids, r, g, b), key = key, shown = false }
					end
				elseif rec then
					RetireEngineRecord(rec)
					line.slots[i] = nil
				end
			end
		end
	end
	-- a strip a settings preview made while it was up (so it was not borrowed and is not
	-- given back): home again, out of sight until a rebuild places it (out of combat)
	local function Rehome(f)
		if f:GetParent() == UIParent then return end
		f.spPaneShown = nil
		f:SetParent(UIParent)
		f:SetFrameStrata("MEDIUM")
		f:SetScale(1)
		f:ClearAllPoints()
		f:SetPoint("CENTER", UIParent, "CENTER", DEFAULT_X, DEFAULT_Y)
		f:Hide()
	end
	-- a strip not in use: hidden (out of combat; its lines are elsewhere or sit out)
	local function RetireStrip(f)
		wipe(f.lines)
		f.used = false
		f:Hide()
	end

	-- -------------------------------------------------------------------------
	-- What each spot says, any time (a fight too): our mark, and the game's display on or off
	-- -------------------------------------------------------------------------
	local ArmReport   -- (with the hooks below)
	local UpdateSpot, NoteOwnDrop   -- (this section's own helpers stay in it: the main chunk's locals are counted)
	do
		local function ReportState(unit)
			local name = UnitName(unit)
			if type(name) ~= "string" or issecretvalue(name) then return "unknown" end
			local has
			if SP.GetWindfuryRangeStatus then
				has = SP:GetWindfuryRangeStatus(name)
			else
				local d = SP.WindfuryRangeData and SP.WindfuryRangeData[name]
				if d and GetTime() - d.timestamp <= REPORT_TTL then has = d.hasWindfury end
			end
			if has == true then return "has" elseif has == false then return "missing" end
			return "unknown"
		end

		-- A report says "Windfury", never whose (G4). Your own totem's evidence decides:
		-- where it went down (your spot as its slot filled; the open world gives
		-- positions, instances do not) against where the member is now. Within its
		-- reach the buff is yours to give; plainly out of it, it is not yours, whoever's
		-- it is. Unmeasured or in between, it is yours only when no other shaman is in
		-- your party (a totem reaches its own party only); else "?", never a guess.
		local WF_REACH, WF_OUT = 20, 30      -- yards: Windfury Totem's reach (TBC), and plainly out of it
		local ownDrop = {}                   -- your Windfury: start (its slot's start time), x, y, map
		local function UnitSpot(unit)
			if SP.debugNoPositions or not UnitPosition then return nil end   -- (the core's dev switch: act as in an instance)
			local ok, y, x, _, map = pcall(UnitPosition, unit)
			if not ok or issecretvalue(x) or issecretvalue(y) or type(x) ~= "number" or type(y) ~= "number" then return nil end
			return x, y, map
		end
		-- your totems changed: a Windfury that has just gone down stands where you are now
		NoteOwnDrop = function(w)
			local have, _, start = SP:GetElementTotemInfo(w.element)
			if issecretvalue(have) or issecretvalue(start) or not have or type(start) ~= "number" then
				ownDrop.start = nil
				return
			end
			if ownDrop.start == start then return end
			ownDrop.start = start
			ownDrop.x, ownDrop.y, ownDrop.map = nil, nil, nil
			if GetTime() - start > 1.5 then return end   -- down a while already (the strip came on later): you may have walked off
			ownDrop.x, ownDrop.y, ownDrop.map = UnitSpot("player")
		end
		-- yards from your Windfury to this member; nil when that can't be measured
		local function OwnDropYards(unit, w)
			if not ownDrop.x then return nil end
			local _, _, start = SP:GetElementTotemInfo(w.element)
			if issecretvalue(start) or start ~= ownDrop.start then return nil end   -- (another totem since)
			local x, y, map = UnitSpot(unit)
			if not x or map ~= ownDrop.map then return nil end
			local dx, dy = x - ownDrop.x, y - ownDrop.y
			return math.sqrt(dx * dx + dy * dy)
		end
		local function OtherShamanInParty()
			for i = 1, 4 do
				local unit = PARTY[i]
				if SafeExists(unit) then
					local _, class = UnitClass(unit)
					if not issecretvalue(class) and class == "SHAMAN" then return true end
				end
			end
			return false
		end
		-- a report that says the member has Windfury: yours ("has"), not yours, or "?"
		local function ReportOwner(unit, w)
			local yards = OwnDropYards(unit, w)
			if yards then
				if yards <= WF_REACH then return "has" end
				if yards > WF_OUT then return "missing" end
			end
			if OtherShamanInParty() then return "unknown" end
			return "has"
		end

		-- A member's buffs, read ONCE per aura change for every line (not once per line):
		-- yours only ("PLAYER"), by the buff's name or any rank's ID, as SP:UnitHasBuff reads
		-- them. TBC Anniversary; on WoW: Forever only when the game's display could not be built.
		local scans = {}   -- [party spot] = { unit, gen, at, names = {}, ids = {} }
		local function MemberHasBuff(i, unit, buffName)
			if SP:PartyUnitFarAway(unit) then return false end
			local sc = scans[i]
			if not sc then sc = { names = {}, ids = {} }; scans[i] = sc end
			if not (sc.unit == unit and SP:AuraCacheValid(unit, sc.gen, sc.at)) then
				local names, ids = sc.names, sc.ids
				wipe(names)
				wipe(ids)
				if SPCompat.FOREVER then
					local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
					if get then
						for k = 1, 40 do
							local aura = get(unit, k, "HELPFUL|PLAYER")
							if issecretvalue(aura) or not aura then break end
							local name, id = aura.name, aura.spellId
							if not issecretvalue(name) and name then names[name] = true end
							if not issecretvalue(id) and id then ids[id] = true end
						end
					end
				else
					local read = SPCompat.UnitBuff or UnitBuff   -- (ShamanPower's own reader)
					for k = 1, 32 do
						local name, _, _, _, _, _, _, _, _, id = read(unit, k, "PLAYER")
						if issecretvalue(name) or issecretvalue(id) or not name then break end
						names[name] = true
						if id then ids[id] = true end
					end
				end
				sc.unit, sc.gen, sc.at = unit, SP.auraGen and SP.auraGen[unit] or 0, GetTime()
			end
			if sc.names[buffName] then return true end
			for id in pairs(SP.TotemBuffIDSets[buffName] or EMPTY) do
				if sc.ids[id] then return true end
			end
			return false
		end

		-- one spot of one totem's line
		UpdateSpot = function(line, i, shown)
			local unit, c, rec, w = PARTY[i], line.spots[i], line.slots[i], line.w
			local exists = SafeExists(unit)
			local game = rec and rec.container
			local state
			if not exists then
				state = "empty"
			elseif game then
				state = "missing"   -- the game draws "has it" over this mark
			elseif w and w.reports then
				-- (#2) far away, or no such totem of yours down: nobody has YOUR buff (A05 Q4 / Q8)
				if SP:PartyUnitFarAway(unit) or not (SP.GetActiveTotemIndex and SP:GetActiveTotemIndex(w.element) == w.index) then
					state = "missing"
				else
					state = ReportState(unit)
					if state ~= "unknown" and ArmReport then ArmReport(i, unit) end
					if state == "has" then state = ReportOwner(unit, w) end   -- (G4) whose Windfury it is
				end
			elseif w and w.buffName and not (SPCompat.AurasUnreadable and SPCompat.AurasUnreadable()) then
				state = MemberHasBuff(i, unit, w.buffName) and "has" or "missing"
			else
				state = "unknown"   -- nothing can say right now (the game's display could not be built)
			end
			PaintMark(c, state)
			if game then ShowEngineRecord(rec, shown and exists and not SP:PartyUnitFarAway(unit) or false) end
			-- someone new in this spot during a fight: no name until it ends (the layout waits)
			if exists and InCombatLockdown() and c.guid ~= SafeGUID(unit) and c.name:GetText() ~= "" then
				c.name:SetText("")
				pending = true
			end
		end
	end

	-- a line's icon grayed while you have no such totem down (only when that changes)
	local function UpdateIcon(f, line)
		if not f.iconsOn then return end
		local w = line.w
		local down = (SP.GetActiveTotemIndex and SP:GetActiveTotemIndex(w.element) == w.index) and true or false
		if line.iconDown == down then return end
		line.iconDown = down
		line.icon:SetDesaturated(not down)
		line.icon:SetAlpha(down and 1 or 0.5)
	end

	-- in a group (party1-4: your own subgroup in a raid), or a preview
	local function Wanted(f)
		if f.demo then return true end
		if not On() or SP:IsOff() then return false end
		if not IsInGroup() then return false end
		local n = GetNumSubgroupMembers and GetNumSubgroupMembers() or 0
		return (not issecretvalue(n)) and n > 0
	end
	-- a strip on screen for real (not a preview's)
	local function Live(f) return f:IsShown() and not f.demo end

	function SP:UpdatePartyStrip()
		for _, f in ipairs(frames) do
			if Live(f) then
				local shown = Wanted(f)
				f:SetAlpha(shown and 1 or 0)   -- by alpha: the frame holds the game's containers
				for _, line in ipairs(f.lines) do
					for i = 1, 4 do UpdateSpot(line, i, shown) end
					if shown then UpdateIcon(f, line) end
				end
			end
		end
	end

	-- -------------------------------------------------------------------------
	-- Rebuild: which strips show which totems, names, classes, the game's displays,
	-- layout and place. Out of combat only; a fight leaves it owed
	-- (PartyStripAfterCombat) and keeps what is built.
	-- -------------------------------------------------------------------------
	local picksNow = {}   -- (reused)
	local builtSig        -- the totems shown at the last rebuild (a newly learned one rebuilds)
	local function PicksSig(picks)
		local s = ""
		for _, e in ipairs(picks) do s = s .. e.key .. "," end
		return s
	end
	-- the strips in use and their lines: one strip with every totem, or (Break Up Totem
	-- List) a strip per totem, one totem too (it keeps its own spot and size). Each line's
	-- host goes to its strip; a line no strip shows sits out (hidden; real: its game
	-- displays retired). Out of combat only. Returns how many strips.
	local function AssignLines(picks, real)
		local count = #picks
		local split = BreakUp()
		local used = split and count or 1
		for _, line in ipairs(lineList) do line.strip = nil end
		for k = 1, used do
			local f = Strip(k)
			wipe(f.lines)
			if split then
				f.lines[1] = LineFor(f, picks[k])
				f.stripKey = picks[k].key
				f.spMoverLabel = "Party Strip: " .. TotemName(picks[k])
			else
				for j = 1, count do f.lines[j] = LineFor(f, picks[j]) end
				f.stripKey = nil
				f.spMoverLabel = "Party Strip"
			end
			f.used = true
			for _, line in ipairs(f.lines) do
				line.strip = f
				local host = line.host
				if host:GetParent() ~= f then   -- (this totem was on another strip)
					host:SetParent(f)
					host:ClearAllPoints()
					host:SetAllPoints(f)
				end
				host:Show()
			end
		end
		for _, line in ipairs(lineList) do
			if not line.strip then
				if real then RetireLine(line) end
				line.host:Hide()
			end
		end
		return used
	end

	function SP:RebuildPartyStrip()
		local f = frames[1]
		local on = On() and not self:IsOff()
		if not f and not on then return end
		f = f or self:CreatePartyStrip()
		if f.demo then return end   -- a preview has it: its Demo(false) rebuilds
		if InCombatLockdown() then
			pending = true
			self:UpdatePartyStrip()   -- (switched off in the fight: the alpha says so until it ends)
			if not on then
				for _, fr in ipairs(frames) do
					fr:SetAlpha(0)
					for _, line in ipairs(fr.lines) do
						for i = 1, 4 do ShowEngineRecord(line.slots[i], false) end
					end
				end
			end
			return
		end
		pending = false
		for _, fr in ipairs(frames) do Rehome(fr) end
		local picks = Picks(picksNow)
		builtSig = PicksSig(picks)
		if not on or #picks == 0 then   -- off, or no totem to show (nothing picked, or none learned yet)
			for _, line in ipairs(lineList) do
				RetireLine(line)
				line.host:Hide()
			end
			for _, fr in ipairs(frames) do RetireStrip(fr) end
			return
		end
		ResolveColors()
		local engine = EngineDotsAvailable()
		if engine then
			local any = false
			for _, e in ipairs(picks) do if e.ids then any = true end end
			engine = any
		end
		if engine then pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer") end
		local classSet = self.ThemeClassColorSet and self:ThemeClassColorSet(SPOT_CLASS)
		local used = AssignLines(picks, true)
		for k = used + 1, #frames do RetireStrip(frames[k]) end
		for k = 1, used do
			local fr = frames[k]
			BuildLines(fr, engine, classSet)
			Layout(fr)
			PaintPanel(fr)
		end
		PlaceAll()
		for k = 1, used do
			if not frames[k]:IsShown() then frames[k]:Show() end
		end
		if self.ThemeBoxesRefresh then self:ThemeBoxesRefresh() end   -- (ShamanPower Minimal: the icons' flat boxes)
		self:UpdatePartyStrip()
	end

	function SP:PartyStripAfterCombat()
		if pending then self:RebuildPartyStrip() end
	end

	-- the strips in use, in order (Unlock UI's boxes)
	local function UsedFrames()
		local out = {}
		for _, f in ipairs(frames) do if f.used then out[#out + 1] = f end end
		if #out == 0 then out[1] = SP:CreatePartyStrip() end
		return out
	end
	-- after a broken-up strip moved or changed size: the ones stacked under it follow
	-- (next frame, once the move is saved), and Unlock UI's boxes with them
	local restackQueued = false
	local function RestackNow()
		restackQueued = false
		if InCombatLockdown() then return end
		PlaceAll()
		if SP.RefreshUnlockBoxes then SP:RefreshUnlockBoxes() end
	end
	local function Restack()
		if restackQueued or not frames[2] then return end
		restackQueued = true
		C_Timer.After(0, RestackNow)
	end

	local demoPaint   -- (the preview's painter, while one runs)
	-- a setting changed (the Party Strip tab): what = "panel" (colors: at once, a
	-- fight too), "scale" (Size), else a rebuild
	function SP:PartyStripSettingChanged(what)
		local f = frames[1]
		if what == "panel" then
			for _, fr in ipairs(frames) do PaintPanel(fr) end
			return
		end
		if what == "scale" then
			-- the tab's Size sizes every strip: a broken-up strip's own size (Unlock UI's wheel)
			-- goes at once, in a fight too (only the frames wait for its end)
			local t = Opts().strips
			if type(t) == "table" then
				for _, r in pairs(t) do if type(r) == "table" then r.scale = nil end end
			end
			if f and f:IsShown() and not InCombatLockdown() then
				-- (a preview that has borrowed it fits it itself; Unlock UI's wheel resizes it on its spot)
				if f.stripKey == nil then
					if f:GetParent() == UIParent then
						self:SetFrameScaleKeepCenter(f, Scale())   -- grows round its middle, then that is its spot
						SavePosition(f)
					end
				else
					PlaceAll()   -- (each round its middle; the ones stacked under another follow it)
				end
				return
			end
		end
		if f and f.demo then   -- a preview has it: show the change there, rebuild afterwards
			if demoPaint then demoPaint() end
			return
		end
		self:RebuildPartyStrip()
	end

	function SP:ResetPartyStripPosition()
		Opts().position = nil
		local t = Opts().strips
		if type(t) == "table" then
			for _, r in pairs(t) do if type(r) == "table" then r.position = nil end end
		end
		if not InCombatLockdown() then PlaceAll() end
	end
	-- one strip's Reset (Unlock UI): a broken-up strip goes back under the one before it
	-- (the first: on the Party Strip's spot); the Party Strip to its first spot
	function SP:ResetPartyStripFramePosition(frame)
		if frame and frame.stripKey then
			local r = StripRec(frame.stripKey)
			if r then r.position = nil end
		else
			Opts().position = nil
		end
		if not InCombatLockdown() then PlaceAll() end
	end
	-- Unlock UI's wheel over a broken-up strip's box: that strip's own Size (nil: the
	-- tab's Size, for the one strip)
	function SP:PartyStripBoxAccess(frame)
		local key = frame and frame.stripKey
		if not key then return nil end
		return function() return ScaleOf(frame) end,
			function(v)
				StripRec(key, true).scale = v
				if InCombatLockdown() or frame:GetParent() ~= UIParent then return end
				local own = StripRec(key)
				if own and own.position then
					SP:SetFrameScaleKeepCenter(frame, ScaleOf(frame))   -- grows round its middle
					SavePosition(frame)
				end
				PlaceAll()   -- (one stacked under another stays under it; the ones under this follow)
			end,
			0.5, 3, 0.05, true
	end

	-- -------------------------------------------------------------------------
	-- Previews (the tab's live preview and Unlock UI): sample members acting out
	-- a short scene, looped. The game's live displays step aside meanwhile.
	-- -------------------------------------------------------------------------
	do
		local DEMO_PARTY = { { "Brakka", "WARRIOR" }, { "Lyria", "ROGUE" }, { "Tamsin", "PRIEST" }, { "Orrin", "HUNTER" } }
		local DEMO_SCENE = {
			{ "has", "has", "has", "has", down = true },             -- your totem is down, everyone has it
			{ "has", "missing", "has", "has", down = true },         -- the Rogue walked out of range
			{ "has", "missing", "has", "missing", down = true },
			{ "missing", "missing", "missing", "missing" },          -- no totem of yours down
			{ "has", "has", "unknown", "has", down = true, reports = true },   -- (TBC Anniversary Windfury: no report)
		}
		local demoBeat, demoTicker, demoLinesSeen = 1, nil, -1   -- (demoLinesSeen: how many lines the theme's boxes saw)
		-- a line's beat: the scene's, a step on for each line after the first (so they differ)
		local function DemoBeat(n, w)
			local idx = ((n - 1) % #DEMO_SCENE) + 1
			local beat = DEMO_SCENE[idx]
			if beat.reports and not (w and w.reports) then beat = DEMO_SCENE[(idx % #DEMO_SCENE) + 1] end
			return beat
		end
		-- what a preview shows: the totems shown, or the ones picked if none is learned yet
		local demoPicks = {}
		local function DemoPicks()
			Picks(demoPicks)
			if #demoPicks == 0 then
				for _, e in ipairs(Catalog()) do
					if Picked(e.key) then demoPicks[#demoPicks + 1] = e end
				end
			end
			return demoPicks
		end
		function SP:PartyStripDemo(on)
			local f = self:CreatePartyStrip()
			if on then
				local was = f.demo
				for _, fr in ipairs(frames) do
					fr.demo = true
					for _, line in ipairs(fr.lines) do
						for i = 1, 4 do ShowEngineRecord(line.slots[i], false) end
					end
				end
				local function paint()
					if InCombatLockdown() then return end   -- (the lines move between strips: never in a fight)
					ResolveColors()
					local picks = DemoPicks()
					local used = (#picks > 0) and AssignLines(picks) or 0
					for k = 1, used do
						local fr = frames[k]
						fr.demo = true
						for j, line in ipairs(fr.lines) do
							local beat = DemoBeat(demoBeat + (k - 1) + (j - 1), line.w)
							for i = 1, 4 do
								local c, d = line.spots[i], DEMO_PARTY[i]
								local color = ThemeClassColor(SPOT_CLASS, d[2], RAID_CLASS_COLORS[d[2]]) or RAID_CLASS_COLORS[d[2]]
								local r, g, b = 0, 1, 0
								if color then r, g, b = color.r, color.g, color.b end
								c.name:SetText(j == 1 and d[1] or "")
								c.name:SetTextColor(r, g, b)
								c.lit:SetVertexColor(r, g, b)
								PaintSpotColors(c)
								c.state = nil
								PaintMark(c, beat[i])
							end
							line.demoDown = beat.down and true or false
						end
						Layout(fr)
						PaintPanel(fr)
						if fr.iconsOn then
							for _, line in ipairs(fr.lines) do
								line.icon:SetDesaturated(not line.demoDown)
								line.icon:SetAlpha(line.demoDown and 1 or 0.5)
							end
						end
						fr.spDemoHidden = nil
						fr:SetAlpha(1)
						fr:Show()
					end
					-- the strips this preview does not use
					for k = used + 1, #frames do
						local fr = frames[k]
						fr.demo, fr.used, fr.spDemoHidden = true, false, true
						wipe(fr.lines)
						fr:Hide()
					end
					PlaceAll()   -- (Unlock UI: on their spots; a preview's borrowed strips stay where it put them)
					if #lineList ~= demoLinesSeen then   -- (a new line's icon: ShamanPower Minimal's flat box)
						demoLinesSeen = #lineList
						if self.ThemeBoxesRefresh then self:ThemeBoxesRefresh() end
					end
				end
				demoPaint = paint
				paint()
				if not was then
					if demoTicker then demoTicker:Cancel() end
					demoTicker = C_Timer.NewTicker(2.2, function()
						if not (frames[1] and frames[1].demo) then return end
						demoBeat = (demoBeat % #DEMO_SCENE) + 1
						if demoPaint then demoPaint() end
					end)
				end
			else
				if demoTicker then demoTicker:Cancel(); demoTicker = nil end
				demoPaint, demoBeat, demoLinesSeen = nil, 1, -1
				for _, fr in ipairs(frames) do
					fr.demo, fr.spDemoHidden = nil, nil
					if not InCombatLockdown() then Rehome(fr) end   -- (in a fight: the rebuild after it)
				end
				for _, line in ipairs(lineList) do
					for i = 1, 4 do line.spots[i].state = nil end
				end
				-- real names, classes, layout, place and the game's displays back
				if InCombatLockdown() then pending = true else self:RebuildPartyStrip() end
				if not (On() and not self:IsOff()) and not InCombatLockdown() then
					for _, fr in ipairs(frames) do fr:Hide() end
				end
			end
		end
		-- the settings preview: the Party Strip and, with Break Up Totem List, the other strips
		-- (k: 2 .. as many as the preview shows; nil past them)
		function SP:PartyStripPreviewFrame(k)
			if k == 1 then return self:CreatePartyStrip() end
			if not BreakUp() then return nil end
			local picks = DemoPicks()
			if #picks < 2 or k > #picks then return nil end
			return Strip(k)
		end

		if SP.RegisterPreview then
			local list = {}
			for k = 1, 20 do list[k] = function() return SP:PartyStripPreviewFrame(k) end end
			SP:RegisterPreview("partystrip", {
				frames = list,
				demo = "SP:PartyStripDemo",
				pad = 24,
				-- (broken up: the strips one under the other, in the pane's grid of one column)
				pane = { grid = true, columns = 1, maxScale = 2.5 },
			})
		end
	end
	-- its own Unlock UI box (one per strip with Break Up Totem List), with Reset (ShamanPowerUnlock.lua)
	if SP.UnlockModules then
		table.insert(SP.UnlockModules, {
			key = "partystrip", label = "Party Strip",
			enabled = function() return On() and not SP:IsOff() and (SP:PartyStripCounts()) > 0 end,
			frames = UsedFrames,
			save = function(frame)
				SavePosition(frame)
				Restack()
			end,
			reset = function() SP:ResetPartyStripPosition() end,
			resetOne = "ResetPartyStripFramePosition",
		})
	end

	-- -------------------------------------------------------------------------
	-- What wakes it (nothing ticks)
	-- -------------------------------------------------------------------------
	do
		-- in a group now (asked once per wake, for every strip)
		local function WantedLive()
			local f = frames[1]
			return f and Wanted(f) or false
		end
		-- a party member's auras changed (the core's UNIT_AURA, party1-4 included): that
		-- member's spot on every line, in one pass
		if SP.UNIT_AURA then
			hooksecurefunc(SP, "UNIT_AURA", function(_, _, unit)
				if issecretvalue(unit) then return end
				local i = PARTY_INDEX[unit]
				if not i then return end
				local want
				for _, f in ipairs(frames) do
					if Live(f) then
						if want == nil then want = WantedLive() end
						if not want then return end
						for _, line in ipairs(f.lines) do UpdateSpot(line, i, true) end
					end
				end
			end)
		end
		-- your totems changed: the icons' "not down" look (next frame, once per burst)
		local iconQueued = false
		local function IconNow()
			iconQueued = false
			local want, noted
			for _, f in ipairs(frames) do
				if Live(f) then
					for _, line in ipairs(f.lines) do
						UpdateIcon(f, line)
						if line.w.reports then   -- (#2)
							if want == nil then want = WantedLive() end
							if want then
								if not noted then NoteOwnDrop(line.w); noted = true end   -- (G4) where a new Windfury of yours went down
								for i = 1, 4 do UpdateSpot(line, i, true) end
							end
						end
					end
				end
			end
		end
		if SP.InvalidateTotemInfo then
			hooksecurefunc(SP, "InvalidateTotemInfo", function()
				if iconQueued then return end
				local any = false
				for _, f in ipairs(frames) do
					-- (out of sight: the next update sets it; #2: report spots follow your totem)
					if Live(f) and f:GetAlpha() > 0 and f.wakeOnTotems then any = true end
				end
				if not any then return end
				iconQueued = true
				C_Timer.After(0, IconNow)
			end)
		end
		-- a Windfury report (TBC Anniversary): that spot now, and again when it would run out
		local reportTimers, reportDue = {}, {}
		local function ReportSpot(i)
			for _, f in ipairs(frames) do
				if Live(f) then
					for _, line in ipairs(f.lines) do
						if line.w.reports then UpdateSpot(line, i, true) end
					end
				end
			end
		end
		local function ReportRanOut(i)
			reportTimers[i], reportDue[i] = nil, nil
			if WantedLive() then ReportSpot(i) end
		end
		-- (#3) the spot's expiry, from the report it shows (whenever and however it was painted)
		ArmReport = function(i, unit)
			local d = SP.WindfuryRangeData and SP.WindfuryRangeData[(UnitName(unit))]
			if not (d and d.timestamp) then return end
			local due = d.timestamp + REPORT_TTL + 0.1
			if reportDue[i] == due then return end
			reportDue[i] = due
			if reportTimers[i] then reportTimers[i]:Cancel() end
			reportTimers[i] = C_Timer.NewTimer(math.max(0.05, due - GetTime()), function() ReportRanOut(i) end)
		end
		if SP.SetWindfuryReport then
			hooksecurefunc(SP, "SetWindfuryReport", function(_, sender)
				local f = frames[1]
				if not (f and Live(f)) or type(sender) ~= "string" or not Wanted(f) then return end
				local any = false   -- (a line built for Windfury's reports)
				for _, fr in ipairs(frames) do
					for _, line in ipairs(fr.lines) do if line.w.reports then any = true end end
				end
				if not any then return end
				local name = strsplit("-", sender)
				for i = 1, 4 do
					local unit = PARTY[i]
					if SafeExists(unit) and UnitName(unit) == name then
						ReportSpot(i)   -- (arms its expiry)
						return
					end
				end
			end)
		end
	end
	-- a theme change: the marks, the panels and the lines repaint now; the game's dots
	-- take their class colors when built, so a new Class Colors set rebuilds them
	local classSetSeen
	if SP.OnThemeChanged then
		SP:OnThemeChanged(function()
			local f = frames[1]
			if not f then return end
			ResolveColors()
			for _, line in ipairs(lineList) do
				for i = 1, 4 do PaintSpotColors(line.spots[i]) end
			end
			for _, fr in ipairs(frames) do PaintPanel(fr) end
			if f.demo and demoPaint then demoPaint() end
			local set = SP.ThemeClassColorSet and SP:ThemeClassColorSet(SPOT_CLASS)
			if set ~= classSetSeen then
				classSetSeen = set
				if not f.demo then SP:RebuildPartyStrip() end
			end
		end)
	end
	-- another font for the names: the strips fit them again
	if SP.RefreshFonts then
		hooksecurefunc(SP, "RefreshFonts", function()
			local f = frames[1]
			if not (f and f:IsShown()) then return end
			if f.demo then
				if demoPaint then demoPaint() end
			elseif InCombatLockdown() then
				pending = true
			else
				for _, fr in ipairs(frames) do
					if fr.used and fr:IsShown() then Layout(fr) end
				end
				PlaceAll()
			end
		end)
	end
	-- a totem picked before it was learned shows once it is (the core's SPELLS_CHANGED, bucketed)
	if SP.SPELLS_CHANGED then
		hooksecurefunc(SP, "SPELLS_CHANGED", function()
			if not (On() and not SP:IsOff()) then return end
			local f = frames[1]
			if f and f.demo then return end
			if PicksSig(Picks(picksNow)) ~= builtSig then SP:RebuildPartyStrip() end
		end)
	end
	-- ShamanPower switched on or off (applied out of combat)
	SP:OnOnOff(function() SP:RebuildPartyStrip() end)
	-- another profile: its own settings and spot
	if SP.OnProfileChanged then
		hooksecurefunc(SP, "OnProfileChanged", function() SP:RebuildPartyStrip() end)
	end
end

-- Update all party range dots
function SP:UpdatePartyRangeDots()
	-- Always update range counters (even if dots are disabled)
	self:UpdateRangeCounters()

	-- Enable/disable partyRange subsystem based on whether any features are enabled
	-- (none are while ShamanPower is switched off: every dot hides and the pass stops)
	local off = self:IsOff()
	local rangeCounterEnabled = self.opt.rangeCounter and self.opt.rangeCounter.enabled and not off
	local dotsEnabled = self.opt.showPartyRangeDots and not off
	local coverageEnabled = self.opt.coverage and self.opt.coverage.enabled and not off
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
	-- "Only missing": a class-coloured dot for each member WITHOUT the buff, none for the rest
	local missingOnly = self.opt.partyDotsMissingOnly

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
			classColor = ThemeClassColor("tb.dots-class", class, classColor)
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
							PaintMissingDot(dot)
							dot:Show()
						else
							dot:Hide()
						end
						if useOverlay and mainDot then mainDot:Hide() end
					elseif haveTotem then
						local buffName = self:GetActiveTotemBuffName(element)
						local hasBuff = buffName and self:UnitHasBuff(unit, buffName, element)

						-- Special case: Air element (4) with no buffName = Windfury Totem
						local isWindfury = (element == 4 and not buffName and not SPCompat.FOREVER)
						if isWindfury then
							local playerName = UnitName(unit)
							local wfStatus = self:IsPlayerInWindfuryRange(playerName)
							if wfStatus == true and missingOnly then
								dot:Hide()
								if useOverlay and mainDot then mainDot:Hide() end
							elseif wfStatus == true then
								if classColor then
									dot:SetVertexColor(classColor.r, classColor.g, classColor.b)
								else
									dot:SetVertexColor(0, 1, 0)
								end
								dot:Show()
								if useOverlay and mainDot then mainDot:Hide() end
							elseif wfStatus == false then
								if missingOnly and classColor then
									dot:SetVertexColor(classColor.r, classColor.g, classColor.b)
								else
									PaintMissingDot(dot)
								end
								dot:Show()
								if useOverlay and mainDot then mainDot:Hide() end
							else
								dot:Hide()
								if useOverlay and mainDot then mainDot:Hide() end
							end
						elseif hasBuff and missingOnly then
							dot:Hide()
							if useOverlay and mainDot then mainDot:Hide() end
						elseif hasBuff then
							if classColor then
								dot:SetVertexColor(classColor.r, classColor.g, classColor.b)
							else
								dot:SetVertexColor(0, 1, 0)
							end
							dot:Show()
							if useOverlay and mainDot then mainDot:Hide() end
						elseif buffName then
							if missingOnly and classColor then
								dot:SetVertexColor(classColor.r, classColor.g, classColor.b)
							else
								PaintMissingDot(dot)
							end
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
	ThemeCounterFrame(frame)

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
				ThemeCounterFrame(frame)
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
	if not rcOpt or not rcOpt.enabled or self:IsOff() then
		-- Hide all counters when disabled (or ShamanPower is switched off)
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
					local isWindfury = (element == 4 and not buffName and not SPCompat.FOREVER)
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
			ThemeCounterFrame(frame)
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

-- A theme change (General > Themes): the red dots, the Coverage panel and the
-- counter frames take the new look now (nothing here is protected, so combat
-- does not matter); the totem bar's dots repaint on their next range pass.
if SP.OnThemeChanged then
	SP:OnThemeChanged(function()
		ResolveThemeLooks()
		local frame = SP.coverageFrame
		if frame then
			local co = SP.opt and SP.opt.coverage
			if not (co and co.hideBorder) then ThemeCoveragePanel(frame, true) end
			-- a Coverage dot paints only when its state flips: forget the state, so the next pass repaints
			for element = 1, 4 do
				for _, row in ipairs(frame.buttons[element].rows) do row.dotRed = nil end
			end
			for _, btn in pairs(frame.totemCells) do
				for _, row in ipairs(btn.rows) do row.dotRed = nil end
			end
			if SP.coverageDemoActive and SP.coverageDemo and SP.coverageDemo.paint then SP.coverageDemo.paint() end
		end
		local rc = SP.opt and SP.opt.rangeCounter
		for element = 1, 4 do
			local f = SP.rangeCounterFrames[element]
			if f and (SP.partyRangeDemoActive or not (rc and rc.hideFrame)) then ThemeCounterFrame(f, true) end
		end
		-- Class Colors: a dot set changed. The game-drawn dots and the Coverage rows
		-- take their colours when built, so they are built again (only then: a
		-- colour-picker drag also comes through here)
		if SP.ThemeClassColorSet then
			local party, cov = SP:ThemeClassColorSet("tb.dots-class"), SP:ThemeClassColorSet("mod.coverage-dots-class")
			if party ~= classSetsSeen.party then
				classSetsSeen.party = party
				if SP.RebuildEnginePartyDots then SP:RebuildEnginePartyDots() end
			end
			if cov ~= classSetsSeen.coverage then
				classSetsSeen.coverage = cov
				if SP.UpdateCoverageLayout and not InCombatLockdown() then SP:UpdateCoverageLayout() end
			end
		end
	end)
end

-- Enable ShamanPower switched: off hides every dot, counter and coverage cell and
-- stops the range pass; on brings back what the settings show.
SP:OnOnOff(function(off)
	if off then
		SP:UpdatePartyRangeDots()   -- dots, engine dots and counters hide; the pass stops
		SP:UpdateCoverage()
		return
	end
	-- roster changes while off were skipped: rebuild, then draw as the settings say
	SP:RebuildCoverage()
	if engineDotsReady then   -- the totem bar's dots exist (SetupPartyRangeDots has run)
		SP:RebuildEnginePartyDots()
		SP:UpdatePartyRangeDots()
		SP:EnableUpdateSubsystem("partyRange")   -- as SetupPartyRangeDots leaves it
	end
end)
