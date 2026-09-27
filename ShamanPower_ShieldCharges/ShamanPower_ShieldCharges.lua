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
		-- them. The core already hears exactly those units through the game's unit
		-- filter (player, party1-4 and the Earth Shield carrier's raid token, see
		-- SetupUnitEventFilters) and updates the charges this display reads, so the
		-- display wakes after the core's own handler. A frame of its own here heard
		-- every raid member and nameplate. (Counted in the core's stress rows.)
		hooksecurefunc(ShamanPower, "UNIT_AURA", function(_, _, unit)
			if unit ~= "player" and ShamanPower.esTrackedTargetGUID then SP._shieldWake = true end
		end)
		wake:SetScript("OnEvent", function(_, ev, unit)
			if ev == "UNIT_AURA" and unit ~= "player" and not ShamanPower.esTrackedTargetGUID then return end
			SP._shieldWake = true
		end)
	end
	-- Only enable if shield charge display is configured to show something (and ShamanPower is on)
	local showAny = ((settings.showPlayerShield ~= false) or earthShieldWanted(settings)) and not self:IsOff()
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

-- ============================================================================
-- Optional looks, all off by default (the plain number): the shield's icon
-- with the number on it (in the center, or smaller in the bottom-right corner)
-- and a segmented charge bar under it. The same parts are built twice - on the
-- display frame, drawn by the addon (out of combat, and always on clients
-- without secret auras), and on the engine's aura button, drawn by the game
-- while auras are secret - and placed by one function relative to a box that
-- covers the display frame exactly, so both pictures line up.
-- ============================================================================
local ICON_SIZE      = 48   -- the shield icon (square)
local NUMBER_SIZE    = 48   -- the plain number (the default look)
local NUMBER_ON_ICON = 34   -- the number centerd on the icon
local NUMBER_CORNER  = 20   -- the number in the icon's bottom-right corner
local NUMBER_BOTTOM  = 17   -- how far the plain number's digits reach below its center
local BAR_WIDTH, BAR_HEIGHT, BAR_GAP = 48, 7, 3
local MAX_CHARGES = { player = 3, earth = 6 }
local NO_SETTINGS = {}
-- The bar keeps the display's own color at every count: in combat the game
-- fills it and cannot recolor it by count, so out of combat does the same.
local SHIELD_COLOR = { player = { 0.2, 0.6, 1.0 }, earth = { 0.2, 0.8, 0.2 } }

-- Which parts a display shows. The number can only be off while the icon or
-- the bar is on, so a display is never drawn with nothing in it.
local function displayParts(settings)
	local icon = settings.showIcon and true or false
	local bar = settings.showChargeBar and true or false
	local number = (settings.showNumber ~= false) or not (icon or bar)
	local corner = (icon and number and settings.numberPosition == "corner") and true or false
	return icon, number, corner, bar
end

-- How far a display's parts reach from its center, in the frame's own units:
-- half its width, above, below. The setup tour lays the preview out by it.
function SP:ShieldChargeDisplayExtent(frame)
	local settings = self.opt.shieldChargeDisplay or NO_SETTINGS
	local s = settings.scale or 1
	local icon, number, _, bar = displayParts(settings)
	local halfW, above, below = 0, 0, 0
	if number and frame and frame.text then
		halfW = (frame.text:GetStringWidth() or 0) / 2
		above = (frame.text:GetStringHeight() or 0) / 2
		below = above
	end
	if icon then
		local h = ICON_SIZE / 2 * s
		halfW, above, below = math.max(halfW, h), math.max(above, h), math.max(below, h)
	end
	if bar then
		halfW = math.max(halfW, BAR_WIDTH / 2 * s)
		below = math.max(below, ((icon and ICON_SIZE / 2) or (number and NUMBER_BOTTOM) or 0) * s + (BAR_GAP + BAR_HEIGHT) * s)
	end
	return halfW, above, below
end

local function numberSize(icon, corner)
	if corner then return NUMBER_CORNER end
	if icon then return NUMBER_ON_ICON end
	return NUMBER_SIZE
end

-- Icon files, [1] Lightning Shield, [2] Water Shield, [3] Earth Shield: looked
-- up once, the first time an icon is drawn. The fallbacks ship with every client.
local ICON_FALLBACK = {
	"Interface\\Icons\\Spell_Nature_LightningShield",
	"Interface\\Icons\\Ability_Shaman_WaterShield",
	"Interface\\Icons\\Spell_Nature_SkinofEarth",
}
local shieldIcons
local function firstSpellIcon(ids)
	for _, id in ipairs(ids or {}) do
		local ok, tex = pcall(GetSpellTexture, id)
		if ok and tex then return tex end
		if GetSpellInfo then
			local ok2, _, _, tex2 = pcall(GetSpellInfo, id)
			if ok2 and tex2 then return tex2 end
		end
	end
end
local function shieldIcon(which)
	if not shieldIcons then
		shieldIcons = {}
		for _, set in ipairs(ShamanPower.ShieldAuraSets or {}) do
			if set.name == "Lightning Shield" then shieldIcons[1] = firstSpellIcon(set.ids)
			elseif set.name == "Water Shield" then shieldIcons[2] = firstSpellIcon(set.ids) end
		end
		shieldIcons[3] = firstSpellIcon(ES_SPELL_IDS)
		for i = 1, 3 do shieldIcons[i] = shieldIcons[i] or ICON_FALLBACK[i] end
	end
	return shieldIcons[which] or ICON_FALLBACK[1]
end

-- A segmented charge bar: one StatusBar filled to the count over a dark
-- backing, with thin dark dividers between the segments drawn over the fill.
local function createChargeBar(parent, kind)
	local n, c = MAX_CHARGES[kind], SHIELD_COLOR[kind]
	local bar = CreateFrame("StatusBar", nil, parent)
	local back = bar:CreateTexture(nil, "BACKGROUND")
	back:SetPoint("TOPLEFT", bar, "TOPLEFT", -1, 1)
	back:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 1, -1)
	back:SetColorTexture(0, 0, 0, 0.6)
	bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
	bar:SetStatusBarColor(c[1], c[2], c[3])
	bar:SetMinMaxValues(0, n)
	bar:SetValue(0)
	bar.dividers = {}
	for i = 1, n - 1 do
		local d = bar:CreateTexture(nil, "OVERLAY")
		d:SetColorTexture(0, 0, 0, 0.9)
		bar.dividers[i] = d
	end
	return bar
