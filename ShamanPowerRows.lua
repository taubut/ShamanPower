-- ShamanPowerRows.lua
-- Totem Rows (D48): a switch that goes with any totem bar style but Grid (Grid lays
-- every totem out in rows of its own): every element's totems also stay out for good
-- in a row of their own, each row placed on its own in Unlock UI, next to the bar the
-- player picked (Normal, TotemTimers, Single Totem, Dynamic, Compact, Blizzard's).
--
-- The rows ARE the flyouts' own secure buttons, pinned the way Grid pins them
-- (the spGridPinned attribute and the totem button's spGridPinned field), moved
-- into a row frame of their own: a click casts or assigns exactly as a flyout
-- pick does, in a fight too, and the flyout code leaves them alone while they are
-- rows (Grid's GridLayoutElement asks RowsOwnFlyouts first). Only the marks and
-- the time text change in a fight (plain textures); every move, show and hide
-- waits for the fight to end.
--
-- A row's spot is its FIRST totem (the anchor). The row opens away from the
-- nearest screen edge, the way the flyouts do: across rows to the left on the
-- right side of the screen, down rows downward in the top part. The direction is
-- worked out when the row is dropped and kept with its spot, with a dead zone, so
-- a row near the middle does not flip back and forth.
--
-- CPU: no OnUpdate of its own. The marks and the time text are painted from the
-- totem events and the bar's own 10 fps duration tick (asleep while no totem is
-- down); nothing here allocates on that path.
local SP = ShamanPower
if not SP then return end

local KEYS = { "totem_earth", "totem_fire", "totem_water", "totem_air" }
local NAMES = { "Earth", "Fire", "Water", "Air" }
local GAP = 4                        -- between two totems of a row (the edges sit 1 px outside the icon)
-- between two rows on their default spots, and from the bar (UIParent units): room for
-- the Reset tab over each Unlock UI box, as the cooldown bar's default spot leaves it
local ROW_GAP = 4 + 15

local rows = {}                      -- [element] = { element, anchor, host, all, count, shown, gx, gy, side, box }
local applied, owner = false, nil
local newCopies = false              -- (a Keep Flyouts copy made since the looks were last painted)
local carrying = false               -- Show Main Totem Bar off: the rows carry the bar's pieces (see "Carry")
local secret = issecretvalue or function() return false end
local pending, queued, refreshing = false, false, false

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------
-- Totem Rows' switch is on, with any style but Grid (a profile saved while it was a
-- style of its own, in 3.0.7's test builds, has the switch on)
local function requested()
	local o = SP.opt
	if not o then return false end
	if o.rowsStyle ~= nil then
		if o.rowsStyle == true then o.totemRows = true end
		o.rowsStyle = nil
	end
	return o.totemRows == true and not o.gridStyle
end

function SP:RowsActive() return applied end
function SP:RowsRequested() return requested() end

-- While an element's row holds its flyout's buttons, the flyout code leaves them
-- alone: no hover layout, no show or hide (Grid's GridLayoutElement asks this
-- first). A row switched off gives its element the plain hover flyout back.
function SP:RowsOwnFlyouts(element)
	if not applied then return false end
	local r = element and rows[element]
	return r ~= nil and r.all ~= nil and r.pinned == true
end

-- The element pop-outs wait while Totem Rows is on (each row already moves on its
-- own); they come back when it is off.
function SP:RowsOwnElementPopouts()
	return applied or requested() or (self.opt and self.opt.rowsRestorePopouts ~= nil) or false
end

-- Show the Bar is off: the bar's own buttons stay hidden. Their keybinds still drop
-- your assigned totems (a hidden secure button still answers its binding), and
-- Keybind Mode shows them while it is open.
function SP:RowsHideBar()
	return applied and self.opt and self.opt.rowsShowBar == false and not self.opt.useBlizzardTotemBar
		and not (self.UsingBlizzardTotemBar and self:UsingBlizzardTotemBar())   -- (Blizzard's bar: not ours)
		and not (self.KeybindModeActive and self:KeybindModeActive()) or false
end

-- a row's totems: the flyouts' size (Totem Bar > Flyouts), whatever the bar's style (Compact's own
-- smaller flyouts are for its lines)
local function rowButtonSize()
	local v = tonumber(SP.opt and SP.opt.totemFlyoutButtonSize) or 28
	return math.max(16, math.min(64, math.floor(v + 0.5)))
end

local function rowScale()
	local s = SP.opt and SP.opt.rowsScale
	return (type(s) == "number" and s >= 0.5 and s <= 2) and s or 1
end

-- The bar would be up right now (switched on, wanted in this kind of group, not
-- hidden by Hide Out of Combat / Hide When No Totems): the rows follow it, also
-- with Show the Bar off. (With Blizzard's bar those rules don't run: in use is enough.)
local function barUp()
	if SP:IsOff() then return false end
	if not SP:TotemBarInUse() then return false end
	if SP.UsingBlizzardTotemBar and SP:UsingBlizzardTotemBar() then return true end
	return not SP.totemBarHidden
end

local function wanted(element)
	local off = SP.opt.rowsOff
	if type(off) == "table" and off[element] then return false end
	if not SP:IsElementShown(element) then return false end
	-- Unlock UI open: every row is up so it can be placed, whatever hides the bar right now
	-- (Hide Out of Combat, Hide When No Totems)
	if SP.IsMasterUnlocked and SP:IsMasterUnlocked() then return not SP:IsOff() end
	return barUp()
end

-- The flyout's opacity (the rows are its choices), or the faded bar's.
local function rowAlpha()
	if SP.totemBarFaded then return SP.opt.fadeOpacity or 0.25 end
	return SP.opt.totemFlyoutOpacity or 1
end

-- a mark left on a button by an earlier test build of this file: hidden
local function hideVisual(b)
	local v = b and b.spRowVisual
	if not v then return end
	for i = 1, 4 do v.edges[i]:Hide() end
	v.text:Hide()
end

-- The rows are plain totems, as TotemTimers drew them: what is down, what is assigned and
-- the time left are the bar's to show. (Kept for the core's flyout-mark call: nothing to do.)
function SP:UpdateTotemRows() end

-- ---------------------------------------------------------------------------
-- Rows and their spots
-- ---------------------------------------------------------------------------
local function rowFrames(element)
	local r = rows[element]
	if r then return r end
	r = { element = element, count = 0, shown = false }
	-- The spot: one totem's size, on the row's first totem. Unlock UI moves this
	-- one (one point on UIParent) and its box covers the whole row (spMoverSize).
	local anchor = CreateFrame("Frame", "ShamanPowerTotemRowSpot" .. element, UIParent)
	anchor:SetSize(28, 28)
	anchor:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	anchor:EnableMouse(false)
	-- The row: holds the pinned secure buttons, so it is protected itself (it is
	-- only ever moved, scaled, shown or hidden out of combat).
	local host = CreateFrame("Frame", "ShamanPowerTotemRow" .. element, UIParent, "SecureFrameTemplate")
	host:SetSize(28, 28)
	host:Hide()
	-- Arrow (box) flyouts close by Lua when the mouse leaves a button or a fight ends, and
	-- find the flyout through the button's parent: the row is pinned, so it never closes.
	host.spGridPinned = true
	anchor.spMoverSize = host
	anchor.spMoverLabel = NAMES[element] .. " Row"
	r.anchor, r.host = anchor, host
	rows[element] = r
	return r
end

local function anchorXY(point, W, H)
	local x = (point:find("LEFT") and 0) or (point:find("RIGHT") and W) or W / 2
	local y = (point:find("TOP") and H) or (point:find("BOTTOM") and 0) or H / 2
	return x, y
end

-- Which way a row opens from its spot (cx, cy: the spot's centre, UIParent units).
-- prev: the direction it had, kept inside the dead zone (0.4 to 0.6 of the screen).
local function growFrom(prev, cx, cy)
	local W, H = UIParent:GetWidth(), UIParent:GetHeight()
	local fx, fy = cx / math.max(1, W), cy / math.max(1, H)
	local gx, gy = prev and prev.gx, prev and prev.gy
	if gx == "left" then
		if fx < 0.4 then gx = "right" end
	elseif gx == "right" then
		if fx > 0.6 then gx = "left" end
	else
		gx = fx > 0.5 and "left" or "right"
	end
	if gy == "down" then
		if fy < 0.4 then gy = "up" end
	elseif gy == "up" then
		if fy > 0.6 then gy = "down" end
	else
		gy = fy > 0.5 and "down" or "up"
	end
	return gx, gy
end

-- The visible totem bar's box (centre x, y, width, height; UIParent units), from
-- the saved spots and the sizes set on the frames, as the cooldown bar's default
-- spot is worked out (never read back off the screen).
local function barBox()
	local W, H = UIParent:GetWidth(), UIParent:GetHeight()
	local dx, dy, bw, bh = SP:TotemBarGeometry()
	local rec = SP:TotemBarRecord()
	local tx, ty
	if rec then
		local ax, ay = anchorXY(rec.anchor, W, H)
		tx, ty = ax + rec.x + dx, ay + rec.y + dy
	else
		local def = SP.DEFAULT_TOTEM_BAR_POSITION
		local ax, ay = anchorXY(def.anchor, W, H)
		tx, ty = ax + def.x, ay + def.y
	end
	return tx, ty, bw, bh
end

-- A row with no saved spot sits on its default one, worked out again on every
-- layout until it is moved: the rows stack over the bar (under it when there is no
-- room above), first in the bar's order nearest it; down rows stand side by side.
-- n = its place among the rows shown, cell / extra = a totem's size and the room
-- for its time text (UIParent units).
local function defaultSpot(n, down, cell, extra)
	local W, H = UIParent:GetWidth(), UIParent:GetHeight()
	local tx, ty, bw, bh = barBox()
	local left, right, top, bottom = tx - bw / 2, tx + bw / 2, ty + bh / 2, ty - bh / 2
	-- Show the Bar off: the rows start where the bar would be
	if SP:RowsHideBar() then top = bottom - ROW_GAP end
	local x, y
	if down then
		local tall = 6 * (cell + GAP)
		local above = top + ROW_GAP + tall <= H
		x = left + cell / 2 + (n - 1) * (cell + extra + ROW_GAP)
		y = above and (top + ROW_GAP + cell / 2) or (bottom - ROW_GAP - cell / 2)
		return x, y, { gx = "right", gy = above and "up" or "down" }
	end
	local rowH = cell + extra
	local above = top + 4 * (rowH + ROW_GAP) <= H
	local growLeft = tx / math.max(1, W) > 0.6
	x = growLeft and (right - cell / 2) or (left + cell / 2)
	if above then
		y = top + ROW_GAP + extra + cell / 2 + (n - 1) * (rowH + ROW_GAP)
	else
		y = bottom - ROW_GAP - cell / 2 - (n - 1) * (rowH + ROW_GAP)
	end
	return x, y, { gx = growLeft and "left" or "right", gy = above and "up" or "down" }
end

-- Put a row's spot down; returns its centre (UIParent units) and its direction.
local function placeSpot(r, n, down, cell, extra)
	local rec = SP.opt.rowsPositions and SP.opt.rowsPositions[r.element]
	local anchor = r.anchor
	anchor:SetSize(cell, cell)
	if type(rec) == "table" and rec.anchor then
		SP:ApplyPositionRecord(anchor, rec)
		local ax, ay = anchorXY(rec.anchor, UIParent:GetWidth(), UIParent:GetHeight())
		local cx, cy = ax + (rec.x or 0), ay + (rec.y or 0)
		local gx, gy = growFrom(rec, cx, cy)
		return cx, cy, gx, gy
	end
	local x, y, dir = defaultSpot(n, down, cell, extra)
	anchor:ClearAllPoints()
	anchor:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
	return x, y, dir.gx, dir.gy
end

-- ---------------------------------------------------------------------------
-- Pulling a totem back from a row (WoW: Forever; Totem Bar > Clicks), as on the bar.
-- Right-Click Pulls That Totem Back: right-click on any totem in a row pulls back that
-- element's totem, and the assign moves to Shift+Right-Click. Shift+Right-Click Pulls That
-- Totem Back: Shift+Right-Click pulls it back. With Swap Left and Right Click, left and right
-- trade places, as on the bar. The game's own secure "destroytotem" action on the element's
-- slot, so it works in a fight. A button's own clicks are kept and put back when the row lets
-- it go (or the setting goes off).
-- ---------------------------------------------------------------------------
-- Which mouse button: the ASSIGN click, never the cast click (an action bar key routed through the
-- flyout, RouteFlyoutBarKeys, and a Keybind Mode key on the button press the cast click; with a modifier
-- held WoW presses it too when that modifier's key is free, so even the shifted cast click is never
-- touched). Swap Left and Right Click mirrors it all, as on the bar: there the assign click is the left one.
local PULL_KEYS = {}
for _, n in ipairs({ "1", "2" }) do
	for _, k in ipairs({ "type", "spell", "macrotext", "totem-slot" }) do
		PULL_KEYS[#PULL_KEYS + 1] = k .. n
		PULL_KEYS[#PULL_KEYS + 1] = "shift-" .. k .. n
	end
end

-- "right": the assign click pulls back, the assign moves to Shift + that click; "shift": Shift + the
-- assign click pulls back.
local function pullMode()
	if SP.RightClickDestroysTotems and SP:RightClickDestroysTotems() then return "right" end
	if SP.ShiftRightClickPullsTotem and SP:ShiftRightClickPullsTotem() then return "shift" end
	return nil
end

-- a button's assign click as its number ("2" = right, "1" = left with the clicks swapped), read from the
-- button's OWN layout (a copy: its flyout button's), never the option: a profile switch can leave buttons
-- built the other way until they are rebuilt, and the cast click must never be the one taken
local function pullN(b)
	local src = b.spSource or b
	return (src:GetAttribute("assignButton") == "LeftButton") and "1" or "2"
end

-- (a pull-back click never runs the assign click's after-click)
local function pullPostClick(self, button)
	local pullButton = (self.spPullN == "1") and "LeftButton" or "RightButton"
	if button == pullButton then
		local shift = IsShiftKeyDown()
		if (self.spPullMode == "right" and not shift) or (self.spPullMode == "shift" and shift) then return end
	end
	local post = self.spPullPost
	if post then post(self, button) end
end

local function setPull(b, mode, slot, n)
	local saved = b.spPullSaved
	if saved then
		local key = (b.spPullMode == "right" and "type" or "shift-type") .. (b.spPullN or "2")
		if b:GetAttribute(key) ~= "destroytotem" then
			-- set up again since by a writer: what it wrote is the button's own now; where our overlay is
			-- still there untouched, the button's own value goes back (ours never becomes its own)
			local set = b.spPullSet
			if set then
				for _, k in ipairs(PULL_KEYS) do
					local mine = set[k]
					if mine ~= nil and mine ~= false and b:GetAttribute(k) == mine then b:SetAttribute(k, saved[k] or nil) end
				end
			end
			b.spPullSet = nil
		elseif b.spPullMode == mode and b.spPullSlot == slot and b.spPullN == n then
			return
		else
			-- its own first: only the keys the overlay set (a key it never touched stays as it is)
			for k in pairs(b.spPullSet or {}) do b:SetAttribute(k, saved[k] or nil) end
		end
		b.spPullSaved = nil
	end
	if not (mode and slot and n) then
		if b.spPullHooked then
			b:SetScript("PostClick", b.spPullPost)   -- (its own, or none)
			b.spPullHooked, b.spPullPost = nil, nil
		end
		b.spPullMode, b.spPullSlot, b.spPullSet, b.spPullN = nil, nil, nil, nil
		return
	end
	saved = {}
	for _, k in ipairs(PULL_KEYS) do saved[k] = b:GetAttribute(k) or false end
	b.spPullSaved = saved
	-- what we set (false: cleared), so a later writer's work is never mistaken for ours
	local set = {}
	if mode == "right" then
		set["shift-type" .. n], set["shift-spell" .. n], set["shift-macrotext" .. n] = saved["type" .. n], saved["spell" .. n], saved["macrotext" .. n]
		set["type" .. n], set["spell" .. n], set["macrotext" .. n], set["totem-slot" .. n] = "destroytotem", false, false, slot
	else
		set["shift-type" .. n], set["shift-spell" .. n], set["shift-macrotext" .. n], set["shift-totem-slot" .. n] = "destroytotem", false, false, slot
	end
	for k, v in pairs(set) do b:SetAttribute(k, v or nil) end
	b.spPullSet = set
	if not b.spPullHooked then
		b.spPullHooked, b.spPullPost = true, b:GetScript("PostClick")
		b:SetScript("PostClick", pullPostClick)
	end
	b.spPullMode, b.spPullSlot, b.spPullN = mode, slot, n
end

-- a row button's click lines while it pulls back (its tooltip, and the flyout button's own in the core)
function SP:RowPullTooltipLines(b)
	local swapped = b.spPullN == "1"
	local cast, other = swapped and "Right-click" or "Left-click", swapped and "Left-click" or "Right-click"
	local pull = "Pull this element's totem back"
	GameTooltip:AddLine("|cff00ff00" .. cast .. ":|r Cast totem", 1, 1, 1)
	if b.spPullMode == "right" then
		GameTooltip:AddLine("|cffffcc00" .. other .. ":|r " .. pull, 1, 1, 1)
		GameTooltip:AddLine("|cffffcc00Shift+" .. other:lower() .. ":|r Set as assigned totem", 1, 1, 1)
	else
		GameTooltip:AddLine("|cffffcc00" .. other .. ":|r Set as assigned totem", 1, 1, 1)
		GameTooltip:AddLine("|cffffcc00Shift+" .. other:lower() .. ":|r " .. pull, 1, 1, 1)
	end
end

-- ---------------------------------------------------------------------------
-- Pinning the buttons
-- ---------------------------------------------------------------------------
local function releaseButton(b, host, size)
	-- (Grid already took the buttons for its own rows: its pin and its showing stay)
	local grid = SP.GridActive and SP:GridActive()
	if not grid then b:SetAttribute("spGridPinned", nil) end
	setPull(b, nil)   -- (its own right-click back)
	b.spRowSlot = nil
	hideVisual(b)
	if b.spRowHome and b:GetParent() == host then
		b:SetParent(b.spRowHome)
		-- (a parent change takes the new parent's strata: the flyout's own, DIALOG, back)
		if b.spRowStrata then b:SetFrameStrata(b.spRowStrata) end
		if b.spRowLevel then b:SetFrameLevel(b.spRowLevel) end
	end
	b.spRowHome, b.spRowStrata, b.spRowLevel = nil, nil, nil
	if size then b:SetSize(size, size) end   -- (the flyout's own size back)
	if not grid then b:Hide() end
end

local function releaseRow(element)
	local r = rows[element]
	if not r then return end
	local button = SP.totemButtons and SP.totemButtons[element]
	local grid = SP.GridActive and SP:GridActive()
	if button and not grid then button.spGridPinned = nil end
	local flyout = SP.totemFlyouts and SP.totemFlyouts[element]
	local size = flyout and flyout.buttonSize
	if r.all and not r.pinned then
		for i = 1, #r.all do r.all[i]:Hide() end   -- (the row's own copies: the flyout was never taken)
	elseif r.all then
		for i = 1, #r.all do releaseButton(r.all[i], r.host, size) end
	end
	if r.box and not grid then
		-- the arrow flyout's watched box opens and closes by itself again (with Grid on, the box is Grid's:
		-- a profile switching to Grid lays Grid out before this runs)
		r.box:SetAttribute("unit", "none")
		RegisterUnitWatch(r.box)
		r.box:Hide()
	end
	r.all, r.box, r.count, r.shown, r.pinned = nil, nil, 0, false, nil
	r.host:Hide()
end

-- ---------------------------------------------------------------------------
-- Keep Flyouts on Main Totem Bar: the row's own buttons, copies of the flyout's (the
-- same cast and assign clicks, through the same secure helpers, and the flyout
-- button's own after-click), so the bar keeps its flyouts. Made out of combat; a
-- copy follows its flyout button whenever the rows are laid out again.
-- ---------------------------------------------------------------------------
local COPY_ATTRS = PULL_KEYS   -- (every click key: the source's own, the pull-back goes on after)

local function copyTooltip(self)
	if not (SP.opt and SP.opt.ShowTooltips) or not self.spellID then return end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetSpellByID(SPCompat.HighestKnownRank and SPCompat.HighestKnownRank(self.spellID) or self.spellID)
	GameTooltip:AddLine(" ")
	if self.spPullMode then
		SP:RowPullTooltipLines(self)
	elseif SP.opt.swapFlyoutClickButtons then
		GameTooltip:AddLine("|cff00ff00Left-click:|r Set as assigned totem", 1, 1, 1)
		GameTooltip:AddLine("|cffffcc00Right-click:|r Cast totem", 1, 1, 1)
	else
		GameTooltip:AddLine("|cff00ff00Left-click:|r Cast totem", 1, 1, 1)
		GameTooltip:AddLine("|cffffcc00Right-click:|r Set as assigned totem", 1, 1, 1)
	end
	GameTooltip:Show()
end

local function copyPostClick(self, button)
	local src = self.spSource
	local post = src and src:GetScript("PostClick")
	if post then post(self, button) end   -- (it reads self.totemIndex: the copy carries it)
end

local function copyButton(r, src)
	r.copies = r.copies or {}
	local b = r.copies[src]
	if not b then
		b = CreateFrame("Button", nil, r.host, "SecureActionButtonTemplate")
		b:RegisterForClicks("AnyUp", "AnyDown")
		b:SetSize(28, 28)
		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetAllPoints()
		local hl = b:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		hl:SetColorTexture(1, 1, 1, 0.3)
		hl:SetBlendMode("ADD")
		b:SetHighlightTexture(hl)   -- (the button's own highlight: Icon Shape shapes it with the icon)
		local cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
		cd:SetAllPoints(b.icon)
		cd:SetDrawSwipe(true)
		cd:SetDrawEdge(true)
		cd:SetSwipeColor(0, 0, 0, 0.8)
		cd:SetHideCountdownNumbers(true)
		if SP.StyleEngineCooldown then SP:StyleEngineCooldown(cd) end
		b.cooldown = cd
		local tf = CreateFrame("Frame", nil, b)
		tf:SetAllPoints(b)
		tf:SetFrameLevel(cd:GetFrameLevel() + 1)
		local t = tf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		if SP.AdoptSPFont then SP:AdoptSPFont(t, "timers") end
		t:SetPoint("CENTER", b, "CENTER", 0, 0)
		t:SetShadowOffset(1, -1)
		t:Hide()
		b.cooldownText = t
		b:HookScript("OnEnter", copyTooltip)
		b:HookScript("OnLeave", function() GameTooltip:Hide() end)
		b:SetScript("PostClick", copyPostClick)
		r.copies[src] = b
		r.copyAll = r.copyAll or {}
		r.copyAll[#r.copyAll + 1] = b
		newCopies = true
	end
	b.spSource = src
	b.totemIndex, b.spellID, b.talentSpellID = src.totemIndex, src.spellID, src.talentSpellID
	b.isDisabledInFlyout = src.isDisabledInFlyout
	for _, a in ipairs(COPY_ATTRS) do
		local v = src:GetAttribute(a)
		if b:GetAttribute(a) ~= v then b:SetAttribute(a, v) end
	end
	b.spPullSaved = nil   -- (its own right-click again: the pull-back goes on after)
	if src.icon then
		b.icon:SetTexture(src.icon:GetTexture())
		b.icon:SetTexCoord(src.icon:GetTexCoord())
		-- Icon Shape's trim comes with the coordinates, its mark too (or a stale one goes): back on
		-- Square, the shaping takes it off the copy as off the flyout's button
		b.icon.spTrimmed = src.icon.spTrimmed
	end
	local c = SP.opt and SP.opt.totemCooldownTextColor
	b.cooldownText:SetTextColor(c and c.r or 1, c and c.g or 1, c and c.b or 1)
	return b
end

-- true: this row uses copies (Keep Flyouts on Main Totem Bar, with the main bar showing)
local function keepFlyouts()
	local o = SP.opt
	return o and o.rowsKeepFlyouts == true and o.rowsShowBar ~= false or false
end

-- One row, out of combat. n = its place among the rows shown (default spots).
local function layoutRow(element, n)
	local r = rowFrames(element)
	local flyout = SP.totemFlyouts and SP.totemFlyouts[element]
	local button = SP.totemButtons and SP.totemButtons[element]
	if not (flyout and button and flyout.allButtons) then
		releaseRow(element)
		return false
	end
	local copies = keepFlyouts()
	if r.all and (r.pinned == true) == copies then releaseRow(element) end   -- (the other way round before)
	local all = flyout.allButtons
	if copies then
		-- the bar keeps its flyout: the row gets copies of the flyout's buttons
		local list = r.copyList or {}
		r.copyList = list
		wipe(list)
		if r.copies then for _, c in pairs(r.copies) do c:Hide() end end
		for i = 1, #all do list[#list + 1] = copyButton(r, all[i]) end
		all = list
		r.pinned = false
	else
		button.spGridPinned = true   -- the bar button opens no flyout: its choices are the row
		r.pinned = true
	end
	if not copies and r.all and r.all ~= all then
		-- the flyout was rebuilt: let go of the buttons that are no longer in it
		for i = 1, #r.all do
			local old, kept = r.all[i], false
			for j = 1, #all do if all[j] == old then kept = true break end end
			if not kept then releaseButton(old, r.host, flyout.buttonSize) end
		end
	end
	r.all = all
	if not copies and flyout.box and r.box ~= flyout.box then
		-- arrow flyouts: the buttons leave the watched box, which stays closed
		UnregisterUnitWatch(flyout.box)
		flyout.box:Hide()
		r.box = flyout.box
	end

	local o = SP.opt
	local S = rowButtonSize()
	local k = (o.buffscale or 0.9) * rowScale()
	local down = o.rowsGo == "down"
	local textOn = false   -- (no time text on the rows: the bar shows it)
	local textH, textW = 0, 0
	local host = r.host
	host:SetScale(k)
	if SP.autoButton then host:SetFrameStrata(SP.autoButton:GetFrameStrata()) end

	-- the totems that belong: as the flyout picks them (and Grid): switched on in the
	-- flyout settings, talent ones only while known, single pop-outs on their own
	local count = 0
	local mode = pullMode()
	local slot = mode and SP:TotemDestroySlot(element) or nil
	r.byIndex = r.byIndex or {}
	wipe(r.byIndex)
	for i = 1, #all do
		local b = all[i]
		if not copies then
			if b:GetParent() ~= host then
				b.spRowHome = b:GetParent()
				b.spRowStrata, b.spRowLevel = b:GetFrameStrata(), b:GetFrameLevel()
				b:SetParent(host)
			end
			if not b:GetAttribute("spGridPinned") then b:SetAttribute("spGridPinned", true) end
		end
		-- (never the flyout's "Empty" choice: a row is the element's totems, as in TotemTimers)
		local eligible = b.totemIndex ~= 0 and not b.isDisabledInFlyout
			and (not b.talentSpellID or SPCompat.KnowsSpellID(b.talentSpellID))
			and not SP:IsSingleTotemPoppedOut(element, b.totemIndex)
		if eligible then
			count = count + 1
			b.spRowSlot = count
			r.byIndex[b.totemIndex] = b
		else
			b.spRowSlot = nil
		end
		setPull(b, eligible and mode or nil, slot, mode and pullN(b) or nil)
	end
	r.count = count
	r.size = S

	-- the spot, the direction, and the row's corner on the spot
	local cell, extraU = S * k, (textOn and (down and textW or textH) or 0) * k
	local cx, cy, gx, gy = placeSpot(r, n, down, cell, extraU)
	local side = (cx / math.max(1, UIParent:GetWidth()) < 0.5) and "right" or "left"   -- a down row's time text
	r.gx, r.gy, r.side = gx, gy, side
	local length = math.max(1, count) * S + math.max(0, count - 1) * GAP
	local extra = textOn and (down and textW or textH) or 0
	if down then host:SetSize(S + extra, length) else host:SetSize(length, S + extra) end
	local corner
	if down then corner = (gy == "down" and "TOP" or "BOTTOM") .. (side == "right" and "LEFT" or "RIGHT")
	else corner = "TOP" .. (gx == "left" and "RIGHT" or "LEFT") end
	host:ClearAllPoints()
	host:SetPoint(corner, r.anchor, corner, 0, 0)

	local visible = wanted(element) and count > 0
	local alpha = rowAlpha()
	for i = 1, #all do
		local b = all[i]
		local slot = b.spRowSlot
		if slot then
			local along = (slot - 1) * (S + GAP)
			b:ClearAllPoints()
			if down then
				local x = (side == "right") and 0 or extra
				if gy == "down" then b:SetPoint("TOPLEFT", host, "TOPLEFT", x, -along)
				else b:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", x, along) end
			elseif gx == "left" then
				b:SetPoint("TOPRIGHT", host, "TOPRIGHT", -along, 0)
			else
				b:SetPoint("TOPLEFT", host, "TOPLEFT", along, 0)
			end
			b:SetSize(S, S)
			if b.icon then b.icon:SetAlpha(1); b.icon:SetDesaturated(false) end
			b:SetAlpha(alpha)
			hideVisual(b)   -- (a mark from an earlier build of this file)
			b:Show()
		else
			hideVisual(b)
			b:Hide()
		end
	end
	host:SetShown(visible)
	r.shown = visible
	if not copies then
		SP:PlaceFlyoutArrows(flyout)                 -- pinned: the bar button's arrow tabs hide
		if flyout.box then SP:DressFlyoutFrame(flyout) end
	end
	return visible
end

-- ---------------------------------------------------------------------------
-- Show the Bar off: the bar's own pieces stay hidden. Hooked on their OnShow, so
-- no layout pass can bring them back; Keybind Mode is let through.
-- ---------------------------------------------------------------------------
local function hideable(f)
	if not f then return false end
	if f == _G.ShamanPowerAutoDropAll and SP.IsDropAllPoppedOut and SP:IsDropAllPoppedOut() then return false end
	if f == _G.ShamanPowerEarthShieldBtn and SP.IsEarthShieldPoppedOut and SP:IsEarthShieldPoppedOut() then return false end
	if f.GetParent and SP.poppedOutFrames then
		local p = f:GetParent()
		for _, frame in pairs(SP.poppedOutFrames) do if p == frame then return false end end   -- in a pop-out
	end
	return true
end

local function onBarPieceShown(self)
	if SP:RowsHideBar() and not InCombatLockdown() and hideable(self) then self:Hide() end
end

local function eachBarPiece(fn)
	fn(SP.autoButton)
	for element = 1, 4 do fn(SP.totemButtons and SP.totemButtons[element]) end
	fn(_G.ShamanPowerAutoDropAll); fn(_G.ShamanPowerEarthShieldBtn)
	fn(_G.ShamanPowerTotemicCallBtn); fn(_G.ShamanPowerAutoTotemicCall); fn(_G.ShamanPowerCompactShieldBtn)
end

local function hookPiece(f)
	if f and f.HookScript and not f.spRowsShowHook then
		f.spRowsShowHook = true
		f:HookScript("OnShow", onBarPieceShown)
	end
end

local function hidePiece(f)
	if f and f:IsShown() and hideable(f) then f:Hide() end
end

local function hideBar()
	if InCombatLockdown() or not SP:RowsHideBar() then return end
	eachBarPiece(hookPiece)
	eachBarPiece(hidePiece)
	if SP.HideActiveTotemOverlaysForCompact then SP:HideActiveTotemOverlaysForCompact() end
end

-- ---------------------------------------------------------------------------
-- Carry: with Show Main Totem Bar off, the rows carry the bar's own pieces. Each row's
-- totem that is down gets the duration bar and the time left (Totem Bar > Duration
-- Bars), the pulse (the bar's own pulse, handed over as Blizzard's bar has it handed
-- over) and the totem effects (ShamanPowerCues); the party dots and range numbers sit on
-- the row at its assigned totem. The frame that follows the totem that is down is a
-- plain one of ours (it moves in a fight too); the dots' frame never moves in a fight
-- (on WoW: Forever the game draws the dots, and what it draws on cannot move there).
-- ---------------------------------------------------------------------------
local function carryFrames(r)
	local c = r.carry
	if c then return c end
	c = {}
	local h = CreateFrame("Frame", nil, r.host)
	h:EnableMouse(false)
	h:SetSize(28, 28)
	h:Hide()
	c.host = h
	c.bg = h:CreateTexture(nil, "OVERLAY", nil, 1)
	c.bg:SetColorTexture(0, 0, 0, 0.8)
	c.bar = h:CreateTexture(nil, "OVERLAY", nil, 2)
	c.text = h:CreateFontString(nil, "OVERLAY", nil, 3)
	SP:SetSPFont(c.text, "timers", 8, "OUTLINE")   -- (the font first: nothing is written before it)
	c.text:SetTextColor(1, 1, 1)
	local d = CreateFrame("Frame", nil, r.host)
	d:EnableMouse(false)
	d:SetSize(28, 28)
	c.dots = d
	r.carry = c
	return c
end

-- the duration bar and its text as the bar's Duration Bars settings place them (out of combat)
local function carryStyle(c, element, size)
	local opt = SP.opt
	local position, thickness = opt.durationBarPosition or "bottom", opt.durationBarHeight or 3
	c.size, c.thickness, c.position = size, thickness, position
	c.vertical = position == "left" or position == "right" or position == "top_vert" or position == "bottom_vert"
	local h, bg, bar, text = c.host, c.bg, c.bar, c.text
	bg:ClearAllPoints(); bar:ClearAllPoints(); text:ClearAllPoints()
	if position == "left" then bg:SetPoint("TOPRIGHT", h, "TOPLEFT", -1, 0)
	elseif position == "right" then bg:SetPoint("TOPLEFT", h, "TOPRIGHT", 1, 0)
	elseif position == "top_vert" then bg:SetPoint("BOTTOM", h, "TOP", 0, 1)
	elseif position == "bottom_vert" then bg:SetPoint("TOP", h, "BOTTOM", 0, -1)
	elseif position == "top" then bg:SetPoint("BOTTOMLEFT", h, "TOPLEFT", 0, 1)
	else bg:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -1) end
	bg:SetSize(c.vertical and thickness or size, c.vertical and size or thickness)
	bar:SetPoint(c.vertical and "BOTTOMLEFT" or "TOPLEFT", bg, c.vertical and "BOTTOMLEFT" or "TOPLEFT", 0, 0)
	local color = SP.DurationBarColors and SP.DurationBarColors[element]
	if color then SP:SetSPBarColor(bar, "duration", color[1], color[2], color[3], 1) end
	-- Duration Bar Opacity and Duration Bar Background (General > Themes too), as the bar's own
	local a = opt.durationBarOpacity or 1
	bg:SetAlpha(SP:DurationTrackAlpha(a))
	bar:SetAlpha(a)
	SP:SetSPFont(text, "timers", opt.durationTextSize or 8, "OUTLINE")
	SP:ThemePaintDurationText(text, element)   -- General > Themes: Duration Text Color; white on Standard
	c.location = opt.durationTextLocation or "none"
	if c.location == "inside_top" then text:SetPoint("TOP", bg, "TOP", 0, -1)
	elseif c.location == "inside_bottom" then text:SetPoint("BOTTOM", bg, "BOTTOM", 0, 1)
	elseif c.location == "above" then
		if position == "left" then text:SetPoint("RIGHT", bg, "LEFT", -1, 0)
		elseif position == "right" then text:SetPoint("LEFT", bg, "RIGHT", 1, 0)
		else text:SetPoint("BOTTOM", bg, "TOP", 0, 1) end
	elseif c.location == "below" then
		if position == "left" then text:SetPoint("LEFT", bg, "RIGHT", 1, 0)
		elseif position == "right" then text:SetPoint("RIGHT", bg, "LEFT", -1, 0)
		else text:SetPoint("TOP", bg, "BOTTOM", 0, -1) end
	else text:SetPoint("CENTER", h, "CENTER", 0, 0) end
	c.secs = false
end

-- the pulse: the bar's own pulse for this element, handed over to the row (and back)
local function carryPulseOn(element, c)
	if not (SP.pulseOverlays and element <= 3) then return end
	if not c.pulse and SP.CreatePulseOverlay then
		c.pulse = SP:CreatePulseOverlay(c.host)
		if c.pulse and SP.ThemePaintPulse then SP:ThemePaintPulse(c.pulse, element) end
	end
	local cur = SP.pulseOverlays[element]
	if c.pulse and cur ~= c.pulse then
		c.savedPulse = cur
		if cur and SP.PulseVisualStop then SP:PulseVisualStop(cur) end
		SP.pulseOverlays[element] = c.pulse
	end
end

local function carryPulseOff(element, c)
	if not (c.pulse and SP.pulseOverlays) then return end
	if SP.pulseOverlays[element] == c.pulse then
		if SP.PulseVisualStop then SP:PulseVisualStop(c.pulse) end
		SP.pulseOverlays[element] = c.savedPulse
		-- (the bar had none yet: it builds its own again)
		if not c.savedPulse and SP.SetupPulseOverlays then SP:SetupPulseOverlays() end
	end
	c.savedPulse = nil
end

-- each row's carried pieces on or off (out of combat), the dots moved over. Reconciled row by row, every
-- layout: a row switched on (or off) while the others already carry gets (or gives back) its own pieces.
local function setCarry(on)
	local changed = (on ~= carrying)
	carrying = on
	for element = 1, 4 do
		local r = rows[element]
		local want = on and r ~= nil and r.host ~= nil and r.all ~= nil and (r.count or 0) > 0 or false
		local c = r and (want and carryFrames(r) or r.carry)
		if c and want and not c.active then
			c.active = true
			carryPulseOn(element, c)
			changed = true
		elseif c and not want and c.active then
			c.active = nil
			carryPulseOff(element, c)
			c.host:Hide()
			c.on, c.last, c.anchor = nil, nil, nil
			changed = true
		end
	end
	if not changed then return end
	if SP.RefreshPartyRangeHosts then SP:RefreshPartyRangeHosts() end   -- the dots and range numbers move over
	if SP.UpdatePulseBarPositions then SP:UpdatePulseBarPositions() end
	if SP.UpdateTotemProgressBarPositions then SP:UpdateTotemProgressBarPositions() end   -- (the duration tick on)
end

-- each layout while carrying: the dots' spot on the row's assigned totem (or its first), the duration look
local function carryLayout(element, r)
	local c = r.carry
	if not (carrying and c and c.active) then return end
	local S = r.size or 28
	c.host:SetSize(S, S)
	c.host:SetFrameLevel(r.host:GetFrameLevel() + 8)
	carryStyle(c, element, S)
	local assigned = SP:AssignedIndex(element)
	local b = r.byIndex and (r.byIndex[assigned] or nil)
	if not b then
		for i = 1, #r.all do if r.all[i].spRowSlot == 1 then b = r.all[i] break end end
	end
	c.dots:ClearAllPoints()
	c.dots:SetSize(S, S)
	if b then c.dots:SetPoint("CENTER", b, "CENTER", 0, 0) end
	c.anchor = b   -- (the effects' Test button, with no totem down)
	c.dots:SetFrameLevel(r.host:GetFrameLevel() + 9)
	-- the rows' fade: the pieces fade with the row's icons (siblings of them, never multiplied twice)
	local a = rowAlpha()
	c.host:SetAlpha(a)
	c.dots:SetAlpha(a)
	if c.pulse then
		c.pulse.buttonWidth, c.pulse.buttonHeight = S - 4, S - 4
		if c.pulse.wipeFrame then c.pulse.wipeFrame:SetFrameLevel(c.host:GetFrameLevel() + 2) end
		if SP.ThemePaintPulse then SP:ThemePaintPulse(c.pulse, element) end
		if SP.PositionPulseWipe then SP:PositionPulseWipe(c.pulse) end
	end
	c.on, c.last = nil, nil   -- (placed again on the next update)
end

-- No tables, closures, formatting or frame geometry reads here: the bar's duration tick runs it 10 times
-- a second while a totem is down. A label is only written when its whole second changes.
function SP:UpdateRowsCarry()
	if not (applied and carrying) then return end
	local now = GetTime()
	for element = 1, 4 do
		local r = rows[element]
		local c = r and r.shown and r.carry
		if c and c.active then
			local have, _, start, duration = self:GetElementTotemInfo(element)
			local valid = not secret(have) and have == true and not secret(start) and type(start) == "number"
				and not secret(duration) and type(duration) == "number" and duration > 0 and start + duration > now
			local idx = valid and self:GetActiveTotemIndex(element) or nil
			local b = idx and r.byIndex and r.byIndex[idx] or nil
			if b ~= c.on then
				c.on = b
				local h = c.host
				h:ClearAllPoints()
				if b then
					-- (a plain frame of ours: it follows the totem that is down, in a fight too)
					h:SetPoint("CENTER", b, "CENTER", 0, 0)
					h:Show()
					c.last = b
				else
					h:Hide()
				end
				c.secs = false
			end
			if b then
				local remaining = start + duration - now
				local length = math.max(1, c.size * math.min(1, remaining / duration))
				local showBar = c.position ~= "none"
				c.bar:SetSize(c.vertical and c.thickness or length, c.vertical and length or c.thickness)
				c.bg:SetShown(showBar); c.bar:SetShown(showBar)
				local secs = c.location ~= "none" and math.floor(remaining) or nil
				if secs ~= c.secs then
					c.secs = secs
					if secs then c.text:SetText(SP.FormatDuration(secs)); c.text:Show() else c.text:Hide() end
				end
			end
		end
	end
end

-- the row's button of the totem that is down, for the effects (ShamanPowerCues)
function SP:RowsCarryButton(element)
	if not carrying then return nil end
	local r = rows[element]
	local c = r and r.shown and r.carry
	return c and c.active and (c.on or c.last or c.anchor) or nil
end

-- true while the rows carry the bar's pieces
function SP:RowsCarryBar() return applied and carrying or false end

-- Keep Flyouts on Main Totem Bar: every copy a row has made, for the look painters (General > Themes'
-- Element-Colored Borders on the flyouts, Icon Shape, Minimal's boxes, Cooldown Text Color), which paint
-- them as the flyout's own buttons
function SP:RowsCopies(element)
	local r = rows[element]
	return r and r.copyAll or nil
end

-- the party dots and range numbers: on the row while it carries them (PartyRange, the core's dot placing)
local baseOverlayHost = SP.GetTotemOverlayHost
function SP:GetTotemOverlayHost(element)
	if carrying then
		local r = rows[element]
		local c = r and r.carry
		if c and c.active then return c.dots end
	end
	if baseOverlayHost then return baseOverlayHost(self, element) end
	return self.totemButtons and self.totemButtons[element]
end

-- ---------------------------------------------------------------------------
-- Apply / restore
-- ---------------------------------------------------------------------------
local function returnElement(element)
	local key = KEYS[element]
	if SP.poppedOutFrames[key] then SP:ReturnPopOutToBar(key) end
	if SP.opt.poppedOut then SP.opt.poppedOut[key] = nil end
	local button = SP.totemButtons[element]
	if button and button:GetParent() ~= UIParent then
		button:SetParent(UIParent)
		button:SetScale(SP.opt.buffscale or 0.9)
	end
end

local function apply()
	local o = SP.opt
	local entering = not applied
	o.poppedOut = o.poppedOut or {}
	-- the element pop-outs wait: what was popped out comes back when Totem Rows is off
	if not o.rowsRestorePopouts then
		o.rowsRestorePopouts = {}
		for element = 1, 4 do o.rowsRestorePopouts[element] = o.poppedOut[KEYS[element]] == true end
	end
	for element = 1, 4 do
		if SP.poppedOutFrames[KEYS[element]] or o.poppedOut[KEYS[element]] then returnElement(element) end
	end
	owner, applied = o, true
	-- the rows are the flyouts' buttons: build any flyout still missing
	local missing = false
	for element = 1, 4 do
		if SP:IsElementShown(element) and not (SP.totemFlyouts and SP.totemFlyouts[element]) then missing = true end
	end
	if entering or missing then SP:SetupTotemFlyouts() end
	-- each row in the bar's order (its default spot: first nearest the bar); a row
	-- switched off hands its buttons back to the element's own flyout
	local order = o.totemBarOrder or { 1, 2, 3, 4 }
	local off = type(o.rowsOff) == "table" and o.rowsOff or {}
	local n, pinsChanged, released = 0, entering, nil
	for i = 1, 4 do
		local element = order[i] or i
		local r = rows[element]
		local held = r ~= nil and r.all ~= nil
		local wasPinned = r ~= nil and r.pinned == true
		if off[element] then
			if held then
				releaseRow(element)
				pinsChanged = true
				released = released or {}
				released[#released + 1] = element
			end
		else
			if SP:IsElementShown(element) then n = n + 1 end
			layoutRow(element, math.max(1, n))
			if not held and rows[element].all then pinsChanged = true end
			if held and wasPinned and rows[element].pinned == false then
				-- (Keep Flyouts on Main Totem Bar turned on: the flyout has its buttons back)
				pinsChanged = true
				released = released or {}
				released[#released + 1] = element
			elseif held and not wasPinned and rows[element].pinned then
				pinsChanged = true
			end
		end
	end
	if pinsChanged then
		-- the bar buttons whose choices are rows open no flyout; their right-click is
		-- Totemic Call again (or the corner totem / pull back, as Totem Bar > Clicks sets it)
		SP:UpdateTotemFlyoutEnabled()
	end
	if released then
		for _, element in ipairs(released) do
			SP:UpdateFlyoutVisibility(element)
			SP:MarkAssignedInFlyout(element)
		end
	end
	-- Show Main Totem Bar off: the rows carry the bar's pieces
	setCarry(SP:RowsHideBar())
	for element = 1, 4 do
		local r = rows[element]
		if r then carryLayout(element, r) end
	end
	if carrying and SP.UpdatePartyDotPositions then SP:UpdatePartyDotPositions() end
	SP:UpdateRowsCarry()
	hideBar()
	-- SetupTotemFlyouts above lays the bar's buttons out and shows them: a bar that is down right now goes
	-- back down, as the layout leaves it (switched off, not used in this kind of group, or kept down by Hide
	-- Out of Combat / Hide When No Totems). Keybind Mode's bar stays up; Blizzard's bar puts ours down itself.
	if not InCombatLockdown() and not (SP.UsingBlizzardTotemBar and SP:UsingBlizzardTotemBar())
		and not (SP.KeybindModeActive and SP:KeybindModeActive())
		and (not SP:TotemBarInUse() or (SP.totemBarHidden and (o.hideOutOfCombat or o.hideWhenNoTotems))) then
		SP:SetTotemBarFramesShown(false)
	end
	if newCopies then   -- (new copies on the rows: the looks General > Themes gives the flyout's own buttons)
		newCopies = false
		if SP.ApplyIconShapes then SP:ApplyIconShapes() end
		if SP.ThemePaintTotemBorders then SP:ThemePaintTotemBorders() end
		if SP.ThemeBoxesRefresh then SP:ThemeBoxesRefresh() end
	end
	if SP.RefreshUnlockBoxes then SP:RefreshUnlockBoxes() end   -- (Unlock UI open: the boxes follow)
end

local function restore()
	local o = SP.opt
	setCarry(false)   -- (the pieces back on the bar first)
	applied = false
	for element = 1, 4 do releaseRow(element) end
	local snapshot = o and o.rowsRestorePopouts
	if o then o.rowsRestorePopouts = nil end
	owner = nil
	-- the bar back (Show the Bar) and its flyouts opening on hover again
	SP:UpdateLayout()
	SP:UpdateTotemFlyoutEnabled()
	for element = 1, 4 do
		SP:UpdateFlyoutVisibility(element)
		SP:MarkAssignedInFlyout(element)
	end
	SP:UpdateActiveTotemOverlays()
	if snapshot then
		for element = 1, 4 do
			if snapshot[element] then SP:PopOutElementWithFlyout(element) end
		end
	end
end

function SP:RefreshRowsStyle()
	if refreshing then return end
	if not (self.opt and self.autoButton and self.player and self.totemButtons and self.totemButtons[1]) then return end
	if not requested() and not applied and not self.opt.rowsRestorePopouts then return end
	if InCombatLockdown() then pending = true; return end
	refreshing, pending = true, false
	local ok, err = pcall(function()
		if owner and owner ~= self.opt then
			-- a profile change: the old profile keeps its own snapshot (never copied here). The bar's
			-- pieces go back to the bar first (pulse, dots, duration), as when the switch goes off.
			setCarry(false)
			applied, owner = false, nil
			for element = 1, 4 do releaseRow(element) end
			if not requested() then
				self:UpdateLayout()
				self:UpdateTotemFlyoutEnabled()
				for element = 1, 4 do self:UpdateFlyoutVisibility(element) end
				return
			end
		end
		if requested() then apply() elseif applied or self.opt.rowsRestorePopouts then restore() end
	end)
	refreshing = false
	if not ok then geterrorhandler()(err) end
end

-- Totem Rows' switch (Totem Bar > Style, and the setup tour).
function SP:SetTotemRows(on)
	if InCombatLockdown() or not self.opt then return false end
	self.opt.totemRows = on and true or nil
	self:RefreshRowsStyle()
	if not on then self:UpdateLayout() end   -- (the bar's flyouts and its own look back at once)
	return true
end

-- Grid is about to take the flyouts' buttons for its own rows: let go of them now (the
-- switch stays on; the rows come back when Grid is left)
function SP:RowsLetGo()
	if not applied or InCombatLockdown() then return end
	refreshing = true
	local ok, err = pcall(restore)
	refreshing = false
	if not ok then geterrorhandler()(err) end
end

local function runQueued()
	queued = false
	SP:RefreshRowsStyle()
end

local function queueRefresh()
	if queued or refreshing then return end
	if not (applied or requested() or (SP.opt and SP.opt.rowsRestorePopouts)) then return end
	if InCombatLockdown() then pending = true; return end
	queued = true
	C_Timer.After(0, runQueued)
end
SP.QueueRowsRefresh = queueRefresh

-- ---------------------------------------------------------------------------
-- Settings and Unlock UI
-- ---------------------------------------------------------------------------
-- A row's spot for Unlock UI (nil while the row is switched off or empty: no box for it).
-- Unlock UI opening: a row the bar's hide rules keep down comes up first, to be placed.
function SP:GetTotemRowAnchor(element)
	local r = rows[element]
	if not (applied and r and r.all) then return nil end
	if not r.shown and self.IsMasterUnlocked and self:IsMasterUnlocked() and not InCombatLockdown() and not refreshing then
		self:RefreshRowsStyle()
	end
	return r.shown and r.anchor or nil
end

-- Unlock UI dropped (or nudged) a row: keep its spot and the way it opens.
function SP:SaveTotemRowPosition(element)
	local r = rows[element]
	if not (applied and r) or InCombatLockdown() then return end
	local rec = self:GetPositionRecord(r.anchor)
	if not rec then return end
	local o = self.opt
	o.rowsPositions = type(o.rowsPositions) == "table" and o.rowsPositions or {}
	local old = o.rowsPositions[element]
	local ax, ay = anchorXY(rec.anchor, UIParent:GetWidth(), UIParent:GetHeight())
	rec.gx, rec.gy = growFrom(type(old) == "table" and old or { gx = r.gx, gy = r.gy }, ax + rec.x, ay + rec.y)
	o.rowsPositions[element] = rec
	self:RefreshRowsStyle()
end

-- Unlock UI's Reset on a row's box: back on its default spot over the bar.
function SP:ResetTotemRowPosition(element)
	if InCombatLockdown() or not self.opt then return end
	if type(self.opt.rowsPositions) == "table" then self.opt.rowsPositions[element] = nil end
	self:RefreshRowsStyle()
end

-- Row Icon Size (Totem Bar > Style, and the mouse wheel on a row's box).
function SP:SetTotemRowsScale(v)
	if InCombatLockdown() or not self.opt then return end
	v = tonumber(v) or 1
	v = math.max(0.5, math.min(2, v))
	self.opt.rowsScale = (math.abs(v - 1) > 0.001) and v or nil
	self:RefreshRowsStyle()
end

-- The shown row buttons, for the fade's glide (fadeFrames in ShamanPower.lua).
function SP:RowsFadeFrames(add)
	if not applied then return end
	for element = 1, 4 do
		local r = rows[element]
		local all = r and r.shown and r.all
		if all then for i = 1, #all do if all[i].spRowSlot then add(all[i]) end end end
		-- the bar's pieces on the row (Show Main Totem Bar off) fade with its icons
		local c = all and carrying and r.carry
		if c and c.active then add(c.host); add(c.dots) end
	end
end

function SP:ApplyTotemRowAlpha()
	if not applied then return end
	local a = rowAlpha()
	for element = 1, 4 do
		local r = rows[element]
		local all = r and r.all
		if all then for i = 1, #all do if all[i].spRowSlot then all[i]:SetAlpha(a) end end end
		local c = carrying and r and r.carry
		if c and c.active then c.host:SetAlpha(a); c.dots:SetAlpha(a) end
	end
end

-- ---------------------------------------------------------------------------
-- Hooks: lifecycle only, never a tick. All callbacks are made once.
-- ---------------------------------------------------------------------------
-- The flyouts were built, rebuilt or resized, the bar was laid out again (an
-- element shown or hidden, its size, a pop-out): lay the rows out again, once,
-- on the next frame.
-- The bar moved (dropped, nudged, reset, its style's own spot): rows still on their
-- default spots follow it.
for _, name in ipairs({ "SetupTotemFlyouts", "RecreateTotemFlyouts", "RebuildTotemFlyout", "AddMissingFlyoutButtons",
	"ApplyTotemFlyoutButtonSize", "UpdateTotemFlyoutEnabled", "UpdateLayout", "UpdateMiniTotemBar",
	"PopOutSingleTotem", "ReturnPopOutToBar", "SaveFramePosition", "ResetBarPositions", "RestoreTotemBarPosition" }) do
	if SP[name] then hooksecurefunc(SP, name, queueRefresh) end
end

-- Blizzard's bar keeps the pulse it finds as the one to give back: never ours
if SP.RefreshBlizzardTotemBar then
	local baseRefresh = SP.RefreshBlizzardTotemBar
	SP.RefreshBlizzardTotemBar = function(self, ...)
		if carrying and self.opt and self.opt.useBlizzardTotemBar and not InCombatLockdown() then setCarry(false) end
		return baseRefresh(self, ...)
	end
end

-- The flyout buttons' clicks written again by the core (Swap Flyout Click Buttons, Close Flyout After
-- Casting From It): the rows' pull-back comes off first, so the writer writes the buttons' own clicks and
-- never ours, and goes back on with the copies on the next layout (restore, write, reapply). Out of combat
-- only, as both writers are.
local function pullsOff()
	for element = 1, 4 do
		local r = rows[element]
		if r and r.all then
			for i = 1, #r.all do
				if r.all[i].spPullMode then setPull(r.all[i], nil) end
			end
		end
	end
end
for _, name in ipairs({ "UpdateFlyoutClickBehavior", "ApplyFlyoutPickMacros" }) do
	local base = SP[name]
	if base then
		SP[name] = function(self, ...)
			local strip = applied and not InCombatLockdown()
			if strip then pullsOff() end
			local a, b, c = base(self, ...)
			if strip then queueRefresh() end
			return a, b, c
		end
	end
end

-- cast-order clients: a row's pull-back follows the element's slot between fights, as the bar's does
if SP.RefreshTotemDestroySlots then
	hooksecurefunc(SP, "RefreshTotemDestroySlots", function(self)
		if not (applied and self.dynamicTotemSlots) or InCombatLockdown() then return end
		for element = 1, 4 do
			local r = rows[element]
			if r and r.all then
				local slot = self:TotemDestroySlot(element)
				for i = 1, #r.all do
					local b = r.all[i]
					if b.spPullMode and b.spPullSlot ~= slot then
						local key = (b.spPullMode == "right" and "totem-slot" or "shift-totem-slot") .. (b.spPullN or "2")
						b:SetAttribute(key, slot)
						if b.spPullSet then b.spPullSet[key] = slot end
						b.spPullSlot = slot
					end
				end
			end
		end
	end)
end

-- the copies' cooldowns, as the flyout's buttons get theirs (only shown ones: a read builds a table on WoW: Forever).
-- The reader is SPCompat's, as the core's own (on WoW: Forever a fight hides cooldown numbers from addons; it
-- answers from the player's own casts then, never with a hidden number), asked at the call: never the global.
if SP.UpdateTotemCooldowns then
	hooksecurefunc(SP, "UpdateTotemCooldowns", function(self)
		if not applied then return end
		local engine = self.EngineCooldownsOn and self:EngineCooldownsOn()
		for element = 1, 4 do
			local r = rows[element]
			if r and r.shown and r.pinned == false and r.all then
				for i = 1, #r.all do
					local b = r.all[i]
					if b.spRowSlot and b.spellID and b:IsVisible() then
						local read = (SPCompat and SPCompat.GetSpellCooldown) or GetSpellCooldown
						local start, duration, enabled = read(b.spellID)
						if secret(start) or secret(duration) or secret(enabled) then start, duration, enabled = nil, nil, nil end
						if engine then
							local estimate = start and duration and duration > 1.5 and enabled == 1
							self:FeedEngineCooldown(b, b.spellID, self:EngineCooldownRunning(b, b.spellID, estimate))
						elseif start and duration and duration > 1.5 and enabled == 1 then
							self:ApplyTotemCooldownVisual(b, start, duration)
							self._totemCdShown = true
							local remaining = start + duration - GetTime()
							if remaining > 0 and self.opt.totemCooldownText ~= false then
								if remaining >= 60 then b.cooldownText:SetFormattedText("%dm", math.ceil(remaining / 60))
								elseif remaining >= 10 then b.cooldownText:SetFormattedText("%d", math.floor(remaining))
								else b.cooldownText:SetFormattedText("%.1f", remaining) end
								b.cooldownText:Show()
							else
								b.cooldownText:Hide()
							end
						else
							self:ClearTotemCooldownVisual(b)
							b.cooldownText:Hide()
						end
					end
				end
			end
		end
	end)
end

-- the carried pieces follow every totem (the bar's own 10 fps duration tick, asleep with no totem down)
local function afterTotem()
	if carrying and applied and not SP:IsOff() then SP:UpdateRowsCarry() end
end
for _, name in ipairs({ "PLAYER_TOTEM_UPDATE", "UNIT_SPELLCAST_SUCCEEDED", "UpdateTotemProgressBars" }) do
	if SP[name] then hooksecurefunc(SP, name, afterTotem) end
end

-- The hide and fade rules: the rows come and go with the bar (out of combat; in a
-- fight only the fade can change, and alpha is never protected).
if SP.UpdateTotemBarVisibility then
	hooksecurefunc(SP, "UpdateTotemBarVisibility", function()
		if not applied or refreshing or InCombatLockdown() then return end
		local changed = false
		for element = 1, 4 do
			local r = rows[element]
			if r and r.all and ((wanted(element) and r.count > 0) ~= r.shown) then changed = true break end
		end
		-- (combat start lands here before the lockdown: the rows can still be shown)
		if changed then SP:RefreshRowsStyle() end
		if SP:RowsHideBar() then hideBar() end
	end)
end
-- Unlock UI closed (Done, Escape, a fight starting before the lockdown): the rows it brought
-- up go back to what the bar's rules say
if SP.HideBarMover then
	hooksecurefunc(SP, "HideBarMover", function(_, key)
		if not applied or type(key) ~= "string" or not key:find("^unlock_rows_") then return end
		if InCombatLockdown() then pending = true else SP:RefreshRowsStyle() end
	end)
end
-- the flyout opacity setting sets every flyout button, the rows too: a faded row goes back to the fade
if SP.UpdateTotemFlyoutOpacity then
	hooksecurefunc(SP, "UpdateTotemFlyoutOpacity", function() if applied then SP:ApplyTotemRowAlpha() end end)
end
-- Duration Bar Opacity / Duration Bar Background changed (the setting, or a theme picked): the rows' duration
-- bars follow, as the bar's do
if SP.ApplyDurationBarOpacity then
	hooksecurefunc(SP, "ApplyDurationBarOpacity", function(self)
		local a = self.opt and self.opt.durationBarOpacity or 1
		for element = 1, 4 do
			local c = rows[element] and rows[element].carry
			if c then
				c.bg:SetAlpha(self:DurationTrackAlpha(a))
				c.bar:SetAlpha(a)
			end
		end
	end)
end

-- Keybind Mode with Show the Bar off: the bar comes up for the length of the mode,
-- so its buttons can take keys; closing the mode re-runs SetupKeybindings.
if SP.SetKeybindMode then
	hooksecurefunc(SP, "SetKeybindMode", function(self, on)
		if on and applied and self.opt.rowsShowBar == false and self.KeybindModeActive and self:KeybindModeActive()
			and not InCombatLockdown() then
			self:SetTotemBarFramesShown(true)
			self:UpdateMiniTotemBar()
		elseif not on and applied and SP:RowsHideBar() ~= carrying then
			-- (closed: the rows carry the bar's pieces again, with the bar hidden; at once when a fight starting
			-- closed it, before the lockdown, or the fight would run with the pieces nowhere)
			if InCombatLockdown() then queueRefresh() else SP:RefreshRowsStyle() end
		end
	end)
end
if SP.SetupKeybindings then
	hooksecurefunc(SP, "SetupKeybindings", function()
		if not applied then return end
		-- (Keybind Mode closing lands here too: the pieces go back on the rows, at once while the game still
		-- allows it; a fight starting closes the mode just before its lockdown)
		if SP:RowsHideBar() ~= carrying then
			if InCombatLockdown() then queueRefresh() else SP:RefreshRowsStyle() end
		end
		hideBar()
	end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("SPELLS_CHANGED")
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_REGEN_ENABLED" then
		if pending then queueRefresh() end
		if applied then hideBar() end
		return
	end
	if pending or applied or requested() then queueRefresh() end
end)
