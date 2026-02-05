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
	fontSize = 14,
	fontOutline = true,

	-- Effects
	showGlow = true,
	glowIntensity = 0.8,
	colorByDebuffType = true,

	-- Audio
	playSound = false,
	soundID = 8959,
	soundVolume = 100,

	-- Behavior
	clickToCast = true,

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
	debuffText:SetFont("Fonts\\FRIZQT__.TTF", sv.fontSize or 14, sv.fontOutline and "OUTLINE" or "")
	debuffText:SetPoint("TOP", frame, "BOTTOM", 0, -4)
	debuffText:SetTextColor(c.r, c.g, c.b)
	debuffText:SetShadowColor(0, 0, 0, 1)
	debuffText:SetShadowOffset(1, -1)
	frame.debuffText = debuffText

	-- Totem name text
	local totemText = frame:CreateFontString(nil, "OVERLAY")
	totemText:SetFont("Fonts\\FRIZQT__.TTF", (sv.fontSize or 14) - 2, sv.fontOutline and "OUTLINE" or "")
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
			GameTooltip:AddLine("Click to cast: " .. self.totemData.totemName, 0.7, 0.7, 0.7)
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
			if LibStub and LibStub("AceConfigDialog-3.0", true) then
				LibStub("AceConfigDialog-3.0"):Open("ShamanPower")
				LibStub("AceConfigDialog-3.0"):SelectGroup("ShamanPower", "fluffy", "reactivetotems_section")
			end
		end
	end)

	frame:SetScale(sv.scale or 1.0)
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
		frame:SetScale(sv.scale or 1.0)
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
		frame.debuffText:SetFont("Fonts\\FRIZQT__.TTF", fontSize, outline)
		frame.totemText:SetFont("Fonts\\FRIZQT__.TTF", fontSize - 2, outline)

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

function SP:UpdateReactiveTotemDisplay()
	-- Skip updates during positioning mode
	if self.reactivePositioningMode then return end

	local sv = ShamanPower_ReactiveTotems
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
				ShamanPower:PlaySoundWithVolume(sv.soundID or 8959, sv.soundVolume, false)
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
-- Event Handling
-- ============================================================================

function SP:SetupReactiveTotemsEvents()
	if self.reactiveEventsSetup then return end
	self.reactiveEventsSetup = true

	local eventFrame = CreateFrame("Frame", "ShamanPowerReactiveEventFrame", UIParent)
	eventFrame:RegisterEvent("UNIT_AURA")
	eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
	eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")

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

	eventFrame:SetScript("OnEvent", function(self, event, unit)
		if event == "UNIT_AURA" then
			-- Only check player and party units (totems are party-wide only)
			if unit == "player" or unit == "party1" or unit == "party2" or unit == "party3" or unit == "party4" then
				RequestUpdate()
			end
		elseif event == "PLAYER_ENTERING_WORLD" or event == "GROUP_ROSTER_UPDATE" then
			RequestUpdate()
		end
	end)

	self.reactiveEventFrame = eventFrame
end

-- ============================================================================
-- Configuration UI
-- ============================================================================

