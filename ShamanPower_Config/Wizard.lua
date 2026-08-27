-- ShamanPower_Config :: Wizard
-- First-time setup. A large, self-contained screen: pick your spec, then walk
-- the features that matter to it, each showing its REAL frame live inside the
-- wizard (via ShamanPowerPreview) with sample data. Ends in a forced reload so
-- everything is rebuilt cleanly from the profile.

local ADDON, ns = ...
local Core = ns.Core
local SP = ShamanPower
-- Mocks read options through OPT() so the Quick Setup preview can point them
-- at a decoded preset profile instead of the live one.
local function OPT() return SP.Wizard.optOverride or SP.opt end
if not SP or not Core then return end

-- Preferred size; Build() shrinks it to fit small screens.
local WIZ_W, WIZ_H = 1180, 760
local RAIL_W = 210
local HEADER_H = 64
local FOOTER_H = 56

SP.Wizard = SP.Wizard or {}
local wiz            -- the frame
local state = { role = nil, step = 1, steps = {} }
local RenderStep   -- defined further down; forward-declared so earlier code (positioning) can call it

-- ---------------------------------------------------------------------------
-- Enable bindings: get/set for each feature's on/off, reused from the options.
-- ---------------------------------------------------------------------------
local function notify()
	local reg = LibStub and LibStub("AceConfigRegistry-3.0", true)
	if reg then reg:NotifyChange("ShamanPower") end
end
local function safecall(fn) if SP[fn] then pcall(SP[fn], SP) end end

local BIND = {
	estracker = {
		get = function() return SP.opt.esTracker and SP.opt.esTracker.enabled end,
		set = function(v) SP.opt.esTracker = SP.opt.esTracker or {}; SP.opt.esTracker.enabled = v; safecall("UpdateESTracker"); notify() end,
	},
	playershield = {
		get = function() return SP.opt.shieldChargeDisplay and SP.opt.shieldChargeDisplay.showPlayerShield ~= false end,
		set = function(v) SP.opt.shieldChargeDisplay = SP.opt.shieldChargeDisplay or {}; SP.opt.shieldChargeDisplay.showPlayerShield = v; safecall("UpdateShieldChargeDisplays"); notify()
			if SP.shieldChargesDemoActive then SP:ShieldChargesDemo(true) end; if SP.Wizard._shieldFit then SP.Wizard._shieldFit() end end,
	},
	earthshieldcharge = {
		get = function() return SP.opt.shieldChargeDisplay and SP.opt.shieldChargeDisplay.showEarthShield ~= false end,
		set = function(v) SP.opt.shieldChargeDisplay = SP.opt.shieldChargeDisplay or {}; SP.opt.shieldChargeDisplay.showEarthShield = v; safecall("UpdateShieldChargeDisplays"); notify()
			if SP.shieldChargesDemoActive then SP:ShieldChargesDemo(true) end; if SP.Wizard._shieldFit then SP.Wizard._shieldFit() end end,
	},
	twisting = {
		get = function() return SP.opt.enableTotemTwisting end,
		set = function(v)
			SP.opt.enableTotemTwisting = v
			if SP.SendMessage and SP.player then pcall(SP.SendMessage, SP, "TWIST " .. SP.player .. " " .. (v and "1" or "0")) end
			safecall("UpdateMiniTotemBar"); safecall("UpdateSPMacros")
			if v then safecall("SetupTwistTimer") else safecall("HideTwistTimer") end
			notify()
			if ns.Widgets and SP.Wizard._twistCard then ns.Widgets:RefreshAll(SP.Wizard._twistCard) end
		end,
	},
	reactive = {
		get = function() return ShamanPower_ReactiveTotems and ShamanPower_ReactiveTotems.enabled ~= false end,
		set = function(v) ShamanPower_ReactiveTotems = ShamanPower_ReactiveTotems or {}; ShamanPower_ReactiveTotems.enabled = v; safecall("UpdateReactiveTotems"); notify()
			if ns.Widgets and SP.Wizard._reactiveCard then ns.Widgets:RefreshAll(SP.Wizard._reactiveCard) end end,
	},
	tremor = {
		get = function() return ShamanPowerTremorReminderDB and ShamanPowerTremorReminderDB.enabled ~= false end,
		set = function(v) ShamanPowerTremorReminderDB = ShamanPowerTremorReminderDB or {}; ShamanPowerTremorReminderDB.enabled = v; safecall("UpdateTremorReminderAppearance"); notify()
			if ns.Widgets and SP.Wizard._tremorCard then ns.Widgets:RefreshAll(SP.Wizard._tremorCard) end end,
	},
	expiring = {
		get = function() return ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.enabled ~= false end,
		set = function(v) ShamanPowerExpiringAlertsDB = ShamanPowerExpiringAlertsDB or {}; ShamanPowerExpiringAlertsDB.enabled = v; notify()
			if ns.Widgets and SP.Wizard._expiringCard then ns.Widgets:RefreshAll(SP.Wizard._expiringCard) end end,
	},
	partybuff = {
		get = function() return SP.opt.rangeCounter and SP.opt.rangeCounter.enabled end,
		set = function(v) SP.opt.rangeCounter = SP.opt.rangeCounter or {}; SP.opt.rangeCounter.enabled = v; safecall("UpdatePartyRangeDots"); notify() end,
	},
	totemplates = {
		get = function() return SP.opt.totemPlates and SP.opt.totemPlates.enabled end,
		set = function(v) SP:EnsureProfileTable("totemPlates"); SP.opt.totemPlates.enabled = v; safecall("ToggleTotemPlates"); notify()
			if SP.totemPlatesDemoActive then SP:TotemPlatesDemo(true) end
			if ns.Widgets and SP.Wizard._platesCard then ns.Widgets:RefreshAll(SP.Wizard._platesCard) end end,
	},
	totembar = {
		get = function() return SP.opt.miniBar and SP.opt.miniBar.autobutton and true or false end,
		set = function(v)
			SP:EnsureProfileTable("miniBar"); SP.opt.miniBar.autobutton = v
			if not v and SP.opt.cooldownBarLocked then SP.opt.cooldownBarLocked = nil; safecall("UpdateCooldownBarPosition") end
			safecall("UpdateLayout"); safecall("UpdateRoster"); notify()
		end,
	},
	cdprogress = {
		get = function() return SP.opt.cdbarShowProgressBars ~= false end,
		set = function(v) SP.opt.cdbarShowProgressBars = v; safecall("UpdateCooldownBarProgressBars"); safecall("UpdateCooldownBar"); notify() end,
	},
	cdsweep = {
		get = function() return SP.opt.cdbarShowColorSweep ~= false end,
		set = function(v) SP.opt.cdbarShowColorSweep = v; safecall("UpdateCooldownBar"); notify() end,
	},
	cdtext = {
		get = function() return SP.opt.cdbarShowCDText ~= false end,
		set = function(v) SP.opt.cdbarShowCDText = v; safecall("UpdateCooldownBar"); notify() end,
	},
}

-- Switch the totem bar layout the way the options page does: keep the bar's
-- on-screen position, and do not touch it in combat.
local function SetTotemBarLayout(val)
	if InCombatLockdown() then return end
	if SP.opt.cdbarLayout == nil then SP.opt.cdbarLayout = SP.opt.layout end
	local autoBtn = SP.autoButton
	local ox, oy
	if autoBtn and autoBtn:IsShown() then ox, oy = autoBtn:GetCenter() end
	SP.opt.layout = val
	safecall("UpdateLayout"); safecall("UpdateRoster")
	if ox and oy and autoBtn and SP.Header then
		local nx, ny = autoBtn:GetCenter()
		local frame = _G["ShamanPowerFrame"]
		if nx and ny and frame then
			local point, rel, relPoint, x, y = frame:GetPoint()
			if point and x and y then
				frame:ClearAllPoints(); frame:SetPoint(point, rel, relPoint, x + (ox - nx), y + (oy - ny))
				if SP.SaveFramePosition then pcall(SP.SaveFramePosition, SP, frame) end
			end
		end
	end
	safecall("UpdateCooldownBar")
end
local LAYOUT_VALUES = function() return { Horizontal = "Horizontal", Vertical = "Vertical (flyouts right)", VerticalLeft = "Vertical (flyouts left)" } end
local LAYOUT_ORDER  = function() return { "Horizontal", "Vertical", "VerticalLeft" } end

-- ---------------------------------------------------------------------------
-- Per-spec defaults, applied the moment a spec is picked. Everything here can
-- still be changed on the steps that follow; this only sets the starting point.
-- ---------------------------------------------------------------------------
function SP.Wizard.ApplyRoleDefaults(role)
	local resto, enh, ele = role == "restoration", role == "enhancement", role == "elemental"
	-- Earth Shield is Resto-only: tracker and the Earth Shield charge number.
	SP:EnsureProfileTable("esTracker");           SP.opt.esTracker.enabled = resto
	SP:EnsureProfileTable("shieldChargeDisplay"); SP.opt.shieldChargeDisplay.showPlayerShield = true
	SP.opt.shieldChargeDisplay.showEarthShield = resto
	-- Twisting: on by default for Enhancement only.
	if SP.opt.enableTotemTwisting ~= enh then
		SP.opt.enableTotemTwisting = enh
		if SP.SendMessage and SP.player then pcall(SP.SendMessage, SP, "TWIST " .. SP.player .. " " .. (enh and "1" or "0")) end
		safecall("UpdateMiniTotemBar"); safecall("UpdateSPMacros")
		if enh then safecall("SetupTwistTimer") else safecall("HideTwistTimer") end
	end
	-- Cooldown bar: spec talents only where they exist (the bar also hides unknown spells).
	SP.opt.cdbarShowNS = resto; SP.opt.cdbarShowManaTide = resto
	SP.opt.cdbarShowShamanisticRage = enh
	SP.opt.cdbarShowElementalMastery = ele
	-- Clean look by default: no black panel / border behind any frame. Each
	-- step still has a "Show frame" / "Show border" toggle to bring it back.
	SP.opt.hideTotemBarFrame = true;                 safecall("UpdateTotemBarFrame")
	SP.opt.hideCooldownBarFrame = true;              safecall("UpdateCooldownBarFrame")
	SP.opt.raidCDButtonHideFrame = true;             safecall("UpdateCallerButtonFrameStyle")
	SP.opt.esTracker.hideBorder = true;              safecall("UpdateESTrackerBorder")
	SP:EnsureProfileTable("rangeTracker");           SP.opt.rangeTracker.hideBorder = true; safecall("UpdateSPRangeBorder")
	SP.opt.rangeCounter = SP.opt.rangeCounter or {}; SP.opt.rangeCounter.hideFrame = true; safecall("UpdateRangeCounterFrameStyle")
	ShamanPower_ReactiveTotems = ShamanPower_ReactiveTotems or {}
	ShamanPower_ReactiveTotems.hideBackground = true; safecall("UpdateReactiveTotemAppearance")
	safecall("UpdateESTracker"); safecall("UpdateShieldChargeDisplays")
	if not InCombatLockdown() then safecall("RecreateCooldownBar") end
	notify()
end

-- ---------------------------------------------------------------------------
-- Steps. roles = which specs see the step. previewKey = which module frame to
-- borrow into the preview panel (nil = a drawn mock or none).
-- ---------------------------------------------------------------------------
local ALL = { restoration = true, enhancement = true, elemental = true }

local STEPS = {
	{ id = "totembar", title = "Totem Bar", roles = ALL, build = "BuildTotemBarStep",
	  desc = "Your totem bar can show totems three ways. Click a style and watch the preview drop, run down and expire.",
	  bullets = {
	    "Normal: assigned totems stay put; a different dropped totem pops up above its slot.",
	    "TotemTimers style: the dropped totem becomes the big icon, assigned shrinks to the corner.",
	    "Dynamic: the bar is simply whatever you last dropped. Great for PvP.",
	    "Hover any totem for its flyout: left-click drops that totem, right-click makes it the assigned one.",
	  },
	  toggles = { { label = "Show the totem bar", bind = "totembar" } } },
	{ id = "assign", title = "Assignments", roles = ALL, build = "BuildAssignStep",
	  desc = "The assignments window: every shaman in your group who runs ShamanPower, side by side, with the totem each one should drop for Earth, Fire, Water and Air.",
	  bullets = {
	    "Your row is always yours to set. The raid leader or an assistant can set everyone's - or a shaman can allow it with Free Assign.",
	    "Left-click a cell (or wheel) for the next totem, right-click for the previous. Twisting and the Earth Shield target are here too.",
	    "Open it any time with /sp totems, the minimap icon, or the totem bar's handle.",
	  } },
	{ id = "durationbars", title = "Duration Bars", roles = ALL, build = "BuildDurationBarsStep",
	  desc = "How each totem shows its remaining time, cooldown and pulse timer.",
	  bullets = {
	    "Every control here is live - the preview redraws as you change it.",
	  } },
	{ id = "cooldownbar", title = "Cooldown Bar", roles = ALL, build = "BuildCooldownBarStep",
	  desc = "A separate bar that tracks your big cooldowns so you never lose one in a crowded action bar.",
	  bullets = {
	    "Each button shows a cooldown sweep, a colored progress bar and the time left.",
	    "Your shield shows its charges; Ankh shows how many you carry.",
	    "Choose which spells appear below - the preview updates as you click.",
	  },
	  toggles = {
	    { label = "Progress bars",      bind = "cdprogress" },
	    { label = "Cooldown sweep",     bind = "cdsweep" },
	    { label = "Time remaining text", bind = "cdtext" },
	  } },
	{ id = "estracker", title = "Earth Shield Tracker", roles = { restoration = true }, build = "BuildESTrackerStep",
	  desc = "Every Earth Shield in your raid - not just yours - with who it is on, who cast it, and how many charges are left.",
	  bullets = {
	    "One icon per shield: target name inside, charges top-right, caster below in class color.",
	    "A shield vanishes the moment it drops off, so you can see who needs one back.",
	    "Grows and shrinks with the raid; drag it anywhere once setup is done.",
	  },
	  toggles = { { label = "Enable Earth Shield Tracker", bind = "estracker" } } },
	{ id = "shieldcharges", title = "Shield Charges", roles = ALL, build = "BuildShieldChargesStep",
	  desc = "Large on-screen numbers for your shield charges, so you re-apply before they run out.",
	  bullets = {
	    "Your Lightning / Water Shield charges - useful to every shaman.",
	    { "Earth Shield charges on your target - for Resto healing a tank.", roles = { restoration = true } },
	    "Numbers turn yellow, then red, as charges drop.",
	  },
	  toggles = {
	    { label = "Player Shield charges", bind = "playershield" },
	    { label = "Earth Shield charges", bind = "earthshieldcharge", roles = { restoration = true } },
	  } },
	{ id = "twisting", title = "Totem Twisting", roles = ALL, build = "BuildTwistingStep",
	  desc = "Keep the Windfury buff on your melee all the time by alternating Windfury with a second air totem.",
	  bullets = {
	    "Drop Windfury, then your twist totem; the Air slot shows what to cast next.",
	    "A countdown on the icon shows how long the Windfury buff has left - white, then yellow, then red.",
	    "Optional sound when it is time to re-drop Windfury. On by default for Enhancement.",
	  },
	  toggles = { { label = "Enable Totem Twisting", bind = "twisting" } } },
	{ id = "raidcd", title = "Raid Cooldowns", roles = ALL, build = "BuildRaidCDStep",
	  desc = "One-press callers for Bloodlust / Heroism, Mana Tide and Drums of Battle - the whole raid is told, and the assigned player gets an alert they cannot miss.",
	  bullets = {
	    "Assign who does what in Settings > Raid Cooldowns (raid leader or assistant).",
	    "Callers appear only for people allowed to call; you can give control to anyone.",
	    "Try it: press a button in the preview to see what the assigned player sees.",
	  } },
	{ id = "reactive", title = "Reactive Totems", roles = ALL, build = "BuildReactiveStep",
	  desc = "Big on-screen alerts the instant someone in your group gets feared, poisoned or diseased - telling you which totem fixes it.",
	  bullets = {
	    "Tremor for fear and charm, Poison Cleansing for poison, Disease Cleansing for disease.",
	    "Shows who has it and what it is; goes away when it is cleared or the totem is already down.",
	    "Each alert can be dragged to its own spot later.",
	  },
	  toggles = { { label = "Enable Reactive Totems", bind = "reactive" } } },
	{ id = "tremor", title = "Tremor Reminder", roles = ALL, build = "BuildTremorStep",
	  desc = "A heads-up to drop Tremor Totem the moment you target a mob that is known to fear - before anyone in your group gets feared.",
	  bullets = {
	    "Built-in list of hundreds of fear-casting dungeon and raid mobs; add your own.",
	    "Goes away as soon as your Tremor Totem is down.",
	    "Icon, text or both, with an optional glow and sound.",
	  },
	  toggles = { { label = "Enable Tremor Reminder", bind = "tremor" } } },
	{ id = "expiring", title = "Expiring Alerts", roles = ALL, build = "BuildExpiringStep",
	  desc = "Scrolling-combat-text style alerts the moment a shield runs out, a totem dies or times out, or a weapon imbue fades.",
	  bullets = {
	    "Lightning / Water Shield, Earth Shield on your target, totems destroyed or expired, main- and off-hand imbues.",
	    "Pick the look and animation; turn on a sound per category.",
	  },
	  toggles = { { label = "Enable Expiring Alerts", bind = "expiring" } } },
	{ id = "partybuff", title = "Party Buff Tracker", roles = ALL, build = "BuildPartyBuffStep",
	  desc = "Shows, right on your totem bar, which party members your totems are actually reaching.",
	  bullets = {
	    "A corner dot per party member - class color when your totem buff is on them, red when they are out of range.",
	    "Or a number: how many of them the totem reaches. Or both.",
	    "This is about YOUR totems. Totem Range (later) is about other shamans' totems reaching you.",
	  } },
	{ id = "wfcompanion", title = "Windfury Companion", roles = ALL, build = "BuildWFCompanionStep",
	  desc = "The game never shows Windfury Totem's weapon buff on other players, so ShamanPower cannot see who has it. A tiny WeakAura on your melee fixes that.",
	  bullets = {
	    "Melee who run it quietly tell your addon they have Windfury.",
	    "Your Air slot then counts them and shows whether each is in range.",
	  } },
	{ id = "range", title = "Totem Range", roles = ALL, build = "BuildRangeStep",
	  desc = "Are you standing in range of the OTHER shamans' totems? A small overlay that goes green, red or gray per totem.",
	  bullets = {
	    "Tracks the totems you pick: green in range, red out of range, gray when nobody has it down.",
	    "Shows up automatically whenever there is a shaman in your group.",
	    "The opposite of Party Buff Tracker, which is about YOUR totems reaching THEM.",
	  } },
	{ id = "totemplates", title = "Totem Plates", roles = ALL, build = "BuildTotemPlatesStep",
	  desc = "Replaces the tiny nameplate on every totem with a big icon, so you can see exactly which totem that is - and kill the right one.",
	  bullets = {
	    "Red border for enemy totems, green for friendly. Optional name under the icon.",
	    "Pulsing totems get a countdown to their next tick: text, bar, or swipe.",
	    "|cffFFB000Friendly totems do NOT show inside dungeons or raids|r (the game hides those nameplates there). Enemy totems work everywhere.",
	  },
	  toggles = { { label = "Enable Totem Plates", bind = "totemplates" } } },
	{ id = "position", title = "Position", roles = ALL, build = "BuildPositionStep",
	  desc = "Move your bars and frames wherever you like.",
	  bullets = {
	    "Setup fills the whole screen, so we'll step aside while you drag.",
	    "Click below to unlock everything and position it.",
	    "You can always move things later from Settings.",
	  } },

}

local function VisibleSteps()
	local out = { { id = "role", title = "Your Spec" } }
	if not state.role then return out end
	for _, s in ipairs(STEPS) do
		if s.roles[state.role] then out[#out + 1] = s end
	end
	out[#out + 1] = { id = "finish", title = "Finish" }
	return out
end

-- ===========================================================================
-- Frame construction
-- ===========================================================================
local function Build()
	if wiz then return wiz end
	wiz = CreateFrame("Frame", "ShamanPowerWizard", UIParent)
	-- Use the room the screen gives us (wider card = readable option rows),
	-- but never larger than the screen itself.
	local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
	wiz:SetSize(math.max(900, math.min(WIZ_W, sw - 60)), math.max(600, math.min(WIZ_H, sh - 60)))
	wiz:SetPoint("CENTER")
	wiz:SetFrameStrata("FULLSCREEN_DIALOG")
	-- Not toplevel: the config kit's dropdown popup (level 20) and its
	-- click-away catcher (level 10) must stay above this frame.
	wiz:SetFrameLevel(1)
	wiz:EnableMouse(true)
	wiz:Hide()
	Core:SolidTex(wiz, "windowBg", "BACKGROUND")
	Core:MakeBorder(wiz, "accent", 2)

	-- Dim the world behind it.
	local shade = CreateFrame("Frame", nil, wiz)
	shade:SetPoint("TOPLEFT", UIParent); shade:SetPoint("BOTTOMRIGHT", UIParent)
	shade:SetFrameStrata("FULLSCREEN")
	local st = shade:CreateTexture(nil, "BACKGROUND"); st:SetAllPoints(shade); st:SetColorTexture(0, 0, 0, 0.55)
	wiz.shade = shade

	-- Header
	local header = CreateFrame("Frame", nil, wiz)
	header:SetPoint("TOPLEFT", wiz, "TOPLEFT", 2, -2)
	header:SetPoint("TOPRIGHT", wiz, "TOPRIGHT", -2, -2)
	header:SetHeight(HEADER_H)
	Core:SolidTex(header, "sidebarBg", "BACKGROUND")
	local brand = header:CreateFontString(nil, "OVERLAY")
	brand:SetFontObject(Core.fonts.brand)
	brand:SetPoint("LEFT", header, "LEFT", 20, 10)
	brand:SetText("|cff0070ddShaman|r|cffE6EAF0Power|r Setup")
	local stepTitle = header:CreateFontString(nil, "OVERLAY")
	stepTitle:SetFontObject(Core.fonts.tiny)
	stepTitle:SetPoint("TOPLEFT", brand, "BOTTOMLEFT", 1, -3)
	wiz.stepTitle = stepTitle
	local glow = Core:AccentGlow(wiz, 2)
	glow:SetPoint("TOPLEFT", wiz, "TOPLEFT", 2, -(HEADER_H + 2))
	glow:SetPoint("TOPRIGHT", wiz, "TOPRIGHT", -2, -(HEADER_H + 2))

	-- Left rail (step list)
	local rail = CreateFrame("Frame", nil, wiz)
	rail:SetPoint("TOPLEFT", wiz, "TOPLEFT", 2, -(HEADER_H + 4))
	rail:SetPoint("BOTTOMLEFT", wiz, "BOTTOMLEFT", 2, FOOTER_H)
	rail:SetWidth(RAIL_W)
	Core:SolidTex(rail, "sidebarBg", "BACKGROUND")
	wiz.rail, wiz.railRows = rail, {}

	-- Content
	local content = CreateFrame("Frame", nil, wiz)
	content:SetPoint("TOPLEFT", rail, "TOPRIGHT", 0, 0)
	content:SetPoint("BOTTOMRIGHT", wiz, "BOTTOMRIGHT", -2, FOOTER_H)
	Core:SolidTex(content, "contentBg", "BACKGROUND")
	wiz.content = content

	-- Footer
	local footRule = wiz:CreateTexture(nil, "ARTWORK")
	footRule:SetHeight(1)
	footRule:SetPoint("BOTTOMLEFT", wiz, "BOTTOMLEFT", 2, FOOTER_H)
	footRule:SetPoint("BOTTOMRIGHT", wiz, "BOTTOMRIGHT", -2, FOOTER_H)
	footRule:SetColorTexture(Core:Color("border"))

	local back = Core:MakeButton(wiz, "Back", 90, false)
	back:SetPoint("BOTTOMLEFT", wiz, "BOTTOMLEFT", 16, 14)
	back:SetScript("OnClick", function() SP.Wizard:Go(state.step - 1) end)
	wiz.back = back

	local next = Core:MakeButton(wiz, "Next", 120, true)
	next:SetPoint("BOTTOMRIGHT", wiz, "BOTTOMRIGHT", -16, 14)
	next:SetScript("OnClick", function() SP.Wizard:NextOrFinish() end)
	wiz.next = next

	local skip = Core:MakeButton(wiz, "Skip Setup", 100, false)
	skip:SetPoint("BOTTOM", wiz, "BOTTOM", 0, 14)
	skip:SetScript("OnClick", function() SP.Wizard:Close(true) end)
	wiz.skip = skip

	wiz:SetScript("OnHide", function() SP:RestoreAllPreviews() end)
	return wiz
end

-- ===========================================================================
-- Rail + content rendering
-- ===========================================================================
local pageWidgets = {}
local function ClearContent()
	SP.Wizard._shieldFit = nil
	SP.Wizard._twistCard = nil
	SP.Wizard._reactiveCard = nil
	SP.Wizard._tremorCard = nil
	SP.Wizard._expiringCard = nil
	SP.Wizard._platesCard = nil
	SP:RestoreAllPreviews()
	if ns.Widgets then
		ns.Widgets:HidePopup()
		for _, w in ipairs(pageWidgets) do
			ns.Widgets:ReleaseAll(w)
			if w.body then ns.Widgets:ReleaseAll(w.body) end
		end
	end
	for _, w in ipairs(pageWidgets) do w:Hide(); w:SetParent(nil) end
	wipe(pageWidgets)
end
local function track(w) pageWidgets[#pageWidgets + 1] = w; return w end

local function RenderRail(steps)
	for _, r in ipairs(wiz.railRows) do r:Hide() end
	wipe(wiz.railRows)
	local y = 14
	for i, s in ipairs(steps) do
		local row = CreateFrame("Frame", nil, wiz.rail)
		row:SetSize(RAIL_W, 30)
		row:SetPoint("TOPLEFT", wiz.rail, "TOPLEFT", 0, -y)
		local on = (i == state.step)
		local done = (i < state.step)
		local acc = row:CreateTexture(nil, "ARTWORK"); acc:SetWidth(2)
		acc:SetPoint("TOPLEFT"); acc:SetPoint("BOTTOMLEFT")
		acc:SetColorTexture(Core:Color("accent")); acc:SetShown(on)
		local num = row:CreateFontString(nil, "OVERLAY")
		num:SetFontObject(Core.fonts.tiny)
		num:SetPoint("LEFT", row, "LEFT", 16, 0)
		num:SetText(done and "|TInterface\\RaidFrame\\ReadyCheck-Ready:14|t" or tostring(i))
		local t = row:CreateFontString(nil, "OVERLAY")
		t:SetFontObject(on and Core.fonts.navOn or Core.fonts.nav)
		t:SetPoint("LEFT", num, "RIGHT", 8, 0)
		t:SetText(s.title)
		if not on and not done then t:SetTextColor(Core:Color("textDim")) end
		wiz.railRows[#wiz.railRows + 1] = row
		y = y + 30
	end
end

-- A framed preview panel on the right of the content; returns the inner box.
-- A framed, CLIPPED preview panel on the right; nothing drawn inside can spill
-- outside the box. Returns the inner container to render into.
local function PreviewPanel(parent)
	local box = track(CreateFrame("Frame", nil, parent))
	box:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -26, -26)
	box:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -26, 26)
	box:SetWidth((parent:GetWidth() - 52) * 0.50)
	Core:SolidTex(box, "windowBg", "BACKGROUND")
	Core:MakeBorder(box, "border")
	local cap = track(box:CreateFontString(nil, "OVERLAY"))
	cap:SetFontObject(Core.fonts.tiny)
	cap:SetPoint("TOP", box, "TOP", 0, -9)
	cap:SetText("|cff5A6678LIVE PREVIEW|r")
	-- Inner clip region below the caption.
	local inner = track(CreateFrame("Frame", nil, box))
	inner:SetPoint("TOPLEFT", box, "TOPLEFT", 8, -26)
	inner:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -8, 8)
	inner:SetClipsChildren(true)
	box.inner = inner
	return box
end

-- A left card holding the step's title, description and controls, so controls
-- never float in empty space.
local function LeftCard(parent)
	local card = track(CreateFrame("Frame", nil, parent))
	card:SetPoint("TOPLEFT", parent, "TOPLEFT", 26, -26)
	card:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 26, 26)
	card:SetWidth((parent:GetWidth() - 52) * 0.46)
	Core:SolidTex(card, "rowBg", "BACKGROUND")
	Core:MakeBorder(card, "borderSoft")
	-- Scrollable body: steps with many controls scroll instead of overflowing.
	local scroll = CreateFrame("ScrollFrame", nil, card)
	scroll:SetPoint("TOPLEFT", card, "TOPLEFT", 0, -2)
	scroll:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -14, 2)
	local body = CreateFrame("Frame", nil, scroll)
	body:SetSize(card:GetWidth() - 14, 10)
	scroll:SetScrollChild(body)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local maxS = math.max(0, body:GetHeight() - self:GetHeight())
		self:SetVerticalScroll(math.max(0, math.min(maxS, self:GetVerticalScroll() - delta * 40)))
	end)
	Core:AttachScrollbar(scroll, body, { offset = -6 })
	card.scroll, card.body = scroll, body
	return card
