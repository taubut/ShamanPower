-- ============================================================================
-- ShamanPower [Windfury Proc] (3.0.9.17, WoW: Forever only; asked on both Discords, mockup A111)
-- An alert on your screen each time Windfury procs on you: your weapon's Windfury Weapon or a Windfury Totem.
-- It shows for a moment (Time On Screen, from each proc) with its glow, and plays its sound. Its own module:
-- its own settings (ShamanPowerWindfuryProcDB), its own page (Alerts & Reminders > Windfury Proc), its own
-- font (Appearance > Fonts & Textures > Windfury Proc).
--
-- A proc is seen by its own spell ID: WoW: Forever names the spell in SPELL_UPDATE_COOLDOWN, a proc's own
-- spell too (the owner's test on a dummy, 11-17: 10610 Windfury Totem, 439440 Windfury Weapon). Casting
-- Windfury Weapon or dropping Windfury Totem has IDs of its own and never shows it. A hidden ID is never read.
-- ============================================================================

local SP = ShamanPower
if not SP then return end
if not (SPCompat and SPCompat.FOREVER) then return end   -- (WoW: Forever only)
SP.WindfuryProcLoaded = true

-- the procs' own spell IDs (WoW: Forever's spell data: each is a melee strike of its own, with no cast and no
-- cooldown). Seen in the owner's test: 439440 (Windfury Weapon) and 10610 (Windfury Totem, its top rank).
local WEAPON = { [439440] = true, [439441] = true, [8233] = true, [8236] = true, [10484] = true, [16361] = true, [16363] = true }
local TOTEM = { [8516] = true, [10608] = true, [10610] = true }
-- the icons: Windfury Weapon's and Windfury Totem's own (WoW: Forever's spell data, SpellMisc)
local ICON = { weapon = 136018, totem = 136114 }
local ICON_SPELL = { weapon = 8232, totem = 8512 }
local WORD = "WINDFURY!"
local SOUND_GAP = 1.0   -- at most one sound a second (a proc the game reports twice plays it once)
local GLOW_KEY = "windfury"
-- Windfury Weapon's internal cooldown: it cannot proc again for 1.5 seconds (WoW: Forever's spell data: every rank's
-- enchant equips 439431, whose proc has ProcCategoryRecovery 1500 ms, 20% chance). Windfury Totem has none (its
-- enchants' 20% chance on each hit, no recovery).
local WEAPON_ICD = 1.5

local defaults = {
	enabled = false,
	weapon = true,           -- Windfury Weapon Procs
	totem = true,            -- Windfury Totem Procs
	showICD = true,          -- Show Internal Cooldown (on Windfury Weapon's icon until it can proc again), and its look:
	icdSweep = "radial",     --   Sweep: "radial" (Clock Sweep), "vertical" (Color Fills In), "none"
	icdSweepDirection = "bottom",   -- Color Fills In: the color comes back from "bottom" or "top"
	icdBar = "none",         --   Progress Bar: "none", "below", "above" (the icon)
	icdBarHeight = 4,
	icdBarColor = { r = 0.3, g = 0.8, b = 1.0 },
	icdGray = false,         --   Gray Out The Icon while it can't proc
	icdCountdown = true,     --   Show Countdown (the seconds left, 1.2)
	icdCountdownPosition = "center",   -- "center", "top", "bottom", "below", "above"
	icdCountdownSize = 0,    --   0: sized to the icon
	icdCountdownColors = false,   -- Countdown Colors: Appearance's Cooldown Numbers colors (else white)
	showTime = 1.5,          -- Time On Screen (seconds, from each proc)
	displayMode = "icon",    -- "icon", "both" (Icon + Text), "text"
	iconSize = 64,
	opacity = 1,
	textSize = 24,
	showGlow = true,
	glowColor = { r = 1, g = 0.8, b = 0 },   -- WoW's gold
	-- glowShape: "default" (Square), "round", "proc" (Proc Glow); nil = Appearance > Themes' Glow Shape
	-- glowThick: Proc Glow's thickness (0 to 0.6 of the icon); nil = the shared Proc Glow Thickness
	playSound = true,
	soundName = "Raid Warning",
	soundVolume = 100,
	position = { point = "CENTER", x = 0, y = 250 },   -- (above the alerts at 150)
}
-- the support code (/sp support) reports only what differs from these
if SP.SUPPORT_MODULE_DEFAULTS then SP.SUPPORT_MODULE_DEFAULTS.ShamanPowerWindfuryProcDB = defaults end
SP.WindfuryProcDefaults = defaults

local W = { gen = 0 }   -- gen: each proc's own hide; soundAt: the last sound; shown: up now; demo: the preview's loop
local frame

local function DB()
	local sv = ShamanPowerWindfuryProcDB
	if type(sv) ~= "table" then return nil end
	for k, v in pairs(defaults) do
		if sv[k] == nil then
			if type(v) == "table" then
				local t = {}
				for k2, v2 in pairs(v) do t[k2] = v2 end
				sv[k] = t
			else
				sv[k] = v
			end
		end
	end
	return sv
end

local function iconFor(which)
	local id = ICON_SPELL[which] or ICON_SPELL.weapon
	local t = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)
	if t and not (issecretvalue and issecretvalue(t)) then return t end
	return ICON[which] or ICON.weapon
end

local function place()
	local sv = DB()
	if not (frame and sv) then return end
	local p = sv.position or defaults.position
	frame:ClearAllPoints()
	frame:SetPoint(p.point or "CENTER", UIParent, p.point or "CENTER", p.x or 0, p.y or 250)
end

-- its Glow Shape: its own pick (Square, Round, Proc Glow), else Appearance > Themes' Glow Shape, as a Ready
-- Reminder icon's is
local function shapeOf(sv) return sv.glowShape or (SP.opt and SP.opt.glowShape) or "default" end

local function glowOn()
	local sv = DB()
	if not (frame and sv) then return end
	if sv.showGlow and (sv.displayMode or "icon") ~= "text" then
		local c = sv.glowColor or defaults.glowColor
		local r, g, b = c.r or 1, c.g or 0.8, c.b or 0
		if shapeOf(sv) == "proc" and SP.ProcGlow_Start and SP.ProcGlowOptions then
			-- Proc Glow: the ring, in its Glow Color (white: the game's gold) at its Glow Thickness
			frame.pulse:Stop()
			frame.glow:Hide()
			local col = { r, g, b, 1 }
			if r > 0.98 and g > 0.98 and b > 0.98 then col = nil end
			SP.ProcGlow_Stop(frame, GLOW_KEY)
			SP.ProcGlow_Start(frame, SP:ProcGlowOptions(frame, col, GLOW_KEY, false, sv.glowThick))
		else
			-- Square or Round: the glow round the icon, breathing
			if SP.ProcGlow_Stop then SP.ProcGlow_Stop(frame, GLOW_KEY) end
			if SP.PaintGlowShape then SP:PaintGlowShape(frame.glow, shapeOf(sv)) end
			frame.glow:SetVertexColor(r, g, b)
			frame.glow:Show()
			frame.pulse:Play()
		end
	else
		frame.pulse:Stop()
		frame.glow:Hide()
		if SP.ProcGlow_Stop then SP.ProcGlow_Stop(frame, GLOW_KEY) end
	end
end

local function glowOff()
	if not frame then return end
	frame.pulse:Stop()
	frame.glow:Hide()
	if SP.ProcGlow_Stop then SP.ProcGlow_Stop(frame, GLOW_KEY) end
end

-- its look from the settings: size, opacity, what it shows, the word's font and size, the glow
local function look()
	local sv = DB()
	if not (frame and sv) then return end
	local size = sv.iconSize or 64
	frame:SetSize(size, size)
	frame:SetAlpha(sv.opacity or 1)
	local mode = sv.displayMode or "icon"
	frame.icon:SetShown(mode ~= "text")
	frame.text:SetShown(mode ~= "icon")
	-- the internal cooldown's parts, placed by their settings (the same places whether or not it runs, so the word
	-- under the icon never jumps)
	local icd = sv.showICD ~= false and sv.weapon ~= false
	local barAt = icd and sv.icdBar or "none"
	local countAt = icd and sv.icdCountdown ~= false and (sv.icdCountdownPosition or "center") or nil
	frame.sheet:ClearAllPoints()
	if sv.icdSweepDirection == "top" then   -- (the color comes back from the top: the sheet leaves toward the bottom)
		frame.sheet:SetPoint("BOTTOMLEFT", frame.icon, "BOTTOMLEFT", 0, 0); frame.sheet:SetPoint("BOTTOMRIGHT", frame.icon, "BOTTOMRIGHT", 0, 0)
	else
		frame.sheet:SetPoint("TOPLEFT", frame.icon, "TOPLEFT", 0, 0); frame.sheet:SetPoint("TOPRIGHT", frame.icon, "TOPRIGHT", 0, 0)
	end
	frame.bar:ClearAllPoints()
	frame.bar:SetHeight(sv.icdBarHeight or 4)
	if barAt == "above" then
		frame.bar:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 2); frame.bar:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0, 2)
	else
		frame.bar:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -2); frame.bar:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 0, -2)
	end
	local bc = sv.icdBarColor or defaults.icdBarColor
	frame.bar:SetStatusBarColor(bc.r or 0.3, bc.g or 0.8, bc.b or 1.0)
	local cs = sv.icdCountdownSize
	SP:SetSPFont(frame.count, "windfury", (cs and cs > 0) and cs or math.max(10, math.floor(size * 0.34)), "OUTLINE")
	frame.count:ClearAllPoints()
	local under = (barAt == "below") and frame.bar or frame   -- (what sits lowest under the icon so far)
	local over = (barAt == "above") and frame.bar or frame
	if countAt == "top" then frame.count:SetPoint("TOP", frame, "TOP", 0, -2)
	elseif countAt == "bottom" then frame.count:SetPoint("BOTTOM", frame, "BOTTOM", 0, 2)
	elseif countAt == "below" then frame.count:SetPoint("TOP", under, "BOTTOM", 0, -2); under = frame.count
	elseif countAt == "above" then frame.count:SetPoint("BOTTOM", over, "TOP", 0, 2)
	else frame.count:SetPoint("CENTER", frame, "CENTER", 0, 0) end
	frame.text:ClearAllPoints()
	if mode == "text" then
		frame.text:SetPoint("CENTER", frame, "CENTER", 0, 0)
	else
		frame.text:SetPoint("TOP", under, "BOTTOM", 0, -5)
	end
	SP:SetSPFont(frame.text, "windfury", sv.textSize or 24, "OUTLINE")   -- (its own font: Appearance > Fonts & Textures)
	if W.shown then
		glowOn()
		if W.sweep then W.sweep() end   -- (Show Internal Cooldown or Text Only switched while it shows)
	end
