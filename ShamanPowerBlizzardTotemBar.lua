-- Forever native-bar hosts. Actions and every Blizzard-owned cooldown remain
-- untouched; our own lifetime widgets consume the existing own-totem model.
local SP = ShamanPower
if not SP or WOW_PROJECT_ID ~= WOW_PROJECT_MAINLINE then return end

local secret = issecretvalue or function() return false end
local applied, refreshing, queued, pending, editing = false, false, false, false, false
local hosts, elementHosts, originalPulses = {}, {}, {}
local globalHooks, methodHooks = {}, {}
local hookedBar, scaleFrame, scaleBase, scaleFactor, failedScaleFactor
local nativeHooks = { "MultiCastActionButton_Update", "MultiCastSlotButton_Update", "MultiCastActionBarFrame_Update" }
local addonHooks = { "UpdateLayout", "UpdateMiniTotemBar", "UpdateTotemButtons",
	"PositionTotemButtons", "UpdateDropAllButton", "RestyleEngineCooldowns",
	"UpdateTotemProgressBarPositions", "PositionActiveOverlays" }

-- Build the custom bar's duration labels once, never while a bar is ticking.
local durationLabels = {}
for seconds = 0, 599 do
	durationLabels[seconds] = seconds < 60 and tostring(seconds)
		or string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end
for minutes = 10, 59 do durationLabels[minutes * 60] = minutes .. "m" end
for hours = 1, 24 do durationLabels[hours * 3600] = hours .. "h" end

local function durationLabel(remaining)
	local seconds = math.max(0, math.floor(remaining))
	if seconds >= 3600 then return durationLabels[math.min(24, math.floor(seconds / 3600)) * 3600] end
	if seconds >= 600 then return durationLabels[math.floor(seconds / 60) * 60] end
	return durationLabels[seconds]
end

local function requested()
	return SP.opt and SP.opt.useBlizzardTotemBar and SP.opt.enabled ~= false
		and SP.HasTotemBar and SP:HasTotemBar()
end

function SP.UsingBlizzardTotemBar()
	return applied
end

function SP:GetTotemOverlayHost(element)
	return (applied and elementHosts[element]) or (self.totemButtons and self.totemButtons[element])
end

local function stopPulse(pulse)
	if not pulse then return end
	pulse:Hide()
	pulse:HideWipe()
	pulse:HideTime()
	if pulse.wipeFrame then pulse.wipeFrame:Hide() end
end

local function clearLifetime(host)
	if host.widgetBlocked then return end
	if host.running then
		local ok = pcall(host.lifetime.Clear, host.lifetime)
		if not ok then host.widgetBlocked = true; return end
	end
	host.running, host.start, host.duration, host.fedElement = false, nil, nil, nil
end

