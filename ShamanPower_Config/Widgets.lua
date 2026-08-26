-- ShamanPower_Config :: Widgets
-- Widget factory. Every constructor takes (parent, opts) and returns
-- (frame, heightUsed) so callers can stack rows by accumulating height.
--
-- Frames are pooled per widget type. A constructor acquires a free frame of
-- its type (creating one only when the pool is empty) and then configures it
-- for the current opts. Every script installed at creation time reads
-- frame.opts at call time, so a reused frame never sees the get/set/values of
-- the page it was last drawn on. Widgets:ReleaseAll(parent) hands everything
-- back; Widgets:PoolStats() shows that re-rendering does not allocate.
--
-- Rows are tagged at configure time with the metadata the search filter
-- needs, so filtering is a cheap walk over tagged children rather than a
-- re-render.

local ADDON, ns = ...
local Core = ns.Core

local Widgets = {}
ns.Widgets = Widgets

-- Layout constants -----------------------------------------------------------
local ROW_H       = 34
local ROW_GAP     = 6
local PAD         = 12
local SECTION_H   = 24
local SECTION_TOP = 14
local SECTION_BOT = 6

local DROPDOWN_W  = 152
local SLIDER_W    = 118
local NUMBOX_W    = 44
local SWATCH_W    = 26
local TOGGLE_W    = 38
local TOGGLE_H    = 18
local BUTTON_W    = 110

Widgets.ROW_H   = ROW_H
Widgets.ROW_GAP = ROW_GAP
Widgets.PAD     = PAD

local INVERTED_ALPHA = (WOW_PROJECT_ID ~= WOW_PROJECT_MAINLINE)

-- ---------------------------------------------------------------------------
-- Pools
-- One pool per widget type. `free` is a stack of released frames; `created`
-- only ever grows when a pool is empty at acquire time.
-- ---------------------------------------------------------------------------
local POOL_TYPES = {
	"section", "toggle", "slider", "dropdown", "color", "button", "input", "description",
}

local pools = {}
for _, kind in ipairs(POOL_TYPES) do
	pools[kind] = { free = {}, created = 0, inUse = 0 }
end

-- Forward declaration; defined with the dropdown code below.
local HidePopupIfOwnedBy

local function Acquire(kind, parent, create)
	local pool = pools[kind]
	local f = table.remove(pool.free)
	if not f then
		f = create(parent)
		f._spPoolType = kind
		pool.created = pool.created + 1
	end
	pool.inUse = pool.inUse + 1
	f._spAcquired = true

	f:SetParent(parent)
	f:ClearAllPoints()
	f:Show()

	parent._spWidgets = parent._spWidgets or {}
	table.insert(parent._spWidgets, f)
	return f
end

local function Release(f)
	if not f._spAcquired then return end
	f._spAcquired = false
	local pool = pools[f._spPoolType]
	pool.inUse = pool.inUse - 1

	-- A row released mid-interaction must not leave anything behind.
	if f.box and f.box.ClearFocus then f.box:ClearFocus() end
	if f.btn then HidePopupIfOwnedBy(f.btn) end
	Core:HideTooltipFor(f)
	if f.btn then Core:HideTooltipFor(f.btn) end

	f.opts = nil
	f:Hide()
	f:ClearAllPoints()
	table.insert(pool.free, f)
end

-- Return every widget acquired for `parent` to its pool and drop the refresh
-- list built up while the page was rendered.
function Widgets:ReleaseAll(parent)
	local list = parent._spWidgets
	if list then
		for i = #list, 1, -1 do
			Release(list[i])
			list[i] = nil
		end
	end
	parent._spRefreshers = nil
end

-- { type = { created = n, inUse = n } }
function Widgets:PoolStats()
	local out = {}
	for kind, pool in pairs(pools) do
		out[kind] = { created = pool.created, inUse = pool.inUse }
	end
	return out
end

-- ---------------------------------------------------------------------------
-- Search tagging
-- ---------------------------------------------------------------------------
function Widgets:TagRow(frame, labelText, descText, sectionFrame)
	frame._isOptionRow     = true
	frame._isSectionHeader = nil
	frame._labelText       = labelText and strlower(labelText) or ""
	frame._descText        = descText and strlower(descText) or ""
	frame._sectionFrame    = sectionFrame
end

function Widgets:TagSection(frame, labelText)
	frame._isSectionHeader = true
	frame._isOptionRow     = nil
	frame._labelText       = labelText and strlower(labelText) or ""
	frame._descText        = ""
	frame._sectionFrame    = nil
