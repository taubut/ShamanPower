-- ShamanPower_Config :: Window
-- The options shell: sidebar navigation, tab strip, dual search, and the
-- two-column content packer.

local ADDON, ns = ...
local Core    = ns.Core
local Widgets = ns.Widgets
local Tree    = ns.Tree

local SPConfig = {}
ns.SPConfig = SPConfig
_G.ShamanPowerConfig = SPConfig

-- Geometry -------------------------------------------------------------------
local WIN_W, WIN_H   = 1000, 640
local SIDEBAR_W      = 244
local HEADER_H       = 92
local FOOTER_H       = 52
local TABSTRIP_H     = 34
local CONTENT_PAD    = 16
local COL_GAP        = 12
local NAV_ROW_H      = 26
local NAV_GROUP_H    = 24

-- ---------------------------------------------------------------------------
-- Sidebar information architecture
-- Explicit rather than derived: the existing option tree is organised for
-- Ace's tab widget, and this regroups it into something navigable. Anything
-- not listed here is appended automatically under "More" so nothing is lost
-- if the option table grows.
-- ---------------------------------------------------------------------------
-- ---------------------------------------------------------------------------
-- Explicit power-dot bindings
-- The sidebar's default is to promote an "Enable ..." toggle found in the
-- page's option table. Some modules keep their on/off state in their own
-- code instead, so those get an explicit { loaded, get, set, label, desc }
-- here. `loaded` gates the dot: when the module addon is not running the dot
-- is simply not drawn. `power = false` opts a page out of the heuristic.
-- ---------------------------------------------------------------------------
local function SP() return _G.ShamanPower end

-- Totem Range Tracker: the module's on/off is the overlay frame itself.
-- ShamanPower_SPRange.lua ToggleSPRange() is the only writer of
-- ShamanPower_RangeTracker.shown / spRangeManuallyOpened; the live truth is
-- whether spRangeFrame is shown, which is also what the auto-show path
-- (UpdateSPRangeVisibility) drives.
local POWER_SPRANGE = {
	label  = "Totem Range overlay",
	desc   = "Show or hide the totem range overlay (same as /sprange toggle).",
	loaded = function() local sp = SP() return sp and sp.SPRangeLoaded and true or false end,
	get    = function()
		local f = SP().spRangeFrame
		return f and f:IsShown() and true or false
	end,
	set    = function(v)
		local sp = SP()
		local f = sp.spRangeFrame
		local cur = f and f:IsShown() and true or false
		if (v and true or false) ~= cur then sp:ToggleSPRange() end
	end,
}

-- Party Buff Tracker: the module gates itself on showPartyRangeDots OR
-- rangeCounter.enabled (ShamanPower_PartyRange.lua UpdatePartyRangeDots).
-- The page's "Display Mode" select maps the pair to dots/numbers/both/none;
-- the dot remembers which mode was active when it was switched off so
-- switching back on restores it (session-only, nothing new is persisted).
local partyBuffLastMode
local POWER_PARTYBUFF = {
	label  = "Party Buff Tracker",
	desc   = "Turn the party range dots and counters on or off.",
	loaded = function() local sp = SP() return sp and sp.PartyRangeLoaded and true or false end,
	get    = function()
		local o = SP().opt
		if not o then return false end
		return (o.showPartyRangeDots or (o.rangeCounter and o.rangeCounter.enabled)) and true or false
	end,
	set    = function(v)
		local sp = SP()
		local o = sp.opt
		if not o then return end
		sp:EnsureProfileTable("rangeCounter")
		if v then
			local mode = partyBuffLastMode or "dots"
			o.showPartyRangeDots   = (mode == "dots" or mode == "both")
			o.rangeCounter.enabled = (mode == "numbers" or mode == "both")
		else
			local dots, nums = o.showPartyRangeDots, o.rangeCounter.enabled
			if dots and nums then partyBuffLastMode = "both"
			elseif nums then partyBuffLastMode = "numbers"
			else partyBuffLastMode = "dots" end
			o.showPartyRangeDots   = false
			o.rangeCounter.enabled = false
		end
		sp:UpdatePartyRangeDots()
		sp:UpdateRangeCounters()
	end,
}

-- Shield Charges: the module is on while either display is on
-- (ShamanPower_ShieldCharges.lua UpdateShieldChargeDisplays: showAny =
-- showPlayerShield ~= false or showEarthShield ~= false). Off clears both;
-- on restores whichever were on before, defaulting to both.
local shieldLastPlayer, shieldLastEarth
local POWER_SHIELDCHARGES = {
	label  = "Shield Charge Display",
	desc   = "Turn the on-screen shield charge numbers on or off.",
	loaded = function() local sp = SP() return sp and sp.ShieldChargesLoaded and true or false end,
	get    = function()
		local o = SP().opt
		local s = o and o.shieldChargeDisplay
		if not s then return false end
		return ((s.showPlayerShield ~= false) or (s.showEarthShield ~= false)) and true or false
	end,
	set    = function(v)
		local sp = SP()
		if not sp.opt then return end
		sp:EnsureProfileTable("shieldChargeDisplay")
		local s = sp.opt.shieldChargeDisplay
		if v then
			local p = shieldLastPlayer
			local e = shieldLastEarth
			if p == nil and e == nil then p, e = true, true end
			s.showPlayerShield = p and true or false
			s.showEarthShield  = e and true or false
		else
			shieldLastPlayer = (s.showPlayerShield ~= false)
			shieldLastEarth  = (s.showEarthShield ~= false)
			s.showPlayerShield = false
			s.showEarthShield  = false
		end
		sp:UpdateShieldChargeDisplays()
	end,
}

-- Sidebar information architecture.
-- An entry is either { label, path = {...} } (one option group = one page) or
-- { label, tabs = { { label, paths = { {...}, ... } }, ... } } (a composed
-- page: each tab shows one or more option groups; with several groups in a
-- tab each gets a section header, overridable with path.label). Anything the
-- map never mentions is appended under "More" automatically.
local function P(...) return { ... } end