end

-- Place a display's parts on `box` (the display frame, or the engine's aura
-- button, which covers it exactly). Every part hangs off the box's center, and
-- the icon (or the plain number) stays where it is when the bar is added.
local function placeParts(box, s, icon, number, corner, iconTex, text, chargeBar)
	if iconTex then
		iconTex:ClearAllPoints()
		iconTex:SetSize(ICON_SIZE * s, ICON_SIZE * s)
		iconTex:SetPoint("CENTER", box, "CENTER", 0, 0)
	end
	if text then
		text:ClearAllPoints()
		if corner then
			text:SetPoint("BOTTOMRIGHT", box, "CENTER", (ICON_SIZE / 2 - 1) * s, -(ICON_SIZE / 2 - 1) * s)
		else
			text:SetPoint("CENTER", box, "CENTER", 0, 0)
		end
	end
	if chargeBar then
		local w = BAR_WIDTH * s
		chargeBar:ClearAllPoints()
		chargeBar:SetSize(w, BAR_HEIGHT * s)
		local below = (icon and ICON_SIZE / 2) or (number and NUMBER_BOTTOM) or nil
		if below then
			chargeBar:SetPoint("TOP", box, "CENTER", 0, -(below + BAR_GAP) * s)
		else
			chargeBar:SetPoint("CENTER", box, "CENTER", 0, 0)
		end
		local dividers = chargeBar.dividers
		local n = #dividers + 1
		local dw = math.max(1, math.floor(s + 0.5))
		for i = 1, #dividers do
			local d = dividers[i]
			d:ClearAllPoints()
			d:SetWidth(dw)
			d:SetPoint("TOP", chargeBar, "TOPLEFT", w * i / n, 0)
			d:SetPoint("BOTTOM", chargeBar, "BOTTOMLEFT", w * i / n, 0)
		end
	end
end

