-- ============================================================================
-- ShamanPower Ready Reminders: Shield's charges (3.0.9.17, A116; a CurseForge ask and the owner's picks)
-- With Show: Always the Shield reminder stays on screen while Lightning Shield or Water Shield is on you, and shows the
-- cooldown bar's shield parts on its icon, each its own switch:
--   Show Charge Bar    the cooldown bar's charge bar: inside the icon along its bottom, three pieces in Shield
--                      Charges' blue
--   Show Charge Count  the charges as a number, green 3, yellow 2, red 1: at the bottom right over the bar (the
--                      cooldown bar's), or large in the middle (Count Position: Center, Shield Charges')
-- Never one without the icon. Only When Missing (the default) draws none of it, and the reminder is as it was.
--
-- In a fight on WoW: Forever the game hides your buffs, so there the game draws them, in and out of fights: the count
-- and the bar's fill hang on the button of an AuraContainer slot filtered to both shields, which the game shows only
-- while one is on you (as on the cooldown bar's shield). Ours is the bar's backing and its dividers. Built out of
-- combat (a setting changed in a fight lands after it). Anniversary: the buff is read, all ours.
-- The settings previews and Unlock UI draw them with our own parts (Demo).
-- ============================================================================

local SP = ShamanPower
if not SP then return end
local API = SP.ReadyProcAPI   -- the Ready Reminders file's own helpers (it loads first, shamans only)
if not API then return end

local IconOpt, Buff = API.IconOpt, API.Buff

local C = { of = {} }   -- [reminder frame] = its state
SP.ReadyShieldCharges = C

local SEGMENTS = 3
local BLUE = { 0.2, 0.6, 1.0 }   -- Shield Charges' blue (the cooldown bar's charge bar)
local WHITE = "Interface\\Buttons\\WHITE8x8"

local function stateOf(f)
	local st = C.of[f]
	if not st then
		st = {}
		C.of[f] = st
		f.shieldSt = st
	end
	return st
end

-- the count's color, as the cooldown bar's: green 3 (or more), yellow 2, red 1
local function countRGB(n)
	if n >= 3 then return 0, 1, 0 elseif n == 2 then return 1, 1, 0 end
	return 1, 0, 0
end

-- what is on: nil when nothing is drawn (Only When Missing, or both switches off)
local function wants(e)
	if IconOpt(e, "shieldShow") ~= "always" then return nil end
	local count, bar = IconOpt(e, "shieldCount") ~= false, IconOpt(e, "shieldBar") ~= false
	if not (count or bar) then return nil end
	return count, bar, (IconOpt(e, "shieldCountPos") == "center") and "center" or "corner"
end

-- the bar's look (the cooldown bar's): a dark backing round it, the Shield Charge Bars texture, the blue
local function styleBar(bar, noBacking)
	if not noBacking then
		local back = bar:CreateTexture(nil, "BACKGROUND")
		back:SetPoint("TOPLEFT", bar, "TOPLEFT", -1, 1)
		back:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 1, -1)
		back:SetColorTexture(0, 0, 0, 0.6)
	end
	SP:SetSPStatusBarTexture(bar, "shieldcharges", WHITE)   -- Shield Charge Bars (Fonts & Textures)
	bar:SetStatusBarColor(BLUE[1], BLUE[2], BLUE[3])
	bar:SetMinMaxValues(0, SEGMENTS)
	bar:SetValue(0)
end

-- the count's font and spot: bottom right over the bar (the cooldown bar's), or large in the middle (Shield Charges')
local function placeCount(fs, f, st)
	fs:ClearAllPoints()
	if st.pos == "center" then
		SP:SetSPFont(fs, "charges", math.max(10, math.floor(st.size * 0.55 + 0.5)), "OUTLINE")
		fs:SetPoint("CENTER", f, "CENTER", 0, 0)
	else
		fs:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, st.barOn and (st.sh + 3) or 1)
	end
end
local function newCount(parent, center)
	local fs = parent:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	if not center then SP:AdoptSPFont(fs, "charges") end   -- (template font = the design; follows the Fonts settings)
	fs:SetText("")
	return fs
end

-- the game's number rule for the count: one color per count (a rule at 1 is what draws a single charge at all)
local fmt
local function formatter()
	if fmt ~= nil then return fmt or nil end
	fmt = false
	local U = C_StringUtil
	if not (U and U.CreateNumericRuleFormatter) then return nil end
	local ok, f = pcall(U.CreateNumericRuleFormatter)
	if not (ok and f and f.AddBreakpoint) then return nil end
	for n = 0, SEGMENTS do
		local r, g, b = countRGB(n)
		local text = (n == 0) and "" or ("|cff%02x%02x%02x%%d|r"):format(math.floor(r * 255), math.floor(g * 255), math.floor(b * 255))
		if not pcall(f.AddBreakpoint, f, { threshold = n, format = text }) then return nil end
	end
	fmt = f
	return f
end