end

-- ---------------------------------------------------------------------------
-- Shared row scaffold
-- CreateRow runs once per pooled frame; ConfigureRow runs on every acquire and
-- resets everything the previous occupant could have changed.
-- ---------------------------------------------------------------------------
local function CreateRow(parent)
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(300, ROW_H)
	row:EnableMouse(true)
	Core:RowBg(row)
	Core:HoverHighlight(row)

	local label = row:CreateFontString(nil, "OVERLAY")
	label:SetFontObject(Core.fonts.row)
	label:SetPoint("LEFT", row, "LEFT", PAD, 0)
	label:SetJustifyH("LEFT")
	row.label = label

	-- Hook once; the fields are refreshed by ConfigureRow.
	Core:AttachTooltip(row, "", nil)
	return row
end

local function ConfigureRow(row, parent, opts)
	row.opts = opts
	row:SetSize(opts.width or 300, ROW_H)
	row:SetPoint("TOPLEFT", parent, "TOPLEFT", opts.x or 0, -(opts.y or 0))

	-- Visual state a released row may have been left in.
	if row.spBg then row.spBg:SetColorTexture(Core:Color("rowBg", Core.opacity)) end
	Core:SetBorderColor(row, "borderSoft")
	row.label:SetText("")
	row.label:SetTextColor(Core:Color("text"))
	row.label.spTruncated = false
	row._fullLabel = opts.label
	row._disabled = false

	Core:AttachTooltip(row, opts.label, opts.desc)
	Widgets:TagRow(row, opts.label, opts.desc, opts.section)
end

-- Truncate the label so it can never run under the control cluster.
-- Row width must already be set (ConfigureRow does that) before this runs.
local function ClampRowLabel(row, controlWidth)
	local avail = row:GetWidth() - controlWidth - (PAD * 2) - 8
	Core:ClampLabel(row.label, avail, row._fullLabel or "")
end

local function ApplyDisabled(row, isDisabled)
	row._disabled = isDisabled and true or false
	if isDisabled then
		row.label:SetTextColor(Core:Color("textMute"))
	else
		row.label:SetTextColor(Core:Color("text"))
	end
	if row.spSetControlEnabled then
		row:spSetControlEnabled(not isDisabled)
	end
end

-- Every widget exposes a refresh closure so a page can re-sync after any set.
local function RegisterRefresh(parent, fn)
	parent._spRefreshers = parent._spRefreshers or {}
	table.insert(parent._spRefreshers, fn)
end

function Widgets:RefreshAll(parent)
	if not parent._spRefreshers then return end
	for _, fn in ipairs(parent._spRefreshers) do
		local ok, err = pcall(fn)
		if not ok then
			geterrorhandler()(err)
		end
	end
end