end

-- Size the scroll body to its content (measured after layout settles).
local function FitCardBody(card, minH)
	local body, scroll = card.body, card.scroll
	local function measure()
		if not body:IsShown() or not body:GetTop() then return end
		local top, bottom = body:GetTop(), body:GetTop()
		local function take(r)
			if r and r.GetBottom and r:IsShown() then
				local b = r:GetBottom()
				if b and b < bottom then bottom = b end
			end
		end
		for _, c in ipairs({ body:GetChildren() }) do take(c) end
		for _, r in ipairs({ body:GetRegions() }) do take(r) end
		local h = math.max(minH or 0, (top - bottom) + 24, scroll:GetHeight())
		body:SetHeight(h)
	end
	C_Timer.After(0, measure); C_Timer.After(0.1, measure)
end

local function ToggleRow(parent, y, label, bind)
	local row = track(CreateFrame("Frame", nil, parent))
	row:SetSize(parent:GetWidth() - 36, 28)
	row:SetPoint("TOPLEFT", parent, "TOPLEFT", 18, -y)
	local tr = CreateFrame("Button", nil, row)
	tr:SetSize(38, 18); tr:SetPoint("LEFT", row, "LEFT", 0, 0)
	local tex = tr:CreateTexture(nil, "BACKGROUND"); tex:SetAllPoints(tr)
	Core:MakeBorder(tr, "border")
	local knob = tr:CreateTexture(nil, "OVERLAY"); knob:SetSize(12, 12); knob:SetColorTexture(0.95, 0.96, 0.98, 1)
	local b = BIND[bind]
	local function paint()
		local on = b and b.get()
		tex:SetColorTexture(Core:ColorIf(on, "accent", "off"))
		knob:ClearAllPoints(); knob:SetPoint(on and "RIGHT" or "LEFT", tr, on and "RIGHT" or "LEFT", on and -3 or 3, 0)
	end
	tr:SetScript("OnClick", function() if b then b.set(not b.get()); paint() end end)
	paint()
	local lbl = row:CreateFontString(nil, "OVERLAY")
	lbl:SetFontObject(Core.fonts.row); lbl:SetPoint("LEFT", tr, "RIGHT", 10, 0)
	lbl:SetText(label)
	return row
end

-- Shared: an icon row inside a preview container (for mock previews).
local function MockIconRow(inner, icons, labels, size, gap)
	size = size or 48; gap = gap or 8
	local n = #icons
	local row = CreateFrame("Frame", nil, inner)
	row:SetSize(n * size + (n - 1) * gap, size + 16)
	row:SetPoint("CENTER", inner, "CENTER", 0, 0)
	local made = {}
	for i = 1, n do
		local slot = CreateFrame("Frame", nil, row)
		slot:SetSize(size, size + 16)
		slot:SetPoint("LEFT", row, "LEFT", (i - 1) * (size + gap), 0)
		local ic = slot:CreateTexture(nil, "ARTWORK"); ic:SetSize(size, size); ic:SetPoint("TOP")
		ic:SetTexture(icons[i]); ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		Core:MakeBorder(slot, "border")
		if labels and labels[i] then
			local l = slot:CreateFontString(nil, "OVERLAY"); l:SetFontObject(Core.fonts.tiny)
			l:SetPoint("TOP", ic, "BOTTOM", 0, -3); l:SetText(labels[i]); l:SetTextColor(Core:Color("textDim"))
		end
		made[i] = slot
	end
	return row, made
end

function SP.Wizard.BuildTotemBarStep(card, inner, y)
	-- assigned = what is on the bar; active = a different totem you dropped.
	local ELE = {
		{ n = "Earth", r = 0.72, g = 0.52, b = 0.32, dur = 9,  gap = 2.5, off = 0.0,
		  icon = "Interface\\Icons\\Spell_Nature_EarthBindTotem", active = "Interface\\Icons\\Spell_Nature_StoneClawTotem" },
		{ n = "Fire",  r = 1.00, g = 0.36, b = 0.22, dur = 7,  gap = 2.0, off = 3.1,
		  icon = "Interface\\Icons\\Spell_Fire_TotemOfWrath",   active = "Interface\\Icons\\Spell_Fire_SealOfFire" },
		{ n = "Water", r = 0.42, g = 0.58, b = 1.00, dur = 11, gap = 2.5, off = 6.4,
		  icon = "Interface\\Icons\\Spell_Nature_ManaRegenTotem", active = "Interface\\Icons\\Spell_Frost_SummonWaterElemental" },
		{ n = "Air",   r = 0.86, g = 0.88, b = 0.98, dur = 8,  gap = 2.0, off = 1.7,
		  icon = "Interface\\Icons\\Spell_Nature_Windfury",     active = "Interface\\Icons\\Spell_Nature_InvisibilityTotem" },
	}
	local STYLES = {
		{ key = "normal", label = "Normal",
		  set = function() OPT().activeTotemAsMain = false; OPT().dynamicTotemMode = false end,
		  is  = function() return not OPT().activeTotemAsMain and not OPT().dynamicTotemMode end,
		  caption = "Your assigned totems stay on the bar. Drop a different totem and it appears above its slot while the assigned one greys out until it expires." },
		{ key = "totemtimers", label = "TotemTimers Style",
		  set = function() OPT().activeTotemAsMain = true; OPT().dynamicTotemMode = false end,
		  is  = function() return OPT().activeTotemAsMain and not OPT().dynamicTotemMode end,
		  caption = "The dropped totem takes over the big icon and your assigned totem shrinks into the bottom-right corner until it expires." },
		{ key = "dynamic", label = "Dynamic (PvP)",
		  set = function() OPT().dynamicTotemMode = true; OPT().activeTotemAsMain = false end,
		  is  = function() return OPT().dynamicTotemMode end,
		  caption = "The bar simply becomes whatever you last dropped - one totem per slot, nothing else. Great for PvP." },
	}
	local SIZE, GAP, STEP = 46, 12, 58
	local bar = CreateFrame("Frame", nil, inner)
	bar:SetSize(4 * STEP - GAP, SIZE * 2 + 30); bar:SetPoint("CENTER", inner, "CENTER", 0, 8)
	-- frame behind the bar (Hide Totem Bar Frame option)
	local frameBg = bar:CreateTexture(nil, "BACKGROUND", nil, -1); frameBg:SetPoint("TOPLEFT", bar, "TOPLEFT", -8, 8); frameBg:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 8, -8); frameBg:SetColorTexture(0, 0, 0, 0.7)
	local frameBd = CreateFrame("Frame", nil, bar); frameBd:SetPoint("TOPLEFT", frameBg); frameBd:SetPoint("BOTTOMRIGHT", frameBg); Core:MakeBorder(frameBd, "border")
	local slots = {}
	for i, e in ipairs(ELE) do
		local slot = CreateFrame("Frame", nil, bar); slot:SetSize(SIZE, SIZE * 2 + 30)
		slot:SetPoint("LEFT", bar, "LEFT", (i - 1) * STEP, 0)
		-- Main button (the assigned totem slot). Sits at the bottom; in the
		-- single-row styles it is centered by moving the whole bar instead.
		local main = CreateFrame("Frame", nil, slot); main:SetSize(SIZE, SIZE); main:SetPoint("BOTTOM", slot, "BOTTOM", 0, 14)
		local mbg = main:CreateTexture(nil, "BACKGROUND"); mbg:SetAllPoints(main); mbg:SetColorTexture(0, 0, 0, 0.6)
		local mIcon = main:CreateTexture(nil, "ARTWORK"); mIcon:SetPoint("TOPLEFT", 2, -2); mIcon:SetPoint("BOTTOMRIGHT", -2, 2); mIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		Core:MakeBorder(main, "border")
		local key = main:CreateFontString(nil, "OVERLAY"); key:SetFont("Fonts\\ARIALN.TTF", 9, "OUTLINE"); key:SetPoint("BOTTOMLEFT", main, "BOTTOMLEFT", 2, 2); key:SetText("S-" .. i); key:SetTextColor(0.9, 0.9, 0.9)
		-- Assigned-totem corner badge (TotemTimers style).
		local inset = main:CreateTexture(nil, "OVERLAY"); inset:SetSize(18, 18); inset:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", -2, 2); inset:SetTexCoord(0.08, 0.92, 0.08, 0.92); inset:SetTexture(e.icon)
		local insetBd = main:CreateTexture(nil, "OVERLAY"); insetBd:SetPoint("TOPLEFT", inset, -1, 1); insetBd:SetPoint("BOTTOMRIGHT", inset, 1, -1); insetBd:SetColorTexture(0, 0, 0, 0.9); insetBd:SetDrawLayer("OVERLAY", -1)
		-- Duration bar under the button (3px, element color), like the real bar.
		local dbg = main:CreateTexture(nil, "BACKGROUND"); dbg:SetHeight(3); dbg:SetPoint("TOPLEFT", main, "BOTTOMLEFT", 0, -1); dbg:SetPoint("TOPRIGHT", main, "BOTTOMRIGHT", 0, -1); dbg:SetColorTexture(0, 0, 0, 0.6)
		local dbar = main:CreateTexture(nil, "ARTWORK"); dbar:SetHeight(3); dbar:SetPoint("TOPLEFT", main, "BOTTOMLEFT", 0, -1); dbar:SetWidth(SIZE); dbar:SetColorTexture(e.r, e.g, e.b, 0.95)
		-- Active-totem overlay above the button (Normal style).
		local over = CreateFrame("Frame", nil, slot); over:SetSize(SIZE, SIZE); over:SetPoint("BOTTOM", main, "TOP", 0, 4)
		slot.main, slot.over = main, over
		local obg = over:CreateTexture(nil, "BACKGROUND"); obg:SetAllPoints(over); obg:SetColorTexture(0, 0, 0, 0.6)
		local oIcon = over:CreateTexture(nil, "ARTWORK"); oIcon:SetPoint("TOPLEFT", 2, -2); oIcon:SetPoint("BOTTOMRIGHT", -2, 2); oIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92); oIcon:SetTexture(e.active)
		Core:MakeBorder(over, "border")
		slots[i] = { e = e, main = main, mIcon = mIcon, inset = inset, insetBd = insetBd, dbg = dbg, dbar = dbar, over = over, t = e.off, lastMode = nil }
	end
	local styleCap = inner:CreateFontString(nil, "OVERLAY"); styleCap:SetFontObject(Core.fonts.rowDim)
	styleCap:SetPoint("BOTTOMLEFT", inner, "BOTTOMLEFT", 12, 14); styleCap:SetPoint("BOTTOMRIGHT", inner, "BOTTOMRIGHT", -12, 14)
	styleCap:SetJustifyH("CENTER"); styleCap:SetWordWrap(true)

	local function mode()
		if OPT().dynamicTotemMode then return "dynamic" end
		if OPT().activeTotemAsMain then return "tt" end
		return "normal"
	end

	-- Simulation: each slot drops a totem (different from the assigned one),
	-- it runs down, expires, and after a short gap is dropped again.
	-- Re-orient the mock for the chosen layout. Horizontal: overlay above the
	-- button. Vertical: overlay pops out on the flyout side.
	local lastLay, lastMode
	local function relayout(lay, m)
		local vertical = (lay ~= "Horizontal")
		local side = (lay == "VerticalLeft") and -1 or 1
		local normal = (m == "normal")
		for i, s in ipairs(slots) do
			local slot, main, over = s.main:GetParent(), s.main, s.over
			slot:ClearAllPoints(); main:ClearAllPoints(); over:ClearAllPoints()
			if vertical then
				slot:SetSize(SIZE, SIZE + 14)
				slot:SetPoint("TOP", bar, "TOP", 0, -(i - 1) * (SIZE + 14 + 8))
				main:SetPoint("TOP", slot, "TOP", 0, 0)
				over:SetPoint(side > 0 and "LEFT" or "RIGHT", main, side > 0 and "RIGHT" or "LEFT", side * 4, 0)
			else
				slot:SetSize(SIZE, normal and (SIZE * 2 + 30) or (SIZE + 14))
				slot:SetPoint("LEFT", bar, "LEFT", (i - 1) * STEP, 0)
				main:SetPoint("BOTTOM", slot, "BOTTOM", 0, 14)
				over:SetPoint("BOTTOM", main, "TOP", 0, 4)
			end
		end
		if vertical then bar:SetSize(SIZE + (normal and (SIZE + 4) or 0), 4 * (SIZE + 14 + 8) - 8)
		else bar:SetSize(4 * STEP - GAP, normal and (SIZE * 2 + 30) or (SIZE + 14)) end
		bar:ClearAllPoints(); bar:SetPoint("CENTER", inner, "CENTER", (vertical and normal) and (-side * (SIZE + 4) / 2) or 0, vertical and 10 or (normal and 8 or -14))
	end

	bar:SetScript("OnUpdate", function(_, el)
		local m = mode()
		local lay = OPT().layout or "Horizontal"
		if lay ~= lastLay or m ~= lastMode then lastLay, lastMode = lay, m; relayout(lay, m) end
		local sc = OPT().buffscale or 1
		if SP.Wizard.previewOnly then sc = math.min(sc, (inner:GetHeight() - 6) / math.max(1, bar:GetHeight() + 16)) end
		bar:SetScale(sc)
		local opacity, fullActive = OPT().totemBarOpacity or 1, OPT().totemBarFullOpacityWhenActive
		frameBg:SetShown(not OPT().hideTotemBarFrame); frameBd:SetShown(not OPT().hideTotemBarFrame)
		for _, s in ipairs(slots) do
			local e = s.e
			s.t = s.t + el
			local cycle = e.dur + e.gap
			if s.t >= cycle then s.t = s.t - cycle end
			local activeNow = s.t < e.dur
			local frac = activeNow and (1 - s.t / e.dur) or 0
			s.main:GetParent():SetAlpha((fullActive and activeNow) and 1 or opacity)
			-- duration bars have their own step; keep this one about the styles
			s.dbg:Hide(); s.dbar:Hide()
			if m == "normal" then
				s.over:SetShown(activeNow and not s.flyOpen)
				s.mIcon:SetTexture(e.icon)
				s.mIcon:SetDesaturated(activeNow); s.mIcon:SetAlpha(activeNow and 0.5 or 1)
				s.inset:Hide(); s.insetBd:Hide()
			elseif m == "tt" then
				s.over:Hide()
				s.mIcon:SetTexture(activeNow and e.active or e.icon)
				s.mIcon:SetDesaturated(false); s.mIcon:SetAlpha(1)
				s.inset:SetShown(activeNow); s.insetBd:SetShown(activeNow)
			else -- dynamic: the slot becomes whatever was dropped, and stays that way
				s.over:Hide()
				s.mIcon:SetTexture(e.active)
				s.mIcon:SetDesaturated(false); s.mIcon:SetAlpha(1)
				s.inset:Hide(); s.insetBd:Hide()
			end
		end
	end)

	if SP.Wizard.previewOnly then
		for _, st in ipairs(STYLES) do if st.is() then styleCap:SetText(st.caption) end end
		return y
	end
	-- ---- flyout demo on the Fire slot ------------------------------------
	-- A pretend cursor hovers the slot, the flyout opens with the real Fire
	-- totem icons, left-click drops one, right-click assigns one.
	local fire = slots[2]
	local FIRE_ICONS = (SP.TotemIcons and SP.TotemIcons[2]) or {}
	local FB = SIZE                                  -- flyout buttons match the totem size
	local fly = CreateFrame("Frame", nil, bar); fly:SetFrameLevel(bar:GetFrameLevel() + 12); fly:SetSize(1, 1); fly:SetPoint("CENTER", fire.main); fly:Hide()
	local flyBtns, flyIdx = {}, { 2, 3, 4 }        -- shown in the flyout (the assigned one is never listed)
	for i = 1, 3 do
		local b = CreateFrame("Frame", nil, fly); b:SetSize(FB, FB)
		local bg = b:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(b); bg:SetColorTexture(0, 0, 0, 0.75)
		local ic = b:CreateTexture(nil, "ARTWORK"); ic:SetPoint("TOPLEFT", 2, -2); ic:SetPoint("BOTTOMRIGHT", -2, 2); ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		Core:MakeBorder(b, "border")
		local hl = b:CreateTexture(nil, "OVERLAY"); hl:SetAllPoints(b); hl:SetColorTexture(1, 1, 1, 0.25); hl:Hide()
		flyBtns[i] = { f = b, ic = ic, hl = hl }
	end
	local function paintFly()
		for i, b in ipairs(flyBtns) do b.ic:SetTexture(FIRE_ICONS[flyIdx[i]] or fire.e.active); b.hl:Hide() end
	end
	local function layoutFly()
		local lay = OPT().layout or "Horizontal"
		for i, b in ipairs(flyBtns) do
			b.f:ClearAllPoints()
			if lay == "Horizontal" then b.f:SetPoint("BOTTOM", fire.main, "TOP", 0, 2 + (i - 1) * FB)
			elseif lay == "VerticalLeft" then b.f:SetPoint("RIGHT", fire.main, "LEFT", -((i - 1) * FB), 0)
			else b.f:SetPoint("LEFT", fire.main, "RIGHT", (i - 1) * FB, 0) end
		end
	end
	paintFly()
	-- the pretend cursor (tip at its top-left) + a click flash
	local cur = CreateFrame("Frame", nil, inner); cur:SetSize(26, 26); cur:SetFrameLevel(inner:GetFrameLevel() + 40); cur:Hide()
	local curTex = cur:CreateTexture(nil, "OVERLAY"); curTex:SetAllPoints(cur); curTex:SetTexture("Interface\\Cursor\\Point")
	local flash = cur:CreateTexture(nil, "OVERLAY"); flash:SetSize(44, 44); flash:SetPoint("CENTER", cur, "TOPLEFT", 3, -3)
	flash:SetTexture("Interface\\Buttons\\UI-ActionButton-Border"); flash:SetBlendMode("ADD"); flash:SetAlpha(0)
	local flyCap = inner:CreateFontString(nil, "OVERLAY"); flyCap:SetFontObject(Core.fonts.row)
	flyCap:SetPoint("BOTTOM", styleCap, "TOP", 0, 12); flyCap:SetWidth(inner:GetWidth() - 40); flyCap:SetJustifyH("CENTER"); flyCap:SetWordWrap(true)

	-- position the cursor tip on a frame's centre, in inner's coordinates
	local cx, cy, tx, ty = 0, 0, 0, 0
	local function targetOf(f)
		local x, y = f:GetCenter(); if not x then return end
		local es, is = f:GetEffectiveScale(), inner:GetEffectiveScale()
		tx = x * es / is - inner:GetLeft()
		ty = y * es / is - inner:GetBottom()
	end
	local function parkOffscreen() tx, ty = inner:GetWidth() - 30, 60 end
	parkOffscreen(); cx, cy = tx, ty

	-- choreography: { at = seconds, do = function }
	local SCRIPT = {
		{ at = 0.0,  go = function() cur:Show(); parkOffscreen(); flyCap:SetText("") end },
		{ at = 0.8,  go = function() targetOf(fire.main); flyCap:SetText("Mouse over a totem on the bar...") end },
		{ at = 2.0,  go = function() fire.flyOpen = true; layoutFly(); paintFly(); fly:Show(); flyCap:SetText("...and its flyout opens with your other totems of that element.") end },
		{ at = 3.0,  go = function() targetOf(flyBtns[3].f); flyBtns[3].hl:Show() end },
		{ at = 4.0,  go = function()
			flash:SetVertexColor(1, 1, 1); flash:SetAlpha(1)
			fire.e.active = FIRE_ICONS[flyIdx[3]] or fire.e.active; fire.t = 0     -- dropped right now
			flyCap:SetText("|cffffffffLeft-click|r drops that totem right now.")
		end },
		{ at = 5.0,  go = function() fly:Hide(); fire.flyOpen = nil; parkOffscreen() end },
		{ at = 7.0,  go = function() targetOf(fire.main); flyCap:SetText("Now the other click...") end },
		{ at = 8.0,  go = function() fire.flyOpen = true; layoutFly(); paintFly(); fly:Show() end },
		{ at = 9.0,  go = function() targetOf(flyBtns[1].f); flyBtns[1].hl:Show() end },
		{ at = 10.0, go = function()
			flash:SetVertexColor(0.3, 0.7, 1); flash:SetAlpha(1)
			local newAssigned = flyIdx[1]
			local old = fire.assignedIdx or 1
			fire.e.icon = FIRE_ICONS[newAssigned] or fire.e.icon; fire.assignedIdx = newAssigned
			flyIdx[1] = old; paintFly()                                          -- the old one is back in the flyout
			flyCap:SetText("|cffffffffRight-click|r makes it your |cffffffffassigned|r Fire totem - the one that lives on the bar and drops with your keybind.")
		end },
		{ at = 11.2, go = function() fly:Hide(); fire.flyOpen = nil; parkOffscreen() end },
		{ at = 13.5, go = function() cur:Hide(); flyCap:SetText("") end },
	}
	local CYCLE, ft, fi = 14.5, 0, 0
	local demo = CreateFrame("Frame", nil, inner)
	demo:SetScript("OnUpdate", function(_, el)
		ft = ft + el
		if ft >= CYCLE then ft = 0; fi = 0 end
		while SCRIPT[fi + 1] and SCRIPT[fi + 1].at <= ft do fi = fi + 1; SCRIPT[fi].go() end
		-- glide the cursor, fade the flash
		cx = cx + (tx - cx) * math.min(1, el * 6); cy = cy + (ty - cy) * math.min(1, el * 6)
		cur:ClearAllPoints(); cur:SetPoint("TOPLEFT", inner, "BOTTOMLEFT", cx, cy)
		if flash:GetAlpha() > 0 then flash:SetAlpha(math.max(0, flash:GetAlpha() - el * 2.5)) end
		if fly:IsShown() then layoutFly() end
	end)

	local buttons = {}
	local function refresh()
		for _, st in ipairs(STYLES) do
			local on = st.is()
			buttons[st.key].bg:SetColorTexture(Core:Color("accent", on and 0.34 or 0.10))
			Core:SetBorderColor(buttons[st.key], on and "accent" or "border")
			buttons[st.key].text:SetTextColor(Core:Color(on and "accentHi" or "text"))
			if on then styleCap:SetText(st.caption) end
		end
	end
	for _, st in ipairs(STYLES) do
		local btn = Core:MakeButton(card, st.label, 10, false)
		btn:SetPoint("TOPLEFT", card, "TOPLEFT", 18, -y); btn:SetPoint("TOPRIGHT", card, "TOPRIGHT", -18, -y)
		btn:SetScript("OnClick", function()
			st.set()
			if SP.UpdateLayout then pcall(SP.UpdateLayout, SP) end
			if SP.UpdateMiniTotemBar then pcall(SP.UpdateMiniTotemBar, SP) end
			local reg = LibStub and LibStub("AceConfigRegistry-3.0", true); if reg then reg:NotifyChange("ShamanPower") end
			refresh()
		end)
		buttons[st.key] = btn
		y = y + 40
	end
	refresh()

	-- ---- appearance (from Settings > Bars) ----
	local Widgets = ns.Widgets
	local W = card:GetWidth() - 36
	y = y + 6
	local function row(kind, opts)
		opts.x, opts.y, opts.width = 18, y, W
		local _, h = Widgets[kind](Widgets, card, opts)
		y = y + h
	end
	row("Dropdown", { label = "Layout", get = function() return OPT().layout or "Horizontal" end,
		set = function(v) SetTotemBarLayout(v); notify() end, values = LAYOUT_VALUES, order = LAYOUT_ORDER })
	row("Slider", { label = "Size", min = 0.4, max = 3.0, step = 0.05, get = function() return OPT().buffscale or 1 end,
		set = function(v) OPT().buffscale = v; safecall("UpdateLayout"); safecall("UpdateCooldownBarScale"); safecall("UpdateRoster"); notify() end })
	row("Slider", { label = "Opacity", min = 0, max = 1, step = 0.05, get = function() return OPT().totemBarOpacity or 1 end,
		set = function(v) OPT().totemBarOpacity = v; safecall("UpdateTotemBarOpacity"); notify() end })
	row("Toggle", { label = "Full opacity while a totem is down", get = function() return OPT().totemBarFullOpacityWhenActive and true or false end,
		set = function(v) OPT().totemBarFullOpacityWhenActive = v; safecall("UpdateTotemBarOpacity"); notify() end })
	row("Toggle", { label = "Show frame behind the bar", get = function() return not OPT().hideTotemBarFrame end,
		set = function(v) OPT().hideTotemBarFrame = not v; safecall("UpdateTotemBarFrame"); notify() end })
	return y
end

