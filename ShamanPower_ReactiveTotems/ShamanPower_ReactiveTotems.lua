-- ============================================================================
-- ShamanPower [Reactive Totems] Module
-- Shows large totem icons when you have fear, disease, or poison debuffs
-- Each totem type has its own movable frame
-- ============================================================================

local SP = ShamanPower
if not SP then
	print("|cffff0000ShamanPower [Reactive Totems]:|r Core addon not found!")
	return
end

-- Only load for Shamans
local _, playerClass = UnitClass("player")
if playerClass ~= "SHAMAN" then
	return
end

-- Mark module as loaded
SP.ReactiveTotemsLoaded = true

-- SavedVariables
ShamanPower_ReactiveTotems = ShamanPower_ReactiveTotems or {}

-- ============================================================================
-- Reactive Totem Definitions
-- ============================================================================

SP.ReactiveTotems = {
	fear = {
		id = "fear",
		name = "Fear/Charm",
		debuffTypes = {"Fear", "Charm", "Horrify"},
		totemName = "Tremor Totem",
		totemSpellID = 8143,
		totemElement = 1,  -- Earth
		icon = "Interface\\Icons\\Spell_Nature_TremorTotem",
		color = {r = 0.8, g = 0.2, b = 0.8},  -- Purple
		defaultPos = { point = "CENTER", x = -80, y = 150 },
	},
	poison = {
		id = "poison",
		name = "Poison",
		debuffTypes = {"Poison"},
		totemName = "Poison Cleansing Totem",
		totemSpellID = 8166,
		totemElement = 3,  -- Water
		icon = "Interface\\Icons\\Spell_Nature_PoisonCleansingTotem",
		color = {r = 0.2, g = 0.8, b = 0.2},  -- Green
		defaultPos = { point = "CENTER", x = 0, y = 150 },
	},
	disease = {
		id = "disease",
		name = "Disease",
		debuffTypes = {"Disease"},
		totemName = "Disease Cleansing Totem",
		totemSpellID = 8170,
		totemElement = 3,  -- Water
		icon = "Interface\\Icons\\Spell_Nature_DiseaseCleansingTotem",
		color = {r = 0.6, g = 0.4, b = 0.2},  -- Brown
		defaultPos = { point = "CENTER", x = 80, y = 150 },
	},
}

-- Known fear/charm spell names
SP.FearSpellNames = {
	["Fear"] = true,
	["Howl of Terror"] = true,
	["Death Coil"] = true,
	["Seduction"] = true,
	["Intimidating Shout"] = true,
	["Psychic Scream"] = true,
	["Bellowing Roar"] = true,
	["Terrifying Screech"] = true,
	["Ancient Hysteria"] = true,
	["Intimidating Roar"] = true,
}

-- ============================================================================
-- Default Settings
-- ============================================================================

local defaultSettings = {
	enabled = true,
	locked = false,

	-- Global appearance (applies to all frames)
	iconSize = 64,
	scale = 1.0,
	opacity = 1.0,
	hideBorder = false,
	hideBackground = false,

	-- Text options
	showDebuffName = true,
	showTotemName = true,
	showDebuffIcon = false,       -- engine-drawn alerts: the debuff's own icon as a corner badge (opt-in)
	fontSize = 14,
	fontOutline = true,

	-- Effects
	showGlow = true,
	glowIntensity = 0.8,
	colorByDebuffType = true,

	-- Audio
	playSound = false,
	soundName = "Raid Warning",
	soundVolume = 100,

	-- Behavior
	clickToCast = true,
	onlyInInstance = false,       -- Only show alerts inside instances (dungeons/raids/PvP)
	hideWhenTotemActive = true,   -- Hide alert when the relevant totem is already placed

	-- Per-totem tracking toggles
	trackFear = true,
	trackPoison = true,
	trackDisease = true,

	-- Per-totem positions (each totem can be moved independently)
	positions = {
		fear = { point = "CENTER", x = -80, y = 150 },
		poison = { point = "CENTER", x = 0, y = 150 },
		disease = { point = "CENTER", x = 80, y = 150 },
	},
}

-- ============================================================================
-- Initialization
-- ============================================================================

function SP:InitReactiveTotems()
	-- One-time merge of the old separate Scale into Size (iconSize).
	local db = ShamanPower_ReactiveTotems
	if db and db.scale and math.abs(db.scale - 1) > 0.001 then
		db.iconSize = math.floor((db.iconSize or 64) * db.scale + 0.5)
		db.scale = 1.0
	end
	local sv = ShamanPower_ReactiveTotems

	-- Apply defaults for missing settings
	for key, value in pairs(defaultSettings) do
		if sv[key] == nil then
			if type(value) == "table" then
				sv[key] = {}
				for k, v in pairs(value) do
					if type(v) == "table" then
						sv[key][k] = {}
						for k2, v2 in pairs(v) do
							sv[key][k][k2] = v2
						end
					else
						sv[key][k] = v
					end
				end
			else
				sv[key] = value
			end
		end
	end

	-- Ensure positions table exists for each totem
	if not sv.positions then sv.positions = {} end
	for totemId, totemData in pairs(self.ReactiveTotems) do
		if not sv.positions[totemId] then
			sv.positions[totemId] = {
				point = totemData.defaultPos.point,
				x = totemData.defaultPos.x,
				y = totemData.defaultPos.y
			}
		end
	end
end

-- ============================================================================
-- Frame Creation (one frame per totem type)
-- ============================================================================

SP.reactiveFrames = {}  -- [totemId] = frame

