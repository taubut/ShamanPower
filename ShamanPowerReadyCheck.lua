-- ============================================================================
-- Ready Check Sweep + Totem Items
--
-- On a ready check (and, if wanted, on entering an instance, after you come
-- back to life, or /sp check) list what this shaman is missing: shield, weapon
-- imbue, totem items in the bags (WoW: Forever, where totems still need them),
-- assigned totems not down, low mana. Each check and each way of showing it is
-- an option. A check the game hides right now is listed as "could not check",
-- never counted as fine.
--
-- Separately, on WoW: Forever, warn once when one of the four totem items goes
-- missing from the bags.
--
-- Event-driven only: nothing runs while no check is pending. The panel's refresh
-- events are registered only while the panel is up.
-- ============================================================================

local SP = ShamanPower
if not SP then return end
if select(2, UnitClass("player")) ~= "SHAMAN" then return end

local FOREVER = (SPCompat.FOREVER)
local secret = issecretvalue or function() return false end
local GetWeaponEnchantInfoC = (SPCompat and SPCompat.GetWeaponEnchantInfo) or GetWeaponEnchantInfo
local GetItemCountC = (C_Item and C_Item.GetItemCount) or GetItemCount
local GetItemInfoInstantC = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local GetItemIconC = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
local GetItemNameC = (C_Item and C_Item.GetItemNameByID) or function(id) return (GetItemInfo(id)) end
local GetSpellTextureC = (C_Spell and C_Spell.GetSpellTexture) or GetSpellTexture
-- the weapon imbue rows show Windfury Weapon's icon (8232 on both clients), not the weapon
local function ImbueIcon() return GetSpellTextureC(8232) or "Interface\\Icons\\Spell_Nature_Cyclone" end

local ELEMENTS = { "Earth", "Fire", "Water", "Air" }
local TOTEM_ITEMS = { 5175, 5176, 5177, 5178 }   -- Earth / Fire / Water / Air Totem (vanilla tools)
local GOLD = "|cffFFD100"
local TAG = "|cff0070ddShamanPower|r: "

-- Totem items are needed where the client is the vanilla line (WoW: Forever).
local ITEMS_NEEDED = FOREVER

local DEFAULTS = {
	-- on for WoW: Forever; opt-in on Anniversary, so an upgrade changes nothing
	enabled = (SPCompat.FOREVER),
	onReadyCheck = true,
	onEnterInstance = false,
	checkShield = true,
	checkImbue = true,
	checkTotemItems = true,
	checkAssigned = false,   -- the only check off by default
	checkMana = true,
	manaPercent = 0.8,
	showPanel = true,
	showChat = true,
	playSound = false,
	soundName = "Raid Warning",
	panelScale = 1,
	panelOpacity = 1,
	itemWarn = true,
	itemWarnScreen = false,
	-- 3.0.8: the same check once you are alive again (opt-in). Brought back in a
	-- fight: "wait" for its end, or "remind" at once with a short reminder.
	onResurrect = false,
	resurrectInFight = "wait",
}
-- the support code (/sp support) reports only what differs from these
SP.SUPPORT_PROFILE_DEFAULTS = SP.SUPPORT_PROFILE_DEFAULTS or {}
SP.SUPPORT_PROFILE_DEFAULTS.readyCheck = DEFAULTS

local function cfg()
	local o = SP.opt
	if not o then return DEFAULTS end
	local c = o.readyCheck
	if type(c) ~= "table" then c = {}; o.readyCheck = c end
	-- The first 3.0 test builds had the mana check off by default, and the loop
	-- below saves every default the first time it runs: switch it on once for
	-- those characters (no released version had it, so nobody chose "off").
	if not c.checkManaMigrated then
		c.checkManaMigrated = true
		if c.checkMana == false then c.checkMana = true end
	end
	for k, v in pairs(DEFAULTS) do if c[k] == nil then c[k] = v end end
	return c
end

-- ---------------------------------------------------------------------------
-- Checks. Each returns a list entry { icon, text } when something is missing,
-- false when all is well, nil when it cannot tell right now (a hidden value).
-- ---------------------------------------------------------------------------
-- When you last died (GetTime(), from PLAYER_DEAD below): your shield goes with
-- you, so a record of a shield cast before then is known to be gone.
local diedAt
-- WoW: Forever: when you last cast Lightning or Water Shield yourself (your own
-- casts are always seen, in fights too). While buffs are hidden the record of
-- that cast can go before the shield does (its charges are counted down by
-- guess), so after a death only "no cast since" counts as missing.
local lastShieldCast
if FOREVER and SP.ShadowShieldCast then
	hooksecurefunc(SP, "ShadowShieldCast", function(_, unit)
		if unit ~= "player" then return end
		-- a cast opens a new record stamped now; a proc only takes a charge off
		local rec = SP.shadowShield
		if rec and rec.start == GetTime() then lastShieldCast = rec.start end
	end)
end
-- Cached until the spellbook changes: bag updates ask this often.
local knownCache = {}
do
	local f = CreateFrame("Frame")
	if SPCompat and SPCompat.StressRegister then SPCompat.StressRegister(f, "Ready Check (spells)") end
	f:RegisterEvent("SPELLS_CHANGED")
	f:SetScript("OnEvent", function() wipe(knownCache) end)
end
local function elementKnown(element)
	if knownCache[element] ~= nil then return knownCache[element] end
	local spells = SP.Totems and SP.Totems[element]
	local known = false
	if spells then
		for _, id in pairs(spells) do
			if SPCompat.KnowsSpellID(id) then known = true break end
		end
	end
	knownCache[element] = known
	return known
end

local function shieldLabel()
	return SPCompat.SpellLabel(324, "Lightning") .. " or " .. SPCompat.SpellLabel(FOREVER and 408510 or 24398, "Water Shield")
