-- ============================================================================
-- ShamanPowerCompact.lua
-- "Compact" totem bar display style: each totem slot is an element-colored
-- LINE instead of an icon. Duration drains as an outline (both long edges
-- shrink together from the far end toward the start - top to bottom on a
-- vertical line) or as the line itself draining ("fill" mode), the pulse
-- countdown refills inside the line, and a tiny optional icon square sits
-- above or below it. The Earth Shield button becomes a segmented line, one
-- segment per charge.
--
-- The secure buttons are reused unchanged (click / flyout behavior is
-- identical); this file only draws on them. Everything is driven by
-- SP:CompactOpts(), which the setup wizard also feeds with its preview options
-- so the mock and the real bar are painted by the same code.
-- ============================================================================

local SP = ShamanPower

local FONT  = "Fonts\\FRIZQT__.TTF"
local EMPTY = { r = 0.32, g = 0.32, b = 0.32 }   -- "nothing down" line color
local ES_MAX_CHARGES = 6

-- ---------------------------------------------------------------------------
-- Option access
-- ---------------------------------------------------------------------------
function SP:CompactActive()
	return self.opt and self.opt.compactStyle and true or false
end

-- Normalized compact options. `o` defaults to the live profile; the wizard
-- passes its own table when previewing a layout.
function SP:CompactOpts(o)
	o = o or self.opt
	local vertical = (o.compactOrientation or "horizontal") == "vertical"
	local T = o.compactThickness
	if T == nil then T = vertical and 16 or 10 end
	local mode = o.compactDurationMode
	if mode == nil or mode == "auto" then mode = vertical and "fill" or "outline" end
	local sq = o.compactIconSquares or "off"
	if sq == "above" then sq = "before" elseif sq == "below" then sq = "after" end   -- old values
	return {
		vertical  = vertical,
		L         = o.compactLength or 120,
		T         = T,
		ow        = o.compactOutlineWidth or 2,
		olColor   = (o.compactOutlineColorMode == "custom") and o.compactOutlineColor or nil,
		fill      = (mode == "fill"),
		sq        = sq,
		iq        = o.compactIconSize or 12,
		pulseText = o.compactPulseText ~= false,
		pulseBar  = o.compactPulseBar ~= false,
	}
end

function SP:CompactVerticalLines()
	return self:CompactOpts().vertical
end

-- Direction the totem slots are laid out along. Compact horizontal lines stack
-- top-to-bottom (a vertical bar); vertical lines sit side by side.
function SP:IsTotemBarHorizontal()
	if self:CompactActive() then return self:CompactVerticalLines() end
	return self.opt.layout == "Horizontal"
end

-- Button size (bw, bh), slot size including the icon square (sw, sh), and the
-- button's offset inside its slot (ox, oy; oy negative = down). Icon-style
-- bars are the classic 26x26.
-- Icon squares sit BEFORE / AFTER the line along its own axis: left / right of a
-- horizontal line (the row stays one line tall), above / below a vertical one.
function SP:GetTotemSlotDims(o)
	if not self:CompactActive() and not o then return 26, 26, 26, 26, 0, 0 end
	local co = self:CompactOpts(o)
	local extra = (co.sq ~= "off") and (co.iq + 2) or 0
	if co.vertical then
		local sw = math.max(co.T, (co.sq ~= "off") and co.iq or 0)
		return co.T, co.L, sw, co.L + extra, math.floor((sw - co.T) / 2), (co.sq == "before") and -extra or 0
	else
		local sh = math.max(co.T, (co.sq ~= "off") and co.iq or 0)
		return co.L, co.T, co.L + extra, sh, (co.sq == "before") and extra or 0, -math.floor((sh - co.T) / 2)
	end
end

-- ---------------------------------------------------------------------------
-- Visuals: create / layout / paint (shared by the real bar and the wizard mock)
-- ---------------------------------------------------------------------------
local function Tex(frame, layer, sub)
	local t = frame:CreateTexture(nil, layer, nil, sub)
	t:SetColorTexture(1, 1, 1, 1)
	t:Hide()
	return t
end