-- Duration Bars: the same simulated totem row, but every duration / cooldown /
-- pulse option from the Totem Bar > Duration Bars page is live in the card.
function SP.Wizard.BuildDurationBarsStep(card, inner, y)
	local Widgets = ns.Widgets
	local SIZE = 46
	local K = SIZE / 26          -- real totem buttons are 26px; bar/text sizes scale with the icon
	local function px(v) return math.max(1, math.floor(v * K + 0.5)) end
	local ELE = {
		{ r = 0.72, g = 0.52, b = 0.32, dur = 9,  gap = 2.5, off = 0.0, pulse = 3,
		  icon = "Interface\\Icons\\Spell_Nature_TremorTotem" },                -- Earth: pulsing (Tremor)
		{ r = 1.00, g = 0.36, b = 0.22, dur = 7,  gap = 2.0, off = 3.1,
		  icon = "Interface\\Icons\\Spell_Fire_SealOfFire" },                   -- Fire
		{ r = 0.42, g = 0.58, b = 1.00, dur = 11, gap = 2.5, off = 6.4, cd = 14,
		  icon = "Interface\\Icons\\Spell_Frost_SummonWaterElemental" },        -- Water: has a cooldown (Mana Tide)
		{ r = 0.86, g = 0.88, b = 0.98, dur = 8,  gap = 2.0, off = 1.7,
		  icon = "Interface\\Icons\\Spell_Nature_Windfury" },                   -- Air
	}
	local bar = CreateFrame("Frame", nil, inner); bar:SetPoint("CENTER", inner, "CENTER", 0, 6)
	local slots = {}
	for i, e in ipairs(ELE) do
		local b = CreateFrame("Frame", nil, bar); b:SetSize(SIZE, SIZE)
		local bg = b:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(b); bg:SetColorTexture(0, 0, 0, 0.6)
		local icon = b:CreateTexture(nil, "ARTWORK"); icon:SetPoint("TOPLEFT", 2, -2); icon:SetPoint("BOTTOMRIGHT", -2, 2); icon:SetTexture(e.icon); icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		Core:MakeBorder(b, "border")
		local s = { e = e, f = b, icon = icon, t = e.off, wasActive = false }
		-- duration bar + its five text slots (mirrors totemProgressBars)
		s.dbg = b:CreateTexture(nil, "BACKGROUND", nil, 1); s.dbg:SetColorTexture(0, 0, 0, 0.6)
		s.dbar = b:CreateTexture(nil, "ARTWORK", nil, 1); s.dbar:SetColorTexture(e.r, e.g, e.b, 0.95)
		local function fs(parent) local t = parent:CreateFontString(nil, "OVERLAY", nil, 7); t:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE"); t:SetTextColor(1, 1, 1); t:Hide(); return t end
		s.txt = { inside_top = fs(b), inside_bottom = fs(b), above = fs(b), below = fs(b), icon = fs(b) }
		s.txt.icon:SetPoint("CENTER", b, "CENTER")
		-- totem cooldown: radial swipe + colored remaining text (Water only)
		if e.cd then
			s.cdf = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate"); s.cdf:SetAllPoints(b); s.cdf:SetDrawEdge(false)
			if s.cdf.SetHideCountdownNumbers then s.cdf:SetHideCountdownNumbers(true) end
			s.cdt = b:CreateFontString(nil, "OVERLAY", nil, 7); s.cdt:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE"); s.cdt:SetPoint("CENTER", b, "CENTER"); s.cdt:Hide()
			-- vertical sweep alternative (grey grows down from the top, like the cooldown bar)
			s.cdgray = b:CreateTexture(nil, "ARTWORK", nil, 1); s.cdgray:SetPoint("TOPLEFT", icon, "TOPLEFT"); s.cdgray:SetPoint("TOPRIGHT", icon, "TOPRIGHT")
			s.cdgray:SetTexture(e.icon); s.cdgray:SetDesaturated(true); s.cdgray:SetVertexColor(0.5, 0.5, 0.5); s.cdgray:Hide()
		end
		-- pulse wipe (Earth only): white overlay, plus its text slots
		if e.pulse then
			s.wf = CreateFrame("Frame", nil, b); s.wf:SetFrameLevel(b:GetFrameLevel() + 2)
			s.wipe = s.wf:CreateTexture(nil, "OVERLAY"); s.wipe:SetColorTexture(1, 1, 1, 0.7)
			s.ptxt = { inside_top = fs(s.wf), inside_bottom = fs(s.wf), above = fs(s.wf), below = fs(s.wf), on_icon = fs(b) }
			s.ptxt.inside_top:SetPoint("TOP", s.wf, "TOP", 0, -1); s.ptxt.inside_bottom:SetPoint("BOTTOM", s.wf, "BOTTOM", 0, 1)
			s.ptxt.above:SetPoint("BOTTOM", s.wf, "TOP", 0, 1); s.ptxt.below:SetPoint("TOP", s.wf, "BOTTOM", 0, -1)
			s.ptxt.on_icon:SetPoint("CENTER", b, "CENTER", 0, -12)
		end
		slots[i] = s
	end

	local function O(k, d) local v = OPT()[k]; if v == nil then return d end; return v end
	local function sideSpace()
		local dp, pp = O("durationBarPosition", "bottom"), O("pulseBarPosition", "on_icon")
		local n = 0
		if dp == "left" or dp == "right" then n = n + px(O("durationBarHeight", 3)) + 2 end
		if pp == "left" or pp == "right" then n = n + px(O("pulseBarSize", 4)) + 2 end
		return n
	end

	-- Re-anchor everything from the current options (called on any change).
	local function layout()
		local dp, ds = O("durationBarPosition", "bottom"), px(O("durationBarHeight", 3))
		local pp, ps = O("pulseBarPosition", "on_icon"), px(O("pulseBarSize", 4))
		local step = SIZE + 14 + sideSpace()
		bar:SetSize(4 * step - 14 - sideSpace(), SIZE)
		for i, s in ipairs(slots) do
			local b = s.f
			b:ClearAllPoints(); b:SetPoint("LEFT", bar, "LEFT", (i - 1) * step + math.floor(sideSpace() / 2), 0)
			-- duration bar geometry (same anchors as UpdateTotemProgressBarPositions)
			s.dbg:ClearAllPoints(); s.dbar:ClearAllPoints()
			s.vert = (dp == "left" or dp == "right" or dp == "top_vert" or dp == "bottom_vert")
			if dp == "bottom" then
				s.dbg:SetHeight(ds); s.dbg:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, -1); s.dbg:SetPoint("TOPRIGHT", b, "BOTTOMRIGHT", 0, -1)
				s.dbar:SetHeight(ds); s.dbar:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, -1)
			elseif dp == "top" then
				s.dbg:SetHeight(ds); s.dbg:SetPoint("BOTTOMLEFT", b, "TOPLEFT", 0, 1); s.dbg:SetPoint("BOTTOMRIGHT", b, "TOPRIGHT", 0, 1)
				s.dbar:SetHeight(ds); s.dbar:SetPoint("BOTTOMLEFT", b, "TOPLEFT", 0, 1)
			elseif dp == "bottom_vert" then
				s.dbg:SetSize(ds, SIZE); s.dbg:SetPoint("TOP", b, "BOTTOM", 0, -1)
				s.dbar:SetWidth(ds); s.dbar:SetPoint("TOP", s.dbg, "TOP", 0, 0)
			elseif dp == "top_vert" then
				s.dbg:SetSize(ds, SIZE); s.dbg:SetPoint("BOTTOM", b, "TOP", 0, 1)
				s.dbar:SetWidth(ds); s.dbar:SetPoint("BOTTOM", s.dbg, "BOTTOM", 0, 0)
			elseif dp == "left" then
				s.dbg:SetWidth(ds); s.dbg:SetPoint("TOPRIGHT", b, "TOPLEFT", -1, 0); s.dbg:SetPoint("BOTTOMRIGHT", b, "BOTTOMLEFT", -1, 0)
				s.dbar:SetWidth(ds); s.dbar:SetPoint("BOTTOMRIGHT", b, "BOTTOMLEFT", -1, 0)
			elseif dp == "right" then
				s.dbg:SetWidth(ds); s.dbg:SetPoint("TOPLEFT", b, "TOPRIGHT", 1, 0); s.dbg:SetPoint("BOTTOMLEFT", b, "BOTTOMRIGHT", 1, 0)
				s.dbar:SetWidth(ds); s.dbar:SetPoint("BOTTOMLEFT", b, "BOTTOMRIGHT", 1, 0)
			end
			for _, t in pairs(s.txt) do t:ClearAllPoints() end
			s.txt.icon:SetPoint("CENTER", b, "CENTER")
			s.txt.inside_top:SetPoint("TOP", s.dbg, "TOP", 0, -1); s.txt.inside_bottom:SetPoint("BOTTOM", s.dbg, "BOTTOM", 0, 1)
			s.txt.above:SetPoint("BOTTOM", s.dbg, "TOP", 0, 1); s.txt.below:SetPoint("TOP", s.dbg, "BOTTOM", 0, -1)
			-- pulse wipe geometry (same anchors as PositionPulseWipe)
			if s.wf then
				local wf, w = s.wf, s.wipe
				wf:ClearAllPoints(); w:ClearAllPoints()
				s.pvert, s.pmax = true, SIZE - 4
				if pp == "on_icon" then
					wf:SetAllPoints(b); w:SetPoint("TOPLEFT", b, "TOPLEFT", 2, -2); w:SetPoint("TOPRIGHT", b, "TOPRIGHT", -2, -2); w:SetHeight(1)
				elseif pp == "above" then
					wf:SetPoint("BOTTOMLEFT", b, "TOPLEFT", 0, 1); wf:SetSize(SIZE, ps); w:SetPoint("LEFT", wf, "LEFT"); w:SetHeight(ps); w:SetWidth(1); s.pvert, s.pmax = false, SIZE
				elseif pp == "above_vert" then
					wf:SetPoint("BOTTOM", b, "TOP", 0, 1); wf:SetSize(ps, SIZE); w:SetPoint("BOTTOMLEFT", wf, "BOTTOMLEFT"); w:SetWidth(ps); w:SetHeight(1); s.pmax = SIZE
				elseif pp == "below" then
					wf:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, -1); wf:SetSize(SIZE, ps); w:SetPoint("LEFT", wf, "LEFT"); w:SetHeight(ps); w:SetWidth(1); s.pvert, s.pmax = false, SIZE
				elseif pp == "below_vert" then
					wf:SetPoint("TOP", b, "BOTTOM", 0, -1); wf:SetSize(ps, SIZE); w:SetPoint("TOPLEFT", wf, "TOPLEFT"); w:SetWidth(ps); w:SetHeight(1); s.pmax = SIZE
				elseif pp == "left" then
					wf:SetPoint("TOPRIGHT", b, "TOPLEFT", -1, 0); wf:SetSize(ps, SIZE); w:SetPoint("BOTTOMLEFT", wf, "BOTTOMLEFT"); w:SetWidth(ps); w:SetHeight(1); s.pmax = SIZE
				elseif pp == "right" then
					wf:SetPoint("TOPLEFT", b, "TOPRIGHT", 1, 0); wf:SetSize(ps, SIZE); w:SetPoint("BOTTOMLEFT", wf, "BOTTOMLEFT"); w:SetWidth(ps); w:SetHeight(1); s.pmax = SIZE
				end
				-- when the duration bar and pulse bar share a side, stack the pulse text outside it
				if (pp == "above" or pp == "below") then wf:SetFrameLevel(b:GetFrameLevel() + 2) end
			end
		end
	end

	bar:SetScript("OnUpdate", function(_, el)
		local dp, tl, ts = O("durationBarPosition", "bottom"), O("durationTextLocation", "none"), px(O("durationTextSize", 8))
		local showCd, cdc = O("showTotemCooldowns", true), OPT().totemCooldownTextColor
		local pp, ptl, pts = O("pulseBarPosition", "on_icon"), O("pulseTimeDisplay", "none"), px(O("pulseTextSize", 8))
		for _, s in ipairs(slots) do
			local e = s.e
			s.t = s.t + el
			local cycle = e.dur + e.gap
			if s.t >= cycle then s.t = s.t - cycle end
			local active = s.t < e.dur
			local remain = active and (e.dur - s.t) or 0
			local pct = active and (remain / e.dur) or 0
			-- duration bar
			local showBar = active and dp ~= "none"
			s.dbg:SetShown(showBar); s.dbar:SetShown(showBar)
			if showBar then
				if s.vert then s.dbar:SetHeight(math.max(1, SIZE * pct)) else s.dbar:SetWidth(math.max(1, SIZE * pct)) end
			end
			for k, t in pairs(s.txt) do
				local on = active and tl == k and (k == "icon" or dp ~= "none")
				t:SetShown(on)
				if on then t:SetFont("Fonts\\FRIZQT__.TTF", ts, "OUTLINE"); t:SetText(tostring(math.ceil(remain))) end
			end
			-- totem cooldown (starts when the totem is dropped)
			if s.cdf then
				local cdStyleOpt = O("totemCooldownSweep", "radial")
				local vertical = (cdStyleOpt == "vertical" or cdStyleOpt == "reverse")
				if active and not s.wasActive then s.cdStart = GetTime(); s.cdStyle = nil end
				local cdRemain = s.cdStart and (s.cdStart + e.cd - GetTime()) or 0
				if showCd and cdRemain > 0 then
					local style = cdStyleOpt
					if s.cdStyle ~= style then
						s.cdStyle = style
						if vertical then s.cdf:Clear() else s.cdf:SetCooldown(s.cdStart, e.cd) end
					end
					if vertical then
						local dep = (cdStyleOpt == "reverse") and (cdRemain / e.cd) or (1 - cdRemain / e.cd)
						s.cdgray:SetHeight(math.max(0.5, (SIZE - 4) * dep)); s.cdgray:SetTexCoord(0.08, 0.92, 0.08, 0.08 + dep * 0.84); s.cdgray:Show()
					else s.cdgray:Hide() end
					if O("totemCooldownText", true) ~= false then
						s.cdt:SetText(tostring(math.ceil(cdRemain))); s.cdt:Show()
						if cdc then s.cdt:SetTextColor(cdc.r or 1, cdc.g or 1, cdc.b or 1) else s.cdt:SetTextColor(1, 1, 1) end
					else s.cdt:Hide() end
				else
					s.cdt:Hide(); s.cdgray:Hide(); s.cdf:Clear(); s.cdStyle = nil
				end
			end
			-- pulse wipe: fills up to the next pulse, then resets
			if s.wf then
				local vis = active and pp ~= "none"
				s.wf:SetShown(vis)
				if vis then
					local prog = (s.t % e.pulse) / e.pulse
					local size = math.max(1, s.pmax * prog)
					if s.pvert then s.wipe:SetHeight(size) else s.wipe:SetWidth(size) end
					s.wipe:SetShown(prog > 0.02)
				end
				for k, t in pairs(s.ptxt) do
					local on = active and ptl == k and (k == "on_icon" or pp ~= "none")
					t:SetShown(on)
					if on then t:SetFont("Fonts\\FRIZQT__.TTF", pts, "OUTLINE"); t:SetText(string.format("%.1f", e.pulse - (s.t % e.pulse))) end
				end
			end
			s.wasActive = active
		end
	end)

	if SP.Wizard.previewOnly then layout(); return y end
	-- ---- controls (same widget kit as the options screen) ----
	local W = card:GetWidth() - 36
	local function row(kind, opts)
		opts.x, opts.y, opts.width = 18, y, W
		opts.onChanged = function() layout() end
		local _, h = Widgets[kind](Widgets, card, opts)
		y = y + h
	end
	local function upd(...) for _, fn in ipairs({ ... }) do safecall(fn) end; notify(); layout() end
	row("Dropdown", { label = "Bar position", get = function() return O("durationBarPosition", "bottom") end,
		set = function(v) OPT().durationBarPosition = v; upd("UpdateTotemProgressBarPositions", "UpdateMiniTotemBar") end,
		values = function() return { none = "None", bottom = "Bottom (Horizontal)", bottom_vert = "Bottom (Vertical)", top = "Top (Horizontal)", top_vert = "Top (Vertical)", left = "Left", right = "Right" } end,
		order = function() return { "none", "bottom", "bottom_vert", "top", "top_vert", "left", "right" } end })
	row("Slider", { label = "Bar size", min = 2, max = 26, step = 1, get = function() return O("durationBarHeight", 3) end,
		set = function(v) OPT().durationBarHeight = v; upd("UpdateTotemProgressBarHeight") end })
	row("Dropdown", { label = "Show duration", get = function() return O("durationTextLocation", "none") end,
		set = function(v) OPT().durationTextLocation = v; upd("UpdateTotemProgressBarPositions", "UpdateTotemProgressBars") end,
		values = function() return { none = "None", inside_top = "Inside Bar (Top)", inside_bottom = "Inside Bar (Bottom)", above = "Above Bar", below = "Below Bar", icon = "On Icon" } end,
		order = function() return { "none", "inside_top", "inside_bottom", "above", "below", "icon" } end })
	row("Slider", { label = "Text size", min = 6, max = 20, step = 1, get = function() return O("durationTextSize", 8) end,
		set = function(v) OPT().durationTextSize = v; upd("UpdateTotemProgressBarPositions", "UpdateTotemProgressBars") end })
	row("Toggle", { label = "Show totem cooldowns", get = function() return O("showTotemCooldowns", true) end,
		set = function(v) OPT().showTotemCooldowns = v; upd("SetupTotemProgressBars"); Widgets:RefreshAll(card) end })
	row("Dropdown", { label = "Cooldown style", disabled = function() return O("showTotemCooldowns", true) == false end,
		get = function() return O("totemCooldownSweep", "radial") end,
		set = function(v) OPT().totemCooldownSweep = v; upd("UpdateTotemCooldowns") end,
		values = function() return { radial = "Radial swipe", vertical = "Vertical sweep (greys out)", reverse = "Vertical sweep (fills back in)" } end, order = function() return { "radial", "vertical", "reverse" } end })
	row("Toggle", { label = "Show cooldown time", desc = "The remaining seconds on the totem. Off = just the swipe.",
		disabled = function() return O("showTotemCooldowns", true) == false end,
		get = function() return O("totemCooldownText", true) ~= false end,
		set = function(v) OPT().totemCooldownText = v; upd("UpdateTotemCooldowns"); Widgets:RefreshAll(card) end })
	row("Color", { label = "Cooldown text color", disabled = function() return O("showTotemCooldowns", true) == false or O("totemCooldownText", true) == false end,
		get = function() local c = OPT().totemCooldownTextColor; if c then return c.r or 1, c.g or 1, c.b or 1 end; return 1, 1, 1 end,
		set = function(r, g, b) OPT().totemCooldownTextColor = OPT().totemCooldownTextColor or {}; local c = OPT().totemCooldownTextColor; c.r, c.g, c.b = r, g, b; upd("ApplyTotemCooldownTextColor") end })
	row("Dropdown", { label = "Pulse position", get = function() return O("pulseBarPosition", "on_icon") end,
		set = function(v) OPT().pulseBarPosition = v; upd("UpdatePulseBarPositions") end,
		values = function() return { none = "None", on_icon = "On Icon", above = "Above (Horizontal)", above_vert = "Above (Vertical)", below = "Below (Horizontal)", below_vert = "Below (Vertical)", left = "Left", right = "Right" } end,
		order = function() return { "none", "on_icon", "above", "above_vert", "below", "below_vert", "left", "right" } end })
	row("Slider", { label = "Pulse size", min = 2, max = 26, step = 1, get = function() return O("pulseBarSize", 4) end,
		set = function(v) OPT().pulseBarSize = v; upd("UpdatePulseBarPositions") end })
	row("Dropdown", { label = "Pulse time", get = function() return O("pulseTimeDisplay", "none") end,
		set = function(v) OPT().pulseTimeDisplay = v; upd("UpdatePulseBarPositions") end,
		values = function() return { none = "None", inside_top = "Inside Bar (Top)", inside_bottom = "Inside Bar (Bottom)", above = "Above Bar", below = "Below Bar", on_icon = "On Icon" } end,
		order = function() return { "none", "inside_top", "inside_bottom", "above", "below", "on_icon" } end })
	row("Slider", { label = "Pulse text size", min = 6, max = 20, step = 1, get = function() return O("pulseTextSize", 8) end,
		set = function(v) OPT().pulseTextSize = v; upd("UpdatePulseBarPositions") end })
	local endY = y

	local legend = inner:CreateFontString(nil, "OVERLAY"); legend:SetFontObject(Core.fonts.rowDim)
	legend:SetPoint("BOTTOMLEFT", inner, "BOTTOMLEFT", 12, 14); legend:SetPoint("BOTTOMRIGHT", inner, "BOTTOMRIGHT", -12, 14)
	legend:SetJustifyH("CENTER"); legend:SetWordWrap(true)
	legend:SetText("Tremor (left) shows the white pulse bar. Mana Tide (third) shows a totem cooldown. Change anything on the left and watch it here.")
	layout()
	return endY
end

-- Earth Shield Tracker: the REAL tracker frame, borrowed into the preview and
-- fed a simulated raid, with every option from its settings page live.
function SP.Wizard.BuildESTrackerStep(card, inner, y)
	local Widgets = ns.Widgets
	local function es() SP:EnsureProfileTable("esTracker"); return SP.opt.esTracker end
	local function get(k, d) local t = SP.opt.esTracker; local v = t and t[k]; if v == nil then return d end; return v end

	-- Borrow the real frame; re-fit whenever its size changes (options or the
	-- simulation adding / removing shields).
	inner.previewInsetBottom = 60   -- keep the caption strip clear
	inner.previewMaxScale = 1.4     -- close to life size
	local function fit() if inner:IsShown() and inner:GetWidth() > 0 then SP:ShowPreview("estracker", inner) end end
	C_Timer.After(0.02, fit)
	local watcher, lastW, lastH, acc = CreateFrame("Frame", nil, inner), 0, 0, 0
	watcher:SetScript("OnUpdate", function(_, e)
		acc = acc + e; if acc < 0.25 then return end; acc = 0
		local f = SP.esTrackerFrame
		if f and f:GetParent() == inner then
			local w, h = f:GetWidth(), f:GetHeight()
			if w ~= lastW or h ~= lastH then lastW, lastH = w, h; fit() end
		end
	end)

	local legend = inner:CreateFontString(nil, "OVERLAY"); legend:SetFontObject(Core.fonts.rowDim)
	legend:SetPoint("BOTTOMLEFT", inner, "BOTTOMLEFT", 12, 14); legend:SetPoint("BOTTOMRIGHT", inner, "BOTTOMRIGHT", -12, 14)
	legend:SetJustifyH("CENTER"); legend:SetWordWrap(true)
	legend:SetText("Three shamans, three Earth Shields. Watch charges get used up, a shield drop off, and its shaman put it back.")

	local W = card:GetWidth() - 36
	local function row(kind, opts)
		opts.x, opts.y, opts.width = 18, y, W
		local _, h = Widgets[kind](Widgets, card, opts)
		y = y + h
	end
	local function upd(...) for _, fn in ipairs({ ... }) do safecall(fn) end; notify(); fit() end
	row("Slider", { label = "Icon size", min = 20, max = 60, step = 4, get = function() return get("iconSize", 40) end,
		set = function(v) es().iconSize = v; upd("UpdateESTrackerFrame") end })
	row("Slider", { label = "Opacity", min = 0.2, max = 1.0, step = 0.1, get = function() return get("opacity", 1.0) end,
		set = function(v) es().opacity = v; upd("UpdateESTrackerOpacity") end })
	row("Toggle", { label = "Vertical layout", get = function() return get("vertical", false) end,
		set = function(v) es().vertical = v; upd("UpdateESTrackerFrame", "UpdateESTrackerBorder") end })
	row("Toggle", { label = "Hide caster names", get = function() return get("hideNames", false) end,
		set = function(v) es().hideNames = v; upd("UpdateESTrackerFrame") end })
	row("Toggle", { label = "Hide charge counts", get = function() return get("hideCharges", false) end,
		set = function(v) es().hideCharges = v; upd("UpdateESTrackerFrame") end })
	row("Toggle", { label = "Hide border and title", get = function() return get("hideBorder", false) end,
		set = function(v) es().hideBorder = v; upd("UpdateESTrackerBorder") end })
	return y
end

-- Shield Charges: both real number frames borrowed side by side, charges
-- ticking down through their color thresholds, options live in the card.
function SP.Wizard.BuildShieldChargesStep(card, inner, y)
	local Widgets = ns.Widgets
	local function sc() SP:EnsureProfileTable("shieldChargeDisplay"); return SP.opt.shieldChargeDisplay end
	local function get(k, d) local t = SP.opt.shieldChargeDisplay; local v = t and t[k]; if v == nil then return d end; return v end

	local resto = state.role == "restoration"
	if not resto then sc().showEarthShield = false end   -- Enhancement / Elemental cannot cast Earth Shield
	inner.previewInsetBottom = 60
	inner.previewMaxScale = 1.0     -- the Scale option is the real size control
	local lblL = inner:CreateFontString(nil, "OVERLAY"); lblL:SetFontObject(Core.fonts.rowDim); lblL:SetText("Lightning / Water Shield")
	local lblR = inner:CreateFontString(nil, "OVERLAY"); lblR:SetFontObject(Core.fonts.rowDim); lblR:SetText("Earth Shield on target")
	local function fit()
		if not (inner:IsShown() and inner:GetWidth() > 0) then return end
		SP:ShowPreview("shieldcharges", inner)
		local p, e = SP.shieldChargeFrames and SP.shieldChargeFrames.player, SP.shieldChargeFrames and SP.shieldChargeFrames.earth
		-- Measure the rendered digits so the two numbers always sit inside the
		-- box at their true size; only the spacing between them adapts.
		local tw, th = 30, 48
		if p and p.text then tw = math.max(tw, p.text:GetStringWidth() or 0); th = math.max(th, p.text:GetStringHeight() or 0) end
		if e and e.text then tw = math.max(tw, e.text:GetStringWidth() or 0); th = math.max(th, e.text:GetStringHeight() or 0) end
		local halfW = tw / 2 + 12
		local dx = math.max(70, halfW + 16)
		dx = math.max(halfW, math.min(dx, inner:GetWidth() / 2 - halfW - 10))
		local showE = resto and get("showEarthShield", true) ~= false
		if e then e:SetShown(showE) end
		if not showE then dx = 0 end        -- one number: center it
		local cy = math.min(40, inner:GetHeight() / 2 - th / 2 - 16)
		if p then p:ClearAllPoints(); p:SetPoint("CENTER", inner, "CENTER", -dx, cy) end
		if e then e:ClearAllPoints(); e:SetPoint("CENTER", inner, "CENTER", dx, cy) end
		local ly = cy - th / 2 - 8
		lblL:ClearAllPoints(); lblL:SetPoint("TOP", inner, "CENTER", -dx, ly)
		lblR:ClearAllPoints(); lblR:SetPoint("TOP", inner, "CENTER", dx, ly)
		lblL:SetShown(get("showPlayerShield", true) ~= false); lblR:SetShown(showE)
	end
	C_Timer.After(0.02, fit)
	SP.Wizard._shieldFit = fit

	local legend = inner:CreateFontString(nil, "OVERLAY"); legend:SetFontObject(Core.fonts.rowDim)
	legend:SetPoint("BOTTOMLEFT", inner, "BOTTOMLEFT", 12, 14); legend:SetPoint("BOTTOMRIGHT", inner, "BOTTOMRIGHT", -12, 14)
	legend:SetJustifyH("CENTER"); legend:SetWordWrap(true)
	legend:SetText("Charges are being used up: blue / green while healthy, yellow when getting low, red when almost gone, then the shield is re-applied.")

	local W = card:GetWidth() - 36
	local function row(kind, opts)
		opts.x, opts.y, opts.width = 18, y, W
		local _, h = Widgets[kind](Widgets, card, opts)
		y = y + h
	end
	local function upd() notify(); if SP.ShieldChargesDemo then SP:ShieldChargesDemo(true) end; fit() end
	row("Slider", { label = "Size", min = 0.5, max = 3.0, step = 0.1, get = function() return get("scale", 1.0) end,
		set = function(v) sc().scale = v; upd() end })
	row("Slider", { label = "Opacity", min = 0.1, max = 1.0, step = 0.1, get = function() return get("opacity", 1.0) end,
		set = function(v) sc().opacity = v; upd() end })
	row("Toggle", { label = "Hide out of combat", get = function() return get("hideOutOfCombat", false) end,
		set = function(v) sc().hideOutOfCombat = v; upd() end })
	row("Toggle", { label = "Hide when no shield is up", get = function() return get("hideNoShields", false) end,
		set = function(v) sc().hideNoShields = v; upd() end })
	return y
end