end
local function shieldMissingText() return "No " .. shieldLabel() end

local function shieldIcon()
	local data = SP.ShieldSpells and SP.ShieldSpells[1]
	return data and GetSpellTextureC(data[1]) or "Interface\\Icons\\Spell_Nature_LightningShield"
end

local function shieldMissing()
	-- switched off, the shield read sleeps: /sp check reads it fresh
	if (not SP.shieldCache or SP:IsOff()) and SP.ScanPlayerShield then SP:ScanPlayerShield() end
	local c = SP.shieldCache
	if not c then return nil end
	local has
	if c.engineCount then
		-- buffs are hidden right now: our own record of the last shield cast.
		-- Shields drop when you die, so a record from before your last death
		-- is stale, and with no cast since that death the shield is gone. A
		-- cast since then whose record has gone (its charges guessed used up)
		-- could still be on you: that one is "could not check".
		local rec = SP.shadowShield
		if rec and not (diedAt and (rec.start or 0) < diedAt) then has = true
		elseif diedAt and not (lastShieldCast and lastShieldCast >= diedAt) then has = false
		else return nil end
	else
		has = c.hasShield and true or false
	end
	if has then return false end
	return { shieldIcon(), shieldMissingText() }
end

local function isWeapon(slot)
	local id = GetInventoryItemID("player", slot)
	if not id then return false end
	local classID = select(6, GetItemInfoInstantC(id))
	return classID == 2   -- Enum.ItemClass.Weapon
end

