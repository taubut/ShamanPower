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
local GetSpellTextureC = (C_Spell and C_Spell.GetSpellTexture) or GetSpellTexture

-- SavedVariables
ShamanPower_ReadyReminders = ShamanPower_ReadyReminders or {}

local DEFAULTS = {
	-- On for WoW: Forever (no WeakAuras there); opt-in on Anniversary, where most
	-- players already cover this with WeakAuras. The setup tour and settings turn it on.
	enabled = (SPCompat.FOREVER),
	mode = "ready",        -- "ready": show only when ready | "cooldown": show only while on cooldown | "always": dim + countdown on cooldown
	                       -- | "flash": never on screen, only the Ready Flash
	onlyInCombat = false,
	-- D51: with Only In Combat on, the icon fades to fadeOpacity out of combat instead of
	-- hiding (the page's default; each icon sets its own in its right-click menu)
	fadeInsteadOfHide = false,
	fadeOpacity = 0.4,
	-- D52: the buff the spell puts on you, shown with its icon (each icon sets its own in
	-- its right-click menu; these are what an icon that never set one uses)
	buffLook = "off",      -- off | corner (in the icon's corner) | own (as its own icon) | edge (round the icon)
	buffCorner = "tr",     -- corner: tr | tl | br | bl
	buffSize = 0.45,       -- corner: its size, a share of the icon's (30% to 70%)
	buffSide = "above",    -- own icon: above | below | left | right | spot (In Its Own Spot)
	buffOwnSize = 1.0,     -- own icon: its size, a share of the icon's (30% to 100%)
	buffTime = true,       -- the time it has left, in whole seconds
	buffGoldUnder = 3,     -- seconds: the time turns WoW's gold under this (0 = never)
	-- edge: WoW's mana-bar blue (PowerBarColor.MANA, read from the game; 0, 0, 1 on both)
	buffEdgeColor = (function()
		local all = rawget(_G, "PowerBarColor")
		local m = type(all) == "table" and type(all.MANA) == "table" and all.MANA or nil
		if not (m and type(m.r) == "number" and type(m.g) == "number" and type(m.b) == "number") then return { r = 0, g = 0, b = 1 } end
		return { r = m.r, g = m.g, b = m.b }
	end)(),
	buffPositions = {},    -- [key] = { anchor, x, y }: a buff In Its Own Spot, once moved (none: above its icon)
	iconSize = 48,
	opacity = 1.0,
	dimOpacity = 0.35,     -- "always" mode, while on cooldown
	desaturate = true,     -- "always" mode, while on cooldown
	sweepStyle = "radial", -- "always" mode: radial | vertical | none
	sweepDirection = "bottom", -- vertical: the color returns from this edge (top | bottom)
	barStyle = "none",     -- "always" mode: none | below | above  (thin bar draining with the cooldown)
	barHeight = 4,
	barColor = { r = 0.3, g = 0.8, b = 1.0 },
	showCountdown = true,  -- "always" mode
	countdownUnder = 0,    -- seconds: the countdown shows only once less is left (0 = always)
	textPosition = "center", -- center | top | bottom | below | above
	textSize = 0,          -- 0 = automatic from icon size
	readyEffect = "glow",  -- glow | pulse | both | none
	glowColor = { r = 0.3, g = 0.8, b = 1.0 },
	borderColor = { r = 0.2, g = 0.7, b = 1.0 },
	outOfRange = false,    -- Show Out of Range, for every icon (an icon's own setting wins)
	rangeLook = "red",     -- red | gray | dim
	-- Red Tint: the game's own out-of-range icon red (its Cooldown Manager's ITEM_NOT_IN_RANGE_COLOR)
	rangeColor = { r = 0.64, g = 0.15, b = 0.15 },
	hideBackground = false,
	showNames = false,     -- spell name under each icon
	soundOnReady = false,
	soundName = "Raid Warning",
	soundVolume = 100,
	soundMinCooldown = 20, -- seconds; shorter cooldowns never make a sound
	-- Ready Flash (D38): a big copy of the icon on its own spot when the spell is ready
	flash = false,
	flashAnim = "grow",    -- grow (and fade) | pop | fade (only)
	flashSize = 96,
	flashHold = 1.0,       -- seconds on screen, start to finish
	flashEarly = 0,        -- seconds before it is ready (0 = the moment it is ready)
	flashName = false,     -- the spell's name under it
	flashMin = 10,         -- seconds; shorter cooldowns never flash (an icon's own On always does)
	-- flashPos = { anchor, x, y }: its spot (nil = the default, a little above the middle)
	flashPositions = {},   -- [key] = { point, x, y }: a spell's own flash spot (none: the shared one)
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
	icons = {},            -- [key] = { setting = value }: an icon's own settings (nil = the page's)
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
for i, e in ipairs(SP.ReadyReminderSpells) do
	e.order = i
	catalogByKey[e.key] = e
	if not e.combo then
		for _, id in ipairs(e.ids) do
			local name = SPCompat.SpellName(id)
			if name then e.name = SPCompat.SpellLabel(id, e.name) break end
		end
	end
end

-- D52: the buff each spell puts on you, on this game (its display: "Your buff on its
-- Ready Reminder", below). One table for all of it (this file is near Lua's 200 locals).
local Buff = { of = {}, list = {}, formatters = {}, proxies = {},
	KEY = { buffLook = true, buffCorner = true, buffSize = true, buffSide = true, buffOwnSize = true, buffTime = true,
		buffGoldUnder = true, buffEdgeColor = true } }
-- a buff setting copied or pasted onto an icon whose spell puts no buff on you here: left out
function Buff.Skip(key, opt)
	return Buff.KEY[opt] == true and not (catalogByKey[key] and catalogByKey[key].buff)
end
do
	-- Every buff by spell ID, from each game's own data (SpellName / SpellEffect /
	-- SpellMisc / ItemSet, read 2026-10-06, and Wowhead's tooltips for each game); each has
	-- one rank. talent / setBonus: what puts the buff in reach (the menu says when it is
	-- missing). timed = false: it lasts until used, so it has no time left to show.
	local list
	if SPCompat.FOREVER then
		list = {
			-- Improved Stormstrike: the talent 1223031 (trait node 104742, 2 points) gives the
			-- buff 1238931 (15 s) when you Stormstrike
			stormstrike = { ids = { 1238931 }, name = "Improved Stormstrike", talent = 1223031, node = 104742 },
		}
	else
		list = {
			-- no Improved Stormstrike here: Stormstrike's buff is Stormpower (38430, 12 s), from the
			-- 4-piece bonus 38432 of the Skyshatter Harness (item set 682, any 4 of its 8 pieces)
			stormstrike = { ids = { 38430 }, name = "Stormpower", setBonus = 38432, setID = 682, setName = "Skyshatter Harness",
				setItems = { 31018, 31011, 31015, 31021, 31024, 34567, 34439, 34545 } },
		}
	end
	for _, e in ipairs(SP.ReadyReminderSpells) do
		local b = list[e.key]
		if b then
			b.timed = b.timed ~= false
			b.map = {}
			for _, id in ipairs(b.ids) do b.map[id] = true end
			if b.setItems then
				b.setMap = {}
				for _, id in ipairs(b.setItems) do b.setMap[id] = true end
			end
			b.label = SPCompat.SpellLabel(b.ids[1], b.name) or b.name
			e.buff = b
			Buff.list[#Buff.list + 1] = e
		end
	end
end

-- Filling in the defaults walks every one of them, and SV() is called about 20
-- times per update pass. So the walk runs only when the saved table is a new one
-- (it loaded, an import replaced it), when a theme reset cleared one of the
-- colors, and once a second besides (a setting cleared some other way); every
-- other call hands the table straight back.
local filledFor, filledAt = nil, 0
-- Bumped on every settings write (the options, an icon's menu, an import, a theme,
-- Reset This Icon ...) and whenever SV() finds a new table or a cleared value:
-- IconOpt's kept answers are thrown away then.
local optGen = 1
local function SV()
	local sv = ShamanPower_ReadyReminders
	local now = GetTime()
	if sv == filledFor and now - filledAt < 1 and sv.borderColor ~= nil and sv.glowColor ~= nil and sv.barColor ~= nil
		and sv.rangeColor ~= nil and sv.buffEdgeColor ~= nil then
		return sv
	end
	local changed = sv ~= filledFor
	filledFor, filledAt = sv, now
	for k, v in pairs(DEFAULTS) do
		if sv[k] == nil then
			changed = true
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
	if type(sv.icons) ~= "table" then sv.icons = {}; changed = true end   -- (a damaged import)
	if changed then optGen = optGen + 1 end
	return sv
end

-- ---------------------------------------------------------------------------
-- Settings per icon: SV().icons[catalog key] holds only what an icon sets for
-- itself; everything else follows the page. An explicit value (false too) wins,
-- nil follows the page. IconOpt is the one way an icon's setting is read: the
-- answers are kept per icon until a setting changes (optGen), so an update pass
-- reads plain fields and builds nothing.
-- ---------------------------------------------------------------------------
local ICON_KEYS = { "mode", "outOfRange", "readyEffect", "glowColor", "soundOnReady", "soundName",
	"onlyInCombat", "showCountdown", "iconSize", "countdownUnder", "flash",
	"flashAnim", "flashSize", "flashHold", "flashEarly", "flashName",
	-- D40: every setting the page had is the icon's own now (the page's saved value is
	-- what an icon that never set one uses, so nothing on screen changed on the update)
	"opacity", "dimOpacity", "desaturate", "sweepStyle", "sweepDirection", "barStyle", "barHeight", "barColor",
	"textPosition", "textSize", "borderColor", "rangeLook", "rangeColor", "hideBackground", "hideBorder",
	"showNames", "soundVolume", "soundMinCooldown", "flashMin",
	-- D51: Fade Instead of Hide (with Only In Combat) and its Faded Opacity
	"fadeInsteadOfHide", "fadeOpacity",
	-- D52: the buff the spell puts on you, on its icon
	"buffLook", "buffCorner", "buffSize", "buffSide", "buffOwnSize", "buffTime", "buffGoldUnder", "buffEdgeColor" }
local ICON_KEY = {}
for _, k in ipairs(ICON_KEYS) do ICON_KEY[k] = true end
local resolved = {}   -- [catalog key] = { gen = n, <setting> = value }: one table per icon, made once
local function IconOpt(entry, key)
	local r = resolved[entry.key]
	if not r then r = {}; resolved[entry.key] = r end
	if r.gen ~= optGen or ShamanPower_ReadyReminders ~= filledFor then   -- (a new saved table: SV() moves optGen)
		local sv = SV()
		local own = type(sv.icons) == "table" and sv.icons[entry.key] or nil
		if type(own) ~= "table" then own = nil end
		for i = 1, #ICON_KEYS do
			local k = ICON_KEYS[i]
			local v = own and own[k]
			if v == nil then v = sv[k] end
			r[k] = v
		end
		-- its own Show (not the page's): an icon set to "only while on cooldown" draws
		-- as the page does in that mode (see coolingLook)
		local ownMode
		if own then ownMode = own.mode end
		r.ownMode = ownMode
		-- its own Sound When Ready turned on: it plays whatever its cooldown (see readySound)
		r.ownSound = own ~= nil and own.soundOnReady == true
		-- its own Ready Flash turned on: it flashes whatever its cooldown (see flashWanted)
		r.ownFlash = own ~= nil and own.flash == true
		-- its own cooling look (Gray Out / Opacity While On Cooldown) set (see coolingLook)
		r.ownCoolLook = own ~= nil and (own.desaturate ~= nil or own.dimOpacity ~= nil)
		r.gen = optGen
	end
	return r[key]
end

-- the icons' own settings, always a table (even straight after a damaged import)
local function iconTable()
	local sv = SV()
	if type(sv.icons) ~= "table" then sv.icons = {}; optGen = optGen + 1 end
	return sv.icons
end

-- Everything that shows an icon's settings (the Your Icons row and its menu in
-- the settings window) hears about a change once, on the next frame.
local watchers, watchQueued = {}, false
local function runWatchers()
	watchQueued = false
	for i = 1, #watchers do
		local ok, err = pcall(watchers[i])
		if not ok then geterrorhandler()(err) end
	end
end
local function settingsChanged()
	optGen = optGen + 1
	if #watchers > 0 and not watchQueued then
		watchQueued = true
		C_Timer.After(0, runWatchers)
	end
end
function SP.ReadyReminderWatch(_, fn)
	if type(fn) == "function" then watchers[#watchers + 1] = fn end
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
		known = SPCompat.KnowsSpellID(id)
	end
	knownCache[entry.key] = known
	return known
end

local GCD_MAX = 1.6   -- a "cooldown" this short is only the global cooldown

-- start, duration (plain numbers) for the highest known rank, or nil when unreadable.
local function ownCooldownOf(entry)
	local id = clientSpellID(entry)
	if not id then return nil end
	local name = SPCompat.SpellName(id)
	local start, duration = GetSpellCooldownC(name or id)
	if type(start) ~= "number" or type(duration) ~= "number" then return nil end
	return start, duration
end

-- Earth, Flame and Frost Shock share one cooldown (category 19 in the spell data).
-- WoW: Forever in combat: the compat model knows only the shock that was cast, so
-- the other two read ready while the shared cooldown runs. A shock with no run of
-- its own takes the family's. ownOnly: the game's own flags already say whether
-- this shock is cooling (they report the shared cooldown), so it keeps its own.
local IS_MAINLINE = (SPCompat.FOREVER)
local SHOCK_FAMILY = { "earthshock", "flameshock", "frostshock" }
local isShock = { earthshock = true, flameshock = true, frostshock = true }
local function cooldownOf(entry, ownOnly)
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
	if IS_MAINLINE and not ownOnly and isShock[entry.key] and not (duration and duration > GCD_MAX) then
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
-- is placed from Earth Shock, below), so adding it moved nobody's icons. Each
-- spot is as wide as that icon's own Icon Size, so a bigger one never overlaps
-- its neighbors (every icon at the page's size: the same spots as before).
local function defaultPos(entry)
	local sv = SV()
	local gap = sv.spacing or 8
	if entry.combo then
		-- Earth Shock's spot when its own reminder is off (the three singles hidden),
		-- else one step before it (half of each icon, and the gap)
		local es = catalogByKey.earthshock
		local p = sv.positions.earthshock or defaultPos(es)
		local x, y = p.x or 0, p.y or 0
		local v = sv.spells.earthshock
		if v == nil then v = es.def end
		if v then
			local step = ((IconOpt(es, "iconSize") or 48) + (IconOpt(entry, "iconSize") or 48)) / 2 + gap
			if sv.layout == "column" then y = y + step else x = x - step end
		end
		return { point = p.point or "CENTER", x = x, y = y }
	end
	local total, before = -gap, 0
	for _, e in ipairs(SP.ReadyReminderSpells) do
		if not e.combo then
			local cell = (IconOpt(e, "iconSize") or 48) + gap
			total = total + cell
			if e.order < entry.order then before = before + cell end
		end
	end
	local off = before + (IconOpt(entry, "iconSize") or 48) / 2 - total / 2   -- its center, the row centered
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
	local spells = sv.spells
	byCatalog = byCatalog and true or false
	local changed = gridDirty or byCatalog ~= gridByCatalog
	wipe(gridList)
	local enabled, nVis, biggest = 0, 0, 0
	for _, entry in ipairs(SP.ReadyReminderSpells) do
		local on = spells[entry.key]   -- spellOn(), without its SV() call
		if on == nil then on = entry.def end
		if on and usable(entry) then
			enabled = enabled + 1
			local sz = IconOpt(entry, "iconSize") or 48
			if sz > biggest then biggest = sz end
		end
		local f = frames[entry.key]
		if f then
			local mode = IconOpt(entry, "mode") or "ready"
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

	-- the cell of the biggest icon: every icon the page's Icon Size = today's grid exactly
	local size, gap, perRow = biggest > 0 and biggest or (sv.iconSize or 48), sv.spacing or 8, sv.gridColumns or 6
	local grow, align = sv.gridGrow or "down", sv.gridAlign or "center"
	local k = gridKey
	if k.enabled ~= enabled or k.size ~= size or k.gap ~= gap or k.perRow ~= perRow or k.grow ~= grow or k.align ~= align
		or k.gen ~= optGen then   -- an icon's own Icon Size
		changed = true
		k.enabled, k.size, k.gap, k.perRow, k.grow, k.align, k.gen = enabled, size, gap, perRow, grow, align, optGen
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

	-- Row by row: a row is as tall as its tallest icon on screen, each icon sits in
	-- the middle of its row's height, and Align Rows places the row's icons on screen
	-- (the rest trail after them). Rows stack down from the block's top, or up from
	-- its bottom.
	local up = grow == "up"
	local count = #gridList
	local rowTop = 0   -- down: this row's top under the block's top; up: its bottom over the block's bottom
	for first = 1, count, cols do
		local last = math.min(count, first + cols - 1)
		local inRow = math.min(cols, nVis - (first - 1))   -- icons on screen in this row
		local rowW, rowH = 0, 0
		if inRow > 0 then
			for i = first, first + inRow - 1 do
				local sz = IconOpt(gridList[i].entry, "iconSize") or 48
				rowW = rowW + sz + gap
				if sz > rowH then rowH = sz end
			end
			rowW = rowW - gap
		else
			rowW = W   -- none on screen: they sit from the left, as a full row would
			for i = first, last do
				local sz = IconOpt(gridList[i].entry, "iconSize") or 48
				if sz > rowH then rowH = sz end
			end
		end
		local x = align == "left" and 0 or align == "right" and (W - rowW) or (W - rowW) / 2
		for i = first, last do
			local f = gridList[i]
			local sz = IconOpt(f.entry, "iconSize") or 48
			local y = -rowTop - (rowH - sz) / 2
			if up then y = -(H - rowTop - rowH) - (rowH - sz) / 2 end
			if f.gridX ~= x or f.gridY ~= y or f.gridAnchored ~= a then
				f:ClearAllPoints(); f:SetPoint("TOPLEFT", a, "TOPLEFT", x, y)
				f.gridX, f.gridY, f.gridAnchored = x, y, a
			end
			x = x + sz + gap
		end
		rowTop = rowTop + rowH + gap
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
	local size = IconOpt(entry, "iconSize") or 48
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
	-- vertical sweep: a gray sheet shrinks toward the edge opposite the returning color
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
		if button ~= "RightButton" then return end
		-- the settings page with this icon's own menu open (ShamanPower_Config ReadyIcons.lua)
		if SP.ReadyReminderOpenIconMenu then SP:ReadyReminderOpenIconMenu(self.entry.key)
		elseif ShamanPowerConfig then ShamanPowerConfig:Open({ "fluffy", "readyreminders_section" }) end
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
	if (issecretvalue and issecretvalue(spellID)) or spellID == nil then return end
	local key = shockKeyOf[spellID]
	if key == nil then
		key = false
		local name = SPCompat.SpellName(spellID)
		if name then
			for _, k in ipairs(SHOCK_FAMILY) do
				local e = catalogByKey[k]
				local id = e and clientSpellID(e)
				if id and SPCompat.SpellName(id) == name then key = k break end
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

-- The icon's look, on the icon and every texture drawn with it (the Shocks
-- crossfade, the split slices): Gray Out while it cools (f.desatCool) and the
-- out-of-range look while its spell cannot reach the target (f.oorLook: "red",
-- "gray" or "dim"). The two stack, and each comes off exactly when it ends.
-- Repainted only when something in it changed (any setting change repaints once).
-- how light Gray and Dim leave the icon (the D29 mock: 25% / 55% toward black)
local RANGE_GRAY, RANGE_DIM = 0.75, 0.45
-- the icon's own Out of Range look (red | gray | dim)
local function rangeLookOf(f)
	local l = IconOpt(f.entry, "rangeLook")
	if l == "gray" or l == "dim" then return l end
	return "red"
end
local function lookOn(f, tex)
	local look = f.oorLook
	tex:SetDesaturated((f.desatCool or look == "gray") and true or false)
	if look == "red" then tex:SetVertexColor(color(IconOpt(f.entry, "rangeColor"), 0.64, 0.15, 0.15))
	elseif look == "gray" then tex:SetVertexColor(RANGE_GRAY, RANGE_GRAY, RANGE_GRAY)
	elseif look == "dim" then tex:SetVertexColor(RANGE_DIM, RANGE_DIM, RANGE_DIM)
	else tex:SetVertexColor(1, 1, 1) end
end
local function paintIcon(f)
	local d = (f.desatCool or f.oorLook == "gray") and true or false
	if f.lkD == d and f.lkL == f.oorLook and f.lkG == optGen then return end
	f.lkD, f.lkL, f.lkG = d, f.oorLook, optGen
	lookOn(f, f.icon)
	if f.icon2 then lookOn(f, f.icon2) end
	if f.slices then
		for i = 2, 3 do if f.slices[i] then lookOn(f, f.slices[i]) end end
	end
end
local function setDesat(f, on)
	f.desatCool = on and true or false
	paintIcon(f)
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
	lookOn(f, f.icon2)   -- gray / out of range, as the icon it fades over
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
	local iw = (IconOpt(f.entry, "iconSize") or 48) - 4   -- the icon sits 2 px inside the frame
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
			lookOn(f, sl)   -- gray / out of range, as the icon under it
			sl:Show()
		elseif sl then
			sl:Hide()
		end
	end
	if style == "split" then setIconTex(f, f.cycTex[1]) else shockIcon(f, false) end   -- the ready pass starts a cycle
end

function SP:UpdateReadyReminderAppearance(key)
	local f = frames[key]; if not f then return end
	local e = f.entry
	local size = IconOpt(e, "iconSize") or 48
	f:SetSize(size, size)
	-- Fills Back In: the remaining gray sheet sits opposite the edge where color returns.
	local fromTop = IconOpt(e, "sweepDirection") == "top"
	f.overlay:ClearAllPoints()
	if fromTop then
		f.overlay:SetPoint("BOTTOMLEFT", f.icon, "BOTTOMLEFT", 0, 0)
		f.overlay:SetPoint("BOTTOMRIGHT", f.icon, "BOTTOMRIGHT", 0, 0)
	else
		f.overlay:SetPoint("TOPLEFT", f.icon, "TOPLEFT", 0, 0)
		f.overlay:SetPoint("TOPRIGHT", f.icon, "TOPRIGHT", 0, 0)
	end
	-- countdown text: size and position
	local tsz = IconOpt(e, "textSize")
	local ts = (tsz and tsz > 0) and tsz or math.max(10, math.floor(size * 0.34))
	SP:SetSPFont(f.count, "alerts", ts, "OUTLINE")
	f.count:ClearAllPoints()
	local tp = IconOpt(e, "textPosition") or "center"
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
	local hideBg = IconOpt(e, "hideBackground") and true or false
	local borderOn = not hideBg and not IconOpt(e, "hideBorder")
	local ringFile = SP.BorderRingFile and SP:BorderRingFile("ready")
	f.bg:SetShown(not hideBg); f.border:SetShown(borderOn and not ringFile)
	f.border:SetBackdropBorderColor(color(IconOpt(e, "borderColor"), 0.2, 0.7, 1.0))
	if ringFile then
		if not f.ring then
			f.ring = f:CreateTexture(nil, "OVERLAY")
			f.ring:SetAllPoints(f.border)
		end
		if f.ring.spFile ~= ringFile then f.ring:SetTexture(ringFile); f.ring.spFile = ringFile end
		f.ring:SetVertexColor(color(IconOpt(e, "borderColor"), 0.2, 0.7, 1.0))
		f.ring:SetShown(borderOn)
	elseif f.ring then
		f.ring:Hide()
	end
	f.glow:SetVertexColor(color(IconOpt(e, "glowColor"), 0.3, 0.8, 1.0))
	local namesOn = IconOpt(e, "showNames") == true
	f.label:SetShown(namesOn)
	-- bar placement
	local barStyle = IconOpt(e, "barStyle")
	local bh = IconOpt(e, "barHeight") or 4
	f.bar:ClearAllPoints(); f.bar:SetHeight(bh)
	if barStyle == "above" then
		f.bar:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, 2); f.bar:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 0, 2)
	else
		f.bar:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -2); f.bar:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, -2)
	end
	f.bar:SetStatusBarColor(color(IconOpt(e, "barColor"), 0.3, 0.8, 1.0))
	if barStyle == "above" and namesOn then f.label:ClearAllPoints(); f.label:SetPoint("TOP", f, "BOTTOM", 0, -3) end
	if f.entry.combo then
		applyShockLook(f)
	else
		local id = clientSpellID(f.entry)
		local tex = id and GetSpellTextureC(id)
		f.icon:SetTexture(tex or 136024)
	end
	f:SetAlpha((IconOpt(e, "opacity") or 1) * (f.fade or 1))   -- (D51: below 1 only while faded)
	applyPos(f)
	styleEngine(f)