-- Draw one display with the addon's own parts. Restricted: the engine draws
-- the live state on top, so the addon's parts show only the empty state
-- (grayed icon, empty bar, and a red 0 when the icon is there to hide it), and
-- only while "Hide When No Shields" is off: the engine's icon covers them
-- while the shield is up. Below 100% opacity the red 0 would show through the
-- engine's live count, so in combat it is only drawn at full opacity (the
-- grayed icon and empty bar stay at any opacity).
-- iconWhich: 1 Lightning Shield, 2 Water Shield, 3 Earth Shield.
local function paintDisplay(frame, kind, settings, s, charges, present, restricted, iconWhich)
	local icon, number, corner, bar = displayParts(settings)
	if frame.layScale ~= s or frame.layIcon ~= icon or frame.layNumber ~= number
		or frame.layCorner ~= corner or frame.layBar ~= bar then
		frame.layScale, frame.layIcon, frame.layNumber, frame.layCorner, frame.layBar = s, icon, number, corner, bar
		if icon and not frame.icon then
			local t = frame:CreateTexture(nil, "ARTWORK")
			t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			t:Hide()
			frame.icon = t
		end
		if bar and not frame.chargeBar then
			frame.chargeBar = createChargeBar(frame, kind)
			frame.chargeBar:Hide()
		end
		placeParts(frame, s, icon, number, corner, icon and frame.icon, frame.text, bar and frame.chargeBar)
	end

	local own = not restricted or not settings.hideNoShields
	local text = frame.text
	local r, g, b = SP:GetShieldChargeColor(charges, MAX_CHARGES[kind], kind == "earth")
	-- restricted: our 0 sits under the engine's icon, which hides it while the
	-- shield is up at full opacity; without an icon nothing would hide it, and
	-- below 100% it would show through, so no 0 there
	local solid = (settings.opacity or 1) >= 1
	local shown = not number and "" or (not restricted and charges) or ((own and icon and solid) and "0" or "")
	text:SetText(shown)
	text:SetTextColor(r, g, b)
	SP:SetSPFont(text, "charges", numberSize(icon, corner) * s, "OUTLINE")

	local lit = present and not restricted
	local tex = frame.icon
	if tex then
		if icon and own then
			local file = shieldIcon(iconWhich)
			if frame.iconFile ~= file then
				tex:SetTexture(file)
				frame.iconFile = file
			end
			tex:SetDesaturated(not lit)
			tex:SetAlpha(lit and 1 or 0.45)
			tex:Show()
		else
			tex:Hide()
		end
	end
	local cb = frame.chargeBar
	if cb then
		if bar and own then
			cb:SetValue(lit and charges or 0)
			cb:Show()
		else
			cb:Hide()
		end
	end
end

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

