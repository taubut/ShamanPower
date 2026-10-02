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
	enabled = (SPCompat.FOREVER),
	mode = "ready",        -- "ready": show only when ready | "cooldown": show only while on cooldown | "always": dim + countdown on cooldown
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
	arrange = "free",      -- free: a spot per icon | grid: one block, filled in the order the icons appear
	gridColumns = 6,       -- grid: icons per row
	gridGrow = "down",     -- grid: new rows go down | up
	gridAlign = "center",  -- grid: a row that is not full sits left | center | right
	-- gridPos = { point, x, y }: the grid's spot (nil = default)
	shockIcon = "cycle",   -- the Shocks entry's icon: cycle | split | one ("earth" = the old Earth Shock only: one, Earth)
	shockPick = "earthshock",   -- One Shock: the shock shown (earthshock | flameshock | frostshock)
	shockKeepLast = false,      -- Keep Showing the Last Shock (Cycle, One Shock)
	spacing = 8,
	locked = true,
	spells = {},           -- [key] = true/false (nil = catalog default)
	positions = {},        -- [key] = { point, x, y }
}
-- the support code (/sp support) reports only what differs from these
if SP and SP.SUPPORT_MODULE_DEFAULTS then SP.SUPPORT_MODULE_DEFAULTS.ShamanPower_ReadyReminders = DEFAULTS end

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
	{ key = "chainlightning", name = "Chain Lightning",   ids = { 421 },                  def = false },   -- 6 s cooldown on both clients
	-- Earth, Flame and Frost Shock in one icon (they share one cooldown). Earth Shock's
	-- ID stands for the cooldown: the game puts all three on it whichever is cast.
	{ key = "shocks", name = "Combined Shocks", optName = "Combined Shocks (Earth, Flame and Frost Shock)", ids = { 8042 }, def = false, combo = true },
}

local frames = {}
SP.readyReminderFrames = frames   -- read by the setup tour's preview
local catalogByKey = {}
for i, e in ipairs(SP.ReadyReminderSpells) do e.order = i; catalogByKey[e.key] = e end

-- Filling in the defaults walks every one of them, and SV() is called about 20
-- times per update pass. So the walk runs only when the saved table is a new one
-- (it loaded, an import replaced it), when a theme reset cleared one of the
-- colors, and once a second besides (a setting cleared some other way); every
-- other call hands the table straight back.
local filledFor, filledAt = nil, 0
local function SV()
	local sv = ShamanPower_ReadyReminders
	local now = GetTime()
	if sv == filledFor and now - filledAt < 1 and sv.borderColor ~= nil and sv.glowColor ~= nil and sv.barColor ~= nil then
		return sv
	end
	filledFor, filledAt = sv, now
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
local IS_MAINLINE = (SPCompat.FOREVER)
local SHOCK_FAMILY = { "earthshock", "flameshock", "frostshock" }
local isShock = { earthshock = true, flameshock = true, frostshock = true }
local function cooldownOf(entry)
	if entry.combo then
		-- Shocks: the family's cooldown (the latest end among the shocks known)
		local bs, bd
		for _, key in ipairs(SHOCK_FAMILY) do
			local e = catalogByKey[key]
			if e then
				local s, d = ownCooldownOf(e)
				if s and d and d > GCD_MAX and (not bd or s + d > bs + bd) then bs, bd = s, d end
			end
		end
		return bs, bd
	end
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
-- the row / column Reset Positions lays out: the single spells only (Shocks
-- is placed from Earth Shock, below), so adding it moved nobody's icons
local baseCount = 0
for _, e in ipairs(SP.ReadyReminderSpells) do if not e.combo then baseCount = baseCount + 1 end end

local function defaultPos(entry)
	local sv = SV()
	local size, gap = sv.iconSize or 48, sv.spacing or 8
	if entry.combo then
		-- Earth Shock's spot when its own reminder is off (the three singles hidden),
		-- else one step before it
		local es = catalogByKey.earthshock
		local p = sv.positions.earthshock or defaultPos(es)
		local x, y = p.x or 0, p.y or 0
		local v = sv.spells.earthshock
		if v == nil then v = es.def end
		if v then
			if sv.layout == "column" then y = y + size + gap else x = x - size - gap end
		end
		return { point = p.point or "CENTER", x = x, y = y }
	end
	local n = baseCount
	local off = (entry.order - (n + 1) / 2) * (size + gap)
	if sv.layout == "column" then return { point = "CENTER", x = 260, y = -off } end
	return { point = "CENTER", x = off, y = -140 }
end

local function savePos(frame)
	local point, _, _, x, y = frame:GetPoint()
	SV().positions[frame.entry.key] = { point = point, x = x, y = y }
end

-- ---------------------------------------------------------------------------
-- Grid placement: the icons sit in one block that moves as a whole, and the
-- ones on screen fill its slots in the order they appeared, so no hole is left
-- where a hidden spell would be. Free placement (the default) keeps a spot per
-- icon. The icons stay parented to UIParent (only anchored to the block), so
-- the settings preview can still borrow them one by one.
-- ---------------------------------------------------------------------------
local gridAnchor
local gridSeq = 0      -- counts appearances: a lower number came on screen first
local gridList = {}    -- reused each pass
local gridByCatalog = false
-- Most passes nobody appears or leaves: the layout then only notices that and
-- stops. gridDirty (a setting changed, an icon was re-anchored) or a change in
-- who is on screen or in the grid's settings (gridKey) sorts and places again.
local gridDirty = true
local gridKey = {}

local function gridOn() return SV().arrange == "grid" end

-- the corner (or edge middle) the grid grows from: it stays put when the grid grows or shrinks
local function gridOrigin(sv)
	local v = (sv.gridGrow == "up") and "BOTTOM" or "TOP"
	local h = sv.gridAlign == "left" and "LEFT" or sv.gridAlign == "right" and "RIGHT" or ""
	return v .. h
end