-- Common tail for every control row: enabled state is reset explicitly (a
-- row with no `disabled` in its opts would otherwise inherit the previous
-- occupant's muted label), then the widget's own refresh syncs the value.
local function FinishRow(row, parent, controlWidth)
	ApplyDisabled(row, false)
	ClampRowLabel(row, controlWidth)
	RegisterRefresh(parent, row.refresh)
	row.refresh()
	return row, ROW_H + ROW_GAP
end

-- ---------------------------------------------------------------------------
-- Section header
-- ---------------------------------------------------------------------------
local function CreateSection(parent)
	local h = CreateFrame("Frame", nil, parent)
	h:SetSize(300, SECTION_H)

	local fs = h:CreateFontString(nil, "OVERLAY")
	fs:SetFontObject(Core.fonts.section)
	fs:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", PAD, 2)
	h.label = fs

	local note = h:CreateFontString(nil, "OVERLAY")
	note:SetFontObject(Core.fonts.tiny)
	note:SetPoint("LEFT", fs, "RIGHT", 6, 0)
	note:Hide()
	h.note = note

	local rule = h:CreateTexture(nil, "ARTWORK")
	rule:SetHeight(1)
	rule:SetPoint("BOTTOMLEFT", fs, "BOTTOMRIGHT", 10, 3)
	rule:SetPoint("RIGHT", h, "RIGHT", -PAD, 0)
	rule:SetColorTexture(Core:Color("border", 0.6))
	h.rule = rule
	return h
end

function Widgets:SectionHeader(parent, opts)
	local h = Acquire("section", parent, CreateSection)
	h.opts = opts
	h:SetSize(opts.width or 300, SECTION_H)
	h:SetPoint("TOPLEFT", parent, "TOPLEFT", opts.x or 0, -((opts.y or 0) + SECTION_TOP))

	h.label:SetText(strupper(opts.label or ""))
	if opts.note then
		h.note:SetText(opts.note)
		h.note:Show()
	else
		h.note:SetText("")
		h.note:Hide()
	end

	self:TagSection(h, opts.label)
	return h, SECTION_H + SECTION_TOP + SECTION_BOT
end

-- ---------------------------------------------------------------------------
-- Toggle (pill switch)
-- ---------------------------------------------------------------------------
local function TogglePaint(row, state)
	if state then
		row.trackTex:SetColorTexture(Core:Color("accent"))
		row.knob:ClearAllPoints()
		row.knob:SetPoint("RIGHT", row.track, "RIGHT", -3, 0)
	else
		row.trackTex:SetColorTexture(Core:Color("off"))
		row.knob:ClearAllPoints()
		row.knob:SetPoint("LEFT", row.track, "LEFT", 3, 0)
	end
	if row._disabled then
		row.knob:SetVertexColor(0.5, 0.5, 0.5, 1)
	else
		row.knob:SetVertexColor(1, 1, 1, 1)
	end
end

local function CreateToggle(parent)
	local row = CreateRow(parent)

	local track = CreateFrame("Button", nil, row)
	track:SetSize(TOGGLE_W, TOGGLE_H)
	track:SetPoint("RIGHT", row, "RIGHT", -PAD, 0)
	local trackTex = track:CreateTexture(nil, "BACKGROUND")
	trackTex:SetAllPoints(track)
	trackTex:SetColorTexture(Core:Color("off"))
	Core:MakeBorder(track, "border")

	local knob = track:CreateTexture(nil, "OVERLAY")
	knob:SetSize(TOGGLE_H - 6, TOGGLE_H - 6)
	knob:SetColorTexture(0.95, 0.96, 0.98, 1)

	row.track, row.trackTex, row.knob = track, trackTex, knob

	track:SetScript("OnClick", function()
		local opts = row.opts
		if not opts or row._disabled then return end
		local newVal = not opts.get()
		opts.set(newVal)
		TogglePaint(row, newVal)
		if opts.onChanged then opts.onChanged() end
	end)

	row.spSetControlEnabled = function(_, enabled)
		if enabled then track:Enable() else track:Disable() end
		if row.opts then TogglePaint(row, row.opts.get()) end
	end

	row.refresh = function()
		local opts = row.opts
		if not opts then return end
		TogglePaint(row, opts.get())
		if opts.disabled then ApplyDisabled(row, opts.disabled()) end
	end
	return row
end

function Widgets:Toggle(parent, opts)
	local row = Acquire("toggle", parent, CreateToggle)
	ConfigureRow(row, parent, opts)
	return FinishRow(row, parent, TOGGLE_W)
end

-- ---------------------------------------------------------------------------
-- Slider with numeric readout
-- ---------------------------------------------------------------------------
local function SliderFormat(row, v)
	if row.step < 1 then return string.format("%.2f", v) end
	return tostring(math.floor(v + 0.5))
end

local function SliderPaintFill(row, v)
	local minV, maxV = row.min, row.max
	local pct = (maxV > minV) and ((v - minV) / (maxV - minV)) or 0
	row.fill:SetWidth(math.max(1, SLIDER_W * pct))
end

local function CreateSlider(parent)
	local row = CreateRow(parent)
	row.min, row.max, row.step = 0, 100, 1

	local box = CreateFrame("EditBox", nil, row)
	box:SetSize(NUMBOX_W, 20)
	box:SetPoint("RIGHT", row, "RIGHT", -PAD, 0)
	box:SetAutoFocus(false)
	box:SetFontObject(Core.fonts.row)
	box:SetJustifyH("CENTER")
	box:SetTextInsets(2, 2, 0, 0)
	Core:SolidTex(box, "windowBg", "BACKGROUND")
	Core:MakeBorder(box, "border")

	local slider = CreateFrame("Slider", nil, row)
	slider:SetSize(SLIDER_W, 14)
	slider:SetPoint("RIGHT", box, "LEFT", -8, 0)
	slider:SetOrientation("HORIZONTAL")
	slider:SetMinMaxValues(0, 100)
	slider:SetValueStep(1)
	if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end

	local groove = slider:CreateTexture(nil, "BACKGROUND")
	groove:SetHeight(3)
	groove:SetPoint("LEFT", slider, "LEFT", 0, 0)
	groove:SetPoint("RIGHT", slider, "RIGHT", 0, 0)
	groove:SetColorTexture(Core:Color("off"))

	local fill = slider:CreateTexture(nil, "ARTWORK")
	fill:SetHeight(3)
	fill:SetPoint("LEFT", groove, "LEFT", 0, 0)
	fill:SetColorTexture(Core:Color("accent"))

	local thumb = slider:CreateTexture(nil, "OVERLAY")
	thumb:SetSize(12, 12)
	thumb:SetColorTexture(0.95, 0.96, 0.98, 1)
	slider:SetThumbTexture(thumb)

	row.box, row.slider, row.fill = box, slider, fill
	row._applying = false

	slider:SetScript("OnValueChanged", function(self, v)
		if row._applying then return end
		local opts = row.opts
		if not opts then return end
		box:SetText(SliderFormat(row, v))
		SliderPaintFill(row, v)
		if row._disabled then return end
		opts.set(v)
		if opts.onChanged then opts.onChanged() end
	end)

	box:SetScript("OnEnterPressed", function(self)
		local v = tonumber(self:GetText())
		if v then
			v = math.max(row.min, math.min(row.max, v))
			slider:SetValue(v)
		end
		self:ClearFocus()
	end)
	box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

	row.spSetControlEnabled = function(_, enabled)
		slider:EnableMouse(enabled)
		box:EnableMouse(enabled)
		box:SetTextColor(Core:ColorIf(enabled, "text", "textMute"))
		fill:SetColorTexture(Core:ColorIf(enabled, "accent", "off"))
	end

	row.refresh = function()
		local opts = row.opts
		if not opts then return end
		row._applying = true
		local ok, err = pcall(function()
			local v = opts.get() or row.min
			slider:SetValue(v)
			box:SetText(SliderFormat(row, v))
			SliderPaintFill(row, v)
		end)
		row._applying = false
		if not ok then geterrorhandler()(err) end
		if opts.disabled then ApplyDisabled(row, opts.disabled()) end
	end
	return row
end

function Widgets:Slider(parent, opts)
	local row = Acquire("slider", parent, CreateSlider)
	ConfigureRow(row, parent, opts)

	row.min  = opts.min or 0
	row.max  = opts.max or 100
	row.step = opts.step or 1

	-- Changing the range can clamp the current value and fire OnValueChanged;
	-- that must never reach the new opts.set.
	row._applying = true
	row.slider:SetMinMaxValues(row.min, row.max)
	row.slider:SetValueStep(row.step)
	row._applying = false

	return FinishRow(row, parent, SLIDER_W + NUMBOX_W + 8)
end

-- ---------------------------------------------------------------------------
-- Dropdown
-- One shared popup is reused by every dropdown on screen.
-- ---------------------------------------------------------------------------
local popup
function Widgets:HidePopup()
	if popup then popup:Hide() end
end

local function GetPopup()
	if popup then return popup end
	popup = CreateFrame("Frame", "ShamanPowerConfigDropdownPopup", UIParent)
	popup:SetFrameStrata("FULLSCREEN_DIALOG")
	popup:SetFrameLevel(20)
	popup:SetClampedToScreen(true)
	popup:Hide()

	-- Click-away catcher: an invisible full-screen button one level under the
	-- menu. Any click outside the menu lands here and closes it, exactly like
	-- Blizzard's dropdowns; the click is consumed rather than passed through.
	local catcher = CreateFrame("Button", nil, UIParent)
	catcher:SetFrameStrata("FULLSCREEN_DIALOG")
	catcher:SetFrameLevel(10)
	catcher:SetAllPoints(UIParent)
	catcher:EnableMouse(true)
	catcher:RegisterForClicks("AnyUp", "AnyDown")
	catcher:EnableMouseWheel(true)
	catcher:SetScript("OnClick", function() popup:Hide() end)
	catcher:SetScript("OnMouseWheel", function() popup:Hide() end)
	catcher:Hide()
	popup.catcher = catcher
	Core:SolidTex(popup, "sidebarBg", "BACKGROUND")
	Core:MakeBorder(popup, "accent")

	popup.scroll = CreateFrame("ScrollFrame", nil, popup)
	popup.scroll:SetPoint("TOPLEFT", popup, "TOPLEFT", 2, -2)
	popup.scroll:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -2, 2)
	popup.content = CreateFrame("Frame", nil, popup.scroll)
	popup.content:SetSize(10, 10)
	popup.scroll:SetScrollChild(popup.content)
	popup.buttons = {}

	popup.scroll:EnableMouseWheel(true)
	popup.scroll:SetScript("OnMouseWheel", function(self, delta)
		local cur = self:GetVerticalScroll()
		local maxS = math.max(0, popup.content:GetHeight() - self:GetHeight())
		self:SetVerticalScroll(math.max(0, math.min(maxS, cur - delta * 28)))
	end)

	popup:SetScript("OnShow", function() popup.catcher:Show() end)
	popup:SetScript("OnHide", function()
		popup.owner = nil
		popup.catcher:Hide()
	end)
	return popup
