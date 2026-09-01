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
local NOTES = {
	version = "2.0.4",
	items = {
		{ h = "Earth Shield flyout filter",
		  b = "The Earth Shield flyout can now show only the players you would actually shield. Pick group roles (Tanks / Healers / Damage - raid Main Tanks count as Tanks), pick classes, or both; picks combine, nothing picked shows everyone, and your assigned target always shows."
		    .. "\n|cff3FA9F5Settings > Totem Bar > Flyouts > Earth Shield Flyout Filter|r" },
		{ h = "Flyouts know where they are on screen",
		  b = "With the flyout direction on |cffFFD100Auto|r, the totem bar and Earth Shield flyouts open away from the screen edge: downward when your bar sits near the top of the screen, upward when it sits near the bottom. You can still force |cffFFD100Above|r or |cffFFD100Below|r."
		    .. "\n|cff3FA9F5Settings > Totem Bar > Flyouts > Totem Flyout Direction|r" },
	},
	footer = "Plus a batch of Earth Shield flyout and totem flyout fixes - the full list is in the changelog.",
}

local dlg
local function BuildDialog()
	if dlg then return dlg end
	dlg = Core:CreateDialog({
		name = "ShamanPowerWhatsNew", width = 540, height = 200,
		title = "What's new in ShamanPower " .. NOTES.version,
		subtitle = "shown once per update", headerHeight = 46, footer = 52, special = true,
	})
	dlg:SetFrameStrata("DIALOG")
	local solid = dlg:CreateTexture(nil, "BACKGROUND", nil, 1)
	solid:SetPoint("TOPLEFT", 2, -2); solid:SetPoint("BOTTOMRIGHT", -2, 2)
	solid:SetColorTexture(Core:Color("windowBg", 1))

	local W, y = 506, 2
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
	if cur ~= NOTES.version then g.lastSeenVersion = cur return end
	-- Never on top of the setup wizard; try again next login instead.
	local wiz = _G["ShamanPowerWizard"]
	if wiz and wiz:IsShown() then return end
	if InCombatLockdown() then C_Timer.After(15, function() SP:ShowWhatsNew() end) return end
	g.lastSeenVersion = cur
	BuildDialog():Show()
end

SLASH_SPWHATSNEW1 = "/spwhatsnew"
SlashCmdList["SPWHATSNEW"] = function() SP:ShowWhatsNew(true) end

local ef = CreateFrame("Frame")
ef:RegisterEvent("PLAYER_ENTERING_WORLD")
ef:SetScript("OnEvent", function(self)
	self:UnregisterAllEvents()
	C_Timer.After(4, function() SP:ShowWhatsNew() end)
end)