local function saveGridPos()
	local a, sv = gridAnchor, SV()
	if not a then return end
	local point = gridOrigin(sv)
	-- still hanging off its origin on UIParent (Unlock UI's box shifts it that way):
	-- read the offsets, as the screen spot can lag straight after a SetPoint
	if a:GetNumPoints() == 1 then
		local p, rel, relP, x, y = a:GetPoint(1)
		if p == point and relP == point and rel == UIParent then sv.gridPos = { point = point, x = x, y = y }; return end
	end
	if not a:GetLeft() then return end
	local pw, ph = UIParent:GetWidth(), UIParent:GetHeight()
	local x, y
	if point:find("LEFT") then x = a:GetLeft()
	elseif point:find("RIGHT") then x = a:GetRight() - pw
	else x = (a:GetLeft() + a:GetRight()) / 2 - pw / 2 end
	if point:find("TOP") then y = a:GetTop() - ph else y = a:GetBottom() end
	sv.gridPos = { point = point, x = x, y = y }
end

local function applyGridPos()
	local sv = SV()
	-- by default the first row sits where the default row of icons does
	local p = sv.gridPos or { point = "TOP", x = 0, y = -140 + (sv.iconSize or 48) / 2 }
	gridAnchor:ClearAllPoints()
	gridAnchor:SetPoint(p.point or "TOP", UIParent, p.point or "TOP", p.x or 0, p.y or 0)
end

local function ensureGridAnchor()
	if gridAnchor then return gridAnchor end
	local a = CreateFrame("Frame", "ShamanPowerReadyGrid", UIParent)
	a:SetSize(48, 48); a:SetMovable(true); a:SetClampedToScreen(true)
	a.spMoverLabel = "Ready Reminders"   -- Unlock UI's box
	-- Unlock UI's box and a dragged icon both end here: record where the block is now
	a:SetScript("OnMouseUp", function(self)
		if self.isMoving then self:StopMovingOrSizing(); self.isMoving = false; saveGridPos(); applyGridPos() end
	end)
	gridAnchor = a
	applyGridPos()
	return a
end

-- the icons still on screen but invisible (a cooldown curve holds them at
-- alpha 0) go after the visible ones, so they never leave a hole
local function gridBefore(p, q)
	if p.gridVis ~= q.gridVis then return p.gridVis end
	if gridByCatalog or not p.gridVis or p.gridSeq == q.gridSeq then return p.entry.order < q.entry.order end
	return p.gridSeq < q.gridSeq
end

-- byCatalog: every icon at once, in the list's order (Unlock Positions)
local function layoutGrid(byCatalog)
	local sv = SV()   -- once: SV() walks the defaults on every call, and this runs every pass
	if sv.arrange ~= "grid" then return end
	local a = ensureGridAnchor()
	local mode = sv.mode or "ready"
	local spells = sv.spells
	byCatalog = byCatalog and true or false
	local changed = gridDirty or byCatalog ~= gridByCatalog
	wipe(gridList)
	local enabled, nVis = 0, 0
	for _, entry in ipairs(SP.ReadyReminderSpells) do
		local on = spells[entry.key]   -- spellOn(), without its SV() call
		if on == nil then on = entry.def end
		if on and usable(entry) then enabled = enabled + 1 end
		local f = frames[entry.key]
		if f then
			local inList = f:IsShown() and f:GetParent() == UIParent   -- not while the settings preview has it
			local vis = false
			if inList then
				if byCatalog or mode == "always" then vis = true
				elseif mode == "ready" then vis = (f.gridReady or f.realDone == true) and true or false   -- realDone: the curve has lit it
				else vis = not f.gridReady and not f.realDone end                                         -- "cooldown": the curve has hidden it
				if vis and not f.gridVis then gridSeq = gridSeq + 1; f.gridSeq = gridSeq end
				if vis then nVis = nVis + 1 end
				gridList[#gridList + 1] = f
			end
			if vis ~= (f.gridVis or false) or inList ~= (f.gridIn or false) then changed = true end
			f.gridVis, f.gridIn = vis, inList
		end
	end

	local size, gap, perRow = sv.iconSize or 48, sv.spacing or 8, sv.gridColumns or 6
	local grow, align = sv.gridGrow or "down", sv.gridAlign or "center"
	local k = gridKey
	if k.enabled ~= enabled or k.size ~= size or k.gap ~= gap or k.perRow ~= perRow or k.grow ~= grow or k.align ~= align then
		changed = true
		k.enabled, k.size, k.gap, k.perRow, k.grow, k.align = enabled, size, gap, perRow, grow, align
	end
	if not changed then return end   -- the usual pass: nothing to move
	gridDirty = false
	gridByCatalog = byCatalog
	table.sort(gridList, gridBefore)

	-- the block is sized for every enabled icon, so its box in Unlock UI holds them all
	local cell = size + gap
	local n = math.max(enabled, 1)
	local cols = math.max(1, math.min(perRow, n))
	local rows = math.ceil(n / cols)
	local W, H = cols * cell - gap, rows * cell - gap
	-- Grow or Align changed: keep the block where it is, measured from its new origin
	if (sv.gridPos and sv.gridPos.point or "TOP") ~= gridOrigin(sv) then saveGridPos(); applyGridPos() end
	if a.gridW ~= W or a.gridH ~= H then a:SetSize(W, H); a.gridW, a.gridH = W, H end

	local up = grow == "up"
	for i, f in ipairs(gridList) do
		local r, c = math.floor((i - 1) / cols), (i - 1) % cols
		local inRow = math.min(cols, nVis - r * cols)   -- visible icons in this row (the rest trail after them)
		if inRow <= 0 then inRow = cols end
		local rowW = inRow * cell - gap
		local x = (align == "left" and 0 or align == "right" and (W - rowW) or (W - rowW) / 2) + c * cell
		local y = up and -(H - size - r * cell) or -r * cell
		if f.gridX ~= x or f.gridY ~= y or f.gridAnchored ~= a then
			f:ClearAllPoints(); f:SetPoint("TOPLEFT", a, "TOPLEFT", x, y)
			f.gridX, f.gridY, f.gridAnchored = x, y, a
		end
	end
end

local function applyPos(frame)
	if gridOn() then
		-- the grid places it (layoutGrid); until then it waits on the first slot
		local a = ensureGridAnchor()
		if frame.gridAnchored ~= a then
			frame:ClearAllPoints(); frame:SetPoint("TOPLEFT", a, "TOPLEFT", 0, 0)
			frame.gridX, frame.gridY, frame.gridAnchored = 0, 0, a
			gridDirty = true   -- off its slot: the next layout puts it back
		end
		return
	end
	frame.gridAnchored = nil
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
	if SP.ShapeGlow then SP:ShapeGlow(glow, "alert") end   -- Glow Shape
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
	-- Icon Shape (Ready Reminders): the icon, the sweep over it, its backing and the swipe
	if SP.ShapeIconTexture then
		SP:ShapeIconTexture(icon, icon, "ready")
		SP:ShapeIconTexture(overlay, icon, "ready")
		SP:ShapeIconTexture(bg, f, "ready")
		SP:ShapeCooldown(cd, "ready")
	end
	local label = f:CreateFontString(nil, "OVERLAY")
	SP:SetSPFont(label, "alerts", 11, "OUTLINE")
	label:SetPoint("TOP", f, "BOTTOM", 0, -3)
	label:SetText(entry.name); label:SetTextColor(1, 0.82, 0)
	label:Hide()
	f.label = label

	f:SetScript("OnMouseDown", function(self, button)
		-- icons move only while positions are unlocked
		if button == "LeftButton" and SP.readyPositioning then
			if gridOn() then   -- one block: any icon drags the whole grid
				local a = ensureGridAnchor()
				a:StartMoving(); a.isMoving = true; self.movesGrid = true
			else
				self:StartMoving(); self.isMoving = true
			end
		end
	end)
	f:SetScript("OnMouseUp", function(self)
		if self.movesGrid then
			self.movesGrid = nil
			local a = gridAnchor
			if a and a.isMoving then a:StopMovingOrSizing(); a.isMoving = false; saveGridPos(); applyGridPos() end
		elseif self.isMoving then self:StopMovingOrSizing(); self.isMoving = false; savePos(self) end
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

-- ---------------------------------------------------------------------------
-- Shocks (the combined entry). Shock Icon picks the look:
--   cycle: Earth, Flame, Frost in turn, each held SHOCK_HOLD then crossfaded
--          into the next (a game-drawn Alpha animation on a second texture;
--          Lua runs once per shock, to swap the textures). Only while ready:
--          on cooldown it stops on the shock just cast, and the cycle starts
--          again from that one.
--   split: Earth's icon with the matching thirds of Flame and Frost laid over
--          its middle and right (halves at two shocks), like the cooldown
--          bar's split imbue icon. A theme's flat box still covers it whole.
--   one:   one shock, picked in Shock (Earth by default; "earth" is the old
--          "Earth Shock only", read as one + Earth).
-- Keep Showing the Last Shock (Cycle, One Shock): once a shock is cast, the icon
-- stays on the shock cast last, ready or not, until another is cast. It starts
-- over (cycling, or the picked shock) after a reload.
-- Only the shocks the character knows (the setup tour's demo shows them all).
-- ---------------------------------------------------------------------------
local SHOCK_HOLD, SHOCK_FADE = 1.2, 0.3
local lastShockKey   -- the shock cast last (UNIT_SPELLCAST_SUCCEEDED, see the wake frame)

-- Own casts' spell IDs stay readable in combat. Any rank, matched by name once per ID.
local shockKeyOf = {}   -- [spellID] = "earthshock" | "flameshock" | "frostshock" | false
local function noteShockCast(spellID)
	if spellID == nil or (issecretvalue and issecretvalue(spellID)) then return end
	local key = shockKeyOf[spellID]
	if key == nil then
		key = false
		local name = GetSpellInfoC(spellID)
		if name and not (issecretvalue and issecretvalue(name)) then
			for _, k in ipairs(SHOCK_FAMILY) do
				local e = catalogByKey[k]
				local id = e and clientSpellID(e)
				if id and GetSpellInfoC(id) == name then key = k break end
			end
		end
		shockKeyOf[spellID] = key
	end
	if key then
		lastShockKey = key
		SP.readyWake = true   -- the icon shows it on the next pass
	end
end

local function setIconTex(f, tex)
	if f.shownTex ~= tex then f.shownTex = tex; f.icon:SetTexture(tex) end
end

-- the icon and every texture drawn with it (a crossfade, split slices)
local function setDesat(f, on)
	f.icon:SetDesaturated(on)
	if f.icon2 then f.icon2:SetDesaturated(on) end
	if f.slices then
		for i = 2, 3 do if f.slices[i] then f.slices[i]:SetDesaturated(on) end end
	end
end

local function stopCycle(f)
	if not f.cycling then return end
	f.cycling = nil
	f.cycAG:Stop()
	f.icon2:SetAlpha(0); f.icon2:Hide()
end

local function cycleNext(f)
	local n = f.cycN or 0
	if not f.cycling or n < 2 then return end
	f.cycIdx = (f.cycIdx or 1) % n + 1
	setIconTex(f, f.cycTex[f.cycIdx])
	f.icon2:SetTexture(f.cycTex[f.cycIdx % n + 1])
	f.cycAG:Play()
end

local function shockStyle(sv)
	local st = sv.shockIcon or "cycle"
	if st == "earth" then return "one" end
	return st
end

-- the shock the icon stays on (an index into f.cycKeys), or nil to cycle
local function staticShock(f, sv, style)
	local want
	if sv.shockKeepLast and lastShockKey then
		want = lastShockKey
	elseif style == "one" then
		want = (sv.shockIcon == "earth") and "earthshock" or (sv.shockPick or "earthshock")
	end
	if not want then return nil end
	for i = 1, f.cycN or 0 do
		if f.cycKeys[i] == want then return i end
	end
	return (style == "one") and 1 or nil   -- a picked shock not known yet: the first one known
end

local function startCycle(f)
	if f.cycling or shockStyle(SV()) ~= "cycle" or (f.cycN or 0) < 2 then return end
	if not f.icon2 then
		local t = f:CreateTexture(nil, "ARTWORK", nil, 1)
		t:SetAllPoints(f.icon)
		t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		t:SetAlpha(0)
		local ag = t:CreateAnimationGroup()
		local a = ag:CreateAnimation("Alpha")
		a:SetFromAlpha(0); a:SetToAlpha(1); a:SetStartDelay(SHOCK_HOLD); a:SetDuration(SHOCK_FADE)
		-- the next shock is now fully up: it becomes the icon, and the next fade starts
		ag:SetScript("OnFinished", function() cycleNext(f) end)
		f.icon2, f.cycAG = t, ag
		if SP.ShapeIconTexture then SP:ShapeIconTexture(t, f.icon, "ready") end   -- Icon Shape
	end
	f.icon2:SetDesaturated(f.icon:IsDesaturated() and true or false)
	f.icon2:SetTexture(f.cycTex[(f.cycIdx or 1) % f.cycN + 1])
	f.icon2:SetAlpha(0); f.icon2:Show()
	f.cycling = true
	f.cycAG:Play()
end

-- The icon for the state: ready (Cycle cycles unless a shock is kept) or on
-- cooldown (Cycle stops on the shock just cast and picks up from it later).
local function shockIcon(f, ready)
	if not f.cycKeys then return end
	local sv = SV()
	local style = shockStyle(sv)
	if style == "split" then stopCycle(f) return end
	local idx = staticShock(f, sv, style)
	if not idx and style == "cycle" then
		if ready then startCycle(f) return end
		stopCycle(f)
		if lastShockKey then
			for i = 1, f.cycN or 0 do
				if f.cycKeys[i] == lastShockKey then f.cycIdx = i break end
			end
		end
		setIconTex(f, f.cycTex[f.cycIdx or 1])
		return
	end
	stopCycle(f)
	idx = idx or 1
	f.cycIdx = idx
	setIconTex(f, f.cycTex[idx])
end
local function showCastShock(f) shockIcon(f, false) end

local function applyShockLook(f)
	local sv = SV()
	local style = shockStyle(sv)
	f.cycTex, f.cycKeys = f.cycTex or {}, f.cycKeys or {}
	local n = 0
	for _, key in ipairs(SHOCK_FAMILY) do
		local e = catalogByKey[key]
		if e and usable(e) and (SP.readyDemoActive or playerKnows(e)) then
			n = n + 1
			f.cycTex[n] = GetSpellTextureC(clientSpellID(e)) or 136024
			f.cycKeys[n] = key
		end
	end
	for i = n + 1, 3 do f.cycTex[i], f.cycKeys[i] = nil, nil end
	if n == 0 then n = 1; f.cycTex[1] = GetSpellTextureC(8042) or 136024; f.cycKeys[1] = "earthshock" end
	f.cycN = n
	if not f.cycIdx or f.cycIdx > n then f.cycIdx = 1 end
	stopCycle(f)   -- the next ready pass starts it again with this look
	-- split: slices 2 and 3 over Earth's icon, each the matching part of its own icon
	local iw = (sv.iconSize or 48) - 4   -- the icon sits 2 px inside the frame
	f.slices = f.slices or {}
	for i = 2, 3 do
		local sl = f.slices[i]
		if style == "split" and i <= n then
			if not sl then
				sl = f:CreateTexture(nil, "ARTWORK", nil, 1); f.slices[i] = sl
				if SP.ShapeIconTexture then SP:ShapeIconTexture(sl, f.icon, "ready") end   -- Icon Shape: the whole icon's shape
			end
			sl:ClearAllPoints()
			sl:SetPoint("TOPLEFT", f.icon, "TOPLEFT", iw * (i - 1) / n, 0)
			sl:SetPoint("BOTTOMLEFT", f.icon, "BOTTOMLEFT", iw * (i - 1) / n, 0)
			sl:SetWidth(iw / n)
			sl:SetTexture(f.cycTex[i])
			sl:SetTexCoord(0.08 + 0.84 * (i - 1) / n, 0.08 + 0.84 * i / n, 0.08, 0.92)
			sl:SetDesaturated(f.icon:IsDesaturated() and true or false)
			sl:Show()
		elseif sl then
			sl:Hide()
		end
	end
	if style == "split" then setIconTex(f, f.cycTex[1]) else shockIcon(f, false) end   -- the ready pass starts a cycle
end

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
	-- the border (Hide Border: just the border); round a Rounded / Circle icon it
	-- follows the shape as a ring, unless Keep Borders Square
	local borderOn = not sv.hideBackground and not sv.hideBorder
	local ringFile = SP.BorderRingFile and SP:BorderRingFile("ready")
	f.bg:SetShown(not sv.hideBackground); f.border:SetShown(borderOn and not ringFile)
	f.border:SetBackdropBorderColor(color(sv.borderColor, 0.2, 0.7, 1.0))
	if ringFile then
		if not f.ring then
			f.ring = f:CreateTexture(nil, "OVERLAY")
			f.ring:SetAllPoints(f.border)
		end
		if f.ring.spFile ~= ringFile then f.ring:SetTexture(ringFile); f.ring.spFile = ringFile end
		f.ring:SetVertexColor(color(sv.borderColor, 0.2, 0.7, 1.0))
		f.ring:SetShown(borderOn)
	elseif f.ring then
		f.ring:Hide()
	end
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
	if f.entry.combo then
		applyShockLook(f)
	else
		local id = clientSpellID(f.entry)
		local tex = id and GetSpellTextureC(id)
		f.icon:SetTexture(tex or 136024)
	end
	f:SetAlpha(sv.opacity or 1)
	applyPos(f)
	styleEngine(f)
end

function SP:UpdateAllReadyReminderAppearance()
	for key, f in pairs(frames) do self:UpdateReadyReminderAppearance(key); applyPos(f) end   -- positions too: an import replaces them
	if gridAnchor then applyGridPos() end   -- an import replaces the grid's spot as well
	gridDirty = true   -- any setting may have changed
	layoutGrid(self.readyPositioning)
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
	if f.entry.combo then showCastShock(f) end   -- Shocks: no cycling while not ready
end

-- The Ready Effect (glow / pulse): on a ready icon, or in "only while on
-- cooldown" (where a ready icon is never shown) on the icon while it counts down.
local function playEffects(f, sv)
	local fx = sv.readyEffect or "glow"
	if (fx == "glow" or fx == "both") then
		if not f.glowShown then f.glow:Show(); f.glowAnim:Play(); f.glowShown = true end
	elseif f.glowShown then f.glow:Hide(); f.glowAnim:Stop(); f.glowShown = nil end
	if (fx == "pulse" or fx == "both") then
		if not f.pulsing then f.pulseAnim:Play(); f.pulsing = true end
	elseif f.pulsing then f.pulseAnim:Stop(); f.pulsing = nil end
end

local function setReady(f, ready)
	local sv = SV()
	if ready then
		setDesat(f, false)
		f.cooldown:Hide(); f.overlay:Hide(); f.bar:Hide(); f.count:SetText(""); f.countShown = nil
		f.ecdOn, f.ecdDur, f.readyDur, f.readyDurStart, f.realDone = nil, nil, nil, nil, nil
		curveMouseBack(f)
		if f.engineSheet then f.engineSheet:Hide() end
		f:SetAlpha(sv.opacity or 1)
		playEffects(f, sv)
		if f.entry.combo then shockIcon(f, true) end
	else
		setDesat(f, sv.desaturate ~= false)
		f:SetAlpha(sv.dimOpacity or 0.35)
		if sv.mode == "cooldown" then
			playEffects(f, sv)   -- runs on untouched each pass: only a change starts or stops it
			if f.entry.combo then showCastShock(f) end   -- Shocks: no cycling while not ready
		else
			stopEffects(f)
		end
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
			if SP.ShapeIconTexture then SP:ShapeIconTexture(sheet:GetStatusBarTexture(), f.icon, "ready") end   -- Icon Shape
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

-- "Always" and "only while on cooldown" modes, on cooldown: dim, countdown, sweep, bar.
local function drawCooldown(f, start, duration, remaining)
	local sv = SV()
	setReady(f, false)
	if engineOn() and not SP.readyDemoActive then
		if f.ecdStartSeen ~= start then f.ecdStartSeen = start; f.realDone = nil end   -- a new cooldown
		drawEngineCooldown(f, sv)
		-- Gray Out holds while the REAL cooldown runs: the game's end signal (realDone)
		-- brings the colour back even if our estimate still says cooling
		if f.realDone then setDesat(f, false) end
		-- dim while the REAL cooldown runs, full the moment it ends (the estimate may lag);
		-- "only while on cooldown" goes invisible (and stops catching clicks) then instead
		local onlyCooling = sv.mode == "cooldown"
		if f.ecdDur then curveAlpha(f, f.ecdDur, onlyCooling and 0 or (sv.opacity or 1), sv.dimOpacity or 0.35) end
		if onlyCooling and f.realDone then curveMouseOff(f) end
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
		pcall(wakeFrame.RegisterUnitEvent, wakeFrame, "UNIT_SPELLCAST_SUCCEEDED", "player")   -- Shocks: which shock was cast
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
		for _, f in pairs(frames) do if f:IsShown() then f:Hide() end; f.wasReady = nil; f.gridVis = nil end   -- gridVis: they appear anew
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
			f.gridReady = ready
			if ready then
				if f.wasReady == false then readySound(entry, f.lastDuration) end
				f.wasReady = true
				if sv.mode == "cooldown" then
					-- "only while on cooldown": a ready spell has nothing to show
					if f:IsShown() then setReady(f, true); stopEffects(f); f:Hide() end
				else
					if not f:IsShown() then f:Show() end
					setReady(f, true)
				end
			elseif sv.mode == "always" or sv.mode == "cooldown" then
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
	layoutGrid(false)
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
			setDesat(f, false); f:SetAlpha(SV().opacity or 1)
			f.label:SetShown(SV().showNames == true); f:Show()
		end
	end
	layoutGrid(true)
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
	-- only the placement in use: Grid puts the block back on its default spot and
	-- keeps the Free spots, Free lays the icons out again and keeps the grid's spot
	local grid = gridOn()
	if grid then
		SV().gridPos = nil
		if gridAnchor then applyGridPos() end
	else
		SV().positions = {}
	end
	for _, f in pairs(frames) do applyPos(f) end
	gridDirty = true
	layoutGrid(self.readyPositioning)
	SP:Print(grid and "Ready Reminders: grid position reset." or "Ready Reminders: positions reset.")
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
					f.gridReady = t >= DEMO_CD
					if t < DEMO_CD then
						if sv.mode == "always" or sv.mode == "cooldown" then
							if not f:IsShown() then f:Show() end
							drawCooldown(f, now - t, DEMO_CD, DEMO_CD - t)
						elseif f:IsShown() then f:Hide(); stopEffects(f) end
					else
						readyCount = readyCount + 1
						if sv.mode == "cooldown" then
							if f:IsShown() then setReady(f, true); stopEffects(f); f:Hide() end
						else
							if not f:IsShown() then f:Show() end
							setReady(f, true)
						end
					end
				elseif f and f:IsShown() then
					f:Hide()
				end
			end
			layoutGrid(false)   -- the grid fills and empties as it would in play
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
		if frames.shocks then applyShockLook(frames.shocks) end   -- the demo showed every shock: back to the known ones
		-- the settings preview hands its frames back on the points they had when it
		-- borrowed them (this runs after that): Placement, Reset or a drag made meanwhile
		-- would be undone, so every icon goes back on the spot the settings say now
		for _, f in pairs(frames) do f.gridAnchored = nil; applyPos(f) end
		self:UpdateReadyReminders()
		layoutGrid(self.readyPositioning)   -- the pass skips the layout while positioning
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

-- What Unlock UI boxes: the icons one by one, or in Grid placement the one block
-- (sized for every enabled icon; the demo fills and empties it meanwhile).
function SP:ReadyReminderMoverFrames()
	if not gridOn() then return self:ReadyReminderEnabledFrames() end
	self:ReadyReminderEnabledFrames()   -- makes the frames the block lays out
	local a = ensureGridAnchor()
	layoutGrid(self.readyPositioning)
	return { a }
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
-- Shocks switched on while a single shock reminder is still on: offer to hide
-- the three, so there are not four icons for one cooldown
local function shocksTurnedOn()
	local sv = SV()
	local any = false
	for _, key in ipairs(SHOCK_FAMILY) do
		local e = catalogByKey[key]
		if e and usable(e) and spellOn(e) then any = true end
	end
	if not any or not SP.ShowSPDialog then return end
	SP:ShowSPDialog({
		key = "ready_shocks_singles",
		title = "Hide the single shock reminders?",
		text = "Combined Shocks now stands for Earth, Flame and Frost Shock. Hide their own three reminders so you do not see four icons for one cooldown? You can turn them back on in the list any time.",
		buttons = {
			{ text = "Hide Them", onClick = function()
				for _, key in ipairs(SHOCK_FAMILY) do sv.spells[key] = false end
				SP:UpdateAllReadyReminderAppearance(); SP:UpdateReadyReminders()
				local reg = LibStub and LibStub("AceConfigRegistry-3.0", true)
				if reg then reg:NotifyChange("ShamanPower") end   -- the open settings show the three switched off
			end },
			{ text = "Keep Them" },
		},
	})
end

SP.ReadyShocksTurnedOn = shocksTurnedOn   -- the setup tour's spell list offers the same

-- the modes that draw the icon while on cooldown (the While On Cooldown settings apply)
local function coolingShown()
	local m = SV().mode or "ready"
	return m == "always" or m == "cooldown"
end

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
				desc = "Only when ready: the icon appears when the spell is off cooldown. Only while on cooldown: the icon appears with the sweep and countdown while the spell recharges, and goes away when it is ready. Always: the icon stays on screen with the sweep and countdown while on cooldown. Always, dimmed: the same, but grayed and faded until it is ready.",
				values = { ready = "Only when ready", cooldown = "Only while on cooldown", always_bright = "Always (sweep + countdown)", always = "Always, dimmed while on cooldown" },
				sorting = { "ready", "cooldown", "always_bright", "always" },
				get = function()
					local sv = SV()
					if sv.mode == "cooldown" then return "cooldown" end
					if (sv.mode or "ready") ~= "always" then return "ready" end
					-- "always" split by how the icon looks on cooldown: full colour, or dimmed
					if sv.desaturate == false and (sv.dimOpacity or 0.35) >= 1 then return "always_bright" end
					return "always"
				end,
				set = function(_, v)
					local sv = SV()
					if v == "ready" then
						sv.mode = "ready"
					elseif v == "cooldown" then
						-- starts in full colour (it is the only look it has); Gray Out / Opacity below still apply
						if sv.mode ~= "cooldown" then sv.desaturate = false; sv.dimOpacity = 1 end
						sv.mode = "cooldown"
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
				desc = function()
					if gridOn() then return "Puts the grid back on its default spot." end
					return "Lays the icons out again in a row or column (see Arrange As)."
				end, width = 1.0,
				func = function() SP:ResetReadyReminderPositions() end },
			arrange = { order = 4.9, type = "select", name = "Placement", width = 1.4,
				desc = "Free: each icon has its own spot, and a hidden icon leaves a gap. Grid: the icons form one block you move as a whole; the icons on screen fill it in the order they appeared, so there are never gaps.",
				values = { free = "Free (each icon its own spot)", grid = "Grid (fills in the order they appear)" },
				sorting = { "free", "grid" },
				get = function() return SV().arrange or "free" end,
				set = function(_, v) SV().arrange = v; refresh() end },
			gridColumns = { order = 4.91, type = "range", name = "Icons Per Row", min = 1, max = 12, step = 1, width = 1.0,
				desc = "How many icons fit in a row before the next row starts. 1 makes a column.",
				hidden = function() return not gridOn() end,
				get = function() return SV().gridColumns or 6 end, set = function(_, v) SV().gridColumns = v; refresh() end },
			gridGrow = { order = 4.92, type = "select", name = "New Rows Go", width = 1.0,
				hidden = function() return not gridOn() end,
				values = { down = "Down", up = "Up" }, sorting = { "down", "up" },
				get = function() return SV().gridGrow or "down" end, set = function(_, v) SV().gridGrow = v; refresh() end },
			gridAlign = { order = 4.93, type = "select", name = "Align Rows", width = 1.0,
				desc = "Where a row that is not full sits: packed to the left, centered, or packed to the right. Left keeps every icon still as new ones join; Center and Right shift the row to make room.",
				hidden = function() return not gridOn() end,
				values = { left = "Left", center = "Center", right = "Right" }, sorting = { "left", "center", "right" },
				get = function() return SV().gridAlign or "center" end, set = function(_, v) SV().gridAlign = v; refresh() end },
			layout = { order = 5.1, type = "select", name = "Reset Layout", width = 1.0,
				hidden = function() return gridOn() end,
				values = { row = "Row", column = "Column" },
				get = function() return SV().layout or "row" end, set = function(_, v) SV().layout = v end },
			spacing = { order = 5.2, type = "range", name = "Reset Spacing", min = 0, max = 40, step = 1, width = 1.0,
				desc = "The gap between icons: in the grid, and when Reset Position lays them out in Free placement.",
				get = function() return SV().spacing or 8 end,
				set = function(_, v) SV().spacing = v; if gridOn() then refresh() end end },

			lookHeader = { order = 6, type = "header", name = "Look" },
			iconSize = { order = 6.1, type = "range", name = "Icon Size", min = 24, max = 96, step = 2, width = 1.2,
				get = function() return SV().iconSize or 48 end, set = function(_, v) SV().iconSize = v; refresh() end },
			opacity = { order = 6.2, type = "range", name = "Opacity", min = 0.2, max = 1, step = 0.05, width = 1.2, isPercent = true,
				get = function() return SV().opacity or 1 end, set = function(_, v) SV().opacity = v; refresh() end },
			hideBackground = { order = 6.3, type = "toggle", name = "Hide Background & Border", width = 1.0,
				get = function() return SV().hideBackground end, set = function(_, v) SV().hideBackground = v; refresh() end },
			iconShape = { order = 6.33, type = "select", name = "Icon Shape", width = 1.0,
				desc = "The shape of the reminder icons: Square (as today), Flat, Rounded or Circle. The glow keeps its own Glow Shape. The same setting as Ready Reminders Icon Shape on General > Themes.",
				values = function() return (SP:IconShapeValues()) end,
				sorting = function() return select(2, SP:IconShapeValues()) end,
				get = function() return SP.IconShapeOf and SP:IconShapeOf("ready") or "default" end,
				set = function(_, v) if SP.SetIconShape then SP:SetIconShape(v, "ready") end end },
			iconBordersSquare = { order = 6.34, type = "toggle", name = "Keep Borders Square", width = 1.0,
				desc = "With Rounded or Circle icons the border follows the shape. Turn this on to keep it square. One setting for every bar (and on General > Themes).",
				hidden = function()
					local k = SP.IconShapeOf and SP:IconShapeOf("ready")
					return (k ~= "rounded" and k ~= "circle") or SV().hideBackground or SV().hideBorder
				end,
				get = function() return SP.opt and SP.opt.iconBordersSquare == true end,
				set = function(_, v) if SP.SetIconBordersSquare then SP:SetIconBordersSquare(v) end end },
			hideBorder = { order = 6.35, type = "toggle", name = "Hide Border", width = 1.0,
				desc = "Hide just the border round each reminder icon and keep the background. (Hide Background hides both.)",
				hidden = function() return SV().hideBackground end,
				get = function() return SV().hideBorder == true end, set = function(_, v) SV().hideBorder = v or nil; refresh() end },
			borderColor = { order = 6.4, type = "color", name = "Border Color", width = 1.0,
				hidden = function() return SV().hideBackground or SV().hideBorder end,
				get = function() return color(SV().borderColor, 0.2, 0.7, 1.0) end,
				set = function(_, r, g, b) SV().borderColor = { r = r, g = g, b = b }; refresh() end },
			showNames = { order = 6.5, type = "toggle", name = "Show Spell Names", desc = "The spell's name under each icon.", width = 1.0,
				get = function() return SV().showNames == true end, set = function(_, v) SV().showNames = v; refresh() end },

			readyHeader = { order = 7, type = "header", name = "When Ready" },
			readyEffect = { order = 7.1, type = "select", width = 1.0,
				-- "only while on cooldown" never shows a ready icon: the effect plays while it counts down
				name = function() return SV().mode == "cooldown" and "Effect While Shown" or "Ready Effect" end,
				desc = function()
					if SV().mode == "cooldown" then return "Plays on the icon while it is on screen, counting down the cooldown." end
					return "Plays on the icon when the spell is ready."
				end,
				values = { glow = "Glow", pulse = "Pulse", both = "Glow + pulse", none = "None" },
				get = function() return SV().readyEffect or "glow" end, set = function(_, v) SV().readyEffect = v; refresh() end },
			glowShape = { order = 7.25, type = "select", name = "Glow Shape", width = 1.0,
				desc = "The shape of the glow. The same setting as Glow Shape on General > Themes and Totem Bar > Duration Bars (it also shapes the pulse flash and the other alert glows).",
				hidden = function() local fx = SV().readyEffect or "glow"; return fx ~= "glow" and fx ~= "both" end,
				values = function() return (SP:GlowShapeValues()) end,
				sorting = function() return select(2, SP:GlowShapeValues()) end,
				get = function() return SP.opt and SP.opt.glowShape or "default" end,
				set = function(_, v) SP:SetGlowShape(v) end },
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
			soundVolume = { order = 7.5, type = "range", name = "Sound Volume", min = 0, max = 100, step = 1, width = 1.0,
				disabled = function() return not SV().soundOnReady end,
				get = function() return SV().soundVolume or 100 end, set = function(_, v) SV().soundVolume = v end },
			soundMinCooldown = { order = 7.6, type = "range", name = "Sound Only For Cooldowns Over (sec)", min = 0, max = 300, step = 5, width = 1.4,
				disabled = function() return not SV().soundOnReady end,
				get = function() return SV().soundMinCooldown or 20 end, set = function(_, v) SV().soundMinCooldown = v end },
			soundTest = { order = 7.7, type = "execute", name = "Test Sound", width = 0.8,
				disabled = function() return not SV().soundOnReady end,
				func = function() if SP.PlaySoundWithVolume then SP:PlaySoundWithVolume(SP:GetSoundFile(SV().soundName or "Raid Warning"), SV().soundVolume or 100, true) end end },

			cdHeader = { order = 8, type = "header", name = "While On Cooldown" },
			cdNote = { order = 8.05, type = "description", name = "These apply when Show is set to Always or Only while on cooldown; in Only-when-ready mode the icon is simply hidden.\n",
				hidden = function() return coolingShown() end },
			dimOpacity = { order = 8.1, type = "range", name = "Opacity While On Cooldown", min = 0.1, max = 1, step = 0.05, width = 1.2, isPercent = true,
				hidden = function() return not coolingShown() end,
				get = function() return SV().dimOpacity or 0.35 end, set = function(_, v) SV().dimOpacity = v; refresh() end },
			desaturate = { order = 8.2, type = "toggle", name = "Gray Out The Icon", width = 1.0,
				hidden = function() return not coolingShown() end,
				get = function() return SV().desaturate ~= false end, set = function(_, v) SV().desaturate = v; refresh() end },
			sweepStyle = { order = 8.3, type = "select", name = "Sweep", width = 1.0,
				hidden = function() return not coolingShown() end,
				values = { radial = "Radial (clock)", vertical = "Vertical (fills up)", none = "None" },
				get = function() return SV().sweepStyle or "radial" end, set = function(_, v) SV().sweepStyle = v; refresh() end },
			barStyle = { order = 8.4, type = "select", name = "Progress Bar", width = 1.0,
				hidden = function() return not coolingShown() end,
				values = { none = "None", below = "Below the icon", above = "Above the icon" },
				get = function() return SV().barStyle or "none" end, set = function(_, v) SV().barStyle = v; refresh() end },
			barHeight = { order = 8.5, type = "range", name = "Bar Height", min = 2, max = 12, step = 1, width = 1.0,
				hidden = function() return not coolingShown() or (SV().barStyle or "none") == "none" end,
				get = function() return SV().barHeight or 4 end, set = function(_, v) SV().barHeight = v; refresh() end },
			barColor = { order = 8.6, type = "color", name = "Bar Color", width = 1.0,
				hidden = function() return not coolingShown() or (SV().barStyle or "none") == "none" end,
				get = function() return color(SV().barColor, 0.3, 0.8, 1.0) end,
				set = function(_, r, g, b) SV().barColor = { r = r, g = g, b = b }; refresh() end },
			barGradientDirection = { order = 8.65, type = "select", name = "Bar Gradient Direction", width = 1.0,
				desc = "Where the gradient starts on this bar. Along the Bar follows the bar. Shown when Bar Gradient (Totem Bar > Duration Bars or General > Themes) is not Flat.",
				hidden = function() return not coolingShown() or (SV().barStyle or "none") == "none" or not (SP.opt and SP.opt.barGradient) end,
				values = function() return (SP:GradientDirectionValues("barGradient")) end,
				sorting = function() return select(2, SP:GradientDirectionValues("barGradient")) end,
				get = function() return SP:BarGradientDirection("other") end,
				set = function(_, v) SP:SetBarGradientDirection("other", v) end },
			showCountdown = { order = 8.7, type = "toggle", name = "Countdown Text", width = 1.0,
				hidden = function() return not coolingShown() end,
				get = function() return SV().showCountdown ~= false end,
				set = function(_, v) SV().showCountdown = v; if v and SP.EnableCountdownNumbers then SP:EnableCountdownNumbers() end; refresh() end },
			textPosition = { order = 8.8, type = "select", name = "Countdown Position", width = 1.0,
				hidden = function() return not coolingShown() or SV().showCountdown == false end,
				values = { center = "Center", top = "Top", bottom = "Bottom", below = "Below the icon", above = "Above the icon" },
				get = function() return SV().textPosition or "center" end, set = function(_, v) SV().textPosition = v; refresh() end },
			textSize = { order = 8.9, type = "range", name = "Countdown Size (0 = auto)", min = 0, max = 40, step = 1, width = 1.0,
				hidden = function() return not coolingShown() or SV().showCountdown == false end,
				get = function() return SV().textSize or 0 end, set = function(_, v) SV().textSize = v; refresh() end },

			spellsHeader = { order = 20, type = "header", name = "Spells" },
			spellsDesc = { order = 21, type = "description", name = "Only spells this client has are listed; an icon only shows once you know the spell.\n" },
	}
	-- the per-spell toggles sit directly in the section (an empty inline group renders as a blank band)
	local spellKeys = { "spellsDesc" }
	for i, entry in ipairs(SP.ReadyReminderSpells) do
		spellKeys[#spellKeys + 1] = "spell_" .. entry.key
		args["spell_" .. entry.key] = {
			order = 22 + i, type = "toggle", name = entry.optName or entry.name, width = entry.combo and "full" or 1.2,
			hidden = function() return not usable(entry) end,   -- not in this client's data, or no cooldown here
			get = function() return spellOn(entry) end,
			set = function(_, v)
				SV().spells[entry.key] = v; refresh()
				if v and entry.combo then shocksTurnedOn() end
			end,
		}
		if entry.combo then
			spellKeys[#spellKeys + 1] = "shockIcon"
			args.shockIcon = {
				order = 22 + i + 0.5, type = "select", name = "Shock Icon", width = 1.4,
				desc = "Cycle: Earth, Flame and Frost Shock take turns, fading from one to the next while the reminder is ready. Split: one icon cut into three slices. One Shock: the shock you pick below.",
				hidden = function() return not (usable(entry) and spellOn(entry)) end,
				values = { cycle = "Cycle", split = "Split", one = "One Shock" },
				sorting = { "cycle", "split", "one" },
				get = function() return shockStyle(SV()) end,
				set = function(_, v)
					local sv = SV()
					if sv.shockIcon == "earth" then sv.shockPick = "earthshock" end   -- the old choice kept its shock
					sv.shockIcon = v
					refresh()
				end,
			}
			spellKeys[#spellKeys + 1] = "shockPick"
			args.shockPick = {
				order = 22 + i + 0.6, type = "select", name = "Shock", width = 1.4,
				desc = "The shock One Shock shows.",
				hidden = function() return not (usable(entry) and spellOn(entry) and shockStyle(SV()) == "one") end,
				values = { earthshock = "Earth Shock", flameshock = "Flame Shock", frostshock = "Frost Shock" },
				sorting = { "earthshock", "flameshock", "frostshock" },
				get = function()
					local sv = SV()
					if sv.shockIcon == "earth" then return "earthshock" end
					return sv.shockPick or "earthshock"
				end,
				set = function(_, v)
					local sv = SV()
					if sv.shockIcon == "earth" then sv.shockIcon = "one" end
					sv.shockPick = v
					refresh()
				end,
			}
			spellKeys[#spellKeys + 1] = "shockKeepLast"
			args.shockKeepLast = {
				order = 22 + i + 0.7, type = "toggle", name = "Keep Showing the Last Shock", width = "full",
				desc = "Once you cast a shock, the icon stays on the shock you cast last, ready or not, until you cast a different one. With Cycle it cycles only until your first shock; with One Shock it shows your picked shock until then. It starts over after a reload.",
				hidden = function() return not (usable(entry) and spellOn(entry) and shockStyle(SV()) ~= "split") end,
				get = function() return SV().shockKeepLast == true end,
				set = function(_, v) SV().shockKeepLast = v and true or false; refresh() end,
			}
		end
	end
	SP.OrderSettingsBands({ args = args }, {
		{ keys = { "desc" } },
		{ keys = { "enabled", "mode", "onlyInCombat" } },
		{ header = "spellsHeader", name = "Spells", keys = spellKeys },
		{ header = "lookHeader", name = "Look", keys = {
			"iconSize", "opacity", "textSize", "iconShape", "hideBackground", "hideBorder", "iconBordersSquare", "borderColor", "showNames",
		}, names = { textSize = "Text Size (0 = auto)", hideBackground = "Hide Background" } },
		{ header = "readyHeader", name = "Behavior", keys = { "readyEffect", "glowColor", "glowShape" } },
		{ header = "cdHeader", name = "While On Cooldown", keys = {
			"cdNote", "dimOpacity", "desaturate", "sweepStyle", "barStyle", "barHeight", "barColor", "barGradientDirection",
			"showCountdown", "textPosition",
		} },
		{ header = "soundHeader", name = "Sound", keys = {
			"soundOnReady", "soundName", "soundTest", "soundVolume", "soundMinCooldown",
		}, names = { soundOnReady = "Play Sound", soundName = "Sound", soundVolume = "Volume" } },
		{ header = "positionHeader", name = "Position", keys = { "arrange", "gridColumns", "gridGrow", "gridAlign", "move", "unlock", "layout", "spacing", "reset" },
			names = { move = "Move", unlock = "Unlock Position", layout = "Arrange As",
				spacing = "Spacing", reset = "Reset Position" } },
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
			wake:SetScript("OnEvent", function(_, event, _, _, spellID)
				if event == "UNIT_SPELLCAST_SUCCEEDED" then noteShockCast(spellID) return end
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

-- Theme (General > Themes, spot mod.readyreminders): the existing Border Color
-- setting is the theme's Border swatch. A theme writes it exactly as the Border
-- Color option does (this module's page still shows and changes it); Standard
-- puts the player's own colour back.
if SP.ThemeSpotSettings then
	SP:ThemeSpotSettings("mod.readyreminders", {
		{ role = "border", label = "Border",
		  get = function()
			local r, g, b = color(SV().borderColor, 0.2, 0.7, 1.0)
			return { r = r, g = g, b = b }
		  end,
		  set = function(v)
			if type(v) ~= "table" then return end
			SV().borderColor = { r = v.r or v[1], g = v.g or v[2], b = v.b or v[3] }
			SP:UpdateAllReadyReminderAppearance(); SP:UpdateReadyReminders()
		  end,
		  -- ShamanPower and ShamanPower Minimal: logo blue #3FA9F5
		  shamanpower = { r = 63 / 255, g = 169 / 255, b = 245 / 255 },
		},
	})
end
