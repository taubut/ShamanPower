-- ============================================================================
-- ShamanPower [SPRange] Module
-- Totem Range Tracker - Shows which totems are affecting you
-- ============================================================================

-- "First Surname" on WoW: Forever (SPCompat.UnitName); other clients unchanged
local UnitName = (SPCompat and SPCompat.UnitName) or UnitName
local GetRaidRosterInfo = (SPCompat and SPCompat.GetRaidRosterInfo) or GetRaidRosterInfo
local SP = ShamanPower
local UnitBuff = SPCompat and SPCompat.UnitBuff or UnitBuff   -- ShamanPower's own reader on Forever, never another addon's global
-- Forever returns a LIST of enchants per weapon; the legacy global reports only
-- the first entry, which is empty when the imbue lands in the second.
local GetWeaponEnchantInfo = (SPCompat and SPCompat.GetWeaponEnchantInfo) or GetWeaponEnchantInfo
if not SP then
	print("|cff0070ddShamanPower [Totem Range Tracker]:|r ShamanPower is not loaded.")
	return
end

-- Mark module as loaded
SP.SPRangeLoaded = true

ShamanPower_RangeTracker = ShamanPower_RangeTracker or {}

-- the defaults InitSPRange fills in, registered like the other modules' (the support
-- code and Settings > Reset This Page read them)
if SP.SUPPORT_MODULE_DEFAULTS then
	SP.SUPPORT_MODULE_DEFAULTS.ShamanPower_RangeTracker = {
		tracked = { windfury = true, graceofair = true },
		position = { point = "CENTER", x = 0, y = 0 },
		shown = false,
	}
end

-- Trackable totems with their detection methods
-- detection: "buff" = check for buff, "weapon" = check weapon enchant
-- buffSpellID: the BUFF spell ID (aura on party members), NOT the cast spell ID
-- buffName is resolved at load time through SPCompat.SpellName
SP.TrackableTotems = {
	-- Earth
	{
		id = "soe",
		name = "Strength of Earth",
		element = 1,
		index = 1,
		spellID = 8075,
		detection = "buff",
		buffSpellID = 8076,
	},
	{
		id = "stoneskin",
		name = "Stoneskin",
		element = 1,
		index = 2,
		spellID = 8071,
		detection = "buff",
		buffSpellID = 8072,
	},
	-- Fire
	{
		id = "tow",
		name = "Totem of Wrath",
		element = 2,
		index = 1,
		spellID = 30706,
		detection = "buff",
		buffSpellID = 30708,
	},
	{
		id = "flametongue",
		name = "Flametongue Totem",
		element = 2,
		index = 5,
		spellID = 8227,
		detection = "buff",
		buffSpellID = 8215,
	},
	{
		id = "frostresist",
		name = "Frost Resistance",
		element = 2,
		index = 6,
		spellID = 8181,
		detection = "buff",
		buffSpellID = 8182,
	},
	-- Water
	{
		id = "manaspring",
		name = "Mana Spring",
		element = 3,
		index = 1,
		spellID = 5675,
		detection = "buff",
		buffSpellID = 5677,
	},
	{
		id = "healingstream",
		name = "Healing Stream",
		element = 3,
		index = 2,
		spellID = 5394,
		detection = "buff",
		buffSpellID = 5672,
	},
	{
		id = "fireresist",
		name = "Fire Resistance",
		element = 3,
		index = 6,
		spellID = 8184,
		detection = "buff",
		buffSpellID = 8185,
	},
	{
		id = "manatide",
		name = "Mana Tide Totem",
		element = 3,
		index = 3,
		spellID = 16190,
		detection = "buff",
		buffSpellID = 16191,
	},
	-- Air
	{
		id = "windfury",
		name = "Windfury Totem",
		element = 4,
		index = 1,
		spellID = 8512,
		detection = "weapon",  -- Special: check weapon enchant
		buffSpellID = 8513,
	},
	{
		id = "graceofair",
		name = "Grace of Air",
		element = 4,
		index = 2,
		spellID = 8835,
		detection = "buff",
		buffSpellID = 8836,
	},
	{
		id = "wrathofair",
		name = "Wrath of Air",
		element = 4,
		index = 3,
		spellID = 3738,
		detection = "buff",
		buffSpellID = 2895,
	},
	{
		id = "tranquilair",
		name = "Tranquil Air",
		element = 4,
		index = 4,
		spellID = 25908,
		detection = "buff",
		buffSpellID = 25909,
		buffSpellIDs = { 25909 },
		-- name AND icon rows are encrypted on WoW: Forever; the client cannot draw it
		icon = "Interface\\Icons\\Spell_Nature_Brilliance",
	},
	{
		id = "grounding",
		name = "Grounding",
		element = 4,
		index = 5,
		spellID = 8177,
		detection = "buff",
		buffSpellID = 8178,   -- every party member in its range carries it (measured 10-21)
	},
	{
		id = "natureresist",
		name = "Nature Resistance",
		element = 4,
		index = 6,
		spellID = 10595,
		detection = "buff",
		buffSpellID = 10596,
	},
	{
		id = "windwall",
		name = "Windwall",
		element = 4,
		index = 7,
		spellID = 15107,
		detection = "buff",
		buffSpellID = 15108,
	},
}

-- TBC Anniversary: Flametongue Totem enchants weapons and puts no buff on anyone
-- (8215 is "Rapid Cast" there), so it sat at MISSING: not tracked on that client.
-- Windfury, the same kind of totem, keeps its weapon-enchant check.
if not SPCompat.FOREVER then
	for i = #SP.TrackableTotems, 1, -1 do
		-- (Grounding: WoW: Forever only, as in the party buff list; Anniversary shows its hits already)
		local id = SP.TrackableTotems[i].id
		if id == "flametongue" or id == "grounding" then table.remove(SP.TrackableTotems, i) end
	end
end

-- Party Range is optional for this module. Keep its existing ranked buff
-- families here too, so the ID fallback works when only Totem Range is loaded.
-- Forever's Flametongue starts at 8230; 8215 belongs to Rapid Cast there.
local BUFF_RANKS = {
	[8076] = { 8076, 8162, 8163, 10441, 25362 },
	[8072] = { 8072, 8156, 8157, 10403, 10404, 10405 },
	[8230] = { 8230, 8250, 10521, 15036 },
	[8182] = { 8182, 10476, 10477 },
	[5677] = { 5677, 10491, 10493, 10494 },
	[5672] = { 5672, 6371, 6372, 10460, 10461 },
	[16191] = { 16191, 17355, 17360, 1325257 },   -- (1325257: rank 4, WoW: Forever)
	[8185] = { 8185, 10534, 10535 },
	[8836] = { 8836, 10626, 25360 },
	[8178] = { 8178 },
	[10596] = { 10596, 10598, 10599 },
	[15108] = { 15108, 15109, 15110 },
	[8515] = { 8515, 10609, 10612 },
}

-- TBC Anniversary's level-70 ranks (the buffs of 25528, 25508/25509, 25570, 25567,
-- 25560, 25563, 25574 and 25577 in Anniversary's SpellName.db2): matched by ID too
if not SPCompat.FOREVER then
	for buff, ids in pairs({ [8076] = { 25527 }, [8072] = { 25506, 25507 }, [5677] = { 25569 }, [5672] = { 25566 },
		[8182] = { 25559 }, [8185] = { 25562 }, [10596] = { 25573 }, [15108] = { 25576 } }) do
		for _, id in ipairs(ids) do table.insert(BUFF_RANKS[buff], id) end
	end
end

