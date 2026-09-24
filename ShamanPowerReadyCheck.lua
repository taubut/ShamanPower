-- ============================================================================
-- Ready Check Sweep + Totem Items
--
-- On a ready check (and, if wanted, on entering an instance or /sp check) list
-- what this shaman is missing: shield, weapon imbue, totem items in the bags
-- (WoW: Forever, where totems still need them), assigned totems not down, low
-- mana. Each check and each way of showing it is an option.
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

local FOREVER = (WOW_PROJECT_ID == WOW_PROJECT_MAINLINE)
local secret = issecretvalue or function() return false end
local GetWeaponEnchantInfoC = (SPCompat and SPCompat.GetWeaponEnchantInfo) or GetWeaponEnchantInfo
local GetItemCountC = (C_Item and C_Item.GetItemCount) or GetItemCount
local GetItemInfoInstantC = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local GetItemIconC = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
local GetItemNameC = (C_Item and C_Item.GetItemNameByID) or function(id) return (GetItemInfo(id)) end
local GetSpellTextureC = (C_Spell and C_Spell.GetSpellTexture) or GetSpellTexture

local ELEMENTS = { "Earth", "Fire", "Water", "Air" }
local TOTEM_ITEMS = { 5175, 5176, 5177, 5178 }   -- Earth / Fire / Water / Air Totem (vanilla tools)
local GOLD = "|cffffd200"
local TAG = "|cff0070ddShamanPower|r: "

-- Totem items are needed where the client is the vanilla line (WoW: Forever).
local ITEMS_NEEDED = FOREVER

local DEFAULTS = {
	-- on for WoW: Forever; opt-in on Anniversary, so an upgrade changes nothing
	enabled = (WOW_PROJECT_ID == WOW_PROJECT_MAINLINE),
	onReadyCheck = true,
	onEnterInstance = false,
	checkShield = true,
	checkImbue = true,
	checkTotemItems = true,
	checkAssigned = false,
	checkMana = false,
	manaPercent = 0.8,
	showPanel = true,
	showChat = true,
	playSound = false,
	soundName = "Raid Warning",
	panelScale = 1,
	panelOpacity = 1,
	itemWarn = true,
	itemWarnScreen = false,
}

local function cfg()
	local o = SP.opt
	if not o then return DEFAULTS end
	local c = o.readyCheck
	if type(c) ~= "table" then c = {}; o.readyCheck = c end
	for k, v in pairs(DEFAULTS) do if c[k] == nil then c[k] = v end end
	return c
end

-- ---------------------------------------------------------------------------
-- Checks. Each returns a list entry { icon, text } when something is missing,
-- false when all is well, nil when it cannot tell right now (a hidden value).
-- ---------------------------------------------------------------------------
-- cached until the spellbook changes: bag updates ask this often, and a name
-- lookup builds a table per call on Forever
local knownCache = {}
do
	local f = CreateFrame("Frame")
	if SPCompat and SPCompat.StressRegister then SPCompat.StressRegister(f, "Ready Check (spells)") end
	f:RegisterEvent("SPELLS_CHANGED")
	f:SetScript("OnEvent", function() wipe(knownCache) end)
end
local function elementKnown(element)
	if knownCache[element] ~= nil then return knownCache[element] end
	local names = SP.TotemNames and SP.TotemNames[element]
	local known = false
	if names then
		for _, name in pairs(names) do
			-- a name lookup answers only for spells in the spellbook; the table holds short names
			if type(name) == "string" and (GetSpellInfo(name .. " Totem") or GetSpellInfo(name)) then known = true break end
		end
	end
	knownCache[element] = known
	return known
end