local NAV = {
	{ group = "General", entries = {
		{ label = "General", lock = true, desc = "Global behaviour, interface and raid settings.", tabs = {
			{ label = "Main",      paths = { P("settings", "settings_show") } },
			{ label = "Interface", paths = { P("settings", "settings_newui") } },
			{ label = "Raid",      paths = { P("raids", "visibility") } },
			{ label = "Reset",     paths = { P("settings", "settings_frames") } },
		}},
		{ label = "Profiles", path = P("profiles"), lock = true },
	}},
	{ group = "Bars", entries = {
		{ label = "Mode & Twisting", lock = true, desc = "How the totem bar behaves, and totem twisting.", tabs = {
			{ label = "Mode & Twisting", paths = { P("settings", "settings_totemMode") } },
		}},
		{ label = "Appearance", lock = true, desc = "Layout, size, opacity, textures and visibility of the bars.", tabs = {
			{ label = "Layout",            paths = { P("fluffy", "layout_section") } },
			{ label = "Scale & Opacity",   paths = { P("fluffy", "scale_section"), P("fluffy", "opacity_section"), P("fluffy", "padding_section") } },
			{ label = "Textures & Colors", paths = { P("fluffy", "texture_section"), P("fluffy", "color_section") } },
			{ label = "Visibility",        paths = { P("fluffy", "visibility_section"), { "settings", "settings_visibility", label = "Auto-Hide" } } },
		}},
		{ label = "Totem Bar", lock = true, desc = "The totem bar: what it shows, drop order, duration bars, flyouts, macros and loadouts.", tabs = {
			{ label = "Bar",           paths = { P("buttons", "auto_button") } },
			{ label = "Items",         paths = { P("fluffy", "totembar_items_section") } },
			{ label = "Order",         paths = { P("fluffy", "totembar_order_section") } },
			{ label = "Duration Bars", paths = { P("fluffy", "totembar_duration_section") } },
			{ label = "Flyouts",       paths = { P("fluffy", "totemflyouts_section") } },
			{ label = "Macros",        paths = { P("buttons", "macros_section") } },
			{ label = "Loadouts",      paths = { P("buttons", "loadouts_section") } },
			{ label = "Loadout Bar",   paths = { P("fluffy", "loadoutbar_section") } },
		}},
		{ label = "Cooldown Bar", lock = true, desc = "Which cooldowns the bar shows, their order and display.", tabs = {
			{ label = "Items",   paths = { P("fluffy", "cdbar_items_section") } },
			{ label = "Order",   paths = { P("fluffy", "cdbar_order_section") } },
			{ label = "Display", paths = { P("fluffy", "cooldown_display_section") } },
		}},
	}},
	{ group = "Modules", power = true, entries = {
		{ label = "Raid Cooldowns",       path = P("fluffy", "raid_cd_section"), power = false },
		{ label = "Totem Range Tracker",  path = P("fluffy", "sprange_section"), power = POWER_SPRANGE },
		{ label = "Party Buff Tracker",   path = P("fluffy", "partybuff_section"), power = POWER_PARTYBUFF },
		{ label = "Earth Shield Tracker", path = P("fluffy", "estrack_section") },
		{ label = "Shield Charges",       path = P("fluffy", "shieldcharges_section"), power = POWER_SHIELDCHARGES },
		{ label = "Reactive Totems",      path = P("fluffy", "reactivetotems_section") },
		{ label = "Expiring Alerts",      path = P("fluffy", "expiringalerts_section") },
		{ label = "Tremor Reminder",      path = P("fluffy", "tremorreminder_section") },
		{ label = "Totem Plates",         path = P("fluffy", "totemplates_section") },
		{ label = "Pop-Out Trackers", power = false, desc = "Middle-click any bar button to pop it out as a movable tracker.", tabs = {
			{ label = "Pop-Out Trackers", paths = {
				{ "settings", "settings_popout", label = "Middle-Click Pop-Out" },
				{ "fluffy",   "popout_section",  label = "Popped-Out Trackers" },
			}},
		}},
	}},
}

