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

-- Geometry (the D32b "lit" mockup: settings_glowup_b_mock.py window(style="lit")) ----
local WIN_W, WIN_H   = 1000, 640
local SIDEBAR_W      = 244
local CONTENT_W      = WIN_W - SIDEBAR_W
local HEADER_H       = 96      -- the header band
local FOOTER_H       = 54
local TABSTRIP_H     = 34
local CONTENT_PAD    = 16
local COL_GAP        = 12
local NAV_ROW_H      = 24
local NAV_GROUP_H    = 24
local NAV_GROUP_GAP  = 6       -- under each group's last row
local ACTION_ROW_H   = 26      -- Unlock UI / Keybind Mode / UI Animations at the top of the sidebar (D30b A1)
local CARD_TOP       = 6       -- the first section card under the tabs
local CARD_GAP       = 12      -- between section cards

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

-- Live-preview specs for the bar pages: the setup wizard's own mocks of the
-- bars, drawn from the live options (they follow style, Compact, layout and
-- the rest as they change). A module page names its registered preview
-- instead (a string, see ShamanPowerPreview).
local MOCK_TOTEM    = { mocks = { { label = "Totem bar",     build = "BuildTotemBarPane" } } }
local MOCK_DURATION = { mocks = { { label = "Duration bars", build = "BuildDurationBarsPane" } } }
local MOCK_CDBAR    = { mocks = { { label = "Cooldown bar",  build = "BuildCooldownBarStep" } } }
local MOCK_BARS     = { mocks = { MOCK_TOTEM.mocks[1], MOCK_CDBAR.mocks[1] } }
-- the Totem Bar's Effects tab: its preview with its effects playing on it
local MOCK_TOTEM_EFFECTS = { mocks = MOCK_TOTEM.mocks, effects = true }
local MOCK_THEMES   = { mocks = MOCK_BARS.mocks }   -- General > Themes: the split bar preview, rebuilt on every theme change (no Effects: themes are not effects)
-- which bar a mock is, for a theme's flat boxes on it (SP:ThemeSkinPreview)
local MOCK_SKIN_FAMILY = {
	BuildTotemBarPane = "totembar", BuildDurationBarsPane = "totembar", BuildPartyBuffStep = "totembar",
	BuildCooldownBarStep = "cooldownbar", BuildLoadoutBarPane = "loadout", BuildLoadoutSetsPane = "loadout",
}
local MOCK_LOADOUT  = { mocks = {
	{ label = "Loadout bar", build = "BuildLoadoutBarPane" },
	{ label = "Blizzard totem sets", build = "BuildLoadoutSetsPane", when = function()
		local sp = SP()
		return SPCompat.FOREVER and sp and sp.HasTotemBar and sp:HasTotemBar()
	end },
} }
local MOCK_PARTY    = { mocks = {
	{ label = "Party Buff Tracker", build = "BuildPartyBuffStep", weight = 2.3, shiftY = 85 },
} }
-- General > Themes: the preview each module section shows while it is in view
-- (the same one as that module's own settings page). Sections not listed, and the
-- top of the tab, show MOCK_THEMES: both bars.
local THEMES_SECTION_PREVIEW = {
	totembar = MOCK_TOTEM, cooldownbar = MOCK_CDBAR, loadouts = MOCK_LOADOUT, partybuff = MOCK_PARTY,
	shieldcharges = "shieldcharges", alerts = "expiring", range = "sprange", raidcd = "raidcd",
	estracker = "estracker", reactive = "reactive", readyreminders = "readyreminders", tremor = "tremor",
	readycheck = "readycheck", plates = "totemplates",
}

-- Totem Range Tracker: the module's on/off is the overlay frame itself.
-- ShamanPower_SPRange.lua ToggleSPRange() is the only writer of
-- ShamanPower_RangeTracker.shown / spRangeManuallyOpened; the live truth is
-- whether spRangeFrame is shown, which is also what the auto-show path
-- (UpdateSPRangeVisibility) drives.
-- Raid Resistance: its page leads with "Raid Resistance Requests", not an
-- "Enable ..." name, so the square runs that toggle's own get/set. WoW: Forever
-- only: without the group there is no square.
local function ResistToggle()
	local sp = SP()
	local g = sp and sp.options and sp.options.args.buttons and sp.options.args.buttons.args.resist_section
	return g and g.args and g.args.enabled
end
local POWER_RESIST = {
	label  = "Raid Resistance Requests",
	desc   = "Off: no Raid Resistance ticks, and a request that picks you passes straight to the next shaman.",
	loaded = function() return ResistToggle() ~= nil end,
	get    = function() local t = ResistToggle() return t and t.get() and true or false end,
	set    = function(v) local t = ResistToggle() if t then t.set(nil, v and true or false) end end,
}

local POWER_SPRANGE = {
	label  = "Totem Range overlay",
	desc   = "Show or hide Totem Range Tracker. You can also use /sprange toggle.",
	loaded = function() local sp = SP() return sp and sp.SPRangeLoaded and true or false end,
	get    = function()   -- on also while it waits for a group (Show the Overlay)
		local sp = SP()
		return sp.SPRangeOverlayOn ~= nil and sp:SPRangeOverlayOn()
	end,
	set    = function(v)
		local sp = SP()
		if (v and true or false) ~= sp:SPRangeOverlayOn() then sp:ToggleSPRange() end
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
-- Ready Reminders' on / off (D40: its page has no Enable row any more)
local POWER_READYREMINDERS = {
	label  = "Ready Reminders",
	desc   = "Turn Ready Reminders on or off.",
	loaded = function() local sp = SP() return sp and sp.ReadyRemindersLoaded and sp.ReadyRemindersEnabled and true or false end,
	get    = function() return SP().ReadyRemindersEnabled() end,
	set    = function(v) SP():SetReadyRemindersEnabled(v) end,
}
-- Target Tracker's on / off (its page has no Enable row; it starts off)
local POWER_TARGETTRACKER = {
	label  = "Target Tracker",
	desc   = "Turn Target Tracker on or off.",
	loaded = function() local sp = SP() return sp and type(sp.TT_Enabled) == "function" and type(sp.TT_SetEnabled) == "function" or false end,
	get    = function() return SP():TT_Enabled() and true or false end,
	set    = function(v) SP():TT_SetEnabled(v and true or false) end,
}

-- the Cooldown Bar's on / off (A13: its page has no Enable row any more)
local POWER_CDBAR = {
	label  = "Cooldown Bar",
	desc   = "Turn the Cooldown Bar on or off.",
	get    = function() local o = SP().opt return o and o.showCooldownBar and true or false end,
	set    = function(v)
		local sp = SP()
		if not sp.opt then return end
		sp.opt.showCooldownBar = v and true or false
		sp:UpdateCooldownBar()
	end,
}

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

local PLAYER_IS_SHAMAN = select(2, UnitClass("player")) == "SHAMAN"
local NAV = {
	{ group = "General", entries = {
		{ label = "General", lock = true, desc = "Choose how ShamanPower looks and works.", tabs = {
			-- the Totem Bar Style dropdown is on Main: a shaman sees the bar change as they hover its list
			{ label = "Main",      preview = PLAYER_IS_SHAMAN and MOCK_TOTEM or nil, paths = { P("settings", "settings_show") } },
			-- every theme setting, and nothing else (drawn by Themes.lua)
			{ label = "Themes",    preview = PLAYER_IS_SHAMAN and MOCK_THEMES or nil, custom = "themes", paths = { P("settings", "settings_themes") } },
			{ label = "Fonts & Textures", preview = PLAYER_IS_SHAMAN and MOCK_BARS or nil, paths = { P("settings", "settings_fonts") } },
			{ label = "Interface", paths = { P("settings", "settings_newui") } },
			{ label = "Keybinds",  paths = { P("settings", "settings_keybinds") } },
			{ label = "Reset",     paths = { P("settings", "settings_frames") } },
		}},
		{ label = "Profiles", path = P("profiles"), lock = true },
		-- every version's notes (PatchNotesPage.lua draws the page); NEW until opened
		{ label = "Patch Notes", custom = "patchnotes", path = P("settings", "settings_patchnotes"),
			desc = "What changed in each version, newest first. Click a version to open or close it.",
			newTag = function() local sp = ShamanPower; return sp and sp.PatchNotesUnseen and sp:PatchNotesUnseen() end },
	}},
	{ group = "Bars", power = true, entries = {
		{ label = "Totem Bar", preview = MOCK_TOTEM, shamanOnly = true, lock = true, power = false,
			desc = "The totem bar: its style and clicks, what it shows, button and drop order, duration bars, flyouts and macros.", tabs = {
			{ label = "Style",         paths = { P("settings", "settings_totemMode") } },
			{ label = "Clicks",        paths = { P("settings", "settings_totemClicks") } },
			{ label = "Bar",           paths = { P("buttons", "auto_button") } },
			{ label = "Items",         paths = { P("fluffy", "totembar_items_section") } },
			{ label = "Order",         paths = { P("fluffy", "totembar_order_section") } },
			{ label = "Drop All",      paths = { P("buttons", "dropall_section") } },
			{ label = "Duration Bars", preview = MOCK_DURATION, paths = { P("fluffy", "totembar_duration_section") } },
			{ label = "Flyouts",       paths = { P("fluffy", "totemflyouts_section") } },
			{ label = "Effects",       preview = MOCK_TOTEM_EFFECTS, paths = { P("fluffy", "totembar_effects_section") } },
			{ label = "Macros",        paths = { P("buttons", "macros_section") } },
			{ label = "Twisting",      paths = { P("settings", "settings_totemTwisting") } },   -- no rows (so no tab) on WoW: Forever
		}},
		-- one page (A13): the Items row (click, right-click, drag) and what is about the whole bar
		{ label = "Cooldown Bar", preview = MOCK_CDBAR, shamanOnly = true, lock = true, power = POWER_CDBAR,
			desc = "Click an item to show or hide it, right-click it for its settings, drag it to move it.",
			path = P("fluffy", "cdbar_page") },
		{ label = "Appearance", preview = MOCK_BARS, shamanOnly = true, lock = true, power = false, desc = "Layout, size, opacity, textures and visibility of the bars.", tabs = {
			{ label = "Totem Bar", preview = MOCK_TOTEM, paths = {
				P("fluffy", "totembar_appearance"), P("fluffy", "appearance_resets"),
			} },
			{ label = "Flyouts", paths = { P("fluffy", "flyout_appearance") } },
			{ label = "Textures & Colors", paths = {
				P("fluffy", "texture_section"), P("fluffy", "color_section"),
				P("fluffy", "element_colors_section"), P("fluffy", "button_tints_section"),
			} },
			{ label = "Visibility",        paths = { P("fluffy", "visibility_section"), { "settings", "settings_visibility", label = "Auto-Hide" } } },
		}},
		{ label = "Loadouts", preview = MOCK_LOADOUT, shamanOnly = true, lock = true, power = false,
			desc = "Save totem loadouts, set up their bar and choose when to switch automatically.", tabs = {
			{ label = "Loadouts", preview = MOCK_LOADOUT, paths = { P("buttons", "loadouts_section") } },
			{ label = "Loadout Bar", preview = MOCK_LOADOUT, paths = { P("fluffy", "loadoutbar_section") } },
			{ label = "Auto-Switch", paths = { P("buttons", "loadoutrules_section") } },
		}},
	}},
	{ group = "Group Tools", power = true, entries = {
		{ label = "Raid Cooldowns", preview = "raidcd",       path = P("fluffy", "raid_cd_section") },
		{ label = "Raid Resistance", shamanOnly = true, path = P("buttons", "resist_section"), power = POWER_RESIST },   -- WoW: Forever only (the group exists only there)
		{ label = "Cooldown Announce", shamanOnly = true, path = P("fluffy", "announce_section") },
		{ label = "Totem Range Tracker", preview = "sprange",  path = P("fluffy", "sprange_section"), power = POWER_SPRANGE },
		{ label = "Party Buff Tracker", preview = MOCK_PARTY, shamanOnly = true, power = POWER_PARTYBUFF, tabs = {
			{ label = "Dots & Counters", paths = { P("fluffy", "partybuff_section") } },
			{ label = "Coverage", preview = "coverage", paths = { P("fluffy", "coverage_section") } },
			{ label = "Party Strip", preview = "partystrip", paths = { P("fluffy", "partystrip_section") } },
		}},
		{ label = "Earth Shield Tracker", preview = "estracker", path = P("fluffy", "estrack_section") },
		{ label = "Ready Check", preview = "readycheck", shamanOnly = true, path = P("fluffy", "readycheck_section") },
	}},
	{ group = "Alerts & Reminders", power = true, entries = {
		{ label = "Shield Charges", preview = "shieldcharges", shamanOnly = true,       path = P("fluffy", "shieldcharges_section"), power = POWER_SHIELDCHARGES },
		{ label = "Reactive Totems", preview = "reactive", shamanOnly = true,      path = P("fluffy", "reactivetotems_section") },
		{ label = "Ready Reminders", preview = "readyreminders", shamanOnly = true,      path = P("fluffy", "readyreminders_section"), power = POWER_READYREMINDERS },
		{ label = "Target Tracker", preview = "targettracker", shamanOnly = true,       path = P("fluffy", "targettracker_section"), power = POWER_TARGETTRACKER, noReset = true },
		{ label = "Expiring Alerts", preview = "expiring", shamanOnly = true,      path = P("fluffy", "expiringalerts_section") },
		{ label = "Tremor Reminder", preview = "tremor", shamanOnly = true,      path = P("fluffy", "tremorreminder_section") },
		{ label = "Trainer Reminder", shamanOnly = true, path = P("fluffy", "trainer_section") },
	}},
	{ group = "Other", power = true, entries = {
		{ label = "Totem Plates", preview = "totemplates",         path = P("fluffy", "totemplates_section") },
		{ label = "Pop-Out Trackers", shamanOnly = true, power = false, desc = "Middle-click any bar button to pop it out as a movable tracker.", tabs = {
			{ label = "Pop-Out Trackers", paths = {
				{ "settings", "settings_popout", label = "Middle-Click Pop-Out" },
				{ "fluffy",   "popout_section",  label = "Popped-Out Trackers" },
			}},
		}},
	}},
}

-- The four elements are the window's identity (D32): every NAV group is one
-- (SP.Brand.groupElement: General = Air, Bars = Earth, Group Tools = Water,
-- Alerts & Reminders = Fire, Other = logo blue) and a page wears its group's.
for _, g in ipairs(NAV) do
	for _, e in ipairs(g.entries) do e._group = g.group end
end
local function GroupElement(group)
	local sp = SP()
	local map = sp and sp.Brand and sp.Brand.groupElement
	return map and map[group] or "spirit"
end
-- {r, g, b} 0-1 (SP.Brand's own table: read it, never write into it)
local function ElementColor(key)
	local els = SP().Brand.elements
	return els[key] or els.spirit
end

-- Every option-group path an entry draws from.
local function EntryPaths(entry)
	if entry.path then return { entry.path } end
	local out = {}
	for _, t in ipairs(entry.tabs or {}) do
		for _, pth in ipairs(t.paths) do out[#out + 1] = pth end
	end
	return out
end

local function VisiblePath(path)
	local node, chain = Tree:Resolve(path)
	if not node or Tree:IsHidden(node, chain, Tree:BuildInfo(path, node, chain)) then return end
	local rows = Tree:BuildRenderList(node, path, chain)
	if Tree:HasContent(rows) then return node, chain, rows end
end

local function EntryHasContent(entry)
	if not entry or (entry.shamanOnly and not PLAYER_IS_SHAMAN) then return false end
	for _, path in ipairs(EntryPaths(entry)) do
		if VisiblePath(path) then return true end
	end
	return false
end

local function PathStartsWith(path, prefix)
	if #prefix > #path then return false end
	for i = 1, #prefix do
		if path[i] ~= prefix[i] then return false end
	end
	return true
end

-- Moves record old full paths as well as old group paths. Prefer the most
-- specific alias so a split page's individual controls still find their tab.
local function ResolvePathAlias(path)
	local sp = SP()
	local aliases = sp and sp.SettingsPathAliases
	if not aliases then return path end
	local seen = {}
	while not seen[table.concat(path, "/")] do
		local key = table.concat(path, "/")
		seen[key] = true
		local best, target
		for old, destination in pairs(aliases) do
			if (key == old or key:sub(1, #old + 1) == old .. "/") and (not best or #old > #best) then
				best, target = old, destination
			end
		end
		if not best then break end
		local resolved, count = {}, 1
		for _ in best:gmatch("/") do count = count + 1 end
		for _, part in ipairs(target) do resolved[#resolved + 1] = part end
		for i = count + 1, #path do resolved[#resolved + 1] = path[i] end
		path = resolved
	end
	return path
end

-- A caller may name a whole tab or an option beneath it. Prefer the longest
-- visible prefix; a hidden tab falls back to that page's first visible tab.
local function EntryPathMatch(entry, path)
	local depth, tab, fallbackDepth
	if entry.path and PathStartsWith(path, entry.path) and VisiblePath(entry.path) then
		depth = #entry.path
	end
	for _, candidate in ipairs(entry.tabs or {}) do
		for _, prefix in ipairs(candidate.paths) do
			if PathStartsWith(path, prefix) then
				if VisiblePath(prefix) then
					if not depth or #prefix > depth then depth, tab = #prefix, candidate.label end
				elseif not fallbackDepth or #prefix > fallbackDepth then
					fallbackDepth = #prefix
				end
			end
		end
	end
	return depth or fallbackDepth, tab, depth ~= nil
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

-- ---------------------------------------------------------------------------
-- Live preview pane. The current page's module frame, borrowed through
-- ShamanPowerPreview (the wizard's harness: real frame, sample data from the
-- module's own Demo, restored on exit) into a panel hung off the window's
-- right edge, re-fed after every change. The header's Preview button opens
-- and closes it (lit while it is open), its own X closes it; the choice is
-- remembered.
-- ---------------------------------------------------------------------------
local PREVIEW_W = 380

local function PreviewStore()
	local sp = SP()
	if not sp then return nil end
	if sp.db and sp.db.global then return sp.db.global end
	return sp.opt
end
local function PreviewOpenWanted()
	local st = PreviewStore()
	if st and st.configPreviewOpen ~= nil then return st.configPreviewOpen and true or false end
	return false   -- tucked away until asked for; the tab on the edge is the invitation
end

function SPConfig:BuildPreviewPane()
	if frame.preview then return end
	-- the pane sits in a clip on the window's right edge, so it can slide out of the edge
	-- and back in (SlidePane, below) without crossing the window
	local clip = CreateFrame("Frame", nil, frame)
	clip:SetPoint("TOPLEFT", frame, "TOPRIGHT", 4, 0)
	clip:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", 4, 0)
	clip:SetWidth(PREVIEW_W)
	clip:SetClipsChildren(true)
	frame.previewClip = clip
	local pane = CreateFrame("Frame", nil, clip)
	pane:SetPoint("TOPLEFT", clip, "TOPLEFT", 0, 0)
	pane:SetPoint("BOTTOMLEFT", clip, "BOTTOMLEFT", 0, 0)
	pane:SetWidth(PREVIEW_W)
	Core:SolidTex(pane, "windowBg", "BACKGROUND", nil, true)
	Core:MakeBorder(pane, "border", 1.5)   -- the window's own soft edge (D32b)
	local cap = pane:CreateFontString(nil, "OVERLAY")
	cap:SetFontObject(Core.fonts.tiny)
	cap:SetPoint("TOP", pane, "TOP", 0, -12)
	cap:SetText("|cff5A6678LIVE PREVIEW|r")
	local title = pane:CreateFontString(nil, "OVERLAY")
	title:SetFontObject(Core.fonts.navOn)
	title:SetPoint("TOP", cap, "BOTTOM", 0, -4)
	pane.title = title
	local inner = CreateFrame("Frame", nil, pane)
	inner:SetPoint("TOPLEFT", pane, "TOPLEFT", 10, -52)
	inner:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -10, 10)
	inner:SetClipsChildren(true)
	inner.previewMaxScale = 1.6
	inner.previewPane = true   -- ShowPreview reads the registrations' pane hints for this container only
	pane.inner = inner
	local note = inner:CreateFontString(nil, "OVERLAY")
	note:SetFontObject(Core.fonts.nav)
	note:SetPoint("CENTER", inner, "CENTER", 0, 0)
	note:SetWidth(PREVIEW_W - 60)
	note:SetJustifyH("CENTER")
	note:SetTextColor(Core:Color("textDim"))
	pane.note = note
	pane:Hide()
	frame.preview = pane

	-- its own close X in the corner (D35 B, owner 2026-10-02: a player asked how to close it)
	local close = Core:CloseButton(pane, 20)
	close:SetPoint("TOPRIGHT", pane, "TOPRIGHT", -6, -6)
	close:SetScript("OnClick", function() SPConfig:SetPreviewPaneOpen(false) end)
	pane.close = close
end

-- The wizard's bar mocks, stacked in the pane. Rebuilt on page / tab
-- changes and (throttled) after a setting changes; the previous set is
-- discarded, as the wizard does.
local function ReleaseMocks()
	local pane = frame and frame.preview
	SPConfig:HoverStyle(nil)
	if pane and pane.mockPreviews then
		local sp = SP()
		for key in pairs(pane.mockPreviews) do
			if sp and sp.RestorePreview then sp:RestorePreview(key) end
		end
		wipe(pane.mockPreviews)
	end
	if pane and pane.mockHost then
		pane.mockHost:Hide()
		pane.mockHost:SetParent(nil)
		pane.mockHost = nil
	end
	if pane then pane.mockSpec = nil; pane.mockFits = nil end
end

local function MountMocks(spec)
	ReleaseMocks()
	local sp = SP()
	local W = sp and sp.Wizard
	local pane = frame.preview
	if not (W and pane) then return false end
	local inner = pane.inner
	if inner.previewStage then inner.previewStage:Hide() end   -- a module's staged character does not belong under mocks
	local host = CreateFrame("Frame", nil, inner)
	host:SetAllPoints(inner)
	pane.mockHost, pane.mockSpec = host, spec
	pane.mockFits = {}
	local list = {}
	for _, m in ipairs(spec.mocks) do
		if not m.when or m.when() then list[#list + 1] = m end
	end
	local n = #list
	local gap = 6
	local ih = inner:GetHeight()
	if ih < 50 then ih = WIN_H - 62 end   -- anchors not resolved yet on the first draw
	-- panels share the height by weight (a mock drawn for the wizard's tall panel needs more of it)
	local totalW = 0
	for _, m in ipairs(list) do totalW = totalW + (m.weight or 1) end
	local usable = ih - gap * (n - 1)
	pane.mockPreviews = pane.mockPreviews or {}
	local wasPreviewOnly, wasEffects = W.previewOnly, W.effectsDemo
	W.previewOnly = true
	W.effectsDemo = spec.effects   -- the Effects tab: the mocks run the chosen effects (RunEffectsDemo)
	local dummyCard = CreateFrame("Frame", nil, host)
	dummyCard:SetSize(400, 10)
	dummyCard:Hide()
	local yy = 0
	for _, m in ipairs(list) do
		local h = math.floor(usable * (m.weight or 1) / totalW)
		local panel = CreateFrame("Frame", nil, host)
		panel:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -yy)
		panel:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, -yy)
		panel:SetHeight(h)
		Core:SolidTex(panel, "contentBg", "BACKGROUND")
		Core:MakeBorder(panel, "border")
		local lbl = panel:CreateFontString(nil, "OVERLAY")
		lbl:SetFontObject(Core.fonts.tiny)
		lbl:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -6)
		lbl:SetText(strupper(m.label))
		lbl:SetTextColor(Core:Color("textDim"))
		local pin = CreateFrame("Frame", nil, panel)
		-- shiftY: a mock laid out for the wizard's taller panel (content above
		-- its centre) needs its centre lower here. The pin's top stays at the
		-- panel top (it clips there); its bottom is extended by twice the shift,
		-- which moves the centre - where the mock anchors - down by the shift.
		local shift = m.shiftY or 0
		pin:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -18)
		pin:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -4, 4 - 2 * shift)
		pin:SetClipsChildren(true)
		if m.preview then
			-- a module preview: the real frame with its demo, through the harness
			pin.previewPane = true
			pin.previewMaxScale = m.maxScale or 1.3
			if sp.ShowPreview and sp.PreviewRegistry and sp.PreviewRegistry[m.preview] then
				sp:ShowPreview(m.preview, pin)
				pane.mockPreviews[m.preview] = true
			end
		else
			local fn = (ns.PaneBuilders and ns.PaneBuilders[m.build]) or W[m.build]
			if fn then
				local ok, err = pcall(fn, dummyCard, pin, 0)
				if not ok then print("|cff0070ddShamanPower|r: preview of " .. m.label .. " failed: " .. tostring(err)) end
			end
		end
		-- a theme's flat boxes on the mock (only when a theme is set: Standard draws today's mock untouched)
		if not m.preview and sp.ThemeSkinPreview and sp.opt and type(sp.opt.theme) == "table" then
			local ok, err = pcall(sp.ThemeSkinPreview, sp, pin, MOCK_SKIN_FAMILY[m.build] or "totembar")
			if not ok then geterrorhandler()(err) end
		end
		-- the mocks' captions belong to the wizard's step pages
		for _, r in ipairs({ pin:GetRegions() }) do
			if r.IsObjectType and r:IsObjectType("FontString") then r:Hide() end
		end
		-- The mocks size themselves for the wizard's wide panel (by height
		-- only, and from their own OnUpdate); a bar wider than this pane is
		-- shrunk to fit, on the pane's own container so the wizard never sees
		-- it. Measured a frame later, once the mock has applied its own scale.
		-- Width only, on shown children: a bar wider than this pane is shrunk to
		-- fit (the mocks size themselves by height for the wizard's panel, and
		-- park helper frames off-screen, so height is not measured here).
		local function fit()
			if not pin:IsShown() then return end
			local widest = 0
			for _, ch in ipairs({ pin:GetChildren() }) do
				if ch:IsShown() then
					local w = ch:GetWidth() * ch:GetScale()
					if w > widest then widest = w end
				end
			end
			local avail = (pin:GetWidth() * pin:GetScale()) - 12
			if avail < 40 then avail = PREVIEW_W - 40 end
			if widest > 0 then pin:SetScale(math.min(1, avail / widest)) end
		end
		fit()
		C_Timer.After(0, fit)
		C_Timer.After(0.2, fit)
		pane.mockFits[#pane.mockFits + 1] = fit   -- a hover preview re-fits without remounting
		yy = yy + h + gap
	end
	W.previewOnly, W.effectsDemo = wasPreviewOnly, wasEffects
	return true
end

-- Give the borrowed frame back (window closing, page changing).
function SPConfig:ReleasePreview()
	local sp = SP()
	if frame and frame._previewKey and sp and sp.RestorePreview then sp:RestorePreview(frame._previewKey) end
	if frame then frame._previewKey = nil end
	ReleaseMocks()
end

-- The pane slides out of the window's edge and back in (owner 2026-10-02, with UI
-- Animations on); off, or restoring a remembered open pane, it is there or gone at once.
local SLIDE_T = 0.26
local slide = { x = 0 }
local slider = CreateFrame("Frame")
slider:Hide()
local function PlacePane(x)
	local pane, clip = frame.preview, frame.previewClip
	pane:ClearAllPoints()
	pane:SetPoint("TOPLEFT", clip, "TOPLEFT", x, 0)
	pane:SetPoint("BOTTOMLEFT", clip, "BOTTOMLEFT", x, 0)
	pane:SetAlpha(1 - 0.6 * math.min(1, -x / PREVIEW_W))   -- a little fade toward the hidden end
	slide.x = x
end
slider:SetScript("OnUpdate", function(self)
	local p = math.min(1, (GetTime() - slide.t0) / SLIDE_T)
	local sp = SP()
	local e = (sp and sp.BrandEaseOut) and sp.BrandEaseOut(p) or p
	PlacePane(slide.from + (slide.to - slide.from) * e)
	if p < 1 then return end
	self:Hide()
	local done = slide.done
	slide.done = nil
	if done then done() end
end)
local function SlidePane(to, done)
	slide.from, slide.to, slide.t0, slide.done = slide.x, to, GetTime(), done
	slider:Show()
end
local function PaneAnimated()
	local sp = SP()
	if not frame:IsShown() then return false end
	return not (sp and sp.UIAnimationsOn) or sp:UIAnimationsOn() ~= false
end

function SPConfig:SetPreviewPaneOpen(on, silent)
	if not frame then return end
	self:BuildPreviewPane()
	on = on and true or false
	frame._previewOpen = on
	local pane = frame.preview
	if frame.previewBtn then frame.previewBtn:SetLit(on) end
	if not silent then
		local st = PreviewStore()
		if st then st.configPreviewOpen = on end
	end
	-- keep the whole assembly on screen when the window is dragged (wide while it slides)
	if on then frame:SetClampRectInsets(0, PREVIEW_W + 4, 0, 0) end
	local function closed()
		pane:Hide()
		frame:SetClampRectInsets(0, 0, 0, 0)
		SPConfig:ReleasePreview()
	end
	if silent or not PaneAnimated() then
		slider:Hide()
		slide.done = nil
		PlacePane(on and 0 or -PREVIEW_W)
		if on then pane:Show() else closed() end
	elseif on then
		if not pane:IsShown() then PlacePane(-PREVIEW_W) end
		pane:Show()
		SlidePane(0, nil)
	else
		SlidePane(-PREVIEW_W, closed)
	end
	self:UpdatePreviewPane()
end

-- A setting changed: module previews re-feed at once (no new frames); the
-- bar mocks are rebuilt (new frames each time, which WoW never frees), so a
-- slider drag waits until the value settles for 0.3 s, or 1 s at most.
local remountQueued, lastChange, firstChange = false, 0, 0
local feedQueued = false
-- a slider thumb held down right now (the button still down: a release off the slider counts)
local function SliderHeld()
	if not Widgets.sliderDragging then return false end
	if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then Widgets.sliderDragging = false; return false end
	return true
end
local function remountWhenSettled()
	local now = GetTime()
	-- a slider still held down: wait for the release (a rebuild mid-drag made it stutter)
	if SliderHeld() or (now - lastChange < 0.3 and now - firstChange < 1) then C_Timer.After(0.1, remountWhenSettled) return end
	remountQueued = false
	SPConfig:UpdatePreviewPane(true)
end
function SPConfig:PreviewChanged(themeChanged)
	if not (frame and frame.preview and frame._previewOpen and frame:IsShown()) then return end
	-- the Effects tab's mocks play the options live (RunEffectsDemo): nothing to rebuild
	-- (a theme change repaints the bars themselves, so it rebuilds them anyway)
	if not themeChanged and frame.preview.mockSpec and frame.preview.mockSpec.effects then return end
	if frame.preview.mockSpec then
		lastChange = GetTime()
		if remountQueued then return end
		remountQueued, firstChange = true, lastChange
		C_Timer.After(0.1, remountWhenSettled)
	elseif SliderHeld() then
		-- module previews re-run their demo: at most ten times a second while dragging
		if feedQueued then return end
		feedQueued = true
		C_Timer.After(0.1, function() feedQueued = false; SPConfig:UpdatePreviewPane() end)
	else
		self:UpdatePreviewPane()
	end
end

function SPConfig:TogglePreviewPane()
	self:SetPreviewPaneOpen(not (frame and frame._previewOpen))
end

-- Hover preview of a totem bar style. A style toggle on Mode & Twisting, or a
-- style in the General page's dropdown, under the mouse shows that style in
-- the live preview without changing a setting. The wizard's mocks read
-- SP.Wizard.optOverride every frame, so pointing it at a copy of the options
-- with the style's flags set is the whole trick; nil puts the live options
-- back. Only while a mock pane is up, and never over the setup tour or a
-- preset preview, which own that override themselves.
function SPConfig:HoverStyle(key)
	local sp = SP()
	local pane = frame and frame.preview
	local function refit()
		-- the mocks re-lay themselves out on their next frame; a wider style must still fit the pane
		local fits = pane and pane.mockFits
		if not fits then return end
		local function run() if pane.mockFits == fits then for _, f in ipairs(fits) do f() end end end
		C_Timer.After(0, run)
		C_Timer.After(0.2, run)
	end
	if not key then
		if frame then frame._themesStyle = nil end   -- (the Themes tab puts its own back on its next preview update)
		if frame and frame._hoverStyle then
			frame._hoverStyle = nil
			-- only the copy this window set; a style preview or the tour may own the override by now
			if sp and sp.Wizard and sp.Wizard.optOverride == frame._hoverOverride then sp.Wizard.optOverride = nil end
			frame._hoverOverride = nil
			refit()
		end
		return
	end
	if not (pane and frame._previewOpen and pane.mockSpec and frame:IsShown()) then return end
	if not (sp and sp.Wizard and sp.opt and sp.ApplyTotemBarStyleTo) then return end
	local wiz = _G["ShamanPowerWizard"]
	if wiz and wiz:IsShown() then return end
	if sp.Wizard.optOverride and sp.Wizard.optOverride ~= frame._hoverOverride then return end   -- someone else's override
	local o = {}
	for k, v in pairs(sp.opt) do o[k] = v end   -- shallow copy; the mocks only read nested tables
	if not sp:ApplyTotemBarStyleTo(o, key) then return end
	sp.Wizard.optOverride = o
	frame._hoverStyle, frame._hoverOverride = key, o
	refit()
end

-- Show the current page's preview (or say why there is none). Re-running it
-- for the same key re-feeds the sample data, which is how setters reach it.
-- General > Themes: the module section in the top third of the page right now
-- (key, label), or nil at the top of the tab / on any other page
-- (key, label, style: the totem bar style of the Totem Bar Styles rows in view)
local STYLE_OF_SPOT = {
	["st.compact"] = "compact", ["st.compact-shield"] = "compact", ["st.boxes-compact"] = "compact",
	["st.grid"] = "grid", ["st.boxes-grid"] = "grid", ["st.blizzard"] = "blizzard",
}
local function ThemesSectionNow()
	local tp = ns.ThemesPage
	local sc = frame and frame.bodyScroll
	if not (sc and tp and tp.SectionAt and tp:IsShown()) then return nil end
	local key, label, spot = tp:SectionAt(sc:GetVerticalScroll() + sc:GetHeight() * 0.3)
	return key, label, key == "styles" and (STYLE_OF_SPOT[spot] or "compact") or nil
end
local function ThemesShownKey()
	local key, _, style = ThemesSectionNow()
	return (key or "") .. "/" .. (style or "")
end

function SPConfig:UpdatePreviewPane(remount)
	if not (frame and frame.preview and frame._previewOpen and frame:IsShown()) then return end
	local sp = SP()
	local entry = frame._current
	local spec = entry and entry.preview or nil
	if entry and entry.tabs and frame._activeTab then
		for _, t in ipairs(entry.tabs) do
			if t.label == frame._activeTab and t.preview then spec = t.preview break end
		end
	end
	if frame._themesSearch and PLAYER_IS_SHAMAN and ns.ThemesPage and ns.ThemesPage:IsShown() then
		spec = MOCK_THEMES   -- search results have the same section-driven preview as the Themes tab
	end
	local title = entry and entry.label or ""
	local styleKey
	if spec == MOCK_THEMES then
		-- the Themes tab: the preview of the module section scrolled into view
		local key, label, style = ThemesSectionNow()
		frame._themesShown = (key or "") .. "/" .. (style or "")
		if style then
			spec, title, styleKey = MOCK_TOTEM, label, style   -- that style on the totem bar mock
		else
			local s = key and THEMES_SECTION_PREVIEW[key]
			if s then spec, title = s, label end
		end
	end
	-- the Totem Bar Styles override ends as soon as the preview shows anything else
	if frame._themesStyle and frame._themesStyle ~= styleKey then
		frame._themesStyle = nil
		self:HoverStyle(nil)
	end
	local pane = frame.preview
	pane.title:SetText(title)
	if type(spec) == "table" then
		-- the wizard's bar mocks
		if frame._previewKey then self:ReleasePreview() end
		if pane.mockSpec ~= spec or remount then MountMocks(spec) end
		if styleKey and (frame._themesStyle ~= styleKey or remount) then   -- (a theme change: a fresh copy of the settings)
			frame._themesStyle = styleKey
			self:HoverStyle(styleKey)   -- the style is only shown, never set
		end
		pane.note:Hide()
		return
	end
	ReleaseMocks()
	local key = spec
	if frame._previewKey and frame._previewKey ~= key then self:ReleasePreview() end
	-- A module preview borrows the REAL frame and runs its demo, which pauses the
	-- frame's live updates. Never in combat: the fight needs the real numbers.
	if key and (SPConfig._inCombat or InCombatLockdown()) then
		if frame._previewKey then self:ReleasePreview() end
		pane.note:Show()
		pane.note:SetText("The preview is paused during combat so the real display keeps working. It returns when combat ends.")
		return
	end
	-- Unlock UI has the real frames up under its boxes (a right-click on a box opens
	-- this page): borrowing one would pull it out from under its box
	if key and sp and sp.IsMasterUnlocked and sp:IsMasterUnlocked() then
		if frame._previewKey then self:ReleasePreview() end
		pane.note:Show()
		pane.note:SetText("The preview is paused while you move things with Unlock UI. Click Done to show it again.")
		return
	end
	local def = key and sp and sp.PreviewRegistry and sp.PreviewRegistry[key]
	if def and sp.ShowPreview then
		local shown = sp:ShowPreview(key, pane.inner)
		frame._previewKey = shown and key or nil
		pane.note:SetShown(shown == nil)
		if shown == nil then pane.note:SetText("This feature is unavailable, so there is no preview.") end
	else
		frame._previewKey = nil
		pane.note:Show()
		pane.note:SetText(key and "This feature is unavailable, so there is no preview."
			or (PLAYER_IS_SHAMAN and "No preview for this page: its settings change the bars themselves, which stay on screen while this window is open."
				or "No preview for this page."))
	end
end

-- defined further down with their features (in do-blocks: this chunk's locals are counted)
local CpuStart, CpuStop, ConfirmResetPage, MotionWindowBuilt, MotionWindowHidden, MotionOpenedAgain
local SidebarActions, LinkButtons

do
	local MEDIA = "Interface\\AddOns\\ShamanPower\\Media\\Textures\\"

	-- ---------------------------------------------------------------------------
	-- Unlock UI and Keybind Mode at the top of the sidebar (D30 3, D30b A1): two
	-- rows with a small glyph each (accentHi), running exactly what General >
	-- Main's two buttons run: those options' own functions (the buttons stay). A
	-- row whose option is hidden (Keybind Mode for other classes) is left out.
	-- Under them UI Animations, an on / off row: its option lives in General >
	-- Main but is hidden there (this row is its only place), so it is read even
	-- when hidden, through the option's own get and set.
	-- ---------------------------------------------------------------------------
	local SIDEBAR_ACTIONS = {
		{ key = "master_unlock", label = "Unlock UI", glyph = "move" },
		{ key = "keybind_mode", label = "Keybind Mode", glyph = "keys" },
		{ key = "uiAnimations", label = "UI Animations", glyph = "motion", toggle = true },
	}

	local function MainOption(key, evenHidden)
		local path = { "settings", "settings_show", key }
		local node, chain = Tree:Resolve(path)
		if not node then return nil end
		local info = Tree:BuildInfo(path, node, chain)
		if not evenHidden and Tree:IsHidden(node, chain, info) then return nil end
		return node, chain, info
	end

	-- the D30b mock's glyphs, 20 x 20 around their center: a four-way cross with a
	-- dot (moving things), and a small keyboard (three keys and a space bar)
	local function MoveGlyph(g, r, gr, b)
		for _, d in ipairs({ { 0, 1 }, { 0, -1 }, { -1, 0 }, { 1, 0 } }) do
			local l = g:CreateLine(nil, "ARTWORK")
			l:SetThickness(1.4)
			l:SetColorTexture(r, gr, b, 1)
			l:SetStartPoint("CENTER", g, 0, 0)
			l:SetEndPoint("CENTER", g, d[1] * 7, d[2] * 7)
		end
		local dot = g:CreateTexture(nil, "OVERLAY")
		dot:SetSize(4, 4)
		dot:SetPoint("CENTER", g, "CENTER", 0, 0)
		dot:SetTexture(MEDIA .. "Mask_Circle")
		dot:SetVertexColor(r, gr, b, 1)
	end

	local function KeysGlyph(g, r, gr, b)
		local box = CreateFrame("Frame", nil, g)
		box:SetSize(16, 10)
		box:SetPoint("CENTER", g, "CENTER", 0, 0)
		Core:MakeBorder(box, "accentHi", 1.2)
		for k = 0, 2 do
			local key = g:CreateTexture(nil, "ARTWORK")
			key:SetSize(2, 2)
			key:SetPoint("TOPLEFT", g, "CENTER", -5 + k * 4, 2)
			key:SetColorTexture(r, gr, b, 1)
		end
		local space = g:CreateTexture(nil, "ARTWORK")
		space:SetSize(8, 1.4)
		space:SetPoint("TOPLEFT", g, "CENTER", -4, -1.5)
		space:SetColorTexture(r, gr, b, 1)
	end

	-- UI Animations: a dot moving right with three speed lines behind it
	local function MotionGlyph(g, r, gr, b)
		for _, s in ipairs({ { 4, -4 }, { 0, -8 }, { -4, -4 } }) do
			local l = g:CreateLine(nil, "ARTWORK")
			l:SetThickness(1.4)
			l:SetColorTexture(r, gr, b, 1)
			l:SetStartPoint("CENTER", g, s[2], s[1])
			l:SetEndPoint("CENTER", g, 0, s[1])
		end
		local dot = g:CreateTexture(nil, "OVERLAY")
		dot:SetSize(6, 6)
		dot:SetPoint("CENTER", g, "CENTER", 5, 0)
		dot:SetTexture(MEDIA .. "Mask_Circle")
		dot:SetVertexColor(r, gr, b, 1)
	end

	-- the rows from sidebar y `top` down; returns the y under them (where the nav list starts)
	SidebarActions = function(side, top)
		local y = top
		local paints = {}
		for _, a in ipairs(SIDEBAR_ACTIONS) do
			local node, _, info = MainOption(a.key, a.toggle)
			if node then
				local row = CreateFrame("Button", nil, side)
				row:SetSize(SIDEBAR_W - 1, ACTION_ROW_H)
				row:SetPoint("TOPLEFT", side, "TOPLEFT", 0, -y)
				local bg = row:CreateTexture(nil, "BACKGROUND")
				bg:SetAllPoints(row)
				bg:SetColorTexture(0, 0, 0, 0)
				local g = CreateFrame("Frame", nil, row)
				g:SetSize(20, 20)
				g:SetPoint("CENTER", row, "LEFT", 28, 0)
				local r, gr, b = Core:Color("accentHi")
				if a.glyph == "move" then
					MoveGlyph(g, r, gr, b)
				elseif a.glyph == "motion" then
					MotionGlyph(g, r, gr, b)
				else
					KeysGlyph(g, r, gr, b)
				end
				local text = row:CreateFontString(nil, "OVERLAY")
				text:SetFontObject(Core.fonts.nav)
				text:SetTextColor(Core:Color("text"))
				text:SetPoint("LEFT", row, "LEFT", 46, 0)
				text:SetText(a.label)
				local key = a.key
				row:SetScript("OnEnter", function() bg:SetColorTexture(Core:Color("rowHover", 0.5)) end)
				row:SetScript("OnLeave", function() bg:SetColorTexture(0, 0, 0, 0) end)
				local hint
				if a.toggle then
					-- on / off: the module rows' small totem switch at the right; the whole
					-- row is the button (the switch takes no clicks of its own)
					local pw = SP():CreateTotemSwitch(row, { scale = 0.62 })
					pw:SetPoint("RIGHT", row, "RIGHT", -16, 0)
					pw:EnableMouse(false)
					local function Paint()
						local n, c, i = MainOption(key, true)
						pw:SetChecked(n ~= nil and Tree:MakeGetter(n, c, i)() == true)
					end
					row:SetScript("OnClick", function()
						local n, c, i = MainOption(key, true)
						if not n then return end
						Tree:MakeSetter(n, c, i)(not (Tree:MakeGetter(n, c, i)() == true))
						Paint()
					end)
					row:HookScript("OnShow", Paint)
					Paint()
					paints[#paints + 1] = Paint
					hint = "Click to turn it on or off"
				else
					row:SetScript("OnClick", function()
						local n, c, i = MainOption(key)   -- (read now: always what that button runs)
						if not n then return end
						Tree:MakeFunc(n, c, i)()
						-- as the page's button does: the open page re-reads its settings after it
						if frame:IsShown() and frame._onChanged then frame._onChanged() end
					end)
				end
				Core:AttachTooltip(row, a.label, Tree:GetDesc(node, info), hint)   -- (after SetScript, which would drop its hook)
				y = y + ACTION_ROW_H
			end
		end
		-- the window's refresh after a change repaints the on / off rows (a profile change, a reset)
		frame.spPaintActions = function()
			for _, paint in ipairs(paints) do paint() end
		end
		return y + 6
	end

	-- ---------------------------------------------------------------------------
	-- The named link buttons in the footer (D30 2, D30b C2): each link's mark and
	-- its name beside Reload UI. WoW cannot open a browser, so a click opens
	-- ShamanPower's copy box with the link selected. The mark is gray at rest and
	-- takes its brand's color on hover.
	-- ---------------------------------------------------------------------------
	local LINKS = {
		{ name = "Discord", key = "discordLink", mark = "SP_Link_Discord", title = "ShamanPower Discord",
			url = "https://discord.gg/eCtNeBqE8U", color = { 0x58 / 255, 0x65 / 255, 0xF2 / 255 } },
		{ name = "CurseForge", key = "curseforgeLink", mark = "SP_Link_CurseForge", title = "ShamanPower on CurseForge",
			url = "https://www.curseforge.com/wow/addons/shamanpower", color = { 0xF1 / 255, 0x64 / 255, 0x36 / 255 } },
		{ name = "GitHub", key = "githubLink", mark = "SP_Link_GitHub", title = "ShamanPower on GitHub",
			url = "https://github.com/taubut/ShamanPower", color = { 1, 1, 1 } },
	}

	local function LinkButton(parent, link)
		local b = CreateFrame("Button", nil, parent)
		b:SetHeight(26)
		local bg = b:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints(b)
		bg:SetColorTexture(Core:Color("windowBg"))
		Core:MakeBorder(b, "border")
		local mark = b:CreateTexture(nil, "ARTWORK")
		mark:SetSize(16, 16)
		mark:SetPoint("LEFT", b, "LEFT", 7, 0)
		mark:SetTexture(MEDIA .. link.mark)
		mark:SetVertexColor(Core:Color("textDim"))
		local label = b:CreateFontString(nil, "OVERLAY")
		label:SetFontObject(Core.fonts.link)
		label:SetPoint("LEFT", b, "LEFT", 28, 0)
		label:SetText(link.name)
		b:SetWidth(math.ceil(30 + label:GetStringWidth() + 10))
		b:SetScript("OnEnter", function()
			mark:SetVertexColor(link.color[1], link.color[2], link.color[3])
			Core:SetBorderColor(b, "accent")
		end)
		b:SetScript("OnLeave", function()
			mark:SetVertexColor(Core:Color("textDim"))
			Core:SetBorderColor(b, "border")
		end)
		b:SetScript("OnClick", function()
			SP():ShowSPDialog({ key = link.key, title = link.title, editText = link.url,
				text = "Press |cffFFD100Ctrl+C|r to copy it, then paste it into your browser." })
		end)
		Core:AttachTooltip(b, link.title, link.url, "Click to copy")
		b.spElement = "spirit"   -- its tooltip in logo blue: the window's, not the page's
		return b
	end

	-- the three in a row on the footer, from x (its left edge), 14 up
	LinkButtons = function(footer, x)
		for _, link in ipairs(LINKS) do
			local b = LinkButton(footer, link)
			b:SetPoint("BOTTOMLEFT", footer, "BOTTOMLEFT", x, 14)
			x = x + b:GetWidth() + 8
		end
	end
end

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
	local sp = SP()
	local level = frame:GetFrameLevel()

	Core:SolidTex(frame, "windowBg", "BACKGROUND", nil, true)

	-- Sidebar ---------------------------------------------------------------
	local side = CreateFrame("Frame", nil, frame)
	side:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	side:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
	side:SetWidth(SIDEBAR_W)
	Core:SolidTex(side, "sidebarBg", "BACKGROUND", nil, true)
	-- a soft light at its top, behind the logo: the mock's #171C24 over its top 45%
	local sideLight = Core:Light(side, SIDEBAR_W, WIN_H * 0.45, 0.3, 0, 1)
	Core:RegisterFadeLight(sideLight, Core:Color("sidebarLight"))
	frame.side = side

	local sideEdge = side:CreateTexture(nil, "BORDER")
	sideEdge:SetWidth(1)
	sideEdge:SetPoint("TOPRIGHT", side, "TOPRIGHT", 0, 0)
	sideEdge:SetPoint("BOTTOMRIGHT", side, "BOTTOMRIGHT", 0, 0)
	sideEdge:SetColorTexture(Core:Color("border"))

	-- The logo (D30 1, D32 1): the brand kit's totem graphic, 46 wide, beside the
	-- wordmark ("Shaman" in logo blue, "Power" in white) and "Totems, Done Right"
	local logo = sp:CreateTotemGraphic(side)
	logo:SetGraphicHeight(46 * 682 / 650)
	logo:SetPoint("TOPLEFT", side, "TOPLEFT", 16, -16)

	local brand = side:CreateFontString(nil, "OVERLAY")
	brand:SetFontObject(Core.fonts.wordmark)
	brand:SetPoint("LEFT", side, "TOPLEFT", 70, -30)
	brand:SetText("|cff3FA9F5Shaman|r|cffFFFFFFPower|r")

	local tagline = side:CreateFontString(nil, "OVERLAY")
	tagline:SetFontObject(Core.fonts.tagline)
	tagline:SetPoint("LEFT", side, "TOPLEFT", 71, -52)
	tagline:SetText("TOTEMS, DONE RIGHT")

	local ver = side:CreateFontString(nil, "OVERLAY")
	ver:SetFontObject(Core.fonts.tiny)
	ver:SetPoint("LEFT", side, "BOTTOMLEFT", 18, 16)
	local v = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("ShamanPower", "Version")
		or (GetAddOnMetadata and GetAddOnMetadata("ShamanPower", "Version"))
	ver:SetText("v" .. (v or "?"))

	-- ShamanPower's CPU beside it (D30 7, as in the D30 mock), filled while the window is open
	local cpuLabel = side:CreateFontString(nil, "OVERLAY")
	cpuLabel:SetFontObject(Core.fonts.tiny)
	cpuLabel:SetPoint("RIGHT", side, "BOTTOMRIGHT", -16, 30)
	cpuLabel:SetText("SHAMANPOWER CPU")
	cpuLabel:Hide()
	local cpuValue = side:CreateFontString(nil, "OVERLAY")
	cpuValue:SetFontObject(Core.fonts.small)
	cpuValue:SetPoint("RIGHT", side, "BOTTOMRIGHT", -16, 16)
	cpuValue:Hide()
	frame.cpuLabel, frame.cpuValue = cpuLabel, cpuValue

	-- Sidebar search
	local navSearch = CreateFrame("EditBox", nil, side)
	navSearch:SetSize(SIDEBAR_W - 32, 24)
	navSearch:SetPoint("TOPLEFT", side, "TOPLEFT", 16, -78)
	navSearch:SetAutoFocus(false)
	navSearch:SetFontObject(Core.fonts.row)
	navSearch:SetTextInsets(8, 8, 0, 0)
	Core:SolidTex(navSearch, "windowBg", "BACKGROUND")
	Core:MakeBorder(navSearch, "border")
	frame.navSearch = navSearch

	local navPlaceholder = navSearch:CreateFontString(nil, "OVERLAY")
	navPlaceholder:SetFontObject(Core.fonts.rowDim)
	navPlaceholder:SetTextColor(Core:Color("textMute"))
	navPlaceholder:SetPoint("LEFT", navSearch, "LEFT", 8, 0)
	navPlaceholder:SetText("Search all settings...")
	navSearch.placeholder = navPlaceholder

	-- Unlock UI, Keybind Mode and UI Animations, then the page list
	local navTop = SidebarActions(side, 112)

	-- Sidebar scroll: the whole width, so the open page's row runs edge to edge
	-- (its scrollbar sits inside, clear of the switches)
	local navScroll = CreateFrame("ScrollFrame", nil, side)
	navScroll:SetPoint("TOPLEFT", side, "TOPLEFT", 0, -navTop)
	navScroll:SetPoint("BOTTOMRIGHT", side, "BOTTOMRIGHT", -1, 58)
	local navList = CreateFrame("Frame", nil, navScroll)
	navList:SetSize(SIDEBAR_W - 1, 10)
	navScroll:SetScrollChild(navList)
	navScroll:EnableMouseWheel(true)
	navScroll:SetScript("OnMouseWheel", function(self, delta)
		local maxS = math.max(0, navList:GetHeight() - self:GetHeight())
		self:SetVerticalScroll(math.max(0, math.min(maxS, self:GetVerticalScroll() - delta * 30)))
	end)
	frame.navScroll, frame.navList = navScroll, navList
	Core:AttachScrollbar(navScroll, navList, { offset = -4 })   -- flush with the sidebar's edge (no lit row peeking past it)

	-- Content ---------------------------------------------------------------
	local content = CreateFrame("Frame", nil, frame)
	content:SetPoint("TOPLEFT", side, "TOPRIGHT", 0, 0)
	content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
	Core:SolidTex(content, "contentBg", "BACKGROUND", nil, true)
	-- the page's element lights the whole page, faintly, from its top left (painted per page)
	local contentLight = Core:Light(content, CONTENT_W, WIN_H, 0.05, 0, 1)
	Core:RegisterFadeLight(contentLight, Core:Color("contentBg"))
	frame.content, frame.contentLight = content, contentLight

	-- The header band (D30 5, D32 2 and 4): the intro's navy light warmed by the
	-- page's element, the huge barely-there totem graphic cut off by its edges,
	-- the page title with a short underline in the element's color.
	local band = CreateFrame("Frame", nil, content)
	band:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
	band:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
	band:SetHeight(HEADER_H)
	band:SetClipsChildren(true)
	band:SetFrameLevel(level + 2)
	Core:SolidTex(band, "bandBg", "BACKGROUND", nil, true)
	local bandLight = Core:Light(band, CONTENT_W, HEADER_H, 0.12, 0, 1.2)
	Core:RegisterFadeLight(bandLight, Core:Color("bandLight"))
	local big = sp:CreateTotemGraphic(band, { noOverlap = true })
	big:SetGraphicHeight(150)
	big:SetPoint("TOPRIGHT", band, "TOPRIGHT", -26, 6)
	Core:RegisterFadeAlpha(big, 0.12)
	frame.bandLight = bandLight

	-- the band's words and lines, over the graphic
	local head = CreateFrame("Frame", nil, content)
	head:SetAllPoints(band)
	head:SetFrameLevel(level + 5)
	local bandEdge = head:CreateTexture(nil, "BORDER")
	bandEdge:SetHeight(1)
	bandEdge:SetPoint("BOTTOMLEFT", head, "BOTTOMLEFT", 0, 0)
	bandEdge:SetPoint("BOTTOMRIGHT", head, "BOTTOMRIGHT", 0, 0)
	bandEdge:SetColorTexture(Core:Color("border"))

	local title = head:CreateFontString(nil, "OVERLAY")
	title:SetFontObject(Core.fonts.pageTitle)
	title:SetPoint("LEFT", head, "TOPLEFT", 26, -38)
	frame.title = title

	local subtitle = head:CreateFontString(nil, "OVERLAY")
	subtitle:SetFontObject(Core.fonts.subtitle)
	subtitle:SetPoint("TOPLEFT", head, "TOPLEFT", 27, -61)
	subtitle:SetPoint("RIGHT", head, "RIGHT", -245, 0)   -- room for Preview and Reset This Page beside it (D37)
	subtitle:SetJustifyH("LEFT")
	frame.subtitle = subtitle

	local underline = head:CreateTexture(nil, "ARTWORK")
	underline:SetSize(44, 3)
	underline:SetPoint("BOTTOMLEFT", head, "BOTTOMLEFT", 26, 0)
	frame.underline = underline

	-- Close (on the header's top line, the page search beside it)
	local close = Core:CloseButton(frame, 26)
	close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -14)
	close:SetFrameLevel(level + 8)
	close:SetScript("OnClick", function() frame._closedByPlayer = true; frame:Hide() end)

	-- Tab strip
	local tabStrip = CreateFrame("Frame", nil, content)
	tabStrip:SetHeight(TABSTRIP_H)
	tabStrip:SetPoint("TOPLEFT", content, "TOPLEFT", CONTENT_PAD + 8, -HEADER_H)
	tabStrip:SetPoint("RIGHT", content, "RIGHT", -CONTENT_PAD, 0)
	frame.tabStrip = tabStrip
	frame.tabs = {}

	-- Scoped search: at the top right of the header band (the mock), left of the X
	local pageSearch = CreateFrame("EditBox", nil, content)
	pageSearch:SetSize(200, 22)
	pageSearch:SetPoint("RIGHT", close, "LEFT", -8, 0)
	pageSearch:SetFrameLevel(level + 6)
	pageSearch:SetAutoFocus(false)
	pageSearch:SetFontObject(Core.fonts.row)
	pageSearch:SetTextInsets(8, 8, 0, 0)
	Core:SolidTex(pageSearch, "windowBg", "BACKGROUND")
	Core:MakeBorder(pageSearch, "border")
	frame.pageSearch = pageSearch

	-- What's new: always one click away, left of the page search
	local whatsNew = Core:MakeButton(content, "What's New", 100, false)
	whatsNew:SetPoint("RIGHT", pageSearch, "LEFT", -10, 0)
	whatsNew:SetHeight(22)
	whatsNew:SetFrameLevel(level + 6)
	-- Gold, so it stands out from the plain header buttons.
	whatsNew.text:SetTextColor(1, 0.82, 0)
	for _, edge in pairs(whatsNew.spBorder) do edge:SetColorTexture(1, 0.82, 0, 0.85) end
	whatsNew.bg:SetColorTexture(1, 0.82, 0, 0.10)
	whatsNew:SetScript("OnEnter", function() whatsNew.bg:SetColorTexture(1, 0.82, 0, 0.24) end)
	whatsNew:SetScript("OnLeave", function() whatsNew.bg:SetColorTexture(1, 0.82, 0, 0.10) end)
	whatsNew:SetScript("OnClick", function() local s = SP(); if s and s.ShowWhatsNew then s:ShowWhatsNew(true) end end)
	frame.whatsNewBtn = whatsNew

	-- Preview (D35 B): opens and closes the live preview pane, lit blue while it is
	-- open; a small window-and-panel icon before the word (the panel filled while open)
	local preview = Core:MakeButton(content, "Preview", 0, false)
	preview:SetHeight(22)
	preview:SetFrameLevel(level + 6)
	preview.text:ClearAllPoints()
	preview.text:SetPoint("LEFT", preview, "LEFT", 30, 0)
	preview:SetWidth(30 + math.ceil(preview.text:GetStringWidth()) + 12)
	local lit = preview:CreateTexture(nil, "BACKGROUND", nil, 2)
	lit:SetAllPoints(preview)
	lit:SetColorTexture(Core:Color("accent", 0.34))   -- over the button's own blue: the primary buttons' brighter one
	Core:MonoNote(lit, Core:Color("accent", 0.34))
	lit:Hide()
	local icon = CreateFrame("Frame", nil, preview)
	icon:SetSize(14, 11)
	icon:SetPoint("LEFT", preview, "LEFT", 10, 0)
	local function edge(p1, p2, w, h)
		local t = icon:CreateTexture(nil, "OVERLAY")
		t:SetColorTexture(Core:Color("white"))
		t:SetPoint(p1, icon, p1, 0, 0)
		if w then t:SetWidth(w) end
		if h then t:SetHeight(h) end
		t:SetPoint(p2, icon, p2, 0, 0)
		return t
	end
	edge("TOPLEFT", "TOPRIGHT", nil, 1.5); edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1.5)
	edge("TOPLEFT", "BOTTOMLEFT", 1.5, nil); edge("TOPRIGHT", "BOTTOMRIGHT", 1.5, nil)
	local panel = icon:CreateTexture(nil, "OVERLAY")
	panel:SetPoint("TOPRIGHT", icon, "TOPRIGHT", 0, 0)
	panel:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 0)
	panel:SetWidth(5)
	panel:SetColorTexture(Core:Color("white"))
	local divider = icon:CreateTexture(nil, "OVERLAY")
	divider:SetPoint("TOPRIGHT", icon, "TOPRIGHT", -5, 0)
	divider:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -5, 0)
	divider:SetWidth(1.5)
	divider:SetColorTexture(Core:Color("white"))
	function preview:SetLit(on)
		lit:SetShown(on)
		panel:SetShown(on)
	end
	preview:SetLit(false)
	local hoverIn = preview:GetScript("OnEnter")
	local hoverOut = preview:GetScript("OnLeave")
	preview:SetScript("OnEnter", function(self)
		if hoverIn then hoverIn(self) end
		local tip = Core:Tooltip()
		tip:SetOwner(self, "ANCHOR_CURSOR")
		tip:SetText(frame._previewOpen and "Hide the live preview" or "Show the live preview")
		tip:AddLine("See a preview beside the window. It updates as you change the settings.")
		tip:Show()
	end)
	preview:SetScript("OnLeave", function(self)
		if hoverOut then hoverOut(self) end
		Core:Tooltip():Hide()
	end)
	preview:SetScript("OnClick", function() SPConfig:TogglePreviewPane() end)
	frame.previewBtn = preview

	-- Reset This Page (D30 Q11): a small secondary button beside the page search
	local reset = Core:MakeButton(content, "Reset This Page", 0, false)
	reset:SetHeight(22)
	reset:SetFrameLevel(level + 6)
	reset:SetScript("OnClick", function() ConfirmResetPage() end)
	reset:Hide()
	frame.resetBtn = reset

	-- Turn On (D42): on the page of a module that is off, beside Preview / Reset This
	-- Page; the one thing on that page that keeps its color (its click: RenderPage)
	local turnOn = Core:MakeButton(content, "Turn On", 0, true)
	turnOn:SetHeight(22)
	turnOn:SetFrameLevel(level + 6)
	turnOn:Hide()
	Core.monoSkip[turnOn] = true
	frame.turnOnBtn = turnOn

	local pagePlaceholder = pageSearch:CreateFontString(nil, "OVERLAY")
	pagePlaceholder:SetFontObject(Core.fonts.rowDim)
	pagePlaceholder:SetTextColor(Core:Color("textMute"))
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
	-- General > Themes: once the scrolling settles, the preview switches to the
	-- module section now in view (only when that section changed). Nothing runs
	-- on any other page or while the page sits still.
	do
		local lastScroll, settleQueued = 0, false
		local function Settle()
			if GetTime() - lastScroll < 0.2 then C_Timer.After(0.1, Settle) return end
			settleQueued = false
			if frame and frame._previewOpen and ThemesShownKey() ~= frame._themesShown then SPConfig:UpdatePreviewPane() end
		end
		bodyScroll:HookScript("OnVerticalScroll", function()
			if not (ns.ThemesPage and ns.ThemesPage:IsShown()) then return end
			lastScroll = GetTime()
			if not settleQueued then
				settleQueued = true
				C_Timer.After(0.1, Settle)
			end
		end)
	end
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
	Core:CullScrollChild(bodyScroll, body)   -- rows out of view hidden: a long page (Themes) scrolls light

	-- Footer: its own band (the mock's sidebar navy) under a rule
	local footer = CreateFrame("Frame", nil, content)
	footer:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 0, 0)
	footer:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
	footer:SetHeight(FOOTER_H)
	Core:SolidTex(footer, "sidebarBg", "BACKGROUND", nil, true)
	Core.monoSkip[footer] = true   -- (D42) a page in gray keeps its footer in color
	local footRule = footer:CreateTexture(nil, "ARTWORK")
	footRule:SetHeight(1)
	footRule:SetPoint("TOPLEFT", footer, "TOPLEFT", 0, 0)
	footRule:SetPoint("TOPRIGHT", footer, "TOPRIGHT", 0, 0)
	footRule:SetColorTexture(Core:Color("border"))

	-- Every footer button anchors to a footer edge with an explicit x offset.
	-- Chaining one button off another's corner made it inherit the y offset
	-- twice and sit high.
	local function FooterButton(text, width, at, xOff, primary)
		local b = Core:MakeButton(footer, text, width, primary)
		local point = (at == "left") and "BOTTOMLEFT" or "BOTTOMRIGHT"
		b:SetPoint(point, footer, point, xOff, 14)
		return b, b:GetWidth()
	end

	local reload, reloadW = FooterButton("Reload UI", 100, "left", CONTENT_PAD, false)
	reload:SetScript("OnClick", function() Core:RequestReload() end)

	-- Discord, CurseForge and GitHub beside Reload UI
	LinkButtons(footer, CONTENT_PAD + reloadW + 14)

	local done = FooterButton("Done", 110, "right", -CONTENT_PAD, true)
	done:SetScript("OnClick", function() frame._closedByPlayer = true; frame:Hide() end)

	-- The window's edge (the mock's soft 1.5 px #2B374A) and the four elements
	-- along its top (D32 7), over everything
	local edge = CreateFrame("Frame", nil, frame)
	edge:SetAllPoints(frame)
	edge:SetFrameLevel(level + 14)
	Core:MakeBorder(edge, "border", 1.5)
	local stripe = sp:CreateElementStripe(frame)
	stripe:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	stripe:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
	stripe:SetFrameLevel(level + 15)

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
	frame:SetScript("OnShow", function()
		SPConfig:UpdateCombatLock()
		SPConfig:SetPreviewPaneOpen(PreviewOpenWanted(), true)
		CpuStart()
	end)
	-- The dropdown popup is parented to UIParent so it can escape the scroll
	-- clip; it must not outlive the window.
	frame:SetScript("OnHide", function(self)
		Core:MonoClear()   -- (D42) a gray page's regions are pooled: their colors back
		Widgets:HidePopup()
		SPConfig:HoverStyle(nil)
		SPConfig:ReleasePreview()
		CpuStop()
		MotionWindowHidden()
		SPConfig:ThemeWindowHidden(self)
	end)

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

	MotionWindowBuilt()
	return frame
