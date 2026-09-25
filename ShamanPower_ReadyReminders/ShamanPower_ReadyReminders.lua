-- ============================================================================
-- ShamanPower Ready Reminders
-- One placeable icon per spell that appears when the spell is off cooldown
-- (or, in "always" mode, sits there dimmed with a countdown and lights up
-- when ready). Display only: no secure buttons, so the icons may show and
-- hide freely in combat and never fight the client's combat restrictions.
-- Cooldowns are read through SPCompat when it is present, so clients with
-- secret cooldown values still get the addon's shadow model.
-- ============================================================================

local SP = ShamanPower
if not SP then return end
-- Only load for Shamans (the core keeps no-op stubs for everything this module provides)
if select(2, UnitClass("player")) ~= "SHAMAN" then return end
SP.ReadyRemindersLoaded = true   -- the setup tour checks this before borrowing our frames

local GetSpellCooldownC = (SPCompat and SPCompat.GetSpellCooldown) or GetSpellCooldown
local GetSpellInfoC = GetSpellInfo
local GetSpellTextureC = (C_Spell and C_Spell.GetSpellTexture) or GetSpellTexture

-- SavedVariables
ShamanPower_ReadyReminders = ShamanPower_ReadyReminders or {}

local DEFAULTS = {
	-- On for WoW: Forever (no WeakAuras there); opt-in on Anniversary, where most
	-- players already cover this with WeakAuras. The setup tour and settings turn it on.
	enabled = (WOW_PROJECT_ID == WOW_PROJECT_MAINLINE),
	mode = "ready",        -- "ready": show only when ready | "always": dim + countdown on cooldown
	onlyInCombat = false,
	iconSize = 48,
	opacity = 1.0,
	dimOpacity = 0.35,     -- "always" mode, while on cooldown
	desaturate = true,     -- "always" mode, while on cooldown
	sweepStyle = "radial", -- "always" mode: radial | vertical | none
	barStyle = "none",     -- "always" mode: none | below | above  (thin bar draining with the cooldown)
	barHeight = 4,
	barColor = { r = 0.3, g = 0.8, b = 1.0 },
	showCountdown = true,  -- "always" mode
	textPosition = "center", -- center | top | bottom | below | above
	textSize = 0,          -- 0 = automatic from icon size
	readyEffect = "glow",  -- glow | pulse | both | none
	glowColor = { r = 0.3, g = 0.8, b = 1.0 },
	borderColor = { r = 0.2, g = 0.7, b = 1.0 },
	hideBackground = false,
	showNames = false,     -- spell name under each icon
	soundOnReady = false,
	soundName = "Raid Warning",
	soundVolume = 100,
	soundMinCooldown = 20, -- seconds; shorter cooldowns never make a sound
	layout = "row",        -- row | column: arrangement used by Reset Positions
	spacing = 8,
	locked = true,
	spells = {},           -- [key] = true/false (nil = catalog default)
	positions = {},        -- [key] = { point, x, y }
}

-- Catalog. ids: every spell ID the spell has had across clients; the first one
-- the client knows is used. No cooldown lengths here: on a secret-value client
-- the compat shadow model takes each cast's length from the game's own spell
-- data (GetSpellBaseCooldown), then the real one once seen readable.
-- noCooldownIDs: client IDs where the spell has no real cooldown (never shown there).
-- def: on by default. order: default placement (a row, left to right).
SP.ReadyReminderSpells = {
	{ key = "earthshock",   name = "Earth Shock",         ids = { 8042 },                 def = true },
	{ key = "flameshock",   name = "Flame Shock",         ids = { 8050 },                 def = true },
	{ key = "frostshock",   name = "Frost Shock",         ids = { 8056 },                 def = true },
	{ key = "stormstrike",  name = "Stormstrike",         ids = { 17364 },                def = true },
	{ key = "lavaburst",    name = "Lava Burst",          ids = { 408490, 51505 },        def = true },
	{ key = "riptide",      name = "Riptide",             ids = { 408521, 61295 },        def = true },
	{ key = "farseer",      name = "Rage of the Farseer", ids = { 425336 },               def = true },
	{ key = "firenova",     name = "Fire Nova",           ids = { 408341, 1535 },         def = false },
	{ key = "projection",   name = "Totemic Projection",  ids = { 437009 },               def = false },
	{ key = "grounding",    name = "Grounding Totem",     ids = { 8177 },                 def = false },
	{ key = "watershield",  name = "Water Shield",        ids = { 24398, 408510, 52127 }, def = false, noCooldownIDs = { [24398] = true } },
	{ key = "ns",           name = "Nature's Swiftness",  ids = { 16188 },                def = false },
	{ key = "manatide",     name = "Mana Tide Totem",     ids = { 16190 },                def = false },
	{ key = "shamrage",     name = "Shamanistic Rage",    ids = { 30823 },                def = false },
	{ key = "elemastery",   name = "Elemental Mastery",   ids = { 16166 },                def = false },
	{ key = "earthbind",    name = "Earthbind Totem",     ids = { 2484 },                 def = false },
}

local frames = {}
SP.readyReminderFrames = frames   -- read by the setup tour's preview
local catalogByKey = {}
for i, e in ipairs(SP.ReadyReminderSpells) do e.order = i; catalogByKey[e.key] = e end

local function SV()
	local sv = ShamanPower_ReadyReminders
	for k, v in pairs(DEFAULTS) do
		if sv[k] == nil then
			if type(v) == "table" then
				local t = {}
				for kk, vv in pairs(v) do t[kk] = vv end
				sv[k] = t
			else
				sv[k] = v
			end
		end
	end
	-- older saved setting
	if sv.showGlow == false and sv.readyEffect == "glow" then sv.readyEffect = "none"; sv.showGlow = nil end
	return sv
end

local function color(c, dr, dg, db)
	if type(c) == "table" then return c.r or dr, c.g or dg, c.b or db end
	return dr, dg, db
end

local function spellOn(entry)
	local v = SV().spells[entry.key]
	if v == nil then return entry.def end
	return v
end

-- The spell ID this client has for the entry (client data, not the spellbook).
local function clientSpellID(entry)
	if entry.clientID ~= nil then return entry.clientID or nil end
	-- SPCompat.SpellExists, not a name lookup: this client ships encrypted
	-- spell names, so GetSpellInfo returns nil for live spells such as
	-- Elemental Mastery 16166 and the entry would be written off as absent.
	for _, id in ipairs(entry.ids) do
		if SPCompat and SPCompat.SpellExists and SPCompat.SpellExists(id) then entry.clientID = id; return id end
	end
	entry.clientID = false
	return nil
end

-- Usable on this client: exists in the data and has a real cooldown here.
local function usable(entry)
	local id = clientSpellID(entry)
	if not id then return false end
	if entry.noCooldownIDs and entry.noCooldownIDs[id] then return false end
	return true
end
SP.ReadyReminderUsable = usable
SP.ReadyReminderOn = spellOn

-- Does the player know the spell (any rank)? Cached until SPELLS_CHANGED.
local knownCache = {}
local function playerKnows(entry)
	local c = knownCache[entry.key]
	if c ~= nil then return c end
	local id = clientSpellID(entry)
	local known = false
	if id then
		if IsPlayerSpell then known = IsPlayerSpell(id) and true or false end
		if not known and IsSpellKnown then known = IsSpellKnown(id) and true or false end
		if not known then
			-- name lookup resolves only spells in the spellbook, any rank
			local name = GetSpellInfoC(id)
			if name and GetSpellInfoC(name) then known = true end
		end
	end
	knownCache[entry.key] = known
	return known
