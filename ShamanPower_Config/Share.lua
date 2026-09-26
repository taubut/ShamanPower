-- ShamanPower_Config :: Share
-- Export/import dialogs on the dialog kit, and Export/Import buttons injected
-- into the Profiles options page. The serialize logic lives in the engine
-- (ShamanPowerShare.lua); this is only the UI.

local ADDON, ns = ...
local Core = ns.Core
local SP = ShamanPower
if not SP or not Core then return end

-- The string box of both dialogs scrolls with the wheel and our own scroll bar.
-- A shorter string (or deleted text) pulls the view back inside the text.
-- Core:AttachScrollbar hooks these scripts, so it is attached after them.
local BOX_W = 460 - 2 * 14 - 10   -- the dialog's body, less the scroll bar beside the box
local function ScrollBox(scroll, edit)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScrollRange(), self:GetVerticalScroll() - delta * 40)))
	end)
	scroll:SetScript("OnScrollRangeChanged", function(self)
		if self:GetVerticalScroll() > self:GetVerticalScrollRange() then self:SetVerticalScroll(self:GetVerticalScrollRange()) end
	end)
	Core:AttachScrollbar(scroll, edit)
end

-- ---------------------------------------------------------------------------
-- Export dialog: a read-only, pre-selected multiline box.
-- ---------------------------------------------------------------------------
local exportDlg
function SP:ShowExportDialog(str, title, heading)
	if not str then
		print("|cff0070ddShamanPower|r: nothing to export.")
		return
	end
	if not exportDlg then
		exportDlg = Core:CreateDialog({
			name = "ShamanPowerExportDialog", width = 460, height = 300,
			title = "Export", subtitle = "copy this string", headerHeight = 46, footer = 44,
			special = true, strata = "FULLSCREEN_DIALOG",
		})

		local hint = exportDlg.body:CreateFontString(nil, "OVERLAY")
		hint:SetFontObject(Core.fonts.rowDim)
		hint:SetPoint("TOPLEFT", exportDlg.body, "TOPLEFT", 0, 0)
		hint:SetPoint("RIGHT", exportDlg.body, "RIGHT", 0, 0)
		hint:SetJustifyH("LEFT")
		hint:SetText("Press Ctrl+C to copy, then paste it wherever you like.")

		local scroll = CreateFrame("ScrollFrame", nil, exportDlg.body)
		scroll:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -8)
		scroll:SetPoint("BOTTOMRIGHT", exportDlg.body, "BOTTOMRIGHT", -10, 0)
		Core:SolidTex(scroll, "windowBg", "BACKGROUND")
		Core:MakeBorder(scroll, "border")
		local edit = CreateFrame("EditBox", nil, scroll)
		edit:SetMultiLine(true)
		edit:SetFontObject(Core.fonts.row)
		edit:SetWidth(BOX_W)
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
		ScrollBox(scroll, edit)
		exportDlg.edit, exportDlg.scroll = edit, scroll

		local sel = Core:MakeButton(exportDlg, "Select All", 100, true)
		sel:SetPoint("BOTTOMRIGHT", exportDlg, "BOTTOMRIGHT", -14, 12)
		sel:SetScript("OnClick", function() edit:SetFocus(); edit:HighlightText() end)
	end

	exportDlg:SetTitles(heading or "Export", title and title or "copy this string")
	exportDlg.edit.spText = str
	exportDlg.edit:SetText(str)
	-- Size the dialog to the content: a link or short string gets a one-line
	-- box; long strings (profiles, WeakAuras) keep the big scrolling box.
	local short = #str <= 80 and not str:find("\n")
	exportDlg:SetHeight(short and 168 or 300)   -- the scroll bar hides itself when the string fits
	exportDlg.scroll:SetVerticalScroll(0)
	exportDlg:Show()
	exportDlg.edit:SetFocus()
	exportDlg.edit:HighlightText()
end

