-- Dropped Totems (3.0.9, the owner's ask: "a dynamic totem bar that only shows whats dropped. No flyouts no
-- nothing else. just if you drop a totem it shows that, with all the pulse and all that but nothing else"):
-- a totem bar style, picked like the others (Totem Bar Style on General > Main and Totem Bar > Style, the
-- tour's cards). The bar is the totems you have down and nothing more: one picture per element, shown while
-- that element's totem is down, the ones down laid out as a group centered on the bar's spot, in the bar's
-- element order: one totem alone sits dead center, a second slides the first over, and they shift again
-- whenever one lands or ends, in a fight too. Each picture draws its totem's icon (in the Totem Bar Icon
-- Shape), the Duration Bars tab's bar and time, the Pulse Timer tab's pulse bar and the Effects tab's
-- expiring look, with the Normal bar's own painters and settings: nothing new to set up. Nothing on it can
-- be clicked and it ignores the mouse.
--
-- The bar's frame (ShamanPowerAuto) is the spot the player placed, the same spot as the Normal bar's. While
-- this style is on, Drop All and Totemic Call on the bar are switched off (and put back exactly as they were
-- when another style is picked), so that frame is the four slots and nothing else: its center is the
-- totems' center, and no separator line is drawn. The frame's backdrop goes too (ApplySkin).
--
-- In a fight: the pictures are plain frames of the addon's own, so the game lets them come and go, move and
-- resize then, and the totem model (GetElementTotemInfo, the shadow model on WoW: Forever) answers in a fight
-- on both clients. The Normal bar's buttons stay built, out of sight, so every keybind still casts (a hidden
-- button answers its key); Keybind Mode brings them back while it is open, and Unlock UI shows the four slots
-- faintly (the assigned totems) so the bar can be dragged with nothing down.
local SP = ShamanPower

local SLOT = 26                -- the icon bars' button size (GetTotemSlotDims)
local container                -- ShamanPowerDroppedTotems
local pics = {}                -- [element] = its picture
local shownSig                 -- the last layout (which pictures, in which order, which way)
local idle = 0                 -- passes with nothing down: the loop sleeps after a few
local queued                   -- an apply asked this frame (the hooks at the end): once
local isSecret = issecretvalue or function() return false end
local TEXTS = { "insideTextTop", "insideTextBottom", "aboveBarText", "belowBarText", "iconText" }
local TEXT_OF = { inside_top = "insideTextTop", inside_bottom = "insideTextBottom", above = "aboveBarText", below = "belowBarText", icon = "iconText" }
local NONE = "nil"             -- a saved setting that was unset

function SP:DroppedActive()
	return self.opt and self.opt.droppedTotems == true and not self:IsOff() or false
end

-- ShamanPowerCues.lua: the frame an element's expiring look plays on while this style is on
function SP:DroppedHost(element)
	if not self:DroppedActive() then return nil end
	local p = pics[element]
	if p and p.spDown and p:IsShown() then return p end
	return nil
end

-- the time as the Normal bar's duration texts show it (FormatDuration in ShamanPower.lua)
local timeCache = {}
local function timeText(seconds)
	local s = math.floor(seconds)
	if s < 0 then s = 0 end
	local t = timeCache[s]
	if t then return t end
	if s >= 3600 then t = math.floor(s / 3600) .. "h"
	elseif s >= 600 then t = math.floor(s / 60) .. "m"
	elseif s >= 60 then
		local m, r = math.floor(s / 60), s % 60
		t = m .. (r < 10 and ":0" or ":") .. r
	else t = tostring(s) end
	if s < 900 then timeCache[s] = t end
	return t
end

local function Container()
	if container then return container end
	if not SP.autoButton then return nil end
	container = CreateFrame("Frame", "ShamanPowerDroppedTotems", SP.autoButton)
	container:SetPoint("CENTER", SP.autoButton, "CENTER", 0, 0)
	container:SetSize(SLOT, SLOT)
	container:EnableMouse(false)
	container:Hide()
	return container
end

