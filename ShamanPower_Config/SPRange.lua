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
-- Theme looks (General > Themes, ShamanPowerTheme.lua), spot win.rangecfg: a
-- theme recolours these in place and puts today's numbers back on Standard;
-- an open window repaints below (ShowSPRangeConfig).
if SP.ThemeBind then
	for e = 1, 4 do SP:ThemeBind(ELEMENTS[e], "win.rangecfg", e) end
end

-- The window's own element (D32: Totem Range is a Group Tools window, so Water): the
-- header band's light, the title's underline and the content's light, and the
-- overlay panels' switches and sliders. The columns' tints above follow the
-- player's palette and stay as they are.
local ELEMENT = "water"

local COL_W, COL_GAP = 78, 8
local ICON     = 40
local ROW_H    = ICON + 18
local COLHEAD  = 24
local HEADER_H = 46
local FOOTER_H = 48

local dlg
local registry = _G.LibStub("AceConfigRegistry-3.0", true)
local function Notify()
	if registry then registry:NotifyChange("ShamanPower") end
end

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
		special = true, strata = "DIALOG",
		element = ELEMENT,
	})
	-- The content lit by the window's element, faintly, from its top left (the settings
	-- content's light, D32b: 11% of the element over the window's navy), under the columns
	local er, eg, eb = 0.400, 0.553, 0.949   -- #668DF2 without the brand kit
	if SP.BrandElementRGB then er, eg, eb = SP:BrandElementRGB(ELEMENT) end
	local wr, wg, wb = Core:Color("windowBg")
	local lit = Core:Light(dlg, width, height, 0.05, 0, 1)
	Core:RegisterFadeLight(lit, er * 0.11 + wr * 0.89, eg * 0.11 + wg * 0.89, eb * 0.11 + wb * 0.89)
	dlg.totemButtons = {}
	dlg.elementCols = {}   -- each column's tint and heading, for a theme repaint

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
		dlg.elementCols[e] = { bg = bg, head = head }

		for i, t in ipairs(byElement[e]) do
			local btn = CreateFrame("Button", nil, col)
			btn:SetSize(ICON, ICON)
			btn:SetPoint("TOP", col, "TOP", 0, -COLHEAD - (i - 1) * ROW_H)

			local icon = btn:CreateTexture(nil, "ARTWORK")
			icon:SetAllPoints(btn)
			icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
			icon:SetTexture(SP.TrackableTotemIcon and SP:TrackableTotemIcon(t) or GetSpellTexture(t.spellID))
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
				Notify()
			end)
			btn:SetScript("OnEnter", function(self)
				for _, tex in pairs(self.spBorder) do tex:SetColorTexture(el.r, el.g, el.b, 0.9) end
				local tip = Core:Tooltip()
				tip:SetOwner(self, "ANCHOR_CURSOR")
				tip:AddLine(self.totemData.name)
				if ShamanPower_RangeTracker.tracked[self.totemData.id] then
					tip:AddLine("Currently tracking", Core:Color("on"))
					tip:AddHint("Click to stop tracking")
				else
					tip:AddLine("Not tracking", Core:Color("textDim"))
					tip:AddHint("Click to track")
				end
				tip:Show()
			end)
			btn:SetScript("OnLeave", function(self)
				Core:SetBorderColor(self, "borderSoft")
				Core:Tooltip():Hide()
			end)

			dlg.totemButtons[t.id] = btn
		end
	end

	-- Footer: overlay toggle (its rule runs under the window's edge)
	local rule = dlg:CreateTexture(nil, "ARTWORK")
	rule:SetHeight(1)
	rule:SetPoint("BOTTOMLEFT", dlg, "BOTTOMLEFT", 0, FOOTER_H)
	rule:SetPoint("BOTTOMRIGHT", dlg, "BOTTOMRIGHT", 0, FOOTER_H)
	rule:SetColorTexture(Core:Color("border"))

	local toggle = Core:MakeButton(dlg, "Show Overlay", 130, true)
	toggle:SetPoint("BOTTOMRIGHT", dlg, "BOTTOMRIGHT", -pad, 12)
	local function PaintToggle()
		local shown = SP.SPRangeOverlayOn and SP:SPRangeOverlayOn()
		toggle.text:SetText(shown and "Hide Overlay" or "Show Overlay")
	end
	toggle:SetScript("OnClick", function()
		SP:ToggleSPRange()
		PaintToggle()
		Notify()
	end)
	Core:AttachTooltip(toggle, "Totem Range Tracker", "Show or hide the range tracker for your chosen totems.")
	dlg.updateToggleBtnText = PaintToggle
	dlg.spOnShow = PaintToggle

	local hint = dlg:CreateFontString(nil, "OVERLAY")
	hint:SetFontObject(Core.fonts.tiny)
	-- left of the button, level with its middle, wrapping in the room it leaves
	hint:SetPoint("LEFT", dlg, "BOTTOMLEFT", pad, 12 + 13)
	hint:SetPoint("RIGHT", toggle, "LEFT", -12, 0)
	hint:SetJustifyH("LEFT"); hint:SetWordWrap(true)
	hint:SetText("Grayed totems are not tracked")
	hint:SetTextColor(Core:Color("textMute"))

	SP.spRangeConfigFrame = dlg
	return dlg
end

function SP:ShowSPRangeConfig()
	Build()
	self:UpdateSPRangeConfigButtons()
	dlg:Show()
end

-- A theme change (General > Themes): the columns take the new element tints
-- (the hover border reads ELEMENTS live)
if SP.OnThemeChanged then
	SP:OnThemeChanged(function()
		if not (dlg and dlg.elementCols) then return end
		for e = 1, 4 do
			local el, c = ELEMENTS[e], dlg.elementCols[e]
			c.bg:SetColorTexture(el.r, el.g, el.b, 0.10)
			c.head:SetTextColor(el.r, el.g, el.b)
		end
		for _, btn in pairs(dlg.totemButtons) do
			local el, ec = ELEMENTS[btn.totemData.element], btn.elementColors
			if el and ec then ec.r, ec.g, ec.b = el.r, el.g, el.b end
		end
	end)
end

-- Settings panel for the on-screen overlay (its corner button).
local FS = ns.FrameSettings
if FS then
	local function RT()
		SP.opt.rangeTracker = SP.opt.rangeTracker or {}
		return SP.opt.rangeTracker
	end
	-- Totem Coverage: the shaman's own overlay (Party Range module), same chrome
	local function CO() SP.opt.coverage = SP.opt.coverage or {}; return SP.opt.coverage end
	FS.specs.coverage = function(frame)
		return {
			key = "coverage", title = "Totem Coverage", subtitle = "who is out of range",
			element = ELEMENT,   -- Party Buff Tracker: Group Tools
			opacity = {
				min = 20, max = 100,
				get = function() return math.floor((CO().opacity or 1) * 100 + 0.5) end,
				set = function(v) CO().opacity = v / 100; SP:UpdateCoverageOpacity(); Notify() end,
			},
			hideFrame = {
				get = function() return CO().hideBorder and true or false end,
				set = function(v) CO().hideBorder = v and true or false; SP:UpdateCoverageBorder(); Notify() end,
			},
			rows = function(Row)
				Row("Slider", {
					label = "Icon Size", desc = "Size of the totem icons.",
					min = 20, max = 60, step = 4,
					get = function() return CO().iconSize or 36 end,
					set = function(v) CO().iconSize = v; SP:UpdateCoverageLayout(); Notify() end,
				})
				Row("Slider", {
					label = "Text Size", desc = "Size of the party names under each totem.",
					min = 7, max = 14, step = 1,
					get = function() return CO().fontSize or 9 end,
					set = function(v) CO().fontSize = v; SP:UpdateCoverageLayout(); Notify() end,
				})
				Row("Toggle", {
					label = "Place Each Totem Freely",
					desc = "Move and resize each totem separately. Alt-drag it or use Move under Coverage > Position.",
					get = function() return CO().freeCells and true or false end,
					set = function(v) CO().freeCells = v and true or false; SP:UpdateCoverageLayout(); Notify() end,
				})
				if CO().freeCells and SP.CoverageWatchedCells then
					for _, cell in ipairs(SP:CoverageWatchedCells()) do
						local key = cell.cellKey
						Row("Slider", {
							label = cell.cellLabel .. " Icon Size", min = 20, max = 80, step = 4,
							get = function() local c = CO().cells and CO().cells[key]; return (c and c.iconSize) or CO().iconSize or 36 end,
							set = function(v) CO().cells = CO().cells or {}; CO().cells[key] = CO().cells[key] or {}; CO().cells[key].iconSize = v; SP:UpdateCoverageLayout(); Notify() end,
						})
					end
				end
				Row("Toggle", {
					label = "Vertical Layout", desc = "Stack the totems in a column. Only applies when they are not placed freely.",
					get = function() return CO().vertical and true or false end,
					set = function(v) CO().vertical = v and true or false; SP:UpdateCoverageLayout(); Notify() end,
				})
				Row("Toggle", {
					label = "Hide a Totem Once Everyone Is in Range", desc = "When the whole party is getting a totem's buff, its cell disappears; it comes back as soon as someone is out of range. During fights in dungeons every totem stays listed and the names show who is missing its buff.",
					get = function() return CO().hideWhenCovered ~= false end,
					set = function(v) CO().hideWhenCovered = v and true or false; SP:UpdateCoverage(); Notify() end,
				})
			end,
			actions = {
				{ text = "Choose Totems", desc = "Pick which totems the overlay watches.",
				  func = function() FS:Hide(); if ShamanPowerConfig then ShamanPowerConfig:Open({ "fluffy", "partybuff_section" }) end end },
			},
		}
	end

	FS.specs.sprange = function(frame)
		return {
			key = "sprange", title = "Totem Range", subtitle = "overlay",
			element = ELEMENT,
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

if registry and registry.RegisterCallback then
	registry.RegisterCallback({}, "ConfigTableChange", function(_, appName)
		if appName ~= "ShamanPower" or not (dlg and dlg:IsShown()) then return end
		SP:UpdateSPRangeConfigButtons()
		dlg.updateToggleBtnText()
	end)
end

return true
