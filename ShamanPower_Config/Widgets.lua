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
if ShamanPower then ShamanPower.UIKit = ShamanPower.UIKit or {}; ShamanPower.UIKit.Widgets = Widgets end

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
local BUTTON_W    = 110

Widgets.ROW_H   = ROW_H
Widgets.ROW_GAP = ROW_GAP
Widgets.PAD     = PAD

-- The settings page's element (Window.lua sets it while it draws a page): the
-- switches and the slider fills take its color. nil (any other window): the
-- switches in logo blue, the slider fills in accent as before.
local curElement
function Widgets:SetElement(key) curElement = key end

-- A row inside a section card (Window.lua's page packer, D30 "one card per
-- section": opts.inCard) draws no card of its own and stacks with no gap; the
-- card draws the thin lines between the rows.
Widgets.CARD_INSET = 2         -- a row in a card: its label 14 in from the card's edge (PAD + 2)
local CARD_TEXT_PAD = 9        -- a description in a card: above and below its text

-- (the brand file is missing when the addon was updated while the game ran: accent)
local function ElementRGB(key)
	local sp = ShamanPower
	if sp and sp.BrandElementRGB then return sp:BrandElementRGB(key) end
	return Core:Color("accent")
end

-- ---------------------------------------------------------------------------
-- Pools
-- One pool per widget type. `free` is a stack of released frames; `created`
-- only ever grows when a pool is empty at acquire time.
-- ---------------------------------------------------------------------------
local POOL_TYPES = {
	"section", "toggle", "slider", "dropdown", "color", "button", "input", "description", "card",
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
-- opts.tag: a string, or function(opts.tagNode) -> string or nil (no tag)
local function PaintRowTag(row)
	local src, text = row._tagSrc, nil
	if type(src) == "function" then
		local ok, t = pcall(src, row._tagNode)
		if ok and type(t) == "string" and t ~= "" then text = t end
	elseif type(src) == "string" and src ~= "" then
		text = src
	end
	if text then
		row.tag:SetText(strupper(text))
		row.tag:SetTextColor(Core:Color("accentHi"))
		row.tag:Show()
	else
		row.tag:SetText("")
		row.tag:Hide()
	end
end

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
	label:SetNonSpaceWrap(true)   -- when it wraps, a long word breaks rather than cuts
	row.label = label

	-- a tag right after the label (opts.tag): small caps in accentHi, like the Themes
	-- page's "WOW"; a function tag is asked again on every refresh of the row
	local tag = row:CreateFontString(nil, "OVERLAY")
	tag:SetFontObject(Core.fonts.strip)
	tag:SetPoint("LEFT", label, "RIGHT", 8, 0)
	tag:Hide()
	row.tag = tag
	row.spPaintTag = function() PaintRowTag(row) end

	-- Hook once; the fields are refreshed by ConfigureRow.
	Core:AttachTooltip(row, "", nil)
	return row
end

local function ConfigureRow(row, parent, opts)
	row.opts = opts
	row:SetSize(opts.width or 300, ROW_H)
	row:SetPoint("TOPLEFT", parent, "TOPLEFT", opts.x or 0, -(opts.y or 0))

	-- Visual state a released row may have been left in. Inside a section card
	-- the row's own card is see-through and edgeless (its hover still shows).
	row._inCard = opts.inCard and true or false
	row._element = curElement
	if row._inCard then
		Core:SetFadeAlpha(row.spBg, 0)
		Core:SetBorderColor(row, "borderSoft", 0)
	else
		Core:SetFadeAlpha(row.spBg, 1)
		Core:SetBorderColor(row, "borderSoft")
	end
	row.label:SetText("")
	row.label:SetTextColor(Core:Color("text"))
	row.label.spTruncated = false
	row._fullLabel = opts.label
	row._controlMinH = nil
	row._disabled = false
	row._tagSrc, row._tagNode = opts.tag, opts.tagNode
	PaintRowTag(row)
	-- optional card hover hooks (style previews); pooled rows must not keep old ones
	row.spOnEnter, row.spOnLeave = opts.onEnter, opts.onLeave

	-- (opts.searchPath: the row was reached through search, its tooltip says where it lives)
	Core:AttachTooltip(row, opts.label, opts.desc, nil, opts.searchPath)
	Widgets:TagRow(row, opts.label, opts.desc, opts.section)
end

-- Truncate the label so it can never run under the control cluster.
-- Row width must already be set (ConfigureRow does that) before this runs.
-- Labels are never cut short. One that does not fit beside the control wraps
-- onto more lines and the row grows to hold them. spTruncated still tells the
-- settings page renderer "this needed more room", so it can hand the row the
-- whole width first; only a label too long even then ends up wrapped.
local function ClampRowLabel(row, controlWidth)
	local tagW = 0
	if row.tag:IsShown() then tagW = row.tag:GetStringWidth() + 8 end
	local avail = row:GetWidth() - controlWidth - (PAD * 2) - 8 - tagW
	local label = row.label
	-- a control taller than one line (a dropdown whose value wraps) sets the floor
	local minH = math.max(ROW_H, row._controlMinH or 0)
	label:SetWordWrap(false)
	label:SetWidth(0)
	label:SetText(row._fullLabel or "")
	local tooLong = avail > 0 and label:GetStringWidth() > avail
	label.spTruncated = tooLong
	if tooLong then
		label:SetWidth(avail)
		label:SetWordWrap(true)
		row:SetHeight(math.max(minH, math.ceil(label:GetStringHeight()) + 14))
	else
		row:SetHeight(minH)
	end
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

-- the gap under a row: none inside a section card (a line separates the rows)
local function RowGap(row)
	if row._inCard then return 0 end
	return ROW_GAP
end

-- Common tail for every control row: enabled state is reset explicitly (a
-- row with no `disabled` in its opts would otherwise inherit the previous
-- occupant's muted label), then the widget's own refresh syncs the value.
local function FinishRow(row, parent, controlWidth)
	ApplyDisabled(row, false)
	row._controlWidth = controlWidth
	ClampRowLabel(row, controlWidth)
	RegisterRefresh(parent, row.refresh)
	if type(row._tagSrc) == "function" then RegisterRefresh(parent, row.spPaintTag) end
	row.refresh()
	return row, row:GetHeight() + RowGap(row)   -- taller when the label wrapped
end

-- The page renderer asks this after placing a row in a column: a label that
-- had to be cut gets the whole line instead (controls anchor to the row's
-- right edge, so only the width changes).
function Widgets:LabelTruncated(row)
	return row and row.label and row.label.spTruncated or false
end

function Widgets:Widen(row, width)
	row:SetWidth(width)
	-- a dropdown fitted to its column can use the extra room before it wraps
	if row.spRefit then row.spRefit() end
	ClampRowLabel(row, row._controlWidth or 0)
	return row:GetHeight() + RowGap(row)   -- the new height: one line again, or wrapped
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

	-- featured heading extras (hidden on ordinary sections)
	h.icon = h:CreateTexture(nil, "ARTWORK")
	h.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	h.icon:Hide()
	h.glow = h:CreateTexture(nil, "BACKGROUND")
	h.glow:SetColorTexture(1, 1, 1, 1)
	h.glow:Hide()
	return h
end

local FEATURED_H = 44
local DISCORD_BLURPLE = { 0.345, 0.396, 0.949 }

function Widgets:SectionHeader(parent, opts)
	local h = Acquire("section", parent, CreateSection)
	h.opts = opts
	h:SetSize(opts.width or 300, SECTION_H)
	h:SetPoint("TOPLEFT", parent, "TOPLEFT", opts.x or 0, -((opts.y or 0) + SECTION_TOP))

	local featured = opts.featured
	h.label:ClearAllPoints(); h.rule:ClearAllPoints()
	if featured then
		-- the featured heading (D39 A): the settings page header's look, its own icon kept; the
		-- Discord one in Discord's blurple
		h:SetHeight(FEATURED_H)
		local path = type(featured) == "string" and featured or "Interface\\Icons\\ClassIcon_Shaman"
		h.icon:SetTexture(path)
		-- spell icons carry a dark frame to trim; our own art (transparent) is used whole
		if path:find("Interface\\Icons\\", 1, true) then h.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) else h.icon:SetTexCoord(0, 1, 0, 1) end
		h.icon:SetSize(32, 32)
		h.icon:ClearAllPoints(); h.icon:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", PAD, 4)
		h.icon:Show()
		h.label:SetPoint("LEFT", h.icon, "RIGHT", 10, 1)
		h.label:SetText(opts.label or "")
		h.rule:SetPoint("TOPLEFT", h, "BOTTOMLEFT", PAD, 0)
		h.rule:SetPoint("TOPRIGHT", h, "BOTTOMRIGHT", -PAD, 0)
		h.glow:ClearAllPoints()
		h.glow:SetPoint("TOPLEFT", h, "TOPLEFT", PAD, -2)
		h.glow:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", -PAD, 0)
		local discord = path:lower():find("discord", 1, true) ~= nil
		Core:PageBanner({ host = h, glow = h.glow, rule = h.rule, title = h.label, icon = h.icon, keepIcon = true,
			color = discord and DISCORD_BLURPLE or nil, element = "air", textX = PAD + 42 })
	else
		Core:PageBannerOff(h)
		h:SetHeight(SECTION_H)
		h.icon:Hide(); h.glow:Hide()
		h.label:SetFontObject(Core.fonts.section)
		h.label:SetTextColor(Core:Color(opts.color or "textDim"))   -- opts.color: a page's own heading color (Themes: accentHi)
		h.label:SetShadowOffset(0, 0)
		h.label:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", PAD, 2)
		h.label:SetText(strupper(opts.label or ""))
		h.rule:SetHeight(1)
		h.rule:SetPoint("BOTTOMLEFT", h.label, "BOTTOMRIGHT", 10, 3)
		h.rule:SetPoint("RIGHT", h, "RIGHT", -PAD, 0)
		h.rule:SetColorTexture(Core:Color("border", 0.6))
	end
	if opts.note then
		h.note:SetText(opts.note)
		h.note:Show()
	else
		h.note:SetText("")
		h.note:Hide()
	end

	self:TagSection(h, opts.label)
	return h, (featured and FEATURED_H + 6 or SECTION_H) + SECTION_TOP + SECTION_BOT
end

-- ---------------------------------------------------------------------------
-- Toggle: THE on / off switch (D32 design C2, ShamanPowerBrand's
-- SP:CreateTotemSwitch): a tiny totem box sliding on its own duration bar, in
-- the page's element. 38 x 18 like the pill it replaces; disabled = the knob
-- and fill at half brightness (the switch repaints itself on Enable / Disable).
-- ---------------------------------------------------------------------------
local function TogglePaint(row, state)
	row.track:SetChecked(state)
end

-- Without the brand file (an update the game has not seen yet: it needs a full
-- restart) the switch is the pre-3.0.6 pill, with the same methods.
local function PillPaint(b)
	b.spTex:SetColorTexture(Core:ColorIf(b.spChecked, "accent", "off"))
	b.spKnob:ClearAllPoints()
	if b.spChecked then b.spKnob:SetPoint("RIGHT", b, "RIGHT", -3, 0) else b.spKnob:SetPoint("LEFT", b, "LEFT", 3, 0) end
	local k = 1
	if not b.spEnabled then k = 0.5 end
	b.spKnob:SetVertexColor(k, k, k, 1)
end
local function PillSetChecked(b, on)
	if on then b.spChecked = true else b.spChecked = false end
	PillPaint(b)
end
local function PillGetChecked(b) return b.spChecked end
local function PillSetElement() end
local function PillOnEnable(b) b.spEnabled = true; PillPaint(b) end
local function PillOnDisable(b) b.spEnabled = false; PillPaint(b) end

local function NewSwitch(parent)
	local sp = ShamanPower
	if sp and sp.CreateTotemSwitch then return sp:CreateTotemSwitch(parent, { scale = 1 }) end
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(TOGGLE_W, 18)
	b.spTex = b:CreateTexture(nil, "BACKGROUND")
	b.spTex:SetAllPoints(b)
	Core:MakeBorder(b, "border")
	b.spKnob = b:CreateTexture(nil, "OVERLAY")
	b.spKnob:SetSize(12, 12)
	b.spKnob:SetColorTexture(0.95, 0.96, 0.98, 1)
	b.spChecked, b.spEnabled = false, true
	b.SetChecked, b.GetChecked, b.SetElement = PillSetChecked, PillGetChecked, PillSetElement
	b:HookScript("OnEnable", PillOnEnable)
	b:HookScript("OnDisable", PillOnDisable)
	PillPaint(b)
	return b
end

local function CreateToggle(parent)
	local row = CreateRow(parent)

	local track = NewSwitch(row)
	Core:ForwardTooltip(track, row)   -- the row's tooltip over the control too
	track:SetPoint("RIGHT", row, "RIGHT", -PAD, 0)

	row.track = track
	-- The switch is a mouse-enabled child: sliding onto it fires the row's
	-- OnLeave. Keep the row's hover hooks (a style preview) alive across it.
	track:HookScript("OnEnter", function() if row.spOnEnter then row:spOnEnter() end end)
	track:HookScript("OnLeave", function() if row.spOnLeave then row:spOnLeave() end end)

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
	row.track:SetElement(row._element or "spirit")
	return FinishRow(row, parent, TOGGLE_W)
end

-- ---------------------------------------------------------------------------
-- Slider with numeric readout
-- ---------------------------------------------------------------------------
local function SliderFormat(row, v)
	-- isPercent (AceConfig): the value is a 0-1 fraction, shown as a percentage
	if row.isPercent then return string.format("%d%%", math.floor(v * 100 + 0.5)) end
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
	Core:ForwardTooltip(box, row)   -- the row's tooltip over the control too
	box:SetSize(NUMBOX_W, 20)
	box:SetPoint("RIGHT", row, "RIGHT", -PAD, 0)
	box:SetAutoFocus(false)
	box:SetFontObject(Core.fonts.row)
	box:SetJustifyH("CENTER")
	box:SetTextInsets(2, 2, 0, 0)
	Core:SolidTex(box, "windowBg", "BACKGROUND")
	Core:MakeBorder(box, "border")

	local slider = CreateFrame("Slider", nil, row)
	Core:ForwardTooltip(slider, row)   -- the row's tooltip over the control too
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
	-- Widgets.sliderDragging: a slider thumb is held down. The live preview waits for the
	-- release before rebuilding (Window.lua PreviewChanged), so a drag stays smooth.
	slider:HookScript("OnMouseDown", function() Widgets.sliderDragging = true end)
	slider:HookScript("OnMouseUp", function()
		Widgets.sliderDragging = false
		local opts = row.opts
		if not opts or row._disabled then return end
		local pv = row._pendingV   -- the last value of the drag, not yet set
		if pv ~= nil then row._pendingV = nil; opts.set(pv) end
		if opts.onChanged then opts.onChanged() end   -- the page and preview, once, with the final value
	end)
	slider:HookScript("OnHide", function() Widgets.sliderDragging = false end)

	slider:SetScript("OnValueChanged", function(self, v)
		if row._applying then return end
		local opts = row.opts
		if not opts then return end
		box:SetText(SliderFormat(row, v))
		SliderPaintFill(row, v)
		if row._disabled then return end
		if Widgets.sliderDragging then
			-- Held down: running the setting and the whole page (every row, the sidebar,
			-- the live preview) on every frame of a drag dropped the game to a crawl. The
			-- value goes to the setting twenty times a second, the page and preview follow
			-- ten times a second, and the release applies the last value at once.
			row._pendingV = v
			if not row._setQueued then
				row._setQueued = true
				C_Timer.After(0.05, function()
					row._setQueued = false
					local pv = row._pendingV
					if row.opts == opts and pv ~= nil then row._pendingV = nil; opts.set(pv) end
				end)
			end
			if opts.onChanged and not row._changeQueued then
				row._changeQueued = true
				C_Timer.After(0.1, function()
					row._changeQueued = false
					if row.opts == opts and opts.onChanged then opts.onChanged() end
				end)
			end
			return
		end
		opts.set(v)
		if opts.onChanged then opts.onChanged() end
	end)

	box:SetScript("OnEnterPressed", function(self)
		local text = self:GetText() or ""
		local v = tonumber((text:gsub("%%", "")))
		if v and row.isPercent then
			-- "50" and "50%" mean 50%; a typed fraction like "0.5" is taken as one
			if not (v <= 1 and text:find(".", 1, true)) then v = v / 100 end
		end
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
		-- the fill in the page's element (accent outside the settings pages)
		if not enabled then
			fill:SetColorTexture(Core:Color("off"))
		elseif row._element then
			fill:SetColorTexture(ElementRGB(row._element))
		else
			fill:SetColorTexture(Core:Color("accent"))
		end
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
	-- Percent display: AceConfig pages say so explicitly (true/false). Sliders built
	-- by hand (the setup tour, module windows) do not; a fractional step on a
	-- 0-3 range is a scale or an opacity there, so it shows as 70% / 180% too.
	-- Seconds sliders (e.g. Duration 1-5) run past 3 and keep their decimals.
	if opts.isPercent ~= nil then
		row.isPercent = opts.isPercent and true or false   -- rows are pooled: always reset
	else
		row.isPercent = row.step < 1 and row.min >= 0 and row.max <= 3
	end

	-- Changing the range can clamp the current value and fire OnValueChanged;
	-- that must never reach the new opts.set.
	row._applying = true
	row.slider:SetMinMaxValues(row.min, row.max)
	-- a percentage drags in 1% steps whatever its option's step (5% was too coarse);
	-- the box beside it still takes any typed value
	row.slider:SetValueStep(row.isPercent and math.min(row.step, 0.01) or row.step)
	row._applying = false

	return FinishRow(row, parent, SLIDER_W + NUMBOX_W + 8)
end

-- ---------------------------------------------------------------------------
-- Dropdown
-- One shared popup is reused by every dropdown on screen.
-- The look (D33 "Lit menu", menus_glowup_mock.py list_menu_A): the settings
-- window's soft 1.5 px edge with a thin stripe of the four elements on top, 22 px
-- rows with the text 28 in, hover the plain row hover, the current choice lit
-- like the settings sidebar's open page (its element's light fading right, a 3 px
-- element bar, the tiny totem box). The element is the one of the page or window
-- it opens from (Widgets:MenuElement); logo blue outside any.
-- ---------------------------------------------------------------------------
local POPUP_EDGE, POPUP_STRIPE = 1.5, 2
local POPUP_TOP, POPUP_BOTTOM = 4, 2          -- the stripe + 2 above the first row, 2 under the last
local POPUP_BOX, POPUP_BOX_X, POPUP_TEXT_X = 10, 11, 28

local popup
function Widgets:HidePopup()
	if popup then popup:Hide() end
end

-- The element of the page or window a menu opens from: the first of the anchor
-- and its parents that names one (a settings row's _element, the settings
-- window's or the setup tour's _element, a Core:CreateDialog window's
-- spElement); nil when none does (the menu is then logo blue).
function Widgets:MenuElement(anchor)
	local f, depth = anchor, 0
	while f and depth < 24 do
		local el = f._element or f.spElement
		if type(el) == "string" then return el end
		if not f.GetParent then return nil end
		f = f:GetParent()
		depth = depth + 1
	end
	return nil
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
	-- the soft edge and the four elements along the top, over the rows
	local edge = CreateFrame("Frame", nil, popup)
	edge:SetAllPoints(popup)
	edge:SetFrameLevel(popup:GetFrameLevel() + 8)
	Core:MakeBorder(edge, "border", POPUP_EDGE)
	local sp = ShamanPower
	if sp and sp.CreateElementStripe then   -- (no brand file before a full restart: no stripe)
		local stripe = sp:CreateElementStripe(popup)
		stripe:SetStripeHeight(POPUP_STRIPE)
		stripe:SetPoint("TOPLEFT", popup, "TOPLEFT", 0, 0)
		stripe:SetPoint("TOPRIGHT", popup, "TOPRIGHT", 0, 0)
		stripe:SetFrameLevel(popup:GetFrameLevel() + 9)
	end

	popup.scroll = CreateFrame("ScrollFrame", nil, popup)
	popup.scroll:SetPoint("TOPLEFT", popup, "TOPLEFT", POPUP_EDGE, -POPUP_TOP)
	popup.scroll:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -POPUP_EDGE, POPUP_BOTTOM)
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
		if popup.onHoverEnd then popup.onHoverEnd() end
		popup.onHover, popup.onHoverEnd = nil, nil
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

-- the current choice's light: 28% of the element over rowHover, fading out to the
-- right (the settings sidebar's open page), its 3 px bar and its tiny totem box;
-- painted only when the pooled row's element changes
local function PaintPopupLit(b, key)
	if b._litKey == key then return end
	b._litKey = key
	local er, eg, eb = ElementRGB(key)
	local hr, hg, hb = Core:Color("rowHover")
	local lr, lg, lb = er * 0.28 + hr * 0.72, eg * 0.28 + hg * 0.72, eb * 0.28 + hb * 0.72
	Core:Gradient(b.lit, "HORIZONTAL", lr, lg, lb, 1, hr, hg, hb, 1)
	b.bar:SetColorTexture(er, eg, eb, 1)
	if b.box then b.box:SetElement(key) end
end

local function ShowPopup(anchorTo, items, currentValue, onPick, popts)
	local p = GetPopup()
	p.owner = anchorTo
	-- per-show hover callbacks (a style list previews the hovered style)
	p.onHover, p.onHoverEnd = popts and popts.onHover or nil, popts and popts.onHoverEnd or nil
	local element = (popts and popts.element) or Widgets:MenuElement(anchorTo) or "spirit"

	for _, b in ipairs(p.buttons) do b:Hide() end

	-- As wide as the longest name (in its own font on a font list, which can be
	-- wider than the row font), plus a texture list's swatch: a name never runs
	-- under the swatch or past the edge. Every list is measured, since a
	-- dropdown whose value wraps is narrower than its longest option.
	if not p.measure then p.measure = p:CreateFontString(nil, "OVERLAY"); p.measure:Hide() end
	local itemFontOf = popts and popts.itemFont
	local _, rowSize = Core.fonts.row:GetFont()
	local widest = 0
	for _, item in ipairs(items) do
		p.measure:SetFontObject(Core.fonts.row)
		local itemFont = itemFontOf and itemFontOf(item.key)
		if itemFont then
			p.measure:SetFont(itemFont, rowSize or 13, "")
			if not p.measure:GetFont() then p.measure:SetFontObject(Core.fonts.row) end
		end
		p.measure:SetText(item.text)
		widest = math.max(widest, (p.measure.GetUnboundedStringWidth and p.measure:GetUnboundedStringWidth()) or p.measure:GetStringWidth())
	end
	local width = math.max(anchorTo:GetWidth(), (popts and popts.width) or 140)
	if popts and popts.itemTexture then
		width = math.max(width, 280, POPUP_TEXT_X + widest + 12 + 70 + 8 + POPUP_EDGE)
	else
		width = math.max(width, POPUP_TEXT_X + widest + 8)   -- the dropdown button's own fit (+36): the list lines up with it
	end
	local rowW = width - 2 * POPUP_EDGE
	local y = 0
	for i, item in ipairs(items) do
		local b = p.buttons[i]
		if not b then
			b = CreateFrame("Button", nil, p.content)
			b.bg = b:CreateTexture(nil, "BACKGROUND")
			b.bg:SetAllPoints(b)
			b.lit = b:CreateTexture(nil, "BACKGROUND", nil, 1)
			b.lit:SetAllPoints(b)
			b.lit:SetColorTexture(1, 1, 1, 1)
			b.bar = b:CreateTexture(nil, "ARTWORK")
			b.bar:SetWidth(3)
			b.bar:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
			b.bar:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
			local sp = ShamanPower
			if sp and sp.CreateElementBox then   -- (no brand file before a full restart: no box)
				b.box = sp:CreateElementBox(b, POPUP_BOX)
				b.box:SetPoint("LEFT", b, "LEFT", POPUP_BOX_X - POPUP_EDGE, 0)
			end
			b.text = b:CreateFontString(nil, "OVERLAY")
			b.text:SetFontObject(Core.fonts.row)
			b.text:SetPoint("LEFT", b, "LEFT", POPUP_TEXT_X - POPUP_EDGE, 0)
			b.text:SetJustifyH("LEFT")
			-- hover: the plain row hover; the lit current choice stays as it is
			b:SetScript("OnEnter", function(self)
				if not self._selected then self.bg:SetColorTexture(Core:Color("rowHover")) end
				if p.onHover then p.onHover(self._key) end
			end)
			b:SetScript("OnLeave", function(self)
				self.bg:SetColorTexture(0, 0, 0, 0)
				if p.onHoverEnd then p.onHoverEnd() end
			end)
			-- Installed once; per-show data lives on the button.
			b:SetScript("OnClick", function(self)
				p:Hide()
				if self._onPick then self._onPick(self._key) end
			end)
			p.buttons[i] = b
		end
		b:SetSize(rowW, ITEM_H)
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", p.content, "TOPLEFT", 0, -y)
		-- a font list draws each name in its own font; pooled buttons go back to the row font
		local itemFont = popts and popts.itemFont and popts.itemFont(item.key)
		b.text:SetFontObject(Core.fonts.row)
		if itemFont then
			b.text:SetFont(itemFont, rowSize or 13, "")
			if not b.text:GetFont() then b.text:SetFontObject(Core.fonts.row) end
		end
		-- a texture list shows a swatch of each texture at the row's right edge
		local itemTexture = popts and popts.itemTexture and popts.itemTexture(item.key)
		if itemTexture then
			if not b.swatch then
				b.swatch = b:CreateTexture(nil, "ARTWORK")
				b.swatch:SetSize(70, 12)
				b.swatch:SetPoint("RIGHT", b, "RIGHT", -8, 0)
			end
			b.swatch:SetTexture(itemTexture)
			b.swatch:SetVertexColor(Core:Color("accentHi"))
			b.swatch:Show()
		elseif b.swatch then
			b.swatch:Hide()
		end
		b.text:SetText(item.text)
		b.text:SetTextColor(Core:Color("text"))
		b._key = item.key
		b._onPick = onPick
		b._selected = (item.key == currentValue)
		b.bg:SetColorTexture(0, 0, 0, 0)
		if b._selected then PaintPopupLit(b, element) end
		b.lit:SetShown(b._selected)
		b.bar:SetShown(b._selected)
		if b.box then b.box:SetShown(b._selected) end
		b:Show()
		y = y + ITEM_H
	end

	p.content:SetSize(rowW, math.max(y, 1))
	local h = math.min(POPUP_TOP + y + POPUP_BOTTOM, MAX_POPUP_H)
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

-- A SharedMedia picker (dialogControl LSM30_*) is fed the LSM list, which
-- is name -> file; the name is both the stored value and the label.
local function DropdownText(opts, values, k)
	if opts.keyIsLabel then return tostring(k) end
	return tostring(values[k])
end

local function DropdownItems(opts)
	local values = opts.values()
	local order  = opts.order and opts.order() or nil
	local items = {}
	if order then
		for _, k in ipairs(order) do
			if values[k] ~= nil then
				table.insert(items, { key = k, text = DropdownText(opts, values, k) })
			end
		end
	else
		local keys = {}
		for k in pairs(values) do table.insert(keys, k) end
		table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
		for _, k in ipairs(keys) do
			table.insert(items, { key = k, text = DropdownText(opts, values, k) })
		end
	end
	return items, values
end

local function DropdownPaint(row)
	local opts = row.opts
	if not opts then return end
	local _, values = DropdownItems(opts)
	local cur = opts.get()
	local label = values and cur ~= nil and values[cur] ~= nil and DropdownText(opts, values, cur) or nil
	local text = label and tostring(label) or "|cff8A94A6-|r"
	-- The button is sized to the longest option below. A value still too wide
	-- for it (very long localized strings) wraps; the button is already tall
	-- enough for that.
	row.txt:SetText(text)
end

-- Width that fits the longest option label, bounded so the row label keeps
-- at least DROPDOWN_LABEL_MIN of room. An option wider than that wraps inside
-- the button, so the height fits the tallest option once wrapped. Every option
-- is measured, not just the current one: a pick only refreshes the page, it
-- does not lay the rows out again, so the height must not depend on the value.
local DROPDOWN_LABEL_MIN = 96
local DROPDOWN_H = 22
local function DropdownFit(row, opts)
	local items = DropdownItems(opts)
	local measure = row.measure
	local widest = 0
	for _, item in ipairs(items) do
		measure:SetText(item.text)
		local w = measure:GetStringWidth()
		if w > widest then widest = w end
	end
	local want = math.ceil(widest) + 8 + 22 + 6      -- text pad + arrow zone + slack
	local maxW = row:GetWidth() - (PAD * 2) - DROPDOWN_LABEL_MIN
	if maxW < DROPDOWN_W then maxW = DROPDOWN_W end
	local w = math.max(DROPDOWN_W, math.min(want, maxW))

	local h = DROPDOWN_H
	local textW = w - 28                             -- txt spans LEFT +8 .. RIGHT -20
	if widest > textW then
		measure:SetWidth(textW)
		local tallest = 0
		for _, item in ipairs(items) do
			measure:SetText(item.text)
			local sh = measure:GetStringHeight()
			if sh > tallest then tallest = sh end
		end
		measure:SetWidth(0)
		h = math.max(DROPDOWN_H, math.ceil(tallest) + 8)
	end
	return w, h
end

local function CreateDropdown(parent)
	local row = CreateRow(parent)

	local btn = CreateFrame("Button", nil, row)
	btn:SetSize(DROPDOWN_W, DROPDOWN_H)
	btn:SetPoint("RIGHT", row, "RIGHT", -PAD, 0)
	Core:SolidTex(btn, "windowBg", "BACKGROUND")
	Core:MakeBorder(btn, "border")

	local txt = btn:CreateFontString(nil, "OVERLAY")
	txt:SetFontObject(Core.fonts.row)
	txt:SetPoint("LEFT", btn, "LEFT", 8, 0)
	txt:SetPoint("RIGHT", btn, "RIGHT", -20, 0)
	txt:SetJustifyH("LEFT")
	txt:SetWordWrap(true)
	txt:SetNonSpaceWrap(true)   -- a single long word (an LSM key) breaks, not cuts

	-- Off-screen string used only to measure option labels.
	local measure = btn:CreateFontString(nil, "OVERLAY")
	measure:SetFontObject(Core.fonts.row)
	measure:SetPoint("LEFT", btn, "LEFT", 0, 0)
	measure:SetNonSpaceWrap(true)   -- wraps like txt, so the height matches
	measure:Hide()
	row.measure = measure

	local arrow = btn:CreateFontString(nil, "OVERLAY")
	arrow:SetFontObject(Core.fonts.tiny)
	arrow:SetPoint("RIGHT", btn, "RIGHT", -7, 0)
	arrow:SetText("v")
	arrow:SetTextColor(Core:Color("textDim"))

	row.btn, row.txt = btn, txt

	-- Fit the button to the options and set the row's floor for a wrapped
	-- (taller) button. Runs on every acquire, and again from Widen when the
	-- page hands the row more room.
	row.spRefit = function()
		if not row.opts then return btn:GetWidth() end
		local w, h = DropdownFit(row, row.opts)
		btn:SetSize(w, h)
		row._controlWidth = w
		row._controlMinH = h + (ROW_H - DROPDOWN_H)
		return w
	end

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
		end, { onHover = opts.onHover, onHoverEnd = opts.onHoverEnd, itemFont = opts.itemFont, itemTexture = opts.itemTexture })
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
	-- the row's tooltip over the control too: hooked after the control's own
	-- OnEnter/OnLeave are set (SetScript would drop an earlier hook)
	Core:ForwardTooltip(btn, row)
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
	local w = row.spRefit()
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

		-- The picker calls back later; bind to the opts that opened it so
		-- a page re-render in between cannot redirect the commit.
		local function Commit(nr, ng, nb, na)
			if not opts.hasAlpha then na = 1 end
			opts.set(nr, ng, nb, na)
			if row.opts == opts then ColorPaint(row) end
			if opts.onChanged then opts.onChanged() end
		end

		-- ShamanPower's own color picker (ColorPicker.lua): live while picking;
		-- Cancel, the X and Escape commit the color it opened with, as before.
		-- Its alpha is the opacity itself (1 = solid) on every client.
		if ShamanPower and ShamanPower.OpenColorPicker then
			ShamanPower:OpenColorPicker({
				r = r, g = g, b = b, a = a,
				hasAlpha = opts.hasAlpha,
				title = opts.label,
				onChange = Commit,
			})
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
	-- the row's tooltip over the control too: hooked after the control's own
	-- OnEnter/OnLeave are set (SetScript would drop an earlier hook)
	Core:ForwardTooltip(btn, row)
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
local function FitButtonCaption(row)
	row.txt:SetWidth(math.max(1, row:GetWidth() - PAD * 2 - 16))
	local height = math.max(ROW_H, math.ceil(row.txt:GetStringHeight()) + 18)
	row._controlMinH = height
	row:SetHeight(height)
end

local function CreateButton(parent)
	local row = CreateRow(parent)

	local btn = CreateFrame("Button", nil, row)
	btn:SetPoint("TOPLEFT", row, "TOPLEFT", PAD, -3)
	btn:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -PAD, 3)

	local txt = btn:CreateFontString(nil, "OVERLAY")
	txt:SetFontObject(Core.fonts.button)
	txt:SetPoint("CENTER")
	txt:SetJustifyH("CENTER")
	txt:SetWordWrap(true)
	txt:SetNonSpaceWrap(true)
	Core:BevelButton(btn, false, txt)   -- the shared button look: blue bevel

	row.btn, row.btnBg, row.txt = btn, btn.bg, txt
	row.spRefit = function() FitButtonCaption(row) end

	btn:SetScript("OnClick", function()
		local opts = row.opts
		if not opts or row._disabled then return end
		opts.func()
		if opts.onChanged then opts.onChanged() end
	end)

	row.spSetControlEnabled = function(_, enabled)
		if enabled then btn:Enable() else btn:Disable() end
		txt:SetTextColor(Core:ColorIf(enabled, "white", "textMute"))
	end

	row.refresh = function()
		local opts = row.opts
		if not opts then return end
		if opts.disabled then ApplyDisabled(row, opts.disabled()) end
	end
	-- the row's tooltip over the control too: hooked after the control's own
	-- OnEnter/OnLeave are set (SetScript would drop an earlier hook)
	Core:ForwardTooltip(btn, row)
	return row