local function createHost(slot)
	local host = CreateFrame("Frame", nil, slot)
	host:SetAllPoints(slot)
	host:EnableMouse(false)
	host.spNativeTotemHost = true
	local lifetime = CreateFrame("Cooldown", nil, host, "CooldownFrameTemplate")
	lifetime:SetAllPoints(host)
	lifetime:EnableMouse(false)
	lifetime:SetDrawSwipe(true)
	lifetime:SetDrawEdge(true)
	lifetime:SetDrawBling(false)
	lifetime:Clear()
	lifetime:Show()
	host.lifetime, host.running = lifetime, false
	-- Texture-only indicator updates avoid protected child-frame Show/Hide
	-- while the existing overlay driver is running in combat.
	local indicator = CreateFrame("Frame", nil, host)
	indicator:SetSize(12, 12)
	indicator:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0)
	indicator:EnableMouse(false)
	host.indicator = indicator
	local background = indicator:CreateTexture(nil, "BACKGROUND")
	background:SetAllPoints()
	background:SetColorTexture(0, 0, 0, 0.9)
	background:Hide()
	local icon = indicator:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("TOPLEFT", 1, -1)
	icon:SetPoint("BOTTOMRIGHT", -1, 1)
	icon:Hide()
	host.activeIcon, host.iconBackground = icon, background
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local assigned = indicator:CreateTexture(nil, "OVERLAY", nil, 2)
	assigned:SetSize(12, 12)
	assigned:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -1, 1)
	assigned:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	assigned:Hide()
	host.assignedIcon = assigned
	local dimmed = host:CreateTexture(nil, "ARTWORK")
	dimmed:SetAllPoints(host)
	dimmed:SetDesaturated(true)
	dimmed:SetVertexColor(0.5, 0.5, 0.5)
	dimmed:Hide()
	host.dimmedAssigned = dimmed
	local sweep = indicator:CreateTexture(nil, "ARTWORK", nil, 1)
	sweep:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
	sweep:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, 0)
	sweep:SetDesaturated(true)
	sweep:SetVertexColor(0.5, 0.5, 0.5)
	sweep:Hide()
	host.sweep = sweep
	local bg = host:CreateTexture(nil, "OVERLAY")
	bg:SetColorTexture(0, 0, 0, 0.7)
	bg:Hide()
	host.durationBackground = bg
	local bar = host:CreateTexture(nil, "OVERLAY", nil, 1)
	bar:Hide()
	host.durationBar = bar
	local text = host:CreateFontString(nil, "OVERLAY", nil, 7)
	text:Hide()
	host.durationText = text
	return host
end

-- Structural work is out of combat, matching the custom bar's anchors. Dots
-- and pulse retain the slot host even when the active icon pops out beside it.
local function styleHost(host, element)
	local opt, bg, bar, text = SP.opt, host.durationBackground, host.durationBar, host.durationText
	local position, size = opt.durationBarPosition or "bottom", opt.durationBarHeight or 3
	local top, bottom, left, right = SP:GetPartyDotPads()
	host.barPosition, host.barSize = position, size
	host.barVertical = position == "left" or position == "right" or position == "top_vert" or position == "bottom_vert"
	host.width, host.height = host:GetWidth(), host:GetHeight()
	bg:ClearAllPoints(); bar:ClearAllPoints(); text:ClearAllPoints()
	if position == "top" then
		bg:SetSize(host.width, size); bg:SetPoint("BOTTOMLEFT", host, "TOPLEFT", 0, 1 + top)
		bar:SetPoint("BOTTOMLEFT", bg, "BOTTOMLEFT", 0, 0)
	elseif position == "top_vert" then
		bg:SetSize(size, host.height); bg:SetPoint("BOTTOM", host, "TOP", 0, 1 + top)
		bar:SetPoint("BOTTOM", bg, "BOTTOM", 0, 0)
	elseif position == "bottom_vert" then
		bg:SetSize(size, host.height); bg:SetPoint("TOP", host, "BOTTOM", 0, -(1 + bottom))
		bar:SetPoint("TOP", bg, "TOP", 0, 0)
	elseif position == "left" then
		bg:SetSize(size, host.height); bg:SetPoint("TOPRIGHT", host, "TOPLEFT", -(1 + left), 0)
		bar:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", 0, 0)
	elseif position == "right" then
		bg:SetSize(size, host.height); bg:SetPoint("TOPLEFT", host, "TOPRIGHT", 1 + right, 0)
		bar:SetPoint("BOTTOMLEFT", bg, "BOTTOMLEFT", 0, 0)
	else
		bg:SetSize(host.width, size); bg:SetPoint("TOPLEFT", host, "BOTTOMLEFT", 0, -(1 + bottom))
		bar:SetPoint("TOPLEFT", bg, "TOPLEFT", 0, 0)
	end
	local colors = SP.DurationBarColors[element]
	bar:SetColorTexture(colors[1], colors[2], colors[3], 1)
	local location = opt.durationTextLocation or "none"
	host.textLocation = location
	text:SetFont("Fonts\\FRIZQT__.TTF", opt.durationTextSize or 8, "OUTLINE")
	text:SetTextColor(1, 1, 1)
	if location == "inside_top" then text:SetPoint("TOP", bg, "TOP", 0, -1)
	elseif location == "inside_bottom" then text:SetPoint("BOTTOM", bg, "BOTTOM", 0, 1)
	elseif location == "above" then
		if position == "left" then text:SetPoint("RIGHT", bg, "LEFT", -1, 0)
		elseif position == "right" then text:SetPoint("LEFT", bg, "RIGHT", 1, 0)
		else text:SetPoint("BOTTOM", bg, "TOP", 0, 1) end
	elseif location == "below" then
		if position == "left" then text:SetPoint("LEFT", bg, "RIGHT", 1, 0)
		elseif position == "right" then text:SetPoint("RIGHT", bg, "LEFT", -1, 0)
		else text:SetPoint("TOP", bg, "BOTTOM", 0, -1) end
	end
	host.activeAsMain = opt.activeTotemAsMain == true
	host.indicator:ClearAllPoints()
	if host.activeAsMain then host.indicator:SetAllPoints(host)
	else
		host.indicator:SetSize(26, 26)
		local point, relative, x, y = SP:GetActiveOverlayAnchor()
		host.indicator:SetPoint(point, host, relative, x, y)
	end
	local border = SP.ElementColors[element]
	host.iconBackground:SetColorTexture(border.r, border.g, border.b, 1)
	host.activeIcon:ClearAllPoints()
	host.activeIcon:SetPoint("TOPLEFT", host.indicator, "TOPLEFT", 2, -2)
	host.activeIcon:SetPoint("BOTTOMRIGHT", host.indicator, "BOTTOMRIGHT", -2, 2)
	SP:StyleEngineCooldown(host.lifetime)
	host.lifetime:SetHideCountdownNumbers(location ~= "icon" or opt.totemCooldownText == false)
	local ok, font = pcall(host.lifetime.GetCountdownFontString, host.lifetime)
	if ok and font then font:SetFont("Fonts\\FRIZQT__.TTF", opt.durationTextSize or 8, "OUTLINE") end
	host.sweepStyle = opt.totemCooldownSweep or "radial"
	host.showSweep = opt.showTotemCooldowns ~= false
	host.lifetime:SetDrawSwipe(host.showSweep and host.sweepStyle == "radial")
	host.lifetime:SetDrawEdge(host.showSweep and host.sweepStyle == "radial" and opt.totemCooldownEdge ~= false)
	host.indicator:SetFrameLevel(host:GetFrameLevel() + 1)
	host.lifetime:SetFrameLevel(host:GetFrameLevel() + 2)
