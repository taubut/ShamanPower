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

-- Buff names that totems apply to party members (used for range detection)
-- Use partial names to match more reliably across different versions/localizations
-- NOTE: Some totems (like Windfury) don't apply visible buffs detectable via UnitBuff
SP.TotemBuffNames = {
	[1] = {  -- Earth
		[1] = "Strength of Earth",
		[2] = "Stoneskin",
		-- Tremor, Earthbind, Stoneclaw, Earth Elemental don't have party buffs
	},
	[2] = {  -- Fire
		[1] = "Totem of Wrath",
		[5] = "Flametongue",
		[6] = "Frost Resistance",
		-- Searing, Magma, Fire Nova are damage totems with no party buff
	},
	[3] = {  -- Water
		[1] = "Mana Spring",
		[2] = "Healing Stream",  -- This heals, doesn't buff
		[3] = "Mana Tide",
		[6] = "Fire Resistance",
		-- Poison/Disease cleansing don't have visible buffs
	},
	[4] = {  -- Air
		-- [1] = Windfury Totem - uses broadcast system since we can't check other players' buffs
		[2] = "Grace of Air",
		[3] = "Wrath of Air",
		[4] = "Tranquil Air",
		[6] = "Nature Resistance",
		[7] = "Windwall",
	},
}

-- Create party range dots for a totem button
function SP:CreatePartyRangeDots(button, element)
	if not button then return end
	if self.partyRangeDots[element] then return end  -- Already created

	self.partyRangeDots[element] = {}

	for i = 1, 4 do
		local dot = button:CreateTexture(nil, "OVERLAY")
		dot:SetTexture("Interface\\AddOns\\ShamanPower\\textures\\dot")
		dot:SetSize(5, 5)  -- Smaller dots for inside corners

		-- Position dots inside the button corners (2x2 grid)
		-- 1=top-left, 2=top-right, 3=bottom-left, 4=bottom-right
		if i == 1 then
			dot:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
		elseif i == 2 then
			dot:SetPoint("TOPRIGHT", button, "TOPRIGHT", -1, -1)
		elseif i == 3 then
			dot:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 1, 1)
		else
			dot:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
		end

		dot:SetVertexColor(1, 1, 1)  -- Default white, will be colored by class
		dot:Hide()
		self.partyRangeDots[element][i] = dot
	end
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
		self:RegisterUpdateSubsystem("partyRange", 0.5, function()
			SP:UpdatePartyRangeDots()
			SP:UpdatePlayerTotemRange()
		end)
	end
	-- Only enable if party buff tracker features are on
	if self.opt.showPartyRangeDots or self.opt.showRangeCounters then
		self:EnableUpdateSubsystem("partyRange")
	else
		self:DisableUpdateSubsystem("partyRange")
	end
end

-- Get the buff name for the currently active totem of an element
function SP:GetActiveTotemBuffName(element)
	local slot = self.ElementToSlot[element]
	if not slot then return nil end

	local haveTotem, totemName = GetTotemInfo(slot)
	if not haveTotem or not totemName then return nil end

	local buffNames = self.TotemBuffNames[element]
	if not buffNames then return nil end

	-- Match based on actual totem name from GetTotemInfo (not assignments!)
	-- This ensures we check the buff for the ACTIVE totem, not the assigned one
	-- Strip rank number from totem name for matching (e.g., "Windfury Totem VII" -> "Windfury Totem")
	local totemBaseName = totemName:gsub("%s+[IVXLCDM]+$", ""):gsub("%s+%d+$", "")
	local totemLower = totemBaseName:lower()
	local fullNameLower = totemName:lower()

	for totemIndex, buffName in pairs(buffNames) do
		if type(buffName) == "string" then
			local buffLower = buffName:lower()
			-- Check if totem name contains the buff search term
			if totemLower:find(buffLower, 1, true) or fullNameLower:find(buffLower, 1, true) then
				return buffName
			end
		end
	end

	-- No matching buff found - this totem doesn't have a trackable buff
	-- (e.g., Tremor, Disease Cleansing, Searing, etc.)
	return nil
end

-- Check if a unit has a specific buff (optimized for performance)
function SP:UnitHasBuff(unit, buffName)
	if not buffName then return false end

	-- Use optimized API if available (Retail/newer Classic)
	if AuraUtil and AuraUtil.FindAuraByName then
		return AuraUtil.FindAuraByName(buffName, unit) ~= nil
	end

	-- Fallback: scan first 20 buffs (totems are usually early in the list)
	for i = 1, 20 do
		local name = UnitBuff(unit, i)
		if not name then break end
		-- Case-insensitive partial match
		if name:lower():find(buffName:lower(), 1, true) then
			return true
		end
	end
	return false
