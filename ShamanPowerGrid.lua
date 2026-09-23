-- Grid pins the existing secure choices; casting and spell cooldowns remain
-- owned by the flyout code. Only ordinary decorations update during combat.
local SP = ShamanPower
local secret = issecretvalue or function() return false end
local keys = { "totem_earth", "totem_fire", "totem_water", "totem_air" }
local orderDefault = { 1, 2, 3, 4 }
local rows = { {}, {}, {}, {} }
local auxiliaryNames = { "ShamanPowerAutoDropAll", "ShamanPowerAutoTotemicCall", "ShamanPowerEarthShieldBtn" }
local owner, pending, queued
local combinedWidth, combinedHeight = 0, 0
local visibilityHidden, visibilityShown
local labels = {}
for seconds = 0, 599 do
	labels[seconds] = seconds < 60 and tostring(seconds)
		or string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end
for minutes = 10, 59 do labels[minutes * 60] = minutes .. "m" end
for hours = 1, 24 do labels[hours * 3600] = hours .. "h" end

local function label(remaining)
	local seconds = math.max(0, math.floor(remaining))
	if seconds >= 3600 then return labels[math.min(24, math.floor(seconds / 3600)) * 3600] end
	if seconds >= 600 then return labels[math.floor(seconds / 60) * 60] end
	return labels[seconds]
end

local function requested()
	-- A saved native-bar selection wins a conflicting profile on Mainline.
	return SP.opt and SP.opt.gridStyle and not (WOW_PROJECT_ID == WOW_PROJECT_MAINLINE
		and SP.opt.useBlizzardTotemBar and SP.HasTotemBar and SP:HasTotemBar())
end

function SP:GridActive()
	return self._gridApplied == true
end

function SP:GridOwnsElementPopouts()
	return self:GridActive() or requested() or (self.opt and self.opt.gridRestorePopouts ~= nil)
end

local function hideVisual(v)
	if not v then return end
	v.assigned:Hide(); v.bg:Hide(); v.bar:Hide(); v.text:Hide()
end

local function ensureVisual(button)
	if button.spGridVisual then return button.spGridVisual end
	local frame = CreateFrame("Frame", nil, button)
	frame:SetAllPoints(button)
	frame:SetFrameLevel((button.cooldown and button.cooldown:GetFrameLevel() or button:GetFrameLevel()) + 3)
	frame:EnableMouse(false)
	local v = { frame = frame }
	v.assigned = frame:CreateTexture(nil, "OVERLAY")
	v.assigned:SetAllPoints(button)
	v.assigned:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
	v.assigned:SetBlendMode("ADD")
	v.bg = frame:CreateTexture(nil, "OVERLAY", nil, 1)
	v.bg:SetColorTexture(0, 0, 0, 0.8)
	v.bar = frame:CreateTexture(nil, "OVERLAY", nil, 2)
	v.text = frame:CreateFontString(nil, "OVERLAY", nil, 3)
	v.text:SetTextColor(1, 1, 1)
	button.spGridVisual = v
	hideVisual(v)
	return v
end

