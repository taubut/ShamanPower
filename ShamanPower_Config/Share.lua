-- ShamanPower_Config :: Share
-- Export/import dialogs on the dialog kit, and Export/Import buttons injected
-- into the Profiles options page. The serialize logic lives in the engine
-- (ShamanPowerShare.lua); this is only the UI.

local ADDON, ns = ...
local Core = ns.Core
local SP = ShamanPower
if not SP or not Core then return end

-- ---------------------------------------------------------------------------
-- Export dialog: a read-only, pre-selected multiline box.
-- ---------------------------------------------------------------------------
local exportDlg
function SP:ShowExportDialog(str, title)
	if not str then
		print("|cff0070ddShamanPower|r: nothing to export.")
		return
	end
	if not exportDlg then
		exportDlg = Core:CreateDialog({
			name = "ShamanPowerExportDialog", width = 460, height = 300,
			title = "Export", subtitle = "copy this string", headerHeight = 46, footer = 44,
		})
		exportDlg:SetFrameStrata("FULLSCREEN_DIALOG")

		local hint = exportDlg.body:CreateFontString(nil, "OVERLAY")
		hint:SetFontObject(Core.fonts.rowDim)
		hint:SetPoint("TOPLEFT", exportDlg.body, "TOPLEFT", 0, 0)
		hint:SetPoint("RIGHT", exportDlg.body, "RIGHT", 0, 0)
		hint:SetJustifyH("LEFT")
		hint:SetText("Press Ctrl+C to copy, then paste it wherever you like.")

		local scroll = CreateFrame("ScrollFrame", "ShamanPowerExportScroll", exportDlg.body, "UIPanelScrollFrameTemplate")
		scroll:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -8)
		scroll:SetPoint("BOTTOMRIGHT", exportDlg.body, "BOTTOMRIGHT", -24, 0)
		Core:SolidTex(scroll, "windowBg", "BACKGROUND")
		Core:MakeBorder(scroll, "border")
		local edit = CreateFrame("EditBox", nil, scroll)
		edit:SetMultiLine(true)
		edit:SetFontObject(Core.fonts.row)
		edit:SetWidth(400)
		edit:SetAutoFocus(false)
		edit:SetTextInsets(6, 6, 6, 6)
		edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
		edit:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
		-- Read-only: revert any typing back to the export string.
		edit:SetScript("OnTextChanged", function(self, user)
			if user and self.spText and self:GetText() ~= self.spText then
				self:SetText(self.spText); self:HighlightText()
			end
		end)
		scroll:SetScrollChild(edit)
		exportDlg.edit = edit

		local sel = Core:MakeButton(exportDlg, "Select All", 100, true)
		sel:SetPoint("BOTTOMRIGHT", exportDlg, "BOTTOMRIGHT", -14, 12)
		sel:SetScript("OnClick", function() edit:SetFocus(); edit:HighlightText() end)
	end

	exportDlg:SetTitles("Export", title and title or "copy this string")
	exportDlg.edit.spText = str
	exportDlg.edit:SetText(str)
	exportDlg:Show()
	exportDlg.edit:SetFocus()
	exportDlg.edit:HighlightText()
end

