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
--
-- Motion (D31): Unlock UI opens with the logo building up at the screen center
-- and docking into the bar while the boxes rise in; a right-click (or the bar's
-- Settings) drops everything away for the settings window and brings it all
-- back up after; Done lets the boxes go like totems being removed. Only Unlock
-- UI's own frames move, never the real ones under the boxes. No sound.

local SP = ShamanPower
if not SP then return end

local ACTIVE = false
local onlyKey           -- the one module unlocked by itself (a "move these" button), else nil
local shown = {}        -- mover keys that are up
local demos = {}        -- registry keys whose Demo(true) was called
local forced = {}       -- frames that were hidden before we showed them
local doneBar
-- (further down: the mode's off switch, the trip to the settings, the position readout)
local TurnOff, OffRest, StepAside, ShowCoords, DragCoords, FightStopsTrip
-- Words use ShamanPower's dialog fonts (ShamanPowerDialog.lua): the brand's Fira Sans,
-- or the game's font where Fira is missing or cannot show the language.

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
		b:HookScript("OnEnter", function(self)
			local tip = SP.Tooltip or GameTooltip   -- (ShamanPower's own tooltip, D34)
			tip:SetOwner(self, "ANCHOR_CURSOR")
			tip:SetText("Put this one back where it starts")
			tip:Show()
		end)
		b:HookScript("OnLeave", function() (SP.Tooltip or GameTooltip):Hide() end)
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
	DragCoords(self)
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
	ShowCoords(selected, false, d[1] * step, d[2] * step)   -- (the box itself follows a frame later)
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
	-- Ready Reminders (D40): every icon has its own Icon Size and Opacity (ReadyReminderBoxAccess)
	readyreminders = { page = { "fluffy", "readyreminders_section" }, size = { rr = "size" }, opacity = { rr = "opacity" } },
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
	readyflash     = { page = { "fluffy", "readyreminders_section" }, size = { rr = "flashSize" } },
	readyflashspell = { page = { "fluffy", "readyreminders_section" }, size = { rr = "flashSize" } },
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
local accessMover   -- the box the wheel is over (a Ready Reminders spec reads its own icon)
local function Access(spec)
	if not spec then return nil end
	if spec.get then return spec.get, spec.set, spec.min, spec.max, spec.step, spec.pct end
	if spec.rr then
		local e = accessMover and shown[accessMover.key]
		local fr = e and e.frame
		if not (fr and SP.ReadyReminderBoxAccess) then return nil end
		return SP:ReadyReminderBoxAccess(spec.rr, fr)
	end
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

-- The line above a box: its name with its size and opacity after a wheel step,
-- or its position (x / y) while it is picked, dragged or nudged. It goes 2.5 s
-- after the last change (one timer out at a time, no closure per step).
local readout
-- hold: kept while dragging; at: when it goes; wait: a timer is out; box, x, y:
-- the box whose position it shows, and the numbers shown
local RO = { hold = false, at = 0, wait = false }

local function ReadoutTimeout()
	RO.wait = false
	if RO.hold or not (readout and readout:IsShown()) then return end
	local left = RO.at - GetTime()
	if left > 0.05 then
		RO.wait = true
		C_Timer.After(left, ReadoutTimeout)
		return
	end
	readout:Hide()
	RO.box = nil
end

local function ReadoutRelease()
	RO.hold = false
	RO.at = GetTime() + 2.5
	if not RO.wait then
		RO.wait = true
		C_Timer.After(2.5, ReadoutTimeout)
	end
end

local function ShowReadout(mover, text, hold)
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
	RO.box = nil
	if hold then RO.hold = true else ReadoutRelease() end
end

-- A box's center as an offset from the screen center, in UIParent units (rounded).
-- A box hangs on one CENTER point off UIParent's bottom left (ShowBarMover, the
-- drag): read from that point it is exact even straight after a SetPoint.
local function BoxXY(m)
	local s = m:GetEffectiveScale() / UIParent:GetEffectiveScale()
	local p, rel, rp, x, y = m:GetPoint(1)
	if not (p == "CENTER" and rp == "BOTTOMLEFT" and rel == UIParent and x) then
		x, y = m:GetCenter()
		if not x then return nil end
	end
	local w, h = UIParent:GetSize()
	return math.floor(x * s - w / 2 + 0.5), math.floor(y * s - h / 2 + 0.5)
end

local function CoordsText(m, x, y)
	RO.x, RO.y = x, y
	readout.text:SetText(string.format("%s   x %d   y %d", m.spLabel or "", x, y))
	readout:SetWidth(math.ceil(readout.text:GetStringWidth()) + 20)
end

-- Picked, or nudged (dx, dy: the step the box itself shows a frame later), or
-- dragged (hold: it stays until the drop).
ShowCoords = function(m, hold, dx, dy)
	local x, y = BoxXY(m)
	if not x then return end
	ShowReadout(m, "", hold)
	RO.box = m
	CoordsText(m, x + (dx or 0), y + (dy or 0))
end

-- Every drag frame: new text only when the numbers change.
DragCoords = function(m)
	if RO.box ~= m then return end
	local x, y = BoxXY(m)
	if x and (x ~= RO.x or y ~= RO.y) then CoordsText(m, x, y) end
end

-- ---------------------------------------------------------------------------
-- Motion (D31, decided 2026-09-30): the numbers. Seconds and UIParent units, plain
-- math with no frames, so it can be checked outside the game. Rising things use
-- the logo's back-ease (ShamanPowerBrand.lua), falling things speed up (gravity).
-- ---------------------------------------------------------------------------
local MO = {
	OUT = 0.15,          -- the settings window rises off the top first (its own motion)
	DOCK = 0.24,         -- the finished logo shrinks into the bar: 1.81 -> 2.05
	RIPPLE_AT = 0.09,    -- the boxes start rising 0.09 s after the build (1.90) ...
	RIPPLE = 0.30,       -- ... the farthest 0.30 s after the nearest: the ripple ends at 2.50
	BOX_RISE = 0.30, BOX_LIFT = 8, ALPHA_K = 1.6,   -- a box: the kit's own rise (opaque at 62% of it)
	BAR_AT = 0.29, BAR_FADE = 0.35,                 -- the bar fades in around the logo: 2.10 -> 2.45
	DROP = 0.25, DROP_STEP = 0.02,                  -- right-click: everything drops away ...
	RISE = 0.30, RISE_STEP = 0.02,                  -- ... and rises back up after the settings
	SPAN = 0.16,         -- (mine) many boxes tighten those steps: a move stays about 0.4 s
	HIT_AT = 0.62, HIT = 0.15,                      -- the landing pulse (the approved clip's jolt)
	SINK = 0.25, SINK_STEP = 0.05, SINK_BY = 14,    -- Done: the boxes go like totems being removed
	SINK_SPAN = 0.25,    -- (mine) the same for the sink
	UP = 0.20,           -- Done: the bar goes up off the top
	-- Tuck Away: the bar closes in from both sides (C, ease-in-out) and rises into its tab
	-- (R, ease-in); back out it drops from the tab (D, back-ease) and opens out (O, ease-out).
	-- Its own contents fade out / in over FADE; WAIT: after the mouse leaves it (D, O: mine)
	TUCK_C = 0.20, TUCK_R = 0.14, TUCK_D = 0.16, TUCK_O = 0.20, TUCK_FADE = 0.05, TUCK_WAIT = 0.6,
	MARGIN = 30,         -- (mine) how far past the screen's edge a piece goes (a Reset chip included)
}
do
	-- the logo's own easing (ShamanPowerBrand.lua; the same formulas when that file is missing)
	local EaseBack = SP.BrandEaseBack or function(x, s) x = x - 1; return 1 + (s + 1) * x ^ 3 + s * x ^ 2 end
	local EaseOut = SP.BrandEaseOut or function(x) return 1 - (1 - x) ^ 3 end
	local function Clamp01(x)
		if x < 0 then return 0 elseif x > 1 then return 1 end
		return x
	end
	local function EaseIn(x) return x * x end   -- gravity: slow, then fast
	MO.Clamp01 = Clamp01

	-- The step between staggered pieces: `step`, tightened so all n start within `span`.
	function MO.Step(n, step, span)
		if n < 2 then return 0 end
		return math.min(step, span / (n - 1))
	end

	-- The opening's ripple: a box's delay grows with its distance from the screen
	-- center, the nearest at 0 and the farthest at RIPPLE (dist, out: 1 .. n).
	function MO.Ripple(dist, n, out)
		local lo, hi = math.huge, -math.huge
		for i = 1, n do
			if dist[i] < lo then lo = dist[i] end
			if dist[i] > hi then hi = dist[i] end
		end
		for i = 1, n do
			if hi > lo then out[i] = (dist[i] - lo) / (hi - lo) * MO.RIPPLE else out[i] = 0 end
		end
	end

	-- The opening: a box `tl` seconds into its rise -> alpha, y offset.
	function MO.RiseIn(tl)
		local p = Clamp01(tl / MO.BOX_RISE)
		if p <= 0 then return 0, -MO.BOX_LIFT end
		return math.min(1, p * MO.ALPHA_K), -(1 - EaseBack(p, 1.6)) * MO.BOX_LIFT
	end

	-- Rising back up from `from` (below the screen: negative) -> y offset.
	function MO.RiseBack(tl, from) return (1 - EaseBack(Clamp01(tl / MO.RISE), 1.6)) * from end

	-- Dropping away to `to` (below the screen: negative) -> y offset.
	function MO.Drop(tl, to) return EaseIn(Clamp01(tl / MO.DROP)) * to end

	-- Done: a box sinking away -> alpha, y offset.
	function MO.Sink(tl)
		local p = Clamp01(tl / MO.SINK)
		return 1 - p, -EaseIn(p) * MO.SINK_BY
	end

	-- Going up off the top to `to` (positive) in `dur` -> y offset.
	function MO.Up(tl, dur, to) return EaseIn(Clamp01(tl / dur)) * to end

	-- The landing pulse, for a move of `dur`: its strength (0 = none).
	function MO.Hit(tl, dur)
		local p = (tl - MO.HIT_AT * dur) / MO.HIT
		if p < 0 or p > 1 then return 0 end
		return (1 - p) ^ 1.5
	end

	-- The opening: the logo's trip into the bar (0 -> 1) and the bar's fade (alpha).
	function MO.Dock(t) return EaseOut(Clamp01(t / MO.DOCK)) end
	function MO.BarFade(t) return Clamp01((t - MO.BAR_AT) / MO.BAR_FADE) end

	-- Tuck Away: a segment of the plate's move, `p` of its time -> 0 .. 1 of its way (the
	-- drop's back-ease overshoots a hair). C: the kit's ease_in_out; R: going home, ease-in.
	MO.TUCK_TIME = { C = MO.TUCK_C, R = MO.TUCK_R, D = MO.TUCK_D, O = MO.TUCK_O }
	function MO.TuckEase(kind, p)
		if kind == "C" then
			if p < 0.5 then return 4 * p ^ 3 end
			return 1 - (-2 * p + 2) ^ 3 / 2
		end
		if kind == "R" then return EaseIn(p) end
		if kind == "D" then return EaseBack(p, 1.6) end
		return EaseOut(p)
	end
end

-- ---------------------------------------------------------------------------
-- Motion: the frames. Only Unlock UI's own move: the boxes (their Reset chips ride
-- on them), the bar with its logo, the tab, and the grid's fade. The real frames
-- under the boxes never do, so no position is ever saved from a move. One driver,
-- shown only while something moves (the logo build runs itself); a click, Escape
-- or a fight finishes a move at once. No sound.
-- ---------------------------------------------------------------------------
local BAR = { DOCK_H = 22, DOCK_X = 12, DOCK_Y = -8,    -- the docked logo, centered on the one-line bar (D36b A)
	TAB_W = 34, TAB_H = 20, TAB_LOGO = 16,               -- (mine) the tab: the mock's 30 x 18 plate, logo at 78%
	BIG = 646 / 1080 }                                   -- the logo's height on the intro's 1080-tall canvas
BAR.DOCK_W = BAR.DOCK_H * 614 / 646                      -- the logo build's own proportions
BAR.DOCK_CX, BAR.DOCK_CY = BAR.DOCK_X + BAR.DOCK_W / 2, BAR.DOCK_Y - BAR.DOCK_H / 2
-- The bar's own spot (p, rel, rp, x, y: read while it sits there), how far above it
-- it is now (off: tucked or moving), the tab it leaves at the top edge (tab, tabX), and
-- the frame (GetTime) the settings window's close brought it back in (backAt).
local BS = { off = 0, tabX = 0, backAt = -1 }
local scene                    -- the move running now: "open", "rise", "drop", "done" or "tuck"
local FinishScene, StartOpening, StartRise, StartDrop, StartDone   -- (the moves: below)
local BarHover, TuckArm, StartTuckSlide, ShowTab, BarPlace, DockLogo

local function TuckOn() return SP.opt and SP.opt.unlockTuck and true or false end

-- General > Main > UI Animations (ShamanPowerBrand.lua). Off: every move of Unlock UI lands in
-- its end state at once. (A brand file without the switch: on.)
local function Animated()
	if type(SP.UIAnimationsOn) ~= "function" then return true end
	return SP:UIAnimationsOn() ~= false
end

local function MouseOnBar()
	if doneBar and doneBar:IsVisible() and doneBar:IsMouseOver() then return true end
	local tab = BS.tab
	return tab and tab:IsVisible() and tab:IsMouseOver() and true or false
end

-- The settings window's own motion (ShamanPower_Config/Window.lua). Missing (an
-- older settings module): false, and the caller shows or hides it at once.
local function SettingsMotion(name, arg)
	local api = rawget(_G, "ShamanPowerConfig")
	local fn = api and api[name]
	if type(fn) ~= "function" then return false end
	return (pcall(fn, api, arg))