function SP:CreateReactiveTotemFrame(totemId)
	if self.reactiveFrames[totemId] then return self.reactiveFrames[totemId] end

	local sv = ShamanPower_ReactiveTotems
	local totemData = self.ReactiveTotems[totemId]
	if not totemData then return nil end

	local size = sv.iconSize or 64
	local pos = sv.positions[totemId] or totemData.defaultPos

	-- Main frame - regular button (no click-to-cast due to combat restrictions)
	local frame = CreateFrame("Button", "ShamanPowerReactive_" .. totemId, UIParent, "BackdropTemplate")
	frame:SetSize(size, size)
	frame:SetPoint(pos.point or "CENTER", UIParent, pos.point or "CENTER", pos.x or 0, pos.y or 150)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:SetClampedToScreen(true)
	frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	frame.totemId = totemId
	frame.totemData = totemData

	-- Background
	local bg = frame:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.6)
	frame.bg = bg

	-- Icon
	local icon = frame:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("TOPLEFT", 3, -3)
	icon:SetPoint("BOTTOMRIGHT", -3, 3)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	icon:SetTexture(totemData.icon)
	frame.icon = icon

	-- Border
	local borderFrame = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	borderFrame:SetPoint("TOPLEFT", -2, 2)
	borderFrame:SetPoint("BOTTOMRIGHT", 2, -2)
	borderFrame:SetBackdrop({
		edgeFile = "Interface\\Buttons\\WHITE8X8",
		edgeSize = 2,
	})
	local c = totemData.color
	borderFrame:SetBackdropBorderColor(c.r, c.g, c.b, 1)
	frame.borderFrame = borderFrame

	-- Glow
	local glow = frame:CreateTexture(nil, "OVERLAY", nil, 1)
	glow:SetPoint("TOPLEFT", -12, 12)
	glow:SetPoint("BOTTOMRIGHT", 12, -12)
	glow:SetTexture("Interface\\SpellActivationOverlay\\IconAlert")
	glow:SetTexCoord(0.00781250, 0.50781250, 0.27734375, 0.52734375)
	glow:SetAlpha(0)
	glow:SetBlendMode("ADD")
	glow:SetVertexColor(c.r, c.g, c.b)
	frame.glow = glow

	-- Animation
	local ag = glow:CreateAnimationGroup()
	ag:SetLooping("REPEAT")

	local fadeIn = ag:CreateAnimation("Alpha")
	fadeIn:SetFromAlpha(0.2)
	fadeIn:SetToAlpha(sv.glowIntensity or 0.8)
	fadeIn:SetDuration(0.4)
	fadeIn:SetOrder(1)

	local fadeOut = ag:CreateAnimation("Alpha")
	fadeOut:SetFromAlpha(sv.glowIntensity or 0.8)
	fadeOut:SetToAlpha(0.2)
	fadeOut:SetDuration(0.4)
	fadeOut:SetOrder(2)

	frame.glowAnim = ag

	-- Debuff name text
	local debuffText = frame:CreateFontString(nil, "OVERLAY")
	SP:SetSPFont(debuffText, "alerts", sv.fontSize or 14, sv.fontOutline and "OUTLINE" or "")
	debuffText:SetPoint("TOP", frame, "BOTTOM", 0, -4)
	debuffText:SetTextColor(c.r, c.g, c.b)
	debuffText:SetShadowColor(0, 0, 0, 1)
	debuffText:SetShadowOffset(1, -1)
	frame.debuffText = debuffText

	-- Totem name text
	local totemText = frame:CreateFontString(nil, "OVERLAY")
	SP:SetSPFont(totemText, "alerts", (sv.fontSize or 14) - 2, sv.fontOutline and "OUTLINE" or "")
	totemText:SetPoint("TOP", debuffText, "BOTTOM", 0, -2)
	totemText:SetText(totemData.totemName)
	totemText:SetTextColor(1, 0.82, 0)
	totemText:SetShadowColor(0, 0, 0, 1)
	totemText:SetShadowOffset(1, -1)
	frame.totemText = totemText

	-- Drag handling - use ALT+drag to move (so left-click can cast)
	frame:SetScript("OnMouseDown", function(self, button)
		if button == "LeftButton" and IsAltKeyDown() and not ShamanPower_ReactiveTotems.locked then
			self:StartMoving()
			self.isMoving = true
		end
	end)

	frame:SetScript("OnMouseUp", function(self, button)
		if self.isMoving then
			self:StopMovingOrSizing()
			self.isMoving = false
			local point, _, _, x, y = self:GetPoint()
			ShamanPower_ReactiveTotems.positions[self.totemId] = { point = point, x = x, y = y }
		end
	end)

	-- Tooltip
	frame:SetScript("OnEnter", function(self)
		if SP.opt and SP.opt.ShowTooltips then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(self.totemData.name .. " Alert", 1, 0.82, 0)
			GameTooltip:AddLine(" ")
			if self.currentDebuffName then
				GameTooltip:AddLine("Debuff: " .. self.currentDebuffName, c.r, c.g, c.b)
			end
			if not ShamanPower_ReactiveTotems.locked then
				GameTooltip:AddLine(" ")
				GameTooltip:AddLine("Drag to move | Right-click for options", 0.5, 0.5, 0.5)
			end
			GameTooltip:Show()
		end
	end)

	frame:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	-- Click handlers
	frame:SetScript("OnClick", function(self, button)
		if button == "RightButton" then
			-- Open Look & Feel settings
			if ShamanPowerConfig then
				ShamanPowerConfig:Open({ "fluffy", "reactivetotems_section" })
			end
		end
	end)

	frame:SetAlpha(sv.opacity or 1.0)
	frame:Hide()

	self.reactiveFrames[totemId] = frame
	self:UpdateReactiveFrameAppearance(totemId)
	return frame
end

-- Create all frames
function SP:CreateAllReactiveFrames()
	for totemId, _ in pairs(self.ReactiveTotems) do
		self:CreateReactiveTotemFrame(totemId)
	end
end

-- Update appearance for one or all frames
function SP:UpdateReactiveFrameAppearance(totemId)
	local sv = ShamanPower_ReactiveTotems

	local function updateFrame(id)
		local frame = self.reactiveFrames[id]
		if not frame then return end

		local size = sv.iconSize or 64
		frame:SetSize(size, size)
		frame:SetAlpha(sv.opacity or 1.0)

		-- Background
		if sv.hideBackground then
			frame.bg:Hide()
		else
			frame.bg:Show()
		end

		-- Border
		if sv.hideBorder then
			frame.borderFrame:Hide()
		else
			frame.borderFrame:Show()
		end

		-- Font
		local fontSize = sv.fontSize or 14
		local outline = sv.fontOutline and "OUTLINE" or ""
		SP:SetSPFont(frame.debuffText, "alerts", fontSize, outline)
		SP:SetSPFont(frame.totemText, "alerts", fontSize - 2, outline)

		-- Text visibility
		if sv.showDebuffName then
			frame.debuffText:Show()
		else
			frame.debuffText:Hide()
		end

		if sv.showTotemName then
			frame.totemText:Show()
		else
			frame.totemText:Hide()
		end

	end

	if totemId then
		updateFrame(totemId)
	else
		for id, _ in pairs(self.ReactiveTotems) do
			updateFrame(id)
		end
	end
	if self.reactiveEngineBuilt then self:RebuildReactiveEngine() end   -- engine copies of the art (no-op unless it changed)