-- ---------------------------------------------------------------------------
-- Import dialog: paste box, optional profile name, Import button.
-- ---------------------------------------------------------------------------
local importDlg
function SP:ShowImportDialog()
	if not importDlg then
		importDlg = Core:CreateDialog({
			name = "ShamanPowerImportDialog", width = 460, height = 320,
			title = "Import", subtitle = "paste a string", headerHeight = 46, footer = 44,
		})
		importDlg:SetFrameStrata("FULLSCREEN_DIALOG")

		local hint = importDlg.body:CreateFontString(nil, "OVERLAY")
		hint:SetFontObject(Core.fonts.rowDim)
		hint:SetPoint("TOPLEFT", importDlg.body, "TOPLEFT", 0, 0)
		hint:SetPoint("RIGHT", importDlg.body, "RIGHT", 0, 0)
		hint:SetJustifyH("LEFT")
		hint:SetText("Paste a ShamanPower string, name the new profile, then Import.")

		local scroll = CreateFrame("ScrollFrame", "ShamanPowerImportScroll", importDlg.body, "UIPanelScrollFrameTemplate")
		scroll:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -8)
		scroll:SetPoint("BOTTOMRIGHT", importDlg.body, "BOTTOMRIGHT", -24, 30)
		Core:SolidTex(scroll, "windowBg", "BACKGROUND")
		Core:MakeBorder(scroll, "border")
		local edit = CreateFrame("EditBox", nil, scroll)
		edit:SetMultiLine(true)
		edit:SetFontObject(Core.fonts.row)
		edit:SetWidth(400)
		edit:SetAutoFocus(false)
		edit:SetTextInsets(6, 6, 6, 6)
		edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
		scroll:SetScrollChild(edit)
		importDlg.edit = edit

		local nameLabel = importDlg.body:CreateFontString(nil, "OVERLAY")
		nameLabel:SetFontObject(Core.fonts.rowDim)
		nameLabel:SetPoint("BOTTOMLEFT", importDlg.body, "BOTTOMLEFT", 0, 6)
		nameLabel:SetText("Profile name:")
		local nameBox = CreateFrame("EditBox", nil, importDlg.body)
		nameBox:SetSize(180, 22)
		nameBox:SetPoint("LEFT", nameLabel, "RIGHT", 8, 0)
		nameBox:SetAutoFocus(false)
		nameBox:SetFontObject(Core.fonts.row)
		nameBox:SetTextInsets(6, 6, 0, 0)
		Core:SolidTex(nameBox, "windowBg", "BACKGROUND")
		Core:MakeBorder(nameBox, "border")
		nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
		importDlg.nameBox = nameBox

		local status = importDlg.body:CreateFontString(nil, "OVERLAY")
		status:SetFontObject(Core.fonts.tiny)
		status:SetPoint("BOTTOMLEFT", importDlg, "BOTTOMLEFT", 14, 16)
		importDlg.status = status

		local go = Core:MakeButton(importDlg, "Import", 100, true)
		go:SetPoint("BOTTOMRIGHT", importDlg, "BOTTOMRIGHT", -14, 12)
		go:SetScript("OnClick", function()
			local ok, res = SP:ImportShare(edit:GetText(), "newProfile", nameBox:GetText())
			if ok then
				status:SetTextColor(Core:Color("on"))
				status:SetText("Imported into profile: " .. res)
				C_Timer.After(1.2, function() importDlg:Hide() end)
			else
				status:SetTextColor(Core:Color("warn"))
				status:SetText("Import failed: " .. tostring(res))
			end
		end)
	end

	importDlg.edit:SetText("")
	importDlg.nameBox:SetText("Imported")
	importDlg.status:SetText("")
	importDlg:Show()
	importDlg.edit:SetFocus()
end

-- ---------------------------------------------------------------------------
-- Inject Export / Import into the Profiles options page.
-- ---------------------------------------------------------------------------
local function InjectProfileButtons()
	local root = SP.options
	local profiles = root and root.args and root.args.profiles
	if not (profiles and profiles.args) or profiles.args.spShareHeader then return end
	profiles.args.spShareHeader = { order = 0.1, type = "header", name = "Share" }
	profiles.args.spShareDesc = {
		order = 0.15, type = "description", fontSize = "medium",
		name = "|cffE6EAF0Export|r turns this profile into a copyable string you can back up or send to someone. |cffE6EAF0Import|r loads a string as a new profile, leaving your current one untouched.",
	}
	profiles.args.spExport = {
		order = 0.2, type = "execute", name = "Export This Profile",
		desc = "Copy this profile as a string you can back up or share.",
		func = function() SP:ShowExportDialog(SP:ExportCurrentProfile(), "copy this string") end,
	}
	profiles.args.spImport = {
		order = 0.3, type = "execute", name = "Import a String",
		desc = "Paste a ShamanPower string to load it as a new profile.",
		func = function() SP:ShowImportDialog() end,
	}
end
InjectProfileButtons()

return true
