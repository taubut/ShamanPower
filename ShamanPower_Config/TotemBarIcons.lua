-- ShamanPower_Config :: TotemBarIcons
-- The Totem Bar's Bar tab as an icon page (A15, 2026-10-07), on the shared icon row
-- (IconRow.lua). Two rows:
--   Buttons: the bar's buttons as they sit on it: the four elements in the bar's order
--     (each shows its assigned totem, its element's 2 px line under it), then Drop All
--     (the real Drop All icon, the four lines under it) and, on TBC Anniversary, Earth
--     Shield. Click: on or off the bar. Right-click: its menu (an element: its Drop All
--     place / Not Dropped and its keys; Drop All: the whole drop order, Blizzard Totem
--     Sets on WoW: Forever, its key; Earth Shield: its Flyout, Players In The Flyout,
--     Running Out). Drag an element: its place on the bar (opt.totemBarOrder).
--   Totems: a line per element, every totem this game has, in the flyout's order.
--     Click: in or out of its element's flyout. Right-click: Pulse Bar, Pulse Flash (the
--     9 that pulse), Counts As Temporary (Put Your Usual Totem Back), its key, Copy /
--     Paste / Copy To, Hide From The Flyout, Reset This Totem.
-- No new saved keys: every value is today's setting (Show Earth Totem ..., Show Drop All
-- Button, totemBarOrder, dropOrder and the Excludes, flyoutTotems, the pulse lists,
-- usualTotemTemp, the Earth Shield flyout and its filter, the Blizzard Totem Sets
-- switches) and Earth Shield's own Running Out slot (ShamanPowerCdItems.lua type 12).
-- The pulse lists keep their old form: a totem turned Off turns its "Only Show ... for
-- Specific Totems" switch on (a list ticked while that switch was off did nothing and
-- starts afresh), the last one turned On again turns it off.
local _, ns = ...
local Core = ns.Core
local SP = ShamanPower
if not (Core and SP and ns.IconRow) then return end

local Menu = ns.IconRow.Menu
local Slider = Menu.Slider
local SEP = { separator = true }
local FOREVER = SPCompat and SPCompat.FOREVER

local ELEM = { "Earth", "Fire", "Water", "Air" }
local EKEY = { "earth", "fire", "water", "air" }
local SHOW_KEY = { "totemBarShowEarth", "totemBarShowFire", "totemBarShowWater", "totemBarShowAir" }
local EXCLUDE_KEY = { "excludeEarthFromDropAll", "excludeFireFromDropAll", "excludeWaterFromDropAll", "excludeAirFromDropAll" }
local ORD = { "1st", "2nd", "3rd", "4th" }
local BIND_BUTTON = { "SHAMANPOWER_EARTH_TOTEM", "SHAMANPOWER_FIRE_TOTEM", "SHAMANPOWER_WATER_TOTEM", "SHAMANPOWER_AIR_TOTEM" }
local BIND_FLYOUT = { "SHAMANPOWER_FLYOUT_EARTH", "SHAMANPOWER_FLYOUT_FIRE", "SHAMANPOWER_FLYOUT_WATER", "SHAMANPOWER_FLYOUT_AIR" }
local DROPALL, ES, RECALL = "dropall", "es", "recall"
-- Totemic Recall (its Bar choice: Totem Bar): its icon sits after Drop All here, with the Cooldown Bar
-- page's own menu for it (CdbarIcons.lua ns.CdbarRecall); on the Cooldown Bar it is on that page instead
local function RecallHere() return ns.CdbarRecall ~= nil and SP.RecallOnTotemBarPage ~= nil and SP:RecallOnTotemBarPage() end
local ES_SLOT = 12          -- Earth Shield's own Running Out settings (ShamanPowerCdItems.lua)
local COTE = 66842          -- Call of the Elements: the Drop All button's icon with Blizzard's totem sets
local GENERIC_DROPALL = 136024

local BTN_CAPTION = "|cff3FA9F5CLICK|r a button to show or hide it on the bar. |cff3FA9F5RIGHT-CLICK|r it for its settings."
	.. " |cff3FA9F5DRAG|r an element to move it on the bar. |cff3FA9F5Dark|r: not learned yet."
local BTN_CAPTION_NATIVE = "|cff3FA9F5RIGHT-CLICK|r Drop All for its drop order and Blizzard Totem Sets. You use Blizzard's"
	.. " Totem Bar (Totem Bar > Style), so its own buttons are on screen instead of ShamanPower's."
local TOT_CAPTION = "|cff3FA9F5CLICK|r a totem to show or hide it in its flyout. |cff3FA9F5RIGHT-CLICK|r it for its settings."
	.. " |cff3FA9F5DRAG|r it along its line to change the order they fly out in."
	.. " |cff3FA9F5Dark|r totems aren't learned yet: set them up now, they show once learned."
local TOT_CAPTION_NATIVE = "|cff3FA9F5RIGHT-CLICK|r a totem for its settings. Blizzard's Totem Bar shows its own flyouts,"
	.. " so a click here doesn't change them."

local function O() return SP.opt end
local function Run(fn, ...)
	if type(SP[fn]) ~= "function" then return end
	local ok, err = pcall(SP[fn], SP, ...)
	if not ok then geterrorhandler()(err) end
end
local function Say(text) print("|cff0070ddShamanPower|r: " .. text) end

local function SpellTexture(id)
	if not id then return nil end
	if C_Spell and C_Spell.GetSpellTexture then
		local t = C_Spell.GetSpellTexture(id)
		if t then return t end
	end
	if GetSpellTexture then
		local t = GetSpellTexture(id)
		if t then return t end
	end
	return (select(3, GetSpellInfo(id)))
end

-- Blizzard's Totem Bar in place of ShamanPower's (WoW: Forever, Totem Bar > Style): its own
-- buttons and flyouts are on screen, so only Drop All and the totems' menus mean something
local function Native()
	if not (FOREVER and SP.HasTotemBar and SP:HasTotemBar()) then return false end
	return O().useBlizzardTotemBar == true
end
local function HasESButton() return not (SPCompat and SPCompat.earthShieldExists == false) end

local function KeyText(binding)
	local key = binding and GetBindingKey and GetBindingKey(binding)
	if not key then return "Not Set" end
	return (GetBindingText and GetBindingText(key, "KEY_")) or key
end
local function KeybindMode() Run("SetKeybindMode", true) end