end

local function updateDisplay(host, element, active, name, icon, remaining, duration)
	local assignments = ShamanPower_Assignments and SP.player and ShamanPower_Assignments[SP.player]
	local assigned = assignments and assignments[element] or 0
	local names = SP.TotemNames and SP.TotemNames[element]
	local assignedName = names and names[assigned]
	-- Blizzard's bar works like our Dynamic mode: whatever sits in the slot is
	-- what you drop, so the slot's own spell is the assignment here. The window's
	-- assignment is only a fallback for a slot we could not read.
	if host.slotSpellName then assignedName = host.slotSpellName end
	local matches = not secret(name) and type(name) == "string" and assignedName
		and (string.find(name, assignedName, 1, true) or string.find(assignedName, name, 1, true))
	local twisting = element == 4 and SP.opt.enableTotemTwisting
	if twisting and not secret(name) and type(name) == "string" then
		local twistNames = SP.TotemNames and SP.TotemNames[4]
		local twistName = twistNames and twistNames[SP.opt.twistTotem or 2]
		matches = host.activeAsMain or string.find(name, "Windfury", 1, true)
			or (twistName and string.find(name, twistName, 1, true))
	end
	local validIcon = active and not secret(icon) and (type(icon) == "number" or type(icon) == "string")
	local showIcon = validIcon and (not matches or (twisting and host.activeAsMain))
	if showIcon then
		if host.iconTexture ~= icon then host.activeIcon:SetTexture(icon); host.iconTexture = icon end
		host.activeIcon:Show(); host.iconBackground:Show()
	else host.activeIcon:Hide(); host.iconBackground:Hide() end
	local assignedIcon = SP:GetTotemIcon(element, assigned)
	if showIcon and not host.activeAsMain and assigned > 0 then
		if host.dimmedTexture ~= assignedIcon then
			host.dimmedAssigned:SetTexture(assignedIcon); host.dimmedTexture = assignedIcon
		end
		host.dimmedAssigned:Show()
	else host.dimmedAssigned:Hide() end
	if showIcon and host.activeAsMain and not matches and assigned > 0 then
		if host.assignedTexture ~= assignedIcon then
			host.assignedIcon:SetTexture(assignedIcon); host.assignedTexture = assignedIcon
		end
		host.assignedIcon:Show()
	else host.assignedIcon:Hide() end
	if active then
		local fraction = math.min(1, remaining / duration)
		if host.barPosition ~= "none" then
			if host.barVertical then host.durationBar:SetSize(host.barSize, math.max(1, host.height * fraction))
			else host.durationBar:SetSize(math.max(1, host.width * fraction), host.barSize) end
			host.durationBackground:Show(); host.durationBar:Show()
		else host.durationBackground:Hide(); host.durationBar:Hide() end
		if host.textLocation ~= "none" and host.textLocation ~= "icon" then
			host.durationText:SetText(durationLabel(remaining)); host.durationText:Show()
		else host.durationText:Hide() end
		-- Lifetime is the duration bar and its text here. On our own bar the grey
		-- sweep belongs to SPELL cooldowns, which Blizzard's button already draws,
		-- so drawing it for lifetime showed the same timer twice.
		host.sweep:Hide()
	else
		host.durationBackground:Hide(); host.durationBar:Hide(); host.durationText:Hide(); host.sweep:Hide()
	end
