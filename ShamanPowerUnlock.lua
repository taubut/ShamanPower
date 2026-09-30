-- ShamanPowerUnlock.lua
-- "Unlock UI": one switch that puts every movable piece of ShamanPower on screen
-- at once, each under a labelled blue box that can be dragged, with a bar at the
-- top to finish. The per-module unlock toggles (Shield Charges "Lock Position",
-- Ready Reminders "Unlock Positions", ALT+drag on the reminders ...) are left
-- exactly as they are: nothing here reads or writes them. The boxes sit above
-- the real frames and move them from outside, so a frame's own lock state never
-- matters and there is nothing to restore afterwards.
--
-- What is shown comes from the preview registry the setup tour already uses
-- (ShamanPowerPreview.lua): each module registers its frame(s) and a Demo(on)
-- method that fills them with sample content, which is what makes an alert or
-- a reminder that is normally invisible something you can grab.
--
-- Out of combat only: the bars are protected frames. A fight ends the mode.

local SP = ShamanPower
if not SP then return end

local ACTIVE = false
local onlyKey           -- the one module unlocked by itself (a "move these" button), else nil
local shown = {}        -- mover keys that are up
local demos = {}        -- registry keys whose Demo(true) was called
local forced = {}       -- frames that were hidden before we showed them
local doneBar

-- ---------------------------------------------------------------------------
-- Saving: a module frame's own drag-end script is its "save my position" code.
-- The mover has already placed the frame; running that script records it in
-- the module's own format.
-- ---------------------------------------------------------------------------
local function SaveThroughOwnScripts(frame)
	frame.isMoving = true   -- Ready Reminders / Reactive Totems only save "while moving"
	for _, script in ipairs({ "OnDragStop", "OnMouseUp" }) do
		local handler = frame:GetScript(script)
		if handler then pcall(handler, frame, "LeftButton") end
	end
	frame.isMoving = nil
end

local function DB(name) return _G[name] end

-- Modules in the order they are listed. `frames` overrides the registry's own
-- list; `enabled` keeps a module the player has switched off out of the way;
-- `save` / `reset` replace the generic ones.
-- The unlock loop below boxes a module only when a preview is registered under
-- the same key (PreviewRegistry[m.key] ~= nil). The loadout bar never had one,
-- so its entry was skipped before any box could be drawn; give it a frame-only
-- registration here (Preview.lua has loaded by now).
if SP.RegisterPreview and SP.PreviewRegistry and not SP.PreviewRegistry.loadoutbar then
	SP:RegisterPreview("loadoutbar", { frame = "ShamanPowerSetAnchor" })
end