end

-- ============================================================================
-- Debuff Detection
-- ============================================================================

function SP:IsKnownFearDebuff(debuffName)
	if not debuffName then return false end
	return self.FearSpellNames[debuffName] or false
end

function SP:ScanForReactiveDebuffs()
	local sv = ShamanPower_ReactiveTotems
	if not sv or not sv.enabled then return {} end

	if sv.onlyInInstance then
		local inInstance, instanceType = IsInInstance()
		if not inInstance then return {} end
	end

	local found = {
		fear = nil,
		poison = nil,
		disease = nil,
	}

	-- Scan player and party members only (totems are party-wide, not raid-wide)
	local units = {"player", "party1", "party2", "party3", "party4"}

	for _, unit in ipairs(units) do
		if UnitExists(unit) and not UnitIsDeadOrGhost(unit) then
			for i = 1, 40 do
				local name, icon, count, debuffType = UnitDebuff(unit, i)
				if not name then break end

				-- Fear/Charm
				if sv.trackFear and not found.fear then
					if debuffType == "Fear" or debuffType == "Charm" or debuffType == "Horrify"
						or self:IsKnownFearDebuff(name) then
						found.fear = { debuffName = name, debuffIcon = icon, unit = unit }
					end
				end

				-- Poison
				if sv.trackPoison and not found.poison and debuffType == "Poison" then
					found.poison = { debuffName = name, debuffIcon = icon, unit = unit }
				end

				-- Disease
				if sv.trackDisease and not found.disease and debuffType == "Disease" then
					found.disease = { debuffName = name, debuffIcon = icon, unit = unit }
				end

				-- Early exit if we found all types
				if found.fear and found.poison and found.disease then
					return found
				end
			end
		end
	end

	return found
end

-- ============================================================================
-- Display Updates
-- ============================================================================

-- Totem state by addon element (1 Earth, 2 Fire, 3 Water, 4 Air). The core's
-- resolver handles clients that fill slots in cast order; otherwise the fixed
-- slot map applies (WoW slot 1 is Fire, slot 2 is Earth).
local function ElementTotemInfo(element)
	if ShamanPower.GetElementTotemInfo then return ShamanPower:GetElementTotemInfo(element) end
	return GetTotemInfo(ShamanPower.ElementToSlot[element])
end

function SP:UpdateReactiveTotemDisplay()
	-- Skip updates during positioning mode
	if self.reactivePositioningMode then return end

	-- Setup-wizard preview: don't let live scans overwrite the sample data.
	if self.reactiveDemoActive then return end

	local sv = ShamanPower_ReactiveTotems
	if self:ReactiveEngineLive() then
		-- The engine draws the alerts (below). The host frames are anchors only,
		-- and the sound is the one thing left to the scan, while it can read.
		self:SetReactiveHostMode()
		self:ApplyReactiveEngineVisibility()
		if sv and sv.enabled and sv.playSound and not (SPCompat and SPCompat.AurasUnreadable and SPCompat.AurasUnreadable()) then
			local found = self:ScanForReactiveDebuffs()
			for totemId, frame in pairs(self.reactiveFrames) do
				if found[totemId] then
					if not frame.soundPlayed then
						ShamanPower:PlaySoundWithVolume(ShamanPower:GetSoundFile(sv.soundName or "Raid Warning"), sv.soundVolume, true)
						frame.soundPlayed = true
					end
				else
					frame.soundPlayed = nil
				end
			end
		end
		return
	end
	if not sv or not sv.enabled then
		-- Hide all frames
		for id, frame in pairs(self.reactiveFrames) do
			frame:Hide()
		end
		return
	end

	local found = self:ScanForReactiveDebuffs()

	-- Update each totem frame based on whether that debuff type is present
	for totemId, totemData in pairs(self.ReactiveTotems) do
		local frame = self.reactiveFrames[totemId]
		if not frame then
			frame = self:CreateReactiveTotemFrame(totemId)
		end

		local debuffData = found[totemId]

		-- Check if relevant totem is already active
		if debuffData and sv.hideWhenTotemActive then
			local element = totemData.totemElement
			if element then
				local haveTotem, totemName = ElementTotemInfo(element)
				if haveTotem and totemName and totemName:find(totemData.totemName, 1, true) then
					debuffData = nil
				end
			end
		end

		if debuffData then
			-- Show this totem's frame
			frame.currentDebuffName = debuffData.debuffName
			frame.currentUnit = debuffData.unit

			-- Show unit name and debuff name
			local unitName = UnitName(debuffData.unit) or debuffData.unit
			if debuffData.unit == "player" then
				frame.debuffText:SetText(debuffData.debuffName)
			else
				frame.debuffText:SetText(unitName .. ": " .. debuffData.debuffName)
			end

			-- Glow
			if sv.showGlow then
				frame.glow:Show()
				frame.glowAnim:Play()
			else
				frame.glow:Hide()
				frame.glowAnim:Stop()
			end

			-- Sound (only once per debuff application)
			if sv.playSound and not frame.soundPlayed then
				ShamanPower:PlaySoundWithVolume(ShamanPower:GetSoundFile(sv.soundName or "Raid Warning"), sv.soundVolume, true)
				frame.soundPlayed = true
			end

			frame:Show()
		else
			-- Hide this totem's frame
			frame.glowAnim:Stop()
			frame.glow:Hide()
			frame.currentDebuffName = nil
			frame.soundPlayed = nil
			frame:Hide()
		end
	end
end

