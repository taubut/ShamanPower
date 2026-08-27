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

local function Build()
	if panel then return panel end
	panel = Core:CreateDialog({
		name = "ShamanPowerFrameSettings",
		width = PANEL_W, height = 200,
		title = "Frame Settings", subtitle = "",
		headerHeight = 44, bodyTop = 8,
	})
	panel:SetFrameStrata("DIALOG")
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

	if spec.scale then
		Row("Slider", {
			label = "Scale", desc = "Size of this frame, as a percentage.",
			min = spec.scale.min or 50, max = spec.scale.max or 300, step = spec.scale.step or 5,
			get = spec.scale.get, set = spec.scale.set,
		})
	end
	if spec.opacity then
		Row("Slider", {
			label = "Opacity", desc = "How solid this frame is.",
			min = spec.opacity.min or 10, max = spec.opacity.max or 100, step = spec.opacity.step or 5,
			get = spec.opacity.get, set = spec.opacity.set,
		})
	end
	if spec.hideFrame then
		Row("Toggle", {
			label = "Hide Frame (icon only)", desc = "Hide the panel and border; the icons stay and can still be dragged.",
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

return FS
