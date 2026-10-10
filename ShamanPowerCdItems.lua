-- ShamanPowerCdItems
-- The Cooldown Bar's per-item settings (3.0.8): each item on the bar (the shield, the
-- weapon imbue and every cooldown) can have settings of its own. They live in the
-- profile as
--     opt.cdbarItem = { [cooldownType] = { [name] = value } }
-- and a value left nil falls back to today's shared key, so an update changes nothing
-- on screen until an item is given a value of its own. The settings page only CALLS the
-- API below; the bar reads every per-item value through SP:CdItemOpt (no allocation).
--
-- cooldownType: 1 Shield, 2 Totemic Call / Recall, 3 Reincarnation, 4 Nature's Swiftness,
-- 5 Mana Tide, 6 Bloodlust / Heroism, 7 Weapon Imbue, 8 Shamanistic Rage, 9 Elemental
-- Mastery, 10 Rage of the Farseer, 11 Totemic Projection. "cooldowns" = 2-6, 8-11.
--
-- NAME             VALUE                                     SHARED KEY (today)                       ITEMS
-- [show]
--   runOutOnly     boolean                                   cdbarRunOutOnly (false)                   all
--   runOutReady    "hide" | "keep"                           cdbarRunOutReady ("hide")                 cooldowns
--   runOutSecs     seconds                                   cdbarRunOutSecs (60)                      1, 7
--   almostSecs     seconds (0 allowed)                       cdbarAlmostSecs (5)                       cooldowns
-- [look]  (theme-able looks)
--   buttonStyle    "mirror" | a CDBAR_STYLE key              cdbarOwnStyle + cdbarStyle ("mirror")     1, 7
--   sweep          "none" | "greys" | "fills" | "radial"     cdbarShowColorSweep + cdbarSweepStyle     all (imbue: radial draws as greys)
--   sweepDirection "top" | "bottom"                          cdbarSweepDirection (by the sweep)        all
--   progressBar    boolean                                   cdbarShowProgressBars (true; imbue: true)  all
--   progressColor  boolean (true = spell color)              cdbarSpellColors (false)                  all
--   timeOnIcon     boolean                                   cdbarShowCDText (true)                    cooldowns, 7
--   ankhCount      boolean                                   showAnkhCount (false)                     3
-- [charges]
--   chargeCount    boolean                                   cdbarShowShieldCount (true)               1
--   colorCount     boolean                                   shieldChargeColors (true)                 1
--   chargeBar      boolean                                   cdbarShieldChargeBar (false)              1
-- [effects]  (button animations: never themes)
--   cueReady / cueReadyStyle       cdbarCueReady / cdbarCueReadyStyle ("pop")                          cooldowns
--   cueAlmost / cueAlmostStyle     cdbarCueAlmost / cdbarCueAlmostStyle ("glow")                       cooldowns
--   cueGone / cueGoneStyle         shield: cdbarCueShield / cdbarCueShieldStyle, imbue: cdbarCueImbue / cdbarCueImbueStyle ("shake")   1, 7
--   cueMark                        shield: cdbarCueShieldMark, imbue: cdbarCueImbueMark                1, 7
--   cueMissing                     cdbarCueMissing                                                     1, 7
--   cueMissingGlow                 cdbarCueMissingGlow                                                 1, 7
--   cueRunning / cueRunningStyle   cdbarCueRunning / cdbarCueRunningStyle ("red")                      1, 7
--   cueTimeColor                   cdbarCueTimeColor                                                   all
-- [flyout]
--   flyoutDirection "auto" | "above" | "below"               cdbarFlyoutDirection ("auto")             1, 7
--   flyoutIconSize  12..56                                   cooldownFlyoutButtonSize (22)             1, 7
--   flyoutOpacity   0.1..1.0                                 cooldownFlyoutOpacity (1.0)               1, 7
-- [clicks]
--   rightClickOther boolean                                  cdbarShieldRightClickOther (false)        1
-- [where]
--   onTotemBar      boolean                                  totemicCallOnTotemBar (false)             2
--
-- Type 12 = Earth Shield (TBC Anniversary: its button on the totem bar). Not a cooldown bar item
-- (no icon in the Items row, never copied by "all"): a data slot of its own, so Lightning / Water /
-- Earth never share state. Only runOutSecs, cueRunning and cueRunningStyle, falling back to the
-- same shared keys as before; its settings get a home on the Totem Bar's Earth Shield menu later.
--
-- Signature Moves (opt.cdbarCueSignature, one shared switch): while it is on and the Effects Look
-- (opt.cdbarCueLook) is not Standard, the theme writes its moves into the SHARED style keys, so the
-- five style names (cueReadyStyle, cueAlmostStyle, cueGoneStyle, cueRunningStyle) read the shared
-- value then, whatever an item has of its own.
-- (The same list, for the settings page: ~/.claude/shamanpower/3.0.8-alpha/CONTRACT-cdbar-items.final.md)