end

local GCD_MAX = 1.6   -- a "cooldown" this short is only the global cooldown

-- start, duration (plain numbers) for the highest known rank, or nil when unreadable.
local function ownCooldownOf(entry)
	local id = clientSpellID(entry)
	if not id then return nil end
	local name = GetSpellInfoC(id)
	local start, duration = GetSpellCooldownC(name or id)
	if type(start) ~= "number" or type(duration) ~= "number" then return nil end
	return start, duration
end

-- Earth, Flame and Frost Shock share one cooldown (category 19 in the spell data).
-- WoW: Forever in combat: the compat model knows only the shock that was cast, so
-- the other two read ready while the shared cooldown runs. A shock with no run of
-- its own takes the family's.
local IS_MAINLINE = (WOW_PROJECT_ID == WOW_PROJECT_MAINLINE)
local SHOCK_FAMILY = { "earthshock", "flameshock", "frostshock" }
local isShock = { earthshock = true, flameshock = true, frostshock = true }
local function cooldownOf(entry)
	local start, duration = ownCooldownOf(entry)
	if IS_MAINLINE and isShock[entry.key] and not (duration and duration > GCD_MAX) then
		for _, key in ipairs(SHOCK_FAMILY) do
			local other = catalogByKey[key]
			if other and other ~= entry then
				local s, d = ownCooldownOf(other)
				if s and d and d > GCD_MAX and not (duration and duration > GCD_MAX and start + duration >= s + d) then
					start, duration = s, d
				end
			end
		end
	end
	return start, duration
end

-- ---------------------------------------------------------------------------
-- Frames
-- ---------------------------------------------------------------------------
local function defaultPos(entry)
	local sv = SV()
	local size, gap = sv.iconSize or 48, sv.spacing or 8
	local n = #SP.ReadyReminderSpells
	local off = (entry.order - (n + 1) / 2) * (size + gap)
	if sv.layout == "column" then return { point = "CENTER", x = 260, y = -off } end
	return { point = "CENTER", x = off, y = -140 }
end

local function savePos(frame)
	local point, _, _, x, y = frame:GetPoint()
	SV().positions[frame.entry.key] = { point = point, x = x, y = y }
end

local function applyPos(frame)
	local pos = SV().positions[frame.entry.key] or defaultPos(frame.entry)
	frame:ClearAllPoints()
	frame:SetPoint(pos.point or "CENTER", UIParent, pos.point or "CENTER", pos.x or 0, pos.y or 0)
end

function SP:CreateReadyReminderFrame(entry)
	if frames[entry.key] then return frames[entry.key] end
	local sv = SV()
	local size = sv.iconSize or 48
	local f = CreateFrame("Button", "ShamanPowerReady_" .. entry.key, UIParent, "BackdropTemplate")
	f:SetSize(size, size)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:SetClampedToScreen(true)
	f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	f.entry = entry
	applyPos(f)

	local bg = f:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.6)
	f.bg = bg
	local icon = f:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("TOPLEFT", 2, -2); icon:SetPoint("BOTTOMRIGHT", -2, 2)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	f.icon = icon
	local border = CreateFrame("Frame", nil, f, "BackdropTemplate")
	border:SetPoint("TOPLEFT", -2, 2); border:SetPoint("BOTTOMRIGHT", 2, -2)
	border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
	border:SetBackdropBorderColor(0.2, 0.7, 1.0, 1)
	f.border = border
	-- cooldown sweep for "always" mode (plain numbers only; SetCooldown takes secret values too)
	local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
	cd:SetAllPoints(icon)
	cd:SetDrawEdge(false)
	cd:SetHideCountdownNumbers(true)
	if cd.SetIgnoreParentAlpha then cd:SetIgnoreParentAlpha(true) end   -- its countdown stays readable while the icon dims
	cd:Hide()
	f.cooldown = cd
	-- vertical sweep: a grey sheet over the top part of the icon, shrinking as the cooldown ends
	local overlay = f:CreateTexture(nil, "ARTWORK", nil, 2)
	overlay:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0); overlay:SetPoint("TOPRIGHT", icon, "TOPRIGHT", 0, 0)
	overlay:SetHeight(1); overlay:SetColorTexture(0, 0, 0, 0.65); overlay:Hide()
	f.overlay = overlay
	-- thin bar draining with the cooldown (below or above the icon)
	local bar = CreateFrame("StatusBar", nil, f)
	SP:SetSPStatusBarTexture(bar, "other", "Interface\\Buttons\\WHITE8X8")
	bar:SetMinMaxValues(0, 1); bar:SetValue(1); bar:Hide()
	if bar.SetIgnoreParentAlpha then bar:SetIgnoreParentAlpha(true) end   -- the dim is for the icon, not the bar
	local barBg = bar:CreateTexture(nil, "BACKGROUND"); barBg:SetAllPoints(bar); barBg:SetColorTexture(0, 0, 0, 0.6)
	f.bar = bar
	local count = f:CreateFontString(nil, "OVERLAY")
	SP:SetSPFont(count, "alerts", math.max(10, math.floor(size * 0.34)), "OUTLINE")
	count:SetPoint("CENTER", f, "CENTER", 0, 0)
	count:SetTextColor(1, 1, 1)
	if count.SetIgnoreParentAlpha then count:SetIgnoreParentAlpha(true) end   -- the dim is for the icon, not the number
	f.count = count
	local glow = f:CreateTexture(nil, "OVERLAY", nil, 1)
	glow:SetPoint("TOPLEFT", -10, 10); glow:SetPoint("BOTTOMRIGHT", 10, -10)
	glow:SetTexture("Interface\\SpellActivationOverlay\\IconAlert")
	glow:SetTexCoord(0.00781250, 0.50781250, 0.27734375, 0.52734375)
	glow:SetBlendMode("ADD"); glow:SetVertexColor(0.3, 0.8, 1.0); glow:SetAlpha(0)
	f.glow = glow
	local ag = glow:CreateAnimationGroup(); ag:SetLooping("REPEAT")
	local a1 = ag:CreateAnimation("Alpha"); a1:SetFromAlpha(0.15); a1:SetToAlpha(0.8); a1:SetDuration(0.5); a1:SetOrder(1)
	local a2 = ag:CreateAnimation("Alpha"); a2:SetFromAlpha(0.8); a2:SetToAlpha(0.15); a2:SetDuration(0.5); a2:SetOrder(2)
	f.glowAnim = ag
	-- pulse: the whole icon breathes
	local pg = f:CreateAnimationGroup(); pg:SetLooping("REPEAT")
	local p1 = pg:CreateAnimation("Scale"); p1:SetScale(1.12, 1.12); p1:SetDuration(0.45); p1:SetOrder(1)
	local p2 = pg:CreateAnimation("Scale"); p2:SetScale(1 / 1.12, 1 / 1.12); p2:SetDuration(0.45); p2:SetOrder(2)
	f.pulseAnim = pg
	local label = f:CreateFontString(nil, "OVERLAY")
	SP:SetSPFont(label, "alerts", 11, "OUTLINE")
	label:SetPoint("TOP", f, "BOTTOM", 0, -3)
	label:SetText(entry.name); label:SetTextColor(1, 0.82, 0)
	label:Hide()
	f.label = label

	f:SetScript("OnMouseDown", function(self, button)
		-- icons move only while positions are unlocked
		if button == "LeftButton" and SP.readyPositioning then
			self:StartMoving(); self.isMoving = true
		end
	end)
	f:SetScript("OnMouseUp", function(self)
		if self.isMoving then self:StopMovingOrSizing(); self.isMoving = false; savePos(self) end
	end)
	f:SetScript("OnClick", function(self, button)
		if button == "RightButton" and ShamanPowerConfig then ShamanPowerConfig:Open({ "fluffy", "readyreminders_section" }) end
	end)
	f:SetScript("OnEnter", function(self)
		if not (SP.opt and SP.opt.ShowTooltips) then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(self.entry.name .. " ready", 0.3, 0.8, 1.0)
		if SP.readyPositioning then GameTooltip:AddLine("Drag to move | Right-click for options", 0.5, 0.5, 0.5) end
		GameTooltip:Show()
	end)
	f:SetScript("OnLeave", function() GameTooltip:Hide() end)
	f:Hide()
	frames[entry.key] = f
	self:UpdateReadyReminderAppearance(entry.key)   -- styles the engine string too
	return f