end

-- No spell-cooldown query or native widget read. SetCooldown and Clear are
-- protected methods (FILE5154513.bin); only our own plain-valued widget is
-- changed. Live protection/taint behavior still requires a client test.
function SP:UpdateBlizzardTotemOverlays()
	if not applied then return end
	local now = GetTime()
	if secret(now) or type(now) ~= "number" then return end
	for element = 1, 4 do
		local host = elementHosts[element]
		if host then
			local ok, have, name, start, duration, icon = pcall(self.GetElementTotemInfo, self, element)
			local active = ok and not secret(have) and have == true
				and not secret(start) and not secret(duration)
				and type(start) == "number" and type(duration) == "number"
				and start >= 0 and start < math.huge and duration > 0 and duration < math.huge
				and start + duration > now and start + duration < math.huge
			if active then
				if not host.widgetBlocked and (not host.running or host.fedElement ~= element
					or host.start ~= start or host.duration ~= duration) then
					local fed = pcall(host.lifetime.SetCooldown, host.lifetime, start, duration)
					if fed then
						host.running, host.start, host.duration, host.fedElement = true, start, duration, element
					else host.widgetBlocked = true end
				end
			else
				clearLifetime(host)
			end
			updateDisplay(host, element, active, name, icon, active and start + duration - now or 0, duration)
		end
	end
end

local function publicNumber(value)
	return not secret(value) and type(value) == "number" and value > -math.huge and value < math.huge
end

-- Screen centre of the buttons that are actually showing. Blizzard's frame is
-- a fixed 230 px wide; a low-level shaman fills only its left part, so scaling
-- about the frame's own centre swung the visible buttons out sideways.
local VISIBLE_BUTTONS = { "MultiCastSummonSpellButton", "MultiCastSlotButton1", "MultiCastSlotButton2",
	"MultiCastSlotButton3", "MultiCastSlotButton4", "MultiCastRecallSpellButton" }
