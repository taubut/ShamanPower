-- ============================================================================
-- ShamanPower ES Tracker Module
-- Track Earth Shields cast by OTHER shamans in your raid/party
-- ============================================================================

-- "First Surname" on WoW: Forever (SPCompat.UnitName); other clients unchanged
local UnitName = (SPCompat and SPCompat.UnitName) or UnitName
local SP = ShamanPower
if not SP then return end
-- Loads for every class: raid leaders and healers track the shamans' Earth Shields.

-- Earth Shield is not an obtainable spell on the Mainline/Forever line. The
-- spell data ships (974 and 408514 both resolve by name) but neither carries a
-- trainer entry or a talent node on build 1.60.1, so no shaman can learn or
-- cast it and there is nothing here to track.
-- Bail before creating a single frame, registering an event or touching the
-- saved variable. The core defines no-op stubs for every ES Tracker entry
-- point, and the setup tour hides its step while ESTrackerLoaded is unset, so
-- nothing downstream needs to know.
-- If Earth Shield is ever turned on, delete this block.
if SP.ESTrackerUnavailable then return end

-- Mark module as loaded
SP.ESTrackerLoaded = true

-- ============================================================================
-- Raid Earth Shield Tracker: Shows all Earth Shields in raid/party
-- ============================================================================

SP.earthShields = {}  -- { [targetGUID] = { target, caster, charges, expiration } }

-- Earth Shield spell ID (for icon)
SP.EarthShieldSpellID = 32594  -- Rank 1, we just need the icon

-- Initialize Earth Shield tracker settings
function SP:InitESTracker()
	-- Ensure profile table exists
	self:EnsureProfileTable("esTracker")

	-- Migrate from old global variable if it exists
	if ShamanPower_ESTracker and next(ShamanPower_ESTracker) then
		-- Copy old settings to profile if profile is empty/default
		if SP.opt.esTracker.enabled == false and SP.opt.esTracker.enabled then
			SP.opt.esTracker.enabled = SP.opt.esTracker.enabled
		end
		if SP.opt.esTracker.position then
			self.opt.esTracker.position = SP.opt.esTracker.position
		end
		if SP.opt.esTracker.opacity and SP.opt.esTracker.opacity ~= 1.0 then
			self.opt.esTracker.opacity = SP.opt.esTracker.opacity
		end
		if SP.opt.esTracker.iconSize and SP.opt.esTracker.iconSize ~= 40 then
			self.opt.esTracker.iconSize = SP.opt.esTracker.iconSize
		end
		if SP.opt.esTracker.vertical then
			self.opt.esTracker.vertical = SP.opt.esTracker.vertical
		end
		if SP.opt.esTracker.hideNames then
			self.opt.esTracker.hideNames = SP.opt.esTracker.hideNames
		end
		if SP.opt.esTracker.hideBorder then
			self.opt.esTracker.hideBorder = SP.opt.esTracker.hideBorder
		end
		if SP.opt.esTracker.hideCharges then
			self.opt.esTracker.hideCharges = SP.opt.esTracker.hideCharges
		end
		-- Clear the old global after migration
		ShamanPower_ESTracker = nil
	end
end