end

-- Reusable table for party units (avoids creating garbage every call)
SP.partyUnitsCache = {}
SP.emptyTable = {}  -- Shared empty table for early returns

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
	for i = 1, numMembers do
		if UnitExists("party" .. i) then
			count = count + 1
			partyUnits[count] = "party" .. i
		end
	end

	return partyUnits, count
end

-- Update all party range dots
function SP:UpdatePartyRangeDots()
	-- Always update range counters (even if dots are disabled)
	self:UpdateRangeCounters()

	-- Enable/disable partyRange subsystem based on whether any tracking is enabled
	local rangeCounterEnabled = self.opt.rangeCounter and self.opt.rangeCounter.enabled
	local trackingEnabled = self.opt.showPartyRangeDots or rangeCounterEnabled
	if trackingEnabled then
		self:EnableUpdateSubsystem("partyRange")
	else
		self:DisableUpdateSubsystem("partyRange")
	end

	-- Check if dots feature is enabled
	if not self.opt.showPartyRangeDots then
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
	-- If solo, partyUnits is empty (no dots shown)

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
					-- Also hide the other dot
					if useOverlay and mainDot then mainDot:Hide() end
				else
					local slot = self.ElementToSlot[element]
					local haveTotem, totemName = GetTotemInfo(slot)

					if haveTotem then
						-- Totem is active - check if party member has the buff
						local buffName = self:GetActiveTotemBuffName(element)
						local hasBuff = buffName and self:UnitHasBuff(unit, buffName)

						-- Special case: Air element (4) with no buffName = Windfury Totem
						-- We can't check other players' buffs with UnitBuff, so use
						-- the broadcast system where each player reports their own buff status
						-- Only show dots for players who have ShamanPower and are reporting
						local isWindfury = (element == 4 and not buffName)
						if isWindfury then
							local playerName = UnitName(unit)
							local wfStatus = self:IsPlayerInWindfuryRange(playerName)
							if wfStatus == true then
								-- Player reported having Windfury enchant - in range
								if classColor then
									dot:SetVertexColor(classColor.r, classColor.g, classColor.b)
								else
									dot:SetVertexColor(0, 1, 0)  -- Green
								end
								dot:Show()
								if useOverlay and mainDot then mainDot:Hide() end
							elseif wfStatus == false then
								-- Player reported NOT having Windfury enchant - out of range
								dot:SetVertexColor(1, 0, 0)
								dot:Show()
								if useOverlay and mainDot then mainDot:Hide() end
							else
								-- No data - player doesn't have ShamanPower, hide dot
								dot:Hide()
								if useOverlay and mainDot then mainDot:Hide() end
							end
						elseif hasBuff then
							-- In range - show class-colored dot
							if classColor then
								dot:SetVertexColor(classColor.r, classColor.g, classColor.b)
							else
								dot:SetVertexColor(0, 1, 0)  -- Green
							end
							dot:Show()
							if useOverlay and mainDot then mainDot:Hide() end
						elseif buffName then
							-- Has a buff to check but doesn't have it - out of range (red)
							dot:SetVertexColor(1, 0, 0)
							dot:Show()
							if useOverlay and mainDot then mainDot:Hide() end
						else
							-- No buff to check (Tremor, Earthbind, Searing, etc.) - hide dot
							-- These totems can't be tracked via buffs
							dot:Hide()
							if useOverlay and mainDot then mainDot:Hide() end
						end
					else
						-- No totem active for this element
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
		-- Save position as CENTER coordinates (so scaling works properly)
		local centerX, centerY = self:GetCenter()
		local screenWidth, screenHeight = UIParent:GetWidth(), UIParent:GetHeight()
		-- Convert to offset from screen center
		local x = centerX - (screenWidth / 2)
		local y = centerY - (screenHeight / 2)
		if not SP.opt.rangeCounter.positions then
			SP.opt.rangeCounter.positions = {}
		end
		SP.opt.rangeCounter.positions[element] = {
			point = "CENTER", relPoint = "CENTER", x = x, y = y
		}
		-- Re-anchor to CENTER so scaling works properly
		self:ClearAllPoints()
		self:SetPoint("CENTER", UIParent, "CENTER", x, y)
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
		local slot = self.ElementToSlot[element]
		local haveTotem = slot and GetTotemInfo(slot)
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
						local hasBuff = self:UnitHasBuff(unit, buffName)
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