end

local styleEngine   -- defined with the engine helpers below; used by the appearance update

function SP:UpdateReadyReminderAppearance(key)
	local f = frames[key]; if not f then return end
	local sv = SV()
	local size = sv.iconSize or 48
	f:SetSize(size, size)
	-- countdown text: size and position
	local ts = (sv.textSize and sv.textSize > 0) and sv.textSize or math.max(10, math.floor(size * 0.34))
	SP:SetSPFont(f.count, "alerts", ts, "OUTLINE")
	f.count:ClearAllPoints()
	local tp = sv.textPosition or "center"
	if tp == "top" then f.count:SetPoint("TOP", f, "TOP", 0, -2)
	elseif tp == "bottom" then f.count:SetPoint("BOTTOM", f, "BOTTOM", 0, 2)
	elseif tp == "below" then f.count:SetPoint("TOP", f, "BOTTOM", 0, -2)
	elseif tp == "above" then f.count:SetPoint("BOTTOM", f, "TOP", 0, 2)
	else f.count:SetPoint("CENTER", f, "CENTER", 0, 0) end
	-- name goes under the text when the text is below the icon
	f.label:ClearAllPoints()
	if tp == "below" then f.label:SetPoint("TOP", f.count, "BOTTOM", 0, -1) else f.label:SetPoint("TOP", f, "BOTTOM", 0, -3) end
	f.bg:SetShown(not sv.hideBackground); f.border:SetShown(not sv.hideBackground)
	f.border:SetBackdropBorderColor(color(sv.borderColor, 0.2, 0.7, 1.0))
	f.glow:SetVertexColor(color(sv.glowColor, 0.3, 0.8, 1.0))
	f.label:SetShown(sv.showNames == true)
	-- bar placement
	local bh = sv.barHeight or 4
	f.bar:ClearAllPoints(); f.bar:SetHeight(bh)
	if sv.barStyle == "above" then
		f.bar:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, 2); f.bar:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 0, 2)
	else
		f.bar:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -2); f.bar:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, -2)
	end
	f.bar:SetStatusBarColor(color(sv.barColor, 0.3, 0.8, 1.0))
	if sv.barStyle == "above" and sv.showNames then f.label:ClearAllPoints(); f.label:SetPoint("TOP", f, "BOTTOM", 0, -3) end
	local id = clientSpellID(f.entry)
	local tex = id and GetSpellTextureC(id)
	f.icon:SetTexture(tex or 136024)
	f:SetAlpha(sv.opacity or 1)
	applyPos(f)
	styleEngine(f)
end

function SP:UpdateAllReadyReminderAppearance()
	for key, f in pairs(frames) do self:UpdateReadyReminderAppearance(key); applyPos(f) end   -- positions too: an import replaces them
end

-- ---------------------------------------------------------------------------
-- Tick
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- WoW: Forever: in combat the addon cannot read a cooldown, so "is it ready"
-- comes from our own estimate (cast time + learned length). The game can still
-- judge the REAL cooldown for us: a curve evaluated on the spell's duration
-- object gives an alpha (possibly a hidden value) that goes straight to
-- SetAlpha, never compared in Lua. Used for the one thing a curve can do here:
-- the icon's opacity at the moment the real cooldown ends. The ready sound,
-- glow and pulse still follow the estimate (Lua has to decide those).
-- One curve per (ready alpha, cooling alpha) pair, made once.
-- ---------------------------------------------------------------------------
local readyCurves = {}
local function readyCurve(readyA, coolingA)
	if not (C_CurveUtil and C_CurveUtil.CreateCurve) then return nil end
	local row = readyCurves[readyA]
	if not row then row = {}; readyCurves[readyA] = row end
	local c = row[coolingA]
	if c == nil then
		local ok, made = pcall(C_CurveUtil.CreateCurve)
		c = ok and made or false
		if c then
			if c.SetType and Enum and Enum.LuaCurveType and Enum.LuaCurveType.Linear then pcall(c.SetType, c, Enum.LuaCurveType.Linear) end
			-- remaining 0 (run out, or an expired duration that lingers): ready; from 0.05 s up: cooling
			if not (pcall(c.AddPoint, c, 0, readyA) and pcall(c.AddPoint, c, 0.05, coolingA)) then c = false end
		end
		row[coolingA] = c
	end
	return c or nil
end

-- The icon's alpha from the real cooldown; false when the game gave nothing usable.
local function curveAlpha(f, d, readyA, coolingA)
	local c = d and d.EvaluateRemainingDuration and readyCurve(readyA, coolingA)
	if not c then return false end
	local ok, a = pcall(d.EvaluateRemainingDuration, d, c)
	if not ok then return false end
	return pcall(f.SetAlpha, f, a)   -- a may be secret: handed over, never looked at
end

-- "Only when ready" keeps a cooling icon on screen at alpha 0 so the curve can
-- show it the moment the real cooldown ends; it must not catch clicks then.
local function curveMouseOff(f)
	if not f.mouseByCurve and f:IsMouseEnabled() then f:EnableMouse(false); f.mouseByCurve = true end
end
local function curveMouseBack(f)
	if f.mouseByCurve then f:EnableMouse(true); f.mouseByCurve = nil end
end

-- The curve is evaluated once per pass, so on its own the icon would light up
-- on the next 0.2 s pass after the real cooldown ends. A Cooldown widget that
-- draws nothing carries the same duration object; the game fires its
-- OnCooldownDone when the real cooldown ends and a pass runs on the next frame.
-- That signal is the game's, not a value read, so "only when ready" also gives
-- the icon its mouse back there (f.realDone) instead of when our estimate ends.
-- If a client never fires it for this watch, nothing breaks: the icon lights
-- on the next pass, and the mouse comes back when our estimate ends.
local passQueued = false
local function passNow()
	passQueued = false
	SP:UpdateReadyReminders()
end
local function onRealCooldownDone(watch)
	local f = watch:GetParent()
	if f then f.realDone = true; curveMouseBack(f) end
	if not passQueued then passQueued = true; C_Timer.After(0, passNow) end
