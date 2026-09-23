-- ShamanPower_Config / WhatsNew.lua
-- Small once-per-release "what's new" card for existing users. New installs
-- get the guided setup instead and are never shown this; releases whose notes
-- below do not match the running version show nothing at all. The seen
-- version is stamped account-wide (db.global.lastSeenVersion).
local _, ns = ...
local Core = ns.Core
local SP = ShamanPower
if not SP then return end

-- Notes for the release this file ships with. Update per big release; leave
-- items for the running version out entirely and the popup stays quiet.
-- Test builds ("2.1.0-alpha2") match on the part before the dash.
local NOTES = {
	-- PLACEHOLDER until the release is versioned: must equal the TOC version
	-- of the release that ships these notes, or the card stays quiet.
	version = "2.2.0",
	items = {
		{ h = "Grid style: every totem on screen", try = "grid",
		  b = "A fifth look for the totem bar. Every totem of every element sits in rows: click one to drop it, the assigned one is highlighted and the dropped one carries the timer. Split by Element gives each row its own movable frame and direction."
		    .. "\n|cff3FA9F5Settings > General > Totem Bar Style|r  -  hover a style there to see it in the live preview" },
		{ h = "Totem Coverage: who is missing your buff", when = function() return SP.CoverageAvailable and SP:CoverageAvailable() end,
		  b = "The reverse of Totem Range. Under each of your totems, the names of the party members who do NOT have its buff, in red or class colour. Pick which totems to watch; it hides itself once everyone is covered, in combat too."
		    .. "\n|cff3FA9F5Settings > Party Buff Tracker > Totem Coverage|r" },
		{ h = "Totem markers on the minimap", when = function() return SP.MinimapTotemsAvailable end,
		  b = "A pin where each totem was dropped and a ring for its reach, turning with the minimap. Open world only."
		    .. "\n|cff3FA9F5Settings > Totem Range Tracker|r" },
		{ h = "Auto-Assign picks by who is in the group",
		  b = "Stoneskin for caster-only groups and Strength of Earth with melee; Mana Spring with mana users, Healing Stream otherwise; the Air totem by who benefits. This changes what Auto-Assign picks for existing characters too." },
		{ h = "The settings window shows what it changes",
		  b = "The arrow tab on the right opens a live preview of the page's module, redrawn as you change its settings. Every window a module has (Totem Range picker, Raid Cooldowns, the fear-caster list, Totem Assignments) opens from a button on its page, and every option those windows hold is on the page too. Test buttons hide the window while they run." },
	},
	footer = "Also: the loadout bar has a Move button and a box in Unlock All, the loadout icon picker is rebuilt with a search box, and ShamanPower now runs on WoW: Forever - Forever characters get the setup tour instead of this card. The full list is in the changelog.",
}

local function BaseVersion(v)
	return v and (v:gsub("%-.*$", "")) or nil
end