end

-- ---------------------------------------------------------------------------
-- Sidebar rendering
-- ---------------------------------------------------------------------------
local navRows = {}
local selfNotify = false   -- the window's own change notifications are not news to it
local navPool = {}
local navPoolUsed = 0
local SelectEntry   -- (below: the rows' clicks call it)

-- A page's row: at rest its name in textDim (textMute for another class's
-- shaman-only page); the open page's row LIT (D32b): its group's element at 28%
-- over rowHover fading out to the right, a 3px element bar at its left edge.
local function PaintNavRow(row, on)
	row.lit:SetShown(on)
	row.bar:SetShown(on)
	row.bg:SetColorTexture(0, 0, 0, 0)
	if on then
		row.text:SetFontObject(Core.fonts.navOn)
		row.text:SetTextColor(Core:Color("text"))
	else
		row.text:SetFontObject(Core.fonts.nav)
		row.text:SetTextColor(Core:ColorIf(row.shamanOnly, "textMute", "textDim"))
	end
end

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
		return row
	end
	row = CreateFrame("Button", nil, list)
	navPool[navPoolUsed] = row
	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints(row)
	row.lit = row:CreateTexture(nil, "BACKGROUND", nil, 1)
	row.lit:SetAllPoints(row)
	row.lit:SetColorTexture(1, 1, 1, 1)
	row.bar = row:CreateTexture(nil, "ARTWORK")
	row.bar:SetWidth(3)
	row.bar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
	row.bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
	row.text = row:CreateFontString(nil, "OVERLAY")
	row.text:SetFontObject(Core.fonts.nav)
	row.text:SetPoint("LEFT", row, "LEFT", 30, 0)
	row.text:SetJustifyH("LEFT")
	-- set once (a later SetScript would drop the tooltip's hooks); they read the row's entry
	row:SetScript("OnEnter", function(self)
		if frame._current ~= self.entry then self.bg:SetColorTexture(Core:Color("rowHover", 0.5)) end
	end)
	row:SetScript("OnLeave", function(self)
		if frame._current ~= self.entry then self.bg:SetColorTexture(0, 0, 0, 0) end
	end)
	row:SetScript("OnClick", function(self) if not self.shamanOnly then SelectEntry(self.entry) end end)
	return row
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

-- tab: open the page on that tab; nil opens its first
SelectEntry = function(entry, tab)
	frame._current = entry
	frame._activeTab = tab
	frame.pageSearch:SetText("")
	frame.pageSearch.placeholder:Show()
	SPConfig:RenderPage(entry, nil)
	SPConfig:UpdatePreviewPane()
	for _, r in ipairs(navRows) do PaintNavRow(r, r.entry == entry) end
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
				local n, c = VisiblePath(pth)
				-- Resolve only walks the path, so a group that hides itself still
				-- resolves. Skip those here or the sidebar keeps a row that opens
				-- an empty page (every row on it filtered out by the same flag).
				-- Shaman-only pages (the bars and the shaman modules) are left out for
				-- other classes: nothing on them runs there. Search is built from this list too.
				if n and not (entry.shamanOnly and not PLAYER_IS_SHAMAN) then
					node, chain, firstPath = n, c, pth break
				end
			end
			if node then
				entry._node, entry._chain, entry._firstPath = node, chain, firstPath
				-- Style changes and newly saved loadouts reveal new labels. Rebuild
				-- only when the sidebar draws, never on a timer or while it is shut.
				entry._terms = {}
				entry._resettable = nil   -- (Reset This Page asks again)
				for _, pth in ipairs(EntryPaths(entry)) do
					local n, c, rows = VisiblePath(pth)
					if n then
						for _, term in ipairs(Tree:IndexPage(n, pth, c, rows)) do entry._terms[#entry._terms + 1] = term end
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
			-- the group's header: its element's tiny totem box and its name in small
			-- caps, tinted toward the element (80%)
			local el = GroupElement(groupDef.group)
			local ec = ElementColor(el)
			list.groupHeaders = list.groupHeaders or {}
			local gh = list.groupHeaders[groupDef.group]
			if not gh then
				gh = { box = SP():CreateElementBox(list, 10, el), fs = list:CreateFontString(nil, "OVERLAY") }
				gh.fs:SetFontObject(Core.fonts.group)
				gh.fs:SetText(strupper(groupDef.group))
				gh.fs:SetTextColor(Core:Mix(ec, "text", 0.8))
				list.groupHeaders[groupDef.group] = gh
			end
			gh.box:ClearAllPoints()
			gh.box:SetPoint("TOPLEFT", list, "TOPLEFT", 18, -(y + 6))
			gh.box:Show()
			gh.fs:ClearAllPoints()
			gh.fs:SetPoint("LEFT", list, "TOPLEFT", 34, -(y + 11))
			gh.fs:Show()
			y = y + NAV_GROUP_H

			for _, entry in ipairs(visibleEntries) do
				idx = idx + 1
				firstVisible = firstVisible or entry
				entry._group = groupDef.group

				local row = AcquireNavRow(list)
				row:SetSize(list:GetWidth(), NAV_ROW_H)
				row:ClearAllPoints()
				row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -y)
				-- the open page's light: 28% of the element over rowHover, fading to the right
				-- (painted when the pooled row's element changes, not on every redraw)
				if row.spElement ~= el then
					row.spElement = el
					row.bar:SetColorTexture(ec[1], ec[2], ec[3])
					local litR, litG, litB = Core:Mix(ec, "rowHover", 0.28)
					local hovR, hovG, hovB = Core:Color("rowHover")
					Core:Gradient(row.lit, "HORIZONTAL", litR, litG, litB, 1, hovR, hovG, hovB, 1)
				end

				row.text:SetText(Tree:StripColor(entry.label))
				-- (shaman-only pages never reach here for other classes; kept as a guard)
				row.shamanOnly = entry.shamanOnly and select(2, UnitClass("player")) ~= "SHAMAN"
				row.entry = entry
				PaintNavRow(row, frame._current == entry)
				if row.shamanOnly then Core:AttachTooltip(row, entry.label, "Only available to shamans.") else Core:AttachTooltip(row, "", nil) end
				-- a NEW tag (Patch Notes, until its page is opened): gold small caps, as on the What's New card
				local tagOn = entry.newTag and entry.newTag() or false
				if tagOn and not row.newTag then
					row.newTag = row:CreateFontString(nil, "OVERLAY")
					row.newTag:SetFontObject(Core.fonts.section)
					row.newTag:SetTextColor(1, 0.82, 0)
					row.newTag:SetText("NEW")
				end
				if row.newTag then
					row.newTag:ClearAllPoints()
					row.newTag:SetPoint("LEFT", row.text, "RIGHT", 8, 0)
					row.newTag:SetShown(tagOn)
				end

				-- The module's on / off (D32 C2): the tiny totem switch in the group's
				-- element (0.62 of the settings rows' switch). An explicit binding on the
				-- entry wins, otherwise an "Enable ..." toggle found in the page is promoted.
				if row.power then row.power:Hide() end
				entry._powerGet, entry._powerSet = nil, nil   -- (D42) the page reads its module's on / off here
				if groupDef.power and not row.shamanOnly then
					local getter, setter, tipTitle, tipBody = ResolvePower(entry)
					if getter then
						entry._powerGet, entry._powerSet = getter, setter
						local pw = row.power
						if not pw then
							pw = SP():CreateTotemSwitch(row, { scale = 0.62 })
							pw:SetPoint("RIGHT", row, "RIGHT", -16, 0)
							row.power = pw
						end
						if pw.spElement ~= el then pw.spElement = el; pw:SetElement(el) end
						pw:Show()
						local function PaintSwitch()
							pw:SetChecked(getter())
						end
						pw:SetScript("OnClick", function()
							setter(not getter())
							PaintSwitch()
							if frame._current == entry then SPConfig:RenderPage(entry, nil) end
						end)
						Core:AttachTooltip(pw, tipTitle, tipBody, "Click to turn it on or off")
						PaintSwitch()
						row.paintPower = PaintSwitch
					end
				end

				table.insert(navRows, row)
				y = y + NAV_ROW_H
			end
			y = y + NAV_GROUP_GAP
		else
			local gh = list.groupHeaders and list.groupHeaders[groupDef.group]
			if gh then gh.box:Hide(); gh.fs:Hide() end
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
		if c.node.type == "group" and VisiblePath(c.path) then
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
	-- the strip's width, worked out from the window's fixed layout rather than read
	-- back: a tab that would run past it starts a new row (a long page or a big font)
	local stripW = CONTENT_W - 2 * CONTENT_PAD - 8
	-- the open tab's underline in the page's element
	local ec = ElementColor(frame._element or "spirit")
	local x, row = 0, 0
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
		local w = math.max(tab.text:GetStringWidth() + 26, 60)
		tab:SetWidth(w)
		if x > 0 and x + w > stripW then x, row = 0, row + 1 end
		tab:ClearAllPoints()
		tab:SetPoint("TOPLEFT", frame.tabStrip, "TOPLEFT", x, -row * TABSTRIP_H)

		local isActive = (g.key == activeKey)
		tab.text:SetFontObject(isActive and Core.fonts.navOn or Core.fonts.nav)
		tab.underline:SetColorTexture(ec[1], ec[2], ec[3])
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

		x = x + w
	end
	frame.tabStrip:SetHeight((row + 1) * TABSTRIP_H)
end

-- Widgets go back to their pools rather than being orphaned; pageWidgets is
-- kept only as the "did this render draw anything" count for the empty state.
local function ClearPage()
	if frame.bodyScroll.spCullReset then frame.bodyScroll.spCullReset() end   -- rows hidden out of view: back first
	Widgets:ReleaseAll(frame.body)
	wipe(pageWidgets)
	if ns.ThemesPage then ns.ThemesPage:Release() end
	if ns.PatchNotesPage then ns.PatchNotesPage:Release() end
	for _, row in pairs(ns.CustomRows) do
		if row.Release then row:Release() end
	end
end

-- General > Themes draws its own page (Themes.lua) in place of its group's
-- rows; a search appends its matching blocks after the ordinary settings rows.
local function CustomTabActive(entry, query)
	if (query and query ~= "") or not (entry and entry.tabs) then return nil end
	for _, t in ipairs(entry.tabs) do
		if t.custom and t.label == frame._activeTab then return t.custom end
	end
	return nil
end

-- a row's tag after its label: SP.OptionRowTag[option] = "TEXT" or function(option) -> text or nil
local function OptionOpts(entry, sectionRef, x, y, width, onChanged)
	local node, chain, info = entry.node, entry.chain, entry.info
	local sp = SP()
	local tag = sp and sp.OptionRowTag and node and sp.OptionRowTag[node]
	return {
		label    = Tree:StripColor(entry.label),
		desc     = entry.desc and Tree:StripColor(entry.desc) or nil,
		x = x, y = y, width = width,
		section  = sectionRef,
		disabled = function() return Tree:IsDisabled(node, chain, info) end,
		onChanged = onChanged,
		tag = tag, tagNode = node,
	}
end

local function FilterList(list, query)
	if not (query and query ~= "") then return list end
	local filtered, pendingSection = {}, nil
	for _, e in ipairs(list) do
		if e.kind == "section" then
			pendingSection = e
		else
			local hay = strlower(Tree:StripColor(e.label) .. " " .. Tree:StripColor(e.desc))
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
			RenderTabs(tabs, (not searching) and active.key or nil, onPick)   -- no tab lit while search results span them all
		else
			RenderTabs({}, nil, function() end)
		end
	end
	return active
end

local function OnTabPick(key)
	frame._activeTab = key
	SPConfig:RenderPage(frame._current, nil)
	SPConfig:UpdatePreviewPane()
end

-- Composed page: entry.tabs -> each tab draws one or more option groups.
local function ResolveComposed(entry, query, drawTabs)
	local searching = (query and query ~= "")
	local tabs = {}
	for _, t in ipairs(entry.tabs) do
		local live = {}
		for _, pth in ipairs(t.paths) do
			local n, c, rows = VisiblePath(pth)
			if n then
				live[#live + 1] = { node = n, chain = c, path = pth, rows = rows }
			end
		end
		if #live > 0 then tabs[#tabs + 1] = { key = t.label, name = t.label, live = live, custom = t.custom } end
	end
	if #tabs == 0 then
		if drawTabs then RenderTabs({}, nil, function() end) end
		return {}, {}
	end
	local active = PickTab(tabs, OnTabPick, drawTabs, searching)
	local list = {}
	for _, t in ipairs(searching and tabs or { active }) do
		-- The custom renderer searches its real blocks, not the Ace placeholder.
		for _, lv in ipairs((searching and t.custom == "themes") and {} or t.live) do
			-- A first band already labels these rows; do not stack an empty
			-- same-depth group heading directly above it.
			if (#t.live > 1 or (searching and #tabs > 1)) and lv.rows[1].kind ~= "section" then
				local info = Tree:BuildInfo(lv.path, lv.node, lv.chain)
				local label = lv.path.label or Tree:StripColor(Tree:GetName(lv.node, info))
				if searching and #tabs > 1 and #t.live == 1 then label = t.name end
				table.insert(list, { kind = "section", label = label, depth = 0 })
			end
			for _, row in ipairs(lv.rows) do
				-- (a search result's tooltip names its tab; the rows are built fresh per call)
				if searching and #tabs > 1 then row._spTab = t.name end
				list[#list + 1] = row
			end
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
	-- a search spans the page's tabs: each row remembers its tab for its tooltip's path
	if useTabs and searching and #groups >= 2 then
		for _, e in ipairs(list) do
			if e.kind == "option" and e.path then
				for _, g in ipairs(groups) do
					if PathStartsWith(e.path, g.path) then
						e._spTab = Tree:StripColor(g.name ~= "" and g.name or g.key)
						break
					end
				end
			end
		end
	end
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
			-- the label too: a name that follows another setting (Ready Effect /
			-- Effect While Shown) is redrawn when only it changed
			parts[#parts + 1] = table.concat(e.path, "/") .. "=" .. tostring(e.label)
		end
	end
	return table.concat(parts, "|")
end

-- The page wears its NAV group's element (D32 4, D32b): the header band's
-- light (26% over the intro's navy), the page's own faint light (11% over the
-- content), the title's underline; the tabs, cards and switches read it too.
local function PaintPageElement(key)
	local ec = ElementColor(key)
	Core:SetFadeColor(frame.contentLight, Core:Mix(ec, "contentBg", 0.11))
	Core:SetFadeColor(frame.bandLight, Core:Mix(ec, "bandLight", 0.26))
	frame.underline:SetColorTexture(ec[1], ec[2], ec[3])
	frame._element = key
end

-- The header's buttons (D37 option 2, owner 2026-10-02): the title's row keeps What's New
-- (General > Main), the page search and the X; Reset This Page and Preview sit on the
-- description's row, right-aligned with the X, so no page title can run into them.
local function PlaceHeaderButtons()
	local reset, preview = frame.resetBtn, frame.previewBtn
	if not reset then return end
	local head = frame.title:GetParent()
	reset:ClearAllPoints()
	reset:SetPoint("RIGHT", head, "TOPRIGHT", -10, -67)
	if preview then
		preview:ClearAllPoints()
		if reset:IsShown() then
			preview:SetPoint("RIGHT", reset, "LEFT", -8, 0)
		else
			preview:SetPoint("RIGHT", head, "TOPRIGHT", -10, -67)
		end
	end
end

local ResetShown   -- (with Reset This Page, below)

local function RenderPageInner(self, entry, query, keepScroll)
	local wasThemesSearch = frame._themesSearch
	frame._themesSearch = nil
	ClearPage()
	if frame.whatsNewBtn then frame.whatsNewBtn:Hide() end
	if frame.resetBtn then frame.resetBtn:Hide() end
	if not entry then return end

	local firstPath = entry._firstPath or entry.path or EntryPaths(entry)[1]
	local node, chain
	if firstPath then node, chain = Tree:Resolve(firstPath) end
	if not node then return end

	local element = GroupElement(entry._group)
	if frame._element ~= element then PaintPageElement(element) end

	local info = Tree:BuildInfo(firstPath, node, chain)
	frame.title:SetText(Tree:StripColor(entry.label))
	frame.subtitle:SetText(Tree:StripColor(entry.desc or Tree:GetDesc(node, info) or ""))

	local patchNotes = entry.custom == "patchnotes" and ns.PatchNotesPage or nil
	local list, groups = ResolvePageList(entry, (not patchNotes) and query or nil, true)
	-- What's New sits on General's Main tab only (elsewhere it covers the page description)
	if frame.whatsNewBtn then frame.whatsNewBtn:SetShown(entry.label == "General" and frame._activeTab == "Main") end
	if frame.resetBtn then frame.resetBtn:SetShown(ResetShown(entry)) end
	PlaceHeaderButtons()
	if not list then return end
	frame._query = query
	frame._pageSig = PageSignature(list, groups)
	local customTab = CustomTabActive(entry, query) == "themes" and ns.ThemesPage or nil
	if customTab or patchNotes then list = {} end   -- drawn below by the page itself
	local searchThemes, themeSelection
	if query and query ~= "" and ns.ThemesPage then
		for _, tab in ipairs(groups or {}) do
			if tab.custom == "themes" then searchThemes = true break end
		end
		if searchThemes then themeSelection = ns.ThemesPage:Search(query) end
	end
	frame._themesSearch = searchThemes

	local body = frame.body
	local fullW = frame.bodyScroll:GetWidth() - 8
	if fullW <= 1 then
		-- Anchors have not resolved yet on the first draw; fall back to geometry.
		fullW = CONTENT_W - (CONTENT_PAD * 2) - 8
	end
	body:SetWidth(fullW)

	-- One card per section (D30 6, D32b): a section's rows sit in one card headed
	-- by a strip with the element's box and the section's name, thin lines between
	-- the rows and a divider between the two columns. Everything else of the
	-- packer is as before: the order, the two columns, spans, widening, action
	-- rows, descriptions, featured headers, custom rows. (Not for a page that
	-- draws itself.)
	Widgets:SetElement(element)
	local INSET, cellW = Widgets.CARD_INSET, math.floor(fullW / 2)
	local tags = SP() and SP().OptionHeaderTag

	local y = 0
	if #list > 0 then y = CARD_TOP end
	local col, rowY, rowMaxH = 1, y, 0
	local currentSection
	local card, cardTop, cardEnd, cardLines, runTop, runEnd, gapUnder
	local pending = {}   -- headings waiting for their first row (the last one heads that row's card)

	-- A row reached through search says where it lives (D34, its tooltip's last line):
	-- Settings > the sidebar's page > its tab (a page with tabs) > its card's name.
	-- Only while searching: the normal page draws its rows without it.
	local pathBase = (query and query ~= "") and ("Settings > " .. Tree:StripColor(entry.label)) or nil
	local pathSection
	local function SearchPath(e)
		if not pathBase then return nil end
		local tab = e._spTab
		local path = pathBase
		if tab and tab ~= "" then path = path .. " > " .. tab end
		if pathSection and pathSection ~= tab then path = path .. " > " .. pathSection end
		return path
	end

	-- a finished line of rows in the open card: a thin line above it (not the first
	-- line) and the column divider through a run of two-column lines
	local function FlushRun()
		if runTop then
			Widgets:CardLine(card, cellW, runTop + 6 - cardTop, 1, runEnd - runTop - 12, "border")
			runTop = nil
		end
	end
	local function EndLine(top, height, twoCol)
		if not card then return end
		if cardLines > 0 then Widgets:CardLine(card, 12, top - cardTop, fullW - 24, 1, "borderSoft") end
		cardLines = cardLines + 1
		if twoCol then
			runTop = runTop or top
			runEnd = top + height
		else
			FlushRun()
		end
		cardEnd = top + height
	end

	local function BreakRow()
		if col == 2 then
			EndLine(rowY, rowMaxH, true)   -- a left column on its own
			y = rowY + rowMaxH
			col, rowMaxH = 1, 0
			rowY = y
		end
	end

	local function CloseCard()
		BreakRow()
		if not card then return end
		FlushRun()
		Widgets:CardFinish(card, cardEnd - cardTop)
		y = cardEnd + CARD_GAP
		rowY, col, rowMaxH = y, 1, 0
		card, gapUnder = nil, true
	end

	-- a heading with no rows of its own (a group holding only groups): today's plain heading
	local function PlainHeading(e)
		local f, h = Widgets:SectionHeader(body, { label = Tree:StripColor(e.label), x = 0, y = y, width = fullW })
		table.insert(pageWidgets, f)
		currentSection = f
		y = y + h
		rowY, gapUnder = y, false
	end

	local function OpenCard()
		if card then return end
		for i = 1, #pending - 1 do PlainHeading(pending[i]) end
		local sec = pending[#pending]
		for i = #pending, 1, -1 do pending[i] = nil end
		local label, tag = sec and Tree:StripColor(sec.label) or nil, nil
		if label == "" then label = nil end
		if label and tags and sec.node then tag = tags[sec.node] end
		if sec then pathSection = label end
		card = Widgets:Card(body, { x = 0, y = y, width = fullW, label = label, element = element, tag = tag })
		currentSection = card
		cardTop, cardLines = y, 0
		if label then y = y + Widgets.STRIP_H end
		cardEnd = y
		rowY, col, rowMaxH = y, 1, 0
	end

	local onChanged = function()
		-- A set() may flip another option's hidden= (e.g. TotemTimers Style
		-- Display reveals Right-Click Drops Corner Totem). Re-resolve the page
		-- and redraw only when the visible row set actually changed.
		selfNotify = true
		local navQuery = string.lower(frame.navSearch:GetText() or ""):match("^%s*(.-)%s*$")
		local first = SPConfig:RenderNav(navQuery ~= "" and navQuery or nil)
		local cur = frame._current
		if not EntryHasContent(cur) then
			SelectEntry(first)
			selfNotify = false
			return
		end
		if cur then
			local newList, newGroups = ResolvePageList(cur, frame._query, false)
			-- A theme choice can change both its search text and conditional rows,
			-- including a search that previously had no Themes matches.
			if newList and (searchThemes or PageSignature(newList, newGroups) ~= frame._pageSig) then
				SPConfig:RenderPage(cur, frame._query, frame.bodyScroll:GetVerticalScroll())
				if LibStub then
					local reg = LibStub("AceConfigRegistry-3.0", true)
					if reg then reg:NotifyChange("ShamanPower") end
				end
				selfNotify = false
				SPConfig:PreviewChanged()   -- this path returns early: the preview still needs the new settings
				return
			end
		end
		Widgets:RefreshAll(body)
		for _, r in ipairs(navRows) do
			if r.paintPower and r:IsShown() then r.paintPower() end
		end
		if frame.spPaintActions then frame.spPaintActions() end
		if LibStub then
			local reg = LibStub("AceConfigRegistry-3.0", true)
			if reg then reg:NotifyChange("ShamanPower") end
		end
		selfNotify = false
		SPConfig:PreviewChanged()   -- the sample data is re-fed with the new settings
	end
	frame._onChanged = onChanged

	-- Options that pick a totem bar style preview it while hovered (the map is
	-- keyed by the option table itself: AceConfig allows no extra keys).
	local spNow = SP()
	local hoverStyles = spNow and spNow.OptionHoverStyle or nil
	local actionRows = spNow and spNow.SettingsActionRow
	local buttonTones = spNow and spNow.OptionButtonTone   -- [option] = "help": a gold button
	local actionThrough = 0
	SPConfig:HoverStyle(nil)   -- a rebuild under the mouse gets no OnLeave

	for index, e in ipairs(list) do
		-- Skip actions already drawn together on the preceding row.
		if index > actionThrough and e.kind == "option" and e.type == "execute" and actionRows and actionRows[e.node] then
			OpenCard()
			BreakRow()
			local count = 1
			while count < 3 do
				local nextEntry = list[index + count]
				if not nextEntry or nextEntry.kind ~= "option" or nextEntry.type ~= "execute"
					or not actionRows[nextEntry.node] then break end
				count = count + 1
			end
			local width = math.floor((fullW - 2 * INSET - COL_GAP * (count - 1)) / count)
			local height = 0
			for offset = 0, count - 1 do
				local action = list[index + offset]
				local opts = OptionOpts(action, currentSection, INSET + offset * (width + COL_GAP), rowY, width, onChanged)
				opts.inCard = true
				opts.searchPath = SearchPath(action)
				opts.func = Tree:MakeFunc(action.node, action.chain, action.info)
				opts.buttonText = Tree:StripColor(action.label)
				opts.tone = buttonTones and buttonTones[action.node]
				local widget, used = Widgets:Button(body, opts)
				pageWidgets[#pageWidgets + 1] = widget
				height = math.max(height, used)
			end
			EndLine(rowY, height, false)
			y = rowY + height
			rowY, col, rowMaxH = y, 1, 0
			actionThrough = index + count - 1
		elseif index > actionThrough and e.kind == "section" then
			-- a featured section (SP.OptionFeaturedHeader, keyed by the option group) gets the big gold heading
			local sp0 = SP()
			local featured = sp0 and sp0.OptionFeaturedHeader and e.node and sp0.OptionFeaturedHeader[e.node]
			CloseCard()
			if not featured then
				pending[#pending + 1] = e   -- its card opens with its first row
			else
				-- the gold heading as before, its rows in a card under it
				for i = 1, #pending do PlainHeading(pending[i]) end
				for i = #pending, 1, -1 do pending[i] = nil end
				pathSection = Tree:StripColor(e.label)
				local f, h = Widgets:SectionHeader(body, {
					label = pathSection, x = 0, y = y, width = fullW, featured = featured,
				})
				table.insert(pageWidgets, f)
				currentSection = f
				y = y + h
				rowY, gapUnder = y, false
			end
		elseif index > actionThrough then
			OpenCard()
			local span = Tree:ColumnSpan(e.node, e.info)
			if span == 2 then BreakRow() end
			-- two columns of half the card each (the divider between them), inset so a
			-- row's label sits 14 in from its cell
			local x, w
			if span == 2 then
				x, w = INSET, fullW - 2 * INSET
			elseif col == 1 then
				x, w = INSET, cellW - 2 * INSET
			else
				x, w = cellW + INSET, fullW - cellW - 2 * INSET
			end

			local opts = OptionOpts(e, currentSection, x, rowY, w, onChanged)
			opts.inCard = true
			opts.searchPath = SearchPath(e)
			local f, h

			if e.type == "toggle" then
				opts.get = Tree:MakeGetter(e.node, e.chain, e.info)
				local setter = Tree:MakeSetter(e.node, e.chain, e.info)
				opts.set = function(v) setter(v) end
				local hs = hoverStyles and hoverStyles[e.node]
				if hs and hs ~= "select" then
					opts.onEnter = function() SPConfig:HoverStyle(hs) end
					opts.onLeave = function() SPConfig:HoverStyle(nil) end
				end
				f, h = Widgets:Toggle(body, opts)

			elseif e.type == "range" then
				opts.get = Tree:MakeGetter(e.node, e.chain, e.info)
				local setter = Tree:MakeSetter(e.node, e.chain, e.info)
				opts.set = function(v) setter(v) end
				opts.min  = Tree:EvalPlain(e.node.min, e.info) or 0
				opts.max  = Tree:EvalPlain(e.node.max, e.info) or 100
				opts.step = Tree:EvalPlain(e.node.step, e.info) or 1
				opts.isPercent = e.node.isPercent and true or false
				f, h = Widgets:Slider(body, opts)

			elseif e.type == "select" then
				opts.get = Tree:MakeGetter(e.node, e.chain, e.info)
				local setter = Tree:MakeSetter(e.node, e.chain, e.info)
				opts.set = function(v) setter(v) end
				opts.values = Tree:MakeValues(e.node, e.info)
				opts.order  = Tree:MakeSorting(e.node, e.info)
				local control = e.node.dialogControl
				opts.keyIsLabel = type(control) == "string" and control:sub(1, 6) == "LSM30_"
				if hoverStyles and hoverStyles[e.node] == "select" then
					opts.onHover = function(key) SPConfig:HoverStyle(key) end
					opts.onHoverEnd = function() SPConfig:HoverStyle(nil) end
				end
				-- a font list: each name in its own font, and the hovered one shown on the frames
				local fontArea = spNow and spNow.OptionHoverFont and spNow.OptionHoverFont[e.node]
				if fontArea then
					local lsm = LibStub and LibStub("LibSharedMedia-3.0", true)
					opts.itemFont = function(key)
						local path = lsm and key and key:sub(1, 2) ~= "__" and lsm:Fetch("font", key, true) or nil
						if path then return spNow:ResolveLocaleFontPath(path) end
					end
					opts.onHover = function(key) local sp = SP(); if sp and sp.PreviewFont then sp:PreviewFont(fontArea, key) end end
					opts.onHoverEnd = function() local sp = SP(); if sp and sp.PreviewFont then sp:PreviewFont(nil) end end
				end
				-- a bar texture list: a swatch per texture, and the hovered one shown on the bars
				local texArea = spNow and spNow.OptionHoverTexture and spNow.OptionHoverTexture[e.node]
				if texArea then
					local lsm = LibStub and LibStub("LibSharedMedia-3.0", true)
					opts.itemTexture = function(key) return lsm and key and key:sub(1, 2) ~= "__" and lsm:Fetch("statusbar", key, true) or nil end
					opts.onHover = function(key) local sp = SP(); if sp and sp.PreviewTexture then sp:PreviewTexture(texArea, key) end end
					opts.onHoverEnd = function() local sp = SP(); if sp and sp.PreviewTexture then sp:PreviewTexture(nil) end end
				end
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
				opts.tone = buttonTones and buttonTones[e.node]
				f, h = Widgets:Button(body, opts)

			elseif e.type == "description" then
				-- a row drawn by its own code: SP.OptionCustomRow[node] = key names a
				-- renderer in ns.CustomRows (:Render(body, x, y, width, onChanged) ->
				-- frame, height; :Release() on every redraw): the full width of its
				-- card (it draws no background of its own)
				local customKey = spNow and spNow.OptionCustomRow and spNow.OptionCustomRow[e.node]
				local customRow = customKey and ns.CustomRows[customKey]
				BreakRow()
				if customRow then
					local ok, cf, ch = pcall(customRow.Render, customRow, body, 0, rowY, fullW, onChanged)
					if ok and cf then
						table.insert(pageWidgets, cf)
						EndLine(rowY, ch or 0, false)
						y = rowY + (ch or 0)
						rowY = y
					elseif not ok then
						geterrorhandler()(cf)
					end
				else
					opts.text = Tree:ThemeText(e.label)   -- plain text, with notes in the note color
					opts.x, opts.y, opts.width = INSET, rowY, fullW - 2 * INSET
					f, h = Widgets:Description(body, opts)
					table.insert(pageWidgets, f)
					EndLine(rowY, h, false)
					y = rowY + h
					rowY = y
				end
				h = nil
			end

			if f and h then
				-- Never show an ellipsis while there is room: a column that cannot
				-- hold the label hands the row the full width.
				if span == 1 and Widgets:LabelTruncated(f) then
					if col == 2 then
						EndLine(rowY, rowMaxH, true)
						y = rowY + rowMaxH
						rowY = y
						col, rowMaxH = 1, 0
					end
					f:ClearAllPoints()
					f:SetPoint("TOPLEFT", body, "TOPLEFT", INSET, -rowY)
					h = Widgets:Widen(f, fullW - 2 * INSET) or h
					span = 2
				end
				table.insert(pageWidgets, f)
				if span == 2 then
					EndLine(rowY, h, false)
					y = rowY + h
					rowY = y
					col, rowMaxH = 1, 0
				else
					rowMaxH = math.max(rowMaxH, h)
					if col == 2 then
						EndLine(rowY, rowMaxH, true)
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

	CloseCard()
	for i = 1, #pending do PlainHeading(pending[i]) end   -- (a heading left with no rows)
	if gapUnder then y = y - CARD_GAP end   -- no gap under the last card
	rowY = y

	if customTab then
		local ok, h = pcall(customTab.Render, customTab, body, fullW, onChanged)
		if ok then
			y = h or 0
			pageWidgets[#pageWidgets + 1] = body
		else
			geterrorhandler()(h)
		end
	elseif patchNotes then
		-- Settings > Patch Notes: the page search narrows the notes themselves
		local ok, h = pcall(patchNotes.Render, patchNotes, body, fullW, onChanged, query)
		if ok then
			y = h or 0
			pageWidgets[#pageWidgets + 1] = body
		else
			geterrorhandler()(h)
		end
	elseif themeSelection then
		BreakRow()
		local header, height = Widgets:SectionHeader(body, { label = "Themes", x = 0, y = y, width = fullW })
		pageWidgets[#pageWidgets + 1] = header
		y = y + height
		local ok, heightUsed = pcall(ns.ThemesPage.Render, ns.ThemesPage, body, fullW, onChanged, themeSelection, y)
		if ok then
			y = heightUsed or y
		else
			geterrorhandler()(heightUsed)
		end
	end
	Widgets:SetElement(nil)

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
	if searchThemes or wasThemesSearch then self:UpdatePreviewPane() end
end

-- A module that is off (D42): its page has no color. It is drawn once, every region
-- of it then remembers the colors it is painted with (Core:MonoWatch), it is drawn
-- again so every paint is known, and then it all turns gray (Core:MonoSet): the
-- footer and Turn On keep their colors. A note under the title says it is off; every
-- setting still works. Turning the module on (Turn On or the sidebar switch) draws
-- the page again in color. Nothing of this runs on a page whose module is on.
function SPConfig:RenderPage(entry, query, keepScroll)
	Core:MonoClear()
	local turnOn = frame.turnOnBtn
	local head = frame.title:GetParent()
	if turnOn then turnOn:Hide() end
	frame.subtitle:SetPoint("RIGHT", head, "RIGHT", -245, 0)   -- room for Preview and Reset This Page beside it (D37)
	local off = false
	local get = entry and entry._powerGet
	if get then
		local ok, on = pcall(get)
		off = ok and not on
	end
	if not off then return RenderPageInner(self, entry, query, keepScroll) end

	RenderPageInner(self, entry, query, keepScroll)
	local content = frame.content
	Core:MonoWatch(content)
	frame._element = nil                 -- the element's lights and underline paint again, now remembered
	Core:ApplyOpacity(Core.opacity)      -- every faded background too
	for _, b in ipairs({ frame.previewBtn, frame.resetBtn }) do
		if b and b.spPaint then b.spPaint(false) end
	end
	RenderPageInner(self, entry, query, frame.bodyScroll:GetVerticalScroll())

	frame.subtitle:SetText("|cffE6EAF0" .. Tree:StripColor(entry.label) .. " is turned off.|r You can still change its settings.")
	if turnOn then
		turnOn:ClearAllPoints()
		local preview, reset = frame.previewBtn, frame.resetBtn
		local left = (preview and preview:IsShown() and preview) or (reset and reset:IsShown() and reset) or nil
		if left then turnOn:SetPoint("RIGHT", left, "LEFT", -8, 0) else turnOn:SetPoint("RIGHT", head, "TOPRIGHT", -10, -67) end
		turnOn:SetScript("OnClick", function()
			local set = entry._powerSet
			if not set then return end
			set(true)
			for _, r in ipairs(navRows) do
				if r.entry == entry and r.paintPower then r.paintPower() end
			end
			SPConfig:RenderPage(entry, frame._query, frame.bodyScroll:GetVerticalScroll())
		end)
		turnOn:Show()
		frame.subtitle:SetPoint("RIGHT", turnOn, "LEFT", -12, 0)
	end
	Core:MonoSet(content)
	-- anything the page draws a moment later (a row laid out on the next frame) goes gray too
	C_Timer.After(0, function()
		if frame:IsShown() and frame._current == entry and Core:MonoActive() then Core:MonoSet(frame.content) end
	end)
end

do
	-- ---------------------------------------------------------------------------
	-- ShamanPower's CPU (D30 7; G's profiler spec): the recent average time per frame
	-- of every loaded ShamanPower addon folder (ShamanPower and each ShamanPower_*,
	-- each counted once), from the game's own addon profiler, beside the version. A
	-- one-second ticker while the window is shown, cancelled when it hides; hidden
	-- where the profiler is missing or off. Nothing is allocated per tick.
	-- ---------------------------------------------------------------------------
	local cpuRoster, cpuTicker = {}, nil

	local function CpuAvailable()
		local profiler = rawget(_G, "C_AddOnProfiler")
		local metrics = Enum and Enum.AddOnProfilerMetric
		if not (profiler and profiler.GetAddOnMetric and profiler.IsEnabled and metrics and metrics.RecentAverageTime) then
			return false
		end
		local ok, on = pcall(profiler.IsEnabled)
		return ok and on == true
	end

	local function CpuSample()
		if not (frame and frame:IsShown()) then return end
		if not CpuAvailable() then CpuStop() return end
		local getMetric, metric = C_AddOnProfiler.GetAddOnMetric, Enum.AddOnProfilerMetric.RecentAverageTime
		local ms = 0
		for i = 1, #cpuRoster do
			local ok, v = pcall(getMetric, cpuRoster[i], metric)
			if ok and type(v) == "number" and not (issecretvalue and issecretvalue(v)) then ms = ms + v end
		end
		-- the share of a frame at the current frame rate: ms / (1000 / fps) * 100
		local fps = GetFramerate() or 0
		local pct = 0
		if fps > 0 then pct = ms / (1000 / fps) * 100 end
		frame.cpuValue:SetFormattedText("%.2f%%  (%.2f ms per frame)", pct, ms)
	end

	CpuStart = function()
		if cpuTicker then cpuTicker:Cancel(); cpuTicker = nil end
		if not CpuAvailable() then
			frame.cpuLabel:Hide(); frame.cpuValue:Hide()
			return
		end
		-- the loaded ShamanPower folders, read on each opening (a module can load later)
		wipe(cpuRoster)
		local num = C_AddOns and C_AddOns.GetNumAddOns or GetNumAddOns
		local nameOf = C_AddOns and C_AddOns.GetAddOnInfo or GetAddOnInfo
		local loaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
		for i = 1, num() do
			local name = nameOf(i)
			if type(name) == "string" and (name == "ShamanPower" or name:find("^ShamanPower_")) and loaded(name) then
				cpuRoster[#cpuRoster + 1] = name
			end
		end
		frame.cpuLabel:Show(); frame.cpuValue:Show()
		CpuSample()
		cpuTicker = C_Timer.NewTicker(1, CpuSample)
	end

	CpuStop = function()
		if cpuTicker then cpuTicker:Cancel(); cpuTicker = nil end
		if frame then frame.cpuLabel:Hide(); frame.cpuValue:Hide() end
	end

	-- ===========================================================================
	-- The window's own motion (D31: Unlock UI's round trips). Every open falls in
	-- (SPConfig:Open calls MotionIn when the window was not already up); closing
	-- stays instant unless SetMotionClose is on:
	--   SPConfig:MotionIn()
	--       Right after the window is shown: it falls in from above the top of the
	--       screen to its place in 0.3 s with the logo's back-ease (s = 1.6, so it
	--       overshoots a hair and settles), then the landing hit exactly as in the
	--       approved clip (settings-polish/landing_hit_clip.py): a jolt of logo blue
	--       through its border (outlines 0 / 2 / 4 px out, alphas 1 / 0.45 / 0.2,
	--       fading as (1 - p)^1.5 over 0.15 s) and a soft white sheen crossing it
	--       diagonally (0.2 s, ease-in-out, clipped to the window), both from the
	--       moment it lands (0.62 of the fall).
	--   SPConfig:MotionOut(onDone)
	--       It shoots up off the top (0.15 s, ease-in), hides, then calls
	--       onDone(window, skipped): skipped is true when a click, Escape or combat
	--       finished it early (or it could not play: in combat, already hidden), false
	--       when it ran to the end. Show(), Raise() or Open() while it rises keep the
	--       window where it is (no hide, no onDone).
	--   SPConfig:SetMotionClose(on)
	--       Every way of closing the window (the X, Done, Escape through
	--       UISpecialFrames, a slash command, Keybind Mode: anything that calls its
	--       Hide) plays MotionOut first; OnHide runs when it has gone. Always on (the
	--       owner: closing ALWAYS flies up); kept for Unlock UI's calls, `false` is ignored.
	--   SPConfig:IsLeaving()
	--       True while a MotionOut plays.
	-- A click anywhere, Escape or combat starting finishes a motion at once. Only
	-- the window's anchor offset moves and it is put back exactly, so where the
	-- window sits never changes. One OnUpdate while a motion plays, none otherwise;
	-- nothing is allocated per frame. No sound.
	-- ===========================================================================
	local FALL, HIT, SHEEN, RISE = 0.30, 0.15, 0.20, 0.15
	local LAND = FALL * 0.62                 -- the clip's landing moment
	local RING_ALPHA = { 1, 0.45, 0.2 }      -- the jolt's outlines at 0 / 2 / 4 px out
	local CLIP_K = WIN_W / 700               -- the clip drew the window 700 wide
	local EaseBack = SP().BrandEaseBack
	local motion = { t = 0, dist = 0, x = 0, y = 0 }
	local motionClose = true   -- every close flies up (see SetMotionClose)
	local motionDriver = CreateFrame("Frame")
	local motionHit, motionSheenClip, motionSheen, motionKeys, RealHide, RealShow, RealRaise
	local KeepOnShow, KeepOnRaise   -- (while a MotionOut plays: Show / Raise keep the window)

	-- onDone(window, skipped), its errors to the error handler (Lua 5.1's xpcall passes no arguments)
	local function CallDone(fn, skipped)
		xpcall(function() fn(frame, skipped) end, geterrorhandler())
	end

	local function EaseInOut(x)
		if x < 0.5 then return 4 * x * x * x end
		local u = 2 - 2 * x
		return 1 - u * u * u / 2
	end

	local function MotionOffset(dy)
		frame:SetPoint(motion.point, motion.rel, motion.relPoint, motion.x, motion.y + dy)
	end

	-- the jolt (three rings of four edges, logo blue) and the sheen (the clip's 31 thin
	-- diagonal lines, scaled to the window, in a holder moved across a clipping frame)
	local function BuildLandingHit()
		local blue = SP().Brand.logoBlue
		local level = frame:GetFrameLevel()
		motionHit = CreateFrame("Frame", nil, frame)
		motionHit:SetAllPoints(frame)
		motionHit:SetFrameLevel(level + 60)
		motionHit.rings = {}
		for k = 1, 3 do
			local o = (k - 1) * 2
			local ring = {}
			local function Edge(p1, x1, y1, p2, x2, y2, w, h)
				local t = motionHit:CreateTexture(nil, "OVERLAY")
				t:SetColorTexture(blue[1], blue[2], blue[3], 1)
				t:SetPoint(p1, frame, p1, x1, y1)
				t:SetPoint(p2, frame, p2, x2, y2)
				if w then t:SetWidth(w) else t:SetHeight(h) end
				ring[#ring + 1] = t
			end
			Edge("TOPLEFT", -o, o, "TOPRIGHT", o, o, nil, 2)
			Edge("BOTTOMLEFT", -o, -o, "BOTTOMRIGHT", o, -o, nil, 2)
			Edge("TOPLEFT", -o, o - 2, "BOTTOMLEFT", -o, 2 - o, 2, nil)
			Edge("TOPRIGHT", o, o - 2, "BOTTOMRIGHT", o, 2 - o, 2, nil)
			motionHit.rings[k] = ring
		end
		motionHit:Hide()

		motionSheenClip = CreateFrame("Frame", nil, frame)
		motionSheenClip:SetAllPoints(frame)
		motionSheenClip:SetFrameLevel(level + 59)
		motionSheenClip:SetClipsChildren(true)
		motionSheen = CreateFrame("Frame", nil, motionSheenClip)
		motionSheen:SetSize(1, WIN_H)
		for i = 0, 30 do
			local off = -60 + i * 4
			local l = motionSheen:CreateLine(nil, "OVERLAY")
			l:SetThickness(4 * CLIP_K)
			l:SetColorTexture(1, 1, 1, math.floor(30 * (1 - math.abs(off) / 60)) / 255)
			l:SetStartPoint("TOPLEFT", motionSheen, off * CLIP_K, 0)
			l:SetEndPoint("BOTTOMLEFT", motionSheen, (off - 120) * CLIP_K, 0)
		end
		motionSheenClip:Hide()
	end

	-- how: "end" = it ran to the end; "keep" = a MotionOut stopped because the window is
	-- wanted again (it stays, its onDone is dropped); nil = finished early (a click,
	-- Escape, combat, a hide): the end state at once, onDone told it was skipped
	local function FinishMotion(how)
		local kind = motion.kind
		if not kind then return end
		motion.kind = nil
		motionDriver:SetScript("OnUpdate", nil)
		motionDriver:UnregisterAllEvents()
		if motionKeys then motionKeys:Hide() end
		if motionHit then motionHit:Hide(); motionSheenClip:Hide() end
		if rawget(frame, "Show") == KeepOnShow then frame.Show = nil end
		if rawget(frame, "Raise") == KeepOnRaise then frame.Raise = nil end
		local done = motion.onDone
		motion.onDone = nil
		local leaves = kind == "out" and how ~= "keep"
		if leaves then RealHide(frame) end
		MotionOffset(0)
		frame:SetClampedToScreen(true)
		if leaves and done then CallDone(done, how ~= "end") end
	end

	local function MotionStep(_, elapsed)
		local m = motion
		m.t = m.t + elapsed
		local t = m.t
		if m.kind == "out" then
			local p = t / RISE
			if p >= 1 then FinishMotion("end") return end
			MotionOffset(m.dist * p * p * p)   -- ease-in: slow, then fast
			return
		end
		local p = t / FALL
		if p > 1 then p = 1 end
		MotionOffset((1 - EaseBack(p, 1.6)) * m.dist)
		-- the landing hit
		local hp = (t - LAND) / HIT
		if hp >= 0 and hp <= 1 then
			if not motionHit:IsShown() then motionHit:Show() end
			local a = (1 - hp) ^ 1.5
			for k = 1, 3 do
				local ring, ra = motionHit.rings[k], RING_ALPHA[k] * a
				for i = 1, 4 do ring[i]:SetAlpha(ra) end
			end
		elseif hp > 1 and motionHit:IsShown() then
			motionHit:Hide()
		end
		local sp = (t - LAND) / SHEEN
		if sp > 1 then FinishMotion("end") return end
		if sp >= 0 then
			if not motionSheenClip:IsShown() then motionSheenClip:Show() end
			motionSheen:SetPoint("TOPLEFT", motionSheenClip, "TOPLEFT", (-160 + 1020 * EaseInOut(sp)) * CLIP_K, 0)
		end
	end

	motionDriver:SetScript("OnEvent", function(_, event)
		-- (the click that opened the window, in the same frame, does not count)
		if event == "GLOBAL_MOUSE_DOWN" and GetTime() == motion.started then return end
		FinishMotion()
	end)

	-- Escape during a motion finishes it (out of combat an addon may hold the key for a
	-- moment, as ShamanPower's dialogs do; every other key passes through)
	local function MotionKey(self, key)
		if InCombatLockdown() then return end   -- (hidden by then)
		if key == "ESCAPE" then
			self:SetPropagateKeyboardInput(false)
			FinishMotion()
		else
			self:SetPropagateKeyboardInput(true)
		end
	end

	local function StartMotion(kind)
		motion.kind, motion.t, motion.started = kind, 0, GetTime()
		frame:SetClampedToScreen(false)
		if kind == "out" then
			frame.Show, frame.Raise = KeepOnShow, KeepOnRaise
			local tip = SP() and SP().Tooltip   -- a row's tooltip must not ride along as it flies away
			if tip and tip.Hide then tip:Hide() end
		end
		motionDriver:SetScript("OnUpdate", MotionStep)
		pcall(motionDriver.RegisterEvent, motionDriver, "GLOBAL_MOUSE_DOWN")
		motionDriver:RegisterEvent("PLAYER_REGEN_DISABLED")
		if not motionKeys then
			motionKeys = CreateFrame("Frame", nil, UIParent)
			motionKeys:SetAllPoints(UIParent)
			motionKeys:SetFrameStrata("FULLSCREEN_DIALOG")
			motionKeys:SetFrameLevel(240)
			motionKeys:EnableMouse(false)
			motionKeys:EnableKeyboard(true)
			motionKeys:SetScript("OnKeyDown", MotionKey)
		end
		motionKeys:SetPropagateKeyboardInput(true)   -- a key held from before passes through
		motionKeys:Show()
	end

	-- where it sits now, and how far up takes it wholly off the top of the screen (the
	-- clip: its top's distance from the screen's top, its height, 20 more)
	local function MotionMeasure()
		frame:StopMovingOrSizing()   -- (a drag in progress: its anchor first settles)
		if frame:GetNumPoints() ~= 1 then
			-- anchored by more than one point (the client's own placement after a drag):
			-- pin it where it is by its top-left, so the offset can carry the motion
			local left, top = frame:GetLeft(), frame:GetTop()
			if not (left and top) then return false end
			frame:ClearAllPoints()
			frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
		end
		local point, rel, relPoint, x, y = frame:GetPoint(1)
		local top, screenTop = frame:GetTop(), UIParent:GetTop()
		if not (point and top and screenTop) then return false end
		motion.point, motion.rel, motion.relPoint, motion.x, motion.y = point, rel, relPoint, x or 0, y or 0
		motion.dist = (screenTop - top) + frame:GetHeight() + 20
		return true
	end

	-- General > Main > UI Animations off: no motion, the window just shows and hides
	local function AnimationsOn()
		local sp = SP()
		return not (sp and sp.UIAnimationsOn) or sp:UIAnimationsOn()
	end

	function SPConfig:MotionIn()
		if not (frame and frame:IsShown()) then return end
		if motion.kind == "in" then return end   -- already falling in: it carries on
		if not AnimationsOn() then return end
		if motion.kind then FinishMotion("keep") end   -- (one leaving stays: it comes back in)
		if InCombatLockdown() or not MotionMeasure() then return end   -- in a fight it simply stays
		if not motionHit then BuildLandingHit() end
		StartMotion("in")
		MotionOffset(motion.dist)   -- starts wholly above the screen
	end

	function SPConfig:MotionOut(onDone)
		if not (frame and frame:IsShown()) then
			if onDone then CallDone(onDone, true) end
			return
		end
		if motion.kind == "out" then
			-- already leaving: this onDone runs after the first one
			if onDone then
				local first = motion.onDone
				motion.onDone = function(w, skipped) if first then first(w, skipped) end onDone(w, skipped) end
			end
			return
		end
		if motion.kind then FinishMotion() end
		if InCombatLockdown() or not AnimationsOn() or not MotionMeasure() then
			RealHide(frame)
			if onDone then CallDone(onDone, true) end
			return
		end
		motion.onDone = onDone
		StartMotion("out")
	end

	function SPConfig:IsLeaving()
		return motion.kind == "out"
	end

	-- while motion-close is on, Hide() plays MotionOut first
	local function MotionHide(self)
		if motion.kind == "out" then return end   -- already on its way up
		self._motionHideAt = GetTime()            -- (the Escape hook below reads it)
		SPConfig:MotionOut(nil)
	end

	function SPConfig:SetMotionClose(_on)
		-- (always on: a caller turning it off after a round trip changes nothing)
		if not frame then return end   -- applied when the window is built
		if motionClose then frame.Hide = MotionHide end
	end

	MotionWindowBuilt = function()
		-- the frame's own methods (before any override)
		RealHide, RealShow, RealRaise = frame.Hide, frame.Show, frame.Raise
		if motionClose then frame.Hide = MotionHide end
	end

	-- the window hid for real in the middle of a motion (not by the motion itself):
	-- the motion ends there (a MotionOut's onDone still runs)
	MotionWindowHidden = function()
		if motion.kind and not frame:IsShown() then FinishMotion() end
	end

	-- the window is opened again while it is leaving: it stays (and no close happened,
	-- so no player's close waits for its hide)
	MotionOpenedAgain = function()
		if motion.kind == "out" then
			frame._closedByPlayer = nil
			FinishMotion("keep")
		end
	end
	-- Show() or Raise() while it leaves (Unlock UI's ReopenSettingsWindow raises it): it stays
	KeepOnShow = function(self)
		MotionOpenedAgain()
		return RealShow(self)
	end
	KeepOnRaise = function(self)
		MotionOpenedAgain()
		return RealRaise(self)
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
			if q ~= "" and first then
				if frame._current ~= first then SelectEntry(first) end
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

-- An update adds files (ShamanPowerBrand.lua, the Fira fonts) that WoW only sees after
-- a full restart: until then the window cannot be drawn, so it does not open (said once).
local restartSaid = false
local function NeedsRestart()
	local sp = SP()
	if sp and sp.Brand then return false end
	if not restartSaid then
		restartSaid = true
		print("|cff0070ddShamanPower|r: I was updated while WoW was running. Please exit WoW completely"
			.. " and start it again to finish the update (a /reload is not enough).")
	end
	return true
end

function SPConfig:Open(path)
	if NeedsRestart() then return end
	local wasShown = frame and frame:IsShown()
	BuildWindow()
	if not frame._wired then
		WireSearch()
		frame._wired = true
	end
	MotionOpenedAgain()
	frame:Show()
	frame:Raise()
	Core:SyncOpacity()
	self:UpdateCombatLock()
	local first = self:RenderNav(nil)
	local best, bestTab
	if path then
		path = ResolvePathAlias(path)
		local bestDepth, bestVisible
		for _, r in ipairs(navRows) do
			if r.entry then
				local depth, tab, visible = EntryPathMatch(r.entry, path)
				if depth and (not bestDepth or (visible and not bestVisible)
					or (visible == bestVisible and depth > bestDepth)) then
					best, bestTab, bestDepth, bestVisible = r.entry, tab, depth, visible
				end
			end
		end
		if best then SelectEntry(best, bestTab) end
	end
	if not best then SelectEntry(EntryHasContent(frame._current) and frame._current or first) end
	-- every way in (the minimap button, /sp, Esc > Options, What's New ...) drops it in
	-- from the top with the landing hit; a window that is still here just stays
	if not wasShown then self:MotionIn() end
end

-- Lives for the session regardless of whether the window has ever been built,
-- so entering combat always reaches UpdateCombatLock.
local combatWatcher = CreateFrame("Frame")
combatWatcher:RegisterEvent("PLAYER_REGEN_DISABLED")
combatWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
combatWatcher:SetScript("OnEvent", function(_, event)
	-- InCombatLockdown() is still false while REGEN_DISABLED fires: track it from the event
	SPConfig._inCombat = (event == "PLAYER_REGEN_DISABLED")
	SPConfig:UpdateCombatLock()
	if frame and frame:IsShown() and frame.body then
		frame._lastCombat = InCombatLockdown() and true or false
		Widgets:RefreshAll(frame.body)
		-- pause a module preview for the fight (see UpdatePreviewPane), bring it back after
		SPConfig:UpdatePreviewPane()
	end
end)

-- Something outside the window changed the addon's state while it is open
-- (an assignment from a flyout or Blizzard's totem bar, a loadout applied):
-- the core raises AceConfig's change notification, and the open page redraws
-- as if one of its own rows had been set. Coalesced to one redraw per frame.
do
	local reg = LibStub and LibStub("AceConfigRegistry-3.0", true)
	if reg and reg.RegisterCallback then
		local queued = false
		reg.RegisterCallback(SPConfig, "ConfigTableChange", function(_, appName)
			if appName ~= "ShamanPower" or selfNotify or queued then return end
			if not (frame and frame:IsShown() and frame._onChanged) then return end
			queued = true
			C_Timer.After(0, function()
				queued = false
				if frame and frame:IsShown() and frame._onChanged then frame._onChanged() end
			end)
		end)
	end
end

-- A theme changed (General > Themes, a colour picker drag, a profile switch)
-- while the window is open: the Themes page repaints on the next frame, the
-- live preview is rebuilt, and the page's rows re-read their values once the
-- changes settle. Nothing runs while the window is shut.
local themeChangedWhileOpen = false
do
	local sp = SP()
	if sp and sp.OnThemeChanged then
		local paintQueued, settleQueued, lastTheme = false, false, 0
		local function Paint()
			paintQueued = false
			if not (frame and frame:IsShown()) then return end
			if frame._themesSearch then
				-- A theme change can create matches even when none were drawn before.
				SPConfig:RefreshCurrent()
			elseif ns.ThemesPage then
				ns.ThemesPage:Repaint()
			end
			SPConfig:PreviewChanged(true)
		end
		local function Settle()
			if GetTime() - lastTheme < 0.25 then C_Timer.After(0.1, Settle) return end
			settleQueued = false
			if frame and frame:IsShown() and frame.body then Widgets:RefreshAll(frame.body) end
		end
		sp:OnThemeChanged(function()
			if not (frame and frame:IsShown()) then return end
			themeChangedWhileOpen = true
			lastTheme = GetTime()
			if not paintQueued then paintQueued = true; C_Timer.After(0, Paint) end
			if not settleQueued then settleQueued = true; C_Timer.After(0.1, Settle) end
		end)
	end
end

-- Reload prompt on close: a theme changed while the window was open, and the
-- player closed it (Done, the X or Escape): ask for a reload once, so every
-- part picks the new look up. Mainline: the existing reload prompt (a secure
-- button, Core:RequestReload). Classic reloads straight away from that call,
-- so it gets the same prompt drawn here, with the plain call on its button.
-- Windows that tuck the settings away for a moment (Unlock, Keybind Mode, the
-- tour) never prompt.
local themeReloadDlg
local THEME_RELOAD_REASON = "You changed your ShamanPower theme. Reload the UI so every part picks up the new look."
local function ShowThemeReloadPrompt()
	if SPCompat.FOREVER then
		Core:RequestReload(THEME_RELOAD_REASON)
		return
	end
	if not themeReloadDlg then
		local f = Core:CreateDialog({
			name = "ShamanPowerThemeReloadPrompt", width = 430, height = 168,
			title = "Reload for your new look", footer = 46, special = true, strata = "FULLSCREEN_DIALOG",
		})
		local t = f.body:CreateFontString(nil, "OVERLAY")
		t:SetFontObject(Core.fonts.row)
		t:SetPoint("TOPLEFT", f.body, "TOPLEFT", 0, -2)
		t:SetWidth(390); t:SetJustifyH("LEFT"); t:SetWordWrap(true)
		t:SetText(THEME_RELOAD_REASON .. " |cff808080Typing |cffFFD100/reload|r|cff808080 yourself works just as well.|r")
		f:SetHeight(math.max(168, 46 + 4 + 10 + math.ceil(t:GetStringHeight()) + 2 + 14 + 46))
		local ok = Core:MakeButton(f, "Reload now", 150, true)
		ok:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 12)
		ok:SetScript("OnClick", function() Core:RequestReload() end)
		local later = Core:MakeButton(f, "Later", 100, false)
		later:SetPoint("RIGHT", ok, "LEFT", -8, 0)
		later:SetScript("OnClick", function() f:Hide() end)
		themeReloadDlg = f
	end
	themeReloadDlg:Show()
end

local reloadWaiter = CreateFrame("Frame")
local function ThemeReloadOnClose()
	local sp = SP()
	if not (themeChangedWhileOpen and sp and sp.ThemeChangedThisSession) then return end
	if frame and frame:IsShown() then return end   -- opened again meanwhile: the next close asks
	if InCombatLockdown() then
		-- nothing pops up in a fight: ask once it ends
		reloadWaiter:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end
	themeChangedWhileOpen = false
	sp.ThemeChangedThisSession = false   -- once: a later close asks again only after another change
	ShowThemeReloadPrompt()
end
reloadWaiter:SetScript("OnEvent", function(self)
	self:UnregisterEvent("PLAYER_REGEN_ENABLED")
	ThemeReloadOnClose()
end)

function SPConfig:ThemeWindowHidden(win)
	if win:IsShown() then return end   -- the whole UI was hidden (Alt+Z), not this window
	if win._closedByPlayer then
		win._closedByPlayer = nil
		C_Timer.After(0, ThemeReloadOnClose)
	else
		-- Escape closes it through CloseSpecialWindows (hooked below); any other
		-- hide in this frame is some window tucking the settings away
		win._maybeEscape = true
		C_Timer.After(0, function() win._maybeEscape = nil end)
	end
end

if type(CloseSpecialWindows) == "function" then
	hooksecurefunc("CloseSpecialWindows", function()
		if frame and frame._maybeEscape then
			frame._maybeEscape = nil
			C_Timer.After(0, ThemeReloadOnClose)
		end
		-- Escape while motion-close is on: the window is still leaving (MotionOut) and
		-- hides a moment later, as a close by the player
		if frame and frame._motionHideAt == GetTime() then frame._closedByPlayer = true end
	end)
end

do
	-- ---------------------------------------------------------------------------
	-- Reset This Page (D30 Q11): every setting on the open page, all its tabs, back
	-- to how it came, after a confirm that names the page. Left alone: buttons,
	-- descriptions and custom rows; anything named like a position (where things
	-- sit on screen is Unlock UI's); anything a theme holds (a reset that changes the
	-- theme's look is put back at once); the lists the player made (saved loadouts,
	-- Auto-Switch rules, the new-loadout form); and everything in combat. A default
	-- is what the setting's own getter reads with every setting at its default: the
	-- profile's defaults in place of the profile, and each module's saved table
	-- empty (they read their defaults then), as the theme cards work them out.
	-- ---------------------------------------------------------------------------
	local RESET_TYPES = { toggle = true, range = true, select = true, color = true, input = true }
	-- the modules' own saved tables (ShamanPowerSupportCode.lua MODULE_SVARS)
	local RESET_MODULE_SVARS = { "ShamanPowerExpiringAlertsDB", "ShamanPower_ReadyReminders", "ShamanPower_ReactiveTotems",
		"ShamanPowerTremorReminderDB", "ShamanPower_RangeTracker" }
	-- where things sit and how they are laid out on screen: never reset (a key or a
	-- name with one of these words, and every row under a heading with LAYOUT_WORDS)
	local RESET_POSITION_WORDS = { "position", "anchor", "offset", "point", "placement", "arrange", "grow", "align" }
	local RESET_LAYOUT_WORDS = { "position", "placement", "layout" }

	local function PositionLike(key, name)
		local k, n = strlower(key), strlower(name or "")
		for _, w in ipairs(RESET_POSITION_WORDS) do
			if k:find(w, 1, true) or n:find(w, 1, true) then return true end
		end
		-- "pos", x and y as a part of the key (posX, barPos, offsetY, x) or a word of the name
		if k:find("^pos") or key:find("Pos") or k:find("_pos") then return true end
		if k == "x" or k == "y" or key:find("[a-z][XY]$") or k:find("_[xy]$") or k:find("^[xy]_") then return true end
		local words = " " .. n:gsub("[^%w]", " ") .. " "
		return words:find(" pos ", 1, true) or words:find(" x ", 1, true) or words:find(" y ", 1, true) or false
	end

	local function Resettable(e, sp)
		if not RESET_TYPES[e.type] or e.spLayout then return false end
		if sp.OptionCustomRow and sp.OptionCustomRow[e.node] then return false end
		local key = e.path and e.path[#e.path]
		if type(key) ~= "string" then return false end
		-- lists the player made: Auto-Switch rules, saved loadouts, the new-loadout form
		if key:find("^rule_") or key:find("^lo_") or key:find("^new_") then return false end
		return not PositionLike(key, e.label)
	end

	local function LayoutHeading(label)
		local l = strlower(Tree:StripColor(label or ""))
		for _, w in ipairs(RESET_LAYOUT_WORDS) do
			if l:find(w, 1, true) then return true end
		end
		return false
	end

	-- every option row on the page, on all its tabs (not a tab the page draws itself),
	-- that is not in `seen` yet; each goes into `seen`. A row under a Position /
	-- Placement / Layout heading is marked e.spLayout: under any heading still open
	-- above it (a heading closes at the next heading as high up or higher), or in a
	-- composed page's group of that name
	local function PageOptionRows(entry, seen)
		local out, paths = {}, {}
		if entry.tabs then
			for _, t in ipairs(entry.tabs) do
				if not t.custom then
					for _, p in ipairs(t.paths) do paths[#paths + 1] = p end
				end
			end
		elseif entry.path then
			paths[1] = entry.path
		end
		for _, pth in ipairs(paths) do
			local n, c, rows = VisiblePath(pth)
			if n then
				local groupLayout = false
				if pth.label then
					groupLayout = LayoutHeading(pth.label)
				elseif entry.tabs then
					groupLayout = LayoutHeading(Tree:GetName(n, Tree:BuildInfo(pth, n, c)))
				end
				local open, deepest = {}, -1   -- [depth] = true: the heading open there is a layout heading
				for _, e in ipairs(rows) do
					local depth = e.depth or 0
					if e.kind == "section" then
						for d = depth + 1, deepest do open[d] = nil end
						open[depth] = LayoutHeading(e.label)
						deepest = depth
					elseif e.kind == "option" and not seen[e.node] then
						seen[e.node] = true
						local layout = groupLayout
						for d = 0, deepest do
							if open[d] then layout = true end
						end
						e.spLayout = layout
						out[#out + 1] = e
					end
				end
			end
		end
		return out
	end

	local function Copy(v)
		if type(v) ~= "table" then return v end
		local t = {}
		for k, x in pairs(v) do t[k] = Copy(x) end
		return t
	end

	-- the defaults view: a copy of the profile's defaults (plus the profile tables whose
	-- defaults live in their own file, as the support code reads them)
	local function DefaultsView(sp)
		local view = Copy(sp.db and sp.db.defaults and sp.db.defaults.profile or {})
		local extra = sp.SUPPORT_PROFILE_DEFAULTS
		if type(extra) == "table" then
			for k, v in pairs(extra) do
				if view[k] == nil then view[k] = Copy(v) end
			end
		end
		return view
	end

	-- what a getter reads with every setting at its default: ok, then its values. A
	-- module's saved table is stood in for by a fresh copy of the defaults the module
	-- registered (SP.SUPPORT_MODULE_DEFAULTS: its own, for this client); a module that
	-- registered none is left as it is, so its rows read their current values (no change)
	local function ReadDefault(get, view, sp)
		local real, keep, swapped = sp.opt, {}, {}
		local md = type(sp.SUPPORT_MODULE_DEFAULTS) == "table" and sp.SUPPORT_MODULE_DEFAULTS or {}
		for i, name in ipairs(RESET_MODULE_SVARS) do
			if type(md[name]) == "table" then
				keep[i], swapped[i] = rawget(_G, name), true
				_G[name] = Copy(md[name])
			end
		end
		sp.opt = view
		local ok, a, b, c, d = pcall(get)
		sp.opt = real
		for i, name in ipairs(RESET_MODULE_SVARS) do
			if swapped[i] then _G[name] = keep[i] end
		end
		return ok, a, b, c, d
	end

	local function Near(a, b)
		if type(a) == "number" and type(b) == "number" then return math.abs(a - b) < 0.0001 end
		return a == b
	end

	-- one setting to its default; put back when the reset moved what a theme holds
	local function ResetOption(e, view, sp)
		local get = Tree:MakeGetter(e.node, e.chain, e.info)
		local set = Tree:MakeSetter(e.node, e.chain, e.info)
		local okNow, n1, n2, n3, n4 = pcall(get)
		local okDef, d1, d2, d3, d4 = ReadDefault(get, view, sp)
		if not (okNow and okDef) then return end
		if e.type == "toggle" then
			-- nil and false are both off (the default goes back as it is: nil stays nil)
			if (n1 and true or false) == (d1 and true or false) then return end
		elseif e.type == "color" then
			if d1 == nil or (Near(n1, d1) and Near(n2, d2) and Near(n3, d3) and Near(n4 or 1, d4 or 1)) then return end
		elseif d1 == nil or Near(n1, d1) then
			return   -- (no default to go back to, or already there)
		end
		local before = sp.ThemeFlatSnapshot and sp:ThemeFlatSnapshot()
		if not pcall(set, d1, d2, d3, d4) then return end
		if before and not sp:ThemeFlatSame(before, sp:ThemeFlatSnapshot()) then
			pcall(set, n1, n2, n3, n4)   -- a theme's setting: it stays as it was
		end
	end

	function SPConfig:ResetPage(entry)
		local sp = SP()
		if not (sp and entry) or InCombatLockdown() then return end
		local view = DefaultsView(sp)
		local wasChanged, wasSession = themeChangedWhileOpen, sp.ThemeChangedThisSession
		local startFlat = sp.ThemeFlatSnapshot and sp:ThemeFlatSnapshot()
		-- a reset can show rows that were hidden (an "Enable" switch back on): they are
		-- reset too, in another pass
		local seen = {}
		for _ = 1, 3 do
			local rows = PageOptionRows(entry, seen)
			if #rows == 0 then break end
			for _, e in ipairs(rows) do
				if Resettable(e, sp) then ResetOption(e, view, sp) end
			end
		end
		-- the theme came out as it went in: no reload prompt for it on closing
		if startFlat and sp:ThemeFlatSame(startFlat, sp:ThemeFlatSnapshot()) then
			themeChangedWhileOpen, sp.ThemeChangedThisSession = wasChanged, wasSession
		end
		if LibStub then
			local reg = LibStub("AceConfigRegistry-3.0", true)
			if reg then reg:NotifyChange("ShamanPower") end
		end
		-- the page and the live preview show the defaults
		self:RefreshCurrent()
		self:PreviewChanged(true)
	end

	local RESET_COMBAT = "|cff0070ddShamanPower|r: |cffe64a4aSettings cannot be reset in combat"
		.. " - click Reset again after the fight.|r"

	ConfirmResetPage = function()
		local entry = frame and frame._current
		local sp = SP()
		if not (entry and sp and sp.ShowSPDialog) then return end
		if InCombatLockdown() then print(RESET_COMBAT) return end
		sp:ShowSPDialog({
			key = "resetPage", title = "Reset This Page",
			text = "Reset every " .. Tree:StripColor(entry.label) .. " setting to how it came?"
				.. " Where things sit on screen and your theme stay.",
			buttons = {
				{ text = "Reset", onClick = function()
					-- combat began while it was open: say so, and keep the question up for after the fight
					if InCombatLockdown() then print(RESET_COMBAT) return true end
					if frame._current == entry then SPConfig:ResetPage(entry) end
				end },
				{ text = "Cancel" },
			},
		})
	end

	-- the button shows where there is something to reset: not on the Themes tab or
	-- Patch Notes, not on Profiles (it switches profiles), not on a page of buttons
	ResetShown = function(entry)
		if entry.custom == "patchnotes" or (entry.path and entry.path[1] == "profiles") then return false end
		-- a page whose parts each reset on their own (Target Tracker: Reset This Spell, a rule's x,
		-- Reset Position), its settings in a module's own saved table
		if entry.noReset then return false end
		if CustomTabActive(entry, nil) then return false end
		local sp = SP()
		if not sp then return false end
		if entry._resettable == nil then
			entry._resettable = false
			for _, e in ipairs(PageOptionRows(entry, {})) do
				if Resettable(e, sp) then entry._resettable = true break end
			end
		end
		return entry._resettable
	end
end

function SPConfig:IsOpen()
	return frame ~= nil and frame:IsShown() and true or false
end

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
	-- Reset This Page is off in combat: its caption goes quiet (a click says why)
	if frame.resetBtn then
		frame.resetBtn.text:SetTextColor(Core:ColorIf(InCombatLockdown() or SPConfig._inCombat, "textMute", "white"))
	end
end

-- Redraw the current page (options table changed shape, e.g. a loadout was
-- added or renamed). Keeps the scroll position.
function SPConfig:RefreshCurrent()
	if frame and frame:IsShown() and frame._current then
		local navQuery = string.lower(frame.navSearch:GetText() or ""):match("^%s*(.-)%s*$")
		local first = self:RenderNav(navQuery ~= "" and navQuery or nil)
		if EntryHasContent(frame._current) then
			self:RenderPage(frame._current, frame._query, frame.bodyScroll:GetVerticalScroll())
		else
			SelectEntry(first)
		end
	end
end

function SPConfig:Toggle()
	if NeedsRestart() then return end
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
				min = 0.2, max = 1, step = 0.05, isPercent = true,
				width = "full",
				get = function()
					return ShamanPower.opt.uiOpacity or 1
				end,
				set = function(_, v)
					v = math.floor(v * 100 + 0.5) / 100   -- store whole percents, as before
					ShamanPower.opt.uiOpacity = v
					Core:ApplyOpacity(v)
				end,
			},
		},
	}
end
InjectOptions()

-- Interface is created by this settings UI; keep the original scale
-- option object and its callback when moving it from the old Scale section.
do
	local sp = SP()
	local settings = sp and sp.options and sp.options.args.settings
	if settings and settings.args.settings_newui then
		sp.MoveSettingsOptions({ "fluffy", "scale_section" }, { "settings", "settings_newui" }, { "assignmentsscale" })
		local option = settings.args.settings_newui.args.assignmentsscale
		if option then
			option.order = 2
			option.hidden = function() return not PLAYER_IS_SHAMAN end
		end
	end
end

-- Root files have now contributed their General actions. Keep the original
-- objects so their handlers, hover maps and featured community header survive.
do
	local sp = SP()
	local root = sp and sp.options and sp.options.args
	local main = root and root.settings.args.settings_show
	if main then
		sp.OrderSettingsBands(main, {
			{ keys = { "globally", "totemBarStyle", "hide_blizzard_totem_bar", "hide_player_totems" } },
			{ keys = { "showparty", "showsingle", "showminimapicon", "showtooltips" } },
			{ keys = { "master_unlock", "keybind_mode", "open_assignments" }, names = {
				master_unlock = "Unlock UI", keybind_mode = "Keybind Mode", open_assignments = "Open Totem Assignments",
			} },
			{ keys = { "windfuryOnly" } },
			{ keys = { "community", "share_setup", "support_code" } },
		})
		sp.SettingsActionRow = {}
		for _, key in ipairs({ "master_unlock", "keybind_mode", "open_assignments" }) do
			local option = main.args[key]
			if option then sp.SettingsActionRow[option] = true end
		end
		local keybind = root.settings.args.settings_keybinds and root.settings.args.settings_keybinds.args.keybind_mode
		if keybind then keybind.name = "Keybind Mode" end
	end
end

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