-- Every option-group path an entry draws from.
local function EntryPaths(entry)
	if entry.path then return { entry.path } end
	local out = {}
	for _, t in ipairs(entry.tabs or {}) do
		for _, pth in ipairs(t.paths) do out[#out + 1] = pth end
	end
	return out
end

local function EntryHasPath(entry, path)
	local want = table.concat(path, "/")
	for _, pth in ipairs(EntryPaths(entry)) do
		if table.concat(pth, "/") == want then return true end
	end
	return false
end

-- Any top-level group the map above doesn't mention gets collected here so a
-- newly added tab still shows up without editing NAV.
local function AppendUnmapped(nav)
	local root = Tree:Root()
	if not root or not root.args then return nav end

	local claimed = {}
	for _, g in ipairs(nav) do
		for _, e in ipairs(g.entries) do
			for _, pth in ipairs(EntryPaths(e)) do
				if pth[1] then claimed[pth[1]] = true end
			end
		end
	end

	local extras = {}
	for key, child in pairs(root.args) do
		if type(child) == "table" and child.type == "group" and not claimed[key] then
			-- fluffy is fully redistributed above; skip its container.
			if key ~= "fluffy" then
				local info = Tree:BuildInfo({ key }, child, { root, child })
				table.insert(extras, {
					label = Tree:StripColor(Tree:GetName(child, info)),
					path  = { key },
					lock  = true,
				})
			end
		end
	end

	if #extras > 0 then
		table.sort(extras, function(a, b) return a.label < b.label end)
		table.insert(nav, { group = "More", entries = extras })
	end
	return nav
end

-- ---------------------------------------------------------------------------
-- Frame construction
-- ---------------------------------------------------------------------------
local frame

local function BuildWindow()
	if frame then return frame end

	frame = CreateFrame("Frame", "ShamanPowerConfigUIFrame", UIParent)
	frame:SetSize(WIN_W, WIN_H)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("HIGH")
	-- Clicking a window brings its whole subtree forward; otherwise the other
	-- window's child frames can sit above this one's base and eat the drag.
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:Hide()
	tinsert(UISpecialFrames, "ShamanPowerConfigUIFrame")

	Core:SolidTex(frame, "windowBg", "BACKGROUND", nil, true)
	-- 2px accent frame so the two windows read as separate panels when overlapped.
	Core:MakeBorder(frame, "accent", 2)

	-- Sidebar ---------------------------------------------------------------
	local side = CreateFrame("Frame", nil, frame)
	side:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
	side:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, 1)
	side:SetWidth(SIDEBAR_W)
	Core:SolidTex(side, "sidebarBg", "BACKGROUND", nil, true)
	frame.side = side

	local sideEdge = side:CreateTexture(nil, "BORDER")
	sideEdge:SetWidth(1)
	sideEdge:SetPoint("TOPRIGHT", side, "TOPRIGHT", 0, 0)
	sideEdge:SetPoint("BOTTOMRIGHT", side, "BOTTOMRIGHT", 0, 0)
	sideEdge:SetColorTexture(Core:Color("border"))

	-- Brand
	local brand = side:CreateFontString(nil, "OVERLAY")
	brand:SetFontObject(Core.fonts.brand)
	brand:SetPoint("TOPLEFT", side, "TOPLEFT", 18, -22)
	brand:SetText("|cff0070ddShaman|r|cffE6EAF0Power|r")

	local brandRule = side:CreateTexture(nil, "ARTWORK")
	brandRule:SetHeight(1)
	brandRule:SetPoint("TOPLEFT", brand, "BOTTOMLEFT", 0, -10)
	-- Underline exactly the word "Shaman": measure it in the brand font rather
	-- than guessing a pixel width.
	local measure = side:CreateFontString(nil, "OVERLAY")
	measure:SetFontObject(Core.fonts.brand)
	measure:SetText("Shaman")
	brandRule:SetWidth(math.ceil(measure:GetStringWidth()))
	measure:Hide()
	brandRule:SetColorTexture(Core:Color("accent"))

	local ver = side:CreateFontString(nil, "OVERLAY")
	ver:SetFontObject(Core.fonts.tiny)
	ver:SetPoint("BOTTOMLEFT", side, "BOTTOMLEFT", 18, 14)
	local v = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("ShamanPower", "Version")
		or (GetAddOnMetadata and GetAddOnMetadata("ShamanPower", "Version"))
	ver:SetText("v" .. (v or "?"))

	-- Sidebar search
	local navSearch = CreateFrame("EditBox", nil, side)
	navSearch:SetSize(SIDEBAR_W - 36, 24)
	navSearch:SetPoint("TOPLEFT", brandRule, "BOTTOMLEFT", 0, -16)
	navSearch:SetAutoFocus(false)
	navSearch:SetFontObject(Core.fonts.row)
	navSearch:SetTextInsets(8, 8, 0, 0)
	Core:SolidTex(navSearch, "windowBg", "BACKGROUND")
	Core:MakeBorder(navSearch, "border")
	frame.navSearch = navSearch

	local navPlaceholder = navSearch:CreateFontString(nil, "OVERLAY")
	navPlaceholder:SetFontObject(Core.fonts.rowDim)
	navPlaceholder:SetPoint("LEFT", navSearch, "LEFT", 8, 0)
	navPlaceholder:SetText("Search all settings...")
	navSearch.placeholder = navPlaceholder

	-- Sidebar scroll
	local navScroll = CreateFrame("ScrollFrame", nil, side)
	navScroll:SetPoint("TOPLEFT", navSearch, "BOTTOMLEFT", 0, -12)
	navScroll:SetPoint("BOTTOMRIGHT", side, "BOTTOMRIGHT", -10, 34)
	local navList = CreateFrame("Frame", nil, navScroll)
	navList:SetSize(SIDEBAR_W - 36, 10)
	navScroll:SetScrollChild(navList)
	navScroll:EnableMouseWheel(true)
	navScroll:SetScript("OnMouseWheel", function(self, delta)
		local maxS = math.max(0, navList:GetHeight() - self:GetHeight())
		self:SetVerticalScroll(math.max(0, math.min(maxS, self:GetVerticalScroll() - delta * 30)))
	end)
	frame.navScroll, frame.navList = navScroll, navList
	Core:AttachScrollbar(navScroll, navList, { offset = 3 })

	-- Content ---------------------------------------------------------------
	local content = CreateFrame("Frame", nil, frame)
	content:SetPoint("TOPLEFT", side, "TOPRIGHT", 0, 0)
	content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
	Core:SolidTex(content, "contentBg", "BACKGROUND", nil, true)
	frame.content = content

	local title = content:CreateFontString(nil, "OVERLAY")
	title:SetFontObject(Core.fonts.title)
	title:SetPoint("TOPLEFT", content, "TOPLEFT", CONTENT_PAD + 8, -24)
	frame.title = title

	local subtitle = content:CreateFontString(nil, "OVERLAY")
	subtitle:SetFontObject(Core.fonts.subtitle)
	subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 1, -6)
	subtitle:SetPoint("RIGHT", content, "RIGHT", -240, 0)
	subtitle:SetJustifyH("LEFT")
	frame.subtitle = subtitle

	local glow = Core:AccentGlow(content, 2)
	glow:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(HEADER_H - 12))
	glow:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(HEADER_H - 12))

	-- Close
	local close = CreateFrame("Button", nil, frame)
	close:SetSize(26, 26)
	close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -10)
	Core:MakeBorder(close, "border")
	local closeTxt = close:CreateFontString(nil, "OVERLAY")
	closeTxt:SetFontObject(Core.fonts.row)
	closeTxt:SetPoint("CENTER")
	closeTxt:SetText("X")
	closeTxt:SetTextColor(Core:Color("textDim"))
	close:SetScript("OnEnter", function()
		Core:SetBorderColor(close, "warn")
		closeTxt:SetTextColor(Core:Color("warn"))
	end)
	close:SetScript("OnLeave", function()
		Core:SetBorderColor(close, "border")
		closeTxt:SetTextColor(Core:Color("textDim"))
	end)
	close:SetScript("OnClick", function() frame:Hide() end)

	-- Tab strip
	local tabStrip = CreateFrame("Frame", nil, content)
	tabStrip:SetHeight(TABSTRIP_H)
	tabStrip:SetPoint("TOPLEFT", content, "TOPLEFT", CONTENT_PAD + 8, -HEADER_H)
	tabStrip:SetPoint("RIGHT", content, "RIGHT", -CONTENT_PAD, 0)
	frame.tabStrip = tabStrip
	frame.tabs = {}

	-- Scoped search
	local pageSearch = CreateFrame("EditBox", nil, content)
	pageSearch:SetSize(200, 22)
	-- Sits in the header band, above the accent rule: below the close button
	-- and clear of the tab strip underneath.
	pageSearch:SetPoint("TOPRIGHT", content, "TOPRIGHT", -CONTENT_PAD, -42)
	pageSearch:SetAutoFocus(false)
	pageSearch:SetFontObject(Core.fonts.row)
	pageSearch:SetTextInsets(8, 8, 0, 0)
	Core:SolidTex(pageSearch, "windowBg", "BACKGROUND")
	Core:MakeBorder(pageSearch, "border")
	frame.pageSearch = pageSearch

	local pagePlaceholder = pageSearch:CreateFontString(nil, "OVERLAY")
	pagePlaceholder:SetFontObject(Core.fonts.rowDim)
	pagePlaceholder:SetPoint("LEFT", pageSearch, "LEFT", 8, 0)
	pagePlaceholder:SetText("Search this page...")
	pageSearch.placeholder = pagePlaceholder

	-- Body scroll
	local bodyScroll = CreateFrame("ScrollFrame", nil, content)
	bodyScroll:SetPoint("TOPLEFT", tabStrip, "BOTTOMLEFT", -8, -6)
	bodyScroll:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -CONTENT_PAD, FOOTER_H)
	local body = CreateFrame("Frame", nil, bodyScroll)
	body:SetSize(10, 10)
	bodyScroll:SetScrollChild(body)
	bodyScroll:EnableMouseWheel(true)
	bodyScroll:SetScript("OnMouseWheel", function(self, delta)
		local maxS = math.max(0, body:GetHeight() - self:GetHeight())
		self:SetVerticalScroll(math.max(0, math.min(maxS, self:GetVerticalScroll() - delta * 40)))
	end)
	-- Created once and toggled. Previously this was built inside RenderPage and
	-- never tracked in pageWidgets, so it survived ClearPage and then sat
	-- underneath the rows of every page rendered afterwards.
	local emptyText = body:CreateFontString(nil, "OVERLAY")
	emptyText:SetFontObject(Core.fonts.rowDim)
	emptyText:SetPoint("TOPLEFT", body, "TOPLEFT", 12, -20)
	emptyText:Hide()
	frame.emptyText = emptyText

	frame.bodyScroll, frame.body = bodyScroll, body
	Core:AttachScrollbar(bodyScroll, body, { offset = 6 })

	-- Footer
	local footRule = content:CreateTexture(nil, "ARTWORK")
	footRule:SetHeight(1)
	footRule:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 0, FOOTER_H)
	footRule:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, FOOTER_H)
	footRule:SetColorTexture(Core:Color("border"))

	-- Every footer button anchors to a content edge with an explicit x offset.
	-- Chaining one button off another's corner made it inherit the y offset
	-- twice and sit high.
	local function FooterButton(text, width, side, xOff, primary)
		local b = CreateFrame("Button", nil, content)
		b:SetSize(width, 26)
		local point = (side == "left") and "BOTTOMLEFT" or "BOTTOMRIGHT"
		b:SetPoint(point, content, point, xOff, 14)
		local bg = b:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints(b)
		bg:SetColorTexture(Core:Color("accent", primary and 0.30 or 0.12))
		Core:MakeBorder(b, primary and "accent" or "border")
		local t = b:CreateFontString(nil, "OVERLAY")
		t:SetFontObject(Core.fonts.button)
		t:SetPoint("CENTER")
		t:SetText(text)
		t:SetTextColor(Core:Color(primary and "accentHi" or "text"))
		b:SetWidth(math.max(width, t:GetStringWidth() + 28))
		b:SetScript("OnEnter", function() bg:SetColorTexture(Core:Color("accent", primary and 0.48 or 0.26)) end)
		b:SetScript("OnLeave", function() bg:SetColorTexture(Core:Color("accent", primary and 0.30 or 0.12)) end)
		return b, b:GetWidth()
	end

	local reload, reloadW = FooterButton("Reload UI", 100, "left", CONTENT_PAD, false)
	reload:SetScript("OnClick", function() ReloadUI() end)

	local aceBtn = FooterButton("Old Options", 110, "left", CONTENT_PAD + reloadW + 8, false)
	aceBtn:SetScript("OnClick", function()
		frame:Hide()
		local acd = LibStub and LibStub("AceConfigDialog-3.0", true)
		if acd then acd:Open("ShamanPower") end
	end)

	local done = FooterButton("Done", 110, "right", -CONTENT_PAD, true)
	done:SetScript("OnClick", function() frame:Hide() end)

	-- Combat lock. Only pages whose setters actually reach a combat-guarded
	-- function get this; a page of colours and sliders stays fully usable.
	-- Covers the body only, so the sidebar and tabs remain navigable.
	local combatBlock = CreateFrame("Frame", nil, content)
	combatBlock:SetPoint("TOPLEFT", bodyScroll, "TOPLEFT", 0, 0)
	combatBlock:SetPoint("BOTTOMRIGHT", bodyScroll, "BOTTOMRIGHT", 0, 0)
	combatBlock:SetFrameLevel(bodyScroll:GetFrameLevel() + 20)
	combatBlock:EnableMouse(true)
	combatBlock:Hide()

	local shade = combatBlock:CreateTexture(nil, "BACKGROUND")
	shade:SetAllPoints(combatBlock)
	shade:SetColorTexture(0, 0, 0, 0.62)

	local blockText = combatBlock:CreateFontString(nil, "OVERLAY")
	blockText:SetFontObject(Core.fonts.title)
	blockText:SetTextColor(Core:Color("warn"))
	blockText:SetPoint("CENTER", combatBlock, "CENTER", 0, 8)
	blockText:SetText("Can't change these options in combat")

	local blockHint = combatBlock:CreateFontString(nil, "OVERLAY")
	blockHint:SetFontObject(Core.fonts.rowDim)
	blockHint:SetPoint("TOP", blockText, "BOTTOM", 0, -8)
	blockHint:SetText("Other pages are still available.")

	-- Reading while locked is fine, so pass the wheel through to the scroll.
	combatBlock:EnableMouseWheel(true)
	combatBlock:SetScript("OnMouseWheel", function(_, delta)
		local handler = bodyScroll:GetScript("OnMouseWheel")
		if handler then handler(bodyScroll, delta) end
	end)

	frame.combatBlock = combatBlock

	-- Catch the case where the window is opened while already in combat.
	frame:SetScript("OnShow", function() SPConfig:UpdateCombatLock() end)
	-- The dropdown popup is parented to UIParent so it can escape the scroll
	-- clip; it must not outlive the window.
	frame:SetScript("OnHide", function() Widgets:HidePopup() end)

	-- Safety net. The regen events below are the real mechanism; this only
	-- covers a state change that arrives without one. Four comparisons a
	-- second against a cached boolean, and it stops the moment the state
	-- matches what is already drawn.
	frame:SetScript("OnUpdate", function(self, elapsed)
		self._combatPoll = (self._combatPoll or 0) + elapsed
		if self._combatPoll < 0.25 then return end
		self._combatPoll = 0
		local inCombat = InCombatLockdown() and true or false
		if inCombat ~= self._lastCombat then
			self._lastCombat = inCombat
			SPConfig:UpdateCombatLock()
			Widgets:RefreshAll(self.body)
		end
	end)

	return frame