function SP:CreateCompactVisuals(frame)
	local c = {}
	c.bg    = Tex(frame, "BACKGROUND", 0); c.bg:SetAllPoints(frame); c.bg:SetColorTexture(0, 0, 0, 0.55)
	c.line  = Tex(frame, "ARTWORK", 0)
	c.pulse = Tex(frame, "ARTWORK", 2); c.pulse:SetColorTexture(1, 1, 1, 0.35)
	-- outline: [1] start cap, [2] far cap, [3] and [4] the two long edges
	c.ol    = { Tex(frame, "OVERLAY", 0), Tex(frame, "OVERLAY", 0), Tex(frame, "OVERLAY", 0), Tex(frame, "OVERLAY", 0) }
	c.text  = frame:CreateFontString(nil, "OVERLAY", nil, 7)
	c.text:SetFont(FONT, 10, "OUTLINE"); c.text:SetTextColor(1, 1, 1); c.text:Hide()
	c.sqBd  = Tex(frame, "ARTWORK", 0); c.sqBd:SetColorTexture(0, 0, 0, 0.9)
	c.sq    = Tex(frame, "ARTWORK", 1); c.sq:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	return c
end

function SP:HideCompactVisuals(c)
	if not c then return end
	c.bg:Hide(); c.line:Hide(); c.pulse:Hide(); c.text:Hide(); c.sq:Hide(); c.sqBd:Hide()
	for i = 1, 4 do c.ol[i]:Hide() end
end

-- Anchor every piece for the given size/options. `frame` must already be
-- sized bw x bh (the line, outline included).
function SP:LayoutCompactVisuals(c, frame, co, bw, bh)
	local ow = co.ow
	c.vertical, c.fill, c.ow, c.bw, c.bh = co.vertical, co.fill, ow, bw, bh
	c.lineLen = (co.vertical and bh or bw) - 2 * ow
	c.pulseBar = co.pulseBar
	c.olColor = co.olColor

	-- the line: inset by the outline; in fill mode only the start edge is anchored
	c.line:ClearAllPoints()
	if co.fill then
		if co.vertical then
			c.line:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", ow, ow)
			c.line:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -ow, ow)
			c.line:SetHeight(c.lineLen)
		else
			c.line:SetPoint("TOPLEFT", frame, "TOPLEFT", ow, -ow)
			c.line:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", ow, ow)
			c.line:SetWidth(c.lineLen)
		end
	else
		c.line:SetPoint("TOPLEFT", frame, "TOPLEFT", ow, -ow)
		c.line:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -ow, ow)
	end

	-- outline pieces. Start cap = bottom (vertical) / left (horizontal); far
	-- cap = top / right; the two long edges are anchored at the start so they
	-- can shrink toward it.
	local startCap, farCap, edgeA, edgeB = c.ol[1], c.ol[2], c.ol[3], c.ol[4]
	startCap:ClearAllPoints(); farCap:ClearAllPoints(); edgeA:ClearAllPoints(); edgeB:ClearAllPoints()
	if co.vertical then
		startCap:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0); startCap:SetSize(bw, ow)
		farCap:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0);         farCap:SetSize(bw, ow)
		edgeA:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0);    edgeA:SetSize(ow, bh)
		edgeB:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0);  edgeB:SetSize(ow, bh)
	else
		startCap:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0);       startCap:SetSize(ow, bh)
		farCap:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0);       farCap:SetSize(ow, bh)
		edgeA:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0);          edgeA:SetSize(bw, ow)
		edgeB:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0);    edgeB:SetSize(bw, ow)
	end

	-- pulse refill from the start of the line
	c.pulse:ClearAllPoints()
	if co.vertical then
		c.pulse:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", ow, ow)
		c.pulse:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -ow, ow)
		c.pulse:SetHeight(1)
	else
		c.pulse:SetPoint("TOPLEFT", frame, "TOPLEFT", ow, -ow)
		c.pulse:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", ow, ow)
		c.pulse:SetWidth(1)
	end

	-- pulse text: start of a horizontal line, top of a vertical one; hidden on
	-- lines too thin to read it
	-- (never give the text a fixed width: WoW would truncate "1.4" to "..." on a
	-- narrow vertical line - let it overhang instead)
	local fs = math.max(7, math.min(14, co.T - (co.vertical and 5 or 3)))
	c.text:SetFont(FONT, fs, "OUTLINE")
	c.text:SetWordWrap(false)
	c.text:ClearAllPoints()
	c.text:SetWidth(0)
	if co.vertical then
		c.text:SetPoint("TOP", frame, "TOP", 0, -(ow + 2)); c.text:SetJustifyH("CENTER")
	else
		c.text:SetPoint("LEFT", frame, "LEFT", ow + 3, 0); c.text:SetJustifyH("LEFT")
	end
	c.textOk = co.pulseText and co.T >= 14

	-- icon square above / below
	c.sq:ClearAllPoints(); c.sqBd:ClearAllPoints()
	if co.sq == "off" then
		c.sqOn = false
	else
		c.sqOn = true
		c.sq:SetSize(co.iq, co.iq); c.sqBd:SetSize(co.iq + 2, co.iq + 2)
		if co.vertical then
			if co.sq == "before" then c.sq:SetPoint("BOTTOM", frame, "TOP", 0, 2) else c.sq:SetPoint("TOP", frame, "BOTTOM", 0, -2) end
		else
			if co.sq == "before" then c.sq:SetPoint("RIGHT", frame, "LEFT", -2, 0) else c.sq:SetPoint("LEFT", frame, "RIGHT", 2, 0) end
		end
		c.sqBd:SetPoint("CENTER", c.sq, "CENTER", 0, 0)
	end
	c.bg:Show()
