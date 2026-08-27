-- ============================================================================
-- ShamanPower Shield Charge Display Module
-- Large on-screen numbers showing your shield charges and Earth Shield charges
-- ============================================================================

local SP = ShamanPower
if not SP then return end

-- Mark module as loaded
SP.ShieldChargesLoaded = true

-- ============================================================================
-- Shield Charge Display (large on-screen numbers)
-- ============================================================================

SP.shieldChargeFrames = {}

-- Create or update the shield charge display frames
function SP:CreateShieldChargeDisplays()
	local settings = self.opt.shieldChargeDisplay
	if not settings then
		self:EnsureProfileTable("shieldChargeDisplay")
		settings = self.opt.shieldChargeDisplay
	end

	-- Create player shield frame (Lightning/Water Shield)
	if not self.shieldChargeFrames.player then
		local frame = CreateFrame("Frame", "ShamanPowerPlayerShieldCharge", UIParent)
		frame:SetSize(60, 60)
		frame:SetPoint("CENTER", UIParent, "CENTER", settings.playerShieldX or -50, settings.playerShieldY or -100)
		frame:SetFrameStrata("MEDIUM")

		local text = frame:CreateFontString(nil, "OVERLAY")
		text:SetFont("Fonts\\FRIZQT__.TTF", 48, "OUTLINE")
		text:SetPoint("CENTER", frame, "CENTER", 0, 0)
		text:SetTextColor(0.2, 0.6, 1.0)  -- Blue for Lightning/Water Shield
		frame.text = text

		-- Make movable when unlocked
		frame:SetMovable(true)
		frame:RegisterForDrag("LeftButton")
		frame:SetScript("OnDragStart", function(self)
			if not SP.opt.shieldChargeDisplay.locked then
				self:StartMoving()
			end
		end)
		frame:SetScript("OnDragStop", function(self)
			self:StopMovingOrSizing()
			local _, _, _, x, y = self:GetPoint()
			SP.opt.shieldChargeDisplay.playerShieldX = x
			SP.opt.shieldChargeDisplay.playerShieldY = y
		end)

		frame:Hide()
		self.shieldChargeFrames.player = frame
	end

	-- Create Earth Shield frame
	if not self.shieldChargeFrames.earth then
		local frame = CreateFrame("Frame", "ShamanPowerEarthShieldCharge", UIParent)
		frame:SetSize(60, 60)
		frame:SetPoint("CENTER", UIParent, "CENTER", settings.earthShieldX or 50, settings.earthShieldY or -100)
		frame:SetFrameStrata("MEDIUM")

		local text = frame:CreateFontString(nil, "OVERLAY")
		text:SetFont("Fonts\\FRIZQT__.TTF", 48, "OUTLINE")
		text:SetPoint("CENTER", frame, "CENTER", 0, 0)
		text:SetTextColor(0.2, 0.8, 0.2)  -- Green for Earth Shield
		frame.text = text

		-- Make movable when unlocked
		frame:SetMovable(true)
		frame:RegisterForDrag("LeftButton")
		frame:SetScript("OnDragStart", function(self)
			if not SP.opt.shieldChargeDisplay.locked then
				self:StartMoving()
			end
		end)
		frame:SetScript("OnDragStop", function(self)
			self:StopMovingOrSizing()
			local _, _, _, x, y = self:GetPoint()
			SP.opt.shieldChargeDisplay.earthShieldX = x
			SP.opt.shieldChargeDisplay.earthShieldY = y
		end)

		frame:Hide()
		self.shieldChargeFrames.earth = frame
	end

	-- Register shield charge updates with consolidated update system (10fps)
	if not self.updateSystem.subsystems["shieldCharge"] then
		self:RegisterUpdateSubsystem("shieldCharge", 0.1, function()
			SP:UpdateShieldChargeDisplays()
		end)
	end
	-- Only enable if shield charge display is configured to show something
	local showAny = (settings.showPlayerShield ~= false) or (settings.showEarthShield ~= false)
	if showAny then
		self:EnableUpdateSubsystem("shieldCharge")
	else
		self:DisableUpdateSubsystem("shieldCharge")
	end

	self:UpdateShieldChargeDisplays()
end

