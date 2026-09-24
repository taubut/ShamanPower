-- ============================================================================
-- ShamanPower Shield Charge Display Module
-- Large on-screen numbers showing your shield charges and Earth Shield charges
-- ============================================================================

local SP = ShamanPower
if not SP then return end
-- Only load for Shamans (the core keeps no-op stubs for everything this module provides)
if select(2, UnitClass("player")) ~= "SHAMAN" then return end

-- Mark module as loaded
SP.ShieldChargesLoaded = true

-- ============================================================================
-- Shield Charge Display (large on-screen numbers)
-- ============================================================================

SP.shieldChargeFrames = {}

-- Create or update the shield charge display frames
-- Earth Shield does not exist on every client (WoW: Forever has none): the
-- second number, its options and its preview stand down there.
local function earthShieldWanted(settings)
	if ShamanPower.ESTrackerUnavailable then return false end
	return settings.showEarthShield ~= false
end

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
		SP:SetSPFont(text, "charges", 48, "OUTLINE")
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
		SP:SetSPFont(text, "charges", 48, "OUTLINE")
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
		-- What this display shows changes with the player's (or the Earth Shield target's)
		-- auras and with entering / leaving combat - in combat on a restricted client the
		-- engine draws the count by itself and this function only decides visibility. So it
		-- runs when one of those events asks, and once a second as a safety net, instead of
		-- ten times a second (measured with /spperf: the top idle cost, and 3 KB/s in combat).
		local idleTicks = 0
		self:RegisterUpdateSubsystem("shieldCharge", 0.1, function()
			if not SP._shieldWake then
				idleTicks = idleTicks + 1
				if idleTicks < 10 then return end
			end
			idleTicks = 0
			SP._shieldWake = nil
			SP:UpdateShieldChargeDisplays()
		end)
		local wake = CreateFrame("Frame")
		if SPCompat and SPCompat.StressRegister then SPCompat.StressRegister(wake, "Shield Charges") end
		for _, ev in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "SPELLS_CHANGED" }) do
			pcall(wake.RegisterEvent, wake, ev)
		end
		-- your own auras through the game's unit filter: a raid's other 39 members
		-- and every nameplate no longer reach this handler
		if wake.RegisterUnitEvent then
			wake:RegisterUnitEvent("UNIT_AURA", "player")
		else
			wake:RegisterEvent("UNIT_AURA")
		end
		-- someone else's auras only matter while an Earth Shield is being tracked on
		-- them, so only a shaman who knows Earth Shield listens to other units at all
		local others = CreateFrame("Frame")
		others:SetScript("OnEvent", function()
			if ShamanPower.esTrackedTargetGUID then SP._shieldWake = true end
		end)
		local othersOn = false
		local function refreshOthers()
			local want = not SP.ESTrackerUnavailable and IsSpellKnown
				and (IsSpellKnown(974) or IsSpellKnown(32593) or IsSpellKnown(32594)) or false
			if want and not othersOn then others:RegisterEvent("UNIT_AURA")
			elseif not want and othersOn then others:UnregisterEvent("UNIT_AURA") end
			othersOn = want
		end
		refreshOthers()
		wake:SetScript("OnEvent", function(_, ev, unit)
			if ev == "SPELLS_CHANGED" or ev == "PLAYER_ENTERING_WORLD" then refreshOthers() end
			if ev == "UNIT_AURA" and unit ~= "player" and not ShamanPower.esTrackedTargetGUID then return end
			SP._shieldWake = true
		end)
	end
	-- Only enable if shield charge display is configured to show something
	local showAny = (settings.showPlayerShield ~= false) or earthShieldWanted(settings)
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
-- ============================================================================
-- Restricted clients (retail rules): while auras are secret the charge numbers
-- are drawn by the engine. Each display frame gets an AuraContainer whose aura
-- button carries a FontString in the same font/size/position (white); the
-- container is shown only while restricted and the addon's own text is blank.
-- The Earth Shield container is pointed at the group token of the player who
-- carries your shield, and re-pointed whenever that changes.
-- ============================================================================
function SP:ShieldChargesRestricted()
	return SPCompat and SPCompat.secretsRegime and SPCompat.AnyRestrictionActive and SPCompat.AnyRestrictionActive() or false
end

local ES_SPELL_IDS = { 974, 32593, 32594, 383648 }   -- Earth Shield ranks; retail's AURA is 383648 (cast 974)