end

HidePopupIfOwnedBy = function(anchor)
	if popup and popup.owner == anchor then
		popup:Hide()
	end
end

local ITEM_H = 22
local MAX_POPUP_H = 260

local function ShowPopup(anchorTo, items, currentValue, onPick, popts)
	local p = GetPopup()
	p.owner = anchorTo

	for _, b in ipairs(p.buttons) do b:Hide() end

	local width = math.max(anchorTo:GetWidth(), (popts and popts.width) or 140)
	local y = 0
	for i, item in ipairs(items) do
		local b = p.buttons[i]
		if not b then
			b = CreateFrame("Button", nil, p.content)
			b.bg = b:CreateTexture(nil, "BACKGROUND")
			b.bg:SetAllPoints(b)
			b.text = b:CreateFontString(nil, "OVERLAY")
			b.text:SetFontObject(Core.fonts.row)
			b.text:SetPoint("LEFT", b, "LEFT", 8, 0)
			b.text:SetJustifyH("LEFT")
			b:SetScript("OnEnter", function(self)
				self.bg:SetColorTexture(Core:Color("accent", 0.35))
			end)
			b:SetScript("OnLeave", function(self)
				if self._selected then
					self.bg:SetColorTexture(Core:Color("accent", 0.22))
				else
					self.bg:SetColorTexture(0, 0, 0, 0)
				end
			end)
			-- Installed once; per-show data lives on the button.
			b:SetScript("OnClick", function(self)
				p:Hide()
				if self._onPick then self._onPick(self._key) end
			end)
			p.buttons[i] = b
		end
		b:SetSize(width - 4, ITEM_H)
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", p.content, "TOPLEFT", 0, -y)
		b.text:SetText(item.text)
		b._key = item.key
		b._onPick = onPick
		b._selected = (item.key == currentValue)
		if b._selected then
			b.bg:SetColorTexture(Core:Color("accent", 0.22))
			b.text:SetTextColor(Core:Color("accentHi"))
		else
			b.bg:SetColorTexture(0, 0, 0, 0)
			b.text:SetTextColor(Core:Color("text"))
		end
		b:Show()
		y = y + ITEM_H
	end

	p.content:SetSize(width - 4, math.max(y, 1))
	local h = math.min(y + 4, MAX_POPUP_H)
	p:SetSize(width, h)
	p:ClearAllPoints()
	if popts and popts.above then
		p:SetPoint("BOTTOMLEFT", anchorTo, "TOPLEFT", 0, 2)
	else
		p:SetPoint("TOPRIGHT", anchorTo, "BOTTOMRIGHT", 0, -2)
	end
	p.scroll:SetVerticalScroll(0)
	p:Show()