-- Get color based on charges remaining
function SP:GetShieldChargeColor(charges, maxCharges, isEarthShield)
	if isEarthShield then
		-- Earth Shield: 6 charges max, yellow at 3, red at 1-2
		if charges >= 4 then
			return 0.2, 0.8, 0.2  -- Green
		elseif charges >= 3 then
			return 1.0, 0.8, 0.0  -- Yellow
		else
			return 1.0, 0.2, 0.2  -- Red
		end
	else
		-- Lightning/Water Shield: 3-4 charges max, yellow at 2, red at 1
		if charges >= 3 then
			return 0.2, 0.6, 1.0  -- Blue (full)
		elseif charges == 2 then
			return 1.0, 0.8, 0.0  -- Yellow (medium)
		else
			return 1.0, 0.2, 0.2  -- Red (low)
		end
	end
end

-- Update the shield charge displays
function SP:UpdateShieldChargeDisplays()
	if self.shieldChargesDemoActive then return end
	local settings = self.opt.shieldChargeDisplay
	if not settings then return end

	-- Enable/disable the shieldCharge subsystem based on settings
	local showAny = (settings.showPlayerShield ~= false) or (settings.showEarthShield ~= false)
	if showAny then
		self:EnableUpdateSubsystem("shieldCharge")
	else
		self:DisableUpdateSubsystem("shieldCharge")
	end

	local playerFrame = self.shieldChargeFrames.player
	local earthFrame = self.shieldChargeFrames.earth
	if not playerFrame or not earthFrame then return end

	local scale = settings.scale or 1.0
	local opacity = settings.opacity or 1.0
	local locked = settings.locked
	local hideOOC = settings.hideOutOfCombat
	local hideNoShields = settings.hideNoShields

	-- Check combat state
	local inCombat = InCombatLockdown() or UnitAffectingCombat("player")

	-- Update player shield (Lightning/Water Shield)
	if settings.showPlayerShield ~= false then
		local charges = 0
		local maxCharges = 3  -- Default for Lightning/Water Shield
		local hasShield = false

		-- Check for Lightning Shield or Water Shield
		for i = 1, 40 do
			local name, _, count, _, _, _, _, _, _, spellId = UnitBuff("player", i)
			if not name then break end
			if name:find("Lightning Shield") or name:find("Water Shield") then
				charges = count or 0
				-- If charges is 0 but we have the buff, it might be stored differently
				if charges == 0 then
					-- Try getting it from the 3rd return value directly
					local _, _, c = UnitBuff("player", i)
					charges = c or 3  -- Default to 3 if we can't get count
				end
				hasShield = true
				break
			end
		end

		-- Determine visibility
		local shouldShow = hasShield or not hideNoShields
		if hideOOC and not inCombat then
			shouldShow = false
		end

		if shouldShow then
			local r, g, b = self:GetShieldChargeColor(charges, maxCharges, false)
			playerFrame.text:SetText(charges)
			playerFrame.text:SetTextColor(r, g, b)
			playerFrame.text:SetFont("Fonts\\FRIZQT__.TTF", 48 * scale, "OUTLINE")
			playerFrame:SetAlpha(opacity)
			playerFrame:EnableMouse(not locked)
			playerFrame:Show()
		else
			playerFrame:Hide()
		end
	else
		playerFrame:Hide()
	end

	-- Update Earth Shield
	if settings.showEarthShield ~= false then
		local charges = 0
		local maxCharges = 6  -- Earth Shield has 6 charges
		local hasShield = false

		-- Get Earth Shield charges from FindEarthShieldTarget
		local esTarget, esCharges = self:FindEarthShieldTarget()
		if esTarget and esCharges and esCharges > 0 then
			charges = esCharges
			hasShield = true
		end

		-- Determine visibility
		local shouldShow = hasShield or not hideNoShields
		if hideOOC and not inCombat then
			shouldShow = false
		end

		if shouldShow then
			local r, g, b = self:GetShieldChargeColor(charges, maxCharges, true)
			earthFrame.text:SetText(charges)
			earthFrame.text:SetTextColor(r, g, b)
			earthFrame.text:SetFont("Fonts\\FRIZQT__.TTF", 48 * scale, "OUTLINE")
			earthFrame:SetAlpha(opacity)
			earthFrame:EnableMouse(not locked)
			earthFrame:Show()
		else
			earthFrame:Hide()
		end
	else
		earthFrame:Hide()
	end