end

local rangeRepaintAll   -- the out-of-range look, defined with the range check below

function SP:UpdateAllReadyReminderAppearance()
	settingsChanged()   -- any setting may have changed: each icon reads its own settings again
	for key, f in pairs(frames) do self:UpdateReadyReminderAppearance(key); applyPos(f) end   -- positions too: an import replaces them
	if gridAnchor then applyGridPos() end   -- an import replaces the grid's spot as well
	gridDirty = true   -- any setting may have changed
	layoutGrid(self.readyPositioning)
	rangeRepaintAll()   -- the Out of Range look or color may have changed
	if self.ReadyFlashRefresh then self:ReadyFlashRefresh() end   -- (defined below, with the flash)
	Buff.LayoutAll()   -- (D52) each spell's buff: its look and place (defined below)
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
-- A faded icon (D51, see setFade) lets clicks through too. Two holders, one mouse:
-- it is off while either holds it (mouseByCurve, mouseByFade) and comes back once
-- neither does. A mouse something else switched off is not taken, nor given back.
local function mouseHold(f, holder)
	if f[holder] then return end
	if not (f.mouseByCurve or f.mouseByFade) then
		if not f:IsMouseEnabled() then return end
		f:EnableMouse(false)
	end
	f[holder] = true
end
local function mouseRelease(f, holder)
	if not f[holder] then return end
	f[holder] = nil
	if not (f.mouseByCurve or f.mouseByFade) then f:EnableMouse(true) end
end
local function curveMouseOff(f) mouseHold(f, "mouseByCurve") end
local function curveMouseBack(f) mouseRelease(f, "mouseByCurve") end

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
	if f then
		f.realDone = true; curveMouseBack(f)
		f.flagFresh = true   -- WoW: Forever: that pass reads the cooldown's own flags again (a wake, not the answer)
	end
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

-- the Ready Effect's glow and pulse off (alone: a faded icon's Shocks picture keeps cycling)
local function stopGlowPulse(f)
	if f.glowShown then f.glow:Hide(); f.glowAnim:Stop(); f.glowShown = nil end
	if f.pulsing then f.pulseAnim:Stop(); f.pulsing = nil end
end
local function stopEffects(f)
	stopGlowPulse(f)
	if f.entry.combo then showCastShock(f) end   -- Shocks: no cycling while not ready
end

-- The Ready Effect (glow / pulse): on a ready icon, or in "only while on
-- cooldown" (where a ready icon is never shown) on the icon while it counts down.
local function playEffects(f)
	local fx = IconOpt(f.entry, "readyEffect") or "glow"
	if (fx == "glow" or fx == "both") then
		if not f.glowShown then f.glow:Show(); f.glowAnim:Play(); f.glowShown = true end
	elseif f.glowShown then f.glow:Hide(); f.glowAnim:Stop(); f.glowShown = nil end
	if (fx == "pulse" or fx == "both") then
		if not f.pulsing then f.pulseAnim:Play(); f.pulsing = true end
	elseif f.pulsing then f.pulseAnim:Stop(); f.pulsing = nil end
end