local function Pic(element)
	local p = pics[element]
	if p then return p end
	local c = Container()
	if not c then return nil end
	p = CreateFrame("Frame", "ShamanPowerDropped" .. element, c)
	p:SetSize(SLOT, SLOT)
	p:SetFrameLevel(c:GetFrameLevel() + 2)
	p:EnableMouse(false)
	p.element = element
	local icon = p:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints(p)
	p.icon = icon
	-- the duration bar and its time texts, as SetupTotemProgressBars makes them for a button
	local bars = {}
	bars.bg = p:CreateTexture(nil, "OVERLAY")
	bars.bg:SetColorTexture(0, 0, 0, 0.7)
	bars.bg:Hide()
	bars.bar = p:CreateTexture(nil, "OVERLAY", nil, 1)
	bars.bar:Hide()
	local textHost = SP:DurationTextHost(p, bars)   -- the time texts' frame, above the pulse bar
	for _, key in ipairs(TEXTS) do
		local fs = textHost:CreateFontString(nil, "OVERLAY", nil, (key == "insideTextTop" or key == "insideTextBottom") and 7 or nil)
		SP:SetSPFont(fs, "timers", key == "iconText" and 9 or 8, "OUTLINE")
		fs:SetTextColor(1, 1, 1)
		fs:Hide()
		bars[key] = fs
	end
	bars.iconText:SetPoint("CENTER", p, "CENTER", 0, 0)
	p.bars = bars
	-- the pulse bar: the Normal bar's own overlay object, on this picture
	p.pulse = SP:CreatePulseOverlay(p)
	pics[element] = p
	p:Hide()
	return p
end