-- ---------------------------------------------------------------------------
-- Our parts: the bar (backing, fill, dividers) and the count, laid out to the icon's size
-- ---------------------------------------------------------------------------
local function parts(f, st)
	if st.bar then return end
	local bar = CreateFrame("StatusBar", nil, f)
	bar:SetFrameLevel(f:GetFrameLevel() + 2)
	styleBar(bar)
	bar:Hide()
	local lines = CreateFrame("Frame", nil, f)
	lines:SetFrameLevel(f:GetFrameLevel() + 12)   -- over the game's button (its container at +6)
	lines:SetAllPoints(bar)
	lines.d = {}
	for i = 1, SEGMENTS - 1 do
		local d = lines:CreateTexture(nil, "OVERLAY")
		d:SetColorTexture(0, 0, 0, 0.9)
		lines.d[i] = d
	end
	lines:Hide()
	local texts = CreateFrame("Frame", nil, f)
	texts:SetAllPoints(f)
	texts:SetFrameLevel(f:GetFrameLevel() + 18)   -- over the icon's glow and the game's parts
	texts:EnableMouse(false)
	st.bar, st.lines, st.texts = bar, lines, texts
	st.corner, st.center = newCount(texts, false), newCount(texts, true)
end

local function layout(f, st, countOn, barOn, pos)
	local s = IconOpt(f.entry, "iconSize") or 48
	local w, h = f:GetWidth(), f:GetHeight()
	if st.lw == w and st.lh == h and st.lbar == barOn and st.lpos == pos and st.size == s then return end
	st.lw, st.lh, st.lbar, st.lpos, st.size = w, h, barOn, pos, s
	st.barOn, st.pos = barOn, pos
	local sh = math.max(3, math.floor(h * 0.14 + 0.5))   -- (the cooldown bar's: a seventh of the icon)
	st.sh = sh
	local bar = st.bar
	bar:ClearAllPoints()
	bar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 2, 2)
	bar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
	bar:SetHeight(sh)
	local sw = w - 4
	for i, d in ipairs(st.lines.d) do
		d:ClearAllPoints()
		d:SetWidth(1)
		d:SetPoint("TOP", bar, "TOPLEFT", sw * i / SEGMENTS, 0)
		d:SetPoint("BOTTOM", bar, "BOTTOMLEFT", sw * i / SEGMENTS, 0)
	end
	st.pos = "corner"; placeCount(st.corner, f, st)
	st.pos = "center"; placeCount(st.center, f, st)
	st.pos = pos
end