-- ---------------------------------------------------------------------------
-- Fade Instead of Hide (D51, a Discord request): out of combat an icon with Only In
-- Combat on stays on screen at its Faded Opacity instead of hiding, so the player
-- still sees which spells are ready. f.fade is that opacity out of combat, and 1 in a
-- fight, while hidden, in Unlock UI and in the previews. It multiplies every alpha the
-- icon is given: setReady, the appearance, and on WoW: Forever the cooldown curves'
-- two inputs (plain numbers going in; the curve's answer, maybe a hidden value, still
-- goes straight to SetAlpha and is never looked at). At 1 each is today's value
-- exactly. The countdown, the sweep (the engine's numbers live in it) and the bar
-- ignore the icon's alpha, so they take the fade themselves. A faded icon lets clicks
-- through and stays quiet: no glow, pulse, sound or Ready Flash (setReady, the pass).
-- Display-only frames: none of this is protected, in a fight either.
-- ---------------------------------------------------------------------------
local FADE_GLIDE = 0.2   -- a fight ended: down to faded over this long (the totem bar's Smooth Fade)

-- an icon's Faded Opacity (its own, else the page's), inside the slider's range
local function fadedOpacity(entry)
	local v = tonumber(IconOpt(entry, "fadeOpacity")) or 0.4
	if v < 0.05 then return 0.05 elseif v > 0.9 then return 0.9 end
	return v
end

-- Only when the value changes: the three children, the mouse, and the glide's turn.
local function setFade(f, v)
	local old = f.fade or 1
	if old == v then return end
	f.fade = v
	f.cooldown:SetAlpha(v); f.bar:SetAlpha(v); f.count:SetAlpha(v)
	if v < 1 then mouseHold(f, "mouseByFade") else mouseRelease(f, "mouseByFade") end
	if old >= 1 and v < 1 and f:IsShown() then
		f.fadeGlide = true   -- full to faded on screen (a fight ended): glided once this pass set the alpha
	else
		f.fadeGlide = nil
		if f.fadeAG then f.fadeAG:Stop() end   -- back to full (a pull): at once
	end
end

-- The glide (the totem bar's playFade): the icon already has its faded alpha; an Alpha
-- animation runs from the alpha it had at full down to it and ends on the icon's own.
-- f.fadeBase is the plain alpha the pass gave it at full (nothing is read back from
-- the icon: on WoW: Forever its alpha may be a hidden value). An icon held at 0 (a
-- curve keeps it invisible while it cools) has nothing to glide. One group per icon,
-- made on its first glide; it stops by itself after FADE_GLIDE.
local function fadeGlideNow(f)
	f.fadeGlide = nil
	local base = f.fadeBase
	if not (base and base > 0.01 and f:IsShown()) then return end
	local ag = f.fadeAG
	if not ag then
		ag = f:CreateAnimationGroup()
		ag.alpha = ag:CreateAnimation("Alpha")
		ag.alpha:SetDuration(FADE_GLIDE)
		ag.alpha:SetSmoothing("IN_OUT")
		f.fadeAG = ag
	end
	ag:Stop()
	ag.alpha:SetFromAlpha(base)
	ag.alpha:SetToAlpha(base * (f.fade or 1))
	ag:Play()
end

-- ---------------------------------------------------------------------------
-- Your buff on its Ready Reminder (D52, a Discord request: "a way to show, maybe on the
-- ready reminder, that you currently have the stormstrike mana regen buff", then "a small
-- buff icon that I could track"). A spell that puts a buff on you can show that buff with
-- its icon: in the icon's corner, as its own icon (beside it, or In Its Own Spot with a
-- box of its own in Unlock UI), or as an edge round the icon; with its time left in whole
-- seconds, in WoW's gold for the last few. Each icon's own, in its right-click menu, off
-- to start. The buff is found by spell ID only (Buff.list, at the top).
--
-- WoW: Forever: nothing is read. An AuraContainer slot on "player", filtered to the buff's
-- spell IDs, has the game draw it: the game shows the slot's button only while the buff is
-- on you, gives it the buff's icon and counts its time left (gold: a color code in the
-- number formatter's text; the game writes it). Our parts hang on that button, made and
-- painted out of combat; in a fight only the container's own switch (SetEnabled) and the
-- alpha of a frame of ours (the holder) change, never the game's button or what is on it.
-- TBC Anniversary: the buff is read by its ID on UNIT_AURA (player) and drawn on frames of
-- our own; its time left is a duration text binding, or the pass where the client has none.
--
-- The holder is ours: anchored to the icon's spot (so the buff stays there while the icon
-- hides between casts, and follows the icon when it moves), on its own spot, or for the
-- edge a child of the icon (it shows and hides with the icon). The buff follows its icon's
-- Opacity, Only In Combat and Fade Instead of Hide (D51: faded, gliding down as the fight
-- ends, just like the icon), and stays off while the icons are being placed (Unlock UI) or
-- borrowed by the settings preview. Nothing runs while idle: the game draws, or UNIT_AURA.
-- ---------------------------------------------------------------------------
Buff.CORNER = { tr = { "TOPRIGHT", -4, -4 }, tl = { "TOPLEFT", 4, -4 }, br = { "BOTTOMRIGHT", -4, 4 }, bl = { "BOTTOMLEFT", 4, 4 } }
Buff.SIDES = { above = true, below = true, left = true, right = true, spot = true }

function Buff.Clamp(v, lo, hi, def)
	v = tonumber(v) or def
	if v < lo then return lo elseif v > hi then return hi end
	return v
end

-- WoW: Forever: the game's AuraContainer can draw (the probe's container is the first one used)
function Buff.Engine()
	if Buff.engine ~= nil then return Buff.engine end
	Buff.engine = false
	if not IS_MAINLINE then return false end
	if C_AddOns and C_AddOns.LoadAddOn then pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer") end
	local ok, c = pcall(CreateFrame, "AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
	if ok and c and type(c.AddAuraSlot) == "function" and type(c.SetUnit) == "function" then
		Buff.engine = true
		c:Hide()
		Buff.spare = c
	end
	return Buff.engine
end

-- The game's button (and what hangs on it) must not be touched now: a fight, or WoW: Forever
-- hiding auras. Only the engine's buffs care; Anniversary's are frames of our own.
function Buff.Locked()
	if not (IS_MAINLINE and Buff.engine ~= false) then return false end
	if InCombatLockdown() then return true end
	local S = C_Secrets
	if S and S.ShouldAurasBeSecret then
		local ok, v = pcall(S.ShouldAurasBeSecret)
		if not ok or (issecretvalue and issecretvalue(v)) or v == true then return true end
	end
	if SPCompat.secretsRegime then
		if SPCompat.AnyRestrictionActive and SPCompat.AnyRestrictionActive() then return true end
		if SPCompat.AurasUnreadable and SPCompat.AurasUnreadable() then return true end
	end
	return false
end

-- WoW's gold (NORMAL_FONT_COLOR, read from the game: #FFD100 Anniversary, #FFD200 Forever)
function Buff.GoldRGB()
	local c = NORMAL_FONT_COLOR
	if c and c.GetRGB then return c:GetRGB() end
	return 1, 0.82, 0
end

-- The time left as the game writes it: whole seconds, rounded up as WoW counts down, in
-- WoW's gold under `gold` seconds (a color code in the text), minutes from a minute on.
-- One formatter per number of seconds, made once; nil where the client has none.
function Buff.Formatter(gold)
	gold = math.floor(tonumber(gold) or 0)
	local f = Buff.formatters[gold]
	if f ~= nil then return f or nil end
	Buff.formatters[gold] = false
	local S = C_StringUtil
	if not (S and S.CreateNumericRuleFormatter) then return nil end
	local ok, made = pcall(S.CreateNumericRuleFormatter)
	if not (ok and made and made.AddBreakpoint) then return nil end
	local up = Enum and Enum.NumericRuleFormatRounding and Enum.NumericRuleFormatRounding.Up or 1
	local good
	if gold > 0 then
		local r, g, b = Buff.GoldRGB()
		local code = string.format("|cff%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
		good = pcall(made.AddBreakpoint, made, { threshold = 0, step = 1, rounding = up, format = code .. "%d|r" })
			and pcall(made.AddBreakpoint, made, { threshold = gold, step = 1, rounding = up, format = "%d" })
	else
		good = pcall(made.AddBreakpoint, made, { threshold = 0, step = 1, rounding = up, format = "%d" })
	end
	if not good then return nil end
	pcall(made.AddBreakpoint, made, { threshold = 60, format = "%dm", components = { { div = 60, step = 1, rounding = up } } })
	Buff.formatters[gold] = made
	return made
end

-- The parts, on `host` (the game's button, or a frame of ours): the backing, the buff's
-- icon and its edge (four sides, or a ring round a Rounded / Circle icon) on one frame,
-- the time left on a frame above it. Made once; Buff.Paint gives them their look.
function Buff.NewParts(host)
	local P = {}
	local art = CreateFrame("Frame", nil, host)
	art:SetAllPoints(host)
	art:EnableMouse(false)
	P.art = art
	P.bg = art:CreateTexture(nil, "BACKGROUND")
	P.bg:SetAllPoints(art)
	P.icon = art:CreateTexture(nil, "ARTWORK")
	P.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	P.edges = {}
	for i = 1, 4 do P.edges[i] = art:CreateTexture(nil, "OVERLAY") end
	P.ring = art:CreateTexture(nil, "OVERLAY")
	P.ring:Hide()
	local tf = CreateFrame("Frame", nil, host)
	tf:SetAllPoints(host)
	tf:SetFrameLevel(art:GetFrameLevel() + 3)
	tf:EnableMouse(false)
	P.text = tf
	P.time = tf:CreateFontString(nil, "OVERLAY")
	SP:SetSPFont(P.time, "alerts", 12, "OUTLINE")   -- a font at once: the game may write the time into it straight away
	P.time:SetTextColor(1, 1, 1)
	return P
end

-- Icon Shape (Ready Reminders) on the buff's backing and icon, with masks of our own: the
-- shared shape walk runs whenever a shape changes, in a fight too, and must never reach
-- the game's button (Paint runs only while the button may be touched).
function Buff.Shape(P)
	local file = SP.IconShapeMaskFile and SP.IconShapeOf and SP:IconShapeMaskFile(SP:IconShapeOf("ready")) or false
	if P.maskFile == file or not P.bg.AddMaskTexture then return end
	if P.maskFile then
		P.bg:RemoveMaskTexture(P.bgMask)
		P.icon:RemoveMaskTexture(P.iconMask)
	end
	P.maskFile = file
	if not file then return end
	if not P.bgMask then
		P.bgMask = P.art:CreateMaskTexture()
		P.bgMask:SetAllPoints(P.art)
		P.iconMask = P.art:CreateMaskTexture()
		P.iconMask:SetAllPoints(P.icon)
	end
	P.bgMask:SetTexture(file, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	P.iconMask:SetTexture(file, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	P.bg:AddMaskTexture(P.bgMask)
	P.icon:AddMaskTexture(P.iconMask)
end

-- the edge: `t` px thick, `out` px outside the parts' frame; a ring round a Rounded /
-- Circle icon (Keep Borders Square off), as the icon's own border does
function Buff.Edges(P, t, out, r, g, b, shown)
	local ringFile = shown and SP.BorderRingFile and SP:BorderRingFile("ready") or nil
	local E, art = P.edges, P.art
	for i = 1, 4 do E[i]:SetShown(shown and not ringFile) end
	if ringFile then
		P.ring:ClearAllPoints()
		P.ring:SetPoint("TOPLEFT", art, "TOPLEFT", -out, out)
		P.ring:SetPoint("BOTTOMRIGHT", art, "BOTTOMRIGHT", out, -out)
		if P.ring.spFile ~= ringFile then P.ring:SetTexture(ringFile); P.ring.spFile = ringFile end
		P.ring:SetVertexColor(r, g, b)
		P.ring:Show()
		return
	end
	P.ring:Hide()
	if not shown then return end
	E[1]:ClearAllPoints(); E[1]:SetPoint("TOPLEFT", art, "TOPLEFT", -out, out); E[1]:SetPoint("TOPRIGHT", art, "TOPRIGHT", out, out); E[1]:SetHeight(t)
	E[2]:ClearAllPoints(); E[2]:SetPoint("BOTTOMLEFT", art, "BOTTOMLEFT", -out, -out); E[2]:SetPoint("BOTTOMRIGHT", art, "BOTTOMRIGHT", out, -out); E[2]:SetHeight(t)
	E[3]:ClearAllPoints(); E[3]:SetPoint("TOPLEFT", art, "TOPLEFT", -out, out); E[3]:SetPoint("BOTTOMLEFT", art, "BOTTOMLEFT", -out, -out); E[3]:SetWidth(t)
	E[4]:ClearAllPoints(); E[4]:SetPoint("TOPRIGHT", art, "TOPRIGHT", out, out); E[4]:SetPoint("BOTTOMRIGHT", art, "BOTTOMRIGHT", out, -out); E[4]:SetWidth(t)
	for i = 1, 4 do E[i]:SetColorTexture(r, g, b, 1) end
end

-- the look of the parts for the buff's look (WoW: Forever: only while Buff.Locked() is false)
function Buff.Paint(B)
	local P = B.P
	if not P then return end
	local entry, look, s = B.entry, B.look, B.size or 24
	Buff.Shape(P)
	if look == "edge" then
		-- the icon's border, in the edge's color, with the time in the icon's corner
		P.bg:Hide(); P.icon:Hide()
		local r, g, b = color(IconOpt(entry, "buffEdgeColor"), 0, 0, 1)
		Buff.Edges(P, 2, 2, r, g, b, true)
		SP:SetSPFont(P.time, "alerts", math.max(10, math.floor(s * 0.30)), "OUTLINE")
		P.time:ClearAllPoints()
		P.time:SetPoint("BOTTOMRIGHT", P.art, "BOTTOMRIGHT", -2, 3)
	elseif look == "corner" then
		-- a small badge: dark backing, the buff's icon, a 1 px edge in the icon's Border Color
		P.bg:SetColorTexture(0, 0, 0, 0.85); P.bg:Show()
		P.icon:ClearAllPoints()
		P.icon:SetPoint("TOPLEFT", P.art, "TOPLEFT", 1, -1); P.icon:SetPoint("BOTTOMRIGHT", P.art, "BOTTOMRIGHT", -1, 1)
		P.icon:Show()
		local r, g, b = color(IconOpt(entry, "borderColor"), 0.2, 0.7, 1.0)
		Buff.Edges(P, 1, 1, r, g, b, true)
		SP:SetSPFont(P.time, "alerts", math.max(8, math.floor(s * 0.55 + 0.5)), "OUTLINE")
		P.time:ClearAllPoints()
		P.time:SetPoint("CENTER", P.art, "CENTER", 1, 0)
	else
		-- its own icon, drawn like a Ready Reminder (the icon's Background, Border and Border Color)
		local hideBg = IconOpt(entry, "hideBackground") and true or false
		local e = (s >= 24) and 2 or 1
		P.bg:SetColorTexture(0, 0, 0, 0.6); P.bg:SetShown(not hideBg)
		P.icon:ClearAllPoints()
		P.icon:SetPoint("TOPLEFT", P.art, "TOPLEFT", e, -e); P.icon:SetPoint("BOTTOMRIGHT", P.art, "BOTTOMRIGHT", -e, e)
		P.icon:Show()
		local r, g, b = color(IconOpt(entry, "borderColor"), 0.2, 0.7, 1.0)
		Buff.Edges(P, e, e, r, g, b, not hideBg and not IconOpt(entry, "hideBorder"))
		SP:SetSPFont(P.time, "alerts", math.max(8, math.floor(s * 0.34 + 0.5)), "OUTLINE")
		P.time:ClearAllPoints()
		P.time:SetPoint("CENTER", P.art, "CENTER", 0, 0)
	end
	if P.engine then
		P.text:SetShown(B.timeOn and true or false)   -- (the game's button shows the buff only while it is on you)
		Buff.EngineTime(B)
	else
		Buff.ShowParts(B)
	end
end

-- WoW: Forever: the game counts the time left on its button, in the gold formatter
-- (again only when the seconds of gold changed; never in a fight: Buff.Locked)
function Buff.EngineTime(B)
	local P = B.P
	if not (P and P.engine and B.entry.buff.timed) then return end
	local gold = B.gold or 3
	if B.goldSet == gold then return end
	if pcall(P.button.SetDurationText, P.button, P.time, { textFormatter = Buff.Formatter(gold) }) then B.goldSet = gold end
end

-- WoW: Forever: the game's button for the buff, made with the container (out of combat)
function Buff.Init(B, button)
	button:ClearAllPoints()
	button:SetAllPoints(B.frame)
	if button.SetMouseClickEnabled then pcall(button.SetMouseClickEnabled, button, false) end
	if button.SetMouseMotionEnabled then pcall(button.SetMouseMotionEnabled, button, false) end
	local P = Buff.NewParts(button)
	P.engine, P.button = true, button
	B.P = P
	Buff.Paint(B)
	pcall(button.SetIcon, button, P.icon)   -- the game puts the buff's own icon on it
end

-- WoW: Forever: the container, one slot for the buff (out of combat, once; three tries)
function Buff.Build(B)
	local h, c = B.frame, Buff.spare
	if c then
		Buff.spare = nil
		c:SetParent(h)
		c:Show()
	else
		local ok, made = pcall(CreateFrame, "AuraContainer", nil, h, "CustomAuraContainerTemplate")
		c = ok and made and type(made.AddAuraSlot) == "function" and made or nil
	end
	if not c then B.fails = (B.fails or 0) + 1 return false end
	c:ClearAllPoints()
	c:SetSize(1, 1)
	c:SetPoint("CENTER", h, "CENTER", 0, 0)
	c:SetFrameLevel(h:GetFrameLevel() + 1)
	-- WoW's Edit Mode fills aura displays with made-up auras while it is open: never this one
	if c.SetEditModePreviewEnabled then pcall(c.SetEditModePreviewEnabled, c, false) end
	local ok = pcall(c.AddAuraSlot, c, "buff", "HELPFUL", {
		candidateFilters = { includeSpellIDs = B.entry.buff.map },
		initializeFrame = function(button) Buff.Init(B, button) end,
	})
	if not (ok and B.P) then
		pcall(c.SetEnabled, c, false)
		c:Hide()
		B.P = nil   -- (parts on a refused slot's button are never used)
		B.fails = (B.fails or 0) + 1
		return false
	end
	pcall(c.SetUnit, c, "player")
	pcall(c.SetEnabled, c, false)   -- on only while the buff may show (Buff.Switch)
	B.c, B.on = c, false
	return true
end

-- a buff's display (the holder, ours): made the first time its look is turned on
function Buff.Make(entry)
	local h = CreateFrame("Frame", "ShamanPowerReadyBuff_" .. entry.key, UIParent)
	h:SetSize(1, 1)
	h:EnableMouse(false)
	h:SetAlpha(0)
	local B = { entry = entry, key = entry.key, frame = h, look = "off", on = false, alpha = 0, fade = 1 }
	Buff.of[entry.key] = B
	return B
end

-- Its own icon's place: beside the Ready Reminder (Side), or its own spot (In Its Own Spot:
-- where Unlock UI put it; above the icon until it is moved there)
function Buff.PlaceOwn(B, f)
	local h, side, gap = B.frame, B.side, SV().spacing or 8
	if side == "spot" then
		local rec = SV().buffPositions[B.key]
		if type(rec) == "table" and SP.ApplyPositionRecord and SP:ApplyPositionRecord(h, rec) then return end
		side = "above"
	end
	if side == "below" then h:SetPoint("TOP", f, "BOTTOM", 0, -gap)
	elseif side == "left" then h:SetPoint("RIGHT", f, "LEFT", -gap, 0)
	elseif side == "right" then h:SetPoint("LEFT", f, "RIGHT", gap, 0)
	else h:SetPoint("BOTTOM", f, "TOP", 0, gap) end
end

-- One buff's look and place, after a setting changed (WoW: Forever: out of combat, and
-- not while the game hides auras: then right after, Buff.Flush). Off: switched off at once.
function Buff.Layout(entry)
	local b = entry.buff
	if not b then return end
	local B = Buff.of[entry.key]
	local look = IconOpt(entry, "buffLook")
	if look ~= "corner" and look ~= "own" and look ~= "edge" then look = "off" end
	if look == "off" or not usable(entry) or not SV().enabled then   -- (Ready Reminders off: nothing made either)
		if B then B.look = "off"; Buff.Switch(B, false, 0) end
		return
	end
	if IS_MAINLINE and Buff.engine == nil and not InCombatLockdown() then Buff.Engine() end
	if Buff.Locked() then Buff.dirty = true return end
	B = B or Buff.Make(entry)
	local f = frames[entry.key] or SP:CreateReadyReminderFrame(entry)
	local h = B.frame
	local S = IconOpt(entry, "iconSize") or 48
	local side = IconOpt(entry, "buffSide")
	B.look = look
	B.side = (look == "own") and (Buff.SIDES[side] and side or "above") or nil
	B.timeOn = b.timed and IconOpt(entry, "buffTime") ~= false
	B.gold = math.floor(Buff.Clamp(IconOpt(entry, "buffGoldUnder"), 0, 10, 3))
	local parent = (look == "edge") and f or UIParent
	if h:GetParent() ~= parent then h:SetParent(parent) end
	h:SetFrameStrata(f:GetFrameStrata())
	h:SetFrameLevel(f:GetFrameLevel() + 10)
	h:ClearAllPoints()
	if look == "edge" then
		h:SetAllPoints(f)
		B.size = S
	elseif look == "corner" then
		local s = math.floor(S * Buff.Clamp(IconOpt(entry, "buffSize"), 0.3, 0.7, 0.45) + 0.5)
		h:SetSize(s, s)
		B.size = s
		local c = Buff.CORNER[IconOpt(entry, "buffCorner")] or Buff.CORNER.tr
		h:SetPoint("CENTER", f, c[1], c[2], c[3])
	else
		local s = math.floor(S * Buff.Clamp(IconOpt(entry, "buffOwnSize"), 0.3, 1, 1) + 0.5)
		h:SetSize(s, s)
		B.size = s
		Buff.PlaceOwn(B, f)
	end
	if B.c then
		B.c:SetFrameLevel(h:GetFrameLevel() + 1)
		Buff.Paint(B)
	elseif Buff.engine and (B.fails or 0) < 3 then
		if not Buff.Build(B) then return end   -- (tried again on the next layout; B.P is painted by its button's Init)
	else
		-- TBC Anniversary, or the game's container refused three times: frames of our own
		-- (WoW: Forever then shows the buff out of combat only: in a fight it cannot be read)
		if not B.P then B.P = Buff.NewParts(h) end
		Buff.Paint(B)
		if B.on then   -- a new look, Time Left or gold: the buff as it is now, its time started again
			B.bindOn, B.ticking = nil, nil
			Buff.Read(B)
		end
	end
	B.ready = true
end

function Buff.LayoutAll()
	for i = 1, #Buff.list do Buff.Layout(Buff.list[i]) end
	Buff.Events()
end

-- WoW: Forever: what waited for the end of a fight (or for the game to show auras again)
function Buff.Flush()
	if not Buff.dirty or Buff.Locked() then return end
	Buff.dirty = nil
	Buff.LayoutAll()
	SP:UpdateReadyReminders()   -- (the pass switches them on)
end

-- On or off (in a fight too): the container's own switch (WoW: Forever) or our parts
-- (Anniversary), and the holder's alpha. The pass calls it with what the icon allows.
function Buff.Switch(B, on, alpha)
	alpha = on and alpha or 0
	if B.on ~= on then
		B.on = on
		if B.c then
			pcall(B.c.SetEnabled, B.c, on)
			if on then pcall(B.c.UpdateAllAuras, B.c) end
		elseif on then
			Buff.Read(B)
		else
			Buff.Hide(B)
		end
	end
	if B.alpha ~= alpha then
		B.alpha = alpha
		if B.ag then B.ag:Stop() end
		B.frame:SetAlpha(alpha)
	end
end

-- a fight ended and the icon fades (D51): the buff glides down with it, over the same 0.2 s
function Buff.Glide(B, from, to)
	if not (from and from > 0.01) then return end
	local ag = B.ag
	if not ag then
		ag = B.frame:CreateAnimationGroup()
		ag.alpha = ag:CreateAnimation("Alpha")
		ag.alpha:SetDuration(FADE_GLIDE)
		ag.alpha:SetSmoothing("IN_OUT")
		B.ag = ag
	end
	ag:Stop()
	ag.alpha:SetFromAlpha(from)
	ag.alpha:SetToAlpha(to)
	ag:Play()
end

-- What the icon allows its buff now: on, the holder's alpha, the fade. As the icon: the
-- spell switched on and known (In Its Own Spot: its own, the icon need not be on), Only In
-- Combat (hidden out of combat, or faded with Fade Instead of Hide), Opacity. The edge is
-- on the icon itself: the icon's own alpha carries all of that to it.
function Buff.Wanted(entry, B, inCombat)
	if not usable(entry) then return false, 0, 1 end
	if not (B.look == "own" and B.side == "spot") and not (spellOn(entry) and playerKnows(entry)) then return false, 0, 1 end
	local fade = 1
	if not inCombat and IconOpt(entry, "onlyInCombat") then
		if IconOpt(entry, "fadeInsteadOfHide") and IconOpt(entry, "mode") ~= "flash" then fade = fadedOpacity(entry)
		else return false, 0, 1 end
	end
	if B.look == "edge" then return true, 1, 1 end
	return true, (IconOpt(entry, "opacity") or 1) * fade, fade
end

-- Every pass (readyPass, 5 a second while something counts down, else once a second and on
-- the wake events): each buff on or off. allOff: the icons are hidden, placed or previewed.
-- Returns true while a buff's time is counted here (Anniversary without a binding).
function Buff.Pass(inCombat, allOff)
	allOff = allOff or Buff.placing
	local ticks, now = false, nil
	for i = 1, #Buff.list do
		local entry = Buff.list[i]
		local B = Buff.of[entry.key]
		if B then
			local on, alpha, fade = false, 0, 1
			if not allOff and B.ready and B.look ~= "off" then on, alpha, fade = Buff.Wanted(entry, B, inCombat) end
			local glide = on and B.on and (B.fade or 1) >= 1 and fade < 1   -- a fight ended: down to faded, as the icon
			B.fade = fade
			Buff.Switch(B, on, alpha)
			if glide then Buff.Glide(B, alpha / fade, alpha) end
			if B.ticking and B.on and B.shown then
				now = now or GetTime()
				Buff.TickText(B, now)
				ticks = true
			end
		end
	end
	return ticks
end

-- ---- TBC Anniversary (and WoW: Forever without the engine): read by spell ID ----------
-- found, icon, duration, expirationTime of the buff on you; nothing when it is not (or when
-- the game hides it: a hidden value is never looked at)
function Buff.FindAura(b)
	local A = C_UnitAuras
	local secret = issecretvalue or function() return false end
	if A and A.GetPlayerAuraBySpellID then
		for i = 1, #b.ids do
			local ok, a = pcall(A.GetPlayerAuraBySpellID, b.ids[i])
			if ok and type(a) == "table" and not secret(a) then
				local dur, exp = a.duration, a.expirationTime
				if secret(dur) or secret(exp) or secret(a.icon) then return false end
				return true, a.icon, tonumber(dur) or 0, tonumber(exp) or 0
			end
		end
		return false
	end
	if not SPCompat.UnitBuff then return false end
	for i = 1, 40 do
		local name, icon, _, _, dur, exp, _, _, _, spellID = SPCompat.UnitBuff("player", i)
		if not name then break end
		if not secret(spellID) and b.map[spellID] then
			if secret(dur) or secret(exp) then return false end
			return true, icon, tonumber(dur) or 0, tonumber(exp) or 0
		end
	end
	return false
end

function Buff.ShowParts(B)
	local P = B.P
	if not P then return end
	P.art:SetShown(B.shown and true or false)
	P.text:SetShown((B.shown and B.timeOn and B.timedNow) and true or false)
end

-- the time left drawn by the game from numbers of ours (a duration text binding, with the
-- gold formatter); false where the client has neither (the pass writes it then)
function Buff.TimeBinding(B, start, duration)
	local f = Buff.Formatter(B.gold)
	if not f then return false end
	if B.bind == nil then
		B.bind = false
		local D = C_DurationUtil
		if D and D.CreateDurationTextBinding and D.CreateDuration then
			local ok, bnd = pcall(D.CreateDurationTextBinding)
			local okD, d = pcall(D.CreateDuration)
			if ok and bnd and okD and d and pcall(bnd.SetFontString, bnd, B.P.time) then
				if bnd.SetExpiredText then pcall(bnd.SetExpiredText, bnd, "") end
				B.bind, B.dur = bnd, d
			end
		end
	end
	local bnd = B.bind
	if not bnd then return false end
	if B.bindGold ~= B.gold then
		if not pcall(bnd.SetFormatter, bnd, f) then return false end
		B.bindGold = B.gold
	end
	B.P.time:SetTextColor(1, 1, 1)
	return pcall(B.dur.SetTimeFromStart, B.dur, start, duration) and pcall(bnd.SetDuration, bnd, B.dur)
		and pcall(bnd.SetEnabled, bnd, true)
end

function Buff.StopTime(B)
	if B.bind then pcall(B.bind.SetEnabled, B.bind, false) end
	B.ticking, B.sec = nil, nil
	if B.P then B.P.time:SetText("") end
end

-- the time left written by the pass (a client with no binding): once a second, gold at the end
function Buff.TickText(B, now)
	local left = (B.exp or 0) - now
	local sec = (left > 0) and math.ceil(left) or 0
	if B.sec == sec then return end
	B.sec = sec
	local t = B.P.time
	if sec <= 0 then t:SetText("") return end
	if sec >= 60 then t:SetText(string.format("%dm", math.ceil(left / 60))) else t:SetText(string.format("%d", sec)) end
	if (B.gold or 0) > 0 and left < B.gold then t:SetTextColor(Buff.GoldRGB()) else t:SetTextColor(1, 1, 1) end
end

-- the buff as it is on you now (on UNIT_AURA, and when the buff is switched on)
function Buff.Read(B)
	if B.c or not B.P then return end
	local found, icon, dur, exp = Buff.FindAura(B.entry.buff)
	if not found then Buff.Hide(B) return end
	B.shown = true
	B.P.icon:SetTexture(icon or GetSpellTextureC(B.entry.buff.ids[1]) or 136243)
	B.timedNow = (dur or 0) > 0 and (exp or 0) > 0
	if B.timeOn and B.timedNow then
		if B.exp ~= exp or not (B.ticking or B.bindOn) then
			B.exp = exp
			if Buff.TimeBinding(B, exp - dur, dur) then
				B.ticking, B.bindOn = nil, true
			else
				B.ticking, B.bindOn, B.sec = true, nil, nil
				Buff.TickText(B, GetTime())
				SP.readyWake = true   -- the pass counts it down from now (five times a second)
			end
		end
	else
		Buff.StopTime(B)
		B.bindOn = nil
	end
	Buff.ShowParts(B)
end

function Buff.Hide(B)
	B.shown, B.exp, B.bindOn = nil, nil, nil
	Buff.StopTime(B)
	Buff.ShowParts(B)
end

function Buff.OnAura()
	for i = 1, #Buff.list do
		local B = Buff.of[Buff.list[i].key]
		if B and B.on and not B.c then Buff.Read(B) end
	end
end

-- The events: UNIT_AURA (player) while a buff is read here; the end of a fight while
-- something waits for it (WoW: Forever).
Buff.ev = CreateFrame("Frame")
Buff.ev:SetScript("OnEvent", function(_, event, unit)
	if event == "UNIT_AURA" then
		if unit == "player" then Buff.OnAura() end
	elseif event == "PLAYER_REGEN_ENABLED" then
		Buff.Flush()
	end
end)
function Buff.Events()
	local ev, read = Buff.ev, false
	if SV().enabled then
		for _, B in pairs(Buff.of) do
			if B.look ~= "off" and B.P and not B.c then read = true break end
		end
	end
	if read ~= (ev.read or false) then
		ev.read = read
		if read then
			if not pcall(ev.RegisterUnitEvent, ev, "UNIT_AURA", "player") then ev:RegisterEvent("UNIT_AURA") end
		else
			ev:UnregisterEvent("UNIT_AURA")
		end
	end
	if Buff.dirty then ev:RegisterEvent("PLAYER_REGEN_ENABLED") else ev:UnregisterEvent("PLAYER_REGEN_ENABLED") end
end
if SPCompat.OnUnrestricted then SPCompat.OnUnrestricted(function() Buff.Flush() end) end

-- ---- what the menu says (the plain line before it can show) --------------------------
-- WoW: Forever: the talent, by its spell ID, else its node's rank in your talents
function Buff.KnowsTalent(b)
	if SPCompat.KnowsSpellID(b.talent) then return true end
	local CT, T = C_ClassTalents, C_Traits
	if not (b.node and CT and CT.GetActiveConfigID and T and T.GetNodeInfo) then return false end
	local secret = issecretvalue or function() return false end
	local ok, cfg = pcall(CT.GetActiveConfigID)
	if not ok or secret(cfg) or type(cfg) ~= "number" then return false end
	local ok2, info = pcall(T.GetNodeInfo, cfg, b.node)
	if not ok2 or type(info) ~= "table" then return false end
	local rank = info.activeRank
	if secret(rank) or type(rank) ~= "number" then rank = info.ranksPurchased end
	return not secret(rank) and type(rank) == "number" and rank > 0
end

-- TBC Anniversary: four pieces of the set on (by item ID), else the bonus itself on you
function Buff.HasSetBonus(b)
	local n = 0
	if GetInventoryItemID then
		for slot = 1, 19 do
			local id = GetInventoryItemID("player", slot)
			if id and b.setMap[id] then n = n + 1 end
		end
	end
	if n >= 4 then return true end
	local A = C_UnitAuras
	if A and A.GetPlayerAuraBySpellID then
		local ok, a = pcall(A.GetPlayerAuraBySpellID, b.setBonus)
		if ok and type(a) == "table" then return true end
	end
	return SPCompat.KnowsExactSpellID and SPCompat.KnowsExactSpellID(b.setBonus) or false
end

-- the set's name in the game's language
function Buff.SetName(b)
	local I = C_Item
	if I and I.GetItemSetInfo then
		local ok, name = pcall(I.GetItemSetInfo, b.setID)
		if ok and type(name) == "string" and name ~= "" then return name end
	end
	return b.setName
end

-- ---- In Its Own Spot: Unlock UI's box (a still copy of the buff, as the flash's own spots) ----
-- where the spot starts: above its icon (until moved)
function Buff.DefaultSpot(entry, s)
	local f = frames[entry.key] or SP:CreateReadyReminderFrame(entry)
	local cx, cy = f:GetCenter()
	if not cx then return { anchor = "CENTER", x = 0, y = -80 } end
	local fs = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
	local S = IconOpt(entry, "iconSize") or 48
	cx, cy = cx * fs, (cy + S / 2 + (SV().spacing or 8)) * fs + s / 2
	return { anchor = "CENTER", x = cx - UIParent:GetWidth() / 2, y = cy - UIParent:GetHeight() / 2 }
end

function Buff.Proxy(key)
	local entry = catalogByKey[key]
	if not (entry and entry.buff) then return nil end
	local p = Buff.proxies[key]
	if not p then
		p = CreateFrame("Frame", nil, UIParent)
		p:SetFrameStrata("HIGH")
		p.icon = p:CreateTexture(nil, "ARTWORK")
		p.icon:SetAllPoints(p)
		p.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		p.spBuffKey = key
		p.spMoverLabel = entry.buff.label .. " Buff"   -- Unlock UI's box (the menu's name for it)
		p:Hide()
		Buff.proxies[key] = p
	end
	local s = math.floor((IconOpt(entry, "iconSize") or 48) * Buff.Clamp(IconOpt(entry, "buffOwnSize"), 0.3, 1, 1) + 0.5)
	p:SetSize(s, s)
	p.icon:SetTexture(GetSpellTextureC(entry.buff.ids[1]) or 136243)
	p.icon:SetAlpha(0.6)
	local rec = SV().buffPositions[key]
	if type(rec) ~= "table" then rec = Buff.DefaultSpot(entry, s) end
	if not (SP.ApplyPositionRecord and SP:ApplyPositionRecord(p, rec)) then
		p:ClearAllPoints()
		p:SetPoint("CENTER", UIParent, "CENTER", 0, -80)
	end
	return p
end

-- the buffs shown In Their Own Spot (Move This Buff: that one only)
function Buff.SpotKeys(out)
	for _, entry in ipairs(Buff.list) do
		if usable(entry) and (Buff.moveOnly == nil or Buff.moveOnly == entry.key)
			and IconOpt(entry, "buffLook") == "own" and IconOpt(entry, "buffSide") == "spot" then
			out[#out + 1] = entry.key
		end
	end
	return out
end

-- The look while it cools: the icon's Gray Out The Icon and Opacity While On
-- Cooldown. An icon set to "only while on cooldown" in its menu before these were
-- its own (3.0.5) looks as the page did in that mode: no gray, full opacity.
local function coolingLook(f)
	local e = f.entry
	if IconOpt(e, "ownMode") == "cooldown" and not IconOpt(e, "ownCoolLook") then return false, 1 end
	return IconOpt(e, "desaturate") ~= false, IconOpt(e, "dimOpacity") or 0.35
end

local function setReady(f, ready)
	local fade = f.fade or 1   -- (D51: below 1 only while faded out of combat)
	if ready then
		setDesat(f, false)
		f.cooldown:Hide(); f.overlay:Hide(); f.bar:Hide(); f.count:SetText(""); f.countShown = nil
		f.ecdOn, f.ecdDur, f.readyDur, f.readyDurStart, f.realDone = nil, nil, nil, nil, nil
		curveMouseBack(f)
		if f.engineSheet then f.engineSheet:Hide() end
		local a = IconOpt(f.entry, "opacity") or 1
		f:SetAlpha(a * fade); f.fadeBase = a
		if fade < 1 then stopGlowPulse(f) else playEffects(f) end   -- faded: quiet
		if f.entry.combo then shockIcon(f, true) end
	else
		local gray, dim = coolingLook(f)
		setDesat(f, gray)
		f:SetAlpha(dim * fade); f.fadeBase = dim
		if IconOpt(f.entry, "mode") == "cooldown" then
			-- runs on untouched each pass: only a change starts or stops it (faded: quiet)
			if fade < 1 then stopGlowPulse(f) else playEffects(f) end
			if f.entry.combo then showCastShock(f) end   -- Shocks: no cycling while not ready
		else
			stopEffects(f)
		end
	end
end

-- A value that is plainly true or false (a hidden value is neither).
local function plainBool(v)
	if issecretvalue and issecretvalue(v) then return false end
	return type(v) == "boolean"
end

-- "Sound Only For Cooldowns Over" is measured on the cooldown's length: the run
-- the estimate saw, else the length learned from the game, else the spell's base
-- cooldown (a cooldown the game's flags reported with no run of ours).
local function soundLength(entry, duration)
	if type(duration) == "number" and duration > GCD_MAX then return duration end
	local id = clientSpellID(entry)
	if not id then return 0 end
	local name = SPCompat.SpellName(id)
	local shadow = SPCompat and SPCompat.shadowCooldowns
	local learned = shadow and name and shadow[name]
	if type(learned) == "table" and type(learned.duration) == "number" then return learned.duration end
	if GetSpellBaseCooldown then
		local ok, ms = pcall(GetSpellBaseCooldown, id)
		if ok and type(ms) == "number" and not (issecretvalue and issecretvalue(ms)) then return ms / 1000 end
	end
	return 0
end

-- The icon's own Sound When Ready and sound, else the page's. WoW: Forever: one
-- sound per icon per second at most (the same edge reported twice).
local SOUND_GAP = 1.0
local function readySound(f, duration)
	local entry = f.entry
	if not IconOpt(entry, "soundOnReady") then return end
	-- the minimum is for the old page switch: a sound the player turned on for this one
	-- spell (its right-click menu) always plays
	if not IconOpt(entry, "ownSound") and soundLength(entry, duration) < (IconOpt(entry, "soundMinCooldown") or 20) then return end
	if IS_MAINLINE then
		local now = GetTime()
		if f.soundAt and now - f.soundAt < SOUND_GAP then return end
		f.soundAt = now
	end
	if SP.PlaySoundWithVolume and SP.GetSoundFile then
		SP:PlaySoundWithVolume(SP:GetSoundFile(IconOpt(entry, "soundName") or "Raid Warning"), IconOpt(entry, "soundVolume") or 100, true)
	end
end

-- ---------------------------------------------------------------------------
-- Ready Flash (D38; a Discord request: Doom Cooldown Pulse). When a spell is
-- ready, or Flash Early seconds before, a big copy of its icon flashes on the
-- flash's own spot (the middle of the screen, a little above the character,
-- until Unlock UI moves it) and fades away. One frame, made the first time it
-- is needed and reused; it never takes a click. A spell ready while another
-- flash plays waits its turn. The motion is ours, a step each frame while a flash
-- plays (so it looks the same on every client), and nothing runs while none does.
-- The flash is the icon in the page's Look (background, border, its shape, the
-- ready glow) at Flash Size: no colors of its own.
-- ---------------------------------------------------------------------------
local FLASH_X, FLASH_Y = 0, 150
-- each animation: how long it takes to come in, how fast it fades in, the size it
-- starts at, and Pop's size past full before it settles (seconds; 1 = Flash Size)
local FLASH_MOTION = {
	grow = { inT = 0.32, fadeIn = 0.08, from = 0.35 },
	pop = { inT = 0.36, fadeIn = 0.05, from = 0.45, over = 1.3 },
	fade = { inT = 0.2, fadeIn = 0.2 },
}
local flashFrame        -- the spot (Unlock UI's box); flashFrame.body is what flashes
local flashQueue = {}   -- catalog entries waiting their turn, oldest first
local flashPlaying      -- the entry on screen now
local flashSampleOn     -- Unlock UI: a still sample sits on the spot

local function applyFlashPos()
	local f = flashFrame
	if not f then return end
	local rec = SV().flashPos
	if not (rec and SP.ApplyPositionRecord and SP:ApplyPositionRecord(f, rec)) then
		f:ClearAllPoints()
		f:SetPoint("CENTER", UIParent, "CENTER", FLASH_X, FLASH_Y)
	end
end

local function saveFlashPos(frame)
	frame = frame or flashFrame
	if not frame then return end
	local rec = SP.GetPositionRecord and SP:GetPositionRecord(frame)
	if rec then SV().flashPos = rec end
	applyFlashPos()
end

-- the texture and words the flash shows for a catalog entry (Combined Shocks:
-- the shock its icon shows now)
local function flashArt(entry)
	local f = frames[entry.key]
	if entry.combo then
		local idx = f and f.cycIdx or 1
		local tex = f and f.cycTex and f.cycTex[idx]
		local k = f and f.cycKeys and f.cycKeys[idx]
		local e = k and catalogByKey[k]
		return tex or GetSpellTextureC(8042) or 136024, e and e.name or entry.name
	end
	local id = clientSpellID(entry)
	return id and GetSpellTextureC(id) or 136024, entry.name
end

local flashDone   -- (below) a flash has faded: the next one in line, if any

-- One flash player: the frame on its spot and the body that flashes. The shared spot's
-- player is Unlock UI's "Ready Flash" box; a spell with a spot of its own gets its own
-- player, so flashes on different spots play at the same time.
local function newFlashFrame(name)
	local f = CreateFrame("Frame", name, UIParent)
	f:SetFrameStrata("HIGH")
	f:SetSize(96, 96)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(false)   -- a flash never takes a click
	local body = CreateFrame("Frame", nil, f)
	body:SetPoint("CENTER", f, "CENTER", 0, 0)   -- sized with the flash, scaled around its middle
	body:SetSize(96, 96)
	body:EnableMouse(false)
	f.body = body
	local bg = body:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(body); bg:SetColorTexture(0, 0, 0, 0.6)
	body.bg = bg
	local icon = body:CreateTexture(nil, "ARTWORK")
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	body.icon = icon
	-- the border: four plain edges (a backdrop's corner pieces came apart under Pop's
	-- quick size change and drew past the corners)
	local border = CreateFrame("Frame", nil, body)
	border:EnableMouse(false)
	border.edges = {}
	for i = 1, 4 do border.edges[i] = border:CreateTexture(nil, "OVERLAY") end
	body.border = border
	local glow = body:CreateTexture(nil, "OVERLAY", nil, 1)
	glow:SetTexture("Interface\\SpellActivationOverlay\\IconAlert")
	glow:SetTexCoord(0.00781250, 0.50781250, 0.27734375, 0.52734375)
	if SP.ShapeGlow then SP:ShapeGlow(glow, "alert") end   -- Glow Shape
	glow:SetBlendMode("ADD")
	body.glow = glow
	if SP.ShapeIconTexture then   -- Icon Shape (Ready Reminders): the icon and its backing
		SP:ShapeIconTexture(icon, icon, "ready")
		SP:ShapeIconTexture(bg, body, "ready")
	end
	local label = body:CreateFontString(nil, "OVERLAY")
	SP:SetSPFont(label, "alerts", 15, "OUTLINE")
	label:SetTextColor(1, 0.82, 0)
	label:Hide()
	body.label = label
	body.spPlayer = f
	body:Hide()
	f:Hide()
	return f
end

local function ensureFlash()
	if flashFrame then return flashFrame end
	flashFrame = newFlashFrame("ShamanPowerReadyFlash")
	flashFrame.spMoverLabel = "Ready Flash"   -- Unlock UI's box
	applyFlashPos()
	return flashFrame
end

local ownPlayers = {}   -- [catalog key] = the player of a spell with its own spot, made on its first flash
local playersOn = {}    -- [player] = true while it shows a flash

-- the page's Look on the flash, at the spell's Flash Size (its own, else the page's;
-- any setting change repaints it)
local function flashLook(entry, f)
	f = f or ensureFlash()
	entry = entry or f.spEntry   -- (a settings change repaints the spell it shows)
	f.spEntry = entry
	local body, sv = f.body, SV()
	local size
	if entry then size = IconOpt(entry, "flashSize") end
	size = size or sv.flashSize or 96
	if f.spSize ~= size then f:SetSize(size, size); body:SetSize(size, size); f.spSize = size end
	local edge = math.max(2, math.floor(size / 32 + 0.5))
	body.icon:ClearAllPoints()
	body.icon:SetPoint("TOPLEFT", body, "TOPLEFT", edge, -edge); body.icon:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -edge, edge)
	body.border:ClearAllPoints()
	body.border:SetPoint("TOPLEFT", body, "TOPLEFT", -edge, edge); body.border:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", edge, -edge)
	if body.border.spEdge ~= edge then
		local b, e = body.border, body.border.edges
		e[1]:ClearAllPoints(); e[1]:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0); e[1]:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, 0); e[1]:SetHeight(edge)
		e[2]:ClearAllPoints(); e[2]:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0); e[2]:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0); e[2]:SetHeight(edge)
		e[3]:ClearAllPoints(); e[3]:SetPoint("TOPLEFT", e[1], "BOTTOMLEFT", 0, 0); e[3]:SetPoint("BOTTOMLEFT", e[2], "TOPLEFT", 0, 0); e[3]:SetWidth(edge)
		e[4]:ClearAllPoints(); e[4]:SetPoint("TOPRIGHT", e[1], "BOTTOMRIGHT", 0, 0); e[4]:SetPoint("BOTTOMRIGHT", e[2], "TOPRIGHT", 0, 0); e[4]:SetWidth(edge)
		body.border.spEdge = edge
	end
	local hideBg, hideBorder, borderColor
	if entry then
		hideBg, hideBorder, borderColor = IconOpt(entry, "hideBackground"), IconOpt(entry, "hideBorder"), IconOpt(entry, "borderColor")
	else
		hideBg, hideBorder, borderColor = sv.hideBackground, sv.hideBorder, sv.borderColor
	end
	local borderOn = not hideBg and not hideBorder
	local ringFile = SP.BorderRingFile and SP:BorderRingFile("ready")
	body.bg:SetShown(not hideBg)
	body.border:SetShown(borderOn and not ringFile)
	do
		local r, g, b = color(borderColor, 0.2, 0.7, 1.0)
		for i = 1, 4 do body.border.edges[i]:SetColorTexture(r, g, b, 1) end
	end
	if ringFile then
		if not body.ring then
			body.ring = body:CreateTexture(nil, "OVERLAY")
			body.ring:SetAllPoints(body.border)
		end
		if body.ring.spFile ~= ringFile then body.ring:SetTexture(ringFile); body.ring.spFile = ringFile end
		body.ring:SetVertexColor(color(borderColor, 0.2, 0.7, 1.0))
		body.ring:SetShown(borderOn)
	elseif body.ring then
		body.ring:Hide()
	end
	-- the ready glow (Ready Effect Glow, or Glow + pulse), still, in the icon's Glow Color
	local fx = entry and IconOpt(entry, "readyEffect") or sv.readyEffect or "glow"
	local glowOn = fx == "glow" or fx == "both"
	local pad = math.floor(size * 0.21 + 0.5)
	body.glow:ClearAllPoints()
	body.glow:SetPoint("TOPLEFT", body, "TOPLEFT", -pad, pad); body.glow:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", pad, -pad)
	body.glow:SetVertexColor(color(entry and IconOpt(entry, "glowColor") or sv.glowColor, 0.3, 0.8, 1.0))
	body.glow:SetAlpha(0.8)
	body.glow:SetShown(glowOn)
	-- Show Spell Name (the spell's own, else the page's): under it, in the reminders' gold
	local nameOn
	if entry then nameOn = IconOpt(entry, "flashName") == true else nameOn = sv.flashName == true end
	if nameOn then
		SP:SetSPFont(body.label, "alerts", math.max(12, math.floor(size * 0.16 + 0.5)), "OUTLINE")
		body.label:ClearAllPoints()
		body.label:SetPoint("TOP", body, "BOTTOM", 0, -(edge + 4))
	end
	body.label:SetShown(nameOn)
	if entry then f:SetAlpha(IconOpt(entry, "opacity") or 1) else f:SetAlpha(sv.opacity or 1) end
	if entry then
		local tex, name = flashArt(entry)
		-- Combined Shocks set to Split: the shocks side by side, as its icon draws them
		-- (the first shock whole, the others as slices over it)
		local rf = entry.combo and shockStyle(sv) == "split" and frames[entry.key] or nil
		local n = rf and rf.cycN or 1
		if rf and rf.cycTex and rf.cycTex[1] then tex, name = rf.cycTex[1], entry.name end
		body.icon:SetTexture(tex)
		body.label:SetText(name or "")
		body.slices = body.slices or {}
		local iw = size - 2 * edge
		for i = 2, 3 do
			local sl = body.slices[i]
			if rf and i <= n and rf.cycTex[i] then
				if not sl then
					sl = body:CreateTexture(nil, "ARTWORK", nil, 1)
					body.slices[i] = sl
					if SP.ShapeIconTexture then SP:ShapeIconTexture(sl, body.icon, "ready") end   -- Icon Shape: the whole icon's shape
				end
				sl:ClearAllPoints()
				sl:SetPoint("TOPLEFT", body.icon, "TOPLEFT", iw * (i - 1) / n, 0)
				sl:SetPoint("BOTTOMLEFT", body.icon, "BOTTOMLEFT", iw * (i - 1) / n, 0)
				sl:SetWidth(iw / n)
				sl:SetTexture(rf.cycTex[i])
				sl:SetTexCoord(0.08 + 0.84 * (i - 1) / n, 0.08 + 0.84 * i / n, 0.08, 0.92)
				sl:Show()
			elseif sl then
				sl:Hide()
			end
		end
	end
end

local function easeOut(p) return 1 - (1 - p) * (1 - p) end
local function easeInOut(p)
	if p < 0.5 then return 2 * p * p end
	return 1 - 2 * (1 - p) * (1 - p)
end

-- one frame of the flash's motion (its OnUpdate, set only while a flash plays):
-- in (fade in, and grow or spring), hold, out (fade out; Grow and Fade swells a little)
local function flashStep(body)
	local m, t = body.spMotion, GetTime() - body.spT0
	local inT = m.inT
	local a, sc = 1, 1
	if t < m.fadeIn then a = t / m.fadeIn end
	if m.from and t < inT then
		if m.over then
			local up = inT * 0.55
			if t < up then sc = m.from + (m.over - m.from) * easeOut(t / up)
			else sc = m.over + (1 - m.over) * easeInOut((t - up) / (inT - up)) end
		else
			sc = m.from + (1 - m.from) * easeOut(t / inT)
		end
	end
	local outStart = inT + body.spHold
	if t >= outStart then
		local p = (t - outStart) / body.spOutT
		if p >= 1 then
			body:SetScript("OnUpdate", nil)
			body:SetScale(1)
			body:SetAlpha(0)
			flashDone(body.spPlayer)
			return
		end
		a = 1 - p
		if m.from and not m.over then sc = 1 + 0.12 * p end
	end
	body:SetScale(math.max(0.05, sc))
	body:SetAlpha(a)
end

local function stopFlashMotion(body)
	body:SetScript("OnUpdate", nil)
	body:SetScale(1)
end

-- the player for a spell's flash, on its spot: its own (Move This Flash), else the
-- shared one; the second answer says which
local function playerFor(entry)
	local rec = entry and SV().flashPositions[entry.key]
	if rec then
		local f = ownPlayers[entry.key]
		if not f then f = newFlashFrame(nil); ownPlayers[entry.key] = f end
		if not (SP.ApplyPositionRecord and SP:ApplyPositionRecord(f, rec)) then
			f:ClearAllPoints()
			f:SetPoint("CENTER", UIParent, "CENTER", FLASH_X, FLASH_Y)
		end
		local size = IconOpt(entry, "flashSize") or 96
		f:SetSize(size, size)
		return f, true
	end
	local f = ensureFlash()
	applyFlashPos()
	return f, false
end

-- does this player's spot overlap a flash on screen now (another spot placed on top)?
local function overlapsPlaying(f)
	local l, r, b, t = f:GetLeft(), f:GetRight(), f:GetBottom(), f:GetTop()
	if not (l and r and b and t) then return false end
	for p in pairs(playersOn) do
		if p ~= f then
			local pl, pr, pb, pt = p:GetLeft(), p:GetRight(), p:GetBottom(), p:GetTop()
			if pl and pr and pb and pt and l < pr and r > pl and b < pt and t > pb then return true end
		end
	end
	return false
end

local function flashPlay(entry, f)
	local body = f.body
	f.spPlaying = entry
	playersOn[f] = true
	if f == flashFrame then flashPlaying = entry end
	flashLook(entry, f)
	-- the spell's animation over its Time On Screen (start to finish)
	local m = FLASH_MOTION[IconOpt(entry, "flashAnim")] or FLASH_MOTION.grow
	local total = IconOpt(entry, "flashHold") or SV().flashHold or 1
	local outT = math.min(0.4, math.max(0.2, total * 0.35))
	body.spMotion, body.spOutT = m, outT
	body.spHold = math.max(0.05, total - m.inT - outT)
	body.spT0 = GetTime()
	if not f:IsShown() then f:Show() end
	body:Show()
	flashStep(body)
	body:SetScript("OnUpdate", flashStep)
end

-- a flash has faded: the ones waiting whose spot is free now play (in the order they
-- came), then the player hides unless one of them took it
flashDone = function(f)
	f = f or flashFrame
	if not f then return end
	f.spPlaying = nil
	playersOn[f] = nil
	if f == flashFrame then flashPlaying = nil end
	if flashSampleOn and f == flashFrame then return end   -- Unlock UI took the spot meanwhile: the sample stays
	local i = 1
	while i <= #flashQueue do
		local e = flashQueue[i]
		local pf = playerFor(e)
		if not pf.spPlaying and not overlapsPlaying(pf) then
			table.remove(flashQueue, i)
			flashPlay(e, pf)
		else
			i = i + 1
		end
	end
	if not f.spPlaying then f.body:Hide(); f:Hide() end
end

-- one flash for this spell: now, or after the ones waiting (never twice in the line)
-- A flash plays the moment its spell is ready, unless its spot overlaps a flash on
-- screen (the shared spot, or spots placed on top of each other): then it waits its
-- turn. Never twice in the line.
local function flashQueueUp(entry)
	if flashSampleOn then return end   -- Unlock UI is placing it
	local f = playerFor(entry)
	if f.spPlaying == entry then return end
	for i = 1, #flashQueue do if flashQueue[i] == entry then return end end
	if f.spPlaying or overlapsPlaying(f) then
		if #flashQueue < 8 then flashQueue[#flashQueue + 1] = entry end
		return
	end
	flashPlay(entry, f)
end

-- Ready Flash on for this icon (its own, else the page's). Only For Cooldowns Over
-- is the page's switch: an icon whose own menu turned the flash on always flashes
-- (as Sound When Ready). The length is measured as the sound's minimum is.
local function flashWanted(entry, duration)
	if not IconOpt(entry, "flash") then return false end
	if IconOpt(entry, "ownFlash") then return true end
	return soundLength(entry, duration) >= (IconOpt(entry, "flashMin") or 10)
end

local function readyFlash(f, duration)
	if flashWanted(f.entry, duration) then flashQueueUp(f.entry) end
end

-- Flash Early: once per cooldown, when the countdown (our estimate) reaches it;
-- the ready moment then brings no second flash. A cooldown no longer than Flash
-- Early flashes when it is ready instead.
local function flashEarlyCheck(f, duration, remaining)
	local early = IconOpt(f.entry, "flashEarly") or 0
	if early <= 0 or not duration or duration <= early or remaining > early then return end
	f.flashedEarly = true
	readyFlash(f, duration)
end

-- the page or any icon of its own has the flash on (the settings rows, Unlock UI)
local function flashUsedAnywhere()
	if SV().flash == true then return true end
	for _, own in pairs(iconTable()) do
		if type(own) == "table" and own.flash == true then return true end
	end
	return false
end

-- Test Flash: the spell asked for (its own menu's Test Flash), else the first spell
-- the icons show (any spell when none), right away
function SP:ReadyFlashTest(key)
	local pick = key and catalogByKey[key] or nil
	if not pick then
		for _, entry in ipairs(self.ReadyReminderSpells) do
			if spellOn(entry) and usable(entry) and playerKnows(entry) then pick = entry break end
		end
	end
	if not pick then
		for _, entry in ipairs(self.ReadyReminderSpells) do
			if usable(entry) and not entry.combo then pick = entry break end
		end
	end
	if not pick then return end
	local f, own = playerFor(pick)
	if not own then wipe(flashQueue) end
	flashSampleOn = nil
	flashPlay(pick, f)
end

-- Unlock UI: a still sample on the spot while it is placed (Demo(true)), gone after (Demo(false))
function SP:ReadyFlashDemo(on)
	local f = ensureFlash()
	local body = f.body
	if on then
		wipe(flashQueue)
		stopFlashMotion(body)
		flashPlaying = nil
		f.spPlaying = nil
		for _, p in pairs(ownPlayers) do stopFlashMotion(p.body); p.spPlaying = nil; p.body:Hide(); p:Hide() end
		wipe(playersOn)
		flashSampleOn = true
		local pick
		for _, entry in ipairs(self.ReadyReminderSpells) do
			if spellOn(entry) and usable(entry) and playerKnows(entry) and IconOpt(entry, "flash") then pick = entry break end
		end
		pick = pick or catalogByKey.earthshock
		flashLook(pick, f)
		applyFlashPos()   -- the shared spot's box
		body:SetAlpha(1)
		body:Show()
		f:Show()
	else
		flashSampleOn = nil
		body:Hide()
		f:Hide()
	end
end

-- a setting changed or a profile came in: the flash's spot and look again (once it exists)
function SP:ReadyFlashRefresh()
	if not flashFrame then return end
	applyFlashPos()   -- an import replaces its spot
	flashLook(nil)
end

-- Move Ready Flash: Unlock UI with only the shared flash's box
function SP:ReadyFlashMove()
	if SP.UnlockModuleFrames then SP:UnlockModuleFrames("readyflash") end
end

function SP:ReadyFlashResetPosition()
	SV().flashPos = nil
	applyFlashPos()
end

-- A spell's own flash spot (Move This Flash in its menu): Unlock UI gets a box for
-- every spell that has one, a still copy of its flash in the box. The box starts on
-- the shared spot; a drop there gives the spell its spot. Use Shared Spot takes it away.
local flashProxies = {}   -- [key] = the box's frame, made once
local flashMoveOnly       -- Move This Flash: the one spell whose box Unlock UI shows
local function flashProxy(key)
	local entry = catalogByKey[key]
	local p = flashProxies[key]
	if not p then
		p = CreateFrame("Frame", nil, UIParent)
		p:SetFrameStrata("HIGH")
		p.icon = p:CreateTexture(nil, "ARTWORK")
		p.icon:SetAllPoints(p)
		p.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		p.spFlashKey = key
		p.spMoverLabel = "Ready Flash: " .. entry.name
		p:Hide()
		flashProxies[key] = p
	end
	local size = IconOpt(entry, "flashSize") or 96
	p:SetSize(size, size)
	p.icon:SetTexture((flashArt(entry)))
	p.icon:SetAlpha(0.6)
	local rec = SV().flashPositions[key] or SV().flashPos
	if not (rec and SP.ApplyPositionRecord and SP:ApplyPositionRecord(p, rec)) then
		p:ClearAllPoints()
		p:SetPoint("CENTER", UIParent, "CENTER", FLASH_X, FLASH_Y)
	end
	return p
end
function SP:ReadyFlashSpellFrames()
	local out = {}
	if flashMoveOnly then
		if catalogByKey[flashMoveOnly] then out[1] = flashProxy(flashMoveOnly) end
		return out
	end
	for _, entry in ipairs(self.ReadyReminderSpells) do
		if SV().flashPositions[entry.key] then out[#out + 1] = flashProxy(entry.key) end
	end
	return out
end
function SP:ReadyFlashSpellDemo(on)
	if on then
		for _, p in ipairs(self:ReadyFlashSpellFrames()) do p:Show() end
	else
		flashMoveOnly = nil
		for _, p in pairs(flashProxies) do p:Hide() end
	end
end
local function saveFlashSpot(frame)
	local key = frame and frame.spFlashKey
	local rec = key and SP.GetPositionRecord and SP:GetPositionRecord(frame)
	if rec then SV().flashPositions[key] = rec; settingsChanged() end
end
function SP:ReadyFlashMoveSpell(key)
	if not catalogByKey[key] then return end
	flashMoveOnly = key
	if SP.UnlockModuleFrames then SP:UnlockModuleFrames("readyflashspell") end
end
function SP.ReadyFlashHasOwnSpot(_, key) return SV().flashPositions[key] ~= nil end
function SP.ReadyFlashUseShared(_, key)
	SV().flashPositions[key] = nil
	settingsChanged()
end
function SP:ReadyFlashResetSpellSpots()
	wipe(SV().flashPositions)
	for _, p in pairs(flashProxies) do p:Hide() end
	settingsChanged()
end
-- One spell's own flash spot (Unlock UI: that box's Reset): back on the shared spot
function SP:ReadyFlashResetSpellSpot(frame)
	local key = frame and frame.spFlashKey
	if not key then return self:ReadyFlashResetSpellSpots() end
	SV().flashPositions[key] = nil
	local rec = SV().flashPos
	if not (rec and self.ApplyPositionRecord and self:ApplyPositionRecord(frame, rec)) then
		frame:ClearAllPoints()
		frame:SetPoint("CENTER", UIParent, "CENTER", FLASH_X, FLASH_Y)
	end
	settingsChanged()
end

-- A buff In Its Own Spot (D52; its menu's Side, "Move This Buff"): Unlock UI gets a box
-- for each one, a still copy of the buff in it. It starts above its icon; a drop gives it
-- its spot, the box's Reset puts it back above the icon.
function SP:ReadyBuffSpotFrames()
	local out = {}
	for _, key in ipairs(Buff.SpotKeys({})) do
		local p = Buff.Proxy(key)
		if p then out[#out + 1] = p end
	end
	return out
end
function SP:ReadyBuffSpotDemo(on)
	if on then
		Buff.placing = true
		Buff.Pass(false, true)   -- the real buffs stay off while their boxes are placed
		for _, p in ipairs(self:ReadyBuffSpotFrames()) do p:Show() end
	else
		Buff.placing, Buff.moveOnly = nil, nil
		for _, p in pairs(Buff.proxies) do p:Hide() end
		self:UpdateReadyReminders()
	end
end
-- a buff's own spot, and the buff on it (out of combat: Unlock UI never runs in a fight)
function Buff.SaveSpot(frame)
	local key = frame and frame.spBuffKey
	local rec = key and SP.GetPositionRecord and SP:GetPositionRecord(frame)
	if not rec then return end
	SV().buffPositions[key] = rec
	settingsChanged()
	if catalogByKey[key] then Buff.Layout(catalogByKey[key]) end
end
-- one box's Reset: that buff back above its icon (Reset All Positions: every one)
function SP:ReadyBuffSpotReset(frame)
	local key = frame and frame.spBuffKey
	if not key then return self:ReadyBuffSpotResetAll() end
	SV().buffPositions[key] = nil
	settingsChanged()
	Buff.Proxy(key)
	if catalogByKey[key] then Buff.Layout(catalogByKey[key]) end
end
function SP:ReadyBuffSpotResetAll()
	wipe(SV().buffPositions)
	settingsChanged()
	for key in pairs(Buff.proxies) do Buff.Proxy(key) end
	Buff.LayoutAll()
end
-- Move This Buff: Unlock UI with that buff's box only
function SP:ReadyBuffMoveSpot(key)
	if not (catalogByKey[key] and catalogByKey[key].buff) then return end
	Buff.moveOnly = key
	if SP.UnlockModuleFrames then SP:UnlockModuleFrames("readybuffspot") end
end

-- ---------------------------------------------------------------------------
-- WoW: Forever: the REAL "ready". C_Spell.GetSpellCooldown's isActive and
-- isEnabled are never secret (readable in combat, measured 2026-09-30; Flame
-- Shock reports the shocks' shared cooldown), so they decide ready or cooling;
-- the estimate only times the countdown. isOnGCD can be trusted only while
-- SPELL_UPDATE_COOLDOWN is handled, so it is latched there; an active cooldown
-- never latched is unknown. isEnabled false = on hold (Nature's Swiftness until
-- its buff is used) = not ready. No answer = unknown: the estimate decides, as
-- before. The call makes a new table, so the flags are read only for the icons in
-- use: on SPELL_UPDATE_COOLDOWN / SPELL_UPDATE_CHARGES, when the cooldown widget's
-- OnCooldownDone wakes a pass, and when the estimate says a cooling spell is done.
-- A fresh read is kept in SPCompat's cooldown cache, so the pass after it reads
-- nothing new. Anniversary keeps its path (its numbers are readable).
-- ---------------------------------------------------------------------------
local FLAGS = IS_MAINLINE and C_Spell and C_Spell.GetSpellCooldown and SPCompat
	and SPCompat.CooldownTable and SPCompat.CooldownTableNow and true or false
local flagState = {}   -- [catalog key] = "cooling" | "ready"; nil = unknown
local flagGCD = {}     -- [catalog key] = isOnGCD as SPELL_UPDATE_COOLDOWN last reported it
local freshSerial, eventSerial = {}, 0   -- one fresh read per spell per event

-- the spell whose flags stand for the entry: its own (by name, as the cooldown
-- reads ask, so both use one cache entry); Combined Shocks: the first shock known
local function flagSpell(entry)
	local e = entry
	if entry.combo then
		e = nil
		for _, key in ipairs(SHOCK_FAMILY) do
			local s = catalogByKey[key]
			if s and usable(s) and playerKnows(s) then e = s break end
		end
		if not e then return nil end
	end
	local id = clientSpellID(e)
	if not id then return nil end
	local name = SPCompat.SpellName(id)
	if name == nil then return id end
	return name
end

-- fresh: a new read (else SPCompat's kept one); latch: SPELL_UPDATE_COOLDOWN is
-- being handled, so isOnGCD is kept; inEvent: one read per spell for this event
local function readFlags(entry, fresh, latch, inEvent)
	local spell = flagSpell(entry)
	local c
	if spell then
		if fresh and inEvent then
			if freshSerial[spell] == eventSerial then fresh = false else freshSerial[spell] = eventSerial end
		end
		local ok, v = pcall(fresh and SPCompat.CooldownTableNow or SPCompat.CooldownTable, spell)
		if ok and type(v) == "table" then c = v end
	end
	local key, st = entry.key, nil
	if c and plainBool(c.isActive) and plainBool(c.isEnabled) then
		if latch then
			local g = c.isOnGCD
			if plainBool(g) and g then flagGCD[key] = true else flagGCD[key] = false end
		end
		if not c.isEnabled then st = "cooling"               -- on hold
		elseif not c.isActive then st = "ready"
		elseif flagGCD[key] == true then st = "ready"        -- only the global cooldown
		elseif flagGCD[key] == false then st = "cooling"
		end                                                  -- active, never latched: unknown
	end
	flagState[key] = st
end

-- SPELL_UPDATE_COOLDOWN (isOnGCD trustworthy: latched) / SPELL_UPDATE_CHARGES
local function flagsAtEvent(latch)
	if not FLAGS then return end
	eventSerial = eventSerial + 1
	for _, entry in ipairs(SP.ReadyReminderSpells) do
		local f = frames[entry.key]
		if f and f.inUse then
			readFlags(entry, true, latch, true)
			f.flagRecheck = nil
		end
	end
end

-- login, a reload, a loading screen: first sight again, so nothing sounds for it
local function primeFlags()
	if not FLAGS then return end
	wipe(flagState); wipe(flagGCD)
	for _, f in pairs(frames) do f.wasReady = nil end
end

-- ---------------------------------------------------------------------------
-- Out of range. An icon on screen whose Out of Range setting is on (its own, or
-- the page's) and whose spell has a range is checked against the current target
-- (Riptide: a friendly one). Totems, Fire Nova, Nature's Swiftness, Mana Tide,
-- Water Shield ... have none and are never checked. The game reports changes:
-- EnableSpellRangeCheck, then SPELL_RANGE_CHECK_UPDATE; PLAYER_TARGET_CHANGED
-- samples too. The registration is one per spell, shared with other addons, and
-- the game's Cooldown Manager switches it off when it resets an item: so it is
-- asked for again whenever an icon starts being checked and at every target
-- change, and never switched off here. Registering does not report where things
-- stand, so a spell is sampled the moment its icon starts being checked. Only an
-- explicit, readable false is out of range: no target, a target the spell cannot
-- be cast on, or a hidden answer leave the icon as it is. The events are
-- registered only while an icon is being checked. A client that never sends
-- SPELL_RANGE_CHECK_UPDATE (none seen this session a second after the target
-- appeared) is sampled four times a second instead, only while a target exists
-- and an icon is checked; the first event for one of our spells ends that for
-- the session.
-- ---------------------------------------------------------------------------
local RANGE_API = C_Spell and C_Spell.IsSpellInRange and C_Spell.SpellHasRange and C_Spell.EnableSpellRangeCheck
	and true or false
local RANGE_FALLBACK_WAIT, RANGE_FALLBACK_EVERY = 1.0, 0.25
local rangeIDs = {}          -- [catalog key] = the spell ID checked, or false (no range, not known)
local tracked, trackedN = {}, 0
local rangeFrame, rangeTicker
local rangeEventSeen, rangeWaiting = false, false

local function rangeIDOf(entry)
	local id = rangeIDs[entry.key]
	if id ~= nil then return id or nil end
	id = false
	if RANGE_API then
		local cand
		if entry.combo then
			for _, key in ipairs(SHOCK_FAMILY) do
				local s = catalogByKey[key]
				if s and usable(s) and playerKnows(s) then cand = clientSpellID(s) break end
			end
		else
			cand = clientSpellID(entry)
		end
		if cand then
			local ok, has = pcall(C_Spell.SpellHasRange, cand)
			if ok and plainBool(has) and has then id = cand end
		end
	end
	rangeIDs[entry.key] = id
	return id or nil
end

-- true: out of range (a readable false); nil: in range, or unknown
local function rangeOut(id)
	local ok, v = pcall(C_Spell.IsSpellInRange, id, "target")
	if ok and plainBool(v) and not v then return true end
	return nil
end

local function hasTarget()
	local v = UnitExists("target")
	return plainBool(v) and v
end

local function setRangeLook(f)
	local look
	if f.oor then look = rangeLookOf(f) end
	if f.oorLook ~= look then f.oorLook = look; paintIcon(f) end
end

local function rangeSampleAll()
	for i = 1, trackedN do
		local f = tracked[i]
		f.oor = rangeOut(f.rangeID)
		setRangeLook(f)
	end
end

local function rangeStopFallback()
	if rangeTicker then rangeTicker:Cancel(); rangeTicker = nil end
end
local function rangeFallbackTick()
	if rangeEventSeen or trackedN == 0 or not hasTarget() then rangeStopFallback() return end
	rangeSampleAll()
end
local function rangeFallbackStart()
	rangeWaiting = false
	if rangeTicker or rangeEventSeen or trackedN == 0 or not hasTarget() then return end
	rangeTicker = C_Timer.NewTicker(RANGE_FALLBACK_EVERY, rangeFallbackTick)
end
local function rangeFallbackCheck()
	if rangeEventSeen or trackedN == 0 or not hasTarget() then rangeStopFallback() return end
	if not rangeTicker and not rangeWaiting then
		rangeWaiting = true
		C_Timer.After(RANGE_FALLBACK_WAIT, rangeFallbackStart)
	end
end

local function rangeOnEvent(_, event, id, inRange, checksRange)
	if event == "PLAYER_TARGET_CHANGED" then
		-- ask for the reports again (someone may have switched them off), then read now
		for i = 1, trackedN do pcall(C_Spell.EnableSpellRangeCheck, tracked[i].rangeID, true) end
		rangeSampleAll()
		rangeFallbackCheck()
		return
	end
	-- SPELL_RANGE_CHECK_UPDATE: one spell, any addon's; a hidden id: ours are read again
	local hiddenID = issecretvalue and issecretvalue(id)
	local mine = false
	for i = 1, trackedN do
		local f = tracked[i]
		if hiddenID or f.rangeID == id then
			mine = true
			if not hiddenID and plainBool(checksRange) and plainBool(inRange) then
				if checksRange and not inRange then f.oor = true else f.oor = nil end
			else
				f.oor = rangeOut(f.rangeID)
			end
			setRangeLook(f)
		end
	end
	if mine and not rangeEventSeen then rangeEventSeen = true; rangeStopFallback() end
end

-- Which icons are checked: worked out again by every update pass (positioning and
-- the setup tour's demo check none). A spell is registered (again) and sampled the
-- moment its icon starts being checked.
local function rangeSync()
	local n = 0
	local off = not RANGE_API or SP.readyPositioning or SP.readyDemoActive
	for _, f in pairs(frames) do
		local id
		if not off and f:IsShown() and f:GetParent() == UIParent and IconOpt(f.entry, "outOfRange") then
			id = rangeIDOf(f.entry)
		end
		if id then
			n = n + 1
			tracked[n] = f
			if f.rangeID ~= id then
				f.rangeID = id
				pcall(C_Spell.EnableSpellRangeCheck, id, true)
				f.oor = rangeOut(id)
			end
		else
			f.rangeID, f.oor = nil, nil
		end
		setRangeLook(f)
	end
	for i = n + 1, trackedN do tracked[i] = nil end
	trackedN = n
	if n > 0 then
		if not rangeFrame then
			rangeFrame = CreateFrame("Frame")
			if SPCompat and SPCompat.StressRegister then SPCompat.StressRegister(rangeFrame, "Ready Reminders (range)") end
			rangeFrame:SetScript("OnEvent", rangeOnEvent)
		end
		if not rangeFrame.spOn then
			rangeFrame.spOn = true
			pcall(rangeFrame.RegisterEvent, rangeFrame, "SPELL_RANGE_CHECK_UPDATE")
			rangeFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
		end
		rangeFallbackCheck()
	elseif rangeFrame and rangeFrame.spOn then
		rangeFrame.spOn = nil
		rangeFrame:UnregisterAllEvents()
		rangeStopFallback()
	end
end

-- the Out of Range look or color changed: every icon painted again
rangeRepaintAll = function()
	for _, f in pairs(frames) do
		setRangeLook(f)
		paintIcon(f)
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
	local cd = f.cooldown
	cd:SetHideCountdownNumbers(IconOpt(f.entry, "showCountdown") == false)
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

local function drawEngineCooldown(f)
	local style = IconOpt(f.entry, "sweepStyle") or "radial"
	local direction = IconOpt(f.entry, "sweepDirection") or "bottom"
	local barOn = (IconOpt(f.entry, "barStyle") or "none") ~= "none"
	if f.ecdOn and not f.cdChanged and f.ecdStyle == style and f.ecdDirection == direction and f.ecdBar == barOn then return end
	local id = clientSpellID(f.entry)
	if not id then return end
	local ok, d = pcall(C_Spell.GetSpellCooldownDuration, id, true)   -- true: not the global cooldown
	if not ok or d == nil then return end   -- tried again next pass
	f.ecdOn, f.ecdStyle, f.ecdBar, f.ecdDur, f.cdChanged = true, style, barOn, d, nil
	f.ecdDirection = direction
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
			if sheet.SetFillStyle then sheet:SetFillStyle("STANDARD") end
			sheet:SetFrameLevel(f:GetFrameLevel() + 1)
			f.engineSheet = sheet
			if SP.ShapeIconTexture then SP:ShapeIconTexture(sheet:GetStatusBarTexture(), f.icon, "ready") end   -- Icon Shape
		end
		-- Remaining time drains toward the edge opposite the returning color.
		sheet:SetReverseFill(direction ~= "top")
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

-- Countdown Only Under on the engine's countdown: a step on the real time left
-- (it may be a hidden value) gives the numbers' opacity, handed straight to
-- SetAlpha and never looked at. One curve per number of seconds, made once.
local underCurves = {}
local function underCurve(sec)
	local c = underCurves[sec]
	if c == nil then
		c = false
		if C_CurveUtil and C_CurveUtil.CreateCurve then
			local ok, made = pcall(C_CurveUtil.CreateCurve)
			if ok and made then
				local linear = Enum and Enum.LuaCurveType and Enum.LuaCurveType.Linear
				if made.SetType and linear then pcall(made.SetType, made, linear) end
				-- under the seconds: shown; from there up: hidden
				if pcall(made.AddPoint, made, math.max(0, sec - 0.05), 1) and pcall(made.AddPoint, made, sec, 0) then c = made end
			end
		end
		underCurves[sec] = c
	end
	return c or nil
end
local function engineCountdownUnder(f)
	local fs = f.cdText
	if fs == nil then
		local ok, got = pcall(f.cooldown.GetCountdownFontString, f.cooldown)
		fs = ok and got or false
		f.cdText = fs
	end
	if not fs then return end
	local under = IconOpt(f.entry, "countdownUnder") or 0
	local c = under > 0 and f.ecdDur and f.ecdDur.EvaluateRemainingDuration and underCurve(under)
	if c then
		local ok, a = pcall(f.ecdDur.EvaluateRemainingDuration, f.ecdDur, c)
		if ok and pcall(fs.SetAlpha, fs, a) then f.cdTextUnder = true return end
	end
	if f.cdTextUnder then f.cdTextUnder = nil; fs:SetAlpha(1) end
end

-- "Always" and "only while on cooldown" modes, on cooldown: dim, countdown, sweep, bar.
local function drawCooldown(f, start, duration, remaining)
	local e = f.entry
	setReady(f, false)
	if engineOn() and not SP.readyDemoActive then
		if f.ecdStartSeen ~= start then f.ecdStartSeen = start; f.realDone = nil end   -- a new cooldown
		drawEngineCooldown(f)
		-- Gray Out holds while the REAL cooldown runs: the game's end signal (realDone)
		-- brings the colour back even if our estimate still says cooling
		if f.realDone then setDesat(f, false) end
		-- dim while the REAL cooldown runs, full the moment it ends (the estimate may lag);
		-- "only while on cooldown" goes invisible (and stops catching clicks) then instead
		local onlyCooling = IconOpt(f.entry, "mode") == "cooldown"
		local _, dim = coolingLook(f)
		-- faded (D51): both inputs times the fade, plain numbers (the curve's answer is never read)
		local fade = f.fade or 1
		local readyA = onlyCooling and 0 or (IconOpt(e, "opacity") or 1)
		if f.ecdDur then curveAlpha(f, f.ecdDur, readyA * fade, dim * fade) end
		if f.realDone then f.fadeBase = readyA end   -- the game says it is over: the curve shows it ready
		if onlyCooling and f.realDone then curveMouseOff(f) end
		engineCountdownUnder(f)
		return
	end
	local under = IconOpt(f.entry, "countdownUnder") or 0
	if IconOpt(f.entry, "showCountdown") ~= false and (under <= 0 or remaining < under) then
		-- the text only changes once a second (or once a minute): build the string then, not ten times a second
		local shown = remaining >= 60 and -math.floor(remaining / 60) or math.ceil(remaining)
		if f.countShown ~= shown then
			f.countShown = shown
			f.count:SetText(shown < 0 and string.format("%dm", -shown) or string.format("%d", shown))
		end
	elseif f.countShown ~= false then f.countShown = false; f.count:SetText("") end
	local frac = duration > 0 and math.max(0, math.min(1, remaining / duration)) or 0
	local style = IconOpt(e, "sweepStyle") or "radial"
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
	if (IconOpt(e, "barStyle") or "none") ~= "none" then
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
	local hideAll = not sv.enabled or self:IsOff()
	if hideAll then
		for _, f in pairs(frames) do
			if f:IsShown() then f:Hide() end; f.wasReady = nil; f.gridVis = nil   -- gridVis: they appear anew
			setFade(f, 1)   -- (D51) a hidden icon is never faded
		end
		Buff.Pass(false, true)   -- (D52) their buffs too
		self.readyCooling = false   -- nothing to draw: sleep until an event wakes the ticker
		rangeSync()
		return
	end
	local now = GetTime()
	local inCombat = InCombatLockdown()
	local cooling = false   -- anything still counting down? if not, the ticker can sleep (see the subsystem callback)
	for _, entry in ipairs(self.ReadyReminderSpells) do
		local f = frames[entry.key]
		local want = spellOn(entry) and usable(entry) and playerKnows(entry)
		if f then f.inUse = want end   -- its flags are read on the cooldown events (Forever)
		-- Only In Combat (the icon's own, else the page's): hidden out of combat, or faded
		-- with Fade Instead of Hide (D51; not in "never", where it is never on screen)
		local faded = false
		if want and not inCombat and IconOpt(entry, "onlyInCombat") then
			if IconOpt(entry, "fadeInsteadOfHide") and IconOpt(entry, "mode") ~= "flash" then faded = true
			else want = false end
		end
		if want then
			if not f then f = self:CreateReadyReminderFrame(entry); f.inUse = true end
			local mode = IconOpt(entry, "mode") or "ready"
			setFade(f, faded and fadedOpacity(entry) or 1)   -- before any alpha this pass (in a fight: 1)
			-- WoW: Forever: the game's own flags decide (see readFlags); the estimate times it
			local st
			if FLAGS then
				if f.flagFresh then f.flagFresh = nil; readFlags(entry, true, false, false)
				elseif flagState[entry.key] == "cooling" then readFlags(entry, false, false, false) end
				st = flagState[entry.key]
			end
			local start, duration = cooldownOf(entry, st ~= nil)
			local ready, remaining = true, 0
			local timed = start and duration and duration > GCD_MAX
			if timed then
				remaining = start + duration - now
				ready = remaining <= 0
			end
			if st == "cooling" and timed and ready and not f.flagRecheck then
				-- the estimate's run is over: ask the game once (its end signal may not come)
				f.flagRecheck = true
				readFlags(entry, true, false, false)
				st = flagState[entry.key]
			end
			if FLAGS then
				if st == "cooling" and f.flagWas ~= "cooling" then
					f.flagRun = (f.flagRun or 0) + 1   -- a new cooldown: the last one's end signal is not this one's
					f.realDone = nil
				end
				if st ~= "cooling" then f.flagRecheck = nil end
				f.flagWas = st
			end
			if st == "ready" then
				ready, remaining = true, 0
			elseif st == "cooling" then
				ready = false
				if remaining < 0 then remaining = 0 end
				if not timed then
					-- a cooldown the game reports and we never timed: the engine draws it
					if engineOn() then start, duration = -f.flagRun, nil else start, duration = now, 0 end
				end
			end
			if not ready then
				cooling = true
				if timed and not f.flashedEarly and not faded then flashEarlyCheck(f, duration, remaining) end
			end
			f.gridReady = ready
			if ready then
				-- faded (D51): quiet; it still counts as seen ready, so the pull plays nothing for it
				if f.wasReady == false and not faded then
					readySound(f, f.lastDuration)
					if not f.flashedEarly then readyFlash(f, f.lastDuration) end   -- (Flash Early already flashed it)
				end
				f.wasReady, f.flashedEarly = true, nil
				if mode == "cooldown" or mode == "flash" then
					-- "only while on cooldown" / "never" (Ready Flash only): a ready spell has nothing to show
					if f:IsShown() then setReady(f, true); stopEffects(f); f:Hide() end
				else
					if not f:IsShown() then f:Show() end
					setReady(f, true)
				end
			elseif mode == "always" or mode == "cooldown" then
				f.wasReady = false; f.lastDuration = duration
				if not f:IsShown() then f:Show() end
				drawCooldown(f, start, duration, remaining)
			elseif mode == "flash" then
				-- never on screen (Ready Flash only): the pass still times it for the flash
				f.wasReady = false; f.lastDuration = duration
				stopEffects(f); curveMouseBack(f)
				if f:IsShown() then f:Hide() end
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
						-- faded (D51): the ready input times the fade (a plain number; the answer is never read)
						local readyA = IconOpt(entry, "opacity") or 1
						curved = curveAlpha(f, f.readyDur, readyA * (f.fade or 1), 0)
						f.fadeBase = f.realDone and readyA or 0   -- held at 0 while it cools: nothing to glide
					end
				end
				if not curved then
					curveMouseBack(f)
					if f:IsShown() then f:Hide() end
				end
			end
			if f.fadeGlide then fadeGlideNow(f) end   -- (D51) a fight ended: down to faded
		elseif f then
			-- not on screen now (switched off, or Only In Combat out of combat): it is
			-- first sight again when it comes back, as when every icon was hidden
			-- (a cooldown that ended meanwhile makes no sound at the next pull)
			if f:IsShown() then f:Hide() end
			f.wasReady, f.flashedEarly = nil, nil
			setFade(f, 1)   -- (D51) a hidden icon is never faded
		end
	end
	layoutGrid(false)
	rangeSync()
	-- (D52) each spell's buff on or off as its icon allows; a buff whose time this pass writes
	-- (a client with no duration binding) keeps the passes coming, as a countdown does
	local buffTicks = Buff.Pass(inCombat)
	self.readyCooling = cooling or buffTicks
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
			setFade(f, 1)       -- (D51) full while placed
			curveMouseBack(f)   -- draggable again
			stopEffects(f)
			f.cooldown:Hide(); f.overlay:Hide(); f.bar:Hide(); f.count:SetText(""); f.countShown = nil
			setDesat(f, false); f:SetAlpha(IconOpt(entry, "opacity") or 1)
			f.label:SetShown(IconOpt(entry, "showNames") == true); f:Show()
		end
	end
	layoutGrid(true)
	rangeSync()   -- nothing is range-checked while positioning
	Buff.Pass(false, true)   -- (D52) no buffs while the icons are placed
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

-- One reminder back where it starts (Unlock UI: that box's Reset). Grid: the block's spot, as above.
function SP:ResetReadyReminderPosition(frame)
	if gridOn() or not (frame and frame.entry) then return self:ResetReadyReminderPositions() end
	SV().positions[frame.entry.key] = nil
	applyPos(frame)
	gridDirty = true
	layoutGrid(self.readyPositioning)
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
		for _, f in pairs(frames) do setFade(f, 1) end   -- (D51) the previews keep the in-a-fight look
		self:UpdateAllReadyReminderAppearance()
		rangeSync()   -- the demo's icons are never range-checked
		Buff.Pass(false, true)   -- (D52) nor do the buffs show over the borrowed icons
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
					local mode = IconOpt(entry, "mode") or "ready"
					f.gridReady = t >= DEMO_CD
					if t < DEMO_CD then
						if mode == "always" or mode == "cooldown" then
							if not f:IsShown() then f:Show() end
							drawCooldown(f, now - t, DEMO_CD, DEMO_CD - t)
						elseif f:IsShown() then f:Hide(); stopEffects(f) end
					else
						readyCount = readyCount + 1
						if mode == "cooldown" then
							if f:IsShown() then setReady(f, true); stopEffects(f); f:Hide() end
						else
							if not f:IsShown() then f:Show() end
							setReady(f, true)
						end
					end
				elseif f and f:IsShown() then
					f:Hide()
				end
				if f then f.spDemoOff = not want end   -- ticked off: no cell in the settings preview's grid
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
		for _, f in pairs(frames) do stopEffects(f); f.cooldown:Hide(); f.overlay:Hide(); f.bar:Hide(); f.count:SetText(""); f.countShown = nil; f.spDemoHidden = nil; f.spDemoOff = nil; f:Hide() end
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
		if spellOn(entry) and usable(entry) and IconOpt(entry, "mode") ~= "flash" then
			out[#out + 1] = frames[entry.key] or self:CreateReadyReminderFrame(entry)
		end
	end
	return out
end

-- What Unlock UI boxes: the icons one by one, or in Grid placement the one block
-- (sized for every enabled icon; the demo fills and empties it meanwhile).
function SP:ReadyReminderMoverFrames()
	if not gridOn() then return self:ReadyReminderEnabledFrames() end
	if #self:ReadyReminderEnabledFrames() == 0 then return {} end   -- (makes the frames the block lays out)
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
			if SP.readyDemoActive and not spellOn(entry) then f.spDemoHidden = true; f.spDemoOff = true end
			return f
		end
	end
	SP:RegisterPreview("readyreminders", { frames = list, demo = "SP:ReadyRemindersDemo", pad = 24,
		pane = { grid = true, columns = 2, maxScale = 2.4 } })   -- settings-window pane only: big icons in a grid
	-- Ready Flash's spot (Unlock UI only: the settings preview never borrows it)
	SP:RegisterPreview("readyflash", { frame = function() return ensureFlash() end, demo = "SP:ReadyFlashDemo" })
end
if SP.RegisterPreview then
	-- the spells' own flash spots (Unlock UI only)
	SP:RegisterPreview("readyflashspell", { frame = function() return nil end, demo = "SP:ReadyFlashSpellDemo" })
	-- (D52) the buffs In Their Own Spot (Unlock UI only)
	SP:RegisterPreview("readybuffspot", { frame = function() return nil end, demo = "SP:ReadyBuffSpotDemo" })
end
if SP.UnlockModules then
	table.insert(SP.UnlockModules, {
		key = "readyflash", label = "Ready Flash",
		enabled = function() return SV().enabled ~= false and flashUsedAnywhere() end,
		save = function(frame) saveFlashPos(frame) end,
		reset = function() SP:ReadyFlashResetPosition() end,
	})
	table.insert(SP.UnlockModules, {
		key = "readyflashspell", label = "Ready Flash",
		frames = function() return SP:ReadyFlashSpellFrames() end,
		enabled = function() return SV().enabled ~= false and (flashMoveOnly ~= nil or next(SV().flashPositions) ~= nil) end,
		save = function(frame) saveFlashSpot(frame) end,
		reset = function() SP:ReadyFlashResetSpellSpots() end,
		resetOne = "ReadyFlashResetSpellSpot",   -- a box's Reset: that spell's own spot only
	})
	-- (D52) a buff In Its Own Spot: a box each
	table.insert(SP.UnlockModules, {
		key = "readybuffspot", label = "Buff",
		frames = function() return SP:ReadyBuffSpotFrames() end,
		enabled = function() return SV().enabled ~= false and #Buff.SpotKeys({}) > 0 end,
		save = function(frame) Buff.SaveSpot(frame) end,
		reset = function() SP:ReadyBuffSpotResetAll() end,
		resetOne = "ReadyBuffSpotReset",   -- a box's Reset: that buff only
	})
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
	-- (D52) each buff's display: its look, how the game draws it, on / off (never what the buff reads)
	for _, entry in ipairs(Buff.list) do
		local B = Buff.of[entry.key]
		out[#out + 1] = string.format("buff %-20s ids=%s look=%s drawn by=%s on=%s alpha=%s fails=%s waiting=%s", entry.buff.label,
			table.concat(entry.buff.ids, ","), tostring(IconOpt(entry, "buffLook")),
			B and (B.c and "game" or (B.P and "addon" or "-")) or "-", tostring(B and B.on), tostring(B and B.alpha),
			tostring(B and B.fails or 0), tostring(Buff.dirty == true))
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

-- ---------------------------------------------------------------------------
-- Settings per icon, for the settings window's Your Icons row and its
-- right-click menu (ShamanPower_Config ReadyIcons.lua). Every write goes one
-- way: the icons read their settings again and are drawn again.
-- ---------------------------------------------------------------------------
local function refreshIcons()
	SP:UpdateAllReadyReminderAppearance()   -- (reads every setting again: settingsChanged)
	SP:UpdateReadyReminders()
end
local function copyValue(v)
	if type(v) ~= "table" then return v end
	local t = {}
	for k, x in pairs(v) do t[k] = x end
	return t
end
SP.ReadyReminderKnown = playerKnows
-- (D52) the buff an icon's spell puts on you, for its menu: nil when it puts none on you in
-- this game. name, timed (it has a time left), known (it can come up now) and, when not,
-- the plain line saying why nothing shows yet (two rows, as the menu draws them).
function SP.ReadyReminderBuffInfo(_, key)
	local entry = catalogByKey[key]
	local b = entry and entry.buff
	if not (b and usable(entry)) then return nil end
	local info = b.info or {}
	b.info = info
	info.name, info.timed = b.label, b.timed
	local known
	if b.talent then
		known = Buff.KnowsTalent(b)
		info.line1 = "You don't have the " .. b.label .. " talent:"
	elseif b.setBonus then
		known = Buff.HasSetBonus(b)
		info.line1 = "You don't have the " .. Buff.SetName(b) .. " 4-piece bonus:"
	else
		known = playerKnows(entry)
		info.line1 = "You haven't learned " .. entry.name .. " yet:"
	end
	info.known = known and true or false
	info.line2 = "there's no buff to show yet."
	return info
end
-- (D52) Move This Buff: its box in Unlock UI (In Its Own Spot)
function SP.ReadyReminderBuffMove(_, key) SP:ReadyBuffMoveSpot(key) end
function SP.ReadyReminderIconOpt(_, key, opt)   -- what the icon uses now: its own, else the page's
	local entry = catalogByKey[key]
	return entry and IconOpt(entry, opt)
end
function SP.ReadyReminderPageOpt(_, opt) return SV()[opt] end
function SP.ReadyReminderOwnOpt(_, key, opt)    -- nil: the icon follows the page
	local own = iconTable()[key]
	if type(own) ~= "table" then return nil end
	return own[opt]
end
function SP.ReadyReminderHasOwn(_, key)
	local own = iconTable()[key]
	return type(own) == "table" and next(own) ~= nil
end
-- value nil: back to the page's setting
function SP.ReadyReminderSetIconOpt(_, key, opt, value)
	if not (catalogByKey[key] and ICON_KEY[opt]) then return end
	local icons = iconTable()
	local own = icons[key]
	if type(own) ~= "table" then
		if value == nil then return end
		own = {}
		icons[key] = own
	end
	own[opt] = copyValue(value)
	if opt == "mode" and value == "flash" and not IconOpt(catalogByKey[key], "flash") then own.flash = true end
	if next(own) == nil then icons[key] = nil end
	-- as the page's Countdown Text does: the game's own numbers switched on too
	if opt == "showCountdown" and value == true and SP.EnableCountdownNumbers then SP:EnableCountdownNumbers() end
	refreshIcons()
end
function SP.ReadyReminderResetIcon(_, key)
	local icons = iconTable()
	if icons[key] == nil then return end
	icons[key] = nil
	refreshIcons()
end
-- this icon's own settings become theirs (none: theirs are removed); targets: a key or a list
function SP.ReadyReminderCopyIcon(_, fromKey, targets)
	local icons = iconTable()
	local src = icons[fromKey]
	if type(targets) ~= "table" then targets = { targets } end
	for _, key in ipairs(targets) do
		if key ~= fromKey and catalogByKey[key] then
			if type(src) == "table" and next(src) ~= nil then
				local t = {}
				for k, v in pairs(src) do
					if not Buff.Skip(key, k) then t[k] = copyValue(v) end   -- (D52) no buff here: not its buff's settings
				end
				icons[key] = next(t) and t or nil
			else
				icons[key] = nil
			end
		end
	end
	refreshIcons()
end
-- Show, as the old page offered it: "always" split by the cooling look
-- (always_bright: full color while it cools)
function SP.ReadyReminderShowOf(_, key)
	local entry = catalogByKey[key]
	if not entry then return "ready" end
	local m = IconOpt(entry, "mode") or "ready"
	if m == "cooldown" or m == "flash" then return m end
	if m ~= "always" then return "ready" end
	if IconOpt(entry, "desaturate") == false and (IconOpt(entry, "dimOpacity") or 0.35) >= 1 then return "always_bright" end
	return "always"
end
function SP.ReadyReminderSetShow(_, key, v)
	local entry = catalogByKey[key]
	if not entry then return end
	local icons = iconTable()
	local own = icons[key]
	if type(own) ~= "table" then own = {}; icons[key] = own end
	if v == "cooldown" then
		-- starts in full color (it is the only look it has); Gray Out / Opacity still apply
		if IconOpt(entry, "mode") ~= "cooldown" then own.desaturate = false; own.dimOpacity = 1 end
		own.mode = "cooldown"
	elseif v == "always_bright" then
		own.mode = "always"; own.desaturate = false; own.dimOpacity = 1
	elseif v == "always" then
		own.mode = "always"; own.desaturate = true
		if (IconOpt(entry, "dimOpacity") or 0.35) >= 1 then own.dimOpacity = 0.35 end
	elseif v == "flash" then
		own.mode = "flash"; own.flash = true   -- the flash is all it shows: on
	else
		own.mode = "ready"
	end
	refreshIcons()
end
-- the icon's own settings as they are (nothing: it uses the defaults), for Copy Settings
function SP.ReadyReminderOwnSnapshot(_, key)
	local own = iconTable()[key]
	local t = {}
	if type(own) == "table" then for k, v in pairs(own) do t[k] = copyValue(v) end end
	return t
end
-- Paste Settings: a copied icon's settings become this icon's (exactly: what the
-- source used from the defaults, this one uses from them too)
function SP.ReadyReminderPasteSnapshot(_, key, snap)
	if not (catalogByKey[key] and type(snap) == "table") then return end
	local t = {}
	for k, v in pairs(snap) do
		if not Buff.Skip(key, k) then t[k] = copyValue(v) end   -- (D52) no buff here: not its buff's settings
	end
	iconTable()[key] = next(t) and t or nil
	refreshIcons()
end
-- Copy <Group> To All Icons: these settings of this icon, on every other icon; the
-- rest of their settings stay as they are
function SP.ReadyReminderCopyGroup(_, fromKey, opts)
	local icons = iconTable()
	local src = icons[fromKey]
	if type(src) ~= "table" then src = nil end
	for _, entry in ipairs(SP.ReadyReminderSpells) do
		local key = entry.key
		if key ~= fromKey and usable(entry) then
			local own = icons[key]
			if type(own) ~= "table" then own = {}; icons[key] = own end
			for _, opt in ipairs(opts) do
				local v = src and src[opt]
				if v == nil then own[opt] = nil else own[opt] = copyValue(v) end
			end
			if next(own) == nil then icons[key] = nil end
		end
	end
	refreshIcons()
end
-- Combined Shocks: how its icon shows the shocks (its menu's Shocks group)
function SP.ReadyReminderShockOpt(_, field)
	local sv = SV()
	if field == "shockIcon" then return shockStyle(sv) end
	if field == "shockPick" then
		if sv.shockIcon == "earth" then return "earthshock" end
		return sv.shockPick or "earthshock"
	end
	if field == "shockKeepLast" then return sv.shockKeepLast == true end
end
function SP.ReadyReminderSetShockOpt(_, field, v)
	local sv = SV()
	if field == "shockIcon" then
		if sv.shockIcon == "earth" then sv.shockPick = "earthshock" end   -- the old choice kept its shock
		sv.shockIcon = v
	elseif field == "shockPick" then
		if sv.shockIcon == "earth" then sv.shockIcon = "one" end
		sv.shockPick = v
	elseif field == "shockKeepLast" then
		sv.shockKeepLast = v and true or false
	else
		return
	end
	refreshIcons()
end
-- the module switched on and off (the sidebar's switch)
function SP.ReadyRemindersEnabled() return SV().enabled and true or false end
function SP.SetReadyRemindersEnabled(_, v)
	SV().enabled = v and true or false
	refreshIcons()
end
-- The "settings moved" notice at the top of the page (3.0.6 and 3.0.7 only), for
-- players who had Ready Reminders before; Got it hides it for good.
local function noticeVersionOK()
	local meta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
	local v = meta and meta("ShamanPower", "Version")
	if type(v) ~= "string" then return false end
	local a, b, c = v:match("^(%d+)%.(%d+)%.(%d+)")
	a, b, c = tonumber(a), tonumber(b), tonumber(c)
	-- 3.0.6 and 3.0.7 (3.0.5: this beta build, before its version goes up)
	return a == 3 and b == 0 and c ~= nil and c >= 5 and c <= 7
end
function SP.ReadyReminderNoticeShown()
	return SV().notice306 ~= true and noticeVersionOK()
end
function SP.ReadyReminderNoticeDone()
	SV().notice306 = true
	settingsChanged()
end
-- Unlock UI's mouse wheel over a Ready Reminders box: get, set, min, max, step, percent.
-- An icon's box: its own Icon Size / Opacity. The Grid block: every icon in it, each
-- a step. The flash: the spell's own Flash Size (a spell's own spot), or every
-- spell's that uses the shared spot.
function SP.ReadyReminderBoxAccess(_, what, frame)
	if not frame then return nil end
	local opt, lo, hi, step, pct = "iconSize", 24, 96, 2, false
	if what == "opacity" then opt, lo, hi, step, pct = "opacity", 0.2, 1, 0.05, true
	elseif what == "flashSize" then opt, lo, hi, step = "flashSize", 48, 200, 4
	elseif what == "buffOwnSize" then opt, lo, hi, step, pct = "buffOwnSize", 0.3, 1, 0.05, true end   -- (D52) a buff In Its Own Spot
	local targets = {}
	if what == "buffOwnSize" then
		targets[1] = frame.spBuffKey and catalogByKey[frame.spBuffKey] or nil
	elseif frame.entry and frame.entry.key and what ~= "flashSize" then
		targets[1] = frame.entry
	elseif frame.spFlashKey then
		targets[1] = catalogByKey[frame.spFlashKey]
	elseif what == "flashSize" then
		for _, entry in ipairs(SP.ReadyReminderSpells) do
			if usable(entry) and IconOpt(entry, "flash") and not SV().flashPositions[entry.key] then targets[#targets + 1] = entry end
		end
	else   -- the Grid block
		for _, entry in ipairs(SP.ReadyReminderSpells) do
			if spellOn(entry) and usable(entry) then targets[#targets + 1] = entry end
		end
	end
	if #targets == 0 then return nil end
	local first = targets[1]
	local function get() return IconOpt(first, opt) end
	local function set(v)
		local base = IconOpt(first, opt) or v
		local icons = iconTable()
		for _, entry in ipairs(targets) do
			local cur = IconOpt(entry, opt) or base
			local nv = math.max(lo, math.min(hi, cur + (v - base)))
			local own = icons[entry.key]
			if type(own) ~= "table" then own = {}; icons[entry.key] = own end
			own[opt] = nv
		end
		refreshIcons()
		if frame.spFlashKey then flashProxy(frame.spFlashKey) end
		if frame.spBuffKey then Buff.Proxy(frame.spBuffKey) end   -- (its box's copy, at the new size)
	end
	return get, set, lo, hi, step, pct
end
-- the same setting as its switch under Spells
function SP.ReadyReminderSetSpell(_, key, on)
	local entry = catalogByKey[key]
	if not entry then return end
	SV().spells[key] = on and true or false
	refreshIcons()
	if on and entry.combo then shocksTurnedOn() end
end
-- the icon's picture: one texture, or (Combined Shocks) each shock known
function SP.ReadyReminderIconTextures(_, key, out)
	local entry = catalogByKey[key]
	if not entry then return 0 end
	if entry.combo then
		local n = 0
		for _, k in ipairs(SHOCK_FAMILY) do
			local e = catalogByKey[k]
			if e and usable(e) and playerKnows(e) then n = n + 1; out[n] = GetSpellTextureC(clientSpellID(e)) or 136024 end
		end
		if n == 0 then n = 1; out[1] = GetSpellTextureC(8042) or 136024 end
		return n
	end
	local id = clientSpellID(entry)
	out[1] = id and GetSpellTextureC(id) or 136024
	return 1
end
-- a sound from the list, at the icon's volume (the menu's speaker buttons and Test Sound)
function SP.ReadyReminderPlaySound(_, name, key)
	local entry = key and catalogByKey[key]
	local vol = entry and IconOpt(entry, "soundVolume") or SV().soundVolume or 100
	if SP.PlaySoundWithVolume and SP.GetSoundFile then
		SP:PlaySoundWithVolume(SP:GetSoundFile(name or (entry and IconOpt(entry, "soundName")) or "Raid Warning"), vol, true)
	end
end

-- The page (D40, 2026-10-02): the notice, the Spells row and Position. Every other
-- setting lives in each icon's right-click menu (ShamanPower_Config ReadyIcons.lua).
local function InjectOptions()
	local root = SP.options
	if not (root and root.args and root.args.fluffy and root.args.fluffy.args) then return end
	if root.args.fluffy.args.readyreminders_section then return end
	local function refresh() SP:UpdateAllReadyReminderAppearance(); SP:UpdateReadyReminders() end
	local args = {
			-- 3.0.6 and 3.0.7: a card at the top for players who had Ready Reminders before
			-- (the settings window draws it: ReadyIcons.lua, the notice row)
			noticeHeader = { order = 0.01, type = "header", name = "Settings Moved",
				hidden = function() return not SP.ReadyReminderNoticeShown() end },
			notice306 = { order = 0.02, type = "description", width = "full",
				name = "Ready Reminders has moved to a per-spell settings menu.",
				hidden = function() return not SP.ReadyReminderNoticeShown() end },
			-- the Spells row: the settings window draws it (ReadyIcons.lua); the text is what a
			-- search finds (every setting is in an icon's menu)
			iconsHeader = { order = 0.1, type = "header", name = "Spells" },
			yourIcons = { order = 0.2, type = "description", width = "full",
				name = "Click a spell to show or hide it. Right-click it for its settings: Show, Only In Combat,"
					.. " Fade Instead of Hide, Look, When Ready, While On Cooldown, Out of Range, Sound and Ready Flash."
					.. " Vertical - Fills Back In, Sweep Direction: From The Top or From The Bottom."
					-- (D52) the buff a spell puts on you, in that spell's menu
					.. " Your buff on its icon (Improved Stormstrike, Stormpower ...): Show The Buff In The Icon's Corner,"
					.. " As Its Own Icon, In Its Own Spot or As An Edge Around The Icon; Time Left, Time Turns Gold Under, Edge Color." },

			move = { order = 1.5, type = "execute", name = "Move the Icons", width = 1.2,
				desc = "Unlocks just the reminder icons: drag each box where you want it, then press Done to come back here.",
				hidden = function() return not SP.UnlockModuleFrames end,
				func = function() SP:UnlockModuleFrames("readyreminders") end },
			flashMove = { order = 1.6, type = "execute", name = "Move Ready Flash", width = 1.2,
				desc = "Unlocks just the Ready Flash's spot: drag its box where you want it, then press Done to come back here. A spell can have its own spot too (Ready Flash > Move This Flash in its menu).",
				hidden = function() return not SP.UnlockModuleFrames or not flashUsedAnywhere() end,
				func = function() SP:ReadyFlashMove() end },
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
	}
	SP.OrderSettingsBands({ args = args }, {
		{ header = "noticeHeader", name = "Settings Moved", keys = { "notice306" } },
		{ header = "iconsHeader", name = "Spells", keys = { "yourIcons" } },
		{ header = "positionHeader", name = "Position", keys = { "arrange", "gridColumns", "gridGrow", "gridAlign", "move", "flashMove", "unlock", "layout", "spacing", "reset" },
			names = { move = "Move", unlock = "Unlock Position", layout = "Arrange As",
				spacing = "Spacing", reset = "Reset Position" } },
	})
	-- every write on this page: each icon reads its settings again (some setters draw nothing)
	for _, option in pairs(args) do
		if type(option) == "table" and type(option.set) == "function" then
			local set = option.set
			option.set = function(...) set(...); settingsChanged() end
		end
	end
	-- the notice and the Spells row, drawn by the settings window (ShamanPower_Config ReadyIcons.lua)
	SP.OptionCustomRow = SP.OptionCustomRow or {}
	SP.OptionCustomRow[args.yourIcons] = "readyIcons"
	SP.OptionCustomRow[args.notice306] = "readyNotice"
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

-- The "settings moved" notice is for players who had Ready Reminders before 3.0.6: a
-- saved table that loaded empty (or not at all) is a brand-new install.
do
	local nf = CreateFrame("Frame")
	nf:RegisterEvent("ADDON_LOADED")
	nf:SetScript("OnEvent", function(self, _, name)
		if name ~= "ShamanPower_ReadyReminders" then return end
		self:UnregisterEvent("ADDON_LOADED")
		local sv = rawget(_G, "ShamanPower_ReadyReminders")
		if type(sv) ~= "table" then sv = {}; ShamanPower_ReadyReminders = sv end
		if next(sv) == nil then sv.notice306 = true end
	end)
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
				-- WoW: Forever: the cooldowns' own flags, read while the event is handled
				if event == "SPELL_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_CHARGES" then
					flagsAtEvent(event == "SPELL_UPDATE_COOLDOWN")
				elseif event == "PLAYER_ENTERING_WORLD" then
					primeFlags()   -- after a loading screen: first sight again, no sound for it
				end
			end)
			wakeFrame = wake
			setTicking(SV().enabled and not SP:IsOff() and true or false)
		else
			C_Timer.NewTicker(0.1, function() SP:UpdateReadyReminders() end)
		end
	else
		knownCache = {}
		wipe(rangeIDs)   -- the spells known (and so which one a range is checked with) may have changed
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
	local entries = {
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
		{ key = "sweepDirection", label = "Sweep Direction",
		  get = function() return SV().sweepDirection end,
		  set = function(v)
			if v ~= "top" and v ~= "bottom" then return end
			SV().sweepDirection = v
			SP:UpdateAllReadyReminderAppearance(); SP:UpdateReadyReminders()
		  end,
		},
	}
	for _, entry in ipairs(SP.ReadyReminderSpells) do
		local key = entry.key
		entries[#entries + 1] = { key = "sweepDirection." .. key, label = entry.name .. " Sweep Direction",
			-- Keep inheritance: restoring a theme must not turn the shared default into an override.
			get = function() return SP:ReadyReminderOwnOpt(key, "sweepDirection") or "default" end,
			set = function(v)
				if v == "default" then SP:ReadyReminderSetIconOpt(key, "sweepDirection", nil)
				elseif v == "top" or v == "bottom" then SP:ReadyReminderSetIconOpt(key, "sweepDirection", v) end
			end }
	end
	SP:ThemeSpotSettings("mod.readyreminders", entries)
end

-- The Out of Range color is a theme color too (ShamanPowerTheme.lua Cards.RR): Reset
-- All Colors (and Reset Everything, which runs it) clears it with the module's
-- other colors, back to the game's red on the next read.
if SP.ResetAllColorsToDefault and hooksecurefunc then
	hooksecurefunc(SP, "ResetAllColorsToDefault", function()
		local sv = rawget(_G, "ShamanPower_ReadyReminders")
		if type(sv) == "table" then sv.rangeColor = nil end
		settingsChanged()
	end)
end