-- the looks that follow a setting or a theme: the bar's color and texture, the texts' color,
-- the pulse bar's color, the icon's shape (asked again after each change: the hooks at the end)
local function Dress(p)
	local e = p.element
	local c = SP.DurationBarColors[e]
	if c then SP:SetSPBarColor(p.bars.bar, "duration", c[1], c[2], c[3], 1) end
	for _, key in ipairs(TEXTS) do SP:ThemePaintDurationText(p.bars[key], e) end
	SP:ThemePaintPulse(p.pulse, e)
	SP:ShapeIconTexture(p.icon, p.icon, "totem")
	local a = SP.opt.durationBarOpacity or 1
	p.bars.bg:SetAlpha(SP:DurationTrackAlpha(a))
	p.bars.bar:SetAlpha(a)
	-- Appearance > Themes' borders on the totem bar's boxes (ThemePaintTotemBorders' rule)
	local t = SP.opt.theme
	local edges = type(t) == "table" and t.borders == true
	if edges or p.spThemeBorder then SP:ThemeBorderEdges(p, edges, "tb.boxes", e) end
end

-- the duration bar and its texts where the Duration Bars tab puts them (UpdateTotemProgressBarPositions,
-- without the party dots' and flyout tabs' room: a picture has neither)
local function PlaceDuration(p)
	local o = SP.opt
	local pos, size = o.durationBarPosition or "bottom", o.durationBarHeight or 3
	local sig = pos .. ":" .. size
	if p.spDurSig == sig then return end
	p.spDurSig = sig
	local b = p.bars
	b.bg:ClearAllPoints(); b.bar:ClearAllPoints()
	b.insideTextTop:ClearAllPoints(); b.insideTextBottom:ClearAllPoints(); b.aboveBarText:ClearAllPoints(); b.belowBarText:ClearAllPoints()
	local sideways = false
	if pos == "bottom" then
		b.bg:SetHeight(size); b.bg:SetPoint("TOPLEFT", p, "BOTTOMLEFT", 0, -1); b.bg:SetPoint("TOPRIGHT", p, "BOTTOMRIGHT", 0, -1)
		b.bar:SetHeight(size); b.bar:SetPoint("TOPLEFT", p, "BOTTOMLEFT", 0, -1)
	elseif pos == "bottom_vert" then
		b.bg:SetWidth(size); b.bg:SetHeight(SLOT); b.bg:SetPoint("TOP", p, "BOTTOM", 0, -1)
		b.bar:SetWidth(size); b.bar:SetPoint("TOP", b.bg, "TOP", 0, 0)
	elseif pos == "top" then
		b.bg:SetHeight(size); b.bg:SetPoint("BOTTOMLEFT", p, "TOPLEFT", 0, 1); b.bg:SetPoint("BOTTOMRIGHT", p, "TOPRIGHT", 0, 1)
		b.bar:SetHeight(size); b.bar:SetPoint("BOTTOMLEFT", p, "TOPLEFT", 0, 1)
	elseif pos == "top_vert" then
		b.bg:SetWidth(size); b.bg:SetHeight(SLOT); b.bg:SetPoint("BOTTOM", p, "TOP", 0, 1)
		b.bar:SetWidth(size); b.bar:SetPoint("BOTTOM", b.bg, "BOTTOM", 0, 0)
	elseif pos == "left" then
		sideways = true
		b.bg:SetWidth(size); b.bg:SetPoint("TOPRIGHT", p, "TOPLEFT", -1, 0); b.bg:SetPoint("BOTTOMRIGHT", p, "BOTTOMLEFT", -1, 0)
		b.bar:SetWidth(size); b.bar:SetPoint("BOTTOMRIGHT", p, "BOTTOMLEFT", -1, 0)
	elseif pos == "right" then
		sideways = true
		b.bg:SetWidth(size); b.bg:SetPoint("TOPLEFT", p, "TOPRIGHT", 1, 0); b.bg:SetPoint("BOTTOMLEFT", p, "BOTTOMRIGHT", 1, 0)
		b.bar:SetWidth(size); b.bar:SetPoint("BOTTOMLEFT", p, "BOTTOMRIGHT", 1, 0)
	end
	b.insideTextTop:SetPoint("TOP", b.bg, "TOP", 0, -1)
	b.insideTextBottom:SetPoint("BOTTOM", b.bg, "BOTTOM", 0, 1)
	if sideways then
		local l, r = (pos == "left") and "RIGHT" or "LEFT", (pos == "left") and "LEFT" or "RIGHT"
		b.aboveBarText:SetPoint(l, b.bg, r, (pos == "left") and -1 or 1, 0)
		b.belowBarText:SetPoint(r, b.bg, l, (pos == "left") and 1 or -1, 0)
	else
		b.aboveBarText:SetPoint("BOTTOM", b.bg, "TOP", 0, 1)
		b.belowBarText:SetPoint("TOP", b.bg, "BOTTOM", 0, -1)
	end
	SP:PositionPulseWipe(p.pulse)
end

local function HideDuration(p)
	local b = p.bars
	b.bg:Hide(); b.bar:Hide()
	for _, key in ipairs(TEXTS) do b[key]:Hide() end
	p.spTextKey = nil
end

-- one picture's bar and time for a totem down since start for duration (UpdateTotemProgressBars)
local function PaintDuration(p, start, duration, now)
	local o = SP.opt
	local b = p.bars
	local remaining = (start + duration) - now
	local pct = remaining / duration
	if pct <= 0 or pct > 1 then HideDuration(p) return end
	local pos, size = o.durationBarPosition or "bottom", o.durationBarHeight or 3
	if pos == "none" then
		b.bg:Hide(); b.bar:Hide()
	else
		PlaceDuration(p)
		if pos == "left" or pos == "right" or pos == "top_vert" or pos == "bottom_vert" then
			b.bar:SetHeight(math.max(1, SLOT * pct)); b.bar:SetWidth(size)
		else
			b.bar:SetWidth(math.max(1, SLOT * pct)); b.bar:SetHeight(size)
		end
		if not b.bg:IsShown() then b.bg:Show(); b.bar:Show() end
	end
	local key = TEXT_OF[o.durationTextLocation or "none"]
	if key ~= p.spTextKey then
		for _, k in ipairs(TEXTS) do b[k]:Hide() end
		p.spTextKey = key
		if key then
			PlaceDuration(p)
			SP:SetSPFont(b[key], "timers", o.durationTextSize or 8, "OUTLINE")
			b[key]:Show()
		end
	end
	if key then
		local s = timeText(remaining)
		if p.spTimeStr ~= s then p.spTimeStr = s; b[key]:SetText(s) end
	end
end

-- the pictures in sight as one group centered on the bar's spot, in the bar's element order
local function Layout()
	local c = container
	if not c then return end
	local o = SP.opt
	local horizontal = o.layout == "Horizontal"
	local spacing = SP:TotemBarSpacing()
	local order = o.totemBarOrder or { 1, 2, 3, 4 }
	local unlocked = SP.IsMasterUnlocked and SP:IsMasterUnlocked() or false
	local list, sig = {}, ""
	for i = 1, 4 do
		local e = order[i]
		local p = pics[e]
		if p and (p.spDown or unlocked) and SP:IsElementShown(e) then
			list[#list + 1] = p
			sig = sig .. e .. (p.spDown and "d" or "u")
		end
	end
	sig = sig .. (horizontal and "h" or "v") .. ":" .. spacing
	if sig == shownSig then return end
	shownSig = sig
	for e = 1, 4 do
		local p = pics[e]
		if p and not p.spDown and not unlocked then p:Hide() end
	end
	local n = #list
	local total = n * SLOT + math.max(0, n - 1) * spacing
	for i, p in ipairs(list) do
		p:ClearAllPoints()
		local off = -total / 2 + (i - 1) * (SLOT + spacing) + SLOT / 2
		if horizontal then p:SetPoint("CENTER", c, "CENTER", off, 0) else p:SetPoint("CENTER", c, "CENTER", 0, -off) end
		if not p.spDown then
			-- Unlock UI, nothing down: the assigned totem, faint, so the bar has a shape to drag
			local btn = SP.totemButtons and SP.totemButtons[p.element]
			local tex = btn and btn.icon and btn.icon:GetTexture()
			if tex and p.spIcon ~= tex then p.icon:SetTexture(tex); p.spIcon = tex; SP:ShapeIconTexture(p.icon, p.icon, "totem") end
			p:SetAlpha(0.35)
		else
			p:SetAlpha(1)
		end
		Dress(p)
		p:Show()
	end
	if horizontal then c:SetSize(math.max(total, SLOT), SLOT) else c:SetSize(SLOT, math.max(total, SLOT)) end
end

-- the pass: what is down, each picture's bar, time and pulse; asleep while nothing is down
local function Pass()
	if not SP:DroppedActive() then return end
	local now = GetTime()
	local changed = false
	local any = false
	for e = 1, 4 do
		local p = Pic(e)
		if not p then return end
		local have, _, start, duration, icon = SP:GetElementTotemInfo(e)
		local down = have and not isSecret(have) and not isSecret(start) and not isSecret(duration)
			and type(start) == "number" and type(duration) == "number" and duration > 0 and (start + duration) > now
		if down ~= (p.spDown or false) then p.spDown = down or nil; changed = true end
		if down then
			any = true
			if icon and not isSecret(icon) and p.spIcon ~= icon then
				p.icon:SetTexture(icon); p.spIcon = icon
				SP:ShapeIconTexture(p.icon, p.icon, "totem")
			end
			PaintDuration(p, start, duration, now)
			local data, pstart = SP:GetActivePulsingTotem(e)
			if data and pstart and not isSecret(pstart) and SP.opt.pulseBarPosition ~= "none" then
				local pulse = p.pulse
				local barOff
				barOff, pulse._noFlash = SP:PulsePartsOff(data)
				pulse._noBar = barOff
				local age = SP:PulseVisualSync(pulse, pstart, data.interval, now)
				SP:PulseVisualText(pulse, data.interval - (age % data.interval), (not barOff and SP.opt.pulseTimeDisplay) or "none")
			else
				SP:PulseVisualStop(p.pulse)
			end
		elseif p.spTextKey ~= nil or p.bars.bg:IsShown() then
			HideDuration(p)
			SP:PulseVisualStop(p.pulse)
		end
	end
	if changed then Layout() end
	if any then
		idle = 0
	else
		idle = idle + 1
		if idle > 2 then
			local us = SP.updateSystem
			if us and us.totemSleepers then
				us.totemSleepers.dropped = true
				SP:SleepUpdateSubsystem("dropped")
			end
		end
	end
end

-- Drop All and Totemic Call on the bar: off while the style is on (the bar's frame is then the four
-- slots, its center the totems' center, no separator), and back exactly as they were when it goes
local function ExtrasOff(self)
	local o = self.opt
	if o.droppedSaved then return false end
	local items = o.cdbarItem
	local recall = items and items[2] and items[2].onTotemBar
	o.droppedSaved = { dropAll = (o.showDropAllButton == nil) and NONE or o.showDropAllButton, recall = (recall == nil) and NONE or recall }
	o.showDropAllButton = false
	if recall ~= false and self.SetCdItemOpt then self:SetCdItemOpt(2, "onTotemBar", false) end
	return true
end
local function ExtrasBack(self)
	local o = self.opt
	local saved = o.droppedSaved
	if not saved then return false end
	o.droppedSaved = nil
	if saved.dropAll == NONE then o.showDropAllButton = nil else o.showDropAllButton = saved.dropAll end
	if self.SetCdItemOpt then
		if saved.recall == NONE then self:SetCdItemOpt(2, "onTotemBar", nil) else self:SetCdItemOpt(2, "onTotemBar", saved.recall) end
	end
	return true
end

-- the style on or off: the Normal bar's parts out of sight or back, the pictures up or down.
-- Out of a fight only; asked in one, the fight's end runs it
function SP:ApplyDroppedTotems()
	if InCombatLockdown() then self._droppedApplyLater = true return end
	local on = self:DroppedActive()
	local c = on and Container()
	if on and c and not (self.KeybindModeActive and self:KeybindModeActive()) then
		local relaid = ExtrasOff(self)
		for e = 1, 4 do
			local b = self.totemButtons and self.totemButtons[e]
			if b and not (self.IsElementPoppedOut and self:IsElementPoppedOut(e)) then b:Hide() end
			Pic(e)
		end
		for _, name in ipairs({ "ShamanPowerAutoDropAll", "ShamanPowerAutoTotemicCall", "ShamanPowerTotemicCallBtn", "ShamanPowerEarthShieldBtn", "ShamanPowerCompactShieldBtn" }) do
			local f = _G[name]
			if f then f:Hide() end
		end
		local sep = _G.ShamanPowerAutoSeparator
		if sep then sep:Hide() end
		if self.HideActiveTotemOverlaysForCompact then self:HideActiveTotemOverlaysForCompact() end
		if self.autoButton and not self.autoButton.spDroppedMouse then
			self.autoButton.spDroppedMouse = true
			self.autoButton:EnableMouse(false)   -- (nothing to click; Unlock UI drags by its own box)
		end
		if not self.updateSystem.subsystems.dropped then
			self:RegisterUpdateSubsystem("dropped", 0.05, Pass)
		end
		self:EnableUpdateSubsystem("dropped")
		shownSig = nil
		idle = 0
		for e = 1, 4 do local p = pics[e]; if p then p.spDurSig = nil end end
		c:Show()
		Pass()
		Layout()
		if relaid then self:UpdateMiniTotemBar() end   -- the frame as the four slots alone (its center: the totems')
	else
		if container then container:Hide() end
		for e = 1, 4 do
			local p = pics[e]
			if p then p.spDown = nil; HideDuration(p); self:PulseVisualStop(p.pulse); p:Hide() end
		end
		shownSig = nil
		self:DisableUpdateSubsystem("dropped")
		if self.autoButton and self.autoButton.spDroppedMouse then
			self.autoButton.spDroppedMouse = nil
			self.autoButton:EnableMouse(true)
		end
		if not on and ExtrasBack(self) then
			self:UpdateMiniTotemBar()
			if self.UpdateDropAllButton then self:UpdateDropAllButton() end
		end
		-- Keybind Mode with the style on: the Normal bar back for its labels, the pictures down meanwhile
		if on and self.SetTotemBarFramesShown then self:SetTotemBarFramesShown(true) end
	end
end

local function Queue()
	if queued then return end
	queued = true
	C_Timer.After(0, function()
		queued = nil
		if SP.opt and (SP:DroppedActive() or container or SP.opt.droppedSaved) then SP:ApplyDroppedTotems() end
	end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_TOTEM_UPDATE")
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_REGEN_ENABLED" then
		if SP._droppedApplyLater then SP._droppedApplyLater = nil; Queue() end
	elseif SP.opt and SP:DroppedActive() and container and container:IsShown() then
		-- a totem landed or went: at once, not on the next tick (and the loop awake again)
		idle = 0
		SP:WakeUpdateSubsystem("dropped")
		Pass()
	end
end)

-- the bar is laid out, shown, hidden and dressed in many places: after each, the style's say
for _, name in ipairs({ "UpdateMiniTotemBar", "UpdateLayout", "PositionTotemButtons", "UpdateTotemBarVisibility", "SetTotemBarFramesShown",
	"UpdateDropAllButton", "UpdateEarthShieldButton", "UpdateActiveTotemOverlays", "ApplyCompactStyle", "SetKeybindMode",
	"RefreshUnlockBoxes", "UpdateTotemProgressBarPositions", "UpdatePulseBarPositions", "ApplyDurationBarOpacity",
	"RefreshIconShapes", "ThemePaintTotemBorders", "RepaintPulseBarColors" }) do
	if type(SP[name]) == "function" then hooksecurefunc(SP, name, Queue) end
end
-- a theme or a color changed one element's bar: this element's picture too
if type(SP.ThemePaintDurationBars) == "function" then
	hooksecurefunc(SP, "ThemePaintDurationBars", function(_, element)
		local p = pics[element]
		if p and p:IsShown() then Dress(p) end
	end)
end