end

local function build()
	if frame then return frame end
	local f = CreateFrame("Frame", "ShamanPowerWindfuryProcFrame", UIParent)
	f:SetFrameStrata("HIGH")
	f:SetClampedToScreen(true)   -- (never left off the screen, as the game keeps it)
	f:SetMovable(true)
	f:SetSize(64, 64)
	f.icon = f:CreateTexture(nil, "ARTWORK")
	f.icon:SetAllPoints()
	f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	f.icon:SetTexture(iconFor("weapon"))
	f.text = f:CreateFontString(nil, "OVERLAY")
	SP:SetSPFont(f.text, "windfury", 24, "OUTLINE")
	f.text:SetText(WORD)
	f.text:SetTextColor(1, 0.8, 0)   -- (WoW's gold)
	f.glow = f:CreateTexture(nil, "OVERLAY", nil, 1)
	f.glow:SetPoint("TOPLEFT", -12, 12)
	f.glow:SetPoint("BOTTOMRIGHT", 12, -12)
	f.glow:SetTexture("Interface\\SpellActivationOverlay\\IconAlert")
	f.glow:SetTexCoord(0.00781250, 0.50781250, 0.27734375, 0.52734375)
	-- (its shape is painted by glowOn: its own Glow Shape, else the shared one)
	f.glow:Hide()
	f.pulse = f.glow:CreateAnimationGroup()
	f.pulse:SetLooping("REPEAT")
	local up = f.pulse:CreateAnimation("Alpha")
	up:SetFromAlpha(0.4); up:SetToAlpha(1); up:SetDuration(0.4); up:SetOrder(1)
	local down = f.pulse:CreateAnimation("Alpha")
	down:SetFromAlpha(1); down:SetToAlpha(0.4); down:SetDuration(0.4); down:SetOrder(2)
	-- Show Internal Cooldown: the game's own cooldown sweep over Windfury Weapon's icon (no numbers: 1.5 seconds)
	f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
	f.cd:SetAllPoints(f.icon)
	f.cd:SetDrawEdge(false)
	if f.cd.SetHideCountdownNumbers then f.cd:SetHideCountdownNumbers(true) end
	f.cd.noCooldownCount = true   -- (OmniCC and the like: no numbers either)
	f.cd:EnableMouse(false)
	f.cd:Hide()
	-- Color Fills In: a gray sheet over the icon that gives way toward one edge as the cooldown runs
	f.sheet = f:CreateTexture(nil, "ARTWORK", nil, 2)
	f.sheet:SetColorTexture(0, 0, 0, 0.65)
	f.sheet:Hide()
	-- Progress Bar: a thin bar under (or over) the icon, draining with the cooldown (ShamanPower's bar texture)
	f.bar = CreateFrame("StatusBar", nil, f)
	if SP.SetSPStatusBarTexture then SP:SetSPStatusBarTexture(f.bar, "other", "Interface\\Buttons\\WHITE8X8")
	else f.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8") end
	f.bar:SetMinMaxValues(0, 1); f.bar:SetValue(1)
	local barBg = f.bar:CreateTexture(nil, "BACKGROUND"); barBg:SetAllPoints(f.bar); barBg:SetColorTexture(0, 0, 0, 0.6)
	f.bar:EnableMouse(false)
	f.bar:Hide()
	-- Show Countdown: the seconds left, on a frame above the sweep (on the icon's own frame the sweep covers it)
	f.over = CreateFrame("Frame", nil, f)
	f.over:SetAllPoints(f)
	f.over:SetFrameLevel(f:GetFrameLevel() + 4)
	f.over:EnableMouse(false)
	f.count = f.over:CreateFontString(nil, "OVERLAY")
	SP:SetSPFont(f.count, "windfury", 20, "OUTLINE")
	f.count:SetTextColor(1, 1, 1)
	f.count:SetText("1.5")   -- (never empty: the word under it keeps its place)
	f.count:Hide()
	-- its spot, saved the way a drag saves it (Unlock UI runs this after moving it)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local sv = DB()
		local point, _, _, x, y = self:GetPoint(1)
		if sv and point then sv.position = { point = point, x = x, y = y } end
	end)
	f:EnableMouse(false)   -- (never in the way of a click: it moves in Unlock UI)
	f:Hide()
	frame = f
	place()
	look()
	return f
end

-- Show Internal Cooldown: the sweep over Windfury Weapon's icon while its cooldown runs (a totem proc's icon, Text
-- Only or the setting off: none)
-- (each part runs on our own numbers: the proc's moment and the 1.5 seconds, never a value read from the game)
local ticker = CreateFrame("Frame")
local function sweepOff()
	ticker:SetScript("OnUpdate", nil)
	if not (frame and W.sweeping) then return end
	W.sweeping = nil
	if frame.cd.Clear then frame.cd:Clear() end
	frame.cd:Hide()
	frame.sheet:Hide()
	frame.bar:Hide()
	frame.count:Hide()
	frame.icon:SetDesaturated(false)
end
-- each frame while it runs: the sheet, the bar and the number follow the time left; done: all of it goes
local function tick()
	local sv = DB()
	local left = W.icdAt and (W.icdAt + WEAPON_ICD - GetTime()) or 0
	if not (frame and sv) or left <= 0 then sweepOff() return end
	local share = left / WEAPON_ICD
	if frame.sheet:IsShown() then frame.sheet:SetHeight(math.max(0.01, frame.icon:GetHeight() * share)) end
	if frame.bar:IsShown() then frame.bar:SetValue(share) end
	if frame.count:IsShown() then
		frame.count:SetText(string.format("%.1f", left))
		if sv.icdCountdownColors and SP.CountdownColor then
			frame.count:SetTextColor(SP:CountdownColor(left, WEAPON_ICD, "cd"))
		else
			frame.count:SetTextColor(1, 1, 1)
		end
	end
end
local function sweep()
	local sv = DB()
	if not (frame and sv) then return end
	local left = W.icdAt and (W.icdAt + WEAPON_ICD - GetTime()) or 0
	if sv.showICD ~= false and W.icon == "weapon" and left > 0 and (sv.displayMode or "icon") ~= "text" then
		local style = sv.icdSweep or "radial"
		if style == "radial" then
			frame.cd:SetCooldown(W.icdAt, WEAPON_ICD)
			frame.cd:Show()
		else
			if frame.cd.Clear then frame.cd:Clear() end
			frame.cd:Hide()
		end
		frame.sheet:SetShown(style == "vertical")
		frame.bar:SetShown((sv.icdBar or "none") ~= "none")
		frame.count:SetShown(sv.icdCountdown ~= false)
		frame.icon:SetDesaturated(sv.icdGray == true)
		W.sweeping = true
		tick()
		ticker:SetScript("OnUpdate", tick)
	else
		sweepOff()
	end
end
W.sweep = sweep   -- (look() redraws it: a setting changed while it shows)

local function hide()
	W.shown = nil
	glowOff()
	sweepOff()
	if frame then frame:Hide() end
end

-- a proc: shown (or kept up) for Time On Screen from this proc, its icon the proc's own, its sound; a Windfury
-- Weapon proc with Show Internal Cooldown: its sweep, and up at least until the sweep is done
local function fire(which, quiet)
	local sv = DB()
	if not sv then return end
	local f = build()
	W.icon = which
	if which == "weapon" then W.icdAt = GetTime() end
	f.icon:SetTexture(iconFor(which))
	if not W.shown then
		look()            -- (before it counts as shown: its glow starts once, below)
		W.shown = true
		f:Show()
		glowOn()
	end
	sweep()
	local hold = sv.showTime or 1.5
	if W.sweeping then hold = math.max(hold, WEAPON_ICD) end
	W.gen = W.gen + 1
	local gen = W.gen
	C_Timer.After(hold, function()
		if W.gen == gen and not W.demo and not W.unlocked then hide() end
	end)
	if not quiet and sv.playSound then
		local now = GetTime()
		if not W.soundAt or now - W.soundAt >= SOUND_GAP then
			W.soundAt = now
			SP:PlaySoundWithVolume(SP:GetSoundFile(sv.soundName or "Raid Warning"), sv.soundVolume or 100, true)
		end
	end
end

-- ---------------------------------------------------------------------------
-- The game's word of a proc: listened to only while it is on (and ShamanPower is)
-- ---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
local function sync()
	local sv = DB()
	local on = sv and sv.enabled == true and not SP:IsOff()
	if on then
		ev:RegisterEvent("SPELL_UPDATE_COOLDOWN")
	else
		ev:UnregisterEvent("SPELL_UPDATE_COOLDOWN")
		if not W.demo and not W.unlocked then hide() end
	end
end

ev:RegisterEvent("ADDON_LOADED")
ev:SetScript("OnEvent", function(self, event, id)
	if event == "SPELL_UPDATE_COOLDOWN" then
		if type(id) ~= "number" or (issecretvalue and issecretvalue(id)) or W.demo or W.unlocked then return end
		local sv = DB()
		if not sv then return end
		if WEAPON[id] then
			if sv.weapon ~= false then fire("weapon") end
		elseif TOTEM[id] then
			if sv.totem ~= false then fire("totem") end
		end
	elseif event == "ADDON_LOADED" and id == "ShamanPower_WindfuryProc" then
		self:UnregisterEvent("ADDON_LOADED")
		if type(ShamanPowerWindfuryProcDB) ~= "table" then ShamanPowerWindfuryProcDB = {} end
		DB()
		build()
		sync()
	end
end)
SP:OnOnOff(function() sync() end)   -- (Enable ShamanPower switched)

-- ---------------------------------------------------------------------------
-- What the settings, Unlock UI, the profile switch and the preview call
-- ---------------------------------------------------------------------------
-- a setting changed (or a profile switched): its look, its spot and whether it listens
function SP:UpdateWindfuryProcAppearance()
	if not DB() then return end
	build()
	place()
	look()
	sync()
end

-- Test Windfury Proc: one proc, as it shows in a fight, with its sound
function SP:WindfuryProcTest()
	if not DB() then return end
	fire("weapon")
end

-- back to where it starts
function SP:WindfuryProcReset()
	local sv = DB()
	if not sv then return end
	local p = defaults.position
	sv.position = { point = p.point, x = p.x, y = p.y }
	place()
end

-- the page's preview and Unlock UI: up the whole time in Unlock UI; in the preview, a weapon proc and a totem
-- proc in turn (quiet: Test Windfury Proc plays the sound)
function SP:WindfuryProcDemo(on)
	if not DB() then return end
	build()
	if W.ticker then W.ticker:Cancel(); W.ticker = nil end
	if not on then
		W.demo, W.unlocked = nil, nil
		hide()
		return
	end
	if self.IsMasterUnlocked and self:IsMasterUnlocked() then
		W.unlocked = true
		fire("weapon", true)
		return
	end
	W.demo = true
	local beat = 0
	local function step()
		beat = beat + 1
		local which = (beat % 2 == 1) and "weapon" or "totem"
		W.shown = nil
		fire(which, true)
		local hold = W.sweeping and math.max(DB().showTime or 1.5, WEAPON_ICD) or (DB().showTime or 1.5)
		C_Timer.After(hold, function() if W.demo then hide() end end)
	end
	step()
	W.ticker = C_Timer.NewTicker(math.max(DB().showTime or 1.5, WEAPON_ICD) + 1, function() if W.demo then step() end end)
end

if SP.RegisterPreview then
	SP:RegisterPreview("windfury", { frame = "ShamanPowerWindfuryProcFrame", demo = "SP:WindfuryProcDemo", pad = 24 })
end