end

-- ---------------------------------------------------------------------------
-- Sidebar rendering
-- ---------------------------------------------------------------------------
local navRows = {}
local navPool = {}
local navPoolUsed = 0

-- Sidebar rows are recycled. Search re-renders the nav on every change, so
-- allocating fresh frames here would leak steadily while the user types.
local function AcquireNavRow(list)
	navPoolUsed = navPoolUsed + 1
	local row = navPool[navPoolUsed]
	if row then
		row:SetParent(list)
		row:Show()
		if row.power then row.power:Hide() end
		row.paintPower = nil
		return row, false
	end
	row = CreateFrame("Button", nil, list)
	navPool[navPoolUsed] = row
	return row, true
end

-- Returns getter, setter, tooltip title, tooltip body -- or nil for no dot.
-- Explicit entry.power table first (gated by its `loaded`), `power = false`
-- opts out, anything else falls back to the "Enable ..." toggle heuristic.
local function ResolvePower(entry)
	local pw = entry.power
	if pw == false then return nil end
	if type(pw) == "table" then
		if pw.loaded and not pw.loaded() then return nil end
		if type(pw.get) ~= "function" or type(pw.set) ~= "function" then return nil end
		return pw.get, pw.set, pw.label or entry.label, pw.desc
	end
	local enableEntry = Tree:FindEnableToggle(entry._node, entry._firstPath or entry.path, entry._chain)
	if not enableEntry then return nil end
	return Tree:MakeGetter(enableEntry.node, enableEntry.chain, enableEntry.info),
		Tree:MakeSetter(enableEntry.node, enableEntry.chain, enableEntry.info),
		enableEntry.label, enableEntry.desc
