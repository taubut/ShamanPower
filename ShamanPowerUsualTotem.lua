-- ShamanPowerUsualTotem.lua
-- Put Your Usual Totem Back (Settings > Bars > Totem Bar > Effects; off to start).
--
-- When a temporary totem you dropped (Grounding, Tremor, Mana Tide, Earthbind,
-- a cleansing totem...) ends, the element's button lights up until your usual
-- totem of that element is down again. Your usual totem is the one assigned to
-- that element on your bar (with Dynamic Mode, where every drop becomes the
-- assignment: the last one that is not temporary). A reminder only: nothing
-- here casts a spell, changes an assignment or touches a protected frame.
--
-- How it knows, on both games:
--   arms     your own successful cast of a temporary totem (UNIT_SPELLCAST_SUCCEEDED
--            for the player: never hidden, in fights on WoW: Forever too), called
--            from the core's own handler. A readable slot at login or /reload arms
--            too; after a /reload in a fight (WoW: Forever) nothing is known and it
--            waits for your next cast. With Dynamic Mode the usual totem is the last
--            drop that was not temporary (kept per character); none known: quiet.
--   ends     WoW: Forever in a fight: the core's own-cast totem record says the
--            totem went and why (ShadowTotemSlotUpdate -> UsualTotemGone). Out of
--            fights and on TBC Anniversary: the readable slot after its update
--            (UsualTotemUpdate), with the core's half-second wait so a Totemic Call,
--            your death or a re-drop is never a reminder.
--   clears   your usual totem (or any totem of that element that is not
--            temporary), Totemic Call, dying, a loading screen or a flight path,
--            and a change to that element's assignment.
--
-- The look: the bar Effects' own loops (ShamanPowerCues.lua, SP.CueFx: Glow or
-- Pulse, a loop kind of its own, "usual", in the Totem Bar's Effects Look: the
-- Cooldown Ready gold, or the element's color under Elemental), on a frame of ours
-- over the element's button and over your usual totem in its
-- flyout, Totem Row or Grid row; a short BACK on the button (a Compact line says
-- "Put Windfury back"); with Dynamic Mode, where the button shows the totem you
-- dropped, your usual totem in the button's corner instead. Optionally one line
-- in the Expiring Alerts text. Every part is built once and reused; nothing runs
-- while no reminder is armed: events and one-shot timers only.

local SP = ShamanPower
if not SP then return end

local GetTime, type, ipairs, pairs = GetTime, type, ipairs, pairs
local floor, max, min = math.floor, math.max, math.min

local GOLD = { 1, 0.82, 0.25 }   -- the bar Effects' gold (Cooldown Ready): "cast it now"
local LETTERS = "Interface\\AddOns\\ShamanPower\\Media\\Fonts\\BebasNeue-Regular.ttf"   -- letters on a button (brand rule)
local VERDICT = 0.5              -- the core's bind window: a recall, dismiss or re-drop can trail a slot update
local TEST_SECONDS = 5
local TOTEMIC_CALL = 36936       -- Totemic Call (TBC Anniversary) / Totemic Recall (WoW: Forever): one ID on both
-- WoW: Forever's Decoy Totem (Earth) is not in the totem tables, and the core's record
-- does not follow it: it would read as the end of the Earth totem it replaces in a fight
-- but not out of one. It counts as dropping a totem of that element (no reminder), the
-- same everywhere.
local DECOY_TOTEM, DECOY_ELEMENT = 425874, 1

-- The totems that count as temporary until the player says otherwise, by the
-- rank-1 IDs of the totem tables (every rank counts: matched through them).
-- Each game offers the ones it has (WoW: Forever has no Fire Nova Totem or
-- elementals). The resistance totems are a plan of their own: off to start.
local TEMP_DEFAULT = {
	[8143] = true, [2484] = true, [5730] = true, [2062] = true,      -- Tremor, Earthbind, Stoneclaw, Earth Elemental
	[8190] = true, [1535] = true, [2894] = true, [8181] = false,     -- Magma, Fire Nova, Fire Elemental, Frost Resistance
	[16190] = true, [8166] = true, [8170] = true, [8184] = false,    -- Mana Tide, Poison / Disease Cleansing, Fire Resistance
	[8177] = true, [15107] = true, [6495] = true, [10595] = false,   -- Grounding, Windwall, Sentry, Nature Resistance
}
-- the settings list, element by element
SP.USUAL_TOTEM_CHOICES = { 8143, 2484, 5730, 2062, 8190, 1535, 2894, 8181, 16190, 8166, 8170, 8184, 8177, 15107, 6495, 10595 }

local function isSecret(v) return issecretvalue and issecretvalue(v) or false end
local function secretNow()
	return SPCompat and SPCompat.secretsRegime and SPCompat.AnyRestrictionActive and SPCompat.AnyRestrictionActive() or false
end
local function on()
	local o = SP.opt
	return o and o.usualTotemReminder == true and not SP:IsOff() or false
end