end

-- The settings window counts as open unless it is on its way out (shooting up off
-- the top: ShamanPowerConfig:IsLeaving(); an older settings module: shown = open).
local function SettingsOpen(w)
	if not (w and w:IsShown()) then return false end
	local api = rawget(_G, "ShamanPowerConfig")
	if api and type(api.IsLeaving) == "function" then
		local ok, leaving = pcall(api.IsLeaving, api)
		if ok and leaving then return false end
	end
	return true
end

-- The settings window has left at the opening's start (MotionOut's onDone). When a
-- click, Escape or a fight cut that short (its second argument), the opening finishes
-- at once as well. (An older settings module calls it with no arguments.)
local function SettingsLeft(_, skipped)
	if skipped and scene == "open" then FinishScene("skip") end
end

-- The four elements along a bar's top edge (none without the brand kit).
local function TopStripe(f)
	if not SP.CreateElementStripe then return end
	local stripe = SP:CreateElementStripe(f)
	stripe:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	stripe:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
end

do
	local driver = CreateFrame("Frame", nil, UIParent)
	driver:Hide()
	local Clamp01 = MO.Clamp01
	-- The pieces of the move running now, by index (tables made once, then reused):
	-- of: frame -> index; order: the boxes nearest the screen center first, then the
	-- bar; t, stop: the move's clock and its end.
	local PC = { n = 0, t = 0, stop = 0, frame = {}, kind = {}, pt = {}, rel = {}, rpt = {}, x = {}, y = {},
		delay = {}, dist = {}, key = {}, off = {}, lit = {}, of = {}, order = {} }
	-- The opening: phase 1 the settings window leaving, 2 the logo build, 3 the rest;
	-- x0, y0: where the logo starts its trip (the screen center), from the bar's top
	-- left; reveal: how far the bar has faded in. page, rr: where a drop goes.
	local OP = { phase = 0, buildAt = 0, big = 0, docked = false, x0 = 0, y0 = 0, reveal = -1 }
	-- Tuck Away. hover: the mouse on the bar, its controls or the tab; at / wait: the wait after
	-- it leaves. goal ("up" / "down"): where the slide running goes. The moving is done by a
	-- plate in the bar's look (plate) while the bar itself stays as it is, hidden, so nothing in
	-- it is ever squeezed. seg / seg2: the plate's segments (C close in, R rise into the tab,
	-- D drop out of it, O open out); segStart / segD their clock; w0 h0 top0: where the segment
	-- began; w h top: the plate now (top: below the screen's top edge); cx W H B: the bar's own
	-- center, size and top; alpha (a0 at the segment's start): how much of the bar shows.
	local TK = { hover = false, at = 0, wait = false, w = 0, h = 0, top = 0, cx = 0, W = 0, H = 0, B = 0,
		alpha = 1, a0 = 1, segStart = 0, segD = 1, w0 = 0, h0 = 0, top0 = 0 }

	local function ReadHome(i)
		PC.pt[i], PC.rel[i], PC.rpt[i], PC.x[i], PC.y[i] = PC.frame[i]:GetPoint(1)
	end

	local function AddPiece(frame, kind)
		local i = PC.n + 1
		PC.n = i
		PC.frame[i], PC.kind[i] = frame, kind
		PC.delay[i], PC.dist[i], PC.key[i], PC.off[i], PC.lit[i] = 0, 0, 0, 0, false
		if kind == "box" then ReadHome(i) end
		PC.of[frame] = i
		return i
	end

	BarPlace = function(off)
		if not doneBar then return end
		if BS.off == 0 then BS.p, BS.rel, BS.rp, BS.x, BS.y = doneBar:GetPoint(1) end
		BS.off = off
		if off ~= 0 then doneBar:SetClampedToScreen(false) end   -- (clamped, it could never leave the screen)
		doneBar:ClearAllPoints()
		doneBar:SetPoint(BS.p, BS.rel, BS.rp, BS.x, BS.y + off)
	end

	local function TabPlace(off)
		BS.tab:ClearAllPoints()
		BS.tab:SetPoint("TOP", UIParent, "TOP", BS.tabX, off)
	end

	-- Tuck Away: the small logo tab at the top edge, centered where the bar is.
	ShowTab = function(alpha)
		local tab = BS.tab
		if not tab then
			tab = CreateFrame("Frame", nil, UIParent)
			tab:SetSize(BAR.TAB_W, BAR.TAB_H)
			tab:SetFrameStrata("FULLSCREEN_DIALOG")
			tab:SetFrameLevel(60)
			tab:EnableMouse(true)
			local bg = tab:CreateTexture(nil, "BACKGROUND")
			bg:SetAllPoints()
			bg:SetColorTexture(SP:SPColor("windowBg", 0.94))
			SP:SPMakeBorder(tab, "accent", 1)
			if SP.CreateTotemGraphic then   -- (without the brand kit: a plain tab)
				local g = SP:CreateTotemGraphic(tab, { noOverlap = true })   -- (it fades in as the bar arrives)
				g:SetGraphicHeight(BAR.TAB_LOGO)
				g:SetPoint("CENTER", tab, "CENTER", 0, 0)
			end
			tab:SetScript("OnEnter", function() BarHover(true, true) end)
			tab:SetScript("OnLeave", function() BarHover(false) end)
			BS.tab = tab
		end
		if BS.off == 0 and doneBar then
			local l, r = doneBar:GetLeft(), doneBar:GetRight()
			if l then BS.tabX = (l + r) / 2 - UIParent:GetWidth() / 2 end
		end
		TabPlace(0)
		tab:SetAlpha(alpha or 1)
		tab:Show()
	end

	-- How far up the bar goes to be out of sight.
	local function TuckedOff()
		local h, b = UIParent:GetHeight(), doneBar:GetBottom()
		if not b then return h end
		return h - (b - BS.off) + 4
	end

	-- The plate that does the tucking: the bar's fill, its soft edge and the four elements on top
	-- (under the bar, so the bar's own contents fade out over it; under the tab).
	local function EnsurePlate()
		if TK.plate then return end
		local p = CreateFrame("Frame", nil, UIParent)
		p:SetFrameStrata("FULLSCREEN_DIALOG")
		p:SetFrameLevel(49)
		local bg = p:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(SP:SPColor("windowBg", 0.94))
		SP:SPMakeBorder(p, "border", 1.5)
		TopStripe(p)
		p:Hide()
		TK.plate = p
	end

	-- the bar's own place and size, read while it sits on its spot (the tab goes over its center)
	local function TuckMeasure()
		local l, r, t, b = doneBar:GetLeft(), doneBar:GetRight(), doneBar:GetTop(), doneBar:GetBottom()
		if not (l and t) then return false end
		TK.cx, TK.W, TK.H, TK.B = (l + r) / 2, r - l, t - b, t - UIParent:GetHeight()
		BS.tabX = TK.cx - UIParent:GetWidth() / 2
		return true
	end

	local function PlacePlate()
		local p = TK.plate
		p:ClearAllPoints()
		p:SetPoint("TOP", UIParent, "TOPLEFT", TK.cx, TK.top)
		p:SetSize(TK.w, TK.h)
	end

	-- where a segment takes the plate: width, height, top
	local function SegTarget(kind)
		if kind == "C" or kind == "D" then return BAR.TAB_W, TK.H, TK.B end
		if kind == "R" then return BAR.TAB_W, BAR.TAB_H, 0 end
		return TK.W, TK.H, TK.B   -- O
	end

	-- a segment starts where the plate is now; turned around halfway, it has less way to go and
	-- takes that much less time
	local function SegBegin(kind, at)
		TK.seg, TK.segStart = kind, at
		TK.w0, TK.h0, TK.top0, TK.a0 = TK.w, TK.h, TK.top, TK.alpha
		local w1, h1 = SegTarget(kind)
		local left
		if kind == "C" or kind == "O" then
			left = math.abs(w1 - TK.w) / math.max(1, TK.W - BAR.TAB_W)
		else
			left = math.abs(h1 - TK.h) / math.max(1, TK.H - BAR.TAB_H)
		end
		TK.segD = math.max(0.03, MO.TUCK_TIME[kind] * math.min(1, left))
	end

	-- how much of the bar itself shows (0: hidden, its controls take no mouse); it waits off screen
	-- while tucked and comes back to its spot as it shows again
	local function BarContents(a)
		if a > 0 and BS.off ~= 0 then BarPlace(0) end
		TK.alpha = a
		doneBar:SetAlpha(a)
		doneBar.body:SetShown(a > 0)
		doneBar:EnableMouse(a > 0)
		if a <= 0 then   -- (a control's tooltip goes with it, e.g. the switch that started the tuck)
			local tip = SP.Tooltip or GameTooltip
			local owner = tip:IsShown() and tip:GetOwner()
			if owner and not owner:IsVisible() then tip:Hide() end
		end
	end

	-- the two places a slide ends: tucked (the tab), or down (the bar on its spot)
	local function TuckedState()
		TK.w, TK.h, TK.top, TK.alpha = BAR.TAB_W, BAR.TAB_H, 0, 0
		if BS.off == 0 then BarPlace(TuckedOff()) end   -- (the bar waits off screen, whole)
		doneBar:SetAlpha(1)
		doneBar.body:Show()
		doneBar:EnableMouse(true)
		doneBar:SetClampedToScreen(false)
		if TK.plate then TK.plate:Hide() end
		ShowTab(1)
	end
	local function DownState()
		TK.w, TK.h, TK.top, TK.alpha = TK.W, TK.H, TK.B, 1
		BarPlace(0)
		doneBar:SetAlpha(1)
		doneBar.body:Show()
		doneBar:EnableMouse(true)
		doneBar:SetClampedToScreen(true)
		if TK.plate then TK.plate:Hide() end
		-- the tab stays, unseen: pointing at its spot counts as pointing at the bar (no twitch)
		if BS.tab then BS.tab:SetAlpha(0) end
	end

	local function PlacePiece(i, dy)
		PC.off[i] = dy
		local k = PC.kind[i]
		if k == "bar" then
			BarPlace(dy)
		elseif k == "tab" then
			TabPlace(dy)
		else
			local f = PC.frame[i]
			f:ClearAllPoints()
			f:SetPoint(PC.pt[i], PC.rel[i], PC.rpt[i], PC.x[i], PC.y[i] + dy)
		end
	end

	local function CenterDist(f, w, h)
		local x, y = f:GetCenter()
		if not x then return 0 end
		return math.sqrt((x - w / 2) ^ 2 + (y - h / 2) ^ 2)
	end

	-- How far down a piece goes to be below the screen (negative).
	local function OffBelow(f)
		return -((f:GetTop() or UIParent:GetHeight()) + MO.MARGIN)
	end

	local function NearerFirst(a, b) return PC.key[a] < PC.key[b] end

	-- Every box of the mode becomes a piece, listed nearest the screen center first.
	local function BoxPieces()
		local w, h = UIParent:GetSize()
		local order, nb = PC.order, 0
		for moverKey in pairs(shown) do
			local m = SP.barMovers and SP.barMovers[moverKey]
			if m and m:IsShown() then
				local i = AddPiece(m, "box")
				PC.key[i] = CenterDist(m, w, h)
				nb = nb + 1
				order[nb] = i
			end
		end
		for k = nb + 1, #order do order[k] = nil end
		table.sort(order, NearerFirst)
		return nb
	end

	-- The landing pulse on a box: a jolt of logo blue through its edge, fading out
	-- (the approved clip: three 2 px rings at 0 / 2 / 4 px out, alphas 1 / 0.45 / 0.2).
	local rings = {}               -- box -> its 12 edge textures, made at its first landing
	local RING_A = { 1, 1, 1, 1, 0.45, 0.45, 0.45, 0.45, 0.2, 0.2, 0.2, 0.2 }
	local RING_BLUE = { 0.247, 0.663, 0.961 }   -- logo blue #3FA9F5 (SP.Brand.logoBlue)
	local function PaintRings(m, a)
		local r = rings[m]
		if not r then
			if a <= 0 then return end
			r = {}
			local c = SP.Brand and SP.Brand.logoBlue or RING_BLUE
			for o = 0, 4, 2 do
				for side = 1, 4 do
					local t = m:CreateTexture(nil, "BORDER", nil, 7)
					t:SetColorTexture(c[1], c[2], c[3], 1)
					if side == 1 then
						t:SetPoint("TOPLEFT", m, "TOPLEFT", -o, o)
						t:SetPoint("TOPRIGHT", m, "TOPRIGHT", o, o)
						t:SetHeight(2)
					elseif side == 2 then
						t:SetPoint("BOTTOMLEFT", m, "BOTTOMLEFT", -o, -o)
						t:SetPoint("BOTTOMRIGHT", m, "BOTTOMRIGHT", o, -o)
						t:SetHeight(2)
					elseif side == 3 then
						t:SetPoint("TOPLEFT", m, "TOPLEFT", -o, o - 2)
						t:SetPoint("BOTTOMLEFT", m, "BOTTOMLEFT", -o, 2 - o)
						t:SetWidth(2)
					else
						t:SetPoint("TOPRIGHT", m, "TOPRIGHT", o, o - 2)
						t:SetPoint("BOTTOMRIGHT", m, "BOTTOMRIGHT", o, 2 - o)
						t:SetWidth(2)
					end
					r[#r + 1] = t
				end
			end
			rings[m] = r
		end
		for i = 1, 12 do
			if a > 0 then
				r[i]:SetAlpha(a * RING_A[i])
				r[i]:Show()
			else
				r[i]:Hide()
			end
		end
	end

	-- The opening: the bar fading in around its docked logo (0 = not there yet).
	local function BarReveal(q)
		if q == OP.reveal then return end
		OP.reveal = q
		local body = doneBar.body
		if q <= 0 then
			body:Hide()
			doneBar:EnableMouse(false)
		else
			body:Show()
			body:SetAlpha(q)
			doneBar:EnableMouse(true)
		end
		if gridFrame then gridFrame:SetAlpha(q) end
		-- Tuck Away: the tab's spot is there, unseen, while the bar is down (it shows when it tucks)
		if TuckOn() then
			if q <= 0 then
				if BS.tab then BS.tab:Hide() end
			elseif not (BS.tab and BS.tab:IsShown()) then
				ShowTab(0)
			end
		end
	end

	DockLogo = function()
		local logo = doneBar.logo
		if not logo then return end   -- (without the brand kit the bar has no logo)
		logo:ClearAllPoints()
		logo:SetGraphicHeight(BAR.DOCK_H)
		logo:SetPoint("CENTER", doneBar.dock, "CENTER", 0, 0)
	end

	local function Listen(on)      -- a click anywhere finishes a move at once
		if on then
			pcall(driver.RegisterEvent, driver, "GLOBAL_MOUSE_DOWN")
		else
			pcall(driver.UnregisterEvent, driver, "GLOBAL_MOUSE_DOWN")
		end
	end

	-- back on their spots, seen and clickable again (a drop or Done hides them next)
	local function RestorePieces()
		for i = 1, PC.n do
			local f = PC.frame[i]
			PlacePiece(i, 0)
			f:SetAlpha(1)
			if PC.kind[i] ~= "tab" then f:EnableMouse(true) end
		end
		if doneBar then doneBar:SetClampedToScreen(BS.off == 0) end
		if gridFrame then gridFrame:SetAlpha(1) end
	end

	-- Each move's end state, reached when it runs out or at once (a click, Escape, a fight).
	local END = {}
	function END.open()
		OP.phase = 0
		if doneBar.logo then doneBar.logo:SetBuildTime(nil) end   -- the finished logo (a build playing stops, no call back)
		DockLogo()
		for moverKey in pairs(shown) do
			local m = SP.barMovers and SP.barMovers[moverKey]
			if m then m:SetAlpha(1) end
		end
		for i = 1, PC.n do PlacePiece(i, 0) end
		BarReveal(1)
		if TuckOn() and not MouseOnBar() then TuckArm() end
	end
	function END.rise()
		for i = 1, PC.n do
			PlacePiece(i, 0)
			if PC.kind[i] == "box" then PaintRings(PC.frame[i], 0) end
		end
		doneBar:SetClampedToScreen(BS.off == 0)
		if gridFrame then gridFrame:SetAlpha(1) end
		if TuckOn() and not MouseOnBar() then TuckArm() end
	end
	function END.drop(reason)
		RestorePieces()
		if reason == "combat" or reason == "cancel" then return end   -- a fight, or the mode ending: no settings
		StepAside(OP.page, OP.rr)
	end
	function END.done()   -- (cut short or not, the cleanup is the same; the settings fall in either way)
		RestorePieces()
		OffRest()
	end
	function END.tuck()
		if TK.goal == "up" then TuckedState() else DownState() end
		TK.goal = nil
	end

	-- reason: nil (it ran out), "skip" (a click or Escape), "combat", "cancel" (the mode is turned off)
	FinishScene = function(reason)
		local kind = scene
		if not kind then return end
		scene = nil
		driver:Hide()
		Listen(false)
		END[kind](reason)
	end

	local function BeginScene(kind)
		if scene and not (scene == "tuck" and kind == "tuck") then FinishScene("skip") end
		scene, PC.t, PC.stop, PC.started = kind, 0, math.huge, GetTime()
		if kind ~= "tuck" then
			PC.n = 0
			wipe(PC.of)
		end
		Listen(true)
	end

	-- Tuck Away, driven by the mouse entering and leaving the bar, its buttons and
	-- the tab (OnEnter / OnLeave): nothing polls.
	-- up: the bar closes in from both sides to the tab's width, then rises into the tab; down:
	-- it drops out of the tab to its spot, then opens out to both sides. Turned around halfway,
	-- it goes back from where it is.
	StartTuckSlide = function(up)
		if not ACTIVE or not doneBar or (scene and scene ~= "tuck") then return end   -- (Done, a trip ...: not now)
		local goal = up and "up" or "down"
		local first, second
		if scene == "tuck" then
			if TK.goal == goal then return end   -- (already on its way there)
			if up then
				if TK.seg == "O" then first, second = "C", "R" else first = "R" end
			elseif TK.seg == "C" then
				first = "O"
			else
				first, second = "D", "O"
			end
		else
			if up == (BS.off ~= 0) then return end   -- (already there)
			if not Animated() then   -- (UI Animations off: tucked / down at once; the leave wait stays)
				if not up then
					DownState()
				elseif TuckMeasure() then
					TuckedState()
				end
				return
			end
			EnsurePlate()
			if up then
				if not TuckMeasure() then return end
				TK.w, TK.h, TK.top, TK.alpha = TK.W, TK.H, TK.B, 1
				first, second = "C", "R"
			else
				TK.w, TK.h, TK.top, TK.alpha = BAR.TAB_W, BAR.TAB_H, 0, 0
				first, second = "D", "O"
			end
			PlacePlate()
			TK.plate:Show()
		end
		BeginScene("tuck")
		TK.goal, TK.seg2 = goal, second
		SegBegin(first, 0)
		PC.stop = TK.segD
		if second then PC.stop = PC.stop + MO.TUCK_TIME[second] end
		doneBar:SetClampedToScreen(false)
		driver:Show()
	end

	local function TuckFire()
		TK.wait = false
		if TK.hover or not (ACTIVE and TuckOn()) then return end
		local left = TK.at - GetTime()
		if left > 0.02 then
			TK.wait = true
			C_Timer.After(left, TuckFire)
			return
		end
		StartTuckSlide(true)
	end

	-- the mouse left the bar and its tab: up it goes after a moment (one timer out at a time)
	TuckArm = function()
		if TK.hover or not (ACTIVE and TuckOn()) then return end
		TK.at = GetTime() + MO.TUCK_WAIT
		if not TK.wait then
			TK.wait = true
			C_Timer.After(MO.TUCK_WAIT, TuckFire)
		end
	end

	-- fromTab: the tab's own OnEnter. While the bar tucks away only the tab calls it back, so a
	-- twitch over the bar as it goes does not.
	BarHover = function(on, fromTab)
		TK.hover = on
		if not (ACTIVE and TuckOn()) or (scene and scene ~= "tuck") then return end
		if not on then
			TuckArm()
		elseif fromTab or not (scene == "tuck" and TK.goal == "up") then
			StartTuckSlide(false)
		end
	end

	-- The moves, frame by frame (t: seconds into the move).
	local OpenBuilt   -- (below: the logo build is done)
	local STEP = {}
	function STEP.open(t)
		if OP.phase == 1 then   -- waiting for the settings window to leave
			if t >= OP.buildAt then
				OP.phase = 2
				if doneBar.logo then
					driver:Hide()        -- the build runs itself (ShamanPowerBrand.lua)
					doneBar.logo:PlayBuild(OpenBuilt)
				else
					OpenBuilt()
				end
			end
			return
		end
		if OP.phase ~= 3 then return end
		-- the finished logo shrinks and travels into its spot beside the title
		if not OP.docked then
			local e = MO.Dock(t)
			if e >= 1 then
				DockLogo()
				OP.docked = true
			else
				local logo = doneBar.logo
				logo:SetGraphicHeight(OP.big + (BAR.DOCK_H - OP.big) * e)
				logo:ClearAllPoints()
				logo:SetPoint("CENTER", doneBar, "TOPLEFT", OP.x0 + (BAR.DOCK_CX - OP.x0) * e,
					OP.y0 + (BAR.DOCK_CY - OP.y0) * e)
			end
		end
		-- the boxes rise in, nearest the screen center first
		for i = 1, PC.n do
			local a, dy = MO.RiseIn(t - MO.RIPPLE_AT - PC.delay[i])
			PlacePiece(i, dy)
			PC.frame[i]:SetAlpha(a)
		end
		-- the bar fades in around the docked logo
		BarReveal(MO.BarFade(t))
	end
	function STEP.rise(t)
		for i = 1, PC.n do
			local tl = t - PC.delay[i]
			PlacePiece(i, MO.RiseBack(tl, PC.dist[i]))
			if PC.kind[i] == "box" then
				local a = MO.Hit(tl, MO.RISE)
				if a > 0 or PC.lit[i] then
					PaintRings(PC.frame[i], a)
					PC.lit[i] = a > 0
				end
			end
		end
		if gridFrame then gridFrame:SetAlpha(Clamp01(t / MO.RISE)) end
	end
	function STEP.drop(t)
		for i = 1, PC.n do PlacePiece(i, MO.Drop(t - PC.delay[i], PC.dist[i])) end
		if gridFrame then gridFrame:SetAlpha(1 - Clamp01(t / MO.DROP)) end
	end
	function STEP.done(t)
		for i = 1, PC.n do
			local tl = t - PC.delay[i]
			if PC.kind[i] == "box" then
				local a, dy = MO.Sink(tl)
				PlacePiece(i, dy)
				PC.frame[i]:SetAlpha(a)
			else
				PlacePiece(i, MO.Up(tl, MO.UP, PC.dist[i]))
			end
		end
		if gridFrame then gridFrame:SetAlpha(1 - Clamp01(t / MO.UP)) end
	end
	function STEP.tuck(t)
		local st = t - TK.segStart
		if st >= TK.segD and TK.seg2 then   -- the next segment, from where this one ends
			TK.w, TK.h, TK.top = SegTarget(TK.seg)
			local nextSeg = TK.seg2
			TK.seg2 = nil
			SegBegin(nextSeg, TK.segStart + TK.segD)
			st = t - TK.segStart
		end
		local kind = TK.seg
		local e = MO.TuckEase(kind, Clamp01(st / TK.segD))
		local w1, h1, top1 = SegTarget(kind)
		TK.w = TK.w0 + (w1 - TK.w0) * e
		TK.h = TK.h0 + (h1 - TK.h0) * e
		TK.top = TK.top0 + (top1 - TK.top0) * e
		PlacePlate()
		-- the bar's own contents: out over the first moment of closing in, back as the opening ends
		if kind == "C" then
			if TK.alpha > 0 then BarContents(TK.a0 * (1 - Clamp01(st / MO.TUCK_FADE))) end
		elseif kind == "O" then
			local span = math.min(MO.TUCK_FADE, TK.segD)
			local f = (st - (TK.segD - span)) / span
			if f > 0 then BarContents(TK.a0 + (1 - TK.a0) * Clamp01(f)) end
		end
		-- the tab: there only as the plate arrives in it, gone as it leaves
		if BS.tab then
			local a = 0
			if kind == "R" or kind == "D" then
				a = Clamp01(1 - (TK.h - BAR.TAB_H) / (0.35 * math.max(1, TK.H - BAR.TAB_H)))
			end
			BS.tab:SetAlpha(a)
		end
	end

	driver:SetScript("OnUpdate", function(_, elapsed)
		PC.t = PC.t + elapsed
		local kind = scene
		local step = kind and STEP[kind]
		if not step then
			driver:Hide()
			return
		end
		step(PC.t)
		if scene == kind and PC.t >= PC.stop then FinishScene(nil) end
	end)
	-- GLOBAL_MOUSE_DOWN. Not in the frame a move starts: that click is the one that started it
	-- (or finished the settings window's own motion and brought this one on)
	driver:SetScript("OnEvent", function()
		if GetTime() ~= PC.started then FinishScene("skip") end
	end)

	-- The opening: the settings window rises off the top (0 -> 0.15), the logo builds
	-- at the screen center at the intro's pace (-> 1.81), then docks beside the bar's
	-- title (-> 2.05) while the boxes rise in from the center outward (1.90 -> 2.50)
	-- and the bar fades in around it (2.10 -> 2.45). Nothing stays at the center.
	OpenBuilt = function()
		if scene ~= "open" or OP.phase ~= 2 then return end   -- (finished meanwhile)
		OP.phase, PC.t = 3, 0
		local nb = BoxPieces()
		MO.Ripple(PC.key, nb, PC.delay)
		local w, h = UIParent:GetSize()
		local l, t = doneBar:GetLeft(), doneBar:GetTop()
		if l then OP.x0, OP.y0 = w / 2 - l, h / 2 - t else OP.x0, OP.y0 = BAR.DOCK_CX, BAR.DOCK_CY end
		PC.stop = math.max(MO.DOCK, MO.RIPPLE_AT + MO.RIPPLE + MO.BOX_RISE, MO.BAR_AT + MO.BAR_FADE)
		driver:Show()
	end

	StartOpening = function(buildAt)
		BeginScene("open")
		if not Animated() then   -- (UI Animations off: the bar with its docked logo and every box, at once)
			OP.phase, OP.reveal = 0, -1
			FinishScene(nil)
			return
		end
		local logo = doneBar.logo   -- (none without the brand kit: then no build and no dock)
		OP.phase, OP.buildAt, OP.docked = 1, buildAt, logo == nil
		-- each box waits unseen for its turn (a click finishes the opening: then it is there)
		for moverKey in pairs(shown) do
			local m = SP.barMovers and SP.barMovers[moverKey]
			if m then m:SetAlpha(0) end
		end
		OP.reveal = -1
		BarReveal(0)
		-- the logo, as tall on the screen as in the intro
		if logo then
			OP.big = UIParent:GetHeight() * BAR.BIG
			logo:ClearAllPoints()
			logo:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
			logo:SetGraphicHeight(OP.big)
			logo:SetBuildTime(SP.Brand.BUILD_START)
		end
		if buildAt > 0 then
			driver:Show()
		else
			OP.phase = 2
			if logo then logo:PlayBuild(OpenBuilt) else OpenBuilt() end
		end
	end

	-- Back from the settings window (no logo build): everything rises back up from
	-- below the screen into place, one after another, each box landing with a pulse.
	StartRise = function()
		BeginScene("rise")
		local order = PC.order
		local nb = BoxPieces()
		for k = 1, nb do
			local i = order[k]
			PC.dist[i] = OffBelow(PC.frame[i])
		end
		local n = nb + 1
		if TuckOn() then   -- the bar stays tucked up: its tab comes back instead
			local up = TuckedOff()
			TuckMeasure()   -- (the bar's spot, for the next time it drops out of the tab)
			ShowTab(1)
			BarPlace(up)
			order[n] = AddPiece(BS.tab, "tab")
		else
			order[n] = AddPiece(doneBar, "bar")
		end
		PC.dist[order[n]] = OffBelow(PC.frame[order[n]])
		local step = MO.Step(n, MO.RISE_STEP, MO.SPAN)
		for k = 1, n do PC.delay[order[k]] = (k - 1) * step end
		PC.stop = (n - 1) * step + math.max(MO.RISE, MO.HIT_AT * MO.RISE + MO.HIT)
		if not Animated() then FinishScene(nil) return end   -- (UI Animations off: back in place at once)
		STEP.rise(0)
		driver:Show()
	end

	-- A right-click (or the bar's Settings): every box and the bar drop away off the
	-- bottom, one after another; then the settings window falls in (StepAside).
	StartDrop = function(page, rrKey)
		BeginScene("drop")
		Select(nil)   -- (the picked box goes with the rest: its arrow keys and gold edge go now)
		OP.page, OP.rr = page, rrKey
		if readout then readout:Hide() end
		RO.box = nil
		local order = PC.order
		local nb = BoxPieces()
		for k = 1, nb do
			local i = order[k]
			PC.dist[i] = OffBelow(PC.frame[i])
			PC.frame[i]:EnableMouse(false)   -- (going away: nothing to grab)
		end
		local n = nb
		if BS.off == 0 then   -- (tucked, the bar is already out of sight: its tab goes)
			n = n + 1
			order[n] = AddPiece(doneBar, "bar")
			PC.dist[order[n]] = OffBelow(doneBar)
			doneBar:EnableMouse(false)
		end
		if BS.tab and BS.tab:IsShown() and BS.off ~= 0 then   -- (unseen while the bar is down: it stays)
			n = n + 1
			order[n] = AddPiece(BS.tab, "tab")
			PC.dist[order[n]] = OffBelow(BS.tab)
		end
		local step = MO.Step(n, MO.DROP_STEP, MO.SPAN)
		for k = 1, n do PC.delay[order[k]] = (k - 1) * step end
		PC.stop = math.max(0, n - 1) * step + MO.DROP
		if not Animated() then FinishScene(nil) return end   -- (UI Animations off: gone at once, the settings open)
		driver:Show()
	end

	-- Done: the boxes go like totems being removed (each sinks and fades) and the bar
	-- goes up off the top; then the mode's cleanup (OffRest).
	StartDone = function()
		BeginScene("done")
		local order = PC.order
		local nb = BoxPieces()
		local step = MO.Step(nb, MO.SINK_STEP, MO.SINK_SPAN)
		for k = 1, nb do
			local i = order[k]
			PC.delay[i] = (k - 1) * step
			PC.frame[i]:EnableMouse(false)
		end
		if BS.off == 0 then   -- (tucked, it is already up there: its tab goes)
			local i = AddPiece(doneBar, "bar")
			PC.dist[i] = UIParent:GetHeight() - (doneBar:GetBottom() or 0) + MO.MARGIN
			doneBar:EnableMouse(false)
		end
		if BS.tab and BS.tab:IsShown() and BS.off ~= 0 then
			local i = AddPiece(BS.tab, "tab")
			PC.dist[i] = BAR.TAB_H + MO.MARGIN
		end
		PC.stop = MO.UP
		if nb > 0 then PC.stop = math.max(PC.stop, (nb - 1) * step + MO.SINK) end
		driver:Show()
	end

	-- ShowBarMover puts a box over its frame: at the start, after a drop or a nudge, a
	-- Reset, a module's own re-layout. While something moves, that box keeps its place
	-- in the move (a box that turns up late, like the cooldown bar's a frame after the
	-- rest, joins it); the picked box's readout follows it.
	hooksecurefunc(SP, "ShowBarMover", function(sp, key)
		local m = sp.barMovers and sp.barMovers[key]
		if not (m and m:IsShown()) then return end
		if scene and scene ~= "tuck" then
			local i = PC.of[m]
			if i then
				ReadHome(i)                 -- (its frame moved or grew meanwhile: this is its spot now)
				PlacePiece(i, PC.off[i])
			elseif ACTIVE and shown[key] then
				if scene == "open" then
					m:SetAlpha(0)
					if OP.phase == 3 then
						local j = AddPiece(m, "box")
						PC.delay[j] = math.max(0, PC.t - MO.RIPPLE_AT)
						PlacePiece(j, -MO.BOX_LIFT)
					end
				elseif scene == "rise" then
					local j = AddPiece(m, "box")
					PC.delay[j], PC.dist[j] = PC.t, OffBelow(m)
					PlacePiece(j, PC.dist[j])
					PC.stop = math.max(PC.stop, PC.t + MO.HIT_AT * MO.RISE + MO.HIT)
				end
			end
		end
		if m == RO.box and readout and readout:IsShown() then
			local x, y = BoxXY(m)
			if x and (x ~= RO.x or y ~= RO.y) then CoordsText(m, x, y) end
		end
	end)
end

-- Mouse wheel over a box: its size; Ctrl + wheel: its opacity. One step of its
-- settings slider at a time, within the slider's own limits.
function SP:UnlockBoxWheel(mover, delta)
	if not ACTIVE or InCombatLockdown() then return end
	if scene then FinishScene("skip") end   -- (scrolled while it rises in: it is there now)
	if not ACTIVE then return end
	local fx = FX[ModuleKeyOf(mover)]
	if not fx then return end
	accessMover = mover
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
	accessMover = nil
	ShowReadout(mover, text)
	self:RefreshUnlockBoxes()
	C_Timer.After(0, function() SP:RefreshUnlockBoxes() end)   -- again once the resized frames are laid out
end

-- Click a box: pick it (the arrow keys move it) and show where it is. Right-click:
-- its settings page (the boxes drop away until the window closes; a Ready
-- Reminder icon's box opens that icon's own menu there).
function SP:UnlockBoxClick(mover, button)
	if not ACTIVE or InCombatLockdown() then return end
	-- the right button while the left still drags this box: the drag goes on (its drop saves it)
	if button == "RightButton" and mover:GetScript("OnUpdate") == DragUpdate then return end
	if scene then FinishScene("skip") end
	if not self:IsMasterUnlocked() then return end   -- (a drop finished just now has stepped aside)
	Select(mover)
	if button ~= "RightButton" then
		ShowCoords(mover)
		return
	end
	local mod = ModuleKeyOf(mover)
	local fx = FX[mod]
	if fx and fx.page then
		-- no settings module (switched off): nowhere to go. It says so; Unlock UI stays
		if not rawget(_G, "ShamanPowerConfig") then self:OpenConfigWindow(fx.page) return end
		-- a page that shows one of several (Pop-Out Trackers): this box's one first
		local pick = fx.pick
		local node = pick and FindOption(pick.node, nil, "select")
		if node and type(node.set) == "function" then pcall(node.set, { pick.node, option = node }, pick.value) end
		-- a Ready Reminder icon's own box (free placement) carries its catalog key;
		-- the Grid block's box has none: the plain page
		local rrKey
		local e = mod == "readyreminders" and shown[mover.key]
		local entry = e and e.frame and e.frame.entry
		if entry then rrKey = entry.key end
		StartDrop(fx.page, rrKey)
		return
	end
	if doneBar and doneBar.Refresh then doneBar:Refresh() end
end

function SP:UnlockDragStart(mover)
	if not ACTIVE or InCombatLockdown() then return false end
	if scene then FinishScene("skip") end   -- (grabbed while it rises in: it is on its spot now)
	if not ACTIVE then return false end
	Select(mover)
	local uis = UIParent:GetEffectiveScale()
	local s = mover:GetEffectiveScale() / uis
	local fx, fy = mover:GetCenter()
	local cx, cy = GetCursorPosition()
	if not fx then return false end
	mover.spDragDX, mover.spDragDY = fx * s - cx / uis, fy * s - cy / uis
	mover:SetScript("OnUpdate", DragUpdate)
	ShowCoords(mover, true)
	return true
end

function SP:UnlockDragStop(mover)
	if not mover:GetScript("OnUpdate") then return false end
	mover:SetScript("OnUpdate", nil)
	ShowGuides()
	if RO.box == mover then ReadoutRelease() end
	return true
end

-- ---------------------------------------------------------------------------
-- The bar at the top of the screen: the keys, Snapping, the grid, Tuck Away, the
-- settings window, Reset All Positions and Done. In the 3.0.6 brand: Fira Sans,
-- the four elements along its top edge, the tiny totem switches, and the logo
-- docked beside the title.
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
local enterBack = false   -- the mode comes back from that window: no logo build, everything rises
local function SettingsClosed()
	local back, w = backAfterSettings, SettingsWindow()
	if not back or (w and w:IsShown()) then return end   -- (Alt+Z hides it with the rest of the UI: not a close)
	backAfterSettings = nil
	SettingsMotion("SetMotionClose", false)   -- (it has shot up off the top on its way out)
	if SP.unlockOnDone == nil then SP.unlockOnDone = back.onDone end
	if ACTIVE then return end   -- unlocked again from the window
	-- a fight ends the trip as it ends the mode. As one starts, the window can close a moment
	-- before or after our combat handler runs, while InCombatLockdown() is still false
	if InCombatLockdown() or back.fightAt == GetTime() or (UnitAffectingCombat and UnitAffectingCombat("player")) then
		FightStopsTrip()
		return
	end
	enterBack = true
	BS.backAt = GetTime()   -- (an Escape closed the window: that same key press is not for the bar, see its OnHide)
	SP:SetMasterUnlock(true, back.only)
	enterBack = false
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

-- The mode steps aside for a settings page and comes back as it was when the
-- window closes. The page: `page`, a Ready Reminder icon's own menu (rrKey: its
-- catalog key, Ready Reminders opens it), else the page used last.
function SP:UnlockSettingsPage(page, rrKey)
	backAfterSettings = { only = onlyKey, onDone = self.unlockOnDone, toConfig = self.unlockReturnToConfig }
	self.unlockOnDone, self.unlockReturnToConfig = nil, nil
	TurnOff(true)   -- (its boxes have dropped away already)
	local opened = false
	if rrKey and type(self.ReadyReminderOpenIconMenu) == "function" then
		local ok = pcall(self.ReadyReminderOpenIconMenu, self, rrKey)
		local w = SettingsWindow()   -- (the call may have built the window)
		opened = ok and w ~= nil and w:IsShown()
	end
	if not opened then
		local w = SettingsWindow()
		if page then
			self:OpenConfigWindow(page)
		elseif w and w:IsShown() then
			w:Raise()
		elseif w then
			self:ReopenSettingsWindow()   -- on the page it was left on
		else
			self:OpenConfigWindow()
		end
	end
	HookSettingsWindow()
end

-- The trip's first half, once everything has dropped away: the page falls in from
-- the top, however the drop ended (every open of the settings falls in). Closing it (X, Done,
-- Escape) shoots it up off the top and brings Unlock UI back (SettingsClosed).
StepAside = function(page, rrKey)
	local w = SettingsWindow()
	local was = w and w:IsShown()
	SP:UnlockSettingsPage(page, rrKey)
	w = SettingsWindow()
	if w and w:IsShown() then
		SettingsMotion("SetMotionClose", true)
		if not was then SettingsMotion("MotionIn") end   -- (the window's own open does too: one plays)
	end
end

-- The bar's Settings: the same trip as a right-click, to the page used last.
local function SettingsTrip()
	if not ACTIVE or InCombatLockdown() then return end
	-- no settings module (switched off): nowhere to go. It says so; Unlock UI stays
	if not rawget(_G, "ShamanPowerConfig") then SP:OpenConfigWindow() return end
	if scene then FinishScene("skip") end
	if ACTIVE then StartDrop(nil, nil) end
end

-- The bar's controls report the mouse for Tuck Away (hooked: their own hover stays).
local function HoverIn() BarHover(true) end
local function HoverOut() BarHover(false) end

-- A button on the bar: ShamanPower's own (its caption in the dialog font).
local function BarButton(parent, text, minW, primary)
	local b = SP:CreateSPButton(parent, text, minW, primary)
	b:HookScript("OnEnter", HoverIn)
	b:HookScript("OnLeave", HoverOut)
	return b
end

-- Without the brand kit (ShamanPowerBrand.lua not loaded yet): the plain switch the
-- bar had before, a track with a knob, answering the same SetChecked.
local function PlainSwitch(parent)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(30, 14)
	local track = b:CreateTexture(nil, "ARTWORK")
	track:SetAllPoints()
	local knob = b:CreateTexture(nil, "OVERLAY")
	knob:SetSize(12, 12)
	knob:SetColorTexture(0.95, 0.96, 0.98)
	function b:SetChecked(on)
		track:SetColorTexture(SP:SPColor(on and "accent" or "off"))
		knob:ClearAllPoints()
		knob:SetPoint("LEFT", self, "LEFT", on and 17 or 1, 0)
	end
	return b
end

-- An on / off switch: the tiny totem box on its duration bar, in logo blue
-- (ShamanPowerBrand.lua), its label beside it; one click target for both.
local function MakeSwitch(parent, label, get, set, tip)
	local sw
	if SP.CreateTotemSwitch then
		sw = SP:CreateTotemSwitch(parent, { element = "spirit", checked = get() and true or false })
	else
		sw = PlainSwitch(parent)
		sw:SetChecked(get() and true or false)
	end
	local text = sw:CreateFontString(nil, "OVERLAY")
	text:SetFontObject(SP.SPDialogFonts.text)
	text:SetPoint("LEFT", sw, "RIGHT", 8, 0)
	text:SetText(label)
	sw.label, sw.labelW = text, math.ceil(text:GetStringWidth())
	sw:SetHitRectInsets(0, -(8 + sw.labelW), -4, -4)
	function sw:Refresh() self:SetChecked(get() and true or false) end
	sw:SetScript("OnClick", function(self) set(not get()); self:Refresh() end)
	sw:SetScript("OnEnter", function(self)
		local box = SP.Tooltip or GameTooltip
		box:SetOwner(self, "ANCHOR_CURSOR")
		box:SetText(label)
		box:AddLine(tip, nil, nil, nil, true)
		box:Show()
		BarHover(true)
	end)
	sw:SetScript("OnLeave", function() (SP.Tooltip or GameTooltip):Hide(); BarHover(false) end)
	return sw
end

-- Tuck Away on: the bar tucks away into its tab at once. Off: the bar stays down.
local function SetTuck(v)
	if v then
		SP.opt.unlockTuck = true
		ShowTab(0)   -- (its spot; seen once the bar is in it)
		StartTuckSlide(true)
	else
		SP.opt.unlockTuck = nil
		StartTuckSlide(false)   -- (on its way up or tucked: it comes back down)
		if BS.tab then BS.tab:Hide() end
	end
end

-- Escape hid the bar (UISpecialFrames). The bar stays up for what comes next, which
-- runs a frame later: the same key press must not also shut the settings window a
-- Done brings back. Escape during a move finishes the move at once; otherwise it
-- ends Unlock UI as Done does. (With a box picked, Escape only lets the box go: the
-- arrow keys' frame takes it.)
local ESC = { wait = false }   -- wait: the next frame's call is out; kind: the move Escape met
local function AfterEscape()
	ESC.wait = false
	local was = ESC.kind
	ESC.kind = nil
	if scene then FinishScene("skip") end
	if was and was ~= "tuck" then return end
	if ACTIVE then SP:SetMasterUnlock(false) end
end

local function EnsureDoneBar()
	if doneBar then return doneBar end
	local f = CreateFrame("Frame", "ShamanPowerUnlockBar", UIParent)
	-- D36b A (owner 2026-10-02): one slim line flush with the top of the screen, out of the
	-- way of the boxes being moved (the old box, 840 x 225 and 70 down, covered them); the
	-- instructions wait behind the ? (hover)
	f:SetSize(1180, 36)
	f:SetPoint("TOP", UIParent, "TOP", 0, 0)
	f:SetFrameStrata("FULLSCREEN_DIALOG")
	f:SetFrameLevel(50)
	f:EnableMouse(true)
	-- dragged anywhere on its background, out of the way of what is being moved
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		if BS.tab and BS.tab:IsShown() then ShowTab(BS.tab:GetAlpha()) end   -- (the tab follows the bar's new spot)
	end)
	f:SetScript("OnEnter", HoverIn)
	f:SetScript("OnLeave", HoverOut)

	-- everything but the docked logo sits on `body`, so the bar can fade in around the logo
	local body = CreateFrame("Frame", nil, f)
	body:SetAllPoints(f)
	f.body = body
	local bg = body:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(SP:SPColor("windowBg", 0.94))
	SP:SPMakeBorder(body, "border", 1.5)   -- the settings window's soft edge (as the Keybind Mode bar)
	TopStripe(body)

	-- the logo: the opening builds it at the screen center and docks it here, beside the title
	local dock = CreateFrame("Frame", nil, f)
	dock:SetSize(BAR.DOCK_W, BAR.DOCK_H)
	dock:SetPoint("TOPLEFT", f, "TOPLEFT", BAR.DOCK_X, BAR.DOCK_Y)
	f.dock = dock
	if SP.CreateTotemBuild then   -- (without the brand kit: no logo, the title keeps its place)
		f.logo = SP:CreateTotemBuild(f)
		f.logo:SetFrameLevel(f:GetFrameLevel() + 20)
	end

	local F = SP.SPDialogFonts
	local title = body:CreateFontString(nil, "OVERLAY")
	title:SetFontObject(F.title)
	title:SetPoint("LEFT", dock, "RIGHT", 8, 0)
	title:SetText("Unlock UI")
	local sub = body:CreateFontString(nil, "OVERLAY")
	sub:SetFontObject(F.tiny)
	sub:SetPoint("LEFT", title, "RIGHT", 10, -1)
	sub:SetText("DRAG ANY BLUE BOX")
	local div = body:CreateTexture(nil, "ARTWORK")
	div:SetSize(1, 18)
	div:SetColorTexture(SP:SPColor("border"))
	div:SetPoint("LEFT", sub, "RIGHT", 16, 1)

	-- one row, centered on the bar under its stripe
	local row = CreateFrame("Frame", nil, body)
	row:SetPoint("LEFT", div, "RIGHT", 16, 0)
	row:SetPoint("RIGHT", f, "RIGHT", -10, 0)
	row:SetHeight(26)
	local snap = MakeSwitch(row, "Snapping", SnapOn,
		function(v) if v then SP.opt.unlockSnap = nil else SP.opt.unlockSnap = false end end,
		"Line up dragged boxes with other boxes' edges and centers, or the screen center. Boxes snap within 8 pixels. Gold lines show the alignment. This choice is saved.")
	snap:SetPoint("LEFT", row, "LEFT", 0, 0)
	local grid = MakeSwitch(row, "Show Grid", function() return SP.opt.unlockGrid end,
		function(v) if v then SP.opt.unlockGrid = true else SP.opt.unlockGrid = nil end; ApplyGrid() end,
		"Show a grid to help line up your bars and panels. Away from other boxes, a dropped box lines up with the grid. This choice is saved.")
	grid:SetPoint("LEFT", snap.label, "RIGHT", 20, 0)
	local function stepGrid(d)
		local g = math.min(math.max(GridSize() + d, 8), 128)
		if g == GRID_DEFAULT then SP.opt.unlockGridSize = nil else SP.opt.unlockGridSize = g end
		ApplyGrid()
	end
	local function gridTip(self)
		local tip = SP.Tooltip or GameTooltip
		tip:SetOwner(self, "ANCHOR_CURSOR")
		tip:SetText("Grid Size")
		tip:AddLine("The space between the grid's lines, in steps of 4.", nil, nil, nil, true)
		tip:Show()
	end
	local minus = BarButton(row, "-", 22, false)
	minus:SetHeight(22)
	minus:SetPoint("LEFT", grid.label, "RIGHT", 10, 0)
	minus:SetScript("OnClick", function() stepGrid(-4) end)
	local value = row:CreateFontString(nil, "OVERLAY")
	value:SetFontObject(F.text)
	value:SetWidth(30)
	value:SetJustifyH("CENTER")
	value:SetPoint("LEFT", minus, "RIGHT", 2, 0)
	local plus = BarButton(row, "+", 22, false)
	plus:SetHeight(22)
	plus:SetPoint("LEFT", value, "RIGHT", 2, 0)
	plus:SetScript("OnClick", function() stepGrid(4) end)
	for _, b in ipairs({ minus, plus }) do
		b:HookScript("OnEnter", gridTip)
		b:HookScript("OnLeave", function() (SP.Tooltip or GameTooltip):Hide() end)
	end
	local tuck = MakeSwitch(row, "Tuck Away", TuckOn, SetTuck,
		"Slides this bar up out of the way, leaving a small tab at the top of the screen."
		.. " Point at the tab to bring the bar back. Remembered for next time.")
	tuck:SetPoint("LEFT", plus, "RIGHT", 20, 0)

	local done = BarButton(row, "Done", 84, true)
	done:SetHeight(24)
	done:SetPoint("RIGHT", row, "RIGHT", 0, 0)
	done:SetScript("OnClick", function() SP:SetMasterUnlock(false) end)
	local all = BarButton(row, "Reset All Positions", 150, false)
	all:SetHeight(24)
	all:SetPoint("RIGHT", done, "LEFT", -8, 0)
	all:SetScript("OnClick", ConfirmResetAll)
	local settings = BarButton(row, "Settings", 84, false)
	settings:SetHeight(24)
	settings:SetPoint("RIGHT", all, "LEFT", -8, 0)
	settings:SetScript("OnClick", SettingsTrip)
	-- hooked: the button's own OnEnter/OnLeave draw its hover
	settings:HookScript("OnEnter", function(self)
		local tip = SP.Tooltip or GameTooltip
		tip:SetOwner(self, "ANCHOR_CURSOR")
		tip:SetText("Settings")
		tip:AddLine("Opens ShamanPower's settings on the page you used last. Unlock UI comes back when"
			.. " you close them. Right-click a box to open its own page.", nil, nil, nil, true)
		tip:Show()
	end)
	settings:HookScript("OnLeave", function() (SP.Tooltip or GameTooltip):Hide() end)

	-- ? : the controls, as a card under it while the mouse is on it (the old bar's rows)
	local help = BarButton(row, "?", 24, false)
	help:SetSize(24, 24)
	help:SetPoint("RIGHT", settings, "LEFT", -12, 0)
	local card = CreateFrame("Frame", nil, f)
	card:SetFrameLevel(f:GetFrameLevel() + 40)
	local cbg = card:CreateTexture(nil, "BACKGROUND"); cbg:SetAllPoints(); cbg:SetColorTexture(SP:SPColor("windowBg", 0.96))
	SP:SPMakeBorder(card, "border", 1.5)
	TopStripe(card)
	local head = card:CreateFontString(nil, "OVERLAY")
	head:SetFontObject(F.title)
	head:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -12)
	head:SetText("Moving things")
	local cy, widest = -38, 0
	for _, k in ipairs(KEYS) do
		local key = card:CreateFontString(nil, "OVERLAY")
		key:SetFontObject(F.text)
		key:SetTextColor(1, 0.82, 0)
		key:SetPoint("TOPLEFT", card, "TOPLEFT", 12, cy)
		key:SetText(k[1])
		local what = card:CreateFontString(nil, "OVERLAY")
		what:SetFontObject(F.text)
		what:SetPoint("TOPLEFT", card, "TOPLEFT", 172, cy)
		what:SetJustifyH("LEFT")
		what:SetText(k[2])
		widest = math.max(widest, math.ceil(what:GetStringWidth()))
		cy = cy - 19
	end
	card:SetSize(172 + widest + 14, -cy + 8)
	card:SetPoint("TOPRIGHT", help, "BOTTOMRIGHT", 0, -10)
	card:Hide()
	help:HookScript("OnEnter", function() card:Show() end)
	help:HookScript("OnLeave", function() card:Hide() end)
	f.helpCard = card
	function f:Refresh()
		snap:Refresh()
		grid:Refresh()
		tuck:Refresh()
		value:SetText(GridSize())
		HookSettingsWindow()
	end
	-- hidden before the OnHide below exists: this runs with the mode already
	-- on, so that handler would end the mode the moment the bar is made
	f:Hide()
	tinsert(UISpecialFrames, "ShamanPowerUnlockBar")
	f:SetScript("OnHide", function(self)
		if self:IsShown() or not (ACTIVE or scene) then return end   -- a hidden UI (Alt+Z), or the mode's own end
		self:Show()   -- Escape: see AfterEscape
		-- the Escape that just closed the settings window, which brought the bar back in the
		-- same pass over UISpecialFrames (at once with UI Animations off): it stays, nothing ends
		if BS.backAt == GetTime() then return end
		if not ESC.wait then
			ESC.wait = true
			ESC.kind = scene
			C_Timer.After(0, AfterEscape)
		end
	end)
	doneBar = f
	DockLogo()
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

-- Turning the mode off comes in two halves: what stops at once (the keys, a drag,
-- the readout) and the cleanup, which runs after the Done motion, or at once when
-- there is none (a fight, a hidden UI, a trip to the settings window).
local function OffNow()
	ACTIVE = false
	Select(nil)
	ShowGuides()
	if readout then readout:Hide() end
	RO.hold, RO.box = false, nil
	for _, m in pairs(SP.barMovers or {}) do m:EnableMouseWheel(false); m:SetScript("OnUpdate", nil) end
end

-- The settings window a Done brings back falls in from the top, however the Done motion
-- ended (run out, a click, Escape): every open of the settings falls in.
OffRest = function()
	for moverKey, e in pairs(shown) do
		if e.bar then
			if moverKey == "totembar" then SP:SetTotemBarUnlocked(false) else SP:SetCooldownBarUnlocked(false) end
		else
			SP:HideBarMover(moverKey)
		end
		local mover = SP.barMovers and SP.barMovers[moverKey]
		if mover and mover.spReset then mover.spReset:Hide() end
	end
	wipe(shown)
	-- sample content off first, so each module decides for itself what shows now;
	-- then anything that was hidden before we started goes back to hidden
	for key in pairs(demos) do
		local def = SP.PreviewRegistry and SP.PreviewRegistry[key]
		local demo = def and DemoMethod(def)
		if demo then pcall(demo, SP, false) end
	end
	wipe(demos)
	SP.unlockDemoAll = nil
	for frame in pairs(forced) do
		if frame:IsShown() then pcall(frame.Hide, frame) end
	end
	wipe(forced)
	if doneBar then
		if BS.off ~= 0 then BarPlace(0) end   -- (tucked away: back on its spot for next time)
		doneBar:SetClampedToScreen(true)
		doneBar:Hide()
	end
	if BS.tab then BS.tab:Hide() end
	if gridFrame then gridFrame:Hide(); gridFrame:SetAlpha(1) end
	SP:HideSPDialog("unlock_reset_all")   -- its question is about the boxes just put away
	-- whoever opened the unlock (the setup tour) gets control back
	if SP.unlockOnDone then
		local fn = SP.unlockOnDone
		SP.unlockOnDone = nil
		pcall(fn)
	end
	if SP.unlockReturnToConfig then
		SP.unlockReturnToConfig = nil
		local w = SettingsWindow()
		local was = w and w:IsShown()
		SP:ReopenSettingsWindow()
		w = SettingsWindow()
		if not was and w and w:IsShown() then SettingsMotion("MotionIn") end   -- (ReopenSettingsWindow does too: one plays)
	end
	-- a page opened meanwhile (right-click on a box) mounts its preview now
	local api = rawget(_G, "ShamanPowerConfig")
	if api and api.UpdatePreviewPane then pcall(api.UpdatePreviewPane, api, true) end
end

-- instant: no Done motion (a fight, a trip to the settings window, another unlock)
TurnOff = function(instant)
	if not ACTIVE then return end
	if scene then FinishScene("cancel") end   -- (a move of the mode stops where it would end: no trip)
	-- a box still being dragged: no Done motion, so it cannot sink before its drop saves it
	for _, m in pairs(SP.barMovers or {}) do
		if m:GetScript("OnUpdate") == DragUpdate then instant = true end
	end
	OffNow()
	if instant or not Animated() or InCombatLockdown() or not (doneBar and doneBar:IsVisible()) then
		OffRest()
	else
		StartDone()
	end
end

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
		TurnOff(false)
		return
	end

	if scene then FinishScene("skip") end   -- (a Done still moving: its cleanup runs now)
	local back = enterBack
	enterBack = false
	ACTIVE = true
	onlyKey = only
	self.unlockDemoAll = true   -- demos fill every frame they own, not just the one the wizard borrows
	-- our own windows would sit on top of what is being moved: the settings window
	-- rises off the top first (its own motion), then the logo builds
	local buildAt = 0
	local cfg = _G["ShamanPowerConfigUIFrame"]
	if SettingsOpen(cfg) then   -- (one already on its way out was being closed: it stays closed)
		self.unlockReturnToConfig = true
		SettingsMotion("SetMotionClose", false)
		if SettingsMotion("MotionOut", SettingsLeft) then buildAt = MO.OUT else cfg:Hide() end
	end
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
	-- back from a right-click's settings window: no logo build, everything rises back up
	if back then StartRise() else StartOpening(buildAt) end
end

function SP:ToggleMasterUnlock() self:SetMasterUnlock(not ACTIVE) end

-- Unlock one module's frames only (a "move these" button on its settings page).
function SP:UnlockModuleFrames(key)
	TurnOff(true)   -- (straight into the other unlock: no Done motion)
	self:SetMasterUnlock(true, key)
end

-- a fight ends the mode: protected frames cannot be moved, and the sample content should not sit over combat
do
	local f = CreateFrame("Frame")
	local resume   -- the setup tour's "bring me back", held until the fight is over
	-- no settings window or setup tour popping up as the fight starts
	local function holdReturns()
		SP.unlockReturnToConfig = nil
		if SP.unlockOnDone then
			resume, SP.unlockOnDone = SP.unlockOnDone, nil
			f:RegisterEvent("PLAYER_REGEN_ENABLED")
		end
	end
	local function locked()
		print("|cff0070ddShamanPower|r: Unlock UI closed because combat started. Your new positions are saved."
			.. (resume and " The setup tour comes back when the fight ends." or ""))
	end
	-- a right-click's settings window closed as a fight starts or in it (SettingsClosed):
	-- Unlock UI stays off, as the fight ends the mode
	FightStopsTrip = function()
		holdReturns()
		locked()
	end
	f:RegisterEvent("PLAYER_REGEN_DISABLED")
	f:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_REGEN_ENABLED" then
			f:UnregisterEvent("PLAYER_REGEN_ENABLED")
			local fn = resume
			resume = nil
			if fn then pcall(fn) end
			return
		end
		-- a move finishes at once (Done just pressed: its cleanup, holding what it would bring back)
		if scene == "done" then holdReturns() end
		if scene then FinishScene("combat") end
		-- a trip's settings window: it closes at once in a fight, and Unlock UI does not come
		-- back (stamped: that window may still close in this same moment, see SettingsClosed)
		if backAfterSettings then
			backAfterSettings.fightAt = GetTime()
			SettingsMotion("SetMotionClose", false)
		end
		if ACTIVE then
			holdReturns()
			TurnOff(true)
			locked()
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
			desc = "Shows every ShamanPower element at once - both bars and each enabled module, with sample content - under a blue box you can drag. Most boxes have their own Reset, and the bar at the top has Reset All Positions and Done. Out of combat only; a fight locks everything again. Each module's own lock setting is left as it is. Also: /spunlock",
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
		f:SetPoint("TOP", UIParent, "TOP", 0, 0)   -- flush with the top, as Unlock UI's bar
		f:SetFrameStrata("FULLSCREEN_DIALOG")
		f:EnableMouse(true)
		local bg = f:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints(); bg:SetColorTexture(SP:SPColor("windowBg", 0.94))
		SP:SPMakeBorder(f, "border", 1.5)   -- Unlock UI's bar's look: the soft edge, the elements on top
		TopStripe(f)
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
		if api.MotionIn then pcall(api.MotionIn, api) end   -- every open falls in
		return
	end
	if api.Open then pcall(api.Open, api) end
end