-- our own count and fill (Anniversary, the previews; on WoW: Forever the game's draw over them, ours stay empty)
local function paintOwn(st, countOn, barOn, pos, n)
	n = n or 0
	if barOn then
		local v = math.max(0, math.min(n, SEGMENTS))
		if st.lv ~= v then st.lv = v; st.bar:SetValue(v) end
		if not st.bar:IsShown() then st.bar:Show() end
		if not st.lines:IsShown() then st.lines:Show() end
	else
		if st.bar:IsShown() then st.bar:Hide() end
		if st.lines:IsShown() then st.lines:Hide() end
	end
	local show = countOn and n > 0
	local fs, other = st.corner, st.center
	if pos == "center" then fs, other = st.center, st.corner end
	other:SetText("")
	if show then
		fs:SetText(tostring(n))
		fs:SetTextColor(countRGB(n))
	else
		fs:SetText("")
	end
end

-- ---------------------------------------------------------------------------
-- The game's parts (WoW: Forever): one AuraContainer slot on both shields, built out of combat
-- ---------------------------------------------------------------------------
local function dropEngine(st)
	local c = st.c
	if not c then return end
	pcall(c.SetEnabled, c, false)
	pcall(c.SetUnit, c, "none")
	c:Hide()
	if st.holder then st.holder:Hide() end
	st.c, st.holder, st.cOn = nil, nil, nil
end

local function shieldMap()
	local map = {}
	for w = 1, 2 do
		local set = SP.ShieldAuraSets and SP.ShieldAuraSets[w]
		for _, id in ipairs(set and set.ids or {}) do map[id] = true end
	end
	return map
end

local function buildEngine(f, st, countOn, barOn, pos)
	dropEngine(st)
	local holder = CreateFrame("Frame", nil, f)
	holder:SetAllPoints(f); holder:EnableMouse(false)
	holder:SetFrameLevel(f:GetFrameLevel() + 6)
	local ok, c = pcall(CreateFrame, "AuraContainer", nil, holder, "CustomAuraContainerTemplate")
	if not (ok and c and type(c.AddAuraSlot) == "function") then holder:Hide(); st.failed = true return false end
	c:ClearAllPoints(); c:SetSize(1, 1); c:SetPoint("CENTER", f, "CENTER", 0, 0)
	c:SetFrameLevel(holder:GetFrameLevel() + 1)
	if c.SetEditModePreviewEnabled then pcall(c.SetEditModePreviewEnabled, c, false) end   -- (Edit Mode's made-up auras: never here)
	local made = false
	local okSlot = pcall(c.AddAuraSlot, c, "shield", "HELPFUL|PLAYER", {
		candidateFilters = { includeSpellIDs = shieldMap() },
		initializeFrame = function(button)
			button:ClearAllPoints()
			button:SetAllPoints(f)
			if button.SetMouseClickEnabled then pcall(button.SetMouseClickEnabled, button, false) end
			if button.SetMouseMotionEnabled then pcall(button.SetMouseMotionEnabled, button, false) end
			-- the bar: the game fills a copy laid over ours (our dividers ride above both)
			if barOn then
				local cb = CreateFrame("StatusBar", nil, button)
				cb:SetAllPoints(st.bar)
				styleBar(cb, true)
				pcall(button.SetApplicationBar, button, cb, { maxApplications = SEGMENTS, minApplications = 0 })
			end
			-- the count: in the same font and spot as ours, colored by the game's number rule
			if countOn then
				local texts = CreateFrame("Frame", nil, button)
				texts:SetAllPoints(f)
				texts:SetFrameLevel(f:GetFrameLevel() + 18)
				local fs = newCount(texts, pos == "center")
				placeCount(fs, f, st)
				SP:SPFontGameOwned(fs)   -- (on the game's button: a font change waits out fights and hidden auras)
				local rule = formatter()
				pcall(button.SetApplicationCount, button, fs, rule and { formatter = rule } or {})
			end
			made = true
		end,
	})
	if not (okSlot and made) then
		pcall(c.SetEnabled, c, false); c:Hide(); holder:Hide()
		st.failed = true
		return false
	end
	pcall(c.SetUnit, c, "player")
	pcall(c.SetEnabled, c, true)
	if c.UpdateAllAuras then pcall(c.UpdateAllAuras, c) end
	st.c, st.holder, st.cOn, st.failed = c, holder, true, nil
	return true
end

-- the game's parts as the settings say: made again when what they are built from changed (out of combat only)
local function ensureEngine(f, st, countOn, barOn, pos)
	local sig = table.concat({ tostring(countOn), tostring(barOn), pos, st.lw or 0, st.lh or 0 }, "|")
	if st.c and st.sig == sig then
		if not st.cOn then pcall(st.c.SetEnabled, st.c, true); st.cOn = true end
		if st.holder and not st.holder:IsShown() then st.holder:Show() end
		return true
	end
	if InCombatLockdown() or Buff.Locked() then
		if st.holder and not st.holder:IsShown() then st.holder:Show() end
		return st.c ~= nil   -- (the old ones until the fight ends)
	end
	local ok = buildEngine(f, st, countOn, barOn, pos)
	st.sig = ok and sig or nil
	return ok
end

-- ---------------------------------------------------------------------------
-- What the Ready Reminders file calls
-- ---------------------------------------------------------------------------
-- each pass, while the Shield reminder is in use (ready: no shield on you)
function C.Pass(f, ready)
	local e = f.entry
	local countOn, barOn, pos = wants(e)
	if countOn == nil then C.Idle(f, false) return end
	local st = stateOf(f)
	parts(f, st)
	layout(f, st, countOn, barOn, pos)
	if Buff.Engine() and ensureEngine(f, st, countOn, barOn, pos) then
		paintOwn(st, false, barOn, pos, 0)   -- (the game draws the count and the fill; ours: the empty bar under them)
	else
		paintOwn(st, countOn, barOn, pos, (not ready) and SP.ReadyShield.charges() or 0)
	end
end

-- off screen, Only When Missing, or both switches off: nothing drawn, the game's slot rests. prepare: switched on but
-- off screen for now (Only In Combat, Hide In Town): its game parts made now, out of combat, so the first fight has them
function C.Idle(f, prepare)
	if not f then return end
	local free = not InCombatLockdown() and not Buff.Locked()
	local countOn, barOn, pos = wants(f.entry)
	local st = C.of[f]
	if prepare and countOn ~= nil and free and Buff.Engine() and not (st and st.c) then
		st = stateOf(f)
		parts(f, st)
		layout(f, st, countOn, barOn, pos)
		ensureEngine(f, st, countOn, barOn, pos)
	end
	if not st then return end
	if st.bar then st.bar:Hide(); st.lines:Hide(); st.corner:SetText(""); st.center:SetText("") end
	if st.c and st.cOn then pcall(st.c.SetEnabled, st.c, false); st.cOn = false end
	if st.holder then st.holder:Hide() end
	if countOn == nil and free then dropEngine(st); st.sig = nil end
end

-- the previews, the setup tour and Unlock UI: our own parts at n charges (the game's set aside meanwhile)
function C.Demo(f, n)
	local countOn, barOn, pos = wants(f.entry)
	if countOn == nil then C.Idle(f, false) return end
	local st = stateOf(f)
	parts(f, st)
	layout(f, st, countOn, barOn, pos)
	if st.holder then st.holder:Hide() end
	paintOwn(st, countOn, barOn, pos, n)
end

-- the support code's line
function C.Diag(f)
	local st = f and C.of[f]
	return string.format("shield charges engine=%s built=%s failed=%s", tostring(Buff.Engine()), tostring(st ~= nil and st.c ~= nil),
		tostring(st and st.failed or false))
end