end

function Widgets:Button(parent, opts)
	local row = Acquire("button", parent, CreateButton)
	ConfigureRow(row, parent, opts)

	local txt = row.txt
	local caption = opts.buttonText or opts.label or ""
	row.btn.spTone = opts.tone   -- "help": the gold Support Code button (a pooled row resets it)
	row.btn.spPaint(false)   -- a pooled row may come back from another page mid-hover
	txt.spTruncated = false
	txt:SetText(caption)
	FitButtonCaption(row)

	-- The button fills the whole row card, so it reads as a real button rather
	-- than a small control in an empty box.

	-- The button carries its own caption, so the row label stays empty.
	-- (FinishRow's clamp runs against _fullLabel, so blank that too.)
	row._fullLabel = ""
	ApplyDisabled(row, false)
	row.label:SetText("")
	row._tagSrc = nil   -- (a button carries its caption: no label, so no tag)
	PaintRowTag(row)
	-- (through the fade list, so a Background Opacity change cannot paint it back)
	Core:SetFadeAlpha(row.spBg, 0)
	Core:SetBorderColor(row, "borderSoft", 0)
	row.spOnEnter, row.spOnLeave = nil, nil   -- no card hover behind the button
	RegisterRefresh(parent, row.refresh)
	row.refresh()
	return row, row:GetHeight() + RowGap(row)
end

-- ---------------------------------------------------------------------------
-- Text input
-- ---------------------------------------------------------------------------
local function CreateInput(parent)
	local row = CreateRow(parent)

	local box = CreateFrame("EditBox", nil, row)
	Core:ForwardTooltip(box, row)   -- the row's tooltip over the control too
	box:SetSize(DROPDOWN_W, 22)
	box:SetPoint("RIGHT", row, "RIGHT", -PAD, 0)
	box:SetAutoFocus(false)
	box:SetFontObject(Core.fonts.row)
	box:SetTextInsets(6, 6, 0, 0)
	Core:SolidTex(box, "windowBg", "BACKGROUND")
	Core:MakeBorder(box, "border")

	row.box = box

	box:SetScript("OnEditFocusGained", function() Core:SetBorderColor(box, "accent") end)
	-- Commit on focus loss too (typing a loadout name then clicking Create must
	-- not lose the name); Escape reverts first, so it still cancels.
	box:SetScript("OnEditFocusLost", function(self)
		Core:SetBorderColor(box, "border")
		local opts = row.opts
		if opts and not self._spReverting and self:GetText() ~= (opts.get() or "") then
			opts.set(self:GetText())
			if opts.onChanged then opts.onChanged() end
		end
	end)
	box:SetScript("OnEnterPressed", function(self)
		local opts = row.opts
		if not opts then self:ClearFocus() return end
		opts.set(self:GetText())
		self:ClearFocus()
		if opts.onChanged then opts.onChanged() end
	end)
	box:SetScript("OnEscapePressed", function(self)
		local opts = row.opts
		self._spReverting = true
		self:SetText(opts and opts.get() or "")
		self:ClearFocus()
		self._spReverting = nil
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

local inputMeasure
function Widgets:Input(parent, opts)
	local row = Acquire("input", parent, CreateInput)
	ConfigureRow(row, parent, opts)
	Core:SetBorderColor(row.box, "border")
	-- the box is wide enough for its whole value (a link, a long name): never a
	-- cut-off field. It grows up to about two thirds of the row.
	local w = DROPDOWN_W
	local ok, value = pcall(opts.get)
	if ok and value ~= nil and value ~= "" then
		inputMeasure = inputMeasure or UIParent:CreateFontString(nil, "OVERLAY")
		inputMeasure:SetFontObject(Core.fonts.row)
		inputMeasure:SetText(tostring(value))
		local need = math.ceil(inputMeasure:GetStringWidth()) + 24
		w = math.max(DROPDOWN_W, math.min(need, math.floor((opts.width or 300) * 0.66)))
	end
	row.box:SetWidth(w)
	return FinishRow(row, parent, w)
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

	-- in a section card the text gets room above and below, like a row's line
	local inCard = opts.inCard
	local top = 0
	if inCard then top = CARD_TEXT_PAD end
	local fs = f.text
	fs:ClearAllPoints()
	fs:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -top)
	fs:SetWidth(width - PAD * 2)
	fs:SetText(opts.text or "")

	-- GetStringHeight can under-report before the region is laid out, which
	-- lets the next row ride up over the text. Size the frame to the string,
	-- then let the fontstring drive the final height.
	f:SetSize(width, 18)
	local h = math.max(fs:GetStringHeight() + 10, 18)
	if inCard then h = math.max(fs:GetStringHeight() + top * 2, 18) end
	f:SetSize(width, h)

	self:TagRow(f, opts.text, nil, opts.section)
	if inCard then return f, h end
	return f, h + ROW_GAP
end

-- ---------------------------------------------------------------------------
-- Section card (D30 "one card per section", D32b "lit by the element"): one
-- card holds a section's rows (rowBg, a 1px borderSoft edge, both fading with
-- Background Opacity), headed by a 26px strip tinted toward the page's element
-- (mix(element, stripBg, 0.16)) with the element's tiny totem box and the
-- section's name in small caps (tinted 55% toward the element), and an optional
-- tag after the name. Window.lua's page packer puts the rows over it and asks
-- for the thin lines between them (Widgets:CardLine), then its height.
-- ---------------------------------------------------------------------------
local STRIP_H = 26
Widgets.STRIP_H = STRIP_H