-- Totem Twisting: a life-size Air button running the real twist cycle
-- (Windfury down -> countdown on the icon -> twist totem -> re-drop before 0),
-- with every twisting option live in the card.
function SP.Wizard.BuildTwistingStep(card, inner, y)
	local Widgets = ns.Widgets
	SP.Wizard._twistCard = card
	local WF = "Interface\\Icons\\Spell_Nature_Windfury"
	local S = 1.5                       -- preview zoom (button is 40px in game)
	local SIZE = math.floor(40 * S)
	local function twistIcon() return SP.GetTwistTotemIcon and SP:GetTwistTotemIcon() or "Interface\\Icons\\Spell_Nature_InvisibilityTotem" end
	local function twistName() return SP.GetTwistTotemName and SP:GetTwistTotemName() or "Grace of Air Totem" end

	local btn = CreateFrame("Frame", nil, inner); btn:SetSize(SIZE, SIZE); btn:SetPoint("CENTER", inner, "CENTER", 0, 40)
	local bg = btn:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(btn); bg:SetColorTexture(0, 0, 0, 0.6)
	local icon = btn:CreateTexture(nil, "ARTWORK"); icon:SetPoint("TOPLEFT", 2, -2); icon:SetPoint("BOTTOMRIGHT", -2, 2); icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	Core:MakeBorder(btn, "border")
	local glows = {}
	for i = 1, 3 do
		local g = btn:CreateTexture(nil, "OVERLAY", nil, 7); local o = (6 + i * 4) * S
		g:SetPoint("TOPLEFT", btn, "TOPLEFT", -o, o); g:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", o, -o)
		g:SetTexture("Interface\\Buttons\\UI-ActionButton-Border"); g:SetBlendMode("ADD"); g:SetVertexColor(0.4, 1, 0.4); g:SetAlpha(0)
		glows[i] = g
	end
	local key = btn:CreateFontString(nil, "OVERLAY"); key:SetFont("Fonts\\ARIALN.TTF", math.floor(9 * S), "OUTLINE"); key:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 1, 0); key:SetText("S-4"); key:SetTextColor(0.9, 0.9, 0.9)
	local timer = btn:CreateFontString(nil, "OVERLAY", nil, 7); timer:SetFont("Fonts\\FRIZQT__.TTF", math.floor(16 * S), "OUTLINE"); timer:SetPoint("CENTER", btn, "CENTER", 0, 0)
	local status = inner:CreateFontString(nil, "OVERLAY"); status:SetFontObject(Core.fonts.row); status:SetPoint("TOP", btn, "BOTTOM", 0, -18 - 10 * S)
	status:SetWidth(inner:GetWidth() - 40); status:SetJustifyH("CENTER"); status:SetWordWrap(true)
	local sub = inner:CreateFontString(nil, "OVERLAY"); sub:SetFontObject(Core.fonts.rowDim); sub:SetPoint("TOP", status, "BOTTOM", 0, -6)
	sub:SetWidth(inner:GetWidth() - 40); sub:SetJustifyH("CENTER"); sub:SetWordWrap(true)
	local legend = inner:CreateFontString(nil, "OVERLAY"); legend:SetFontObject(Core.fonts.rowDim)
	legend:SetPoint("BOTTOMLEFT", inner, "BOTTOMLEFT", 12, 14); legend:SetPoint("BOTTOMRIGHT", inner, "BOTTOMRIGHT", -12, 14)
	legend:SetJustifyH("CENTER"); legend:SetWordWrap(true)
	legend:SetText("The Air slot always shows the totem to cast NEXT. The number is how long the Windfury buff has left.")

	-- Simulation of one twist cycle: WF at 0s, twist totem at 1.5s, buff runs
	-- out at 10s (the real TWIST_WINDOW), a short pause, repeat.
	local WINDOW = SP.TWIST_WINDOW or 10
	local t, soundPlayed = 0, false
	local function offState()
		icon:SetTexture(WF); icon:SetDesaturated(true); timer:SetText("")
		for _, g in ipairs(glows) do g:SetAlpha(0) end
		status:SetText("Twisting is off"); sub:SetText("Turn it on to see the cycle.")
	end
	btn:SetScript("OnUpdate", function(_, e)
		if not SP.opt.enableTotemTwisting then offState(); return end
		icon:SetDesaturated(false)
		t = t + e
		local cycle = WINDOW + 2.5
		if t >= cycle then t = 0; soundPlayed = false end
		local remaining = WINDOW - t
		local twistDown = t >= 1.5
		icon:SetTexture(twistDown and WF or twistIcon())
		if remaining > 0 then
			local fmt = SP.opt.twistTimerNoDecimals and "%.0f" or "%.1f"
			timer:SetText(string.format(fmt, remaining))
			if remaining <= 1 then timer:SetTextColor(1, 0.2, 0.2) elseif remaining <= 3 then timer:SetTextColor(1, 1, 0.2) else timer:SetTextColor(1, 1, 1) end
			local pulse = 0.55 + 0.45 * math.sin(GetTime() * 4)
			for i, g in ipairs(glows) do g:SetAlpha(pulse * (1.1 - i * 0.2)) end
			if SP.opt.twistSoundEnabled and not soundPlayed and remaining <= (SP.opt.twistSoundThreshold or 3) then
				soundPlayed = true
				if SP.PlaySoundWithVolume and SP.GetSoundFile then
					pcall(SP.PlaySoundWithVolume, SP, SP:GetSoundFile(SP.opt.twistSoundName or "Raid Warning"), SP.opt.twistSoundVolume or 100, true)
				end
			end
			if twistDown then
				status:SetText("|cffffffff" .. twistName() .. "|r is down - re-drop Windfury before the timer hits 0")
				sub:SetText("Your group keeps the Windfury buff the whole time.")
			else
				status:SetText("Windfury is down - drop |cffffffff" .. twistName() .. "|r now")
				sub:SetText("The 10 second Windfury buff has started ticking.")
			end
		else
			timer:SetText(""); for _, g in ipairs(glows) do g:SetAlpha(0) end
			status:SetText("|cffff4040Windfury buff expired|r"); sub:SetText("Drop Windfury again to restart the cycle.")
		end
	end)

	-- ---- options (same widget kit as the settings page) ----
	local W = card:GetWidth() - 36
	local function row(kind, opts)
		opts.x, opts.y, opts.width = 18, y, W
		local _, h = Widgets[kind](Widgets, card, opts)
		y = y + h
	end
	local function twistValues()
		local v = {}
		for idx, spellID in pairs(SP.AirTotems or {}) do
			if SP.TwistTotemIcons and SP.TwistTotemIcons[idx] then v[idx] = GetSpellInfo(spellID) or ("Air totem " .. idx) end
		end
		return v
	end
	local function twistOrder() local o = {}; for k in pairs(twistValues()) do o[#o + 1] = k end; table.sort(o); return o end
	local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
	local function soundList() return LSM and LSM:List("sound") or { "Raid Warning" } end
	local function soundValues() local v = {}; for _, n in ipairs(soundList()) do v[n] = n end; return v end
	local function disabled() return not SP.opt.enableTotemTwisting end
	local function noSound() return not SP.opt.enableTotemTwisting or not SP.opt.twistSoundEnabled end

	row("Dropdown", { label = "Twist totem", disabled = disabled, get = function() return SP.opt.twistTotem or 2 end,
		set = function(v) SP.opt.twistTotem = v; safecall("UpdateMiniTotemBar"); safecall("UpdateSPMacros"); notify() end,
		values = twistValues, order = twistOrder })
	row("Toggle", { label = "Whole seconds", desc = "Show the twist countdown as whole seconds instead of decimals (8 instead of 8.3)", disabled = disabled, get = function() return SP.opt.twistTimerNoDecimals and true or false end,
		set = function(v) SP.opt.twistTimerNoDecimals = v; notify() end })
	row("Toggle", { label = "Warning sound", desc = "Play a sound shortly before the Windfury buff runs out", disabled = disabled, get = function() return SP.opt.twistSoundEnabled and true or false end,
		set = function(v) SP.opt.twistSoundEnabled = v; notify(); Widgets:RefreshAll(card) end })
	row("Slider", { label = "Warn at (sec)", desc = "How many seconds of Windfury buff are left when the sound plays", min = 0, max = 10, step = 1, disabled = noSound, get = function() return SP.opt.twistSoundThreshold or 3 end,
		set = function(v) SP.opt.twistSoundThreshold = v; notify() end })
	row("Dropdown", { label = "Sound", disabled = noSound, get = function() return SP.opt.twistSoundName or "Raid Warning" end,
		set = function(v) SP.opt.twistSoundName = v; notify() end,
		values = soundValues, order = soundList })
	row("Slider", { label = "Volume", min = 0, max = 100, step = 1, disabled = noSound, get = function() return SP.opt.twistSoundVolume or 100 end,
		set = function(v) SP.opt.twistSoundVolume = v; notify() end })
	row("Button", { label = "Hear it", buttonText = "Test sound", disabled = noSound,
		func = function()
			if SP.PlaySoundWithVolume and SP.GetSoundFile then
				pcall(SP.PlaySoundWithVolume, SP, SP:GetSoundFile(SP.opt.twistSoundName or "Raid Warning"), SP.opt.twistSoundVolume or 100, true)
			end
		end })
	return y
end

-- Windfury Companion: explain the melee-side WeakAura, show what it unlocks on
-- the Air slot, and hand out the import string / link.
function SP.Wizard.BuildWFCompanionStep(card, inner, y)
	local comp = SP.Companions and SP.Companions.windfury
	local S = 1.5
	local SIZE = math.floor(40 * S)

	-- ---- preview: the Air slot without / with a melee running the aura ----
	-- Drawn exactly like the Party Buff Tracker mock, from the SAME options the
	-- user just chose there (dots on/off + position, numbers on/off + size +
	-- element color + on-icon vs separate frame).
	local SIZE = 46
	local ROGUE = { r = 1.00, g = 0.96, b = 0.41 }
	local AIR = { 1.0, 1.0, 1.0 }
	local function airSlot(x, yy)
		local ZOOM = 1.4
		local holder = CreateFrame("Frame", nil, inner); holder:SetSize(SIZE * ZOOM, SIZE * ZOOM); holder:SetPoint("CENTER", inner, "CENTER", x, yy)
		local b = CreateFrame("Frame", nil, holder); b:SetSize(SIZE, SIZE); b:SetPoint("CENTER", holder, "CENTER"); b:SetScale(ZOOM)
		local bg = b:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(b); bg:SetColorTexture(0, 0, 0, 0.6)
		local ic = b:CreateTexture(nil, "ARTWORK"); ic:SetPoint("TOPLEFT", 2, -2); ic:SetPoint("BOTTOMRIGHT", -2, 2)
		ic:SetTexture("Interface\\Icons\\Spell_Nature_Windfury"); ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		Core:MakeBorder(b, "border")
		local key = b:CreateFontString(nil, "OVERLAY"); key:SetFont("Fonts\\ARIALN.TTF", 9, "OUTLINE"); key:SetPoint("TOPRIGHT", b, "TOPRIGHT", 1, 0); key:SetText("S-4"); key:SetTextColor(0.9, 0.9, 0.9)
		local dots = {}
		for d = 1, 4 do
			local dot = b:CreateTexture(nil, "OVERLAY", nil, 7); dot:SetTexture("Interface\\AddOns\\ShamanPower\\textures\\dot"); dot:SetSize(6, 6); dot:Hide(); dots[d] = dot
		end
		local n = b:CreateFontString(nil, "OVERLAY", nil, 7); n:SetPoint("CENTER", b, "CENTER", 0, 0); n:Hide()
		-- separate counter frame (if the user chose that style)
		local cf = CreateFrame("Frame", nil, holder); cf:SetSize(40, 40); cf:SetPoint("TOP", b, "BOTTOM", 0, -6); cf:Hide()
		local cbg = cf:CreateTexture(nil, "BACKGROUND"); cbg:SetAllPoints(cf); cbg:SetColorTexture(0, 0, 0, 0.7); Core:MakeBorder(cf, "border")
		local ct = cf:CreateFontString(nil, "OVERLAY"); ct:SetPoint("CENTER", cf, "CENTER", 0, 0)
		local cl = cf:CreateFontString(nil, "OVERLAY"); cl:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE"); cl:SetPoint("BOTTOM", cf, "BOTTOM", 0, 4); cl:SetText("Air"); cl:SetTextColor(unpack(AIR))
		return { holder = holder, f = b, dots = dots, n = n, cf = cf, cbg = cbg, ct = ct, cl = cl }
	end
	local function placeDots(sl)
		local pos = SP.opt.partyDotPosition or "corners"
		local size, gap = 6, 2
		local span = 4 * size + 3 * gap
		for d = 1, 4 do
			local dot, along = sl.dots[d], (d - 1) * (size + gap)
			dot:ClearAllPoints()
			if pos == "above" then dot:SetPoint("BOTTOMLEFT", sl.f, "TOP", along - span / 2, 2)
			elseif pos == "below" then dot:SetPoint("TOPLEFT", sl.f, "BOTTOM", along - span / 2, -2)
			elseif pos == "left" then dot:SetPoint("TOPRIGHT", sl.f, "LEFT", -2, span / 2 - along)
			elseif pos == "right" then dot:SetPoint("TOPLEFT", sl.f, "RIGHT", 2, span / 2 - along)
			elseif d == 1 then dot:SetPoint("TOPLEFT", sl.f, "TOPLEFT", 1, -1)
			elseif d == 2 then dot:SetPoint("TOPRIGHT", sl.f, "TOPRIGHT", -1, -1)
			elseif d == 3 then dot:SetPoint("BOTTOMLEFT", sl.f, "BOTTOMLEFT", 1, 1)
			else dot:SetPoint("BOTTOMRIGHT", sl.f, "BOTTOMRIGHT", -1, 1) end
		end
	end
	-- paint a slot: `known` = the rogue runs the companion (dot 1 is the rogue)
	local function paint(sl, known)
		local rc = SP.opt.rangeCounter or {}
		local showDots, showNum = SP.opt.showPartyRangeDots and true or false, rc.enabled and true or false
		local separate = showNum and rc.location == "unlocked"
		local fontSize, useEle = rc.fontSize or 14, rc.useElementColors ~= false
		for d = 1, 4 do sl.dots[d]:Hide() end
		if known and showDots then sl.dots[1]:SetVertexColor(ROGUE.r, ROGUE.g, ROGUE.b); sl.dots[1]:Show() end
		local count = known and 1 or 0
		if showNum and not separate then
			sl.n:SetFont("Fonts\\FRIZQT__.TTF", fontSize, "OUTLINE")
			if useEle then sl.n:SetTextColor(unpack(AIR)) else sl.n:SetTextColor(1, 1, 1) end
			sl.n:SetText(tostring(count)); sl.n:Show()
		else sl.n:Hide() end
		if separate then
			sl.cf:Show(); sl.cf:SetScale(rc.scale or 1.0); sl.cf:SetAlpha(rc.opacity or 1.0)
			sl.cbg:SetShown(not rc.hideFrame); Core:SetBorderColor(sl.cf, rc.hideFrame and "windowBg" or "border")
			sl.cl:SetShown(not rc.hideLabel)
			if rc.hideFrame and rc.hideLabel then sl.cf:SetSize(30, 25) elseif rc.hideLabel then sl.cf:SetSize(40, 35) else sl.cf:SetSize(40, 40) end
			sl.ct:SetFont("Fonts\\FRIZQT__.TTF", fontSize, "OUTLINE")
			if useEle then sl.ct:SetTextColor(unpack(AIR)) else sl.ct:SetTextColor(1, 1, 1) end
			sl.ct:SetText(tostring(count))
		else sl.cf:Hide() end
	end
	-- Two rows: icon on the left, its explanation to the right (full width).
	local IX = -(inner:GetWidth() / 2) + 70
	local without = airSlot(IX, 105)
	local with    = airSlot(IX, -35)
	local textW = inner:GetWidth() - 170
	local function cap(anchor, text, color)
		local t = inner:CreateFontString(nil, "OVERLAY"); t:SetFontObject(Core.fonts.row); t:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 26, -4)
		t:SetWidth(textW); t:SetJustifyH("LEFT"); t:SetWordWrap(true); t:SetText(text); if color then t:SetTextColor(Core:Color(color)) end
		return t
	end
	local c1 = cap(without.holder, "Rogue WITHOUT the aura", "textDim")
	local c2 = cap(with.holder, "Rogue WITH the aura", "accentHi")
	local e1 = inner:CreateFontString(nil, "OVERLAY"); e1:SetFontObject(Core.fonts.rowDim); e1:SetPoint("TOPLEFT", c1, "BOTTOMLEFT", 0, -6); e1:SetWidth(textW); e1:SetJustifyH("LEFT"); e1:SetWordWrap(true)
	e1:SetText("Nothing shows - the addon cannot see Windfury on his weapon, so he is not counted and has no dot.")
	local e2 = inner:CreateFontString(nil, "OVERLAY"); e2:SetFontObject(Core.fonts.rowDim); e2:SetPoint("TOPLEFT", c2, "BOTTOMLEFT", 0, -6); e2:SetWidth(textW); e2:SetJustifyH("LEFT"); e2:SetWordWrap(true)
	e2:SetText("He is counted, and his dot shows in his class color while he is in range of your totem (red when he is not).")
	local modeNote = inner:CreateFontString(nil, "OVERLAY"); modeNote:SetFontObject(Core.fonts.tiny); modeNote:SetPoint("TOP", inner, "TOP", 0, -8); modeNote:SetTextColor(Core:Color("textDim"))
	local lastPos
	inner:SetScript("OnUpdate", function()
		local pos = SP.opt.partyDotPosition or "corners"
		if pos ~= lastPos then lastPos = pos; placeDots(without); placeDots(with) end
		paint(without, false); paint(with, true)
		local rc = SP.opt.rangeCounter or {}
		local d, n = SP.opt.showPartyRangeDots, rc.enabled
		modeNote:SetText("Shown with your Party Buff Tracker choice: " .. ((d and n) and "dots and numbers" or d and "dots only" or n and "numbers only" or "|cffff6060nothing (it is switched off)|r"))
	end)

	local legend = inner:CreateFontString(nil, "OVERLAY"); legend:SetFontObject(Core.fonts.rowDim)
	legend:SetPoint("BOTTOMLEFT", inner, "BOTTOMLEFT", 12, 14); legend:SetPoint("BOTTOMRIGHT", inner, "BOTTOMRIGHT", -12, 14)
	legend:SetJustifyH("CENTER"); legend:SetWordWrap(true)
	legend:SetText("The number on the Air slot is how many melee have Windfury; each dot is one of them, in their class color when in range and red when not.")

	-- ---- card: the one thing people get wrong, said loudly ----
	local callout = CreateFrame("Frame", nil, card); callout:SetPoint("TOPLEFT", card, "TOPLEFT", 18, -y); callout:SetPoint("TOPRIGHT", card, "TOPRIGHT", -18, -y)
	Core:SolidTex(callout, "warn", "BACKGROUND", 0.10); Core:MakeBorder(callout, "warn")
	local calW = card:GetWidth() - 36 - 24
	local h = callout:CreateFontString(nil, "OVERLAY"); h:SetFontObject(Core.fonts.row); h:SetPoint("TOPLEFT", callout, "TOPLEFT", 12, -10); h:SetWidth(calW)
	h:SetJustifyH("LEFT"); h:SetWordWrap(true); h:SetTextColor(Core:Color("warn"))
	h:SetText("THIS IS FOR YOUR MELEE - NOT FOR YOU")
	local body = callout:CreateFontString(nil, "OVERLAY"); body:SetFontObject(Core.fonts.rowDim); body:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -6); body:SetWidth(calW)
	body:SetJustifyH("LEFT"); body:SetWordWrap(true)
	body:SetText("You do NOT install this. Send it to the rogues, warriors and paladins in your group. They import it into WeakAuras once, nothing to set up, and from then on your totem bar can see their Windfury.")
	callout:SetHeight(20 + h:GetStringHeight() + 6 + body:GetStringHeight() + 12)
	y = y + callout:GetHeight() + 14

	local b1 = Core:MakeButton(card, "Show the WeakAura string to copy", 10, true)
	b1:SetPoint("TOPLEFT", card, "TOPLEFT", 18, -y); b1:SetPoint("TOPRIGHT", card, "TOPRIGHT", -18, -y)
	b1:SetScript("OnClick", function()
		if comp and SP.ShowExportDialog then SP:ShowExportDialog(comp.str, "send this to your melee - they import it in WeakAuras", "Windfury Companion") end
	end)
	y = y + 38
	local b2 = Core:MakeButton(card, "Show the wago.io link instead", 10, false)
	b2:SetPoint("TOPLEFT", card, "TOPLEFT", 18, -y); b2:SetPoint("TOPRIGHT", card, "TOPRIGHT", -18, -y)
	b2:SetScript("OnClick", function()
		if comp and SP.ShowExportDialog then SP:ShowExportDialog(comp.url, "send this link to your melee", "Windfury Companion") end
	end)
	y = y + 38
	local note = card:CreateFontString(nil, "OVERLAY"); note:SetFontObject(Core.fonts.tiny); note:SetPoint("TOPLEFT", card, "TOPLEFT", 18, -y)
	note:SetWidth(card:GetWidth() - 36); note:SetJustifyH("LEFT"); note:SetWordWrap(true); note:SetTextColor(Core:Color("textDim"))
	note:SetText("Need it again later? It lives in Settings under Windfury Companion.")
	y = y + 30
	return y
end

-- Party Buff Tracker: the totem bar with a simulated 5-man group moving in
-- and out of range of your totems, drawn the way the module draws it
-- (class-colored corner dots, red when out of range, count in the middle).
function SP.Wizard.BuildPartyBuffStep(card, inner, y)
	local Widgets = ns.Widgets
	local SIZE, STEP = 46, 62
	local ELE = {
		{ icon = "Interface\\Icons\\Spell_Nature_EarthBindTotem",       col = { 0.2, 0.9, 0.2 } },   -- Strength of Earth uses the EarthBind art
		{ icon = "Interface\\Icons\\Spell_Fire_TotemOfWrath",          col = { 0.9, 0.2, 0.2 } },
		{ icon = "Interface\\Icons\\Spell_Nature_ManaRegenTotem",      col = { 0.2, 0.6, 1.0 } },
		{ icon = "Interface\\Icons\\Spell_Nature_Windfury",            col = { 1.0, 1.0, 1.0 } },
	}
	-- Your party: class color + a personal wander pattern.
	local PARTY = {
		{ name = "Rogue",   r = 1.00, g = 0.96, b = 0.41, period = 5.0, off = 0.0, wf = true },
		{ name = "Warrior", r = 0.78, g = 0.61, b = 0.43, period = 7.0, off = 2.0, wf = true },
		{ name = "Priest",  r = 1.00, g = 1.00, b = 1.00, period = 9.0, off = 4.5 },
		{ name = "Hunter",  r = 0.67, g = 0.83, b = 0.45, period = 6.0, off = 1.0 },
	}
	local bar = CreateFrame("Frame", nil, inner); bar:SetSize(4 * STEP - (STEP - SIZE), SIZE); bar:SetPoint("CENTER", inner, "CENTER", 0, 30)
	local slots = {}
	for i, e in ipairs(ELE) do
		local b = CreateFrame("Frame", nil, bar); b:SetSize(SIZE, SIZE); b:SetPoint("LEFT", bar, "LEFT", (i - 1) * STEP, 0)
		local bg = b:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(b); bg:SetColorTexture(0, 0, 0, 0.6)
		local ic = b:CreateTexture(nil, "ARTWORK"); ic:SetPoint("TOPLEFT", 2, -2); ic:SetPoint("BOTTOMRIGHT", -2, 2); ic:SetTexture(e.icon); ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		Core:MakeBorder(b, "border")
		local key = b:CreateFontString(nil, "OVERLAY"); key:SetFont("Fonts\\ARIALN.TTF", 9, "OUTLINE"); key:SetPoint("TOPRIGHT", b, "TOPRIGHT", 1, 0); key:SetText("S-" .. i); key:SetTextColor(0.9, 0.9, 0.9)
		local dots = {}
		for d = 1, 4 do
			local dot = b:CreateTexture(nil, "OVERLAY", nil, 7); dot:SetTexture("Interface\\AddOns\\ShamanPower\\textures\\dot"); dot:SetSize(6, 6)
			dots[d] = dot
		end
		local n = b:CreateFontString(nil, "OVERLAY", nil, 7); n:SetPoint("CENTER", b, "CENTER", 0, 0)
		slots[i] = { e = e, f = b, dots = dots, n = n }
	end
	-- "Separate movable frames" counter style: one small frame per element,
	-- drawn like CreateRangeCounterFrame (dark backdrop, number, element label).
	local ENAMES = { "Earth", "Fire", "Water", "Air" }
	local cframes = {}
	for i = 1, 4 do
		local f = CreateFrame("Frame", nil, inner); f:SetSize(40, 40); f:SetPoint("TOP", bar, "BOTTOM", (i - 2.5) * 55, -34)
		local fbg = f:CreateTexture(nil, "BACKGROUND"); fbg:SetAllPoints(f); fbg:SetColorTexture(0, 0, 0, 0.7)
		Core:MakeBorder(f, "border")
		local t = f:CreateFontString(nil, "OVERLAY"); t:SetPoint("CENTER", f, "CENTER", 0, 0)
		local l = f:CreateFontString(nil, "OVERLAY"); l:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE"); l:SetPoint("BOTTOM", f, "BOTTOM", 0, 4); l:SetText(ENAMES[i])
		l:SetTextColor(unpack(ELE[i].col))
		cframes[i] = { f = f, bg = fbg, t = t, l = l }
		f:Hide()
	end
	-- who is where: a member is "in range" of an element when their wander wave is positive
	local function inRange(m, element, t)
		local phase = (t + m.off + element * 1.3) / m.period
		return math.sin(phase * 2 * math.pi) > -0.35
	end
	local legend = inner:CreateFontString(nil, "OVERLAY"); legend:SetFontObject(Core.fonts.rowDim)
	legend:SetPoint("BOTTOMLEFT", inner, "BOTTOMLEFT", 12, 14); legend:SetPoint("BOTTOMRIGHT", inner, "BOTTOMRIGHT", -12, 14)
	legend:SetJustifyH("CENTER"); legend:SetWordWrap(true)
	legend:SetText("Each corner dot is a party member, in their class color when your totem is reaching them and red when it is not. The number is how many it reaches. Windfury (Air) only knows about melee running the companion aura - next step.")
	local names = inner:CreateFontString(nil, "OVERLAY"); names:SetFontObject(Core.fonts.tiny); names:SetPoint("TOP", bar, "BOTTOM", 0, -12)
	names:SetText("|cffFFF569Rogue|r  |cffC79C6EWarrior|r  |cffFFFFFFPriest|r  |cffABD473Hunter|r"); names:SetTextColor(Core:Color("textDim"))

	-- dot placement, same geometry as ShamanPower:PositionPartyDots (6px dots here)
	local lastDotPos
	local function placeDots()
		local pos = SP.opt.partyDotPosition or "corners"
		local size, gap = 6, 2
		local span = 4 * size + 3 * gap
		for _, s in ipairs(slots) do
			for d = 1, 4 do
				local dot, along = s.dots[d], (d - 1) * (size + gap)
				dot:ClearAllPoints()
				if pos == "above" then dot:SetPoint("BOTTOMLEFT", s.f, "TOP", along - span / 2, 2)
				elseif pos == "below" then dot:SetPoint("TOPLEFT", s.f, "BOTTOM", along - span / 2, -2)
				elseif pos == "left" then dot:SetPoint("TOPRIGHT", s.f, "LEFT", -2, span / 2 - along)
				elseif pos == "right" then dot:SetPoint("TOPLEFT", s.f, "RIGHT", 2, span / 2 - along)
				elseif d == 1 then dot:SetPoint("TOPLEFT", s.f, "TOPLEFT", 1, -1)
				elseif d == 2 then dot:SetPoint("TOPRIGHT", s.f, "TOPRIGHT", -1, -1)
				elseif d == 3 then dot:SetPoint("BOTTOMLEFT", s.f, "BOTTOMLEFT", 1, 1)
				else dot:SetPoint("BOTTOMRIGHT", s.f, "BOTTOMRIGHT", -1, 1) end
			end
		end
		lastDotPos = pos
	end
	local t = 0
	bar:SetScript("OnUpdate", function(_, el)
		t = t + el
		if (SP.opt.partyDotPosition or "corners") ~= lastDotPos then placeDots() end
		local showDots = SP.opt.showPartyRangeDots and true or false
		local rc = SP.opt.rangeCounter or {}
		local showNum = rc.enabled and true or false
		local fontSize = rc.fontSize or 14
		local useEle = rc.useElementColors ~= false
		local separate = showNum and (rc.location == "unlocked")
		local cScale, cAlpha = rc.scale or 1.0, rc.opacity or 1.0
		for i, s in ipairs(slots) do
			local count = 0
			for d, m in ipairs(PARTY) do
				local dot = s.dots[d]
				local known = (i ~= 4) or m.wf          -- Windfury: only companion users are visible
				if not known then
					dot:Hide()
				else
					local ok = inRange(m, i, t)
					if ok then count = count + 1; dot:SetVertexColor(m.r, m.g, m.b) else dot:SetVertexColor(1, 0, 0) end
					dot:SetShown(showDots)
				end
			end
			if showNum and not separate then
				s.n:SetFont("Fonts\\FRIZQT__.TTF", fontSize, "OUTLINE")
				if useEle then s.n:SetTextColor(unpack(s.e.col)) else s.n:SetTextColor(1, 1, 1) end
				s.n:SetText(tostring(count)); s.n:Show()
			else
				s.n:Hide()
			end
			local c = cframes[i]
			if separate then
				c.f:Show(); c.f:SetScale(cScale); c.f:SetAlpha(cAlpha)
				c.bg:SetShown(not rc.hideFrame); Core:SetBorderColor(c.f, rc.hideFrame and "windowBg" or "border")
				c.l:SetShown(not rc.hideLabel)
				if rc.hideFrame and rc.hideLabel then c.f:SetSize(30, 25) elseif rc.hideLabel then c.f:SetSize(40, 35) else c.f:SetSize(40, 40) end
				c.t:SetFont("Fonts\\FRIZQT__.TTF", fontSize, "OUTLINE")
				if useEle then c.t:SetTextColor(unpack(s.e.col)) else c.t:SetTextColor(1, 1, 1) end
				c.t:SetText(tostring(count))
			else
				c.f:Hide()
			end
		end
	end)

	-- ---- controls ----
	local W = card:GetWidth() - 36
	local function row(kind, opts)
		opts.x, opts.y, opts.width = 18, y, W
		local _, h = Widgets[kind](Widgets, card, opts)
		y = y + h
	end
	local function rc() SP.opt.rangeCounter = SP.opt.rangeCounter or {}; return SP.opt.rangeCounter end
	local function upd() safecall("UpdatePartyRangeDots"); safecall("UpdateRangeCounters"); notify(); Widgets:RefreshAll(card) end
	row("Dropdown", { label = "Show on the totem bar",
		get = function()
			local d, n = SP.opt.showPartyRangeDots, SP.opt.rangeCounter and SP.opt.rangeCounter.enabled
			if d and n then return "both" elseif d then return "dots" elseif n then return "numbers" else return "none" end
		end,
		set = function(v)
			local r = rc()
			SP.opt.showPartyRangeDots = (v == "dots" or v == "both")
			r.enabled = (v == "numbers" or v == "both")
			safecall("UpdatePartyDotPositions")
			upd()
		end,
		values = function() return { dots = "Dots only", numbers = "Numbers only", both = "Dots and numbers", none = "Nothing" } end,
		order = function() return { "dots", "numbers", "both", "none" } end })
	row("Dropdown", { label = "Dot position", disabled = function() return not SP.opt.showPartyRangeDots end,
		get = function() return SP.opt.partyDotPosition or "corners" end,
		set = function(v) SP.opt.partyDotPosition = v; safecall("UpdatePartyDotPositions"); upd() end,
		values = function() return { corners = "Icon corners", above = "Row above the icon", below = "Row below the icon", left = "Column left of the icon", right = "Column right of the icon" } end,
		order = function() return { "corners", "above", "below", "left", "right" } end })
	local function noNum() return not (SP.opt.rangeCounter and SP.opt.rangeCounter.enabled) end
	row("Toggle", { label = "Color numbers by element", disabled = noNum, get = function() return not (SP.opt.rangeCounter and SP.opt.rangeCounter.useElementColors == false) end,
		set = function(v) rc().useElementColors = v; upd() end })
	row("Slider", { label = "Number size", min = 8, max = 32, step = 1, disabled = noNum, get = function() return (SP.opt.rangeCounter and SP.opt.rangeCounter.fontSize) or 14 end,
		set = function(v) rc().fontSize = v; upd() end })
	row("Dropdown", { label = "Numbers shown", disabled = noNum, get = function() return (SP.opt.rangeCounter and SP.opt.rangeCounter.location) or "icon" end,
		set = function(v) rc().location = v; upd() end,
		values = function() return { icon = "On the totem icon", unlocked = "In separate movable frames" } end, order = function() return { "icon", "unlocked" } end })
	local function noSep() return noNum() or (SP.opt.rangeCounter and SP.opt.rangeCounter.location) ~= "unlocked" end
	row("Toggle", { label = "    Show frame background", disabled = noSep, get = function() return not (SP.opt.rangeCounter and SP.opt.rangeCounter.hideFrame) end,
		set = function(v) rc().hideFrame = not v; safecall("UpdateRangeCounterFrameStyle"); upd() end })
	row("Toggle", { label = "    Show element label", disabled = noSep, get = function() return not (SP.opt.rangeCounter and SP.opt.rangeCounter.hideLabel) end,
		set = function(v) rc().hideLabel = not v; safecall("UpdateRangeCounterFrameStyle"); upd() end })
	row("Slider", { label = "    Frame scale", min = 0.5, max = 3.0, step = 0.1, disabled = noSep, get = function() return (SP.opt.rangeCounter and SP.opt.rangeCounter.scale) or 1.0 end,
		set = function(v)
			rc().scale = v
			for el = 1, 4 do
				local f = SP.rangeCounterFrames and SP.rangeCounterFrames[el]
				if f then
					if SP.SetFrameScaleKeepCenter then pcall(SP.SetFrameScaleKeepCenter, SP, f, v) else f:SetScale(v) end
					if SP.SaveRangeCounterPosition then pcall(SP.SaveRangeCounterPosition, SP, el) end
				end
			end
			upd()
		end })
	row("Slider", { label = "    Frame opacity", min = 10, max = 100, step = 5, disabled = noSep, get = function() return math.floor(((SP.opt.rangeCounter and SP.opt.rangeCounter.opacity) or 1.0) * 100 + 0.5) end,
		set = function(v)
			rc().opacity = v / 100
			for el = 1, 4 do local f = SP.rangeCounterFrames and SP.rangeCounterFrames[el]; if f then f:SetAlpha(v / 100) end end
			upd()
		end })
	return y
