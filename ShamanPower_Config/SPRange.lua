-- ShamanPower_Config :: SPRange
-- The "Totem Range – click totems to track" window, rebuilt on the dialog
-- chrome. Tracking state, the overlay and the button painter
-- (UpdateSPRangeConfigButtons) stay in ShamanPower_SPRange; this file only
-- replaces the window and hands the module the same `totemButtons` table it
-- already paints.

local ADDON, ns = ...
local Core = ns.Core

local SP = ShamanPower
if not SP or not SP.TrackableTotems or not SP.UpdateSPRangeConfigButtons then return end

local ELEMENTS = {
	{ label = "Earth", r = 0.72, g = 0.52, b = 0.32 },
	{ label = "Fire",  r = 1.00, g = 0.36, b = 0.22 },
	{ label = "Water", r = 0.42, g = 0.58, b = 1.00 },
	{ label = "Air",   r = 0.86, g = 0.88, b = 0.98 },
}

local COL_W, COL_GAP = 78, 8
local ICON     = 40
local ROW_H    = ICON + 18
local COLHEAD  = 24
local HEADER_H = 46
local FOOTER_H = 48

local dlg

local function ShortName(t)
	return SP.TrackableTotemShortNames[t.id] or (t.name and t.name:gsub(" Totem", "")) or ""
end

