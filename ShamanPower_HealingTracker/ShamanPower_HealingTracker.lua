-- ============================================================================
-- ShamanPower [Frame Buff Indicators] (3.0.9.17, WoW: Forever only; the owner's ask, mockup A117). Built as
-- Healing Tracker: its folder, settings table and functions keep that name; players see Frame Buff Indicators.
-- Your heals' buffs on WoW: Forever's own party and raid frames: on each player who has one, its icon with the
-- game's sweep and the seconds left. Two of them, each with its own size, spot and look:
--   Riptide             (the heal over time; ranks 408521, 1239242, 1239243)
--   Ancestral Healing   (Ancestral Fortitude 16177: the armor your heals' critical hits give, 15 seconds)
-- Its own module: its own settings (ShamanPowerHealingTrackerDB), its own page (Group Tools > Frame Buff
-- Indicators), its own font (Appearance > Fonts & Textures > Frame Buff Indicators).
--
-- The game draws it: an AuraContainer per buff on each frame's unit with one slot for YOUR buff, whose button
-- wears our icon, a sweep handed over with SetDurationCooldown and a time handed over with SetDurationText.
-- Nothing is read: it shows and counts down in fights too. Built out of combat only (the game's buttons may
-- only be made then); a change asked for in a fight waits for its end.
-- ============================================================================

local SP = ShamanPower
if not SP then return end
if not (SPCompat and SPCompat.FOREVER) then return end   -- (WoW: Forever only: Riptide is a WoW: Forever spell)
SP.HealingTrackerLoaded = true

-- the buffs (WoW: Forever's spell data: each is an aura on the healed player under its own ID)
local TRACKERS = {
	{ key = "riptide",   ids = { [408521] = true, [1239242] = true, [1239243] = true }, icon = 252995 },   -- Riptide
	{ key = "ancestral", ids = { [16177] = true }, icon = 136109 },                                       -- Ancestral Fortitude
}

local function look(point)
	return { on = true, size = 14, point = point, x = 0, y = 0, sweep = true, timeText = true, textSize = 0 }
end
local defaults = {
	enabled = false,
	party = true,                      -- Party Frames (Blizzard's raid-style party frames)
	raid = true,                       -- Raid Frames
	-- each buff: shown or not, Icon Size, Position (a corner, an edge or the middle; WoW's buffs are bottom right),
	-- Offset X / Y from that spot, Show Sweep (darkens as it runs out), Show Time Left, Time Text Size (0: to the icon)
	riptide = look("TOPRIGHT"),
	ancestral = look("TOPLEFT"),
}
-- the support code (/sp support) reports only what differs from these
if SP.SUPPORT_MODULE_DEFAULTS then SP.SUPPORT_MODULE_DEFAULTS.ShamanPowerHealingTrackerDB = defaults end
SP.HealingTrackerDefaults = defaults

local function DB()
	local sv = ShamanPowerHealingTrackerDB
	if type(sv) ~= "table" then return nil end
	for k, v in pairs(defaults) do
		if type(v) == "table" then
			if type(sv[k]) ~= "table" then sv[k] = {} end
			for k2, v2 in pairs(v) do
				if sv[k][k2] == nil then sv[k][k2] = v2 end
			end
		elseif sv[k] == nil then
			sv[k] = v
		end
	end
	return sv
end

local INSET = 3          -- from the frame's edge (the health bar is 1 in, 2 more)
local SPOT = {           -- point -> the offset's direction in from that spot
	TOPLEFT = { INSET, -INSET }, TOP = { 0, -INSET }, TOPRIGHT = { -INSET, -INSET },
	LEFT = { INSET, 0 }, CENTER = { 0, 0 }, RIGHT = { -INSET, 0 },
	BOTTOMLEFT = { INSET, INSET }, BOTTOM = { 0, INSET }, BOTTOMRIGHT = { -INSET, INSET },
}

-- the frames: Blizzard's party and raid frames, by name (pets never): { name, kind }
local FRAMES
local function frameList()
	if FRAMES then return FRAMES end
	FRAMES = {}
	for i = 1, 5 do FRAMES[#FRAMES + 1] = { "CompactPartyFrameMember" .. i, "party" } end
	for i = 1, 40 do FRAMES[#FRAMES + 1] = { "CompactRaidFrame" .. i, "raid" } end
	for g = 1, 8 do
		for m = 1, 5 do FRAMES[#FRAMES + 1] = { "CompactRaidGroup" .. g .. "Member" .. m, "raid" } end
	end
	return FRAMES
end

-- recs[frame] = { frame, kind, parts = { [key] = { host, container, sig, unit, boundSig, failed, timeText } } }
local H = { recs = setmetatable({}, { __mode = "k" }), pending = false, ticker = nil }
SP.HealingTrackerState = H   -- (tests and the support code)

local function locked()
	if InCombatLockdown() then return true end
	return SP.GameAuraButtonsLocked and SP:GameAuraButtonsLocked() or false
end

-- the seconds left, rounded up ("12"), minutes from 60 ("2m"); nil = the game's own
local formatter
local function timeFormatter()
	if formatter ~= nil then return formatter or nil end
	formatter = false
	local S = C_StringUtil
	if not (S and S.CreateNumericRuleFormatter) then return nil end
	local ok, made = pcall(S.CreateNumericRuleFormatter)
	if not (ok and made and made.AddBreakpoint) then return nil end
	local up = Enum and Enum.NumericRuleFormatRounding and Enum.NumericRuleFormatRounding.Up or 1
	if not pcall(made.AddBreakpoint, made, { threshold = 0, step = 1, rounding = up, format = "%d" }) then return nil end
	pcall(made.AddBreakpoint, made, { threshold = 60, format = "%dm", components = { { div = 60, step = 1, rounding = up } } })
	formatter = made
	return made
end

local function textSize(o)
	local n = tonumber(o.textSize) or 0
	if n > 0 then return n end
	return math.max(7, math.floor((tonumber(o.size) or 14) * 0.62 + 0.5))
end

-- where the icon sits on its frame (ours: moved any time out of combat)
local function place(part, frame, o)
	local h = part.host
	local size = tonumber(o.size) or 14
	local point = SPOT[o.point] and o.point or "TOPRIGHT"
	local d = SPOT[point]
	h:ClearAllPoints()
	h:SetSize(size, size)
	h:SetPoint(point, frame, point, d[1] + (tonumber(o.x) or 0), d[2] + (tonumber(o.y) or 0))
	h:SetFrameLevel(frame:GetFrameLevel() + 10)
end

-- The game's slot for one buff on one frame's unit: our icon, its sweep and its time left, made ONCE. Every look
-- change after that goes onto these same parts (dress, below): a slot made again shows a buff that is already
-- running only from its next cast (the owner's test, 11-18: a new Icon Size waited for the next Riptide).
local function build(part, t, o)
	local host = part.host
	local ok, c = pcall(CreateFrame, "AuraContainer", nil, host, "CustomAuraContainerTemplate")
	if not (ok and c and type(c.AddAuraSlot) == "function") then part.failed = true return nil end
	c:SetAllPoints(host)
	c:SetFrameLevel(host:GetFrameLevel() + 1)
	if c.SetEditModePreviewEnabled then pcall(c.SetEditModePreviewEnabled, c, false) end
	local px = textSize(o)
	local okSlot = pcall(c.AddAuraSlot, c, t.key, "HELPFUL|PLAYER", {   -- your buff only
		candidateFilters = { includeSpellIDs = t.ids },
		initializeFrame = function(button)
			button:ClearAllPoints()
			button:SetAllPoints(host)
			if button.SetMouseClickEnabled then pcall(button.SetMouseClickEnabled, button, false) end
			if button.SetMouseMotionEnabled then pcall(button.SetMouseMotionEnabled, button, false) end
			local edge = button:CreateTexture(nil, "BACKGROUND")
			edge:SetAllPoints(button)
			edge:SetColorTexture(0, 0, 0, 1)
			local icon = button:CreateTexture(nil, "ARTWORK")
			icon:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
			icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
			icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			icon:SetTexture(t.icon)
			pcall(button.SetIcon, button, icon)
			-- the sweep and the time left are always made and handed over: Show Sweep / Show Time Left only
			-- show or hide them (dress)
			local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
			cd:SetAllPoints(icon)
			cd:SetDrawEdge(false)
			cd:SetDrawBling(false)
			cd:SetHideCountdownNumbers(true)   -- (the time left is our own string, below)
			cd:SetReverse(true)                -- darkens as it runs out, as the game's buff icons do
			cd:SetSwipeColor(0, 0, 0, 0.65)
			pcall(button.SetDurationCooldown, button, cd)
			part.cd = cd
			local texts = CreateFrame("Frame", nil, button)   -- (ours: shown or hidden for Show Time Left)
			texts:SetAllPoints(button)
			texts:SetFrameLevel(button:GetFrameLevel() + 5)
			local fs = texts:CreateFontString(nil, "OVERLAY")
			SP:SetSPFont(fs, "healing", px, "OUTLINE")
			SP:SPFontGameOwned(fs)
			fs:SetPoint("CENTER", button, "CENTER", 0, 0)
			fs:SetTextColor(1, 1, 1)
			local fmt = timeFormatter()
			pcall(button.SetDurationText, button, fs, fmt and { textFormatter = fmt } or {})
			part.texts, part.timeText, part.px = texts, fs, px
		end,
	})
	if not okSlot then
		c:Hide()
		part.failed = true
		return nil
	end
	return c
end

-- the look, on the slot's own parts (out of combat): Show Sweep, Show Time Left, Time Text Size
local function dress(part, o)
	if part.cd then pcall(part.cd.SetDrawSwipe, part.cd, o.sweep ~= false) end
	if part.texts then pcall(part.texts.SetShown, part.texts, o.timeText ~= false) end
	local px = textSize(o)
	if part.timeText and part.px ~= px then
		SP:SetSPFont(part.timeText, "healing", px, "OUTLINE")
		part.px = px
	end
end

local function bind(part, unit)
	part.unit = unit
	if not part.container then return end
	pcall(part.container.SetUnit, part.container, unit)
	pcall(part.container.SetEnabled, part.container, unit ~= nil)
	if unit then pcall(part.container.UpdateAllAuras, part.container) end
end

local function hidePart(part)
	part.host:Hide()
	if part.container then pcall(part.container.SetEnabled, part.container, false) end
	part.unit = nil   -- (shown again: bound again)
end

-- one frame brought up to date: each buff's slot made, placed, bound to the frame's unit, shown or not
local function sync(frame, sv, kind)
	if not kind then return end
	local rec = H.recs[frame]
	local frameOn = sv.enabled == true and sv[kind] ~= false
	if not frameOn and not rec then return end
	if not rec then
		rec = { frame = frame, kind = kind, parts = {} }
		H.recs[frame] = rec
	end
	for _, t in ipairs(TRACKERS) do
		local o = sv[t.key]
		local part = rec.parts[t.key]
		if not (frameOn and o.on ~= false) then
			if part then hidePart(part) end
		else
			if not part then
				part = { host = CreateFrame("Frame", nil, frame) }
				rec.parts[t.key] = part
			end
			place(part, frame, o)
			if not part.container and not part.failed then
				part.container = build(part, t, o)
			end
			dress(part, o)
			local unit = frame.unit
			if part.unit ~= unit then bind(part, unit) end
			part.host:Show()
		end
	end
end

local ev = CreateFrame("Frame")

local queued = false
local function soon()
	if queued then return end
	queued = true
	C_Timer.After(0.1, function() queued = false; SP:UpdateHealingTracker() end)
end

-- a frame handed another player (the game does this out of combat): bound again.
-- (3.0.9.18, denko on Discord, 11-19, in dungeons: "calling '?' on bad self (Attempt to access forbidden object from
-- code tainted by an AddOn)", 903 times in his support code) this module watched the game's shared
-- CompactUnitFrame_SetUnit, which the nameplates go through too, forbidden ones included (Forever's Blizzard_NamePlates:
-- FORBIDDEN_NAME_PLATE_CREATED), and asked each frame its name. Now only the party and raid frames themselves are
-- watched, each for its own "unit" (CompactUnitFrame_SetUnit sets it on the frame): nothing else reaches this module
local watched = setmetatable({}, { __mode = "k" })
local function watch(f)
	if watched[f] then return end
	watched[f] = true
	local ok, err = pcall(f.HookScript, f, "OnAttributeChanged", function(_, name)
		if name == "unit" then soon() end
	end)
	if not ok then geterrorhandler()(err) end   -- (a roster change still binds the frame again)
end
H.watched = watched   -- (tests)

-- everything brought up to date; in a fight (or while the game hides auras) it waits
function SP:UpdateHealingTracker()
	local sv = DB()
	if not sv then return end
	if locked() then
		if not H.pending then
			H.pending = true
			ev:RegisterEvent("PLAYER_REGEN_ENABLED")
			if not H.ticker then   -- (the game can hide auras out of a fight too: looked at again each second)
				H.ticker = C_Timer.NewTicker(1, function() if not locked() then SP:UpdateHealingTracker() end end)
			end
		end
		return
	end
	H.pending = false
	ev:UnregisterEvent("PLAYER_REGEN_ENABLED")
	if H.ticker then H.ticker:Cancel() H.ticker = nil end
	local seen = {}
	for _, e in ipairs(frameList()) do
		local f = _G[e[1]]
		if f then seen[f] = true; watch(f); sync(f, sv, e[2]) end
	end
	for f, rec in pairs(H.recs) do   -- (a frame made under another name: kept up to date as well)
		if not seen[f] then sync(f, sv, rec.kind) end
	end
end

-- a settings change: the page calls this
function SP:UpdateHealingTrackerAppearance()
	self:UpdateHealingTracker()
end

-- The settings page's way in (ShamanPower_Config/HealingIcons.lua): each buff's own values. The page never stores one.
local KEYS = { riptide = true, ancestral = true }
function SP:HealingOpt(key, name)
	local sv = DB()
	local o = sv and KEYS[key] and sv[key]
	if type(o) ~= "table" then return defaults[key] and defaults[key][name] end
	return o[name]
end
function SP:SetHealingOpt(key, name, v)
	local sv = DB()
	if not (sv and KEYS[key]) then return end
	sv[key][name] = v
	self:UpdateHealingTracker()
end
-- a value changed from its starting one (the page's blue)
function SP:HealingOptOwn(key, name)
	local def = defaults[key]
	return def ~= nil and self:HealingOpt(key, name) ~= def[name]
end
function SP:HealingOwnChanged(key)
	for name in pairs(defaults[key] or {}) do
		if name ~= "on" and self:HealingOptOwn(key, name) then return true end
	end
	return false
end
-- Reset This Icon: back to its starting values (shown or hidden stays as it is)
function SP:ResetHealingBuff(key)
	local sv = DB()
	if not (sv and KEYS[key]) then return end
	for name, v in pairs(defaults[key]) do
		if name ~= "on" then sv[key][name] = v end
	end
	self:UpdateHealingTracker()
end
-- Copy Settings To: the look once, never linked; never the spot (the two would sit on each other)
local SPOT_KEYS = { on = true, point = true, x = true, y = true }
function SP:CopyHealingBuff(from, to)
	local sv = DB()
	if not (sv and KEYS[from] and KEYS[to]) or from == to then return end
	for name in pairs(defaults[from]) do
		if not SPOT_KEYS[name] then sv[to][name] = sv[from][name] end
	end
	self:UpdateHealingTracker()
end

-- the page's Reset: back to the starting settings
function SP:HealingTrackerReset()
	local sv = ShamanPowerHealingTrackerDB
	if type(sv) == "table" then
		for k in pairs(sv) do sv[k] = nil end
	end
	self:UpdateHealingTracker()
end

ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("GROUP_ROSTER_UPDATE")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		if type(ShamanPowerHealingTrackerDB) ~= "table" then ShamanPowerHealingTrackerDB = {} end
	end
	local sv = DB()
	if not (sv and (sv.enabled or next(H.recs))) then return end   -- (off and never made: nothing to do)
	soon()
end)

-- /sp support: what it is doing
function SP:HealingTrackerStatus()
	local sv = DB() or {}
	local out = {}
	for _, t in ipairs(TRACKERS) do
		local o = sv[t.key] or {}
		local n, made, failed, bound = 0, 0, 0, 0
		for _, rec in pairs(H.recs) do
			local part = rec.parts[t.key]
			if part then
				n = n + 1
				if part.container then made = made + 1 end
				if part.failed then failed = failed + 1 end
				if part.unit then bound = bound + 1 end
			end
		end
		out[#out + 1] = ("%s on=%s size=%s point=%s frames=%d made=%d failed=%d bound=%d"):format(
			t.key, tostring(o.on), tostring(o.size), tostring(o.point), n, made, failed, bound)
	end
	return ("enabled=%s party=%s raid=%s waiting=%s; %s"):format(tostring(sv.enabled), tostring(sv.party),
		tostring(sv.raid), tostring(H.pending), table.concat(out, "; "))
end