-- Geometry/font changes happen only during the out-of-combat layout pass.
local function styleVisual(v, button, element, size)
	local opt, bg, bar, text = SP.opt, v.bg, v.bar, v.text
	local position, thickness = opt.durationBarPosition or "bottom", opt.durationBarHeight or 3
	v.size, v.thickness, v.position = size, thickness, position
	v.vertical = position == "left" or position == "right" or position == "top_vert" or position == "bottom_vert"
	bg:ClearAllPoints(); bar:ClearAllPoints(); text:ClearAllPoints()
	if position == "left" then bg:SetPoint("TOPRIGHT", button, "TOPLEFT", -1, 0)
	elseif position == "right" then bg:SetPoint("TOPLEFT", button, "TOPRIGHT", 1, 0)
	elseif position == "top_vert" then bg:SetPoint("BOTTOM", button, "TOP", 0, 1)
	elseif position == "bottom_vert" then bg:SetPoint("TOP", button, "BOTTOM", 0, -1)
	elseif position == "top" then bg:SetPoint("BOTTOMLEFT", button, "TOPLEFT", 0, 1)
	else bg:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -1) end
	bg:SetSize(v.vertical and thickness or size, v.vertical and size or thickness)
	bar:SetPoint(v.vertical and "BOTTOMLEFT" or "TOPLEFT", bg, v.vertical and "BOTTOMLEFT" or "TOPLEFT", 0, 0)
	local color = SP.DurationBarColors[element]
	bar:SetColorTexture(color[1], color[2], color[3], 1)
	local tint = SP.ElementColors[element]
	v.assigned:SetVertexColor(tint.r, tint.g, tint.b, 1)
	v.location = opt.durationTextLocation or "none"
	text:SetFont("Fonts\\FRIZQT__.TTF", opt.durationTextSize or 8, "OUTLINE")
	if v.location == "inside_top" then text:SetPoint("TOP", bg, "TOP", 0, -1)
	elseif v.location == "inside_bottom" then text:SetPoint("BOTTOM", bg, "BOTTOM", 0, 1)
	elseif v.location == "above" then
		if position == "left" then text:SetPoint("RIGHT", bg, "LEFT", -1, 0)
		elseif position == "right" then text:SetPoint("LEFT", bg, "RIGHT", 1, 0)
		else text:SetPoint("BOTTOM", bg, "TOP", 0, 1) end
	elseif v.location == "below" then
		if position == "left" then text:SetPoint("LEFT", bg, "RIGHT", 1, 0)
		elseif position == "right" then text:SetPoint("RIGHT", bg, "LEFT", -1, 0)
		else text:SetPoint("TOP", bg, "BOTTOM", 0, -1) end
	else text:SetPoint("CENTER", button, "CENTER", 0, 0) end
end

-- No tables, closures, formatting, spell lookups, or frame geometry reads here.
function SP:UpdateGridTotems()
	if not self:GridActive() then return end
	local now = GetTime()
	local assignments = ShamanPower_Assignments and self.player and ShamanPower_Assignments[self.player]
	for element = 1, 4 do
		local row = rows[element]
		local have, name, start, duration = self:GetElementTotemInfo(element)
		local valid = not secret(have) and have == true and not secret(name) and type(name) == "string"
			and not secret(start) and type(start) == "number" and not secret(duration) and type(duration) == "number"
			and duration > 0 and start + duration > now
		local active
		if valid then
			-- Names were read from our spell attributes out of combat. Match without
			-- allocating lowercase strings or querying the spell API on the tick.
			if row.name ~= name then
				row.name, row.active = name, nil
				local length = 0
				if row.all then
					for i = 1, #row.all do
						local child = row.all[i]
						local candidate = child.spGridSpell
						if candidate and #candidate > length and string.find(name, candidate, 1, true) then
							row.active, length = child.totemIndex, #candidate
						end
					end
				end
			end
			active = row.active
		end
		local assigned = self.pendingAssignments and self.pendingAssignments[element]
		if assigned == nil then assigned = assignments and assignments[element] or 0 end
		if row.all then
			for i = 1, #row.all do
				local button = row.all[i]
				local v = button.spGridVisual
				if v then
					local shown = row.shown and button.spGridEligible
					v.assigned:SetShown(shown and button.totemIndex == assigned or false)
					local running = shown and valid and active == button.totemIndex
					if running then
						local remaining = start + duration - now
						local length = math.max(1, v.size * math.min(1, remaining / duration))
						v.bar:SetSize(v.vertical and v.thickness or length, v.vertical and length or v.thickness)
						v.bg:SetShown(v.position ~= "none"); v.bar:SetShown(v.position ~= "none")
						if v.location ~= "none" then v.text:SetText(label(remaining)); v.text:Show()
						else v.text:Hide() end
					else v.bg:Hide(); v.bar:Hide(); v.text:Hide() end
				end
			end
		end
	end
end