-- ---------------------------------------------------------------------------
-- Import dialog: paste box, optional profile name, Import button.
-- ---------------------------------------------------------------------------
local importDlg
local IMPORT_H = 320
function SP:ShowImportDialog()
	if not importDlg then
		importDlg = Core:CreateDialog({
			name = "ShamanPowerImportDialog", width = 460, height = IMPORT_H,
			title = "Import", subtitle = "paste a string", headerHeight = 46, footer = 44,
			special = true, strata = "FULLSCREEN_DIALOG",
		})

		local hint = importDlg.body:CreateFontString(nil, "OVERLAY")
		hint:SetFontObject(Core.fonts.rowDim)
		hint:SetPoint("TOPLEFT", importDlg.body, "TOPLEFT", 0, 0)
		hint:SetPoint("RIGHT", importDlg.body, "RIGHT", 0, 0)
		hint:SetJustifyH("LEFT")
		hint:SetText("Paste a ShamanPower string, name the new profile, then Import.")

		local scroll = CreateFrame("ScrollFrame", nil, importDlg.body)
		scroll:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -8)
		scroll:SetPoint("BOTTOMRIGHT", importDlg.body, "BOTTOMRIGHT", -10, 30)
		Core:SolidTex(scroll, "windowBg", "BACKGROUND")
		Core:MakeBorder(scroll, "border")
		local edit = CreateFrame("EditBox", nil, scroll)
		edit:SetMultiLine(true)
		edit:SetFontObject(Core.fonts.row)
		edit:SetWidth(BOX_W)
		edit:SetAutoFocus(false)
		edit:SetTextInsets(6, 6, 6, 6)
		edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
		scroll:SetScrollChild(edit)
		ScrollBox(scroll, edit)
		importDlg.edit, importDlg.scroll = edit, scroll

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
		nameBox:SetScript("OnEditFocusGained", function() Core:SetBorderColor(nameBox, "accent") end)
		nameBox:SetScript("OnEditFocusLost", function() Core:SetBorderColor(nameBox, "border") end)
		nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
		importDlg.nameBox = nameBox

		local status = importDlg.body:CreateFontString(nil, "OVERLAY")
		status:SetFontObject(Core.fonts.tiny)
		importDlg.status = status

		local go = Core:MakeButton(importDlg, "Import", 100, true)
		go:SetPoint("BOTTOMRIGHT", importDlg, "BOTTOMRIGHT", -14, 12)
		go:SetScript("OnClick", function()
			local ok, res = SP:ImportShare(edit:GetText(), "newProfile", nameBox:GetText())
			if ok then
				importDlg:SetStatus("Imported into profile: " .. res, "on")
				C_Timer.After(1.2, function() importDlg:Hide() end)
			else
				importDlg:SetStatus("Import failed: " .. tostring(res), "warn")
			end
		end)
		local cancel = Core:MakeButton(importDlg, "Cancel", 100, false)
		cancel:SetPoint("RIGHT", go, "LEFT", -8, 0)
		cancel:SetScript("OnClick", function() importDlg:Hide() end)
		-- the status line sits left of the buttons and wraps in the room they leave,
		-- up to 4px under the body, where the name row starts. One too tall for that
		-- (a long profile name) lifts the name row and the string box by the
		-- difference, and the dialog grows by as much.
		status:SetPoint("BOTTOMLEFT", importDlg, "BOTTOMLEFT", 14, 16)
		status:SetWidth(importDlg:GetWidth() - 14 - go:GetWidth() - 8 - cancel:GetWidth() - 12 - 14)
		status:SetJustifyH("LEFT"); status:SetWordWrap(true)
		local room = 44 + importDlg.pad - 4 - 16   -- the body's bottom (footer 44 + pad), 4px clear, above y 16
		function importDlg:SetStatus(text, key)
			if key then status:SetTextColor(Core:Color(key)) end
			status:SetText(text)
			local lift = math.max(0, math.ceil(status:GetStringHeight()) - room)
			nameLabel:SetPoint("BOTTOMLEFT", self.body, "BOTTOMLEFT", 0, 6 + lift)
			scroll:SetPoint("BOTTOMRIGHT", self.body, "BOTTOMRIGHT", -10, 30 + lift)
			self:SetHeight(IMPORT_H + lift)
		end
	end

	importDlg.edit:SetText("")
	importDlg.scroll:SetVerticalScroll(0)
	importDlg.nameBox:SetText("Imported")
	importDlg:SetStatus("")
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
	-- Built-in layouts: the same preview-then-apply dialog the setup uses.
	if SP.Presets and SP.Presets[1] then
		profiles.args.spPresetHeader = { order = 0.4, type = "header", name = "Built-in Layouts" }
		profiles.args.spPresetDesc = {
			order = 0.45, type = "description", fontSize = "medium",
			name = "A complete, ready-made setup - bars, scales, colors, positions and every module tuned. You get to see it before anything is applied; your totem choices and raid assignments are never touched.",
		}
		profiles.args.spRestoreBackup = {
			order = 0.9, type = "execute", name = "Restore My Previous Setup",
			desc = function()
				local b = SP.db.global.setupBackups and SP.db.global.setupBackups[1]
				return b and ("Backed up " .. b.date .. " (" .. b.reason .. "). Comes back as a new profile; your current profile is kept.") or ""
			end,
			hidden = function() return not (SP.db.global.setupBackups and SP.db.global.setupBackups[1]) end,
			func = function() SP:RestoreSetupBackup(1) end,
		}
		for i, preset in ipairs(SP.Presets) do
			profiles.args["spPreset" .. i] = {
				order = 0.5 + i * 0.01, type = "execute", name = "Preview " .. preset.name,
				desc = preset.desc,
				func = function()
					if SP.Wizard and SP.Wizard.ShowPresetPreview then
						SP.Wizard:ShowPresetPreview(preset, { fromSettings = true })
					else
						SP:ApplyPreset(preset.key, "overwrite"); Core:RequestReload("Preset applied.")
					end
				end,
			}
		end
	end
