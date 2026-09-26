-- ============================================================================
-- Setup share code: a short, anonymous string listing which ShamanPower features
-- a player uses, for them to paste in the ShamanPower Discord so the developer
-- can see what people actually use. Nothing personal goes in it (no name, realm,
-- guild). Built only when asked (the settings button, /sp share, the tour's
-- Finish page); nothing here runs otherwise.
--
-- Format:  "SPS1:" .. base64url(bytes), no padding (alphabet A-Z a-z 0-9 - _)
--   byte 1   code version            (1)
--   byte 2   client                  0 other, 1 WoW: Forever, 2 TBC Anniversary
--   byte 3   is a shaman             0 / 1
--   byte 4   spec                    0 unknown, 1 Restoration, 2 Enhancement, 3 Elemental
--   byte 5   level bucket            floor(level / 10)  (0..6)
--   byte 6   setup path              see SETUP_PATHS (index, 0 = unknown)
--   byte 7   totem bar style         see STYLES (index, 0 = unknown)
--   byte 8   feature count N         (how many bits follow; old codes decode with
--                                     the first N entries of SP.SHARE_FEATURES)
--   byte 9+  feature bits            feature i is bit ((i-1) % 8) of byte
--                                     9 + floor((i-1) / 8), least significant first
-- SP.SHARE_FEATURES is APPEND-ONLY: never reorder or remove an entry, or old
-- codes decode wrong. tools/share-code-features.json mirrors it for the decoder.
-- ============================================================================

local SP = ShamanPower
if not SP then return end

local CODE_VERSION = 1

SP.SHARE_CLIENTS = { "WoW: Forever", "TBC Anniversary" }                               -- 1, 2
SP.SHARE_SPECS = { "Restoration", "Enhancement", "Elemental" }                          -- 1..3
SP.SHARE_SETUP_PATHS = { "tour", "quick", "skipped", "declined", "windfury" }           -- 1..5
SP.SHARE_STYLES = { "normal", "totemtimers", "dynamic", "compact", "grid", "blizzard" }  -- 1..6

-- ---------------------------------------------------------------------------
-- Safe readers: a missing table or module is simply "off".
-- ---------------------------------------------------------------------------
local function O() return SP.opt or {} end
local function sub(t, k) return type(t) == "table" and t[k] or nil end
local function G(name) return rawget(_G, name) end
local function on(v) return v == true end
local function notOff(v) return v ~= nil and v ~= false end   -- "on unless switched off", set tables only
local function anyTrue(t)
	if type(t) ~= "table" then return false end
	for _, v in pairs(t) do if v then return true end end
	return false
end