local function CreateCard(parent)
	local c = CreateFrame("Frame", nil, parent)
	c.bg = c:CreateTexture(nil, "BACKGROUND")
	c.bg:SetAllPoints(c)
	Core:RegisterFade(c.bg, "rowBg", 1)
	Core:MakeBorder(c, "borderSoft")
	-- the strip is drawn over the card's edge along it, as in the mock
	c.strip = c:CreateTexture(nil, "ARTWORK", nil, -1)
	c.strip:SetPoint("TOPLEFT", c, "TOPLEFT", 0, 0)
	c.strip:SetPoint("TOPRIGHT", c, "TOPRIGHT", 0, 0)
	c.strip:SetHeight(STRIP_H)
	Core:RegisterFadeRGB(c.strip, Core:Color("stripBg"))
	if ShamanPower.CreateElementBox then
		c.box = ShamanPower:CreateElementBox(c, 10)
	else   -- updated without a restart: no brand file, so no element box
		c.box = CreateFrame("Frame", nil, c)
		c.box:SetSize(10, 10)
		c.box.SetElement = function() end
	end
	c.box:SetPoint("TOPLEFT", c, "TOPLEFT", 10, -8)
	c.label = c:CreateFontString(nil, "OVERLAY")
	c.label:SetFontObject(Core.fonts.strip)
	c.label:SetPoint("LEFT", c, "TOPLEFT", 26, -13)
	-- a tag after the name ("NEW"): gold small caps, as the sidebar's NEW tag
	c.tag = c:CreateFontString(nil, "OVERLAY")
	c.tag:SetFontObject(Core.fonts.strip)
	c.tag:SetTextColor(1, 0.82, 0)
	c.tag:SetPoint("LEFT", c.label, "RIGHT", 8, 0)
	c.lines = {}
	c.lineUsed = 0
	return c