end

-- Outline for the remaining fraction: the far cap goes first, then both long
-- edges shrink together toward the start cap, which goes last.
local function SetOutline(c, frac, r, g, b)
	local startCap, farCap, edgeA, edgeB = c.ol[1], c.ol[2], c.ol[3], c.ol[4]
	if frac <= 0 then
		startCap:Hide(); farCap:Hide(); edgeA:Hide(); edgeB:Hide()
		return
	end
	local full = c.vertical and c.bh or c.bw
	local len = math.max(1, full * frac)
	if c.vertical then edgeA:SetHeight(len); edgeB:SetHeight(len) else edgeA:SetWidth(len); edgeB:SetWidth(len) end
	for i = 1, 4 do c.ol[i]:SetColorTexture(r, g, b, 1) end
	startCap:Show(); edgeA:Show(); edgeB:Show()
	farCap:SetShown(frac >= 0.995)
end

-- "1.4" strings without per-frame garbage
local tenths = {}
local function FormatTenths(t)
	local k = math.floor(t * 10 + 0.5)
	if k < 0 then k = 0 end
	local s = tenths[k]
	if not s then s = string.format("%.1f", k / 10); tenths[k] = s end
	return s
end

-- col = element color or nil for an empty slot. frac = remaining duration 0..1.
-- dim = true when the player is out of range of the totem. pulsePos 0..1 and
-- pulseRemain (seconds) are nil for totems that do not pulse.
function SP:PaintCompactVisuals(c, col, frac, dim, pulsePos, pulseRemain, icon, iconAlpha)
	local active = col ~= nil
	local r, g, b, a = EMPTY.r, EMPTY.g, EMPTY.b, 0.6
	if active then
		local k = dim and 0.5 or 1
		r, g, b, a = col.r * k, col.g * k, col.b * k, 0.95
	end
	c.line:SetColorTexture(r, g, b, a)
	if c.fill then
		local len = active and math.max(1, c.lineLen * frac) or c.lineLen
		if c.vertical then c.line:SetHeight(len) else c.line:SetWidth(len) end
	end
	c.line:Show()

	local oFrac = active and (c.fill and 1 or frac) or 0
	if c.olColor then
		SetOutline(c, oFrac, c.olColor.r or 1, c.olColor.g or 1, c.olColor.b or 1)
	else
		SetOutline(c, oFrac, r * 0.55 + 0.45, g * 0.55 + 0.45, b * 0.55 + 0.45)
	end

	if active and pulsePos and c.pulseBar then
		local sz = math.max(1, c.lineLen * pulsePos)
		if c.vertical then c.pulse:SetHeight(sz) else c.pulse:SetWidth(sz) end
		c.pulse:Show()
	else
		c.pulse:Hide()
	end
	if active and pulseRemain and c.textOk then
		c.text:SetText(FormatTenths(pulseRemain)); c.text:Show()
	else
		c.text:Hide()
	end

	if c.sqOn and icon then
		c.sq:SetTexture(icon); c.sq:SetAlpha(iconAlpha or 1); c.sq:Show(); c.sqBd:Show()
	else
		c.sq:Hide(); c.sqBd:Hide()
	end
	c.bg:Show()