local function imbueMissing(out)
	local ok, mh, _, _, _, oh = pcall(GetWeaponEnchantInfoC)
	if not ok or secret(mh) or secret(oh) then return nil end
	local any = false
	if isWeapon(16) and not mh then
		out[#out + 1] = { ImbueIcon(), "No weapon imbue on your main hand" }
		any = true
	end
	if isWeapon(17) and not oh then
		out[#out + 1] = { ImbueIcon(), "No weapon imbue on your off hand" }
		any = true
	end
	return any
end

-- count of one totem item, or nil when unreadable
local function itemCount(id)
	local ok, n = pcall(GetItemCountC, id)
	if not ok or secret(n) or type(n) ~= "number" then return nil end
	return n
end

-- adds a row per missing item; nil when any item's count could not be read
local function totemItemsMissing(out)
	if not ITEMS_NEEDED then return false end
	local any, unread = false, false
	for element = 1, 4 do
		if elementKnown(element) then
			local n = itemCount(TOTEM_ITEMS[element])
			if n == nil then
				unread = true
			elseif n == 0 then
				out[#out + 1] = { GetItemIconC(TOTEM_ITEMS[element]) or "Interface\\Icons\\INV_Misc_QuestionMark",
					"No " .. (GetItemNameC(TOTEM_ITEMS[element]) or (ELEMENTS[element] .. " Totem")) .. " in your bags" }
				any = true
			end
		end
	end
	if unread then return nil end
	return any
end

-- adds a row per assigned totem not down; nil when any of them could not be read
local function assignedMissing(out)
	local mine = ShamanPower_Assignments and SP.player and ShamanPower_Assignments[SP.player]
	if not mine and not SP.pendingAssignments then return false end
	local any, unread = false, false
	for element = 1, 4 do
		local idx = SP:AssignedIndex(element)   -- a flyout pick made in this fight first
		if type(idx) == "number" and idx > 0 then
			local spellID = SP.GetTotemSpell and SP:GetTotemSpell(element, idx)
			local name, _, icon
			if spellID and SPCompat.KnowsSpellID(spellID) then name, _, icon = GetSpellInfo(spellID) end
			if name then
				local ok, have = pcall(SP.GetElementTotemInfo, SP, element)
				if not ok or secret(have) then
					unread = true
				elseif not have then
					out[#out + 1] = { icon or "Interface\\Icons\\INV_Misc_QuestionMark", name .. " is not down" }
					any = true
				end
			end
		end
	end
	if unread then return nil end
	return any
end

local MANA_ICON = "Interface\\Icons\\Spell_Nature_ManaRegenTotem"
local function manaMissing()
	local ok, cur, max = pcall(function() return UnitPower("player", 0), UnitPowerMax("player", 0) end)
	if not ok or secret(cur) or secret(max) or type(cur) ~= "number" or type(max) ~= "number" or max <= 0 then return nil end
	local pct = cur / max
	if pct >= (cfg().manaPercent or 0.8) then return false end
	return { MANA_ICON, string.format("Mana at %d%%", math.floor(pct * 100 + 0.5)) }
end

-- Two lists of { icon, text }: what is missing, and what could not be checked
-- (the game hides it right now). An empty first list only means "nothing
-- missing" while the second one is empty too.
local function collect()
	local c, out, unknown = cfg(), {}, {}
	if c.checkShield then
		local r = shieldMissing()
		if r then out[#out + 1] = r
		elseif r == nil then unknown[#unknown + 1] = { shieldIcon(), shieldLabel() } end
	end
	if c.checkImbue and imbueMissing(out) == nil then unknown[#unknown + 1] = { ImbueIcon(), "Weapon imbues" } end
	if c.checkTotemItems and totemItemsMissing(out) == nil then
		unknown[#unknown + 1] = { GetItemIconC(TOTEM_ITEMS[1]) or "Interface\\Icons\\INV_Misc_QuestionMark", "Totem items in your bags" }
	end
	if c.checkAssigned and assignedMissing(out) == nil then
		unknown[#unknown + 1] = { "Interface\\Icons\\Spell_Nature_StoneSkinTotem", "Assigned totems" }
	end
	if c.checkMana then
		local r = manaMissing()
		if r then out[#out + 1] = r
		elseif r == nil then unknown[#unknown + 1] = { MANA_ICON, "Mana" } end
	end
	return out, unknown
end

-- ---------------------------------------------------------------------------
-- The panel
-- ---------------------------------------------------------------------------
-- 280: "Ready check: you are missing" fits the title font on one line beside the X
local PANEL_W, ROW_ICON, PAD = 280, 20, 10
local panel, rows = nil, {}
local hideTimer
-- why the real list is up ("readycheck", "instance", "manual", "rez", or
-- "rezfight" for the short reminder in a fight); nil while none is (a sample
-- can cover it)
local sweepReason
-- true while the check after your resurrection is still to come or has just run
-- (set with Check After Resurrection, below)
local rezCovers
local refreshEvents = { "UNIT_AURA", "UNIT_INVENTORY_CHANGED", "BAG_UPDATE_DELAYED", "PLAYER_TOTEM_UPDATE", "UNIT_POWER_UPDATE" }

-- the title: what is missing, or (only checks that could not run) what to look at yourself
-- (each fits the panel on one line)
local TITLES = {
	readycheck = { "Ready check: you are missing", "Ready check: look at these" },
	rez = { "Resurrected: you are missing", "Resurrected: look at these" },
	other = { "You are missing", "Look at these" },
}
local function titleFor(reason, anyMissing)
	local t = TITLES[reason] or TITLES.other
	if anyMissing then return t[1] end
	return t[2]
end
-- brought back in a fight, with "Show a Short Reminder": it never says what is missing
local REMINDER_TITLE = "Resurrected in a fight"
local REMINDER_TEXT = "Check your shield and weapon imbues"

local function savePos(f)
	local point, _, relPoint, x, y = f:GetPoint(1)
	cfg().pos = { point = point, relPoint = relPoint, x = x, y = y }
end

local function applyPos(f)
	local p = cfg().pos
	f:ClearAllPoints()
	if p and p.point then f:SetPoint(p.point, UIParent, p.relPoint or p.point, p.x or 0, p.y or 0)
	else f:SetPoint("CENTER", UIParent, "CENTER", 0, 180) end
end

-- Theme (General > Themes, spot mod.readycheck): the panel's background and
-- border. nil on Standard: today's look stays exactly as it is. The background
-- still follows the opacity setting. restore (a theme change) puts today's
-- colours back.
local function themeLook(f, restore)
	if not SP.ThemeColor then return end
	local r, g, b = SP:ThemeColor("mod.readycheck", "bg")
	if r then
		f.bg:SetColorTexture(r, g, b, (SP:ThemeAlpha("mod.readycheck", "bg") or 0.9) * (cfg().panelOpacity or 1))
	elseif restore then
		f.bg:SetColorTexture(SP:SPColor("windowBg", 0.9 * (cfg().panelOpacity or 1)))
	end
	r, g, b = SP:ThemeColor("mod.readycheck", "border")
	if r then
		for _, t in ipairs(f.spEdges) do t:SetColorTexture(r, g, b, 1) end
	elseif restore then
		SP:SPSetBorderColor(f, "border")
	end
end

-- the opacity setting fades the background only: the border, text and icons
-- stay solid, so the list reads over the world at any setting
local function applyLook(f)
	local c = cfg()
	f:SetScale(c.panelScale or 1)
	f.bg:SetColorTexture(SP:SPColor("windowBg", 0.9 * (c.panelOpacity or 1)))
	themeLook(f)   -- the theme's colours (nothing on Standard)
end

function SP:ReadyCheckFrame()
	if panel then return panel end
	local f = CreateFrame("Frame", "ShamanPowerReadyCheckFrame", UIParent)
	f:SetSize(PANEL_W, 60)
	-- DIALOG, like the game's own ready check: "Check Now" in the settings window
	-- (HIGH) shows the list on top of it
	f:SetFrameStrata("DIALOG")
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self) self:StartMoving() end)
	f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); savePos(self) end)
	-- ShamanPower's own panel look (ShamanPowerDialog.lua): dark background, the
	-- settings window's soft 1.5px edge with the four elements along the top, the
	-- dialog fonts (Fira Sans) for the title and the rows
	f.bg = f:CreateTexture(nil, "BACKGROUND")
	f.bg:SetAllPoints(f)
	SP:SPMakeBorder(f, "border", 1.5)
	if SP.CreateElementStripe then   -- (no brand file: an update the game has not loaded yet)
		local stripe = SP:CreateElementStripe(f)
		stripe:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
		stripe:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
	end
	local title = f:CreateFontString(nil, "OVERLAY")
	title:SetFontObject(SP.SPDialogFonts.title)
	title:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -PAD)
	title:SetWidth(PANEL_W - 2 * PAD - 18); title:SetJustifyH("LEFT"); title:SetWordWrap(true)
	f.title = title
	local close = SP:CreateSPCloseButton(f, 18)
	close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
	close:SetScript("OnClick", function() SP:HideReadyCheckPanel() end)
	f.close = close
	f:Hide()
	-- Escape closes it (UISpecialFrames) as the X does: the timer and the
	-- refresh events go with it. Not while a sample fills it, and not for a
	-- hidden UI (Alt+Z), where the frame stays "shown".
	tinsert(UISpecialFrames, "ShamanPowerReadyCheckFrame")
	f:SetScript("OnHide", function(self)
		if not self:IsShown() and not SP.readyCheckDemoActive and (hideTimer or sweepReason) then
			SP:HideReadyCheckPanel()
		end
	end)
	panel = f
	applyPos(f); applyLook(f)
	return f
end

local function row(i)
	local r = rows[i]
	if r then return r end
	r = {}
	r.icon = panel:CreateTexture(nil, "ARTWORK")
	r.icon:SetSize(ROW_ICON, ROW_ICON)
	r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	r.text = panel:CreateFontString(nil, "OVERLAY")
	r.text:SetFontObject(SP.SPDialogFonts.text)
	r.text:SetJustifyH("LEFT"); r.text:SetWordWrap(true)
	r.text:SetWidth(PANEL_W - 2 * PAD - ROW_ICON - 8)
	rows[i] = r
	return r
end

-- one row at y; gray = a check that could not run (dimmed icon and text). Returns the next y.
local function placeRow(f, i, y, item, gray)
	local r = row(i)
	r.icon:SetTexture(item[1])
	r.icon:SetDesaturated(gray == true)
	r.icon:SetAlpha(gray and 0.7 or 1)
	r.text:SetText(item[2])
	r.text:SetTextColor(SP:SPColor(gray and "textDim" or "text"))
	r.icon:ClearAllPoints(); r.icon:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -y)
	r.text:ClearAllPoints(); r.text:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
	r.icon:Show(); r.text:Show()
	return y + math.max(ROW_ICON, r.text:GetStringHeight()) + 6
end

-- the small-caps heading over the checks that could not run
local function unknownHeading(f)
	local h = f.unknownHead
	if not h then
		h = f:CreateFontString(nil, "OVERLAY")
		h:SetFontObject(SP.SPDialogFonts.tiny)
		h:SetJustifyH("LEFT"); h:SetWordWrap(true)
		h:SetWidth(PANEL_W - 2 * PAD)
		h:SetTextColor(SP:SPColor("textDim"))   -- the dim label color: reads over the world at any opacity
		f.unknownHead = h
	end
	return h
end

-- list: what is missing; unknown (optional): what could not be checked, under its own heading
local function layout(titleText, list, unknown)
	local f = SP:ReadyCheckFrame()
	f.title:SetText(titleText)
	local y = PAD + f.title:GetStringHeight() + 8
	local n = 0
	for _, item in ipairs(list) do
		n = n + 1
		y = placeRow(f, n, y, item)
	end
	if unknown and #unknown > 0 then
		local h = unknownHeading(f)
		h:SetText(#unknown > 1 and "COULD NOT CHECK: THE GAME HIDES THESE RIGHT NOW"
			or "COULD NOT CHECK: THE GAME HIDES IT RIGHT NOW")
		if n > 0 then y = y + 2 end
		h:ClearAllPoints(); h:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -y)
		h:Show()
		y = y + h:GetStringHeight() + 6
		for _, item in ipairs(unknown) do
			n = n + 1
			y = placeRow(f, n, y, item, true)
		end
	elseif f.unknownHead then
		f.unknownHead:Hide()
	end
	for i = n + 1, #rows do rows[i].icon:Hide(); rows[i].text:Hide() end
	f:SetHeight(y + PAD - 6)
end

-- the short reminder for a resurrection in a fight
local function reminderLayout()
	layout(REMINDER_TITLE, { { shieldIcon(), REMINDER_TEXT } })
end

local watcher = CreateFrame("Frame")
if SPCompat and SPCompat.StressRegister then SPCompat.StressRegister(watcher, "Ready Check (list)") end
local refreshQueued = false

local function stopWatching()
	for _, e in ipairs(refreshEvents) do watcher:UnregisterEvent(e) end
	pcall(watcher.UnregisterEvent, watcher, "WEAPON_ENCHANT_CHANGED")
end

function SP:HideReadyCheckPanel()
	if hideTimer then hideTimer:Cancel(); hideTimer = nil end
	sweepReason = nil
	stopWatching()
	if panel and not SP.readyCheckDemoActive then panel:Hide() end
end

-- Re-check while the panel is up; the panel goes away once nothing is missing
-- and every check could run. (The short reminder never changes on its own.)
local function refresh()
	refreshQueued = false
	if not (panel and panel:IsShown()) or SP.readyCheckDemoActive or not sweepReason or sweepReason == "rezfight" then
		stopWatching()
		return
	end
	local list, unknown = collect()
	if #list == 0 and #unknown == 0 then SP:HideReadyCheckPanel() return end
	layout(titleFor(sweepReason, #list > 0), list, unknown)
end

local function queueRefresh()
	if refreshQueued then return end
	refreshQueued = true
	C_Timer.After(0.3, refresh)   -- coalesce bursts (a bag sort, an aura storm)
end

watcher:SetScript("OnEvent", function(_, event, unit)
	if (event == "UNIT_AURA" or event == "UNIT_INVENTORY_CHANGED" or event == "UNIT_POWER_UPDATE") and unit ~= "player" then return end
	queueRefresh()
end)

-- WoW: Forever: the moment the game stops hiding things (a little after a
-- fight), a list that is up looks again, so "could not check" turns into the
-- real answer
if SPCompat and SPCompat.OnUnrestricted then
	SPCompat.OnUnrestricted(function()
		if panel and panel:IsShown() and sweepReason and sweepReason ~= "rezfight" and not SP.readyCheckDemoActive then
			queueRefresh()
		end
	end)
end

-- the unit events for the player only: in a raid the others' auras, bags and
-- mana would otherwise all reach the handler just to be dropped
local UNIT_EVENTS = { UNIT_AURA = true, UNIT_INVENTORY_CHANGED = true, UNIT_POWER_UPDATE = true }
local function startWatching()
	for _, e in ipairs(refreshEvents) do
		if e ~= "UNIT_POWER_UPDATE" or cfg().checkMana then
			if UNIT_EVENTS[e] and watcher.RegisterUnitEvent then
				pcall(watcher.RegisterUnitEvent, watcher, e, "player")
			else
				pcall(watcher.RegisterEvent, watcher, e)
			end
		end
	end
	pcall(watcher.RegisterEvent, watcher, "WEAPON_ENCHANT_CHANGED")   -- Mainline family only
end

-- ---------------------------------------------------------------------------
-- The sweep
-- ---------------------------------------------------------------------------
local function names(items)
	local parts = {}
	for _, item in ipairs(items) do parts[#parts + 1] = item[2] end
	return table.concat(parts, ", ")
end

local function playListSound(c)
	if c.playSound and SP.GetSoundFile then
		pcall(SP.PlaySoundWithVolume, SP, SP:GetSoundFile(c.soundName), nil, true)
	end
end

local function hideLater()
	if hideTimer then hideTimer:Cancel() end
	hideTimer = C_Timer.NewTimer(30, function() hideTimer = nil; SP:HideReadyCheckPanel() end)
end

-- reason: "readycheck", "instance", "manual", "rez" (alive again)
function SP:RunReadyCheckSweep(reason)
	local c = cfg()
	if (not c.enabled or SP:IsOff()) and reason ~= "manual" then return end   -- /sp check still answers when switched off
	-- a ghost run back into an instance: the check after the resurrection is the
	-- one list (the entering check would be a second one a moment later)
	if reason == "instance" and rezCovers and rezCovers() then return end
	-- alive again: read the shield fresh (one read, nothing kept from the life before)
	if reason == "rez" and SP.ScanPlayerShield and not SP:IsOff() then SP:ScanPlayerShield() end
	local list, unknown = collect()
	if #list == 0 and #unknown == 0 then
		if reason == "manual" then print(TAG .. "nothing missing.") end
		if panel and panel:IsShown() then SP:HideReadyCheckPanel() end
		return
	end
	-- /sp check always answers in chat, as "nothing missing" does
	if c.showChat or (reason == "manual" and #list == 0) then
		local line = TAG
		if #list > 0 then line = line .. GOLD .. "missing:|r " .. names(list) end
		if #unknown > 0 then
			line = line .. (#list > 0 and "; " or "") .. "could not check (the game hides it right now): " .. names(unknown)
		end
		print(line)
	end
	-- the sound means something to put back: not for checks that only could not run
	if #list > 0 then playListSound(c) end
	if c.showPanel then
		local f = SP:ReadyCheckFrame()
		applyLook(f)
		sweepReason = reason
		layout(titleFor(reason, #list > 0), list, unknown)
		f:Show()
		startWatching()
		-- a ready check hides at READY_CHECK_FINISHED; the others after a while
		if reason ~= "readycheck" then
			hideLater()
		elseif hideTimer then
			hideTimer:Cancel(); hideTimer = nil
		end
	end
end

-- Brought back in a fight with "Show a Short Reminder": a reminder that claims
-- nothing about what is missing (the full check follows once the fight ends).
local function showRezReminder()
	local c = cfg()
	if c.showChat then print(TAG .. "resurrected in a fight: check your shield and weapon imbues") end
	playListSound(c)
	if not c.showPanel then return end
	stopWatching()   -- it never changes on its own
	local f = SP:ReadyCheckFrame()
	applyLook(f)
	sweepReason = "rezfight"
	reminderLayout()
	f:Show()
	hideLater()
end

-- Settings preview / Unlock UI: sample rows, never hidden by the sweep's timers.
function SP:ReadyCheckDemo(on)
	local f = self:ReadyCheckFrame()
	if on then
		self.readyCheckDemoActive = true
		local sample = {
			{ GetSpellTextureC(324) or "Interface\\Icons\\Spell_Nature_LightningShield", shieldMissingText() },
			{ ImbueIcon(), "No weapon imbue on your main hand" },
		}
		if ITEMS_NEEDED then sample[#sample + 1] = { GetItemIconC(TOTEM_ITEMS[3]) or "Interface\\Icons\\INV_Misc_QuestionMark",
			"No " .. (GetItemNameC(TOTEM_ITEMS[3]) or "Water Totem") .. " in your bags" } end
		applyLook(f)
		layout("Ready check: you are missing", sample)
		f:Show()
	else
		self.readyCheckDemoActive = nil
		-- a real list that was up under the sample (a ready check still running) comes back
		if sweepReason == "rezfight" then
			applyLook(f)
			reminderLayout()
			f:Show()
			return
		end
		if sweepReason then
			local list, unknown = collect()
			if #list > 0 or #unknown > 0 then
				applyLook(f)
				layout(titleFor(sweepReason, #list > 0), list, unknown)
				f:Show()
				startWatching()
				return
			end
			self:HideReadyCheckPanel()
		end
		f:Hide()
	end
end

-- Settings changes: scale/opacity apply at once to a shown panel.
function SP:UpdateReadyCheckLook()
	if panel then applyLook(panel) end
end

-- Theme changed (General > Themes): repaint the panel if it was built.
if SP.OnThemeChanged then
	-- today's colours, for the Themes tab's swatches (the dialog palette)
	if SP.ThemeSetRoleStd then
		SP:ThemeSetRoleStd("mod.readycheck", "bg", "0E141E")
		SP:ThemeSetRoleStd("mod.readycheck", "border", "2B374A")   -- the dialog palette's `border`: the window edge
	end
	SP:OnThemeChanged(function() if panel then themeLook(panel, true) end end)
end

if SP.RegisterPreview then
	SP:RegisterPreview("readycheck", { frame = function() return SP:ReadyCheckFrame() end, demo = "SP:ReadyCheckDemo" })
end
if SP.UnlockModules then
	table.insert(SP.UnlockModules, {
		key = "readycheck", label = "Ready Check",
		enabled = function() local c = cfg(); return c.enabled and c.showPanel and true or false end,
		reset = function() cfg().pos = nil; if panel then applyPos(panel) end end,
	})
end

-- ---------------------------------------------------------------------------
-- Totem items outside ready checks (WoW: Forever)
-- ---------------------------------------------------------------------------
local itemHad = {}      -- [element] = true/false as last seen
local errorWarnedAt = {}

local function warnItem(element)
	local name = GetItemNameC(TOTEM_ITEMS[element]) or (ELEMENTS[element] .. " Totem")
	print(TAG .. "no |cffffffff" .. name .. "|r in your bags - " .. ELEMENTS[element] .. " totems cannot be cast without it.")
	if cfg().itemWarnScreen and RaidNotice_AddMessage and RaidWarningFrame then
		RaidNotice_AddMessage(RaidWarningFrame, "No " .. name .. " in your bags!", { r = 1, g = 0.3, b = 0.3 })
	end
end

-- atLogin: warn about every missing one; otherwise only a change from present to missing
local function checkItems(atLogin)
	if not (ITEMS_NEEDED and cfg().itemWarn) or SP:IsOff() then return end
	for element = 1, 4 do
		if elementKnown(element) then
			local n = itemCount(TOTEM_ITEMS[element])
			if n ~= nil then
				local has = n > 0
				if not has and (atLogin or itemHad[element] == true) then warnItem(element) end
				itemHad[element] = has
			end
		end
	end
end

local ev = CreateFrame("Frame")
if SPCompat and SPCompat.StressRegister then SPCompat.StressRegister(ev, "Ready Check") end
ev:RegisterEvent("READY_CHECK")
ev:RegisterEvent("READY_CHECK_FINISHED")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
if ITEMS_NEEDED then
	ev:RegisterEvent("BAG_UPDATE_DELAYED")
	ev:RegisterEvent("UI_ERROR_MESSAGE")
end
local loginDone = false
ev:SetScript("OnEvent", function(_, event, a1, a2)
	if SP:IsOff() then return end   -- switched off: no sweep, no item warnings
	if event == "READY_CHECK" then
		if cfg().onReadyCheck then SP:RunReadyCheckSweep("readycheck") end
	elseif event == "READY_CHECK_FINISHED" then
		if panel and panel:IsShown() then SP:HideReadyCheckPanel() end
	elseif event == "PLAYER_ENTERING_WORLD" then
		if not loginDone then
			loginDone = true
			C_Timer.After(5, function() checkItems(true) end)   -- bags finish loading after login
		end
		local c = cfg()
		if c.enabled and c.onEnterInstance and IsInInstance() then
			C_Timer.After(3, function() SP:RunReadyCheckSweep("instance") end)
		end
	elseif event == "BAG_UPDATE_DELAYED" then
		checkItems(false)
	elseif event == "UI_ERROR_MESSAGE" then
		-- "Requires Water Totem": only when the message is readable
		local msg = a2
		if not cfg().itemWarn or type(msg) ~= "string" or secret(msg) then return end
		for element = 1, 4 do
			local name = GetItemNameC(TOTEM_ITEMS[element])
			if type(name) == "string" and name ~= "" and msg:find(name, 1, true) then
				-- the item is in the bags: the error is about something else that
				-- names it (Fire Nova with no Fire totem down), not a missing item
				if (itemCount(TOTEM_ITEMS[element]) or 0) > 0 then return end
				local now = GetTime()
				if not errorWarnedAt[element] or now - errorWarnedAt[element] > 10 then
					errorWarnedAt[element] = now
					warnItem(element)
				end
				return
			end
		end
	end
end)

-- ---------------------------------------------------------------------------
-- Check After Resurrection (opt-in): once you are alive again, the same check.
-- Three events that only come around a death; the end of a fight is listened
-- to only while a check waits for it. One settling timer per resurrection
-- (PLAYER_ALIVE and PLAYER_UNGHOST can both come for one), and dying again
-- cancels whatever was waiting. Nothing hidden is read in a fight: there it
-- waits for the fight to end, or shows a reminder that names nothing missing.
-- ---------------------------------------------------------------------------
local REZ_SETTLE = 2     -- seconds for your auras, mana and the shield read to settle
local FIGHT_SETTLE = 3   -- after a fight: the game shows your buffs again about 2 seconds after it ends
local rezTimer           -- the settling timer
local rezWaiting         -- the check waits for the fight to end
local rezReminded        -- the short reminder was shown for this resurrection
local deadSeen           -- you died (or logged in dead) and have not been checked since
local rezSweptAt         -- when the check after a resurrection last ran
local rezLoad            -- the last loading screen began dead, as a ghost, or with that check on its way
local REZ_COVERS = 5     -- seconds a just-run check still counts as on its way when a loading screen begins

local rezFrame = CreateFrame("Frame")
if SPCompat and SPCompat.StressRegister then SPCompat.StressRegister(rezFrame, "Ready Check (resurrection)") end

local function aliveNow()
	local ok, dead = pcall(UnitIsDeadOrGhost, "player")
	return ok and not secret(dead) and not dead
end

local function rezOn()
	local c = cfg()
	return c.enabled and c.onResurrect and not SP:IsOff()
end

local function stopRez()
	if rezTimer then rezTimer:Cancel(); rezTimer = nil end
	rezWaiting, rezReminded = nil, nil
	rezFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
end

local function rezSettled()
	rezTimer = nil
	if not rezOn() then
		stopRez()
		if aliveNow() then deadSeen = nil end
		return
	end
	-- PLAYER_ALIVE also comes on releasing your spirit: a ghost waits for PLAYER_UNGHOST
	if not aliveNow() then return end
	deadSeen = nil
	if InCombatLockdown() then
		-- brought back in a fight: the check waits for its end
		if cfg().resurrectInFight == "remind" and not rezReminded then
			rezReminded = true
			showRezReminder()
		end
		rezWaiting = true
		rezFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end
	stopRez()
	rezSweptAt = GetTime()
	SP:RunReadyCheckSweep("rez")
end

-- (RunReadyCheckSweep) a ghost that runs back into an instance comes back to life
-- as it enters: that resurrection's check covers the entering check
rezCovers = function()
	if not rezOn() then return false end
	if rezTimer or rezWaiting then return true end              -- on its way
	if deadSeen and not aliveNow() then return true end         -- still a ghost: it comes once you are alive
	if rezLoad then rezLoad = nil; return true end   -- this loading screen began as a ghost run back (that one entering check)
	return false
end

local function startRezSettle(seconds)
	if rezTimer then rezTimer:Cancel() end
	rezTimer = C_Timer.NewTimer(seconds or REZ_SETTLE, rezSettled)
end

rezFrame:RegisterEvent("PLAYER_DEAD")
rezFrame:RegisterEvent("PLAYER_ALIVE")
rezFrame:RegisterEvent("PLAYER_UNGHOST")
rezFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
rezFrame:RegisterEvent("PLAYER_LEAVING_WORLD")
rezFrame:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_DEAD" then
		diedAt, deadSeen = GetTime(), true
		stopRez()
		-- what was listed for the life before goes with it
		if sweepReason == "rez" or sweepReason == "rezfight" then SP:HideReadyCheckPanel() end
	elseif event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
		if not deadSeen then return end   -- (PLAYER_ALIVE can come at login too)
		if rezOn() then startRezSettle() elseif aliveNow() then deadSeen = nil end
	elseif event == "PLAYER_REGEN_ENABLED" then
		if rezWaiting then
			rezWaiting = nil
			rezFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
			startRezSettle(FIGHT_SETTLE)
		end
	elseif event == "PLAYER_LEAVING_WORLD" then
		-- a loading screen begins: a ghost running back in (or a check after a resurrection on its
		-- way) makes that check the one list for the instance entered; any other trip is checked as usual
		rezLoad = (deadSeen and not aliveNow()) or rezTimer ~= nil or rezWaiting == true
			or (rezSweptAt ~= nil and GetTime() - rezSweptAt < REZ_COVERS)
	elseif event == "PLAYER_ENTERING_WORLD" then
		-- logged in, or through a loading screen, dead or as a ghost
		if not aliveNow() then deadSeen = true end
	end
end)

-- For testing without dying: act as if you were just brought back (your death
-- is not recorded, so your shield reads as it really is).
function SP:ReadyCheckTestResurrection()
	deadSeen = true
	if rezOn() then startRezSettle() end
end

-- switched off: a list that is up goes away with the rest, and nothing waits
SP:OnOnOff(function(off) if off then SP:HideReadyCheckPanel(); stopRez() end end)

-- ---------------------------------------------------------------------------
-- Options: Modules > Ready Check
-- ---------------------------------------------------------------------------
local fluffy = SP.options and SP.options.args and SP.options.args.fluffy
if fluffy and fluffy.args then
	local function get(key) return function() return cfg()[key] end end
	local function set(key, after) return function(_, v) cfg()[key] = v; if after then after() end end end
	local function off() return not cfg().enabled end
	fluffy.args.readycheck_section = {
		order = 19.6,
		name = "|cff0070ddReady Check|r",
		type = "group",
		args = {
			desc = {
				order = 0, type = "description", width = "full",
				name = "When a ready check starts, ShamanPower lists what you are missing: your shield, a weapon imbue"
					.. (ITEMS_NEEDED and ", a totem item in your bags" or "") .. ", and anything else you pick below."
					.. " Pick what it checks and how it tells you. /sp check runs it any time.",
			},
			enabled = {
				order = 1, type = "toggle", name = "Enable Ready Check Sweep", width = "full",
				get = get("enabled"), set = set("enabled"),
			},
			when_header = { order = 10, type = "header", name = "When" },
			onReadyCheck = { order = 11, type = "toggle", name = "On a Ready Check", width = 1.5, disabled = off, get = get("onReadyCheck"), set = set("onReadyCheck"),
				desc = "Check the moment someone starts a ready check." },
			onEnterInstance = { order = 12, type = "toggle", name = "On Entering a Dungeon or Raid", width = 1.5, disabled = off, get = get("onEnterInstance"), set = set("onEnterInstance"),
				desc = "Check a few seconds after you enter an instance." },
			onResurrect = { order = 12.5, type = "toggle", name = "Check After Resurrection", width = 1.5, disabled = off,
				get = get("onResurrect"), set = set("onResurrect"),
				desc = "When you come back to life (someone resurrects you, you use Reincarnation, or you release and run back),"
					.. " check what you need to put back before the next pull: your shield, weapon imbues and anything else on under"
					.. " What to Check. It shows the way you picked under How to Show It." },
			resurrectInFight = { order = 12.6, type = "select", name = "During a Fight", width = 1.5,
				values = { wait = "Wait Until the Fight Ends", remind = "Show a Short Reminder" }, sorting = { "wait", "remind" },
				hidden = function() return not cfg().onResurrect end, disabled = off,
				get = get("resurrectInFight"), set = set("resurrectInFight"),
				desc = "Brought back in the middle of a fight: wait and check once the fight is over, or right away show"
					.. " \"Check your shield and weapon imbues\" and still check once the fight is over. The reminder never says"
					.. " what is missing." },
			checkNow = { order = 13, type = "execute", name = "Check Now", width = 1,
				desc = "Run the check right now (same as /sp check).",
				func = function() SP:RunReadyCheckSweep("manual") end },
			what_header = { order = 20, type = "header", name = "What to Check" },
			checkShield = { order = 21, type = "toggle", name = "Lightning or Water Shield", width = 1.5, disabled = off, get = get("checkShield"), set = set("checkShield") },
			checkImbue = { order = 22, type = "toggle", name = "Weapon Imbue", width = 1.5, disabled = off, get = get("checkImbue"), set = set("checkImbue"),
				desc = "Main hand, and off hand when you carry a weapon there." },
			checkTotemItems = { order = 23, type = "toggle", name = "Totem Items in Bags", width = 1.5, disabled = off, get = get("checkTotemItems"), set = set("checkTotemItems"),
				hidden = function() return not ITEMS_NEEDED end,
				desc = "Earth, Fire, Water and Air Totem: totems of an element cannot be cast without its item. Only elements you have a totem for." },
			checkAssigned = { order = 24, type = "toggle", name = "Assigned Totems Down", width = 1.5, disabled = off, get = get("checkAssigned"), set = set("checkAssigned"),
				desc = "List each assigned totem that is not down right now." },
			checkMana = { order = 25, type = "toggle", name = "Mana", width = 1.5, disabled = off, get = get("checkMana"), set = set("checkMana") },
			manaPercent = { order = 26, type = "range", name = "Warn Below", min = 0.1, max = 1, step = 0.05, isPercent = true, width = 1.5,
				hidden = function() return not cfg().checkMana end, disabled = off, get = get("manaPercent"), set = set("manaPercent") },
			how_header = { order = 30, type = "header", name = "How to Show It" },
			showPanel = { order = 31, type = "toggle", name = "On-Screen List", width = 1.5, disabled = off, get = get("showPanel"), set = set("showPanel"),
				desc = "A small list with icons. It goes away when the ready check ends or once you have fixed everything. Move it with Unlock UI." },
			panelScale = { order = 32, type = "range", name = "List Size", min = 0.5, max = 2, step = 0.05, isPercent = true, width = 1.5,
				hidden = function() return not cfg().showPanel end, disabled = off, get = get("panelScale"),
				set = set("panelScale", function() SP:UpdateReadyCheckLook() end) },
			panelOpacity = { order = 33, type = "range", name = "List Background Opacity", min = 0.2, max = 1, step = 0.05, isPercent = true, width = 1.5,
				desc = "How see-through the list's background is. Its border, text and icons always stay solid.",
				hidden = function() return not cfg().showPanel end, disabled = off, get = get("panelOpacity"),
				set = set("panelOpacity", function() SP:UpdateReadyCheckLook() end) },
			showChat = { order = 34, type = "toggle", name = "Line in My Chat Window", width = 1.5, disabled = off, get = get("showChat"), set = set("showChat"),
				desc = "Only you see it." },
			playSound = { order = 35, type = "toggle", name = "Play a Sound", width = 1.5, disabled = off, get = get("playSound"), set = set("playSound") },
			soundName = { order = 36, type = "select", name = "Sound", dialogControl = "LSM30_Sound",
				values = AceGUIWidgetLSMlists and AceGUIWidgetLSMlists.sound or {}, width = "double",
				hidden = function() return not cfg().playSound end, disabled = off, get = get("soundName"), set = set("soundName") },
			testSound = { order = 36.5, type = "execute", name = "Test Sound", desc = "Play the selected sound.", width = 0.7,
				hidden = function() return not cfg().playSound end, disabled = off,
				func = function() if SP.GetSoundFile then SP:PlaySoundWithVolume(SP:GetSoundFile(cfg().soundName), nil, true) end end },
			resetPos = { order = 37, type = "execute", name = "Reset List Position", width = 1,
				hidden = function() return not cfg().showPanel end,
				func = function() cfg().pos = nil; if panel then applyPos(panel) end end },
			items_header = { order = 40, type = "header", name = "Totem Items", hidden = function() return not ITEMS_NEEDED end },
			itemWarn = { order = 41, type = "toggle", name = "Warn When a Totem Item Is Missing", width = "full",
				hidden = function() return not ITEMS_NEEDED end, get = get("itemWarn"), set = set("itemWarn"),
				desc = "Any time, not only on ready checks: a line in your chat window when one of your totem items leaves your bags, at login if one is missing, and when a totem fails because of it." },
			itemWarnScreen = { order = 42, type = "toggle", name = "Also Big Text on My Screen", width = "full",
				hidden = function() return not ITEMS_NEEDED end, disabled = function() return not cfg().itemWarn end,
				get = get("itemWarnScreen"), set = set("itemWarnScreen"),
				desc = "Raid-warning-style text, drawn only on your screen." },
		},
	}
	SP.OrderSettingsBands(fluffy.args.readycheck_section, {
		{ keys = { "desc" } },
		{ keys = { "enabled" } },
		{ header = "what_header", name = "What to Check", keys = {
			"checkShield", "checkImbue", "checkTotemItems", "checkAssigned", "checkMana", "manaPercent",
		} },
		{ header = "how_header", name = "How to Show It", keys = { "showPanel", "showChat" } },
		{ header = "items_header", name = "Totem Items", keys = { "itemWarn", "itemWarnScreen" } },
		{ header = "look_header", name = "Look", keys = { "panelScale", "panelOpacity" },
			names = { panelScale = "Scale", panelOpacity = "Background Opacity" } },
		{ header = "when_header", name = "Behavior", keys = { "onReadyCheck", "onEnterInstance", "onResurrect", "resurrectInFight" } },
		{ header = "sound_header", name = "Sound", keys = { "playSound", "soundName", "testSound" },
			names = { playSound = "Play Sound" } },
		{ header = "position_header", name = "Position", keys = { "resetPos" },
			names = { resetPos = "Reset Position" } },
		{ header = "test_header", name = "Test / Reset", keys = { "checkNow" } },
	})
end