local function visibleCenter()
	local l, r, b, t
	for _, name in ipairs(VISIBLE_BUTTONS) do
		local btn = _G[name]
		local okS, shown = pcall(function() return btn and btn:IsShown() end)
		if okS and shown == true then
			local ok, bl, bb, bw, bh = pcall(btn.GetRect, btn)
			local okE, es = pcall(btn.GetEffectiveScale, btn)
			if ok and okE and publicNumber(bl) and publicNumber(bb) and publicNumber(bw) and publicNumber(bh) and publicNumber(es) then
				bl, bb, bw, bh = bl * es, bb * es, bw * es, bh * es
				l = l and math.min(l, bl) or bl
				b = b and math.min(b, bb) or bb
				r = r and math.max(r, bl + bw) or bl + bw
				t = t and math.max(t, bb + bh) or bb + bh
			end
		end
	end
	if not l then return nil end
	return (l + r) / 2, (b + t) / 2
end

local function scaleAndAnchor(bar, scale, x, y)
	bar:SetScale(scale)
	local actual = bar:GetScale()
	if not publicNumber(actual) or math.abs(actual - scale) > 0.000001 then error("Native bar scale rejected", 0) end
	local effective = bar:GetEffectiveScale()
	if not publicNumber(effective) or effective <= 0 then error("Native bar scale unavailable", 0) end
	x, y = x / effective, y / effective
	if not publicNumber(x) or not publicNumber(y) then error("Native bar centre unavailable", 0) end
	bar:ClearAllPoints()
	bar:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
end

-- Edit Mode normally anchors an edge. Preserve physical screen centre instead
-- of allowing that edge to drag the bar across the screen as its size changes.
-- Snapshot anchors only on an OOC scale change, so a rejected call can roll back.
local function setScaleInPlace(bar, scale)
	if InCombatLockdown() or not publicNumber(scale) or scale <= 0 then return nil end
	local centerOK, x, y = pcall(bar.GetCenter, bar)
	local scaleOK, old = pcall(bar.GetScale, bar)
	local effectiveOK, effective = pcall(bar.GetEffectiveScale, bar)
	if not centerOK or not scaleOK or not effectiveOK or not publicNumber(x) or not publicNumber(y)
		or not publicNumber(old) or old <= 0 or not publicNumber(effective) or effective <= 0 then return nil end
	local nextEffective = effective * scale / old
	x, y = x * effective, y * effective
	-- keep the VISIBLE buttons' centre where it is: the frame centre moves by the
	-- (scaled) offset between the two
	local vx, vy = visibleCenter()
	if vx and publicNumber(vx) and publicNumber(vy) then
		local ox, oy = (vx - x) / effective, (vy - y) / effective
		x, y = vx - ox * nextEffective, vy - oy * nextEffective
	end
	if not publicNumber(nextEffective) or nextEffective <= 0 or not publicNumber(x) or not publicNumber(y)
		or not publicNumber(x / nextEffective) or not publicNumber(y / nextEffective) then return nil end
	local pointsOK, count = pcall(bar.GetNumPoints, bar)
	if not pointsOK or not publicNumber(count) or count < 1 then return nil end
	local points = {}
	for i = 1, count do
		local ok, point, relative, relativePoint, px, py = pcall(bar.GetPoint, bar, i)
		if not ok or secret(point) or secret(relative) or secret(relativePoint)
			or type(point) ~= "string" or type(relativePoint) ~= "string"
			or not publicNumber(px) or not publicNumber(py) then return nil end
		points[i] = { point, relative, relativePoint, px, py }
	end
	local ok = pcall(scaleAndAnchor, bar, scale, x, y)
	if not ok then
		pcall(bar.SetScale, bar, old)
		pcall(bar.ClearAllPoints, bar)
		for i = 1, count do pcall(bar.SetPoint, bar, unpack(points[i], 1, 5)) end
	end
	return ok
end

local function restoreScale()
	if not scaleFrame then return true end
	local ok = setScaleInPlace(scaleFrame, scaleBase)
	if ok then scaleFrame, scaleBase, scaleFactor = nil, nil, nil end
	return ok
end