end

local function SelectEntry(entry)
	frame._current = entry
	frame._activeTab = nil
	frame.pageSearch:SetText("")
	frame.pageSearch.placeholder:Show()
	SPConfig:RenderPage(entry, nil)
	for _, r in ipairs(navRows) do
		local on = (r.entry == entry)
		r.accent:SetShown(on)
		r.text:SetFontObject(on and Core.fonts.navOn or Core.fonts.nav)
		r.bg:SetColorTexture(Core:Color(on and "rowHover" or "sidebarBg", on and 1 or 0))
	end
end

function SPConfig:RenderNav(query)
	local list = frame.navList
	for _, r in ipairs(navRows) do r:Hide() end
	wipe(navRows)
	navPoolUsed = 0

	local nav = AppendUnmapped({ unpack(NAV) })
	local y = 0
	local idx = 0
	local firstVisible

	for _, groupDef in ipairs(nav) do
		local visibleEntries = {}
		for _, entry in ipairs(groupDef.entries) do
			local node, chain, firstPath
			for _, pth in ipairs(EntryPaths(entry)) do
				local n, c = Tree:Resolve(pth)
				if n then node, chain, firstPath = n, c, pth break end
			end
			if node then
				entry._node, entry._chain, entry._firstPath = node, chain, firstPath
				if not entry._terms then
					entry._terms = {}
					for _, pth in ipairs(EntryPaths(entry)) do
						local n, c = Tree:Resolve(pth)
						if n then
							for _, term in ipairs(Tree:IndexPage(n, pth, c)) do entry._terms[#entry._terms + 1] = term end
						end
					end
				end
				local labelMatch = (not query) or query == ""
					or strfind(strlower(entry.label), query, 1, true)
				if labelMatch or Tree:TermsMatch(entry._terms, query) then
					table.insert(visibleEntries, entry)
				end
			end
		end

		if #visibleEntries > 0 then
			local gh = list.groupHeaders and list.groupHeaders[groupDef.group]
			if not gh then
				gh = list:CreateFontString(nil, "OVERLAY")
				gh:SetFontObject(Core.fonts.group)
				list.groupHeaders = list.groupHeaders or {}
				list.groupHeaders[groupDef.group] = gh
			end
			gh:ClearAllPoints()
			gh:SetPoint("TOPLEFT", list, "TOPLEFT", 8, -(y + 8))
			gh:SetText(strupper(groupDef.group))
			gh:Show()
			y = y + NAV_GROUP_H + 4

			for _, entry in ipairs(visibleEntries) do
				idx = idx + 1
				firstVisible = firstVisible or entry

				local row, isNew = AcquireNavRow(list)
				row:SetSize(list:GetWidth(), NAV_ROW_H)
				row:ClearAllPoints()
				row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -y)

				if isNew then
					row.bg = row:CreateTexture(nil, "BACKGROUND")
					row.bg:SetAllPoints(row)

					row.accent = row:CreateTexture(nil, "ARTWORK")
					row.accent:SetWidth(2)
					row.accent:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
					row.accent:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
					row.accent:SetColorTexture(Core:Color("accent"))

					row.text = row:CreateFontString(nil, "OVERLAY")
					row.text:SetPoint("LEFT", row, "LEFT", 16, 0)
					row.text:SetJustifyH("LEFT")
				end

				row.bg:SetColorTexture(0, 0, 0, 0)
				row.accent:Hide()
				row.text:SetFontObject(Core.fonts.nav)
				row.text:SetText(Tree:StripColor(entry.label))

				-- Power dot: an explicit binding on the entry wins, otherwise an
				-- "Enable ..." toggle found in the page is promoted.
				if groupDef.power then
					local getter, setter, tipTitle, tipBody = ResolvePower(entry)
					if getter then
						local pw = row.power
						if not pw then
							pw = CreateFrame("Button", nil, row)
							pw:SetSize(14, 14)
							pw:SetPoint("RIGHT", row, "RIGHT", -10, 0)
							pw.dot = pw:CreateTexture(nil, "ARTWORK")
							pw.dot:SetAllPoints(pw)
							row.power = pw
						end
						pw:Show()
						local dot = pw.dot
						local function PaintDot()
							dot:SetColorTexture(Core:ColorIf(getter(), "on", "off"))
						end
						pw:SetScript("OnClick", function()
							setter(not getter())
							PaintDot()
							if frame._current == entry then SPConfig:RenderPage(entry, nil) end
						end)
						Core:AttachTooltip(pw, tipTitle, tipBody)
						PaintDot()
						row.power = pw
						row.paintPower = PaintDot
					end
				end

				row.entry = entry
				row:SetScript("OnEnter", function(self)
					if frame._current ~= self.entry then
						self.bg:SetColorTexture(Core:Color("rowHover", 0.5))
					end
				end)
				row:SetScript("OnLeave", function(self)
					if frame._current ~= self.entry then
						self.bg:SetColorTexture(0, 0, 0, 0)
					end
				end)
				row:SetScript("OnClick", function(self) SelectEntry(self.entry) end)

				table.insert(navRows, row)
				y = y + NAV_ROW_H
			end
			y = y + 8
		else
			local gh = list.groupHeaders and list.groupHeaders[groupDef.group]
			if gh then gh:Hide() end
		end
	end

	list:SetHeight(math.max(y, 1))
	if frame.navScroll.spScrollbarUpdate then frame.navScroll.spScrollbarUpdate() end
	return firstVisible