local function unpinRow(element)
	local row, button = rows[element], SP.totemButtons and SP.totemButtons[element]
	if button then button.spGridPinned = nil end
	if row.all then
		for i = 1, #row.all do
			local child = row.all[i]
			child:SetAttribute("spGridPinned", nil)
			child.spGridEligible = nil
			hideVisual(child.spGridVisual)
			if child.icon then child.icon:SetAlpha(1); child.icon:SetDesaturated(false) end
			child:Hide()
		end
	end
	if row.box then
		row.box:SetAttribute("unit", "none")
		RegisterUnitWatch(row.box)
		row.box:Hide()
	end
	if row.dragHost then
		row.dragHost:SetScript("OnDragStart", row.dragStart)
		row.dragHost:SetScript("OnDragStop", row.dragStop)
		row.dragHost, row.dragStart, row.dragStop = nil, nil, nil
	end
	row.box, row.all, row.host, row.name, row.active, row.shown = nil, nil, nil, nil, nil, false
end

local function clearLegacyDecorations(element)
	local bars = SP.totemProgressBars and SP.totemProgressBars[element]
	if bars then
		bars.bg:Hide(); bars.bar:Hide()
		if bars.insideTextTop then bars.insideTextTop:Hide() end
		if bars.insideTextBottom then bars.insideTextBottom:Hide() end
		if bars.aboveBarText then bars.aboveBarText:Hide() end
		if bars.belowBarText then bars.belowBarText:Hide() end
		if bars.iconText then bars.iconText:Hide() end
	end
	local legacy = _G["ShamanPowerAutoTotem" .. element]
	if legacy and legacy ~= SP.totemButtons[element] then legacy:Hide() end
end

local function returnElement(element)
	local key = keys[element]
	local row = rows[element]
	if row.dragHost then
		row.dragHost:SetScript("OnDragStart", row.dragStart)
		row.dragHost:SetScript("OnDragStop", row.dragStop)
		row.dragHost, row.dragStart, row.dragStop = nil, nil, nil
	end
	if SP.poppedOutFrames[key] then SP:ReturnPopOutToBar(key) end
	SP.opt.poppedOut[key] = nil
	local button = SP.totemButtons[element]
	if button then button:SetParent(UIParent); button:SetScale(SP.opt.buffscale or 0.9) end
end

local function restore()
	SP._gridApplied = false
	SP.opt.poppedOut = SP.opt.poppedOut or {}
	for element = 1, 4 do unpinRow(element) end
	local snapshot = SP.opt.gridRestorePopouts
	for element = 1, 4 do
		returnElement(element)
		if snapshot and snapshot[element] then SP:PopOutElementWithFlyout(element) end
	end
	SP.opt.gridRestorePopouts = nil
	owner = nil
	SP:UpdateMiniTotemBar()
	SP:UpdateTotemButtons()
	for element = 1, 4 do
		SP:UpdateFlyoutVisibility(element)
		SP:MarkAssignedInFlyout(element)
	end
	SP:UpdateTotemProgressBarPositions()
	SP:UpdateTotemFlyoutEnabled()
	SP:PositionActiveOverlays()
	SP:UpdateActiveTotemOverlays()
end

local function splitDragStart(frame)
	if InCombatLockdown() or not SP:GridActive() or not SP.opt.gridSplit then return end
	if SP.poppedOutFrames[frame.key] == frame and frame:IsMovable() and not SP:PopOutsLocked() then
		frame:StartMoving()
	end
end

local function splitDragStop(frame)
	if InCombatLockdown() or not SP:GridActive() or SP.poppedOutFrames[frame.key] ~= frame then return end
	frame:StopMovingOrSizing()
	SP.opt.poppedOutPositions = SP.opt.poppedOutPositions or {}
	SP.opt.poppedOutPositions[frame.key] = SP:SavePositionRecord(frame)
end

local function rowHost(element)
	local key, button = keys[element], SP.totemButtons[element]
	if SP.opt.gridSplit then
		if not SP.poppedOutFrames[key] then
			SP.opt.poppedOut[key] = nil
			SP:PopOutElementWithFlyout(element)
			local frame = SP.poppedOutFrames[key]
			if frame and not (SP.opt.poppedOutPositions and SP.opt.poppedOutPositions[key]) then
				frame:ClearAllPoints()
				frame:SetPoint("CENTER", UIParent, "CENTER", 0, (2.5 - element) * 100)
			end
		end
		SP.opt.poppedOut[key] = true
		local frame, row = SP.poppedOutFrames[key], rows[element]
		if frame and row.dragHost ~= frame then
			row.dragHost, row.dragStart, row.dragStop = frame, frame:GetScript("OnDragStart"), frame:GetScript("OnDragStop")
			frame:SetScript("OnDragStart", splitDragStart)
			frame:SetScript("OnDragStop", splitDragStop)
		end
		return frame
	end
	if SP.poppedOutFrames[key] or SP.opt.poppedOut[key] then returnElement(element) end
	button:SetParent(SP.autoButton)
	button:SetScale(1)
	return SP.autoButton