-- A nil option never acquires scale ownership. Restore before Edit Mode can
-- change its own baseline; the next exit captures that new baseline once.
local function updateScale(bar)
	local factor = SP.opt and SP.opt.blizzardTotemBarScale
	if not applied or editing then restoreScale(); return end
	if secret(factor) or type(factor) ~= "number" or not (factor >= 0.5 and factor <= 2) then
		failedScaleFactor = nil
		restoreScale()
		return
	end
	if failedScaleFactor == factor then return end
	if scaleFrame and scaleFrame ~= bar and not restoreScale() then return end
	if not scaleFrame then
		local ok, base = pcall(bar.GetScale, bar)
		if not ok or secret(base) or type(base) ~= "number" or not (base > 0 and base < math.huge) then return end
		scaleFrame, scaleBase = bar, base
	end
	if scaleFactor ~= factor then
		local desired = scaleBase * factor
		local ok = desired < math.huge and setScaleInPlace(bar, desired)
		if ok == nil then return end -- Geometry is not available yet; retry after layout.
		local readOK, actual = pcall(bar.GetScale, bar)
		if ok and readOK and not secret(actual) and type(actual) == "number"
			and math.abs(actual - desired) <= 0.000001 then
			scaleFactor, failedScaleFactor = factor, nil
		else
			failedScaleFactor = factor -- Do not fight a rejecting owner until reset or a new factor.
			restoreScale()
		end
	end
end

local function slotElement(slot)
	if secret(slot) or type(slot) ~= "number" then return end
	for element = 1, 4 do
		if SP.ElementToSlot and SP.ElementToSlot[element] == slot then return element end
	end
end

local function restorePulses()
	for element, pulse in pairs(originalPulses) do
		SP.pulseOverlays[element] = pulse
		if pulse.wipeFrame then pulse.wipeFrame:Show() end
		originalPulses[element] = nil
	end
end

local function mapHosts()
	-- Restore before remapping, so moving a visual slot never saves another
	-- native host's pulse as the original custom-button pulse.
	restorePulses()
	for element = 1, 4 do elementHosts[element] = nil end
	for position = 1, 4 do
		local slot = _G["MultiCastSlotButton" .. position]
		local element = slot and slotElement(slot:GetID())
		local host = hosts[position]
		if element then
			local width, height = slot:GetWidth(), slot:GetHeight()
			if secret(width) or secret(height) or type(width) ~= "number" or type(height) ~= "number"
				or width <= 4 or height <= 4 then element = nil end
		end
		if element then
			if not host then host = createHost(slot); hosts[position] = host end
			host.widgetBlocked = nil -- Retry a rejected widget only from this OOC structural pass.
			if host.element ~= element then
				clearLifetime(host)
				stopPulse(host.pulse)
				host.element, host.fedElement = element, nil
			end
			host:SetParent(slot)
			host:ClearAllPoints()
			host:SetAllPoints(slot)
			host:SetFrameLevel(slot:GetFrameLevel() + 5)
			host.lifetime:SetFrameLevel(host:GetFrameLevel() + 1)
			host:Show()
			if host.widgetBlocked then host.lifetime:Hide() else host.lifetime:Show() end
			styleHost(host, element)
			host.slotSpellName = nil
			if SP.ReadTotemSet then
				local okRead, slots = pcall(SP.ReadTotemSet, SP, 1)
				local id = okRead and slots and slots[element]
				if id and not secret(id) then
					local spellName = GetSpellInfo(id)
					if type(spellName) == "string" then host.slotSpellName = spellName end
				end
			end
			elementHosts[element] = host
			if element <= 3 and SP.pulseOverlays and SP.totemButtons[element] then
				local original = SP.pulseOverlays[element] or SP:CreatePulseOverlay(SP.totemButtons[element])
				originalPulses[element] = original
				stopPulse(original)
				if not host.pulse then host.pulse = SP:CreatePulseOverlay(host) end
				SP.pulseOverlays[element] = host.pulse
				host.pulse.buttonWidth, host.pulse.buttonHeight = host:GetWidth() - 4, host:GetHeight() - 4
				host.pulse.wipeFrame:SetFrameLevel(host:GetFrameLevel() + 2)
				host.pulse.wipeFrame:Show()
			elseif host.pulse then stopPulse(host.pulse) end
		elseif host then
			host.widgetBlocked = nil
			clearLifetime(host)
			host.element = nil
			stopPulse(host.pulse)
			host:Hide()
		end
	end