end

-- ---------------------------------------------------------------------------
-- Page rendering
-- ---------------------------------------------------------------------------
local pageWidgets = {}
local tabPool = {}

-- A page with three or more child groups renders them as a tab strip rather
-- than one long stack of sections. Fewer than that and stacking reads better.
local TAB_MIN_GROUPS = 3

local function ChildGroups(node, path, chain)
	local groups = {}
	for _, c in ipairs(Tree:SortedChildren(node, path, chain)) do
		if c.node.type == "group" and not Tree:IsHidden(c.node, c.chain, c.info) then
			table.insert(groups, c)
		end
	end
	return groups
end

local function RenderTabs(groups, activeKey, onPick)
	for _, t in ipairs(tabPool) do t:Hide() end
	if #groups == 0 then
		frame.tabStrip:SetHeight(1)
		return
	end
	frame.tabStrip:SetHeight(TABSTRIP_H)

	local x = 0
	for i, g in ipairs(groups) do
		local tab = tabPool[i]
		if not tab then
			tab = CreateFrame("Button", nil, frame.tabStrip)
			tab:SetHeight(TABSTRIP_H)
			tab.text = tab:CreateFontString(nil, "OVERLAY")
			tab.text:SetPoint("CENTER", tab, "CENTER", 0, 1)
			tab.underline = tab:CreateTexture(nil, "ARTWORK")
			tab.underline:SetHeight(2)
			tab.underline:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 0, 0)
			tab.underline:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", 0, 0)
			tab.underline:SetColorTexture(Core:Color("accent"))
			tabPool[i] = tab
		end

		local label = Tree:StripColor(g.name ~= "" and g.name or g.key)
		tab.text:SetFontObject(Core.fonts.nav)
		tab.text:SetText(label)
		tab:SetWidth(math.max(tab.text:GetStringWidth() + 26, 60))
		tab:ClearAllPoints()
		tab:SetPoint("BOTTOMLEFT", frame.tabStrip, "BOTTOMLEFT", x, 0)

		local isActive = (g.key == activeKey)
		tab.text:SetFontObject(isActive and Core.fonts.navOn or Core.fonts.nav)
		tab.underline:SetShown(isActive)
		tab._key = g.key
		tab:SetScript("OnClick", function(self) onPick(self._key) end)
		tab:SetScript("OnEnter", function(self)
			if self._key ~= activeKey then self.text:SetFontObject(Core.fonts.navOn) end
		end)
		tab:SetScript("OnLeave", function(self)
			if self._key ~= activeKey then self.text:SetFontObject(Core.fonts.nav) end
		end)
		tab:Show()

		x = x + tab:GetWidth()
	end
end

-- Widgets go back to their pools rather than being orphaned; pageWidgets is
-- kept only as the "did this render draw anything" count for the empty state.
local function ClearPage()
	Widgets:ReleaseAll(frame.body)
	wipe(pageWidgets)
end

local function OptionOpts(entry, sectionRef, x, y, width, onChanged)
	local node, chain, info = entry.node, entry.chain, entry.info
	return {
		label    = Tree:StripColor(entry.label),
		desc     = entry.desc and Tree:StripColor(entry.desc) or nil,
		x = x, y = y, width = width,
		section  = sectionRef,
		disabled = function() return Tree:IsDisabled(node, chain, info) end,
		onChanged = onChanged,
	}
end

local function FilterList(list, query)
	if not (query and query ~= "") then return list end
	local filtered, pendingSection = {}, nil
	for _, e in ipairs(list) do
		if e.kind == "section" then
			pendingSection = e
		else
			local hay = strlower((e.label or "") .. " " .. (e.desc or ""))
			if strfind(hay, query, 1, true) then
				if pendingSection then
					table.insert(filtered, pendingSection)
					pendingSection = nil
				end
				table.insert(filtered, e)
			end
		end
	end
	return filtered
end

local function PickTab(tabs, onPick, drawTabs, searching)
	local active
	for _, t in ipairs(tabs) do
		if t.key == frame._activeTab then active = t break end
	end
	active = active or tabs[1]
	if drawTabs then
		frame._activeTab = active.key
		if #tabs >= 2 then
			RenderTabs(tabs, searching and nil or active.key, onPick)
		else
			RenderTabs({}, nil, function() end)
		end
	end
	return active
end

local function OnTabPick(key)
	frame._activeTab = key
	SPConfig:RenderPage(frame._current, nil)
end