end
local function watchRealEnd(f, d)
	local w = f.endWatch
	if w == nil then
		local ok, made = pcall(CreateFrame, "Cooldown", nil, f)
		w = ok and made or false
		if w then
			w.noCooldownCount = true   -- OmniCC and the like: not a cooldown to draw on
			w:SetSize(1, 1); w:SetPoint("CENTER", f, "CENTER", 0, 0)
			pcall(w.SetDrawSwipe, w, false); pcall(w.SetDrawEdge, w, false); pcall(w.SetDrawBling, w, false)
			pcall(w.SetHideCountdownNumbers, w, true)
			w:SetScript("OnCooldownDone", onRealCooldownDone)
		end
		f.endWatch = w
	end
	if not w then return end
	if not w:IsShown() then w:Show() end
	pcall(w.SetCooldownFromDurationObject, w, d, true)
end

local function stopEffects(f)
	if f.glowShown then f.glow:Hide(); f.glowAnim:Stop(); f.glowShown = nil end
	if f.pulsing then f.pulseAnim:Stop(); f.pulsing = nil end
end

local function setReady(f, ready)
	local sv = SV()
	if ready then
		f.icon:SetDesaturated(false)
		f.cooldown:Hide(); f.overlay:Hide(); f.bar:Hide(); f.count:SetText(""); f.countShown = nil
		f.ecdOn, f.ecdDur, f.readyDur, f.readyDurStart, f.realDone = nil, nil, nil, nil, nil
		curveMouseBack(f)
		if f.engineSheet then f.engineSheet:Hide() end
		f:SetAlpha(sv.opacity or 1)
		local fx = sv.readyEffect or "glow"
		if (fx == "glow" or fx == "both") then
			if not f.glowShown then f.glow:Show(); f.glowAnim:Play(); f.glowShown = true end
		elseif f.glowShown then f.glow:Hide(); f.glowAnim:Stop(); f.glowShown = nil end
		if (fx == "pulse" or fx == "both") then
			if not f.pulsing then f.pulseAnim:Play(); f.pulsing = true end
		elseif f.pulsing then f.pulseAnim:Stop(); f.pulsing = nil end
	else
		f.icon:SetDesaturated(sv.desaturate ~= false)
		f:SetAlpha(sv.dimOpacity or 0.35)
		stopEffects(f)
	end
end

local function readySound(entry, duration)
	local sv = SV()
	if not sv.soundOnReady then return end
	if (duration or 0) < (sv.soundMinCooldown or 20) then return end
	if SP.PlaySoundWithVolume and SP.GetSoundFile then
		SP:PlaySoundWithVolume(SP:GetSoundFile(sv.soundName or "Raid Warning"), sv.soundVolume or 100, true)
	end
end

-- ---------------------------------------------------------------------------
-- Engine-drawn countdown on the Mainline family (the core's totem buttons
-- do the same): the Cooldown widget draws the sweep and the numbers from a
-- duration object handed over once per cooldown; the vertical sheet and the
-- bar are StatusBars the engine fills. The addon keeps the ready / dim state.
-- The demo's cooldowns are made up, so it stays on the addon's own path.
-- ---------------------------------------------------------------------------
local function engineOn()
	return SP.EngineCooldownsOn and SP:EngineCooldownsOn() or false
end

-- The engine's countdown string takes the addon text's font, colour and place.
styleEngine = function(f)
	if not engineOn() or not f.cooldown then return end
	local sv = SV()
	local cd = f.cooldown
	cd:SetHideCountdownNumbers(sv.showCountdown == false)
	pcall(cd.SetMinimumCountdownDuration, cd, 2000)
	pcall(cd.SetCountdownMillisecondsThreshold, cd, 0)
	cd:SetFrameLevel(f:GetFrameLevel() + 3)   -- above the engine sheet, so the numbers stay readable
	local ok, fs = pcall(cd.GetCountdownFontString, cd)
	if ok and fs then
		local font, size = f.count:GetFont()
		if font then SP:SetSPFont(fs, "alerts", size, "OUTLINE") end   -- same area as f.count, so a font change restyles both
		local r, g, b = f.count:GetTextColor()
		fs:SetTextColor(r or 1, g or 1, b or 1)
		fs:ClearAllPoints()
		local point, rel, relPoint, x, y = f.count:GetPoint(1)
		if point then fs:SetPoint(point, rel or f, relPoint or point, x or 0, y or 0) else fs:SetPoint("CENTER", f, "CENTER", 0, 0) end
	end
	f.ecdOn = nil   -- re-fed with the new look
end

local function drawEngineCooldown(f, sv)
	local style = sv.sweepStyle or "radial"
	local barOn = (sv.barStyle or "none") ~= "none"
	-- a sweep is the dimming: the covered part is the cooldown left, the rest
	-- is the icon coming back in colour. Desaturating as well hides that.
	if style ~= "none" then f.icon:SetDesaturated(false) end
	if f.ecdOn and not f.cdChanged and f.ecdStyle == style and f.ecdBar == barOn then return end
	local id = clientSpellID(f.entry)
	if not id then return end
	local ok, d = pcall(C_Spell.GetSpellCooldownDuration, id, true)   -- true: not the global cooldown
	if not ok or d == nil then return end   -- tried again next pass
	f.ecdOn, f.ecdStyle, f.ecdBar, f.ecdDur, f.cdChanged = true, style, barOn, d, nil
	watchRealEnd(f, d)   -- the curve's switch to full runs when the real cooldown ends
	local cd = f.cooldown
	if f.countShown ~= false then f.countShown = false; f.count:SetText("") end   -- the engine's string counts
	f.overlay:Hide()
	cd:SetDrawSwipe(style == "radial")
	if not cd:IsShown() then cd:Show() end
	pcall(cd.SetCooldownFromDurationObject, cd, d, true)
	local Dir = Enum and Enum.StatusBarTimerDirection or {}
	local Interp = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate
	-- the vertical sheet: an engine-filled bar in place of the addon's overlay
	if style == "vertical" then
		local sheet = f.engineSheet
		if not sheet then
			sheet = CreateFrame("StatusBar", nil, f)
			sheet:SetPoint("TOPLEFT", f.icon, "TOPLEFT", 0, 0)
			sheet:SetPoint("BOTTOMRIGHT", f.icon, "BOTTOMRIGHT", 0, 0)
			sheet:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
			sheet:SetStatusBarColor(0, 0, 0, 0.65)
			sheet:SetOrientation("VERTICAL")
			sheet:SetReverseFill(true)
			if sheet.SetFillStyle then sheet:SetFillStyle("STANDARD") end
			sheet:SetFrameLevel(f:GetFrameLevel() + 1)
			f.engineSheet = sheet
		end
		local okb = pcall(sheet.SetTimerDuration, sheet, d, Interp, Dir.RemainingTime)
		sheet:SetShown(okb and true or false)
	elseif f.engineSheet then
		f.engineSheet:Hide()
	end
	if barOn then
		local okb = pcall(f.bar.SetTimerDuration, f.bar, d, Interp, Dir.RemainingTime)
		f.bar:SetShown(okb and true or false)
	elseif f.bar:IsShown() then
		f.bar:Hide()
	end
end