end

local function DropdownItems(opts)
	local values = opts.values()
	local order  = opts.order and opts.order() or nil
	local items = {}
	if order then
		for _, k in ipairs(order) do
			if values[k] ~= nil then
				table.insert(items, { key = k, text = tostring(values[k]) })
			end
		end
	else
		local keys = {}
		for k in pairs(values) do table.insert(keys, k) end
		table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
		for _, k in ipairs(keys) do
			table.insert(items, { key = k, text = tostring(values[k]) })
		end
	end
	return items, values
end

local function DropdownPaint(row)
	local opts = row.opts
	if not opts then return end
	local _, values = DropdownItems(opts)
	local cur = opts.get()
	local label = values and values[cur]
	local text = label and tostring(label) or "|cff8A94A6-|r"
	-- Button is sized to the longest option below; this is the fallback for a
	-- value that is still too wide (very long localized strings).
	Core:ClampLabel(row.txt, row.btn:GetWidth() - 30, text)
end

-- Width that fits the longest option label, bounded so the row label keeps
-- at least DROPDOWN_LABEL_MIN of room.
local DROPDOWN_LABEL_MIN = 96
local function DropdownFitWidth(row, opts)
	local items = DropdownItems(opts)
	local widest = 0
	for _, item in ipairs(items) do
		row.measure:SetText(item.text)
		local w = row.measure:GetStringWidth()
		if w > widest then widest = w end
	end
	local want = math.ceil(widest) + 8 + 22 + 6      -- text pad + arrow zone + slack
	local maxW = row:GetWidth() - (PAD * 2) - DROPDOWN_LABEL_MIN
	if maxW < DROPDOWN_W then maxW = DROPDOWN_W end
	return math.max(DROPDOWN_W, math.min(want, maxW))