end

local function refresh(self)
	local want = requested() and self.totemButtons and self.autoButton
		and MultiCastActionBarFrame ~= nil and _G.MultiCastSlotButton1 ~= nil
	local changing = applied ~= not not want
	if not applied and not want and not scaleFrame then return end
	if not want then
		restorePulses()
		for _, host in pairs(hosts) do
			host.widgetBlocked = nil
			clearLifetime(host)
			stopPulse(host.pulse)
			host:Hide()
		end
		for element = 1, 4 do elementHosts[element] = nil end
	end
	applied = not not want
	if changing then
		self.totemBarHidden = nil
		self:UpdateLayout()
		if applied then self:UpdateMiniTotemBar() end
		self:UpdateTotemFlyoutEnabled()
		self:SetupTotemBarVisibilityUpdater()
		self:UpdateTotemBarVisibility()
	end
	updateScale(MultiCastActionBarFrame)
	if applied then mapHosts() end
	if self.RefreshPartyRangeHosts then self:RefreshPartyRangeHosts() end
	if self.UpdatePartyDotPositions then self:UpdatePartyDotPositions() end
	if self.UpdatePulseBarPositions then self:UpdatePulseBarPositions() end
	if applied then
		self:UpdateBlizzardTotemOverlays()
		if self.HideCustomTotemBarForBlizzard then self:HideCustomTotemBarForBlizzard() end
	end
	self._ovWake = true
end

function SP:RefreshBlizzardTotemBar()
	if refreshing then return end
	if InCombatLockdown() then pending = true; return end
	pending, refreshing = false, true
	local ok, err = pcall(refresh, self)
	refreshing = false
	if not ok then error(err, 0) end
end

local function runRefresh()
	queued = false
	SP:RefreshBlizzardTotemBar()
end

function SP.QueueBlizzardTotemBarRefresh()
	if refreshing or queued then return end
	if InCombatLockdown() then pending = true; return end
	queued = true
	C_Timer.After(0, runRefresh)
end

local function afterNativeUpdate()
	if applied or requested() then SP:QueueBlizzardTotemBarRefresh() end
end

local function afterAddonLayout()
	if applied or requested() then SP:RefreshBlizzardTotemBar() end
end

local function afterEditMode(_bar, active)
	if secret(active) then return end
	editing = not not active
	if editing and not InCombatLockdown() then restoreScale() end
	afterNativeUpdate()
end

local function installHooks()
	for _, name in ipairs(nativeHooks) do
		if not globalHooks[name] and type(_G[name]) == "function" then
			hooksecurefunc(name, afterNativeUpdate)
			globalHooks[name] = true
		end
	end
	for _, name in ipairs(addonHooks) do
		if not methodHooks[name] and type(SP[name]) == "function" then
			hooksecurefunc(SP, name, afterAddonLayout)
			methodHooks[name] = true
		end
	end
	local bar = MultiCastActionBarFrame
	if bar and hookedBar ~= bar and type(bar.SetIsInEditMode) == "function" then
		hooksecurefunc(bar, "SetIsInEditMode", afterEditMode)
		hookedBar = bar
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("SPELLS_CHANGED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_TOTEM_UPDATE")
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_TOTEM_UPDATE" then
		if applied then
			SP:InvalidateTotemInfo()
			SP._ovWake = true
			SP:UpdateBlizzardTotemOverlays()
		end
		return
	end
	installHooks()
	if pending or applied or requested() or scaleFrame then SP:QueueBlizzardTotemBarRefresh() end
end)
installHooks()