-- "Always" mode, on cooldown: dim, countdown, sweep, bar.
local function drawCooldown(f, start, duration, remaining)
	local sv = SV()
	setReady(f, false)
	if engineOn() and not SP.readyDemoActive then
		drawEngineCooldown(f, sv)
		-- dim while the REAL cooldown runs, full the moment it ends (the estimate may lag)
		if f.ecdDur then curveAlpha(f, f.ecdDur, sv.opacity or 1, sv.dimOpacity or 0.35) end
		return
	end
	if sv.showCountdown ~= false then
		-- the text only changes once a second (or once a minute): build the string then, not ten times a second
		local shown = remaining >= 60 and -math.floor(remaining / 60) or math.ceil(remaining)
		if f.countShown ~= shown then
			f.countShown = shown
			f.count:SetText(shown < 0 and string.format("%dm", -shown) or string.format("%d", shown))
		end
	elseif f.countShown ~= false then f.countShown = false; f.count:SetText("") end
	local frac = duration > 0 and math.max(0, math.min(1, remaining / duration)) or 0
	local style = sv.sweepStyle or "radial"
	if style == "radial" then
		if not f.cooldown:IsShown() then f.cooldown:Show() end
		if f.cdStart ~= start or f.cdDuration ~= duration then
			f.cooldown:SetCooldown(start, duration); f.cdStart, f.cdDuration = start, duration
		end
		f.overlay:Hide()
	elseif style == "vertical" then
		f.cooldown:Hide()
		f.overlay:SetHeight(math.max(0.5, frac * f.icon:GetHeight()))
		if not f.overlay:IsShown() then f.overlay:Show() end
	else
		f.cooldown:Hide(); f.overlay:Hide()
	end
	if (sv.barStyle or "none") ~= "none" then
		f.bar:SetValue(frac)
		if not f.bar:IsShown() then f.bar:Show() end
	elseif f.bar:IsShown() then f.bar:Hide() end
end

-- The 0.2 s pass and the events that wake it run only while Ready Reminders is
-- on (off is the Anniversary default). Everything that changes the setting (the
-- settings, /spready on|off, the setup tour, an import) calls
-- UpdateReadyReminders, which switches them here. The pass itself never
-- switches the ticker off: it runs inside the core's walk over the active
-- subsystems, and taking an entry out of that list mid-walk breaks the walk.
local wakeFrame   -- made at login with the subsystem
local WAKE_EVENTS = { "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_CHARGES", "SPELLS_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD" }
local ticking = nil
local function setTicking(on)
	if ticking == on or not wakeFrame then return end
	ticking = on
	if on then
		if SP.EnableUpdateSubsystem then SP:EnableUpdateSubsystem("readyReminders") end
		for _, ev in ipairs(WAKE_EVENTS) do pcall(wakeFrame.RegisterEvent, wakeFrame, ev) end
	else
		if SP.DisableUpdateSubsystem then SP:DisableUpdateSubsystem("readyReminders") end
		wakeFrame:UnregisterAllEvents()
	end
end

local function readyPass(self)
	local sv = SV()
	if self.readyPositioning or self.readyDemoActive then return end
	local hideAll = not sv.enabled or self:IsOff() or (sv.onlyInCombat and not InCombatLockdown())
	if hideAll then
		for _, f in pairs(frames) do if f:IsShown() then f:Hide() end; f.wasReady = nil end
		self.readyCooling = false   -- nothing to draw: sleep until an event wakes the ticker
		return
	end
	local now = GetTime()
	local cooling = false   -- anything still counting down? if not, the ticker can sleep (see the subsystem callback)
	for _, entry in ipairs(self.ReadyReminderSpells) do
		local f = frames[entry.key]
		local want = spellOn(entry) and usable(entry) and playerKnows(entry)
		if want then
			if not f then f = self:CreateReadyReminderFrame(entry) end
			local start, duration = cooldownOf(entry)
			local ready, remaining = true, 0
			if start and duration and duration > GCD_MAX then
				remaining = start + duration - now
				ready = remaining <= 0
			end
			if not ready then cooling = true end
			if ready then
				if f.wasReady == false then readySound(entry, f.lastDuration) end
				f.wasReady = true
				if not f:IsShown() then f:Show() end
				setReady(f, true)
			elseif sv.mode == "always" then
				f.wasReady = false; f.lastDuration = duration
				if not f:IsShown() then f:Show() end
				drawCooldown(f, start, duration, remaining)
			else
				f.wasReady = false; f.lastDuration = duration
				stopEffects(f)
				-- Forever: stay on screen, invisible, and let the real cooldown's curve
				-- show the icon when it ends, even if our estimate says it is still cooling
				local curved = false
				if engineOn() and not self.readyDemoActive and C_CurveUtil then
					-- fetch the duration object once per cooldown, and again when the client
					-- says a cooldown changed (see the wake frame)
					if f.readyDurStart ~= start or f.cdChanged then
						if f.readyDurStart ~= start then f.realDone = nil end   -- a new cooldown, not a refetch of this one
						f.readyDurStart, f.cdChanged = start, nil
						local id = clientSpellID(entry)
						local okd, d = pcall(C_Spell.GetSpellCooldownDuration, id, true)
						f.readyDur = okd and d or nil
						if f.readyDur then watchRealEnd(f, f.readyDur) end
					end
					if f.readyDur then
						-- nothing of "always" mode may stay behind: the sweep's numbers and
						-- the bar ignore the icon's alpha (the mode can change mid-cooldown)
						if f.cooldown:IsShown() then f.cooldown:Hide() end
						if f.overlay:IsShown() then f.overlay:Hide() end
						if f.bar:IsShown() then f.bar:Hide() end
						if f.engineSheet and f.engineSheet:IsShown() then f.engineSheet:Hide() end
						if f.countShown ~= nil then f.count:SetText(""); f.countShown = nil end
						f.ecdOn = nil
						if not f.realDone then curveMouseOff(f) end
						if not f:IsShown() then f:Show() end
						curved = curveAlpha(f, f.readyDur, sv.opacity or 1, 0)
					end
				end
				if not curved then
					curveMouseBack(f)
					if f:IsShown() then f:Hide() end
				end
			end
		elseif f and f:IsShown() then
			f:Hide(); f.wasReady = nil
		end
	end
	self.readyCooling = cooling
end

-- fromTick: the subsystem's own pass. A setting found off there (changed
-- without a call to this) switches the ticker off on the next frame, outside
-- the core's walk.
local function tickerOffIfDisabled()
	if not SV().enabled or SP:IsOff() then setTicking(false) end
end
function SP:UpdateReadyReminders(fromTick)
	local on = SV().enabled and not self:IsOff() and true or false   -- off as well while ShamanPower is switched off
	if on or not fromTick then setTicking(on)
	elseif ticking then C_Timer.After(0, tickerOffIfDisabled) end
	readyPass(self)
end

-- ---------------------------------------------------------------------------
-- Positioning / test / reset
-- ---------------------------------------------------------------------------
function SP:ShowAllReadyReminders()
	self.readyPositioning = true
	SV().locked = false
	for _, entry in ipairs(self.ReadyReminderSpells) do
		if spellOn(entry) and usable(entry) then
			local f = self:CreateReadyReminderFrame(entry)
			curveMouseBack(f)   -- draggable again
			stopEffects(f)
			f.cooldown:Hide(); f.overlay:Hide(); f.bar:Hide(); f.count:SetText(""); f.countShown = nil
			f.icon:SetDesaturated(false); f:SetAlpha(SV().opacity or 1)
			f.label:SetShown(SV().showNames == true); f:Show()
		end
	end
	SP:Print("Ready Reminders unlocked: drag the icons where you want them, then /spready lock"
		.. " (or turn off Unlock Position in settings).")
end

function SP:HideAllReadyReminders()
	self.readyPositioning = false
	SV().locked = true
	for _, f in pairs(frames) do f:Hide() end
	self:UpdateReadyReminders()
	if self.SettingsTestDone then self:SettingsTestDone() end