local MODULES = {
	{ key = "shieldcharges", label = "Shield Charges", labels = { "Shield Charges", "Earth Shield Charges" },
		-- the real frames only: the preview's own Water Shield frame (the settings
		-- preview draws Water apart; in play it shows in the player frame) got a box
		-- named "Earth Shield Charges", and the real Earth frame "Shield Charges 3"
		frames = function()
			if not (SP.shieldChargeFrames and SP.shieldChargeFrames.player) and SP.CreateShieldChargeDisplays then SP:CreateShieldChargeDisplays() end
			local f, s, out = SP.shieldChargeFrames or {}, SP.opt.shieldChargeDisplay, {}
			if f.player and (not s or s.showPlayerShield ~= false) then
				f.player.spMoverLabel = "Shield Charges"
				out[#out + 1] = f.player
			end
			if f.earth and not ShamanPower.ESTrackerUnavailable and s and s.showEarthShield == true then
				f.earth.spMoverLabel = "Earth Shield Charges"
				out[#out + 1] = f.earth
			end
			return out
		end,
		reset = function()
			local s = SP.opt.shieldChargeDisplay
			if not s then return end
			s.playerShieldX, s.playerShieldY, s.earthShieldX, s.earthShieldY = nil, nil, nil, nil
			local f = SP.shieldChargeFrames
			if f and f.player then f.player:ClearAllPoints(); f.player:SetPoint("CENTER", UIParent, "CENTER", -50, -100) end
			if f and f.earth then f.earth:ClearAllPoints(); f.earth:SetPoint("CENTER", UIParent, "CENTER", 50, -100) end
		end,
		enabled = function()
			local s = SP.opt.shieldChargeDisplay
			return not s or s.showPlayerShield ~= false or s.showEarthShield == true
		end },
	{ key = "readyreminders", label = "Ready Reminder", reset = "ResetReadyReminderPositions",
		-- only the reminders that are switched on get a box (Grid placement: one box for the block)
		frames = function() return SP.ReadyReminderMoverFrames and SP:ReadyReminderMoverFrames() or {} end,
		enabled = function() local d = DB("ShamanPower_ReadyReminders"); return not d or d.enabled ~= false end },
	{ key = "expiring", label = "Expiring Alerts", reset = "ExpiringAlertsReset",
		enabled = function() local d = DB("ShamanPowerExpiringAlertsDB"); return not d or d.enabled ~= false end,
		save = function(frame)
			local d = DB("ShamanPowerExpiringAlertsDB")
			local point, _, _, x, y = frame:GetPoint()
			if d and point then d.position = { point = point, x = x, y = y } end
			local pos = SP.expiringAlertsPosFrame   -- the module's own positioning box follows
			if pos and point then pos:ClearAllPoints(); pos:SetPoint(point, UIParent, point, x, y) end
		end },
	{ key = "reactive", label = "Reactive Totem", labels = { "Reactive: Fear", "Reactive: Poison", "Reactive: Disease" }, reset = "ResetReactiveTotemPositions",
		enabled = function() local d = DB("ShamanPower_ReactiveTotems"); return not d or d.enabled ~= false end },
	{ key = "tremor", label = "Tremor Reminder", reset = "TremorReminderReset",
		enabled = function() local d = DB("ShamanPowerTremorReminderDB"); return not d or d.enabled ~= false end },
	{ key = "partyrange", label = "Party Range Counter",
		enabled = function()
			local rc = SP.opt.rangeCounter
			return rc and rc.enabled and rc.location == "unlocked" and true or false   -- otherwise the counters ride on the totem buttons
		end,
		frames = function()
			local out = {}
			for element = 1, 4 do
				local ok, f = pcall(SP.CreateRangeCounterFrame, SP, element)
				if ok and f then out[#out + 1] = f end
			end
			return out
		end,
		labels = { "Range: Earth", "Range: Fire", "Range: Water", "Range: Air" } },
	{ key = "coverage", label = "Totem Coverage", reset = "ResetCoveragePositions",
		enabled = function() return SP.opt.coverage and SP.opt.coverage.enabled and true or false end,
		frames = function()
			local f = SP.CreateCoverageFrame and SP:CreateCoverageFrame()
			if not f then return {} end
			if SP.opt.coverage and SP.opt.coverage.freeCells and SP.CoverageWatchedCells then   -- one box per watched totem
				return SP:CoverageWatchedCells()
			end
			return { f }
		end },
	{ key = "loadoutbar", label = "Loadout Bar",
		enabled = function() return SP.opt.showLoadoutBar and true or false end,
		frames = function() return SP.loadoutAnchor and { SP.loadoutAnchor } or {} end,
		-- the anchor's own drag scripts want ALT and an unlocked bar; the box moves it directly
		save = function() if SP.SaveLoadoutBarPosition then SP:SaveLoadoutBarPosition() end end,
		reset = function()
			local a = SP.loadoutAnchor
			if not a then return end
			a:ClearAllPoints(); a:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
			if SP.SaveLoadoutBarPosition then SP:SaveLoadoutBarPosition() end
		end },
	{ key = "sprange", label = "Totem Range" },
	{ key = "raidcd", label = "Raid Cooldown Callers" },
	{ key = "estracker", label = "Earth Shield Tracker",
		enabled = function()
			if SPCompat and SPCompat.earthShieldExists == false then return false end
			return SP.opt.esTracker and SP.opt.esTracker.enabled and true or false
		end },
}
-- Files that load later (Ready Check) add their own entries here.
SP.UnlockModules = MODULES

-- Movers resolve existing split-row pop-outs lazily; these registrations are
-- never borrowed into a settings preview (the rows have secure children).
for element, name in ipairs({ "earth", "fire", "water", "air" }) do
	local index = element
	local key = "grid_" .. name
	local function rowFrame()
		return SP.GetGridRowFrame and SP:GetGridRowFrame(index)
	end
	if SP.RegisterPreview then SP:RegisterPreview(key, { frame = rowFrame }) end
	MODULES[#MODULES + 1] = {
		key = key, label = "Grid: " .. name:sub(1, 1):upper() .. name:sub(2),
		enabled = function()
			return SP.GridActive and SP:GridActive() and SP.opt.gridSplit and rowFrame() ~= nil
		end,
		reset = function()
			if SP.ResetGridRowPosition then SP:ResetGridRowPosition(index) end
		end,
	}
end

local function ResolveFrames(def)
	local out = {}
	local function one(f)
		if type(f) == "function" then local ok, r = pcall(f); f = ok and r or nil end
		if type(f) == "string" then f = _G[f] end
		if type(f) == "table" and f.GetObjectType then out[#out + 1] = f end
	end
	if def.frames then for _, f in ipairs(def.frames) do one(f) end else one(def.frame) end
	return out
end

local function DemoMethod(def)
	if not def.demo then return nil end
	return SP[(def.demo):match("^SP:(.+)$") or def.demo]
end

-- ---------------------------------------------------------------------------
-- One blue box (reuses the bar mover) plus a small Reset button on it.
-- ---------------------------------------------------------------------------
local function AddReset(moverKey, resetFn)
	local mover = SP.barMovers and SP.barMovers[moverKey]
	if not mover then return end
	if not mover.spReset then
		-- a secondary button at the compact height buttons have in header bands
		-- (22), as wide as CreateSPButton makes it (text + 28); solid
		-- underneath, as it sits over the world
		local b = SP:CreateSPButton(mover, "Reset", 0, false)
		b:SetHeight(22)
		b:SetPoint("BOTTOMRIGHT", mover, "TOPRIGHT", 0, 1)
		local base = b:CreateTexture(nil, "BACKGROUND", nil, -1); base:SetAllPoints(); base:SetColorTexture(SP:SPColor("windowBg", 0.95))
		-- hooked: the button's own OnEnter/OnLeave draw its hover
		b:HookScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText("Put this one back where it starts", 1, 1, 1); GameTooltip:Show() end)
		b:HookScript("OnLeave", function() GameTooltip:Hide() end)
		b:SetScript("OnClick", function(self)
			if InCombatLockdown() or not self.resetFn then return end
			pcall(self.resetFn)
			SP:RefreshUnlockBoxes()
			C_Timer.After(0, function() SP:RefreshUnlockBoxes() end)   -- again once the moved frames are laid out
		end)
		mover.spReset = b
	end
	mover.spReset.resetFn = resetFn
	mover.spReset:SetShown(resetFn ~= nil)
end

-- A frame may name (or compute) the frame the box should be sized to.
local function MoverSize(frame)
	local size = frame.spMoverSize
	if type(size) == "function" then size = size() end
	return size or frame
end

-- In Unlock UI a box takes the mouse wheel (size / opacity); outside it the wheel
-- over a box zooms the camera as usual.
local function ArmMover(moverKey)
	local m = SP.barMovers and SP.barMovers[moverKey]
	if m then m:EnableMouseWheel(true) end
end

local function ShowBox(moverKey, frame, label, save, resetFn)
	if not (frame and frame.GetLeft) then return end
	if not frame:IsShown() then forced[frame] = true; frame:Show() end
	if not frame:GetLeft() then return end   -- still not laid out: nothing to put a box on
	SP:ShowBarMover(moverKey, frame, MoverSize(frame), label, function() save(frame) end)
	shown[moverKey] = { frame = frame, label = label, save = save, reset = resetFn }
	AddReset(moverKey, resetFn)
	ArmMover(moverKey)
end

function SP:RefreshUnlockBoxes()
	if not ACTIVE or InCombatLockdown() then return end
	for moverKey, e in pairs(shown) do
		if e.bar then
			-- the two bars re-place their own movers
			if moverKey == "totembar" then SP:SetTotemBarUnlocked(true) else SP:SetCooldownBarUnlocked(true) end
		elseif e.frame and e.frame:GetLeft() then
			SP:ShowBarMover(moverKey, e.frame, MoverSize(e.frame), e.label, function() e.save(e.frame) end)
		end
		AddReset(moverKey, e.reset)
		ArmMover(moverKey)
	end
end

-- ---------------------------------------------------------------------------
-- The two bars
-- ---------------------------------------------------------------------------
-- Both drop the saved spot; the bars then go on their default spots (the
-- totem bar's Reset brings the cooldown bar back under it as well).
local function ResetTotemBar() SP:ResetBarPositions(true) end
local function ResetCooldownBar() SP:ResetBarPositions(false) end

-- ---------------------------------------------------------------------------
-- The bar at the top of the screen
-- ---------------------------------------------------------------------------
local function ConfirmResetAll()
	SP:ShowSPDialog({
		key = "unlock_reset_all",
		title = "Reset all positions?",
		text = "Put every ShamanPower element back where it starts?\n\nThis resets positions only, not settings.",
		buttons = {
			{ text = "Reset All", onClick = function() SP:ResetAllUnlockPositions() end },
			{ text = "Cancel" },
		},
	})
end

-- ---------------------------------------------------------------------------
-- Moving the boxes: they snap as they are dragged (to each other, the screen
-- center and the grid, gold lines showing to what), the arrow keys nudge the
-- picked box, the mouse wheel sets its size and Ctrl + wheel its opacity,
-- right-click opens its settings page.
--
-- Adapted from ShamanForever's positioning mode (ShamanForever_Positioning.lua),
-- Copyright (c) 2026 Michael Cassidy, under the MIT License:
--   Permission is hereby granted, free of charge, to any person obtaining a copy
--   of this software and associated documentation files (the "Software"), to deal
--   in the Software without restriction, including without limitation the rights
--   to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
--   copies of the Software, subject to including the above copyright notice and
--   this permission notice in all copies or substantial portions of the Software.
--   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.
--
-- Nothing here runs outside Unlock UI; in it, only while a box is dragged or an
-- arrow key is held.
-- ---------------------------------------------------------------------------
local SNAP = 8             -- UIParent px: how close an edge or center must come to snap
local GRID_DEFAULT = 16

local function SnapOn() return not (SP.opt and SP.opt.unlockSnap == false) end
local function GridOn() return ACTIVE and SP.opt and SP.opt.unlockGrid and true or false end
local function GridSize()
	local g = tonumber(SP.opt and SP.opt.unlockGridSize) or GRID_DEFAULT
	return math.min(math.max(g, 8), 128)
end

-- Snap step in UIParent pixels while Unlock UI's grid is on, else nil.
function SP:UnlockGridStep()
	return GridOn() and GridSize() or nil
end

-- The grid: lines every Grid Size pixels from the screen center (the two center
-- lines brighter). Drawn again only when its size or the screen's changes.
local gridFrame, gridKey
local gridLines = {}
local function DrawGrid()
	if not gridFrame then
		gridFrame = CreateFrame("Frame", "ShamanPowerUnlockGrid", UIParent)
		gridFrame:SetAllPoints(UIParent)
		gridFrame:SetFrameStrata("BACKGROUND")
		gridFrame:EnableMouse(false)
		gridFrame:Hide()
	end
	local step = GridSize()
	local w, h = UIParent:GetWidth(), UIParent:GetHeight()
	local key = step .. ":" .. math.floor(w) .. "x" .. math.floor(h)
	if key == gridKey then return end
	gridKey = key
	local n = 0
	local function line(vertical, offset, centre)
		n = n + 1
		local t = gridLines[n]
		if not t then t = gridFrame:CreateTexture(nil, "ARTWORK"); gridLines[n] = t end
		t:ClearAllPoints()
		if centre then t:SetColorTexture(0.25, 0.66, 1, 0.55) else t:SetColorTexture(1, 1, 1, 0.12) end
		if vertical then
			t:SetWidth(1)
			t:SetPoint("TOP", gridFrame, "TOP", offset, 0); t:SetPoint("BOTTOM", gridFrame, "BOTTOM", offset, 0)
		else
			t:SetHeight(1)
			t:SetPoint("LEFT", gridFrame, "LEFT", 0, offset); t:SetPoint("RIGHT", gridFrame, "RIGHT", 0, offset)
		end
		t:Show()
	end
	for k = 0, math.ceil(w / 2 / step) do
		line(true, k * step, k == 0)
		if k > 0 then line(true, -k * step, false) end
	end
	for k = 0, math.ceil(h / 2 / step) do
		line(false, k * step, k == 0)
		if k > 0 then line(false, -k * step, false) end
	end
	for i = n + 1, #gridLines do gridLines[i]:Hide() end
end

local function ApplyGrid()
	if GridOn() then DrawGrid(); gridFrame:Show() elseif gridFrame then gridFrame:Hide() end
	if doneBar and doneBar.Refresh then doneBar:Refresh() end
end

-- Gold lines showing what a dragged box has snapped to (made on the first snap).
local guides
local function ShowGuides(gx, gy)
	if not guides then
		if not (gx or gy) then return end
		guides = CreateFrame("Frame", nil, UIParent)
		guides:SetAllPoints(UIParent)
		guides:SetFrameStrata("FULLSCREEN")   -- over the frames, under the boxes
		guides:EnableMouse(false)
		guides.x = guides:CreateTexture(nil, "ARTWORK")
		guides.x:SetColorTexture(1, 0.82, 0, 0.85)
		guides.x:SetWidth(1)
		guides.y = guides:CreateTexture(nil, "ARTWORK")
		guides.y:SetColorTexture(1, 0.82, 0, 0.85)
		guides.y:SetHeight(1)
	end
	guides.x:SetShown(gx ~= nil)
	guides.y:SetShown(gy ~= nil)
	if gx then
		guides.x:ClearAllPoints()
		guides.x:SetPoint("TOP", guides, "TOPLEFT", gx, 0)
		guides.x:SetPoint("BOTTOM", guides, "BOTTOMLEFT", gx, 0)
	end
	if gy then
		guides.y:ClearAllPoints()
		guides.y:SetPoint("LEFT", guides, "BOTTOMLEFT", 0, gy)
		guides.y:SetPoint("RIGHT", guides, "BOTTOMRIGHT", 0, gy)
	end
end

-- One axis: pos is the box's center, half its half-size, targets[1..n] other
-- boxes' edges and centers (and the screen center). A target within SNAP of the
-- box's either edge or center wins and returns a guide line; otherwise, with a
-- grid, the nearest of those three lands on a grid line.
local EDGES = { -1, 0, 1 }
local function SnapAxis(pos, half, targets, n, origin, step)
	local best, shift, guide = SNAP, nil, nil
	for i = 1, n do
		local t = targets[i]
		for _, e in ipairs(EDGES) do
			local d = t - (pos + e * half)
			if math.abs(d) <= best then best, shift, guide = math.abs(d), d, t end
		end
	end
	if shift then return pos + shift, guide end
	if step then
		for _, e in ipairs(EDGES) do
			local p = pos + e * half
			local d = origin + math.floor((p - origin) / step + 0.5) * step - p
			if not shift or math.abs(d) < math.abs(shift) then shift = d end
		end
		return pos + shift
	end
	return pos
end

-- Dragging by hand (not StartMoving), so the box snaps while it moves; the drop
-- then moves the real frame as before (ShamanPower.lua GetBarMover).
local tx, ty = {}, {}   -- snap targets, refilled each drag frame
local function DragUpdate(self)
	if not ACTIVE or InCombatLockdown() then self:SetScript("OnUpdate", nil); ShowGuides(); return end
	local uis = UIParent:GetEffectiveScale()
	local cx, cy = GetCursorPosition()
	local x, y = cx / uis + self.spDragDX, cy / uis + self.spDragDY
	local s = self:GetEffectiveScale() / uis
	local step = SP:UnlockGridStep()
	local snap = SnapOn()
	local gx, gy
	if snap or step then
		local w, h = UIParent:GetSize()
		local n = 0
		if snap then
			n = 1
			tx[1], ty[1] = w / 2, h / 2
			for _, m in pairs(SP.barMovers) do
				if m ~= self and m:IsShown() and m:GetLeft() then
					local ms = m:GetEffectiveScale() / uis
					local l, r, b, t = m:GetLeft() * ms, m:GetRight() * ms, m:GetBottom() * ms, m:GetTop() * ms
					tx[n + 1], tx[n + 2], tx[n + 3] = l, (l + r) / 2, r
					ty[n + 1], ty[n + 2], ty[n + 3] = b, (b + t) / 2, t
					n = n + 3
				end
			end
		end
		x, gx = SnapAxis(x, self:GetWidth() * s / 2, tx, n, w / 2, step)
		y, gy = SnapAxis(y, self:GetHeight() * s / 2, ty, n, h / 2, step)
	end
	ShowGuides(gx, gy)
	self:ClearAllPoints()
	self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / s, y / s)
end

-- The picked box: gold edges, and the arrow keys move it.
local selected
local Select   -- (below)

local function PaintSelected(m, on)
	if not (m and m.spEdges) then return end
	for _, t in ipairs(m.spEdges) do
		if on then t:SetColorTexture(1, 0.82, 0, 1) else t:SetColorTexture(0.247, 0.663, 1, 0.9) end
	end
end

-- The arrow keys move the picked box by 1 px (Shift: 10), repeating while held;
-- Escape lets it go. Keys are taken only while a box is picked, out of combat,
-- and only for the press itself (the frame lets every other key through, and
-- goes back to passing keys on the next frame), so a fight can never start with
-- a key stuck here: the mode ends on PLAYER_REGEN_DISABLED, before the lockdown.
local NUDGE = { UP = { 0, 1 }, DOWN = { 0, -1 }, LEFT = { -1, 0 }, RIGHT = { 1, 0 } }
local nudger

local function Nudge(key)
	local d = NUDGE[key]
	if not (d and selected and selected:IsShown()) then return end
	local step = IsShiftKeyDown() and 10 or 1
	SP:NudgeBarMover(selected, d[1] * step, d[2] * step)
end

local function HeldUpdate(self, elapsed)
	self.wait = self.wait - elapsed
	if self.wait <= 0 then
		Nudge(self.held)
		self.wait = 0.04
	end
end

local function SyncNudger()
	local on = selected ~= nil and ACTIVE and not InCombatLockdown()
	if on and not nudger then
		nudger = CreateFrame("Frame", "ShamanPowerUnlockNudge", UIParent)
		nudger:Hide()
		nudger:SetScript("OnKeyDown", function(self, key)
			if InCombatLockdown() then self:Hide() return end
			if NUDGE[key] or key == "ESCAPE" then
				self:SetPropagateKeyboardInput(false)
				C_Timer.After(0, function() if not InCombatLockdown() then self:SetPropagateKeyboardInput(true) end end)
				if key == "ESCAPE" then Select(nil) return end
				Nudge(key)
				self.held, self.wait = key, 0.4
				self:SetScript("OnUpdate", HeldUpdate)
			else
				self:SetPropagateKeyboardInput(true)   -- any other key goes on to the game
			end
		end)
		nudger:SetScript("OnKeyUp", function(self, key)
			if key == self.held then self.held = nil; self:SetScript("OnUpdate", nil) end
		end)
		nudger:SetScript("OnHide", function(self) self.held = nil; self:SetScript("OnUpdate", nil) end)
	end
	if on and not nudger.keys then
		nudger:EnableKeyboard(true)   -- out of combat only (restricted in combat)
		nudger.keys = true
	end
	-- passing every other key through, each time it is shown: a fight can start between
	-- an arrow press and the next frame's restore, which then must not carry over
	if on then nudger:SetPropagateKeyboardInput(true) end
	if nudger then nudger:SetShown(on) end
end

Select = function(m)
	if selected == m then return end
	if selected then PaintSelected(selected, false) end
	selected = m
	if m then PaintSelected(m, true) end
	SyncNudger()
end

-- What the wheel and right-click reach on each element (the box's module key):
-- its settings page, and its size and opacity. A size or opacity names the
-- settings slider it goes through (its own get / set and limits, so the wheel
-- can set nothing the settings page could not). No opacity where that setting
-- does not apply on the spot: Expiring Alerts (the next alert), Ready Check (the
-- list's background only).
local FX = {
	totembar       = { page = { "fluffy", "totembar_appearance" },    size = { node = "buffscale" },           opacity = { node = "totemBarOpacity" } },
	cooldownbar    = { page = { "fluffy", "cooldownbar_appearance" }, size = { node = "cooldownBarScale" },    opacity = { node = "cooldownBarOpacity" } },
	shieldcharges  = { page = { "fluffy", "shieldcharges_section" },  size = { node = "shieldcharges_scale" }, opacity = { node = "shieldcharges_opacity" } },
	readyreminders = { page = { "fluffy", "readyreminders_section" },
		size = { node = "iconSize", under = "readyreminders_section" }, opacity = { node = "opacity", under = "readyreminders_section" } },
	expiring       = { page = { "fluffy", "expiringalerts_section" }, size = { node = "alerts_icon_size" } },
	reactive       = { page = { "fluffy", "reactivetotems_section" }, size = { node = "reactive_icon_size" },  opacity = { node = "reactive_opacity" } },
	tremor         = { page = { "fluffy", "tremorreminder_section" }, size = { node = "tremor_icon_size" },    opacity = { node = "tremor_opacity" } },
	partyrange     = { page = { "fluffy", "partybuff_section" },      size = { node = "partybuff_scale" },     opacity = { node = "partybuff_opacity" } },
	coverage       = { page = { "fluffy", "coverage_section" },       size = { node = "coverage_icon_size" },  opacity = { node = "coverage_opacity" } },
	loadoutbar     = { page = { "fluffy", "loadoutbar_section" },     size = { node = "loadoutbar_scale" },    opacity = { node = "loadoutbar_opacity" } },
	sprange        = { page = { "fluffy", "sprange_section" },        size = { node = "sprange_icon_size" },   opacity = { node = "sprange_opacity" } },
	raidcd         = { page = { "fluffy", "raid_cd_section" },        size = { node = "raidCDButtonScale" },   opacity = { node = "raidCDButtonOpacity" } },
	estracker      = { page = { "fluffy", "estrack_section" },        size = { node = "estrack_icon_size" },   opacity = { node = "estrack_opacity" } },
	readycheck     = { page = { "fluffy", "readycheck_section" },     size = { node = "panelScale", under = "readycheck_section" } },
}
-- the split Grid style's rows are pop-out trackers: their own scale and opacity
for _, name in ipairs({ "earth", "fire", "water", "air" }) do
	local pop = "totem_" .. name
	local function saved() return SP.opt.poppedOutSettings and SP.opt.poppedOutSettings[pop] end
	FX["grid_" .. name] = { page = { "fluffy", "popout_section" }, pick = { node = "selected_tracker", value = pop },
		size = { pct = true, min = 0.5, max = 3, step = 0.05,
			get = function() local s = saved(); return s and s.scale or SP.opt.poppedOutDefaultScale or 1 end,
			set = function(v) SP:SetPopOutScale(pop, v) end },
		opacity = { pct = true, min = 0.1, max = 1, step = 0.05,
			get = function() local s = saved(); return s and s.opacity or 1 end,
			set = function(v) SP:SetPopOutOpacity(pop, v) end } }
end

-- a box's module key: "unlock_<key>_<n>", or the two bars' own keys
local function ModuleKeyOf(mover)
	local key = mover and mover.key
	return key and (key:match("^unlock_(.+)_%d+$") or key) or nil
end

-- The first option named `key` in the settings table (under the group `under`),
-- of the type `kind` ("range" when not given).
local function FindOption(key, under, kind)
	kind = kind or "range"
	local function walk(node, inside)
		local args = node.args
		if type(args) ~= "table" then return nil end
		for k, child in pairs(args) do
			if type(child) == "table" then
				local here = inside or k == under
				if here and k == key and child.type == kind then return child end
				local found = walk(child, here)
				if found then return found end
			end
		end
	end
	return SP.options and walk(SP.options, under == nil) or nil
end

-- A size or opacity: get, set, min, max, step, shown as % (nil when there is none,
-- or its slider is hidden or disabled right now, like the settings page).
local function Access(spec)
	if not spec then return nil end
	if spec.get then return spec.get, spec.set, spec.min, spec.max, spec.step, spec.pct end
	local node = spec._node
	if node == nil then node = FindOption(spec.node, spec.under) or false; spec._node = node end
	if not node or type(node.get) ~= "function" or type(node.set) ~= "function" then return nil end
	local info = spec._info
	if not info then info = { spec.node, option = node, type = "range" }; spec._info = info end
	local function flag(v)
		if type(v) == "function" then local ok, r = pcall(v, info); return ok and r end
		return v
	end
	if flag(node.hidden) or flag(node.disabled) then return nil end
	return function() local ok, v = pcall(node.get, info); return ok and tonumber(v) or nil end,
		function(v) pcall(node.set, info, v) end,
		node.min, node.max, node.step, node.isPercent
end

local function Fmt(v, pct)
	if not v then return "?" end
	if pct then return string.format("%d%%", math.floor(v * 100 + 0.5)) end
	return tostring(math.floor(v + 0.5))
end

-- The line above a box after a wheel step: its name, size and opacity.
local readout
local readoutGen = 0
local function ShowReadout(mover, text)
	if not readout then
		readout = CreateFrame("Frame", nil, UIParent)
		readout:SetFrameStrata("FULLSCREEN_DIALOG")
		readout:SetFrameLevel(80)
		local bg = readout:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(SP:SPColor("windowBg", 0.94))
		SP:SPMakeBorder(readout, "accent", 1)
		readout.text = readout:CreateFontString(nil, "OVERLAY")
		readout.text:SetFontObject(SP.SPDialogFonts.text)
		readout.text:SetPoint("CENTER")
	end
	readout.text:SetText(text)
	readout:SetSize(math.ceil(readout.text:GetStringWidth()) + 20, 24)
	readout:ClearAllPoints()
	readout:SetPoint("BOTTOM", mover, "TOP", 0, 24)   -- above the box's Reset
	readout:Show()
	readoutGen = readoutGen + 1
	local gen = readoutGen
	C_Timer.After(2.5, function() if gen == readoutGen and readout then readout:Hide() end end)
end

-- Mouse wheel over a box: its size; Ctrl + wheel: its opacity. One step of its
-- settings slider at a time, within the slider's own limits.
function SP:UnlockBoxWheel(mover, delta)
	if not ACTIVE or InCombatLockdown() then return end
	local fx = FX[ModuleKeyOf(mover)]
	if not fx then return end
	-- Ctrl + wheel is its opacity or nothing: an element without one (Expiring Alerts,
	-- Ready Check) must not fall back to its size ("ctrl and opacity or size" did)
	local spec
	if IsControlKeyDown() then spec = fx.opacity else spec = fx.size end
	local get, set, lo, hi, step, pct = Access(spec)
	if get then
		local v = get()
		if v then
			step = step or (pct and 0.05 or 1)
			local nv = math.floor((v + (delta > 0 and step or -step)) / step + 0.5) * step
			if lo then nv = math.max(lo, nv) end
			if hi then nv = math.min(hi, nv) end
			if math.abs(nv - v) > 1e-6 then set(nv) end
		end
	end
	Select(mover)
	local text = mover.spLabel or ""
	local g1, _, _, _, _, p1 = Access(fx.size)
	if g1 then text = text .. "   " .. (p1 and "Scale " or "Size ") .. Fmt(g1(), p1) end
	local g2, _, _, _, _, p2 = Access(fx.opacity)
	if g2 then text = text .. "   Opacity " .. Fmt(g2(), p2) end
	ShowReadout(mover, text)
	self:RefreshUnlockBoxes()
	C_Timer.After(0, function() SP:RefreshUnlockBoxes() end)   -- again once the resized frames are laid out
end

-- Click a box: pick it (the arrow keys move it). Right-click: its settings page
-- (SP:UnlockSettingsPage: the boxes step aside until the window closes).
function SP:UnlockBoxClick(mover, button)
	if not ACTIVE or InCombatLockdown() then return end
	Select(mover)
	if button ~= "RightButton" then return end
	local fx = FX[ModuleKeyOf(mover)]
	if fx and fx.page then
		-- a page that shows one of several (Pop-Out Trackers): this box's one first
		local pick = fx.pick
		local node = pick and FindOption(pick.node, nil, "select")
		if node and type(node.set) == "function" then pcall(node.set, { pick.node, option = node }, pick.value) end
		self:UnlockSettingsPage(fx.page)
		return
	end
	if doneBar and doneBar.Refresh then doneBar:Refresh() end
end

function SP:UnlockDragStart(mover)
	if not ACTIVE or InCombatLockdown() then return false end
	Select(mover)
	local uis = UIParent:GetEffectiveScale()
	local s = mover:GetEffectiveScale() / uis
	local fx, fy = mover:GetCenter()
	local cx, cy = GetCursorPosition()
	if not fx then return false end
	mover.spDragDX, mover.spDragDY = fx * s - cx / uis, fy * s - cy / uis
	mover:SetScript("OnUpdate", DragUpdate)
	return true
end

function SP:UnlockDragStop(mover)
	if not mover:GetScript("OnUpdate") then return false end
	mover:SetScript("OnUpdate", nil)
	ShowGuides()
	return true
end

-- ---------------------------------------------------------------------------
-- The bar at the top of the screen: the keys, Snapping, the grid, the settings
-- window, Reset All Positions and Done.
-- ---------------------------------------------------------------------------
local KEYS = {
	{ "Drag", "Move it (it snaps to other boxes and the screen center while Snapping is on)" },
	{ "Click, then arrow keys", "Nudge it 1 px (Shift: 10 px). Escape lets it go" },
	{ "Mouse wheel", "Its size (its Scale, or its Icon Size)" },
	{ "Ctrl + wheel", "Its opacity" },
	{ "Right-click", "Its settings page" },
}

local function SettingsWindow() return _G["ShamanPowerConfigUIFrame"] end

-- A right-click's settings page: the boxes would sit over the window, so the mode
-- turns off while it is open and comes back as it was when the window closes.
-- What waits for the real Done (the setup tour, reopening the settings) waits on.
local backAfterSettings   -- { only, onDone, toConfig } while that window is open
local function SettingsClosed()
	local back, w = backAfterSettings, SettingsWindow()
	if not back or (w and w:IsShown()) then return end   -- (Alt+Z hides it with the rest of the UI: not a close)
	backAfterSettings = nil
	if SP.unlockOnDone == nil then SP.unlockOnDone = back.onDone end
	if ACTIVE or InCombatLockdown() then return end   -- unlocked again from the window / a fight ends the mode
	SP:SetMasterUnlock(true, back.only)
	if ACTIVE and back.toConfig then SP.unlockReturnToConfig = true end
end

local winHooked
local function HookSettingsWindow()
	local w = SettingsWindow()
	if not w or winHooked then return end
	winHooked = true
	local function refresh() if doneBar and doneBar:IsShown() and doneBar.Refresh then doneBar:Refresh() end end
	w:HookScript("OnShow", refresh)
	w:HookScript("OnHide", function() refresh(); SettingsClosed() end)
end

function SP:UnlockSettingsPage(page)
	backAfterSettings = { only = onlyKey, onDone = self.unlockOnDone, toConfig = self.unlockReturnToConfig }
	self.unlockOnDone, self.unlockReturnToConfig = nil, nil
	self:SetMasterUnlock(false)
	self:OpenConfigWindow(page)
	HookSettingsWindow()
end

local function ToggleSettings()
	local w = SettingsWindow()
	if w and w:IsShown() then
		w:Hide()
	elseif w then
		SP:ReopenSettingsWindow()   -- on the page it was left on
	else
		SP:OpenConfigWindow()
	end
	if doneBar and doneBar.Refresh then doneBar:Refresh() end
end

-- An on / off switch drawn like the settings window's toggles.
local function MakeToggle(parent, label, get, set, tip)
	local b = CreateFrame("Button", nil, parent)
	local track = b:CreateTexture(nil, "ARTWORK")
	track:SetSize(30, 14)
	track:SetPoint("LEFT", b, "LEFT", 0, 0)
	local knob = b:CreateTexture(nil, "OVERLAY")
	knob:SetSize(12, 12)
	local text = b:CreateFontString(nil, "OVERLAY")
	text:SetFontObject(SP.SPDialogFonts.text)
	text:SetPoint("LEFT", track, "RIGHT", 8, 0)
	text:SetText(label)
	b:SetSize(38 + math.ceil(text:GetStringWidth()), 22)
	function b:Refresh()
		local on = get() and true or false
		track:SetColorTexture(SP:SPColor(on and "accent" or "off"))
		knob:SetColorTexture(0.95, 0.96, 0.98)
		knob:ClearAllPoints()
		knob:SetPoint("LEFT", track, "LEFT", on and 17 or 1, 0)
	end
	b:SetScript("OnClick", function(self) set(not get()); self:Refresh() end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText(label, 1, 1, 1)
		GameTooltip:AddLine(tip, 0.8, 0.8, 0.8, true)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	b:Refresh()
	return b
end

local function EnsureDoneBar()
	if doneBar then return doneBar end
	local F = SP.SPDialogFonts
	local f = CreateFrame("Frame", "ShamanPowerUnlockBar", UIParent)
	f:SetWidth(840)
	f:SetPoint("TOP", UIParent, "TOP", 0, -70)
	f:SetFrameStrata("FULLSCREEN_DIALOG")
	f:SetFrameLevel(50)
	f:EnableMouse(true)
	-- dragged anywhere on its background, out of the way of what is being moved
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	local bg = f:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(SP:SPColor("windowBg", 0.94))
	SP:SPMakeBorder(f, "accent", 2)

	local title = f:CreateFontString(nil, "OVERLAY")
	title:SetFontObject(F.title)
	title:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -14)
	title:SetText("Unlock UI")
	local sub = f:CreateFontString(nil, "OVERLAY")
	sub:SetFontObject(F.tiny)
	sub:SetPoint("LEFT", title, "RIGHT", 12, -1)
	sub:SetText("DRAG ANY BLUE BOX  -  EACH HAS ITS OWN RESET")

	-- the keys: each key name in gold (as key names are in ShamanPower's dialogs), then what it does
	local y = -44
	for _, k in ipairs(KEYS) do
		local key = f:CreateFontString(nil, "OVERLAY")
		key:SetFontObject(F.text)
		key:SetTextColor(1, 0.82, 0)
		key:SetPoint("TOPLEFT", f, "TOPLEFT", 16, y)
		key:SetText(k[1])
		local what = f:CreateFontString(nil, "OVERLAY")
		what:SetFontObject(F.text)
		what:SetPoint("TOPLEFT", f, "TOPLEFT", 200, y)
		what:SetPoint("RIGHT", f, "RIGHT", -16, 0)
		what:SetJustifyH("LEFT")
		what:SetWordWrap(true)
		what:SetText(k[2])
		y = y - math.max(19, math.ceil(what:GetStringHeight()) + 5)
	end

	local row = CreateFrame("Frame", nil, f)
	row:SetPoint("TOPLEFT", f, "TOPLEFT", 16, y - 10)
	row:SetPoint("RIGHT", f, "RIGHT", -16, 0)
	row:SetHeight(26)
	local snap = MakeToggle(row, "Snapping", SnapOn,
		function(v) if v then SP.opt.unlockSnap = nil else SP.opt.unlockSnap = false end end,
		"While you drag, a box snaps to other boxes' edges and centers and to the screen center (within 8 px); gold lines show what it snapped to. Remembered for next time.")
	snap:SetPoint("LEFT", row, "LEFT", 0, 0)
	local grid = MakeToggle(row, "Show Grid", function() return SP.opt.unlockGrid end,
		function(v) if v then SP.opt.unlockGrid = true else SP.opt.unlockGrid = nil end; ApplyGrid() end,
		"Lines across the screen. A box dropped away from other boxes lands on them, so frames line up exactly. Remembered for next time.")
	grid:SetPoint("LEFT", snap, "RIGHT", 22, 0)
	local gridLabel = row:CreateFontString(nil, "OVERLAY")
	gridLabel:SetFontObject(F.text)
	gridLabel:SetPoint("LEFT", grid, "RIGHT", 22, 0)
	gridLabel:SetText("Grid Size")
	local function stepGrid(d)
		local g = math.min(math.max(GridSize() + d, 8), 128)
		if g == GRID_DEFAULT then SP.opt.unlockGridSize = nil else SP.opt.unlockGridSize = g end
		ApplyGrid()
	end
	local minus = SP:CreateSPButton(row, "-", 22, false)
	minus:SetPoint("LEFT", gridLabel, "RIGHT", 10, 0)
	minus:SetScript("OnClick", function() stepGrid(-4) end)
	local value = row:CreateFontString(nil, "OVERLAY")
	value:SetFontObject(F.text)
	value:SetWidth(32)
	value:SetJustifyH("CENTER")
	value:SetPoint("LEFT", minus, "RIGHT", 2, 0)
	local plus = SP:CreateSPButton(row, "+", 22, false)
	plus:SetPoint("LEFT", value, "RIGHT", 2, 0)
	plus:SetScript("OnClick", function() stepGrid(4) end)

	local done = SP:CreateSPButton(row, "Done", 84, true)
	done:SetPoint("RIGHT", row, "RIGHT", 0, 0)
	done:SetScript("OnClick", function() SP:SetMasterUnlock(false) end)
	local all = SP:CreateSPButton(row, "Reset All Positions", 150, false)
	all:SetPoint("RIGHT", done, "LEFT", -8, 0)
	all:SetScript("OnClick", ConfirmResetAll)
	local settings = SP:CreateSPButton(row, "Show Settings", 110, false)
	settings:SetPoint("RIGHT", all, "LEFT", -8, 0)
	settings:SetScript("OnClick", ToggleSettings)
	-- hooked: the button's own OnEnter/OnLeave draw its hover
	settings:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText("Settings window", 1, 1, 1)
		GameTooltip:AddLine("Shows or hides ShamanPower's settings while the boxes stay up. Right-click a box to open its own page.", 0.8, 0.8, 0.8, true)
		GameTooltip:Show()
	end)
	settings:HookScript("OnLeave", function() GameTooltip:Hide() end)

	f:SetHeight(-(y - 10) + 26 + 16)
	function f:Refresh()
		snap:Refresh()
		grid:Refresh()
		value:SetText(GridSize())
		HookSettingsWindow()
		local w = SettingsWindow()
		settings:SetLabel((w and w:IsShown()) and "Hide Settings" or "Show Settings")
	end
	-- hidden before the OnHide below exists: this runs with the mode already
	-- on, so that handler would end the mode the moment the bar is made
	f:Hide()
	-- Escape closes it and ends the mode as Done does: a frame later, or the
	-- settings window Done brings back would be shut by the same Escape. (With a
	-- box picked, Escape only lets the box go: the arrow keys' frame takes it.)
	tinsert(UISpecialFrames, "ShamanPowerUnlockBar")
	f:SetScript("OnHide", function(self)
		if ACTIVE and not self:IsShown() then   -- not a hidden UI (Alt+Z)
			C_Timer.After(0, function() if ACTIVE then SP:SetMasterUnlock(false) end end)
		end
	end)
	doneBar = f
	return f
end

function SP:ResetAllUnlockPositions()
	if InCombatLockdown() then return end
	for _, e in pairs(shown) do
		if e.reset then pcall(e.reset) end
	end
	self:RefreshUnlockBoxes()
	C_Timer.After(0, function() SP:RefreshUnlockBoxes() end)   -- again once the moved frames are laid out
	print("|cff0070ddShamanPower|r: positions reset. Elements without a Reset button stay where they are.")
end

-- ---------------------------------------------------------------------------
-- On / off
-- ---------------------------------------------------------------------------
function SP:IsMasterUnlocked() return ACTIVE end

-- `only`: unlock just one module's frames (its key in MODULES) and nothing
-- else - the settings pages use it for "move these" buttons. The settings
-- window that asked comes back when Done is pressed.
function SP:SetMasterUnlock(on, only)
	on = on and true or false
	if on == ACTIVE then return end
	if on and InCombatLockdown() then
		print("|cff0070ddShamanPower|r: |cffe64a4athe UI cannot be unlocked in combat.|r")
		return
	end

	if not on then
		ACTIVE = false
		Select(nil)
		ShowGuides()
		if readout then readout:Hide() end
		for _, m in pairs(self.barMovers or {}) do m:EnableMouseWheel(false); m:SetScript("OnUpdate", nil) end
		for moverKey, e in pairs(shown) do
			if e.bar then
				if moverKey == "totembar" then self:SetTotemBarUnlocked(false) else self:SetCooldownBarUnlocked(false) end
			else
				self:HideBarMover(moverKey)
			end
			local mover = self.barMovers and self.barMovers[moverKey]
			if mover and mover.spReset then mover.spReset:Hide() end
		end
		wipe(shown)
		-- sample content off first, so each module decides for itself what shows now;
		-- then anything that was hidden before we started goes back to hidden
		for key in pairs(demos) do
			local def = self.PreviewRegistry and self.PreviewRegistry[key]
			local demo = def and DemoMethod(def)
			if demo then pcall(demo, self, false) end
		end
		wipe(demos)
		self.unlockDemoAll = nil
		for frame in pairs(forced) do
			if frame:IsShown() then pcall(frame.Hide, frame) end
		end
		wipe(forced)
		if doneBar then doneBar:Hide() end
		if gridFrame then gridFrame:Hide() end
		self:HideSPDialog("unlock_reset_all")   -- its question is about the boxes just put away
		-- whoever opened the unlock (the setup tour) gets control back
		if self.unlockOnDone then
			local fn = self.unlockOnDone
			self.unlockOnDone = nil
			pcall(fn)
		end
		if self.unlockReturnToConfig then
			self.unlockReturnToConfig = nil
			self:ReopenSettingsWindow()
		end
		-- a page opened meanwhile (right-click on a box) mounts its preview now
		local api = rawget(_G, "ShamanPowerConfig")
		if api and api.UpdatePreviewPane then pcall(api.UpdatePreviewPane, api, true) end
		return
	end

	ACTIVE = true
	onlyKey = only
	self.unlockDemoAll = true   -- demos fill every frame they own, not just the one the wizard borrows
	-- our own windows would sit on top of what is being moved
	local cfg = _G["ShamanPowerConfigUIFrame"]
	if cfg and cfg:IsShown() then cfg:Hide(); self.unlockReturnToConfig = true end
	if ShamanPowerAssign and ShamanPowerAssign.Hide then pcall(ShamanPowerAssign.Hide, ShamanPowerAssign) end

	local isShaman = select(2, UnitClass("player")) == "SHAMAN"
	if only then isShaman = false end   -- one module only: the bars stay locked
	if isShaman and self.TotemBarEnabled and self:TotemBarEnabled() and self.SetTotemBarUnlocked then
		self:SetTotemBarUnlocked(true)
		shown.totembar = { bar = true, reset = ResetTotemBar }
		AddReset("totembar", ResetTotemBar)
		ArmMover("totembar")
	end
	if isShaman and self.cooldownBar and self.opt.showCooldownBar and self.SetCooldownBarUnlocked then
		self:SetCooldownBarUnlocked(true)
		shown.cooldownbar = { bar = true, reset = ResetCooldownBar }
		AddReset("cooldownbar", ResetCooldownBar)
		ArmMover("cooldownbar")
	end

	for _, m in ipairs(MODULES) do
		local def = self.PreviewRegistry and self.PreviewRegistry[m.key]   -- nil when the module is not loaded
		local wanted = def ~= nil and (only == nil or only == m.key)
		if wanted and m.enabled then
			local ok, res = pcall(m.enabled)
			wanted = ok and res and true or false
		end
		if wanted then
			local demo = DemoMethod(def)
			if demo then
				local ok, err = pcall(demo, self, true)
				if ok then demos[m.key] = true else print("|cff0070ddShamanPower|r: |cffe64a4acould not preview " .. m.label .. ": " .. tostring(err) .. "|r") end
			end
			local frames
			if m.frames then
				local ok, res = pcall(m.frames)
				frames = ok and res or {}
			else
				frames = ResolveFrames(def)
			end
			local resetFn
			if type(m.reset) == "function" then resetFn = m.reset
			elseif type(m.reset) == "string" and self[m.reset] then
				local name = m.reset
				resetFn = function() SP[name](SP) end
			end
			for i, frame in ipairs(frames) do
				local label = frame.spMoverLabel or (m.labels and m.labels[i]) or (#frames > 1 and (m.label .. " " .. i) or m.label)
				ShowBox("unlock_" .. m.key .. "_" .. i, frame, label, m.save or SaveThroughOwnScripts, resetFn)
			end
		end
	end

	EnsureDoneBar():Show()
	ApplyGrid()
end

function SP:ToggleMasterUnlock() self:SetMasterUnlock(not ACTIVE) end

-- Unlock one module's frames only (a "move these" button on its settings page).
function SP:UnlockModuleFrames(key)
	if ACTIVE then self:SetMasterUnlock(false) end
	self:SetMasterUnlock(true, key)
end

-- a fight ends the mode: protected frames cannot be moved, and the sample content should not sit over combat
do
	local f = CreateFrame("Frame")
	local resume   -- the setup tour's "bring me back", held until the fight is over
	f:RegisterEvent("PLAYER_REGEN_DISABLED")
	f:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_REGEN_ENABLED" then
			f:UnregisterEvent("PLAYER_REGEN_ENABLED")
			local fn = resume
			resume = nil
			if fn then pcall(fn) end
			return
		end
		if ACTIVE then
			-- no settings window or setup tour popping up as the fight starts
			SP.unlockReturnToConfig = nil
			if SP.unlockOnDone then
				resume, SP.unlockOnDone = SP.unlockOnDone, nil
				f:RegisterEvent("PLAYER_REGEN_ENABLED")
			end
			SP:SetMasterUnlock(false)
			print("|cff0070ddShamanPower|r: UI locked again (combat). Positions you had already moved are saved."
				.. (resume and " The setup tour comes back when the fight ends." or ""))
		end
	end)
end

SLASH_SPUNLOCK1 = "/spunlock"
SlashCmdList["SPUNLOCK"] = function() SP:ToggleMasterUnlock() end

-- General > Main: the button
do
	local settings = SP.options and SP.options.args and SP.options.args.settings
	local main = settings and settings.args and settings.args.settings_show
	if main and main.args then
		main.args.master_unlock = {
			order = 0.2,
			type = "execute",
			name = "Unlock UI (move everything)",
			desc = "Shows every ShamanPower element at once - both bars and each enabled module, with sample content - under a blue box you can drag. Every box has its own Reset, and the bar at the top has Reset All Positions and Done. Out of combat only; a fight locks everything again. Each module's own lock setting is left as it is. Also: /spunlock",
			func = function() ShamanPower:SetMasterUnlock(true) end,
		}
	end
end

-- ---------------------------------------------------------------------------
-- Page actions that show live frames ("Test All Frames", "Show All (Position)")
-- would otherwise play behind the settings window, or not at all while the
-- preview pane's demo owns the frames. Hide the window (which releases the
-- pane's mocks) for the length of the action and bring it back after: a timed
-- action passes its seconds; a mode that ends through another button (Hide
-- All, Done) passes nil and may supply a cleanup method as the third argument.
-- ---------------------------------------------------------------------------
local settingsTestGeneration = 0
local settingsTestCleanup, settingsTestDoneBar

local function FinishSettingsTestClick()
	SP:SettingsTestDone()
end

-- Escape closes the bar, which ends the session as Done does: a frame later,
-- or the settings window Done brings back would be shut by the same Escape.
-- In a fight too: the sample frames are plain frames, and Done already leaves
-- the settings window shut in combat.
local function FinishAfterEscape(generation)
	if generation ~= settingsTestGeneration then return end   -- Done, or a new session, meanwhile
	SP:SettingsTestDone()
end

local function ShowSettingsTestDone()
	if not settingsTestDoneBar then
		local f = CreateFrame("Frame", "ShamanPowerSettingsTestBar", UIParent)
		f:SetSize(380, 42)
		f:SetPoint("TOP", UIParent, "TOP", 0, -70)
		f:SetFrameStrata("FULLSCREEN_DIALOG")
		f:EnableMouse(true)
		local bg = f:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints(); bg:SetColorTexture(SP:SPColor("windowBg", 0.94))
		SP:SPMakeBorder(f, "accent", 2)
		local done = SP:CreateSPButton(f, "Done", 84, true)
		done:SetPoint("RIGHT", -14, 0)
		done:SetScript("OnClick", FinishSettingsTestClick)
		local text = f:CreateFontString(nil, "OVERLAY")
		text:SetFontObject(SP.SPDialogFonts.text)
		text:SetPoint("LEFT", 14, 0)
		text:SetWidth(f:GetWidth() - 14 - 14 - done:GetWidth() - 12)
		text:SetJustifyH("LEFT"); text:SetWordWrap(true)
		text:SetText("Finish previewing or positioning:")
		f:SetHeight(math.max(42, math.ceil(text:GetStringHeight()) + 20))
		tinsert(UISpecialFrames, "ShamanPowerSettingsTestBar")
		f:SetScript("OnHide", function(self)
			-- our own Hide (Done, a new session) has already ended the session
			if self:IsShown() or not (settingsTestCleanup or SP.settingsTestReturn) then return end
			local generation = settingsTestGeneration
			C_Timer.After(0, function() FinishAfterEscape(generation) end)
		end)
		settingsTestDoneBar = f
	end
	settingsTestDoneBar:Show()
end

function ShamanPower:RunWithSettingsHidden(seconds, fn, cleanup)
	-- Replacing a session must stop its sample without reopening the window.
	-- Clear the return flag before cleanup: an existing Hide bridge may call Done.
	local restore = self.settingsTestReturn
	self.settingsTestReturn = nil
	settingsTestGeneration = settingsTestGeneration + 1
	local previous = settingsTestCleanup
	settingsTestCleanup = nil
	if settingsTestDoneBar then settingsTestDoneBar:Hide() end
	if previous then pcall(previous, self) end
	settingsTestGeneration = settingsTestGeneration + 1
	local generation = settingsTestGeneration
	self.settingsTestReturn = restore
	local cfg = _G["ShamanPowerConfigUIFrame"]
	if cfg and cfg:IsShown() then
		local api = rawget(_G, "ShamanPowerConfig")
		if api and api.ReleasePreview then pcall(api.ReleasePreview, api) end
		cfg:Hide()
		self.settingsTestReturn = true
	end
	settingsTestCleanup = cleanup
	if fn then
		local ok, err = pcall(fn, self)
		if not ok then self:SettingsTestDone(); error(err, 0) end
	end
	if generation ~= settingsTestGeneration then return end
	if seconds then
		C_Timer.After(seconds, function()
			if generation == settingsTestGeneration then ShamanPower:SettingsTestDone() end
		end)
	else
		ShowSettingsTestDone()
	end
end

function ShamanPower:SettingsTestDone()
	local restore, cleanup = self.settingsTestReturn, settingsTestCleanup
	self.settingsTestReturn = nil
	settingsTestCleanup = nil
	settingsTestGeneration = settingsTestGeneration + 1
	if settingsTestDoneBar then settingsTestDoneBar:Hide() end
	if cleanup then pcall(cleanup, self) end
	if not restore then return end
	if InCombatLockdown() then return end   -- the window is not for combat; the user reopens it
	self:ReopenSettingsWindow()
end

-- Bring back the settings window a mode hid (Unlock UI, keybind mode, a page's
-- test action) on the page, tab and scroll it was hidden on. Open() would pick
-- the page afresh: its first tab, scrolled to the top. The hidden window still
-- holds all of that, so show it and redraw its page in place (the preview pane
-- gave its frame back when the window hid, so that is mounted again too).
function ShamanPower:ReopenSettingsWindow()
	local api = rawget(_G, "ShamanPowerConfig")
	if not api then return end
	local win = _G["ShamanPowerConfigUIFrame"]
	if win and win:IsShown() then win:Raise() return end   -- reopened meanwhile: leave it as it is
	if win and api.RefreshCurrent then
		win:Show()
		win:Raise()
		pcall(api.RefreshCurrent, api)
		if api.UpdatePreviewPane then pcall(api.UpdatePreviewPane, api) end
		return
	end
	if api.Open then pcall(api.Open, api) end
end