-- The engine draws the count and never shows us the number, but it applies a
-- NumericRuleFormatter we hand it first (CustomAuraButtonApplicationCountOptions
-- .formatter, per the client's own API docs). One breakpoint per count decides
-- the text and colour, which is how 1 gets drawn at all: by default the client
-- hides a count of 1, the way stack counts work everywhere else.
local function chargeFormatter(maxCharges, isES)
	if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter) then return nil end
	local ok, fmt = pcall(C_StringUtil.CreateNumericRuleFormatter)
	if not ok or not fmt or not fmt.AddBreakpoint then return nil end
	for n = 0, maxCharges do
		local cr, cg, cb = ShamanPower:GetShieldChargeColor(n, maxCharges, isES)
		pcall(fmt.AddBreakpoint, fmt, {
			threshold = n,
			format = ("|cff%02x%02x%02x%%d|r"):format(
				math.floor(cr * 255 + 0.5), math.floor(cg * 255 + 0.5), math.floor(cb * 255 + 0.5)),
		})
	end
	return fmt
end

local function buildChargeContainer(frame, scale, sets, r, g, b)
	if C_AddOns and C_AddOns.LoadAddOn then pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer") end
	local ok, container = pcall(CreateFrame, "AuraContainer", nil, frame, "CustomAuraContainerTemplate")
	if not ok or not container then return nil end
	container:SetAllPoints(frame)
	container:SetFrameLevel(frame:GetFrameLevel() + 2)
	for _, set in ipairs(sets) do
		local idMap = {}
		for _, id in ipairs(set.ids) do idMap[id] = true end
		pcall(function()
			container:AddAuraSlot("charges_" .. set.name:gsub("%s", ""), "HELPFUL|PLAYER", {
				candidateFilters = { includeSpellIDs = idMap },
				initializeFrame = function(button)
					button:ClearAllPoints()
					button:SetAllPoints(frame)
					if button.SetMouseClickEnabled then pcall(button.SetMouseClickEnabled, button, false) end
					if button.SetMouseMotionEnabled then pcall(button.SetMouseMotionEnabled, button, false) end
					local carrier = CreateFrame("Frame", nil, button)
					carrier:SetAllPoints(button)
					local count = carrier:CreateFontString(nil, "OVERLAY")
					SP:SetSPFont(count, "charges", 48 * scale, "OUTLINE")
					count:SetPoint("CENTER", button, "CENTER", 0, 0)
					count:SetTextColor(r or 1, g or 1, b or 1)   -- fallback if the formatter is unavailable
					local isES = (set.name == "Earth Shield")
					pcall(button.SetApplicationCount, button, count,
						{ formatter = chargeFormatter(isES and 6 or 3, isES) })
				end,
			})
		end)
	end
	container:Hide()
	return container
end