end

function SP:ResetReadyReminderPositions()
	SV().positions = {}
	for _, f in pairs(frames) do applyPos(f) end
	SP:Print("Ready Reminders: positions reset.")
end

-- Setup tour demo: every enabled icon runs a pretend cooldown, staggered, so
-- both looks are on screen: on cooldown (dimmed, counting down) then ready
-- (lit up). Honors the mode: in "only when ready" the icon vanishes while
-- on cooldown, as it does in play.
local DEMO_CD, DEMO_READY = 5, 3
function SP:ReadyRemindersDemo(on)
	if on then
		local wasActive = self.readyDemoActive
		self.readyDemoActive = true
		self:UpdateAllReadyReminderAppearance()
		-- The preview shows every borrowed icon (enabled or not) before calling
		-- this; sorting them right here, in the same frame, means the disabled
		-- ones never get drawn. Waiting for the first tick flashed them all.
		if wasActive then
			if self.readyDemoTick then self.readyDemoTick() end
			return   -- re-entrant: options changed, keep cycling
		end
		local t0 = GetTime()
		if self.readyDemoTicker then self.readyDemoTicker:Cancel() end
		local function tick()
			if not self.readyDemoActive then return end
			local sv = SV()
			local now = GetTime()
			local idx, readyCount, total = 0, 0, 0
			for _, entry in ipairs(self.ReadyReminderSpells) do
				local f = frames[entry.key]
				local want = spellOn(entry) and usable(entry)
				if want then
					if not f then f = self:CreateReadyReminderFrame(entry) end
					idx = idx + 1; total = total + 1
					local cycle = DEMO_CD + DEMO_READY
					local t = (now - t0 + idx * 1.7) % cycle
					if t < DEMO_CD then
						if sv.mode == "always" then
							if not f:IsShown() then f:Show() end
							drawCooldown(f, now - t, DEMO_CD, DEMO_CD - t)
						elseif f:IsShown() then f:Hide(); stopEffects(f) end
					else
						readyCount = readyCount + 1
						if not f:IsShown() then f:Show() end
						setReady(f, true)
					end
				elseif f and f:IsShown() then
					f:Hide()
				end
			end
			-- tell the preview which icons this demo is keeping hidden (see ShamanPowerPreview showFrame)
			for _, fr in pairs(frames) do fr.spDemoHidden = not fr:IsShown() end
			self.readyDemoStatus = total == 0 and "No spells enabled - tick some below."
				or string.format("%d of %d ready - the rest are counting down", readyCount, total)
		end
		self.readyDemoTick = tick
		self.readyDemoTicker = C_Timer.NewTicker(0.1, tick)
		tick()
	else
		self.readyDemoActive = nil
		self.readyDemoTick = nil
		if self.readyDemoTicker then self.readyDemoTicker:Cancel(); self.readyDemoTicker = nil end
		self.readyDemoStatus = nil
		for _, f in pairs(frames) do stopEffects(f); f.cooldown:Hide(); f.overlay:Hide(); f.bar:Hide(); f.count:SetText(""); f.countShown = nil; f.spDemoHidden = nil; f:Hide() end
		self:UpdateReadyReminders()
	end
end