-- Resolve localized buff names and build client-specific spell ID sets once
for _, totem in ipairs(SP.TrackableTotems) do
	-- Display the client's spell name; English keeps the existing compact labels.
	totem.fallbackName = totem.name
	totem.name = SPCompat.SpellLabel(totem.spellID, totem.name)
	-- WoW: Forever made Windfury Totem a party buff (8515 / 10609 / 10612), not
	-- TBC's weapon enchant: read it like any other totem buff there
	if totem.id == "windfury" and SPCompat.FOREVER then
		totem.detection = "buff"
		totem.buffSpellID = 8515
		totem.buffSpellIDs = { 8515, 10609, 10612 }
	end
	if totem.buffSpellID then
		-- Forever reuses 8215 (TBC's Flametongue Totem buff) for "Rapid Cast"; the
		-- aura party members carry there is the effect spell
		if totem.id == "flametongue" and SPCompat.FOREVER then totem.buffSpellID = 8230 end
		totem.buffName = SPCompat.SpellName(totem.buffSpellID)
	end
	if SPCompat.FOREVER then
		-- Build once, after client-specific ID overrides; nameless auras need
		-- ID matching, while named entries retain the single native lookup.
		totem.buffSpellIDs = totem.buffSpellIDs
			or (SP.TotemBuffRanks and (SP.TotemBuffRanks[totem.buffSpellID] or SP.TotemBuffRanks[totem.spellID]))
			or BUFF_RANKS[totem.buffSpellID] or { totem.buffSpellID }
		totem.buffSpellIDSet = {}
		for _, spellID in ipairs(totem.buffSpellIDs) do totem.buffSpellIDSet[spellID] = true end
	end
end

-- Some translated ranks use a different name from rank one. Resolve those
-- aliases outside range updates, reusing each family's tables on spell changes.
-- English retains the original one-name query and its spell API count.
local buffAliases, buffAliasSets = {}, {}
local buffAliasGeneration = -1
local function RefreshBuffAliases()
	if buffAliasGeneration == SPCompat.SpellDataGeneration then return end
	buffAliasGeneration = SPCompat.SpellDataGeneration
	for name in pairs(buffAliases) do buffAliases[name] = nil end
	for name in pairs(buffAliasSets) do buffAliasSets[name] = nil end
	local locale = GetLocale and GetLocale()
	if not locale or locale == "enUS" or locale == "enGB" then return end
	for _, totem in ipairs(SP.TrackableTotems) do
		local ranks = totem.buffSpellIDs or BUFF_RANKS[totem.buffSpellID]
		if ranks then
			totem.buffName = SPCompat.SpellName(totem.buffSpellID)
			local names, nameSet = SPCompat.AuraFamilyNames(ranks)
			if totem.buffName and names and #names > 1 then
				buffAliases[totem.buffName], buffAliasSets[totem.buffName] = names, nameSet
			end
		end
	end
end
RefreshBuffAliases()
SPCompat.OnSpellDataChanged(function()
	if SP.spRangeFrame and SP.spRangeFrame:IsShown() and not SP:IsOff() then RefreshBuffAliases() end
end)

-- Only totems this client has. WoW: Forever has no Totem of Wrath and no Wrath
-- of Air; a tracked totem the client lacks would sit at MISSING forever.
if SPCompat.FOREVER and SPCompat and SPCompat.SpellExists then
	local kept = {}
	for _, totem in ipairs(SP.TrackableTotems) do
		if SPCompat.SpellExists(totem.spellID) then kept[#kept + 1] = totem end
	end
	SP.TrackableTotems = kept
end

-- Icon for a trackable totem. Tranquil Air (25908) has no readable icon row on
-- WoW: Forever (encrypted, like its name), so an entry may carry a static one.
function SP:TrackableTotemIcon(totem)
	local tex = GetSpellTexture and GetSpellTexture(totem.spellID)
	if not tex then tex = select(3, GetSpellInfo(totem.spellID)) end
	return tex or totem.icon
end

-- Build lookup by ID
SP.TrackableTotemsByID = {}
for _, totem in ipairs(SP.TrackableTotems) do
	SP.TrackableTotemsByID[totem.id] = totem
end

-- Short names for display
SP.TrackableTotemShortNames = {
	soe = "SoE",
	stoneskin = "Stone",
	tow = "ToW",
	flametongue = "FT",
	frostresist = "FrRes",
	manaspring = "Mana",
	healingstream = "Heal",
	fireresist = "FiRes",
	manatide = "Mana Tide",
	windfury = "WF",
	graceofair = "GoA",
	wrathofair = "WoA",
	tranquilair = "Tranq",
	grounding = "Ground",
	natureresist = "NaRes",
	windwall = "Wind",
}

-- Initialize SPRange settings
function SP:InitSPRange()
	-- Ensure profile table exists for visual settings
	self:EnsureProfileTable("rangeTracker")

	-- Migrate old global settings to profile if they exist
	if ShamanPower_RangeTracker then
		if ShamanPower_RangeTracker.opacity and ShamanPower_RangeTracker.opacity ~= 1.0 then
			self.opt.rangeTracker.opacity = ShamanPower_RangeTracker.opacity
			ShamanPower_RangeTracker.opacity = nil
		end
		if ShamanPower_RangeTracker.iconSize and ShamanPower_RangeTracker.iconSize ~= 36 then
			self.opt.rangeTracker.iconSize = ShamanPower_RangeTracker.iconSize
			ShamanPower_RangeTracker.iconSize = nil
		end
		if ShamanPower_RangeTracker.vertical then
			self.opt.rangeTracker.vertical = ShamanPower_RangeTracker.vertical
			ShamanPower_RangeTracker.vertical = nil
		end
		if ShamanPower_RangeTracker.hideNames then
			self.opt.rangeTracker.hideNames = ShamanPower_RangeTracker.hideNames
			ShamanPower_RangeTracker.hideNames = nil
		end
		if ShamanPower_RangeTracker.hideBorder then
			self.opt.rangeTracker.hideBorder = ShamanPower_RangeTracker.hideBorder
			ShamanPower_RangeTracker.hideBorder = nil
		end
	end

	-- Runtime state stays in global SavedVariable
	if not ShamanPower_RangeTracker then
		ShamanPower_RangeTracker = {}
	end
	if not ShamanPower_RangeTracker.tracked then
		-- Default: track Windfury and Grace of Air
		ShamanPower_RangeTracker.tracked = {
			windfury = true,
			graceofair = true,
		}
	end
	if not ShamanPower_RangeTracker.position then
		ShamanPower_RangeTracker.position = { point = "CENTER", x = 0, y = 0 }
	end
	if ShamanPower_RangeTracker.shown == nil then
		ShamanPower_RangeTracker.shown = false
	end
end

-- Check readable player or group auras through the native aura API
local function MainlineHasNamedBuff(unit, buffName, buffSpellIDSet)
	if issecretvalue(buffName) then return false end
	if SPCompat and SPCompat.AurasUnreadable and SPCompat.AurasUnreadable() then return false end
	if buffName then
		if not (C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName) then return false end
		local aura = C_UnitAuras.GetAuraDataBySpellName(unit, buffName, "HELPFUL")
		-- The native lookup already selected the name; do not inspect secret fields.
		if issecretvalue(aura) then return false end
		if aura ~= nil then return true end
		local aliases = buffAliases[buffName]
		if aliases then
			for index = 1, #aliases do
				if aliases[index] ~= buffName then
					aura = C_UnitAuras.GetAuraDataBySpellName(unit, aliases[index], "HELPFUL")
					if issecretvalue(aura) then return false end
					if aura ~= nil then return true end
				end
			end
		end
		return false
	end
	if not (buffSpellIDSet and C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return false end
	-- Tranquil Air's name is encrypted. Only public IDs from readable auras
	-- can match here; this does not bypass combat aura restrictions.
	for index = 1, 40 do
		local aura = C_UnitAuras.GetAuraDataByIndex(unit, index, "HELPFUL")
		if issecretvalue(aura) then return false end
		if not aura then break end
		local spellID = aura.spellId
		if not issecretvalue(spellID) and spellID and buffSpellIDSet[spellID] then return true end
	end
	return false
end

function SP:SPRangeHasBuff(buffName, buffSpellIDSet)
	if issecretvalue(buffName) then return false end
	if SPCompat.FOREVER then
		return MainlineHasNamedBuff("player", buffName, buffSpellIDSet)
	end
	if not buffName then return false end

	for i = 1, 32 do
		local name = UnitBuff("player", i)
		if issecretvalue(name) then return false end
		if not name then break end
		if name == buffName or (buffAliasSets[buffName] and buffAliasSets[buffName][name]) then return true end
	end
	return false
end

-- Check if player has Windfury weapon enchant
function SP:SPRangeHasWindfuryWeapon()
	-- WoW: Forever: Windfury Totem is the party buff there, and any other
	-- temporary enchant (your own imbue, a rogue's poison) is not Windfury
	if SPCompat.FOREVER then
		local wf = SP.TrackableTotemsByID and SP.TrackableTotemsByID.windfury
		if wf and MainlineHasNamedBuff("player", wf.buffName, wf.buffSpellIDSet) then return true, nil, nil end
		return false, nil, nil
	end
	local hasMainHandEnchant, mainHandExpiration, mainHandCharges, mainHandEnchantID,
	      hasOffHandEnchant, offHandExpiration, offHandCharges, offHandEnchantID = GetWeaponEnchantInfo()

	-- Windfury weapon enchant IDs (from Windfury Totem)
	-- The enchant applied by Windfury Totem is different from the shaman's self-buff
	-- We check if either hand has any temporary enchant as an approximation
	-- More accurate: check for specific Windfury buff on weapon
	if hasMainHandEnchant or hasOffHandEnchant then
		-- Check if we also have the Windfury buff indicator
		-- Windfury Totem applies "Windfury Totem" buff in some versions
		-- or we can check for the weapon enchant directly
		return true, mainHandExpiration, offHandExpiration
	end
	return false, nil, nil
end

-- Check if player is in range of a tracked totem
function SP:SPRangeCheckTotem(totemData)
	if totemData.detection == "weapon" then
		-- Special case: Windfury - check weapon enchant
		local hasEnchant = self:SPRangeHasWindfuryWeapon()
		return hasEnchant
	else
		-- Standard buff check
		return self:SPRangeHasBuff(totemData.buffName, totemData.buffSpellIDSet)
	end
end

-- Our own totem of this kind, if it's the one down for its element: in range by
-- distance from where we dropped it (see ShamanPower:TotemDropInRange).
-- nil = not ours, or no position to measure from.
function SP:SPRangeOwnTotemInRange(totemData)
	if not self.TotemDropInRange or not self.GetElementTotemInfo then return nil end
	local have, name = self:GetElementTotemInfo(totemData.element)
	if issecretvalue(have) or issecretvalue(name) or not have or type(name) ~= "string" then return nil end
	if not SPCompat.TotemNameMatches(name, totemData.spellID, totemData.fallbackName) then return nil end
	return self:TotemDropInRange(totemData.element)
end

-- ============================================================================
-- In a fight on WoW: Forever, drawn by the game (10-21)
-- ============================================================================
-- Buffs cannot be read in a fight there, and dungeons and raids give out no positions: a button
-- kept what it showed before the pull. The game still draws the buff on you, so over each icon sits
-- an engine aura slot for its buff (every rank, from any shaman: the overlay is about you having it),
-- its child the totem's picture in full color. In a fight the icon takes its Out of Range look
-- underneath, and the game covers it in full color while the buff is on you, in dungeons too. The
-- status, its border, text and effects keep their own answer (your own totem's drop spot, else the
-- last one): the game only draws while the buff is there. Built out of combat (a fight's start is
-- the last moment), lit by alpha.
local spEnginePending = false
local function SPRangeEngineAvailable()
	return SPCompat.secretsRegime == true and C_AddOns ~= nil and C_AddOns.LoadAddOn ~= nil
end
function SP:SPRangeEngineBuild(btn)
	if btn.spEngine or not SPRangeEngineAvailable() then return end
	local totem = btn.totemData
	local list = totem and totem.buffSpellIDs
	if not list or totem.detection == "weapon" then return end
	if InCombatLockdown() then spEnginePending = true return end
	pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
	local ok, c = pcall(CreateFrame, "AuraContainer", nil, btn, "CustomAuraContainerTemplate")
	if not ok or not c then return end
	local icon = btn.icon
	c:SetAllPoints(icon)
	c:SetFrameLevel(btn:GetFrameLevel() + 1)   -- right above the icon, under its glows and texts
	local ids = {}
	for _, id in ipairs(list) do ids[id] = true end
	local file = self:TrackableTotemIcon(totem)
	local a, b, cc, d, e, f, g, h = icon:GetTexCoord()
	local okAdd, err = pcall(c.AddAuraSlot, c, "sprange_" .. tostring(totem.id), "HELPFUL", {
		candidateFilters = { includeSpellIDs = ids },
		initializeFrame = function(button)
			if button.SetMouseClickEnabled then pcall(button.SetMouseClickEnabled, button, false) end
			if button.SetMouseMotionEnabled then pcall(button.SetMouseMotionEnabled, button, false) end
			button:ClearAllPoints()
			button:SetAllPoints(c)
			pcall(button.SetFrameLevel, button, c:GetFrameLevel())
			local t = button:CreateTexture(nil, "ARTWORK")
			t:SetAllPoints(button)
			if file then t:SetTexture(file) end
			if h then t:SetTexCoord(a, b, cc, d, e, f, g, h) end
		end,
	})
	if not okAdd then
		c:Hide()
		if SPCompat.Trace then SPCompat.Trace("SPRANGE AddAuraSlot %s failed: %s", tostring(totem.id), tostring(err)) end
		return
	end
	pcall(c.SetUnit, c, "player")
	pcall(c.SetEnabled, c, false)
	c:SetAlpha(0)
	btn.spEngine = c
	self:SPRangeEngineRoom(btn)
end
-- the button's own frames right above the icon go one level up (the game's picture between)
function SP:SPRangeEngineRoom(btn)
	local c = btn.spEngine
	if not c then return end
	local lvl = btn:GetFrameLevel() + 1
	for _, ch in ipairs({ btn:GetChildren() }) do
		if ch ~= c and not (ch.IsForbidden and ch:IsForbidden()) and ch:GetFrameLevel() <= lvl then ch:SetFrameLevel(lvl + 1) end
	end
end
-- (3.0.9.6) as on the totem bar: a slot switched on in a fight heard of no change to your auras after
-- that moment, so a buff that reached you later never showed. While one is on, each change to your
-- auras has it read them again (once a frame at most); asleep again once none is.
local spEngineAuraWatch = CreateFrame("Frame")
if SPCompat and SPCompat.StressRegister then SPCompat.StressRegister(spEngineAuraWatch, "Totem Range Tracker") end
spEngineAuraWatch:SetScript("OnEvent", function(self)
	local frame = SP.spRangeFrame
	local any = false
	if frame and frame.totemButtons then
		for _, btn in pairs(frame.totemButtons) do
			local c = btn.spEngineOn and btn.spEngine
			if c then any = true; pcall(c.UpdateAllAuras, c) end
		end
	end
	if not any then self:UnregisterEvent("UNIT_AURA") end
end)
-- on: in a fight, the icon takes its Out of Range look and the game covers it while the buff is on you
function SP:SPRangeEngineApply(btn, on)
	local c = btn.spEngine
	if not c then return end
	on = on and true or false
	if on and btn.status == "inrange" then
		local look = self:SPRangeIconOpt(btn.totemData.id, "oorLook")
		btn.rangeOverlay:SetShown(look == "red")
		btn.icon:SetDesaturated(look == "red" or look == "gray")
		btn.icon:SetAlpha((look == "dim" and 0.4) or (look == "none" and 1) or 0.6)
	end
	if btn.spEngineOn ~= on then
		pcall(c.SetEnabled, c, on)
		if on then pcall(c.UpdateAllAuras, c) end
		c:SetAlpha(on and 1 or 0)
		btn.spEngineOn = on
		if on then spEngineAuraWatch:RegisterUnitEvent("UNIT_AURA", "player") end
	end
end
local spEngineEvents = CreateFrame("Frame")
spEngineEvents:RegisterEvent("PLAYER_REGEN_DISABLED")   -- (before the lockdown)
spEngineEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
spEngineEvents:SetScript("OnEvent", function(_, event)
	local frame = SP.spRangeFrame
	if not (frame and frame.totemButtons) then return end
	if event == "PLAYER_REGEN_ENABLED" and not spEnginePending then return end
	spEnginePending = false
	for _, btn in pairs(frame.totemButtons) do
		if btn.spEngine then SP:SPRangeEngineRoom(btn) else SP:SPRangeEngineBuild(btn) end
	end
end)

-- Theme looks (Appearance > Themes, ShamanPowerTheme.lua), spot mod.range-colors:
-- the overlay panel's background and border. On Standard every read is nil and
-- SP:ApplyPanelBackdrop's colours stay; `restore` puts them back (the Themes
-- tab went back to Standard).
local THEME_SPOT = "mod.range-colors"
local function ThemeRGB(role)
	if SP.ThemeColor then return SP:ThemeColor(THEME_SPOT, role) end
end
local function ThemePanel(frame, restore)
	local bg, edge = SP.PANEL_BG, SP.PANEL_BORDER
	local r, g, b = ThemeRGB("bg")
	if r then frame:SetBackdropColor(r, g, b, (SP.ThemeAlpha and SP:ThemeAlpha(THEME_SPOT, "bg")) or bg[4])
	elseif restore then frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4]) end
	r, g, b = ThemeRGB("border")
	if r then frame:SetBackdropBorderColor(r, g, b, edge[4])
	elseif restore then frame:SetBackdropBorderColor(edge[1], edge[2], edge[3], edge[4]) end