-- Group token of the player carrying your Earth Shield (nil if not in view)
function SP:EarthShieldTargetToken()
	local guid = ShamanPower.esTrackedTargetGUID
	if not guid then return nil end
	local tokens = { "player" }
	for i = 1, 4 do tokens[#tokens + 1] = "party" .. i end
	if IsInRaid() then for i = 1, 40 do tokens[#tokens + 1] = "raid" .. i end end
	for _, u in ipairs(tokens) do
		if UnitExists(u) and UnitGUID(u) == guid then return u end
	end
	return nil
end

-- Make sure each frame has an engine container for the current scale and unit
function SP:EnsureShieldChargeEngine(frame, kind, scale)
	if not (SPCompat and SPCompat.secretsRegime) then return end
	if frame.engine and frame.engineScale ~= scale then
		frame.engine:Hide()
		frame.engine = nil
	end
	if not frame.engine then
		local sets = (kind == "player") and (ShamanPower.ShieldAuraSets or {}) or { { name = "Earth Shield", ids = ES_SPELL_IDS } }
		if kind == "player" then
			frame.engine = buildChargeContainer(frame, scale, sets, 0.2, 0.6, 1.0)   -- blue, like the module at full charges
		else
			frame.engine = buildChargeContainer(frame, scale, sets, 0.2, 0.8, 0.2)   -- green
		end
		frame.engineScale = scale
		frame.engineUnit = nil
	end
	local c = frame.engine
	if not c then return end
	local unit = (kind == "player") and "player" or (self:EarthShieldTargetToken() or "none")
	if frame.engineUnit ~= unit then
		frame.engineUnit = unit
		pcall(c.SetUnit, c, unit)
		pcall(c.UpdateAllAuras, c)
	end
end

function SP:UpdateShieldChargeDisplays()
	if self.shieldChargesDemoActive then return end
	local settings = self.opt.shieldChargeDisplay
	if not settings then return end

	-- Enable/disable the shieldCharge subsystem based on settings
	local showAny = (settings.showPlayerShield ~= false) or earthShieldWanted(settings)
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

		local restricted = self:ShieldChargesRestricted()
		if restricted then
			-- auras are secret: the engine draws the count (nothing while no shield)
			hasShield = true
			self:EnsureShieldChargeEngine(playerFrame, "player", scale)
		else
			-- Check for Lightning Shield or Water Shield; the answer holds until the next aura event
			local sc = self._shieldChargeScan
			if not sc then sc = {}; self._shieldChargeScan = sc end
			if self.AuraCacheValid and self:AuraCacheValid("player", sc.gen, sc.at) then
				charges, hasShield = sc.charges, sc.hasShield
			else
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
			sc.gen, sc.at, sc.charges, sc.hasShield = ShamanPower.auraGen and ShamanPower.auraGen["player"] or 0, GetTime(), charges, hasShield
			end
		end
		if playerFrame.engine then playerFrame.engine:SetShown(restricted) end

		-- Determine visibility
		local shouldShow = hasShield or not hideNoShields
		if hideOOC and not inCombat then
			shouldShow = false
		end

		if shouldShow then
			local r, g, b = self:GetShieldChargeColor(charges, maxCharges, false)
			playerFrame.text:SetText(restricted and "" or charges)
			playerFrame.text:SetTextColor(r, g, b)
			SP:SetSPFont(playerFrame.text, "charges", 48 * scale, "OUTLINE")
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
	if earthShieldWanted(settings) then
		local charges = 0
		local maxCharges = 6  -- Earth Shield has 6 charges
		local hasShield = false

		local restricted = self:ShieldChargesRestricted()
		if restricted then
			-- auras are secret: the engine draws the count on the tracked target
			hasShield = ShamanPower.esTrackedTargetGUID ~= nil
			self:EnsureShieldChargeEngine(earthFrame, "earth", scale)
		else
			-- Get Earth Shield charges from FindEarthShieldTarget
			local esTarget, esCharges = self:FindEarthShieldTarget()
			if esTarget and esCharges and esCharges > 0 then
				charges = esCharges
				hasShield = true
			end
		end
		if earthFrame.engine then earthFrame.engine:SetShown(restricted) end

		-- Determine visibility
		local shouldShow = hasShield or not hideNoShields
		if hideOOC and not inCombat then
			shouldShow = false
		end

		if shouldShow then
			local r, g, b = self:GetShieldChargeColor(charges, maxCharges, true)
			earthFrame.text:SetText(restricted and "" or charges)
			earthFrame.text:SetTextColor(r, g, b)
			SP:SetSPFont(earthFrame.text, "charges", 48 * scale, "OUTLINE")
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
		SP:SetSPFont(playerFrame.text, "charges", 48 * scale, "OUTLINE")
		playerFrame:SetAlpha(opacity)
		playerFrame:EnableMouse(false)
		playerFrame:Show()
	else
		playerFrame:Hide()
	end
	if earthShieldWanted(settings) then
		local r, g, b = self:GetShieldChargeColor(d.earth, 6, true)
		earthFrame.text:SetText(d.earth)
		earthFrame.text:SetTextColor(r, g, b)
		SP:SetSPFont(earthFrame.text, "charges", 48 * scale, "OUTLINE")
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
			-- the staged character (preview) acts it out: shield gone at 0, recast brings it back
			if self.PreviewStageEvent then
				if d.player == 0 then self:PreviewStageEvent("cast") elseif d.player == 3 then self:PreviewStageEvent("aura") end
			end
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
			function() if ShamanPower.ESTrackerUnavailable then return nil end; return SP.shieldChargeFrames.earth end,
		},
		demo = "SP:ShieldChargesDemo",
		pad = 24,
		stage = "player",   -- the player's own character behind the number: it floats near them on screen
		stageKit = 292,     -- Lightning Shield's aura visual (SpellVisualEvent kit for spell visual 37, Forever 1.60.1 data)
		stageCastKit = 237275,   -- its cast visual, played once when the demo recasts
	})
end