end

-- Raid Cooldowns: a clickable copy of the caller bar. Pressing a caller shows
-- what the assigned player sees (the big USE ... NOW! alert, sound) and puts
-- the button on cooldown, exactly per the module's options.
function SP.Wizard.BuildRaidCDStep(card, inner, y)
	local Widgets = ns.Widgets
	local horde = UnitFactionGroup and UnitFactionGroup("player") == "Horde"
	local BL_ICON = horde and "Interface\\Icons\\Spell_Nature_Bloodlust" or "Interface\\Icons\\Ability_Shaman_Heroism"
	local BL_NAME = horde and "BLOODLUST" or "HEROISM"
	local MT_ICON = "Interface\\Icons\\Spell_Frost_SummonWaterElemental"
	local DRUM_ICON = "Interface\\Icons\\INV_Misc_Drum_02"
	local CALLERS = {
		{ key = "bl",   icon = BL_ICON,   border = { 1, 0.5, 0 },       who = "Srumar",  alert = "USE " .. BL_NAME .. " NOW!", cd = 14 },
		{ key = "mt1",  icon = MT_ICON,   border = { 0.3, 0.6, 1 },     who = "Group 1", alert = "USE MANA TIDE NOW!",        cd = 10 },
		{ key = "mt2",  icon = MT_ICON,   border = { 0.3, 0.6, 1 },     who = "Group 3", alert = "USE MANA TIDE NOW!",        cd = 10 },
		{ key = "drum", icon = DRUM_ICON, border = { 0.9, 0.65, 0.2 },  who = "Kabum",   alert = "USE DRUMS NOW!",            cd = 8 },
	}
	local function O(k, d) local v = SP.opt[k]; if v == nil then return d end; return v end

	-- ---- the caller bar ----
	local bar = CreateFrame("Frame", nil, inner); bar:SetPoint("CENTER", inner, "CENTER", 0, -40)
	local bbg = bar:CreateTexture(nil, "BACKGROUND"); bbg:SetAllPoints(bar); bbg:SetColorTexture(0, 0, 0, 0.7)
	Core:MakeBorder(bar, "border")
	bar.bg = bbg
	local buttons, alertFn = {}, nil
	for i, c in ipairs(CALLERS) do
		local b = CreateFrame("Button", nil, bar); b:SetSize(40, 40); b:SetPoint("TOPLEFT", bar, "TOPLEFT", 8 + (i - 1) * 44, -8)
		local ic = b:CreateTexture(nil, "ARTWORK"); ic:SetPoint("TOPLEFT", 3, -3); ic:SetPoint("BOTTOMRIGHT", -3, 3); ic:SetTexture(c.icon); ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
			local t = b:CreateTexture(nil, "BORDER"); t:SetColorTexture(c.border[1], c.border[2], c.border[3], 1)
			if side == "TOP" or side == "BOTTOM" then t:SetHeight(3); t:SetPoint(side .. "LEFT", 0, 0); t:SetPoint(side .. "RIGHT", 0, 0)
			else t:SetWidth(3); t:SetPoint("TOP" .. side, 0, 0); t:SetPoint("BOTTOM" .. side, 0, 0) end
		end
		local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(ic); hl:SetColorTexture(1, 1, 1, 0.3)
		local cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate"); cd:SetAllPoints(ic); cd:SetDrawEdge(false); cd:SetDrawBling(false); cd:SetSwipeColor(0, 0, 0, 0.8)
		if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end
		local lbl = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); lbl:SetPoint("TOP", b, "BOTTOM", 0, -2); lbl:SetText(c.who)
		b:SetScript("OnClick", function() if alertFn then alertFn(c, b) end end)
		b:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText("Call " .. c.alert:gsub("^USE ", ""):gsub(" NOW!$", ""):lower():gsub("^%l", string.upper)); GameTooltip:AddLine("Will call: " .. c.who, 0, 1, 0); GameTooltip:Show() end)
		b:SetScript("OnLeave", function() GameTooltip:Hide() end)
		buttons[i] = { f = b, icon = ic, cd = cd, until_ = 0 }
	end
	bar:SetSize(#CALLERS * 44 + 16, 62)

	-- ---- the alert the assigned player sees (drawn inside the box) ----
	local alert = CreateFrame("Frame", nil, inner); alert:SetSize(150, 150); alert:SetPoint("CENTER", inner, "CENTER", 0, 70); alert:Hide()
	local aIcon = alert:CreateTexture(nil, "ARTWORK"); aIcon:SetSize(96, 96); aIcon:SetPoint("CENTER", 0, 10); aIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local aText = alert:CreateFontString(nil, "OVERLAY"); aText:SetFont("Fonts\\FRIZQT__.TTF", 22, "OUTLINE"); aText:SetPoint("TOP", aIcon, "BOTTOM", 0, -6); aText:SetTextColor(1, 0.3, 0)
	local aWho = alert:CreateFontString(nil, "OVERLAY"); aWho:SetFontObject(Core.fonts.tiny); aWho:SetPoint("TOP", aText, "BOTTOM", 0, -4); aWho:SetTextColor(Core:Color("textDim"))
	local hint = inner:CreateFontString(nil, "OVERLAY"); hint:SetFontObject(Core.fonts.rowDim); hint:SetPoint("CENTER", inner, "CENTER", 0, 70)
	hint:SetText("Click a caller button below"); hint:SetWidth(inner:GetWidth() - 40); hint:SetJustifyH("CENTER"); hint:SetWordWrap(true)
	local legend = inner:CreateFontString(nil, "OVERLAY"); legend:SetFontObject(Core.fonts.rowDim)
	legend:SetPoint("BOTTOMLEFT", inner, "BOTTOMLEFT", 12, 14); legend:SetPoint("BOTTOMRIGHT", inner, "BOTTOMRIGHT", -12, 14)
	legend:SetJustifyH("CENTER"); legend:SetWordWrap(true)
	legend:SetText("Raid leaders, assistants and anyone you give control to see these buttons. One press and the assigned shaman or drummer gets this alert.")

	local alertT, alertUntil = 0, 0
	alertFn = function(c, b)
		local showIcon, showText, sound = O("raidCDShowWarningIcon", true), O("raidCDShowWarningText", true), O("raidCDPlaySound", true)
		-- the button goes on cooldown (if animation is on)
		for _, bt in ipairs(buttons) do
			if bt.f == b then
				bt.until_ = GetTime() + c.cd
				if O("raidCDShowButtonAnimation", true) then bt.cd:SetCooldown(GetTime(), c.cd); bt.icon:SetDesaturated(true) end
			end
		end
		if sound and SP.PlaySoundWithVolume then pcall(SP.PlaySoundWithVolume, SP, 8959, O("raidCDSoundVolume", 100), false) end
		if not showIcon and not showText then return end
		aIcon:SetTexture(c.icon); aIcon:SetShown(showIcon)
		aText:SetText(c.alert); aText:SetShown(showText)
		aWho:SetText("what " .. c.who .. " sees")
		alertT, alertUntil = 0, GetTime() + 5
		alert:Show(); hint:Hide()
	end
	inner:SetScript("OnUpdate", function(_, e)
		-- panel style / scale / opacity follow the options live
		local hide = O("raidCDButtonHideFrame", nil) and true or false
		bar.bg:SetShown(not hide); Core:SetBorderColor(bar, hide and "windowBg" or "border")
		bar:SetScale(O("raidCDButtonScale", 1.0)); bar:SetAlpha(O("raidCDButtonOpacity", 1.0))
		for _, bt in ipairs(buttons) do
			if bt.until_ > 0 and GetTime() >= bt.until_ then bt.until_ = 0; bt.cd:Clear(); bt.icon:SetDesaturated(false) end
			if not O("raidCDShowButtonAnimation", true) then bt.cd:Clear(); bt.icon:SetDesaturated(false) end
		end
		if alert:IsShown() then
			alertT = alertT + e
			alert:SetAlpha(0.6 + 0.4 * math.sin(alertT * 4))
			local s = 1 + 0.05 * math.sin(alertT * 5); aIcon:SetSize(96 * s, 96 * s)
			if GetTime() >= alertUntil then alert:Hide(); hint:Show() end
		end
	end)

	-- ---- the requirement people miss, said in red ----
	local req = CreateFrame("Frame", nil, card); req:SetPoint("TOPLEFT", card, "TOPLEFT", 18, -y); req:SetPoint("TOPRIGHT", card, "TOPRIGHT", -18, -y)
	Core:SolidTex(req, "warn", "BACKGROUND", 0.10); Core:MakeBorder(req, "warn")
	local reqW = card:GetWidth() - 36 - 24
	local rh = req:CreateFontString(nil, "OVERLAY"); rh:SetFontObject(Core.fonts.row); rh:SetPoint("TOPLEFT", req, "TOPLEFT", 12, -10); rh:SetWidth(reqW)
	rh:SetJustifyH("LEFT"); rh:SetWordWrap(true); rh:SetTextColor(1, 0.25, 0.25)
	rh:SetText("CALLERS NEED SHAMANPOWER TOO - EVEN IF THEY ARE NOT A SHAMAN")
	local rb = req:CreateFontString(nil, "OVERLAY"); rb:SetFontObject(Core.fonts.rowDim); rb:SetPoint("TOPLEFT", rh, "BOTTOMLEFT", 0, -6); rb:SetWidth(reqW)
	rb:SetJustifyH("LEFT"); rb:SetWordWrap(true)
	rb:SetText("Callers do not have to be shamans: a warrior raid leader or a mage you give control to can call for your Bloodlust, Mana Tide or Drums. But whoever calls must have |cffE6EAF0ShamanPower|r installed with the |cffE6EAF0Raid Cooldowns|r module enabled in their AddOns list - otherwise they see no buttons at all. Tell them.")
	req:SetHeight(20 + rh:GetStringHeight() + 6 + rb:GetStringHeight() + 12)
	y = y + req:GetHeight() + 14

	-- ---- options ----
	local W = card:GetWidth() - 36
	local function row(kind, opts)
		opts.x, opts.y, opts.width = 18, y, W
		local _, h = Widgets[kind](Widgets, card, opts)
		y = y + h
	end
	local function upd(fn) if fn then safecall(fn) end; notify() end
	row("Slider", { label = "Button size", min = 0.5, max = 2.0, step = 0.05, get = function() return O("raidCDButtonScale", 1.0) end,
		set = function(v) SP.opt.raidCDButtonScale = v; upd("UpdateCallerButtonScale") end })
	row("Slider", { label = "Button opacity", min = 0.1, max = 1.0, step = 0.05, get = function() return O("raidCDButtonOpacity", 1.0) end,
		set = function(v) SP.opt.raidCDButtonOpacity = v; upd("UpdateCallerButtonOpacity") end })
	row("Toggle", { label = "Show panel behind buttons", get = function() return not O("raidCDButtonHideFrame", nil) end,
		set = function(v) SP.opt.raidCDButtonHideFrame = (not v) or nil; upd("UpdateCallerButtonFrameStyle") end })
	row("Toggle", { label = "Cooldown swipe on buttons", get = function() return O("raidCDShowButtonAnimation", true) end,
		set = function(v) SP.opt.raidCDShowButtonAnimation = v; upd() end })
	row("Toggle", { label = "Alert: big icon", get = function() return O("raidCDShowWarningIcon", true) end,
		set = function(v) SP.opt.raidCDShowWarningIcon = v; upd() end })
	row("Toggle", { label = "Alert: USE ... NOW text", get = function() return O("raidCDShowWarningText", true) end,
		set = function(v) SP.opt.raidCDShowWarningText = v; upd() end })
	row("Toggle", { label = "Alert: sound", get = function() return O("raidCDPlaySound", true) end,
		set = function(v) SP.opt.raidCDPlaySound = v; upd(); Widgets:RefreshAll(card) end })
	row("Slider", { label = "Sound volume", min = 0, max = 100, step = 5, disabled = function() return not O("raidCDPlaySound", true) end,
		get = function() return O("raidCDSoundVolume", 100) end, set = function(v) SP.opt.raidCDSoundVolume = v; upd() end })
	return y
end

-- Reactive Totems: the three REAL alert frames, side by side, running a
-- looping raid scene (fear -> poison -> disease), with every option live.
function SP.Wizard.BuildReactiveStep(card, inner, y)
	local Widgets = ns.Widgets
	SP.Wizard._reactiveCard = card
	local function sv() ShamanPower_ReactiveTotems = ShamanPower_ReactiveTotems or {}; return ShamanPower_ReactiveTotems end
	local function get(k, d) local v = sv()[k]; if v == nil then return d end; return v end

	inner.previewInsetBottom = 90
	inner.previewMaxScale = 1.0
	local ORDER = { "fear", "poison", "disease" }
	local function fit()
		if not (inner:IsShown() and inner:GetWidth() > 0) then return end
		SP:ShowPreview("reactive", inner)
		local size = get("iconSize", 64)
		local gap = math.max(size + 40, 120)
		gap = math.min(gap, (inner:GetWidth() - size) / 2 - 10)
		for i, id in ipairs(ORDER) do
			local f = SP.reactiveFrames and SP.reactiveFrames[id]
			if f then
				f:ClearAllPoints(); f:SetPoint("CENTER", inner, "CENTER", (i - 2) * gap, 40)
				f:SetShown(f.currentDebuffName ~= nil)   -- the harness shows everything; only live alerts stay up
			end
		end
	end
	C_Timer.After(0.02, fit)

	-- ghost outlines so you can see where each alert lives even while hidden
	local ghosts = {}
	for i, id in ipairs(ORDER) do
		local g = CreateFrame("Frame", nil, inner); g:SetFrameLevel(inner:GetFrameLevel() + 1)
		Core:MakeBorder(g, "border"); g:SetAlpha(0.35)
		local t = g:CreateFontString(nil, "OVERLAY"); t:SetFontObject(Core.fonts.tiny); t:SetPoint("TOP", g, "BOTTOM", 0, -4)
		t:SetText(({ fear = "Tremor", poison = "Poison Cleansing", disease = "Disease Cleansing" })[id]); t:SetTextColor(Core:Color("textDim"))
		ghosts[i] = g
	end
	local story = inner:CreateFontString(nil, "OVERLAY"); story:SetFontObject(Core.fonts.row)
	story:SetPoint("BOTTOM", inner, "BOTTOM", 0, 62); story:SetWidth(inner:GetWidth() - 40); story:SetJustifyH("CENTER"); story:SetWordWrap(true)
	local legend = inner:CreateFontString(nil, "OVERLAY"); legend:SetFontObject(Core.fonts.rowDim)
	legend:SetPoint("BOTTOMLEFT", inner, "BOTTOMLEFT", 12, 14); legend:SetPoint("BOTTOMRIGHT", inner, "BOTTOMRIGHT", -12, 14)
	legend:SetJustifyH("CENTER"); legend:SetWordWrap(true)
	legend:SetText("An alert pops up the moment someone in your group gets feared, poisoned or diseased, and disappears when it is cleared or the right totem is already down.")
	inner:SetScript("OnUpdate", function()
		story:SetText(SP.reactiveDemoStatus or "")
		local size = get("iconSize", 64)
		for i, id in ipairs(ORDER) do
			local f = SP.reactiveFrames and SP.reactiveFrames[id]
			local g = ghosts[i]
			if f and f:GetParent() == inner then
				g:ClearAllPoints(); g:SetPoint("CENTER", f, "CENTER"); g:SetSize(size, size)
				g:SetShown(not f:IsShown())
			else g:Hide() end
		end
	end)

	local W = card:GetWidth() - 36
	local function row(kind, opts)
		opts.x, opts.y, opts.width = 18, y, W
		local _, h = Widgets[kind](Widgets, card, opts)
		y = y + h
	end
	local function upd(fn) if fn then safecall(fn) end; notify(); if SP.reactiveDemoActive then SP:ReactiveDemo(true) end; fit(); Widgets:RefreshAll(card) end
	local function off() return not get("enabled", true) end
	row("Toggle", { label = "Fear / Charm  (Tremor Totem)", disabled = off, get = function() return get("trackFear", true) end, set = function(v) sv().trackFear = v; upd("UpdateReactiveTotems") end })
	row("Toggle", { label = "Poison  (Poison Cleansing Totem)", disabled = off, get = function() return get("trackPoison", true) end, set = function(v) sv().trackPoison = v; upd("UpdateReactiveTotems") end })
	row("Toggle", { label = "Disease  (Disease Cleansing Totem)", disabled = off, get = function() return get("trackDisease", true) end, set = function(v) sv().trackDisease = v; upd("UpdateReactiveTotems") end })
	row("Toggle", { label = "Only alert inside instances", disabled = off, get = function() return get("onlyInInstance", false) end, set = function(v) sv().onlyInInstance = v; upd("UpdateReactiveTotems") end })
	row("Toggle", { label = "Hide when that totem is already down", disabled = off, get = function() return get("hideWhenTotemActive", true) end, set = function(v) sv().hideWhenTotemActive = v; upd("UpdateReactiveTotems") end })
	row("Slider", { label = "Icon size", min = 32, max = 256, step = 4, disabled = off, get = function() return get("iconSize", 64) end, set = function(v) sv().iconSize = v; upd("UpdateReactiveTotemAppearance") end })
	row("Slider", { label = "Opacity", min = 0.2, max = 1.0, step = 0.1, disabled = off, get = function() return get("opacity", 1.0) end, set = function(v) sv().opacity = v; upd("UpdateReactiveTotemAppearance") end })
	row("Slider", { label = "Text size", min = 8, max = 24, step = 1, disabled = off, get = function() return get("fontSize", 14) end, set = function(v) sv().fontSize = v; upd("UpdateReactiveTotemAppearance") end })
	row("Toggle", { label = "Show who has the debuff", disabled = off, get = function() return get("showDebuffName", true) end, set = function(v) sv().showDebuffName = v; upd("UpdateReactiveTotemAppearance") end })
	row("Toggle", { label = "Show totem name", disabled = off, get = function() return get("showTotemName", true) end, set = function(v) sv().showTotemName = v; upd("UpdateReactiveTotemAppearance") end })
	row("Toggle", { label = "Show border", disabled = off, get = function() return not get("hideBorder", false) end, set = function(v) sv().hideBorder = not v; upd("UpdateReactiveTotemAppearance") end })
	row("Toggle", { label = "Show background", disabled = off, get = function() return not get("hideBackground", false) end, set = function(v) sv().hideBackground = not v; upd("UpdateReactiveTotemAppearance") end })
	row("Toggle", { label = "Pulsing glow", disabled = off, get = function() return get("showGlow", true) end, set = function(v) sv().showGlow = v; upd("UpdateReactiveTotemAppearance") end })
	local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
	local function soundList() return LSM and LSM:List("sound") or { "Raid Warning" } end
	local function soundValues() local v = {}; for _, n in ipairs(soundList()) do v[n] = n end; return v end
	local function noSound() return off() or not get("playSound", false) end
	row("Toggle", { label = "Alert sound", disabled = off, get = function() return get("playSound", false) end, set = function(v) sv().playSound = v; upd() end })
	row("Dropdown", { label = "Sound", disabled = noSound, get = function() return get("soundName", "Raid Warning") end, set = function(v) sv().soundName = v; upd() end, values = soundValues, order = soundList })
	row("Slider", { label = "Volume", min = 0, max = 100, step = 5, disabled = noSound, get = function() return get("soundVolume", 100) end, set = function(v) sv().soundVolume = v; upd() end })
	row("Button", { label = "Hear it", buttonText = "Test sound", disabled = noSound,
		func = function() if SP.PlaySoundWithVolume and SP.GetSoundFile then pcall(SP.PlaySoundWithVolume, SP, SP:GetSoundFile(get("soundName", "Raid Warning")), get("soundVolume", 100), true) end end })
	return y
end

-- Tremor Reminder: the REAL reminder frame running a targeting scene, with
-- every option from its settings page live in the card.
function SP.Wizard.BuildTremorStep(card, inner, y)
	local Widgets = ns.Widgets
	SP.Wizard._tremorCard = card
	local function sv() ShamanPowerTremorReminderDB = ShamanPowerTremorReminderDB or {}; return ShamanPowerTremorReminderDB end
	local function get(k, d) local v = sv()[k]; if v == nil then return d end; return v end

	inner.previewInsetBottom = 90
	inner.previewMaxScale = 1.0
	local function fit() if inner:IsShown() and inner:GetWidth() > 0 then SP:ShowPreview("tremor", inner) end end
	C_Timer.After(0.02, fit)

	local story = inner:CreateFontString(nil, "OVERLAY"); story:SetFontObject(Core.fonts.row)
	story:SetPoint("BOTTOM", inner, "BOTTOM", 0, 62); story:SetWidth(inner:GetWidth() - 40); story:SetJustifyH("CENTER"); story:SetWordWrap(true)
	local legend = inner:CreateFontString(nil, "OVERLAY"); legend:SetFontObject(Core.fonts.rowDim)
	legend:SetPoint("BOTTOMLEFT", inner, "BOTTOMLEFT", 12, 14); legend:SetPoint("BOTTOMRIGHT", inner, "BOTTOMRIGHT", -12, 14)
	legend:SetJustifyH("CENTER"); legend:SetWordWrap(true)
	legend:SetText("Target a mob that is known to fear and the reminder appears BEFORE anyone gets feared. Drop Tremor and it goes away.")
	inner:SetScript("OnUpdate", function() story:SetText(SP.tremorDemoStatus or "") end)

	local W = card:GetWidth() - 36
	local function row(kind, opts)
		opts.x, opts.y, opts.width = 18, y, W
		local _, h = Widgets[kind](Widgets, card, opts)
		y = y + h
	end
	local function upd(fn) if fn then safecall(fn) end; notify(); if SP.TremorDemoActive then SP:TremorDemo(true) end; fit(); Widgets:RefreshAll(card) end
	local function off() return not get("enabled", true) end
	row("Toggle", { label = "Hide while Tremor Totem is down", disabled = off, get = function() return get("hideWhenTremorActive", true) end, set = function(v) sv().hideWhenTremorActive = v; upd() end })
	row("Toggle", { label = "Use the built-in fear-caster list", desc = "Hundreds of known fear-casting mobs from dungeons and raids. Add your own in Settings > Tremor Reminder > Manage Mob List.",
		disabled = off, get = function() return get("useDefaultList", true) end, set = function(v) sv().useDefaultList = v; upd() end })
	row("Dropdown", { label = "Display", disabled = off, get = function() return get("displayMode", "icon") end,
		set = function(v) sv().displayMode = v; upd("UpdateTremorReminderAppearance") end,
		values = function() return { icon = "Icon", text = "TREMOR! text", both = "Icon and text" } end, order = function() return { "icon", "text", "both" } end })
	row("Slider", { label = "Icon size", min = 32, max = 256, step = 1, disabled = off, get = function() return get("iconSize", 64) end, set = function(v) sv().iconSize = v; upd("UpdateTremorReminderAppearance") end })
	row("Slider", { label = "Opacity", min = 50, max = 100, step = 5, disabled = off, get = function() return get("opacity", 100) end, set = function(v) sv().opacity = v; upd("UpdateTremorReminderAppearance") end })
	row("Slider", { label = "Text size", min = 12, max = 48, step = 1, disabled = off, get = function() return get("textSize", 24) end, set = function(v) sv().textSize = v; upd("UpdateTremorReminderAppearance") end })
	row("Toggle", { label = "Pulsing glow", disabled = off, get = function() return get("showGlow", true) end, set = function(v) sv().showGlow = v; upd("UpdateTremorReminderAppearance") end })
	row("Color", { label = "Glow color", disabled = function() return off() or not get("showGlow", true) end,
		get = function() local c = get("glowColor", nil) or {}; return c.r or 1, c.g or 0.8, c.b or 0 end,
		set = function(r, g, b) sv().glowColor = { r = r, g = g, b = b }; upd("UpdateTremorReminderAppearance") end })
	local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
	local function soundList() return LSM and LSM:List("sound") or { "Raid Warning" } end
	local function soundValues() local v = {}; for _, n in ipairs(soundList()) do v[n] = n end; return v end
	local function noSound() return off() or not get("playSound", false) end
	row("Toggle", { label = "Alert sound", disabled = off, get = function() return get("playSound", false) end, set = function(v) sv().playSound = v; upd() end })
	row("Dropdown", { label = "Sound", disabled = noSound, get = function() return get("soundName", "Raid Warning") end, set = function(v) sv().soundName = v; upd() end, values = soundValues, order = soundList })
	row("Slider", { label = "Volume", min = 0, max = 100, step = 5, disabled = noSound, get = function() return get("soundVolume", 100) end, set = function(v) sv().soundVolume = v; upd() end })
	row("Button", { label = "Hear it", buttonText = "Test sound", disabled = noSound,
		func = function() if SP.PlaySoundWithVolume and SP.GetSoundFile then pcall(SP.PlaySoundWithVolume, SP, SP:GetSoundFile(get("soundName", "Raid Warning")), get("soundVolume", 100), true) end end })
	local note = card:CreateFontString(nil, "OVERLAY"); note:SetFontObject(Core.fonts.tiny); note:SetPoint("TOPLEFT", card, "TOPLEFT", 18, -(y + 6))
	note:SetWidth(W); note:SetJustifyH("LEFT"); note:SetWordWrap(true); note:SetTextColor(Core:Color("textDim"))
	note:SetText("Add or remove mobs from the fear-caster list in Settings > Tremor Reminder > Manage Mob List.")
	y = y + 6 + note:GetStringHeight() + 10
	return y
end

-- Expiring Alerts: real alerts through the module's real queue + animation,
-- with the display options and what-to-alert-on toggles live in the card.
function SP.Wizard.BuildExpiringStep(card, inner, y)
	local Widgets = ns.Widgets
	SP.Wizard._expiringCard = card
	local function sv() ShamanPowerExpiringAlertsDB = ShamanPowerExpiringAlertsDB or {}; return ShamanPowerExpiringAlertsDB end
	local function sub(k) local t = sv(); t[k] = t[k] or {}; return t[k] end
	local function get(k, d) local v = sv()[k]; if v == nil then return d end; return v end
	local function sget(k, f, d) local t = sv()[k]; local v = t and t[f]; if v == nil then return d end; return v end

	inner.previewInsetBottom = 90
	inner.previewMaxScale = 1.0
	local function fit() if inner:IsShown() and inner:GetWidth() > 0 then SP:ShowPreview("expiring", inner) end end
	C_Timer.After(0.02, fit)

	local story = inner:CreateFontString(nil, "OVERLAY"); story:SetFontObject(Core.fonts.row)
	story:SetPoint("BOTTOM", inner, "BOTTOM", 0, 62); story:SetWidth(inner:GetWidth() - 40); story:SetJustifyH("CENTER"); story:SetWordWrap(true)
	local legend = inner:CreateFontString(nil, "OVERLAY"); legend:SetFontObject(Core.fonts.rowDim)
	legend:SetPoint("BOTTOMLEFT", inner, "BOTTOMLEFT", 12, 14); legend:SetPoint("BOTTOMRIGHT", inner, "BOTTOMRIGHT", -12, 14)
	legend:SetJustifyH("CENTER"); legend:SetWordWrap(true)
	legend:SetText("Scrolling-combat-text style. A new one fires every few seconds here; in game they fire the moment something fades.")
	-- Keep every alert inside the box: shrink the borrowed frame (never
	-- enlarge) to fit the LONGEST demo line at the chosen sizes. Computed from
	-- the settings, not the live alerts, so the scale never changes while an
	-- alert is animating (that made them jitter).
	local measure = inner:CreateFontString(nil, "OVERLAY"); measure:Hide()
	local LONGEST = "Mana Spring Totem Expired FADED!"
	local lastKey
	inner:SetScript("OnUpdate", function()
		story:SetText(SP.expiringDemoStatus or "")
		local f = SP.expiringAlertsFrame
		if not (f and f:GetParent() == inner) then return end
		local ts, is, dm, ol = get("textSize", 24), get("iconSize", 32), get("displayMode", "both"), get("fontOutline", true)
		local key = ts .. ":" .. is .. ":" .. dm .. ":" .. tostring(ol) .. ":" .. math.floor(inner:GetWidth())
		if key == lastKey then return end
		lastKey = key
		local w = 0
		if dm ~= "text" then w = w + is + 8 end
		if dm ~= "icon" then
			measure:SetFont("Fonts\\FRIZQT__.TTF", ts, ol and "OUTLINE" or ""); measure:SetText(LONGEST)
			w = w + (measure:GetStringWidth() or 0)
		end
		local target = math.min(1, (inner:GetWidth() - 24) / math.max(1, w))
		if math.abs(f:GetScale() - target) > 0.01 then f:SetScale(target) end
	end)

	local W = card:GetWidth() - 36
	local function row(kind, opts)
		opts.x, opts.y, opts.width = 18, y, W
		local _, h = Widgets[kind](Widgets, card, opts)
		y = y + h
	end
	local function header(text)
		local h = card:CreateFontString(nil, "OVERLAY"); h:SetFontObject(Core.fonts.tiny); h:SetPoint("TOPLEFT", card, "TOPLEFT", 18, -(y + 6))
		h:SetText(text); h:SetTextColor(Core:Color("textDim")); y = y + 24
	end
	local function upd(fn) if fn then safecall(fn) end; notify(); Widgets:RefreshAll(card) end
	local function off() return not get("enabled", true) end

	header("LOOK")
	row("Dropdown", { label = "Display", disabled = off, get = function() return get("displayMode", "both") end, set = function(v) sv().displayMode = v; upd() end,
		values = function() return { both = "Icon + text", text = "Text only", icon = "Icon only" } end, order = function() return { "both", "text", "icon" } end })
	row("Dropdown", { label = "Animation", disabled = off, get = function() return get("animationStyle", "scrollUp") end, set = function(v) sv().animationStyle = v; upd() end,
		values = function() return { scrollUp = "Scroll up", scrollDown = "Scroll down", staticFade = "Static fade", bounce = "Bounce" } end, order = function() return { "scrollUp", "scrollDown", "staticFade", "bounce" } end })
	row("Slider", { label = "Text size", min = 12, max = 36, step = 1, disabled = off, get = function() return get("textSize", 24) end, set = function(v) sv().textSize = v; upd("UpdateExpiringAlertsAppearance") end })
	row("Slider", { label = "Icon size", min = 24, max = 64, step = 2, disabled = off, get = function() return get("iconSize", 32) end, set = function(v) sv().iconSize = v; upd("UpdateExpiringAlertsAppearance") end })
	row("Slider", { label = "Duration (s)", min = 1, max = 5, step = 0.5, disabled = off, get = function() return get("duration", 2.5) end, set = function(v) sv().duration = v; upd() end })
	row("Slider", { label = "Opacity", min = 50, max = 100, step = 5, disabled = off, get = function() return get("opacity", 100) end, set = function(v) sv().opacity = v; upd() end })
	row("Toggle", { label = "Outlined text", disabled = off, get = function() return get("fontOutline", true) end, set = function(v) sv().fontOutline = v; upd("UpdateExpiringAlertsAppearance") end })

	header("ALERT WHEN THESE FADE")
	local function shOff() return off() or not sget("shields", "enabled", true) end
	row("Toggle", { label = "Shields", disabled = off, get = function() return sget("shields", "enabled", true) end, set = function(v) sub("shields").enabled = v; upd() end })
	row("Toggle", { label = "    Lightning Shield", disabled = shOff, get = function() return sget("shields", "lightning", true) end, set = function(v) sub("shields").lightning = v; upd() end })
	row("Toggle", { label = "    Water Shield", disabled = shOff, get = function() return sget("shields", "water", true) end, set = function(v) sub("shields").water = v; upd() end })
	row("Toggle", { label = "    Earth Shield on your target", disabled = shOff, get = function() return sget("shields", "earthShield", true) end, set = function(v) sub("shields").earthShield = v; upd() end })
	row("Toggle", { label = "    Sound", disabled = shOff, get = function() return sget("shields", "sound", false) end, set = function(v) sub("shields").sound = v; upd() end })
	local function toOff() return off() or not sget("totems", "enabled", true) end
	row("Toggle", { label = "Totems", disabled = off, get = function() return sget("totems", "enabled", true) end, set = function(v) sub("totems").enabled = v; upd() end })
	row("Toggle", { label = "    Destroyed by a mob", disabled = toOff, get = function() return sget("totems", "destroyed", true) end, set = function(v) sub("totems").destroyed = v; upd() end })
	row("Toggle", { label = "    Timed out", desc = "Off by default - can be spammy.", disabled = toOff, get = function() return sget("totems", "expired", false) end, set = function(v) sub("totems").expired = v; upd() end })
	row("Toggle", { label = "    Sound", disabled = toOff, get = function() return sget("totems", "sound", false) end, set = function(v) sub("totems").sound = v; upd() end })
	local function imOff() return off() or not sget("weaponImbues", "enabled", true) end
	row("Toggle", { label = "Weapon imbues", disabled = off, get = function() return sget("weaponImbues", "enabled", true) end, set = function(v) sub("weaponImbues").enabled = v; upd() end })
	row("Toggle", { label = "    Sound", disabled = imOff, get = function() return sget("weaponImbues", "sound", false) end, set = function(v) sub("weaponImbues").sound = v; upd() end })
	row("Slider", { label = "Sound volume", min = 0, max = 100, step = 5, disabled = off, get = function() return get("soundVolume", 100) end, set = function(v) sv().soundVolume = v; upd() end })
	local note = card:CreateFontString(nil, "OVERLAY"); note:SetFontObject(Core.fonts.tiny); note:SetPoint("TOPLEFT", card, "TOPLEFT", 18, -(y + 6))
	note:SetWidth(W); note:SetJustifyH("LEFT"); note:SetWordWrap(true); note:SetTextColor(Core:Color("textDim"))
	note:SetText("Pick a different sound per category, and main-hand / off-hand imbues separately, in Settings > Expiring Alerts.")
	y = y + 6 + note:GetStringHeight() + 10
	return y
end

-- Totem Range: the REAL range overlay, animated for the totems the user
-- tracks, with the picker and appearance options in the card.
function SP.Wizard.BuildRangeStep(card, inner, y)
	local Widgets = ns.Widgets
	local function rt() SP:EnsureProfileTable("rangeTracker"); return SP.opt.rangeTracker end
	local function get(k, d) local t = SP.opt.rangeTracker; local v = t and t[k]; if v == nil then return d end; return v end
	local function tracked() ShamanPower_RangeTracker = ShamanPower_RangeTracker or {}; ShamanPower_RangeTracker.tracked = ShamanPower_RangeTracker.tracked or {}; return ShamanPower_RangeTracker.tracked end

	-- ---- preview: borrow the real frame; refit whenever it changes size ----
	inner.previewInsetBottom = 90
	inner.previewMaxScale = 1.4
	local function fit() if inner:IsShown() and inner:GetWidth() > 0 then SP:ShowPreview("sprange", inner) end end
	C_Timer.After(0.02, fit)
	local story = inner:CreateFontString(nil, "OVERLAY"); story:SetFontObject(Core.fonts.row)
	story:SetPoint("BOTTOM", inner, "BOTTOM", 0, 62); story:SetWidth(inner:GetWidth() - 40); story:SetJustifyH("CENTER"); story:SetWordWrap(true)
	local legend = inner:CreateFontString(nil, "OVERLAY"); legend:SetFontObject(Core.fonts.rowDim)
	legend:SetPoint("BOTTOMLEFT", inner, "BOTTOMLEFT", 12, 14); legend:SetPoint("BOTTOMRIGHT", inner, "BOTTOMRIGHT", -12, 14)
	legend:SetJustifyH("CENTER"); legend:SetWordWrap(true)
	legend:SetText("Green = you have that totem's buff. Red = the totem is down but you are out of its range. Gray = nobody has it down. Appears by itself whenever a shaman is in your group.")
	local lastW, lastH, acc = 0, 0, 0
	inner:SetScript("OnUpdate", function(_, e)
		story:SetText(SP.sprangeDemoStatus or "")
		acc = acc + e; if acc < 0.25 then return end; acc = 0
		local f = SP.spRangeFrame
		if f and f:GetParent() == inner then
			local w, h = f:GetWidth(), f:GetHeight()
			if w ~= lastW or h ~= lastH then lastW, lastH = w, h; fit() end
		end
	end)

	-- ---- card: not just for shamans ----
	local box = CreateFrame("Frame", nil, card); box:SetPoint("TOPLEFT", card, "TOPLEFT", 18, -y); box:SetPoint("TOPRIGHT", card, "TOPRIGHT", -18, -y)
	Core:SolidTex(box, "accent", "BACKGROUND", 0.10); Core:MakeBorder(box, "accent")
	local bw = card:GetWidth() - 36 - 24
	local bh = box:CreateFontString(nil, "OVERLAY"); bh:SetFontObject(Core.fonts.row); bh:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -10); bh:SetWidth(bw)
	bh:SetJustifyH("LEFT"); bh:SetWordWrap(true); bh:SetTextColor(Core:Color("accentHi"))
	bh:SetText("NOT JUST FOR SHAMANS")
	local bb = box:CreateFontString(nil, "OVERLAY"); bb:SetFontObject(Core.fonts.rowDim); bb:SetPoint("TOPLEFT", bh, "BOTTOMLEFT", 0, -6); bb:SetWidth(bw)
	bb:SetJustifyH("LEFT"); bb:SetWordWrap(true)
	bb:SetText("Any class can install ShamanPower and enable only the |cffE6EAF0Totem Range|r module to see whether they are standing in range of their shaman's totems. As a shaman, keep it on if you run with other shamans and want to track their totems too.")
	box:SetHeight(20 + bh:GetStringHeight() + 6 + bb:GetStringHeight() + 12)
	y = y + box:GetHeight() + 14

	-- ---- totem picker (chips, like the cooldown bar) ----
	local hdr = card:CreateFontString(nil, "OVERLAY"); hdr:SetFontObject(Core.fonts.tiny)
	hdr:SetPoint("TOPLEFT", card, "TOPLEFT", 18, -y); hdr:SetText("TOTEMS TO TRACK"); hdr:SetTextColor(Core:Color("textDim"))
	y = y + 18
	local chipW = math.floor((card:GetWidth() - 36 - 8) / 2)
	local col, row = 0, 0
	local function paintChip(c)
		local on = tracked()[c.id] and true or false
		c.bg:SetColorTexture(Core:Color("accent", on and 0.28 or 0.06))
		Core:SetBorderColor(c, on and "accent" or "border")
		c.lbl:SetTextColor(Core:Color(on and "accentHi" or "textDim"))
		c.ic:SetDesaturated(not on); c.ic:SetAlpha(on and 1 or 0.55)
	end
	local seen = {}
	for _, t in ipairs(SP.TrackableTotems or {}) do
		if not seen[t.id] then
			seen[t.id] = true
			local c = CreateFrame("Button", nil, card); c:SetSize(chipW, 26)
			c:SetPoint("TOPLEFT", card, "TOPLEFT", 18 + col * (chipW + 8), -(y + row * 32))
			c.bg = c:CreateTexture(nil, "BACKGROUND"); c.bg:SetAllPoints(c); Core:MakeBorder(c, "border")
			c.ic = c:CreateTexture(nil, "ARTWORK"); c.ic:SetSize(18, 18); c.ic:SetPoint("LEFT", c, "LEFT", 5, 0)
			c.ic:SetTexture(GetSpellTexture(t.spellID)); c.ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			c.lbl = c:CreateFontString(nil, "OVERLAY"); c.lbl:SetFontObject(Core.fonts.row); c.lbl:SetPoint("LEFT", c.ic, "RIGHT", 7, 0)
			c.lbl:SetPoint("RIGHT", c, "RIGHT", -6, 0); c.lbl:SetJustifyH("LEFT"); c.lbl:SetText(t.name)
			c.id = t.id
			c:SetScript("OnClick", function()
				tracked()[t.id] = (not tracked()[t.id]) or nil
				paintChip(c)
				if SP.sprangeDemo and SP.sprangeDemo.build then SP.sprangeDemo.build() else safecall("UpdateSPRangeFrame") end
				fit()
			end)
			paintChip(c)
			col = col + 1; if col == 2 then col = 0; row = row + 1 end
		end
	end
	y = y + (row + (col > 0 and 1 or 0)) * 32 + 10

	-- ---- appearance ----
	local W = card:GetWidth() - 36
	local function wrow(kind, opts)
		opts.x, opts.y, opts.width = 18, y, W
		local _, h = Widgets[kind](Widgets, card, opts)
		y = y + h
	end
	local function upd(...) for _, fn in ipairs({ ... }) do safecall(fn) end; notify(); if SP.sprangeDemo and SP.sprangeDemo.build then SP.sprangeDemo.build() end; fit() end
	wrow("Slider", { label = "Icon size", min = 20, max = 60, step = 4, get = function() return get("iconSize", 36) end, set = function(v) rt().iconSize = v; upd("UpdateSPRangeFrame") end })
	wrow("Slider", { label = "Opacity", min = 0.2, max = 1.0, step = 0.1, get = function() return get("opacity", 1.0) end, set = function(v) rt().opacity = v; upd("UpdateSPRangeOpacity") end })
	wrow("Toggle", { label = "Vertical layout", get = function() return get("vertical", false) end, set = function(v) rt().vertical = v; upd("UpdateSPRangeFrame", "UpdateSPRangeBorder") end })
	wrow("Toggle", { label = "Show totem names", get = function() return not get("hideNames", false) end, set = function(v) rt().hideNames = not v; upd("UpdateSPRangeFrame") end })
	wrow("Toggle", { label = "Show border and title", get = function() return not get("hideBorder", false) end, set = function(v) rt().hideBorder = not v; upd("UpdateSPRangeBorder") end })
	return y