-- Create the Earth Shield tracker frame
function SP:CreateESTrackerFrame()
	if self.esTrackerFrame then return self.esTrackerFrame end

	local frame = CreateFrame("Frame", "ShamanPowerESTrackerFrame", UIParent, "BackdropTemplate")
	frame:SetSize(150, 60)
	frame:SetPoint("CENTER", UIParent, "CENTER", 200, 0)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:SetClampedToScreen(true)
	frame:SetFrameStrata("MEDIUM")

	-- Backdrop
	frame:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 }
	})
	frame:SetBackdropColor(0, 0, 0, 0.8)
	frame:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)

	-- Title: the other module titles' look, and it follows the Fonts settings
	local title = frame:CreateFontString(nil, "OVERLAY")
	SP:SetSPFont(title, "labels", 11, "", STANDARD_TEXT_FONT)
	title:SetShadowOffset(1, -1)
	title:SetShadowColor(0, 0, 0, 0.8)
	title:SetTextColor(SP:SPColor("text"))
	title:SetPoint("TOP", frame, "TOP", 0, -6)
	title:SetText("Earth Shields")
	frame.title = title

	-- Container for ES icons
	local iconContainer = CreateFrame("Frame", nil, frame)
	iconContainer:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -20)
	iconContainer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 8)
	frame.iconContainer = iconContainer

	-- Drag to move (ALT+drag when borderless, normal drag when bordered)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self)
		if not self:IsMovable() then return end
		if SP.opt.esTracker.hideBorder and not IsAltKeyDown() then
			return
		end
		self:StartMoving()
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, _, x, y = self:GetPoint()
		-- Set individual fields for better AceDB persistence
		if not SP.opt.esTracker.position then
			SP.opt.esTracker.position = {}
		end
		SP.opt.esTracker.position.point = point
		SP.opt.esTracker.position.x = x
		SP.opt.esTracker.position.y = y
	end)

	-- Tooltip
	frame:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine("Earth Shield Tracker", 0.4, 0.8, 0.4)
		GameTooltip:AddLine(" ")
		if SP.opt.esTracker.hideBorder then
			GameTooltip:AddLine("ALT+drag to move", 0.7, 0.7, 0.7)
		else
			GameTooltip:AddLine("Drag to move", 0.7, 0.7, 0.7)
		end
		GameTooltip:Show()
	end)
	frame:SetScript("OnLeave", function(self)
		GameTooltip:Hide()
	end)

	frame.esButtons = {}
	frame:Hide()

	-- Enable/disable ES tracker events based on visibility
	frame:HookScript("OnShow", function()
		SP:EnableESTrackerEvents()
	end)
	frame:HookScript("OnHide", function()
		SP:DisableESTrackerEvents()
	end)

	self.esTrackerFrame = frame
	return frame
end

-- Get class color for a unit
function SP:GetClassColorForUnit(unit)
	if not unit or not UnitExists(unit) then
		return 1, 1, 1
	end
	local _, class = UnitClass(unit)
	if class and RAID_CLASS_COLORS[class] then
		local color = RAID_CLASS_COLORS[class]
		return color.r, color.g, color.b
	end
	return 1, 1, 1
end

-- Get class color by class name
function SP:GetClassColor(class)
	if class and RAID_CLASS_COLORS[class] then
		local color = RAID_CLASS_COLORS[class]
		return color.r, color.g, color.b
	end
	return 1, 1, 1
end

-- Create an Earth Shield button for the tracker
-- Rows are pooled (one frame per slot, reused between updates) so a row can
-- own an engine aura container: on restricted clients the charge count is
-- drawn by the engine from the carrier's unit while auras are secret.
local function esTrackerAuraIDs()
	return ShamanPower.EarthShieldAuraIDs or { 974, 32593, 32594, 383648 }
end

local function buildESRowContainer(btn)
	if not (SPCompat and SPCompat.secretsRegime) then return nil end
	if C_AddOns and C_AddOns.LoadAddOn then pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer") end
	local ok, container = pcall(CreateFrame, "AuraContainer", nil, btn, "CustomAuraContainerTemplate")
	if not ok or not container then return nil end
	container:SetAllPoints(btn)
	container:SetFrameLevel(btn:GetFrameLevel() + 3)
	local idMap = {}
	for _, id in ipairs(esTrackerAuraIDs()) do idMap[id] = true end
	pcall(function()
		container:AddAuraSlot("es", "HELPFUL", {   -- any shaman's Earth Shield on this unit
			candidateFilters = { includeSpellIDs = idMap },
			initializeFrame = function(button)
				button:ClearAllPoints()
				button:SetAllPoints(btn)
				if button.SetMouseClickEnabled then pcall(button.SetMouseClickEnabled, button, false) end
				if button.SetMouseMotionEnabled then pcall(button.SetMouseMotionEnabled, button, false) end
				local carrier = CreateFrame("Frame", nil, button)
				carrier:SetAllPoints(button)
				local count = carrier:CreateFontString(nil, "OVERLAY")
				SP:SetSPFont(count, "labels", 12, "OUTLINE")
				count:SetPoint("TOPRIGHT", button, "TOPRIGHT", -2, -2)
				count:SetTextColor(0.4, 1, 0.4)
				pcall(button.SetApplicationCount, button, count, {})
			end,
		})
	end)
	pcall(container.SetUnit, container, "none")
	container:Hide()
	return container