-- ============================================================================
-- Engine-drawn alerts (secrets regime: Forever / retail)
-- ============================================================================
-- In combat the scan above reads nothing (party debuffs are blocked), which is
-- the only time a cleansing call matters. An AuraContainer bound to each unit
-- (player, party1-4) shows its own copy of the alert art whenever that unit
-- carries a matching debuff and hides it the moment the debuff is gone, in
-- combat, with no reads: poison and disease by dispel type (a filter the
-- client does not tie to spell identity), fear by the client's CROWD_CONTROL
-- class. That class covers every crowd-control effect and the client offers
-- no fear-only filter, so on this family the Tremor alert means "crowd
-- controlled". The debuff's own icon and time left are painted by the engine;
-- the unit's name is static text set when the display is built (party names
-- are public out of combat). The sound cannot come from the engine (a sound
-- registration is per spell ID), so it plays only while the scan can read.
-- Built out of combat only; a rebuild asked for in a fight waits for regen.
SP.reactiveEngine = {}     -- [totemId][unitIndex] = { container = frame, key = string }
local reactivePending = false
local REACTIVE_UNITS = { "player", "party1", "party2", "party3", "party4" }
local REACTIVE_TRACK = { fear = "trackFear", poison = "trackPoison", disease = "trackDisease" }

local function ReactiveEngineAvailable()
	return SPCompat ~= nil and SPCompat.secretsRegime == true and C_AddOns ~= nil and C_AddOns.LoadAddOn ~= nil
end

-- true while the engine's displays are the live alerts
function SP:ReactiveEngineLive()
	return self.reactiveEngineBuilt == true and not self.reactivePositioningMode and not self.reactiveDemoActive
		and not self.reactiveTestActive
end

-- Everything about the art the display was built with; a change rebuilds it.
local function ReactiveAppearanceKey()
	local sv = ShamanPower_ReactiveTotems
	return table.concat({ tostring(sv.iconSize or 64), tostring(sv.hideBackground and 1 or 0), tostring(sv.hideBorder and 1 or 0),
		tostring(sv.showGlow ~= false and 1 or 0), tostring(sv.glowIntensity or 0.8), tostring(sv.fontSize or 14),
		tostring(sv.fontOutline and 1 or 0), tostring(sv.showDebuffName ~= false and 1 or 0), tostring(sv.showTotemName ~= false and 1 or 0),
		tostring(sv.showDebuffIcon and 1 or 0) }, "|")
end

local function ReactiveShouldShow(totemId)
	local sv = ShamanPower_ReactiveTotems
	if not sv or not sv.enabled then return false end
	if SP.reactivePositioningMode or SP.reactiveDemoActive then return false end
	if sv[REACTIVE_TRACK[totemId]] == false then return false end
	if sv.onlyInInstance and not IsInInstance() then return false end
	if sv.hideWhenTotemActive then
		local data = SP.ReactiveTotems[totemId]
		local haveTotem, totemName = ElementTotemInfo(data.totemElement)
		if haveTotem and type(totemName) == "string" and not issecretvalue(totemName) and totemName:find(data.totemName, 1, true) then
			return false
		end
	end
	return true
end

function SP:ApplyReactiveEngineVisibility()
	if not self.reactiveEngineBuilt then return end
	for totemId, list in pairs(self.reactiveEngine) do
		local show = ReactiveShouldShow(totemId)
		for _, slot in pairs(list) do
			local c = slot.container
			if c and c:IsShown() ~= show then c:SetShown(show) end
		end
	end
end

-- In engine mode the host frame is an anchor: its own art shows only for
-- positioning and the wizard demo; the engine's copies are the live alerts.
function SP:SetReactiveHostMode()
	if not self.reactiveEngineBuilt then return end
	local sv = ShamanPower_ReactiveTotems
	local live = self:ReactiveEngineLive()
	for _, frame in pairs(self.reactiveFrames) do
		if live then
			frame.bg:Hide(); frame.icon:Hide(); frame.borderFrame:Hide()
			frame.glow:Hide(); frame.glowAnim:Stop()
			frame.debuffText:Hide(); frame.totemText:Hide()
			frame:EnableMouse(false)
			frame:SetAlpha(sv.opacity or 1.0)
			frame:Show()
		elseif not frame.icon:IsShown() then
			frame.icon:Show()
			frame.bg:SetShown(not sv.hideBackground)
			frame.borderFrame:SetShown(not sv.hideBorder)
			frame.debuffText:SetShown(sv.showDebuffName and true or false)
			frame.totemText:SetShown(sv.showTotemName and true or false)
			frame:EnableMouse(true)
		end
	end
end

local reactiveLog = {}   -- one line per display built or refused, for /spreactive status

