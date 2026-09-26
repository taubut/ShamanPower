-- ShamanPower_Config :: FrameSettings
-- One settings panel for any HUD frame (pop-out trackers, caller buttons, ...).
-- A caller passes a spec describing what the frame supports; the panel draws
-- the matching rows on the dialog chrome.
--
--   spec = {
--     key      = "popout:totem_earth",          -- identity, for toggle/debounce
--     title    = "Pop-Out Settings", subtitle = "Earth totem",
--     scale    = { get = fn -> percent, set = fn(percent), min = 50, max = 300 },
--     opacity  = { get = fn -> percent, set = fn(percent) },
--     hideFrame= { get = fn -> bool,    set = fn(bool) },
--     rows     = function(Row) ... end,          -- extra rows, optional
--     actions  = { { text = "...", func = fn, desc = "..." }, ... },
--   }
-- Engine frames reach it through ShamanPower:OpenFrameSettings(key, frame),
-- which the engine defines as a no-op and this file overrides; specs are
-- registered in FS.specs[key] = function(frame) return spec end.

local ADDON, ns = ...
local Core    = ns.Core
local Widgets = ns.Widgets

local FS = { specs = {} }
ns.FrameSettings = FS

local PANEL_W = 316
local panel

-- Only rebuild when the set of rows changes; refreshing a slider must not
-- release the control currently being dragged.
local function RowShape(spec)
	local shape = (spec.scale and "s" or "") .. (spec.opacity and "o" or "") .. (spec.hideFrame and "h" or "")
	if spec.rows then
		spec.rows(function(kind, opts) shape = shape .. ":" .. kind .. ":" .. (opts.label or "") end)
	end
	return shape
end

local function Build()
	if panel then return panel end
	panel = Core:CreateDialog({
		name = "ShamanPowerFrameSettings",
		width = PANEL_W, height = 200,
		title = "Frame Settings", subtitle = "",
		headerHeight = 44, bodyTop = 8,
		special = true,   -- Escape closes it
		strata = "DIALOG",
	})
	return panel
end

local function Populate(spec)
	local body = panel.body
	Widgets:ReleaseAll(body)
	local width = PANEL_W - panel.pad * 2
	local y = 0
	local function Row(kind, opts)
		opts.x, opts.y, opts.width = 0, y, width
		local f, h = Widgets[kind](Widgets, body, opts)
		y = y + h
		return f
	end

	-- Specs speak whole percents (100 = normal); the slider runs on fractions so
	-- it reads "100%" like every other scale and opacity.
	local function PercentRow(label, desc, s, minP, maxP)
		Row("Slider", {
			label = label, desc = desc, isPercent = true,
			min = (s.min or minP) / 100, max = (s.max or maxP) / 100, step = (s.step or 5) / 100,
			get = function() local v = s.get(); return v and v / 100 end,
			set = function(v) s.set(math.floor(v * 100 + 0.5)) end,
		})
	end
	if spec.scale then
		PercentRow("Scale", "Size of this frame, as a percentage.", spec.scale, 50, 300)
	end
	if spec.opacity then
		PercentRow("Opacity", "How solid this frame is.", spec.opacity, 10, 100)
	end
	if spec.hideFrame then
		Row("Toggle", {
			label = "Hide Background", desc = "Hide the panel and border; the icons stay and can still be dragged.",
			get = spec.hideFrame.get, set = spec.hideFrame.set,
		})
	end
	if spec.rows then spec.rows(Row) end
	if spec.actions and #spec.actions > 0 then
		y = y + 6
		for _, a in ipairs(spec.actions) do
			Row("Button", { label = a.text, buttonText = a.text, desc = a.desc, func = a.func })
		end
	end

	panel:SetHeight(44 + 4 + 8 + y + panel.pad + 2)
end

function FS:Hide()
	if panel then panel:Hide() end
end

function FS:Open(anchorFrame, spec)
	Build()
	if panel:IsShown() then
		if panel.currentKey == spec.key then
			-- A second click on the same button within 0.3s is a double-fire.
			if GetTime() - (panel.openTime or 0) < 0.3 then return end
			panel:Hide()
			return
		end
		panel:Hide()
	end

	panel.currentKey = spec.key
	panel.currentSpec, panel.rowShape = spec, RowShape(spec)
	panel:SetTitles(spec.title or "Frame Settings", spec.subtitle)
	Populate(spec)

	-- Anchor to the SCREEN at the frame's top-right, not to the frame: scale
	-- changes re-centre the frame each tick, and a panel that followed it would
	-- drag the slider out from under the cursor.
	panel:ClearAllPoints()
	local right, top = anchorFrame and anchorFrame:GetRight(), anchorFrame and anchorFrame:GetTop()
	if right and top then
		local ratio = anchorFrame:GetEffectiveScale() / panel:GetEffectiveScale()
		panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", right * ratio + 6, top * ratio)
	else
		panel:SetPoint("CENTER")
	end
	panel.openTime = GetTime()
	panel:Show()
end

-- Engine hook: frames call ShamanPower:OpenFrameSettings(key, frame).
if ShamanPower then
	function ShamanPower:OpenFrameSettings(key, frame)
		local build = FS.specs[key]
		if build then FS:Open(frame, build(frame)) end
	end
end

local registry = _G.LibStub("AceConfigRegistry-3.0", true)
if registry and registry.RegisterCallback then
	local queued = false
	registry.RegisterCallback(FS, "ConfigTableChange", function(_, appName)
		if appName ~= "ShamanPower" or queued or not (panel and panel:IsShown()) then return end
		queued = true
		_G.C_Timer.After(0, function()
			queued = false
			if not (panel and panel:IsShown() and panel.currentSpec) then return end
			local shape = RowShape(panel.currentSpec)
			if shape ~= panel.rowShape then
				panel.rowShape = shape
				Populate(panel.currentSpec)
			else
				Widgets:RefreshAll(panel.body)
			end
		end)
	end)
end

return FS