end

-- Create the SPRange frame
function SP:CreateSPRangeFrame()
	if self.spRangeFrame then return self.spRangeFrame end

	local frame = CreateFrame("Frame", "ShamanPowerRangeFrame", UIParent, "BackdropTemplate")
	frame:SetSize(150, 40)
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:SetClampedToScreen(true)

	-- Backdrop
	SP:ApplyPanelBackdrop(frame)
	ThemePanel(frame)

	-- Title
	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	title:SetPoint("TOP", frame, "TOP", 0, -6)
	title:SetText("Totem Range")
	SP:SetSPFont(title, "labels", 11, "", STANDARD_TEXT_FONT)
	title:SetShadowOffset(1, -1)
	title:SetTextColor(0.902, 0.918, 0.941)
	frame.title = title

	-- Settings button (cog icon in top right)
	local settingsBtn = CreateFrame("Button", nil, frame)
	settingsBtn:SetSize(14, 14)
	settingsBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
	SP:StyleSettingsButton(settingsBtn)
	settingsBtn:SetScript("OnClick", function()
		SP:OpenFrameSettings("sprange", frame)
	end)
	settingsBtn:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Totem Range Tracker settings", 1, 1, 1)
		GameTooltip:Show()
	end)
	settingsBtn:HookScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	frame.settingsBtn = settingsBtn

	-- Container for totem icons
	local iconContainer = CreateFrame("Frame", nil, frame)
	iconContainer:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -20)
	iconContainer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 8)
	frame.iconContainer = iconContainer

	-- Drag to move (ALT+drag when borderless, normal drag when bordered)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self)
		if not self:IsMovable() then return end
		-- If border is hidden, require ALT to drag
		if SP.opt.rangeTracker.hideBorder and not IsAltKeyDown() then
			return
		end
		self:StartMoving()
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		-- Save position
		-- the point's other end too: Unlock UI drops the frame anchored to a corner of the screen, and
		-- reading that back as "from the center" put it back in the middle (a reviewer's bug, 3.0.9.1)
		local point, _, relPoint, x, y = self:GetPoint()
		ShamanPower_RangeTracker.position = { point = point, relPoint = relPoint, x = x, y = y }
	end)

	-- Right-click to configure (when border is hidden)
	frame:SetScript("OnMouseUp", function(self, button)
		if button == "RightButton" and SP.opt.rangeTracker.hideBorder then
			SP:ShowSPRangeConfig()
		end
	end)

	-- Tooltip
	frame:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine("Totem Range Tracker", 1, 0.82, 0)
		GameTooltip:AddLine(" ")
		if SP.opt.rangeTracker.hideBorder then
			GameTooltip:AddLine("ALT+drag to move", 0.7, 0.7, 0.7)
			GameTooltip:AddLine("Right-click for settings", 0.7, 0.7, 0.7)
		else
			GameTooltip:AddLine("Drag to move", 0.7, 0.7, 0.7)
		end
		GameTooltip:Show()
	end)
	frame:SetScript("OnLeave", function(self)
		GameTooltip:Hide()
	end)

	frame.totemButtons = {}
	frame:Hide()

	-- Enable/disable spRange subsystem based on visibility
	frame:HookScript("OnShow", function()
		SP:SetupSPRangeUpdater()
		SP:EnableUpdateSubsystem("spRange")
	end)
	frame:HookScript("OnHide", function()
		SP:DisableUpdateSubsystem("spRange")
	end)

	self.spRangeFrame = frame
	return frame