-- APPEND-ONLY. { key, label, get }
SP.SHARE_FEATURES = {
	-- Bars
	{ key = "cooldownBar",        label = "Cooldown bar shown",                 get = function() return on(O().showCooldownBar) end },
	{ key = "loadoutBar",         label = "Loadout bar shown",                  get = function() return on(O().showLoadoutBar) end },
	{ key = "flyouts",            label = "Totem flyouts on",                   get = function() return on(O().showTotemFlyouts) end },
	{ key = "twisting",           label = "Totem twisting on",                  get = function() return on(O().enableTotemTwisting) end },
	{ key = "hideOutOfCombat",    label = "Hide totem bar out of combat",       get = function() return on(O().hideOutOfCombat) end },
	{ key = "hideWhenNoTotems",   label = "Hide totem bar with no totems down", get = function() return on(O().hideWhenNoTotems) end },
	{ key = "fadeInsteadOfHide",  label = "Fade instead of hide",               get = function() return on(O().fadeInsteadOfHide) end },
	{ key = "showWithTarget",     label = "Show bar when targeting",            get = function() return on(O().showWithTarget) end },
	{ key = "hideTotemBarFrame",  label = "Totem bar frame hidden",             get = function() return on(O().hideTotemBarFrame) end },
	{ key = "fullOpacityPlaced",  label = "Full opacity when totem placed",     get = function() return on(O().totemBarFullOpacityWhenActive) end },
	{ key = "keybindsShown",      label = "Keybinds shown on buttons",          get = function() return on(O().showButtonKeybinds) end },
	{ key = "rightClickDestroy",  label = "Right-click destroys a totem",       get = function() return on(O().rightClickDestroysTotem) end },
	{ key = "hideBlizzardBar",    label = "Hide Blizzard's totem bar",          get = function() return O().hideBlizzardTotemBar ~= false end },
	{ key = "gridSplit",          label = "Grid split by element",              get = function() return on(O().gridSplit) end },
	{ key = "gridDropAssigns",    label = "Grid left-click also assigns",       get = function() return O().gridDropAssigns ~= false end },
	{ key = "manaTint",           label = "Mana tint",                          get = function() return on(O().manaTint) end },
	{ key = "customFont",         label = "Custom font chosen",                 get = function() return O().fontName ~= nil or anyTrue(O().fontAreas) end },
	{ key = "customOutline",      label = "Custom outline chosen",              get = function() return O().fontOutline ~= nil end },
	{ key = "customTexture",      label = "Custom bar texture chosen",          get = function() return O().barTexture ~= nil or anyTrue(O().barTextureAreas) end },
	{ key = "compactTexture",     label = "Compact line texture set",           get = function() return O().compactLineTexture ~= nil end },
	{ key = "popOuts",            label = "Pop-out trackers in use",            get = function() return anyTrue(O().poppedOut) end },
	{ key = "totemicCallOnBar",   label = "Totemic Call on the totem bar",      get = function() return on(O().totemicCallOnTotemBar) end },
	{ key = "twistSound",         label = "Twist sound",                        get = function() return on(O().twistSoundEnabled) end },
	{ key = "keybindsFlyoutKeys", label = "Flyouts open from bar keys",         get = function() return on(O().flyoutRouteBarKeys) end },
	-- Modules
	{ key = "esTracker",          label = "Earth Shield tracker",               get = function() return on(sub(O().esTracker, "enabled")) end },
	{ key = "shieldChargesSelf",  label = "Shield charges (own shield)",        get = function() return on(sub(O().shieldChargeDisplay, "showPlayerShield")) end },
	{ key = "shieldChargesES",    label = "Shield charges (Earth Shield)",      get = function() return on(sub(O().shieldChargeDisplay, "showEarthShield")) end },
	{ key = "reactive",           label = "Reactive totems",                    get = function() return on(sub(G("ShamanPower_ReactiveTotems"), "enabled")) end },
	{ key = "readyReminders",     label = "Ready reminders",                    get = function() return on(sub(G("ShamanPower_ReadyReminders"), "enabled")) end },
	{ key = "expiring",           label = "Expiring alerts",                    get = function() return on(sub(G("ShamanPowerExpiringAlertsDB"), "enabled")) end },
	{ key = "expiringShields",    label = "Expiring alerts: shields",           get = function() return on(sub(sub(G("ShamanPowerExpiringAlertsDB"), "shields"), "enabled")) end },
	{ key = "expiringTotems",     label = "Expiring alerts: totems",            get = function() return on(sub(sub(G("ShamanPowerExpiringAlertsDB"), "totems"), "enabled")) end },
	{ key = "expiringImbues",     label = "Expiring alerts: weapon imbues",     get = function() return on(sub(sub(G("ShamanPowerExpiringAlertsDB"), "weaponImbues"), "enabled")) end },
	{ key = "totemDestroyed",     label = "Totem destroyed alert",              get = function() return notOff(sub(sub(G("ShamanPowerExpiringAlertsDB"), "totems"), "destroyed")) end },
	{ key = "destroyedChat",      label = "Destroyed: chat line",               get = function() return notOff(sub(sub(G("ShamanPowerExpiringAlertsDB"), "totems"), "destroyedChat")) end },
	{ key = "destroyedCenter",    label = "Destroyed: big text",                get = function() return on(sub(sub(G("ShamanPowerExpiringAlertsDB"), "totems"), "destroyedCenter")) end },
	{ key = "destroyedParty",     label = "Destroyed: group chat",              get = function() return on(sub(sub(G("ShamanPowerExpiringAlertsDB"), "totems"), "destroyedParty")) end },
	{ key = "totemExpired",       label = "Totem expired alert",                get = function() return on(sub(sub(G("ShamanPowerExpiringAlertsDB"), "totems"), "expired")) end },
	{ key = "tremor",             label = "Tremor reminder",                    get = function() return on(sub(G("ShamanPowerTremorReminderDB"), "enabled")) end },
	{ key = "partyDots",          label = "Party buff dots",                    get = function() return on(O().showPartyRangeDots) end },
	{ key = "rangeCounters",      label = "Party range counters",               get = function() return on(sub(O().rangeCounter, "enabled")) end },
	{ key = "coverage",           label = "Totem coverage",                     get = function() return on(sub(O().coverage, "enabled")) end },
	{ key = "totemPlates",        label = "Totem plates",                       get = function() return on(sub(O().totemPlates, "enabled")) end },
	{ key = "rangeOverlay",       label = "Totem range overlay shown",          get = function() return on(sub(G("ShamanPower_RangeTracker"), "shown")) end },
	{ key = "minimapMarkers",     label = "Minimap totem markers",              get = function() return SP.MinimapTotemsAvailable == true and O().minimapTotemMarkers ~= false end },
	{ key = "raidCDSound",        label = "Raid cooldown call sound",           get = function() return O().raidCDPlaySound ~= false end },
	{ key = "raidCDFrame",        label = "Raid cooldown caller frame shown",   get = function() return not on(O().raidCDButtonHideFrame) end },
	{ key = "readyCheck",         label = "Ready check sweep",                  get = function()
		local c = O().readyCheck
		if type(c) == "table" and c.enabled ~= nil then return c.enabled == true end
		return WOW_PROJECT_ID == WOW_PROJECT_MAINLINE    -- its default: on for Forever, off elsewhere
	end },
	{ key = "announceUse",        label = "Announce: cooldown used",            get = function() return on(sub(O().announce, "announceUse")) end },
	{ key = "announceSoon",       label = "Announce: ready soon",               get = function() return on(sub(O().announce, "announceSoon")) end },
	{ key = "announceReply",      label = "Announce: tide auto-reply",          get = function() return on(sub(O().announce, "reply")) end },
	{ key = "announceLocalCall",  label = "Announce: local Mana Tide call",     get = function() return on(sub(O().announce, "localCall")) end },
	{ key = "loadoutAutoSwitch",  label = "Loadout auto-switch",                get = function() return on(sub(O().loadoutRules, "enabled")) end },
	{ key = "trainerReminder",    label = "Trainer reminder",                   get = function()
		if WOW_PROJECT_ID ~= WOW_PROJECT_MAINLINE then return false end
		local t = O().trainerReminder
		return not (type(t) == "table" and t.enabled == false)
	end },
	{ key = "windfuryOnly",       label = "Windfury-only mode (non-shaman)",    get = function() return on(O().windfuryOnly) end },
	{ key = "hasLoadouts",        label = "Has saved loadouts",                 get = function() local l = G("ShamanPower_TotemLoadouts"); return type(l) == "table" and #l > 0 end },
	{ key = "enabled",            label = "ShamanPower enabled",                get = function() return O().enabled ~= false end },
	{ key = "minimapIcon",        label = "Minimap icon shown",                 get = function() return sub(O().minimap, "show") ~= false end },
	{ key = "readyCheckList",     label = "Ready check: on-screen list",        get = function() return sub(O().readyCheck, "showPanel") ~= false end },
	{ key = "readyRemindersAlways", label = "Ready reminders: always shown (dim on cooldown)", get = function()
		local m = sub(G("ShamanPower_ReadyReminders"), "mode"); return m ~= nil and m ~= "ready"
	end },
	{ key = "coverageFreeCells",  label = "Coverage: one box per totem",        get = function() return on(sub(O().coverage, "freeCells")) end },
}

-- ---------------------------------------------------------------------------
local function indexOf(list, value)
	for i, v in ipairs(list) do if v == value then return i end end
	return 0
end

local function specIndex()
	local role = SP.Wizard and SP.Wizard.DetectSpec and SP.Wizard.DetectSpec()
	if not role and select(2, UnitClass("player")) == "SHAMAN" and GetNumTalentTabs and GetTalentTabInfo then
		-- the same talent-tab count the setup's detection uses (Config may not be loaded)
		local tabs, best, bestPts, second = { "elemental", "enhancement", "restoration" }, nil, 0, 0
		for i = 1, math.min(GetNumTalentTabs() or 0, 3) do
			local r = { pcall(GetTalentTabInfo, i) }
			local pts = r[1] and ((type(r[2]) == "number") and r[6] or r[4]) or nil
			if type(pts) == "number" and not (issecretvalue and issecretvalue(pts)) then
				if pts > bestPts then second = bestPts; best, bestPts = tabs[i], pts elseif pts > second then second = pts end
			end
		end
		if best and bestPts > second then role = best end
	end
	-- the talents cannot tell (below level 10, a tie, no readable points): the spec picked in the setup
	if not role then role = sub(sub(SP.db, "char"), "setupRole") end
	if role == "restoration" then return 1 elseif role == "enhancement" then return 2 elseif role == "elemental" then return 3 end
	return 0
end

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
local function base64url(bytes)
	local out, n = {}, #bytes
	for i = 1, n, 3 do
		local a, b, c = bytes[i], bytes[i + 1] or 0, bytes[i + 2] or 0
		local v = a * 65536 + b * 256 + c
		local c1 = math.floor(v / 262144) % 64
		local c2 = math.floor(v / 4096) % 64
		local c3 = math.floor(v / 64) % 64
		local c4 = v % 64
		out[#out + 1] = B64:sub(c1 + 1, c1 + 1) .. B64:sub(c2 + 1, c2 + 1)
		if i + 1 <= n then out[#out + 1] = B64:sub(c3 + 1, c3 + 1) end
		if i + 2 <= n then out[#out + 1] = B64:sub(c4 + 1, c4 + 1) end
	end
	return table.concat(out)
end

function SP:BuildShareCode()
	local client = 0
	if WOW_PROJECT_ID == WOW_PROJECT_MAINLINE then client = 1 elseif WOW_PROJECT_ID ~= nil then client = 2 end
	local isShaman = select(2, UnitClass("player")) == "SHAMAN"
	local okStyle, style = pcall(function() return SP.GetTotemBarStyle and SP:GetTotemBarStyle() end)
	local path = self.opt and self.opt.setupPath
	-- the tour's Finish page offers the code before its Finish button records "tour"
	local tour = rawget(_G, "ShamanPowerWizard")
	if tour and tour:IsShown() then path = "tour" end
	local bytes = {
		CODE_VERSION,
		client,
		isShaman and 1 or 0,
		isShaman and specIndex() or 0,
		math.min(255, math.floor((UnitLevel("player") or 0) / 10)),
		indexOf(SP.SHARE_SETUP_PATHS, path),
		isShaman and okStyle and indexOf(SP.SHARE_STYLES, style) or 0,
		#SP.SHARE_FEATURES,
	}
	local acc, bit = 0, 0
	for i, f in ipairs(SP.SHARE_FEATURES) do
		local ok, v = pcall(f.get)
		if ok and v then acc = acc + 2 ^ bit end
		bit = bit + 1
		if bit == 8 or i == #SP.SHARE_FEATURES then
			bytes[#bytes + 1] = acc
			acc, bit = 0, 0
		end
	end
	return "SPS1:" .. base64url(bytes)
end

-- ---------------------------------------------------------------------------
-- The copy box. WoW cannot write the clipboard, so the code sits selected in a
-- box: Ctrl+C copies it. Typing in the box changes nothing. ShamanPower's own
-- dialog (ShamanPowerDialog.lua) opens above the setup tour, whose Finish page
-- has the button.
-- ---------------------------------------------------------------------------
function SP:ShowShareCode()
	local ok, code = pcall(self.BuildShareCode, self)
	if not ok then
		print("|cff0070ddShamanPower|r: could not build the setup code (" .. tostring(code) .. ").")
		return
	end
	self:ShowSPDialog({
		key = "sharecode",
		title = "Your ShamanPower setup code",
		text = "Press |cffFFD100Ctrl+C|r, then paste it in #setup-stats on the ShamanPower Discord (discord.gg/eCtNeBqE8U). It lists which features you use - nothing personal.",
		editText = code,
	})
end

-- General > Main: the button, for every class, right after the Discord section
do
	local main = SP.options and SP.options.args and SP.options.args.settings
		and SP.options.args.settings.args.settings_show and SP.options.args.settings.args.settings_show.args
	if main then
		main.share_setup = {
			order = 91, type = "execute", name = "Share My Setup (for the developer)", width = "full",
			desc = "Makes a short code listing which ShamanPower features you use (nothing personal: no name, realm or guild). Paste it in #setup-stats on the ShamanPower Discord so the developer can see what people use most. Also: /sp share",
			func = function() SP:ShowShareCode() end,
		}
	end
end
