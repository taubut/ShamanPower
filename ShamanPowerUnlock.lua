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
local MODULES = {
	{ key = "shieldcharges", label = "Shield Charges", labels = { "Shield Charges", "Earth Shield Charges" },
		reset = function()
			local s = SP.opt.shieldChargeDisplay
			if not s then return end
			s.playerShieldX, s.playerShieldY, s.earthShieldX, s.earthShieldY = nil, nil, nil, nil
			local f = SP.shieldChargeFrames
			if f and f.player then f.player:ClearAllPoints(); f.player:SetPoint("CENTER", UIParent, "CENTER", -50, -100) end
			if f and f.earth then f.earth:ClearAllPoints(); f.earth:SetPoint("CENTER", UIParent, "CENTER", 50, -100) end
		end },
	{ key = "readyreminders", label = "Ready Reminder", reset = "ResetReadyReminderPositions" },
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
			if SP.opt.coverage and SP.opt.coverage.freeCells then   -- one box per cell
				return { f.buttons[1], f.buttons[2], f.buttons[3], f.buttons[4] }
			end
			return { f }
		end,
		labels = { "Coverage: Earth", "Coverage: Fire", "Coverage: Water", "Coverage: Air" } },
	{ key = "sprange", label = "Totem Range" },
	{ key = "raidcd", label = "Raid Cooldown Callers" },
	{ key = "estracker", label = "Earth Shield Tracker",
		enabled = function()
			if SPCompat and SPCompat.earthShieldExists == false then return false end
			return SP.opt.esTracker and SP.opt.esTracker.enabled and true or false
		end },
}

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
		local b = CreateFrame("Button", nil, mover)
		b:SetSize(38, 14)
		b:SetPoint("BOTTOMRIGHT", mover, "TOPRIGHT", 0, 1)
		local bg = b:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0.05, 0.12, 0.22, 0.95)
		local t = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); t:SetPoint("CENTER"); t:SetText("Reset"); t:SetTextColor(0.55, 0.8, 1)
		b:SetScript("OnEnter", function(self) bg:SetColorTexture(0.1, 0.3, 0.55, 1); GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText("Put this one back where it starts"); GameTooltip:Show() end)
		b:SetScript("OnLeave", function() bg:SetColorTexture(0.05, 0.12, 0.22, 0.95); GameTooltip:Hide() end)
		b:SetScript("OnClick", function(self)
			if InCombatLockdown() or not self.resetFn then return end
			pcall(self.resetFn)
			SP:RefreshUnlockBoxes()
		end)
		mover.spReset = b
	end
	mover.spReset.resetFn = resetFn
	mover.spReset:SetShown(resetFn ~= nil)
end

local function ShowBox(moverKey, frame, label, save, resetFn)
	if not (frame and frame.GetLeft) then return end
	if not frame:IsShown() then forced[frame] = true; frame:Show() end
	if not frame:GetLeft() then return end   -- still not laid out: nothing to put a box on
	SP:ShowBarMover(moverKey, frame, frame, label, function() save(frame) end)
	shown[moverKey] = { frame = frame, label = label, save = save, reset = resetFn }
	AddReset(moverKey, resetFn)
end

function SP:RefreshUnlockBoxes()
	if not ACTIVE or InCombatLockdown() then return end
	for moverKey, e in pairs(shown) do
		if e.bar then
			-- the two bars re-place their own movers
			if moverKey == "totembar" then SP:SetTotemBarUnlocked(true) else SP:SetCooldownBarUnlocked(true) end
		elseif e.frame and e.frame:GetLeft() then
			SP:ShowBarMover(moverKey, e.frame, e.frame, e.label, function() e.save(e.frame) end)
		end
		AddReset(moverKey, e.reset)
	end
end

-- ---------------------------------------------------------------------------
-- The two bars
-- ---------------------------------------------------------------------------
local function ResetTotemBar()
	local h = _G["ShamanPowerFrame"]
	if not h then return end
	h:ClearAllPoints()
	h:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	if SP.SaveFramePosition then SP:SaveFramePosition(h) end
end

