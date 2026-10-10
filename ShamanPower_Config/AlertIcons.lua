-- ShamanPower_Config :: AlertIcons
-- Expiring Alerts and Reactive Totems as icon pages (A16, 3.0.8), on the shared icon row
-- (IconRow.lua). Each page keeps only what is about the whole page (ShamanPowerOptions.lua);
-- every alert is an icon in its Alerts row. Click: that alert on or off. Right-click:
-- everything about that one alert, grouped (an It Shows line first: what it says and when).
-- No drag: Expiring Alerts' lines show as things happen and each Reactive Totems alert has
-- its own spot, so there is no order. In a fight the rows refuse changes, as the other icon
-- pages do (the row's lock closes the menus when a fight starts; a click, a menu choice,
-- Copy / Paste and Reset refuse and say so): on WoW: Forever the game draws the alerts in a
-- fight, and the module builds them again with any change once the fight ends.
--
-- Expiring Alerts: Lightning Shield, Water Shield (and Earth Shield on your target, TBC
-- Anniversary), the Earth, Fire, Water and Air totems, Main Hand, Off Hand. Each alert's
-- values go through the module (SP:ExpiringAlertOpt / SetExpiringAlertOpt ...,
-- ShamanPower_ExpiringAlerts): empty until changed, today's shared values until then. A
-- shield's sound is ShamanPower's own, one per shield (SP:ShieldSoundOn ...,
-- ShamanPowerShieldSound.lua): the same setting as that shield's sound on Shield Charges.
-- Reactive Totems: Fear, Poison, Disease, each with its own look, Spell Keybind, glow,
-- sound and Hide While Its Totem Is Down (SP:ReactiveOpt ..., ShamanPower_ReactiveTotems).
-- A value an alert has of its own is drawn in blue, and the alert gets the blue corner.
local _, ns = ...
local Core = ns.Core
local SP = ShamanPower
if not (Core and SP and ns.IconRow) then return end

local Menu = ns.IconRow.Menu
local Choice, OnOff, Slider, Group = Menu.Choice, Menu.OnOff, Menu.Slider, Menu.Group
local SEP = { separator = true }
local FOREVER = SPCompat and SPCompat.FOREVER

local function Label(id, fb)
	if SPCompat and SPCompat.SpellLabel then return SPCompat.SpellLabel(id, fb) end
	return fb
end
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
local function Known(id) return id and SPCompat and SPCompat.KnowsSpellID and SPCompat.KnowsSpellID(id) or false end
local function OnOffWord(v) if v then return "On" end return "Off" end
local function Pct(v) return string.format("%d%%", math.floor((tonumber(v) or 0) * 100 + 0.5)) end
local function Volume(v) return string.format("%d%%", math.floor((tonumber(v) or 0) + 0.5)) end
local function PreviewChanged()
	local cfg = _G.ShamanPowerConfig
	if cfg and cfg.PreviewChanged then cfg:PreviewChanged() end
end

-- the sound list: every LibSharedMedia sound; only the speaker button plays one
local function SoundList(get, set)
	return {
		text = "Sound", subMaxHeight = 300,
		value = function()
			local v, own = get()
			return tostring(v or ""), own
		end,
		sub = function()
			local lsm = LibStub and LibStub("LibSharedMedia-3.0", true)
			local names = lsm and lsm:List("sound")
			local cur = get()
			local items = {}
			for _, name in ipairs(type(names) == "table" and names or {}) do
				items[#items + 1] = { text = name, selected = name == cur,
					preview = function() if SP.PlaySoundWithVolume and SP.GetSoundFile then SP:PlaySoundWithVolume(SP:GetSoundFile(name), 100, true) end end,
					onClick = function() return set(name) end }
			end
			return items
		end,
	}
end

-- a line that only says something (It Shows, Key Now): a click keeps the menu open
local function InfoLine(text, value, tip)
	return { text = text, tip = tip, value = function() return value(), false end, onClick = function() return true end }
end

-- ===========================================================================
-- Expiring Alerts
-- ===========================================================================
local EA_CAPTION = "|cff3FA9F5CLICK|r an alert to turn it on or off. |cff3FA9F5RIGHT-CLICK|r it for its settings:"
	.. " each alert has its own. |cff3FA9F5Dark|r: not learned yet (you can still set it up)."