end

-- ---------------------------------------------------------------------------
-- Charge segments (Earth Shield line) - shared with the wizard mock
-- ---------------------------------------------------------------------------
-- Lays `n` segments along the inside of the line described by visuals `c`.
function SP:LayoutCompactSegments(frame, c, n, gap)
	gap = gap or 2
	frame.compactSeg = frame.compactSeg or {}
	local seg = frame.compactSeg
	local ow = c.ow
	local segLen = (c.lineLen - (n - 1) * gap) / n
	for i = 1, n do
		local t = seg[i]
		if not t then t = Tex(frame, "ARTWORK", 1); seg[i] = t end
		local off = ow + (i - 1) * (segLen + gap)
		t:ClearAllPoints()
		if c.vertical then
			t:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", ow, off)
			t:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -ow, off)
			t:SetHeight(segLen)
		else
			t:SetPoint("TOPLEFT", frame, "TOPLEFT", off, -ow)
			t:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", off, ow)
			t:SetWidth(segLen)
		end
	end
	for i = n + 1, #seg do seg[i]:Hide() end
	seg.n = n
	return seg
end

-- charges = filled segments; active = false paints everything gray.
-- useColors mirrors the Shield Charges option: green / yellow / red as they run low.
function SP:PaintCompactSegments(seg, charges, active, useColors)
	if not seg then return end
	local r, g, b = 0.25, 0.85, 0.3
	if useColors then
		if charges <= 2 then r, g, b = 1, 0.25, 0.25 elseif charges <= 4 then r, g, b = 1, 0.85, 0.2 end
	end
	for i = 1, seg.n or #seg do
		if active and i <= charges then
			seg[i]:SetColorTexture(r, g, b, 0.95)
		else
			seg[i]:SetColorTexture(EMPTY.r, EMPTY.g, EMPTY.b, active and 0.45 or 0.6)
		end
		seg[i]:Show()
	end
end

function SP:HideCompactSegments(seg)
	if not seg then return end
	for i = 1, #seg do seg[i]:Hide() end
end

-- ---------------------------------------------------------------------------
-- Real totem bar
-- ---------------------------------------------------------------------------
function SP:EnsureCompactVisuals(btn)
	if not btn.compact then btn.compact = self:CreateCompactVisuals(btn) end
	return btn.compact
end

-- Room taken at the far end of a line by the keybind label and the
-- range-counter number, so the party dots sit after them.
function SP:CompactCounterShift(btn)
	local shift = 0
	if btn.keybindText and btn.keybindText:IsShown() and (btn.keybindText:GetText() or "") ~= "" then
		shift = shift + math.ceil(btn.keybindText:GetStringWidth()) + 3
	end
	local rc = self.opt.rangeCounter
	if rc and rc.enabled and (rc.location or "icon") == "icon" and self.rangeCounterTexts and self.rangeCounterTexts[btn.element] then
		shift = shift + 18
	end
	return shift
end