end

-- ============================================================================
-- Setup wizard preview: fill both shield frames with sample charge counts
-- ============================================================================
-- Setup-wizard preview: show BOTH numbers with simulated charges being used
-- up (blue/green -> yellow -> red) and the shields re-applied, rendered with
-- the same font/scale/opacity rules as the live display.
function SP:ShieldChargesDemoRefresh()
	local playerFrame = self.shieldChargeFrames.player
	local earthFrame = self.shieldChargeFrames.earth
	if not playerFrame or not earthFrame then return end
	local settings = self.opt.shieldChargeDisplay or {}
	local scale, opacity = settings.scale or 1.0, settings.opacity or 1.0
	local d = self.shieldChargesDemoState or { player = 3, earth = 6 }

	if settings.showPlayerShield ~= false then
		local r, g, b = self:GetShieldChargeColor(d.player, 3, false)
		playerFrame.text:SetText(d.player)
		playerFrame.text:SetTextColor(r, g, b)
		playerFrame.text:SetFont("Fonts\\FRIZQT__.TTF", 48 * scale, "OUTLINE")
		playerFrame:SetAlpha(opacity)
		playerFrame:EnableMouse(false)
		playerFrame:Show()
	else
		playerFrame:Hide()
	end
	if settings.showEarthShield ~= false then
		local r, g, b = self:GetShieldChargeColor(d.earth, 6, true)
		earthFrame.text:SetText(d.earth)
		earthFrame.text:SetTextColor(r, g, b)
		earthFrame.text:SetFont("Fonts\\FRIZQT__.TTF", 48 * scale, "OUTLINE")
		earthFrame:SetAlpha(opacity)
		earthFrame:EnableMouse(false)
		earthFrame:Show()
	else
		earthFrame:Hide()
	end
end

function SP:ShieldChargesDemo(on)
	if on then
		self:CreateShieldChargeDisplays()
		if not (self.shieldChargeFrames.player and self.shieldChargeFrames.earth) then return end
		if self.shieldChargesDemoActive then
			self:ShieldChargesDemoRefresh()   -- re-entrant: options changed
			return
		end
		self.shieldChargesDemoActive = true
		self.shieldChargesDemoState = { player = 3, earth = 6 }
		if self.shieldChargesDemoTicker then self.shieldChargesDemoTicker:Cancel() end
		local tick = 0
		self.shieldChargesDemoTicker = C_Timer.NewTicker(1.2, function()
			if not self.shieldChargesDemoActive then return end
			tick = tick + 1
			local d = self.shieldChargesDemoState
			-- player shield loses a charge every tick; re-applied after 0
			d.player = d.player - 1
			if d.player < 0 then d.player = 3 end
			-- earth shield loses a charge every other tick (it lasts longer)
			if tick % 2 == 0 then
				d.earth = d.earth - 1
				if d.earth < 0 then d.earth = 6 end
			end
			self:ShieldChargesDemoRefresh()
		end)
		self:ShieldChargesDemoRefresh()
	else
		self.shieldChargesDemoActive = nil
		if self.shieldChargesDemoTicker then self.shieldChargesDemoTicker:Cancel(); self.shieldChargesDemoTicker = nil end
		self.shieldChargesDemoState = nil
		local settings = self.opt.shieldChargeDisplay
		local locked = settings and settings.locked
		if self.shieldChargeFrames.player then self.shieldChargeFrames.player:EnableMouse(not locked) end
		if self.shieldChargeFrames.earth then self.shieldChargeFrames.earth:EnableMouse(not locked) end
		self:UpdateShieldChargeDisplays()
	end
end

if ShamanPower.RegisterPreview then
	ShamanPower:RegisterPreview("shieldcharges", {
		frames = {
			function()
				if not SP.shieldChargeFrames.player then SP:CreateShieldChargeDisplays() end
				return SP.shieldChargeFrames.player
			end,
			function() return SP.shieldChargeFrames.earth end,
		},
		demo = "SP:ShieldChargesDemo",
		pad = 24,
	})
end