-- ---------------------------------------------------------------------------
-- Style preview: the setup tour's own Totem Bar mock, drawn with the player's
-- current bar settings plus one style's flags (ShamanPowerStyles.lua), in
-- read-only preview mode. Nothing changes unless "Turn it on" is pressed.
-- ---------------------------------------------------------------------------
local previewDlg
local function ShowStylePreview(key)
	local st = SP.TotemBarStyle and SP:TotemBarStyle(key)
	if not (st and SP.Wizard and SP.Wizard.BuildTotemBarStep and SP.ApplyTotemBarStyleTo) then
		print("|cff0070ddShamanPower|r: that totem bar style is not available on this client.")
		return
	end
	if not previewDlg then
		previewDlg = Core:CreateDialog({
			name = "ShamanPowerStylePreview", width = 560, height = 372,
			title = st.label, subtitle = "a preview with your current bar settings - nothing changes until you turn it on",
			headerHeight = 46, footer = 52, special = true, strata = "FULLSCREEN_DIALOG",
		})
		local solid = previewDlg:CreateTexture(nil, "BACKGROUND", nil, 1)
		solid:SetPoint("TOPLEFT", 2, -2); solid:SetPoint("BOTTOMRIGHT", -2, 2)
		solid:SetColorTexture(Core:Color("windowBg", 1))
		local solidH = previewDlg.header:CreateTexture(nil, "BACKGROUND", nil, 1)
		solidH:SetAllPoints(previewDlg.header); solidH:SetColorTexture(Core:Color("sidebarBg", 1))

		local shot = CreateFrame("Frame", nil, previewDlg.body)
		shot:SetPoint("TOPLEFT", previewDlg.body, "TOPLEFT", 0, 0)
		shot:SetPoint("TOPRIGHT", previewDlg.body, "TOPRIGHT", 0, 0)
		shot:SetHeight(190)
		Core:SolidTex(shot, "contentBg", "BACKGROUND"); Core:MakeBorder(shot, "border")
		previewDlg.shot = shot

		local cap = previewDlg.body:CreateFontString(nil, "OVERLAY"); cap:SetFontObject(Core.fonts.rowDim)
		cap:SetPoint("TOPLEFT", shot, "BOTTOMLEFT", 0, -8); cap:SetPoint("TOPRIGHT", shot, "BOTTOMRIGHT", 0, -8)
		cap:SetJustifyH("LEFT"); cap:SetWordWrap(true)
		previewDlg.cap = cap

		-- spOnHide keeps the dialog shell's own OnHide (popup cleanup) intact
		previewDlg.spOnHide = function(self)
			SP.Wizard.optOverride = nil
			SP.Wizard.previewOnly = nil
			if self.host then self.host:Hide() end
		end

		local on = Core:MakeButton(previewDlg, "Turn it on", 150, true)
		on:SetPoint("BOTTOMRIGHT", previewDlg, "BOTTOMRIGHT", -14, 12)
		on:SetScript("OnClick", function()
			local k = previewDlg.styleKey
			previewDlg:Hide()
			local picked = SP.TotemBarStyle and SP:TotemBarStyle(k)
			if picked and SP:SetTotemBarStyle(k) then   -- in combat it says so itself
				print("|cff0070ddShamanPower|r: " .. picked.label .. " is on. Settings > General > Totem Bar Style switches back; Mode & Twisting has its settings.")
				if ns.SPConfig and ns.SPConfig.Open then ns.SPConfig:Open({ "settings", "settings_totemMode" }) end
			end
		end)
		local notNow = Core:MakeButton(previewDlg, "Not now", 100, false)
		notNow:SetPoint("RIGHT", on, "LEFT", -8, 0)
		notNow:SetScript("OnClick", function() previewDlg:Hide() end)
	end
	previewDlg.styleKey = key
	previewDlg:SetTitles(st.label, "a preview with your current bar settings - nothing changes until you turn it on")
	previewDlg.cap:SetText(ns.StyleCaptions and ns.StyleCaptions[key] or "")

	-- Rebuild the mock on every open so it reflects the current settings.
	if previewDlg.host then previewDlg.host:Hide(); previewDlg.host:SetParent(nil) end
	local host = CreateFrame("Frame", nil, previewDlg.shot)
	host:SetPoint("TOPLEFT", previewDlg.shot, "TOPLEFT", 4, -4)
	host:SetPoint("BOTTOMRIGHT", previewDlg.shot, "BOTTOMRIGHT", -4, 4)
	host:SetClipsChildren(true)
	previewDlg.host = host

	local o = {}
	for k, v in pairs(SP.opt) do o[k] = v end   -- shallow copy; nested tables are only read
	SP:ApplyTotemBarStyleTo(o, key)
	SP.Wizard.optOverride = o
	SP.Wizard.previewOnly = true
	local dummyCard = CreateFrame("Frame", nil, host); dummyCard:SetSize(400, 10); dummyCard:Hide()
	local ok = pcall(SP.Wizard.BuildTotemBarStep, dummyCard, host, 0)
	if ok then
		-- the mock's own caption belongs to the tour page, not this card
		for _, r in ipairs({ host:GetRegions() }) do
			if r.IsObjectType and r:IsObjectType("FontString") then r:Hide() end
		end
	else
		local t = host:CreateFontString(nil, "OVERLAY"); t:SetFontObject(Core.fonts.rowDim)
		t:SetPoint("CENTER"); t:SetText("Could not build the preview.")
	end
	previewDlg:Show()
end

