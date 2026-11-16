-- ============================================================================
-- Quick Totems (3.0.9.14; mockups A109 + A110, Endorian's ask on Discord 11-13)
--
-- Up to two small buttons at each element button's corners, each dropping a totem
-- of that element the player picked (Totem Bar > Bar: a totem's right-click menu,
-- Quick Totem). The main totem stays as it is. One pair per element, whatever the
-- main totem is (and on WoW: Forever for all three Calls).
--
-- Where (A110): right against the button, on the side away from the flyouts by
-- default (Auto). Everything else on that side (duration bars, pulse timers, the
-- dropped-totem icon, time text, party dots, the flyout) steps out past them: their
-- room goes into the room each side of a button already has for the flyout tab
-- (ShamanPower:FlyoutArrowPads). Picked on the flyout's side, they keep the tab's
-- room even out of a fight, so nothing on the bar moves when a fight starts.
--
-- They are click-to-cast buttons, so a fight freezes them: made, shown, hidden and
-- placed out of combat only (a change in a fight waits for its end). In a fight only
-- their looks change: lit in the element's color with the time left while their
-- totem is down, and the flyout buttons' cooldown look while it cools down.
--
-- Off by default. On the Normal, TotemTimers, Single Totem and Dynamic styles; not
-- Compact, Grid, Dropped Totems, Blizzard's Totem Bar, or with Totem Rows on.
-- Costs nothing while off: no frame is made, no event is listened to.
-- ============================================================================

local SP = ShamanPower
if not SP then return end

local QT = {}
SP.QuickTotemsModule = QT

local secret = issecretvalue or function() return false end
local ELEMENT_KEYS = { "earth", "fire", "water", "air" }
-- a side as the flyout code names it
local FLY = { above = "top", below = "bottom", left = "left", right = "right" }
local AWAY = { top = "below", bottom = "above", left = "right", right = "left" }

local sets = {}          -- [element] = { [1] = button, [2] = button } (made the first time they are wanted)
local madeOf = {}        -- [element] = the made buttons in a list (the look painters walk it)
local all = {}           -- every made button (the cooldown pass)
local active = false     -- any quick totem on screen
local pending = false    -- a change asked for in a fight: laid out when it ends
local listening = false

local function O() return SP.opt end
local function isShaman() return select(2, UnitClass("player")) == "SHAMAN" end

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------
function SP:QuickTotemsWanted()
	local o = O()
	return o and o.quickTotems == true and isShaman() or false
end

-- the styles they go with (A109 Q7, and the owner 11-14: the ones that do not show every totem already)
function SP:QuickTotemsStyleOK()
	if self.IsOff and self:IsOff() then return false end
	if self.CompactActive and self:CompactActive() then return false end
	if self.GridActive and self:GridActive() then return false end
	if self.UsingBlizzardTotemBar and self:UsingBlizzardTotemBar() then return false end
	if self.DroppedActive and self:DroppedActive() then return false end
	if self.RowsActive and self:RowsActive() then return false end
	return true
end

-- the totem (its index in the element's list) in a quick spot, or nil
function SP:QuickTotemPick(element, slot)
	local p = O() and O().quickTotemPicks
	local e = type(p) == "table" and p[ELEMENT_KEYS[element]]
	return type(e) == "table" and e[slot] or nil
end

-- the quick spot a totem holds: 0 (none), 1 or 2
function SP:QuickTotemSlotOf(element, totemIndex)
	for slot = 1, 2 do
		if self:QuickTotemPick(element, slot) == totemIndex then return slot end
	end
	return 0
end

-- put a totem in a quick spot (0: out of both). One totem per spot: a new pick takes the spot over.
function SP:SetQuickTotemSlot(element, totemIndex, slot)
	local o = O()
	if not (o and ELEMENT_KEYS[element] and totemIndex) then return end
	if type(o.quickTotemPicks) ~= "table" then o.quickTotemPicks = {} end
	local key = ELEMENT_KEYS[element]
	local e = type(o.quickTotemPicks[key]) == "table" and o.quickTotemPicks[key] or {}
	for s = 1, 2 do
		if e[s] == totemIndex then e[s] = nil end
	end
	if slot == 1 or slot == 2 then e[slot] = totemIndex end
	o.quickTotemPicks[key] = next(e) and e or nil
	if not next(o.quickTotemPicks) then o.quickTotemPicks = nil end
	self:QuickTotemsChanged()
end

-- ---------------------------------------------------------------------------
-- The buttons
-- ---------------------------------------------------------------------------
local function spellNameOf(spellID)
	local name = spellID and GetSpellInfo(spellID)
	if spellID and SPCompat.HasTotemCastAliases and SPCompat.HasTotemCastAliases(spellID) then name = SPCompat.TotemCastName(spellID) end
	return name
end

local function onEnter(self)
	if not (SP.opt and SP.opt.ShowTooltips) or not self.spellID then return end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetSpellByID(SPCompat.HighestKnownRank and SPCompat.HighestKnownRank(self.spellID) or self.spellID)
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("|cff00ff00Click:|r Drop this totem (Quick Totem " .. (self.spSlot or 1) .. ")", 1, 1, 1)
	GameTooltip:Show()
end
local function onLeave() GameTooltip:Hide() end

local function make(element, slot)
	local btn = SP.totemButtons and SP.totemButtons[element]
	if not btn or InCombatLockdown() then return nil end
	local name = "ShamanPowerQuickTotem" .. element .. "_" .. slot
	local q = _G[name] or CreateFrame("Button", name, btn, "SecureActionButtonTemplate, SecureHandlerEnterLeaveTemplate")
	q:SetParent(btn)
	q:Hide()
	q:RegisterForClicks("AnyUp", "AnyDown")
	q.element, q.spSlot = element, slot

	-- the look of a flyout button: the icon, a highlight, the cooldown sweep with its numbers above it
	local icon = q:CreateTexture(name .. "Icon", "ARTWORK")
	icon:SetAllPoints()
	q.icon = icon
	local hl = q:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 1, 1, 0.3)
	hl:SetBlendMode("ADD")

	local cd = CreateFrame("Cooldown", name .. "Cooldown", q, "CooldownFrameTemplate")
	cd:SetAllPoints(icon)
	cd:SetDrawSwipe(true)
	cd:SetDrawEdge(true)
	cd:SetSwipeColor(0, 0, 0, 0.8)
	cd:SetHideCountdownNumbers(true)   -- (the addon's own text...)
	SP:StyleEngineCooldown(cd)          -- (...except where the engine draws the numbers)
	q.cooldown = cd
	local texts = CreateFrame("Frame", nil, q)
	texts:SetAllPoints(q)
	texts:SetFrameLevel(cd:GetFrameLevel() + 1)
	SP:KeepAboveCooldown(q, texts, 2)
	local cdText = texts:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	SP:AdoptSPFont(cdText, "timers")
	SP:SizeTotemCooldownText(cdText)
	cdText:SetPoint("CENTER", q, "CENTER", 0, 0)
	local c = SP.opt.totemCooldownTextColor
	cdText:SetTextColor(c and c.r or 1, c and c.g or 1, c and c.b or 1)
	cdText:SetShadowOffset(1, -1)
	cdText:Hide()
	q.cooldownText = cdText

	-- while its totem is down: lit in the element's color, its time left (A109)
	local lit = CreateFrame("Frame", nil, q)
	lit:SetAllPoints(q)
	lit:SetFrameLevel(texts:GetFrameLevel() + 1)
	lit:Hide()
	q.lit = lit
	q.edges = {}
	for i = 1, 4 do q.edges[i] = lit:CreateTexture(nil, "OVERLAY") end
	q.ring = lit:CreateTexture(nil, "OVERLAY")
	q.ring:SetAllPoints(q)
	q.ring:Hide()
	local time = lit:CreateFontString(nil, "OVERLAY")
	SP:SetSPFont(time, "timers", 8, "OUTLINE")
	time:SetPoint("CENTER", q, "CENTER", 0, 0)
	time:SetTextColor(1, 1, 1)
	q.time = time

	-- its key (Show Their Keys): what Keybind Mode set on it, or the spell's action bar key
	local keyText = texts:CreateFontString(nil, "OVERLAY")
	SP:SetSPFont(keyText, "labels", 7, "OUTLINE", "Fonts\\ARIALN.TTF")
	keyText:SetPoint("TOPRIGHT", q, "TOPRIGHT", 1, 0)
	keyText:SetTextColor(0.9, 0.9, 0.9, 1)
	keyText:Hide()
	q.keybindText = keyText

	q:SetScript("OnEnter", onEnter)
	q:SetScript("OnLeave", onLeave)
	-- the hover flyout closes when the mouse leaves a quick totem for anywhere but its button or the flyout
	-- (hover flyouts only: arrows and keys open them in box mode)
	if SP.SECURE_ONLEAVE_PARENT and not SP:FlyoutBoxMode() then SP:SetSnippet(q, "_onleave", SP.SECURE_ONLEAVE_PARENT) end

	sets[element] = sets[element] or {}
	sets[element][slot] = q
	madeOf[element] = madeOf[element] or {}
	table.insert(madeOf[element], q)
	all[#all + 1] = q
	-- the bar's looks: Icon Shape, Dark Icons, Element-Colored Borders (as the flyout's buttons)
	QT.painted = false
	return q
end

-- the made buttons of an element (the look painters, Keybind Mode)
function SP:QuickTotemButtons(element) return madeOf[element] end
function SP:QuickTotemButtonList() return all end

-- ---------------------------------------------------------------------------
-- Where they go
-- ---------------------------------------------------------------------------
local function flyoutSide(element, btn)
	if not SP.FlyoutDirection then return "top" end
	return SP:FlyoutDirection({ element = element, totemButton = btn })
end

-- their side of this element's button: "above", "below", "left" or "right"
function SP:QuickTotemSide(element)
	local w = (O() and O().quickTotemSide) or "auto"
	if FLY[w] then return w end
	local btn = self.totemButtons and self.totemButtons[element]
	return AWAY[flyoutSide(element, btn)] or "below"
end

-- the room a quick row takes on the flyout's side of an element button (the flyout starts past it), 0 elsewhere
function SP:QuickTotemFlyoutLead(flyout)
	local btn = flyout and flyout.totemButton
	if not (btn and flyout.element and btn.spQuickSide) then return 0 end
	if btn.spQuickSide ~= flyoutSide(flyout.element, btn) then return 0 end
	return btn.spQuickRoom or 0
end

local function setPads(btn, side, room)
	local t, b, l, r = 0, 0, 0, 0
	if side == "top" then t = room elseif side == "bottom" then b = room elseif side == "left" then l = room elseif side == "right" then r = room end
	if not side then
		local was = btn.spQuickPadT ~= nil
		btn.spQuickPadT, btn.spQuickPadB, btn.spQuickPadL, btn.spQuickPadR = nil, nil, nil, nil
		btn.spQuickSide, btn.spQuickRoom = nil, nil
		return was
	end
	local changed = btn.spQuickPadT ~= t or btn.spQuickPadB ~= b or btn.spQuickPadL ~= l or btn.spQuickPadR ~= r
	btn.spQuickPadT, btn.spQuickPadB, btn.spQuickPadL, btn.spQuickPadR = t, b, l, r
	btn.spQuickSide, btn.spQuickRoom = side, room
	return changed
end

-- what is drawn outside a button follows its new room (as for the flyout tab: FollowFlyoutArrows)
local function follow(element, btn)
	local host = btn:GetParent()
	if host and host.key and SP.poppedOutFrames and SP.poppedOutFrames[host.key] == host then SP:FitBarBackdrop(host) end
	if SP.FitBarBackdrop then SP:FitBarBackdrop(SP.autoButton) end
	local pulse = SP.pulseOverlays and SP.pulseOverlays[element]
	if pulse and pulse.button == btn and SP.PositionPulseWipe then SP:PositionPulseWipe(pulse) end
	if SP.UpdateTotemProgressBarPositions then SP:UpdateTotemProgressBarPositions() end
	if SP.PlacePartyDotFrame then SP:PlacePartyDotFrame(btn) end
	if SP.PositionActiveOverlays then SP:PositionActiveOverlays() end
	-- the flyout starts past them on its side
	local fl = SP.totemFlyouts and SP.totemFlyouts[element]
	if fl then
		if fl.box and SP.UpdateFlyoutVisibility then SP:UpdateFlyoutVisibility(element)
		elseif SP.LayoutFlyoutButtons then SP:LayoutFlyoutButtons(fl, fl.isHorizontal) end
	end
end

-- ---------------------------------------------------------------------------
-- Lay them out (out of combat only)
-- ---------------------------------------------------------------------------
local function litLook(q, size)
	-- a ring round a Rounded / Circle icon, else four 1 px edges (the buttons are small)
	local file = SP.BorderRingSizedFile and SP:BorderRingSizedFile("totem", 1, size)
	local e = q.edges
	if file then
		q.ring:SetTexture(file)
		q.ring:Show()
		for i = 1, 4 do e[i]:Hide() end
	else
		q.ring:Hide()
		e[1]:ClearAllPoints(); e[1]:SetPoint("TOPLEFT", q, "TOPLEFT"); e[1]:SetPoint("TOPRIGHT", q, "TOPRIGHT"); e[1]:SetHeight(1)
		e[2]:ClearAllPoints(); e[2]:SetPoint("BOTTOMLEFT", q, "BOTTOMLEFT"); e[2]:SetPoint("BOTTOMRIGHT", q, "BOTTOMRIGHT"); e[2]:SetHeight(1)
		e[3]:ClearAllPoints(); e[3]:SetPoint("TOPLEFT", q, "TOPLEFT"); e[3]:SetPoint("BOTTOMLEFT", q, "BOTTOMLEFT"); e[3]:SetWidth(1)
		e[4]:ClearAllPoints(); e[4]:SetPoint("TOPRIGHT", q, "TOPRIGHT"); e[4]:SetPoint("BOTTOMRIGHT", q, "BOTTOMRIGHT"); e[4]:SetWidth(1)
		for i = 1, 4 do e[i]:Show() end
	end
	local c = SP.DurationBarColors and SP.DurationBarColors[q.element]
	local r, g, b = 1, 1, 1
	if c then r, g, b = c[1] or c.r or 1, c[2] or c.g or 1, c[3] or c.b or 1 end
	if file then q.ring:SetVertexColor(r, g, b, 1) end
	for i = 1, 4 do e[i]:SetColorTexture(r, g, b, 1) end
	SP:SetSPFont(q.time, "timers", math.max(5, math.floor(size * 0.3 + 0.5)), "OUTLINE")
end

-- the cooldown numbers at the quick button's scale: the totem bar's size (Number Sizes) times how much smaller it is
local function sizeNumbers(q)
	local k = q.spScale or 0.5
	local fs = q.cooldownText
	SP:SizeTotemCooldownText(fs)
	local font, size, flags = fs:GetFont()
	if font and size then fs:SetFont(font, math.max(5, math.floor(size * k + 0.5)), flags) end
	local cd = q.cooldown
	if cd and SP:EngineCooldownsOn() then
		local ok, efs = pcall(cd.GetCountdownFontString, cd)
		if ok and efs then
			local f, sz, fl = efs:GetFont()
			if f and sz and not secret(sz) then efs:SetFont(f, math.max(5, math.floor(sz * k + 0.5)), fl) end
		end
	end
end
QT.sizeNumbers = sizeNumbers

local function placeElement(element, want)
	local btn = SP.totemButtons and SP.totemButtons[element]
	if not btn then return end
	local any = false
	local side = want and SP:QuickTotemSide(element) or nil
	local across = (side == "above" or side == "below")
	local edge = btn and (across and btn:GetWidth() or btn:GetHeight()) or 0
	local size = math.max(6, math.floor(edge * ((O() and O().quickTotemSize) or 0.5) + 0.5))
	-- on the flyout's side: the tab's room kept, in and out of a fight (A110 Q3)
	local fs = side and flyoutSide(element, btn)
	local tab = (fs and FLY[side] == fs and SP.FlyoutTabRoom) and SP:FlyoutTabRoom(btn, fs) or 0
	local gap = 1 + tab
	for slot = 1, 2 do
		local idx = want and SP:QuickTotemPick(element, slot) or nil
		local spellID = idx and SP:GetTotemSpell(element, idx)
		local known = spellID and SP.PlayerKnowsTotem and SP.PlayerKnowsTotem(spellID)
		local name = known and spellNameOf(spellID)
		local q = sets[element] and sets[element][slot]
		if name and not q then q = make(element, slot) end
		if q then
			if name then
				any = true
				q.spOn, q.spIndex, q.spellID = true, idx, spellID
				q:SetAttribute("type", "spell")
				q:SetAttribute("spell", name)
				---@type string|number|nil
				local tex = SP.TotemIcons and SP.TotemIcons[element] and SP.TotemIcons[element][idx]   -- (a path, or a file ID below)
				if not tex and spellID then
					tex = (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID)) or (GetSpellTexture and GetSpellTexture(spellID))
				end
				q.icon:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")
				q:SetFrameStrata(btn:GetFrameStrata())
				q:SetFrameLevel(btn:GetFrameLevel() + 3)
				q:SetSize(size - 1, size - 1)   -- (a 1 px gap between the two)
				q:ClearAllPoints()
				if side == "above" then
					if slot == 1 then q:SetPoint("BOTTOMLEFT", btn, "TOPLEFT", 0, gap) else q:SetPoint("BOTTOMRIGHT", btn, "TOPRIGHT", 0, gap) end
				elseif side == "below" then
					if slot == 1 then q:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -gap) else q:SetPoint("TOPRIGHT", btn, "BOTTOMRIGHT", 0, -gap) end
				elseif side == "left" then
					if slot == 1 then q:SetPoint("TOPRIGHT", btn, "TOPLEFT", -gap, 0) else q:SetPoint("BOTTOMRIGHT", btn, "BOTTOMLEFT", -gap, 0) end
				else
					if slot == 1 then q:SetPoint("TOPLEFT", btn, "TOPRIGHT", gap, 0) else q:SetPoint("BOTTOMLEFT", btn, "BOTTOMRIGHT", gap, 0) end
				end
				litLook(q, size - 1)
				q.spScale = (size - 1) / math.max(edge, 1)
				SP:StyleEngineCooldown(q.cooldown)
				sizeNumbers(q)
				q.spDown, q.spSecs = nil, nil
				q.lit:Hide()
				q:Show()
			else
				q.spOn, q.spIndex, q.spellID = nil, nil, nil
				q:SetAttribute("type", nil)
				q:SetAttribute("spell", nil)
				q:Hide()
			end
		end
	end
	-- their room on that side: past them (and the tab's room kept in it) everything else steps out
	local changed = setPads(btn, any and FLY[side] or nil, gap + size - 1)
	if changed then follow(element, btn) end
	return any
end

-- everything again (a setting, the bar laid out again, a style, spells learned)
function QT.Refresh()
	if InCombatLockdown() then pending = true return end
	pending = false
	local want = SP:QuickTotemsWanted() and SP:QuickTotemsStyleOK() and SP.totemButtons and SP.totemButtons[1] ~= nil
	if not want and #all == 0 then
		-- never made: nothing to undo, except a room left by an earlier pass
		for element = 1, 4 do
			local btn = SP.totemButtons and SP.totemButtons[element]
			if btn and setPads(btn, nil) then follow(element, btn) end
		end
		active = false
		QT.Listen(false)
		return
	end
	local any = false
	for element = 1, 4 do
		if placeElement(element, want) then any = true end
	end
	active = any
	QT.Listen(any)
	if not QT.painted and #all > 0 then
		QT.painted = true
		if SP.ApplyIconShapes then SP:ApplyIconShapes() end
		if SP.ApplyIconDark then SP:ApplyIconDark() end
		if SP.ThemePaintTotemBorders then SP:ThemePaintTotemBorders() end
	end
	if any then
		SP:UpdateQuickTotems()
		QT.Keys()
	end
end

function SP:QuickTotemsChanged() QT.Refresh() end

-- ---------------------------------------------------------------------------
-- In a fight too: lit while their totem is down, its time left. No tables, closures, formatting or frame
-- geometry reads here: the bar's duration tick runs it 10 times a second while a totem is down.
-- ---------------------------------------------------------------------------
local function setLit(q, down)
	q.spDown, q.spSecs = down, nil
	q.lit:SetShown(down)
	-- the cooldown's number gives way to the time left while it is down
	if down then
		q.cooldownText:Hide()
		if q.cooldown and SP:EngineCooldownsOn() then q.cooldown:SetHideCountdownNumbers(true) end
	elseif q.cooldown then
		SP:StyleEngineCooldown(q.cooldown)
		sizeNumbers(q)
	end
end

function SP:UpdateQuickTotems()
	if not active then return end
	local now = GetTime()
	for element = 1, 4 do
		local set = sets[element]
		if set then
			local have, _, start, duration = self:GetElementTotemInfo(element)
			local valid = not secret(have) and have == true and not secret(start) and type(start) == "number"
				and not secret(duration) and type(duration) == "number" and duration > 0 and start + duration > now
			local idx = valid and self:GetActiveTotemIndex(element) or nil
			for slot = 1, 2 do
				local q = set[slot]
				if q and q.spOn then
					local down = (idx ~= nil and idx == q.spIndex) and true or false
					if down ~= q.spDown then setLit(q, down) end
					if down then
						local secs = math.floor(start + duration - now)
						if secs ~= q.spSecs then
							q.spSecs = secs
							q.time:SetText(SP.FormatDuration(secs))
						end
					end
				end
			end
		end
	end
end

local function afterTotem()
	if active then SP:UpdateQuickTotems() end
end
for _, name in ipairs({ "PLAYER_TOTEM_UPDATE", "UNIT_SPELLCAST_SUCCEEDED", "UpdateTotemProgressBars" }) do
	if SP[name] then hooksecurefunc(SP, name, afterTotem) end
end

-- their cooldowns, as the flyout's buttons get theirs (only shown ones: a read builds a table on WoW: Forever).
-- SPCompat's reader, as the core's own: in a fight on WoW: Forever it answers from the player's own casts.
if SP.UpdateTotemCooldowns then
	hooksecurefunc(SP, "UpdateTotemCooldowns", function(self)
		if not active then return end
		local engine = self.EngineCooldownsOn and self:EngineCooldownsOn()
		local read = (SPCompat and SPCompat.GetSpellCooldown) or GetSpellCooldown
		for i = 1, #all do
			local q = all[i]
			if q.spOn and q.spellID and q:IsVisible() then
				local start, duration, enabled = read(q.spellID)
				local readable = not (secret(start) or secret(duration) or secret(enabled))   -- (a hidden number: as none)
				local running = readable and start and duration and duration > 1.5 and enabled == 1
				if engine then
					local estimate = running
					self:FeedEngineCooldown(q, q.spellID, self:EngineCooldownRunning(q, q.spellID, estimate))
				elseif running then
					self:ApplyTotemCooldownVisual(q, start, duration)
					self._totemCdShown = true
					local remaining = start + duration - GetTime()
					if remaining > 0 and self.opt.totemCooldownText ~= false and not q.spDown then
						if remaining >= 60 then q.cooldownText:SetFormattedText("%dm", math.ceil(remaining / 60))
						elseif remaining >= 10 then q.cooldownText:SetFormattedText("%d", math.floor(remaining))
						else q.cooldownText:SetFormattedText("%.1f", remaining) end
						q.cooldownText:Show()
					else
						q.cooldownText:Hide()
					end
				else
					self:ClearTotemCooldownVisual(q)
					q.cooldownText:Hide()
				end
			end
		end
	end)
end

-- ---------------------------------------------------------------------------
-- Their keys (Show Their Keys): the key Keybind Mode set on one (a CLICK binding on its button), or its spell's
-- key on the action bars, in the order the bar buttons use (Keybind Shown)
-- ---------------------------------------------------------------------------
function QT.Keys()
	local on = O() and O().quickTotemKeys ~= false
	local mode = O() and O().keybindSource
	for i = 1, #all do
		local q = all[i]
		local text
		if on and q.spOn then
			local own = GetBindingKey("CLICK " .. q:GetName() .. ":LeftButton")
			local name = q.spellID and spellNameOf(q.spellID)
			local bar = name and mode ~= "sponly" and SP.GetKeybindForSpell and SP:GetKeybindForSpell(name) or nil
			local short = SP.ShortKeybindText
			own = own and short and short(own) or own
			bar = bar and short and short(bar) or bar
			if mode == "sp" or mode == "sponly" then text = own or bar else text = bar or own end
		end
		if text then
			q.keybindText:SetText(text)
			q.keybindText:Show()
		else
			q.keybindText:SetText("")
			q.keybindText:Hide()
		end
	end
end

-- ---------------------------------------------------------------------------
-- Events (only while a quick totem shows) and the hooks that lay them out again
-- ---------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_REGEN_ENABLED" then
		if pending then QT.Refresh() end
	elseif event == "UPDATE_BINDINGS" then
		QT.Keys()
	else   -- SPELLS_CHANGED: a totem learned (or a rank): its spot shows, with the new rank's name
		if not InCombatLockdown() then QT.Refresh() else pending = true end
	end
end)
events:RegisterEvent("PLAYER_REGEN_ENABLED")   -- (a change asked for in a fight; one event, nothing else while off)
function QT.Listen(on)
	if on == listening then return end
	listening = on
	if on then
		events:RegisterEvent("SPELLS_CHANGED")
		events:RegisterEvent("UPDATE_BINDINGS")
	else
		events:UnregisterEvent("SPELLS_CHANGED")
		events:UnregisterEvent("UPDATE_BINDINGS")
	end