end

local function layoutRow(element, offset, visible)
	local row, button, flyout = rows[element], SP.totemButtons[element], SP.totemFlyouts[element]
	if not button or not flyout then return 0, 0 end
	local host = rowHost(element)
	if not host then return 0, 0 end
	local split = SP.opt.gridSplit
	local horizontal = (SP.opt.layout or "Horizontal") == "Horizontal"
	if split then horizontal = not SP.opt.gridOrientation or SP.opt.gridOrientation[element] ~= "vertical" end
	local size, mainSize = flyout.buttonSize or 28, 26
	local gap = math.max(4, SP.opt.totemBarPadding or 2)
	-- Reserve external bar/text room between choices and between whole rows.
	local margin = math.max(12, (SP.opt.durationTextSize or 8) + (SP.opt.durationBarHeight or 3) + 4)
	if SP.opt.showPartyRangeDots then margin = math.max(margin, (SP.opt.partyDotSize or 5) + 3) end
	if SP.opt.durationBarPosition == "top_vert" or SP.opt.durationBarPosition == "bottom_vert" then
		margin = margin + size
	end
	local stride = math.max(size, mainSize) + margin * 2
	button.spGridPinned = true
	button:SetSize(mainSize, mainSize)
	button:ClearAllPoints()
	if split then button:SetPoint("TOPLEFT", host, "TOPLEFT", margin, -margin - 12)
	elseif horizontal then button:SetPoint("TOPLEFT", host, "TOPLEFT", margin, -margin - offset)
	else button:SetPoint("TOPLEFT", host, "TOPLEFT", margin + offset, -margin) end
	if row.all and row.all ~= flyout.allButtons then
		for i = 1, #row.all do
			local child = row.all[i]
			child:SetAttribute("spGridPinned", nil)
			child.spGridEligible = nil
			hideVisual(child.spGridVisual)
		end
	end
	row.host, row.shown, row.all, row.name = host, visible, flyout.allButtons, nil
	if flyout.box then
		if row.box ~= flyout.box then UnregisterUnitWatch(flyout.box); row.box = flyout.box end
		flyout.box:Show()
	end
	local count = 0
	for i = 1, row.all and #row.all or 0 do
		local child = row.all[i]
		if child then
			child:SetAttribute("spGridPinned", true)
			local spell = child:GetAttribute("mySpell")
			child.spGridSpell = not secret(spell) and type(spell) == "string" and spell ~= "" and spell or nil
			local eligible = not child.isDisabledInFlyout
				and (not child.talentSpellID or IsSpellKnown(child.talentSpellID))
				and not SP:IsSingleTotemPoppedOut(element, child.totemIndex)
			child.spGridEligible = eligible
			if eligible then
				count = count + 1
				local along = mainSize + gap + margin + (count - 1) * (size + gap + margin)
				child:ClearAllPoints()
				child:SetPoint("TOPLEFT", button, "TOPLEFT", horizontal and along or 0, horizontal and 0 or -along)
				child:SetSize(size, size)
				if child.icon then child.icon:SetAlpha(1); child.icon:SetDesaturated(false) end
				child:SetAlpha(SP.opt.totemFlyoutOpacity or 1)
				styleVisual(ensureVisual(child), child, element, size)
			else hideVisual(child.spGridVisual) end
			child:SetShown(visible and eligible or false)
		end
	end
	button:SetShown(visible)
	SP:PlaceFlyoutArrows(flyout)
	if flyout.box then SP:DressFlyoutFrame(flyout) end
	clearLegacyDecorations(element)
	local length = mainSize + count * (size + gap + margin) + margin * 2
	local width, height = horizontal and length or stride, horizontal and stride or length
	if split then
		host:SetSize(width, height + 24)
		local color = SP.ElementColors[element]
		host:SetBackdrop(SP.PANEL_BACKDROP)
		host:SetBackdropColor(0.086, 0.098, 0.122, 0.92)
		host:SetBackdropBorderColor(color.r, color.g, color.b, 1)
		host:SetShown(visible)
	end
	return width, height