local function BuildReactiveContainer(totemId, unitIndex, host)
	local sv = ShamanPower_ReactiveTotems
	local data = SP.ReactiveTotems[totemId]
	local unit = REACTIVE_UNITS[unitIndex]
	local ok, container = pcall(CreateFrame, "AuraContainer", nil, host, "CustomAuraContainerTemplate")
	if not ok or not container then
		reactiveLog[#reactiveLog + 1] = totemId .. "/" .. unit .. " create: " .. tostring(container)
		if SPCompat.Trace then SPCompat.Trace("REACTIVE container %s/%s create failed: %s", totemId, unit, tostring(container)) end
		return nil
	end
	container:SetAllPoints(host)
	container:SetFrameLevel(host:GetFrameLevel() + 5)
	local filter, options = "HARMFUL", {}
	if totemId == "fear" then
		filter = "HARMFUL|CROWD_CONTROL"
	elseif totemId == "poison" then
		options.candidateFilters = { includeDispelTypes = { Poison = true } }
	else
		options.candidateFilters = { includeDispelTypes = { Disease = true } }
	end
	-- decided now, drawn by the engine later
	local size = sv.iconSize or 64
	local c = data.color
	local fontSize = sv.fontSize or 14
	local outline = sv.fontOutline and "OUTLINE" or ""
	local label = (unit == "player") and "You" or (UnitName(unit) or unit)
	local lr, lg, lb = c.r, c.g, c.b
	local _, class = UnitClass(unit)
	if class and RAID_CLASS_COLORS[class] then
		lr, lg, lb = RAID_CLASS_COLORS[class].r, RAID_CLASS_COLORS[class].g, RAID_CLASS_COLORS[class].b
	end
	options.initializeFrame = function(button)
		button:ClearAllPoints()
		button:SetAllPoints(host)
		if button.SetMouseClickEnabled then pcall(button.SetMouseClickEnabled, button, false) end
		if button.SetMouseMotionEnabled then pcall(button.SetMouseMotionEnabled, button, false) end
		if not sv.hideBackground then
			local bg = button:CreateTexture(nil, "BACKGROUND")
			bg:SetAllPoints(button)
			bg:SetColorTexture(0, 0, 0, 0.6)
		end
		local icon = button:CreateTexture(nil, "ARTWORK")
		icon:SetPoint("TOPLEFT", 3, -3)
		icon:SetPoint("BOTTOMRIGHT", -3, 3)
		icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		icon:SetTexture(data.icon)
		if not sv.hideBorder then
			local border = CreateFrame("Frame", nil, button, "BackdropTemplate")
			border:SetPoint("TOPLEFT", -2, 2)
			border:SetPoint("BOTTOMRIGHT", 2, -2)
			border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
			border:SetBackdropBorderColor(c.r, c.g, c.b, 1)
		end
		if sv.showGlow ~= false then
			local glow = button:CreateTexture(nil, "OVERLAY", nil, 1)
			glow:SetPoint("TOPLEFT", -12, 12)
			glow:SetPoint("BOTTOMRIGHT", 12, -12)
			glow:SetTexture("Interface\\SpellActivationOverlay\\IconAlert")
			glow:SetTexCoord(0.00781250, 0.50781250, 0.27734375, 0.52734375)
			glow:SetBlendMode("ADD")
			glow:SetVertexColor(c.r, c.g, c.b)
			glow:SetAlpha(0.2)
			local ag = glow:CreateAnimationGroup()
			ag:SetLooping("REPEAT")
			local a1 = ag:CreateAnimation("Alpha"); a1:SetFromAlpha(0.2); a1:SetToAlpha(sv.glowIntensity or 0.8); a1:SetDuration(0.4); a1:SetOrder(1)
			local a2 = ag:CreateAnimation("Alpha"); a2:SetFromAlpha(sv.glowIntensity or 0.8); a2:SetToAlpha(0.2); a2:SetDuration(0.4); a2:SetOrder(2)
			ag:Play()
		end
		-- the debuff itself: its icon as a badge hanging off the corner, painted
		-- by the engine; a dark edge keeps it from reading as a copy of the totem.
		-- Opt-in: off, the badge is still registered (the engine wants an icon
		-- region) but stays invisible.
		local badge = CreateFrame("Frame", nil, button)
		if not sv.showDebuffIcon then badge:SetAlpha(0) end
		local dsize = math.floor(size * 0.4)
		badge:SetSize(dsize, dsize)
		badge:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 6, -6)
		badge:SetFrameLevel(button:GetFrameLevel() + 3)
		local edge = badge:CreateTexture(nil, "BACKGROUND")
		edge:SetPoint("TOPLEFT", -2, 2)
		edge:SetPoint("BOTTOMRIGHT", 2, -2)
		edge:SetColorTexture(0, 0, 0, 1)
		local debuff = badge:CreateTexture(nil, "ARTWORK")
		debuff:SetAllPoints(badge)
		debuff:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		pcall(button.SetIcon, button, debuff)
		-- who and how long: one row per unit, so several alerts read as a list
		local carrier = CreateFrame("Frame", nil, button)
		carrier:SetAllPoints(button)
		if sv.showDebuffName ~= false then
			local who = carrier:CreateFontString(nil, "OVERLAY")
			SP:SetSPFont(who, "alerts", fontSize, outline)
			who:SetPoint("TOP", button, "BOTTOM", 0, -4 - (unitIndex - 1) * (fontSize + 2))
			who:SetTextColor(lr, lg, lb)
			who:SetShadowColor(0, 0, 0, 1)
			who:SetShadowOffset(1, -1)
			who:SetText(label)
			local left = carrier:CreateFontString(nil, "OVERLAY")
			SP:SetSPFont(left, "alerts", fontSize, outline)
			left:SetPoint("LEFT", who, "RIGHT", 4, 0)
			left:SetTextColor(1, 1, 1)
			left:SetShadowColor(0, 0, 0, 1)
			left:SetShadowOffset(1, -1)
			pcall(button.SetDurationText, button, left, {})
		end
		if sv.showTotemName ~= false then
			local totem = carrier:CreateFontString(nil, "OVERLAY")
			SP:SetSPFont(totem, "alerts", fontSize - 2, outline)
			totem:SetPoint("BOTTOM", button, "TOP", 0, 3)
			totem:SetText(data.totemName)
			totem:SetTextColor(1, 0.82, 0)
			totem:SetShadowColor(0, 0, 0, 1)
			totem:SetShadowOffset(1, -1)
		end
	end
	local okAdd, err = pcall(container.AddAuraSlot, container, "alert", filter, options)
	if not okAdd then
		reactiveLog[#reactiveLog + 1] = totemId .. "/" .. unit .. " slot: " .. tostring(err)
		if SPCompat.Trace then SPCompat.Trace("REACTIVE AddAuraSlot %s/%s failed: %s", totemId, unit, tostring(err)) end
		container:Hide()
		return nil
	end
	local okU, errU = pcall(container.SetUnit, container, unit)
	local okE, errE = pcall(container.SetEnabled, container, true)
	local okA, errA = pcall(container.UpdateAllAuras, container)
	reactiveLog[#reactiveLog + 1] = ("%s/%s ok (unit %s, enable %s, update %s)"):format(totemId, unit,
		okU and "ok" or tostring(errU), okE and "ok" or tostring(errE), okA and "ok" or tostring(errA))
	container:Hide()   -- ApplyReactiveEngineVisibility decides
	return container
end

-- /spreactive status: what the engine displays are doing, for testing on the beta.
function SP:ReactiveEngineReport()
	local sv = ShamanPower_ReactiveTotems
	self:Print(("Reactive engine: available=%s built=%s live=%s combat=%s enabled=%s instanceOnly=%s hideWhenTotem=%s"):format(
		tostring(ReactiveEngineAvailable()), tostring(self.reactiveEngineBuilt), tostring(self:ReactiveEngineLive()),
		tostring(InCombatLockdown()), tostring(sv and sv.enabled), tostring(sv and sv.onlyInInstance), tostring(sv and sv.hideWhenTotemActive)))
	self:Print(("  look: size=%s glow=%s debuffName=%s totemName=%s font=%s border=%s background=%s"):format(
		tostring(sv and sv.iconSize), tostring(sv and sv.showGlow), tostring(sv and sv.showDebuffName), tostring(sv and sv.showTotemName),
		tostring(sv and sv.fontSize), tostring(not (sv and sv.hideBorder)), tostring(not (sv and sv.hideBackground))))
	for totemId in pairs(self.ReactiveTotems) do
		local host = self.reactiveFrames[totemId]
		local parts = {}
		for i, unit in ipairs(REACTIVE_UNITS) do
			local slot = self.reactiveEngine[totemId] and self.reactiveEngine[totemId][i]
			local c = slot and slot.container
			parts[#parts + 1] = unit .. "=" .. (c and (c:IsShown() and "shown" or "hidden") or "-")
		end
		self:Print(("  %s: shouldShow=%s host=%s track=%s  %s"):format(totemId, tostring(ReactiveShouldShow(totemId)),
			host and (host:IsShown() and "shown" or "hidden") or "none", tostring(sv and sv[REACTIVE_TRACK[totemId]]), table.concat(parts, " ")))
	end
	self:Print("  built: " .. (#reactiveLog > 0 and table.concat(reactiveLog, "; ") or "(nothing built yet)"))
end

-- Build, or rebuild where a unit's name / class or the art changed. Cheap when
-- nothing changed (one key per display), so options and roster code call it freely.
function SP:RebuildReactiveEngine()
	if not ReactiveEngineAvailable() then return end
	if InCombatLockdown() then reactivePending = true return end
	reactivePending = false
	pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
	local look = ReactiveAppearanceKey()
	local built = false
	for totemId in pairs(self.ReactiveTotems) do
		local host = self.reactiveFrames[totemId] or self:CreateReactiveTotemFrame(totemId)
		if host then
			self.reactiveEngine[totemId] = self.reactiveEngine[totemId] or {}
			local list = self.reactiveEngine[totemId]
			for i, unit in ipairs(REACTIVE_UNITS) do
				local exists = UnitExists(unit)
				local _, class = UnitClass(unit)
				local key = (exists and ((UnitName(unit) or "?") .. "/" .. tostring(class)) or "-") .. "|" .. look
				local slot = list[i]
				if not slot or slot.key ~= key then
					if slot and slot.container then
						pcall(slot.container.SetEnabled, slot.container, false)
						slot.container:Hide()
					end
					list[i] = { container = exists and BuildReactiveContainer(totemId, i, host) or nil, key = key }
				end
				if list[i].container then built = true end
			end
		end
	end
	self.reactiveEngineBuilt = built or nil
	self:SetReactiveHostMode()
	self:ApplyReactiveEngineVisibility()
end

function SP:ReactiveEngineRegen()
	if reactivePending then self:RebuildReactiveEngine() end
end

-- ============================================================================
-- Event Handling
-- ============================================================================

function SP:SetupReactiveTotemsEvents()
	if self.reactiveEventsSetup then return end
	self.reactiveEventsSetup = true

	local eventFrame = CreateFrame("Frame", "ShamanPowerReactiveEventFrame", UIParent)
	if SPCompat and SPCompat.StressRegister then SPCompat.StressRegister(eventFrame, "Reactive Totems") end
	-- UNIT_AURA for player + party1-4 only (totems are party-wide): the game filters,
	-- so a raid's other members and nameplates never reach the handler. Two units
	-- per frame, the count every client accepts. Old clients: all units, filtered below.
	local auraFrames = {}
	if eventFrame.RegisterUnitEvent then
		for _, units in ipairs({ { "player", "party1" }, { "party2", "party3" }, { "party4" } }) do
			local f = CreateFrame("Frame")
			if SPCompat and SPCompat.StressRegister then SPCompat.StressRegister(f, "Reactive Totems (auras)") end
			f:RegisterUnitEvent("UNIT_AURA", units[1], units[2])
			auraFrames[#auraFrames + 1] = f
		end
	else
		eventFrame:RegisterEvent("UNIT_AURA")
	end
	eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
	eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
	eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
	eventFrame:RegisterEvent("PLAYER_TOTEM_UPDATE")
	eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")   -- engine displays rebuilt after a fight if asked for in one

	-- Throttle updates to max 20 per second (0.05s between updates)
	local lastUpdate = 0
	local pendingUpdate = false

	local function DoUpdate()
		pendingUpdate = false
		SP:UpdateReactiveTotemDisplay()
	end

	local function RequestUpdate()
		local now = GetTime()
		if now - lastUpdate >= 0.05 then
			lastUpdate = now
			DoUpdate()
		elseif not pendingUpdate then
			pendingUpdate = true
			C_Timer.After(0.05, DoUpdate)
		end
	end

	local function OnPartyAura()
		-- engine mode: aura changes are the engine's business; the scan only serves the sound
		if SP:ReactiveEngineLive() and not (ShamanPower_ReactiveTotems and ShamanPower_ReactiveTotems.playSound) then return end
		RequestUpdate()
	end
	-- the filtered frames only ever hear player and party1-4 (whatever token the
	-- game names them by), so they need no token check
	for _, f in ipairs(auraFrames) do f:SetScript("OnEvent", OnPartyAura) end

	local function OnReactiveEvent(self, event, unit)
		if event == "UNIT_AURA" then
			-- Unfiltered fallback: only player and party units (totems are party-wide only)
			if unit == "player" or unit == "party1" or unit == "party2" or unit == "party3" or unit == "party4" then
				OnPartyAura()
			end
		elseif event == "PLAYER_REGEN_ENABLED" then
			SP:ReactiveEngineRegen()
		elseif event == "PLAYER_ENTERING_WORLD" or event == "GROUP_ROSTER_UPDATE"
			or event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_TOTEM_UPDATE" then
			if event ~= "PLAYER_TOTEM_UPDATE" then SP:RebuildReactiveEngine() end   -- names / classes may have changed
			RequestUpdate()
		end
	end
	eventFrame:SetScript("OnEvent", OnReactiveEvent)

	self.reactiveEventFrame = eventFrame
end

-- ============================================================================
-- Configuration UI
-- ============================================================================

-- The module's old Blizzard-template configuration window is retired: every
-- setting it held is on the Reactive Totems page of the settings window, with
-- the Test / Show All / Reset actions. /spreactive and the old entry points land
-- on that page.
function SP:ShowReactiveTotemsConfig()
	self:OpenConfigWindow({ "fluffy", "reactivetotems_section" })
end

-- Test all alerts
function SP:TestReactiveAlerts()
	local sv = ShamanPower_ReactiveTotems
	self.reactiveTestActive = true
	self:SetReactiveHostMode()
	self:ApplyReactiveEngineVisibility()

	for totemId, totemData in pairs(self.ReactiveTotems) do
		local frame = self.reactiveFrames[totemId]
		if not frame then
			frame = self:CreateReactiveTotemFrame(totemId)
		end

		frame.debuffText:SetText("Test " .. totemData.name)
		frame.currentDebuffName = "Test " .. totemData.name

		if sv.showGlow then
			frame.glow:Show()
			frame.glowAnim:Play()
		end

		frame:Show()
	end

	if sv.playSound then
		ShamanPower:PlaySoundWithVolume(ShamanPower:GetSoundFile(sv.soundName or "Raid Warning"), sv.soundVolume, true)
	end

	-- Hide after 3 seconds
	C_Timer.After(3, function()
		for totemId, frame in pairs(SP.reactiveFrames) do
			frame.glowAnim:Stop()
			frame.glow:Hide()
			frame:Hide()
		end
		SP.reactiveTestActive = nil
		SP:SetReactiveHostMode()
		SP:ApplyReactiveEngineVisibility()
	end)
end

-- Show all frames for positioning (disables click-to-cast so user can drag freely)
function SP:ShowAllReactiveFrames()
	self.reactivePositioningMode = true
	self:SetReactiveHostMode()
	self:ApplyReactiveEngineVisibility()

	for totemId, totemData in pairs(self.ReactiveTotems) do
		local frame = self.reactiveFrames[totemId]
		if not frame then
			frame = self:CreateReactiveTotemFrame(totemId)
		end

		-- Disable click-to-cast during positioning
		frame:SetAttribute("type1", nil)
		frame:SetAttribute("spell1", nil)

		frame.debuffText:SetText(totemData.name)
		frame.glow:Hide()
		frame.glowAnim:Stop()
		frame:Show()
	end

	SP:Print("Positioning mode: drag the frames, then press Hide All on the Reactive Totems settings page (or /spreactive hide).")
end

-- Hide all frames and restore click-to-cast
function SP:HideAllReactiveFrames()
	local sv = ShamanPower_ReactiveTotems
	self.reactivePositioningMode = false
	if self.SettingsTestDone then self:SettingsTestDone() end   -- back to the settings page that started positioning

	for totemId, frame in pairs(self.reactiveFrames) do
		frame:Hide()

		-- Restore click-to-cast if enabled
		if sv.clickToCast then
			frame:SetAttribute("type1", "spell")
			frame:SetAttribute("spell1", frame.totemData.totemName)
		end
	end

	self:SetReactiveHostMode()
	self:ApplyReactiveEngineVisibility()
	SP:Print("Positioning mode ended.")
end

-- Reset positions
function SP:ResetReactivePositions()
	local sv = ShamanPower_ReactiveTotems

	for totemId, totemData in pairs(self.ReactiveTotems) do
		sv.positions[totemId] = {
			point = totemData.defaultPos.point,
			x = totemData.defaultPos.x,
			y = totemData.defaultPos.y
		}

		local frame = self.reactiveFrames[totemId]
		if frame then
			frame:ClearAllPoints()
			frame:SetPoint(totemData.defaultPos.point, UIParent, totemData.defaultPos.point,
				totemData.defaultPos.x, totemData.defaultPos.y)
		end
	end

	SP:Print("Reactive totem positions reset to defaults")
end

-- ============================================================================
-- Slash Commands
-- ============================================================================

SLASH_SPREACTIVE1 = "/spreactive"
SLASH_SPREACTIVE2 = "/reactivetotem"
SlashCmdList["SPREACTIVE"] = function(msg)
	msg = msg and msg:lower():trim() or ""

	if msg == "toggle" then
		ShamanPower_ReactiveTotems.enabled = not ShamanPower_ReactiveTotems.enabled
		SP:UpdateReactiveTotemDisplay()
		SP:Print("Reactive Totems " .. (ShamanPower_ReactiveTotems.enabled and "enabled" or "disabled"))
	elseif msg == "test" then
		SP:TestReactiveAlerts()
	elseif msg == "reset" then
		SP:ResetReactivePositions()
	elseif msg == "status" then
		SP:ReactiveEngineReport()
	elseif msg == "rebuild" then
		wipe(reactiveLog)
		for _, list in pairs(SP.reactiveEngine) do
			for _, slot in pairs(list) do slot.key = "" end   -- force every display to be built again
		end
		SP:RebuildReactiveEngine()
		SP:ReactiveEngineReport()
	elseif msg == "show" then
		SP:ShowAllReactiveFrames()
	elseif msg == "hide" then
		SP:HideAllReactiveFrames()
	else
		-- Open ShamanPower options to Look & Feel > Reactive Totems using AceConfigDialog
		if ShamanPowerConfig then
			ShamanPowerConfig:Open({ "fluffy", "reactivetotems_section" })
		else
			SP:Print("Type /sp to open ShamanPower settings, then go to Look & Feel > Reactive Totems")
		end
	end
end

-- ============================================================================
-- Bridge Functions (called by ShamanPowerOptions.lua)
-- ============================================================================

-- Called when enabled or tracking settings change
function SP:UpdateReactiveTotems()
	self:UpdateReactiveTotemDisplay()
end

-- Called when appearance settings change
function SP:UpdateReactiveTotemAppearance()
	self:UpdateReactiveFrameAppearance()
end

-- Called by Test All button in options
function SP:TestReactiveTotems()
	self:TestReactiveAlerts()
end

-- Called by Reset Positions button in options
function SP:ResetReactiveTotemPositions()
	self:ResetReactivePositions()
end

-- Called by Show All button in options (bridge function)
-- Note: ShowAllReactiveFrames is defined above, this just ensures consistent naming

-- Called by Hide All button in options (bridge function)
-- Note: HideAllReactiveFrames is defined above, this just ensures consistent naming

-- ============================================================================
-- Setup Wizard Preview (frame borrowed by ShamanPowerPreview.lua)
-- ============================================================================

-- Which reactive totem to showcase in the wizard preview (Tremor Totem).
local PREVIEW_TOTEM = "fear"

-- Fill the reactive totem frame with believable sample data for the wizard.
-- Reuses the same render the test/live paths use (debuffText + glow); only the
-- data is faked. Unlike TestReactiveAlerts this plays no sound and never
-- auto-expires, and it does NOT call frame:Show() itself -- the preview harness
-- shows the frame, so the frame's real (hidden) state is preserved for a clean
-- restore. reactiveDemoActive guards UpdateReactiveTotemDisplay meanwhile.
function SP:ReactiveDemo(on)
	local sv = ShamanPower_ReactiveTotems
	self.reactiveFrames = self.reactiveFrames or {}
	for id in pairs(self.ReactiveTotems) do
		if not self.reactiveFrames[id] then self:CreateReactiveTotemFrame(id) end
	end

	-- The live alert's debuff badge is drawn by the game; the preview draws its own
	-- copy (same corner, same size, same dark edge) with a sample debuff icon.
	local DEMO_DEBUFF_ICON = {
		fear = "Interface\\Icons\\Ability_GolemThunderClap",    -- Intimidating Shout
		poison = "Interface\\Icons\\Ability_Rogue_DualWeild",   -- Deadly Poison
		disease = "Interface\\Icons\\Spell_Shadow_CallofBone",  -- Plague
	}
	local function demoBadge(frame, id)
		local b = frame.spDemoBadge
		if not b then
			b = CreateFrame("Frame", nil, frame)
			local edge = b:CreateTexture(nil, "BACKGROUND")
			edge:SetPoint("TOPLEFT", -2, 2); edge:SetPoint("BOTTOMRIGHT", 2, -2)
			edge:SetColorTexture(0, 0, 0, 1)
			b.icon = b:CreateTexture(nil, "ARTWORK")
			b.icon:SetAllPoints(b); b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			frame.spDemoBadge = b
		end
		local dsize = math.floor(frame:GetWidth() * 0.4)
		b:SetSize(dsize, dsize)
		b:ClearAllPoints(); b:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 6, -6)
		b:SetFrameLevel(frame:GetFrameLevel() + 6)
		b.icon:SetTexture(DEMO_DEBUFF_ICON[id])
		b:Show()
	end

	local function clearAll()
		for id, frame in pairs(self.reactiveFrames) do
			if frame.spDemoBadge then frame.spDemoBadge:Hide() end
			frame.glowAnim:Stop(); frame.glow:Hide()
			frame.debuffText:SetText(""); frame.currentDebuffName = nil; frame.soundPlayed = nil
			frame:Hide()
		end
	end

	if on then
		if self.reactiveDemoActive then
			self:UpdateReactiveFrameAppearance()   -- re-entrant: options changed
			return
		end
		self.reactiveDemoActive = true
		self:SetReactiveHostMode()
		self:ApplyReactiveEngineVisibility()
		self:UpdateReactiveFrameAppearance()

		-- A short raid scene, looped: each beat is { totem, "who: debuff", seconds }.
		local SCENE = {
			{ "fear",    "Tank: Intimidating Shout", 4.0, story = "The tank got feared - drop Tremor Totem" },
			{ nil,       nil,                        1.5, story = "Tremor is down, fear broken" },
			{ "poison",  "Rogue: Deadly Poison",     4.0, story = "Rogue is poisoned - drop Poison Cleansing Totem" },
			{ nil,       nil,                        1.5, story = "Cleansed" },
			{ "disease", "Priest: Plague",           4.0, story = "Priest is diseased - drop Disease Cleansing Totem" },
			{ nil,       nil,                        2.0, story = "All clear" },
		}
		local track = { fear = "trackFear", poison = "trackPoison", disease = "trackDisease" }
		local beat, left = 0, 0
		local function apply(b)
			clearAll()
			local id, text = b[1], b[2]
			self.reactiveDemoStatus = b.story
			if id and sv[track[id]] ~= false then
				local frame = self.reactiveFrames[id]
				frame.debuffText:SetText(text); frame.currentDebuffName = text
				if sv.showGlow ~= false then frame.glow:Show(); frame.glowAnim:Play() end
				if sv.showDebuffIcon then demoBadge(frame, id) end
				if sv.playSound then
					self:PlaySoundWithVolume(self:GetSoundFile(sv.soundName or "Raid Warning"), sv.soundVolume, true)
				end
				frame:Show()
			elseif id then
				self.reactiveDemoStatus = b.story .. "  (tracking for this debuff is off)"
			end
		end
		if self.reactiveDemoTicker then self.reactiveDemoTicker:Cancel() end
		self.reactiveDemoTicker = C_Timer.NewTicker(0.25, function()
			if not self.reactiveDemoActive then return end
			left = left - 0.25
			if left <= 0 then
				beat = (beat % #SCENE) + 1
				left = SCENE[beat][3]
				apply(SCENE[beat])
			end
		end)
	else
		self.reactiveDemoActive = false
		if self.reactiveDemoTicker then self.reactiveDemoTicker:Cancel(); self.reactiveDemoTicker = nil end
		self.reactiveDemoStatus = nil
		clearAll()
		-- Hand control back to the real scan (frames hide when no debuff).
		self:UpdateReactiveTotemDisplay()
	end
end

-- ============================================================================
-- Module Initialization
-- ============================================================================

function SP:InitializeReactiveTotems()
	self:InitReactiveTotems()
	self:CreateAllReactiveFrames()
	self:SetupReactiveTotemsEvents()
	self:RebuildReactiveEngine()
	self:UpdateReactiveTotemDisplay()
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self, event)
	if event == "PLAYER_LOGIN" then
		C_Timer.After(0.5, function()
			SP:InitializeReactiveTotems()
		end)
	end
end)

-- ============================================================================
-- Setup Wizard Preview Registration
-- ============================================================================

if ShamanPower.RegisterPreview then
	ShamanPower:RegisterPreview("reactive", {
		frames = {
			function() SP.reactiveFrames = SP.reactiveFrames or {}; return SP.reactiveFrames.fear or SP:CreateReactiveTotemFrame("fear") end,
			function() return SP.reactiveFrames.poison or SP:CreateReactiveTotemFrame("poison") end,
			function() return SP.reactiveFrames.disease or SP:CreateReactiveTotemFrame("disease") end,
		},
		demo = "SP:ReactiveDemo",
		pad = 24,
		pane = { overlap = true },   -- settings-window pane only: the scene lights one alert at a time, so one centred spot
	})
end