-- ---------------------------------------------------------------------------
-- The card
-- ---------------------------------------------------------------------------
local dlg
local function BuildDialog()
	if dlg then return dlg end
	dlg = Core:CreateDialog({
		name = "ShamanPowerWhatsNew", width = 560, height = 200,
		title = "What's new in ShamanPower " .. NOTES.version,
		subtitle = "shown once per update", headerHeight = 46, footer = 52, special = true,
	})
	dlg:SetFrameStrata("DIALOG")
	local solid = dlg:CreateTexture(nil, "BACKGROUND", nil, 1)
	solid:SetPoint("TOPLEFT", 2, -2); solid:SetPoint("BOTTOMRIGHT", -2, 2)
	solid:SetColorTexture(Core:Color("windowBg", 1))

	local W, y = 526, 2
	local isShaman = select(2, UnitClass("player")) == "SHAMAN"
	for _, it in ipairs(NOTES.items) do
	  if not it.when or it.when() then   -- an item for a feature this client lacks stays out
		-- a totem bar style gets its picture on the left and a Try it button on the right
		local tryIt = it.try and isShaman and SP.TotemBarStyle and SP:TotemBarStyle(it.try) ~= nil
		local x, w = 0, W
		if tryIt then
			if ns.DrawStyleThumb then
				local th = ns.DrawStyleThumb(dlg.body, it.try, 72, 34)
				th:SetPoint("TOPLEFT", dlg.body, "TOPLEFT", 0, -y)
				x = 84
			end
			local tb = Core:MakeButton(dlg.body, "Try it", 80, false)
			tb:SetPoint("TOPRIGHT", dlg.body, "TOPRIGHT", 0, -(y + 2))
			local key = it.try
			tb:SetScript("OnClick", function() ShowStylePreview(key) end)
			w = W - x - 92
		end
		local h = dlg.body:CreateFontString(nil, "OVERLAY"); h:SetFontObject(Core.fonts.row)
		h:SetPoint("TOPLEFT", dlg.body, "TOPLEFT", x, -y); h:SetWidth(w); h:SetJustifyH("LEFT")
		h:SetText(it.h); h:SetTextColor(Core:Color("accentHi"))
		y = y + h:GetStringHeight() + 4
		local b = dlg.body:CreateFontString(nil, "OVERLAY"); b:SetFontObject(Core.fonts.rowDim)
		b:SetPoint("TOPLEFT", dlg.body, "TOPLEFT", x, -y); b:SetWidth(w); b:SetJustifyH("LEFT"); b:SetWordWrap(true)
		b:SetText(it.b)
		y = y + b:GetStringHeight() + 14
	  end
	end
	if NOTES.footer then
		local f = dlg.body:CreateFontString(nil, "OVERLAY"); f:SetFontObject(Core.fonts.tiny)
		f:SetPoint("TOPLEFT", dlg.body, "TOPLEFT", 0, -y); f:SetWidth(W); f:SetJustifyH("LEFT"); f:SetWordWrap(true)
		f:SetText(NOTES.footer)
		y = y + f:GetStringHeight()
	end
	dlg:SetHeight(46 + 16 + y + 52)

	local ok = Core:MakeButton(dlg, "Got it", 120, true)
	ok:SetPoint("BOTTOMRIGHT", dlg, "BOTTOMRIGHT", -14, 12)
	ok:SetScript("OnClick", function() dlg:Hide() end)
	if dlg.close then dlg.close:SetScript("OnClick", function() ok:Click() end) end
	return dlg
end

-- force = true (the /spwhatsnew test command) bypasses the version gate and
-- never stamps anything. "/spwhatsnew preview <style>" opens a style preview.
function SP:ShowWhatsNew(force)
	if force then BuildDialog():Show() return end
	local cur = GetAddOnMetadata and GetAddOnMetadata("ShamanPower", "Version")
	local g = self.db and self.db.global
	if not cur or not g then return end
	if g.lastSeenVersion == cur then return end
	-- Brand-new installs are in (or headed into) the guided setup - stamp and
	-- stay quiet rather than stacking two windows.
	if self.opt and not self.opt.setupDone then g.lastSeenVersion = cur return end
	-- A release without notes for itself stays quiet too.
	if BaseVersion(cur) ~= NOTES.version then g.lastSeenVersion = cur return end
	-- Never on top of the setup wizard; try again next login instead.
	local wiz = _G["ShamanPowerWizard"]
	if wiz and wiz:IsShown() then return end
	if InCombatLockdown() then C_Timer.After(15, function() SP:ShowWhatsNew() end) return end
	g.lastSeenVersion = cur
	BuildDialog():Show()
end

SLASH_SPWHATSNEW1 = "/spwhatsnew"
SlashCmdList["SPWHATSNEW"] = function(msg)
	local m = strtrim(msg or ""):lower()
	if m == "preview" then ShowStylePreview("grid") return end
	local key = m:match("^preview%s+(%S+)$")
	if key then ShowStylePreview(key) return end
	SP:ShowWhatsNew(true)
end

local ef = CreateFrame("Frame")
ef:RegisterEvent("PLAYER_ENTERING_WORLD")
ef:SetScript("OnEvent", function(self)
	self:UnregisterAllEvents()
	C_Timer.After(4, function() SP:ShowWhatsNew() end)
end)