end

-- (3.0.9.2) Each tracked totem's own look, from its right-click menu on the page's Totems to
-- Track row (ShamanPower_Config/TrackerIcons.lua). opt.rangeTracker.icons[id] holds only what
-- the player set there; anything unset is the page's (Icon Size, Hide Names, Show Totem Icons,
-- as they were) or the look the overlay always had, so an icon nobody touched looks the same.
SP.SPRANGE_ICON_DEFAULTS = {
	opacity = 1, statusText = true,
	inEffect = "none", inGlowColor = { r = 0.2, g = 1, b = 0.4 },
	oorLook = "red", oorEffect = "none", oorGlowColor = { r = 1, g = 0.25, b = 0.25 },
	missingLook = "gray",
}
-- value, and true when it is the icon's own
function SP:SPRangeIconOpt(id, key)
	local rt = self.opt and self.opt.rangeTracker
	local own = rt and type(rt.icons) == "table" and rt.icons[id]
	local v
	if type(own) == "table" then v = own[key] end
	if v ~= nil then return v, true end
	if key == "iconSize" then return (rt and rt.iconSize) or 36 end
	if key == "showName" then return not (rt and rt.hideNames) end
	if key == "showMode" then return (rt and rt.showMode) or "always" end
	if key == "glowShape" then return (self.opt and self.opt.glowShape) or "default" end
	return SP.SPRANGE_ICON_DEFAULTS[key]
end
function SP:SetSPRangeIconOpt(id, key, v)
	local rt = self.opt and self.opt.rangeTracker
	if not rt then return end
	if type(rt.icons) ~= "table" then rt.icons = {} end
	local own = rt.icons[id]
	if type(own) ~= "table" then own = {}; rt.icons[id] = own end
	own[key] = v
	if next(own) == nil then rt.icons[id] = nil end
	self:SPRangeRefreshLook()
end
-- Theme hook (Appearance > Themes, spot mod.range): each totem's two glow colors travel with a
-- theme ("default": the overlay's own green and red, or whatever the icon has from nothing)
if SP.ThemeSpotSettings then
	local entries = {}
	for _, t in ipairs(SP.TrackableTotems) do
		for _, k in ipairs({ "inGlowColor", "oorGlowColor" }) do
			local id = t.id
			entries[#entries + 1] = { key = k .. "." .. id,
				label = (t.name or id) .. (k == "inGlowColor" and " In Range Glow Color" or " Out of Range Glow Color"),
				mayBeColor = true,
				get = function()
					local rt = SP.opt and SP.opt.rangeTracker
					local own = rt and type(rt.icons) == "table" and rt.icons[id]
					local c = type(own) == "table" and own[k]
					if type(c) ~= "table" then return "default" end
					return { r = c.r or c[1] or 1, g = c.g or c[2] or 1, b = c.b or c[3] or 1 }
				end,
				set = function(v)
					if v == "default" then SP:SetSPRangeIconOpt(id, k, nil)
					elseif type(v) == "table" then SP:SetSPRangeIconOpt(id, k, { r = v.r or v[1], g = v.g or v[2], b = v.b or v[3] }) end
				end }
		end
	end
	SP:ThemeSpotSettings("mod.range", entries)
end

-- Reset All Colors (Appearance > Themes): the glow colors back to the overlay's own
if SP.ResetAllColorsToDefault and hooksecurefunc then
	hooksecurefunc(SP, "ResetAllColorsToDefault", function()
		local rt = SP.opt and SP.opt.rangeTracker
		if not (rt and type(rt.icons) == "table") then return end
		for id, own in pairs(rt.icons) do
			if type(own) == "table" then
				own.inGlowColor, own.oorGlowColor = nil, nil
				if next(own) == nil then rt.icons[id] = nil end
			end
		end
		SP:SPRangeRefreshLook()
	end)
end

-- the overlay (or its preview) drawn again with the icons' settings as they are now
function SP:SPRangeRefreshLook()
	if self.sprangeDemoActive and self.sprangeDemo and self.sprangeDemo.build then
		self.sprangeDemo.build()
	elseif self.spRangeFrame then
		self:UpdateSPRangeFrame()
		self:UpdateSPRangeStatus()
	end
end

-- a glow (the icon's Glow Shape, Proc Glow too) and / or a pulse on a button, in one color;
-- fx "none" stops them. Only redone when something about it changed.
local function rangeColor(c, dr, dg, db)
	if type(c) ~= "table" then return dr, dg, db end
	return c.r or c[1] or dr, c.g or c[2] or dg, c.b or c[3] or db
end
function SP:SPRangeEffect(btn, fx, c, shapeKey)
	local id = btn.totemData and btn.totemData.id
	-- each moment's own Glow Shape (inGlowShape / oorGlowShape), else the icon's, else the shared one
	local shape = (shapeKey and (self:SPRangeIconOpt(id, shapeKey))) or self:SPRangeIconOpt(id, "glowShape")
	local r, g, b = rangeColor(c, 1, 1, 1)
	if btn.spFx == fx and btn.spFxShape == shape and btn.spFxR == r and btn.spFxG == g and btn.spFxB == b then return end
	btn.spFx, btn.spFxShape, btn.spFxR, btn.spFxG, btn.spFxB = fx, shape, r, g, b
	if btn.spGlow then btn.spGlow:Hide(); btn.spGlowAnim:Stop() end
	if btn.spProc and SP.ProcGlow_Stop then SP.ProcGlow_Stop(btn, "sprange"); btn.spProc = nil end
	if btn.spPulse then btn.spPulse:Stop() end
	if not fx or fx == "none" then return end
	if fx == "glow" or fx == "both" then
		if shape == "proc" and SP.ProcGlow_Start and SP.ProcGlowOptions then
			SP.ProcGlow_Start(btn, SP:ProcGlowOptions(btn, { r, g, b, 1 }, "sprange", false, SP.PROC_GLOW_OUT or 0.2))
			btn.spProc = true
		else
			if not btn.spGlow then
				local t = btn:CreateTexture(nil, "OVERLAY", nil, 2)
				t:SetPoint("TOPLEFT", -10, 10); t:SetPoint("BOTTOMRIGHT", 10, -10)
				t:SetTexture("Interface\\SpellActivationOverlay\\IconAlert")
				t:SetTexCoord(0.00781250, 0.50781250, 0.27734375, 0.52734375)
				if SP.ShapeGlow then SP:ShapeGlow(t, "alert") end
				t:SetBlendMode("ADD")
				local ag = t:CreateAnimationGroup(); ag:SetLooping("REPEAT")
				local a1 = ag:CreateAnimation("Alpha"); a1:SetFromAlpha(0.15); a1:SetToAlpha(0.8); a1:SetDuration(0.5); a1:SetOrder(1)
				local a2 = ag:CreateAnimation("Alpha"); a2:SetFromAlpha(0.8); a2:SetToAlpha(0.15); a2:SetDuration(0.5); a2:SetOrder(2)
				btn.spGlow, btn.spGlowAnim = t, ag
			end
			if SP.PaintGlowShape then SP:PaintGlowShape(btn.spGlow, shape) end
			btn.spGlow:SetVertexColor(r, g, b)
			btn.spGlow:Show(); btn.spGlowAnim:Play()
		end
	end
	if fx == "pulse" or fx == "both" then
		if not btn.spPulse then
			local pg = btn.icon:CreateAnimationGroup(); pg:SetLooping("REPEAT")
			local p1 = pg:CreateAnimation("Scale"); p1:SetScale(1.12, 1.12); p1:SetDuration(0.45); p1:SetOrder(1)
			local p2 = pg:CreateAnimation("Scale"); p2:SetScale(1 / 1.12, 1 / 1.12); p2:SetDuration(0.45); p2:SetOrder(2)
			btn.spPulse = pg
		end
		btn.spPulse:Play()
	end
end

-- one button's look for its status: in range, out of range, missing (the overlay and its preview)
function SP:SPRangePaint(btn, status)
	local id = btn.totemData and btn.totemData.id
	local textOn = self:SPRangeIconOpt(id, "statusText") ~= false
	btn:SetAlpha(tonumber((self:SPRangeIconOpt(id, "opacity"))) or 1)
	if status == "inrange" then
		btn:SetBackdropBorderColor(0, 1, 0, 1); btn.rangeOverlay:Hide()
		btn.icon:SetDesaturated(false); btn.icon:SetAlpha(1); btn.statusText:Hide()
		btn.nameText:SetTextColor(0, 1, 0.4)
		self:SPRangeEffect(btn, self:SPRangeIconOpt(id, "inEffect"), (self:SPRangeIconOpt(id, "inGlowColor")), "inGlowShape")
	elseif status == "outofrange" then
		-- Red (as it always was): grayed with a red film; Gray; Dim; None: full color
		local look = self:SPRangeIconOpt(id, "oorLook")
		btn:SetBackdropBorderColor(0.8, 0, 0, 1)
		btn.rangeOverlay:SetShown(look == "red")
		btn.icon:SetDesaturated(look == "red" or look == "gray")
		btn.icon:SetAlpha((look == "dim" and 0.4) or (look == "none" and 1) or 0.6)
		btn.statusText:SetText("OUT OF\nRANGE"); btn.statusText:SetTextColor(1, 0.2, 0.2); btn.statusText:SetShown(textOn)
		btn.nameText:SetTextColor(0.8, 0.3, 0.3)
		self:SPRangeEffect(btn, self:SPRangeIconOpt(id, "oorEffect"), (self:SPRangeIconOpt(id, "oorGlowColor")), "oorGlowShape")
	else
		-- Gray (as it always was); Dim: faded in color; None: full color
		local look = self:SPRangeIconOpt(id, "missingLook")
		btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1); btn.rangeOverlay:Hide()
		btn.icon:SetDesaturated(look == "gray")
		btn.icon:SetAlpha(look == "none" and 1 or 0.4)
		btn.statusText:SetText("MISSING"); btn.statusText:SetTextColor(0.7, 0.7, 0.7); btn.statusText:SetShown(textOn)
		btn.nameText:SetTextColor(0.5, 0.5, 0.5)
		self:SPRangeEffect(btn, "none")
	end
end

-- the frame sized to the shown buttons and the buttons placed in it (each its own size)
function SP:SPRangePlace(frame, shown)
	local padding, n = 6, #shown
	local isVertical = SP.opt.rangeTracker.vertical
	local maxS, total, nameSpace = 0, 0, 0
	for _, btn in ipairs(shown) do
		local s = btn.spSize or 36
		if s > maxS then maxS = s end
		total = total + s
		if btn.nameText:IsShown() then nameSpace = 14 end
	end
	local gaps = padding * math.max(n - 1, 0)
	local width, height
	if isVertical then
		width = maxS + 24 + nameSpace
		height = total + gaps + 28
	else
		width = total + gaps + 24
		height = maxS + 26 + nameSpace
	end
	frame:SetSize(math.max(80, width), height)
	local x, y = (frame:GetWidth() - (total + gaps)) / 2, -20
	for _, btn in ipairs(shown) do
		btn:ClearAllPoints()
		if isVertical then
			btn:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, y)
			y = y - (btn.spSize or 36) - padding
		else
			btn:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -20)
			x = x + (btn.spSize or 36) + padding
		end
		btn:Show()
	end