function SP:ShowReactiveTotemsConfig()
	local sv = ShamanPower_ReactiveTotems

	if not self.reactiveConfigFrame then
		local config = CreateFrame("Frame", "ShamanPowerReactiveConfigFrame", UIParent, "BackdropTemplate")
		config:SetSize(320, 480)
		config:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
		config:SetMovable(true)
		config:EnableMouse(true)
		config:SetClampedToScreen(true)
		config:SetFrameStrata("DIALOG")

		config:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 }
		})
		config:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
		config:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

		-- Title
		local title = config:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		title:SetPoint("TOP", config, "TOP", 0, -12)
		title:SetText("Reactive Totems")
		title:SetTextColor(1, 0.82, 0)

		-- Close button
		local closeBtn = CreateFrame("Button", nil, config, "UIPanelCloseButton")
		closeBtn:SetPoint("TOPRIGHT", config, "TOPRIGHT", -2, -2)
		closeBtn:SetScript("OnClick", function() config:Hide() end)

		-- Drag
		config:RegisterForDrag("LeftButton")
		config:SetScript("OnDragStart", function(self) self:StartMoving() end)
		config:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

		-- Scroll frame
		local scrollFrame = CreateFrame("ScrollFrame", nil, config, "UIPanelScrollFrameTemplate")
		scrollFrame:SetPoint("TOPLEFT", config, "TOPLEFT", 10, -35)
		scrollFrame:SetPoint("BOTTOMRIGHT", config, "BOTTOMRIGHT", -30, 50)

		local content = CreateFrame("Frame", nil, scrollFrame)
		content:SetSize(280, 550)
		scrollFrame:SetScrollChild(content)

		local yOffset = 0

		local function CreateCheckbox(parent, label, settingKey, callback)
			local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
			check:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOffset)
			check.text:SetText(label)
			check.text:SetFontObject("GameFontNormalSmall")
			check.settingKey = settingKey
			check:SetScript("OnClick", function(self)
				ShamanPower_ReactiveTotems[settingKey] = self:GetChecked()
				if callback then callback() end
			end)
			yOffset = yOffset - 24
			return check
		end

		local function CreateSlider(parent, label, settingKey, min, max, step, callback)
			local sliderLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
			sliderLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", 5, yOffset)
			sliderLabel:SetText(label)
			yOffset = yOffset - 15

			local slider = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
			slider:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOffset)
			slider:SetWidth(200)
			slider:SetMinMaxValues(min, max)
			slider:SetValueStep(step)
			slider:SetObeyStepOnDrag(true)
			slider.Low:SetText(tostring(min))
			slider.High:SetText(tostring(max))
			slider.settingKey = settingKey
			slider:SetScript("OnValueChanged", function(self, value)
				ShamanPower_ReactiveTotems[settingKey] = value
				self.Text:SetText(string.format("%.1f", value))
				if callback then callback() end
			end)
			yOffset = yOffset - 35
			return slider
		end

		-- Section: General
		local section1 = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		section1:SetPoint("TOPLEFT", content, "TOPLEFT", 0, yOffset)
		section1:SetText("General")
		section1:SetTextColor(1, 0.82, 0)
		yOffset = yOffset - 20

		config.enableCheck = CreateCheckbox(content, "Enable Reactive Totems", "enabled", function()
			SP:UpdateReactiveTotemDisplay()
		end)
		config.lockCheck = CreateCheckbox(content, "Lock Positions", "locked")

		yOffset = yOffset - 10

		-- Section: Tracking
		local section2 = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		section2:SetPoint("TOPLEFT", content, "TOPLEFT", 0, yOffset)
		section2:SetText("Debuff Tracking")
		section2:SetTextColor(1, 0.82, 0)
		yOffset = yOffset - 20

		config.fearCheck = CreateCheckbox(content, "Fear/Charm (Tremor Totem)", "trackFear", function()
			SP:UpdateReactiveTotemDisplay()
		end)
		config.poisonCheck = CreateCheckbox(content, "Poison (Poison Cleansing)", "trackPoison", function()
			SP:UpdateReactiveTotemDisplay()
		end)
		config.diseaseCheck = CreateCheckbox(content, "Disease (Disease Cleansing)", "trackDisease", function()
			SP:UpdateReactiveTotemDisplay()
		end)

		yOffset = yOffset - 10

		-- Section: Appearance
		local section3 = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		section3:SetPoint("TOPLEFT", content, "TOPLEFT", 0, yOffset)
		section3:SetText("Appearance")
		section3:SetTextColor(1, 0.82, 0)
		yOffset = yOffset - 20

		config.sizeSlider = CreateSlider(content, "Icon Size", "iconSize", 32, 128, 4, function()
			SP:UpdateReactiveFrameAppearance()
		end)
		config.scaleSlider = CreateSlider(content, "Scale", "scale", 0.5, 2.0, 0.1, function()
			SP:UpdateReactiveFrameAppearance()
		end)
		config.opacitySlider = CreateSlider(content, "Opacity", "opacity", 0.2, 1.0, 0.1, function()
			SP:UpdateReactiveFrameAppearance()
		end)
		config.fontSizeSlider = CreateSlider(content, "Font Size", "fontSize", 10, 24, 1, function()
			SP:UpdateReactiveFrameAppearance()
		end)

		config.hideBorderCheck = CreateCheckbox(content, "Hide Border", "hideBorder", function()
			SP:UpdateReactiveFrameAppearance()
		end)
		config.hideBackgroundCheck = CreateCheckbox(content, "Hide Background", "hideBackground", function()
			SP:UpdateReactiveFrameAppearance()
		end)
		config.showDebuffNameCheck = CreateCheckbox(content, "Show Debuff Name", "showDebuffName", function()
			SP:UpdateReactiveFrameAppearance()
		end)
		config.showTotemNameCheck = CreateCheckbox(content, "Show Totem Name", "showTotemName", function()
			SP:UpdateReactiveFrameAppearance()
		end)

		yOffset = yOffset - 10

		-- Section: Effects
		local section4 = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		section4:SetPoint("TOPLEFT", content, "TOPLEFT", 0, yOffset)
		section4:SetText("Effects & Behavior")
		section4:SetTextColor(1, 0.82, 0)
		yOffset = yOffset - 20

		config.showGlowCheck = CreateCheckbox(content, "Show Pulsing Glow", "showGlow", function()
			SP:UpdateReactiveTotemDisplay()
		end)
		config.glowSlider = CreateSlider(content, "Glow Intensity", "glowIntensity", 0.2, 1.0, 0.1)
		config.playSoundCheck = CreateCheckbox(content, "Play Alert Sound", "playSound")
		config.clickToCastCheck = CreateCheckbox(content, "Click to Cast Totem", "clickToCast", function()
			SP:UpdateReactiveFrameAppearance()
		end)
		config.fontOutlineCheck = CreateCheckbox(content, "Font Outline", "fontOutline", function()
			SP:UpdateReactiveFrameAppearance()
		end)

		-- Buttons at bottom
		local testBtn = CreateFrame("Button", nil, config, "UIPanelButtonTemplate")
		testBtn:SetPoint("BOTTOMLEFT", config, "BOTTOMLEFT", 16, 16)
		testBtn:SetSize(85, 24)
		testBtn:SetText("Test All")
		testBtn:SetScript("OnClick", function()
			SP:TestReactiveAlerts()
		end)

		local resetBtn = CreateFrame("Button", nil, config, "UIPanelButtonTemplate")
		resetBtn:SetPoint("BOTTOM", config, "BOTTOM", 0, 16)
		resetBtn:SetSize(85, 24)
		resetBtn:SetText("Reset Pos")
		resetBtn:SetScript("OnClick", function()
			SP:ResetReactivePositions()
		end)

		local unlockBtn = CreateFrame("Button", nil, config, "UIPanelButtonTemplate")
		unlockBtn:SetPoint("BOTTOMRIGHT", config, "BOTTOMRIGHT", -16, 16)
		unlockBtn:SetSize(85, 24)
		unlockBtn:SetText("Show All")
		unlockBtn:SetScript("OnClick", function()
			SP:ShowAllReactiveFrames()
		end)

		config:Hide()
		self.reactiveConfigFrame = config
	end

	-- Update controls
	local config = self.reactiveConfigFrame
	config.enableCheck:SetChecked(sv.enabled)
	config.lockCheck:SetChecked(sv.locked)
	config.fearCheck:SetChecked(sv.trackFear)
	config.poisonCheck:SetChecked(sv.trackPoison)
	config.diseaseCheck:SetChecked(sv.trackDisease)
	config.sizeSlider:SetValue(sv.iconSize or 64)
	config.scaleSlider:SetValue(sv.scale or 1.0)
	config.opacitySlider:SetValue(sv.opacity or 1.0)
	config.fontSizeSlider:SetValue(sv.fontSize or 14)
	config.hideBorderCheck:SetChecked(sv.hideBorder)
	config.hideBackgroundCheck:SetChecked(sv.hideBackground)
	config.showDebuffNameCheck:SetChecked(sv.showDebuffName)
	config.showTotemNameCheck:SetChecked(sv.showTotemName)
	config.showGlowCheck:SetChecked(sv.showGlow)
	config.glowSlider:SetValue(sv.glowIntensity or 0.8)
	config.playSoundCheck:SetChecked(sv.playSound)
	config.clickToCastCheck:SetChecked(sv.clickToCast)
	config.fontOutlineCheck:SetChecked(sv.fontOutline)

	config:Show()