-- Switch one totem button between icon and compact rendering. `forceOff` is
-- used for popped-out buttons, which always keep their icon.
function SP:ApplyCompactButtonLayout(btn, forceOff)
	if not btn then return end
	local on = self:CompactActive() and not forceOff
	local rc = self.rangeCounterTexts and self.rangeCounterTexts[btn.element]
	local gcd = self.gcdCooldowns and self.gcdCooldowns[btn.element]
	if not on then
		if btn.compactLayoutOn then
			self:HideCompactVisuals(btn.compact)
			if btn.icon then btn.icon:Show() end
			if rc then rc:ClearAllPoints(); rc:SetPoint("CENTER", btn, "CENTER", 0, 0) end
			if btn.keybindText then btn.keybindText:ClearAllPoints(); btn.keybindText:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 1, 0) end
			if gcd then gcd:Show() end
			btn.compactLayoutOn = nil
			local dots = self.partyRangeDots and self.partyRangeDots[btn.element]
			if dots and self.PositionPartyDots then self:PositionPartyDots(dots, btn) end
		end
		return
	end

	local c = self:EnsureCompactVisuals(btn)
	btn.compactLayoutOn = true
	if btn.icon then btn.icon:Hide() end
	if btn.assignedIndicator then btn.assignedIndicator:Hide() end
	if btn.cooldownText then btn.cooldownText:Hide() end
	if btn.cooldown then btn.cooldown:Clear() end
	if btn.cdSweep then btn.cdSweep:Hide() end
	if gcd then gcd:Clear(); gcd:Hide() end      -- the GCD swipe is an icon thing

	local co = self:CompactOpts()
	local bw, bh = self:GetTotemSlotDims()
	self:LayoutCompactVisuals(c, btn, co, bw, bh)

	-- far end of the line: keybind label, then the range counter, then the dots
	local shift = 0
	if btn.keybindText then
		btn.keybindText:ClearAllPoints()
		if co.vertical then btn.keybindText:SetPoint("BOTTOM", btn, "BOTTOM", 0, co.ow + 1)
		else btn.keybindText:SetPoint("RIGHT", btn, "RIGHT", -(co.ow + 2), 0) end
		if btn.keybindText:IsShown() and (btn.keybindText:GetText() or "") ~= "" then
			shift = math.ceil(btn.keybindText:GetStringWidth()) + 3
		end
	end
	if rc then
		rc:ClearAllPoints()
		if co.vertical then rc:SetPoint("BOTTOM", btn, "BOTTOM", 0, co.ow + 2 + shift)
		else rc:SetPoint("RIGHT", btn, "RIGHT", -(co.ow + 3 + shift), 0) end
	end
	local dots = self.partyRangeDots and self.partyRangeDots[btn.element]
	if dots and self.PositionPartyDots then self:PositionPartyDots(dots, btn) end
	self:UpdateCompactTotems()
end

-- The Earth Shield button on the totem bar becomes a segmented line: one
-- segment per charge, the target's name over it (below it when vertical).
function SP:ApplyCompactESLayout()
	local esBtn = _G["ShamanPowerEarthShieldBtn"]
	if not esBtn then return end
	local icon    = _G["ShamanPowerEarthShieldBtnIcon"]
	local name    = _G["ShamanPowerEarthShieldBtnName"]
	local charges = _G["ShamanPowerEarthShieldBtnCharges"]
	local on = self:CompactActive() and not (self.IsEarthShieldPoppedOut and self:IsEarthShieldPoppedOut())
	if not on then
		if esBtn.compactLayoutOn then
			self:HideCompactVisuals(esBtn.compact)
			self:HideCompactSegments(esBtn.compactSeg)
			esBtn:SetSize(26, 26)
			if icon then icon:Show() end
			if charges then charges:Show() end
			if name then
				name:ClearAllPoints(); name:SetPoint("TOP", esBtn, "BOTTOM", 0, -1)
				name:SetWidth(40); name:SetHeight(10); name:SetFontObject("GameFontHighlightSmall")
			end
			esBtn.compactLayoutOn = nil
		end
		return
	end

	local c = self:EnsureCompactVisuals(esBtn)
	esBtn.compactLayoutOn = true
	local co = self:CompactOpts()
	local bw, bh = self:GetTotemSlotDims()
	esBtn:SetSize(bw, bh)
	if icon then icon:Hide() end
	if charges then charges:Hide() end
	self:LayoutCompactVisuals(c, esBtn, co, bw, bh)
	c.line:Hide()
	self:LayoutCompactSegments(esBtn, c, ES_MAX_CHARGES)
	if name then
		name:ClearAllPoints()
		name:SetFont(FONT, math.max(7, math.min(12, co.T - 3)), "OUTLINE")
		name:SetHeight(0)
		if co.vertical then
			name:SetPoint("TOP", esBtn, "BOTTOM", 0, -2); name:SetWidth(0)
		else
			name:SetPoint("CENTER", esBtn, "CENTER", 0, 0); name:SetWidth(c.lineLen)
		end
	end
	self:UpdateCompactES()
end

-- Charges come from the ES button's own updater (esButton subsystem, 2 Hz),
-- which keeps the charge text and cached target current.
function SP:UpdateCompactES()
	local esBtn = _G["ShamanPowerEarthShieldBtn"]
	if not esBtn or not esBtn.compactLayoutOn or not esBtn:IsShown() then return end
	local chargeText = _G["ShamanPowerEarthShieldBtnCharges"]
	local charges = chargeText and tonumber(chargeText:GetText() or "") or 0
	local active = self.currentEarthShieldTarget ~= nil and charges > 0
	self:PaintCompactSegments(esBtn.compactSeg, charges, active, self.opt.shieldChargeColors)
	if esBtn.compact then esBtn.compact.bg:Show() end