end

local function CreateDropdown(parent)
	local row = CreateRow(parent)

	local btn = CreateFrame("Button", nil, row)
	btn:SetSize(DROPDOWN_W, 22)
	btn:SetPoint("RIGHT", row, "RIGHT", -PAD, 0)
	Core:SolidTex(btn, "windowBg", "BACKGROUND")
	Core:MakeBorder(btn, "border")

	local txt = btn:CreateFontString(nil, "OVERLAY")
	txt:SetFontObject(Core.fonts.row)
	txt:SetPoint("LEFT", btn, "LEFT", 8, 0)
	txt:SetPoint("RIGHT", btn, "RIGHT", -20, 0)
	txt:SetJustifyH("LEFT")
	txt:SetWordWrap(false)

	-- Off-screen string used only to measure option labels.
	local measure = btn:CreateFontString(nil, "OVERLAY")
	measure:SetFontObject(Core.fonts.row)
	measure:SetPoint("LEFT", btn, "LEFT", 0, 0)
	measure:Hide()
	row.measure = measure

	local arrow = btn:CreateFontString(nil, "OVERLAY")
	arrow:SetFontObject(Core.fonts.tiny)
	arrow:SetPoint("RIGHT", btn, "RIGHT", -7, 0)
	arrow:SetText("v")
	arrow:SetTextColor(Core:Color("textDim"))

	row.btn, row.txt = btn, txt

	btn:SetScript("OnEnter", function() Core:SetBorderColor(btn, "accent") end)
	btn:SetScript("OnLeave", function() Core:SetBorderColor(btn, "border") end)

	btn:SetScript("OnClick", function()
		local opts = row.opts
		if not opts or row._disabled then return end
		local p = GetPopup()
		if p:IsShown() and p.owner == btn then p:Hide() return end
		local items = DropdownItems(opts)
		ShowPopup(btn, items, opts.get(), function(key)
			-- The row may have been re-rendered for a different option between
			-- opening the popup and picking; commit to the opts that opened it.
			opts.set(key)
			if row.opts == opts then DropdownPaint(row) end
			if opts.onChanged then opts.onChanged() end
		end)
	end)

	row.spSetControlEnabled = function(_, enabled)
		if enabled then btn:Enable() else btn:Disable() end
		txt:SetTextColor(Core:ColorIf(enabled, "text", "textMute"))
	end

	row.refresh = function()
		local opts = row.opts
		if not opts then return end
		DropdownPaint(row)
		if opts.disabled then ApplyDisabled(row, opts.disabled()) end
	end
	return row
end

-- Public: used by other windows in this module (assignment window menus).
function Widgets:ShowPopup(anchorTo, items, currentValue, onPick, popts)
	return ShowPopup(anchorTo, items, currentValue, onPick, popts)
end

function Widgets:Dropdown(parent, opts)
	local row = Acquire("dropdown", parent, CreateDropdown)
	ConfigureRow(row, parent, opts)
	Core:SetBorderColor(row.btn, "border")
	local w = DropdownFitWidth(row, opts)
	row.btn:SetWidth(w)
	row.txt:SetText("")
	return FinishRow(row, parent, w)
end

-- ---------------------------------------------------------------------------
-- Color swatch
-- ---------------------------------------------------------------------------
local function ColorPaint(row)
	local opts = row.opts
	if not opts then return end
	local r, g, b, a = opts.get()
	row.swatch:SetColorTexture(r or 1, g or 1, b or 1, opts.hasAlpha and (a or 1) or 1)
end