-- ---------------------------------------------------------------------------
-- Which totem a spell is: element and index in the totem tables, any rank
-- ---------------------------------------------------------------------------
local byID   -- [spell ID of any rank] = { element, index, base }
local function totemOf(id)
	if type(id) ~= "number" or isSecret(id) then return nil end
	if not byID then
		byID = {}
		for e = 1, 4 do
			for index, base in pairs(SP.Totems and SP.Totems[e] or {}) do
				if type(base) == "number" then
					local rec = { element = e, index = index, base = base }
					byID[base] = rec
					for _, rank in ipairs(SPCompat.SpellRanks(base) or {}) do
						if byID[rank] == nil then byID[rank] = rec end
					end
				end
			end
		end
	end
	return byID[id]
end

-- the rank-1 ID a settings choice stands for exists on this game (in the totem tables)
function SP:UsualTotemChoiceExists(base)
	local t = totemOf(base)
	return t ~= nil and t.base == base
end

-- how a totem came (Counts As Temporary on the Totem Bar's Bar tab: each totem's menu)
function SP:UsualTotemTempDefault(base)
	return TEMP_DEFAULT[base] == true
end

-- the settings page (a totem's menu): saved only where it differs from how it came
function SP:SetUsualTotemTemporary(base, v)
	if type(base) ~= "number" or TEMP_DEFAULT[base] == nil then return end
	v = v and true or false
	local o = self.opt
	if not o then return end
	if v == (TEMP_DEFAULT[base] == true) then
		if type(o.usualTotemTemp) == "table" then
			o.usualTotemTemp[base] = nil
			if next(o.usualTotemTemp) == nil then o.usualTotemTemp = nil end
		end
	else
		if type(o.usualTotemTemp) ~= "table" then o.usualTotemTemp = {} end
		o.usualTotemTemp[base] = v
	end
	self:ApplyUsualTotemSettings()   -- (taken off while it is down: its reminder goes)
end

function SP:UsualTotemIsTemporary(base)
	local o = self.opt and self.opt.usualTotemTemp
	local v
	if type(o) == "table" then v = o[base] end   -- (a saved false is a choice: never "and ... or")
	if v == nil then v = TEMP_DEFAULT[base] end
	return v == true
end
local function isTemp(e, index)
	local base = SP.Totems and SP.Totems[e] and SP.Totems[e][index]
	return base ~= nil and SP:UsualTotemIsTemporary(base)
end

-- ---------------------------------------------------------------------------
-- State, per element
-- ---------------------------------------------------------------------------
-- phase    nil, "armed" (a temporary totem of yours is down) or "showing"
-- temp     the temporary totem's index; usual: the totem to put back (index)
-- assigned the element's assignment as last seen (a change to it is a new plan)
local st = { {}, {}, {}, {} }
local armedCount, showingCount = 0, 0
-- [element] = the last assignment that was not temporary (Dynamic Mode), kept per
-- character (db.char, like the core's learned totem lengths) so a /reload or a new
-- login still knows it. Read through each time: the core can rebind db.char once the
-- player's real name is known (FixPlayerIdentity).
local sessionPlan = {}
local function lastPlan()
	local db = SP.db
	local c = db and db.char
	if type(c) ~= "table" then return sessionPlan end
	local t = c.usualTotemLastPlan
	if type(t) ~= "table" then
		t = {}
		for e, v in pairs(sessionPlan) do t[e] = v end
		c.usualTotemLastPlan = t
	end
	return t
end
local worldAt = 0         -- the last loading screen: totems it takes are not a reminder
local setWait = {}        -- [element] = the core's record of a set summon's totem, until its slot confirms it
local testUntil = {}      -- [element] = GetTime() the Test button's look ends
local testState = { {}, {}, {}, {} }   -- [element] = what the Test button shows (its usual totem)

local function recount()
	local a, s = 0, 0
	for e = 1, 4 do
		if st[e].phase == "armed" then a = a + 1 elseif st[e].phase == "showing" then s = s + 1 end
	end
	armedCount, showingCount = a, s
end

-- The usual totem of an element: its assignment. With Dynamic Mode (and Grid's
-- Left-Click Also Assigns) every drop is the assignment, so a temporary one there
-- gives way to the last assignment this session that was not temporary; none seen
-- yet (a new session that starts on a temporary drop): nothing is known, so no
-- reminder (0) rather than asking for a temporary totem.
local function usualFor(e)
	local a = SP:AssignedIndex(e)
	if not a or a <= 0 then return 0 end
	if not isTemp(e, a) then
		local plan = lastPlan()
		if plan[e] ~= a then plan[e] = a end
		return a
	end
	if SP:DropSetsAssignment() then return lastPlan()[e] or 0 end
	return a   -- (a temporary totem you assigned yourself is your plan: Tremor for a fear boss)
end

-- ---------------------------------------------------------------------------
-- The look
-- ---------------------------------------------------------------------------
local shown = { {}, {}, {}, {} }   -- [element] = our frames lit now
local shownKey = {}                 -- [element] = the layout they were lit for (layoutKey)
local hostList = {}                 -- scratch, reused

-- What the look depends on besides its buttons: Compact (and upright), Totem Rows with
-- the bar hidden, the bar's button showing another totem (the corner), the button's
-- height (the label's size). A number, so nothing is built to compare it.
local function layoutKey(e, s)
	local k = 0
	if SP:CompactActive() then
		k = 1
		if SP.opt.compactOrientation == "vertical" then k = k + 2 end   -- (as CompactOpts reads it, without its table)
	end
	if SP.RowsHideBar and SP:RowsHideBar() then k = k + 4 end
	if SP:AssignedIndex(e) ~= s.usual then k = k + 8 end
	local b = SP.totemButtons and SP.totemButtons[e]
	return k + 16 * floor((b and b:GetHeight() or 0) + 0.5)
end

-- Our frame over a button: the loops play on it (never on the button itself, so the
-- bar's own effects on the same button are never stopped or recolored by this).
local function overlay(host)
	local ov = host.spUsualTotem
	if ov then return ov end
	ov = CreateFrame("Frame", nil, host)
	ov:SetAllPoints(host)
	ov:SetFrameLevel(host:GetFrameLevel() + 12)
	ov:EnableMouse(false)
	ov:SetAlpha(0)
	host.spUsualTotem = ov
	return ov
end

-- BACK (or the Compact line's sentence) and the corner totem: above the loops
local function labelParts(ov)
	if ov.label then return end
	local tf = CreateFrame("Frame", nil, ov)
	tf:SetAllPoints(ov)
	tf:SetFrameLevel(ov:GetFrameLevel() + 20)
	ov.labelFrame = tf
	local fs = tf:CreateFontString(nil, "OVERLAY")
	fs:SetJustifyH("CENTER")
	fs:Hide()
	ov.label = fs
	local cbg = tf:CreateTexture(nil, "ARTWORK", nil, 1)
	cbg:SetColorTexture(0, 0, 0, 0.9)
	cbg:Hide()
	local cic = tf:CreateTexture(nil, "ARTWORK", nil, 2)
	cic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	cic:SetPoint("TOPLEFT", cbg, "TOPLEFT", 1, -1)
	cic:SetPoint("BOTTOMRIGHT", cbg, "BOTTOMRIGHT", -1, 1)
	cic:Hide()
	ov.cornerBg, ov.cornerIcon = cbg, cic
end

local function hideLabel(ov)
	if not ov.label then return end
	ov.label:Hide(); ov.cornerBg:Hide(); ov.cornerIcon:Hide()
end

-- The Effects Look the totem bar's effects use (Standard / Elemental / Signal): the
-- reminder's own loop kind follows it (never the cooldown bar's)
local function effectsLook()
	local cue = SP.ThemeCue
	return cue and cue.lookOf and cue.lookOf("usual") or "standard"
end

-- The reminder's color: the bar Effects' gold, or the element's color under the
-- Elemental look (as that look paints the loops). A Compact line's loop is always
-- the gold one (line), so its words are too.
local function tint(e, line)
	if not line and effectsLook() == "elemental" and SP.ThemeElement then return SP:ThemeElement("tb.effects", e) end
	return GOLD[1], GOLD[2], GOLD[3]
end

-- The bar's own Totem Destroyed mark (the red X, Elemental's stone, Signal's slash)
-- playing on a button: the label waits for it, so the two never sit on each other.
local function marking(host)
	local c = host and host.spCue
	if not c then return false end
	if c.markHold and c.markHold:IsPlaying() then return true end
	if c.spTheme then
		if c.stoneHold and c.stoneHold:IsPlaying() then return true end
		if c.slashHold and c.slashHold:IsPlaying() then return true end
	end
	return false
end

local sentence = {}   -- [element .. index] = "Put <totem> back", made once
local function putBack(e, index)
	local key = e * 100 + index
	local s = sentence[key]
	if not s then
		s = "Put " .. SP:GetTotemName(e, index) .. " back"
		sentence[key] = s
	end
	return s
end
if SPCompat.OnSpellDataChanged then SPCompat.OnSpellDataChanged(function() wipe(sentence) end) end

local function paintLabel(ov, host, e, s, isMain)
	labelParts(ov)
	hideLabel(ov)
	-- Write BACK on the Button off: the glow alone (the Dynamic Mode corner is its BACK)
	if SP.opt.usualTotemLabel == false then return end
	local fs = ov.label
	local c = host.compact
	if c and host.compactLayoutOn and SP:CompactActive() then
		-- a Compact line: the sentence inside the empty line (BACK across an upright one)
		local r, g, b = tint(e, true)
		fs:ClearAllPoints()
		if c.vertical then
			SP:SetSPFont(fs, "alerts", max(7, floor((c.bw or 16) * 0.45 + 0.5)), "OUTLINE", LETTERS)
			fs:SetText("BACK")
			fs:SetPoint("TOP", host, "TOP", 0, -((c.ow or 2) + 2))
		else
			local size = max(7, min(12, (c.bh or 14) - 4))
			SP:SetSPFont(fs, "alerts", size, "OUTLINE")
			fs:SetText(putBack(e, s.usual))
			fs:SetPoint("LEFT", host, "LEFT", (c.ow or 2) + 4, 0)
			-- a line too short for the sentence: BACK, never cut
			if fs:GetStringWidth() > (c.lineLen or host:GetWidth()) - 6 then
				SP:SetSPFont(fs, "alerts", max(7, floor((c.bh or 14) * 0.7 + 0.5)), "OUTLINE", LETTERS)
				fs:SetText("BACK")
				fs:ClearAllPoints()
				fs:SetPoint("CENTER", host, "CENTER", 0, 0)
			end
		end
		fs:SetTextColor(r, g, b)
		fs:Show()
		return
	end
	local r, g, b = tint(e)
	local h = host:GetHeight()
	if isMain and SP:AssignedIndex(e) ~= s.usual then
		-- the bar's button shows another totem (Dynamic Mode: the one you dropped): your
		-- usual totem in its corner, where the assigned-totem indicator normally sits (a row's
		-- or flyout's button IS your usual totem: BACK on it)
		local size = max(10, floor(h * 0.46 + 0.5))
		ov.cornerBg:ClearAllPoints()
		ov.cornerBg:SetPoint("BOTTOMRIGHT", ov, "BOTTOMRIGHT", 0, 0)
		ov.cornerBg:SetSize(size, size)
		ov.cornerIcon:SetTexture(SP:GetTotemIcon(e, s.usual))
		ov.cornerBg:Show(); ov.cornerIcon:Show()
		return
	end
	-- BACK along the bottom of the button, in the bar's letters (at most half its height);
	-- above the Signal look's bar inside the bottom edge (its Pulse)
	local y = max(1, floor(h * 0.06 + 0.5))
	if SP.opt.usualTotemStyle == "pulse" and effectsLook() == "signal" then y = 6 end
	SP:SetSPFont(fs, "alerts", max(7, floor(h * 0.4 + 0.5)), "OUTLINE", LETTERS)
	fs:SetText("BACK")
	fs:ClearAllPoints()
	fs:SetPoint("BOTTOM", host, "BOTTOM", 0, y)
	fs:SetTextColor(r, g, b)
	fs:Show()
end

-- Every button that shows the element's reminder: the bar's own button first,
-- then your usual totem in the element's flyout, Totem Row (and its copies) or
-- Grid row. Blizzard's Totem Bar is the game's own: nothing is drawn on it.
local function hostsFor(e, usual, out)
	for i = #out, 1, -1 do out[i] = nil end
	if SP.UsingBlizzardTotemBar and SP:UsingBlizzardTotemBar() then return out end
	local btn = SP.totemButtons and SP.totemButtons[e]
	if btn then out[#out + 1] = btn end
	local fly = SP.totemFlyouts and SP.totemFlyouts[e]
	if fly then
		for _, b in ipairs(fly.allButtons or fly.buttons or {}) do
			if b.totemIndex == usual then out[#out + 1] = b end
		end
	end
	local copies = SP.RowsCopies and SP:RowsCopies(e)
	if copies then
		for _, b in ipairs(copies) do
			if b.totemIndex == usual then out[#out + 1] = b end
		end
	end
	return out
end

local labelGen = { 0, 0, 0, 0 }   -- [element] = bumped by every paint and release: a waiting label checks it

local function release(e)
	local list = shown[e]
	for i = #list, 1, -1 do
		local ov = list[i]
		if SP.CueFx then SP.CueFx.stop(ov) end
		ov:SetAlpha(0)
		hideLabel(ov)
		list[i] = nil
	end
	shownKey[e] = nil
	labelGen[e] = labelGen[e] + 1
end

-- what an element's look shows now: its reminder, or the Test button's (nil: none)
local function lookState(e)
	local s = st[e]
	if s.phase == "showing" then return s end
	if testUntil[e] and testUntil[e] > GetTime() then return testState[e] end
	return nil
end

-- The label once the bar's destroyed mark has gone (it lasts 5 seconds at most). The
-- mark's own animations say when they end: their finish and stop are hooked once per
-- button, the first time a label waits there, so nothing runs while a mark plays. A
-- newer paint or a release makes a waiting label stand down (its generation).
local MARK_GROUPS = { "markHold", "stoneHold", "slashHold" }   -- (marking's three)
local function markDone(host)
	local w = host.spUsualWait
	if not (w and w.gen) then return end
	if labelGen[w.e] ~= w.gen then w.gen = nil return end   -- painted again or released since
	if marking(host) then return end   -- another of its marks still plays: its own end comes
	w.gen = nil
	local s = lookState(w.e)
	if s and w.ov:GetAlpha() > 0 then paintLabel(w.ov, host, w.e, s, w.isMain) end
end
local function labelWhenFree(ov, host, e, isMain)
	local w = host.spUsualWait
	if not w then
		w = {}
		w.done = function() markDone(host) end
		-- a stop can be the mark starting over (Stop, then Play at once): looked at a moment later
		w.stopped = function() if w.gen then C_Timer.After(0, w.done) end end
		host.spUsualWait = w
	end
	w.ov, w.e, w.isMain, w.gen = ov, e, isMain, labelGen[e]
	local c = host.spCue
	for i = 1, #MARK_GROUPS do
		local g = c and c[MARK_GROUPS[i]]
		if g and not g.spUsualHooked then
			g.spUsualHooked = true
			g:HookScript("OnFinished", w.done)
			g:HookScript("OnStop", w.stopped)
		end
	end
end

-- (a host list the same as what is lit: nothing to redo, so a loop never restarts)
local function sameHosts(e, hosts)
	local list = shown[e]
	if #list ~= #hosts then return false end
	for i = 1, #hosts do
		if list[i] ~= hosts[i].spUsualTotem then return false end
	end
	return true
end

local function paint(e, s)
	release(e)
	local fx = SP.CueFx
	if not fx then return end
	local hosts = hostsFor(e, s.usual, hostList)
	local style = SP.opt.usualTotemStyle == "pulse" and "pulse" or "glow"
	-- Totem Rows with the bar hidden: the row's totem carries the label
	local labelOnRow = SP.RowsHideBar and SP:RowsHideBar()
	local labelled = false
	local list = shown[e]
	local main = SP.totemButtons and SP.totemButtons[e]
	for i = 1, #hosts do
		local host = hosts[i]
		local ov = overlay(host)
		ov.element = e   -- (the Elemental look paints a loop in its element's color)
		local line = i == 1 and host.compact and host.compactLayoutOn and SP:CompactActive()
		if line then
			-- a Compact line: a ring or edges sized for a square do not fit a line, so Glow is
			-- the Signal look's thin frame and Pulse the plain darkening, both in the gold
			fx.loop(ov, style, "usual", style == "glow" and "signal" or "standard")
		else
			fx.loop(ov, style, "usual")   -- (the Totem Bar's Effects Look, in ov.element's color)
		end
		ov:SetAlpha(1)
		if not labelled and (i == 1 and not labelOnRow or i > 1 and labelOnRow) then
			if marking(host) then
				hideLabel(ov)
				labelWhenFree(ov, host, e, host == main)
			else
				paintLabel(ov, host, e, s, host == main)
			end
			labelled = true
		end
		list[#list + 1] = ov
	end
	shownKey[e] = layoutKey(e, s)
end

-- re-lay the look where the hosts changed (a style, flyout or row rebuilt); with
-- force, always (a setting changed)
local function refreshLook(e, force)
	local s = lookState(e)   -- (its reminder, or the Test button's while it lasts)
	if not s then
		if #shown[e] > 0 then release(e) end
		return
	end
	if not force then
		local hosts = hostsFor(e, s.usual, hostList)
		if sameHosts(e, hosts) and shownKey[e] == layoutKey(e, s) then return end
	end
	paint(e, s)
end

-- ---------------------------------------------------------------------------
-- Arm, show, clear
-- ---------------------------------------------------------------------------
local function clear(e)
	local s = st[e]
	if s.phase then
		s.phase, s.temp, s.usual, s.assigned, s.goneAt = nil, nil, nil, nil, nil
		recount()
	end
	if not (testUntil[e] and testUntil[e] > GetTime()) and #shown[e] > 0 then release(e) end
end
local function clearAll()
	for e = 1, 4 do clear(e); setWait[e] = nil end
end

local function arm(e, temp, usual)
	local s = st[e]
	s.phase, s.temp, s.usual, s.goneAt = "armed", temp, usual, nil
	s.assigned = SP:AssignedIndex(e)
	recount()
	if #shown[e] > 0 then release(e) end   -- a reminder that was up goes while the new totem is down
end

local function alert(e, s)
	if not SP.opt.usualTotemAlert then return end
	local db = rawget(_G, "ShamanPowerExpiringAlertsDB")
	if not (SP.ShowExpiringAlert and type(db) == "table" and db.enabled) then return end
	local color = SP.ExpiringAlertElementColor and SP:ExpiringAlertElementColor(e) or nil
	SP:ShowExpiringAlert("reminder", putBack(e, s.usual), SP:GetTotemIcon(e, s.usual), color)
end

local function show(e)
	local s = st[e]
	if s.phase ~= "armed" then return end
	if not (SP.Totems[e] and SP.Totems[e][s.usual]) then clear(e) return end
	s.phase, s.goneAt = "showing", nil
	recount()
	paint(e, s)
	alert(e, s)
end

-- ---------------------------------------------------------------------------
-- Your casts (the core's UNIT_SPELLCAST_SUCCEEDED, player only)
-- ---------------------------------------------------------------------------
local function castOf(spellID)
	local t = totemOf(spellID)
	if not t then return end
	local e, index = t.element, t.index
	local s = st[e]
	if isTemp(e, index) then
		if s.phase then
			-- another temporary totem while one is down or its reminder is up: the same
			-- usual totem comes back after it (the usual one itself is the plan: done)
			if index == s.usual then clear(e) return end
			s.phase, s.temp, s.goneAt = "armed", index, nil
			recount()
			if #shown[e] > 0 then release(e) end
			return
		end
		local usual = usualFor(e)
		if usual > 0 and index ~= usual then arm(e, index, usual) end
		return
	end
	-- any other totem of that element: it is taken care of
	clear(e)
	if SP:DropSetsAssignment() then lastPlan()[e] = index end
end

function SP:UsualTotemCast(spellID)
	if not on() or isSecret(spellID) or type(spellID) ~= "number" then return end
	if spellID == TOTEMIC_CALL then clearAll() return end
	if spellID == DECOY_TOTEM then clear(DECOY_ELEMENT) return end
	-- Call of the Elements / Ancestors / Spirits (WoW: Forever): each totem it drops, once
	-- its slot says it landed. The core opens a record per totem of the summon and its
	-- slot update confirms it (ShadowTotemSetCast / ShadowTotemSlotUpdate); one the summon
	-- could not place (no mana, not known) never lands: that element keeps its reminder.
	local set = self.TotemSetForSummon and self:TotemSetForSummon(spellID)
	if set then
		local records, now = self.shadowTotems, GetTime()
		for e = 1, 4 do
			setWait[e] = nil
			local id = set[e]
			local entry = id and records and records[e]
			if entry and entry.setAt == now and entry.spellID == id then   -- (this summon's record)
				if entry.setPending then
					setWait[e] = entry   -- its slot update still to come: UsualTotemSetPlaced
				else
					castOf(id)   -- its slot update came first: it landed
				end
			end
		end
		return
	end
	castOf(spellID)
end

-- The core: a totem of a set summon landed (its slot confirmed the record)
function SP:UsualTotemSetPlaced(element, entry)
	if setWait[element] ~= entry or entry == nil then return end
	setWait[element] = nil
	if on() then castOf(entry.spellID) end
end

-- ---------------------------------------------------------------------------
-- The temporary totem ends
-- ---------------------------------------------------------------------------
-- the record the core retired is the temporary totem that armed this element
local function isOurs(e, s, entry)
	if type(entry) ~= "table" then return false end
	local t = totemOf(entry.spellID)
	if t then return t.element == e and t.index == s.temp end
	local base = SP.Totems[e] and SP.Totems[e][s.temp]
	local names = SP.TotemNames and SP.TotemNames[e]
	return type(entry.name) == "string" and not isSecret(entry.name)
		and SPCompat.TotemNameMatches(entry.name, base, names and names[s.temp]) or false
end

-- WoW: Forever in a fight: the core's own-cast record says the totem went, one bind
-- window after its slot emptied, and why (recalled / dismissed / died / unknown /
-- expired / destroyed).
function SP:UsualTotemWanted()
	return armedCount > 0 and on()
end
function SP:UsualTotemGone(element, entry, why)
	if not on() then return end
	local s = st[element]
	if not s or s.phase ~= "armed" or not isOurs(element, s, entry) then return end
	if why == "recalled" then clear(element) return end
	if why == "died" then clearAll() return end
	show(element)
end

-- Out of fights, and always on TBC Anniversary: the readable slots, after the core
-- has taken the update in. An element left empty waits out the bind window first.
local verdict = {}
for e = 1, 4 do
	verdict[e] = function()
		local s = st[e]
		local at = s.goneAt
		if s.phase ~= "armed" or not at then return end
		s.goneAt = nil
		if not on() then return end
		local recall = SP._totemRecallAt
		if recall and at - recall < 2 then clear(e) return end
		if UnitIsDeadOrGhost("player") then clearAll() return end
		-- a loading screen or a flight path takes your totems: not a reminder
		if at - worldAt < 3 or (UnitOnTaxi and UnitOnTaxi("player")) then clearAll() return end
		if SP:GetElementTotemInfo(e) then return end   -- a totem of that element is down again
		show(e)
	end
end

function SP:UsualTotemUpdate()
	if (armedCount + showingCount) == 0 or not on() or secretNow() then return end
	for e = 1, 4 do
		local s = st[e]
		if s.phase then
			local have = self:GetElementTotemInfo(e)
			if s.phase == "armed" and not have then
				if not s.goneAt then
					s.goneAt = GetTime()
					C_Timer.After(VERDICT, verdict[e])
				end
			elseif have then
				-- a totem stands there that no cast of yours told us about (a totem set, or a
				-- cast event that trailed its slot): another temporary one keeps the reminder
				-- coming (on hold while it is down), anything else ends it
				local idx = self:GetActiveTotemIndex(e)
				if idx and (idx ~= s.temp or s.phase == "showing") then
					if isTemp(e, idx) and idx ~= s.usual then
						s.phase, s.temp, s.goneAt = "armed", idx, nil
						recount()
						if #shown[e] > 0 then release(e) end
					else
						clear(e)
					end
				end
			end
		end
	end
end

-- At login and /reload: a temporary totem of yours already down is armed from its
-- readable slot. In a fight on WoW: Forever the slots are hidden and nothing is
-- known: the next temporary totem you drop arms it.
local function armFromSlots()
	if not on() or secretNow() then return end
	for e = 1, 4 do
		if not st[e].phase then
			local idx = SP:GetActiveTotemIndex(e)
			if idx and isTemp(e, idx) then
				local usual = usualFor(e)
				if usual > 0 and usual ~= idx then arm(e, idx, usual) end
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- A new plan, and the bar changing under the look
-- ---------------------------------------------------------------------------
-- An element's assignment changed: a new plan for it, so its reminder goes. The
-- drop itself (Dynamic Mode, Grid's Left-Click Also Assigns) is not a new plan.
local function checkPlans()
	for e = 1, 4 do
		local s = st[e]
		if s.phase then
			local a = SP:AssignedIndex(e)
			if a ~= s.assigned then
				if a == s.usual or (a == s.temp and SP:DropSetsAssignment()) then
					s.assigned = a
				else
					clear(e)
				end
			end
		end
	end
end

-- After the bar refreshes (its style, its buttons, an assignment): new plans, and
-- the look moves to the buttons that show the element now. Nothing while no
-- reminder is armed or up.
function SP:UsualTotemRefresh(force)
	if (armedCount + showingCount) == 0 and not next(testUntil) then return end
	checkPlans()
	for e = 1, 4 do refreshLook(e, force) end
end

-- Settings (and the switch, a profile change, ShamanPower on or off)
function SP:ApplyUsualTotemSettings()
	if not on() then
		clearAll()
		for e = 1, 4 do testUntil[e] = nil; release(e) end
	end
	-- a totem taken off Totems That Count as Temporary while it is down: no reminder for it
	for e = 1, 4 do
		local s = st[e]
		if s.phase == "armed" and not isTemp(e, s.temp) then clear(e) end
	end
	local f = self.usualTotemEvents
	if f then
		if on() then
			f:RegisterEvent("PLAYER_DEAD")
			f:RegisterEvent("PLAYER_LEAVING_WORLD")
		else
			f:UnregisterEvent("PLAYER_DEAD")
			f:UnregisterEvent("PLAYER_LEAVING_WORLD")
		end
	end
	if on() then
		armFromSlots()
		self:UsualTotemRefresh(true)
	end
end

-- The Test button: the look (and the text alert, when on) on one element for a few
-- seconds, on Air if it has an assigned totem, else the first element that does.
function SP:TestUsualTotemReminder()
	local o = self.opt
	if not o then return end
	local busy = false
	for _, e in ipairs({ 4, 3, 1, 2 }) do
		local usual = usualFor(e)
		if usual > 0 and self:IsElementShown(e) and st[e].phase then busy = true end
		if usual > 0 and self:IsElementShown(e) and not st[e].phase then
			local fake = testState[e]
			fake.usual = usual
			testUntil[e] = GetTime() + TEST_SECONDS
			paint(e, fake)
			if o.usualTotemAlert then alert(e, fake) end
			C_Timer.After(TEST_SECONDS, function()
				if testUntil[e] and testUntil[e] <= GetTime() + 0.05 then
					testUntil[e] = nil
					if st[e].phase ~= "showing" then release(e) end
				end
			end)
			return
		end
	end
	if busy then
		print("|cff0070ddShamanPower|r: your reminder is already waiting on every element with an assigned totem.")
	else
		print("|cff0070ddShamanPower|r: assign a totem to an element on your bar to test the reminder.")
	end
end

-- What the reminder is doing now, per element: phase, temporary totem, usual totem
-- (indexes). For tests (the renderer, the test round's buttons).
function SP:UsualTotemState(e)
	local s = st[e]
	return s and s.phase, s and s.temp, s and s.usual
end

-- ---------------------------------------------------------------------------
-- Events: a loading screen, death, login. Your casts and the totem updates come
-- through the core's own handlers (ShamanPower.lua).
-- ---------------------------------------------------------------------------
do
	local f = CreateFrame("Frame")
	SP.usualTotemEvents = f
	f:RegisterEvent("PLAYER_LOGIN")
	f:RegisterEvent("PLAYER_ENTERING_WORLD")
	f:SetScript("OnEvent", function(_, event, isLogin, isReload)
		if event == "PLAYER_LOGIN" then
			SP:ApplyUsualTotemSettings()
		elseif event == "PLAYER_ENTERING_WORLD" then
			worldAt = GetTime()
			clearAll()   -- a loading screen takes every totem
			-- login or /reload: the slots as they are, once they have settled
			if isLogin or isReload then C_Timer.After(2, armFromSlots) end
		elseif event == "PLAYER_LEAVING_WORLD" then
			worldAt = GetTime()
			clearAll()
		elseif event == "PLAYER_DEAD" then
			clearAll()
		end
	end)
end

-- the bar refreshing: hosts may have changed, an assignment may be new
if hooksecurefunc then
	for _, method in ipairs({ "UpdateMiniTotemBar", "UpdateActiveTotemOverlays" }) do
		if type(SP[method]) == "function" then
			hooksecurefunc(SP, method, function() SP:UsualTotemRefresh() end)
		end
	end
	-- the Effects Look and every Effects setting: the look again
	if type(SP.ApplyCueSettings) == "function" then
		hooksecurefunc(SP, "ApplyCueSettings", function() SP:UsualTotemRefresh(true) end)
	end
	if type(SP.OnProfileChanged) == "function" then
		hooksecurefunc(SP, "OnProfileChanged", function() SP:ApplyUsualTotemSettings() end)
	end
end
if SP.OnOnOff then SP:OnOnOff(function() SP:ApplyUsualTotemSettings() end) end

-- ---------------------------------------------------------------------------
-- Settings: Totem Bar > Effects (the rows go under the bar's own effects: a look
-- on the element's button when something happens to its totem)
-- ---------------------------------------------------------------------------
do
	local fluffy = SP.options and SP.options.args and SP.options.args.fluffy
	local sec = fluffy and fluffy.args and fluffy.args.totembar_effects_section
	if sec and sec.args then
		local args = sec.args
		local function usualOn() return SP.opt.usualTotemReminder == true end
		local function off() return not usualOn() end
		local function apply() SP:ApplyUsualTotemSettings() end
		local function alertsOn()
			local db = rawget(_G, "ShamanPowerExpiringAlertsDB")
			return SP.ExpiringAlertsLoaded == true and type(db) == "table" and db.enabled == true
		end
		args.usual_header = { order = 3, type = "header", name = "Put Your Usual Totem Back" }
		args.usual_desc = { order = 3.01, type = "description",
			name = "When a temporary totem you dropped (like Grounding, Tremor or Mana Tide) ends, that element's button"
				.. " lights up until you drop your usual totem again. Your usual totem is the one assigned to that"
				.. " element on your bar. It never casts anything or changes your assignments." }
		args.usualTotemReminder = { order = 3.02, type = "toggle", width = "full",
			name = "Remind Me to Put My Usual Totem Back",
			desc = function()
				return "When a temporary totem you dropped ends, the element's button lights up until you drop your usual"
					.. " totem (the one assigned on your bar), use " .. (SPCompat.SpellName(TOTEMIC_CALL) or "Totemic Call")
					.. ", die, or change that element's assignment. Works in fights on both games."
			end,
			get = function() return usualOn() end,
			set = function(_, v) SP.opt.usualTotemReminder = v and true or nil; apply() end }
		args.usualTotemStyle = { order = 3.03, type = "select", width = "full", name = "Reminder Style",
			desc = "Glow: the button's edges glow gold. Pulse: the icon pulses darker. Both follow the Effects Look"
				.. " above: Elemental paints them in the element's color.",
			values = { glow = "Glow", pulse = "Pulse" }, sorting = { "glow", "pulse" },
			disabled = off,
			get = function() return SP.opt.usualTotemStyle == "pulse" and "pulse" or "glow" end,
			set = function(_, v) SP.opt.usualTotemStyle = (v == "pulse") and "pulse" or nil; apply() end }
		args.usualTotemLabel = { order = 3.04, type = "toggle", width = "full", name = "Write BACK on the Button",
			desc = "BACK along the bottom of the button. A Compact line says Put Windfury back, with your own totem's"
				.. " name. With Dynamic Mode the button shows the totem you dropped, so your usual totem sits in its"
				.. " corner instead.",
			disabled = off,
			get = function() return SP.opt.usualTotemLabel ~= false end,
			set = function(_, v)
				if v then SP.opt.usualTotemLabel = nil else SP.opt.usualTotemLabel = false end
				apply()
			end }
		args.usualTotemAlert = { order = 3.05, type = "toggle", width = "full", name = "Also Show a Text Alert",
			desc = "A line like Put Windfury back in the Expiring Alerts text, at its spot and size. No sound.",
			disabled = off,
			get = function() return SP.opt.usualTotemAlert == true end,
			set = function(_, v) SP.opt.usualTotemAlert = v and true or nil end }
		args.usual_alert_note = { order = 3.06, type = "description",
			hidden = function() return not (usualOn() and SP.opt.usualTotemAlert == true) or alertsOn() end,
			name = "|cffffa040The text alert shows in Expiring Alerts, which is turned off right now. Turn Expiring Alerts"
				.. " on to see it.|r" }
		args.usual_hide_note = { order = 3.065, type = "description",
			hidden = function() return not (usualOn() and SP.opt.hideWhenNoTotems == true) end,
			name = function()
				return "|cffffa040Hide When No Totems is on: when your temporary totem was the only totem down, the bar"
					.. " hides with it and can't show the reminder. "
					.. (SP.opt.usualTotemAlert == true and "The text alert still shows it.|r"
						or "Turn on the text alert to still get it.|r")
			end }
		args.usual_where = { order = 3.07, type = "description",
			name = "|cffa0a0a0Shows on ShamanPower's own totem buttons and Compact lines, and on your usual totem in its"
				.. " flyout, Totem Row or Grid row. Not on Blizzard's Totem Bar.|r" }
		args.usual_test = { order = 3.08, type = "execute", name = "Test the Reminder",
			desc = "Shows the reminder for 5 seconds on your Air button, or on the next element with an assigned totem"
				.. " (Water, Earth, Fire), with the text alert if it is on.",
			disabled = off,
			func = function() SP:TestUsualTotemReminder() end }
		-- Totems That Count as Temporary (13 / 16 switches): each totem's menu on Totem Bar > Bar now
		-- (SP:SetUsualTotemTemporary); one line says where they went
		args.usual_temp_note = { order = 3.1, type = "description",
			name = "Which totems count as temporary (Tremor, Grounding, Mana Tide...): right-click a totem on Totem Bar > Bar,"
				.. " then Counts As Temporary." }
	end
end