-- The icons that are switched on (and usable on this client): Unlock UI boxes
-- only these, never a row of every reminder the player turned off.
function SP:ReadyReminderEnabledFrames()
	local out = {}
	for _, entry in ipairs(self.ReadyReminderSpells) do
		if spellOn(entry) and usable(entry) then
			out[#out + 1] = frames[entry.key] or self:CreateReadyReminderFrame(entry)
		end
	end
	return out
end

if SP.RegisterPreview then
	local list = {}
	for _, entry in ipairs(SP.ReadyReminderSpells) do
		-- every usable spell's frame is borrowed (so toggling one on during the
		-- step lands inside the preview); the demo shows only the enabled ones
		list[#list + 1] = function()
			if not usable(entry) then return nil end
			local f = frames[entry.key] or SP:CreateReadyReminderFrame(entry)
			-- created after the demo sorted its icons (first mount): a ticked-off spell stays hidden
			if SP.readyDemoActive and not spellOn(entry) then f.spDemoHidden = true end
			return f
		end
	end
	SP:RegisterPreview("readyreminders", { frames = list, demo = "SP:ReadyRemindersDemo", pad = 24,
		pane = { grid = true, columns = 2, maxScale = 2.4 } })   -- settings-window pane only: big icons in a grid
end

-- ---------------------------------------------------------------------------
-- Diagnostics: /spdiag ready
-- ---------------------------------------------------------------------------
function SP:ReadyRemindersDiag()
	local out = { "=== ShamanPower ready reminders probe ===" }
	local sv = SV()
	out[#out + 1] = string.format("enabled=%s mode=%s locked=%s cooldown api=%s", tostring(sv.enabled), tostring(sv.mode), tostring(sv.locked),
		(SPCompat and SPCompat.GetSpellCooldown) and "SPCompat" or "native")
	for _, entry in ipairs(self.ReadyReminderSpells) do
		local id = clientSpellID(entry)
		local start, duration = cooldownOf(entry)
		out[#out + 1] = string.format("%-20s on=%-5s clientID=%-7s known=%-5s cd start=%s dur=%s shown=%s", entry.name, tostring(spellOn(entry)),
			tostring(id), tostring(id and playerKnows(entry)), tostring(start), tostring(duration), tostring(frames[entry.key] and frames[entry.key]:IsShown()))
	end
	return out
end

-- ---------------------------------------------------------------------------
-- Options (injected into the core options table under fluffy)
-- ---------------------------------------------------------------------------
local function InjectOptions()
	local root = SP.options
	if not (root and root.args and root.args.fluffy and root.args.fluffy.args) then return end
	if root.args.fluffy.args.readyreminders_section then return end
	local function refresh() SP:UpdateAllReadyReminderAppearance(); SP:UpdateReadyReminders() end
	local args = {
			desc = { order = 0, type = "description", fontSize = "medium",
				name = "An icon per spell that appears when the spell is off cooldown. Turn on Unlock Position"
					.. " to see every icon and drag it where you want, then turn it off.\n" },
			enabled = { order = 1, type = "toggle", name = "Enable Ready Reminders", width = "full",
				get = function() return SV().enabled end, set = function(_, v) SV().enabled = v; refresh() end },
			mode = { order = 2, type = "select", name = "Show", width = 1.4,
				desc = "Only when ready: the icon appears when the spell is off cooldown. Always: the icon stays on screen with the sweep and countdown while on cooldown. Always, dimmed: the same, but greyed and faded until it is ready.",
				values = { ready = "Only when ready", always_bright = "Always (sweep + countdown)", always = "Always, dimmed while on cooldown" },
				sorting = { "ready", "always_bright", "always" },
				get = function()
					local sv = SV()
					if (sv.mode or "ready") ~= "always" then return "ready" end
					-- "always" split by how the icon looks on cooldown: full colour, or dimmed
					if sv.desaturate == false and (sv.dimOpacity or 0.35) >= 1 then return "always_bright" end
					return "always"
				end,
				set = function(_, v)
					local sv = SV()
					if v == "ready" then
						sv.mode = "ready"
					elseif v == "always_bright" then
						sv.mode = "always"; sv.desaturate = false; sv.dimOpacity = 1
					else
						sv.mode = "always"; sv.desaturate = true
						if (sv.dimOpacity or 0.35) >= 1 then sv.dimOpacity = 0.35 end
					end
					refresh()
				end },
			move = { order = 1.5, type = "execute", name = "Move the Icons", width = 1.2,
				desc = "Unlocks just the reminder icons: drag each box where you want it, then press Done to come back here.",
				hidden = function() return not SP.UnlockModuleFrames end,
				func = function() SP:UnlockModuleFrames("readyreminders") end },
			onlyInCombat = { order = 2.5, type = "toggle", name = "Only In Combat", desc = "Hide every icon while you are out of combat.", width = 1.0,
				get = function() return SV().onlyInCombat == true end, set = function(_, v) SV().onlyInCombat = v; refresh() end },
			unlock = { order = 3, type = "toggle", name = "Unlock Positions", width = 1.0,
				desc = "Shows every enabled icon with settings hidden. Drag them, then press Done to return here.",
				get = function() return SP.readyPositioning == true end,
				set = function(_, v)
					if v then SP:RunWithSettingsHidden(nil, SP.ShowAllReadyReminders, SP.HideAllReadyReminders)
					else SP:HideAllReadyReminders() end
				end },
			reset = { order = 5, type = "execute", name = "Reset Positions",
				desc = "Lays the icons out again in a row or column (see Arrange As).", width = 1.0,
				func = function() SP:ResetReadyReminderPositions() end },
			layout = { order = 5.1, type = "select", name = "Reset Layout", width = 1.0,
				values = { row = "Row", column = "Column" },
				get = function() return SV().layout or "row" end, set = function(_, v) SV().layout = v end },
			spacing = { order = 5.2, type = "range", name = "Reset Spacing", min = 0, max = 40, step = 1, width = 1.0,
				get = function() return SV().spacing or 8 end, set = function(_, v) SV().spacing = v end },

			lookHeader = { order = 6, type = "header", name = "Look" },
			iconSize = { order = 6.1, type = "range", name = "Icon Size", min = 24, max = 96, step = 2, width = 1.2,
				get = function() return SV().iconSize or 48 end, set = function(_, v) SV().iconSize = v; refresh() end },
			opacity = { order = 6.2, type = "range", name = "Opacity", min = 0.2, max = 1, step = 0.05, width = 1.2, isPercent = true,
				get = function() return SV().opacity or 1 end, set = function(_, v) SV().opacity = v; refresh() end },
			hideBackground = { order = 6.3, type = "toggle", name = "Hide Background & Border", width = 1.0,
				get = function() return SV().hideBackground end, set = function(_, v) SV().hideBackground = v; refresh() end },
			borderColor = { order = 6.4, type = "color", name = "Border Color", width = 1.0,
				hidden = function() return SV().hideBackground end,
				get = function() return color(SV().borderColor, 0.2, 0.7, 1.0) end,
				set = function(_, r, g, b) SV().borderColor = { r = r, g = g, b = b }; refresh() end },
			showNames = { order = 6.5, type = "toggle", name = "Show Spell Names", desc = "The spell's name under each icon.", width = 1.0,
				get = function() return SV().showNames == true end, set = function(_, v) SV().showNames = v; refresh() end },

			readyHeader = { order = 7, type = "header", name = "When Ready" },
			readyEffect = { order = 7.1, type = "select", name = "Ready Effect", width = 1.0,
				values = { glow = "Glow", pulse = "Pulse", both = "Glow + pulse", none = "None" },
				get = function() return SV().readyEffect or "glow" end, set = function(_, v) SV().readyEffect = v; refresh() end },
			glowColor = { order = 7.2, type = "color", name = "Glow Color", width = 1.0,
				hidden = function() local fx = SV().readyEffect or "glow"; return fx ~= "glow" and fx ~= "both" end,
				get = function() return color(SV().glowColor, 0.3, 0.8, 1.0) end,
				set = function(_, r, g, b) SV().glowColor = { r = r, g = g, b = b }; refresh() end },
			soundOnReady = { order = 7.3, type = "toggle", name = "Sound When Ready", desc = "Plays once when a spell comes off cooldown. Short cooldowns are skipped (see the minimum).", width = 1.0,
				get = function() return SV().soundOnReady == true end, set = function(_, v) SV().soundOnReady = v end },
			soundName = { order = 7.4, type = "select", name = "Ready Sound", width = "double",
				-- names as labels (the shared-media table maps names to file paths)
				values = function() local t = {} for name in pairs((AceGUIWidgetLSMlists and AceGUIWidgetLSMlists.sound) or {}) do t[name] = name end return t end,
				disabled = function() return not SV().soundOnReady end,
				get = function() return SV().soundName or "Raid Warning" end, set = function(_, v) SV().soundName = v end },
			soundVolume = { order = 7.5, type = "range", name = "Sound Volume", min = 0, max = 100, step = 5, width = 1.0,
				disabled = function() return not SV().soundOnReady end,
				get = function() return SV().soundVolume or 100 end, set = function(_, v) SV().soundVolume = v end },
			soundMinCooldown = { order = 7.6, type = "range", name = "Sound Only For Cooldowns Over (sec)", min = 0, max = 300, step = 5, width = 1.4,
				disabled = function() return not SV().soundOnReady end,
				get = function() return SV().soundMinCooldown or 20 end, set = function(_, v) SV().soundMinCooldown = v end },
			soundTest = { order = 7.7, type = "execute", name = "Test Sound", width = 0.8,
				disabled = function() return not SV().soundOnReady end,
				func = function() if SP.PlaySoundWithVolume then SP:PlaySoundWithVolume(SP:GetSoundFile(SV().soundName or "Raid Warning"), SV().soundVolume or 100, true) end end },

			cdHeader = { order = 8, type = "header", name = "While On Cooldown (Always mode)" },
			cdNote = { order = 8.05, type = "description", name = "These apply when Show is set to Always; in Only-when-ready mode the icon is simply hidden.\n",
				hidden = function() return (SV().mode or "ready") == "always" end },
			dimOpacity = { order = 8.1, type = "range", name = "Opacity While On Cooldown", min = 0.1, max = 1, step = 0.05, width = 1.2, isPercent = true,
				hidden = function() return (SV().mode or "ready") ~= "always" end,
				get = function() return SV().dimOpacity or 0.35 end, set = function(_, v) SV().dimOpacity = v; refresh() end },
			desaturate = { order = 8.2, type = "toggle", name = "Grey Out The Icon", width = 1.0,
				hidden = function() return (SV().mode or "ready") ~= "always" end,
				get = function() return SV().desaturate ~= false end, set = function(_, v) SV().desaturate = v; refresh() end },
			sweepStyle = { order = 8.3, type = "select", name = "Sweep", width = 1.0,
				hidden = function() return (SV().mode or "ready") ~= "always" end,
				values = { radial = "Radial (clock)", vertical = "Vertical (fills up)", none = "None" },
				get = function() return SV().sweepStyle or "radial" end, set = function(_, v) SV().sweepStyle = v; refresh() end },
			barStyle = { order = 8.4, type = "select", name = "Progress Bar", width = 1.0,
				hidden = function() return (SV().mode or "ready") ~= "always" end,
				values = { none = "None", below = "Below the icon", above = "Above the icon" },
				get = function() return SV().barStyle or "none" end, set = function(_, v) SV().barStyle = v; refresh() end },
			barHeight = { order = 8.5, type = "range", name = "Bar Height", min = 2, max = 12, step = 1, width = 1.0,
				hidden = function() return (SV().mode or "ready") ~= "always" or (SV().barStyle or "none") == "none" end,
				get = function() return SV().barHeight or 4 end, set = function(_, v) SV().barHeight = v; refresh() end },
			barColor = { order = 8.6, type = "color", name = "Bar Color", width = 1.0,
				hidden = function() return (SV().mode or "ready") ~= "always" or (SV().barStyle or "none") == "none" end,
				get = function() return color(SV().barColor, 0.3, 0.8, 1.0) end,
				set = function(_, r, g, b) SV().barColor = { r = r, g = g, b = b }; refresh() end },
			showCountdown = { order = 8.7, type = "toggle", name = "Countdown Text", width = 1.0,
				hidden = function() return (SV().mode or "ready") ~= "always" end,
				get = function() return SV().showCountdown ~= false end,
				set = function(_, v) SV().showCountdown = v; if v and SP.EnableCountdownNumbers then SP:EnableCountdownNumbers() end; refresh() end },
			textPosition = { order = 8.8, type = "select", name = "Countdown Position", width = 1.0,
				hidden = function() return (SV().mode or "ready") ~= "always" or SV().showCountdown == false end,
				values = { center = "Center", top = "Top", bottom = "Bottom", below = "Below the icon", above = "Above the icon" },
				get = function() return SV().textPosition or "center" end, set = function(_, v) SV().textPosition = v; refresh() end },
			textSize = { order = 8.9, type = "range", name = "Countdown Size (0 = auto)", min = 0, max = 40, step = 1, width = 1.0,
				hidden = function() return (SV().mode or "ready") ~= "always" or SV().showCountdown == false end,
				get = function() return SV().textSize or 0 end, set = function(_, v) SV().textSize = v; refresh() end },

			spellsHeader = { order = 20, type = "header", name = "Spells" },
			spellsDesc = { order = 21, type = "description", name = "Only spells this client has are listed; an icon only shows once you know the spell.\n" },
	}
	-- the per-spell toggles sit directly in the section (an empty inline group renders as a blank band)
	local spellKeys = { "spellsDesc" }
	for i, entry in ipairs(SP.ReadyReminderSpells) do
		spellKeys[#spellKeys + 1] = "spell_" .. entry.key
		args["spell_" .. entry.key] = {
			order = 22 + i, type = "toggle", name = entry.name, width = 1.2,
			hidden = function() return not usable(entry) end,   -- not in this client's data, or no cooldown here
			get = function() return spellOn(entry) end,
			set = function(_, v) SV().spells[entry.key] = v; refresh() end,
		}
	end
	SP.OrderSettingsBands({ args = args }, {
		{ keys = { "desc" } },
		{ keys = { "enabled", "mode" } },
		{ header = "spellsHeader", name = "Spells", keys = spellKeys },
		{ header = "lookHeader", name = "Look", keys = {
			"iconSize", "opacity", "textSize", "hideBackground", "borderColor", "showNames",
		}, names = { textSize = "Text Size (0 = auto)", hideBackground = "Hide Background" } },
		{ header = "readyHeader", name = "Behavior", keys = { "onlyInCombat", "readyEffect", "glowColor" } },
		{ header = "cdHeader", name = "While On Cooldown", keys = {
			"cdNote", "dimOpacity", "desaturate", "sweepStyle", "barStyle", "barHeight", "barColor",
			"showCountdown", "textPosition",
		} },
		{ header = "soundHeader", name = "Sound", keys = {
			"soundOnReady", "soundName", "soundTest", "soundVolume", "soundMinCooldown",
		}, names = { soundOnReady = "Play Sound", soundName = "Sound", soundVolume = "Volume" } },
		{ header = "positionHeader", name = "Position", keys = { "move", "unlock", "layout", "spacing", "reset" },
			names = { move = "Move", unlock = "Unlock Position", layout = "Arrange As",
				spacing = "Spacing When Arranged", reset = "Reset Position" } },
	})
	args.hideBackground.desc = "Hide the background and border around each reminder icon."
	root.args.fluffy.args.readyreminders_section = { order = 9.5, type = "group", name = "Ready Reminders", args = args }
end

-- ---------------------------------------------------------------------------
-- Slash + events
-- ---------------------------------------------------------------------------
SLASH_SPREADY1 = "/spready"
SlashCmdList["SPREADY"] = function(msg)
	msg = (msg or ""):trim():lower()
	if msg == "show" or msg == "unlock" then SP:ShowAllReadyReminders()
	elseif msg == "hide" or msg == "lock" then SP:HideAllReadyReminders(); SP:Print("Ready Reminders locked.")
	elseif msg == "reset" then SP:ResetReadyReminderPositions()
	elseif msg == "on" then SV().enabled = true; SP:UpdateReadyReminders()
	elseif msg == "off" then SV().enabled = false; SP:UpdateReadyReminders()
	else
		if ShamanPowerConfig then ShamanPowerConfig:Open({ "fluffy", "readyreminders_section" })
		else SP:Print("/spready unlock | lock | reset | on | off") end
	end
end

local ef = CreateFrame("Frame")
if SPCompat and SPCompat.StressRegister then SPCompat.StressRegister(ef, "Ready Reminders") end
ef:RegisterEvent("PLAYER_LOGIN")
ef:RegisterEvent("PLAYER_ENTERING_WORLD")
ef:RegisterEvent("SPELLS_CHANGED")
ef:RegisterEvent("PLAYER_TALENT_UPDATE")
ef:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		SV()
		InjectOptions()
		if SP.RegisterUpdateSubsystem then
			-- Ten passes a second are only needed while something is counting down. With
			-- every spell ready nothing on screen can change until the client says a
			-- cooldown changed, so the ticker sleeps and these events wake it; one pass a
			-- second runs regardless, as a safety net.
			local idleTicks = 0
			-- Five passes a second while something counts down: the number changes once a second, the
			-- radial sweep animates by itself, and a spell coming ready is noticed within 0.2 s. (Ten a
			-- second was this module's whole in-combat cost, measured with /spperf.)
			SP:RegisterUpdateSubsystem("readyReminders", 0.2, function()
				if SP.readyCooling == false and not SP.readyWake then
					idleTicks = idleTicks + 1
					if idleTicks < 5 then return end
				end
				idleTicks = 0
				SP.readyWake = nil
				SP:UpdateReadyReminders(true)
			end)
			local wake = CreateFrame("Frame")   -- its events follow the setting (setTicking)
			if SPCompat and SPCompat.StressRegister then SPCompat.StressRegister(wake, "Ready Reminders (wake)") end
			wake:SetScript("OnEvent", function(_, event)
				SP.readyWake = true
				-- a cooldown can change without its start time changing (reset, haste,
				-- a secret start): fetch the duration object again on the next pass,
				-- in both modes
				if event == "SPELL_UPDATE_COOLDOWN" then
					for _, f in pairs(frames) do f.cdChanged = true end
				end
			end)
			wakeFrame = wake
			setTicking(SV().enabled and not SP:IsOff() and true or false)
		else
			C_Timer.NewTicker(0.1, function() SP:UpdateReadyReminders() end)
		end
	else
		knownCache = {}
		for _, entry in ipairs(SP.ReadyReminderSpells) do entry.clientID = nil end
		SP:UpdateAllReadyReminderAppearance()
	end
end)

-- Enable ShamanPower switched: the same pass a settings change runs (off hides
-- every icon and stops the ticker; on shows what the settings say)
SP:OnOnOff(function() SP:UpdateReadyReminders() end)