end

-- Test all alerts
function SP:TestReactiveAlerts()
	local sv = ShamanPower_ReactiveTotems

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
		ShamanPower:PlaySoundWithVolume(sv.soundID or 8959, sv.soundVolume, false)
	end

	-- Hide after 3 seconds
	C_Timer.After(3, function()
		for totemId, frame in pairs(SP.reactiveFrames) do
			frame.glowAnim:Stop()
			frame.glow:Hide()
			frame:Hide()
		end
	end)
end

-- Show all frames for positioning (disables click-to-cast so user can drag freely)
function SP:ShowAllReactiveFrames()
	self.reactivePositioningMode = true

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

	SP:Print("Positioning mode: Drag frames freely. Type /spreactive hide when done.")
end

-- Hide all frames and restore click-to-cast
function SP:HideAllReactiveFrames()
	local sv = ShamanPower_ReactiveTotems
	self.reactivePositioningMode = false

	for totemId, frame in pairs(self.reactiveFrames) do
		frame:Hide()

		-- Restore click-to-cast if enabled
		if sv.clickToCast then
			frame:SetAttribute("type1", "spell")
			frame:SetAttribute("spell1", frame.totemData.totemName)
		end
	end

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
	elseif msg == "show" then
		SP:ShowAllReactiveFrames()
	elseif msg == "hide" then
		SP:HideAllReactiveFrames()
	else
		-- Open ShamanPower options to Look & Feel > Reactive Totems using AceConfigDialog
		if LibStub and LibStub("AceConfigDialog-3.0", true) then
			LibStub("AceConfigDialog-3.0"):Open("ShamanPower")
			LibStub("AceConfigDialog-3.0"):SelectGroup("ShamanPower", "fluffy", "reactivetotems_section")
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
-- Module Initialization
-- ============================================================================

function SP:InitializeReactiveTotems()
	self:InitReactiveTotems()
	self:CreateAllReactiveFrames()
	self:SetupReactiveTotemsEvents()
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