-- a choice from a list ({ value, label } or "-" for a separator); get() -> value, own; set(v) keeps it open
-- 3.0.9: a list entry's 4th field is that choice's picture on the icon's own screen (IconScreen.lua),
-- `pic` the fallback (an On / Off row: its ON picture); the menus ignore them
local function Choice(text, list, get, set, tip, disabled, pic)
	return {
		text = text, tip = tip, disabled = disabled, pic = pic,
		value = function()
			local v, own = get()
			for _, c in ipairs(list) do
				if type(c) == "table" and c[1] == v then return c[2], own and true or false end
			end
			return "", false
		end,
		sub = function()
			local cur = get()
			local items = {}
			for _, c in ipairs(list) do
				if c == "-" then
					items[#items + 1] = SEP
				else
					local v = c[1]
					items[#items + 1] = { text = c[2], selected = cur == v, tip = c[3], pic = c[4],
						onClick = function() return set(v) end }
				end
			end
			return items
		end,
	}
end

-- ---------------------------------------------------------------------------
-- The bar's buttons
-- ---------------------------------------------------------------------------
local function ElementShown(e) return O()[SHOW_KEY[e]] ~= false end
local function ElementLearned(e) return not SP.IsElementLearned or SP:IsElementLearned(e) end

local function ValidOrder(t)
	if type(t) ~= "table" then return nil end
	local seen = {}
	for i = 1, 4 do
		local e = t[i]
		if type(e) ~= "number" or e < 1 or e > 4 or seen[e] then return nil end
		seen[e] = true
	end
	return t
end
local function CopyOrder(t)
	t = ValidOrder(t) or { 1, 2, 3, 4 }
	return { t[1], t[2], t[3], t[4] }
end
local function BarOrder() return CopyOrder(O().totemBarOrder) end
local function DropOrder() return CopyOrder(O().dropOrder) end
local function IsDefaultOrder(t) return t[1] == 1 and t[2] == 2 and t[3] == 3 and t[4] == 4 end

local function AssignedIcon(e)
	local idx = SP.AssignedIndex and SP:AssignedIndex(e) or 0
	if idx and idx > 0 and SP.GetTotemIcon then return SP:GetTotemIcon(e, idx) end
	return SP.ElementIcons and SP.ElementIcons[e] or 134400
end
local function AssignedEmpty(e)
	local idx = SP.AssignedIndex and SP:AssignedIndex(e) or 0
	return not idx or idx == 0
end

-- Drop All: an element's place among the elements it drops (nil: Not Dropped)
local function Excluded(e) return O()[EXCLUDE_KEY[e]] and true or false end
local function DroppedCount()
	local n = 0
	for e = 1, 4 do if not Excluded(e) then n = n + 1 end end
	return n
end
local function DropPlace(e)
	if Excluded(e) then return nil end
	local p = 0
	for _, x in ipairs(DropOrder()) do
		if not Excluded(x) then
			p = p + 1
			if x == e then return p end
		end
	end
	return nil
end
local function ElementOwn(e)
	if Excluded(e) then return true end
	return DropOrder()[e] ~= e
end

-- the element to `place` among the dropped ones; picked while Not Dropped: dropped again, and
-- where it was when that is already the place asked for
local function SetDropPlace(e, place)
	if InCombatLockdown() then return end
	local order = DropOrder()
	local from
	for i, x in ipairs(order) do if x == e then from = i break end end
	local rank = 1
	for i = 1, from - 1 do if not Excluded(order[i]) then rank = rank + 1 end end
	if rank ~= place then
		table.remove(order, from)
		local dropped = {}
		for i, x in ipairs(order) do if not Excluded(x) then dropped[#dropped + 1] = i end end
		local at
		if place <= #dropped then
			at = dropped[place]
		elseif #dropped > 0 then
			at = dropped[#dropped] + 1
		else
			at = from
		end
		table.insert(order, math.max(1, math.min(#order + 1, at)), e)
		O().dropOrder = order
		Run("LoadoutOrderChanged")   -- (3.0.9.9) the loadout in use keeps it (Loadouts Remember the Totem Bar and Drop Order)
	end
	if Excluded(e) then
		SP:SetDropAllExclude(e, false)   -- (the active loadout keeps it too; the button and macros follow)
	else
		Run("UpdateDropAllButton")
	end
end
local function SetNotDropped(e)
	if InCombatLockdown() or Excluded(e) then return end
	SP:SetDropAllExclude(e, true)
end

local function SetsBar() return (FOREVER and SP.HasTotemBar and SP:HasTotemBar()) and true or false end
local function SetsKnown() return (SP.HasTotemSets and SP:HasTotemSets()) and true or false end
local function SetsOwnDropAll() return SetsKnown() and O().dropAllUsesTotemSets ~= false end

-- what the real Drop All button shows: Call of the Elements with Blizzard's totem sets (dark until
-- it is learned), else the button's own icon (the next totem it drops)
local function DropAllIcon()
	local own = SP.DropAllOwnIcon and SP:DropAllOwnIcon()
	if own then return own end
	if SetsBar() and (not SetsKnown() or O().dropAllUsesTotemSets ~= false) then
		return SpellTexture(COTE) or GENERIC_DROPALL
	end
	local btn = _G.ShamanPowerAutoDropAll
	local icon = btn and (btn.icon or _G.ShamanPowerAutoDropAllIcon)
	local t = icon and icon.GetTexture and icon:GetTexture()
	return t or GENERIC_DROPALL
end
local function DropAllLearned()
	if SetsBar() then return SetsKnown() end
	for e = 1, 4 do if ElementLearned(e) then return true end end
	return false
end
local function DropAllOwn()
	if SP.DropAllOwnIcon and SP:DropAllOwnIcon() then return true end
	for e = 1, 4 do if Excluded(e) then return true end end
	if not IsDefaultOrder(DropOrder()) then return true end
	if SetsBar() then
		local o = O()
		if o.dropAllUsesTotemSets == false or o.totemSetsSyncAssignments == false or o.totemSetsAdoptFromBar == false then return true end
	end
	return false
end

-- Earth Shield (TBC Anniversary: its button at the end of the bar)
local ROLES = { { "TANK", "Tanks" }, { "HEALER", "Healers" }, { "DAMAGER", "Damage" } }
local CLASSES = { { "WARRIOR", "Warriors" }, { "PALADIN", "Paladins" }, { "HUNTER", "Hunters" }, { "ROGUE", "Rogues" },
	{ "PRIEST", "Priests" }, { "SHAMAN", "Shamans" }, { "MAGE", "Mages" }, { "WARLOCK", "Warlocks" }, { "DRUID", "Druids" } }
local function ESName() return (SPCompat and SPCompat.SpellLabel and SPCompat.SpellLabel(974, "Earth Shield")) or "Earth Shield" end
local function ESLearned() return (SP.HasEarthShield and SP:HasEarthShield()) and true or false end
local function Picked(tbl, k)
	local t = O()[tbl]
	return (type(t) == "table" and t[k]) and true or false
end
local function AnyPicked()
	for _, tbl in ipairs({ "esFlyoutRoles", "esFlyoutClasses" }) do
		local t = O()[tbl]
		if type(t) == "table" and next(t) then return true end
	end
	return false
end
local function ClassText(c)
	local col = RAID_CLASS_COLORS and RAID_CLASS_COLORS[c[1]]
	if col and col.colorStr then return "|c" .. col.colorStr .. c[2] .. "|r" end
	return c[2]
end
local function WhoText()
	local names = {}
	for _, r in ipairs(ROLES) do if Picked("esFlyoutRoles", r[1]) then names[#names + 1] = r[2] end end
	for _, c in ipairs(CLASSES) do if Picked("esFlyoutClasses", c[1]) then names[#names + 1] = c[2] end end
	if #names == 0 then return "Everyone" end
	if #names > 2 then return #names .. " Picked" end
	return table.concat(names, ", ")
end
local function ESOwn()
	if AnyPicked() then return true end
	return (SP.CdItemHasOwn and SP:CdItemHasOwn(ES_SLOT)) and true or false
end
-- Earth Shield's Running Out back to how it came (off, Turns red, 60 sec): no value of its own
-- where the fallback already reads that, else that value as its own
local ES_RUNOUT_DEFAULT = { runOutSecs = 60, cueRunning = false, cueRunningStyle = "red" }
local function ResetESRunOut()
	if not (SP.SetCdItemOpt and SP.CdItemOpt) then return end
	for name, def in pairs(ES_RUNOUT_DEFAULT) do
		if SP:CdItemOwnOpt(ES_SLOT, name) ~= nil then SP:SetCdItemOpt(ES_SLOT, name, nil) end
		if SP:CdItemOpt(ES_SLOT, name) ~= def then SP:SetCdItemOpt(ES_SLOT, name, def) end
	end
end
local function ResetES()
	local o = O()
	o.totemBarShowEarthShield = true
	o.enableESFlyout = false
	o.esFlyoutRoles, o.esFlyoutClasses = nil, nil
	ResetESRunOut()
	Run("UpdateEarthShieldButton")
	Run("CreateEarthShieldFlyout", true)
end

-- ---------------------------------------------------------------------------
-- The totems
-- ---------------------------------------------------------------------------
local PULSE_KEY   -- [rank-1 spell] = its ShamanPower.PulsingTotems key
local function PulseKey(id)
	if not PULSE_KEY then
		PULSE_KEY = {}
		for k, d in pairs(SP.PulsingTotems or {}) do
			if type(d) == "table" and d.spellID then PULSE_KEY[d.spellID] = k end
		end
	end
	return PULSE_KEY[id]
end
local function PartOn(listKey, onlyKey, key)
	local o = O()
	return not (o[onlyKey] and type(o[listKey]) == "table" and o[listKey][key])
end
local function PulseBarOn(key) return PartOn("pulseTotemsOff", "pulseOnlySome", key) end
local function PulseFlashOn(key) return PartOn("pulseFlashTotemsOff", "pulseFlashOnlySome", key) end
-- one totem's pulse bar or flash on / off, in the lists' own form (see the top)
local function SetPart(listKey, onlyKey, key, on)
	local o = O()
	if on then
		if type(o[listKey]) == "table" then o[listKey][key] = nil end
		if o[onlyKey] and not (type(o[listKey]) == "table" and next(o[listKey])) then
			o[onlyKey], o[listKey] = nil, nil
		end
	else
		if not o[onlyKey] then o[listKey] = nil end
		o[onlyKey] = true
		if type(o[listKey]) ~= "table" then o[listKey] = {} end
		o[listKey][key] = true
	end
end
local function SetPulseBar(key, on) SetPart("pulseTotemsOff", "pulseOnlySome", key, on) end
local function SetPulseFlash(key, on) SetPart("pulseFlashTotemsOff", "pulseFlashOnlySome", key, on) end

local TEMP_CHOICE
local function TempApplies(id)
	if not TEMP_CHOICE then
		TEMP_CHOICE = {}
		for _, base in ipairs(SP.USUAL_TOTEM_CHOICES or {}) do TEMP_CHOICE[base] = true end
	end
	return (TEMP_CHOICE[id] and SP.UsualTotemChoiceExists and SP:UsualTotemChoiceExists(id)) and true or false
end
local function TempOn(id) return (SP.UsualTotemIsTemporary and SP:UsualTotemIsTemporary(id)) and true or false end
local function TempDefault(id) return (SP.UsualTotemTempDefault and SP:UsualTotemTempDefault(id)) and true or false end
local function SetTemp(id, v)
	if SP.SetUsualTotemTemporary then SP:SetUsualTotemTemporary(id, v) end
end

local function FlyKey(e, idx) return EKEY[e] .. "_" .. idx end
local function InFlyout(item)
	local f = O().flyoutTotems
	return f == nil or f[FlyKey(item.e, item.idx)] ~= false
end
local function SetInFlyout(item, v)
	local o = O()
	if type(o.flyoutTotems) ~= "table" then o.flyoutTotems = {} end
	o.flyoutTotems[FlyKey(item.e, item.idx)] = v and true or false
	if not InCombatLockdown() then Run("RecreateTotemFlyouts"); Run("SetupKeybindings") end   -- its key follows
end

local function TotemOwn(item)
	local pk = PulseKey(item.key)
	if pk and not (PulseBarOn(pk) and PulseFlashOn(pk)) then return true end
	if TempApplies(item.key) and TempOn(item.key) ~= TempDefault(item.key) then return true end
	local own = SP.opt and type(SP.opt.totemOwn) == "table" and SP.opt.totemOwn[item.key]   -- (3.0.9.2) its own effects
	if type(own) == "table" and next(own) ~= nil then return true end
	return false
end

-- every totem this game has, element by element, in the flyout's order
local TOTEMS = {}
local function Totems()
	if TOTEMS[1] then return TOTEMS end
	for e = 1, 4 do
		local t = SP.Totems and SP.Totems[e] or {}
		-- in the flyout's order (3.0.9: the player's, dragged here; else the game's)
		local order
		if SP.FlyoutOrder then order = SP:FlyoutOrder(e) end
		if not order then
			order = {}
			local last = SP.GetTotemIndexLimit and SP:GetTotemIndexLimit(e) or 10
			for idx = 1, math.max(last, 10) do if t[idx] then order[#order + 1] = idx end end
		end
		for _, idx in ipairs(order) do
			local id = t[idx]
			if id and (not (SPCompat and SPCompat.SpellExists) or SPCompat.SpellExists(id)) then
				TOTEMS[#TOTEMS + 1] = { key = id, e = e, idx = idx, name = SP.GetTotemName and SP:GetTotemName(e, idx) or tostring(id) }
			end
		end
	end
	return TOTEMS
end
local function TotemsChanged() wipe(TOTEMS) end   -- (the order changed: listed again)
local function TotemLearned(item) return not SP.KnowsTotem or SP:KnowsTotem(item.e, item.idx) end
local function TotemIcon(item)
	return SpellTexture(item.key) or (SP.GetTotemIcon and SP:GetTotemIcon(item.e, item.idx)) or 134400
end

-- ---------------------------------------------------------------------------
-- The rows (made below; the menus call them)
-- ---------------------------------------------------------------------------
local BtnRow, TotRow
local function Changed(row) row:Changed(true) return true end

-- (3.0.9) the flyout order: a totem's new place among its element's totems (position: 1 = first).
-- The flyouts are built again in it, the row lists it again; the menu stays open on the totem.
local function SetTotemPlace(item, position)
	local order = {}
	for _, t in ipairs(Totems()) do
		if t.e == item.e and t.key ~= item.key then order[#order + 1] = t.idx end
	end
	if position < 1 then position = 1 elseif position > #order + 1 then position = #order + 1 end
	table.insert(order, position, item.idx)
	SP:SetFlyoutOrder(item.e, order)
end
local function OrderChanged()
	TotemsChanged()
	if not InCombatLockdown() then Run("RecreateTotemFlyouts") end
	if TotRow:ListChanged() then
		-- the row drawn again in the new order; the menu opens again on the totem (Release keeps it
		-- while the row is writing)
		TotRow.writing = true
		local cfg = _G.ShamanPowerConfig
		if cfg and cfg.RefreshCurrent then cfg:RefreshCurrent() end
		TotRow.writing = false
		return true
	end
	return Changed(TotRow)
end
-- a totem dragged along its line (IconRow's move: `to` is its place in the whole list): its place in
-- its element's order; a drop past the element's line lands at that end
local function MoveTotem(item, to)
	local first, last
	for i, t in ipairs(Totems()) do
		if t.e == item.e then first = first or i; last = i end
	end
	if not first then return end
	if to < first then to = first elseif to > last then to = last end
	SetTotemPlace(item, to - first + 1)
	TotemsChanged()
	if not InCombatLockdown() then Run("RecreateTotemFlyouts") end
end
-- where a totem sits in its element's order, and how many there are
local function TotemPlace(item)
	local pos, n = 1, 0
	for _, t in ipairs(Totems()) do
		if t.e == item.e then
			n = n + 1
			if t.key == item.key then pos = n end
		end
	end
	return pos, n
end

local function LockedSay()
	Say("|cffe64a4aThe Totem Bar's settings can't change in combat - try again after the fight.|r")
end

-- Drop All's place, one element's row (the same setting in Drop All's menu > Drop Order)
local function DropAllTip(e)
	local t = "Its place when Drop All drops your totems, one per click. Not Dropped: Drop All leaves " .. ELEM[e]
		.. " out (your own " .. ELEM[e] .. " button still casts it). The same setting as Drop All's menu > Drop Order."
	if AssignedEmpty(e) then
		t = t .. "\n\n|cffffa040" .. ELEM[e] .. " is set to Empty, so Drop All already skips it. This setting applies once you"
			.. " assign " .. ((e == 1 or e == 4) and "an " or "a ") .. ELEM[e] .. " totem.|r"
	end
	if SetsOwnDropAll() then
		t = t .. "\n\n|cffffa040\"Drop All Casts Call of the Elements\" is on, and that spell drops all four totems at once, so"
			.. " the place is not used by the button. It still orders the SP_DropAll macro.|r"
	end
	if SetsBar() then
		if O().totemSetsSyncAssignments == false then
			t = t .. "\n\nNot Dropped: \"Call of the Elements Follows My Assignments\" is off, so Blizzard's totem bar is left"
				.. " alone: whatever sits in its " .. ELEM[e] .. " slot is still dropped by Call of the Elements."
		else
			t = t .. "\n\nNot Dropped: Call of the Elements drops whatever Blizzard's totem bar holds, so its " .. ELEM[e]
				.. " slot is kept empty."
		end
	end
	return t
end
local function DropPlaceRow(row, e, text, icon)
	local n = DroppedCount() + (Excluded(e) and 1 or 0)
	local list = {}
	-- the pictures: its place as a number on the icon; Not Dropped: the icon grayed (Drop All skips it)
	for p = 1, n do list[#list + 1] = { p, ORD[p], nil, { kind = "number", text = tostring(p) } } end
	list[#list + 1] = "-"
	list[#list + 1] = { "not", "Skip", nil, { kind = "gray" } }
	local r = Choice(text, list, function()
		return DropPlace(e) or "not", ElementOwn(e)
	end, function(v)
		if v == "not" then SetNotDropped(e) else SetDropPlace(e, v) end
		return Changed(row)
	end, DropAllTip(e))
	r.icon = icon
	return r
end

-- words: its card's line on the icon's own screen
local function Keybind(rows, words) return { text = "Keys", words = words, sub = function() return rows() end } end
local function KeyRows(button, flyout)
	local r = {}
	if button then r[#r + 1] = { text = "Cast Key", value = function() return KeyText(button), false end } end
	if flyout then r[#r + 1] = { text = button and "Flyout Key" or "Cast Key", value = function() return KeyText(flyout), false end } end
	r[#r + 1] = SEP
	r[#r + 1] = { text = "Open Keybind Mode...", tip = "Opens Keybind Mode: press the key you want on it.", onClick = KeybindMode }
	return r
end

local function ElementMenu(e)
	local r = {}
	-- the button itself
	local on = ElementShown(e)
	r[#r + 1] = { text = on and "Hide This Icon" or "Show This Icon", onClick = function()
		O()[SHOW_KEY[e]] = not on
		Run("UpdateMiniTotemBar")
		BtnRow:Changed(false)
	end }
	r[#r + 1] = SEP
	-- what it does
	local place = DropPlaceRow(BtnRow, e, "Drop All")
	place.words = "its place in Drop All, or left out of it"
	r[#r + 1] = place
	r[#r + 1] = SEP
	-- its keys
	r[#r + 1] = Keybind(function() return KeyRows(BIND_BUTTON[e], BIND_FLYOUT[e]) end, "its button key and its flyout key")
	r[#r + 1] = SEP
	-- reset
	r[#r + 1] = { text = "Reset This Button", disabled = not (ElementOwn(e) or not on),
		tip = "Shows this button again and puts it back in its own place in Drop All (" .. ORD[e] .. " of the four).",
		onClick = function()
			O()[SHOW_KEY[e]] = true
			local order = DropOrder()
			for i, x in ipairs(order) do if x == e then table.remove(order, i) break end end
			table.insert(order, e, e)
			O().dropOrder = order
			Run("LoadoutOrderChanged")   -- (3.0.9.9) the loadout in use keeps it
			if Excluded(e) then SP:SetDropAllExclude(e, false) else Run("UpdateDropAllButton") end
			Run("UpdateMiniTotemBar")
			BtnRow:Changed(false)
		end }
	return r
end

local function SetsRow(text, key, tip, needsKnown, apply, pic)
	local dis = needsKnown and not SetsKnown()
	if dis then tip = tip .. "\n\n|cffffa040Once you know Call of the Elements.|r" end
	return Choice(text, { { true, "On" }, { false, "Off" } }, function()
		local v = O()[key] ~= false
		return v, not v
	end, function(v)
		O()[key] = v
		if apply then apply(v) end
		return Changed(BtnRow)
	end, tip, dis or nil, pic)
end

local function DropAllMenu()
	local r = {}
	local native = Native()
	-- the button itself
	if not native then
		local on = O().showDropAllButton ~= false
		r[#r + 1] = { text = on and "Hide This Icon" or "Show This Icon", onClick = function()
			O().showDropAllButton = not on
			Run("UpdateMiniTotemBar")
			BtnRow:Changed(false)
		end }
		r[#r + 1] = SEP
	end
	-- what it does
	if SetsBar() then r[#r + 1] = { text = "Behavior", label = true } end
	r[#r + 1] = { text = "Drop Order", value = function()
			local n = DroppedCount()
			return (n == 4) and "All Four" or (n .. " Of 4"), DropAllOwn()
		end,
		tip = "The order Drop All drops your totems in, one per click, and which ones it leaves out. The same setting as each"
			.. " element's menu > Drop All." .. (SetsOwnDropAll() and ("\n\n|cffffa040\"Drop All Casts Call of the Elements\" is"
			.. " on, and that spell drops all four totems at once, so the order is not used by the button. It still orders the"
			.. " SP_DropAll macro.|r") or ""),
		words = "the drop order, and the ones left out",
		sub = function()
			local o = {}
			for e = 1, 4 do o[#o + 1] = DropPlaceRow(BtnRow, e, ELEM[e], AssignedIcon(e)) end
			return o
		end }
	if SetsBar() then
		r[#r + 1] = { text = "Blizzard Totem Sets", tip = "WoW: Forever's totem sets: Call of the Elements drops the four totems"
			.. " Blizzard's totem bar holds.", words = "Drop All with Blizzard's sets", sub = function()
			-- the pictures: On, the button shows Call of the Elements; no picture says the two that keep Blizzard's bar in step
			return {
				SetsRow("Drop All Casts Call of the Elements", "dropAllUsesTotemSets", "With totem sets available, Drop All casts"
					.. " Call of the Elements instead of one totem per click. Shift casts Call of the Ancestors. Ctrl casts Call of"
					.. " the Spirits. Right-click casts Totemic Recall. The SP_DropAll macro still drops one totem per press."
					.. (O().showDropAllButton == false and "\n\n|cffffa040\"Show Drop All Button\" is off, so there is no button"
					.. " for this to change.|r" or ""), true,
					function() if not InCombatLockdown() then Run("UpdateDropAllButton") end end,
					{ kind = "swap", icon = SpellTexture(COTE) or GENERIC_DROPALL }),
				SetsRow("Call of the Elements Follows My Assignments", "totemSetsSyncAssignments", "Whenever your totem"
					.. " assignments change, the four totems in Call of the Elements are updated to match (out of combat). Use"
					.. " /spl set 2 <loadout> and /spl set 3 <loadout> to fill Call of the Ancestors and Call of the Spirits from"
					.. " saved loadouts.", true,
					function(v) if v and not InCombatLockdown() then Run("SyncTotemSetFromAssignments") end end, { kind = "none" }),
				SetsRow("My Assignments Follow Blizzard's Totem Bar", "totemSetsAdoptFromBar", "Pick a totem on Blizzard's own"
					.. " totem bar and the matching ShamanPower assignment follows it (clearing a slot there clears the assignment here)."
					.. " Elements kept out of Drop All are left alone. Out of combat; a change made during a fight is picked up"
					.. " when it ends.", false,
					function(v) if v then Run("AdoptTotemBarAssignments") end end, { kind = "none" }),
			}
		end }
	end
	r[#r + 1] = SEP
	-- how it looks. Icon (a player's request): the button's usual icon, or one picked in the icon picker
	local ownIcon = SP.DropAllOwnIcon and SP:DropAllOwnIcon()
	-- Next Totem's picture while an icon is picked: the icon the button shows without one (Call of the
	-- Elements with Blizzard's totem sets, else the first totem in its drop order)
	local function usualIcon()
		if SetsBar() and (not SetsKnown() or O().dropAllUsesTotemSets ~= false) then
			return SpellTexture(COTE) or GENERIC_DROPALL
		end
		for _, e in ipairs(DropOrder()) do
			if not Excluded(e) then return AssignedIcon(e) end
		end
		return GENERIC_DROPALL
	end
	local function pick()
		SP:OpenIconPicker({ icon = SP:DropAllOwnIcon() }, function(selected)
			if BtnRow:RefuseLocked() then return end   -- (the picker was open when a fight started)
			O().dropAllIcon = selected
			if not InCombatLockdown() then Run("UpdateDropAllButton") end
			BtnRow:Changed(false)
		end)
		return false   -- the menu closes; the picker is open
	end
	r[#r + 1] = { text = "Icon", icon = ownIcon, words = "what the button shows",
		value = function() return ownIcon and "Picked" or "Next Totem", ownIcon and true or false end,
		tip = "What the button shows. Next Totem: the icon of the totem it drops next (Call of the Elements when it casts that)."
			.. " Pick an Icon: one icon you choose, which stays put.",
		sub = function()
			-- the pictures: the button as usual (its usual icon while one is picked); the picked icon, else PICK
			local nextPic, pickPic = { kind = "plain" }, { kind = "word", text = "PICK" }
			if ownIcon then nextPic, pickPic = { kind = "swap", icon = usualIcon() }, { kind = "swap", icon = ownIcon } end
			return {
				{ text = "Next Totem", selected = not ownIcon, pic = nextPic, onClick = function()
					O().dropAllIcon = nil
					if not InCombatLockdown() then Run("UpdateDropAllButton") end
					BtnRow:Changed(false)
				end },
				{ text = ownIcon and "Pick Another Icon..." or "Pick an Icon...", selected = ownIcon and true or false, icon = ownIcon,
					pic = pickPic, onClick = pick },
			}
		end }
	-- Start Over After (a Discord ask, 3.0.9.1): the sequence's reset time, the button's and SP_DropAll's alike
	r[#r + 1] = Slider("Start Over After", 0, 60, 1, function() return O().dropAllResetSeconds or 15 end,
		function(v)
			O().dropAllResetSeconds = v
			Run("UpdateDropAllButton")
			if not InCombatLockdown() then Run("UpdateSPMacros") end
		end,
		function(v) if (v or 0) <= 0 then return "Never" end return v .. " s" end, false,
		"How long after a press the button (and the SP_DropAll macro) waits before the sequence starts over at its"
		.. " first totem. Never: it only moves on when you cast. Leaving a fight starts it over either way.")
	r[#r + 1] = SEP
	-- its key
	r[#r + 1] = Keybind(function() return KeyRows("SHAMANPOWER_DROPALL") end, "the key that presses it")
	r[#r + 1] = SEP
	-- reset
	r[#r + 1] = { text = "Reset This Button", disabled = not (DropAllOwn() or O().showDropAllButton == false or O().dropAllResetSeconds ~= nil),
		tip = "Back to how it came: on the bar with its usual icon, dropping Earth, Fire, Water, Air in that order"
			.. (SetsBar() and ", the Blizzard Totem Sets switches on." or "."),
		onClick = function()
			local o = O()
			o.showDropAllButton = true
			o.dropAllIcon = nil
			o.dropAllResetSeconds = nil
			o.dropOrder = { 1, 2, 3, 4 }
			Run("LoadoutOrderChanged")   -- (3.0.9.9) the loadout in use keeps it
			if SetsBar() then o.dropAllUsesTotemSets, o.totemSetsSyncAssignments, o.totemSetsAdoptFromBar = nil, nil, nil end
			for e = 1, 4 do if Excluded(e) then SP:SetDropAllExclude(e, false) end end
			Run("UpdateDropAllButton")
			Run("UpdateMiniTotemBar")
			BtnRow:Changed(false)
		end }
	return r
end

-- Signature Moves (Cooldown Bar > Effects) plays the look's own move: the other styles wait
local function SignatureOn()
	local o = O()
	return (o.cdbarCueSignature and (o.cdbarCueLook or "standard") ~= "standard") and true or false
end
-- (the 4th field: each style's picture on the icon's own screen, in WoW's red and the Running Out orange)
local RUNNING_STYLES = {
	{ "off", "Off", nil, { kind = "plain" } },
	{ "red", "Turns red", nil, { kind = "tint", color = { 1, 0.125, 0.125 } } },
	{ "pulse", "Pulse", nil, { kind = "dark", alpha = 0.4 } },
	{ "glow", "Glow", nil, { kind = "glow", color = { 1, 0.6, 0.1 } } },
	{ "drain", "Shrinking Border", nil, { kind = "edge", color = { 1, 0.6, 0.1 } } },
	{ "underbar", "Bar Below Icon", nil, { kind = "bar", frac = 0.4, color = { 1, 0.6, 0.1 } } },
}
local function ESGet(name)
	if not SP.CdItemOpt then return nil, false end
	return SP:CdItemOpt(ES_SLOT, name), SP:CdItemOwnOpt(ES_SLOT, name) ~= nil
end
local function ESSet(name, v) if SP.SetCdItemOpt then SP:SetCdItemOpt(ES_SLOT, name, v) end end
local function ESRunningRow()
	local function cur()
		local on, own1 = ESGet("cueRunning")
		local st, own2 = ESGet("cueRunningStyle")
		if not on then return "off", own1 end
		return st or "red", own1 or own2
	end
	return {
		text = "Running Out",
		words = "what it plays over its last seconds",
		tip = "Over its last seconds (Running Out At), or on its last 2 charges, the Earth Shield button plays this until you"
			.. " cast it again. Off to start.",
		value = function()
			local v, own = cur()
			return Menu.LabelOf(RUNNING_STYLES, v), own and true or false
		end,
		sub = function()
			local now = cur()
			local sig = SignatureOn() and (ESGet("cueRunningStyle") or "red") or nil
			local items = {}
			for _, c in ipairs(RUNNING_STYLES) do
				local v = c[1]
				items[#items + 1] = { text = c[2], selected = now == v, disabled = (sig and v ~= "off" and v ~= sig) or nil,
					pic = c[4], onClick = function()
						if v == "off" then
							ESSet("cueRunning", false)
						elseif SignatureOn() then
							ESSet("cueRunning", true)
						else
							ESSet("cueRunningStyle", v)
							ESSet("cueRunning", true)
						end
						return Changed(BtnRow)
					end }
			end
			return items
		end,
	}
end

local function EarthShieldMenu()
	local r = {}
	local flyOn = O().enableESFlyout ~= false
	-- the button itself
	local on = O().totemBarShowEarthShield ~= false
	r[#r + 1] = { text = on and "Hide This Icon" or "Show This Icon", onClick = function()
		O().totemBarShowEarthShield = not on
		Run("UpdateEarthShieldButton")
		BtnRow:Changed(false)
	end }
	r[#r + 1] = SEP
	-- what it does
	r[#r + 1] = { text = "Behavior", label = true }
	-- (no picture says a flyout: its card is the switch alone)
	local fly = Choice("Flyout", { { true, "On" }, { false, "Off" } }, function()
		return O().enableESFlyout ~= false, false
	end, function(v)
		O().enableESFlyout = v
		if not InCombatLockdown() then Run("UpdateEarthShieldButton") end
		return Changed(BtnRow)
	end, "A flyout on the Earth Shield button to choose its target. How flyouts open is on Totem Bar > Clicks.",
		nil, { kind = "none" })
	fly.words = "a flyout on the button to choose its target"
	r[#r + 1] = fly
	r[#r + 1] = { text = "Players In The Flyout", subMaxHeight = 420, disabled = (not flyOn) or nil,
		words = "who the flyout shows",
		value = function() return WhoText(), AnyPicked() end,
		tip = "Only these players show in the flyout: a player shows if any picked role or class matches them. Nothing picked: everyone."
			.. " Your assigned target always shows. Roles use the group roles (raid Main Tanks count as Tanks)."
			.. ((not flyOn) and "\n\n|cffffa040The flyout is off: turn Flyout on first.|r" or ""),
		sub = function()
			local o = {}
			local function pick(tbl, k, text, pic)
				local on = Picked(tbl, k)
				o[#o + 1] = { text = text, selected = on, pic = pic, onClick = function()
					if SP.EnsureProfileTable then SP:EnsureProfileTable(tbl) end
					if type(O()[tbl]) ~= "table" then O()[tbl] = {} end
					O()[tbl][k] = (not on) or nil
					if not InCombatLockdown() then Run("CreateEarthShieldFlyout", true) end
					return Changed(BtnRow)
				end }
			end
			-- the pictures: a class as its class icon; no picture says a role
			for _, x in ipairs(ROLES) do pick("esFlyoutRoles", x[1], x[2], { kind = "none" }) end
			o[#o + 1] = SEP
			for _, c in ipairs(CLASSES) do
				pick("esFlyoutClasses", c[1], ClassText(c), { kind = "swap", icon = "Interface\\Icons\\ClassIcon_" .. c[1] })
			end
			o[#o + 1] = SEP
			o[#o + 1] = { text = "Show Everyone", disabled = (not AnyPicked()) or nil, onClick = function()
				O().esFlyoutRoles, O().esFlyoutClasses = nil, nil
				if not InCombatLockdown() then Run("CreateEarthShieldFlyout", true) end
				return Changed(BtnRow)
			end }
			return o
		end }
	r[#r + 1] = SEP
	-- what it plays over its last seconds
	r[#r + 1] = { text = "Effects & Sound", label = true }
	r[#r + 1] = ESRunningRow()
	r[#r + 1] = Slider("Running Out (Seconds Left)", 10, 300, 5, function() return (ESGet("runOutSecs")) or 60 end,
		function(v) ESSet("runOutSecs", v); BtnRow:Repaint() end,
		function(v) return string.format("%d sec", tonumber(v) or 0) end, false,
		"When Earth Shield counts as running out, for Running Out. It also counts on its last 2 charges.")
	r[#r + 1] = SEP
	-- its key
	r[#r + 1] = Keybind(function() return KeyRows("SHAMANPOWER_EARTH_SHIELD") end, "the key that presses it")
	r[#r + 1] = SEP
	-- reset
	r[#r + 1] = { text = "Reset This Button", disabled = not (ESOwn() or flyOn or not on),
		tip = "Back to how it came: on the bar, no flyout, everyone in the flyout, Running Out off.",
		onClick = function()
			ResetES()
			BtnRow:Changed(false)
		end }
	return r
end

-- ---------------------------------------------------------------------------
-- A totem's menu
-- ---------------------------------------------------------------------------
local function CompactOn()
	if Native() then return false end
	return (SP.CompactActive and SP:CompactActive()) and true or false
end
local function PulseOffWhy(flash)
	local o = O()
	if o.pulseBarPosition == "none" then   -- (nil: on, its default)
		return "Pulse bars are off: Totem Bar > Duration Bars > Pulse Bar Position."
	end
	if flash and o.pulseFlashOpacity == 0 then
		return "The pulse flash is off: Totem Bar > Duration Bars > Pulse Flash Opacity is at 0%."
	end
	if CompactOn() then return "Compact draws its own pulse. This setting applies to the other styles." end
	return nil
end

-- ---------------------------------------------------------------------------
-- (3.0.9.2) Each totem's own effects, in its menu: what it set there lives in opt.totemOwn[its
-- spell] under the bar's own keys; anything it didn't set is the bar's own setting, as it was
-- (ShamanPowerCues.lua SP:TotemCueOpt). Apply to All Totems makes this totem's the bar's own
-- (every totem follows them); Apply to All <Element> Totems puts them on that element's totems.
-- ---------------------------------------------------------------------------
local FX = {
	destroyed = { "totemCueDestroyed", "totemCueDestroyedStyle", "totemCueDestroyedMark", "totemCueDestroyedMarkStays" },
	expired = { "totemCueExpired", "totemCueExpiredStyle" },
	expiring = { "totemCueExpiring", "totemCueExpiringStyle", "totemCueExpiringSecs" },
	range = { "totemRangeLook", "totemRangeGlowShape", "totemRangeGlowColor" },
	look = { "totemCueLook", "totemCueSignature" },
	usual = { "usualTotemReminder", "usualTotemStyle", "usualTotemLabel", "usualTotemAlert" },
}
local FX_ALL = {}
for _, g in pairs(FX) do for _, k in ipairs(g) do FX_ALL[#FX_ALL + 1] = k end end
local FX_FALLBACK = { totemCueDestroyedStyle = "shake", totemCueExpiredStyle = "pop", totemCueExpiringStyle = "pulse",
	totemCueExpiringSecs = 5, totemRangeLook = "gray", totemCueLook = "standard", usualTotemStyle = "glow", usualTotemLabel = true }
local LOOKS = { { "standard", "Standard" }, { "elemental", "Elemental" }, { "signal", "Signal" } }
local RANGE_LOOKS = { { "gray", "Gray (as always)" }, { "glow", "Glow" }, { "both", "Gray + Glow" }, { "none", "Nothing" } }
local function CopyV(v)
	if type(v) ~= "table" then return v end
	local t = {}
	for k, x in pairs(v) do t[k] = x end
	return t
end
local function TOwn(id, create)
	local o = O()
	if type(o.totemOwn) ~= "table" then
		if not create then return nil end
		o.totemOwn = {}
	end
	local t = o.totemOwn[id]
	if type(t) ~= "table" and create then t = {}; o.totemOwn[id] = t end
	return t
end
local function TPrune(id)
	local o = O()
	local t = type(o.totemOwn) == "table" and o.totemOwn[id]
	if type(t) == "table" and next(t) == nil then o.totemOwn[id] = nil end
end
-- value (the bar's own, or its default, when the totem has none), own
local function TGet(id, k)
	local own = TOwn(id)
	if own and own[k] ~= nil then return own[k], true end
	local v = O()[k]
	if v == nil then v = FX_FALLBACK[k] end
	return v, false
end
local function FxApplied()
	Run("ApplyCueSettings")
	Run("ApplyUsualTotemSettings")
	if SP.UpdatePlayerTotemRange then Run("UpdatePlayerTotemRange") end
end
local function TSet(id, k, v)
	TOwn(id, true)[k] = v
	TPrune(id)
	FxApplied()
	return Changed(TotRow)
end
-- the style list each effect has on Totem Bar > Effects (the same choices, the Effects Look's too)
local function StyleList(key)
	local a = SP.options and SP.options.args.fluffy.args.totembar_effects_section
	local opt = a and a.args[key]
	local values, order = opt and opt.values, opt and opt.sorting
	if type(values) == "function" then values = values() end
	if type(order) == "function" then order = order() end
	local list = {}
	for _, k in ipairs(order or {}) do if values and values[k] then list[#list + 1] = { k, values[k] } end end
	return list
end
local function OnOffRowT(id, text, k, tip, isTrue)
	return Choice(text, { { true, "On" }, { false, "Off" } }, function()
		local v, own = TGet(id, k)
		if isTrue then v = v == true else v = v and true or false end
		return v, own
	end, function(v) return TSet(id, k, v) end, tip)
end
local function ApplyRows(item, keys)
	local id, e = item.key, item.e
	return {
		{ text = "Apply to All Totems", tip = "Every totem takes these settings of this one (they become the bar's own).",
			onClick = function()
				local o = O()
				for _, k in ipairs(keys) do o[k] = CopyV((TGet(id, k))) end
				if type(o.totemOwn) == "table" then
					for sid, own in pairs(o.totemOwn) do
						if type(own) == "table" then
							for _, k in ipairs(keys) do own[k] = nil end
							if next(own) == nil then o.totemOwn[sid] = nil end
						end
					end
				end
				FxApplied()
				TotRow:Changed(false)
			end },
		{ text = "Apply to All " .. ELEM[e] .. " Totems", tip = "Every " .. ELEM[e] .. " totem takes these settings of this one.",
			onClick = function()
				for _, t in ipairs(Totems()) do
					if t.e == e and t.key ~= id then
						local own = TOwn(t.key, true)
						for _, k in ipairs(keys) do
							local v, mine = TGet(id, k)
							if mine then own[k] = CopyV(v) else own[k] = nil end
						end
						TPrune(t.key)
					end
				end
				FxApplied()
				TotRow:Changed(false)
			end },
	}
end
local function Join(a, b) for _, x in ipairs(b) do a[#a + 1] = x end return a end
local function FxGroups(item)
	local id = item.key
	local out = {}
	-- the look its effects play in (Standard, Elemental, Signal) and Signature Moves: was Totem Bar > Effects
	out[#out + 1] = Menu.Group("Effects Look", function()
		local look = TGet(id, "totemCueLook")
		local t = {
			Choice("Look", LOOKS, function() return TGet(id, "totemCueLook") end, function(v) return TSet(id, "totemCueLook", v) end,
				"Standard: the original look. Elemental: a ring and glow in the element's color, with cracked stone for a destroyed totem."
				.. " Signal: a thin border and a bar along the bottom, with a red slash and corner flag for a destroyed totem."),
			OnOffRowT(id, "Signature Moves", "totemCueSignature", "Each effect plays the look's own animation (Elemental: Crumble,"
				.. " Shrinking Ring, Shrinking Border. Signal: Blinking Border, Shrinking Underline, Bar Below Icon) instead of its"
				.. " Style. Needs a look other than Standard.", true),
			SEP,
		}
		if look == "standard" then t[2].disabled = true end
		return Join(t, ApplyRows(item, FX.look))
	end, nil, nil, "the look its effects play in")
	out[#out + 1] = Menu.Group("When Destroyed", function()
		local t = {
			OnOffRowT(id, "Effect", "totemCueDestroyed", "When this totem is killed before its time, its button plays the style below in red. Your own right-click dismiss, Totemic Call and dying do not count."),
			Choice("Style", StyleList("totemCueDestroyedStyle"), function() return TGet(id, "totemCueDestroyedStyle") end,
				function(v) return TSet(id, "totemCueDestroyedStyle", v) end),
			OnOffRowT(id, "Red X Until Recast", "totemCueDestroyedMark", "A red X on the button when it's destroyed, until you drop that element again (5 seconds at most).", true),
		}
		if TGet(id, "totemCueDestroyedMark") == true then
			t[#t + 1] = OnOffRowT(id, "Keep the Red X Until Recast", "totemCueDestroyedMarkStays", "The X stays until you drop that element again, instead of fading after 5 seconds.")
		end
		t[#t + 1] = SEP
		return Join(t, ApplyRows(item, FX.destroyed))
	end, nil, nil, "killed before its time")
	out[#out + 1] = Menu.Group("When It Expires", function()
		local t = {
			OnOffRowT(id, "Effect", "totemCueExpired", "When this totem runs out, its button plays the style below in white."),
			Choice("Style", StyleList("totemCueExpiredStyle"), function() return TGet(id, "totemCueExpiredStyle") end,
				function(v) return TSet(id, "totemCueExpiredStyle", v) end),
			SEP,
		}
		return Join(t, ApplyRows(item, FX.expired))
	end, nil, nil, "it runs out")
	out[#out + 1] = Menu.Group("Expiring Soon", function()
		local t = {
			OnOffRowT(id, "Effect", "totemCueExpiring", "Over this totem's last seconds its button plays the style below, until it runs out or you drop it again."),
			Choice("Style", StyleList("totemCueExpiringStyle"), function() return TGet(id, "totemCueExpiringStyle") end,
				function(v) return TSet(id, "totemCueExpiringStyle", v) end),
			Slider("Warn Before It Ends (Seconds)", 3, 15, 1, function() return (TGet(id, "totemCueExpiringSecs")) end,
				function(v) TOwn(id, true).totemCueExpiringSecs = v; FxApplied() end),
			SEP,
		}
		return Join(t, ApplyRows(item, FX.expiring))
	end, nil, nil, "its last seconds")
	out[#out + 1] = Menu.Group("Out of Range", function()
		local t = { Choice("Look", RANGE_LOOKS, function() return TGet(id, "totemRangeLook") end,
			function(v) return TSet(id, "totemRangeLook", v) end,
			"How its button looks while you're out of its range: gray as it always was, a glow, both, or nothing.") }
		local look = TGet(id, "totemRangeLook")
		if look == "glow" or look == "both" then
			if SP.GlowShapeValues then
				local map, order = SP:GlowShapeValues()
				local list = {}
				for _, k in ipairs(order or {}) do list[#list + 1] = { k, map[k] } end
				t[#t + 1] = Choice("Glow Shape", list, function()
					local v, own = TGet(id, "totemRangeGlowShape")
					return v or (O().glowShape or "default"), own
				end, function(v) return TSet(id, "totemRangeGlowShape", v) end, "The glow's shape. Proc Glow is the game's ring.")
			end
			local c = TGet(id, "totemRangeGlowColor") or SP.TOTEM_RANGE_GLOW_DEFAULT or { r = 1, g = 0.3, b = 0.3 }
			t[#t + 1] = { text = "Glow Color", swatch = { c.r or 1, c.g or 0.3, c.b or 0.3 }, onClick = function()
				if not SP.OpenColorPicker then return false end
				local _, own = TGet(id, "totemRangeGlowColor")
				local before = own and CopyV((TGet(id, "totemRangeGlowColor"))) or nil
				SP:OpenColorPicker({ r = c.r or 1, g = c.g or 0.3, b = c.b or 0.3, hasAlpha = false, title = item.name .. " Out of Range Glow Color",
					onChange = function(r, g, b) TOwn(id, true).totemRangeGlowColor = { r = r, g = g, b = b }; FxApplied(); TotRow:Changed(false) end,
					onCancel = function() TOwn(id, true).totemRangeGlowColor = before; TPrune(id); FxApplied(); TotRow:Changed(false) end })
				return false
			end }
		end
		t[#t + 1] = SEP
		return Join(t, ApplyRows(item, FX.range))
	end, nil, nil, "you're out of its range")
	-- Put Your Usual Totem Back (was Totem Bar > Effects): a temporary totem's reminder when it ends
	if TempApplies(id) then
		out[#out + 1] = Menu.Group("Put Your Usual Totem Back", function()
			local t = {
				OnOffRowT(id, "Remind Me", "usualTotemReminder", "When this totem ends (while it counts as temporary), its"
					.. " element's button lights up until you drop your usual totem (the one assigned on your bar) again.", true),
				Choice("Reminder Style", { { "glow", "Glow" }, { "pulse", "Pulse" } }, function()
					local v, own = TGet(id, "usualTotemStyle")
					return v == "pulse" and "pulse" or "glow", own
				end, function(v) return TSet(id, "usualTotemStyle", v) end,
					"Glow: the button's edges glow gold. Pulse: the icon pulses darker. Both follow this totem's Effects Look."),
				OnOffRowT(id, "Show BACK on the Button", "usualTotemLabel", "BACK along the bottom of the button. A Compact line says"
					.. " Put Windfury back, with your own totem's name."),
				OnOffRowT(id, "Also Show a Text Alert", "usualTotemAlert", "A line like Put Windfury back in the Expiring Alerts text,"
					.. " at its spot and size. No sound.", true),
				{ text = "Test Usual Totem Reminder", tip = "Shows this reminder for 5 seconds on its element's button.",
					onClick = function() if SP.TestUsualTotemReminder then SP:TestUsualTotemReminder(id) end return true end },
				SEP,
			}
			return Join(t, ApplyRows(item, FX.usual))
		end, nil, nil, "when it ends, back to your usual totem")
	end
	return out
end
SP.TotemOwnFxKeys = FX_ALL   -- (Copy / Paste and Reset This Totem carry them; ShamanPowerTheme the color)

local function TotemSnapshot(item)
	local snap = { from = item.key, name = item.name }
	local pk = PulseKey(item.key)
	if pk then
		snap.bar = PulseBarOn(pk)
		snap.flash = PulseFlashOn(pk)
	end
	if TempApplies(item.key) then snap.temp = TempOn(item.key) end
	local own = TOwn(item.key)
	if own then snap.fx = CopyV(own) end   -- (3.0.9.2) its own effects
	return snap
end
local function PasteTotem(snap, item)
	if not snap or snap.from == item.key then return end
	local pk = PulseKey(item.key)
	if pk then
		if snap.bar ~= nil then SetPulseBar(pk, snap.bar) end
		if snap.flash ~= nil then SetPulseFlash(pk, snap.flash) end
	end
	if snap.temp ~= nil and TempApplies(item.key) then SetTemp(item.key, snap.temp) end
	-- (3.0.9.2) its own effects, exactly: what the source took from the bar, this one does too
	local o = O()
	if snap.fx then
		if type(o.totemOwn) ~= "table" then o.totemOwn = {} end
		o.totemOwn[item.key] = CopyV(snap.fx)
	elseif type(o.totemOwn) == "table" then
		o.totemOwn[item.key] = nil
	end
	FxApplied()
end
local function CopyTo(item, element)
	local snap = TotemSnapshot(item)
	for _, t in ipairs(Totems()) do
		if t.key ~= item.key and (not element or t.e == element) then PasteTotem(snap, t) end
	end
end


local function FlyoutBinding(item)
	local cast = O().swapFlyoutClickButtons and "RightButton" or "LeftButton"
	return "CLICK ShamanPowerFlyout" .. item.e .. "Btn" .. item.idx .. ":" .. cast
end

local function TotemMenu(item)
	local r = {}
	local id = item.key
	local pk = PulseKey(id)
	-- the totem itself (in its flyout, or not)
	if not Native() then
		local on = InFlyout(item)
		r[#r + 1] = { text = on and "Hide From The Flyout" or "Show In The Flyout", onClick = function()
			SetInFlyout(item, not on)
			TotRow:Changed(false)
		end }
		r[#r + 1] = SEP
	end
	-- what it does
	if TempApplies(id) then
		local temp = Choice("Treat as Temporary", { { true, "On" }, { false, "Off" } }, function()
			local v = TempOn(id)
			return v, v ~= TempDefault(id)
		end, function(v) SetTemp(id, v) return Changed(TotRow) end,
			"When it ends, Put Your Usual Totem Back (below) asks for your usual " .. ELEM[item.e] .. " totem. Turn"
				.. " it off for a totem you keep down on purpose.", nil, { kind = "none" })   -- (the words say it)
		temp.words = "then back to your usual totem"
		r[#r + 1] = temp
	end
	if TempApplies(id) then r[#r + 1] = SEP end
	-- its effects (3.0.9.2: each totem's own) and its pulse: the bar and the flash
	r[#r + 1] = { text = "Effects & Sound", label = true }
	Join(r, FxGroups(item))
	if pk then
		local why = PulseOffWhy(false)
		-- the pictures: the bar in Pulse Bar Color (the theme's, else white); the flash in Pulse Flash Color
		local bar = Choice("Pulse Bar", { { true, "On" }, { false, "Off" } }, function()
			local v = PulseBarOn(pk)
			return v, not v
		end, function(v) SetPulseBar(pk, v) return Changed(TotRow) end,
			why and ("|cffffa040" .. why .. "|r") or ("The bar that shows the time to this totem's next pulse (and its pulse"
				.. " time). Turned off: this totem gets neither."), why and true or nil,
			{ kind = "bar", frac = 0.6, color = function()
				local c = O().pulseBarColor
				if c then return c.r or 1, c.g or 1, c.b or 1 end
				local tr, tg, tb = SP:ThemeColor("tb.pulse", item.e)
				if tr then return tr, tg, tb end
				return 1, 1, 1
			end })
		bar.words = "the bar that counts down to its next pulse"
		r[#r + 1] = bar
		local whyF = PulseOffWhy(true)
		local flash = Choice("Pulse Flash", { { true, "On" }, { false, "Off" } }, function()
			local v = PulseFlashOn(pk)
			return v, not v
		end, function(v) SetPulseFlash(pk, v) return Changed(TotRow) end,
			whyF and ("|cffffa040" .. whyF .. "|r") or "The flash on the button each time this totem pulses.", whyF and true or nil,
			{ kind = "glow", color = function()
				local c = O().pulseFlashColor
				if c then return c.r or 0.4, c.g or 1, c.b or 0.4 end
				return 0.4, 1, 0.4
			end })
		flash.words = "the flash on the button each time it pulses"
		r[#r + 1] = flash
	end
	r[#r + 1] = SEP
	-- where it sits in its flyout, and its key (one group: Position & Keys)
	local pk2 = {}
	if not Native() then
		-- (3.0.9) its place in the flyout, for whoever would rather click than drag it on the row
		local pos, n = TotemPlace(item)
		pk2[#pk2 + 1] = { text = "Earlier in Flyout", disabled = (pos <= 1) or nil,
			tip = "One place earlier in its flyout. Drag it along its line on the row for any place.",
			onClick = function() SetTotemPlace(item, pos - 1) return OrderChanged() end }
		pk2[#pk2 + 1] = { text = "Later in Flyout", disabled = (pos >= n) or nil,
			tip = "One place later in its flyout. Drag it along its line on the row for any place.",
			onClick = function() SetTotemPlace(item, pos + 1) return OrderChanged() end }
	end
	pk2[#pk2 + 1] = Keybind(function() return KeyRows(nil, FlyoutBinding(item)) end,
		"the key that casts it from its flyout")
	if #pk2 > 1 then r[#r + 1] = { text = "Position & Keys", label = true } end
	for _, x in ipairs(pk2) do r[#r + 1] = x end
	r[#r + 1] = SEP
	-- copy and reset
	r[#r + 1] = { text = "Copy & Reset", label = true }
	do   -- (3.0.9.2: every totem has its own effects to copy now)
		r[#r + 1] = { text = "Copy Settings", onClick = function()
			TotRow.clip = TotemSnapshot(item)
			return true
		end }
		local clip = TotRow.clip
		r[#r + 1] = { text = clip and ("Paste Settings  (from " .. clip.name .. ")") or "Paste Settings",
			disabled = (not clip or clip.from == id) or nil,
			onClick = function()
				PasteTotem(TotRow.clip, item)
				return Changed(TotRow)
			end }
		r[#r + 1] = { text = "Copy Settings To...", tip = "Its effects, and Pulse Bar, Pulse Flash and Treat as Temporary onto the"
			.. " totems that have those settings.", words = "the same settings onto other totems",
			sub = function()
			local o = {}
			for e = 1, 4 do
				o[#o + 1] = { text = "All " .. ELEM[e] .. " Totems", icon = AssignedIcon(e), onClick = function()
					CopyTo(item, e)
					TotRow:Changed(false)
				end }
			end
			o[#o + 1] = SEP
			o[#o + 1] = { text = "All Totems", onClick = function()
				CopyTo(item, nil)
				TotRow:Changed(false)
			end }
			return o
		end }
	end
	if not Native() then
		r[#r + 1] = { text = "Reset Flyout Order", disabled = (not SP.FlyoutOrderIsUsual or SP:FlyoutOrderIsUsual(item.e)) or nil,
			tip = "The " .. ELEM[item.e] .. " flyout back in the game's order.",
			onClick = function() SP:SetFlyoutOrder(item.e, nil) return OrderChanged() end }
	end
	r[#r + 1] = { text = "Reset This Totem", disabled = not (TotemOwn(item) or TOwn(id) or not InFlyout(item)),
		tip = "Back to how it came: in its flyout" .. (pk and ", Pulse Bar and Pulse Flash on" or "")
			.. (TempApplies(id) and (", Counts As Temporary " .. (TempDefault(id) and "on" or "off")) or "") .. ".",
		onClick = function()
			if not InFlyout(item) then SetInFlyout(item, true) end
			if pk then SetPulseBar(pk, true); SetPulseFlash(pk, true) end
			if TempApplies(id) then SetTemp(id, TempDefault(id)) end
			if type(O().totemOwn) == "table" then O().totemOwn[id] = nil; FxApplied() end   -- (3.0.9.2) its own effects
			TotRow:Changed(false)
		end }
	-- its test (3.0.9.2: was Totem Bar > Effects' Test button)
	r[#r + 1] = SEP
	r[#r + 1] = { text = "Test This Totem's Effects", tip = "Plays this totem's own Destroyed (and its red X), Expired and"
		.. " Expiring Soon on its element's button, one after the other.",
		onClick = function() if SP.TestTotemCuesFor then SP:TestTotemCuesFor(id, item.e) end return true end }
	return r
end

-- ---------------------------------------------------------------------------
-- The Buttons row
-- ---------------------------------------------------------------------------
local UNDER = { {}, {}, {}, {} }   -- the colors handed to the row (filled per call, never new tables)
local function FillUnder(i, e)
	local c = UNDER[i]
	c[1], c[2], c[3] = SP:BrandElementRGB(EKEY[e])
	return c
end
local function BtnLearned(item)
	local k = item.key
	if k == DROPALL then return DropAllLearned() end
	if k == ES then return ESLearned() end
	if k == RECALL then return ns.CdbarRecall.learned() end
	return ElementLearned(k)
end
local function BtnShown(item)
	local k = item.key
	if k == DROPALL then return O().showDropAllButton ~= false end
	if k == ES then return O().totemBarShowEarthShield ~= false end
	if k == RECALL then return ns.CdbarRecall.shown() end
	return ElementShown(k)
end

BtnRow = ns.IconRow.New({
	caption = function() return Native() and BTN_CAPTION_NATIVE or BTN_CAPTION end,
	hint = "Click: show or hide it on the bar\nRight-click: its settings\nDrag an element: its place on the bar",
	list = function(out)
		if not Native() then
			for _, e in ipairs(BarOrder()) do out[#out + 1] = { key = e, name = ELEM[e] } end
		end
		out[#out + 1] = { key = DROPALL, name = "Drop All" }
		if RecallHere() then out[#out + 1] = { key = RECALL, name = ns.CdbarRecall.name() } end
		if HasESButton() and not Native() then out[#out + 1] = { key = ES, name = ESName() } end
	end,
	textures = function(item, out)
		local k = item.key
		if k == DROPALL then out[1] = DropAllIcon()
		elseif k == ES then out[1] = SpellTexture(SP.EarthShield and SP.EarthShield.rank1 or 974) or 136089
		elseif k == RECALL then out[1] = ns.CdbarRecall.icon() or 134400
		else out[1] = AssignedIcon(k) end
		return 1
	end,
	shown = BtnShown,
	learned = BtnLearned,
	hasOwn = function(item)
		local k = item.key
		if k == DROPALL then return DropAllOwn() end
		if k == ES then return ESOwn() end
		if k == RECALL then return ns.CdbarRecall.hasOwn() end
		return ElementOwn(k)
	end,
	tooltip = function(item)
		local k = item.key
		local t
		if k == DROPALL then
			t = SetsOwnDropAll() and "Drop All: casts Call of the Elements (the four totems Blizzard's totem bar holds)."
				or "Drop All: drops your assigned totems, one per click, in its drop order."
			if not DropAllLearned() then
				t = t .. (SetsBar() and " You don't know Call of the Elements yet: until then it drops one totem per click."
					or " It shows once you have learned a totem.")
			end
		elseif k == ES then
			t = ESName() .. ": casts it on your assigned target."
			if not ESLearned() then t = t .. " You haven't learned it yet. You can still set it up." end
		elseif k == RECALL then
			t = item.name .. ": at the end of your totem bar (its Bar setting). Right-click it for its settings, the same"
				.. " ones it has on the Cooldown Bar page; Bar: Cooldown Bar puts it back there."
			if not BtnLearned(item) then t = t .. " You haven't learned it yet. You can still set it up." end
		else
			local idx = SP.AssignedIndex and SP:AssignedIndex(k) or 0
			t = "Your " .. ELEM[k] .. " button: " .. ((idx and idx > 0 and SP.GetTotemName) and SP:GetTotemName(k, idx)
				or "no totem assigned (Empty)") .. "."
			if not ElementLearned(k) then
				t = t .. " You haven't learned " .. ((k == 1 or k == 4) and "an " or "a ") .. ELEM[k] .. " totem yet. You can"
					.. " still set it up; Only Show Learned Elements decides whether the bar shows it before then."
			end
		end
		if not BtnShown(item) then t = t .. "\n\nHidden: not on the bar (click to show it)." end
		return t
	end,
	toggle = function(item)
		local k = item.key
		if Native() then
			Say("You use Blizzard's Totem Bar (Totem Bar > Style), so ShamanPower's own buttons aren't on screen.")
			return
		end
		if k == DROPALL then
			O().showDropAllButton = not BtnShown(item)
			Run("UpdateMiniTotemBar")
		elseif k == ES then
			O().totemBarShowEarthShield = not BtnShown(item)
			Run("UpdateEarthShieldButton")
		elseif k == RECALL then
			ns.CdbarRecall.toggle()   -- (the Cooldown Bar page's own switch: both bars follow)
		else
			O()[SHOW_KEY[k]] = not ElementShown(k)
			Run("UpdateMiniTotemBar")
		end
		Run("SetupKeybindings")   -- its key follows (Keybinds Still Work Even If Icon Is Turned Off)
	end,
	menu = function(item)
		local k = item.key
		if k == DROPALL then return DropAllMenu() end
		if k == ES then return EarthShieldMenu() end
		if k == RECALL then return ns.CdbarRecall.menu(BtnRow, item) end
		return ElementMenu(k)
	end,
	move = function(item, index)
		if InCombatLockdown() or type(item.key) ~= "number" then return end
		local order = BarOrder()
		local from
		for i, x in ipairs(order) do if x == item.key then from = i break end end
		if not from then return end
		table.remove(order, from)
		table.insert(order, math.max(1, math.min(#order + 1, index)), item.key)
		O().totemBarOrder = order
		Run("UpdateMiniTotemBar")
		Run("LoadoutOrderChanged")   -- (3.0.9.9) the loadout in use keeps it (Loadouts Remember the Totem Bar and Drop Order)
	end,
	movable = function(item) return type(item.key) == "number" end,
	gapBefore = function(item) if item.key == DROPALL then return 14 end return 0 end,
	under = function(item, out)
		local k = item.key
		if k == ES or k == RECALL then return 0 end
		if k == DROPALL then
			for e = 1, 4 do out[e] = FillUnder(e, e) end
			return 4
		end
		out[1] = FillUnder(1, k)
		return 1
	end,
	menuElement = function(item) if type(item.key) == "number" then return EKEY[item.key] end return nil end,
	locked = function() return InCombatLockdown() end,
	onLocked = LockedSay,
})

-- ---------------------------------------------------------------------------
-- The Totems rows (one line per element)
-- ---------------------------------------------------------------------------
local LABEL_W = 70
TotRow = ns.IconRow.New({
	caption = function() return Native() and TOT_CAPTION_NATIVE or TOT_CAPTION end,
	hint = "Click: show or hide it in its flyout\nRight-click: its settings\nDrag: its place in the flyout",
	list = function(out)
		for _, t in ipairs(Totems()) do out[#out + 1] = t end
	end,
	-- (3.0.9) dragged along its element's line: its place in the flyout order (not with Blizzard's
	-- Totem Bar, whose flyouts are its own)
	movable = function() return not Native() end,
	move = MoveTotem,
	textures = function(item, out) out[1] = TotemIcon(item) return 1 end,
	shown = function(item) return Native() or InFlyout(item) end,
	learned = TotemLearned,
	hasOwn = TotemOwn,
	tooltip = function(item)
		local t = Native() and ("A " .. ELEM[item.e] .. " totem.")
			or (InFlyout(item) and ("In your " .. ELEM[item.e] .. " flyout.") or ("Hidden from your " .. ELEM[item.e] .. " flyout."))
		if not TotemLearned(item) then t = t .. " You haven't learned it yet: set it up now, it shows once learned." end
		if TotemOwn(item) then t = t .. "\n\nIt has settings of its own (right-click to see them)." end
		return t
	end,
	toggle = function(item)
		if Native() then
			Say("You use Blizzard's Totem Bar (Totem Bar > Style): its own flyouts are on screen, so this changes nothing there.")
			return
		end
		SetInFlyout(item, not InFlyout(item))
	end,
	menu = TotemMenu,
	group = function(item) return item.e end,
	groupLabelWidth = LABEL_W,
	groupGap = 2,
	groupLabel = function(holder, e)
		if not holder.box then
			holder.box = SP:CreateElementBox(holder, 10, EKEY[e])
			holder.box:SetPoint("LEFT", holder, "LEFT", 0, 0)
			holder.text = holder:CreateFontString(nil, "OVERLAY")
			holder.text:SetFontObject(Core.fonts.section)
			holder.text:SetPoint("LEFT", holder.box, "RIGHT", 7, 0)
			holder.text:SetJustifyH("LEFT")
		end
		holder.box:SetElement(EKEY[e])
		holder.text:SetText(ELEM[e]:upper())
	end,
	menuElement = function(item) return EKEY[item.e] end,
	locked = function() return InCombatLockdown() end,
	onLocked = LockedSay,
})

ns.CustomRows.tbButtons = BtnRow
ns.CustomRows.tbTotems = TotRow
ns.TotemBarRows = { buttons = BtnRow, totems = TotRow }
SP.TotemBarRows = ns.TotemBarRows   -- (the test round and the renderer reach the rows here)

-- SP:TotemBarOpenItemMenu(kind, key, path): the settings window on Totem Bar > Bar with that
-- button's ("button": 1-4, "dropall", "es") or totem's ("totem": its rank-1 spell) menu open
function SP.TotemBarOpenItemMenu(_, kind, key, path)
	local cfg = _G.ShamanPowerConfig
	if not (cfg and cfg.Open) then return end
	local row = (kind == "totem") and TotRow or BtnRow
	row:QueueMenu(key, path)
	cfg:Open({ "buttons", "auto_button" })
end

-- ---------------------------------------------------------------------------
-- Reset This Page (Window.lua, after the page's own rows): what the two rows and their menus
-- hold, back to how it came: every button on the bar in its own place, Drop All's order and
-- its Excludes, the Blizzard Totem Sets switches, every totem in its flyout with its pulse bar
-- and flash on, Counts As Temporary as it came, the Earth Shield flyout off with nobody picked
-- and its Running Out off. Where the bar sits stays (as on every page); none of this is a look
-- a theme holds.
-- ---------------------------------------------------------------------------
function SP.TotemBarResetPage(sp)
	if InCombatLockdown() or not sp.opt then return end
	local o = sp.opt
	for e = 1, 4 do o[SHOW_KEY[e]] = true end
	o.showDropAllButton = true
	o.totemBarOrder = { 1, 2, 3, 4 }
	o.dropOrder = { 1, 2, 3, 4 }
	o.dropAllUsesTotemSets, o.totemSetsSyncAssignments, o.totemSetsAdoptFromBar = nil, nil, nil
	for e = 1, 4 do if Excluded(e) and sp.SetDropAllExclude then sp:SetDropAllExclude(e, false) end end
	o.flyoutTotems = nil
	o.flyoutOrder = nil   -- (3.0.9) the flyouts back in the game's order
	TotemsChanged()
	o.pulseOnlySome, o.pulseTotemsOff, o.pulseFlashOnlySome, o.pulseFlashTotemsOff = nil, nil, nil, nil
	o.usualTotemTemp = nil
	o.dropAllIcon = nil   -- (a picked Drop All icon goes too: the button rotates again)
	ResetES()
	for _, fn in ipairs({ "UpdateMiniTotemBar", "UpdateDropAllButton", "RecreateTotemFlyouts", "ApplyUsualTotemSettings" }) do
		Run(fn)
	end
end