local function ResetCooldownBar()
	local bar = SP.cooldownBar
	if not bar then return end
	bar:ClearAllPoints()
	bar:SetPoint("CENTER", UIParent, "CENTER", 0, -50)
	SP.opt.cooldownBarPosition = SP:SavePositionRecord(bar)
	SP.opt.cooldownBarPoint, SP.opt.cooldownBarRelPoint = nil, nil
	SP.opt.cooldownBarPosX, SP.opt.cooldownBarPosY = nil, nil
end

-- ---------------------------------------------------------------------------
-- The bar at the top of the screen
-- ---------------------------------------------------------------------------
StaticPopupDialogs["SHAMANPOWER_UNLOCK_RESET_ALL"] = {
	text = "Put every ShamanPower element back where it starts?\n\nThis resets positions only, not settings.",
	button1 = YES, button2 = NO, whileDead = 1, hideOnEscape = 1, timeout = 0, preferredIndex = 3,
	OnAccept = function() SP:ResetAllUnlockPositions() end,
}

local function EnsureDoneBar()
	if doneBar then return doneBar end
	local f = CreateFrame("Frame", "ShamanPowerUnlockBar", UIParent)
	f:SetSize(560, 46)
	f:SetPoint("TOP", UIParent, "TOP", 0, -70)
	f:SetFrameStrata("FULLSCREEN_DIALOG")
	f:SetFrameLevel(50)
	f:EnableMouse(true)
	local bg = f:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0.04, 0.06, 0.10, 0.94)
	for _, edge in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 2 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 2 }, { "TOPLEFT", "BOTTOMLEFT", 2, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 2, nil } }) do
		local t = f:CreateTexture(nil, "BORDER"); t:SetColorTexture(0.25, 0.66, 1, 1)
		t:SetPoint(edge[1]); t:SetPoint(edge[2])
		if edge[3] then t:SetWidth(edge[3]) else t:SetHeight(edge[4]) end
	end
	local text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	text:SetPoint("LEFT", f, "LEFT", 14, 0)
	text:SetText("Drag any blue box. Each has its own Reset.")
	local done = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	done:SetSize(84, 24); done:SetPoint("RIGHT", f, "RIGHT", -10, 0); done:SetText("Done")
	done:SetScript("OnClick", function() SP:SetMasterUnlock(false) end)
	local all = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	all:SetSize(150, 24); all:SetPoint("RIGHT", done, "LEFT", -8, 0); all:SetText("Reset All Positions")
	all:SetScript("OnClick", function() StaticPopup_Show("SHAMANPOWER_UNLOCK_RESET_ALL") end)
	f:Hide()
	doneBar = f
	return f
end

function SP:ResetAllUnlockPositions()
	if InCombatLockdown() then return end
	for _, e in pairs(shown) do
		if e.reset then pcall(e.reset) end
	end
	self:RefreshUnlockBoxes()
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
		print("|cffff0000ShamanPower:|r the UI cannot be unlocked in combat.")
		return
	end

	if not on then
		ACTIVE = false
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
		if self.unlockReturnToConfig then
			self.unlockReturnToConfig = nil
			local cfg = rawget(_G, "ShamanPowerConfig")
			if cfg and cfg.Open then pcall(cfg.Open, cfg) end
		end
		return
	end

	ACTIVE = true
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
	end
	if isShaman and self.cooldownBar and self.opt.showCooldownBar and self.SetCooldownBarUnlocked then
		self:SetCooldownBarUnlocked(true)
		shown.cooldownbar = { bar = true, reset = ResetCooldownBar }
		AddReset("cooldownbar", ResetCooldownBar)
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
				if ok then demos[m.key] = true else print("|cffff4040ShamanPower|r: could not preview " .. m.label .. ": " .. tostring(err)) end
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
				local label = (m.labels and m.labels[i]) or (#frames > 1 and (m.label .. " " .. i) or m.label)
				ShowBox("unlock_" .. m.key .. "_" .. i, frame, label, m.save or SaveThroughOwnScripts, resetFn)
			end
		end
	end

	EnsureDoneBar():Show()
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
	f:RegisterEvent("PLAYER_REGEN_DISABLED")
	f:SetScript("OnEvent", function()
		if ACTIVE then
			SP:SetMasterUnlock(false)
			print("|cff0070ddShamanPower|r: UI locked again (combat). Positions you had already moved are saved.")
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