end

-- Assignments: the real window with a fake three-shaman roster.
function SP.Wizard.BuildAssignStep(card, inner, y)
	local Widgets = ns.Widgets
	inner.previewInsetBottom = 60
	inner.previewMaxScale = 1.0
	local function fit() if inner:IsShown() and inner:GetWidth() > 0 then SP:ShowPreview("assign", inner) end end
	C_Timer.After(0.02, fit)
	local legend = inner:CreateFontString(nil, "OVERLAY"); legend:SetFontObject(Core.fonts.rowDim)
	legend:SetPoint("BOTTOMLEFT", inner, "BOTTOMLEFT", 12, 14); legend:SetPoint("BOTTOMRIGHT", inner, "BOTTOMRIGHT", -12, 14)
	legend:SetJustifyH("CENTER"); legend:SetWordWrap(true)
	legend:SetText("You plus two other shamans who also run ShamanPower. Watch the raid leader change Nazgrel's Fire totem - everyone's window updates instantly.")

	-- other shamans need the addon too
	local box = CreateFrame("Frame", nil, card); box:SetPoint("TOPLEFT", card, "TOPLEFT", 18, -y); box:SetPoint("TOPRIGHT", card, "TOPRIGHT", -18, -y)
	Core:SolidTex(box, "accent", "BACKGROUND", 0.10); Core:MakeBorder(box, "accent")
	local bw = card:GetWidth() - 36 - 24
	local bh = box:CreateFontString(nil, "OVERLAY"); bh:SetFontObject(Core.fonts.row); bh:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -10); bh:SetWidth(bw)
	bh:SetJustifyH("LEFT"); bh:SetWordWrap(true); bh:SetTextColor(Core:Color("accentHi")); bh:SetText("OTHER SHAMANS SHOW UP ONLY IF THEY RUN SHAMANPOWER")
	local bb = box:CreateFontString(nil, "OVERLAY"); bb:SetFontObject(Core.fonts.rowDim); bb:SetPoint("TOPLEFT", bh, "BOTTOMLEFT", 0, -6); bb:SetWidth(bw)
	bb:SetJustifyH("LEFT"); bb:SetWordWrap(true)
	bb:SetText("Shamans talk to each other through the addon. A shaman without it will not appear in this list and cannot receive assignments - tell your fellow shamans to install it.")
	box:SetHeight(20 + bh:GetStringHeight() + 6 + bb:GetStringHeight() + 12)
	y = y + box:GetHeight() + 14

	local W = card:GetWidth() - 36
	local function row(kind, opts)
		opts.x, opts.y, opts.width = 18, y, W
		local _, h = Widgets[kind](Widgets, card, opts)
		y = y + h
	end
	row("Toggle", { label = "Free Assign", desc = "Let anyone in the group set your totems, not just the leader and assistants.",
		get = function() return SP.opt.freeassign and true or false end,
		set = function(v)
			SP.opt.freeassign = v
			local me = SP.AllShamans and SP.AllShamans[SP.player]; if me then me.freeassign = v end
			if SP.SendSelf and IsInGroup() then pcall(SP.SendSelf, SP) end
			notify(); if ShamanPowerAssign and ShamanPowerAssign.Redraw then ShamanPowerAssign:Redraw() end
		end })
	row("Slider", { label = "Window size", min = 0.4, max = 3.0, step = 0.05, get = function() return SP.opt.configscale or 0.9 end,
		set = function(v) SP.opt.configscale = v; safecall("UpdateLayout"); safecall("UpdateRoster"); notify() end })
	return y
end