-- The engine's button gets the same parts as the display frame (icon, number,
-- bar), laid out by the same placeParts, all before any of them is handed to
-- the game: the game fills in the icon, the count and the bar's value itself.
local function buildChargeContainer(frame, kind, scale, sets, icon, number, corner, bar)
	if C_AddOns and C_AddOns.LoadAddOn then pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer") end
	local ok, container = pcall(CreateFrame, "AuraContainer", nil, frame, "CustomAuraContainerTemplate")
	if not ok or not container then return nil end
	container:SetAllPoints(frame)
	container:SetFrameLevel(frame:GetFrameLevel() + 2)
	local isES = (kind == "earth")
	local maxCharges, c = MAX_CHARGES[kind], SHIELD_COLOR[kind]
	local interpolation = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate
	for _, set in ipairs(sets) do
		local idMap = {}
		for _, id in ipairs(set.ids) do idMap[id] = true end
		local which = isES and 3 or (set.name == "Water Shield" and 2 or 1)
		pcall(function()
			container:AddAuraSlot("charges_" .. set.name:gsub("%s", ""), "HELPFUL|PLAYER", {
				candidateFilters = { includeSpellIDs = idMap },
				initializeFrame = function(button)
					button:ClearAllPoints()
					button:SetAllPoints(frame)
					if button.SetMouseClickEnabled then pcall(button.SetMouseClickEnabled, button, false) end
					if button.SetMouseMotionEnabled then pcall(button.SetMouseMotionEnabled, button, false) end
					local iconTex, count, chargeBar
					if icon then
						-- this shield's own file, so the icon never depends on the game painting it
						iconTex = button:CreateTexture(nil, "ARTWORK")
						iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
						iconTex:SetTexture(shieldIcon(which))
					end
					if bar then chargeBar = createChargeBar(button, kind) end
					if number then
						local carrier = CreateFrame("Frame", nil, button)
						carrier:SetAllPoints(button)
						count = carrier:CreateFontString(nil, "OVERLAY")
						SP:SetSPFont(count, "charges", numberSize(icon, corner) * scale, "OUTLINE")
						count:SetTextColor(c[1], c[2], c[3])   -- fallback if the formatter is unavailable
					end
					placeParts(button, scale, icon, number, corner, iconTex, count, chargeBar)
					if iconTex then pcall(button.SetIcon, button, iconTex) end
					if chargeBar then
						pcall(button.SetApplicationBar, button, chargeBar,
							{ maxApplications = maxCharges, minApplications = 0, interpolation = interpolation })
					end
					if count then
						pcall(button.SetApplicationCount, button, count,
							{ formatter = chargeFormatter(maxCharges, isES) })
					end
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

-- Make sure each frame has an engine container for the current look and unit.
-- The engine button's parts are laid out once, when the game builds it: a new
-- scale or a different set of parts (icon, number, corner, bar) needs a new one.
function SP:EnsureShieldChargeEngine(frame, kind, scale)
	if not (SPCompat and SPCompat.secretsRegime) then return end
	local icon, number, corner, bar = displayParts(self.opt.shieldChargeDisplay or NO_SETTINGS)
	if frame.engine and (frame.engineScale ~= scale or frame.engineIcon ~= icon or frame.engineNumber ~= number
		or frame.engineCorner ~= corner or frame.engineBar ~= bar) then
		frame.engine:Hide()
		pcall(frame.engine.SetUnit, frame.engine, "none")   -- the old one stops following auras
		frame.engine = nil
	end
	if not frame.engine then
		-- player: blue, like the module at full charges; Earth Shield: green
		local sets = (kind == "player") and (ShamanPower.ShieldAuraSets or {}) or { { name = "Earth Shield", ids = ES_SPELL_IDS } }
		frame.engine = buildChargeContainer(frame, kind, scale, sets, icon, number, corner, bar)
		frame.engineScale = scale
		frame.engineIcon, frame.engineNumber, frame.engineCorner, frame.engineBar = icon, number, corner, bar
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

	-- ShamanPower switched off: no numbers, and the update stops
	if self:IsOff() then
		self:DisableUpdateSubsystem("shieldCharge")
		if self.shieldChargeFrames.player then self.shieldChargeFrames.player:Hide() end
		if self.shieldChargeFrames.earth then self.shieldChargeFrames.earth:Hide() end
		return
	end

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
		local hasShield = false
		local water = false   -- Water Shield (not Lightning Shield): which icon to draw

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
				charges, hasShield, water = sc.charges, sc.hasShield, sc.water
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
					water = name:find("Water Shield") and true or false
					break
				end
			end
			sc.gen, sc.at, sc.charges, sc.hasShield = ShamanPower.auraGen and ShamanPower.auraGen["player"] or 0, GetTime(), charges, hasShield
			sc.water = water
			end
			-- the icon shown with no shield up (and under the engine's in combat) is the last one seen
			if hasShield then self._shieldLastWater = water end
		end
		if playerFrame.engine then playerFrame.engine:SetShown(restricted) end

		-- Determine visibility
		local shouldShow = hasShield or not hideNoShields
		if hideOOC and not inCombat then
			shouldShow = false
		end

		if shouldShow then
			if not (hasShield and not restricted) then
				-- no shield to read: the last one seen, else the preferred shield
				water = self._shieldLastWater
				if water == nil then water = (self.opt.preferredShield == 2) end
			end
			paintDisplay(playerFrame, "player", settings, scale, charges, hasShield, restricted, water and 2 or 1)
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
			paintDisplay(earthFrame, "earth", settings, scale, charges, hasShield, restricted, 3)
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
-- the same font/scale/opacity rules and parts (icon, bar) as the live display.
function SP:ShieldChargesDemoRefresh()
	local playerFrame = self.shieldChargeFrames.player
	local earthFrame = self.shieldChargeFrames.earth
	if not playerFrame or not earthFrame then return end
	local settings = self.opt.shieldChargeDisplay or {}
	local scale, opacity = settings.scale or 1.0, settings.opacity or 1.0
	local d = self.shieldChargesDemoState or { player = 3, earth = 6 }

	if settings.showPlayerShield ~= false then
		-- Lightning Shield, like the character on stage; at 0 it shows the no-shield look
		paintDisplay(playerFrame, "player", settings, scale, d.player, d.player > 0, false, 1)
		playerFrame:SetAlpha(opacity)
		playerFrame:EnableMouse(false)
		playerFrame:Show()
	else
		playerFrame:Hide()
	end
	if earthShieldWanted(settings) then
		paintDisplay(earthFrame, "earth", settings, scale, d.earth, d.earth > 0, false, 3)
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

-- Enable ShamanPower switched: hide the numbers (off), or show them as the settings say (on)
SP:OnOnOff(function() SP:UpdateShieldChargeDisplays() end)