end

-- a new Icon Shape: the lit edge becomes a ring (or edges again)
if SP.ApplyIconShapes then
	hooksecurefunc(SP, "ApplyIconShapes", function()
		for i = 1, #all do
			local q = all[i]
			if q.spOn then litLook(q, q:GetWidth()) end
		end
	end)
end

-- Number Sizes, Fonts or the cooldown text settings changed: the quick buttons' numbers follow, at their scale
if SP.RestyleEngineCooldowns then
	hooksecurefunc(SP, "RestyleEngineCooldowns", function()
		for i = 1, #all do
			local q = all[i]
			if q.spOn then SP:StyleEngineCooldown(q.cooldown); sizeNumbers(q) end
		end
	end)
end

-- laid out again with the bar: its layout, its style, Totem Rows, the flyouts' side
local function relayout()
	if SP:QuickTotemsWanted() or #all > 0 then QT.Refresh() end
end
for _, name in ipairs({ "UpdateMiniTotemBar", "SetTotemBarStyle", "RefreshRowsStyle", "ApplyCompactStyle" }) do
	if SP[name] then hooksecurefunc(SP, name, relayout) end
end
-- Auto follows the flyouts: the bar dragged across the middle of the screen turns them round
if SP.FlyoutGoesBelow then
	local was
	hooksecurefunc(SP, "FlyoutGoesBelow", function(self)
		local now = self._flyoutAutoBelow
		if now == was then return end
		was = now
		if (#all > 0) and not InCombatLockdown() then C_Timer.After(0, relayout) end
	end)
end