function SP.Wizard.BuildCooldownBarStep(card, inner, y)
	local Widgets = ns.Widgets
	local horde = UnitFactionGroup and UnitFactionGroup("player") == "Horde"
	-- Spells the real bar can track, in bar order. roles = who sees the chip.
	local SPELLS = {
		{ id = 324,   name = "Shield",         opt = "cdbarShowShields",          cd = 0,  ready = 0,  charges = "3", color = {0.4, 0.6, 1.0} },
		{ id = 36936, name = "Recall", long = "Totemic Call",   opt = "cdbarShowRecall",           cd = 6,  ready = 5,  color = {0.6, 0.4, 0.2} },
		{ id = 20608, name = "Ankh",           opt = "cdbarShowReincarnation",    cd = 14, ready = 6,  count = "2", color = {0.8, 0.2, 0.2} },
		{ id = 16188, name = "NS", long = "Nature's Swiftness", opt = "cdbarShowNS",           cd = 9,  ready = 4,  color = {0.2, 0.8, 0.3}, roles = { restoration = true } },
		{ id = 16190, name = "Mana Tide",      opt = "cdbarShowManaTide",         cd = 11, ready = 3,  color = {0.2, 0.5, 1.0}, roles = { restoration = true } },
		{ id = 30823, name = "Sham. Rage", long = "Shamanistic Rage", opt = "cdbarShowShamanisticRage", cd = 8, ready = 5,  color = {0.8, 0.5, 0.1}, roles = { enhancement = true } },
		{ id = horde and 2825 or 32182, name = horde and "Bloodlust" or "Heroism", opt = "cdbarShowBloodlust", cd = 16, ready = 4, color = {0.8, 0.1, 0.1} },
		{ id = 16166, name = "Ele. Mastery", long = "Elemental Mastery", opt = "cdbarShowElementalMastery", cd = 10, ready = 5, color = {0.9, 0.6, 0.1}, roles = { elemental = true } },
		{ id = 8232,  name = "Imbues", long = "Weapon Imbues",  opt = "cdbarShowImbues",           cd = 0,  ready = 0,  imbue = true, color = {0.6, 0.8, 1.0} },
	}
	local function visible(sp) return (not sp.roles or sp.roles[state.role] or SP.Wizard.previewOnly) and OPT()[sp.opt] ~= false end
	local function roleSees(sp) return not sp.roles or sp.roles[state.role] end

	-- ---- mock bar (mirrors the real bar: dark backdrop, 36px buttons) ----
	local SIZE, GAP = 36, 6
	local bar = CreateFrame("Frame", nil, inner)
	bar:SetPoint("CENTER", inner, "CENTER", 0, 10)
	local bg = bar:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(bar); bg:SetColorTexture(0, 0, 0, 0.7)
	Core:MakeBorder(bar, "border")
	local buttons = {}
	for i, sp in ipairs(SPELLS) do
		local btn = CreateFrame("Frame", nil, bar); btn:SetSize(SIZE, SIZE)
		local icon = btn:CreateTexture(nil, "ARTWORK"); icon:SetAllPoints(btn)
		icon:SetTexture(GetSpellTexture(sp.id)); icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		-- Grayed sweep overlay: like the real bar it grows DOWN from the top as
		-- the cooldown depletes (no radial swipe on cooldown-type buttons).
		local gray = btn:CreateTexture(nil, "ARTWORK", nil, 1); gray:SetPoint("TOPLEFT"); gray:SetPoint("TOPRIGHT"); gray:SetHeight(0)
		gray:SetTexture(GetSpellTexture(sp.id)); gray:SetDesaturated(true); gray:SetVertexColor(0.5, 0.5, 0.5); gray:Hide()
		-- radial swipe (only used when Sweep style is "Radial swipe")
		local cdr = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate"); cdr:SetAllPoints(icon); cdr:SetDrawEdge(false); cdr:SetSwipeColor(0, 0, 0, 0.8)
		if cdr.SetHideCountdownNumbers then cdr:SetHideCountdownNumbers(true) end
		-- Progress bar (position follows cdbarProgressPosition, laid out below).
		local pbg = btn:CreateTexture(nil, "BACKGROUND", nil, 2); pbg:SetColorTexture(0, 0, 0, 0.6); pbg:SetSize(3, SIZE)
		local pb = btn:CreateTexture(nil, "ARTWORK", nil, 2); pb:SetColorTexture(sp.color[1], sp.color[2], sp.color[3], 1); pb:SetSize(3, SIZE)
		local txt = btn:CreateFontString(nil, "OVERLAY", nil, 7); txt:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE"); txt:SetPoint("CENTER"); txt:SetTextColor(1, 1, 1)
		local corner = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormal"); corner:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
		corner:SetText(sp.charges or sp.count or "")
		local lbl = btn:CreateFontString(nil, "OVERLAY"); lbl:SetFontObject(Core.fonts.tiny); lbl:SetPoint("TOP", btn, "BOTTOM", 0, -8)
		lbl:SetText(sp.name); lbl:SetWidth(SIZE + GAP + 14); lbl:SetJustifyH("CENTER"); lbl:SetWordWrap(false)
		-- Staggered sim clock so the bar is not in lockstep.
		buttons[i] = { sp = sp, f = btn, icon = icon, gray = gray, cdr = cdr, lbl = lbl, pbg = pbg, corner = corner, pb = pb, txt = txt, t = (i * 2.7) % math.max(1, sp.cd + sp.ready), onCd = false }
	end

	-- Progress bar + duration text geometry, same anchors as
	-- UpdateCooldownBarProgressBars / the duration text locations.
	local function layoutBars()
		local pos, size = OPT().cdbarProgressPosition or "left", OPT().cdbarProgressBarHeight or 3
		local tl, ts = OPT().cdbarDurationTextLocation or "none", OPT().cdbarDurationTextSize or 8
		for _, b in ipairs(buttons) do
			local f, pbg, pb, txt = b.f, b.pbg, b.pb, b.txt
			pbg:ClearAllPoints(); pb:ClearAllPoints(); txt:ClearAllPoints()
			b.vert = (pos == "left" or pos == "right" or pos == "top_vert" or pos == "bottom_vert" or pos == "on_icon")
			if pos == "bottom" then
				pbg:SetSize(SIZE, size); pbg:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -1); pb:SetSize(SIZE, size); pb:SetPoint("TOPLEFT", pbg, "TOPLEFT")
			elseif pos == "top" then
				pbg:SetSize(SIZE, size); pbg:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, 1); pb:SetSize(SIZE, size); pb:SetPoint("TOPLEFT", pbg, "TOPLEFT")
			elseif pos == "bottom_vert" then
				pbg:SetSize(size, SIZE); pbg:SetPoint("TOP", f, "BOTTOM", 0, -1); pb:SetSize(size, SIZE); pb:SetPoint("BOTTOMLEFT", pbg, "BOTTOMLEFT")
			elseif pos == "top_vert" then
				pbg:SetSize(size, SIZE); pbg:SetPoint("BOTTOM", f, "TOP", 0, 1); pb:SetSize(size, SIZE); pb:SetPoint("BOTTOMLEFT", pbg, "BOTTOMLEFT")
			elseif pos == "on_icon" then
				pbg:SetSize(size, SIZE); pbg:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0); pb:SetSize(size, SIZE); pb:SetPoint("BOTTOMLEFT", pbg, "BOTTOMLEFT")
			elseif pos == "right" then
				pbg:SetSize(size, SIZE); pbg:SetPoint("TOPLEFT", f, "TOPRIGHT", 1, 0); pb:SetSize(size, SIZE); pb:SetPoint("BOTTOMLEFT", pbg, "BOTTOMLEFT")
			else -- left
				pbg:SetSize(size, SIZE); pbg:SetPoint("TOPRIGHT", f, "TOPLEFT", -1, 0); pb:SetSize(size, SIZE); pb:SetPoint("BOTTOMLEFT", pbg, "BOTTOMLEFT")
			end
			b.textMode = tl
			if tl == "inside" then
				txt:SetFont("Fonts\\FRIZQT__.TTF", ts, "OUTLINE"); txt:SetPoint("CENTER", pbg, "CENTER")
			elseif tl == "outside" then
				txt:SetFont("Fonts\\FRIZQT__.TTF", ts, "OUTLINE")
				if pos == "bottom" or pos == "bottom_vert" then txt:SetPoint("TOP", pbg, "BOTTOM", 0, -1)
				elseif pos == "top" or pos == "top_vert" then txt:SetPoint("BOTTOM", pbg, "TOP", 0, 1)
				elseif pos == "right" then txt:SetPoint("LEFT", pbg, "RIGHT", 1, 0)
				else txt:SetPoint("RIGHT", pbg, "LEFT", -1, 0) end
			elseif tl == "icon" then
				txt:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE"); txt:SetPoint("CENTER", f, "CENTER")
			else -- "none": legacy centre text, only if the CD Text toggle is on
				txt:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE"); txt:SetPoint("CENTER", f, "CENTER")
			end
		end
	end
	local lastGeom
	local function layoutMock()
		local lay = OPT().cdbarLayout or OPT().layout or "Horizontal"
		local vertical = (lay ~= "Horizontal")
		local n, x = 0, 10
		for _, b in ipairs(buttons) do
			if visible(b.sp) then
				b.f:ClearAllPoints(); b.lbl:ClearAllPoints()
				if vertical then
					b.f:SetPoint("TOP", bar, "TOP", -30, -x)
					b.lbl:SetPoint("LEFT", b.f, "RIGHT", 10, 0); b.lbl:SetJustifyH("LEFT"); b.lbl:SetWidth(90)
				else
					b.f:SetPoint("LEFT", bar, "LEFT", x, 6)
					b.lbl:SetPoint("TOP", b.f, "BOTTOM", 0, -8); b.lbl:SetJustifyH("CENTER"); b.lbl:SetWidth(SIZE + GAP + 14)
				end
				b.f:Show(); b.lbl:SetShown(not SP.Wizard.previewOnly)
				x = x + SIZE + GAP + 4; n = n + 1
			else b.f:Hide() end
		end
		local labelH = SP.Wizard.previewOnly and 0 or 24
		if vertical then bar:SetSize(SIZE + (SP.Wizard.previewOnly and 20 or 120), math.max(60, x + 6)) else bar:SetSize(math.max(60, x + 6), SIZE + 12 + labelH) end
		bar:ClearAllPoints(); bar:SetPoint("CENTER", inner, "CENTER", 0, SP.Wizard.previewOnly and 0 or 10)
		layoutBars()
	end

	bar:SetScript("OnUpdate", function(_, e)
		local showBars  = OPT().cdbarShowProgressBars ~= false
		local showSweep = OPT().cdbarShowColorSweep ~= false
		local showText  = OPT().cdbarShowCDText ~= false
		local geom = tostring(OPT().cdbarProgressPosition) .. tostring(OPT().cdbarProgressBarHeight) .. tostring(OPT().cdbarDurationTextLocation) .. tostring(OPT().cdbarDurationTextSize)
		if geom ~= lastGeom then lastGeom = geom; layoutBars() end
		local opacity, fullActive = OPT().cooldownBarOpacity or 1, OPT().cooldownBarFullOpacityWhenActive
		local sc = OPT().cooldownBarScale or 0.9
		if SP.Wizard.previewOnly then sc = math.min(sc, (inner:GetHeight() - 6) / math.max(1, bar:GetHeight())) end
		bar:SetScale(sc)
		local hideFrame = OPT().hideCooldownBarFrame
		bg:SetShown(not hideFrame)
		for _, t in pairs(bar.spBorder or {}) do t:SetShown(not hideFrame) end
		for _, b in ipairs(buttons) do
			if b.f:IsShown() then
				local sp = b.sp
				b.f:SetAlpha((fullActive and b.onCd) and 1 or opacity)
				b.pbg:SetShown(showBars); b.pb:SetShown(showBars)
				if sp.cd > 0 then
					b.t = b.t + e
					local cycle = sp.cd + sp.ready
					if b.t >= cycle then b.t = b.t - cycle end
					local onCd = b.t < sp.cd
					b.onCd = onCd
					if onCd then
						local remain = sp.cd - b.t
						local frac = remain / sp.cd
						if b.vert then b.pb:SetHeight(math.max(0.5, SIZE * frac)) else b.pb:SetWidth(math.max(0.5, SIZE * frac)) end
						-- duration text: chosen location, or the legacy centre text when the toggle is on
						local wantText = (b.textMode ~= "none" and b.textMode ~= nil) or showText
						b.txt:SetText(wantText and tostring(math.ceil(remain)) or "")
						local style = OPT().cdbarSweepStyle or "greys"
						if showSweep and style == "radial" then
							b.gray:Hide()
							if not b.radialSet then b.cdr:SetCooldown(GetTime() - b.t, sp.cd); b.radialSet = true end
						elseif showSweep then
							if b.radialSet then b.cdr:Clear(); b.radialSet = nil end
							local dep = (style == "fills") and frac or (1 - frac)
							b.gray:Show(); b.gray:SetHeight(math.max(0.5, SIZE * dep))
							b.gray:SetTexCoord(0.08, 0.92, 0.08, 0.08 + 0.84 * dep)
						else
							b.gray:Hide(); if b.radialSet then b.cdr:Clear(); b.radialSet = nil end
						end
						if sp.count then b.corner:Hide() end          -- Ankh count hides while on cooldown
					else
						if b.vert then b.pb:SetHeight(SIZE) else b.pb:SetWidth(SIZE) end
						b.txt:SetText(""); b.gray:Hide()
						if b.radialSet then b.cdr:Clear(); b.radialSet = nil end
						if sp.count then b.corner:Show() end
					end
				else
					-- Shield / imbues: always "up" in the demo.
					if b.vert then b.pb:SetHeight(SIZE) else b.pb:SetWidth(SIZE) end
					b.gray:Hide(); b.txt:SetText("")
				end
			end
		end
	end)

	if SP.Wizard.previewOnly then layoutMock(); return y end
	-- ---- spell chips in the card: which spells appear on the bar ----
	local hdr = card:CreateFontString(nil, "OVERLAY"); hdr:SetFontObject(Core.fonts.tiny)
	hdr:SetPoint("TOPLEFT", card, "TOPLEFT", 18, -y); hdr:SetText("SPELLS ON THE BAR"); hdr:SetTextColor(Core:Color("textDim"))
	y = y + 18
	local chipW = math.floor((card:GetWidth() - 36 - 8) / 2)
	local chips, col, row = {}, 0, 0
	local function paintChip(c)
		local on = OPT()[c.sp.opt] ~= false
		c.bg:SetColorTexture(Core:Color("accent", on and 0.28 or 0.06))
		Core:SetBorderColor(c, on and "accent" or "border")
		c.lbl:SetTextColor(Core:Color(on and "accentHi" or "textDim"))
		c.ic:SetDesaturated(not on); c.ic:SetAlpha(on and 1 or 0.55)
	end
	for _, sp in ipairs(SPELLS) do
		if roleSees(sp) then
			local c = CreateFrame("Button", nil, card); c:SetSize(chipW, 26)
			c:SetPoint("TOPLEFT", card, "TOPLEFT", 18 + col * (chipW + 8), -(y + row * 32))
			c.bg = c:CreateTexture(nil, "BACKGROUND"); c.bg:SetAllPoints(c)
			Core:MakeBorder(c, "border")
			c.ic = c:CreateTexture(nil, "ARTWORK"); c.ic:SetSize(18, 18); c.ic:SetPoint("LEFT", c, "LEFT", 5, 0)
			c.ic:SetTexture(GetSpellTexture(sp.id)); c.ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			c.lbl = c:CreateFontString(nil, "OVERLAY"); c.lbl:SetFontObject(Core.fonts.row); c.lbl:SetPoint("LEFT", c.ic, "RIGHT", 7, 0)
			c.lbl:SetPoint("RIGHT", c, "RIGHT", -6, 0); c.lbl:SetJustifyH("LEFT"); c.lbl:SetText(sp.long or sp.name)
			c.sp = sp
			c:SetScript("OnClick", function()
				OPT()[sp.opt] = not (OPT()[sp.opt] ~= false)
				if not InCombatLockdown() and SP.RecreateCooldownBar then pcall(SP.RecreateCooldownBar, SP) end
				local reg = LibStub and LibStub("AceConfigRegistry-3.0", true); if reg then reg:NotifyChange("ShamanPower") end
				paintChip(c); layoutMock()
			end)
			paintChip(c)
			chips[#chips + 1] = c
			col = col + 1; if col == 2 then col = 0; row = row + 1 end
		end
	end
	local note = card:CreateFontString(nil, "OVERLAY"); note:SetFontObject(Core.fonts.tiny)
	note:SetPoint("TOPLEFT", card, "TOPLEFT", 18, -(y + (row + (col > 0 and 1 or 0)) * 32 + 6))
	note:SetWidth(card:GetWidth() - 36); note:SetJustifyH("LEFT"); note:SetWordWrap(true); note:SetTextColor(Core:Color("textDim"))
	note:SetText("Spells you have not learned yet are hidden on the real bar automatically.")
	y = y + (row + (col > 0 and 1 or 0)) * 32 + 6 + note:GetStringHeight() + 14

	-- ---- appearance (from Settings > Bars) ----
	local function wrow(kind, opts)
		opts.x, opts.y, opts.width = 18, y, card:GetWidth() - 36
		local _, h = Widgets[kind](Widgets, card, opts)
		y = y + h
	end
	wrow("Dropdown", { label = "Sweep style", disabled = function() return OPT().cdbarShowColorSweep == false end,
		get = function() return OPT().cdbarSweepStyle or "greys" end,
		set = function(v) SP.opt.cdbarSweepStyle = v; safecall("UpdateCooldownBar"); notify() end,
		values = function() return { greys = "Vertical - greys out", fills = "Vertical - fills back in", radial = "Radial swipe" } end,
		order = function() return { "greys", "fills", "radial" } end })
	wrow("Dropdown", { label = "Progress bar position", get = function() return OPT().cdbarProgressPosition or "left" end,
		set = function(v) SP.opt.cdbarProgressPosition = v; if not InCombatLockdown() then safecall("RecreateCooldownBar") end; notify(); layoutMock() end,
		values = function() return { left = "Left", right = "Right", top = "Top (horizontal)", top_vert = "Top (vertical)", bottom = "Bottom (horizontal)", bottom_vert = "Bottom (vertical)", on_icon = "On the icon" } end,
		order = function() return { "left", "right", "top", "top_vert", "bottom", "bottom_vert", "on_icon" } end })
	wrow("Slider", { label = "Progress bar size", min = 3, max = 16, step = 1, get = function() return OPT().cdbarProgressBarHeight or 3 end,
		set = function(v) SP.opt.cdbarProgressBarHeight = v; safecall("UpdateCooldownBarProgressBars"); safecall("UpdateCooldownBar"); notify(); layoutMock() end })
	wrow("Dropdown", { label = "Time text", get = function() return OPT().cdbarDurationTextLocation or "none" end,
		set = function(v) SP.opt.cdbarDurationTextLocation = v; safecall("UpdateCooldownBarProgressBars"); safecall("UpdateCooldownBarLayout"); safecall("UpdateCooldownBar"); notify(); layoutMock() end,
		values = function() return { none = "None (centre number if Time text is on)", inside = "Inside the bar", outside = "Beside the bar", icon = "On the icon" } end,
		order = function() return { "none", "inside", "outside", "icon" } end })
	wrow("Slider", { label = "Time text size", min = 6, max = 20, step = 1, get = function() return OPT().cdbarDurationTextSize or 8 end,
		set = function(v) SP.opt.cdbarDurationTextSize = v; safecall("ApplyCdbarTextSize"); safecall("UpdateCooldownBarProgressBars"); notify(); layoutMock() end })
	wrow("Dropdown", { label = "Layout", get = function() return OPT().cdbarLayout or OPT().layout or "Horizontal" end,
		set = function(v) OPT().cdbarLayout = v; safecall("UpdateCooldownBarLayout"); safecall("UpdateCooldownBar"); safecall("LayoutShieldFlyout"); safecall("LayoutWeaponImbueFlyout"); notify(); layoutMock() end,
		values = LAYOUT_VALUES, order = LAYOUT_ORDER })
	wrow("Slider", { label = "Size", min = 0.4, max = 3.0, step = 0.05, get = function() return OPT().cooldownBarScale or 0.9 end,
		set = function(v) OPT().cooldownBarScale = v; safecall("UpdateCooldownBarScale"); notify() end })
	wrow("Slider", { label = "Opacity", min = 0, max = 1, step = 0.05, get = function() return OPT().cooldownBarOpacity or 1 end,
		set = function(v) OPT().cooldownBarOpacity = v; safecall("UpdateCooldownBarOpacity"); notify() end })
	wrow("Toggle", { label = "Full opacity while on cooldown", get = function() return OPT().cooldownBarFullOpacityWhenActive and true or false end,
		set = function(v) OPT().cooldownBarFullOpacityWhenActive = v; safecall("UpdateCooldownBarOpacity"); notify() end })
	wrow("Toggle", { label = "Show frame behind the bar", get = function() return not OPT().hideCooldownBarFrame end,
		set = function(v) OPT().hideCooldownBarFrame = (not v) or nil; safecall("UpdateCooldownBarFrame"); notify() end })

	layoutMock()
	return y
end

-- Totem Plates: real plate frames on mock enemy / friendly nameplates, with
-- every Totem Plates option live in the card.
function SP.Wizard.BuildTotemPlatesStep(card, inner, y)
	local Widgets = ns.Widgets
	SP.Wizard._platesCard = card
	local function tp() SP:EnsureProfileTable("totemPlates"); return SP.opt.totemPlates end
	local function get(k, d) local t = SP.opt.totemPlates; local v = t and t[k]; if v == nil then return d end; return v end

	inner.previewInsetBottom = 44
	inner.previewMaxScale = 1.0
	local function fit() if inner:IsShown() and inner:GetWidth() > 0 then SP:ShowPreview("totemplates", inner) end end
	C_Timer.After(0.02, fit)
	-- scene labels (the demo frame is centered by the harness; labels sit around it)
	local lblE = inner:CreateFontString(nil, "OVERLAY"); lblE:SetFontObject(Core.fonts.rowDim); lblE:SetPoint("CENTER", inner, "CENTER", 0, 35 + 95 + 10)
	lblE:SetText("|cffff5050Enemy shaman's totems|r  (their nameplates replaced by icons)")
	local lblF = inner:CreateFontString(nil, "OVERLAY"); lblF:SetFontObject(Core.fonts.rowDim); lblF:SetPoint("CENTER", inner, "CENTER", 0, 35 - 70 - 42)
	lblF:SetText("|cff50ff50Your party's totem|r")
	local legend = inner:CreateFontString(nil, "OVERLAY"); legend:SetFontObject(Core.fonts.rowDim)
	legend:SetPoint("BOTTOMLEFT", inner, "BOTTOMLEFT", 12, 14); legend:SetPoint("BOTTOMRIGHT", inner, "BOTTOMRIGHT", -12, 14)
	legend:SetJustifyH("CENTER"); legend:SetWordWrap(true)
	legend:SetText("Spot the Tremor or Grounding you need to kill at a glance. Pulsing totems (Tremor, Mana Spring...) count down to their next tick.")
	inner:SetScript("OnUpdate", function()
		local f = SP.totemPlatesDemoFrame
		if f and f:GetParent() == inner then
			-- captions ride just above each row's plates, wherever those end up
			local pe, pf = f.plates and f.plates[2], f.plates and f.plates[4]
			local te = pe and pe.totemPlateFrame or pe
			local tf = pf and pf.totemPlateFrame or pf
			if te then lblE:ClearAllPoints(); lblE:SetPoint("BOTTOM", te, "TOP", 0, 8) end
			if tf then lblF:ClearAllPoints(); lblF:SetPoint("BOTTOM", tf, "TOP", 0, 8) end
		end
		local on = get("enabled", false) and true or false
		lblE:SetShown(on and get("showEnemy", true) ~= false)
		lblF:SetShown(on and get("showFriendly", true) ~= false)
	end)

	local W = card:GetWidth() - 36
	local function row(kind, opts)
		opts.x, opts.y, opts.width = 18, y, W
		local _, h = Widgets[kind](Widgets, card, opts)
		y = y + h
	end
	local function upd(fn) if fn then safecall(fn) end; notify(); if SP.totemPlatesDemoActive then SP:TotemPlatesDemo(true) end; fit(); Widgets:RefreshAll(card) end
	local function off() return not get("enabled", false) end
	row("Toggle", { label = "Enemy totems", disabled = off, get = function() return get("showEnemy", true) ~= false end, set = function(v) tp().showEnemy = v; upd() end })
	row("Toggle", { label = "Friendly totems", desc = "Only works in the open world and battlegrounds. Inside dungeons and raids the game hides friendly totem nameplates, so friendly plates cannot show there - enemy totems still work everywhere.",
		disabled = off, get = function() return get("showFriendly", true) ~= false end, set = function(v) tp().showFriendly = v; upd() end })
	row("Slider", { label = "Icon size", min = 20, max = 80, step = 2, disabled = off, get = function() return get("iconSize", 40) end, set = function(v) tp().iconSize = v; upd("UpdateTotemPlatesSize") end })
	row("Slider", { label = "Opacity", min = 0.3, max = 1.0, step = 0.1, disabled = off, get = function() return get("alpha", 0.9) end, set = function(v) tp().alpha = v; upd() end })
	row("Toggle", { label = "Show totem name", disabled = off, get = function() return get("showName", false) and true or false end, set = function(v) tp().showName = v; upd() end })
	local function noPulse() return off() or get("showPulseTimer", true) == false end
	row("Toggle", { label = "Pulse timer", desc = "Countdown to the next tick on pulsing totems (Tremor, Mana Spring, Healing Stream, Searing...).",
		disabled = off, get = function() return get("showPulseTimer", true) ~= false end, set = function(v) tp().showPulseTimer = v; upd("UpdateTotemPlatesPulseSettings") end })
	row("Toggle", { label = "    Countdown text", disabled = noPulse, get = function() return get("showPulseText", true) ~= false end, set = function(v) tp().showPulseText = v; upd("UpdateTotemPlatesPulseSettings") end })
	row("Toggle", { label = "    Pulse bar", disabled = noPulse, get = function() return get("showPulseBar", true) ~= false end, set = function(v) tp().showPulseBar = v; upd("UpdateTotemPlatesPulseSettings") end })
	row("Toggle", { label = "    Cooldown swipe", disabled = noPulse, get = function() return get("showPulseCooldown", false) and true or false end, set = function(v) tp().showPulseCooldown = v; upd("UpdateTotemPlatesPulseSettings") end })
	row("Slider", { label = "    Text size", min = 8, max = 24, step = 1, disabled = noPulse, get = function() return get("pulseTextSize", 14) end, set = function(v) tp().pulseTextSize = v; upd("UpdateTotemPlatesPulseSettings") end })
	row("Slider", { label = "    Bar height", min = 2, max = 12, step = 1, disabled = noPulse, get = function() return get("pulseBarHeight", 4) end, set = function(v) tp().pulseBarHeight = v; upd("UpdateTotemPlatesPulseSettings") end })
	return y
end

function SP.Wizard.BuildFinishNote(card, inner, y) end

function SP.Wizard.BuildPositionStep(card, inner, y)
	local btn = Core:MakeButton(card, "Unlock & Position My Frames", 10, true)
	btn:SetPoint("TOPLEFT", card, "TOPLEFT", 18, -y)
	btn:SetPoint("TOPRIGHT", card, "TOPRIGHT", -18, -y)
	btn:SetScript("OnClick", function() SP.Wizard:EnterPositioning() end)

	local pic = inner:CreateFontString(nil, "OVERLAY")
	pic:SetFontObject(Core.fonts.rowDim); pic:SetPoint("CENTER"); pic:SetWidth(inner:GetWidth() - 24)
	pic:SetJustifyH("CENTER"); pic:SetWordWrap(true)
	pic:SetText("The setup screen will step aside so you can drag your totem bar and cooldown bar. A small bar appears at the top - click Done when you are finished.")
end

local posBar
function SP.Wizard:EnterPositioning()
	if wiz then wiz:Hide() end
	if SP.SetTotemBarUnlocked then SP:SetTotemBarUnlocked(true) end
	if SP.SetCooldownBarUnlocked then SP:SetCooldownBarUnlocked(true) end
	if not posBar then
		posBar = CreateFrame("Frame", "ShamanPowerWizardPosBar", UIParent)
		posBar:SetSize(420, 52); posBar:SetPoint("TOP", UIParent, "TOP", 0, -80)
		posBar:SetFrameStrata("FULLSCREEN_DIALOG")
		Core:SolidTex(posBar, "windowBg", "BACKGROUND", nil, true)
		Core:MakeBorder(posBar, "accent", 2)
		local t = posBar:CreateFontString(nil, "OVERLAY"); t:SetFontObject(Core.fonts.row)
		t:SetPoint("LEFT", posBar, "LEFT", 16, 0); t:SetText("Drag your bars to move them")
		local done = Core:MakeButton(posBar, "Done", 90, true)
		done:SetPoint("RIGHT", posBar, "RIGHT", -12, 0)
		done:SetScript("OnClick", function() SP.Wizard:ExitPositioning() end)
	end
	posBar:Show()
end

function SP.Wizard:ExitPositioning()
	if SP.SetTotemBarUnlocked then SP:SetTotemBarUnlocked(false) end
	if SP.SetCooldownBarUnlocked then SP:SetCooldownBarUnlocked(false) end
	if posBar then posBar:Hide() end
	if wiz then wiz:Show(); RenderStep() end
end

function RenderStep()
	ClearContent()
	local steps = state.steps
	local s = steps[state.step]
	wiz.stepTitle:SetText(string.format("Step %d of %d", state.step, #steps))
	RenderRail(steps)

	-- Role/welcome is a full-bleed centered screen (no rail); feature steps use
	-- the rail.
	local roleStep = (s.id == "role")
	wiz.rail:SetShown(not roleStep)
	wiz.content:ClearAllPoints()
	if roleStep then
		wiz.content:SetPoint("TOPLEFT", wiz, "TOPLEFT", 2, -(HEADER_H + 4))
	else
		wiz.content:SetPoint("TOPLEFT", wiz.rail, "TOPRIGHT", 0, 0)
	end
	wiz.content:SetPoint("BOTTOMRIGHT", wiz, "BOTTOMRIGHT", -2, FOOTER_H)

	if roleStep then
		SP.Wizard:RenderRole()
		wiz.stepTitle:SetText("Welcome")
		wiz.next:SetShown(state.role ~= nil)
		wiz.back:Hide()
		wiz.next.text:SetText("Next")
		return
	end
	wiz.back:SetShown(state.step > 1)

	if s.id == "finish" then
		SP.Wizard:RenderFinish()
		wiz.next.text:SetText("Finish & Reload")
		wiz.next:Show()
		return
	end

	-- Feature step: left card (title + description + controls) and a clipped
	-- preview panel on the right.
	local cardFrame = track(LeftCard(wiz.content))
	local card = cardFrame.body
	local box = track(PreviewPanel(wiz.content))

	local title = card:CreateFontString(nil, "OVERLAY")
	title:SetFontObject(Core.fonts.title)
	title:SetPoint("TOPLEFT", card, "TOPLEFT", 18, -18)
	title:SetText(s.title)
	local desc = card:CreateFontString(nil, "OVERLAY")
	desc:SetFontObject(Core.fonts.rowDim)
	desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
	desc:SetWidth(card:GetWidth() - 36); desc:SetJustifyH("LEFT")
	desc:SetText(s.desc)

	local y = 78 + math.max(desc:GetStringHeight(), 30)

	if s.bullets then
		for _, line in ipairs(s.bullets) do
			local roles
			if type(line) == "table" then roles = line.roles; line = line[1] end
			if roles and not roles[state.role] then line = nil end
			if line then
			local dot = card:CreateFontString(nil, "OVERLAY")
			dot:SetFontObject(Core.fonts.row); dot:SetPoint("TOPLEFT", card, "TOPLEFT", 18, -y)
			dot:SetTextColor(Core:Color("accentHi")); dot:SetText("\226\128\162")
			local b = card:CreateFontString(nil, "OVERLAY")
			b:SetFontObject(Core.fonts.rowDim); b:SetPoint("TOPLEFT", dot, "TOPRIGHT", 8, 0)
			b:SetWidth(card:GetWidth() - 54); b:SetJustifyH("LEFT"); b:SetText(line)
			y = y + math.max(b:GetStringHeight(), 18) + 8
			end
		end
	end

	if s.toggles then
		y = y + 6
		for _, tg in ipairs(s.toggles) do
			if not tg.roles or tg.roles[state.role] then
				ToggleRow(card, y, tg.label, tg.bind)
				y = y + 34
			end
		end
	end

	if s.build and SP.Wizard[s.build] then
		local endY = SP.Wizard[s.build](card, box.inner, y + 4)
		FitCardBody(cardFrame, type(endY) == "number" and (endY + 24) or (y + 4))
	elseif s.previewKey then
		FitCardBody(cardFrame, y)
		C_Timer.After(0.02, function()
			if wiz:IsShown() and state.steps[state.step] and state.steps[state.step].id == s.id then
				SP:ShowPreview(s.previewKey, box.inner)
			end
		end)
	else
		local none = box.inner:CreateFontString(nil, "OVERLAY")
		none:SetFontObject(Core.fonts.rowDim); none:SetPoint("CENTER")
		none:SetText("|cff5A6678This feature has no preview.|r")
	end

	wiz.next.text:SetText(state.step < #steps and "Next" or "Finish & Reload")
	wiz.next:Show()
end


-- Role selection: three cards
local SPEC_ICON = {
	restoration = "Interface\\Icons\\Spell_Nature_HealingWaveGreater",
	enhancement = "Interface\\Icons\\Spell_Nature_LightningShield",
	elemental   = "Interface\\Icons\\Spell_Nature_Lightning",
}

-- ---------------------------------------------------------------------------
-- Quick Setup preview: what a built-in preset looks like and what it sets,
-- decoded from the preset string itself, before the user commits to it.
-- ---------------------------------------------------------------------------
local previewDlg
local function PresetSummary(preset)
	local payload = SP.DecodeShare and SP:DecodeShare(preset.str)
	local p = payload and payload.profile or {}
	local x = payload and payload.extras or {}
	local function on(v) return v and "|cff40ff40on|r" or "|cff8090a0off|r" end
	local style = p.dynamicTotemMode and "Dynamic (PvP)" or (p.activeTotemAsMain and "TotemTimers style" or "Normal")
	local dbp = ({ none = "none", bottom = "bottom", bottom_vert = "bottom (vertical)", top = "top", top_vert = "top (vertical)", left = "left", right = "right" })[p.durationBarPosition or "bottom"] or tostring(p.durationBarPosition)
	local dots = (p.showPartyRangeDots and (p.rangeCounter and p.rangeCounter.enabled) and "dots + numbers") or (p.showPartyRangeDots and "dots") or ((p.rangeCounter and p.rangeCounter.enabled) and "numbers") or "off"
	local lines = {
		{ "Totem bar", string.format("%s, %s, size %.2f%s", p.layout or "Horizontal", style, p.buffscale or 1, p.hideTotemBarFrame and ", no frame" or "") },
		{ "Duration bars", dbp .. ((p.durationTextLocation and p.durationTextLocation ~= "none") and (", time " .. p.durationTextLocation) or "") },
		{ "Cooldown bar", (p.showCooldownBar == false) and "off" or string.format("%s, size %.2f%s", p.cdbarLayout or p.layout or "Horizontal", p.cooldownBarScale or 0.9, p.hideCooldownBarFrame and ", no frame" or "") },
		{ "Totem twisting", on(p.enableTotemTwisting) },
		{ "Earth Shield tracker", on(p.esTracker and p.esTracker.enabled) },
		{ "Shield charges", on(p.shieldChargeDisplay and p.shieldChargeDisplay.showPlayerShield ~= false) },
		{ "Party Buff Tracker", dots .. (p.partyDotPosition and p.partyDotPosition ~= "corners" and (", dots " .. p.partyDotPosition) or "") },
		{ "Totem Plates", on(p.totemPlates and p.totemPlates.enabled) },
		{ "Reactive Totems", on(x.ShamanPower_ReactiveTotems and x.ShamanPower_ReactiveTotems.enabled ~= false) },
		{ "Tremor Reminder", on(x.ShamanPowerTremorReminderDB and x.ShamanPowerTremorReminderDB.enabled ~= false) },
		{ "Expiring Alerts", on(x.ShamanPowerExpiringAlertsDB and x.ShamanPowerExpiringAlertsDB.enabled ~= false) },
	}
	return lines, payload ~= nil
end

function SP.Wizard:ShowPresetPreview(preset)
	if not previewDlg then
		previewDlg = Core:CreateDialog({
			name = "ShamanPowerPresetPreview", width = 940, height = 560,
			title = preset.name, subtitle = "quick setup - preview before you apply", headerHeight = 46, footer = 52, strata = "FULLSCREEN_DIALOG",
		})
		local body = previewDlg.body
		-- opaque: this sits over the welcome screen and must be readable
		local solid = previewDlg:CreateTexture(nil, "BACKGROUND", nil, 1); solid:SetPoint("TOPLEFT", 2, -2); solid:SetPoint("BOTTOMRIGHT", -2, 2); solid:SetColorTexture(Core:Color("windowBg", 1))
		local solidH = previewDlg.header:CreateTexture(nil, "BACKGROUND", nil, 1); solidH:SetAllPoints(previewDlg.header); solidH:SetColorTexture(Core:Color("sidebarBg", 1))
		-- live mocks of the preset (rebuilt on every open, see below)
		local shot = CreateFrame("Frame", nil, body); shot:SetSize(520, 400); shot:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
		previewDlg.shot = shot
		local desc = body:CreateFontString(nil, "OVERLAY"); desc:SetFontObject(Core.fonts.rowDim); desc:SetPoint("TOPLEFT", shot, "BOTTOMLEFT", 0, -8); desc:SetWidth(520); desc:SetJustifyH("LEFT"); desc:SetWordWrap(true)
		previewDlg.desc = desc
		previewDlg:SetScript("OnHide", function() SP.Wizard.optOverride = nil; SP.Wizard.previewOnly = nil end)
		-- summary
		local hdr = body:CreateFontString(nil, "OVERLAY"); hdr:SetFontObject(Core.fonts.tiny); hdr:SetPoint("TOPLEFT", shot, "TOPRIGHT", 22, 0); hdr:SetText("WHAT IT SETS"); hdr:SetTextColor(Core:Color("textDim"))
		previewDlg.rows = {}
		for i = 1, 12 do
			-- rows are re-stacked after filling so long values can wrap to two lines
			local k = body:CreateFontString(nil, "OVERLAY"); k:SetFontObject(Core.fonts.rowDim); k:SetWidth(128); k:SetJustifyH("LEFT"); k:SetJustifyV("TOP")
			local v = body:CreateFontString(nil, "OVERLAY"); v:SetFontObject(Core.fonts.row); v:SetPoint("TOPLEFT", k, "TOPRIGHT", 6, 0); v:SetWidth(240); v:SetJustifyH("LEFT"); v:SetJustifyV("TOP"); v:SetWordWrap(true)
			previewDlg.rows[i] = { k = k, v = v }
		end
		previewDlg.hdr = hdr
		local note = body:CreateFontString(nil, "OVERLAY"); note:SetFontObject(Core.fonts.tiny); note:SetWidth(370); note:SetJustifyH("LEFT"); note:SetWordWrap(true); note:SetTextColor(Core:Color("textDim"))
		previewDlg.note = note
		note:SetText("Positions, colors, sounds and every other setting come along too. Your totem choices and raid assignments are not touched.")
		-- footer
		local apply = Core:MakeButton(previewDlg, "Apply this layout & reload", 220, true)
		apply:SetPoint("BOTTOMRIGHT", previewDlg, "BOTTOMRIGHT", -14, 12)
		apply:SetScript("OnClick", function()
			local p = previewDlg.preset
			previewDlg:Hide()
			SP:ApplyPreset(p.key, "overwrite")
			SP.opt.setupDone = true
			SP.Wizard:Close(true)
			ReloadUI()
		end)
		local cont = Core:MakeButton(previewDlg, "Apply & continue the setup", 220, false)
		cont:SetPoint("RIGHT", apply, "LEFT", -8, 0)
		cont:SetScript("OnClick", function()
			local p = previewDlg.preset
			previewDlg:Hide()
			local ok = SP:ApplyPreset(p.key, "overwrite")   -- applies live, no reload needed
			state.presetApplied = ok and p or nil
			print("|cff0070ddShamanPower|r: " .. p.name .. " applied. The setup will keep it as your starting point.")
			RenderStep()
		end)
		local back = Core:MakeButton(previewDlg, "Back", 90, false)
		back:SetPoint("RIGHT", cont, "LEFT", -8, 0)
		back:SetScript("OnClick", function() previewDlg:Hide() end)
	end
	previewDlg.preset = preset
	previewDlg:SetTitles(preset.name, "quick setup - preview before you apply")
	previewDlg.desc:SetText(preset.desc or "")
	-- Rebuild the mocks against the preset's own profile.
	local payload = SP.DecodeShare and SP:DecodeShare(preset.str)
	if previewDlg.host then previewDlg.host:Hide(); previewDlg.host:SetParent(nil) end
	local host = CreateFrame("Frame", nil, previewDlg.shot); host:SetAllPoints(previewDlg.shot)
	previewDlg.host = host
	if payload and payload.profile then
		SP.Wizard.optOverride = payload.profile
		SP.Wizard.previewOnly = true
		local dummyCard = CreateFrame("Frame", nil, host); dummyCard:SetSize(400, 10); dummyCard:Hide()
		local PANELS = {
			{ label = "Totem bar",     build = "BuildTotemBarStep",     h = 176 },
			{ label = "Duration bars", build = "BuildDurationBarsStep", h = 108 },
			{ label = "Cooldown bar",  build = "BuildCooldownBarStep",  h = 108 },
		}
		local yy = 0
		for _, pdef in ipairs(PANELS) do
			local panel = CreateFrame("Frame", nil, host); panel:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -yy); panel:SetSize(520, pdef.h)
			Core:SolidTex(panel, "contentBg", "BACKGROUND"); Core:MakeBorder(panel, "border")
			local lbl = panel:CreateFontString(nil, "OVERLAY"); lbl:SetFontObject(Core.fonts.tiny); lbl:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -6); lbl:SetText(strupper(pdef.label)); lbl:SetTextColor(Core:Color("textDim"))
			local inner = CreateFrame("Frame", nil, panel); inner:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -18); inner:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -4, 4); inner:SetClipsChildren(true)
			local fn = SP.Wizard[pdef.build]
			if fn then pcall(fn, dummyCard, inner, 0) end
			-- the mocks' own captions are for the step pages, not this card
			for _, r in ipairs({ inner:GetRegions() }) do if r.IsObjectType and r:IsObjectType("FontString") then r:Hide() end end
			yy = yy + pdef.h + 4
		end
	else
		local t = host:CreateFontString(nil, "OVERLAY"); t:SetFontObject(Core.fonts.rowDim); t:SetPoint("CENTER"); t:SetText("Could not read this preset.")
	end
	local lines, decoded = PresetSummary(preset)
	local yy, last = 8, nil
	for i, r in ipairs(previewDlg.rows) do
		local l = lines[i]
		if l then
			r.k:SetText(l[1]); r.v:SetText(l[2]); r.k:Show(); r.v:Show()
			r.k:ClearAllPoints(); r.k:SetPoint("TOPLEFT", previewDlg.hdr, "BOTTOMLEFT", 0, -yy)
			local h = math.max(r.k:GetStringHeight(), r.v:GetStringHeight(), 14)
			yy = yy + h + 8
		else r.k:Hide(); r.v:Hide() end
	end
	previewDlg.note:ClearAllPoints(); previewDlg.note:SetPoint("TOPLEFT", previewDlg.hdr, "BOTTOMLEFT", 0, -(yy + 6))
	if not decoded then previewDlg.rows[1].k:Show(); previewDlg.rows[1].k:ClearAllPoints(); previewDlg.rows[1].k:SetPoint("TOPLEFT", previewDlg.hdr, "BOTTOMLEFT", 0, -8); previewDlg.rows[1].k:SetText("Could not read this preset"); previewDlg.rows[1].v:SetText("") end
	previewDlg:Show()