local SP = ShamanPower
if not SP then return end

local SHIELD, IMBUE = 1, 7
local ALL = { [1] = true, [2] = true, [3] = true, [4] = true, [5] = true, [6] = true, [7] = true, [8] = true, [9] = true, [10] = true, [11] = true }
local CDS = { [2] = true, [3] = true, [4] = true, [5] = true, [6] = true, [8] = true, [9] = true, [10] = true, [11] = true }
local SI = { [SHIELD] = true, [IMBUE] = true }
local CDS_IMBUE = { [2] = true, [3] = true, [4] = true, [5] = true, [6] = true, [7] = true, [8] = true, [9] = true, [10] = true, [11] = true }
local EARTH = 12   -- Earth Shield's own slot (see the top)
local SI_ES = { [SHIELD] = true, [IMBUE] = true, [EARTH] = true }

local GROUPS = {
	show    = { "runOutOnly", "runOutReady", "runOutSecs", "almostSecs" },
	look    = { "buttonStyle", "sweep", "sweepDirection", "progressBar", "progressColor", "timeOnIcon", "ankhCount" },
	charges = { "chargeCount", "colorCount", "chargeBar" },
	effects = { "cueReady", "cueReadyStyle", "cueAlmost", "cueAlmostStyle", "cueGone", "cueGoneStyle", "cueMark",
	            "cueMissing", "cueMissingGlow", "cueRunning", "cueRunningStyle", "cueTimeColor", "cueTimeOnly" },
	flyout  = { "flyoutDirection", "flyoutIconSize", "flyoutOpacity" },
	clicks  = { "rightClickOther" },
	where   = { "onTotemBar" },
}
local GROUP_ORDER = { "show", "look", "charges", "effects", "flyout", "clicks", "where" }

-- which items a name means something on
local APPLIES = {
	runOutOnly = ALL, runOutReady = CDS, runOutSecs = SI_ES, almostSecs = CDS,
	buttonStyle = SI, sweep = ALL, sweepDirection = ALL, progressBar = ALL, progressColor = ALL,
	timeOnIcon = CDS_IMBUE, ankhCount = { [3] = true },
	chargeCount = { [SHIELD] = true }, colorCount = { [SHIELD] = true }, chargeBar = { [SHIELD] = true },
	cueReady = CDS, cueReadyStyle = CDS, cueAlmost = CDS, cueAlmostStyle = CDS,
	cueGone = SI, cueGoneStyle = SI, cueMark = SI, cueMissing = SI, cueMissingGlow = SI, cueRunning = SI_ES, cueRunningStyle = SI_ES,
	cueTimeColor = ALL, cueTimeOnly = { [SHIELD] = true },
	flyoutDirection = SI, flyoutIconSize = SI, flyoutOpacity = SI,
	rightClickOther = { [SHIELD] = true }, onTotemBar = { [2] = true },
}

-- The shared key a name inherits on an item (a string; nil for the two built from two keys,
-- whose rule is the same on every item)
local GONE_KEY  = { [SHIELD] = "cdbarCueShield", [IMBUE] = "cdbarCueImbue" }
local GONES_KEY = { [SHIELD] = "cdbarCueShieldStyle", [IMBUE] = "cdbarCueImbueStyle" }
local MARK_KEY  = { [SHIELD] = "cdbarCueShieldMark", [IMBUE] = "cdbarCueImbueMark" }
local function sharedKey(name, t)
	if name == "cueGone" then return GONE_KEY[t] or "cdbarCueShield" end
	if name == "cueGoneStyle" then return GONES_KEY[t] or "cdbarCueShieldStyle" end
	if name == "cueMark" then return MARK_KEY[t] or "cdbarCueShieldMark" end
	return nil