local EA_HINT = "Click: turn it on or off\nRight-click: its settings"
local NOT_LOADED = "Expiring Alerts is not loaded: turn on ShamanPower [Expiring Alerts] in the AddOns list, then type /reload."
local EA_COMBAT = "|cff0070ddShamanPower|r: |cffe64a4aExpiring Alerts' settings can't change in combat - try again after the fight.|r"
-- a change in a fight: refused, and said (the row's lock closes the menu when a fight starts)
local function EARefuse()
	if not InCombatLockdown() then return false end
	print(EA_COMBAT)
	return true
end

local EAItems, EAByKey = {}, {}
local SHIELD_KEYS = { "LS", "WS", "ES" }
local WHICH = { LS = 1, WS = 2, ES = 3 }
local ELEMENTS = { "Earth", "Fire", "Water", "Air" }
local ELEMENT_KEYS = { "earth", "fire", "water", "air" }
-- a totem of each element for the It Shows line (Stoneskin, Searing, Healing Stream, Windfury)
local EXAMPLE_TOTEM = { { 8071, "Stoneskin Totem" }, { 3599, "Searing Totem" }, { 5394, "Healing Stream Totem" },
	{ 8512, "Windfury Totem" } }
-- a plain weapon icon for an empty hand
local EMPTY_HAND = { mh = "Interface\\Icons\\INV_Mace_01", oh = "Interface\\Icons\\INV_Axe_01" }
local HAND_SLOT = { mh = 16, oh = 17 }
-- the weapon in that hand's icon (nil: the hand is empty)
local function HeldWeapon(it)
	local tex = GetInventoryItemTexture and GetInventoryItemTexture("player", HAND_SLOT[it.key])
	if tex == nil or (issecretvalue and issecretvalue(tex)) then return nil end
	return tex
end


local function EASetup()
	if #EAItems > 0 then return end
	local water = (SP.ShieldSpells and SP.ShieldSpells[2] and SP.ShieldSpells[2][1]) or (FOREVER and 408510) or 24398
	local spells = { LS = 324, WS = water, ES = 974 }
	local names = { LS = Label(324, "Lightning Shield"), WS = Label(water, "Water Shield"), ES = Label(974, "Earth Shield") .. " (on your target)" }
	local icons = { LS = SpellTexture(324) or 136051, WS = SpellTexture(water) or 132315, ES = SpellTexture(974) or 136089 }
	for _, k in ipairs(SHIELD_KEYS) do
		EAItems[#EAItems + 1] = { key = k, kind = "shield", which = WHICH[k], spell = spells[k], name = names[k], icon = icons[k],
			group = "Enable Shield Alerts" }
	end
	for e = 1, 4 do
		EAItems[#EAItems + 1] = { key = ELEMENT_KEYS[e], kind = "totem", element = e, name = ELEMENTS[e] .. " Totems",
			group = "Enable Totem Alerts" }
	end
	EAItems[#EAItems + 1] = { key = "mh", kind = "imbue", name = "Main Hand", hand = "main hand", group = "Enable Imbue Alerts" }
	EAItems[#EAItems + 1] = { key = "oh", kind = "imbue", name = "Off Hand", hand = "off hand", group = "Enable Imbue Alerts" }
	for _, it in ipairs(EAItems) do EAByKey[it.key] = it end
end

-- Earth Shield on your target: TBC Anniversary only (WoW: Forever has no Earth Shield)
local function EarthHere()
	if FOREVER then return false end
	return not (SPCompat and SPCompat.earthShieldExists == false)
end
local function EAList()
	EASetup()
	local out = {}
	for _, it in ipairs(EAItems) do
		if it.key ~= "ES" or EarthHere() then out[#out + 1] = it end
	end
	return out
end
local function EALoaded() return SP.ExpiringAlertsLoaded and type(SP.ExpiringAlertOpt) == "function" and type(rawget(_G, "ShamanPowerExpiringAlertsDB")) == "table" end

local EARow   -- (below)

-- ---- the values: a totem's or a weapon's through the module, a shield's sound through the core
local SHIELD_SOUND_KEY = { "shieldDropSoundLS", "shieldDropSoundWS", "shieldDropSoundES" }
local SHIELD_NAME_KEY = { "shieldDropSoundNameLS", "shieldDropSoundNameWS", "shieldDropSoundNameES" }
local function ShieldGet(which, name)
	if not SP.ShieldSoundOn then return nil, false end
	local sharedOn, sharedName = SP:ShieldSoundShared(which)
	if name == "sound" then
		local v = SP:ShieldSoundOn(which)
		return v, v ~= sharedOn
	end
	local v = SP:ShieldSoundName(which)
	return v, v ~= sharedName
end
-- a shield's sound as saved (nil: it uses the shared one); set: saved as is
local function ShieldRaw(which, name)
	local o = SP.opt
	if not o then return nil end
	return o[(name == "sound") and SHIELD_SOUND_KEY[which] or SHIELD_NAME_KEY[which]]
end
local function ShieldRawSet(which, name, v)
	local o = SP.opt
	if not o then return end
	o[(name == "sound") and SHIELD_SOUND_KEY[which] or SHIELD_NAME_KEY[which]] = v
	if SP.UpdateShieldSounds then SP:UpdateShieldSounds() end
end

local function Get(it, name)
	if it.kind == "shield" then return ShieldGet(it.which, name) end
	if not EALoaded() then return nil, false end
	return SP:ExpiringAlertOpt(it.key, name)
end
local function Raw(it, name)
	if it.kind == "shield" then return ShieldRaw(it.which, name) end
	local sv = rawget(_G, "ShamanPowerExpiringAlertsDB")
	local own = type(sv) == "table" and type(sv.alertOwn) == "table" and sv.alertOwn[it.key]
	if type(own) ~= "table" then return nil end
	return own[name]   -- (an own false stays false: "off", not "uses the shared one")
end
local function RawSet(it, name, v)
	if it.kind == "shield" then return ShieldRawSet(it.which, name, v) end
	if EALoaded() then SP:SetExpiringAlertOpt(it.key, name, v) end
end
-- a choice: saved as this alert's own, the menu stays open and is drawn again
local function Set(it, name, v)
	if EARefuse() then return true end
	if it.kind == "shield" then
		if SP.SetShieldSoundOpt then SP:SetShieldSoundOpt(it.which, name, v) end
	elseif EALoaded() then
		SP:SetExpiringAlertOpt(it.key, name, v)
	end
	EARow:Changed(true)
	return true
end
-- a Sound group's value: On / Off, blue when its switch or (while on) its sound is its own
local function SoundValue(it)
	local on, ownOn = Get(it, "sound")
	local _, ownName = Get(it, "soundName")
	return OnOffWord(on), (ownOn or (on and ownName)) and true or false
end
local function OnOffName(it, text, name, tip)
	return OnOff(text, function() return Get(it, name) end, function(v) return Set(it, name, v) end, tip)
end

local function AlertOn(it)
	if not EALoaded() then return false end
	return SP:ExpiringAlertOn(it.key)
end
local function EAOwn(it)
	if it.kind == "shield" then return SP.ShieldSoundOwnChanged and SP:ShieldSoundOwnChanged(it.which) or false end
	return EALoaded() and SP:ExpiringAlertOwnChanged(it.key) or false
end

-- ---- Copy: a value snapshot at Copy time; between alerts that fall back on the same shared
-- value the saved state is copied (its own value, or "uses the shared one"); between alerts
-- with different fallbacks (a shield and a totem, Earth Shield and your own shields) the
-- value it has. Only what both have: between a shield, a totem and a weapon, the sound.
local TOTEM_NAMES = { "destroyed", "destroyedChat", "destroyedCenter", "destroyedParty", "expired", "sound", "soundName" }
local DESTROYED_NAMES = { "destroyed", "destroyedChat", "destroyedCenter", "destroyedParty" }
local SOUND_NAMES = { "sound", "soundName" }
local function NamesOf(it) if it.kind == "totem" then return TOTEM_NAMES end return SOUND_NAMES end
local function Family(it)
	if it.kind == "shield" then return (it.key == "ES") and "es" or "shield" end
	return it.kind
end
local function Snapshot(it, names)
	local snap = { from = it, family = Family(it), values = {} }
	for _, name in ipairs(names or NamesOf(it)) do
		local v = Get(it, name)
		snap.values[name] = { raw = Raw(it, name), eff = v }
	end
	return snap
end
local function Paste(snap, to, only)
	if EARefuse() then return end
	local same = snap.family == Family(to)
	local wanted = {}
	for _, n in ipairs(only or NamesOf(to)) do wanted[n] = true end
	for name, e in pairs(snap.values) do
		if wanted[name] then
			if same then RawSet(to, name, e.raw) else RawSet(to, name, e.eff) end
		end
	end
end
local function CopyTo(from, list, names)
	if EARefuse() then return end
	local snap = Snapshot(from, names)
	for _, to in ipairs(list) do
		if to ~= from then Paste(snap, to, names) end
	end
end
local function OthersOfKind(it)
	local o = {}
	for _, x in ipairs(EAList()) do if x.kind == it.kind and x ~= it then o[#o + 1] = x end end
	return o
end
local function CopyLine(text, tip, fn)
	return { text = text, tip = tip, onClick = function() fn(); EARow:Changed(true); return true end }
end

-- ---- the menu
local function ShieldShows(it)
	if it.key == "ES" then
		return Label(974, "Earth Shield") .. " (Tank) FADED!",
			"When your Earth Shield is gone from the player you put it on (its last charge used or run out), with their name."
	end
	if FOREVER then
		return it.name .. " FADED!", "When this shield is gone from you. In a fight the game hides your shields from addons,"
			.. " so the line shows once the fight ends; the sound (Sound When It Drops) plays in fights too, played by the game."
	end
	return it.name .. " FADED!", "When this shield is gone from you (its last charge used, run out, canceled or replaced). In fights too."
end
local function TotemShows(it)
	local ex = EXAMPLE_TOTEM[it.element]
	local name = (SPCompat and SPCompat.SpellName and SPCompat.SpellName(ex[1], ex[2])) or ex[2]
	return name .. " Destroyed!", "When a totem of this element is destroyed (When One Is Destroyed), and with When One Expires"
		.. " on also when one runs out by itself (" .. name .. " Expired). A totem you take down yourself (Totemic Call,"
		.. " a right-click) is not destroyed."
		.. (FOREVER and " In a fight the game hides your totems from addons: ShamanPower tells a destroyed totem from your own"
			.. " drops, so it works in fights too." or " In fights too.")
end

local function ShieldSoundRows(it)
	local r = { OnOffName(it, "Sound When It Drops", "sound", it.key == "ES"
		and ("When your Earth Shield is gone from the player you put it on. It plays only while this alert is on."
			.. " The same setting as Earth Shield's sound on Shield Charges.")
		or ("The moment your " .. it.name .. " leaves you (its last charge used, run out, canceled or replaced), in fights"
			.. " too" .. (FOREVER and ": the game plays it, so the page's Volume doesn't change it." or ".")
			.. " It plays with this alert on or off. The same setting as this shield's sound on Shield Charges.")) }
	if Get(it, "sound") then
		r[#r + 1] = SoundList(function() return Get(it, "soundName") end, function(v) return Set(it, "soundName", v) end)
		r[#r + 1] = { text = "Test Sound", onClick = function()
			if SP.TestShieldSound then SP:TestShieldSound(SHIELD_KEYS[it.which]) end
			return true
		end }
	end
	r[#r + 1] = SEP
	r[#r + 1] = CopyLine("Copy Sound To All Shields",
		"Copies this shield's Sound When It Drops and its sound onto the other shields, once. They stay separate.",
		function() CopyTo(it, OthersOfKind(it), SOUND_NAMES) end)
	return r
end

local function PlayAlertSound(name)
	if not (SP.PlaySoundWithVolume and SP.GetSoundFile) then return end
	local sv = rawget(_G, "ShamanPowerExpiringAlertsDB")
	SP:PlaySoundWithVolume(SP:GetSoundFile(name), type(sv) == "table" and sv.soundVolume or 100, true)
end
local function PlaySoundRows(it, tip, copyText, copyTip, copyFn)
	local r = { OnOffName(it, "Play Sound", "sound", tip) }
	if Get(it, "sound") then
		r[#r + 1] = SoundList(function() return Get(it, "soundName") end, function(v) return Set(it, "soundName", v) end)
		r[#r + 1] = { text = "Test Sound", onClick = function() PlayAlertSound((Get(it, "soundName"))) return true end }
	end
	r[#r + 1] = SEP
	r[#r + 1] = CopyLine(copyText, copyTip, copyFn)
	return r
end

local function DestroyedRows(it)
	local r = { OnOffName(it, "Alert On My Screen", "destroyed",
		"A line like Searing Totem Destroyed! at the alerts' spot, with this element's sound. Off: nothing at all when one is destroyed.") }
	if Get(it, "destroyed") then
		r[#r + 1] = OnOffName(it, "Line in My Chat Window", "destroyedChat",
			"A line in your own chat window. Only you see it." .. (FOREVER and " It works in fights too." or ""))
		r[#r + 1] = OnOffName(it, "Big Text on My Screen", "destroyedCenter",
			"Big raid-warning text at the top of your screen. Drawn only on your screen; nothing is sent.")
		r[#r + 1] = OnOffName(it, "Tell My Group in Chat", "destroyedParty",
			"Says it in party, raid or instance chat so everyone sees it."
			.. (FOREVER and " The game locks group chat in boss fights, Mythic+ and PvP matches: then only you are told." or ""))
	end
	r[#r + 1] = SEP
	r[#r + 1] = CopyLine("Copy When One Is Destroyed To All Totems",
		"Copies these choices onto the other three elements, once. They stay separate.",
		function() CopyTo(it, OthersOfKind(it), DESTROYED_NAMES) end)
	return r
end

local function UsualLine(it)
	local o = SP.opt
	local on = o ~= nil and o.usualTotemReminder == true and o.usualTotemAlert == true
	return {
		text = "Put Your Usual Totem Back",
		value = function() return OnOffWord(on), false end,
		tip = "When a temporary " .. ELEMENTS[it.element]:lower() .. " totem you dropped ends (like Tremor or Grounding), a line"
			.. " like Put Windfury back shows with these alerts, in this element's color, with no sound. One switch for all"
			.. " four elements, on Totem Bar > Effects: Remind Me to Put My Usual Totem Back, then Also Show a Text Alert."
			.. " Turning this element's alerts off here doesn't stop it.",
		sub = function()
			return { { text = "Open Totem Bar > Effects", tip = "Where its switch is: Put Your Usual Totem Back > Also Show a Text Alert.",
				onClick = function()
					local cfg = _G.ShamanPowerConfig
					if cfg and cfg.Open then cfg:Open({ "fluffy", "totembar_effects_section" }) end
				end } }
		end,
	}
end

local function TurnLine(it, on)
	return { text = on and "Turn This Alert Off" or "Turn This Alert On",
		tip = "The same as a click on its icon. Its settings stay as they are.",
		onClick = function()
			if EARefuse() then return end
			if EALoaded() then SP:SetExpiringAlertOn(it.key, not on) end
			EARow:Changed(false)
		end }
end

local function EAMenu(item)
	if not EALoaded() then return { { text = NOT_LOADED, disabled = true } } end
	local it = item
	local r = {}
	if it.kind == "shield" then
		local shows, tip = ShieldShows(it)
		r[#r + 1] = InfoLine("It Shows", function() return shows end, tip)
		r[#r + 1] = Group("Sound", function() return ShieldSoundRows(it) end,
			"The same setting as this shield's sound on Shield Charges: each shield has its own.",
			function() return SoundValue(it) end)
	elseif it.kind == "totem" then
		local shows, tip = TotemShows(it)
		r[#r + 1] = InfoLine("It Shows", function() return shows end, tip)
		r[#r + 1] = Group("When One Is Destroyed", function() return DestroyedRows(it) end)
		r[#r + 1] = OnOffName(it, "When One Expires", "expired",
			"A line like Searing Totem Expired when one runs out by itself. It can be a lot of lines.")
		r[#r + 1] = UsualLine(it)
		r[#r + 1] = Group("Sound", function()
			return PlaySoundRows(it, "For this element's Destroyed and Expired lines. How loud: the page's Volume.",
				"Copy Sound To All Totems", "Copies this element's sound onto the other three, once. They stay separate.",
				function() CopyTo(it, OthersOfKind(it), SOUND_NAMES) end)
		end, nil, function() return SoundValue(it) end)
	else
		r[#r + 1] = InfoLine("It Shows", function() return "Weapon Imbue (" .. (it.key == "mh" and "MH" or "OH") .. ") FADED!" end,
			"When the imbue on your " .. it.hand .. " weapon runs out or comes off (a weapon swap too). In fights too, on both games.")
		local other = EAByKey[it.key == "mh" and "oh" or "mh"]
		r[#r + 1] = Group("Sound", function()
			return PlaySoundRows(it, "When this weapon's imbue fades. How loud: the page's Volume.",
				"Copy Sound To " .. other.name, "Copies this hand's sound onto the " .. other.hand .. ", once. They stay separate.",
				function() CopyTo(it, { other }, SOUND_NAMES) end)
		end, nil, function() return SoundValue(it) end)
	end
	-- Copy / Paste / Copy To, on / off, Reset
	r[#r + 1] = SEP
	r[#r + 1] = { text = "Copy Settings",
		tip = "Remembers every setting of this alert as it is now, for Paste Settings on another alert.",
		onClick = function()
			EARow.clip = { name = it.name, from = it, snap = Snapshot(it) }
			return true
		end }
	local clip = EARow.clip
	r[#r + 1] = { text = clip and ("Paste Settings  (from " .. clip.name .. ")") or "Paste Settings",
		disabled = (not clip or clip.from == it) or nil,
		tip = (not clip) and "Copy Settings on another alert first, then paste them here."
			or (clip.from == it) and "These are this alert's own settings: paste them on another alert."
			or "Puts the settings you copied onto this alert, once. Between a shield, a totem and a weapon only what both have is copied (the sound).",
		onClick = function()
			if EARow.clip then Paste(EARow.clip.snap, it) end
			EARow:Changed(true)
			return true
		end }
	r[#r + 1] = { text = "Copy Settings To...",
		tip = "Every setting of this alert onto another one, once. Between a shield, a totem and a weapon only what both have is copied (the sound).",
		sub = function()
			local o = {}
			for _, x in ipairs(EAList()) do
				if x ~= it then
					local tex = {}
					local n = EARow.def.textures(x, tex)
					o[#o + 1] = { text = x.name, icon = n > 0 and tex[1] or nil,
						onClick = function() CopyTo(it, { x }); EARow:Changed(false) end }
				end
			end
			o[#o + 1] = SEP
			o[#o + 1] = { text = "All Alerts", onClick = function() CopyTo(it, EAList()); EARow:Changed(false) end }
			return o
		end }
	r[#r + 1] = SEP
	r[#r + 1] = TurnLine(it, AlertOn(it))
	local own = EAOwn(it)
	r[#r + 1] = { text = "Reset This Alert", disabled = (not own) or nil,
		tip = own and "Back to the settings it used before it had its own (what the page had)."
			or "Nothing to reset: it uses the settings the page had.",
		onClick = function()
			if EARefuse() then return end
			if it.kind == "shield" then
				if SP.SetShieldSoundOpt then SP:SetShieldSoundOpt(it.which, "reset") end
			elseif EALoaded() then
				SP:ResetExpiringAlert(it.key)
			end
			EARow:Changed(false)
		end }
	return r
end

local function EATooltip(it)
	if not EALoaded() then return NOT_LOADED end
	local lines = {}
	if it.kind == "shield" and not Known(it.spell) then
		lines[#lines + 1] = (it.key == "ES") and "You haven't learned Earth Shield yet (a talent). You can still set it up: it alerts once you learn it."
			or "You haven't learned this shield yet. You can still set it up: it alerts once you learn it."
	end
	local on, byGroup = SP:ExpiringAlertOn(it.key)
	if on then
		lines[#lines + 1] = "On: " .. ((it.kind == "shield") and "a line when it fades."
			or (it.kind == "totem") and "a line when one of these totems is destroyed (or runs out, with When One Expires on)."
			or "a line when this weapon's imbue fades.")
	elseif byGroup then
		lines[#lines + 1] = "Off: it was turned off with the old " .. it.group .. " switch (that switch is gone: each alert"
			.. " is its own switch now). A click turns on only this one."
	else
		lines[#lines + 1] = "Off: a click turns it back on, with all its settings."
	end
	if it.kind == "imbue" and not HeldWeapon(it) then
		lines[#lines + 1] = "No weapon in your " .. it.hand .. " right now: its icon is a plain one until you hold one."
	end
	if EAOwn(it) then
		lines[#lines + 1] = "It has settings of its own (Reset This Alert in its menu clears them)."
	end
	return table.concat(lines, "\n\n")
end

-- A totem element wears Blizzard's faded empty totem in its element's color (the totem bar's
-- Empty Totem in Flyouts art, Interface\\Buttons\\UI-TotemBar) with EARTH / FIRE / WATER / AIR
-- over it: it reads as "this element", not as one totem you own (the owner, 2026-10-09).
local EMPTY_ART = SP.FlyoutArrowArt
local ELEMENT_WORD = { "EARTH", "FIRE", "WATER", "AIR" }
local function EmptyArt(it)
	if it.kind ~= "totem" or not (EMPTY_ART and EMPTY_ART.texture and EMPTY_ART.empty) then return nil end
	return EMPTY_ART.empty[it.element]
end
local function EATexCoords(it)
	local c = EmptyArt(it)
	if c then return c[1], c[2], c[3], c[4] end
end
local function EAOverlay(it)
	if EmptyArt(it) then return ELEMENT_WORD[it.element] end
end

local function EATextures(it, out)
	if it.kind == "shield" then
		out[1] = it.icon
	elseif it.kind == "totem" then
		out[1] = (EmptyArt(it) and EMPTY_ART.texture) or (SP.ElementIcons and SP.ElementIcons[it.element]) or "Interface\\Icons\\INV_Misc_QuestionMark"
	else
		-- the weapon you hold; a plain weapon icon when that hand is empty
		out[1] = HeldWeapon(it) or EMPTY_HAND[it.key]
	end
	return 1
end

EARow = ns.IconRow.New({
	caption = EA_CAPTION,
	hint = EA_HINT,
	list = function(out) for _, it in ipairs(EAList()) do out[#out + 1] = it end end,
	textures = EATextures,
	texCoords = EATexCoords,
	overlay = EAOverlay,
	shown = AlertOn,
	learned = function(it)
		if it.kind == "shield" then return Known(it.spell) end
		return true
	end,
	hasOwn = EAOwn,
	tooltip = EATooltip,
	toggle = function(it)
		if EARefuse() then return end
		if EALoaded() then SP:SetExpiringAlertOn(it.key, not AlertOn(it)) end
	end,
	menu = EAMenu,
	locked = function() return InCombatLockdown() end,
	onLocked = function() print(EA_COMBAT) end,
})
ns.CustomRows.eaIcons = EARow
ns.ExpiringAlertsRow = EARow

-- SP:ExpiringAlertsOpenMenu(key, path): the settings window on the Expiring Alerts page with
-- that alert's menu open once the row is drawn
function SP.ExpiringAlertsOpenMenu(_, key, path)
	local cfg = _G.ShamanPowerConfig
	if not (cfg and cfg.Open) then return end
	EARow:QueueMenu(key, path)
	cfg:Open({ "fluffy", "expiringalerts_section" })
end

-- Reset This Page (Window.lua calls it after the page's own rows): every alert's menu
-- settings back to how they came (each alert's own values gone, the values they fall back
-- on back to their defaults, every alert on again), and the shields' sounds (the same
-- settings as on Shield Charges). Left alone, as on every page: where the alerts sit, and
-- what a theme holds (the alert text colors, General > Themes).
local KEEP = { color = true }
function SP.ExpiringAlertsResetPage(sp)
	if InCombatLockdown() then return end
	local sv = rawget(_G, "ShamanPowerExpiringAlertsDB")
	if type(sv) == "table" and sp.ExpiringAlertsDefaults then
		local d = sp:ExpiringAlertsDefaults()
		sv.alertOwn = nil
		for _, group in ipairs({ "shields", "totems", "weaponImbues" }) do
			if type(sv[group]) ~= "table" then sv[group] = {} end
			for k, v in pairs(d[group] or {}) do
				if not KEEP[k] and type(v) ~= "table" then sv[group][k] = v end
			end
		end
	end
	if sp.SetShieldSoundOpt and sp.opt then
		for which = 1, 3 do sp:SetShieldSoundOpt(which, "reset") end
		if sp.SetShieldDropSound then sp:SetShieldDropSound(false) end
		sp.opt.shieldDropSoundName = nil
		if sp.UpdateShieldSounds then sp:UpdateShieldSounds() end
	end
	EARow:Repaint()
end

-- ===========================================================================
-- Reactive Totems
-- ===========================================================================
local RT_CAPTION = "|cff3FA9F5CLICK|r an alert to turn it on or off. |cff3FA9F5RIGHT-CLICK|r it for its settings:"
	.. " each alert has its own. |cff3FA9F5Dark|r: its totem isn't learned yet (you can still set it up)."
local RT_NOT_LOADED = "Reactive Totems is not loaded: turn on ShamanPower [Reactive Totems] in the AddOns list, then type /reload."
local RT_COMBAT = "|cff0070ddShamanPower|r: |cffe64a4aReactive Totems' settings can't change in combat - try again after the fight.|r"
-- a change in a fight: refused, and said (the module's setters refuse it too; the row's lock closes
-- the menu when a fight starts)
local function RTRefuse()
	if not InCombatLockdown() then return false end
	print(RT_COMBAT)
	return true
end
local RT_IDS = { "fear", "poison", "disease" }
local RT_TITLE = { fear = "Fear", poison = "Poison", disease = "Disease" }
local RTItems = {}

local function RTLoaded() return SP.ReactiveTotemsLoaded and type(SP.ReactiveOpt) == "function" and type(rawget(_G, "ShamanPower_ReactiveTotems")) == "table" end
local function RTData(id) return SP.ReactiveTotems and SP.ReactiveTotems[id] end
local RT_SPELL = { fear = 8143, poison = 8166, disease = 8170 }
local RT_TOTEM = { fear = "Tremor Totem", poison = "Poison Cleansing Totem", disease = "Disease Cleansing Totem" }
local function RTSetup()
	if #RTItems > 0 then return end
	for _, id in ipairs(RT_IDS) do
		local totem = Label(RT_SPELL[id], RT_TOTEM[id])
		RTItems[#RTItems + 1] = { key = id, totem = totem, name = RT_TITLE[id] .. ": " .. totem, spell = RT_SPELL[id] }
	end
end

local RTRow   -- (below)

local function RGet(id, name)
	if not RTLoaded() then return nil, false end
	return SP:ReactiveOpt(id, name)
end
local function RVal(id, name) return (RGet(id, name)) end
local function RSet(id, name, v)
	if RTRefuse() then return true end
	if RTLoaded() then SP:SetReactiveOpt(id, name, v) end
	RTRow:Changed(true)
	return true
end
-- a slider's value: only saved, the icons and the preview follow; never a redraw of the page
-- under a drag
local function RSliderSet(id, name, v)
	if RTRefuse() then return end
	if RTLoaded() then SP:SetReactiveOpt(id, name, v) end
	RTRow:Repaint()
	PreviewChanged()
end
local function ROnOff(id, text, name, tip)
	return OnOff(text, function() return RGet(id, name) end, function(v) return RSet(id, name, v and true or false) end, tip)
end
-- Show / Hide for a setting saved as hide = true (Background, Border)
local function RShowHideInv(id, text, name, tip)
	return Choice(text, { { true, "Show" }, { false, "Hide" } }, function()
		local v, own = RGet(id, name)
		return not v, own
	end, function(v) return RSet(id, name, not v) end, tip)
end
-- Show / Hide for a setting saved as show = true (Debuff Text, Debuff Icon, Totem Name)
local function RShowHide(id, text, name, tip)
	return Choice(text, { { true, "Show" }, { false, "Hide" } }, function()
		local v, own = RGet(id, name)
		return v and true or false, own
	end, function(v) return RSet(id, name, v) end, tip)
end

local RT_LOOK = { "iconSize", "opacity", "fontSize", "fontOutline", "hideBackground", "hideBorder", "showDebuffName",
	"showDebuffIcon", "showTotemName" }
local RT_KEYS = { "showSpellKeybind", "noKeyText" }
local RT_GLOW = { "showGlow", "glowIntensity" }
local RT_SOUND = { "playSound", "soundName", "soundVolume" }

-- Copy: a value snapshot at Copy time (each value as saved: its own, or "uses the shared one";
-- the three alerts fall back on the same shared values)
local function RSnapshot(id, names)
	local snap = {}
	for _, name in ipairs(names or SP.ReactiveOwnNames or {}) do snap[name] = SP:ReactiveOwnRaw(id, name) end
	return snap
end
local function RCopyTo(from, to, names)
	if RTRefuse() or not RTLoaded() then return end
	names = names or SP.ReactiveOwnNames
	local snap = RSnapshot(from, names)
	for _, id in ipairs(RT_IDS) do
		if id ~= from and (to == "all" or to == id) then SP:SetReactiveOpts(id, snap, names) end
	end
end
local function RCopyLine(text, from, names)
	return { text = text, tip = "Copies this alert's " .. text:match("^Copy (.-) To") .. " settings onto the other alerts, once. They stay separate.",
		onClick = function() RCopyTo(from, "all", names); RTRow:Changed(true); PreviewChanged(); return true end }
end

local function RTShows(id)
	if id == "fear" then
		if FOREVER then
			return "You: Feared, Charmed, Asleep", "Only while YOU are feared, charmed or asleep: in a fight the game hides what"
				.. " kind of control the others in your group are under. In a fight the game draws the alert."
		end
		return "You Or Your Group: Feared, Charmed", "While you or a party member is feared, charmed or horrified."
	end
	local what = (id == "poison") and "poisoned" or "diseased"
	return "You Or Your Group: " .. ((id == "poison") and "Poisoned" or "Diseased"),
		"While you or a party member is " .. what .. "." .. (FOREVER and " In a fight the game draws the alert." or "")
end

local function LookRows(id)
	local r = {}
	r[#r + 1] = Slider("Icon Size", 32, 256, 4, function() return RVal(id, "iconSize") or 64 end,
		function(v) RSliderSet(id, "iconSize", v) end, nil, false,
		"How big this alert is. In Unlock UI, the mouse wheel over its box does the same.")
	r[#r + 1] = Slider("Opacity", 0.2, 1, 0.1, function() return RVal(id, "opacity") or 1 end,
		function(v) RSliderSet(id, "opacity", v) end, Pct, true, "How see-through this alert is. In Unlock UI: Ctrl + mouse wheel over its box.")
	r[#r + 1] = Slider("Text Size", 8, 24, 1, function() return RVal(id, "fontSize") or 14 end,
		function(v) RSliderSet(id, "fontSize", v) end, nil, false, "The size of its debuff and totem name text.")
	r[#r + 1] = ROnOff(id, "Outline", "fontOutline", "An outline round its text, unless General > Fonts & Textures sets one.")
	r[#r + 1] = RShowHideInv(id, "Background", "hideBackground", "The dark square behind the totem's icon.")
	r[#r + 1] = RShowHideInv(id, "Border", "hideBorder", "The colored edge round the totem's icon.")
	r[#r + 1] = RShowHide(id, "Debuff Text", "showDebuffName", "Who has it and what it is, like Tank: Fear.")
	if SPCompat and SPCompat.secretsRegime then
		r[#r + 1] = RShowHide(id, "Debuff Icon", "showDebuffIcon", "The debuff's own icon in the alert's corner, in fights too.")
	end
	r[#r + 1] = RShowHide(id, "Totem Name", "showTotemName", "The totem to drop, like " .. ((RTData(id) and RTData(id).totemName) or "Tremor Totem") .. ".")
	r[#r + 1] = SEP
	r[#r + 1] = RCopyLine("Copy Look To All Alerts", id, RT_LOOK)
	return r
end

local function KeyRows(it)
	local id = it.key
	local r = { ROnOff(id, "Show Spell Keybind", "showSpellKeybind",
		"Under the totem's name, the key that casts " .. it.totem .. ", like Shift-2. Only a key for that exact totem counts:"
		.. " the totem on your action bars, or its flyout button in Keybind Mode. When it has a key in both places, Keybind"
		.. " Shown (General > Keybinds) picks which one shows.") }
	if RVal(id, "showSpellKeybind") then
		r[#r + 1] = Choice("When No Key Is Bound", { { "none", "Show Nothing" }, { "show", "Show 'No Key Bound'" } }, function()
			local v, own = RGet(id, "noKeyText")
			return (v == "show") and "show" or "none", own
		end, function(v) return RSet(id, "noKeyText", v) end,
			"What the alert shows when its totem has no key: nothing, or No Key Bound as a reminder to bind one.")
		r[#r + 1] = InfoLine("Key Now", function() return SP.ReactiveKeyNow and SP:ReactiveKeyNow(id) or "" end,
			"The key found right now." .. (FOREVER and " In a fight the game draws these alerts: a key you change during a fight shows after it." or ""))
	end
	r[#r + 1] = SEP
	r[#r + 1] = { text = "Set Keys In Keybind Mode", onClick = function()
		if SP.SetKeybindMode then SP:SetKeybindMode(true) end
	end }
	r[#r + 1] = RCopyLine("Copy Spell Keybind To All Alerts", id, RT_KEYS)
	return r
end

local function GlowRows(id)
	local r = { OnOff("Glow", function()
		local v, own = RGet(id, "showGlow")
		return v ~= false, own
	end, function(v) return RSet(id, "showGlow", v and true or false) end, "A pulsing glow round the alert.") }
	if RVal(id, "showGlow") ~= false then
		r[#r + 1] = Slider("Glow Intensity", 0.2, 1, 0.1, function() return RVal(id, "glowIntensity") or 0.8 end,
			function(v) RSliderSet(id, "glowIntensity", v) end, Pct, true,
			"How bright the glow pulses. Type /reload to see a new brightness.")
	end
	r[#r + 1] = SEP
	r[#r + 1] = RCopyLine("Copy Glow To All Alerts", id, RT_GLOW)
	return r
end

local function SoundRows(id)
	local r = { ROnOff(id, "Play Sound", "playSound",
		"When the alert shows." .. (FOREVER and " Out of fights only: in a fight the game draws the alert and can't play a sound for it." or "")) }
	if RVal(id, "playSound") then
		r[#r + 1] = SoundList(function()
			local v, own = RGet(id, "soundName")
			return v or "Raid Warning", own
		end, function(v) return RSet(id, "soundName", v) end)
		r[#r + 1] = Slider("Volume", 0, 100, 1, function() return RVal(id, "soundVolume") or 100 end,
			function(v) RSliderSet(id, "soundVolume", v) end, Volume, false,
			"How loud this alert's sound is. Your game's Dialog volume must be at 100% for this to work.")
		r[#r + 1] = { text = "Test Sound", onClick = function()
			if SP.PlayReactiveSound then SP:PlayReactiveSound(id) end
			return true
		end }
	end
	r[#r + 1] = SEP
	r[#r + 1] = RCopyLine("Copy Sound To All Alerts", id, RT_SOUND)
	return r
end

-- a group's value: On / Off by its switch, blue when the switch or (while on) one of its values is its own
local function GroupValue(id, switch, ...)
	local on, own = RGet(id, switch)
	if switch == "showGlow" then on = on ~= false end
	if on and not own then
		for i = 1, select("#", ...) do
			local _, o = RGet(id, (select(i, ...)))
			if o then own = true break end
		end
	end
	return OnOffWord(on), own and true or false
end

local function RTMenu(it)
	if not RTLoaded() then return { { text = RT_NOT_LOADED, disabled = true } } end
	local id = it.key
	local r = {}
	local shows, tip = RTShows(id)
	r[#r + 1] = InfoLine("It Shows", function() return shows end, tip)
	r[#r + 1] = ROnOff(id, "Hide While " .. it.totem .. " Is Down", "hideWhenTotemActive",
		"No alert while your " .. it.totem .. " is already down."
		.. (FOREVER and " In dungeons and raids the game can hide which totem is down: then the alert shows." or ""))
	r[#r + 1] = Group("Look", function() return LookRows(id) end)
	r[#r + 1] = Group("Spell Keybind", function() return KeyRows(it) end, nil,
		function() return GroupValue(id, "showSpellKeybind", "noKeyText") end)
	r[#r + 1] = Group("Glow", function() return GlowRows(id) end, nil,
		function() return GroupValue(id, "showGlow", "glowIntensity") end)
	r[#r + 1] = Group("Sound", function() return SoundRows(id) end, nil,
		function() return GroupValue(id, "playSound", "soundName", "soundVolume") end)
	r[#r + 1] = SEP
	r[#r + 1] = { text = "Copy Settings",
		tip = "Remembers every setting of this alert as it is now, for Paste Settings on another alert.",
		onClick = function()
			RTRow.clip = { from = id, name = it.name, snap = RSnapshot(id) }
			return true
		end }
	local clip = RTRow.clip
	r[#r + 1] = { text = clip and ("Paste Settings  (from " .. clip.name .. ")") or "Paste Settings",
		disabled = (not clip or clip.from == id) or nil,
		tip = (not clip) and "Copy Settings on another alert first, then paste them here."
			or (clip.from == id) and "These are this alert's own settings: paste them on another alert."
			or "Puts the settings you copied onto this alert, once. The two never stay linked.",
		onClick = function()
			if RTRefuse() then return true end
			if RTRow.clip then SP:SetReactiveOpts(id, RTRow.clip.snap, SP.ReactiveOwnNames) end
			RTRow:Changed(true)
			PreviewChanged()
			return true
		end }
	r[#r + 1] = { text = "Copy Settings To...", sub = function()
		local o = {}
		for _, x in ipairs(RTItems) do
			if x.key ~= id then
				o[#o + 1] = { text = x.name, icon = SpellTexture(x.spell),
					onClick = function() RCopyTo(id, x.key); RTRow:Changed(false); PreviewChanged() end }
			end
		end
		o[#o + 1] = SEP
		o[#o + 1] = { text = "All Alerts", onClick = function() RCopyTo(id, "all"); RTRow:Changed(false); PreviewChanged() end }
		return o
	end }
	r[#r + 1] = SEP
	local on = SP:ReactiveAlertOn(id)
	r[#r + 1] = { text = on and "Turn This Alert Off" or "Turn This Alert On",
		tip = "The same as a click on its icon. Its settings stay as they are.",
		onClick = function()
			if RTRefuse() then return end
			SP:SetReactiveAlertOn(id, not on)
			RTRow:Changed(false)
		end }
	local own = SP:ReactiveOwnChanged(id)
	r[#r + 1] = { text = "Reset This Alert", disabled = (not own) or nil,
		tip = own and "Back to the settings it used before it had its own (what the page had)."
			or "Nothing to reset: it uses the settings the page had.",
		onClick = function()
			if RTRefuse() then return end
			SP:ResetReactiveAlert(id)
			RTRow:Changed(false)
			PreviewChanged()
		end }
	return r
end

RTRow = ns.IconRow.New({
	caption = RT_CAPTION,
	hint = EA_HINT,
	list = function(out)
		RTSetup()
		for _, it in ipairs(RTItems) do out[#out + 1] = it end
	end,
	textures = function(it, out)
		out[1] = SpellTexture(it.spell) or (RTData(it.key) and RTData(it.key).icon) or "Interface\\Icons\\INV_Misc_QuestionMark"
		return 1
	end,
	shown = function(it) return RTLoaded() and SP:ReactiveAlertOn(it.key) or false end,
	learned = function(it) return Known(it.spell) end,
	hasOwn = function(it) return RTLoaded() and SP:ReactiveOwnChanged(it.key) or false end,
	tooltip = function(it)
		if not RTLoaded() then return RT_NOT_LOADED end
		local lines = {}
		if not Known(it.spell) then
			lines[#lines + 1] = "You haven't learned " .. it.totem .. " yet. You can still set it up: it alerts once you learn it."
		end
		lines[#lines + 1] = SP:ReactiveAlertOn(it.key) and ("On: " .. (select(2, RTShows(it.key))))
			or "Off: a click turns it back on, with all its settings."
		if SP:ReactiveOwnChanged(it.key) then
			lines[#lines + 1] = "It has settings of its own (Reset This Alert in its menu clears them)."
		end
		return table.concat(lines, "\n\n")
	end,
	toggle = function(it)
		if RTRefuse() then return end
		if RTLoaded() then SP:SetReactiveAlertOn(it.key, not SP:ReactiveAlertOn(it.key)) end
		PreviewChanged()
	end,
	menu = RTMenu,
	locked = function() return InCombatLockdown() end,
	onLocked = function() print(RT_COMBAT) end,
})
ns.CustomRows.rtIcons = RTRow
ns.ReactiveTotemsRow = RTRow

-- SP:ReactiveTotemsOpenMenu(id, path): the Reactive Totems page with that alert's menu open
function SP.ReactiveTotemsOpenMenu(_, id, path)
	local cfg = _G.ShamanPowerConfig
	if not (cfg and cfg.Open) then return end
	RTRow:QueueMenu(id, path)
	cfg:Open({ "fluffy", "reactivetotems_section" })
end

-- Reset This Page: every alert's menu settings back to how they came (each alert's own
-- values gone, the values they fall back on back to their defaults, every alert on
-- again). Left alone: where the alerts sit, and what a theme holds (the alert colors, and
-- each alert's own looks: the alert's entries in the theme cards, General > Themes).
function SP.ReactiveTotemsResetPage(sp)
	if InCombatLockdown() or not RTLoaded() then return end
	local sv = rawget(_G, "ShamanPower_ReactiveTotems")
	local d = sp.ReactiveTotemsDefaults and sp:ReactiveTotemsDefaults()
	if not d then return end
	-- each alert's own looks a theme holds stay: the theme stays as it is
	local looks, keep = sp.ReactiveThemeLooks or {}, {}
	for _, id in ipairs(RT_IDS) do
		for _, name in ipairs(looks) do
			local v = sp:ReactiveOwnRaw(id, name)
			if v ~= nil then keep[id] = keep[id] or {}; keep[id][name] = v end
		end
	end
	sv.alertOwn = nil
	for _, name in ipairs(sp.ReactiveOwnNames or {}) do sv[name] = d[name] end
	sv.trackFear, sv.trackPoison, sv.trackDisease = true, true, true
	for id, own in pairs(keep) do sp:SetReactiveOpts(id, own, looks) end
	sp:ReactiveOptChanged(nil, "showSpellKeybind")
	sp:ReactiveOptChanged(nil, "hideWhenTotemActive")
	RTRow:Repaint()
end