-- Composed page: entry.tabs -> each tab draws one or more option groups.
local function ResolveComposed(entry, query, drawTabs)
	local searching = (query and query ~= "")
	local tabs = {}
	for _, t in ipairs(entry.tabs) do
		local live = {}
		for _, pth in ipairs(t.paths) do
			local n, c = Tree:Resolve(pth)
			if n and not Tree:IsHidden(n, c, Tree:BuildInfo(pth, n, c)) then
				live[#live + 1] = { node = n, chain = c, path = pth }
			end
		end
		if #live > 0 then tabs[#tabs + 1] = { key = t.label, name = t.label, live = live } end
	end
	if #tabs == 0 then
		if drawTabs then RenderTabs({}, nil, function() end) end
		return {}, {}
	end
	local active = PickTab(tabs, OnTabPick, drawTabs, searching)
	local list = {}
	for _, t in ipairs(searching and tabs or { active }) do
		for _, lv in ipairs(t.live) do
			if #t.live > 1 or (searching and #tabs > 1) then
				local info = Tree:BuildInfo(lv.path, lv.node, lv.chain)
				local label = lv.path.label or Tree:StripColor(Tree:GetName(lv.node, info))
				if searching and #tabs > 1 and #t.live == 1 then label = t.name end
				table.insert(list, { kind = "section", label = label, depth = 0 })
			end
			Tree:BuildRenderList(lv.node, lv.path, lv.chain, list, 0)
		end
	end
	return FilterList(list, query), tabs
end

-- Resolve a sidebar entry to the exact list of rows that should be on screen:
-- tab selection, hidden= evaluation (inside BuildRenderList) and the page
-- search filter. Used by RenderPage to draw, and by onChanged to detect that
-- a set() just changed which rows are visible.
local function ResolvePageList(entry, query, drawTabs)
	if entry.tabs then return ResolveComposed(entry, query, drawTabs) end

	local node, chain = Tree:Resolve(entry.path)
	if not node then return nil end

	local groups = ChildGroups(node, entry.path, chain)
	local useTabs = (#groups >= TAB_MIN_GROUPS)
	local searching = (query and query ~= "")

	local renderNode, renderPath, renderChain = node, entry.path, chain
	if useTabs then
		local active = PickTab(groups, OnTabPick, drawTabs, searching)
		if not searching then
			renderNode, renderPath, renderChain = active.node, active.path, active.chain
		end
	elseif drawTabs then
		RenderTabs({}, nil, function() end)
	end

	local list = Tree:BuildRenderList(renderNode, renderPath, renderChain)
	return FilterList(list, query), groups
end

-- Fingerprint of what is visible: tab keys plus every row's path/label.
local function PageSignature(list, groups)
	local parts = {}
	for _, g in ipairs(groups or {}) do parts[#parts + 1] = "T:" .. tostring(g.key) end
	for _, e in ipairs(list or {}) do
		if e.kind == "section" then
			parts[#parts + 1] = "S:" .. tostring(e.label)
		else
			parts[#parts + 1] = table.concat(e.path, "/")
		end
	end
	return table.concat(parts, "|")
end

function SPConfig:RenderPage(entry, query, keepScroll)
	ClearPage()
	if not entry then return end

	local firstPath = entry._firstPath or entry.path or EntryPaths(entry)[1]
	local node, chain = firstPath and Tree:Resolve(firstPath)
	if not node then return end

	local info = Tree:BuildInfo(firstPath, node, chain)
	frame.title:SetText(Tree:StripColor(entry.label))
	frame.subtitle:SetText(Tree:StripColor(entry.desc or Tree:GetDesc(node, info) or ""))

	local list, groups = ResolvePageList(entry, query, true)
	if not list then return end
	frame._query = query
	frame._pageSig = PageSignature(list, groups)

	local body = frame.body
	local fullW = frame.bodyScroll:GetWidth() - 8
	if fullW <= 1 then
		-- Anchors have not resolved yet on the first draw; fall back to geometry.
		fullW = WIN_W - SIDEBAR_W - (CONTENT_PAD * 2) - 8
	end
	body:SetWidth(fullW)
	local colW = math.floor((fullW - COL_GAP) / 2)

	local y, col, rowY, rowMaxH = 0, 1, 0, 0
	local currentSection

	local function BreakRow()
		if col == 2 then
			y = rowY + rowMaxH
			col, rowMaxH = 1, 0
			rowY = y
		end
	end

	local onChanged = function()
		-- A set() may flip another option's hidden= (e.g. TotemTimers Style
		-- Display reveals Right-Click Drops Corner Totem). Re-resolve the page
		-- and redraw only when the visible row set actually changed.
		local cur = frame._current
		if cur then
			local newList, newGroups = ResolvePageList(cur, frame._query, false)
			if newList and PageSignature(newList, newGroups) ~= frame._pageSig then
				SPConfig:RenderPage(cur, frame._query, frame.bodyScroll:GetVerticalScroll())
				if LibStub then
					local reg = LibStub("AceConfigRegistry-3.0", true)
					if reg then reg:NotifyChange("ShamanPower") end
				end
				return
			end
		end
		Widgets:RefreshAll(body)
		for _, r in ipairs(navRows) do
			if r.paintPower and r:IsShown() then r.paintPower() end
		end
		if LibStub then
			local reg = LibStub("AceConfigRegistry-3.0", true)
			if reg then reg:NotifyChange("ShamanPower") end
		end
	end

	for _, e in ipairs(list) do
		if e.kind == "section" then
			BreakRow()
			local f, h = Widgets:SectionHeader(body, {
				label = Tree:StripColor(e.label), x = 0, y = y, width = fullW,
			})
			table.insert(pageWidgets, f)
			currentSection = f
			y = y + h
			rowY = y
		else
			local span = Tree:ColumnSpan(e.node, e.info)
			local w  = (span == 2) and fullW or colW
			if span == 2 then BreakRow() end
			local x  = (span == 2 or col == 1) and 0 or (colW + COL_GAP)

			local opts = OptionOpts(e, currentSection, x, rowY, w, onChanged)
			local f, h

			if e.type == "toggle" then
				opts.get = Tree:MakeGetter(e.node, e.chain, e.info)
				local setter = Tree:MakeSetter(e.node, e.chain, e.info)
				opts.set = function(v) setter(v) end
				f, h = Widgets:Toggle(body, opts)

			elseif e.type == "range" then
				opts.get = Tree:MakeGetter(e.node, e.chain, e.info)
				local setter = Tree:MakeSetter(e.node, e.chain, e.info)
				opts.set = function(v) setter(v) end
				opts.min  = Tree:EvalPlain(e.node.min, e.info) or 0
				opts.max  = Tree:EvalPlain(e.node.max, e.info) or 100
				opts.step = Tree:EvalPlain(e.node.step, e.info) or 1
				f, h = Widgets:Slider(body, opts)

			elseif e.type == "select" then
				opts.get = Tree:MakeGetter(e.node, e.chain, e.info)
				local setter = Tree:MakeSetter(e.node, e.chain, e.info)
				opts.set = function(v) setter(v) end
				opts.values = Tree:MakeValues(e.node, e.info)
				opts.order  = Tree:MakeSorting(e.node, e.info)
				f, h = Widgets:Dropdown(body, opts)

			elseif e.type == "color" then
				opts.get = Tree:MakeGetter(e.node, e.chain, e.info)
				local setter = Tree:MakeSetter(e.node, e.chain, e.info)
				opts.set = function(r, g, b, a) setter(r, g, b, a) end
				opts.hasAlpha = Tree:EvalPlain(e.node.hasAlpha, e.info) and true or false
				f, h = Widgets:Color(body, opts)

			elseif e.type == "input" then
				opts.get = Tree:MakeGetter(e.node, e.chain, e.info)
				local setter = Tree:MakeSetter(e.node, e.chain, e.info)
				opts.set = function(v) setter(v) end
				f, h = Widgets:Input(body, opts)

			elseif e.type == "execute" then
				opts.func = Tree:MakeFunc(e.node, e.chain, e.info)
				opts.buttonText = Tree:StripColor(e.label)
				f, h = Widgets:Button(body, opts)

			elseif e.type == "description" then
				opts.text = Tree:StripColor(e.label)
				BreakRow()
				opts.x, opts.y, opts.width = 0, rowY, fullW
				f, h = Widgets:Description(body, opts)
				table.insert(pageWidgets, f)
				y = rowY + h
				rowY = y
				h = nil
			end

			if f and h then
				table.insert(pageWidgets, f)
				if span == 2 then
					y = rowY + h
					rowY = y
					col, rowMaxH = 1, 0
				else
					rowMaxH = math.max(rowMaxH, h)
					if col == 2 then
						y = rowY + rowMaxH
						rowY = y
						col, rowMaxH = 1, 0
					else
						col = 2
					end
				end
			end
		end
	end

	self:UpdateCombatLock()

	BreakRow()
	if col == 1 and rowMaxH > 0 then y = rowY + rowMaxH end
	body:SetHeight(math.max(y + 20, 1))
	local maxScroll = math.max(0, body:GetHeight() - frame.bodyScroll:GetHeight())
	frame.bodyScroll:SetVerticalScroll(math.max(0, math.min(keepScroll or 0, maxScroll)))

	if #pageWidgets == 0 then
		frame.emptyText:SetText(
			(query and query ~= "") and "No settings match that search."
			or "Nothing to configure here.")
		frame.emptyText:Show()
	else
		frame.emptyText:Hide()
	end
end

-- ---------------------------------------------------------------------------
-- Wiring
-- ---------------------------------------------------------------------------
local function WireSearch()
	local navSearch = frame.navSearch
	local navPending
	navSearch:SetScript("OnTextChanged", function(self)
		local q = strtrim(strlower(self:GetText() or ""))
		self.placeholder:SetShown(q == "")
		navPending = q
		C_Timer.After(0.2, function()
			if navPending ~= q then return end
			local first = SPConfig:RenderNav(q ~= "" and q or nil)
			if q ~= "" and first and frame._current ~= first then
				SelectEntry(first)
				frame.pageSearch:SetText(q)
			end
		end)
	end)
	navSearch:SetScript("OnEscapePressed", function(self)
		self:SetText("")
		self:ClearFocus()
	end)

	local pageSearch = frame.pageSearch
	local pagePending
	pageSearch:SetScript("OnTextChanged", function(self)
		local q = strtrim(strlower(self:GetText() or ""))
		self.placeholder:SetShown(q == "")
		pagePending = q
		C_Timer.After(0.2, function()
			if pagePending ~= q then return end
			SPConfig:RenderPage(frame._current, q ~= "" and q or nil)
		end)
	end)
	pageSearch:SetScript("OnEscapePressed", function(self)
		self:SetText("")
		self:ClearFocus()
	end)
end

function SPConfig:Open(path)
	BuildWindow()
	if not frame._wired then
		WireSearch()
		frame._wired = true
	end
	frame:Show()
	frame:Raise()
	Core:SyncOpacity()
	self:UpdateCombatLock()
	local first = self:RenderNav(nil)
	if path then
		for _, r in ipairs(navRows) do
			if r.entry and EntryHasPath(r.entry, path) then
				SelectEntry(r.entry)
				return
			end
		end
	end
	SelectEntry(frame._current or first)
end

-- Lives for the session regardless of whether the window has ever been built,
-- so entering combat always reaches UpdateCombatLock.
local combatWatcher = CreateFrame("Frame")
combatWatcher:RegisterEvent("PLAYER_REGEN_DISABLED")
combatWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
combatWatcher:SetScript("OnEvent", function()
	SPConfig:UpdateCombatLock()
	if frame and frame:IsShown() and frame.body then
		frame._lastCombat = InCombatLockdown() and true or false
		Widgets:RefreshAll(frame.body)
	end
end)

function SPConfig:UpdateCombatLock()
	if not frame or not frame.combatBlock then return end
	local entry = frame._current
	local locked = InCombatLockdown() and entry and entry.lock
	local block = frame.combatBlock
	block:SetShown(locked and true or false)
	if locked then
		-- Raise above the scroll child's regions, which can otherwise draw over
		-- a plain sibling frame.
		block:SetFrameLevel(frame.body:GetFrameLevel() + 25)
	end
end

function SPConfig:Toggle()
	if frame and frame:IsShown() then
		frame:Hide()
	else
		self:Open()
	end
end

-- Widget pool report. Re-render the same page any number of times (tab
-- clicks, page search, power dot) and `created` must not move.
function SPConfig:PrintPoolStats()
	local stats = Widgets:PoolStats()
	local kinds = {}
	for kind in pairs(stats) do table.insert(kinds, kind) end
	table.sort(kinds)
	print("|cff0070ddShamanPower|r config widget pools (created / in use):")
	local created, inUse = 0, 0
	for _, kind in ipairs(kinds) do
		local s = stats[kind]
		created, inUse = created + s.created, inUse + s.inUse
		print(string.format("  %-12s %3d / %3d", kind, s.created, s.inUse))
	end
	print(string.format("  %-12s %3d / %3d", "total", created, inUse))
	print(string.format("  %-12s %3d / %3d", "nav rows", #navPool, navPoolUsed))
	print(string.format("  %-12s %3d", "tabs", #tabPool))
end

-- Slash command kept separate from the shipped /sp so both paths stay usable
-- while this is being evaluated. "/spui stats" prints the pool report.
-- ---------------------------------------------------------------------------
-- Options contributed by this module
-- ---------------------------------------------------------------------------
local function InjectOptions()
	local root = ShamanPower and ShamanPower.options
	local settings = root and root.args and root.args.settings
	if not settings or not settings.args then return end
	if settings.args.settings_newui then return end

	local baseOrder = 1
	local show = settings.args.settings_show
	if show and type(show.order) == "number" then baseOrder = show.order end

	settings.args.settings_newui = {
		order = baseOrder + 0.5,
		name = "New UI",
		type = "group",
		inline = true,
		args = {
			uiOpacity = {
				order = 1,
				name = "Background Opacity",
				desc = "How solid the panels of the options and assignment windows are. Text, icons and borders always stay fully visible.",
				type = "range",
				min = 20, max = 100, step = 5,
				width = "full",
				get = function()
					return math.floor(((ShamanPower.opt.uiOpacity or 1) * 100) + 0.5)
				end,
				set = function(_, v)
					ShamanPower.opt.uiOpacity = v / 100
					Core:ApplyOpacity(v / 100)
				end,
			},
		},
	}
end
InjectOptions()

SLASH_SHAMANPOWERCONFIG1 = "/spui"
SlashCmdList["SHAMANPOWERCONFIG"] = function(msg)
	msg = strtrim(strlower(msg or ""))
	if msg == "stats" then
		SPConfig:PrintPoolStats()
		return
	end
	SPConfig:Toggle()
end

return SPConfig