end

function SP:CreateESTrackerButton(parent, esData, index)
	local iconSize = SP.opt.esTracker.iconSize or 40
	local btn = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	btn:SetSize(iconSize, iconSize)

	-- Background
	btn:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Buttons\\WHITE8X8",
		tile = true, tileSize = 16, edgeSize = 2,
		insets = { left = 2, right = 2, top = 2, bottom = 2 }
	})
	btn:SetBackdropColor(0, 0, 0, 0.7)
	btn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

	-- Icon (Earth Shield icon)
	local icon = btn:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("TOPLEFT", 3, -3)
	icon:SetPoint("BOTTOMRIGHT", -3, 3)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local _, _, spellIcon = GetSpellInfo(self.EarthShieldSpellID)
	icon:SetTexture(spellIcon or "Interface\\Icons\\Spell_Nature_SkinofEarth")
	btn.icon = icon

	-- Target name (inside the icon area, at bottom)
	local targetText = btn:CreateFontString(nil, "OVERLAY")
	SP:SetSPFont(targetText, "labels", 9, "OUTLINE")
	targetText:SetPoint("BOTTOM", btn, "BOTTOM", 0, 5)
	targetText:SetTextColor(1, 1, 1)
	btn.targetText = targetText

	-- Charges (top right corner)
	local chargesText = btn:CreateFontString(nil, "OVERLAY")
	SP:SetSPFont(chargesText, "labels", 12, "OUTLINE")
	chargesText:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -2, -2)
	chargesText:SetTextColor(0.4, 1, 0.4)
	btn.chargesText = chargesText

	-- Caster name (below the icon)
	local casterText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	SP:SetSPFont(casterText, "labels", 8, "OUTLINE")
	casterText:SetPoint("TOP", btn, "BOTTOM", 0, -1)
	btn.casterText = casterText

	-- Tooltip (reads the row's current data)
	btn:EnableMouse(true)
	btn:SetScript("OnEnter", function(self)
		local d = self.esData or {}
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Earth Shield", 0.4, 0.8, 0.4)
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Target: " .. (d.targetName or "Unknown"), 1, 1, 1)
		GameTooltip:AddLine("Caster: " .. (d.casterName or "Unknown"), 1, 0.82, 0)
		GameTooltip:AddLine("Charges: " .. (d.charges or "?"), 0.4, 1, 0.4)
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", function(self)
		GameTooltip:Hide()
	end)

	btn.engine = buildESRowContainer(btn)
	self:FillESTrackerButton(btn, esData)
	return btn
end

-- Put an entry's data on a (possibly reused) row
function SP:FillESTrackerButton(btn, esData)
	btn.esData = esData
	btn.targetText:SetText(esData.targetName or "?")
	btn.chargesText:SetText(esData.charges or "?")
	if SP.opt.esTracker.hideCharges then btn.chargesText:Hide() else btn.chargesText:Show() end
	btn.casterText:SetText(esData.casterName or "?")
	local r, g, b = self:GetClassColor(esData.casterClass)
	btn.casterText:SetTextColor(r, g, b)
	if SP.opt.esTracker.hideNames then btn.casterText:Hide() else btn.casterText:Show() end
	if btn.engine and esData.unit and btn.engineUnit ~= esData.unit then
		btn.engineUnit = esData.unit
		pcall(btn.engine.SetUnit, btn.engine, esData.unit)
		pcall(btn.engine.UpdateAllAuras, btn.engine)
	end
end

-- Restricted client: rows keep their last readable data; the engine draws the
-- live count while secret, the addon's count while readable
function SP:ESTrackerSetRestricted(restricted)
	local frame = self.esTrackerFrame
	if not frame or not frame.esButtons then return end
	for _, btn in ipairs(frame.esButtons) do
		if btn.engine then
			if btn.engine:IsShown() ~= restricted then btn.engine:SetShown(restricted) end
			if restricted then
				btn.chargesText:SetText("")
			elseif btn.esData and not SP.opt.esTracker.hideCharges then
				btn.chargesText:SetText(btn.esData.charges or "?")
			end
		end
	end
end

-- Update the Earth Shield tracker display
-- (the list and the sort are reused: a raid redraws this several times a second)
local esList = {}
local function byCasterName(a, b)
	return (a.casterName or "") < (b.casterName or "")
end

function SP:UpdateESTrackerFrame()
	local frame = self.esTrackerFrame
	if not frame then return end

	-- Hide current rows; they are reused from the pool below
	frame.esButtonPool = frame.esButtonPool or {}
	for _, btn in pairs(frame.esButtons) do
		btn:Hide()
	end
	wipe(frame.esButtons)

	-- Get all tracked Earth Shields
	wipe(esList)
	for _, esData in pairs(self.earthShields) do
		esList[#esList + 1] = esData
	end

	-- Sort by caster name for consistency
	table.sort(esList, byCasterName)

	if #esList == 0 then
		frame:SetSize(120, 50)
		frame.title:SetText("Earth Shields (none)")
		return
	end

	-- Calculate frame size
	local buttonSize = SP.opt.esTracker.iconSize or 40
	local padding = 6
	local numButtons = #esList
	local nameSpace = SP.opt.esTracker.hideNames and 0 or 14
	local isVertical = SP.opt.esTracker.vertical

	local width, height
	if isVertical then
		width = buttonSize + 24 + nameSpace
		height = (buttonSize * numButtons) + (padding * (numButtons - 1)) + 28 + nameSpace
	else
		local buttonsWidth = (buttonSize * numButtons) + (padding * (numButtons - 1))
		width = buttonsWidth + 24
		height = buttonSize + 26 + nameSpace
	end

	frame:SetSize(math.max(100, width), height)
	frame.title:SetText("Earth Shields")

	-- Rows from the pool (created once, refilled each update)
	for i, esData in ipairs(esList) do
		local btn = frame.esButtonPool[i]
		if btn and (btn:GetWidth() ~= buttonSize) then
			btn:SetSize(buttonSize, buttonSize)
		end
		if btn then
			self:FillESTrackerButton(btn, esData)
		else
			btn = self:CreateESTrackerButton(frame.iconContainer, esData, i)
			frame.esButtonPool[i] = btn
		end
		btn:ClearAllPoints()

		if isVertical then
			local startY = -20
			btn:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, startY - (i - 1) * (buttonSize + padding + nameSpace))
		else
			local buttonsWidth = (buttonSize * numButtons) + (padding * (numButtons - 1))
			local startX = (frame:GetWidth() - buttonsWidth) / 2
			btn:SetPoint("TOPLEFT", frame, "TOPLEFT", startX + (i - 1) * (buttonSize + padding), -20)
		end

		btn:Show()
		table.insert(frame.esButtons, btn)
	end
	self:ESTrackerSetRestricted(false)

	-- Apply opacity
	frame:SetAlpha(SP.opt.esTracker.opacity or 1.0)
end

-- Setup-wizard preview: fill the tracker with a believable raid's worth of
-- Earth Shields (three shamans, three targets) and animate charges being
-- consumed and shields dropping off / being re-applied, all through the
-- tracker's real render path.
function SP:ESTrackerDemo(on)
	if on then
		if not (self.opt and self.opt.esTracker) then
			self:InitESTracker()
		end
		if not self.esTrackerFrame then
			self:CreateESTrackerFrame()
		end
		local frame = self.esTrackerFrame
		if not frame then return end

		-- Re-entrant: the wizard re-fits the preview on option changes; keep
		-- the running simulation instead of resetting it.
		if self.esTrackerDemoActive then
			self:UpdateESTrackerBorder()
			self:UpdateESTrackerFrame()
			frame:Show()
			return
		end
		self.esTrackerDemoActive = true

		local sample = {
			{ guid = "Player-Demo-ES-1", target = "Tank",    caster = "Srumar",   charges = 6 },
			{ guid = "Player-Demo-ES-2", target = "Offtank", caster = "Nazgrel",  charges = 4 },
			{ guid = "Player-Demo-ES-3", target = "Priest",  caster = "Drakthul", charges = 2 },
		}
		self.earthShields = {}
		for _, s in ipairs(sample) do
			self.earthShields[s.guid] = {
				targetGUID = s.guid, targetName = s.target,
				casterName = s.caster, casterClass = "SHAMAN",
				charges = s.charges, expirationTime = 0, icon = nil,
			}
		end

		-- Simulation: every tick one shield absorbs a hit; at 0 it drops off,
		-- and a couple of ticks later its shaman re-applies it at 6 charges.
		local tick, gone = 0, {}
		if self.esTrackerDemoTicker then self.esTrackerDemoTicker:Cancel() end
		self.esTrackerDemoTicker = C_Timer.NewTicker(1.4, function()
			if not self.esTrackerDemoActive then return end
			tick = tick + 1
			-- re-apply anything that has been gone long enough
			for guid, info in pairs(gone) do
				if tick - info.at >= 3 then
					self.earthShields[guid] = info.data
					info.data.charges = 6
					gone[guid] = nil
				end
			end
			-- consume a charge on a rotating shield
			local live = {}
			for guid, d in pairs(self.earthShields) do live[#live + 1] = guid end
			table.sort(live)
			if #live > 0 then
				local guid = live[(tick % #live) + 1]
				local d = self.earthShields[guid]
				d.charges = (d.charges or 1) - 1
				if d.charges <= 0 then
					gone[guid] = { at = tick, data = d }
					self.earthShields[guid] = nil
				end
			end
			self:UpdateESTrackerFrame()
		end)

		self:UpdateESTrackerBorder()
		self:UpdateESTrackerFrame()
		frame:Show()
	else
		self.esTrackerDemoActive = false
		if self.esTrackerDemoTicker then self.esTrackerDemoTicker:Cancel(); self.esTrackerDemoTicker = nil end
		self.earthShields = {}

		local frame = self.esTrackerFrame
		if frame then
			self:UpdateESTrackerBorder()
			if SP.opt and SP.opt.esTracker and SP.opt.esTracker.enabled and frame:IsShown() then
				-- Real tracker is enabled: let live auras repopulate it
				self:ScanEarthShields()
			else
				self:UpdateESTrackerFrame()
				frame:Hide()
			end
		end
	end
end

-- Scan for Earth Shields in the raid/party
-- One unit's Earth Shield, or nil. Classic TBC UnitBuff returns:
-- name, icon, count, debuffType, duration, expirationTime, caster
-- `entry` is an old row to refill instead of building a new table (aura events
-- arrive many times a second in a raid).
local function scanUnitES(unit, entry)
	if not UnitExists(unit) then return nil end
	local name, icon, count, expirationTime, caster
	for i = 1, 40 do
		local buffName, buffIcon, buffCount, _, _, buffExpiration, buffCaster = UnitBuff(unit, i)
		if not buffName then break end
		if buffName == "Earth Shield" then
			name, icon, count, expirationTime, caster = buffName, buffIcon, buffCount, buffExpiration, buffCaster
			break
		end
	end
	if not name then return nil end
	local casterName = "Unknown"
	local casterClass = nil
	-- Get caster info - need to check if caster unit is valid
	if caster and UnitExists(caster) then
		casterName = UnitName(caster) or "Unknown"
		local _, cls = UnitClass(caster)
		casterClass = cls
	end
	entry = entry or {}
	entry.targetGUID = UnitGUID(unit)
	entry.unit = unit
	entry.targetName = UnitName(unit)
	entry.casterName = casterName
	entry.casterClass = casterClass
	entry.charges = count or 0
	entry.expirationTime = expirationTime
	entry.icon = icon
	return entry
end

-- Restricted client: aura reads return nothing while secret, which would read
-- as every shield having fallen off. Keep the last readable picture instead;
-- SPCompat re-runs the scan once restrictions clear.
local function scanBlocked(self)
	if SPCompat and SPCompat.secretsRegime and SPCompat.AnyRestrictionActive and SPCompat.AnyRestrictionActive() then
		self:ESTrackerSetRestricted(true)
		return true
	end
	-- Setup-wizard preview owns the data while active; don't clobber it
	return self.esTrackerDemoActive and true or false
end

-- Group unit tokens the tracker reads: raid1-40 in a raid, player + party1-4
-- otherwise. Nameplates, target, focus, pets and the other mode's tokens are
-- the same players under another name (or not group members at all).
local RAID_TOKENS, PARTY_TOKENS, SOLO_TOKENS = {}, { "player", "party1", "party2", "party3", "party4" }, { "player" }
for i = 1, 40 do RAID_TOKENS[i] = "raid" .. i end
local RAID_UNIT, PARTY_UNIT = {}, { player = true }
for i = 1, 40 do RAID_UNIT["raid" .. i] = true end
for i = 1, 4 do PARTY_UNIT["party" .. i] = true end

-- Rows no longer shown wait here to be refilled by the next shield found
local spareEntries = {}

-- Full scan: when the tracker opens and once a roster change settles. Between
-- those, each member's own UNIT_AURA re-reads just that member.
function SP:ScanEarthShields()
	if scanBlocked(self) then return end

	local shields = self.earthShields
	for guid, d in pairs(shields) do
		spareEntries[#spareEntries + 1] = d
		shields[guid] = nil
	end

	local units = IsInRaid() and RAID_TOKENS or (IsInGroup() and PARTY_TOKENS or SOLO_TOKENS)
	for i = 1, #units do
		local spare = spareEntries[#spareEntries]
		local entry = scanUnitES(units[i], spare)
		if entry then
			if entry == spare then spareEntries[#spareEntries] = nil end
			shields[entry.targetGUID] = entry
		end
	end

	self:UpdateESTrackerFrame()
end

-- UNIT_AURA for one group member: re-read just that unit and redraw at most
-- 4 times a second, and only when what the tracker shows changed (a raid fires
-- hundreds of aura events a second; each used to rescan all 40 members).
local redrawPending = false
local function redrawNow()
	redrawPending = false
	if SP.esTrackerFrame and SP.esTrackerFrame:IsShown() then SP:UpdateESTrackerFrame() end
end
local function redrawSoon()
	if redrawPending then return end
	redrawPending = true
	C_Timer.After(0.25, redrawNow)
end

function SP:ScanEarthShieldUnit(unit)
	if type(unit) ~= "string" or (issecretvalue and issecretvalue(unit)) then return end
	if not (IsInRaid() and RAID_UNIT[unit] or (not IsInRaid() and PARTY_UNIT[unit])) then return end
	if scanBlocked(self) then return end
	if not self.earthShields then self:ScanEarthShields() return end
	-- drop what this unit (or this player under its GUID) had, then re-read it
	-- into the same row
	local shields = self.earthShields
	local guid = UnitGUID(unit)
	local old, dropped = nil, 0
	for g, d in pairs(shields) do
		if d.unit == unit or g == guid then
			shields[g] = nil
			dropped = dropped + 1
			old = old or d
		end
	end
	local oldGUID, oldCharges, oldCaster, oldName
	if old then oldGUID, oldCharges, oldCaster, oldName = old.targetGUID, old.charges, old.casterName, old.targetName end
	local entry = scanUnitES(unit, old)
	if entry then
		shields[entry.targetGUID] = entry
	elseif old then
		spareEntries[#spareEntries + 1] = old
	end
	if dropped > 1 or (entry == nil) ~= (old == nil) or (entry and (entry.targetGUID ~= oldGUID
		or entry.charges ~= oldCharges or entry.casterName ~= oldCaster or entry.targetName ~= oldName)) then
		redrawSoon()
	end
end

-- Update Earth Shield tracker border visibility
function SP:UpdateESTrackerBorder()
	local frame = self.esTrackerFrame
	if not frame then return end

	if SP.opt.esTracker.hideBorder then
		frame:SetBackdrop(nil)
		if frame.title then frame.title:Hide() end
	else
		frame:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 }
		})
		frame:SetBackdropColor(0, 0, 0, 0.8)
		frame:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
		if frame.title then frame.title:Show() end
	end
end

-- Update Earth Shield tracker opacity
function SP:UpdateESTrackerOpacity()
	local frame = self.esTrackerFrame
	if frame then
		frame:SetAlpha(SP.opt.esTracker.opacity or 1.0)
	end
end

-- Set the Earth Shield tracker on or off explicitly (settings and the tour use
-- this; flipping on IsShown() went backwards while a preview had the frame shown).
function SP:SetESTrackerEnabled(on)
	self:InitESTracker()
	if not self.esTrackerFrame then self:CreateESTrackerFrame() end
	SP.opt.esTracker.enabled = on and true or false
	if self.esTrackerDemoActive then return end   -- a preview owns the frame; its restore follows the setting
	if on then
		local pos = SP.opt.esTracker.position
		if pos then
			self.esTrackerFrame:ClearAllPoints()
			self.esTrackerFrame:SetPoint(pos.point, UIParent, pos.point, pos.x, pos.y)
		end
		self:UpdateESTrackerBorder()
		self:ScanEarthShields()
		self.esTrackerFrame:Show()
		self:EnableESTrackerEvents()
	else
		self.esTrackerFrame:Hide()
		self:DisableESTrackerEvents()
	end
end

-- Toggle Earth Shield tracker visibility (the Open button, /sp es)
function SP:ToggleESTracker()
	self:InitESTracker()
	if not self.esTrackerFrame then
		self:CreateESTrackerFrame()
	end

	if self.esTrackerFrame:IsShown() then
		self.esTrackerFrame:Hide()
		self:DisableESTrackerEvents()  -- Stop UNIT_AURA tracking
		SP.opt.esTracker.enabled = false
	else
		-- Restore saved position
		local pos = SP.opt.esTracker.position
		if pos then
			self.esTrackerFrame:ClearAllPoints()
			self.esTrackerFrame:SetPoint(pos.point, UIParent, pos.point, pos.x, pos.y)
		end
		self:UpdateESTrackerBorder()
		self:ScanEarthShields()
		self.esTrackerFrame:Show()
		self:EnableESTrackerEvents()  -- Start UNIT_AURA tracking
		SP.opt.esTracker.enabled = true
	end
end

-- UNIT_AURA only for the group's own tokens (raid1-40 in a raid, player +
-- party1-4 otherwise). Registered with RegisterEvent it arrived for every
-- nameplate, target and pet too, just to be ignored. RegisterUnitEvent takes up
-- to two units per frame, so the tokens are spread over small frames.
local auraFrames = {}
local function onGroupAura(_, _, unit)
	if SP.esTrackerFrame and SP.esTrackerFrame:IsShown() then SP:ScanEarthShieldUnit(unit) end
end
local function setAuraFilter(on)
	local units = on and (IsInRaid() and RAID_TOKENS or PARTY_TOKENS) or nil
	local need = units and math.ceil(#units / 2) or 0
	for i = 1, math.max(need, #auraFrames) do
		local f = auraFrames[i]
		if i <= need and not f then
			f = CreateFrame("Frame")
			f:SetScript("OnEvent", onGroupAura)
			if SPCompat and SPCompat.StressRegister then SPCompat.StressRegister(f, "ES Tracker") end
			auraFrames[i] = f
		end
		f:UnregisterEvent("UNIT_AURA")
		if i <= need then
			local a, b = units[2 * i - 1], units[2 * i]
			if f.RegisterUnitEvent then
				if b then f:RegisterUnitEvent("UNIT_AURA", a, b) else f:RegisterUnitEvent("UNIT_AURA", a) end
			elseif i == 1 then
				f:RegisterEvent("UNIT_AURA")   -- no unit filters on this client: one frame hears all (the handler checks the unit)
			end
		end
	end
end

-- A raid forming fires dozens of GROUP_ROSTER_UPDATEs: re-point the aura
-- filter (raid indexes shift, party <-> raid) and rescan once, 0.3 s after the
-- last. One timer at a time: when it fires with newer events behind it, it
-- waits again for the rest of their 0.3 s (a storm that never pauses still
-- rescans every 5 s).
local rosterQueued, rosterFirst, rosterLast = false, 0, 0
local function rosterSettled()
	local now = GetTime()
	local wait = rosterLast + 0.3 - now
	if wait > 0.01 and now - rosterFirst < 5 then C_Timer.After(wait, rosterSettled) return end
	rosterQueued = false
	if not SP.esTrackerEventsEnabled then return end
	setAuraFilter(true)
	if SP.esTrackerFrame and SP.esTrackerFrame:IsShown() then SP:ScanEarthShields() end
end

-- Setup Earth Shield tracker events (no OnUpdate or timer: roster and aura
-- events drive every update)
function SP:SetupESTrackerUpdater()
	if self.esTrackerUpdateFrame then return end

	-- Don't register UNIT_AURA here - EnableESTrackerEvents will do it
	local eventFrame = CreateFrame("Frame")
	if SPCompat and SPCompat.StressRegister then SPCompat.StressRegister(eventFrame, "ES Tracker") end
	eventFrame:RegisterEvent("GROUP_LEFT")
	eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
	eventFrame:SetScript("OnEvent", function(self, event)
		if event == "GROUP_LEFT" then
			SP:ClearESTracker()
		elseif event == "GROUP_ROSTER_UPDATE" then
			if not IsInGroup() then
				SP:ClearESTracker()
			end
		end
		if SP.esTrackerEventsEnabled then
			rosterLast = GetTime()
			if not rosterQueued then
				rosterQueued, rosterFirst = true, rosterLast
				C_Timer.After(0.3, rosterSettled)
			end
		end
	end)

	self.esTrackerUpdateFrame = eventFrame
end

-- Enable ES tracker events (called when tracker is shown)
function SP:EnableESTrackerEvents()
	if self.esTrackerUpdateFrame and not self.esTrackerEventsEnabled then
		setAuraFilter(true)
		self.esTrackerEventsEnabled = true
	end
end

-- Disable ES tracker events (called when tracker is hidden)
function SP:DisableESTrackerEvents()
	if self.esTrackerUpdateFrame and self.esTrackerEventsEnabled then
		setAuraFilter(false)
		self.esTrackerEventsEnabled = false
	end
end

function SP:ClearESTracker()
	if self.trackedEarthShields then
		wipe(self.trackedEarthShields)
	end
	if self.esTrackerButtons then
		for _, btn in pairs(self.esTrackerButtons) do
			btn:Hide()
		end
	end
	self:UpdateESTrackerFrame()
end

-- Initialize Earth Shield tracker
function SP:InitializeESTracker()
	self:InitESTracker()
	self:CreateESTrackerFrame()
	self:SetupESTrackerUpdater()

	-- Show if it was enabled
	if SP.opt.esTracker.enabled then
		local pos = SP.opt.esTracker.position
		if pos then
			self.esTrackerFrame:ClearAllPoints()
			self.esTrackerFrame:SetPoint(pos.point, UIParent, pos.point, pos.x, pos.y)
		end
		self:UpdateESTrackerBorder()
		self:ScanEarthShields()
		self.esTrackerFrame:Show()
		self:EnableESTrackerEvents()  -- Start UNIT_AURA tracking
	end
end

-- Register /spestrack slash command
SLASH_SPESTRACK1 = "/spestrack"
SLASH_SPESTRACK2 = "/spearthshield"
SlashCmdList["SPESTRACK"] = function(msg)
	msg = (msg or ""):lower():trim()

	if msg == "toggle" or msg == "" then
		SP:ToggleESTracker()
	elseif msg == "show" then
		SP:InitESTracker()
		if not SP.esTrackerFrame then
			SP:CreateESTrackerFrame()
		end
		local pos = SP.opt.esTracker.position
		if pos then
			SP.esTrackerFrame:ClearAllPoints()
			SP.esTrackerFrame:SetPoint(pos.point, UIParent, pos.point, pos.x, pos.y)
		end
		SP:UpdateESTrackerBorder()
		SP:ScanEarthShields()
		SP.esTrackerFrame:Show()
		SP:EnableESTrackerEvents()  -- Start UNIT_AURA tracking
		SP.opt.esTracker.enabled = true
	elseif msg == "hide" then
		if SP.esTrackerFrame then
			SP.esTrackerFrame:Hide()
		end
		SP:DisableESTrackerEvents()  -- Stop UNIT_AURA tracking
		SP.opt.esTracker.enabled = false
	else
		print("|cff0070ddShamanPower:|r Earth Shield Tracker commands:")
		print("  /spestrack - Toggle the tracker")
		print("  /spestrack show - Show the tracker")
		print("  /spestrack hide - Hide the tracker")
	end
end

-- Register the tracker frame with the setup-wizard preview harness (safe if absent)
if SP.RegisterPreview then
	SP:RegisterPreview("estracker", { frame = "ShamanPowerESTrackerFrame", demo = "SP:ESTrackerDemo", pad = 24 })
end

-- Refresh the tracker when a restricted client's secrets lift
if SPCompat and SPCompat.OnUnrestricted then
	SPCompat.OnUnrestricted(function() if SP.ScanEarthShields then SP:ScanEarthShields() end end)
end
