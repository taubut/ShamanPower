ShamanPower = LibStub("AceAddon-3.0"):NewAddon("ShamanPower", "AceConsole-3.0", "AceEvent-3.0", "AceBucket-3.0", "AceTimer-3.0")
-- Every chat line starts with the style guide's blue prefix (|cff0070ddShamanPower|r:);
-- AceConsole's own Print would draw the name green. An optional first chat frame is kept.
function ShamanPower:Print(...)
	local frame = DEFAULT_CHAT_FRAME
	local first = 1
	local a = ...
	if type(a) == "table" and a.AddMessage then frame, first = a, 2 end
	local parts = {}
	for i = first, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
	frame:AddMessage("|cff0070ddShamanPower|r: " .. table.concat(parts, " "))
end

ShamanPower.isVanilla = (_G.WOW_PROJECT_ID == _G.WOW_PROJECT_CLASSIC)
ShamanPower.isBCC = (_G.WOW_PROJECT_ID == _G.WOW_PROJECT_BURNING_CRUSADE_CLASSIC)
ShamanPower.isWrath = (_G.WOW_PROJECT_ID == _G.WOW_PROJECT_WRATH_CLASSIC)

-- "First Surname" on WoW: Forever (SPCompat.UnitName); other clients unchanged
local UnitName = (SPCompat and SPCompat.UnitName) or UnitName
local GetRaidRosterInfo = (SPCompat and SPCompat.GetRaidRosterInfo) or GetRaidRosterInfo
local L = LibStub("AceLocale-3.0"):GetLocale("ShamanPower", true)
if not L then
	L = setmetatable({}, {__index = function(t, k) return k end})
end
local LSM3 = LibStub("LibSharedMedia-3.0")

-- Register WoW built-in sounds with LibSharedMedia
-- (LSM:Register rejects "Sound\\" prefix, so insert directly into MediaTable)
-- The Classic line plays these by path. The Mainline family (WoW: Forever)
-- refuses a "Sound\\..." path outright - PlaySoundFile returns nothing and
-- every alert picked from this list was silent there - and plays Blizzard's
-- files by FileDataID only, so each entry carries both (IDs from the client's
-- file list; 567397 = RaidWarning.ogg was measured to play on Forever).
local SP_SOUNDS = {
	["Raid Warning"]          = { [[Sound\Interface\RaidWarning.ogg]],          567397 },
	["Alarm Clock Warning 1"] = { [[Sound\Interface\AlarmClockWarning1.ogg]],  567436 },
	["Alarm Clock Warning 2"] = { [[Sound\Interface\AlarmClockWarning2.ogg]],  567399 },
	["Alarm Clock Warning 3"] = { [[Sound\Interface\AlarmClockWarning3.ogg]],  567458 },
	["Ready Check"]           = { [[Sound\Interface\ReadyCheck.ogg]],           567409 },
	["Map Ping"]              = { [[Sound\Interface\MapPing.ogg]],              567416 },
	["PVP Flag Taken"]        = { [[Sound\Interface\PVPFlagTaken.ogg]],         567466 },   -- PVPFlagTakenMono.ogg on Mainline
	["Quest Failed"]          = { [[Sound\Interface\igQuestFailed.ogg]],        567459 },
	["Level Up"]              = { [[Sound\Interface\LevelUp.ogg]],              567431 },
}
local SP_SOUND_BY_ID = (SPCompat.FOREVER)
for name, entry in pairs(SP_SOUNDS) do
	LSM3.MediaTable.sound[name] = SP_SOUND_BY_ID and entry[2] or entry[1]
end
local LUIDDM = LibStub("LibUIDropDownMenu-4.0")

-- Patch 2.5.6+: IsUnderMouse(true) returns nil in the secure restricted
-- environment (recursive form broken by the Midnight shared UI code brought
-- to Classic). "not nil" is true, so flyouts closed unconditionally on every
-- OnLeave. Fix: walk children explicitly using the still-working
-- non-recursive IsUnderMouse().
local SP_SECURE_ONLEAVE_SELF = [[
	if self:IsUnderMouse() then return end
	local children = newtable(self:GetChildren())
	for i = 1, #children do
		local c = children[i]
		if c:IsShown() and c:IsUnderMouse() then return end
	end
	self:ChildUpdate("show", false)
]]

-- Flyout button leave, Classic clients (verified on Anniversary, issue #17):
-- any shown sibling under the cursor keeps the flyout open, so moving between
-- adjacent flyout buttons never closes it.
local SP_SECURE_ONLEAVE_PARENT_CLASSIC = [[
	local parent = self:GetParent()
	if parent:IsUnderMouse() then return end
	local children = newtable(parent:GetChildren())
	for i = 1, #children do
		local c = children[i]
		if c:IsShown() and c:IsUnderMouse() then return end
	end
	parent:ChildUpdate("show", false)
]]

-- Mainline (retail / Forever) fires OnLeave (motion=true) the instant a secure
-- click casts and drops mouse focus while the cursor is still over the button.
-- At that moment the button itself and any decoration parked at the same spot
-- (pulse frame, active overlay) are geometrically "under the mouse", so only
-- siblings that take part in the flyout protocol may keep the flyout open.
-- They are marked with the spFlyoutProtocol attribute: the restricted
-- environment refuses to read any attribute whose name starts with "_", so
-- testing for the _onleave snippet itself always came back nil.
local SP_SECURE_ONLEAVE_PARENT_MAINLINE = [[
	local parent = self:GetParent()
	if parent:IsUnderMouse() then return end
	local children = newtable(parent:GetChildren())
	for i = 1, #children do
		local c = children[i]
		if c ~= self and c:GetAttribute("spFlyoutProtocol") and c:IsShown() and c:IsUnderMouse() then return end
	end
	parent:ChildUpdate("show", false)
]]

local SP_SECURE_ONLEAVE_PARENT = (SPCompat.FOREVER)
	and SP_SECURE_ONLEAVE_PARENT_MAINLINE or SP_SECURE_ONLEAVE_PARENT_CLASSIC

-- Every secure snippet write goes through here.
--
-- A client that cannot compile snippet bodies throws a Lua error every single
-- time the script fires, which on an _onenter snippet means an error per
-- mouseover. Forever beta 1.60.1.69913 is such a client: Blizzard's
-- RestrictedExecution.lua captures `loadstring_untainted` as an upvalue, but
-- that global only exists in the secure environment, so the upvalue is nil and
-- compilation dies at its line 79. Writing the attribute there buys nothing
-- (the snippet can never run) and costs an error storm, so we simply do not
-- write it, and actively clear any stale value.
--
-- SPCompat.SecureSnippetsWork() probes rather than checking the client, so the
-- secure path returns by itself the moment Blizzard fixes it.
function ShamanPower:SetSnippet(frame, attr, body)
	if not frame or not frame.SetAttribute then return false end
	if self:FlyoutBoxMode() then
		frame:SetAttribute(attr, nil)
		ShamanPower:WireFlyoutFallback(frame, attr)
		return false
	end
	frame:SetAttribute(attr, body)
	return true
end

-- ---------------------------------------------------------------------------
-- Plain-script flyout fallback.
--
-- The secure snippets ARE the flyout: the parent broadcasts ChildUpdate("show")
-- on enter, each child decides whether to appear, and leave hides them once the
-- cursor is off the parent and every shown child. On a client that cannot
-- compile snippets none of that runs, so flyouts never open at all and there is
-- no way to pick a different totem.
--
-- This reproduces the same protocol with ordinary scripts. It only works out of
-- combat, because Show and Hide are protected methods on this client, and that
-- is the honest trade: a flyout that works while you are standing still beats
-- one that never works. In combat the buttons keep whatever the bar assigned.
--
-- Wired from SetSnippet so every flyout in the addon is covered by the same
-- code, and so it disappears by itself the moment snippets start working again.
-- ---------------------------------------------------------------------------
local FLYOUT_LEAVE_GRACE = 0.08   -- lets the cursor cross the gap parent->child

-- ---------------------------------------------------------------------------
-- Click-to-open flyouts that work IN COMBAT without snippets ("box mode").
--
-- Measured on the Forever beta (2026-09-21), all three in combat:
--   * a SecureActionButton of type "attribute" may set an attribute on a
--     protected frame (SECURE_ACTIONS.attribute is plain Lua, no snippet);
--   * a protected frame registered with RegisterUnitWatch is shown/hidden by
--     Blizzard's own manager according to its "unit" attribute ("player"
--     exists -> shown, "none" -> hidden), re-checked every 0.2 s;
--   * a macro may press such a button with "/click Name LeftButton 1" (the
--     bare form sends a release, which key-down casting ignores).
-- So each element's flyout buttons live in one watched box; an arrow on the
-- totem button opens it, a second arrow inside it closes it, and picking a
-- totem casts and closes in the same click. Out of combat the hover behaviour
-- is unchanged, it just drives the same box. Only used while snippets are
-- broken, so it retires itself when Blizzard fixes them.
-- ---------------------------------------------------------------------------
local FLYOUT_ARROW = 16   -- room the arrow tab takes between the totem button and its flyout

-- Blizzard's own totem-bar flyout tabs (Interface\\Buttons\\UI-TotemBar, 128x256):
-- a 28x18 tab per element, one pointing away from the button (open) and one
-- pointing back at it (close), plus a 20x11 additive glow for hover. Values
-- are the ones in Blizzard_ActionBar/Shared/MultiCastActionBarFrame.lua.
-- Indexed by ShamanPower element: 1 Earth, 2 Fire, 3 Water, 4 Air.
local ARROW_TEXTURE = "Interface\\Buttons\\UI-TotemBar"
local ARROW_W, ARROW_H = 28, 18
local ARROW_OPEN = {
	{ 99 / 128, 127 / 128, 160 / 256, 178 / 256 },   -- earth
	{ 99 / 128, 127 / 128, 122 / 256, 140 / 256 },   -- fire
	{ 99 / 128, 127 / 128, 199 / 256, 217 / 256 },   -- water
	{ 99 / 128, 127 / 128, 237 / 256, 255 / 256 },   -- air
	{ 99 / 128, 127 / 128,  84 / 256, 102 / 256 },   -- neutral ("summon"): cooldown bar flyouts
}
local ARROW_CLOSE = {
	{ 99 / 128, 127 / 128, 141 / 256, 159 / 256 },
	{ 99 / 128, 127 / 128, 103 / 256, 121 / 256 },
	{ 99 / 128, 127 / 128, 180 / 256, 198 / 256 },
	{ 99 / 128, 127 / 128, 218 / 256, 236 / 256 },
	{ 99 / 128, 127 / 128,  65 / 256,  83 / 256 },
}
-- Blizzard's flyout frame (opt.flyoutStyle == "frame"): a 32x20 cap that holds
-- the close tab, over a band that stretches behind the buttons. Same indexing
-- as the tabs; 5 is the neutral set. From FLYOUT_TOP/MIDDLE_TCOORDS.
local FRAME_CAP = {
	{  0 / 128, 32 / 128, 46 / 256,  68 / 256 },   -- earth
	{ 33 / 128, 65 / 128, 46 / 256,  68 / 256 },   -- fire
	{  0 / 128, 32 / 128,  1 / 256,  23 / 256 },   -- water
	{  0 / 128, 32 / 128, 91 / 256, 113 / 256 },   -- air
	{ 33 / 128, 65 / 128,  1 / 256,  23 / 256 },   -- neutral
}
local FRAME_BAND = {
	{  0 / 128, 32 / 128,  68 / 256,  88 / 256 },
	{ 33 / 128, 65 / 128,  68 / 256,  88 / 256 },
	{  0 / 128, 32 / 128,  23 / 256,  43 / 256 },
	{  0 / 128, 32 / 128, 113 / 256, 133 / 256 },
	{ 33 / 128, 65 / 128,  23 / 256,  43 / 256 },
}

-- The flyout panel art has no bottom edge: on Blizzard's bar it stands on the
-- square border drawn round the slot button (SLOT_OVERLAY_TCOORDS, 34 px round
-- a 30 px button). Drawn round our totem button it closes the frame off the
-- same way. The fifth, brown square is in the texture but unused by Blizzard;
-- it serves as the neutral one for the cooldown bar.
local FRAME_SLOT = {
	{  1 / 128, 35 / 128, 172 / 256, 206 / 256 },   -- earth
	{ 36 / 128, 70 / 128, 172 / 256, 206 / 256 },   -- fire
	{  1 / 128, 35 / 128, 207 / 256, 240 / 256 },   -- water
	{ 36 / 128, 70 / 128, 137 / 256, 171 / 256 },   -- air
	{  1 / 128, 35 / 128, 137 / 256, 171 / 256 },   -- neutral
}

-- The faded totem Blizzard's bar shows for "leave this slot empty"
-- (SLOT_EMPTY_TCOORDS), per element; used for the flyout's Empty choice.
local SLOT_EMPTY = {
	{ 66 / 128, 96 / 128,   3 / 256,  33 / 256 },   -- earth
	{ 67 / 128, 97 / 128, 100 / 256, 130 / 256 },   -- fire
	{ 39 / 128, 69 / 128, 209 / 256, 239 / 256 },   -- water
	{ 66 / 128, 96 / 128,  36 / 256,  66 / 256 },   -- air
}

-- The setup tour and the settings preview draw Blizzard's tabs and flyout on
-- their Blizzard's-bar mock, from the same art.
ShamanPower.FlyoutArrowArt = { texture = ARROW_TEXTURE, w = ARROW_W, h = ARROW_H,
	open = ARROW_OPEN, close = ARROW_CLOSE, cap = FRAME_CAP, band = FRAME_BAND, empty = SLOT_EMPTY }

-- A totem button with nothing assigned wears the same faded totem, in its
-- element's colour, instead of a spell icon that reads as a real totem. It is a
-- texture laid over the icon, so it can change mid-fight. Forever only: the
-- Classic line keeps the look it shipped with.
local EMPTY_SLOT_ART = (SPCompat.FOREVER)

function ShamanPower:ShowEmptySlotArt(element, empty)
	if not EMPTY_SLOT_ART then return end
	local btn = self.totemButtons and self.totemButtons[element]
	if not (btn and btn.icon) then return end
	if element == 4 and self.opt.enableTotemTwisting then empty = false end   -- twisting draws Air itself
	if btn.compactLayoutOn then empty = false end   -- Compact draws a line, not an icon
	local art = btn.emptyArt
	if empty and not art then
		art = btn:CreateTexture(nil, "ARTWORK", nil, 1)
		art:SetAllPoints(btn.icon)
		art:SetTexture(ARROW_TEXTURE)
		local c = SLOT_EMPTY[element] or SLOT_EMPTY[1]
		art:SetTexCoord(c[1], c[2], c[3], c[4])
		btn.emptyArt = art
	end
	if art then art:SetShown(empty and true or false) end
	if empty then btn.icon:SetTexture(nil) end   -- the art has rounded corners; nothing should peek out behind them
end

local ARROW_GLOW_OPEN  = { 0.5625, 0.71875, 0.34375, 0.3828125 }      -- up-arrow shaped
local ARROW_GLOW_CLOSE = { 0.5625, 0.71875, 0.26953125, 0.30859375 }  -- down-arrow shaped

-- The art is drawn for a flyout that opens upward. For the other three
-- directions the texture is turned by remapping its corners (UL, LL, UR, LR),
-- which stays inside the tab's own rectangle; SetRotation would not.
local function spArrowCoords(c, dir)
	local l, r, t, b = c[1], c[2], c[3], c[4]
	if dir == "bottom" then return r, b, r, t, l, b, l, t end
	if dir == "left" then return r, t, l, t, r, b, l, b end
	if dir == "right" then return l, b, r, b, l, t, r, t end
	return l, t, l, b, r, t, r, b
end

-- The arrow strip only exists during a fight. PLAYER_REGEN_DISABLED fires just
-- BEFORE the UI locks, which is the last moment secure frames may be moved, so
-- that is where the flyouts shift out to make room and the arrows appear; both
-- are undone when the fight ends. Out of combat nothing is different.
local spFlyoutCombatLayout = false

-- Room kept between the totem button and its first flyout icon. Only the
-- icons-only style needs any, and only in combat: there the close tab sits
-- against the button while the flyout is open. In the frame style the close tab
-- is at the far end, and the open tab is simply covered by the first icon.
-- WoW: Forever players can pick Blizzard's own totem bar look: flyouts that open
-- from arrow tabs (click or key), built by the same box mode that serves a client
-- whose secure snippets are broken. Read once, when the flyouts are built (login,
-- /reload): switching mid-session would leave built flyouts of the other kind.
function ShamanPower:BlizzardStyleFlyouts()
	if self._blizzardArrows == nil then
		if not self.opt then return false end   -- too early to know: not cached
		self._blizzardArrows = (SPCompat.FOREVER and self.opt.flyoutBlizzardArrows == true) and true or false
	end
	return self._blizzardArrows
end

local function spFlyoutBoxMode()
	if SPCompat and SPCompat.SecureSnippetsWork and not SPCompat.SecureSnippetsWork() then return true end
	return ShamanPower:BlizzardStyleFlyouts()
end
-- arrow ("box") flyouts: secure snippets do not work here, or the player picked them
function ShamanPower:FlyoutBoxMode() return spFlyoutBoxMode() end

-- The arrow strip is laid out during a fight, and all the time for players who
-- asked for that: opt.flyoutArrowsAlways, or opt.flyoutArrowOnly (flyouts open
-- from the arrow or a key and never from hovering, which needs the arrow there).
local function spFlyoutArrowLayout()
	if spFlyoutCombatLayout then return true end
	local o = ShamanPower.opt
	return (o and (o.flyoutArrowsAlways or o.flyoutArrowOnly) and spFlyoutBoxMode()) and true or false
end

function ShamanPower:FlyoutArrowOnly()
	return (self.opt and self.opt.flyoutArrowOnly and spFlyoutBoxMode()) and true or false
end

-- "Flyout requires right-click" is a snippet-era mode: the right-click opened the
-- flyout through a secure handler, in combat too. Box mode has no such handler
-- (arrows and keys open flyouts there), so the option is retired in box mode and
-- right-click keeps its normal job.
function ShamanPower:FlyoutOpensOnRightClick()
	return (self.opt and self.opt.flyoutRequiresClick and not spFlyoutBoxMode()) and true or false
end

local function spFlyoutLeadGap()
	if not spFlyoutArrowLayout() then return 0 end
	if ShamanPower.opt and ShamanPower.opt.flyoutStyle == "frame" then return 0 end
	return FLYOUT_ARROW
end

-- Flyout buttons hang from the box in box mode; hooks written against the
-- totem button find it through here.
local function spFlyoutOwner(child)
	local p = child and child:GetParent()
	return (p and p.spFlyoutOwner) or p
end

local function spFlyoutChildren(parent)
	local out = {}
	if not parent or not parent.GetChildren then return out end
	for _, c in ipairs({ parent:GetChildren() }) do
		if c.spFlyoutChild then out[#out + 1] = c end
	end
	local box = parent.spFlyoutBox
	if box then
		for _, c in ipairs({ box:GetChildren() }) do
			if c.spFlyoutChild then out[#out + 1] = c end
		end
	end
	return out
end

local function spFlyoutMouseIsOn(parent)
	if not parent then return false end
	if parent.IsMouseOver and parent:IsMouseOver() then return true end
	-- the arrow strip sits between the totem button and its flyout
	local open, close = parent.spFlyoutOpenArrow, parent.spFlyoutCloseArrow
	if open and open:IsVisible() and open:IsMouseOver() then return true end
	if close and close:IsVisible() and close:IsMouseOver() then return true end
	-- Buttons may hang from the totem button (secure path) or from the
	-- unprotected host (fallback path). Check both, or moving the cursor onto a
	-- flyout button reads as "left the flyout" and closes it instantly.
	for _, c in ipairs(spFlyoutChildren(parent)) do
		if c:IsShown() and c.IsMouseOver and c:IsMouseOver() then return true end
	end
	return false
end

-- A rebuilt flyout makes new buttons under the names the old ones had. The
-- template's icon used to be fetched through its GLOBAL name, and after a rebuild
-- that name still led to the retired button's texture: the new buttons were laid
-- out, clickable and labelled, with no icon on them (found by toggling the click
-- swap, which rebuilds). Take the region from the button itself, then point the
-- globals at the live objects so name lookups (key bindings, /click) agree.
local function spOwnIcon(btn)
	local name = btn:GetName()
	local icon
	if name then
		for _, region in ipairs({ btn:GetRegions() }) do
			if region.GetName and region:GetName() == name .. "Icon" then icon = region break end
		end
	end
	icon = icon or btn:CreateTexture(nil, "ARTWORK")
	if name then
		_G[name] = btn
		_G[name .. "Icon"] = icon
	end
	return icon
end

-- Parents with a flyout left open when combat started, so it can be closed the
-- moment the fight ends rather than hanging there.
local spFlyoutStuck = {}

function ShamanPower:FlyoutFallbackSetShown(parent, show)
	if parent and parent.spGridPinned then return end
	local inCombat = InCombatLockdown()

	-- Box mode: one watched container per flyout. Out of combat we set its unit
	-- and show it directly (no 0.2 s wait); in combat only the arrows may touch
	-- it, so a hover-close there is left for the sweep when the fight ends.
	local box = parent and parent.spFlyoutBox
	if box then
		if inCombat then
			if not show then spFlyoutStuck[parent] = true end
			return
		end
		if show then
			-- Which buttons belong (the assigned totem does not) is only known
			-- to the flyout's own layout pass, and at login that has not run
			-- yet, so the assigned totem showed up twice. Refresh on every open.
			for _, entry in pairs(ShamanPower.boxFlyouts or {}) do
				if entry.button == parent then pcall(entry.relayout) break end
			end
		end
		box:SetAttribute("unit", show and "player" or "none")
		box:SetShown(show and true or false)
		ShamanPower:SyncFlyoutToggle(parent, show)
		return
	end

	-- The buttons are children of the totem button, which is a secure action
	-- button and therefore protected, so showing them in combat is refused.
	-- An unprotected container was tried and removed: protection propagates
	-- upward from the secure buttons inside it, so it changed nothing and cost
	-- the buttons the totem button's scale. Blizzard's own MultiCastFlyoutFrame
	-- only escapes this because its buttons assign totems rather than cast them.
	--
	-- Opening in combat is therefore declined, and so is closing: Hide on a
	-- secure button is refused in combat even when it is already hidden, and
	-- every refusal prints "Interface action failed because of an AddOn". So
	-- only buttons that are actually open are touched, and in combat those are
	-- left for the PLAYER_REGEN_ENABLED sweep below, which closes them the
	-- moment the fight ends.
	if show and inCombat then return end
	for _, c in ipairs(spFlyoutChildren(parent)) do
		if show then
			-- "inactive": a loadout flyout slot with no loadout in it
			if not c:GetAttribute("isCurrentAssignment") and not c:GetAttribute("flyoutHidden") and not c:GetAttribute("inactive") then
				c:Show()
			end
		elseif c:IsShown() then
			if inCombat or not pcall(c.Hide, c) then
				spFlyoutStuck[parent] = true
			end
		end
	end
end

-- Safety net: close anything combat refused to close, the instant it ends.
do
	local f = CreateFrame("Frame")
	f:RegisterEvent("PLAYER_REGEN_ENABLED")
	f:RegisterEvent("PLAYER_REGEN_DISABLED")
	-- Shift every box-mode flyout to the combat layout (room for the arrows,
	-- arrows shown) or back. Must run synchronously inside the event: on
	-- PLAYER_REGEN_DISABLED the UI is not locked yet, a frame later it is.
	local function setCombatLayout(on)
		spFlyoutCombatLayout = on
		ShamanPower.flyoutArrowGap = spFlyoutArrowLayout() and FLYOUT_ARROW or 0
		for _, entry in pairs(ShamanPower.boxFlyouts or {}) do
			local flyout = entry.flyout
			if flyout and flyout.box then
				flyout.leadGap = ShamanPower:FlyoutLeadGap(flyout)
				pcall(entry.relayout)   -- re-lays out, then places the arrows
			end
			-- what we draw outside the button follows its tab (placing the arrows does
			-- this; here too for a relayout that stopped short, a no-op otherwise)
			if entry.button then ShamanPower:FollowFlyoutArrows(entry.button) end
		end
		if ShamanPower.PositionActiveOverlays then ShamanPower:PositionActiveOverlays() end
		if on and ShamanPower.RefreshTotemBarHelpers then ShamanPower:RefreshTotemBarHelpers() end
	end

	-- the arrow options changed: lay everything out again (out of combat; a change
	-- made mid-fight is picked up by the relayout when the fight ends)
	function ShamanPower:RefreshFlyoutLayout()
		if InCombatLockdown() then return end
		setCombatLayout(false)
	end

	f:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_REGEN_DISABLED" then
			setCombatLayout(true)
			return
		end
		-- box mode: anything opened during the fight closes now, unless the
		-- cursor is still on it
		for _, entry in pairs(ShamanPower.boxFlyouts or {}) do
			local btn = entry.button
			local box = btn and btn.spFlyoutBox
			if box and not btn.spGridPinned and box:IsShown()
				and not spFlyoutMouseIsOn(btn) and not ShamanPower:FlyoutArrowOnly() then
				box:SetAttribute("unit", "none")
				box:Hide()
			end
			if box and not box:IsShown() then ShamanPower:SyncFlyoutToggle(btn, false) end
		end
		for parent in pairs(spFlyoutStuck) do
			if parent and parent.GetChildren and not parent.spFlyoutBox and not parent.spGridPinned then
				for _, c in ipairs(spFlyoutChildren(parent)) do pcall(c.Hide, c) end
			end
		end
		wipe(spFlyoutStuck)
		setCombatLayout(false)
		if ShamanPower.flyoutArrowModePending then ShamanPower:ApplyFlyoutArrowMode() end
		if ShamanPower.flyoutClickSyncPending then ShamanPower:SyncFlyoutClicks() end
		if ShamanPower.clickSwapPending then ShamanPower:ApplyClickSwap() end
		if ShamanPower.flyoutPickPending then ShamanPower:ApplyFlyoutPickMacros() end
	end)
end

-- True while the cursor is inside the rectangle spanning a button and its open
-- box-mode flyout. The space between them (arrow strip, Compact's icon square)
-- belongs to no frame, and the leave grace is far too short to cross it.
local function spFlyoutCursorInSpan(parent)
	local box = parent and parent.spFlyoutBox
	if not (box and box:IsShown()) then return false end
	local x, y = GetCursorPosition()
	local l, r, t, b
	local function add(f)
		if not (f and f:IsVisible() and f:GetLeft()) then return end
		local s = f:GetEffectiveScale()
		local fl, fr, ft, fb = f:GetLeft() * s, f:GetRight() * s, f:GetTop() * s, f:GetBottom() * s
		l = l and math.min(l, fl) or fl
		r = r and math.max(r, fr) or fr
		t = t and math.max(t, ft) or ft
		b = b and math.min(b, fb) or fb
	end
	add(parent)
	for _, c in ipairs(spFlyoutChildren(parent)) do add(c) end
	return (l and x >= l and x <= r and y >= b and y <= t) and true or false
end

local function spFlyoutScheduleClose(parent)
	if not parent or parent.spGridPinned then return end
	-- opened with the arrow or a key, closed the same way (or by picking)
	if parent.spFlyoutBox and ShamanPower:FlyoutArrowOnly() then return end
	C_Timer.After(FLYOUT_LEAVE_GRACE, function()
		if not parent or parent.spGridPinned or spFlyoutMouseIsOn(parent) then return end
		if spFlyoutCursorInSpan(parent) then
			-- between the button and its flyout: no frame there will report a leave,
			-- so keep watching until the cursor lands on something or moves away
			spFlyoutScheduleClose(parent)
			return
		end
		ShamanPower:FlyoutFallbackSetShown(parent, false)
	end)
end

function ShamanPower:WireFlyoutFallback(frame, attr)
	if attr == "_onenter" then
		if frame.spFlyoutHostWired then return end
		frame.spFlyoutHostWired = true   -- hook-once marker, not a frame
		frame:HookScript("OnEnter", function(self)
			if self:GetAttribute("OpenMenu") == "mouseover" and not (self.spFlyoutBox and ShamanPower:FlyoutArrowOnly()) then
				ShamanPower:FlyoutFallbackSetShown(self, true)
			end
		end)
		frame:HookScript("OnLeave", function(self) spFlyoutScheduleClose(self) end)
		-- click mode: the snippet path toggles on click, so mirror that
		frame:HookScript("OnClick", function(self)
			if self:GetAttribute("OpenMenu") == "click" then
				local anyShown = false
				if self.spFlyoutBox then
					-- box mode keeps its buttons shown inside a hidden box
					anyShown = self.spFlyoutBox:IsShown()
				else
					for _, c in ipairs(spFlyoutChildren(self)) do
						if c:IsShown() then anyShown = true break end
					end
				end
				ShamanPower:FlyoutFallbackSetShown(self, not anyShown)
			end
		end)

	elseif attr == "_childupdate-show" then
		-- mark it so the parent can find it, and close when the cursor leaves
		frame.spFlyoutChild = true
		if frame.spFlyoutChildWired then return end
		frame.spFlyoutChildWired = true
		frame:HookScript("OnLeave", function(self) spFlyoutScheduleClose(spFlyoutOwner(self)) end)
		frame:HookScript("OnClick", function(self)
			-- picking one closes the flyout, matching the secure behaviour
			spFlyoutScheduleClose(spFlyoutOwner(self))
		end)
	end
end

local LCD = (ShamanPower.isVanilla) and LibStub("LibClassicDurations", true)
local UnitAura = LCD and LCD.UnitAuraWrapper or SPCompat.UnitAura or UnitAura   -- SPCompat: its own reader on Forever (see SPCompat.UnitBuff)
-- Guarded natives on restricted clients; the globals stay untouched so Blizzard
-- code is never tainted by calling into us (see SPCompat)
local GetTotemInfo = (SPCompat and SPCompat.GetTotemInfo) or GetTotemInfo
-- Forever returns a LIST of enchants per weapon; the legacy global only ever
-- describes the first entry, which is empty when the imbue lands in the second.
local GetWeaponEnchantInfo = (SPCompat and SPCompat.GetWeaponEnchantInfo) or GetWeaponEnchantInfo
local GetSpellCooldown = (SPCompat and SPCompat.GetSpellCooldown) or GetSpellCooldown

local tinsert = table.insert
local tremove = table.remove
local twipe = table.wipe
local tsort = table.sort
local strfind = string.find
local strmatch = string.match
local strsub = string.sub
local format = string.format

-- Pre-built number strings for 0-20 (avoids tostring() garbage for charges/counts)
local NumberStrings = {}
for i = 0, 20 do
	NumberStrings[i] = tostring(i)
end

ShamanPower.player = UnitName("player")
-- These three are DECLARED SavedVariables. Assigning a fresh table at file
-- scope throws away whatever was restored, so they must be `or {}`.
-- It is harmless on a client that restores after the chunk runs and essential
-- on one that restores before it, and nothing downstream can tell the
-- difference. ShamanPower_Talents is not a SavedVariable, so it is fine as is.
ShamanPower_Talents = {}
ShamanPower_Assignments = ShamanPower_Assignments or {}
ShamanPower_EarthShieldAssignments = ShamanPower_EarthShieldAssignments or {}  -- Maps shamanName -> targetName
ShamanPower_TwistAssignments = ShamanPower_TwistAssignments or {}  -- Maps shamanName -> true/false for totem twisting

ShamanPower.AllShamans = {}
ShamanPower.SyncList = {}
ShamanPower.AC_DebugEnabled = false

local initialized = false
local isShaman = false

AC_Leader = false

-- ============================================================================
-- CONSOLIDATED ONUPDATE SYSTEM
-- Instead of 10+ separate OnUpdate frames each being called every frame,
-- we use ONE master frame that manages all timed updates efficiently.
-- Uses array-based active list for fastest iteration (ipairs > pairs)
-- ============================================================================
ShamanPower.updateSystem = {
	frame = nil,
	subsystems = {},  -- {name = {interval=seconds, elapsed=0, callback=func, enabled=false}}
	activeList = {},  -- Array of enabled subsystem references for fast iteration
}

-- The per-tick loops (pulse 20 Hz, progress bars 10 Hz) used to do their full work
-- with no totem on the ground - most of what the addon cost while idle. This is
-- the question they sleep on. The answer is kept for half a second and dropped at
-- once on PLAYER_TOTEM_UPDATE (a totem placed, expired, destroyed or recalled), so
-- a drop is seen on the next tick. Any doubt (an error, an unreadable value) counts
-- as "yes": the loops then simply run as they always did.
local function spElementHasTotem(self, element)
	local have = self:GetElementTotemInfo(element)
	if have then return true end
	return false
end

function ShamanPower:AnyTotemDown()
	local now = GetTime()
	if self._totemDownAt and (now - self._totemDownAt) < 0.5 then return self._totemDown end
	self._totemDownAt = now
	local down = false
	for element = 1, 4 do
		local ok, res = pcall(spElementHasTotem, self, element)
		if not ok or res then down = true break end
	end
	self._totemDown = down
	-- a totem seen down: whatever sleeps until one is wakes (the safety net for a
	-- drop that came without an event, see spWhileTotemsDown)
	if down then self:WakeTotemSleepers() end
	return down
end

-- Runs fn while a totem is down, and twice more after the last one goes so the
-- bars / glows it drew are cleared; then not at all until a totem is down again.
-- Called from a subsystem of the update loop, that subsystem then sleeps (leaves
-- the loop) until a totem change wakes it: InvalidateTotemInfo (PLAYER_TOTEM_UPDATE,
-- your own casts, the combat edges) or any totem seen down by AnyTotemDown. A
-- subsystem whose callback does other work as well keeps state.stayAwake set.
local function spWhileTotemsDown(state, fn)
	if ShamanPower:AnyTotemDown() then
		state.idle = 0
	else
		state.idle = (state.idle or 0) + 1
		if state.idle > 2 then
			local us = ShamanPower.updateSystem
			local sys = us.running
			if sys and not state.stayAwake then
				us.totemSleepers[sys.name] = true
				ShamanPower:SleepUpdateSubsystem(sys.name)
			end
			return
		end
	end
	fn()
end
ShamanPower._whileTotemsDown = spWhileTotemsDown

function ShamanPower:InitUpdateSystem()
	if self.updateSystem.frame then return end

	local us = self.updateSystem
	us.frame = CreateFrame("Frame")
	us.pass, us.totemSleepers = 0, {}
	local activeList = us.activeList  -- Local reference for speed

	us.frame:SetScript("OnUpdate", function(frame, elapsed)
		-- Fast array iteration (no pairs overhead, no garbage). A callback may switch
		-- a subsystem off or put one to sleep (itself too): the list then closes up,
		-- so the index moves on only past one still in its place, and each subsystem
		-- is looked at once a frame (its pass number).
		local pass = us.pass + 1
		us.pass = pass
		us.running = nil
		local i = 1
		local sys = activeList[1]
		while sys do
			if sys.pass ~= pass then
				sys.pass = pass
				sys.elapsed = sys.elapsed + elapsed
				if sys.elapsed >= sys.interval then
					sys.elapsed = 0
					us.running = sys
					sys.callback()
					us.running = nil
				end
			end
			if activeList[i] == sys then i = i + 1 end
			sys = activeList[i]
		end
	end)
	us.frame:Hide()   -- nothing to run yet: the first subsystem switched on shows it
end

-- The loop's frame is shown only while a subsystem is in the active list and
-- ShamanPower is on: a hidden frame gets no OnUpdate at all, so with everything
-- off or asleep the loop costs nothing.
function ShamanPower:SyncUpdateFrame()
	local us = self.updateSystem
	local f = us.frame
	if not f then return end
	local run = us.activeList[1] ~= nil and not self._appliedOff
	if run ~= (f:IsShown() and true or false) then f:SetShown(run) end
end

function ShamanPower:RegisterUpdateSubsystem(name, interval, callback)
	self.updateSystem.subsystems[name] = {
		name = name,
		interval = interval,
		elapsed = 0,
		callback = callback,
		enabled = false,
	}
end

function ShamanPower:EnableUpdateSubsystem(name)
	local sys = self.updateSystem.subsystems[name]
	if sys and not sys.enabled then
		sys.enabled = true
		sys.asleep = nil
		sys.elapsed = 0
		-- Add to active list
		self.updateSystem.activeList[#self.updateSystem.activeList + 1] = sys
		self:SyncUpdateFrame()
	elseif sys and sys.asleep then
		self:WakeUpdateSubsystem(name)   -- switched on again while asleep: back at once
	end
end

function ShamanPower:DisableUpdateSubsystem(name)
	local sys = self.updateSystem.subsystems[name]
	if sys and sys.enabled then
		sys.enabled = false
		if sys.asleep then sys.asleep = nil return end   -- already out of the list
		-- Remove from active list
		local activeList = self.updateSystem.activeList
		for i = #activeList, 1, -1 do
			if activeList[i] == sys then
				table.remove(activeList, i)
				break
			end
		end
		self:SyncUpdateFrame()
	end
end

-- A switched-on subsystem with nothing to do can sleep: it leaves the active list
-- (with the last one gone the frame stops) and stays switched on. Whoever puts one
-- to sleep wakes it on every event that can give it work again (any doubt: stay
-- awake). Waking, or switching it on again, brings it back for a pass on the next
-- frame; waking one that is awake just moves its next pass to the next frame.
function ShamanPower:SleepUpdateSubsystem(name)
	local sys = self.updateSystem.subsystems[name]
	if not (sys and sys.enabled) or sys.asleep then return end
	sys.asleep = true
	local activeList = self.updateSystem.activeList
	for i = #activeList, 1, -1 do
		if activeList[i] == sys then
			table.remove(activeList, i)
			break
		end
	end
	self:SyncUpdateFrame()
end

function ShamanPower:WakeUpdateSubsystem(name)
	local sys = self.updateSystem.subsystems[name]
	if not (sys and sys.enabled) then return end
	sys.elapsed = sys.interval   -- due on the next frame
	if sys.asleep then
		sys.asleep = nil
		local activeList = self.updateSystem.activeList
		activeList[#activeList + 1] = sys
		self:SyncUpdateFrame()
	end
end

-- Everything spWhileTotemsDown put to sleep: a totem may be down now.
function ShamanPower:WakeTotemSleepers()
	local sleepers = self.updateSystem.totemSleepers
	if not (sleepers and next(sleepers)) then return end
	for name in pairs(sleepers) do
		sleepers[name] = nil
		self:WakeUpdateSubsystem(name)
	end
end

function ShamanPower:IsUpdateSubsystemEnabled(name)
	return self.updateSystem.subsystems[name] and self.updateSystem.subsystems[name].enabled
end
-- ============================================================================

-- Any rank, by spell ID only (SPCompat.KnowsSpellID: this client's own rank list).
local function PlayerKnowsSpellByID(spellID)
	return SPCompat.KnowsSpellID(spellID)
end

-- unit tables
local party_units = {}
local raid_units = {}
local leaders = {}

local lastMsg = ""
local lastMsgTime = 0

do
	table.insert(party_units, "player")
	table.insert(party_units, "pet")

	for i = 1, MAX_PARTY_MEMBERS do
		table.insert(party_units, ("party%d"):format(i))
	end
	for i = 1, MAX_PARTY_MEMBERS do
		table.insert(party_units, ("partypet%d"):format(i))
	end

	for i = 1, MAX_RAID_MEMBERS do
		table.insert(raid_units, ("raid%d"):format(i))
	end
	for i = 1, MAX_RAID_MEMBERS do
		table.insert(raid_units, ("raidpet%d"):format(i))
	end
end

ShamanPower.Credits1 = "ShamanPower - Shaman Totem Coordination"
ShamanPower.Credits2 = "Created by Srumar. Originally adapted from PallyPower."

function ShamanPower:Debug(s)
	if (ShamanPower.AC_DebugEnabled) then
		DEFAULT_CHAT_FRAME:AddMessage("[PP] " .. tostring(s), 1, 0, 0)
	end
end

-- Sound at a custom volume. WoW has no per-sound volume for sound files (WoW:
-- Forever has one for built-in sound kits, used first), so a file below 100
-- is routed through the Dialog channel with Sound_DialogVolume temporarily
-- lowered. Rules that keep this from hurting the client:
--   * never touch Sound_Enable* CVars - toggling one restarts the sound engine,
--     which is a visible freeze; if Dialog is disabled we just play on Master
--   * only SetCVar when the value actually changes
--   * one shared restore timer, and the ORIGINAL volume is captured once,
--     before the first change, so overlapping alerts cannot drift it
local soundRestoreOriginal   -- user's Sound_DialogVolume before we touched it
local soundRestoreTimer
local function RestoreDialogVolume()
	soundRestoreTimer = nil
	if soundRestoreOriginal ~= nil then
		if GetCVar("Sound_DialogVolume") ~= soundRestoreOriginal then
			SetCVar("Sound_DialogVolume", soundRestoreOriginal)
		end
		soundRestoreOriginal = nil
	end
end

function ShamanPower:PlaySoundWithVolume(soundOrFile, volume, isFile)
	-- WoW: Forever gives a built-in sound (a sound kit, not a file) a volume of its own:
	-- it plays on Master at that volume, and the Dialog channel never comes into it
	if not isFile and SPCompat.FOREVER and C_Sound and C_Sound.PlaySound then
		if volume and volume <= 0 then return end
		C_Sound.PlaySound(soundOrFile, "Master", false, false, nil, (volume and volume < 100) and volume / 100 or nil)
		return
	end
	if not volume or volume >= 100 or GetCVar("Sound_EnableDialog") == "0" then
		if volume and volume <= 0 then return end
		if isFile then
			PlaySoundFile(soundOrFile, "Master")
		else
			PlaySound(soundOrFile, "Master")
		end
		return
	end
	if volume <= 0 then return end
	if soundRestoreOriginal == nil then
		soundRestoreOriginal = GetCVar("Sound_DialogVolume")
	end
	local target = tostring(volume / 100)
	if GetCVar("Sound_DialogVolume") ~= target then
		SetCVar("Sound_DialogVolume", target)
	end
	if isFile then
		PlaySoundFile(soundOrFile, "Dialog")
	else
		PlaySound(soundOrFile, "Dialog")
	end
	if soundRestoreTimer then soundRestoreTimer:Cancel() end
	soundRestoreTimer = C_Timer.NewTimer(5, RestoreDialogVolume)
end

function ShamanPower:GetSoundFile(soundName)
	-- a FileDataID (number) on the Mainline family, a path elsewhere; PlaySoundFile takes either.
	-- noDefault: an unregistered name (a stale saved value) must not fall through to
	-- SharedMedia's default, which is the silent "None" - it gets Raid Warning instead.
	local file = soundName and LSM3:Fetch("sound", soundName, true)
	if file == nil or file == "" then file = LSM3:Fetch("sound", "Raid Warning", true) end
	return file or (SP_SOUND_BY_ID and 567397 or [[Sound\Interface\RaidWarning.ogg]])
end

-------------------------------------------------------------------
-- Ace Framework Events
-------------------------------------------------------------------
-- The assignment window lives in the optional ShamanPower_Config module
function ShamanPower:ToggleAssignmentWindow()
	if ShamanPower_ToggleAssignments then
		ShamanPower_ToggleAssignments()
	else
		print("|cff0070ddShamanPower|r: the ShamanPower_Config module is required for the assignment window")
	end
end

-- One-time profile migration: the mini totem bar settings moved from
-- profile.autobuff to profile.miniBar (sub-keys unchanged).
-- rawget is required because AceDB profile tables fall through to defaults.
local function MigrateMiniBarProfile(db, opt)
	local old = rawget(db.profile, "autobuff")
	if type(old) == "table" then
		if type(opt.miniBar) ~= "table" then
			opt.miniBar = {}
		end
		-- Copy only keys the current defaults know about, so stale keys from
		-- old profiles are not carried forward.
		local known = SHAMANPOWER_DEFAULT_VALUES and SHAMANPOWER_DEFAULT_VALUES.profile
			and SHAMANPOWER_DEFAULT_VALUES.profile.miniBar
		for k, v in pairs(old) do
			if not known or known[k] ~= nil then
				opt.miniBar[k] = v
			end
		end
		db.profile.autobuff = nil
	end
end

function ShamanPower:OnInitialize()
	-- Initialize the consolidated update system (single OnUpdate for all timed updates)
	self:InitUpdateSystem()

	if select(2, UnitClass("player")) == "SHAMAN" then
		self.db = LibStub("AceDB-3.0"):New("ShamanPowerDB", SHAMANPOWER_DEFAULT_VALUES, "Default")
		self:KeepOldLookOnSavedProfiles()
	else
		self.db = LibStub("AceDB-3.0"):New("ShamanPowerDB", SHAMANPOWER_OTHER_VALUES, "Other")
		self:KeepOldLookOnSavedProfiles()   -- before SetProfile lays the defaults into a profile
		self.db:SetProfile("Other")
	end

	self.db.RegisterCallback(self, "OnProfileChanged", "OnProfileChanged")
	self.db.RegisterCallback(self, "OnProfileCopied", "OnProfileChanged")
	self.db.RegisterCallback(self, "OnProfileReset", "OnProfileChanged")

	self.opt = self.db.profile
	self:ClearTwistingOnForever()
	MigrateMiniBarProfile(self.db, self.opt)
	self:SplitPulseFlashList()
	-- switched off at login: the central update loop stays stopped (switch-on starts it)
	self._appliedOff = self:IsOff()   -- the state everything was last set up for
	self:SyncUpdateFrame()
	if self.PreserveCompactLook then self:PreserveCompactLook() end   -- before anything reads the Compact look
	if self.ApplyElementColors then self:ApplyElementColors() end
	-- The cooldown bar now always floats free of the totem bar (the old
	-- attach option was removed). Detach any profile still attached.
	if self.opt.cooldownBarLocked then self.opt.cooldownBarLocked = nil end

	-- Sync twist setting from shared assignments table (source of truth for sync)
	if ShamanPower_TwistAssignments and ShamanPower_TwistAssignments[self.player] ~= nil then
		self.opt.enableTotemTwisting = ShamanPower_TwistAssignments[self.player]
	elseif self.opt.enableTotemTwisting then
		-- Initialize assignments table from local opt if it exists
		ShamanPower_TwistAssignments = ShamanPower_TwistAssignments or {}
		ShamanPower_TwistAssignments[self.player] = self.opt.enableTotemTwisting
	end

	self.options.args.profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db)

	-- The options table drives the ShamanPower_Config window; no slash
	-- commands here (AceConfigCmd would open the retired AceGUI dialog).
	LibStub("AceConfig-3.0"):RegisterOptionsTable("ShamanPower", self.options)
	self:CreateInterfaceOptionsPanel()

	LSM3:Register("background", "None", "Interface\\Tooltips\\UI-Tooltip-Background")
	LSM3:Register("background", "Banto", "Interface\\AddOns\\ShamanPower\\Skins\\Banto")
	LSM3:Register("background", "BantoBarReverse", "Interface\\AddOns\\ShamanPower\\Skins\\BantoBarReverse")
	LSM3:Register("background", "Glaze", "Interface\\AddOns\\ShamanPower\\Skins\\Glaze")
	LSM3:Register("background", "Gloss", "Interface\\AddOns\\ShamanPower\\Skins\\Gloss")
	LSM3:Register("background", "Healbot", "Interface\\AddOns\\ShamanPower\\Skins\\Healbot")
	LSM3:Register("background", "oCB", "Interface\\AddOns\\ShamanPower\\Skins\\oCB")
	LSM3:Register("background", "Smooth", "Interface\\AddOns\\ShamanPower\\Skins\\Smooth")

	self.zone = GetRealZoneText()

	self:CreateLayout()

	if self.opt.skin then
		self:ApplySkin(self.opt.skin)
	end

	self.menuFrame = LUIDDM:Create_UIDropDownMenu("ShamanPowerMenuFrame", UIParent)

	-- Re-sync the settings window after the options table changed shape
	-- (loadouts added/renamed, etc.).
	self.RefreshConfig = function(self)
		local reg = LibStub("AceConfigRegistry-3.0", true)
		if reg then reg:NotifyChange("ShamanPower") end
		if ShamanPowerConfig and ShamanPowerConfig.RefreshCurrent then ShamanPowerConfig:RefreshCurrent() end
	end

	self.MinimapIcon = LibStub("LibDBIcon-1.0")
	self.LDB =
		LibStub("LibDataBroker-1.1"):NewDataObject(
		"ShamanPower",
		{
			["type"] = "data source",
			["text"] = "ShamanPower",
			["icon"] = "Interface\\Icons\\ClassIcon_Shaman",
			["OnTooltipShow"] = function(tooltip)
				if self.opt.ShowTooltips then
					tooltip:SetText(SHAMANPOWER_NAME)
					if self:IsOff() then
						tooltip:AddLine("ShamanPower is off. Click to turn it back on.", 1, 1, 1, true)
					elseif self:WindfuryOnly() then
						tooltip:AddLine("Windfury-only mode. Click to turn the other features back on.", 1, 1, 1, true)
					else
						tooltip:AddLine(L["MINIMAP_ICON_TOOLTIP"])
					end
					tooltip:Show()
				end
			end,
			["OnClick"] = function(_, button)
				local playerIsShaman = select(2, UnitClass("player")) == "SHAMAN"
				-- Switched off, or Windfury-only mode: every click opens the one menu
				-- that turns the rest back on
				if (ShamanPower:IsOff() or ShamanPower:WindfuryOnly()) and ShamanPower.ShowMinimapMenu then
					ShamanPower:ShowMinimapMenu()
					return
				end

				if (button == "LeftButton") then
					if playerIsShaman then
						ShamanPower:ToggleAssignmentWindow()
					else
						-- Non-shaman: open SPRange
						ShamanPower:InitSPRange()
						if not ShamanPower.spRangeFrame then
							ShamanPower:CreateSPRangeFrame()
						end
						ShamanPower:ShowSPRangeConfig()
					end
				elseif (button == "MiddleButton") then
					-- Middle click: open /sp totems (for non-shamans, or anyone)
					ShamanPower:ToggleAssignmentWindow()
				elseif IsShiftKeyDown() or not ShamanPower.ShowMinimapMenu then
					self:OpenConfigWindow()
				else
					-- right-click: the quick menu (shift-right-click: settings straight away)
					ShamanPower:ShowMinimapMenu()
				end
			end
		}
	)
	self.MinimapIcon:Register("ShamanPower", self.LDB, self.opt.minimap)
	C_Timer.After(
		2.0,
		function()
			ShamanPowerMinimapIcon_Toggle()
		end
	)

	if self.isVanilla and LCD then
		-- LCD registers COMBAT_LOG_EVENT_UNFILTERED; a client that forbids it must not abort OnEnable
		pcall(LCD.Register, LCD, "ShamanPower")
	end

	-- the transition from TBC Classic to Wrath Classic has caused some errors for players with SavedVariables values intended for the 2.5.4 clients and earlier
	if self.isWrath and not self.opt.WrathTransition then
		ShamanPower:Purge()

		self.opt.WrathTransition = true
	end

	if not ShamanPower_TotemLoadouts then
		ShamanPower_TotemLoadouts = {}
	end
	-- Rebuild loadout options now that SavedVariables are loaded
	if self.RefreshLoadoutArgs then
		self:RefreshLoadoutArgs()
	end

	-- Initialize assignment tables if they don't exist
	if not ShamanPower_Assignments then
		ShamanPower_Assignments = {}
	end
	if not ShamanPower_EarthShieldAssignments then
		ShamanPower_EarthShieldAssignments = {}
	end
	if not ShamanPower_TwistAssignments then
		ShamanPower_TwistAssignments = {}
	end

	self:RestoreTotemBarPosition()

end

-- Helper function to ensure nested tables exist in the profile for proper saving
-- AceDB returns default tables when profile doesn't have the key, but setting
-- values on default tables doesn't persist to the profile
-- Deep copy a table (for nested structures like position tables)
local function DeepCopy(orig)
	if type(orig) ~= "table" then return orig end
	local copy = {}
	for k, v in pairs(orig) do
		copy[k] = DeepCopy(v)
	end
	return copy
end

function ShamanPower:EnsureProfileTable(tableName)
	if not rawget(self.db.profile, tableName) then
		-- Create a deep copy of the defaults in the profile
		local defaults = SHAMANPOWER_DEFAULT_VALUES.profile[tableName]
		if defaults then
			self.db.profile[tableName] = DeepCopy(defaults)
		else
			self.db.profile[tableName] = {}
		end
	end
end

-- Helper to save frame position to profile (ensures display table exists)
-- Saves absolute screen position for exact restore
-- profile.display.position (record). Legacy profiles used absolute frame-unit
-- offsetX/Y; those convert the first time they are restored.
function ShamanPower:RestoreTotemBarPosition()
	local h = _G["ShamanPowerFrame"]
	if not h then return end
	self:EnsureProfileTable("display")
	local d = self.opt.display
	h:SetScale(self.opt.buffscale or 0.9)   -- records are scale-free; SetPoint is not
	self._barScaleApplied = true
	-- Upgrading from 2.x (Anniversary): a bar never dragged sat at dead centre (its
	-- 1x1 anchor there) and saved no spot. Save that spot once, so only new setups
	-- get the new default. A profile used by 2.x finished or skipped its setup, or
	-- saved a cooldown bar spot; one set up by 3.0 records how (setupPath).
	if not d.defaultSpotChecked then
		d.defaultSpotChecked = true
		local o = self.opt
		local upgrade = not SPCompat.FOREVER and not o.setupPath and (o.setupDone or o.cooldownBarPosition)
		local legacy = d.offsetX and d.offsetY and d.offsetX ~= 0 and d.offsetY ~= 0
		if upgrade and not (d.position and d.position.anchor) and not legacy then
			d.position = { anchor = "CENTER", x = 0, y = 0 }
		end
		-- Its cooldown bar likewise: with no saved spot and its old fields still at the
		-- CENTER 0,-50 default, 2.x put it 50 of its own units below the centre, at its
		-- own scale. (Old fields moved off that default convert where the bar is placed.)
		if upgrade and not (o.cooldownBarPosition and o.cooldownBarPosition.anchor)
			and (o.cooldownBarPosX or 0) == 0 and (o.cooldownBarPosY or -50) == -50
			and (o.cooldownBarPoint or "CENTER") == "CENTER" and (o.cooldownBarRelPoint or "CENTER") == "CENTER" then
			o.cooldownBarPosition = { anchor = "CENTER", x = 0, y = -50 * (o.cooldownBarScale or 0.9) }
		end
	end
	self._barSpotKey = self:BarStyleSpotKey()   -- FollowStyleSpot: the spot now applied
	local rec = self:TotemBarRecord()
	if rec then
		self:ApplyPositionRecord(h, rec)
	elseif d.offsetX and d.offsetY and d.offsetX ~= 0 and d.offsetY ~= 0 then
		h:ClearAllPoints()
		h:SetPoint("CENTER", UIParent, "BOTTOMLEFT", d.offsetX, d.offsetY)
		d.position = self:SavePositionRecord(h)
		d.offsetX, d.offsetY = nil, nil
	else
		self:ApplyDefaultBarPositions()
	end
end

function ShamanPower:SaveFramePosition(frame)
	self:EnsureProfileTable("display")
	-- every style keeps its own spot (BarStyleSpotKey)
	local d = self.db.profile.display
	local key = frame == _G["ShamanPowerFrame"] and self:BarStyleSpotKey() or "normal"
	self:SetStyleSpot(d, key, self:SavePositionRecord(frame))
	if key == "normal" then d.offsetX, d.offsetY = nil, nil end
	self:ApplyDefaultBarPositions()   -- a cooldown bar on its default spot follows
end

function ShamanPower:OnEnable()
	-- WoW only finds files an update added when it starts: after an update and a
	-- /reload they are missing and the windows that use them cannot draw
	if not self.Brand then
		print("|cff0070ddShamanPower|r: I was updated while WoW was running. Please exit WoW completely and start it again to finish the update (a /reload is not enough).")
	end
	isShaman = select(2, UnitClass("player")) == "SHAMAN"
	if not self:FixPlayerIdentity() then
		local f = CreateFrame("Frame")
		f:RegisterEvent("PLAYER_ENTERING_WORLD")
		f:RegisterUnitEvent("UNIT_NAME_UPDATE", "player")
		f:SetScript("OnEvent", function(frame)
			if ShamanPower:FixPlayerIdentity() then frame:UnregisterAllEvents() end
		end)
	end

	self.opt.enable = true
	self:ScanTalents()
	self:ScanSpells()
	self:RegisterEvent("CHAT_MSG_ADDON")
	self:RegisterEvent("ZONE_CHANGED")
	self:RegisterEvent("ZONE_CHANGED_NEW_AREA")
	self:SetupUnitEventFilters()   -- UNIT_SPELLCAST_* (player) and UNIT_AURA (player, party, ES carrier)
	self:RegisterEvent("PLAYER_TOTEM_UPDATE")  -- shadow totem model slot binding
	self:RegisterEvent("GROUP_JOINED")
	self:RegisterEvent("GROUP_LEFT")
	self:RegisterEvent("PLAYER_ROLES_ASSIGNED")
	self:RegisterEvent("UPDATE_BINDINGS", "BindKeys")
	self:RegisterEvent("CHARACTER_POINTS_CHANGED", "OnTalentsChanged")  -- Classic talent changes
	self:RegisterEvent("PLAYER_TALENT_UPDATE", "OnTalentsChanged")  -- Talent updates
	self:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED", "OnTalentsChanged")  -- Wrath dual spec switch
	self:RegisterBucketEvent("SPELLS_CHANGED", 1, "SPELLS_CHANGED")
	self:RegisterBucketEvent("PLAYER_ENTERING_WORLD", 2, "PLAYER_ENTERING_WORLD")
	-- a raid forming fires dozens of GROUP_ROSTER_UPDATEs: the roster pass runs at
	-- most once a second (a bucket fires a second after the first event it catches,
	-- again for any after that), and after combat. Pets never mattered to it.
	self:RegisterBucketEvent({"GROUP_ROSTER_UPDATE", "PLAYER_REGEN_ENABLED"}, 1, "OnRosterSettled")
	-- the shaman-count check only on real roster changes: when it finds a shaman
	-- missing it wipes the shaman list and asks the group again
	self:RegisterBucketEvent("GROUP_ROSTER_UPDATE", 1, "UpdateAllShamans")
	-- Reset Drop All castsequence when combat ends
	self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombatEnd")
	-- the game starts every /castsequence over on death: Drop All's icon follows it
	self:RegisterEvent("PLAYER_DEAD", "OnDropAllSequenceReset")
	-- Restricted clients: once secrets lift, re-read what the engine/shadow paths served
	if SPCompat and SPCompat.OnUnrestricted then
		SPCompat.OnUnrestricted(function()
			self:ScanPlayerShield()
			self:RefreshEarthShieldTarget()
			self:RefreshPlayerBuffCache()
			self:InvalidateTotemInfo()   -- the totems too: a loop asleep on the shadow model wakes and looks
		end)
	end
	-- Forever: what the chat lockdown refused goes out once it lifts
	if SPCompat and SPCompat.OnChatUnlocked then
		SPCompat.OnChatUnlocked(function() self:SendHeldMessages() end)
	end
	if isShaman then
		self.ButtonsUpdate(self)
		-- Keep the binding button, but do not leave a dead macro on clients without Earth Shield.
		self:UpdateEarthShieldMacroButton()
		if not self.ESTrackerUnavailable then
			self:CreateEarthShieldMacro()
		else
			local idx = GetMacroIndexByName("AC EarthShield")
			if idx and idx > 0 and not InCombatLockdown() then DeleteMacro(idx) end
		end
	end
	self:BindKeys()
	self:UpdateRoster()
	if isShaman then
		self:CreateLoadoutBar()
		self:UpdateLoadoutBar()
	end
	self:ApplyPlayerTotemFrame()
end

-- Called when combat ends - reset Drop All castsequence
function ShamanPower:OnCombatEnd()
	self:LandPendingShield()   -- a shield picked in the fight: saved now (the button already casts it)
	self:SyncShieldButtonCast()   -- a profile switched in the fight: its shield on the button now
	if self._shieldClicksPending then self:ApplyShieldButtonClicks() end
	if self._onOffPendingCombat then self:ApplyOnOff() end
	if self._cdBarRebuildPending then self:RecreateCooldownBar() end
	-- WoW: Forever: the game-drawn shield layers on the cooldown bar's shield button and
	-- the Earth Shield button. A rebuild asked for during the fight runs now; one that
	-- is missing (the addon loaded mid-fight) or came back incomplete is built again,
	-- a few times at most, so a failed build never lasts until the next /reload.
	if SPCompat and SPCompat.secretsRegime then
		local btn = self.shieldButton
		if btn and (self._shieldContainerRebuildPending or not btn.chargeContainer or btn.chargeContainerFailed) then
			local tries = (btn.chargeContainerTries or 0) + 1
			if self._shieldContainerRebuildPending or tries <= 3 then
				btn.chargeContainerTries = tries
				self:RebuildShieldChargeContainer()
				if btn.chargeContainer and not btn.chargeContainerFailed then btn.chargeContainerTries = nil end
			end
		end
		local esBtn = _G["ShamanPowerEarthShieldBtn"]
		if esBtn and not esBtn.chargeContainer and self.EnsureESButtonContainer then self:EnsureESButtonContainer(esBtn) end
	end
	-- Layout skipped because the addon loaded (or was reloaded) mid-combat:
	-- run the parts of the login sequence that could not touch secure frames.
	if self._layoutPendingCombat then
		self._layoutPendingCombat = nil
		self:UpdateLayout()
		self:UpdateRoster()
		self:BindKeys()
		C_Timer.After(0.5, function()
			if not InCombatLockdown() then self:UpdateTotemFlyoutEnabled() end
		end)
		self.cdbarVisibilityPending = true
	end
	-- Force rebuild of the Drop All macro to reset the castsequence
	self.dropAllLastMacro = ""
	self.dropAllCurrentElement = 1   -- reset=combat: the game starts the sequence over now too
	self:UpdateDropAllButton()
	-- the game's own manager starts the sequence over on this same event; read it next frame
	C_Timer.After(0, self.DropAllRefresh)
	-- Deferred cooldown bar visibility update if blocked during combat
	if self.cdbarVisibilityPending then
		self.cdbarVisibilityPending = false
		self:UpdateCooldownBar()
	end
	-- Deferred loadout bar update if blocked during combat
	if self.pendingLoadoutBarUpdate then
		self.pendingLoadoutBarUpdate = false
		self:UpdateLoadoutBar()
	end
	-- A macro refresh asked for during the fight (UpdateSPMacros refuses in combat)
	if self.macroUpdatePending then
		self.macroUpdatePending = false
		self:UpdateSPMacros()
	end
end

-- The Earth Shield macro's body: its tooltip line names the spell in the game's own
-- language (an English name shows a "?" icon with no tooltip on other clients)
function ShamanPower:EarthShieldMacroBody()
	return "#showtooltip " .. (SPCompat.SpellName(974) or "Earth Shield") .. "\n/click ShamanPowerESMacroBtn"
end

-- Create a macro for Earth Shield that users can keybind
function ShamanPower:CreateEarthShieldMacro()
	local macroName = "AC EarthShield"
	local macroBody = self:EarthShieldMacroBody()
	-- Use ? icon so #showtooltip shows the correct spell icon dynamically
	local macroIcon = "INV_Misc_QuestionMark"

	-- Check if macro already exists
	local existingIndex = GetMacroIndexByName(macroName)
	if existingIndex and existingIndex > 0 then
		-- Macro exists, no need to recreate. One made before 3.0.6 with the English
		-- tooltip line (and not changed by the player) gets this client's name.
		local old = "#showtooltip Earth Shield\n/click ShamanPowerESMacroBtn"
		if old ~= macroBody and not InCombatLockdown() and GetMacroBody(existingIndex) == old then
			EditMacro(existingIndex, macroName, macroIcon, macroBody)
		end
		return
	end

	-- Check if we have room for a new macro
	local numGlobal, numPerChar = GetNumMacros()
	if numGlobal >= MAX_ACCOUNT_MACROS then
		-- Try character-specific macros
		if numPerChar >= MAX_CHARACTER_MACROS then
			-- No room, silently fail (user can manually create it)
			return
		end
		-- Create as character-specific macro
		CreateMacro(macroName, macroIcon, macroBody, true)
	else
		-- Create as global macro
		CreateMacro(macroName, macroIcon, macroBody, false)
	end
end

function ShamanPower:OnDisable()
	self.opt.enable = false
	self:UpdateRoster()
	self.autoButton:Hide()
	ShamanPowerAnchor:Hide()
	self:UnbindKeys()
	self:UnregisterAllEvents()
	self:UnregisterAllBuckets()
end

function ShamanPower:OnProfileChanged()
	local fix = self.aceCharKeyFix
	local pk = fix and self.db and rawget(self.db, "sv") and rawget(self.db, "sv").profileKeys
	if pk then pk[fix.real], pk[fix.bad] = self.db:GetCurrentProfile(), nil end
	-- Clean up all popped-out frames from the old profile first
	if self.poppedOutFrames then
		for key, frame in pairs(self.poppedOutFrames) do
			if frame then
				-- Reparent buttons back before hiding frame
				if frame.totemButton then
					frame.totemButton:SetParent(UIParent)
				end
				if frame.cooldownButton and self.cooldownBar then
					frame.cooldownButton:SetParent(self.cooldownBar)
				end
				if frame.button then
					frame.button:Hide()
					frame.button:SetParent(nil)
				end
				frame:Hide()
				frame:SetParent(nil)
			end
		end
		wipe(self.poppedOutFrames)
	end

	self.opt = self.db.profile
	self:ClearTwistingOnForever()
	if self.RefreshFonts then self:RefreshFonts() end   -- the new profile may pick other fonts
	if self.RefreshTextures then self:RefreshTextures() end   -- and other bar textures
	if self.UpdateAnnounceEvents then self:UpdateAnnounceEvents() end   -- announce settings live in the profile
	MigrateMiniBarProfile(self.db, self.opt)
	self:SplitPulseFlashList()
	if self.PreserveCompactLook then self:PreserveCompactLook() end   -- before anything reads the Compact look
	if self.ApplyElementColors then self:ApplyElementColors() end

	-- Reset frame positions when profile changes (prevents off-screen issues)
	if not InCombatLockdown() then
		self:RestoreTotemBarPosition()
		if self.loadoutAnchor then
			self.loadoutAnchor:SetScale(self.opt.loadoutBarScale or 1.0)
			self.loadoutAnchor._scaleApplied = true
			if self.RestoreLoadoutBarPosition then self:RestoreLoadoutBarPosition() end
		end

		-- Apply cooldown bar position from new profile (force reposition to use profile's saved position)
		if self.cooldownBar then
			self:UpdateCooldownBarPosition(true)  -- true = force reposition from profile
		end
	end

	self:ApplySkin()
	self:SyncFlyoutClicks()   -- the new profile's Swap Left and Right Click, before the layout sends the keys
	self:ApplyShieldButtonClicks()   -- and its Right-Click Casts Your Other Shield (after the fight if in one)
	self:SyncShieldButtonCast()      -- the new profile's shield on the button (also with the cooldown bar hidden)
	self:UpdateLayout()
	self:UpdateRoster()
	self:ApplyAllOpacity()
	self:SetupTotemBarVisibilityUpdater()   -- the new profile's hide and fade rules, now (no poll)

	-- Restore popped-out trackers from the new profile
	C_Timer.After(0.5, function()
		self:RestorePoppedOutTrackers()
	end)
	-- the new profile has the other Enable ShamanPower setting: switch now (after
	-- combat); its pop-outs come back through the restore above, not the switch
	if (self.opt.enabled == false) ~= (self._appliedOff == true) then
		self._popOutsSkippedByOff = nil
		if InCombatLockdown() then self._onOffPendingCombat = true else self:ApplyOnOff() end
	end
	if self.ApplyCueSettings then self:ApplyCueSettings() end   -- the new profile's Effects
	-- the game-drawn shield layer keeps the settings it was built with: the new profile's
	-- sweep, count, bar and text (after the fight if this runs in one)
	if self.RebuildShieldChargeContainer then self:RebuildShieldChargeContainer() end
	--self:Debug("Profile changed, positions restored from profile.")
end

function ShamanPower:BindKeys()
	if self:IsOff() then return end
	local key1 = GetBindingKey("SHAMANPOWER_AUTOKEY1")
	local key2 = GetBindingKey("SHAMANPOWER_AUTOKEY2")
	if key1 then
		SetOverrideBindingClick(self.autoButton, false, key1, "ShamanPowerAuto", "Hotkey1")
	end
	if key2 then
		SetOverrideBindingClick(self.autoButton, false, key2, "ShamanPowerAuto", "Hotkey2")
	end
end

function ShamanPower:UnbindKeys()
	ClearOverrideBindings(self.autoButton)
end

-------------------------------------------------------------------
-- Config Window Functionality
-------------------------------------------------------------------
function ShamanPower:Purge()
	ShamanPower_Assignments = {}
end

function ShamanPower:Reset()
	if InCombatLockdown() then return end

	-- Clear the saved spot: UpdateLayout below puts the bar on its default one
	local h = _G["ShamanPowerFrame"]
	self:EnsureProfileTable("display")
	self.opt.display.offsetX = nil
	self.opt.display.offsetY = nil
	self.opt.display.position = nil
	self.opt.display.compactPosition = nil
	self.opt.display.stylePositions = nil

	-- Reset visual settings to defaults
	self.opt.buffscale = 0.9
	self.opt.border = "Blizzard Tooltip"
	self.opt.layout = "Horizontal"
	self.opt.skin = "Smooth"
	self.opt.configscale = 0.9

	-- Position was just cleared; apply the default scale as a fresh first
	-- application so UpdateLayout does not compensate and re-save it.
	h:SetScale(self.opt.buffscale)
	self._barScaleApplied = true

	self:ApplySkin()
	self:UpdateLayout()
	-- the cooldown bar's saved spot goes too: it comes back straight under the totem bar
	self:ResetBarPositions(false)
end

-- Settings live in the optional ShamanPower_Config module.
function ShamanPower:OpenConfigWindow(path)
	if not self.Brand then   -- updated without a restart: the window cannot draw
		print("|cff0070ddShamanPower|r: I was updated while WoW was running. Please exit WoW completely and start it again to finish the update (a /reload is not enough).")
		return
	end
	if ShamanPowerAssign then ShamanPowerAssign:Hide() end
	if ShamanPowerConfig then
		if path then ShamanPowerConfig:Open(path) else ShamanPowerConfig:Toggle() end
	else
		print("|cff0070ddShamanPower|r: enable the |cff0070ddShamanPower_Config|r module in your AddOns list to open settings.")
	end
end

-- Interface > AddOns entry (Esc > Options > AddOns > ShamanPower): ShamanPower's
-- own page (D21b): the logo's totem boxes, the wordmark, "Totems, Done Right",
-- one big button into the settings window, the tour / What's New / Discord, and
-- the ways in. Drawn from plain textures and the brand's Fira Sans in the brand
-- colors, so it needs neither image files nor the settings module (its buttons
-- use it when it is there). Everything lives in this method: no main-chunk locals.
function ShamanPower:CreateInterfaceOptionsPanel()
	if self.optionsFrame then return end
	if not self.Brand then return end   -- updated without a restart (OnEnable says so)
	-- 2.5.6 removed InterfaceOptions_AddCategory; the modern Settings API is
	-- the live path now, the legacy call kept as a fallback for older clients
	local canModern = Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory
	if not canModern and not InterfaceOptions_AddCategory then return end
	local SP = self
	-- Fira Sans (ShamanPowerBrand.lua; the game's font on Chinese and Korean clients):
	-- SemiBold for the wordmark, Regular for every other word
	local FONT = SP:BrandFontPath("regular")
	local BLUE, WHITE, TEXT = { 0.247, 0.663, 0.961 }, { 1, 1, 1 }, { 0.902, 0.918, 0.941 }
	local DIM, MUTE = { 0.541, 0.580, 0.651 }, { 0.353, 0.392, 0.455 }
	local panel = CreateFrame("Frame", "ShamanPowerInterfacePanel", UIParent)
	panel.name = "ShamanPower"
	panel:Hide()

	-- the navy card the page sits on
	local card = CreateFrame("Frame", nil, panel)
	card:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -4)
	card:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -4, 4)
	local bg = card:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(); bg:SetColorTexture(0.078, 0.106, 0.149, 1)
	local function Edge(p1, p2, horizontal)
		local t = card:CreateTexture(nil, "BORDER")
		t:SetColorTexture(0.169, 0.216, 0.290, 1)
		t:SetPoint(p1); t:SetPoint(p2)
		if horizontal then t:SetHeight(1) else t:SetWidth(1) end
	end
	Edge("TOPLEFT", "TOPRIGHT", true); Edge("BOTTOMLEFT", "BOTTOMRIGHT", true)
	Edge("TOPLEFT", "BOTTOMLEFT"); Edge("TOPRIGHT", "BOTTOMRIGHT")

	local function Text(size, color, text, weight)
		local fs = card:CreateFontString(nil, "ARTWORK")
		fs:SetFont(SP:BrandFontPath(weight), size, "")
		fs:SetTextColor(color[1], color[2], color[3])
		fs:SetText(text or "")
		return fs
	end

	-- the logo's totem boxes (no letters, no SP), drawn by the brand kit's port
	-- (ShamanPowerBrand.lua): 800 logo units -> 200 px, the boxes' own bounds
	local logo = SP:CreateTotemGraphic(card)
	logo:SetGraphicHeight(682 * 0.25)
	logo:SetPoint("TOP", card, "TOP", 0, -28)

	-- the wordmark ("Shaman" in logo blue, "Power" in white), centred as one
	local word = CreateFrame("Frame", nil, card)
	word:SetPoint("TOP", logo, "BOTTOM", 0, -26)
	local shaman, power = Text(32, BLUE, "Shaman", "semibold"), Text(32, WHITE, "Power", "semibold")
	shaman:SetParent(word); power:SetParent(word)
	shaman:SetPoint("LEFT", word, "LEFT", 0, 0)
	power:SetPoint("LEFT", shaman, "RIGHT", 0, 0)
	word:SetSize(1, 36)
	word:SetScript("OnShow", function(f) f:SetWidth(shaman:GetStringWidth() + power:GetStringWidth()) end)

	local tagline = Text(16, TEXT, "Totems, Done Right")
	tagline:SetPoint("TOP", word, "BOTTOM", 0, -8)
	local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
	local version = getMeta and getMeta("ShamanPower", "Version")
	local ver = Text(11, MUTE, version and ("Version " .. version) or "")
	ver:SetPoint("TOP", tagline, "BOTTOM", 0, -6)

	-- Options closes before one of ShamanPower's own windows opens
	local function CloseOptions()
		if SettingsPanel and SettingsPanel:IsShown() then
			if not pcall(HideUIPanel, SettingsPanel) then SettingsPanel:Hide() end
		end
		if InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown() then InterfaceOptionsFrame:Hide() end
		if GameMenuFrame and GameMenuFrame:IsShown() then GameMenuFrame:Hide() end
	end
	-- the blue bevel button of ShamanPower's settings (ui-style-guide): primary stronger;
	-- help = the same button in gold (Support Code)
	local function Button(w, h, label, size, primary, onClick, help)
		local b = CreateFrame("Button", nil, card)
		b:SetSize(w, h)
		local fill = b:CreateTexture(nil, "BACKGROUND")
		fill:SetAllPoints()
		local shade = b:CreateTexture(nil, "BORDER")
		shade:SetAllPoints(); shade:SetColorTexture(1, 1, 1, 1)
		if CreateColor and shade.SetGradient then
			shade:SetGradient("VERTICAL", CreateColor(0, 0, 0, 0.24), CreateColor(1, 1, 1, 0.06))
		else
			shade:SetColorTexture(0, 0, 0, 0.1)
		end
		local lit = b:CreateTexture(nil, "ARTWORK")
		lit:SetPoint("TOPLEFT", 1, -1); lit:SetPoint("TOPRIGHT", -1, -1); lit:SetHeight(1)
		if help then lit:SetColorTexture(1, 0.851, 0.4, 0.45) else lit:SetColorTexture(0.247, 0.663, 1, primary and 0.45 or 0.35) end
		local edges = {}
		for i = 1, 4 do edges[i] = b:CreateTexture(nil, "OVERLAY") end
		edges[1]:SetPoint("TOPLEFT"); edges[1]:SetPoint("TOPRIGHT"); edges[1]:SetHeight(1)
		edges[2]:SetPoint("BOTTOMLEFT"); edges[2]:SetPoint("BOTTOMRIGHT"); edges[2]:SetHeight(1)
		edges[3]:SetPoint("TOPLEFT"); edges[3]:SetPoint("BOTTOMLEFT"); edges[3]:SetWidth(1)
		edges[4]:SetPoint("TOPRIGHT"); edges[4]:SetPoint("BOTTOMRIGHT"); edges[4]:SetWidth(1)
		local caption = b:CreateFontString(nil, "OVERLAY")
		caption:SetFont(FONT, size, ""); caption:SetTextColor(1, 1, 1); caption:SetText(label)
		caption:SetPoint("CENTER", 0, 0)
		local function Paint(hover)
			if help then
				fill:SetColorTexture(1, 0.722, 0.110, hover and 0.56 or 0.40)
				for i = 1, 4 do
					if hover then edges[i]:SetColorTexture(1, 0.851, 0.4, 1) else edges[i]:SetColorTexture(1, 0.722, 0.110, 1) end
				end
				return
			end
			local a = primary and (hover and 0.62 or 0.46) or (hover and 0.46 or 0.28)
			fill:SetColorTexture(0, 0.439, 0.867, a)
			for i = 1, 4 do
				if hover then edges[i]:SetColorTexture(0.247, 0.663, 1, 1) else edges[i]:SetColorTexture(0, 0.439, 0.867, 1) end
			end
		end
		Paint(false)
		b:SetScript("OnEnter", function() Paint(true) end)
		b:SetScript("OnLeave", function() Paint(false) end)
		b:SetScript("OnMouseDown", function() caption:SetPoint("CENTER", 0, -1) end)
		b:SetScript("OnMouseUp", function() caption:SetPoint("CENTER", 0, 0) end)
		b:SetScript("OnClick", onClick)
		return b
	end
	local NEEDS_CONFIG = "|cff0070ddShamanPower|r: this needs the |cff0070ddShamanPower_Config|r module (enable it in your AddOns list)."
	local open = Button(340, 48, "Open ShamanPower Settings", 16, true, function()
		CloseOptions()
		if ShamanPowerConfig and ShamanPowerConfig.Open then ShamanPowerConfig:Open() else SP:OpenConfigWindow() end
	end)
	open:SetPoint("TOP", ver, "BOTTOM", 0, -22)
	local tour = Button(160, 32, "Setup Tour", 12, false, function()
		CloseOptions()
		if SP.Wizard and SP.Wizard.Open then SP.Wizard:Open() else print(NEEDS_CONFIG) end
	end)
	local news = Button(160, 32, "What's New", 12, false, function()
		CloseOptions()
		if SP.ShowWhatsNew then SP:ShowWhatsNew(true) else print(NEEDS_CONFIG) end
	end)
	local discord = Button(160, 32, "Discord", 12, false, function()
		-- WoW cannot open links: the invite in a box, selected, ready for Ctrl+C
		if SP.ShowSPDialog then
			SP:ShowSPDialog({ key = "discordLink", title = "ShamanPower Discord",
				text = "The link is selected: press |cffFFD100Ctrl+C|r to copy it, then paste it into your browser.",
				editText = "https://discord.gg/eCtNeBqE8U" })
		else
			print("|cff0070ddShamanPower|r: Discord: https://discord.gg/eCtNeBqE8U")
		end
	end)
	news:SetPoint("TOP", open, "BOTTOM", 0, -14)
	tour:SetPoint("RIGHT", news, "LEFT", -10, 0)
	discord:SetPoint("LEFT", news, "RIGHT", 10, 0)

	-- the ways in
	local rule = card:CreateTexture(nil, "BORDER")
	rule:SetColorTexture(0.169, 0.216, 0.290, 1); rule:SetHeight(1)
	rule:SetPoint("TOP", news, "BOTTOM", 0, -24)
	rule:SetPoint("LEFT", card, "LEFT", 40, 0); rule:SetPoint("RIGHT", card, "RIGHT", -40, 0)
	local TIPS = {
		{ "/sp", "opens the settings from chat" },
		{ "Minimap icon", "right-click it for the settings" },
		{ "Key bindings", "Options > Key Bindings > ShamanPower" },
	}
	local prev
	for _, tip in ipairs(TIPS) do
		local key = Text(12, BLUE, tip[1])
		local what = Text(12, DIM, tip[2])
		if prev then key:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -10) else key:SetPoint("TOPLEFT", rule, "BOTTOM", -200, -16) end
		what:SetPoint("LEFT", key, "LEFT", 150, 0)
		prev = key
	end
	-- under the ways in, apart from the everyday buttons: the code for #help, in gold like
	-- the settings' Support Code button (centered: the tips start 200 left of center)
	local support = Button(160, 28, "Support Code", 12, false, function()
		if SP.ShowSupportCode then SP:ShowSupportCode() end
	end, true)
	support:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 200 - 80, -18)
	local foot = Text(10, MUTE, "Made for TBC Anniversary and WoW: Forever")
	foot:SetPoint("BOTTOM", card, "BOTTOM", 0, 14)

	if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
		local category = Settings.RegisterCanvasLayoutCategory(panel, "ShamanPower")
		if category then
			category.ID = "ShamanPower"
			Settings.RegisterAddOnCategory(category)
		end
	elseif InterfaceOptions_AddCategory then
		InterfaceOptions_AddCategory(panel)
	end
	self.optionsFrame = panel
end

-- /sp and /shamanpower
-- /sp restrict: the client's forced-restriction cvars make it behave as if you were in a
-- boss fight, M+, a PvP match, an instance, combat or chat lockdown, so those paths can be
-- tested solo. They reset on login. Addon code must never SetCVar these (a tainted write
-- taints every Blizzard frame that later reads the restriction state), so this only shows
-- the state and prints the untainted command to type.
local RESTRICT_CVARS = {
	{ key = "encounter", cvar = "addonEncounterRestrictionsForced", label = "Boss encounter" },
	{ key = "mplus", cvar = "addonChallengeModeRestrictionsForced", label = "Mythic+" },
	{ key = "pvp", cvar = "addonPvPMatchRestrictionsForced", label = "PvP match" },
	{ key = "map", cvar = "addonMapRestrictionsForced", label = "Instance (map)" },
	{ key = "combat", cvar = "addonCombatRestrictionsForced", label = "Combat" },
	{ key = "chat", cvar = "addonChatRestrictionsForced", label = "Chat lockdown" },
}

function ShamanPower:RestrictCommand(args)
	local key, state = strsplit(" ", args or "", 2)
	local function value(cvar)
		local ok, v = pcall(GetCVar, cvar)
		if ok then return v end
	end
	local function line(r)
		local v = value(r.cvar)
		local shown = v == nil and "|cff808080n/a|r" or (v == "1" and "|cff4cc776ON|r" or "|cff808080off|r")
		print(string.format("  %s %s  |cff808080(/sp restrict %s)|r", r.label .. ":", shown, r.key))
	end
	if not key or key == "" then
		print("|cff0070ddShamanPower|r forced restrictions (reset on login):")
		for _, r in ipairs(RESTRICT_CVARS) do line(r) end
		return
	end
	for _, r in ipairs(RESTRICT_CVARS) do
		if r.key == key then
			-- nil on Forever: Lua cannot read it there (the cvar may still exist), so the line to type
			-- is printed anyway; the Classic line has no such cvars at all
			local v = value(r.cvar)
			if v == nil and not SPCompat.FOREVER then
				print("|cff0070ddShamanPower|r: " .. r.cvar .. " is not available in this version of the game.")
				return
			end
			local on
			if state == "on" or state == "1" then on = true
			elseif state == "off" or state == "0" then on = false
			else on = v ~= "1" end
			print(string.format("|cff0070ddShamanPower|r: %s is %s. Type this yourself:  |cffffd100/console %s %s|r",
				r.label, v == nil and "unknown (not readable here)" or (v == "1" and "ON" or "off"), r.cvar, on and "1" or "0"))
			return
		end
	end
	print("|cff0070ddShamanPower|r: /sp restrict [encounter | mplus | pvp | map | combat | chat] [on | off]")
end

SLASH_SHAMANPOWER1 = "/sp"
SLASH_SHAMANPOWER2 = "/shamanpower"
SlashCmdList["SHAMANPOWER"] = function(msg)
	msg = strtrim(strlower(msg or ""))
	if msg == "" or msg == "config" or msg == "options" or msg == "settings" then
		ShamanPower:OpenConfigWindow()
	elseif msg == "totems" or msg == "to" or msg == "assign" then
		ShamanPower:ToggleAssignmentWindow()
	elseif msg == "setup" or msg == "setup look" then
		-- "setup look": the tour with its Pick your look step, which otherwise only a new install sees
		if ShamanPower.Wizard and ShamanPower.Wizard.Open then
			ShamanPower.Wizard.showLookStep = (msg == "setup look") or nil
			ShamanPower.Wizard:Open()
		else print("|cff0070ddShamanPower|r: setup needs the ShamanPower_Config module.") end
	elseif msg == "welcome" then   -- the first-login choice window on demand (to test it on a set-up character)
		if ShamanPower.Wizard and ShamanPower.Wizard.ShowWelcomeChoice then ShamanPower.Wizard:ShowWelcomeChoice() else print("|cff0070ddShamanPower|r: setup needs the ShamanPower_Config module.") end
	elseif msg == "unlock" or msg == "move" then
		if ShamanPower.ToggleMasterUnlock then ShamanPower:ToggleMasterUnlock() end
	elseif msg == "range" then
		if ShamanPower.ToggleSPRange then ShamanPower:ToggleSPRange() end
	elseif msg == "bind" or msg == "keybind" or msg == "keys" then
		if ShamanPower.ToggleKeybindMode then ShamanPower:ToggleKeybindMode() end
	elseif msg == "share" then
		if ShamanPower.ShowShareCode then ShamanPower:ShowShareCode() end
	elseif msg == "support" then
		if ShamanPower.ShowSupportCode then ShamanPower:ShowSupportCode() end
	elseif msg == "themecheck" then
		-- the developer's tripwire (not in the help): Themes-tab changes a theme would not capture
		local g = ShamanPower.db and ShamanPower.db.global
		if g then
			g.themeCheck = not g.themeCheck or nil
			print("|cff0070ddShamanPower|r: theme check " .. (g.themeCheck and "|cff4cc776ON|r: a Themes-tab change a theme would not capture prints a warning." or "off."))
		end
	elseif msg == "check" then
		if ShamanPower.RunReadyCheckSweep then
			ShamanPower:RunReadyCheckSweep("manual")
		elseif not isShaman then   -- the Ready Check module loads for shamans only
			print("|cff0070ddShamanPower|r: /sp check is for shamans: it lists what a shaman is missing (shield, imbue, totem items).")
		end
	elseif msg == "restrict" or msg:sub(1, 9) == "restrict " then
		ShamanPower:RestrictCommand(strtrim(msg:sub(10)))
	else
		-- one command per line, the command in the style guide's gold. /sp restrict, /sptrace
		-- and /spperf are left out on purpose: tools for testing and bug reports.
		local function line(cmd, what) print("  |cffffd100" .. cmd .. "|r  " .. what) end
		print("|cff0070ddShamanPower|r commands:")
		line("/sp", "settings")
		line("/sp totems", "totem assignments")
		line("/sp setup", "the setup tour")
		line("/sp range", "totem range overlay")
		line("/sp bind", "keybind mode")
		line("/sp share", "your setup code")
		line("/sp support", "a support code to paste in #help")
		if ShamanPower.RunReadyCheckSweep then line("/sp check", "what you are missing (shield, imbue, totem items)") end
		if ShamanPower.SetResistPractice then line("/sp resisttest", "practice raid resistance requests (pretend shamans, nothing sent)") end
		if ShamanPower.RaidCooldownsLoaded then line("/sp calltest", "practice Mana Tide calls as if you knew Mana Tide") end
	end
end

function ShamanPower_ClearAssignments()
	if InCombatLockdown() then return end

	if GetNumGroupMembers() > 0 and ShamanPower:CheckLeader(ShamanPower.player) then
		-- Leader clears everyone and broadcasts
		ShamanPower:ClearAssignments(ShamanPower.player)
		ShamanPower:SendMessage("CLEAR")
	else
		-- Non-leader or solo: clear own assignments
		ShamanPower:ClearAssignments(ShamanPower.player)
		if GetNumGroupMembers() > 0 then
			ShamanPower:SendSelf()
		end
	end
	ShamanPower:UpdateLayout()
	ShamanPower:UpdateRoster()
end

function ShamanPower_RefreshAssignments()
	ShamanPower:Debug("ShamanPower_RefreshAssignments")
	ShamanPower:ScanSpells()
	if GetNumGroupMembers() > 0 then
		ShamanPower:SendSelf()
		ShamanPower:RequestShamanData()
	end
	ShamanPower:UpdateLayout()
	ShamanPower:UpdateRoster()
end

-- Windfury-only mode (non-shamans): ShamanPower runs nothing but the quiet
-- "my weapon has Windfury" report to the group's shamans. No frames, no Totem
-- Plates, no caller buttons. The minimap icon stays: its right-click menu then
-- holds one entry that turns everything back on (and /sp does too).
function ShamanPower:WindfuryOnly()
	-- WoW: Forever made Windfury Totem a party buff the shaman's own addon reads,
	-- so the report (this mode's only job) is gone there
	if SPCompat.FOREVER then return false end
	return self.opt and self.opt.windfuryOnly == true and select(2, UnitClass("player")) ~= "SHAMAN" or false
end

function ShamanPower:SetWindfuryOnly(on)
	if select(2, UnitClass("player")) == "SHAMAN" then return end
	if SPCompat.FOREVER then return end
	self.opt.windfuryOnly = on and true or nil
	ShamanPowerMinimapIcon_Toggle()
	if self.UpdateSPRangeVisibility then self:UpdateSPRangeVisibility() end
	if self.UpdateCallerButtons then self:UpdateCallerButtons() end
	if self.ToggleTotemPlates then self:ToggleTotemPlates() end
	if self.UpdateWindfuryBroadcaster then self:UpdateWindfuryBroadcaster() end
end

-- Enable ShamanPower off: the whole addon goes quiet, the way Windfury-only mode
-- does for non-shamans, for every class. Nothing is drawn, announced, sent or
-- bound, Blizzard's totem bar is left alone, and every setting stays open to
-- change. The minimap icon stays: any click on it offers the one way back
-- (and the settings toggle does too). Each part checks IsOff() where it decides
-- to show or run; OnOnOff() lets the module addons re-check theirs on a switch.
-- IsOff() is the state everything is set up for: a switch made in combat
-- takes effect for every part at once when the fight ends (the settings
-- toggle shows the saved choice right away).
function ShamanPower:IsOff()
	if self._appliedOff ~= nil then return self._appliedOff end
	return self.opt and self.opt.enabled == false or false
end

local onOffHandlers = {}
function ShamanPower:OnOnOff(fn)
	onOffHandlers[#onOffHandlers + 1] = fn
end

function ShamanPower:SetOff(off)
	self.opt.enabled = not off
	if InCombatLockdown() then   -- the bars are secure frames: switch after the fight
		self._onOffPendingCombat = true
		print("|cff0070ddShamanPower|r: turns " .. (off and "off" or "on") .. " when combat ends.")
		return
	end
	self:ApplyOnOff()
end

function ShamanPower:ApplyOnOff()
	self._onOffPendingCombat = nil
	local off = self.opt.enabled == false
	-- switched and switched back in the same fight (or a new profile with the
	-- same choice): nothing to change, and nothing is sent or asked again
	if off == self._appliedOff then return end
	self._appliedOff = off
	if off then self:UnbindKeys() else self:BindKeys() end
	-- popped-out trackers: hide the shown ones, bring back only those (or, when
	-- the switch was off at login, the saved ones for the first time)
	for _, frame in pairs(self.poppedOutFrames or {}) do
		if off and frame:IsShown() then
			frame.spHiddenByOff = true
			frame:Hide()
		elseif not off and frame.spHiddenByOff then
			frame.spHiddenByOff = nil
			frame:Show()
		end
	end
	if not off and self._popOutsSkippedByOff then
		self._popOutsSkippedByOff = nil
		self:RestorePoppedOutTrackers()
	end
	-- Blizzard's totem bar: the Blizzard style lets go of it, the hide option gives it back
	if self.RefreshBlizzardTotemBar then self:RefreshBlizzardTotemBar() end
	self:UpdateLayout()   -- the totem bar (UpdateRoster skips solo players)
	if not off then
		-- the flyout click mode on the totem buttons, as at login (buttons first
		-- built by this switch-on, when it was off at login, start on mouseover)
		C_Timer.After(0.5, function()
			if not InCombatLockdown() and not self:IsOff() then self:UpdateTotemFlyoutEnabled() end
		end)
	end
	self:UpdateTotemBarVisibility(true)
	if self.UpdateCooldownBar then self:UpdateCooldownBar() end
	if self.UpdateLoadoutBar then self:UpdateLoadoutBar() end
	if self.ApplyBlizzardTotemBarHiding then self:ApplyBlizzardTotemBarHiding() end
	-- one part's error is reported but never stops the others from switching
	for i = 1, #onOffHandlers do xpcall(onOffHandlers[i], geterrorhandler(), off) end
	ShamanPowerMinimapIcon_Toggle()
	if self.RefreshConfig then self:RefreshConfig() end   -- an open settings window shows the switch
end

function ShamanPowerMinimapIcon_Toggle()
	if ShamanPower.opt.minimap.show == false then
		ShamanPower.MinimapIcon:Hide("ShamanPower")
	else
		ShamanPower.MinimapIcon:Show("ShamanPower")
	end
end

-- The core's own part of a switch. Off: the central update loop stops (each
-- subsystem keeps its own on/off and ticks again on switch-on), the totem and
-- cooldown key bindings are cleared, and messages still waiting to go out are
-- dropped. On: bindings back, the shield / Earth Shield / buff reads that slept
-- are taken fresh, and the group hears from us (and we ask for its data).
-- Hide Blizzard's Totem Timers (Totem Bar > Bar): the small totem icons and
-- timers the game draws under the player frame (TotemFrame). Faded out and
-- made click-through, never hidden: the game shows it again on every totem
-- change, and hiding it would run Blizzard's player-frame layout from addon
-- code (taint). The hook is only put on once the option is used.
function ShamanPower:ApplyPlayerTotemFrame()
	local f = _G.TotemFrame
	if not (f and f.totemPool) then return end
	local hide = (self.opt and self.opt.hidePlayerTotems and not self:IsOff()) and true or false
	if hide and not self._playerTotemHooked and type(f.Update) == "function" then
		self._playerTotemHooked = true
		-- the pool hands out buttons again on every totem change: keep them click-through
		hooksecurefunc(f, "Update", function(frame)
			local on = not ShamanPower._playerTotemHidden
			for b in frame.totemPool:EnumerateActive() do b:EnableMouse(on) end
		end)
	end
	self._playerTotemHidden = hide
	f:SetAlpha(hide and 0 or 1)
	for b in f.totemPool:EnumerateActive() do b:EnableMouse(not hide) end
end

ShamanPower:OnOnOff(function(off)
	local sp = ShamanPower
	sp._appliedOff = off
	sp:ApplyPlayerTotemFrame()   -- switched off: Blizzard's totem timers come back
	sp:SyncUpdateFrame()   -- off: the loop stops; on: it runs whatever is switched on
	sp:SetupKeybindings()
	if off then
		sp:DropHeldMessages()
		sp:ForgetEngineCooldownReads()   -- nothing is read for the buttons on cooldown events while off
		return
	end
	sp:ScanPlayerShield()
	sp:RefreshEarthShieldTarget()
	sp:RefreshPlayerBuffCache()
	if GetNumGroupMembers() > 0 then
		sp:SendSelf(nil, true)
		sp:RequestShamanData()
	end
end)

-- ============================================================================
-- Totem Status Detection
-- ============================================================================

-- Map our element IDs to WoW's totem slots
-- Our addon: 1=Earth, 2=Fire, 3=Water, 4=Air
-- WoW slots: 1=Fire, 2=Earth, 3=Water, 4=Air
ShamanPower.ElementToSlot = {
	[1] = 2,  -- Earth -> slot 2
	[2] = 1,  -- Fire -> slot 1
	[3] = 3,  -- Water -> slot 3
	[4] = 4,  -- Air -> slot 4
}

-- Classic clients keep each element in its fixed slot above. The retail client
-- (and possibly Forever) fills the slots in cast order instead, so a lone Earth
-- totem lands in slot 1. Every "which totem of this element is down" lookup
-- goes through GetElementTotemInfo: it trusts the fixed slot until it sees a
-- totem of another element sitting there, then resolves by totem name for the
-- rest of the session.
ShamanPower.dynamicTotemSlots = (SPCompat.FOREVER)

-- WoW: Forever cannot twist: its Windfury Totem is a party aura (no weapon buff
-- that outlasts the totem), and Windfury, Grace of Air and Tranquil Air no
-- longer stack. Twisting is not offered there and stays off, whatever a profile
-- saved. Anniversary keeps all of it.
ShamanPower.NoTotemTwisting = (SPCompat.FOREVER)
-- 3.0 changed defaults: both bars run across (Horizontal), and no frame or
-- border is drawn behind the totem bar, the cooldown bar, the caller buttons,
-- the Earth Shield tracker or the range tracker. A profile saved before keeps
-- the look it had (it never stored those, so it would change under the player);
-- a new profile gets the new look. Once per install, over every saved profile.
function ShamanPower:KeepOldLookOnSavedProfiles()
	local sv = self.db and self.db.sv
	if not sv or (sv.global and sv.global.oldLookKept) then return end
	-- AceDB puts empty tables into a profile it sets up: only real values count
	local function saved(t)
		for _, v in pairs(t) do
			if type(v) ~= "table" or saved(v) then return true end
		end
		return false
	end
	local function keep(t, key, old)
		if rawget(t, key) == nil then rawset(t, key, old) end
	end
	for _, prof in pairs(sv.profiles or {}) do
		if type(prof) == "table" and saved(prof) then
			keep(prof, "layout", "Vertical")
			keep(prof, "hideTotemBarFrame", false)
			keep(prof, "hideCooldownBarFrame", false)
			keep(prof, "raidCDButtonHideFrame", false)
			for _, sub in ipairs({ "esTracker", "rangeTracker" }) do
				if type(rawget(prof, sub)) ~= "table" then
					local d = SHAMANPOWER_DEFAULT_VALUES.profile[sub]
					rawset(prof, sub, d and DeepCopy(d) or {})
					rawget(prof, sub).hideBorder = false   -- (the copy carries the new default)
				else
					keep(rawget(prof, sub), "hideBorder", false)
				end
			end
		end
	end
	self.db.global.oldLookKept = true
end

-- 3.0.4 gave the pulse flash its own "for Specific Totems" list. In 3.0.3 the
-- pulse bar list switched a totem's flash off too, so a profile that used it
-- keeps that look: the flash list starts as a copy of it (once per profile).
function ShamanPower:SplitPulseFlashList()
	local o = self.opt
	if not o or o.pulseFlashSplit then return end
	o.pulseFlashSplit = true
	if o.pulseOnlySome and o.pulseFlashOnlySome == nil then
		o.pulseFlashOnlySome = true
		local off = {}
		for k, v in pairs(o.pulseTotemsOff or {}) do off[k] = v end
		o.pulseFlashTotemsOff = off
	end
end

function ShamanPower:ClearTwistingOnForever()
	if not self.NoTotemTwisting then return end
	self.opt.enableTotemTwisting = nil
	if ShamanPower_TwistAssignments then wipe(ShamanPower_TwistAssignments) end
end

local totemNameElementCache = {}

-- Teach the resolver a totem name (used by discovery on clients whose totem
-- list differs from the static tables). Also clears a cached miss.
function ShamanPower:RegisterTotemElement(totemName, element)
	if issecretvalue(totemName) or issecretvalue(element) then return end
	if totemName and element then
		totemNameElementCache[totemName] = element
	end
end

-- Element (1-4) a totem name belongs to, or nil if it matches nothing known.
-- Whole names prevent weapon imbues from being mistaken for totem casts.
function ShamanPower:TotemNameElement(totemName)
	if issecretvalue(totemName) then return nil end
	if not totemName or totemName == "" then return nil end
	local cached = totemNameElementCache[totemName]
	if cached ~= nil then return cached or nil end

	-- A translated cast name need not contain any part of its English label.
	for element = 1, 4 do
		for index, id in pairs(self.Totems and self.Totems[element] or {}) do
			local fallback = self.TotemNames and self.TotemNames[element] and self.TotemNames[element][index]
			if SPCompat.TotemNameMatches(totemName, id, fallback) then
				totemNameElementCache[totemName] = element
				return element
			end
		end
	end
	totemNameElementCache[totemName] = false
	return nil
end

-- Element (1-4) of a totem spell ID from the static tables, or nil.
local totemSpellElementCache
function ShamanPower:TotemSpellElement(spellID)
	if issecretvalue(spellID) then return nil end
	if type(spellID) ~= "number" or spellID == 0 then return nil end
	if not totemSpellElementCache then
		totemSpellElementCache = {}
		for element = 1, 4 do
			for _, id in pairs(self.Totems and self.Totems[element] or {}) do
				if type(id) == "number" then
					totemSpellElementCache[id] = element
					-- and every rank of it, by ID: a higher rank's name can differ from the
					-- first rank's in some languages, so it must never be found by name
					for _, rank in ipairs(SPCompat.SpellRanks(id) or {}) do
						if totemSpellElementCache[rank] == nil then totemSpellElementCache[rank] = element end
					end
				end
			end
		end
		-- (TalentTotems' first field is the talent TREE, not the element: the talent
		-- totems are already in the element tables above, so they are not read again)
	end
	return totemSpellElementCache[spellID]
end

-- Element a slot's totem belongs to: the spell ID when the client reports one
-- (retail's 7th GetTotemInfo return), else the name tables. nil = unknown.
local function slotTotemElement(self, totemName, spellID)
	return self:TotemSpellElement(spellID) or self:TotemNameElement(totemName)
end

-- The name ShamanPower's checks use for a totem that is down. The game names a
-- summoned totem on its own, and in some languages that name is not its spell's:
-- Spanish above all ("Tótem piel de piedra" for the spell "Tótem Piel de piedra"),
-- also a few totems in French, Portuguese, Russian and Chinese (every client
-- language's game data checked, 2026-10-04). So a totem whose spell ID the game
-- gives is named after its first rank's spell, the name every check compares with
-- (Mana Spring: the name it is cast by). No ID, or a spell outside the tables:
-- the game's own name, as before.
function ShamanPower:CanonicalTotemName(name, spellID)
	if issecretvalue(spellID) or type(spellID) ~= "number" or spellID == 0 then return name end
	local canon = self._totemCanon
	if not canon or canon.gen ~= SPCompat.SpellDataGeneration then
		canon = { gen = SPCompat.SpellDataGeneration, names = {} }
		for element = 1, 4 do
			for _, id in pairs(self.Totems and self.Totems[element] or {}) do
				if type(id) == "number" then
					local castName
					if SPCompat.HasTotemCastAliases(id) then castName = SPCompat.TotemCastName(id) end
					castName = castName or SPCompat.SpellName(id)
					if castName then
						canon.names[id] = castName
						for _, rank in ipairs(SPCompat.SpellRanks(id) or {}) do
							if canon.names[rank] == nil then canon.names[rank] = castName end
						end
					end
				end
			end
		end
		self._totemCanon = canon
	end
	return canon.names[spellID] or name
end

-- ----------------------------------------------------------------------------
-- Shadow totem model. On a restricted client (retail rules, Forever) the
-- totem API returns secret values in combat, but the player's own casts never
-- do. So we keep our own record of what we dropped: UNIT_SPELLCAST_SUCCEEDED
-- for a totem spell opens an entry for its element (name/icon from the static
-- spell data, duration learned from the API while it was readable), and
-- PLAYER_TOTEM_UPDATE binds it to a slot or, arriving with no cast behind it,
-- retires whatever sat in that slot (expired, destroyed, recalled). While the
-- API is readable the model is simply refreshed from it, so it is exact at the
-- moment combat starts. On classic clients the model is maintained but never
-- consulted.
-- ----------------------------------------------------------------------------
ShamanPower.shadowTotems = {}          -- [element] = { spellID, name, icon, startTime, duration, slot }
local shadowLearnedDuration = {}       -- [spellID] = duration seen from the API
local SHADOW_DEFAULT_DURATION = 120    -- until the real duration has been observed once
-- Learned lengths are kept per character (db.char.totemDurations), so after a
-- /reload or a new login a totem first dropped in combat still has its real length:
-- its timer is right, and a kill mid-fight still reads as "destroyed" instead of
-- "unknown". Not account-wide: another character's talents, gear or rank could make
-- the same totem last a different time, and a length too long would turn its natural
-- expiry into a false "destroyed". The saved table is bound on first use (the db
-- exists by then).
local shadowDurationsSaved = false
local function learnedDurations()
	if not shadowDurationsSaved then
		-- only where the model is consulted (the secrets regime): Anniversary saves nothing new
		local db = SPCompat and SPCompat.secretsRegime and ShamanPower.db
		local c = db and db.char
		if not c then return shadowLearnedDuration end
		shadowDurationsSaved = true
		if db.global then db.global.totemDurations = nil end   -- an earlier test build kept them account-wide
		c.totemDurations = c.totemDurations or {}
		for id, d in pairs(shadowLearnedDuration) do c.totemDurations[id] = d end
		shadowLearnedDuration = c.totemDurations
	end
	return shadowLearnedDuration
end
-- On a cold login to WoW: Forever the game can still call the player "Unknown" while
-- addons load, so everything that takes the name then files it under a character called
-- "Unknown": our own player name (assignments, the name sent to other shamans) and AceDB's
-- character key (per-character data such as learned totem lengths, and which profile this
-- character uses). Measured 2026-09-24: a whole session's assignments and totem lengths
-- saved under "Unknown", then "not learned" after a /reload. Once the real name is
-- readable this puts both right; false while the game still has no name.
local function nameKnown(n)
	return type(n) == "string" and n ~= "" and n ~= "Unknown" and n ~= UNKNOWNOBJECT
end
local PER_NAME_TABLES = { "ShamanPower_Assignments", "ShamanPower_TwistAssignments", "ShamanPower_EarthShieldAssignments" }
function ShamanPower:FixPlayerIdentity()
	local name = UnitName("player")          -- "First Surname" on Forever (SPCompat.UnitName)
	local first = _G.UnitName("player")      -- AceDB keys on the game's first return
	if not nameKnown(name) or not nameKnown(first) then return false end
	local old = self.player
	self.player = name
	for _, global in ipairs(PER_NAME_TABLES) do
		local t = _G[global]
		if type(t) == "table" then
			-- this login's own entries, written before the name was known, belong to the real name;
			-- so do ones filed under the first name alone (builds before the surname was read)
			for _, stale in ipairs({ old, first }) do
				if stale and stale ~= name and t[stale] ~= nil then
					if t[name] == nil then t[name] = t[stale] end
					t[stale] = nil
				end
			end
			-- left over from an earlier cold login: whose it was cannot be told, so it goes
			t.Unknown = nil
			if UNKNOWNOBJECT then t[UNKNOWNOBJECT] = nil end
		end
	end
	if self.AllShamans then
		if old and old ~= name then self.AllShamans[old] = nil end
		if first ~= name then self.AllShamans[first] = nil end
	end
	-- AceDB took its character key when it loaded and never looks again
	local db = self.db
	local keys = db and rawget(db, "keys")
	local sv = db and rawget(db, "sv")
	if keys and sv and type(keys.char) == "string" then
		local realKey = first .. " - " .. (GetRealmName() or "")
		local badKey = keys.char
		if badKey ~= realKey and not nameKnown((badKey:match("^(.-) %- "))) then
			keys.char = realKey
			rawset(db, "char", nil)   -- AceDB builds db.char from sv.char[keys.char] on its next use
			if sv.char then sv.char[badKey] = nil end   -- mixed whichever characters logged in cold
			shadowDurationsSaved, shadowLearnedDuration = false, {}   -- rebind learned lengths to the real character
			self.aceCharKeyFix = { bad = badKey, real = realKey }
			local pk = sv.profileKeys
			if pk then
				local current = db:GetCurrentProfile()
				local want = pk[realKey] or current
				pk[badKey], pk[realKey] = nil, want
				-- this character has its own profile: switch to it once the addon is up
				if want ~= current then C_Timer.After(0, function() self.db:SetProfile(want) end) end
			end
		end
		-- "Unknown" leftovers from earlier cold logins, whoever they were: never read again
		for _, store in ipairs({ sv.char, sv.profileKeys }) do
			if type(store) == "table" then
				for key in pairs(store) do
					if key ~= keys.char and type(key) == "string" and not nameKnown((key:match("^(.-) %- "))) then store[key] = nil end
				end
			end
		end
	end
	return true
end

local SHADOW_BIND_WINDOW = 0.5         -- seconds between a cast and its PLAYER_TOTEM_UPDATE
local shadowPendingCast                -- { element, at } waiting for its slot update
local shadowPendingSlot                -- { slot, at } update that arrived before its cast event
local lastSlotUpdateAt = {}            -- [slot] = GetTime() of the last PLAYER_TOTEM_UPDATE for it
-- A totem retired while combat hides totem data is only announced (OnShadowTotemGone)
-- after one bind window, so a set summon whose slot updates arrived BEFORE its cast
-- can still claim the slot and cancel the false "destroyed". One record per slot.
local pendingGone = {}                 -- [slot] = { element, entry, at }
-- A single re-drop of an element whose slot update came BEFORE its cast event
-- retires the old totem of that element; a cast of the same element this soon
-- after is that re-drop, not a new totem after a kill (a player cannot react
-- that fast). Kept short for that reason.
local SHADOW_REDROP_WINDOW = 0.25

-- The player's own dismissals: a right-click on a totem button (ShamanPower's or
-- Blizzard's) runs DestroyTotem(slot), and the slot update that follows has no
-- cast behind it. Without this stamp it read as "destroyed by enemies".
-- A secure hook: it runs after the call and never taints it. Mainline family only,
-- where the shadow model is consulted. The one stamp of your own dismissals:
-- modules that need it read ShamanPower._totemDismissedAt rather than hooking again.
ShamanPower._totemDismissedAt = {}     -- [slot] = GetTime()
if SPCompat.FOREVER and type(DestroyTotem) == "function" and hooksecurefunc then
	hooksecurefunc("DestroyTotem", function(slot)
		if issecretvalue and issecretvalue(slot) then return end
		slot = tonumber(slot)
		if slot then ShamanPower._totemDismissedAt[slot] = GetTime() end
	end)
end

local function totemsSecretNow()
	return SPCompat and SPCompat.secretsRegime and SPCompat.AnyRestrictionActive and SPCompat.AnyRestrictionActive() or false
end

-- ----------------------------------------------------------------------------
-- Where our totems went down. Range to our own totem is read from its buff,
-- but combat hides buffs on the Mainline family and a hidden buff reads the
-- same as a missing one, so every totem greyed out as "out of range" the
-- moment a fight started. A totem lands at the shaman's feet, so the player's
-- own position at the drop is the totem's position, and distance from it is
-- range. UnitPosition stays readable in combat in the open world; where it
-- doesn't (instances), the range check keeps what it last knew.
-- ----------------------------------------------------------------------------
local TRACK_TOTEM_DROPS = (SPCompat.FOREVER)
local TOTEM_AURA_RANGE = 30            -- yards: every buff totem's radius in the Forever 1.60.1 spell data
ShamanPower.totemDropPos = {}          -- [element] = { x, y, map }
ShamanPower.totemRangeLast = {}        -- [element] = last range answer while buffs were readable

-- Shared model radius, not a promise of exact per-spell or talent-modified reach.
function ShamanPower.GetTotemRangeModelRadius()
	return TOTEM_AURA_RANGE
end

local function unitPosition(unit)
	if not UnitPosition then return nil end
	local ok, y, x, _, map = pcall(UnitPosition, unit)
	if not ok or type(x) ~= "number" or type(y) ~= "number" then return nil end
	if issecretvalue and (issecretvalue(x) or issecretvalue(y)) then return nil end
	return x, y, map
end

function ShamanPower:RecordTotemDrop(element)
	if not TRACK_TOTEM_DROPS or not element then return end
	local x, y, map = unitPosition("player")
	self.totemDropPos[element] = x and { x = x, y = y, map = map } or nil
	self.totemRangeLast[element] = nil   -- a new totem: the old answer no longer applies
end

-- true/false = within/outside totem range of where this element's totem was
-- dropped; nil = can't tell (no drop recorded, or no position right now).
-- unit defaults to the player; party members measure the same way (UnitPosition
-- returns plain numbers for them in combat in the open world, measured).
function ShamanPower:TotemDropInRange(element, unit)
	-- dev switch: behave as if inside an instance, where the client gives out no
	-- positions, so the no-position fallbacks can be tested in the open world
	-- (/run ShamanPower.debugNoPositions = true)
	if self.debugNoPositions then return nil end
	local drop = self.totemDropPos[element]
	if not drop then return nil end
	local x, y, map = unitPosition(unit or "player")
	if not x or map ~= drop.map then return nil end
	local dx, dy = x - drop.x, y - drop.y
	return dx * dx + dy * dy <= TOTEM_AURA_RANGE * TOTEM_AURA_RANGE
end

-- Element a cast totem spell belongs to: by ID for every rank (TotemSpellElement),
-- the spell name only for a spell outside the rank lists.
function ShamanPower:TotemCastElement(spellID)
	local element = self:TotemSpellElement(spellID)
	if element then return element end
	local name = SPCompat.SpellName(spellID)
	if not name then return nil end
	return self:TotemNameElement(name)
end

function ShamanPower:ShadowTotemCast(unit, spellID)
	if issecretvalue(unit) or issecretvalue(spellID) then return end
	if unit ~= "player" or type(spellID) ~= "number" then return end
	local element = self:TotemCastElement(spellID)
	if not element then
		-- Call of the Elements / Ancestors / Spirits (Forever): one cast, several totems
		local set = self.TotemSetForSummon and self:TotemSetForSummon(spellID)
		if set then self:ShadowTotemSetCast(set) return end
		-- Recall and Projection suppress destroyed cues while the slots settle.
		if spellID == 36936 or spellID == 437009 then self._totemRecallAt = GetTime() end
		return
	end
	self:RecordTotemDrop(element)
	local name, _, icon = GetSpellInfo(spellID)
	name = self:CanonicalTotemName(name, spellID)
	local now = GetTime()
	local learned = learnedDurations()[spellID] or (self.TotemBaseDurations and self.TotemBaseDurations[spellID])
	local entry = {
		spellID = spellID,
		name = name,
		icon = icon,
		startTime = now,
		duration = learned or SHADOW_DEFAULT_DURATION,
		durationKnown = learned ~= nil,   -- a guessed length cannot tell expired from destroyed
		slot = nil,
	}
	-- the same element can only hold one totem; the old one is replaced
	self.shadowTotems[element] = entry
	-- The slot update can arrive BEFORE the cast event. Then it either filled an
	-- empty slot (nothing retired: bind to it), or it retired this element's
	-- previous totem a moment ago: that was this re-drop replacing it, not a kill,
	-- so bind to that slot too and take back the old totem's "gone" notice.
	local pending = shadowPendingSlot
	local age = pending and (now - pending.at)
	if pending and ((pending.element == nil and age <= SHADOW_BIND_WINDOW)
		or (pending.element == element and age <= SHADOW_REDROP_WINDOW)) then
		local slot = pending.slot
		entry.slot = slot
		shadowPendingSlot = nil
		local gone = pendingGone[slot]
		if gone and gone.element == element and now - gone.at <= SHADOW_REDROP_WINDOW then
			pendingGone[slot] = nil
		end
		-- bound by the update that retired the old totem: if this totem's own update
		-- still follows, it comes with this cast (the same frame) and confirms the
		-- binding rather than retiring it
		if pending.element then entry.boundEarlyAt = now end
	else
		shadowPendingCast = { element = element, at = now }
	end
end

-- A totem-set summon drops up to four totems from one cast, so there is no cast
-- per slot to bind. Open an entry per totem the page holds, bound to that
-- element's slot, and let the slot updates that follow confirm them. A totem the
-- summon could not place (no mana, not known) gets no slot update and is dropped.
local SET_CONFIRM_WINDOW = SHADOW_BIND_WINDOW + 0.3
function ShamanPower:ShadowTotemSetCast(spells)
	local now, placed = GetTime(), false
	for element = 1, 4 do
		local id = spells[element]
		local name, _, icon = GetSpellInfo(id or 0)
		if id and name then
			name = self:CanonicalTotemName(name, id)
			local slot = self.ElementToSlot and self.ElementToSlot[element] or element
			local learned = learnedDurations()[id] or (self.TotemBaseDurations and self.TotemBaseDurations[id])
			local entry = {
				spellID = id, name = name, icon = icon, startTime = now,
				duration = learned or SHADOW_DEFAULT_DURATION,
				durationKnown = learned ~= nil,
				slot = slot,
				setAt = now, setPending = true,
				setPrev = self.shadowTotems[element],   -- put back if this one never lands
			}
			self.shadowTotems[element] = entry
			-- the slot update can arrive BEFORE the cast event: if this slot just changed,
			-- the totem has already landed; confirm it now, and take back any
			-- "destroyed" the old totem's retirement queued a moment ago
			local at = lastSlotUpdateAt[slot]
			if at and now - at <= SHADOW_BIND_WINDOW then
				entry.setPending = nil
				entry.setPrev = nil
				pendingGone[slot] = nil
				if shadowPendingSlot and shadowPendingSlot.slot == slot then shadowPendingSlot = nil end
				self:RecordTotemDrop(element)   -- placed for sure
			end
			placed = true
		end
	end
	if not placed then return end
	self:InvalidateTotemInfo()
	C_Timer.After(SET_CONFIRM_WINDOW, function()
		local changed = false
		for element, entry in pairs(self.shadowTotems) do
			if entry.setPending and entry.setAt == now then
				self.shadowTotems[element] = entry.setPrev   -- never placed: the totem that was there stays
				changed = true
			elseif entry.setAt == now then
				entry.setPrev = nil   -- confirmed: the old record is no longer needed
			end
		end
		if changed then self:InvalidateTotemInfo() end
	end)
end

function ShamanPower:ShadowTotemSlotUpdate(slot)
	if type(slot) ~= "number" then return end
	local now = GetTime()
	lastSlotUpdateAt[slot] = now
	-- a slot filled by a totem-set summon: confirm that entry instead of retiring it.
	-- Only that slot is claimed; any other slot's update goes through the normal path.
	for element, entry in pairs(self.shadowTotems) do
		if entry.setPending and entry.slot == slot and now - entry.setAt <= SET_CONFIRM_WINDOW then
			entry.setPending = nil
			self:RecordTotemDrop(element)   -- the summon really placed this one
			-- Put Your Usual Totem Back (ShamanPowerUsualTotem.lua): that totem landed
			if self.UsualTotemSetPlaced then self:UsualTotemSetPlaced(element, entry) end
			return
		end
	end
	if shadowPendingCast and now - shadowPendingCast.at <= SHADOW_BIND_WINDOW then
		local entry = self.shadowTotems[shadowPendingCast.element]
		if entry then entry.slot = slot end
		shadowPendingCast = nil
		return
	end
	-- a totem bound to this slot by an update that came before its cast (ShadowTotemCast):
	-- its own update, arriving with that cast (the same frame, so the same GetTime()),
	-- is not its end. Only that one: any later update, even a moment later, is the
	-- totem going (killed as it landed) and must not be swallowed. Like the cast-first
	-- path above, this counts on one slot update per totem placed. That is unmeasured
	-- (a /sptrace of a re-drop shows it); a client that sent two would trip both paths.
	for _, entry in pairs(self.shadowTotems) do
		if entry.slot == slot and entry.boundEarlyAt == now then
			entry.boundEarlyAt = nil
			return
		end
	end
	-- no cast behind this update: the totem that lived in the slot is gone
	local retiredElement
	for element, entry in pairs(self.shadowTotems) do
		if entry.slot == slot then
			self.shadowTotems[element] = nil
			retiredElement = element
			-- While the game hides totem data (combat on Forever) this is the only way to
			-- know a totem went: tell whoever listens (Expiring Alerts, the bar's
			-- Effects) why, as best we can.
			if (self.OnShadowTotemGone or (self.TotemCuesWanted and self:TotemCuesWanted())
				or (self.UsualTotemWanted and self:UsualTotemWanted())) and totemsSecretNow() then
				-- announced one bind window later: a cast that arrives just after its own
				-- slot updates (a totem set, or a re-drop of this element) claims the slot
				-- and cancels this. The reason is worked out then too, so a Totemic Recall
				-- or a right-click dismiss whose event trails the slot update still counts.
				local rec = { element = element, entry = entry, at = now,
					dead = UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") or nil }
				pendingGone[slot] = rec
				C_Timer.After(SHADOW_BIND_WINDOW, function()
					if pendingGone[slot] ~= rec then return end   -- claimed by a cast, or replaced
					pendingGone[slot] = nil
					local e, at = rec.entry, rec.at
					local recall, dismissed = self._totemRecallAt, self._totemDismissedAt[slot]
					local why
					if recall and at - recall < 2 then why = "recalled"
					elseif dismissed and at - dismissed < 2 then why = "dismissed"
					elseif rec.dead or (UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")) then why = "died"
					elseif not e.durationKnown then why = "unknown"
					elseif at >= e.startTime + e.duration - 1 then why = "expired"
					else why = "destroyed" end
					if SPCompat and SPCompat.Trace and (not SPCompat.TraceOn or SPCompat.TraceOn()) then   -- formats nothing while /sptrace is off
						SPCompat.Trace("SHADOW gone element %d: %s (%.1f s after the drop, length %s)", rec.element, why,
							at - e.startTime, e.durationKnown and string.format("%.0f s", e.duration) or "not learned")
					end
					if self.OnShadowTotemGone then pcall(self.OnShadowTotemGone, self, rec.element, e, why) end
					if self.TotemEndCue then pcall(self.TotemEndCue, self, rec.element, why) end
					-- Put Your Usual Totem Back (ShamanPowerUsualTotem.lua): last, after the bar's own effects
					if self.UsualTotemGone then pcall(self.UsualTotemGone, self, rec.element, e, why) end
				end)
			end
		end
	end
	-- remember the update briefly in case the cast event trails it; if it retired a
	-- totem, only a re-drop of that element may claim it (ShadowTotemCast)
	shadowPendingSlot = { slot = slot, at = now, element = retiredElement }
end

-- Refresh one element's entry from readable API data (called on every readable lookup).
local function shadowSyncFromAPI(self, element, haveTotem, name, startTime, duration, icon, slot, spellID)
	if haveTotem and name and name ~= "" then
		local entry = self.shadowTotems[element]
		if not entry or entry.name ~= name then
			entry = { spellID = spellID }
			self.shadowTotems[element] = entry
		end
		entry.name, entry.icon, entry.startTime, entry.duration, entry.slot = name, icon, startTime, duration, slot
		entry.setPending = nil   -- the game itself says it is down: nothing left to confirm
		entry.durationKnown = type(duration) == "number" and duration > 0 or nil   -- read from the game: exact
		if type(spellID) == "number" and spellID ~= 0 then entry.spellID = spellID end
		if entry.spellID and duration and duration > 0 then learnedDurations()[entry.spellID] = duration end
	else
		self.shadowTotems[element] = nil
	end
end

-- How long a totem's record outlives its time: the game's own "slot emptied" update
-- comes a moment after the timer runs out (measured 0.3 s, Stoneclaw, 2026-09-27), and
-- that update is what retires the record and tells Expiring Alerts "expired". Dropping
-- the record at the timer instead left the update nothing to retire: no alert.
local SHADOW_EXPIRY_LINGER = 3

local function shadowLookup(self, element)
	local entry = self.shadowTotems[element]
	if entry and entry.setPending then
		-- a set summon's totem its slot update has not confirmed yet: keep showing
		-- the totem it replaces, so one the summon cannot place (no mana) never
		-- flashes up for the confirm window. A confirmed one shows at once.
		local prev = entry.setPrev
		if not prev or prev.startTime + prev.duration <= GetTime() then return false, nil, nil, nil, nil, nil end
		return true, prev.name, prev.startTime, prev.duration, prev.icon, prev.slot
	end
	if not entry then return false, nil, nil, nil, nil, nil end
	if entry.startTime + entry.duration <= GetTime() then
		-- time's up: shown as gone at once, but the record waits for the slot update
		-- (see SHADOW_EXPIRY_LINGER), and goes on its own if that never comes
		if entry.startTime + entry.duration + SHADOW_EXPIRY_LINGER <= GetTime() then self.shadowTotems[element] = nil end
		return false, nil, nil, nil, nil, nil
	end
	return true, entry.name, entry.startTime, entry.duration, entry.icon, entry.slot
end

-- A totem that just appeared in a slot without a cast of its own (Call of the
-- Elements drops several from one spell): record its drop here instead.
function ShamanPower:RecordTotemDropFromSlot(slot)
	if not TRACK_TOTEM_DROPS or type(slot) ~= "number" then return end
	local have, name, startTime, _, _, _, spellID = GetTotemInfo(slot)
	if not have or not name or name == "" or not startTime then return end
	if GetTime() - startTime > 1.5 then return end   -- not a fresh drop
	local element = slotTotemElement(self, name, spellID)
	if element then self:RecordTotemDrop(element) end
end

-- GetTotemInfo for the totem of an element, wherever the client put it.
-- Returns the GetTotemInfo tuple (haveTotem, name, startTime, duration, icon)
-- plus the slot it was found in. Falls back to the shadow model while the
-- API is secret.
-- GetElementTotemInfo is asked by every loop, several times a tick (pulse x3 at
-- 20 Hz, bars / opacity / overlays x4 at 10 Hz, range x4 ...), and on cast-order
-- clients each ask scans all four slots and re-syncs the shadow model. What it
-- answers only changes when a totem is placed, replaced, expires, dies or is
-- recalled - all PLAYER_TOTEM_UPDATE - or, under the secrets regime, when the
-- player casts. So the answer is kept per element until one of those bumps the
-- generation (plus the combat edges, where the regime changes), with two safety
-- nets: half a second at most, and a totem that has run out by the clock is read
-- again at once. Measured with /spperf: ~950 calls / 15 s while idle.
local totemInfoCache = {}
ShamanPower._totemInfoGen = 0
function ShamanPower:InvalidateTotemInfo()
	self._totemInfoGen = (self._totemInfoGen or 0) + 1
	self._totemDownAt = nil   -- AnyTotemDown asks again too
	self:WakeTotemSleepers()  -- and the loops asleep until a totem is down take a look
end

function ShamanPower:GetElementTotemInfo(element)
	local c = totemInfoCache[element]
	local now = GetTime()
	if c and c.gen == self._totemInfoGen and (now - c.at) < 0.5 then
		local s, d = c.s, c.d
		if not (c.h == true and type(s) == "number" and type(d) == "number" and d > 0 and (s + d) <= now) then
			return c.h, c.n, c.s, c.d, c.i, c.slot
		end
	end
	local h, n, s, d, i, slot = self:ReadElementTotemInfo(element)
	if not c then c = {}; totemInfoCache[element] = c end
	c.gen, c.at, c.h, c.n, c.s, c.d, c.i, c.slot = self._totemInfoGen, now, h, n, s, d, i, slot
	return h, n, s, d, i, slot
end

function ShamanPower:ReadElementTotemInfo(element)
	local fixedSlot = self.ElementToSlot[element]
	if not fixedSlot then return false end

	if totemsSecretNow() then
		return shadowLookup(self, element)
	end

	local haveTotem, totemName, startTime, duration, icon, _, spellID = GetTotemInfo(fixedSlot)
	if haveTotem and totemName and totemName ~= "" then
		totemName = self:CanonicalTotemName(totemName, spellID)
		local slotElement = slotTotemElement(self, totemName, spellID)
		if not slotElement or slotElement == element then
			shadowSyncFromAPI(self, element, haveTotem, totemName, startTime, duration, icon, fixedSlot, spellID)
			return haveTotem, totemName, startTime, duration, icon, fixedSlot
		end
		self.dynamicTotemSlots = true
	end
	if not self.dynamicTotemSlots then
		shadowSyncFromAPI(self, element, false)
		return false, nil, nil, nil, nil, fixedSlot
	end

	for slot = 1, 4 do
		if slot ~= fixedSlot then
			local h, n, s, d, i, _, id = GetTotemInfo(slot)
			if h and n and slotTotemElement(self, n, id) == element then
				n = self:CanonicalTotemName(n, id)
				shadowSyncFromAPI(self, element, h, n, s, d, i, slot, id)
				return h, n, s, d, i, slot
			end
		end
	end
	shadowSyncFromAPI(self, element, false)
	return false, nil, nil, nil, nil, nil
end

-- Check if a specific totem element is currently active
function ShamanPower:IsTotemActive(element)
	local haveTotem, _, startTime, duration = self:GetElementTotemInfo(element)
	return haveTotem and (startTime + duration > GetTime())
end

-- Find the totem index for a given element based on the active totem name
-- Used for Dynamic Mode to determine which totem is currently placed
ShamanPower.activeTotemIndexCache = { {}, {}, {}, {} }
function ShamanPower:GetActiveTotemIndex(element)
	local haveTotem, activeTotemName = self:GetElementTotemInfo(element)
	if issecretvalue(haveTotem) or issecretvalue(activeTotemName) then return nil end
	if not haveTotem or not activeTotemName then return nil end
	local cached = self.activeTotemIndexCache[element]
	local generation = SPCompat.SpellDataGeneration
	if cached and cached.name == activeTotemName and cached.generation == generation then return cached.index end
	if cached then
		cached.name, cached.generation, cached.index = activeTotemName, generation, nil
	end

	-- Search through all totems for this element to find a match
	local totemNames = self.TotemNames[element]
	if not totemNames then return nil end

	for totemIndex in pairs(totemNames) do
		if SPCompat.TotemNameMatches(activeTotemName, self:GetTotemSpell(element, totemIndex), totemNames[totemIndex]) then
			if cached then cached.index = totemIndex end
			return totemIndex
		end
	end

	return nil
end

-- The player's assignment for an element as the bar draws it (0 = none). A
-- flyout pick made during a fight waits in pendingAssignments until the fight
-- ends while the button already casts it, so it comes first. Drawing only:
-- secure attributes are set out of combat, from the saved table.
function ShamanPower:AssignedIndex(element)
	local p = self.pendingAssignments
	local v = p and p[element]
	if v then return v end
	local a = ShamanPower_Assignments and self.player and ShamanPower_Assignments[self.player]
	return (a and a[element]) or 0
end

-- Get status of all assigned totems: returns active count, total assigned
function ShamanPower:GetTotemStatus()
	if not ShamanPower_Assignments[self.player] and not self.pendingAssignments then return 0, 0 end

	local activeCount = 0
	local assignedCount = 0

	for element = 1, 4 do
		local totemIndex = self:AssignedIndex(element)   -- a pick made in this fight counts already
		if totemIndex and totemIndex > 0 then
			assignedCount = assignedCount + 1
			if self:IsTotemActive(element) then
				activeCount = activeCount + 1
			end
		end
	end

	return activeCount, assignedCount
end

-- Does a dropped totem become the assignment? Dynamic mode always; Grid style
-- too unless "Left-Click Also Assigns" is off (every totem is on screen there,
-- so the one you click is the one you mean).
function ShamanPower:DropSetsAssignment()
	local o = self.opt
	if not o then return false end
	-- Grid first: it can sit on top of a Dynamic setup (dynamicTotemMode stays set
	-- underneath), and its own "Left-Click Also Assigns" toggle must win there.
	if o.gridStyle == true and self.GridActive and self:GridActive() then return o.gridDropAssigns ~= false end
	return o.dynamicTotemMode and true or false
end

-- Update totem assignments and icons for Dynamic Mode
-- When a totem is placed, it becomes the new assignment for that element
function ShamanPower:UpdateDynamicTotemIcons()
	if not self:DropSetsAssignment() then return end

	local playerName = self.player
	if not ShamanPower_Assignments[playerName] then
		ShamanPower_Assignments[playerName] = {}
	end
	local assignments = ShamanPower_Assignments[playerName]

	local needsFullUpdate = false

	for element = 1, 4 do
		-- Skip Air (element 4) when totem twisting is enabled - twist manages Air specially
		if element == 4 and self.opt.enableTotemTwisting then
			-- Don't update Air assignment or icon in dynamic mode when twisting
		else
			local activeIndex = self:GetActiveTotemIndex(element)

			-- If there's an active totem and it's different from the assignment, update it
			if activeIndex and activeIndex ~= assignments[element] then
				assignments[element] = activeIndex
				needsFullUpdate = true
			end

			-- Update the icon regardless (a flyout pick made in this fight wins: the
			-- button casts it and it is saved when the fight ends)
			local totemIndex = self:AssignedIndex(element)
			local icon = self.ElementIcons[element]  -- Default
			if totemIndex and totemIndex > 0 then
				icon = self:GetTotemIcon(element, totemIndex)
			end

			-- Update the XML button icon
			local iconTexture = _G["ShamanPowerAutoTotem" .. element .. "Icon"]
			if iconTexture then
				iconTexture:SetTexture(icon)
			end

			-- Update the Lua button icon (if exists)
			local btn = self.totemButtons and self.totemButtons[element]
			if btn and btn.icon then
				btn.icon:SetTexture(icon)
			end
			self:ShowEmptySlotArt(element, totemIndex == 0)
		end
	end

	-- If assignments changed and we're not in combat, do a full update
	if needsFullUpdate and not InCombatLockdown() then
		self:UpdateMiniTotemBar()
		self:UpdateTotemButtons()
		self:UpdateDropAllButton()
	end
end

-- ============================================================================
-- Totem Pulse Overlay (visual pulse for totems like Tremor)
-- ============================================================================

ShamanPower.pulseOverlays = {}

-- ----------------------------------------------------------------------------
-- Pulse visuals run by the engine. A pulse object (a CreatePulseOverlay
-- container, a pop-out's container, or an active-totem overlay) has a wipe bar
-- and three glow textures. Their motion over one pulse cycle is fixed by the
-- totem's drop time and interval, so it is handed to AnimationGroups: the wipe
-- grows with a Scale animation and the glow flash fades with Alpha animations,
-- started once per cycle. The 20 Hz pulse pass only notices a new cycle (or a
-- change of state) and restarts them; between those it draws nothing. The
-- countdown text is set only when the shown tenths change, from cached strings.
-- ----------------------------------------------------------------------------
local PULSE_FLASH = 0.15   -- share of the cycle the glow flash lasts

local function setScaleAnim(a, fx, fy, tx, ty)
	if a.SetScaleFrom then a:SetScaleFrom(fx, fy); a:SetScaleTo(tx, ty)
	else a:SetFromScale(fx, fy); a:SetToScale(tx, ty) end
end

-- "1.4" strings without per-frame garbage
local pulseTenthsCache = {}
local function PulseTenths(t)
	local k = math.floor(t * 10 + 0.5)
	if k < 0 then k = 0 end
	local s = pulseTenthsCache[k]
	if not s then s = string.format("%.1f", k / 10); pulseTenthsCache[k] = s end
	return s
end

local PULSE_TEXT_KEYS = {
	inside_top = "barTimeTextTop", inside_bottom = "barTimeTextBottom",
	above = "aboveTimeText", below = "belowTimeText", on_icon = "iconTimeText",
}

function ShamanPower:PulseVisualHideText(o)
	if not o or o._tOpt == nil then return end
	for _, key in pairs(PULSE_TEXT_KEYS) do
		local fs = o[key]
		if fs then fs:Hide() end
	end
	o._tOpt, o._tStr, o._tSize = nil, nil, nil
end

-- Show the countdown in the option's text; only touches the string when the
-- shown tenths change (at most ten times a second).
function ShamanPower:PulseVisualText(o, remain, opt)
	if not o then return end
	if not opt or opt == "none" then self:PulseVisualHideText(o) return end
	if o._tOpt ~= opt then
		self:PulseVisualHideText(o)
		o._tOpt = opt
	end
	local key = PULSE_TEXT_KEYS[opt]
	local fs = key and o[key]
	if not fs then return end
	local size = self.opt.pulseTextSize or 8
	if o._tSize ~= size then self:SetSPFont(fs, "timers", size, "OUTLINE"); o._tSize = size end
	local str = PulseTenths(remain)
	if o._tStr ~= str then fs:SetText(str); o._tStr = str end
	if not fs:IsShown() then fs:Show() end
end

local function stopWipe(o)
	if o._wipeAG then o._wipeAG:Stop() end
	if o.wipe then o.wipe:Hide() end
end

local function stopGlows(o, hide)
	local glows = o.glows
	if not glows then return end
	for i, g in ipairs(glows) do
		local ag = o._glowAG and o._glowAG[i]
		if ag then ag:Stop() end
		g:SetAlpha(0)
		if hide then g:Hide() end
	end
end

-- Everything off (idempotent: a pass that finds it already off does nothing).
function ShamanPower:PulseVisualStop(o)
	if not o or o._pState == "off" then return end
	o._pState, o._pIdx = "off", nil
	stopWipe(o)
	stopGlows(o, true)
	self:PulseVisualHideText(o)
end

-- Keep the object's wipe and glow in step with a totem dropped at `start` that
-- pulses every `interval` seconds. Restarts the animations on a new cycle, on
-- a new totem, or when something else hid the wipe; otherwise returns at once.
-- Returns the totem's age.
function ShamanPower:PulseVisualSync(o, start, interval, now)
	local age = now - start
	if age < 0 then age = 0 end
	-- Animations do not advance on a hidden frame (Hide Out of Combat, a hidden
	-- host): one started or left running there would resume from a stale point
	-- when the bar shows. Leave it alone until the frame is visible; the first
	-- pass after that starts it from the right place.
	local host = o.button or o.frame
	if host and not host:IsVisible() then
		o._pState = nil
		return age
	end
	local idx = math.floor(age / interval)
	local wipe = o.wipe
	-- Only Show Pulse Bars / Pulse Flash for Specific Totems: set by the caller (PulsePartsOff)
	local noBar = o._noBar
	local mask = (noBar and 1 or 0) + (o._noFlash and 2 or 0)
	local wipeOk = o.isDisabled or noBar or not wipe or (wipe:IsShown() and o._wipeAG ~= nil and o._wipeAG:IsPlaying())
	if o._pState == "on" and o._pIdx == idx and o._pStart == start and o._pInt == interval and o._pMask == mask and wipeOk then
		return age
	end
	o._pState, o._pIdx, o._pStart, o._pInt, o._pMask = "on", idx, start, interval, mask
	local phase = (age - idx * interval) / interval

	-- the wipe: from its size now to full over the rest of the cycle
	if wipe then
		if o.isDisabled or noBar then
			stopWipe(o)
		else
			local ag = o._wipeAG
			if not ag then
				ag = wipe:CreateAnimationGroup()
				o._wipeScale = ag:CreateAnimation("Scale")
				ag:SetScript("OnFinished", function() wipe:Hide() end)   -- end of the cycle
				o._wipeAG = ag
			end
			ag:Stop()
			local full = math.max(1, o.maxSize or 22)
			local cur = math.max(1, full * phase)
			local sc = o._wipeScale
			if o.isVertical then
				wipe:SetHeight(cur)
				sc:SetOrigin(o.wipeGrowsDown and "TOP" or "BOTTOM", 0, 0)
				setScaleAnim(sc, 1, 1, 1, full / cur)
			else
				wipe:SetWidth(cur)
				sc:SetOrigin("LEFT", 0, 0)
				setScaleAnim(sc, 1, 1, full / cur, 1)
			end
			sc:SetDuration(math.max(0.01, (1 - phase) * interval))
			wipe:SetAlpha(self.opt.pulseBarOpacity or 1)   -- Pulse Bar Opacity (Duration Bars)
			wipe:Show()
			ag:Play()
		end
	end

	-- the glow flash: bright at the pulse, gone after PULSE_FLASH of the cycle;
	-- Pulse Flash Opacity (Duration Bars) scales it, and 0% leaves it out
	local glows = o.glows
	local flash = self.opt.pulseFlashOpacity or 1
	if glows then
		if phase < PULSE_FLASH and flash > 0 and not o._noFlash then
			local k = 1 - phase / PULSE_FLASH
			local dur = math.max(0.01, (PULSE_FLASH - phase) * interval)
			-- Pulse Flash Color (Duration Bars); the green it always had by default
			local fc = self.opt.pulseFlashColor
			local fr, fg, fb = 0.4, 1, 0.4
			if fc then fr, fg, fb = fc.r or 0.4, fc.g or 1, fc.b or 0.4 end
			if not o._glowAG then o._glowAG = {} end
			for i, g in ipairs(glows) do
				local ag = o._glowAG[i]
				if not ag then
					ag = g:CreateAnimationGroup()
					ag.fade = ag:CreateAnimation("Alpha")
					if ag.SetToFinalAlpha then ag:SetToFinalAlpha(true) end
					ag:SetScript("OnFinished", function() g:SetAlpha(0) end)
					o._glowAG[i] = ag
				end
				ag:Stop()
				local a0 = 0.9 * (1.1 - i * 0.2) * k * flash   -- inner glows brighter, as before
				g:SetVertexColor(fr, fg, fb)
				ag.fade:SetFromAlpha(a0); ag.fade:SetToAlpha(0); ag.fade:SetDuration(dur)
				g:SetAlpha(a0); g:Show()
				ag:Play()
			end
		else
			stopGlows(o, false)
		end
	end
	return age
end

function ShamanPower:CreatePulseOverlay(button)
	if not button then return nil end

	local container = { glows = {}, button = button }

	-- Create multiple layered glows for more intensity
	for i = 1, 3 do
		local glow = button:CreateTexture(nil, "OVERLAY", nil, 7)
		local offset = 6 + (i * 4)  -- 10, 14, 18 pixel offsets
		glow:SetPoint("TOPLEFT", button, "TOPLEFT", -offset, offset)
		glow:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", offset, -offset)
		glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
		if ShamanPower.ShapeGlow then ShamanPower:ShapeGlow(glow, "border") end   -- Glow Shape
		glow:SetBlendMode("ADD")
		glow:SetVertexColor(0.4, 1, 0.4)  -- Bright green
		glow:SetAlpha(0)
		container.glows[i] = glow
	end

	-- Create wipe frame for pulse countdown
	local wipeFrame = CreateFrame("Frame", nil, button)
	wipeFrame:SetFrameLevel(button:GetFrameLevel() + 1)

	-- White overlay texture
	local wipe = wipeFrame:CreateTexture(nil, "OVERLAY")
	ShamanPower:SetSPBarColor(wipe, "pulse", 1, 1, 1, 0.7)  -- White for visibility
	wipe:Hide()

	-- Time text inside the bar (top)
	local barTimeTextTop = wipeFrame:CreateFontString(nil, "OVERLAY")
	ShamanPower:SetSPFont(barTimeTextTop, "timers", 9, "OUTLINE")
	barTimeTextTop:SetPoint("TOP", wipeFrame, "TOP", 0, -1)
	barTimeTextTop:SetTextColor(1, 1, 1)  -- White text
	barTimeTextTop:Hide()
	container.barTimeTextTop = barTimeTextTop

	-- Time text inside the bar (bottom)
	local barTimeTextBottom = wipeFrame:CreateFontString(nil, "OVERLAY")
	ShamanPower:SetSPFont(barTimeTextBottom, "timers", 9, "OUTLINE")
	barTimeTextBottom:SetPoint("BOTTOM", wipeFrame, "BOTTOM", 0, 1)
	barTimeTextBottom:SetTextColor(1, 1, 1)  -- White text
	barTimeTextBottom:Hide()
	container.barTimeTextBottom = barTimeTextBottom

	-- Time text above the bar
	local aboveTimeText = wipeFrame:CreateFontString(nil, "OVERLAY")
	ShamanPower:SetSPFont(aboveTimeText, "timers", 9, "OUTLINE")
	aboveTimeText:SetPoint("BOTTOM", wipeFrame, "TOP", 0, 1)
	aboveTimeText:SetTextColor(1, 1, 1)  -- White text
	aboveTimeText:Hide()
	container.aboveTimeText = aboveTimeText

	-- Time text below the bar
	local belowTimeText = wipeFrame:CreateFontString(nil, "OVERLAY")
	ShamanPower:SetSPFont(belowTimeText, "timers", 9, "OUTLINE")
	belowTimeText:SetPoint("TOP", wipeFrame, "BOTTOM", 0, -1)
	belowTimeText:SetTextColor(1, 1, 1)  -- White text
	belowTimeText:Hide()
	container.belowTimeText = belowTimeText

	-- Time text on the icon
	local iconTimeText = button:CreateFontString(nil, "OVERLAY")
	ShamanPower:SetSPFont(iconTimeText, "timers", 10, "OUTLINE")
	iconTimeText:SetPoint("CENTER", button, "CENTER", 0, 0)
	iconTimeText:SetTextColor(1, 1, 1)  -- White text
	iconTimeText:Hide()
	container.iconTimeText = iconTimeText

	container.wipeFrame = wipeFrame
	container.wipe = wipe
	container.buttonWidth = button:GetWidth() - 4
	container.buttonHeight = button:GetHeight() - 4

	-- Position the wipe bar based on current option
	self:PositionPulseWipe(container)

	container.SetAlpha = function(self, alpha)
		for i, glow in ipairs(self.glows) do
			glow:SetAlpha(alpha * (1.1 - i * 0.2))  -- Inner glows brighter
		end
	end

	container.Show = function(self)
		for _, glow in ipairs(self.glows) do glow:Show() end
	end

	-- (the next pulse pass restarts the animations after any of these)
	container.Hide = function(self)
		stopGlows(self, true)
		self._pState = nil
	end

	container.HideWipe = function(self)
		stopWipe(self)
		self._pState = nil
	end

	-- Draw the wipe by hand (0 = just pulsed/no coverage, 1 = about to pulse/full
	-- coverage). The pulse pass uses PulseVisualSync; this stays for other callers.
	container.UpdateWipe = function(self, progress)
		if self._wipeAG then self._wipeAG:Stop() end
		self._pState = nil
		if self.wipe then
			-- Don't show if pulse bar is disabled
			if self.isDisabled then
				self.wipe:Hide()
				return
			end
			if progress > 0 and progress < 1 then
				local size = self.maxSize * progress
				if self.isVertical then
					self.wipe:SetHeight(math.max(1, size))
				else
					self.wipe:SetWidth(math.max(1, size))
				end
				self.wipe:Show()
			else
				self.wipe:Hide()
			end
		end
	end

	-- Update the time display (only when the shown tenths change)
	container.UpdateTime = function(self, timeRemaining, displayOption)
		ShamanPower:PulseVisualText(self, timeRemaining, displayOption)
	end

	-- Hide time displays
	container.HideTime = function(self)
		ShamanPower:PulseVisualHideText(self)
	end

	return container
end

-- Position the pulse wipe bar based on the pulseBarPosition option
function ShamanPower:PositionPulseWipe(container)
	if not container or not container.wipe or not container.button then return end

	local button = container.button
	local wipeFrame = container.wipeFrame
	local wipe = container.wipe
	local position = self.opt.pulseBarPosition or "on_icon"
	local barSize = self.opt.pulseBarSize or 4  -- Size of the external bar
	local padT, padB, padL, padR = self:GetPartyDotPads()
	-- and out past the flyout tab on its side while that shows (see FollowFlyoutArrows)
	local aT, aB, aL, aR = self:FlyoutArrowPads(button)
	padT, padB, padL, padR = padT + aT, padB + aB, padL + aL, padR + aR

	-- a running wipe animation belongs to the old placement: stop it, and let the
	-- next pulse pass start again from the new one
	if container._wipeAG then container._wipeAG:Stop() end
	container._pState = nil
	container.wipeGrowsDown = (position == "on_icon" or position == "below_vert")   -- anchored at the top

	wipe:ClearAllPoints()
	wipeFrame:ClearAllPoints()

	-- Handle "none" position - hide the pulse bar
	if position == "none" then
		wipe:Hide()
		wipeFrame:Hide()
		container.isDisabled = true
		return
	end

	container.isDisabled = false
	wipeFrame:Show()   -- hidden by "none"; every other position shows it again

	if position == "on_icon" then
		-- Original behavior: wipe slides down inside the icon
		wipeFrame:SetAllPoints(button)
		wipe:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
		wipe:SetPoint("TOPRIGHT", button, "TOPRIGHT", -2, -2)
		wipe:SetHeight(1)
		container.isVertical = true
		container.isOnIcon = true
		container.maxSize = container.buttonHeight
	elseif position == "above" then
		-- Horizontal bar above the icon, fills left to right
		wipeFrame:SetPoint("BOTTOMLEFT", button, "TOPLEFT", 0, 1 + padT)
		wipeFrame:SetSize(button:GetWidth(), barSize)
		wipe:SetPoint("LEFT", wipeFrame, "LEFT", 0, 0)
		wipe:SetHeight(barSize)
		wipe:SetWidth(1)
		container.isVertical = false
		container.isOnIcon = false
		container.maxSize = button:GetWidth()
	elseif position == "above_vert" then
		-- Vertical bar above the icon, fills bottom to top (same height as icon)
		wipeFrame:SetPoint("BOTTOM", button, "TOP", 0, 1 + padT)
		wipeFrame:SetSize(barSize, button:GetHeight())
		wipe:SetPoint("BOTTOMLEFT", wipeFrame, "BOTTOMLEFT", 0, 0)
		wipe:SetWidth(barSize)
		wipe:SetHeight(1)
		container.isVertical = true
		container.isOnIcon = false
		container.maxSize = button:GetHeight()
	elseif position == "below" then
		-- Horizontal bar below the icon, fills left to right
		wipeFrame:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -(1 + padB))
		wipeFrame:SetSize(button:GetWidth(), barSize)
		wipe:SetPoint("LEFT", wipeFrame, "LEFT", 0, 0)
		wipe:SetHeight(barSize)
		wipe:SetWidth(1)
		container.isVertical = false
		container.isOnIcon = false
		container.maxSize = button:GetWidth()
	elseif position == "below_vert" then
		-- Vertical bar below the icon, fills top to bottom (same height as icon)
		wipeFrame:SetPoint("TOP", button, "BOTTOM", 0, -(1 + padB))
		wipeFrame:SetSize(barSize, button:GetHeight())
		wipe:SetPoint("TOPLEFT", wipeFrame, "TOPLEFT", 0, 0)
		wipe:SetWidth(barSize)
		wipe:SetHeight(1)
		container.isVertical = true
		container.isOnIcon = false
		container.maxSize = button:GetHeight()
	elseif position == "left" then
		-- Vertical bar to the left, fills bottom to top
		wipeFrame:SetPoint("TOPRIGHT", button, "TOPLEFT", -(1 + padL), 0)
		wipeFrame:SetSize(barSize, button:GetHeight())
		wipe:SetPoint("BOTTOMLEFT", wipeFrame, "BOTTOMLEFT", 0, 0)
		wipe:SetWidth(barSize)
		wipe:SetHeight(1)
		container.isVertical = true
		container.isOnIcon = false
		container.maxSize = button:GetHeight()
	elseif position == "right" then
		-- Vertical bar to the right, fills bottom to top
		wipeFrame:SetPoint("TOPLEFT", button, "TOPRIGHT", 1 + padR, 0)
		wipeFrame:SetSize(barSize, button:GetHeight())
		wipe:SetPoint("BOTTOMLEFT", wipeFrame, "BOTTOMLEFT", 0, 0)
		wipe:SetWidth(barSize)
		wipe:SetHeight(1)
		container.isVertical = true
		container.isOnIcon = false
		container.maxSize = button:GetHeight()
	end
end

-- Update all pulse bar positions when option changes
function ShamanPower:UpdatePulseBarPositions()
	-- Enable/disable pulse subsystem based on whether pulse bar is enabled
	local pulseEnabled = (self.opt.pulseBarPosition ~= "none")
	if pulseEnabled then
		self:EnableUpdateSubsystem("pulse")
	else
		self:DisableUpdateSubsystem("pulse")
	end

	for element, container in pairs(self.pulseOverlays) do
		if container then
			self:PositionPulseWipe(container)
		end
	end
	-- Also update active totem overlay pulse positions
	if self.activeTotemOverlays then
		for element, overlay in pairs(self.activeTotemOverlays) do
			if overlay and overlay.frame then
				self:PositionOverlayPulseWipe(overlay, overlay.frame)
			end
		end
	end
	-- the overlay leaves room past a flyout tab for its own pulse bar and dots:
	-- place it again for the new ones (Blizzard's bar has no tabs of ours)
	if not (self.UsingBlizzardTotemBar and self:UsingBlizzardTotemBar()) then self:PositionActiveOverlays() end
end

-- Position the pulse wipe bar for active totem overlays
function ShamanPower:PositionOverlayPulseWipe(overlay, frame)
	if not overlay or not overlay.wipe or not frame then return end

	local wipeFrame = overlay.wipeFrame
	local wipe = overlay.wipe
	local position = self.opt.pulseBarPosition or "on_icon"
	local barSize = self.opt.pulseBarSize or 4  -- Size of the external bar

	if overlay._wipeAG then overlay._wipeAG:Stop() end
	overlay._pState = nil
	overlay.wipeGrowsDown = (position == "on_icon" or position == "below_vert")   -- anchored at the top

	wipe:ClearAllPoints()
	if wipeFrame then wipeFrame:ClearAllPoints() end

	-- Handle "none" position - hide the pulse bar
	if position == "none" then
		wipe:Hide()
		if wipeFrame then wipeFrame:Hide() end
		overlay.isDisabled = true
		return
	end

	overlay.isDisabled = false
	if wipeFrame then wipeFrame:Show() end   -- hidden by "none"; every other position shows it again

	if position == "on_icon" then
		-- Original behavior: wipe slides down inside the icon
		if wipeFrame then wipeFrame:SetAllPoints(frame) end
		wipe:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -2)
		wipe:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
		wipe:SetHeight(1)
		overlay.isVertical = true
		overlay.isOnIcon = true
		overlay.maxSize = overlay.buttonHeight or (frame:GetHeight() - 4)
	elseif position == "above" then
		-- Horizontal bar above the frame, fills left to right
		if wipeFrame then
			wipeFrame:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 1)
			wipeFrame:SetSize(frame:GetWidth(), barSize)
		end
		wipe:SetPoint("LEFT", wipeFrame or frame, "LEFT", 0, 0)
		wipe:SetHeight(barSize)
		wipe:SetWidth(1)
		overlay.isVertical = false
		overlay.isOnIcon = false
		overlay.maxSize = frame:GetWidth()
	elseif position == "above_vert" then
		-- Vertical bar above the frame, fills bottom to top (same height as icon)
		if wipeFrame then
			wipeFrame:SetPoint("BOTTOM", frame, "TOP", 0, 1)
			wipeFrame:SetSize(barSize, frame:GetHeight())
		end
		wipe:SetPoint("BOTTOMLEFT", wipeFrame or frame, "BOTTOMLEFT", 0, 0)
		wipe:SetWidth(barSize)
		wipe:SetHeight(1)
		overlay.isVertical = true
		overlay.isOnIcon = false
		overlay.maxSize = frame:GetHeight()
	elseif position == "below" then
		-- Horizontal bar below the frame, fills left to right
		if wipeFrame then
			wipeFrame:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -1)
			wipeFrame:SetSize(frame:GetWidth(), barSize)
		end
		wipe:SetPoint("LEFT", wipeFrame or frame, "LEFT", 0, 0)
		wipe:SetHeight(barSize)
		wipe:SetWidth(1)
		overlay.isVertical = false
		overlay.isOnIcon = false
		overlay.maxSize = frame:GetWidth()
	elseif position == "below_vert" then
		-- Vertical bar below the frame, fills top to bottom (same height as icon)
		if wipeFrame then
			wipeFrame:SetPoint("TOP", frame, "BOTTOM", 0, -1)
			wipeFrame:SetSize(barSize, frame:GetHeight())
		end
		wipe:SetPoint("TOPLEFT", wipeFrame or frame, "TOPLEFT", 0, 0)
		wipe:SetWidth(barSize)
		wipe:SetHeight(1)
		overlay.isVertical = true
		overlay.isOnIcon = false
		overlay.maxSize = frame:GetHeight()
	elseif position == "left" then
		-- Vertical bar to the left, fills bottom to top
		if wipeFrame then
			wipeFrame:SetPoint("TOPRIGHT", frame, "TOPLEFT", -1, 0)
			wipeFrame:SetSize(barSize, frame:GetHeight())
		end
		wipe:SetPoint("BOTTOMLEFT", wipeFrame or frame, "BOTTOMLEFT", 0, 0)
		wipe:SetWidth(barSize)
		wipe:SetHeight(1)
		overlay.isVertical = true
		overlay.isOnIcon = false
		overlay.maxSize = frame:GetHeight()
	elseif position == "right" then
		-- Vertical bar to the right, fills bottom to top
		if wipeFrame then
			wipeFrame:SetPoint("TOPLEFT", frame, "TOPRIGHT", 1, 0)
			wipeFrame:SetSize(barSize, frame:GetHeight())
		end
		wipe:SetPoint("BOTTOMLEFT", wipeFrame or frame, "BOTTOMLEFT", 0, 0)
		wipe:SetWidth(barSize)
		wipe:SetHeight(1)
		overlay.isVertical = true
		overlay.isOnIcon = false
		overlay.maxSize = frame:GetHeight()
	end
end

-- Pulsing totem data: totemName pattern -> { element, interval }. Intervals are the
-- totem passive's period in the client's spell data (SpellEffect, periodic trigger).
ShamanPower.PulsingTotems = {
	-- Earth totems
	["Tremor"] = { element = 1, spellID = 8143, interval = (SPCompat.FOREVER) and 4 or 3 },   -- WoW: Forever pulses every 4 s (Tremor Totem Passive 8145)
	["Earthbind"] = { element = 1, spellID = 2484, interval = 3 },
	["Stoneclaw"] = { element = 1, spellID = 5730, interval = 2 },   -- its taunt (Stoneclaw Totem Passive, every 2 s on both clients)
	-- Fire totems
	["Magma"] = { element = 2, spellID = 8190, interval = 2 },
	-- Water totems
	["Mana Tide"] = { element = 3, spellID = 16190, interval = 3 },
	["Mana Spring"] = { element = 3, spellID = 5675, interval = 2 },
	["Healing Stream"] = { element = 3, spellID = 5394, interval = 2 },
	["Poison Cleansing"] = { element = 3, spellID = 8166, interval = 5 },
	["Disease Cleansing"] = { element = 3, spellID = 8170, interval = 5 },
}

-- Only Show Pulse Bars / Pulse Flash for Specific Totems (Duration Bars): two
-- lists, one per part. Returns barOff (the pulse bar and its pulse time) and
-- flashOff for a PulsingTotems entry.
function ShamanPower:PulsePartsOff(data)
	local o, key = self.opt, data and data.key
	if not key then return false, false end
	local barOff = (o.pulseOnlySome and o.pulseTotemsOff and o.pulseTotemsOff[key]) and true or false
	local flashOff = (o.pulseFlashOnlySome and o.pulseFlashTotemsOff and o.pulseFlashTotemsOff[key]) and true or false
	return barOff, flashOff
end

local pulsingByName = {}   -- [element .. name] = PulsingTotems entry, or false
function ShamanPower:GetActivePulsingTotem(element)
	local haveTotem, totemName, startTime, duration = self:GetElementTotemInfo(element)
	if haveTotem and totemName then
		local key = element .. totemName
		local data = pulsingByName[key]
		if data == nil then
			data = false
			for pattern, entry in pairs(self.PulsingTotems) do
				if entry.element == element and SPCompat.TotemNameMatches(totemName, entry.spellID, pattern) then
					data = entry; entry.key = pattern break
				end
			end
			pulsingByName[key] = data
		end
		-- Only Show Pulse Bars / Pulse Flash for Specific Totems (Duration Bars): a
		-- totem turned off in both lists does not pulse on the bar at all; one list
		-- alone is handled per part where it is drawn
		if data then
			local barOff, flashOff = self:PulsePartsOff(data)
			if barOff and flashOff then return nil, nil, nil end
			return data, startTime, duration
		end
	end
	return nil, nil, nil
end

function ShamanPower:SetupPulseOverlays()
	-- Create pulse overlays for Earth (1), Fire (2), and Water (3) totem buttons
	local elements = {1, 2, 3}  -- Earth, Fire, and Water can have pulsing totems
	for _, element in ipairs(elements) do
		local button = self.totemButtons[element]
		if button and not self.pulseOverlays[element] then
			self.pulseOverlays[element] = self:CreatePulseOverlay(button)
			self:ThemePaintPulse(self.pulseOverlays[element], element)   -- tb.pulse (General > Themes); nothing on Standard
		end
	end

	-- Register pulse tracking with consolidated update system (20fps)
	-- Only register once, but only enable if feature is on
	if not self.updateSystem.subsystems["pulse"] then
		local pulseState = {}
		local function pulsePass()
			-- Earth, Fire, Water (elements 1-3) can have pulsing totems
			-- which totem pulses (and since when) only changes with the totems: look it up
			-- when they change or twice a second, not twenty times a second
			local gen, now = ShamanPower._totemInfoGen, GetTime()
			if pulseState.gen ~= gen or (now - (pulseState.at or 0)) > 0.5 then
				pulseState.gen, pulseState.at = gen, now
				pulseState.data, pulseState.start = pulseState.data or {}, pulseState.start or {}
				for element = 1, 3 do
					pulseState.data[element], pulseState.start[element] = ShamanPower:GetActivePulsingTotem(element)
				end
			end
			for element = 1, 3 do
				local data, start = pulseState.data[element], pulseState.start[element]
				-- Only an element whose totem pulses needs 20 passes a second; one that
				-- just stopped gets a single pass to clear its glow. (With Stoneskin and
				-- Searing down, nothing pulses and this loop now does no drawing at all.)
				if data or pulseState[element] then
					ShamanPower:UpdatePulseGlow(element, data, start)
					ShamanPower:UpdatePoppedOutPulse(element, data, start)
				end
				pulseState[element] = data and true or nil
			end
		end
		self:RegisterUpdateSubsystem("pulse", 0.05, function()
			spWhileTotemsDown(pulseState, pulsePass)   -- nothing pulses with no totem down
		end)
	end
	-- Only enable if pulse bar is not disabled (pulseBarPosition != "none")
	local pulseEnabled = (self.opt.pulseBarPosition ~= "none")
	if pulseEnabled then
		self:EnableUpdateSubsystem("pulse")
	else
		self:DisableUpdateSubsystem("pulse")
	end
end

-- lower-case totem names, cached (the pulse pass compares them 20 times a second)
local pulseLower = {}
local function lowerName(name)
	local l = pulseLower[name]
	if not l then l = name:lower(); pulseLower[name] = l end
	return l
end
local NO_OVERLAYS = {}

-- Update pulse effects on popped-out single totems
function ShamanPower:UpdatePoppedOutPulse(element, totemData, startTime)
	-- Get the active totem name to match against pop-outs
	local haveTotem, activeTotemName = self:GetElementTotemInfo(element)

	-- Iterate through all popped-out overlays for this element
	for key, overlay in pairs(self.poppedOutOverlays or NO_OVERLAYS) do
		if overlay.element == element then
			local frame = self.poppedOutFrames[key]
			local matchesTotem = false

			-- Check if this pop-out's totem matches the active totem
			if haveTotem and activeTotemName and overlay.spellName then
				-- Simple case-insensitive substring match
				local activeLower = lowerName(activeTotemName)
				local spellLower = lowerName(overlay.spellName)
				if activeLower:find(spellLower, 1, true) or spellLower:find(activeLower, 1, true) then
					matchesTotem = true
				end
			end

			if matchesTotem and totemData and startTime then
				-- This pop-out matches the active pulsing totem: the engine animates
				-- the wipe and the glow flash; this only restarts them each cycle
				local pulseInterval = totemData.interval
				local barOff
				barOff, overlay._noFlash = self:PulsePartsOff(totemData)
				overlay._noBar = barOff
				local totemAge = self:PulseVisualSync(overlay, startTime, pulseInterval, GetTime())
				self:PulseVisualText(overlay, pulseInterval - (totemAge % pulseInterval), (not barOff and self.opt.pulseTimeDisplay) or "none")

				-- Show active border on the frame
				if frame and frame.activeBorder then
					frame.activeBorder:Show()
				end
			else
				-- No match or no active pulsing totem - hide pulse
				self:PulseVisualStop(overlay)

				-- Check if this pop-out's totem is active (but not pulsing)
				if matchesTotem and haveTotem then
					-- Totem is active but not pulsing - just show active border
					if frame and frame.activeBorder then
						frame.activeBorder:Show()
					end
				else
					-- Hide active border
					if frame and frame.activeBorder then
						frame.activeBorder:Hide()
					end
				end
			end
		end
	end
end

function ShamanPower:UpdatePulseGlow(element, totemData, startTime)
	local glow = self.pulseOverlays[element]
	if not glow then return end
	local nativeBar = self.UsingBlizzardTotemBar and self:UsingBlizzardTotemBar()
	local activeOverlay = self.activeTotemOverlays and self.activeTotemOverlays[element]
	-- Totem Rows with the main bar hidden: the pulse is the row's (ShamanPowerRows)
	local rowsCarry = self.RowsCarryBar and self:RowsCarryBar()

	-- Compact style paints the pulse inside the line
	if self:CompactActive() and not rowsCarry then
		self:PulseVisualStop(glow)
		return
	end

	-- Check if active overlay is showing for this element
	-- In TotemTimers style mode (activeTotemAsMain), always use main button even when overlay is "active"
	local useOverlay = not nativeBar and not rowsCarry and activeOverlay and activeOverlay.isActive and not self.opt.activeTotemAsMain

	-- Check if the active totem is popped out - if so, don't show pulse on main bar
	local totemIsPoppedOut = false
	if totemData and not nativeBar then
		local haveTotem, activeTotemName = self:GetElementTotemInfo(element)
		if haveTotem and activeTotemName then
			-- Check if any popped-out single totem matches
			for key, overlay in pairs(self.poppedOutOverlays or NO_OVERLAYS) do
				if overlay.element == element and overlay.spellName then
					local ok1, result1 = pcall(string.find, activeTotemName, overlay.spellName, 1, true)
					local ok2, result2 = pcall(string.find, overlay.spellName, activeTotemName, 1, true)
					if (ok1 and result1) or (ok2 and result2) then
						totemIsPoppedOut = true
						break
					end
				end
			end
		end
	end

	-- If totem is popped out, hide main bar pulse and let UpdatePoppedOutPulse handle it
	if totemIsPoppedOut then
		self:PulseVisualStop(glow)
		return
	end

	if totemData and startTime then
		-- One of the two shows the pulse (the active-totem overlay when it is up,
		-- otherwise the button); the other is kept off. The engine animates the
		-- wipe and the glow flash; this only restarts them on each new cycle.
		local target = useOverlay and activeOverlay or glow
		local other = (target == glow) and activeOverlay or glow
		if other then self:PulseVisualStop(other) end
		local interval = totemData.interval
		local barOff
		barOff, target._noFlash = self:PulsePartsOff(totemData)
		target._noBar = barOff
		local totemAge = self:PulseVisualSync(target, startTime, interval, GetTime())
		self:PulseVisualText(target, interval - (totemAge % interval), (not barOff and self.opt.pulseTimeDisplay) or "none")
	else
		self:PulseVisualStop(glow)
		if activeOverlay then self:PulseVisualStop(activeOverlay) end
	end
end

-- ============================================================================
-- Totem Twisting Helpers
-- ============================================================================

-- Hardcoded icon paths for twist totem options (avoids GetSpellInfo flicker in per-frame updates)
ShamanPower.TwistTotemIcons = {
	[2] = "Interface\\Icons\\Spell_Nature_InvisibilityTotem",     -- Grace of Air
	[3] = "Interface\\Icons\\Spell_Nature_SlowingTotem",          -- Wrath of Air
	[4] = "Interface\\Icons\\Spell_Nature_Brilliance",            -- Tranquil Air
	[6] = "Interface\\Icons\\Spell_Nature_NatureResistanceTotem", -- Nature Resistance
}

function ShamanPower:GetTwistTotemName()
	local idx = self.opt.twistTotem or 2
	local spellID = self.AirTotems[idx]
	if spellID then
		return SPCompat.SpellName(spellID, "Grace of Air Totem")
	end
	return "Grace of Air Totem"
end

function ShamanPower:GetTwistTotemIcon()
	local idx = self.opt.twistTotem or 2
	return self.TwistTotemIcons[idx] or "Interface\\Icons\\Spell_Nature_InvisibilityTotem"
end

-- ============================================================================
-- Totem Twisting Timer (visual countdown for Air totem twist window)
-- ============================================================================

ShamanPower.twistTimer = nil
ShamanPower.twistCooldown = nil
ShamanPower.TWIST_WINDOW = 10  -- Seconds before Windfury buff expires

function ShamanPower:SetupTwistTimer()
	if not self.opt.enableTotemTwisting then return end

	local airButton = self.totemButtons[4]
	if not airButton then return end

	-- Create twist timer display on top of air totem icon
	if not self.twistTimerFrame then
		self.twistTimerFrame = CreateFrame("Frame", "ShamanPowerTwistTimerFrame", airButton)
		self.twistTimerFrame:SetAllPoints(airButton)
		self.twistTimerFrame:SetFrameStrata("HIGH")

		self.twistTimerText = self.twistTimerFrame:CreateFontString(nil, "OVERLAY")
		ShamanPower:SetSPFont(self.twistTimerText, "timers", 16, "OUTLINE")
		self.twistTimerText:SetPoint("CENTER", airButton, "CENTER", 0, 0)
		self.twistTimerText:SetTextColor(1, 1, 1)
		self.twistTimerFrame:Hide()
	end

	-- Register twist tracking with consolidated update system (20fps)
	if not self.updateSystem.subsystems["twist"] then
		self:RegisterUpdateSubsystem("twist", 0.05, function()
			ShamanPower:UpdateTwistTimer()
		end)
	end
	self:EnableUpdateSubsystem("twist")
end

function ShamanPower:HideTwistTimer()
	if self.twistTimerFrame then
		self.twistTimerFrame:Hide()
	end
	self:DisableUpdateSubsystem("twist")
	self.twistStartTime = nil
end

-- The air name changes when a totem changes, not on each 20 Hz paint pass.
ShamanPower.windfuryNameCache = {}
function ShamanPower:IsWindfuryTotemName(name)
	if issecretvalue(name) or type(name) ~= "string" then return false end
	local cached, generation = self.windfuryNameCache, SPCompat.SpellDataGeneration
	if cached.name ~= name or cached.generation ~= generation then
		cached.name, cached.generation = name, generation
		cached.matches = SPCompat.TotemNameMatches(name, 8512, "Windfury Totem")
	end
	return cached.matches
end

function ShamanPower:UpdateTwistTimer()
	if not self.opt.enableTotemTwisting then
		self:HideTwistTimer()
		return
	end

	-- Check if Air totem is active
	local haveTotem, name, startTime, duration = self:GetElementTotemInfo(4)
	if issecretvalue(haveTotem) or issecretvalue(name) or issecretvalue(startTime) then return end
	local isWindfury = self:IsWindfuryTotemName(name)

	-- Only update icon in classic mode (not TotemTimers mode)
	-- In TotemTimers mode, UpdateActiveTotemOverlays handles the icon
	if not self.opt.activeTotemAsMain then
		local airButton = self.totemButtons[4]
		local iconTexture = airButton and airButton.icon
		if iconTexture then
			if haveTotem and name then
				local twistName = self:GetTwistTotemName()
				if isWindfury then
					-- WF is down, show twist totem icon (what to cast next)
					iconTexture:SetTexture(self:GetTwistTotemIcon())
				elseif name:find(twistName, 1, true) then
					-- Twist totem is down, show WF icon (what to cast next)
					iconTexture:SetTexture("Interface\\Icons\\Spell_Nature_Windfury")
				end
				-- Don't change icon for other Air totems - let them show naturally
			end
		end
	end

	if haveTotem and startTime and startTime > 0 then
		-- Restart timer every time WINDFURY is placed
		if isWindfury and self.twistStartTime ~= startTime then
			-- New Windfury placed - reset the 10 second timer
			self.twistStartTime = startTime
			self.twistSoundPlayed = false
		end

		-- If no timer running, hide and return
		if not self.twistStartTime then
			if self.twistTimerFrame then
				self.twistTimerFrame:Hide()
			end
			return
		end

		-- Calculate remaining time
		local elapsed = GetTime() - self.twistStartTime
		local remaining = self.TWIST_WINDOW - elapsed

		-- Show center-screen timer
		if remaining > 0 then
			if self.twistTimerFrame and self.twistTimerText then
				local format = self.opt.twistTimerNoDecimals and "%.0f" or "%.1f"
				self.twistTimerText:SetText(string.format(format, remaining))
				-- Twist beep sound (not once switched off during a fight: the bar waits for its end)
				if self.opt.twistSoundEnabled and not self.twistSoundPlayed then
					if remaining <= self.opt.twistSoundThreshold and not self:IsOff() then
						self:PlaySoundWithVolume(self:GetSoundFile(self.opt.twistSoundName or "Raid Warning"), self.opt.twistSoundVolume, true)
						self.twistSoundPlayed = true
					end
				end
				-- Color: white > 3s, yellow > 1s, red <= 1s
				if remaining <= 1 then
					self.twistTimerText:SetTextColor(1, 0.2, 0.2)
				elseif remaining <= 3 then
					self.twistTimerText:SetTextColor(1, 1, 0.2)
				else
					self.twistTimerText:SetTextColor(1, 1, 1)
				end
				self.twistTimerFrame:Show()
			end
		else
			-- Timer expired, reset
			self.twistStartTime = nil
			self.twistSoundPlayed = false
			if self.twistTimerFrame then
				self.twistTimerFrame:Hide()
			end
		end
	else
		-- No Air totem active - but don't reset immediately in case we're mid-twist
		-- Only reset if timer has expired or been running for a while with no totem
		if self.twistStartTime then
			local elapsed = GetTime() - self.twistStartTime
			local remaining = self.TWIST_WINDOW - elapsed
			if remaining <= 0 then
				-- Timer expired, safe to reset
				self.twistStartTime = nil
				self.twistSoundPlayed = false
				if self.twistTimerFrame then
					self.twistTimerFrame:Hide()
				end
			end
			-- Otherwise keep the timer running - Grace of Air might be incoming
		else
			if self.twistTimerFrame then
				self.twistTimerFrame:Hide()
			end
		end
	end
end

-- ============================================================================
-- Totem Duration Progress Bar (shows time remaining on totems)
-- ============================================================================

ShamanPower.totemProgressBars = {}  -- Progress bar textures for each element

-- Element colors for duration bars
ShamanPower.DurationBarColors = {
	[1] = {0.2, 0.8, 0.2},  -- Earth - green
	[2] = {0.9, 0.3, 0.1},  -- Fire - orange/red
	[3] = {0.2, 0.5, 0.9},  -- Water - blue
	[4] = {0.8, 0.8, 0.8},  -- Air - white/gray
}

-- Duration Bar Opacity (Totem Bar > Duration Bars): the colored bar and its
-- dark track, on ShamanPower's bar and on Blizzard's (WoW: Forever). Duration Bar
-- Background off hides the dark track (like the pulse bars, which have none),
-- on the pop-out trackers' bars too. Set once per change, nothing per frame.
function ShamanPower:DurationTrackAlpha(a)
	if self.opt and self.opt.durationBarBackground == false then return 0 end
	return a or 1
end
function ShamanPower:ApplyDurationBarOpacity()
	local a = self.opt and self.opt.durationBarOpacity or 1
	for _, b in pairs(self.totemProgressBars or {}) do
		if b.bg then b.bg:SetAlpha(self:DurationTrackAlpha(a)) end
		if b.bar then b.bar:SetAlpha(a) end
	end
	for _, b in pairs(self.poppedOutProgressBars or {}) do
		if b.bg then b.bg:SetAlpha(self:DurationTrackAlpha(1)) end
	end
	if self.ApplyBlizzardBarDurationOpacity then self:ApplyBlizzardBarDurationOpacity() end
end
function ShamanPower:SetDurationBarBackground(on)
	if not self.opt then return end
	if on then self.opt.durationBarBackground = nil else self.opt.durationBarBackground = false end
	self:ApplyDurationBarOpacity()
end

-- Create progress bars for totem buttons
function ShamanPower:SetupTotemProgressBars()
	local barSize = self.opt.durationBarHeight or 3

	for element = 1, 4 do
		local totemButton = self.totemButtons[element]
		if totemButton and not self.totemProgressBars[element] then
			-- Background (dark)
			local bgBar = totemButton:CreateTexture(nil, "OVERLAY")
			bgBar:SetColorTexture(0, 0, 0, 0.7)
			bgBar:Hide()

			-- Progress bar (colored)
			local progressBar = totemButton:CreateTexture(nil, "OVERLAY", nil, 1)
			local colors = self.DurationBarColors[element]
			ShamanPower:SetSPBarColor(progressBar, "duration", colors[1], colors[2], colors[3], 1)
			progressBar:Hide()

			-- Duration text INSIDE the bar (top)
			local insideTextTop = totemButton:CreateFontString(nil, "OVERLAY", nil, 7)
			ShamanPower:SetSPFont(insideTextTop, "timers", 8, "OUTLINE")
			insideTextTop:SetTextColor(1, 1, 1)
			insideTextTop:Hide()

			-- Duration text INSIDE the bar (bottom)
			local insideTextBottom = totemButton:CreateFontString(nil, "OVERLAY", nil, 7)
			ShamanPower:SetSPFont(insideTextBottom, "timers", 8, "OUTLINE")
			insideTextBottom:SetTextColor(1, 1, 1)
			insideTextBottom:Hide()

			-- Duration text ABOVE the bar
			local aboveBarText = totemButton:CreateFontString(nil, "OVERLAY")
			ShamanPower:SetSPFont(aboveBarText, "timers", 8, "OUTLINE")
			aboveBarText:SetTextColor(1, 1, 1)
			aboveBarText:Hide()

			-- Duration text BELOW the bar
			local belowBarText = totemButton:CreateFontString(nil, "OVERLAY")
			ShamanPower:SetSPFont(belowBarText, "timers", 8, "OUTLINE")
			belowBarText:SetTextColor(1, 1, 1)
			belowBarText:Hide()

			-- Duration text ON the icon
			local iconText = totemButton:CreateFontString(nil, "OVERLAY")
			ShamanPower:SetSPFont(iconText, "timers", 9, "OUTLINE")
			iconText:SetPoint("CENTER", totemButton, "CENTER", 0, 0)
			iconText:SetTextColor(1, 1, 1)
			iconText:Hide()

			self.totemProgressBars[element] = {
				bg = bgBar,
				bar = progressBar,
				insideText = insideTextTop,  -- Keep for compatibility
				insideTextTop = insideTextTop,
				insideTextBottom = insideTextBottom,
				aboveBarText = aboveBarText,
				belowBarText = belowBarText,
				belowText = belowBarText,  -- Keep old name for compatibility
				outsideText = belowBarText,  -- Keep old name for compatibility
				iconText = iconText,
				maxWidth = totemButton:GetWidth(),
				maxHeight = totemButton:GetHeight()
			}
		elseif totemButton and self.totemProgressBars[element] then
			-- Bars exist but maybe missing text elements (upgrade from old version)
			local bars = self.totemProgressBars[element]

			if not bars.insideTextTop then
				local insideTextTop = totemButton:CreateFontString(nil, "OVERLAY", nil, 7)
				ShamanPower:SetSPFont(insideTextTop, "timers", 8, "OUTLINE")
				insideTextTop:SetTextColor(1, 1, 1)
				insideTextTop:Hide()
				bars.insideTextTop = insideTextTop
				bars.insideText = insideTextTop  -- Compatibility
			end

			if not bars.insideTextBottom then
				local insideTextBottom = totemButton:CreateFontString(nil, "OVERLAY", nil, 7)
				ShamanPower:SetSPFont(insideTextBottom, "timers", 8, "OUTLINE")
				insideTextBottom:SetTextColor(1, 1, 1)
				insideTextBottom:Hide()
				bars.insideTextBottom = insideTextBottom
			end

			if not bars.aboveBarText then
				local aboveBarText = totemButton:CreateFontString(nil, "OVERLAY")
				ShamanPower:SetSPFont(aboveBarText, "timers", 8, "OUTLINE")
				aboveBarText:SetTextColor(1, 1, 1)
				aboveBarText:Hide()
				bars.aboveBarText = aboveBarText
			end

			if not bars.belowBarText then
				local belowBarText = totemButton:CreateFontString(nil, "OVERLAY")
				ShamanPower:SetSPFont(belowBarText, "timers", 8, "OUTLINE")
				belowBarText:SetTextColor(1, 1, 1)
				belowBarText:Hide()
				bars.belowBarText = belowBarText
				bars.belowText = belowBarText  -- Compatibility
				bars.outsideText = belowBarText  -- Compatibility
			end

			if not bars.iconText then
				local iconText = totemButton:CreateFontString(nil, "OVERLAY")
				ShamanPower:SetSPFont(iconText, "timers", 9, "OUTLINE")
				iconText:SetPoint("CENTER", totemButton, "CENTER", 0, 0)
				iconText:SetTextColor(1, 1, 1)
				iconText:Hide()
				bars.iconText = iconText
			end

			-- Store dimensions
			bars.maxWidth = totemButton:GetWidth()
			bars.maxHeight = totemButton:GetHeight()
		end
	end

	-- General > Themes: the time texts' colour (tb.duration-text); nothing on Standard
	for element = 1, 4 do self:ThemePaintDurationBars(element, false) end

	-- Position bars based on setting
	self:UpdateTotemProgressBarPositions()

	-- Register progress bar updates with consolidated update system (10fps)
	if not self.updateSystem.subsystems["progressBars"] then
		local barState = { stayAwake = true }   -- more than totem work below: never asleep
		local function barPass() ShamanPower:UpdateTotemProgressBars() end
		self:RegisterUpdateSubsystem("progressBars", 0.1, function()
			spWhileTotemsDown(barState, barPass)   -- duration bars / texts / dropped-totem overlays need a totem down

			-- Dynamic Mode (and Grid): update totem icons to reflect currently placed totems
			if ShamanPower:DropSetsAssignment() then
				ShamanPower:UpdateDynamicTotemIcons()
			end

			-- Update totem bar opacity (for "full opacity when active" option). It only
			-- changes when a totem does, and PLAYER_TOTEM_UPDATE asks for a pass through
			-- _barWake; the once-a-second pass is a safety net.
			barState.n = (barState.n or 0) + 1
			local slowPass = barState.n >= 10
			if slowPass then barState.n = 0 end
			local woke = ShamanPower._barWake
			ShamanPower._barWake = nil
			if ShamanPower.opt.totemBarFullOpacityWhenActive and (woke or slowPass) then
				ShamanPower:UpdateTotemBarOpacity()
			end

			-- Update totem cooldowns on main buttons and flyout buttons: every tick while a
			-- cooldown is being drawn (its text counts down), otherwise only when the client
			-- says a cooldown changed, a flyout opened, or once a second.
			if ShamanPower.opt.showTotemCooldowns ~= false and (ShamanPower._totemCdShown or woke or slowPass) then
				ShamanPower:UpdateTotemCooldowns()
			end
		end)
		if not self._barWakeFrame then
			local f = CreateFrame("Frame")
			for _, ev in ipairs({ "SPELL_UPDATE_COOLDOWN", "PLAYER_TOTEM_UPDATE", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "SPELLS_CHANGED" }) do
				pcall(f.RegisterEvent, f, ev)
			end
			f:SetScript("OnEvent", function(_, ev)
				ShamanPower._barWake = true
				ShamanPower._ovWake = true
				-- (where SPCompat hands the event on itself, it calls this: see OnCooldownEvent)
				if ev == "SPELL_UPDATE_COOLDOWN" and not (SPCompat and SPCompat.OnCooldownEvent) then
					ShamanPower:RefreshEngineCooldowns()
				end
				if ev == "PLAYER_REGEN_DISABLED" or ev == "PLAYER_REGEN_ENABLED" then ShamanPower:InvalidateTotemInfo() end
			end)
			self._barWakeFrame = f
		end
	end
	-- Only enable if any of these features are on
	local needsProgressBars = self.opt.showDurationBars ~= false
		or self.opt.dynamicTotemMode
		or self.opt.totemBarFullOpacityWhenActive
		or self.opt.showTotemCooldowns ~= false
		or (self.UsingBlizzardTotemBar and self:UsingBlizzardTotemBar())
		or (self.GridActive and self:GridActive())
	if needsProgressBars then
		self:EnableUpdateSubsystem("progressBars")
	else
		self:DisableUpdateSubsystem("progressBars")
	end
end

-- Update progress bar positions based on setting
function ShamanPower:UpdateTotemProgressBarPositions()
	local barPosition = self.opt.durationBarPosition or "bottom"
	local barSize = self.opt.durationBarHeight or 3
	local dotT, dotB, dotL, dotR = self:GetPartyDotPads()

	-- Enable/disable progressBars subsystem based on whether any features need it
	local barDisabled = (barPosition == "none")
	local textDisabled = (self.opt.durationTextLocation == "none" or self.opt.durationTextLocation == nil)
	local needsProgressBars = (not barDisabled) or (not textDisabled)
		or self.opt.dynamicTotemMode
		or self.opt.totemBarFullOpacityWhenActive
		or self.opt.showTotemCooldowns ~= false
		or (self.UsingBlizzardTotemBar and self:UsingBlizzardTotemBar())
		or (self.GridActive and self:GridActive())
	if needsProgressBars then
		self:EnableUpdateSubsystem("progressBars")
	else
		self:DisableUpdateSubsystem("progressBars")
	end

	for element = 1, 4 do
		local totemButton = self.totemButtons[element]
		local bars = self.totemProgressBars[element]
		if totemButton and bars then
			-- room for the party dots, and for the flyout tab on its side while it shows
			local aT, aB, aL, aR = self:FlyoutArrowPads(totemButton)
			local padT, padB, padL, padR = dotT + aT, dotB + aB, dotL + aL, dotR + aR
			bars.bg:ClearAllPoints()
			bars.bar:ClearAllPoints()
			if bars.insideTextTop then bars.insideTextTop:ClearAllPoints() end
			if bars.insideTextBottom then bars.insideTextBottom:ClearAllPoints() end
			if bars.aboveBarText then bars.aboveBarText:ClearAllPoints() end
			if bars.belowBarText then bars.belowBarText:ClearAllPoints() end

			if barPosition == "bottom" then
				-- Horizontal bar below the icon
				bars.bg:SetHeight(barSize)
				bars.bg:SetPoint("TOPLEFT", totemButton, "BOTTOMLEFT", 0, -(1 + padB))
				bars.bg:SetPoint("TOPRIGHT", totemButton, "BOTTOMRIGHT", 0, -(1 + padB))
				bars.bar:SetHeight(barSize)
				bars.bar:SetPoint("TOPLEFT", totemButton, "BOTTOMLEFT", 0, -(1 + padB))
				if bars.insideTextTop then bars.insideTextTop:SetPoint("TOP", bars.bg, "TOP", 0, -1) end
				if bars.insideTextBottom then bars.insideTextBottom:SetPoint("BOTTOM", bars.bg, "BOTTOM", 0, 1) end
				if bars.aboveBarText then bars.aboveBarText:SetPoint("BOTTOM", bars.bg, "TOP", 0, 1) end
				if bars.belowBarText then bars.belowBarText:SetPoint("TOP", bars.bg, "BOTTOM", 0, -1) end
			elseif barPosition == "bottom_vert" then
				-- Vertical bar below the icon (centered), shrinks UP toward icon
				bars.bg:SetWidth(barSize)
				bars.bg:SetPoint("TOP", totemButton, "BOTTOM", 0, -(1 + padB))
				bars.bg:SetHeight(totemButton:GetHeight())
				bars.bar:SetWidth(barSize)
				bars.bar:SetPoint("TOP", bars.bg, "TOP", 0, 0)
				if bars.insideTextTop then bars.insideTextTop:SetPoint("TOP", bars.bg, "TOP", 0, -1) end
				if bars.insideTextBottom then bars.insideTextBottom:SetPoint("BOTTOM", bars.bg, "BOTTOM", 0, 1) end
				if bars.aboveBarText then bars.aboveBarText:SetPoint("BOTTOM", bars.bg, "TOP", 0, 1) end
				if bars.belowBarText then bars.belowBarText:SetPoint("TOP", bars.bg, "BOTTOM", 0, -1) end
			elseif barPosition == "top" then
				-- Horizontal bar above the icon
				bars.bg:SetHeight(barSize)
				bars.bg:SetPoint("BOTTOMLEFT", totemButton, "TOPLEFT", 0, 1 + padT)
				bars.bg:SetPoint("BOTTOMRIGHT", totemButton, "TOPRIGHT", 0, 1 + padT)
				bars.bar:SetHeight(barSize)
				bars.bar:SetPoint("BOTTOMLEFT", totemButton, "TOPLEFT", 0, 1 + padT)
				if bars.insideTextTop then bars.insideTextTop:SetPoint("TOP", bars.bg, "TOP", 0, -1) end
				if bars.insideTextBottom then bars.insideTextBottom:SetPoint("BOTTOM", bars.bg, "BOTTOM", 0, 1) end
				if bars.aboveBarText then bars.aboveBarText:SetPoint("BOTTOM", bars.bg, "TOP", 0, 1) end
				if bars.belowBarText then bars.belowBarText:SetPoint("TOP", bars.bg, "BOTTOM", 0, -1) end
			elseif barPosition == "top_vert" then
				-- Vertical bar above the icon (centered)
				bars.bg:SetWidth(barSize)
				bars.bg:SetPoint("BOTTOM", totemButton, "TOP", 0, 1 + padT)
				bars.bg:SetHeight(totemButton:GetHeight())
				bars.bar:SetWidth(barSize)
				bars.bar:SetPoint("BOTTOM", bars.bg, "BOTTOM", 0, 0)
				if bars.insideTextTop then bars.insideTextTop:SetPoint("TOP", bars.bg, "TOP", 0, -1) end
				if bars.insideTextBottom then bars.insideTextBottom:SetPoint("BOTTOM", bars.bg, "BOTTOM", 0, 1) end
				if bars.aboveBarText then bars.aboveBarText:SetPoint("BOTTOM", bars.bg, "TOP", 0, 1) end
				if bars.belowBarText then bars.belowBarText:SetPoint("TOP", bars.bg, "BOTTOM", 0, -1) end
			elseif barPosition == "left" then
				-- Vertical bar to the left of the icon
				bars.bg:SetWidth(barSize)
				bars.bg:SetPoint("TOPRIGHT", totemButton, "TOPLEFT", -(1 + padL), 0)
				bars.bg:SetPoint("BOTTOMRIGHT", totemButton, "BOTTOMLEFT", -(1 + padL), 0)
				bars.bar:SetWidth(barSize)
				bars.bar:SetPoint("BOTTOMRIGHT", totemButton, "BOTTOMLEFT", -(1 + padL), 0)
				if bars.insideTextTop then bars.insideTextTop:SetPoint("TOP", bars.bg, "TOP", 0, -1) end
				if bars.insideTextBottom then bars.insideTextBottom:SetPoint("BOTTOM", bars.bg, "BOTTOM", 0, 1) end
				if bars.aboveBarText then bars.aboveBarText:SetPoint("RIGHT", bars.bg, "LEFT", -1, 0) end
				if bars.belowBarText then bars.belowBarText:SetPoint("LEFT", bars.bg, "RIGHT", 1, 0) end
			elseif barPosition == "right" then
				-- Vertical bar to the right of the icon
				bars.bg:SetWidth(barSize)
				bars.bg:SetPoint("TOPLEFT", totemButton, "TOPRIGHT", 1 + padR, 0)
				bars.bg:SetPoint("BOTTOMLEFT", totemButton, "BOTTOMRIGHT", 1 + padR, 0)
				bars.bar:SetWidth(barSize)
				bars.bar:SetPoint("BOTTOMLEFT", totemButton, "BOTTOMRIGHT", 1 + padR, 0)
				if bars.insideTextTop then bars.insideTextTop:SetPoint("TOP", bars.bg, "TOP", 0, -1) end
				if bars.insideTextBottom then bars.insideTextBottom:SetPoint("BOTTOM", bars.bg, "BOTTOM", 0, 1) end
				if bars.aboveBarText then bars.aboveBarText:SetPoint("LEFT", bars.bg, "RIGHT", 1, 0) end
				if bars.belowBarText then bars.belowBarText:SetPoint("RIGHT", bars.bg, "LEFT", -1, 0) end
			end
		end
	end
	self:ApplyDurationBarOpacity()   -- new bars, or a settings change
end

-- Format duration time as M:SS or just seconds (with caching to avoid string garbage)
local FormatDurationCache = {}
local FormatDurationCacheSize = 0
local DURATION_CACHE_MAX = 500  -- Limit cache size to prevent unbounded growth

local function FormatDuration(seconds)
	local intSec = math.floor(seconds)
	if intSec < 0 then intSec = 0 end

	-- Check cache first
	local cached = FormatDurationCache[intSec]
	if cached then return cached end

	-- Generate formatted string
	local result
	if intSec >= 3600 then
		local hours = math.floor(intSec / 3600)
		result = hours .. "h"
	elseif intSec >= 600 then
		local mins = math.floor(intSec / 60)
		result = mins .. "m"
	elseif intSec >= 60 then
		local mins = math.floor(intSec / 60)
		local secs = intSec % 60
		if secs < 10 then
			result = mins .. ":0" .. secs
		else
			result = mins .. ":" .. secs
		end
	else
		result = tostring(intSec)
	end

	-- Cache the result (with size limit)
	if FormatDurationCacheSize < DURATION_CACHE_MAX then
		FormatDurationCache[intSec] = result
		FormatDurationCacheSize = FormatDurationCacheSize + 1
	end

	return result
end
ShamanPower.FormatDuration = FormatDuration   -- the Coverage cells' time left reads the same

-- Update progress bars based on totem duration
function ShamanPower:UpdateTotemProgressBars()
	if self.GridActive and self:GridActive() then
		self:UpdateGridTotems()
		self:UpdatePoppedOutProgressBars()
		self:UpdateActiveTotemOverlaysIfDue()
		return
	end
	-- Native hosts use this existing driver; the engine animates their lifetime
	-- widgets between model changes. Do not draw hidden custom duration bars.
	if self.UsingBlizzardTotemBar and self:UsingBlizzardTotemBar() then
		self:UpdateBlizzardTotemOverlays()
		self:UpdatePoppedOutProgressBars()
		self:UpdateActiveTotemOverlaysIfDue()
		return
	end
	local textLocation = self.opt.durationTextLocation or "none"
	local barPosition = self.opt.durationBarPosition or "bottom"
	local barSize = self.opt.durationBarHeight or 3
	local textSize = self.opt.durationTextSize or 8
	local barDisabled = (barPosition == "none")
	local isVertical = (barPosition == "left" or barPosition == "right" or barPosition == "top_vert" or barPosition == "bottom_vert")

	-- Compact style draws duration itself: keep the icon-style bars hidden
	if self:CompactActive() then
		for element = 1, 4 do
			local bars = self.totemProgressBars[element]
			if bars then
				bars.bg:Hide(); bars.bar:Hide()
				if bars.insideTextTop then bars.insideTextTop:Hide() end
				if bars.insideTextBottom then bars.insideTextBottom:Hide() end
				if bars.aboveBarText then bars.aboveBarText:Hide() end
				if bars.belowBarText then bars.belowBarText:Hide() end
				if bars.iconText then bars.iconText:Hide() end
			end
		end
		self:UpdatePoppedOutProgressBars()
		self:UpdateActiveTotemOverlaysIfDue()
		return
	end

	for element = 1, 4 do
		local bars = self.totemProgressBars[element]
		if bars then
			local haveTotem, totemName, startTime, duration = self:GetElementTotemInfo(element)

			-- Check if the active totem is popped out as a single totem
			local totemIsPoppedOut = false
			if haveTotem and totemName then
				for key, popOutBars in pairs(self.poppedOutProgressBars or {}) do
					if popOutBars.element == element and popOutBars.spellName then
						local ok1, result1 = pcall(string.find, totemName, popOutBars.spellName, 1, true)
						local ok2, result2 = pcall(string.find, popOutBars.spellName, totemName, 1, true)
						if (ok1 and result1) or (ok2 and result2) then
							totemIsPoppedOut = true
							break
						end
					end
				end
			end

			-- If totem is popped out, hide main bar and let pop-out handle it
			if totemIsPoppedOut then
				bars.bg:Hide()
				bars.bar:Hide()
				if bars.insideTextTop then bars.insideTextTop:Hide() end
				if bars.insideTextBottom then bars.insideTextBottom:Hide() end
				if bars.aboveBarText then bars.aboveBarText:Hide() end
				if bars.belowBarText then bars.belowBarText:Hide() end
				if bars.iconText then bars.iconText:Hide() end
			elseif haveTotem and duration and duration > 0 then
				local remaining = (startTime + duration) - GetTime()
				local pct = remaining / duration

				if pct > 0 and pct <= 1 then
					-- Show/hide bars based on whether bar position is "none"
					if barDisabled then
						bars.bg:Hide()
						bars.bar:Hide()
					else
						-- Update bar size based on remaining time and orientation
						if isVertical then
							local height = (bars.maxHeight or 26) * pct
							bars.bar:SetHeight(math.max(1, height))
							bars.bar:SetWidth(barSize)
						else
							local width = (bars.maxWidth or 26) * pct
							bars.bar:SetWidth(math.max(1, width))
							bars.bar:SetHeight(barSize)
						end
						bars.bg:Show()
						bars.bar:Show()
					end

					-- Update duration text based on option
					local durationStr = FormatDuration(remaining)

					-- Hide all text elements first
					if bars.insideTextTop then bars.insideTextTop:Hide() end
					if bars.insideTextBottom then bars.insideTextBottom:Hide() end
					if bars.aboveBarText then bars.aboveBarText:Hide() end
					if bars.belowBarText then bars.belowBarText:Hide() end
					if bars.iconText then bars.iconText:Hide() end

					-- Show the appropriate text element (apply text size)
					if textLocation == "inside_top" then
						if bars.insideTextTop then
							ShamanPower:SetSPFont(bars.insideTextTop, "timers", textSize, "OUTLINE")
							bars.insideTextTop:SetText(durationStr)
							bars.insideTextTop:Show()
						end
					elseif textLocation == "inside_bottom" then
						if bars.insideTextBottom then
							ShamanPower:SetSPFont(bars.insideTextBottom, "timers", textSize, "OUTLINE")
							bars.insideTextBottom:SetText(durationStr)
							bars.insideTextBottom:Show()
						end
					elseif textLocation == "above" then
						if bars.aboveBarText then
							ShamanPower:SetSPFont(bars.aboveBarText, "timers", textSize, "OUTLINE")
							bars.aboveBarText:SetText(durationStr)
							bars.aboveBarText:Show()
						end
					elseif textLocation == "below" then
						if bars.belowBarText then
							ShamanPower:SetSPFont(bars.belowBarText, "timers", textSize, "OUTLINE")
							bars.belowBarText:SetText(durationStr)
							bars.belowBarText:Show()
						end
					elseif textLocation == "icon" then
						if bars.iconText then
							ShamanPower:SetSPFont(bars.iconText, "timers", textSize, "OUTLINE")
							bars.iconText:SetText(durationStr)
							bars.iconText:Show()
						end
					end
				else
					bars.bg:Hide()
					bars.bar:Hide()
					if bars.insideTextTop then bars.insideTextTop:Hide() end
					if bars.insideTextBottom then bars.insideTextBottom:Hide() end
					if bars.aboveBarText then bars.aboveBarText:Hide() end
					if bars.belowBarText then bars.belowBarText:Hide() end
					if bars.iconText then bars.iconText:Hide() end
				end
			else
				bars.bg:Hide()
				bars.bar:Hide()
				if bars.insideTextTop then bars.insideTextTop:Hide() end
				if bars.insideTextBottom then bars.insideTextBottom:Hide() end
				if bars.aboveBarText then bars.aboveBarText:Hide() end
				if bars.belowBarText then bars.belowBarText:Hide() end
				if bars.iconText then bars.iconText:Hide() end
			end
		end
	end

	-- Update popped-out single totem progress bars
	self:UpdatePoppedOutProgressBars()

	-- Update active totem overlays
	self:UpdateActiveTotemOverlaysIfDue()
end

-- Format cooldown time for display
local function FormatCooldownTime(seconds)
	if seconds >= 60 then
		return string.format("%dm", math.ceil(seconds / 60))
	elseif seconds >= 10 then
		return string.format("%d", math.floor(seconds))
	else
		return string.format("%.1f", seconds)
	end
end

-- Direction names describe the advancing gray (Grays Out) or color (Fills
-- Back In). A missing choice preserves the old top-gray / bottom-color look.
function ShamanPower:SweepGrayFromTop(style, direction)
	if direction ~= "top" and direction ~= "bottom" then return true end
	if style == "reverse" or style == "fills" then return direction == "bottom" end
	return direction == "top"
end

-- Plain, already-readable fractions only. The game-driven paths use a
-- StatusBar instead. Shared by full icons and the two halves of an imbue.
function ShamanPower:PaintVerticalSweep(texture, anchor, fraction, height, fromTop, left, right, width, side)
	local h = height * fraction
	if h <= 1 then texture:Hide(); return end
	if texture._sweepAnchor ~= anchor or texture._sweepTop ~= fromTop or texture._sweepSide ~= side or texture._sweepWidth ~= width then
		texture._sweepAnchor, texture._sweepTop, texture._sweepSide, texture._sweepWidth = anchor, fromTop, side, width
		texture:ClearAllPoints()
		if side == "right" then
			texture:SetPoint(fromTop and "TOPRIGHT" or "BOTTOMRIGHT", anchor, fromTop and "TOPRIGHT" or "BOTTOMRIGHT", 0, 0)
		else
			texture:SetPoint(fromTop and "TOPLEFT" or "BOTTOMLEFT", anchor, fromTop and "TOPLEFT" or "BOTTOMLEFT", 0, 0)
		end
		if width then texture:SetWidth(width)
		else texture:SetPoint(fromTop and "TOPRIGHT" or "BOTTOMRIGHT", anchor, fromTop and "TOPRIGHT" or "BOTTOMRIGHT", 0, 0) end
	end
	texture:SetHeight(h)
	if fromTop then texture:SetTexCoord(left, right, 0.08, 0.08 + fraction * 0.84)
	else texture:SetTexCoord(left, right, 0.92 - fraction * 0.84, 0.92) end
	texture:Show()
end

-- Totem cooldown visual: radial swipe, growing gray, or returning color.
function ShamanPower:ApplyTotemCooldownVisual(btn, start, duration)
	local style = self.opt.totemCooldownSweep or "radial"
	if style == "vertical" or style == "reverse" then
		btn.cooldown:Clear()
		local icon = btn.icon
		if not btn.cdSweep and icon then
			local g = btn:CreateTexture(nil, "ARTWORK", nil, 1)
			g:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
			g:SetPoint("TOPRIGHT", icon, "TOPRIGHT", 0, 0)
			g:SetDesaturated(true)
			g:SetVertexColor(0.5, 0.5, 0.5)
			btn.cdSweep = g
			if ShamanPower.ShapeIconTexture then ShamanPower:ShapeIconTexture(g, icon) end   -- Icon Shape
		end
		if btn.cdSweep then
			local remaining = (start + duration) - GetTime()
			local frac = math.max(0, math.min(1, remaining / duration))
			local depleted = (style == "reverse") and frac or (1 - frac)   -- reverse: grey shrinks as time runs down
			btn.cdSweep:SetTexture(icon:GetTexture())
			self:PaintVerticalSweep(btn.cdSweep, icon, depleted, icon:GetHeight(),
				self:SweepGrayFromTop(style, self.opt.totemCooldownSweepDirection), 0.08, 0.92)
		end
	else
		if btn.cdSweep then btn.cdSweep:Hide() end
		btn.cooldown:SetDrawEdge(self.opt.totemCooldownEdge ~= false)
		btn.cooldown:SetCooldown(start, duration)
	end
end

function ShamanPower:ClearTotemCooldownVisual(btn)
	self:DisarmEngineCooldownEnd(btn.cooldown)
	btn.cooldown:Clear()
	if btn.cdSweep then btn.cdSweep:Hide() end
	if btn.cdBar then btn.cdBar:Hide() end
	btn._engineCDKey = nil   -- the next pass hands the engine whatever is running
	btn._cdSpell = nil       -- and nothing is read for it on cooldown events (WoW: Forever)
end

-- ============================================================================
-- Engine-drawn totem cooldowns (Mainline family)
-- ============================================================================
-- Cooldown numbers are secret in combat, so the addon's own text counted down
-- a shadow model there (own cast time plus a learned or base length). The
-- client's Cooldown widget draws its own countdown from a duration object,
-- which C_Spell.GetSpellCooldownDuration hands out secret-safe, in combat
-- (measured, /spdiag engine timer pipeline). So on this family the engine is
-- handed a cooldown once when it starts or ends (SPELL_UPDATE_COOLDOWN wakes
-- the pass; the game's own flags say whether one is running, the shadow model
-- only when they cannot: EngineCooldownRunning) and draws the
-- sweep and the numbers itself from then on: nothing per tick, the real
-- talent-adjusted length, and the same numbers as the action bars. The
-- numbers obey the client's "Show Numbers for Cooldowns" setting; turning the
-- addon's text option on turns that on too, turning it off leaves it alone.
local COUNTDOWN_CVAR = "countdownForCooldowns"

function ShamanPower:EngineCooldownsOn()
	if self._engineCD == nil then
		local on = false
		if SPCompat.FOREVER and C_Spell and C_Spell.GetSpellCooldownDuration then
			local ok, probe = pcall(CreateFrame, "Cooldown", nil, UIParent, "CooldownFrameTemplate")
			if ok and probe then
				on = probe.SetCooldownFromDurationObject ~= nil and probe.GetCountdownFontString ~= nil
					and probe.SetMinimumCountdownDuration ~= nil
				probe:Hide()
			end
		end
		self._engineCD = on
	end
	return self._engineCD
end

function ShamanPower:CountdownNumbersEnabled()
	return GetCVarBool ~= nil and GetCVarBool(COUNTDOWN_CVAR) or false
end

-- The addon's cooldown text wants the client's numbers: turn them on, once,
-- and say so (they show on the action bars too). Never turned off from here.
function ShamanPower:EnableCountdownNumbers()
	if not self:EngineCooldownsOn() or self:CountdownNumbersEnabled() then return end
	SetCVar(COUNTDOWN_CVAR, "1")
	self:Print("Turned on WoW's |cffffd100Show Numbers for Cooldowns|r so cooldown time can show on the totems (this also shows numbers on your action bars).")
end

-- The text settings the engine strings were last styled with (plain fields:
-- this is compared on every cooldown pass and must not build strings).
local function EngineTextChanged(self)
	local c = self.opt.totemCooldownTextColor
	local hide = self.opt.totemCooldownText == false
	local r, g, b = c and c.r or 1, c and c.g or 1, c and c.b or 1
	local t = self._engineText
	if t and t.hide == hide and t.r == r and t.g == g and t.b == b then return false end
	self._engineText = { hide = hide, r = r, g = g, b = b }
	return true
end

-- One Cooldown widget styled like the addon's own text.
function ShamanPower:StyleEngineCooldown(cd)
	if not (cd and self:EngineCooldownsOn()) then return end
	cd:SetHideCountdownNumbers(self.opt.totemCooldownText == false)
	pcall(cd.SetMinimumCountdownDuration, cd, 2000)        -- the global cooldown stays numberless
	pcall(cd.SetCountdownMillisecondsThreshold, cd, 10)    -- tenths under 10 s, like the addon's text
	pcall(cd.SetCountdownFont, cd, "GameFontNormalSmall")
	local ok, fs = pcall(cd.GetCountdownFontString, cd)
	if ok and fs then
		self:AdoptSPFont(fs, "timers")   -- the game's countdown follows the Fonts settings too
		local c = self.opt.totemCooldownTextColor
		fs:SetTextColor(c and c.r or 1, c and c.g or 1, c and c.b or 1)
		fs:SetShadowOffset(1, -1)
	end
end

function ShamanPower:RestyleEngineCooldowns()
	if not self:EngineCooldownsOn() then return end
	EngineTextChanged(self)   -- remember what is being applied
	for element = 1, 4 do
		local btn = self.totemButtons and self.totemButtons[element]
		if btn and btn.cooldown then self:StyleEngineCooldown(btn.cooldown) end
		local flyout = self.totemFlyouts and self.totemFlyouts[element]
		if flyout and flyout.buttons then
			for _, b in ipairs(flyout.buttons) do if b.cooldown then self:StyleEngineCooldown(b.cooldown) end end
		end
		-- Totem Rows' copies of them (Keep Flyouts on Main Totem Bar): their own Cooldowns draw the numbers
		local copies = self.RowsCopies and self:RowsCopies(element)
		if copies then
			for i = 1, #copies do
				local cd = copies[i].cooldown
				if cd then self:StyleEngineCooldown(cd) end
			end
		end
	end
end

-- "Show Totem Cooldowns" off: whatever the engine was drawing goes too.
function ShamanPower:ClearEngineCooldowns()
	if not self:EngineCooldownsOn() then return end
	for element = 1, 4 do
		local btn = self.totemButtons and self.totemButtons[element]
		if btn and btn.cooldown then self:ClearTotemCooldownVisual(btn) end
		local flyout = self.totemFlyouts and self.totemFlyouts[element]
		if flyout and flyout.buttons then
			for _, b in ipairs(flyout.buttons) do if b.cooldown then self:ClearTotemCooldownVisual(b) end end
		end
		-- Totem Rows' copies of them (Keep Flyouts on Main Totem Bar)
		local copies = self.RowsCopies and self:RowsCopies(element)
		if copies then
			for i = 1, #copies do
				if copies[i].cooldown then self:ClearTotemCooldownVisual(copies[i]) end
			end
		end
	end
end

-- The totem bar's (and its flyouts') vertical sweep, drawn the way Target Tracker's is:
-- the bar ALWAYS fills from the bottom. A bar filled from its top edge stretches the
-- icon's copy into the fill instead of cropping it, so a whole second icon, hard edges
-- and all, showed over the real one (2026-10-04). Gray from the top is drawn as the
-- colored copy filling over a gray one instead, and FeedEngineCooldown turns the timer
-- round for it. The cooldown bar's buttons use it too (FeedEngineBarCooldown, 2026-10-05:
-- the same hard edges there in a fight).
function ShamanPower:TotemEngineSweepBar(btn, fromTop)
	local icon = btn.icon
	if not icon then return nil end
	if not btn.cdBar then
		local clip = CreateFrame("Frame", nil, btn)
		clip:SetAllPoints(icon)
		clip:SetClipsChildren(true)
		clip:SetFrameLevel(btn:GetFrameLevel() + 1)
		local bar = CreateFrame("StatusBar", nil, clip)
		bar:SetOrientation("VERTICAL")
		if bar.SetFillStyle then bar:SetFillStyle("STANDARD") end   -- texture cropped to the fill, never stretched into it
		btn.cdBar, btn.cdBarClip = bar, clip
		if self.ShapeIconTexture then self:ShapeIconTexture(bar:GetStatusBarTexture(), icon) end   -- Icon Shape
	end
	local bar = btn.cdBar
	if not btn.cdBarGray then
		-- the gray copy under a colored fill, on the bar so it shows and hides with it
		local gray = bar:CreateTexture(nil, "BACKGROUND")
		gray:SetAllPoints(bar)
		btn.cdBarGray = gray
		if self.ShapeIconTexture then self:ShapeIconTexture(gray, icon) end   -- Icon Shape
	end
	bar:SetReverseFill(false)
	local left, _, _, _, right = icon:GetTexCoord()
	local trim = (left and right and right > left) and (left / (right - left)) or 0
	local margin = trim * icon:GetWidth()
	bar:ClearAllPoints()
	bar:SetPoint("TOPLEFT", btn.cdBarClip, "TOPLEFT", -margin, margin)
	bar:SetPoint("BOTTOMRIGHT", btn.cdBarClip, "BOTTOMRIGHT", margin, -margin)
	local file = icon:GetTexture()
	bar:SetStatusBarTexture(file)
	-- gray from the top: the colored copy fills from the bottom over the gray one;
	-- gray from the bottom: the gray copy fills, over the real icon
	local colored = fromTop and true or false
	if bar.SetStatusBarDesaturated then bar:SetStatusBarDesaturated(not colored) end
	if colored then bar:SetStatusBarColor(1, 1, 1, 1) else bar:SetStatusBarColor(0.5, 0.5, 0.5, 1) end
	local t = bar:GetStatusBarTexture()
	if t then
		t:SetDesaturated(not colored)
		if colored then t:SetVertexColor(1, 1, 1) else t:SetVertexColor(0.5, 0.5, 0.5) end
	end
	local gray = btn.cdBarGray
	gray:SetTexture(file)
	gray:SetDesaturated(true)
	gray:SetVertexColor(0.5, 0.5, 0.5)
	gray:SetShown(colored)
	return bar
end

-- Hand the engine a button's cooldown. Called from the cooldown pass with
-- the answer to "is one running" (EngineCooldownRunning); only does anything
-- when that, the spell or the style changed since the last call.
function ShamanPower:FeedEngineCooldown(btn, spellID, running)
	local cd = btn.cooldown
	if not cd then return end
	if EngineTextChanged(self) then self:RestyleEngineCooldowns() end
	local style = self.opt.totemCooldownSweep or "radial"
	local fromTop = self:SweepGrayFromTop(style, self.opt.totemCooldownSweepDirection)
	-- ShamanPower Minimal draws the sweep as a flat dark band (ShamanPowerThemeBoxes.lua): a band has no
	-- picture to stretch, so it fills from the chosen edge itself, with no gray copy under it
	local band = (self.ThemeMinimal and self:ThemeMinimal("tb.sweep")) and true or false
	running = running and true or false
	if btn._engineCDKey and btn._ecdSpell == spellID and btn._ecdRunning == running and btn._ecdStyle == style
		and btn._ecdFromTop == fromTop and btn._ecdBand == band then return end
	btn._engineCDKey, btn._ecdSpell, btn._ecdRunning, btn._ecdStyle = true, spellID, running, style
	btn._ecdFromTop = fromTop
	btn._ecdBand = band
	if btn.cdSweep then btn.cdSweep:Hide() end   -- the addon's own vertical sweep: never on this path
	if not (spellID and running) then
		self:DisarmEngineCooldownEnd(cd)
		cd:Clear()
		if btn.cdBar then btn.cdBar:Hide() end
		return
	end
	local ok, d = pcall(C_Spell.GetSpellCooldownDuration, spellID, true)   -- true: the global cooldown is not one
	if not ok or d == nil then
		self:DisarmEngineCooldownEnd(cd)
		cd:Clear()
		if btn.cdBar then btn.cdBar:Hide() end
		btn._engineCDKey = nil   -- ask again next pass
		return
	end
	if style == "radial" then
		cd:SetDrawSwipe(true)
		cd:SetDrawEdge(self.opt.totemCooldownEdge ~= false)
		if btn.cdBar then btn.cdBar:Hide() end
	else
		cd:SetDrawSwipe(false)   -- the numbers stay; the sweep is the bar
		cd:SetDrawEdge(false)    -- and the radial swipe's travelling edge goes with it
		local bar = self:TotemEngineSweepBar(btn, fromTop and not band)
		if bar then
			local Dir = Enum and Enum.StatusBarTimerDirection or {}
			local Interp = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate
			-- the gray copy grows with the time gone (Grays Out) or shrinks with the time
			-- left (Fills Back In); a colored fill (gray from the top) runs the other way
			local grayGrows = style ~= "reverse"
			local direction
			if band then
				bar:SetReverseFill(fromTop)   -- (Minimal's band: from the chosen edge, the timer as it reads)
				if grayGrows then direction = Dir.ElapsedTime else direction = Dir.RemainingTime end
			elseif grayGrows ~= fromTop then direction = Dir.ElapsedTime else direction = Dir.RemainingTime end
			local okb = pcall(bar.SetTimerDuration, bar, d, Interp, direction)
			bar:SetShown(okb and true or false)
		end
	end
	self:WatchEngineCooldownEnd(cd)
	pcall(cd.SetCooldownFromDurationObject, cd, d, true)   -- clearIfZero
end

-- WoW: Forever: is a button's spell on a real cooldown (longer than the global
-- one)? The game's never-secret flags answer (SPCompat.CooldownRunning: read when
-- SPELL_UPDATE_COOLDOWN is handled, kept between); the estimate (the shadow
-- model's numbers, or the readable ones) answers only when the game never has. The
-- game is asked afresh when the engine's widget says the cooldown it drew ended
-- (a wake-up, never the answer), and when the estimate's run has just ended while
-- the flags still say cooling (at most five times, half a second apart: the end
-- signal may not come). A button that was really cooling stays so when the only
-- news is the global cooldown (a cast in its last 1.5 s: it ends before that
-- global cooldown does, so at most 1.5 s more) or no answer at all, until the
-- flags say otherwise, the widget says done, or the estimate's run ends: no early
-- clear, no flicker. Nothing here looks at a number.
function ShamanPower:EngineCooldownRunning(btn, spellID, estimate)
	local running = SPCompat and SPCompat.CooldownRunning
	if not (running and spellID and self:EngineCooldownsOn()) then return estimate end
	if btn._cdSpell ~= spellID then
		btn._cdSpell, btn._cdReal, btn._cdRechecks, btn._cdRecheckAt = spellID, nil, nil, nil
		btn._cdEstWas, btn._cdDone, btn._cdFresh, btn._cdHold = nil, nil, nil, nil
	end
	if estimate then btn._cdRechecks, btn._cdRecheckAt = nil, nil end   -- a run of its own: its end gets the checks
	local done, estEnded = btn._cdDone, btn._cdEstWas and not estimate
	local how
	if btn._cdFresh then
		btn._cdFresh, how = nil, "now"
	elseif btn._cdReal == true and not estimate and (btn._cdEstWas or btn._cdRechecks) then
		local now, n = GetTime(), btn._cdRechecks or 0
		if n < 5 and now >= (btn._cdRecheckAt or 0) then
			btn._cdRechecks, btn._cdRecheckAt, how = n + 1, now + 0.5, "now"
		end
	end
	btn._cdEstWas, btn._cdDone = estimate and true or nil, nil
	local real, why = running(spellID, how)
	local hold = btn._cdHold
	btn._cdHold = nil
	if btn._cdReal == true and not (done or estEnded) then
		if real == nil then
			real = true   -- no answer: still the cooldown it was
		elseif why == "gcd" then
			local now = GetTime()
			hold = hold or (now + 1.5)   -- what is left of it ends within the global cooldown
			if now < hold then real, btn._cdHold = true, hold end
		end
	end
	if real == true then
		if done then self:ArmEngineCooldownEnd(btn.cooldown) end   -- still drawing it: its end still counts
	else
		btn._cdRechecks, btn._cdRecheckAt = nil, nil
	end
	btn._cdReal = real
	if real == nil then return estimate end
	return real
end

-- The widget handed a real duration object fires OnCooldownDone when that runs
-- out. Not in the client's docs, so only a wake-up: the button's next pass, on
-- the next frame, asks the game's flags afresh and they decide. Only a widget
-- armed by a hand-over counts (one signal each): never one the addon cleared.
function ShamanPower.EngineCooldownDone(cd)
	local armed = ShamanPower._cdArmed
	if not (armed and armed[cd]) then return end
	armed[cd] = nil
	local btn = cd:GetParent()
	if btn then btn._cdFresh, btn._cdDone = true, true end
	local sp = ShamanPower
	sp._barWake = true
	sp:WakeUpdateSubsystem("progressBars")
	sp:WakeUpdateSubsystem("cooldownBar")
end

-- Right before a duration object is handed over: watch that widget's end.
function ShamanPower:WatchEngineCooldownEnd(cd)
	if self._cdDoneWatched == nil then
		self._cdDoneWatched = setmetatable({}, { __mode = "k" })
		self._cdArmed = setmetatable({}, { __mode = "k" })
	end
	self._cdArmed[cd] = true
	if self._cdDoneWatched[cd] then return end
	self._cdDoneWatched[cd] = true
	pcall(cd.HookScript, cd, "OnCooldownDone", ShamanPower.EngineCooldownDone)
end

function ShamanPower:ArmEngineCooldownEnd(cd)
	if cd and self._cdArmed and self._cdDoneWatched[cd] then self._cdArmed[cd] = true end
end

-- Right before the addon clears a widget itself: that is not a cooldown ending.
function ShamanPower:DisarmEngineCooldownEnd(cd)
	local armed = self._cdArmed
	if armed and cd then armed[cd] = nil end
end

-- Whether the SPELL_UPDATE_COOLDOWN being handled can have changed this button's
-- spell: it names no spell (all cooldowns), it names this spell in any rank, this
-- button has no answer yet (its first event decides it), or it is cooling (the
-- global cooldown may now outlast what is left of it). A spell's own cooldown
-- starts only with an event that names it; for a ready one, the others only bring
-- the global cooldown, which the kept answer already covers.
function ShamanPower:CooldownEventConcerns(btn, evID, evBase, evName)
	if evID == nil or btn._cdReal ~= false then return true end
	local spell = btn._cdSpell
	if spell == evID or spell == evBase then return true end
	return evName ~= nil and GetSpellInfo(spell) == evName
end

-- Switched off: no button is read on cooldown events (the first pass after
-- switching on starts them again).
function ShamanPower:ForgetEngineCooldownReads()
	for element = 1, 4 do
		local btn = self.totemButtons and self.totemButtons[element]
		if btn then btn._cdSpell = nil end
		local flyout = self.totemFlyouts and self.totemFlyouts[element]
		local list = flyout and flyout.buttons
		if list then for i = 1, #list do list[i]._cdSpell = nil end end
	end
	local cds = self.cooldownButtons
	if cds then for i = 1, #cds do cds[i]._cdSpell = nil end end
end

-- A duration object holds a fixed time span; it does not follow the spell
-- (Forever's LuaDurationObject docs). A running cooldown shortened, lengthened
-- or reset mid-fight would keep the old pace on screen, so each
-- SPELL_UPDATE_COOLDOWN marks the running ones to be handed over again on the
-- next pass: a few buttons at most, one duration object each. atEvent (the
-- event itself, from SPCompat): the flags of the spells it concerns are read now,
-- the one moment isOnGCD can be trusted. The pass after it would have read each
-- of them anyway (the event empties the cache); now it finds these.
function ShamanPower:RefreshEngineCooldowns(atEvent)
	if not self:EngineCooldownsOn() then return end
	local read = atEvent and not self:IsOff() and SPCompat and SPCompat.CooldownRunning
	local evID, evBase, evName
	if read and SPCompat.CooldownEventSpell then
		evID, evBase = SPCompat.CooldownEventSpell()
		if evID then evName = GetSpellInfo(evID) end
	end
	for element = 1, 4 do
		local btn = self.totemButtons and self.totemButtons[element]
		if btn then
			if btn._ecdRunning then btn._engineCDKey = nil end
			if read and btn._cdSpell and self:CooldownEventConcerns(btn, evID, evBase, evName) then
				read(btn._cdSpell, "event")
			end
		end
		local flyout = self.totemFlyouts and self.totemFlyouts[element]
		local list = flyout and flyout.buttons
		if list then
			for i = 1, #list do
				local b = list[i]
				if b._ecdRunning then b._engineCDKey = nil end
				if read and b._cdSpell and b:IsVisible() and self:CooldownEventConcerns(b, evID, evBase, evName) then
					read(b._cdSpell, "event")
				end
			end
		end
	end
	local cds = self.cooldownButtons
	if cds then
		for i = 1, #cds do
			local b = cds[i]
			if b._ebSpell then b._ebStale = true end
			if read and b._cdSpell and b:IsVisible() and self:CooldownEventConcerns(b, evID, evBase, evName) then
				read(b._cdSpell, "event")
			end
		end
	end
end
-- SPCompat hands SPELL_UPDATE_COOLDOWN on right after emptying its cooldown cache
if SPCompat and SPCompat.OnCooldownEvent then
	SPCompat.OnCooldownEvent(function() ShamanPower:RefreshEngineCooldowns(true) end)
end

-- Update cooldown displays on totem buttons and flyout buttons
function ShamanPower:UpdateTotemCooldowns()
	local drawing = false   -- any cooldown on screen? decides whether the loop keeps ticking this
	local engine = self:EngineCooldownsOn()   -- the engine draws and counts; this pass only hands it changes
	-- Update main totem buttons
	for element = 1, 4 do
		local btn = self.totemButtons[element]
		if btn and btn.cooldown and btn.compactLayoutOn then
			-- Compact style: no cooldown sweep on a line
			self:ClearTotemCooldownVisual(btn)
			if btn.cooldownText then btn.cooldownText:Hide() end
		elseif btn and btn.cooldown then
			-- Get the assigned totem's spell ID (a flyout pick made in this fight: the one the button casts)
			local totemIndex = self:AssignedIndex(element)
			local spellID = nil

			if totemIndex and totemIndex > 0 then
				spellID = self:GetTotemSpell(element, totemIndex)
			end

			if spellID then
				local start, duration, enabled = GetSpellCooldown(spellID)
				-- Only show cooldown if it's longer than GCD (1.5 sec)
				if engine then
					local estimate = start and duration and duration > 1.5 and enabled == 1
					self:FeedEngineCooldown(btn, spellID, self:EngineCooldownRunning(btn, spellID, estimate))
				elseif start and duration and duration > 1.5 and enabled == 1 then
					self:ApplyTotemCooldownVisual(btn, start, duration); drawing = true
					-- Calculate remaining time for text
					local remaining = (start + duration) - GetTime()
					if remaining > 0 and btn.cooldownText and self.opt.totemCooldownText ~= false then
						btn.cooldownText:SetText(FormatCooldownTime(remaining))
						btn.cooldownText:Show()
					elseif btn.cooldownText then
						btn.cooldownText:Hide()
					end
				else
					self:ClearTotemCooldownVisual(btn)
					if btn.cooldownText then
						btn.cooldownText:Hide()
					end
				end
			else
				self:ClearTotemCooldownVisual(btn)
				if btn.cooldownText then
					btn.cooldownText:Hide()
				end
			end
		end
	end

	-- Update flyout buttons
	for element = 1, 4 do
		local flyout = self.totemFlyouts[element]
		if flyout and flyout.buttons then
			for _, btn in ipairs(flyout.buttons) do
				-- Only a flyout that is actually on screen: every cooldown read on a
				-- Mainline client builds a table (C_Spell.GetSpellCooldown), and this ran
				-- for every flyout button ten times a second whether or not any flyout
				-- was open. An opening flyout is caught up within one tick.
				if btn.cooldown and btn.spellID and btn:IsVisible() then
					local start, duration, enabled = GetSpellCooldown(btn.spellID)
					-- Only show cooldown if it's longer than GCD (1.5 sec)
					if engine then
						local estimate = start and duration and duration > 1.5 and enabled == 1
						self:FeedEngineCooldown(btn, btn.spellID, self:EngineCooldownRunning(btn, btn.spellID, estimate))
					elseif start and duration and duration > 1.5 and enabled == 1 then
						self:ApplyTotemCooldownVisual(btn, start, duration); drawing = true
						-- Calculate remaining time for text
						local remaining = (start + duration) - GetTime()
						if remaining > 0 and btn.cooldownText and self.opt.totemCooldownText ~= false then
							btn.cooldownText:SetText(FormatCooldownTime(remaining))
							btn.cooldownText:Show()
						elseif btn.cooldownText then
							btn.cooldownText:Hide()
						end
					else
						self:ClearTotemCooldownVisual(btn)
						if btn.cooldownText then
							btn.cooldownText:Hide()
						end
					end
				end
			end
		end
	end	self._totemCdShown = drawing
end

-- Update progress bars on popped-out single totems
function ShamanPower:UpdatePoppedOutProgressBars()
	if not self.poppedOutProgressBars then return end

	local textLocation = self.opt.durationTextLocation or "none"
	local barSize = self.opt.durationBarHeight or 3

	for key, bars in pairs(self.poppedOutProgressBars) do
		local frame = self.poppedOutFrames[key]
		if frame and bars.element and bars.spellName then
			local haveTotem, activeTotemName, startTime, duration = self:GetElementTotemInfo(bars.element)

			-- Check if this pop-out's totem is the active one
			local isActive = false
			if haveTotem and activeTotemName and bars.spellName then
				local ok1, result1 = pcall(string.find, activeTotemName, bars.spellName, 1, true)
				local ok2, result2 = pcall(string.find, bars.spellName, activeTotemName, 1, true)
				if (ok1 and result1) or (ok2 and result2) then
					isActive = true
				end
			end

			if isActive and duration and duration > 0 then
				local remaining = (startTime + duration) - GetTime()
				local pct = remaining / duration

				if pct > 0 and pct <= 1 then
					-- Update bar size
					local width = (bars.maxWidth or 32) * pct
					bars.bar:SetWidth(math.max(1, width))
					bars.bar:SetHeight(barSize)
					bars.bg:SetHeight(barSize)
					bars.bg:Show()
					bars.bar:Show()

					-- Update duration text if option is set to show on icon
					if textLocation == "icon" then
						local durationStr = FormatDuration(remaining)
						bars.text:SetText(durationStr)
						bars.text:Show()
					else
						bars.text:Hide()
					end
				else
					bars.bg:Hide()
					bars.bar:Hide()
					bars.text:Hide()
				end
			else
				bars.bg:Hide()
				bars.bar:Hide()
				bars.text:Hide()
			end
		end
	end
end

-- Update progress bar size when option changes
function ShamanPower:UpdateTotemProgressBarHeight()
	local barSize = self.opt.durationBarHeight or 3
	local barPosition = self.opt.durationBarPosition or "bottom"
	local isVertical = (barPosition == "left" or barPosition == "right" or barPosition == "top_vert" or barPosition == "bottom_vert")

	for element = 1, 4 do
		local bars = self.totemProgressBars[element]
		if bars then
			if isVertical then
				bars.bg:SetWidth(barSize)
				bars.bar:SetWidth(barSize)
			else
				bars.bg:SetHeight(barSize)
				bars.bar:SetHeight(barSize)
			end

			-- Update inside text font size based on bar size
			if bars.insideText then
				local fontSize = math.max(7, barSize - 2)
				ShamanPower:SetSPFont(bars.insideText, "timers", fontSize, "OUTLINE")
			end
		end
	end

	-- Re-position bars to update anchors
	self:UpdateTotemProgressBarPositions()
end

-- ============================================================================
-- Active Totem Overlay (shows actual totem when different from assigned)
-- ============================================================================

ShamanPower.activeTotemOverlays = {}

-- Flyout vertical direction. "auto" is screen-aware: the flyout extends
-- downward when the bar sits in the top part of the screen, upward otherwise
-- (issue #20 - flyouts used to always extend up and could run off screen).
function ShamanPower:FlyoutGoesBelow(anchorBtn)
	local dir = self.opt.totemFlyoutDirection or "auto"
	if dir == "below" then return true end
	if dir == "above" then return false end
	-- Auto is decided by where the BAR sits (one decision for the totem
	-- flyouts, the ES flyout and the dropped-totem indicators together), with
	-- a dead zone so a bar near the middle of the screen cannot flip back and
	-- forth as the container resizes by a few pixels.
	local bar = _G["ShamanPowerFrame"] or self.autoButton or anchorBtn
	local below = self._flyoutAutoBelow or false
	if bar then
		local _, cy = bar:GetCenter()
		if cy then
			local frac = cy * bar:GetEffectiveScale() / (UIParent:GetHeight() * UIParent:GetEffectiveScale())
			if below then
				if frac < 0.45 then below = false end
			else
				if frac > 0.60 then below = true end
			end
			self._flyoutAutoBelow = below
		end
	end
	return below
end

-- Where the dropped-totem indicator (and the ES one) pops out, relative to
-- its button. opt.activeOverlayDirection: "auto" follows the bar layout -
-- above a horizontal bar, on the flyout side of a vertical one (issue #20).
function ShamanPower:GetActiveOverlayAnchor()
	local dir = self.opt.activeOverlayDirection or "auto"
	if dir == "auto" then
		if self.opt.layout == "VerticalLeft" then dir = "left"
		elseif self.opt.layout == "Vertical" then dir = "right"
		else dir = self:FlyoutGoesBelow() and "below" or "above" end
	end
	-- fifth return: the side of the button it sits on, in FlyoutDirection's terms
	if dir == "below" then return "TOP", "BOTTOM", 0, -2, "bottom"
	elseif dir == "left" then return "RIGHT", "LEFT", -2, 0, "left"
	elseif dir == "right" then return "LEFT", "RIGHT", 2, 0, "right"
	end
	return "BOTTOM", "TOP", 0, 2, "top"
end

function ShamanPower:PositionActiveOverlays()
	local p, rp, ox, oy, side = self:GetActiveOverlayAnchor()
	-- In combat the flyout arrow sits against the totem button; an overlay on the
	-- same side moves out past it rather than covering it. Its own pulse bar or
	-- party dots on the side facing the button would then land on the tab, so the
	-- overlay leaves room for those too.
	local facing = (side == "top" and "below") or (side == "bottom" and "above") or (side == "left" and "right") or "left"
	local pulsePos = self.opt.pulseBarPosition or "on_icon"
	local reach = (pulsePos == facing) and (1 + (self.opt.pulseBarSize or 4)) or 0
	local reachVert = (side == "top" and pulsePos == "below_vert") or (side == "bottom" and pulsePos == "above_vert")
	if self.opt.showPartyRangeDots and IsInGroup() and (self.opt.partyDotPosition or "corners") == facing then
		reach = math.max(reach, 2 + (self.opt.partyDotSize or 5))
	end
	for element = 1, 4 do
		local ov = self.activeTotemOverlays and self.activeTotemOverlays[element]
		local btn = self.totemButtons and self.totemButtons[element]
		-- (a plain frame; one made protected by something secure anchored to it is left alone in a fight)
		if ov and ov.frame and btn and not (InCombatLockdown() and ov.frame:IsProtected()) then
			local gx, gy = 0, 0
			local aT, aB, aL, aR = self:FlyoutArrowPads(btn)
			local gap = (side == "top" and aT) or (side == "bottom" and aB) or (side == "left" and aL) or aR
			if gap > 0 then
				gap = gap + (reachVert and math.max(reach, 1 + ov.frame:GetHeight()) or reach)
				if side == "top" then gy = gap
				elseif side == "bottom" then gy = -gap
				elseif side == "left" then gx = -gap
				else gx = gap end
			end
			ov.frame:ClearAllPoints()
			ov.frame:SetPoint(p, btn, rp, ox + gx, oy + gy)
		end
	end
	local esOv = self.esActiveOverlay
	local esBtn = _G["ShamanPowerEarthShieldBtn"]
	if esOv and esOv.frame and esBtn then
		esOv.frame:ClearAllPoints()
		esOv.frame:SetPoint(p, esBtn, rp, ox, oy)
	end
end

function ShamanPower:CreateActiveTotemOverlay(element)
	local totemButton = self.totemButtons[element]
	if not totemButton then return nil end

	local overlay = {}

	-- Create a frame to hold the active totem icon (appears above the button)
	local frame = CreateFrame("Frame", "ShamanPowerActiveOverlay" .. element, totemButton)
	frame:SetSize(26, 26)
	do
		local p, rp, ox, oy = self:GetActiveOverlayAnchor()
		frame:SetPoint(p, totemButton, rp, ox, oy)
	end
	frame:SetFrameLevel(totemButton:GetFrameLevel() + 5)
	frame:Hide()

	-- Background
	local bg = frame:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.7)
	overlay.bg = bg

	-- Icon for the active totem
	local icon = frame:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("TOPLEFT", 2, -2)
	icon:SetPoint("BOTTOMRIGHT", -2, 2)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	overlay.icon = icon

	-- Border with element color
	local colors = self.ElementColors[element]
	local borderSize = 2
	local r, g, b = colors.r, colors.g, colors.b

	local borderTop = frame:CreateTexture(nil, "BORDER")
	borderTop:SetPoint("TOPLEFT", 0, 0)
	borderTop:SetPoint("TOPRIGHT", 0, 0)
	borderTop:SetHeight(borderSize)
	borderTop:SetColorTexture(r, g, b, 1)

	local borderBottom = frame:CreateTexture(nil, "BORDER")
	borderBottom:SetPoint("BOTTOMLEFT", 0, 0)
	borderBottom:SetPoint("BOTTOMRIGHT", 0, 0)
	borderBottom:SetHeight(borderSize)
	borderBottom:SetColorTexture(r, g, b, 1)

	local borderLeft = frame:CreateTexture(nil, "BORDER")
	borderLeft:SetPoint("TOPLEFT", 0, 0)
	borderLeft:SetPoint("BOTTOMLEFT", 0, 0)
	borderLeft:SetWidth(borderSize)
	borderLeft:SetColorTexture(r, g, b, 1)

	local borderRight = frame:CreateTexture(nil, "BORDER")
	borderRight:SetPoint("TOPRIGHT", 0, 0)
	borderRight:SetPoint("BOTTOMRIGHT", 0, 0)
	borderRight:SetWidth(borderSize)
	borderRight:SetColorTexture(r, g, b, 1)
	-- kept so a General > Themes change can repaint them (tb.overlay-border)
	overlay.spEdges = { borderTop, borderBottom, borderLeft, borderRight }
	self:ThemePaintOverlayBorder(overlay, element)

	-- Create pulse wipe frame on this frame
	local wipeFrame = CreateFrame("Frame", nil, frame)
	wipeFrame:SetFrameLevel(frame:GetFrameLevel() + 1)
	overlay.wipeFrame = wipeFrame

	local wipe = wipeFrame:CreateTexture(nil, "OVERLAY")
	ShamanPower:SetSPBarColor(wipe, "pulse", 1, 1, 1, 0.7)  -- White for visibility
	wipe:Hide()
	overlay.wipe = wipe
	self:ThemePaintPulse(overlay, element)   -- tb.pulse; nothing on Standard
	overlay.buttonWidth = frame:GetWidth() - 4
	overlay.buttonHeight = frame:GetHeight() - 4

	-- Position the wipe based on option (will be called after creation)
	self:PositionOverlayPulseWipe(overlay, frame)

	-- Create pulse glow textures on this frame
	overlay.glows = {}
	for i = 1, 3 do
		local glow = frame:CreateTexture(nil, "OVERLAY", nil, 7)
		local offset = 6 + (i * 4)
		glow:SetPoint("TOPLEFT", frame, "TOPLEFT", -offset, offset)
		glow:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", offset, -offset)
		glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
		if ShamanPower.ShapeGlow then ShamanPower:ShapeGlow(glow, "border") end   -- Glow Shape
		glow:SetBlendMode("ADD")
		glow:SetVertexColor(0.4, 1, 0.4)
		glow:SetAlpha(0)
		overlay.glows[i] = glow
	end

	-- Create range dots on this frame
	overlay.dots = {}
	for i = 1, 4 do
		local dot = frame:CreateTexture(nil, "OVERLAY")
		dot:SetTexture("Interface\\AddOns\\ShamanPower\\textures\\dot")
		dot:SetSize(5, 5)
		dot:SetVertexColor(1, 1, 1)
		dot:Hide()
		overlay.dots[i] = dot
	end
	self:PositionPartyDots(overlay.dots, frame)

	-- Create pulse time text elements (same as main pulse overlay)
	-- Time text inside the bar (top)
	local barTimeTextTop = wipeFrame:CreateFontString(nil, "OVERLAY")
	ShamanPower:SetSPFont(barTimeTextTop, "timers", 9, "OUTLINE")
	barTimeTextTop:SetPoint("TOP", wipeFrame, "TOP", 0, -1)
	barTimeTextTop:SetTextColor(1, 1, 1)
	barTimeTextTop:Hide()
	overlay.barTimeTextTop = barTimeTextTop

	-- Time text inside the bar (bottom)
	local barTimeTextBottom = wipeFrame:CreateFontString(nil, "OVERLAY")
	ShamanPower:SetSPFont(barTimeTextBottom, "timers", 9, "OUTLINE")
	barTimeTextBottom:SetPoint("BOTTOM", wipeFrame, "BOTTOM", 0, 1)
	barTimeTextBottom:SetTextColor(1, 1, 1)
	barTimeTextBottom:Hide()
	overlay.barTimeTextBottom = barTimeTextBottom

	-- Time text above the bar
	local aboveTimeText = wipeFrame:CreateFontString(nil, "OVERLAY")
	ShamanPower:SetSPFont(aboveTimeText, "timers", 9, "OUTLINE")
	aboveTimeText:SetPoint("BOTTOM", wipeFrame, "TOP", 0, 1)
	aboveTimeText:SetTextColor(1, 1, 1)
	aboveTimeText:Hide()
	overlay.aboveTimeText = aboveTimeText

	-- Time text below the bar
	local belowTimeText = wipeFrame:CreateFontString(nil, "OVERLAY")
	ShamanPower:SetSPFont(belowTimeText, "timers", 9, "OUTLINE")
	belowTimeText:SetPoint("TOP", wipeFrame, "BOTTOM", 0, -1)
	belowTimeText:SetTextColor(1, 1, 1)
	belowTimeText:Hide()
	overlay.belowTimeText = belowTimeText

	-- Time text on the icon
	local iconTimeText = frame:CreateFontString(nil, "OVERLAY")
	ShamanPower:SetSPFont(iconTimeText, "timers", 10, "OUTLINE")
	iconTimeText:SetPoint("CENTER", frame, "CENTER", 0, 0)
	iconTimeText:SetTextColor(1, 1, 1)
	iconTimeText:Hide()
	overlay.iconTimeText = iconTimeText

	-- Time text: only touched when the shown tenths change (see PulseVisualText)
	overlay.UpdateTime = function(self, timeRemaining, displayOption)
		ShamanPower:PulseVisualText(self, timeRemaining, displayOption)
	end

	overlay.HideTime = function(self)
		ShamanPower:PulseVisualHideText(self)
	end

	overlay.frame = frame
	overlay.buttonHeight = frame:GetHeight() - 4
	return overlay
end

-- UpdateActiveTotemOverlays only applies state (which overlay is up, which icon, what
-- is greyed): nothing in it moves with time, yet the 10 Hz bar loop ran it on every
-- tick (measured with /spperf: over half of that loop's cost in combat). From the
-- loop it now runs when a totem or an assignment changed, when something asked
-- (_ovWake), and once a second as a safety net. Direct callers are unaffected.
function ShamanPower:UpdateActiveTotemOverlaysIfDue()
	local now = GetTime()
	local a = ShamanPower_Assignments and self.player and ShamanPower_Assignments[self.player]
	local a1, a2, a3, a4 = a and a[1], a and a[2], a and a[3], a and a[4]
	if not self._ovWake and self._ovGen == self._totemInfoGen and (now - (self._ovAt or 0)) < 1
		and self._ovA1 == a1 and self._ovA2 == a2 and self._ovA3 == a3 and self._ovA4 == a4 then
		return
	end
	self._ovWake, self._ovGen, self._ovAt = nil, self._totemInfoGen, now
	self._ovA1, self._ovA2, self._ovA3, self._ovA4 = a1, a2, a3, a4
	self:UpdateActiveTotemOverlays()
end

function ShamanPower:UpdateActiveTotemOverlays()
	if self.GridActive and self:GridActive() then
		self:UpdateGridTotems()
		self:UpdatePoppedOutActiveBorders()
		return
	end
	-- A native/loadout cast need not have a custom-bar assignment.
	if self.UsingBlizzardTotemBar and self:UsingBlizzardTotemBar() then
		self:UpdateBlizzardTotemOverlays()
		self:UpdatePoppedOutActiveBorders()
		return
	end
	-- Safety checks for early calls before addon is fully initialized
	if not self.player then return end
	if not self.ElementToSlot then return end
	if not self.Totems then return end
	if not ShamanPower_Assignments then return end

	-- No saved assignments yet: nothing to compare with, unless the first one was
	-- picked in this fight (it waits in pendingAssignments until the fight ends)
	if not ShamanPower_Assignments[self.player] and not self.pendingAssignments then return end

	-- Compact style: the line is whatever is down, no pop-above overlay. Nor with Totem Rows carrying the
	-- hidden bar's pieces: the row's totem that is down is the one shown (and the party dots stay on the row)
	if self:CompactActive() or (self.RowsCarryBar and self:RowsCarryBar()) then
		self:HideActiveTotemOverlaysForCompact()
		return
	end

	for element = 1, 4 do
		-- Create overlay if needed
		if not self.activeTotemOverlays[element] then
			self.activeTotemOverlays[element] = self:CreateActiveTotemOverlay(element)
			-- A new overlay is anchored flat against its button. When the flyout arrow
			-- tabs are showing it has to sit out past them, and nothing re-ran that
			-- placement for overlays created late (first seen coming back from Compact
			-- with the arrows always on: the tab was drawn over the overlay).
			self:PositionActiveOverlays()
		end

		local overlay = self.activeTotemOverlays[element]

		if overlay then
			local haveTotem, totemName, startTime, duration = self:GetElementTotemInfo(element)

			-- Get assigned totem info (a right-click assign made in this fight waits in
			-- pendingAssignments until it ends: the button already shows it, so compare with it)
			local assignedIndex = self:AssignedIndex(element)
			local assignedSpellID = nil
			local assignedName = nil
			if assignedIndex > 0 then
				assignedSpellID = self:GetTotemSpell(element, assignedIndex)
				if assignedSpellID then
					assignedName = GetSpellInfo(assignedSpellID)
				end
			end

			-- Get the main icon texture
			local totemBtn = self.totemButtons[element]
			local iconTexture = totemBtn and totemBtn.icon

			-- Check if active totem differs from assigned
			local showOverlay = false
			local activeIcon = nil

			-- Working out whether the dropped totem differs from the assigned one, and which
			-- icon it gets, walks the element's totems with name lookups and string finds.
			-- That answer only changes with the totem or the assignment, so it is kept on the
			-- overlay and redone when either changes; the ten-a-second part is the timer
			-- drawing further down. (Not kept for Air while twisting: that rule has more inputs.)
			local twistingAir = (element == 4 and self.opt and self.opt.enableTotemTwisting) and true or false
			local nowName, nowHave = totemName or false, haveTotem and true or false
			local kept = (not twistingAir) and overlay.cName == nowName and overlay.cHave == nowHave and overlay.cAssigned == assignedIndex

			if kept then
				showOverlay, activeIcon = overlay.cShow, overlay.cIcon
			elseif haveTotem and totemName and totemName ~= "" then
				-- Check if active totem matches assigned
				local matches = false
				if SPCompat.HasTotemCastAliases(assignedSpellID) then
					matches = SPCompat.TotemNameMatches(totemName, assignedSpellID)
				end

				-- Use pcall for string.find in case of pattern issues
				if not matches and assignedName then
					local ok1, result1 = pcall(string.find, totemName, assignedName, 1, true)
					local ok2, result2 = pcall(string.find, assignedName, totemName, 1, true)
					if (ok1 and result1) or (ok2 and result2) then
						matches = true
					end
				end

				-- Special case: totem twisting on Air with TotemTimers mode
				-- In this mode, the main icon always shows the active totem, so no overlay needed
				if element == 4 and self.opt and self.opt.enableTotemTwisting and self.opt.activeTotemAsMain then
					-- Any Air totem matches - the main icon will show whatever is active
					matches = true
				elseif element == 4 and self.opt and self.opt.enableTotemTwisting then
					-- Classic mode: Windfury or selected twist totem match
					local twistName = self:GetTwistTotemName()
					if SPCompat.TotemNameMatches(totemName, 8512, "Windfury Totem") or totemName:find(twistName, 1, true) then
						matches = true
					end
				end

				if not matches then
					-- Different totem is active - find its icon
					showOverlay = true
					-- Try to find the icon for the active totem
					local totems = self.Totems[element]
					if totems then
						for idx, totemSpellID in pairs(totems) do
							-- totemSpellID is directly the spell ID number
							if totemSpellID and type(totemSpellID) == "number" then
								local totemSpellName = GetSpellInfo(totemSpellID)
								if totemSpellName then
									local ok, found = pcall(string.find, totemName, totemSpellName, 1, true)
									if SPCompat.HasTotemCastAliases(totemSpellID)
										and SPCompat.TotemNameMatches(totemName, totemSpellID) then ok, found = true, true end
									if ok and found then
										activeIcon = self:GetTotemIcon(element, idx)
										break
									end
								end
							end
						end
					end
					-- Fallback: try to get icon from spell name directly
					if not activeIcon then
						local _, _, icon = GetSpellInfo(totemName)
						activeIcon = icon
					end
				end
			end

			if not kept and not twistingAir then
				overlay.cName, overlay.cHave, overlay.cAssigned, overlay.cShow, overlay.cIcon = nowName, nowHave, assignedIndex, showOverlay, activeIcon
			end

			local totemButton = self.totemButtons[element]
			local useActiveAsMain = self.opt.activeTotemAsMain

			-- TotemTimers Style hides the totem that is DOWN from the flyout (the others
			-- hide the assigned one), so a drop changes the hidden choice. Only a hover
			-- redrew it: a flyout left open after a pick kept a gap and a stale button.
			-- Redrawn here when the totem changes (out of combat; the flyout's buttons
			-- are secure, and a fight's change is picked up once it ends).
			if useActiveAsMain and not twistingAir and not InCombatLockdown() and overlay.cFlyName ~= nowName then
				overlay.cFlyName, overlay.cFadeName = nowName, nowName
				self:UpdateFlyoutVisibility(element)
				self:SyncOpenFlyoutButtons(element)   -- an open flyout: its buttons too
			elseif useActiveAsMain and not twistingAir and overlay.cFadeName ~= nowName then
				-- mid-fight: arrow ("box") flyouts fade the totem that is down,
				-- and a fade is only a texture, so it follows a drop in combat too
				overlay.cFadeName = nowName
				self:MarkAssignedInFlyout(element)
			end

			if showOverlay and activeIcon then
				overlay.isActive = true

				if useActiveAsMain and totemButton then
					-- TotemTimers style: main icon shows active totem, corner shows assigned
					-- Hide the overlay frame (not needed in this mode)
					if overlay.frame then
						overlay.frame:Hide()
					end

					-- Change main button icon to active totem
					-- Note: Don't set desaturation here - let UpdatePlayerTotemRange handle it
					-- based on whether the player is in range of the totem buff
					if iconTexture then
						iconTexture:SetTexture(activeIcon)
						-- Don't call SetDesaturated - UpdatePlayerTotemRange handles range display
						iconTexture:SetAlpha(1)
					end
					-- Empty: the faded slot art would cover the totem that is down
					if assignedIndex == 0 and totemButton.emptyArt then totemButton.emptyArt:Hide() end

					-- Show assigned indicator in corner (none when nothing is assigned:
					-- index 0 has no icon, GetTotemIcon would give the question mark;
					-- none either with Show Assigned Totem in Corner off)
					if totemButton.assignedIndicator and totemButton.assignedIndicatorIcon then
						if assignedIndex > 0 and self.opt.activeAssignedCorner ~= false then
							totemButton.assignedIndicatorIcon:SetTexture(self:GetTotemIcon(element, assignedIndex))
							totemButton.assignedIndicator:Show()
						else
							totemButton.assignedIndicator:Hide()
						end
					end

					-- Use main button's pulse overlay (not the overlay's)
					-- The pulse will show on the active totem icon
				else
					-- Classic style: overlay shows active totem above the button
					if overlay.frame then
						overlay.icon:SetTexture(activeIcon)
						overlay.frame:Show()
					end

					-- Grey out the assigned totem icon
					if iconTexture then
						iconTexture:SetDesaturated(true)
						iconTexture:SetAlpha(0.5)
					end

					-- Hide assigned indicator (not used in this mode)
					if totemButton and totemButton.assignedIndicator then
						totemButton.assignedIndicator:Hide()
					end

					-- Hide main button's pulse overlay (we'll use overlay's)
					if self.pulseOverlays and self.pulseOverlays[element] then
						self:PulseVisualStop(self.pulseOverlays[element])
					end
				end

				-- Note: Range dots are handled by UpdatePartyRangeDots()
				-- which checks overlay.isActive and updates the correct dots
			else
				-- No active totem or same as assigned - restore normal state
				if overlay.frame then
					overlay.frame:Hide()
				end
				overlay.isActive = false

				-- Hide assigned indicator
				if totemButton and totemButton.assignedIndicator then
					totemButton.assignedIndicator:Hide()
				end

				-- Restore main button icon
				if useActiveAsMain and totemButton and iconTexture then
					-- Special case: Air totem with twisting - show the currently active totem icon
					if element == 4 and self.opt.enableTotemTwisting and haveTotem and totemName then
						-- Use hardcoded icons to avoid flicker from per-frame GetSpellInfo calls
						if SPCompat.TotemNameMatches(totemName, 8512, "Windfury Totem") then
							iconTexture:SetTexture("Interface\\Icons\\Spell_Nature_Windfury")
						else
							local twistName = self:GetTwistTotemName()
							if totemName:find(twistName, 1, true) then
								iconTexture:SetTexture(self:GetTwistTotemIcon())
							end
						end
					elseif assignedIndex > 0 then
						-- Normal case: show assigned totem icon
						iconTexture:SetTexture(self:GetTotemIcon(element, assignedIndex))
					else
						-- Nothing assigned: as the bar draws it (the element icon; Forever: the empty slot art)
						iconTexture:SetTexture(self.ElementIcons[element])
						self:ShowEmptySlotArt(element, true)
					end
				end

				-- Hide overlay's dots and pulse
				if overlay.dots then
					for i = 1, 4 do
						if overlay.dots[i] then overlay.dots[i]:Hide() end
					end
				end
				self:PulseVisualStop(overlay)

				-- Don't reset desaturation here - let UpdatePlayerTotemRange handle it
				-- based on whether the player is in range of the totem buff
				if iconTexture then
					iconTexture:SetAlpha(1)  -- Only restore alpha, not desaturation
				end
			end
		end
	end

	-- Update active borders on popped-out single totems
	self:UpdatePoppedOutActiveBorders()
end

-- Update active borders on popped-out single totems
function ShamanPower:UpdatePoppedOutActiveBorders()
	if not self.poppedOutFrames then return end

	for key, frame in pairs(self.poppedOutFrames) do
		if key:match("^single_") and frame.element and frame.spellName then
			local element = frame.element
			local haveTotem, activeTotemName = self:GetElementTotemInfo(element)

			local isActive = false
			if haveTotem and activeTotemName and frame.spellName then
				if SPCompat.HasTotemCastAliases(frame.spellID) then
					isActive = SPCompat.TotemNameMatches(activeTotemName, frame.spellID)
				end
				-- Check if active totem matches this pop-out's totem
				local ok1, result1 = pcall(string.find, activeTotemName, frame.spellName, 1, true)
				local ok2, result2 = pcall(string.find, frame.spellName, activeTotemName, 1, true)
				if (ok1 and result1) or (ok2 and result2) then
					isActive = true
				end
			end

			-- Show/hide active border
			if frame.activeBorder then
				if isActive then
					frame.activeBorder:Show()
				else
					frame.activeBorder:Hide()
				end
			end

			-- Desaturate/restore icon based on active state
			if frame.button and frame.button.icon then
				if isActive then
					frame.button.icon:SetDesaturated(false)
					frame.button.icon:SetAlpha(1)
				else
					-- Optionally desaturate when not active (matching main bar behavior)
					-- For now, keep it normal since it's a standalone tracker
					frame.button.icon:SetDesaturated(false)
					frame.button.icon:SetAlpha(1)
				end
			end
		end
	end
end

-- ============================================================================
-- Totem Flyout Menus (TotemTimers-style popup for selecting totems)
-- ============================================================================

ShamanPower.totemFlyouts = {}  -- Flyout frames for each element

-- Helper function to check if player knows a totem spell
-- Check every rank because Classic may only report the highest learned rank.
local function PlayerKnowsTotem(spellID)
	-- Any rank of the totem, by spell ID only, from this client's own rank list (SPCompat.KnowsSpellID).
	-- Never by name: "Flametongue" matched Flametongue Weapon and "Nature Resistance" the Tauren racial,
	-- so those totems showed (and were given to an empty slot) long before they were learned.
	return SPCompat.KnowsSpellID(spellID)
end

-- the same check by element and totem index, for the settings (loadout pickers mark what is not learned yet)
function ShamanPower:KnowsTotem(element, totemIndex)
	return PlayerKnowsTotem(self:GetTotemSpell(element, totemIndex))
end
ShamanPower.PlayerKnowsTotem = PlayerKnowsTotem

-- Track if we've already hooked the totem buttons
ShamanPower.flyoutHooksInstalled = {}

-- ============================================================================
-- POP-OUT TRACKERS
-- Allow any button to be "popped out" into a standalone, movable tracker
-- ============================================================================

-- Storage for popped-out frames by key
ShamanPower.poppedOutFrames = {}

-- Global lock for every pop-out tracker: no frame drag, no ALT-drag on the icon.
function ShamanPower:PopOutsLocked()
	return self.opt and self.opt.poppedOutLocked and true or false
end

function ShamanPower:SetPopOutsLocked(locked)
	self.opt.poppedOutLocked = locked and true or nil
	for _, frame in pairs(self.poppedOutFrames or {}) do
		if frame.SetMovable then frame:SetMovable(not locked) end
	end
end

-- Storage for pop-out pulse/active overlays (for single totem pop-outs)
ShamanPower.poppedOutOverlays = {}

-- Storage for pop-out duration bars (for single totem pop-outs)
ShamanPower.poppedOutProgressBars = {}

-- Create a pop-out frame container with cog wheel (top-right) and title below icon
-- ---------------------------------------------------------------------------
-- Flat panel look shared by the HUD frames (pop-outs, trackers). A plain
-- white texture tinted from code, so every frame matches the options UI
-- instead of the tooltip-style Blizzard backdrop.
-- ---------------------------------------------------------------------------
ShamanPower.PANEL_BACKDROP = {
	bgFile = "Interface\\Buttons\\WHITE8x8",
	edgeFile = "Interface\\Buttons\\WHITE8x8",
	edgeSize = 2,
	insets = { left = 0, right = 0, top = 0, bottom = 0 },
}
ShamanPower.PANEL_BG     = { 0.086, 0.098, 0.122, 0.92 }
ShamanPower.PANEL_BORDER = { 0.180, 0.204, 0.243, 1.00 }
ShamanPower.PANEL_ACCENT = { 0.000, 0.439, 0.867, 1.00 }

-- Size a pop-out frame so its label always fits: at least the icon plus
-- padding, wider when the name needs it. Scaling is uniform, so a frame that
-- fits at 1x fits at any scale.
function ShamanPower:FitPopOutFrame(frame)
	local buttonSize = frame.buttonSize or 32
	local cogSize = 12
	local textW, textH = 0, 12
	if frame.titleText then
		textW = frame.titleText:GetStringWidth() or 0
		textH = math.max(12, frame.titleText:GetStringHeight() or 12)
	end
	local width = math.max(buttonSize + 20, math.ceil(textW) + 16)
	local height = buttonSize + textH + cogSize + 12
	frame:SetSize(width, height)
end

-- Opened by the settings button on HUD frames; the ShamanPower_Config module
-- replaces this with the real panel. Without the module it does nothing.
function ShamanPower:OpenFrameSettings(key, frame) end

-- Rescale a frame around its on-screen centre instead of its anchor point.
-- SetScale alone scales the anchor offset too, so a frame anchored 300px from
-- the left edge ends up 600px away at 2x -- it slides as it grows.
local ANCHOR_POINTS = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }
local function AnchorXY(name, W, H)
	local x = (strfind(name, "LEFT") and 0) or (strfind(name, "RIGHT") and W) or W / 2
	local y = (strfind(name, "TOP") and H) or (strfind(name, "BOTTOM") and 0) or H / 2
	return x, y
end

-- Resolution-independent position: the frame's CENTER relative to the nearest
-- of UIParent's nine anchors, in UIParent units. A record survives resolution
-- and UI-scale changes and can be shared between players.
-- ---------------------------------------------------------------------------
-- Bar movers
-- A labelled, grab-anywhere overlay for repositioning a bar without its drag
-- handle. Non-secure (a sibling frame), so it never taints the bar's secure
-- children; on release it moves the real frame and saves a position record.
-- ---------------------------------------------------------------------------
ShamanPower.barMovers = ShamanPower.barMovers or {}
local MOVER_MIN_W, MOVER_MIN_H = 60, 24   -- a box is never smaller (an empty cooldown bar is 1x1)
local MOVER_PAD = 4                       -- label inset from the box's edges

-- The label wraps inside the box, never "...": remember its longest word, the
-- narrowest the box may get without splitting one.
local function SetBarMoverLabel(mover, label)
	if label == mover.spLabel then return end
	local text, wordW = mover.text, 0
	for word in label:gmatch("%S+") do
		text:SetText(word)
		wordW = math.max(wordW, (text.GetUnboundedStringWidth and text:GetUnboundedStringWidth()) or text:GetStringWidth())
	end
	text:SetText(label)
	mover.spLabel, mover.spWordW = label, math.ceil(wordW)
end

-- Every box on screen goes back over its frame a frame after a drop, once the
-- moved frames are laid out: read in the same frame as the SetPoint, a frame
-- can still report its old spot (and a cooldown bar on its default spot has
-- just followed the totem bar).
local function RefreshShownBarMovers()
	if InCombatLockdown() then return end
	for key, m in pairs(ShamanPower.barMovers) do
		if m:IsShown() and m.moveFrame then ShamanPower:ShowBarMover(key, m.moveFrame, m.sizeFrame, nil, m.onMoved) end
	end
end

function ShamanPower:GetBarMover(key, moveFrame, sizeFrame, label, onMoved)
	local mover = self.barMovers[key]
	if mover then
		mover.moveFrame, mover.sizeFrame, mover.onMoved = moveFrame, sizeFrame or moveFrame, onMoved
		if label then SetBarMoverLabel(mover, label) end
		return mover
	end
	mover = CreateFrame("Frame", "ShamanPowerMover_" .. key, UIParent)
	mover:SetFrameStrata("FULLSCREEN_DIALOG")
	mover:EnableMouse(true)
	mover:SetMovable(true)
	mover:RegisterForDrag("LeftButton")
	mover:Hide()

	local bg = mover:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(mover)
	bg:SetColorTexture(0, 0.439, 0.867, 0.35)
	local edge = {}
	for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
		local t = mover:CreateTexture(nil, "BORDER")
		t:SetColorTexture(0.247, 0.663, 1, 0.9)
		if side == "TOP" or side == "BOTTOM" then
			t:SetHeight(2); t:SetPoint(side .. "LEFT"); t:SetPoint(side .. "RIGHT")
		else
			t:SetWidth(2); t:SetPoint("TOP" .. side); t:SetPoint("BOTTOM" .. side)
		end
		edge[#edge + 1] = t   -- Unlock UI paints these gold on the picked box
	end
	local text = mover:CreateFontString(nil, "OVERLAY")
	text:SetFontObject("ShamanPowerDialogFontText")   -- ShamanPowerDialog.lua's row font
	text:SetPoint("CENTER")
	text:SetJustifyH("CENTER")
	text:SetWordWrap(true)
	mover.text = text
	mover.spEdges = edge   -- Unlock UI paints the picked box's edges gold

	-- In Unlock UI the box is dragged by hand so it can snap as it moves, and it
	-- takes the mouse wheel, clicks and the arrow keys (ShamanPowerUnlock.lua)
	mover:SetScript("OnDragStart", function(self)
		if ShamanPower.UnlockDragStart and ShamanPower:UnlockDragStart(self) then return end
		self:StartMoving()
	end)
	mover:SetScript("OnMouseUp", function(self, button)
		if ShamanPower.UnlockBoxClick then ShamanPower:UnlockBoxClick(self, button) end
	end)
	mover:SetScript("OnMouseWheel", function(self, delta)
		if ShamanPower.UnlockBoxWheel then ShamanPower:UnlockBoxWheel(self, delta) end
	end)
	mover:SetScript("OnDragStop", function(self)
		local snapped = ShamanPower.UnlockDragStop and ShamanPower:UnlockDragStop(self)
		self:StopMovingOrSizing()
		local mf, sf = self.moveFrame, self.sizeFrame
		if mf and sf then
			-- Shift the moved frame by how far the mover moved from the bar,
			-- in physical px. Works even when the moved frame is a 1x1 anchor.
			local mcx, mcy = self:GetCenter()
			local scx, scy = sf:GetCenter()
			-- Unlock UI's alignment grid: snap the box's top-left corner to the
			-- nearest grid lines (lines run from the screen centre, in UIParent pixels).
			-- A box dragged by Unlock UI has already snapped as it moved.
			local step = not snapped and ShamanPower.UnlockGridStep and ShamanPower:UnlockGridStep()
			if step and mcx and self:GetLeft() then
				local mes, uis = self:GetEffectiveScale(), UIParent:GetEffectiveScale()
				local l, t = self:GetLeft() * mes / uis, self:GetTop() * mes / uis
				local cx, cy = UIParent:GetWidth() / 2, UIParent:GetHeight() / 2
				local sl = cx + math.floor((l - cx) / step + 0.5) * step
				local st = cy + math.floor((t - cy) / step + 0.5) * step
				mcx = mcx + (sl - l) * uis / mes
				mcy = mcy + (st - t) * uis / mes
			end
			if mcx and scx then
				local mes, ses = self:GetEffectiveScale(), sf:GetEffectiveScale()
				local dx = mcx * mes - scx * ses
				local dy = mcy * mes - scy * ses
				local point, rel, relPoint, x, y = mf:GetPoint()
				local mes2 = mf:GetEffectiveScale()
				if point then
					mf:ClearAllPoints()
					mf:SetPoint(point, rel, relPoint, x + dx / mes2, y + dy / mes2)
				end
			end
			if self.onMoved then self.onMoved() end
			-- Re-place the overlay over the bar's new spot, next frame.
			C_Timer.After(0, RefreshShownBarMovers)
		end
	end)
	mover.key = key
	self.barMovers[key] = mover
	mover.moveFrame, mover.sizeFrame, mover.onMoved = moveFrame, sizeFrame or moveFrame, onMoved
	SetBarMoverLabel(mover, label or "Move")
	return mover
end

function ShamanPower:ShowBarMover(key, moveFrame, sizeFrame, label, onMoved)
	if InCombatLockdown() then
		print("|cff0070ddShamanPower|r: can't unlock bars in combat")
		return
	end
	sizeFrame = sizeFrame or moveFrame
	local mover = self:GetBarMover(key, moveFrame, sizeFrame, label, onMoved)
	if not sizeFrame or not sizeFrame:GetLeft() then return end
	local es = sizeFrame:GetEffectiveScale()
	local W = (sizeFrame:GetRight() - sizeFrame:GetLeft()) * es
	local H = (sizeFrame:GetTop() - sizeFrame:GetBottom()) * es
	local cx = (sizeFrame:GetLeft() + sizeFrame:GetRight()) / 2 * es
	local cy = (sizeFrame:GetTop() + sizeFrame:GetBottom()) / 2 * es
	local mes = mover:GetEffectiveScale()
	-- at least as wide as the label's longest word and tall enough for its lines
	local w = math.max(W / mes, MOVER_MIN_W, mover.spWordW + 2 * MOVER_PAD)
	mover.text:SetWidth(w - 2 * MOVER_PAD)
	local h = math.max(H / mes, MOVER_MIN_H, math.ceil(mover.text:GetStringHeight()) + 2 * MOVER_PAD)
	mover:ClearAllPoints()
	mover:SetSize(w, h)
	mover:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx / mes, cy / mes)
	mover:Show()
end

function ShamanPower:HideBarMover(key)
	local mover = self.barMovers[key]
	if mover then mover:Hide() end
end

-- Unlock UI's arrow keys: move the frame a box stands for by dx, dy (UIParent
-- pixels), save it as a drop does, and put the boxes back over it next frame.
function ShamanPower:NudgeBarMover(mover, dx, dy)
	local mf = mover and mover.moveFrame
	if not mf or InCombatLockdown() then return end
	local point, rel, relPoint, x, y = mf:GetPoint()
	if not point then return end
	local k = UIParent:GetEffectiveScale() / mf:GetEffectiveScale()
	mf:ClearAllPoints()
	mf:SetPoint(point, rel, relPoint, x + dx * k, y + dy * k)
	if mover.onMoved then mover.onMoved() end
	C_Timer.After(0, RefreshShownBarMovers)
end

function ShamanPower:GetPositionRecord(frame)
	local fs = frame:GetScale() or 1
	local W, H = UIParent:GetWidth(), UIParent:GetHeight()
	local cx, cy
	-- A UIParent child hanging off one point on UIParent (every SetPoint in here)
	-- is worked out from that point and its size, not read back off the screen:
	-- straight after a SetPoint the game can still report the old spot. Anything
	-- else (a frame just dropped by StopMovingOrSizing was laid out while dragged)
	-- has its centre read.
	local point, rel, relPoint, x, y
	if frame:GetNumPoints() == 1 and frame:GetParent() == UIParent then point, rel, relPoint, x, y = frame:GetPoint(1) end
	if point and rel == UIParent then
		local ax, ay = AnchorXY(relPoint or point, W, H)
		local px = (strfind(point, "LEFT") and -0.5) or (strfind(point, "RIGHT") and 0.5) or 0
		local py = (strfind(point, "TOP") and 0.5) or (strfind(point, "BOTTOM") and -0.5) or 0
		cx = ax + ((x or 0) - px * frame:GetWidth()) * fs
		cy = ay + ((y or 0) - py * frame:GetHeight()) * fs
	else
		cx, cy = frame:GetCenter()
		if not cx then return nil end
		cx, cy = cx * fs, cy * fs
	end
	local best, bestD, bx, by
	for _, a in ipairs(ANCHOR_POINTS) do
		local ax, ay = AnchorXY(a, W, H)
		local d = (cx - ax) ^ 2 + (cy - ay) ^ 2
		if not bestD or d < bestD then best, bestD, bx, by = a, d, ax, ay end
	end
	return { anchor = best, x = cx - bx, y = cy - by }
end

function ShamanPower:ApplyPositionRecord(frame, rec)
	if not (rec and rec.anchor) then return false end
	local fs = frame:GetScale() or 1
	frame:ClearAllPoints()
	frame:SetPoint("CENTER", UIParent, rec.anchor, (rec.x or 0) / fs, (rec.y or 0) / fs)
	return true
end

function ShamanPower:SavePositionRecord(frame)
	local rec = self:GetPositionRecord(frame)
	if rec then self:ApplyPositionRecord(frame, rec) end
	return rec
end

-- ---------------------------------------------------------------------------
-- Default spots. A bar with no saved spot sits on its default one, worked out
-- again whenever a size, the layout or the scale changes, until the player
-- moves it (which saves a spot); Reset drops the saved spot. Everything is
-- computed from the saved spots and the sizes set on the frames, never read
-- back off the screen.
-- ---------------------------------------------------------------------------
-- Fresh setups start low and centred, above the action bars, so the totem bar
-- and the cooldown bar under it aren't covered by the pop-ups and alerts that
-- sit around the middle of the screen. Picked in game on 2026-09-24. This is
-- where the VISIBLE bar's centre goes (ShamanPowerAuto, the box Unlock UI
-- draws), not ShamanPowerFrame: that is a 1x1 anchor the bar hangs off.
ShamanPower.DEFAULT_TOTEM_BAR_POSITION = { anchor = "CENTER", x = 0, y = -195 }
-- UIParent units between the two bars' Unlock boxes; a cooldown bar under the
-- totem bar also leaves room for its box's Reset tab (ShamanPowerUnlock AddReset).
local BAR_GAP, RESET_TAB_H = 4, 15

-- Every style keeps its own spot, as Compact always did: Grid tucked into a
-- corner leaves the Normal bar where it was, and switching back brings each
-- style home. Normal (and Blizzard's bar, which hides ShamanPower's) uses
-- display.position, Compact display.compactPosition, TotemTimers, Dynamic and
-- Grid display.stylePositions[style]. Read from the chosen style, not from
-- what is built yet, so a /reload in Grid lands on Grid's spot.
function ShamanPower:BarStyleSpotKey()
	local key = self.GetTotemBarStyle and self:GetTotemBarStyle() or "normal"
	if key == "blizzard" then return "normal" end
	return key
end
function ShamanPower:GetStyleSpot(d, key)
	if key == "normal" then return d.position end
	if key == "compact" then return d.compactPosition end
	return d.stylePositions and d.stylePositions[key]
end
function ShamanPower:SetStyleSpot(d, key, rec)
	if key == "normal" then d.position = rec
	elseif key == "compact" then d.compactPosition = rec
	else
		d.stylePositions = d.stylePositions or {}
		d.stylePositions[key] = rec
	end
end
-- After a style change: put the bar on the new style's spot. The bar is secure, so a
-- change made in a fight (Dynamic and TotemTimers can be) moves it when the fight ends.
function ShamanPower:FollowStyleSpot()
	if self:BarStyleSpotKey() == self._barSpotKey then return end
	if InCombatLockdown() then
		if not self._styleSpotWaiter then
			local f = CreateFrame("Frame")
			f:SetScript("OnEvent", function(frame)
				frame:UnregisterEvent("PLAYER_REGEN_ENABLED")
				ShamanPower:FollowStyleSpot()
			end)
			self._styleSpotWaiter = f
		end
		self._styleSpotWaiter:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end
	self:RestoreTotemBarPosition()
	self:ApplyDefaultBarPositions()   -- a cooldown bar on its default spot follows
end

-- The totem bar's saved spot, or nil while it sits on its default one. A style
-- never moved starts where the Normal bar is; { default = true } is a style's
-- spot reset to the default.
function ShamanPower:TotemBarRecord()
	local d = self.opt and self.opt.display
	if not d then return nil end
	local rec = d.position
	local key = self:BarStyleSpotKey()
	if key ~= "normal" then
		local c = self:GetStyleSpot(d, key)
		if c and (c.anchor or c.default) then rec = c end
	end
	return rec and rec.anchor and rec or nil
end

-- The visible bar against ShamanPowerFrame's centre, in UIParent units: centre
-- offset (dx, dy) and size (w, h). UpdateLayout pins its TOPLEFT to the frame's
-- CENTER at the layout offset.
function ShamanPower:TotemBarGeometry()
	local a = self.autoButton
	local layout = self.Layouts[self.opt.layout] or self.Layouts["Vertical"]
	-- (the defaults if a setup import left them out: never a Lua error here)
	local d = self.opt.display
	local ox = layout.ab.x * (d.buttonWidth or 100)
	local oy = layout.ab.y * (d.buttonHeight or 34)
	local w, h = a:GetWidth(), a:GetHeight()
	local k = ShamanPowerFrame:GetScale() * a:GetScale()
	return (ox + w / 2) * k, (oy - h / 2) * k, w * k, h * k
end

-- Where the cooldown bar goes with no saved spot: straight under the totem
-- bar, its Unlock box clear of the totem bar's. into: a record to fill instead
-- of a new one (the layout passes run this often).
function ShamanPower:CooldownBarDefaultRecord(into)
	local W, H = UIParent:GetWidth(), UIParent:GetHeight()
	local dx, dy, _, th = self:TotemBarGeometry()
	local rec = self:TotemBarRecord()
	local tx, ty
	if rec then
		local ax, ay = AnchorXY(rec.anchor, W, H)
		tx, ty = ax + rec.x + dx, ay + rec.y + dy
	else
		local def = self.DEFAULT_TOTEM_BAR_POSITION
		local ax, ay = AnchorXY(def.anchor, W, H)
		tx, ty = ax + def.x, ay + def.y
	end
	local bar = self.cooldownBar
	th = math.max(th, MOVER_MIN_H)
	local bh = math.max(bar:GetHeight() * bar:GetScale(), MOVER_MIN_H)
	-- always straight under the totem bar, whatever the layout
	local x, y = tx, ty - th / 2 - BAR_GAP - RESET_TAB_H - bh / 2
	local out = into or {}
	out.anchor, out.x, out.y = "CENTER", x - W / 2, y - H / 2
	return out
end

-- Put each bar that has no saved spot on its default one. Out of combat only
-- (both bars hold secure buttons), and never under a bar being dragged.
-- Runs on every layout pass (roster changes too): the two records it applies
-- are reused, never kept.
local defaultTotemScratch, defaultCooldownScratch = {}, {}
function ShamanPower:ApplyDefaultBarPositions()
	if InCombatLockdown() or self.isDragging or not (self.opt and self.autoButton) then return end
	if not self:TotemBarRecord() then
		local def = self.DEFAULT_TOTEM_BAR_POSITION
		local dx, dy = self:TotemBarGeometry()
		local r = defaultTotemScratch
		r.anchor, r.x, r.y = def.anchor, def.x - dx, def.y - dy
		self:ApplyPositionRecord(ShamanPowerFrame, r)
	end
	local bar, rec = self.cooldownBar, self.opt.cooldownBarPosition
	if bar and bar:GetParent() == UIParent and not self.cooldownBarDragging and not (rec and rec.anchor) then
		self:ApplyPositionRecord(bar, self:CooldownBarDefaultRecord(defaultCooldownScratch))
	end
end

-- Unlock UI "Reset": drop the saved spot so the bar goes back on its default
-- one. The totem bar's Reset takes the cooldown bar back under it too.
function ShamanPower:ResetBarPositions(totemBar)
	if InCombatLockdown() then return end
	if totemBar then
		self:EnsureProfileTable("display")
		local d = self.opt.display
		d.offsetX, d.offsetY = nil, nil
		local key = self:BarStyleSpotKey()
		if key == "normal" then d.position = nil else self:SetStyleSpot(d, key, { default = true }) end
	end
	self.opt.cooldownBarPosition = nil
	self.opt.cooldownBarPoint, self.opt.cooldownBarRelPoint = nil, nil
	self.opt.cooldownBarPosX, self.opt.cooldownBarPosY = nil, nil
	self:ApplyDefaultBarPositions()
	-- detaches a bar still on the totem bar; that also shows it, so not a bar switched off
	if self.cooldownBar and self.opt.showCooldownBar then self:UpdateCooldownBarPosition(true) end
end

-- Unlock/lock the totem bar for free dragging via a mover overlay.
-- Unlocking is a one-session action: at login the saved flag is cleared, so a
-- checkbox left ticked never outlives the overlay it stands for.
do
	local f = CreateFrame("Frame")
	f:RegisterEvent("PLAYER_LOGIN")
	f:SetScript("OnEvent", function()
		local d = ShamanPower.opt and ShamanPower.opt.display
		if d then d.moverUnlocked = nil end
	end)
end

function ShamanPower:SetTotemBarUnlocked(unlocked)
	self:EnsureProfileTable("display")
	self.opt.display.moverUnlocked = unlocked and true or nil
	if unlocked then
		-- (a cooldown bar on its default spot follows; the mover puts its box back over it a frame later)
		self:ShowBarMover("totembar", _G["ShamanPowerFrame"], self.autoButton, "Totem Bar", function()
			ShamanPower:SaveFramePosition(_G["ShamanPowerFrame"])
		end)
	else
		self:HideBarMover("totembar")
	end
end

-- Unlock/lock the cooldown bar.
function ShamanPower:SetCooldownBarUnlocked(unlocked)
	if unlocked and not self.cooldownBar then unlocked = nil end   -- no bar (yet): nothing to move
	self.cdBarMoverShown = unlocked and true or nil
	if unlocked then
		local function onMoved()
			ShamanPower.opt.cooldownBarPosition = ShamanPower:SavePositionRecord(ShamanPower.cooldownBar)
			ShamanPower.opt.cooldownBarPoint, ShamanPower.opt.cooldownBarRelPoint = nil, nil
			ShamanPower.opt.cooldownBarPosX, ShamanPower.opt.cooldownBarPosY = nil, nil
		end
		-- Moving only makes sense detached from the totem bar; detach (once)
		-- and reposition, but NEVER re-attach when the mover is turned off.
		if self.opt.cooldownBarLocked or self.cooldownBar:GetParent() ~= UIParent then
			self.opt.cooldownBarLocked = nil
			self:UpdateCooldownBarPosition(true)
			-- just placed: read now, it can still report its old spot, so its box is
			-- measured a frame later (the box exists now, for the Unlock UI's Reset)
			self:GetBarMover("cooldownbar", self.cooldownBar, self.cooldownBar, "Cooldown Bar", onMoved)
			C_Timer.After(0, function()
				if self.cdBarMoverShown then self:ShowBarMover("cooldownbar", self.cooldownBar, self.cooldownBar, "Cooldown Bar", onMoved) end
			end)
			return
		end
		self:ShowBarMover("cooldownbar", self.cooldownBar, self.cooldownBar, "Cooldown Bar", onMoved)
	else
		self:HideBarMover("cooldownbar")
	end
end

function ShamanPower:SetFrameScaleKeepCenter(frame, scale)
	local old = frame:GetScale() or 1
	local cx, cy = frame:GetCenter()
	if cx and cy and old > 0 then
		cx, cy = cx * old, cy * old              -- screen (UIParent) coordinates
		frame:SetScale(scale)
		frame:ClearAllPoints()
		frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx / scale, cy / scale)
	else
		frame:SetScale(scale)
	end
end

-- On-screen centre (physical pixels) of the visible totem bar: the mini bar
-- frame plus every visible totem button that is still on the bar. The buttons
-- are parented to UIParent and hang off the frame's top-left, so the frame's
-- own centre is not the bar's centre.
function ShamanPower:GetTotemBarScreenCenter()
	local l, r, t, b
	local function add(f)
		if not f or not f:IsShown() or not f:GetLeft() then return end
		local es = f:GetEffectiveScale()
		local fl, fr, ft, fb = f:GetLeft() * es, f:GetRight() * es, f:GetTop() * es, f:GetBottom() * es
		l = (not l or fl < l) and fl or l
		r = (not r or fr > r) and fr or r
		t = (not t or ft > t) and ft or t
		b = (not b or fb < b) and fb or b
	end
	add(self.autoButton)
	for element, btn in pairs(self.totemButtons or {}) do
		if not self:IsElementPoppedOut(element) then add(btn) end
	end
	if not l then return nil end
	return (l + r) / 2, (t + b) / 2
end

-- Re-anchor a UIParent-parented frame as CENTER -> UIParent CENTER (offsets in
-- the frame's own units) and return those offsets. Modules that save
-- {point, x, y} and restore with point used for both ends need this after a
-- keep-centre rescale, which leaves the anchor on UIParent's BOTTOMLEFT.
function ShamanPower:AnchorToScreenCenter(frame)
	local cx, cy = frame:GetCenter()
	if not cx then return nil end
	local s = frame:GetScale() or 1
	local x = cx - (UIParent:GetWidth() / 2) / s
	local y = cy - (UIParent:GetHeight() / 2) / s
	frame:ClearAllPoints()
	frame:SetPoint("CENTER", UIParent, "CENTER", x, y)
	return x, y
end

-- Icon-only mode must not strand the user: instead of hiding the settings
-- button outright, show it only while the mouse is over the frame.
-- Event-driven, so nothing runs while the mouse is elsewhere. The cursor can
-- reach or leave the frame straight off a child without the frame hearing it
-- (an icon-only pop-out is all button), so every mouse-enabled Frame/Button
-- inside it reports too, and each event just asks whether the cursor is over
-- the frame. Children come and go while the frame stays up (Raid Cooldowns
-- rebuilds its Mana Tide buttons on every sync), so every enter, leave, show
-- and resize walks the children again: whatever the cursor crosses onto from
-- something we hear is hooked before it can be left. A cursor that lands
-- straight from outside on a child built since the last walk shows the button
-- only once it moves on to the frame or another child. Engine widgets (aura
-- containers, cooldowns) are left alone.
do
	local owner = setmetatable({}, { __mode = "k" })   -- hooked region -> the frame whose button it drives
	local WALK = { Frame = true, Button = true, CheckButton = true }

	local function Update(region)
		local frame = owner[region]
		local cog = frame and frame.spCogHoverOnly
		if cog then cog:SetShown(frame:IsVisible() and (frame:IsMouseOver() or cog:IsMouseOver())) end
	end

	local Refresh
	local function HookTree(frame, ...)
		for i = 1, select("#", ...) do
			local region = select(i, ...)
			-- engine aura displays (the Coverage rows' names) are forbidden objects or
			-- answer with secret values on Forever: never touch them. Frames marked
			-- spNoHoverWalk hold them and never take the mouse, so they are skipped whole.
			local forbidden = region.IsForbidden and region:IsForbidden()
			local okType, objType
			if not forbidden and not region.spNoHoverWalk then okType, objType = pcall(region.GetObjectType, region) end
			local walk = okType and WALK[objType]
			local mouse = walk and region:IsMouseEnabled()
			if walk and not (issecretvalue and issecretvalue(mouse)) then
				if mouse then
					if not owner[region] then
						region:HookScript("OnEnter", Refresh)
						region:HookScript("OnLeave", Refresh)
					end
					owner[region] = frame
				end
				HookTree(frame, region:GetChildren())
			end
		end
	end

	Refresh = function(region)
		local frame = owner[region]
		if frame and frame.spCogHoverOnly then HookTree(frame, frame:GetChildren()) end
		Update(region)
	end

	function ShamanPower:SetSettingsButtonHoverOnly(frame, cog, enabled)
		if not frame or not cog then return end
		if not enabled then
			frame.spCogHoverOnly = nil
			cog:Show()
			return
		end
		frame.spCogHoverOnly = cog
		owner[frame] = frame
		if not frame.spCogHoverHooked then
			frame.spCogHoverHooked = true
			frame:HookScript("OnEnter", Refresh)
			frame:HookScript("OnLeave", Refresh)
			frame:HookScript("OnShow", Refresh)
			frame:HookScript("OnSizeChanged", Refresh)
			frame:HookScript("OnHide", Update)
		end
		Refresh(frame)
	end
end

function ShamanPower:ApplyPanelBackdrop(frame, border, spot)
	if not frame.SetBackdrop then Mixin(frame, BackdropTemplateMixin) end
	frame:SetBackdrop(self.PANEL_BACKDROP)
	local bg = self.PANEL_BG
	frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
	local b = border or self.PANEL_BORDER
	frame:SetBackdropBorderColor(b[1], b[2], b[3], b[4])
	-- spot: a General > Themes spot with bg / border roles repaints the colours
	-- above (nothing on Standard); the backdrop itself never changes
	if spot then self:ThemePaintPanel(frame, spot, border) end
	if self.EdgeFrame then self:EdgeFrame(frame) end   -- Frame Edges
end

-- The bg / border colours of a themed panel spot, or the panel's own colours
-- again once a theme had painted it. Colours only: never the size, position or
-- backdrop. A caller's own border colour (border) is left alone.
function ShamanPower:ThemePaintPanel(frame, spot, border)
	if not (frame and frame.backdropInfo) then return end
	local r, g, b = self:ThemeColor(spot, "bg")
	if r then
		frame:SetBackdropColor(r, g, b, self:ThemeAlpha(spot, "bg") or self.PANEL_BG[4])
		frame.spThemeFill = true
	elseif frame.spThemeFill then
		frame.spThemeFill = nil
		local bg = self.PANEL_BG
		frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
	end
	if border then return end
	r, g, b = self:ThemeColor(spot, "border")
	if r then
		frame:SetBackdropBorderColor(r, g, b, self.PANEL_BORDER[4])
		frame.spThemeEdge = true
	elseif frame.spThemeEdge then
		frame.spThemeEdge = nil
		local e = self.PANEL_BORDER
		frame:SetBackdropBorderColor(e[1], e[2], e[3], e[4])
	end
end

-- Small settings button: dark square, 1px border, three bars. Replaces the
-- Blizzard gear texture on the pop-out frames. The hover paint is hooked, so
-- callers add their tooltip with HookScript: a SetScript would wipe it.
function ShamanPower:StyleSettingsButton(btn)
	local bg = btn:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(btn)
	bg:SetColorTexture(0.055, 0.063, 0.078, 0.9)
	local edges = {}
	for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
		local t = btn:CreateTexture(nil, "BORDER")
		t:SetColorTexture(0.180, 0.204, 0.243, 1)
		if side == "TOP" or side == "BOTTOM" then
			t:SetHeight(1); t:SetPoint(side .. "LEFT"); t:SetPoint(side .. "RIGHT")
		else
			t:SetWidth(1); t:SetPoint("TOP" .. side); t:SetPoint("BOTTOM" .. side)
		end
		edges[#edges + 1] = t
	end
	local bars = {}
	for i = -1, 1 do
		local bar = btn:CreateTexture(nil, "ARTWORK")
		bar:SetHeight(1)
		bar:SetPoint("LEFT", btn, "LEFT", 4, i * 3)
		bar:SetPoint("RIGHT", btn, "RIGHT", -4, i * 3)
		bar:SetColorTexture(0.541, 0.580, 0.651, 1)
		bars[#bars + 1] = bar
	end
	btn.spPaint = function(hover)
		local r, g, b = 0.541, 0.580, 0.651
		if hover then r, g, b = 0.247, 0.663, 1.000 end
		for _, bar in ipairs(bars) do bar:SetColorTexture(r, g, b, 1) end
		for _, e in ipairs(edges) do e:SetColorTexture(hover and 0.0 or 0.180, hover and 0.439 or 0.204, hover and 0.867 or 0.243, 1) end
	end
	btn:HookScript("OnEnter", function() btn.spPaint(true) end)
	btn:HookScript("OnLeave", function() btn.spPaint(false) end)
end

function ShamanPower:CreatePopOutFrame(key, buttonSize, title)
	-- key: "totem_earth", "single_1_3", "cd_1", etc.
	if self.poppedOutFrames[key] then
		return self.poppedOutFrames[key]
	end

	local frameWidth = buttonSize + 20
	local titleHeight = 14
	local cogSize = 12
	local frameHeight = buttonSize + titleHeight + cogSize + 12

	local frame = CreateFrame("Frame", "ShamanPowerPopOut_" .. key, UIParent, "BackdropTemplate")
	frame:SetSize(frameWidth, frameHeight)
	frame:SetMovable(not self:PopOutsLocked())
	frame:EnableMouse(true)
	frame:SetClampedToScreen(true)
	frame:RegisterForDrag("LeftButton")
	frame.key = key
	frame.buttonSize = buttonSize
	frame.title = title

	-- Background frame
	self:ApplyPanelBackdrop(frame, nil, "mod.popouts-colors")

	-- Cog wheel settings button (top-right corner)
	local cogBtn = CreateFrame("Button", frame:GetName() .. "Cog", frame)
	cogBtn:SetSize(cogSize, cogSize)
	cogBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
	self:StyleSettingsButton(cogBtn)
	cogBtn:SetScript("OnClick", function()
		ShamanPower:ShowPopOutSettingsPanel(key, frame)
	end)
	cogBtn:HookScript("OnEnter", function(self)
		if not ShamanPower.opt.ShowTooltips then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Settings")
		GameTooltip:Show()
	end)
	cogBtn:HookScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	frame.cogBtn = cogBtn

	-- Title text (below where the icon will be placed)
	local titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	titleText:SetPoint("BOTTOM", frame, "BOTTOM", 0, 4)
	titleText:SetText(title or "Pop-Out")
	ShamanPower:SetSPFont(titleText, "labels", 11, "", STANDARD_TEXT_FONT)
	titleText:SetShadowOffset(1, -1)
	titleText:SetShadowColor(0, 0, 0, 0.8)
	titleText:SetTextColor(0.902, 0.918, 0.941)
	frame.titleText = titleText
	self:FitPopOutFrame(frame)

	-- Apply scale/opacity from settings BEFORE the position: position records
	-- are scale-free but SetPoint offsets are not, so a frame placed first and
	-- scaled afterwards slides to a different spot on every reload.
	local settings = self.opt.poppedOutSettings and self.opt.poppedOutSettings[key] or {}
	local scale = settings.scale or self.opt.poppedOutDefaultScale or 1.0
	local opacity = settings.opacity or self.opt.poppedOutDefaultOpacity or 1.0
	frame:SetScale(scale)
	frame:SetAlpha(opacity)

	-- Restore position or default to center
	local pos = self.opt.poppedOutPositions and self.opt.poppedOutPositions[key]
	if pos and pos.anchor then
		self:ApplyPositionRecord(frame, pos)
	elseif pos then
		-- Old edge-anchored format. The edge is only right once the caller has
		-- sized the frame (title width, hidden-frame mode), so convert it to a
		-- center record on the next frame, not now.
		frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
		C_Timer.After(0, function()
			if self.poppedOutFrames[key] == frame and self.opt.poppedOutPositions and not (self.opt.poppedOutPositions[key] or {}).anchor then
				self.opt.poppedOutPositions[key] = self:SavePositionRecord(frame)
			end
		end)
	else
		frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	end

	-- Check if frame should be hidden (show only icon)
	local hideFrame = settings.hideFrame
	if hideFrame then
		frame:SetBackdrop(nil)
		titleText:Hide()
		cogBtn:Hide()
	end

	-- Drag to move (no ALT needed - drag from title area or frame edge)
	frame:SetScript("OnDragStart", function(self)
		if self:IsMovable() and not ShamanPower:PopOutsLocked() then self:StartMoving() end
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		ShamanPower.opt.poppedOutPositions = ShamanPower.opt.poppedOutPositions or {}
		ShamanPower.opt.poppedOutPositions[key] = ShamanPower:SavePositionRecord(self)
	end)

	-- Middle-click on frame to return to bar
	frame:SetScript("OnMouseUp", function(self, button)
		if button == "MiddleButton" then
			if InCombatLockdown() then
				print("|cff0070ddShamanPower:|r Cannot modify pop-outs during combat")
				return
			end
			ShamanPower:ReturnPopOutToBar(key)
		end
	end)

	self.poppedOutFrames[key] = frame
	return frame
end

-- Settings panel for pop-out frames (with sliders)

-- The pop-out settings panel lives in ShamanPower_Config (FrameSettings);
-- this stub only reports when that module is missing.
function ShamanPower:ShowPopOutSettingsPanel(key, popOutFrame)
	print("|cff0070ddShamanPower|r: the ShamanPower_Config module is required for pop-out settings")
end

-- Where a pop-out's spot is saved. Under Grid "Split by Element" each element's
-- pop-out frame is a Grid row with its own spot (ShamanPowerGrid.lua), so a trip
-- through Grid never overwrites the element's regular pop-out spot.
local GRID_ROW_KEYS = { totem_earth = true, totem_fire = true, totem_water = true, totem_air = true }
local function PopOutPositions(key)
	local o = ShamanPower.opt
	if GRID_ROW_KEYS[key] and o.gridSplit and ShamanPower.GridActive and ShamanPower:GridActive() then
		o.gridSplitPositions = o.gridSplitPositions or {}
		return o.gridSplitPositions
	end
	o.poppedOutPositions = o.poppedOutPositions or {}
	return o.poppedOutPositions
end

-- Set scale for a pop-out frame
function ShamanPower:SetPopOutScale(key, scale)
	local frame = self.poppedOutFrames[key]
	if frame then
		-- Get current center position before scaling
		local oldScale = frame:GetScale()
		local centerX, centerY = frame:GetCenter()
		if centerX and centerY then
			-- Convert to screen coordinates
			centerX = centerX * oldScale
			centerY = centerY * oldScale

			-- Apply new scale
			frame:SetScale(scale)

			-- Reposition so center stays in same place
			frame:ClearAllPoints()
			frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", centerX / scale, centerY / scale)

			-- Save new position (a Grid split row keeps its own)
			PopOutPositions(key)[key] = self:SavePositionRecord(frame)
		else
			frame:SetScale(scale)
		end
	end
	self.opt.poppedOutSettings = self.opt.poppedOutSettings or {}
	self.opt.poppedOutSettings[key] = self.opt.poppedOutSettings[key] or {}
	self.opt.poppedOutSettings[key].scale = scale
end

-- Set opacity for a pop-out frame
function ShamanPower:SetPopOutOpacity(key, opacity)
	local frame = self.poppedOutFrames[key]
	if frame then
		frame:SetAlpha(opacity)
	end
	self.opt.poppedOutSettings = self.opt.poppedOutSettings or {}
	self.opt.poppedOutSettings[key] = self.opt.poppedOutSettings[key] or {}
	self.opt.poppedOutSettings[key].opacity = opacity
end

-- Set flyout direction for a popped-out element
function ShamanPower:SetPopOutFlyoutDirection(key, direction)
	self.opt.poppedOutSettings = self.opt.poppedOutSettings or {}
	self.opt.poppedOutSettings[key] = self.opt.poppedOutSettings[key] or {}
	self.opt.poppedOutSettings[key].flyoutDirection = direction

	-- Get element from key and re-layout flyout
	local elementName = key:match("^totem_(.+)$")
	if elementName then
		local element = self.ElementToID[elementName:upper()]
		if element and self.totemFlyouts[element] then
			self:LayoutFlyoutButtons(self.totemFlyouts[element])
		end
	end
end

-- Toggle frame visibility (show only icon or full frame)
function ShamanPower:TogglePopOutFrame(key)
	self.opt.poppedOutSettings = self.opt.poppedOutSettings or {}
	self.opt.poppedOutSettings[key] = self.opt.poppedOutSettings[key] or {}

	local settings = self.opt.poppedOutSettings[key]
	settings.hideFrame = not settings.hideFrame

	local frame = self.poppedOutFrames[key]
	if frame then
		if settings.hideFrame then
			-- Hide frame decorations, show only icon
			frame:SetBackdrop(nil)
			if frame.titleText then frame.titleText:Hide() end
			self:SetSettingsButtonHoverOnly(frame, frame.cogBtn, true)
			-- Resize to just fit the button
			frame:SetSize(frame.buttonSize + 4, frame.buttonSize + 4)
			-- Reposition button
			if frame.button then
				frame.button:ClearAllPoints()
				frame.button:SetPoint("CENTER", frame, "CENTER", 0, 0)
			end
		else
			-- Show full frame with decorations
			self:ApplyPanelBackdrop(frame, nil, "mod.popouts-colors")
			self:FitBarBackdrop(frame)   -- setting the backdrop again resets its corners
			if frame.titleText then frame.titleText:Show() end
			self:SetSettingsButtonHoverOnly(frame, frame.cogBtn, false)
			-- Resize to full size (cog at top, icon in middle, title at bottom)
			local titleHeight = 14
			local cogSize = 12
			self:FitPopOutFrame(frame)
			-- Reposition button (center, slightly above bottom to make room for title)
			if frame.button then
				frame.button:ClearAllPoints()
				frame.button:SetPoint("CENTER", frame, "CENTER", 0, 2)
			end
		end
	end

	-- Update the settings panel checkbox if it's open for this key
end

-- Pop out a single totem from a flyout
function ShamanPower:PopOutSingleTotem(element, totemIndex)
	local key = "single_" .. element .. "_" .. totemIndex
	if self.opt.poppedOut and self.opt.poppedOut[key] then return end  -- Already popped

	self.opt.poppedOut = self.opt.poppedOut or {}
	self.opt.poppedOut[key] = true

	-- Get totem spell info
	local spellID = self:GetTotemSpell(element, totemIndex)
	local spellName = spellID and GetSpellInfo(spellID)
	if SPCompat.HasTotemCastAliases(spellID) then spellName = SPCompat.TotemCastName(spellID) end
	local icon = self:GetTotemIcon(element, totemIndex)
	local totemName = self:GetTotemName(element, totemIndex) or "Totem"

	-- Create frame with title
	local frame = self:CreatePopOutFrame(key, 32, totemName)

	-- Create a visible icon holder frame for the icon and all visual effects
	local iconHolder = CreateFrame("Frame", frame:GetName() .. "IconHolder", frame)
	iconHolder:SetSize(32, 32)
	iconHolder:SetPoint("CENTER", frame, "CENTER", 0, 2)
	frame.iconHolder = iconHolder

	-- Create the icon texture on the holder
	local iconTex = iconHolder:CreateTexture(nil, "ARTWORK")
	iconTex:SetAllPoints()
	iconTex:SetTexture(icon)
	iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	frame.iconTex = iconTex
	iconHolder.icon = iconTex

	-- Create invisible secure button on top for click handling only
	local btn = CreateFrame("Button", frame:GetName() .. "Btn", frame,
		"SecureActionButtonTemplate, SecureHandlerEnterLeaveTemplate")
	btn:SetSize(32, 32)
	btn:SetPoint("CENTER", frame, "CENTER", 0, 2)
	btn:SetFrameLevel(iconHolder:GetFrameLevel() + 10)  -- Make sure it's on top
	btn:RegisterForClicks("AnyUp", "AnyDown")
	btn:SetAlpha(0)  -- Invisible - just handles clicks
	btn.icon = iconTex  -- Reference the separate texture

	-- Set up spell casting
	if spellName then
		btn:SetAttribute("type1", "spell")
		btn:SetAttribute("spell1", spellName)
	end

	-- Right-click to cast Totemic Call (destroys all totems)
	btn:SetAttribute("type2", "spell")
	btn:SetAttribute("spell2", GetSpellInfo(36936))  -- Totemic Call

	-- Tooltip
	btn:SetScript("OnEnter", function(self)
		if not ShamanPower.opt.ShowTooltips then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if spellID then
			GameTooltip:SetSpellByID(SPCompat.HighestKnownRank and SPCompat.HighestKnownRank(spellID) or spellID)
		end
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("|cff00ff00Middle-click:|r Return to bar", 1, 1, 1)
		GameTooltip:AddLine("|cff00ff00SHIFT+Middle-click:|r Settings", 1, 1, 1)
		GameTooltip:AddLine("|cff00ff00ALT+drag:|r Move (when only the icon is shown)", 1, 1, 1)
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	-- Middle-click handler on button (SHIFT = settings, plain = return to bar)
	btn:HookScript("OnClick", function(self, button)
		if button == "MiddleButton" then
			if IsShiftKeyDown() then
				-- SHIFT+Middle-click opens settings
				ShamanPower:ShowPopOutSettingsPanel(key, frame)
			else
				-- Plain middle-click returns to bar
				if InCombatLockdown() then
					print("|cff0070ddShamanPower:|r Cannot modify pop-outs during combat")
					return
				end
				ShamanPower:ReturnPopOutToBar(key)
			end
		end
	end)

	-- ALT+drag on button to move frame (works when frame is hidden)
	btn:RegisterForDrag("LeftButton")
	btn:SetScript("OnDragStart", function(self)
		if IsAltKeyDown() and frame:IsMovable() and not ShamanPower:PopOutsLocked() then
			frame:StartMoving()
		end
	end)
	btn:SetScript("OnDragStop", function(self)
		frame:StopMovingOrSizing()
		ShamanPower.opt.poppedOutPositions = ShamanPower.opt.poppedOutPositions or {}
		ShamanPower.opt.poppedOutPositions[key] = ShamanPower:SavePositionRecord(frame)
	end)

	-- Store references
	frame.button = btn
	frame.element = element
	frame.totemIndex = totemIndex
	frame.spellID = spellID
	frame.spellName = spellName

	-- Create pulse overlay on the visible iconHolder (Earth, Fire, and Water totems can pulse)
	if element == 1 or element == 2 or element == 3 then
		local pulseOverlay = self:CreatePulseOverlay(iconHolder)
		if pulseOverlay then
			self.poppedOutOverlays[key] = pulseOverlay
			pulseOverlay.element = element
			pulseOverlay.totemIndex = totemIndex
			pulseOverlay.spellID = spellID
			pulseOverlay.spellName = spellName
			self:ThemePaintPulse(pulseOverlay, element)   -- tb.pulse; nothing on Standard
			-- Position the wipe properly for this button
			self:PositionPulseWipe(pulseOverlay)
		end
	end

	-- DISABLED: Active border causes a visual box artifact inside the icon
	-- The UI-ActionButton-Border texture has inner content that shows through
	--[[
	-- Create active totem border on iconHolder (shows when this totem is placed)
	local activeBorder = iconHolder:CreateTexture(nil, "OVERLAY")
	activeBorder:SetPoint("TOPLEFT", iconHolder, "TOPLEFT", -2, 2)
	activeBorder:SetPoint("BOTTOMRIGHT", iconHolder, "BOTTOMRIGHT", 2, -2)
	activeBorder:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
	activeBorder:SetBlendMode("ADD")
	local colors = self.ElementColors[element]
	activeBorder:SetVertexColor(colors.r, colors.g, colors.b, 0.8)
	activeBorder:Hide()
	frame.activeBorder = activeBorder
	--]]
	frame.activeBorder = nil

	-- Create duration bar on iconHolder (same style as main totem bars)
	local barColors = self.DurationBarColors[element]
	local barSize = self.opt.durationBarHeight or 3

	-- Background bar
	local bgBar = iconHolder:CreateTexture(nil, "OVERLAY")
	bgBar:SetColorTexture(0, 0, 0, 0.7)
	bgBar:SetAlpha(self:DurationTrackAlpha(1))   -- Duration Bar Background
	bgBar:SetPoint("BOTTOMLEFT", iconHolder, "BOTTOMLEFT", 0, 0)
	bgBar:SetPoint("BOTTOMRIGHT", iconHolder, "BOTTOMRIGHT", 0, 0)
	bgBar:SetHeight(barSize)
	bgBar:Hide()

	-- Progress bar
	local progressBar = iconHolder:CreateTexture(nil, "OVERLAY", nil, 1)
	ShamanPower:SetSPBarColor(progressBar, "duration", barColors[1], barColors[2], barColors[3], 1)
	progressBar:SetPoint("BOTTOMLEFT", iconHolder, "BOTTOMLEFT", 0, 0)
	progressBar:SetHeight(barSize)
	progressBar:SetWidth(1)
	progressBar:Hide()

	-- Duration text on icon
	local durationText = iconHolder:CreateFontString(nil, "OVERLAY")
	ShamanPower:SetSPFont(durationText, "timers", 11, "OUTLINE")
	durationText:SetPoint("CENTER", iconHolder, "CENTER", 0, 0)
	durationText:SetTextColor(1, 1, 1)
	self:ThemePaintDurationText(durationText, element)   -- tb.duration-text; nothing on Standard
	durationText:Hide()

	self.poppedOutProgressBars[key] = {
		bg = bgBar,
		bar = progressBar,
		text = durationText,
		maxWidth = iconHolder:GetWidth(),
		element = element,
		spellName = spellName
	}

	-- Check if frame should be hidden based on saved settings
	local settings = self.opt.poppedOutSettings and self.opt.poppedOutSettings[key] or {}
	if settings.hideFrame then
		self:TogglePopOutFrame(key)  -- Apply hide
		self:TogglePopOutFrame(key)  -- Toggle back since it was already set
		-- Actually just apply the hidden state directly
		frame:SetBackdrop(nil)
		if frame.titleText then frame.titleText:Hide() end
		self:SetSettingsButtonHoverOnly(frame, frame.cogBtn, true)
		frame:SetSize(frame.buttonSize + 4, frame.buttonSize + 4)
		iconHolder:ClearAllPoints()
		iconHolder:SetPoint("CENTER", frame, "CENTER", 0, 0)
		btn:ClearAllPoints()
		btn:SetPoint("CENTER", frame, "CENTER", 0, 0)
	end

	-- Update main bar to hide this from flyout
	self:UpdateFlyoutVisibility(element)

	frame:Show()
end

-- Pop out an entire element with its flyout
function ShamanPower:PopOutElementWithFlyout(element)
	if not self._gridRefreshing and self.GridPopOutElement and self:GridPopOutElement(element) then return end
	-- Totem Rows: every row already moves on its own (Unlock UI); the element pop-outs
	-- come back when it is off (ShamanPowerRows.lua keeps them)
	if self.RowsActive and self:RowsActive() then
		print("|cff0070ddShamanPower:|r In Totem Rows each row moves on its own: use Unlock UI.")
		return
	end
	local elementName = self.Elements[element]:lower()  -- "earth", "fire", "water", "air"
	local key = "totem_" .. elementName
	if self.opt.poppedOut and self.opt.poppedOut[key] then return end

	self.opt.poppedOut = self.opt.poppedOut or {}
	self.opt.poppedOut[key] = true

	-- Get element display name
	local displayName = self.Elements[element]  -- "EARTH", "FIRE", etc.
	displayName = displayName:sub(1,1) .. displayName:sub(2):lower()  -- "Earth", "Fire", etc.

	-- Create frame with title
	local frame = self:CreatePopOutFrame(key, 28, displayName)

	-- Get the existing totem button
	local totemBtn = self.totemButtons[element]
	if not totemBtn then return end

	-- Store original parent and points for restoration
	frame.originalParent = totemBtn:GetParent()
	frame.originalPoints = {}
	for i = 1, totemBtn:GetNumPoints() do
		frame.originalPoints[i] = {totemBtn:GetPoint(i)}
	end

	-- Reparent the totem button to this frame
	totemBtn:SetParent(frame)
	totemBtn:ClearAllPoints()
	totemBtn:SetPoint("CENTER", frame, "CENTER", 0, 2)  -- Slightly above center to leave room for title below
	totemBtn:SetScale(1)  -- Reset scale since frame handles it

	-- Flyout buttons are children of totemBtn, so they move with it

	frame.totemButton = totemBtn
	frame.button = totemBtn  -- For TogglePopOutFrame compatibility
	frame.element = element

	-- The same button can return and split again. Hook once and resolve the live
	-- frame, rather than retaining every retired pop-out in another drag closure.
	totemBtn.spElementPopOutKey = key
	if not totemBtn.spElementPopOutDragHooked then
		totemBtn.spElementPopOutDragHooked = true
		totemBtn:RegisterForDrag("LeftButton")
		totemBtn:HookScript("OnDragStart", function(button)
			if InCombatLockdown() then return end
			local currentKey = button.spElementPopOutKey
			local current = ShamanPower.poppedOutFrames[currentKey]
			local popped = ShamanPower.opt.poppedOut
			if current and current.totemButton == button and popped and popped[currentKey]
				and IsAltKeyDown() and not ShamanPower:PopOutsLocked() then
				current:StartMoving()
			end
		end)
		totemBtn:HookScript("OnDragStop", function(button)
			if InCombatLockdown() then return end
			local currentKey = button.spElementPopOutKey
			local current = ShamanPower.poppedOutFrames[currentKey]
			local popped = ShamanPower.opt.poppedOut
			if current and current.totemButton == button and popped and popped[currentKey] then
				current:StopMovingOrSizing()
				PopOutPositions(currentKey)[currentKey] = ShamanPower:SavePositionRecord(current)   -- a Grid split row keeps its own
			end
		end)
	end

	-- Note: SHIFT+Middle-click for settings is handled by the main totem button OnClick handler

	-- Check if frame should be hidden based on saved settings
	local settings = self.opt.poppedOutSettings and self.opt.poppedOutSettings[key] or {}
	if settings.hideFrame then
		frame:SetBackdrop(nil)
		if frame.titleText then frame.titleText:Hide() end
		self:SetSettingsButtonHoverOnly(frame, frame.cogBtn, true)
		frame:SetSize(frame.buttonSize + 4, frame.buttonSize + 4)
		totemBtn:ClearAllPoints()
		totemBtn:SetPoint("CENTER", frame, "CENTER", 0, 0)
	end

	-- Update main bar layout (skip this element)
	self:UpdateMiniTotemBar()
	self:UpdateTotemButtons()

	frame:Show()
end

-- Cooldown type names for display
local CooldownTypeNames = {
	[1] = "Shield",
	[2] = SPCompat.SpellLabel(36936, "Recall"),
	[3] = SPCompat.SpellLabel(20608, "Ankh"),
	[4] = SPCompat.SpellLabel(16188, "NS"),
	[5] = SPCompat.SpellLabel(16190, "Mana Tide"),
	[6] = SPCompat.SpellLabel(2825, "Bloodlust"),
	[7] = "Imbue",
	[8] = SPCompat.SpellLabel(30823, "Shamanistic Rage"),
	[9] = SPCompat.SpellLabel(16166, "Elemental Mastery"),
	[10] = SPCompat.SpellLabel(425336, "Rage of the Farseer"),
	[11] = SPCompat.SpellLabel(437009, "Totemic Projection"),
}

-- Pop out a cooldown bar item
function ShamanPower:PopOutCooldownItem(cooldownType)
	local key = "cd_" .. cooldownType
	if self.opt.poppedOut and self.opt.poppedOut[key] then return end

	self.opt.poppedOut = self.opt.poppedOut or {}
	self.opt.poppedOut[key] = true

	-- Find the button
	local btn = nil
	for _, b in ipairs(self.cooldownButtons) do
		if b.cooldownType == cooldownType then
			btn = b
			break
		end
	end
	if not btn then return end

	-- Get display name
	local displayName = CooldownTypeNames[cooldownType] or "Cooldown"

	-- Create frame with title
	local buttonSize = btn:GetWidth() or 22
	local frame = self:CreatePopOutFrame(key, buttonSize, displayName)

	-- Store original parent and points for restoration
	frame.originalParent = btn:GetParent()
	frame.originalPoints = {}
	for i = 1, btn:GetNumPoints() do
		frame.originalPoints[i] = {btn:GetPoint(i)}
	end

	-- Reparent button
	btn:SetParent(frame)
	btn:ClearAllPoints()
	btn:SetPoint("CENTER", frame, "CENTER", 0, 2)  -- Slightly above center to leave room for title below

	frame.cooldownButton = btn
	frame.button = btn  -- For TogglePopOutFrame compatibility
	frame.cooldownType = cooldownType

	-- ALT+drag on button to move frame (only add once)
	if not btn.popOutDragHooked then
		btn.popOutDragHooked = true
		btn:RegisterForDrag("LeftButton")
		btn:HookScript("OnDragStart", function(self)
			if IsAltKeyDown() then
				local popOutFrame = ShamanPower.poppedOutFrames["cd_" .. self.cooldownType]
				if popOutFrame and not ShamanPower:PopOutsLocked() then
					popOutFrame:StartMoving()
				end
			end
		end)
		btn:HookScript("OnDragStop", function(self)
			local cdKey = "cd_" .. self.cooldownType
			local popOutFrame = ShamanPower.poppedOutFrames[cdKey]
			if popOutFrame then
				popOutFrame:StopMovingOrSizing()
				ShamanPower.opt.poppedOutPositions = ShamanPower.opt.poppedOutPositions or {}
				ShamanPower.opt.poppedOutPositions[cdKey] = ShamanPower:SavePositionRecord(popOutFrame)
			end
		end)
	end

	-- Middle-click is handled by the initial handler in CreateCooldownBar
	-- (no duplicate hook needed here)

	-- Check if frame should be hidden based on saved settings
	local settings = self.opt.poppedOutSettings and self.opt.poppedOutSettings[key] or {}
	if settings.hideFrame then
		frame:SetBackdrop(nil)
		if frame.titleText then frame.titleText:Hide() end
		self:SetSettingsButtonHoverOnly(frame, frame.cogBtn, true)
		frame:SetSize(frame.buttonSize + 4, frame.buttonSize + 4)
		btn:ClearAllPoints()
		btn:SetPoint("CENTER", frame, "CENTER", 0, 0)
	end

	-- Update cooldown bar layout
	self:UpdateCooldownBarLayout()

	frame:Show()
end

-- Pop out Earth Shield button as standalone tracker
function ShamanPower:PopOutEarthShield()
	local key = "earthshield"
	if self.opt.poppedOut and self.opt.poppedOut[key] then return end

	local esBtn = _G["ShamanPowerEarthShieldBtn"]
	if not esBtn then return end

	self.opt.poppedOut = self.opt.poppedOut or {}
	self.opt.poppedOut[key] = true

	-- Create frame with title
	local buttonSize = esBtn:GetWidth() or 26
	local frame = self:CreatePopOutFrame(key, buttonSize, SPCompat.SpellLabel(974, "Earth Shield"))

	-- Store original parent for restoration
	frame.originalParent = esBtn:GetParent()

	-- Reparent button
	esBtn:SetParent(frame)
	esBtn:ClearAllPoints()
	esBtn:SetPoint("CENTER", frame, "CENTER", 0, 2)

	frame.earthShieldButton = esBtn
	frame.button = esBtn

	-- ALT+drag on button to move frame (only add hook once)
	if not esBtn.popOutDragHooked then
		esBtn.popOutDragHooked = true
		esBtn:RegisterForDrag("LeftButton")
		esBtn:HookScript("OnDragStart", function(self)
			if IsAltKeyDown() then
				local popOutFrame = ShamanPower.poppedOutFrames["earthshield"]
				if popOutFrame and not ShamanPower:PopOutsLocked() then
					popOutFrame:StartMoving()
				end
			end
		end)
		esBtn:HookScript("OnDragStop", function(self)
			local popOutFrame = ShamanPower.poppedOutFrames["earthshield"]
			if popOutFrame then
				popOutFrame:StopMovingOrSizing()
				ShamanPower.opt.poppedOutPositions = ShamanPower.opt.poppedOutPositions or {}
				ShamanPower.opt.poppedOutPositions["earthshield"] = ShamanPower:SavePositionRecord(popOutFrame)
			end
		end)
	end

	-- Middle-click is handled by the handler in CreateEarthShieldButton
	-- (no duplicate hook needed here to avoid accumulation)

	-- Check if frame should be hidden based on saved settings
	local settings = self.opt.poppedOutSettings and self.opt.poppedOutSettings[key] or {}
	if settings.hideFrame then
		frame:SetBackdrop(nil)
		if frame.titleText then frame.titleText:Hide() end
		self:SetSettingsButtonHoverOnly(frame, frame.cogBtn, true)
		frame:SetSize(frame.buttonSize + 4, frame.buttonSize + 4)
		esBtn:ClearAllPoints()
		esBtn:SetPoint("CENTER", frame, "CENTER", 0, 0)
	end

	-- Update totem bar layout
	self:RepositionEarthShieldButton()

	frame:Show()
end

-- Pop out Drop All button as standalone tracker
function ShamanPower:PopOutDropAll()
	local key = "dropall"
	if self.opt.poppedOut and self.opt.poppedOut[key] then return end

	local dropAllBtn = _G["ShamanPowerAutoDropAll"]
	if not dropAllBtn then return end

	self.opt.poppedOut = self.opt.poppedOut or {}
	self.opt.poppedOut[key] = true

	-- Create frame with title
	local buttonSize = dropAllBtn:GetWidth() or 26
	local frame = self:CreatePopOutFrame(key, buttonSize, "Drop All")

	-- Store original parent for restoration
	frame.originalParent = dropAllBtn:GetParent()

	-- Reparent button
	dropAllBtn:SetParent(frame)
	dropAllBtn:ClearAllPoints()
	dropAllBtn:SetPoint("CENTER", frame, "CENTER", 0, 2)

	frame.dropAllButton = dropAllBtn
	frame.button = dropAllBtn

	-- ALT+drag on button to move frame (only add hook once)
	if not dropAllBtn.popOutDragHooked then
		dropAllBtn.popOutDragHooked = true
		dropAllBtn:RegisterForDrag("LeftButton")
		dropAllBtn:HookScript("OnDragStart", function(self)
			if IsAltKeyDown() then
				local popOutFrame = ShamanPower.poppedOutFrames["dropall"]
				if popOutFrame and not ShamanPower:PopOutsLocked() then
					popOutFrame:StartMoving()
				end
			end
		end)
		dropAllBtn:HookScript("OnDragStop", function(self)
			local popOutFrame = ShamanPower.poppedOutFrames["dropall"]
			if popOutFrame then
				popOutFrame:StopMovingOrSizing()
				ShamanPower.opt.poppedOutPositions = ShamanPower.opt.poppedOutPositions or {}
				ShamanPower.opt.poppedOutPositions["dropall"] = ShamanPower:SavePositionRecord(popOutFrame)
			end
		end)
	end

	-- Middle-click is handled by the handler in UpdateDropAllButton
	-- (no duplicate hook needed here to avoid accumulation)

	-- Check if frame should be hidden based on saved settings
	local settings = self.opt.poppedOutSettings and self.opt.poppedOutSettings[key] or {}
	if settings.hideFrame then
		frame:SetBackdrop(nil)
		if frame.titleText then frame.titleText:Hide() end
		self:SetSettingsButtonHoverOnly(frame, frame.cogBtn, true)
		frame:SetSize(frame.buttonSize + 4, frame.buttonSize + 4)
		dropAllBtn:ClearAllPoints()
		dropAllBtn:SetPoint("CENTER", frame, "CENTER", 0, 0)
	end

	-- Update totem bar layout
	self:UpdateMiniTotemBar()

	frame:Show()
end

-- Check if Earth Shield is popped out
function ShamanPower:IsEarthShieldPoppedOut()
	if not self.opt.poppedOut then return false end
	return self.opt.poppedOut["earthshield"] == true
end

-- Check if Drop All is popped out
function ShamanPower:IsDropAllPoppedOut()
	if not self.opt.poppedOut then return false end
	return self.opt.poppedOut["dropall"] == true
end

-- Return a popped-out item to its original bar
function ShamanPower:ReturnPopOutToBar(key)
	if not self._gridRefreshing and self.GridReturnPopOut and self:GridReturnPopOut(key) then return end
	if not self.opt.poppedOut then return end
	self.opt.poppedOut[key] = nil

	local frame = self.poppedOutFrames[key]
	if not frame then return end

	if key:match("^totem_") then
		-- Element with flyout - reparent button back
		local totemBtn = frame.totemButton
		if totemBtn then
			totemBtn:SetParent(UIParent)  -- Back to UIParent (original parent for secure buttons)
			-- Position will be restored by UpdateTotemButtons
		end
		self:UpdateMiniTotemBar()
		self:UpdateTotemButtons()

	elseif key:match("^single_") then
		-- Single totem - destroy the pop-out frame and button
		if frame.button then
			frame.button:Hide()
			frame.button:SetParent(nil)
		end
		-- Clean up pulse overlay for this pop-out
		if self.poppedOutOverlays[key] then
			self.poppedOutOverlays[key] = nil
		end
		-- Clean up progress bars for this pop-out
		if self.poppedOutProgressBars[key] then
			self.poppedOutProgressBars[key] = nil
		end
		local element = frame.element
		self:UpdateFlyoutVisibility(element)

	elseif key:match("^cd_") then
		-- Cooldown item - reparent back to cooldown bar
		local btn = frame.cooldownButton
		if btn and self.cooldownBar then
			btn:SetParent(self.cooldownBar)
			-- Position will be restored by UpdateCooldownBarLayout
		end
		self:UpdateCooldownBarLayout()

	elseif key == "earthshield" then
		-- Earth Shield - reparent back to UIParent
		local esBtn = frame.earthShieldButton
		if esBtn then
			esBtn:SetParent(UIParent)
			-- Position will be restored by RepositionEarthShieldButton
		end
		self:RepositionEarthShieldButton()

	elseif key == "dropall" then
		-- Drop All - reparent back to original parent
		local dropAllBtn = frame.dropAllButton
		if dropAllBtn and frame.originalParent then
			dropAllBtn:SetParent(frame.originalParent)
			-- Position will be restored by UpdateMiniTotemBar
		end
		self:UpdateMiniTotemBar()
		-- Ensure Earth Shield is properly repositioned after Drop All returns
		C_Timer.After(0.05, function()
			self:RepositionEarthShieldButton()
		end)
	end

	frame:Hide()
	frame:SetParent(nil)
	self.poppedOutFrames[key] = nil
end

-- Restore all popped-out trackers on load
function ShamanPower:RestorePoppedOutTrackers()
	if not self.opt.poppedOut then return end
	if self:IsOff() then self._popOutsSkippedByOff = true; return end   -- brought back on switch-on

	for key, isPopped in pairs(self.opt.poppedOut) do
		if isPopped then
			if key:match("^totem_") then
				local elementName = key:match("^totem_(.+)$")
				if elementName then
					local element = self.ElementToID[elementName:upper()]
					if element and not (self.GridOwnsElementPopouts and self:GridOwnsElementPopouts())
						and not (self.RowsOwnElementPopouts and self:RowsOwnElementPopouts()) then
						local profile, popouts, requested = self.opt, self.opt.poppedOut, isPopped
						-- Delay slightly to ensure buttons exist
						C_Timer.After(0.1, function()
							if self.opt ~= profile or profile.poppedOut ~= popouts or popouts[key] ~= requested then return end
							if self.GridOwnsElementPopouts and self:GridOwnsElementPopouts() then return end
							if self.RowsOwnElementPopouts and self:RowsOwnElementPopouts() then return end
							self.opt.poppedOut[key] = nil  -- Clear so PopOutElementWithFlyout can proceed
							self:PopOutElementWithFlyout(element)
						end)
					end
				end

			elseif key:match("^single_") then
				local elem, idx = key:match("^single_(%d+)_(%d+)$")
				if elem and idx then
					C_Timer.After(0.1, function()
						self.opt.poppedOut[key] = nil  -- Clear so PopOutSingleTotem can proceed
						self:PopOutSingleTotem(tonumber(elem), tonumber(idx))
					end)
				end

			elseif key:match("^cd_") then
				local cdType = key:match("^cd_(%d+)$")
				if cdType then
					C_Timer.After(0.2, function()
						self.opt.poppedOut[key] = nil  -- Clear so PopOutCooldownItem can proceed
						self:PopOutCooldownItem(tonumber(cdType))
					end)
				end

			elseif key == "earthshield" then
				C_Timer.After(0.2, function()
					self.opt.poppedOut[key] = nil  -- Clear so PopOutEarthShield can proceed
					self:PopOutEarthShield()
				end)

			elseif key == "dropall" then
				C_Timer.After(0.2, function()
					self.opt.poppedOut[key] = nil  -- Clear so PopOutDropAll can proceed
					self:PopOutDropAll()
				end)
			end
		end
	end
end

-- Return all popped-out items to bars
function ShamanPower:ReturnAllPopOutsToBar()
	if not self.opt.poppedOut then return end

	-- Make a copy of keys since we're modifying the table
	local keys = {}
	for key in pairs(self.opt.poppedOut) do
		table.insert(keys, key)
	end

	for _, key in ipairs(keys) do
		self:ReturnPopOutToBar(key)
	end
end

-- Check if an element is popped out
function ShamanPower:IsElementPoppedOut(element)
	if not self.opt.poppedOut then return false end
	local elementName = self.Elements[element]:lower()
	local key = "totem_" .. elementName
	return self.opt.poppedOut[key] == true
end

-- Check if a single totem is popped out
function ShamanPower:IsSingleTotemPoppedOut(element, totemIndex)
	if not self.opt.poppedOut then return false end
	local key = "single_" .. element .. "_" .. totemIndex
	return self.opt.poppedOut[key] == true
end

-- Check if a cooldown item is popped out
function ShamanPower:IsCooldownPoppedOut(cooldownType)
	if not self.opt.poppedOut then return false end
	local key = "cd_" .. cooldownType
	return self.opt.poppedOut[key] == true
end

-- Combat-functional totem buttons parented to UIParent (TotemTimers architecture)
-- These buttons handle all totem interactions and support combat flyouts
ShamanPower.totemButtons = {}

-- Create totem buttons parented to UIParent using SPTotemButtonTemplate
-- This architecture enables combat-functional flyout menus
function ShamanPower:CreateTotemButtons()
	if self.totemButtons[1] then return end  -- Already created

	local elementIcons = {
		[1] = "Interface\\Icons\\Spell_Nature_EarthElemental_Totem",  -- Earth
		[2] = "Interface\\Icons\\Spell_Fire_SealOfFire",              -- Fire
		[3] = "Interface\\Icons\\Spell_Frost_SummonWaterElemental",   -- Water
		[4] = "Interface\\Icons\\Spell_Nature_InvisibilityTotem",     -- Air
	}

	for element = 1, 4 do
		-- Create button parented to UIParent using the new template
		local btn = CreateFrame("Button", "ShamanPowerTotemBtn" .. element, UIParent,
			"SPTotemButtonTemplate")

		btn:SetSize(26, 26)
		btn.element = element
		btn.icon = _G[btn:GetName() .. "Icon"]

		-- Set default icon
		if btn.icon then
			btn.icon:SetTexture(elementIcons[element])
		end

		-- Create small corner indicator for "assigned totem" (used in TotemTimers style mode)
		local assignedIndicator = CreateFrame("Frame", nil, btn)
		assignedIndicator:SetSize(12, 12)
		assignedIndicator:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
		assignedIndicator:SetFrameLevel(btn:GetFrameLevel() + 10)
		assignedIndicator:Hide()

		local indicatorBg = assignedIndicator:CreateTexture(nil, "BACKGROUND")
		indicatorBg:SetAllPoints()
		indicatorBg:SetColorTexture(0, 0, 0, 0.8)

		local indicatorIcon = assignedIndicator:CreateTexture(nil, "ARTWORK")
		indicatorIcon:SetPoint("TOPLEFT", 1, -1)
		indicatorIcon:SetPoint("BOTTOMRIGHT", -1, 1)
		indicatorIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

		btn.assignedIndicator = assignedIndicator
		btn.assignedIndicatorIcon = indicatorIcon

		-- Create cooldown frame for spell cooldown display on main totem button
		local cdFrame = CreateFrame("Cooldown", btn:GetName() .. "Cooldown", btn, "CooldownFrameTemplate")
		cdFrame:SetAllPoints(btn.icon)
		cdFrame:SetDrawSwipe(true)
		cdFrame:SetDrawEdge(true)
		cdFrame:SetSwipeColor(0, 0, 0, 0.8)
		cdFrame:SetHideCountdownNumbers(true)  -- We'll show our own text
		self:StyleEngineCooldown(cdFrame)       -- ...except where the engine draws the numbers
		btn.cooldown = cdFrame

		-- Create cooldown text overlay for main totem button (above the cooldown swipe)
		local cdTextFrame = CreateFrame("Frame", nil, btn)
		cdTextFrame:SetAllPoints(btn)
		cdTextFrame:SetFrameLevel(cdFrame:GetFrameLevel() + 1)
		local cdText = cdTextFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		ShamanPower:AdoptSPFont(cdText, "timers")   -- template font = the design; follows the Fonts settings
		cdText:SetPoint("CENTER", btn, "CENTER", 0, 0)
		local cdColor = self.opt.totemCooldownTextColor
		cdText:SetTextColor(cdColor and cdColor.r or 1, cdColor and cdColor.g or 1, cdColor and cdColor.b or 1)
		cdText:SetShadowOffset(1, -1)
		cdText:Hide()
		btn.cooldownText = cdText

		-- SECURE HANDLER: Show flyout on enter (WORKS IN COMBAT)
		btn:SetAttribute("OpenMenu", "mouseover")
		ShamanPower:SetSnippet(btn, "_onenter", [[
			if self:GetAttribute("OpenMenu") == "mouseover" then
				self:ChildUpdate("show", true)
			end
		]])

		-- SECURE HANDLER: Hide flyout on leave (WORKS IN COMBAT)
		ShamanPower:SetSnippet(btn, "_onleave", SP_SECURE_ONLEAVE_SELF)

		-- SECURE HANDLER: Show flyout on right-click when in click mode (WORKS IN COMBAT).
		-- Swap Left and Right Click makes it the left-click; with Shift+Right-Click
		-- Pulls That Totem Back on, the shifted click pulls the totem back instead.
		ShamanPower:SetSnippet(btn, "_onmouseup", [[
			local button = button
			local opener = (self:GetAttribute("*helpbutton1") == "RightButton") and "LeftButton" or "RightButton"
			if button == opener and self:GetAttribute("OpenMenu") == "click" then
				if not (self:GetAttribute("shiftpullback") and IsShiftKeyDown()) then
					self:ChildUpdate("show", true)
				end
			end
		]])

		-- Store layout info as attributes for secure relayout
		btn:SetAttribute("flyoutButtonSize", ShamanPower:TotemFlyoutButtonSize())
		btn:SetAttribute("flyoutSpacing", 0)

		-- Spell casting (type1 = left click)
		btn:SetAttribute("type1", "spell")

		-- Right-click to cast Totemic Call (destroys all totems)
		btn:SetAttribute("type2", "spell")
		btn:SetAttribute("spell2", GetSpellInfo(36936))  -- Totemic Call

		-- Register for clicks
		btn:RegisterForClicks("AnyUp", "AnyDown")
		btn:EnableMouse(true)

		-- Lua hooks for tooltips (work alongside secure handlers)
		btn:HookScript("OnEnter", function(self)
			ShamanPower:TotemBarTooltip(self, element)
		end)
		btn:HookScript("OnLeave", function(self)
			GameTooltip:Hide()
		end)

		-- Middle-click to pop out element with flyout (or SHIFT+Middle-click for settings when popped out)
		btn:HookScript("OnClick", function(self, button)
			if button == "MiddleButton" then
				-- Check if pop-out is enabled
				if ShamanPower.opt.enableMiddleClickPopOut == false then return end

				-- Debounce to prevent double-firing on down+up (same button is reparented)
				local now = GetTime()
				if ShamanPower.lastElementPopOutTime and (now - ShamanPower.lastElementPopOutTime) < 0.3 then
					return
				end
				ShamanPower.lastElementPopOutTime = now

				local elem = self.element
				local elementName = ShamanPower.Elements[elem]:lower()
				local key = "totem_" .. elementName

				-- If popped out and SHIFT is held, open settings instead of returning
				if ShamanPower.opt.poppedOut and ShamanPower.opt.poppedOut[key] then
					if IsShiftKeyDown() then
						local frame = ShamanPower.poppedOutFrames[key]
						if frame then
							ShamanPower:ShowPopOutSettingsPanel(key, frame)
						end
					else
						if InCombatLockdown() then
							print("|cff0070ddShamanPower:|r Cannot modify pop-outs during combat")
							return
						end
						ShamanPower:ReturnPopOutToBar(key)
					end
				else
					if InCombatLockdown() then
						print("|cff0070ddShamanPower:|r Cannot pop out during combat")
						return
					end
					ShamanPower:PopOutElementWithFlyout(elem)
				end
			end
		end)

		btn:Show()
		self.totemButtons[element] = btn
	end
end

-- Position totem buttons over the visual container
-- Which elements the bar shows: the per-element toggle, and (option, default
-- on) only elements the player has learned a totem for - a fresh shaman has
-- Earth alone until Fire at 10, Water at 20 and Air at 30. If detection finds
-- no totem at all (unknown client data) every element counts as learned.
local elementLearnedCache
function ShamanPower:InvalidateElementLearned()
	elementLearnedCache = nil
end

function ShamanPower:IsElementLearned(element)
	if not elementLearnedCache then
		elementLearnedCache = {}
		local any = false
		for e = 1, 4 do
			local known = false
			for _, id in pairs(self.Totems and self.Totems[e] or {}) do
				if PlayerKnowsTotem(id) then
					known = true
					break
				end
			end
			if not known then
				for id, info in pairs(self.TalentTotems or {}) do
					if type(info) == "table" and info[1] == e and PlayerKnowsTotem(id) then known = true break end
				end
			end
			elementLearnedCache[e] = known
			any = any or known
		end
		-- No totem found at all: below 10 that is a real new shaman (Earth's
		-- quest is at 4, Fire's at 10); at 10+ every shaman has totems, so an
		-- empty result means the spell tables do not fit this client - show all.
		if not any and (UnitLevel("player") or 0) >= 10 then
			for e = 1, 4 do elementLearnedCache[e] = true end
		end
	end
	return elementLearnedCache[element] and true or false
end

-- Drop All only once there is a totem to drop: a new shaman's bar shows no
-- lone Drop All button (SPELLS_CHANGED re-lays the bar when the first is learned).
function ShamanPower:ShowsDropAllButton()
	if self.opt.showDropAllButton == false then return false end
	for e = 1, 4 do if self:IsElementLearned(e) then return true end end
	return false
end

-- An accepted raid resistance request holds its element (ShamanPowerResist.lua,
-- Forever): that slot shows even before the element is learned, so the
-- resistance totem lands on a low-level shaman's bar too.
local function HoldsResistRequest(self, element)
	local list, applied = self.RESIST_REQUESTS, self.opt.resistApplied
	if not (list and applied) then return false end
	for i = 1, #list do
		if list[i].element == element and applied[list[i].key] ~= nil then return true end
	end
	return false
end

local ELEMENT_SHOW_KEY = { "totemBarShowEarth", "totemBarShowFire", "totemBarShowWater", "totemBarShowAir" }
function ShamanPower:IsElementShown(element)
	if self.opt[ELEMENT_SHOW_KEY[element]] == false then return false end
	if self.opt.hideUnlearnedElements ~= false and not self:IsElementLearned(element)
		and not HoldsResistRequest(self, element) then return false end
	return true
end

-- Dynamic Mode shows (and casts) the totem that is down instead of the assigned
-- one. Grid can sit on top of a Dynamic setup; with its "Left-Click Also
-- Assigns" off a drop keeps the assignment, so the row's leading button keeps
-- showing the assigned totem too (as DropSetsAssignment does for the assignment).
function ShamanPower:ShowsActiveTotemOnBar()
	if not self.opt.dynamicTotemMode then return false end
	return not (self.opt.gridStyle == true and self.GridActive and self:GridActive() and self.opt.gridDropAssigns == false)
end

function ShamanPower:PositionTotemButtons()
	if not self.autoButton then return end

	local padding = 4
	local spacing = self:TotemBarSpacing()   -- Button Spacing, plus room for dots between the buttons
	local isHorizontal = self:IsTotemBarHorizontal()
	-- Compact style: buttons are lines (bw x bh) inside a slot that may also hold an icon square
	local bw, bh, sw, sh, offX, offY = self:GetTotemSlotDims()
	local startOff = self.CompactStartOffset and self:CompactStartOffset() or 0   -- Compact shield line at the start
	local totemOrder = self.opt.totemBarOrder or {1, 2, 3, 4}

	-- Check which totem buttons should be visible (not hidden and not popped out)
	local elementVisible = {
		[1] = self:IsElementShown(1) and not self:IsElementPoppedOut(1),
		[2] = self:IsElementShown(2) and not self:IsElementPoppedOut(2),
		[3] = self:IsElementShown(3) and not self:IsElementPoppedOut(3),
		[4] = self:IsElementShown(4) and not self:IsElementPoppedOut(4),
	}

	local visiblePosition = 0
	for position = 1, 4 do
		local element = totemOrder[position]
		local btn = self.totemButtons[element]
		if btn then
			-- Skip popped out elements entirely (they're reparented elsewhere)
			if self:IsElementPoppedOut(element) then
				-- Don't touch popped out buttons
			elseif not elementVisible[element] then
				btn:Hide()
			else
				visiblePosition = visiblePosition + 1
				btn:ClearAllPoints()
				btn:SetSize(bw, bh)

				if isHorizontal then
					btn:SetPoint("TOPLEFT", self.autoButton, "TOPLEFT", padding + startOff + (visiblePosition - 1) * (sw + spacing) + offX, -padding + offY)
				else
					btn:SetPoint("TOPLEFT", self.autoButton, "TOPLEFT", padding + offX, -padding - startOff - (visiblePosition - 1) * (sh + spacing) + offY)
				end

				-- Match the scale of the visual container
				btn:SetScale(self.opt.buffscale or 0.9)
				btn:Show()
			end
		end
	end
end

-- Update totem buttons with spell info and position (called from UpdateMiniTotemBar)
function ShamanPower:UpdateTotemButtons()
	if InCombatLockdown() then return end
	if self:IsOff() then return end   -- switched off: the buttons (UIParent children) stay down

	-- Make sure totem buttons exist
	self:CreateTotemButtons()

	local playerName = self.player
	local assignments = ShamanPower_Assignments[playerName]
	if not assignments then return end

	local padding = 4
	local spacing = self:TotemBarSpacing()   -- Button Spacing, plus room for dots between the buttons
	local isHorizontal = self:IsTotemBarHorizontal()
	-- Compact style: buttons are lines (bw x bh) inside a slot that may also hold an icon square
	local bw, bh, sw, sh, offX, offY = self:GetTotemSlotDims()
	local startOff = self.CompactStartOffset and self:CompactStartOffset() or 0   -- Compact shield line at the start
	local totemOrder = self.opt.totemBarOrder or {1, 2, 3, 4}

	-- Check which totem buttons should be visible (not hidden in options and not popped out)
	local elementVisible = {
		[1] = self:IsElementShown(1) and not self:IsElementPoppedOut(1),
		[2] = self:IsElementShown(2) and not self:IsElementPoppedOut(2),
		[3] = self:IsElementShown(3) and not self:IsElementPoppedOut(3),
		[4] = self:IsElementShown(4) and not self:IsElementPoppedOut(4),
	}

	local visiblePosition = 0
	for position = 1, 4 do
		local element = totemOrder[position]
		local btn = self.totemButtons[element]

		if btn then
			local isPoppedOut = self:IsElementPoppedOut(element)

			-- Get totem spell - Dynamic Mode uses active totem, Normal Mode uses assignment.
			-- The icon also shows a flyout pick from a fight that is just ending (saved a
			-- moment later, in the regen pass); the spell attributes stay on the saved table.
			local totemIndex, shownIndex
			local activeIndex = self:ShowsActiveTotemOnBar() and self:GetActiveTotemIndex(element)
			if activeIndex then
				totemIndex, shownIndex = activeIndex, activeIndex
			else
				totemIndex, shownIndex = assignments[element] or 0, self:AssignedIndex(element)
			end

			local spellID = nil
			local spellName = nil
			local icon = self.ElementIcons[element]

			if totemIndex and totemIndex > 0 then
				spellID = self:GetTotemSpell(element, totemIndex)
				icon = self:GetTotemIcon(element, totemIndex)
				if spellID then
					spellName = GetSpellInfo(spellID)
					if SPCompat.HasTotemCastAliases(spellID) then spellName = SPCompat.TotemCastName(spellID) end
				end
			end
			if shownIndex ~= totemIndex then
				icon = shownIndex > 0 and self:GetTotemIcon(element, shownIndex) or self.ElementIcons[element]
			end

			-- Always update icon (even for popped out elements)
			-- Skip Air icon when twisting - the twist timer manages it to avoid flicker
			if btn.icon and not (element == 4 and self.opt.enableTotemTwisting) then
				btn.icon:SetTexture(icon)
			end
			self:ShowEmptySlotArt(element, shownIndex == 0)

			-- Always update spell attributes (even for popped out elements)
			-- Clear old attributes
			btn:SetAttribute("type", nil)
			btn:SetAttribute("type1", nil)
			btn:SetAttribute("spell", nil)
			btn:SetAttribute("spell1", nil)
			btn:SetAttribute("macrotext1", nil)

			-- Set up spell casting (same logic as XML buttons)
			if element == 4 and self.opt.enableTotemTwisting then
				local wfName = GetSpellInfo(8512) or "Windfury Totem"
				local twistName = self:GetTwistTotemName()
				btn:SetAttribute("type1", "macro")
				btn:SetAttribute("macrotext1", "/castsequence reset=combat/15 " .. wfName .. ", " .. twistName)
				-- Set initial twist icon (Windfury) if icon hasn't been set yet by twist timer
				if btn.icon then
					btn.icon:SetTexture("Interface\\Icons\\Spell_Nature_Windfury")
				end
			elseif spellName then
				btn:SetAttribute("type1", "spell")
				btn:SetAttribute("spell1", spellName)
			else
				-- Nothing assigned: keep the cast type, so a totem assigned from the flyout
				-- mid-fight (which can only write spell1) still casts, on both clients. A
				-- spell action with no spell does nothing.
				btn:SetAttribute("type1", "spell")
			end

			-- Right-click behavior: Totemic Call by default, assigned totem if option enabled, or flyout trigger
			btn:SetAttribute("shift-type2", nil)
			btn:SetAttribute("shift-spell2", nil)
			if self.opt.showTotemFlyouts and self:FlyoutOpensOnRightClick() then
				-- Right-click shows flyout instead of Totemic Call
				btn:SetAttribute("type2", nil)
				btn:SetAttribute("spell2", nil)
				self:ApplyShiftPullBack(btn, element)
			elseif self:RightClickDestroysTotems() then
				self:ApplyTotemDestroyAttributes(btn, element)
			elseif self.opt.activeTotemAsMain and self.opt.rightClickCastsAssigned then
				-- TotemTimers mode: right-click casts the assigned totem (shown in corner)
				local assignedIndex = assignments[element] or 0
				local assignedSpellID = assignedIndex > 0 and self:GetTotemSpell(element, assignedIndex)
				local assignedSpellName = assignedSpellID and GetSpellInfo(assignedSpellID)
				if SPCompat.HasTotemCastAliases(assignedSpellID) then
					assignedSpellName = SPCompat.TotemCastName(assignedSpellID)
				end
				if assignedSpellName then
					btn:SetAttribute("type2", "spell")
					btn:SetAttribute("spell2", assignedSpellName)
				else
					btn:SetAttribute("type2", "spell")
					btn:SetAttribute("spell2", GetSpellInfo(36936))  -- Totemic Call
				end
			else
				-- Right-click to cast Totemic Call (destroys all totems)
				btn:SetAttribute("type2", "spell")
				btn:SetAttribute("spell2", GetSpellInfo(36936))  -- Totemic Call
			end

			-- Handle visibility and positioning (only for non-popped-out elements)
			if not elementVisible[element] then
				-- Hide only if not popped out (popped out buttons are reparented)
				if not isPoppedOut then
					btn:Hide()
				elseif self.ApplyCompactButtonLayout then
					self:ApplyCompactButtonLayout(btn, true)   -- pop-outs keep their icon
				end
			else
				visiblePosition = visiblePosition + 1
				btn:Show()

				-- Position button relative to visual container
				btn:ClearAllPoints()
				btn:SetSize(bw, bh)
				if isHorizontal then
					btn:SetPoint("TOPLEFT", self.autoButton, "TOPLEFT", padding + startOff + (visiblePosition - 1) * (sw + spacing) + offX, -padding + offY)
				else
					btn:SetPoint("TOPLEFT", self.autoButton, "TOPLEFT", padding + offX, -padding - startOff - (visiblePosition - 1) * (sh + spacing) + offY)
				end

				-- Match the scale of the visual container
				btn:SetScale(self.opt.buffscale or 0.9)
				-- Compact style: draw the line visuals (or restore the icon)
				if self.ApplyCompactButtonLayout then self:ApplyCompactButtonLayout(btn) end
			end
		end
	end

	-- Hide the XML totem buttons since we're using the new totem buttons
	for element = 1, 4 do
		local xmlButton = _G["ShamanPowerAutoTotem" .. element]
		if xmlButton then
			xmlButton:Hide()
		end
	end

	-- a bar the layout keeps down (not in use here) or the hide rules keep down goes back down: the buttons
	-- above were shown for their layout (Dynamic Mode and the pop-outs run this after a fight too). Keybind
	-- Mode's bar stays up
	if not (self.KeybindModeActive and self:KeybindModeActive()) and (not self:TotemBarInUse()
		or (self.totemBarHidden and (self.opt.hideOutOfCombat or self.opt.hideWhenNoTotems
			or (self.ControllerHidesTotemBar and self:ControllerHidesTotemBar())))) then
		self:SetTotemBarFramesShown(false)
	end
end

-- Create flyout menu for an element
-- Which way this element's flyout opens: "top", "bottom", "left" or "right".
function ShamanPower:FlyoutDirection(flyout)
	local element = flyout and flyout.element
	if element and self:IsElementPoppedOut(element) then
		local key = "totem_" .. self.Elements[element]:lower()
		local settings = self.opt.poppedOutSettings and self.opt.poppedOutSettings[key]
		if settings and settings.flyoutDirection then return settings.flyoutDirection end
	end
	if not self:IsTotemBarHorizontal() then
		local isVerticalLeft = (self.opt.layout == "VerticalLeft") and not self:CompactActive()
		return isVerticalLeft and "left" or "right"
	end
	return self:FlyoutGoesBelow(flyout.totemButton) and "bottom" or "top"
end

-- Arrows exist while the arrow layout is on (see spFlyoutArrowLayout). Texture
-- alpha is used for the hover highlight because regions are never protected.
local function spFlyoutArrowAlpha(arrow, hovered)
	if not arrow then return end
	local a = 0
	if spFlyoutArrowLayout() then a = hovered and 1 or 0.85 end
	-- The close tab sits on top of the open tab while the flyout is up, and its
	-- art has transparent parts, so the open tab's art goes away for that time.
	-- (The frame cannot be hidden in combat; its textures can.)
	if arrow.spHideWhileShown and arrow.spHideWhileShown:IsShown() then a, hovered = 0, false end
	arrow.tex:SetAlpha(a)
	arrow.glow:SetAlpha((spFlyoutArrowLayout() and hovered) and 1 or 0)
end

local function spFlyoutMakeArrow(name, parent, box, unitValue)
	local b = _G[name] or CreateFrame("Button", name, parent, "SecureActionButtonTemplate")
	b:SetParent(parent)
	b:RegisterForClicks("AnyUp", "AnyDown")
	b:SetAttribute("type", "attribute")
	b:SetAttribute("attribute-frame", box)
	b:SetAttribute("attribute-name", "unit")
	b:SetAttribute("attribute-value", unitValue)
	if not b.tex then
		b.tex = b:CreateTexture(nil, "ARTWORK")
		b.tex:SetAllPoints()
		b.tex:SetTexture(ARROW_TEXTURE)
		b.glow = b:CreateTexture(nil, "OVERLAY")
		b.glow:SetPoint("CENTER")
		b.glow:SetTexture(ARROW_TEXTURE)
		b.glow:SetBlendMode("ADD")
		b.glow:SetAlpha(0)
		b:HookScript("OnEnter", function(self) spFlyoutArrowAlpha(self, true) end)
		b:HookScript("OnLeave", function(self)
			spFlyoutArrowAlpha(self, false)
			if self.spOwner then spFlyoutScheduleClose(self.spOwner) end
		end)
	end
	return b
end

-- Every flyout running in box mode, by key: 1-4 for the totem elements, "S" for
-- the shield flyout and "I" for the weapon imbue flyout on the cooldown bar.
-- { flyout =, button =, relayout = function } - relayout re-runs that flyout's
-- own layout, which is how the combat layout (arrow gap) is applied and undone.
ShamanPower.boxFlyouts = {}

-- Create (once per button) the watched box and its two arrows for a flyout.
function ShamanPower:EnsureFlyoutBox(element, totemButton, flyout, relayout)
	if InCombatLockdown() then return totemButton.spFlyoutBox end
	self.boxFlyouts[element] = { flyout = flyout, button = totemButton, relayout = relayout or function() end }
	local box = totemButton.spFlyoutBox
	if not box then
		box = _G["ShamanPowerFlyoutBox" .. element]
			or CreateFrame("Frame", "ShamanPowerFlyoutBox" .. element, totemButton, "SecureFrameTemplate")
		box:SetParent(totemButton)
		box:SetFrameLevel(totemButton:GetFrameLevel() + 8)   -- above the active-totem overlay (+5)
		box:SetAllPoints(totemButton)
		box:SetAttribute("unit", "none")
		box:Hide()
		RegisterUnitWatch(box)
		box.spFlyoutOwner = totemButton
		totemButton.spFlyoutBox = box

		local open = spFlyoutMakeArrow("ShamanPowerFlyoutOpen" .. element, totemButton, box, "player")
		local close = spFlyoutMakeArrow("ShamanPowerFlyoutClose" .. element, box, box, "none")
		open.spOwner, close.spOwner = totemButton, totemButton
		-- (a tab reused by name from a rebuilt bar: its mouse as its button's now, Show Items Only
		-- When Running Out takes it away with a hidden cooldown bar button: ShamanPowerCues.lua)
		open:EnableMouse(not totemButton._roMouseOff)
		-- Invisible press targets for macros (short names keep every macro far
		-- below the length limit). Per flyout key K:
		--   SPFO<K> / SPFC<K>  attribute: open / close the box
		--   SPFT<K>            macro: the TOGGLE the keybind presses
		--   SPFA<K> / SPFR<K>  attribute: rewrite SPFT's macrotext to its "close"
		--                      / "open" form (arm / reset)
		-- A key cannot ask whether the flyout is open (hidden buttons still
		-- answer /click, measured), so the toggle carries its own state: each
		-- press rewrites what the next press will do, and every other way a
		-- flyout closes presses SPFC + SPFR so the toggle never falls out of step.
		-- The macro texts themselves are filled in by ApplyFlyoutArrowMode.
		--
		-- Two rules learned the hard way (both measured in game):
		--   * a macro may press attribute buttons, but a macro-type button
		--     pressed from inside a macro does not run, so every macro here is
		--     flat: it presses SPFO/SPFC/SPFA/SPFR directly, never another macro;
		--   * the attribute helpers set useOnKeyDown = false, so they act on a
		--     click RELEASE whatever the player's key-down setting is, and a bare
		--     "/click NAME" (which sends a release) is all a macro needs. That
		--     keeps the longest macro (close five others, open mine) near 150
		--     characters, well inside the macro length limit.
		local function helper(prefix)
			local h = _G[prefix .. element] or CreateFrame("Button", prefix .. element, totemButton, "SecureActionButtonTemplate")
			h:SetParent(totemButton)   -- a rebuilt cooldown bar hands us a new button
			h:SetSize(1, 1)
			h:SetPoint("CENTER", totemButton, "CENTER")
			h:EnableMouse(false)
			h:RegisterForClicks("AnyUp", "AnyDown")
			return h
		end
		for _, def in ipairs({ { "SPFO", "player" }, { "SPFC", "none" } }) do
			local h = helper(def[1])
			h:SetAttribute("useOnKeyDown", false)
			h:SetAttribute("type", "attribute")
			h:SetAttribute("attribute-frame", box)
			h:SetAttribute("attribute-name", "unit")
			h:SetAttribute("attribute-value", def[2])
		end
		local toggle = helper("SPFT")   -- pressed by a real key: follows the player's key-down setting
		toggle:SetAttribute("type", "macro")
		for _, prefix in ipairs({ "SPFA", "SPFR" }) do
			local h = helper(prefix)
			h:SetAttribute("useOnKeyDown", false)
			h:SetAttribute("type", "attribute")
			h:SetAttribute("attribute-frame", toggle)
			h:SetAttribute("attribute-name", "macrotext")
		end
		open.spHideWhileShown = box
		if not box.spArrowHooked then
			box.spArrowHooked = true
			box:HookScript("OnShow", function(self)
				spFlyoutArrowAlpha(self.spOpenArrow, false)
				ShamanPower._barWake = true   -- its buttons' cooldowns are only read while it is on screen
				-- opened by its arrow or key out of combat: same refresh a hover-open gets
				local entry = ShamanPower.boxFlyouts[element]
				if entry and not InCombatLockdown() and not self.spRelayouting then
					self.spRelayouting = true
					pcall(entry.relayout)
					self.spRelayouting = nil
				end
			end)
			box:HookScript("OnHide", function(self) spFlyoutArrowAlpha(self.spOpenArrow, false) end)
		end
		box.spOpenArrow = open
		open:SetFrameLevel(totemButton:GetFrameLevel() + 7)
		close:SetFrameLevel(totemButton:GetFrameLevel() + 12)   -- covers the open arrow while the box is up
		totemButton.spFlyoutOpenArrow, totemButton.spFlyoutCloseArrow = open, close
		if not totemButton.spFlyoutArrowHooked then
			totemButton.spFlyoutArrowHooked = true
			totemButton:HookScript("OnEnter", function(self) spFlyoutArrowAlpha(self.spFlyoutOpenArrow, true) end)
			totemButton:HookScript("OnLeave", function(self) spFlyoutArrowAlpha(self.spFlyoutOpenArrow, false) end)
		end
	end
	flyout.box = box
	flyout.leadGap = self:FlyoutLeadGap(flyout)
	self.flyoutArrowGap = spFlyoutArrowLayout() and FLYOUT_ARROW or 0
	self:ApplyFlyoutArrowMode()
	return box
end

-- opt.flyoutSingleOpen (default on): an arrow closes every other flyout before
-- opening its own, so only one is ever open. Off: the arrow just opens its own
-- and the rest stay until picked from or closed. A macro cannot set attributes,
-- so the "on" form presses the SPFC/SPFO helper buttons instead.
function ShamanPower:ApplyFlyoutArrowMode()
	if InCombatLockdown() then
		self.flyoutArrowModePending = true
		return
	end
	self.flyoutArrowModePending = nil
	local single = self.opt.flyoutSingleOpen ~= false

	for key, entry in pairs(self.boxFlyouts) do
		-- close: shut the box, reset the toggle
		local mClose = "/click SPFC" .. key .. "\n/click SPFR" .. key
		-- open: (single-open) close and reset every other flyout, open mine, arm the toggle
		local lines = {}
		if single then
			for other in pairs(self.boxFlyouts) do
				if other ~= key then
					lines[#lines + 1] = "/click SPFC" .. other
					lines[#lines + 1] = "/click SPFR" .. other
				end
			end
		end
		lines[#lines + 1] = "/click SPFO" .. key
		lines[#lines + 1] = "/click SPFA" .. key
		local mOpen = table.concat(lines, "\n")
		entry.mOpen, entry.mClose = mOpen, mClose

		local A, R, T = _G["SPFA" .. key], _G["SPFR" .. key], _G["SPFT" .. key]
		if A and R and T then
			A:SetAttribute("attribute-value", mClose)   -- armed: next press closes
			R:SetAttribute("attribute-value", mOpen)    -- reset: next press opens
			local box = entry.button and entry.button.spFlyoutBox
			T:SetAttribute("macrotext", (box and box:IsShown()) and mClose or mOpen)
		end
		-- the visible tabs do exactly what the toggle does
		local btn = entry.button
		if btn and btn.spFlyoutOpenArrow then
			btn.spFlyoutOpenArrow:SetAttribute("type", "macro")
			btn.spFlyoutOpenArrow:SetAttribute("macrotext", mOpen)
		end
		if btn and btn.spFlyoutCloseArrow then
			btn.spFlyoutCloseArrow:SetAttribute("type", "macro")
			btn.spFlyoutCloseArrow:SetAttribute("macrotext", mClose)
		end
	end

	-- SPFCALL: one invisible button that closes every flyout (keybind target)
	local all = _G.SPFCALL or CreateFrame("Button", "SPFCALL", UIParent, "SecureActionButtonTemplate")
	all:SetSize(1, 1)
	all:EnableMouse(false)
	all:RegisterForClicks("AnyUp", "AnyDown")
	local lines = {}
	for key in pairs(self.boxFlyouts) do
		lines[#lines + 1] = "/click SPFC" .. key
		lines[#lines + 1] = "/click SPFR" .. key
	end
	all:SetAttribute("type", "macro")
	all:SetAttribute("macrotext", table.concat(lines, "\n"))
end

-- What clicking an icon inside a box-mode flyout does. Each button carries its
-- plain cast text per mouse button in btn.spPick (set where the button is
-- built); opt.flyoutCloseOnCast (default on) appends the two presses that close
-- the flyout and put its toggle key back to "open".
-- A hidden secure button a flyout macro presses with a bare /click: it acts on
-- release whatever ActionButtonUseKeyDown says, and needs no size or mouse.
function ShamanPower:FlyoutAssignHelper(name, parent)
	local h = _G[name] or CreateFrame("Button", name, parent, "SecureActionButtonTemplate")
	h:SetParent(parent)
	h:SetSize(1, 1)
	h:ClearAllPoints()
	h:SetPoint("CENTER", parent, "CENTER")
	h:EnableMouse(false)
	h:RegisterForClicks("AnyUp", "AnyDown")
	h:SetAttribute("useOnKeyDown", false)
	return h
end

-- Point every SPFM helper at the right slot and spell of Blizzard's totem bar
-- (ranks, the sync option and the Drop All excludes all change the answer).
-- Out of combat only; the start of a fight is the last call.
function ShamanPower:RefreshTotemBarHelpers()
	if InCombatLockdown() then return end
	for element = 1, 4 do
		local flyout = self.totemFlyouts and self.totemFlyouts[element]
		if flyout then
			for _, btn in ipairs(flyout.allButtons or {}) do
				local M = _G["SPFM" .. element .. "_" .. btn.totemIndex]
				if M then
					local action, spell
					if self.TotemBarSlotSpell then action, spell = self:TotemBarSlotSpell(element, btn.totemIndex) end
					M:SetAttribute("type", action and "multispell" or nil)
					M:SetAttribute("action", action)
					M:SetAttribute("spell", spell)
				end
			end
		end
	end
end

function ShamanPower:ApplyFlyoutPickMacros()
	if InCombatLockdown() then
		self.flyoutPickPending = true
		return
	end
	self.flyoutPickPending = nil
	local closeOnCast = self.opt.flyoutCloseOnCast ~= false
	for key, entry in pairs(self.boxFlyouts) do
		local flyout = entry.flyout
		local tail = closeOnCast and ("\n/click SPFC" .. key .. "\n/click SPFR" .. key) or ""
		for _, btn in ipairs(flyout.allButtons or flyout.buttons or {}) do
			for n, base in pairs(btn.spPick or {}) do
				btn:SetAttribute("type" .. n, "macro")
				btn:SetAttribute("macrotext" .. n, base .. tail)
			end
		end
	end
end

-- Out of combat the box is opened and closed directly (hover, assignment, the
-- end-of-fight sweep), so the toggle is put in step directly too.
function ShamanPower:SyncFlyoutToggle(button, shown)
	for key, entry in pairs(self.boxFlyouts) do
		if entry.button == button then
			local T = _G["SPFT" .. key]
			if T and entry.mOpen and not InCombatLockdown() then
				T:SetAttribute("macrotext", shown and entry.mClose or entry.mOpen)
			end
			return
		end
	end
end

-- Put both arrows on the edge the flyout opens from, pointing the right way.
function ShamanPower:PlaceFlyoutArrows(flyout)
	local btn = flyout and (flyout.anchorButton or flyout.totemButton)
	if not btn or not btn.spFlyoutOpenArrow or InCombatLockdown() then return end
	if btn.spGridPinned then
		btn.spFlyoutOpenArrow:Hide()
		if btn.spFlyoutCloseArrow then btn.spFlyoutCloseArrow:Hide() end
		self:DressFlyoutFrame(flyout)
		btn.spFlyoutArrowSide = nil
		self:FollowFlyoutArrows(btn)
		return
	end
	local dir = flyout.arrowDir or self:FlyoutDirection(flyout)
	btn.spFlyoutArrowSide = dir   -- where the tab is: what we draw on this side steps out past it
	local element = flyout.artIndex or flyout.element or 5
	local sideways = (dir == "left" or dir == "right")
	for _, arrow in ipairs({ btn.spFlyoutOpenArrow, btn.spFlyoutCloseArrow }) do
		-- the tab sits centred on the edge the flyout opens from, tucked 2 px in
		arrow:ClearAllPoints()
		-- never longer than the edge it sits on (cooldown bar buttons are 22 px; a
		-- Compact row is a thin bar, and a sideways tab runs along its HEIGHT)
		local edge = sideways and btn:GetHeight() or btn:GetWidth()
		local k = math.min(1, ((edge and edge > 0) and edge or ARROW_W) / ARROW_W)
		local tw, th = ARROW_W * k, ARROW_H * k
		arrow:SetSize(sideways and th or tw, sideways and tw or th)
		if dir == "bottom" then
			arrow:SetPoint("TOP", btn, "BOTTOM", 0, 2)
		elseif dir == "left" then
			arrow:SetPoint("RIGHT", btn, "LEFT", 2, 0)
		elseif dir == "right" then
			arrow:SetPoint("LEFT", btn, "RIGHT", -2, 0)
		else
			arrow:SetPoint("BOTTOM", btn, "TOP", 0, -2)
		end
		local isClose = (arrow == btn.spFlyoutCloseArrow)
		local art = (isClose and ARROW_CLOSE or ARROW_OPEN)[element] or ARROW_OPEN[1]
		if arrow.spFlatTab then arrow.tex:SetTexture(ARROW_TEXTURE); arrow.spFlatTab = nil end   -- back from a theme's flat tab
		arrow.tex:SetTexCoord(spArrowCoords(art, dir))
		-- General > Themes (tb.flyout-art): a flat tab in the element colour; nil = the art above
		local fr, fg, fb = self:ThemeFlyoutTabColor(flyout, element)
		if fr then arrow.tex:SetColorTexture(fr, fg, fb, 1); arrow.spFlatTab = true end
		arrow.glow:SetSize((sideways and 11 or 20) * k, (sideways and 20 or 11) * k)
		arrow.glow:SetTexCoord(spArrowCoords(isClose and ARROW_GLOW_CLOSE or ARROW_GLOW_OPEN, dir))
		-- (none on the hidden custom bar while Blizzard's own totem bar is the style)
		local enabled = flyout.isCdbarFlyout or (self.opt.showTotemFlyouts and not (self.UsingBlizzardTotemBar and self:UsingBlizzardTotemBar()))
		local anything = false
		for _, b in ipairs(flyout.buttons or {}) do
			if b:IsShown() then anything = true break end
		end
		-- in the arrow layout only, only with flyouts on, and never for a flyout with nothing in it
		arrow:SetShown((enabled and anything and spFlyoutArrowLayout()) and true or false)
		spFlyoutArrowAlpha(arrow, false)
	end
	self:DressFlyoutFrame(flyout)
	if self.RefreshCompactSquares then self:RefreshCompactSquares() end   -- Compact's icon square steps out past the tab
	self:FollowFlyoutArrows(btn)   -- and so do the pulse / duration bars, dots and overlay on that side
end

-- How far a button's arrow tab sticks out on `side` ("top"/"bottom"/"left"/
-- "right"); 0 when there is no tab there right now.
-- How far an arrow tab WILL stick out of a button on `dir` while the arrow layout
-- is on. From the button's size, not the tab frame: the flyout is laid out
-- before the tabs are placed.
function ShamanPower:FlyoutArrowAcross(btn, dir)
	if not (btn and spFlyoutArrowLayout()) then return 0 end
	local sideways = (dir == "left" or dir == "right")
	local edge = sideways and btn:GetHeight() or btn:GetWidth()
	local k = math.min(1, ((edge and edge > 0) and edge or ARROW_W) / ARROW_W)
	return math.max(0, math.floor(ARROW_H * k - 2 + 0.5))   -- the tab is tucked 2 px into the button
end

-- Room between a button and the first icon of its flyout, measured so the pieces
-- butt up against each other with no gap and no overlap:
--   button | arrow tab | (Compact: the icon square, when it is on this end) | flyout
-- The tab is scaled to the edge it sits on (a thin Compact line or a 22 px
-- cooldown button gets a smaller tab than a 28 px totem button), so the room is
-- the tab's real size, not a constant. The icons-only style keeps the tab clear;
-- in the frame style the first icon covers the open tab, so only the square counts.
function ShamanPower:FlyoutLeadGap(flyout)
	local btn = flyout and (flyout.anchorButton or flyout.totemButton)
	if not btn then return spFlyoutLeadGap() end
	local dir = flyout.arrowDir or self:FlyoutDirection(flyout)
	local across = self:FlyoutArrowAcross(btn, dir)
	local lead = (spFlyoutLeadGap() > 0) and across or 0
	if flyout.element and self.CompactSquareExtent then
		local sq = self:CompactSquareExtent(btn, dir)        -- square plus its border, 0 if none on this end
		if sq > 0 then lead = math.max(lead, self:CompactSquareOffset(across) - 1 + sq) end
	end
	return lead
end

-- Where Compact's icon square starts, measured from the end of the line: hard
-- against the arrow tab when there is one (1 px is the square's own border),
-- otherwise the usual 2 px off the line.
function ShamanPower:CompactSquareOffset(across)
	return (across and across > 0) and (across + 1) or 2
end

function ShamanPower:FlyoutArrowGapOn(btn, side)
	local arrow = btn and btn.spFlyoutOpenArrow
	if not (arrow and arrow:IsShown() and spFlyoutArrowLayout()) then return 0 end
	-- the edge PlaceFlyoutArrows put the tab on (a cooldown bar button has no element)
	local dir = btn.spFlyoutArrowSide
	if not dir then
		local flyout = btn.element and self.totemFlyouts and self.totemFlyouts[btn.element]
		dir = flyout and (flyout.arrowDir or self:FlyoutDirection(flyout))
	end
	if dir ~= side then return 0 end
	return self:FlyoutArrowAcross(btn, dir)
end

-- Room the tab takes on each side of a button: top, bottom, left, right (only
-- the tab's own side is ever above 0), as FollowFlyoutArrows last found it.
-- Everything we draw outside a button on a side adds this to its distance from
-- the button, so it sits out past the tab instead of behind it. Plain fields,
-- so the per-tick cooldown bar code can read it too.
function ShamanPower:FlyoutArrowPads(btn)
	if not btn then return 0, 0, 0, 0 end
	return btn.spArrowPadT or 0, btn.spArrowPadB or 0, btn.spArrowPadL or 0, btn.spArrowPadR or 0
end

-- A button's tab appeared, moved or went (PlaceFlyoutArrows, which only runs out
-- of combat: the start and end of a fight, an arrow option, a relayout). When its
-- room changed, place again what we draw outside that button: its pulse and
-- duration bars with their numbers, the party dots, the dropped-totem overlay,
-- or on the cooldown bar the shield / imbue bars and their text. Layout changes
-- only; nothing here runs per frame. No option: it follows the tab by itself.
function ShamanPower:FollowFlyoutArrows(btn)
	if not btn or InCombatLockdown() then return end
	local side = btn.spFlyoutArrowSide
	local gap = side and self:FlyoutArrowGapOn(btn, side) or 0
	local t, b = (side == "top") and gap or 0, (side == "bottom") and gap or 0
	local l, r = (side == "left") and gap or 0, (side == "right") and gap or 0
	local oT, oB, oL, oR = self:FlyoutArrowPads(btn)
	if t == oT and b == oB and l == oL and r == oR then return end
	btn.spArrowPadT, btn.spArrowPadB, btn.spArrowPadL, btn.spArrowPadR = t, b, l, r
	-- a popped-out button's own panel reaches out past its tab too
	local host = btn:GetParent()
	if host and host.key and self.poppedOutFrames and self.poppedOutFrames[host.key] == host then
		self:FitBarBackdrop(host)
	end
	if btn.cooldownType then
		if self.UpdateCooldownBarProgressBars then self:UpdateCooldownBarProgressBars() end
		self:FitBarBackdrop(self.cooldownBar)
		return
	end
	self:FitBarBackdrop(self.autoButton)
	local element = btn.element
	if not (element and self.totemButtons and self.totemButtons[element] == btn) then return end
	local pulse = self.pulseOverlays and self.pulseOverlays[element]
	if pulse and pulse.button == btn then self:PositionPulseWipe(pulse) end
	self:UpdateTotemProgressBarPositions()
	self:PlacePartyDotFrame(btn)
	self:PositionActiveOverlays()
end

-- "Show frame behind the bar": what a bar draws past a flyout tab (pulse and
-- duration bars, their numbers, the dots) sits outside the bar, so the frame
-- reaches out by the same room on the tab's side while the tab shows, and comes
-- back with it. The bar itself is not resized (everything on it is laid out
-- from its corner, and the totem bar is a secure frame): the backdrop's four
-- corner textures are anchored out instead, and its edges and fill hang off
-- them. Layout time only, never in lockdown: FollowFlyoutArrows (the start and
-- end of a fight, a relayout) and wherever the backdrop is set again.
function ShamanPower:FitBarBackdrop(bar)
	if not (bar and bar.backdropInfo and bar.TopLeftCorner and bar.TopRightCorner
		and bar.BottomLeftCorner and bar.BottomRightCorner) or InCombatLockdown() then return end
	local t, b, l, r = 0, 0, 0, 0
	if bar == self.autoButton then
		-- the totem buttons on the bar (popped-out ones have their own frame)
		for element = 1, 4 do
			local btn = self.totemButtons and self.totemButtons[element]
			if btn and self:IsElementShown(element) and not self:IsElementPoppedOut(element) then
				local bt, bb, bl, br = self:FlyoutArrowPads(btn)
				t, b, l, r = math.max(t, bt), math.max(b, bb), math.max(l, bl), math.max(r, br)
			end
		end
	elseif bar == self.cooldownBar then
		for _, btn in ipairs(self.cooldownButtons or {}) do
			if btn:GetParent() == bar and btn:IsShown() then
				local bt, bb, bl, br = self:FlyoutArrowPads(btn)
				t, b, l, r = math.max(t, bt), math.max(b, bb), math.max(l, bl), math.max(r, br)
			end
		end
	elseif bar.key and self.poppedOutFrames and self.poppedOutFrames[bar.key] == bar then
		-- a pop-out panel holds one button
		local btn = bar.button
		if btn and btn:GetParent() == bar then t, b, l, r = self:FlyoutArrowPads(btn) end
	end
	-- all 0: the anchors the backdrop gives them itself
	bar.TopLeftCorner:SetPoint("TOPLEFT", bar, "TOPLEFT", -l, t)
	bar.TopRightCorner:SetPoint("TOPRIGHT", bar, "TOPRIGHT", r, t)
	bar.BottomLeftCorner:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", -l, -b)
	bar.BottomRightCorner:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", r, -b)
end

-- Optional Blizzard-style frame around an open flyout (opt.flyoutStyle ==
-- "frame"). Pure artwork: textures on the box, so they appear and vanish with
-- the flyout by themselves, in and out of combat. Blizzard's proportions are
-- for 24 px buttons in a 32 px frame, scaled here to our button size. As on
-- Blizzard's bar the close tab moves to the far end, into the cap's notch; a
-- copy of the tab art is drawn there as decoration so the cap never looks
-- empty out of combat, where the real tab is hidden.
function ShamanPower:DressFlyoutFrame(flyout)
	local btn = flyout and (flyout.anchorButton or flyout.totemButton)
	local box = flyout and flyout.box
	if not btn or not box then return end
	if btn.spGridPinned then
		if box.frameFill then box.frameFill:Hide() end
		if box.frameBand then box.frameBand:Hide() end
		if box.frameCap then box.frameCap:Hide() end
		if box.frameFoot then box.frameFoot:Hide() end
		if box.frameTab then box.frameTab:Hide() end
		if box.frameSlot then box.frameSlot:Hide() end
		return false
	end
	if not box.frameArt then
		-- The panel wraps the totem button too, so it is drawn on a plain frame
		-- one level BELOW the button (the box itself sits above it): the button's
		-- icon stays on top of the panel's fill. It is the box's child, so it
		-- still comes and goes with the flyout.
		local art = CreateFrame("Frame", nil, box)
		art:SetAllPoints(btn)
		box.frameArt = art
		-- Blizzard's panel art is translucent, so the world shows through it. A
		-- dark backing inside the border gives it a solid body; it follows the
		-- Frame Opacity slider with the rest of the panel.
		box.frameFill = art:CreateTexture(nil, "BACKGROUND", nil, -3)
		box.frameFill:SetColorTexture(0, 0, 0, 1)
		box.frameBand = art:CreateTexture(nil, "BACKGROUND", nil, -2)
		box.frameCap = art:CreateTexture(nil, "BACKGROUND", nil, -1)
		box.frameFoot = art:CreateTexture(nil, "BACKGROUND", nil, -1)
		box.frameTab = box:CreateTexture(nil, "BORDER")   -- the tab stays above everything
		for _, t in ipairs({ box.frameBand, box.frameCap, box.frameFoot, box.frameTab }) do t:SetTexture(ARROW_TEXTURE) end
	end
	box.frameArt:SetFrameLevel(math.max(0, btn:GetFrameLevel() - 1))
	local band, cap, foot, tab = box.frameBand, box.frameCap, box.frameFoot, box.frameTab
	if box.frameSlot then box.frameSlot:Hide() end

	local count = 0
	for _, b in ipairs(flyout.buttons or {}) do
		if b:IsShown() then count = count + 1 end
	end
	local fill = box.frameFill
	if self.opt.flyoutStyle ~= "frame" or count == 0 then
		band:Hide(); cap:Hide(); foot:Hide(); tab:Hide(); fill:Hide()
		return false
	end

	local dir = flyout.arrowDir or self:FlyoutDirection(flyout)
	local opposite = ({ top = "bottom", bottom = "top", left = "right", right = "left" })[dir] or "bottom"
	local sideways = (dir == "left" or dir == "right")
	local art = flyout.artIndex or flyout.element or 5
	local size = flyout.buttonSize or 28
	local f = size / 24                                  -- Blizzard's art is for 24 px icons
	local lead = flyout.leadGap or 0
	local bw, bh = btn:GetWidth() or 30, btn:GetHeight() or 30
	local bAlong, bAcross = sideways and bw or bh, sideways and bh or bw
	-- One even border all the way round: Blizzard shows 4 px of panel beside a
	-- 24 px icon, so the same margin (scaled) is kept beside the totem button,
	-- which is the widest thing inside the frame, and below it.
	local margin = 4 * f
	local pad = margin                                   -- how far the frame reaches past the totem button
	local capLen, tabW, tabH = 20 * f, ARROW_W * f, ARROW_H * f
	local wide = math.max(32 * f, bAcross + 2 * margin)
	-- Distances are measured along the flyout's direction from the button edge
	-- it opens from: positive is out into the flyout, negative is back across
	-- the totem button.
	local length = lead + count * (size + (flyout.spacing or 0)) + 20 * f   -- 2 px pad + the 18 px tab
	local farCapStart = length - 30 * f                                      -- the far cap starts 10 px in from the end
	local footStart = -bAlong - pad

	local function place(region, start, len, across)
		region:ClearAllPoints()
		if dir == "bottom" then
			region:SetPoint("TOP", btn, "BOTTOM", 0, -start);  region:SetSize(across, len)
		elseif dir == "left" then
			region:SetPoint("RIGHT", btn, "LEFT", -start, 0);  region:SetSize(len, across)
		elseif dir == "right" then
			region:SetPoint("LEFT", btn, "RIGHT", start, 0);   region:SetSize(len, across)
		else
			region:SetPoint("BOTTOM", btn, "TOP", 0, start);   region:SetSize(across, len)
		end
	end

	-- backing: inside the border, from the foot to the far cap's outer edge
	local inset = 2 * f
	local fillStart, fillEnd = footStart + inset, (length - 10 * f) - inset
	place(fill, fillStart, fillEnd - fillStart, wide - 2 * inset)
	place(foot, footStart, capLen, wide)                                   -- closes the frame under the button
	place(band, footStart + capLen, farCapStart - (footStart + capLen), wide)
	place(cap, farCapStart, capLen, wide)
	place(tab, length - tabH, tabH, tabW)
	-- the foot is the cap turned to face the other way
	foot:SetTexCoord(spArrowCoords(FRAME_CAP[art] or FRAME_CAP[5], opposite))
	band:SetTexCoord(spArrowCoords(FRAME_BAND[art] or FRAME_BAND[5], dir))
	cap:SetTexCoord(spArrowCoords(FRAME_CAP[art] or FRAME_CAP[5], dir))
	if tab.spFlatTab then tab:SetTexture(ARROW_TEXTURE); tab.spFlatTab = nil end   -- back from a theme's flat tab
	tab:SetTexCoord(spArrowCoords(ARROW_CLOSE[art] or ARROW_CLOSE[5], dir))
	-- General > Themes (tb.flyout-art): the tab drawn flat in the element colour; nil = the art above
	local fr, fg, fb = self:ThemeFlyoutTabColor(flyout, art)
	if fr then tab:SetColorTexture(fr, fg, fb, 1); tab.spFlatTab = true end

	-- The panel (border and fill) has its own opacity on top of the flyout's; the
	-- tab keeps the flyout's, so it never fades out of reach.
	-- a shield / imbue flyout follows the CD Flyouts opacity, not the totem one
	local alpha = (flyout.isCdbarFlyout and self:CdItemOpt(flyout.cdItemType, "flyoutOpacity") or self.opt.totemFlyoutOpacity) or 1.0
	local panelAlpha = alpha * (self.opt.flyoutFrameOpacity or 1.0)
	for _, t in ipairs({ band, cap, foot }) do t:SetAlpha(panelAlpha); t:Show() end
	fill:SetAlpha(panelAlpha * 0.85); fill:Show()
	tab:SetAlpha(alpha); tab:Show()

	-- The real close tab sits exactly on the decorative one. It is anchored to the
	-- totem button with the same numbers rather than to the texture: a protected
	-- frame may not be anchored to a region.
	local close = btn.spFlyoutCloseArrow
	if close and not InCombatLockdown() then
		place(close, length - tabH, tabH, tabW)
	end
	return true
end

-- Box mode keeps every eligible button SHOWN inside the (hidden) box, because
-- nothing can show them individually once a fight starts. Out of combat only.
function ShamanPower:SyncCombatFlyoutButtons(element)
	local flyout = self.totemFlyouts[element]
	if not flyout or not flyout.box or InCombatLockdown() then return end
	if self.GridLayoutElement and self:GridLayoutElement(element) then return end
	for _, btn in ipairs(flyout.allButtons or {}) do
		local show = not btn.isDisabledInFlyout
			and not btn:GetAttribute("isCurrentAssignment")
			and not btn:GetAttribute("flyoutHidden")
		btn:SetShown(show and true or false)
	end
	self:PlaceFlyoutArrows(flyout)
end

-- A flyout left OPEN while its choices change (TotemTimers Style / Single Totem:
-- a drop changes which totem the flyout leaves out): show and hide its buttons
-- as opening it does, so the re-laid list has no gap and no button left under
-- another. Out of combat, not for the box (SyncCombatFlyoutButtons does that),
-- and a closed flyout is left alone (opening it does this).
function ShamanPower:SyncOpenFlyoutButtons(element)
	local flyout = self.totemFlyouts and self.totemFlyouts[element]
	if not flyout or flyout.box or InCombatLockdown() then return end
	if self.GridLayoutElement and self:GridLayoutElement(element) then return end
	local buttons = flyout.allButtons or flyout.buttons
	if not buttons then return end
	local open = false
	for _, btn in ipairs(buttons) do
		if btn:IsShown() then open = true break end
	end
	if not open then return end
	for _, btn in ipairs(buttons) do
		local show = not btn.isDisabledInFlyout
			and not btn:GetAttribute("isCurrentAssignment")
			and not btn:GetAttribute("flyoutHidden")
		btn:SetShown(show and true or false)
	end
end

-- The totem flyout buttons' secure handlers, shared by every totem button and
-- the "Empty" choice. The parent broadcasts them with ChildUpdate: "show" opens
-- or closes the flyout, "assignment" tells each button whether it now holds the
-- totem button's spell (message = the new spell, nil for Empty), and "relayout"
-- closes the gap the assigned one leaves.
local SP_FLYOUT_CHILD_SHOW = [[
		if self:GetAttribute("spGridPinned") then return end
		if message then
			if not self:GetAttribute("isCurrentAssignment") and not self:GetAttribute("flyoutHidden") then
				self:Show()
			end
		else
			self:Hide()
		end
	]]
local SP_FLYOUT_CHILD_ASSIGNMENT = [[
		-- a popped-out totem is shown on its own button, never in the flyout
		if self:GetAttribute("spPoppedOut") then
			self:SetAttribute("isCurrentAssignment", true)
			return
		end
		local newSpell = message
		local mySpell = self:GetAttribute("mySpell")
		if newSpell == mySpell then
			self:SetAttribute("isCurrentAssignment", true)
		else
			self:SetAttribute("isCurrentAssignment", false)
		end
	]]
local SP_FLYOUT_CHILD_RELAYOUT = [[
		if self:GetAttribute("spGridPinned") then return end
		-- If I'm the current assignment, I don't need to position myself (I'll be hidden)
		if self:GetAttribute("isCurrentAssignment") or self:GetAttribute("flyoutHidden") then
			return
		end

		local parent = self:GetParent()
		local buttonSize = parent:GetAttribute("flyoutButtonSize") or 28
		local spacing = parent:GetAttribute("flyoutSpacing") or 0
		local isVerticalLeft = parent:GetAttribute("isVerticalLeft")
		local flyoutIsHorizontal = parent:GetAttribute("flyoutIsHorizontal")
		local flyoutGoesBelow = parent:GetAttribute("flyoutGoesBelow")
		local myIndex = self:GetAttribute("myTotemIndex") or 0

		-- Count visible siblings with lower totemIndex
		local visibleBefore = 0
		local children = newtable(parent:GetChildren())
		for i = 1, #children do
			local sibling = children[i]
			if sibling:GetAttribute("isFlyoutButton") then
				local sibIndex = sibling:GetAttribute("myTotemIndex") or 0
				if sibIndex < myIndex and not sibling:GetAttribute("isCurrentAssignment") and not sibling:GetAttribute("flyoutHidden") then
					visibleBefore = visibleBefore + 1
				end
			end
		end

		-- Position myself based on how many visible buttons are before me
		self:ClearAllPoints()
		if flyoutIsHorizontal then
			if isVerticalLeft then
				self:SetPoint("RIGHT", parent, "LEFT", -spacing - visibleBefore * (buttonSize + spacing), 0)
			else
				self:SetPoint("LEFT", parent, "RIGHT", spacing + visibleBefore * (buttonSize + spacing), 0)
			end
		else
			if flyoutGoesBelow then
				self:SetPoint("TOP", parent, "BOTTOM", 0, -spacing - visibleBefore * (buttonSize + spacing))
			else
				self:SetPoint("BOTTOM", parent, "TOP", 0, spacing + visibleBefore * (buttonSize + spacing))
			end
		end
	]]

-- SPFU<element>: pressed last by a hover flyout's assign macro, after SPFS/SPFN
-- has written the totem button's spell. It re-sorts the open flyout around the
-- new assignment and closes it, in combat too. (The flyout buttons cannot run a
-- click snippet of their own: their template has no mouse-up handler, so the old
-- _onmouseup snippet on them never ran.) spSecureResort is off where the plain
-- relayout above would misplace the buttons; then the pick only closes the
-- flyout and the list catches up when the fight ends.
function ShamanPower:FlyoutResortHelper(element, parent)
	local name = "SPFU" .. element
	local h = _G[name] or CreateFrame("Button", name, parent, "SecureHandlerClickTemplate")
	h:SetParent(parent)
	h:SetSize(1, 1)
	h:ClearAllPoints()
	h:SetPoint("CENTER", parent, "CENTER")
	h:EnableMouse(false)
	h:RegisterForClicks("AnyUp", "AnyDown")
	h:SetAttribute("_onclick", [[
		local p = self:GetParent()
		if not p then return end
		if p:GetAttribute("spSecureResort") then
			p:ChildUpdate("assignment", p:GetAttribute("spell1"))
			p:ChildUpdate("relayout", true)
		end
		p:ChildUpdate("show", false)
	]])
	return h
end

function ShamanPower:CreateTotemFlyout(element)
	if self.totemFlyouts[element] then return self.totemFlyouts[element] end

	-- Make sure totem buttons exist
	self:CreateTotemButtons()

	-- Use the totem button as parent (parented to UIParent for combat flyout support)
	local parentButton = self.totemButtons[element]
	if not parentButton then return nil end

	-- Get totems for this element
	local totems = self.Totems[element]
	local icons = self.TotemIcons[element]

	-- Flyout is just a table to track buttons (buttons are children of parentButton)
	local flyout = {
		buttons = {},      -- Active/enabled buttons only
		allButtons = {},   -- All known totem buttons (for rebuilding when settings change)
		buttonSize = self:TotemFlyoutButtonSize(),
		padding = 4,
		spacing = 0,  -- No gap between buttons to prevent menu closing when moving mouse
		element = element,
		totemButton = parentButton
	}


	-- Box mode (snippets broken): the buttons hang from a watched box so a click
	-- can open them in combat. Anchors still point at the totem button, and the
	-- box is its child, so position and scale are unchanged.
	local buttonParent = parentButton
	if spFlyoutBoxMode() and not InCombatLockdown() then
		buttonParent = self:EnsureFlyoutBox(element, parentButton, flyout,
			function() ShamanPower:UpdateFlyoutVisibility(element) end) or parentButton
	end

	-- Element names for flyout settings lookup
	local elementKeys = { [1] = "earth", [2] = "fire", [3] = "water", [4] = "air" }
	local elementKey = elementKeys[element]

	for totemIndex, spellID in pairs(totems) do
		-- Ask knowledge by ID; the localized name below is used for casting.
		local spellName = GetSpellInfo(spellID)
		if SPCompat.HasTotemCastAliases(spellID) then spellName = SPCompat.TotemCastName(spellID) end
		local isKnown = PlayerKnowsTotem(spellID)
		-- Talent-gated totems (Totem of Wrath, Mana Tide) always get a button, so
		-- a respec can show/hide them through the normal flyout filter with no
		-- /reload - exactly like the settings toggles do.
		-- spellName must resolve: a talent totem the client has no spell data for
		-- (Totem of Wrath on the Mainline line) would otherwise force a nameless,
		-- iconless, uncastable button into the flyout.
		local isTalentTotem = self.TalentTotems and self.TalentTotems[spellID] ~= nil and spellName ~= nil

		-- Check if totem is enabled in flyout settings (default to true if not set)
		local flyoutKey = elementKey .. "_" .. totemIndex
		local isEnabledInFlyout = self.opt.flyoutTotems == nil or self.opt.flyoutTotems[flyoutKey] ~= false

		if (isKnown and (not SPCompat.FOREVER or spellName)) or isTalentTotem then
			-- Create button as CHILD of totem button using SPFlyoutButtonTemplate
			-- Parent is totemButton (parented to UIParent) for combat flyout support
			-- Parent is the totem button: ChildUpdate needs it on the secure
			-- path, and the buttons inherit its scale, which a separate host
			-- frame does not. An unprotected host was tried and removed - it
			-- cannot be shown in combat anyway, because protection propagates
			-- up from the secure buttons inside it.
			local btn = CreateFrame("Button",
				"ShamanPowerFlyout" .. element .. "Btn" .. totemIndex,
				buttonParent,
				"SPFlyoutButtonTemplate")

			-- IMPORTANT: CreateFrame returns existing frame if name exists, but doesn't re-parent it
			-- Must explicitly set parent when reusing frames after RecreateTotemFlyouts()
			btn:SetParent(buttonParent)
			btn:SetSize(flyout.buttonSize, flyout.buttonSize)
			btn:Hide()  -- Start hidden (template handles this too)
			btn:SetIgnoreParentAlpha(true)  -- Independent opacity from parent button

			-- SECURE HANDLER: Respond to parent's ChildUpdate (WORKS IN COMBAT)
			ShamanPower:SetSnippet(btn, "_childupdate-show", SP_FLYOUT_CHILD_SHOW)

			-- SECURE HANDLER: Respond to assignment changes (WORKS IN COMBAT)
			-- Updates isCurrentAssignment based on whether this button's spell matches the new assignment
			ShamanPower:SetSnippet(btn, "_childupdate-assignment", SP_FLYOUT_CHILD_ASSIGNMENT)

			-- SECURE HANDLER: Relayout this button after assignment change (WORKS IN COMBAT)
			-- Each button counts visible siblings before it and positions itself accordingly
			ShamanPower:SetSnippet(btn, "_childupdate-relayout", SP_FLYOUT_CHILD_RELAYOUT)

			-- SECURE HANDLER: Check parent on leave (WORKS IN COMBAT)
			ShamanPower:SetSnippet(btn, "_onleave", SP_SECURE_ONLEAVE_PARENT)
			btn:SetAttribute("spFlyoutProtocol", true)  -- lets sibling leave snippets tell flyout buttons from decoration

			-- Store spell info as attributes for secure snippets
			btn:SetAttribute("mySpell", spellName)
			btn:SetAttribute("myElement", element)
			btn:SetAttribute("myTotemIndex", totemIndex)
			btn:SetAttribute("isFlyoutButton", true)  -- Mark as flyout button for relayout handler

			-- Check if buttons are swapped
			local swapped = self.opt.swapFlyoutClickButtons

			-- Set up casting (opposite of assignment button)
			-- Clear BOTH sets of attributes first (frame may be reused with old attributes)
			btn:SetAttribute("type1", nil)
			btn:SetAttribute("spell1", nil)
			btn:SetAttribute("type2", nil)
			btn:SetAttribute("spell2", nil)

			if swapped then
				-- Swapped: right-click casts, left-click assigns
				btn:SetAttribute("type2", "spell")
				btn:SetAttribute("spell2", spellName)
				btn:SetAttribute("assignButton", "LeftButton")
			else
				-- Normal: left-click casts, right-click assigns
				btn:SetAttribute("type1", "spell")
				btn:SetAttribute("spell1", spellName)
				btn:SetAttribute("assignButton", "RightButton")
			end

			-- The assign click presses secure helpers from a macro: SPFS writes the
			-- totem button's spell (the "attribute" action), SPFM writes the same
			-- totem into Blizzard's totem bar (the "multispell" action, the only way
			-- to reach that bar mid-fight; Call of the Elements casts what the bar
			-- holds, not what we show). All of it works in combat, and PostClick
			-- below handles the rest.
			-- Box mode: picking a totem casts it AND closes the flyout in the same
			-- click, by pressing the close arrow from a macro; the assign click ends
			-- by closing the flyout and resetting its toggle key.
			-- Hover mode: the assign click ends with SPFU, which re-sorts and closes.
			if spellName then
				local castN, assignN = swapped and "2" or "1", swapped and "1" or "2"
				local tag = element .. "_" .. totemIndex
				local S = self:FlyoutAssignHelper("SPFS" .. tag, parentButton)
				S:SetAttribute("type", "attribute")
				S:SetAttribute("attribute-frame", parentButton)
				S:SetAttribute("attribute-name", "spell1")
				S:SetAttribute("attribute-value", spellName)
				self:FlyoutAssignHelper("SPFM" .. tag, parentButton)   -- filled by RefreshTotemBarHelpers
				local tail
				if flyout.box then
					btn.spPick = { [castN] = "/cast " .. spellName }   -- finished by ApplyFlyoutPickMacros
					tail = "\n/click SPFC" .. element .. "\n/click SPFR" .. element
				else
					self:FlyoutResortHelper(element, parentButton)
					tail = "\n/click SPFU" .. element
				end
				btn:SetAttribute("type" .. assignN, "macro")
				btn:SetAttribute("macrotext" .. assignN, "/click SPFS" .. tag .. "\n/click SPFM" .. tag .. tail)
			end

			-- Set up icon (use template's icon child or create one)
			btn.icon = spOwnIcon(btn)
			-- Always reset icon state (button may be reused after SetParent(nil))
			btn.icon:ClearAllPoints()
			btn.icon:SetAllPoints()
			btn.icon:SetTexture(icons[totemIndex] or "Interface\\Icons\\INV_Misc_QuestionMark")
			btn.icon:Show()

			-- Create cooldown frame for spell cooldown display
			local cdFrame = CreateFrame("Cooldown", btn:GetName() .. "Cooldown", btn, "CooldownFrameTemplate")
			cdFrame:SetAllPoints(btn.icon)
			cdFrame:SetDrawSwipe(true)
			cdFrame:SetDrawEdge(true)
			cdFrame:SetSwipeColor(0, 0, 0, 0.8)
			cdFrame:SetHideCountdownNumbers(true)  -- We'll show our own text
			self:StyleEngineCooldown(cdFrame)       -- ...except where the engine draws the numbers
			btn.cooldown = cdFrame

			-- Create cooldown text overlay (above the cooldown swipe)
			local cdTextFrame = CreateFrame("Frame", nil, btn)
			cdTextFrame:SetAllPoints(btn)
			cdTextFrame:SetFrameLevel(cdFrame:GetFrameLevel() + 1)
			local cdText = cdTextFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
			ShamanPower:AdoptSPFont(cdText, "timers")   -- template font = the design; follows the Fonts settings
			cdText:SetPoint("CENTER", btn, "CENTER", 0, 0)
			local cdColor = self.opt.totemCooldownTextColor
			cdText:SetTextColor(cdColor and cdColor.r or 1, cdColor and cdColor.g or 1, cdColor and cdColor.b or 1)
			cdText:SetShadowOffset(1, -1)
			cdText:Hide()
			btn.cooldownText = cdText

			-- Tooltip (Lua hook, works alongside secure handlers)
			btn:HookScript("OnEnter", function(self)
				if not ShamanPower.opt.ShowTooltips then return end
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:SetSpellByID(SPCompat.HighestKnownRank and SPCompat.HighestKnownRank(spellID) or spellID)
				GameTooltip:AddLine(" ")
				if self.spPullMode and ShamanPower.RowPullTooltipLines then
					ShamanPower:RowPullTooltipLines(self)   -- (in a Totem Row that pulls totems back)
				elseif ShamanPower.opt.swapFlyoutClickButtons then
					GameTooltip:AddLine("|cff00ff00Left-click:|r Set as assigned totem", 1, 1, 1)
					GameTooltip:AddLine("|cffffcc00Right-click:|r Cast totem", 1, 1, 1)
				else
					GameTooltip:AddLine("|cff00ff00Left-click:|r Cast totem", 1, 1, 1)
					GameTooltip:AddLine("|cffffcc00Right-click:|r Set as assigned totem", 1, 1, 1)
				end
				if ShamanPower.opt.enableMiddleClickPopOut ~= false then
					GameTooltip:AddLine("|cff00ccffMiddle-click:|r Pop out element", 1, 1, 1)
				end
				GameTooltip:Show()
			end)
			btn:HookScript("OnLeave", function(self)
				GameTooltip:Hide()
			end)

			-- Handle assignment click (button depends on swap setting)
			-- The secure _onclick handler has already changed the spell in combat
			-- This Lua handler does the non-secure parts (SavedVariables, UI updates)
			btn:SetScript("PostClick", function(self, button)
				-- (the click the button's own layout assigns on, as the secure side did: a profile
				-- switched in a fight changes the option before the layout follows. A row's copy: its source's)
				local assignButton = (self.spSource or self):GetAttribute("assignButton")
					or (ShamanPower.opt.swapFlyoutClickButtons and "LeftButton" or "RightButton")
				if button == assignButton then
					local totemIdx = self.totemIndex
					local elem = element

					if InCombatLockdown() then
						-- In combat: secure handler already changed the spell
						-- Update icon immediately (texture changes are allowed in combat)
						local totemBtn = ShamanPower.totemButtons[elem]
						if totemBtn and totemBtn.icon then
							local icons = ShamanPower.TotemIcons[elem]
							if icons and icons[totemIdx] then
								totemBtn.icon:SetTexture(icons[totemIdx])
								ShamanPower:ShowEmptySlotArt(elem, false)
							end
						end
						-- Queue the Lua-side updates for when combat ends (silently, like TotemTimers)
						if not ShamanPower.pendingAssignments then
							ShamanPower.pendingAssignments = {}
						end
						ShamanPower.pendingAssignments[elem] = totemIdx
						ShamanPower:MarkAssignedInFlyout(elem)
						-- the dropped totem now differs from (or matches) the new one: its icon above, now
						ShamanPower:UpdateActiveTotemOverlays()
					else
						-- Out of combat: do all updates immediately
						if not ShamanPower_Assignments[ShamanPower.player] then
							ShamanPower_Assignments[ShamanPower.player] = {}
						end
						ShamanPower_Assignments[ShamanPower.player][elem] = totemIdx
						ShamanPower:UpdateMiniTotemBar()
						ShamanPower:UpdateDropAllButton()
						ShamanPower:UpdateSPMacros()
						ShamanPower:SendMessage("ASSIGN " .. ShamanPower.player .. " " .. elem .. " " .. totemIdx)
						-- Update flyout visibility to mark the new assignment correctly
						ShamanPower:UpdateFlyoutVisibility(elem)
						-- Hide flyout buttons
						local flyoutData = ShamanPower.totemFlyouts[elem]
						if flyoutData and flyoutData.box then
							ShamanPower:FlyoutFallbackSetShown(flyoutData.totemButton, false)
						elseif flyoutData and flyoutData.buttons and not parentButton.spGridPinned then
							for _, flyoutBtn in ipairs(flyoutData.buttons) do
								flyoutBtn:Hide()
							end
						end
					end
				end
			end)

			-- Middle-click to pop out single totem
			btn:HookScript("OnClick", function(self, button)
				if button == "MiddleButton" then
					if InCombatLockdown() then
						print("|cff0070ddShamanPower:|r Cannot pop out during combat")
						return
					end
					local elem = element
					local totemIdx = self.totemIndex
					local key = "single_" .. elem .. "_" .. totemIdx

					if ShamanPower.opt.poppedOut and ShamanPower.opt.poppedOut[key] then
						ShamanPower:ReturnPopOutToBar(key)
					else
						ShamanPower:PopOutSingleTotem(elem, totemIdx)
					end
				end
			end)

			btn.totemIndex = totemIndex
			btn.spellID = spellID
			btn.talentSpellID = isTalentTotem and spellID or nil

			-- Always add to allButtons (for rebuilding when settings change)
			table.insert(flyout.allButtons, btn)

			-- Only add to active buttons if enabled in flyout settings and, for
			-- talent-gated totems, currently known
			if isEnabledInFlyout and (not isTalentTotem or isKnown) then
				btn.isDisabledInFlyout = false
				btn:SetAttribute("flyoutHidden", false)
				table.insert(flyout.buttons, btn)
			else
				btn.isDisabledInFlyout = true
				btn:Hide()
				btn:SetAttribute("isCurrentAssignment", true)  -- Treat as hidden
				btn:SetAttribute("flyoutHidden", true)         -- unlike isCurrentAssignment, survives assignment broadcasts
			end
		end
	end

	-- "Empty": leave this element unassigned, as on Blizzard's totem bar (there it
	-- is how an element is kept out of a totem set). totemIndex 0 is the
	-- addon's existing "nothing assigned" state, so the rest of the flyout code
	-- treats it like any other button: it sorts first, next to the totem button,
	-- and hides itself while nothing is assigned (box mode keeps it, faded).
	-- Picking it clears the totem button's spell and Blizzard's slot through the
	-- same secure helpers as an assign click, so it works in combat. WoW: Forever
	-- only: it exists for Call of the Elements, and Anniversary has no totem sets.
	if SPCompat.FOREVER and self.opt.flyoutShowEmpty ~= false and #flyout.allButtons > 0 then
		local name = "ShamanPowerFlyout" .. element .. "Btn0"
		local btn = CreateFrame("Button", name, buttonParent, "SPFlyoutButtonTemplate")
		btn:SetParent(buttonParent)
		btn:SetSize(flyout.buttonSize, flyout.buttonSize)
		btn:Hide()
		btn:SetIgnoreParentAlpha(true)
		ShamanPower:SetSnippet(btn, "_childupdate-show", SP_FLYOUT_CHILD_SHOW)   -- box mode: wires the hover-leave fallback
		if not flyout.box then
			ShamanPower:SetSnippet(btn, "_childupdate-assignment", SP_FLYOUT_CHILD_ASSIGNMENT)
			ShamanPower:SetSnippet(btn, "_childupdate-relayout", SP_FLYOUT_CHILD_RELAYOUT)
			ShamanPower:SetSnippet(btn, "_onleave", SP_SECURE_ONLEAVE_PARENT)
		end
		btn:SetAttribute("spFlyoutProtocol", true)
		btn:SetAttribute("mySpell", nil)   -- matches the cleared spell in the "assignment" broadcast
		btn:SetAttribute("myElement", element)
		btn:SetAttribute("myTotemIndex", 0)
		btn:SetAttribute("isFlyoutButton", true)
		btn:SetAttribute("flyoutHidden", false)

		-- SPFN<element>: clears the totem button's spell (works in combat)
		local clear = _G["SPFN" .. element] or CreateFrame("Button", "SPFN" .. element, parentButton, "SecureActionButtonTemplate")
		clear:SetParent(parentButton)
		clear:SetSize(1, 1)
		clear:SetPoint("CENTER", parentButton, "CENTER")
		clear:EnableMouse(false)
		clear:RegisterForClicks("AnyUp", "AnyDown")
		clear:SetAttribute("useOnKeyDown", false)
		clear:SetAttribute("type", "attribute")
		clear:SetAttribute("attribute-frame", parentButton)
		clear:SetAttribute("attribute-name", "spell1")
		clear:SetAttribute("attribute-value", nil)
		-- either mouse button: clear the spell, then close the flyout (box mode:
		-- and reset its toggle key; hover mode: SPFU re-sorts it first)
		self:FlyoutAssignHelper("SPFM" .. element .. "_0", parentButton)   -- empties Blizzard's slot too
		local tail
		if flyout.box then
			tail = "\n/click SPFC" .. element .. "\n/click SPFR" .. element
		else
			self:FlyoutResortHelper(element, parentButton)
			tail = "\n/click SPFU" .. element
		end
		local macro = "/click SPFN" .. element .. "\n/click SPFM" .. element .. "_0" .. tail
		for _, n in ipairs({ "1", "2" }) do
			btn:SetAttribute("type" .. n, "macro")
			btn:SetAttribute("macrotext" .. n, macro)
		end

		btn.icon = spOwnIcon(btn)
		btn.icon:ClearAllPoints()
		btn.icon:SetAllPoints()
		btn.icon:SetTexture(ARROW_TEXTURE)
		local c = SLOT_EMPTY[element] or SLOT_EMPTY[1]
		btn.icon:SetTexCoord(c[1], c[2], c[3], c[4])
		btn.icon:Show()

		btn:HookScript("OnEnter", function(self)
			if not ShamanPower.opt.ShowTooltips then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText("Empty")
			GameTooltip:AddLine("Leave this element with no totem assigned.", 1, 1, 1, true)
			GameTooltip:Show()
		end)
		btn:HookScript("OnLeave", function() GameTooltip:Hide() end)

		btn:SetScript("PostClick", function(self)
			local elem = element
			if InCombatLockdown() then
				-- the secure helper already cleared the spell; show it now, save it after the fight
				ShamanPower:ShowEmptySlotArt(elem, true)
				ShamanPower.pendingAssignments = ShamanPower.pendingAssignments or {}
				ShamanPower.pendingAssignments[elem] = 0
				ShamanPower:MarkAssignedInFlyout(elem)
				ShamanPower:UpdateActiveTotemOverlays()   -- a totem still down is no longer the assigned one
			else
				ShamanPower_Assignments[ShamanPower.player] = ShamanPower_Assignments[ShamanPower.player] or {}
				ShamanPower_Assignments[ShamanPower.player][elem] = 0
				ShamanPower:UpdateMiniTotemBar()
				ShamanPower:UpdateDropAllButton()
				ShamanPower:UpdateSPMacros()
				ShamanPower:SendMessage("ASSIGN " .. ShamanPower.player .. " " .. elem .. " 0")
				ShamanPower:UpdateFlyoutVisibility(elem)
				local flyoutData = ShamanPower.totemFlyouts[elem]
				if flyoutData and flyoutData.box then
					ShamanPower:FlyoutFallbackSetShown(flyoutData.totemButton, false)
				elseif flyoutData and flyoutData.buttons and not parentButton.spGridPinned then
					for _, flyoutBtn in ipairs(flyoutData.buttons) do flyoutBtn:Hide() end
				end
			end
		end)

		btn.totemIndex = 0
		btn.isDisabledInFlyout = false
		table.insert(flyout.allButtons, btn)
		table.insert(flyout.buttons, btn)
	end

	-- Sort buttons by totemIndex for consistent ordering
	table.sort(flyout.allButtons, function(a, b) return a.totemIndex < b.totemIndex end)
	table.sort(flyout.buttons, function(a, b) return a.totemIndex < b.totemIndex end)
	self:RefreshTotemBarHelpers()

	-- Initial layout
	self:LayoutFlyoutButtons(flyout)

	self.totemFlyouts[element] = flyout
	if flyout.box then
		self:ApplyFlyoutPickMacros()
		self:UpdateFlyoutVisibility(element)   -- decides which buttons belong, then syncs
	end

	return flyout
end

-- Layout flyout buttons based on current bar orientation
-- For horizontal bar: flyout is VERTICAL (buttons stacked)
-- For vertical bar: flyout is HORIZONTAL (buttons in a row)
function ShamanPower:LayoutFlyoutButtons(flyout, flyoutIsHorizontal)
	if not flyout or not flyout.buttons then return end
	if flyout.totemButton and flyout.totemButton.spGridPinned and InCombatLockdown() then return end
	-- Creation lays out its local table before publishing it. Refreshing Grid
	-- there would ask SetupTotemFlyouts to build that same missing element again.
	if flyout.element and self.totemFlyouts[flyout.element] == flyout
		and self.GridLayoutElement and self:GridLayoutElement(flyout.element) then return end
	self:PlaceFlyoutArrows(flyout)

	local totemButton = flyout.totemButton
	if not totemButton then return end

	local buttons = flyout.buttons
	local numButtons = #buttons
	local buttonSize = flyout.buttonSize or 28
	local spacing = flyout.spacing or 0
	local lead = spacing + (flyout.leadGap or 0)   -- box mode leaves room for the arrow strip

	-- Check if this element is popped out and has a custom flyout direction
	local element = flyout.element or (totemButton and totemButton.element)
	local poppedOutDirection = nil
	if element then
		local elementName = self.Elements[element]:lower()
		local key = "totem_" .. elementName
		if self:IsElementPoppedOut(element) then
			local settings = self.opt.poppedOutSettings and self.opt.poppedOutSettings[key]
			if settings and settings.flyoutDirection then
				poppedOutDirection = settings.flyoutDirection
			end
		end
	end

	-- If popped out with custom direction, use that instead of bar-based logic
	if poppedOutDirection then
		flyout.isHorizontal = (poppedOutDirection == "left" or poppedOutDirection == "right")

		if numButtons == 0 then return end

		-- Position based on custom direction
		if poppedOutDirection == "top" then
			for i, btn in ipairs(buttons) do
				btn:ClearAllPoints()
				btn:SetPoint("BOTTOM", totemButton, "TOP", 0, lead + (i - 1) * (buttonSize + spacing))
			end
		elseif poppedOutDirection == "bottom" then
			for i, btn in ipairs(buttons) do
				btn:ClearAllPoints()
				btn:SetPoint("TOP", totemButton, "BOTTOM", 0, -lead - (i - 1) * (buttonSize + spacing))
			end
		elseif poppedOutDirection == "left" then
			for i, btn in ipairs(buttons) do
				btn:ClearAllPoints()
				btn:SetPoint("RIGHT", totemButton, "LEFT", -lead - (i - 1) * (buttonSize + spacing), 0)
			end
		elseif poppedOutDirection == "right" then
			for i, btn in ipairs(buttons) do
				btn:ClearAllPoints()
				btn:SetPoint("LEFT", totemButton, "RIGHT", lead + (i - 1) * (buttonSize + spacing), 0)
			end
		end
		return
	end

	-- Default: if bar is horizontal, flyout is vertical (and vice versa)
	if flyoutIsHorizontal == nil then
		local isHorizontalBar = self:IsTotemBarHorizontal()
		-- Both "Vertical" and "VerticalLeft" result in horizontal flyouts
		flyoutIsHorizontal = not isHorizontalBar
	end

	local isVerticalLeft = (self.opt.layout == "VerticalLeft") and not self:CompactActive()

	-- Determine flyout direction for vertical flyouts (when horizontal bar)
	local flyoutDir = self.opt.totemFlyoutDirection or "auto"
	local flyoutGoesBelow = self:FlyoutGoesBelow(totemButton)

	flyout.isHorizontal = flyoutIsHorizontal

	-- Store layout info on parent button for secure relayout handler
	totemButton:SetAttribute("isVerticalLeft", isVerticalLeft)
	totemButton:SetAttribute("flyoutIsHorizontal", flyoutIsHorizontal)
	totemButton:SetAttribute("flyoutGoesBelow", flyoutGoesBelow)

	if numButtons == 0 then return end

	-- Position buttons relative to the totem button (parent)
	-- Buttons are children of totemButton, so we anchor to the parent
	if flyoutIsHorizontal then
		if isVerticalLeft then
			-- VerticalLeft: horizontal flyout extends to the LEFT
			for i, btn in ipairs(buttons) do
				btn:ClearAllPoints()
				btn:SetPoint("RIGHT", totemButton, "LEFT", -lead - (i - 1) * (buttonSize + spacing), 0)
			end
		else
			-- Vertical (Right): horizontal flyout extends to the RIGHT
			for i, btn in ipairs(buttons) do
				btn:ClearAllPoints()
				btn:SetPoint("LEFT", totemButton, "RIGHT", lead + (i - 1) * (buttonSize + spacing), 0)
			end
		end
	else
		-- Vertical flyout: buttons extend upward or downward based on option
		if flyoutGoesBelow then
			-- Extend downward
			for i, btn in ipairs(buttons) do
				btn:ClearAllPoints()
				btn:SetPoint("TOP", totemButton, "BOTTOM", 0, -lead - (i - 1) * (buttonSize + spacing))
			end
		else
			-- Extend upward (default/auto)
			for i, btn in ipairs(buttons) do
				btn:ClearAllPoints()
				btn:SetPoint("BOTTOM", totemButton, "TOP", 0, lead + (i - 1) * (buttonSize + spacing))
			end
		end
	end
end

-- Position flyout relative to totem button, reversing direction if needed
-- For horizontal bar layout: flyout extends vertically (above/below)
-- For vertical bar layout: flyout extends horizontally (left/right)
-- "Vertical" (Right) prefers flyouts to the right, "VerticalLeft" prefers flyouts to the left
function ShamanPower:PositionFlyout(flyout, totemButton)
	if not flyout or not totemButton then return end

	local isHorizontalBar = self:IsTotemBarHorizontal()
	local isVerticalLeft = (self.opt.layout == "VerticalLeft") and not self:CompactActive()

	-- Match the scale of the parent button's frame
	local parentScale = totemButton:GetEffectiveScale() / UIParent:GetEffectiveScale()
	flyout:SetScale(parentScale)

	-- Get screen dimensions
	local screenWidth = GetScreenWidth()
	local screenHeight = GetScreenHeight()

	-- Get totem button position
	local buttonLeft = totemButton:GetLeft() or 0
	local buttonRight = totemButton:GetRight() or 0
	local buttonTop = totemButton:GetTop() or 0
	local buttonBottom = totemButton:GetBottom() or 0

	-- Get flyout dimensions (adjusted for scale)
	local flyoutWidth = flyout:GetWidth() * parentScale
	local flyoutHeight = flyout:GetHeight() * parentScale

	flyout:ClearAllPoints()

	if isHorizontalBar then
		-- Horizontal bar: flyout is VERTICAL and goes above or below
		local flyoutDir = self.opt.totemFlyoutDirection or "auto"
		local spaceAbove = screenHeight - buttonTop
		local spaceBelow = buttonBottom

		if flyoutDir == "above" then
			flyout:SetPoint("BOTTOM", totemButton, "TOP", 0, 2)
		elseif flyoutDir == "below" then
			flyout:SetPoint("TOP", totemButton, "BOTTOM", 0, -2)
		elseif spaceAbove >= flyoutHeight + 2 then
			flyout:SetPoint("BOTTOM", totemButton, "TOP", 0, 2)
		elseif spaceBelow >= flyoutHeight + 2 then
			flyout:SetPoint("TOP", totemButton, "BOTTOM", 0, -2)
		elseif spaceAbove >= spaceBelow then
			flyout:SetPoint("BOTTOM", totemButton, "TOP", 0, 2)
		else
			flyout:SetPoint("TOP", totemButton, "BOTTOM", 0, -2)
		end
	else
		-- Vertical bar: flyout is HORIZONTAL and goes left or right
		-- "VerticalLeft" prefers left, "Vertical" (Right) prefers right
		local spaceRight = screenWidth - buttonRight
		local spaceLeft = buttonLeft

		if isVerticalLeft then
			-- Prefer left side
			if spaceLeft >= flyoutWidth + 2 then
				flyout:SetPoint("RIGHT", totemButton, "LEFT", -2, 0)
			elseif spaceRight >= flyoutWidth + 2 then
				flyout:SetPoint("LEFT", totemButton, "RIGHT", 2, 0)
			elseif spaceLeft >= spaceRight then
				flyout:SetPoint("RIGHT", totemButton, "LEFT", -2, 0)
			else
				flyout:SetPoint("LEFT", totemButton, "RIGHT", 2, 0)
			end
		else
			-- Prefer right side (default "Vertical")
			if spaceRight >= flyoutWidth + 2 then
				flyout:SetPoint("LEFT", totemButton, "RIGHT", 2, 0)
			elseif spaceLeft >= flyoutWidth + 2 then
				flyout:SetPoint("RIGHT", totemButton, "LEFT", -2, 0)
			elseif spaceRight >= spaceLeft then
				flyout:SetPoint("LEFT", totemButton, "RIGHT", 2, 0)
			else
				flyout:SetPoint("RIGHT", totemButton, "LEFT", -2, 0)
			end
		end
	end
end

-- Update flyout to hide currently assigned totem and reposition
-- For horizontal bar: flyout is VERTICAL (buttons stacked top to bottom)
-- For vertical bar: flyout is HORIZONTAL (buttons in a row left to right)
-- The flyout list in the options can hide every totem an element has. With an
-- Empty choice on the bar that would strand the element: once it is emptied
-- (possibly mid-fight, when nothing can be shown any more) there would be no
-- way to pick a totem again. So a list that leaves an element with nothing is
-- ignored for that element, and applies again once it lists something known.
-- Box mode only: the Classic line has no Empty choice and keeps its behaviour.
function ShamanPower:RescueFilteredFlyout(flyout)
	if not flyout.box then return end
	local listed = 0
	for _, btn in ipairs(flyout.allButtons or {}) do
		if btn.totemIndex > 0 and not btn.isDisabledInFlyout and not btn.spRescued then listed = listed + 1 end
	end
	local want = listed == 0
	local changed = false
	for _, btn in ipairs(flyout.allButtons or {}) do
		if btn.totemIndex > 0 then
			if want and btn.isDisabledInFlyout and (not btn.talentSpellID or PlayerKnowsTotem(btn.talentSpellID)) then
				btn.spRescued, btn.isDisabledInFlyout = true, false
				btn:SetAttribute("flyoutHidden", false)
				changed = true
			elseif not want and btn.spRescued then
				btn.spRescued, btn.isDisabledInFlyout = nil, true
				btn:Hide()
				btn:SetAttribute("isCurrentAssignment", true)
				btn:SetAttribute("flyoutHidden", true)
				changed = true
			end
		end
	end
	if changed then
		flyout.buttons = {}
		for _, btn in ipairs(flyout.allButtons) do
			if not btn.isDisabledInFlyout then table.insert(flyout.buttons, btn) end
		end
		table.sort(flyout.buttons, function(a, b) return a.totemIndex < b.totemIndex end)
	end
end

-- Box-mode flyouts keep the assigned totem in the list (see
-- UpdateFlyoutVisibility). It cannot be hidden mid-fight, but its icon is only a
-- texture, so the choice that is on the totem button right now is drawn faded
-- and follows every swap, in a fight or out of one.
function ShamanPower:MarkAssignedInFlyout(element)
	if self.GridActive and self:GridActive() then self:UpdateGridTotems(); return end
	-- Totem Rows: the row edges its assigned totem itself (ShamanPowerRows.lua)
	if self.RowsOwnFlyouts and self:RowsOwnFlyouts(element) then self:UpdateTotemRows(); return end
	local flyout = self.totemFlyouts and self.totemFlyouts[element]
	if not (flyout and flyout.box) then return end
	-- the choice a click on the button casts is the one drawn faded, in every style
	-- (TotemTimers Style / Single Totem SHOW the totem that is down, but still cast
	-- the assigned one: as UpdateFlyoutVisibility's hideIndex)
	local cur = self:AssignedIndex(element)
	for _, btn in ipairs(flyout.allButtons or {}) do
		if btn.icon then
			local on = btn.totemIndex == cur
			btn.icon:SetAlpha(on and 0.3 or 1)
			btn.icon:SetDesaturated(on and true or false)
		end
	end
end

function ShamanPower:UpdateFlyoutVisibility(element)
	local flyout = self.totemFlyouts[element]
	if not flyout or not flyout.buttons then return end

	-- Don't modify secure buttons during combat
	if InCombatLockdown() then
		return
	end
	if self.GridLayoutElement and self:GridLayoutElement(element) then return end

	local totemButton = flyout.totemButton
	if not totemButton then return end

	-- Get current assignment
	local assignments = ShamanPower_Assignments[self.player]
	local currentTotemIndex = assignments and assignments[element] or 0

	self:RescueFilteredFlyout(flyout)
	if flyout.box then flyout.leadGap = self:FlyoutLeadGap(flyout) end   -- Compact's icon square may have moved or resized

	-- Box mode: nothing in the flyout can be shown or hidden during a fight, while
	-- the assignment can change (another totem, or Empty). So the flyout holds
	-- every choice, the assigned totem and Empty included, as Blizzard's own
	-- flyout does - and it holds them out of combat too, so the flyout is the
	-- same list in the same order whenever it is opened. The choice that is on
	-- the button is drawn faded (MarkAssignedInFlyout).
	local keepAll = flyout.box and true or false

	-- The flyout leaves out the totem a click on the button casts: the assigned one,
	-- in every style. TotemTimers Style / Single Totem SHOW the totem that is down on
	-- the button but still cast the assigned one; leaving the one that is down out
	-- meant a dropped totem other than the assigned one could not be cast or assigned
	-- again until it was gone (reported 2026-10-04). It stays in the flyout now.
	local hideIndex = currentTotemIndex

	-- For horizontal bar, flyout is vertical. For vertical bar (both "Vertical" and "VerticalLeft"), flyout is horizontal.
	local isHorizontalBar = self:IsTotemBarHorizontal()
	local isVerticalLeft = (self.opt.layout == "VerticalLeft") and not self:CompactActive()
	local flyoutIsHorizontal = not isHorizontalBar

	-- Determine flyout direction for vertical flyouts (when horizontal bar)
	local flyoutDir = self.opt.totemFlyoutDirection or "auto"
	local flyoutGoesBelow = self:FlyoutGoesBelow(totemButton)

	-- Store layout info on parent button for secure relayout handler
	totemButton:SetAttribute("isVerticalLeft", isVerticalLeft)
	totemButton:SetAttribute("flyoutIsHorizontal", flyoutIsHorizontal)
	totemButton:SetAttribute("flyoutGoesBelow", flyoutGoesBelow)
	-- The in-combat re-sort after a pick (SPFU) redoes only the plain layouts
	-- below: not a popped-out element's own direction. (Every style leaves out the
	-- assigned totem now, TotemTimers Style and Single Totem too.)
	local ownDirection = self:IsElementPoppedOut(element) and self.opt.poppedOutSettings
		and self.opt.poppedOutSettings["totem_" .. self.Elements[element]:lower()]
	ownDirection = ownDirection and ownDirection.flyoutDirection
	totemButton:SetAttribute("spSecureResort", (not flyout.box and not ownDirection) or nil)

	local buttonSize = flyout.buttonSize or 28
	local spacing = flyout.spacing or 0
	local lead = spacing + (flyout.leadGap or 0)   -- box mode leaves room for the arrow strip
	local visibleIndex = 0
	local visibleButtons = {}

	-- First pass: determine which buttons should be visible (hide totem shown on main button and popped-out totems)
	for _, btn in ipairs(flyout.buttons) do
		local totemIdx = btn.totemIndex
		local isPoppedOut = self:IsSingleTotemPoppedOut(element, totemIdx)
		btn:SetAttribute("spPoppedOut", isPoppedOut or nil)   -- the "assignment" broadcast keeps it out

		if (totemIdx == hideIndex and not keepAll) or isPoppedOut then
			-- Mark this button to be hidden (via attribute so secure handler knows)
			btn:SetAttribute("isCurrentAssignment", true)
			if isPoppedOut then
				btn:Hide()  -- Explicitly hide popped-out totems
			end
		else
			btn:SetAttribute("isCurrentAssignment", false)
			visibleIndex = visibleIndex + 1
			table.insert(visibleButtons, btn)
		end
	end

	self:MarkAssignedInFlyout(element)

	-- No visible buttons, nothing to layout
	if visibleIndex == 0 then
		self:SyncCombatFlyoutButtons(element)
		return
	end

	-- Check if this element is popped out and has a custom flyout direction
	local poppedOutDirection = nil
	local elementName = self.Elements[element]:lower()
	local key = "totem_" .. elementName
	if self:IsElementPoppedOut(element) then
		local settings = self.opt.poppedOutSettings and self.opt.poppedOutSettings[key]
		if settings and settings.flyoutDirection then
			poppedOutDirection = settings.flyoutDirection
		end
	end

	-- Layout visible buttons relative to the totem button (parent)
	if poppedOutDirection then
		-- Use custom direction for popped-out element
		if poppedOutDirection == "top" then
			for i, btn in ipairs(visibleButtons) do
				btn:ClearAllPoints()
				btn:SetPoint("BOTTOM", totemButton, "TOP", 0, lead + (i - 1) * (buttonSize + spacing))
			end
		elseif poppedOutDirection == "bottom" then
			for i, btn in ipairs(visibleButtons) do
				btn:ClearAllPoints()
				btn:SetPoint("TOP", totemButton, "BOTTOM", 0, -lead - (i - 1) * (buttonSize + spacing))
			end
		elseif poppedOutDirection == "left" then
			for i, btn in ipairs(visibleButtons) do
				btn:ClearAllPoints()
				btn:SetPoint("RIGHT", totemButton, "LEFT", -lead - (i - 1) * (buttonSize + spacing), 0)
			end
		elseif poppedOutDirection == "right" then
			for i, btn in ipairs(visibleButtons) do
				btn:ClearAllPoints()
				btn:SetPoint("LEFT", totemButton, "RIGHT", lead + (i - 1) * (buttonSize + spacing), 0)
			end
		end
	elseif flyoutIsHorizontal then
		if isVerticalLeft then
			-- VerticalLeft: horizontal flyout extends to the LEFT
			for i, btn in ipairs(visibleButtons) do
				btn:ClearAllPoints()
				btn:SetPoint("RIGHT", totemButton, "LEFT", -lead - (i - 1) * (buttonSize + spacing), 0)
			end
		else
			-- Vertical (Right): horizontal flyout extends to the RIGHT
			for i, btn in ipairs(visibleButtons) do
				btn:ClearAllPoints()
				btn:SetPoint("LEFT", totemButton, "RIGHT", lead + (i - 1) * (buttonSize + spacing), 0)
			end
		end
	else
		-- Vertical flyout: buttons extend upward or downward based on option
		if flyoutGoesBelow then
			-- Extend downward
			for i, btn in ipairs(visibleButtons) do
				btn:ClearAllPoints()
				btn:SetPoint("TOP", totemButton, "BOTTOM", 0, -lead - (i - 1) * (buttonSize + spacing))
			end
		else
			-- Extend upward (default/auto)
			for i, btn in ipairs(visibleButtons) do
				btn:ClearAllPoints()
				btn:SetPoint("BOTTOM", totemButton, "TOP", 0, lead + (i - 1) * (buttonSize + spacing))
			end
		end
	end

	-- Apply flyout opacity
	local opacity = self.opt.totemFlyoutOpacity or 1.0
	for _, btn in ipairs(flyout.buttons) do
		btn:SetAlpha(opacity)
	end

	self:SyncCombatFlyoutButtons(element)
end

-- Setup all flyout menus
function ShamanPower:SetupTotemFlyouts()
	-- (Grid and Totem Rows show the flyouts' buttons as their rows: built either way)
	if not self.opt.showTotemFlyouts and not self.opt.gridStyle and not self.opt.totemRows then return end

	-- Ensure totem buttons exist and are positioned
	self:CreateTotemButtons()
	self:PositionTotemButtons()

	for element = 1, 4 do
		local totemButton = self.totemButtons[element]

		if totemButton then
			-- Create the flyout (will parent to totemButton)
			local flyout = self:CreateTotemFlyout(element)
			if not flyout then return end

			-- Only install Lua hooks once per totem button
			-- (Secure handlers are set up in CreateTotemButtons)
			if not self.flyoutHooksInstalled[element] then
				self.flyoutHooksInstalled[element] = true

				-- Lua hook for positioning updates (out of combat only)
				totemButton:HookScript("OnEnter", function(btn)
					if ShamanPower.opt.showTotemFlyouts and not InCombatLockdown() then
						ShamanPower:UpdateFlyoutVisibility(element)
					end
				end)
			end
		end
	end
end

-- Refresh flyout buttons (call when spells change or out of combat)
function ShamanPower:RefreshTotemFlyouts()
	if InCombatLockdown() then return end

	for element = 1, 4 do
		local flyout = self.totemFlyouts[element]
		if flyout then
			-- Update spell bindings for any new spells learned
			local totems = self.Totems[element]
			for _, btn in ipairs(flyout.buttons) do
				local spellName = GetSpellInfo(btn.spellID)
				if SPCompat.HasTotemCastAliases(btn.spellID) then spellName = SPCompat.TotemCastName(btn.spellID) end
				if spellName then
					btn:SetAttribute("spell", spellName)
				end
			end
		end
	end
end

-- Update click behavior on existing flyout buttons (no recreation needed)
-- Keybind Mode's keys on flyout totems are CLICK bindings on the button's cast click: when the clicks are
-- swapped, each moves to the new cast click so it keeps casting (as the swap's description promises). Read
-- from each button's own layout before it is rewritten. Out of combat; saved like Keybind Mode saves.
function ShamanPower:MoveFlyoutCastBindings(newCast)
	if InCombatLockdown() or not self.totemFlyouts then return end
	local moved = false
	for element = 1, 4 do
		local flyout = self.totemFlyouts[element]
		for _, btn in ipairs(flyout and flyout.allButtons or {}) do
			local name = btn:GetName()
			local oldCast = (btn:GetAttribute("assignButton") == "LeftButton") and "RightButton" or "LeftButton"
			if name and btn.totemIndex and btn.totemIndex > 0 and oldCast ~= newCast then
				for _, key in ipairs({ GetBindingKey("CLICK " .. name .. ":" .. oldCast) }) do
					if SetBindingClick(key, name, newCast) then moved = true end
				end
			end
		end
	end
	if moved then SaveBindings(GetCurrentBindingSet()) end
end

-- Swap Left and Right Click is a profile setting, but the flyouts keep the clicks they were built with: a
-- profile with the other setting lays them out again (Keybind Mode's keys moving with them) before anything
-- reads the clicks, or an action bar key sent to the cast click lands on the assign click. Out of combat
-- (a fight leaves it for after). The keys are sent again here: the layout only sends them while the bar is
-- in use.
function ShamanPower:SyncFlyoutClicks()
	local want = self.opt.swapFlyoutClickButtons and "LeftButton" or "RightButton"
	for element = 1, 4 do
		local flyout = self.totemFlyouts and self.totemFlyouts[element]
		for _, btn in ipairs(flyout and flyout.allButtons or {}) do
			local have = btn.totemIndex and btn.totemIndex > 0 and btn:GetAttribute("assignButton")
			if have and have ~= want then
				if InCombatLockdown() then self.flyoutClickSyncPending = true return end
				self.flyoutClickSyncPending = nil
				self:UpdateFlyoutClickBehavior()
				self:SetupKeybindings()
				return
			end
		end
	end
	self.flyoutClickSyncPending = nil
end

function ShamanPower:UpdateFlyoutClickBehavior()
	if InCombatLockdown() then
		print("|cff0070ddShamanPower:|r Cannot change flyout settings in combat")
		return
	end

	local swapped = self.opt.swapFlyoutClickButtons
	self:MoveFlyoutCastBindings(swapped and "RightButton" or "LeftButton")

	for element = 1, 4 do
		local flyout = self.totemFlyouts[element]
		if flyout and flyout.box then
			-- Box mode buttons cast and assign through macros, not plain spell
			-- attributes; rewriting those here left them half configured (cast
			-- worked, assign only out of combat) until a reload. Rebuild instead.
			self:RebuildTotemFlyout(element)
		elseif flyout and flyout.buttons then
			-- (every totem's button, shown or not: one turned on later keeps this layout. Never the empty
			-- button, which clears on either click)
			local castN, assignN = swapped and "2" or "1", swapped and "1" or "2"
			for _, btn in ipairs(flyout.allButtons or flyout.buttons) do
				if btn.totemIndex and btn.totemIndex > 0 then
					local spellName = btn:GetAttribute("mySpell")
					-- the assign click's macro (CreateTotemFlyout) moves to the new assign click: without it
					-- that click only changed the icon in a fight, and the totem button kept the old totem
					local assignMacro = btn:GetAttribute("macrotext1") or btn:GetAttribute("macrotext2")

					-- Clear old attributes
					for _, n in ipairs({ "1", "2" }) do
						btn:SetAttribute("type" .. n, nil)
						btn:SetAttribute("spell" .. n, nil)
						btn:SetAttribute("macrotext" .. n, nil)
					end

					-- Set new attributes based on swap setting
					btn:SetAttribute("type" .. castN, "spell")
					btn:SetAttribute("spell" .. castN, spellName)
					btn:SetAttribute("assignButton", swapped and "LeftButton" or "RightButton")
					if assignMacro then
						btn:SetAttribute("type" .. assignN, "macro")
						btn:SetAttribute("macrotext" .. assignN, assignMacro)
					end
				end
			end
		end
	end

	-- Also update Earth Shield flyout
	self:UpdateESFlyoutClickBehavior()
end

-- Toggle totem flyouts on/off based on showTotemFlyouts option
-- Right-click pulls back that one totem: the secure "destroytotem" action with
-- a "totem-slot" attribute.
-- Fixed-slot clients get a constant slot per element, so nothing has to change
-- in combat; on cast-order clients the resolver's current slot is used and
-- refreshed on PLAYER_TOTEM_UPDATE out of combat.
-- Mainline family only: Classic clients block DestroyTotem for addons even
-- though the secure action is declared there, so the project id is the only
-- usable discriminator.
-- Do NOT test SECURE_ACTIONS here: it is a file-local table inside Blizzard's
-- secure templates, never published as a global, so any check against it is
-- always false and silently disables the whole feature.
function ShamanPower:TotemDestroySupported()
	return SPCompat.FOREVER and type(DestroyTotem) == "function"
end

function ShamanPower:RightClickDestroysTotems()
	return self.opt.rightClickDestroysTotem == true and self:TotemDestroySupported()
end

function ShamanPower:TotemDestroySlot(element)
	local slot = self.ElementToSlot[element]
	if self.dynamicTotemSlots then
		local haveTotem, _, _, _, _, resolved = self:GetElementTotemInfo(element)
		if haveTotem and type(resolved) == "number" then slot = resolved end
	end
	return slot
end

function ShamanPower:ApplyTotemDestroyAttributes(btn, element)
	btn:SetAttribute("type2", "destroytotem")
	btn:SetAttribute("spell2", nil)
	btn:SetAttribute("totem-slot2", self:TotemDestroySlot(element))
	-- Shift+right-click keeps Totemic Call / Totemic Recall
	btn:SetAttribute("shift-type2", "spell")
	btn:SetAttribute("shift-spell2", GetSpellInfo(36936))
end

-- Shift+Right-Click Pulls That Totem Back (Totem Bar > Clicks, shown while Flyout
-- Requires Right-Click is on; WoW: Forever): right-click opens the flyout and the
-- shifted right-click pulls just that totem back. The flyout's snippet skips a
-- shifted click while "shiftpullback" is set (snippets cannot read "_" names).
function ShamanPower:ShiftRightClickPullsTotem()
	return self.opt.shiftRightClickPullsTotem == true and self:TotemDestroySupported()
end

function ShamanPower:ApplyShiftPullBack(btn, element)
	if self:ShiftRightClickPullsTotem() then
		btn:SetAttribute("shift-type2", "destroytotem")
		btn:SetAttribute("shift-spell2", nil)
		btn:SetAttribute("shift-totem-slot2", self:TotemDestroySlot(element))
		btn:SetAttribute("shiftpullback", true)
	else
		btn:SetAttribute("shift-type2", nil)
		btn:SetAttribute("shift-spell2", nil)
		btn:SetAttribute("shift-totem-slot2", nil)
		btn:SetAttribute("shiftpullback", nil)
	end
end

-- Cast-order clients only: keep the slot attribute current between fights.
function ShamanPower:RefreshTotemDestroySlots()
	if not (self.dynamicTotemSlots and (self:RightClickDestroysTotems() or self:ShiftRightClickPullsTotem())) then return end
	if InCombatLockdown() or not self.totemButtons then return end
	for element = 1, 4 do
		local btn = self.totemButtons[element]
		if btn and btn:GetAttribute("type2") == "destroytotem" then
			btn:SetAttribute("totem-slot2", self:TotemDestroySlot(element))
		end
		if btn and btn:GetAttribute("shift-type2") == "destroytotem" then
			btn:SetAttribute("shift-totem-slot2", self:TotemDestroySlot(element))
		end
	end
end

function ShamanPower:UpdateTotemFlyoutEnabled()
	if InCombatLockdown() then
		print("|cff0070ddShamanPower:|r Cannot change flyout settings in combat")
		return
	end
	if self.GridActive and self:GridActive() then
		for element = 1, 4 do self:GridLayoutElement(element) end
		self:UpdateCooldownBarFlyoutEnabled()
		self:ApplyClickSwap()
		return
	end
	for element = 1, 4 do
		local flyout = self.totemFlyouts[element]
		if flyout and flyout.box then self:PlaceFlyoutArrows(flyout) end
	end

	local enabled = self.opt.showTotemFlyouts
		and not (self.UsingBlizzardTotemBar and self:UsingBlizzardTotemBar())
	local requiresClick = self:FlyoutOpensOnRightClick()
	local hoverMode = self:FlyoutArrowOnly() and "arrow" or "mouseover"   -- "arrow": nothing opens it but its arrow or key
	local totemicCallName = GetSpellInfo(36936)  -- Totemic Call
	local useRightClickAssigned = self.opt.activeTotemAsMain and self.opt.rightClickCastsAssigned
	local playerName = self.player
	local assignments = ShamanPower_Assignments[playerName] or {}

	for element = 1, 4 do
		local btn = self.totemButtons[element]
		-- Totem Rows: this element's choices are a row of their own, so its button opens
		-- no flyout and its right-click does what it does with flyouts off
		local rowHeld = self.RowsOwnFlyouts and self:RowsOwnFlyouts(element)
		if btn then
			if not enabled or rowHeld then
				-- Flyouts disabled
				btn:SetAttribute("OpenMenu", nil)
				-- Check if right-click should cast assigned totem
				btn:SetAttribute("shift-type2", nil)
				btn:SetAttribute("shift-spell2", nil)
				if self:RightClickDestroysTotems() then
					self:ApplyTotemDestroyAttributes(btn, element)
				elseif useRightClickAssigned then
					local assignedIndex = assignments[element] or 0
					local assignedSpellID = assignedIndex > 0 and self:GetTotemSpell(element, assignedIndex)
					local assignedSpellName = assignedSpellID and GetSpellInfo(assignedSpellID)
					if SPCompat.HasTotemCastAliases(assignedSpellID) then
						assignedSpellName = SPCompat.TotemCastName(assignedSpellID)
					end
					if assignedSpellName then
						btn:SetAttribute("type2", "spell")
						btn:SetAttribute("spell2", assignedSpellName)
					else
						btn:SetAttribute("type2", "spell")
						btn:SetAttribute("spell2", totemicCallName)
					end
				else
					btn:SetAttribute("type2", "spell")
					btn:SetAttribute("spell2", totemicCallName)
				end
				-- Hide any visible flyout buttons directly (not a Totem Rows row: those stay out)
				local flyout = self.totemFlyouts[element]
				if rowHeld then
					-- (the row owns them)
				elseif flyout and flyout.box then
					self:FlyoutFallbackSetShown(btn, false)
				elseif flyout and flyout.buttons then
					for _, flyoutBtn in ipairs(flyout.buttons) do
						flyoutBtn:Hide()
					end
				end
			elseif requiresClick then
				-- Flyouts enabled, right-click to show
				btn:SetAttribute("OpenMenu", "click")
				btn:SetAttribute("type2", nil)  -- Disable Totemic Call on right-click
				btn:SetAttribute("spell2", nil)
				self:ApplyShiftPullBack(btn, element)
			else
				-- Flyouts enabled, mouseover to show (default)
				btn:SetAttribute("OpenMenu", hoverMode)
				-- Check if right-click should cast assigned totem
				btn:SetAttribute("shift-type2", nil)
				btn:SetAttribute("shift-spell2", nil)
				if self:RightClickDestroysTotems() then
					self:ApplyTotemDestroyAttributes(btn, element)
				elseif useRightClickAssigned then
					local assignedIndex = assignments[element] or 0
					local assignedSpellID = assignedIndex > 0 and self:GetTotemSpell(element, assignedIndex)
					local assignedSpellName = assignedSpellID and GetSpellInfo(assignedSpellID)
					if assignedSpellName then
						btn:SetAttribute("type2", "spell")
						if SPCompat.HasTotemCastAliases(assignedSpellID) then
							assignedSpellName = SPCompat.TotemCastName(assignedSpellID)
						end
						btn:SetAttribute("spell2", assignedSpellName)
					else
						btn:SetAttribute("type2", "spell")
						btn:SetAttribute("spell2", totemicCallName)
					end
				else
					btn:SetAttribute("type2", "spell")
					btn:SetAttribute("spell2", totemicCallName)
				end
			end
		end
	end

	-- Also update cooldown bar flyouts (shield and weapon imbue buttons)
	self:UpdateCooldownBarFlyoutEnabled()
	self:ApplyClickSwap()
end

-- Toggle cooldown bar flyouts (shield/imbue) based on flyoutRequiresClick option
function ShamanPower:UpdateCooldownBarFlyoutEnabled()
	if InCombatLockdown() then return end

	local requiresClick = self:FlyoutOpensOnRightClick()
	local hoverMode = self:FlyoutArrowOnly() and "arrow" or "mouseover"   -- "arrow": nothing opens it but its arrow or key

	-- Shield button
	if self.shieldButton then
		if requiresClick then
			self.shieldButton:SetAttribute("OpenMenu", "click")
		else
			self.shieldButton:SetAttribute("OpenMenu", hoverMode)
		end
	end

	-- Weapon imbue button
	if self.weaponImbueButton then
		if requiresClick then
			self.weaponImbueButton:SetAttribute("OpenMenu", "click")
			-- Disable off-hand cast on right-click so it only opens the flyout
			self.weaponImbueButton:SetAttribute("type2", nil)
			self.weaponImbueButton:SetAttribute("macrotext2", nil)
		else
			self.weaponImbueButton:SetAttribute("OpenMenu", hoverMode)
			-- Restore off-hand cast on right-click
			local currentImbue = self.weaponImbueButton.currentImbueName
			if currentImbue then
				local offHandMacro = "/cast [@none] " .. currentImbue .. "\n/use 17\n/click StaticPopup1Button1"
				self.weaponImbueButton:SetAttribute("type2", "macro")
				self.weaponImbueButton:SetAttribute("macrotext2", offHandMacro)
			end
		end
	end

	-- the shield button's right-click: the flyout's (above), or Right-Click Casts Your Other Shield
	self:ApplyShieldButtonClicks()
end

-- A flyout only has buttons for the totems that were known when it was built,
-- and re-filtering cannot show a button that does not exist: a totem learned
-- mid-session never appeared until a /reload (found with a first fire totem:
-- allButtons was 0 after training Searing). Rebuild any element whose known
-- totems are not all represented. Out of combat only.
-- ---------------------------------------------------------------------------
-- Swap left and right click (opt.swapFlyoutClickButtons, Mainline clients)
-- ---------------------------------------------------------------------------
-- The option used to flip the totem flyout buttons only, which left the totem
-- button itself the other way round: right-click dropped a totem in the flyout
-- and pulled it back on the bar. Now it flips the mouse on everything with two
-- click meanings: totem buttons, Drop All, the imbue button and the shield and
-- imbue flyouts, and the shield button while Right-Click Casts Your Other Shield
-- is on (ApplyShieldButtonClicks). (Totem flyout buttons keep their own attribute swap.)
--
-- It is done with the secure templates' own button remap rather than by
-- mirroring attributes: a button with a "unit" it can assist looks up
-- "helpbutton<N>" and treats the click as that button instead. With unit =
-- player and the two buttons pointed at each other, every writer of type1 /
-- spell1 / type2 / shift-type2 (assign helpers, destroy, twisting, imbue macros)
-- stays exactly as it is - only the mouse is flipped. The "*" form covers every
-- modifier. None of the flipped actions takes a target, so unit = player is inert.
--
-- Cooldown buttons with a single action are not flipped (some may be targeted
-- spells, and unit = player would force a self-cast): they get the same action
-- on the other click instead, so neither click is ever dead.
-- The Classic line keeps the flyout-only behaviour it shipped with.
local CLICK_SWAP_SUPPORTED = (SPCompat.FOREVER)

function ShamanPower:ClicksSwapped()
	return (CLICK_SWAP_SUPPORTED and self.opt and self.opt.swapFlyoutClickButtons) and true or false
end

local function spSetAttr(frame, key, value)
	if frame:GetAttribute(key) ~= value then frame:SetAttribute(key, value) end
end

local function spFlipClicks(frame, on)
	if not frame then return end
	on = on and true or false
	spSetAttr(frame, "unit", on and "player" or nil)
	spSetAttr(frame, "*helpbutton1", on and "RightButton" or nil)
	spSetAttr(frame, "*helpbutton2", on and "LeftButton" or nil)
	frame.spClickFlipped = on or nil
end

local FILL_KEYS = { "type", "spell", "macrotext" }
local function spFillOtherClick(frame, on)
	if not frame then return end
	if on and (frame.spClickFilled or frame:GetAttribute("type2") == nil) then
		for _, k in ipairs(FILL_KEYS) do spSetAttr(frame, k .. "2", frame:GetAttribute(k .. "1")) end
		frame.spClickFilled = true
	elseif not on and frame.spClickFilled then
		for _, k in ipairs(FILL_KEYS) do frame:SetAttribute(k .. "2", nil) end
		frame.spClickFilled = nil
	end
end

function ShamanPower:ApplyClickSwap()
	if not CLICK_SWAP_SUPPORTED then return end
	if InCombatLockdown() then self.clickSwapPending = true return end
	self.clickSwapPending = nil
	local on = self:ClicksSwapped()
	for element = 1, 4 do spFlipClicks(self.totemButtons and self.totemButtons[element], on) end
	spFlipClicks(_G["ShamanPowerAutoDropAll"], on)
	local fill = on and not self:FlyoutOpensOnRightClick()
	for _, btn in ipairs(self.cooldownButtons or {}) do
		if btn == self.weaponImbueButton then
			spFlipClicks(btn, on)
		elseif btn ~= self.shieldButton then   -- (the shield button's own: ApplyShieldButtonClicks, below)
			spFillOtherClick(btn, fill)
		end
	end
	for k = 1, 2 do local flyout = self[k == 1 and "shieldFlyout" or "weaponImbueFlyout"]   -- each optional flyout (ipairs over { nil, imbue } stopped at the missing shield one)
		for _, btn in ipairs(flyout and (flyout.allButtons or flyout.buttons) or {}) do spFlipClicks(btn, on) end
	end
	-- the shield button: filled as the others, or flipped while Right-Click Casts Your Other Shield is on
	self:ApplyShieldButtonClicks()
end

-- The mouse button a handler should reason about: what the click MEANT.
function ShamanPower:LogicalButton(frame, button)
	if frame and frame.spClickFlipped then
		if button == "LeftButton" then return "RightButton" end
		if button == "RightButton" then return "LeftButton" end
	end
	return button
end

-- The mouse button a KEY has to press to get a button's main action.
function ShamanPower:KeyMouseButton(buttonName)
	if not self:ClicksSwapped() or not buttonName then return "LeftButton" end
	if buttonName:match("^ShamanPowerTotemBtn%d$") or buttonName == "ShamanPowerAutoDropAll" then return "RightButton" end
	local f = _G[buttonName]
	if f and f == self.weaponImbueButton then return "RightButton" end
	-- the shield button flips only while Right-Click Casts Your Other Shield is on: its key still casts
	if f and f == self.shieldButton and f.spClickFlipped then return "RightButton" end
	return "LeftButton"
end

-- Tooltip labels that follow the swap: main = the cast click, other = the second one.
function ShamanPower:ClickLabel(main, shift)
	local right = (main and self:ClicksSwapped()) or (not main and not self:ClicksSwapped())
	local text = right and "Right-click" or "Left-click"
	if shift then text = "Shift+" .. text:lower() end
	return (main and "|cff00ff00" or "|cffffcc00") .. text .. ":|r"
end

-- ---------------------------------------------------------------------------
-- "Reset to defaults" per settings section
-- ---------------------------------------------------------------------------
-- A cleared profile value falls back to its default, so a section reset is a
-- list of setting names to clear plus that section's normal refresh. Positions
-- are not part of this (they belong to the unlock mode). Out of combat only:
-- most of these touch secure frames.
ShamanPower.ResetSections = {
	compact = {
		label = "Compact Style",
		note = "Compact stays on; only its look goes back to default.",
		keys = { "compactOrientation", "compactDurationMode", "compactLineTexture", "compactIdleColor", "compactIdleOutline",
			"compactLength", "compactThickness", "compactOutlineWidth", "compactOutlineColorMode", "compactOutlineColor",
			"compactIconSquares", "compactIconSize", "compactFlyoutButtonSize", "compactPulseBar", "compactPulseText",
			"compactShieldLine", "compactESLine" },
		apply = function(self) self:ApplyCompactStyle() end,
	},
	flyouts = {
		label = "Flyout",
		note = "Your left/right click swap is not touched.",
		keys = { "flyoutStyle", "flyoutFrameOpacity", "flyoutCloseOnCast", "flyoutRouteBarKeys", "flyoutArrowsAlways",
			"flyoutArrowOnly", "flyoutShowEmpty", "flyoutSingleOpen", "totemFlyoutButtonSize" },
		apply = function(self)
			for element = 1, 4 do self:RebuildTotemFlyout(element) end
			self:ApplyFlyoutArrowMode()
			self:ApplyFlyoutPickMacros()
			self:UpdateTotemFlyoutEnabled()
			self:RefreshFlyoutLayout()
			self:ApplyTotemFlyoutButtonSize()
			if self.RouteFlyoutBarKeys then self:RouteFlyoutBarKeys() end
			for _, entry in pairs(self.boxFlyouts or {}) do pcall(entry.relayout) end
		end,
	},
	colors = {
		label = "Element Color",
		keys = { "elementColorPalette", "elementColorsCustom" },
		apply = function(self) self:ApplyElementColors() end,
	},
	scale = {
		label = "Scale",
		keys = { "buffscale", "cooldownBarScale", "configscale", "cooldownFlyoutButtonSize" },
		apply = function(self)
			self:UpdateLayout(); self:UpdateCooldownBarScale(); self:UpdateRoster()
			self:ApplyCooldownFlyoutButtonSize()
		end,
	},
	opacity = {
		label = "Opacity",
		keys = { "totemBarOpacity", "totemBarFullOpacityWhenActive", "cooldownBarOpacity", "cooldownBarFullOpacityWhenActive",
			"totemFlyoutOpacity", "cooldownFlyoutOpacity" },
		apply = function(self)
			self:UpdateTotemBarOpacity(); self:UpdateCooldownBarOpacity()
			self:UpdateTotemFlyoutOpacity(); self:UpdateCooldownFlyoutOpacity()
		end,
	},
	padding = {
		label = "Button Padding",
		keys = { "totemBarPadding", "cooldownBarPadding" },
		apply = function(self) self:UpdateRoster(); self:UpdateCooldownBar() end,
	},
}

function ShamanPower:ResetSection(id)
	local def = self.ResetSections[id]
	if not def then return end
	if InCombatLockdown() then
		print("|cff0070ddShamanPower:|r settings cannot be reset in combat")
		return
	end
	for _, key in ipairs(def.keys) do self.opt[key] = nil end
	local ok, err = pcall(def.apply, self)
	if not ok then print("|cff0070ddShamanPower:|r reset applied, but refreshing failed: " .. tostring(err) .. " (a /reload will finish it)") end
	print("|cff0070ddShamanPower|r: " .. def.label .. " settings are back to their defaults.")
	if self.RefreshConfig then pcall(self.RefreshConfig, self) end
	local ui = _G.ShamanPowerConfig   -- the custom settings window re-reads the page it is showing
	if ui and ui.RefreshCurrent then pcall(ui.RefreshCurrent, ui) end
end

function ShamanPower:ConfirmResetSection(id)
	local def = self.ResetSections[id]
	if not def then return end
	local text = "Reset the " .. def.label .. " settings to their defaults?"
	if def.note then text = text .. "\n\n" .. def.note end
	self:ShowSPDialog({
		key = "resetSection", title = "Reset settings", text = text,
		buttons = {
			{ text = "Reset", onClick = function()
				-- combat began while it was open: say so, and keep the question up for after the fight
				if InCombatLockdown() then
					print("|cff0070ddShamanPower|r: |cffe64a4asettings cannot be reset in combat - click Reset again after the fight.|r")
					return true
				end
				ShamanPower:ResetSection(id)
			end },
			{ text = "Cancel" },
		},
	})
end

-- ---------------------------------------------------------------------------
-- What exists on this client
-- ---------------------------------------------------------------------------
-- One code base serves clients with different spell lists (no Bloodlust,
-- Shamanistic Rage, Earth/Fire Elemental, Totem of Wrath or Wrath of Air on WoW:
-- Forever; no Rage of the Farseer or Totemic Projection anywhere else). The
-- client is asked (SPCompat.SpellExists: a readable spell name, minus the
-- known name-only leftovers), nothing is assumed per game version.
local function spSpellExists(id)
	if not id then return false end
	if SPCompat and SPCompat.SpellExists then return SPCompat.SpellExists(id) end
	return GetSpellInfo(id) ~= nil
end

function ShamanPower:TotemExistsOnClient(element, totemIndex)
	if not totemIndex or totemIndex == 0 then return true end
	local id = self.GetTotemSpell and self:GetTotemSpell(element, totemIndex)
	if not id then return not SPCompat.FOREVER end
	return spSpellExists(id)
end

-- Cooldown bar button types (the 5th field of TrackedCooldowns; 7 = weapon imbue).
ShamanPower.CooldownTypeLabels = {
	[1] = "Shield", [2] = GetSpellInfo(36936) or "Totemic Call", [3] = SPCompat.SpellLabel(20608, "Reincarnation"),
	[4] = SPCompat.SpellLabel(16188, "Nature's Swiftness"), [5] = SPCompat.SpellLabel(16190, "Mana Tide Totem"),
	[6] = SPCompat.SpellLabel(2825, "Bloodlust") .. "/" .. SPCompat.SpellLabel(32182, "Heroism"),
	[7] = "Weapon Imbue", [8] = SPCompat.SpellLabel(30823, "Shamanistic Rage"), [9] = SPCompat.SpellLabel(16166, "Elemental Mastery"),
	[10] = SPCompat.SpellLabel(425336, "Rage of the Farseer"), [11] = SPCompat.SpellLabel(437009, "Totemic Projection"),
}
ShamanPower.COOLDOWN_TYPE_COUNT = 11

function ShamanPower:CooldownTypeExists(cooldownType)
	if cooldownType == 1 or cooldownType == 7 then return true end   -- a shield and an imbue exist everywhere
	for _, entry in ipairs(self.TrackedCooldowns or {}) do
		if entry[5] == cooldownType and spSpellExists(entry[1]) then return true end
	end
	return false
end

-- The order the bar is sorted by: the saved order, limited to what this client
-- has, with anything it has that the saved order never mentioned added at the end
-- (the saved list was 8 long; Elemental Mastery, Rage of the Farseer and Totemic
-- Projection could not be placed at all).
function ShamanPower:GetCooldownBarOrder()
	local out, seen = {}, {}
	for _, t in ipairs(self.opt.cooldownBarOrder or {}) do
		if not seen[t] and self:CooldownTypeExists(t) then out[#out + 1] = t; seen[t] = true end
	end
	for t = 1, self.COOLDOWN_TYPE_COUNT do
		if not seen[t] and self:CooldownTypeExists(t) then out[#out + 1] = t; seen[t] = true end
	end
	return out
end

function ShamanPower:CooldownBarOrderChoices()
	local t = {}
	for _, cooldownType in ipairs(self:GetCooldownBarOrder()) do
		local label = self.CooldownTypeLabels[cooldownType] or ("Button " .. cooldownType)
		if cooldownType == 2 then label = GetSpellInfo(36936) or label end   -- "Totemic Recall" on some clients
		t[cooldownType] = label
	end
	return t
end

function ShamanPower:SetCooldownBarOrderSlot(position, cooldownType)
	local order = self:GetCooldownBarOrder()
	if not order[position] then return end
	for j, t in ipairs(order) do
		if t == cooldownType then order[j] = order[position] break end
	end
	order[position] = cooldownType
	-- types this client does not have stay in the saved list (after the rest), so a
	-- profile used on another client keeps where they were
	local seen = {}
	for _, t in ipairs(order) do seen[t] = true end
	for _, t in ipairs(self.opt.cooldownBarOrder or {}) do
		if not seen[t] then order[#order + 1] = t; seen[t] = true end
	end
	self.opt.cooldownBarOrder = order
	self:RecreateCooldownBar()   -- waits for the end of combat by itself
end

-- Element colours. ShamanPower has always used its own set (earth brown, air
-- pale blue); Blizzard's totem bar art uses green / orange / blue / purple, and
-- the flyout arrow tabs and the empty-slot art are that art, so the two sets
-- sat side by side. opt.elementColorPalette picks one, or "custom" with a colour
-- per element. The shared ElementColors tables are changed in place, so every
-- reader (Compact lines, alerts, party counters, the wizard) follows.
local ELEMENT_PALETTES = {
	classic  = { { 0.60, 0.40, 0.20 }, { 1.00, 0.40, 0.10 }, { 0.20, 0.60, 1.00 }, { 0.80, 0.80, 1.00 } },
	-- sampled from Interface\\Buttons\\UI-TotemBar (slot borders), lifted a little so they read on a thin line
	blizzard = { { 0.36, 0.72, 0.21 }, { 0.92, 0.37, 0.17 }, { 0.28, 0.70, 0.88 }, { 0.60, 0.32, 1.00 } },
	-- the logo's colours, #AE7E4E #F25735 #668DF2 #D0D5ED (the ShamanPower themes pick it, General > Themes)
	shamanpower = { { 174 / 255, 126 / 255, 78 / 255 }, { 242 / 255, 87 / 255, 53 / 255 },
		{ 102 / 255, 141 / 255, 242 / 255 }, { 208 / 255, 213 / 255, 237 / 255 } },
}

-- On WoW: Forever Blizzard's totem bar art is on screen next to ours (arrow tabs,
-- empty-slot totems), so its colours are the default there. Elsewhere the look
-- ShamanPower always had.
function ShamanPower:DefaultElementPalette()
	return (SPCompat.FOREVER) and "blizzard" or "classic"
end

function ShamanPower:ElementPaletteColor(element)
	local mode = self.opt and self.opt.elementColorPalette or self:DefaultElementPalette()
	if mode == "custom" then
		local c = self.opt.elementColorsCustom and self.opt.elementColorsCustom[element]
		if c then return c.r or 1, c.g or 1, c.b or 1 end
		mode = "classic"
	end
	local p = (ELEMENT_PALETTES[mode] or ELEMENT_PALETTES.classic)[element]
	return p[1], p[2], p[3]
end

function ShamanPower:ApplyElementColors()
	for element = 1, 4 do
		local c = self.ElementColors and self.ElementColors[element]
		if c then c.r, c.g, c.b = self:ElementPaletteColor(element) end
	end
	if self.UpdateCompactTotems then pcall(self.UpdateCompactTotems, self) end
end

-- Flyout icon sizes. The totem flyout icons were a fixed 28 (which towers over a
-- thin Compact line) and the cooldown bar's a fixed 22. Each style keeps its own
-- size, because what suits an icon bar does not suit a line:
--   opt.totemFlyoutButtonSize     totem flyouts on the icon bar   (28)
--   opt.compactFlyoutButtonSize   totem flyouts on the Compact bar (15, matching its icon squares)
--   opt.cooldownFlyoutButtonSize  shield / imbue flyouts           (22)
local function spClampSize(v, default)
	v = tonumber(v) or default
	if v < 12 then v = 12 elseif v > 56 then v = 56 end
	return v
end

function ShamanPower:TotemFlyoutButtonSize()
	if self.CompactActive and self:CompactActive() then
		return spClampSize(self.opt and self.opt.compactFlyoutButtonSize, 15)
	end
	return spClampSize(self.opt and self.opt.totemFlyoutButtonSize, 28)
end

-- t: 1 the shield's flyout, 7 the weapon imbue's (their own Icon Size: ShamanPowerCdItems.lua); nil: the shared one
function ShamanPower:CooldownFlyoutButtonSize(t)
	return spClampSize(self.opt and self:CdItemOpt(t, "flyoutIconSize"), 22)
end

function ShamanPower:ApplyCooldownFlyoutButtonSize()
	if InCombatLockdown() then
		print("|cff0070ddShamanPower:|r the flyout size cannot change in combat")
		return
	end
	for _, def in ipairs({ { self.shieldFlyout, "LayoutShieldFlyout", 1 }, { self.weaponImbueFlyout, "LayoutWeaponImbueFlyout", 7 } }) do
		local flyout = def[1]
		local size = self:CooldownFlyoutButtonSize(def[3])
		if flyout then
			flyout.buttonSize = size
			for _, b in ipairs(flyout.allButtons or flyout.buttons or {}) do b:SetSize(size, size) end
			if self[def[2]] then self[def[2]](self) end
		end
	end
end

function ShamanPower:ApplyTotemFlyoutButtonSize()
	if InCombatLockdown() then
		print("|cff0070ddShamanPower:|r the flyout size cannot change in combat")
		return
	end
	local size = self:TotemFlyoutButtonSize()
	for element = 1, 4 do
		local btn = self.totemButtons and self.totemButtons[element]
		if btn then btn:SetAttribute("flyoutButtonSize", size) end   -- read by the secure relayout
		local flyout = self.totemFlyouts and self.totemFlyouts[element]
		if flyout then
			flyout.buttonSize = size
			for _, b in ipairs(flyout.allButtons or {}) do b:SetSize(size, size) end
			self:LayoutFlyoutButtons(flyout)
			self:UpdateFlyoutVisibility(element)
		end
	end
end

-- Throw an element's flyout away and build it again. The old buttons are
-- retired first: the rebuild makes new frames under the same names.
function ShamanPower:RebuildTotemFlyout(element)
	if InCombatLockdown() then return end
	local flyout = self.totemFlyouts[element]
	if flyout then
		for _, btn in ipairs(flyout.allButtons or {}) do
			btn:Hide()
			btn.spFlyoutChild = nil
			btn:SetParent(nil)
		end
	end
	self.totemFlyouts[element] = nil
	self:CreateTotemFlyout(element)
end

function ShamanPower:AddMissingFlyoutButtons()
	if InCombatLockdown() then return end
	for element = 1, 4 do
		local flyout = self.totemFlyouts[element]
		local totems = self.Totems[element]
		if flyout and totems then
			local have = {}
			local missing = false
			for _, btn in ipairs(flyout.allButtons or {}) do
				have[btn.totemIndex] = true
				if not self:IsOff() and SPCompat.HasTotemCastAliases(btn.spellID)
					and btn:GetAttribute("mySpell") ~= SPCompat.TotemCastName(btn.spellID) then
					missing = true -- refresh secure cast/assign actions after learning a renamed rank
				end
			end
			for totemIndex, spellID in pairs(totems) do
				if not have[totemIndex] then
					if PlayerKnowsTotem(spellID) then missing = true break end
				end
			end
			if missing then self:RebuildTotemFlyout(element) end
		end
	end
end

-- An element that has never had a totem assigned gets one as soon as the player
-- knows any: the usual default if known, else the first known one, the way
-- Blizzard's own totem bar fills a slot the moment its first totem is trained.
-- Only a never-set (nil) assignment is touched; an explicit "none" (0) is the
-- player's choice and stays.
function ShamanPower:EnsureElementAssignments()
	if InCombatLockdown() or not self.player then return end
	ShamanPower_Assignments[self.player] = ShamanPower_Assignments[self.player] or {}
	local assignments = ShamanPower_Assignments[self.player]
	local changed = false
	for element = 1, 4 do
		local totems = self.Totems[element]
		if assignments[element] == nil and totems then
			local function known(idx)
				local spellID = idx and totems[idx]
				return spellID and PlayerKnowsTotem(spellID)
			end
			local pick = self.DefaultTotems and self.DefaultTotems[element]
			if not known(pick) then
				pick = nil
				local indices = {}
				for idx in pairs(totems) do indices[#indices + 1] = idx end
				table.sort(indices)
				for _, idx in ipairs(indices) do
					if known(idx) then pick = idx break end
				end
			end
			if pick then
				assignments[element] = pick
				changed = true
				self:SendMessage("ASSIGN " .. self.player .. " " .. element .. " " .. pick)
			end
		end
	end
	if changed then
		self:UpdateMiniTotemBar()
		self:UpdateDropAllButton()
		self:UpdateSPMacros()
		for element = 1, 4 do self:UpdateFlyoutVisibility(element) end
	end
	return changed
end

-- Recreate all totem flyouts (used when major changes require full rebuild)
function ShamanPower:RecreateTotemFlyouts()
	if InCombatLockdown() then
		print("|cff0070ddShamanPower:|r Cannot change flyout settings in combat")
		return
	end

	-- a totem learned since the flyouts were built needs a button first
	self:AddMissingFlyoutButtons()

	-- Instead of destroying and recreating buttons (which breaks secure handlers),
	-- just update which buttons are enabled/disabled and rebuild the buttons table
	local elementKeys = { [1] = "earth", [2] = "fire", [3] = "water", [4] = "air" }

	for element = 1, 4 do
		local flyout = self.totemFlyouts[element]
		if flyout and flyout.allButtons then
			-- Rebuild the active buttons list based on current settings
			local elementKey = elementKeys[element]
			flyout.buttons = {}

			for _, btn in ipairs(flyout.allButtons) do
				local totemIdx = btn.totemIndex
				local flyoutKey = elementKey .. "_" .. totemIdx
				local isEnabled = self.opt.flyoutTotems == nil or self.opt.flyoutTotems[flyoutKey] ~= false
				btn.spRescued = nil
				-- Talent-gated totems only show while the talent is actually known
				if btn.talentSpellID and not PlayerKnowsTotem(btn.talentSpellID) then
					isEnabled = false
				end

				if isEnabled then
					btn.isDisabledInFlyout = false
					btn:SetAttribute("isCurrentAssignment", false)
					btn:SetAttribute("flyoutHidden", false)
					table.insert(flyout.buttons, btn)
				else
					btn:Hide()
					btn.isDisabledInFlyout = true
					btn:SetAttribute("isCurrentAssignment", true)  -- Treat as hidden
					btn:SetAttribute("flyoutHidden", true)
				end
			end

			-- Sort buttons by totemIndex for consistent ordering
			table.sort(flyout.buttons, function(a, b) return a.totemIndex < b.totemIndex end)

			-- Re-layout the flyout
			self:LayoutFlyoutButtons(flyout)
			self:UpdateFlyoutVisibility(element)
		end
	end
end

-- ============================================================================
-- Player Totem Range Indicator (greys out icon if out of range of own totem)
-- ============================================================================

-- Update player's own totem range (desaturate icons when out of range)
-- Reusable arrays for totem range check (avoids creating garbage)
ShamanPower.totemRangeBuffNames = {nil, nil, nil, nil}  -- Buff names to check (indexed by element)
ShamanPower.totemRangeResults = {false, false, false, false}  -- Results (indexed by element)

function ShamanPower:UpdatePlayerTotemRange()
	-- Collect buff names we need to check for each element
	local buffNames = self.totemRangeBuffNames
	local results = self.totemRangeResults
	local buffLowerCache = self.buffNameLowerCache or {}
	self.buffNameLowerCache = buffLowerCache

	-- Track weapon enchant totems (need special weapon enchant check instead of buff check)
	local isWeaponEnchantTotem = self._rangeEnchantScratch   -- [element] = true if weapon enchant totem (reused: this runs twice a second)
	if not isWeaponEnchantTotem then isWeaponEnchantTotem = {}; self._rangeEnchantScratch = isWeaponEnchantTotem end
	isWeaponEnchantTotem[1], isWeaponEnchantTotem[2], isWeaponEnchantTotem[3], isWeaponEnchantTotem[4] = false, false, false, false

	-- Reset results and collect buff names
	for element = 1, 4 do
		results[element] = false
		local haveTotem, totemName = self:GetElementTotemInfo(element)
		if haveTotem and totemName then
			-- Check if this is a weapon enchant totem (Windfury or Flametongue)
			if element == 4 and SPCompat.TotemNameMatches(totemName, 8512, "Windfury Totem") and not SPCompat.FOREVER then
				-- Windfury Totem (Air) - applies weapon enchant, not a buff
				-- (WoW: Forever: a party buff, read below like the others)
				isWeaponEnchantTotem[element] = true
				buffNames[element] = nil
			elseif element == 2 and SPCompat.TotemNameMatches(totemName, 8227, "Flametongue Totem") then
				-- Flametongue Totem (Fire) - applies weapon enchant, not a buff
				isWeaponEnchantTotem[element] = true
				buffNames[element] = nil
			else
				-- Standard totem - try to get buff name for range tracking
				buffNames[element] = self:GetActiveTotemBuffName(element)
			end
		else
			buffNames[element] = nil
		end
	end

	-- Single scan through player buffs, checking all 4 elements at once
	local scannedCache = self.scannedBuffLowerCache or {}
	self.scannedBuffLowerCache = scannedCache

	-- When buffs cannot be read (combat on the Mainline family) the answer comes from the
	-- drop-distance model further down, so there is nothing to scan for - and each aura
	-- read on that client builds a table.
	local blindNow = TRACK_TOTEM_DROPS and SPCompat and SPCompat.AurasUnreadable and SPCompat.AurasUnreadable()
	-- The buff list only changes on an aura event: reuse the last scan until then.
	local scan = self._rangeScan
	if not scan then scan = { hits = {}, names = {} }; self._rangeScan = scan end
	local reuse = not blindNow and self:AuraCacheValid("player", scan.gen, scan.at)
	if reuse then
		for element = 1, 4 do
			if scan.names[element] ~= buffNames[element] then reuse = false break end
		end
	end
	if reuse then
		for element = 1, 4 do results[element] = scan.hits[element] end
	end
	for i = 1, ((blindNow or reuse) and 0 or 20) do
		local name = SPCompat.UnitBuff("player", i)
		if not name then break end

		local nameLower = scannedCache[name]
		if not nameLower then
			nameLower = name:lower()
			scannedCache[name] = nameLower
		end

		-- Check this buff against all 4 element buff names
		for element = 1, 4 do
			if not results[element] and buffNames[element] then
				local searchLower = buffLowerCache[buffNames[element]]
				if not searchLower then
					searchLower = buffNames[element]:lower()
					buffLowerCache[buffNames[element]] = searchLower
				end
				if nameLower:find(searchLower, 1, true) then
					results[element] = true
				end
			end
		end
	end

	if not blindNow and not reuse then
		scan.gen, scan.at = self.auraGen["player"] or 0, GetTime()
		for element = 1, 4 do scan.hits[element], scan.names[element] = results[element], buffNames[element] end
	end

	-- Check weapon enchant totems via GetWeaponEnchantInfo()
	local hasWeaponEnchant = nil  -- Lazy load only if needed
	for element = 1, 4 do
		if isWeaponEnchantTotem[element] then
			if hasWeaponEnchant == nil then
				hasWeaponEnchant = self:SPRangeHasWindfuryWeapon()
			end
			results[element] = hasWeaponEnchant
		end
	end

	-- Combat hides buffs from addons on the Mainline family, and an empty read
	-- there means "not allowed to look", not "no buff". Measure distance from
	-- where each totem was dropped instead; with no position, keep the last
	-- answer from while buffs were readable, and never grey out on a guess.
	if TRACK_TOTEM_DROPS then
		local blind = SPCompat and SPCompat.AurasUnreadable and SPCompat.AurasUnreadable()
		local lastRange = self.totemRangeLast
		for element = 1, 4 do
			if buffNames[element] then
				if blind then
					local near = self:TotemDropInRange(element)
					if near == nil then near = lastRange[element] end
					if near == nil then near = true end
					results[element] = near
				else
					lastRange[element] = results[element]
				end
			end
		end
	end

	-- Check if using Dynamic/TotemTimers mode (active totem shows on main icon)
	local useActiveAsMain = self.opt.activeTotemAsMain

	-- Now apply the results to icons
	for element = 1, 4 do
		local haveTotem = self:GetElementTotemInfo(element)
		local hasBuff = results[element]

		-- Determine if this element has trackable range
		local hasTrackableRange = buffNames[element] or isWeaponEnchantTotem[element]

		-- Check if active overlay is showing (different totem than assigned)
		local activeOverlay = self.activeTotemOverlays and self.activeTotemOverlays[element]
		local overlayActive = activeOverlay and activeOverlay.isActive

		local totemBtn = self.totemButtons[element]
		local iconTexture = totemBtn and totemBtn.icon

		-- Determine which icon to update for range display:
		-- - In useActiveAsMain mode: main icon shows active totem, update main icon
		-- - In classic mode with overlay: overlay shows active totem, update overlay icon
		-- - No overlay: update main icon
		local updateMainIcon = not overlayActive or useActiveAsMain
		local updateOverlayIcon = overlayActive and not useActiveAsMain

		-- Update the appropriate icon based on trackability
		if updateOverlayIcon and activeOverlay and activeOverlay.icon then
			if haveTotem then
				if hasTrackableRange then
					activeOverlay.icon:SetDesaturated(not hasBuff)
					activeOverlay.icon:SetVertexColor(hasBuff and 1 or 0.6, hasBuff and 1 or 0.6, hasBuff and 1 or 0.6)
				else
					-- Non-trackable totem - always show normal (not greyed)
					activeOverlay.icon:SetDesaturated(false)
					activeOverlay.icon:SetVertexColor(1, 1, 1)
				end
			end
		end

		if updateMainIcon and iconTexture then
			if haveTotem then
				if hasTrackableRange then
					iconTexture:SetDesaturated(not hasBuff)
				else
					-- Non-trackable totem - always show normal (not greyed)
					iconTexture:SetDesaturated(false)
				end
			else
				iconTexture:SetDesaturated(false)
			end
		end
	end
end

-- ============================================================================
-- Cooldown Tracker Bar (tracks shields, ankh, nature's swiftness, etc.)
-- ============================================================================

ShamanPower.cooldownBar = nil
ShamanPower.cooldownButtons = {}

-- Spells to track on the cooldown bar
-- Format: {spellID, name, type} where type is "buff", "cooldown", or "shield"
-- 5th field = cooldownType (pop-out key, order list, keybinds); 7 is the imbue button.
ShamanPower.TrackedCooldowns = {
	{324, "Lightning Shield", "shield", "cdbarShowShields", 1},   -- Lightning/Water Shield (combined)
	{36936, "Totemic Call", "cooldown", "cdbarShowRecall", 2},  -- Totemic Call (recall totems)
	{20608, "Reincarnation", "cooldown", "cdbarShowReincarnation", 3},  -- Ankh cooldown
	{16188, "Nature's Swiftness", "cooldown", "cdbarShowNS", 4},  -- NS cooldown (Resto talent)
	{16190, "Mana Tide Totem", "cooldown", "cdbarShowManaTide", 5},  -- Mana Tide cooldown (Resto talent)
	{30823, "Shamanistic Rage", "cooldown", "cdbarShowShamanisticRage", 8},  -- Shamanistic Rage cooldown (Enhancement talent)
	{2825, "Bloodlust", "cooldown", "cdbarShowBloodlust", 6},  -- Bloodlust (Horde)
	{32182, "Heroism", "cooldown", "cdbarShowBloodlust", 6},  -- Heroism (Alliance)
	{16166, "Elemental Mastery", "cooldown", "cdbarShowElementalMastery", 9},  -- Elemental Mastery (Elemental talent)
	-- WoW: Forever only (the spells do not exist on other clients, so the buttons never appear there)
	{425336, "Rage of the Farseer", "cooldown", "cdbarShowRageOfTheFarseer", 10},  -- Enhancement capstone, 3 min
	{437009, "Totemic Projection", "cooldown", "cdbarShowTotemicProjection", 11},  -- level 22, 1 min
}

-- Spell colors for progress bars (used when cdbarSpellColors is enabled)
ShamanPower.SpellBarColors = {
	-- Cooldown bar spells (by spellID)
	[324]   = {0.4, 0.6, 1.0},   -- Lightning Shield - blue
	[24398] = {0.2, 0.7, 1.0},   -- Water Shield - light blue
	[408510] = {0.2, 0.7, 1.0},  -- Water Shield on WoW: Forever (talent, Season of Discovery spell ID)
	[36936] = {0.6, 0.4, 0.2},   -- Totemic Call - earthy brown
	[20608] = {0.8, 0.2, 0.2},   -- Reincarnation - red
	[16188] = {0.2, 0.8, 0.3},   -- Nature's Swiftness - green
	[16190] = {0.2, 0.5, 1.0},   -- Mana Tide Totem - blue
	[30823] = {0.8, 0.5, 0.1},   -- Shamanistic Rage - orange
	[2825]  = {0.8, 0.1, 0.1},   -- Bloodlust - red
	[32182] = {0.8, 0.1, 0.1},   -- Heroism - red
	[16166] = {0.9, 0.6, 0.1},   -- Elemental Mastery - golden
	[425336] = {0.8, 0.1, 0.1},  -- Rage of the Farseer (Forever) - red, the Bloodlust slot
	[437009] = {0.6, 0.4, 0.2},  -- Totemic Projection (Forever) - earthy brown
}

-- Weapon imbue colors (by imbue type index)
ShamanPower.ImbueBarColors = {
	[1] = {0.6, 0.8, 1.0},   -- Windfury - white/light blue
	[2] = {1.0, 0.4, 0.1},   -- Flametongue - orange/red
	[3] = {0.3, 0.6, 1.0},   -- Frostbrand - blue
	[4] = {0.6, 0.4, 0.2},   -- Rockbiter - brown
}

-- Shield spell IDs for the combined shield button. Water Shield's ID differs per
-- client: 24398 on TBC, 408510 on WoW: Forever (Restoration talent, Season of
-- Discovery spell ID), 52127 on retail. Take the first one the client knows.
local WATER_SHIELD_ID = 24398
for _, id in ipairs({ 24398, 408510, 52127 }) do
	if SPCompat and SPCompat.SpellExists and SPCompat.SpellExists(id) then WATER_SHIELD_ID = id break end
end
ShamanPower.ShieldSpells = {
	{324, "Lightning Shield"},          -- Lightning Shield
	{WATER_SHIELD_ID, "Water Shield"},  -- Water Shield
}

-- What the cooldown bar's flyouts are built from: the highest rank of each weapon
-- imbue and which shields are known. Learning one later (Flametongue Weapon at
-- 10, Water Shield) changes it, and SPELLS_CHANGED rebuilds the bar so the flyout
-- offers it straight away instead of after a /reload.
function ShamanPower:CooldownBarSpellKey()
	-- one bit per imbue and per shield known: a number, so nothing is built
	local key, bit = 0, 1
	for i = 1, 4 do
		if self:GetHighestRankImbue(i) then key = key + bit end
		bit = bit * 2
	end
	for _, s in ipairs(self.ShieldSpells or {}) do
		if PlayerKnowsSpellByID(s[1]) then key = key + bit end
		bit = bit * 2
	end
	return key
end

function ShamanPower:CreateCooldownBar()
	if self.cooldownBar then return end
	self._cdBarSpellKey = self:CooldownBarSpellKey()
	if not self.autoButton then return end

	-- Create the cooldown bar frame
	local bar = CreateFrame("Frame", "ShamanPowerCooldownBar", self.autoButton, "BackdropTemplate")
	-- a bar on its default spot stays clear of the totem bar as it grows (Hook: the backdrop has its own)
	bar:HookScript("OnSizeChanged", function() ShamanPower:ApplyDefaultBarPositions() end)
	-- Only apply backdrop if not hidden
	if not self.opt.hideCooldownBarFrame then
		bar:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 12,
			insets = { left = 2, right = 2, top = 2, bottom = 2 }
		})
		bar:SetBackdropColor(0, 0, 0, 0.7)
		bar:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
		self:ThemePaintBarFrame(bar, "cd.frame")   -- General > Themes; nothing on Standard
	end

	self.cooldownBar = bar
	self.cooldownButtons = {}

	-- Add drag handlers for independent positioning (ALT+drag on bar itself)
	bar:SetScript("OnDragStart", function(self)
		-- Unlocked = drag the bar directly, no modifier. (Alt+drag also still works.)
		if not ShamanPower.opt.cooldownBarLocked then
			ShamanPower.cooldownBarDragging = true
			self:StartMoving()
		end
	end)

	bar:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		-- Only save position if we were actually dragging
		if ShamanPower.cooldownBarDragging then
			-- Save full anchor info so restore uses exact same positioning
			ShamanPower.opt.cooldownBarPosition = ShamanPower:SavePositionRecord(self)
			ShamanPower.opt.cooldownBarPoint, ShamanPower.opt.cooldownBarRelPoint = nil, nil
			ShamanPower.opt.cooldownBarPosX, ShamanPower.opt.cooldownBarPosY = nil, nil
			ShamanPower.cooldownBarDragging = false
		end
	end)

	-- Create drag handle CheckButton for cooldown bar (like main frame drag handle)
	-- Only visible when CD bar is unlocked from totem bar
	-- Green = position movable, Red = position locked
	local dragHandle = CreateFrame("CheckButton", "ShamanPowerCDBarDragHandle", bar)
	dragHandle:SetSize(16, 16)
	dragHandle:SetPoint("LEFT", bar, "LEFT", -18, 0)
	dragHandle:RegisterForDrag("LeftButton")
	dragHandle:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	dragHandle:SetMovable(false)
	dragHandle:EnableMouse(true)

	-- Normal texture (green - position movable)
	dragHandle:SetNormalTexture("Interface\\AddOns\\ShamanPower\\Icons\\draghandle")
	-- Checked texture (red - position locked)
	dragHandle:SetCheckedTexture("Interface\\AddOns\\ShamanPower\\Icons\\draghandle-checked")

	-- Click to toggle position lock (not bar attachment)
	dragHandle:SetScript("OnClick", function(self, mousebutton)
		if InCombatLockdown() then return end
		if mousebutton == "LeftButton" then
			-- Toggle frame lock (whether position can be changed)
			ShamanPower.opt.cooldownBarFrameLocked = not ShamanPower.opt.cooldownBarFrameLocked
			self:SetChecked(ShamanPower.opt.cooldownBarFrameLocked)
		end
	end)

	dragHandle:SetScript("OnDragStart", function(self)
		-- Only allow dragging when position is not locked
		if not ShamanPower.opt.cooldownBarFrameLocked then
			ShamanPower.cooldownBarDragging = true
			ShamanPower.cooldownBar:StartMoving()
		end
	end)

	dragHandle:SetScript("OnDragStop", function(self)
		ShamanPower.cooldownBar:StopMovingOrSizing()
		-- Only save position if we were actually dragging
		if ShamanPower.cooldownBarDragging then
			-- Save full anchor info so restore uses exact same positioning
			ShamanPower.opt.cooldownBarPosition = ShamanPower:SavePositionRecord(ShamanPower.cooldownBar)
			ShamanPower.opt.cooldownBarPoint, ShamanPower.opt.cooldownBarRelPoint = nil, nil
			ShamanPower.opt.cooldownBarPosX, ShamanPower.opt.cooldownBarPosY = nil, nil
			ShamanPower.cooldownBarDragging = false
		end
	end)

	dragHandle:SetScript("OnEnter", function(self)
		if ShamanPower.opt.ShowTooltips then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText("|cffffffffLeft-Click|r Lock/Unlock Position\n|cffffffffDrag|r Move Cooldown Bar")
			GameTooltip:Show()
		end
	end)

	dragHandle:SetScript("OnLeave", function(self)
		GameTooltip:Hide()
	end)

	-- Set initial checked state (checked = position locked = red)
	dragHandle:SetChecked(self.opt.cooldownBarFrameLocked)
	dragHandle:Hide()  -- Hidden by default, only shown when CD bar unlocked from totem bar
	self.cooldownBarDragHandle = dragHandle

	-- Create buttons for each tracked spell
	local buttonSize = 22
	local spacing = self.opt.cooldownBarPadding or 2
	local padding = 4
	local numButtons = 0

	for i, spellData in ipairs(self.TrackedCooldowns) do
		local spellID, spellName, spellType, optionKey = spellData[1], spellData[2], spellData[3], spellData[4]
		local name, _, icon = GetSpellInfo(spellID)

		-- Check if this item is enabled in options (default to true if not set)
		local isEnabled = (optionKey == nil) or (self.opt[optionKey] ~= false)

		-- Skip Totemic Call on cooldown bar if it should be on totem bar instead
		if spellID == 36936 and self:CdItemOpt(2, "onTotemBar") then
			isEnabled = false
		end

		-- For shield type, check if player knows any shield spell
		-- (check regardless of isEnabled - hidden buttons still need to be functional)
		local knowsSpell = false
		local defaultShieldSpell = nil
		if spellType == "shield" then
			-- The preferred shield when you know it, else any known one (AssignedShieldIndex: a pick made in a
			-- fight counts too, if the bar is made again as it ends before that pick is saved)
			local shieldIdx = self:AssignedShieldIndex()
			local shieldData = shieldIdx and self.ShieldSpells[shieldIdx]
			if shieldData then
				knowsSpell = true
				defaultShieldSpell = SPCompat.SpellName(shieldData[1]) or shieldData[1]
				local _, _, sIcon = GetSpellInfo(shieldData[1])
				if sIcon then icon = sIcon end
			end
		else
			-- IsSpellKnown answers by ID and needs no string at all, which is the
			-- point: a client can ship a live spell with its name encrypted
			-- (Elemental Mastery 16166 on the Forever line), and requiring a
			-- readable name here dropped the button for a talent the player
			-- actually had. The name check stays as the Classic fallback.
			knowsSpell = PlayerKnowsSpellByID(spellID)
		end

		-- Only create button if player knows this spell and it's enabled
		if knowsSpell and isEnabled then
			numButtons = numButtons + 1

			-- An encrypted name means GetSpellInfo gave us no icon either, so
			-- fall back rather than drawing a blank button.
			if not icon then
				icon = (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID))
					or (GetSpellTexture and GetSpellTexture(spellID))
					or "Interface\\Icons\\INV_Misc_QuestionMark"
			end

			-- Use different templates for shield (needs combat flyout) vs other buttons
			local templateString
			if spellType == "shield" then
				-- Shield button needs secure handler templates for combat-functional flyout
				templateString = "SecureActionButtonTemplate, SecureHandlerEnterLeaveTemplate, SecureHandlerMouseUpDownTemplate, SecureHandlerBaseTemplate"
			else
				templateString = "SecureActionButtonTemplate"
			end
			local btn = CreateFrame("Button", "ShamanPowerCD" .. i, bar, templateString)
			btn:SetSize(buttonSize, buttonSize)
			btn:RegisterForClicks("AnyUp", "AnyDown")

			local iconTex = btn:CreateTexture(nil, "ARTWORK")
			iconTex:SetAllPoints()
			iconTex:SetTexture(icon)
			iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			btn.icon = iconTex

			-- Cooldown overlay
			local cd = CreateFrame("Cooldown", "ShamanPowerCD" .. i .. "Cooldown", btn, "CooldownFrameTemplate")
			cd:SetAllPoints()
			cd:SetDrawEdge(false)
			cd:SetDrawBling(false)
			-- no game countdown numbers: the addon draws the time (Show Cooldown Text,
			-- Duration Text). Without this the radial swipe printed its own "10m" on
			-- the shield whatever the settings said. The engine path (PlaceEngineBarText)
			-- turns them on where they stand in for the addon's text.
			cd:SetHideCountdownNumbers(true)
			btn.cooldown = cd

			-- Dark overlay for when buff is missing
			local dark = btn:CreateTexture(nil, "OVERLAY")
			dark:SetAllPoints()
			dark:SetColorTexture(0, 0, 0, 0.6)
			dark:Hide()
			btn.darkOverlay = dark

			-- Progress bar elements (position set dynamically in UpdateCooldownBarProgressBars)
			local barSize = self.opt.cdbarProgressBarHeight or 3

			-- Background bar
			local bgBar = btn:CreateTexture(nil, "OVERLAY")
			bgBar:SetColorTexture(0, 0, 0, 0.7)
			bgBar:Hide()
			btn.bgBar = bgBar

			-- Progress bar (colored)
			local progressBar = btn:CreateTexture(nil, "OVERLAY", nil, 1)
			ShamanPower:SetSPBarColor(progressBar, "cooldown", 0.2, 0.8, 0.2, 0.9)
			progressBar:Hide()
			btn.progressBar = progressBar

			-- Grey sweep overlay for visual timer
			local greyOverlay = btn:CreateTexture(nil, "ARTWORK", nil, 1)
			greyOverlay:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
			greyOverlay:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, 0)
			greyOverlay:SetHeight(0)
			greyOverlay:SetTexture(icon)
			greyOverlay:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			greyOverlay:SetDesaturated(true)
			greyOverlay:SetVertexColor(0.5, 0.5, 0.5)
			greyOverlay:Hide()
			btn.greyOverlay = greyOverlay

			-- Time text for showing remaining duration (center of button - legacy)
			local timeText = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
			ShamanPower:AdoptSPFont(timeText, "timers")   -- template font = the design; follows the Fonts settings
			timeText:SetPoint("CENTER", btn, "CENTER", 0, 0)
			timeText:SetText("")
			btn.timeText = timeText

			-- Duration text INSIDE the bar
			local insideText = btn:CreateFontString(nil, "OVERLAY", nil, 7)
			ShamanPower:SetSPFont(insideText, "timers", 8, "OUTLINE")
			insideText:SetTextColor(1, 1, 1)
			insideText:Hide()
			btn.insideText = insideText

			-- Duration text OUTSIDE the bar
			local outsideText = btn:CreateFontString(nil, "OVERLAY")
			ShamanPower:SetSPFont(outsideText, "timers", 8, "OUTLINE")
			outsideText:SetTextColor(1, 1, 1)
			outsideText:Hide()
			btn.outsideText = outsideText
			btn.belowText = outsideText  -- Compatibility

			-- Duration text ON the icon
			local iconText = btn:CreateFontString(nil, "OVERLAY")
			ShamanPower:SetSPFont(iconText, "timers", 9, "OUTLINE")
			iconText:SetPoint("CENTER", btn, "CENTER", 0, 0)
			iconText:SetTextColor(1, 1, 1)
			iconText:Hide()
			btn.iconText = iconText

			-- Keybind text (top right corner, like standard action buttons)
			local keybindText = btn:CreateFontString(nil, "OVERLAY")
			ShamanPower:SetSPFont(keybindText, "labels", 9, "OUTLINE", "Fonts\\ARIALN.TTF")
			keybindText:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 1, 0)
			keybindText:SetTextColor(0.9, 0.9, 0.9, 1)
			keybindText:SetText("")
			keybindText:Hide()  -- Hidden by default, shown if option enabled
			btn.keybindText = keybindText

			-- Charge count text for shield buttons (bottom right corner)
			if spellType == "shield" then
				local chargeText = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
				ShamanPower:AdoptSPFont(chargeText, "charges")   -- template font = the design; follows the Fonts settings
				chargeText:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
				chargeText:SetText("")
				btn.chargeText = chargeText
			end

			-- Ankh count text for Reincarnation button (bottom right corner)
			if spellID == 20608 then
				local ankhCountText = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
				ShamanPower:AdoptSPFont(ankhCountText, "labels")   -- template font = the design; follows the Fonts settings
				ankhCountText:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
				ankhCountText:SetText("")
				btn.ankhCountText = ankhCountText
			end

			-- Store spell info
			btn.spellID = spellID
			btn.spellName = SPCompat.SpellLabel(spellID, spellName)
			btn.spellType = spellType
			btn.defaultShieldSpell = defaultShieldSpell

			-- cooldownType keys the pop-out record, the order list and the keybinds
			-- (1=Shield, 2=Recall, 3=Ankh, 4=NS, 5=MTT, 6=BL/Hero, 7=Imbue, 8+ see TrackedCooldowns).
			-- Every entry carries its own type as the 5th field so two buttons never share a key.
			btn.cooldownType = spellData[5] or (i <= 5 and i or 6)

			-- Store reference to shield button for flyout
			if spellType == "shield" then
				self.shieldButton = btn
				self:EnsureShieldChargeContainer(btn)
			end

			-- Set up click action
			if spellType == "shield" then
				-- Shield button casts the preferred shield
				local shieldSpellName = GetSpellInfo(defaultShieldSpell)
				if shieldSpellName then
					btn:SetAttribute("type1", "spell")
					btn:SetAttribute("spell1", shieldSpellName)
					btn.spShieldSeen = ShamanPower:ShieldIndexOfName(shieldSpellName)   -- (ShieldButtonChanged)
				end

				-- SECURE HANDLER: Show flyout on enter (WORKS IN COMBAT)
				btn:SetAttribute("OpenMenu", "mouseover")
				ShamanPower:SetSnippet(btn, "_onenter", [[
					if self:GetAttribute("OpenMenu") == "mouseover" then
						self:ChildUpdate("show", true)
					end
				]])

				-- SECURE HANDLER: Hide flyout on leave (WORKS IN COMBAT)
				ShamanPower:SetSnippet(btn, "_onleave", SP_SECURE_ONLEAVE_SELF)

				-- SECURE HANDLER: Show flyout on right-click when in click mode (WORKS IN COMBAT)
				ShamanPower:SetSnippet(btn, "_onmouseup", [[
					local button = button
					if button == "RightButton" and self:GetAttribute("OpenMenu") == "click" then
						self:ChildUpdate("show", true)
					end
				]])

				-- Right-Click Casts Your Other Shield (ApplyShieldButtonClicks) puts that shield on the button
				-- through secure helpers, in a fight too: the icon and the flyout follow (ShieldButtonChanged)
				btn:HookScript("PostClick", function() ShamanPower:ShieldButtonChanged(true) end)
			else
				-- Regular cooldown buttons cast their spell
				local castSpellName = GetSpellInfo(spellID)
				if castSpellName then
					btn:SetAttribute("type1", "spell")
					btn:SetAttribute("spell1", castSpellName)
				end
			end

			-- Tooltip and flyout
			if spellType == "shield" then
				-- Use HookScript for tooltip (works alongside secure handlers)
				btn:HookScript("OnEnter", function(self)
					if not ShamanPower.opt.ShowTooltips then return end
					GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
					GameTooltip:SetText("Shield Spells")
					if self.activeShieldID then
						local activeName = GetSpellInfo(self.activeShieldID)
						GameTooltip:AddLine("Active: " .. (activeName or "Unknown"), 0, 1, 0)
					else
						GameTooltip:AddLine("No shield active", 1, 0.5, 0.5)
					end
					-- Right-Click Casts Your Other Shield: both clicks (Swap Left and Right Click trades them)
					if ShamanPower:ShieldOtherClickActive() then
						local cur = ShamanPower:ShieldIndexOfName(self:GetAttribute("spell1")) or ShamanPower:AssignedShieldIndex()
						local other = ShamanPower:OtherShieldIndex(cur)
						local curName = cur and SPCompat.SpellName(ShamanPower.ShieldSpells[cur][1])
						local otherName = other and SPCompat.SpellName(ShamanPower.ShieldSpells[other][1])
						if curName and otherName then
							GameTooltip:AddLine(ShamanPower:ClickLabel(true) .. " Cast " .. curName, 1, 1, 1)
							GameTooltip:AddLine(ShamanPower:ClickLabel(false) .. " Cast " .. otherName .. " and keep it on the button", 1, 1, 1)
						end
					end
					if ShamanPower.opt.enableMiddleClickPopOut ~= false then
						GameTooltip:AddLine("|cff00ccffMiddle-click:|r Pop out", 1, 1, 1)
					end
					GameTooltip:Show()
				end)

				btn:HookScript("OnLeave", function()
					GameTooltip:Hide()
				end)
			else
				btn:SetScript("OnEnter", function(self)
					if not ShamanPower.opt.ShowTooltips then return end
					GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
					GameTooltip:SetSpellByID(SPCompat.HighestKnownRank and SPCompat.HighestKnownRank(self.spellID) or self.spellID)
					if ShamanPower.opt.enableMiddleClickPopOut ~= false then
						GameTooltip:AddLine("|cff00ccffMiddle-click:|r Pop out", 1, 1, 1)
					end
					GameTooltip:Show()
				end)
				btn:SetScript("OnLeave", function()
					GameTooltip:Hide()
				end)
			end

			-- Middle-click to pop out cooldown item (or return/settings if already popped)
			btn:HookScript("OnClick", function(self, button)
				if button == "MiddleButton" then
					-- Check if pop-out is enabled
					if ShamanPower.opt.enableMiddleClickPopOut == false then return end

					local cdType = self.cooldownType
					local key = "cd_" .. cdType

					if ShamanPower.opt.poppedOut and ShamanPower.opt.poppedOut[key] then
						-- Already popped out
						if IsShiftKeyDown() then
							-- SHIFT+middle-click opens settings
							local frame = ShamanPower.poppedOutFrames[key]
							if frame then
								ShamanPower:ShowPopOutSettingsPanel(key, frame)
							end
						else
							-- Plain middle-click returns to bar
							if InCombatLockdown() then
								print("|cff0070ddShamanPower:|r Cannot modify pop-outs during combat")
								return
							end
							ShamanPower:ReturnPopOutToBar(key)
						end
					else
						-- Not popped out, pop it out
						if InCombatLockdown() then
							print("|cff0070ddShamanPower:|r Cannot pop out during combat")
							return
						end
						ShamanPower:PopOutCooldownItem(cdType)
					end
				end
			end)

			-- Track if button is hidden in options (still functional but not shown)
			btn.isHiddenInOptions = not isEnabled
			if not isEnabled then
				btn:Hide()
			end

			self.cooldownButtons[numButtons] = btn
		end
	end

	-- Store layout parameters for later use
	bar.buttonSize = buttonSize
	bar.spacing = spacing
	bar.padding = padding
	bar.numButtons = numButtons

	-- Initial sizing will be done in UpdateCooldownBarLayout
	if numButtons == 0 then
		bar:SetSize(1, 1)
	end

	-- Register cooldown updates with consolidated update system (5fps)
	if not self.updateSystem.subsystems["cooldownBar"] then
		self:RegisterUpdateSubsystem("cooldownBar", 0.2, function()
			ShamanPower:UpdateCooldownButtons()
			if ShamanPower.opt.cooldownBarFullOpacityWhenActive then
				ShamanPower:UpdateCooldownBarOpacity()
			end
			-- Update Totemic Call on totem bar opacity if shown there
			if ShamanPower:CdItemOpt(2, "onTotemBar") then
				ShamanPower:UpdateTotemicCallOpacity()
			end
			-- Nothing counting down in seconds (all ready, or only long timers shown in
			-- minutes): once a second draws the bar the same. Anything that can change
			-- it (the events below, a setting) brings back 5 a second for a second.
			local sys = ShamanPower.updateSystem.subsystems.cooldownBar
			sys.interval = (ShamanPower._cdbarBusy or GetTime() < (ShamanPower._cdbarWakeUntil or 0)) and 0.2 or 1
		end)
	end
	if not self._cdbarWakeFrame then
		local f = CreateFrame("Frame")
		for _, ev in ipairs({ "SPELL_UPDATE_COOLDOWN", "PLAYER_TOTEM_UPDATE", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "BAG_UPDATE_DELAYED", "SPELLS_CHANGED" }) do
			pcall(f.RegisterEvent, f, ev)
		end
		pcall(f.RegisterUnitEvent, f, "UNIT_AURA", "player")               -- the shield
		pcall(f.RegisterUnitEvent, f, "UNIT_INVENTORY_CHANGED", "player")  -- imbues, a weapon swap
		f:SetScript("OnEvent", function() ShamanPower:WakeCooldownBar() end)
		local reg = LibStub and LibStub("AceConfigRegistry-3.0", true)
		if reg then reg.RegisterCallback(f, "ConfigTableChange", function() ShamanPower:WakeCooldownBar() end) end
		self._cdbarWakeFrame = f
	end
	-- Note: Enabled/disabled in UpdateCooldownBarVisibility
	self:ApplyClickSwap()
	self:ApplyShieldButtonClicks()   -- (both clients: ApplyClickSwap is WoW: Forever's only)
end

-- Something the cooldown bar shows may have changed: 5 passes a second again for
-- the next second (the change itself can land a moment after its event). Never
-- more than 5 a second, however many events arrive.
function ShamanPower:WakeCooldownBar()
	self._cdbarWakeUntil = GetTime() + 1
	local sys = self.updateSystem.subsystems.cooldownBar
	if sys then sys.interval = 0.2 end
end

-- Find a cooldown button by spell ID
function ShamanPower:GetCooldownButtonBySpellID(spellID)
	for _, btn in ipairs(self.cooldownButtons) do
		if btn.spellID == spellID then
			return btn
		end
	end
	return nil
end

-- Auto-clear an alert 10 seconds after the latest call: a newer call on the same
-- button bumps the counter, so an older timer then leaves it alone
local function armCooldownButtonAlertClear(btn, spellID)
	btn.alertSerial = (btn.alertSerial or 0) + 1
	local serial = btn.alertSerial
	C_Timer.After(10, function()
		if btn.alertSerial == serial then ShamanPower:RemoveCooldownButtonAlert(spellID) end
	end)
end

-- Add alert effect to a cooldown button (glow, shake, scale up)
function ShamanPower:AddCooldownButtonAlert(spellID)
	-- Check if button animation is enabled
	if self.opt.raidCDShowButtonAnimation == false then return end

	local btn = self:GetCooldownButtonBySpellID(spellID)
	if not btn then return end

	-- Already pulsing: a repeat call keeps it going for another 10 seconds
	if btn.alertActive then
		armCooldownButtonAlertClear(btn, spellID)
		return
	end
	btn.alertActive = true

	-- Create glow texture if it doesn't exist
	if not btn.glowTexture then
		local glow = btn:CreateTexture(nil, "OVERLAY")
		glow:SetPoint("TOPLEFT", -8, 8)
		glow:SetPoint("BOTTOMRIGHT", 8, -8)
		glow:SetTexture("Interface\\SpellActivationOverlay\\IconAlert")
		glow:SetTexCoord(0.00781250, 0.50781250, 0.27734375, 0.52734375)
		if ShamanPower.ShapeGlow then ShamanPower:ShapeGlow(glow, "alert") end   -- Glow Shape
		glow:SetBlendMode("ADD")
		glow:Hide()
		btn.glowTexture = glow
	end

	btn.glowTexture:Show()

	-- The pulse runs in the engine (AnimationGroups): no Lua per frame. Same
	-- shape as the old hand-driven pulse: the glow swings 0 -> 1 alpha about once
	-- a second (sin 6t), the icon swings 85% -> 115% size about every 1.6 s (sin 4t).
	-- The icon texture is scaled, not the button: the button is a secure frame,
	-- and resizing it during combat (when raid calls arrive) is blocked.
	if not btn.alertAnims and btn.glowTexture.CreateAnimationGroup then
		local function bounce(region)
			local ag = region:CreateAnimationGroup()
			ag:SetLooping("BOUNCE")
			return ag
		end
		local glowAG = bounce(btn.glowTexture)
		local ga = glowAG:CreateAnimation("Alpha")
		ga:SetFromAlpha(0); ga:SetToAlpha(1)
		ga:SetDuration(math.pi / 6)            -- half of the sin(6t) period
		ga:SetSmoothing("IN_OUT")
		local anims = { glowAG }
		if btn.icon and btn.icon.CreateAnimationGroup then
			local iconAG = bounce(btn.icon)
			local sa = iconAG:CreateAnimation("Scale")
			if sa.SetScaleFrom then sa:SetScaleFrom(0.85, 0.85); sa:SetScaleTo(1.15, 1.15)
			elseif sa.SetFromScale then sa:SetFromScale(0.85, 0.85); sa:SetToScale(1.15, 1.15) end
			sa:SetOrigin("CENTER", 0, 0)
			sa:SetDuration(math.pi / 4)        -- half of the sin(4t) period
			sa:SetSmoothing("IN_OUT")
			anims[#anims + 1] = iconAG
		end
		btn.alertAnims = anims
	end
	if btn.alertAnims then
		for _, ag in ipairs(btn.alertAnims) do ag:Play() end
	end

	armCooldownButtonAlertClear(btn, spellID)
end

-- Remove alert effect from a cooldown button
function ShamanPower:RemoveCooldownButtonAlert(spellID)
	local btn = self:GetCooldownButtonBySpellID(spellID)
	if not btn then return end

	btn.alertActive = false

	-- Hide glow
	if btn.glowTexture then
		btn.glowTexture:Hide()
	end

	-- Stop the pulse (the icon and glow go back to their own size and alpha)
	if btn.alertAnims then
		for _, ag in ipairs(btn.alertAnims) do ag:Stop() end
	end
end

-- Helper to get progress bar color based on time remaining (milliseconds)
local function GetTimerBarColor(expiration)
	local mins = expiration / 60000
	-- General > Themes (cd.timers): the theme's healthy / low / critical colours; nil = the ones below
	if ShamanPower:ThemeActive("cd.timers") then
		local r, g, b = ShamanPower:ThemeColor("cd.timers", (mins < 5 and "bad") or (mins < 10 and "low") or "good")
		if r then return r, g, b end
	end
	if mins < 5 then
		return 0.9, 0.2, 0.2  -- Red when critical
	elseif mins < 10 then
		return 0.9, 0.7, 0.2  -- Yellow/orange when low
	else
		return 0.2, 0.8, 0.2  -- Green when healthy
	end
end

-- Get progress bar color: spell color when healthy, yellow/red when low
-- spellID: only when the item uses Spell Color (its Progress Bar Color: ShamanPowerCdItems.lua), else nil
local function GetBarColor(expiration, spellID)
	local mins = expiration / 60000
	if spellID and mins >= 10 then
		local c = ShamanPower.SpellBarColors[spellID]
		if c then return c[1], c[2], c[3] end
	end
	return GetTimerBarColor(expiration)
end

-- Get imbue bar color: imbue color when healthy, yellow/red when low
local function GetImbueBarColor(expiration, imbueType)   -- (imbueType: only with Spell Color, as GetBarColor)
	local mins = expiration / 60000
	if imbueType and mins >= 10 then
		local c = ShamanPower.ImbueBarColors[imbueType]
		if c then return c[1], c[2], c[3] end
	end
	return GetTimerBarColor(expiration)
end

-- ----------------------------------------------------------------------------
-- Cooldown bar buttons of type "cooldown" on the Mainline family: the same
-- hand-off as the totem buttons. The engine draws the radial swipe or the
-- greyed-icon sweep, fills the progress bar and counts the time where the
-- addon's own text sits; the addon keeps the ready / dark state (from the
-- never-secret "is it running") and the bar's colour rule, from the shadow
-- remaining once a pass - a colour, never a number.
local function EngineProgressBar(btn)
	if not btn.engineBar then
		local bar = CreateFrame("StatusBar", nil, btn)
		ShamanPower:SetSPStatusBarTexture(bar, "cooldown", "Interface\\Buttons\\WHITE8x8")
		bar:SetFrameLevel(btn:GetFrameLevel() + 2)
		if bar.SetFillStyle then bar:SetFillStyle("STANDARD") end
		btn.engineBar = bar
	end
	return btn.engineBar
end

-- The engine's countdown string takes the place, font and colour of the
-- addon's text for the chosen location; none chosen, no numbers.
local function PlaceEngineBarText(self, btn, textLocation, showText)
	local cd = btn.cooldown
	local ok, fs = pcall(cd.GetCountdownFontString, cd)
	if not ok or not fs then return end
	local src
	if textLocation == "inside" then src = btn.insideText
	elseif textLocation == "outside" then src = btn.outsideText
	elseif textLocation == "icon" then src = btn.iconText
	elseif showText then src = btn.timeText end
	cd:SetHideCountdownNumbers(src == nil)
	if not src then return end
	local font, size, flags = src:GetFont()
	if font then fs:SetFont(font, size, flags) end
	local r, g, b = src:GetTextColor()
	fs:SetTextColor(r or 1, g or 1, b or 1)
	fs:ClearAllPoints()
	local point, rel, relPoint, x, y = src:GetPoint(1)
	if point then fs:SetPoint(point, rel or btn, relPoint or point, x or 0, y or 0) else fs:SetPoint("CENTER", btn, "CENTER", 0, 0) end
	pcall(cd.SetMinimumCountdownDuration, cd, 2000)
	pcall(cd.SetCountdownMillisecondsThreshold, cd, 10)
end

function ShamanPower:ClearEngineBarCooldown(btn)
	btn._ebSpell = nil
	btn._ebDur = nil   -- (Cooldown Almost Ready's exact moment: ShamanPowerCues.lua)
	self:DisarmEngineCooldownEnd(btn.cooldown)
	if btn.cooldown then btn.cooldown:Clear(); btn.cooldown:SetHideCountdownNumbers(true) end   -- back to none (see the button's creation)
	if btn.cdBar then btn.cdBar:Hide() end
	if btn.engineBar then btn.engineBar:Hide() end
end

-- Layout changed (bar side, sizes, text location): the next pass re-places
-- every engine display.
function ShamanPower:ResetEngineBarCooldowns()
	if not (self.cooldownButtons and self:EngineCooldownsOn()) then return end
	for i = 1, #self.cooldownButtons do self.cooldownButtons[i]._ebText = nil end
end

function ShamanPower:FeedEngineBarCooldown(btn, start, duration, showSweep, showBars, textLocation, showText, barPosition)
	btn.darkOverlay:Hide()
	btn.icon:SetDesaturated(false)
	if btn.ankhCountText then btn.ankhCountText:Hide() end
	local ct = btn.cooldownType   -- (the item's own sweep: ShamanPowerCdItems.lua)
	local sweepStyle = showSweep and self:CdItemOpt(ct, "sweep") or "none"
	local fromTop = self:SweepGrayFromTop(sweepStyle, self:CdItemOpt(ct, "sweepDirection"))
	-- ShamanPower Minimal's flat band (as on the totem bar, FeedEngineCooldown)
	local band = (self.ThemeMinimal and self:ThemeMinimal("cd.sweep")) and true or false
	local textKey = showText and (textLocation .. "+") or textLocation
	if btn._ebSpell ~= btn.spellID or btn._ebStale or btn._ebSweep ~= sweepStyle or btn._ebBars ~= showBars
		or btn._ebText ~= textKey or btn._ebPos ~= barPosition or btn._ebFromTop ~= fromTop or btn._ebBand ~= band then
		btn._ebStale = nil   -- a cooldown change since the last feed (RefreshEngineCooldowns)
		local ok, d = pcall(C_Spell.GetSpellCooldownDuration, btn.spellID, true)   -- true: not the global cooldown
		if not ok or d == nil then self:ClearEngineBarCooldown(btn) return end
		btn._ebSpell, btn._ebSweep, btn._ebBars, btn._ebText, btn._ebPos = btn.spellID, sweepStyle, showBars, textKey, barPosition
		btn._ebFromTop = fromTop
		btn._ebBand = band
		-- the duration object for Cooldown Almost Ready's exact moment, and its time text colored
		-- again after PlaceEngineBarText below (ShamanPowerCues.lua)
		btn._ebDur, btn._roEngTime = d, nil
		local cd = btn.cooldown
		local Dir = Enum and Enum.StatusBarTimerDirection or {}
		local Interp = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate
		-- the addon's own drawings of the same things
		if btn.greyOverlay then btn.greyOverlay:Hide() end
		if btn.progressBar then btn.progressBar:Hide() end
		if btn.timeText then btn.timeText:SetText("") end
		if btn.insideText then btn.insideText:Hide() end
		if btn.outsideText then btn.outsideText:Hide() end
		if btn.iconText then btn.iconText:Hide() end
		-- radial swipe, or the greyed icon on an engine-filled bar
		cd:SetDrawSwipe(sweepStyle == "radial")
		if sweepStyle == "greys" or sweepStyle == "fills" then
			local bar = self:TotemEngineSweepBar(btn, fromTop and not band)
			if bar then
				-- the gray copy grows with the time gone (Grays Out) or shrinks with the time left (Fills
				-- Back In); a colored fill (gray from the top) runs the other way
				local grayGrows = sweepStyle ~= "fills"
				local direction
				if band then
					bar:SetReverseFill(fromTop)   -- (Minimal's band: from the chosen edge, the timer as it reads)
					if grayGrows then direction = Dir.ElapsedTime else direction = Dir.RemainingTime end
				elseif grayGrows ~= fromTop then direction = Dir.ElapsedTime else direction = Dir.RemainingTime end
				local okb = pcall(bar.SetTimerDuration, bar, d, Interp, direction)
				bar:SetShown(okb and true or false)
			end
		elseif btn.cdBar then
			btn.cdBar:Hide()
		end
		-- progress bar: remaining time, filled from the bottom / left like the addon's
		if showBars and btn.bgBar then
			local bar = EngineProgressBar(btn)
			bar:ClearAllPoints()
			bar:SetAllPoints(btn.bgBar)
			local vertical = (barPosition == "left" or barPosition == "right" or barPosition == "top_vert" or barPosition == "bottom_vert" or barPosition == "on_icon")
			bar:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL")
			bar:SetReverseFill(false)
			local okb = pcall(bar.SetTimerDuration, bar, d, Interp, Dir.RemainingTime)
			bar:SetShown(okb and true or false)
			btn.bgBar:Show()
			btn._ebColorR = nil
		else
			if btn.engineBar then btn.engineBar:Hide() end
			if btn.bgBar then btn.bgBar:Hide() end
		end
		PlaceEngineBarText(self, btn, textLocation, showText)
		self:WatchEngineCooldownEnd(cd)
		pcall(cd.SetCooldownFromDurationObject, cd, d, true)
	end
	-- the bar's colour rule, from the shadow remaining (none for a cooldown only the
	-- game knows, after a reload mid-fight: the healthy color, never the critical red)
	if showBars and btn.engineBar and btn.engineBar:IsShown() then
		local left = math.huge
		if start and start > 0 then left = ((start + duration) - GetTime()) * 1000 end
		local r, g, b = GetBarColor(left, self:CdItemOpt(ct, "progressColor") and btn.spellID or nil)
		if r ~= btn._ebColorR or g ~= btn._ebColorG or b ~= btn._ebColorB then
			btn._ebColorR, btn._ebColorG, btn._ebColorB = r, g, b
			btn.engineBar:SetStatusBarColor(r, g, b, 0.9)
		end
	end
end

-- Update cooldown bar layout (horizontal or vertical)
function ShamanPower:UpdateCooldownBarLayout()
	if not self.cooldownBar then return end
	if #self.cooldownButtons == 0 then return end
	if InCombatLockdown() then return end

	-- Sort cooldownButtons by cooldownBarOrder
	local cooldownBarOrder = self:GetCooldownBarOrder()

	-- Create a lookup table for order position (cooldownType -> position)
	local orderLookup = {}
	for position, cooldownType in ipairs(cooldownBarOrder) do
		orderLookup[cooldownType] = position
	end

	-- Sort by order position
	table.sort(self.cooldownButtons, function(a, b)
		local orderA = orderLookup[a.cooldownType] or 99
		local orderB = orderLookup[b.cooldownType] or 99
		return orderA < orderB
	end)

	local bar = self.cooldownBar
	local buttonSize = bar.buttonSize or 22
	local spacing = self.opt.cooldownBarPadding or 2
	local padding = bar.padding or 4
	local cdLayout = self.opt.cdbarLayout or self.opt.layout
	local isVertical = (cdLayout == "Vertical" or cdLayout == "VerticalLeft")

	-- Count only visible buttons (not hidden in options and not popped out)
	local visibleButtons = {}
	for _, btn in ipairs(self.cooldownButtons) do
		local isPoppedOut = self:IsCooldownPoppedOut(btn.cooldownType)
		if not btn.isHiddenInOptions and not isPoppedOut then
			table.insert(visibleButtons, btn)
		end
	end
	local numButtons = #visibleButtons

	-- Extra padding for progress bars based on position
	-- Only reserve space when at least one is currently visible (Progress Bar is per item:
	-- an item with it off never shows one)
	local showBars = true
	if showBars then
		local anyBarVisible = false
		for _, btn in ipairs(self.cooldownButtons) do
			if btn.progressBar and btn.progressBar:IsShown() then
				anyBarVisible = true
				break
			end
		end
		showBars = anyBarVisible
	end
	local barPosition = self.opt.cdbarProgressPosition or "left"
	local progressBarSize = self.opt.cdbarProgressBarHeight or 3

	-- Calculate padding based on bar position (add extra room for imbue dual bars)
	local leftPadding, rightPadding = 0, 0
	local extraSpacing = 0  -- Additional spacing between buttons when bars stick out sideways
	if showBars then
		local hasImbueButton = self.weaponImbueButton ~= nil
		if barPosition == "left" then
			leftPadding = progressBarSize + 2
			if hasImbueButton then rightPadding = progressBarSize + 2 end
			extraSpacing = progressBarSize + 1
		elseif barPosition == "right" then
			rightPadding = progressBarSize + 2
			if hasImbueButton then leftPadding = progressBarSize + 2 end
			extraSpacing = progressBarSize + 1
		elseif barPosition == "on_icon" then
			-- Bars render ON the icon itself, no extra padding or spacing needed
		elseif barPosition == "top_vert" or barPosition == "bottom_vert" then
			leftPadding = progressBarSize + 2
			rightPadding = progressBarSize + 2
		end
	end
	local topPadding = (showBars and (barPosition == "top" or barPosition == "top_vert")) and (progressBarSize + 2) or 0
	local bottomPadding = (showBars and (barPosition == "bottom" or barPosition == "bottom_vert")) and (progressBarSize + 2) or 0
	-- Vertical bars on top/bottom need extra height for the bar length
	if showBars and barPosition == "top_vert" then topPadding = buttonSize + 2 end
	if showBars and barPosition == "bottom_vert" then bottomPadding = buttonSize + 2 end

	if isVertical then
		-- Vertical: stack buttons top to bottom
		local barHeight = (buttonSize * numButtons) + (spacing * math.max(numButtons - 1, 0)) + (padding * 2) + topPadding + bottomPadding
		local barWidth = buttonSize + (padding * 2) + leftPadding + rightPadding
		bar:SetSize(barWidth, barHeight)

		for i, btn in ipairs(visibleButtons) do
			btn:ClearAllPoints()
			local xOffset = (leftPadding - rightPadding) / 2
			btn:SetPoint("TOP", bar, "TOP", xOffset, -padding - topPadding - (i - 1) * (buttonSize + spacing))
			btn:Show()
		end

		-- Position drag handle at top of bar for vertical layout
		if self.cooldownBarDragHandle then
			self.cooldownBarDragHandle:ClearAllPoints()
			self.cooldownBarDragHandle:SetPoint("BOTTOM", bar, "TOP", 0, 2)
		end
	else
		-- Horizontal: buttons left to right
		local barWidth = (buttonSize * numButtons) + (spacing * math.max(numButtons - 1, 0)) + (extraSpacing * math.max(numButtons - 1, 0)) + (padding * 2) + leftPadding + rightPadding
		local barHeight = buttonSize + (padding * 2) + topPadding + bottomPadding
		bar:SetSize(barWidth, barHeight)

		for i, btn in ipairs(visibleButtons) do
			btn:ClearAllPoints()
			local yOffset = (bottomPadding - topPadding) / 2
			btn:SetPoint("LEFT", bar, "LEFT", padding + leftPadding + (i - 1) * (buttonSize + spacing + extraSpacing), yOffset)
			btn:Show()
		end

		-- Position drag handle at left of bar for horizontal layout
		if self.cooldownBarDragHandle then
			self.cooldownBarDragHandle:ClearAllPoints()
			self.cooldownBarDragHandle:SetPoint("RIGHT", bar, "LEFT", -2, 0)
		end
	end

	-- Update progress bar positions for all buttons
	self:UpdateCooldownBarProgressBars()
end

function ShamanPower:EngineCooldownStop(btn)
	if SPCompat and SPCompat.Trace then SPCompat.Trace("ENGINE CD stop %s", tostring(btn.spellID)) end
	btn._engineCDSpell = nil
	if btn.cooldown then
		pcall(btn.cooldown.SetCooldownFromDurationObject, btn.cooldown, nil)
		pcall(btn.cooldown.SetCooldown, btn.cooldown, 0, 0)
		btn.cooldown:Clear()
	end
	if btn._engineSweep then btn._engineSweep:Hide() end
	if btn._engineBar then btn._engineBar:Hide() end
end

-- Engine-drawn shield button for restricted clients. A shield can end early
-- (charges used up, cancelled, purged) with no event the addon can see in
-- combat, so while auras are secret an AuraContainer bound to the player
-- draws the whole shield state - icon, charge count, sweep, bar, text - as
-- regions of its own aura button, which the engine hides the instant the aura
-- is gone. Regions are created in the initializeFrame window (the only moment
-- the button subtree may be written) and styled to match the addon's own
-- rendering; out of combat the container stays hidden and the addon draws.
-- Spell IDs per shield, all ranks (Forever/TBC) plus the retail test-bed IDs.
ShamanPower.ShieldAuraSets = {
	{ name = "Lightning Shield", ids = { 324, 325, 905, 945, 8134, 10431, 10432, 25469, 25472, 192106 } },
	{ name = "Water Shield",     ids = { 24398, 33736, 52127, 408510, 408511, 409941 } },
}

function ShamanPower:ShieldIndexForAura(name, spellID)
	for index, set in ipairs(self.ShieldAuraSets) do
		if SPCompat.AuraMatches(name, spellID, set.ids) then return index end
	end
end

-- The colour the cooldown bar's shield count is drawn in for `charges` (the
-- addon's own text out of combat, the engine formatter in combat).
function ShamanPower:ShieldCountColor(charges, t)
	if not self:CdItemOpt(t, "colorCount") then return 1, 1, 1 end
	-- General > Themes (cd.count): the theme's green / yellow / red; nil = the ones below
	if self:ThemeActive("cd.count") then
		local r, g, b = self:ThemeColor("cd.count", (charges >= 3 and "high") or (charges == 2 and "mid") or "low")
		if r then return r, g, b end
	end
	if charges >= 3 then return 0, 1, 0 elseif charges == 2 then return 1, 1, 0 else return 1, 0, 0 end
end

function ShamanPower:ShieldCountFormatter(maxCharges, t)
	if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter) then return nil end
	local ok, fmt = pcall(C_StringUtil.CreateNumericRuleFormatter)
	if not ok or not fmt or not fmt.AddBreakpoint then return nil end
	for n = 0, maxCharges do
		local r, g, b = self:ShieldCountColor(n, t)
		pcall(fmt.AddBreakpoint, fmt, {
			threshold = n,
			format = ("|cff%02x%02x%02x%%d|r"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5)),
		})
	end
	return fmt
end

-- "Show Shield Charge Bar": a strip along the bottom of the shield button's
-- icon, one segment per charge, in the Shield Charges display's blue (it keeps
-- that color at every count: in combat the game fills it and cannot recolor
-- it). Three layers line up on it: the addon's strip (backing and fill, under
-- the engine's aura button), the engine's copy while auras are secret (hung on
-- the addon's strip, see EnsureShieldChargeContainer) and the dividers above
-- both, so the segments sit in the same place in and out of combat and follow
-- the button's size.
-- One top-level local for all of it: ShamanPower.lua's main chunk is close to Lua's
-- limit of 200 locals, so new file-level helpers go in tables like this one.
local ShieldStrip = { SEGMENTS = 3, COLOR = { 0.2, 0.6, 1.0 } }

-- noBacking: the engine's copy, laid exactly over the addon's strip, which already
-- draws the dark backing (two backings made empty segments darker in combat)
function ShieldStrip.Style(bar, noBacking)
	if not noBacking then
		local back = bar:CreateTexture(nil, "BACKGROUND")
		back:SetPoint("TOPLEFT", bar, "TOPLEFT", -1, 1)
		back:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 1, -1)
		back:SetColorTexture(0, 0, 0, 0.6)
	end
	ShamanPower:SetSPStatusBarTexture(bar, "shieldcharges", "Interface\\Buttons\\WHITE8x8")   -- Shield Charge Bars (Fonts & Textures)
	bar:SetStatusBarColor(ShieldStrip.COLOR[1], ShieldStrip.COLOR[2], ShieldStrip.COLOR[3])
	bar:SetMinMaxValues(0, ShieldStrip.SEGMENTS)
	bar:SetValue(0)
end

-- any Charge Bar Look / Orb Look / Orb Color / Show Empty Orbs change (Shield
-- Charges and General > Themes; the cooldown bar's strip always stays the bar)
function ShamanPower:ShieldLookChanged()
	if self.UpdateShieldChargeDisplays then self:UpdateShieldChargeDisplays() end
end

function ShamanPower:PaintShieldChargeStrip(btn, charges)
	local strip = btn.chargeStrip
	if not self:CdItemOpt(btn.cooldownType, "chargeBar") then
		if strip and strip:IsShown() then
			strip:Hide(); strip.lines:Hide()
			strip.lw = nil   -- laid out again (and the count raised again) when it comes back
			if btn.chargeText then
				btn.chargeText:ClearAllPoints()
				btn.chargeText:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
			end
		end
		return
	end
	if not strip then
		strip = CreateFrame("StatusBar", nil, btn)
		strip:SetFrameLevel(btn:GetFrameLevel() + 2)
		ShieldStrip.Style(strip)
		local lines = CreateFrame("Frame", nil, btn)
		lines:SetFrameLevel(btn:GetFrameLevel() + 12)   -- above the engine's aura button (container at +6)
		lines:SetAllPoints(strip)
		lines.d = {}
		for i = 1, ShieldStrip.SEGMENTS - 1 do
			local d = lines:CreateTexture(nil, "OVERLAY")
			d:SetColorTexture(0, 0, 0, 0.9)
			lines.d[i] = d
		end
		strip.lines = lines
		btn.chargeStrip = strip
	end
	-- geometry: the button's size, inside the on-icon duration bars
	local opt = self.opt
	local w, h = btn:GetWidth(), btn:GetHeight()
	local inset = 2
	if self:CdItemOpt(btn.cooldownType, "progressBar") and opt.cdbarProgressPosition == "on_icon" then
		inset = inset + (opt.cdbarProgressBarHeight or 3)
	end
	if strip.lw ~= w or strip.lh ~= h or strip.li ~= inset then
		strip.lw, strip.lh, strip.li = w, h, inset
		local sh = math.max(3, math.floor(h * 0.14 + 0.5))
		strip:ClearAllPoints()
		strip:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", inset, 2)
		strip:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -inset, 2)
		strip:SetHeight(sh)
		local sw = w - 2 * inset
		for i, d in ipairs(strip.lines.d) do
			d:ClearAllPoints()
			d:SetWidth(1)
			d:SetPoint("TOP", strip, "TOPLEFT", sw * i / ShieldStrip.SEGMENTS, 0)
			d:SetPoint("BOTTOM", strip, "BOTTOMLEFT", sw * i / ShieldStrip.SEGMENTS, 0)
		end
		-- the count sits just above the strip (the engine's count hangs on this one)
		if btn.chargeText then
			btn.chargeText:ClearAllPoints()
			btn.chargeText:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, sh + 3)
		end
	end
	local v = math.min(charges or 0, ShieldStrip.SEGMENTS)
	if strip.lv ~= v then strip.lv = v; strip:SetValue(v) end
	if not strip:IsShown() then strip:Show() end
	if not strip.lines:IsShown() then strip.lines:Show() end
end

function ShamanPower:EnsureShieldChargeContainer(btn)
	if not (SPCompat and SPCompat.secretsRegime) then return end
	if btn.chargeContainer then return end
	-- the engine's charge bar is hung on the addon's strip, so that exists first
	local ct = btn.cooldownType   -- (the shield item's own settings: ShamanPowerCdItems.lua)
	if self:CdItemOpt(ct, "chargeBar") and btn.chargeText then self:PaintShieldChargeStrip(btn, 0) end
	if C_AddOns and C_AddOns.LoadAddOn then pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer") end
	local ok, container = pcall(CreateFrame, "AuraContainer", nil, btn, "CustomAuraContainerTemplate")
	if not ok or not container then
		if SPCompat.Trace then SPCompat.Trace("SHIELD container create failed: %s", tostring(container)) end
		return
	end
	container:SetAllPoints(btn)
	container:SetFrameLevel(btn:GetFrameLevel() + 6)

	local opt = self.opt
	local sweepStyle = self:CdItemOpt(ct, "sweep")
	local showSweep = sweepStyle ~= "none"
	local sweepDir = self:CdItemOpt(ct, "sweepDirection")
	local showBars = self:CdItemOpt(ct, "progressBar")
	local chargeBar = self:CdItemOpt(ct, "chargeBar")
	local chargeCount = self:CdItemOpt(ct, "chargeCount")
	local barPosition = opt.cdbarProgressPosition or "left"
	local textLocation = opt.cdbarDurationTextLocation or "none"
	local Interp = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate
	local Dir = Enum and Enum.StatusBarTimerDirection or {}

	-- One slot per shield: the engine matches by spell ID (a MAP of id -> true;
	-- a list matches nothing) and each slot carries that shield's own icon file,
	-- so the icon and the greyed sweep copy never depend on the engine painting.
	local function buildSlot(set)
		local idMap = {}
		for _, id in ipairs(set.ids) do idMap[id] = true end
		local iconFile
		for _, id in ipairs(set.ids) do
			iconFile = (GetSpellTexture and GetSpellTexture(id)) or select(3, GetSpellInfo(id))
			if iconFile then break end
		end
		local slotKey = "shield_" .. set.name:gsub("%s", "")
		return pcall(function()
			container:AddAuraSlot(slotKey, "HELPFUL|PLAYER", {
				candidateFilters = { includeSpellIDs = idMap },
				initializeFrame = function(button)
					local T = SPCompat and SPCompat.Trace or function() end
					local function reg(label, ok, err) T("SHIELD init %s %s: %s%s", set.name, label, tostring(ok), ok and "" or (" " .. tostring(err))) end
					button:ClearAllPoints()
					button:SetAllPoints(btn)
					if button.SetMouseClickEnabled then pcall(button.SetMouseClickEnabled, button, false) end
					if button.SetMouseMotionEnabled then pcall(button.SetMouseMotionEnabled, button, false) end

					-- icon: this shield's own file (SetIcon registered too, in case the engine paints)
					local icon = button:CreateTexture(nil, "ARTWORK")
					icon:SetAllPoints(button)
					icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
					if iconFile then icon:SetTexture(iconFile) end
					reg("SetIcon", pcall(button.SetIcon, button, icon))
					-- Cooldown Bar Icon Shape: this game-drawn button sits over the addon's own
					if ShamanPower.ShapeIconTexture then ShamanPower:ShapeIconTexture(icon, icon, "cooldown") end

					-- duration source: the cooldown widget (swipe drawn only for the radial style)
					local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
					cd:SetAllPoints(button)
					cd:SetDrawEdge(false)
					cd:SetDrawBling(false)
					cd:SetHideCountdownNumbers(true)
					cd:SetDrawSwipe(showSweep and sweepStyle == "radial")
					if ShamanPower.ShapeCooldown then ShamanPower:ShapeCooldown(cd, "cooldown") end   -- Icon Shape: the swipe too
					reg("SetDurationCooldown", pcall(button.SetDurationCooldown, button, cd))

					-- vertical sweep: a copy of this shield's icon on a StatusBar the engine fills,
					-- oversized in a clip so the untrimmed texture lines up with the trimmed icon. The
					-- bar ALWAYS fills from the bottom: one filled from its top edge is stretched by the
					-- game instead of cropped (a squashed second icon with hard edges, in fights only,
					-- 2026-10-05; the totem bar had the same, see TotemEngineSweepBar). Gray from the top
					-- is the colored copy filling over a gray one, with the timer turned round.
					if showSweep and sweepStyle ~= "radial" and iconFile and (Dir.ElapsedTime or Dir.RemainingTime) then
						local clip = CreateFrame("Frame", nil, button)
						clip:SetAllPoints(button)
						clip:SetClipsChildren(true)
						local sb = CreateFrame("StatusBar", nil, clip)
						local margin = (0.08 / 0.84) * btn:GetWidth()
						sb:SetPoint("TOPLEFT", clip, "TOPLEFT", -margin, margin)
						sb:SetPoint("BOTTOMRIGHT", clip, "BOTTOMRIGHT", margin, -margin)
						sb:SetOrientation("VERTICAL")
						sb:SetReverseFill(false)
						local fillStyle = Enum and Enum.StatusBarFillStyle and Enum.StatusBarFillStyle.Standard
						if sb.SetFillStyle then sb:SetFillStyle(fillStyle or "STANDARD") end   -- cropped to the fill, never stretched
						local grayTop = ShamanPower:SweepGrayFromTop(sweepStyle, sweepDir)
						if grayTop then
							-- the gray copy under the colored fill
							local gray = sb:CreateTexture(nil, "BACKGROUND")
							gray:SetAllPoints(sb)
							gray:SetTexture(iconFile)
							gray:SetDesaturated(true)
							gray:SetVertexColor(0.5, 0.5, 0.5)
							if ShamanPower.ShapeIconTexture then ShamanPower:ShapeIconTexture(gray, icon, "cooldown") end   -- Icon Shape
						end
						sb:SetStatusBarTexture(iconFile)
						if sb.SetStatusBarDesaturated then sb:SetStatusBarDesaturated(not grayTop) end
						if grayTop then sb:SetStatusBarColor(1, 1, 1, 1) else sb:SetStatusBarColor(0.5, 0.5, 0.5, 1) end
						local sbt = sb:GetStatusBarTexture()
						if sbt then
							sbt:SetDesaturated(not grayTop)
							if grayTop then sbt:SetVertexColor(1, 1, 1) else sbt:SetVertexColor(0.5, 0.5, 0.5) end
						end
						if sbt and ShamanPower.ShapeIconTexture then ShamanPower:ShapeIconTexture(sbt, icon, "cooldown") end   -- Icon Shape
						-- the gray grows with the time gone (Grays Out) or shrinks with the time left (Fills
						-- Back In); a colored fill (gray from the top) runs the other way
						local grayGrows = sweepStyle ~= "fills"
						local direction
						if grayGrows ~= grayTop then direction = Dir.ElapsedTime else direction = Dir.RemainingTime end
						reg("SetDurationBar(sweep)", pcall(button.SetDurationBar, button, sb, { interpolation = Interp, direction = direction }))
					end

					-- charge count: same font and corner as the addon's own text. The engine
					-- draws the secret count and applies a NumericRuleFormatter we hand it:
					-- one breakpoint per count, coloured by the same rule as the addon's own
					-- text (green / yellow / red with "Color Shield Charges by Count", white
					-- without). That is also what draws a count of 1, which the client hides
					-- by default. (The Shield Charges module got this first; this button had
					-- kept a fixed blue and an empty options table.)
					local carrier = CreateFrame("Frame", nil, button)
					carrier:SetAllPoints(button)
					-- the count and the time on a frame of their own, over the button's effects (its cue
					-- frame, +14, and its parts up to +17): a running-out look over the game's icon keeps
					-- them sharp on top
					local texts = CreateFrame("Frame", nil, button)
					texts:SetAllPoints(button)
					texts:SetFrameLevel(btn:GetFrameLevel() + 18)   -- (over the cue frame's own parts too)
					local count = texts:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
					ShamanPower:AdoptSPFont(count, "charges")   -- template font = the design; follows the Fonts settings
					ShamanPower:SPFontGameOwned(count)   -- (on the game's button: a font change waits out fights and hidden auras)
					local strip = chargeBar and btn.chargeStrip
					if strip and btn.chargeText then
						-- hung on the addon's count, which sits above the strip
						count:SetPoint("BOTTOMRIGHT", btn.chargeText, "BOTTOMRIGHT", 0, 0)
					else
						count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
					end
					count:SetTextColor(1, 1, 1)

					-- charge bar: the engine fills a copy laid over the addon's strip (the
					-- dividers ride above both, see PaintShieldChargeStrip)
					if strip then
						local cb = CreateFrame("StatusBar", nil, carrier)
						cb:SetAllPoints(strip)
						ShieldStrip.Style(cb, true)
						reg("SetApplicationBar", pcall(button.SetApplicationBar, button, cb,
							{ maxApplications = ShieldStrip.SEGMENTS, minApplications = 0, interpolation = Interp }))
					end
					-- "Show Shield Charge Count" off: the engine is never handed the count
					if chargeCount then
						reg("SetApplicationCount", pcall(button.SetApplicationCount, button, count, { formatter = self:ShieldCountFormatter(3, ct) }))
					end

					-- progress bar in the addon's bar slot: black background + engine-filled bar
					if showBars and btn.bgBar and Dir.RemainingTime then
						local bg = carrier:CreateTexture(nil, "BACKGROUND")
						bg:SetAllPoints(btn.bgBar)
						bg:SetColorTexture(0, 0, 0, 0.7)
						local bar = CreateFrame("StatusBar", nil, carrier)
						bar:SetAllPoints(btn.bgBar)
						ShamanPower:SetSPStatusBarTexture(bar, "cooldown", "Interface\\Buttons\\WHITE8x8")
						local bt = bar:GetStatusBarTexture()
						if bt then bt:SetVertexColor(0.2, 0.8, 0.2, 0.9) end
						-- General > Themes (cd.engine, WoW: Forever): the theme's green, set here when built
						if bt and SPCompat.FOREVER then
							local er, eg, eb = ShamanPower:ThemeColor("cd.engine", "bar")
							if er then bt:SetVertexColor(er, eg, eb, 0.9) end
						end
						local vertical = (barPosition == "left" or barPosition == "right" or barPosition == "top_vert" or barPosition == "bottom_vert" or barPosition == "on_icon")
						bar:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL")
						reg("SetDurationBar(bar)", pcall(button.SetDurationBar, button, bar, { interpolation = Interp, direction = Dir.RemainingTime }))
					end

					-- duration text where the addon puts it
					local src = (textLocation == "inside" and btn.insideText) or (textLocation == "outside" and btn.outsideText)
						or (textLocation == "icon" and btn.iconText)
					if src then
						local fs = texts:CreateFontString(nil, "OVERLAY")
						self:CopySPFont(fs, src)   -- same font as the addon's text, and follows later font changes
						self:SPFontGameOwned(fs)
						local r, g, b = src:GetTextColor()
						fs:SetTextColor(r or 1, g or 1, b or 1)
						-- hung on the addon's text by the same point, not a copy of its anchor:
						-- when that text steps out past the flyout tab (FollowFlyoutArrows, at
						-- the start and end of a fight) this one goes with it, no rebuild
						-- The point is the one UpdateCooldownBarProgressBars gives that text, taken
						-- from the options: the first build (CreateCooldownBar) runs before the text
						-- is placed, and initializeFrame runs only once per slot, so reading it back
						-- here pinned the engine's number to the icon's centre after every reload.
						local point = "CENTER"   -- inside (bar centre), on the icon (button centre)
						if textLocation == "outside" then
							if barPosition == "bottom" or barPosition == "bottom_vert" then point = "TOP"
							elseif barPosition == "top" or barPosition == "top_vert" then point = "BOTTOM"
							elseif barPosition == "right" then point = "LEFT"
							else point = "RIGHT" end   -- left, on_icon
						end
						fs:SetPoint(point, src, point, 0, 0)
						-- Time Turns Red While Running Out (Cooldown Bar > Effects): the game colors its own time
						local topts = self.ShieldTimeTextOptions and self:ShieldTimeTextOptions()
						if topts and pcall(button.SetDurationText, button, fs, topts) then
							reg("SetDurationText(colored)", true)
						else
							reg("SetDurationText", pcall(button.SetDurationText, button, fs, {}))
						end
					end
					T("SHIELD init end %s", set.name)
				end,
			})
		end)
	end
	local failed = false
	for _, set in ipairs(self.ShieldAuraSets) do
		local okAdd, err = buildSlot(set)
		if not okAdd then
			failed = true
			if SPCompat.Trace then SPCompat.Trace("SHIELD AddAuraSlot %s failed: %s", set.name, tostring(err)) end
		end
	end
	if not pcall(container.SetUnit, container, "player") then failed = true end
	pcall(container.UpdateAllAuras, container)
	container:Hide()   -- shown only while auras are secret
	btn.chargeContainer = container
	-- what its time text is built with (Time Turns Red While Running Out: ShamanPowerCues.lua)
	btn.spTimeKey = self.ShieldTimeTextKey and self:ShieldTimeTextKey() or 0
	-- a shield slot that did not register: kept (it draws what it can), built again
	-- after the next fight (OnCombatEnd), a few times at most
	btn.chargeContainerFailed = failed or nil
	if SPCompat.Trace then SPCompat.Trace("SHIELD container ready on %s (sweep=%s bars=%s text=%s)", tostring(btn:GetName()), tostring(sweepStyle), tostring(showBars), tostring(textLocation)) end
end

-- Display options changed (sweep, bar, count, time text and its color, a theme, a profile): those are
-- baked in at creation, so build a fresh container (out of combat only). The shield on the button is not
-- one of them: there is a slot for every shield, each with its own icon, count and time.
function ShamanPower:RebuildShieldChargeContainer()
	local btn = self.shieldButton
	if not btn then return end
	-- asked for in a fight (a setting, a profile): after it (OnCombatEnd)
	if InCombatLockdown() then self._shieldContainerRebuildPending = true return end
	self._shieldContainerRebuildPending = nil
	if btn.chargeContainer then
		btn.chargeContainer:Hide()
		pcall(btn.chargeContainer.SetUnit, btn.chargeContainer, "none")   -- the old one stops following auras
		btn.chargeContainer = nil
	end
	self:EnsureShieldChargeContainer(btn)
end

local imbueCtx = {}

-- Shared helpers keep the imbue update free of per-tick closures.
local function PositionDualImbueBars(ctx, bgMain, bgOff, insideMain, insideOff, outsideMain, outsideOff)
	local hasMain, hasOff = ctx.hasMain, ctx.hasOff
	local buttonWidth, buttonHeight, barHeight = ctx.buttonWidth, ctx.buttonHeight, ctx.barHeight
	local barPosition, btn = ctx.barPosition, ctx.btn
	local both = hasMain and hasOff
	-- out past the flyout tab on its side while it shows (see FollowFlyoutArrows)
	local aT, aB, aL, aR = ShamanPower:FlyoutArrowPads(btn)

	if not hasMain and not hasOff then
		if bgMain then bgMain:Hide() end
		if bgOff then bgOff:Hide() end
		return
	end

	if barPosition == "bottom" then
		if both then
			bgMain:SetSize(buttonWidth / 2, barHeight)
			bgMain:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -(1 + aB))
			bgOff:SetSize(buttonWidth / 2, barHeight)
			bgOff:SetPoint("TOPLEFT", btn, "BOTTOM", 0, -(1 + aB))
		else
			bgMain:SetSize(buttonWidth, barHeight)
			bgMain:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -(1 + aB))
			if bgOff then bgOff:Hide() end
		end
	elseif barPosition == "top" then
		if both then
			bgMain:SetSize(buttonWidth / 2, barHeight)
			bgMain:SetPoint("BOTTOMLEFT", btn, "TOPLEFT", 0, 1 + aT)
			bgOff:SetSize(buttonWidth / 2, barHeight)
			bgOff:SetPoint("BOTTOMLEFT", btn, "TOP", 0, 1 + aT)
		else
			bgMain:SetSize(buttonWidth, barHeight)
			bgMain:SetPoint("BOTTOMLEFT", btn, "TOPLEFT", 0, 1 + aT)
			if bgOff then bgOff:Hide() end
		end
	elseif barPosition == "top_vert" then
		if both then
			bgMain:SetSize(barHeight, buttonHeight)
			bgMain:SetPoint("BOTTOMRIGHT", btn, "TOP", -1, 1 + aT)
			bgOff:SetSize(barHeight, buttonHeight)
			bgOff:SetPoint("BOTTOMLEFT", btn, "TOP", 1, 1 + aT)
		else
			bgMain:SetSize(barHeight, buttonHeight)
			bgMain:SetPoint("BOTTOM", btn, "TOP", 0, 1 + aT)
			if bgOff then bgOff:Hide() end
		end
	elseif barPosition == "bottom_vert" then
		if both then
			bgMain:SetSize(barHeight, buttonHeight)
			bgMain:SetPoint("TOPRIGHT", btn, "BOTTOM", -1, -(1 + aB))
			bgOff:SetSize(barHeight, buttonHeight)
			bgOff:SetPoint("TOPLEFT", btn, "BOTTOM", 1, -(1 + aB))
		else
			bgMain:SetSize(barHeight, buttonHeight)
			bgMain:SetPoint("TOP", btn, "BOTTOM", 0, -(1 + aB))
			if bgOff then bgOff:Hide() end
		end
	elseif barPosition == "on_icon" then
		if both then
			bgMain:SetSize(barHeight, buttonHeight)
			bgMain:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
			bgOff:SetSize(barHeight, buttonHeight)
			bgOff:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, 0)
		else
			bgMain:SetSize(barHeight, buttonHeight)
			bgMain:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
			if bgOff then bgOff:Hide() end
		end
	elseif barPosition == "left" then
		if both then
			bgMain:SetSize(barHeight, buttonHeight)
			bgMain:SetPoint("TOPRIGHT", btn, "TOPLEFT", -(1 + aL), 0)
			bgOff:SetSize(barHeight, buttonHeight)
			bgOff:SetPoint("TOPLEFT", btn, "TOPRIGHT", 1 + aR, 0)
		else
			bgMain:SetSize(barHeight, buttonHeight)
			bgMain:SetPoint("TOPRIGHT", btn, "TOPLEFT", -(1 + aL), 0)
			if bgOff then bgOff:Hide() end
		end
	elseif barPosition == "right" then
		if both then
			bgMain:SetSize(barHeight, buttonHeight)
			bgMain:SetPoint("TOPLEFT", btn, "TOPRIGHT", 1 + aR, 0)
			bgOff:SetSize(barHeight, buttonHeight)
			bgOff:SetPoint("TOPLEFT", bgMain, "TOPRIGHT", 1, 0)
		else
			bgMain:SetSize(barHeight, buttonHeight)
			bgMain:SetPoint("TOPLEFT", btn, "TOPRIGHT", 1 + aR, 0)
			if bgOff then bgOff:Hide() end
		end
	end

	if insideMain then
		insideMain:ClearAllPoints()
		insideMain:SetPoint("CENTER", bgMain, "CENTER", 0, 0)
		local fontSize = ShamanPower.opt.cdbarDurationTextSize or 8
		ShamanPower:SetSPFont(insideMain, "timers", fontSize, "OUTLINE")
	end
	if insideOff then
		if both then
			insideOff:ClearAllPoints()
			insideOff:SetPoint("CENTER", bgOff, "CENTER", 0, 0)
			local fontSize = ShamanPower.opt.cdbarDurationTextSize or 8
			ShamanPower:SetSPFont(insideOff, "timers", fontSize, "OUTLINE")
		else
			insideOff:Hide()
		end
	end

	if outsideMain then
		outsideMain:ClearAllPoints()
		if barPosition == "bottom" then
			outsideMain:SetPoint("TOP", bgMain, "BOTTOM", both and -2 or 0, -1)
		elseif barPosition == "top" then
			outsideMain:SetPoint("BOTTOM", bgMain, "TOP", both and -2 or 0, 1)
		elseif barPosition == "top_vert" then
			outsideMain:SetPoint("BOTTOM", bgMain, "TOP", 0, 1)
		elseif barPosition == "bottom_vert" then
			outsideMain:SetPoint("TOP", bgMain, "BOTTOM", 0, -1)
		else
			outsideMain:SetPoint("RIGHT", bgMain, "LEFT", -1 - (barPosition == "on_icon" and aL or 0), 0)
		end
	end
	if outsideOff then
		if both then
			outsideOff:ClearAllPoints()
			if barPosition == "bottom" then
				outsideOff:SetPoint("TOP", bgOff, "BOTTOM", 2, -1)
			elseif barPosition == "top" then
				outsideOff:SetPoint("BOTTOM", bgOff, "TOP", 2, 1)
			elseif barPosition == "top_vert" then
				outsideOff:SetPoint("BOTTOM", bgOff, "TOP", 0, 1)
			elseif barPosition == "bottom_vert" then
				outsideOff:SetPoint("TOP", bgOff, "BOTTOM", 0, -1)
			else
				outsideOff:SetPoint("LEFT", bgOff, "RIGHT", 1 + (barPosition == "on_icon" and aR or 0), 0)
			end
		else
			outsideOff:Hide()
		end
	end
end

local function UpdateImbueHand(ctx, hasHand, expMS, imbueType, bg, bar, grey, inside, outside,
	iconTextField, alignLeft)
	local maxDuration, buttonWidth, buttonHeight = ctx.maxDuration, ctx.buttonWidth, ctx.buttonHeight
	local barHeight, isVerticalBar, showSweep = ctx.barHeight, ctx.isVerticalBar, ctx.showSweep
	local self, btn = ctx.self, ctx.btn
	local textLocation, showText = ctx.textLocation, ctx.showText
	if not (hasHand and bar and bg) then
		if bar then bar:Hide() end
		if bg then bg:Hide() end
		if grey then grey:Hide() end
		if inside then inside:Hide() end
		if outside then outside:Hide() end
		if iconTextField then iconTextField:Hide() end
		return
	end

	local percent = math.min(expMS / maxDuration, 1)
	local r, g, b = GetImbueBarColor(expMS, ctx.spellColors and imbueType or nil)

	if ctx.showBars then
	bg:Show()
	bar:ClearAllPoints()

	if isVerticalBar then
		local progressHeight = math.max(buttonHeight * percent, 1)
		bar:SetSize(barHeight, progressHeight)
		if alignLeft then
			bar:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", 0, 0)
		else
			bar:SetPoint("BOTTOMLEFT", bg, "BOTTOMLEFT", 0, 0)
		end
	else
		local progressWidth = math.max((buttonWidth / 2) * percent, 1)
		bar:SetSize(progressWidth, barHeight)
		bar:SetPoint("LEFT", bg, "LEFT", 0, 0)
	end

	ShamanPower:SetSPBarColor(bar, "cooldown", r, g, b, 0.9)
	bar:Show()
	else
		-- the imbue item's own Progress Bar off (it always showed them before per-item settings)
		bar:Hide()
		bg:Hide()
	end

	if showSweep and grey then
		-- "fills": grey recedes instead of growing.
		local depletedPercent = (ctx.sweepStyle == "fills") and percent or (1 - percent)
		local fromTop = ctx.sweepTop
		if btn.icon2:IsShown() then
			self:PaintVerticalSweep(grey, btn, depletedPercent, buttonHeight, fromTop,
				alignLeft and 0.08 or 0.50, alignLeft and 0.50 or 0.92, buttonWidth / 2, alignLeft and "left" or "right")
		else
			self:PaintVerticalSweep(grey, btn, depletedPercent, buttonHeight, fromTop, 0.08, 0.92)
		end
	elseif grey then
		grey:Hide()
	end

	local durationStr = FormatDuration(expMS / 1000)
	if inside then
		inside:SetText(durationStr)
	end
	if outside then
		outside:SetText(durationStr)
	end
	if iconTextField then
		iconTextField:SetText(durationStr)
	end

	if textLocation == "inside" then
		if inside then inside:Show() end
		if outside then outside:Hide() end
		if iconTextField then iconTextField:Hide() end
		if btn.timeText then btn.timeText:SetText("") end
	elseif textLocation == "outside" then
		if outside then outside:Show() end
		if inside then inside:Hide() end
		if iconTextField then iconTextField:Hide() end
		if btn.timeText then btn.timeText:SetText("") end
	elseif textLocation == "icon" then
		if iconTextField then iconTextField:Show() end
		if inside then inside:Hide() end
		if outside then outside:Hide() end
		if btn.timeText then btn.timeText:SetText("") end
	elseif textLocation == "none" and showText then
		if btn.timeText then btn.timeText:SetText(durationStr) end
		if inside then inside:Hide() end
		if outside then outside:Hide() end
		if iconTextField then iconTextField:Hide() end
	else
		if btn.timeText then btn.timeText:SetText("") end
		if inside then inside:Hide() end
		if outside then outside:Hide() end
		if iconTextField then iconTextField:Hide() end
	end
end

function ShamanPower:UpdateCooldownButtons()
	-- Get display options (the per-item ones in the loop: ShamanPowerCdItems.lua)
	local barPosition = self.opt.cdbarProgressPosition or "left"
	local barHeight = self.opt.cdbarProgressBarHeight or 3
	local textLocation = self.opt.cdbarDurationTextLocation or "none"
	local isVerticalBar = (barPosition == "left" or barPosition == "right" or barPosition == "top_vert" or barPosition == "bottom_vert" or barPosition == "on_icon")
	local engine = self:EngineCooldownsOn()   -- the engine draws and counts the cooldown buttons; this pass hands it changes
	-- busy: something here counts down in seconds, or a cue is due soon. Otherwise
	-- (all ready, or only long timers shown in minutes) the next pass can wait a
	-- second: see the cooldownBar subsystem and WakeCooldownBar.
	local busy = false

	-- Use numeric for loop instead of ipairs to avoid iterator garbage
	for i = 1, #self.cooldownButtons do
		local btn = self.cooldownButtons[i]
		local buttonHeight = btn:GetHeight()
		local buttonWidth = btn:GetWidth()
		-- this item's own settings, else the bar's shared ones (no allocation)
		local ct = btn.cooldownType
		local showBars = self:CdItemOpt(ct, "progressBar")
		local sweepStyle = self:CdItemOpt(ct, "sweep")
		local showSweep = sweepStyle ~= "none"
		local sweepTop = self:SweepGrayFromTop(sweepStyle, self:CdItemOpt(ct, "sweepDirection"))
		local showText = self:CdItemOpt(ct, "timeOnIcon")
		local spellColors = self:CdItemOpt(ct, "progressColor")

		if btn.spellType == "shield" then
			-- Use cached shield state from UNIT_AURA event (no UnitBuff calls here!)
			local cache = self.shieldCache
			if btn.chargeContainer then
				local restricted = totemsSecretNow()
				if restricted ~= btn.chargeContainer:IsShown() then btn.chargeContainer:SetShown(restricted) end
			end
			local hasShield = false
			local activeShieldID = nil
			local activeShieldIcon = nil
			local shieldDuration = 0
			local shieldExpiration = 0
			local shieldCharges = 0

			if not cache then
				-- No cache yet, do initial scan
				self:ScanPlayerShield()
				cache = self.shieldCache
			end

			if cache and cache.hasShield then
				-- Use fully cached values - no UnitBuff calls needed!
				-- Duration/charges are updated by UNIT_AURA event when shield procs
				hasShield = true
				activeShieldID = cache.shieldID
				activeShieldIcon = cache.shieldIcon
				shieldCharges = cache.shieldCharges
				shieldDuration = cache.shieldDuration
				shieldExpiration = cache.shieldExpiration
			end
			-- If cache exists and hasShield is false, we know there's no shield - no scanning needed!

			-- the style (the totem bar's, or the cooldown bar's own): the shield the button shows, whether
			-- it counts as up, the one shown above it, the one in its corner (CooldownBarShieldView)
			local viewIdx, viewUp, aboveIdx, cornerIdx = self:CooldownBarShieldView(hasShield and self:ShieldIndexOf(activeShieldID) or nil)
			local aboveCharges = aboveIdx and shieldCharges or 0
			local shieldUp = hasShield   -- (running out: the shield really up, whichever the style shows)
			hasShield = viewUp

			if hasShield then
				btn.darkOverlay:Hide()
				btn.icon:SetDesaturated(false)
				-- the icon is the shield the style shows (Normal: the assigned one, lit only while it is up)
				local shownIcon = self:ShieldIcon(viewIdx) or activeShieldIcon
				if shownIcon then
					btn.icon:SetTexture(shownIcon)
					if btn.greyOverlay then
						btn.greyOverlay:SetTexture(shownIcon)
					end
				end
				btn.activeShieldID = activeShieldID

				-- Calculate remaining time
				local remaining = shieldExpiration - GetTime()
				local maxDuration = shieldDuration > 0 and shieldDuration or 600  -- Default 10 min
				-- its time left in text, in seconds (under 10 minutes it reads 9:59)
				if shieldDuration > 0 and remaining < 601 and (textLocation == "inside" or textLocation == "outside" or textLocation == "icon") then busy = true end

				-- Show charge count with optional coloring
				if btn.chargeText then
					if shieldCharges > 0 and self:CdItemOpt(ct, "chargeCount") then
						btn.chargeText:SetText((cache and cache.engineCount) and "" or (NumberStrings[shieldCharges] or tostring(shieldCharges)))
						btn.chargeText:SetTextColor(self:ShieldCountColor(shieldCharges, ct))   -- same rule the engine formatter uses in combat
					else
						btn.chargeText:SetText("")
					end
				end
				self:PaintShieldChargeStrip(btn, (cache and cache.engineCount) and 0 or shieldCharges)
				if self.CueShieldState then self:CueShieldState(btn, true, false) end   -- "Shield Gone" effect

				-- Progress bar (for shields, show based on time remaining)
				local isVerticalBar = (barPosition == "left" or barPosition == "right" or barPosition == "top_vert" or barPosition == "bottom_vert" or barPosition == "on_icon")
				if showBars and btn.progressBar and shieldDuration > 0 then
					local percent = math.min(remaining / maxDuration, 1)
					local r, g, b = GetBarColor(remaining * 1000, spellColors and activeShieldID or nil)

					if btn.bgBar then btn.bgBar:Show() end
					btn.progressBar:ClearAllPoints()   -- on its background, which steps out past a flyout tab

					if isVerticalBar then
						-- Vertical bar
						local progressHeight = math.max(buttonHeight * percent, 1)
						btn.progressBar:SetSize(barHeight, progressHeight)
						if barPosition == "on_icon" then
							btn.progressBar:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
						elseif barPosition == "left" then
							btn.progressBar:SetPoint("BOTTOMRIGHT", btn.bgBar, "BOTTOMRIGHT", 0, 0)
						elseif barPosition == "right" then
							btn.progressBar:SetPoint("BOTTOMLEFT", btn.bgBar, "BOTTOMLEFT", 0, 0)
						elseif barPosition == "top_vert" then
							btn.progressBar:SetPoint("BOTTOM", btn.bgBar, "BOTTOM", 0, 0)
						elseif barPosition == "bottom_vert" then
							btn.progressBar:SetPoint("BOTTOM", btn.bgBar, "BOTTOM", 0, 0)
						end
					else
						-- Horizontal bar (top/bottom)
						local progressWidth = math.max(buttonWidth * percent, 1)
						btn.progressBar:SetSize(progressWidth, barHeight)
						if barPosition == "bottom" then
							btn.progressBar:SetPoint("TOPLEFT", btn.bgBar, "TOPLEFT", 0, 0)
						else
							btn.progressBar:SetPoint("BOTTOMLEFT", btn.bgBar, "BOTTOMLEFT", 0, 0)
						end
					end
					ShamanPower:SetSPBarColor(btn.progressBar, "cooldown", r, g, b, 0.9)
					btn.progressBar:Show()
				else
					if btn.progressBar then btn.progressBar:Hide() end
					if btn.bgBar then btn.bgBar:Hide() end
				end

				-- Grey sweep overlay
				if showSweep and sweepStyle == "radial" and shieldDuration > 0 then
					if btn.greyOverlay then btn.greyOverlay:Hide() end
					btn.cooldown:SetCooldown(shieldExpiration - maxDuration, maxDuration)
				elseif showSweep and btn.greyOverlay and shieldDuration > 0 then
					local percent = math.min(remaining / maxDuration, 1)
					local depletedPercent = (sweepStyle == "fills") and percent or (1 - percent)   -- "fills": grey recedes instead of growing
					self:PaintVerticalSweep(btn.greyOverlay, btn, depletedPercent, buttonHeight, sweepTop, 0.08, 0.92)
				elseif btn.greyOverlay then
					btn.greyOverlay:Hide()
				end

				-- Duration text handling for shields
				local durationStr = nil
				if shieldDuration > 0 then
					durationStr = FormatDuration(remaining)
				end

				-- Hide all duration texts first
				if btn.timeText then btn.timeText:SetText("") end
				if btn.insideText then btn.insideText:Hide() end
				if btn.outsideText then btn.outsideText:Hide() end
				if btn.belowText and btn.belowText ~= btn.outsideText then btn.belowText:Hide() end
				if btn.iconText then btn.iconText:Hide() end

				-- Show duration text at chosen location
				if durationStr then
					if textLocation == "inside" then
						if btn.insideText then
							btn.insideText:SetText(durationStr)
							btn.insideText:Show()
						end
					elseif textLocation == "outside" then
						if btn.outsideText then
							btn.outsideText:SetText(durationStr)
							btn.outsideText:Show()
						end
					elseif textLocation == "icon" then
						if btn.iconText then
							btn.iconText:SetText(durationStr)
							btn.iconText:Show()
						end
					end
				end
			else
				btn.darkOverlay:Show()
				btn.icon:SetDesaturated(true)
				btn.activeShieldID = nil
				-- not up: the shield the style shows, grayed (Normal: the assigned one)
				local restIcon = self:ShieldIcon(viewIdx)
				if restIcon then btn.icon:SetTexture(restIcon) end
				btn.cooldown:Clear()
				if btn.chargeText then btn.chargeText:SetText("") end
				self:PaintShieldChargeStrip(btn, 0)   -- empty strip: no shield (in combat, under the engine's)
				if self.CueShieldState then self:CueShieldState(btn, false, cache and cache.engineCount) end   -- "Shield Gone" effect
				if btn.progressBar then btn.progressBar:Hide() end
				if btn.bgBar then btn.bgBar:Hide() end
				if btn.greyOverlay then btn.greyOverlay:Hide() end
				if btn.timeText then btn.timeText:SetText("") end
				if btn.insideText then btn.insideText:Hide() end
				if btn.outsideText then btn.outsideText:Hide() end
				if btn.belowText and btn.belowText ~= btn.outsideText then btn.belowText:Hide() end
				if btn.iconText then btn.iconText:Hide() end
			end
			if not (showSweep and sweepStyle == "radial") then btn.cooldown:Clear() end
			-- the flyout holds every shield you know and leaves out (arrows: fades) the one a click on the
			-- button casts; out of a fight it follows a change that came from elsewhere (Dynamic, a profile).
			-- Grid on or off makes it again. The button's cast first, in every style (SyncShieldButtonCast:
			-- a profile switch, a shield learned or unlearned), so the flyout is made or marked from it.
			local gridOn = self:CooldownBarGridOn(ct)
			if not InCombatLockdown() then
				if (gridOn and 1 or 0) ~= self._shieldFlyoutGrid then
					self:SyncShieldButtonCast(true)
					self:RebuildShieldFlyout()
				else
					self:SyncShieldButtonCast()
				end
			end
			-- Grid: the assigned one edged on the row, the one that is up with its charges
			if gridOn and self.shieldFlyout and self.shieldFlyout.grid then
				local up = self.shieldCache and self.shieldCache.hasShield and self:ShieldIndexOf(self.shieldCache.shieldID) or nil
				for _, b in ipairs(self.shieldFlyout.buttons) do
					local idx = self:ShieldIndexOf(b.spellID)
					local count = (idx == up and shieldCharges > 0 and not (cache and cache.engineCount)) and (NumberStrings[shieldCharges] or tostring(shieldCharges)) or nil
					self:CooldownGridMark(b, idx ~= nil and idx == viewIdx, idx ~= nil and idx == up, count)
				end
			end
			-- another shield up: above the button (Normal), as a different totem that is down shows; the
			-- assigned one in its corner (TotemTimers Style)
			do
				local ar, ag, ab = 1, 0.82, 0
				local color = aboveIdx and self.SpellBarColors and self.SpellBarColors[self.ShieldSpells[aboveIdx][1]]
				if color then ar, ag, ab = color[1], color[2], color[3] end
				local count = (aboveCharges > 0 and not (cache and cache.engineCount)) and (NumberStrings[aboveCharges] or tostring(aboveCharges)) or nil
				self:CooldownBarAbove(btn, aboveIdx and self:ShieldIcon(aboveIdx), nil, ar, ag, ab, count, not viewUp)
				self:CooldownBarCorner(btn, cornerIdx and self:ShieldIcon(cornerIdx))
			end
			-- running out (Show Items Only When Running Out, the running-out effects: ShamanPowerCues.lua)
			if self.RunOutShield and self:RunOutShield(btn, shieldUp, (shieldUp and shieldDuration > 0) and (shieldExpiration - GetTime()) or nil,
				shieldCharges, cache and cache.engineCount) then busy = true end

		elseif btn.spellType == "cooldown" then
			-- Check cooldown
			local start, duration, enabled = GetSpellCooldown(btn.spellID)
			-- on a cooldown longer than the global one; on WoW: Forever the game's own
			-- flags say it, the estimate only when they cannot (EngineCooldownRunning)
			local cooling = start and start > 0 and duration > 1.5
			local real   -- WoW: Forever: the game's own answer for the Ready cue too (nil: none)
			if engine then cooling = self:EngineCooldownRunning(btn, btn.spellID, cooling); real = btn._cdReal end
			if self.CueCooldownCheck then self:CueCooldownCheck(btn, start, duration, real) end   -- "Cooldown Ready" effect
			-- a cooldown in its last 10 minutes (seconds in its text, its end to catch for
			-- the Ready cue), any cooldown the engine is drawing, or a Ready cue waiting
			-- out the global cooldown
			if cooling then
				if engine or (start + duration) - GetTime() < 601 then busy = true end
			elseif btn._cueCdEnd then
				busy = true
			end
			if engine and cooling then
				self:FeedEngineBarCooldown(btn, start, duration, showSweep, showBars, textLocation, showText, barPosition)
			elseif cooling then
				-- Radial swipe only when chosen; otherwise the vertical grey sweep below
				if showSweep and sweepStyle == "radial" then
					btn.cooldown:SetCooldown(start, duration)
				else
					btn.cooldown:Clear()
				end
				btn.darkOverlay:Hide()
				btn.icon:SetDesaturated(false)
				-- Hide Ankh count when on cooldown
				if btn.ankhCountText then btn.ankhCountText:Hide() end

				-- Calculate remaining time
				local remaining = (start + duration) - GetTime()
				local percent = math.min(remaining / duration, 1)

				-- Progress bar
				local isVerticalBar = (barPosition == "left" or barPosition == "right" or barPosition == "top_vert" or barPosition == "bottom_vert" or barPosition == "on_icon")
				if showBars and btn.progressBar then
					local r, g, b = GetBarColor(remaining * 1000, spellColors and btn.spellID or nil)

					if btn.bgBar then btn.bgBar:Show() end
					btn.progressBar:ClearAllPoints()   -- on its background, which steps out past a flyout tab

					if isVerticalBar then
						-- Vertical bar
						local progressHeight = math.max(buttonHeight * percent, 1)
						btn.progressBar:SetSize(barHeight, progressHeight)
						if barPosition == "on_icon" then
							btn.progressBar:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
						elseif barPosition == "left" then
							btn.progressBar:SetPoint("BOTTOMRIGHT", btn.bgBar, "BOTTOMRIGHT", 0, 0)
						elseif barPosition == "right" then
							btn.progressBar:SetPoint("BOTTOMLEFT", btn.bgBar, "BOTTOMLEFT", 0, 0)
						elseif barPosition == "top_vert" then
							btn.progressBar:SetPoint("BOTTOM", btn.bgBar, "BOTTOM", 0, 0)
						elseif barPosition == "bottom_vert" then
							btn.progressBar:SetPoint("BOTTOM", btn.bgBar, "BOTTOM", 0, 0)
						end
					else
						-- Horizontal bar (top/bottom)
						local progressWidth = math.max(buttonWidth * percent, 1)
						btn.progressBar:SetSize(progressWidth, barHeight)
						if barPosition == "bottom" then
							btn.progressBar:SetPoint("TOPLEFT", btn.bgBar, "TOPLEFT", 0, 0)
						else
							btn.progressBar:SetPoint("BOTTOMLEFT", btn.bgBar, "BOTTOMLEFT", 0, 0)
						end
					end
					ShamanPower:SetSPBarColor(btn.progressBar, "cooldown", r, g, b, 0.9)
					btn.progressBar:Show()
				else
					if btn.progressBar then btn.progressBar:Hide() end
					if btn.bgBar then btn.bgBar:Hide() end
				end

				-- Gray sweep overlay (vertical, from the chosen edge)
				if showSweep and btn.greyOverlay and sweepStyle ~= "radial" then
					local depletedPercent = (sweepStyle == "fills") and percent or (1 - percent)   -- "fills": grey recedes instead of growing
					self:PaintVerticalSweep(btn.greyOverlay, btn, depletedPercent, buttonHeight, sweepTop, 0.08, 0.92)
				elseif btn.greyOverlay then
					btn.greyOverlay:Hide()
				end

				-- Duration text handling
				local durationStr = FormatDuration(remaining)

				-- Hide all duration texts first
				if btn.timeText then btn.timeText:SetText("") end
				if btn.insideText then btn.insideText:Hide() end
				if btn.outsideText then btn.outsideText:Hide() end
				if btn.belowText and btn.belowText ~= btn.outsideText then btn.belowText:Hide() end
				if btn.iconText then btn.iconText:Hide() end

				-- Show duration text at chosen location
				if textLocation == "inside" then
					if btn.insideText then
						btn.insideText:SetText(durationStr)
						btn.insideText:Show()
					end
				elseif textLocation == "outside" then
					if btn.outsideText then
						btn.outsideText:SetText(durationStr)
						btn.outsideText:Show()
					end
				elseif textLocation == "icon" then
					if btn.iconText then
						btn.iconText:SetText(durationStr)
						btn.iconText:Show()
					end
				elseif textLocation == "none" and showText then
					-- Legacy: show text on icon if CD Text toggle is enabled
					if btn.timeText then
						btn.timeText:SetText(durationStr)
					end
				end
			else
				if engine and btn._ebSpell then self:ClearEngineBarCooldown(btn) end
				btn.cooldown:Clear()
				btn.darkOverlay:Hide()
				if btn.progressBar then btn.progressBar:Hide() end
				if btn.bgBar then btn.bgBar:Hide() end
				if btn.greyOverlay then btn.greyOverlay:Hide() end
				if btn.timeText then btn.timeText:SetText("") end
				if btn.insideText then btn.insideText:Hide() end
				if btn.outsideText then btn.outsideText:Hide() end
				if btn.belowText and btn.belowText ~= btn.outsideText then btn.belowText:Hide() end
				if btn.iconText then btn.iconText:Hide() end

				-- Special case: Reincarnation - grey out if no Ankhs, show count if enabled
				if btn.spellID == 20608 then
					local ankhCount = GetItemCount(17030)  -- Ankh item ID
					btn.icon:SetDesaturated(ankhCount == 0)
					-- Show Ankh count if option enabled
					if btn.ankhCountText then
						if self:CdItemOpt(ct, "ankhCount") then
							btn.ankhCountText:SetText(ankhCount > 0 and tostring(ankhCount) or "0")
							-- Color based on count
							if ankhCount == 0 then
								btn.ankhCountText:SetTextColor(1, 0, 0)  -- Red when empty
							elseif ankhCount <= 3 then
								btn.ankhCountText:SetTextColor(1, 1, 0)  -- Yellow when low
							else
								btn.ankhCountText:SetTextColor(1, 1, 1)  -- White when plenty
							end
							btn.ankhCountText:Show()
						else
							btn.ankhCountText:Hide()
						end
					end
				-- Special case: Totemic Call - grey out if no totems are placed
				elseif btn.spellID == 36936 then
					local anyTotem = false
					for slot = 1, 4 do
						local haveTotem = ShamanPower:GetElementTotemInfo(slot)  -- element loop; shadow model in combat
						if haveTotem then
							anyTotem = true
							break
						end
					end
					btn.icon:SetDesaturated(not anyTotem)
				else
					btn.icon:SetDesaturated(false)
				end
			end
			-- running out (ShamanPowerCues.lua): its seconds left from the numbers above (in a fight on
			-- WoW: Forever, ShamanPower's own record of your cast; none known: nil)
			if self.RunOutCooldown then
				local left = (cooling and type(start) == "number" and type(duration) == "number" and start > 0 and duration > 1.5)
					and ((start + duration) - GetTime()) or nil
				if self:RunOutCooldown(btn, cooling and true or false, left) then busy = true end
			end
		elseif btn.spellType == "weaponImbue" then
			local hasMain, mainExp, _, mainID, hasOff, offExp, _, offID = GetWeaponEnchantInfo()
			if self.CueImbueCheck then self:CueImbueCheck(btn, hasMain, hasOff, mainID, offID, mainExp, offExp) end   -- "Weapon Imbue Gone" effect
			local readMain, readOff = hasMain, hasOff   -- (running out, below: the game's own read)
			-- the style (the totem bar's, or the cooldown bar's own): the imbue the button shows on each hand,
			-- whether each hand counts as up, the ones shown above it, the one in its corner
			local actualMain = hasMain and (self.EnchantIDToImbue[mainID] or self.lastMainHandImbue or 1) or nil
			local actualOff = hasOff and (self.EnchantIDToImbue[offID] or self.lastOffHandImbue or 2) or nil
			local viewMain, viewOff, upMain, upOff, above1, above2, cornerImbue = self:CooldownBarImbueView(actualMain, actualOff)
			hasMain, hasOff = upMain, upOff
			do
				local first = viewMain or viewOff or 0
				self:NoteImbuesShown(first, (viewOff and viewOff ~= first) and viewOff or 0)
			end
			local buttonHeight = btn:GetHeight()
			local buttonWidth = btn:GetWidth()
			local maxDuration = (SPCompat and SPCompat.GetWeaponEnchantInfo and SPCompat.FOREVER) and 3600000 or 1800000 -- imbues run 60 min on Forever, 30 on the Classic line
			imbueCtx.buttonWidth, imbueCtx.buttonHeight = buttonWidth, buttonHeight
			imbueCtx.barHeight, imbueCtx.barPosition = barHeight, barPosition
			imbueCtx.isVerticalBar, imbueCtx.showSweep = isVerticalBar, showSweep
			-- (radial is drawn as Grays Out on the imbue, as before; its Progress Bar inherits "on": its bars
			-- always showed, whatever the shared Show Progress Bars said)
			imbueCtx.sweepStyle, imbueCtx.sweepTop, imbueCtx.spellColors = sweepStyle, sweepTop, spellColors
			imbueCtx.showBars = showBars
			imbueCtx.maxDuration, imbueCtx.hasMain, imbueCtx.hasOff = maxDuration, hasMain, hasOff
			imbueCtx.btn, imbueCtx.self = btn, self
			imbueCtx.textLocation, imbueCtx.showText = textLocation, showText

			if hasMain or hasOff then
				-- a hand in its last minute (the Imbue Gone cue), or in its last 10 minutes
				-- with its time in text (seconds): keep the pace
				local textShown = textLocation == "inside" or textLocation == "outside" or textLocation == "icon" or (textLocation == "none" and showText)
				if (hasMain and type(mainExp) == "number" and (mainExp < 60000 or (textShown and mainExp < 601000)))
					or (hasOff and type(offExp) == "number" and (offExp < 60000 or (textShown and offExp < 601000))) then
					busy = true
				end
				-- Track each hand separately
				local mainType = viewMain or viewOff or 1
				local offType = viewOff or mainType

				btn.hasMainActive = hasMain
				btn.hasOffActive = hasOff

				-- Update grey sweep overlay textures to match current imbues
				btn.greyOverlayMain:SetTexture(self.WeaponIcons[mainType])
				btn.greyOverlayOff:SetTexture(self.WeaponIcons[offType])

				-- Split icon display when both hands have different imbues (Normal style: the assigned pair,
				-- a hand whose imbue is not on grayed)
				if viewMain and viewOff and viewMain ~= viewOff then
					-- Left half = main hand
					btn.icon:ClearAllPoints()
					btn.icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
					btn.icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOM", 0, 0)
					btn.icon:SetTexture(self.WeaponIcons[mainType])
					btn.icon:SetTexCoord(0.08, 0.50, 0.08, 0.92)
					btn.icon:SetDesaturated(not hasMain)
					-- Right half = off hand
					btn.icon2:ClearAllPoints()
					btn.icon2:SetPoint("TOPLEFT", btn, "TOP", 0, 0)
					btn.icon2:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
					btn.icon2:SetTexture(self.WeaponIcons[offType])
					btn.icon2:SetTexCoord(0.50, 0.92, 0.08, 0.92)
					btn.icon2:SetDesaturated(not hasOff)
					btn.icon2:Show()
				else
					-- Single imbue or same on both hands - full icon
					btn.icon:ClearAllPoints()
					btn.icon:SetAllPoints()
					local displayType = hasMain and mainType or offType
					btn.icon:SetTexture(self.WeaponIcons[displayType])
					btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
					btn.icon:SetDesaturated(false)
					btn.icon2:Hide()
				end
				btn.darkOverlay:Hide()

				-- Layout backgrounds first (uses hasMainActive/hasOffActive)
				if btn.bgBarMain and btn.bgBarOff then
					PositionDualImbueBars(imbueCtx, btn.bgBarMain, btn.bgBarOff,
						btn.insideText, btn.insideText2, btn.outsideText, btn.outsideText2)
				end

				UpdateImbueHand(imbueCtx, hasMain, mainExp, mainType, btn.bgBarMain, btn.progressBarMain,
					btn.greyOverlayMain, btn.insideText, btn.outsideText, btn.iconText, true)
				UpdateImbueHand(imbueCtx, hasOff, offExp, offType, btn.bgBarOff, btn.progressBarOff,
					btn.greyOverlayOff, btn.insideText2, btn.outsideText2, btn.iconText2, false)
			else
				-- No imbue active - restore full icon.
				-- Show the imbue this button would actually cast. Without this
				-- the texture keeps whatever was set at creation, so a shaman
				-- who has only Rockbiter sees a greyed Windfury icon.
				local restIdx
				if SPCompat.FOREVER then
					-- Name-based spellbook checks allocate modern API result tables.
					-- Keep the resting choice (including nil) until spells or preference change.
					local generation = self._imbueSpellGeneration or 0
					if not btn._restImbueReady or btn._restImbueGeneration ~= generation
						or btn._restImbuePreference ~= self.opt.preferredImbue then
						btn._restImbueIndex = self:DefaultImbueIndex()
						btn._restImbueGeneration, btn._restImbuePreference = generation, self.opt.preferredImbue
						btn._restImbueReady = true
					end
					restIdx = btn._restImbueIndex or self.lastMainHandImbue
				else
					restIdx = self:DefaultImbueIndex() or self.lastMainHandImbue
				end
				if restIdx and self.WeaponIcons[restIdx] then
					btn.icon:SetTexture(self.WeaponIcons[restIdx])
				end
				btn.icon:ClearAllPoints()
				btn.icon:SetAllPoints()
				btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
				btn.icon:SetDesaturated(true)
				btn.icon2:Hide()
				btn.darkOverlay:Show()
				if btn.progressBarMain then btn.progressBarMain:Hide() end
				if btn.progressBarOff then btn.progressBarOff:Hide() end
				if btn.bgBarMain then btn.bgBarMain:Hide() end
				if btn.bgBarOff then btn.bgBarOff:Hide() end
				if btn.greyOverlayMain then btn.greyOverlayMain:Hide() end
				if btn.greyOverlayOff then btn.greyOverlayOff:Hide() end
				if btn.timeText then btn.timeText:SetText("") end
				if btn.insideText then btn.insideText:Hide() end
				if btn.outsideText then btn.outsideText:Hide() end
				if btn.belowText and btn.belowText ~= btn.outsideText then btn.belowText:Hide() end
				if btn.iconText then btn.iconText:Hide() end
				if btn.insideText2 then btn.insideText2:Hide() end
				if btn.outsideText2 then btn.outsideText2:Hide() end
				if btn.iconText2 then btn.iconText2:Hide() end
			end
			-- another imbue on a hand: above the button (Normal), as a different totem that is down shows
			-- (both halves for two hands); the main hand's assigned one in its corner (TotemTimers Style)
			-- Grid: the assigned ones edged on the row, the ones that are up marked
			if self.weaponImbueFlyout and self.weaponImbueFlyout.grid and self:CooldownBarGridOn(ct) then
				for _, b in ipairs(self.weaponImbueFlyout.buttons) do
					local i = b.imbueIndex
					self:CooldownGridMark(b, i == viewMain or i == viewOff, i == actualMain or i == actualOff, nil)
				end
			end
			do
				local ar, ag, ab = 1, 0.82, 0
				local shown = above1 or above2
				local color = shown and self.ElementColors and self.ElementColors[self.IMBUE_ELEMENT[shown]]
				if color then ar, ag, ab = color.r, color.g, color.b end
				self:CooldownBarAbove(btn, above1 and self.WeaponIcons[above1], above2 and self.WeaponIcons[above2], ar, ag, ab, nil, not (upMain or upOff))
				self:CooldownBarCorner(btn, cornerImbue and self.WeaponIcons[cornerImbue])
			end
			-- running out (Show Items Only When Running Out, the running-out effects: ShamanPowerCues.lua)
			if self.RunOutImbue and self:RunOutImbue(btn, readMain, readOff, mainID, offID, mainExp, offExp) then busy = true end
		end
	end

	-- Check if progress bar visibility changed and relayout if needed (Progress Bar is per item)
	do
		local anyBarVisible = false
		for i = 1, #self.cooldownButtons do
			local btn = self.cooldownButtons[i]
			if (btn.progressBar and btn.progressBar:IsShown()) or
			   (btn.progressBarMain and btn.progressBarMain:IsShown()) or
			   (btn.progressBarOff and btn.progressBarOff:IsShown()) then
				anyBarVisible = true
				break
			end
		end
		if anyBarVisible ~= self.cdbarAnyProgressVisible then
			self.cdbarAnyProgressVisible = anyBarVisible
			self:UpdateCooldownBarLayout()
		end
	end
	self._cdbarBusy = busy
end

function ShamanPower:UpdateCooldownBar()
	if not isShaman then return end
	-- Don't update while dragging
	if self.cooldownBarDragging then return end

	if not self.cooldownBar then
		self:CreateCooldownBar()
	end

	-- Create weapon imbue button if not exists
	if not self.weaponImbueButton then
		self:CreateWeaponImbueButton()
	end

	-- Create shield flyout if shield button exists but flyout doesn't
	if self.shieldButton and not self.shieldFlyout then
		self:CreateShieldFlyout()
	end

	-- Apply flyout right-click mode to cooldown bar buttons
	self:UpdateCooldownBarFlyoutEnabled()

	-- Apply saved text size
	self:ApplyCdbarTextSize()

	if not self.cooldownBar then return end

	if self.opt.showCooldownBar and not self:IsOff() and #self.cooldownButtons > 0 then
		-- Update the button layout first
		self:UpdateCooldownBarLayout()

		-- Defer Show/Hide/positioning if in combat (secure frame)
		if InCombatLockdown() then
			self.cdbarVisibilityPending = true
			return
		end

		-- Position based on lock state
		if self.opt.cooldownBarLocked then
			-- Locked: anchor to totem bar based on layout orientation
			local isVertical = (self.opt.layout == "Vertical" or self.opt.layout == "VerticalLeft")
			local isVerticalLeft = (self.opt.layout == "VerticalLeft")
			self.cooldownBar:ClearAllPoints()
			if isVertical then
				if isVerticalLeft then
					-- Vertical (Left): bar on left side of screen, CDs go to the RIGHT of totems
					self.cooldownBar:SetPoint("LEFT", self.autoButton, "RIGHT", 2, 0)
				else
					-- Vertical (Right): bar on right side of screen, CDs go to the LEFT of totems
					self.cooldownBar:SetPoint("RIGHT", self.autoButton, "LEFT", -2, 0)
				end
			else
				-- Horizontal: position below the main totem bar
				self.cooldownBar:SetPoint("TOP", self.autoButton, "BOTTOM", 0, -2)
			end
			-- Hide drag handle when CD bar is locked to totem bar
			if self.cooldownBarDragHandle then
				self.cooldownBarDragHandle:Hide()
			end
		else
			-- Unlocked: set up independent positioning
			self:UpdateCooldownBarPosition()
		end
		-- your cooldowns show in the controller look (WoW: Forever, Hide The Cooldown Bar While This Shows):
		-- the bar hides, and its pass keeps running for its keys and the controller slots that press them
		self.cooldownBar:SetShown(not (self.ControllerHidesCooldownBar and self:ControllerHidesCooldownBar()))
		self:EnableUpdateSubsystem("cooldownBar")
		self:WakeCooldownBar()

		-- Apply scale
		self:UpdateCooldownBarScale()
	else
		if InCombatLockdown() then
			self.cdbarVisibilityPending = true
			return
		end
		self.cooldownBar:Hide()
		self:DisableUpdateSubsystem("cooldownBar")
	end
end

function ShamanPower:RecreateCooldownBar()
	-- a change made in combat (an item ticked off, the order) is applied when combat ends
	if InCombatLockdown() then self._cdBarRebuildPending = true; return end
	self._cdBarRebuildPending = nil

	-- Destroy existing cooldown bar and drag handle
	if self.cooldownBarDragHandle then
		self.cooldownBarDragHandle:Hide()
		self.cooldownBarDragHandle = nil
	end
	if self.cooldownBar then
		self.cooldownBar:Hide()
		self.cooldownBar:SetParent(nil)
		self.cooldownBar = nil
	end
	self.cooldownButtons = {}

	-- Destroy existing weapon imbue button and flyout
	if self.weaponImbueButton then
		self.weaponImbueButton:Hide()
		self.weaponImbueButton:SetParent(nil)
		self.weaponImbueButton = nil
	end
	if self.weaponImbueFlyout then
		-- Weapon imbue flyout buttons are children of imbue button, clean them up
		if self.weaponImbueFlyout.buttons then
			for _, btn in ipairs(self.weaponImbueFlyout.buttons) do
				btn:Hide()
				btn:SetParent(nil)
			end
		end
		self.weaponImbueFlyout = nil
	end

	-- Destroy existing shield button and flyout
	if self.shieldButton then
		self.shieldButton = nil  -- Reference only, actual button is in cooldownButtons
	end
	if self.shieldFlyout then
		-- Shield flyout buttons are children of shield button, clean them up
		if self.shieldFlyout.buttons then
			for _, btn in ipairs(self.shieldFlyout.buttons) do
				btn:Hide()
				btn:SetParent(nil)
			end
		end
		self.shieldFlyout = nil
	end

	-- Recreate it
	self:CreateCooldownBar()
	self:UpdateCooldownBar()

	-- Create shield flyout after cooldown bar is created
	if self.shieldButton then
		self:CreateShieldFlyout()
	end

	-- Apply lock/unlock state, position, and drag handle visibility
	self:UpdateCooldownBarPosition()
end

-- Update cooldown bar position based on lock state
-- forceReposition: set to true when switching profiles to apply new profile's position
function ShamanPower:UpdateCooldownBarPosition(forceReposition)
	if not self.cooldownBar then return end
	if InCombatLockdown() then return end
	if self.cooldownBarDragging then return end

	if self.opt.cooldownBarLocked then
		-- CD bar is attached to totem bar - hide drag handle
		if self.cooldownBarDragHandle then
			self.cooldownBarDragHandle:Hide()
		end
		self.cooldownBar:SetParent(self.autoButton)
		self.cooldownBar:EnableMouse(false)
		self.cooldownBar:SetMovable(false)
		self:UpdateCooldownBar()
	else
		-- CD bar is independent
		if self.cooldownBarDragHandle then
			self.cooldownBarDragHandle:SetChecked(self.opt.cooldownBarFrameLocked)
			self.cooldownBarDragHandle:Hide()
		end

		-- Position the bar when first unlocking OR when forcing reposition (profile change)
		if self.cooldownBar:GetParent() ~= UIParent or forceReposition then
			self.cooldownBar:SetParent(UIParent)
			self.cooldownBar:SetFrameStrata("MEDIUM")
			self.cooldownBar:SetFrameLevel(100)
			self.cooldownBar:ClearAllPoints()
			-- Saved offsets are in the bar's own units at its detached scale:
			-- apply that scale first, and mark it applied so the next
			-- UpdateCooldownBarScale does not "compensate" a fresh anchor.
			self.cooldownBar:SetScale(self.opt.cooldownBarScale or 0.9)
			self.cooldownBar._scaleApplied = true
			-- Use the saved spot if there is one; one saved by an old version (not
			-- the CENTER 0,-50 default) converts once. With neither,
			-- ApplyDefaultBarPositions below keeps it under the totem bar.
			local o = self.opt
			if o.cooldownBarPosition and o.cooldownBarPosition.anchor then
				self:ApplyPositionRecord(self.cooldownBar, o.cooldownBarPosition)
			elseif (o.cooldownBarPosX or 0) ~= 0 or (o.cooldownBarPosY or -50) ~= -50
				or (o.cooldownBarPoint or "CENTER") ~= "CENTER" or (o.cooldownBarRelPoint or "CENTER") ~= "CENTER" then
				local point = self.opt.cooldownBarPoint or "CENTER"
				local relPoint = self.opt.cooldownBarRelPoint or "CENTER"
				self.cooldownBar:SetPoint(point, UIParent, relPoint, self.opt.cooldownBarPosX or 0, self.opt.cooldownBarPosY or 0)
				self.opt.cooldownBarPosition = self:SavePositionRecord(self.cooldownBar)
				self.opt.cooldownBarPoint, self.opt.cooldownBarRelPoint = nil, nil
				self.opt.cooldownBarPosX, self.opt.cooldownBarPosY = nil, nil
			end
			self:ApplyDefaultBarPositions()
		end

		self.cooldownBar:EnableMouse(true)
		self.cooldownBar:SetMovable(true)
		self.cooldownBar:RegisterForDrag("LeftButton")
		-- shown only when UpdateCooldownBar would show it (switched on, something on
		-- it): a Reset or a reposition never brings up an empty or disabled bar
		if self.opt.showCooldownBar and not self:IsOff() and #self.cooldownButtons > 0
			and not (self.ControllerHidesCooldownBar and self:ControllerHidesCooldownBar()) then self.cooldownBar:Show() end
	end

	self:UpdateCooldownBarScale()
end

-- Update cooldown bar scale
function ShamanPower:UpdateCooldownBarScale()
	if not self.cooldownBar then return end

	local cdScale = self.opt.cooldownBarScale or 0.9

	if self.opt.cooldownBarLocked then
		-- When locked, counteract parent scale and apply CD scale
		local parentScale = self.opt.buffscale or 0.9
		self.cooldownBar:SetScale(cdScale / parentScale)
	else
		-- When unlocked (parented to UIParent), apply directly
		local bar = self.cooldownBar
		if not bar._scaleApplied then
			bar:SetScale(cdScale)
			bar._scaleApplied = true
		elseif math.abs(bar:GetScale() - cdScale) > 0.001 then
			if self.opt.cooldownBarPosition and self.opt.cooldownBarPosition.anchor then
				self:SetFrameScaleKeepCenter(bar, cdScale)
				self.opt.cooldownBarPosition = self:SavePositionRecord(bar)
			else
				bar:SetScale(cdScale)   -- on its default spot: worked out again for the new size
				self:ApplyDefaultBarPositions()
			end
		end
	end
end

-- Update cooldown bar progress bar positions and sizes
function ShamanPower:UpdateCooldownBarProgressBars()
	local barPosition = self.opt.cdbarProgressPosition or "left"
	local barSize = self.opt.cdbarProgressBarHeight or 3
	self:ResetEngineBarCooldowns()   -- engine strings and bars follow the new anchors on the next pass

	for _, btn in ipairs(self.cooldownButtons) do
		local buttonSize = btn:GetWidth()
		local buttonHeight = btn:GetHeight()
		-- out past the flyout tab on its side while it shows (shield and imbue buttons)
		local aT, aB, aL, aR = self:FlyoutArrowPads(btn)

		-- Normal buttons (single bar)
		if btn.spellType ~= "weaponImbue" then
			if btn.bgBar then
				btn.bgBar:ClearAllPoints()
				if barPosition == "bottom" then
					btn.bgBar:SetSize(buttonSize, barSize)
					btn.bgBar:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -(1 + aB))
					btn.bgBar:SetPoint("TOPRIGHT", btn, "BOTTOMRIGHT", 0, -(1 + aB))
				elseif barPosition == "bottom_vert" then
					btn.bgBar:SetSize(barSize, buttonHeight)
					btn.bgBar:SetPoint("TOP", btn, "BOTTOM", 0, -(1 + aB))
				elseif barPosition == "top" then
					btn.bgBar:SetSize(buttonSize, barSize)
					btn.bgBar:SetPoint("BOTTOMLEFT", btn, "TOPLEFT", 0, 1 + aT)
					btn.bgBar:SetPoint("BOTTOMRIGHT", btn, "TOPRIGHT", 0, 1 + aT)
				elseif barPosition == "top_vert" then
					btn.bgBar:SetSize(barSize, buttonHeight)
					btn.bgBar:SetPoint("BOTTOM", btn, "TOP", 0, 1 + aT)
				elseif barPosition == "on_icon" then
					btn.bgBar:SetSize(barSize, buttonSize)
					btn.bgBar:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
					btn.bgBar:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
				elseif barPosition == "left" then
					btn.bgBar:SetSize(barSize, buttonSize)
					btn.bgBar:SetPoint("TOPRIGHT", btn, "TOPLEFT", -(1 + aL), 0)
					btn.bgBar:SetPoint("BOTTOMRIGHT", btn, "BOTTOMLEFT", -(1 + aL), 0)
				elseif barPosition == "right" then
					btn.bgBar:SetSize(barSize, buttonSize)
					btn.bgBar:SetPoint("TOPLEFT", btn, "TOPRIGHT", 1 + aR, 0)
					btn.bgBar:SetPoint("BOTTOMLEFT", btn, "BOTTOMRIGHT", 1 + aR, 0)
				end
			end

			if btn.insideText and btn.bgBar then
				btn.insideText:ClearAllPoints()
				btn.insideText:SetPoint("CENTER", btn.bgBar, "CENTER", 0, 0)
				local fontSize = self.opt.cdbarDurationTextSize or 8
				ShamanPower:SetSPFont(btn.insideText, "timers", fontSize, "OUTLINE")
			end

			if btn.outsideText and btn.bgBar then
				btn.outsideText:ClearAllPoints()
				if barPosition == "bottom" or barPosition == "bottom_vert" then
					btn.outsideText:SetPoint("TOP", btn.bgBar, "BOTTOM", 0, -1)
				elseif barPosition == "top" or barPosition == "top_vert" then
					btn.outsideText:SetPoint("BOTTOM", btn.bgBar, "TOP", 0, 1)
				elseif barPosition == "on_icon" then
					btn.outsideText:SetPoint("RIGHT", btn, "LEFT", -(1 + aL), 0)
				elseif barPosition == "left" then
					btn.outsideText:SetPoint("RIGHT", btn.bgBar, "LEFT", -1, 0)
				elseif barPosition == "right" then
					btn.outsideText:SetPoint("LEFT", btn.bgBar, "RIGHT", 1, 0)
				end
			end
		else
			-- Weapon imbue: two bars (main / off)
			local function positionDual(bgMain, bgOff, insideMain, insideOff, outsideMain, outsideOff)
				local hasMain = btn.hasMainActive
				local hasOff = btn.hasOffActive
				local both = hasMain and hasOff

				if not hasMain and not hasOff then
					if bgMain then bgMain:Hide() end
					if bgOff then bgOff:Hide() end
					return
				end

				if barPosition == "bottom" then
					if both then
						bgMain:SetSize(buttonSize / 2, barSize)
						bgMain:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -(1 + aB))
						bgOff:SetSize(buttonSize / 2, barSize)
						bgOff:SetPoint("TOPLEFT", btn, "BOTTOM", 0, -(1 + aB))
					else
						bgMain:SetSize(buttonSize, barSize)
						bgMain:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -(1 + aB))
						if bgOff then bgOff:Hide() end
					end
				elseif barPosition == "top" then
					if both then
						bgMain:SetSize(buttonSize / 2, barSize)
						bgMain:SetPoint("BOTTOMLEFT", btn, "TOPLEFT", 0, 1 + aT)
						bgOff:SetSize(buttonSize / 2, barSize)
						bgOff:SetPoint("BOTTOMLEFT", btn, "TOP", 0, 1 + aT)
					else
						bgMain:SetSize(buttonSize, barSize)
						bgMain:SetPoint("BOTTOMLEFT", btn, "TOPLEFT", 0, 1 + aT)
						if bgOff then bgOff:Hide() end
					end
				elseif barPosition == "top_vert" then
					if both then
						bgMain:SetSize(barSize, buttonHeight)
						bgMain:SetPoint("BOTTOMRIGHT", btn, "TOP", -1, 1 + aT)
						bgOff:SetSize(barSize, buttonHeight)
						bgOff:SetPoint("BOTTOMLEFT", btn, "TOP", 1, 1 + aT)
					else
						bgMain:SetSize(barSize, buttonHeight)
						bgMain:SetPoint("BOTTOM", btn, "TOP", 0, 1 + aT)
						if bgOff then bgOff:Hide() end
					end
				elseif barPosition == "bottom_vert" then
					if both then
						bgMain:SetSize(barSize, buttonHeight)
						bgMain:SetPoint("TOPRIGHT", btn, "BOTTOM", -1, -(1 + aB))
						bgOff:SetSize(barSize, buttonHeight)
						bgOff:SetPoint("TOPLEFT", btn, "BOTTOM", 1, -(1 + aB))
					else
						bgMain:SetSize(barSize, buttonHeight)
						bgMain:SetPoint("TOP", btn, "BOTTOM", 0, -(1 + aB))
						if bgOff then bgOff:Hide() end
					end
				elseif barPosition == "on_icon" then
					if both then
						bgMain:SetSize(barSize, buttonSize)
						bgMain:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
						bgOff:SetSize(barSize, buttonSize)
						bgOff:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, 0)
					else
						bgMain:SetSize(barSize, buttonSize)
						bgMain:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
						if bgOff then bgOff:Hide() end
					end
				elseif barPosition == "left" then
					if both then
						bgMain:SetSize(barSize, buttonSize)
						bgMain:SetPoint("TOPRIGHT", btn, "TOPLEFT", -(1 + aL), 0)
						bgOff:SetSize(barSize, buttonSize)
						bgOff:SetPoint("TOPLEFT", btn, "TOPRIGHT", 1 + aR, 0)
					else
						bgMain:SetSize(barSize, buttonSize)
						bgMain:SetPoint("TOPRIGHT", btn, "TOPLEFT", -(1 + aL), 0)
						if bgOff then bgOff:Hide() end
					end
				elseif barPosition == "right" then
					if both then
						bgMain:SetSize(barSize, buttonSize)
						bgMain:SetPoint("TOPLEFT", btn, "TOPRIGHT", 1 + aR, 0)
						bgOff:SetSize(barSize, buttonSize)
						bgOff:SetPoint("TOPLEFT", bgMain, "TOPRIGHT", 1, 0)
					else
						bgMain:SetSize(barSize, buttonSize)
						bgMain:SetPoint("TOPLEFT", btn, "TOPRIGHT", 1 + aR, 0)
						if bgOff then bgOff:Hide() end
					end
				end

				if insideMain then
					insideMain:ClearAllPoints()
					insideMain:SetPoint("CENTER", bgMain, "CENTER", 0, 0)
					local fontSize = ShamanPower.opt.cdbarDurationTextSize or 8
					ShamanPower:SetSPFont(insideMain, "timers", fontSize, "OUTLINE")
				end
				if insideOff and hasOff and both then
					insideOff:ClearAllPoints()
					insideOff:SetPoint("CENTER", bgOff, "CENTER", 0, 0)
					local fontSize = ShamanPower.opt.cdbarDurationTextSize or 8
					ShamanPower:SetSPFont(insideOff, "timers", fontSize, "OUTLINE")
				elseif insideOff then
					insideOff:Hide()
				end

				if outsideMain then
					outsideMain:ClearAllPoints()
					if barPosition == "bottom" then
						outsideMain:SetPoint("TOP", bgMain, "BOTTOM", both and -2 or 0, -1)
					elseif barPosition == "top" then
						outsideMain:SetPoint("BOTTOM", bgMain, "TOP", both and -2 or 0, 1)
					elseif barPosition == "top_vert" then
						outsideMain:SetPoint("BOTTOM", bgMain, "TOP", 0, 1)
					elseif barPosition == "bottom_vert" then
						outsideMain:SetPoint("TOP", bgMain, "BOTTOM", 0, -1)
					else
						outsideMain:SetPoint("RIGHT", bgMain, "LEFT", -1 - (barPosition == "on_icon" and aL or 0), 0)
					end
				end
				if outsideOff then
					if hasOff and both then
						outsideOff:ClearAllPoints()
						if barPosition == "bottom" then
							outsideOff:SetPoint("TOP", bgOff, "BOTTOM", 2, -1)
						elseif barPosition == "top" then
							outsideOff:SetPoint("BOTTOM", bgOff, "TOP", 2, 1)
						elseif barPosition == "top_vert" then
							outsideOff:SetPoint("BOTTOM", bgOff, "TOP", 0, 1)
						elseif barPosition == "bottom_vert" then
							outsideOff:SetPoint("TOP", bgOff, "BOTTOM", 0, -1)
						else
							outsideOff:SetPoint("LEFT", bgOff, "RIGHT", 1 + (barPosition == "on_icon" and aR or 0), 0)
						end
					else
						outsideOff:Hide()
					end
				end
			end

			if btn.bgBarMain and btn.bgBarOff then
				positionDual(btn.bgBarMain, btn.bgBarOff, btn.insideText, btn.insideText2, btn.outsideText, btn.outsideText2)
			end
		end
	end
end

-- ============================================================================
-- Opacity Functions
-- ============================================================================

-- Party-range dots: where they sit relative to a totem button.
-- opt.partyDotPosition: "corners" (default) | "above" | "below" | "left" | "right"
function ShamanPower:PositionPartyDots(dots, frame)
	if not dots or not frame then return end
	local pos = (self.opt and self.opt.partyDotPosition) or "corners"
	local size, gap = (self.opt and self.opt.partyDotSize) or 5, 2
	local outline = not (self.opt and self.opt.partyDotOutline == false)
	local span = 4 * size + 3 * gap
	local anchor = self:PlacePartyDotFrame(frame)
	for i = 1, 4 do
		local dot = dots[i]
		if dot then
			dot:SetSize(size, size)
			-- 1px dark ring under the dot so it reads on bright icons; it
			-- follows the dot's own Show/Hide.
			if not dot.spOutline then
				local parent = dot:GetParent()
				local o = parent:CreateTexture(nil, "OVERLAY", nil, -1)
				o:SetTexture("Interface\\AddOns\\ShamanPower\\textures\\dot")
				o:SetVertexColor(0, 0, 0, 0.9)
				o:SetPoint("CENTER", dot, "CENTER", 0, 0)
				o:Hide()
				dot.spOutline = o
				hooksecurefunc(dot, "Show", function(d) if d.spOutline and d.spOutlineOn then d.spOutline:Show() end end)
				hooksecurefunc(dot, "Hide", function(d) if d.spOutline then d.spOutline:Hide() end end)
			end
			dot.spOutlineOn = outline
			dot.spOutline:SetSize(size + 2, size + 2)
			dot.spOutline:SetShown(outline and dot:IsShown())
			local tex = self.DotTexture and self:DotTexture()   -- Dot Shape
			if tex and dot.spDotTex ~= tex then dot:SetTexture(tex); dot.spOutline:SetTexture(tex); dot.spDotTex = tex end
			if self.DotGem then self:DotGem(dot) end   -- Gem Dot Finish
			dot:ClearAllPoints()
			local point, relPoint, x, y = self:PartyDotAnchor(i, frame)
			dot:SetPoint(point, anchor, relPoint, x, y)
		end
	end
	-- engine-drawn dots are anchored when built: re-anchoring means rebuilding
	-- (a no-op while nothing about the placement changed)
	if self.RebuildEnginePartyDots then self:RebuildEnginePartyDots() end
end

-- The dots hang from a stand-in for the button's rectangle rather than from the
-- button: dots on the side where the flyout tab sits step out past it by moving
-- this one plain frame, and the engine-drawn dots (Party Range), anchored to the
-- same frame, go with them, so the two sets stay on top of each other without a
-- rebuild. Corners and Compact's in-line dots never move.
function ShamanPower:PlacePartyDotFrame(frame)
	local x, y = 0, 0
	if not (frame.compactLayoutOn and self:CompactActive()) then
		local pos = (self.opt and self.opt.partyDotPosition) or "corners"
		local t, b, l, r = self:FlyoutArrowPads(frame)
		if pos == "above" then y = t
		elseif pos == "below" then y = -b
		elseif pos == "left" then x = -l
		elseif pos == "right" then x = r end
	end
	local f = frame.spDotFrame
	if f and f.spX == x and f.spY == y then return f end   -- already there
	if not f then
		f = CreateFrame("Frame", nil, frame)
		frame.spDotFrame = f
	elseif InCombatLockdown() and f:IsProtected() then
		return f   -- an engine dot anchored to it may protect it: left for the next layout
	end
	f.spX, f.spY = x, y
	f:ClearAllPoints()
	f:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
	f:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", x, y)
	return f
end

-- Where party dot `i` sits on `frame` (point, relative point, x, y) under the
-- position option. Shared by the addon's own dots and the engine-drawn ones
-- (Party Range module), which cover each other and so must anchor identically.
-- `pos` / `size` override the totem bar's options (the Coverage dots pass theirs).
function ShamanPower:PartyDotAnchor(i, frame, pos, size)
	pos = pos or (self.opt and self.opt.partyDotPosition) or "corners"
	size = size or (self.opt and self.opt.partyDotSize) or 5
	local gap = 2
	local span = 4 * size + 3 * gap
	local along = (i - 1) * (size + gap)
	if frame.compactLayoutOn and self:CompactActive() then
		-- Compact style: dots sit at the far end of the line (after the
		-- range-counter number when that is on too)
		local co = self:CompactOpts()
		local shift = self:CompactCounterShift(frame)
		if co.vertical then return "BOTTOM", "BOTTOM", 0, co.ow + 2 + shift + along end
		return "RIGHT", "RIGHT", -(co.ow + 3 + shift + along), 0
	elseif pos == "above" then return "BOTTOMLEFT", "TOP", along - span / 2, 2
	elseif pos == "below" then return "TOPLEFT", "BOTTOM", along - span / 2, -2
	elseif pos == "left" then return "TOPRIGHT", "LEFT", -2, span / 2 - along
	elseif pos == "right" then return "TOPLEFT", "RIGHT", 2, span / 2 - along
	elseif i == 1 then return "TOPLEFT", "TOPLEFT", 1, -1
	elseif i == 2 then return "TOPRIGHT", "TOPRIGHT", -1, -1
	elseif i == 3 then return "BOTTOMLEFT", "BOTTOMLEFT", 1, 1
	end
	return "BOTTOMRIGHT", "BOTTOMRIGHT", -1, 1
end

-- Extra distance (px) a bar on a given side must keep from the button so it
-- does not sit on top of the party dots. Returns top, bottom, left, right.
function ShamanPower:GetPartyDotPads()
	local pos = (self.opt and self.opt.partyDotPosition) or "corners"
	if not (self.opt and self.opt.showPartyRangeDots) then return 0, 0, 0, 0 end
	-- solo there are no dots: the bars sit where they always do (the room comes back
	-- in a group; OnRosterSettled lays the bar out again when that changes)
	if not IsInGroup() then return 0, 0, 0, 0 end
	local pad = (self.opt.partyDotSize or 5) + 3   -- the dot + 2px gap + 1px breathing room
	return (pos == "above") and pad or 0, (pos == "below") and pad or 0,
	       (pos == "left") and pad or 0, (pos == "right") and pad or 0
end

-- Space between totem bar buttons: the Button Spacing option, plus room for the
-- party dots where they sit between two buttons (a column beside each icon on a
-- horizontal bar, a row above / below each one on a vertical bar), so they never
-- land on the next totem. Compact puts its dots at the end of each line: no room.
function ShamanPower:TotemBarSpacing()
	local spacing = self.opt.totemBarPadding or 2
	if not self.opt.showPartyRangeDots or (self.CompactActive and self:CompactActive()) then return spacing end
	local t, b, l, r = self:GetPartyDotPads()
	if self:IsTotemBarHorizontal() then return spacing + math.max(l, r) end
	return spacing + math.max(t, b)
end

-- Re-anchor every party dot (main buttons + active-totem overlays) after the
-- position option changes, and move the duration / pulse bars out of their way.
function ShamanPower:UpdatePartyDotPositions()
	for element = 1, 4 do
		local btn = self.GetTotemOverlayHost and self:GetTotemOverlayHost(element)
			or (self.totemButtons and self.totemButtons[element])
		local dots = self.partyRangeDots and self.partyRangeDots[element]
		if btn and dots then self:PositionPartyDots(dots, btn) end
		local ov = self.activeTotemOverlays and self.activeTotemOverlays[element]
		if ov and ov.dots and ov.frame then self:PositionPartyDots(ov.dots, ov.frame) end
	end
	if self.UpdateTotemProgressBarPositions then self:UpdateTotemProgressBarPositions() end
	if self.UpdatePulseBarPositions then self:UpdatePulseBarPositions() end
	-- dots between the buttons need room there: lay the bar out again when that changes
	local spacing = self:TotemBarSpacing()
	if self._dotBarSpacing ~= spacing and not InCombatLockdown() then
		self._dotBarSpacing = spacing
		self:UpdateMiniTotemBar()
	end
end

function ShamanPower:UpdateTotemBarOpacity()
	local opacity = self.opt.totemBarOpacity or 1.0
	local fullWhenActive = self.opt.totemBarFullOpacityWhenActive
	-- a fade rule is on (UpdateTotemBarVisibility): the whole bar at the faded opacity
	if self.totemBarFaded then opacity, fullWhenActive = self.opt.fadeOpacity or 0.25, false end

	if self.autoButton then
		self.autoButton:SetAlpha(opacity)
	end
	-- Drop All sits on the bar button and takes its alpha: its own stays 1 (both set
	-- multiply: a 25% fade showed it at 6%). Popped out, it has its own frame.
	local dropAllBtn = _G["ShamanPowerAutoDropAll"]
	if dropAllBtn and dropAllBtn:IsShown() then
		dropAllBtn:SetAlpha(dropAllBtn:GetParent() == self.autoButton and 1 or opacity)
	end

	-- Set alpha on totem buttons - full opacity if totem is placed and option enabled
	if self.totemButtons then
		for element = 1, 4 do
			local btn = self.totemButtons[element]
			if btn then
				if fullWhenActive then
					local haveTotem = self:GetElementTotemInfo(element)
					btn:SetAlpha(haveTotem and 1.0 or opacity)
				else
					btn:SetAlpha(opacity)
				end
			end
		end
	end

	-- Also set alpha on Earth Shield button
	local esBtn = _G["ShamanPowerEarthShieldBtn"]
	if esBtn then
		if fullWhenActive then
			-- Check if someone has our Earth Shield active
			local hasActiveES = self.esTrackedTarget and self.esTrackedCharges and self.esTrackedCharges > 0
			esBtn:SetAlpha(hasActiveES and 1.0 or opacity)
		else
			esBtn:SetAlpha(opacity)
		end
	end
end

-- AuraUtil.FindAuraByName is broken on the 2.5.x client (its data provider
-- lacks GetAuraDataBySpellName and throws). Scan the player's buffs directly.
-- Shadow buff model for the player's own short buffs (Bloodlust, Nature's
-- Swiftness, Shamanistic Rage ...): aura reads go secret in combat, own casts
-- never do. A cast stamps the start; the length is learned while readable.
ShamanPower.shadowBuffs = {}   -- [spellName] = { start, duration }
local cachePlayerBuffs = SPCompat.FOREVER
local buffIsSecret = _G.issecretvalue or function() return false end

-- Opacity watches share the shadow entries, but only public aura observations
-- populate this cache. Unknown reads are retried on aura/restriction events.
local function RefreshPlayerBuffEntry(spellName, entry)
	entry.opacityKnown = nil
	if totemsSecretNow() or (_G.SPCompat and _G.SPCompat.AurasUnreadable and _G.SPCompat.AurasUnreadable()) then
		return
	end
	local api = _G.C_UnitAuras
	if not (api and api.GetAuraDataBySpellName) then return end
	-- RequiresNonSecretAura may hide a particular spell even outside combat.
	local policy = _G.C_Secrets and _G.C_Secrets.ShouldSpellAuraBeSecret
	if not policy then return end
	local policyOK, secret = pcall(policy, spellName)
	if not policyOK or buffIsSecret(secret) or secret ~= false then return end
	local ok, aura = pcall(api.GetAuraDataBySpellName, "player", spellName, "HELPFUL")
	if not ok or buffIsSecret(aura) then return end
	if aura == nil then
		entry.opacityKnown, entry.opacityPresent, entry.opacityExpiration = true, false, nil
		entry.start = nil
		return
	end
	if type(aura) ~= "table" then return end
	local name, duration, expiration = aura.name, aura.duration, aura.expirationTime
	if buffIsSecret(name) or buffIsSecret(duration) or buffIsSecret(expiration) then return end
	if type(name) ~= "string" or name ~= spellName then return end
	if type(duration) ~= "number" or type(expiration) ~= "number" then return end
	entry.opacityKnown, entry.opacityPresent, entry.opacityExpiration = true, true, expiration
	if duration > 0 then
		entry.duration = duration
		if expiration > 0 then entry.start = expiration - duration end
	end
end

function _G.ShamanPower:RefreshPlayerBuffCache()
	if not cachePlayerBuffs then return end
	for name, entry in pairs(self.shadowBuffs) do
		if entry.opacityWatched then RefreshPlayerBuffEntry(name, entry) end
	end
end

function ShamanPower:ShadowBuffCast(spellID)
	local name = GetSpellInfo(spellID)
	if cachePlayerBuffs and buffIsSecret(name) then return end
	if not name then return end
	local e = self.shadowBuffs[name] or {}
	e.start = GetTime()
	self.shadowBuffs[name] = e
end

local function PlayerHasBuff(spellID)
	local spellName = SPCompat.SpellName(spellID)
	if not spellName then return false end
	if totemsSecretNow() then
		local e = ShamanPower.shadowBuffs[spellName]
		if not (e and e.start) then return false end
		local duration = e.duration or 30   -- unknown length (Nature's Swiftness has none): assume a short window
		return e.start + duration > GetTime()
	end
	if cachePlayerBuffs then
		local e = _G.ShamanPower.shadowBuffs[spellName]
		if not e then
			e = {}
			_G.ShamanPower.shadowBuffs[spellName] = e
		end
		if not e.opacityWatched then
			e.opacityWatched = true
			RefreshPlayerBuffEntry(spellName, e)
		end
		if not e.opacityKnown then return false end
		return e.opacityPresent and (e.opacityExpiration == 0 or e.opacityExpiration > _G.GetTime())
	end
	local found, duration, expiration
	if C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
		local a = C_UnitAuras.GetAuraDataBySpellName("player", spellName, "HELPFUL")
		if a then found, duration, expiration = true, a.duration, a.expirationTime end
	else
		for i = 1, 40 do
			local name, _, _, _, dur, exp = UnitAura("player", i, "HELPFUL")
			if not name then break end
			if name == spellName then found, duration, expiration = true, dur, exp break end
		end
	end
	if found and duration and duration > 0 then
		local e = ShamanPower.shadowBuffs[spellName] or {}
		e.duration = duration
		if expiration and expiration > 0 then e.start = expiration - duration end
		ShamanPower.shadowBuffs[spellName] = e
	end
	return found and true or false
end

function ShamanPower:UpdateCooldownBarOpacity()
	local opacity = self.opt.cooldownBarOpacity or 1.0
	local fullWhenActive = self.opt.cooldownBarFullOpacityWhenActive

	if self.cooldownBar then
		if fullWhenActive and self.cooldownButtons then
			-- Set bar to full opacity, but we'll control individual button opacity
			self.cooldownBar:SetAlpha(1.0)

			-- Check each button for active state
			for i = 1, #self.cooldownButtons do
				local btn = self.cooldownButtons[i]
				local isActive = false

				if btn.spellType == "shield" then
					-- Shield is active if player has the buff
					isActive = btn.activeShieldID ~= nil
				elseif btn.spellType == "cooldown" then
					-- Check if the buff is active on the player (for spells with buffs)
					local spellID = btn.spellID
					local spellName = btn.spellName

					-- Check for specific buff-based abilities
					if spellID == 16188 then
						-- Nature's Swiftness - check if NS buff is active
						isActive = PlayerHasBuff(16188)
					elseif spellID == 30823 then
						-- Shamanistic Rage - check if SR buff is active
						isActive = PlayerHasBuff(30823)
					elseif spellID == 2825 or spellID == 32182 then
						-- Bloodlust/Heroism - check if buff is active
						local hasBL = PlayerHasBuff(2825)
						local hasHero = PlayerHasBuff(32182)
						isActive = hasBL or hasHero
					elseif spellID == 16190 then
						-- Mana Tide Totem - check if MTT is active (water totem)
						local haveTotem, totemName = self:GetElementTotemInfo(3)
						if haveTotem and SPCompat.TotemNameMatches(totemName, 16190, "Mana Tide Totem") then
							isActive = true
						end
					elseif spellID == 36936 then
						-- Totemic Call - active if any totems are placed
						for slot = 1, 4 do
							local haveTotem = ShamanPower:GetElementTotemInfo(slot)  -- element loop; shadow model in combat
							if haveTotem then
								isActive = true
								break
							end
						end
					elseif spellID == 20608 then
						-- Reincarnation - active if off cooldown and available
						local start, duration = GetSpellCooldown(spellID)
						isActive = (not start or start == 0 or duration <= 1.5)
						-- WoW: Forever: the game's own answer from the cooldown pass just before, when it has one
						if btn._cdReal ~= nil and self:EngineCooldownsOn() then isActive = not btn._cdReal end
					end
				elseif btn.spellType == "imbue" then
					-- Imbue is active if weapon is enchanted
					local hasMain = GetWeaponEnchantInfo()
					isActive = hasMain
				end

				-- out of sight (Show Items Only When Running Out): 0, keeping its spot
				btn:SetAlpha(btn._roHidden and 0 or (isActive and 1.0 or opacity))
			end
		else
			self.cooldownBar:SetAlpha(opacity)
			-- Reset all buttons to inherit bar opacity
			if self.cooldownButtons then
				for i = 1, #self.cooldownButtons do
					local btn = self.cooldownButtons[i]
					btn:SetAlpha(btn._roHidden and 0 or 1.0)  -- Full relative to parent (0: out of sight)
				end
			end
		end
	end
end

function ShamanPower:UpdateTotemFlyoutOpacity()
	local opacity = self.opt.totemFlyoutOpacity or 1.0
	-- Update all totem flyout buttons (flyout is now a table with buttons array)
	if self.totemFlyouts then
		for element = 1, 4 do
			local flyout = self.totemFlyouts[element]
			if flyout and flyout.buttons then
				for _, btn in ipairs(flyout.buttons) do
					btn:SetAlpha(opacity)
				end
			end
		end
	end
end

-- Apply duration text size to all cooldown bar text elements
function ShamanPower:ApplyCdbarTextSize()
	self:ResetEngineBarCooldowns()   -- the engine strings copy the font on their next placement
	local size = self.opt.cdbarDurationTextSize or 8
	for _, btn in ipairs(self.cooldownButtons) do
		if btn.insideText then ShamanPower:SetSPFont(btn.insideText, "timers", size, "OUTLINE") end
		if btn.outsideText then ShamanPower:SetSPFont(btn.outsideText, "timers", size, "OUTLINE") end
		if btn.iconText then ShamanPower:SetSPFont(btn.iconText, "timers", size, "OUTLINE") end
		if btn.insideText2 then ShamanPower:SetSPFont(btn.insideText2, "timers", size, "OUTLINE") end
		if btn.outsideText2 then ShamanPower:SetSPFont(btn.outsideText2, "timers", size, "OUTLINE") end
		if btn.iconText2 then ShamanPower:SetSPFont(btn.iconText2, "timers", size, "OUTLINE") end
	end
end

function ShamanPower:UpdateCooldownFlyoutOpacity()
	-- Update cooldown bar flyouts (shield selector, imbue selector), each at its item's own Opacity
	-- Flyouts are now tables with buttons as children of the parent button
	if self.shieldFlyout and self.shieldFlyout.buttons then
		local opacity = self:CdItemOpt(1, "flyoutOpacity") or 1.0
		for _, btn in ipairs(self.shieldFlyout.buttons) do
			btn:SetAlpha(opacity)
		end
	end
	if self.weaponImbueFlyout and self.weaponImbueFlyout.buttons then
		local opacity = self:CdItemOpt(7, "flyoutOpacity") or 1.0
		for _, btn in ipairs(self.weaponImbueFlyout.buttons) do
			btn:SetAlpha(opacity)
		end
	end
end

-- Apply totem cooldown text color to all existing buttons
function ShamanPower:ApplyTotemCooldownTextColor()
	local c = self.opt.totemCooldownTextColor
	local r, g, b = c and c.r or 1, c and c.g or 1, c and c.b or 1
	self:RestyleEngineCooldowns()
	-- Main totem buttons
	for element = 1, 4 do
		local btn = self.totemButtons and self.totemButtons[element]
		if btn and btn.cooldownText then
			btn.cooldownText:SetTextColor(r, g, b)
		end
	end
	-- Flyout buttons
	for element = 1, 4 do
		local flyout = self.totemFlyouts and self.totemFlyouts[element]
		if flyout and flyout.buttons then
			for _, btn in ipairs(flyout.buttons) do
				if btn.cooldownText then
					btn.cooldownText:SetTextColor(r, g, b)
				end
			end
		end
		-- Totem Rows' copies of them (Keep Flyouts on Main Totem Bar)
		local copies = self.RowsCopies and self:RowsCopies(element)
		if copies then
			for i = 1, #copies do
				if copies[i].cooldownText then copies[i].cooldownText:SetTextColor(r, g, b) end
			end
		end
	end
end

-- Apply all opacity settings (called on load/profile change)
function ShamanPower:ApplyAllOpacity()
	self:UpdateTotemBarOpacity()
	self:UpdateCooldownBarOpacity()
	self:UpdateTotemFlyoutOpacity()
	self:UpdateCooldownFlyoutOpacity()
end

-- ============================================================================
-- Weapon Imbue Bar (for applying weapon enchants)
-- ============================================================================

ShamanPower.weaponImbueButton = nil
ShamanPower.weaponImbueFlyout = nil
ShamanPower.lastMainHandImbue = nil  -- Last imbue applied to main hand
ShamanPower.lastOffHandImbue = nil   -- Last imbue applied to off hand

-- Check if player can dual wield (Enhancement talent)
function ShamanPower:CanDualWield()
	-- Check if player has an off-hand weapon equipped
	local offHandLink = GetInventoryItemLink("player", 17)  -- SecondaryHandSlot
	if issecretvalue(offHandLink) then return false end
	if offHandLink then
		-- Item class IDs do not change with the client's language.
		local _, _, _, _, _, _, _, _, _, _, _, itemClass = GetItemInfo(offHandLink)
		if not issecretvalue(itemClass) and itemClass == 2 then
			return true
		end
	end
	return false
end

-- Which imbue the button would cast right now: the preferred one when it is
-- actually known, otherwise the first one that is. Used for the resting icon
-- so an unenchanted weapon shows the imbue you have rather than a fixed guess.
function ShamanPower:DefaultImbueIndex()
	local pref = self.opt and self.opt.preferredImbue
	if pref and self:GetHighestRankImbue(pref) then return pref end
	for i = 1, 4 do
		if self:GetHighestRankImbue(i) then return i end
	end
	return nil
end

-- Get the highest rank of a weapon imbue spell that the player knows
function ShamanPower:GetHighestRankImbue(imbueIndex)
	local baseSpellID = self.WeaponImbueSpells[imbueIndex]
	if not baseSpellID then return nil end

	local baseName = SPCompat.SpellName(baseSpellID)
	if not baseName then return nil end

	-- Try to find the spell in the spellbook (gets highest rank)
	local spellName = baseName
	if PlayerKnowsSpellByID(baseSpellID) then
		return spellName
	end

	return nil
end

-- Create the weapon imbue button on the cooldown bar
function ShamanPower:CreateWeaponImbueButton()
	if self.weaponImbueButton then return end
	if not self.cooldownBar then return end
	if InCombatLockdown() then return end

	-- Check if imbues are enabled in options
	if self.opt.cdbarShowImbues == false then return end

	-- Check if player knows any weapon imbue
	local knowsAnyImbue = false
	for i = 1, 4 do
		if self:GetHighestRankImbue(i) then
			knowsAnyImbue = true
			break
		end
	end

	if not knowsAnyImbue then return end

	local buttonSize = self.cooldownBar.buttonSize or 22

	-- Create the button with secure templates for combat-functional flyout
	local btn = CreateFrame("Button", "ShamanPowerWeaponImbue", self.cooldownBar,
		"SecureActionButtonTemplate, SecureHandlerEnterLeaveTemplate, SecureHandlerMouseUpDownTemplate, SecureHandlerBaseTemplate")
	btn:SetSize(buttonSize, buttonSize)
	btn:RegisterForClicks("LeftButtonUp", "LeftButtonDown", "RightButtonUp", "RightButtonDown")

	-- Icon texture (will be updated based on current enchants)
	local iconTex = btn:CreateTexture(nil, "ARTWORK")
	iconTex:SetAllPoints()
	iconTex:SetTexture(self.WeaponIcons[self:DefaultImbueIndex() or 1])  -- the imbue this button would cast, not a fixed Windfury
	iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	btn.icon = iconTex

	-- Second icon for split display (off-hand)
	local icon2 = btn:CreateTexture(nil, "ARTWORK")
	icon2:SetPoint("TOPLEFT", btn, "CENTER", 0, 0)
	icon2:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
	icon2:SetTexture(self.WeaponIcons[2])  -- Default to Flametongue
	icon2:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	icon2:Hide()
	btn.icon2 = icon2

	-- Dark overlay for when no enchant is active
	local dark = btn:CreateTexture(nil, "OVERLAY")
	dark:SetAllPoints()
	dark:SetColorTexture(0, 0, 0, 0.6)
	dark:Hide()
	btn.darkOverlay = dark

	-- Dual progress bars (main hand / off hand) + backgrounds
	local barSize = self.opt.cdbarProgressBarHeight or 3

	local bgBarMain = btn:CreateTexture(nil, "OVERLAY")
	bgBarMain:SetColorTexture(0, 0, 0, 0.7)
	bgBarMain:Hide()
	btn.bgBarMain = bgBarMain

	local progressBarMain = btn:CreateTexture(nil, "OVERLAY", nil, 1)
	ShamanPower:SetSPBarColor(progressBarMain, "cooldown", 0.2, 0.8, 0.2, 0.9)
	progressBarMain:Hide()
	btn.progressBarMain = progressBarMain

	local bgBarOff = btn:CreateTexture(nil, "OVERLAY")
	bgBarOff:SetColorTexture(0, 0, 0, 0.7)
	bgBarOff:Hide()
	btn.bgBarOff = bgBarOff

	local progressBarOff = btn:CreateTexture(nil, "OVERLAY", nil, 1)
	ShamanPower:SetSPBarColor(progressBarOff, "cooldown", 0.2, 0.8, 0.2, 0.9)
	progressBarOff:Hide()
	btn.progressBarOff = progressBarOff

	-- Grey sweep overlays (one per hand)
	local greyOverlayMain = btn:CreateTexture(nil, "ARTWORK", nil, 1)
	greyOverlayMain:SetTexture(self.WeaponIcons[1])
	greyOverlayMain:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	greyOverlayMain:SetDesaturated(true)
	greyOverlayMain:SetVertexColor(0.5, 0.5, 0.5)
	greyOverlayMain:Hide()
	btn.greyOverlayMain = greyOverlayMain

	local greyOverlayOff = btn:CreateTexture(nil, "ARTWORK", nil, 1)
	greyOverlayOff:SetTexture(self.WeaponIcons[2])
	greyOverlayOff:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	greyOverlayOff:SetDesaturated(true)
	greyOverlayOff:SetVertexColor(0.5, 0.5, 0.5)
	greyOverlayOff:Hide()
	btn.greyOverlayOff = greyOverlayOff

	-- Time text for showing remaining duration (legacy)
	local timeText = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	ShamanPower:AdoptSPFont(timeText, "timers")   -- template font = the design; follows the Fonts settings
	timeText:SetPoint("CENTER", btn, "CENTER", 0, 0)
	timeText:SetText("")
	btn.timeText = timeText

	-- Duration text INSIDE the bar
	local insideText = btn:CreateFontString(nil, "OVERLAY", nil, 7)
	ShamanPower:SetSPFont(insideText, "timers", 8, "OUTLINE")
	insideText:SetTextColor(1, 1, 1)
	insideText:Hide()
	btn.insideText = insideText

	-- Duration text OUTSIDE the bar
	local outsideText = btn:CreateFontString(nil, "OVERLAY")
	ShamanPower:SetSPFont(outsideText, "timers", 8, "OUTLINE")
	outsideText:SetTextColor(1, 1, 1)
	outsideText:Hide()
	btn.outsideText = outsideText
	btn.belowText = outsideText

	-- Duration text ON the icon
	local iconText = btn:CreateFontString(nil, "OVERLAY")
	ShamanPower:SetSPFont(iconText, "timers", 9, "OUTLINE")
	iconText:SetPoint("CENTER", btn, "CENTER", 0, 0)
	iconText:SetTextColor(1, 1, 1)
	iconText:Hide()
	btn.iconText = iconText

	-- Off-hand duration text (mirrors main-hand options)
	local insideText2 = btn:CreateFontString(nil, "OVERLAY", nil, 7)
	ShamanPower:SetSPFont(insideText2, "timers", 8, "OUTLINE")
	insideText2:SetTextColor(1, 1, 1)
	insideText2:Hide()
	btn.insideText2 = insideText2

	local outsideText2 = btn:CreateFontString(nil, "OVERLAY")
	ShamanPower:SetSPFont(outsideText2, "timers", 8, "OUTLINE")
	outsideText2:SetTextColor(1, 1, 1)
	outsideText2:Hide()
	btn.outsideText2 = outsideText2

	local iconText2 = btn:CreateFontString(nil, "OVERLAY")
	ShamanPower:SetSPFont(iconText2, "timers", 9, "OUTLINE")
	iconText2:SetTextColor(1, 1, 1)
	iconText2:Hide()
	btn.iconText2 = iconText2

	-- Keybind text (top right corner, like standard action buttons)
	local keybindText = btn:CreateFontString(nil, "OVERLAY")
	ShamanPower:SetSPFont(keybindText, "labels", 9, "OUTLINE", "Fonts\\ARIALN.TTF")
	keybindText:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 1, 0)
	keybindText:SetTextColor(0.9, 0.9, 0.9, 1)
	keybindText:SetText("")
	keybindText:Hide()  -- Hidden by default, shown if option enabled
	btn.keybindText = keybindText
	btn.cooldownType = 7  -- Imbue type for keybind lookup

	-- SECURE HANDLER: Show flyout on enter (WORKS IN COMBAT)
	btn:SetAttribute("OpenMenu", "mouseover")
	ShamanPower:SetSnippet(btn, "_onenter", [[
		if self:GetAttribute("OpenMenu") == "mouseover" then
			self:ChildUpdate("show", true)
		end
	]])

	-- SECURE HANDLER: Hide flyout on leave (WORKS IN COMBAT)
	ShamanPower:SetSnippet(btn, "_onleave", SP_SECURE_ONLEAVE_SELF)

	-- SECURE HANDLER: Show flyout on right-click when in click mode (WORKS IN COMBAT)
	ShamanPower:SetSnippet(btn, "_onmouseup", [[
		local button = button
		if button == "RightButton" and self:GetAttribute("OpenMenu") == "click" then
			self:ChildUpdate("show", true)
		end
	]])

	-- Tooltip (Lua hooks work alongside secure handlers)
	btn:HookScript("OnEnter", function(self)
		if not ShamanPower.opt.ShowTooltips then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Weapon Imbues")

		-- Show current enchant status
		local hasMain, mainExp, _, mainID, hasOff, offExp, _, offID = GetWeaponEnchantInfo()
		if hasMain then
			local imbueType = ShamanPower.EnchantIDToImbue[mainID]
			local imbueName = imbueType and SPCompat.SpellLabel(ShamanPower.WeaponImbueSpells[imbueType], ShamanPower.WeaponEnchantNames[imbueType]) or "Unknown"
			GameTooltip:AddLine("Main Hand: " .. imbueName .. " (" .. math.floor(mainExp/60000) .. "m)", 0, 1, 0)
		else
			GameTooltip:AddLine("Main Hand: None", 1, 0.5, 0.5)
		end

		if ShamanPower:CanDualWield() then
			if hasOff then
				local imbueType = ShamanPower.EnchantIDToImbue[offID]
				local imbueName = imbueType and SPCompat.SpellLabel(ShamanPower.WeaponImbueSpells[imbueType], ShamanPower.WeaponEnchantNames[imbueType]) or "Unknown"
				GameTooltip:AddLine("Off Hand: " .. imbueName .. " (" .. math.floor(offExp/60000) .. "m)", 0, 1, 0)
			else
				GameTooltip:AddLine("Off Hand: None", 1, 0.5, 0.5)
			end
		end

		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(ShamanPower:ClickLabel(true) .. " Apply to Main Hand", 1, 1, 1)
		if ShamanPower:CanDualWield() then
			GameTooltip:AddLine(ShamanPower:ClickLabel(false) .. " Apply to Off Hand", 1, 1, 1)
		end
		GameTooltip:Show()
	end)

	btn:HookScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	-- Set default spell for quick cast (preferred imbue, or first known)
	local prefIdx = self.opt.preferredImbue
	local defaultImbue = (prefIdx and self:GetHighestRankImbue(prefIdx))
		or self:GetHighestRankImbue(1) or self:GetHighestRankImbue(2)
		or self:GetHighestRankImbue(3) or self:GetHighestRankImbue(4)
	if defaultImbue then
		local mainHandMacro = "/cast [@none] " .. defaultImbue .. "\n/use 16\n/click StaticPopup1Button1"
		local offHandMacro = "/cast [@none] " .. defaultImbue .. "\n/use 17\n/click StaticPopup1Button1"
		btn:SetAttribute("type1", "macro")
		btn:SetAttribute("macrotext1", mainHandMacro)
		btn:SetAttribute("type2", "macro")
		btn:SetAttribute("macrotext2", offHandMacro)
		btn.currentImbueName = defaultImbue
	end

	self.weaponImbueButton = btn
	self:SetImbueButtonMacros()   -- each hand's own assigned imbue (the off hand's own pick, when it has one)

	-- Add to cooldown buttons array for positioning
	table.insert(self.cooldownButtons, btn)
	btn.spellType = "weaponImbue"
	btn.cooldownType = 7  -- Imbue is type 7 for ordering

	-- Create the flyout
	self:CreateWeaponImbueFlyout()
end

-- ============================================================================
-- Shield Flyout (for selecting between Lightning Shield and Water Shield)
-- ============================================================================

-- Create the flyout menu for shields (combat-functional architecture)
-- Flyout buttons are parented directly to shieldButton for ChildUpdate to work
-- Box mode for the cooldown bar flyouts: every button stays shown inside the
-- (hidden) box, since nothing can show them one by one during a fight.
function ShamanPower:SyncCdbarFlyout(flyout)
	if not flyout or not flyout.box or InCombatLockdown() then return end
	for _, btn in ipairs(flyout.buttons or {}) do btn:Show() end
	self:PlaceFlyoutArrows(flyout)
end

-- ---------------------------------------------------------------------------
-- The cooldown bar's shield and imbue buttons follow a totem bar style the way the totem buttons do:
-- the totem bar's own (General > Main: Totem Bar Style), or the cooldown bar's own pick when Do Not
-- Mirror Totem Bar Style is on (Cooldown Bar page). Only these two buttons; the totem bar is untouched.
--   Normal (and Blizzard's bar): the button is the assigned one, lit only while THAT one is up; another
--     one up shows above it (on its flyout's side, as a totem's) and the assigned one is grayed out
--   TotemTimers Style: the button is the one that is up, the assigned one in its corner
--   Single Totem, Compact: the one that is up, no corner
--   Dynamic: the one that is up, and casting another makes it the assigned one
--   Grid: as Normal, with every choice pinned open as a row beside the button (the assigned one edged,
--     the one that is up marked), as the totem bar's Grid lays out every totem
-- The imbue flyout leaves out what the button shows. The shield flyout leaves out the shield a click on the
-- button casts (arrows: drawn faded), as the totem flyouts do, so a pick can change it in a fight
-- (CreateShieldFlyout).
-- ---------------------------------------------------------------------------
ShamanPower.IMBUE_ELEMENT = { 4, 2, 3, 1 }
ShamanPower.CDBAR_STYLE = {
	normal = {}, blizzard = {}, grid = { grid = true },
	totemtimers = { showsActive = true, corner = true },
	single = { showsActive = true }, compact = { showsActive = true },
	dynamic = { showsActive = true, adopt = true },
}

-- t: the item (1 the shield, 7 the weapon imbue: its own Button Style, ShamanPowerCdItems.lua); nil: the shared one
function ShamanPower:CooldownBarStyle(t)
	local s = self.opt and self:CdItemOpt(t, "buttonStyle")
	if s and s ~= "mirror" and self.CDBAR_STYLE[s] then return s end
	return (self.GetTotemBarStyle and self:GetTotemBarStyle()) or "normal"
end

function ShamanPower:CooldownBarStyleFlags(t)
	return self.CDBAR_STYLE[self:CooldownBarStyle(t)] or self.CDBAR_STYLE.normal
end

-- Grid on the cooldown bar (t: as CooldownBarStyle)
function ShamanPower:CooldownBarGridOn(t)
	return self:CooldownBarStyleFlags(t).grid or false
end

-- Grid: a flyout's choices shown for good (the open / close broadcasts leave them alone); arrow
-- ("box") flyouts keep their box shown, as the totem bar's Grid does
function ShamanPower:PinCooldownGrid(flyout)
	if InCombatLockdown() or not flyout then return end
	if flyout.box then
		UnregisterUnitWatch(flyout.box)
		flyout.box:Show()
	end
	for _, b in ipairs(flyout.buttons or {}) do
		b:SetAttribute("spGridPinned", true)
		b:Show()
	end
end

-- before a Grid flyout goes: its box opens and closes by itself again
function ShamanPower:UnpinCooldownGrid(flyout)
	if not (flyout and flyout.grid and flyout.box) or InCombatLockdown() then return end
	flyout.box:SetAttribute("unit", "none")
	RegisterUnitWatch(flyout.box)
	flyout.box:Hide()
end

-- Grid: a choice's marks, as the totem bar's Grid marks its totems: the assigned one edged in
-- gold, the one that is up edged in green (text: a shield's charges)
function ShamanPower:CooldownGridMark(b, assigned, up, text)
	local m = b.spGridMark
	if not m then
		m = { edges = {} }
		for i = 1, 4 do m.edges[i] = b:CreateTexture(nil, "OVERLAY", nil, 4) end
		m.edges[1]:SetPoint("TOPLEFT"); m.edges[1]:SetPoint("TOPRIGHT"); m.edges[1]:SetHeight(2)
		m.edges[2]:SetPoint("BOTTOMLEFT"); m.edges[2]:SetPoint("BOTTOMRIGHT"); m.edges[2]:SetHeight(2)
		m.edges[3]:SetPoint("TOPLEFT"); m.edges[3]:SetPoint("BOTTOMLEFT"); m.edges[3]:SetWidth(2)
		m.edges[4]:SetPoint("TOPRIGHT"); m.edges[4]:SetPoint("BOTTOMRIGHT"); m.edges[4]:SetWidth(2)
		m.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		self:AdoptSPFont(m.text, "timers")
		m.text:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
		m.text:SetTextColor(1, 1, 1)
		b.spGridMark = m
	end
	local show = assigned or up
	for i = 1, 4 do
		local e = m.edges[i]
		if show then
			if up then e:SetColorTexture(0.1, 1, 0.1, 1) else e:SetColorTexture(1, 0.82, 0, 1) end
			e:Show()
		else
			e:Hide()
		end
	end
	m.text:SetText(text or "")
end

-- The shield the button would cast: one picked in this fight (pendingShield: the button already casts it,
-- the saved choice lands when the fight ends), else the preferred one when you know it, else the first you know
function ShamanPower:AssignedShieldIndex()
	local pend = self.pendingShield
	local data = pend and self.ShieldSpells[pend]
	if data and PlayerKnowsSpellByID(data[1]) then return pend end
	local pref = self.opt and self.opt.preferredShield
	data = pref and self.ShieldSpells[pref]
	if data and PlayerKnowsSpellByID(data[1]) then return pref end
	for i, d in ipairs(self.ShieldSpells) do
		if PlayerKnowsSpellByID(d[1]) then return i end
	end
	return nil
end

-- A shield's place in ShieldSpells by the name a button casts (nil: not a shield, or unreadable)
function ShamanPower:ShieldIndexOfName(name)
	if not name or (issecretvalue and issecretvalue(name)) then return nil end
	for i, d in ipairs(self.ShieldSpells) do
		if SPCompat.SpellName(d[1]) == name then return i end
	end
	return nil
end

-- The shields you know (Lightning Shield, Water Shield): how many, and the one that isn't idx
function ShamanPower:KnownShieldCount()
	local n = 0
	for _, d in ipairs(self.ShieldSpells) do
		if SPCompat.SpellName(d[1]) and PlayerKnowsSpellByID(d[1]) then n = n + 1 end
	end
	return n
end

function ShamanPower:OtherShieldIndex(idx)
	for i, d in ipairs(self.ShieldSpells) do
		if i ~= idx and SPCompat.SpellName(d[1]) and PlayerKnowsSpellByID(d[1]) then return i end
	end
	return nil
end

-- A shield picked in a fight (flyout, Right-Click Casts Your Other Shield) lands when it ends: saved, and
-- everything that waited for the fight follows (AssignShield). Both end-of-fight handlers call this.
function ShamanPower:LandPendingShield()
	local idx = self.pendingShield
	if not idx or InCombatLockdown() then return end
	self:AssignShield(idx)
end

-- After a click that may have put another shield on the shield button: a flyout pick, or Right-Click Casts
-- Your Other Shield. Secure helpers changed the button's cast (in a fight too); this reads what it casts now.
-- The icon and the flyout follow at once; in a fight the saved choice waits for its end (pendingShield).
-- A click runs this twice (press and release): only the edge that acted changes anything.
-- ownClick: the shield button's own click, which counts only when it changed the shield (Right-Click Casts
-- Your Other Shield). A plain cast is no pick, also while a profile switched in this fight still has the
-- old profile's shield on the button (it goes on when the fight ends: SyncShieldButtonCast).
function ShamanPower:ShieldButtonChanged(ownClick)
	local btn = self.shieldButton
	if not btn then return end
	local idx = self:ShieldIndexOfName(btn:GetAttribute("spell1"))
	local seen = btn.spShieldSeen   -- what the button cast before (SetShieldButtonSpell, the last click)
	btn.spShieldSeen = idx
	if ownClick and seen and idx == seen then return end
	if not idx or idx == self:AssignedShieldIndex() then return end
	if InCombatLockdown() then
		self.pendingShield = idx
		self:FadeShieldFlyoutMarks()
		self:WakeCooldownBar()
		self:UpdateCooldownButtons()   -- the icon now (textures only), not at the next pass
	else
		self:AssignShield(idx)
	end
end

function ShamanPower:ShieldIndexOf(spellID)
	if not spellID then return nil end
	for i, d in ipairs(self.ShieldSpells) do
		if d[1] == spellID then return i end
	end
	return nil
end

-- a shield's icon by its place in ShieldSpells (looked up once)
function ShamanPower:ShieldIcon(idx)
	local d = idx and self.ShieldSpells[idx]
	if not d then return nil end
	self._shieldIcons = self._shieldIcons or {}
	local icon = self._shieldIcons[idx]
	if icon == nil then
		local _, _, found = GetSpellInfo(d[1])
		icon = found or false
		self._shieldIcons[idx] = icon
	end
	return icon or nil
end

-- The shield button casts shield `name` (out of combat): its cast click, and its other click while Swap
-- Left and Right Click fills that one with the cast
function ShamanPower:SetShieldButtonSpell(name)
	local btn = self.shieldButton
	if not btn or not name or InCombatLockdown() then return end
	btn:SetAttribute("spell1", name)
	if btn.spClickFilled then btn:SetAttribute("spell2", name) end
	btn.defaultShieldSpell = name
	btn.spShieldSeen = self:ShieldIndexOfName(name)   -- (ShieldButtonChanged)
end

-- A shield made the assigned one (Dynamic: the one you cast; a pick from the flyout): the button casts it,
-- saved (out of combat: a pick in a fight waits in pendingShield, see LandPendingShield). The game-drawn
-- shield display (WoW: Forever) has a slot for every shield, so nothing is built again for it here.
function ShamanPower:AssignShield(idx)
	local d = idx and self.ShieldSpells[idx]
	if not d or InCombatLockdown() then return end
	local spellName = SPCompat.SpellName(d[1])
	if not spellName then return end
	self.pendingShield = nil
	self:SetShieldButtonSpell(spellName)
	self.opt.preferredShield = idx
	self:ApplyShieldButtonClicks()   -- Right-Click Casts Your Other Shield: now the other one
	self:MarkShieldFlyout()          -- the flyout leaves out (arrows: fades) the new one
end

-- The shield button's cast follows the shield it shows, out of a fight: AssignedShieldIndex, the saved
-- choice while you know it, else the first shield you know. A profile switch in any style (Normal, Grid,
-- hover or arrow flyouts) and a talent change that unlearns or learns a shield (WoW: Forever: Water Shield
-- is a Restoration talent) come through here. The saved choice (opt.preferredShield) is never written
-- here, so a shield learned again goes back on the button. In a fight: nothing (the end of the fight and
-- the cooldown bar's next pass catch up). castOnly: the flyout is made again right after, not marked here.
function ShamanPower:SyncShieldButtonCast(castOnly)
	local btn = self.shieldButton
	if not btn or InCombatLockdown() then return end
	local idx = self:AssignedShieldIndex()
	local d = idx and self.ShieldSpells[idx]
	local name = d and SPCompat.SpellName(d[1])
	if name and btn:GetAttribute("spell1") ~= name then
		self:SetShieldButtonSpell(name)
		self:ApplyShieldButtonClicks()   -- Right-Click Casts Your Other Shield: the other one from this one
		if not castOnly then self:MarkShieldFlyout() end
	elseif not castOnly and (idx or 0) ~= self._shieldFlyoutMarked then
		self:MarkShieldFlyout()
	end
end

-- Which shield the button shows, whether it counts as up, which one shows above it (Normal), which
-- one in its corner (TotemTimers). activeIdx: the shield you have up (nil: none).
function ShamanPower:CooldownBarShieldView(activeIdx)
	local f = self:CooldownBarStyleFlags(1)
	local assigned = self:AssignedShieldIndex()
	-- (Dynamic adopts only a shield you know: one still up after a talent change took it away stays off
	-- the button, as SyncShieldButtonCast keeps it)
	if f.adopt and activeIdx and activeIdx ~= assigned and not InCombatLockdown()
		and PlayerKnowsSpellByID(self.ShieldSpells[activeIdx][1]) then
		self:AssignShield(activeIdx)
		assigned = activeIdx
	end
	if f.showsActive then
		local corner = (f.corner and activeIdx and assigned and activeIdx ~= assigned) and assigned or nil
		return activeIdx or assigned, activeIdx ~= nil, nil, corner
	end
	if activeIdx and activeIdx ~= assigned then return assigned, false, (not f.grid) and activeIdx or nil, nil end
	return assigned, activeIdx ~= nil, nil, nil
end

-- With an off-hand weapon (kept until the off-hand item changes)
function ShamanPower:HasOffHandWeapon()
	local id = GetInventoryItemID and GetInventoryItemID("player", 17)
	if issecretvalue and issecretvalue(id) then return self._ohWeapon or false end
	if id ~= self._ohItemID then
		self._ohItemID = id
		self._ohWeapon = (id ~= nil and self:CanDualWield()) or false
	end
	return self._ohWeapon
end

-- The off hand's assigned imbue: its own pick (a right-click with two weapons), else the main hand's
function ShamanPower:AssignedOffImbue(main)
	local o = self.opt and self.opt.preferredOffImbue
	if o and self:GetHighestRankImbue(o) then return o end
	return main
end

-- The imbue button's two casts: left the main hand's assigned imbue on the main hand, right the off
-- hand's on the off hand (Click Swap flips which mouse button is which, as before). Out of combat.
function ShamanPower:SetImbueButtonMacros()
	local btn = self.weaponImbueButton
	if not btn or InCombatLockdown() then return end
	local main = self:DefaultImbueIndex()
	local mainSpell = main and self:GetHighestRankImbue(main)
	if not mainSpell then return end
	local off = self:AssignedOffImbue(main)
	local offSpell = (off and self:GetHighestRankImbue(off)) or mainSpell
	btn:SetAttribute("type1", "macro")
	btn:SetAttribute("macrotext1", "/cast [@none] " .. mainSpell .. "\n/use 16\n/click StaticPopup1Button1")
	btn:SetAttribute("type2", "macro")
	btn:SetAttribute("macrotext2", "/cast [@none] " .. offSpell .. "\n/use 17\n/click StaticPopup1Button1")
	btn.currentImbueName = mainSpell
end

-- An imbue made a hand's assigned one (a pick, or Dynamic: the one you put on): out of combat
function ShamanPower:AssignImbue(hand, idx)
	if InCombatLockdown() or not idx then return end
	if hand == "off" then
		self.opt.preferredOffImbue = idx
		self.lastOffHandImbue = idx
	else
		self.opt.preferredImbue = idx
		self.lastMainHandImbue = idx
	end
	self:SetImbueButtonMacros()
end

-- Which imbue the button shows on each hand, whether each hand counts as up, which show above it
-- (Normal), which in its corner (TotemTimers). actualMain / actualOff: the imbue on each hand (nil: none).
function ShamanPower:CooldownBarImbueView(actualMain, actualOff)
	local f = self:CooldownBarStyleFlags(7)
	local dual = self:HasOffHandWeapon()
	local main = self:DefaultImbueIndex()
	local off = dual and self:AssignedOffImbue(main) or nil
	if f.adopt and not InCombatLockdown() then
		if actualMain and actualMain ~= main then
			self:AssignImbue("main", actualMain)
			main = actualMain
			if dual then off = self:AssignedOffImbue(main) end
		end
		if dual and actualOff and actualOff ~= off then
			self:AssignImbue("off", actualOff)
			off = actualOff
		end
	end
	if f.showsActive then
		if actualMain or actualOff then
			local corner
			if f.corner then
				if actualMain and actualMain ~= main then corner = main
				elseif dual and actualOff and actualOff ~= off then corner = off end
			end
			return actualMain, actualOff, actualMain ~= nil, actualOff ~= nil, nil, nil, corner
		end
		return main, nil, false, false, nil, nil, nil
	end
	local litMain = actualMain ~= nil and actualMain == main
	local litOff = dual and actualOff ~= nil and actualOff == off or false
	local above1 = (not f.grid and actualMain and actualMain ~= main) and actualMain or nil
	local above2 = (not f.grid and dual and actualOff and actualOff ~= off) and actualOff or nil
	return main, off, litMain, litOff, above1, above2, nil
end

-- Where the one that is up shows: on the button's flyout side, as a totem's shows on the totem
-- bar's flyout side (the flyout opens over it, as there)
function ShamanPower:CooldownAboveAnchor(t)
	local cdLayout = self.opt.cdbarLayout or self.opt.layout
	local isLocked = (self.opt.cooldownBarLocked ~= false)
	if cdLayout == "Horizontal" then
		local flyoutDir = self:CdItemOpt(t, "flyoutDirection")
		local goBelow = (flyoutDir == "below") or (flyoutDir == "auto" and isLocked)
		if goBelow then return "TOP", "BOTTOM", 0, -2 end
		return "BOTTOM", "TOP", 0, 2
	end
	local isVerticalLeft = (cdLayout == "VerticalLeft")
	local goRight
	if isLocked then goRight = isVerticalLeft else goRight = not isVerticalLeft end
	if goRight then return "LEFT", "RIGHT", 2, 0 end
	return "RIGHT", "LEFT", -2, 0
end

-- The one that is up, above the button (Normal style), as a totem button shows a different totem
-- that is down: the button grays out to half opacity when nothing on it is up (dim). icon2: an
-- off-hand imbue beside it. r, g, b: its edge. text: a shield's charges.
function ShamanPower:CooldownBarAbove(btn, icon1, icon2, r, g, b, text, dim)
	local a = btn.spAbove
	if not (icon1 or icon2) then
		if a and a:IsShown() then a:Hide() end
		if btn.spAboveDim then
			btn.spAboveDim = nil
			btn.icon:SetAlpha(1)
			if btn.icon2 then btn.icon2:SetAlpha(1) end
		end
		return
	end
	if not a then
		a = CreateFrame("Frame", nil, btn)
		a:SetFrameLevel(btn:GetFrameLevel() + 5)
		a.bg = a:CreateTexture(nil, "BACKGROUND")
		a.bg:SetAllPoints()
		a.bg:SetColorTexture(0, 0, 0, 0.7)
		a.i1 = a:CreateTexture(nil, "ARTWORK")
		a.i2 = a:CreateTexture(nil, "ARTWORK")
		a.edges = {}
		for i = 1, 4 do a.edges[i] = a:CreateTexture(nil, "BORDER") end
		a.edges[1]:SetPoint("TOPLEFT"); a.edges[1]:SetPoint("TOPRIGHT"); a.edges[1]:SetHeight(2)
		a.edges[2]:SetPoint("BOTTOMLEFT"); a.edges[2]:SetPoint("BOTTOMRIGHT"); a.edges[2]:SetHeight(2)
		a.edges[3]:SetPoint("TOPLEFT"); a.edges[3]:SetPoint("BOTTOMLEFT"); a.edges[3]:SetWidth(2)
		a.edges[4]:SetPoint("TOPRIGHT"); a.edges[4]:SetPoint("BOTTOMRIGHT"); a.edges[4]:SetWidth(2)
		a.text = a:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		self:AdoptSPFont(a.text, "timers")
		a.text:SetPoint("BOTTOMRIGHT", a, "BOTTOMRIGHT", -1, 1)
		a.text:SetTextColor(1, 1, 1)
		btn.spAbove = a
	end
	local size = btn:GetWidth() or 22
	if a.spSize ~= size then a.spSize = size; a:SetSize(size, size) end
	local p, rp, ox, oy = self:CooldownAboveAnchor(btn.cooldownType)
	if a.spAnchor ~= p then
		a.spAnchor = p
		a:ClearAllPoints()
		a:SetPoint(p, btn, rp, ox, oy)
	end
	a.i1:ClearAllPoints(); a.i2:ClearAllPoints()
	if icon1 and icon2 then
		a.i1:SetPoint("TOPLEFT", 2, -2); a.i1:SetPoint("BOTTOMRIGHT", a, "BOTTOM", 0, 2)
		a.i1:SetTexture(icon1); a.i1:SetTexCoord(0.08, 0.50, 0.08, 0.92)
		a.i2:SetPoint("TOPLEFT", a, "TOP", 0, -2); a.i2:SetPoint("BOTTOMRIGHT", -2, 2)
		a.i2:SetTexture(icon2); a.i2:SetTexCoord(0.50, 0.92, 0.08, 0.92)
		a.i2:Show()
	else
		a.i1:SetPoint("TOPLEFT", 2, -2); a.i1:SetPoint("BOTTOMRIGHT", -2, 2)
		a.i1:SetTexture(icon1 or icon2); a.i1:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		a.i2:Hide()
	end
	for i = 1, 4 do a.edges[i]:SetColorTexture(r or 1, g or 0.82, b or 0, 1) end
	a.text:SetText(text or "")
	a:Show()
	if (dim and true or nil) ~= btn.spAboveDim then
		btn.spAboveDim = dim and true or nil
		local alpha = dim and 0.5 or 1
		btn.icon:SetAlpha(alpha)
		if btn.icon2 then btn.icon2:SetAlpha(alpha) end
	end
end

-- The assigned one in the button's corner (TotemTimers Style), as on a totem button
function ShamanPower:CooldownBarCorner(btn, icon)
	local c = btn.spCorner
	if not icon then
		if c and c:IsShown() then c:Hide() end
		return
	end
	if not c then
		c = CreateFrame("Frame", nil, btn)
		c:SetSize(12, 12)
		c:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
		c:SetFrameLevel(btn:GetFrameLevel() + 10)
		local bg = c:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(0, 0, 0, 0.8)
		c.icon = c:CreateTexture(nil, "ARTWORK")
		c.icon:SetPoint("TOPLEFT", 1, -1)
		c.icon:SetPoint("BOTTOMRIGHT", -1, 1)
		c.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		btn.spCorner = c
	end
	c.icon:SetTexture(icon)
	c:Show()
end

-- The shield flyout made again (Grid turned on or off, a shield learned, a profile): out of combat only
function ShamanPower:RebuildShieldFlyout()
	if InCombatLockdown() then return end
	local flyout = self.shieldFlyout
	self:UnpinCooldownGrid(flyout)
	if flyout then
		for _, btn in ipairs(flyout.buttons or {}) do
			btn:Hide()
			btn:SetParent(nil)
		end
		self.shieldFlyout = nil
	end
	self:CreateShieldFlyout()
end

-- ---------------------------------------------------------------------------
-- The shield flyout in a fight (GitHub #11). A pick makes that shield the button's shield at once, in a
-- fight too, the way a totem flyout's assign click does (CreateTotemFlyout): each click is a macro that
-- presses hidden secure "attribute" helpers, and those write the shield button's own attributes:
--   SPFSS<i>  its cast (spell1) = shield i
--   SPFSF<i>  its other click (spell2), while Swap Left and Right Click fills that click with the cast
--   SPFSX<i>  its right-click's macro while Right-Click Casts Your Other Shield is on: the shield that isn't i
--   SPFUS     (hover flyouts) the totem flyouts' re-sort (FlyoutResortHelper): every flyout button learns
--             the button's new spell1, the rest are packed from the button, and the flyout closes
-- Only attribute helpers and that click snippet: a macro button pressed from a macro does not run. The cast
-- click is the helpers and "/cast <shield>", the other click the helpers alone. PostClick then reads what
-- the button casts (ShieldButtonChanged): the icon follows at once, the saved choice when the fight ends
-- (pendingShield). So the flyout holds every shield you know: hover flyouts leave out the one a click on
-- the button casts (isCurrentAssignment, the totem flyouts' secure show), arrow ("box") flyouts keep it,
-- faded, and Grid pins them all. Indexes are ShieldSpells' (1 Lightning Shield, 2 Water Shield).
-- ---------------------------------------------------------------------------

-- Right-Click Casts Your Other Shield (Cooldown Bar > Items) does something right now: switched on, a
-- second shield known, and the right-click free (Flyout Requires Right-Click opens the flyout with it)
function ShamanPower:ShieldOtherClickActive()
	return (self.opt and self:CdItemOpt(1, "rightClickOther") and not self:FlyoutOpensOnRightClick()
		and self:KnownShieldCount() >= 2) and true or false
end

-- The macro lines that make shield idx the button's shield: its cast, plus what the button's other click
-- does right now (the Swap fill, or the other-shield macro)
function ShamanPower:ShieldAssignLines(idx)
	local btn = self.shieldButton
	local lines = "/click SPFSS" .. idx
	if btn and btn.spShieldOther then
		lines = lines .. "\n/click SPFSX" .. idx
	elseif btn and btn.spClickFilled then
		lines = lines .. "\n/click SPFSF" .. idx
	end
	return lines
end

-- The button's right-click while shield idx is on it (Right-Click Casts Your Other Shield): cast the other
-- one and make it the button's shield, its own right-click then casting idx again (hover flyouts re-sort)
function ShamanPower:ShieldOtherMacro(idx)
	local other = self:OtherShieldIndex(idx)
	local name = other and SPCompat.SpellName(self.ShieldSpells[other][1])
	if not name then return nil end
	local flyout = self.shieldFlyout
	local tail = (flyout and not flyout.box and not flyout.grid) and "\n/click SPFUS" or ""
	return "/click SPFSS" .. other .. "\n/click SPFSX" .. other .. "\n/cast " .. name .. tail
end

-- The shield button's clicks, from the settings (out of combat; one asked for in a fight waits for its end):
--   its cast (type1 / spell1) is set where it is built, by AssignShield and by the helpers;
--   Right-Click Casts Your Other Shield: the right-click is the other-shield macro. Swap Left and Right
--     Click makes it the left-click by flipping the mouse, as on the imbue button (keys press the cast:
--     KeyMouseButton);
--   else Swap fills the right-click with the cast, as before (spFillOtherClick).
-- The helpers and the flyout's macros follow (ApplyShieldPickMacros).
function ShamanPower:ApplyShieldButtonClicks()
	local btn = self.shieldButton
	if not btn then return end
	if InCombatLockdown() then self._shieldClicksPending = true return end
	self._shieldClicksPending = nil
	local swapped = self:ClicksSwapped()
	local idx = self:ShieldIndexOfName(btn:GetAttribute("spell1")) or self:AssignedShieldIndex()
	local macro = self:ShieldOtherClickActive() and idx and self:ShieldOtherMacro(idx)
	local wasFlipped = btn.spClickFlipped and true or false
	if macro then
		spFlipClicks(btn, swapped)
		if btn.spClickFilled then
			btn.spClickFilled = nil
			spSetAttr(btn, "spell2", nil)
		end
		spSetAttr(btn, "type2", "macro")
		spSetAttr(btn, "macrotext2", macro)
		btn.spShieldOther = true
	else
		if btn.spShieldOther then   -- switched off, or nothing to switch to: the right-click is free again
			spSetAttr(btn, "type2", nil)
			spSetAttr(btn, "macrotext2", nil)
			btn.spShieldOther = nil
		end
		spFlipClicks(btn, false)
		if CLICK_SWAP_SUPPORTED then spFillOtherClick(btn, swapped and not self:FlyoutOpensOnRightClick()) end
	end
	self:ApplyShieldPickMacros()
	-- the button flipped (or back): its key presses the other mouse button now (KeyMouseButton). A frame
	-- later, so a call from SetupKeybindings itself (ApplyClickSwap) is not entered twice.
	if wasFlipped ~= (btn.spClickFlipped and true or false) then
		C_Timer.After(0, function() ShamanPower:SetupKeybindings() end)
	end
end

-- The helpers, and the flyout's click macros for what the button's clicks do right now (out of combat).
-- A flyout button's cast click (type1) = the helpers + /cast (arrows: + the close, as every pick there,
-- ApplyFlyoutPickMacros); its other click (type2) = the helpers alone (hover: re-sort and close; arrows:
-- close, as a totem's assign click). Swap Left and Right Click flips their mouse (ApplyClickSwap), never
-- these attributes.
function ShamanPower:ApplyShieldPickMacros()
	local btn = self.shieldButton
	if not btn or InCombatLockdown() or self:KnownShieldCount() < 2 then return end
	for i, d in ipairs(self.ShieldSpells) do
		local name = SPCompat.SpellName(d[1])
		if name and PlayerKnowsSpellByID(d[1]) then
			local S = self:FlyoutAssignHelper("SPFSS" .. i, btn)
			S:SetAttribute("type", "attribute")
			S:SetAttribute("attribute-frame", btn)
			S:SetAttribute("attribute-name", "spell1")
			S:SetAttribute("attribute-value", name)
			local F = self:FlyoutAssignHelper("SPFSF" .. i, btn)
			F:SetAttribute("type", "attribute")
			F:SetAttribute("attribute-frame", btn)
			F:SetAttribute("attribute-name", "spell2")
			F:SetAttribute("attribute-value", name)
			local X = self:FlyoutAssignHelper("SPFSX" .. i, btn)
			X:SetAttribute("type", "attribute")
			X:SetAttribute("attribute-frame", btn)
			X:SetAttribute("attribute-name", "macrotext2")
			X:SetAttribute("attribute-value", self:ShieldOtherMacro(i))
		end
	end
	local flyout = self.shieldFlyout
	if not flyout then return end
	local hover = not flyout.box and not flyout.grid
	if hover then self:FlyoutResortHelper("S", btn) end
	for _, fb in ipairs(flyout.buttons or {}) do
		local assign = self:ShieldAssignLines(fb.shieldIndex)
		local cast = assign .. "\n/cast " .. fb.spellName
		if flyout.box then
			fb.spPick = { ["1"] = cast }   -- finished by ApplyFlyoutPickMacros (Close Flyout After Casting From It)
			assign = assign .. "\n/click SPFCS\n/click SPFRS"
		elseif hover then
			cast, assign = cast .. "\n/click SPFUS", assign .. "\n/click SPFUS"
		end
		fb:SetAttribute("type1", "macro")
		fb:SetAttribute("macrotext1", cast)
		fb:SetAttribute("type2", "macro")
		fb:SetAttribute("macrotext2", assign)
	end
	if flyout.box then self:ApplyFlyoutPickMacros() end
end

-- Arrow ("box") flyouts keep the shield that is on the button in the list: its icon is drawn faded, as a
-- box-mode totem flyout draws its assigned totem. A texture, so it follows every pick in a fight too.
-- (Hover flyouts leave it out; Grid edges it in gold, UpdateCooldownButtons.)
function ShamanPower:FadeShieldFlyoutMarks()
	local flyout = self.shieldFlyout
	if not (flyout and flyout.box) or flyout.grid then return end
	local cur = self:AssignedShieldIndex()
	for _, fb in ipairs(flyout.buttons or {}) do
		if fb.icon then
			local on = fb.shieldIndex == cur
			fb.icon:SetAlpha(on and 0.3 or 1)
			fb.icon:SetDesaturated(on and true or false)
		end
	end
end

-- The flyout follows the shield on the button, out of a fight (in one: the helpers' re-sort and the fade
-- above): hover flyouts leave it out and pack the rest from the button, arrow flyouts fade it.
function ShamanPower:MarkShieldFlyout()
	local cur = self:AssignedShieldIndex()
	self._shieldFlyoutMarked = cur or 0
	local flyout = self.shieldFlyout
	if not flyout then return end
	self:FadeShieldFlyoutMarks()
	if InCombatLockdown() then return end
	local hover = not flyout.box and not flyout.grid
	local open = false
	for _, fb in ipairs(flyout.buttons or {}) do
		if hover then fb:SetAttribute("isCurrentAssignment", fb.shieldIndex == cur) end
		if fb:IsShown() then open = true end
	end
	self:LayoutShieldFlyout()
	if hover and open then   -- left open while the shield changed: the new set, as opening it shows it
		for _, fb in ipairs(flyout.buttons) do fb:SetShown(fb.shieldIndex ~= cur) end
	end
end

-- What a shield's two clicks in the flyout do, the same in and out of fights (Swap Left and Right Click
-- trades the labels, ClickLabel)
function ShamanPower:ShieldFlyoutTooltipLines(fb)
	local btn = self.shieldButton
	if btn and self:ShieldIndexOfName(btn:GetAttribute("spell1")) == fb.shieldIndex then
		local r, g, b = 0.5, 0.5, 0.5
		if GRAY_FONT_COLOR and GRAY_FONT_COLOR.GetRGB then r, g, b = GRAY_FONT_COLOR:GetRGB() end
		GameTooltip:AddLine("On the shield button now", r, g, b)
		GameTooltip:AddLine(self:ClickLabel(true) .. " Cast it", 1, 1, 1)
	else
		GameTooltip:AddLine(self:ClickLabel(true) .. " Cast it and make it the button's shield", 1, 1, 1)
		GameTooltip:AddLine(self:ClickLabel(false) .. " Make it the button's shield (no cast)", 1, 1, 1)
	end
end

function ShamanPower:CreateShieldFlyout()
	if self.shieldFlyout then return end
	if InCombatLockdown() then return end
	if not self.shieldButton then return end

	-- Every shield you know (see above); Grid: pinned open as a row beside the button. With only one known
	-- there is nothing to pick: no flyout.
	local grid = self:CooldownBarGridOn(1)
	self._shieldFlyoutGrid = grid and 1 or 0
	if self:KnownShieldCount() < 2 then
		if self.boxFlyouts then self.boxFlyouts.S = nil end
		self._shieldFlyoutMarked = self:AssignedShieldIndex() or 0
		self:ApplyShieldButtonClicks()
		return
	end

	local parentButton = self.shieldButton
	local buttonSize = self:CooldownFlyoutButtonSize(1)
	local spacing = 0  -- No gap between buttons for smooth mouse movement

	local flyout = {
		buttons = {},
		buttonSize = buttonSize,
		spacing = spacing,
		shieldButton = parentButton
	}

	-- Box mode: same click-to-open arrows as the totem flyouts
	local buttonParent = parentButton
	if spFlyoutBoxMode() then
		flyout.isCdbarFlyout, flyout.anchorButton, flyout.artIndex, flyout.cdItemType = true, parentButton, 5, 1
		buttonParent = self:EnsureFlyoutBox("S", parentButton, flyout,
			function() ShamanPower:LayoutShieldFlyout() end) or parentButton
	end

	-- Create buttons for each known shield as children of the shield button
	for i, shieldData in ipairs(self.ShieldSpells) do
		local spellID = shieldData[1]
		local spellName = SPCompat.SpellName(spellID)

		-- Check if player knows this shield
		if spellName and PlayerKnowsSpellByID(spellID) then
			local name, _, icon = GetSpellInfo(spellID)

			-- Create as CHILD of shield button for ChildUpdate to work
			local btn = CreateFrame("Button", "ShamanPowerShieldFlyout" .. i, buttonParent,
				"SecureActionButtonTemplate, SecureHandlerEnterLeaveTemplate, SecureHandlerShowHideTemplate")
			btn:SetParent(buttonParent)
			btn:SetSize(buttonSize, buttonSize)
			btn:SetFrameStrata("DIALOG")
			-- Both edges: secure clicks are gated on the ActionButtonUseKeyDown
			-- CVar, so a button registered for only one edge silently never
			-- fires for anyone whose setting points the other way. Every other
			-- flyout button here already registers both.
			btn:RegisterForClicks("AnyUp", "AnyDown")
			btn:Hide()
			btn:SetIgnoreParentAlpha(true)  -- Independent opacity from parent button

			local iconTex = btn:CreateTexture(nil, "ARTWORK")
			iconTex:SetAllPoints()
			iconTex:SetTexture(icon)
			iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			btn.icon = iconTex

			-- Highlight texture
			local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
			highlight:SetAllPoints()
			highlight:SetColorTexture(1, 1, 1, 0.3)

			-- SECURE HANDLERS (WORK IN COMBAT): the totem flyouts' own. The shield button's enter (or
			-- right-click) broadcasts "show": every shield but the one it casts (isCurrentAssignment) shows.
			-- After a pick SPFUS broadcasts "assignment" (from the button's new spell1) and "relayout" (the
			-- rest packed from the button, by the attributes LayoutShieldFlyout leaves on it).
			ShamanPower:SetSnippet(btn, "_childupdate-show", SP_FLYOUT_CHILD_SHOW)
			ShamanPower:SetSnippet(btn, "_childupdate-assignment", SP_FLYOUT_CHILD_ASSIGNMENT)
			ShamanPower:SetSnippet(btn, "_childupdate-relayout", SP_FLYOUT_CHILD_RELAYOUT)

			-- SECURE HANDLER: Check parent on leave (WORKS IN COMBAT)
			ShamanPower:SetSnippet(btn, "_onleave", SP_SECURE_ONLEAVE_PARENT)
			btn:SetAttribute("spFlyoutProtocol", true)  -- lets sibling leave snippets tell flyout buttons from decoration
			btn:SetAttribute("mySpell", spellName)
			btn:SetAttribute("myTotemIndex", i)           -- (the re-sort keeps this order)
			btn:SetAttribute("isFlyoutButton", true)
			-- the clicks are macros of the helpers: ApplyShieldPickMacros
			btn:SetAttribute("spell", nil)

			-- After either click the secure part is done, in a fight too (the helpers): the icon and the
			-- flyout follow, the saved choice too (in a fight: when it ends). Out of a fight a hover flyout
			-- closes here as well (an arrow flyout's macros close it).
			btn:HookScript("PostClick", function(self, button)
				if button ~= "LeftButton" and button ~= "RightButton" then return end
				local flyoutData = ShamanPower.shieldFlyout
				if not InCombatLockdown() and flyoutData and not flyoutData.box and not flyoutData.grid then
					for _, flyoutBtn in ipairs(flyoutData.buttons) do flyoutBtn:Hide() end
				end
				ShamanPower:ShieldButtonChanged()
			end)

			-- Tooltip (Lua hooks work alongside secure handlers)
			btn:HookScript("OnEnter", function(self)
				if not ShamanPower.opt.ShowTooltips then return end
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:SetSpellByID(SPCompat.HighestKnownRank and SPCompat.HighestKnownRank(spellID) or spellID)
				GameTooltip:AddLine(" ")
				ShamanPower:ShieldFlyoutTooltipLines(self)
				GameTooltip:Show()
			end)
			btn:HookScript("OnLeave", function()
				GameTooltip:Hide()
			end)

			btn.spellID = spellID
			btn.spellName = spellName
			btn.shieldIndex = i
			table.insert(flyout.buttons, btn)
		end
	end

	flyout.grid = grid or nil
	self.shieldFlyout = flyout
	self:UpdateCooldownFlyoutOpacity()   -- new buttons take the shield's own Flyout Opacity (every rebuild)
	self:ApplyClickSwap()           -- Swap Left and Right Click flips their mouse (WoW: Forever)
	self:ApplyShieldButtonClicks()  -- the button's clicks, the helpers and these buttons' macros
	self:MarkShieldFlyout()         -- leave out (arrows: fade) the one on the button, and lay them out
	if grid then self:PinCooldownGrid(flyout) end
end

-- Layout shield flyout buttons (called after creation and when layout changes)
-- Buttons are children of shieldButton, positioned relative to parent. Out of combat: the arrows' combat
-- layout is placed as the fight starts, before the lock (setCombatLayout).
function ShamanPower:LayoutShieldFlyout()
	local flyout = self.shieldFlyout
	if not flyout or InCombatLockdown() then return end

	local buttons = flyout.buttons
	if not buttons or #buttons == 0 then return end

	local shieldButton = flyout.shieldButton
	if not shieldButton then return end

	local buttonSize = flyout.buttonSize
	local spacing = flyout.spacing
	local lead = spacing + (flyout.leadGap or 0)   -- box mode leaves room for the arrow tab in combat
	-- a hover flyout leaves out the shield the button casts: only the rest take a place, packed from the
	-- button (the one it casts sits in the first place, hidden). Arrows and Grid: every one in order.
	local hover = not flyout.box and not flyout.grid
	local cur = hover and self:AssignedShieldIndex()

	-- Determine flyout direction based on CD bar layout
	local cdLayout = self.opt.cdbarLayout or self.opt.layout
	local isHorizontalBar = (cdLayout == "Horizontal")
	local isVerticalLeft = (cdLayout == "VerticalLeft")
	local isLocked = (self.opt.cooldownBarLocked ~= false)

	-- For horizontal bar: flyout goes vertical
	-- For vertical bar: flyout goes horizontal
	local flyoutIsHorizontal = not isHorizontalBar
	local goRight, goBelow = false, false

	if flyoutIsHorizontal then
		-- When locked to totem bar, go OPPOSITE direction to avoid clipping
		-- When unlocked, go same direction as layout
		if isLocked then
			-- Locked: opposite direction
			goRight = isVerticalLeft  -- VerticalLeft -> go right, VerticalRight -> go left
		else
			-- Unlocked: same direction as layout
			goRight = not isVerticalLeft  -- VerticalLeft -> go left, VerticalRight -> go right
		end
		flyout.arrowDir = goRight and "right" or "left"
	else
		-- Vertical flyout: buttons extend upward or downward based on option
		local flyoutDir = self:CdItemOpt(1, "flyoutDirection")   -- (the shield's own: ShamanPowerCdItems.lua)

		-- When "auto" and locked to totem bar, go below (to avoid clipping into totem icons)
		-- When "auto" and unlocked, go above
		goBelow = (flyoutDir == "below") or (flyoutDir == "auto" and isLocked)
		flyout.arrowDir = goBelow and "bottom" or "top"
	end

	local slot = 0
	for _, btn in ipairs(buttons) do
		local n = 0
		if not (hover and btn.shieldIndex == cur) then n = slot; slot = slot + 1 end
		local off = lead + n * (buttonSize + spacing)
		btn:ClearAllPoints()
		if flyoutIsHorizontal then
			if goRight then
				btn:SetPoint("LEFT", shieldButton, "RIGHT", off, 0)    -- Extend to the RIGHT
			else
				btn:SetPoint("RIGHT", shieldButton, "LEFT", -off, 0)   -- Extend to the LEFT
			end
		elseif goBelow then
			btn:SetPoint("TOP", shieldButton, "BOTTOM", 0, -off)     -- Extend downward
		else
			btn:SetPoint("BOTTOM", shieldButton, "TOP", 0, off)      -- Extend upward
		end
	end

	-- what the secure re-sort (SP_FLYOUT_CHILD_RELAYOUT, pressed by SPFUS after a pick in a fight) reads
	if hover then
		shieldButton:SetAttribute("flyoutButtonSize", buttonSize)
		shieldButton:SetAttribute("flyoutSpacing", spacing)
		shieldButton:SetAttribute("flyoutIsHorizontal", flyoutIsHorizontal)
		shieldButton:SetAttribute("isVerticalLeft", flyoutIsHorizontal and not goRight)
		shieldButton:SetAttribute("flyoutGoesBelow", (not flyoutIsHorizontal) and goBelow)
		shieldButton:SetAttribute("spSecureResort", true)
	end

	self:SyncCdbarFlyout(flyout)
end

-- Show shield flyout (for backward compatibility, mostly handled by secure handlers now)
function ShamanPower:ShowShieldFlyout()
	if not self.shieldFlyout then
		self:CreateShieldFlyout()
	end
	-- Layout is handled in CreateShieldFlyout and LayoutShieldFlyout
	-- Show/hide is handled by secure handlers (_onenter/_onleave/_childupdate-show)
end

-- Create the flyout menu for weapon imbues (combat-functional architecture)
-- Flyout buttons are parented directly to weaponImbueButton for ChildUpdate to work
function ShamanPower:CreateWeaponImbueFlyout()
	if self.weaponImbueFlyout then return end
	if InCombatLockdown() then return end
	if not self.weaponImbueButton then return end

	local parentButton = self.weaponImbueButton
	local buttonSize = self:CooldownFlyoutButtonSize(7)
	local spacing = 0  -- No gap between buttons for smooth mouse movement

	-- Every imbue you know except what the button shows (both halves of a split icon), as a totem
	-- flyout leaves out the totem on its button. Nothing else known: no flyout.
	local grid = self:CooldownBarGridOn(7)
	local shown1, shown2 = self:ImbuesShownOnButton()
	self._imbueFlyoutKey = shown1 * 10 + shown2 + (grid and 1000 or 0)
	if grid then shown1, shown2 = -1, -1 end   -- Grid: every imbue, pinned open as a row beside the button
	local others = 0
	for imbueIndex = 1, 4 do
		if imbueIndex ~= shown1 and imbueIndex ~= shown2 and self:GetHighestRankImbue(imbueIndex) then others = others + 1 end
	end
	if others == 0 or (grid and others < 2) then
		if self.boxFlyouts then self.boxFlyouts.I = nil end
		return
	end

	local flyout = {
		buttons = {},
		buttonSize = buttonSize,
		spacing = spacing,
		imbueButton = parentButton,
	}

	-- Box mode: same click-to-open arrows as the totem flyouts
	local buttonParent = parentButton
	if spFlyoutBoxMode() then
		flyout.isCdbarFlyout, flyout.anchorButton, flyout.artIndex, flyout.cdItemType = true, parentButton, 5, 7
		buttonParent = self:EnsureFlyoutBox("I", parentButton, flyout,
			function() ShamanPower:LayoutWeaponImbueFlyout() end) or parentButton
	end

	-- Create buttons for each known imbue as children of the imbue button
	for imbueIndex = 1, 4 do
		local spellName = imbueIndex ~= shown1 and imbueIndex ~= shown2 and self:GetHighestRankImbue(imbueIndex)
		if spellName then
			-- Create as CHILD of imbue button for ChildUpdate to work
			local btn = CreateFrame("Button", "ShamanPowerImbueFlyout" .. imbueIndex, buttonParent,
				"SecureActionButtonTemplate, SecureHandlerEnterLeaveTemplate, SecureHandlerShowHideTemplate")
			btn:SetParent(buttonParent)
			btn:SetSize(buttonSize, buttonSize)
			btn:SetFrameStrata("DIALOG")
			btn:RegisterForClicks("LeftButtonUp", "LeftButtonDown", "RightButtonUp", "RightButtonDown")
			btn:Hide()
			btn:SetIgnoreParentAlpha(true)  -- Independent opacity from parent button

			-- SECURE HANDLER: Respond to parent's ChildUpdate (WORKS IN COMBAT)
			ShamanPower:SetSnippet(btn, "_childupdate-show", [[
				if self:GetAttribute("spGridPinned") then return end   -- Grid: always shown
				if message then
					self:Show()
				else
					self:Hide()
				end
			]])

			-- SECURE HANDLER: Check parent on leave (WORKS IN COMBAT)
			ShamanPower:SetSnippet(btn, "_onleave", SP_SECURE_ONLEAVE_PARENT)
			btn:SetAttribute("spFlyoutProtocol", true)  -- lets sibling leave snippets tell flyout buttons from decoration

			-- Click to cast imbue spell (left=main hand, right=off hand)
			local mainHandMacro = "/cast [@none] " .. spellName .. "\n/use 16\n/click StaticPopup1Button1"
			local offHandMacro = "/cast [@none] " .. spellName .. "\n/use 17\n/click StaticPopup1Button1"
			if flyout.box then
				btn.spPick = { ["1"] = mainHandMacro, ["2"] = offHandMacro }   -- finished by ApplyFlyoutPickMacros
			end
			btn:SetAttribute("type1", "macro")
			btn:SetAttribute("macrotext1", mainHandMacro)
			btn:SetAttribute("type2", "macro")
			btn:SetAttribute("macrotext2", offHandMacro)

			-- Icon
			local iconTex = btn:CreateTexture(nil, "ARTWORK")
			iconTex:SetAllPoints()
			iconTex:SetTexture(self.WeaponIcons[imbueIndex])
			iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			btn.icon = iconTex

			-- Highlight
			local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
			highlight:SetAllPoints()
			highlight:SetColorTexture(1, 1, 1, 0.3)

			-- Hide flyout after click
			btn:HookScript("PostClick", function(self, button)
				-- Hide flyout buttons only if NOT in combat (in combat, secure handler handles it)
				if not InCombatLockdown() then
					local flyoutData = ShamanPower.weaponImbueFlyout
					if flyoutData and flyoutData.box and not flyoutData.grid then
						ShamanPower:FlyoutFallbackSetShown(flyoutData.imbueButton, false)
					elseif flyoutData and flyoutData.buttons and not flyoutData.grid then
						for _, flyoutBtn in ipairs(flyoutData.buttons) do
							flyoutBtn:Hide()
						end
					end
				end
				-- In combat: flyout will close when mouse leaves (via secure _onleave handler)

				-- The pick is that hand's assigned imbue: left-click the main hand, right-click the off hand (with
				-- no off-hand weapon a right-click lands on the main hand too, so it is the main hand's). In a
				-- fight the button's casts change when it ends (the bar is made again then).
				local hand = (ShamanPower:LogicalButton(self, button) == "LeftButton" or not ShamanPower:HasOffHandWeapon()) and "main" or "off"
				if InCombatLockdown() then
					if hand == "main" then
						ShamanPower.lastMainHandImbue, ShamanPower.opt.preferredImbue = imbueIndex, imbueIndex
					else
						ShamanPower.lastOffHandImbue, ShamanPower.opt.preferredOffImbue = imbueIndex, imbueIndex
					end
					ShamanPower._cdBarRebuildPending = true
				else
					ShamanPower:AssignImbue(hand, imbueIndex)
				end
			end)

			-- Tooltip (Lua hooks work alongside secure handlers)
			btn:HookScript("OnEnter", function(self)
				if not ShamanPower.opt.ShowTooltips then return end
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:SetSpellByID(SPCompat.HighestKnownRank and SPCompat.HighestKnownRank(ShamanPower.WeaponImbueSpells[imbueIndex]) or ShamanPower.WeaponImbueSpells[imbueIndex])
				GameTooltip:AddLine(" ")
				GameTooltip:AddLine(ShamanPower:ClickLabel(true) .. " Apply to Main Hand (sets default)", 1, 1, 1)
				if ShamanPower:CanDualWield() then
					GameTooltip:AddLine(ShamanPower:ClickLabel(false) .. " Apply to Off Hand", 1, 1, 1)
				end
				GameTooltip:Show()
			end)
			btn:HookScript("OnLeave", function()
				GameTooltip:Hide()
			end)

			btn.imbueIndex = imbueIndex
			btn.spellName = spellName
			table.insert(flyout.buttons, btn)
		end
	end

	flyout.grid = grid or nil
	self.weaponImbueFlyout = flyout
	self:UpdateCooldownFlyoutOpacity()   -- new buttons take the imbue's own Flyout Opacity (every rebuild)
	if flyout.box then self:ApplyFlyoutPickMacros() end
	self:ApplyClickSwap()

	-- Layout the flyout buttons
	self:LayoutWeaponImbueFlyout()
	if grid then self:PinCooldownGrid(flyout) end
end

-- What the imbue button shows (its flyout leaves that out): the main hand's and the off hand's (0: none,
-- or the same as the main hand's), by the style's view (CooldownBarImbueView)
function ShamanPower:ImbuesShownOnButton()
	if self._imbueShown1 then return self._imbueShown1, self._imbueShown2 or 0 end
	local hasMain, _, _, mainID, hasOff, _, _, offID = GetWeaponEnchantInfo()
	if issecretvalue and (issecretvalue(hasMain) or issecretvalue(hasOff)) then return self:DefaultImbueIndex() or 0, 0 end
	local actualMain = hasMain and (self.EnchantIDToImbue[mainID] or self.lastMainHandImbue or 1) or nil
	local actualOff = hasOff and (self.EnchantIDToImbue[offID] or self.lastOffHandImbue or 2) or nil
	local viewMain, viewOff = self:CooldownBarImbueView(actualMain, actualOff)
	local first = viewMain or viewOff or 0
	return first, (viewOff and viewOff ~= first) and viewOff or 0
end

-- The icon just drawn on the imbue button (UpdateCooldownButtons): the flyout is made again, out of
-- a fight, when that changes, so it never also offers what the button shows. In a fight it waits.
function ShamanPower:NoteImbuesShown(shown1, shown2)
	self._imbueShown1, self._imbueShown2 = shown1 or 0, shown2 or 0
	local key = self._imbueShown1 * 10 + self._imbueShown2 + (self:CooldownBarGridOn(7) and 1000 or 0)
	if key ~= self._imbueFlyoutKey and not InCombatLockdown() then
		self:RebuildWeaponImbueFlyout()
	end
end

-- The imbue flyout made again (what the button shows changed): out of combat only
function ShamanPower:RebuildWeaponImbueFlyout()
	if InCombatLockdown() then return end
	local flyout = self.weaponImbueFlyout
	self:UnpinCooldownGrid(flyout)
	if flyout then
		for _, btn in ipairs(flyout.buttons or {}) do
			btn:Hide()
			btn:SetParent(nil)
		end
		self.weaponImbueFlyout = nil
	end
	self:CreateWeaponImbueFlyout()
end

-- Layout weapon imbue flyout buttons (called after creation and when layout changes)
-- Buttons are children of weaponImbueButton, positioned relative to parent
function ShamanPower:LayoutWeaponImbueFlyout()
	local flyout = self.weaponImbueFlyout
	if not flyout then return end

	local buttons = flyout.buttons
	if not buttons or #buttons == 0 then return end

	local imbueButton = flyout.imbueButton
	if not imbueButton then return end

	local buttonSize = flyout.buttonSize
	local spacing = flyout.spacing
	local lead = spacing + (flyout.leadGap or 0)   -- box mode leaves room for the arrow tab in combat

	-- Determine flyout direction based on CD bar layout
	local cdLayout = self.opt.cdbarLayout or self.opt.layout
	local isHorizontalBar = (cdLayout == "Horizontal")
	local isVerticalLeft = (cdLayout == "VerticalLeft")
	local isLocked = (self.opt.cooldownBarLocked ~= false)

	-- For horizontal bar: flyout goes vertical
	-- For vertical bar: flyout goes horizontal
	local flyoutIsHorizontal = not isHorizontalBar

	if flyoutIsHorizontal then
		-- When locked to totem bar, go OPPOSITE direction to avoid clipping
		-- When unlocked, go same direction as layout
		local goRight
		if isLocked then
			-- Locked: opposite direction
			goRight = isVerticalLeft  -- VerticalLeft -> go right, VerticalRight -> go left
		else
			-- Unlocked: same direction as layout
			goRight = not isVerticalLeft  -- VerticalLeft -> go left, VerticalRight -> go right
		end

		flyout.arrowDir = goRight and "right" or "left"
		if goRight then
			-- Extend to the RIGHT
			for i, btn in ipairs(buttons) do
				btn:ClearAllPoints()
				btn:SetPoint("LEFT", imbueButton, "RIGHT", lead + (i - 1) * (buttonSize + spacing), 0)
			end
		else
			-- Extend to the LEFT
			for i, btn in ipairs(buttons) do
				btn:ClearAllPoints()
				btn:SetPoint("RIGHT", imbueButton, "LEFT", -lead - (i - 1) * (buttonSize + spacing), 0)
			end
		end
	else
		-- Vertical flyout: buttons extend upward or downward based on option
		local flyoutDir = self:CdItemOpt(7, "flyoutDirection")   -- (the imbue's own: ShamanPowerCdItems.lua)

		-- When "auto" and locked to totem bar, go below (to avoid clipping into totem icons)
		-- When "auto" and unlocked, go above
		local goBelow = (flyoutDir == "below") or (flyoutDir == "auto" and isLocked)

		flyout.arrowDir = goBelow and "bottom" or "top"
		if goBelow then
			-- Extend downward
			for i, btn in ipairs(buttons) do
				btn:ClearAllPoints()
				btn:SetPoint("TOP", imbueButton, "BOTTOM", 0, -lead - (i - 1) * (buttonSize + spacing))
			end
		else
			-- Extend upward
			for i, btn in ipairs(buttons) do
				btn:ClearAllPoints()
				btn:SetPoint("BOTTOM", imbueButton, "TOP", 0, lead + (i - 1) * (buttonSize + spacing))
			end
		end
	end

	self:SyncCdbarFlyout(flyout)
end

-- Show weapon imbue flyout (for backward compatibility, mostly handled by secure handlers now)
function ShamanPower:ShowWeaponImbueFlyout()
	if not self.weaponImbueFlyout then
		self:CreateWeaponImbueFlyout()
	end
	-- Layout is handled in CreateWeaponImbueFlyout and LayoutWeaponImbueFlyout
	-- Show/hide is handled by secure handlers (_onenter/_onleave/_childupdate-show)
end

-- Update the weapon imbue button appearance based on current enchants
function ShamanPower:UpdateWeaponImbueButton()
	-- Imbue visuals are now updated in UpdateCooldownButtons; this function is kept
	-- for backward compatibility with any external callers.
end

-- ============================================================================
-- Mini Totem Bar (built-in totem buttons when TotemTimers is not used)
-- ============================================================================

-- Check if any totems are currently placed
function ShamanPower:HasAnyTotemsPlaced()
	for slot = 1, 4 do
		local haveTotem = ShamanPower:GetElementTotemInfo(slot)  -- element loop; shadow model in combat
		if haveTotem then
			return true
		end
	end
	return false
end

-- Update totem bar visibility based on combat and totem state
-- "Enable Mini Totem Bar" off = no totem bar at all (some shamans keybind
-- their totems and only want the cooldown bar). The four totem buttons, the
-- Drop All / Earth Shield / Totemic Call buttons are all UIParent children,
-- so hiding the anchor alone never hid them.
function ShamanPower:TotemBarEnabled()
	return not self:IsOff() and self.opt.miniBar and self.opt.miniBar.autobutton and true or false
end

-- Whether the layout puts the totem bar up at all right now: a shaman, switched
-- on, and wanted in this kind of group (Use When Solo / Use in Party). The hide
-- and fade rules only act on a bar this allows, so a target, a fade or a pull
-- never brings back one the layout keeps down.
function ShamanPower:TotemBarInUse()
	return isShaman and not self:IsOff() and self.opt.miniBar.autobutton
		and ((GetNumGroupMembers() == 0 and self.opt.ShowWhenSolo) or (GetNumGroupMembers() > 0 and self.opt.ShowInParty))
end

function ShamanPower:SetTotemBarFramesShown(shown)
	if InCombatLockdown() then self._totemBarShownPending = shown; return end
	self._totemBarShownPending = nil
	if self.UsingBlizzardTotemBar and self:UsingBlizzardTotemBar() then shown = false end
	-- The hide rules (UpdateTotemBarVisibility) have the last word: a layout pass
	-- (roster after a fight, zone change, new spell) must not bring back a bar they
	-- hide, since nothing would hide it again before their next event.
	local o, asked = self.opt, shown
	if shown and self.totemBarHidden and o and (o.hideOutOfCombat or o.hideWhenNoTotems
		or (self.ControllerHidesTotemBar and self:ControllerHidesTotemBar())) then shown = false end
	if self.autoButton then self.autoButton:SetShown(shown) end
	if self.totemButtons then
		for element = 1, 4 do
			local btn = self.totemButtons[element]
			if btn then btn:SetShown(shown) end
		end
	end
	local dropAll = _G["ShamanPowerAutoDropAll"]
	if dropAll then dropAll:SetShown(shown and self:ShowsDropAllButton()) end
	local esBtn = _G["ShamanPowerEarthShieldBtn"]
	if esBtn then esBtn:SetShown(shown and self.HasEarthShield and self:HasEarthShield() or false) end
	local tcBtn = _G["ShamanPowerTotemicCallBtn"]
	if tcBtn and not shown then tcBtn:Hide() end
	local shBtn = _G["ShamanPowerCompactShieldBtn"]
	if shBtn then shBtn:SetShown(shown and self.CompactShieldLineActive and self:CompactShieldLineActive() or false) end
	-- and their state checked again (a no-op while it still holds): it can be from
	-- while the bar was off, or from rules switched off since
	if asked then self:SetupTotemBarVisibilityUpdater() end
end

-- Leave hidden secure spell/keybinding targets configured. Only presentation
-- is suppressed, out of combat, after the normal assignment/layout paths run.
function ShamanPower:HideCustomTotemBarForBlizzard()
	if not (self.UsingBlizzardTotemBar and self:UsingBlizzardTotemBar()) then return end
	if InCombatLockdown() then return end
	self:SetTotemBarFramesShown(false)
	self:HideActiveTotemOverlaysForCompact()
	local recall = _G.ShamanPowerAutoTotemicCall
	if recall then recall:Hide() end
	for element = 1, 4 do
		local legacyButton = _G["ShamanPowerAutoTotem" .. element]
		if legacyButton then legacyButton:Hide() end
		local btn = self.totemButtons and self.totemButtons[element]
		if btn then
			btn:SetAttribute("OpenMenu", nil)
			local flyout = self.totemFlyouts and self.totemFlyouts[element]
			if flyout and flyout.box then
				self:FlyoutFallbackSetShown(btn, false)
			elseif flyout and flyout.buttons and not (self.RowsOwnFlyouts and self:RowsOwnFlyouts(element)) then
				for _, child in ipairs(flyout.buttons) do child:Hide() end   -- (a Totem Rows row keeps its own)
			end
		end
	end
end
do
	local f = CreateFrame("Frame")
	f:RegisterEvent("PLAYER_REGEN_ENABLED")
	f:SetScript("OnEvent", function()
		if ShamanPower._totemBarShownPending ~= nil then
			ShamanPower:SetTotemBarFramesShown(ShamanPower._totemBarShownPending)
			if ShamanPower._totemBarShownPending ~= false then ShamanPower:UpdateMiniTotemBar() end
		end
	end)
end

-- Smooth fade for the fade rules: the real alpha is still set at once (the source
-- of truth); an engine Alpha animation then plays from the old value to it over
-- 0.2 s. Only out of combat: combat start stops any fade before lockdown and the
-- bar is simply at its full alpha. opt.fadeSmooth == false turns it off.
local FADE_TIME = 0.2
local function fadeFrames(self)
	-- built without gaps: a missing button must not cut the list short for ipairs
	local list = {}
	local function add(f) if f then list[#list + 1] = f end end
	add(self.autoButton); add(_G["ShamanPowerAutoDropAll"]); add(_G["ShamanPowerEarthShieldBtn"])
	if self.totemButtons then for element = 1, 4 do add(self.totemButtons[element]) end end
	if self.GridFadeFrames then self:GridFadeFrames(add) end   -- Grid's rows glide too
	if self.RowsFadeFrames then self:RowsFadeFrames(add) end   -- and Totem Rows' rows
	return list
end
local function stopFades(self)
	for _, f in ipairs(fadeFrames(self)) do
		if f and f.spFadeAG then f.spFadeAG:Stop() end
	end
end
local function playFade(frame, fromAlpha)
	if not (frame and fromAlpha and frame.CreateAnimationGroup and frame:IsShown()) then return end
	local toAlpha = frame:GetAlpha()
	if math.abs(fromAlpha - toAlpha) < 0.01 then return end
	local ag = frame.spFadeAG
	if not ag then
		ag = frame:CreateAnimationGroup()
		ag.fade = ag:CreateAnimation("Alpha")
		ag.fade:SetDuration(FADE_TIME)
		ag.fade:SetSmoothing("IN_OUT")
		frame.spFadeAG = ag
	end
	ag:Stop()
	ag.fade:SetFromAlpha(fromAlpha)
	ag.fade:SetToAlpha(toAlpha)
	ag:Play()   -- ends on the frame's own (already set) alpha
end

function ShamanPower:UpdateTotemBarVisibility(force)
	if force then self.totemBarHidden, self.totemBarFaded = nil, nil end   -- a fade setting changed: re-apply
	if self.UsingBlizzardTotemBar and self:UsingBlizzardTotemBar() then
		self:HideCustomTotemBarForBlizzard()
		return
	end
	if not self:TotemBarEnabled() then return end   -- bar is switched off entirely
	if not self:TotemBarInUse() then return end     -- the layout keeps it down (solo / party choice)
	if not self.autoButton then return end

	local shouldHide = false

	-- Check hide out of combat option
	if self.opt.hideOutOfCombat then
		local inCombat = InCombatLockdown() or UnitAffectingCombat("player")
		if not inCombat then
			shouldHide = true
		end
	end

	-- Check hide when no totems option (only hide if not already hidden by combat check)
	if not shouldHide and self.opt.hideWhenNoTotems then
		if not self:HasAnyTotemsPlaced() then
			shouldHide = true
		end
	end

	-- Fade rules (opt-in). "Show When I Have a Target" lifts either hide reason
	-- while an attackable target is selected; "Fade Instead of Hide" turns a hide
	-- into a low alpha. Alpha is never protected, so a faded bar can be brought
	-- back in combat too; only real Hide/Show waits for lockdown to end.
	if shouldHide and self.opt.showWithTarget and UnitExists("target") and UnitCanAttack("player", "target") then
		shouldHide = false
	end
	local fade = shouldHide and self.opt.fadeInsteadOfHide == true
	if fade then shouldHide = false end
	-- the controller bar is showing (WoW: Forever controller mode): the same buttons twice, so the totem
	-- bar hides; its keys, and the controller bar's slots that press them, keep working while hidden
	if self.ControllerHidesTotemBar and self:ControllerHidesTotemBar() then shouldHide, fade = true, false end

	-- Skip update if state hasn't changed (prevents blinking)
	if self.totemBarHidden == shouldHide and (self.totemBarFaded or false) == fade then return end
	if InCombatLockdown() and self.totemBarHidden ~= shouldHide then return end   -- Show/Hide: after combat
	-- a fade-only change between two visible states, out of combat, may glide
	local inCombat = InCombatLockdown() or UnitAffectingCombat("player")
	local glide = self.opt.fadeSmooth ~= false and not inCombat and not force
		and self.totemBarHidden == false and not shouldHide and (self.totemBarFaded or false) ~= fade
	local before
	if glide then
		before = {}
		for _, f in ipairs(fadeFrames(self)) do if f then before[f] = f:GetAlpha() end end
	elseif not InCombatLockdown() then
		stopFades(self)   -- never let a fade hold the bar down (combat start stops them before lockdown)
	end
	self.totemBarHidden = shouldHide
	self.totemBarFaded = fade

	-- Apply visibility (can't change in combat lockdown for secure frames)
	if InCombatLockdown() then
		self:UpdateTotemBarOpacity()   -- only a fade changed: alpha is allowed
		if self.ApplyGridRowAlpha then self:ApplyGridRowAlpha() end   -- Grid's rows ignore the bar's alpha
		if self.ApplyTotemRowAlpha then self:ApplyTotemRowAlpha() end   -- and Totem Rows' rows
	else
		if shouldHide then
			-- Hide everything
			self.autoButton:Hide()

			if self.totemButtons then
				for element = 1, 4 do
					local btn = self.totemButtons[element]
					if btn then btn:Hide() end
				end
			end

			-- Hide Drop All button
			local dropAllBtn = _G["ShamanPowerAutoDropAll"]
			if dropAllBtn then dropAllBtn:Hide() end

			-- Hide Earth Shield button
			local esBtn = _G["ShamanPowerEarthShieldBtn"]
			if esBtn then esBtn:Hide() end
			-- and Compact's shield line (a frame of its own, not a child of the bar)
			local shBtn = _G["ShamanPowerCompactShieldBtn"]
			if shBtn then shBtn:Hide() end
		else
			-- Show everything with proper opacity (the faded opacity while a fade rule applies)
			local alpha = fade and (self.opt.fadeOpacity or 0.25) or (self.opt.totemBarOpacity or 1.0)

			self.autoButton:Show()
			self.autoButton:SetAlpha(alpha)

			-- only the elements the layout shows (a hidden or not yet learned one stays
			-- hidden; a popped-out one shows in its own frame)
			if self.totemButtons then
				for element = 1, 4 do
					local btn = self.totemButtons[element]
					if btn then
						btn:SetShown(self:IsElementShown(element) or self:IsElementPoppedOut(element))
						btn:SetAlpha(alpha)
					end
				end
			end

			-- Show Drop All button (if enabled)
			local dropAllBtn = _G["ShamanPowerAutoDropAll"]
			if dropAllBtn and self:ShowsDropAllButton() then
				dropAllBtn:Show()
				dropAllBtn:SetAlpha(dropAllBtn:GetParent() == self.autoButton and 1 or alpha)   -- takes the bar's (UpdateTotemBarOpacity)
			end

			-- Show Earth Shield button (if it should be visible)
			local esBtn = _G["ShamanPowerEarthShieldBtn"]
			if esBtn and self:HasEarthShield() then
				esBtn:Show()
				esBtn:SetAlpha(alpha)
			end
			-- and Compact's shield line with it (combat start lands here before the lockdown); its own tick
			-- keeps its opacity with the bar's
			local shBtn = _G["ShamanPowerCompactShieldBtn"]
			if shBtn then shBtn:SetShown(self.CompactShieldLineActive and self:CompactShieldLineActive() or false) end
			if self.ApplyGridRowAlpha then self:ApplyGridRowAlpha() end   -- Grid's rows ignore the bar's alpha
			if self.ApplyTotemRowAlpha then self:ApplyTotemRowAlpha() end   -- and Totem Rows' rows
			-- per-button rules (Full Opacity When Totem Placed) on top, unless faded
			if not fade then self:UpdateTotemBarOpacity() end
		end
	end
	if before then
		for f, old in pairs(before) do playFade(f, old) end
	end
end

-- The hide and fade rules react to events, not a timer: combat start (before
-- lockdown, so a hidden bar can still be shown), combat end, a totem going down
-- or away, target changes, and the target turning attackable (or not) without a
-- target change: an NPC turning hostile, a duel starting, a PvP flag flip (on
-- either side, as Blizzard's target frame checks it). Idle when the options are off.
do
	local f = CreateFrame("Frame")
	f:RegisterEvent("PLAYER_REGEN_DISABLED")
	f:RegisterEvent("PLAYER_REGEN_ENABLED")
	f:RegisterEvent("PLAYER_TARGET_CHANGED")
	f:RegisterEvent("PLAYER_TOTEM_UPDATE")
	if f.RegisterUnitEvent then f:RegisterUnitEvent("UNIT_FACTION", "player", "target") else f:RegisterEvent("UNIT_FACTION") end
	local totemCheckQueued
	local function totemCheck()
		totemCheckQueued = nil
		ShamanPower:UpdateTotemBarVisibility()
	end
	f:SetScript("OnEvent", function(_, event, unit)
		local o = ShamanPower.opt
		if not (o and (o.hideOutOfCombat or o.hideWhenNoTotems)) or ShamanPower:IsOff() then return end   -- no rules, or switched off
		if (event == "PLAYER_TARGET_CHANGED" or event == "UNIT_FACTION") and not o.showWithTarget then return end
		if event == "UNIT_FACTION" and unit ~= "target" and unit ~= "player" then return end
		if event == "PLAYER_TOTEM_UPDATE" then
			-- read a frame later, once the shadow totem model (combat) has the change too
			if o.hideWhenNoTotems and not totemCheckQueued then totemCheckQueued = true; C_Timer.After(0, totemCheck) end
			return
		end
		if event == "PLAYER_REGEN_DISABLED" then stopFades(ShamanPower) end   -- before lockdown: full alpha now
		ShamanPower:UpdateTotemBarVisibility()
	end)
end

-- One pass where there is hide state to work out (login, a profile change);
-- after that the events above keep it current. A bar with no hide option and
-- nothing hidden is left to the layout, as the old 5 Hz pass left it.
function ShamanPower:SetupTotemBarVisibilityUpdater()
	local o = self.opt
	if o and (o.hideOutOfCombat or o.hideWhenNoTotems or self.totemBarHidden or self.totemBarFaded) then
		self:UpdateTotemBarVisibility()
	end
end

-- Update the mini totem bar icons and spells based on current assignments
-- Out of combat: set one element's assignment and do everything a flyout pick
-- does (bar icon, Drop All / Blizzard's bar, macros, party message, flyout
-- marks). In combat nothing is written: callers queue for the regen pass.
function ShamanPower:ApplyAssignment(element, totemIndex)
	if InCombatLockdown() then return false end
	ShamanPower_Assignments[self.player] = ShamanPower_Assignments[self.player] or {}
	ShamanPower_Assignments[self.player][element] = totemIndex or 0
	self:UpdateMiniTotemBar()
	self:UpdateDropAllButton()
	self:UpdateSPMacros()
	self:SendMessage("ASSIGN " .. self.player .. " " .. element .. " " .. (totemIndex or 0))
	self:UpdateFlyoutVisibility(element)
	if self.ShowEmptySlotArt then self:ShowEmptySlotArt(element, (totemIndex or 0) == 0) end
	return true
end

-- The settings window shows assignment-dependent notes; let it redraw when
-- one changes while it is open (AceConfig's change notification, which the
-- window listens to). Nothing happens while it is closed.
function ShamanPower:AssignmentsChanged()
	local cfg = rawget(_G, "ShamanPowerConfig")
	if not (cfg and cfg.IsOpen and cfg:IsOpen()) then return end
	local reg = LibStub and LibStub("AceConfigRegistry-3.0", true)
	if reg then reg:NotifyChange("ShamanPower") end
end

function ShamanPower:UpdateMiniTotemBar()
	self._ovWake = true   -- this repaints the totem icons: the dropped-totem overlay state is re-applied on the next bar tick
	self:AssignmentsChanged()
	if not self.autoButton then return end
	if InCombatLockdown() then return end
	-- switched off: the totem, Drop All and Earth Shield buttons (UIParent children)
	-- stay down; switch-on lays the bar out again
	if self:IsOff() then return end

	-- A bar the hide rules keep down (Hide Out of Combat, Hide When No Totems) is laid out
	-- all the same and put back down at the end: it used to return here, so a bar hidden from
	-- login was never laid out at all, and the fight that showed it showed the raw XML bar
	-- (the legacy element buttons in a column, no Compact lines, no keybinds or flyouts set up:
	-- reported 2026-10-05, Compact + Hide Out of Combat).
	local keptDown = self.totemBarHidden and not (self.UsingBlizzardTotemBar and self:UsingBlizzardTotemBar())

	local playerName = self.player
	local assignments = ShamanPower_Assignments[playerName]
	if not assignments then return end

	-- Determine layout orientation
	local isHorizontal = self:IsTotemBarHorizontal()
	local buttonSize = 26
	-- Compact style: totem slots are lines, not 26px squares
	local bw, bh, sw, sh = self:GetTotemSlotDims()
	local slotAlong = isHorizontal and sw or sh   -- slot size along the bar
	local slotCross = isHorizontal and sh or sw   -- slot size across the bar
	local startOff = self.CompactStartOffset and self:CompactStartOffset() or 0   -- Compact shield line at the start
	local spacing = self:TotemBarSpacing()   -- Button Spacing, plus room for dots between the buttons
	local padding = 4
	local separatorSize = 12  -- Extra gap for separator
	local showDropAll = self:ShowsDropAllButton()  -- the option (on by default), once a totem is learned
	local dropAllPoppedOut = self:IsDropAllPoppedOut()
	-- Show Totemic Call on totem bar if option is enabled (spell knowledge is validated by CD bar settings)
	local showTotemicCall = self:CdItemOpt(2, "onTotemBar") and self.opt.cdbarShowRecall ~= false

	-- Check which totem buttons should be visible (not hidden in options and not popped out)
	local elementVisible = {
		[1] = self:IsElementShown(1) and not self:IsElementPoppedOut(1),  -- Earth
		[2] = self:IsElementShown(2) and not self:IsElementPoppedOut(2),   -- Fire
		[3] = self:IsElementShown(3) and not self:IsElementPoppedOut(3),  -- Water
		[4] = self:IsElementShown(4) and not self:IsElementPoppedOut(4),    -- Air
	}

	-- Count visible buttons
	local visibleCount = 0
	for i = 1, 4 do
		if elementVisible[i] then
			visibleCount = visibleCount + 1
		end
	end

	-- Resize the parent frame based on layout and visible button count
	-- Don't include Drop All in size calculations if it's popped out
	local includeDropAll = showDropAll and not dropAllPoppedOut
	-- Count extra buttons (Drop All and/or Totemic Call)
	local extraButtonCount = 0
	if includeDropAll then extraButtonCount = extraButtonCount + 1 end
	if showTotemicCall then extraButtonCount = extraButtonCount + 1 end

	if isHorizontal then
		-- Horizontal: wide and short
		local totalWidth = (startOff + slotAlong * visibleCount) + (spacing * math.max(0, visibleCount - 1)) + (padding * 2)
		if extraButtonCount > 0 and visibleCount > 0 then
			totalWidth = totalWidth + separatorSize + (buttonSize * extraButtonCount) + (spacing * math.max(0, extraButtonCount - 1))
		elseif extraButtonCount > 0 then
			totalWidth = (buttonSize * extraButtonCount) + (spacing * math.max(0, extraButtonCount - 1)) + (padding * 2)
		end
		self.autoButton:SetSize(math.max(totalWidth, buttonSize + (padding * 2)), math.max(slotCross, extraButtonCount > 0 and buttonSize or 0) + (padding * 2))
	else
		-- Vertical: narrow and tall
		local totalHeight = (startOff + slotAlong * visibleCount) + (spacing * math.max(0, visibleCount - 1)) + (padding * 2)
		if extraButtonCount > 0 and visibleCount > 0 then
			totalHeight = totalHeight + separatorSize + (buttonSize * extraButtonCount) + (spacing * math.max(0, extraButtonCount - 1))
		elseif extraButtonCount > 0 then
			totalHeight = (buttonSize * extraButtonCount) + (spacing * math.max(0, extraButtonCount - 1)) + (padding * 2)
		end
		self.autoButton:SetSize(math.max(slotCross, extraButtonCount > 0 and buttonSize or 0) + (padding * 2), math.max(totalHeight, buttonSize + (padding * 2)))
	end
	-- Nothing on the bar yet (a new shaman before the first totem: Drop All waits
	-- for one too): no empty panel either. It comes back with the first totem.
	local empty = visibleCount == 0 and extraButtonCount == 0 and startOff == 0
	if empty and self.autoButton.SetBackdrop then
		self.autoButton:SetBackdrop(nil)
	elseif not empty and self._totemBarEmpty then
		self:UpdateTotemBarFrame(); self:ButtonsUpdate()   -- the panel, then its status colour
	end
	self._totemBarEmpty = empty

	-- Get the order to display totem buttons
	local totemOrder = self.opt.totemBarOrder or {1, 2, 3, 4}

	local visiblePosition = 0  -- Track position of visible buttons
	for position = 1, 4 do
		local element = totemOrder[position]
		local totemButton = _G["ShamanPowerAutoTotem" .. element]
		if totemButton then
			-- Check if this element should be visible
			if not elementVisible[element] then
				totemButton:Hide()
			else
				visiblePosition = visiblePosition + 1
				totemButton:Show()

				-- Dynamic Mode: use currently active totem instead of assignment
				-- (no active totem, or Normal mode: the assignment). The icon also shows
				-- a flyout pick from a fight that is just ending; the spells stay on the table.
				local totemIndex, shownIndex
				local activeIndex = self:ShowsActiveTotemOnBar() and self:GetActiveTotemIndex(element)
				if activeIndex then
					totemIndex, shownIndex = activeIndex, activeIndex
				else
					totemIndex, shownIndex = assignments[element] or 0, self:AssignedIndex(element)
				end

				local spellID = nil
				local spellName = nil
				local icon = self.ElementIcons[element]  -- Default to element icon

				if totemIndex and totemIndex > 0 then
					spellID = self:GetTotemSpell(element, totemIndex)
					icon = self:GetTotemIcon(element, totemIndex)
					-- TBC needs spell names, not IDs
					if spellID then
						spellName = GetSpellInfo(spellID)
						if SPCompat.HasTotemCastAliases(spellID) then spellName = SPCompat.TotemCastName(spellID) end
					end
				end
				if shownIndex ~= totemIndex then
					icon = shownIndex > 0 and self:GetTotemIcon(element, shownIndex) or self.ElementIcons[element]
				end

				-- Update the icon
				local iconTexture = _G["ShamanPowerAutoTotem" .. element .. "Icon"]
				if iconTexture then
					iconTexture:SetTexture(icon)
				end

				-- Reposition buttons based on layout (use visiblePosition for layout, element for data)
				totemButton:ClearAllPoints()
				if isHorizontal then
					-- Horizontal: buttons go left to right
					totemButton:SetPoint("TOPLEFT", self.autoButton, "TOPLEFT", padding + (visiblePosition - 1) * (buttonSize + spacing), -padding)
				else
					-- Vertical: buttons go top to bottom
					totemButton:SetPoint("TOPLEFT", self.autoButton, "TOPLEFT", padding, -padding - (visiblePosition - 1) * (buttonSize + spacing))
				end

				-- Set up the button: left-click casts totem, right-click casts Totemic Call
				totemButton:RegisterForClicks("AnyUp", "AnyDown")

				-- Clear old attributes first
				totemButton:SetAttribute("type", nil)
				totemButton:SetAttribute("type1", nil)
				totemButton:SetAttribute("spell", nil)
				totemButton:SetAttribute("spell1", nil)
				totemButton:SetAttribute("macrotext1", nil)

				-- Left-click: cast totem (or castsequence for Air totem twisting)
				if element == 4 and self.opt.enableTotemTwisting then
					-- Air totem with twisting: use castsequence macro
					local wfName = GetSpellInfo(8512) or "Windfury Totem"
					local twistName = self:GetTwistTotemName()
					totemButton:SetAttribute("type1", "macro")
					totemButton:SetAttribute("macrotext1", "/castsequence reset=combat/15 " .. wfName .. ", " .. twistName)
					-- Update icon to Windfury
					local twistIcon = _G["ShamanPowerAutoTotem" .. element .. "Icon"]
					if twistIcon then
						twistIcon:SetTexture("Interface\\Icons\\Spell_Nature_Windfury")
					end
				elseif spellName then
					totemButton:SetAttribute("type1", "spell")
					totemButton:SetAttribute("spell1", spellName)
				end

				-- Right-click behavior: Totemic Call by default, assigned totem if option enabled, or flyout trigger
				totemButton:SetAttribute("shift-type2", nil)
				totemButton:SetAttribute("shift-spell2", nil)
				if self.opt.showTotemFlyouts and self:FlyoutOpensOnRightClick() then
					-- Right-click shows flyout instead of Totemic Call
					totemButton:SetAttribute("type2", nil)
					totemButton:SetAttribute("spell2", nil)
					self:ApplyShiftPullBack(totemButton, element)
				elseif self:RightClickDestroysTotems() then
					self:ApplyTotemDestroyAttributes(totemButton, element)
				elseif self.opt.activeTotemAsMain and self.opt.rightClickCastsAssigned then
					-- TotemTimers mode: right-click casts the assigned totem (shown in corner)
					-- Get the assigned totem spell (not the active one)
					local assignedIndex = assignments[element] or 0
					local assignedSpellID = assignedIndex > 0 and self:GetTotemSpell(element, assignedIndex)
					local assignedSpellName = assignedSpellID and GetSpellInfo(assignedSpellID)
					if assignedSpellName then
						totemButton:SetAttribute("type2", "spell")
						if SPCompat.HasTotemCastAliases(assignedSpellID) then
							assignedSpellName = SPCompat.TotemCastName(assignedSpellID)
						end
						totemButton:SetAttribute("spell2", assignedSpellName)
					else
						-- No assigned totem, fall back to Totemic Call
						totemButton:SetAttribute("type2", "spell")
						totemButton:SetAttribute("spell2", GetSpellInfo(36936))  -- Totemic Call
					end
				else
					-- Right-click to cast Totemic Call (destroys all totems)
					totemButton:SetAttribute("type2", "spell")
					totemButton:SetAttribute("spell2", GetSpellInfo(36936))  -- Totemic Call
				end
			end  -- end of else (visible)
		end  -- end of if totemButton
	end  -- end of for loop

	-- Create or update separator line
	local separator = _G["ShamanPowerAutoSeparator"]
	if not separator then
		separator = self.autoButton:CreateTexture("ShamanPowerAutoSeparator", "ARTWORK")
		separator:SetColorTexture(0.5, 0.5, 0.5, 0.8)  -- Gray line
	end

	-- Reposition the Drop All button and Totemic Call button (after the separator)
	local dropAllButton = _G["ShamanPowerAutoDropAll"]
	local totemicCallButton = _G["ShamanPowerAutoTotemicCall"]

	-- Set up Totemic Call button spell if needed (only needs to be done once)
	if totemicCallButton and showTotemicCall then
		self:SetupTotemicCallButton()
	end

	-- Calculate how many extra buttons will be shown (after separator)
	local showDropAllHere = showDropAll and not dropAllPoppedOut
	local extraButtonsShown = 0
	if showDropAllHere then extraButtonsShown = extraButtonsShown + 1 end
	if showTotemicCall then extraButtonsShown = extraButtonsShown + 1 end

	-- Position extra buttons (Drop All and Totemic Call)
	if extraButtonsShown > 0 and visibleCount > 0 then
		separator:ClearAllPoints()
		if isHorizontal then
			-- Vertical separator line
			separator:SetSize(2, slotCross)
			local separatorX = padding + (startOff + slotAlong * visibleCount) + (spacing * math.max(0, visibleCount - 1)) + (separatorSize / 2) - 1
			separator:SetPoint("TOPLEFT", self.autoButton, "TOPLEFT", separatorX, -padding)
		else
			-- Horizontal separator line
			separator:SetSize(slotCross, 2)
			local separatorY = -padding - (startOff + slotAlong * visibleCount) - (spacing * math.max(0, visibleCount - 1)) - (separatorSize / 2) + 1
			separator:SetPoint("TOPLEFT", self.autoButton, "TOPLEFT", padding, separatorY)
		end
		separator:Show()

		-- Base position after separator
		local extraPos = 0

		-- Position Drop All button first (if shown)
		if showDropAllHere and dropAllButton then
			dropAllButton:ClearAllPoints()
			if isHorizontal then
				local dropAllX = padding + (startOff + slotAlong * visibleCount) + (spacing * math.max(0, visibleCount - 1)) + separatorSize + (extraPos * (buttonSize + spacing))
				dropAllButton:SetPoint("TOPLEFT", self.autoButton, "TOPLEFT", dropAllX, -padding)
			else
				local dropAllY = -padding - (startOff + slotAlong * visibleCount) - (spacing * math.max(0, visibleCount - 1)) - separatorSize - (extraPos * (buttonSize + spacing))
				dropAllButton:SetPoint("TOPLEFT", self.autoButton, "TOPLEFT", padding, dropAllY)
			end
			dropAllButton:Show()
			extraPos = extraPos + 1
		elseif dropAllButton then
			dropAllButton:Hide()
		end

		-- Position Totemic Call button (if shown)
		if showTotemicCall and totemicCallButton then
			totemicCallButton:ClearAllPoints()
			if isHorizontal then
				local tcX = padding + (startOff + slotAlong * visibleCount) + (spacing * math.max(0, visibleCount - 1)) + separatorSize + (extraPos * (buttonSize + spacing))
				totemicCallButton:SetPoint("TOPLEFT", self.autoButton, "TOPLEFT", tcX, -padding)
			else
				local tcY = -padding - (startOff + slotAlong * visibleCount) - (spacing * math.max(0, visibleCount - 1)) - separatorSize - (extraPos * (buttonSize + spacing))
				totemicCallButton:SetPoint("TOPLEFT", self.autoButton, "TOPLEFT", padding, tcY)
			end
			totemicCallButton:Show()
		elseif totemicCallButton then
			totemicCallButton:Hide()
		end

	elseif extraButtonsShown > 0 and visibleCount == 0 then
		-- Show only extra buttons when all totems are hidden
		separator:Hide()
		local extraPos = 0

		if showDropAllHere and dropAllButton then
			dropAllButton:ClearAllPoints()
			if isHorizontal then
				dropAllButton:SetPoint("TOPLEFT", self.autoButton, "TOPLEFT", padding + (extraPos * (buttonSize + spacing)), -padding)
			else
				dropAllButton:SetPoint("TOPLEFT", self.autoButton, "TOPLEFT", padding, -padding - (extraPos * (buttonSize + spacing)))
			end
			dropAllButton:Show()
			extraPos = extraPos + 1
		elseif dropAllButton then
			dropAllButton:Hide()
		end

		if showTotemicCall and totemicCallButton then
			totemicCallButton:ClearAllPoints()
			if isHorizontal then
				totemicCallButton:SetPoint("TOPLEFT", self.autoButton, "TOPLEFT", padding + (extraPos * (buttonSize + spacing)), -padding)
			else
				totemicCallButton:SetPoint("TOPLEFT", self.autoButton, "TOPLEFT", padding, -padding - (extraPos * (buttonSize + spacing)))
			end
			totemicCallButton:Show()
		elseif totemicCallButton then
			totemicCallButton:Hide()
		end
	else
		-- Hide separator and extra buttons
		separator:Hide()
		if dropAllButton then
			dropAllButton:Hide()
		end
		if totemicCallButton then
			totemicCallButton:Hide()
		end
	end

	-- Update totem buttons (parented to UIParent for combat flyouts)
	self:UpdateTotemButtons()

	-- Update Earth Shield button (if shaman has ES and a target assigned)
	self:UpdateEarthShieldButton()

	-- Setup pulse overlays for totems like Tremor
	self:SetupPulseOverlays()

	-- Setup party range dots
	self:SetupPartyRangeDots()

	-- Setup range counters (shows number of players in range)
	self:SetupRangeCounters()

	-- Compact style tick + per-button line visuals (after counters/dots exist)
	if self.SetupCompactStyle then self:SetupCompactStyle() end

	-- Setup totem duration progress bars
	self:SetupTotemProgressBars()

	-- Setup totem flyout menus
	self:SetupTotemFlyouts()

	-- Setup cooldown tracker bar
	self:UpdateCooldownBar()

	-- Setup keybindings for the buttons
	self:SetupKeybindings()

	-- Setup twist timer visual if twisting is enabled
	if self.opt.enableTotemTwisting then
		self:SetupTwistTimer()
	else
		self:HideTwistTimer()
	end

	-- Setup GCD swipe overlays on totem buttons
	self:SetupGCDSwipes()

	-- Note: Macros are created manually via Options -> Buttons -> "Create/Update Macros" button
	-- or /spmacros command. No automatic macro updates to avoid interfering with macro UI.

	-- laid out while the hide rules keep the bar down: down again (in the same frame, so nothing
	-- flickers); the fight that brings it up shows it laid out
	if keptDown and self.totemBarHidden then self:SetTotemBarFramesShown(false) end
	-- and one the layout keeps down as not in use here (Use When Solo / In a Party off, the bar switched off):
	-- this pass shows its buttons, and nothing put them back down (the bar came back after every fight).
	-- Keybind Mode's bar stays up
	if not self:TotemBarInUse() and not (self.KeybindModeActive and self:KeybindModeActive()) then
		self:SetTotemBarFramesShown(false)
	end
end

-- ============================================================================
-- GCD Swipe (shows global cooldown animation on totem buttons)
-- ============================================================================

ShamanPower.gcdCooldowns = {}  -- Cooldown frames for each totem button

function ShamanPower:SetupGCDSwipes()
	for element = 1, 4 do
		local totemButton = self.totemButtons[element]
		if totemButton then
			local cdFrame = self.gcdCooldowns[element]
			if not cdFrame then
				cdFrame = CreateFrame("Cooldown", "ShamanPowerGCD" .. element, totemButton, "CooldownFrameTemplate")
				cdFrame:SetAllPoints(totemButton)
				cdFrame:SetDrawEdge(true)
				cdFrame:SetDrawSwipe(true)
				cdFrame:SetSwipeColor(0, 0, 0, 0.6)
				cdFrame:SetHideCountdownNumbers(true)
				self.gcdCooldowns[element] = cdFrame
			end
		end
	end

	-- Also add to Drop All button
	local dropAllButton = _G["ShamanPowerAutoDropAll"]
	if dropAllButton then
		local cdFrame = self.gcdCooldowns[5]
		if not cdFrame then
			cdFrame = CreateFrame("Cooldown", "ShamanPowerGCD5", dropAllButton, "CooldownFrameTemplate")
			cdFrame:SetAllPoints(dropAllButton)
			cdFrame:SetDrawEdge(true)
			cdFrame:SetDrawSwipe(true)
			cdFrame:SetSwipeColor(0, 0, 0, 0.6)
			cdFrame:SetHideCountdownNumbers(true)
			self.gcdCooldowns[5] = cdFrame
		end
	end
end

function ShamanPower:TriggerGCDSwipe()
	-- Get the current GCD from spell cooldown
	local start, duration = GetSpellCooldown(2484)  -- Earthbind Totem as reference
	if not start or start == 0 then
		-- Fallback: standard 1.5 second GCD
		start = GetTime()
		duration = 1.5
	end

	-- Only trigger if this is a fresh GCD (not a longer cooldown)
	if duration > 2 then return end

	for i = 1, 5 do
		local cdFrame = self.gcdCooldowns[i]
		local btn = i <= 4 and self.totemButtons and self.totemButtons[i]
		if cdFrame and not (btn and btn.compactLayoutOn) then   -- no swipe on Compact lines
			cdFrame:SetCooldown(start, duration)
		end
	end
end

-- Tooltip for mini totem bar buttons
function ShamanPower:TotemBarTooltip(button, element)
	if not self.opt.ShowTooltips then return end

	local totemIndex = self:AssignedIndex(element)   -- a flyout pick made in this fight: the totem the button casts

	local elementName = self.Elements[element] or "Unknown"
	local totemName = "None"
	local spellID = nil

	if totemIndex and totemIndex > 0 then
		totemName = self:GetTotemName(element, totemIndex)
		spellID = self:GetTotemSpell(element, totemIndex)
	end

	GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
	if spellID then
		-- the spell's own tooltip, as the flyout's buttons show it, with the clicks under it
		GameTooltip:SetSpellByID(SPCompat.HighestKnownRank and SPCompat.HighestKnownRank(spellID) or spellID)
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(self:ClickLabel(true) .. " Cast totem", 0.7, 0.7, 0.7)
		-- The other click depends on options (Totem Rows: this element's choices are its row,
		-- so its button has no flyout: what it does with flyouts off)
		local rowHeld = self.RowsOwnFlyouts and self:RowsOwnFlyouts(element)
		if self.opt.showTotemFlyouts and self:FlyoutOpensOnRightClick() and not rowHeld then
			GameTooltip:AddLine(self:ClickLabel(false) .. " Show flyout", 0.7, 0.7, 0.7)
			if self:ShiftRightClickPullsTotem() then
				GameTooltip:AddLine(self:ClickLabel(false, true) .. " Pull this totem back", 0.7, 0.7, 0.7)
			end
		elseif self:RightClickDestroysTotems() then
			GameTooltip:AddLine(self:ClickLabel(false) .. " Pull this totem back", 0.7, 0.7, 0.7)
			GameTooltip:AddLine(self:ClickLabel(false, true) .. " " .. (GetSpellInfo(36936) or "Totemic Call"), 0.7, 0.7, 0.7)
		elseif self.opt.activeTotemAsMain and self.opt.rightClickCastsAssigned then
			GameTooltip:AddLine(self:ClickLabel(false) .. " Drop corner totem (" .. totemName .. ")", 0.7, 0.7, 0.7)
		else
			GameTooltip:AddLine(self:ClickLabel(false) .. " " .. (GetSpellInfo(36936) or "Totemic Call"), 0.7, 0.7, 0.7)
		end
	else
		GameTooltip:AddLine(elementName .. " Totem", 1, 1, 1)
		GameTooltip:AddLine("No totem assigned", 1, 0, 0)
	end
	-- (not in Totem Rows: every row already moves on its own)
	if self.opt.enableMiddleClickPopOut ~= false and not (self.RowsActive and self:RowsActive()) then
		GameTooltip:AddLine("|cff00ccffMiddle-click:|r Pop out", 1, 1, 1)
	end
	GameTooltip:Show()
end

-- ============================================================================
-- Earth Shield Macro Button (invisible, always available for /click)
-- ============================================================================

function ShamanPower:CreateEarthShieldMacroButton()
	if _G["ShamanPowerESMacroBtn"] then return end

	-- Create an invisible button that's always "shown" so /click works
	local macroBtn = CreateFrame("Button", "ShamanPowerESMacroBtn", UIParent, "SecureActionButtonTemplate")
	macroBtn:SetSize(1, 1)
	macroBtn:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -100, 100)  -- Off-screen
	macroBtn:SetAlpha(0)
	macroBtn:EnableMouse(false)  -- Don't intercept mouse clicks on screen
	macroBtn:RegisterForClicks("AnyUp", "AnyDown")
	macroBtn:Show()  -- Must be shown for /click to work
end

function ShamanPower:UpdateEarthShieldMacroButton()
	if InCombatLockdown() then return end

	-- Create if needed
	self:CreateEarthShieldMacroButton()

	local macroBtn = _G["ShamanPowerESMacroBtn"]
	if not macroBtn then return end

	local hasES = self:HasEarthShield()
	local targetName = ShamanPower_EarthShieldAssignments[self.player]

	if hasES and targetName then
		local spellName = self:GetEarthShieldSpell()
		if spellName then
			macroBtn:SetAttribute("type", "macro")
			macroBtn:SetAttribute("macrotext", "/target " .. targetName .. "\n/cast " .. spellName .. "\n/targetlasttarget")
		else
			macroBtn:SetAttribute("type", nil)
			macroBtn:SetAttribute("macrotext", nil)
		end
	else
		macroBtn:SetAttribute("type", nil)
		macroBtn:SetAttribute("macrotext", nil)
	end
end

-- ============================================================================
-- Earth Shield Button (for resto shamans with ES target assigned)
-- ============================================================================

function ShamanPower:CreateEarthShieldButton()
	if _G["ShamanPowerEarthShieldBtn"] then return end

	-- Parent to UIParent and use SPTotemButtonTemplate (same as totem buttons) for combat flyout support
	local esBtn = CreateFrame("Button", "ShamanPowerEarthShieldBtn", UIParent, "SPTotemButtonTemplate")
	esBtn:SetSize(26, 26)
	esBtn:Hide()

	-- SECURE HANDLER: Show flyout on enter (WORKS IN COMBAT)
	esBtn:SetAttribute("OpenMenu", "mouseover")
	ShamanPower:SetSnippet(esBtn, "_onenter", [[
		if self:GetAttribute("OpenMenu") == "mouseover" then
			self:ChildUpdate("show", true)
		end
	]])
	ShamanPower:SetSnippet(esBtn, "_onleave", SP_SECURE_ONLEAVE_SELF)

	-- Icon (use the template's icon - $parentIcon becomes ShamanPowerEarthShieldBtnIcon)
	local icon = _G[esBtn:GetName() .. "Icon"]
	if icon then
		icon:SetTexture(self.EarthShield.icon)
	end

	-- Charge count text (bottom right corner)
	local chargeText = esBtn:CreateFontString("ShamanPowerEarthShieldBtnCharges", "OVERLAY", "NumberFontNormal")
	ShamanPower:AdoptSPFont(chargeText, "charges")   -- template font = the design; follows the Fonts settings
	chargeText:SetPoint("BOTTOMRIGHT", esBtn, "BOTTOMRIGHT", -1, 1)
	chargeText:SetJustifyH("RIGHT")
	chargeText:SetTextColor(1, 1, 1)  -- White
	chargeText:SetText("")
	self:EnsureESButtonContainer(esBtn)

	-- Target name text (optional, shows below button)
	local nameText = esBtn:CreateFontString("ShamanPowerEarthShieldBtnName", "OVERLAY", "GameFontHighlightSmall")
	ShamanPower:AdoptSPFont(nameText, "labels")   -- template font = the design; follows the Fonts settings
	nameText:SetPoint("TOP", esBtn, "BOTTOM", 0, -1)
	nameText:SetWidth(40)
	nameText:SetHeight(10)
	nameText:SetJustifyH("CENTER")

	-- Tooltip (use HookScript to work alongside secure handlers)
	esBtn:HookScript("OnEnter", function(self)
		if not ShamanPower.opt.ShowTooltips then return end
		local assignedTarget = ShamanPower_EarthShieldAssignments[ShamanPower.player]
		local currentTarget, charges = ShamanPower:FindEarthShieldTarget()
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(SPCompat.SpellLabel(974, "Earth Shield"), 0.2, 0.8, 0.2)

		if currentTarget then
			GameTooltip:AddLine("Active on: " .. currentTarget, 0, 1, 0)
			if charges and charges > 0 then
				GameTooltip:AddLine("Charges: " .. charges, 1, 1, 1)
			end
		else
			GameTooltip:AddLine("Not active on anyone", 1, 0.3, 0.3)
		end

		-- Show assigned target if different from current
		if assignedTarget and currentTarget ~= assignedTarget then
			local assignedDead = ShamanPower:IsPlayerDead(assignedTarget)
			if assignedDead then
				GameTooltip:AddLine("Assigned: " .. assignedTarget .. " (dead)", 0.5, 0.5, 0.5)
			else
				GameTooltip:AddLine("Assigned: " .. assignedTarget, 1, 0.8, 0)
			end
		end

		-- Determine who click will cast on (same logic as button)
		local castTarget = nil
		if assignedTarget and not ShamanPower:IsPlayerDead(assignedTarget) then
			castTarget = assignedTarget
		elseif currentTarget and not ShamanPower:IsPlayerDead(currentTarget) then
			castTarget = currentTarget
		end

		if castTarget then
			GameTooltip:AddLine("Click to cast on " .. castTarget, 0.7, 0.7, 0.7)
		else
			GameTooltip:AddLine("Click to cast on current target", 0.7, 0.7, 0.7)
		end
		if ShamanPower.opt.enableMiddleClickPopOut ~= false then
			GameTooltip:AddLine("|cff00ccffMiddle-click:|r Pop out", 1, 1, 1)
		end
		GameTooltip:Show()
	end)
	esBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)

	-- Re-check the flyout direction on hover, like the totem flyouts do (the
	-- size/direction guard inside CreateEarthShieldFlyout makes this a no-op
	-- unless the bar moved across the screen or the layout changed)
	esBtn:HookScript("OnEnter", function()
		if not InCombatLockdown() then
			ShamanPower:CreateEarthShieldFlyout()
		end
	end)

	-- Register ES button updates with consolidated update system (2fps)
	if not self.updateSystem.subsystems["esButton"] then
		self:RegisterUpdateSubsystem("esButton", 0.5, function()
			ShamanPower:UpdateEarthShieldCharges()
			ShamanPower:UpdateESActiveOverlay()

			-- Update button display (name color) based on current target
			local overlay = ShamanPower.esActiveOverlay
			local overlayShowing = overlay and overlay.frame and overlay.frame:IsShown()

			if not overlayShowing then
				local esName = _G["ShamanPowerEarthShieldBtnName"]
				local esIcon = _G["ShamanPowerEarthShieldBtnIcon"]
				if esName and not ShamanPower.opt.hideEarthShieldText then
					local currentTarget = ShamanPower.currentEarthShieldTarget
					local assignedTarget = ShamanPower_EarthShieldAssignments[ShamanPower.player]
					if currentTarget then
						local shortName = Ambiguate(currentTarget, "short")
						esName:SetText(shortName)
						if assignedTarget and currentTarget == assignedTarget then
							esName:SetTextColor(0.2, 1, 0.2)  -- Green - on assigned target
						else
							esName:SetTextColor(1, 0.8, 0)  -- Yellow/Gold - on someone else
						end
						if esIcon then
							esIcon:SetDesaturated(false)
							esIcon:SetVertexColor(1, 1, 1)
						end
					else
						if assignedTarget then
							local shortName = Ambiguate(assignedTarget, "short")
							esName:SetText(shortName)
							esName:SetTextColor(1, 0.3, 0.3)  -- Red - not active
						else
							esName:SetText("None")
							esName:SetTextColor(0.5, 0.5, 0.5)  -- Grey
						end
						if esIcon then
							esIcon:SetDesaturated(true)
							esIcon:SetVertexColor(0.6, 0.6, 0.6)
						end
					end
				end
			end
		end)
	end
	-- Only enable if ES button is visible
	if self.opt.totemBarShowEarthShield ~= false and self:HasEarthShield() then
		self:EnableUpdateSubsystem("esButton")
	else
		self:DisableUpdateSubsystem("esButton")
	end

	esBtn:RegisterForClicks("AnyUp", "AnyDown")

	-- Middle-click to pop out (or return/settings if already popped)
	esBtn:HookScript("OnClick", function(self, button)
		if button == "MiddleButton" then
			-- Check if pop-out is enabled
			if ShamanPower.opt.enableMiddleClickPopOut == false then return end

			-- Debounce
			local now = GetTime()
			if ShamanPower.lastESPopOutTime and (now - ShamanPower.lastESPopOutTime) < 0.3 then
				return
			end
			ShamanPower.lastESPopOutTime = now

			local key = "earthshield"
			if ShamanPower.opt.poppedOut and ShamanPower.opt.poppedOut[key] then
				-- Already popped out
				if IsShiftKeyDown() then
					-- SHIFT+middle-click opens settings
					local frame = ShamanPower.poppedOutFrames[key]
					if frame then
						ShamanPower:ShowPopOutSettingsPanel(key, frame)
					end
				else
					-- Plain middle-click returns to bar
					if InCombatLockdown() then
						print("|cff0070ddShamanPower:|r Cannot modify pop-outs during combat")
						return
					end
					ShamanPower:ReturnPopOutToBar(key)
				end
			else
				-- Not popped out, so pop it out
				if InCombatLockdown() then
					print("|cff0070ddShamanPower:|r Cannot pop out during combat")
					return
				end
				ShamanPower:PopOutEarthShield()
			end
		end
	end)
end

-- ============================================================================
-- Earth Shield Active Overlay (shows current ES target above assigned)
-- ============================================================================

ShamanPower.esActiveOverlay = nil

function ShamanPower:CreateESActiveOverlay()
	local esBtn = _G["ShamanPowerEarthShieldBtn"]
	if not esBtn then return nil end
	if self.esActiveOverlay then return self.esActiveOverlay end

	local overlay = {}

	-- Create frame above the ES button
	local frame = CreateFrame("Frame", "ShamanPowerESActiveOverlay", esBtn)
	frame:SetSize(26, 26)
	do
		local p, rp, ox, oy = self:GetActiveOverlayAnchor()
		frame:SetPoint(p, esBtn, rp, ox, oy)
	end
	frame:SetFrameLevel(esBtn:GetFrameLevel() + 5)
	frame:Hide()

	-- Background
	local bg = frame:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.7)
	overlay.bg = bg

	-- ES Icon
	local icon = frame:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("TOPLEFT", 2, -2)
	icon:SetPoint("BOTTOMRIGHT", -2, 2)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	icon:SetTexture(self.EarthShield and self.EarthShield.icon or "Interface\\Icons\\Spell_Nature_SkinofEarth")
	overlay.icon = icon

	-- Green border (Earth Shield color)
	local borderSize = 2
	local r, g, b = 0.2, 0.8, 0.2

	local borderTop = frame:CreateTexture(nil, "BORDER")
	borderTop:SetPoint("TOPLEFT", 0, 0)
	borderTop:SetPoint("TOPRIGHT", 0, 0)
	borderTop:SetHeight(borderSize)
	borderTop:SetColorTexture(r, g, b, 1)

	local borderBottom = frame:CreateTexture(nil, "BORDER")
	borderBottom:SetPoint("BOTTOMLEFT", 0, 0)
	borderBottom:SetPoint("BOTTOMRIGHT", 0, 0)
	borderBottom:SetHeight(borderSize)
	borderBottom:SetColorTexture(r, g, b, 1)

	local borderLeft = frame:CreateTexture(nil, "BORDER")
	borderLeft:SetPoint("TOPLEFT", 0, 0)
	borderLeft:SetPoint("BOTTOMLEFT", 0, 0)
	borderLeft:SetWidth(borderSize)
	borderLeft:SetColorTexture(r, g, b, 1)

	local borderRight = frame:CreateTexture(nil, "BORDER")
	borderRight:SetPoint("TOPRIGHT", 0, 0)
	borderRight:SetPoint("BOTTOMRIGHT", 0, 0)
	borderRight:SetWidth(borderSize)
	borderRight:SetColorTexture(r, g, b, 1)
	-- a ring round a Rounded / Circle totem bar icon (ShapeOverlayEdge)
	overlay.spEdges = { borderTop, borderBottom, borderLeft, borderRight }
	self:ShapeOverlayEdge(overlay, r, g, b)

	-- Target name text (inside icon)
	local nameText = frame:CreateFontString(nil, "OVERLAY")
	ShamanPower:SetSPFont(nameText, "labels", 8, "OUTLINE")
	nameText:SetPoint("CENTER", frame, "CENTER", 0, 0)
	nameText:SetTextColor(1, 1, 1)
	overlay.nameText = nameText

	-- Charge count (top right)
	local chargeText = frame:CreateFontString(nil, "OVERLAY")
	ShamanPower:SetSPFont(chargeText, "charges", 10, "OUTLINE")
	chargeText:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
	chargeText:SetTextColor(1, 1, 1)
	overlay.chargeText = chargeText

	overlay.frame = frame
	self.esActiveOverlay = overlay
	return overlay
end

function ShamanPower:UpdateESActiveOverlay()
	if not self:HasEarthShield() then return end

	local esBtn = _G["ShamanPowerEarthShieldBtn"]
	if not esBtn then return end

	-- Create overlay if needed
	if not self.esActiveOverlay then
		self:CreateESActiveOverlay()
	end

	local overlay = self.esActiveOverlay
	if not overlay then return end

	-- Compact style: the segmented line carries the target name itself
	if esBtn.compactLayoutOn then
		if overlay.frame then overlay.frame:Hide() end
		return
	end

	local assignedTarget = ShamanPower_EarthShieldAssignments and ShamanPower_EarthShieldAssignments[self.player]
	local currentTarget, charges = self:FindEarthShieldTarget()

	local esIcon = _G["ShamanPowerEarthShieldBtnIcon"]
	local esName = _G["ShamanPowerEarthShieldBtnName"]

	-- Check if current target differs from assigned
	local showOverlay = false
	if currentTarget and assignedTarget then
		-- Normalize names for comparison
		local currentShort = Ambiguate(currentTarget, "short")
		local assignedShort = Ambiguate(assignedTarget, "short")
		if currentShort ~= assignedShort then
			showOverlay = true
		end
	elseif currentTarget and not assignedTarget then
		-- ES is active but no one is assigned - show overlay
		showOverlay = true
	end

	if showOverlay and currentTarget then
		-- Show overlay with current target info
		overlay.frame:Show()

		-- Set target name (truncate if needed)
		local shortName = Ambiguate(currentTarget, "short")
		if #shortName > 5 then
			shortName = shortName:sub(1, 5)
		end
		overlay.nameText:SetText(shortName)

		-- Set charges
		if charges and charges > 0 then
			overlay.chargeText:SetText(charges)
		else
			overlay.chargeText:SetText("")
		end

		-- Grey out the main ES button icon (assigned target)
		if esIcon then
			esIcon:SetDesaturated(true)
			esIcon:SetVertexColor(0.5, 0.5, 0.5)
		end

		-- Update main button name to show assigned (greyed)
		if esName and assignedTarget and not self.opt.hideEarthShieldText then
			local assignedShort = Ambiguate(assignedTarget, "short")
			esName:SetText(assignedShort)
			esName:SetTextColor(0.5, 0.5, 0.5) -- Grey
		end
	else
		-- Hide overlay - ES is on assigned target or not active
		overlay.frame:Hide()

		-- Restore main ES button appearance (handled by UpdateEarthShieldButton)
	end
end

-- ============================================================================
-- Earth Shield Flyout (for quickly casting ES on party/raid members)
-- ============================================================================
-- ES Flyout - OPTIMIZED: Reuses frames, no garbage creation
-- ============================================================================

ShamanPower.esFlyoutButtons = {}  -- Pool of reusable buttons
ShamanPower.esFlyoutButtonCount = 0  -- How many buttons currently in use
ShamanPower.lastESFlyoutSize = 0  -- Track group size to avoid unnecessary rebuilds

-- Pre-computed unit strings for ES flyout (avoids "raid" .. i garbage)
local esFlyoutUnits_raid = {}
local esFlyoutUnits_party = {"player", "party1", "party2", "party3", "party4"}
for i = 1, 40 do
	esFlyoutUnits_raid[i] = "raid" .. i
end

-- Earth Shield flyout filter (issue request): only show players whose group
-- role or class is selected. Empty selection = everyone. The assigned ES
-- target always shows. Raid Main Tanks count as Tanks when they
-- have no LFG role set.
function ShamanPower:ESFlyoutPassesFilter(name, classFilename, unit, raidRole)
	local roles = self.opt.esFlyoutRoles
	local classes = self.opt.esFlyoutClasses
	local anyRole = roles and (roles.TANK or roles.HEALER or roles.DAMAGER)
	local anyClass = false
	if classes then
		for _, v in pairs(classes) do if v then anyClass = true; break end end
	end
	if not anyRole and not anyClass then return true end
	local short = name and Ambiguate(name, "short")
	local assigned = ShamanPower_EarthShieldAssignments and ShamanPower_EarthShieldAssignments[self.player]
	if assigned and short == Ambiguate(assigned, "short") then return true end
	if anyClass and classFilename and classes[classFilename] then return true end
	if anyRole then
		local r = unit and UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit) or "NONE"
		if (not r or r == "NONE") and raidRole == "MAINTANK" then r = "TANK" end
		if r and roles[r] then return true end
	end
	return false
end

function ShamanPower:CreateEarthShieldFlyout(forceRebuild)
	-- CHECK DISABLED FIRST - before any work
	if self.opt.enableESFlyout == false then
		local esBtn = _G["ShamanPowerEarthShieldBtn"]
		if esBtn then
			esBtn:SetAttribute("OpenMenu", nil)
		end
		-- Hide all existing buttons
		for i = 1, self.esFlyoutButtonCount do
			if self.esFlyoutButtons[i] then
				self.esFlyoutButtons[i]:Hide()
			end
		end
		self.esFlyoutButtonCount = 0
		return
	end

	if not self:HasEarthShield() then return end

	-- Skip rebuild if the group size and flyout direction haven't changed
	local currentSize = GetNumGroupMembers()
	local dirSig = (self.opt.layout or "Horizontal") .. (self:FlyoutGoesBelow(_G["ShamanPowerEarthShieldBtn"]) and "b" or "a")
	if not forceRebuild and currentSize == self.lastESFlyoutSize and dirSig == self.lastESFlyoutDir then
		return
	end
	self.lastESFlyoutSize = currentSize
	self.lastESFlyoutDir = dirSig

	local esBtn = _G["ShamanPowerEarthShieldBtn"]
	if not esBtn then return end

	-- Enable the flyout
	esBtn:SetAttribute("OpenMenu", "mouseover")

	local buttonSize = 28
	local spacing = 0
	local spellName = self:GetEarthShieldSpell()
	local swapped = self.opt.swapFlyoutClickButtons
	local layout = self.opt.layout or "Horizontal"
	local flyoutDir = self:FlyoutGoesBelow(_G["ShamanPowerEarthShieldBtn"]) and "below" or "above"

	-- Count and update buttons directly - NO intermediate members table
	local buttonIndex = 0

	if IsInRaid() then
		for i = 1, 40 do
			local name, _, _, _, _, classFilename, _, _, _, raidRole = GetRaidRosterInfo(i)
			if name and self:ESFlyoutPassesFilter(name, classFilename, esFlyoutUnits_raid[i], raidRole) then
				buttonIndex = buttonIndex + 1
				self:UpdateOrCreateESFlyoutButton(buttonIndex, name, classFilename, esFlyoutUnits_raid[i], esBtn, spellName, swapped, buttonSize, spacing, layout, flyoutDir)
			end
		end
	elseif IsInGroup() then
		-- Player first
		local _, classFilename = UnitClass("player")
		buttonIndex = buttonIndex + 1
		self:UpdateOrCreateESFlyoutButton(buttonIndex, UnitName("player"), classFilename, "player", esBtn, spellName, swapped, buttonSize, spacing, layout, flyoutDir)
		-- Party members
		for i = 1, 4 do
			local unit = esFlyoutUnits_party[i + 1]  -- party1-4
			if UnitExists(unit) then
				local name = UnitName(unit)
				local _, classFilename = UnitClass(unit)
				if name and self:ESFlyoutPassesFilter(name, classFilename, unit) then
					buttonIndex = buttonIndex + 1
					self:UpdateOrCreateESFlyoutButton(buttonIndex, name, classFilename, unit, esBtn, spellName, swapped, buttonSize, spacing, layout, flyoutDir)
				end
			end
		end
	else
		-- Solo
		local _, classFilename = UnitClass("player")
		buttonIndex = buttonIndex + 1
		self:UpdateOrCreateESFlyoutButton(buttonIndex, UnitName("player"), classFilename, "player", esBtn, spellName, swapped, buttonSize, spacing, layout, flyoutDir)
	end

	-- Hide any extra buttons (smaller group, or filtered out) and gate them
	-- off from the secure hover-show
	for i = buttonIndex + 1, #self.esFlyoutButtons do
		if self.esFlyoutButtons[i] then
			self.esFlyoutButtons[i]:SetAttribute("esInactive", true)
			self.esFlyoutButtons[i]:Hide()
		end
	end
	self.esFlyoutButtonCount = buttonIndex
end

-- Update an existing button or create a new one if needed
function ShamanPower:UpdateOrCreateESFlyoutButton(index, name, class, unit, esBtn, spellName, swapped, buttonSize, spacing, layout, flyoutDir)
	local btn = self.esFlyoutButtons[index]

	-- Create button only if we don't have one at this index
	if not btn then
		btn = CreateFrame("Button", "ShamanPowerESFlyoutBtn" .. index, esBtn, "SecureActionButtonTemplate, SecureHandlerShowHideTemplate, SecureHandlerEnterLeaveTemplate")
		btn:SetSize(buttonSize, buttonSize)
		btn:SetFrameStrata("DIALOG")

		-- Class icon (created once, updated each time)
		local icon = btn:CreateTexture(nil, "ARTWORK")
		icon:SetAllPoints()
		btn.icon = icon

		-- Player name text
		local nameText = btn:CreateFontString(nil, "OVERLAY")
		ShamanPower:SetSPFont(nameText, "labels", 8, "OUTLINE")
		nameText:SetPoint("CENTER", btn, "CENTER", 0, 0)
		nameText:SetTextColor(1, 1, 1)
		btn.nameText = nameText

		-- Highlight texture
		local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
		highlight:SetAllPoints()
		highlight:SetColorTexture(1, 1, 1, 0.3)

		-- SECURE HANDLER: Respond to parent's ChildUpdate
		ShamanPower:SetSnippet(btn, "_childupdate-show", [[
			if message then
				if not self:GetAttribute("esInactive") then
					self:Show()
				end
			else
				self:Hide()
			end
		]])

		-- SECURE HANDLER: Check parent on leave
		ShamanPower:SetSnippet(btn, "_onleave", SP_SECURE_ONLEAVE_PARENT)
		btn:SetAttribute("spFlyoutProtocol", true)  -- lets sibling leave snippets tell flyout buttons from decoration

		btn:RegisterForClicks("AnyUp", "AnyDown")

		-- Tooltip (uses stored attributes)
		btn:HookScript("OnEnter", function(self)
			if not ShamanPower.opt.ShowTooltips then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			local memberName = self:GetAttribute("memberName")
			local memberClass = self:GetAttribute("memberClass")
			GameTooltip:AddLine(memberName or "Unknown", 1, 1, 1)
			if memberClass and RAID_CLASS_COLORS[memberClass] then
				local classColor = RAID_CLASS_COLORS[memberClass]
				GameTooltip:AddLine(memberClass, classColor.r, classColor.g, classColor.b)
			end
			GameTooltip:AddLine(" ")
			if ShamanPower.opt.swapFlyoutClickButtons then
				GameTooltip:AddLine("|cff00ff00Left-click:|r Assign as ES target", 1, 1, 1)
				GameTooltip:AddLine("|cffffcc00Right-click:|r Cast " .. SPCompat.SpellLabel(974, "Earth Shield"), 1, 1, 1)
			else
				GameTooltip:AddLine("|cff00ff00Left-click:|r Cast " .. SPCompat.SpellLabel(974, "Earth Shield"), 1, 1, 1)
				GameTooltip:AddLine("|cffffcc00Right-click:|r Assign as ES target", 1, 1, 1)
			end
			GameTooltip:Show()
		end)
		btn:HookScript("OnLeave", function() GameTooltip:Hide() end)

		-- Handle assignment
		btn:SetScript("PostClick", function(self, button)
			local assignButton = ShamanPower.opt.swapFlyoutClickButtons and "LeftButton" or "RightButton"
			if button == assignButton then
				local memberName = self:GetAttribute("memberName")
				if memberName then
					ShamanPower_EarthShieldAssignments[ShamanPower.player] = memberName
					ShamanPower:UpdateEarthShieldButton()
					ShamanPower:SendMessage(ShamanPower:EncodeESAssign(ShamanPower.player, memberName))   -- the keyword every client handles (was ES_ASSIGN, never received)
				end
			end
			-- Close the flyout after picking someone, like the totem flyouts
			-- (out of combat only; in combat the secure mouse-leave closes it)
			if not InCombatLockdown() then
				for _, b in ipairs(ShamanPower.esFlyoutButtons) do
					b:Hide()
				end
			end
		end)

		self.esFlyoutButtons[index] = btn
	end

	-- UPDATE existing button with new data (no frame creation, just attribute updates)
	btn:SetParent(esBtn)

	-- Update icon
	local coords = CLASS_ICON_TCOORDS[class]
	if coords then
		btn.icon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
		btn.icon:SetTexCoord(unpack(coords))
	else
		btn.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
		btn.icon:SetTexCoord(0, 1, 0, 1)
	end

	-- Update name text
	local shortName = Ambiguate(name, "short")
	if #shortName > 5 then
		shortName = shortName:sub(1, 5)
	end
	btn.nameText:SetText(shortName)

	-- Store member info as attributes
	btn:SetAttribute("memberName", name)
	btn:SetAttribute("memberUnit", unit)
	btn:SetAttribute("memberClass", class)

	-- Set up casting macro
	local castMacro = "/target " .. name .. "\n/cast " .. spellName .. "\n/targetlasttarget"

	btn:SetAttribute("type1", nil)
	btn:SetAttribute("macrotext1", nil)
	btn:SetAttribute("type2", nil)
	btn:SetAttribute("macrotext2", nil)

	if swapped then
		btn:SetAttribute("type2", "macro")
		btn:SetAttribute("macrotext2", castMacro)
	else
		btn:SetAttribute("type1", "macro")
		btn:SetAttribute("macrotext1", castMacro)
	end

	-- This button is in use (filtered-out and shrunken-group buttons are gated
	-- off so the secure hover-show cannot bring them back)
	btn:SetAttribute("esInactive", false)

	-- Position button
	btn:ClearAllPoints()
	if layout == "Horizontal" then
		if flyoutDir == "below" then
			btn:SetPoint("TOP", esBtn, "BOTTOM", 0, -spacing - (index - 1) * (buttonSize + spacing))
		else
			btn:SetPoint("BOTTOM", esBtn, "TOP", 0, spacing + (index - 1) * (buttonSize + spacing))
		end
	elseif layout == "VerticalLeft" then
		-- VerticalLeft: flyouts go LEFT, same as the totem flyouts
		btn:SetPoint("RIGHT", esBtn, "LEFT", -spacing - (index - 1) * (buttonSize + spacing), 0)
	else
		-- Vertical: flyouts go RIGHT, same as the totem flyouts
		btn:SetPoint("LEFT", esBtn, "RIGHT", spacing + (index - 1) * (buttonSize + spacing), 0)
	end

	btn:Hide()  -- Hidden by default, shown on hover via secure handler
end

function ShamanPower:UpdateEarthShieldFlyout()
	if InCombatLockdown() then return end
	self:CreateEarthShieldFlyout()
end

function ShamanPower:UpdateESFlyoutClickBehavior()
	if InCombatLockdown() then
		print("|cff0070ddShamanPower:|r Cannot change flyout settings in combat")
		return
	end

	local swapped = self.opt.swapFlyoutClickButtons
	local spellName = self:GetEarthShieldSpell()
	if not spellName then return end

	for _, btn in ipairs(self.esFlyoutButtons) do
		local memberName = btn:GetAttribute("memberName")
		if memberName then
			local castMacro = "/target " .. memberName .. "\n/cast " .. spellName .. "\n/targetlasttarget"

			btn:SetAttribute("type1", nil)
			btn:SetAttribute("macrotext1", nil)
			btn:SetAttribute("type2", nil)
			btn:SetAttribute("macrotext2", nil)

			if swapped then
				btn:SetAttribute("type2", "macro")
				btn:SetAttribute("macrotext2", castMacro)
				btn:SetAttribute("assignButton", "LeftButton")
			else
				btn:SetAttribute("type1", "macro")
				btn:SetAttribute("macrotext1", castMacro)
				btn:SetAttribute("assignButton", "RightButton")
			end
		end
	end
end

-- Get unit ID from player name
function ShamanPower:GetUnitFromName(name)
	if not name then return nil end

	-- Normalize the input name (remove server suffix for comparison)
	local shortName = Ambiguate(name, "short")

	-- Check player
	local playerName = UnitName("player")
	if playerName and (playerName == name or playerName == shortName) then return "player" end

	-- Check target
	local targetName = UnitName("target")
	if targetName and (targetName == name or targetName == shortName) then return "target" end

	-- Check party
	for i = 1, 4 do
		local unitName = UnitName("party" .. i)
		if unitName and (unitName == name or unitName == shortName) then return "party" .. i end
	end

	-- Check raid
	for i = 1, 40 do
		local unitName = UnitName("raid" .. i)
		if unitName and (unitName == name or unitName == shortName) then return "raid" .. i end
	end

	return nil
end

-- Get Earth Shield charges on a target
function ShamanPower:GetEarthShieldCharges(targetName)
	local unit = self:GetUnitFromName(targetName)
	if not unit then return 0 end

	-- Get the localized spell name for Earth Shield
	local esSpellName = nil
	if self.EarthShield then
		esSpellName = GetSpellInfo(self.EarthShield.rank3) or GetSpellInfo(self.EarthShield.rank2) or GetSpellInfo(self.EarthShield.rank1)
	end

	-- Search for Earth Shield buff
	for i = 1, 40 do
		local name, icon, count, debuffType, duration, expirationTime, source = SPCompat.UnitBuff(unit, i)
		if not name then break end
		-- Check if it's Earth Shield (by localized name)
		if esSpellName and name == esSpellName then
			return count or 0
		end
	end

	return 0
end

-- ============================================================================
-- Earth Shield Tracking (Event-based, like TotemTimers)
-- Tracks who has ES by watching your casts, NOT by scanning all raid members
-- ============================================================================

-- Tracked ES target info (set when you cast ES)
ShamanPower.esTrackedTarget = nil      -- Name of player with your ES
ShamanPower.esTrackedTargetGUID = nil  -- GUID of player with your ES
ShamanPower.esTrackedCharges = 0       -- Current charges
ShamanPower.esLastCastTarget = nil     -- Pending cast target (from SENT)
ShamanPower.esLastCastGUID = nil       -- Pending cast GUID
ShamanPower.cachedESSpellName = nil    -- Cached spell name

-- Get the ES spell name (cached)
function ShamanPower:GetESSpellName()
	if self.cachedESSpellName then return self.cachedESSpellName end
	if not self.EarthShield then return nil end
	self.cachedESSpellName = GetSpellInfo(self.EarthShield.rank3) or GetSpellInfo(self.EarthShield.rank2) or GetSpellInfo(self.EarthShield.rank1)
	return self.cachedESSpellName
end

-- Handle ES spell cast events
function ShamanPower:OnEarthShieldCastSent(target, castGUID, spellID)
	local esSpellName = self:GetESSpellName()
	if not esSpellName then return end

	local spellName = GetSpellInfo(spellID)
	if spellName == esSpellName then
		-- Store pending cast info
		self.esLastCastTarget = target
		self.esLastCastGUID = UnitGUID(target)
		-- The SENT target is a name; resolve it through the tokens that can carry
		-- your shield: yourself, target, focus, party, raid (group identity stays
		-- readable in combat on restricted clients).
		if not self.esLastCastGUID and target then
			local bare = target:match("^[^%-]+") or target
			local tokens = { "player", "target", "focus" }
			for i = 1, 4 do tokens[#tokens + 1] = "party" .. i end
			if IsInRaid() then for i = 1, 40 do tokens[#tokens + 1] = "raid" .. i end end
			for _, u in ipairs(tokens) do
				if UnitExists(u) then
					local n = UnitName(u)
					if n == target or n == bare then
						self.esLastCastGUID = UnitGUID(u)
						break
					end
				end
			end
		end
	end
end

function ShamanPower:OnEarthShieldCastSucceeded(unit, castGUID, spellID)
	if unit ~= "player" then return end

	local esSpellName = self:GetESSpellName()
	if not esSpellName then return end

	local spellName = GetSpellInfo(spellID)
	if spellName == esSpellName and self.esLastCastTarget then
		-- Cast succeeded! Update tracked target
		self.esTrackedTarget = self.esLastCastTarget
		self.esTrackedTargetGUID = self.esLastCastGUID
		self:UpdateAuraCarrierFilter()   -- aura events follow the new carrier
		self.esTrackedCharges = 6  -- Full charges on fresh cast (will be updated by UNIT_AURA)
		self.esTrackedExpiration = nil   -- (read with the charges, from the carrier's aura)

		-- Clear pending
		self.esLastCastTarget = nil
		self.esLastCastGUID = nil

		-- Update display
		self:UpdateEarthShieldButton()
	end
end

-- Find who carries your Earth Shield when nothing is tracked (login, /reload,
-- restrictions clearing): scan yourself, party and raid for the aura you cast.
function ShamanPower:DiscoverEarthShieldTarget()
	if self.esTrackedTargetGUID or totemsSecretNow() then return end
	local esSpellName = self:GetESSpellName()
	if not esSpellName then return end
	local tokens = { "player" }
	for i = 1, 4 do tokens[#tokens + 1] = "party" .. i end
	if IsInRaid() then for i = 1, 40 do tokens[#tokens + 1] = "raid" .. i end end
	for _, u in ipairs(tokens) do
		if UnitExists(u) then
			for i = 1, 40 do
				local name, _, count, _, _, expiration, source = SPCompat.UnitBuff(u, i)
				if not name then break end
				if name == esSpellName and source == "player" then
					self.esTrackedTarget = UnitName(u)
					self.esTrackedTargetGUID = UnitGUID(u)
					self:UpdateAuraCarrierFilter()   -- aura events follow the new carrier
					self.esTrackedCharges = count or 0
					self.esTrackedExpiration = (type(expiration) == "number" and not issecretvalue(expiration)) and expiration or nil
					self:UpdateEarthShieldButton()
					return
				end
			end
		end
	end
end

-- Re-read the tracked Earth Shield target's aura once it is readable again
function ShamanPower:RefreshEarthShieldTarget()
	if not self.esTrackedTargetGUID then
		self:DiscoverEarthShieldTarget()
		return
	end
	local tokens = { "player", "target", "focus" }
	for i = 1, 4 do tokens[#tokens + 1] = "party" .. i end
	if IsInRaid() then for i = 1, 40 do tokens[#tokens + 1] = "raid" .. i end end
	for _, u in ipairs(tokens) do
		if UnitExists(u) and UnitGUID(u) == self.esTrackedTargetGUID then
			self:OnEarthShieldAuraChange(u)
			return
		end
	end
end

-- Handle aura changes on tracked target
-- TBC Anniversary: the carrier (a tank, in a raid) has aura changes all the time,
-- and each read of its buffs builds a ~1.9 KB record per buff. The game says what
-- changed: only an Earth Shield added, or a change to the one known (its charges,
-- its removal), is read. Anything unclear reads, as before (see
-- PlayerShieldMayHaveChanged). Not on WoW: Forever.
function ShamanPower:TrackedEarthShieldMayHaveChanged(info, esSpellName)
	if SPCompat.FOREVER then return true end
	if not SPCompat.AuraInfoReadable(info) or info.isFullUpdate then return true end
	local added = info.addedAuras
	if added then
		for i = 1, #added do
			local a = added[i]
			if issecretvalue(a) then return true end
			local name = a and a.name
			if issecretvalue(name) or name == esSpellName then return true end
		end
	end
	local id = self.esTrackedAuraGUID == self.esTrackedTargetGUID and self.esTrackedAuraInstanceID or nil
	if not id then return true end
	local upd = info.updatedAuraInstanceIDs
	if upd then for i = 1, #upd do local v = upd[i] if issecretvalue(v) or v == id then return true end end end
	local rem = info.removedAuraInstanceIDs
	if rem then for i = 1, #rem do local v = rem[i] if issecretvalue(v) or v == id then return true end end end
	return false
end

function ShamanPower:OnEarthShieldAuraChange(unit, info)
	if not self.esTrackedTargetGUID then return end
	-- Charges on another player cannot be read while auras are secret; keep the
	-- last known state rather than treating "nothing readable" as "fell off".
	if totemsSecretNow() then return end

	-- Only process if this is our ES target
	if UnitGUID(unit) ~= self.esTrackedTargetGUID then return end

	local esSpellName = self:GetESSpellName()
	if not esSpellName then return end
	if not self:TrackedEarthShieldMayHaveChanged(info, esSpellName) then return end

	-- Check this ONE unit for ES buff
	local found = false
	for i = 1, 40 do
		local name, _, count, _, _, expiration, source = SPCompat.UnitBuff(unit, i)
		if not name then break end
		if name == esSpellName and source == "player" then
			self.esTrackedCharges = count or 0
			-- its end, for Running Out (Cooldown Bar > Effects) in its last seconds
			self.esTrackedExpiration = (type(expiration) == "number" and not issecretvalue(expiration)) and expiration or nil
			found = true
			-- TBC Anniversary: its instance, for TrackedEarthShieldMayHaveChanged
			self.esTrackedAuraInstanceID, self.esTrackedAuraGUID = nil, nil
			if not SPCompat.FOREVER and C_UnitAuras and C_UnitAuras.GetBuffDataByIndex then
				local ok, a = pcall(C_UnitAuras.GetBuffDataByIndex, unit, i)
				if ok and type(a) == "table" and a.name == name then
					self.esTrackedAuraInstanceID, self.esTrackedAuraGUID = a.auraInstanceID, self.esTrackedTargetGUID
				end
			end
			break
		end
	end

	if not found then
		-- ES fell off
		self.esTrackedTarget = nil
		self.esTrackedTargetGUID = nil
		self:UpdateAuraCarrierFilter()   -- aura events follow the new carrier
		self.esTrackedCharges = 0
		self.esTrackedExpiration = nil
	end

	-- Update display (but not full rebuild)
	self:UpdateEarthShieldCharges()
end

-- Find who currently has YOUR Earth Shield (uses tracked data, NO scanning!)
function ShamanPower:FindEarthShieldTarget()
	if not self.EarthShield then return nil, 0 end

	-- Just return the tracked target (set by cast events)
	if self.esTrackedTarget and self.esTrackedTargetGUID then
		-- Verify they still exist and have ES (quick single-unit check)
		local unit = nil
		-- Try to find a valid unit ID for the tracked GUID
		if UnitGUID("target") == self.esTrackedTargetGUID then
			unit = "target"
		elseif UnitGUID("focus") == self.esTrackedTargetGUID then
			unit = "focus"
		elseif UnitGUID("player") == self.esTrackedTargetGUID then
			unit = "player"
		else
			-- Check party/raid
			if IsInRaid() then
				for i = 1, 40 do
					if UnitGUID("raid" .. i) == self.esTrackedTargetGUID then
						unit = "raid" .. i
						break
					end
				end
			else
				for i = 1, 4 do
					if UnitGUID("party" .. i) == self.esTrackedTargetGUID then
						unit = "party" .. i
						break
					end
				end
			end
		end

		if unit and UnitExists(unit) then
			return self.esTrackedTarget, self.esTrackedCharges
		else
			-- Target left group or doesn't exist
			self.esTrackedTarget = nil
			self.esTrackedTargetGUID = nil
			self:UpdateAuraCarrierFilter()   -- aura events follow the new carrier
			self.esTrackedCharges = 0
		end
	end

	return nil, 0
end

-- Update the charge display on the button
-- Earth Shield aura IDs: TBC ranks plus retail's aura (383648; the cast is 974)
ShamanPower.EarthShieldAuraIDs = { 974, 32593, 32594, 383648 }

-- Group token of the player carrying your Earth Shield (nil if not in view)
function ShamanPower:EarthShieldUnitToken()
	local guid = self.esTrackedTargetGUID
	if not guid then return nil end
	local tokens = { "player" }
	for i = 1, 4 do tokens[#tokens + 1] = "party" .. i end
	if IsInRaid() then for i = 1, 40 do tokens[#tokens + 1] = "raid" .. i end end
	for _, u in ipairs(tokens) do
		if UnitExists(u) and UnitGUID(u) == guid then return u end
	end
	return nil
end

-- Engine-drawn Earth Shield charge count on the totem bar button for restricted
-- clients: while auras are secret an AuraContainer pointed at the carrier's
-- group token draws the real count in the button's corner (fixed green); the
-- addon's own count shows out of combat.
function ShamanPower:EnsureESButtonContainer(esBtn)
	if not (SPCompat and SPCompat.secretsRegime) then return end
	if esBtn.chargeContainer then return end
	if C_AddOns and C_AddOns.LoadAddOn then pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer") end
	local ok, container = pcall(CreateFrame, "AuraContainer", nil, esBtn, "CustomAuraContainerTemplate")
	if not ok or not container then return end
	container:SetAllPoints(esBtn)
	container:SetFrameLevel(esBtn:GetFrameLevel() + 6)
	local idMap = {}
	for _, id in ipairs(self.EarthShieldAuraIDs) do idMap[id] = true end
	pcall(function()
		container:AddAuraSlot("es", "HELPFUL|PLAYER", {
			candidateFilters = { includeSpellIDs = idMap },
			initializeFrame = function(button)
				button:ClearAllPoints()
				button:SetAllPoints(esBtn)
				if button.SetMouseClickEnabled then pcall(button.SetMouseClickEnabled, button, false) end
				if button.SetMouseMotionEnabled then pcall(button.SetMouseMotionEnabled, button, false) end
				local carrier = CreateFrame("Frame", nil, button)
				carrier:SetAllPoints(button)
				local count = carrier:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
				ShamanPower:AdoptSPFont(count, "charges")   -- template font = the design; follows the Fonts settings
				ShamanPower:SPFontGameOwned(count)   -- (on the game's button: a font change waits out fights and hidden auras)
				count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
				count:SetJustifyH("RIGHT")
				count:SetTextColor(0, 1, 0)   -- fixed green; a per-charge color would need the secret value
				pcall(button.SetApplicationCount, button, count, {})
			end,
		})
	end)
	pcall(container.SetUnit, container, "none")
	container:Hide()
	esBtn.chargeContainer = container
end

function ShamanPower:UpdateEarthShieldCharges()
	local chargeText = _G["ShamanPowerEarthShieldBtnCharges"]
	if not chargeText then return end

	-- Restricted client: the engine draws the count on the carrier's unit
	local esBtn = _G["ShamanPowerEarthShieldBtn"]
	local container = esBtn and esBtn.chargeContainer
	if container then
		local restricted = totemsSecretNow()
		if restricted then
			local unit = self:EarthShieldUnitToken() or "none"
			if container.engineUnit ~= unit then
				container.engineUnit = unit
				pcall(container.SetUnit, container, unit)
				pcall(container.UpdateAllAuras, container)
			end
		end
		if container:IsShown() ~= restricted then container:SetShown(restricted) end
		if restricted then
			chargeText:SetText("")
			self.currentEarthShieldTarget = self.esTrackedTarget
			return
		end
	end

	-- Find who currently has our Earth Shield
	local currentTarget, charges = self:FindEarthShieldTarget()

	if currentTarget and charges and charges > 0 then
		chargeText:SetText(NumberStrings[charges] or tostring(charges))
		-- Color based on charges if enabled (Earth Shield has more charges: 6-10)
		if self.opt.shieldChargeColors then
			if charges >= 5 then
				chargeText:SetTextColor(0, 1, 0)  -- Green (healthy)
			elseif charges >= 3 then
				chargeText:SetTextColor(1, 1, 0)  -- Yellow (getting low)
			else
				chargeText:SetTextColor(1, 0, 0)  -- Red (critical - 1-2 charges)
			end
		else
			chargeText:SetTextColor(1, 1, 1)  -- White (default)
		end
	else
		chargeText:SetText("")
	end

	-- Store current target for display purposes
	self.currentEarthShieldTarget = currentTarget
	-- Running Out (Cooldown Bar > Effects): its last seconds or 2 charges (ShamanPowerCues.lua)
	if self.RunOutEarthShield and esBtn then self:RunOutEarthShield(esBtn, currentTarget, charges) end
end

-- Check if a player is dead (by name)
function ShamanPower:IsPlayerDead(playerName)
	if not playerName then return true end
	local unit = self:GetUnitFromName(playerName)
	if not unit then return true end  -- Can't find them, treat as unavailable
	return UnitIsDeadOrGhost(unit)
end

function ShamanPower:UpdateEarthShieldButton()
	if InCombatLockdown() then return end
	if not self.autoButton then return end
	-- switched off: a cast or an aura change must not bring the button (a UIParent child) up
	if self:IsOff() then
		local esBtn = _G["ShamanPowerEarthShieldBtn"]
		if esBtn then esBtn:Hide() end
		return
	end

	-- Create button if it doesn't exist
	self:CreateEarthShieldButton()

	local esBtn = _G["ShamanPowerEarthShieldBtn"]
	if not esBtn then return end

	-- Enable/disable esButton subsystem based on visibility
	local shouldShow = (self.opt.totemBarShowEarthShield ~= false) and self:HasEarthShield() and not self.totemBarHidden
	if shouldShow then
		self:EnableUpdateSubsystem("esButton")
	else
		self:DisableUpdateSubsystem("esButton")
	end

	-- Check if totem bar is hidden (hide out of combat / hide when no totems)
	if self.totemBarHidden then
		esBtn:Hide()
		return
	end

	-- Check if Earth Shield button should be hidden
	if self.opt.totemBarShowEarthShield == false then
		esBtn:Hide()
		return
	end

	local esIcon = _G["ShamanPowerEarthShieldBtnIcon"]
	local esName = _G["ShamanPowerEarthShieldBtnName"]

	-- Check if we have Earth Shield talent
	local hasES = self:HasEarthShield()
	local assignedTarget = ShamanPower_EarthShieldAssignments[self.player]

	-- Find who currently has our Earth Shield (fetch fresh, don't rely on cached value)
	local currentTarget, currentCharges = self:FindEarthShieldTarget()
	self.currentEarthShieldTarget = currentTarget  -- Update cache

	if hasES then
		-- Get the spell name
		local spellName = self:GetEarthShieldSpell()
		if spellName then
			-- Determine who to cast on:
			-- Dynamic mode: prioritize current target (refresh existing shield)
			-- Normal mode: prioritize assigned target
			local castTarget = nil
			if self.opt.dynamicTotemMode then
				-- Dynamic mode: prefer whoever currently has ES, fall back to assigned
				if currentTarget and not self:IsPlayerDead(currentTarget) then
					castTarget = currentTarget
					-- Update assignment to match current target
					if currentTarget ~= assignedTarget then
						ShamanPower_EarthShieldAssignments[self.player] = currentTarget
					end
				elseif assignedTarget and not self:IsPlayerDead(assignedTarget) then
					castTarget = assignedTarget
				end
			else
				-- Normal mode: prefer assigned target, fall back to current
				if assignedTarget and not self:IsPlayerDead(assignedTarget) then
					castTarget = assignedTarget
				elseif currentTarget and not self:IsPlayerDead(currentTarget) then
					castTarget = currentTarget
				end
			end

			if castTarget then
				esBtn:SetAttribute("type1", "macro")
				esBtn:SetAttribute("macrotext1", "/target " .. castTarget .. "\n/cast " .. spellName .. "\n/targetlasttarget")
			else
				-- No valid target - just cast on current target
				esBtn:SetAttribute("type1", "spell")
				esBtn:SetAttribute("spell1", spellName)
			end

			-- Update icon
			if esIcon then
				esIcon:SetTexture(self.EarthShield.icon)
				-- Desaturate icon if no one has ES
				if not currentTarget then
					esIcon:SetDesaturated(true)
					esIcon:SetVertexColor(0.6, 0.6, 0.6)
				else
					esIcon:SetDesaturated(false)
					esIcon:SetVertexColor(1, 1, 1)
				end
			end

			-- Show who currently has Earth Shield (unless hidden by option, or
			-- the button is a Compact line, which never carries a name)
			if esName then
				if self.opt.hideEarthShieldText or esBtn.compactLayoutOn then
					esName:Hide()
				else
					if currentTarget then
						-- Someone has ES - show their name
						local shortName = Ambiguate(currentTarget, "short")
						esName:SetText(shortName)
						-- Color based on whether it's the assigned target
						if assignedTarget and currentTarget == assignedTarget then
							esName:SetTextColor(0.2, 1, 0.2)  -- Green - on assigned target
						else
							esName:SetTextColor(1, 0.8, 0)  -- Yellow/Gold - on someone else
						end
					else
						-- No one has ES
						if assignedTarget then
							local shortName = Ambiguate(assignedTarget, "short")
							esName:SetText(shortName)
							esName:SetTextColor(1, 0.3, 0.3)  -- Red - not active
						else
							esName:SetText("None")
							esName:SetTextColor(0.5, 0.5, 0.5)  -- Grey
						end
					end
					esName:Show()
				end
			end

			esBtn:Show()

			-- Reposition in the mini bar
			self:RepositionEarthShieldButton()

			-- Create/update ES flyout for party/raid members
			self:CreateEarthShieldFlyout()

			-- Re-apply the overlay pass in this same frame: this repaint colors
			-- the icon/name, and without this the 0.5s overlay tick greys them
			-- again half a second later - the two alternate visibly (the ES
			-- "blink" with an unassigned active shield)
			self:UpdateESActiveOverlay()
		else
			esBtn:Hide()
		end
	else
		esBtn:Hide()
		if esName then esName:Hide() end
	end
end

function ShamanPower:RepositionEarthShieldButton()
	local esBtn = _G["ShamanPowerEarthShieldBtn"]
	if not esBtn or not esBtn:IsShown() then return end
	if not self.autoButton then return end

	-- Skip repositioning if Earth Shield is popped out
	if self:IsEarthShieldPoppedOut() then return end

	-- Match scale of other totem buttons
	esBtn:SetScale(self.opt.buffscale or 0.9)

	local isHorizontal = self:IsTotemBarHorizontal()
	local buttonSize = 26
	local spacing = self:TotemBarSpacing()   -- Button Spacing, plus room for dots between the buttons
	local showDropAll = self:ShowsDropAllButton()
	local dropAllPoppedOut = self:IsDropAllPoppedOut()
	local showTotemicCall = self:CdItemOpt(2, "onTotemBar") and self.opt.cdbarShowRecall ~= false

	-- Find the anchor point - Totemic Call > Drop All > last visible totem button
	local anchorFrame = nil
	local totemicCallBtn = _G["ShamanPowerAutoTotemicCall"]
	local dropAllBtn = _G["ShamanPowerAutoDropAll"]

	-- First check Totemic Call (it's positioned after Drop All)
	if showTotemicCall and totemicCallBtn and totemicCallBtn:IsShown() then
		anchorFrame = totemicCallBtn
	elseif showDropAll and dropAllBtn and dropAllBtn:IsShown() and not dropAllPoppedOut then
		-- Anchor to Drop All button (only if not popped out)
		anchorFrame = dropAllBtn
	else
		-- Find the last visible totem button based on totemBarOrder
		-- Exclude popped-out elements (they're reparented elsewhere)
		local totemOrder = self.opt.totemBarOrder or {1, 2, 3, 4}
		local elementVisible = {
			[1] = self:IsElementShown(1) and not self:IsElementPoppedOut(1),
			[2] = self:IsElementShown(2) and not self:IsElementPoppedOut(2),
			[3] = self:IsElementShown(3) and not self:IsElementPoppedOut(3),
			[4] = self:IsElementShown(4) and not self:IsElementPoppedOut(4),
		}

		-- Find the last visible element in order
		for i = 4, 1, -1 do
			local element = totemOrder[i]
			if elementVisible[element] and self.totemButtons[element] then
				anchorFrame = self.totemButtons[element]
				break
			end
		end
	end

	esBtn:ClearAllPoints()

	if anchorFrame then
		if self:CompactActive() then
			-- Compact: the ES line lines up with the totem lines' edge
			if isHorizontal then
				esBtn:SetPoint("TOPLEFT", anchorFrame, "TOPRIGHT", spacing, 0)
			else
				esBtn:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, -spacing)
			end
		elseif isHorizontal then
			-- Position to the right of anchor with padding
			esBtn:SetPoint("LEFT", anchorFrame, "RIGHT", spacing, 0)
		else
			-- Position below anchor with padding
			esBtn:SetPoint("TOP", anchorFrame, "BOTTOM", 0, -spacing)
		end
	else
		-- No anchor - position at start of autoButton
		local padding = 4
		if isHorizontal then
			esBtn:SetPoint("TOPLEFT", self.autoButton, "TOPLEFT", padding, -padding)
		else
			esBtn:SetPoint("TOPLEFT", self.autoButton, "TOPLEFT", padding, -padding)
		end
	end

	-- Update autoButton size to include ES button
	self:UpdateAutoButtonSize()
end

function ShamanPower:UpdateAutoButtonSize()
	if not self.autoButton then return end

	local padding = 4
	local buttonSize = 26
	local spacing = self:TotemBarSpacing()   -- Button Spacing, plus room for dots between the buttons
	local isHorizontal = self:IsTotemBarHorizontal()
	local _, _, sw, sh = self:GetTotemSlotDims()
	local slotAlong = isHorizontal and sw or sh
	local startOff = self.CompactStartOffset and self:CompactStartOffset() or 0
	local showDropAll = self:ShowsDropAllButton() and not self:IsDropAllPoppedOut()
	local showES = self.opt.totemBarShowEarthShield ~= false and self:HasEarthShield() and not self:IsEarthShieldPoppedOut()

	-- Count visible totem buttons (not hidden in options and not popped out)
	local visibleCount = 0
	if self:IsElementShown(1) and not self:IsElementPoppedOut(1) then visibleCount = visibleCount + 1 end
	if self:IsElementShown(2) and not self:IsElementPoppedOut(2) then visibleCount = visibleCount + 1 end
	if self:IsElementShown(3) and not self:IsElementPoppedOut(3) then visibleCount = visibleCount + 1 end
	if self:IsElementShown(4) and not self:IsElementPoppedOut(4) then visibleCount = visibleCount + 1 end

	local baseSize = (startOff + slotAlong * visibleCount) + (spacing * math.max(0, visibleCount - 1))

	if isHorizontal then
		local totalWidth = padding * 2
		if visibleCount > 0 then
			totalWidth = totalWidth + baseSize
		end
		if showDropAll and visibleCount > 0 then
			totalWidth = totalWidth + spacing + buttonSize
		elseif showDropAll then
			totalWidth = totalWidth + buttonSize
		end
		if showES then
			totalWidth = totalWidth + spacing + (self:CompactActive() and slotAlong or buttonSize)
		end
		self.autoButton:SetWidth(math.max(totalWidth, buttonSize + padding * 2))
	else
		local totalHeight = padding * 2
		if visibleCount > 0 then
			totalHeight = totalHeight + baseSize
		end
		if showDropAll and visibleCount > 0 then
			totalHeight = totalHeight + spacing + buttonSize
		elseif showDropAll then
			totalHeight = totalHeight + buttonSize
		end
		if showES then
			totalHeight = totalHeight + spacing + (self:CompactActive() and slotAlong or buttonSize)
		end
		self.autoButton:SetHeight(math.max(totalHeight, buttonSize + padding * 2))
	end
end

-- ============================================================================
-- Drop All Button - cycles through all 4 totems
-- ============================================================================

ShamanPower.dropAllCurrentElement = 1  -- Start with Earth
ShamanPower.dropAllSequence = {}  -- Ordered list of {element, spellName, icon}
ShamanPower.dropAllInCombat = false  -- Track if we were in combat
ShamanPower.dropAllLastMacro = ""  -- Track last macro to avoid unnecessary rebuilds
ShamanPower.dropAllMiddleClickHooked = false  -- Track if we've hooked middle-click

-- Build the totem sequence and update the Drop All button
function ShamanPower:UpdateDropAllButton()
	-- Reset sequence when leaving combat (mimics castsequence reset=combat)
	local inCombat = InCombatLockdown()
	if self.dropAllInCombat and not inCombat then
		self.dropAllCurrentElement = 1
		self.dropAllLastMacro = ""  -- Force macro rebuild after combat
	end
	self.dropAllInCombat = inCombat
	local dropAllBtn = _G["ShamanPowerAutoDropAll"]
	if not dropAllBtn then return end

	-- One-time setup: Add middle-click handler for pop-out (or return/settings if already popped)
	if not self.dropAllMiddleClickHooked then
		self.dropAllMiddleClickHooked = true
		dropAllBtn:HookScript("OnClick", function(self, button)
			if button == "MiddleButton" then
				-- Check if pop-out is enabled
				if ShamanPower.opt.enableMiddleClickPopOut == false then return end

				-- Debounce
				local now = GetTime()
				if ShamanPower.lastDropAllPopOutTime and (now - ShamanPower.lastDropAllPopOutTime) < 0.3 then
					return
				end
				ShamanPower.lastDropAllPopOutTime = now

				local key = "dropall"
				if ShamanPower.opt.poppedOut and ShamanPower.opt.poppedOut[key] then
					-- Already popped out
					if IsShiftKeyDown() then
						-- SHIFT+middle-click opens settings
						local frame = ShamanPower.poppedOutFrames[key]
						if frame then
							ShamanPower:ShowPopOutSettingsPanel(key, frame)
						end
					else
						-- Plain middle-click returns to bar
						if InCombatLockdown() then
							print("|cff0070ddShamanPower:|r Cannot modify pop-outs during combat")
							return
						end
						ShamanPower:ReturnPopOutToBar(key)
					end
				else
					-- Not popped out, so pop it out
					if InCombatLockdown() then
						print("|cff0070ddShamanPower:|r Cannot pop out during combat")
						return
					end
					ShamanPower:PopOutDropAll()
				end
			end
		end)
	end

	-- Clients with totem sets (WoW: Forever): the button casts the sets instead
	if self.UpdateDropAllButtonForTotemSets and self:UpdateDropAllButtonForTotemSets(dropAllBtn) then return end

	local playerName = self.player
	local assignments = ShamanPower_Assignments[playerName]
	if not assignments then return end

	-- Build ordered list of assigned totems using custom drop order
	local newSequence = {}
	local totemSpells = {}
	local dropOrder = self.opt.dropOrder or {1, 2, 3, 4}
	-- Build exclude table for easy lookup
	local excludeTotem = {
		[1] = self.opt.excludeEarthFromDropAll,
		[2] = self.opt.excludeFireFromDropAll,
		[3] = self.opt.excludeWaterFromDropAll,
		[4] = self.opt.excludeAirFromDropAll,
	}
	for _, element in ipairs(dropOrder) do
		-- Skip if this totem type is excluded
		if not excludeTotem[element] then
			local totemIndex = assignments[element] or 0
			if totemIndex and totemIndex > 0 then
				local spellID = self:GetTotemSpell(element, totemIndex)
				if spellID then
					local spellName = GetSpellInfo(spellID)
					-- Fallback to our stored name if GetSpellInfo fails
					if SPCompat.HasTotemCastAliases(spellID) then spellName = SPCompat.TotemCastName(spellID) end
					if not spellName and (GetLocale() == "enUS" or GetLocale() == "enGB") then
						spellName = self:GetTotemName(element, totemIndex)
						-- Add "Totem" suffix if not present (for castsequence compatibility)
						if spellName and not spellName:find("Totem") and not spellName:find("Elemental") then
							spellName = spellName .. " Totem"
						end
					end
					if spellName then
						local icon = self:GetTotemIcon(element, totemIndex)
						table.insert(newSequence, {element = element, spellName = spellName, icon = icon})
						table.insert(totemSpells, spellName)
					end
				end
			end
		end
	end

	-- Build the macro text to check if it changed
	local sequenceText, macroText = nil, ""
	if #totemSpells > 0 then
		sequenceText = "reset=combat/15 " .. table.concat(totemSpells, ", ")
		macroText = "/castsequence " .. sequenceText
	end

	-- Only update sequence and macro if the spell list actually changed
	if macroText ~= self.dropAllLastMacro then
		-- Update the cached sequence
		self.dropAllSequence = newSequence

		-- Set up as a castsequence macro (only outside combat)
		if not InCombatLockdown() then
			dropAllBtn:RegisterForClicks("AnyUp", "AnyDown")
			if #totemSpells > 0 then
				dropAllBtn:SetAttribute("type", "macro")
				dropAllBtn:SetAttribute("macrotext", macroText)
			else
				dropAllBtn:SetAttribute("type", nil)
				dropAllBtn:SetAttribute("macrotext", nil)
			end
			self.dropAllLastMacro = macroText
			-- what the button now really casts: its icon follows this sequence
			self:SetDropAllLiveSequence(newSequence, sequenceText)
		end
	end

	-- Reset to first element if current is out of bounds
	if self.dropAllCurrentElement > #self.dropAllSequence then
		self.dropAllCurrentElement = 1
	end
	if self.dropAllCurrentElement < 1 then
		self.dropAllCurrentElement = 1
	end

	-- Update icon to show next totem
	self:UpdateDropAllIcon()
end

-- The sequence the button's /castsequence really runs (written with its macro text,
-- out of combat; a fight keeps the old one until it ends) and the name the game's
-- cast-sequence manager files it under: the text after /castsequence, as the game's
-- own option parser hands it over.
function ShamanPower:SetDropAllLiveSequence(seq, sequenceText)
	local key = sequenceText
	if key and type(SecureCmdOptionParse) == "function" then
		local ok, parsed = pcall(SecureCmdOptionParse, key)
		if ok and type(parsed) == "string" and parsed ~= "" then key = parsed end
	end
	if key ~= self.dropAllSequenceKey then self.dropAllCurrentElement = 1 end   -- a new sequence starts at its first totem
	self.dropAllLiveSequence = key and seq or nil
	self.dropAllSequenceKey = key
end

-- Which step the Drop All button casts next (0 = none) and the sequence it is in.
-- The game's own cast-sequence manager runs the button: a step moves on only once
-- its totem's cast went through (a press during the global cooldown changes
-- nothing), and the sequence starts over after its last totem, when a fight ends,
-- 15 seconds after its last press, and on death. QueryCastSequence (both clients)
-- asks that manager; without it, the count kept from your own casts stands in.
function ShamanPower:DropAllStep()
	local seq = self.dropAllLiveSequence or self.dropAllSequence
	local n = #seq
	if n == 0 then return 0, seq end
	local key, query = self.dropAllSequenceKey, QueryCastSequence
	if key and type(query) == "function" and not self._dropAllQueryBroken then
		local ok, index = pcall(query, key)
		if ok and type(index) == "number" and not issecretvalue(index) and index >= 1 and index <= n then
			if index > 1 then self._dropAllQueryProven = true end
			-- a press just dropped the first totem, so the game's sequence has moved on: still
			-- step 1 twice means it is not found by this name. Then the count stands in.
			if self._dropAllQueryCheck then
				self._dropAllQueryCheck = nil
				if index == 1 and not self._dropAllQueryProven then
					self._dropAllQueryMisses = (self._dropAllQueryMisses or 0) + 1
					if self._dropAllQueryMisses >= 2 then self._dropAllQueryBroken = true end
				end
			end
			if not self._dropAllQueryBroken then return index, seq end
		end
	end
	local i = self.dropAllCurrentElement or 1
	if i < 1 or i > n then i = 1 end
	return i, seq
end

-- How long the button's sequence waits after a press before it starts over (its reset=)
function ShamanPower:DropAllResetSeconds()
	return tonumber(((self.dropAllSequenceKey or ""):match("^reset=[^%s]-(%d+)"))) or 15
end

-- Update just the icon (can be called in combat)
function ShamanPower:UpdateDropAllIcon()
	if self.dropAllTotemSetsActive then return end   -- totem sets own the icon
	local dropAllBtn = _G["ShamanPowerAutoDropAll"]
	if not dropAllBtn then return end

	local iconTexture = dropAllBtn.icon or _G["ShamanPowerAutoDropAllIcon"]
	if not iconTexture then return end

	-- Show the icon of the totem the button casts next
	local step, seq = self:DropAllStep()
	if step > 0 then
		local current = seq[step]
		if current and current.icon then
			iconTexture:SetTexture(current.icon)
		end
	else
		-- Default to generic totem icon if no sequence
		iconTexture:SetTexture(136024)
	end
end
function ShamanPower.DropAllRefresh() ShamanPower:UpdateDropAllIcon() end

-- The button's PostClick (ShamanPower_TBC.xml). A press no longer moves the icon on:
-- presses during the global cooldown ran it ahead of the totems really dropped. It
-- only restarts the sequence's reset clock; the icon moves when a totem's cast goes
-- through (DropAllOwnCast). The secure click itself is untouched.
function ShamanPower:DropAllPressed(button, mouseButton, down)
	if down then return end   -- the button fires on both the press and the release: once per click
	if self.dropAllTotemSetsActive or not self.dropAllLiveSequence then return end
	self._dropAllPressAt = GetTime()
	self:DropAllActive()
end

-- Your own spell went through. A Drop All totem: the icon reads the sequence again
-- next frame (the game's manager moves on in its own handler for this same event),
-- and the stand-in count moves on when it was that step's totem.
function ShamanPower:DropAllOwnCast(spellID)
	if self.dropAllTotemSetsActive then return end
	local seq = self.dropAllLiveSequence
	if not seq or #seq == 0 then return end
	local element = self:TotemCastElement(spellID)
	if not element then return end
	local i = self.dropAllCurrentElement or 1
	if i < 1 or i > #seq then i = 1 end
	if seq[i].element == element then self.dropAllCurrentElement = (i < #seq) and (i + 1) or 1 end
	-- the first totem, dropped by a press: the next read must find the game's sequence past step 1
	if not self._dropAllQueryProven and #seq >= 2 and seq[1].element == element
		and self._dropAllPressAt and GetTime() - self._dropAllPressAt < 2 then
		self._dropAllQueryCheck = true
	end
	self:DropAllActive()
	C_Timer.After(0, self.DropAllRefresh)
end

-- The sequence was just used (a press, or one of its totems cast): one timer reads it
-- again once its reset time has passed (the game checks that once a second, so 2 more
-- seconds), and again after the latest use while it keeps being used. Never a loop.
function ShamanPower:DropAllActive()
	self._dropAllActiveAt = GetTime()
	if not self._dropAllResetTimer then
		self._dropAllResetTimer = C_Timer.NewTimer(self:DropAllResetSeconds() + 2, self.DropAllResetCheck)
	end
end
function ShamanPower.DropAllResetCheck()
	local self = ShamanPower
	self._dropAllResetTimer = nil
	local wait = self:DropAllResetSeconds() + 2 - (GetTime() - (self._dropAllActiveAt or 0))
	if wait > 0.1 then
		self._dropAllResetTimer = C_Timer.NewTimer(wait, self.DropAllResetCheck)   -- used since: look again then
	else
		self.dropAllCurrentElement = 1   -- the stand-in count starts over with the game's
	end
	self:UpdateDropAllIcon()   -- the game's sequence may have started over already (a press long ago)
end

-- Death starts every /castsequence over (the game's own rule): the icon follows
function ShamanPower:OnDropAllSequenceReset()
	self.dropAllCurrentElement = 1
	C_Timer.After(0, self.DropAllRefresh)
end

-- Tooltip for drop all button
function ShamanPower:DropAllTooltip(button)
	if not self.opt.ShowTooltips then return end
	if self.dropAllTotemSetsActive and self.DropAllTotemSetsTooltip then return self:DropAllTotemSetsTooltip(button) end

	GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
	GameTooltip:AddLine("Drop All Totems", 1, 0.8, 0)

	-- Show current/next totem (the step the game's sequence is really on)
	local step, seq = self:DropAllStep()
	local current = step > 0 and seq[step]
	if current then
		local elementName = self.Elements[current.element] or "Unknown"
		GameTooltip:AddLine("Next: " .. elementName .. " - " .. current.spellName, 0, 1, 0)
	end

	GameTooltip:AddLine(" ", 1, 1, 1)
	GameTooltip:AddLine("Sequence:", 0.7, 0.7, 0.7)

	-- Show all totems in sequence, highlighting current
	for i, totem in ipairs(seq) do
		local elementName = self.Elements[totem.element] or "Unknown"
		if i == step then
			GameTooltip:AddLine("  > " .. elementName .. ": " .. totem.spellName, 0, 1, 0)
		else
			GameTooltip:AddLine("    " .. elementName .. ": " .. totem.spellName, 0.7, 0.7, 0.7)
		end
	end

	GameTooltip:AddLine(" ", 1, 1, 1)
	GameTooltip:AddLine("Starts over after the last totem, when combat ends, or "
		.. self:DropAllResetSeconds() .. " seconds after your last press", 0.5, 0.5, 0.5, true)
	if self.opt.enableMiddleClickPopOut ~= false then
		GameTooltip:AddLine("|cff00ccffMiddle-click:|r Pop out", 1, 1, 1)
	end
	GameTooltip:Show()
end

-- Tooltip for Totemic Call button
function ShamanPower:TotemicCallTooltip(button)
	if not self.opt.ShowTooltips then return end
	GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
	GameTooltip:SetSpellByID(36936)  -- Totemic Call
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("|cff888888Recalls all active totems|r", 1, 1, 1)
	GameTooltip:Show()
end

-- Set up Totemic Call button (from XML: ShamanPowerAutoTotemicCall)
function ShamanPower:SetupTotemicCallButton()
	local btn = _G["ShamanPowerAutoTotemicCall"]
	if not btn then return end

	-- Set up spell casting (Totemic Call)
	local spellName = GetSpellInfo(36936)
	if spellName and not InCombatLockdown() then
		btn:RegisterForClicks("AnyUp", "AnyDown")
		btn:SetAttribute("type1", "spell")
		btn:SetAttribute("spell1", spellName)
	end

	-- Update icon texture
	local iconTexture = btn.icon or _G["ShamanPowerAutoTotemicCallIcon"]
	if iconTexture then
		local _, _, icon = GetSpellInfo(36936)
		if icon then
			iconTexture:SetTexture(icon)
		end
	end
end

-- Update Totemic Call button opacity based on whether totems are active
function ShamanPower:UpdateTotemicCallOpacity()
	local btn = _G["ShamanPowerAutoTotemicCall"]
	if not btn or not btn:IsShown() then return end

	local fullWhenActive = self.opt.cooldownBarFullOpacityWhenActive

	if fullWhenActive then
		-- Check if any totems are placed
		local hasTotem = false
		for slot = 1, 4 do
			local haveTotem = ShamanPower:GetElementTotemInfo(slot)  -- element loop; shadow model in combat
			if haveTotem then
				hasTotem = true
				break
			end
		end
		-- When active, ignore parent alpha so button is fully visible
		if hasTotem then
			btn:SetIgnoreParentAlpha(true)
			btn:SetAlpha(1.0)
		else
			btn:SetIgnoreParentAlpha(false)
			btn:SetAlpha(1.0)  -- Inherit parent opacity
		end
	else
		btn:SetIgnoreParentAlpha(false)
		btn:SetAlpha(1.0)  -- Inherit parent opacity
	end
end

function ShamanPower:PerformCycle(name, class, skipzero)
	local cur
	if not ShamanPower_Assignments[name] then
		ShamanPower_Assignments[name] = {}
	end
	if not ShamanPower_Assignments[name][class] then
		cur = 0
	else
		cur = ShamanPower_Assignments[name][class]
	end
	ShamanPower_Assignments[name][class] = 0
	-- Get the max number of totems for this element
	local maxTotems = self:GetTotemIndexLimit(class)
	-- Advance to the next totem; wrap-around is handled below. Totems this client
	-- does not have (Totem of Wrath, the Elementals, Wrath of Air on WoW: Forever)
	-- are stepped over, so the cycle never lands on something nobody can cast.
	for _ = 1, maxTotems + 1 do
		cur = cur + 1
		if cur > maxTotems then
			-- Wrap around to 0 (no totem) or 1 (first totem)
			if skipzero then
				cur = 1
			else
				cur = 0
			end
		end
		if class < 1 or class > 4 or self:TotemExistsOnClient(class, cur) then break end
	end
	if SPCompat.FOREVER and maxTotems == 0 then cur = 0 end
	ShamanPower_Assignments[name][class] = cur
	if name == self.player and class >= 1 and class <= 4 then
		-- Also update the mini totem bar
		self:UpdateMiniTotemBar()
		self:UpdateDropAllButton()
		-- Update macros when assignment changes
		self:UpdateSPMacros()
	end
	local msgQueue
	msgQueue =
		C_Timer.NewTimer(
		2.0,
		function()
			self:SendMessage("ASSIGN " .. name .. " " .. class .. " " .. ShamanPower_Assignments[name][class])
			self:UpdateLayout()
			msgQueue:Cancel()
		end
	)
end

function ShamanPower:PerformCycleBackwards(name, class, skipzero)
	local cur
	if name and not ShamanPower_Assignments[name] then
		ShamanPower_Assignments[name] = {}
	end
	-- Get max totems for this element
	local maxTotems = self:GetTotemIndexLimit(class)
	local sparse = SPCompat.FOREVER and class >= 1 and class <= 4
	if sparse then
		cur = ShamanPower_Assignments[name][class] or 0
		-- The loop decrements first; begin above the last valid index when
		-- wrapping, including a saved index pruned from the end of the table.
		if cur <= 0 or cur > maxTotems then cur = maxTotems + 1 end
	else
		-- The loop decrements first, so wrapping (from no totem, or from the first
		-- one when skipzero leaves out "none") begins above the last totem. Starting
		-- AT the last one stepped straight past it to the one before.
		cur = ShamanPower_Assignments[name][class] or 0
		if cur <= 0 or cur > maxTotems or (skipzero and cur == 1) then cur = maxTotems + 1 end
	end
	ShamanPower_Assignments[name][class] = 0
	-- Simple backwards cycle - go to previous totem (stepping over totems this
	-- client does not have, as the forward cycle does)
	for _ = 1, maxTotems + 1 do
		cur = cur - 1
		if cur < 0 then
			-- Wrap around to max totem or 0
			if skipzero then
				cur = maxTotems
			else
				cur = maxTotems
			end
		end
		if not (skipzero and cur == 0)   -- skipzero never lands on "none", on any client
			and (class < 1 or class > 4 or self:TotemExistsOnClient(class, cur)) then break end
	end
	if sparse and maxTotems == 0 then cur = 0 end
	ShamanPower_Assignments[name][class] = cur
	if name == self.player and class >= 1 and class <= 4 then
		-- Also update the mini totem bar
		self:UpdateMiniTotemBar()
		self:UpdateDropAllButton()
		-- Update macros when assignment changes
		self:UpdateSPMacros()
	end
	local msgQueue
	msgQueue =
		C_Timer.NewTimer(
		2.0,
		function()
			self:SendMessage("ASSIGN " .. name .. " " .. class .. " " .. ShamanPower_Assignments[name][class])
			self:UpdateLayout()
			msgQueue:Cancel()
		end
	)
end

-- The assignment window's right-click with Right-Click an Assignment = Clear Assignment
-- (Totem Bar > Clicks): that element is left with no totem, through the cycle's own
-- update path (your bar and macros now, the group's copy 2 s later). Callers check
-- combat and permission first, as for a cycle. An element already empty is left alone.
function ShamanPower:PerformClearAssignment(name, class)
	if not name or not class then return end
	local current = ShamanPower_Assignments[name] and ShamanPower_Assignments[name][class]
	if not current or current == 0 then return end
	ShamanPower_Assignments[name][class] = 0
	if name == self.player and class >= 1 and class <= 4 then
		self:UpdateMiniTotemBar()
		self:UpdateDropAllButton()
		self:UpdateSPMacros()
	end
	local msgQueue
	msgQueue = C_Timer.NewTimer(2.0, function()
		self:SendMessage("ASSIGN " .. name .. " " .. class .. " " .. ShamanPower_Assignments[name][class])
		self:UpdateLayout()
		msgQueue:Cancel()
	end)
end

function ShamanPower:ScanTalents()
	-- classic talent API only; modern clients use trait trees (no equivalent yet)
	if not GetNumTalentTabs or not GetNumTalents or not GetTalentInfo then return end
	local numTabs = GetNumTalentTabs()
	for t = 1, numTabs do
		for i = 1, GetNumTalents(t) do
			local _, textureID = GetTalentInfo(t, i)
			ShamanPower_Talents[textureID] = {t, i}
		end
	end
end

-- Safe default totems for each element (used when talent-required totems become unavailable)
-- These are totems that all shamans can use regardless of spec
ShamanPower.DefaultTotems = {
	[1] = 1,  -- Earth: Strength of Earth (index 1)
	[2] = 2,  -- Fire: Searing Totem (index 2) - index 1 is Totem of Wrath (Elemental talent)
	[3] = 1,  -- Water: Mana Spring (index 1) - index 3 is Mana Tide (Resto talent)
	[4] = 1,  -- Air: Windfury (index 1)
}

-- Validate totem assignments after respec - reset talent-gated totems if player no longer has them
function ShamanPower:ValidateAssignmentsForSpec()
	if not self.player then return end

	local assignments = ShamanPower_Assignments[self.player]
	if not assignments then return end

	local changed = false

	-- Check each element's assigned totem
	for element = 1, SHAMANPOWER_MAXELEMENTS do
		local totemIndex = assignments[element]
		if totemIndex and totemIndex > 0 then
			-- Get the spell ID for this totem
			local spellID = self.Totems[element] and self.Totems[element][totemIndex]
			if spellID then
				-- Check if this is a talent-required totem
				local talentInfo = self.TalentTotems[spellID]
				if talentInfo then
					-- This totem requires a talent - check if player knows it
					if not PlayerKnowsTotem(spellID) then
						-- Player doesn't have this spell anymore - reset to default
						local defaultTotem = self.DefaultTotems[element] or 1
						assignments[element] = defaultTotem
						changed = true

						local elementName = self.Elements[element] or "Unknown"
						local oldTotemName = self:GetTotemName(element, totemIndex)
						local newTotemName = self:GetTotemName(element, defaultTotem)
						if not self:IsOff() then self:Print("|cffff9900Respec detected:|r " .. elementName .. " totem reset from " .. oldTotemName .. " to " .. newTotemName) end
					end
				end
			end
		end
	end

	return changed
end

-- Called when talents change (respec, dual spec switch, etc.)
function ShamanPower:OnTalentsChanged()
	if not isShaman then return end
	if InCombatLockdown() then
		-- Queue for after combat
		self.talentChangePending = true
		return
	end

	-- Talent events can precede SPELLS_CHANGED; do not validate a respec using
	-- cached knowledge from the old talent selection.
	SPCompat.InvalidateSpellData()
	-- Rescan talents and spells
	self:ScanTalents()
	self:ScanSpells()

	-- Validate assignments - reset any talent-gated totems the player no longer has
	local assignmentsChanged = self:ValidateAssignmentsForSpec()

	-- Recreate cooldown bar to pick up new talent-based abilities (NS, Mana Tide, etc.)
	self:RecreateCooldownBar()

	-- Re-filter the totem flyouts so talent-gated totems (Totem of Wrath,
	-- Mana Tide) appear or disappear with the spec - no /reload needed. The
	-- buttons always exist; this only flips the same filter the settings use.
	self:RecreateTotemFlyouts()

	-- Update keybindings for the new buttons
	self:SetupKeybindings()

	-- If assignments changed, update UI and macros
	if assignmentsChanged then
		self:UpdateLayout()
		self:UpdateSPMacros()
	end
end

function ShamanPower:ScanSpells()
	--self:Debug("[ScanSpells]")
	if SPCompat.FOREVER then
		self._imbueSpellGeneration = (self._imbueSpellGeneration or 0) + 1
	end
	self:InvalidateElementLearned()
	if isShaman then
		self:SyncAdd(self.player)
		ShamanPower.AllShamans[self.player] = {}

		-- Keep every display row, but advertise only totems known by spell ID.
		-- Higher ranks count without reporting unlearned spells to the group.
		for element = 1, SHAMANPOWER_MAXELEMENTS do
			ShamanPower.AllShamans[self.player][element] = {}
			local totemNames = self.TotemNames[element]
			if totemNames then
				for totemIndex, totemName in pairs(totemNames) do
					ShamanPower.AllShamans[self.player][element][totemIndex] = {
						known = PlayerKnowsTotem(self:GetTotemSpell(element, totemIndex)),
						name = totemName
					}
				end
			end
		end

		-- Weapon imbues have their own spell families, separate from totems.
		ShamanPower.AllShamans[self.player].WeaponEnchants = {}
		local enchantNames = {"Windfury Weapon", "Flametongue Weapon", "Frostbrand Weapon", "Rockbiter Weapon"}
		for enchantIndex, enchantName in ipairs(enchantNames) do
			ShamanPower.AllShamans[self.player].WeaponEnchants[enchantIndex] = {
				known = PlayerKnowsSpellByID(self.WeaponImbueSpells[enchantIndex]),
				name = enchantName
			}
		end

		-- Check if player has Earth Shield (Restoration talent)
		ShamanPower.AllShamans[self.player].hasEarthShield = self:HasEarthShield()

		isShaman = true
		if not ShamanPower.AllShamans[self.player].subgroup then
			ShamanPower.AllShamans[self.player].subgroup = 1
		end
	end
	initialized = true
end

-- A request for shaman data (REQ) used to be answered with a whisper to each
-- requester. When a shaman left a raid, every client asked at once and every
-- shaman sent ~35 whispers: over Blizzard's per-prefix limit (10 in a burst,
-- then 1 a second), which stalled that shaman's messages - raid calls included
-- - for half a minute. Now: ONE broadcast to the group, 0.5-2 s later (jittered
-- so the shamans do not all answer on the same frame), however many requests
-- arrive in between. Older clients that still whisper, or still ask, are fine:
-- they read SELF from the group channel either way.
local selfBroadcastQueued = false
function ShamanPower:QueueSelfBroadcast()
	if not isShaman or selfBroadcastQueued or self:IsOff() then return end   -- switched off: no reply
	selfBroadcastQueued = true
	C_Timer.After(0.5 + math.random() * 1.5, function()
		selfBroadcastQueued = false
		ShamanPower:SendSelf(nil, true)   -- force: a reply must not be swallowed as a repeat
	end)
end

-- Ask the group's shamans for their data, at most once every 5 s: a burst of
-- roster changes (a raid forming, someone leaving) asks once. An ask inside the
-- 5 s is not dropped but sent once at the end of it: the caller may have just
-- wiped the shaman list and needs the answers.
local REQUEST_GAP = 5
local lastShamanDataRequest, requestQueued = -10, false
local function sendShamanDataRequest()
	requestQueued = false
	lastShamanDataRequest = GetTime()
	ShamanPower:SendMessage("REQ")
end
function ShamanPower:RequestShamanData()
	if requestQueued then return end   -- one is already on its way
	local wait = REQUEST_GAP - (GetTime() - lastShamanDataRequest)
	if wait <= 0 then
		sendShamanDataRequest()
	else
		requestQueued = true
		C_Timer.After(wait, sendShamanDataRequest)
	end
end

function ShamanPower:SendSelf(sender, force)
	if not initialized or GetNumGroupMembers() == 0 then
		return
	end
	if not isShaman then
		return
	end

	-- Simplified sync for totems - send available totems by element
	local s = ""
	local TotemInfo = ShamanPower.AllShamans[self.player]
	if TotemInfo then
		-- Send which totems are available for each element
		for element = 1, SHAMANPOWER_MAXELEMENTS do
			local elementTotems = TotemInfo[element] or {}
			local available = ""
			for totemIndex = 1, SHAMANPOWER_MAXPERELEMENT do
				if elementTotems[totemIndex] and elementTotems[totemIndex].known then
					available = available .. totemIndex
				end
			end
			s = s .. (available ~= "" and available or "n") .. "|"
		end
	end
	s = s .. "@"

	-- Send current assignments
	if not ShamanPower_Assignments[self.player] then
		ShamanPower_Assignments[self.player] = {}
		for i = 1, SHAMANPOWER_MAXELEMENTS do
			ShamanPower_Assignments[self.player][i] = 0
		end
	end
	local BuffInfo = ShamanPower_Assignments[self.player]
	for i = 1, SHAMANPOWER_MAXELEMENTS do
		if not BuffInfo[i] or BuffInfo[i] == 0 then
			s = s .. "n"
		else
			s = s .. BuffInfo[i]
		end
	end

	-- Add Earth Shield info: #<hasES>:<target>
	local hasES = self:HasEarthShield() and "1" or "0"
	local esTarget = ShamanPower_EarthShieldAssignments[self.player] or ""
	s = s .. "#" .. hasES .. ":" .. esTarget

	-- Add freeassign flag: $<freeassign>
	local freeassign = (self.opt and self.opt.freeassign) and "1" or "0"
	s = s .. "$" .. freeassign

	local leader = self:CheckLeader(sender)
	if sender and not leader then
		self:SendMessage("SELF " .. s, "WHISPER", sender)
	else
		self:SendMessage("SELF " .. s, nil, nil, force)
	end

	-- Set freeassign option locally
	if ShamanPower.AllShamans[self.player] then
		ShamanPower.AllShamans[self.player].freeassign = self.opt and self.opt.freeassign or false
	end

end

-- Duplicate suppression exists to swallow rapid repeats from the assignment
-- timers. Keyed on the exact text with no time limit, it silently ate every
-- repeat of a one-shot command (a non-shaman caller pressing the same call
-- button twice sends identical text and nothing else in between). Repeats
-- are now only dropped within a short window, and one-shot commands pass
-- `force` to bypass it entirely.
local DEDUP_WINDOW = 2
-- WoW: Forever's chat lockdown (instance fights) refuses every addon message. An
-- assignment made meanwhile (a totem, twisting, an Earth Shield target, a clear)
-- is held, in order, and sent when the lockdown lifts; so is a fresh SELF, which
-- carries our own assignments and Earth Shield target. Status and requests are
-- not held: they are sent again fresh anyway. Nothing is held on a client
-- without the lockdown.
local HOLD_IN_LOCKDOWN = { ASSIGN = true, PASSIGN = true, MASSIGN = true, TWIST = true, ESASSIGN = true, CLEAR = true, FREEASSIGN = true }
local MAX_HELD = 20
local heldMessages, sendRefused = nil, false
-- What a held message sets (a player's element, twisting, Earth Shield target...):
-- a newer message for the same thing replaces the held one, so the lockdown
-- lifting sends each setting once, not every step taken meanwhile.
local function heldKey(self, msg)
	local k = strmatch(msg, "^(ASSIGN .+ %d+) %d+$") or strmatch(msg, "^(TWIST .+) [01]$")
		or strmatch(msg, "^(PASSIGN .+)@") or strmatch(msg, "^(MASSIGN .+) %d+$")
	if k then return k end
	if strmatch(msg, "^ESASSIGN") then return "ESASSIGN " .. tostring((self:DecodeESAssign(msg, self.player))) end
	return strmatch(msg, "^(%u+)")   -- CLEAR, FREEASSIGN
end
local function holdMessage(self, msg, type, target)
	local key = heldKey(self, msg)
	heldMessages = heldMessages or {}
	for i = #heldMessages, 1, -1 do
		local m = heldMessages[i]
		if m.key == key and m[3] == target then tremove(heldMessages, i) end
	end
	if #heldMessages >= MAX_HELD then tremove(heldMessages, 1) end
	heldMessages[#heldMessages + 1] = { msg, type, target, key = key,
		instance = IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and true or false }
end
-- Blizzard lets each addon prefix send about 10 messages at once and then 1 a
-- second, and refuses the rest; ChatThrottleLib only paces by bytes. So every
-- message SendMessage lets through leaves by one queue: up to 10 straight away,
-- then one a second, in the order they were made. A newer message for the same
-- thing (a held key above, or a whole-state SELF / *SYNC) replaces one still
-- waiting. The queue belongs to the group it was made in (DropHeldMessages) and
-- waits out a chat lockdown rather than losing what it holds (SendHeldMessages
-- starts it again). Nothing runs while it is empty. Anything else sent on this
-- prefix has to come through SendMessage too, or the count here falls short of
-- the client's.
local outbound = {}
do
	local BURST = 10                   -- at once; then one more for each second since
	local SNAPSHOT = { SELF = true, RCSYNC = true, MTSYNC = true, DRUMSYNC = true }   -- each carries the whole state
	local allowance, allowanceAt = BURST, 0
	local queue, timerSet = nil, false

	-- the channel is worked out as it leaves: the group may have changed while it waited
	local function transmit(self, msg, type, target)
		if not type then
			if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and IsInInstance() then
				type = "INSTANCE_CHAT"
			else
				if IsInRaid() then
					type = "RAID"
				else
					type = "PARTY"
				end
			end
		end
		if target then
			ChatThrottleLib:SendAddonMessage("NORMAL", self.commPrefix, msg, "WHISPER", target)
			--self:Debug("[Sent Message] prefix: " .. self.commPrefix .. " | msg: " .. msg .. " | type: WHISPER | target name: " .. target)
		else
			ChatThrottleLib:SendAddonMessage("NORMAL", self.commPrefix, msg, type)
			--self:Debug("[Sent Message] prefix: " .. self.commPrefix .. " | msg: " .. msg .. " | type: " .. type)
		end
	end
	local function regain()
		local now = GetTime()
		allowance = math.min(BURST, allowance + (now - allowanceAt))
		allowanceAt = now
	end
	local drain
	local function schedule()
		if timerSet then return end
		timerSet = true
		C_Timer.After(1 - allowance + 0.01, drain)   -- when the next one is allowed
	end
	drain = function()
		timerSet = false
		if not queue then return end
		if SPK and SPK() == true then return end   -- chat lockdown: SendHeldMessages starts it again
		if GetNumGroupMembers() == 0 then queue = nil return end
		regain()
		local instance = IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and true or false
		while queue[1] and allowance >= 1 do
			local m = tremove(queue, 1)
			-- made in the other kind of group: dropped, as a held one is
			if m.instance == instance then
				allowance = allowance - 1
				transmit(ShamanPower, m[1], m[2], m[3])
			end
		end
		if queue[1] then schedule() else queue = nil end
	end

	function outbound.send(self, msg, type, target)
		if not queue then
			regain()
			if allowance >= 1 then
				allowance = allowance - 1
				transmit(self, msg, type, target)
				return
			end
			queue = {}
		end
		local kind = strmatch(msg, "^(%u+)") or ""
		local key = (HOLD_IN_LOCKDOWN[kind] and heldKey(self, msg)) or (SNAPSHOT[kind] and kind) or nil
		if key then
			for i = #queue, 1, -1 do
				local m = queue[i]
				if m.key == key and m[3] == target then tremove(queue, i) end
			end
		end
		queue[#queue + 1] = { msg, type, target, key = key,
			instance = IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and true or false }
		schedule()
	end
	function outbound.resume()
		if queue and not timerSet then drain() end
	end
	function outbound.drop()
		queue = nil
	end
end

-- A held message belongs to the group it was made in. The channel is worked out
-- again when it is sent, so leaving that group or joining another (a battleground,
-- a Dungeon Finder group) drops it (GROUP_LEFT / GROUP_JOINED), and one made in the
-- other kind of group is not sent: a held CLEAR must never wipe another group's calls.
-- The messages still waiting to leave go with it.
function ShamanPower:DropHeldMessages()
	heldMessages = nil
	outbound.drop()
end
function ShamanPower:SendHeldMessages()
	outbound.resume()   -- what waited through the lockdown leaves first
	local held = heldMessages
	heldMessages = nil
	if held then
		local instance = IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and true or false
		for i = 1, #held do
			local m = held[i]
			if m.instance == instance then self:SendMessage(m[1], m[2], m[3], true) end
		end
	end
	if sendRefused then
		sendRefused = false
		self:QueueSelfBroadcast()
	end
end

function ShamanPower:SendMessage(msg, type, target, force)
	if self:IsOff() then return false end   -- switched off: tells the group nothing
	if SPK and SPK() == true then
		-- Do not claim delivery while the client's chat messaging lock is active.
		if GetNumGroupMembers() > 0 then
			sendRefused = true
			if HOLD_IN_LOCKDOWN[strmatch(msg, "^(%u+)") or ""] then holdMessage(self, msg, type, target) end
		end
		return false
	end
	if GetNumGroupMembers() > 0 then
		-- Dedup key includes target so broadcast vs whisper of the same msg are distinct
		local dedupKey = target and (msg .. "\001" .. target) or msg
		local now = GetTime()
		if force or lastMsg ~= dedupKey or (now - lastMsgTime) > DEDUP_WINDOW then
			lastMsg = dedupKey
			lastMsgTime = now
			outbound.send(self, msg, type, target)
		end
	end
end

-- A learned rank may change the cast spelling. Existing popouts and saved
-- macros must follow it; the normal flyout rebuild handles its secure actions.
function ShamanPower:RefreshAliasedTotemCasts()
	if self:IsOff() or InCombatLockdown() or not SPCompat.HasTotemCastAliases(5675) then return end
	local name = SPCompat.TotemCastName(5675)
	if not name or name == self._lastTotemCastAlias then return end
	self._lastTotemCastAlias = name
	if self.poppedOutFrames then
		for key, frame in pairs(self.poppedOutFrames) do
			if frame.button and frame.totemIndex and SPCompat.HasTotemCastAliases(frame.spellID) then
				frame.spellName = SPCompat.TotemCastName(frame.spellID)
				frame.button:SetAttribute("spell1", frame.spellName)
				local progress = self.poppedOutProgressBars and self.poppedOutProgressBars[key]
				if progress then progress.spellName = frame.spellName end
				local overlay = self.poppedOutOverlays and self.poppedOutOverlays[key]
				if overlay then overlay.spellName = frame.spellName end
				if frame.titleText then frame.titleText:SetText(self:GetTotemName(frame.element, frame.totemIndex)) end
			end
		end
	end
	self:UpdateSPMacros()
	self:UpdateDropAllButton()
end

function ShamanPower:SPELLS_CHANGED()
	--self:Debug("EVENT: SPELLS_CHANGED")
	if not initialized then
		ShamanPower:ScanSpells()
		return
	end
	ShamanPower:ScanSpells()
	ShamanPower:SendSelf()
	if not InCombatLockdown() then
		ShamanPower:RecreateTotemFlyouts()
		ShamanPower:EnsureElementAssignments()   -- an element's first totem gets assigned by itself
		ShamanPower:RefreshAliasedTotemCasts()
	end
	-- a newly learned imbue or shield: rebuild the cooldown bar so its flyouts offer it.
	-- Spells are learned out of combat; a fight's SPELLS_CHANGED (forms, procs) is
	-- skipped, the next one out of combat catches a learn.
	if ShamanPower.cooldownBar and ShamanPower._cdBarSpellKey and not InCombatLockdown()
		and ShamanPower:CooldownBarSpellKey() ~= ShamanPower._cdBarSpellKey then
		ShamanPower:RecreateCooldownBar()
	end
	ShamanPower:UpdateLayout()
end

function ShamanPower:PLAYER_ENTERING_WORLD()
	--self:Debug("EVENT: PLAYER_ENTERING_WORLD")
	ShamanPower.realm = GetNormalizedRealmName() --GetRealmName()

	-- Validate assignments in case player respecced while logged out
	local assignmentsChanged = self:ValidateAssignmentsForSpec()
	if assignmentsChanged then
		self:UpdateSPMacros()
	end

	self:UpdateLayout()
	self:UpdateRoster()

	-- Pick up an Earth Shield that was already out before this login/reload
	C_Timer.After(1.0, function() self:DiscoverEarthShieldTarget() end)

	-- Apply flyout click mode setting after layout is set up
	C_Timer.After(0.5, function()
		self:UpdateTotemFlyoutEnabled()
	end)

	-- Initialize raid cooldowns and show caller buttons if assigned
	C_Timer.After(1.0, function()
		self:InitRaidCooldowns()
		self:UpdateCallerButtons()
		self:RestoreCallerCooldowns()
	end)

	-- Initialize SPRange (totem range tracker for all classes)
	C_Timer.After(1.5, function()
		self:InitializeSPRange()
	end)

	-- Initialize Earth Shield Tracker (for tracking all ES in raid/party)
	C_Timer.After(2, function()
		self:InitializeESTracker()
	end)

	-- Restore popped-out trackers after bars are fully initialized
	C_Timer.After(2.5, function()
		self:RestorePoppedOutTrackers()
	end)

	-- Initialize Shield Charge Display (large on-screen numbers)
	C_Timer.After(3, function()
		self:CreateShieldChargeDisplays()
	end)

	-- Initialize Totem Plates (replace totem nameplates with icons)
	C_Timer.After(3.5, function()
		self:InitializeTotemPlates()
	end)

	-- Set up totem bar visibility updater (hide out of combat / hide when no totems)
	C_Timer.After(1, function()
		self:SetupTotemBarVisibilityUpdater()
	end)
end

function ShamanPower:ZONE_CHANGED()
	if IsInRaid() then
		self.zone = GetRealZoneText()
		self:UpdateLayout()
		self:UpdateRoster()
	end
end

function ShamanPower:ZONE_CHANGED_NEW_AREA()
	if IsInRaid() then
		self.zone = GetRealZoneText()
		self:UpdateLayout()
		self:UpdateRoster()
	end
end

-- Every addon's messages arrive here (DBM, BigWigs, WeakAuras...): the prefix is
-- checked first, so other addons' traffic costs one comparison and nothing else.
local COMM_DISTRIBUTIONS = { PARTY = true, RAID = true, INSTANCE_CHAT = true, WHISPER = true }
function ShamanPower:CHAT_MSG_ADDON(event, prefix, message, distribution, source)
	if prefix == self.commPrefix then
		if not COMM_DISTRIBUTIONS[distribution] then return end
		local sender = Ambiguate(source, "none")
		if sender then self:ParseMessage(sender, message) end
	elseif prefix == "WFTracker" then
		-- the popular Windfury WeakAura ("PlayerName:Status:TimeRemaining")
		local sender = Ambiguate(source, "none")
		local _, status = message:match("^([^:]+):([01]):")
		if status and sender then self:SetWindfuryReport(sender, status == "1") end
	end
end

-- One record per reporter, reused: a raid's worth of reports every few seconds
-- must not build a new table each time.
function ShamanPower:SetWindfuryReport(sender, has)
	-- keyed by the plain name: the dots look reporters up by UnitName (no realm),
	-- and a report only ever comes from your own party, where names do not clash
	sender = strsplit("-", sender)
	local all = self.WindfuryRangeData
	if not all then all = {}; self.WindfuryRangeData = all end
	local rec = all[sender]
	if not rec then rec = {}; all[sender] = rec end
	rec.hasWindfury, rec.timestamp = has, GetTime()
end

function ShamanPower:GROUP_JOINED(event)
	--self:Debug("[Event] GROUP_JOINED")
	self:DropHeldMessages()   -- held for the group we were in, not this one
	ShamanPower.AllShamans = {}
	ShamanPower.SyncList = {}
	self:ScanSpells()
	C_Timer.After(
		2.0,
		function()
			self:SendSelf()
			self:RequestShamanData()
			self:UpdateLayout()
			self:UpdateRoster()
		end
	)
	self.zone = GetRealZoneText()
end

function ShamanPower:GROUP_LEFT(event)
	--self:Debug("[Event] GROUP_LEFT")
	self:DropHeldMessages()   -- held for the group just left
	ShamanPower.AllShamans = {}
	ShamanPower.SyncList = {}
	for pname in pairs(ShamanPower_Assignments) do
		local match = false
		if pname == self.player then
			match = true
		end
		for i = 1, GetNumGuildMembers() do
			local name = Ambiguate(GetGuildRosterInfo(i), "short")
			if pname == name then
				match = true
				break
			end
		end
		if match == false then
			ShamanPower_Assignments[pname] = nil
		end
	end

	-- Clear Earth Shield assignments when leaving group
	ShamanPower_EarthShieldAssignments = {}
	self.currentEarthShieldTarget = nil

	-- Clear Raid Cooldown assignments when leaving group
	ShamanPower_RaidCooldowns = {
		bloodlust = {
			primary = nil,
			backup1 = nil,
			backup2 = nil,
			caller = nil,
		},
		manatide = {},
	}

	self:ScanSpells()
	self:UpdateLayout()
	self:UpdateRoster()
	self:UpdateEarthShieldButton()
	self:UpdateCallerButtons()
end

function ShamanPower:UpdateAllShamans()
	if not initialized then
		return
	end

	local units
	if IsInRaid() then
		units = raid_units
	else
		units = party_units
	end

	local countAllShamans = 0
	for _ in pairs(ShamanPower.AllShamans) do countAllShamans = countAllShamans + 1 end

	local found = 0
	for _, unitid in pairs(units) do
		if unitid and (not unitid:find("pet")) and UnitExists(unitid) then
			local n = GetUnitName(unitid, true)
			if n and ShamanPower.AllShamans[ShamanPower:RemoveRealmName(n)] then found = found + 1 end
		end
	end

	if found < countAllShamans then -- Zid: if ShamanPower.AllShamans count is reduced do a fresh setup
		C_Timer.After(
			0.5,
			function()
				ShamanPower.AllShamans = {}
				ShamanPower.SyncList = {}
				self:ScanSpells()
				self:SendSelf()
				self:RequestShamanData()
				self:UpdateLayout()
				self:UpdateRoster()
			end
		)
	end
end

function ShamanPower:PLAYER_TOTEM_UPDATE(event, slot)
	self:InvalidateTotemInfo()   -- the loops read the new state on their next tick
	self:ShadowTotemSlotUpdate(slot)
	self:RecordTotemDropFromSlot(slot)
	self:RefreshTotemDestroySlots()   -- cast-order clients: keep right-click destroy on the right slot
	if self.CueTotemUpdate then self:CueTotemUpdate() end   -- the bar's Effects (ShamanPowerCues.lua)
	if self.UsualTotemUpdate then self:UsualTotemUpdate() end   -- Put Your Usual Totem Back (readable slots)
end

function ShamanPower:UNIT_SPELLCAST_SUCCEEDED(event, unitTarget, castGUID, spellID)
	if issecretvalue(unitTarget) or issecretvalue(spellID) then return end
	-- Under the secrets regime the totem model is fed by the player's own casts, not
	-- by the API, so a cast is a "totems may have changed" moment too.
	if unitTarget == "player" then self:InvalidateTotemInfo() end
	-- Own totem casts feed the shadow totem model (never secret, even in combat)
	self:ShadowTotemCast(unitTarget, spellID)
	-- Own casts also stamp the shadow cooldown model (see SPCompat.GetSpellCooldown)
	if unitTarget == "player" and SPCompat and SPCompat.ShadowCooldownCast then
		SPCompat.ShadowCooldownCast(spellID)
	end
	if unitTarget == "player" then
		self:ShadowBuffCast(spellID)
		self:ShadowShieldCast(unitTarget, spellID)
		self:DropAllOwnCast(spellID)   -- Drop All's next-totem icon follows the casts, not the presses
	end

	-- Track Earth Shield casts (event-based tracking, no scanning!)
	self:OnEarthShieldCastSucceeded(unitTarget, castGUID, spellID)

	-- Trigger GCD swipe when player casts a totem (switched off: the bar is down)
	if unitTarget == "player" and not self:IsOff() then
		if self:TotemCastElement(spellID) or spellID == 36936 or spellID == 437009 or spellID == 425874 then
			self:TriggerGCDSwipe()
			-- Dynamic Mode (and Grid): immediately update assignment when totem is cast
			if self:DropSetsAssignment() then
				-- Small delay to let GetTotemInfo update
				C_Timer.After(0.01, function()
					self:UpdateDynamicTotemIcons()
				end)
			end
		end
	end
	-- Put Your Usual Totem Back (ShamanPowerUsualTotem.lua): your own temporary totem arms it.
	-- Last, so nothing above waits on it (Dynamic Mode's new assignment comes a moment later)
	if unitTarget == "player" and self.UsualTotemCast then self:UsualTotemCast(spellID) end
end

function ShamanPower:PLAYER_ROLES_ASSIGNED(event)
	--self:Debug("[Event] PLAYER_ROLES_ASSIGNED")
	C_Timer.After(
		2.0,
		function()
			for name in pairs(leaders) do
				AC_Leader = false
				if name == self.player then
					self:SendSelf()
				end
			end
		end
	)
end

-- Earth Shield cast tracking (tracks who you cast ES on)
function ShamanPower:UNIT_SPELLCAST_SENT(event, unit, target, castGUID, spellID)
	if unit == "player" then
		self:OnEarthShieldCastSent(target, castGUID, spellID)
	end
end

-- Earth Shield aura tracking (updates charges when aura changes on tracked target)
-- Aura generation per unit: bumped on every UNIT_AURA, so a caller can keep an
-- answer about a unit's buffs until that unit's auras actually change. On the
-- Mainline family every aura read builds a table; polling party buffs twice a
-- second was the range pass's whole idle garbage.
ShamanPower.auraGen = {}
-- A roster change can put a different player in the same unit slot without an
-- aura event on that slot: invalidate every group slot's cached answer.
-- A raid forming fires dozens of GROUP_ROSTER_UPDATEs: this bookkeeping runs
-- 0.3 s after the first one, and once more 0.3 s after the first of any that
-- arrive later, so a long burst costs one pass every 0.3 s at most (the Earth
-- Shield carrier's unit token is re-found here too, since raid indexes shift).
do
	local slots = { "party1", "party2", "party3", "party4" }
	for i = 1, 40 do slots[#slots + 1] = "raid" .. i end
	local queued = false
	local function settle()
		queued = false
		local gen = ShamanPower.auraGen
		for _, u in ipairs(slots) do gen[u] = (gen[u] or 0) + 1 end
		if ShamanPower.UpdateAuraCarrierFilter then ShamanPower:UpdateAuraCarrierFilter() end
	end
	local f = CreateFrame("Frame")
	if SPCompat and SPCompat.StressRegister then SPCompat.StressRegister(f, "core (roster settle)") end
	f:RegisterEvent("GROUP_ROSTER_UPDATE")
	f:SetScript("OnEvent", function()
		if queued then return end
		queued = true
		C_Timer.After(0.3, settle)
	end)
end
function ShamanPower:AuraCacheValid(unit, gen, at)
	-- same aura generation; party slots also expire after 5 s (a slot can change
	-- hands without an aura event). The player is always the player: no expiry.
	if gen == nil or gen ~= (self.auraGen[unit] or 0) or not at then return false end
	return unit == "player" or (GetTime() - at) < 5
end

-- ---------------------------------------------------------------------------
-- Unit events only for the units that matter. Registered with RegisterEvent they
-- arrive for every unit in a 40-player raid (and every nameplate), hundreds a
-- second, just to be ignored. Every consumer here wants the player's own casts,
-- and auras on the player, the party (party1-4 are your subgroup inside a raid)
-- and whoever carries your Earth Shield. RegisterUnitEvent takes up to two
-- units per frame on every client, so the units are spread over small frames.
-- The handlers are looked up at call time, so hooks on them keep working.
-- ---------------------------------------------------------------------------
local unitEventFrames
local function unitEventDispatch(_, event, ...)
	local fn = ShamanPower[event]
	if fn then fn(ShamanPower, event, ...) end
end
function ShamanPower:SetupUnitEventFilters()
	if unitEventFrames then return end
	unitEventFrames = {}
	local stress = SPCompat and SPCompat.StressRegister
	local cast = CreateFrame("Frame")
	if stress then stress(cast, "core (casts)") end
	-- a client without unit filters gets the old unfiltered events (handlers check the unit)
	local function reg(frame, event, a, b)
		if frame.RegisterUnitEvent then
			if b then frame:RegisterUnitEvent(event, a, b) else frame:RegisterUnitEvent(event, a) end
		else
			frame:RegisterEvent(event)
		end
	end
	reg(cast, "UNIT_SPELLCAST_SUCCEEDED", "player")
	reg(cast, "UNIT_SPELLCAST_SENT", "player")   -- Earth Shield cast tracking
	cast:SetScript("OnEvent", unitEventDispatch)
	unitEventFrames.cast = cast
	for _, pair in ipairs({ { "player", "party1" }, { "party2", "party3" }, { "party4" } }) do
		local f = CreateFrame("Frame")
		if stress then stress(f, "core (auras)") end
		reg(f, "UNIT_AURA", pair[1], pair[2])
		f:SetScript("OnEvent", unitEventDispatch)
		unitEventFrames[#unitEventFrames + 1] = f
	end
	-- the Earth Shield carrier outside your party (a raid tank): its own frame,
	-- re-pointed whenever the carrier or the raid's order changes
	local carrier = CreateFrame("Frame")   -- roster changes re-point it (see the auraGen block above)
	if stress then stress(carrier, "core (Earth Shield carrier)") end
	carrier:SetScript("OnEvent", unitEventDispatch)
	unitEventFrames.carrier = carrier
	self:UpdateAuraCarrierFilter()
end

local RAID_TOKENS = {}
for i = 1, 40 do RAID_TOKENS[i] = "raid" .. i end
local PARTY_TOKENS = { "party1", "party2", "party3", "party4" }
local function unitHasGUID(unit, guid)
	local ok, g = pcall(UnitGUID, unit)
	return ok and g and not (issecretvalue and issecretvalue(g)) and g == guid
end
function ShamanPower:UpdateAuraCarrierFilter()
	local f = unitEventFrames and unitEventFrames.carrier
	if not f then return end
	f:UnregisterEvent("UNIT_AURA")
	local guid = self.esTrackedTargetGUID
	if not guid or self.ESTrackerUnavailable then return end
	if not f.RegisterUnitEvent then return end   -- without filters the unfiltered frames already hear everyone
	if unitHasGUID("player", guid) then return end   -- the player frame covers it
	if IsInRaid() then
		for i = 1, 40 do
			local unit = RAID_TOKENS[i]
			if unitHasGUID(unit, guid) then
				-- (if the carrier is also in your party its aura event may arrive twice;
				-- the Earth Shield charge update is idempotent)
				f:RegisterUnitEvent("UNIT_AURA", unit)
				return
			end
		end
	else
		for i = 1, 4 do
			if unitHasGUID(PARTY_TOKENS[i], guid) then return end   -- the party frames cover it
		end
	end
	-- outside your group: heard while you target or focus them, as the tracker
	-- (FindEarthShieldTarget) finds them; other units' aura events are ignored by GUID
	f:RegisterUnitEvent("UNIT_AURA", "target", "focus")
end

-- TBC Anniversary: every buff read builds a ~1.9 KB record (measured 2026-09-30:
-- 189 KB per 100 UnitBuff calls), and the shield check read the buffs one by one
-- on every change to them. The game says what changed: a change that cannot be
-- the shield (a proc, a HoT, someone else's buff) keeps what is known. Anything
-- unclear (a full update, no list, a shield whose instance is not known) reads
-- again, as before. Not on WoW: Forever, which keeps its own path.
function ShamanPower:PlayerShieldMayHaveChanged(info)
	if SPCompat.FOREVER then return true end
	local c = self.shieldCache
	if not c or not SPCompat.AuraInfoReadable(info) or info.isFullUpdate then return true end
	local added = info.addedAuras
	if added then
		for i = 1, #added do
			local a = added[i]
			if issecretvalue(a) then return true end
			local name, spellID = a and a.name, a and a.spellId
			if issecretvalue(name) or issecretvalue(spellID) then return true end
			if self:ShieldIndexForAura(name, spellID) then return true end
		end
	end
	local id = c.auraInstanceID
	if id then
		local upd = info.updatedAuraInstanceIDs
		if upd then for i = 1, #upd do local v = upd[i] if issecretvalue(v) or v == id then return true end end end
		local rem = info.removedAuraInstanceIDs
		if rem then for i = 1, #rem do local v = rem[i] if issecretvalue(v) or v == id then return true end end end
	elseif c.hasShield then
		return true
	end
	return false
end

function ShamanPower:UNIT_AURA(event, unit, info)
	if unit then self.auraGen[unit] = (self.auraGen[unit] or 0) + 1 end
	-- Only process if we have a tracked ES target
	if self.esTrackedTargetGUID then
		self:OnEarthShieldAuraChange(unit, info)
	end

	-- Scan for shield buffs when player auras change (avoids polling). Switched
	-- off, nothing shows them: read again on switch-on.
	if unit == "player" and not self:IsOff() then
		if self:PlayerShieldMayHaveChanged(info) then
			self:ScanPlayerShield()
		else
			self._shieldCheckedGen = self.auraGen.player   -- nothing about the shield changed: what is known holds
		end
		if cachePlayerBuffs then self:RefreshPlayerBuffCache() end
	end
end

-- Scan player buffs for shield (called on UNIT_AURA, not every update tick)
-- Shadow shield model: your Lightning / Water Shield from your own casts.
-- A cast opens the record (icon from spell data, length and charge maximum
-- learned from the real aura while readable); a proc of the same shield name
-- under a different spell ID takes a charge off; the real scan re-syncs the
-- record whenever auras are readable, so it is exact when combat starts.
ShamanPower.shadowShield = nil          -- { name, spellID, icon, start, duration, charges }
local shieldLearned = {}                -- [name] = { duration, maxCharges }

local function shieldNameFor(spellID)
	if issecretvalue(spellID) then return nil end
	local name = SPCompat.SpellName(spellID)
	local index = ShamanPower:ShieldIndexForAura(name, spellID)
	if index then
		local data = ShamanPower.ShieldSpells[index]
		return SPCompat.SpellName(data[1], name or data[2]), data[1]
	end
	return nil
end

function ShamanPower:ShadowShieldCast(unit, spellID)
	if unit ~= "player" then return end
	local name, tableID = shieldNameFor(spellID)
	if not name then return end
	local cur = self.shadowShield
	local isRecast = (spellID == tableID) or IsPlayerSpell and IsPlayerSpell(spellID)
	if cur and cur.name == name and not isRecast then
		-- same name, not the castable spell: a proc consumed a charge
		cur.charges = math.max(0, (cur.charges or 0) - 1)
		if SPCompat and SPCompat.Trace then SPCompat.Trace("SHIELD proc %s (%d) charges=%d", name, spellID, cur.charges) end
		if cur.charges == 0 then self.shadowShield = nil end
		return
	end
	local learned = shieldLearned[name] or {}
	local _, _, icon = GetSpellInfo(spellID)
	self.shadowShield = {
		name = name, spellID = tableID, icon = icon,
		start = GetTime(), duration = learned.duration or 600, charges = learned.maxCharges or 3,
	}
	if SPCompat and SPCompat.Trace then SPCompat.Trace("SHIELD cast %s (%d) dur=%s charges=%d", name, spellID, tostring(self.shadowShield.duration), self.shadowShield.charges) end
end

function ShamanPower:ScanPlayerShield()
	local hasShield = false
	local shieldID = nil
	local shieldIcon = nil
	local shieldCharges = 0
	local shieldDuration = 0
	local shieldExpiration = 0
	local shieldBuffIndex = nil
	local shieldName, shieldRawCount = nil, nil

	if totemsSecretNow() then
		-- auras are secret: serve the shadow record (plain numbers, same display code)
		-- the AuraContainer on the shield button draws the shield while auras are
		-- secret; the addon's own rendering shows the empty base underneath
		-- (one table, refilled: in combat this runs on every change to the player's
		-- auras, and a new table each time was the fight's only garbage here.
		-- Compact's memo on it checks the shield and preference it was made for.)
		local c = self._shieldCacheEngine
		if not c then c = {}; self._shieldCacheEngine = c end
		c.hasShield, c.shieldCharges, c.shieldDuration, c.shieldExpiration, c.engineCount = false, 0, 0, 0, true
		c.shieldID, c.shieldIcon, c.buffIndex = nil, nil, nil
		self.shieldCache = c
		return
	end

	for i = 1, 40 do
		local name, icon, count, _, duration, expirationTime, _, _, _, auraID = SPCompat.UnitBuff("player", i)
		if issecretvalue(name) or issecretvalue(auraID) then break end
		if not name then break end
		local index = self:ShieldIndexForAura(name, auraID)
		if index then
			local shieldData = self.ShieldSpells[index]
			hasShield = true
			shieldID = shieldData[1]
			shieldName, shieldRawCount = name, count
			shieldIcon = icon
			shieldCharges = count or 0
			shieldDuration = duration or 0
			shieldExpiration = expirationTime or 0
			shieldBuffIndex = i
		end
		if hasShield then break end
	end

	-- Readable: re-sync the shadow record from the truth and learn the shield's numbers
	if hasShield then
		local name = nil
		for _, data in ipairs(self.ShieldSpells) do if data[1] == shieldID then name = SPCompat.SpellName(shieldID, data[2]) end end
		if name then
			local learned = shieldLearned[name] or {}
			if shieldDuration > 0 then learned.duration = shieldDuration end
			if shieldCharges > (learned.maxCharges or 0) then learned.maxCharges = shieldCharges end
			shieldLearned[name] = learned
			self.shadowShield = {
				name = name, spellID = shieldID, icon = shieldIcon, charges = shieldCharges,
				duration = shieldDuration > 0 and shieldDuration or (learned.duration or 600),
				start = (shieldExpiration > 0 and shieldDuration > 0) and (shieldExpiration - shieldDuration) or GetTime(),
			}
		end
	else
		self.shadowShield = nil
	end

	-- TBC Anniversary: the shield's instance, so a later change can be told apart
	-- (PlayerShieldMayHaveChanged). One more read, only when a shield was found.
	local instanceID
	if hasShield and not SPCompat.FOREVER and C_UnitAuras and C_UnitAuras.GetBuffDataByIndex then
		local ok, a = pcall(C_UnitAuras.GetBuffDataByIndex, "player", shieldBuffIndex)
		if ok and not issecretvalue(a) and type(a) == "table" and not issecretvalue(a.name)
			and a.name == shieldName and not issecretvalue(a.auraInstanceID) then instanceID = a.auraInstanceID end
	end

	-- Cache the result
	self.shieldCache = {
		hasShield = hasShield,
		shieldID = shieldID,
		shieldIcon = shieldIcon,
		shieldCharges = shieldCharges,
		shieldDuration = shieldDuration,
		shieldExpiration = shieldExpiration,
		buffIndex = shieldBuffIndex,
		shieldName = shieldName,          -- Shield Charges reads these on TBC Anniversary instead of its own scan
		rawCount = shieldRawCount,
		auraInstanceID = instanceID,
	}
	self._shieldCheckedGen = self.auraGen and self.auraGen.player or 0   -- current as of this aura change
end

-- Raid cooldown messages: "call" = a one-shot alert, "sync" = assignment state
local RC_MESSAGES = { BLCALL = "call", MTCALL = "call", DRUMCALL = "call", RCSYNC = "sync", MTSYNC = "sync", DRUMSYNC = "sync" }

-- Redraw after received messages at most once per frame. Blizzard's totem bar
-- follows our assignments even with our own bar off, so it is synced here too
-- (cheap and idempotent; in combat it marks itself pending until the fight ends).
local commRefreshQueued = false
local function commRefresh()
	commRefreshQueued = false
	if ShamanPower.SyncTotemSetFromAssignments then ShamanPower:SyncTotemSetFromAssignments() end
	ShamanPower:UpdateLayout()
end
function ShamanPower:QueueCommRefresh()
	if commRefreshQueued or self:IsOff() then return end   -- switched off: switch-on redraws
	commRefreshQueued = true
	C_Timer.After(0, commRefresh)
end

-- Every sender key seen this session, and the form it arrived in, for /spdiag
-- names: one entry per player, nothing allocated per message after the first.
ShamanPower.seenSenderKeys = {}

-- The player a message names, keyed like its sender. Anniversary keeps the realm
-- on a player from another realm ("Name-Realm"), but that shaman's own messages
-- name them plainly (they send UnitName("player")); a plain name equal to the
-- sender's own is the sender. Forever keys are always plain, so nothing changes.
local function messageName(self, name, sender)
	if not strfind(name, "-", 1, true) and name == strsplit("-", sender) then return sender end
	return self:RemoveRealmName(name)
end

function ShamanPower:ParseMessage(sender, msg)
	local received = sender
	sender = self:RemoveRealmName(sender)
	if sender and self.seenSenderKeys[sender] == nil then self.seenSenderKeys[sender] = received end

	if (sender == self.player or sender == nil) or not initialized then return end

	--self:Debug("[Parse Message] sender: " .. sender .. " | msg: " .. msg)

	local leader = self:CheckLeader(sender)
	-- The message type is its first word, read once: the branches below compare
	-- it instead of pattern-matching the whole message a dozen times.
	local kw = strmatch(msg, "^(%u+)")

	if kw == "REQ" then
		-- one broadcast to the group shortly after, however many ask (see QueueSelfBroadcast)
		self:QueueSelfBroadcast()
		return   -- nothing on our bars changed
	end

	-- Windfury status from other players (for SPRange): changes nothing on the bars
	if kw == "WFBUFF" then
		local status = strmatch(msg, "^WFBUFF ([01])")
		if status then self:SetWindfuryReport(sender, status == "1") end
		return
	end

	-- Raid resistance requests (WoW: Forever; ShamanPowerResist.lua): request
	-- state only, nothing on the bars changes until a shaman's own client does it
	if kw == "RESREQ" or kw == "RESPASS" or kw == "RESPICK" then
		if self.HandleResistMessage then
			self:HandleResistMessage(kw, msg, sender)
			return
		end
	end

	-- Raid cooldown coordination: calls are one-shot alerts (no bar change);
	-- the SYNC messages change who is assigned, so they refresh like the rest
	if RC_MESSAGES[kw] then
		if RC_MESSAGES[kw] == "call" and self:IsOff() then return end   -- switched off: no alert
		self:HandleRaidCooldownMessage(nil, msg, sender)
		if RC_MESSAGES[kw] == "call" then return end
	end

	if kw == "SELF" then
		ShamanPower_Assignments[sender] = {}
		ShamanPower.AllShamans[sender] = {}
		self:SyncAdd(sender)

		-- Parse the shaman totem format: SELF <earth>|<fire>|<water>|<air>|@<assignments>#<hasES>:<esTarget>
		-- Example: "SELF 123456|1234567|123456|12345678|@2512#1:Tankname"
		local _, _, totemData, assignAndES = strfind(msg, "SELF ([^@]*)@(.*)")

		-- Split assignments from Earth Shield info
		local assign, esInfo
		if assignAndES then
			local hashPos = strfind(assignAndES, "#")
			if hashPos then
				assign = strsub(assignAndES, 1, hashPos - 1)
				esInfo = strsub(assignAndES, hashPos + 1)
			else
				assign = assignAndES
			end
		end

		if totemData then
			-- Split totemData by pipes to get each element's known totems
			local element = 0
			for elementTotems in string.gmatch(totemData .. "|", "([^|]*)|") do
				element = element + 1
				if element > SHAMANPOWER_MAXELEMENTS then break end

				if elementTotems and elementTotems ~= "" and elementTotems ~= "n" then
					ShamanPower.AllShamans[sender][element] = {}
					-- Each character in elementTotems is a known totem index
					for i = 1, #elementTotems do
						local totemIndex = tonumber(strsub(elementTotems, i, i))
						if totemIndex then
							ShamanPower.AllShamans[sender][element][totemIndex] = { known = true }
						end
					end
				end
			end
		end

		if assign then
			for i = 1, SHAMANPOWER_MAXELEMENTS do
				local tmp = strsub(assign, i, i)
				if tmp == "n" or tmp == "" then
					tmp = 0
				end
				ShamanPower_Assignments[sender][i] = tmp + 0
			end
		end

		-- Parse Earth Shield info and freeassign: <hasES>:<target>$<freeassign>
		if esInfo then
			-- Split off freeassign flag if present
			local esData, freeassignFlag
			local dollarPos = strfind(esInfo, "%$")
			if dollarPos then
				esData = strsub(esInfo, 1, dollarPos - 1)
				freeassignFlag = strsub(esInfo, dollarPos + 1)
			else
				esData = esInfo
			end

			-- Parse Earth Shield
			local _, _, hasES, esTarget = strfind(esData, "([01]):?(.*)")
			if hasES == "1" then
				ShamanPower.AllShamans[sender].hasEarthShield = true
				if esTarget and esTarget ~= "" then
					ShamanPower_EarthShieldAssignments[sender] = esTarget
				end
			else
				ShamanPower.AllShamans[sender].hasEarthShield = false
			end

			-- Parse freeassign flag
			if freeassignFlag == "1" then
				ShamanPower.AllShamans[sender].freeassign = true
			else
				ShamanPower.AllShamans[sender].freeassign = false
			end
		end
	end

	if kw == "ASSIGN" then
		-- the name is everything before the two numbers, so "First Last" stays whole
		local name, class, skill = strmatch(msg, "^ASSIGN (.+) (%d+) (%d+)$")
		if not name then return end
		name = messageName(self, name, sender)
		if name ~= sender and not (leader or self.opt.freeassign) then
			return false
		end
		if not ShamanPower_Assignments[name] then
			ShamanPower_Assignments[name] = {}
		end
		class = class + 0
		skill = skill + 0
		ShamanPower_Assignments[name][class] = skill
		-- Forever: two shamans taking the same raid resistance settle it here
		if self.ResistClaimSeen then self:ResistClaimSeen(name, class, skill) end
	end

	-- Handle TWIST message for totem twisting assignment
	if kw == "TWIST" then
		if self.NoTotemTwisting then return end   -- WoW: Forever cannot twist: nobody turns it on for us
		local name, enabled = strmatch(msg, "^TWIST (.+) ([01])$")
		if not name then return end
		name = messageName(self, name, sender)
		if name ~= sender and not (leader or self.opt.freeassign) then
			return false
		end
		local twistEnabled = (enabled == "1")
		ShamanPower_TwistAssignments[name] = twistEnabled

		-- If this is for us, update our local setting
		if name == self.player then
			self.opt.enableTotemTwisting = twistEnabled
			self:UpdateMiniTotemBar()
			self:UpdateSPMacros()
			-- Refresh Options panel if it's open
			LibStub("AceConfigRegistry-3.0"):NotifyChange("ShamanPower")
			if twistEnabled then
				self:SetupTwistTimer()
			else
				self:HideTwistTimer()
			end
		end

		-- Update the UI
		self:UpdateRoster()
	end

	if kw == "PASSIGN" then
		local name, assign = strmatch(msg, "^PASSIGN (.+)@([0-9n]*)")
		if not name then return end
		name = messageName(self, name, sender)
		if name ~= sender and not (leader or self.opt.freeassign) then
			return false
		end
		if not ShamanPower_Assignments[name] then
			ShamanPower_Assignments[name] = {}
		end
		if assign then
			for i = 1, SHAMANPOWER_MAXELEMENTS do
				local tmp = strsub(assign, i, i)
				if tmp == "n" or tmp == "" then
					tmp = 0
				end
				ShamanPower_Assignments[name][i] = tmp + 0
			end
		end
	end

	if kw == "MASSIGN" then
		local name, skill = strmatch(msg, "^MASSIGN (.+) (%d+)$")
		if not name then return end
		name = messageName(self, name, sender)
		if name ~= sender and not (leader or self.opt.freeassign) then
			return false
		end
		if not ShamanPower_Assignments[name] then
			ShamanPower_Assignments[name] = {}
		end
		skill = skill + 0
		for i = 1, SHAMANPOWER_MAXELEMENTS do
			ShamanPower_Assignments[name][i] = skill
		end
	end

	if kw == "CLEAR" then
		if leader then
			self:ClearAssignments(sender)
		elseif self.opt.freeassign then
			self:ClearAssignments(self.player)
		end
	end

	if kw == "FREEASSIGN" and strfind(msg, "FREEASSIGN YES", 1, true) and ShamanPower.AllShamans[sender] then
		ShamanPower.AllShamans[sender].freeassign = true
	end

	if kw == "FREEASSIGN" and strfind(msg, "FREEASSIGN NO", 1, true) and ShamanPower.AllShamans[sender] then
		ShamanPower.AllShamans[sender].freeassign = false
	end

	-- Earth Shield assignment sync
	if kw == "ESASSIGN" then
		local name, target = self:DecodeESAssign(msg, sender)
		if not name or not target then return end
		name = messageName(self, name, sender)
		if name ~= sender and not (leader or self.opt.freeassign) then
			return false
		end
		if target == "NONE" then
			ShamanPower_EarthShieldAssignments[name] = nil
		else
			target = self:RemoveRealmName(target)
			ShamanPower_EarthShieldAssignments[name] = target
		end
		-- Update UI if it's our own assignment
		if name == self.player then
			self:UpdateMiniTotemBar()
			self:UpdateEarthShieldMacroButton()
		end
	end

	-- Blizzard's totem bar follows our assignments even with our own totem bar
	-- switched off: UpdateLayout only refreshes (and syncs) while that bar is
	-- shown, so an assignment sent by another shaman never reached Blizzard's bar
	-- for someone running without ours. Cheap and idempotent; in combat it marks
	-- itself pending and lands when the fight ends (only a hardware click may
	-- write that bar mid-fight).
	-- A burst of messages (a raid's worth of SELF replies) redraws once, on the
	-- next frame, instead of once per message.
	self:QueueCommRefresh()
end

-- ESASSIGN carries two player names. The original form "ESASSIGN <shaman> <target>"
-- is ambiguous once a name can contain a space (WoW: Forever "First Last"), so
-- when a name has one, WoW: Forever sends "ESASSIGN|<shaman>|<target>" instead;
-- '|' cannot occur in a name. Anniversary names never contain spaces, so its
-- wire format is unchanged. Readers accept both forms.
function ShamanPower:EncodeESAssign(shaman, target)
	target = target or "NONE"
	if SPCompat.FOREVER and (strfind(shaman, " ", 1, true) or strfind(target, " ", 1, true)) then
		return "ESASSIGN|" .. shaman .. "|" .. target
	end
	return "ESASSIGN " .. shaman .. " " .. target
end

function ShamanPower:DecodeESAssign(msg, sender)
	local name, target = strmatch(msg, "^ESASSIGN|([^|]+)|(.+)$")
	if name then return name, target end
	local rest = strmatch(msg, "^ESASSIGN (.+)$")
	if not rest then return nil end
	-- Most often the shaman is the sender: everything after their name is the
	-- target, which keeps a spaced target whole even in the old form.
	if sender then
		local plain = strsplit("-", sender)
		for _, who in ipairs({ sender, plain }) do
			if strsub(rest, 1, #who + 1) == who .. " " then return who, strsub(rest, #who + 2) end
		end
	end
	-- otherwise the last word is the target (the original reading)
	return strmatch(rest, "^(.*) (.-)$")
end

function ShamanPower:CanControl(name)
	if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and IsInInstance() then
		return (name == self.player) or (ShamanPower.AllShamans[name] and (ShamanPower.AllShamans[name].freeassign == true))
	else
		-- the "player" token, not our name: on Forever that is "First Surname", which the group API may not resolve
		if UnitIsGroupLeader("player") or UnitIsGroupAssistant("player") then
			return true
		else
			return (name == self.player) or (ShamanPower.AllShamans[name] and (ShamanPower.AllShamans[name].freeassign == true))
		end
	end
end

function ShamanPower:CheckLeader(nick)
	if leaders[nick] == true then
		return true
	else
		return false
	end
end

function ShamanPower:ClearAssignments(sender)
	local leader = self:CheckLeader(sender)
	for name in pairs(ShamanPower_Assignments) do
		if leader or name == self.player then
			for i = 1, SHAMANPOWER_MAXELEMENTS do
				ShamanPower_Assignments[name][i] = 0
			end
		end
	end
end

function ShamanPower:SyncClear()
	ShamanPower.SyncList = {}
end

function ShamanPower:SyncAdd(name)
	local chk = 0
	for _, v in ipairs(ShamanPower.SyncList) do
		if v == name then
			chk = 1
		end
	end
	if chk == 0 then
		tinsert(ShamanPower.SyncList, name)
		tsort(
			ShamanPower.SyncList,
			function(a, b)
				return a < b
			end
		)
	end
	-- Ensure assignment tables have entries for this player
	if not ShamanPower_Assignments then ShamanPower_Assignments = {} end
	if not ShamanPower_Assignments[name] then
		ShamanPower_Assignments[name] = {}
	end
end

function ShamanPower:FormatTime(time)
	if not time or time < 0 or time == 9999 then
		return ""
	end
	local mins = floor(time / 60)
	local secs = time - (mins * 60)
	return format("%d:%02d", mins, secs)
end

function ShamanPower:AddRealmName(unitID)
	local name, realm = strsplit("-", unitID)
	realm = realm or self.realm

	return name .. "-" .. realm
end

-- WoW: Forever has region-wide unique character names, and the realm part the
-- game reports can differ between players on the same ruleset (seen on the beta).
-- Keeping a "Name-Realm" there would stop it matching the plain name everything
-- else is keyed by (assignments, Windfury reports, raid calls), so Forever always
-- uses the name alone. Classic keeps the realm when it is not ours: two players
-- on different realms can share a name there.
local REGION_UNIQUE_NAMES = (SPCompat.FOREVER)
function ShamanPower:RemoveRealmName(unitID)
	if type(unitID) ~= "string" then return unitID end
	-- only the hyphen separates the realm: a WoW: Forever name may contain a space
	-- ("First Last") and is kept whole
	local name, realm = strsplit("-", unitID)
	if REGION_UNIQUE_NAMES then return name end
	if realm and realm ~= self.realm then
		return unitID
	else
		return name
	end
end

function ShamanPower:OnRosterSettled()
	self:UpdateRoster()
	-- the party dots' room is kept only in a group: joining or leaving one lays the
	-- bars out again (the button spacing waits for the end of a fight, then comes here)
	local grouped = IsInGroup() and true or false
	if self._dotRoomGrouped ~= grouped
		or (self._dotBarSpacing and self._dotBarSpacing ~= self:TotemBarSpacing()) then
		self._dotRoomGrouped = grouped
		if self.UpdatePartyDotPositions then self:UpdatePartyDotPositions() end
		self:PositionActiveOverlays()   -- the dropped-totem icons step past the dots too
		-- Blizzard's Totem Bar styles its own bars (after the fight when in one)
		if self.UsingBlizzardTotemBar and self:UsingBlizzardTotemBar() and self.QueueBlizzardTotemBarRefresh then
			self.QueueBlizzardTotemBarRefresh()
		end
	end
end

-- One roster member: who leads, and which raid subgroup each known shaman is in
-- (used by auto-assign).
local function rosterMember(self, name, rank, subgroup, class, instanceGroup)
	if not name then return end
	-- the same form message senders are keyed by (RemoveRealmName), so leaders[]
	-- and AllShamans[] line up with CheckLeader(sender) and the SELF data
	name = self:RemoveRealmName(name)
	if class == "SHAMAN" and ShamanPower.AllShamans[name] then
		ShamanPower.AllShamans[name].subgroup = subgroup
	end
	if rank and rank > 0 and not instanceGroup then
		leaders[name] = true
		if name == self.player and AC_Leader == false then
			AC_Leader = true
		end
	end
end

function ShamanPower:UpdateRoster()
	--self:Debug("UpdateRoster()")
	-- Skip if not in a group (no roster to update)
	local count = GetNumGroupMembers()
	if count == 0 then
		return
	end
	twipe(leaders)
	local instanceGroup = IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and IsInInstance()
	if IsInRaid() then
		-- one call per member gives name, rank, subgroup and class: no unit tokens,
		-- no string work (pets were walked too and never mattered)
		for i = 1, count do
			local name, rank, subgroup, _, _, class = GetRaidRosterInfo(i)
			rosterMember(self, name, rank, subgroup, class, instanceGroup)
		end
	else
		for i = 1, #party_units do
			local unitid = party_units[i]
			if UnitExists(unitid) and UnitIsPlayer(unitid) then
				rosterMember(self, GetUnitName(unitid, true), UnitIsGroupLeader(unitid) and 2 or 0, 1, (UnitClassBase(unitid)), instanceGroup)
			end
		end
	end
	self:UpdateLayout()

	-- Update SPRange visibility based on group composition
	self:UpdateSPRangeVisibility()

	-- Update Earth Shield flyout when group composition changes
	if not InCombatLockdown() then
		self:CreateEarthShieldFlyout()
	end
end

function ShamanPower:CreateLayout()
	--self:Debug("CreateLayout()")
	self.Header = _G["ShamanPowerFrame"]
	self.autoButton = CreateFrame("Button", "ShamanPowerAuto", self.Header, "SecureHandlerShowHideTemplate, SecureHandlerEnterLeaveTemplate, SecureHandlerStateTemplate, SecureActionButtonTemplate, ShamanPowerAutoButtonTemplate")
	self.autoButton:RegisterForClicks("LeftButtonDown", "RightButtonDown")
	-- the bar grows as totems are learned (and with Grid / Compact): one on its default spot re-centres
	self.autoButton:HookScript("OnSizeChanged", function() ShamanPower:ApplyDefaultBarPositions() end)

	-- ALT+drag to move the frame
	self.autoButton:RegisterForDrag("LeftButton")
	self.autoButton:HookScript("OnDragStart", function(btn)
		local unlocked = ShamanPower.opt.display and ShamanPower.opt.display.moverUnlocked
		if (IsAltKeyDown() or unlocked) and not InCombatLockdown() then
			local frame = ShamanPowerFrame
			frame:SetMovable(true)
			frame:StartMoving()
			ShamanPower.isDragging = true
		end
	end)
	self.autoButton:HookScript("OnDragStop", function(btn)
		if ShamanPower.isDragging then
			local frame = ShamanPowerFrame
			frame:StopMovingOrSizing()
			ShamanPower.isDragging = false
			-- Save position to profile (ensures display table exists for proper persistence)
			ShamanPower:SaveFramePosition(frame)
		end
	end)
	self:UpdateLayout()
end

function ShamanPower:UpdateLayout()
	--self:Debug("UpdateLayout()")
	if InCombatLockdown() then
		-- A /reload during a fight lands here from PLAYER_ENTERING_WORLD with
		-- nothing built yet; OnCombatEnd finishes the login sequence.
		self._layoutPendingCombat = true
		return
	end

	-- Scale around the on-screen centre so the bar does not slide as it grows.
	-- The first application at login is a plain SetScale: the saved position
	-- has not been restored yet, and saving here would overwrite it.
	local buffscale = self.opt.buffscale or 0.9
	if not self._barScaleApplied then
		ShamanPowerFrame:SetScale(buffscale)
		self._barScaleApplied = true
	elseif math.abs(ShamanPowerFrame:GetScale() - buffscale) > 0.001 and not self:TotemBarRecord() then
		ShamanPowerFrame:SetScale(buffscale)   -- on its default spot: put back there below
	elseif math.abs(ShamanPowerFrame:GetScale() - buffscale) > 0.001 then
		-- The whole bar (mini-bar frame + buttons hanging off its top-left)
		-- scales linearly about the root frame, so the shift that keeps the
		-- bar's centre fixed can be computed now -- no deferred correction,
		-- which would show one wrong frame per slider tick and flicker.
		local bx, by = self:GetTotemBarScreenCenter()
		local f = ShamanPowerFrame
		local fcx, fcy = f:GetCenter()
		if bx and fcx then
			local esOld = f:GetEffectiveScale()
			fcx, fcy = fcx * esOld, fcy * esOld
			f:SetScale(buffscale)
			local esNew = f:GetEffectiveScale()
			local k = esNew / esOld
			local nx, ny = bx - (bx - fcx) * k, by - (by - fcy) * k
			f:ClearAllPoints()
			f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", nx / esNew, ny / esNew)
		else
			self:SetFrameScaleKeepCenter(f, buffscale)
		end
		self:SaveFramePosition(f)
	end
	-- Update cooldown bar scale to compensate for parent scale change
	self:UpdateCooldownBarScale()
	local x = self.opt.display.buttonWidth or 100
	local y = self.opt.display.buttonHeight or 34
	local point = "TOPLEFT"
	local layout = self.Layouts[self.opt.layout]
	if not layout then
		-- Fallback to Vertical (Right) if the configured layout doesn't exist
		self.opt.layout = "Horizontal"
		layout = self.Layouts["Vertical"]
	end
	local ox = layout.ab.x * x
	local oy = layout.ab.y * y
	local autob = self.autoButton
	autob:ClearAllPoints()
	autob:SetPoint(point, self.Header, "CENTER", ox, oy)
	autob:SetAttribute("type", "spell")
	-- Show mini totem bar only if:
	-- 1. Is a shaman, addon enabled, autobutton option on
	-- 2. In party/raid or solo (based on settings)
	local showMiniBar = self:TotemBarInUse()   -- the same test the hide and fade rules make
	if showMiniBar then
		self:SetTotemBarFramesShown(true)
		-- Update the mini totem bar icons and spells
		self:UpdateMiniTotemBar()
		self:UpdateDropAllButton()
		-- Note: UpdateSPMacros() is called only when assignments change, not on every layout update
	else
		self:SetTotemBarFramesShown(false)
	end
	self:ApplyDefaultBarPositions()   -- bars with no saved spot follow the new size / layout / scale

	-- Apply opacity settings
	self:ApplyAllOpacity()

	self:ButtonsUpdate()
	self:PositionActiveOverlays()
	self:UpdateAnchor()
end

function ShamanPower:ButtonsUpdate()
	--self:Debug("ButtonsUpdate()")
	local autobutton = _G["ShamanPowerAuto"]
	if not autobutton then return end
	-- Colour the mini totem bar by how many of the assigned totems are currently down
	local activeCount, assignedCount = self:GetTotemStatus()
	if assignedCount == 0 then
		-- No totems assigned
		self:ApplyBackdrop(autobutton, self.opt.cBuffGood)
	elseif activeCount == 0 then
		-- No totems active (all need to be dropped)
		self:ApplyBackdrop(autobutton, self.opt.cBuffNeedAll)
	elseif activeCount < assignedCount then
		-- Some totems active
		self:ApplyBackdrop(autobutton, self.opt.cBuffNeedSome)
	else
		-- All assigned totems are active
		self:ApplyBackdrop(autobutton, self.opt.cBuffGood)
	end
end

function ShamanPower:UpdateAnchor()
	-- The drag handle was replaced by the Unlock Bar mover; keep it hidden.
	ShamanPowerAnchor:Hide()
end

function ShamanPower:ClickHandle(button, mousebutton)
	-- Lock & Unlock the frame on left click, and toggle config dialog with right click
	local function RelockActionBars()
		ShamanPower:EnsureProfileTable("display")
		self.opt.display.frameLocked = true
		if (self.opt.display.LockBuffBars) then
			LOCK_ACTIONBAR = "1"
		end
		_G["ShamanPowerAnchor"]:SetChecked(true)
	end
	if (mousebutton == "RightButton") then
		if IsShiftKeyDown() then
			self:OpenConfigWindow()
			button:SetChecked(self.opt.display.frameLocked)
		else
			ShamanPower:ToggleAssignmentWindow()
			button:SetChecked(self.opt.display.frameLocked)
		end
	elseif (mousebutton == "LeftButton") then
		self:EnsureProfileTable("display")
		self.opt.display.frameLocked = not self.opt.display.frameLocked
		if (self.opt.display.frameLocked) then
			if (self.opt.display.LockBuffBars) then
				LOCK_ACTIONBAR = "1"
			end
			local h = _G["ShamanPowerFrame"]
			self:SaveFramePosition(h)
		else
			if (self.opt.display.LockBuffBars) then
				LOCK_ACTIONBAR = "0"
			end
			self:ScheduleTimer(RelockActionBars, 30)
		end
		button:SetChecked(self.opt.display.frameLocked)
	end
end

function ShamanPower:DragStart()
	-- Start dragging if not locked
	if (not self.opt.display.frameLocked) then
		local h = _G["ShamanPowerFrame"]
		h:SetClampedToScreen(false)  -- Allow free movement
		h:StartMoving()
	end
end

function ShamanPower:DragStop()
	-- End dragging and save position
	local h = _G["ShamanPowerFrame"]
	h:StopMovingOrSizing()
	-- Save position to profile (ensures display table exists for proper persistence)
	self:SaveFramePosition(h)
	-- Auto directions depend on where the bar sits on screen
	self:PositionActiveOverlays()
end

function ShamanPower:ApplySkin()
	local border = LSM3:Fetch("border", self.opt.border)
	local background = LSM3:Fetch("background", self.opt.skin)
	local tmp = {bgFile = background, edgeFile = border, tile = false, tileSize = 8, edgeSize = 8, insets = {left = 0, right = 0, top = 0, bottom = 0}}
	if BackdropTemplateMixin then
		Mixin(ShamanPowerAuto, BackdropTemplateMixin)
	end
	-- Only apply backdrop to totem bar if not hidden
	-- Grid lays the totems out in its own rows and Blizzard's bar replaces ours:
	-- the old bar's frame would be an empty box on screen
	local noBarFrame = (self.GridActive and self:GridActive()) or (self.UsingBlizzardTotemBar and self:UsingBlizzardTotemBar())
	if self.opt.hideTotemBarFrame or noBarFrame then
		ShamanPowerAuto:SetBackdrop(nil)
	else
		ShamanPowerAuto:SetBackdrop(tmp)
		self:ThemePaintBarFrame(ShamanPowerAuto, "tb.frame")   -- General > Themes: the border; nothing on Standard
		self:FitBarBackdrop(ShamanPowerAuto)   -- out past the flyout tabs again, if they show
	end
	if self.EdgeFrame then self:EdgeFrame(ShamanPowerAuto) end   -- Frame Edges
end

function ShamanPower:ApplyBackdrop(button, preset)
	-- button coloring: preset
	if BackdropTemplateMixin then
		Mixin(button, BackdropTemplateMixin)
	end
	button:SetBackdropColor(preset["r"], preset["g"], preset["b"], preset["t"])
end

function ShamanPower:UpdateTotemBarFrame()
	-- Show or hide the totem bar frame (background/border)
	if not ShamanPowerAuto then return end

	local noBarFrame = (self.GridActive and self:GridActive()) or (self.UsingBlizzardTotemBar and self:UsingBlizzardTotemBar())
	if self.opt.hideTotemBarFrame or noBarFrame then
		-- Hide the frame - set backdrop to nil (Grid / Blizzard's bar: there is no bar of ours to frame)
		ShamanPowerAuto:SetBackdrop(nil)
	else
		-- Show the frame - reapply skin
		self:ApplySkin()
	end
end

function ShamanPower:UpdateCooldownBarFrame()
	-- Show or hide the cooldown bar frame (background/border)
	if not self.cooldownBar then return end

	if self.opt.hideCooldownBarFrame then
		-- Hide the frame
		self.cooldownBar:SetBackdrop(nil)
	else
		-- Show the frame
		self.cooldownBar:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 12,
			insets = { left = 2, right = 2, top = 2, bottom = 2 }
		})
		self.cooldownBar:SetBackdropColor(0, 0, 0, 0.7)
		self.cooldownBar:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
		self:ThemePaintBarFrame(self.cooldownBar, "cd.frame")   -- General > Themes; nothing on Standard
		self:FitBarBackdrop(self.cooldownBar)   -- out past the flyout tabs again, if they show
	end
	if self.EdgeFrame then self:EdgeFrame(self.cooldownBar) end   -- Frame Edges
end

function ShamanPower:AutoAssign()
	if InCombatLockdown() then return end

	if self:CheckLeader(self.player) or AC_Leader == false then
		self:ClearAssignments(self.player)
		self:SendMessage("CLEAR")
		self:AutoAssignTotems()
		self:UpdateRoster()
		C_Timer.After(
			0.25,
			function()
				for name in pairs(ShamanPower.AllShamans) do
					local s = ""
					local BuffInfo = ShamanPower_Assignments[name]
					if not BuffInfo then BuffInfo = {} end
					for i = 1, SHAMANPOWER_MAXELEMENTS do
						if not BuffInfo[i] or BuffInfo[i] == 0 then
							s = s .. "n"
						else
							s = s .. BuffInfo[i]
						end
					end
					self:SendMessage("PASSIGN " .. name .. "@" .. s)
				end
				C_Timer.After(
					0.25,
					function()
						self:UpdateLayout()
					end
				)
			end
		)
	end
end

-- Composition-driven priorities (first existing, unused choice; repeat first
-- after the useful choices are exhausted). No Tremor or Mana Tide auto-picks.
--             Physical DPS / tank             Caster-only
-- Earth       Strength, Stoneskin               Stoneskin, Strength
-- Fire        ToW if Elemental (Classic only); Flametongue if casters > melee,
--             otherwise Searing; the other usable Fire choices follow.
-- Water       Mana Spring with any mana user, otherwise Healing Stream; swap
--             to the other choice for another shaman in the same subgroup.
-- Air         Windfury; Grace if AGI > WF users Classic: Wrath, Windfury, Grace
--                                               Forever: Tranquil, Windfury, Grace
-- Forever tankless physical groups keep their physical first choice (including
-- shaman + warrior => Windfury); Tranquil is next for a second shaman.
do
	local priorities = {
		earthPhysical = { 1, 2 }, earthCaster = { 2, 1 },
		fireCaster = { 5, 2 }, firePhysical = { 2, 5 },
		fireElementalCaster = { 1, 5, 2 }, fireElementalPhysical = { 1, 2, 5 },
		waterMana = { 1, 2 }, waterHealth = { 2, 1 },
		airMelee = { 1, 2 }, airAgility = { 2, 1 },
		airMeleeThreat = { 1, 4, 2 }, airAgilityThreat = { 2, 4, 1 },
		airCasterClassic = { 3, 1, 2 }, airCasterForever = { 4, 1, 2 },
	}
	local manaClasses = { PALADIN = true, HUNTER = true, PRIEST = true, SHAMAN = true,
		MAGE = true, WARLOCK = true, DRUID = true }
	local function Public(value)
		if issecretvalue and issecretvalue(value) then return nil end
		return value
	end
	local function Subgroup(value, fallback)
		if issecretvalue and issecretvalue(value) then return nil end
		if value == nil then return fallback end
		if type(value) == "number" and value >= 1 and value <= 8 and value % 1 == 0 then return value end
	end
	local function Composition()
		-- meleeDPS includes rogues/cats; agilityDPS overlaps those and hunters.
		-- Historical aliases preserve the preference comparison: melee means
		-- Windfury-favoured units (including physical tanks), caster includes
		-- healers, agiUsers includes feral tanks as well as agility DPS.
		return { tank = 0, healer = 0, meleeDPS = 0, rangedCaster = 0,
			agilityDPS = 0, manaUsers = 0, melee = 0, caster = 0, agiUsers = 0, total = 0 }
	end
	local function CountUnit(self, comp, unit, raidRole, forever, playerEnhancement)
		if Public(UnitExists(unit)) ~= true then return end
		comp.total = comp.total + 1
		local _, class = UnitClass(unit)
		class = Public(class)
		local role = UnitGroupRolesAssigned and Public(UnitGroupRolesAssigned(unit))
		if role ~= "TANK" and role ~= "HEALER" and role ~= "DAMAGER" then role = nil end
		local power
		if class == "DRUID" and UnitPowerType then power = Public(UnitPowerType(unit)) end
		if not role then
			if Public(raidRole) == "MAINTANK" then role = "TANK"
			elseif class == "DRUID" and power == 1 then role = "TANK"
			else role = "DAMAGER" end
		end
		if role == "TANK" then comp.tank = comp.tank + 1 end
		if role == "HEALER" then comp.healer = comp.healer + 1; comp.caster = comp.caster + 1 end
		-- An unreadable class never becomes a guessed DPS or mana user.
		if not class then return end
		if manaClasses[class] then comp.manaUsers = comp.manaUsers + 1 end
		if role == "HEALER" then return end

		local feral = class == "DRUID" and (power == 1 or power == 3 or role == "TANK")
		if class == "DRUID" and not feral and not forever then feral = self:IsDruidFeral(unit) end
		local enhancement = false
		if class == "SHAMAN" then
			local isPlayer = unit == "player" or (UnitIsUnit and Public(UnitIsUnit(unit, "player")) == true)
			enhancement = isPlayer and playerEnhancement or false
			if not enhancement and not forever then enhancement = self:IsShamanEnhancement(unit) end
		end
		local windfury = class == "WARRIOR" or class == "PALADIN" or enhancement
		local agility = class == "ROGUE" or class == "HUNTER" or feral
		if windfury then comp.melee = comp.melee + 1 end
		if agility then comp.agiUsers = comp.agiUsers + 1 end
		if role == "TANK" then return end
		if agility then comp.agilityDPS = comp.agilityDPS + 1 end
		if windfury or class == "ROGUE" or feral then
			comp.meleeDPS = comp.meleeDPS + 1
		elseif class ~= "HUNTER" and manaClasses[class] then
			comp.rangedCaster = comp.rangedCaster + 1
			comp.caster = comp.caster + 1
		end
	end

	function ShamanPower:AutoAssignTotems()
		local forever = SPCompat.FOREVER
		local composition = self:AnalyzeGroupComposition()
		local names, groups, controllable, assigned = {}, {}, {}, {}
		local fallbackGroup
		if not IsInRaid() then fallbackGroup = 1 end
		for group = 1, 8 do assigned[group] = { {}, {}, {}, {} } end
		for name, info in pairs(self.AllShamans) do
			local group = Subgroup(info.subgroup, fallbackGroup)
			if group then
				names[#names + 1] = name
				groups[name] = group
				controllable[name] = name == self.player or Public(self:CanControl(name)) == true
			end
		end
		table.sort(names)
		-- Preserve others' assignments and count them before picking our slots.
		for _, name in ipairs(names) do
			if not controllable[name] then
				local existing = ShamanPower_Assignments[name]
				for element = 1, 4 do
					local index = existing and Public(existing[element])
					if type(index) == "number" and index > 0 and self:TotemExistsOnClient(element, index) then
						assigned[groups[name]][element][index] = true
					end
				end
			end
		end
		local function Pick(group, element, choices)
			local first
			for _, index in ipairs(choices) do
				if self:TotemExistsOnClient(element, index) then
					first = first or index
					if not assigned[group][element][index] then
						assigned[group][element][index] = true
						return index
					end
				end
			end
			return first or 0 -- Nothing eligible: leave that element unassigned.
		end
		for _, name in ipairs(names) do
			if controllable[name] then
				local group = groups[name]
				local comp = composition[group]
				local physical = comp.tank > 0 or comp.meleeDPS > 0
				local casterHeavy = comp.caster > comp.meleeDPS + comp.tank
				local elemental = not forever and self:TotemExistsOnClient(2, 1) and self:ShamanHasTotemOfWrath(name)
				local fire = casterHeavy and priorities.fireCaster or priorities.firePhysical
				if elemental then fire = casterHeavy and priorities.fireElementalCaster or priorities.fireElementalPhysical end
				local air
				if not physical and comp.agiUsers == 0 then
					air = forever and priorities.airCasterForever or priorities.airCasterClassic
				elseif comp.agiUsers > comp.melee then
					air = forever and comp.tank == 0 and priorities.airAgilityThreat or priorities.airAgility
				else
					air = forever and comp.tank == 0 and priorities.airMeleeThreat or priorities.airMelee
				end
				local loadout = ShamanPower_Assignments[name] or {}
				ShamanPower_Assignments[name] = loadout
				loadout[1] = Pick(group, 1, physical and priorities.earthPhysical or priorities.earthCaster)
				loadout[2] = Pick(group, 2, fire)
				loadout[3] = Pick(group, 3, comp.manaUsers > 0 and priorities.waterMana or priorities.waterHealth)
				loadout[4] = Pick(group, 4, air)
			end
		end
		-- (this used to send "SHPWR_ASSIGNMENTSUPDATED" to the whole group, which no
		-- client ever handled: it was meant as a local notification)
		self:UpdateRoster()
		self:Print("Totems assigned to suit your party and roles.")
	end

	function ShamanPower:AnalyzeGroupComposition()
		local composition = {}
		for group = 1, 8 do composition[group] = Composition() end
		local forever = SPCompat.FOREVER
		local knows = IsPlayerSpell or IsSpellKnown
		-- Stormstrike is already catalogued in Ready Reminders (17364). This is
		-- local spellbook knowledge, never an aura/spec read from another shaman.
		local playerEnhancement = knows and Public(knows(17364)) == true
		local members, raid = GetNumGroupMembers(), IsInRaid()
		if members == 0 then
			CountUnit(self, composition[1], "player", nil, forever, playerEnhancement)
			return composition
		end
		for index = 1, members do
			local unit = raid and ("raid" .. index) or (index == members and "player" or ("party" .. index))
			local group, raidRole = 1, nil
			if raid then
				local _, _, subgroup, _, _, _, _, _, _, role = GetRaidRosterInfo(index)
				group, raidRole = Subgroup(subgroup), role
			end
			if group then CountUnit(self, composition[group], unit, raidRole, forever, playerEnhancement) end
		end
		return composition
	end
end

-- Check if a druid is feral (cat/bear) vs caster (balance/resto)
function ShamanPower:IsDruidFeral(unit)
	if not UnitExists(unit) then return false end

	-- Check power type: Ferals in form use rage (bear) or energy (cat)
	local powerType = UnitPowerType(unit)
	if powerType == 1 or powerType == 3 then  -- Rage or Energy
		return true
	end

	-- Check if they have Mangle or other feral abilities (by checking buffs/debuffs)
	-- Ferals often have Leader of the Pack buff
	for i = 1, 40 do
		local name, _, _, _, _, _, _, _, _, spellID = SPCompat.UnitBuff(unit, i)
		if issecretvalue(name) or issecretvalue(spellID) then return false end
		if not name then break end
		if SPCompat.AuraMatches(name, spellID, 24932) then
			return true
		end
	end

	-- Default: assume caster if we can't tell
	return false
end

-- Check if a shaman is Enhancement spec
function ShamanPower:IsShamanEnhancement(unit)
	if not UnitExists(unit) then return false end

	-- Enhancement shamans dual wield or use 2H with Stormstrike
	-- Check if they have Stormstrike buff/ability
	for i = 1, 40 do
		local name, _, _, _, _, _, _, _, _, spellID = SPCompat.UnitBuff(unit, i)
		if issecretvalue(name) or issecretvalue(spellID) then return false end
		if not name then break end
		-- Unleashed Rage family 30802 and buff 30809 share the localized name;
		-- verified in Blizzard SpellName data, Classic 2.5.5.65463.
		if SPCompat.AuraMatches(name, spellID, 30802) or SPCompat.AuraMatches(name, spellID, 30823) then
			return true
		end
	end

	-- Check power type isn't mana-heavy casting (enhancement still uses mana but differently)
	-- This is a rough heuristic
	return false
end

-- Check if a shaman has Totem of Wrath (Elemental talent)
function ShamanPower:ShamanHasTotemOfWrath(shamanName)
	if ShamanPower.AllShamans[shamanName] and ShamanPower.AllShamans[shamanName].Fire then
		-- Check if they have ToW in their available fire totems
		for totemID, _ in pairs(ShamanPower.AllShamans[shamanName].Fire or {}) do
			if totemID == 1 then  -- ToW is index 1 in fire totems
				return true
			end
		end
	end
	-- For self, check if we know the spell
	if shamanName == self.player then
		return PlayerKnowsTotem(30706)  -- Totem of Wrath spell ID
	end
	return false
end

-- Check if a shaman has Mana Tide (Resto talent)
function ShamanPower:ShamanHasManaTide(shamanName)
	if ShamanPower.AllShamans[shamanName] and ShamanPower.AllShamans[shamanName].Water then
		-- Check if they have Mana Tide in their available water totems
		for totemID, _ in pairs(ShamanPower.AllShamans[shamanName].Water or {}) do
			if totemID == 3 then  -- Mana Tide is index 3 in water totems
				return true
			end
		end
	end
	-- For self, check if we know the spell
	if shamanName == self.player then
		return PlayerKnowsTotem(16190)  -- Mana Tide Totem spell ID
	end
	return false
end

-- ============================================================================
-- Keybinding Setup (using SetOverrideBindingClick for secure button clicks)
-- ============================================================================

-- Map binding names to button names
ShamanPower.KeybindButtons = {
	["SHAMANPOWER_DROPALL"] = "ShamanPowerAutoDropAll",
	["SHAMANPOWER_EARTH_TOTEM"] = "ShamanPowerTotemBtn1",
	["SHAMANPOWER_FIRE_TOTEM"] = "ShamanPowerTotemBtn2",
	["SHAMANPOWER_WATER_TOTEM"] = "ShamanPowerTotemBtn3",
	["SHAMANPOWER_AIR_TOTEM"] = "ShamanPowerTotemBtn4",
	["SHAMANPOWER_EARTH_SHIELD"] = "ShamanPowerEarthShieldBtn",
	-- Compact's Your Shield Line (ShamanPowerCompact.lua). One click casts (type1), and the swap
	-- (ApplyClickSwap) leaves it as it is, so KeyMouseButton's left click is its cast click
	["SHAMANPOWER_SHIELD_LINE"] = "ShamanPowerCompactShieldBtn",
	["SHAMANPOWER_TOTEMIC_CALL"] = "ShamanPowerTotemicCallBtn",
	-- Call of the Elements / Ancestors / Spirits, one key each (hidden buttons
	-- made by ShamanPowerTotemSets.lua on WoW: Forever; inert elsewhere)
	["SHAMANPOWER_CALL_ELEMENTS"] = "ShamanPowerCallElementsBtn",
	["SHAMANPOWER_CALL_ANCESTORS"] = "ShamanPowerCallAncestorsBtn",
	["SHAMANPOWER_CALL_SPIRITS"] = "ShamanPowerCallSpiritsBtn",
	-- Flyouts (box mode): each key presses that flyout's TOGGLE helper (SPFT<K>,
	-- see EnsureFlyoutBox), so one key opens and closes, in or out of combat,
	-- and obeys the single-open setting. On clients without box mode these
	-- buttons do not exist and the bindings are inert.
	["SHAMANPOWER_FLYOUT_EARTH"] = "SPFT1",
	["SHAMANPOWER_FLYOUT_FIRE"] = "SPFT2",
	["SHAMANPOWER_FLYOUT_WATER"] = "SPFT3",
	["SHAMANPOWER_FLYOUT_AIR"] = "SPFT4",
	["SHAMANPOWER_FLYOUT_SHIELD"] = "SPFTS",
	["SHAMANPOWER_FLYOUT_IMBUE"] = "SPFTI",
	["SHAMANPOWER_FLYOUT_CLOSE"] = "SPFCALL",
}

-- Map cooldown bar binding names to cooldownType values
-- cooldownType: 1=Shield, 2=Recall, 3=Ankh, 4=NS, 5=MTT, 6=BL/Hero, 7=Imbue
ShamanPower.CooldownBarKeybinds = {
	["SHAMANPOWER_CD_SHIELD"] = 1,
	["SHAMANPOWER_CD_RECALL"] = 2,
	["SHAMANPOWER_CD_ANKH"] = 3,
	["SHAMANPOWER_CD_NS"] = 4,
	["SHAMANPOWER_CD_MANATIDE"] = 5,
	["SHAMANPOWER_CD_BLOODLUST"] = 6,
	["SHAMANPOWER_CD_IMBUE"] = 7,
}

-- Find a cooldown button by its cooldownType
function ShamanPower:GetCooldownButtonByCooldownType(cooldownType)
	if cooldownType == 7 then
		-- Weapon imbue button
		return self.weaponImbueButton
	end
	-- Totemic Call (cooldownType 2) - check if it's on the totem bar instead
	if cooldownType == 2 and self:CdItemOpt(2, "onTotemBar") then
		return _G["ShamanPowerAutoTotemicCall"]
	end
	if not self.cooldownButtons then return nil end
	for _, btn in ipairs(self.cooldownButtons) do
		if btn.cooldownType == cooldownType then
			return btn
		end
	end
	return nil
end

-- Create a hidden button for Totemic Call keybind
function ShamanPower:CreateTotemicCallButton()
	if _G["ShamanPowerTotemicCallBtn"] then return end

	local spellName = GetSpellInfo(36936)  -- Totemic Call
	if not spellName or not IsSpellKnown(36936) then return end

	local btn = CreateFrame("Button", "ShamanPowerTotemicCallBtn", UIParent, "SecureActionButtonTemplate")
	btn:SetSize(1, 1)
	btn:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	btn:Hide()  -- Hidden, only used for keybind
	btn:RegisterForClicks("AnyUp", "AnyDown")
	btn:SetAttribute("type1", "spell")
	btn:SetAttribute("spell1", spellName)
end

-- ============================================================================
-- Auto-updating WoW Macros
-- Creates actual WoW macros that users can drag to their action bars.
-- The addon automatically updates the macro text when assignments change.
-- ============================================================================

ShamanPower.MacroNames = {
	Earth = "SP_Earth",
	Fire = "SP_Fire",
	Water = "SP_Water",
	Air = "SP_Air",
	DropAll = "SP_DropAll",
	TotemicCall = "SP_Recall",
}

-- Migrate macro icons to ? icon (one-time migration for v1.5.4+)
function ShamanPower:MigrateMacroIcons()
	if InCombatLockdown() then return end

	-- Check if already migrated
	if self.opt and self.opt.macroIconMigrationV1 then
		return
	end

	-- Force update all macros (will use new ? icon)
	self:UpdateSPMacros()

	-- Also update Earth Shield macro if it exists
	local esIndex = GetMacroIndexByName("AC EarthShield")
	if esIndex and esIndex > 0 then
		EditMacro(esIndex, "AC EarthShield", "INV_Misc_QuestionMark", self:EarthShieldMacroBody())
	end

	-- Set migration flag
	if self.opt then
		self.opt.macroIconMigrationV1 = true
	end

	print("|cff0070ddShamanPower:|r Macro icons now match their spells.")
end

-- Migrate macro reset timers to reset=combat/15 (one-time migration for v1.5.6)
function ShamanPower:MigrateMacroResetTimers()
	if InCombatLockdown() then return end

	-- Check if already migrated
	if self.opt and self.opt.macroResetMigrationV156 then
		return
	end

	-- Force update all macros (will use new reset=combat/15)
	self:UpdateSPMacros()

	-- Set migration flag
	if self.opt then
		self.opt.macroResetMigrationV156 = true
	end

	print("|cff0070ddShamanPower:|r Macro reset timers updated (reset=combat/15).")
end

-- Create or update a WoW macro. Says what happened: "updated", "created", or "full"
-- (the character and the account macro lists are both full, so nothing was made);
-- nil in combat, where nothing is touched.
function ShamanPower:CreateOrUpdateMacro(name, icon, body)
	if InCombatLockdown() then return nil end

	local index = GetMacroIndexByName(name)
	if index > 0 then
		-- Macro exists, update it
		EditMacro(index, name, icon, body)
		return "updated"
	end
	-- Create new macro (character-specific)
	local numGlobal, numChar = GetNumMacros()
	if numChar < MAX_CHARACTER_MACROS then
		CreateMacro(name, icon, body, true)  -- true = per-character
	elseif numGlobal < MAX_ACCOUNT_MACROS then
		-- Try global macros if character slots full
		CreateMacro(name, icon, body, false)
	end
	-- made only if the game has it now
	if GetMacroIndexByName(name) > 0 then return "created" end
	return "full"
end

-- What a Create/Update Macros press really did. Returns true when every macro was
-- made or updated (the caller then says so); otherwise says which could not be made
-- and why. retry: how to try again ("type /spmacros again").
function ShamanPower:ReportMacroResult(report, retry)
	local prefix = "|cff0070ddShamanPower|r: "
	if not report then
		print(prefix .. "No macros were made: you have no totem assignments yet.")
		return false
	end
	local full = report.full or {}
	if #full == 0 then return true end
	local why = "your character and account macro lists are both full"
	local fix = ". Delete a macro you don't use (Esc > Macros), then " .. retry .. "."
	if #(report.made or {}) == 0 then
		print(prefix .. "|cffE64A4ANo macro slots available|r: " .. why .. ", so no ShamanPower macros were made" .. fix)
	else
		print(prefix .. "|cffE64A4ANo macro slots available|r for " .. table.concat(full, ", ") .. ": " .. why
			.. ". The other ShamanPower macros were made or updated" .. fix)
	end
	return false
end

-- Update all ShamanPower macros based on current assignments
function ShamanPower:UpdateSPMacros()
	if InCombatLockdown() then
		self.macroUpdatePending = true
		return
	end

	local playerName = self.player
	local assignments = ShamanPower_Assignments[playerName]
	if not assignments then return end

	local elementNames = {"Earth", "Fire", "Water", "Air"}
	-- Use ? icon so #showtooltip shows the correct spell icon dynamically
	local defaultIcon = "INV_Misc_QuestionMark"
	-- what each macro came to, for a Create/Update Macros press (ReportMacroResult)
	local report = { made = {}, full = {} }
	local function track(name, result)
		if result == "full" then report.full[#report.full + 1] = name
		elseif result then report.made[#report.made + 1] = name end
	end

	-- Create/update individual totem macros
	for element = 1, 4 do
		local macroName = self.MacroNames[elementNames[element]]
		local totemIndex = assignments[element] or 0
		local body = "#showtooltip\n/cast "
		local icon = defaultIcon  -- ? icon lets #showtooltip show correct spell

		-- Special handling for Air totem when twisting is enabled
		if element == 4 and self.opt.enableTotemTwisting then
			local wfName = GetSpellInfo(8512) or "Windfury Totem"  -- Windfury Totem
			local twistName = self:GetTwistTotemName()
			body = "#showtooltip\n/castsequence reset=combat/15 " .. wfName .. ", " .. twistName
		elseif totemIndex > 0 then
			local spellID = self:GetTotemSpell(element, totemIndex)
			if spellID then
				local spellName = GetSpellInfo(spellID)
				if SPCompat.HasTotemCastAliases(spellID) then spellName = SPCompat.TotemCastName(spellID) end
				if spellName then
					body = body .. spellName
				else
					body = body .. "-- No totem assigned"
				end
			else
				body = body .. "-- No totem assigned"
			end
		else
			body = body .. "-- No totem assigned"
		end

		track(macroName, self:CreateOrUpdateMacro(macroName, icon, body))
	end

	-- Create/update Drop All macro
	local totemSpells = {}
	local dropOrder = self.opt.dropOrder or {1, 2, 3, 4}
	-- Build exclude table for easy lookup
	local excludeTotem = {
		[1] = self.opt.excludeEarthFromDropAll,
		[2] = self.opt.excludeFireFromDropAll,
		[3] = self.opt.excludeWaterFromDropAll,
		[4] = self.opt.excludeAirFromDropAll,
	}
	for _, element in ipairs(dropOrder) do
		-- Skip if this totem type is excluded
		if not excludeTotem[element] then
			local totemIndex = assignments[element] or 0
			if totemIndex > 0 then
				local spellID = self:GetTotemSpell(element, totemIndex)
				if spellID then
					local spellName = GetSpellInfo(spellID)
					if SPCompat.HasTotemCastAliases(spellID) then spellName = SPCompat.TotemCastName(spellID) end
					if spellName then
						table.insert(totemSpells, spellName)
					end
				end
			end
		end
	end

	local dropAllBody = "#showtooltip\n"
	if #totemSpells > 0 then
		dropAllBody = dropAllBody .. "/castsequence reset=combat/15 " .. table.concat(totemSpells, ", ")
	else
		dropAllBody = dropAllBody .. "/cast -- No totems assigned"
	end
	track(self.MacroNames.DropAll, self:CreateOrUpdateMacro(self.MacroNames.DropAll, "INV_Misc_QuestionMark", dropAllBody))

	-- Create Totemic Call macro
	local tcSpellName = GetSpellInfo(36936)
	if tcSpellName then
		local tcBody = "#showtooltip\n/cast " .. tcSpellName
		track(self.MacroNames.TotemicCall, self:CreateOrUpdateMacro(self.MacroNames.TotemicCall, "INV_Misc_QuestionMark", tcBody))
	end

	self.macroUpdatePending = false
	return report
end

-- Slash command to create/refresh macros
SLASH_SPMACROS1 = "/spmacros"
SlashCmdList["SPMACROS"] = function()
	if InCombatLockdown() then
		print("ShamanPower: Cannot update macros in combat")
		return
	end
	-- say so when the macro lists are full: before, this claimed success either way
	if not ShamanPower:ReportMacroResult(ShamanPower:UpdateSPMacros(), "type /spmacros again") then return end
	print("ShamanPower: Macros updated! Look for these in your macro list:")
	print("  SP_Earth, SP_Fire, SP_Water, SP_Air - Cast assigned totem")
	print("  SP_DropAll - Cast all totems in sequence")
	print("  SP_Recall - " .. (GetSpellInfo(36936) or "Totemic Call"))
	print("Drag them to your action bar - they auto-update when you change assignments!")
end

-- ============================================================================
-- ACTION BAR KEYBIND DETECTION SYSTEM
-- Scans action bars from various addons (Bartender4, Dominos, ElvUI) to find
-- keybinds for spells, allowing ShamanPower to display keybinds on buttons
-- even when users bind spells through their action bar addon.
-- ============================================================================

-- Table to store detected action bar keybinds (keyed by spell name)
ShamanPower.actionBarKeybinds = {}

-- Detect which action bar addon is active
function ShamanPower:GetActiveActionBarAddon()
	if _G["Bartender4"] then
		return "Bartender4"
	elseif _G["Dominos"] then
		return "Dominos"
	elseif _G["ElvUI"] and _G["ElvUI"][1] and _G["ElvUI"][1].ActionBars then
		return "ElvUI"
	end
	return "Default"
end

-- Get spell name from an action slot
-- Filled by every scan: spells that sit on the bars as the plain spell, and
-- spells that are only reached through a macro. Key routing (RouteFlyoutBarKeys)
-- takes over a key only for the first kind; a macro may do something smarter
-- than a plain cast and is left alone.
ShamanPower.barPlainSpells, ShamanPower.barMacroSpells = {}, {}

local function GetSpellNameFromActionSlot(slot)
	local actionType, id, subType = GetActionInfo(slot)
	if actionType == "spell" and id then
		local spellName = GetSpellInfo(id)
		if spellName then ShamanPower.barPlainSpells[spellName] = true end
		return spellName, id
	elseif actionType == "macro" then
		-- Check if macro casts a spell we care about
		local macroSpell = GetMacroSpell(id)
		if macroSpell then
			-- The exact-key pass (ScanActionBarKeybinds, for Reactive Totems' Show
			-- Spell Keybind) passes over ShamanPower's own SP_ macros: SP_Earth or
			-- SP_DropAll cast whichever totem comes next, so their key is never
			-- the key of the one totem the macro shows right now.
			if ShamanPower.scanSkipSPMacros then
				local macroName = GetMacroInfo(id)
				if not issecretvalue(macroName) and type(macroName) == "string" and macroName:find("^SP_") then
					return nil, nil
				end
			end
			local spellName = GetSpellInfo(macroSpell)
			if spellName then ShamanPower.barMacroSpells[spellName] = true end
			return spellName, macroSpell
		end
	end
	return nil, nil
end

-- Scan Bartender4 action bars
function ShamanPower:ScanBartender4Keybinds()
	local keybinds = {}

	-- Bartender4 uses buttons named BT4Button1 through BT4Button120
	for i = 1, 120 do
		local btn = _G["BT4Button" .. i]
		if btn then
			local slot = btn:GetAttribute("action") or btn.action or i
			if slot and type(slot) == "number" and slot >= 1 and slot <= 120 then
				local spellName, spellID = GetSpellNameFromActionSlot(slot)
				if spellName and not keybinds[spellName] then
					-- Try to get keybind for this button
					local bindingString = "CLICK BT4Button" .. i .. ":LeftButton"
					local key1 = GetBindingKey(bindingString)
					if not key1 then
						-- Try alternate binding format
						bindingString = "CLICK BT4Button" .. i .. ":Keybind"
						key1 = GetBindingKey(bindingString)
					end
					if key1 then
						keybinds[spellName] = key1
					end
				end
			end
		end
	end

	return keybinds
end

-- Scan Dominos action bars
function ShamanPower:ScanDominosKeybinds()
	local keybinds = {}

	-- Dominos uses different button naming based on bar type
	-- Main action bar: ActionButton1-12
	-- Bonus bars: MultiBarBottomLeftButton, MultiBarBottomRightButton, etc.
	-- Dominos custom: DominosActionButton1-120

	-- Scan standard action buttons (slots 1-12)
	for i = 1, 12 do
		local slot = i
		local spellName, spellID = GetSpellNameFromActionSlot(slot)
		if spellName and not keybinds[spellName] then
			local key1 = GetBindingKey("ACTIONBUTTON" .. i)
			if key1 then
				keybinds[spellName] = key1
			end
		end
	end

	-- Scan MultiBar buttons (slots 13-72)
	local multiBarMappings = {
		{prefix = "MULTIACTIONBAR1BUTTON", slotOffset = 72, count = 12},  -- Right bar 1
		{prefix = "MULTIACTIONBAR2BUTTON", slotOffset = 60, count = 12},  -- Right bar 2
		{prefix = "MULTIACTIONBAR3BUTTON", slotOffset = 48, count = 12},  -- Bottom left
		{prefix = "MULTIACTIONBAR4BUTTON", slotOffset = 36, count = 12},  -- Bottom right
	}

	for _, barInfo in ipairs(multiBarMappings) do
		for i = 1, barInfo.count do
			local slot = barInfo.slotOffset + i
			local spellName, spellID = GetSpellNameFromActionSlot(slot)
			if spellName and not keybinds[spellName] then
				local key1 = GetBindingKey(barInfo.prefix .. i)
				if key1 then
					keybinds[spellName] = key1
				end
			end
		end
	end

	-- Scan Dominos-specific buttons
	for i = 1, 120 do
		local btn = _G["DominosActionButton" .. i]
		if btn then
			local slot = btn:GetAttribute("action") or i
			if slot and type(slot) == "number" and slot >= 1 and slot <= 120 then
				local spellName, spellID = GetSpellNameFromActionSlot(slot)
				if spellName and not keybinds[spellName] then
					local bindingString = "CLICK DominosActionButton" .. i .. ":LeftButton"
					local key1 = GetBindingKey(bindingString)
					if key1 then
						keybinds[spellName] = key1
					end
				end
			end
		end
	end

	return keybinds
end

-- Scan ElvUI action bars
function ShamanPower:ScanElvUIKeybinds()
	local keybinds = {}

	-- ElvUI action buttons are named ElvUI_Bar1Button1, ElvUI_Bar2Button1, etc.
	for bar = 1, 10 do
		for i = 1, 12 do
			local btnName = "ElvUI_Bar" .. bar .. "Button" .. i
			local btn = _G[btnName]
			if btn then
				local slot = btn:GetAttribute("action") or btn.action
				if slot and type(slot) == "number" and slot >= 1 and slot <= 120 then
					local spellName, spellID = GetSpellNameFromActionSlot(slot)
					if spellName and not keybinds[spellName] then
						-- ElvUI stores bindstring on buttons
						local bindstring = btn.bindstring
						if bindstring then
							local key1 = GetBindingKey(bindstring)
							if key1 then
								keybinds[spellName] = key1
							end
						end
						-- Try click binding format as fallback
						if not keybinds[spellName] then
							local bindingString = "CLICK " .. btnName .. ":LeftButton"
							local key1 = GetBindingKey(bindingString)
							if key1 then
								keybinds[spellName] = key1
							end
						end
					end
				end
			end
		end
	end

	return keybinds
end

-- Scan default WoW action bars
function ShamanPower:ScanDefaultActionBarKeybinds()
	local keybinds = {}

	-- Main action bar (slots 1-12)
	for i = 1, 12 do
		local slot = i
		local spellName, spellID = GetSpellNameFromActionSlot(slot)
		if spellName and not keybinds[spellName] then
			local key1 = GetBindingKey("ACTIONBUTTON" .. i)
			if key1 then
				keybinds[spellName] = key1
			end
		end
	end

	-- Bonus action bar / stance bar (slots 73-84 for first page, etc.)
	for i = 1, 12 do
		local slot = 72 + i
		local spellName, spellID = GetSpellNameFromActionSlot(slot)
		if spellName and not keybinds[spellName] then
			local key1 = GetBindingKey("ACTIONBUTTON" .. i)
			if key1 then
				keybinds[spellName] = key1
			end
		end
	end

	-- Bottom Left MultiBar (MultiBarBottomLeft, slots 61-72)
	for i = 1, 12 do
		local slot = 60 + i
		local spellName, spellID = GetSpellNameFromActionSlot(slot)
		if spellName and not keybinds[spellName] then
			local key1 = GetBindingKey("MULTIACTIONBAR1BUTTON" .. i)
			if key1 then
				keybinds[spellName] = key1
			end
		end
	end

	-- Bottom Right MultiBar (MultiBarBottomRight, slots 49-60)
	for i = 1, 12 do
		local slot = 48 + i
		local spellName, spellID = GetSpellNameFromActionSlot(slot)
		if spellName and not keybinds[spellName] then
			local key1 = GetBindingKey("MULTIACTIONBAR2BUTTON" .. i)
			if key1 then
				keybinds[spellName] = key1
			end
		end
	end

	-- Right MultiBar (MultiBarRight, slots 25-36)
	for i = 1, 12 do
		local slot = 24 + i
		local spellName, spellID = GetSpellNameFromActionSlot(slot)
		if spellName and not keybinds[spellName] then
			local key1 = GetBindingKey("MULTIACTIONBAR3BUTTON" .. i)
			if key1 then
				keybinds[spellName] = key1
			end
		end
	end

	-- Right MultiBar 2 (MultiBarLeft, slots 37-48)
	for i = 1, 12 do
		local slot = 36 + i
		local spellName, spellID = GetSpellNameFromActionSlot(slot)
		if spellName and not keybinds[spellName] then
			local key1 = GetBindingKey("MULTIACTIONBAR4BUTTON" .. i)
			if key1 then
				keybinds[spellName] = key1
			end
		end
	end

	return keybinds
end

-- Main function to scan all action bars and populate the keybind lookup table.
-- With Reactive Totems' Show Spell Keybind on, a second pass on the same call
-- fills actionBarExactKeybinds: each spell's key with ShamanPower's own SP_
-- macros passed over (an alert shows the key of ITS totem, never SP_Earth's or
-- SP_DropAll's). The first pass, the one the bar buttons show, stays as it was.
function ShamanPower:ScanActionBarKeybinds()
	wipe(self.barPlainSpells)
	wipe(self.barMacroSpells)
	self.scanSkipSPMacros = nil
	self.actionBarKeybinds = self:ScanActionBarKeybindsPass()
	local rt = ShamanPower_ReactiveTotems
	-- (3.0.8: each alert has its own Show Spell Keybind: any of them)
	local rtKeys = type(rt) == "table" and rt.showSpellKeybind
	if type(rt) == "table" and self.ReactiveAnyKeybind then rtKeys = self:ReactiveAnyKeybind() end
	if rtKeys then
		self.scanSkipSPMacros = true
		self.actionBarExactKeybinds = self:ScanActionBarKeybindsPass()
		self.scanSkipSPMacros = nil
	else
		self.actionBarExactKeybinds = nil
	end
end

-- One pass over the bars: [spell name] = key
function ShamanPower:ScanActionBarKeybindsPass()
	local addon = self:GetActiveActionBarAddon()
	local keybinds = {}

	-- Always scan default bars first (provides fallback)
	local defaultKeybinds = self:ScanDefaultActionBarKeybinds()
	for spell, key in pairs(defaultKeybinds) do
		keybinds[spell] = key
	end

	-- Then scan addon-specific bars (overwrites default if found)
	if addon == "Bartender4" then
		local addonKeybinds = self:ScanBartender4Keybinds()
		for spell, key in pairs(addonKeybinds) do
			keybinds[spell] = key
		end
	elseif addon == "Dominos" then
		local addonKeybinds = self:ScanDominosKeybinds()
		for spell, key in pairs(addonKeybinds) do
			keybinds[spell] = key
		end
	elseif addon == "ElvUI" then
		local addonKeybinds = self:ScanElvUIKeybinds()
		for spell, key in pairs(addonKeybinds) do
			keybinds[spell] = key
		end
	end

	return keybinds
end

-- Get keybind for a spell by name (checks action bar keybinds first)
function ShamanPower:GetKeybindForSpell(spellName)
	if not spellName then return nil end
	return self.actionBarKeybinds[spellName]
end

-- Map ShamanPower button types to their associated spell names
-- Returns the spell name that should be looked up for action bar keybinds
function ShamanPower:GetSpellNameForButton(buttonType, element)
	-- Cooldown bar buttons (cooldownType values)
	if buttonType == "shield" then
		-- Check which shield is preferred/active
		local btn = self.shieldButton
		if btn and btn.activeShieldID then
			return GetSpellInfo(btn.activeShieldID)
		end
		-- Default to Lightning Shield
		return GetSpellInfo(324)
	elseif buttonType == "recall" then
		return GetSpellInfo(36936)  -- Totemic Call
	elseif buttonType == "ankh" then
		return GetSpellInfo(20608)  -- Reincarnation
	elseif buttonType == "ns" then
		return GetSpellInfo(16188)  -- Nature's Swiftness
	elseif buttonType == "manatide" then
		return GetSpellInfo(16190)  -- Mana Tide Totem
	elseif buttonType == "bloodlust" then
		-- Check faction for Bloodlust vs Heroism
		local faction = UnitFactionGroup("player")
		if faction == "Alliance" then
			return GetSpellInfo(32182)  -- Heroism
		else
			return GetSpellInfo(2825)  -- Bloodlust
		end
	elseif buttonType == "imbue" then
		-- Get current main hand imbue spell
		local hasMain, _, _, mainID = GetWeaponEnchantInfo()
		if hasMain and self.EnchantIDToImbue and self.EnchantIDToImbue[mainID] then
			local imbueType = self.EnchantIDToImbue[mainID]
			if self.WeaponImbueSpells and self.WeaponImbueSpells[imbueType] then
				return GetSpellInfo(self.WeaponImbueSpells[imbueType])
			end
		end
		-- Fallback to last used or Windfury
		if self.lastMainHandImbue and self.WeaponImbueSpells then
			return GetSpellInfo(self.WeaponImbueSpells[self.lastMainHandImbue])
		end
		return GetSpellInfo(8232)  -- Windfury Weapon default
	elseif buttonType == "totem" and element then
		-- Get assigned totem spell for this element (a flyout pick made in this fight included)
		local totemIndex = self:AssignedIndex(element)
		if totemIndex > 0 then
			local spellID = self:GetTotemSpell(element, totemIndex)
			if spellID then
				if SPCompat.HasTotemCastAliases(spellID) then return SPCompat.TotemCastName(spellID) end
				return GetSpellInfo(spellID)
			end
		end
	elseif buttonType == "dropall" then
		-- Drop All uses a macro, but we can check for Call of the Elements or similar
		-- or just return nil since it's not a single spell
		return nil
	end

	return nil
end

-- Convert a key binding to a short display string
local function GetShortKeybindText(key)
	if not key then return nil end
	-- Make common modifiers shorter
	key = key:gsub("CTRL%-", "C-")
	key = key:gsub("ALT%-", "A-")
	key = key:gsub("SHIFT%-", "S-")
	key = key:gsub("NUMPAD", "N")
	key = key:gsub("BUTTON", "M")
	key = key:gsub("MOUSEWHEELUP", "MWU")
	key = key:gsub("MOUSEWHEELDOWN", "MWD")
	return key
end

-- Map totem bar binding names to button names
ShamanPower.TotemBarKeybinds = {
	["SHAMANPOWER_EARTH_TOTEM"] = "ShamanPowerTotemBtn1",
	["SHAMANPOWER_FIRE_TOTEM"] = "ShamanPowerTotemBtn2",
	["SHAMANPOWER_WATER_TOTEM"] = "ShamanPowerTotemBtn3",
	["SHAMANPOWER_AIR_TOTEM"] = "ShamanPowerTotemBtn4",
	["SHAMANPOWER_DROPALL"] = "ShamanPowerAutoDropAll",
}

-- Set up keybind text FontStrings on totem bar buttons (they're created in XML without keybind text)
function ShamanPower:SetupTotemBarKeybindText()
	for bindingName, buttonName in pairs(self.TotemBarKeybinds) do
		local btn = _G[buttonName]
		if btn and not btn.keybindText then
			local keybindText = btn:CreateFontString(nil, "OVERLAY")
			ShamanPower:SetSPFont(keybindText, "labels", 9, "OUTLINE", "Fonts\\ARIALN.TTF")
			keybindText:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 1, 0)
			keybindText:SetTextColor(0.9, 0.9, 0.9, 1)
			keybindText:SetText("")
			keybindText:Hide()
			btn.keybindText = keybindText
		end
	end
end

-- Map totem bar binding names to element index for action bar keybind lookup
ShamanPower.TotemBarElementMap = {
	["SHAMANPOWER_EARTH_TOTEM"] = 1,
	["SHAMANPOWER_FIRE_TOTEM"] = 2,
	["SHAMANPOWER_WATER_TOTEM"] = 3,
	["SHAMANPOWER_AIR_TOTEM"] = 4,
	["SHAMANPOWER_DROPALL"] = nil,  -- Drop All is not a single spell
}

-- Map cooldownType to button type string for action bar keybind lookup
ShamanPower.CooldownTypeToButtonType = {
	[1] = "shield",
	[2] = "recall",
	[3] = "ankh",
	[4] = "ns",
	[5] = "manatide",
	[6] = "bloodlust",
	[7] = "imbue",
}

-- Update keybind text on all buttons (totem bar + cooldown bar)
-- Priority: 1) Action bar addon keybind, 2) Default WoW action bar keybind, 3) ShamanPower binding
-- Which key a button shows (Keybind Shown, opt.keybindSource; a Discord request
-- 2026-09-29): the key from the action bars first, else ShamanPower's own binding
-- ("actionbar", the default and how it always was); ShamanPower's binding first,
-- else the action bar key ("sp"); or ShamanPower's binding only ("sponly").
-- spellName nil: the button has no spell of its own (Drop All), only its binding.
function ShamanPower:ButtonKeybindText(spellName, bindingName, element)
	local mode = self.opt.keybindSource
	local barKey, spKey
	if spellName and mode ~= "sponly" then
		local k = self:GetKeybindForSpell(spellName)
		if k then barKey = GetShortKeybindText(k) end
	end
	-- ShamanPower's key: the button's own, else the key Keybind Mode gave the flyout
	-- button that casts the same spell (the Earth button showing Earthbind shows the
	-- key set on Earthbind in the Earth flyout)
	local own = bindingName and GetBindingKey(bindingName)
	spKey = GetShortKeybindText(own or self:FlyoutSpellClickKey(spellName, element))
	if mode == "sp" or mode == "sponly" then return spKey or barKey end
	return barKey or spKey
end

-- The key Keybind Mode set on a flyout button (a CLICK binding on its cast click).
function ShamanPower:FlyoutClickKey(btn, mouse)
	local name = btn and btn:GetName()
	return name and GetBindingKey("CLICK " .. name .. ":" .. mouse) or nil
end

-- That key for the flyout button casting spellName: the element's totem flyout,
-- or (element nil) the shield and imbue flyouts.
function ShamanPower:FlyoutSpellClickKey(spellName, element)
	if not spellName then return nil end
	if element then
		local flyout = self.totemFlyouts and self.totemFlyouts[element]
		local cast = self.opt.swapFlyoutClickButtons and "RightButton" or "LeftButton"
		for _, btn in ipairs(flyout and flyout.allButtons or {}) do
			if btn.totemIndex and btn.totemIndex > 0 and btn.spellID then
				local name = GetSpellInfo(btn.spellID)
				if SPCompat.HasTotemCastAliases(btn.spellID) then name = SPCompat.TotemCastName(btn.spellID) end
				if name == spellName then return self:FlyoutClickKey(btn, cast) end
			end
		end
		return nil
	end
	for k = 1, 2 do local flyout = self[k == 1 and "shieldFlyout" or "weaponImbueFlyout"]   -- each optional flyout (ipairs over { nil, imbue } stopped at the missing shield one)
		for _, btn in ipairs(flyout and flyout.buttons or {}) do
			if (btn.spellName or (btn.spellID and GetSpellInfo(btn.spellID))) == spellName then
				return self:FlyoutClickKey(btn, "LeftButton")
			end
		end
	end
	return nil
end

function ShamanPower:UpdateButtonKeybindText()
	-- Set up totem bar keybind text if not already done
	self:SetupTotemBarKeybindText()

	-- Scan action bars for keybinds (refreshes actionBarKeybinds table)
	self:ScanActionBarKeybinds()

	if not self.opt.showButtonKeybinds then
		-- Hide all keybind text if option disabled
		-- Hide totem bar keybind text
		for _, buttonName in pairs(self.TotemBarKeybinds) do
			local btn = _G[buttonName]
			if btn and btn.keybindText then
				btn.keybindText:Hide()
			end
		end
		-- Hide cooldown bar keybind text
		if self.cooldownButtons then
			for _, btn in ipairs(self.cooldownButtons) do
				if btn.keybindText then
					btn.keybindText:Hide()
				end
			end
		end
		if self.weaponImbueButton and self.weaponImbueButton.keybindText then
			self.weaponImbueButton.keybindText:Hide()
		end
		self:UpdateFlyoutKeybindText(false)
		return
	end

	-- Update keybind text for totem bar buttons
	for bindingName, buttonName in pairs(self.TotemBarKeybinds) do
		local btn = _G[buttonName]
		if btn and btn.keybindText then
			-- the element's spell on the action bars and/or ShamanPower's own binding
			-- (ButtonKeybindText). Drop All has no spell of its own: its binding only
			-- (bound via a macro, the user would need the SP_DropAll macro on a bar).
			local element = self.TotemBarElementMap[bindingName]
			local spellName = element and self:GetSpellNameForButton("totem", element) or nil
			local keyText = self:ButtonKeybindText(spellName, bindingName, element)

			if keyText then
				btn.keybindText:SetText(keyText)
				btn.keybindText:Show()
			else
				btn.keybindText:SetText("")
				btn.keybindText:Hide()
			end
		end
	end

	-- Update keybind text for each cooldown bar button
	for bindingName, cooldownType in pairs(self.CooldownBarKeybinds) do
		local btn = self:GetCooldownButtonByCooldownType(cooldownType)
		if btn and btn.keybindText then
			local buttonType = self.CooldownTypeToButtonType[cooldownType]
			local spellName = buttonType and self:GetSpellNameForButton(buttonType) or nil
			local keyText = self:ButtonKeybindText(spellName, bindingName)

			if keyText then
				btn.keybindText:SetText(keyText)
				btn.keybindText:Show()
			else
				btn.keybindText:SetText("")
				btn.keybindText:Hide()
			end
		end
	end

	-- Update keybind text for weapon imbue button
	if self.weaponImbueButton and self.weaponImbueButton.keybindText then
		local keyText = self:ButtonKeybindText(self:GetSpellNameForButton("imbue"), "SHAMANPOWER_CD_IMBUE")

		if keyText then
			self.weaponImbueButton.keybindText:SetText(keyText)
			self.weaponImbueButton.keybindText:Show()
		else
			self.weaponImbueButton.keybindText:SetText("")
			self.weaponImbueButton.keybindText:Hide()
		end
	end

	self:UpdateFlyoutKeybindText(true)
end

-- Keybind text on the flyout icons too: each one is a specific spell, so the key
-- it is bound to on the action bars is looked up the same way as for the main
-- buttons. (There is no ShamanPower binding per flyout totem, so a spell that
-- is not on a bound bar slot simply shows nothing.)
function ShamanPower:UpdateFlyoutKeybindText(enabled)
	local function apply(btn, spellName, mouse)
		if not btn then return end
		if not btn.keybindText then
			if InCombatLockdown() then return end   -- make it after the fight; text alone is fine in combat
			-- its own frame, above the cooldown swipe (a child frame of the button)
			local holder = CreateFrame("Frame", nil, btn)
			holder:SetAllPoints(btn)
			holder:SetFrameLevel(btn:GetFrameLevel() + 4)
			local fs = holder:CreateFontString(nil, "OVERLAY")
			ShamanPower:SetSPFont(fs, "labels", 9, "OUTLINE", "Fonts\\ARIALN.TTF")
			fs:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 1, 0)
			fs:SetTextColor(0.9, 0.9, 0.9, 1)
			btn.keybindText = fs
		end
		-- the same choice as the bar buttons (Keybind Shown): the action bar key, or the
		-- key Keybind Mode set on this flyout button (a CLICK binding on its cast click)
		local text
		if enabled then
			local mode = self.opt.keybindSource
			local barKey = spellName and mode ~= "sponly" and self:GetKeybindForSpell(spellName)
			barKey = barKey and GetShortKeybindText(barKey)
			local spKey = GetShortKeybindText(self:FlyoutClickKey(btn, mouse))
			if mode == "sp" or mode == "sponly" then text = spKey or barKey else text = barKey or spKey end
		end
		if text then
			btn.keybindText:SetText(text)
			btn.keybindText:Show()
		else
			btn.keybindText:SetText("")
			btn.keybindText:Hide()
		end
	end

	local cast = self.opt.swapFlyoutClickButtons and "RightButton" or "LeftButton"   -- a totem flyout button's cast click
	for element = 1, 4 do
		local flyout = self.totemFlyouts and self.totemFlyouts[element]
		for _, btn in ipairs(flyout and flyout.allButtons or {}) do
			local name = btn.spellID and GetSpellInfo(btn.spellID)
			if SPCompat.HasTotemCastAliases(btn.spellID) then name = SPCompat.TotemCastName(btn.spellID) end
			apply(btn, name, cast)
		end
	end
	for k = 1, 2 do local flyout = self[k == 1 and "shieldFlyout" or "weaponImbueFlyout"]   -- each optional flyout (ipairs over { nil, imbue } stopped at the missing shield one)
		for _, btn in ipairs(flyout and flyout.buttons or {}) do
			apply(btn, btn.spellName or (btn.spellID and GetSpellInfo(btn.spellID)), "LeftButton")
		end
	end
end

function ShamanPower:SetupKeybindings()
	-- Can't modify bindings during combat
	if InCombatLockdown() then
		self.keybindsPending = true
		return
	end
	-- switched off: none of our bindings (hidden secure buttons still answer a key)
	if self:IsOff() then
		if self.keybindFrame then ClearOverrideBindings(self.keybindFrame) end
		self.keybindsPending = false
		return
	end
	self:ApplyClickSwap()   -- the keys below press whichever mouse button means "main action"

	-- Need a frame to own the bindings
	if not self.keybindFrame then
		self.keybindFrame = CreateFrame("Frame", "ShamanPowerKeybindFrame", UIParent)
	end

	-- Create the Totemic Call button if it doesn't exist
	self:CreateTotemicCallButton()
	if self.CreateTotemSetButtons then self:CreateTotemSetButtons() end

	-- Clear any existing override bindings
	ClearOverrideBindings(self.keybindFrame)

	-- Set up override bindings for totem bar buttons (static button names)
	for bindingName, buttonName in pairs(self.KeybindButtons) do
		local key1, key2 = GetBindingKey(bindingName)
		local mouse = self:KeyMouseButton(buttonName)
		if key1 then
			SetOverrideBindingClick(self.keybindFrame, false, key1, buttonName, mouse)
		end
		if key2 then
			SetOverrideBindingClick(self.keybindFrame, false, key2, buttonName, mouse)
		end
	end

	-- Set up override bindings for cooldown bar buttons (dynamic button lookup)
	for bindingName, cooldownType in pairs(self.CooldownBarKeybinds) do
		local btn = self:GetCooldownButtonByCooldownType(cooldownType)
		if btn then
			local buttonName = btn:GetName()
			if buttonName then
				local key1, key2 = GetBindingKey(bindingName)
				local mouse = self:KeyMouseButton(buttonName)
				if key1 then
					SetOverrideBindingClick(self.keybindFrame, false, key1, buttonName, mouse)
				end
				if key2 then
					SetOverrideBindingClick(self.keybindFrame, false, key2, buttonName, mouse)
				end
			end
		end
	end

	self.keybindsPending = false

	-- Update keybind text on buttons if enabled
	self:UpdateButtonKeybindText()

	-- (after the scan above) action bar keys for flyout spells go through the flyout
	self:RouteFlyoutBarKeys()
end

-- In combat a flyout can only be closed by a press on one of OUR secure buttons,
-- so a totem cast from the player's own action bar key left the flyout standing
-- open. With opt.flyoutRouteBarKeys (default on) the key a flyout spell has on
-- the action bars is pointed at that spell's flyout button instead: the same
-- spell is cast, and the button's macro closes the flyout as it does for a
-- click. Only for plain-spell slots (never a macro), only in box mode, and only
-- as override bindings owned by our keybind frame, so clearing them restores
-- the player's keys untouched. Hidden buttons answer binding presses, so this
-- works whether or not the flyout is open.
function ShamanPower:RouteFlyoutBarKeys()
	if InCombatLockdown() or not self.keybindFrame or self:IsOff() then return end   -- switched off: the player's keys stay theirs
	if self.opt.flyoutRouteBarKeys == false or not self.opt.showTotemFlyouts then return end
	if self.opt.flyoutCloseOnCast == false then return end   -- nothing to gain: leave the player's keys alone
	if not next(self.boxFlyouts or {}) then return end   -- not in box mode

	for key, entry in pairs(self.boxFlyouts) do
		local flyout = entry.flyout
		for _, btn in ipairs(flyout.allButtons or flyout.buttons or {}) do
			-- Shield and imbue flyouts cast on their left click, which Swap Left and
			-- Right Click turns into a right click (spFlipClicks remaps the button):
			-- press whichever one casts, or the key lands on "set as default" and
			-- casts nothing (and an imbue key would hit the off hand).
			-- A totem's button casts on the click its own layout says, never the
			-- option's: the key must never land on the assign click (a Totem Row's
			-- pull-back on WoW: Forever).
			local castButton = (btn:GetAttribute("assignButton") == "LeftButton") and "RightButton" or "LeftButton"
			local mouse = (type(key) == "number") and castButton or (btn.spClickFlipped and "RightButton" or "LeftButton")
			local name = btn.spellName or btn:GetAttribute("mySpell") or (btn.spellID and GetSpellInfo(btn.spellID))
			local bound = name and self.actionBarKeybinds and self.actionBarKeybinds[name]
			if bound and btn:GetName() and self.barPlainSpells[name] and not self.barMacroSpells[name] then
				SetOverrideBindingClick(self.keybindFrame, false, bound, btn:GetName(), mouse)
			end
		end
	end
end

-- Register for binding updates
local keybindEventFrame = CreateFrame("Frame")
keybindEventFrame:RegisterEvent("UPDATE_BINDINGS")
keybindEventFrame:RegisterEvent("PLAYER_LOGIN")
keybindEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
keybindEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
keybindEventFrame:RegisterEvent("ADDON_LOADED")
-- The key shown on a button is looked up from the action bars first, so it has
-- to follow the bars as well as the bindings: putting a spell on a bound slot,
-- taking it off, or paging the bar all change what should be shown.
keybindEventFrame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
keybindEventFrame:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
keybindEventFrame:RegisterEvent("SPELLS_CHANGED")

-- Coalesced refresh of the keybind text. Action bar events arrive in bursts
-- (dozens at login), and a spell's name can come back empty the first time it
-- is asked for, so one quick pass is followed by a second a moment later.
-- Text only, so it is safe in combat.
function ShamanPower:QueueKeybindTextRefresh()
	if self.keybindTextRefreshQueued then return end
	self.keybindTextRefreshQueued = true
	C_Timer.After(0.2, function()
		ShamanPower.keybindTextRefreshQueued = nil
		if ShamanPower.UpdateButtonKeybindText then ShamanPower:UpdateButtonKeybindText() end
	end)
	C_Timer.After(1.0, function()
		if ShamanPower.UpdateButtonKeybindText then ShamanPower:UpdateButtonKeybindText() end
	end)
end

-- Action bar addons that we want to detect for keybind scanning
local actionBarAddons = {
	["Bartender4"] = true,
	["Dominos"] = true,
	["ElvUI"] = true,
}

keybindEventFrame:SetScript("OnEvent", function(self, event, arg1)
	-- If leaving combat, check if we have pending keybind or macro setup
	if event == "PLAYER_REGEN_ENABLED" then
		-- Mid-fight totem picks are saved first, before anything else here can error:
		-- an unsaved pick leaves the bar showing it while the button goes back to the
		-- old totem. The picks are stored before any of the refreshes run.
		local pending = ShamanPower.pendingAssignments
		if pending then
			ShamanPower.pendingAssignments = nil
			ShamanPower_Assignments[ShamanPower.player] = ShamanPower_Assignments[ShamanPower.player] or {}
			for elem, totemIdx in pairs(pending) do
				ShamanPower_Assignments[ShamanPower.player][elem] = totemIdx
			end
			-- Silent save, like TotemTimers
			for elem, totemIdx in pairs(pending) do
				ShamanPower:UpdateMiniTotemBar()
				ShamanPower:UpdateDropAllButton()
				ShamanPower:UpdateSPMacros()
				ShamanPower:SendMessage("ASSIGN " .. ShamanPower.player .. " " .. elem .. " " .. totemIdx)
				ShamanPower:UpdateFlyoutVisibility(elem)
			end
		end
		-- and a shield picked in the fight (OnCombatEnd lands it too, whichever runs first)
		ShamanPower:LandPendingShield()
		if ShamanPower.keybindsPending then
			ShamanPower:SetupKeybindings()
		end
		-- Handle pending talent change from combat
		if ShamanPower.talentChangePending then
			ShamanPower.talentChangePending = false
			ShamanPower:OnTalentsChanged()
		end
		-- Dynamic Mode (and Grid): update button attributes now that we're out of combat
		if ShamanPower:DropSetsAssignment() then
			ShamanPower:UpdateMiniTotemBar()
			ShamanPower:UpdateTotemButtons()
		end
		return
	end

	-- switched off: no key text, bindings or macro migrations (switch-on sets them up)
	if ShamanPower:IsOff() then return end

	if event == "ACTIONBAR_SLOT_CHANGED" or event == "ACTIONBAR_PAGE_CHANGED" or event == "SPELLS_CHANGED" then
		if ShamanPower.opt and ShamanPower.opt.showButtonKeybinds then
			ShamanPower:QueueKeybindTextRefresh()
		end
		-- routed keys follow the bars too; bindings are secure, so defer in combat
		if ShamanPower.opt and ShamanPower.opt.flyoutRouteBarKeys ~= false and next(ShamanPower.boxFlyouts or {}) then
			if InCombatLockdown() then
				ShamanPower.keybindsPending = true
			elseif not ShamanPower.flyoutRouteQueued then
				ShamanPower.flyoutRouteQueued = true
				C_Timer.After(0.5, function()
					ShamanPower.flyoutRouteQueued = nil
					ShamanPower:SetupKeybindings()
				end)
			end
		end
		return
	end

	-- When an action bar addon loads, rescan keybinds after a delay
	if event == "ADDON_LOADED" and actionBarAddons[arg1] then
		-- Delay to allow addon to fully initialize
		C_Timer.After(1.0, function()
			if ShamanPower.UpdateButtonKeybindText then
				ShamanPower:UpdateButtonKeybindText()
			end
		end)
		return
	end

	-- When entering world, refresh action bar keybind scan
	if event == "PLAYER_ENTERING_WORLD" then
		-- Delay to allow action bars to be set up
		C_Timer.After(2.0, function()
			if ShamanPower.UpdateButtonKeybindText then
				ShamanPower:UpdateButtonKeybindText()
			end
		end)
		-- One-time migration of macro icons to ? icon (v1.5.5)
		C_Timer.After(3.0, function()
			if ShamanPower.MigrateMacroIcons then
				ShamanPower:MigrateMacroIcons()
			end
		end)
		-- One-time migration of macro reset timers to reset=combat/15 (v1.5.6)
		C_Timer.After(3.5, function()
			if ShamanPower.MigrateMacroResetTimers then
				ShamanPower:MigrateMacroResetTimers()
			end
		end)
	end

	-- Delay slightly to ensure buttons exist
	C_Timer.After(0.5, function()
		if ShamanPower.SetupKeybindings then
			ShamanPower:SetupKeybindings()
		end
	end)
end)

-- ============================================================================
-- MODULE CHECK STUBS
-- These functions provide fallbacks when optional modules are not loaded
-- Modules: ShamanPower [SPRange], ShamanPower [Raid Cooldowns],
--          ShamanPower [Raid ES Tracker], ShamanPower [Party Range],
--          ShamanPower [Shield Charge Display]
-- ============================================================================

-- Raid Cooldowns module stubs (loaded by ShamanPower_RaidCooldowns addon)
if not ShamanPower.RaidCooldownsLoaded then
	-- Provide stub functions when module not loaded
	function ShamanPower:InitRaidCooldowns() end
	function ShamanPower:ToggleRaidCooldownPanel()
		print("|cff0070ddShamanPower:|r Raid Cooldowns isn't loaded. Turn on 'ShamanPower [Raid Cooldowns]' in your AddOns list.")
	end
	function ShamanPower:UpdateCallerButtons() end
	function ShamanPower:HandleRaidCooldownMessage() end
	function ShamanPower:CallBloodlust() end
	function ShamanPower:CallManaTide() end
	function ShamanPower:RestoreCallerCooldowns() end
	-- (AddCooldownButtonAlert / RemoveCooldownButtonAlert live in this file: this
	-- block runs before the module can set its flag, so a stub here replaced them)
	function ShamanPower:EnableCallerCooldownTracking() end
	function ShamanPower:DisableCallerCooldownTracking() end
	function ShamanPower:UpdateCallerButtonOpacity() end
	function ShamanPower:UpdateCallerButtonScale() end

	-- Register /spraid slash command (shows module not loaded message)
	SLASH_SPRAID1 = "/spraid"
	SlashCmdList["SPRAID"] = function(msg)
		ShamanPower:ToggleRaidCooldownPanel()
	end
end

-- SPRange module stubs (loaded by ShamanPower_SPRange addon)
if not ShamanPower.SPRangeLoaded then
	-- Provide stub functions when module not loaded
	function ShamanPower:InitSPRange() end
	function ShamanPower:CreateSPRangeFrame() end
	function ShamanPower:ToggleSPRange()
		print("|cff0070ddShamanPower:|r Totem Range Tracker isn't loaded. Turn on 'ShamanPower [Totem Range]' in your AddOns list.")
	end
	function ShamanPower:ShowSPRangeConfig()
		print("|cff0070ddShamanPower:|r Totem Range Tracker isn't loaded. Turn on 'ShamanPower [Totem Range]' in your AddOns list.")
	end
	function ShamanPower:InitializeSPRange() end
	function ShamanPower:UpdateSPRangeVisibility() end
	function ShamanPower:UpdateSPRangeFrame() end
	function ShamanPower:UpdateSPRangeBorder() end
	function ShamanPower:UpdateSPRangeOpacity() end
	function ShamanPower:SPRangeHasWindfuryWeapon() return false end
	function ShamanPower:IsPlayerInWindfuryRange() return false end

	-- Register /sprange slash command (shows module not loaded message)
	SLASH_SPRANGE1 = "/sprange"
	SlashCmdList["SPRANGE"] = function(msg)
		ShamanPower:ToggleSPRange()
	end
end

-- Set from the compat layer rather than by the tracker module, so the settings
-- page, the setup tour and the role defaults all agree even when the tracker
-- addon is switched off in the AddOns list.
ShamanPower.ESTrackerUnavailable = (SPCompat and SPCompat.earthShieldExists == false) or nil

-- ES Tracker module stubs (loaded by ShamanPower_ESTracker addon)
-- This module tracks Earth Shields cast by OTHER shamans in your raid/party
if not ShamanPower.ESTrackerLoaded then
	-- Provide stub functions when module not loaded
	function ShamanPower:InitESTracker() end
	function ShamanPower:CreateESTrackerFrame() end
	function ShamanPower:ToggleESTracker()
		if ShamanPower.ESTrackerUnavailable then
			print("|cff0070ddShamanPower:|r Earth Shield isn't available in this version of the game. Earth Shield Tracker stays off.")
		else
			print("|cff0070ddShamanPower:|r Earth Shield Tracker isn't loaded. Turn on 'ShamanPower [Raid ES Tracker]' in your AddOns list.")
		end
	end
	function ShamanPower:InitializeESTracker() end
	function ShamanPower:UpdateESTrackerFrame() end
	function ShamanPower:UpdateESTrackerBorder() end
	function ShamanPower:UpdateESTrackerOpacity() end
	function ShamanPower:ScanEarthShields() end
	function ShamanPower:SetupESTrackerUpdater() end
	function ShamanPower:EnableESTrackerEvents() end
	function ShamanPower:DisableESTrackerEvents() end
	function ShamanPower:ClearESTracker() end
	function ShamanPower:GetClassColorForUnit() return 1, 1, 1 end
	function ShamanPower:GetClassColor() return 1, 1, 1 end

	-- Register /spestrack slash command (shows module not loaded message)
	SLASH_SPESTRACK1 = "/spestrack"
	SLASH_SPESTRACK2 = "/spearthshield"
	SlashCmdList["SPESTRACK"] = function(msg)
		ShamanPower:ToggleESTracker()
	end
end

-- Party Range module stubs (loaded by ShamanPower_PartyRange addon)
-- This module shows party members in/out of totem range via dots and counters
if not ShamanPower.PartyRangeLoaded then
	-- Provide stub functions when module not loaded
	function ShamanPower:CreatePartyRangeDots() end
	function ShamanPower:SetupPartyRangeDots() end
	function ShamanPower:UpdatePartyRangeDots() end
	function ShamanPower:GetActiveTotemBuffName() return nil end
	function ShamanPower:UnitHasBuff() return false end
	function ShamanPower:GetCachedPartyUnits() return {}, 0 end
	function ShamanPower:CreateRangeCounterText() end
	function ShamanPower:CreateRangeCounterFrame() end
	function ShamanPower:SetupRangeCounters() end
	function ShamanPower:UpdateRangeCounterLock() end
	function ShamanPower:UpdateRangeCounterFrameStyle() end
	function ShamanPower:UpdateRangeCounters() end

	-- Initialize empty tables
	ShamanPower.partyRangeDots = {}
	ShamanPower.partyUnitsCache = {}
	ShamanPower.emptyTable = {}
	ShamanPower.rangeCounterTexts = {}
	ShamanPower.rangeCounterFrames = {}
	ShamanPower.RangeCounterColors = {
		[1] = {0.2, 0.9, 0.2},
		[2] = {0.9, 0.2, 0.2},
		[3] = {0.2, 0.6, 1.0},
		[4] = {1.0, 1.0, 1.0},
	}
	ShamanPower.TotemBuffNames = {}
end

-- Shield Charges module stubs (loaded by ShamanPower_ShieldCharges addon)
-- Large on-screen numbers showing your shield charges and Earth Shield charges
if not ShamanPower.ShieldChargesLoaded then
	-- Provide stub functions when module not loaded
	function ShamanPower:CreateShieldChargeDisplays() end
	function ShamanPower:UpdateShieldChargeDisplays() end
	function ShamanPower:GetShieldChargeColor() return 1, 1, 1 end

	-- Initialize empty table
	ShamanPower.shieldChargeFrames = {}
end

-- Totem Plates module stubs (loaded by ShamanPower_TotemPlates addon)
-- Replaces totem nameplates with clean, recognizable icons
if not ShamanPower.TotemPlatesLoaded then
	-- Provide stub functions when module not loaded
	function ShamanPower:InitializeTotemPlates() end
	function ShamanPower:ToggleTotemPlates()
		print("|cff0070ddShamanPower:|r Totem Plates isn't loaded. Turn on 'ShamanPower [Totem Plates]' in your AddOns list.")
	end
	function ShamanPower:UpdateTotemPlatesSize() end
	function ShamanPower:UpdateTotemPlatesPulseSettings() end
	function ShamanPower:DetectNameplateAddon() end

	-- Initialize empty tables
	ShamanPower.activeTotemPlates = {}
	ShamanPower.totemPlateCache = {}
	ShamanPower.detectedNameplateAddon = "Blizzard"
end

-- Reactive Totems module stubs (loaded by ShamanPower_ReactiveTotems addon)
-- Shows large totem icons when party members have fear, disease, or poison debuffs
if not ShamanPower.ReactiveTotemsLoaded then
	-- Provide stub functions when module not loaded
	function ShamanPower:InitializeReactiveTotems() end
	function ShamanPower:UpdateReactiveTotems() end
	function ShamanPower:UpdateReactiveTotemAppearance() end
	function ShamanPower:TestReactiveTotems() end
	function ShamanPower:ResetReactiveTotemPositions() end
	function ShamanPower:ShowAllReactiveFrames() end
	function ShamanPower:HideAllReactiveFrames() end
	function ShamanPower:ShowReactiveTotemsConfig()
		print("|cff0070ddShamanPower:|r Reactive Totems isn't loaded. Turn on 'ShamanPower [Reactive Totems]' in your AddOns list.")
	end

	-- Register slash commands (shows module not loaded message)
	SLASH_SPREACTIVE1 = "/spreactive"
	SLASH_SPREACTIVE2 = "/reactivetotem"
	SlashCmdList["SPREACTIVE"] = function(msg)
		ShamanPower:ShowReactiveTotemsConfig()
	end
end

-- NOTE: The actual implementations of these functions are in:
-- - ShamanPower_RaidCooldowns/ShamanPower_RaidCooldowns.lua
-- - ShamanPower_SPRange/ShamanPower_SPRange.lua
-- - ShamanPower_ESTracker/ShamanPower_ESTracker.lua
-- - ShamanPower_PartyRange/ShamanPower_PartyRange.lua
-- - ShamanPower_ShieldCharges/ShamanPower_ShieldCharges.lua
-- - ShamanPower_TotemPlates/ShamanPower_TotemPlates.lua
-- - ShamanPower_ReactiveTotems/ShamanPower_ReactiveTotems.lua
-- - ShamanPower_ExpiringAlerts/ShamanPower_ExpiringAlerts.lua
-- When those modules are loaded, they override these stub functions.

-- Expiring Alerts module stubs (loaded by ShamanPower_ExpiringAlerts addon)
-- Shows scrolling combat text alerts when shields, totems, or weapon imbues expire
if not ShamanPower.ExpiringAlertsLoaded then
	-- Provide stub functions when module not loaded
	function ShamanPower:InitExpiringAlerts() end
	function ShamanPower:ExpiringAlertsUpdate() end
	function ShamanPower:ExpiringAlertsTest() end
	function ShamanPower:ExpiringAlertsReset() end
	function ShamanPower:ExpiringAlertsShow() end
	function ShamanPower:ExpiringAlertsHide() end
	function ShamanPower:UpdateExpiringAlertsAppearance() end

	-- Register slash commands (shows module not loaded message)
	SLASH_SPALERTS1 = "/spalerts"
	SLASH_SPALERTS2 = "/expiringalerts"
	SlashCmdList["SPALERTS"] = function(msg)
		print("|cff0070ddShamanPower:|r Expiring Alerts isn't loaded. Turn on 'ShamanPower [Expiring Alerts]' in your AddOns list.")
	end
end

-- Stub functions for TremorReminder module (when not loaded)
if not ShamanPower.TremorReminderLoaded then
	function ShamanPower:TremorReminderShow() end
	function ShamanPower:TremorReminderHide() end
	function ShamanPower:TremorReminderTest() end
	function ShamanPower:TremorReminderReset() end
	function ShamanPower:UpdateTremorReminderAppearance() end
	function ShamanPower:GetDefaultFearCasters() return {} end
	function ShamanPower:GetCustomFearCasters() return {} end
	function ShamanPower:ShowMobList() end
	function ShamanPower:HideMobList() end
	function ShamanPower:ToggleMobList() end
	function ShamanPower:RefreshMobList() end

	SLASH_SPTREMOR1 = "/sptremor"
	SlashCmdList["SPTREMOR"] = function(msg)
		print("|cff0070ddShamanPower:|r Tremor Reminder isn't loaded. Turn on 'ShamanPower [Tremor Reminder]' in your AddOns list.")
	end
end

-- ============================================================================
-- SPCenter: totem bar to the centre of the screen, cooldown bar straight under it
-- ============================================================================

SLASH_SPCENTER1 = "/spcenter"
SlashCmdList["SPCENTER"] = function(msg)
	if InCombatLockdown() then
		print("|cff0070ddShamanPower:|r Cannot move the bars during combat.")
		return
	end

	-- A rescue for bars lost off screen: the visible totem bar is saved dead centre
	-- (a real saved spot, so it holds after /reload) and the cooldown bar drops its
	-- own spot, so it sits straight under the totem bar and follows it.
	local SP = ShamanPower
	SP:EnsureProfileTable("display")
	local d = SP.opt.display
	d.offsetX, d.offsetY = nil, nil
	SP.opt.cooldownBarPosition = nil
	SP.opt.cooldownBarPoint, SP.opt.cooldownBarRelPoint = nil, nil
	SP.opt.cooldownBarPosX, SP.opt.cooldownBarPosY = nil, nil

	-- Make sure bars are visible
	if SP.autoButton and SP:TotemBarEnabled() then
		SP.autoButton:Show()
	end

	-- Lay the bar out first: where its centre sits depends on its size and layout
	SP:UpdateLayout()
	SP:UpdateRoster()
	local mainFrame = _G["ShamanPowerFrame"]
	if mainFrame and SP.autoButton then
		local dx, dy = SP:TotemBarGeometry()
		local rec = { anchor = "CENTER", x = -dx, y = -dy }
		SP:SetStyleSpot(d, SP:BarStyleSpotKey(), rec)
		SP:ApplyPositionRecord(mainFrame, rec)
		print("|cff0070ddShamanPower:|r Totem Bar moved to the center of the screen.")
		-- the hide rules keep it down (SetTotemBarFramesShown): say so, or it looks lost still
		if SP.totemBarHidden then
			print("|cff0070ddShamanPower:|r The Totem Bar is hidden right now by Hide Out of Combat or Hide When No Totems. It shows there when those settings allow it.")
		end
	end
	if SP.cooldownBar and SP.opt.showCooldownBar then
		SP:UpdateCooldownBarPosition(true)   -- detaches a bar still on the totem bar
		print("|cff0070ddShamanPower:|r Cooldown Bar moved under it.")
	end
	SP:ApplyDefaultBarPositions()

	print("|cff0070ddShamanPower:|r Move them with /sp unlock (or ALT+drag). Unlock UI > Reset restores their starting positions.")
end

-- ============================================================================
-- TOTEM LOADOUTS: Save/load personal 4-element totem assignments
-- ============================================================================

-- A loadout carries its own Drop All excludes (noDropAll[element] = true: left out of Drop All
-- and Call of the Elements). Switching to it swaps them in, and ticking an exclude while it is
-- the active loadout saves into it. A loadout saved before this has no noDropAll: switching to
-- it leaves the current excludes alone until one of its own is set.
ShamanPower.DropAllExcludeKeys = { "excludeEarthFromDropAll", "excludeFireFromDropAll", "excludeWaterFromDropAll", "excludeAirFromDropAll" }

function ShamanPower:CurrentDropAllExcludes()
	local t = {}
	for e, key in ipairs(self.DropAllExcludeKeys) do t[e] = self.opt[key] and true or false end
	return t
end

-- whether a loadout leaves an element out (its own setting, or the current one if it has none)
function ShamanPower:LoadoutExcluded(index, element)
	local lo = ShamanPower_TotemLoadouts and ShamanPower_TotemLoadouts[index]
	if lo and lo.noDropAll then return lo.noDropAll[element] and true or false end
	return self.opt[self.DropAllExcludeKeys[element]] and true or false
end

-- Set one element's exclude. index nil or the active loadout: the live setting changes (and the
-- active loadout keeps it); another index: only that loadout's copy, used when it is switched to.
function ShamanPower:SetDropAllExclude(element, val, index)
	val = val and true or false
	local active = self.opt.activeLoadout
	local target = index or active
	local lo = target and ShamanPower_TotemLoadouts and ShamanPower_TotemLoadouts[target]
	if lo then
		lo.noDropAll = lo.noDropAll or self:CurrentDropAllExcludes()
		lo.noDropAll[element] = val
	end
	if index == nil or index == active then
		self.opt[self.DropAllExcludeKeys[element]] = val
		self:UpdateDropAllButton()
		self:UpdateSPMacros()
	end
end

function ShamanPower:SaveLoadout(name)
	if #ShamanPower_TotemLoadouts >= 8 then
		print("|cff0070ddShamanPower:|r Maximum of 8 loadouts reached.")
		return
	end
	local assignments = ShamanPower_Assignments[self.player]
	if not assignments then return end
	local loadout = { name = name or nil, noDropAll = self:CurrentDropAllExcludes() }
	for element = 1, 4 do
		loadout[element] = assignments[element] or 0
	end
	tinsert(ShamanPower_TotemLoadouts, loadout)
	-- Auto-enable the bar when first loadout is saved
	if #ShamanPower_TotemLoadouts == 1 then
		self.opt.showLoadoutBar = true
	end
	self:UpdateLoadoutBar()
	print("|cff0070ddShamanPower:|r Saved loadout '" .. (name or ("Loadout " .. #ShamanPower_TotemLoadouts)) .. "'")
end

function ShamanPower:CreateLoadout(name, icon, totems)
	if #ShamanPower_TotemLoadouts >= 8 then
		print("|cff0070ddShamanPower:|r Maximum of 8 loadouts reached.")
		return
	end
	local loadout = { name = name or nil, icon = icon or nil, noDropAll = self:CurrentDropAllExcludes() }
	for element = 1, 4 do
		loadout[element] = (totems and totems[element]) or 0
	end
	tinsert(ShamanPower_TotemLoadouts, loadout)
	local newIndex = #ShamanPower_TotemLoadouts
	if newIndex == 1 then
		self.opt.showLoadoutBar = true
	end
	-- Auto-activate the newly created loadout
	self:ApplyLoadout(newIndex)
	print("|cff0070ddShamanPower:|r Created loadout '" .. (name or ("Loadout " .. newIndex)) .. "'")
end

-- quiet: the caller prints its own line (loadout auto-switch)
function ShamanPower:ApplyLoadout(index, quiet)
	if InCombatLockdown() then
		print("|cff0070ddShamanPower:|r Cannot change loadout in combat")
		return
	end
	local loadout = ShamanPower_TotemLoadouts[index]
	if not loadout then return end
	local assignments = ShamanPower_Assignments[self.player]
	if not assignments then
		ShamanPower_Assignments[self.player] = {}
		assignments = ShamanPower_Assignments[self.player]
	end
	for element = 1, 4 do
		assignments[element] = loadout[element] or 0
	end
	if loadout.noDropAll then
		for e, key in ipairs(self.DropAllExcludeKeys) do self.opt[key] = loadout.noDropAll[e] and true or false end
	end
	self.opt.activeLoadout = index
	self:UpdateMiniTotemBar()
	self:UpdateDropAllButton()   -- Drop All and Call of the Elements follow the new totems and excludes
	self:UpdateSPMacros()
	self:UpdateLoadoutBar()
	-- the flyouts re-sorted around the new totems, as a single flyout pick does
	-- (ApplyAssignment); without it the first hover after a switch showed the old
	-- layout, with gaps where the previous totems had been left out
	for element = 1, 4 do
		self:UpdateFlyoutVisibility(element)
		if self.ShowEmptySlotArt then self:ShowEmptySlotArt(element, (assignments[element] or 0) == 0) end
	end
	-- Broadcast assignments to other ShamanPower clients
	for element = 1, 4 do
		self:SendMessage("ASSIGN " .. self.player .. " " .. element .. " " .. (assignments[element] or 0))
	end
	local name = loadout.name or ("Loadout " .. index)
	if not quiet then print("|cff0070ddShamanPower:|r Activated '" .. name .. "'") end
	LibStub("AceConfigRegistry-3.0"):NotifyChange("ShamanPower")
end

function ShamanPower:DeleteLoadout(index)
	if not ShamanPower_TotemLoadouts[index] then return end
	tremove(ShamanPower_TotemLoadouts, index)
	if self.opt.activeLoadout == index then
		self.opt.activeLoadout = nil
	elseif self.opt.activeLoadout and self.opt.activeLoadout > index then
		self.opt.activeLoadout = self.opt.activeLoadout - 1
	end
	self:UpdateLoadoutBar()
end

function ShamanPower:UpdateLoadout(index)
	local loadout = ShamanPower_TotemLoadouts[index]
	if not loadout then return end
	local assignments = ShamanPower_Assignments[self.player]
	if not assignments then return end
	for element = 1, 4 do
		loadout[element] = assignments[element] or 0
	end
	loadout.noDropAll = self:CurrentDropAllExcludes()
	if self.HasTotemBar and self:HasTotemBar() and self.SyncBoundLoadout then self:SyncBoundLoadout(index) end
	self:UpdateLoadoutBar()
end

function ShamanPower:RenameLoadout(index, newName)
	local loadout = ShamanPower_TotemLoadouts[index]
	if not loadout then return end
	loadout.name = newName
	self:UpdateLoadoutBar()
end

-- Set a specific totem for an element within a loadout
function ShamanPower:SetLoadoutTotem(index, element, totemIdx)
	local loadout = ShamanPower_TotemLoadouts[index]
	if not loadout then return end
	loadout[element] = totemIdx
	if self.HasTotemBar and self:HasTotemBar() and self.SyncBoundLoadout then self:SyncBoundLoadout(index) end
	self:UpdateLoadoutBar()
end

-- Set a custom icon for a loadout (nil to clear and use default 4 mini icons)
function ShamanPower:SetLoadoutIcon(index, iconPath)
	local loadout = ShamanPower_TotemLoadouts[index]
	if not loadout then return end
	loadout.icon = iconPath
	self:UpdateLoadoutBar()
end

-- Get the display icon for a loadout (same as TotemTimers.GetLoadoutIcon):
-- Custom icon > first totem's icon > default shaman icon
function ShamanPower:GetLoadoutIcon(index)
	local loadout = ShamanPower_TotemLoadouts[index]
	if not loadout then return "Interface\\Icons\\ClassIcon_Shaman" end
	-- Custom icon set by user
	if loadout.icon then return loadout.icon end
	-- Fallback: first non-zero totem's icon
	for element = 1, 4 do
		local totemIdx = loadout[element] or 0
		if totemIdx > 0 then
			return self:GetTotemIcon(element, totemIdx)
		end
	end
	return "Interface\\Icons\\ClassIcon_Shaman"
end

-- Element color codes for loadout descriptions (matches TotemTimers ElementColors)
local loadoutElementColors = {
	[1] = "|cffb3804d",  -- Earth - brown (0.7, 0.5, 0.3)
	[2] = "|cffff1a1a",  -- Fire - red (1.0, 0.1, 0.1)
	[3] = "|cff6666ff",  -- Water - blue (0.4, 0.4, 1.0)
	[4] = "|cffffffff",  -- Air - white (1.0, 1.0, 1.0)
}

-- Get a description string of the 4 totems in a loadout (color-coded)
function ShamanPower:GetLoadoutDescription(index)
	local loadout = ShamanPower_TotemLoadouts[index]
	if not loadout then return "" end
	local parts = {}
	for element = 1, 4 do
		local totemIdx = loadout[element] or 0
		local color = loadoutElementColors[element]
		color = self:ThemeLoadoutTipColor(element) or color   -- General > Themes (lo.tooltip); nil = the code above
		if totemIdx > 0 then
			local name = self:GetTotemName(element, totemIdx)
			local out = self:LoadoutExcluded(index, element) and " |cff888888(not in Drop All)|r" or ""
			tinsert(parts, color .. name .. "|r" .. out)
		else
			tinsert(parts, color .. "None|r")
		end
	end
	return table.concat(parts, ", ")
end

-- Get a plain (no color) description string for chat output
function ShamanPower:GetLoadoutDescriptionPlain(index)
	local loadout = ShamanPower_TotemLoadouts[index]
	if not loadout then return "" end
	local parts = {}
	local elementNames = {"E", "F", "W", "A"}
	for element = 1, 4 do
		local totemIdx = loadout[element] or 0
		if totemIdx > 0 then
			local name = self:GetTotemName(element, totemIdx)
			tinsert(parts, elementNames[element] .. ": " .. name)
		else
			tinsert(parts, elementNames[element] .. ": None")
		end
	end
	return table.concat(parts, "  |  ")
end

-- ============================================================================
-- LOADOUT BAR: TotemTimers-style set buttons around a movable anchor
-- ============================================================================

-- Radial button positions around anchor (same as TotemTimers buttonlocations)
-- The flyout is one column over the button (under it when the button sits in the top half of
-- the screen), each name to its right: a ring put every name on the next button. The side is
-- read from the saved spot, never off the frame.
function ShamanPower:LoadoutFlyoutOpensDown()
	local pos = self.opt.loadoutBarPosition
	if not pos then return false end
	local a = pos.anchor or pos.relPoint or pos.point or "CENTER"
	if a:find("TOP") then return true end
	if a:find("BOTTOM") then return false end
	return (pos.y or 0) > 0
end

-- Element colors for tooltips (matches TotemTimers: Fire, Earth, Water, Air by totem slot)
-- ShamanPower uses: 1=Earth, 2=Fire, 3=Water, 4=Air
local loadoutTooltipColors = {
	[1] = {r = 0.7, g = 0.5, b = 0.3},  -- Earth (brown)
	[2] = {r = 1.0, g = 0.1, b = 0.1},  -- Fire (red/orange)
	[3] = {r = 0.4, g = 0.4, b = 1.0},  -- Water (blue)
	[4] = {r = 1.0, g = 1.0, b = 1.0},  -- Air (white)
}

-- Delete set confirmation (Settings > Loadouts > Delete)
function ShamanPower:ConfirmDeleteLoadout(nr, name)
	self:ShowSPDialog({
		key = "deleteLoadout", title = "Delete totem set", text = "Delete totem set " .. tostring(name) .. "?",
		buttons = {
			{ text = "Delete", onClick = function()
				-- combat began while it was open: say so, and keep the question up for after the fight
				if InCombatLockdown() then
					print("|cff0070ddShamanPower|r: |cffe64a4atotem sets cannot be deleted in combat - click Delete again after the fight.|r")
					return true
				end
				ShamanPower:DeleteLoadout(nr)
				if ShamanPower.RefreshLoadoutArgs then ShamanPower:RefreshLoadoutArgs() end
				ShamanPower:RefreshConfig()
			end },
			{ text = "Cancel" },
		},
	})
end

function ShamanPower:CreateLoadoutBar()
	if self.loadoutBarCreated then return end
	self.loadoutBarCreated = true

	-- Anchor button: SecureHandlerEnterLeaveTemplate so hover shows flyout in combat
	-- Same pattern as totem buttons: _onenter shows, _onleave hides
	local anchor = CreateFrame("Button", "ShamanPowerSetAnchor", UIParent,
		"SecureHandlerEnterLeaveTemplate, SecureHandlerBaseTemplate")
	anchor:SetSize(32, 32)
	anchor:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
	anchor:SetFrameStrata("MEDIUM")
	anchor:SetClampedToScreen(true)
	anchor:SetMovable(true)
	-- The client's layout cache remembered where an ALT-drag once left this
	-- named frame and put it back there after every reload, on top of the
	-- position the addon saved: the bar sat behind action bars whatever was
	-- saved, and the move box appeared at the saved spot instead. Never let the
	-- client place it.
	anchor:SetUserPlaced(false)
	if anchor.SetDontSavePosition then anchor:SetDontSavePosition(true) end
	anchor:EnableMouse(true)
	anchor:RegisterForDrag("LeftButton")
	-- With "Click the Button to Cycle Loadouts" on (off by default: the flyout is
	-- the way), clicking the button itself steps through the loadouts (left: next,
	-- right: previous). Out of combat, as ApplyLoadout is.
	anchor:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	anchor:SetScript("OnClick", function(_, button)
		if not ShamanPower.opt.loadoutBarClickCycle then return end
		if IsAltKeyDown() then return end   -- ALT is for moving it
		local n = ShamanPower_TotemLoadouts and #ShamanPower_TotemLoadouts or 0
		if n < 2 then return end
		local cur = ShamanPower.opt.activeLoadout or 0
		ShamanPower:ApplyLoadout(button == "RightButton" and ((cur - 2) % n) + 1 or (cur % n) + 1)
	end)
	self.loadoutAnchor = anchor

	-- SECURE HANDLER: Show flyout on hover (WORKS IN COMBAT)
	-- Same pattern as totem button _onenter/_onleave
	ShamanPower:SetSnippet(anchor, "_onenter", [[
		if self:GetAttribute("spnoflyout") then return end   -- Turn Off the Flyout (plain name: snippets cannot read "_" ones)
		self:ChildUpdate("show", true)
	]])

	ShamanPower:SetSnippet(anchor, "_onleave", SP_SECURE_ONLEAVE_SELF)
	-- the plain-script fallback (Forever, where snippets do not run) opens a flyout only
	-- for a host marked mouseover, as the totem buttons are; without it hovering did nothing
	anchor:SetAttribute("OpenMenu", "mouseover")

	-- Anchor normal texture (standard WoW action button look)
	local normalTex = anchor:CreateTexture(nil, "BORDER")
	normalTex:SetTexture("Interface\\Buttons\\UI-Quickslot2")
	normalTex:SetSize(52, 52)
	normalTex:SetPoint("CENTER", 0, -1)
	anchor.normalTex = normalTex

	-- Anchor icon (shows class icon by default)
	local icon = anchor:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	icon:SetTexture("Interface\\Icons\\ClassIcon_Shaman")
	anchor.icon = icon

	-- Highlight texture
	local hlTex = anchor:CreateTexture(nil, "HIGHLIGHT")
	hlTex:SetAllPoints()
	hlTex:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
	hlTex:SetBlendMode("ADD")

	-- 4 mini totem icons in corners on anchor (13x13, TotemTimers style)
	anchor.miniIcons = {}
	local anchorPositions = {
		{point = "TOPLEFT", x = 3, y = -3},
		{point = "TOPRIGHT", x = -3, y = -3},
		{point = "BOTTOMLEFT", x = 3, y = 3},
		{point = "BOTTOMRIGHT", x = -3, y = 3},
	}
	for e = 1, 4 do
		local miniIcon = anchor:CreateTexture(nil, "OVERLAY")
		miniIcon:SetSize(13, 13)
		miniIcon:SetPoint(anchorPositions[e].point, anchorPositions[e].x, anchorPositions[e].y)
		miniIcon:SetTexture(self:GetTotemIcon(e, 0))
		miniIcon:Hide()
		anchor.miniIcons[e] = miniIcon
	end

	-- Name label to the right of anchor
	local anchorName = anchor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmallOutline")
	ShamanPower:AdoptSPFont(anchorName, "labels")   -- template font = the design; follows the Fonts settings
	anchorName:SetPoint("LEFT", anchor, "RIGHT", 4, 0)
	anchorName:SetText("")
	anchorName:SetJustifyH("LEFT")
	anchor.nameText = anchorName

	-- Anchor drag (ALT+drag to move)
	anchor:SetScript("OnDragStart", function(btn)
		if self.opt.loadoutBarLocked then return end
		if InCombatLockdown() then
			print("|cff0070ddShamanPower:|r Cannot move loadout bar during combat")
			return
		end
		if IsAltKeyDown() then
			anchor:StartMoving()
			anchor.isMoving = true
		end
	end)
	anchor:SetScript("OnDragStop", function(btn)
		if anchor.isMoving then
			anchor:StopMovingOrSizing()
			anchor:SetUserPlaced(false)
			anchor.isMoving = false
			self:SaveLoadoutBarPosition()
		end
	end)

	-- Anchor tooltip (HookScript so secure _onenter/_onleave still fires)
	anchor:HookScript("OnEnter", function(btn)
		if not ShamanPower.opt.ShowTooltips then return end
		GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Totem Sets", 1, 1, 1)
		if self.opt.activeLoadout and ShamanPower_TotemLoadouts[self.opt.activeLoadout] then
			local lo = ShamanPower_TotemLoadouts[self.opt.activeLoadout]
			GameTooltip:AddLine("Active: " .. (lo.name or ("Set " .. self.opt.activeLoadout)), 0.3, 1.0, 0.3)
		end
		if ShamanPower.opt.loadoutBarClickCycle and #ShamanPower_TotemLoadouts > 1 then
			GameTooltip:AddLine("Left-click: next loadout. Right-click: previous.", 0.8, 0.8, 0.8)
		end
		if not self.opt.loadoutBarLocked then
			GameTooltip:AddLine("ALT+Drag to move", 0, 0.9, 1)
		end
		GameTooltip:Show()
	end)
	anchor:HookScript("OnLeave", function(btn)
		GameTooltip:Hide()
	end)

	-- Pre-create 8 set buttons as CHILDREN of anchor (required for ChildUpdate to work)
	self.loadoutButtons = {}
	local hasTotemBar = self.HasTotemBar and self:HasTotemBar()
	local buttonTemplates = "SecureHandlerShowHideTemplate, SecureHandlerEnterLeaveTemplate"
	if hasTotemBar then buttonTemplates = "SecureActionButtonTemplate, " .. buttonTemplates end
	for i = 1, 8 do
		local btn = CreateFrame("Button", "ShamanPowerSetButton" .. i, anchor,
			buttonTemplates)
		btn:SetSize(32, 32)
		btn:SetClampedToScreen(true)
		btn:EnableMouse(true)
		if hasTotemBar then btn:RegisterForClicks("AnyUp", "AnyDown")
		else btn:RegisterForClicks("LeftButtonUp") end
		btn:SetFrameStrata("HIGH")

		-- SECURE HANDLER: Hide flyout when mouse leaves set button (if not over parent anchor)
		-- Same pattern as totem flyout _onleave
		ShamanPower:SetSnippet(btn, "_onleave", SP_SECURE_ONLEAVE_PARENT)
		btn:SetAttribute("spFlyoutProtocol", true)  -- lets sibling leave snippets tell flyout buttons from decoration

		-- SECURE HANDLER: Toggle visibility on parent ChildUpdate("toggle")
		-- Same as TotemTimers: _childupdate-toggle
		ShamanPower:SetSnippet(btn, "_childupdate-toggle", [[
			if not self:GetAttribute("inactive") then
				if self:IsVisible() then
					self:Hide()
				else
					self:Show()
				end
			end
		]])

		-- SECURE HANDLER: Show/hide on parent ChildUpdate("show", bool)
		-- Same as TotemTimers: _childupdate-show
		ShamanPower:SetSnippet(btn, "_childupdate-show", [[
			if message and not self:GetAttribute("inactive") then
				self:Show()
			else
				self:Hide()
			end
		]])

		-- Normal texture (standard WoW action button)
		local btnNormal = btn:CreateTexture(nil, "BORDER")
		btnNormal:SetTexture("Interface\\Buttons\\UI-Quickslot2")
		btnNormal:SetSize(52, 52)
		btnNormal:SetPoint("CENTER", 0, -1)
		btn.normalTex = btnNormal

		-- Button background icon
		local btnIcon = btn:CreateTexture(nil, "ARTWORK")
		btnIcon:SetAllPoints()
		btnIcon:SetTexture(nil)
		btn.icon = btnIcon

		-- Highlight
		local btnHL = btn:CreateTexture(nil, "HIGHLIGHT")
		btnHL:SetAllPoints()
		btnHL:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
		btnHL:SetBlendMode("ADD")

		-- 4 mini totem icons in corners (13x13, same as TotemTimers)
		btn.miniIcons = {}
		local positions = {
			{point = "TOPLEFT", x = 3, y = -3},
			{point = "TOPRIGHT", x = -3, y = -3},
			{point = "BOTTOMLEFT", x = 3, y = 3},
			{point = "BOTTOMRIGHT", x = -3, y = 3},
		}
		for e = 1, 4 do
			local miniIcon = btn:CreateTexture(nil, "OVERLAY")
			miniIcon:SetSize(13, 13)
			miniIcon:SetPoint(positions[e].point, positions[e].x, positions[e].y)
			miniIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
			btn.miniIcons[e] = miniIcon
		end

		-- Name label to the right of button
		local nameText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmallOutline")
		ShamanPower:AdoptSPFont(nameText, "labels")   -- template font = the design; follows the Fonts settings
		nameText:SetPoint("LEFT", btn, "RIGHT", 4, 0)
		nameText:SetText("")
		nameText:SetJustifyH("LEFT")
		btn.nameText = nameText

		btn.nr = i

		-- Keep the secure template's OnClick for bound summons. Unbound buttons
		-- still select assignments on release; Classic retains its old OnClick.
		btn:SetScript(hasTotemBar and "PostClick" or "OnClick", function(buttonFrame, button, down)
			if hasTotemBar and (down or buttonFrame:GetAttribute("spBoundLoadout")) then return end
			if button == "LeftButton" then
				if InCombatLockdown() then
					print("|cff0070ddShamanPower:|r Cannot change loadout during combat")
					return
				end
				local index = buttonFrame:GetAttribute("loadoutIndex")
				ShamanPower:ApplyLoadout(index)
				-- Close flyout (ApplyLoadout calls UpdateLoadoutBar which reconfigures buttons,
				-- but doesn't hide the open flyout — do it explicitly)
				ShamanPower:HideLoadoutMenu()
			end
		end)

		-- Tooltip (HookScript so secure _onleave still fires)
		btn:HookScript("OnEnter", function(self)
			if not ShamanPower.opt.ShowTooltips then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			local set = ShamanPower_TotemLoadouts[self.nr]
			if set then
				GameTooltip:AddLine(set.name or ("Set " .. self.nr), 1, 1, 1)
				for element = 1, 4 do
					local totemIdx = set[element] or 0
					local color = loadoutTooltipColors[element]
					if totemIdx > 0 then
						GameTooltip:AddLine(ShamanPower:GetTotemName(element, totemIdx), color.r, color.g, color.b)
					else
						GameTooltip:AddLine("None", color.r, color.g, color.b)
					end
				end
				GameTooltip:AddLine(" ")
			end
			local summon = ShamanPower.BoundLoadoutSummon and ShamanPower:BoundLoadoutSummon(self.nr)
			if summon then GameTooltip:AddLine("Click to cast this Blizzard totem set", 0, 0.9, 1)
			else GameTooltip:AddLine("Left-click to load totem set", 0, 0.9, 1) end
			GameTooltip:Show()
		end)
		btn:HookScript("OnLeave", function(self)
			GameTooltip:Hide()
		end)

		-- Start hidden and marked inactive (UpdateLoadoutBar will activate populated ones)
		btn:SetAttribute("inactive", true)
		btn:Hide()
		self.loadoutButtons[i] = btn
	end

	-- Restore position
	self:RestoreLoadoutBarPosition()
end

function ShamanPower:UpdateLoadoutBar()
	if not self.loadoutBarCreated then return end
	-- Anchor is a secure frame - can't touch it in combat
	if InCombatLockdown() then
		self.pendingLoadoutBarUpdate = true
		return
	end

	local numLoadouts = #ShamanPower_TotemLoadouts

	-- Show/hide anchor (need loadouts AND setting enabled)
	if not self.opt.showLoadoutBar or numLoadouts == 0 or self:IsOff() then
		if self.HasTotemBar and self:HasTotemBar() then
			for _, button in ipairs(self.loadoutButtons) do
				button:SetAttribute("type", nil)
				button:SetAttribute("spell", nil)
				button:SetAttribute("spBoundLoadout", nil)
				button:SetAttribute("inactive", true)
			end
		end
		if not InCombatLockdown() then
			self.loadoutAnchor:Hide()
		end
		return
	end

	if not InCombatLockdown() then
		self.loadoutAnchor:Show()
		-- "Turn Off the Flyout" (only with click-to-cycle on): neither hover path opens it,
		-- the secure snippet (spnoflyout) nor the Forever fallback (OpenMenu)
		local noFlyout = self.opt.loadoutBarClickCycle and self.opt.loadoutBarNoFlyout
		self.loadoutAnchor:SetAttribute("spnoflyout", noFlyout or nil)
		self.loadoutAnchor:SetAttribute("OpenMenu", (not noFlyout) and "mouseover" or nil)
	end

	-- Apply scale and opacity
	local scale = self.opt.loadoutBarScale or 1.0
	local opacity = self.opt.loadoutBarOpacity or 1.0
	local anchor = self.loadoutAnchor
	if not anchor._scaleApplied then
		anchor:SetScale(scale)
		anchor._scaleApplied = true
	elseif math.abs(anchor:GetScale() - scale) > 0.001 then
		self:SetFrameScaleKeepCenter(anchor, scale)
		self:SaveLoadoutBarPosition()
	end
	self.loadoutAnchor:SetAlpha(opacity)

	-- Update anchor: show active loadout's icon and name
	local hideNames = self.opt.loadoutBarHideNames
	local showTotems = self.opt.loadoutBarShowTotems
	if self.opt.activeLoadout and ShamanPower_TotemLoadouts[self.opt.activeLoadout] then
		local lo = ShamanPower_TotemLoadouts[self.opt.activeLoadout]
		self.loadoutAnchor.nameText:SetText(hideNames and "" or (lo.name or ("Set " .. self.opt.activeLoadout)))
		if showTotems then
			-- Show 4 mini totem icons with dimmed loadout icon background (like flyout buttons)
			self.loadoutAnchor.icon:SetTexture(self:GetLoadoutIcon(self.opt.activeLoadout))
			self.loadoutAnchor.icon:SetAlpha(0.3)
			for e = 1, 4 do
				local totemIdx = lo[e] or 0
				if totemIdx > 0 then
					self.loadoutAnchor.miniIcons[e]:SetTexture(self:GetTotemIcon(e, totemIdx))
				else
					self.loadoutAnchor.miniIcons[e]:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
				end
				self.loadoutAnchor.miniIcons[e]:Show()
			end
		else
			-- Show loadout icon only
			self.loadoutAnchor.icon:SetTexture(self:GetLoadoutIcon(self.opt.activeLoadout))
			self.loadoutAnchor.icon:SetAlpha(1.0)
			for e = 1, 4 do
				self.loadoutAnchor.miniIcons[e]:Hide()
			end
		end
	else
		self.loadoutAnchor.icon:SetTexture("Interface\\Icons\\ClassIcon_Shaman")
		self.loadoutAnchor.icon:SetAlpha(1.0)
		self.loadoutAnchor.nameText:SetText("")
		for e = 1, 4 do
			self.loadoutAnchor.miniIcons[e]:Hide()
		end
	end

	-- Update set buttons: flyout only shows NON-ACTIVE loadouts (anchor is the active one)
	-- The inactive attribute controls whether the secure _childupdate-toggle shows the button
	local btnIndex = 0
	local opensDown = self:LoadoutFlyoutOpensDown()
	self.loadoutFlyoutDown = opensDown
	for i = 1, numLoadouts do
		local summon = self.BoundLoadoutSummon and self:BoundLoadoutSummon(i)
		-- A bound active loadout still needs a cast button: the anchor is only
		-- a hover handle, not a secure action button.
		if i ~= self.opt.activeLoadout or summon then
			btnIndex = btnIndex + 1
			if btnIndex <= 8 then
				local btn = self.loadoutButtons[btnIndex]
				local loadout = ShamanPower_TotemLoadouts[i]

				-- Position radially around anchor (same as TotemTimers)
				local prev = btnIndex == 1 and self.loadoutAnchor or self.loadoutButtons[btnIndex - 1]
				btn:ClearAllPoints()
				-- no gap (as the totem flyouts): the cursor crossing one would leave every
				-- button of the flyout at once, and hover flyouts close on that
				if opensDown then btn:SetPoint("TOP", prev, "BOTTOM", 0, 0)
				else btn:SetPoint("BOTTOM", prev, "TOP", 0, 0) end

				if loadout.icon then
					-- The player chose an icon for this loadout: show it, not the four totems
					for element = 1, 4 do btn.miniIcons[element]:Hide() end
					btn.icon:SetTexture(loadout.icon)
					btn.icon:SetAlpha(1.0)
				else
					-- Update 4 corner icons with totem textures
					for element = 1, 4 do
						local totemIdx = loadout[element] or 0
						if totemIdx > 0 then
							btn.miniIcons[element]:SetTexture(self:GetTotemIcon(element, totemIdx))
						else
							btn.miniIcons[element]:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
						end
						btn.miniIcons[element]:Show()
					end

					-- Show loadout icon as dimmed background (same as TotemTimers: 0.3 alpha)
					btn.icon:SetTexture(self:GetLoadoutIcon(i))
					btn.icon:SetAlpha(0.3)
				end
				btn.nr = i
				btn:SetAttribute("loadoutIndex", i)
				if self.HasTotemBar and self:HasTotemBar() then
					btn:SetAttribute("type", summon and "spell" or nil)
					btn:SetAttribute("spell", summon)
					btn:SetAttribute("spBoundLoadout", summon ~= nil)
				end
				btn.nameText:SetText(hideNames and "" or (ShamanPower_TotemLoadouts[i].name or ("Set " .. i)))

				-- Mark as visible in flyout
				btn:SetAttribute("inactive", false)
			end
		end
	end

	-- Mark remaining buttons as inactive
	for j = btnIndex + 1, 8 do
		local btn = self.loadoutButtons[j]
		btn:SetAttribute("inactive", true)
		if self.HasTotemBar and self:HasTotemBar() then
			btn:SetAttribute("type", nil)
			btn:SetAttribute("spell", nil)
			btn:SetAttribute("spBoundLoadout", nil)
		end
		btn.nameText:SetText("")
		if not InCombatLockdown() then
			btn:Hide()
		end
	end
end

-- Lua fallback for out-of-combat toggle (used by slash commands etc)
function ShamanPower:ToggleLoadoutMenu()
	if InCombatLockdown() then return end
	for i = 1, 8 do
		local btn = self.loadoutButtons[i]
		if not btn:GetAttribute("inactive") then
			if btn:IsVisible() then
				btn:Hide()
			else
				btn:Show()
			end
		end
	end
end

function ShamanPower:ShowLoadoutMenu()
	if InCombatLockdown() then return end
	local numLoadouts = #ShamanPower_TotemLoadouts
	for i = 1, 8 do
		if i <= numLoadouts then
			self.loadoutButtons[i]:Show()
		else
			self.loadoutButtons[i]:Hide()
		end
	end
end

function ShamanPower:HideLoadoutMenu()
	if InCombatLockdown() then return end
	for i = 1, 8 do
		self.loadoutButtons[i]:Hide()
	end
end

function ShamanPower:SaveLoadoutBarPosition()
	local anchor = self.loadoutAnchor
	if not anchor then return end
	self.opt.loadoutBarPosition = self:SavePositionRecord(anchor)
	-- moved across the middle of the screen: the flyout column now opens the other way
	local down = self:LoadoutFlyoutOpensDown()
	if down ~= self.loadoutFlyoutDown and self.loadoutButtons and not InCombatLockdown() then
		self.loadoutFlyoutDown = down
		for i, btn in ipairs(self.loadoutButtons) do
			local prev = i == 1 and anchor or self.loadoutButtons[i - 1]
			btn:ClearAllPoints()
			if down then btn:SetPoint("TOP", prev, "BOTTOM", 0, 0)   -- no gap: see UpdateLoadoutBar
			else btn:SetPoint("BOTTOM", prev, "TOP", 0, 0) end
		end
	end
end

function ShamanPower:RestoreLoadoutBarPosition()
	local pos = self.opt.loadoutBarPosition
	if pos and self.loadoutAnchor then
		self.loadoutAnchor:ClearAllPoints()
		if pos.anchor then
			self:ApplyPositionRecord(self.loadoutAnchor, pos)
		else
			self.loadoutAnchor:SetPoint(pos.point or "CENTER", UIParent, pos.relPoint or "CENTER", pos.x or 0, pos.y or -200)
			self.opt.loadoutBarPosition = self:SavePositionRecord(self.loadoutAnchor)
		end
	end
end

-- ============================================================================
-- TOTEM LOADOUT SLASH COMMANDS: /spl
-- ============================================================================

SLASH_SPLOADOUT1 = "/spl"
SLASH_SPLOADOUT2 = "/sploadout"
SlashCmdList["SPLOADOUT"] = function(msg)
	msg = (msg or ""):trim()

	if msg == "" then
		print("|cff0070ddShamanPower Loadouts:|r")
		print("  /spl save <name>     - Save current totems as new loadout")
		print("  /spl <number>        - Switch to loadout by number")
		print("  /spl <name>          - Switch to loadout by name")
		print("  /spl list            - List all saved loadouts")
		print("  /spl delete <number> - Delete a loadout by number")
		if ShamanPower.HasTotemSets and ShamanPower:HasTotemSets() then
			print("  /spl set <1-3> <loadout> - Send a loadout to Call of the Elements / Ancestors / Spirits")
		end
		return
	end

	-- /spl set <1|2|3> <number|name>  (clients with totem sets)
	local setPage, setWhich = msg:match("^[Ss][Ee][Tt]%s+([123])%s+(.+)$")
	if setPage then
		if not (ShamanPower.PushLoadoutToTotemSet and ShamanPower.HasTotemSets and ShamanPower:HasTotemSets()) then
			print("|cff0070ddShamanPower:|r totem sets are not available in this version of the game")
			return
		end
		local idx = tonumber(setWhich)
		if not idx then
			for i, l in ipairs(ShamanPower_TotemLoadouts) do
				if l.name and l.name:lower() == setWhich:lower() then idx = i break end
			end
		end
		if not idx then print("|cff0070ddShamanPower:|r no loadout '" .. setWhich .. "'") return end
		ShamanPower:PushLoadoutToTotemSet(idx, tonumber(setPage))
		return
	end

	-- /spl list
	if msg:lower() == "list" then
		if #ShamanPower_TotemLoadouts == 0 then
			print("|cff0070ddShamanPower:|r No loadouts saved. Use /spl save <name> to create one.")
			return
		end
		print("|cff0070ddShamanPower Loadouts:|r")
		for i, loadout in ipairs(ShamanPower_TotemLoadouts) do
			local name = loadout.name or ("Loadout " .. i)
			local active = (ShamanPower.opt.activeLoadout == i) and " |cff00ff00[Active]|r" or ""
			local desc = ShamanPower:GetLoadoutDescriptionPlain(i)
			print("  " .. i .. ". " .. name .. active .. "  -  " .. desc)
		end
		return
	end

	-- /spl save <name>
	if msg:lower():sub(1, 5) == "save " then
		local name = msg:sub(6):trim()
		if name == "" then name = nil end
		ShamanPower:SaveLoadout(name)
		return
	end
	if msg:lower() == "save" then
		ShamanPower:SaveLoadout(nil)
		return
	end

	-- /spl delete <number>
	if msg:lower():sub(1, 7) == "delete " then
		local idx = tonumber(msg:sub(8):trim())
		if not idx or not ShamanPower_TotemLoadouts[idx] then
			print("|cff0070ddShamanPower:|r Invalid loadout number.")
			return
		end
		local name = ShamanPower_TotemLoadouts[idx].name or ("Loadout " .. idx)
		ShamanPower:DeleteLoadout(idx)
		print("|cff0070ddShamanPower:|r Deleted loadout '" .. name .. "'")
		return
	end

	-- /spl <number> — switch by index
	local idx = tonumber(msg)
	if idx then
		if ShamanPower_TotemLoadouts[idx] then
			ShamanPower:ApplyLoadout(idx)
		else
			print("|cff0070ddShamanPower:|r No loadout numbered " .. idx .. ". Use /spl list to see available loadouts.")
		end
		return
	end

	-- /spl <name> — switch by name (case-insensitive)
	local searchName = msg:lower()
	for i, loadout in ipairs(ShamanPower_TotemLoadouts) do
		if loadout.name and loadout.name:lower() == searchName then
			ShamanPower:ApplyLoadout(i)
			return
		end
	end
	print("|cff0070ddShamanPower:|r No loadout named '" .. msg .. "'. Use /spl list to see available loadouts.")
end

-- ============================================================================
-- Themes (General > Themes): the core bar files' part. A theme only changes how
-- things LOOK. Where a look has a setting today the theme writes that setting
-- (a preset: the setting's own page still shows and changes it, and Standard
-- puts the player's value back); a look with no setting is read from the engine
-- at paint time, where nil means today's code runs unchanged. Nothing here runs
-- for a player who never picks a theme: the engine calls the repaint only after
-- a theme change. (No new top-level locals: this file is near Lua's limit.)
-- ============================================================================

-- ShamanPowerTheme.lua, loaded right after this file, replaces these three. They
-- only matter if it is missing: then every paint site keeps today's colours.
function ShamanPower:ThemeColor() return nil end
function ShamanPower:ThemeActive() return false end
function ShamanPower:ThemeAlpha() return nil end

-- tb.pulse: the pulse wipe / pulse bar of one pulse visual (white today, 70%).
-- Pulse Bar Color (Totem Bar > Duration Bars) first: a theme clears it while it
-- is picked (the engine keeps the player's colour for Standard), so a colour
-- there means the player picked it; then the theme's colour; then white.
function ShamanPower:ThemePaintPulse(o, element)
	local wipe = o and o.wipe
	if not (wipe and element) then return end
	local r, g, b
	local own = self.opt and self.opt.pulseBarColor
	if own then r, g, b = own.r or 1, own.g or 1, own.b or 1
	else r, g, b = self:ThemeColor("tb.pulse", element) end
	if r then
		self:SetSPBarColor(wipe, "pulse", r, g, b, 0.7)
		o.spThemePulse = true
	elseif o.spThemePulse then
		o.spThemePulse = nil
		self:SetSPBarColor(wipe, "pulse", 1, 1, 1, 0.7)
	end
end

-- Pulse Bar Color changed: every pulse bar and wipe takes it now
function ShamanPower:RepaintPulseBarColors()
	for element = 1, 4 do
		self:ThemePaintPulse(self.pulseOverlays and self.pulseOverlays[element], element)
		local ov = self.activeTotemOverlays and self.activeTotemOverlays[element]
		if ov then self:ThemePaintPulse(ov, element) end
	end
	if self.poppedOutOverlays then
		for _, o in pairs(self.poppedOutOverlays) do self:ThemePaintPulse(o, o.element) end
	end
	if self.RepaintBlizzardBarPulses then self:RepaintBlizzardBarPulses() end
end

-- tb.duration-text: one duration time text (white today).
function ShamanPower:ThemePaintDurationText(fs, element)
	if not (fs and element) then return end
	local r, g, b = self:ThemeColor("tb.duration-text", element)
	if r then
		fs:SetTextColor(r, g, b)
		fs.spThemeText = true
	elseif fs.spThemeText then
		fs.spThemeText = nil
		fs:SetTextColor(1, 1, 1)
	end
end

-- One element's duration bar (tb.duration: the engine rewrites DurationBarColors
-- in place) and its time texts (tb.duration-text). withBar = also repaint the bar.
function ShamanPower:ThemePaintDurationBars(element, withBar)
	local bars = self.totemProgressBars and self.totemProgressBars[element]
	if not bars then return end
	local c = self.DurationBarColors[element]
	if withBar and bars.bar and c then self:SetSPBarColor(bars.bar, "duration", c[1], c[2], c[3], 1) end
	self:ThemePaintDurationText(bars.insideTextTop, element)
	self:ThemePaintDurationText(bars.insideTextBottom, element)
	self:ThemePaintDurationText(bars.aboveBarText, element)
	self:ThemePaintDurationText(bars.belowBarText, element)
	self:ThemePaintDurationText(bars.iconText, element)
end

-- the edge round a dropped-totem or Earth Shield overlay (both sit on the totem
-- bar): a ring round a Rounded / Circle icon in r, g, b; Square or Keep Borders
-- Square: the four edges, as always
function ShamanPower:ShapeOverlayEdge(overlay, r, g, b)
	local edges = overlay and overlay.spEdges
	if not edges then return end
	local frame = edges[1]:GetParent()
	local ringFile = self.BorderRingSizedFile and self:BorderRingSizedFile("totem", 2, frame:GetWidth())
	local ring = overlay.spRing
	if ringFile and not ring then
		ring = frame:CreateTexture(nil, "BORDER")
		ring:SetAllPoints(frame)
		overlay.spRing = ring
	end
	if not ring then return end
	if ringFile then
		if ring.spFile ~= ringFile then ring:SetTexture(ringFile); ring.spFile = ringFile end
		ring:SetVertexColor(r, g, b, 1)
	end
	ring:SetShown(ringFile ~= nil)
	for i = 1, #edges do edges[i]:SetShown(ringFile == nil) end
end

-- tb.overlay-border: the element-coloured edge round a dropped-totem overlay.
function ShamanPower:ThemePaintOverlayBorder(overlay, element)
	local edges = overlay and overlay.spEdges
	if not edges then return end
	local r, g, b = self:ThemeColor("tb.overlay-border", element)
	local c = self.ElementColors[element]
	if r then self:ShapeOverlayEdge(overlay, r, g, b) else self:ShapeOverlayEdge(overlay, c.r, c.g, c.b) end
	if r then
		overlay.spThemeEdge = true
	elseif overlay.spThemeEdge then
		overlay.spThemeEdge = nil
		local c = self.ElementColors[element]
		r, g, b = c.r, c.g, c.b
	else
		return
	end
	for i = 1, #edges do edges[i]:SetColorTexture(r, g, b, 1) end
end

-- tb.frame / cd.frame: the theme's panel colours on the totem bar's and the
-- cooldown bar's backdrop. The totem bar's fill is its Fully Buffed status colour
-- (a setting, written by the theme), so only its border is painted here. Today's
-- colours come back once a theme had painted; colours only, never the backdrop.
function ShamanPower:ThemePaintBarFrame(frame, spot)
	if not (frame and frame.backdropInfo) then return end
	local cd = (spot == "cd.frame")
	local r, g, b = self:ThemeColor(spot, "border")
	if r then
		frame:SetBackdropBorderColor(r, g, b, cd and 0.8 or 1)
		frame.spThemeEdge = true
	elseif frame.spThemeEdge then
		frame.spThemeEdge = nil
		if cd then frame:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8) else frame:SetBackdropBorderColor(1, 1, 1, 1) end
	end
	if not cd then return end
	r, g, b = self:ThemeColor(spot, "bg")
	if r then
		frame:SetBackdropColor(r, g, b, self:ThemeAlpha(spot, "bg") or 0.7)
		frame.spThemeFill = true
	elseif frame.spThemeFill then
		frame.spThemeFill = nil
		frame:SetBackdropColor(0, 0, 0, 0.7)
	end
end

-- tb.flyout-art: a totem flyout's tab drawn flat in its element colour, or nil =
-- Blizzard's tab art. The cooldown bar's flyouts (neutral art) keep the art.
function ShamanPower:ThemeFlyoutTabColor(flyout, element)
	if not flyout or flyout.isCdbarFlyout or type(element) ~= "number" or element < 1 or element > 4 then return nil end
	return self:ThemeColor("tb.flyout-art", element)
end

-- Out of combat (ThemeRepaintSoon waits for the end of a fight): re-place the
-- totem flyouts' tabs, which paints them flat or puts the art back.
function ShamanPower:ThemeRepaintFlyoutTabs()
	if InCombatLockdown() or not self.boxFlyouts then return end
	for key, entry in pairs(self.boxFlyouts) do
		if type(key) == "number" and entry.flyout then self:PlaceFlyoutArrows(entry.flyout) end
	end
end

-- lo.tooltip: the colour code of one element name in a loadout's tooltip, or nil.
function ShamanPower:ThemeLoadoutTipColor(element)
	local r, g, b = self:ThemeColor("lo.tooltip", element)
	if not r then return nil end
	return string.format("|cff%02x%02x%02x",
		math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

-- After every theme change (the engine calls it; never on a plain Standard
-- login). Colours only, all of them allowed in combat; the rebuilds go through
-- ThemeRepaintSoon, which waits for the end of a fight.
-- General > Themes > Element-Colored Borders (SP.opt.theme.borders): a 2px edge in
-- each totem's element colour just inside the edge of its totem bar button, like
-- the icons on the Element Colors cards; with Also on the Flyouts
-- (SP.opt.theme.bordersFlyouts) every totem in the flyouts too. Inside, so nothing moves or overlaps at
-- any button spacing. Icon bar styles only: Compact, Grid and Blizzard's Totem
-- Bar show the element colours their own way. Nothing is made until it is first
-- turned on; turned off, the edges hide.
function ShamanPower:ThemePaintTotemBorders()
	local t = self.opt and self.opt.theme
	local on = type(t) == "table" and t.borders == true
	local want = on
	if want and ((self.CompactActive and self:CompactActive()) or (self.GridActive and self:GridActive())
		or (self.UsingBlizzardTotemBar and self.UsingBlizzardTotemBar())) then
		want = false
	end
	local fly = want and t.bordersFlyouts == true
	local cd = on and t.bordersCooldown == true   -- (the cooldown bar is not a totem bar style)
	if not on and not self._themeBordersMade then return end
	for element = 1, 4 do
		local btn = self.totemButtons and self.totemButtons[element]
		if btn then self:ThemeBorderEdges(btn, want, "tb.boxes", element) end
		-- Also on the Flyouts: every totem in the element's flyout (not the Empty choice)
		local flyout = self.totemFlyouts and self.totemFlyouts[element]
		local all = flyout and flyout.allButtons
		if all then
			for i = 1, #all do
				local fb = all[i]
				if fb and fb.totemIndex ~= 0 then self:ThemeBorderEdges(fb, fly, "tb.flyout-boxes", element) end
			end
		end
		-- Totem Rows' copies of them (Keep Flyouts on Main Totem Bar): as the flyout's own
		local copies = self.RowsCopies and self:RowsCopies(element)
		if copies then
			for i = 1, #copies do
				local cb = copies[i]
				if cb and cb.totemIndex ~= 0 then self:ThemeBorderEdges(cb, fly, "tb.flyout-boxes", element) end
			end
		end
	end
	-- Also on the Cooldown Bar: each button in the colour of its icon (as its flat box)
	local list = self.cooldownButtons
	if list then
		for i = 1, #list do
			local btn = list[i]
			if btn then self:ThemeBorderEdges(btn, cd, "cd.boxes", nil) end
		end
	end
	local es = _G.ShamanPowerEarthShieldBtn
	if es and es.icon then self:ThemeBorderEdges(es, cd, "cd.boxes", nil) end
	-- Also on the Cooldown Bar Flyouts: every shield and imbue in their flyouts,
	-- each in the colour of what it shows (as the cooldown bar's own buttons)
	local cdFly = cd and t.bordersCooldownFlyouts == true
	local shieldFly = self.shieldFlyout
	if shieldFly then
		for _, fb in ipairs(shieldFly.allButtons or shieldFly.buttons or {}) do self:ThemeBorderEdges(fb, cdFly, "cd.flyout-boxes", nil) end
	end
	local imbueFly = self.weaponImbueFlyout
	if imbueFly then
		for _, fb in ipairs(imbueFly.allButtons or imbueFly.buttons or {}) do self:ThemeBorderEdges(fb, cdFly, "cd.flyout-boxes", nil) end
	end
end

-- one button's border: made the first time it is wanted, then shown / hidden
function ShamanPower:ThemeBorderEdges(btn, on, spot, element)
	local icon = btn.icon
	local edges = btn.spThemeBorder
	if on and icon then
		if not edges then
			edges = {}
			for i = 1, 4 do edges[i] = btn:CreateTexture(nil, "OVERLAY", nil, -1) end
			btn.spThemeBorder = edges
			self._themeBordersMade = true
		end
		-- Border Size (General > Themes, one slider under each toggle): 2 px by default
		local field = (spot == "cd.boxes") and "borderSizeCooldown" or ((spot == "cd.flyout-boxes") and "borderSizeCooldownFlyouts")
			or ((spot == "tb.flyout-boxes") and "borderSizeFlyouts" or "borderSize")
		local px = (self.ThemeField and self:ThemeField(field)) or 2
		if edges.px ~= px then
			edges.px = px
			for i = 1, 4 do edges[i]:ClearAllPoints() end
			edges[1]:SetPoint("TOPLEFT", icon, "TOPLEFT"); edges[1]:SetPoint("TOPRIGHT", icon, "TOPRIGHT"); edges[1]:SetHeight(px)
			edges[2]:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT"); edges[2]:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT"); edges[2]:SetHeight(px)
			edges[3]:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, -px); edges[3]:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", 0, px); edges[3]:SetWidth(px)
			edges[4]:SetPoint("TOPRIGHT", icon, "TOPRIGHT", 0, -px); edges[4]:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, px); edges[4]:SetWidth(px)
		end
		-- a Rounded / Circle icon: the border follows it as a ring (Keep Borders Square: the edges)
		local iw = icon:GetWidth()
		if not iw or iw < 4 then iw = btn:GetWidth() or 32 end
		local cdSpot = (spot == "cd.boxes" or spot == "cd.flyout-boxes")
		local ringFile = self.BorderRingSizedFile and self:BorderRingSizedFile(cdSpot and "cooldown" or "totem", px, iw)
		if ringFile and not edges.ring then
			edges.ring = btn:CreateTexture(nil, "OVERLAY", nil, -1)
			edges.ring:SetAllPoints(icon)
		end
		if ringFile and edges.ring.spFile ~= ringFile then edges.ring:SetTexture(ringFile); edges.ring.spFile = ringFile end
		edges.ringOn = ringFile and true or false
		local r, g, b
		if element then
			r, g, b = self:ThemeElement(spot, element)
		elseif self.ThemeIconRGB then
			-- a cooldown button: the colour of whatever its icon shows, and again when it changes
			r, g, b = self:ThemeIconRGB(icon, spot)
			if not btn.spThemeBorderHooked then
				btn.spThemeBorderHooked = true
				hooksecurefunc(icon, "SetTexture", function(tex)
					local e = btn.spThemeBorder
					if e and (e[1]:IsShown() or (e.ring and e.ring:IsShown())) then
						local nr, ng, nb = ShamanPower:ThemeIconRGB(tex, spot)
						if nr then ShamanPower:PaintBorderEdges(e, nr, ng, nb) end
					end
				end)
			end
		end
		if r then self:PaintBorderEdges(edges, r, g, b) end   -- (nil: unreadable right now, keep the last colour)
		for i = 1, 4 do edges[i]:SetShown(not edges.ringOn) end
		if edges.ring then edges.ring:SetShown(edges.ringOn) end
	elseif edges then
		for i = 1, 4 do edges[i]:Hide() end
		if edges.ring then edges.ring:Hide() end
	end
end

-- the four edges (top, bottom, left, right) in one colour, or shaded by the
-- Outline Gradient (General > Themes > Shapes & Textures)
function ShamanPower:PaintBorderEdges(e, r, g, b)
	-- the ring a Rounded / Circle icon's border becomes (ThemeBorderEdges)
	if e.ring then
		if self.PaintOutlineRing then self:PaintOutlineRing(e.ring, r, g, b, 1) else e.ring:SetVertexColor(r, g, b, 1) end
	end
	if self.opt and self.opt.outlineGradient and self.PaintOutlineEdges then
		for k = 1, 4 do e[k]:SetColorTexture(1, 1, 1, 1) end
		self:PaintOutlineEdges(e[1], e[2], e[3], e[4], r, g, b, 1)
	else
		for k = 1, 4 do
			if e[k].spGrad then e[k]:SetVertexColor(1, 1, 1, 1); e[k].spGrad = nil end
			e[k]:SetColorTexture(r, g, b, 1)
		end
	end
end

function ShamanPower:ThemeRepaintCore()
	-- tb.range: the party counters' colours live in the Party Range module's table
	-- (loaded after this file): bound the first time a theme is in play
	local rcc = self.RangeCounterColors
	if rcc and self._themeRangeBound ~= rcc then
		self._themeRangeBound = rcc
		for e = 1, 4 do
			if type(rcc[e]) == "table" then self:ThemeBind(rcc[e], "tb.range", e) end
		end
	end
	-- the unlocked counter frames colour their element label once, when built
	if rcc then
		for e = 1, 4 do
			local f = self.rangeCounterFrames and self.rangeCounterFrames[e]
			local c = rcc[e]
			if f and f.label and type(c) == "table" then f.label:SetTextColor(c[1], c[2], c[3]) end
		end
		if self.UpdateRangeCounters then self:UpdateRangeCounters() end
	end
	for element = 1, 4 do
		self:ThemePaintDurationBars(element, true)
		self:ThemePaintPulse(self.pulseOverlays and self.pulseOverlays[element], element)
		local ov = self.activeTotemOverlays and self.activeTotemOverlays[element]
		if ov then
			self:ThemePaintOverlayBorder(ov, element)
			self:ThemePaintPulse(ov, element)
		end
	end
	if self.poppedOutProgressBars then
		for _, pb in pairs(self.poppedOutProgressBars) do
			local c = pb.element and self.DurationBarColors[pb.element]
			if c and pb.bar then self:SetSPBarColor(pb.bar, "duration", c[1], c[2], c[3], 1) end
			self:ThemePaintDurationText(pb.text, pb.element)
		end
	end
	if self.poppedOutOverlays then
		for _, o in pairs(self.poppedOutOverlays) do self:ThemePaintPulse(o, o.element) end
	end
	if self.poppedOutFrames then
		for _, frame in pairs(self.poppedOutFrames) do self:ThemePaintPanel(frame, "mod.popouts-colors") end
	end
	-- the bars' frames; the totem bar's fill is its Fully Buffed colour, re-applied
	local auto = _G["ShamanPowerAuto"]
	if auto then self:ThemePaintBarFrame(auto, "tb.frame") end
	if self.cooldownBar then self:ThemePaintBarFrame(self.cooldownBar, "cd.frame") end
	if auto and isShaman and self.opt and self.player then self:ButtonsUpdate() end
	-- cd.strip: the shield button's charge strip (the engine rewrote ShieldStrip.COLOR)
	local strip = self.shieldButton and self.shieldButton.chargeStrip
	if strip then
		local c = ShieldStrip.COLOR
		strip:SetStatusBarColor(c[1], c[2], c[3])
	end
	-- The two rebuilds run only when their colours really moved (a colour drag on
	-- the Themes tab changes something else many times a second).
	-- Totem flyout tabs: re-placed out of combat (flat, or the art back).
	local s = 0
	for e = 1, 4 do
		local r, g, b = self:ThemeColor("tb.flyout-art", e)
		if r then s = s + e * (r * 3 + g * 5 + b * 7) end
	end
	if self._themeTabsFn and s ~= (self._themeTabsSig or 0) then
		self._themeTabsSig = s
		self:ThemeRepaintSoon("core.flyouttabs", self._themeTabsFn)
	end
	-- WoW: Forever: the game-drawn shield count / bar take their colours when built
	if SPCompat.FOREVER and self._themeShieldFn then
		s = 0
		local r, g, b = self:ThemeColor("cd.engine", "bar")
		if r then s = s + r * 3 + g * 5 + b * 7 end
		r, g, b = self:ThemeColor("cd.count", "high")
		if r then s = s + r * 11 + g * 13 + b * 17 end
		r, g, b = self:ThemeColor("cd.count", "mid")
		if r then s = s + r * 19 + g * 23 + b * 29 end
		r, g, b = self:ThemeColor("cd.count", "low")
		if r then s = s + r * 31 + g * 37 + b * 41 end
		r, g, b = self:ThemeColor("cd.strip", "strip")
		if r then s = s + r * 43 + g * 47 + b * 53 end
		if s ~= (self._themeShieldSig or 0) then
			self._themeShieldSig = s
			if self.shieldButton and self.shieldButton.chargeContainer then
				self:ThemeRepaintSoon("core.shieldcontainer", self._themeShieldFn)
			end
		end
	end
end

-- Called by ShamanPowerTheme.lua when it loads: this file's setting-backed parts,
-- its live colour tables, and the repaint.
function ShamanPower:ThemeRegisterCore()
	local SP = self

	-- pal.element: the Element Colors setting on Appearance. The ShamanPower themes
	-- write the ShamanPower palette (or the Element Colors card picked on the Themes
	-- tab); Standard puts the player's own back. Each set() does what the Appearance
	-- option does: write the value, then ApplyElementColors. The custom colours go
	-- first, so a "custom" palette never starts from a made-up copy.
	SP:ThemeSpotSettings("pal.element", {
		{ key = "custom", label = "Custom Element Colors",
		  get = function() return SP.opt and SP.opt.elementColorsCustom end,
		  set = function(v)
			if type(v) == "table" then
				local t = {}
				for e = 1, 4 do
					local c = v[e]
					if type(c) == "table" then t[e] = { r = c.r or 1, g = c.g or 1, b = c.b or 1 } end
				end
				SP.opt.elementColorsCustom = t
			else
				SP.opt.elementColorsCustom = nil
			end
			SP:ApplyElementColors()
		  end,
		  -- only when the Themes tab's Custom card is the palette
		  shamanpower = function()
			if SP:ThemeSpotPalette("pal.element") ~= "custom" then return nil end
			local t = {}
			for e = 1, 4 do
				local r, g, b = SP:ThemePaletteRGB("custom", e)
				t[e] = { r = r, g = g, b = b }
			end
			return t
		  end,
		},
		{ key = "palette", label = "Element Colors",
		  get = function() return SP.opt and SP.opt.elementColorPalette end,
		  set = function(v)
			if v == "custom" and not SP.opt.elementColorsCustom then
				-- start from whatever is showing now (as the Appearance option does)
				local t = {}
				for e = 1, 4 do local r, g, b = SP:ElementPaletteColor(e); t[e] = { r = r, g = g, b = b } end
				SP.opt.elementColorsCustom = t
			end
			SP.opt.elementColorPalette = v
			SP:ApplyElementColors()
		  end,
		  shamanpower = function() return SP:ThemeSpotPalette("pal.element") or "shamanpower" end,
		},
	})

	-- tb.pulse: Totem Bar > Duration Bars > Pulse Bar Color. A theme that colours
	-- the pulse clears it while it is picked (its own colours show; the player's
	-- is kept and Standard puts it back). A colour picked on Duration Bars in the
	-- meantime shows over the theme, and the Themes tab says Custom.
	SP:ThemeSpotSettings("tb.pulse", {
		{ key = "pulseBarColor", follows = "choice",
		  get = function()
			local c = SP.opt and SP.opt.pulseBarColor
			if type(c) == "table" then return { r = c.r or 1, g = c.g or 1, b = c.b or 1 } end
			return false
		  end,
		  set = function(v)
			if type(v) == "table" then
				SP.opt.pulseBarColor = { r = v.r or v[1] or 1, g = v.g or v[2] or 1, b = v.b or v[3] or 1 }
			else
				SP.opt.pulseBarColor = nil
			end
			SP:RepaintPulseBarColors()
		  end,
		  shamanpower = false,
		},
	})

	-- tb.cooldown-text: Totem Bar > Duration Bars > Cooldown Text Color. The
	-- ShamanPower themes write white; the Duration Bars page still changes it.
	SP:ThemeSpotSettings("tb.cooldown-text", {
		{ role = "text", label = "Cooldown Text Color",
		  get = function()
			local c = SP.opt and SP.opt.totemCooldownTextColor
			return { r = c and c.r or 1, g = c and c.g or 1, b = c and c.b or 1 }
		  end,
		  set = function(v)
			if type(v) ~= "table" then return end
			if not SP.opt.totemCooldownTextColor then
				SP.opt.totemCooldownTextColor = {}
			end
			SP.opt.totemCooldownTextColor.r = v.r or v[1] or 1
			SP.opt.totemCooldownTextColor.g = v.g or v[2] or 1
			SP.opt.totemCooldownTextColor.b = v.b or v[3] or 1
			SP:ApplyTotemCooldownTextColor()
		  end,
		  shamanpower = { r = 1, g = 1, b = 1 },
		},
	})

	-- tb.frame: the totem bar's panel. Its fill is Status Colors > Fully Buffed
	-- and Textures > Background Textures; the ShamanPower themes write navy #141B26
	-- at 92% on a flat texture. (Partially / None Buffed keep their colours: they
	-- say something.) The border colour has no setting: painted by ThemePaintBarFrame.
	SP:ThemeSpotSettings("tb.frame", {
		{ role = "bg", label = "Background (Fully Buffed)",
		  get = function()
			local c = SP.opt and SP.opt.cBuffGood
			if not c then return nil end
			return { r = c.r, g = c.g, b = c.b, t = c.t }
		  end,
		  set = function(v)
			if type(v) ~= "table" then return end
			SP:EnsureProfileTable("cBuffGood")
			local c = SP.opt.cBuffGood
			c.r = v.r or v[1] or c.r
			c.g = v.g or v[2] or c.g
			c.b = v.b or v[3] or c.b
			if v.t ~= nil then c.t = v.t end
		  end,
		  shamanpower = { r = 0x14 / 255, g = 0x1B / 255, b = 0x26 / 255, t = 0.92 },
		},
		{ key = "skin", label = "Background Texture",
		  get = function() return SP.opt and SP.opt.skin end,
		  set = function(v)
			SP.opt.skin = v
			SP:ApplySkin()
			SP:UpdateRoster()
		  end,
		  shamanpower = "Solid",
		},
	})

	-- tb.range: Party Buff Tracker > Use Element Colors (the numbers take the
	-- palette's colours only while it is on). Colours: bound in ThemeRepaintCore.
	SP:ThemeSpotSettings("tb.range", {
		{ key = "useElementColors", label = "Use Element Colors",
		  get = function()
			local rc = SP.opt and SP.opt.rangeCounter
			if rc then return rc.useElementColors end
			return nil
		  end,
		  set = function(v)
			if not SP.opt.rangeCounter then
				SP.opt.rangeCounter = {}
			end
			SP.opt.rangeCounter.useElementColors = v
			SP:UpdateRangeCounters()
		  end,
		  shamanpower = true,
		},
	})

	-- cd.count: Cooldown Display > Color Shield Charges by Count (the ShamanPower
	-- themes colour the count with WoW's green / yellow / red).
	SP:ThemeSpotSettings("cd.count", {
		{ key = "shieldChargeColors", label = "Color Shield Charges by Count",
		  get = function() return SP.opt and SP.opt.shieldChargeColors end,
		  set = function(v)
			SP.opt.shieldChargeColors = v
			if SP.RebuildShieldChargeContainer then SP:RebuildShieldChargeContainer() end
		  end,
		  shamanpower = true,
		},
	})

	-- cd.shieldbar (and cd.imbuebar): Cooldown Display > Spell-Colored Progress
	-- Bars, which is what puts the shield / imbue colours on the bars at all.
	-- Registered once, here, so the two spots never undo each other.
	SP:ThemeSpotSettings("cd.shieldbar", {
		{ key = "cdbarSpellColors", label = "Spell-Colored Progress Bars",
		  get = function() return SP.opt and SP.opt.cdbarSpellColors end,
		  set = function(v)
			SP.opt.cdbarSpellColors = v
			if SP.RebuildShieldChargeContainer then SP:RebuildShieldChargeContainer() end
		  end,
		  shamanpower = true,
		},
	})

	-- Live colour tables the engine rewrites in place (and restores on Standard);
	-- every reader follows without a change at the paint site.
	for e = 1, 4 do SP:ThemeBind(SP.DurationBarColors[e], "tb.duration", e) end
	SP:ThemeBind(SP.SpellBarColors[324], "cd.shieldbar", "lightning")
	SP:ThemeBind(SP.SpellBarColors[24398], "cd.shieldbar", "water")
	SP:ThemeBind(SP.SpellBarColors[408510], "cd.shieldbar", "water")
	-- ImbueBarColors: 1 Windfury (Air), 2 Flametongue (Fire), 3 Frostbrand (Water), 4 Rockbiter (Earth)
	SP:ThemeBind(SP.ImbueBarColors[1], "cd.imbuebar", 4)
	SP:ThemeBind(SP.ImbueBarColors[2], "cd.imbuebar", 2)
	SP:ThemeBind(SP.ImbueBarColors[3], "cd.imbuebar", 3)
	SP:ThemeBind(SP.ImbueBarColors[4], "cd.imbuebar", 1)
	SP:ThemeBind(ShieldStrip.COLOR, "cd.strip", "strip")

	-- the rebuilds ThemeRepaintCore schedules (made once: no closure per change)
	SP._themeTabsFn = function() SP:ThemeRepaintFlyoutTabs() end
	SP._themeShieldFn = function()
		if SP.RebuildShieldChargeContainer then SP:RebuildShieldChargeContainer() end
	end
	SP:OnThemeChanged(function() SP:ThemeRepaintCore(); SP:ThemePaintTotemBorders() end)
	-- the borders follow a rebuilt or restyled totem bar and an Appearance palette change
	-- (both return at once while the borders are off and were never made)
	hooksecurefunc(SP, "UpdateMiniTotemBar", function() SP:ThemePaintTotemBorders() end)
	hooksecurefunc(SP, "ApplyElementColors", function() SP:ThemePaintTotemBorders() end)
	hooksecurefunc(SP, "CreateTotemFlyout", function() SP:ThemePaintTotemBorders() end)   -- a flyout built later
	hooksecurefunc(SP, "CreateCooldownBar", function() SP:ThemePaintTotemBorders() end)   -- a new or rebuilt cooldown bar
	hooksecurefunc(SP, "CreateWeaponImbueButton", function() SP:ThemePaintTotemBorders() end)
	hooksecurefunc(SP, "CreateShieldFlyout", function() SP:ThemePaintTotemBorders() end)        -- the cooldown bar's flyouts, built later
	hooksecurefunc(SP, "CreateWeaponImbueFlyout", function() SP:ThemePaintTotemBorders() end)
end