end

local function onNotFalse(v) return v ~= false end
local function truthy(v) return v and true or false end

-- today's shared value for a name on an item, in the name's encoding (see the top)
local FALLBACK = {
	runOutOnly  = function(o) return truthy(o.cdbarRunOutOnly) end,
	runOutReady = function(o) return (o.cdbarRunOutReady == "keep") and "keep" or "hide" end,
	runOutSecs  = function(o) return o.cdbarRunOutSecs or 60 end,
	almostSecs  = function(o) local s = o.cdbarAlmostSecs if s == nil then s = 5 end return s end,
	buttonStyle = function(o)
		local s = o.cdbarStyle
		if o.cdbarOwnStyle and s and SP.CDBAR_STYLE and SP.CDBAR_STYLE[s] then return s end
		return "mirror"
	end,
	sweep = function(o)
		if o.cdbarShowColorSweep == false then return "none" end
		local s = o.cdbarSweepStyle
		if s == "fills" or s == "radial" then return s end
		return "greys"
	end,
	sweepDirection = function(o, t)
		local d = o.cdbarSweepDirection
		if d == "top" or d == "bottom" then return d end
		return (SP:CdItemOpt(t, "sweep") == "fills") and "bottom" or "top"
	end,
	-- (the imbue's bars never followed the shared switch: they always showed, so it inherits "on")
	progressBar   = function(o, t) if t == IMBUE then return true end return onNotFalse(o.cdbarShowProgressBars) end,
	progressColor = function(o) return truthy(o.cdbarSpellColors) end,
	timeOnIcon    = function(o) return onNotFalse(o.cdbarShowCDText) end,
	ankhCount     = function(o) return truthy(o.showAnkhCount) end,
	chargeCount   = function(o) return onNotFalse(o.cdbarShowShieldCount) end,
	colorCount    = function(o) return truthy(o.shieldChargeColors) end,
	chargeBar     = function(o) return truthy(o.cdbarShieldChargeBar) end,
	cueReady        = function(o) return truthy(o.cdbarCueReady) end,
	cueReadyStyle   = function(o) return o.cdbarCueReadyStyle or "pop" end,
	cueAlmost       = function(o) return truthy(o.cdbarCueAlmost) end,
	cueAlmostStyle  = function(o) return o.cdbarCueAlmostStyle or "glow" end,
	cueGone         = function(o, t) if t == IMBUE then return truthy(o.cdbarCueImbue) end return truthy(o.cdbarCueShield) end,
	cueGoneStyle    = function(o, t)
		if t == IMBUE then return o.cdbarCueImbueStyle or "shake" end
		return o.cdbarCueShieldStyle or "shake"
	end,
	cueMark         = function(o, t) if t == IMBUE then return truthy(o.cdbarCueImbueMark) end return truthy(o.cdbarCueShieldMark) end,
	cueMissing      = function(o) return truthy(o.cdbarCueMissing) end,
	cueMissingGlow  = function(o) return truthy(o.cdbarCueMissingGlow) end,
	cueRunning      = function(o) return truthy(o.cdbarCueRunning) end,
	cueRunningStyle = function(o) return o.cdbarCueRunningStyle or "red" end,
	cueTimeColor    = function(o) return truthy(o.cdbarCueTimeColor) end,
	cueTimeOnly     = function(o) return truthy(o.cdbarCueTimeOnly) end,
	flyoutDirection = function(o) return o.cdbarFlyoutDirection or "auto" end,
	flyoutIconSize  = function(o) return o.cooldownFlyoutButtonSize or 22 end,
	flyoutOpacity   = function(o) return o.cooldownFlyoutOpacity or 1.0 end,
	rightClickOther = function(o) return truthy(o.cdbarShieldRightClickOther) end,
	onTotemBar      = function(o) return truthy(o.totemicCallOnTotemBar) end,
}

-- the effect styles Signature Moves writes into the shared keys
local SIG_STYLE = { cueReadyStyle = true, cueAlmostStyle = true, cueGoneStyle = true, cueRunningStyle = true }

-- ---------------------------------------------------------------------------
-- Reading (the bar's passes: no allocation)
-- ---------------------------------------------------------------------------
function SP:CdItemOpt(t, name)
	local o = self.opt
	if not o then return nil end
	local items = o.cdbarItem
	-- Signature Moves on (a look other than Standard): the shared styles it wrote
	if SIG_STYLE[name] and o.cdbarCueSignature and o.cdbarCueLook ~= nil and o.cdbarCueLook ~= "standard" then items = nil end
	if items and t then
		local it = items[t]
		if it then
			local v = it[name]
			if v ~= nil then return v end
		end
	end
	local f = FALLBACK[name]
	if f then return f(o, t) end
	return nil
end

function SP:CdItemOwnOpt(t, name)
	local items = self.opt and self.opt.cdbarItem
	local it = items and t and items[t]
	if it then return it[name] end
	return nil
end

function SP:CdItemHasOwn(t)
	local items = self.opt and self.opt.cdbarItem
	local it = items and t and items[t]
	return (it ~= nil and next(it) ~= nil) and true or false
end

function SP:CdItemApplies(t, name)
	local a = APPLIES[name]
	return (a ~= nil and a[t] == true) and true or false
end

function SP:CdItemNames(group)
	return GROUPS[group]
end

-- Any item on the bar with this name on (truthy): the share code's existing switches, the
-- runtime's "is it on anywhere" checks
function SP:CdItemAny(name)
	for t = 1, EARTH do
		local a = APPLIES[name]
		if (not a or a[t]) and self:CdItemOpt(t, name) then return true end
	end
	return false
end

-- ---------------------------------------------------------------------------
-- Writing (the settings page)
-- ---------------------------------------------------------------------------
local function itemTable(self, t, make)
	local o = self.opt
	if not o or type(t) ~= "number" then return nil end
	local items = o.cdbarItem
	if not items then
		if not make then return nil end
		items = {}
		o.cdbarItem = items
	end
	local it = items[t]
	if not it and make then
		it = {}
		items[t] = it
	end
	return it, items
end

local function tidy(items, t)
	if items and items[t] and next(items[t]) == nil then items[t] = nil end
end

function SP:SetCdItemOpt(t, name, v)
	if not FALLBACK[name] then return end
	local it, items = itemTable(self, t, v ~= nil)
	if not it then return end
	it[name] = v
	tidy(items, t)
	self:CdItemChanged(t, name)
end

function SP:ResetCdItem(t)
	local items = self.opt and self.opt.cdbarItem
	if items then items[t] = nil end
	self:CdItemChanged(t)
end

-- Copy from's settings onto to: afterwards to reads the same as from for every name both
-- items have. A value from inherits is copied as "inherit" only when both fall back the same
-- way (the same shared key, the same rule); otherwise as the value it reads: the shield's and
-- the imbue's Gone keys differ, and the imbue's Progress Bar is on where the cooldowns follow
-- Show Progress Bars.
local function sameInherit(name, from, to)
	if sharedKey(name, from) ~= sharedKey(name, to) then return false end
	if name == "progressBar" and ((from == IMBUE) ~= (to == IMBUE)) then return false end
	return true
end

-- An item's settings as they are now, kept apart from the item (Copy Settings: Paste writes
-- these, whatever the item does meanwhile): per name, its own value (nil: it inherits) and
-- the value it reads.
function SP:CdItemSnapshot(t)
	local snap = { from = t, own = {}, eff = {} }
	for gi = 1, #GROUP_ORDER do
		for _, name in ipairs(GROUPS[GROUP_ORDER[gi]]) do
			local a = APPLIES[name]
			if a and a[t] then
				snap.own[name] = self:CdItemOwnOpt(t, name)
				snap.eff[name] = self:CdItemOpt(t, name)
			end
		end
	end
	return snap
end

local function pasteOne(self, snap, to, group)
	local from = snap.from
	if from == to then return end
	local groups = group and { group } or GROUP_ORDER
	for gi = 1, #groups do
		local names = GROUPS[groups[gi]]
		if names then
			for _, name in ipairs(names) do
				local a = APPLIES[name]
				if a and a[from] and a[to] then
					local v = snap.own[name]
					if v == nil and not sameInherit(name, from, to) then v = snap.eff[name] end
					local it, items = itemTable(self, to, v ~= nil)
					if it then
						it[name] = v
						tidy(items, to)
					end
				end
			end
		end
	end
end

local function copyOne(self, from, to, group)
	if from == to then return end
	pasteOne(self, self:CdItemSnapshot(from), to, group)
end

-- Paste Settings: a snapshot (SP:CdItemSnapshot) onto an item; to = "all" pastes onto every
-- other item
function SP:PasteCdItem(snap, to, group)
	if type(snap) ~= "table" or type(snap.own) ~= "table" then return end
	if to == "all" then
		for t = 1, 11 do pasteOne(self, snap, t, group) end
		self:CdItemChanged(nil)
		return
	end
	pasteOne(self, snap, to, group)
	self:CdItemChanged(to)
end

function SP:CopyCdItem(from, to, group)
	if to == "all" then
		for t = 1, 11 do copyOne(self, from, t, group) end
		self:CdItemChanged(nil)
		return
	end
	copyOne(self, from, to, group)
	self:CdItemChanged(to)
end

-- ---------------------------------------------------------------------------
-- Refresh after a change: out of a fight at once; in a fight it waits for the fight's end
-- (WoW: Forever's game-drawn shield display and the bar's buttons are made out of fights only)
-- ---------------------------------------------------------------------------
local REMAKE = { buttonStyle = true, onTotemBar = true }   -- the bar is made again
local SHIELD_DISPLAY = { sweep = true, sweepDirection = true, progressBar = true, chargeCount = true, colorCount = true,
	chargeBar = true, cueTimeColor = true, cueRunning = true, cueRunningStyle = true, runOutSecs = true }

local pending = false
function SP:CdItemChanged(t, name)
	if InCombatLockdown() then
		pending = true
		return
	end
	if name == nil or REMAKE[name] then
		-- Reset / Copy / the button style / where Totemic Call sits: made again (RecreateCooldownBar
		-- also builds the shield's game-drawn display and the flyouts afresh)
		if self.RecreateCooldownBar then self:RecreateCooldownBar() end
		if (t == nil or t == 2) and self.UpdateMiniTotemBar then self:UpdateMiniTotemBar() end
	else
		if t == SHIELD and SHIELD_DISPLAY[name] and self.RebuildShieldChargeContainer then self:RebuildShieldChargeContainer() end
		if name == "flyoutIconSize" then
			if self.ApplyCooldownFlyoutButtonSize then self:ApplyCooldownFlyoutButtonSize() end
		elseif name == "flyoutDirection" or name == "flyoutOpacity" then
			if self.LayoutShieldFlyout and self.shieldFlyout then self:LayoutShieldFlyout() end
			if self.LayoutWeaponImbueFlyout and self.weaponImbueFlyout then self:LayoutWeaponImbueFlyout() end
			if self.UpdateCooldownFlyoutOpacity then self:UpdateCooldownFlyoutOpacity() end
		elseif name == "rightClickOther" then
			if self.ApplyShieldButtonClicks then self:ApplyShieldButtonClicks() end
		elseif name == "progressBar" then
			self.cdbarAnyProgressVisible = nil   -- the bar's room for its progress bars: worked out again
		end
		if self.UpdateCooldownBar and self.cooldownBar then self:UpdateCooldownBar() end
	end
	-- the effects and Show: the looks start afresh, the bar's next pass (at once) puts back what is wanted
	if self.ApplyCueSettings then self:ApplyCueSettings() end
end

do
	local f = CreateFrame("Frame")
	f:RegisterEvent("PLAYER_REGEN_ENABLED")
	f:SetScript("OnEvent", function()
		if not pending then return end
		pending = false
		SP:CdItemChanged(nil)
	end)
end