local function CreateColor(parent)
	local row = CreateRow(parent)

	local btn = CreateFrame("Button", nil, row)
	btn:SetSize(SWATCH_W, 18)
	btn:SetPoint("RIGHT", row, "RIGHT", -PAD, 0)
	Core:MakeBorder(btn, "border")

	local checker = btn:CreateTexture(nil, "BACKGROUND")
	checker:SetAllPoints(btn)
	checker:SetColorTexture(0.25, 0.25, 0.25, 1)

	local swatch = btn:CreateTexture(nil, "ARTWORK")
	swatch:SetAllPoints(btn)

	row.btn, row.swatch = btn, swatch

	btn:SetScript("OnEnter", function() Core:SetBorderColor(btn, "accent") end)
	btn:SetScript("OnLeave", function() Core:SetBorderColor(btn, "border") end)

	btn:SetScript("OnClick", function()
		local opts = row.opts
		if not opts or row._disabled then return end
		local r, g, b, a = opts.get()
		r, g, b, a = r or 1, g or 1, b or 1, a or 1

		-- ColorPickerFrame calls back later; bind to the opts that opened it so
		-- a page re-render in between cannot redirect the commit.
		local function Commit(nr, ng, nb, na)
			if INVERTED_ALPHA and na then na = 1 - na end
			if not opts.hasAlpha then na = 1 end
			opts.set(nr, ng, nb, na)
			if row.opts == opts then ColorPaint(row) end
			if opts.onChanged then opts.onChanged() end
		end

		ColorPickerFrame:SetFrameStrata("FULLSCREEN_DIALOG")
		ColorPickerFrame:SetClampedToScreen(true)

		local storedAlpha = INVERTED_ALPHA and (1 - a) or a

		if ColorPickerFrame.SetupColorPickerAndShow then
			ColorPickerFrame:SetupColorPickerAndShow({
				r = r, g = g, b = b,
				hasOpacity = opts.hasAlpha,
				opacity = storedAlpha,
				swatchFunc = function()
					local nr, ng, nb = ColorPickerFrame:GetColorRGB()
					Commit(nr, ng, nb, ColorPickerFrame:GetColorAlpha())
				end,
				opacityFunc = function()
					local nr, ng, nb = ColorPickerFrame:GetColorRGB()
					Commit(nr, ng, nb, ColorPickerFrame:GetColorAlpha())
				end,
				cancelFunc = function() Commit(r, g, b, storedAlpha) end,
			})
		else
			ColorPickerFrame.func = function()
				local nr, ng, nb = ColorPickerFrame:GetColorRGB()
				Commit(nr, ng, nb, OpacitySliderFrame and OpacitySliderFrame:GetValue() or 0)
			end
			ColorPickerFrame.opacityFunc = ColorPickerFrame.func
			ColorPickerFrame.hasOpacity = opts.hasAlpha
			if opts.hasAlpha then ColorPickerFrame.opacity = storedAlpha end
			ColorPickerFrame.cancelFunc = function() Commit(r, g, b, storedAlpha) end
			ColorPickerFrame:SetColorRGB(r, g, b)
			ColorPickerFrame:Show()
		end
	end)

	row.spSetControlEnabled = function(_, enabled)
		if enabled then btn:Enable() else btn:Disable() end
		swatch:SetAlpha(enabled and 1 or 0.4)
	end

	row.refresh = function()
		local opts = row.opts
		if not opts then return end
		ColorPaint(row)
		if opts.disabled then ApplyDisabled(row, opts.disabled()) end
	end
	return row
end

function Widgets:Color(parent, opts)
	local row = Acquire("color", parent, CreateColor)
	ConfigureRow(row, parent, opts)
	Core:SetBorderColor(row.btn, "border")
	return FinishRow(row, parent, SWATCH_W)
end

-- ---------------------------------------------------------------------------
-- Button (execute)
-- ---------------------------------------------------------------------------
local function CreateButton(parent)
	local row = CreateRow(parent)

	local btn = CreateFrame("Button", nil, row)
	btn:SetHeight(22)
	btn:SetPoint("RIGHT", row, "RIGHT", -PAD, 0)
	local bg = btn:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(btn)
	bg:SetColorTexture(Core:Color("accent", 0.18))
	Core:MakeBorder(btn, "accent")

	local txt = btn:CreateFontString(nil, "OVERLAY")
	txt:SetFontObject(Core.fonts.button)
	txt:SetPoint("CENTER")
	txt:SetTextColor(Core:Color("accentHi"))

	row.btn, row.btnBg, row.txt = btn, bg, txt

	btn:SetScript("OnEnter", function() bg:SetColorTexture(Core:Color("accent", 0.38)) end)
	btn:SetScript("OnLeave", function() bg:SetColorTexture(Core:Color("accent", 0.18)) end)
	btn:SetScript("OnClick", function()
		local opts = row.opts
		if not opts or row._disabled then return end
		opts.func()
		if opts.onChanged then opts.onChanged() end
	end)

	row.spSetControlEnabled = function(_, enabled)
		if enabled then btn:Enable() else btn:Disable() end
		txt:SetTextColor(Core:ColorIf(enabled, "accentHi", "textMute"))
	end

	row.refresh = function()
		local opts = row.opts
		if not opts then return end
		if opts.disabled then ApplyDisabled(row, opts.disabled()) end
	end
	return row