local function Build()
	if dlg then return dlg end

	local byElement = { {}, {}, {}, {} }
	for _, t in ipairs(SP.TrackableTotems) do
		table.insert(byElement[t.element], t)
	end
	local maxRows = 0
	for e = 1, 4 do if #byElement[e] > maxRows then maxRows = #byElement[e] end end

	local pad = 14
	local width = pad * 2 + 4 * COL_W + 3 * COL_GAP
	local height = HEADER_H + 4 + 8 + COLHEAD + maxRows * ROW_H + 10 + FOOTER_H + pad

	dlg = Core:CreateDialog({
		name = "ShamanPowerRangeConfigFrame",
		width = width, height = height,
		title = "Totem Range", subtitle = "click totems to track",
		headerHeight = HEADER_H, bodyTop = 8, footer = FOOTER_H, pad = pad,
	})
	dlg:SetFrameStrata("DIALOG")
	dlg.totemButtons = {}

	for e = 1, 4 do
		local el = ELEMENTS[e]
		local col = CreateFrame("Frame", nil, dlg.body)
		col:SetSize(COL_W, COLHEAD + #byElement[e] * ROW_H + 6)
		col:SetPoint("TOPLEFT", dlg.body, "TOPLEFT", (e - 1) * (COL_W + COL_GAP), 0)
		local bg = col:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints(col)
		bg:SetColorTexture(el.r, el.g, el.b, 0.10)
		Core:MakeBorder(col, "borderSoft")

		local head = col:CreateFontString(nil, "OVERLAY")
		head:SetFontObject(Core.fonts.section)
		head:SetPoint("TOP", col, "TOP", 0, -7)
		head:SetText(strupper(el.label))
		head:SetTextColor(el.r, el.g, el.b)

		for i, t in ipairs(byElement[e]) do
			local btn = CreateFrame("Button", nil, col)
			btn:SetSize(ICON, ICON)
			btn:SetPoint("TOP", col, "TOP", 0, -COLHEAD - (i - 1) * ROW_H)

			local icon = btn:CreateTexture(nil, "ARTWORK")
			icon:SetAllPoints(btn)
			icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
			local _, _, spellIcon = GetSpellInfo(t.spellID)
			icon:SetTexture(spellIcon)
			Core:MakeBorder(btn, "borderSoft")

			local name = btn:CreateFontString(nil, "OVERLAY")
			name:SetFontObject(Core.fonts.tiny)
			name:SetPoint("TOP", btn, "BOTTOM", 0, -2)
			name:SetWidth(COL_W - 6)
			name:SetJustifyH("CENTER")
			name:SetText(ShortName(t))

			-- Fields the module's painter expects.
			btn.icon, btn.nameText, btn.totemData = icon, name, t
			btn.elementColors = { r = el.r, g = el.g, b = el.b }

			btn:SetScript("OnClick", function(self)
				local id = self.totemData.id
				ShamanPower_RangeTracker.tracked[id] = not ShamanPower_RangeTracker.tracked[id]
				SP:UpdateSPRangeConfigButtons()
				SP:UpdateSPRangeFrame()
			end)
			btn:SetScript("OnEnter", function(self)
				for _, tex in pairs(self.spBorder) do tex:SetColorTexture(el.r, el.g, el.b, 0.9) end
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:AddLine(self.totemData.name, 1, 1, 1)
				if ShamanPower_RangeTracker.tracked[self.totemData.id] then
					GameTooltip:AddLine("Currently tracking", 0.18, 0.8, 0.44)
					GameTooltip:AddLine("Click to stop tracking", 0.7, 0.7, 0.7)
				else
					GameTooltip:AddLine("Not tracking", 0.5, 0.5, 0.5)
					GameTooltip:AddLine("Click to track", 0.7, 0.7, 0.7)
				end
				GameTooltip:Show()
			end)
			btn:SetScript("OnLeave", function(self)
				Core:SetBorderColor(self, "borderSoft")
				GameTooltip:Hide()
			end)

			dlg.totemButtons[t.id] = btn
		end
	end

	-- Footer: overlay toggle
	local rule = dlg:CreateTexture(nil, "ARTWORK")
	rule:SetHeight(1)
	rule:SetPoint("BOTTOMLEFT", dlg, "BOTTOMLEFT", 2, FOOTER_H)
	rule:SetPoint("BOTTOMRIGHT", dlg, "BOTTOMRIGHT", -2, FOOTER_H)
	rule:SetColorTexture(Core:Color("border"))

	local toggle = Core:MakeButton(dlg, "Show Overlay", 130, true)
	toggle:SetPoint("BOTTOMLEFT", dlg, "BOTTOMLEFT", pad, 11)
	local function PaintToggle()
		local shown = SP.spRangeFrame and SP.spRangeFrame:IsShown()
		toggle.text:SetText(shown and "Hide Overlay" or "Show Overlay")
	end
	toggle:SetScript("OnClick", function()
		SP:ToggleSPRange()
		PaintToggle()
	end)
	Core:AttachTooltip(toggle, "Overlay", "Show or hide the on-screen range overlay for the tracked totems.")
	dlg.updateToggleBtnText = PaintToggle
	dlg.spOnShow = PaintToggle

	local hint = dlg:CreateFontString(nil, "OVERLAY")
	hint:SetFontObject(Core.fonts.tiny)
	hint:SetPoint("LEFT", toggle, "RIGHT", 12, 0)
	hint:SetText("Greyed totems are not tracked")
	hint:SetTextColor(Core:Color("textMute"))

	SP.spRangeConfigFrame = dlg
	return dlg
end

function SP:ShowSPRangeConfig()
	Build()
	self:UpdateSPRangeConfigButtons()
	dlg:Show()
end

-- Settings panel for the on-screen overlay (its corner button).
local FS = ns.FrameSettings
if FS then
	local function RT()
		SP.opt.rangeTracker = SP.opt.rangeTracker or {}
		return SP.opt.rangeTracker
	end
	local function Notify()
		local reg = LibStub and LibStub("AceConfigRegistry-3.0", true)
		if reg then reg:NotifyChange("ShamanPower") end
	end
	FS.specs.sprange = function(frame)
		return {
			key = "sprange", title = "Totem Range", subtitle = "overlay",
			opacity = {
				min = 20, max = 100,
				get = function() return math.floor((RT().opacity or 1) * 100 + 0.5) end,
				set = function(v) RT().opacity = v / 100; SP:UpdateSPRangeOpacity(); Notify() end,
			},
			hideFrame = {
				get = function() return RT().hideBorder and true or false end,
				set = function(v) RT().hideBorder = v and true or false; SP:UpdateSPRangeBorder(); Notify() end,
			},
			rows = function(Row)
				Row("Slider", {
					label = "Icon Size", desc = "Size of the totem icons on the overlay.",
					min = 20, max = 60, step = 4,
					get = function() return RT().iconSize or 36 end,
					set = function(v) RT().iconSize = v; SP:UpdateSPRangeFrame(); Notify() end,
				})
				Row("Toggle", {
					label = "Hide Names", desc = "Show only the icons, without totem names.",
					get = function() return RT().hideNames and true or false end,
					set = function(v) RT().hideNames = v and true or false; SP:UpdateSPRangeFrame(); Notify() end,
				})
				Row("Toggle", {
					label = "Vertical Layout", desc = "Stack the icons vertically instead of in a row.",
					get = function() return RT().vertical and true or false end,
					set = function(v) RT().vertical = v and true or false; SP:UpdateSPRangeFrame(); SP:UpdateSPRangeBorder(); Notify() end,
				})
			end,
			actions = {
				{ text = "Choose Totems", desc = "Pick which totems the overlay tracks.",
				  func = function() FS:Hide(); SP:ShowSPRangeConfig() end },
			},
		}
	end
end

return true