end

-- Create a totem button for SPRange
function SP:CreateSPRangeTotemButton(parent, totemData, index)
	local iconSize = SP:SPRangeIconOpt(totemData.id, "iconSize")   -- (3.0.9.2: its own, else the page's)
	local btn = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	btn:SetSize(iconSize, iconSize)
	btn.spSize = iconSize

	-- Background
	SP:ApplyPanelBackdrop(btn)

	-- Icon
	local icon = btn:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("TOPLEFT", 3, -3)
	icon:SetPoint("BOTTOMRIGHT", -3, 3)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	-- Get icon from spell
	icon:SetTexture(self:TrackableTotemIcon(totemData))
	btn.icon = icon

	-- Range indicator overlay (red tint)
	local rangeOverlay = btn:CreateTexture(nil, "OVERLAY")
	rangeOverlay:SetAllPoints(icon)
	rangeOverlay:SetColorTexture(0.3, 0, 0, 0.6)  -- Darker red overlay
	rangeOverlay:Hide()
	btn.rangeOverlay = rangeOverlay

	-- Status text (shows "OUT OF RANGE" or "MISSING")
	local statusText = btn:CreateFontString(nil, "OVERLAY")
	SP:SetSPFont(statusText, "labels", 7, "OUTLINE")
	statusText:SetPoint("CENTER", btn, "CENTER", 0, 0)
	statusText:SetTextColor(1, 0.2, 0.2)  -- Red text
	statusText:SetShadowColor(0, 0, 0, 1)
	statusText:SetShadowOffset(1, -1)
	statusText:Hide()
	btn.statusText = statusText

	-- Short totem name below icon
	local nameText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	SP:SetSPFont(nameText, "labels", 8, "OUTLINE")
	nameText:SetPoint("TOP", btn, "BOTTOM", 0, -1)
	nameText:SetText(self.TrackableTotemShortNames[totemData.id] or totemData.name:sub(1, 6))
	nameText:SetTextColor(0.8, 0.8, 0.8)
	if not SP:SPRangeIconOpt(totemData.id, "showName") then
		nameText:Hide()
	end
	btn.nameText = nameText

	-- In-range state
	btn.inRange = false
	btn.status = "unknown"  -- "inrange", "outofrange", "missing"

	-- Tooltip
	btn:EnableMouse(true)
	btn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(totemData.name, 1, 1, 1)
		if totemData.detection == "weapon" then
			GameTooltip:AddLine("Weapon buff", 0.7, 0.7, 0.7)
		else
			GameTooltip:AddLine("Totem buff", 0.7, 0.7, 0.7)
		end
		if self.status == "inrange" then
			GameTooltip:AddLine("Status: IN RANGE", 0, 1, 0)
		elseif self.status == "missing" then
			GameTooltip:AddLine("Status: MISSING (you don't have this buff)", 0.7, 0.7, 0.7)
		else
			GameTooltip:AddLine("Status: OUT OF RANGE", 1, 0, 0)
		end
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", function(self)
		GameTooltip:Hide()
	end)

	btn.totemData = totemData
	SP:SPRangeEngineBuild(btn)   -- (WoW: Forever: the game's own answer in a fight, below)
	return btn
end

-- Update SPRange frame with tracked totems
function SP:UpdateSPRangeFrame()
	local frame = self.spRangeFrame
	if not frame then return end

	-- Clear existing buttons
	for _, btn in pairs(frame.totemButtons) do
		btn:Hide()
	end
	frame.totemButtons = {}

	-- Get tracked totems
	local tracked = ShamanPower_RangeTracker.tracked or {}
	local trackedList = {}

	for _, totemData in ipairs(self.TrackableTotems) do
		if tracked[totemData.id] then
			table.insert(trackedList, totemData)
		end
	end

	frame.trackedList = trackedList
	if #trackedList == 0 then
		frame:SetSize(120, 50)
		frame.title:SetText("Totem Range (none)")
		return
	end
	frame.title:SetText("Totem Range")

	-- Create buttons (every tracked totem; the layout below places the ones the show mode allows)
	for i, totemData in ipairs(trackedList) do
		local btn = self:CreateSPRangeTotemButton(frame.iconContainer, totemData, i)
		frame.totemButtons[totemData.id] = btn
	end
	self:LayoutSPRangeButtons()
end

-- Show a Tracked Totem's Icon (Look): "always" (nil), "notmissing", "inrange". A button whose
-- status the mode hides keeps its status reads (UpdateSPRangeStatus) so it can come back.
local function SPRangeShownByMode(btn)
	if SP.sprangeDemoActive then return true end   -- the preview shows every icon
	local mode = SP:SPRangeIconOpt(btn.totemData and btn.totemData.id, "showMode")   -- (3.0.9.2: each icon's own)
	if not mode or mode == "always" then return true end
	local status = btn.status
	if not status or status == "unknown" then return true end   -- (not read yet: shown until it is)
	if mode == "notmissing" then return status ~= "missing" end
	if mode == "inrange" then return status == "inrange" end
	return true
end

-- Place the tracked totems' buttons: the ones the show mode allows, in tracking order, the frame
-- sized to them. Called by UpdateSPRangeFrame and whenever a status change alters that set.
function SP:LayoutSPRangeButtons()
	local frame = self.spRangeFrame
	if not frame or not frame.trackedList then return end
	local shown = {}
	for _, totemData in ipairs(frame.trackedList) do
		local btn = frame.totemButtons[totemData.id]
		if btn then
			if SPRangeShownByMode(btn) then shown[#shown + 1] = btn else btn:Hide() end
		end
	end
	self:SPRangePlace(frame, shown)
	local sig = {}
	for _, btn in ipairs(shown) do sig[#sig + 1] = tostring(btn.totemData and btn.totemData.id) end
	frame.shownSignature = table.concat(sig, ",")
end

-- Check if ANYONE in the group has a specific buff (indicates totem is down somewhere)
-- Optimized: party1-4 works in both party AND raid (refers to subgroup in raids)
-- Match cached aura names or rank IDs on the player and party units
local rangePartyUnits = { "party1", "party2", "party3", "party4" }
function SP:SPRangeAnyoneHasBuff(buffName, buffSpellIDSet)
	if issecretvalue(buffName) then return false end
	if SPCompat.FOREVER then
		if MainlineHasNamedBuff("player", buffName, buffSpellIDSet) then return true end
		if IsInGroup() then
			for _, unit in ipairs(rangePartyUnits) do
				local exists = UnitExists(unit)
				if not issecretvalue(exists) and exists
					and MainlineHasNamedBuff(unit, buffName, buffSpellIDSet) then return true end
			end
		end
		return false
	end
	if not buffName then return false end

	-- Check player first
	for i = 1, 32 do
		local name = UnitBuff("player", i)
		if issecretvalue(name) then return false end
		if not name then break end
		if name == buffName or (buffAliasSets[buffName] and buffAliasSets[buffName][name]) then return true end
	end

	-- Check party/subgroup members (party1-4 works in both party and raid)
	if IsInGroup() then
		for i = 1, 4 do
			local unit = "party" .. i
			if UnitExists(unit) then
				for j = 1, 32 do
					local name = UnitBuff(unit, j)
					if issecretvalue(name) then break end
					if not name then break end
					if name == buffName or (buffAliasSets[buffName] and buffAliasSets[buffName][name]) then return true end
				end
			end
		end
	end

	return false
end

-- Check if anyone has Windfury weapon enchant (special case)
function SP:SPRangeAnyoneHasWindfury()
	-- For Windfury, we can only reliably check our own weapon
	-- But if we have the enchant, the totem is definitely up
	local hasEnchant = self:SPRangeHasWindfuryWeapon()
	if hasEnchant then
		return true
	end

	-- We can't check other players' weapon enchants directly
	-- So we'll have to rely on seeing if melee in the group are proccing it
	-- For now, return false if we don't have it ourselves
	-- This means for Windfury specifically, we can only know if WE are in range
	return false
end

-- Update range status for all tracked totems
function SP:UpdateSPRangeStatus()
	if self.sprangeDemoActive then return end
	local frame = self.spRangeFrame
	if not frame or not frame:IsShown() then return end

	for id, btn in pairs(frame.totemButtons) do
		local totemData = btn.totemData
		local playerHasBuff = self:SPRangeCheckTotem(totemData)

		-- Check if anyone in the group has the buff (totem is down)
		local totemIsDown
		if totemData.detection == "weapon" then
			-- Windfury special case - can only check ourselves
			totemIsDown = playerHasBuff  -- If we have it, it's down. Otherwise unknown.
		else
			totemIsDown = self:SPRangeAnyoneHasBuff(totemData.buffName, totemData.buffSpellIDSet)
		end

		-- In combat on the Mainline family the buff reads above come back empty
		-- because they're blocked, which flipped every totem to MISSING. Our own
		-- totems are measured by distance instead; anything else keeps what this
		-- button showed before the reads went dark.
		if totemData.detection ~= "weapon" and SPCompat and SPCompat.AurasUnreadable and SPCompat.AurasUnreadable() then
			local near = self:SPRangeOwnTotemInRange(totemData)
			if near ~= nil then
				playerHasBuff, totemIsDown = near, true
			elseif btn.status then
				playerHasBuff = (btn.status == "inrange")
				totemIsDown = (btn.status ~= "missing")
			end
		end

		btn.inRange = playerHasBuff
		local blind = totemData.detection ~= "weapon" and SPCompat and SPCompat.AurasUnreadable and SPCompat.AurasUnreadable()

		if playerHasBuff then
			btn.status = "inrange"
		elseif totemIsDown then
			btn.status = "outofrange"   -- the totem is down (someone has the buff) but we don't
		else
			btn.status = "missing"      -- no one has the buff: the totem is not down
		end
		self:SPRangePaint(btn, btn.status)   -- (3.0.9.2: each icon's own look for it)
		if btn.spEngine then self:SPRangeEngineApply(btn, blind) end   -- (10-21: in a fight, the game's answer for the icon)
	end
	-- Show a Tracked Totem's Icon: a status change may hide or bring back a button
	if frame.trackedList then   -- (each icon its own show rule, 3.0.9.2)
		local sig = {}
		for _, totemData in ipairs(frame.trackedList) do
			local btn = frame.totemButtons[totemData.id]
			if btn and SPRangeShownByMode(btn) then sig[#sig + 1] = tostring(totemData.id) end
		end
		if table.concat(sig, ",") ~= (frame.shownSignature or "") then self:LayoutSPRangeButtons() end
	end
end

-- Show SPRange configuration
-- The window lives in ShamanPower_Config (SPRange.lua), which replaces this.
function SP:ShowSPRangeConfig()
	print("|cff0070ddShamanPower|r: The Totem Range Tracker settings need ShamanPower_Config.")
end

-- Update SPRange frame border visibility
function SP:UpdateSPRangeBorder()
	if not self.spRangeFrame then return end

	local hideBorder = SP.opt.rangeTracker.hideBorder

	if hideBorder then
		-- Hide border and background
		self.spRangeFrame:SetBackdrop(nil)
		if self.spRangeFrame.title then
			self.spRangeFrame.title:Hide()
		end
		self:SetSettingsButtonHoverOnly(self.spRangeFrame, self.spRangeFrame.settingsBtn, true)
	else
		-- Show border and background
		SP:ApplyPanelBackdrop(self.spRangeFrame)
		ThemePanel(self.spRangeFrame)
		if self.spRangeFrame.title then
			self.spRangeFrame.title:Show()
		end
		self:SetSettingsButtonHoverOnly(self.spRangeFrame, self.spRangeFrame.settingsBtn, false)
	end
end

-- Update SPRange frame opacity
function SP:UpdateSPRangeOpacity()
	if not self.spRangeFrame then return end
	local opacity = SP.opt.rangeTracker.opacity or 1.0
	self.spRangeFrame:SetAlpha(opacity)
end

-- Update config button visual states
function SP:UpdateSPRangeConfigButtons()
	if not self.spRangeConfigFrame or not self.spRangeConfigFrame.totemButtons then return end

	for id, btn in pairs(self.spRangeConfigFrame.totemButtons) do
		local isTracked = ShamanPower_RangeTracker.tracked[id]
		local c = btn.elementColors

		if isTracked then
			-- Tracked - full color
			btn.icon:SetDesaturated(false)
			btn.icon:SetAlpha(1)
			btn.nameText:SetTextColor(1, 1, 1)
		else
			-- Not tracked - grey
			btn.icon:SetDesaturated(true)
			btn.icon:SetAlpha(0.4)
			btn.nameText:SetTextColor(0.5, 0.5, 0.5)
		end
	end
end

-- Is the overlay on (open counts one waiting for a group, per Show the Overlay)?
-- The settings preview shows this same frame, so while it runs the answer is
-- whether the overlay was up before the preview (and any toggle since): the
-- preview's frame being shown said "on" and the toggle could never switch off.
function SP:SPRangeOverlayOn()
	if self.spRangeManuallyOpened then return true end
	if self.sprangeDemoActive then return self.sprangeRealShown == true end
	return self.spRangeFrame ~= nil and self.spRangeFrame:IsShown() == true
end

-- Toggle SPRange visibility
function SP:ToggleSPRange()
	self:InitSPRange()

	if not self.spRangeFrame then
		self:CreateSPRangeFrame()
	end

	-- While the settings preview runs it owns the frame: the choice is kept, and
	-- UpdateSPRangeVisibility applies it when the preview ends.
	if self:SPRangeOverlayOn() then
		if not self.sprangeDemoActive then self.spRangeFrame:Hide() end
		self.sprangeRealShown = false
		self.spRangeManuallyOpened = false  -- User closed it manually
		ShamanPower_RangeTracker.shown = false
		self:Print("Totem Range Tracker hidden. Type /sprange show to bring it back.")
	else
		self.spRangeManuallyOpened = true  -- User opened it manually
		ShamanPower_RangeTracker.shown = true
		if self:SPRangeAllowedHere() then
			if not self.sprangeDemoActive then self:ShowSPRangeOverlay() end
			self:Print("Totem Range Tracker shown. Click the gear for settings.")
		else
			self:Print("Totem Range Tracker is on. It appears when you are in a group"
				.. ((self.opt.rangeTracker and self.opt.rangeTracker.showWhen == "group") and "" or " with a shaman")
				.. " (Settings > Group Tools > Totem Range Tracker > Show the Overlay).")
		end
	end
end

-- The shamans in your own subgroup, by the name a whisper needs (with the realm
-- for other realms): an instance raid's report goes to them (see below). Read
-- again at every send, so a name still "Unknown" at roster time is picked up.
-- Anniversary only: on WoW: Forever the realm label changes and names can have
-- two parts, so a whisper might not find its target (and the failed whisper's
-- system message would repeat every heartbeat); there the report stays on
-- INSTANCE_CHAT.
local WF_WHISPER = not (SPCompat.FOREVER)
local wfWhisperTargets = {}
local function refreshWhisperTargets()
	wipe(wfWhisperTargets)
	for i = 1, 4 do
		local unit = "party" .. i
		if UnitExists(unit) and select(2, UnitClass(unit)) == "SHAMAN" then
			local name = GetUnitName(unit, true)
			if type(name) == "string" and not (issecretvalue and issecretvalue(name)) and name ~= "" and name ~= UNKNOWNOBJECT then
				wfWhisperTargets[#wfWhisperTargets + 1] = name
			end
		end
	end
end

-- Losing Windfury (walking out of the totem's range) is its weapon enchant
-- running out. Whether or not the client fires an event for that, a one-shot
-- timer checks the moment it should have run out. One timer at a time: while
-- the totem keeps renewing the enchant, it waits again for the new end. An
-- enchant that ends sooner than the timer's wake (a long oil replaced by the
-- totem's short enchant) cancels it and wakes at the new end instead.
local wfExpireAt, wfExpireTimer, wfWakeAt = 0, nil, 0
local function wfExpireCheck()
	local wait = wfExpireAt - GetTime()
	if wait > 0.05 then
		wfWakeAt = wfExpireAt
		wfExpireTimer = C_Timer.NewTimer(wait, wfExpireCheck)
		return
	end
	wfExpireTimer = nil
	if not SP:IsUpdateSubsystemEnabled("wfBroadcast") then return end
	SP:SPRangeHasWindfuryWeapon()   -- on Forever this first read drops SPCompat's cache of an enchant that ran out
	SP:BroadcastWindfuryStatus()
end
local function wfWatchExpiry(mainExp, offExp)
	-- milliseconds left on each hand; the report says "0" only once both are gone
	local ms = 0
	if type(mainExp) == "number" and not (issecretvalue and issecretvalue(mainExp)) then ms = mainExp end
	if type(offExp) == "number" and not (issecretvalue and issecretvalue(offExp)) and offExp > ms then ms = offExp end
	if ms <= 0 then return end
	wfExpireAt = GetTime() + ms / 1000 + 0.2
	-- an earlier end rearms the wake (a re-read of the same enchant can differ by a few ms)
	if wfExpireTimer and wfExpireAt < wfWakeAt - 0.1 then
		wfExpireTimer:Cancel()
		wfExpireTimer = nil
	end
	if not wfExpireTimer then
		wfWakeAt = wfExpireAt
		wfExpireTimer = C_Timer.NewTimer(ms / 1000 + 0.2, wfExpireCheck)
	end
end

-- Broadcast Windfury Totem status to group (same detection as SPRange)
-- NOTE: This sends directly via ChatThrottleLib to bypass the lastMsg check in SendMessage
-- which would block repeated "WFBUFF 1" messages. We need periodic broadcasts so the shaman
-- knows party members are still in range.
-- Sent the moment it changes (weapon enchant events), and as a heartbeat every
-- 6 s (receivers drop a report after 10 s): heartbeat = send even if unchanged.
function SP:BroadcastWindfuryStatus(heartbeat)
	if self.sprangeDemoActive or self:IsOff() then return end   -- off: a check queued before the switch sends nothing
	if not IsInGroup() then return end
	-- Chat lockdown: nothing goes out and nothing is recorded as sent; the report
	-- is owed and goes out as soon as the lock lifts (see wfEvents below).
	if SPK and SPK() == true then self.wfReportOwed = true return false end

	-- Use SAME detection as SPRange - check weapon enchant from GetWeaponEnchantInfo()
	local hasWindfury, mainExp, offExp = self:SPRangeHasWindfuryWeapon()
	if hasWindfury then wfWatchExpiry(mainExp, offExp) end
	local status = hasWindfury and "1" or "0"
	if not heartbeat and self.lastWFStatus == status then return end

	-- Totems only reach your own party, so the report only goes there: the
	-- PARTY channel inside a raid is your own subgroup (4 players, not 39).
	-- An instance-only group has no home party. A 5-player one (LFG dungeon) uses
	-- INSTANCE_CHAT, which is those 5; in an instance raid (a battleground, LFR)
	-- INSTANCE_CHAT reaches everyone there, so on Anniversary the report is
	-- whispered to the shamans in your own subgroup instead.
	local channel = "PARTY"
	if not IsInGroup(LE_PARTY_CATEGORY_HOME) and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
		channel = "INSTANCE_CHAT"
		if WF_WHISPER and IsInRaid() then
			refreshWhisperTargets()
			-- no name known yet: nothing goes out and nothing is recorded as sent,
			-- so the next change or heartbeat tries again
			if #wfWhisperTargets == 0 then return end
			channel = "WHISPER"
		end
	end
	self.lastWFStatus = status
	self.lastWFBroadcast = GetTime()
	self.wfReportOwed = nil

	-- Send directly via ChatThrottleLib (bypass lastMsg check in SendMessage)
	if channel == "WHISPER" then
		for _, name in ipairs(wfWhisperTargets) do
			ChatThrottleLib:SendAddonMessage("NORMAL", self.commPrefix, "WFBUFF " .. status, "WHISPER", name)
		end
	else
		ChatThrottleLib:SendAddonMessage("NORMAL", self.commPrefix, "WFBUFF " .. status, channel)
	end
end

-- Get Windfury range data for a specific player
function SP:GetWindfuryRangeStatus(playerName)
	if not self.WindfuryRangeData then return nil end
	local data = self.WindfuryRangeData[playerName]
	if not data then return nil end

	-- Data expires after 10 seconds
	if (GetTime() - data.timestamp) > 10 then
		self.WindfuryRangeData[playerName] = nil
		return nil
	end

	return data.hasWindfury
end

-- Check if a player is in range of Windfury totem (using reported data)
function SP:IsPlayerInWindfuryRange(playerName)
	-- Check self first
	if playerName == self.player then
		return self:SPRangeHasWindfuryWeapon()
	end

	-- Check reported data from other players
	return self:GetWindfuryRangeStatus(playerName)
end

-- Setup SPRange update timer
function SP:SetupSPRangeUpdater()
	if self.spRangeUpdaterSetup then return end
	self.spRangeUpdaterSetup = true
	self.spRangeBroadcastCounter = 0  -- Track broadcasts (every 2 updates = 2 seconds)

	-- Register SPRange updates with consolidated update system (1fps)
	if not self.updateSystem.subsystems["spRange"] then
		self:RegisterUpdateSubsystem("spRange", 1.0, function()
			-- Only run if SPRange frame is actually visible
			if not SP.spRangeFrame or not SP.spRangeFrame:IsShown() then
				return
			end
			SP:UpdateSPRangeStatus()
			-- (the Windfury report has its own timer: UpdateWindfuryBroadcaster)
		end)
	end
	-- Only enable if SPRange frame exists and is shown
	if self.spRangeFrame and self.spRangeFrame:IsShown() then
		self:EnableUpdateSubsystem("spRange")
	end
end

-- Check if there's a shaman anywhere in the group (not just subgroup)
function SP:SPRangeHasAnyShamanInGroup()
	-- If player is a shaman, don't auto-show SPRange (they have the full UI)
	local _, playerClass = UnitClass("player")
	if playerClass == "SHAMAN" then
		return false
	end

	if IsInRaid() then
		for i = 1, 40 do
			local name, _, _, _, _, class = GetRaidRosterInfo(i)
			if name and class == "SHAMAN" then
				return true
			end
		end
	elseif IsInGroup() then
		for i = 1, 4 do
			if UnitExists("party" .. i) then
				local _, class = UnitClass("party" .. i)
				if class == "SHAMAN" then
					return true
				end
			end
		end
	end

	return false
end

-- The Windfury report runs on its own timer whenever a shaman is in the group,
-- whether or not the overlay is on screen (so closing the overlay, or
-- Windfury-only mode, never stops the shaman seeing your Windfury).
-- Switching ShamanPower off does stop it: then nothing is sent.
-- A shaman in YOUR party (party1-4 are your own subgroup inside a raid): the only
-- shamans whose totems can reach you, so the only ones the report is for.
function SP:ShamanInMyParty()
	if select(2, UnitClass("player")) == "SHAMAN" then return false end
	for i = 1, 4 do
		local unit = "party" .. i
		if UnitExists(unit) and select(2, UnitClass(unit)) == "SHAMAN" then return true end
	end
	return false
end

-- Changes are sent when the weapon enchants change, not found by polling: these
-- events are heard only while a shaman is in your party. A burst is checked once,
-- a moment later (after SPCompat's own handler has dropped its enchant cache).
-- The enchant running out is also caught by its own timer (wfWatchExpiry).
local wfCheckQueued, wfCheckForce = false, false
local function wfCheck()
	local force = wfCheckForce
	wfCheckQueued, wfCheckForce = false, false
	SP:BroadcastWindfuryStatus(force)
end
local wfEvents = CreateFrame("Frame")
if SPCompat and SPCompat.StressRegister then SPCompat.StressRegister(wfEvents, "Totem Range (Windfury report)") end
wfEvents:SetScript("OnEvent", function(_, event, _, state)
	local lifted = event == "ADDON_RESTRICTION_STATE_CHANGED"
	if lifted then
		-- a restriction lifting (state 0; chat lockdown is one): send what the lock
		-- held back, heartbeat included (receivers may have dropped the report)
		if state ~= 0 or not SP.wfReportOwed then return end
		wfCheckForce = true
	end
	if wfCheckQueued then return end
	wfCheckQueued = true
	C_Timer.After(lifted and 1 or 0.1, wfCheck)
end)
local function setWFEvents(on)
	if not on then wfEvents:UnregisterAllEvents() return end
	if wfEvents.RegisterUnitEvent then
		wfEvents:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
	else
		wfEvents:RegisterEvent("UNIT_INVENTORY_CHANGED")
	end
	pcall(wfEvents.RegisterEvent, wfEvents, "WEAPON_ENCHANT_CHANGED")
	pcall(wfEvents.RegisterEvent, wfEvents, "ADDON_RESTRICTION_STATE_CHANGED")
end

function SP:UpdateWindfuryBroadcaster()
	if not self.updateSystem then return end
	if not self.updateSystem.subsystems["wfBroadcast"] then
		-- the heartbeat only: changes go out from the events above
		self:RegisterUpdateSubsystem("wfBroadcast", 6.0, function() SP:BroadcastWindfuryStatus(true) end)
	end
	-- WoW: Forever: the shaman reads Windfury as a party buff, nothing to report
	if not self:IsOff() and self:ShamanInMyParty() and not SPCompat.FOREVER then
		if not self:IsUpdateSubsystemEnabled("wfBroadcast") then
			self:EnableUpdateSubsystem("wfBroadcast")
			setWFEvents(true)
			self:BroadcastWindfuryStatus(true)   -- the shaman sees you at once, not after the first heartbeat
		end
	else
		self:DisableUpdateSubsystem("wfBroadcast")
		setWFEvents(false)
	end
end
do
	local f = CreateFrame("Frame")
	if SPCompat and SPCompat.StressRegister then SPCompat.StressRegister(f, "Totem Range (Windfury report)") end
	f:RegisterEvent("GROUP_ROSTER_UPDATE")
	f:RegisterEvent("PLAYER_ENTERING_WORLD")
	f:SetScript("OnEvent", function()
		SP:UpdateWindfuryBroadcaster()
		SP:UpdateSPRangeVisibility()   -- Show the Overlay: leaving or joining a group
	end)
end

-- Where the overlay may be up (Totem Range Tracker > Show the Overlay): "shaman"
-- (the default) only in a group with a shaman in it, you included; "group" in
-- any group; "always" solo too. It holds for an overlay opened by hand as well:
-- that one steps aside when you leave the group and comes back when you join one.
function SP:SPRangeAllowedHere()
	local mode = self.opt and self.opt.rangeTracker and self.opt.rangeTracker.showWhen or "shaman"
	if mode == "always" then return true end
	if not IsInGroup() then return false end
	if mode == "group" then return true end
	return select(2, UnitClass("player")) == "SHAMAN" or self:SPRangeHasAnyShamanInGroup()
end

function SP:ShowSPRangeOverlay()
	-- Hidden/off modules leave spell changes pending until this active boundary.
	RefreshBuffAliases()
	local pos = ShamanPower_RangeTracker.position
	if pos then
		self.spRangeFrame:ClearAllPoints()
		self.spRangeFrame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x, pos.y)
	end
	self:UpdateSPRangeFrame()
	self:UpdateSPRangeBorder()
	self:UpdateSPRangeOpacity()
	self.spRangeFrame:Show()
end

-- Auto-show/hide SPRange based on group composition
function SP:UpdateSPRangeVisibility()
	if not self.spRangeFrame then return end

	-- Windfury-only mode: no overlay at all (the report keeps running)
	if self.WindfuryOnly and self:WindfuryOnly() then
		if self.spRangeFrame:IsShown() then self.spRangeFrame:Hide() end
		return
	end

	-- Opened by hand (shamans may want to track their own totems): kept open, but
	-- only where Show the Overlay allows it
	if self.spRangeManuallyOpened then
		local want = self:SPRangeAllowedHere()
		if want and not self.spRangeFrame:IsShown() then self:ShowSPRangeOverlay()
		elseif not want and self.spRangeFrame:IsShown() then self.spRangeFrame:Hide() end
		return
	end

	-- ShamanPower switched off: no auto-show (an overlay opened by hand is the player's call)
	local shouldShow = not self:IsOff() and self:SPRangeHasAnyShamanInGroup() and self:SPRangeAllowedHere()

	if shouldShow then
		if not self.spRangeFrame:IsShown() then self:ShowSPRangeOverlay() end
	else
		if self.spRangeFrame:IsShown() then
			self.spRangeFrame:Hide()
		end
	end
end

-- Initialize SPRange on addon load (for non-shamans primarily, but works for all)
function SP:InitializeSPRange()
	self:InitSPRange()
	self:CreateSPRangeFrame()
	self:SetupSPRangeUpdater()

	-- Check if we should auto-show (in group with a shaman)
	self:UpdateSPRangeVisibility()
end

-- Register /sprange slash command
SLASH_SPRANGE1 = "/sprange"
SlashCmdList["SPRANGE"] = function(msg)
	msg = msg:lower():trim()

	if msg == "toggle" then
		-- Toggle the overlay visibility
		SP:ToggleSPRange()
	elseif msg == "show" or msg == "hide" then
		-- only flip it when it is not already that way (show never hides, hide never shows)
		local shown = SP:SPRangeOverlayOn()
		if (msg == "show") ~= shown then
			SP:ToggleSPRange()
		else
			SP:Print(shown and "Totem Range Tracker is already shown." or "Totem Range Tracker is already hidden.")
		end
	else
		-- Default: show the config menu
		SP:InitSPRange()
		if not SP.spRangeFrame then
			SP:CreateSPRangeFrame()
		end
		SP:ShowSPRangeConfig()
	end
end

-- ============================================================================
-- Setup Wizard preview: fill the range overlay with sample totems (no group)
-- ============================================================================
function SP:SPRangeDemo(on)
	if on then
		local frame = self.spRangeFrame or self:CreateSPRangeFrame()
		if not frame then return end
		if not self.opt or not self.opt.rangeTracker then return end
		if frame.settingsBtn then frame.settingsBtn:Hide() end
		-- the overlay's own state before the preview takes the frame (SPRangeOverlayOn)
		if not self.sprangeDemoActive then self.sprangeRealShown = frame:IsShown() == true end
		self:InitSPRange()

		-- Style one button from a fake status (the same painter as UpdateSPRangeStatus).
		local function style(btn, status)
			self:SPRangePaint(btn, status)
			btn.status = status; btn.inRange = (status == "inrange")
		end

		-- (Re)build the frame from the user's tracked set. Called on every
		-- option change, so keep the per-totem sim state across rebuilds.
		local d = self.sprangeDemo or { states = {}, tick = 0 }
		self.sprangeDemo = d
		local function build()
			for _, btn in pairs(frame.totemButtons) do btn:Hide() end
			frame.totemButtons = {}
			local list = {}
			local tracked = ShamanPower_RangeTracker and ShamanPower_RangeTracker.tracked or {}
			for _, t in ipairs(self.TrackableTotems) do
				if tracked[t.id] then list[#list + 1] = t end
			end
			d.list = list
			local n = #list
			if frame.title then frame.title:SetText(n == 0 and "Totem Range (pick totems)" or "Totem Range") end
			local shown = {}
			for i, t in ipairs(list) do
				local btn = self:CreateSPRangeTotemButton(frame.iconContainer, t, i)
				d.states[t.id] = d.states[t.id] or ((i % 3 == 0) and "outofrange" or "inrange")
				style(btn, d.states[t.id])
				frame.totemButtons[t.id] = btn
				shown[#shown + 1] = btn
			end
			if n == 0 then frame:SetSize(150, 50) else self:SPRangePlace(frame, shown) end   -- (each its own size, 3.0.9.2)
			self:UpdateSPRangeBorder()
			self:UpdateSPRangeOpacity()
			frame:Show()
		end
		d.build = build
		build()

		if not self.sprangeDemoActive then
			self.sprangeDemoActive = true
			-- Sim: every couple of seconds one totem changes state, as if you
			-- walked around (or its shaman stopped dropping it).
			if self.sprangeDemoTicker then self.sprangeDemoTicker:Cancel() end
			self.sprangeDemoTicker = C_Timer.NewTicker(2.2, function()
				if not self.sprangeDemoActive or not d.list or #d.list == 0 then return end
				d.tick = d.tick + 1
				local t = d.list[(d.tick % #d.list) + 1]
				local cur = d.states[t.id] or "inrange"
				local nxt = (cur == "inrange") and "outofrange" or (cur == "outofrange" and (d.tick % 5 == 0) and "missing") or "inrange"
				d.states[t.id] = nxt
				local btn = frame.totemButtons[t.id]
				if btn then style(btn, nxt) end
				local short = self.TrackableTotemShortNames[t.id] or t.name
				self.sprangeDemoStatus =
					(nxt == "outofrange" and ("You walked out of range of the shaman's " .. t.name))
					or (nxt == "missing" and ("Nobody has " .. t.name .. " down right now"))
					or ("Back in range of " .. t.name)
			end)
		end
	else
		self.sprangeDemoActive = false
		if self.sprangeDemoTicker then self.sprangeDemoTicker:Cancel(); self.sprangeDemoTicker = nil end
		self.sprangeDemo = nil
		self.sprangeDemoStatus = nil
		if self.spRangeFrame and self.spRangeFrame.settingsBtn then self.spRangeFrame.settingsBtn:Show() end
		-- Clear sample data and let real data take over
		self:UpdateSPRangeFrame()
		self:UpdateSPRangeStatus()
		self:UpdateSPRangeVisibility()
	end
end

-- A theme change (Appearance > Themes): the overlay panel takes the new colours
-- now (nothing here is protected, so combat does not matter)
if SP.OnThemeChanged then
	SP:OnThemeChanged(function()
		local frame = SP.spRangeFrame
		if frame and not (SP.opt and SP.opt.rangeTracker and SP.opt.rangeTracker.hideBorder) then ThemePanel(frame, true) end
	end)
end

-- Register the range overlay with the setup wizard preview harness
if ShamanPower.RegisterPreview then
	ShamanPower:RegisterPreview("sprange", { frame = "ShamanPowerRangeFrame", demo = "SP:SPRangeDemo", pad = 24 })
end

-- Enable ShamanPower switched: off hides the overlay (one opened by hand too) and
-- stops the Windfury report; on brings both back as the group and settings say.
SP:OnOnOff(function(off)
	local frame = SP.spRangeFrame
	if frame then
		if off then
			frame:Hide()
		elseif SP.spRangeManuallyOpened then
			frame:Show()   -- opened by hand before the switch
		end
		SP:UpdateSPRangeVisibility()
	end
	SP:UpdateWindfuryBroadcaster()
end)