end

local function layoutAuxiliaries(width, height)
	local x, extra = 8, false
	for i = 1, #auxiliaryNames do
		local button = _G[auxiliaryNames[i]]
		local popped = (i == 1 and SP:IsDropAllPoppedOut()) or (i == 3 and SP:IsEarthShieldPoppedOut())
		if button and not popped and button:IsShown() then
			button:ClearAllPoints()
			button:SetPoint("TOPLEFT", SP.autoButton, "TOPLEFT", x, -height - 4)
			x, extra = x + 30, true
		end
	end
	local separator = _G.ShamanPowerAutoSeparator
	if separator then separator:Hide() end
	SP.autoButton:SetSize(math.max(width, x, 34), math.max(34, height + (extra and 40 or 0)))
end

local function apply()
	local opt = SP.opt
	opt.poppedOut = opt.poppedOut or {}
	if not opt.gridRestorePopouts then
		opt.gridRestorePopouts = {}
		for element = 1, 4 do opt.gridRestorePopouts[element] = opt.poppedOut[keys[element]] == true end
	end
	owner, SP._gridApplied = opt, true
	-- Resolve saved conflicting custom styles without touching Dynamic Mode.
	local wasCompact = opt.compactStyle
	opt.compactStyle, opt.activeTotemAsMain = false, false
	if wasCompact then SP:SetupCompactStyle() end
	SP:SetupTotemFlyouts()
	local order = opt.totemBarOrder or orderDefault
	local offset, width, height = 0, 0, 0
	local barShown = opt.enabled ~= false and not SP.totemBarHidden and SP.autoButton:IsShown()
	visibilityHidden, visibilityShown = SP.totemBarHidden, SP.autoButton:IsShown()
	for i = 1, 4 do
		local element = order[i]
		local visible = barShown and SP:IsElementShown(element)
		local w, h = layoutRow(element, offset, visible)
		if visible and not opt.gridSplit then
			if (opt.layout or "Horizontal") == "Horizontal" then offset = offset + h; width, height = math.max(width, w), offset
			else offset = offset + w; width, height = offset, math.max(height, h) end
		end
	end
	combinedWidth, combinedHeight = width, height
	layoutAuxiliaries(width, height)
	SP:HideActiveTotemOverlaysForCompact()
	if SP.updateSystem and SP.updateSystem.subsystems.progressBars then SP:EnableUpdateSubsystem("progressBars") end
	SP:UpdateGridTotems()
end

function SP:RefreshGridStyle()
	if self._gridRefreshing then return end
	if not self.opt or not self.autoButton or not self.player or not self.totemButtons[1] then return end
	if not requested() and not self:GridActive() and not self.opt.gridRestorePopouts then return end
	if InCombatLockdown() then pending = true; return end
	self._gridRefreshing, pending = true, false
	if owner and owner ~= self.opt then
		-- The old profile keeps its own snapshot. Never copy it into this profile.
		for element = 1, 4 do unpinRow(element) end
		owner, self._gridApplied = nil, false
		if not requested() and not self.opt.gridRestorePopouts then
			for element = 1, 4 do
				local button = self.totemButtons[element]
				if button and not self.poppedOutFrames[keys[element]] then
					button:SetParent(UIParent); button:SetScale(self.opt.buffscale or 0.9)
				end
			end
			self:UpdateMiniTotemBar(); self:UpdateTotemButtons()
			for element = 1, 4 do self:UpdateFlyoutVisibility(element) end
			self._gridRefreshing = false
			return
		end
	end
	if requested() then apply() else restore() end
	self._gridRefreshing = false
end

function SP:GridLayoutElement(element)
	if not element or not self:GridActive() then return false end
	if not self._gridRefreshing then self:RefreshGridStyle() end
	return true
