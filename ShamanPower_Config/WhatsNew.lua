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
	version = "2.1.0",
	items = {
		{ h = "Compact style: your totem bar as lines",
		  b = "A fourth look for the totem bar. No icons: each element is a colored line that drains as the totem runs down and refills with every pulse. Tiny icon squares are optional, clicks and flyouts work exactly as before, and your Lightning / Water Shield and Earth Shield can sit at either end of the bar as charge lines. Stacked or side by side, any length and thickness."
		    .. "\n|cff3FA9F5Settings > Mode & Twisting > Compact Style|r  -  or press |cffFFD100Preview the Compact style|r below" },
		{ h = "Only the elements you have learned",
		  b = "A new shaman's bar now grows with them: nothing before the Earth quest, then Fire, Water and Air appear as each totem is learned, and the bar stays centered on screen while it grows. On by default; existing characters with all four totems see no change."
		    .. "\n|cff3FA9F5Settings > Totem Bar > Items > Only Show Learned Elements|r" },
	},
	footer = "Plus the 2.0.5 - 2.0.7 fixes: pop-out trackers stay where you put them and can be locked together, Earth Shield tracking survives a /reload, and Earth Shield fade alerts fire again. The full list is in the changelog.",
	preview = true,   -- show the Compact preview button
}

local function BaseVersion(v)
	return v and (v:gsub("%-.*$", "")) or nil
end

-- ---------------------------------------------------------------------------
-- Compact preview: the setup tour's own Totem Bar mock, drawn with the
-- player's current bar settings plus compactStyle = true, in read-only
-- preview mode. Nothing changes unless "Turn it on" is pressed.
-- ---------------------------------------------------------------------------
local previewDlg
local function ShowCompactPreview()
	if not (SP.Wizard and SP.Wizard.BuildTotemBarStep and SP.CreateCompactVisuals) then
		print("|cff0070ddShamanPower|r: the Compact preview needs the setup tour module, which is not loaded.")
		return
	end
	if not previewDlg then
		previewDlg = Core:CreateDialog({
			name = "ShamanPowerCompactPreview", width = 560, height = 372,
			title = "Compact style", subtitle = "a preview with your current bar settings - nothing changes until you turn it on",
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
		cap:SetText("Each line is one element. The outline drains as the totem runs down; the pulse refills inside the line; a grey line is an empty slot with its assigned totem ghosted in the square. Line length, thickness, orientation, outline and the shield lines are all yours to tune once it is on.")

		-- spOnHide keeps the dialog shell's own OnHide (popup cleanup) intact
		previewDlg.spOnHide = function(self)
			SP.Wizard.optOverride = nil
			SP.Wizard.previewOnly = nil
			if self.host then self.host:Hide() end
		end

		local on = Core:MakeButton(previewDlg, "Turn it on", 150, true)
		on:SetPoint("BOTTOMRIGHT", previewDlg, "BOTTOMRIGHT", -14, 12)
		on:SetScript("OnClick", function()
			previewDlg:Hide()
			if InCombatLockdown() then
				print("|cff0070ddShamanPower|r: the totem bar style cannot change during combat - try again after the fight.")
				return
			end
			SP.opt.compactStyle = true
			SP.opt.dynamicTotemMode = false
			SP.opt.activeTotemAsMain = false
			if SP.ApplyCompactStyle then SP:ApplyCompactStyle() end
			print("|cff0070ddShamanPower|r: Compact style is on. Settings > Mode & Twisting > Compact Style tunes it or switches back.")
			if ns.SPConfig and ns.SPConfig.Open then ns.SPConfig:Open({ "settings", "settings_totemMode" }) end
		end)
		local notNow = Core:MakeButton(previewDlg, "Not now", 100, false)
		notNow:SetPoint("RIGHT", on, "LEFT", -8, 0)
		notNow:SetScript("OnClick", function() previewDlg:Hide() end)
	end

	-- Rebuild the mock on every open so it reflects the current settings.
	if previewDlg.host then previewDlg.host:Hide(); previewDlg.host:SetParent(nil) end
	local host = CreateFrame("Frame", nil, previewDlg.shot)
	host:SetPoint("TOPLEFT", previewDlg.shot, "TOPLEFT", 4, -4)
	host:SetPoint("BOTTOMRIGHT", previewDlg.shot, "BOTTOMRIGHT", -4, 4)
	host:SetClipsChildren(true)
	previewDlg.host = host

	local o = {}
	for k, v in pairs(SP.opt) do o[k] = v end   -- shallow copy; nested tables are only read
	o.compactStyle, o.dynamicTotemMode, o.activeTotemAsMain = true, false, false
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
	for _, it in ipairs(NOTES.items) do
		local h = dlg.body:CreateFontString(nil, "OVERLAY"); h:SetFontObject(Core.fonts.row)
		h:SetPoint("TOPLEFT", dlg.body, "TOPLEFT", 0, -y); h:SetWidth(W); h:SetJustifyH("LEFT")
		h:SetText(it.h); h:SetTextColor(Core:Color("accentHi"))
		y = y + h:GetStringHeight() + 4
		local b = dlg.body:CreateFontString(nil, "OVERLAY"); b:SetFontObject(Core.fonts.rowDim)
		b:SetPoint("TOPLEFT", dlg.body, "TOPLEFT", 0, -y); b:SetWidth(W); b:SetJustifyH("LEFT"); b:SetWordWrap(true)
		b:SetText(it.b)
		y = y + b:GetStringHeight() + 14
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
	if NOTES.preview then
		local pv = Core:MakeButton(dlg, "Preview the Compact style", 200, false)
		pv:SetPoint("BOTTOMLEFT", dlg, "BOTTOMLEFT", 14, 12)
		pv:SetScript("OnClick", function() ShowCompactPreview() end)
		-- already on Compact: the preview is what they are looking at
		dlg:HookScript("OnShow", function() pv:SetShown(not (SP.opt and SP.opt.compactStyle)) end)
	end
	return dlg
end

-- force = true (the /spwhatsnew test command) bypasses the version gate and
-- never stamps anything.
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
	if strtrim(msg or ""):lower() == "preview" then ShowCompactPreview() return end
	SP:ShowWhatsNew(true)
end

local ef = CreateFrame("Frame")
ef:RegisterEvent("PLAYER_ENTERING_WORLD")
ef:SetScript("OnEvent", function(self)
	self:UnregisterAllEvents()
	C_Timer.After(4, function() SP:ShowWhatsNew() end)
end)