end

-- opts = { x, y, width, label (nil: no strip), element (a SP.Brand element key), tag }
function Widgets:Card(parent, opts)
	local c = Acquire("card", parent, CreateCard)
	c.opts = opts
	c:SetFrameLevel(parent:GetFrameLevel())   -- under the rows placed over it
	c:SetPoint("TOPLEFT", parent, "TOPLEFT", opts.x or 0, -(opts.y or 0))
	c:SetSize(opts.width or 300, STRIP_H)
	c.lineUsed = 0
	local strip = opts.label ~= nil
	c.strip:SetShown(strip)
	c.box:SetShown(strip)
	c.label:SetShown(strip)
	c.tag:SetShown(strip and opts.tag ~= nil)
	if strip then
		local brand = ShamanPower.Brand
		local el = brand and (brand.elements[opts.element or "spirit"] or brand.elements.spirit) or { Core:Color("accentHi") }
		Core:SetFadeColor(c.strip, Core:Mix(el, "stripBg", 0.16))
		c.box:SetElement(opts.element or "spirit")
		c.label:SetText(strupper(opts.label))
		c.label:SetTextColor(Core:Mix(el, "text", 0.55))
		c.tag:SetText(opts.tag and strupper(opts.tag) or "")
	end
	return c
end

-- a thin line in the card (x, y from its top-left): the rows' separators
-- (borderSoft) and the column divider (border); pooled per card
function Widgets:CardLine(c, x, y, w, h, colorKey)
	c.lineUsed = c.lineUsed + 1
	local t = c.lines[c.lineUsed]
	if not t then
		t = c:CreateTexture(nil, "ARTWORK")
		c.lines[c.lineUsed] = t
	end
	t:ClearAllPoints()
	t:SetPoint("TOPLEFT", c, "TOPLEFT", x, -y)
	t:SetSize(w, h)
	t:SetColorTexture(Core:Color(colorKey))
	t:Show()
end

function Widgets:CardFinish(c, height)
	c:SetHeight(height)
	for i = c.lineUsed + 1, #c.lines do c.lines[i]:Hide() end
end

return Widgets