end

function SP:SetGridStyle(on)
	if InCombatLockdown() or not self.opt then return false end
	self.opt.gridStyle = on and true or false
	if on then
		self.opt.compactStyle, self.opt.activeTotemAsMain, self.opt.useBlizzardTotemBar = false, false, false
		if self.RefreshBlizzardTotemBar then self:RefreshBlizzardTotemBar() end
		self:SetupCompactStyle()
	end
	self:RefreshGridStyle()
	self:UpdateLayout()
	self:RefreshGridStyle()
	return true
end

function SP:GridReturnPopOut(key)
	if not self:GridActive() or self._gridRefreshing then return false end
	for element = 1, 4 do
		if key == keys[element] then
			if not InCombatLockdown() then self.opt.gridSplit = false; self:RefreshGridStyle() end
			return true
		end
	end
	return false
end

function SP:GridPopOutElement(element)
	if not self:GridActive() or self._gridRefreshing or not keys[element] then return false end
	if not InCombatLockdown() then self.opt.gridSplit = true; self:RefreshGridStyle() end
	return true
end

function SP:GetGridRowFrame(element)
	local row = rows[element]
	return self:GridActive() and self.opt.gridSplit and row and row.shown and row.host or nil
end

function SP:ResetGridRowPosition(element)
	local frame = self:GetGridRowFrame(element)
	if not frame or InCombatLockdown() then return end
	if self.opt.poppedOutPositions then self.opt.poppedOutPositions[keys[element]] = nil end
	frame:ClearAllPoints()
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, (2.5 - element) * 100)
end

local function refresh()
	if SP._gridRefreshing then return end
	if SP:GridOwnsElementPopouts() then SP:RefreshGridStyle() end
end

local function runQueued()
	queued = false
	refresh()
end

local function queueRefresh()
	if queued or not SP:GridOwnsElementPopouts() then return end
	if InCombatLockdown() then pending = true; return end
	queued = true
	C_Timer.After(0, runQueued)
end

-- Lifecycle hooks, not tick hooks. All callback functions are allocated once.
local hooks = { "UpdateLayout", "UpdateMiniTotemBar", "UpdateTotemButtons", "PositionTotemButtons",
	"SetupTotemFlyouts", "RecreateTotemFlyouts", "UpdateTotemFlyoutEnabled", "ApplyTotemFlyoutButtonSize",
	"RebuildTotemFlyout", "AddMissingFlyoutButtons",
	"RefreshFlyoutLayout", "UpdateTotemProgressBarPositions", "SetTotemBarFramesShown",
	"FitPopOutFrame", "TogglePopOutFrame", "SetPopOutScale", "ReturnPopOutToBar" }
for i = 1, #hooks do if SP[hooks[i]] then hooksecurefunc(SP, hooks[i], refresh) end end
local function afterAuxiliary()
	-- Earth Shield can repaint periodically: only restore its strip anchors here,
	-- never run the allocating flyout/pop-out builders from that path.
	if SP:GridActive() and not SP._gridRefreshing and not InCombatLockdown() then
		layoutAuxiliaries(combinedWidth, combinedHeight)
	end
end
hooksecurefunc(SP, "RepositionEarthShieldButton", afterAuxiliary)
local function afterVisibility()
	if not SP:GridActive() or SP._gridRefreshing or InCombatLockdown() then return end
	-- This caller runs at 5 Hz. Rebuild only on an actual visibility transition.
	local shown = SP.autoButton and SP.autoButton:IsShown()
	if visibilityHidden ~= SP.totemBarHidden or visibilityShown ~= shown then SP:RefreshGridStyle() end
end
hooksecurefunc(SP, "UpdateTotemBarVisibility", afterVisibility)
local function afterTotem()
	if SP:GridActive() then SP:UpdateGridTotems() end
end
hooksecurefunc(SP, "PLAYER_TOTEM_UPDATE", afterTotem)
hooksecurefunc(SP, "UNIT_SPELLCAST_SUCCEEDED", afterTotem)
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("SPELLS_CHANGED")
events:SetScript("OnEvent", function()
	if pending or SP:GridOwnsElementPopouts() then queueRefresh() end
end)