end

function SP.Wizard:RenderRole()
	local c = wiz.content
	local cw = c:GetWidth()

	local intro = track(c:CreateFontString(nil, "OVERLAY"))
	intro:SetFontObject(Core.fonts.title)
	intro:SetPoint("TOP", c, "TOP", 0, -46)
	intro:SetText("Welcome to ShamanPower")
	local sub = track(c:CreateFontString(nil, "OVERLAY"))
	sub:SetFontObject(Core.fonts.rowDim)
	sub:SetPoint("TOP", intro, "BOTTOM", 0, -8)
	sub:SetWidth(560); sub:SetJustifyH("CENTER")
	sub:SetText("Pick your spec and we will walk you through the features that matter for it, showing each one live. You can change anything later.")

	-- Loud, on purpose: first-timers should not skip this.
	local warn = track(CreateFrame("Frame", nil, c))
	warn:SetSize(640, 10); warn:SetPoint("TOP", sub, "BOTTOM", 0, -14)
	Core:SolidTex(warn, "warn", "BACKGROUND", 0.12); Core:MakeBorder(warn, "warn", 2)
	local wh = warn:CreateFontString(nil, "OVERLAY"); wh:SetFontObject(Core.fonts.title)
	wh:SetPoint("TOP", warn, "TOP", 0, -12); wh:SetWidth(600); wh:SetJustifyH("CENTER"); wh:SetWordWrap(true)
	wh:SetTextColor(Core:Color("warn")); wh:SetText("FIRST TIME HERE?  DO NOT SKIP THIS SETUP")
	local wb = warn:CreateFontString(nil, "OVERLAY"); wb:SetFontObject(Core.fonts.row)
	wb:SetPoint("TOP", wh, "BOTTOM", 0, -6); wb:SetWidth(600); wb:SetJustifyH("CENTER"); wb:SetWordWrap(true)
	wb:SetText("ShamanPower does a LOT more than a totem bar. This walkthrough shows every feature working and lets you set it up as you go - it is the fastest way to get the most out of the addon.")
	warn:SetHeight(12 + wh:GetStringHeight() + 6 + wb:GetStringHeight() + 12)

	local roles = {
		{ key = "restoration", name = "Restoration", blurb = "Healing.\nEarth Shield, Mana Tide, shield charges." },
		{ key = "enhancement", name = "Enhancement", blurb = "Melee.\nTotem twisting, Windfury, reactive totems." },
		{ key = "elemental",   name = "Elemental",   blurb = "Caster.\nTotems, cooldowns, reactive utility." },
	}
	local cardW, cardH, gap = 244, 264, 26
	local totalW = #roles * cardW + (#roles - 1) * gap
	local x0 = (cw - totalW) / 2
	for i, r in ipairs(roles) do
		local card = track(CreateFrame("Button", nil, c))
		card:SetSize(cardW, cardH)
		card:SetPoint("TOPLEFT", c, "TOPLEFT", x0 + (i - 1) * (cardW + gap), -216)

		local bg = card:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(card)
		local glow = card:CreateTexture(nil, "ARTWORK")
		glow:SetHeight(2); glow:SetPoint("TOPLEFT", card, "TOPLEFT", 1, -1); glow:SetPoint("TOPRIGHT", card, "TOPRIGHT", -1, -1)
		glow:SetColorTexture(Core:Color("accent"))

		local icon = card:CreateTexture(nil, "ARTWORK")
		icon:SetSize(72, 72); icon:SetPoint("TOP", card, "TOP", 0, -26)
		icon:SetTexture(SPEC_ICON[r.key]); icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

		local nm = card:CreateFontString(nil, "OVERLAY"); nm:SetFontObject(Core.fonts.brand)
		nm:SetPoint("TOP", icon, "BOTTOM", 0, -14); nm:SetText(r.name)
		local rule = card:CreateTexture(nil, "ARTWORK")
		rule:SetSize(40, 1); rule:SetPoint("TOP", nm, "BOTTOM", 0, -8); rule:SetColorTexture(Core:Color("accent", 0.7))
		local bl = card:CreateFontString(nil, "OVERLAY"); bl:SetFontObject(Core.fonts.rowDim)
		bl:SetPoint("TOP", rule, "BOTTOM", 0, -12); bl:SetWidth(cardW - 24); bl:SetJustifyH("CENTER")
		bl:SetText(r.blurb)

		local function paint()
			local sel = (state.role == r.key)
			bg:SetColorTexture(Core:Color(sel and "accent" or "rowBg", sel and 0.20 or 1))
			glow:SetShown(sel)
			nm:SetTextColor(Core:Color(sel and "accentHi" or "text"))
			Core:SetBorderColor(card, sel and "accent" or "border")
		end
		Core:MakeBorder(card, "border")
		paint()
		card:SetScript("OnEnter", function()
			if state.role ~= r.key then bg:SetColorTexture(Core:Color("rowHover")); Core:SetBorderColor(card, "accent") end
		end)
		card:SetScript("OnLeave", function()
			if state.role ~= r.key then bg:SetColorTexture(Core:Color("rowBg")); Core:SetBorderColor(card, "border") end
		end)
		card:SetScript("OnClick", function()
			state.role = r.key
			if not state.presetApplied then SP.Wizard.ApplyRoleDefaults(r.key) end   -- a preset is the baseline instead
			state.steps = VisibleSteps()
			RenderStep()
		end)
		paint()
	end

	-- Quick Setup: skip the walkthrough and apply the built-in preset.
	local preset = SP.Presets and SP.Presets[1]
	if preset and preset.str then
		local qbtn = track(Core:MakeButton(c, "Use " .. preset.name .. "  (Quick Setup)", 320, true))
		qbtn:SetSize(320, 34)
		qbtn:SetPoint("TOP", c, "TOP", 0, -(216 + cardH + 24))
		qbtn:SetScript("OnClick", function() SP.Wizard:ShowPresetPreview(preset) end)
		if state.presetApplied then
			qbtn.text:SetText(preset.name .. " applied - pick your spec to continue")
		end
		local qhint = track(c:CreateFontString(nil, "OVERLAY"))
		qhint:SetFontObject(Core.fonts.tiny)
		qhint:SetPoint("TOP", qbtn, "BOTTOM", 0, -8)
		qhint:SetWidth(560); qhint:SetJustifyH("CENTER"); qhint:SetTextColor(Core:Color("textMute"))
		qhint:SetText("Shows you the layout first - nothing is applied until you confirm.")
	end
end

function SP.Wizard:RenderFinish()
	local c = wiz.content
	local t = track(c:CreateFontString(nil, "OVERLAY"))
	t:SetFontObject(Core.fonts.title)
	t:SetPoint("TOP", c, "TOP", 0, -70)
	t:SetText("You're all set!")
	local d = track(c:CreateFontString(nil, "OVERLAY"))
	d:SetFontObject(Core.fonts.rowDim)
	d:SetPoint("TOP", t, "BOTTOM", 0, -12); d:SetWidth(520); d:SetJustifyH("CENTER"); d:SetWordWrap(true)
	d:SetText("ShamanPower will reload once so everything you chose is applied cleanly. You can run this setup again any time with /spsetup.")

	-- The big one: setup only scratched the surface.
	local box = track(CreateFrame("Frame", nil, c))
	box:SetSize(560, 10); box:SetPoint("TOP", d, "BOTTOM", 0, -28)
	Core:SolidTex(box, "accent", "BACKGROUND", 0.10); Core:MakeBorder(box, "accent")
	local h = box:CreateFontString(nil, "OVERLAY"); h:SetFontObject(Core.fonts.title)
	h:SetPoint("TOPLEFT", box, "TOPLEFT", 20, -16); h:SetWidth(520); h:SetJustifyH("LEFT")
	h:SetTextColor(Core:Color("accentHi")); h:SetText("There is a LOT more in Settings")
	local b = box:CreateFontString(nil, "OVERLAY"); b:SetFontObject(Core.fonts.rowDim)
	b:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -8); b:SetWidth(520); b:SetJustifyH("LEFT"); b:SetWordWrap(true)
	b:SetText("This walkthrough only covered the essentials. The full settings window has far more: every totem bar and cooldown bar option, flyouts, macros, loadouts and the loadout bar, pop-out trackers, mini bar, assignments, colors, sounds, keybinds, profiles, the Windfury Companion, and more.")
	local cmd = box:CreateFontString(nil, "OVERLAY"); cmd:SetFontObject(Core.fonts.row)
	cmd:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, -10); cmd:SetWidth(520); cmd:SetJustifyH("LEFT"); cmd:SetWordWrap(true)
	cmd:SetText("Open it any time with  |cffFFFFFF/spui|r  or the settings button on your totem bar.")

	-- Offer to open it straight after the reload.
	local tr = CreateFrame("Button", nil, box); tr:SetSize(38, 18)
	tr:SetPoint("TOPLEFT", cmd, "BOTTOMLEFT", 0, -14)
	local tex = tr:CreateTexture(nil, "BACKGROUND"); tex:SetAllPoints(tr); Core:MakeBorder(tr, "border")
	local knob = tr:CreateTexture(nil, "OVERLAY"); knob:SetSize(12, 12); knob:SetColorTexture(0.95, 0.96, 0.98, 1)
	local function paint()
		local on = SP.opt.openSettingsAfterSetup and true or false
		tex:SetColorTexture(Core:ColorIf(on, "accent", "off"))
		knob:ClearAllPoints(); knob:SetPoint(on and "RIGHT" or "LEFT", tr, on and "RIGHT" or "LEFT", on and -3 or 3, 0)
	end
	tr:SetScript("OnClick", function() SP.opt.openSettingsAfterSetup = not SP.opt.openSettingsAfterSetup or nil; paint() end)
	if SP.opt.openSettingsAfterSetup == nil then SP.opt.openSettingsAfterSetup = true end
	paint()
	local tl = box:CreateFontString(nil, "OVERLAY"); tl:SetFontObject(Core.fonts.row); tl:SetPoint("LEFT", tr, "RIGHT", 10, 0)
	tl:SetText("Open the full settings window after the reload")

	box:SetHeight(16 + h:GetStringHeight() + 8 + b:GetStringHeight() + 10 + cmd:GetStringHeight() + 14 + 18 + 18)
end

-- ===========================================================================
-- Navigation
-- ===========================================================================
function SP.Wizard:Go(step)
	if step < 1 then step = 1 end
	if step > #state.steps then step = #state.steps end
	state.step = step
	RenderStep()
end

function SP.Wizard:NextOrFinish()
	local steps = state.steps
	if steps[state.step].id == "finish" then
		self:Finish()
	else
		self:Go(state.step + 1)
	end
end

function SP.Wizard:Finish()
	SP.opt.setupDone = true
	self:Close(false)
	ReloadUI()
end

function SP.Wizard:Close(markDone)
	if markDone then SP.opt.setupDone = true end
	-- Give every borrowed module frame back (and stop the demos) before hiding.
	ClearContent()
	if posBar then posBar:Hide() end
	if wiz then wiz:Hide() end
end

function SP.Wizard:Open()
	Build()
	Core:SyncOpacity()
	state.role = nil
	state.presetApplied = nil
	state.step = 1
	state.steps = VisibleSteps()
	wiz:Show()
	RenderStep()
end

-- Someone upgrading from an older ShamanPower already has a configured bar:
-- assigned totems, loadouts, or saved bar positions. A brand-new install has
-- none of those.
local function LooksLikeExistingUser()
	local a = ShamanPower_Assignments and SP.player and ShamanPower_Assignments[SP.player]
	if a then for e = 1, 4 do if (a[e] or 0) > 0 then return true end end end
	if ShamanPower_TotemLoadouts and #ShamanPower_TotemLoadouts > 0 then return true end
	if SP.opt.totemBarPosition or SP.opt.cooldownBarPosition then return true end
	return false
end

-- Small one-time card for upgraders: a lot changed, here is the tour.
local upgradeDlg
function SP.Wizard:ShowUpgradePrompt()
	if InCombatLockdown() then C_Timer.After(5, function() SP.Wizard:ShowUpgradePrompt() end) return end
	if not upgradeDlg then
		upgradeDlg = Core:CreateDialog({
			name = "ShamanPowerUpgradePrompt", width = 480, height = 250,
			title = "ShamanPower has changed", subtitle = "new settings window, new guided setup", headerHeight = 46, footer = 52,
		})
		upgradeDlg:SetFrameStrata("DIALOG")
		local t = upgradeDlg.body:CreateFontString(nil, "OVERLAY"); t:SetFontObject(Core.fonts.row)
		t:SetPoint("TOPLEFT", upgradeDlg.body, "TOPLEFT", 0, -4); t:SetWidth(440); t:SetJustifyH("LEFT"); t:SetWordWrap(true)
		t:SetText("This version replaces the old options screen with a new settings window, and adds a guided setup that shows every feature of the addon working live - quite a few of them are easy to miss.\n\nIf you want to see what is new, take the tour. It only takes a few minutes, nothing is changed until you choose it, and you can run it again any time with |cffffffff/spsetup|r.")
		local go = Core:MakeButton(upgradeDlg, "Take the tour", 150, true)
		go:SetPoint("BOTTOMRIGHT", upgradeDlg, "BOTTOMRIGHT", -14, 12)
		go:SetScript("OnClick", function() upgradeDlg:Hide(); SP.Wizard:Open() end)
		local later = Core:MakeButton(upgradeDlg, "Not now", 110, false)
		later:SetPoint("RIGHT", go, "LEFT", -8, 0)
		later:SetScript("OnClick", function()
			upgradeDlg:Hide()
			SP.opt.setupDone = true      -- do not nag again; /spsetup is always there
			print("|cff0070ddShamanPower|r: run the guided setup any time with /spsetup.")
		end)
	end
	upgradeDlg:Show()
end

-- Auto-open on first login for shamans (once profile data is ready).
-- New install: straight into the setup. Upgrade: a small prompt first.
local function MaybeAutoOpen()
	if not SP.opt then return end
	if SP.opt.setupDone then return end
	if select(2, UnitClass("player")) ~= "SHAMAN" then SP.opt.setupDone = true; return end
	C_Timer.After(1.5, function()
		if SP.opt.setupDone then return end
		if LooksLikeExistingUser() then SP.Wizard:ShowUpgradePrompt() else SP.Wizard:Open() end
	end)
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", function(self)
	self:UnregisterEvent("PLAYER_ENTERING_WORLD")
	MaybeAutoOpen()
	-- Finish screen asked for the settings window after the reload.
	if SP.opt and SP.opt.openSettingsAfterSetup and SP.opt.setupDone then
		SP.opt.openSettingsAfterSetup = nil
		C_Timer.After(2, function() if ns.SPConfig and ns.SPConfig.Open then ns.SPConfig:Open() end end)
	end
end)

SLASH_SHAMANPOWERSETUP1 = "/spsetup"
SlashCmdList["SHAMANPOWERSETUP"] = function() SP.Wizard:Open() end

return true
