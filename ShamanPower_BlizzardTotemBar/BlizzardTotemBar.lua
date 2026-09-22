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
	"PositionTotemButtons", "UpdateDropAllButton", "RestyleEngineCooldowns" }

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
	return host
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
			local ok, have, _, start, duration, icon = pcall(self.GetElementTotemInfo, self, element)
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
			if active and not secret(icon) and (type(icon) == "number" or type(icon) == "string") then
				if host.iconTexture ~= icon then host.activeIcon:SetTexture(icon); host.iconTexture = icon end
				host.activeIcon:Show()
				host.iconBackground:Show()
			else
				host.activeIcon:Hide()
				host.iconBackground:Hide()
			end
		end
	end
end

local function restoreScale()
	if not scaleFrame then return true end
	local ok = pcall(scaleFrame.SetScale, scaleFrame, scaleBase)
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
		local ok = desired < math.huge and pcall(bar.SetScale, bar, desired)
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
			host.indicator:SetFrameLevel(host:GetFrameLevel() + 5)
			host:Show()
			if host.widgetBlocked then host.lifetime:Hide() else host.lifetime:Show() end
			SP:StyleEngineCooldown(host.lifetime)
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