end

-- Per-tick paint of the lines (consolidated update system, 10 Hz).
function SP:UpdateCompactTotems()
	if not self:CompactActive() or not self.totemButtons then return end
	local now = GetTime()
	local assignments = ShamanPower_Assignments and self.player and ShamanPower_Assignments[self.player]
	for element = 1, 4 do
		local btn = self.totemButtons[element]
		local c = btn and btn.compact
		if c and btn.compactLayoutOn and btn:IsShown() then
			local slot = self.ElementToSlot[element]
			local haveTotem, _, startTime, duration, icon = GetTotemInfo(slot)
			if haveTotem and duration and duration > 0 then
				local frac = ((startTime + duration) - now) / duration
				if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
				local pulsePos, pulseRemain
				local pdata = self:GetActivePulsingTotem(slot)
				if pdata then
					pulsePos = ((now - startTime) % pdata.interval) / pdata.interval
					pulseRemain = pdata.interval * (1 - pulsePos)
				end
				local dim = btn.icon and btn.icon:IsDesaturated()
				self:PaintCompactVisuals(c, self.ElementColors[element], frac, dim, pulsePos, pulseRemain, icon, 1)
			else
				-- empty slot: gray line, the assigned totem ghosted in the square
				local idx = assignments and assignments[element] or 0
				local aicon = (idx and idx > 0) and self:GetTotemIcon(element, idx) or nil
				self:PaintCompactVisuals(c, nil, 0, false, nil, nil, aicon, 0.35)
			end
		end
	end
	self:UpdateCompactES()
end

-- Compact style has no "dropped totem pops above the assigned one": the line
-- is whatever is down. Called by UpdateActiveTotemOverlays while Compact is on.
function SP:HideActiveTotemOverlaysForCompact()
	for element = 1, 4 do
		local ov = self.activeTotemOverlays and self.activeTotemOverlays[element]
		if ov then
			if ov.frame then ov.frame:Hide() end
			ov.isActive = false
		end
		local btn = self.totemButtons and self.totemButtons[element]
		if btn and btn.assignedIndicator then btn.assignedIndicator:Hide() end
	end
end

-- Register the tick and (re)apply the layout to every bar button. Called at
-- the end of UpdateMiniTotemBar so it also runs after the range counters,
-- party dots and the Earth Shield button exist.
function SP:SetupCompactStyle()
	if not self.updateSystem then return end
	if not self.updateSystem.subsystems["compact"] then
		self:RegisterUpdateSubsystem("compact", 0.1, function() SP:UpdateCompactTotems() end)
	end
	local on = self:CompactActive()
	if on then self:EnableUpdateSubsystem("compact") else self:DisableUpdateSubsystem("compact") end
	if self.totemButtons then
		for element = 1, 4 do
			local btn = self.totemButtons[element]
			if btn then self:ApplyCompactButtonLayout(btn, self:IsElementPoppedOut(element)) end
		end
	end
	self:ApplyCompactESLayout()
end

-- Option change entry point (settings window + wizard).
function SP:ApplyCompactStyle()
	if InCombatLockdown() then
		print("|cffff0000ShamanPower:|r Cannot change the totem bar style during combat")
		return
	end
	if self.opt.compactStyle then
		self.opt.activeTotemAsMain = false
		self.opt.dynamicTotemMode = false
	end
	self:SetupCompactStyle()
	if self.UpdateLayout then self:UpdateLayout() end
	if self.UpdateMiniTotemBar then self:UpdateMiniTotemBar() end
	if self.UpdateActiveTotemOverlays then self:UpdateActiveTotemOverlays() end
	if self.UpdateTotemProgressBarPositions then self:UpdateTotemProgressBarPositions() end
	if self.UpdatePulseBarPositions then self:UpdatePulseBarPositions() end
	if self.RecreateTotemFlyouts then pcall(self.RecreateTotemFlyouts, self) end
	if self.UpdateTotemBarOpacity then self:UpdateTotemBarOpacity() end
	if self.UpdateCooldownBarScale then self:UpdateCooldownBarScale() end
end