end

function Widgets:Button(parent, opts)
	local row = Acquire("button", parent, CreateButton)
	ConfigureRow(row, parent, opts)

	local txt = row.txt
	local caption = opts.buttonText or opts.label or ""
	row.btnBg:SetColorTexture(Core:Color("accent", 0.18))
	txt.spTruncated = false
	txt:SetText(caption)

	-- Grow the button to fit its caption rather than clipping at a fixed width.
	-- Captions wider than the row get ellipsised instead of overflowing.
	local maxW = (opts.width or 300) - (PAD * 2)
	local desired = txt:GetStringWidth() + 28
	row.btn:SetWidth(math.max(opts.buttonWidth or BUTTON_W, math.min(desired, maxW)))
	if desired > maxW then
		Core:ClampLabel(txt, maxW - 24, caption)
	end

	-- The button carries its own caption, so the row label stays empty.
	-- (FinishRow's clamp runs against _fullLabel, so blank that too.)
	row._fullLabel = ""
	ApplyDisabled(row, false)
	row.label:SetText("")
	RegisterRefresh(parent, row.refresh)
	row.refresh()
	return row, ROW_H + ROW_GAP
end

-- ---------------------------------------------------------------------------
-- Text input
-- ---------------------------------------------------------------------------
local function CreateInput(parent)
	local row = CreateRow(parent)

	local box = CreateFrame("EditBox", nil, row)
	box:SetSize(DROPDOWN_W, 22)
	box:SetPoint("RIGHT", row, "RIGHT", -PAD, 0)
	box:SetAutoFocus(false)
	box:SetFontObject(Core.fonts.row)
	box:SetTextInsets(6, 6, 0, 0)
	Core:SolidTex(box, "windowBg", "BACKGROUND")
	Core:MakeBorder(box, "border")

	row.box = box

	box:SetScript("OnEditFocusGained", function() Core:SetBorderColor(box, "accent") end)
	box:SetScript("OnEditFocusLost", function() Core:SetBorderColor(box, "border") end)
	box:SetScript("OnEnterPressed", function(self)
		local opts = row.opts
		if not opts then self:ClearFocus() return end
		opts.set(self:GetText())
		self:ClearFocus()
		if opts.onChanged then opts.onChanged() end
	end)
	box:SetScript("OnEscapePressed", function(self)
		local opts = row.opts
		self:SetText(opts and opts.get() or "")
		self:ClearFocus()
	end)

	row.spSetControlEnabled = function(_, enabled)
		box:EnableMouse(enabled)
		box:SetTextColor(Core:ColorIf(enabled, "text", "textMute"))
	end

	row.refresh = function()
		local opts = row.opts
		if not opts then return end
		box:SetText(opts.get() or "")
		if opts.disabled then ApplyDisabled(row, opts.disabled()) end
	end
	return row
end

function Widgets:Input(parent, opts)
	local row = Acquire("input", parent, CreateInput)
	ConfigureRow(row, parent, opts)
	Core:SetBorderColor(row.box, "border")
	return FinishRow(row, parent, DROPDOWN_W)
end

-- ---------------------------------------------------------------------------
-- Description block (wrapping prose, no control)
-- ---------------------------------------------------------------------------
local function CreateDescription(parent)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(300, 18)

	local fs = f:CreateFontString(nil, "OVERLAY")
	fs:SetFontObject(Core.fonts.rowDim)
	fs:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, 0)
	fs:SetJustifyH("LEFT")
	f.text = fs
	return f
end

function Widgets:Description(parent, opts)
	local f = Acquire("description", parent, CreateDescription)
	f.opts = opts
	local width = opts.width or 300
	f:SetPoint("TOPLEFT", parent, "TOPLEFT", opts.x or 0, -(opts.y or 0))

	local fs = f.text
	fs:SetWidth(width - PAD * 2)
	fs:SetText(opts.text or "")

	-- GetStringHeight can under-report before the region is laid out, which
	-- lets the next row ride up over the text. Size the frame to the string,
	-- then let the fontstring drive the final height.
	f:SetSize(width, 18)
	local h = math.max(fs:GetStringHeight() + 10, 18)
	f:SetSize(width, h)

	self:TagRow(f, opts.text, nil, opts.section)
	return f, h + ROW_GAP
end

return Widgets