end
InjectProfileButtons()

-- ---------------------------------------------------------------------------
-- Windfury Companion: its own page in Settings so a shaman can hand the
-- WeakAura to a melee again any time.
function SP:ShowWindfuryCompanion(link)
	local comp = self.Companions and self.Companions.windfury
	if not comp then print("|cff0070ddShamanPower|r: companion data missing.") return end
	if link then
		self:ShowExportDialog(comp.url, "send this link to your melee", "Windfury Companion")
	else
		self:ShowExportDialog(comp.str, "send this to your melee - they import it in WeakAuras", "Windfury Companion")
	end
end

local function InjectCompanionPage()
	-- WeakAuras is not a thing on Mainline-family clients (retail, WoW: Forever): no page there
	if WOW_PROJECT_ID == WOW_PROJECT_MAINLINE then return end
	local root = SP.options
	if not (root and root.args) or root.args.spWindfuryCompanion then return end
	root.args.spWindfuryCompanion = {
		order = 96, type = "group", name = "Windfury Companion",
		args = {
			warn = {
				order = 1, type = "description", fontSize = "large",
				name = "|cffFFB000THIS IS FOR YOUR MELEE - NOT FOR YOU|r",
			},
			desc = {
				order = 2, type = "description", fontSize = "medium",
				name = "The game never shows Windfury Totem's weapon buff on other players, so ShamanPower cannot see who has it. "
					.. "This small WeakAura, installed by the |cffE6EAF0rogues, warriors and paladins|r in your group, quietly tells your addon they have Windfury. "
					.. "Your Air slot then counts them and shows a dot for each one, yellow when they are in range of your totem.\n\n"
					.. "You do |cffE6EAF0not|r install it. Send it to your melee; they import it into WeakAuras once and never touch it again.",
			},
			str = {
				order = 3, type = "execute", name = "Show WeakAura String",
				desc = "Opens the import string so you can copy it and send it to a melee.",
				func = function() SP:ShowWindfuryCompanion(false) end,
			},
			link = {
				order = 4, type = "execute", name = "Show wago.io Link",
				desc = "Opens the wago.io link for the companion aura.",
				func = function() SP:ShowWindfuryCompanion(true) end,
			},
		},
	}
end
InjectCompanionPage()

return true