local function shieldMissing()
	if not SP.shieldCache and SP.ScanPlayerShield then SP:ScanPlayerShield() end
	local c = SP.shieldCache
	if not c then return nil end
	local has
	if c.engineCount then
		-- buffs are hidden right now: our own record of the last shield cast
		if SP.shadowShield then has = true else return nil end
	else
		has = c.hasShield and true or false
	end
	if has then return false end
	local data = SP.ShieldSpells and SP.ShieldSpells[1]
	local icon = data and GetSpellTextureC(data[1]) or "Interface\\Icons\\Spell_Nature_LightningShield"
	return { icon, "No Lightning or Water Shield" }
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
		out[#out + 1] = { GetInventoryItemTexture("player", 16) or "Interface\\Icons\\Spell_Fire_FlameTounge", "No weapon imbue on your main hand" }
		any = true
	end
	if isWeapon(17) and not oh then
		out[#out + 1] = { GetInventoryItemTexture("player", 17) or "Interface\\Icons\\Spell_Fire_FlameTounge", "No weapon imbue on your off hand" }
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

local function totemItemsMissing(out)
	if not ITEMS_NEEDED then return false end
	local any = false
	for element = 1, 4 do
		if elementKnown(element) then
			local n = itemCount(TOTEM_ITEMS[element])
			if n == 0 then
				out[#out + 1] = { GetItemIconC(TOTEM_ITEMS[element]) or "Interface\\Icons\\INV_Misc_QuestionMark",
					"No " .. ELEMENTS[element] .. " Totem in your bags" }
				any = true
			end
		end
	end
	return any
end

local function assignedMissing(out)
	local mine = ShamanPower_Assignments and SP.player and ShamanPower_Assignments[SP.player]
	if not mine then return false end
	local any = false
	for element = 1, 4 do
		local idx = mine[element]
		if type(idx) == "number" and idx > 0 then
			local spellID = SP.GetTotemSpell and SP:GetTotemSpell(element, idx)
			local name, _, icon
			if spellID then name, _, icon = GetSpellInfo(spellID) end
			if name then   -- a totem this character knows
				local ok, have = pcall(SP.GetElementTotemInfo, SP, element)
				if ok and not secret(have) and not have then
					out[#out + 1] = { icon or "Interface\\Icons\\INV_Misc_QuestionMark", name .. " is not down" }
					any = true
				end
			end
		end
	end
	return any
end

local function manaMissing()
	local ok, cur, max = pcall(function() return UnitPower("player", 0), UnitPowerMax("player", 0) end)
	if not ok or secret(cur) or secret(max) or type(cur) ~= "number" or type(max) ~= "number" or max <= 0 then return nil end
	local pct = cur / max
	if pct >= (cfg().manaPercent or 0.8) then return false end
	return { "Interface\\Icons\\Spell_Nature_ManaRegenTotem", string.format("Mana at %d%%", math.floor(pct * 100 + 0.5)) }
end

local function collect()
	local c, out = cfg(), {}
	if c.checkShield then local r = shieldMissing(); if r then out[#out + 1] = r end end
	if c.checkImbue then imbueMissing(out) end
	if c.checkTotemItems then totemItemsMissing(out) end
	if c.checkAssigned then assignedMissing(out) end
	if c.checkMana then local r = manaMissing(); if r then out[#out + 1] = r end end
	return out
end

-- ---------------------------------------------------------------------------
-- The panel
-- ---------------------------------------------------------------------------
local PANEL_W, ROW_ICON, PAD = 260, 20, 10
local panel, rows = nil, {}
local hideTimer
local refreshEvents = { "UNIT_AURA", "UNIT_INVENTORY_CHANGED", "BAG_UPDATE_DELAYED", "PLAYER_TOTEM_UPDATE", "UNIT_POWER_UPDATE" }

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

local function applyLook(f)
	local c = cfg()
	f:SetScale(c.panelScale or 1)
	f:SetAlpha(c.panelOpacity or 1)
end

function SP:ReadyCheckFrame()
	if panel then return panel end
	local f = CreateFrame("Frame", "ShamanPowerReadyCheckFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
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
	if f.SetBackdrop then
		f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
		f:SetBackdropColor(0.05, 0.06, 0.09, 0.9)
		f:SetBackdropBorderColor(1, 0.82, 0, 0.8)
	end
	local title = f:CreateFontString(nil, "OVERLAY")
	SP:SetSPFont(title, "alerts", 13, "OUTLINE")
	title:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -PAD)
	title:SetWidth(PANEL_W - 2 * PAD - 18); title:SetJustifyH("LEFT"); title:SetWordWrap(true)
	title:SetTextColor(1, 0.82, 0)
	f.title = title
	local close = SP:CreateSPCloseButton(f, 18)
	close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
	close:SetScript("OnClick", function() SP:HideReadyCheckPanel() end)
	f.close = close
	f:Hide()
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
	SP:SetSPFont(r.text, "alerts", 12, "")
	r.text:SetJustifyH("LEFT"); r.text:SetWordWrap(true)
	r.text:SetWidth(PANEL_W - 2 * PAD - ROW_ICON - 8)
	r.text:SetTextColor(1, 1, 1)
	rows[i] = r
	return r
end

local function layout(titleText, list)
	local f = SP:ReadyCheckFrame()
	f.title:SetText(titleText)
	local y = PAD + f.title:GetStringHeight() + 8
	for i, item in ipairs(list) do
		local r = row(i)
		r.icon:SetTexture(item[1])
		r.text:SetText(item[2])
		r.icon:ClearAllPoints(); r.icon:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -y)
		r.text:ClearAllPoints(); r.text:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
		r.icon:Show(); r.text:Show()
		y = y + math.max(ROW_ICON, r.text:GetStringHeight()) + 6
	end
	for i = #list + 1, #rows do rows[i].icon:Hide(); rows[i].text:Hide() end
	f:SetHeight(y + PAD - 6)
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
	stopWatching()
	if panel and not SP.readyCheckDemoActive then panel:Hide() end
end

-- Re-check while the panel is up; the panel goes away once nothing is missing.
local function refresh()
	refreshQueued = false
	if not (panel and panel:IsShown()) or SP.readyCheckDemoActive then stopWatching() return end
	local list = collect()
	if #list == 0 then SP:HideReadyCheckPanel() return end
	layout(panel.title:GetText(), list)
end

watcher:SetScript("OnEvent", function(_, event, unit)
	if (event == "UNIT_AURA" or event == "UNIT_INVENTORY_CHANGED" or event == "UNIT_POWER_UPDATE") and unit ~= "player" then return end
	if refreshQueued then return end
	refreshQueued = true
	C_Timer.After(0.3, refresh)   -- coalesce bursts (a bag sort, an aura storm)
end)

local function startWatching()
	for _, e in ipairs(refreshEvents) do
		if e ~= "UNIT_POWER_UPDATE" or cfg().checkMana then pcall(watcher.RegisterEvent, watcher, e) end
	end
	pcall(watcher.RegisterEvent, watcher, "WEAPON_ENCHANT_CHANGED")   -- Mainline family only
end

-- ---------------------------------------------------------------------------
-- The sweep
-- ---------------------------------------------------------------------------
-- reason: "readycheck", "instance", "manual"
function SP:RunReadyCheckSweep(reason)
	local c = cfg()
	if not c.enabled and reason ~= "manual" then return end
	local list = collect()
	if #list == 0 then
		if reason == "manual" then print(TAG .. "nothing missing.") end
		if panel and panel:IsShown() then SP:HideReadyCheckPanel() end
		return
	end
	if c.showChat then
		local parts = {}
		for _, item in ipairs(list) do parts[#parts + 1] = item[2] end
		print(TAG .. GOLD .. "missing:|r " .. table.concat(parts, ", "))
	end
	if c.playSound and SP.GetSoundFile then
		pcall(SP.PlaySoundWithVolume, SP, SP:GetSoundFile(c.soundName), nil, true)
	end
	if c.showPanel then
		local f = SP:ReadyCheckFrame()
		applyLook(f)
		layout(reason == "readycheck" and "Ready check: you are missing" or "You are missing", list)
		f:Show()
		startWatching()
		if hideTimer then hideTimer:Cancel() end
		-- a ready check hides at READY_CHECK_FINISHED; the others after a while
		if reason ~= "readycheck" then hideTimer = C_Timer.NewTimer(30, function() hideTimer = nil; SP:HideReadyCheckPanel() end) end
	end
end

-- Settings preview / Unlock UI: sample rows, never hidden by the sweep's timers.
function SP:ReadyCheckDemo(on)
	local f = self:ReadyCheckFrame()
	if on then
		self.readyCheckDemoActive = true
		local sample = {
			{ GetSpellTextureC(324) or "Interface\\Icons\\Spell_Nature_LightningShield", "No Lightning or Water Shield" },
			{ "Interface\\Icons\\Spell_Fire_FlameTounge", "No weapon imbue on your main hand" },
		}
		if ITEMS_NEEDED then sample[#sample + 1] = { GetItemIconC(TOTEM_ITEMS[3]) or "Interface\\Icons\\INV_Misc_QuestionMark", "No Water Totem in your bags" } end
		applyLook(f)
		layout("Ready check: you are missing", sample)
		f:Show()
	else
		self.readyCheckDemoActive = nil
		f:Hide()
	end
end

-- Settings changes: scale/opacity apply at once to a shown panel.
function SP:UpdateReadyCheckLook()
	if panel then applyLook(panel) end
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
	print(TAG .. "no |cffffffff" .. ELEMENTS[element] .. " Totem|r in your bags - " .. ELEMENTS[element] .. " totems cannot be cast without it.")
	if cfg().itemWarnScreen and RaidNotice_AddMessage and RaidWarningFrame then
		RaidNotice_AddMessage(RaidWarningFrame, "No " .. ELEMENTS[element] .. " Totem in your bags!", { r = 1, g = 0.3, b = 0.3 })
	end
end

-- atLogin: warn about every missing one; otherwise only a change from present to missing
local function checkItems(atLogin)
	if not (ITEMS_NEEDED and cfg().itemWarn) then return end
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
			panelOpacity = { order = 33, type = "range", name = "List Opacity", min = 0.2, max = 1, step = 0.05, isPercent = true, width = 1.5,
				hidden = function() return not cfg().showPanel end, disabled = off, get = get("panelOpacity"),
				set = set("panelOpacity", function() SP:UpdateReadyCheckLook() end) },
			showChat = { order = 34, type = "toggle", name = "Line in My Chat Window", width = 1.5, disabled = off, get = get("showChat"), set = set("showChat"),
				desc = "Only you see it." },
			playSound = { order = 35, type = "toggle", name = "Play a Sound", width = 1.5, disabled = off, get = get("playSound"), set = set("playSound") },
			soundName = { order = 36, type = "select", name = "Sound", dialogControl = "LSM30_Sound",
				values = AceGUIWidgetLSMlists and AceGUIWidgetLSMlists.sound or {}, width = "double",
				hidden = function() return not cfg().playSound end, disabled = off, get = get("soundName"), set = set("soundName") },
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
end
